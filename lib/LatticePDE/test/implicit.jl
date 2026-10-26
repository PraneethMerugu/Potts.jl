# F3-07 (F3 design §3.3, §3.4): `BackwardEuler` in front end B for linear groups. The rate
# program is the residual (`fuse_residual`), the operator `J̃` comes from the linearity table
# (`OperatorSpec`, built at the first implicit use only), and each substep solves
# `(I/h − J̃) δ = G(uⁿ)`, `u = uⁿ + δ` at `tⁿ⁺¹`. The tests compare one window with the hand BE
# matrix of the same stencil (faces, ghosts, masks), the order with the exact semi-discrete
# solution, a manufactured solution, a stiff case and OrdinaryDiffEq's `ImplicitEuler`.
# Base (437a84ef, ~/lpwork/f3b3-nc-base.log): `BackwardEuler` is not defined (every testset
# errors); the negative controls below are mutations of this tree (~/lpwork/f3b3-nc-*.log).
using LinearAlgebra: I, norm, lu
using OrdinaryDiffEqSDIRK: OrdinaryDiffEqSDIRK, ImplicitEuler
using OrdinaryDiffEqTsit5: Tsit5
using LatticeFields: Problems as LFB, Solvers as LSB
using LatticeFields.IR: fieldid, HEX

@parameters bD = 0.3 bk = 2.0 bW[1:2] = [0.5, 2.0] bg = 0.5
@variables bc(..) bq(..)::Int32 [input = true] bo(..)
bce, bqe, boe = bc(t, x, y), bq(t, x, y), bo(t, x, y)
const BDIMS = (8, 6)
const BKIND = Int32[(i + j) % 3 for i in 1:8, j in 1:6]
bdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
bsys(eqs, bcs, ps; T = 1.0, dvs = [bce, bqe]) = PDESystem(eqs, bcs, bdom(T), [t, x, y], dvs, ps; name = :be)
bown(sys; dims = BDIMS, T = Float64, kw...) =
    discretize(sys, LatticeDiscretization(Grid(dims); T, problem = :owned, kw...); inputs = [bqe => BKIND])
const BTIGHT = DevicePCG(; rtol = 1e-12, budget = 64)
bwarm(ig) = (step!(ig); @allocated step!(ig))              # (a function barrier)
blast(s) = s[bce, length(s.t)]                             # the last save

# The hand BE matrix of a cell-centered grid on [0, 1]² (`dims` sites, cell centers
# `(i − ½) h`): the rate `r(u)_i = m_i Σ_a Σ_± w (u_nb − u_i)/h_a² − k_i u_i + f_i`, with the
# harmonic face `w = 2K_i K_nb/(K_i + K_nb)` (`K` at the neighbor's center, a ghost center at a
# face of the box). A box face takes `faces[(a, side)]`: `(:dir, g)` (ghost `2g − u_i`) or
# `(:robin, α, β, g)` for `α u + β ∂u/∂x_a = g` as written (ghost from `α (u_g + u_i)/2 +
# β side (u_g − u_i)/h = g`), `g` a number or a function of the face point; no entry is zero
# flux. `hand_rate` returns the rate `(L, b)`; `be_hand` `u` of `(I − h L) u = u0 + h b`, the
# masked sites holding `mval`.
function be_hand(u0, h; mask = nothing, mval = nothing, kw...)
    L, b = hand_rate(; kw...)
    A = I - h * L
    rhs = u0 .+ h .* b
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
function hand_rate(; dims = BDIMS, K = (x, y) -> 1.0, m = (i, j) -> 1.0, k = (x, y) -> 0.0, f = (x, y) -> 0.0, faces = Dict())
    nx, ny = dims
    hs = (1 / nx, 1 / ny)
    lin(i, j) = i + (j - 1) * nx
    ctr(i, j) = ((i - 0.5) * hs[1], (j - 0.5) * hs[2])
    n = nx * ny
    L = zeros(n, n)
    b = zeros(n)
    for j in 1:ny, i in 1:nx
        r = lin(i, j)
        xi, yi = ctr(i, j)
        for a in 1:2, s in (-1, 1)
            ii, jj = a == 1 ? (i + s, j) : (i, j + s)
            Kn = K(ctr(ii, jj)...)
            Ki = K(xi, yi)
            w = Ki + Kn == 0 ? 0.0 : 2Ki * Kn / (Ki + Kn)
            c = m(i, j) * w / hs[a]^2
            if 1 <= ii <= nx && 1 <= jj <= ny
                L[r, lin(ii, jj)] += c
                L[r, r] -= c
            elseif haskey(faces, (a, s))
                fc = faces[(a, s)]
                # the face point, and the ghost u_g = p u_i + q
                fp = a == 1 ? (s < 0 ? 0.0 : 1.0, yi) : (xi, s < 0 ? 0.0 : 1.0)
                g = fc[end] isa Function ? fc[end](fp...) : fc[end]
                p, q = fc[1] === :dir ? (-1.0, 2g) :
                       (bl = fc[3] * s / hs[a]; den = fc[2] / 2 + bl; ((bl - fc[2] / 2) / den, g / den))
                L[r, r] += c * (p - 1)
                b[r] += c * q
            end
        end
        L[r, r] -= k(xi, yi)
        b[r] += f(xi, yi)
    end
    return L, b
end
bxs() = [(i - 0.5) / BDIMS[1] for i in 1:BDIMS[1], j in 1:BDIMS[2]]
bys() = [(j - 0.5) / BDIMS[2] for i in 1:BDIMS[1], j in 1:BDIMS[2]]
# one window of `alg` from the problem's start state
function be_window(prob, alg)
    ig = init(prob, alg)
    u0 = copy(vec(ig[bce]))
    step!(ig)
    return ig, u0, vec(ig[bce])
end

@testset "F3-07: one BackwardEuler window equals the hand BE matrix" begin
    h = 0.05
    alg = BackwardEuler(; dt = h, inner = BTIGHT)
    # a numeric operator: diffusion, decay, a source, a Dirichlet face, a mask with its value
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0,
        bce ~ masked(bqe == 2, 1.5)], [bD, bk]))
    ig, u0, u = be_window(p, alg)
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)),
        mask = vec(BKIND .== 2), mval = fill(1.5, 48))
    @test maximum(abs, u .- want) < 1e-9
    rt = only(ig.runtimes)
    @test rt.cache.newton == 1 && rt.cache.exact && ig.retcode == ReturnCode.Success
    @test all(u[vec(BKIND .== 2)] .== 1.5)                     # the mask value written back (SD-11)
    @test rt.totals.solves == 1                                # one solve per substep (exact operator)
end

