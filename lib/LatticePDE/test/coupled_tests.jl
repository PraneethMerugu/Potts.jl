# F3-12d: the coupled steady solve. A QuasiSteady group whose fields read one another (a cycle,
# a cross diffusion `D laplacian(o)`, a nonlinear cross term such as `c²`) solves its rows together:
# each Newton iteration is one restarted flexible GMRES solve (`LatticeGMRES`) of the whole
# Jacobian of the group's residual, preconditioned by each field's own multigrid solve. Every
# testset checks against an oracle that does not use the solver: the dense steady Jacobian of
# the `:ode` rate (assembled by columns), an exact solution, or a dense split recursion.
# Base (c40a68f8, ~/lpwork/f312d/nc-base-lp.log): the q1 loops in one steady group end
# `ConvergenceFailure` (block iteration ratio ≈ k/√(δμ) = 15.8, 1.6), the N5 rows warn
# (`nlsolve = LatticeNewton(; max_iter = 40)`), the feedback loop is refused ("reads the steady field … of the loop"), the
# indefinite pair is accepted (each row decays) and diverges, the strong `init = :steady` loop
# fails at t = 0, and `LatticeGMRES` is not defined.

@testsetup module LP_coupled
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
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
include("shared/grids.jl")
include("shared/coupled.jl")
include("shared/export_all.jl")
end

@testitem "the q1 loops in one QuasiSteady group equal the dense steady solve" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
    @testset "the q1 loops in one QuasiSteady group equal the dense steady solve" begin
    # every system is well posed (max Re λ < 0, reviewer probe s3); the block iteration's ratio
    # k/√(δμ) is 5, 15.8, 0.5 and 1.6: the coupled solve does not depend on it
    for (δ, k) in ((1.0, 5.0), (0.1, 5.0), (1.0, 0.5), (0.1, 0.5))
        A, b0 = cjac(q1(δ, k), (8, 8))
        want = -(A \ b0)
        for steady in (false, true), (inner, tol) in ((CTIGHT, 1e-9), (:auto, 2e-6))
                ig = init(cown(q1(δ, k; steady)), QuasiSteady(; linsolve = inner); dt = 0.1)
            step!(ig)
            c = only(ig.runtimes).cache
            got = vcat(vec(ig[cae]), vec(ig[cbe]))
                @test c.cs !== nothing && c.newton == 1 && SciMLBase.check_error(ig) == ReturnCode.Success
            @test maximum(abs, got .- want) / maximum(abs, want) < tol || (println("q1 ", (δ, k, steady, inner), " ",
                maximum(abs, got .- want) / maximum(abs, want)); false)
        end
    end
    # the same seed and backend repeat a run bit for bit (fixed-order reductions)
        run() = (s = solve(cown(q1(0.1, 5.0)), QuasiSteady(); dt = 0.1); (s[cae, end], s[cbe, end]))
    @test run() == run()
    # a warm window allocates nothing (CPU), and its solve starts at the last solution (F4-03:
    # the second window ends the span, where the end save copies the state: `save_end = false`)
        ig = init(cown(q1(0.1, 5.0)), QuasiSteady(); dt = 0.1, save_end = false, save_everystep = false)
    @test bwarm(ig) == 0
    # the solve's words: a budget hit names the GMRES budget; `show`, the keywords
        r = @test_logs (:warn, r"the linear solve reached its budget .*`linsolve = LatticeGMRES\(; maxiters = n\)`") match_mode = :any solve(
            cown(q1(0.1, 5.0)), QuasiSteady(; linsolve = LatticeGMRES(; maxiters = 2)); dt = 0.1
        )
    @test r.retcode == ReturnCode.Success
        g = LatticeGMRES(; gmres_restart = 8, maxiters = 40, reltol = 1.0e-8, precs = LatticeBlockSolve(LatticePCG(; maxiters = 3)))
    @test eval(Meta.parse(repr(g))) == g
        @test !occursin("maxiters", repr(LatticeGMRES()))               # a default stays out of the display
        @test startswith(cmsg(() -> LatticeGMRES(; gmres_restart = 1)), "`LatticeGMRES(; gmres_restart = 1)`: `gmres_restart` is the Krylov basis size")
        @test startswith(cmsg(() -> LatticeGMRES(; maxiters = 0)), "`LatticeGMRES(; maxiters = 0)`: `maxiters` is the most GMRES iterations")
        @test startswith(cmsg(() -> LatticeGMRES(; reltol = -1.0)), "`LatticeGMRES(; reltol = -1.0)`: `reltol` is the relative residual")
        @test startswith(cmsg(() -> LatticeBlockSolve(:pcg)), "`LatticeBlockSolve(:pcg)`: the block preconditioner solves each field with")
    op = LSB.CellOperator((8, 8); shift = 1.0)
        @test occursin(
            "solves an implicit group's fields together; a `FieldSolver` solves one field: give it the `LatticeGMRES`'s per-field solver, `linsolve = LatticePCG(; maxiters = 2)`",
            cmsg(() -> LSB.FieldSolver(KernelAbstractions.CPU(), op; linsolve = LatticeGMRES()))
        )
