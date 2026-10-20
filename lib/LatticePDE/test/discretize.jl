# The discretizer (v3 §4.5, §5, C6): BC parser, keys, linearity table, raw-`Differential`
# rule, maps and offset reads, and end-to-end oracles from a `PDESystem` through the C5 host
# runner (the Exec contract on the CPU). Each oracle has a negative control that must fail.
# The explicit step is the test's own `update` (C7a brings the steppers).

using LatticeFields: LatticeFields
using Random: MersenneTwister
include(joinpath(pkgdir(LatticeFields), "test", "host_runner.jl"))
using LatticeFields.IR: print_program, runtime, F16, F32, F64
using LatticeFields.Compile: semantic, fingerprint_text
using LatticeFields.Schedule: plan
using LatticePDE: BC

const euler = (kb, c, r) -> c + runtime(kb, 2) * r          # rt = (t, dt)
ir(cf) = sprint(print_program, cf.program)
dom2(a = 1.0, b = 1.0) = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, a), y ∈ Interval(0.0, b)]
pde(eqs, bcs, dvs, ps; d = dom2()) = PDESystem(eqs, bcs, d, [t, x, y], dvs, ps; name = :f)
lower64(sys, dims; kw...) = symbolic_discretize(sys, LatticeDiscretization(Grid(dims); T = Float64); update = euler, kw...)

"""Semantic program, step plan and host store of a lowered system (Float64)."""
function runner(cf)
    s = semantic(cf.program)
    sp = plan(s; options = CompileOptions(; T = Float64))
    return (s = s, sp = sp, st = HostStore(s), P = Tuple(cf.defaults))
end
field(R, key) = current(R.st, R.s, key)
function steps!(R, dt, n; P = R.P)
    for _ in 1:n
        run_step!(R.s, R.sp, R.st, P; rt = (0.0, dt))
    end
    return R
end
throws_with(f, s) = (try
                         f()
                         false
                     catch e
                         e isa ArgumentError && occursin(s, sprint(showerror, e))
                     end)

@parameters x y z Dc = 1e-3 k = 0.1 h0 = 2.0 g0 = 0.5 K0 = 2.0 cT = 0.1 dx [lattice_spacing = 1] dy [lattice_spacing = 2]
@parameters Dk[1:3] = [1.0, 2.0, 3.0]
@variables c(..) o(..) K(..) N(..) kindₛ(..)::Int32 [input = true] vel(..)[1:2] [input = true] u(..)[1:2]
Dx, Dy = Differential(x), Differential(y)
ce, oe, Ke, Ne, ke, ue = c(t, x, y), o(t, x, y), K(t, x, y), N(t, x, y), kindₛ(t, x, y), u(t, x, y)

