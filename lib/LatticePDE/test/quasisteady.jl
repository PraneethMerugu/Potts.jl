# F3-12a (F3 design §3.5): `QuasiSteady` in front end B. Each window solves `0 = r(u)` at the
# window's start time, `−J̃ δ = r(u_k)` from the field's current values (no time-step term),
# one linear solve for a linear exact group, a checked budget of 8 Newton iterations otherwise.
# It refuses a growth the operator sees and a field with no decay and no fixed value (at build
# and at every parameter write); a region with neither that the inputs cut off (an island) is
# found on the device: a budget hit with no real reduction is `ConvergenceFailure`. The
# windows are checked against the hand steady matrix of `hand_rate` (implicit.jl). Base (the
# guard commit b32d9112, ~/lpwork/f3b5-nc-12a-base.log): `QuasiSteady` is not defined (every
# testset errors). Negative controls (mutations, ~/lpwork/f3b5-nc-12a-*.log): the steady
# failure test left out (noreduce), the growth refusal left out (nogrowth).

# the steady state of the hand rate `(L, b)`: `L u = −b`, the masked sites holding `mval`
function qs_hand(; mask = nothing, mval = nothing, kw...)
    L, b = hand_rate(; kw...)
    A, rhs = copy(L), -b
    if mask !== nothing
        for r in eachindex(rhs)
            mask[r] || continue
            A[r, :] .= 0
            A[r, r] = 1
            rhs[r] = mval[r]
        end
    end
    return A \ rhs
end
qs_window(p, alg) = (ig = init(p, alg); step!(ig); (ig, vec(ig[bce])))
qmsg(f) = try
    f(); ""
catch err
    err isa ArgumentError ? err.msg : sprint(showerror, err)
end
@parameters qg = 1.0

@testset "F3-12a: one QuasiSteady window is the steady state (the hand matrix)" begin
    alg = QuasiSteady(; dt = 0.1, inner = BTIGHT)
    # a numeric operator: diffusion, decay, a source, a Dirichlet face, a mask with its value
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0,
        bce ~ masked(bqe == 2, 1.5)], [bD, bk]))
    ig, u = qs_window(p, alg)
    mk = vec(BKIND .== 2)
    want = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)),
        mask = mk, mval = fill(1.5, 48))
    @test maximum(abs, u .- want) < 1e-9 && all(u[mk] .== 1.5)
    rt = only(ig.runtimes)
    @test rt.cache.newton == 1 && rt.cache.exact && rt.totals.solves == 1 && ig.retcode == ReturnCode.Success
    @test ig.substeps == 1                                     # (one solve per window)
    # the window's start time: a source `x + t` is read at t = 0, then at t = 0.1; the start
    # state does not matter (a steady solve)
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x + t], [bc(0, x, y) ~ 5.0, bc(t, 0, y) ~ 1.0], [bD, bk]))
    ig = init(p, alg)
    step!(ig)
    w1 = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)))
    @test maximum(abs, vec(ig[bce]) .- w1) < 1e-9
    step!(ig)
    w2 = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x + 0.1, faces = Dict((1, -1) => (:dir, 1.0)))
    @test maximum(abs, vec(ig[bce]) .- w2) < 1e-9
    # the default inner solver from a cold start, and warm: the next window starts at the last
    # solution, so its solve is done at its setup
    ig = init(p, QuasiSteady(; dt = 0.1))
    step!(ig)
    @test maximum(abs, vec(ig[bce]) .- w1) < 1e-4
    @test bwarm(ig) == 0
    @test LSB.iterations(ig.runtimes[1].cache.rows[1].solver) <= 8
end

