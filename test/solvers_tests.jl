# Core solver placement beyond frozen P6.0c: Jacobi across groups, scratch layouts, solver keys,
# P6.0n cross-cell reads, and D-208 copy-step reach. Setup lives in `solvers_testsetup.jl`.

@testitem "solver groups are Jacobi, independent of equation order" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "solver groups are Jacobi, independent of equation order" begin
        n = 4
        oy, os = pair_oracle(n)
        for M in (SolverPairYS, SolverPairSY), alg in (SequentialCPM(), CheckerboardCPM())
            sys = M(; name = :p)
            prob = PottsProblem(sys, solver_op(), (0, n); solvers = [solver_var(sys, :s) => Potts.RK4()])
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
        prob = PottsProblem(sys, solver_op(), (0, 3); solvers = [v(:s) => Potts.RK4(), v(:h) => Potts.RK4(),
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
end

@testitem "solver groups: zero warm allocations, remake re-lays out the scratch" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "solver groups: zero warm allocations, remake re-lays out the scratch" begin
        sys = SolverTriple(; name = :t)
        v(n) = solver_var(sys, n)
        prob = PottsProblem(sys, solver_op(), (0, 100); solvers = [v(:s) => Potts.RK4(), v(:h) => Potts.RK4()])
        for alg in (SequentialCPM(), CheckerboardCPM())
            integ = init(prob, alg; save_start = false, save_end = false, save_everystep = false)
            @test minimum(solver_warm(integ) for _ in 1:5) == 0
        end
        # one group → two groups → one group: the state gains and loses its scratch, values kept
        base = PottsProblem(sys, solver_op(), (0, 3))
        split = remake(base; solvers = [v(:s) => Potts.RK4()])
        @test haskey(split.u0.cell, :s__ode) && !haskey(split.u0.model, :g__ode)
        @test split.u0.cell.s == base.u0.cell.s
        direct = PottsProblem(sys, solver_op(), (0, 3); solvers = [v(:s) => Potts.RK4()])
        @test split.f.fingerprint == direct.f.fingerprint
        @test solve(split, SequentialCPM()).u[end].cell == solve(direct, SequentialCPM()).u[end].cell
        back = remake(split; solvers = [])
        @test keys(back.u0.cell) == keys(base.u0.cell) && back.f.fingerprint == base.f.fingerprint
        # remake with u0 and solvers together lays out the new state for the new solvers
        both = remake(base; solvers = [v(:s) => Potts.RK4()], u0 = [ownership => solver_sigma(), kind => [:A], :y => 2.0])
        @test haskey(both.u0.cell, :s__ode) && both.u0.cell.y[1] == 2.0
    end
end

@testitem "solvers keys: names, fields, components; errors" setup = [SolversSetup, SymbolicSetup] tags = [:potts, :solvers] begin
    @testset "solvers keys: names, fields, components; errors" begin
        sys = SolverPairYS(; name = :p)
        bysym = PottsProblem(sys, solver_op(), (0, 2); solvers = [:s => Potts.RK4()])
        byvar = PottsProblem(sys, solver_op(), (0, 2); solvers = [solver_var(sys, :s) => Potts.RK4()])
        @test bysym.f.fingerprint == byvar.f.fingerprint
        @test solver_err(() -> PottsProblem(sys, solver_op(), (0, 2); solvers = [:nope => Potts.RK4()])) isa ArgumentError
        @test solver_err(() -> PottsProblem(sys, solver_op(), (0, 2); solvers = [:s => Potts.RK4(), :s => Potts.RK4()])) isa ArgumentError
        # a field key takes an ExplicitEuler, which overrides `field_solver` for that field
        fs = SolverField(; name = :f)
        op = [ownership => solver_sigma(), kind => [:A], :c => [Float64(x + y) for x in 1:16, y in 1:16]]
        e = solver_err(() -> PottsProblem(fs, op, (0, 2); field_solver = ExplicitEuler(), solvers = [:c => Potts.RK4()]))
        @test e isa ArgumentError && occursin("ExplicitEuler", sprint(showerror, e))
        keyed = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 2), solvers = [:c => ExplicitEuler(substeps = 5)])
        plain = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 5))
        @test keyed.f.fingerprint == plain.f.fingerprint
        @test solve(keyed, SequentialCPM()).u[end].site.c == solve(plain, SequentialCPM()).u[end].site.c
        two = PottsProblem(fs, op, (0, 3); field_solver = ExplicitEuler(substeps = 2))
        @test two.f.fingerprint != plain.f.fingerprint                                           # negative control
        # with `solvers` covering every field, `field_solver` takes its default (D-F2-R1)
        @test PottsProblem(fs, op, (0, 2); solvers = [:c => ExplicitEuler()]).f.fingerprint ==
              PottsProblem(fs, op, (0, 2); field_solver = ExplicitEuler(), solvers = [:c => ExplicitEuler()]).f.fingerprint
        # components: the system (all its integrated unknowns), `comp.x`, or `Symbol("comp₊x")`
        cs = component_model()
        cop = [ownership => (σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2; σ), kind => [:A, :B]]
        fp(kw) = PottsProblem(cs, cop, (0, 2); solvers = kw).f.fingerprint
        @test fp([decay => Potts.RK4()]) == fp([decay.y_c => Potts.RK4()]) == fp([Symbol("decay₊y_c") => Potts.RK4()])
        @test fp([clock => Potts.RK4()]) == fp([clock.m_c => Potts.RK4()]) != fp([decay => Potts.RK4()])
        @test fp([decay => Potts.RK4()]) != PottsProblem(cs, cop, (0, 2)).f.fingerprint
        @named lonely = System([Potts.D(y_c) ~ -y_c], _tc)
        e = solver_err(() -> PottsProblem(cs, cop, (0, 2); solvers = [lonely => Potts.RK4()]))
        @test e isa ArgumentError && occursin("`lonely`", sprint(showerror, e)) && length(sprint(showerror, e)) < 300
        # a PottsSystem is an AbstractSystem too (D-137), never a component key
        e = solver_err(() -> PottsProblem(cs, cop, (0, 2); solvers = [cs => Potts.RK4()]))
        @test e isa ArgumentError && occursin("Potts model", sprint(showerror, e))
        # unknown keywords: `@sweep`, `remake`; `f` together with a solver keyword
        @test solver_err(() -> Potts.sweep_spec(:metropolis; temperature = 1.0, substeps = 2)) isa ArgumentError
        e = solver_err(() -> Potts.sweep_spec(:metropolis; temperature = 1.0, ode_solver = Potts.RK4()))
        @test e isa ArgumentError && occursin("ode_solver", sprint(showerror, e))
        e = solver_err(() -> remake(bysym; nope = 1))
        @test e isa ArgumentError && occursin("nope", sprint(showerror, e))
        @test solver_err(() -> remake(bysym; f = byvar.f, ode_solver = Potts.RK4())) isa ArgumentError
    end
