# Split from implicit_tests.jl (Wave T3b); uses LP_implicit setup.

@testitem "F3-09a: local nonlinear rows: one Newton step keeps order 1" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09a: local nonlinear rows: one Newton step keeps order 1" begin
        dts = [0.02 / 2^k for k in 0:3]
        # logistic growth `3 c (1 − c)`
        es, o, pb, _ = nl_orders(0.05 * Δ(bce) + 3 * bce * (1 - bce), NLIC; T = 0.5, dts)
        @test all(q -> abs(q - 1) < 0.1, o)                 # (measured 1.06, 1.03, 1.02)
        ig = init(pb, BackwardEuler(; dt = 0.02, inner = BTIGHT); save_everystep = false)
        c = only(ig.runtimes).cache
        @test c.newton == 1 && c.iterate && c.exact && only(c.rows).op.iterate && !only(c.rows).op.switch
        @test bwarm(ig) == 0
        # Michaelis–Menten uptake `−V c/(K + c)` with a time-dependent source (read at tⁿ⁺¹)
        es, o, _, _ = nl_orders(0.05 * Δ(bce) - 2 * bce / (0.5 + bce) + 1 + 0.5 * sin(10t), NLIC; T = 0.5, dts)
        @test all(q -> abs(q - 1) < 0.1, o)                 # (measured 1.00, 1.00, 1.00)
        # … stiff: V/K = 1600, `h |∂f/∂c|` up to 32; the errors fall at least linearly and stay small
        # (without the derivative the uptake is explicit and unstable at these steps)
        es, o, _, _ = nl_orders(0.05 * Δ(bce) - 40 * bce / (0.025 + bce) + 20 + 10 * sin(10t), NLIC; T = 0.3, dts)
        @test all(q -> q > 0.9, o) && maximum(es) < 1.0e-3     # (measured 5.7e-4 … 7.9e-7)
    end
end

@testitem "F3-09a: the switch: newton = 2 by default keeps order 1" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09a: the switch: newton = 2 by default keeps order 1" begin
        sw = 0.05 * Δ(bce) - 8 * max(bce - 0.4, 0) / 0.6 + 2 + 2 * sin(6t)
        dts = [0.05 / 2^k for k in 0:3]
        e2, o2, pb, u2 = nl_orders(sw, NLIC; T = 0.3, dts)
        e1, o1, _, u1 = nl_orders(sw, NLIC; T = 0.3, dts, newton = 1)
        _, _, _, u8 = nl_orders(sw, NLIC; T = 0.3, dts, newton = 8)
        c = only(init(pb, BackwardEuler(; dt = 0.05)).runtimes).cache
        @test c.newton == 2 && c.exact && only(c.rows).op.switch
        # newton = 2 keeps order 1 (measured 1.02, 0.98, 0.99); one Newton step, the switch lagged
        # at the substep's start, does not (0.48 at the first pair)
        @test all(q -> abs(q - 1) < 0.1, o2) && abs(o1[1] - 0.48) < 0.05
        # … and is close to the converged Backward Euler step (eight iterations; three are exact):
        # 3.5e-6 off at dt = 0.05, where one iteration is 5.7e-3 off
        @test maximum(abs, u2[1] .- u8[1]) < 1.0e-5 && maximum(abs, u1[1] .- u8[1]) > 1.0e-3
    end
end

@testitem "F3-09a: the switch's flip pass counts no budget hit (review r1, M7)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09a: the switch's flip pass counts no budget hit (review r1, M7)" begin
        # the default count's second iteration fixes the switch state: no convergence test, so a
        # default user sees no warning (base 2d213237, ~/lpwork/f3r1-nc-base.log: 2 hits and the
        # budget warning in Float32 and Float64); a given `newton = 2` checks as before
        sys = PDESystem(
            [D(bce) ~ 0.05 * Δ(bce) - 8 * max(bce - 0.4, 0) / 0.6 + 2 + 2 * sin(6t)], [bc(0, x, y) ~ NLIC], bdom(3.0),
            [t, x, y], [bce], Any[]; name = :sw
        )
        for T in (Float32, Float64)
            p = discretize(sys, LatticeDiscretization(Grid((32, 32)); T))
            s = @test_logs min_level = Base.CoreLogging.Warn solve(p, BackwardEuler(; dt = 0.05))
            @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        end
        p = discretize(sys, LatticeDiscretization(Grid((32, 32)); T = Float64))
        s = @test_logs (:warn, r"the Newton iteration \(`newton = 2`\) reached its budget") solve(p, BackwardEuler(; dt = 0.05, newton = 2))
        @test s.stats.newton_budget > 0
    end