@testset "F3-12a: the solver capabilities in a QuasiSteady group (F3-05)" begin
    alg = QuasiSteady(; dt = 0.1, inner = BTIGHT)
    xs = bxs()
    # a Robin face, positive part
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ bg],
        [bD, bk, bg]))
    ig, u = qs_window(p, alg)
    want = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, -1.0, 0.5)))
    @test maximum(abs, u .- want) < 1e-10 && only(ig.runtimes).cache.newton == 1
    # opposite signs: a steady solve takes the Robin face's negative part into its operator (it is
    # diagonal, so the operator stays symmetric; review r3 S1): one exact solve, newton 1, the hand
    # matrix to 1e-9, for the well-posed faces (max Re λ of the steady Jacobian −0.68 at decay 2,
    # −0.18 at 1.5; reviewer probe s3). Base (e7068add, ~/lpwork/f3b5-nc-r3-s1.log): the defect
    # correction, newton 40 and ~20 solves a window
    rob(kd, β) = remake(bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x],
        [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) + β * Differential(y)(bc(t, x, 0)) ~ bg], [bD, bk, bg])); p = [bk => kd])
    for kd in (2.0, 1.5)
        p = rob(kd, 1.0)
        want = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> kd, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, 1.0, 0.5)))
        ig = init(p, alg)
        @test_logs min_level = WARN step!(ig)
        rt = only(ig.runtimes)
        @test rt.cache.newton == 1 && rt.cache.exact && rt.totals.solves == 1 && ig.retcode == ReturnCode.Success
        @test maximum(abs, vec(ig[bce]) .- want) < 1e-9
    end
    # the faces that make the steady problem indefinite (max Re λ +3.4, +0.82, +1.1, +5.4) are
    # refused at build, as a growth is, with the eigenvalue and the route; and at a write
    for (kd, β) in ((2.0, 0.5), (0.5, 1.0), (0.2, 1.0), (0.05, 0.5))
        m = qmsg(() -> init(rob(kd, β), alg))
        @test startswith(m, "QuasiSteady: field `bc`: its steady operator is indefinite (smallest eigenvalue -") &&
              occursin("step the field with `BackwardEuler`", m) || (println("r3 S1 ", (kd, β), " ", m); false)
    end
    @test occursin("smallest eigenvalue -3.41)", qmsg(() -> init(rob(2.0, 0.5), alg)))
    ig = init(rob(2.0, 1.0), alg)
    @test occursin("its steady operator is indefinite", qmsg(() -> (ig.ps[bk] = 0.5)))
    @test init(rob(2.0, 0.5), BackwardEuler(; dt = 0.1)) isa Any                      # (the route builds)
    # a field face coefficient with a face-Dirichlet value that varies along the face
    p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce], [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0 + y], [bk]))
    ig, u = qs_window(p, alg)
    @test only(ig.runtimes).cache.rows[1].op.field
    want = qs_hand(; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
    @test maximum(abs, u .- want) < 1e-10
    # a mask whose value is a field
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce], [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1 + x)], [bD, bk]))
    ig, u = qs_window(p, alg)
    mk = vec(BKIND .== 2)
    want = qs_hand(; K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(1 .+ xs))
    @test maximum(abs, u .- want) < 1e-10 && all(u[mk] .== vec(1 .+ xs)[mk])
    # an input bound by aliasing: a write of the input between windows changes the next solve
    p = bown(bsys([D(bce) ~ at(bW, bqe) * Δ(bce) - bk * bce + 1], [bc(0, x, y) ~ 0.0], [bW, bk]))
    ig = init(p, alg)
    step!(ig); step!(ig)
    @test bwarm(ig) == 0
    K2 = Int32[(i * j) % 2 for i in 1:8, j in 1:6]
    ig[bqe] = K2
    step!(ig)
    want = qs_hand(; K = (x, y) -> 1.0, m = (i, j) -> (0.0, 0.5, 2.0)[K2[i, j] + 1], k = (x, y) -> 2.0, f = (x, y) -> 1.0)
    @test maximum(abs, vec(ig[bce]) .- want) < 1e-10
end

@testset "F3-12a: nonlinear rows: Michaelis–Menten within the default 8 iterations" begin
    sys = nlsys([D(bce) ~ 0.05 * Δ(bce) - 40 * bce / (0.025 + bce) + 20], [bc(0, x, y) ~ 0.5, bc(t, 0, y) ~ 1.0], [bce]; T = 0.3)
    ig = init(nlown(sys), QuasiSteady(; dt = 0.1, inner = BTIGHT))
    step!(ig)
    rt = only(ig.runtimes)
    @test rt.cache.newton == 8 && rt.cache.check && ig.retcode == ReturnCode.Success
    @test rt.totals.newton_budget == 0 && rt.totals.solves < 8      # (the host stop: converged before the budget)
    po = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64, problem = :ode))
    du = similar(po.u0)
    po.f(du, vec(ig[bce]), po.p, 0.0)
    # the steady residual against the uptake's scale (40): ε_N = 1e-3 of the field
    @test maximum(abs, du) < 1e-3 * 40 || (println("MM steady residual ", maximum(abs, du)); false)
    # the second window starts converged: one iteration
    s0 = rt.totals.solves
    step!(ig)
    @test rt.totals.solves - s0 <= 2
