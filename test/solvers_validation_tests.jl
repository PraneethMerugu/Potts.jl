# Solver and `@sweep` validation, depth bounds (D-130), field solver contracts, and the
# `stable_substeps` Fourier oracle.

@testitem "internal slot suffixes are reserved for declared names" setup = [
    SolversSetup,
] tags = [
    :potts, :solvers,
] begin
    @testset "internal slot suffixes are reserved for declared names" begin
        for suf in ("__ode", "__tick", "__next")
            nm = Symbol(:SuffixClash, suf)
            e = solver_err() do
                Core.eval(
                    @__MODULE__, quote
                        @potts_model $nm begin
                            @kinds medium A
                            @variables $(Symbol(:q, suf))(cell) = 1.0
                            @lattice Lattice((8, 8))
                            @energy cells => (volume - 9.0)^2
                            @sweep Metropolis(; temperature = 1.0)
                        end
                    end
                )
                Base.invokelatest(Base.invokelatest(getglobal, @__MODULE__, nm); name = :x)
            end
            while e isa LoadError
                e = e.error
            end
            @test e isa ArgumentError
        end
    end
end

@testitem "@sweep: combine judged by its printed form; offset must be a finite Real" setup =
    [SolversSetup] tags = [
    :potts, :solvers,
] begin
    @testset "@sweep: combine judged by its printed form; offset must be a finite \
        Real" begin
        spec(; kw...) = Potts.sweep_spec(:metropolis; temperature = 1.0, kw...)
        anon = (a, b) -> a
        for c in (
                anon, Base.Fix2(anon, 1), SweepHolder(anon),
                SweepHolder(SweepHolder(anon)),
            )
            e = solver_err(() -> spec(combine = c))
            @test e isa ArgumentError
        end
        for c in (
                min, max, min ∘ max, splat(min), SweepFnSub(),
                SweepMix(0.7), SweepHolder(min), Base.Fix2(min, 1),
            )
            @test spec(combine = c).combine === c
        end
        for o in (:a, "1", nothing, 1 + 1im, NaN, Inf32, -Inf)
            e = solver_err(() -> spec(offset = o))
            @test e isa ArgumentError
        end
        @test spec(offset = 2).offset === 2.0 && spec(offset = -1.5f0).offset === -1.5f0
    end
end