@testset "F3-07: the solver capabilities in a BackwardEuler group (F3-05 in B)" begin
    h = 0.05
    xs, ys = bxs(), bys()
    # a Robin face, positive part (α and β of the same sign with the outward normal)
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ bg],
        [bD, bk, bg]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, -1.0, 0.5)))
    @test maximum(abs, u .- want) < 1e-10 && only(ig.runtimes).cache.newton == 1
    # opposite signs: the negative part stays in the residual (a defect correction), so the
    # automatic Newton count is more than one (from its bound `w |d⁻|`, S1: 5 here); `newton = k`
    # converges it to the hand matrix
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) + Differential(y)(bc(t, x, 0)) ~ bg],
        [bD, bk, bg]))
    want = be_hand(zeros(48), h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, 1.0, 0.5)))
    ig, _, u4 = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    @test only(ig.runtimes).cache.newton == 5 && only(ig.runtimes).cache.seen && maximum(abs, u4 .- want) < 1e-3
    ig, _, u = be_window(p, BackwardEuler(; dt = h, newton = 30, inner = BTIGHT))
    @test maximum(abs, u .- want) < 1e-10 && only(ig.runtimes).totals.solves == 30
    # a field face coefficient (`DivKGrad(k(x, y), c)`) with a face-Dirichlet value that varies along the face
    p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce], [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0 + y], [bk]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    rt = only(ig.runtimes)
    @test rt.cache.rows[1].op.field && rt.cache.op.jac !== nothing
    want = be_hand(u0, h; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
    @test maximum(abs, u .- want) < 1e-10
    # a mask whose value is a field (`masked(pred, 1 + x)`): each masked site takes its own value
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce], [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1 + x)], [bD, bk]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    mk = vec(BKIND .== 2)
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(1 .+ xs))
    @test maximum(abs, u .- want) < 1e-10 && all(u[mk] .== vec(1 .+ xs)[mk])
    # the face and mask value fields stepped explicitly too: one ExplicitEuler window is
    # `u0 + h r(u0)` off the mask, the mask value on it
    p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce],
        [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0 + y, bce ~ masked(bqe == 2, 1 + x)], [bk]))
    ig = init(p, ExplicitEuler(; dt = 1e-3, substeps = 1))
    u0 = copy(vec(ig[bce]))
    step!(ig)
    L, bb = hand_rate(; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
    want = ifelse.(mk, vec(1 .+ xs), u0 .+ 1e-3 .* (L * u0 .+ bb))
    @test u0[mk] == vec(1 .+ xs)[mk] && maximum(abs, vec(ig[bce]) .- want) < 1e-12
    # an input bound by aliasing: the operator reads the problem's own input array, and a write
    # of the input between windows changes the next solve (no copy; the warm window 0 B)
    p = bown(bsys([D(bce) ~ at(bW, bqe) * Δ(bce) - bk * bce + 1], [bc(0, x, y) ~ 0.0], [bW, bk]))
    ig = init(p, BackwardEuler(; dt = h, inner = BTIGHT))
    rt = only(ig.runtimes)
    r = rt.cache.rows[1]
    qid = fieldid(rt.program, "bq")
    jst = rt.cache.jac[1].launches                      # (the operator's launches read the store's array)
    @test LSB.field(r.solver, "in.f") === r.f && LSB.field(r.solver, "s") === r.s && r.f !== nothing
    @test any(l -> any(a -> a === rt.store.bufs[qid][1], Iterators.flatten(l.launch.params[2][1])), jst)
    step!(ig); step!(ig)
    @test bwarm(ig) == 0
    K2 = Int32[(i * j) % 2 for i in 1:8, j in 1:6]
    u1 = copy(vec(ig[bce]))
    ig[bqe] = K2
    step!(ig)
    want = be_hand(u1, h; K = (x, y) -> 1.0, m = (i, j) -> (0.0, 0.5, 2.0)[K2[i, j] + 1], k = (x, y) -> 2.0, f = (x, y) -> 1.0)
    @test maximum(abs, vec(ig[bce]) .- want) < 1e-10
    @test bwarm(ig) == 0
end
@testset "F3-07: SiteDiffusion rows (row scaling; m = 0 rows in two stages)" begin
    h = 0.05
    # `at(W, q) Δ(c)`: the row scaled by 1/m keeps the faces symmetric (q = 0 reads 0: m = 0 rows)
    p = bown(bsys([D(bce) ~ at(bW, bqe) * Δ(bce) - bk * bce + 1], [bc(0, x, y) ~ x], [bW, bk]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    mm = (i, j) -> (0.0, 0.5, 2.0)[BKIND[i, j] + 1]
    want = be_hand(u0, h; m = mm, k = (x, y) -> 2.0, f = (x, y) -> 1.0)
    @test maximum(abs, u .- want) < 1e-12
    @test only(ig.runtimes).cache.rows[1].op.scaled && only(ig.runtimes).cache.exact
    # a multiplier that is 0 on some rows (`ifelse(kind == 1, 0, D)`): the two-stage solve
    p = bown(bsys([D(bce) ~ ifelse(bqe == 1, 0.0, 0.7) * Δ(bce) - 50.0 * bce], [bc(0, x, y) ~ 1.0 + x], Any[]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = 0.1, inner = BTIGHT))
    want = be_hand(u0, 0.1; m = (i, j) -> BKIND[i, j] == 1 ? 0.0 : 0.7, k = (x, y) -> 50.0)
    @test maximum(abs, u .- want) < 1e-12
    # (the pinned-row rule `δ = G h` is a forward Euler step there: off by about 4 at decay 50)
    @test maximum(abs, u[vec(BKIND .== 1)] .- (u0[vec(BKIND .== 1)] ./ (1 + 0.1 * 50))) < 1e-12
    # `m Δ(c) + D Δ(c)` is `(m + D) Δ(c)`, exact
    p = bown(bsys([D(bce) ~ at(bW, bqe) * Δ(bce) + bD * Δ(bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
    ig, u0, u = be_window(p, BackwardEuler(; dt = h, inner = BTIGHT))
    want = be_hand(u0, h; m = (i, j) -> mm(i, j) + 0.3, k = (x, y) -> 2.0)
    @test maximum(abs, u .- want) < 1e-12 && only(ig.runtimes).cache.exact
    # two face coefficients: one stays in the residual with its bound, the operator is inexact
    # (more Newton iterations, from the bound, which converge to the BE step)
    p = bown(bsys([D(bce) ~ at(bW, bqe) * Δ(bce) + bD * DivKGrad(:harmonic)(1 + x, bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
    ig = init(p, BackwardEuler(; dt = h, newton = 40, inner = BTIGHT))
    rt = only(ig.runtimes)
    @test !rt.cache.op.rows[1].exact && !isempty(rt.cache.op.rows[1].inexact)
    @test init(p, BackwardEuler(; dt = h)).runtimes[1].cache.newton == 10 && init(p, BackwardEuler(; dt = h)).runtimes[1].cache.seen
end

@testset "F3-07: order 1, the manufactured solution, the stage tⁿ⁺¹" begin
    # the discrete sine is an eigenvector of the lattice Laplacian with Dirichlet 0 faces: the
    # semi-discrete solution is `e^{D λ t} u0`, so the BE error is the time error alone
    n = 16
    λ = 2 * (2cos(π / n) - 2) * n^2
    dirs = [bc(t, 0, y) ~ 0.0, bc(t, 1, y) ~ 0.0, bc(t, x, 0) ~ 0.0, bc(t, x, 1) ~ 0.0]
    sys = bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ sin(π * x) * sin(π * y); dirs], [bD]; T = 0.4, dvs = [bce])
    p = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned))
    u0 = [sin(π * (i - 0.5) / n) * sin(π * (j - 0.5) / n) for i in 1:n, j in 1:n]
    err(dt) = maximum(abs, blast(solve(p, BackwardEuler(; dt, inner = BTIGHT))) .- exp(0.3λ * 0.4) .* u0)
    es = [err(0.4 / 2^k) for k in 2:5]
    ord = log2.(es[1:(end - 1)] ./ es[2:end])
    @test all(o -> abs(o - 1) < 0.1, ord)
    # exactly the BE map: (1 − h D λ)^{-m}
    @test maximum(abs, blast(solve(p, BackwardEuler(; dt = 0.05, inner = BTIGHT))) .- (1 - 0.05 * 0.3λ)^-8 .* u0) < 1e-12
    # a manufactured solution `u = e^{−t} sin(πx) sin(πy) + t`: its source and the face value `t`
    # are read at tⁿ⁺¹; observed order 1 over four dt (the space error is below the time error)
    m = 64
    src = -exp(-t) * sin(π * x) * sin(π * y) + 1 + 2π^2 * 0.1 * exp(-t) * sin(π * x) * sin(π * y)
    faces = [bc(t, 0, y) ~ t, bc(t, 1, y) ~ t, bc(t, x, 0) ~ t, bc(t, x, 1) ~ t]
    ms = bsys([D(bce) ~ 0.1 * Δ(bce) + src], [bc(0, x, y) ~ sin(π * x) * sin(π * y); faces], Any[]; T = 1.0, dvs = [bce])
    pm = discretize(ms, LatticeDiscretization(Grid((m, m)); T = Float64, problem = :owned))
    exact = [exp(-1.0) * sin(π * (i - 0.5) / m) * sin(π * (j - 0.5) / m) + 1.0 for i in 1:m, j in 1:m]
    em = [maximum(abs, blast(solve(pm, BackwardEuler(; dt = 0.1 / 2^k, inner = BTIGHT))) .- exact) for k in 0:3]
    om = log2.(em[1:(end - 1)] ./ em[2:end])
    @test all(o -> abs(o - 1) < 0.1, om)
    # one window at the stage tⁿ⁺¹: the time-dependent source and face value of the hand matrix
    # at t = h (at t = 0, the wrong stage, it is off by about h)
    h = 0.1
    pm8 = discretize(ms, LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned))
    ig, u0, u = be_window(pm8, BackwardEuler(; dt = h, inner = BTIGHT))
    s1(xx, yy, tt) = -exp(-tt) * sin(π * xx) * sin(π * yy) + 1 + 2π^2 * 0.1 * exp(-tt) * sin(π * xx) * sin(π * yy)
    fc(tt) = Dict((a, s) => (:dir, tt) for a in 1:2, s in (-1, 1))
    want = be_hand(u0, h; K = (x, y) -> 0.1, f = (xx, yy) -> s1(xx, yy, h), faces = fc(h))
    wrong = be_hand(u0, h; K = (x, y) -> 0.1, f = (xx, yy) -> s1(xx, yy, 0.0), faces = fc(0.0))
    @test maximum(abs, u .- want) < 1e-9 && maximum(abs, u .- wrong) > 1e-2
end

@testset "F3-07: a stiff case, OrdinaryDiffEq's ImplicitEuler (SX-18)" begin
    # D h/dx² = 10⁴: BackwardEuler stays bounded and monotone; ExplicitEuler with one substep
    # (forced) blows up (`Unstable`)
    n = 16
    step0 = PDESystem([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ ifelse(x < 0.5, 1.0, 0.0)], bdom(80 * 1e4 / (0.3 * n^2)),
        [t, x, y], [bce], [bD]; name = :stiff)
    p = discretize(step0, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned))
    hs = 1e4 / (0.3 * n^2)
    s = solve(p, BackwardEuler(; dt = hs); saveat = 8hs)
    @test s.retcode == ReturnCode.Success && all(u -> all(v -> -1e-6 <= v <= 1 + 1e-6, u), s.u)
    @test all(k -> maximum(s.u[k + 1]) <= maximum(s.u[k]) + 1e-6 && minimum(s.u[k + 1]) >= minimum(s.u[k]) - 1e-6, 1:(length(s.u) - 1))
    ig = init(p, ExplicitEuler(; dt = hs))
    ig.substeps = 1
    solve!(ig)
    @test ig.retcode == ReturnCode.Unstable
    # the `:ode` path with OrdinaryDiffEq's ImplicitEuler (fixed steps, tight Newton) at equal dt
    sx = bsys([D(bce) ~ bD * Δ(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
        T = 0.4, dvs = [bce])
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :ode))
    # (the Newton tolerance follows abstol and reltol, 1e-12; the rate is linear, so a Newton step is exact)
    so = solve(po, ImplicitEuler(); dt = 0.05, adaptive = false, abstol = 1e-12, reltol = 1e-12)
    sb = solve(discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned)),
        BackwardEuler(; dt = 0.05, inner = BTIGHT))
    @test maximum(abs, vec(blast(sb)) .- so.u[end]) < 1e-8
end

@testset "F3-07: newton = nothing, the operator built only for implicit groups (S12)" begin
    p = bown(bsys([D(bce) ~ bD * Δ(bce) - bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
    b0 = LatticePDE.OPERATOR_BUILDS[]
    solve(p, ExplicitEuler(; dt = 0.01))
    @test LatticePDE.OPERATOR_BUILDS[] == b0                   # an explicit group builds none
    ig = init(p, BackwardEuler(; dt = 0.01))
    @test LatticePDE.OPERATOR_BUILDS[] == b0 + 1 && only(ig.runtimes).cache.newton == 1
    init(p, BackwardEuler(; dt = 0.02))
    @test LatticePDE.OPERATOR_BUILDS[] == b0 + 1               # once per group
    # an acyclic pair in one group (c reads o): one Newton step in topological order is exact
    p2 = discretize(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + 0.7 * boe, D(boe) ~ 0.5 * Δ(boe) - boe + x],
        [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0], [bD, bk]; dvs = [bce, boe]), LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned))
    ig = init(p2, BackwardEuler(; dt = 0.1, inner = BTIGHT))
    @test only(ig.runtimes).cache.newton == 1 && [r.key for r in only(ig.runtimes).cache.rows] == ["bo", "bc"]
    step!(ig)
    o1 = be_hand(zeros(48), 0.1; K = (x, y) -> 0.5, k = (x, y) -> 1.0, f = (x, y) -> x)
    c1 = be_hand(zeros(48), 0.1; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = let o = reshape(o1, BDIMS)
        (xx, yy) -> 0.7 * o[round(Int, xx * 8 + 0.5), round(Int, yy * 6 + 0.5)]
    end)
    @test maximum(abs, vec(ig[boe]) .- o1) < 1e-10 && maximum(abs, vec(ig[bce]) .- c1) < 1e-10
    # the substep count: 1, raised only by a positive local derivative (`+ g c`: n ≥ ⌈2 dt g⌉)
    @test init(p, BackwardEuler(; dt = 0.5)).substeps == 1
    pg = bown(bsys([D(bce) ~ bD * Δ(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
    @test init(pg, BackwardEuler(; dt = 0.5)).substeps == 2 && init(pg, BackwardEuler(; dt = 0.5, substeps = 5)).substeps == 5
end

@testset "F3-07: messages, the `:ode` path, `show`" begin
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    p = bown(bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ x], [bD]))
    # M1: a linear solver where a field solver goes names `BackwardEuler(; inner = …)`, which works
    m = e(() -> solve(p, DevicePCG(; budget = 12)))
    @test occursin("give it to one, `BackwardEuler(; inner = DevicePCG(; budget = 12))`", m)
    @test solve(p, BackwardEuler(; dt = 0.01, inner = DevicePCG(; budget = 12))).retcode == ReturnCode.Success
    m = e(() -> ExplicitEuler(; dt = 0.01, inner = Multigrid()))
    @test occursin("give it to an implicit field solver, `BackwardEuler(; inner = Multigrid())`", m)
    @test solve(p, BackwardEuler(; dt = 0.01, inner = Multigrid())).retcode == ReturnCode.Success
    # the `:ode` path: a field or linear solver given to an `ODEProblem`
    po = discretize(bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :ode))
    m = e(() -> solve(po, DevicePCG()))
    @test startswith(m, "`solve`/`init` of an `ODEProblem`: `DevicePCG()` is a linear solver, the `inner` of an implicit field solver") &&
          occursin("`ImplicitEuler()` is Backward Euler", m) && occursin("`solve(prob, BackwardEuler(; dt, inner = DevicePCG()))`", m)
    m = e(() -> init(po, BackwardEuler(; dt = 0.1)))
    @test startswith(m, "`solve`/`init` of an `ODEProblem`: `BackwardEuler(; dt = 0.1)` is a field solver") &&
          occursin("problem = :owned", m)
    @test solve(po, ImplicitEuler(); dt = 0.01, adaptive = false).retcode == ReturnCode.Success   # the route
    # the keywords
    for (f, want) in ((() -> BackwardEuler(; dt = 0.1, newton = 0), "BackwardEuler: newton = 0 is the Newton iterations"),
            (() -> BackwardEuler(; substeps = true), "BackwardEuler: substeps = true must be an integer ≥ 1"),
            (() -> BackwardEuler(; inner = :pcg), "BackwardEuler: `inner` takes `:auto`, a `DevicePCG(…)` or a `Multigrid(…)`"),
            (() -> BackwardEuler(; solver_T = BigFloat), "BackwardEuler: `solver_T` takes `:auto`"),
            (() -> BackwardEuler(; theta = 1), "BackwardEuler: no keyword `theta`; its keywords are `dt`, `substeps`, `newton`, `lower`, `inner`, `solver_T` and `init`"))
        @test startswith(e(f), want) || (println("MSG: ", e(f)); false)
    end
    a = BackwardEuler(; dt = 0.1, newton = 2, inner = DevicePCG(; budget = 12))
    @test eval(Meta.parse(repr(a))) == a
    # a map group has no implicit operator
    pm = discretize(PDESystem([Shift(t, 1)(bce) ~ 0.5 * bce], [bc(0, x, y) ~ x], bdom(), [t, x, y], [bce], Any[]; name = :m),
        LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned))
    @test occursin("a map program is stepped by ExplicitMap()", e(() -> init(pm, BackwardEuler(; dt = 1.0))))
end

# R1 (F3-06 review): a group whose step ends `StalledSuccess` (a rounding floor, accepted) does
# not stop the step: the later groups run. A failure still stops it. Base (437a84ef,
# ~/lpwork/f3b3-nc-r1.log): `go` does not move after a stalled `gc` step.
struct StallStub <: LFP.FieldAlgorithm
    dt::Float64
    code::ReturnCode.T
end
LFP.nbuffers(::StallStub) = 2
LFP.update_key(::StallStub) = :euler
LFP.update_rule(::StallStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::StallStub, group, store) = Ref(a.code)
LFP.step_retcode!(c::Base.RefValue{ReturnCode.T}, rt) = c[]
LFP.substeps(::LFP.FieldProblem, ::StallStub, p = nothing; tables = nothing, inputs = nothing, stability = nothing, fields = nothing) = 1
@testset "R1: StalledSuccess does not skip the later groups" begin
    p = gown(gsys())
    for (code, moves) in ((ReturnCode.StalledSuccess, true), (ReturnCode.ConvergenceFailure, false))
        ig = init(p, FieldGroups(gce => StallStub(0.01, code); default = ExplicitEuler(; dt = 0.01)))
        o0 = copy(ig[goe])
        step!(ig)
        @test (ig[goe] != o0) == moves && ig.retcode == code
    end
end

# F3-09a (F3 design §3.4): a local nonlinear term `f(c)` (offset 0, its own field only) enters
# the operator as `−∂f/∂c` at the iterate (`Symbolics.derivative`), so one Newton step per
# substep keeps order 1; a switch `a max(c − c_T, 0)` takes `newton = 2` (one flip pass, S1);
# a growth the count rule cannot see is clamped (the status word's cause bit 8), not a failure.
# Base (f078eb2e, ~/lpwork/f3b3-nc-09a-base.log): these terms are left in the residual (a
# defect correction, `newton = 4`), and the cache has no `iterate` (the testsets error).
# Negative control (mutation, ~/lpwork/f3b3-nc-09a-noderiv.log): the derivative left out of the
# shift (`push!(jterms, dj)` dropped in LatticePDE's `_build_operator`; the row stays exact, one
# Newton step) fails the stiff Michaelis–Menten case (an explicit `h ∂f/∂c` up to 32).
# The orders against the semi-discrete solution (the `:ode` path, Tsit5 at 1e-12), `n²` sites
function nl_orders(rhs, ic; T, dts, newton = nothing, n = 16)
    sys = PDESystem([D(bce) ~ rhs], [bc(0, x, y) ~ ic], bdom(T), [t, x, y], [bce], Any[]; name = :nl)
    ref = solve(discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :ode)), Tsit5();
        reltol = 1e-12, abstol = 1e-12).u[end]
    pb = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned))
    us = [vec(blast(solve(pb, BackwardEuler(; dt, inner = BTIGHT, newton)))) for dt in dts]
    es = [maximum(abs, u .- ref) for u in us]
    return es, log2.(es[1:(end - 1)] ./ es[2:end]), pb, us
