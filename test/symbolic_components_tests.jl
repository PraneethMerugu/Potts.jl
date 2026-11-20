# Split from test/symbolic_tests.jl

@testitem "ensembles and callbacks of generated problems" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "ensembles and callbacks of generated problems" begin
        prob = symbolic_graner_problem(; nmcs = 5)
        alg = SequentialCPM(; proposal = Moore(1))
        ens = solve(
            EnsembleProblem(prob; output_func = (sol, ctx) -> (total_energy(prob, sol.u[end]), false)),
            alg, EnsembleThreads(); trajectories = 4
        )
        @test length(unique(ens.u)) == 4
        @test ens.u[3] == total_energy(prob, solve(remake(prob; replica = 3), alg).u[end])
        # a callback that quenches the temperature through a symbolic parameter map
        cold = remake(prob; p = [:T => 0.0])
        quench = DiscreteCallback((u, t, integ) -> t == 2, integ -> (integ.p = cold.p))
        integ = init(prob, alg; callback = quench)
        foreach(_ -> step!(integ), 1:3)
        @test integ.p.T == 0.0
    end
end


@testitem "components: MTK systems per cell" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "components: MTK systems per cell" begin
        σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
        op = [ownership => σ, kind => [:A, :B]]
        frozen(sys) = PottsProblem(sys, op, (0, 10); T = Float64)
        for (solver, exact, tol) in (
                (Potts.ExplicitEuler(), t -> (1 - 0.3)^t, 1.0e-12),
                (Potts.RK4(substeps = 2), t -> (1 + (z = -0.15) + z^2 / 2 + z^3 / 6 + z^4 / 24)^(2t), 1.0e-12),
            )
            sys = component_model()
            cs = mtkcompile(sys)
            @test Set(Potts.info(v).name for v in Potts.declared_variables(getfield(cs, :sys))) == Set([:decay₊y_c, :clock₊m_c])
            @test Set(Potts.info(v).name for v in Potts.declared_parameters(getfield(cs, :sys))) == Set([:T, :decay₊k_c, :clock₊τ_c])   # r_c is coupled
            # no copies (T = 0 and frozen cells) so the volume coupling is exact
            prob = remake(PottsProblem(cs, op, (0, 10); ode_solver = solver); p = [:T => 1.0e-9])
            sol = solve(prob, SequentialCPM(); saveat = 0:10)
            ys = [u.cell.decay₊y_c[1] for u in sol.u]
            @test maximum(abs.(ys .- exact.(0:10))) < tol
            @test all(u -> u.cell.decay₊y_c[2] == u.cell.decay₊y_c[1], sol.u)            # every kind
            @test sol.u[end].cell.clock₊m_c[2] == 0.0                                     # kind-scoped
            @test sol[:decay₊y_c][end] == sol.u[end].cell.decay₊y_c
        end
        # coupling and division: the clock runs at volume/25/τ per MCS and resets on division
        sys = component_model()
        prob = remake(PottsProblem(sys, op, (0, 12)); p = [:T => 1.0e-9, Symbol("clock₊τ_c") => 8.0])
        sol = solve(prob, SequentialCPM(); saveat = 0:12)
        m = [u.cell.clock₊m_c[1] for u in sol.u]
        @test m[1:8] == (0:7) ./ 8                          # exact: 1/8 per MCS at volume 25
        @test m[9] == 0.0 && sol.u[9].cell.clock₊m_c[3] == 0.0 && count(>(0), sol.u[9].cell.volume) == 3
        @test_throws Potts.PottsCompileError mtkcompile(
            Potts.PottsSystem(;
                name = :x, kinds = [:medium, :A],
                lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
                components = [Potts.ComponentSpec(:clock, clock, Potts.CellDomain(Int[]))],
                equations = [Potts.Symbolics.variable(Symbol("clock₊nope")) ~ 1.0]
            )
        )
    end
end


@testitem "component and domain review regressions" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "component and domain review regressions" begin
        @potts_model TwoClocks begin
            @kinds medium A B
            @parameters T = 1.0
            @components cells(A) fast = clock
            @components cells(B) slow = clock
            @components dec = decay
            @equations begin
                slow.r_c ~ 0.5
                dec.k_c ~ fast.m_c / 10                      # a coupling reading another component
            end
            @observed om(cell) ~ slow.m_c
            @lattice Lattice((20, 20))
            @energy cells => (volume - 25.0)^2
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
        op = [ownership => σ, kind => [:A, :B]]
        # components are named by their binding, whatever the system is called
        p = remake(PottsProblem(TwoClocks(; name = :two), op, (0, 4)); p = [:T => 1.0e-9])
        @test Set(propertynames(p.p)) == Set([:T, :fast₊τ_c, :fast₊r_c, :slow₊τ_c])
        sol = solve(p, SequentialCPM(); saveat = 0:4)
        u = sol.u[end]
        @test u.cell.fast₊m_c ≈ [4 / 20, 0] && u.cell.slow₊m_c ≈ [0, 0.5 * 4 / 20]
        @test sol[:om][end] == u.cell.slow₊m_c
        @test u.cell.dec₊y_c[1] ≈ prod(1 - m / 10 for m in (0:3) ./ 20)             # Euler with k = m(t)/10
        # couplings target component parameters only
        @potts_model BadCoupling begin
            @kinds medium A
            @parameters T = 1.0
            @components clock = clock
            @equations clock.m_c ~ volume
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = T)
        end
        @test_throws Potts.PottsCompileError mtkcompile(BadCoupling(; name = :b))
        # component values without defaults must be given
        @potts_model NoDefault begin
            @kinds medium A
            @parameters T = 1.0
            @components nd = nodefault
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = T)
        end
        σ8 = zeros(Int32, 8, 8); σ8[3:5, 3:5] .= 1
        @test_throws ArgumentError PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1]], (0, 1))
        pn = PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1], Symbol("nd₊k_nd") => 0.5], (0, 1))
        @test pn.p.nd₊k_nd == 0.5
        # kind tables must cover every kind (an extension adding kinds)
        @potts_model MoreKinds begin
            @extend base = GranerGlazier()
            @kinds medium dark light extra
        end
        σg, kg = graner_state()
        @test_throws ArgumentError PottsProblem(MoreKinds(; name = :m), [ownership => σg, kind => kg], (0, 1))
        # models with domains fingerprint by content: checkpoints resume across rebuilds
        σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= first(two_kind_blocks())
        kd = last(two_kind_blocks())
        p1 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6); field_solver = ExplicitEuler())
        p2 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6); field_solver = ExplicitEuler())
        @test p1.f.fingerprint == p2.f.fingerprint && Potts.lattice(DiskSorting(; name = :a)) == Potts.lattice(DiskSorting(; name = :b))
        integ = init(p1, SequentialCPM()); foreach(_ -> step!(integ), 1:3)
        ck = checkpoint(integ)
        @test solve!(init(p2, SequentialCPM(); checkpoint = ck)).u[end].ownership == solve(p1, SequentialCPM()).u[end].ownership
        # site populations stay inside the domain
        @test observe(p1, Potts._fold_iter(count, s -> true, Potts.sites, nothing)) == count(Potts.lattice(DiskSorting(; name = :d)).domain)
    end