end

@testset "F3-12a: the refusals: growth, no unique steady state; keywords, show" begin
    # a growth the operator sees, at build and at a parameter write
    pg = bown(bsys([D(bce) ~ bD * Δ(bce) + qg * bce], [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0], [bD, qg]))
    m = qmsg(() -> init(pg, QuasiSteady(; dt = 0.1)))
    @test startswith(m, "QuasiSteady: field `bc`: its local derivative `∂f/∂c` = 1.0 is positive") && occursin("`BackwardEuler`", m)
    @test qmsg(() -> init(pg, BackwardEuler(; dt = 0.1))) == ""                  # (the route)
    pd = bown(bsys([D(bce) ~ bD * Δ(bce) - qg * bce + x], [bc(0, x, y) ~ x], [bD, qg]))
    ig = init(pd, QuasiSteady(; dt = 0.1))
    step!(ig)
    @test occursin("its local derivative `∂f/∂c` = 2.0 is positive", qmsg(() -> (ig.ps[qg] = -2.0)))
    # no decay and no fixed value: pure Neumann (refused), at build and when a write takes the
    # decay away; a Dirichlet face anchors it (accepted with no decay)
    pn = bown(bsys([D(bce) ~ bD * Δ(bce) + x], [bc(0, x, y) ~ x], [bD]))
    m = qmsg(() -> init(pn, QuasiSteady(; dt = 0.1)))
    @test startswith(m, "QuasiSteady: field `bc` has no unique steady state: it has no decay") &&
          occursin("add a decay or a fixed value", m)
    ig = init(pd, QuasiSteady(; dt = 0.1))
    @test occursin("has no unique steady state", qmsg(() -> (ig.ps[qg] = 0.0)))
    pa = bown(bsys([D(bce) ~ bD * Δ(bce) - qg * bce + x], [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0], [bD, qg]))
    ig = init(pa, QuasiSteady(; dt = 0.1, inner = BTIGHT))
    ig.ps[qg] = 0.0
    step!(ig)
    @test maximum(abs, vec(ig[bce]) .- qs_hand(; K = (x, y) -> 0.3, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)))) < 1e-9
    # a mask anchors it too
    pm = bown(bsys([D(bce) ~ bD * Δ(bce) + x], [bc(0, x, y) ~ x, bce ~ masked(bqe == 2, 1.0)], [bD]))
    @test qmsg(() -> init(pm, QuasiSteady(; dt = 0.1))) == ""
    # the keywords
    @test startswith(qmsg(() -> QuasiSteady(; substeps = 2)), "QuasiSteady: no keyword `substeps`: a steady field is solved once per window")
    @test startswith(qmsg(() -> QuasiSteady(; lower = 0.0)), "QuasiSteady: no keyword `lower`: a steady solve has no substep to clip")
    @test qmsg(() -> QuasiSteady(; theta = 1)) == "QuasiSteady: no keyword `theta`; its keywords are `dt`, `newton`, `inner` and `solver_T`"
    @test startswith(qmsg(() -> QuasiSteady(; newton = 0)), "QuasiSteady: newton = 0 is the Newton iterations per substep")
    a = QuasiSteady(; dt = 0.5, newton = 3)
    @test repr(a) == "QuasiSteady(; dt = 0.5, newton = 3)" && eval(Meta.parse(repr(a))) == a && repr(QuasiSteady()) == "QuasiSteady()"
    @test LFB.canonical(QuasiSteady()) == "QuasiSteady(inner=:auto,lower=nothing,newton=nothing,solver_T=:auto,substeps=nothing)"
end

