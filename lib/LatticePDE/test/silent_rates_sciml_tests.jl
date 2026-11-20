# Split from silent_tests.jl; uses LP_silent setup.

@testitem "F2 (g): a table-read diffusion multiplier takes an automatic count" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (g): a table-read diffusion multiplier takes an automatic count" begin
        # (g) a multiplier read from tables is site diffusion with a bound (bda31989:
        #     refused, "no
        # automatic substeps"); the count is within 10 % of the true one (8², every site
        # kind 2)
        @parameters Da[1:2] = [1.0, 3.0] Db[1:2] = [0.5, 0.0]
        sys = ssys(
            [D(ce) ~ (value_at(Da, qe) - value_at(Db, qe) + 2) * laplacian(ce)], [
                c(0, x, y) ~
                    1.0 +
                    sin(
                    1000x +
                        700y
                ),
            ], [
                ce, qe,
            ], [Da, Db];
            T = 0.02
        )
        K2 = fill(Int32(2), 8, 8)
        ρt = sradius(sys, 8, [qe => K2])
        sol = solve(sown(sys; n = 8, inputs = [qe => K2]), ExplicitEuler(); dt = 0.01)
        @test ceil(Int, 0.01 * ρt / 1.8) <= first(substep_counts(sol)) <=
            ceil(Int, 1.1 * 0.01 * ρt / 1.8) && sok(sol)
    end
end

@testitem "F2 (g): the anti-correlated multiplier and face coefficient are bounded \
    independently" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (g): the anti-correlated multiplier and face coefficient are bounded \
        independently" begin
        Dxs, Dys = Differential(x), Differential(y)
        # the anti-correlated case: m = 1/Dw at the site, K = the face mean of Dw over two
        # sites; a checkerboard puts m = 100 next to K ≈ 0.5 (row factor ≈ 50). One index
        # for m and K would give max_k Dw[k]/Dw[k] = 1, a count of 3 here; the bound takes
        # max|m| · max K = 100
        @parameters Dw[1:2] = [0.01, 1.0]
        Kc = checker(8, 1, 2)
        grouped = ceil(Int, 0.01 * 1.0 * 4 * 2 * 64 / 1.8)
        for (name, rate) in (
                (
                    "DivKGrad",
                    (1 / value_at(Dw, qe)) * DivKGrad(:arithmetic)(value_at(Dw, qe), ce),
                ),
                (
                    "raw flux",
                    (1 / value_at(Dw, qe)) * Dxs(value_at(Dw, qe) * Dxs(ce)) +
                        (1 / value_at(Dw, qe)) * Dys(value_at(Dw, qe) * Dys(ce)),
                ),
            )
            sys = ssys(
                [D(ce) ~ rate], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)],
                [ce, qe], [Dw]; T = 0.02
            )
            ρt = sradius(sys, 8, [qe => Kc])
            p = sown(sys; n = 8, inputs = [qe => Kc])
            sol = solve(p, ExplicitEuler(); dt = 0.01)
            @test grouped == 3 &&
                first(substep_counts(sol)) >= ceil(Int, 0.01 * ρt / 1.8) &&
                first(substep_counts(sol)) > grouped && sok(sol)
            # negative control: a count under the true limit (dt ρ / n = 3 > 2) grows
            # without bound, where the bound's count stays within the start's range. (Half
            # the bound's count is stable here: on these checkerboards the Gershgorin bound
            # is about twice the true radius.)
            nb = floor(Int, 0.01 * ρt / 3)
            # 2000 substeps
            pl = remake(p; tspan = (0.0, 0.01 * cld(2000, nb)))
            ig = init(pl, ExplicitEuler(); dt = 0.01)
            ig.substeps = nb
            @test sgrew(solve!(ig)) && !sgrew(solve(pl, ExplicitEuler(); dt = 0.01))
        end
    end
end