end

@testitem "states given as such are laid out for the scratch (remake, reinit!)" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "states given as such are laid out for the scratch (remake, reinit!)" begin
        sys = SolverPairYS(; name = :p)
        multi = PottsProblem(sys, solver_op(), (0, 4); solvers = [:s => Potts.RK4()])
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
        @test current_state(integ).cell.y == plain.cell.y && haskey(current_state(integ).cell, :s__ode)
        # R3: a solver remake together with a state
        r3 = remake(single; solvers = [:s => Potts.RK4()], u0 = plain)
        @test haskey(r3.u0.cell, :s__ode) && r3.f.fingerprint == multi.f.fingerprint
        @test solve(r3, SequentialCPM()).u[end].cell.s == solve(remake(multi; u0 = plain), SequentialCPM()).u[end].cell.s
        # and back: a scratch state into a single-group problem loses the scratch
        @test !haskey(remake(single; u0 = solve(multi, SequentialCPM()).u[end]).u0.cell, :s__ode)
        # an incompatible state names what differs
        e = solver_err(() -> reinit!(init(single, SequentialCPM()), Potts.CorePotts.with_capacity(plain, 9)))
        @test e isa ArgumentError
    end
end

@testitem "P6.0n: y[id] is the own unknown, a gather over other cells is Jacobi" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "P6.0n: y[id] is the own unknown, a gather over other cells is Jacobi" begin
        op(y) = [ownership => p60n_two(), kind => [:A, :A], :y => y]
        rk4 = 1 - 1 + 1 / 2 - 1 / 6 + 1 / 24                     # one RK4 step of y' = −y, h = 1
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            own = PottsProblem(P60nOwnIndex(; name = :o), op([1.0, 2.0]), (0, 2); ode_solver = Potts.RK4())
            plain = PottsProblem(P60nOwnPlain(; name = :o), op([1.0, 2.0]), (0, 2); ode_solver = Potts.RK4())
            @test !haskey(own.u0.cell, :y__ode)                   # an own read needs no scratch
            u = solve(own, alg).u[end].cell.y
            @test u == solve(plain, alg).u[end].cell.y
            # held at its start-of-step value, `y[id]` would give y + h·(−y) = 0 every step
            @test u ≈ [1.0, 2.0] .* rk4^2 && all(>(0), u)
            g = PottsProblem(P60nGather(; name = :g), op([1.0, 2.0]), (0, 3))
            @test haskey(g.u0.cell, :y__ode)
            traj = [Vector(x.cell.y) for x in solve(g, alg; saveat = 0:3).u]
            @test traj == [[1.0, 2.0], [2.0, 1.0], [1.0, 2.0], [2.0, 1.0]]    # Jacobi: swaps
        end
        # the detector: a hoisted fold or reads of non-ODE cell variables need no scratch
        @test !Potts._ode_reads_other_cells(mtkcompile(SolverPairYS(; name = :p)))
        @test Potts._ode_reads_other_cells(mtkcompile(P60nGather(; name = :g)))
        @test !Potts._ode_reads_other_cells(mtkcompile(P60nOwnIndex(; name = :o)))
    end
