# The discretizer: BC parser, keys, linearity table, raw-`Differential`
# rule, maps and offset reads, and end-to-end oracles from a `PDESystem` through the host
# runner (the executor contract on the CPU). Each oracle has a negative control that must
# fail. The explicit step is the test's own `update` (C7a brings the steppers).

@testsetup module LP_discretize
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")

# Salted operator hashes: another package build's hashes, in this process (the D-107 pattern
# of PottsModels' `canonical_term_order_tests.jl`, extended to field terms). Inert at salt
# 0.
const SALT = Ref{UInt}(0)
for f in (laplacian, value_at, ismember, sin, cos, exp)
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
include("shared/export_all.jl")
end

@testitem "BC parser" setup = [LP_discretize] tags = [:latticepde, :discretize] begin
    @testset "BC parser" begin
        fields = Dict{Any, Bool}(
            operation(unwrap(v)) => MTKB.isinput(unwrap(v))
                for v in (ce, ke, ue)
        )
        ivs = unwrap.([t, x, y])
        ends = [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
        one(bc) = only(LatticePDE.parse_bcs([bc], fields, ivs, ends))
        cases = [
            (c(0, x, y) ~ 0.0, :initial, 0, 0, 0), (c(t, 0, y) ~ 1.0, :dirichlet, 1, -1, 0),
            (c(t, 1.0, y) ~ g0, :dirichlet, 1, 1, 0), (
                Dx(c(t, 1, y)) ~ 0.0, :neumann, 1, 1, 0,
            ),
            (h0 * c(t, x, 0) + Dy(c(t, x, 0)) ~ g0, :robin, 2, -1, 0), (
                c(t, x, 0) ~ c(t, x, 1), :periodic, 2, 0, 0,
            ),
            (ce ~ masked(ke == 3, 0.0), :masked, 0, 0, 0), (
                ce ~ masked(ismember(ke, (2, 3)), 1.0), :masked, 0, 0, 0,
            ),
            (u(t, 0, y)[1] ~ 0.0, :dirichlet, 1, -1, 1), (
                ue[2] ~ masked(ke == 3, 0.0), :masked, 0, 0, 2,
            ),
            (Dx(u(t, 1, y)[2]) ~ 0.0, :neumann, 1, 1, 2),
        ]
        for (bc, kind, axis, side, comp) in cases
            b = one(bc)
            @test (b.kind, b.axis, b.side, b.comp) == (kind, axis, side, comp)
            # never misrouted to the input
            @test !isequal(b.op, operation(unwrap(ke)))
        end
        r = one(h0 * c(t, x, 0) + Dy(c(t, x, 0)) ~ g0)
        @test isequal(r.alpha, unwrap(h0)) && isequal(r.beta, 1) &&
            isequal(r.value, unwrap(g0))
        # refusals
        for bc in (
                c(t, 0.5, y) ~ 1.0, kindₛ(t, 0, y) ~ 1,
                c(t, 0, y) + u(t, 0, y)[1] ~ 0.0, c(t, x, 0) ~ c(t, 0, 0),
                c(t, x, 0) ~ c(t, x, 0), u(t, 0, y) ~ [0.0, 0.0],
                Dy(c(t, 1, y)) ~ 0.0, c(t, 0, 0) ~ 1.0,
                kindₛ(t, x, y) ~ masked(ke == 3, 1),
            )
            @test_throws ArgumentError one(bc)
        end
    end
end

@testitem "keys by operation, refusals, wrong bcs" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "keys by operation, refusals, wrong bcs" begin
        eq = [D(ce) ~ Dc * laplacian(ce)]
        sys = pde(eq, [c(t, x, 0) ~ c(t, x, 1)], [ce], [Dc])
        g = Grid((4, 4))
        base = ir(symbolic_discretize(sys, LatticeDiscretization(g)))
        # the callable, the applied term, unwrapped
        for key in (c, ce, unwrap(ce))
            @test ir(
                symbolic_discretize(
                    sys, LatticeDiscretization(g; methods = Dict(key => FiniteVolume()))
                )
            ) ==
                base
        end
        @test_throws ArgumentError symbolic_discretize(
            sys, LatticeDiscretization(g; methods = Dict(o => FiniteVolume()))
        )
        @test_throws ArgumentError symbolic_discretize(
            sys, LatticeDiscretization(
                g; methods = Dict(
                    c =>
                        :fem
                )
            )
        )
        @test_throws ArgumentError symbolic_discretize(
            sys, LatticeDiscretization(
                Grid(
                    (
                        4, 4, 4,
                    )
                )
            )
        )
        @test_throws ArgumentError symbolic_discretize(
            pde(eq, Equation[], [ce], [Dc => 1.0e-3]), LatticeDiscretization(g)
        )
        @test_throws ArgumentError symbolic_discretize(
            pde([eq; D(ce) ~ ce], Equation[], [ce], [Dc]), LatticeDiscretization(g)
        )
        @test_throws ArgumentError symbolic_discretize(
            pde(eq, Equation[], [ce, oe], [Dc]), LatticeDiscretization(g)
        )
        @test_throws ArgumentError symbolic_discretize(
            pde([eq; D(ke) ~ 1], Equation[], [ce, ke], [Dc]), LatticeDiscretization(g)
        )
        # wrong bcs are detected: a face of a periodic axis; periodicity for one field only
        @test_throws ArgumentError symbolic_discretize(
            pde(eq, [c(t, x, 0) ~ c(t, x, 1), c(t, x, 0) ~ 1.0], [ce], [Dc]),
            LatticeDiscretization(g)
        )
        two = pde([eq; D(oe) ~ laplacian(oe)], [c(t, x, 0) ~ c(t, x, 1)], [ce, oe], [Dc])
        @test_throws ArgumentError symbolic_discretize(two, LatticeDiscretization(g))
        # the vocabulary scans run first
        @test_throws ArgumentError symbolic_discretize(
            pde([D(ce) ~ Pre(ce)], Equation[], [ce], [Dc]), LatticeDiscretization(g)
        )
        # spellings with no lattice meaning
        for (rhs, ok) in (
                Dx(ce) => false, Dx(Dx(ce) * Dy(ce)) => false, value_at(ce, ke) => false,
                ce^cT => true, Symbolics.Num(unwrap(z)) => false,
            )
            f = () -> symbolic_discretize(
                pde([D(ce) ~ rhs], Equation[], [ce, ke], [Dc, cT]),
                LatticeDiscretization(g)
            )
            ok ? (@test f() isa CompiledField) : (@test_throws ArgumentError f())
        end
    end
end

@testitem "linearity table" setup = [LP_discretize] tags = [:latticepde, :discretize] begin
    @testset "linearity table" begin
        states = [operation(unwrap(v)) for v in (ce, oe, Ke)]
        table = [
            Dc * laplacian(ce) - k * ce => Set([:Diffusion, :LinearLocal]),
            DivKGrad(:harmonic)(value_at(Dk, ke), ce) - value_at(Dk, ke) * ce =>
                Set([:Diffusion, :LinearLocal]),
            Advect(Upwind1())(vel(t, x, y), ce) + cT * ismember(ke, (2,)) =>
                Set([:Advection, :Source]),
            ce * laplacian(ce) => Set([:Other]), DivKGrad(:harmonic)(ce, ce) =>
                Set([:Other]),
            -k * max(ce - cT, 0) * ismember(ke, (2,)) => Set([:LaggedSwitch]),
            k * ifelse(cT > ce, cT - ce, 0) => Set([:LaggedSwitch]), k *
                ifelse(
                oe > ce, oe -
                    ce, 0
            ) =>
                Set([:Other]),
            Dc * laplacian(ce) + k * oe => Set([:Diffusion, :CrossLinear]), ce^2 =>
                Set([:Other]), ce * oe^2 => Set([:Other]),
            value_at(Dk, ke) * ce => Set([:LinearLocal]),
            Dx(Dx(ce)) + Dy(Dy(ce)) => Set([:Diffusion]), Dx(Ke * Dx(ce)) => Set([:Other]),
            Dx(
                K0 *
                    Dx(ce)
            ) =>
                Set([:Diffusion]),
            Dx(ce * Dx(ce)) => Set([:Other]), Dc * laplacian(oe) => Set([:CrossLinear]),
            oe *
                Ke =>
                Set([:Other]),
        ]
        inputs = [operation(unwrap(ke))]
        for (rhs, want) in table, form in (identity, simplify, Symbolics.expand)
            @test Set(last.(LatticePDE.linearity(form(rhs), ce, states; inputs))) == want
        end
        # the conservative rule: a coefficient that reads an unknown field makes the term
        # Other, and a diffusion multiplier reads no field at all
        for (rhs, want) in [
                DivKGrad(:harmonic)(Ke, ce) => :Other,    # K ~ c^2 would make it nonlinear
                Ke * ce => :Other, ce * oe => :Other, oe * laplacian(ce) => :Other,
                ifelse(ke == 2, laplacian(ce), 0) => :Other,
                Dc * laplacian(ce) => :Diffusion, ismember(ke, (2,)) *
                    ce =>
                    :LinearLocal,
                # a multiplier that reads inputs through table reads and indicators only
                # varies by site and is bounded; one that reads an input directly is Other
                value_at(Dk, ke) * laplacian(ce) => :SiteDiffusion, ismember(ke, (2,)) *
                    laplacian(ce) =>
                    :SiteDiffusion,
                (value_at(Dk, ke) - value_at(Dk, ke + 1) + 2) * laplacian(ce) =>
                    :SiteDiffusion,
                (1 / value_at(Dk, ke)) * DivKGrad(:arithmetic)(value_at(Dk, ke), ce) =>
                    :SiteDiffusion,
                ifelse(ke == 2, Dc, 2Dc) * laplacian(ce) => :SiteDiffusion, ke *
                    laplacian(ce) =>
                    :Other,
                (ke + value_at(Dk, ke)) * laplacian(ce) => :Other,
            ]
            @test only(last.(LatticePDE.linearity(rhs, ce, states; inputs))) == want
        end
        # the system table uses the same rule: an aux coefficient that depends on c
        cf = symbolic_discretize(
            pde(
                [D(ce) ~ DivKGrad(:harmonic)(Ke, ce) + Ke * ce, Ke ~ ce^2], Equation[], [
                    ce, Ke,
                ], Num[]
            ),
            LatticeDiscretization(Grid((4, 4)))
        )
        @test Set(last.(cf.linearity["c"])) == Set([:Other])
        # Symbolics' own expansion is blind to the registered operators: the reason for the
        # table
        @test !Symbolics.linear_expansion(Dc * laplacian(ce) - k * ce, ce)[3]
    end
end

@testitem "raw Differential rule: same IR as Δ and DivKGrad" setup = [
    LP_discretize,
] tags = [
    :latticepde, :discretize,
] begin
    @testset "raw Differential rule: same IR as Δ and DivKGrad" begin
        g = Grid((5, 4))
        bc = [
            c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) + Dx(c(t, 1, y)) ~ g0, c(t, x, 0) ~
                c(t, x, 1),
        ]
        aux = [Ke ~ K0 + x]
        function low(rhs; e = Equation[])
            return ir(
                symbolic_discretize(
                    pde(
                        [D(ce) ~ rhs; e], bc, isempty(e) ? [ce] : [ce, Ke],
                        [Dc, h0, g0, K0]
                    ),
                    LatticeDiscretization(g)
                )
            )
        end
        @test low(Dc * (Dx(Dx(ce)) + Dy(Dy(ce)))) == low(Dc * laplacian(ce))
        @test low(Dx(Ke * Dx(ce)) + Dy(Ke * Dy(ce)); e = aux) ==
            low(DivKGrad(:harmonic)(Ke, ce); e = aux)
        # negative controls: an axis missing, the arithmetic face mean, a doubled axis
        @test low(Dc * Dx(Dx(ce))) != low(Dc * laplacian(ce))
        @test low(DivKGrad(:arithmetic)(Ke, ce); e = aux) !=
            low(DivKGrad(:harmonic)(Ke, ce); e = aux)
        @test low(Dc * (Dx(Dx(ce)) + Dx(Dx(ce)))) != low(Dc * laplacian(ce))
    end
