# Definitions of implicit_tests.jl that other test files use.
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
# (the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
bown(sys; dims = BDIMS, T = Float64, kw...) =
    LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T, kw...); inputs = [bqe => BKIND]))
const BTIGHT = LatticePCG(; reltol = 1.0e-12, maxiters = 64)
bwarm(ig) = (step!(ig); @allocated step!(ig))              # (a function barrier)
blast(s) = s[bce, length(s.t)]                             # the last save

# The hand BE matrix of a cell-centered grid on [0, 1]² (`dims` sites, cell centers
# `(i − ½) h`): the rate `r(u)_i = m_i Σ_a Σ_± w (u_nb − u_i)/h_a² − k_i u_i + f_i`, with the
# harmonic face `w = 2K_i K_nb/(K_i + K_nb)` (`K` at the neighbor's center, a ghost center at a
# face of the box). A box face takes `faces[(a, side)]`: `(:dir, g)` (ghost `2g − u_i`) or
# `(:robin, α, β, g)` for `α u + β ∂u/∂x_a = g` as written (ghost from `α (u_g + u_i)/2 +
# β side (u_g − u_i)/h = g`), `α`, `β`, `g` numbers or functions of the face point; no entry is zero
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
                ev(v) = v isa Function ? v(fp...) : v
                g = ev(fc[end])
                # (α and β may vary along the face, functions of the face point)
                p, q = fc[1] === :dir ? (-1.0, 2g) :
                       (al = ev(fc[2]); bl = ev(fc[3]) * s / hs[a]; den = al / 2 + bl; ((bl - al / 2) / den, g / den))
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
function be_window(prob, alg; dt)
    ig = init(prob, alg; dt)
    u0 = copy(vec(ig[bce]))
    step!(ig)
    return ig, u0, vec(ig[bce])
end

# A group whose step ends `StalledSuccess` (a rounding floor, accepted) does
# not stop the step: the later groups run. A failure still stops it. Before the fix (437a84ef):
# `go` does not move after a stalled `gc` step.
struct StallStub <: LFP.AbstractFieldAlgorithm
    code::ReturnCode.T
end
LFP.nbuffers(::StallStub) = 2
LFP.update_key(::StallStub) = :euler
LFP.update_rule(::StallStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::StallStub, group, store) = Ref(a.code)
LFP.step_retcode!(c::Base.RefValue{ReturnCode.T}, rt) = c[]
LFP.substeps(::LFP.FieldProblem, ::StallStub, p = nothing; tables = nothing, inputs = nothing, stability = nothing, fields = nothing, dt = nothing) = 1

# A local nonlinear term `f(c)` (offset 0, its own field only) enters
# the operator as `−∂f/∂c` at the iterate (`Symbolics.derivative`), so one Newton step per
# substep keeps order 1; a switch `a max(c − c_T, 0)` takes `newton = 2` (one flip pass);
# a growth the count rule cannot see is clamped (the status word's cause bit 8), not a failure.
# Before the fix (f078eb2e): these terms are left in the residual (a
# defect correction, `newton = 4`), and the cache has no `iterate` (the testsets error).
# Negative control (mutation): the derivative left out of the
# shift (`push!(jterms, dj)` dropped in LatticePDE's `_build_operator`; the row stays exact, one
# Newton step) fails the stiff Michaelis–Menten case (an explicit `h ∂f/∂c` up to 32).
# The orders against the semi-discrete solution (the `:ode` path, Tsit5 at 1e-12), `n²` sites
function nl_orders(rhs, ic; T, dts, nlsolve = nothing, n = 16)
    sys = PDESystem([D(bce) ~ rhs], [bc(0, x, y) ~ ic], bdom(T), [t, x, y], [bce], Any[]; name = :nl)
    ref = solve(discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64)), Tsit5();
        reltol = 1e-12, abstol = 1e-12).u[end]
    pb = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64))
    us = [vec(blast(solve(pb, BackwardEuler(; linsolve = BTIGHT, nlsolve); dt))) for dt in dts]
    es = [maximum(abs, u .- ref) for u in us]
    return es, log2.(es[1:(end - 1)] ./ es[2:end]), pb, us
end
const NLIC = 0.2 + 0.6 * x * y