end

@testitem "F3-09a: an unseen growth is clamped (the cause bit), not a failure" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09a: an unseen growth is clamped (the cause bit), not a failure" begin
        # `20 c² − 20 c` from c = 0.75: `∂f/∂c = 10` at the start, `h = 0.1`: the shift `1/h − 10`
        # is clamped at `1/(2h)`; the rest stays in the residual and the field decays
        sys = PDESystem(
            [D(bce) ~ 0.05 * Δ(bce) + 20 * bce^2 - 20 * bce], [bc(0, x, y) ~ 0.75], bdom(0.3), [t, x, y], [bce], Any[];
            name = :clamp
        )
        pb = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64))
        ig = init(pb, BackwardEuler(; dt = 0.1))
        # with one Newton step nothing else tells: a warning names the field, the window and the
        # route (review r1, S2; base 2d213237: no warning)
        @test_logs (:warn, r"^field `bc`: the implicit shift was clamped in window 1 \(t = 0\.0\) .*a larger `newton = k` checks the step") solve!(ig)
        rt = only(ig.runtimes)
        @test ig.retcode == ReturnCode.Success && rt.totals.cause & 0x08 != 0 && maximum(ig[bce]) < 1.0e-3
        # … once per run, and a site growth that the count rule cannot see (a field row whose growth
        # reads the time: no interval bounds it) warns too
        pg = discretize(
            PDESystem(
                [D(bce) ~ 0.05 * Δ(bce) + 8 * (1 + x) * (1 + t) * bce], [bc(0, x, y) ~ 0.5], bdom(0.3), [t, x, y],
                [bce], Any[]; name = :sitegrowth
            ), LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        @test_logs (:warn, r"the implicit shift was clamped in window 1") solve(pg, BackwardEuler(; dt = 0.1))
        # the route works: more substeps keep the growth below the shift (`h g ≤ 0.02 · 20.2 < 1/2`): no clamp
        s = @test_logs min_level = Base.CoreLogging.Warn solve(pg, BackwardEuler(; dt = 0.1, substeps = 5))
        @test s.retcode == ReturnCode.Success
        # a decay with no clamp leaves the bit clear
        ig = init(
            discretize(
                PDESystem(
                    [D(bce) ~ 0.05 * Δ(bce) - 20 * bce], [bc(0, x, y) ~ 0.75], bdom(0.3), [t, x, y], [bce], Any[];
                    name = :noclamp
                ), LatticeDiscretization(Grid((8, 8)); T = Float64)
            ), BackwardEuler(; dt = 0.1)
        )
        solve!(ig)
        @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.cause == 0
    end
end

@testitem "F3-09b: advection at the rule-2 count; the Newton check (R2-M1)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09b: advection at the rule-2 count; the Newton check (R2-M1)" begin
        # ρ_adv = 2 (1 + 0.5) · 16 = 48: n = ⌈2 · 0.25 · 48⌉ = 24 substeps, ρ_c = 1/2: newton = 10
        sys = nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([1.0, 0.5], bce) + 1 + sin(4t) * x], [bc(0, x, y) ~ x * y], [bce])
        p = nlown(sys)
        ig = init(p, BackwardEuler(; dt = 0.25, inner = BTIGHT))
        c = only(ig.runtimes).cache
        @test ig.substeps == 24 && c.newton == 10 && !c.exact && c.seen && c.ρin == 48.0
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.25, inner = BTIGHT))
        # no budget hit; the host stops at the tolerance (measured 4 iterations a substep: 384 solves)
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0 && s.stats.solves < 10 * 96
        ub = direct_be(sys, (16, 16), 0.25, 1.0, 24)
        @test maximum(abs, vec(blast(s)) .- ub) / maximum(abs, ub) < 1.0e-3       # (measured 3.7e-6)
        # a budget too small: counted, one warning with the count and the route (at the first read,
        # after the first window); the route works
        s2 = @test_logs (:warn, r"field `bc`: the Newton iteration \(`newton = 2`\) reached its budget \d+ times.*a larger `newton = k`") solve(
            p,
            BackwardEuler(; dt = 0.25, inner = BTIGHT, newton = 2)
        )
        @test s2.retcode == ReturnCode.Success && s2.stats.newton_budget == 96
        s3 = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.25, inner = BTIGHT, newton = 12))
        @test s3.stats.newton_budget == 0
        # a field that barely moves (an increment below the rounding of the field): no budget hit
        still = nlown(nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([0.0, 0.0], bce) + 1.0e-16 * x], [bc(0, x, y) ~ 1.0], [bce]))
        ig = init(still, BackwardEuler(; dt = 0.25))
        @test only(ig.runtimes).cache.newton == 2
        solve!(ig)
        @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.newton_budget == 0
    end