end

@testitem "steady linear profiles: Dirichlet, Robin, Neumann" setup = [
    LP_discretize,
] tags = [
    :latticepde, :discretize,
] begin
    @testset "steady linear profiles: Dirichlet, Robin, Neumann" begin
        n = 16
        v, xc = profile([c(t, 0, y) ~ 1.0, c(t, 1, y) ~ 0.0], n)
        # cell-centered FV is exact on lines
        @test maximum(abs, v .- (1 .- xc)) < 1.0e-9
        v, _ = profile([c(t, 0, y) ~ 1.0, c(t, 1, y) ~ g0], n)
        # parameter value at the face
        @test maximum(abs, v .- (1 .+ (0.5 - 1) .* xc)) < 1.0e-9
        # Robin α c + β ∂c/∂x = g at x = 1: h0 c + c′ = g0 → c = 1 − a x, a = (h0 − g0)/(1 +
        # h0)
        v, _ = profile([c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) + Dx(c(t, 1, y)) ~ g0], n)
        a = (2.0 - 0.5) / 3.0
        @test maximum(abs, v .- (1 .- a .* xc)) < 1.0e-9
        # Robin at the low face (outward normal −x): c′(0) − h0 c(0)... here −c′ + c = 0,
        # c(1) = 1 → c = (1 + x)/2
        v, _ = profile([c(t, 0, y) - Dx(c(t, 0, y)) ~ 0.0, c(t, 1, y) ~ 1.0], n)
        @test maximum(abs, v .- (1 .+ xc) ./ 2) < 1.0e-9
        # prescribed flux: c = 1 − g0 x
        v, _ = profile([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ -g0], n)
        @test maximum(abs, v .- (1 .- 0.5 .* xc)) < 1.0e-9
        v, _ = profile([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0], n; steps = 12000)
        # no flux: flat at the Dirichlet value
        @test maximum(abs, v .- 1) < 1.0e-6
        # negative control: the sign of the normal at the high face flipped (h0 c − c′ = g0)
        # misses the oracle
        v, _ = profile([c(t, 0, y) ~ 1.0, h0 * c(t, 1, y) - Dx(c(t, 1, y)) ~ g0], n)
        @test maximum(abs, v .- (1 .- a .* xc)) > 1.0e-2
    end