@testset "BC parser (S-5)" begin
    fields = Dict{Any, Bool}(operation(unwrap(v)) => MTKB.isinput(unwrap(v)) for v in (ce, ke, ue))
    ivs = unwrap.([t, x, y])
    ends = [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
    one(bc) = only(LatticePDE.parse_bcs([bc], fields, ivs, ends))
    cases = [(c(0, x, y) ~ 0.0, :initial, 0, 0, 0), (c(t, 0, y) ~ 1.0, :dirichlet, 1, -1, 0),
        (c(t, 1.0, y) ~ g0, :dirichlet, 1, 1, 0), (Dx(c(t, 1, y)) ~ 0.0, :neumann, 1, 1, 0),
        (h0 * c(t, x, 0) + Dy(c(t, x, 0)) ~ g0, :robin, 2, -1, 0), (c(t, x, 0) ~ c(t, x, 1), :periodic, 2, 0, 0),
        (ce ~ masked(ke == 3, 0.0), :masked, 0, 0, 0), (ce ~ masked(ismember(ke, (2, 3)), 1.0), :masked, 0, 0, 0),
        (u(t, 0, y)[1] ~ 0.0, :dirichlet, 1, -1, 1), (ue[2] ~ masked(ke == 3, 0.0), :masked, 0, 0, 2),
        (Dx(u(t, 1, y)[2]) ~ 0.0, :neumann, 1, 1, 2)]
    for (bc, kind, axis, side, comp) in cases
        b = one(bc)
        @test (b.kind, b.axis, b.side, b.comp) == (kind, axis, side, comp)
        @test !isequal(b.op, operation(unwrap(ke)))              # never misrouted to the input
    end
    r = one(h0 * c(t, x, 0) + Dy(c(t, x, 0)) ~ g0)
    @test isequal(r.alpha, unwrap(h0)) && isequal(r.beta, 1) && isequal(r.value, unwrap(g0))
    # refusals, each with its message
    for (bc, msg) in [(c(t, 0.5, y) ~ 1.0, "not on a face"), (kindₛ(t, 0, y) ~ 1, "input"),
        (c(t, 0, y) + u(t, 0, y)[1] ~ 0.0, "mixes fields"), (c(t, x, 0) ~ c(t, 0, 0), "periodic pair"),
        (c(t, x, 0) ~ c(t, x, 0), "periodic pair"), (u(t, 0, y) ~ [0.0, 0.0], "per component"),
        (Dy(c(t, 1, y)) ~ 0.0, "along the pinned"), (c(t, 0, 0) ~ 1.0, "exactly one"),
        (kindₛ(t, x, y) ~ masked(ke == 3, 1), "input")]
        @test throws_with(() -> one(bc), msg)
    end
end

@testset "keys by operation, refusals, wrong bcs" begin
    eq = [D(ce) ~ Dc * Δ(ce)]
    sys = pde(eq, [c(t, x, 0) ~ c(t, x, 1)], [ce], [Dc])
    g = Grid((4, 4))
    base = ir(symbolic_discretize(sys, LatticeDiscretization(g)))
    for key in (c, ce, unwrap(ce))                  # the callable, the applied term, unwrapped
        @test ir(symbolic_discretize(sys, LatticeDiscretization(g; methods = Dict(key => FiniteVolume())))) == base
    end
    @test throws_with(() -> symbolic_discretize(sys, LatticeDiscretization(g; methods = Dict(o => FiniteVolume()))), "matches no")
    @test throws_with(() -> symbolic_discretize(sys, LatticeDiscretization(g; methods = Dict(c => :fem))), "FiniteVolume")
    @test throws_with(() -> symbolic_discretize(sys, LatticeDiscretization(Grid((4, 4, 4)))), "3 axes")
    @test throws_with(() -> symbolic_discretize(pde(eq, Equation[], [ce], [Dc => 1e-3]), LatticeDiscretization(g)), "`Pair`")
    @test throws_with(() -> symbolic_discretize(pde([eq; D(ce) ~ ce], Equation[], [ce], [Dc]), LatticeDiscretization(g)), "two equations")
    @test throws_with(() -> symbolic_discretize(pde(eq, Equation[], [ce, oe], [Dc]), LatticeDiscretization(g)), "no equation")
    @test throws_with(() -> symbolic_discretize(pde([eq; D(ke) ~ 1], Equation[], [ce, ke], [Dc]), LatticeDiscretization(g)), "input is set by the CPM")
    # wrong bcs are detected: a face of a periodic axis; periodicity for one field only
    @test throws_with(() -> symbolic_discretize(pde(eq, [c(t, x, 0) ~ c(t, x, 1), c(t, x, 0) ~ 1.0], [ce], [Dc]),
                                       LatticeDiscretization(g)), "periodic pair makes periodic")
    two = pde([eq; D(oe) ~ Δ(oe)], [c(t, x, 0) ~ c(t, x, 1)], [ce, oe], [Dc])
    @test throws_with(() -> symbolic_discretize(two, LatticeDiscretization(g)), "periodicity is per axis")
    # the vocabulary scans run first
    @test_throws ArgumentError symbolic_discretize(pde([D(ce) ~ Pre(ce)], Equation[], [ce], [Dc]), LatticeDiscretization(g))
    # spellings with no lattice meaning
    for (rhs, msg) in [Dx(ce) => "flux form", Dx(Dx(ce) * Dy(ce)) => "flux form", at(ce, ke) => "array parameter",
        ce^cT => "", Symbolics.Num(unwrap(z)) => "not a declared"]
        f = () -> symbolic_discretize(pde([D(ce) ~ rhs], Equation[], [ce, ke], [Dc, cT]), LatticeDiscretization(g))
        msg == "" ? (@test f() isa CompiledField) : (@test throws_with(f, msg))
    end
end

@testset "linearity table" begin
    states = [operation(unwrap(v)) for v in (ce, oe, Ke)]
    table = [Dc * Δ(ce) - k * ce => Set([:Diffusion, :LinearLocal]),
        DivKGrad(:harmonic)(at(Dk, ke), ce) - at(Dk, ke) * ce => Set([:Diffusion, :LinearLocal]),
        Advect(Upwind1())(vel(t, x, y), ce) + cT * ismember(ke, (2,)) => Set([:Advection, :Source]),
        ce * Δ(ce) => Set([:Other]), DivKGrad(:harmonic)(ce, ce) => Set([:Other]),
        -k * max(ce - cT, 0) * ismember(ke, (2,)) => Set([:LaggedSwitch]),
        k * ifelse(cT > ce, cT - ce, 0) => Set([:LaggedSwitch]), k * ifelse(oe > ce, oe - ce, 0) => Set([:Other]),
        Dc * Δ(ce) + k * oe => Set([:Diffusion, :CrossLinear]), ce^2 => Set([:Other]), ce * oe^2 => Set([:Other]), at(Dk, ke) * ce => Set([:LinearLocal]),
        Dx(Dx(ce)) + Dy(Dy(ce)) => Set([:Diffusion]), Dx(Ke * Dx(ce)) => Set([:Other]), Dx(K0 * Dx(ce)) => Set([:Diffusion]),
        Dx(ce * Dx(ce)) => Set([:Other]), Dc * Δ(oe) => Set([:CrossLinear]), oe * Ke => Set([:Other])]
    inputs = [operation(unwrap(ke))]
    for (rhs, want) in table, form in (identity, simplify, Symbolics.expand)
        @test Set(last.(LatticePDE.linearity(form(rhs), ce, states; inputs))) == want
    end
    # the conservative rule (review): a coefficient that reads an unknown field makes the term
    # Other, and a diffusion multiplier reads no field at all
    for (rhs, want) in [DivKGrad(:harmonic)(Ke, ce) => :Other,    # K ~ c^2 would make it nonlinear
        Ke * ce => :Other, ce * oe => :Other, oe * Δ(ce) => :Other,
        ifelse(ke == 2, Δ(ce), 0) => :Other, Dc * Δ(ce) => :Diffusion, ismember(ke, (2,)) * ce => :LinearLocal,
        # a multiplier that reads inputs through table reads and indicators only varies by
        # site and is bounded (F2 record (g)); one that reads an input directly is Other
        at(Dk, ke) * Δ(ce) => :SiteDiffusion, ismember(ke, (2,)) * Δ(ce) => :SiteDiffusion,
        (at(Dk, ke) - at(Dk, ke + 1) + 2) * Δ(ce) => :SiteDiffusion,
        (1 / at(Dk, ke)) * DivKGrad(:arithmetic)(at(Dk, ke), ce) => :SiteDiffusion,
        ifelse(ke == 2, Dc, 2Dc) * Δ(ce) => :SiteDiffusion, ke * Δ(ce) => :Other, (ke + at(Dk, ke)) * Δ(ce) => :Other]
        @test only(last.(LatticePDE.linearity(rhs, ce, states; inputs))) == want
    end
    # the system table uses the same rule: an aux coefficient that depends on c
    cf = symbolic_discretize(pde([D(ce) ~ DivKGrad(:harmonic)(Ke, ce) + Ke * ce, Ke ~ ce^2], Equation[], [ce, Ke], Num[]),
                    LatticeDiscretization(Grid((4, 4))))
    @test Set(last.(cf.linearity["c"])) == Set([:Other])
    # Symbolics' own expansion is blind to the registered operators (FR-27): the reason for the table
    @test !Symbolics.linear_expansion(Dc * Δ(ce) - k * ce, ce)[3]
end

@testset "raw Differential rule: same IR as Δ and DivKGrad" begin
    g = Grid((5, 4))
    bc = [c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) + Dx(c(t, 1, y)) ~ g0, c(t, x, 0) ~ c(t, x, 1)]
    aux = [Ke ~ K0 + x]
    low(rhs; e = Equation[]) = ir(symbolic_discretize(pde([D(ce) ~ rhs; e], bc, isempty(e) ? [ce] : [ce, Ke], [Dc, h0, g0, K0]),
                                             LatticeDiscretization(g)))
    @test low(Dc * (Dx(Dx(ce)) + Dy(Dy(ce)))) == low(Dc * Δ(ce))
    @test low(Dx(Ke * Dx(ce)) + Dy(Ke * Dy(ce)); e = aux) == low(DivKGrad(:harmonic)(Ke, ce); e = aux)
    # negative controls: an axis missing, the arithmetic face mean, a doubled axis
    @test low(Dc * Dx(Dx(ce))) != low(Dc * Δ(ce))
    @test low(DivKGrad(:arithmetic)(Ke, ce); e = aux) != low(DivKGrad(:harmonic)(Ke, ce); e = aux)
    @test low(Dc * (Dx(Dx(ce)) + Dx(Dx(ce)))) != low(Dc * Δ(ce))