end

@testitem "P6.0n: an index follows the stepped local" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "P6.0n: an index follows the stepped local" begin
        op = [ownership => p60n_two(), kind => [:A, :A], :y => [0.4, 0.4], :w => [2.0, 1.0]]
        prob = PottsProblem(P60nIndexLocal(; name = :d), op, (0, 1); ode_solver = ExplicitEuler(substeps = 4))
        @test !haskey(prob.u0.cell, :y__ode)
        @test !Potts._ode_reads_other_cells(mtkcompile(P60nIndexLocal(; name = :d)))
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            @test solve(prob, alg).u[end].cell.y ≈ [2.15, 1.65]
        end
    end
end

@testitem "D-208: copy-step relations follow the functions, not only the model" setup = [SolversSetup] tags = [:potts, :solvers] begin
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
        # the checkerboard's spacing with two parts: the gap between two blocks' active sub-regions
        spacing(q) = (l = init(q, CheckerboardCPM(; parts = 2)).cache.layout; (l.k - 1) * minimum(l.base))
        @test spacing(prob) == 1                                              # `far` is not a copy-step read
        # `anneal` (zero temperature around the generated one) keeps the generated reads
        @test Potts.anneal(prob, 2; alg = CheckerboardCPM()) isa Potts.CorePotts.CPMState
        # a bias reading `far` (reach 2) against footprint 1: the spacing widens to cover it (D-271)
        farbias = (st, p, prop, ctx) -> length(ctx.far) < 0
        biased = Potts.CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint, f.temperature,
            bias = farbias, f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
        @test Potts.CorePotts.copy_step_relations(f.sys, biased) === nothing
        @test spacing(remake(prob; f = biased)) >= 2
        @test Symbol(solve(remake(prob; f = biased), CheckerboardCPM()).retcode) === :Success
        @test Symbol(solve(remake(prob; f = biased), SequentialCPM()).retcode) === :Success
        # a swapped ΔH (or temperature) likewise
        dH = (st, p, prop, ctx) -> f.delta_H(st, p, prop, ctx) + 0.0 * length(ctx.far)
        swapped = Potts.CorePotts.CPMFunction(dH; f.commit!, f.constraint, f.temperature,
            f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
        @test spacing(remake(prob; f = swapped)) >= 2
        Tswap = Potts.CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint,
            temperature = (st, p, prop, ctx) -> 2.0, f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity)
        @test Potts.CorePotts.copy_step_relations(f.sys, Tswap) === nothing
    end
end