# A term outside the operator is a defect correction.
# Count rule 2 keeps its contraction `ρ_c = γ h ρ_in ≤ 1/2` (`ρ_adv = Σ_a 2|u_a|/h_a` for upwind
# advection, `κ_in` for a cycle in the group), `newton = nothing` resolves from `ρ_c`, and the
# Newton check on the device (‖δ_k‖∞ ≤ 1e-3 ‖u_k − uⁿ‖∞ + 10 eps ‖u_k‖∞) counts a budget hit
# and ends a divergence; a host executor stops when every row met the tolerance.
# Before the fix (7cead287): no count rule 2, no check (the testsets fail).
# Negative controls (mutations): count rule 2 without the advection
# bound (`norule2`): one substep, the correction diverges (`ConvergenceFailure`); the rounding
# floor dropped (`nofloor`): the field that barely moves reports budget hits.
# The BE map of the `:ode` path's rate, linear in u (assembled by columns): `nsub` steps per
# `dt`; with `timed` the matrix is assembled at each step's end time (an operator that reads
# the time), else once
function direct_be(sys, dims, dt, T, nsub; timed = false, inputs = [])
    po = discretize(sys, LatticeDiscretization(Grid(dims); T = Float64); inputs)
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
nlown(sys; dims = (16, 16)) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T = Float64)))
const WARN = Base.CoreLogging.Warn

# Before the fix (2d213237), unless a testset names a mutation: each testset fails there.
tightpcg() = LatticePCG(; reltol = 1.0e-13, maxiters = 200)
relerr(a, b) = maximum(abs, a .- b) / maximum(abs, b)

# A hexagonal lattice (axial coordinates; `laplacian` is `2/(3h²) Σₙ (cₙ − c)` over the six
# neighbors ±e₁, ±e₂, ±(e₁ − e₂)): the implicit solve's operator has its three face directions.
# The hand rate on `[0, 1]²` with `n × n` sites (`h = 1/n`, the site `(i, j)` at
# `((i − ½)h, (j − ½)h)`): `r(u)_i = m_i D 2/(3h²) Σₙ (u_n − u_i) − k u_i + f_i`, a neighbor
# outside a closed box left out (zero flux), wrapped on a periodic one. `hex_hand` returns the
# rate `(L, b)`. Base (ee577f6e): `init` refuses every implicit algorithm on a hexagonal lattice.
# Negative control: the operator without the diagonal faces fails the
# one-window tests (the defect correction of the left-out faces does not reach 1e-9).
const HEXN = 12
const HEXO = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
function hex_hand(; n = HEXN, D = 1.0, m = (x, y) -> 1.0, k = 0.0, f = (x, y) -> 0.0, periodic = false, faces = Dict())
    h = 1 / n
    lin(i, j) = i + (j - 1) * n
    L, b = zeros(n^2, n^2), zeros(n^2)
    for j in 1:n, i in 1:n
        r = lin(i, j)
        xi, yi = (i - 0.5) * h, (j - 0.5) * h
        for (di, dj) in HEXO
            ii, jj = i + di, j + dj
            c = m(xi, yi) * D * 2 / (3h^2)
            if !(1 <= ii <= n && 1 <= jj <= n) && !periodic
                # a link that leaves the box: the face of axis 1 if it leaves along axis 1, else of
                # axis 2; `(:dir, g)` (ghost `2g − u`) or `(:robin, α, β, g)` for `α u + β ∂u/∂x_a = g`
                # along the link (ghost from `α (u_g + u)/2 + β s (u_g − u)/h = g`); none: zero flux
                a = 1 <= ii <= n ? 2 : 1
                sd = a == 1 ? sign(di) : sign(dj)
                haskey(faces, (a, sd)) || continue
                fc = faces[(a, sd)]
                pg, qg = fc[1] === :dir ? (-1.0, 2fc[2]) :
                         (bl = fc[3] * sd / h; den = fc[2] / 2 + bl; ((bl - fc[2] / 2) / den, fc[4] / den))
                L[r, r] += c * (pg - 1)
                b[r] += c * qg
                continue
            end
            L[r, lin(mod1(ii, n), mod1(jj, n))] += c
            L[r, r] -= c
        end
        L[r, r] -= k
        b[r] += f(xi, yi)
    end
    return L, b
end
const HEXKIND = Int32[(i + 2j) % 3 for i in 1:HEXN, j in 1:HEXN]
hexdisc(sys; T = Float64, inputs = [bqe => HEXKIND], kw...) =
    LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((HEXN, HEXN); geometry = HEX); T, kw...); inputs))
const HEXPER = [bc(t, 0, y) ~ bc(t, 1, y), bc(t, x, 0) ~ bc(t, x, 1)]

# An operator of another field in a row (cross-diffusion `0.1 laplacian(q)` in the rate of
# `c`) stays in the residual, a defect term the Newton check covers (no bound sees it: newton 4,
# warned with the term), so the owned implicit path solves what `:ode` lowers. Before the fix (e7068add):
# "`laplacian` is symbolic-only" from the cross term's bound.
using OrdinaryDiffEqSDIRK: ImplicitEuler