end

@testitem "F3-09b: a cycle in a group converges by Gauss–Seidel (count rule 2)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09b: a cycle in a group converges by Gauss–Seidel (count rule 2)" begin
        # κ_in = 2 (the largest cross sum): n = ⌈2 · 0.5 · 2⌉ = 2, ρ_c = 0.25 · 2 = 1/2: newton = 10
        sys = nlsys(
            [D(bce) ~ 0.1 * Δ(bce) - bce + 2 * boe, D(boe) ~ 0.1 * Δ(boe) - 3 * boe + 1.5 * bce + 1],
            [bc(0, x, y) ~ x, bo(0, x, y) ~ y], [bce, boe]
        )
        p = nlown(sys; dims = BDIMS)
        ig = init(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
        c = only(ig.runtimes).cache
        @test ig.substeps == 2 && c.newton == 10 && c.cyclic && c.ρin == 2.0
        s = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        # the converged block Gauss–Seidel (40 sweeps: the coupled BE step), to the Newton tolerance
        # (1e-3 of the substep's increment; the host stops there)
        r = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT, newton = 40))
        rel(f) = maximum(abs, s[f, length(s.t)] .- r[f, length(r.t)]) / maximum(abs, r[f, length(r.t)])
        @test rel(bce) < 1.0e-3 && rel(boe) < 1.0e-3
        # without the host stop (`newton = 10` given: ten sweeps) it is the coupled step to 1e-6
        r10 = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT, newton = 10))
        @test maximum(abs, r10[bce, length(r10.t)] .- r[bce, length(r.t)]) < 1.0e-6
    end
end

@testitem "review r1 M3: a nonlinear read of another row's field is a source in solve order" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "review r1 M3: a nonlinear read of another row's field is a source in solve order" begin
        # acyclic (c reads o through a switch, o does not read c): the term is known when c is
        # solved, so the operator is exact, newton = 1 and no warning (base cb20be97: the term is
        # unseen, newton = 4 and the warning; ~/lpwork/f3b6r-nc-m3.log)
        p = nlown(
            nlsys(
                [D(bce) ~ 0.1 * Δ(bce) - bce + 2.25 * max(boe - 0.5, 0), D(boe) ~ 0.1 * Δ(boe) - boe + x],
                [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ y], [bce, boe]
            ); dims = BDIMS
        )
        ig = @test_logs min_level = WARN init(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
        c = only(ig.runtimes).cache
        @test c.newton == 1 && c.exact && !c.cyclic && [r.key for r in c.rows] == ["bo", "bc"]
        s = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
        r = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT, newton = 12))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        @test maximum(abs, s[bce, length(s.t)] .- r[bce, length(r.t)]) < 1.0e-10
        # a cycle (o reads c back): the term stays unseen, newton = 4 and the warning
        pc = nlown(
            nlsys(
                [D(bce) ~ 0.1 * Δ(bce) - bce + 2.75 * max(boe - 0.5, 0), D(boe) ~ 0.1 * Δ(boe) - boe + 0.5 * bce],
                [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ y], [bce, boe]
            ); dims = BDIMS
        )
        ig = @test_logs (:warn, r"`2\.75max\(-0\.5 \+ bo, 0\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") match_mode = :any init(
            pc,
            BackwardEuler(; dt = 0.5, inner = BTIGHT)
        )
        @test only(ig.runtimes).cache.newton == 4 && only(ig.runtimes).cache.cyclic
    end
end

@testitem "F3-09b: a term no bound sees warns once; a divergence ends the run" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-09b: a term no bound sees warns once; a divergence ends the run" begin
        # a velocity that varies in time: no bound (the interval bound covers the coordinates, not
        # the time; F3-13 bounds `50(1 + x)`, below), one substep, newton = 4, checked on the device
        p = nlown(nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bce)], [bc(0, x, y) ~ x * y], [bce]; T = 2.0))
        s = @test_logs (:warn, r"field `bc`: `-Advect\(Upwind1\(\)\)\(\[.*t.*, 0\.0\], bc\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") (
            :warn,
            r"field `bc`: the solve failed in window 1 \(t = 0\.0\) \(the Newton iteration diverged\), `ReturnCode.ConvergenceFailure`",
        ) solve(
            p,
            BackwardEuler(; dt = 1.0)
        )
        @test s.retcode == ReturnCode.ConvergenceFailure
        ig = init(p, BackwardEuler(; dt = 1.0))
        @test ig.substeps == 1 && only(ig.runtimes).cache.newton == 4 && !only(ig.runtimes).cache.seen
        # (once per group and term: a second problem does not warn at its build)
        @test_logs min_level = WARN init(p, BackwardEuler(; dt = 1.0))
    end