end
end

@testitem "a cross Δ in a steady row and `0 ~ q − c²`: no warning on a default run, equal to the oracle" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
    @testset "a cross Δ in a steady row and `0 ~ q − c²`: no warning on a default run, equal to the oracle" begin
    # a cross Δ in a cycle and one way; both linear: the dense steady solve of their rate form
        for (eqs, rates) in (
                (
                    [0 ~ 0.3 * laplacian(cae) + 0.1 * laplacian(cqe) - 2.0 * cae + x, 0 ~ 0.3 * laplacian(cqe) - cqe + 0.5 * cae],
                    [D(cae) ~ 0.3 * laplacian(cae) + 0.1 * laplacian(cqe) - 2.0 * cae + x, D(cqe) ~ 0.3 * laplacian(cqe) - cqe + 0.5 * cae],
                ),
                (
                    [0 ~ 0.3 * laplacian(cae) + 0.1 * laplacian(cqe) - 2.0 * cae + x, 0 ~ 0.3 * laplacian(cqe) - cqe + y],
                    [D(cae) ~ 0.3 * laplacian(cae) + 0.1 * laplacian(cqe) - 2.0 * cae + x, D(cqe) ~ 0.3 * laplacian(cqe) - cqe + y],
                ),
            )
        bcs = [ca(t, 0, y) ~ 1.0, cq(t, 0, y) ~ 0.0]
        A, b0 = cjac(PDESystem(rates, [bcs; ca(0, x, y) ~ 0.0; cq(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cqe], Any[]; name = :n5r), (8, 8))
        want = -(A \ b0)
        p = cown(PDESystem(eqs, bcs, bdom(0.2), [t, x, y], [cae, cqe], Any[]; name = :n5))
            r = @test_logs min_level = Logging.Warn solve(p, QuasiSteady(); dt = 0.1)
        got = vcat(vec(r[cae, end]), vec(r[cqe, end]))
        @test r.retcode == ReturnCode.Success && maximum(abs, got .- want) < 1e-5
            rt = solve(p, QuasiSteady(; linsolve = CTIGHT); dt = 0.1)
        @test maximum(abs, vcat(vec(rt[cae, end]), vec(rt[cqe, end])) .- want) < 1e-10
    end
        # `0 ~ q − c²` beside `0 ~ 0.3 * laplacian(c) − 2c + 1`: `c` is the linear steady state, `q = c²` exactly
        p = cown(
            PDESystem(
                [0 ~ cqe - cae^2, 0 ~ 0.3 * laplacian(cae) - 2.0 * cae + 1], [ca(t, 0, y) ~ 1.0, cq(0, x, y) ~ 0.0], bdom(0.2),
        [t, x, y], [cae, cqe], Any[]; name = :alg))
        A, b0 = cjac(
            PDESystem(
                [D(cae) ~ 0.3 * laplacian(cae) - 2.0 * cae + 1], [ca(t, 0, y) ~ 1.0, ca(0, x, y) ~ 0.0], bdom(0.2), [t, x, y],
        [cae], Any[]; name = :algc), (8, 8))
    cw = -(A \ b0)
        r = @test_logs min_level = Logging.Warn solve(p, QuasiSteady(); dt = 0.1)
    @test r.retcode == ReturnCode.Success && maximum(abs, vec(r[cae, end]) .- cw) < 1e-5 && maximum(abs, vec(r[cqe, end]) .- cw .^ 2) < 1e-5
        ig = init(p, QuasiSteady(); dt = 0.1)
    @test only(ig.runtimes).cache.cs !== nothing && only(ig.runtimes).cache.newton == 8      # (nonlinear: the checked count)
        rt = solve(p, QuasiSteady(; linsolve = CTIGHT); dt = 0.1)
    @test maximum(abs, vec(rt[cae, end]) .- cw) < 1e-10 && maximum(abs, vec(rt[cqe, end]) .- cw .^ 2) < 1e-10
    # a nonlinear cycle (Michaelis–Menten uptake, `0.5a²` feeding back): the rate is 0 at the result
        rates = [0.1 * laplacian(cae) - 2.0 * cae / (0.5 + cae) + cbe + x, 0.1 * laplacian(cbe) - cbe + 0.5 * cae^2]
    po = discretize(PDESystem([D(cae) ~ rates[1], D(cbe) ~ rates[2]], [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y],
        [cae, cbe], Any[]; name = :mmr), LatticeDiscretization(Grid((8, 8)); T = Float64))
    p = cown(PDESystem([0 ~ rates[1], 0 ~ rates[2]], [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe],
        Any[]; name = :mm))
    for (inner, tol) in ((:auto, 1e-5), (CTIGHT, 1e-12))
            r = @test_logs min_level = Logging.Warn solve(p, QuasiSteady(; linsolve = inner); dt = 0.1)
        u = vcat(vec(r[cae, end]), vec(r[cbe, end]))
        du = similar(u)
        po.f(du, u, po.p, 0.0)
        @test r.retcode == ReturnCode.Success && maximum(abs, du) < tol || (println("mm ", inner, " ", maximum(abs, du)); false)
    end
end
end

@testitem "F3-12d: a coupled steady pair feeding back through a transient field" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
@testset "F3-12d: a coupled steady pair feeding back through a transient field" begin
    # `a`, `b` steady and coupled (0.5 each way), `e` transient: `a` reads `e`, `e` reads `b`. The
    # loop's gain composes through the steady pair, `X = (I − M)⁻¹ (G ∘ e)`, M = G k = [0 ½; ½ 0]
        rates = [0.1 * laplacian(cae) - cae + 0.5 * cbe + 0.2 * cze, 0.1 * laplacian(cbe) - cbe - 0.5 * cae, 0.1 * laplacian(cze) - cze + 0.5 * cbe + x]
    bc0 = [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0, cz(0, x, y) ~ 0.0]
    p = cown(PDESystem([0 ~ rates[1], 0 ~ rates[2], D(cze) ~ rates[3]], bc0, bdom(1.0), [t, x, y], [cae, cbe, cze], Any[]; name = :fb))
        alg = FieldGroups(cze => BackwardEuler(; linsolve = BTIGHT); default = QuasiSteady(; linsolve = CTIGHT))
        r = solve(p, alg; dt = 0.1)
    @test r.retcode == ReturnCode.Success
    # the dense split recursion: each window the steady pair at `e`'s window-start values, then
    # `e`'s Backward Euler step reading them
    A, b0 = cjac(PDESystem([D(cae) ~ rates[1], D(cbe) ~ rates[2], D(cze) ~ rates[3]], bc0, bdom(1.0), [t, x, y], [cae, cbe, cze],
        Any[]; name = :fbr), (8, 8))
    s, e = 1:128, 129:192
    eh = zeros(64)
    for _ in 1:10
        ab = -(A[s, s] \ (b0[s] .+ A[s, e] * eh))
        eh = (I - 0.1 * A[e, e]) \ (eh .+ 0.1 .* (b0[e] .+ A[e, s] * ab))
    end
    @test maximum(abs, vec(r[cze, end]) .- eh) < 1e-9 || (println("feed ", maximum(abs, vec(r[cze, end]) .- eh)); false)
    # a strong steady coupling (k = 5, δ = 0.1) in the loop: the rule's bound sums magnitudes, so
    # it is refused with the reason and the routes (the pair alone solves: the first testset)
        ps = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - 0.1 * cae + 5.0 * cbe + 0.2 * cze, 0 ~ 0.1 * laplacian(cbe) - cbe - 5.0 * cae, D(cze) ~ rates[3]],
        bc0, bdom(1.0), [t, x, y], [cae, cbe, cze], Any[]; name = :fbs))
        m = cmsg(() -> init(ps, alg; dt = 0.1))
    @test occursin("the steady fields `ca`, `cb` of one group read one another, and the rule's bound on their joint gain does not hold", m) &&
          occursin("Step `ca`, `cb`, `cz` in one `BackwardEuler` group, or step `ca`, `cb` with `BackwardEuler`", m) &&
          endswith(m, "; for a `BackwardEuler` route, write the steady rows of `ca`, `cb` as rates `D(c) ~ rhs` (a steady row `0 ~ rhs` takes only `QuasiSteady`)") ||
          (println("feed strong ", m); false)
    # the route: the rows as rates, stepped by one `BackwardEuler` group
        pr = cown(
            PDESystem(
                [
                    D(cae) ~ 0.1 * laplacian(cae) - 0.1 * cae + 5.0 * cbe + 0.2 * cze, D(cbe) ~ 0.1 * laplacian(cbe) - cbe - 5.0 * cae,
            D(cze) ~ rates[3]], bc0, bdom(1.0), [t, x, y], [cae, cbe, cze], Any[]; name = :fbr))
        @test solve(pr, BackwardEuler(); dt = 0.1).retcode == ReturnCode.Success
    # steady groups that read one another only (two `QuasiSteady` with other keywords): one
    # `QuasiSteady` is the route, and it solves
    pq = cown(q1(0.1, 5.0; steady = true))
        m = cmsg(() -> init(pq, FieldGroups(cae => QuasiSteady(), cbe => QuasiSteady(; nlsolve = LatticeNewton(; max_iter = 3))); dt = 0.1))
    @test occursin("every group of the loop is steady, so no window damps the lag between them", m) &&
          occursin("Give `ca`, `cb` one `QuasiSteady` (the same keywords: one group, whose steady rows are solved together)", m) ||
          (println("qs only ", m); false)
        @test solve(pq, FieldGroups(cae => QuasiSteady(), cbe => QuasiSteady()); dt = 0.1).retcode == ReturnCode.Success
