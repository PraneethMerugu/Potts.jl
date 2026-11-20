# Robin coefficients α and β that vary by site or in
# time. Each lowers into a value field read by the face rule (`FaceRule.afield`, `bfield`);
# a row with such a face is a field row, whose `jac:` kernel writes the boundary diagonal `w
# d⁺` per site (the negative part stays out of the operator per site: a defect correction,
# and the operator is exact only when no site can be negative). The tests compare one window
# with the hand matrix of the ghost rule (`hand_rate`, `be_hand` of implicit.jl), a
# time-varying α with owned ExplicitEuler at a small step, and Dual derivatives with finite
# differences. Before the fix (ca232825): every discretize refuses the coefficient ("the
# Robin coefficient `1 + y` must be one value at every site; it reads `y`").

@testsetup module LP_robin_site
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
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/export_all.jl")
end

@testitem "per-site α and β equal the hand ghost-rule matrix (BackwardEuler, \
    ExplicitEuler)" setup = [LP_robin_site] tags = [
    :latticepde, :robin_site,
] begin
    @testset "per-site α and β equal the hand ghost-rule matrix (BackwardEuler, \
        ExplicitEuler)" begin
        h = 0.05
        p = rsown(
            rsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], rs_bcs(), [
                    bD, bk, bg,
                ]
            )
        )
        # the face rules read value fields; the row is a field row
        fr = [
            r
                for r in p.program.rules
                if r isa LatticeFields.IR.FaceRule && LatticeFields.IR.sitecoefs(r)
        ]
        @test length(fr) == 2 && fr[1].afield != 0 && fr[2].bfield != 0
        ig, u0, u = rs_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        want = be_hand(
            u0, h; dims = RSD, K = (x, y) -> 0.3,
            k = (x, y) -> 2.0, f = (x, y) -> x, faces = rs_faces()
        )
        rt = only(ig.runtimes)
        @test maximum(abs, u .- want) < 1.0e-10 && rt.cache.rows[1].op.field &&
            rt.cache.exact && rt.cache.newton == 1
        # the explicit rate is the hand rate (one small window)
        ig, u0, u = rs_window(p, ExplicitEuler(; substeps = 1); dt = 1.0e-3)
        L, b = hand_rate(;
            dims = RSD, K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = rs_faces()
        )
        @test maximum(abs, u .- (u0 .+ 1.0e-3 .* (L * u0 .+ b))) < 1.0e-12
        # the default count sees the faces (the bound over the face's sites): the count is
        # finite
        @test LFP.substeps(p, ExplicitEuler(); dt = 0.5) >= 1
    end
end

@testitem "a per-site α equal to a uniform one gives the uniform face's result" setup = [
    LP_robin_site,
] tags = [
    :latticepde, :robin_site,
] begin
    @testset "a per-site α equal to a uniform one gives the uniform face's result" begin
        # `ifelse(y < 2, bg, 0)` reads `y` but is `bg` on every face site: a value field, a
        # field row (the multigrid folds its boundary diagonal with the shift); the result
        # is the scalar face's
        h = 0.05
        uni = rsown(
            rsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce], [
                    bc(0, x, y) ~ x * y,
                    bg * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~ 1.0,
                ],
                [bD, bk, bg]
            )
        )
        site = rsown(
            rsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce],
                [
                    bc(0, x, y) ~ x * y,
                    ifelse(y < 2.0, bg, 0.0) * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~
                        1.0,
                ], [
                    bD, bk, bg,
                ]
            )
        )
        for inner in (BTIGHT, LatticeMultigrid(; reltol = 1.0e-12, maxiters = 64))
            igu, _, uu = rs_window(uni, BackwardEuler(; linsolve = inner); dt = h)
            igs, _, us = rs_window(site, BackwardEuler(; linsolve = inner); dt = h)
            @test !only(igu.runtimes).cache.rows[1].op.field &&
                only(igs.runtimes).cache.rows[1].op.field
            @test maximum(abs, uu .- us) < 1.0e-10
        end
        @test LFP.substeps(uni, ExplicitEuler(); dt = 0.5) ==
            LFP.substeps(site, ExplicitEuler(); dt = 0.5)
    end