@testitem "F2 (g): an explicit count under a site-diffusion bound is raised" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (g): an explicit count under a site-diffusion bound is raised" begin
        # an explicit count under the bound is raised (bda31989: n = 2 kept, 1.7e75,
        # Success), and the solution stays within its initial range
        @parameters Dw3[1:3] = [0.01, 1.0, 1.0]
        sys = ssys(
            [D(ce) ~ (1 / value_at(Dw3, qb)) * laplacian(ce)],
            [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qb], [Dw3]
        )
        Kb = checker(4, 1, 2)
        p = sown(sys; inputs = [qb => Kb])
        sol = solve(p, ExplicitEuler(; substeps = 2); dt = 0.025)
        m0 = maximum(abs, sol[:c, 1])
        @test substep_counts(sol)[1] == ceil(Int, 0.025 * 100 * 128 / 1.8) && sok(sol) &&
            maximum(abs, sol[:c, end]) <= m0
        ρt = sradius(sys, 4, [qb => Kb])
        @test first(substep_counts(sol)) >= ceil(Int, 0.025 * ρt / 1.8)
        ig = init(p, ExplicitEuler(); dt = 0.025)
        # negative control: under the limit
        ig.substeps = floor(Int, 0.025 * ρt / 3)
        @test sgrew(solve!(ig)) && !sgrew(sol)
        # a negative entry is negative diffusion, refused
        @parameters Dwn[1:2] = [-0.01, 1.0]
        sys = ssys(
            [D(ce) ~ (1 / value_at(Dwn, qe)) * laplacian(ce)], [c(0, x, y) ~ 1.0], [
                ce, qe,
            ], [Dwn]
        )
        @test occursin(
            "is negative at these parameters", emsg(
                () -> solve(
                    sown(sys; inputs = [qe => checker(4, 1, 2)]),
                    ExplicitEuler()
                    ; dt = 0.025
                )
            )
        )
        # a row of `M A` is balanced, so site diffusion with a cross term is checked by the
        # rest of its row (305be9ad: the diagonal took min m · min K against max m · max K,
        # refused as coupled whenever m varies); a constant multiplier is the control
        @parameters Dk2[1:2] = [0.01, 1.0]
        for m in (value_at(Dk2, qe), 1.0)
            sys = ssys(
                [D(ce) ~ m * laplacian(ce) - 0.2ce - 0.1oe, D(oe) ~ -oe],
                [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0], [ce, oe, qe], [Dk2]
            )
            @test sok(
                solve(
                    sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler();
                    dt = 0.025
                )
            )
        end
        # … and a row that is not dominant (the cross term outweighs the reaction) on a loop
        # is still refused (`o` reads `c` back; one way it is bounded)
        sys = ssys(
            [
                D(ce) ~ value_at(Dk2, qe) * laplacian(ce) - 0.05ce - 0.1oe, D(oe) ~
                    -oe + 0.1ce,
            ],
            [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0],
            [ce, oe, qe],
            [Dk2]
        )
        @test occursin(
            "coupled",
            emsg(
                () ->
                solve(
                    sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler();
                    dt = 0.025
                )
            )
        )
    end
end

@testitem "F2 (j): an `ifelse` on an indicator takes its arm" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (j): an `ifelse` on an indicator takes its arm" begin
        # (j) an `ifelse` on an indicator takes its arm (bda31989: "Condition of `ifelse`
        #     must be a
        # `Bool`")
        @parameters kf = 100.0
        sys = ssys(
            [D(ce) ~ -ifelse(qe == 2, kf, 0) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [kf]
        )
        sol = solve(
            sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler();
            dt = 0.025
        )
        @test first(substep_counts(sol)) >= ceil(Int, 0.025 * 100 / 1.8) && sok(sol)
        # (the true radius)
        @test sradius(sys, 4, [qe => checker(4, 1, 2)]) ≈ 100
    end
end

@testitem "F2 (m): index forms take intervals" setup = [LP_silent] tags = [
    :latticepde,
    :silent,
] begin
    @testset "F2 (m): index forms take intervals" begin
        # (m) index forms: `2kb` and `max(k, 1)` never read index 0 or entry 1 here
        #     (bda31989:
        # refused at index 0); a wrong interval would read the zero entry `Dz4[1]`
        @parameters Dz4[1:3] = [0.0, 1.0, 2.0] Dy4[1:2] = [1.0, 2.0]
        for (rate, q, K, tab) in (
                (-(1 / value_at(Dz4, 2qb)) * ce, qb, checker(4, 1, 2), Dz4),
                (-(1 / value_at(Dy4, max(qe, 1))) * ce, qe, checker(4, 0, 2), Dy4),
            )
            sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, q], [tab])
            sol = solve(sown(sys; inputs = [q => K]), ExplicitEuler(); dt = 0.025)
            @test first(substep_counts(sol)) == 1 && sok(sol)
        end
    end