end
const NLIC = 0.2 + 0.6 * x * y

@testset "F3-09a: local nonlinear rows: one Newton step keeps order 1" begin
    dts = [0.02 / 2^k for k in 0:3]
    # logistic growth `3 c (1 − c)`
    es, o, pb, _ = nl_orders(0.05 * Δ(bce) + 3 * bce * (1 - bce), NLIC; T = 0.5, dts)
    @test all(q -> abs(q - 1) < 0.1, o)                 # (measured 1.06, 1.03, 1.02)
    ig = init(pb, BackwardEuler(; dt = 0.02, inner = BTIGHT))
    c = only(ig.runtimes).cache
    @test c.newton == 1 && c.iterate && c.exact && only(c.rows).op.iterate && !only(c.rows).op.switch
    @test bwarm(ig) == 0
    # Michaelis–Menten uptake `−V c/(K + c)` with a time-dependent source (read at tⁿ⁺¹)
    es, o, _, _ = nl_orders(0.05 * Δ(bce) - 2 * bce / (0.5 + bce) + 1 + 0.5 * sin(10t), NLIC; T = 0.5, dts)
    @test all(q -> abs(q - 1) < 0.1, o)                 # (measured 1.00, 1.00, 1.00)
    # … stiff: V/K = 1600, `h |∂f/∂c|` up to 32; the errors fall at least linearly and stay small
    # (without the derivative the uptake is explicit and unstable at these steps)
    es, o, _, _ = nl_orders(0.05 * Δ(bce) - 40 * bce / (0.025 + bce) + 20 + 10 * sin(10t), NLIC; T = 0.3, dts)
    @test all(q -> q > 0.9, o) && maximum(es) < 1e-3     # (measured 5.7e-4 … 7.9e-7)