end

@testitem "F3-13: a site-varying velocity at the rule-2 count; a site growth at rule 1 (batch 3 review R2, r1 S2)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-13: a site-varying velocity at the rule-2 count; a site growth at rule 1 (batch 3 review R2, r1 S2)" begin
        # `50(1 + x)` over the box and one spacing past it (16²: x ≤ 1 + 1/16): ρ_adv = 2 · 50 (2 + 1/16)
        # · 16 = 3300, n = ⌈2 · 0.01 · 3300⌉ = 66, ρ_c = 1/2: newton = 10, no warning, and the run is
        # the BE matrix's (base b41b73c1: one substep, newton = 4, the warning; at dt = 1 it diverged)
        sys = nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([50 * (1 + x), 0.0], bce)], [bc(0, x, y) ~ x * y], [bce]; T = 0.05)
        p = nlown(sys)
        ig = init(p, BackwardEuler(; dt = 0.01, inner = BTIGHT))
        c = only(ig.runtimes).cache
        @test ig.substeps == 66 && c.newton == 10 && c.seen && c.ρin ≈ 3300
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.01, inner = BTIGHT))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        ub = direct_be(sys, (16, 16), 0.01, 0.05, 66)
        @test maximum(abs, vec(blast(s)) .- ub) / maximum(abs, ub) < 1.0e-3    # (batch 3 review r1 S2): a site growth the interval bound sees (`8(1 + x) c`, a field
        # row) raises the count by rule 1 instead: n = ⌈2 · 0.1 · 8 (2 + 1/8)⌉ = 4 (x over the box and
        # one spacing past it), no clamp and no warning, and the run is the BE matrix's (base
        # b41b73c1: one substep, the clamp warning)
        gsys = PDESystem(
            [D(bce) ~ 0.05 * Δ(bce) + 8 * (1 + x) * bce], [bc(0, x, y) ~ 0.5], bdom(0.3), [t, x, y], [bce], Any[];
            name = :sitegrowth2
        )
        pg = discretize(gsys, LatticeDiscretization(Grid((8, 8)); T = Float64))
        ig = init(pg, BackwardEuler(; dt = 0.1, inner = BTIGHT))
        @test ig.substeps == 4
        @test_logs min_level = Base.CoreLogging.Warn solve!(ig)
        @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.cause & 0x08 == 0
        ub = direct_be(gsys, (8, 8), 0.1, 0.3, 4)
        @test maximum(abs, vec(ig[bce]) .- ub) / maximum(abs, ub) < 1.0e-9
    end
end