end

@testitem "F2 (h): index intervals over the current input values; writes are \
    rechecked" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (h): index intervals over the current input values; writes are \
        rechecked" begin
        # (h) the interval of an index is over the current input values: an undeclared index
        #     map
        # with no 0 takes an automatic count (bda31989: refused at index 0) …
        @parameters Tq[1:2] = [0.01, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Tq, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Tq]
        )
        p = sown(sys; inputs = [qe => checker(4, 1, 2)])
        sol = solve(p, ExplicitEuler(); dt = 0.025)
        @test substep_counts(sol)[1] == ceil(Int, 0.025 * 100 / 1.8) && sok(sol)
        # … and a write that brings index 0 is refused, naming the site; the run is
        # unchanged
        ig, ref = init(p, ExplicitEuler(); dt = 0.025), init(p, ExplicitEuler(); dt = 0.025)
        step!(ig)
        step!(ref)
        K0 = checker(4, 1, 2)
        K0[3, 2] = 0
        err = emsg(() -> (ig[qe] = K0))
        @test occursin("(3, 2)", err) && ig[qe] == checker(4, 1, 2)
        step!(ig)
        step!(ref)
        @test ig.substeps == ref.substeps && ig[ce] == ref[ce]
    end
end

@testitem "F2 (h): `kb - 1` reaches index 0 where `kb` holds a 1" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (h): `kb - 1` reaches index 0 where `kb` holds a 1" begin
        # `kb − 1` reaches index 0 where `kb` holds a 1, though `kb` never holds 0
        @parameters Tb[1:3] = [1.0, 1.0, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Tb, qb - 1)) * ce], [c(0, x, y) ~ 1.0], [ce, qb],
            [Tb]
        )
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qb => checker(4, 1, 2)]), ExplicitEuler(); dt = 0.025
        )
        # control: kb ≥ 2
        p = sown(sys; inputs = [qb => checker(4, 2, 3)])
        @test sok(solve(p, ExplicitEuler(); dt = 0.025))
        ig = init(p, ExplicitEuler(); dt = 0.025)
        @test_throws ArgumentError (ig[qb] = checker(4, 1, 2))
        @test ig[qb] == checker(4, 2, 3)
        @parameters Tz[1:2] = [1.0, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Tz, ifelse(qe == 1, 0, qe))) * ce],
            [c(0, x, y) ~ 1.0], [ce, qe], [Tz]
        )
        @test sok(
            solve(
                sown(sys; inputs = [qe => fill(Int32(2), 4, 4)]), ExplicitEuler();
                dt = 0.025
            )
        )
        K1 = fill(Int32(2), 4, 4)
        K1[3, 2] = 1
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => K1]), ExplicitEuler();
            dt = 0.025
        )
    end
end

@testitem "F2 (i): a coefficient not finite where the inputs reach is refused on every \
    path" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (i): a coefficient not finite where the inputs reach is refused on every \
        path" begin
        @parameters Dz5[1:2] = [0.0, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dz5, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Dz5]
        )
        @test_throws ArgumentError solve(
            discretize(
                sys, LatticeDiscretization(Grid((4, 4)); T = Float64);
                inputs = [qe => checker(4, 1, 2)]
            ), Tsit5()
        )
        @test discretize(
            # control: no kind 1
            sys, LatticeDiscretization(Grid((4, 4)); T = Float64);
            inputs = [qe => fill(Int32(2), 4, 4)]
        ) isa SciMLBase.ODEProblem
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => checker(4, 1, 2)]),
            ExplicitEuler(; substeps = 2); dt = 0.025
        )
    end