end

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
    @test maximum(abs, u2[1] .- u8[1]) < 1e-5 && maximum(abs, u1[1] .- u8[1]) > 1e-3
end

@testset "F3-09a: the switch's flip pass counts no budget hit (review r1, M7)" begin
    # the default count's second iteration fixes the switch state: no convergence test, so a
    # default user sees no warning (base 2d213237, ~/lpwork/f3r1-nc-base.log: 2 hits and the
    # budget warning in Float32 and Float64); a given `newton = 2` checks as before
    sys = PDESystem([D(bce) ~ 0.05 * Δ(bce) - 8 * max(bce - 0.4, 0) / 0.6 + 2 + 2 * sin(6t)], [bc(0, x, y) ~ NLIC], bdom(3.0),
        [t, x, y], [bce], Any[]; name = :sw)
    for T in (Float32, Float64)
        p = discretize(sys, LatticeDiscretization(Grid((32, 32)); T, problem = :owned))
        s = @test_logs min_level = Base.CoreLogging.Warn solve(p, BackwardEuler(; dt = 0.05))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
    end
    p = discretize(sys, LatticeDiscretization(Grid((32, 32)); T = Float64, problem = :owned))
    s = @test_logs (:warn, r"the Newton iteration \(`newton = 2`\) reached its budget") solve(p, BackwardEuler(; dt = 0.05, newton = 2))
    @test s.stats.newton_budget > 0
end

@testset "F3-09a: an unseen growth is clamped (the cause bit), not a failure" begin
    # `20 c² − 20 c` from c = 0.75: `∂f/∂c = 10` at the start, `h = 0.1`: the shift `1/h − 10`
    # is clamped at `1/(2h)`; the rest stays in the residual and the field decays
    sys = PDESystem([D(bce) ~ 0.05 * Δ(bce) + 20 * bce^2 - 20 * bce], [bc(0, x, y) ~ 0.75], bdom(0.3), [t, x, y], [bce], Any[];
        name = :clamp)
    pb = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    ig = init(pb, BackwardEuler(; dt = 0.1))
    # with one Newton step nothing else tells: a warning names the field, the window and the
    # route (review r1, S2; base 2d213237: no warning)
    @test_logs (:warn, r"^field `bc`: the implicit shift was clamped in window 1 \(t = 0\.0\) .*a larger `newton = k` checks the step") solve!(ig)
    rt = only(ig.runtimes)
    @test ig.retcode == ReturnCode.Success && rt.totals.cause & 0x08 != 0 && maximum(ig[bce]) < 1e-3
    # … once per run, and a site growth that the count rule cannot see (a field row whose growth
    # reads the time: no interval bounds it) warns too
    pg = discretize(PDESystem([D(bce) ~ 0.05 * Δ(bce) + 8 * (1 + x) * (1 + t) * bce], [bc(0, x, y) ~ 0.5], bdom(0.3), [t, x, y],
        [bce], Any[]; name = :sitegrowth), LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    @test_logs (:warn, r"the implicit shift was clamped in window 1") solve(pg, BackwardEuler(; dt = 0.1))
    # the route works: more substeps keep the growth below the shift (`h g ≤ 0.02 · 20.2 < 1/2`): no clamp
    s = @test_logs min_level = Base.CoreLogging.Warn solve(pg, BackwardEuler(; dt = 0.1, substeps = 5))
    @test s.retcode == ReturnCode.Success
    # a decay with no clamp leaves the bit clear
    ig = init(discretize(PDESystem([D(bce) ~ 0.05 * Δ(bce) - 20 * bce], [bc(0, x, y) ~ 0.75], bdom(0.3), [t, x, y], [bce], Any[];
        name = :noclamp), LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned)), BackwardEuler(; dt = 0.1))
    solve!(ig)
    @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.cause == 0