end


@testitem "user-registered functions in generated code" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "user-registered functions in generated code" begin
        σ = zeros(Int32, 16, 16); σ[5:9, 5:9] .= 1
        p = PottsProblem(UserFunctions.Hill(; name = :h), [ownership => σ, kind => [1]], (0, 5))
        @test selfcheck(p) < 1.0e-9
        u = solve(p, SequentialCPM()).u[end]
        @test u.cell.g[1] > 0.5
    end
end


@testitem "model-scope ODEs and components" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "model-scope ODEs and components" begin
        σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1; σ[10:12, 10:12] .= 2; σ[15:17, 3:5] .= 3
        p = PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1]], (0, 10); ode_solver = Potts.RK4(substeps = 4))
        @test :pk₊drug_c in propertynames(p.u0.model) && :pk₊drug_k in propertynames(p.p)
        for alg in (SequentialCPM(), CheckerboardCPM())
            u = solve(p, alg).u[end]
            x = 0.5 / 4
            @test u.model.g[1] ≈ (1 - x + x^2 / 2 - x^3 / 6 + x^4 / 24)^40 rtol = 1.0e-12  # RK4, 4 substeps per MCS
            @test u.model.pk₊drug_c[1] ≈ 3 / 0.2 * (1 - exp(-0.2 * 10)) rtol = 1.0e-5
        end
        @test_throws ArgumentError PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1], :g => nothing], (0, 1))
    end
end


@testitem "component bindings Potts does not read" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "component bindings Potts does not read" begin
        t = Potts.t
        σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [:A]]
        @potts_model BindProbeCell begin
            @structural_parameters begin
                comp_sys = nothing
                with_obs = false
            end
            @kinds medium A
            @components cells(A) comp = comp_sys
            if with_obs
                @observed ok2(cell) ~ comp.k2
            end
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        @potts_model BindProbeModel begin
            @structural_parameters comp_sys = nothing
            @kinds medium A
            @components model comp = comp_sys
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        function run(sys; scope = :cells, with_obs = false)
            m = scope === :model ? BindProbeModel(; name = :bp, comp_sys = sys) :
                BindProbeCell(; name = :bp, comp_sys = sys, with_obs)
            mtkcompile(m)
            return solve(PottsProblem(m, op, (0, 2)), SequentialCPM())
        end
        rejected(sys, word; kw...) = try
            run(sys; kw...)
            false
        catch e
            e isa Potts.PottsCompileError
        end
        let
            @parameters k = 0.3
            @parameters k2 = 2k
            Potts.ModelingToolkitBase.@variables y(t) = 1.0 o(t)
            # an unused bound parameter
            sol = run(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp))
            @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.3)^2
            # the same parameter used by the component, or read by the model, is the computed parameter
            # `comp₊k2 = 2 comp₊k` (before: rejected naming `k2`)
            sol = run(System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp))
            @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.6)^2
            sol = run(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp); with_obs = true)
            @test Potts.observe(sol, :ok2)[end][1] ≈ 0.6
            # at model scope, with nothing reading `comp.k2`, it builds
            sol = run(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp); scope = :model)
            @test Symbol(sol.retcode) === :Success
            # an observed variable bound (or given an initial value) consistent with its equation
            Potts.ModelingToolkitBase.@variables ob(t) = 2y
            sol = run(System([ob ~ 2y, Potts.D(y) ~ -k * ob], t; name = :comp))
            @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.6)^2
            sol = run(System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [o => 2y]))
            @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.6)^2
            # an unknown's initial value given as an expression of parameters is evaluated;
            # negative control: one that reads an unknown is rejected
            sol = run(System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [y => 2k]))
            @test sol.u[end].cell.comp₊y[1] ≈ 0.6 * (1 - 0.6)^2
            Potts.ModelingToolkitBase.@variables q(t)
            @test rejected(System([o ~ 2y, Potts.D(y) ~ -k * o, Potts.D(q) ~ -q], t; name = :comp, initial_conditions = [y => 2q, q => 1.0]), "2q")
        end
    end
end
