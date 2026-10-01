# Solver placement beyond the frozen P6.0c acceptance (D-075; review round 1): Jacobi across
# solver groups (scratch `x__ode`), keys (names, components), canonical strings, the remake
# hook's edges, and fingerprints independent of the checkout path.
using OrdinaryDiffEqTsit5: Tsit5

# y' = −s, s' = y − s, listed in both orders. With `s => RK4()` and y under explicit Euler
# the two run in separate groups; Jacobi means each step reads (y, s) at its start.
@potts_model SolverPairYS begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -s
        D(s) ~ y - s
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model SolverPairSY begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(s) ~ y - s
        D(y) ~ -s
    end
    @sweep Metropolis(; temperature = 1.0)
end

# three groups in the cell scope (Euler, RK4, adaptive) and two in the model scope
@potts_model SolverTriple begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
        w(cell) = 0.5
        g(model) = 1.0
        h(model) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -s
        D(s) ~ y - s
        D(w) ~ -0.2 * w + 0.1 * y
        D(g) ~ -h
        D(h) ~ g - h
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model SolverField begin
    @kinds medium A
    @parameters Dc = 0.1
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) - 0.05 * c
    @sweep Metropolis(; temperature = 1.0)
end

solver_sigma() = (σ = zeros(Int32, 16, 16); σ[5:8, 5:8] .= 1; σ)
solver_op() = [ownership => solver_sigma(), kind => [:A]]
solver_var(sys, n) = only(filter(x -> string(x) in (string(n), string(n, "(t)")), variables(sys)))
solver_err(f) = try
    f(); nothing
catch e
    e
end
# RK4 over one step h = 1 of s' = y − s with y frozen: s ← y + (s − y)·(1 − 1 + 1/2 − 1/6 + 1/24)
const RK4_DECAY = 1 - 1 + 1 / 2 - 1 / 6 + 1 / 24
function pair_oracle(n)
    y, s = 1.0, 0.0
    for _ in 1:n
        y, s = y - s, y + (s - y) * RK4_DECAY            # Jacobi: both from the pre-step state
    end
    return y, s
end
solver_warm(integ) = (step!(integ); @allocated step!(integ))

@testset "solver groups are Jacobi, independent of equation order" begin
    n = 4
    oy, os = pair_oracle(n)
    for M in (SolverPairYS, SolverPairSY), alg in (SequentialCPM(), CheckerboardCPM())
        sys = M(; name = :p)
        prob = PottsProblem(sys, solver_op(), (0, n); solvers = [solver_var(sys, :s) => RK4()])
        @test haskey(prob.u0.cell, :y__ode) && haskey(prob.u0.cell, :s__ode)          # two groups: scratch
        u = solve(prob, alg).u[end]
        @test u.cell.y[1] ≈ oy rtol = 1e-12
        @test u.cell.s[1] ≈ os rtol = 1e-12
    end
    # one group: no scratch, and `ExplicitEuler(substeps = 1)` is the default `ExplicitEuler()`
    sys = SolverPairYS(; name = :p)
    one = PottsProblem(sys, solver_op(), (0, n))
    same = PottsProblem(sys, solver_op(), (0, n); solvers = [solver_var(sys, :s) => ExplicitEuler(substeps = 1)])
    @test !any(k -> endswith(String(k), "__ode"), keys(one.u0.cell))
    @test keys(same.u0.cell) == keys(one.u0.cell) && same.f.fingerprint == one.f.fingerprint
    @test length(same.f.phases.after_mcs) == length(one.f.phases.after_mcs)
    @test solve(same, SequentialCPM()).u[end].cell.s == solve(one, SequentialCPM()).u[end].cell.s
    # three cell groups (one adaptive) and two model groups: every rate reads the pre-step state
    sys = SolverTriple(; name = :t)
    v(n) = solver_var(sys, n)
    prob = PottsProblem(sys, solver_op(), (0, 3); solvers = [v(:s) => RK4(), v(:h) => RK4(),
        v(:w) => Adaptive(Tsit5(); reltol = 1e-12, abstol = 1e-14)])
    y, s, w, g, h = 1.0, 0.0, 0.5, 1.0, 0.0
    for _ in 1:3
        # w' = −0.2 w + 0.1 y with y frozen at its pre-step value: exact
        w = 0.5y + (w - 0.5y) * exp(-0.2)
        y, s = y - s, y + (s - y) * RK4_DECAY
        g, h = g - h, g + (h - g) * RK4_DECAY
    end
    for alg in (SequentialCPM(), CheckerboardCPM())
        u = solve(prob, alg).u[end]
        @test all(isapprox.((u.cell.y[1], u.cell.s[1], u.model.g[1], u.model.h[1]), (y, s, g, h); rtol = 1e-12))
        @test u.cell.w[1] ≈ w rtol = 1e-9
    end