@testset "F3-12a: budget hits: a real reduction stays Success, none (an island) is ConvergenceFailure" begin
    # a budget of 2 PCG iterations on 32²: the residual falls by more than half but not to the
    # tolerance; counted and warned with the route, `Success`
    p = discretize(bsys([D(bce) ~ bD * Δ(bce) - 0.01 * bce + x], [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0], [bD]),
        LatticeDiscretization(Grid((32, 32)); T = Float64, problem = :owned); inputs = [bqe => zeros(Int32, 32, 32)])
    ig = init(p, QuasiSteady(; dt = 0.1, inner = DevicePCG(; budget = 2)))
    @test_logs (:warn, r"field `bc`: the linear solve reached its budget 1 time so far .*a larger linear budget") step!(ig)
    sc = LSB.scalars(only(ig.runtimes).cache.rows[1].solver)
    @test sc.status === :budget && sc.rnorm < sc.bnorm / 2 && ig.retcode == ReturnCode.Success   # (3.9 of 614)
    s = solve(p, QuasiSteady(; dt = 0.1, inner = DevicePCG(; budget = 2)))
    @test s.retcode == ReturnCode.Success && s.stats.budget > 0
    # an island: the domain (a Bool input) is two strips; the low one touches the Dirichlet face
    # at y = 0, the high one touches no condition and the field has no decay, so the high
    # strip's steady state is not unique (a source of 1 everywhere: none), and the solve cannot
    # reduce the residual there. The build sees the Dirichlet face and accepts the group.
    @variables bdm(..)::Bool [input = true]
    bdme = bdm(t, x, y)
    dm = [j <= 2 || j >= 5 for i in 1:8, j in 1:6]
    si = PDESystem([D(bce) ~ bD * Δ(bce) + 1.0], [bc(0, x, y) ~ 0.0, bc(t, x, 0) ~ 0.0], bdom(1.0), [t, x, y], [bce, bdme], [bD];
        name = :island)
    pi = discretize(si, LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned, domain = bdm); inputs = [bdme => dm])
    ig = init(pi, QuasiSteady(; dt = 0.1, inner = DevicePCG(; budget = 16)))
    @test_logs (:warn, r"field `bc`: the solve failed in window 1 \(t = 0\.0\) \(the steady solve made no real reduction: a region has no decay and no fixed value.*give that region a decay or a fixed value, or step the field with `BackwardEuler`") step!(ig)
    sc = LSB.scalars(only(ig.runtimes).cache.rows[1].solver)
    # the status the island produces (recorded: `:floor` after 7 iterations, the stall test, with
    # the residual grown to 3.7e9 against ‖b‖ = 1: no reduction)
    @test sc.status === :floor && sc.rnorm > sc.bnorm / 2 || (println("island status ", sc); false)
    s = solve(pi, QuasiSteady(; dt = 0.1, inner = DevicePCG(; budget = 16)))
    @test s.retcode == ReturnCode.ConvergenceFailure && length(s.t) == 2
    # the same strips with a decay in each: unique, solved
    sd = PDESystem([D(bce) ~ bD * Δ(bce) - 0.5 * bce + 1.0], [bc(0, x, y) ~ 0.0, bc(t, x, 0) ~ 0.0], bdom(1.0), [t, x, y],
        [bce, bdme], [bD]; name = :island2)
    pd = discretize(sd, LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned, domain = bdm); inputs = [bdme => dm])
    @test solve(pd, QuasiSteady(; dt = 0.1, inner = BTIGHT)).retcode == ReturnCode.Success
end