end

# F3-09b (F3 design §3.4, §3.6, M5, R2-M1): a term outside the operator is a defect correction.
# Count rule 2 keeps its contraction `ρ_c = γ h ρ_in ≤ 1/2` (`ρ_adv = Σ_a 2|u_a|/h_a` for upwind
# advection, `κ_in` for a cycle in the group), `newton = nothing` resolves from `ρ_c`, and the
# Newton check on the device (‖δ_k‖∞ ≤ 1e-3 ‖u_k − uⁿ‖∞ + 10 eps ‖u_k‖∞) counts a budget hit
# and ends a divergence; a host executor stops when every row met the tolerance.
# Base (7cead287, ~/lpwork/f3b3-nc-09b-base.log): no count rule 2, no check (the testsets fail).
# Negative controls (mutations, ~/lpwork/f3b3-nc-09b-*.log): count rule 2 without the advection
# bound (`norule2`): one substep, the correction diverges (`ConvergenceFailure`); the rounding
# floor dropped (`nofloor`): the field that barely moves reports budget hits.
# The BE map of the `:ode` path's rate, linear in u (assembled by columns): `nsub` steps per
# `dt`; with `timed` the matrix is assembled at each step's end time (an operator that reads
# the time), else once
function direct_be(sys, dims, dt, T, nsub; timed = false, inputs = [])
    po = discretize(sys, LatticeDiscretization(Grid(dims); T = Float64, problem = :ode); inputs)
    m = length(po.u0)
    f(u, tt) = (du = similar(u); po.f(du, u, po.p, tt); du)
    z = zeros(m)
    function mat(tt)
        A = zeros(m, m)
        f0 = f(z, tt)
        for j in 1:m
            e = zeros(m)
            e[j] = 1
            A[:, j] = f(e, tt) .- f0
        end
        return A
    end
    h = dt / nsub
    M = timed ? nothing : lu(I - h * mat(0.0))
    u = copy(po.u0)
    for s in 1:round(Int, T / h)
        rhs = u .+ h .* f(z, s * h)
        u = timed ? (I - h * mat(s * h)) \ rhs : M \ rhs
    end
    return u
end
nlsys(eqs, ics, dvs; T = 1.0) = PDESystem(eqs, ics, bdom(T), [t, x, y], dvs, Any[]; name = :dc)
nlown(sys; dims = (16, 16)) = discretize(sys, LatticeDiscretization(Grid(dims); T = Float64, problem = :owned))
const WARN = Base.CoreLogging.Warn

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
    @test maximum(abs, vec(blast(s)) .- ub) / maximum(abs, ub) < 1e-3       # (measured 3.7e-6)
    # a budget too small: counted, one warning with the count and the route (at the first read,
    # after the first window); the route works
    s2 = @test_logs (:warn, r"field `bc`: the Newton iteration \(`newton = 2`\) reached its budget \d+ times.*a larger `newton = k`") solve(p,
        BackwardEuler(; dt = 0.25, inner = BTIGHT, newton = 2))
    @test s2.retcode == ReturnCode.Success && s2.stats.newton_budget == 96
    s3 = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.25, inner = BTIGHT, newton = 12))
    @test s3.stats.newton_budget == 0
    # a field that barely moves (an increment below the rounding of the field): no budget hit
    still = nlown(nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([0.0, 0.0], bce) + 1e-16 * x], [bc(0, x, y) ~ 1.0], [bce]))
    ig = init(still, BackwardEuler(; dt = 0.25))
    @test only(ig.runtimes).cache.newton == 2
    solve!(ig)
    @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.newton_budget == 0
end

@testset "F3-09b: a cycle in a group converges by Gauss–Seidel (count rule 2)" begin
    # κ_in = 2 (the largest cross sum): n = ⌈2 · 0.5 · 2⌉ = 2, ρ_c = 0.25 · 2 = 1/2: newton = 10
    sys = nlsys([D(bce) ~ 0.1 * Δ(bce) - bce + 2 * boe, D(boe) ~ 0.1 * Δ(boe) - 3 * boe + 1.5 * bce + 1],
        [bc(0, x, y) ~ x, bo(0, x, y) ~ y], [bce, boe])
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
    @test rel(bce) < 1e-3 && rel(boe) < 1e-3
    # without the host stop (`newton = 10` given: ten sweeps) it is the coupled step to 1e-6
    r10 = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT, newton = 10))
    @test maximum(abs, r10[bce, length(r10.t)] .- r[bce, length(r.t)]) < 1e-6
end

@testset "review r1 M3: a nonlinear read of another row's field is a source in solve order" begin
    # acyclic (c reads o through a switch, o does not read c): the term is known when c is
    # solved, so the operator is exact, newton = 1 and no warning (base cb20be97: the term is
    # unseen, newton = 4 and the warning; ~/lpwork/f3b6r-nc-m3.log)
    p = nlown(nlsys([D(bce) ~ 0.1 * Δ(bce) - bce + 2.25 * max(boe - 0.5, 0), D(boe) ~ 0.1 * Δ(boe) - boe + x],
        [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ y], [bce, boe]); dims = BDIMS)
    ig = @test_logs min_level = WARN init(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
    c = only(ig.runtimes).cache
    @test c.newton == 1 && c.exact && !c.cyclic && [r.key for r in c.rows] == ["bo", "bc"]
    s = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT))
    r = solve(p, BackwardEuler(; dt = 0.5, inner = BTIGHT, newton = 12))
    @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
    @test maximum(abs, s[bce, length(s.t)] .- r[bce, length(r.t)]) < 1e-10
    # a cycle (o reads c back): the term stays unseen, newton = 4 and the warning
    pc = nlown(nlsys([D(bce) ~ 0.1 * Δ(bce) - bce + 2.75 * max(boe - 0.5, 0), D(boe) ~ 0.1 * Δ(boe) - boe + 0.5 * bce],
        [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ y], [bce, boe]); dims = BDIMS)
    ig = @test_logs (:warn, r"`2\.75max\(-0\.5 \+ bo, 0\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") match_mode = :any init(pc,
        BackwardEuler(; dt = 0.5, inner = BTIGHT))
    @test only(ig.runtimes).cache.newton == 4 && only(ig.runtimes).cache.cyclic
end

@testset "F3-09b: a term no bound sees warns once; a divergence ends the run" begin
    # a velocity that varies in time: no bound (the interval bound covers the coordinates, not
    # the time; F3-13 bounds `50(1 + x)`, below), one substep, newton = 4, checked on the device
    p = nlown(nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bce)], [bc(0, x, y) ~ x * y], [bce]; T = 2.0))
    s = @test_logs (:warn, r"field `bc`: `-Advect\(Upwind1\(\)\)\(\[.*t.*, 0\.0\], bc\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") (:warn,
        r"field `bc`: the solve failed in window 1 \(t = 0\.0\) \(the Newton iteration diverged\), `ReturnCode.ConvergenceFailure`") solve(p,
        BackwardEuler(; dt = 1.0))
    @test s.retcode == ReturnCode.ConvergenceFailure
    ig = init(p, BackwardEuler(; dt = 1.0))
    @test ig.substeps == 1 && only(ig.runtimes).cache.newton == 4 && !only(ig.runtimes).cache.seen
    # (once per group and term: a second problem does not warn at its build)
    @test_logs min_level = WARN init(p, BackwardEuler(; dt = 1.0))