end

# a 2D rate system with periodic y (a 1D profile in x, 2 rows)
function profile(bcs, n; rhs = Δ(ce), ps = [g0, h0], steps = 20000)
    cf = lower64(pde([D(ce) ~ rhs], [bcs; c(t, x, 0) ~ c(t, x, 1)], [ce], ps), (n, 2))
    R = runner(cf)
    steps!(R, 0.2 / n^2, steps)
    xc = ((1:n) .- 0.5) ./ n
    return reshape(field(R, "c"), n, 2)[:, 1], xc
end

@testset "steady linear profiles: Dirichlet, Robin, Neumann" begin
    n = 16
    v, xc = profile([c(t, 0, y) ~ 1.0, c(t, 1, y) ~ 0.0], n)
    @test maximum(abs, v .- (1 .- xc)) < 1e-9                  # cell-centered FV is exact on lines
    v, _ = profile([c(t, 0, y) ~ 1.0, c(t, 1, y) ~ g0], n)
    @test maximum(abs, v .- (1 .+ (0.5 - 1) .* xc)) < 1e-9     # parameter value at the face
    # Robin α c + β ∂c/∂x = g at x = 1: h0 c + c′ = g0 → c = 1 − a x, a = (h0 − g0)/(1 + h0)
    v, _ = profile([c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) + Dx(c(t, 1, y)) ~ g0], n)
    a = (2.0 - 0.5) / 3.0
    @test maximum(abs, v .- (1 .- a .* xc)) < 1e-9
    # Robin at the low face (outward normal −x): c′(0) − h0 c(0)... here −c′ + c = 0, c(1) = 1 → c = (1 + x)/2
    v, _ = profile([c(t, 0, y) - Dx(c(t, 0, y)) ~ 0.0, c(t, 1, y) ~ 1.0], n)
    @test maximum(abs, v .- (1 .+ xc) ./ 2) < 1e-9
    v, _ = profile([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ -g0], n)   # prescribed flux: c = 1 − g0 x
    @test maximum(abs, v .- (1 .- 0.5 .* xc)) < 1e-9
    v, _ = profile([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0], n; steps = 12000)
    @test maximum(abs, v .- 1) < 1e-6                           # no flux: flat at the Dirichlet value
    # negative control: the sign of the normal at the high face flipped (h0 c − c′ = g0) misses the oracle
    v, _ = profile([c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) - Dx(c(t, 1, y)) ~ g0], n)
    @test maximum(abs, v .- (1 .- a .* xc)) > 1e-2
end

@testset "Fourier mode decay (periodic 2D)" begin
    n, m, kx, ky = 16, 8, 1, 2
    d = dom2(1.0, 2.0)
    mk(rhs) = lower64(pde([D(ce) ~ rhs], [c(t, x, 0) ~ c(t, x, 1)...], [ce], [Dc]; d), (n, m))
    sys(rhs) = pde([D(ce) ~ rhs], [c(t, 0, y) ~ c(t, 1, y), c(t, x, 0) ~ c(t, x, 2)], [ce], [Dc]; d = d)
    hx, hy = 1 / n, 2 / m
    xc, yc = ((1:n) .- 0.5) .* hx, ((1:m) .- 0.5) .* hy
    mode = [cos(2π * kx * a) * cos(2π * ky * b / 2) for a in xc, b in yc]
    λ = -4 / hx^2 * sin(π * kx * hx)^2 - 4 / hy^2 * sin(π * ky * hy / 2)^2
    dt, nsteps, D_ = 0.2 * hx^2 / 1e-3, 50, 1e-3
    function run(rhs)
        R = runner(lower64(sys(rhs), (n, m)))
        copyto!(field(R, "c"), vec(mode))
        steps!(R, dt, nsteps)
        return reshape(field(R, "c"), n, m)
    end
    oracle = (1 + dt * D_ * λ)^nsteps .* mode                 # the discrete eigenvector, exactly
    @test maximum(abs, run(Dc * Δ(ce)) .- oracle) < 1e-12
    @test maximum(abs, run(Dc * (Dx(Dx(ce)) + Dy(Dy(ce)))) .- oracle) < 1e-12
    T = dt * nsteps                                             # and the continuum rate, to O(h²)
    @test maximum(abs, oracle .- exp(-D_ * 4π^2 * (kx^2 + (ky / 2)^2) * T) .* mode) < 0.02
    @test maximum(abs, run(-Dc * Δ(ce)) .- oracle) > 0.1        # negative control: flipped sign
    @test maximum(abs, run(Dc * Dx(Dx(ce)) + Dc * Dx(Dx(ce))) .- oracle) > 1e-4   # an axis wrong