# `mcs_duration` validation (D-126): the `offset`,
# `combine` and `mcs_duration` checks also live in the `SweepSpec` constructor, so a
# hand-built spec passed to `PottsSystem(; sweep)` cannot bypass them, and its errors are
# those of `@sweep`.
@testitem "@sweep: mcs_duration validated; a hand-built SweepSpec is checked too" setup = [
    SolversSetup,
] tags = [
    :potts, :solvers,
] begin
    @testset "@sweep: mcs_duration validated; a hand-built SweepSpec is checked too" begin
        spec(; kw...) = Potts.sweep_spec(:metropolis; temperature = 1.0, kw...)
        hand(o, md) = Potts.SweepSpec(:metropolis, 1.0, min, o, md)
        function sys(sw)
            return Potts.PottsSystem(;
                name = :hand, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
                energies = [Potts.energy(Potts.cells(1) => (Potts.B.volume - 9.0)^2)],
                sweep = sw
            )
        end
        isoff(e) = e isa ArgumentError
        ismd(e) = e isa ArgumentError
        bad_md = (
            NaN, Inf, -Inf, NaN32, Inf32, 0, 0.0, -0.0, -1, -0.5f0, big"1e400", big"1e-400",
            :a, "1", nothing, 1 + 1im,
        )
        for md in bad_md
            @test ismd(solver_err(() -> spec(mcs_duration = md)))
            @test ismd(solver_err(() -> hand(0.0, md)))
            @test ismd(solver_err(() -> sys(hand(0.0, md))))
        end
        for o in (NaN, Inf32, -Inf, big"1e400", :a, "1", 1 + 1im)
            @test isoff(solver_err(() -> spec(offset = o)))
            @test isoff(solver_err(() -> hand(o, 1.0)))
            @test isoff(solver_err(() -> sys(hand(o, 1.0))))
        end
        # an unstable `combine` is rejected by hand too; a named or callable-struct one is
        # accepted
        iscomb(e) = e isa ArgumentError
        anon = (a, b) -> a
        for c in (anon, Base.Fix2(anon, 1))
            @test iscomb(solver_err(() -> Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0)))
            @test iscomb(solver_err(() -> sys(Potts.SweepSpec(:barker, 1.0, c, 0.0, 1.0))))
        end
        for c in (max, SweepMix(0.3), Base.Fix2(min, 1))
            @test Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0).combine === c
            @test Potts._p(
                sys(Potts.SweepSpec(:metropolis, 1.0, c, 0.0, 1.0)),
                :sweep
            ).combine ===
                c
        end
        # the order of `@sweep`'s checks: offset, then combine, then mcs_duration
        @test isoff(solver_err(() -> spec(offset = NaN, combine = anon, mcs_duration = 0)))
        @test iscomb(solver_err(() -> spec(combine = anon, mcs_duration = 0)))
        @test isoff(solver_err(() -> Potts.SweepSpec(:metropolis, 1.0, anon, NaN, 0)))
        # accepted values are stored as `float` of the value (its own float type), by
        # `@sweep` and by hand alike
        for md in (1, 0.5f0, 3 // 2, big"0.25", 1.0e300, floatmin(Float64), nextfloat(0.0))
            @test isequal(spec(mcs_duration = md).mcs_duration, float(md))
            @test spec(mcs_duration = md).mcs_duration isa typeof(float(md))
            @test isequal(hand(2, md).mcs_duration, float(md)) && hand(2, md).offset === 2.0
        end
        # control: a valid hand-built spec builds, compiles, and fingerprints like the
        # `@sweep` one
        good = sys(hand(0, 0.5))
        @test Potts._p(good, :sweep).mcs_duration === 0.5
        function fp(sw)
            σ = zeros(Int32, 8, 8)
            σ[3:5, 3:5] .= 1
            return PottsProblem(
                mtkcompile(sys(sw)), [ownership => σ, kind => [:A]],
                (0, 2)
            ).f.fingerprint
        end
        @test fp(hand(0, 0.5)) == fp(spec(mcs_duration = 0.5))
        # control
        @test fp(hand(0, 0.5)) != fp(spec(mcs_duration = 0.25))
    end
end

@testitem "canonical depth: values too deep are PottsCompileError naming the part" setup = [
    SolversSetup,
] tags = [
    :potts, :solvers,
] begin
    @testset "canonical depth: values too deep are PottsCompileError naming the part" begin
        deep = solver_deep_relation(9)
        @test deep isa Potts.PottsCompileError
        # control: the same relation within the cap compiles and runs
        ok = solver_deep_relation(3)
        @test ok isa Potts.CompiledPottsSystem
        σ = zeros(Int32, 12, 12)
        σ[3:5, 3:5] .= 1
        @test Symbol(
            solve(
                PottsProblem(ok, [ownership => σ, kind => [:A]], (0, 2)),
                SequentialCPM()
            ).retcode
        ) ===
            :Success
        # a constant in an expression key (`_symkey`): too deep names it, within the cap
        # prints
        e = solver_err(() -> Potts._symkey(solver_nest(12)))
        @test e isa Potts.PottsCompileError
        @test Potts._symkey(solver_nest(3)) isa String
        cyc = Ref{Any}(nothing)
        cyc[] = cyc
        @test solver_err(() -> Potts._symkey(cyc)) isa Potts.PottsCompileError
    end
end

@testitem "field solvers: one ExplicitEuler for coupled and standalone routes" setup = [
    SolversSetup,
] tags = [
    :potts, :solvers,
] begin
    @testset "field solvers: one ExplicitEuler for coupled and standalone routes" begin
        m = Module()
        Core.eval(m, :(using Potts; using Potts.LatticePDE))
        @test Core.eval(m, :ExplicitEuler) === Potts.ExplicitEuler ===
            Potts.LatticePDE.ExplicitEuler ===
            Potts.LatticeFields.Problems.ExplicitEuler
        @test Core.eval(m, :ExplicitMap) === Potts.LatticePDE.ExplicitMap
        # `substeps = 0` is no count: an ArgumentError with the route
        sv_throws(
            ArgumentError, ["`substeps = 0` is not a count", "leave `substeps` out"],
            () -> ExplicitEuler(; substeps = 0)
        )
        # the window is a keyword of `solve`, not of the algorithm: `dt` is no constructor
        # keyword
        sv_throws(
            ArgumentError, ["ExplicitEuler", "keyword of `solve`"], () -> ExplicitEuler(;
                dt = 0.5
            )
        )
        @test ExplicitEuler(; substeps = 3).substeps == 3 &&
            !hasproperty(ExplicitEuler(), :dt)   # control
        # a `PottsProblem` steps over the MCS window; a rate field refuses `ExplicitMap` by
        # name
        op = [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:A]]
        sv_throws(
            ArgumentError, ["`ExplicitMap()` steps discrete maps"],
            () -> PottsProblem(
                SolverOneField(; name = :f), op, (0, 1);
                field_solver = ExplicitMap()
            )
        )
        @test PottsProblem(
            SolverOneField(; name = :f), op, (0, 1);
            field_solver = ExplicitEuler()
        ) isa
            PottsProblem   # control
        # an ODE's `substeps = nothing` is one step, keyword-built
        @test Potts._ode_solver(ExplicitEuler()) === ExplicitEuler(; substeps = 1)
        sol = solve(
            PottsProblem(SolverPairYS(; name = :p), solver_op(), (0, 1)),
            SequentialCPM()
        )
        # one Euler step: (1, 0) → (1, 1)
        @test sol.u[end].cell.y[1] == 1.0 && sol.u[end].cell.s[1] == 1.0
    end