end

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
    @test maximum(abs, vec(blast(s)) .- ub) / maximum(abs, ub) < 1e-3    # (batch 3 review r1 S2): a site growth the interval bound sees (`8(1 + x) c`, a field
    # row) raises the count by rule 1 instead: n = ⌈2 · 0.1 · 8 (2 + 1/8)⌉ = 4 (x over the box and
    # one spacing past it), no clamp and no warning, and the run is the BE matrix's (base
    # b41b73c1: one substep, the clamp warning)
    gsys = PDESystem([D(bce) ~ 0.05 * Δ(bce) + 8 * (1 + x) * bce], [bc(0, x, y) ~ 0.5], bdom(0.3), [t, x, y], [bce], Any[];
        name = :sitegrowth2)
    pg = discretize(gsys, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    ig = init(pg, BackwardEuler(; dt = 0.1, inner = BTIGHT))
    @test ig.substeps == 4
    @test_logs min_level = Base.CoreLogging.Warn solve!(ig)
    @test ig.retcode == ReturnCode.Success && only(ig.runtimes).totals.cause & 0x08 == 0
    ub = direct_be(gsys, (8, 8), 0.1, 0.3, 4)
    @test maximum(abs, vec(ig[bce]) .- ub) / maximum(abs, ub) < 1e-9
end

# F3 batch 3 review r1 (research/field-compiler/f3/reviews/F3-batch3-r1.md). Base 2d213237
# (~/lpwork/f3r1-nc-base.log) unless a testset names a mutation: each testset fails there.
r1tight() = DevicePCG(; rtol = 1e-13, budget = 200)
r1rel(a, b) = maximum(abs, a .- b) / maximum(abs, b)

@testset "r1 M1: an operator that reads the time is built at each substep's end time" begin
    # against BE with the matrix assembled at every substep's end time (base, ~/lpwork/f3r1-nc-base.log:
    # 6.6e-2, 1.6e-3, 1.6e-3 relative: every substep took the first substep's operator)
    for rate in (0.1 * Δ(bce) - (1 + 20t) * bce + 1, DivKGrad(:harmonic)(1 + 5t, bce) - bce + 1, (1 + 5t) * Δ(bce) - bce + 1)
        sys = nlsys([D(bce) ~ rate], [bc(0, x, y) ~ x * y], [bce]; T = 0.4)
        p = nlown(sys; dims = (10, 8))
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.2, substeps = 4, inner = r1tight()))
        @test r1rel(vec(blast(s)), direct_be(sys, (10, 8), 0.2, 0.4, 4; timed = true)) < 1e-10   # (measured 1.8e-14)
        c = only(init(p, BackwardEuler(; dt = 0.2, substeps = 4)).runtimes).cache
        @test c.timed && c.exact && c.newton == 1
    end
    # SX-18 with a time-dependent coefficient: OrdinaryDiffEq's ImplicitEuler at the substep
    sx = nlsys([D(bce) ~ DivKGrad(:harmonic)(0.3 * (1 + 5t), bce) - (1 + 20t) * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0],
        [bce]; T = 0.4)
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :ode))
    # (a fresh Jacobian at every Newton iteration: with the matrix of the step's start, the
    # simplified Newton iteration of a time-dependent operator needs more than its default 10
    # iterations at 1e-12 and reports `ConvergenceFailure`)
    ie = ImplicitEuler(; nlsolve = OrdinaryDiffEqSDIRK.NLNewton(; max_iter = 50, always_new = true))
    so = solve(po, ie; dt = 0.05, adaptive = false, abstol = 1e-12, reltol = 1e-12)
    @test so.retcode == ReturnCode.Success
    sb = solve(nlown(sx; dims = (8, 8)), BackwardEuler(; dt = 0.2, substeps = 4, inner = r1tight()))
    @test maximum(abs, vec(blast(sb)) .- so.u[end]) < 1e-8                  # (base: 5.8e-3)
    # an operator that does not read the time is built once per window, as before
    pc = nlown(nlsys([D(bce) ~ DivKGrad(:harmonic)(1 + x, bce) - bce + sin(3t)], [bc(0, x, y) ~ x], [bce]; T = 0.4); dims = (10, 8))
    ig = init(pc, BackwardEuler(; dt = 0.2, substeps = 4))
    solve!(ig)
    @test !only(ig.runtimes).cache.timed && only(ig.runtimes).cache.rebuilds == 1
end

@testset "r1 M2, S1: a Robin face's sign follows a parameter write; a negative face is bounded" begin
    # `1.5 c − rb ∂c/∂x = 0.2` at x = 1: rb = −1 a positive diagonal, rb = +1 a negative one
    function robin(rate, v)
        @parameters rb = v
        return PDESystem([D(bce) ~ rate], [bc(0, x, y) ~ x * y, 1.5 * bc(t, 1, y) - rb * Differential(x)(bc(t, 1, y)) ~ 0.2],
            bdom(1.0), [t, x, y], [bce], [rb]; name = :rob), rb
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
            @test maximum(abs, vec(ig[bce]) .- vec(fresh[bce])) < 1e-12   # (base, rb −1 → +1: 2.4e-2 numeric, 5.1e-2 field)
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
    @test r1rel(vec(blast(s)), vec(blast(r))) < 1e-4                       # (measured 3.8e-5; base 2.1e-4)
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
    @test r1rel(vec(blast(s)), vec(blast(r))) < 1e-4
    # … and a face coefficient no interval bounds (it reads an input field) is unseen: a warning
    # at `init` that names the face (base: none at `init`, only the budget warning later)
    @variables rk(..) [input = true]
    rke = rk(t, x, y)
    sysk = PDESystem([D(bce) ~ DivKGrad(:harmonic)(0.3 * (1 + rke), bce) - 2 * bce + 1],
        [bc(0, x, y) ~ x * y, 1.5 * bc(t, 1, y) - Differential(x)(bc(t, 1, y)) ~ 0.2], bdom(1.0), [t, x, y], [bce, rke], Any[]; name = :robk)
    pk = discretize(sysk, LatticeDiscretization(Grid((10, 8)); T = Float64, problem = :owned); inputs = [rke => fill(0.5, 10, 8)])
    c = @test_logs (:warn, r"the Robin face of `bc` on axis 1 \(high side\), whose diagonal is negative at these parameters, is not in the implicit operator and no bound sees it") match_mode = :any only(init(pk,
        BackwardEuler(; dt = 0.1)).runtimes).cache
    @test !c.exact && !c.seen && c.newton == 4
end