@testitem "r1 M1: an operator that reads the time is built at each substep's end time" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 M1: an operator that reads the time is built at each substep's end time" begin
        # against BE with the matrix assembled at every substep's end time (base, ~/lpwork/f3r1-nc-base.log:
        # 6.6e-2, 1.6e-3, 1.6e-3 relative: every substep took the first substep's operator)
        for rate in (0.1 * Δ(bce) - (1 + 20t) * bce + 1, DivKGrad(:harmonic)(1 + 5t, bce) - bce + 1, (1 + 5t) * Δ(bce) - bce + 1)
            sys = nlsys([D(bce) ~ rate], [bc(0, x, y) ~ x * y], [bce]; T = 0.4)
            p = nlown(sys; dims = (10, 8))
            s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.2, substeps = 4, inner = r1tight()))
            @test r1rel(vec(blast(s)), direct_be(sys, (10, 8), 0.2, 0.4, 4; timed = true)) < 1.0e-10   # (measured 1.8e-14)
            c = only(init(p, BackwardEuler(; dt = 0.2, substeps = 4)).runtimes).cache
            @test c.timed && c.exact && c.newton == 1
        end
        # SX-18 with a time-dependent coefficient: OrdinaryDiffEq's ImplicitEuler at the substep
        sx = nlsys(
            [D(bce) ~ DivKGrad(:harmonic)(0.3 * (1 + 5t), bce) - (1 + 20t) * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0],
            [bce]; T = 0.4
        )
        po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
        # (a fresh Jacobian at every Newton iteration: with the matrix of the step's start, the
        # simplified Newton iteration of a time-dependent operator needs more than its default 10
        # iterations at 1e-12 and reports `ConvergenceFailure`)
        ie = ImplicitEuler(; nlsolve = OrdinaryDiffEqSDIRK.NLNewton(; max_iter = 50, always_new = true))
        so = solve(po, ie; dt = 0.05, adaptive = false, abstol = 1.0e-12, reltol = 1.0e-12)
        @test so.retcode == ReturnCode.Success
        sb = solve(nlown(sx; dims = (8, 8)), BackwardEuler(; dt = 0.2, substeps = 4, inner = r1tight()))
        @test maximum(abs, vec(blast(sb)) .- so.u[end]) < 1.0e-8                  # (base: 5.8e-3)
        # an operator that does not read the time is built once per window, as before
        pc = nlown(nlsys([D(bce) ~ DivKGrad(:harmonic)(1 + x, bce) - bce + sin(3t)], [bc(0, x, y) ~ x], [bce]; T = 0.4); dims = (10, 8))
        ig = init(pc, BackwardEuler(; dt = 0.2, substeps = 4))
        solve!(ig)
        @test !only(ig.runtimes).cache.timed && only(ig.runtimes).cache.rebuilds == 1
    end
end

@testitem "r1 M2, S1: a Robin face's sign follows a parameter write; a negative face is bounded" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 M2, S1: a Robin face's sign follows a parameter write; a negative face is bounded" begin
        # `1.5 c − rb ∂c/∂x = 0.2` at x = 1: rb = −1 a positive diagonal, rb = +1 a negative one
        function robin(rate, v)
            @parameters rb = v
            return PDESystem(
                    [D(bce) ~ rate], [bc(0, x, y) ~ x * y, 1.5 * bc(t, 1, y) - rb * Differential(x)(bc(t, 1, y)) ~ 0.2],
                    bdom(1.0), [t, x, y], [bce], [rb]; name = :rob
                ), rb
        end
        for rate in (0.3 * Δ(bce) - 2 * bce + 1, DivKGrad(:harmonic)(0.3 * (1 + x), bce) - 2 * bce + 1)   # numeric, field row
            for (b0, b1) in ((-1.0, 1.0), (1.0, -1.0))
                sys0, rb = robin(rate, b0)
                ig = init(nlown(sys0; dims = (10, 8)), BackwardEuler(; dt = 0.1, inner = r1tight()))
                ig.ps[rb] = b1
                fresh = init(nlown(first(robin(rate, b1)); dims = (10, 8)), BackwardEuler(; dt = 0.1, inner = r1tight()))
                c, cf = only(ig.runtimes).cache, only(fresh.runtimes).cache
                @test (c.exact, c.seen, c.newton, c.check) == (cf.exact, cf.seen, cf.newton, cf.check)
                @test ig.substeps == fresh.substeps
                # the same warnings (a field row's negative face has no bound: newton = 4, its budget
                # warning in both), the same window
                warns(i) = [l.message for l in first(Test.collect_test_logs(() -> step!(i); min_level = WARN))]
                @test warns(ig) == warns(fresh)
                @test maximum(abs, vec(ig[bce]) .- vec(fresh[bce])) < 1.0e-12   # (base, rb −1 → +1: 2.4e-2 numeric, 5.1e-2 field)
                @test only(ig.runtimes).totals.newton_budget == only(fresh.runtimes).totals.newton_budget
            end
        end
        # S1: the negative face's part `w |d⁻|` is a bound (`w = 0.3/h² = 30`, `d⁻ = α/(α/2 + β)` with
        # `β = −1/h` in lattice units: `|d⁻| = 1.5/9.25`): rule 2 keeps one substep (`⌈2 · 0.1 · 4.86⌉`),
        # `newton` follows ρ_c = 0.49 (10); no budget hit, and the result is the converged step (base:
        # newton = 4 and budget hits with a warning)
        p = nlown(first(robin(0.3 * Δ(bce) - 2 * bce + 1, 1.0)); dims = (10, 8))
        ig = init(p, BackwardEuler(; dt = 0.1, inner = r1tight()))
        c = only(ig.runtimes).cache
        @test !c.exact && c.seen && c.ρin ≈ 30 * 1.5 / 9.25 && ig.substeps == 1 && c.newton == 10
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.1, inner = r1tight()))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        r = solve(p, BackwardEuler(; dt = 0.1, inner = r1tight(), newton = 40))
        @test r1rel(vec(blast(s)), vec(blast(r))) < 1.0e-4                       # (measured 3.8e-5; base 2.1e-4)
        # R2-S1: a field row's negative face is bounded by its largest face coefficient over the
        # box and one spacing past it, `0.3 (1 + 1.1) / 0.1² = 63`: ρ_rob = 63 · 1.5/9.25, rule 2
        # takes ⌈2 · 0.1 · 10.2⌉ = 3 substeps, newton follows ρ_c (base: unseen, newton = 4 and a
        # budget warning in the run)
        pf = nlown(first(robin(DivKGrad(:harmonic)(0.3 * (1 + x), bce) - 2 * bce + 1, 1.0)); dims = (10, 8))
        ig = init(pf, BackwardEuler(; dt = 0.1, inner = r1tight()))
        c = only(ig.runtimes).cache
        @test !c.exact && c.seen && c.ρin ≈ 0.3 * 2.1 / 0.01 * 1.5 / 9.25 && ig.substeps == 3 && c.newton > 4
        s = @test_logs min_level = WARN solve(pf, BackwardEuler(; dt = 0.1, inner = r1tight()))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        r = solve(pf, BackwardEuler(; dt = 0.1, substeps = 3, inner = r1tight(), newton = 40))
        @test r1rel(vec(blast(s)), vec(blast(r))) < 1.0e-4
        # … and a face coefficient no interval bounds (it reads an input field) is unseen: a warning
        # at `init` that names the face (base: none at `init`, only the budget warning later)
        @variables rk(..) [input = true]
        rke = rk(t, x, y)
        sysk = PDESystem(
            [D(bce) ~ DivKGrad(:harmonic)(0.3 * (1 + rke), bce) - 2 * bce + 1],
            [bc(0, x, y) ~ x * y, 1.5 * bc(t, 1, y) - Differential(x)(bc(t, 1, y)) ~ 0.2], bdom(1.0), [t, x, y], [bce, rke], Any[]; name = :robk
        )
        pk = discretize(sysk, LatticeDiscretization(Grid((10, 8)); T = Float64); inputs = [rke => fill(0.5, 10, 8)])
        c = @test_logs (:warn, r"the Robin face of `bc` on axis 1 \(high side\), whose diagonal is negative at these parameters, is not in the implicit operator and no bound sees it") match_mode = :any only(
            init(
                pk,
                BackwardEuler(; dt = 0.1)
            ).runtimes
        ).cache
        @test !c.exact && !c.seen && c.newton == 4
    end