end

@testitem "F2 (l): the CPU pair-table `value_at` reads as the kernel does" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "F2 (l): the CPU pair-table `value_at` reads as the kernel does" begin
        J3 = reshape(collect(1.0:9.0), 3, 3)
        @test value_at(J3, 0, 1) == 0.0 && value_at(J3, 1, 0) == 0.0 &&
            value_at(J3, 9, 1) == J3[end, 1] && value_at(J3, -1, 9) == J3[1, end]
        # control
        @test value_at(J3, 2, 3) == J3[2, 3]
    end
end

@testitem "one ExplicitEuler; a FieldProblem needs its dt" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "one ExplicitEuler; a FieldProblem needs its dt" begin
        @test ExplicitEuler === LatticePDE.Problems.ExplicitEuler
        @parameters kd = 0.5
        p = sown(ssys([D(ce) ~ -kd * ce], [c(0, x, y) ~ 1.0], [ce], [kd]))
        @test_throws ArgumentError solve(p, ExplicitEuler())
        # (`lower_bound` clips in B too; the clip's tests are in groups.jl)
        @test all(
            ≈(0.95^10),
            solve(p, ExplicitEuler(; substeps = 1, lower_bound = 0.0); dt = 0.1)[:c, end]
        )
        @test_throws ArgumentError ExplicitEuler(; substeps = 0)
        # control
        @test all(≈(0.95^10), solve(p, ExplicitEuler(; substeps = 1); dt = 0.1)[:c, end])
    end
end

@testitem "trajectories on other tasks never share a right side's store" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "trajectories on other tasks never share a right side's store" begin
        @parameters kx = 0.05
        sys = ssys(
            [D(ce) ~ DivKGrad(:arithmetic)(Ke, ce) - ce, Ke ~ kx * (1 + ce^2)], [
                c(0, x, y) ~
                    1.0 + x,
            ], [
                ce, Ke,
            ], [kx];
            T = 0.01
        )
        o = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64))
        # (the build behind `o.f.f`)
        f = LFP.rhs_build(o)
        du, u = similar(o.u0), copy(o.u0)
        # the calling task owns the build
        f(du, u, o.p, 0.0)
        # … and its calls stay allocation-free
        @test (@allocated f(du, u, o.p, 0.0)) == 0
        # (its first call compiles)
        o.f.f(du, u, o.p, 0.0)
        # … also through the problem's function
        @test (@allocated o.f.f(du, u, o.p, 0.0)) == 0
        pk = [0.1]
        # (a function barrier)
        warm(fn, dd, uu, pp) = (fn(dd, uu, pp, 0.0); @allocated fn(dd, uu, pp, 0.0))
        function other(fn, uu, pp)
            dd = similar(uu)
            bytes = warm(fn, dd, uu, pp)
            return (dd, task_local_storage(fn.owner).value, bytes)
        end
        # builds the task's copy, then a warm call
        task = Threads.@spawn other(f, u, pk)
        d2, g, b = fetch(task)
        @test g isa typeof(f) && g.store !== f.store && g.owner[1] === task
        # (16 B per call, a lock)
        @test b == 0
        @test d2 ≈ (h = similar(du); f(h, u, pk, 0.0); h)
        # the build holds the copy
        @test only(values(f.copies)) === g
        # a dropped build frees its copies while the other task lives on (the task's
        # local storage held them: 20 builds ≈ 11 MiB kept while the Task was reachable)
        function dropped(f, u, pk)
            r = Ref{Any}(deepcopy(f))
            r[](similar(u), u, pk, 0.0)                               # owned by this task
            t3 = Threads.@spawn (
                h3 = r[]; h3(similar(u), u, pk, 0.0);
                WeakRef(task_local_storage(h3.owner).value)
            )
            w3 = fetch(t3)
            r[] = nothing
            return t3, w3
        end
        t3, w3 = dropped(f, u, pk)
        GC.gc()
        GC.gc()
        @test istaskdone(t3) && w3.value === nothing
        # a deep copy (SciML's safetycopy) is a build of its own, with no owner; so is a
        # serialized one ("cannot serialize a running Task" once a task owned the build)
        @test deepcopy(f).owner[1] === nothing
        io = IOBuffer()
        Serialization.serialize(io, f)
        f2 = Serialization.deserialize(seekstart(io))
        @test f2.owner[1] === nothing && f.owner[1] === current_task()
        # with threads: a shared function (safetycopy = false) gives the serial results
        # (base, 4 threads, 48², 16 trajectories: max |threads − serial| = 0.053, or NaN)
        if Threads.nthreads() > 1
            ks = collect(range(0.01, 0.2; length = 8))
            pf(prob, a, rest...) = remake(prob; p = [ks[a isa Integer ? a : a.sim_id]])
            ep = SciMLBase.EnsembleProblem(o; prob_func = pf, safetycopy = false)
            kw = (;
                trajectories = 8, abstol = 1.0e-8, reltol = 1.0e-8, save_everystep = false,
            )
            a = SciMLBase.solve(ep, Tsit5(), SciMLBase.EnsembleSerial(); kw...)
            b = SciMLBase.solve(ep, Tsit5(), SciMLBase.EnsembleThreads(); kw...)
            @test all(i -> a.u[i].u[end] == b.u[i].u[end], 1:8)
        end
    end