end
end

@testitem "F3-12d: a coupled steady system with no unique stable steady state is refused, with its eigenvalue" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
@testset "F3-12d: a coupled steady system with no unique stable steady state is refused, with its eigenvalue" begin
    # each row decays (−a, −b), the coupling `k` grows: mode 0 of `[−1 k; k −1]` has λ = k − 1
        ind(k) = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + k * cbe + x, 0 ~ 0.1 * laplacian(cbe) - cbe + k * cae], [
                    ca(0, x, y) ~ 0.0,
        cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :ind))
        m = cmsg(() -> init(ind(2.0), QuasiSteady(); dt = 0.1))
    @test startswith(m, "QuasiSteady: the fields `ca`, `cb` read one another, and their coupled steady system has a growing mode: an eigenvalue of its Jacobian with positive real part (1.0, in the slowest spatial mode), so its steady state is unstable") &&
          endswith(m, "step the fields with `BackwardEuler` (a steady row `0 ~ rhs` written as the rate `D(c) ~ rhs`: a steady row takes only `QuasiSteady`), or change the couplings or decays so that every mode decays") || (println("ind ", m); false)
        m = cmsg(() -> init(ind(1.0), QuasiSteady(); dt = 0.1))
    @test occursin("has a neutral mode: an eigenvalue of its Jacobian with zero real part", m) && occursin("not unique", m)
        @test solve(ind(0.5), QuasiSteady(); dt = 0.1).retcode == ReturnCode.Success
    # the route: the rows as rates, stepped by `BackwardEuler` (the growing mode grows)
        indr = cown(
            PDESystem(
                [D(cae) ~ 0.1 * laplacian(cae) - cae + 2.0 * cbe + x, D(cbe) ~ 0.1 * laplacian(cbe) - cbe + 2.0 * cae], [
                    ca(0, x, y) ~ 0.0,
        cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :indr))
        @test solve(indr, BackwardEuler(); dt = 0.1).retcode == ReturnCode.Success
    # a row's own growth that the coupling damps (0.5a − 2b, 2a − b: λ = −0.25 ± 1.85i) is well
    # posed: accepted, and the rate is 0 at the result
        rates = [0.1 * laplacian(cae) + 0.5 * cae - 2.0 * cbe + x, 0.1 * laplacian(cbe) + 2.0 * cae - cbe]
    p = cown(PDESystem([0 ~ rates[1], 0 ~ rates[2]], [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe],
        Any[]; name = :gd))
    A, b0 = cjac(PDESystem([D(cae) ~ rates[1], D(cbe) ~ rates[2]], [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y],
        [cae, cbe], Any[]; name = :gdr), (8, 8))
        r = solve(p, QuasiSteady(; linsolve = CTIGHT); dt = 0.1)
    @test r.retcode == ReturnCode.Success && maximum(abs, vcat(vec(r[cae, end]), vec(r[cbe, end])) .+ (A \ b0)) < 1e-9
    # a write that makes the coupling grow is refused at the write, the values unchanged
    @parameters ck = 0.5
        pk = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + ck * cbe + x, 0 ~ 0.1 * laplacian(cbe) - cbe + ck * cae], [
                    ca(0, x, y) ~ 0.0,
        cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], [ck]; name = :indk))
        ig = init(pk, QuasiSteady(); dt = 0.1)
    @test occursin("has a growing mode", cmsg(() -> (ig.ps[ck] = 3.0)))
    @test ig.ps[ck] == 0.5