end

# The default field solver (amends D-075)
@testitem "a field takes ExplicitEuler() by default" setup = [SolversSetup] tags = [
    :potts, :solvers,
] begin
    @testset "a field takes ExplicitEuler() by default" begin
        op = [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:A]]
        # builds with the default …
        d = PottsProblem(SolverOneField(; name = :f), op, (0, 2))
        e = PottsProblem(
            SolverOneField(; name = :f), op, (0, 2);
            field_solver = ExplicitEuler()
        )
        @test d.f.sys.solvers.canonical == e.f.sys.solvers.canonical
        # … and fingerprints alike
        @test d.f.fingerprint == e.f.fingerprint
        @test solve(d, SequentialCPM()).u[end].site.c ==
            solve(e, SequentialCPM()).u[end].site.c
        # negative control: another solver changes the fingerprint
        @test PottsProblem(
            SolverOneField(; name = :f), op, (0, 2);
            field_solver = ExplicitEuler(; substeps = 3)
        ).f.fingerprint !=
            d.f.fingerprint
        # a field solver given to a model with no field is still an error (PO07)
        sv_throws(
            ArgumentError, ["has no field to integrate"],
            () -> PottsProblem(
                SolverPairYS(; name = :p), solver_op(), (0, 1);
                field_solver = ExplicitEuler()
            )
        )
    end
end

