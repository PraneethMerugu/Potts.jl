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
    # a PottsSystem is an AbstractSystem too (D-137), never a component key
    e = solver_err(() -> PottsProblem(cs, cop, (0, 2); solvers = [cs => RK4()]))
    @test e isa ArgumentError && occursin("Potts model", sprint(showerror, e))
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
    # regrouping of nested sums/products is read flattened (Symbolics' grouping is build-dependent)
    @test Potts._code_hash(Any[:(x + (y + z))]) == Potts._code_hash(Any[:(y + (z + x))])
    @test Potts._code_hash(Any[:(a * (b * c))]) == Potts._code_hash(Any[:((c * a) * b)])
    @test Potts._code_hash(Any[:(a * (b + c))]) != Potts._code_hash(Any[:(a * b + c)])   # nesting across operators kept
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

# Cross-cell reads in cell ODEs (P6.0n, beyond its frozen acceptance): `y[id]` is the cell's
# own unknown (it advances through the stages, no scratch); a gather whose body indexes cells
# reads the other cells' start-of-step state (Jacobi, scratch); a fold hoisted to a model
# slot needs no scratch. Two 4×4 cells side by side, x = 3:6 and 7:10.
p60n_two() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
@potts_model P60nOwnIndex begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -y[id]
    @sweep Metropolis(; temperature = 1.0e-6)
end
@potts_model P60nOwnPlain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -y
    @sweep Metropolis(; temperature = 1.0e-6)
end
# the gather is anchored at site (6, 4), on the interface: its Moore neighbours belong to
# both cells, so each cell reads the other's `y` (medium reads 0, below the positive values)
@potts_model P60nGather begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ maximum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - y
    @sweep Metropolis(; temperature = 1.0e-6)
end

@testset "P6.0n: y[id] is the own unknown, a gather over other cells is Jacobi" begin
    op(y) = [ownership => p60n_two(), kind => [:A, :A], :y => y]
    rk4 = 1 - 1 + 1 / 2 - 1 / 6 + 1 / 24                     # one RK4 step of y' = −y, h = 1
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        own = PottsProblem(P60nOwnIndex(; name = :o), op([1.0, 2.0]), (0, 2); ode_solver = RK4())
        plain = PottsProblem(P60nOwnPlain(; name = :o), op([1.0, 2.0]), (0, 2); ode_solver = RK4())
        @test !haskey(own.u0.cell, :y__ode)                   # an own read needs no scratch
        u = solve(own, alg).u[end].cell.y
        @test u == solve(plain, alg).u[end].cell.y
        # held at its start-of-step value, `y[id]` would give y + h·(−y) = 0 every step
        @test u ≈ [1.0, 2.0] .* rk4^2 && all(>(0), u)
        g = PottsProblem(P60nGather(; name = :g), op([1.0, 2.0]), (0, 3))
        @test haskey(g.u0.cell, :y__ode)
        traj = [Vector(x.cell.y) for x in solve(g, alg; saveat = 0:3).u]
        @test traj == [[1.0, 2.0], [2.0, 1.0], [1.0, 2.0], [2.0, 1.0]]    # Jacobi: swaps
        # (in place in cell order, cell 2 would read cell 1's new value: (2, 2) after one MCS)
        # (no allocation test here: a gather inside a cell-ODE rate allocates with or without
        # cross-cell reads, a separate defect; the frozen P6.0n file covers `y[j]` and folds)
    end
    # the detector: a hoisted fold or reads of non-ODE cell variables need no scratch
    @test !Potts._ode_reads_other_cells(mtkcompile(SolverPairYS(; name = :p)))
    @test Potts._ode_reads_other_cells(mtkcompile(P60nGather(; name = :g)))
    @test !Potts._ode_reads_other_cells(mtkcompile(P60nOwnIndex(; name = :o)))
end