end

@testset "solver groups: zero warm allocations, remake re-lays out the scratch" begin
    sys = SolverTriple(; name = :t)
    v(n) = solver_var(sys, n)
    prob = PottsProblem(sys, solver_op(), (0, 100); solvers = [v(:s) => RK4(), v(:h) => RK4()])
    for alg in (SequentialCPM(), CheckerboardCPM())
        integ = init(prob, alg; save_start = false, save_end = false)
        @test minimum(solver_warm(integ) for _ in 1:5) == 0
    end
    # one group → two groups → one group: the state gains and loses its scratch, values kept
    base = PottsProblem(sys, solver_op(), (0, 3))
    split = remake(base; solvers = [v(:s) => RK4()])
    @test haskey(split.u0.cell, :s__ode) && !haskey(split.u0.model, :g__ode)
    @test split.u0.cell.s == base.u0.cell.s
    direct = PottsProblem(sys, solver_op(), (0, 3); solvers = [v(:s) => RK4()])
    @test split.f.fingerprint == direct.f.fingerprint
    @test solve(split, SequentialCPM()).u[end].cell == solve(direct, SequentialCPM()).u[end].cell
    back = remake(split; solvers = [])
    @test keys(back.u0.cell) == keys(base.u0.cell) && back.f.fingerprint == base.f.fingerprint
    # remake with u0 and solvers together lays out the new state for the new solvers
    both = remake(base; solvers = [v(:s) => RK4()], u0 = [ownership => solver_sigma(), kind => [:A], :y => 2.0])
    @test haskey(both.u0.cell, :s__ode) && both.u0.cell.y[1] == 2.0
end

@testset "solvers keys: names, fields, components; errors" begin
    sys = SolverPairYS(; name = :p)
    bysym = PottsProblem(sys, solver_op(), (0, 2); solvers = [:s => RK4()])
    byvar = PottsProblem(sys, solver_op(), (0, 2); solvers = [solver_var(sys, :s) => RK4()])
    @test bysym.f.fingerprint == byvar.f.fingerprint
    @test solver_err(() -> PottsProblem(sys, solver_op(), (0, 2); solvers = [:nope => RK4()])) isa ArgumentError
    @test solver_err(() -> PottsProblem(sys, solver_op(), (0, 2); solvers = [:s => RK4(), :s => RK4()])) isa ArgumentError
    # a field key takes an ExplicitEuler, which overrides `field_solver` for that field
    fs = SolverField(; name = :f)
    op = [ownership => solver_sigma(), kind => [:A], :c => [Float64(x + y) for x in 1:16, y in 1:16]]
    e = solver_err(() -> PottsProblem(fs, op, (0, 2); field_solver = ExplicitEuler(), solvers = [:c => RK4()]))
    @test e isa ArgumentError && occursin("ExplicitEuler", sprint(showerror, e))
    keyed = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 2), solvers = [:c => ExplicitEuler(substeps = 5)])
    plain = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 5))
    @test keyed.f.fingerprint == plain.f.fingerprint
    @test solve(keyed, SequentialCPM()).u[end].site.c == solve(plain, SequentialCPM()).u[end].site.c
    two = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 2))
    @test two.f.fingerprint != plain.f.fingerprint                                           # negative control
    # `field_solver` is still required when `solvers` covers every field
    @test solver_err(() -> PottsProblem(fs, op, (0, 2); solvers = [:c => ExplicitEuler()])) isa ArgumentError
    # components: the system (all its integrated unknowns), `comp.x`, or `Symbol("comp₊x")`
    cs = component_model()
    cop = [ownership => (σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2; σ), kind => [:A, :B]]
    fp(kw) = PottsProblem(cs, cop, (0, 2); solvers = kw).f.fingerprint
    @test fp([decay => RK4()]) == fp([decay.y_c => RK4()]) == fp([Symbol("decay₊y_c") => RK4()])
    @test fp([clock => RK4()]) == fp([clock.m_c => RK4()]) != fp([decay => RK4()])
    @test fp([decay => RK4()]) != PottsProblem(cs, cop, (0, 2)).f.fingerprint
    @named lonely = System([Potts.D(y_c) ~ -y_c], _tc)
    e = solver_err(() -> PottsProblem(cs, cop, (0, 2); solvers = [lonely => RK4()]))
    @test e isa ArgumentError && occursin("`lonely`", sprint(showerror, e)) && length(sprint(showerror, e)) < 300
    # unknown keywords: `@sweep`, `remake`; `f` together with a solver keyword
    @test solver_err(() -> Potts.sweep_spec(:metropolis; temperature = 1.0, substeps = 2)) isa ArgumentError
    @test occursin("PottsProblem", sprint(showerror, solver_err(() -> Potts.sweep_spec(:metropolis; temperature = 1.0,
        ode_solver = RK4()))))
    e = solver_err(() -> remake(bysym; nope = 1))
    @test e isa ArgumentError && occursin("nope", sprint(showerror, e))
    @test solver_err(() -> remake(bysym; f = byvar.f, ode_solver = RK4())) isa ArgumentError