@testset "F3-12a: components equal scalars; the hexagonal refusal names QuasiSteady" begin
    @variables bu(..)[1:2]
    bue = bu(t, x, y)
    comp = nlsys([D(bue[1]) ~ 0.05 * Δ(bue[1]) - 2 * bue[1] + 1, D(bue[2]) ~ 0.05 * Δ(bue[2]) - bue[2] + bue[1]],
        [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3)
    scal = nlsys([D(bce) ~ 0.05 * Δ(bce) - 2 * bce + 1, D(boe) ~ 0.05 * Δ(boe) - boe + bce],
        [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3)
    a = solve(nlown(comp), QuasiSteady(; dt = 0.1))
    b = solve(nlown(scal), QuasiSteady(; dt = 0.1))
    @test a.stats == b.stats && a.stats.solves > 0
    @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
    hs = PDESystem([D(bce) ~ Δ(bce) - bce], [bc(0, x, y) ~ 0.0], bdom(1.0), [t, x, y], [bce], Any[]; name = :hex)
    ph = discretize(hs, LatticeDiscretization(Grid((6, 6); geometry = HEX); T = Float64, problem = :owned))
    @test startswith(qmsg(() -> init(ph, QuasiSteady(; dt = 0.1))), "QuasiSteady: field `bc`: a hexagonal lattice has no implicit solve yet")
end

# Review r2 M1: until F3-12c bounds a steady group's gain in the coupling rule, a QuasiSteady
# group in a loop of groups is refused, with the two routes (one Backward Euler group; Backward
# Euler for the steady field); a steady group another group reads one way stays accepted. The
# cases are the reviewer's q1 (~/lpwork/f3rev7/q1.jl): `0 = 0.1Δa − δa + s k b` steady,
# `b' = 0.1Δb − b − k a`, whose lag of one window grew to 1e37 (δ = 0.1, k = 5). Base (773f0957,
# ~/lpwork/f3b5-nc-r2-m1.log): every loop accepted (the refusal tests fail).
@testset "F3-12a (r2 M1): a QuasiSteady group in a loop is refused, with its routes" begin
    @variables qa(..) qb(..)
    qae, qbe = qa(t, x, y), qb(t, x, y)
    loop(δ, k, s) = discretize(PDESystem([D(qae) ~ 0.1 * Δ(qae) - δ * qae + s * k * qbe, D(qbe) ~ 0.1 * Δ(qbe) - qbe - k * qae],
            [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [qae, qbe], Any[]; name = :loop),
        LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    for (δ, k, s) in ((0.1, 5.0, 1.0), (0.1, 5.0, -1.0), (1.0, 5.0, 1.0), (0.1, 9.0, 1.0))
        p = loop(δ, k, s)
        m = qmsg(() -> init(p, FieldGroups(qae => QuasiSteady(; dt = 0.1), qbe => BackwardEuler(; dt = 0.1))))
        @test startswith(m, "FieldGroups: the QuasiSteady group of `qa` is in a loop of groups that read one another (`qa`, `qb`)") &&
              occursin("Step `qa`, `qb` in one `BackwardEuler` group, or step `qa` with `BackwardEuler`", m)
        # the routes: one group, or Backward Euler for the steady field
        for alg in (BackwardEuler(; dt = 0.1), FieldGroups(qae => BackwardEuler(; dt = 0.1), qbe => BackwardEuler(; dt = 0.1)))
            r = solve(p, alg)
            # (`s = −1` grows: `a`, `b` have an eigenvalue `k − (1 + δ)/2` > 0; the others decay)
            @test r.retcode == ReturnCode.Success && all(isfinite, r[qbe, length(r.t)]) &&
                  (s < 0 || maximum(abs, r[qbe, length(r.t)]) < 1) || (println("r2 M1 route ", (δ, k, s), " ", r.retcode, " ", maximum(abs, r[qbe, length(r.t)])); false)
        end
    end
    # the loop in one steady group: a well-posed system (max Re λ −0.55) whose block iteration
    # does not contract (≈ k/√(δμ) = 15.8; reviewer probe s3): the failure names the coupling
    # and the route (review r3 S2; base e7068add: "step the field with `BackwardEuler` (a
    # transient solve converges …)", ~/lpwork/f3b6-nc-r3.log)
    p = loop(0.1, 5.0, 1.0)
    r = @test_logs (:warn, r"fields `qa`, `qb`: the solve failed in window 1 .*the coupling between `qa` and `qb` in one steady group does not contract .*step them with `BackwardEuler`") match_mode = :any solve(p, QuasiSteady(; dt = 0.1))
    @test r.retcode == ReturnCode.ConvergenceFailure
    # a steady linear divergence has its own cause (32) and words, apart from no reduction (16)
    @test LFP.status_route(QuasiSteady(), :failure, 0x21) == "step the field with `BackwardEuler`, or give each region a decay or a fixed value"
    @test occursin("may be indefinite (a growth, or a Robin face whose α and β have opposite signs) or have an island",
        last(LFP.STATUS_CAUSES[6]))
    # one way: `qb` reads the steady `qa`, `qa` reads no other group: accepted, the steady state
    pw = discretize(PDESystem([D(qae) ~ 0.1 * Δ(qae) - qae + x, D(qbe) ~ 0.1 * Δ(qbe) - qbe - 5 * qae],
            [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [qae, qbe], Any[]; name = :oneway),
        LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    r = solve(pw, FieldGroups(qae => QuasiSteady(; dt = 0.1, inner = BTIGHT), qbe => BackwardEuler(; dt = 0.1)))
    @test r.retcode == ReturnCode.Success
    p1 = discretize(PDESystem([D(qae) ~ 0.1 * Δ(qae) - qae + x], [qa(0, x, y) ~ 0.0], bdom(1.0), [t, x, y], [qae], Any[];
        name = :alone), LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    rs = solve(p1, QuasiSteady(; dt = 0.1, inner = BTIGHT))                     # (the steady field alone)
    @test maximum(abs, r[qae, length(r.t)] .- rs[qae, length(rs.t)]) < 1e-12
end