end
end

@testitem "F3-12d: `init = :steady` with a coupled loop starts at the coupled steady state" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
@testset "F3-12d: `init = :steady` with a coupled loop starts at the coupled steady state" begin
    # a Backward Euler group with the strong q1 coupling: its steady start is one coupled steady
    # solve (the block iteration of the per-row path diverged, ratio 15.8)
    A, b0 = cjac(q1(0.1, 5.0), (8, 8))
    want = -(A \ b0)
        ig = init(cown(q1(0.1, 5.0)), BackwardEuler(; init = :steady); dt = 0.1)
    @test ig.retcode == ReturnCode.Default || ig.retcode == ReturnCode.Success
    @test maximum(abs, vcat(vec(ig[cae]), vec(ig[cbe])) .- want) / maximum(abs, want) < 1e-5
    # the steady state stays (the rate is 0 there)
    step!(ig)
    @test maximum(abs, vcat(vec(ig[cae]), vec(ig[cbe])) .- want) / maximum(abs, want) < 1e-5
end
end

@testitem "the time steppers refuse `linsolve = LatticeGMRES(…)`, with the default route" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
    @testset "the time steppers refuse `linsolve = LatticeGMRES(…)`, with the default route" begin
        # it was slower than the default linear solver in every case measured (~/lpwork/f312d-g1.txt)
    for A in (BackwardEuler, CrankNicolson, BDF2)
            m = cmsg(() -> A(; linsolve = LatticeGMRES()))
            @test startswith(m, "$(nameof(A)): `linsolve = LatticeGMRES(") &&
              occursin("is the solver of a coupled steady group (`QuasiSteady`, whose fields read one another)", m) &&
                endswith(m, "leave `linsolve` out, or give `linsolve = LatticePCG(; maxiters = n)`") || (println("r1 S2 ", m); false)
            @test A(; linsolve = LatticePCG(; maxiters = 12)) isa A                  # (the route)
    end
        @test QuasiSteady(; linsolve = LatticeGMRES()).linsolve isa LatticeGMRES