end

@enum SolverPredictor SolverTrivial SolverLinear
struct SolverFakeAlg{P, F, K}
    predictor::P
    limiter::F
    knobs::K
end
solver_limiter(c) = (u, i, p, t) -> (u .= max.(u, c); nothing)

@testset "canonical solver strings: no collisions, no host details" begin
    canon(x) = Potts._canonical(Adaptive(x))
    @test canon(SolverFakeAlg(SolverTrivial, nothing, ())) != canon(SolverFakeAlg(SolverLinear, nothing, ()))       # enums
    @test canon(SolverFakeAlg('a', nothing, ())) != canon(SolverFakeAlg('b', nothing, ()))                          # primitives
    @test canon(SolverFakeAlg(nothing, solver_limiter(0.0), ())) != canon(SolverFakeAlg(nothing, solver_limiter(5.0), ()))   # captures
    @test canon(SolverFakeAlg(nothing, solver_limiter(1.0), ())) == canon(SolverFakeAlg(nothing, solver_limiter(1.0), ()))
    @test canon(SolverFakeAlg(nothing, nothing, 1:3)) != canon(SolverFakeAlg(nothing, nothing, [1, 2, 3]))             # ranges
    @test canon(SolverFakeAlg(nothing, nothing, Float64[])) != canon(SolverFakeAlg(nothing, nothing, Int[]))         # element types
    d1 = Dict(:a => 1, :b => 2, :c => 3); d2 = Dict(:c => 3, :b => 2, :a => 1)
    @test canon(SolverFakeAlg(nothing, nothing, d1)) == canon(SolverFakeAlg(nothing, nothing, d2))                   # no hash slots
    @test canon(SolverFakeAlg(nothing, nothing, d1)) != canon(SolverFakeAlg(nothing, nothing, Dict(:a => 1, :b => 2, :c => 4)))
    @test Potts._canonical(Adaptive(Tsit5(); reltol = 1e-6, abstol = 1e-8)) ==
          Potts._canonical(Adaptive(Tsit5(); abstol = 1e-8, reltol = 1e-6))                                         # sorted kwargs
    # solvers that differ only in a closure's captures never share a phase
    sys = SolverPairYS(; name = :p)
    prob = PottsProblem(sys, solver_op(), (0, 2); solvers = [
        :y => Adaptive(Tsit5(step_limiter! = solver_limiter(-10.0))), :s => Adaptive(Tsit5(step_limiter! = solver_limiter(5.0)))])
    @test count(ph -> ph isa Potts._AdaptiveODE, prob.f.phases.after_mcs) == 2
    @test solve(prob, SequentialCPM()).u[end].cell.s[1] == 5.0                     # its own limiter
end

@testset "D-016: fingerprints do not depend on the checkout path" begin
    exprs = Any[values(Base.structdiff(generated_code(SolverPairYS(; name = :p)), (; phases = nothing)))...]
    append!(exprs, generated_code(SolverPairYS(; name = :p)).phases)
    exprs = filter(!isnothing, exprs)
    moved(ex) = ex isa LineNumberNode ? LineNumberNode(ex.line + 100, Symbol("/elsewhere/src/codegen.jl")) :
                ex isa Expr ? Expr(ex.head, map(moved, ex.args)...) : ex
    hasmacroline(ex) = ex isa Expr && ((ex.head === :macrocall && ex.args[2] isa LineNumberNode) || any(hasmacroline, ex.args))
    @test any(hasmacroline, exprs)                                   # the case the hash must ignore
    @test Potts._code_hash(exprs) == Potts._code_hash(map(moved, exprs))
    @test Potts._code_hash(exprs) != Potts._code_hash(exprs[2:end])  # negative control
    # Symbolics' term order is build dependent: sums and products hash in a canonical order
    @test Potts._code_hash([:(f(x) = (+)(a, (*)(-1, b), c))]) == Potts._code_hash([:(f(x) = (+)(c, a, (*)(b, -1)))])
    @test Potts._code_hash([:(f(x) = (-)(a, b))]) != Potts._code_hash([:(f(x) = (-)(b, a))])