@testset "r1 M3: a scaled row keeps the face coefficient with the largest bound" begin
    @parameters rW[1:2] = [50.0, 200.0]
    @variables rq(..)::Int32 [input = true]
    rqe = rq(t, x, y)
    kind = Int32[(i + j) % 2 + 1 for i in 1:16, j in 1:16]
    for (rate, out) in ((at(rW, rqe) * Δ(bce) + 0.01 * DivKGrad(:harmonic)(1 + x, bce) - bce, "0.01DivKGrad(:harmonic)(1 + x, bc)"),
                        # the reversed weights: the face coefficient's term is the stiff one
                        (0.0001 * at(rW, rqe) * Δ(bce) + 5 * DivKGrad(:harmonic)(1 + x, bce) - bce, "0.0001at(rW, rq)*Δ(bc)"))
        sys = PDESystem([D(bce) ~ rate], [bc(0, x, y) ~ x], bdom(0.2), [t, x, y], [bce, rqe], [rW]; name = :scaled)
        p = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64, problem = :owned); inputs = [rqe => kind])
        ig = init(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
        row = only(only(ig.runtimes).cache.rows).op
        @test only(row.inexact) == "`$out` (in the rate of `bc`)" && isempty(row.unseen) && only(ig.runtimes).cache.seen
        # base: the first term in the canonical order stays (here the small one), the stiff term
        # is out and unseen: `newton = 4`, a warning, and `ConvergenceFailure` in window 1
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        ref = direct_be(sys, (16, 16), 0.05, 0.2, ig.substeps; inputs = [rqe => kind])
        @test r1rel(vec(blast(s)), ref) < 1e-4                              # (base: 1.8e8, diverged)
    end
end

@testset "r1 M4: BackwardEuler on a hexagonal lattice is refused in words; ExplicitEuler steps it" begin
    sys = nlsys([D(bce) ~ 2.0 * Δ(bce) - bce + 1], [bc(0, x, y) ~ x], [bce])
    p = discretize(sys, LatticeDiscretization(Grid((16, 16); geometry = HEX); T = Float64, problem = :owned))
    # base: a defect correction that diverges, with the route "more substeps … or a larger linear
    # budget", which does not work either
    @test_throws "BackwardEuler: field `bc`: a hexagonal lattice has no implicit solve yet (the solver's operator has no hexagonal faces); step it with `ExplicitEuler`" init(p,
        BackwardEuler(; dt = 0.1))
    @test solve(p, ExplicitEuler(; dt = 0.1)).retcode == ReturnCode.Success
end

@testset "r1 M5: π and ℯ lower in a source, a coefficient and a face value (both paths)" begin
    # base: "cannot lower `π`: `identity` has no lattice lowering" on every path
    sym = nlsys([D(bce) ~ π * Δ(bce) - ℯ * bce + sin(π * x) + ℯ], [bc(0, x, y) ~ cos(π * y), bc(t, 0, y) ~ π / 2 + ℯ * y], [bce]; T = 0.2)
    num = nlsys([D(bce) ~ Float64(π) * Δ(bce) - Float64(ℯ) * bce + sin(Float64(π) * x) + Float64(ℯ)],
        [bc(0, x, y) ~ cos(Float64(π) * y), bc(t, 0, y) ~ Float64(π) / 2 + Float64(ℯ) * y], [bce]; T = 0.2)
    for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05, inner = r1tight()))
        a, b = blast(solve(nlown(sym; dims = (8, 8)), alg)), blast(solve(nlown(num; dims = (8, 8)), alg))
        @test maximum(abs, a .- b) < 1e-13
    end
    # `π Δ(c)` is a numeric face coefficient (no field row)
    @test !only(only(init(nlown(sym; dims = (8, 8)), BackwardEuler(; dt = 0.05)).runtimes).cache.rows).op.field
    ode(s) = discretize(s, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :ode))
    pa, pb = ode(sym), ode(num)
    da, db = similar(pa.u0), similar(pb.u0)
    pa.f(da, pa.u0, pa.p, 0.1)
    pb.f(db, pb.u0, pb.p, 0.1)
    @test pa.u0 ≈ pb.u0 && maximum(abs, da .- db) < 1e-11
end

@testset "r1 M6, N2: a component field gets the operator of its scalar spelling" begin
    @variables bu(..)[1:2]
    bue = bu(t, x, y)
    comp = nlsys([D(bue[1]) ~ 0.05 * Δ(bue[1]) - 40 * bue[1] / (0.025 + bue[1]) + 20, D(bue[2]) ~ 0.05 * Δ(bue[2]) - bue[2] + bue[1]],
        [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3)
    scal = nlsys([D(bce) ~ 0.05 * Δ(bce) - 40 * bce / (0.025 + bce) + 20, D(boe) ~ 0.05 * Δ(boe) - boe + bce],
        [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3)
    pc, ps = nlown(comp), nlown(scal)
    cc, cs = only(init(pc, BackwardEuler(; dt = 0.05)).runtimes).cache, only(init(ps, BackwardEuler(; dt = 0.05)).runtimes).cache
    # base: every term of both rows unseen, five warnings, newton = 4, no solve
    @test cc.newton == cs.newton == 1 && cc.exact && [r.op.iterate for r in cc.rows] == [r.op.iterate for r in cs.rows] == [true, false]
    @test all(r -> isempty(r.op.unseen), cc.rows) && [r.op.faces for r in cc.rows] == [r.op.faces for r in cs.rows]
    a = @test_logs min_level = WARN solve(pc, BackwardEuler(; dt = 0.05))
    b = solve(ps, BackwardEuler(; dt = 0.05))
    @test a.stats == b.stats && a.stats.solves == 12
    @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
    # N2: a component read in a message is `u[1]` as written (base: `(bu)[1]`)
    pv = nlown(nlsys([D(bue[1]) ~ 0.01 * Δ(bue[1]) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bue[1]), D(bue[2]) ~ -bue[2]],
        [bu(0, x, y)[1] ~ x, bu(0, x, y)[2] ~ 0.0], [bue]))
    @test_logs (:warn, r"`-Advect\(Upwind1\(\)\)\(\[.*, 0\.0\], bu\[1\]\)` \(in the rate of `bu\[1\]`\) is not in the implicit operator") match_mode = :any init(pv,
        BackwardEuler(; dt = 0.1))
end

@testset "r1 S4, S6, N1: the failure route follows the cause; rule 2 on the sum; show" begin
    alg = BackwardEuler(; dt = 0.1)
    @test LFB.status_route(alg, :failure, 0x2) == LFB.status_route(alg, :failure, 0x6) ==
          "more substeps (`substeps = n`): a smaller step brings the Newton iteration into its contraction"
    @test LFB.status_route(alg, :failure, 0x1) == "more substeps (`substeps = n`) or a larger linear budget (`inner = DevicePCG(; budget = n)`)"
    # a Newton divergence in a run names that route (base: "… or a larger linear budget")
    p = nlown(nlsys([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bce)], [bc(0, x, y) ~ x * y], [bce]; T = 2.0))
    @test_logs (:warn, r"the Newton iteration diverged\), `ReturnCode.ConvergenceFailure`: the run stops; more substeps \(`substeps = n`\): a smaller step brings the Newton iteration into its contraction$") match_mode = :any solve(p,
        BackwardEuler(; dt = 1.0))
    # S6: advection (ρ_adv = 48) and a cycle (κ_in = 2) in one group: n = ⌈2 · 0.25 · 50⌉ = 25,
    # so ρ_c = 1/2 and newton = 10 (base, rule 2 on the larger: n = 24, ρ_c = 0.52, newton = 11)
    @parameters bvx = 1.0
    p = nlown(PDESystem([D(bce) ~ 0.01 * Δ(bce) - Advect(Upwind1())([bvx, 0.5], bce) + 2 * boe, D(boe) ~ 0.1 * Δ(boe) - 3 * boe + 1.5 * bce],
        [bc(0, x, y) ~ x * y, bo(0, x, y) ~ y], bdom(1.0), [t, x, y], [bce, boe], [bvx]; name = :s6))
    ig = init(p, BackwardEuler(; dt = 0.25, inner = BTIGHT))
    c = only(ig.runtimes).cache
    @test c.cyclic && c.ρin == 50.0 && ig.substeps == 25 && c.newton == 10
    # the reviewer's write `vx = 8`: ρ_in = 2 (8 + 0.5) 16 + 2 = 274, n = 137, newton 10 at once
    # (R2-N3: the step follows the recount; base: newton 12 until the next window)
    ig.ps[bvx] = 8.0
    @test ig.substeps == 137 && c.h == 0.25 / 137 && c.newton == 10
    step!(ig)
    @test ig.substeps == 137 && c.newton == 10 && only(ig.runtimes).totals.newton_budget == 0
    # N1: `ExplicitEuler` prints by keyword, as `BackwardEuler` does
    @test sprint(show, ExplicitEuler(; dt = 0.1, substeps = 15)) == "ExplicitEuler(; dt = 0.1, substeps = 15)"
    @test sprint(show, ExplicitEuler()) == "ExplicitEuler()"
end