end
end

@testitem "a site-varying coupled system with a growing mode is refused (estimated through the operator)" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
    @testset "a site-varying coupled system with a growing mode is refused (estimated through the operator)" begin
    # the reviewer's case (~/lpwork/f3rev17/p1.jl): `(3 + 0.1x) b`, dense max Re λ = +2.03; the
    # constant-coefficient check cannot see it (a coefficient that varies by site). Base (51d1f386):
    # `Success` at the unstable steady state, no warning
    @parameters kv = 3.0
        sv() = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + (kv + 0.1 * x) * cbe + x, 0 ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], [kv]; name = :sv))
        m = cmsg(() -> init(sv(), QuasiSteady(); dt = 0.1))
    @test startswith(m, "QuasiSteady: the fields `ca`, `cb` read one another, and their coupled steady system has a growing mode") &&
          occursin("estimated through the coupled operator: a coefficient varies by site", m) || (println("M2 ", m); false)
    λ = parse(Float64, match(r"real part \(([-0-9.e]+)", m).captures[1])
        A, _ = cjac(
            PDESystem(
                [D(cae) ~ 0.1 * laplacian(cae) - cae + (3.0 + 0.1 * x) * cbe + x, D(cbe) ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :svr), (8, 8))
    λd = maximum(real, LinearAlgebra.eigvals(A))
    @test λd > 1 && abs(λ - λd) <= 0.05 * λd || (println("M2 λ ", λ, " dense ", λd); false)
    # stable and site-varying (a skew coupling): accepted, and equal to the dense steady solve
        ss = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + (2.0 + 0.1 * x) * cbe + x, 0 ~ 0.1 * laplacian(cbe) - 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :ss))
        r = solve(ss, QuasiSteady(; linsolve = CTIGHT); dt = 0.1)
        As, bs = cjac(
            PDESystem(
                [D(cae) ~ 0.1 * laplacian(cae) - cae + (2.0 + 0.1 * x) * cbe + x, D(cbe) ~ 0.1 * laplacian(cbe) - 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :ssr), (8, 8))
    @test r.retcode == ReturnCode.Success && maximum(abs, [vec(r[cae, end]); vec(r[cbe, end])] .+ As \ bs) < 1e-8
    # a parameter write into the growing range is refused, and the value stays
    @parameters kw = 0.0                                   # (local λ ≤ −1 + √(0.3x) < 0: stable)
        sw = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + (kw + 0.1 * x) * cbe + x, 0 ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [cae, cbe], [kw]; name = :sw))
        ig = init(sw, QuasiSteady(); dt = 0.1)
    @test_throws "estimated through the coupled operator" (ig.ps[kw] = 3.0)
    @test ig.ps[kw] == 0.0
    # the refused write left the old launches (r2 S1): its run equals a fresh one's, bit for bit
    for _ in 1:2
        step!(ig)
    end
        fr = init(sw, QuasiSteady(); dt = 0.1)
    for _ in 1:2
        step!(fr)
    end
    @test ig.retcode == ReturnCode.Default || ig.retcode == ReturnCode.Success
    @test ig[cae] == fr[cae] && ig[cbe] == fr[cbe]
    # nonlinear (r2 M1, the reviewer's probe2): `+ 0.01a²` turns the constant-coefficient check
    # off; the Jacobian at the steady state the solve finds has max Re λ ≈ +2.0, found at the
    # first window after that solve. Base (3f9d5909): `Success`, no warning
        nl(c) = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + c * cbe + x + 0.01 * cae^2, 0 ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.3), [t, x, y], [cae, cbe], Any[]; name = :nlg))
        m = cmsg(() -> solve(nl(3.0), QuasiSteady(); dt = 0.1))
    @test occursin("has a growing mode: an eigenvalue of its Jacobian with positive real part", m) &&
          occursin(", at the steady state its solve found)", m) || (println("r2 M1 ", m); false)
    # right after the first solve (r3): a one-window run and a steady start are refused too.
    # Base (5005083e, the check deferred to the next window): one window `Success`, the steady
    # start not checked
        nl1 = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + 3.0 * cbe + x + 0.01 * cae^2, 0 ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.1), [t, x, y], [cae, cbe], Any[]; name = :nl1))
        @test occursin(", at the steady state its solve found)", cmsg(() -> solve(nl1, QuasiSteady(); dt = 0.1)))
        nlr = cown(
            PDESystem(
                [D(cae) ~ 0.1 * laplacian(cae) - cae + 3.0 * cbe + x + 0.01 * cae^2, D(cbe) ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.3), [t, x, y], [cae, cbe], Any[]; name = :nlr))
        m = cmsg(() -> init(nlr, BackwardEuler(; init = :steady); dt = 0.1))
    @test occursin("has a growing mode", m) && occursin(", at the steady state its solve found)", m) || (println("r3 init ", m); false)
    # a write from stable to unstable (r3 S1): every later step is refused, not only the first.
    # Control (the old order, `pending` cleared before the check): the second `step!` succeeds
    @parameters kn = 0.0
        nlw = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + kn * cbe + x + 0.01 * cae^2, 0 ~ 0.1 * laplacian(cbe) + 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(1.0), [t, x, y], [cae, cbe], [kn]; name = :nlw))
        iw = init(nlw, QuasiSteady(); dt = 0.1)
    step!(iw)
    iw.ps[kn] = 3.0
    @test occursin(", at the steady state its solve found)", cmsg(() -> step!(iw)))
    @test occursin(", at the steady state its solve found)", cmsg(() -> step!(iw)))
    # stable with the same term (a skew coupling): accepted
        nls = cown(
            PDESystem(
                [0 ~ 0.1 * laplacian(cae) - cae + 2.0 * cbe + x + 0.01 * cae^2, 0 ~ 0.1 * laplacian(cbe) - 3.0 * cae - cbe + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.3), [t, x, y], [cae, cbe], Any[]; name = :nls))
        @test solve(nls, QuasiSteady(); dt = 0.1).retcode == ReturnCode.Success