end

@testset "states given as such are laid out for the scratch (remake, reinit!)" begin
    sys = SolverPairYS(; name = :p)
    multi = PottsProblem(sys, solver_op(), (0, 4); solvers = [:s => RK4()])
    single = PottsProblem(sys, solver_op(), (0, 4))
    plain = solve(single, SequentialCPM()).u[end]                     # a state without scratch
    @test !haskey(plain.cell, :s__ode)
    # R1: remake of a multi-group problem with a scratchless state
    r1 = remake(multi; u0 = plain)
    @test haskey(r1.u0.cell, :s__ode) && r1.u0.cell.s == plain.cell.s
    @test solve(r1, SequentialCPM()).t[end] == 4
    # R2: reinit! with a scratchless state
    integ = init(multi, SequentialCPM()); step!(integ)
    reinit!(integ, plain)
    @test integ.u.cell.y == plain.cell.y && haskey(integ.u.cell, :s__ode)
    # R3: a solver remake together with a state
    r3 = remake(single; solvers = [:s => RK4()], u0 = plain)
    @test haskey(r3.u0.cell, :s__ode) && r3.f.fingerprint == multi.f.fingerprint
    @test solve(r3, SequentialCPM()).u[end].cell.s == solve(remake(multi; u0 = plain), SequentialCPM()).u[end].cell.s
    # and back: a scratch state into a single-group problem loses the scratch
    @test !haskey(remake(single; u0 = solve(multi, SequentialCPM()).u[end]).u0.cell, :s__ode)
    # an incompatible state names what differs
    e = solver_err(() -> reinit!(init(single, SequentialCPM()), Potts.CorePotts.with_capacity(plain, 9)))
    @test e isa ArgumentError
end

@testset "internal slot suffixes are reserved for declared names" begin
    for suf in ("__ode", "__tick", "__next")
        nm = Symbol(:SuffixClash, suf)
        e = solver_err() do
            Core.eval(@__MODULE__, quote
                @potts_model $nm begin
                    @kinds medium A
                    @variables $(Symbol(:q, suf))(cell) = 1.0
                    @lattice Lattice((8, 8))
                    @energy cells => (volume - 9.0)^2
                    @sweep Metropolis(; temperature = 1.0)
                end
            end)
            Base.invokelatest(Base.invokelatest(getglobal, @__MODULE__, nm); name = :x)
        end
        while e isa LoadError
            e = e.error
        end
        @test e isa ArgumentError && occursin(suf, sprint(showerror, e))
    end
end

@testset "equal specifications share a phase and a fingerprint" begin
    sys = SolverPairYS(; name = :p)
    A() = Adaptive(Tsit5(); abstol = [1e-8, 1e-8], reltol = 1e-8)
    @test !isequal(A(), A())                                         # fresh, not egal
    whole = PottsProblem(sys, solver_op(), (0, 2); ode_solver = A())
    split = PottsProblem(sys, solver_op(), (0, 2); solvers = [:y => A(), :s => A()])
    @test split.f.fingerprint == whole.f.fingerprint
    @test count(ph -> ph isa Potts._AdaptiveODE, split.f.phases.after_mcs) == 1
    @test keys(split.u0.cell) == keys(whole.u0.cell)
    @test solve(split, SequentialCPM()).u[end].cell.s == solve(whole, SequentialCPM()).u[end].cell.s
end

@testset "D-016: the structural seed is a canonical string" begin
    gg = graner_state()
    sys = mtkcompile(GranerGlazier(; name = :gg))
    seed = Potts._fingerprint_seed(sys.sys, Float64)
    @test seed isa String && occursin("T=Float64", seed) && occursin("Moore", seed)
    @test !occursin("0x", seed)                                       # no addresses
    p64 = PottsProblem(sys, [ownership => gg[1], kind => gg[2]], (0, 1))
    p32 = PottsProblem(sys, [ownership => gg[1], kind => gg[2]], (0, 1); T = Float32)
    @test p64.f.fingerprint != p32.f.fingerprint
    @test Potts._fingerprint_seed(mtkcompile(SolverPairYS(; name = :p)).sys, Float64) != seed
    @test Potts._fingerprint_seed(mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))).sys, Float64) !=
          Potts._fingerprint_seed(mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (30, 30))).sys, Float64)
end
