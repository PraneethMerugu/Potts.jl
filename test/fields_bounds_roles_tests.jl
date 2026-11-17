@testitem "F3-13 M1: Burgers in a model stays unseen (no frozen-velocity count)" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "F3-13 M1: Burgers in a model stays unseen (no frozen-velocity count)" begin
        c0 = [0.5 + 0.4 * sin(2π * (i - 0.5) / 32) for i in 1:32, j in 1:32]
        op = [ownership => zeros(Int32, 32, 32), kind => Symbol[], :c => c0]
        e = something(fd_err(() -> PottsProblem(FbBurgers(; name = :b), op, (0, 20); seed = 1, field_solver = ExplicitEuler())), "")
        @test occursin("Advect", e) && occursin("substeps", e)
        # (review r2 N1) the routes are a count or BackwardEuler; `bounds` cannot help this term
        @test occursin("velocity reads the field it moves", e) && occursin("BackwardEuler", e) && !occursin("`bounds", e)
        # the user's count (h = Δx/8, past the linearized limit Δx/4 at c ≡ 1): bounded, below 1
        pb = @test_logs (:warn, r"Advect") match_mode = :any PottsProblem(
            FbBurgers(; name = :b), op, (0, 20); seed = 1,
            field_solver = ExplicitEuler(; substeps = 8)
        )
        s = solve(pb, SequentialCPM())
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success
        @test 0.1 - 1.0e-6 <= minimum(s.u[end].site.c) && maximum(s.u[end].site.c) <= 0.91
    end
end

@testitem "F3-13 M2: declared intervals after the build in a model" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "F3-13 M2: declared intervals after the build in a model" begin
        RC = Potts.SciMLBase.ReturnCode
        dims = (16, 16)
        e = something(fd_err(() -> PottsProblem(FbDir3(; name = :f), fd_empty(dims), (0, 2))), "")
        @test occursin("field `c`: its condition on the face `x = 16.0` holds 3.0, outside the field's declared bounds (0.0, 1.0)", e)
        # the source drives c past 3 near MCS 3 (s = 1): `Unstable`, the run stops there, one warning
        pr = PottsProblem(FbDrift(; name = :f), fd_empty(dims), (0, 20))
        sol = @test_logs (:warn, r"field `c` left its declared bounds \(0\.0, 3\.0\): it holds .* by the end of the field step of MCS \d+") solve(
            pr,
            SequentialCPM()
        )
        @test sol.retcode == RC.Unstable && sol.t[end] < 20 && maximum(sol.u[end].site.c) > 3
        # with a decay that keeps it inside (s = 0.1: steady 2): no warning, to the end
        sol = @test_logs solve(remake(pr; p = [:s => 0.1]), SequentialCPM())
        @test sol.retcode == RC.Success && sol.t[end] == 20
        # the check reads the field after each MCS on the host and allocates nothing there
        integ = init(remake(pr; p = [:s => 0.1]), SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
        step!(integ); step!(integ)
        @test (@allocated step!(integ)) == 0
    end
end

@testitem "F3-13: the interval bound in a model (declared bounds, aux fields, coordinates, advection)" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "F3-13: the interval bound in a model (declared bounds, aux fields, coordinates, advection)" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        dims = (16, 16)
        Potts.ModelingToolkitBase.@parameters x y k = 2.0
        Potts.ModelingToolkitBase.@variables c(..) [bounds = (0.0, 1.0)] u(..) K(..)
        ce, ue, Ke = c(tt, x, y), u(tt, x, y), K(tt, x, y)
        dom = [tt ∈ LP.Interval(0.0, 2.0), x ∈ LP.Interval(0.0, 16.0), y ∈ LP.Interval(0.0, 16.0)]
        bcount(eqs, dvs, ps, ic) = (
            p = LP.discretize(
                MTKB.PDESystem(eqs, ic, dom, [tt, x, y], dvs, ps; name = :b),
                LP.LatticeDiscretization(LP.Grid(dims); T = Float64)
            ); LP.Problems.substeps(LP.Problems.field_problem(p), LP.ExplicitEuler(; dt = 1.0))
        )
        acount(M; kw...) = substep_counts(
            init(
                PottsProblem(M(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler(), kw...),
                SequentialCPM()
            )
        )
        # `DivKGrad(c, c)` with c ∈ (0, 1): ρ = 8 max K = 8, n = ⌈8/1.8⌉ = 5, as B
        @test acount(FbIvDivK) == [5] == [bcount([DD(ce) ~ LP.DivKGrad(:harmonic)(ce, ce)], [ce], Any[], [c(0, x, y) ~ 0.5])]
        # … and the run equals B's, bitwise (σ frozen: no cells)
        c0 = rand(StableRNG(13), dims...)
        a = Array(
            solve(
                PottsProblem(FbIvDivK(; name = :f), [fd_empty(dims); :c => c0], (0, 2); field_solver = ExplicitEuler()),
                SequentialCPM()
            ).u[end].site.c
        )
        bp = LP.discretize(
            MTKB.PDESystem(
                [DD(ce) ~ LP.DivKGrad(:harmonic)(ce, ce)], [c(0, x, y) ~ 0.5], dom, [tt, x, y], [ce], Any[];
                name = :b
            ), LP.LatticeDiscretization(LP.Grid(dims); T = Float64)
        )
        @test a == LP.solve(LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; dt = 1.0))[:c, end]
        # no declared interval: the term stays one the bound cannot see (the count is refused)
        e = something(fd_err(() -> PottsProblem(FbIvNoBounds(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler())), "")
        @test occursin("DivKGrad", e) && occursin("cannot see", e)
        # a field that starts outside its bounds; `bounds` on a variable that is not a field
        e = something(fd_err(() -> PottsProblem(FbIvOut(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler())), "")
        @test occursin("field `c` starts at 1.5, outside its declared bounds (0, 1)", e)
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables s(Potts.t)), :site; bounds = (0, 1))), "")
        @test occursin("variable `s`: `bounds` applies to fields", e)
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables s(Potts.t)), :field; bounds = (1, 0))), "")
        @test occursin("`bounds` is a pair `(lo, hi)` of numbers with lo ≤ hi", e)
        # an aux field through its definition: ρ = 0.1 · 8 + k, n = ⌈2.8/1.8⌉ = 2 (base: refused)
        @test acount(FbIvAux) == [2] ==
            [bcount([Ke ~ k * ue, DD(ue) ~ 0.1 * LP.Δ(ue) - Ke], [ue, Ke], Any[k], [u(0, x, y) ~ 0.5])]
        # a velocity that varies by site: ρ = 0.8 + 2 max|0.05 (1 + x)| over x ∈ [−0.5, 16.5], n = 2
        @test acount(FbIvAdvect) == [2] ==
            [bcount([DD(ue) ~ 0.1 * LP.Δ(ue) - LP.Advect(LP.Upwind1())([0.05 * (1 + x), 0.0], ue)], [ue], Any[], [u(0, x, y) ~ 0.5])]
    end