@testitem "stable_substeps hand table and Fourier amplification/tightness oracle" setup = [
    SolversSetup,
] tags = [
    :potts, :solvers,
] begin
    @testset "stable_substeps hand table and Fourier amplification/tightness oracle" begin
        LP = Potts.LatticePDE
        LFP = Potts.LatticeFields.Problems
        t, Dt = FieldPDE.t, FieldPDE.Dt
        FieldPDE.@variables u1(..) u2(..) u3(..)
        FieldPDE.@parameters x y z Dp kp

        function build_field_prob(dims, spacing, Dval, kval, dtval)
            N = length(dims)
            xs = (x, y, z)[1:N]
            ufn = (u1, u2, u3)[N]
            c = ufn(t, xs...)
            dom = LP.lattice_domain(t, xs, dims; spacing, tspan = (0.0, dtval))
            sys = LP.PDESystem(
                [Dt(c) ~ Dp * LP.laplacian(c) - kp * c], [ufn(0, xs...) ~ 0.0],
                dom, [t; collect(xs)], [c], [Dp, kp]; name = :ss
            )
            return LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(dims); T = Float64)),
                [Dp => Dval, kp => kval]
        end

        rows = (
            ((12,), (1.0,), 0.1, 0.05, 1.0),
            ((12,), (0.5,), 0.2, 0.1, 1.0),
            ((12,), (1.0,), 0.0, 0.5, 1.0),
            ((12,), (1.0,), 0.0, 2.5, 1.0),
            ((8, 8), (1.0, 1.0), 0.1, 0.05, 1.0),
            ((8, 8), (1.0, 1.0), 0.5, 0.2, 1.0),
            ((8, 8), (0.5, 1.0), 0.25, 0.1, 0.5),
            ((8, 8), (0.5, 0.5), 0.2, 0.3, 1.0),
            ((8, 8), (1.0, 1.0), 0.3, 0.0, 2.0),
            ((6, 6, 6), (1.0, 1.0, 1.0), 0.1, 0.1, 1.0),
            ((6, 6, 6), (0.5, 1.0, 1.0), 0.2, 0.5, 1.0),
            ((6, 6, 6), (1.0, 1.0, 1.0), 0.25, 1.2, 0.8),
        )

        thetas = range(0.0, pi; length = 9)
        for (dims, spacing, Dval, kval, dtval) in rows
            prob, ps = build_field_prob(dims, spacing, Dval, kval, dtval)
            pr = remake(prob; p = ps)
            n = LFP.substeps(
                pr.problem_type.problem, ExplicitEuler(), pr.p.values;
                dt = dtval
            )
            rho = Dval * sum(4.0 / h^2 for h in spacing) + kval
            expected_n = max(1, ceil(Int, dtval * rho / 1.8))
            @test n == expected_n

            # Property 1: FTCS amplification factor <= 1 for every discrete Fourier mode
            hdt = dtval / n
            if length(dims) == 1
                for t1 in thetas
                    lam = Dval * (4.0 / spacing[1]^2 * sin(t1 / 2)^2) + kval
                    @test abs(1.0 - hdt * lam) <= 1.0
                end
            elseif length(dims) == 2
                for t1 in thetas, t2 in thetas
                    lam = Dval * (
                        4.0 / spacing[1]^2 * sin(t1 / 2)^2 +
                            4.0 / spacing[2]^2 * sin(t2 / 2)^2
                    ) + kval
                    @test abs(1.0 - hdt * lam) <= 1.0
                end
            else
                for t1 in thetas, t2 in thetas, t3 in thetas
                    lam = Dval * (
                        4.0 / spacing[1]^2 * sin(t1 / 2)^2 +
                            4.0 / spacing[2]^2 * sin(t2 / 2)^2 +
                            4.0 / spacing[3]^2 * sin(t3 / 2)^2
                    ) + kval
                    @test abs(1.0 - hdt * lam) <= 1.0
                end
            end

            # Property 2: tightness: (n - 1) violates the 1.8 safety margin
            if n > 1
                @test (dtval / (n - 1)) * rho > 1.8
            end
        end

        # Also verify end-to-end in a PottsProblem: Dc = 0.5, k = 0.2, 16x16, h = 1, dt = 1
        # -> ceil((0.5*8+0.2)/1.8) = 3
        p2 = PottsProblem(
            SolverField(; name = :f), [
                ownership => solver_sigma(), kind => [:A], :Dc => 0.5,
            ], (0, 1);
            field_solver = ExplicitEuler()
        )
        integ = init(p2, SequentialCPM())
        @test CorePotts._runtime(getfield(integ.ctx, :__fields1)).n ==
            max(1, ceil(Int, (0.5 * 8.0 + 0.05) / 1.8))
    end
end