end
end

@testitem "no coupled code compiles for one field; every Krylov.jl hook is ours" setup = [LP_coupled] tags = [:latticepde, :coupled] begin
    @testset "no coupled code compiles for one field; every Krylov.jl hook is ours" begin
    # M1: a single-field QuasiSteady `init` in a fresh process compiles no `coupled_modes` and no
    # `_bind_coupled` (both behind barriers). Base (51d1f386): coupled_modes compiled
        # runic: off
    code = raw"""
    using LatticePDE
    using ModelingToolkitBase: @parameters, @variables, PDESystem, t_nounits as t, D_nounits as D
    using DomainSets: Interval
    LF = LatticePDE.Problems
    @parameters x y
    @variables c(..)
    ce = c(t, x, y)
    sys = PDESystem([D(ce) ~ 0.3 * laplacian(ce) - 2.0 * ce + x], [c(0, x, y) ~ 0.0], [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0),
        y ∈ Interval(0.0, 1.0)], [t, x, y], [ce], Any[]; name = :one)
    init(discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64)), QuasiSteady(); dt = 0.1)
    n(f) = sum(m -> count(mi -> mi isa Core.MethodInstance && isdefined(mi, :cache), Base.specializations(m)), methods(f); init = 0)
    println("M1 ", n(LF.coupled_modes), " ", n(LF._bind_coupled))
    """
        # runic: on
    out = readchomp(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`)
    @test occursin("M1 0 0", out) || (println("M1 ", out); false)
    # S1: each vector function Krylov.jl calls on a `CoupledVector` is our method, and indexing it
    # is an error
    LFP2 = LatticePDE.Problems
    K = LFP2.Krylov
    v = LFP2._cvec(zeros(4), zeros(2), KernelAbstractions.CPU())
    for (f, args) in ((K.kdot, (4, v, v)), (K.knorm, (4, v)), (K.kaxpy!, (4, 1.0, v, v)), (K.kaxpby!, (4, 1.0, v, 1.0, v)),
                      (K.kcopy!, (4, v, v)), (K.kdivcopy!, (4, v, v, 1.0)), (K.kfill!, (v, 1.0)))
        @test which(f, typeof.(args)).module === LFP2
    end
    @test_throws ArgumentError v[1]
    @test_throws ArgumentError (v[1] = 1.0)
end
end