end

@testitem "F3-14: lattice_storage, compute_T and solver_T in a model (FE-17)" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "F3-14: lattice_storage, compute_T and solver_T in a model (FE-17)" begin
        σ = zeros(Int32, 12, 10)
        σ[3:5, 3:5] .= 1
        σ[8:10, 6:8] .= 2
        c0 = rand(StableRNG(14), 12, 10)
        prob(T, alg) = PottsProblem(
            FwRoles(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0, :h => c0, :s => c0], (0, 3);
            T, seed = 3, field_solver = alg
        )
        run(T, alg; M = FwRoles) = (
            integ = init(
                M === FwRoles ? prob(T, alg) :
                    PottsProblem(
                        FwWide(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0], (0, 3);
                        T, seed = 3, field_solver = alg
                    ), SequentialCPM()
            );
            foreach(_ -> step!(integ), 1:3); integ
        )
        # the stores have the declared types, the undeclared field the state type
        for T in (Float32, Float64)
            st = current_state(run(T, ExplicitEuler(substeps = 8)))
            @test (eltype(st.site.c), eltype(st.site.h), eltype(st.site.s), eltype(st.site.u)) == (Float64, Float16, Float32, T)
            @test eltype(st.site.c__next) == Float64
        end
        # a Float32 CPM with a Float64 field computed in Float64 equals the Float64 reference to
        # 1e-12 (measured: 0, bitwise); computed in Float32 (the control) it does not (5.7e-8)
        for (a32, ref) in (
                (ExplicitEuler(substeps = 8, compute_T = Float64), ExplicitEuler(substeps = 8)),
                (BackwardEuler(compute_T = Float64), BackwardEuler()),
            )
            a, b = run(Float32, a32; M = FwWide), run(Float64, ref; M = FwWide)
            @test maximum(abs, current_state(a).site.c .- current_state(b).site.c) < 1.0e-12
        end
        ctl = maximum(
            abs, current_state(run(Float32, ExplicitEuler(substeps = 8); M = FwWide)).site.c .-
                current_state(run(Float64, ExplicitEuler(substeps = 8); M = FwWide)).site.c
        )
        @test ctl > 1.0e-9
        # solver_T from A: the implicit solver's own type
        integ = init(
            PottsProblem(
                FwWide(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0], (0, 3); T = Float32,
                field_solver = BackwardEuler(solver_T = Float64)
            ), SequentialCPM()
        )
        rows = CorePotts._runtime(getfield(integ.ctx, :__fields1)).cache.rows
        @test all(r -> r.solver === nothing || r.solver.T == Float64, rows) && any(r -> r.solver !== nothing, rows)
        # refusals in the user's words
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables q(Potts.t)), :field; lattice_storage = BigFloat)), "")
        @test occursin("`lattice_storage` applies to fields and is `Float16`, `Float32` or `Float64`", e) && occursin("got BigFloat", e)
        e = something(fd_err(() -> ExplicitEuler(compute_T = Float16)), "")
        @test occursin("`compute_T` takes `:auto`", e)
    end