end

@testitem "a mixed-sign α works per site (defect correction; not exact)" setup = [
    LP_robin_site,
] tags = [
    :latticepde, :robin_site,
] begin
    @testset "a mixed-sign α works per site (defect correction; not exact)" begin
        # α = y − 0.4 on x = 0: d = α/(α/2 + β/h) changes sign along the face
        h = 0.05
        bcs = [
            bc(0, x, y) ~ x * y, (y - 0.4) * bc(t, 0, y) + Differential(x)(bc(t, 0, y)) ~
                0.5,
        ]
        p = rsown(rsys([D(bce) ~ bD * laplacian(bce) - bk * bce + x], bcs, [bD, bk]))
        faces = Dict((1, -1) => (:robin, (x, y) -> y - 0.4, 1.0, 0.5))
        ig, u0, _ = rs_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        c = only(ig.runtimes).cache
        @test !c.exact && c.newton > 1
        ig, u0, u = rs_window(
            p, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 30), linsolve = BTIGHT);
            dt = h
        )
        want = be_hand(
            u0, h; dims = RSD, K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces
        )
        @test maximum(abs, u .- want) < 1.0e-3 &&
            only(ig.runtimes).totals.newton_budget == 0
        # the same face with α ≥ 0 at every site is exact (the sign is per site, from the
        # bound)
        p2 = rsown(
            rsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x],
                [
                    bc(0, x, y) ~ x * y, (y + 0.1) * bc(t, 0, y) -
                        Differential(x)(bc(t, 0, y)) ~ 0.5,
                ], [bD, bk]
            )
        )
        @test only(init(p2, BackwardEuler(); dt = h).runtimes).cache.exact
    end
end

@testitem "a time-varying α (BackwardEuler rebuilt at each stage; ExplicitEuler at a \
    small step)" setup = [LP_robin_site] tags = [
    :latticepde, :robin_site,
] begin
    @testset "a time-varying α (BackwardEuler rebuilt at each stage; ExplicitEuler at a \
        small step)" begin
        bcs = [
            bc(0, x, y) ~ x * y,
            (1.5 + sin(4t)) * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~ 1.0,
        ]
        p = rsown(rsys([D(bce) ~ bD * laplacian(bce) - bk * bce], bcs, [bD, bk]; T = 0.5))
        ig = init(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.05)
        @test only(ig.runtimes).cache.timed
        # the rate at time t reads α(t): one explicit window at t0 = 0 equals the hand rate
        # there
        _, u0, u = rs_window(p, ExplicitEuler(; substeps = 1); dt = 1.0e-3)
        L, b = hand_rate(;
            dims = RSD, K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            faces = Dict((1, -1) => (:robin, 1.5, -1.0, 1.0))
        )
        @test maximum(abs, u .- (u0 .+ 1.0e-3 .* (L * u0 .+ b))) < 1.0e-12
        # BackwardEuler converges to the explicit solution (first order in dt)
        ref = solve(p, ExplicitEuler(; substeps = 1); dt = 1.0e-4).u[end]
        errs = map((0.02, 0.01)) do dt
            maximum(abs, solve(p, BackwardEuler(; linsolve = BTIGHT); dt).u[end] .- ref)
        end
        @test errs[2] < 0.6 * errs[1] && errs[2] < 5.0e-3
        @test LFP.substeps(p, ExplicitEuler(); dt = 0.5) >= 1
    end
end