end

# the solvers' inner algorithms reach B by name, the same objects as
# A's (`test/fields.jl`): `LatticePCG`, `LatticeMultigrid` exported, `LatticePDE.VCycle`
# public. Base (1079c4ff): `UndefVarError: DevicePCG`.
@testitem "the inner solvers in B" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "the inner solvers in B" begin
        @test parentmodule(LatticePCG) === LatticePDE.Problems.Solvers &&
            LatticeMultigrid === LatticePDE.Problems.Solvers.LatticeMultigrid
        @test LatticePCG(;
            precs = LatticeMultigrid(; cycle = LatticePDE.VCycle(3, 3))
        ).precs.cycle ==
            LatticePDE.VCycle(3, 3)
        @test Base.ispublic(LatticePDE, :VCycle) && !Base.isexported(LatticePDE, :VCycle)
    end
end

# a linear solver given where a field algorithm goes is refused in B's
# words, naming it a linear solver (the `linsolve` of an implicit field solver), and the
# route works when followed. Before the fix (9db10886, 6 of 8 fail; the 2 that pass are the
# followed routes): `solve(p, DevicePCG())` is "MethodError: no method matching
# init(::FieldProblem…, ::DevicePCG)", `FieldGroups` says "`c(t, x, y) =>
# DevicePCG(Multigrid(LatticeFields.Solvers.V(2, 2), …` is not a field algorithm", and
# `ExplicitEuler(; dt, linsolve)` is a MethodError.
@testitem "a linear solver where B takes a field algorithm" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "a linear solver where B takes a field algorithm" begin
        @parameters Dm1 = 0.1
        p = discretize(
            psys([D(ce) ~ Dm1 * laplacian(ce)], [c(0, x, y) ~ x], [Dm1]),
            LatticeDiscretization(Grid((8, 8)); T = Float32)
        )
        @test_throws ArgumentError solve(p, LatticePCG())
        @test_throws ArgumentError init(p, LatticeMultigrid(; cycles = 3))
        # the route
        @test solve(p, ExplicitEuler(); dt = 0.01).retcode == SciMLBase.ReturnCode.Success
        @test_throws ArgumentError FieldGroups(ce => LatticePCG(; maxiters = 12))
        @test_throws ArgumentError FieldGroups(; default = LatticeMultigrid())
        @test solve(p, FieldGroups(ce => ExplicitEuler()); dt = 0.01).retcode ==
            SciMLBase.ReturnCode.Success
        @test_throws ArgumentError ExplicitEuler(; linsolve = LatticePCG())
        @test_throws ArgumentError ExplicitEuler(; step = 2)
    end
end