end

@testitem "Fourier mode decay (periodic 2D)" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "Fourier mode decay (periodic 2D)" begin
        n, m, kx, ky = 16, 8, 1, 2
        d = dom2(1.0, 2.0)
        function mk(rhs)
            return lower64(
                pde([D(ce) ~ rhs], [c(t, x, 0) ~ c(t, x, 1)...], [ce], [Dc]; d), (
                    n, m,
                )
            )
        end
        function sys(rhs)
            return pde(
                [D(ce) ~ rhs], [c(t, 0, y) ~ c(t, 1, y), c(t, x, 0) ~ c(t, x, 2)],
                [ce], [Dc]; d = d
            )
        end
        hx, hy = 1 / n, 2 / m
        xc, yc = ((1:n) .- 0.5) .* hx, ((1:m) .- 0.5) .* hy
        mode = [cos(2π * kx * a) * cos(2π * ky * b / 2) for a in xc, b in yc]
        λ = -4 / hx^2 * sin(π * kx * hx)^2 - 4 / hy^2 * sin(π * ky * hy / 2)^2
        dt, nsteps, D_ = 0.2 * hx^2 / 1.0e-3, 50, 1.0e-3
        function run(rhs)
            R = runner(lower64(sys(rhs), (n, m)))
            copyto!(field(R, "c"), vec(mode))
            steps!(R, dt, nsteps)
            return reshape(field(R, "c"), n, m)
        end
        # the discrete eigenvector, exactly
        oracle = (1 + dt * D_ * λ)^nsteps .* mode
        @test maximum(abs, run(Dc * laplacian(ce)) .- oracle) < 1.0e-12
        @test maximum(abs, run(Dc * (Dx(Dx(ce)) + Dy(Dy(ce)))) .- oracle) < 1.0e-12
        # and the continuum rate, to O(h²)
        T = dt * nsteps
        @test maximum(abs, oracle .- exp(-D_ * 4π^2 * (kx^2 + (ky / 2)^2) * T) .* mode) <
            0.02
        # negative control: flipped sign
        @test maximum(abs, run(-Dc * laplacian(ce)) .- oracle) > 0.1
        # an axis wrong
        @test maximum(abs, run(Dc * Dx(Dx(ce)) + Dc * Dx(Dx(ce))) .- oracle) > 1.0e-4
    end
end

@testitem "no-flux mass conservation" setup = [LP_discretize] tags = [
    :latticepde,
    :discretize,
] begin
    @testset "no-flux mass conservation" begin
        n, m = 12, 9
        function mk(bcs)
            return lower64(
                pde([D(ce) ~ Dc * laplacian(ce) + Dc * Dx(Dx(ce))], bcs, [ce], [Dc]), (
                    n, m,
                )
            )
        end
        function mass(bcs)
            R = runner(mk(bcs))
            u0 = rand(MersenneTwister(3), n * m)
            copyto!(field(R, "c"), u0)
            steps!(R, 0.1 / n^2 / 1.0e-3, 100)
            return abs(sum(field(R, "c")) - sum(u0)), sum(u0)
        end
        # every face defaults to no flux
        dm, m0 = mass(Equation[])
        @test dm <= 64 * eps() * n * m * m0
        dm, _ = mass([Dx(c(t, 0, y)) ~ 0.0, Dx(c(t, 1, y)) ~ 0.0, Dy(c(t, x, 0)) ~ 0.0])
        @test dm <= 64 * eps() * n * m * m0
        # negative control: one face Dirichlet(0)
        dm, _ = mass([c(t, 0, y) ~ 0.0])
        @test dm > 1.0e-3
    end
end