@testset "R2-M1: a diffusion term left out of a scaled row contracts by its face-wise ratio" begin
    @variables r2q(..)::Int32 [input = true]
    r2qe = r2q(t, x, y)
    kind = Int32[(i + j) % 2 for i in 1:16, j in 1:16]
    function prob(W, rate)
        @parameters r2W[1:2] = W
        sys = PDESystem([D(bce) ~ rate(r2W)], [bc(0, x, y) ~ x], bdom(0.5), [t, x, y], [bce, r2qe], [r2W]; name = :r2)
        return sys, discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64, problem = :owned); inputs = [r2qe => kind])
    end
    # the reviewer's case: `5 DivKGrad(1 + x)` kept (its bound is the larger), `at(W, q) Δ(c)`
    # out with θ = 2 / (5 · (1 − 1/16)) = 0.43 ≤ 1/2: one substep, newton 1 + ⌈log 1e-3 / log θ⌉ = 10,
    # no budget hit, the direct BE (base 9585df2e: 410 substeps, 8,228 solves)
    sys, p = prob([0.5, 2.0], W -> at(W, r2qe) * Δ(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce)
    for alg in (BackwardEuler(; dt = 0.05, inner = r1tight()), BackwardEuler(; dt = 0.05, substeps = 1, inner = r1tight()))
        ig = init(p, alg)
        c = only(ig.runtimes).cache
        @test ig.substeps == 1 && c.θ ≈ 2 / (5 * 15 / 16) && c.ρin == 0 && c.newton == 10
        s = @test_logs min_level = WARN solve(p, alg)
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0 && s.stats.solves < 100
        @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, 1; inputs = [r2qe => kind])) < 1e-4
    end
    # θ = 4 / 4.69 > 1/2: the term's Gershgorin bound counts (rule 2 raises the count), and a
    # requested count below it warns why
    sys, p = prob([1.0, 4.0], W -> at(W, r2qe) * Δ(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce)
    ig = init(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    c = only(ig.runtimes).cache
    @test c.θ == 0 && c.ρin > 0 && ig.substeps > 1
    n = ig.substeps
    ig = @test_logs (:warn, r"^BackwardEuler\(substeps = 1\): field `bc` takes \d+ substeps, more than the 1 requested: the terms out of the implicit operator \(`at\(r2W, r2q\)\*Δ\(bc\)` \(in the rate of `bc`\)\) are corrected by Newton iterations, which converge only when the substep keeps their contraction at most 1/2; fewer substeps would not converge$") init(p,
        BackwardEuler(; dt = 0.05, substeps = 1, inner = r1tight()))
    @test ig.substeps == n
    s = solve(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
    @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, n; inputs = [r2qe => kind])) < 1e-4
    # a kept multiplier with zero rows (`ifelse(q == 1, 0, 8) Δ(c)` kept): no ratio, the bound counts
    sys, p = prob([0.5, 2.0], W -> ifelse(r2qe == 1, 0.0, 8.0) * Δ(bce) + DivKGrad(:harmonic)(1 + x, bce) - bce)
    ig = init(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    c = only(ig.runtimes).cache
    @test c.θ == 0 && c.ρin > 0 && ig.substeps > 1
    s = solve(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
    @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, ig.substeps; inputs = [r2qe => kind])) < 1e-4
end

# Batch 3 review r3 N3: at rule 2's limit with θ > 0 the contraction bound is `ρ_c = (1 + θ)/2`
# (up to 3/4), which 12 iterations cannot bring to ε_N: the cap is 26 when θ > 0, so the count
# meets `ρ_c^(k − 1) ≤ ε_N` (base 69bef544: clamped at 12, `0.715^11 = 0.025`); with θ = 0 the
# count and its cap 12 are unchanged
@testset "r3 N3: the Newton count meets the tolerance at rule 2's limit with θ > 0" begin
    θ = 0.43
    for (ρh, want) in ((0.5 * (1 - θ), 22), (0.1, 12), (0.0, 10))
        k = LFP._newton_count(false, false, true, ρh / 0.01, 1.0, 0.01, θ)
        ρc = ρh + θ
        @test k == want && ρc^(k - 1) <= LFP.NEWTON_EPS || (println("θ count ", (ρh, k)); false)
    end
    @test LFP._newton_count(false, false, true, 0.5 / 0.01, 1.0, 0.01, 0.0) == 10          # (θ = 0: unchanged)
    @test LFP._newton_count(false, false, true, 2.0 / 0.01, 1.0, 0.01, 0.0) == 12          # (ρ_c ≥ 1: the cap 12)
    # a run: the reviewer's left-out diffusion (θ = 0.43) with advection at the rule-2 count
    @variables r3q(..)::Int32 [input = true]
    r3qe = r3q(t, x, y)
    kind = Int32[(i + j) % 2 for i in 1:16, j in 1:16]
    @parameters r3W[1:2] = [0.5, 2.0]
    sys = PDESystem([D(bce) ~ at(r3W, r3qe) * Δ(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce -
                              Advect(Upwind1())([2.0, 0.0], bce)], [bc(0, x, y) ~ x], bdom(0.5), [t, x, y], [bce, r3qe],
        [r3W]; name = :r3)
    p = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64, problem = :owned); inputs = [r3qe => kind])
    ig = init(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    c = only(ig.runtimes).cache
    @test c.θ > 0.4 && c.ρin > 0 && c.newton > 12
    s = @test_logs min_level = WARN solve(p, BackwardEuler(; dt = 0.05, inner = r1tight()))
    @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
    @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, ig.substeps; inputs = [r3qe => kind])) < 1e-4
end

# A parameter write that changes the automatic count sets the step at once (R2-N3) from the new
# parameters: the shift of a numeric row reads them (base 69bef544: the bound parameters were
# copied after the recount, so the step's shift kept the old growth `g`: 6.58 against 8.82)
@testset "r3: a write that changes the count sets the step from the new parameters" begin
    @parameters r3g = 1.0
    sg = bsys([D(bce) ~ bD * Δ(bce) + r3g * bce], [bc(0, x, y) ~ x * y], [bD, r3g]; T = 2.0, dvs = [bce])
    pg = discretize(sg, LatticeDiscretization(Grid(BDIMS); T = Float64, problem = :owned))
    ig = init(pg, BackwardEuler(; dt = 0.5, inner = BTIGHT))
    step!(ig)
    u = vec(ig[bce])
    ig.ps[r3g] = 4.0
    @test ig.substeps == 4
    step!(ig)
    fresh = init(remake(pg; u0 = u, p = [r3g => 4.0]), BackwardEuler(; dt = 0.5, inner = BTIGHT))
    step!(fresh)
    @test vec(ig[bce]) == vec(fresh[bce])
end

@testset "R2-N1: the operator build count starts at 0 in a fresh session" begin
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e "using LatticePDE; print(LatticePDE.OPERATOR_BUILDS[])"`
    @test read(cmd, String) == "0"                                   # (base: 1, the precompile workload's)
end

# Review r3 N1: an operator of another field in a row (cross-diffusion `0.1 Δ(q)` in the rate of
# `c`) stays in the residual, a defect term the Newton check covers (no bound sees it: newton 4,
# warned with the term), so the owned implicit path solves what `:ode` lowers. Base (e7068add,
# ~/lpwork/f3b6-nc-r3.log): "`Δ` is symbolic-only" from the cross term's bound.
using OrdinaryDiffEqSDIRK: ImplicitEuler
@testset "r3 N1: cross-diffusion in an implicit group is a defect term" begin
    @variables xq(..)
    xqe = xq(t, x, y)
    sx = PDESystem([D(bce) ~ 0.3 * Δ(bce) + 0.1 * Δ(xqe) - 2.0 * bce + x, D(xqe) ~ 0.3 * Δ(xqe) - xqe + 0.5 * bce],
        [bc(0, x, y) ~ 0.0, xq(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [bce, xqe], Any[]; name = :cross)
    p = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    r = @test_logs (:warn, r"`0.1Δ\(xq\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") match_mode = :any solve(p,
        BackwardEuler(; dt = 0.1, inner = BTIGHT))
    @test r.retcode == ReturnCode.Success
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :ode))
    ro = SciMLBase.solve(po, ImplicitEuler(); adaptive = false, dt = 0.1, abstol = 1e-12, reltol = 1e-12)
    @test maximum(abs, ro.u[end] .- r.u[end]) < 1e-6 || (println("r3 N1 ", maximum(abs, ro.u[end] .- r.u[end])); false)
end