end

@testitem "batch-end review S4: compute_T = Float64 reaches a Float32 model's field kernels" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "batch-end review S4: compute_T = Float64 reaches a Float32 model's field kernels" begin
        run1(T, alg) = (
            integ = init(
                PottsProblem(FwNarrow(; name = :w), fd_empty((12, 10)), (0, 1); T, seed = 3, field_solver = alg),
                SequentialCPM()
            ); step!(integ); Array(current_state(integ).site.c)
        )
        wide, narrow = run1(Float32, ExplicitEuler(; substeps = 1, compute_T = Float64)), run1(Float32, ExplicitEuler(; substeps = 1))
        ref = run1(Float64, ExplicitEuler(; substeps = 1))
        @test eltype(wide) === eltype(narrow) === Float32
        @test maximum(abs, wide .- ref) < 1.0e-12 && maximum(abs, narrow .- ref) > 1.0e-8 ||
            (println("S4: ", maximum(abs, wide .- ref), " ", maximum(abs, narrow .- ref)); false)
    end
end

@testitem "F3-14 S1, S4 in a model: Float16 under the implicit algorithms; Dual parameters in words" setup = [FieldsSetup, FieldsBoundsRolesSetup] tags = [:potts, :fields] begin
    @testset "F3-14 S1, S4 in a model: Float16 under the implicit algorithms; Dual parameters in words" begin
        dims = (16, 16)
        for fs in (BackwardEuler(), BackwardEuler(; compute_T = Float64), CrankNicolson(), BDF2(), QuasiSteady())
            a = solve(PottsProblem(FbHalf(; name = :h), fd_empty(dims), (0, 10); field_solver = fs, T = Float32), SequentialCPM())
            b = solve(PottsProblem(FbFull(; name = :f), fd_empty(dims), (0, 10); field_solver = fs), SequentialCPM())
            ca, cb = a.u[end].site.c, b.u[end].site.c
            @test a.retcode == Potts.SciMLBase.ReturnCode.Success && eltype(ca) == Float16
            @test maximum(abs, Float64.(ca) .- cb) <= 4.0e-3 * maximum(abs, cb)
        end
        # (F3-21b: the Dual runs; its field carries derivative parts, its values are the primal run's)
        pf = PottsProblem(FbFull(; name = :f), fd_empty(dims), (0, 2))
        d = solve(remake(pf; p = [:k => ForwardDiff.Dual(0.05, 1.0)]), SequentialCPM()).u[end].site.c
        @test ForwardDiff.value.(d) == solve(pf, SequentialCPM()).u[end].site.c && all(<(0), ForwardDiff.partials.(d, 1))
        # an integrator write still takes plain numbers, refused in words (the value type, not the type)
        e = something(fd_err(() -> (integ = init(pf, SequentialCPM()); integ.ps[:k] = ForwardDiff.Dual(0.05, 1.0))), "")
        @test occursin("parameter `k` = a ForwardDiff `Dual` of Float64 (value 0.05) does not convert", e) &&
            occursin("A Dual goes to the problem", e) && !occursin("Tag", e) && length(e) < 1200
    end
end