@testitem "masked interior Dirichlet" setup = [LP_discretize] tags = [
    :latticepde,
    :discretize,
] begin
    @testset "masked interior Dirichlet" begin
        n, j = 16, 12                                               # mask column j holds 1
        function sys(bcs)
            return pde(
                [D(ce) ~ laplacian(ce)],
                [bcs; c(t, 0, y) ~ 0.0; c(t, x, 0) ~ c(t, x, 1)], [ce, ke], Num[]
            )
        end
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
        # linear up to the mask, flat beyond
        want = [i <= j ? xc[i] / xc[j] : 1.0 for i in 1:n]
        @test maximum(abs, v .- want) < 1.0e-8
        @test occursin("rule node_value c mask=mask:c value=1.0", ir(cf))
        @test occursin("kernel mask:c", ir(cf))
        # negative control: no mask
        v, _ = solve(Equation[])
        @test maximum(abs, v .- want) > 0.5
    end
end

@testitem "3D: periodic x, no-flux y, Dirichlet z (one step against a loop)" setup = [
    LP_discretize,
] tags = [
    :latticepde, :discretize,
] begin
    @testset "3D: periodic x, no-flux y, Dirichlet z (one step against a loop)" begin
        @parameters g1 = 0.25
        dims = (6, 5, 4)
        d3 = [
            t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 3.0),
            y ∈ Interval(0.0, 1.0), z ∈ Interval(0.0, 2.0),
        ]
        e = c(t, x, y, z)
        function step(zbcs)
            sys = PDESystem(
                [D(e) ~ Dc * laplacian(e)], [c(t, 0, y, z) ~ c(t, 3, y, z); zbcs],
                d3, [t, x, y, z], [e], [Dc, g1]; name = :f
            )
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
                (
                (jj < 5 ? u[i, jj + 1, l] : cc) + (jj > 1 ? u[i, jj - 1, l] : cc) -
                    2cc
            ) / h[2]^2 +
                (
                (l < 4 ? u[i, jj, l + 1] : 2 * 2.0 - cc) +
                    (l > 1 ? u[i, jj, l - 1] : 2 * 0.25 - cc) - 2cc
            ) / h[3]^2
            want[i, jj, l] = cc + 0.7 * 1.0e-3 * lap
        end
        @test maximum(abs, got .- want) < 1.0e-14
        # negative control: z no-flux instead
        bad, _ = step(Equation[])
        @test maximum(abs, bad .- want) > 1.0e-5
    end
end

@testitem "kind table source value_at(Dk, kindₛ)" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "kind table source value_at(Dk, kindₛ)" begin
        cf = lower64(pde([D(ce) ~ value_at(Dk, ke)], Equation[], [ce, ke], [Dk]), (4, 2))
        @test cf.tables == ["Dk" => [1.0, 2.0, 3.0]]
        R = runner(cf)
        R.st.tables[Int32(1)] = [1.0, 2.0, 3.0]
        copyto!(field(R, "kindₛ"), Int32[0, 1, 2, 3, 3, 2, 1, 0])
        steps!(R, 1.0, 1)
        @test field(R, "c") == [0.0, 1.0, 2.0, 3.0, 3.0, 2.0, 1.0, 0.0]    # kind 0 reads 0
    end
end

@testitem "upwind advection: exact shift at CFL 1" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "upwind advection: exact shift at CFL 1" begin
        n = 8
        sys = pde(
            [D(ce) ~ -Advect(Upwind1())(vel(t, x, y), ce)], [
                c(t, 0, y) ~ c(t, 1, y), c(t, x, 0) ~ c(t, x, 1),
            ],
            [ce, vel(t, x, y)], Num[]
        )
        R = runner(lower64(sys, (n, 2)))
        v = field(R, "vel[1]")
        v .= 1.0
        u0 = rand(MersenneTwister(2), 2n)
        copyto!(field(R, "c"), u0)
        steps!(R, 1 / n, 3)
        @test reshape(field(R, "c"), n, 2) ≈
            circshift(reshape(u0, n, 2), (3, 0)) atol = 1.0e-14
    end
end