end

@testitem "r1 M3: a scaled row keeps the face coefficient with the largest bound" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 M3: a scaled row keeps the face coefficient with the largest bound" begin
        @parameters rW[1:2] = [50.0, 200.0]
        @variables rq(..)::Int32 [input = true]
        rqe = rq(t, x, y)
        kind = Int32[(i + j) % 2 + 1 for i in 1:16, j in 1:16]
        for (rate, out) in (
                (at(rW, rqe) * Δ(bce) + 0.01 * DivKGrad(:harmonic)(1 + x, bce) - bce, "0.01DivKGrad(:harmonic)(1 + x, bc)"),
                # the reversed weights: the face coefficient's term is the stiff one
                (0.0001 * at(rW, rqe) * Δ(bce) + 5 * DivKGrad(:harmonic)(1 + x, bce) - bce, "0.0001at(rW, rq)*Δ(bc)"),
            )
            sys = PDESystem([D(bce) ~ rate], [bc(0, x, y) ~ x], bdom(0.2), [t, x, y], [bce, rqe], [rW]; name = :scaled)
            p = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64); inputs = [rqe => kind])
            ig = init(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
            row = only(only(ig.runtimes).cache.rows).op
            @test only(row.inexact) == "`$out` (in the rate of `bc`)" && isempty(row.unseen) && only(ig.runtimes).cache.seen
            # base: the first term in the canonical order stays (here the small one), the stiff term
            # is out and unseen: `newton = 4`, a warning, and `ConvergenceFailure` in window 1
            s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
            @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
            ref = direct_be(sys, (16, 16), 0.05, 0.2, ig.substeps; inputs = [rqe => kind])
            @test r1rel(vec(blast(s)), ref) < 1.0e-4                              # (base: 1.8e8, diverged)
        end
    end
end