end

@testset "no-flux mass conservation" begin
    n, m = 12, 9
    mk(bcs) = lower64(pde([D(ce) ~ Dc * Δ(ce) + Dc * Dx(Dx(ce))], bcs, [ce], [Dc]), (n, m))
    function mass(bcs)
        R = runner(mk(bcs))
        u0 = rand(MersenneTwister(3), n * m)
        copyto!(field(R, "c"), u0)
        steps!(R, 0.1 / n^2 / 1e-3, 100)
        return abs(sum(field(R, "c")) - sum(u0)), sum(u0)
    end
    dm, m0 = mass(Equation[])                                   # every face defaults to no flux
    @test dm <= 64 * eps() * n * m * m0
    dm, _ = mass([Dx(c(t, 0, y)) ~ 0.0, Dx(c(t, 1, y)) ~ 0.0, Dy(c(t, x, 0)) ~ 0.0])
    @test dm <= 64 * eps() * n * m * m0
    dm, _ = mass([c(t, 0, y) ~ 0.0])                            # negative control: one face Dirichlet(0)
    @test dm > 1e-3
end

@testset "masked interior Dirichlet" begin
    n, j = 16, 12                                               # mask column j holds 1
    sys(bcs) = pde([D(ce) ~ Δ(ce)], [bcs; c(t, 0, y) ~ 0.0; c(t, x, 0) ~ c(t, x, 1)], [ce, ke], Num[])
    function solve(bcs)
        cf = lower64(sys(bcs), (n, 2))
        R = runner(cf)
        kind = reshape(field(R, "kindₛ"), n, 2)
        kind[j, :] .= 3
        steps!(R, 0.2 / n^2, 8000)
        return reshape(field(R, "c"), n, 2)[:, 1], cf
    end
    v, cf = solve([ce ~ masked(ismember(ke, (2, 3)), 1.0)])
    xc = ((1:n) .- 0.5) ./ n
    want = [i <= j ? xc[i] / xc[j] : 1.0 for i in 1:n]          # linear up to the mask, flat beyond
    @test maximum(abs, v .- want) < 1e-8
    @test occursin("rule node_value c mask=mask:c value=1.0", ir(cf))
    @test occursin("kernel mask:c", ir(cf))
    v, _ = solve(Equation[])                                    # negative control: no mask
    @test maximum(abs, v .- want) > 0.5
end

@testset "3D: periodic x, no-flux y, Dirichlet z (one step against a loop)" begin
    @parameters g1 = 0.25
    dims = (6, 5, 4)
    d3 = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 3.0), y ∈ Interval(0.0, 1.0), z ∈ Interval(0.0, 2.0)]
    e = c(t, x, y, z)
    function step(zbcs)
        sys = PDESystem([D(e) ~ Dc * Δ(e)], [c(t, 0, y, z) ~ c(t, 3, y, z); zbcs], d3, [t, x, y, z], [e], [Dc, g1]; name = :f)
        R = runner(lower64(sys, dims))
        u0 = rand(MersenneTwister(1), prod(dims))
        copyto!(field(R, "c"), u0)
        steps!(R, 0.7, 1)
        return reshape(field(R, "c"), dims), reshape(u0, dims)
    end
    got, u = step([c(t, x, y, 0) ~ g1, c(t, x, y, 2) ~ 2.0])
    h = (0.5, 0.2, 0.5)
    want = similar(u)
    for l in 1:4, jj in 1:5, i in 1:6
        cc = u[i, jj, l]
        lap = (u[mod1(i + 1, 6), jj, l] + u[mod1(i - 1, 6), jj, l] - 2cc) / h[1]^2 +
              ((jj < 5 ? u[i, jj + 1, l] : cc) + (jj > 1 ? u[i, jj - 1, l] : cc) - 2cc) / h[2]^2 +
              ((l < 4 ? u[i, jj, l + 1] : 2 * 2.0 - cc) + (l > 1 ? u[i, jj, l - 1] : 2 * 0.25 - cc) - 2cc) / h[3]^2
        want[i, jj, l] = cc + 0.7 * 1e-3 * lap
    end
    @test maximum(abs, got .- want) < 1e-14
    bad, _ = step(Equation[])                                   # negative control: z no-flux instead
    @test maximum(abs, bad .- want) > 1e-5
end

@testset "kind table source at(Dk, kindₛ)" begin
    cf = lower64(pde([D(ce) ~ at(Dk, ke)], Equation[], [ce, ke], [Dk]), (4, 2))
    @test cf.tables == ["Dk" => [1.0, 2.0, 3.0]]
    R = runner(cf)
    R.st.tables[Int32(1)] = [1.0, 2.0, 3.0]
    copyto!(field(R, "kindₛ"), Int32[0, 1, 2, 3, 3, 2, 1, 0])
    steps!(R, 1.0, 1)
    @test field(R, "c") == [0.0, 1.0, 2.0, 3.0, 3.0, 2.0, 1.0, 0.0]    # kind 0 reads 0
end

@testset "upwind advection: exact shift at CFL 1" begin
    n = 8
    sys = pde([D(ce) ~ -Advect(Upwind1())(vel(t, x, y), ce)], [c(t, 0, y) ~ c(t, 1, y), c(t, x, 0) ~ c(t, x, 1)],
              [ce, vel(t, x, y)], Num[])
    R = runner(lower64(sys, (n, 2)))
    v = field(R, "vel[1]")
    v .= 1.0
    u0 = rand(MersenneTwister(2), 2n)
    copyto!(field(R, "c"), u0)
    steps!(R, 1 / n, 3)
    @test reshape(field(R, "c"), n, 2) ≈ circshift(reshape(u0, n, 2), (3, 0)) atol = 1e-14
end