# The index of a read is this cell's expression: it follows the stepped local, while the read
# variable is the stored one (P6.0n review round 2). Cell 1 (y = 0.4) reads w[2] = 1 until
# y > 0.5, then w[1] = 2: four Euler substeps of 1/4 give 0.65, 1.15, 1.65, 2.15; cell 2
# reads w[1] = 2, then w[2] = 1: 0.9, 1.15, 1.4, 1.65. (Indexing with the held y gives
# [1.4, 2.4].) `w` is not an ODE unknown, so there is no cross-cell read and no scratch.
@potts_model P60nIndexLocal begin
    @kinds medium A
    @variables begin
        y(cell) = 0.0
        w(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ w[ifelse(y > 0.5, id, 3 - id)]
    @sweep Metropolis(; temperature = 1.0e-6)
end

@testset "P6.0n: an index follows the stepped local" begin
    op = [ownership => p60n_two(), kind => [:A, :A], :y => [0.4, 0.4], :w => [2.0, 1.0]]
    prob = PottsProblem(P60nIndexLocal(; name = :d), op, (0, 1); ode_solver = ExplicitEuler(substeps = 4))
    @test !haskey(prob.u0.cell, :y__ode)
    @test !Potts._ode_reads_other_cells(mtkcompile(P60nIndexLocal(; name = :d)))
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        @test solve(prob, alg).u[end].cell.y ≈ [2.15, 1.65]
    end
end

# D-118: `mcs_duration` is data of a solver (`Adaptive`'s dt), not of the generated code, so
# the fingerprint hashes it when it is not 1.
function md_ode_model(md)
    @potts_model MdODE begin
        @kinds medium A
        @variables y(cell) = 1.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @equations D(y) ~ -y
        @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
    end
    MdODE(; name = :ad)
end
function md_field_model(md)
    @potts_model MdField begin
        @kinds medium A
        @variables c(field) = 0.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @equations D(c) ~ 0.1 * Δ(c) - 0.05 * c
        @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
    end
    MdField(; name = :fd)
end
@testset "D-118: a non-default mcs_duration is in the fingerprint" begin
    md_sigma() = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
    refused(p, ck) = try
        init(p, SequentialCPM(); checkpoint = ck); false
    catch e
        e isa ArgumentError
    end
    ad(md) = PottsProblem(md_ode_model(md), [ownership => md_sigma(), kind => [:A]], (0, 4);
        ode_solver = Adaptive(Tsit5(); reltol = 1e-10, abstol = 1e-12))
    a1, a2, ah = ad(1.0), ad(1.0), ad(0.5)
    # the runs differ: y = e^{-4} after 4 MCS of length 1, e^{-2} of length 0.5
    @test solve(a1, SequentialCPM()).u[end].cell.y[1] ≈ exp(-4) rtol = 1e-6
    @test solve(ah, SequentialCPM()).u[end].cell.y[1] ≈ exp(-2) rtol = 1e-6
    @test a1.f.fingerprint == a2.f.fingerprint                      # control: same schedule
    @test a1.f.fingerprint != ah.f.fingerprint
    i1 = init(a1, SequentialCPM()); step!(i1); step!(i1)
    ck = checkpoint(i1)
    @test refused(ah, ck)
    @test init(a2, SequentialCPM(); checkpoint = ck).t == i1.t      # control: same schedule loads
    # an explicit-substeps field step (no parameter bound): already distinct through its code;
    # kept as a regression guard
    fd(md) = PottsProblem(md_field_model(md), [ownership => md_sigma(), kind => [:A], :c => [Float64(x + y) for x in 1:12, y in 1:12]],
        (0, 3); field_solver = ExplicitEuler(substeps = 4))
    f1, fh = fd(1.0), fd(0.5)
    @test solve(f1, SequentialCPM()).u[end].site.c != solve(fh, SequentialCPM()).u[end].site.c
    @test f1.f.fingerprint == fd(1.0).f.fingerprint
    @test f1.f.fingerprint != fh.f.fingerprint
    j1 = init(f1, SequentialCPM()); step!(j1)
    @test refused(fh, checkpoint(j1))
    # the default `mcs_duration` adds nothing: an explicit 1.0 equals an unset one
    @test fd(1.0).f.fingerprint == PottsProblem(md_field_model(1), [ownership => md_sigma(), kind => [:A],
        :c => [Float64(x + y) for x in 1:12, y in 1:12]], (0, 3); field_solver = ExplicitEuler(substeps = 4)).f.fingerprint
end
# The fingerprint resolves the default proposal and contact neighbourhoods only to compare
# with them (D-122): on a thin periodic lattice where the default aliases (VonNeumann(1) on
# a 2- or 1-wide axis, a lattice `neighborhood = Moore(1)` overridden by a valid contact),
# a model with valid stencils still builds, runs and fingerprints deterministically.
function thin_model(dims, contact, nbhd)
    @potts_model ThinStrip begin
        @kinds medium A
        @lattice Lattice(dims; neighborhood = nbhd)
        @relations begin
            proposal = Stencil([[0, 1], [0, -1]])
            contact = contact
        end
        @energy cells => (volume - 4.0)^2
        @energy contacts => 1.0
        @sweep Metropolis(; temperature = 2.0)
    end
    ThinStrip(; name = :t)
end
@testset "D-122: thin lattices whose default neighbourhood aliases" begin
    line = Stencil([[0, 1], [0, -1]])
    line2 = Stencil([[0, 1], [0, -1], [0, 2], [0, -2]])
    for (dims, nbhd) in (((2, 12), VonNeumann(1)), ((1, 12), VonNeumann(1)), ((2, 12), Moore(1)))
        σ = zeros(Int32, dims); σ[:, 2:3] .= 1
        op = [ownership => σ, kind => [:A]]
        # control: the default itself does not resolve on this lattice
        @test_throws ArgumentError Potts.CorePotts.relation(VonNeumann(1), Potts.CorePotts.Lattice(dims))
        p = PottsProblem(thin_model(dims, line, nbhd), op, (0, 3); seed = 1)
        @test Symbol(solve(p, SequentialCPM()).retcode) === :Success
        @test PottsProblem(thin_model(dims, line, nbhd), op, (0, 3); seed = 1).f.fingerprint == p.f.fingerprint
        @test PottsProblem(thin_model(dims, line2, nbhd), op, (0, 3); seed = 1).f.fingerprint != p.f.fingerprint
    end
end

# `@sweep` validation beyond the frozen P6.0as acceptance (D-123, review round 1): `combine`
# is judged by the printed form that is hashed, so wrappers are checked through; non-Real
# offsets get the same `offset` error as non-finite ones.
struct SweepHolder{F}
    f::F
end
(h::SweepHolder)(a, b) = h.f(a, b)
struct SweepFnSub <: Function end
(::SweepFnSub)(a, b) = min(a, b)
struct SweepMix
    w::Float64
end
(m::SweepMix)(a, b) = m.w * a + (1 - m.w) * b
@testset "@sweep: combine judged by its printed form; offset must be a finite Real" begin
    spec(; kw...) = Potts.sweep_spec(:metropolis; temperature = 1.0, kw...)
    function argerr(f)
        try
            f()
        catch e
            return e
        end
        return nothing
    end
    anon = (a, b) -> a
    for c in (anon, Base.Fix2(anon, 1), SweepHolder(anon), SweepHolder(SweepHolder(anon)))
        e = argerr(() -> spec(combine = c))
        @test e isa ArgumentError && occursin("combine", e.msg) && occursin("callable struct", e.msg)
    end
    for c in (min, max, min ∘ max, splat(min), SweepFnSub(), SweepMix(0.7), SweepHolder(min), Base.Fix2(min, 1))
        @test spec(combine = c).combine === c
    end
    for o in (:a, "1", nothing, 1 + 1im, NaN, Inf32, -Inf)
        e = argerr(() -> spec(offset = o))
        @test e isa ArgumentError && occursin("offset", e.msg)
    end
    @test spec(offset = 2).offset === 2.0 && spec(offset = -1.5f0).offset === -1.5
end

# `mcs_duration` validation beyond the frozen P6.0av acceptance (D-126): the `offset`,
# `combine` and `mcs_duration` checks also live in the `SweepSpec` constructor, so a hand-built
# spec passed to `PottsSystem(; sweep)` cannot bypass them, and its errors are those of `@sweep`.
@testset "@sweep: mcs_duration validated; a hand-built SweepSpec is checked too" begin
    spec(; kw...) = Potts.sweep_spec(:metropolis; temperature = 1.0, kw...)
    hand(o, md) = Potts.SweepSpec(:metropolis, 1.0, min, o, md)
    sys(sw) = Potts.PottsSystem(; name = :hand, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
        energies = [Potts.energy(Potts.cells(1) => (Potts.B.volume - 9.0)^2)], sweep = sw)
    function argerr(f)
        try
            f()
        catch e
            return e
        end
        return nothing
    end
    isoff(e) = e isa ArgumentError && occursin("`@sweep`", e.msg) && occursin("`offset`", e.msg)
    ismd(e) = e isa ArgumentError && occursin("`@sweep`", e.msg) && occursin("`mcs_duration`", e.msg) &&
              occursin("positive, finite", e.msg)
    bad_md = (NaN, Inf, -Inf, NaN32, Inf32, 0, 0.0, -0.0, -1, -0.5f0, big"1e400", big"1e-400",
              :a, "1", nothing, 1 + 1im)
    for md in bad_md
        @test ismd(argerr(() -> spec(mcs_duration = md)))
        @test ismd(argerr(() -> hand(0.0, md)))
        @test ismd(argerr(() -> sys(hand(0.0, md))))
    end
    for o in (NaN, Inf32, -Inf, big"1e400", :a, "1", 1 + 1im)
        @test isoff(argerr(() -> spec(offset = o)))
        @test isoff(argerr(() -> hand(o, 1.0)))
        @test isoff(argerr(() -> sys(hand(o, 1.0))))
    end
    # an unstable `combine` is rejected by hand too; a named or callable-struct one is accepted
    iscomb(e) = e isa ArgumentError && occursin("`@sweep`", e.msg) && occursin("`combine`", e.msg)
    anon = (a, b) -> a
    for c in (anon, Base.Fix2(anon, 1))
        @test iscomb(argerr(() -> Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0)))
        @test iscomb(argerr(() -> sys(Potts.SweepSpec(:barker, 1.0, c, 0.0, 1.0))))
    end
    for c in (max, SweepMix(0.3), Base.Fix2(min, 1))
        @test Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0).combine === c
        @test getfield(sys(Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0)), :sweep).combine === c
    end
    # the order of `@sweep`'s checks: offset, then combine, then mcs_duration
    @test isoff(argerr(() -> spec(offset = NaN, combine = anon, mcs_duration = 0)))
    @test iscomb(argerr(() -> spec(combine = anon, mcs_duration = 0)))
    @test isoff(argerr(() -> Potts.SweepSpec(:metropolis, 1.0, anon, NaN, 0)))
    # accepted values are stored as Float64, by `@sweep` and by hand alike
    for md in (1, 0.5f0, 3 // 2, big"0.25", 1e300, floatmin(Float64), nextfloat(0.0))
        @test spec(mcs_duration = md).mcs_duration === Float64(md)
        @test hand(2, md).mcs_duration === Float64(md) && hand(2, md).offset === 2.0
    end
    # control: a valid hand-built spec builds, compiles, and fingerprints like the `@sweep` one
    good = sys(hand(0, 0.5))
    @test getfield(good, :sweep).mcs_duration === 0.5
    fp(sw) = (σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1;
              PottsProblem(mtkcompile(sys(sw)), [ownership => σ, kind => [:A]], (0, 2)).f.fingerprint)
    @test fp(hand(0, 0.5)) == fp(spec(mcs_duration = 0.5))
    @test fp(hand(0, 0.5)) != fp(spec(mcs_duration = 0.25))                     # control
end

# D-130: a value too deep (or cyclic) for the canonical printer, met outside the solvers, is
# an `ArgumentError` naming the part, never the private `_CanonicalDepthError`
struct SolverDeep
    a::Any
end
solver_nest(k) = k == 0 ? 1.0 : SolverDeep(solver_nest(k - 1))
"""A model with an inline gather relation whose weight closure captures `solver_nest(k)`,
compiled; returns the compiled system or the unwrapped exception."""
function solver_deep_relation(k)
    nm = Symbol(:SolverDeepRel, k)
    R = let d = solver_nest(k)
        Weighted(Moore(1), o -> d isa SolverDeep ? 1.0 : 2.0)
    end
    compiled = Ref{Any}(nothing)
    e = solver_err() do
        Core.eval(@__MODULE__, quote
            @potts_model $nm begin
                @kinds medium A
                @variables q(site) = 0.0
                @lattice Lattice((12, 12))
                # a static-value gather (D-209 refuses `owner[n]` in an energy gather)
                @energy cells => (volume - 9.0)^2 + 0.1 * volume * sum(q[n] for n in $R(40))
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        sys = Base.invokelatest(Base.invokelatest(getglobal, @__MODULE__, nm); name = :x)
        compiled[] = mtkcompile(sys)
    end
    e === nothing && return compiled[]
    while e isa LoadError
        e = e.error
    end
    return e
end

@testset "D-130: values too deep outside the solvers are an ArgumentError naming the part" begin
    deep = solver_deep_relation(9)
    @test deep isa ArgumentError
    @test deep isa ArgumentError && occursin("relation", deep.msg) && occursin("nested deeper", deep.msg)
    # control: the same relation within the cap compiles and runs
    ok = solver_deep_relation(3)
    @test ok isa Potts.CompiledPottsSystem
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    @test Symbol(solve(PottsProblem(ok, [ownership => σ, kind => [:A]], (0, 2)), SequentialCPM()).retcode) === :Success
    # a constant in an expression key (`_symkey`): too deep names it, within the cap prints
    e = solver_err(() -> Potts._symkey(solver_nest(12)))
    @test e isa ArgumentError && occursin("symbolic constant", e.msg)
    @test Potts._symkey(solver_nest(3)) isa String
    cyc = Ref{Any}(nothing)
    cyc[] = cyc
    @test solver_err(() -> Potts._symkey(cyc)) isa ArgumentError
end

# D-208: CheckerboardCPM's reach counts only the relations the generated copy-step functions
# read, and only while the problem runs those functions. A `CPMFunction` keeping the model's
# `sys` but swapping in a function of its own may read any relation: every one counts.
@potts_model ReachBoundaryFar begin
    @kinds medium A
    @variables z(cell) = 0.0
    @lattice Lattice((12, 12))
    @relations far = Ball(2.0)
    @energy cells => (volume - 9.0)^2
    @after_mcs z ~ count(owner[n] == id for n in far(40))
    @sweep Metropolis(; temperature = 2.0)
end

@testset "D-208: copy-step relations follow the functions, not only the model" begin
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[6:8, 2:4] .= 2
    prob = PottsProblem(ReachBoundaryFar(; name = :rb), [ownership => σ, kind => [:A, :A]], (0, 3); seed = 1, capacity = 8)
    f = prob.f
    @test f.footprint.read == 1
    @test Potts.CorePotts.radius(prob.relations.far) == 2
    @test !(:far in Potts.CorePotts.copy_step_relations(f.sys, f))       # read only after the MCS
    @test Symbol(solve(prob, CheckerboardCPM()).retcode) === :Success
    # `anneal` (zero temperature around the generated one) keeps the generated reads
    @test Potts.anneal(prob; mcs = 2, alg = CheckerboardCPM()) isa Potts.CorePotts.CPMState
    # a bias reading `far` (reach 2) against footprint 1: refused, not raced
    farbias = (st, p, prop, ctx) -> length(ctx.far) < 0
    biased = Potts.CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads, f.temperature,
        bias = farbias, f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
    @test Potts.CorePotts.copy_step_relations(f.sys, biased) === nothing
    @test_throws ArgumentError solve(remake(prob; f = biased), CheckerboardCPM())
    @test Symbol(solve(remake(prob; f = biased), SequentialCPM()).retcode) === :Success
    # a swapped ΔH (or temperature) likewise
    dH = (st, p, prop, ctx) -> f.delta_H(st, p, prop, ctx) + 0.0 * length(ctx.far)
    swapped = Potts.CorePotts.CPMFunction(dH; f.commit!, f.constraint, f.claims, f.reads, f.temperature,
        f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
    @test_throws ArgumentError solve(remake(prob; f = swapped), CheckerboardCPM())
    Tswap = Potts.CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads,
        temperature = (st, p, prop, ctx) -> 2.0, f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
    @test Potts.CorePotts.copy_step_relations(f.sys, Tswap) === nothing
end