@testitem "masked averaging map (Shift and offset reads)" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "masked averaging map (Shift and offset reads)" begin
        n, Iset = 5, (1,)
        offs = ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
        rd(a, b) = N(t, x + a * dx, y + b * dy)
        mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), Iset) for (a, b) in offs]
        rhs = ifelse(
            sum(mem) > 0, Dc *
                sum(m * rd(a, b) for (m, (a, b)) in zip(mem, offs)) /
                sum(mem), Ne
        )
        per = [N(t, 0, y) ~ N(t, 1, y), N(t, x, 0) ~ N(t, x, 1)]
        sys(r; e = [Shift(t, 1)(Ne) ~ r]) = pde(e, per, [Ne, ke], [Dc, dx, dy])
        cf = symbolic_discretize(sys(rhs), LatticeDiscretization(Grid((n, n)); T = Float64))
        # spacing parameters valued from the grid
        @test cf.defaults == [1.0e-3, 0.2, 0.2]
        @test occursin("kernel map:N", ir(cf))
        kind = fill(Int32(1), n, n)
        kind[3, 3] = 2
        kind[2, 4] = 2
        N0 = Rational{BigInt}[(i^2 * j + 1) // 7 for i in 1:n, j in 1:n]
        # N ← (D/|I|) Σ_{j∈I} N_j, exact
        function direct(N0, Dv; periodic = true)
            out = copy(N0)
            wrap(i) = periodic ? mod1(i, n) : i
            # closed: outside sites are not in I
            inI(p) = all(v -> 1 <= v <= n, p) && kind[p...] in Iset
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
        @test maximum(abs, got .- Float64.(want)) < 1.0e-13
        # the mass change
        @test abs((sum(got) - sum(Float64.(N0))) - Float64(sum(want) - sum(N0))) < 1.0e-12
        # the map is not conservative
        @test sum(want) != sum(N0)
        # a closed lattice: offset reads outside the box read 0 (kind 0 is not in I)
        closed = symbolic_discretize(
            pde([Shift(t, 1)(Ne) ~ rhs], Equation[], [Ne, ke], [Dc, dx, dy]),
            LatticeDiscretization(Grid((n, n)); T = Float64)
        )
        want_c = direct(N0, 1 // 1; periodic = false)
        got_c = apply(closed, (1.0, 0.2, 0.2))
        @test maximum(abs, got_c .- Float64.(want_c)) < 1.0e-13
        @test abs((sum(got_c) - sum(Float64.(N0))) - Float64(sum(want_c) - sum(N0))) <
            1.0e-12
        # the two lattices differ at the edges
        @test maximum(abs, got_c .- Float64.(want)) > 1.0e-3
        # negative control: a flux-form rate step of the same field misses the exact map
        flux = symbolic_discretize(
            pde([D(Ne) ~ laplacian(Ne)], per, [Ne], Num[]),
            LatticeDiscretization(Grid((n, n)); T = Float64); update = euler
        )
        R = runner(flux)
        copyto!(field(R, "N"), Float64.(vec(N0)))
        steps!(R, 0.01, 1)
        @test maximum(abs, reshape(field(R, "N"), n, n) .- Float64.(want)) > 1.0e-3
        # refusals: only Shift(t, 1) maps; offset reads only in maps and with integer
        # offsets
        g = LatticeDiscretization(Grid((n, n)))
        for (e, msg) in [
                [Shift(t, -1)(Ne) ~ rhs] => "Shift(t, 1)", [
                    Shift(t, 2)(Ne) ~
                        rhs,
                ] => "Shift(t, 1)",
                [MTKB.Hold()(Ne) ~ rhs] => "not supported", [
                    MTKB.Sample(1.0)(Ne) ~
                        rhs,
                ] => "not supported",
                [Shift(t, 1)(Ne) ~ MTKB.Hold()(Ne)] => "not supported", [
                    D(Ne) ~
                        rd(1, 0) -
                        Ne,
                ] => "only in map equations",
                [Shift(t, 1)(Ne) ~ N(t, x + dx / 2, y)] => "integer literal", [
                    Shift(t, 1)(Ne) ~
                        N(
                        t, x + Dc, y
                    ),
                ] => "lattice_spacing",
                [Shift(t, 1)(Ne) ~ N(t, x + dy, y)] => "lattice_spacing = 1", [
                    N(
                        ShiftIndex(t, 1) +
                            1
                    ) ~
                        rhs,
                ] => "ShiftIndex",
            ]
            @test throws_with(() -> symbolic_discretize(sys(rhs; e), g), msg)
        end
    end
end

@testitem "lowered IR independent of operator hashes" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "lowered IR independent of operator hashes" begin
        function build()
            rhs = Dc * laplacian(ce) - k * ce + K0 * sin(ce) + cT * exp(-oe) +
                g0 * cos(oe) + h0 * ismember(ke, (2, 3)) +
                DivKGrad(:harmonic)(Ke, ce) + k * Dx(Dx(ce)) +
                max(ce - cT, 0) * ismember(ke, (1,)) +
                value_at(Dk, ke) * laplacian(oe)
            sys = pde(
                [
                    D(ce) ~ rhs, D(oe) ~ laplacian(oe) + ce * oe + sin(ce) + cos(oe), Ke ~
                        K0 +
                        exp(ce),
                ],
                Equation[], [ce, oe, Ke, ke], [Dc, k, K0, cT, g0, h0, Dk]
            )
            return ir(symbolic_discretize(sys, LatticeDiscretization(Grid((4, 3)))))
        end
        function order()
            return string.(
                arguments(
                    unwrap(
                        Dc * laplacian(ce) + K0 * laplacian(oe) + h0 * ismember(ke, (2,)) +
                            k * sin(ce) +
                            cT * exp(oe) + g0 * cos(ce) + laplacian(Ke)
                    )
                )
            )
        end
        base, base_order = build(), order()
        @test all(s -> salted(build, s) == base, 1:4)
        # and over repeated builds
        @test build() == base
        # negative control: the salt does reorder Symbolics' operands of a sum
        @test any(s -> salted(order, s) != base_order, 1:4)
    end
end

@testitem "masked averaging map: Moore neighborhood, empty sites only (Rational \
    oracle)" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "masked averaging map: Moore neighborhood, empty sites only (Rational \
        oracle)" begin
        # [N(l_i)] ← (D/|I_i|) Σ_{j∈I_i} [N(l_j)], I_i = empty sites of Moore(i) ∪ {i};
        # empty sites update synchronously, cell sites keep their value. Empty is kind 1,
        # the cell kind 2.
        n = 5
        offs = [(a, b) for a in -1:1 for b in -1:1]
        mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), (1,)) for (a, b) in offs]
        rhs = ifelse(
            ismember(ke, (1,)),
            Dc * sum(m * N(t, x + a * dx, y + b * dy) for (m, (a, b)) in zip(mem, offs)) /
                sum(mem), Ne
        )
        per = [N(t, 0, y) ~ N(t, 1, y), N(t, x, 0) ~ N(t, x, 1)]
        # the hand `step`, Rational
        function exact(N, empty, D, periodic)
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
        cases = [
            (false, true, 1 // 1, 1069 // 840), (false, false, 1 // 1, 35 // 36), (
                true, false, 1 // 1, 0 // 1,
            ),
            (true, true, 1 // 1, 13 // 56), (true, false, 9 // 10, -39 // 5),
        ]
        for (periodic, cell, Dv, pinned) in cases
            empty = trues(n, n)
            N0 = Rational{Int}[(i + 2j) % 7 for i in 1:n, j in 1:n]
            cell && (empty[2:3, 2:3] .= false; N0[2:3, 2:3] .= 0)
            want = exact(N0, empty, Dv, periodic)
            @test sum(want[empty]) - sum(N0[empty]) == pinned       # the port reproduces t4
            cf = symbolic_discretize(
                pde(
                    [Shift(t, 1)(Ne) ~ rhs], periodic ? per : Equation[], [Ne, ke], [
                        Dc, dx, dy,
                    ]
                ),
                LatticeDiscretization(Grid((n, n)); T = Float64)
            )
            R = runner(cf)
            copyto!(field(R, "N"), Float64.(vec(N0)))
            copyto!(field(R, "kindₛ"), Int32.(ifelse.(vec(empty), 1, 2)))
            steps!(R, 0.0, 1; P = (Float64(Dv), 0.2, 0.2))
            got = reshape(field(R, "N"), n, n)
            @test maximum(abs, got .- Float64.(want)) < 1.0e-13
            @test abs(sum(got[empty]) - sum(Float64.(N0[empty])) - Float64(pinned)) <
                1.0e-12
            # cell sites keep their value
            cell && @test got[2:3, 2:3] == zeros(2, 2)
        end
        # hand check at site (1, 1), closed lattice with the cell: (N11 + N12 + N21)/3 = 4
        empty = trues(n, n)
        empty[2:3, 2:3] .= false
        N0 = Rational{Int}[(i + 2j) % 7 for i in 1:n, j in 1:n]
        N0[2:3, 2:3] .= 0
        @test exact(N0, empty, 1 // 1, false)[1, 1] == 4
        # negative control: empty coded as kind 0 counts the outside of a closed box as
        # empty
        rhs0 = ifelse(
            ismember(ke, (0,)),
            Dc * sum(
                ismember(kindₛ(t, x + a * dx, y + b * dy), (0,)) *
                    N(t, x + a * dx, y + b * dy)
                    for (a, b) in offs
            ) / sum(ismember(kindₛ(t, x + a * dx, y + b * dy), (0,)) for (a, b) in offs), Ne
        )
        R = runner(
            symbolic_discretize(
                pde([Shift(t, 1)(Ne) ~ rhs0], Equation[], [Ne, ke], [Dc, dx, dy]),
                LatticeDiscretization(Grid((n, n)); T = Float64)
            )
        )
        copyto!(field(R, "N"), Float64.(vec(N0)))
        copyto!(field(R, "kindₛ"), Int32.(ifelse.(vec(empty), 0, 2)))
        steps!(R, 0.0, 1; P = (1.0, 0.2, 0.2))
        @test abs(sum(field(R, "N")[vec(empty)]) - sum(Float64.(N0[empty])) - 1069 / 840) >
            1.0e-3
    end
end

@testitem "periodicity covers map fields" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "periodicity covers map fields" begin
        sys = pde(
            [D(ce) ~ laplacian(ce), Shift(t, 1)(Ne) ~ Ne], [c(t, x, 0) ~ c(t, x, 1)], [
                ce, Ne,
            ], Num[]
        )
        # `c` wraps on y and the map field `N` is closed (base: "periodicity is per axis")
        cf = symbolic_discretize(sys, LatticeDiscretization(Grid((4, 4))))
        @test cf isa CompiledField
        ok = pde(
            [D(ce) ~ laplacian(ce), Shift(t, 1)(Ne) ~ Ne],
            [c(t, x, 0) ~ c(t, x, 1), N(t, x, 0) ~ N(t, x, 1)], [ce, Ne], Num[]
        )
        @test symbolic_discretize(ok, LatticeDiscretization(Grid((4, 4)))) isa CompiledField
    end
end

@testitem "array state end to end (two components)" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "array state end to end (two components)" begin
        n, m = 6, 4
        sys = pde(
            [
                D(ue[1]) ~ Dc * laplacian(ue[1]) - k * ue[2], D(ue[2]) ~
                    laplacian(ue[2]) + k * ue[1],
            ],
            [
                u(t, 0, y)[1] ~ 1.0, u(t, x, 0)[1] ~ u(t, x, 1)[1], u(t, x, 0)[2] ~
                    u(t, x, 1)[2],
                ue[2] ~ masked(ke == 3, 0.5),
            ], [ue, ke], [Dc, k]
        )
        cf = lower64(sys, (n, m))
        @test sort(collect(keys(cf.initial))) == String[] &&
            occursin("kernel mask:u[2]", ir(cf))
        @test occursin("rule face u[1] axis=1 side=- alpha=1.0", ir(cf)) &&
            occursin("rule face u[2] axis=1 side=- alpha=0.0", ir(cf))
        R = runner(cf)
        rng = MersenneTwister(5)
        u1, u2 = rand(rng, n, m), rand(rng, n, m)
        kind = zeros(Int32, n, m)
        kind[4, 2] = 3
        u2[4, 2] = 0.5
        copyto!(field(R, "u[1]"), vec(u1))
        copyto!(field(R, "u[2]"), vec(u2))
        copyto!(field(R, "kindₛ"), vec(kind))
        dt, Dv, kv, h = 0.01, 1.0e-3, 0.1, (1 / n, 1 / m)
        steps!(R, dt, 1; P = (Dv, kv))
        function lap(v, i, j, lo)
            return (
                (i < n ? v[i + 1, j] : v[i, j]) + (i > 1 ? v[i - 1, j] : lo(v[i, j])) -
                    2v[i, j]
            ) / h[1]^2 +
                (v[i, mod1(j + 1, m)] + v[i, mod1(j - 1, m)] - 2v[i, j]) / h[2]^2
        end
        w1 = [
            u1[i, j] + dt * (Dv * lap(u1, i, j, c -> 2 * 1.0 - c) - kv * u2[i, j])
                for i in 1:n, j in 1:m
        ]
        w2 = [
            if kind[i, j] == 3
                0.5
            else
                u2[i, j] + dt * (lap(u2, i, j, c -> c) + kv * u1[i, j])
            end for i in 1:n, j in 1:m
        ]
        @test maximum(abs, reshape(field(R, "u[1]"), n, m) .- w1) < 1.0e-14
        @test maximum(abs, reshape(field(R, "u[2]"), n, m) .- w2) < 1.0e-14
        # held at the masked site
        @test reshape(field(R, "u[2]"), n, m)[4, 2] == 0.5
    end
end

@testitem "Float32 lowered kernels: no Float64, warm launches allocate nothing" setup = [
    LP_discretize,
] tags = [
    :latticepde, :discretize,
] begin
    @testset "Float32 lowered kernels: no Float64, warm launches allocate nothing" begin
        function check32(cf; tables = Dict{Int32, Any}())
            s = semantic(cf.program)
            sp = plan(s)                                            # Float32 compute
            st = HostStore(s)
            # programs without the table ignore it
            foreach(((k, v),) -> k <= length(st.tables) && (st.tables[k] = v), tables)
            for l in sp.launches
                @test !has_f64(l.kernel.body)
                prep = prepare(s, l, st, cf.defaults; rt = (0.0, 0.1))
                run!(prep)
                @test (@allocated run!(prep)) == 0
            end
            return length(sp.launches)
        end
        function f32(sys, dims)
            return symbolic_discretize(
                sys, LatticeDiscretization(Grid(dims); T = Float32); update = euler
            )
        end
        offs = ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))
        mem = [ismember(kindₛ(t, x + a * dx, y + b * dy), (1,)) for (a, b) in offs]
        maprhs = ifelse(
            sum(mem) > 0,
            Dc * sum(m * N(t, x + a * dx, y + b * dy) for (m, (a, b)) in zip(mem, offs)) /
                sum(mem),
            Ne
        )
        systems = [
            pde(
                [D(ce) ~ Dc * laplacian(ce) - k * ce],
                [c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
                [ce], [Dc, k]
            ),
            pde([Shift(t, 1)(Ne) ~ maprhs], Equation[], [Ne, ke], [Dc, dx, dy]),
            pde(
                [D(ce) ~ laplacian(ce)],
                [ce ~ masked(ismember(ke, (2, 3)), g0), c(t, 0, y) ~ 0.0], [ce, ke], [g0]
            ),
            pde(
                [D(ce) ~ value_at(Dk, ke) + DivKGrad(:harmonic)(Ke, ce), Ke ~ K0 + sin(x)],
                Equation[], [ce, Ke, ke], [Dk, K0]
            ),
            pde(
                [D(ce) ~ -Advect(Upwind1())(vel(t, x, y), ce)], Equation[], [
                    ce, vel(t, x, y),
                ], Num[]
            ),
            pde(
                [D(ue[1]) ~ laplacian(ue[1]) - k * ue[2], D(ue[2]) ~ laplacian(ue[2])],
                [ue[2] ~ masked(ke == 3, 0.5)], [ue, ke], [k]
            ),
        ]
        for sys in systems
            @test check32(
                f32(sys, (16, 8)); tables = Dict{Int32, Any}(
                    Int32(1) =>
                        Float32[1, 2, 3]
                )
            ) >= 1
        end
    end
end

@testitem "refusals: faces, conditions and offsets" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "refusals: faces, conditions and offsets" begin
        g = LatticeDiscretization(Grid((4, 4)); T = Float64)
        fields = Dict{Any, Bool}(
            operation(unwrap(ce)) => false, operation(unwrap(ke)) =>
                true
        )
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
        sysb(bcs) = pde([D(ce) ~ laplacian(ce)], bcs, [ce, ke], Num[])
        # 2. one condition per face, mask and start
        for bcs in (
                [c(t, 0, y) ~ 1.0, Dx(c(t, 0, y)) ~ 0.0], [
                    ce ~ masked(ke == 3, 1.0), ce ~ masked(ke == 2, 0.0),
                ],
                [c(0, x, y) ~ 0.0, c(0, x, y) ~ 1.0],
            )
            @test throws_with(
                () -> symbolic_discretize(sysb(bcs), g),
                "already has a condition"
            )
        end
        @test symbolic_discretize(sysb([c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0]), g) isa
            CompiledField
        # 3. the left side: a time operator on the plain field read
        for (e, msg) in [
                [Dx(ce) ~ laplacian(ce)] => "time rate", [
                    Shift(x, 1)(Ne) ~
                        2 * Ne,
                ] => "in time",
                [D(c(t, 0, y)) ~ laplacian(ce)] => "time rate", [
                    Shift(t, 1)(N(t, x + dx, y)) ~
                        2 *
                        Ne,
                ] => "Shift(t, 1)(c(t, x, y))",
                [c(t, 0, y) ~ 1.0] => "field read",
            ]
            @test throws_with(
                () -> symbolic_discretize(pde(e, Equation[], [ce, Ne], [dx]), g), msg
            )
        end
        # 4. an offset needs a lattice_spacing parameter (x + 1 is a physical offset)
        @test throws_with(
            () -> symbolic_discretize(
                pde([Shift(t, 1)(Ne) ~ N(t, x + 1, y)], Equation[], [Ne], Num[]), g
            ),
            "lattice_spacing"
        )
        @test symbolic_discretize(
            pde([Shift(t, 1)(Ne) ~ N(t, x + dx, y)], Equation[], [Ne], [dx]), g
        ) isa
            CompiledField
        # 7. a Robin face whose ghost value is undefined (α/2 + β/h = 0: h = 1/4, β = 1/8 at
        #    the low face)
        @test throws_with(
            () -> symbolic_discretize(sysb([c(t, 0, y) + 0.125 * Dx(c(t, 0, y)) ~ 1.0]), g),
            "ghost value"
        )
        @test symbolic_discretize(sysb([c(t, 0, y) - 0.125 * Dx(c(t, 0, y)) ~ 1.0]), g) isa
            CompiledField
    end
end

@testitem "refusals: offsets, aux reads and initial values" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "refusals: offsets, aux reads and initial values" begin
        g = LatticeDiscretization(Grid((4, 4)); T = Float64)
        function map(r; ps = [dx])
            return () ->
            symbolic_discretize(pde([Shift(t, 1)(Ne) ~ r], Equation[], [Ne], ps), g)
        end
        # 1. an offset is `a * dx` exactly
        for r in (
                N(t, x + dx^2, y), N(t, x + 3dx * dx, y), N(t, x + 1 / dx, y), N(
                    t, x +
                        sqrt(dx), y
                ),
            )
            @test throws_with(map(r), "lattice")
        end
        @test map(N(t, x - 2dx, y))() isa CompiledField
        # 2. a term that reads an aux field is Other (its dependence on c is hidden)
        function lin(eqs, ps = Num[])
            return Set(
                last.(
                    symbolic_discretize(
                        pde(
                            eqs, Equation[], [
                                ce, Ke,
                            ], ps
                        ), g
                    ).linearity["c"]
                )
            )
        end
        @test lin([D(ce) ~ laplacian(ce) + Ke, Ke ~ ce^2]) == Set([:Diffusion, :Other])
        @test lin([D(ce) ~ laplacian(ce) + Dc * laplacian(Ke), Ke ~ ce^2], [Dc]) ==
            Set([:Diffusion, :Other])
        # 3. initial conditions: state fields only, values read no field
        @test throws_with(
            () -> symbolic_discretize(
                pde([D(ce) ~ laplacian(ce), Ke ~ ce], [K(0, x, y) ~ 3.0], [ce, Ke], Num[]),
                g
            ),
            "only rate and map fields"
        )
        @test throws_with(
            () -> symbolic_discretize(
                pde([D(ce) ~ laplacian(ce)], [c(0, x, y) ~ c(0, x, y) + 1], [ce], Num[]),
                g
            ),
            "cannot read a field"
        )
        @test throws_with(
            () -> symbolic_discretize(
                pde(
                    [D(ce) ~ laplacian(ce), D(oe) ~ laplacian(oe)], [
                        c(0, x, y) ~
                            o(0, x, y),
                    ], [ce, oe], Num[]
                ),
                g
            ),
            ""
            # refused by the parser (a field on each side)
        )
        @test symbolic_discretize(
            pde([D(ce) ~ laplacian(ce)], [c(0, x, y) ~ sin(x)], [ce], Num[]), g
        ) isa
            CompiledField
        # 4. an aux equation that reads its own field
        @test throws_with(
            () -> symbolic_discretize(
                pde([D(ce) ~ laplacian(ce), Ke ~ Ke + ce], Equation[], [ce, Ke], Num[]), g
            ),
            "cannot read itself"
        )
        # 5. the Robin check with a parameter coefficient (default 1/8 = h/2 at the low
        #    face)
        @parameters βr = 0.125
        @test throws_with(
            () -> symbolic_discretize(
                pde(
                    [D(ce) ~ laplacian(ce)], [c(t, 0, y) + βr * Dx(c(t, 0, y)) ~ 1.0], [ce],
                    [βr]
                ),
                g
            ),
            "ghost value"
        )
        # and an input multiplier of advection is Other, as of diffusion
        st, inp = [operation(unwrap(ce))],
            [operation(unwrap(ke)), operation(unwrap(vel(t, x, y)))]
        @test only(
            last.(
                LatticePDE.linearity(
                    ke * Advect(Upwind1())(vel(t, x, y), ce), ce, st; inputs = inp
                )
            )
        ) == :Other
        @test only(
            last.(
                LatticePDE.linearity(
                    Dc * Advect(Upwind1())(vel(t, x, y), ce), ce, st; inputs = inp
                )
            )
        ) == :Advection
    end
end

@testitem "state type: lanes per T, default by backend, refusals" setup = [
    LP_discretize,
] tags = [
    :latticepde, :discretize,
] begin
    @testset "state type: lanes per T, default by backend, refusals" begin
        sys = pde(
            [D(ce) ~ Dc * laplacian(ce) - k * ce],
            [c(t, 0, y) ~ 1.0, Dx(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [ce], [Dc, k]
        )
        function lanes(T)
            return [
                f.storage
                    for f in symbolic_discretize(
                        sys,
                        LatticeDiscretization(Grid((8, 4)); T);
                        update = euler
                    ).program.fields
                    if f.key == "c"
            ]
        end
        @test lanes(Float32) == [F32] && lanes(Float64) == [F64] && lanes(Float16) == [F16]
        # host problems fill F64 lanes with BigFloat
        @test lanes(BigFloat) == [F64]
        @test lanes(nothing) == [F64]                     # default on the host: Float64
        # negative control of the old mapping: T = BigFloat must not give F32 storage
        @test lanes(BigFloat) != [F32]
        err = throws_with(() -> lanes(Int), "not a state type")
        @test err
    end
end

# A Robin coefficient that is an expression of parameters is one value at every site,
# held by a computed parameter of its face (`c_x_low_α`); terms on one read add up (`g1 c +
# g2 c` kept only the last one, `g2`); a coefficient that reads the coordinates is a value
# field of its face (robin_site.jl). Before the fix (925110cc): 1 error, the expression
# refused ("the boundary value `g1 + g2` must be a number, …").
@testitem "a Robin coefficient of parameters" setup = [LP_discretize] tags = [
    :latticepde, :discretize,
] begin
    @testset "a Robin coefficient of parameters" begin
        @parameters g1 = 1.0 g2 = 2.0 ar = g1 + g2
        g = LatticeDiscretization(Grid((8, 8)); T = Float64)
        function sysr(bc, ps)
            return pde(
                [D(ce) ~ Dc * laplacian(ce)], [c(0, x, y) ~ 0.0, bc], [ce], [
                    Dc;
                    ps
                ]
            )
        end
        rhs(o) = (du = similar(o.u0); o.f(du, fill(0.5, length(o.u0)), o.p, 0.0); du)
        ref = discretize(sysr(ar * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0, [g1, g2, ar]), g)
        ex = discretize(sysr((g1 + g2) * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0, [g1, g2]), g)
        split = discretize(
            sysr(
                g1 * c(t, 0, y) + g2 * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0, [
                    g1, g2,
                ]
            ), g
        )
        @test rhs(ex) == rhs(ref) == rhs(split) && any(!iszero, rhs(ref))
        @test getp(ex, :c_x_low_α)(ex) == 3.0
        # it follows its parameters (read only, derived after a write)
        @test rhs(remake(ex; p = [g1 => 4.0])) == rhs(remake(ref; p = [g1 => 4.0])) !=
            rhs(ref)
        # β too; and a coefficient that reads a coordinate is refused
        exb = discretize(sysr(c(t, 0, y) - (g1 + g2) * Dx(c(t, 0, y)) ~ 1.0, [g1, g2]), g)
        # (the slot holds β of the outward ∂c/∂n, as A's `Robin`, on either face; the
        # written coefficient of ∂c/∂x on the low face is −β. Base 6d11bc85: −3.0)
        @test getp(exb, :c_x_low_β)(exb) == 3.0
        hib = discretize(sysr(c(t, 1, y) + (g1 + g2) * Dx(c(t, 1, y)) ~ 1.0, [g1, g2]), g)
        @test getp(hib, :c_x_high_β)(hib) == 3.0
        @test rhs(exb) ==
            rhs(discretize(sysr(c(t, 0, y) - ar * Dx(c(t, 0, y)) ~ 1.0, [g1, g2, ar]), g))
        # (one that reads a coordinate is a value field of the face, not a slot;
        # robin_site.jl)
        sy = discretize(sysr((g1 + y) * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0, [g1, g2]), g)
        @test any(
            r -> r isa LatticeFields.IR.FaceRule && r.afield != 0,
            LFP.field_problem(sy).program.rules
        )
    end
end