@testset "masked averaging map (Shift and offset reads)" begin
    n, Iset = 5, (1,)
    offs = ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
    rd(a, b) = N(t, x + a * dx, y + b * dy)
    mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), Iset) for (a, b) in offs]
    rhs = ifelse(sum(mem) > 0, Dc * sum(m * rd(a, b) for (m, (a, b)) in zip(mem, offs)) / sum(mem), Ne)
    per = [N(t, 0, y) ~ N(t, 1, y), N(t, x, 0) ~ N(t, x, 1)]
    sys(r; e = [Shift(t, 1)(Ne) ~ r]) = pde(e, per, [Ne, ke], [Dc, dx, dy])
    cf = symbolic_discretize(sys(rhs), LatticeDiscretization(Grid((n, n)); T = Float64))
    @test cf.defaults == [1e-3, 0.2, 0.2]                       # spacing parameters valued from the grid
    @test occursin("kernel map:N", ir(cf))
    kind = fill(Int32(1), n, n)
    kind[3, 3] = 2
    kind[2, 4] = 2
    N0 = Rational{BigInt}[(i^2 * j + 1) // 7 for i in 1:n, j in 1:n]
    function direct(N0, Dv; periodic = true)                    # N ← (D/|I|) Σ_{j∈I} N_j, exact
        out = copy(N0)
        wrap(i) = periodic ? mod1(i, n) : i
        inI(p) = all(v -> 1 <= v <= n, p) && kind[p...] in Iset  # closed: outside sites are not in I
        for i in 1:n, j in 1:n
            I = [p for p in ((wrap(i + a), wrap(j + b)) for (a, b) in offs) if inI(p)]
            isempty(I) || (out[i, j] = Dv * sum(N0[p...] for p in I) // length(I))
        end
        return out
    end
    function apply(cf, P)
        R = runner(cf)
        copyto!(field(R, "N"), Float64.(vec(N0)))
        copyto!(field(R, "kindₛ"), vec(kind))
        steps!(R, 0.0, 1; P)
        return reshape(field(R, "N"), n, n)
    end
    want = direct(N0, 1 // 1)
    got = apply(cf, (1.0, 0.2, 0.2))
    @test maximum(abs, got .- Float64.(want)) < 1e-13
    @test abs((sum(got) - sum(Float64.(N0))) - Float64(sum(want) - sum(N0))) < 1e-12   # the mass change
    @test sum(want) != sum(N0)                                  # the map is not conservative
    # a closed lattice: offset reads outside the box read 0 (kind 0 is not in I)
    closed = symbolic_discretize(pde([Shift(t, 1)(Ne) ~ rhs], Equation[], [Ne, ke], [Dc, dx, dy]),
                        LatticeDiscretization(Grid((n, n)); T = Float64))
    want_c = direct(N0, 1 // 1; periodic = false)
    got_c = apply(closed, (1.0, 0.2, 0.2))
    @test maximum(abs, got_c .- Float64.(want_c)) < 1e-13
    @test abs((sum(got_c) - sum(Float64.(N0))) - Float64(sum(want_c) - sum(N0))) < 1e-12
    @test maximum(abs, got_c .- Float64.(want)) > 1e-3          # the two lattices differ at the edges
    # negative control: a flux-form rate step of the same field misses the exact map
    flux = symbolic_discretize(pde([D(Ne) ~ Δ(Ne)], per, [Ne], Num[]),
                      LatticeDiscretization(Grid((n, n)); T = Float64); update = euler)
    R = runner(flux)
    copyto!(field(R, "N"), Float64.(vec(N0)))
    steps!(R, 0.01, 1)
    @test maximum(abs, reshape(field(R, "N"), n, n) .- Float64.(want)) > 1e-3
    # refusals: only Shift(t, 1) maps; offset reads only in maps and with integer offsets
    g = LatticeDiscretization(Grid((n, n)))
    for (e, msg) in [[Shift(t, -1)(Ne) ~ rhs] => "Shift(t, 1)", [Shift(t, 2)(Ne) ~ rhs] => "Shift(t, 1)",
        [MTKB.Hold()(Ne) ~ rhs] => "not supported", [MTKB.Sample(1.0)(Ne) ~ rhs] => "not supported",
        [Shift(t, 1)(Ne) ~ MTKB.Hold()(Ne)] => "not supported", [D(Ne) ~ rd(1, 0) - Ne] => "only in map equations",
        [Shift(t, 1)(Ne) ~ N(t, x + dx / 2, y)] => "integer literal", [Shift(t, 1)(Ne) ~ N(t, x + Dc, y)] => "lattice_spacing",
        [Shift(t, 1)(Ne) ~ N(t, x + dy, y)] => "lattice_spacing = 1", [N(ShiftIndex(t, 1) + 1) ~ rhs] => "ShiftIndex"]
        @test throws_with(() -> symbolic_discretize(sys(rhs; e), g), msg)
    end
end

# Salted operator hashes: another package build's hashes, in this process (the D-107 pattern
# of `p6_0ah_canonical_term_order.jl`, extended to field terms). Inert at salt 0.
const SALT = Ref{UInt}(0)
for f in (Δ, at, ismember, sin, cos, exp)
    @eval function Base.hash(g::typeof($f), h::UInt)
        SALT[] == 0 && return invoke(hash, Tuple{Function, UInt}, g, h)
        return hash(SALT[], hash(:lattice_salt, h))
    end
end
function salted(f, s)
    SALT[] = s
    try
        return f()
    finally
        SALT[] = 0
    end
end

@testset "D-107: lowered IR independent of operator hashes" begin
    function build()
        rhs = Dc * Δ(ce) - k * ce + K0 * sin(ce) + cT * exp(-oe) + g0 * cos(oe) + h0 * ismember(ke, (2, 3)) +
              DivKGrad(:harmonic)(Ke, ce) + k * Dx(Dx(ce)) + max(ce - cT, 0) * ismember(ke, (1,)) +
              at(Dk, ke) * Δ(oe)
        sys = pde([D(ce) ~ rhs, D(oe) ~ Δ(oe) + ce * oe + sin(ce) + cos(oe), Ke ~ K0 + exp(ce)],
                  Equation[], [ce, oe, Ke, ke], [Dc, k, K0, cT, g0, h0, Dk])
        return ir(symbolic_discretize(sys, LatticeDiscretization(Grid((4, 3)))))
    end
    order() = string.(arguments(unwrap(Dc * Δ(ce) + K0 * Δ(oe) + h0 * ismember(ke, (2,)) + k * sin(ce) +
                                       cT * exp(oe) + g0 * cos(ce) + Δ(Ke))))
    base, base_order = build(), order()
    @test all(s -> salted(build, s) == base, 1:4)
    @test build() == base                                       # and over repeated builds
    # negative control: the salt does reorder Symbolics' operands of a sum
    @test any(s -> salted(order, s) != base_order, 1:4)
end

# ---- added after the first C6 review round ------------------------------------------------

@testset "masked averaging map: Moore neighborhood, empty sites only (pass-2 t4 oracle)" begin
    # [N(l_i)] ← (D/|I_i|) Σ_{j∈I_i} [N(l_j)], I_i = empty sites of Moore(i) ∪ {i}; empty sites
    # update synchronously, cell sites keep their value. Empty is kind 1, the cell kind 2.
    n = 5
    offs = [(a, b) for a in -1:1 for b in -1:1]
    mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), (1,)) for (a, b) in offs]
    rhs = ifelse(ismember(ke, (1,)),
                 Dc * sum(m * N(t, x + a * dx, y + b * dy) for (m, (a, b)) in zip(mem, offs)) / sum(mem), Ne)
    per = [N(t, 0, y) ~ N(t, 1, y), N(t, x, 0) ~ N(t, x, 1)]
    function exact(N, empty, D, periodic)                       # the pass-2 t4 `step`, Rational
        out = copy(N)
        for i in 1:n, j in 1:n
            empty[i, j] || continue
            I = Tuple{Int, Int}[]
            for a in -1:1, b in -1:1
                ii, jj = i + a, j + b
                if periodic
                    ii, jj = mod1(ii, n), mod1(jj, n)
                elseif !(1 <= ii <= n && 1 <= jj <= n)
                    continue
                end
                empty[ii, jj] && push!(I, (ii, jj))
            end
            out[i, j] = D // length(I) * sum(N[p...] for p in I)
        end
        return out
    end
    # (closed or periodic, cell, D, pinned mass change over empty sites from t4.out)
    cases = [(false, true, 1 // 1, 1069 // 840), (false, false, 1 // 1, 35 // 36), (true, false, 1 // 1, 0 // 1),
        (true, true, 1 // 1, 13 // 56), (true, false, 9 // 10, -39 // 5)]
    for (periodic, cell, Dv, pinned) in cases
        empty = trues(n, n)
        N0 = Rational{Int}[(i + 2j) % 7 for i in 1:n, j in 1:n]
        cell && (empty[2:3, 2:3] .= false; N0[2:3, 2:3] .= 0)
        want = exact(N0, empty, Dv, periodic)
        @test sum(want[empty]) - sum(N0[empty]) == pinned       # the port reproduces t4
        cf = symbolic_discretize(pde([Shift(t, 1)(Ne) ~ rhs], periodic ? per : Equation[], [Ne, ke], [Dc, dx, dy]),
                        LatticeDiscretization(Grid((n, n)); T = Float64))
        R = runner(cf)
        copyto!(field(R, "N"), Float64.(vec(N0)))
        copyto!(field(R, "kindₛ"), Int32.(ifelse.(vec(empty), 1, 2)))
        steps!(R, 0.0, 1; P = (Float64(Dv), 0.2, 0.2))
        got = reshape(field(R, "N"), n, n)
        @test maximum(abs, got .- Float64.(want)) < 1e-13
        @test abs(sum(got[empty]) - sum(Float64.(N0[empty])) - Float64(pinned)) < 1e-12
        cell && @test got[2:3, 2:3] == zeros(2, 2)              # cell sites keep their value
    end
    # hand check at site (1, 1), closed lattice with the cell: (N11 + N12 + N21)/3 = 4
    empty = trues(n, n)
    empty[2:3, 2:3] .= false
    N0 = Rational{Int}[(i + 2j) % 7 for i in 1:n, j in 1:n]
    N0[2:3, 2:3] .= 0
    @test exact(N0, empty, 1 // 1, false)[1, 1] == 4
    # negative control: empty coded as kind 0 counts the outside of a closed box as empty
    rhs0 = ifelse(ismember(ke, (0,)),
                  Dc * sum(ismember(kindₛ(t, x + a * dx, y + b * dy), (0,)) * N(t, x + a * dx, y + b * dy)
                           for (a, b) in offs) / sum(ismember(kindₛ(t, x + a * dx, y + b * dy), (0,)) for (a, b) in offs), Ne)
    R = runner(symbolic_discretize(pde([Shift(t, 1)(Ne) ~ rhs0], Equation[], [Ne, ke], [Dc, dx, dy]),
                          LatticeDiscretization(Grid((n, n)); T = Float64)))
    copyto!(field(R, "N"), Float64.(vec(N0)))
    copyto!(field(R, "kindₛ"), Int32.(ifelse.(vec(empty), 0, 2)))
    steps!(R, 0.0, 1; P = (1.0, 0.2, 0.2))
    @test abs(sum(field(R, "N")[vec(empty)]) - sum(Float64.(N0[empty])) - 1069 / 840) > 1e-3
end

@testset "periodicity covers map fields" begin
    sys = pde([D(ce) ~ Δ(ce), Shift(t, 1)(Ne) ~ Ne], [c(t, x, 0) ~ c(t, x, 1)], [ce, Ne], Num[])
    @test throws_with(() -> symbolic_discretize(sys, LatticeDiscretization(Grid((4, 4)))), "periodicity is per axis")
    ok = pde([D(ce) ~ Δ(ce), Shift(t, 1)(Ne) ~ Ne], [c(t, x, 0) ~ c(t, x, 1), N(t, x, 0) ~ N(t, x, 1)], [ce, Ne], Num[])
    @test symbolic_discretize(ok, LatticeDiscretization(Grid((4, 4)))) isa CompiledField
end

@testset "array state end to end (two components)" begin
    n, m = 6, 4
    sys = pde([D(ue[1]) ~ Dc * Δ(ue[1]) - k * ue[2], D(ue[2]) ~ Δ(ue[2]) + k * ue[1]],
              [u(t, 0, y)[1] ~ 1.0, u(t, x, 0)[1] ~ u(t, x, 1)[1], u(t, x, 0)[2] ~ u(t, x, 1)[2],
               ue[2] ~ masked(ke == 3, 0.5)], [ue, ke], [Dc, k])
    cf = lower64(sys, (n, m))
    @test sort(collect(keys(cf.initial))) == String[] && occursin("kernel mask:u[2]", ir(cf))
    @test occursin("rule face u[1] axis=1 side=- alpha=1.0", ir(cf)) && occursin("rule face u[2] axis=1 side=- alpha=0.0", ir(cf))
    R = runner(cf)
    rng = MersenneTwister(5)
    u1, u2 = rand(rng, n, m), rand(rng, n, m)
    kind = zeros(Int32, n, m)
    kind[4, 2] = 3
    u2[4, 2] = 0.5
    copyto!(field(R, "u[1]"), vec(u1))
    copyto!(field(R, "u[2]"), vec(u2))
    copyto!(field(R, "kindₛ"), vec(kind))
    dt, Dv, kv, h = 0.01, 1e-3, 0.1, (1 / n, 1 / m)
    steps!(R, dt, 1; P = (Dv, kv))
    lap(v, i, j, lo) = ((i < n ? v[i + 1, j] : v[i, j]) + (i > 1 ? v[i - 1, j] : lo(v[i, j])) - 2v[i, j]) / h[1]^2 +
                       (v[i, mod1(j + 1, m)] + v[i, mod1(j - 1, m)] - 2v[i, j]) / h[2]^2
    w1 = [u1[i, j] + dt * (Dv * lap(u1, i, j, c -> 2 * 1.0 - c) - kv * u2[i, j]) for i in 1:n, j in 1:m]
    w2 = [kind[i, j] == 3 ? 0.5 : u2[i, j] + dt * (lap(u2, i, j, c -> c) + kv * u1[i, j]) for i in 1:n, j in 1:m]
    @test maximum(abs, reshape(field(R, "u[1]"), n, m) .- w1) < 1e-14
    @test maximum(abs, reshape(field(R, "u[2]"), n, m) .- w2) < 1e-14
    @test reshape(field(R, "u[2]"), n, m)[4, 2] == 0.5          # held at the masked site
end

@testset "Float32 lowered kernels: no Float64, warm launches allocate nothing" begin
    function check32(cf; tables = Dict{Int32, Any}())
        s = semantic(cf.program)
        sp = plan(s)                                            # Float32 compute
        st = HostStore(s)
        foreach(((k, v),) -> k <= length(st.tables) && (st.tables[k] = v), tables)   # programs without the table ignore it
        for l in sp.launches
            @test !has_f64(l.kernel.body)
            prep = prepare(s, l, st, cf.defaults; rt = (0.0, 0.1))
            run!(prep)
            @test (@allocated run!(prep)) == 0
        end
        return length(sp.launches)
    end
    f32(sys, dims) = symbolic_discretize(sys, LatticeDiscretization(Grid(dims); T = Float32); update = euler)
    offs = ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
    mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), (1,)) for (a, b) in offs]
    maprhs = ifelse(sum(mem) > 0, Dc * sum(m * N(t, x + a * dx, y + b * dy) for (m, (a, b)) in zip(mem, offs)) / sum(mem), Ne)
    systems = [
        pde([D(ce) ~ Dc * Δ(ce) - k * ce], [c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], [ce], [Dc, k]),
        pde([Shift(t, 1)(Ne) ~ maprhs], Equation[], [Ne, ke], [Dc, dx, dy]),
        pde([D(ce) ~ Δ(ce)], [ce ~ masked(ismember(ke, (2, 3)), g0), c(t, 0, y) ~ 0.0], [ce, ke], [g0]),
        pde([D(ce) ~ at(Dk, ke) + DivKGrad(:harmonic)(Ke, ce), Ke ~ K0 + sin(x)], Equation[], [ce, Ke, ke], [Dk, K0]),
        pde([D(ce) ~ -Advect(Upwind1())(vel(t, x, y), ce)], Equation[], [ce, vel(t, x, y)], Num[]),
        pde([D(ue[1]) ~ Δ(ue[1]) - k * ue[2], D(ue[2]) ~ Δ(ue[2])], [ue[2] ~ masked(ke == 3, 0.5)], [ue, ke], [k])]
    for sys in systems
        @test check32(f32(sys, (16, 8)); tables = Dict{Int32, Any}(Int32(1) => Float32[1, 2, 3])) >= 1
    end
end

@testset "review round 1: refusals" begin
    g = LatticeDiscretization(Grid((4, 4)); T = Float64)
    fields = Dict{Any, Bool}(operation(unwrap(ce)) => false, operation(unwrap(ke)) => true)
    ivs = unwrap.([t, x, y])
    ends = [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
    parse(bc) = LatticePDE.parse_bcs([bc], fields, ivs, ends)
    # 1. every term of a condition on one face
    @test throws_with(() -> parse(c(t, 0, y) + Dx(c(t, 1, y)) ~ 0.0), "different faces")
    @test throws_with(() -> parse(c(t, 0, y) + Dy(c(t, x, 0)) ~ 0.0), "different faces")
    @test only(parse(c(t, 1, y) + Dx(c(t, 1, y)) ~ 0.0)).kind == :robin
    # 5. initial conditions are `c(0, x, y) ~ value`
    @test throws_with(() -> parse(2 * c(0, x, y) ~ 1.0), "initial condition")
    @test only(parse(c(0, x, y) ~ 1.0)).kind == :initial
    sysb(bcs) = pde([D(ce) ~ Δ(ce)], bcs, [ce, ke], Num[])
    # 2. one condition per face, mask and start
    for bcs in ([c(t, 0, y) ~ 1.0, Dx(c(t, 0, y)) ~ 0.0], [ce ~ masked(ke == 3, 1.0), ce ~ masked(ke == 2, 0.0)],
                [c(0, x, y) ~ 0.0, c(0, x, y) ~ 1.0])
        @test throws_with(() -> symbolic_discretize(sysb(bcs), g), "already has a condition")
    end
    @test symbolic_discretize(sysb([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0]), g) isa CompiledField
    # 3. the left side: a time operator on the plain field read
    for (e, msg) in [[Dx(ce) ~ Δ(ce)] => "time rate", [Shift(x, 1)(Ne) ~ 2 * Ne] => "in time",
                     [D(c(t, 0, y)) ~ Δ(ce)] => "time rate", [Shift(t, 1)(N(t, x + dx, y)) ~ 2 * Ne] => "Shift(t, 1)(c(t, x, y))",
                     [c(t, 0, y) ~ 1.0] => "field read"]
        @test throws_with(() -> symbolic_discretize(pde(e, Equation[], [ce, Ne], [dx]), g), msg)
    end
    # 4. an offset needs a lattice_spacing parameter (x + 1 is a physical offset)
    @test throws_with(() -> symbolic_discretize(pde([Shift(t, 1)(Ne) ~ N(t, x + 1, y)], Equation[], [Ne], Num[]), g), "lattice_spacing")
    @test symbolic_discretize(pde([Shift(t, 1)(Ne) ~ N(t, x + dx, y)], Equation[], [Ne], [dx]), g) isa CompiledField
    # 7. a Robin face whose ghost value is undefined (α/2 + β/h = 0: h = 1/4, β = 1/8 at the low face)
    @test throws_with(() -> symbolic_discretize(sysb([c(t, 0, y) + 0.125 * Dx(c(t, 0, y)) ~ 1.0]), g), "ghost value")
    @test symbolic_discretize(sysb([c(t, 0, y) - 0.125 * Dx(c(t, 0, y)) ~ 1.0]), g) isa CompiledField
end

@testset "review round 2: refusals" begin
    g = LatticeDiscretization(Grid((4, 4)); T = Float64)
    map(r; ps = [dx]) = () -> symbolic_discretize(pde([Shift(t, 1)(Ne) ~ r], Equation[], [Ne], ps), g)
    # 1. an offset is `a * dx` exactly
    for r in (N(t, x + dx^2, y), N(t, x + 3dx * dx, y), N(t, x + 1 / dx, y), N(t, x + sqrt(dx), y))
        @test throws_with(map(r), "lattice")
    end
    @test map(N(t, x - 2dx, y))() isa CompiledField
    # 2. a term that reads an aux field is Other (its dependence on c is hidden)
    lin(eqs, ps = Num[]) = Set(last.(symbolic_discretize(pde(eqs, Equation[], [ce, Ke], ps), g).linearity["c"]))
    @test lin([D(ce) ~ Δ(ce) + Ke, Ke ~ ce^2]) == Set([:Diffusion, :Other])
    @test lin([D(ce) ~ Δ(ce) + Dc * Δ(Ke), Ke ~ ce^2], [Dc]) == Set([:Diffusion, :Other])
    # 3. initial conditions: state fields only, values read no field
    @test throws_with(() -> symbolic_discretize(pde([D(ce) ~ Δ(ce), Ke ~ ce], [K(0, x, y) ~ 3.0], [ce, Ke], Num[]), g),
                      "only rate and map fields")
    @test throws_with(() -> symbolic_discretize(pde([D(ce) ~ Δ(ce)], [c(0, x, y) ~ c(0, x, y) + 1], [ce], Num[]), g),
                      "cannot read a field")
    @test throws_with(() -> symbolic_discretize(pde([D(ce) ~ Δ(ce), D(oe) ~ Δ(oe)], [c(0, x, y) ~ o(0, x, y)], [ce, oe], Num[]), g),
                      "")                                       # refused by the parser (a field on each side)
    @test symbolic_discretize(pde([D(ce) ~ Δ(ce)], [c(0, x, y) ~ sin(x)], [ce], Num[]), g) isa CompiledField
    # 4. an aux equation that reads its own field
    @test throws_with(() -> symbolic_discretize(pde([D(ce) ~ Δ(ce), Ke ~ Ke + ce], Equation[], [ce, Ke], Num[]), g),
                      "cannot read itself")
    # 5. the Robin check with a parameter coefficient (default 1/8 = h/2 at the low face)
    @parameters βr = 0.125
    @test throws_with(() -> symbolic_discretize(pde([D(ce) ~ Δ(ce)], [c(t, 0, y) + βr * Dx(c(t, 0, y)) ~ 1.0], [ce], [βr]), g),
                      "ghost value")
    # and an input multiplier of advection is Other, as of diffusion
    st, inp = [operation(unwrap(ce))], [operation(unwrap(ke)), operation(unwrap(vel(t, x, y)))]
    @test only(last.(LatticePDE.linearity(ke * Advect(Upwind1())(vel(t, x, y), ce), ce, st; inputs = inp))) == :Other
    @test only(last.(LatticePDE.linearity(Dc * Advect(Upwind1())(vel(t, x, y), ce), ce, st; inputs = inp))) == :Advection
end

@testset "state type: lanes per T, default by backend, refusals (P5 C6-1, C6-3)" begin
    sys = pde([D(ce) ~ Dc * Δ(ce) - k * ce], [c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], [ce], [Dc, k])
    lanes(T) = [f.storage for f in symbolic_discretize(sys, LatticeDiscretization(Grid((8, 4)); T); update = euler).program.fields
                if f.key == "c"]
    @test lanes(Float32) == [F32] && lanes(Float64) == [F64] && lanes(Float16) == [F16]
    @test lanes(BigFloat) == [F64]                    # host problems fill F64 lanes with BigFloat
    @test lanes(nothing) == [F64]                     # default on the host: Float64
    # negative control of the old mapping: T = BigFloat must not give F32 storage
    @test lanes(BigFloat) != [F32]
    err = throws_with(() -> lanes(Int), "not a state type")
    @test err
end