@testitem "ExplicitEuler's default count re-bounds each window over its time span" setup = [
    LP_robin_site,
] tags = [
    :latticepde, :robin_site,
] begin
    @testset "ExplicitEuler's default count re-bounds each window over its time span" begin
        # α(t) = −1 − 40t with the outward β = 1/h > 0: the ghost diagonal d = α/(α/2 + β/h)
        # is negative and grows in size with t, so the face's excess |d − 1| − 1 (and the
        # count) grows
        bcs = [
            bc(0, x, y) ~ x * y, (-1 - 40t) * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~
                0.0,
        ]
        p = rsown(rsys([D(bce) ~ laplacian(bce)], bcs, Any[]; T = 0.5))
        @test Problems.reads_time(p.stability)
        ig = init(p, ExplicitEuler(); dt = 0.1)
        rt = only(ig.runtimes)
        ns = Int[]
        for w in 1:5
            step!(ig)
            push!(ns, rt.n)
            # the window's count is the policy's at the bound over [t, t + dt]
            Problems.bound_window!(p.stability, 0.1 * (w - 1), 0.1 * w)
            @test rt.n == LFP.substeps(p, ExplicitEuler(); dt = 0.1)
        end
        @test issorted(ns) && ns[end] > ns[1] &&
            SciMLBase.check_error(ig) == ReturnCode.Success
        @test all(isfinite, ig[bce])
        # a bound that does not read the time keeps its count (no re-bound)
        q = rsown(
            rsys(
                [D(bce) ~ laplacian(bce)],
                [
                    bc(0, x, y) ~ x * y,
                    (1 + y) * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~
                        0.0,
                ],
                Any[]
            )
        )
        @test !Problems.reads_time(q.stability) &&
            only(init(q, ExplicitEuler(); dt = 0.1).runtimes).recount === nothing
    end
end

@testitem "Dual parameters in per-site α and β (BackwardEuler, ExplicitEuler)" setup = [
    LP_robin_site,
] tags = [
    :latticepde, :robin_site,
] begin
    @testset "Dual parameters in per-site α and β (BackwardEuler, ExplicitEuler)" begin
        @parameters ra = 1.2 rb = 0.7
        bcs = [
            bc(0, x, y) ~ x * y, ra * (1 + y) * bc(t, 0, y) -
                rb * (1 + x) * Differential(x)(bc(t, 0, y)) ~ 1.0,
            (1 + x) * bc(t, x, 1) + rb * Differential(y)(bc(t, x, 1)) ~ 0.5,
        ]
        p = rsown(
            rsys([D(bce) ~ bD * laplacian(bce) - bk * bce], bcs, [bD, bk, ra, rb]; T = 0.2)
        )
        for (q, v0) in ((ra, 1.2), (rb, 0.7)),
                alg in (BackwardEuler(; linsolve = BTIGHT), ExplicitEuler())

            J(v) = sum(solve(remake(p; p = [q => v]), alg; dt = 0.05).u[end])
            d = ForwardDiff.derivative(J, v0)
            fd = (J(v0 + 1.0e-6) - J(v0 - 1.0e-6)) / 2.0e-6
            @test abs(d - fd) < 1.0e-5 * abs(fd) && abs(fd) > 1.0e-3 ||
                (println("Dual ", q, " ", d, " ", fd); false)
        end
    end
end

# A per-site Robin face whose diagonal is positive at every site anchors a
# QuasiSteady group's steady gain (its smallest diagonal over the sites). Base (895c1a02):
# the face did not count, so the loop was refused ("`qa` has no decay and no Dirichlet or
# Robin face").
@testitem "a per-site Robin face anchors a QuasiSteady group" setup = [
    LP_robin_site,
] tags = [
    :latticepde, :robin_site,
] begin
    @testset "a per-site Robin face anchors a QuasiSteady group" begin
        @variables qa(..) qb(..)
        qae, qbe = qa(t, x, y), qb(t, x, y)
        p = discretize(
            PDESystem(
                [
                    D(qae) ~ 0.1 * laplacian(qae) + 0.05 * qbe,
                    D(qbe) ~ 0.1 * laplacian(qbe) - qbe - 0.05 * qae,
                ],
                [
                    qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0,
                    (1 + y) * qa(t, 0, y) - Differential(x)(qa(t, 0, y)) ~ 0.0,
                ],
                bdom(1.0), [t, x, y], [qae, qbe], Any[]; name = :anch
            ), LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        ig = init(p, FieldGroups(qae => QuasiSteady(), qbe => BackwardEuler()); dt = 0.1)
        step!(ig)
        @test SciMLBase.check_error(ig) == ReturnCode.Success && all(isfinite, ig[qae])
    end
end
