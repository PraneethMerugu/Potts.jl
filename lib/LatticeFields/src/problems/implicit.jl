# The implicit runtime (F3 design §3.3, §3.4): the substep loop of the implicit algorithms
# (`BackwardEuler`, `CrankNicolson`, `BDF2`) on the group layer, for both front ends. A group's
# store holds the arrays of its stepped program (the state's two slots, the inputs, the masks);
# the runtime's own programs alias them:
#
# - the residual program (`fuse_residual`): each `rate:c` kernel stores
#   `G = (q − u_k)/(γh) + r(u_k)` into `res:c`, `u_k` the iterate (slot `p` at the first Newton
#   iteration, the other slot after it), `q` the stage's right side (`c__n`: the substep's start
#   `uⁿ` for Backward Euler; Crank–Nicolson's `uⁿ + (h/2) r(uⁿ)`, BDF2's `(4uⁿ − uⁿ⁻¹)/3`, both
#   in a cache array), at the stage's end time, `γh` the launch's step argument;
# - the operator program (the front end's `jac:` kernels, `OperatorSpec.jac`), for the rows
#   whose operator varies by site;
# - one `Solvers.FieldSolver` per row with diffusion, its inputs bound to these arrays (no
#   copy): `(I/(γh) − J̃) δ = G`, δ from 0, homogeneous face values;
#
# then the update `u_{k+1} = u_k + δ` into the other slot (masked sites take their value; the
# clip `lower` after the last iteration) and the status word. Rows (the group's fields) are
# solved in the topological order of the reads among them, each from the residual at the
# fields solved before it (exact for an acyclic group; a cycle is block Gauss–Seidel).
#
# A stage is one such solve from slot `p` into the other slot. Backward Euler takes one stage
# per substep (γ = 1); Crank–Nicolson one (γ = 1/2: the shift `2/h` of a Backward Euler step of
# `h/2`), or two Backward Euler stages of `h/2` for its damped start, with the same operator;
# BDF2 one (γ = 2/3), or one Backward Euler stage (γ = 1) at its start. QuasiSteady takes one
# stage per window with no time-step term (γh = ∞: the residual is `r(u_k)`, the shift 0) at the
# window's start time.

"""
    residual_rule(alg)

The residual of implicit algorithm `alg` for [`fuse_residual`](@ref
LatticeFields.Compile.fuse_residual): `rule(kb, c, r, cn)` from the iterate `c`, the rate `r`
and the stage's right side `cn`: `(cn − c)/(γh) + r`, `γh = G.rt[2]` (the launch's step
argument: `h` for Backward Euler, `h/2` for Crank–Nicolson, `2h/3` for BDF2). One residual for
every implicit algorithm; they differ in `cn` and `γ` (the runtime's stages).
"""
residual_rule(::AbstractImplicitFieldAlgorithm) = BERule()
struct BERule end
(::BERule)(kb, c, r, cn) = (cn - c) / Ex(kb, runtime!(kb, RT_DT)) + r
residual_key(::AbstractImplicitFieldAlgorithm) = :be
# Crank–Nicolson's right side `q = uⁿ + (h/2) r(uⁿ)` (`G.rt[2] = h/2`, the iterate `c` the
# substep's start `uⁿ`, at its start time `tⁿ`): one program for the group's rows at once
struct QRule end
(::QRule)(kb, c, r, cn) = c + Ex(kb, runtime!(kb, RT_DT)) * r
# the γ of the algorithm's shift `1/(γh)` (Backward Euler 1, Crank–Nicolson 1/2, BDF2 2/3)
_gamma(::BackwardEuler) = 1.0
_gamma(::CrankNicolson) = 0.5
_gamma(::BDF2) = 2 / 3
_gamma(::QuasiSteady) = Inf             # (no time-step term: `1/(γh) = 0`)
# … of its operator at a start (BDF2's Backward Euler substep)
_gamma_start(a::AbstractImplicitFieldAlgorithm) = _gamma(a)
_gamma_start(::BDF2) = 1.0
# … of the automatic counts (the substeps' rules 1 and 2 and the Newton count), which hold for
# every stage: BDF2 counts as its Backward Euler start
_gamma_count(a::AbstractImplicitFieldAlgorithm) = max(_gamma(a), _gamma_start(a))
_algname(a) = string(nameof(typeof(a)))

"""
    residual_program(g, alg) -> Program

The semantic residual program of group `g` for implicit algorithm `alg` (`fuse_residual` of
its rate program, once per residual key; thread-safe).
"""
residual_program(g::FieldGroup, alg::AbstractImplicitFieldAlgorithm) =
    lock(() -> get!(() -> semantic(fuse_residual(g.spec.rate, residual_rule(alg); widen16 = true)), g.programs,
        (:residual, residual_key(alg))),
        _PLANS_LOCK)
# … of Crank–Nicolson's right side (`QRule`)
_q_program(g::FieldGroup) =
    lock(() -> get!(() -> semantic(fuse_residual(g.spec.rate, QRule())), g.programs, (:residual, :q)), _PLANS_LOCK)
# the semantic operator program of `g` (`nothing`: every row numeric)
function _jac_program(g::FieldGroup, op::OperatorSpec)
    op.jac === nothing && return nothing
    return lock(() -> get!(() -> semantic(op.jac), g.programs, :jac), _PLANS_LOCK)
end
# a plan of the kernels `ids` of program `s` (cached in the group's plans by `tag`)
function _implicit_plan(g::FieldGroup, s::Program, tag, ids::Vector{Int}, ::Type{V}, backend, o::CompileOptions;
        C::Type = V) where {V}
    return lock(_PLANS_LOCK) do
        first(get!(g.plans, (tag, V, C, Int[], ids)) do
            p = plan(s, ids; options = _options(o, V, backend; clock = clock_slot(g.spec), C, s))
            (p, p)
        end)
    end
end

# The status word's update after one solve (one work item; F3 design §3.3): [4] solves, [5]
# budget hits (`done` still 0), [6] floors (`done` 2: `StalledSuccess`), and a failure
# (`done` 3, diverged; a residual that is not finite; a steady solve's budget hit with no real
# reduction) into [1] code 2, [3] its cause and [2] the window when none is recorded yet. A
# solve the device's convergence gate closed (`gate[1] ≠ 0`: done at its setup, nothing ran) is
# not counted (batch 5 review N3: the device counts the solves the host runs)
function _be_status_body!(i, w, scal, window, steady, gate)
    @inbounds begin                             # i = 1; w has 8 entries, scal SCALARS ≥ 7, gate 1
        (gate !== nothing && gate[1] != 0) && return nothing
        d, rn = scal[Solvers.DONE], scal[Solvers.RNORM]
        w[STATUS_SOLVES] += UInt32(1)
        fail = UInt32(0)
        if !isfinite(rn)
            fail = UInt32(4)
        elseif d == 0
            w[STATUS_BUDGET] += UInt32(1)
            # a steady solve that did not halve its residual (δ from 0: the setup residual is
            # ‖b‖): a singular region, F3 design §3.5 S-a
            steady && rn > scal[Solvers.BNORM] / 2 && (fail = UInt32(16))
        elseif d == 2
            w[STATUS_FLOOR] += UInt32(1)
            w[STATUS_CODE] = max(w[STATUS_CODE], UInt32(1))
            steady && rn > scal[Solvers.BNORM] / 2 && (fail = UInt32(16))     # (a stall above the tolerance, the same)
        elseif d == 3
            fail = steady ? UInt32(1 | 32) : UInt32(1)    # (a steady divergence: indefinite, or an island; r3 S2)
        end
        if fail != 0
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= fail
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
        end
    end
    return nothing
end
_zero_body!(i, a) = (@inbounds a[i] = zero(eltype(a)); nothing)      # i ≤ length(a)
_clip_body!(i, a, lower) = (@inbounds a[i] = max(a[i], lower); nothing)  # i ≤ length(a)
# BDF2's right side `q = (4uⁿ − uⁿ⁻¹)/3` (i ≤ length(q) == length(un) == length(prev))
_bdf2_q_body!(i, q, un, prev) =
    (@inbounds q[i] = (4 * un[i] - prev[i]) / 3; nothing)

# The Newton check: after each iteration's update, under `nlsolve = nothing` (automatic mode),
# the norms of the row's correction ‖δ_k‖∞, increment ‖u_k − uⁿ‖∞ and value ‖u_k‖∞ over its
# unmasked sites are reduced in `NB`-site blocks (`_be_norms_body!`), then combined
# (`_be_newton_body!`). Under `LatticeNewton(; κ, max_iter, check_div)`, `_be_kappa_norms_body!`
# and `_be_kappa_newton_body!` compute the `NLNewton` scaled RMS norm `ndz` over all active
# unknowns in the group (weighted by `abstol + reltol * max(|uⁿ|, |u_k|)` using the pre-update
# iterate `u_k = dst - δ`), damped contraction rate `θ = max(0.3 prev_θ, ndz / ndzprev)`
# carried across steps, multiplier `η = θ / (1 − θ)`, first-iteration rule `ndz < 1e-5`,
# precision-limit check, divergence test (`check_div`), and `η * ndz < κ`. When every row
# meets the tolerance, a host executor stops early and a device closes its convergence gate
# (`c.gate`, setting `δ := 0` and skipping solves). Under automatic mode, a 1-step group runs
# unchecked; under `LatticeNewton`, `max_iter = 1` runs the check.
const NB = 256
const NEWTON_EPS = 1e-3
const STATUS_CONVERGED = 8
const STATUS_CLAMP = 9                  # the first window whose shift was clamped (0: none)
# the larger of two norms; a NaN stays
_nanmax(a, b) = (isnan(b) | (b > a)) ? b : a
function _be_norms_body!(b, part, dst, un, x, smask, v, res, s, mask, n, gate)
    @inbounds begin                             # b ≤ cld(n, NB), 3b ≤ length(part); every array has n sites
        T = eltype(part)
        gated = gate !== nothing && gate[1] != 0
        dm, im, um = zero(T), zero(T), zero(T)
        for i in ((b - 1) * NB + 1):min(b * NB, n)
            (mask !== nothing && mask[i] != 0) && continue
            δ = gated ? zero(T) :
                res !== nothing ? res[i] / _at(s, i) : (v !== nothing && smask[i] != 0) ? v[i] : x[i]
            dm = _nanmax(dm, abs(T(δ)))
            im = _nanmax(im, abs(T(dst[i] - un[i])))
            um = _nanmax(um, abs(T(dst[i])))
        end
        part[3b - 2], part[3b - 1], part[3b] = dm, im, um
    end
    return nothing
end
function _be_newton_body!(i, w, part, nb, hist, it, last, epsn, fl, window, steady, nobit, checkdiv, failbudget)
    @inbounds begin                             # i = 1; 3nb ≤ length(part), hist has 3 entries, w 8
        T = eltype(part)
        dk, inc, un = zero(T), zero(T), zero(T)
        for b in 1:nb
            dk = _nanmax(dk, part[3b - 2])
            inc = _nanmax(inc, part[3b - 1])
            un = _nanmax(un, part[3b])
        end
        d1, d2 = it == 1 ? (zero(T), zero(T)) : (hist[2], hist[1])      # ‖δ_{k−1}‖, ‖δ_{k−2}‖
        fail = !isfinite(dk) ? UInt32(4) : (checkdiv && it >= 3 && dk > 2d1 && d1 > 2d2) ? UInt32(2) : UInt32(0)
        # (a steady solve has no increment over a step: the field-relative form)
        conv = steady ? dk <= (epsn + fl) * un : dk <= epsn * inc + fl * un
        it == 1 && (hist[3] = dk)
        # a steady solve's budget hit whose correction did not halve from the first: no real
        # reduction (a singular region, S-a)
        (fail == 0 && last && !conv && steady && it > 1 && !(dk < hist[3] / 2)) && (fail = nobit)
        if fail != 0
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= fail
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
        elseif last && !conv
            w[STATUS_NEWTON_BUDGET] += UInt32(1)
            if failbudget
                w[STATUS_CODE] = UInt32(2)
                w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
            end
        end
        conv && (w[STATUS_CONVERGED] += UInt32(1))      # (wraps harmlessly where no host reads it)
        hist[1], hist[2] = d1, dk
    end
    return nothing
end

# Rate-scaled NLNewton norm and check (`LatticeNewton(; κ, max_iter, check_div)`): block sums of
# `(δ_i / (abstol + max(|uⁿ_i|, |u_{k,i}|) * reltol))²` (pre-update iterate `u_k = dst − δ`)
# and active site counts, then the single-item RMS norm, θ = max(0.3 prev_θ, ndz / ndzprev),
# η = θ / (1 − θ), precision-limit check, divergence check, and `η * ndz < κ` test.
function _be_kappa_norms_body!(b, part, cnt, off, dst, un, x, smask, v, res, s, mask, dom, abstol, reltol, n, gate)
    @inbounds begin                             # b ≤ cld(n, NB), off + b ≤ length(part); every array has n sites
        T = eltype(part)
        gated = gate !== nothing && gate[1] != 0
        ssq = zero(T)
        c = UInt32(0)
        for i in ((b - 1) * NB + 1):min(b * NB, n)
            ((mask !== nothing && mask[i] != 0) || (dom !== nothing && dom[i] == 0)) && continue
            c += UInt32(1)
            if !gated
                dv = T(res !== nothing ? res[i] / _at(s, i) : (v !== nothing && smask[i] != 0) ? v[i] : x[i])
                u0 = abs(T(un[i]))
                uk = abs(T(dst[i]) - dv)
                um = _nanmax(u0, uk)
                denom = abstol + um * reltol
                r = (dv == 0 && isfinite(um)) ? zero(T) : dv / denom
                ssq += r * r
            end
        end
        part[off + b] = ssq
        cnt[off + b] = c
    end
    return nothing
end
function _be_kappa_newton_body!(
        i, w, part, cnt, nb, hist, it, last, κ, window, steady, nobit, checkdiv, failbudget, gate,
        conv_inc, ndz1_tol, damp, eps_one,
    )
    @inbounds begin                             # i = 1; nb ≤ length(part), hist has 4 entries, w 9
        if gate !== nothing && gate[1] != 0
            w[STATUS_CONVERGED] += conv_inc
            return nothing
        end
        T = eltype(part)
        ssq = zero(T)
        tot = UInt32(0)
        for b in 1:nb
            ssq += part[b]
            tot += cnt[b]
        end
        ndz = tot == 0 ? zero(T) : sqrt(ssq / T(tot))
        it == 1 && (hist[4] = ndz)
        if !isfinite(ndz)
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= UInt32(4)
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
            hist[1] = ndz
            return nothing
        end
        prev_θ = hist[2]
        ndzprev = hist[1]
        fail = UInt32(0)
        conv = false
        θ = prev_θ
        if it > 1
            ratio = (ndz == 0 && ndzprev == 0) ? zero(T) : ndz / ndzprev
            θ = prev_θ = max(damp * prev_θ, ratio)
            if abs(θ - one(T)) <= eps_one
                if ndz <= one(T)
                    conv = true
                elseif checkdiv
                    fail = UInt32(2)
                end
            elseif checkdiv && θ > T(2)
                fail = UInt32(2)
            end
        end
        η = θ / (one(T) - θ)
        if !conv && fail == 0
            if it == 1
                conv = ndz < ndz1_tol
            else
                conv = (η >= zero(T)) && (η * ndz < κ)
            end
        end
        (fail == 0 && last && !conv && steady && it > 1 && !(ndz < hist[4] / T(2))) && (fail = nobit)
        if fail != 0
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= fail
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
        elseif last && !conv
            w[STATUS_NEWTON_BUDGET] += UInt32(1)
            if failbudget
                w[STATUS_CODE] = UInt32(2)
                w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
            end
        end
        conv && (w[STATUS_CONVERGED] += conv_inc)
        hist[1] = ndz
        hist[2] = prev_θ
        hist[3] = η
    end
    return nothing
end
function _reset_hist_body!(i, hist)
    @inbounds begin                             # i = 1; hist has 4 entries
        T = eltype(hist)
        hist[1] = one(T)
        hist[2] = one(T)
        hist[3] = one(T)
        length(hist) >= 4 && (hist[4] = zero(T))
    end
    return nothing
end

# The device's convergence gate (batch 3 R1, F3-15): at each Newton iteration's start, the gate
# closes once the previous iteration's check counted every row converged (`w[8] = nrows`), and
# the count restarts; a closed gate zeroes each row's residual (`_be_gate_body!`), so the solve
# is done at its setup and the update adds 0 (the host's early stop, on the device)
function _be_gate_iter_body!(i, w, gate, nrows, first)
    @inbounds begin                             # i = 1; w has 9 entries, gate 1
        if first
            gate[1] = w[STATUS_CODE] == UInt32(2) ? UInt32(1) : UInt32(0)
        elseif w[STATUS_CONVERGED] == nrows || w[STATUS_CODE] == UInt32(2)
            gate[1] = UInt32(1)
        end
        w[STATUS_CONVERGED] = UInt32(0)
    end
    return nothing
end
_be_gate_body!(i, res, gate) = (@inbounds (gate[1] != 0 && (res[i] = zero(eltype(res)))); nothing)   # i ≤ length(res)
_at(x::Number, i) = x
_at(x::AbstractArray, i) = @inbounds x[i]                              # i ≤ length(x) (one value per site)
_at(::Nothing, i) = false

# The update of one row at site `i` (F3 design §3.3 step 5): δ from the solver's solution `x`
# (or, at a row solved on its own, the value `v`; a row with no diffusion: `res/s`), `dst =
# src + δ`; a masked site takes its value (`mval`, times its value field `mvf`), and the clip
# `lower` (or `nothing`). Every array has one value per site (i ≤ length(dst)).
function _be_update_body!(i, dst, src, x, smask, v, res, s, mask, mval, mvf, lower, clip, gate)
    @inbounds begin
        gated = gate !== nothing && gate[1] != 0
        δ = gated ? zero(eltype(dst)) :
            res !== nothing ? res[i] / _at(s, i) :
            (v !== nothing && smask[i] != 0) ? v[i] : x[i]
        u = src[i] + δ
        if mask !== nothing && mask[i] != 0
            u = mvf === nothing ? mval : mval * mvf[i]
        end
        (clip && lower !== nothing) && (u = max(u, lower))
        dst[i] = u
    end
    return nothing
end

# The shift of a row whose operator varies by site (`OperatorSpec` field mode): `s =
# max(1/(γh) − J, 1/(2γh))/m + d` (the clamp keeps the solve positive definite where the
# local Jacobian grows faster than the step: F3 design §3.4 Positivity; it sets the status
# word's cause bit 8, counted, not a failure), and the solver's mask: a masked site, a site
# outside the domain, a site with multiplier `m = 0` (solved on its own)
function _be_shift_body!(i, s, j, d, m, smask, rmask, dom, ih, ih2, w, window)
    @inbounds begin                             # (w has 9 entries: STATUS_CAUSE = 3, STATUS_CLAMP = 9)
        s0 = ih - _jat(j, i, ih)
        # (every site that clamps writes the same bit and window, and no other launch writes
        # the word meanwhile: the race is benign)
        if s0 < ih2
            w[STATUS_CAUSE] |= UInt32(8)
            w[STATUS_CLAMP] == 0 && (w[STATUS_CLAMP] = UInt32(window))
        end
        base = max(s0, ih2)
        scaled = m === nothing ? base : (m[i] > 0 ? base / m[i] : ih)
        s[i] = d === nothing ? scaled : scaled + d[i]
        if smask !== nothing
            off = (rmask !== nothing && rmask[i] != 0) || (dom !== nothing && dom[i] == 0) || (m !== nothing && !(m[i] > 0))
            smask[i] = off ? 0x01 : 0x00
        end
    end
    return nothing
end
_jat(::Nothing, i, ih) = zero(ih)
_jat(j::AbstractArray, i, ih) = @inbounds j[i]                         # i ≤ length(j)
# The right side of a scaled row (`m laplacian(c)`): `G/m` where `m > 0`, and at a row with `m = 0`
# (inside the domain, not masked) its own `δ = G/max(1/(γh) − J, 1/(2γh))` as the solver's
# mask value (the two-stage solve, M3)
function _be_rhs_body!(i, f, v, res, j, m, smask, rmask, dom, ih, ih2)
    @inbounds begin
        g = res[i]
        if smask[i] != 0
            f[i] = zero(eltype(f))
            own = !(m[i] > 0) && !(rmask !== nothing && rmask[i] != 0) && !(dom !== nothing && dom[i] == 0)
            v[i] = own ? g / max(ih - _jat(j, i, ih), ih2) : zero(eltype(v))
        else
            f[i] = g / m[i]
            v[i] = zero(eltype(v))
        end
    end
    return nothing
end

"""
One row of an implicit runtime: its residual launches per slot parity and iteration kind, its
state buffers, its solver (or `nothing`: a row with no diffusion, solved site by site) with
the arrays its solve reads and writes, and its update's mask and clip.
"""
mutable struct ImplicitRow{R, U, A, SV, X, W, SC, SM, V, S, MK, MV, MF, LO, F, J, M, D, RM, DM, P, CT, Q, H, LC, BOP}
    key::String
    res::NTuple{4, R}                   # (parity 1 first iteration, parity 2 first, parity 1 later, parity 2 later)
    bufs::NTuple{2, U}                  # the row's two state slots
    resarr::A                           # `res:c`
    solver::SV
    xs::NTuple{2, X}                    # the solver's solution array in each of its slots
    xid::Int32
    work::Vector{W}                     # the solver's working buffers (zeroed before each solve)
    scal::SC                            # the solver's scalars
    smask::SM                           # field mode: the solver's mask (cache-owned, U8) or nothing
    v::V                                # scaled rows: the solver's mask value (`δ` of an `m = 0` row)
    s::S                                # the shift: a number (numeric, or a row with no diffusion) or an array
    mask::MK                            # the row's own mask (`c ~ masked(…)`), or nothing
    mval::MV                            # … its value (a number in the state type), times
    mvf::MF                             # … its value field, or nothing
    lo::LO                              # the clip `lower` in the state type, or nothing
    f::F                                # scaled rows: the solver's right side `G/m`
    j::J                                # field mode: the local Jacobian, boundary diagonal, multiplier,
    m::M                                #   domain indicator (`jac:` arrays) or nothing
    d::D
    rmask::RM
    dom::DM
    op::RowOperator
    numeric::Union{Nothing, Solvers.CellOperator}   # the numeric operator the solver holds (numeric rows)
    part::P                             # the Newton check's block partials and
    cnt::CT                             #   active site counts per block (UInt32) and
    off::Int                            #   block offset in the group-wide LatticeNewton reduction
    hist::P                             #   history (`[d2, d1, d_first]` or `[ndzprev, prev_θ, ηold, ndz1]`)
    q::Q                                # the stage's right side `c__n` (Crank–Nicolson, BDF2), or nothing (BE: `uⁿ`)
    prev::H                             # BDF2: the state one substep back, `uⁿ⁻¹` (not in the problem's state), or nothing
    lin::LC                             # the solve as a LinearSolve cache (its `cacheval` is `solver`), or nothing
    bop::BOP                            # BoundOperator for `lin` when `solver === nothing` (for CSC/operator updates), or nothing
end
# a row's linear solve (`lift!` and the budgeted solve of its `FieldSolver`, through LinearSolve)
_solve_cache!(c) = Solvers.solve_owned!(c)

"""
    ImplicitCache

The cache of an implicit runtime (F3 design §3.3): its rows in solve order
([`ImplicitRow`](@ref)), the operator program's launches per slot parity (or `nothing`), the
Newton count, the step `h` and the `γ` the coefficients hold (the shift `1/(γh)`), the `stale`
flag (the hierarchy is rebuilt before the next stage: set at bind, by [`reset!`](@ref) and by a
change of `h` or `γ`), the `start` flag (the next substep is a start: Crank–Nicolson's damped
substep, BDF2's Backward Euler substep; set at bind, by `reset!` and by a change of `h`), the
`jumps` flag (Crank–Nicolson: the group's data can jump at every window, so the first substep
of every window is damped), the `moving` flag (the operator reads data that change every
window: it is rebuilt each window), the `timed` flag (the operator reads the time: it is
rebuilt at each stage's end time), the `iterate` flag (a row's local Jacobian reads its own
field, a local nonlinear term or a switch: that row's operator is rebuilt at every Newton
iteration, at the iterate), Crank–Nicolson's right-side launches (`qres`, per slot parity, or
nothing), the status word, the operator spec and the coupled solve (`cs`: a [`CoupledKrylov`](@ref)
when the group's rows are solved together, F3-12d; `nothing` when they are solved one by one).
"""
mutable struct ImplicitCache{RS, WK, JL, W, BK, QL, GT, CS, KT, AT, RT, GP, GC, GH}
    rows::RS
    walk::WK
    jac::JL
    newton::Int
    h::Float64
    γ::Float64                          # the γ of the operator's shift `1/(γh)` now
    stale::Bool
    start::Bool                         # the next substep is a start (damped, or Backward Euler)
    jumps::Bool                         # Crank–Nicolson: damp the first substep of every window
    moving::Bool
    timed::Bool                         # the operator reads the time: rebuilt at every stage's end time
    word::W
    op::OperatorSpec
    exact0::Bool                        # the operator is exact apart from the Robin faces' signs
    exact::Bool                         # … and every Robin face's diagonal is positive at the parameters
    iterate::Bool                       # a row's operator reads its iterate: rebuilt every Newton iteration
    check::Bool                         # the Newton check runs (more than one iteration)
    flip::Bool                          # the automatic count of an exact switch group: its second
                                        #   iteration is a flip pass, not a convergence test (no budget hit)
    auto::Bool                          # `nlsolve === nothing`: automatic count and criterion
    check_div::Bool                     # abort on Newton divergence growth (`LatticeNewton(; check_div)`)
    fail_budget::Bool                   # end run with `ConvergenceFailure` on Newton budget hit (`LatticeNewton`)
    κ::KT                               # `NLNewton` rate-scaled convergence threshold (`LatticeNewton(; κ)`)
    abstol::AT                          # `NLNewton` absolute tolerance from solve keywords
    reltol::RT                          # `NLNewton` relative tolerance from solve keywords
    switch::Bool
    seen::Bool                          # every term out of the operator has a bound
    ρin::Float64                        # … their bound `ρ_adv + κ_in + ρ_rob` at the bound parameters
    θ::Float64                          # … the face-wise ratio of the diffusion left out of a scaled row (R2-M1)
    smin::Float64                       # the smallest shift the operator keeps with no time-step term (the
                                        #   decay; NaN when a row varies by site): QuasiSteady's count
    keys::Vector{String}
    cyclic::Bool
    rebuilds::Int                       # hierarchy rebuilds so far (a test reads it)
    rebind::Any                         # `p -> (residual launches per row, operator launches, q launches)` (a rebind)
    backend::BK
    qres::QL                            # Crank–Nicolson's right-side launches per slot parity, or nothing
    gate::GT                            # a device's convergence gate (batch 3 R1, F3-15), or nothing
    cs::CS                              # the coupled solve (F3-12d, `CoupledKrylov`), or nothing: row by row
    gpart::GP                           # group-wide LatticeNewton partials, block counts, history, block count
    gcnt::GC
    ghist::GH
    gnbt::Int
end
status_word(c::ImplicitCache) = c.word
newton_count(c::ImplicitCache) = c.newton
function reset_cache!(c::ImplicitCache)
    c.stale = true
    c.start = true
    if !c.auto
        for r in c.rows
            Exec.launch!(c.backend, _reset_hist_body!, 1, (r.hist,))
        end
        c.ghist === nothing || Exec.launch!(c.backend, _reset_hist_body!, 1, (c.ghist,))
        c.cs === nothing || Exec.launch!(c.backend, _reset_hist_body!, 1, (c.cs.hist,))
    end
    return nothing
end
step_retcode!(::ImplicitCache, rt) = SciMLBase.ReturnCode.Success   # (the status word carries the code)

"""
    bind_cache(alg, group, store, p; fields, n, dt, c, backend, options, V) -> cache

The algorithm's cache bound to `store` at parameters `p` (`alg_cache` for the explicit
algorithms; an [`ImplicitCache`](@ref) for the implicit ones).
"""
bind_cache(alg, g, st, p; kw...) = alg_cache(alg, g, st)

# the work type of a row's arrays (a lowered float type for the solver), with the refusal of
# the others (FE-26, R-F3f). A field stored in Float16 is solved in the state's value type `V`
# (its residual is held there, `fuse_residual(…; widen16)`; each update rounds once to the
# storage, batch 5 review S1)
function _implicit_eltype(u, key, alg, V)
    T = eltype(u)
    T === Float16 && V in (Float32, Float64) && return V
    T in (Float32, Float64) && return T
    T === Float16 && throw(ArgumentError(string(_algname(alg), ": the field `", key, "` holds Float16 and the problem's ",
        "value type is Float16; an implicit solve runs in Float32 or Float64: give the problem T = Float32 and the ",
        "field `lattice_storage = Float16` (it is then solved in Float32, each update rounded to Float16), or step it ",
        "with `ExplicitEuler`")))
    throw(ArgumentError(string(_algname(alg), ": the field `", key, "` holds ", _typetext(T), "; an implicit solve runs in ",
        "Float32 or Float64 (BigFloat through the implicit solve is planned after the paper, FE-26). ",
        "Give the field `lattice_storage = Float32` or Float64, or step it with `ExplicitEuler`")))
end
# a number type in messages: a ForwardDiff Dual by its value type, not its full tag (batch 5 review S4)
_typetext(T::Type) = (T <: Real && T !== value_type(T)) ? string("ForwardDiff Duals of ", value_type(T)) : string(T)

# the face conditions of field `id` of program `s` on axis `a` side `k` (1 low, 2 high), at
# parameters `p`, in the solver's homogeneous form: `(:none,)`, `(:dirichlet,)`,
# `(:robin, α, β)` (lattice units) or `(:site,)`, a Robin face whose α or β varies by site or in
# time (F4-12b: its row's `sitefaces` bound its diagonal)
function _face_kind(s::Program, id, a, k, p)
    r = findfirst(x -> x isa FaceRule && x.field == id && x.axis == a && x.side == (k == 1 ? -1 : 1), s.rules)
    r === nothing && return (:none, 0.0, 0.0)
    f = s.rules[r]::FaceRule
    sitecoefs(f) && return (:site, NaN, NaN)
    α, β = _coefval(f.alpha, p), _coefval(f.beta, p)
    α == 0 && return (:none, 0.0, 0.0)
    β == 0 && return (:dirichlet, α, 0.0)
    return (:robin, α, β)
end

# the numeric operator of a row at parameters `p` and step `h`: faces, shift, face conditions
# (homogeneous: δ has zero boundary data), the row's mask with value 0 (its update writes the
# value). Whether the shift was clamped (a growth the count rule did not cover) is returned too.
# `coupled`: the row is a block of a coupled solve's preconditioner (F3-12d); a steady row with
# no positive shift then takes its local block's size `|J_loc| + Σ |cross coefficients|`, so the
# block is not singular where the coupling, not the row, sets the steady state (a growth or no
# decay that the coupling damps)
function _numeric_operator(s::Program{N}, r::RowOperator, id, p, h, γ, mask::Bool; coupled::Bool = false) where {N}
    dims = Tuple(Int.(leveldims(s, s.fields[id].levels[1])))      # (a `Coarse` field's grid, F3-16)
    # (a hexagonal lattice: three face directions, F3-20)
    face = _ishex(s) ? ntuple(a -> _coefsum(r.faces[a], p), 3) : ntuple(a -> _coefsum(r.faces[a], p), N)
    ih = 1 / (γ * h)
    s0 = ih - _coefsum(r.jloc, p)
    shift = max(s0, ih / 2)
    if coupled && isinf(γ * h) && !(s0 > 0)
        shift = abs(s0) + sum((abs(_coefsum(Coef[c], p)) for (_, c, _) in r.cross if !isnan(c.value)); init = 0.0)
    end
    dir = ntuple(a -> s.periodic[a] ? (nothing, nothing) :
                      ntuple(k -> _face_kind(s, id, a, k, p)[1] === :dirichlet ? 0.0 : nothing, 2), N)
    rob = ntuple(a -> s.periodic[a] ? (nothing, nothing) :
                      ntuple(k -> (f = _face_kind(s, id, a, k, p); f[1] === :robin ? (f[2], f[3], 0.0) : nothing), 2), N)
    # a steady solve (γh = ∞) takes a Robin face's negative part into its operator too: with no
    # time-step shift to keep dominant, it stays symmetric and exact (batch 4 review r3 S1)
    op = Solvers.CellOperator(dims; periodic = s.periodic, face, shift, mask = mask ? "mask" : nothing, value = 0.0,
        dirichlet = dir, robin = rob, name = r.key, robin_full = isinf(γ * h), hex = _ishex(s))
    return op, shift > s0
end
# the parameters the bounds of `inexact_bounds` and `_robin_bounds` read: with the store's
# tables when a row has a bound that may read them (`bounds`, `facemax`), else `p` itself (no copy)
function _bound_params(st::FieldStore, s::Program, op::OperatorSpec, keys, p)
    isempty(s.tables) && return p
    any(r -> r.key in keys && (!isempty(r.bounds) || r.facemax !== nothing || r.jmax !== nothing ||
                               any(c -> !(c isa Coef), r.adv)), op.rows) || return p
    return ParamsTables(p, Pair{String, Vector{Float64}}[s.tables[j].key => _primal64(Array(st.tables[j])) for j in eachindex(s.tables)])
end
# the rows whose Robin faces' negative part stays out of the operator: every row of a time
# stepper; a steady solve takes it into a numeric row's operator (`robin_full`), so only its
# field rows (whose operator varies by site) keep the defect correction
_robin_keys(alg, op::OperatorSpec, keys) = alg isa QuasiSteady ? String[r.key for r in op.rows if r.key in keys && r.field] : keys
# The Robin faces with a negative diagonal of the rows `keys` at `p` (their part `w_a d⁻` stays
# out of the operator: a defect correction, S1): whether there is one (`neg`), the bound of the
# part left out, `ρ = Σ_a max_side w_a |d⁻|` (`w_a` the row's face coefficient `K/h_a²`; a
# field row's largest over the sites, `facemax`, R2-S1), and the faces no bound sees
# (`unseen`, with their texts: a field row whose face coefficient has no interval bound)
function _robin_bounds(s::Program{N}, op::OperatorSpec, keys, p) where {N}
    neg, ρ = false, 0.0
    texts = String[]
    for r in op.rows
        r.key in keys || continue
        id = fieldid(s, r.key)
        q = 0.0
        fm = nothing
        for a in 1:N
            m = 0.0
            for k in 1:2
                f = _face_kind(s, id, a, k, p)
                f[1] in (:robin, :site) || continue
                # (a face that varies by site: its smallest diagonal over the sites, F4-12b)
                dm = f[1] === :robin ? Solvers.robin_parts(f[2], f[3], 0.0)[2] : min(_site_dmin(r, a, k, p), 0.0)
                (dm < 0 || isnan(dm)) || continue
                neg = true
                if r.field
                    r.facemax !== nothing && fm === nothing && (fm = r.facemax(p))
                    w = fm === nothing ? NaN : Float64(fm[a])
                    isfinite(w * dm) ? (m = max(m, w * abs(dm))) :
                    push!(texts, string("the Robin face of `", r.key, "` on axis ", a, " (", k == 1 ? "low" : "high",
                        " side), whose diagonal ", isnan(dm) ? "may be negative at some site" : "is negative", " at these parameters,"))
                else
                    m = max(m, abs(_coefsum(r.faces[a], p)) * abs(dm))
                end
            end
            q += _ishex(s) ? 2m : m            # (a hexagonal site has up to two links through one face)
        end
        ρ = max(ρ, q)
    end
    return (; neg, ρ, unseen = !isempty(texts), texts)
end

# the smallest ghost diagonal of row `r`'s face (axis `a`, side `k`) whose α or β varies by site
# or in time, over its sites at parameters `p` (NaN when no bound: F4-12b)
function _site_dmin(r::RowOperator, a, k, p)
    j = findfirst(x -> x[1] == a && x[2] == k, r.sitefaces)
    j === nothing && return NaN
    return Float64(r.sitefaces[j][3](p)[1])
end

# the fields kernel `i` of `s` reads, through the `aux:` kernels of the aux fields it reads (an
# aux field is evaluated from its own reads in the row's residual, so the row depends on them:
# `0.5 L` with `L ~ laplacian(c)` reads `c`, F3-22)
function _reads_through_aux(s::Program, i)
    out, todo, seen = Int32[], Int[i], Set{Int}()
    while !isempty(todo)
        j = pop!(todo)
        j in seen && continue
        push!(seen, j)
        for a in s.kernels[j].accesses
            push!(out, a.field)
            m = findfirst(x -> x.key == "aux:" * s.fields[a.field].key, s.kernels)
            m === nothing || push!(todo, m)
        end
    end
    return unique!(out)
end
# the fields of the group `keys` each row reads (its `rate:` kernel in the stepped program `s`)
function _group_deps(s::Program, keys)
    ids = Dict(k => fieldid(s, k) for k in keys)
    deps = Dict{String, Set{String}}()
    for k in keys
        i = findfirst(x -> x.key == "rate:" * k, s.kernels)
        rd = i === nothing ? Int32[] : _reads_through_aux(s, i)
        deps[k] = Set(q for q in keys if q != k && ids[q] in rd)
    end
    return deps
end
# the rows of the group's fields `keys` in solve order: topological in the reads among them
# (the `rate:` kernels of the stepped program `s`), cycles in state order
function _solve_order(s::Program, keys::Vector{String})
    deps = _group_deps(s, keys)
    out, left = String[], copy(keys)
    while !isempty(left)
        j = findfirst(k -> all(d -> d in out, deps[k]), left)
        j === nothing && (j = 1)                # a cycle: the next in state order (Gauss–Seidel)
        push!(out, popat!(left, j))
    end
    cyclic = any(k -> any(d -> findfirst(==(d), out) > findfirst(==(k), out), deps[k]), out)
    return out, cyclic
end

# the store of program `prog` whose fields alias the arrays of `st` (the stepped program `s`)
# by id up to `length(s.fields)` and by key after it: `res:c` gets its own array, `c__n` the
# two slots of `c`, and the operator program's `jac:` outputs come from `own`
function _alias_store(st::FieldStore, s::Program, prog::Program; own = Dict{String, Vector{Any}}(), byid::Bool, V = nothing)
    bufs = Vector{Vector{Any}}(undef, length(prog.fields))
    for (i, f) in enumerate(prog.fields)
        j = byid && i <= length(s.fields) ? i : findfirst(x -> x.key == f.key, s.fields)
        if j !== nothing
            bufs[i] = st.bufs[j]
        elseif haskey(own, f.key)
            bufs[i] = own[f.key]
        elseif endswith(f.key, "__n") && (c = findfirst(x -> x.key == f.key[1:(end - 3)], s.fields)) !== nothing
            bufs[i] = st.bufs[c]
        elseif startswith(f.key, "res:")
            u = st.bufs[fieldid(s, f.key[5:end])][1]
            # (a widened residual of a Float16 field, `fuse_residual(…; widen16)`: the value type)
            E = eltype(u) === Float16 && f.storage != F16 && V !== nothing ? V : eltype(u)
            bufs[i] = Any[_zeros(st.backend, E, length(u))]
        else
            throw(ArgumentError("the implicit program's field `$(f.key)` has no array in the group's store"))
        end
    end
    tables = Any[(j = findfirst(x -> x.key == t.key, s.tables); j === nothing ? _zeros(st.backend, Float64, 1) : st.tables[j])
                 for t in prog.tables]
    return FieldStore(st.backend, bufs, ones(Int, length(bufs)), tables)
end

# the kernels of the residual program for row `key`: its `rate:` kernel and every kernel that
# writes no state field and no residual (aux fields and face values, read by the rate), never
# the masks (they run at the window's start)
function _row_kernels(rs::Program, key, init)
    st = Set(i for (i, f) in enumerate(rs.fields) if f.buffers == 2)
    out = Int[]
    for (i, k) in enumerate(rs.kernels)
        k.key in init && continue
        w = writes(k)
        k.key == "rate:" * key || (!any(f -> f in st || startswith(rs.fields[f].key, "res:"), w) &&
                                   !startswith(k.key, "rate:")) || continue
        push!(out, i)
    end
    return out
end

# The `ImplicitCache` of the implicit algorithm `alg` for the fields `fields` of group `g` on
# store `st` at raw parameters `p`, `n` substeps of `dt / n`
function bind_cache(
        alg::AbstractImplicitFieldAlgorithm, g::FieldGroup, st::FieldStore, p; fields, n, dt, c, backend, options, V,
        shared = nothing, abstol = 1 // 10^6, reltol = 1 // 10^3
    )
    s = group_program(g, alg)                       # the stepped program: the store's
    # a state with derivative parts (Dual parameters or a Dual start): the primal solve on a
    # primal copy of the store, and the tangent steps after it (F3-21a; behind a barrier: a
    # primal run compiles none of it)
    any(k -> npartials(eltype(st.bufs[fieldid(s, k)][1])) > 0, fields) &&
        return Base.inferencebarrier(_bind_tangent)(alg, g, st, p; fields, n, dt, c, backend, options, V, shared, abstol, reltol)
    op = _operator(g.spec, alg)
    rs = residual_program(g, alg)
    keys = collect(String, fields)
    order, cyclic = _solve_order(s, keys)
    # a coupled solve (F3-12d): the rows solved together, each Newton iteration's residuals all
    # at the iterate (no row solved before another)
    coupled = coupled_solve(alg, op, s, keys)
    swaps = Set(fieldid(s, k) for k in keys)
    all_state = issubset(Set(fieldid(s, k) for k in g.spec.state), swaps)
    γ = _gamma_start(alg)                           # the operator's γ at the first substep
    h = n == 0 ? Float64(dt) : Float64(dt) / n
    hγ = γ * h
    # the operator program, bound to the store and to the `jac:` outputs it owns
    jp = _jac_program(g, op)
    own = Dict{String, Vector{Any}}()
    jac = nothing
    if jp !== nothing
        for f in jp.fields
            startswith(f.key, "jac:") || continue
            own[f.key] = Any[_zeros(st.backend, juliatype(f.storage) === UInt8 ? UInt8 : _eltype(f.storage, withvaltype(eltype(st.bufs[fieldid(s, keys[1])][1]), V), f.fixed), nsites(jp, f.levels[1]))]
        end
        jst = _alias_store(st, s, jp; own, byid = false)
        jids = collect(eachindex(jp.kernels))
        jplan = _implicit_plan(g, jp, :jac, jids, V, backend, options; C = compute_type(alg, V))
        # per slot parity and Newton iteration (first: the iterate is the substep's start, slot
        # `par`; later: the other slot), as the residual's
        jcur(par, first) = [(k = findfirst(x -> x.key == f.key, s.fields)) === nothing ? 1 :
                            k in swaps ? (first ? par : 3 - par) : st.cur[k] for f in jp.fields]
        jcurs = (jcur(1, true), jcur(2, true), jcur(1, false), jcur(2, false))
        mkjac = q -> ntuple(i -> BoundStep(backend, jp, jplan, jst, q; cur = jcurs[i], c), 4)
        jac = mkjac(p)
    end
    # the stage's right side: Backward Euler's is the substep's start (`c__n` bound to the
    # state's slots); Crank–Nicolson's and BDF2's a cache array per row (`c__n` bound to it)
    qs = Dict{String, Any}()
    if alg isa Union{CrankNicolson, BDF2}
        for k in keys
            u = st.bufs[fieldid(s, k)][1]
            qs[k] = _zeros(st.backend, eltype(u), length(u))
        end
    end
    qown = Dict{String, Vector{Any}}(k * "__n" => Any[q, q] for (k, q) in qs)
    # the residual store: the stepped program's arrays by id, the residuals and the histories
    rst = _alias_store(st, s, rs; own = qown, byid = true, V)
    rows = Any[]
    mkres = Any[]
    sps, rcurss = Any[], Any[]
    exact = !cyclic
    # the current slots of a launch of the residual program `prog` for a row solved after the
    # rows `before`, at slot parity `par` (the first Newton iteration: the iterate is the stage's
    # start, slot `par`, for the rows not solved yet; later, the other slot)
    function rcur(prog, before, par, first)
        cur = ones(Int, length(prog.fields))
        for (i, f) in enumerate(prog.fields)
            if i <= length(s.fields)
                cur[i] = i in swaps ? (first && !(i in before) ? par : 3 - par) : (all_state ? par : st.cur[i])
            elseif endswith(f.key, "__n")
                cur[i] = par
            end
        end
        return cur
    end
    goff = 0
    for (ri, key) in enumerate(order)
        r = op.rows[findfirst(x -> x.key == key, op.rows)]
        exact &= r.exact
        id = fieldid(s, key)
        u = st.bufs[id]
        T = _implicit_eltype(u[1], key, alg, V)
        sp = _implicit_plan(g, rs, (:residual, residual_key(alg), key), _row_kernels(rs, key, g.spec.init), V, backend, options; C = compute_type(alg, V))
        before = coupled ? Set{Int}() : Set(fieldid(s, q) for q in order[1:(ri - 1)])
        rcurs = (rcur(rs, before, 1, true), rcur(rs, before, 2, true), rcur(rs, before, 1, false), rcur(rs, before, 2, false))
        push!(sps, sp)
        push!(rcurss, rcurs)
        mk = q -> ntuple(i -> BoundStep(backend, rs, sp, rst, q; cur = rcurs[i], c), 4)
        push!(mkres, mk)
        res = mk(p)
        resarr = rst.bufs[fieldid(rs, "res:" * key)][1]
        # the row's own mask (`c ~ masked(pred, v)`) and its value
        nv = findfirst(x -> x isa NodeValueRule && x.field == id, s.rules)
        mask = nv === nothing ? nothing : array(st, s.masks[s.rules[nv].mask].field, :cur)
        mval = nv === nothing ? zero(T) : T(_coefval(s.rules[nv].value, p))
        mvf = nv === nothing || s.rules[nv].vfield == 0 ? nothing : array(st, s.rules[nv].vfield, :cur)
        lo = alg.lower_bound === nothing ? nothing : T(alg.lower_bound)
        jarr(k) = haskey(own, "jac:$key.$k") ? own["jac:$key.$k"][1] : nothing
        nsite = length(u[1])
        nb = cld(nsite, NB)
        row_off = goff
        goff += nb
        part, cnt, hist = _zeros(st.backend, T, 3 * nb), _zeros(st.backend, UInt32, nb), _zeros(st.backend, T, 4)
        alg.nlsolve === nothing || Exec.launch!(backend, _reset_hist_body!, 1, (hist,))
        q = get(qs, key, nothing)
        prev = alg isa BDF2 ? _zeros(st.backend, T, nsite) : nothing
        if r.local_only
            sv, numeric = nothing, nothing
            sh = r.field ? _zeros(st.backend, T, nsite) : T(max(1 / hγ - _coefsum(r.jloc, p), 1 / (2hγ)))
            row = ImplicitRow(key, res, (u[1], u[2]), resarr, nothing, (u[1], u[1]), Int32(0), typeof(u[1])[], nothing,
                nothing, nothing, sh, mask, mval, mvf, lo, nothing, jarr("j"), nothing, nothing, nothing, r.field && r.domain ? jarr("dom") : nothing,
                r, nothing, part, cnt, row_off, hist, q, prev, nothing, nothing
            )
            push!(rows, row)
            continue
        end
        inner = _row_inner(alg, coupled)
        solver_type = (alg.solver_type === :auto && !(inner isa LinearSolve.SciMLLinearSolveAlgorithm && LinearSolve.needs_concrete_A(inner))) ? T : alg.solver_type
        if !r.field
            numeric, _ = _numeric_operator(s, r, id, p, hγ, 1.0, mask !== nothing; coupled)
            ins = mask === nothing ? ("in.f" => resarr,) : ("in.f" => resarr, "mask" => mask)
            lin, bop = Solvers.bound_field_cache(backend, numeric, inner; T, solver_type, inputs = ins)
            smask, v, f, sh, jj, mm, dd, dm = nothing, nothing, nothing, numeric.shift, nothing, nothing, nothing, nothing
        else
            numeric = nothing
            N = length(s.periodic)
            dims = Tuple(Int.(leveldims(s, s.fields[id].levels[1])))
            sh = _zeros(st.backend, T, nsite)
            usemask = mask !== nothing || r.domain || r.scaled
            smask = usemask ? _zeros(st.backend, UInt8, nsite) : nothing
            v = r.scaled ? _zeros(st.backend, T, nsite) : nothing
            f = r.scaled ? _zeros(st.backend, T, nsite) : nothing
            jj, mm, dd, dm = jarr("j"), r.scaled ? jarr("m") : nothing, jarr("d"), r.domain ? jarr("dom") : nothing
            nf = _ishex(s) ? 3 : N                   # (a hexagonal lattice: three face directions, F3-20)
            cop = Solvers.CellOperator(dims; periodic = s.periodic, face = ntuple(a -> "w$a", nf), shift = "s",
                mask = usemask ? "mask" : nothing, value = r.scaled ? "v" : 0.0, name = key, hex = _ishex(s))
            ins = Any["in.f" => (r.scaled ? f : resarr), "s" => sh]
            for a in 1:nf
                push!(ins, "w$a" => jarr("w$a"))
            end
            usemask && push!(ins, "mask" => smask)
            r.scaled && push!(ins, "v" => v)
            lin, bop = Solvers.bound_field_cache(backend, cop, inner; T, solver_type, inputs = Tuple(ins))
        end
        cv = lin.cacheval
        if cv isa Solvers.FieldSolver
            sv = cv
            xid = Solvers.fid(sv, Solvers.solution_key(sv))
            xb = sv.bufs[xid]
            wid = Solvers.fid(sv, Solvers.working_key(sv))
            work = [w for w in sv.bufs[wid]]
            scal = sv.tables[Solvers.tid(sv, "solve.scal")]
            xs = (xb[1], xb[end])
            row_bop = nothing
        else
            sv = nothing
            xid = Int32(0)
            work = typeof(u[1])[]
            scal = nothing
            xs = (lin.u, lin.u)
            row_bop = bop
        end
        row = ImplicitRow(
            key, res, (u[1], u[2]), resarr, sv, xs, xid, work,
            scal, smask, v, sh, mask, mval, mvf, lo, f, jj, mm, dd, mask, dm, r, numeric,
            part, cnt, row_off, hist, q, prev, lin, row_bop
        )
        push!(rows, row)
    end
    # Crank–Nicolson's right side `uⁿ + (h/2) r(uⁿ)` of every row at once, from the substep's
    # start (every row at slot `par`) at its start time; its `res:c` are the rows' `q` arrays
    qres, mkq = nothing, q -> nothing
    if alg isa CrankNicolson
        qp = _q_program(g)
        qst = _alias_store(st, s, qp; own = Dict{String, Vector{Any}}("res:" * k => Any[q] for (k, q) in qs), byid = true)
        qids = sort!(unique!(reduce(vcat, (_row_kernels(qp, k, g.spec.init) for k in keys); init = Int[])))
        qplan = _implicit_plan(g, qp, (:residual, :q, keys), qids, V, backend, options; C = compute_type(alg, V))
        qcurs = (rcur(qp, Set{Int}(), 1, true), rcur(qp, Set{Int}(), 2, true))
        mkq = q -> ntuple(i -> BoundStep(backend, qp, qplan, qst, q; cur = qcurs[i], c), 2)
        qres = mkq(p)
    end
    # a Robin face with a negative diagonal leaves its part out of the operator (a defect
    # correction): the classification at `p` (again at each rebind, `install_launches!`)
    exact0 = exact
    switch = any(r -> r.op.switch, rows)
    bp = _bound_params(st, s, op, keys, p)
    b, rb = inexact_bounds(op, keys, cyclic, bp), _robin_bounds(s, op, _robin_keys(alg, op, keys), bp)
    sb = _sign_bounds(op, keys, bp)
    exact = exact0 && !rb.neg && !sb.neg
    seen = isempty(b.unseen) && !rb.unseen && !sb.neg
    ρin = b.ρ + b.κ + rb.ρ
    auto_newton = alg.nlsolve === nothing
    check_div = alg.nlsolve === nothing ? true : alg.nlsolve.check_div
    fail_budget = !auto_newton && check_div
    κ = alg.nlsolve === nothing ? (1 // 100) : alg.nlsolve.κ
    # (a coupled solve takes every term into its operator: no term is unseen)
    coupled || exact || seen || !auto_newton || _warn_unseen(keys, [b.unseen; rb.texts], alg)
    coupled || _warn_antidiffusion(keys, sb.texts, alg)
    iterate = any(r -> r.op.iterate, rows)
    smin = _steady_shift(op, keys, p)
    # (behind a barrier: a group that is not coupled compiles none of it, r1 M1)
    cs = coupled ? Base.inferencebarrier(_bind_coupled)(
            rows, _krylov(alg.linsolve), st, s, rs, rst, sps, rcurss, swaps, keys,
            g.spec.init, backend, p, c, op, alg, auto_newton
        ) : nothing
    newton = auto_newton ? (
            coupled ? _coupled_newton(alg, cs.linear, switch) :
            _auto_newton(alg, exact, switch, iterate, seen, ρin, h, b.θ, smin)
        ) : alg.nlsolve.max_iter::Int
    check = !auto_newton || newton > 1
    if !coupled && !auto_newton
        if length(rows) == 1
            gpart, gcnt, ghist, gnbt = rows[1].part, rows[1].cnt, rows[1].hist, cld(length(rows[1].bufs[1]), NB)
        else
            KT = mapreduce(r -> eltype(r.part), promote_type, rows)
            gnbt = goff
            gpart, gcnt, ghist = _zeros(st.backend, KT, gnbt), _zeros(st.backend, UInt32, gnbt), _zeros(st.backend, KT, 4)
            Exec.launch!(backend, _reset_hist_body!, 1, (ghist,))
        end
    else
        gpart, gcnt, ghist, gnbt = nothing, nothing, nothing, 0
    end
    # the operator moves when it reads the time, the clock, a filled input or a field of the state
    # (rebuilt each window), or the solver reads a mask that moves
    moving = _jac_moving(jp, g.spec) || any(r -> r.mask !== nothing || r.dom !== nothing, rows) && _masks_moving(s, g.spec)
    # Crank–Nicolson damps every window when the group's data can jump between windows
    jumps = alg isa CrankNicolson && _jumps(s, rs, keys, g.spec, any(r -> r.mask !== nothing || r.dom !== nothing, rows))
    word = _zeros(st.backend, UInt32, 9)
    rt = Tuple(rows)
    mkjac0 = jp === nothing ? (q -> nothing) : mkjac
    rebind = q -> ([m(q) for m in mkres], mkjac0(q), mkq(q), cs === nothing ? nothing : cs.mkpres(q))
    timed = jp !== nothing && _reads_time(jp)
    # the device's convergence gate: once every row met the Newton tolerance, later iterations'
    # residuals are zeroed, their solves are skipped/done at setup, and the update adds 0 (including
    # Robin-defect rows and generic-path rows), so the field is the host's early-stop form.
    gate = !Exec.ishost(backend) && (newton > 1 || check) ? _zeros(st.backend, UInt32, 1) : nothing
    cache = ImplicitCache(rt, each(length(rt)), jac, newton, h, γ, true, true, jumps, moving, timed, word, op, exact0, exact,
        iterate, check, _flips(alg, exact, switch), auto_newton, check_div, fail_budget, κ, abstol, reltol, switch, seen, ρin, b.θ, smin, keys,
        cyclic, 0, rebind, backend, qres, gate, cs, gpart, gcnt, ghist, gnbt
    )
    # a growing mode that the constant-coefficient check cannot see (r1 M2)
    cs === nothing || Base.inferencebarrier(_check_growth)(cs, alg, s, op, keys, p)
    return cache
end

# whether program `s` lives on a hexagonal lattice (its operator has three face directions, F3-20)
_ishex(s::Program) = s.hierarchy[1].grid.geometry == HEX
# the operator of `spec` for algorithm `alg`: a front end's refusal (a map) names the algorithm
function _operator(spec::GroupSpec, alg)
    try
        return operator_spec(spec)
    catch e
        e isa ArgumentError || rethrow()
        throw(ArgumentError(string(_algname(alg), ": ", e.msg)))
    end
end

# whether the data of a Crank–Nicolson group can jump between its windows (F3 design §3.3): its
# residual kernels (the rows' `rate:` kernels and the aux kernels they read) load an input the
# CPM fills, a field of another group or the clock's step index, or it has a mask (a row's own,
# or the domain's) that moves
function _jumps(s::Program, rs::Program, keys, spec::GroupSpec, masked::Bool)
    masked && _masks_moving(s, spec) && return true
    ks = [rs.kernels[i] for k in keys for i in _row_kernels(rs, k, spec.init)]
    filled = Set(i.key for i in spec.inputs if i.filled)
    others = Set(k for k in [spec.state; spec.external] if !(k in keys))
    cs = clock_slot(spec)
    for k in ks, n in k.nodes
        n.op == PARAM && cs != 0 && n.imm == cs && return true
        n.op == LOAD || continue
        f = rs.fields[k.accesses[n.imm].field]
        (f.key in filled || f.key in others) && return true
    end
    return false
end

# The automatic Newton count (`nlsolve = nothing` or `max_iter = nothing`, F3 design §3.4): 1 for an exact operator, 2 with a
# switch (one flip pass, S1); a defect correction whose terms have bounds takes
# `clamp(⌈log ε_N / log ρ_c⌉ + [θ > 0], 2, cap)` from its contraction `ρ_c = γ h ρ_in + θ` (`θ`
# the face-wise ratio of the diffusion left out of a scaled row, which no step size changes,
# R2-M1; with `θ > 0` one more iteration, since the ratio bound is close to the actual
# contraction and the Newton check measures the last correction against the step:
# `θ^(k−1) ≤ ε_N`), else 4. The cap: rule 2 keeps `γ h ρ_in ≤ (1 − θ)/2`, so `ρ_c ≤ (1 + θ)/2`:
# at most 1/2 with no left-out diffusion (k ≤ 10, cap 12), at most 3/4 with one
# (`⌈log 1e-3 / log ¾⌉ + 1 = 26`, cap 26: a lower cap could not meet ε_N where both bounds are
# tight, batch 3 review r3 N3). Raising the cap, not the substeps, keeps the cost bounded: the
# alternative rule `n ≥ ⌈2γ dt ρ / (1 − 2θ)⌉` grows without bound as θ → 1/2, while the cap
# costs at most 26 iterations, only where a left-out diffusion and another out-of-operator
# term meet, and a host executor stops once the tolerance holds.
const NEWTON_CAP = 12
const NEWTON_CAP_THETA = 26
# the automatic Newton count of `alg`: the time steppers' contraction count. A steady solve has
# no `1/(γh)` term to bound the contraction: one iteration for a linear exact group; at least
# `QS_NEWTON` with nonlinear or switched rows; with terms out of the operator, the count from
# their contraction bound `ρ̂ = ρ_in / s_min + θ` (`s_min` the smallest shift the operator
# keeps: the decay), `clamp(⌈log ε_N / log ρ̂⌉ + 1, QS_NEWTON, QS_NEWTON_CAP)`, and the cap
# when `ρ̂ ≥ 1` or no bound sees a term (F3 design §3.5; batch 4 review r2 S1). Each is checked
# on the device; a host executor stops at the tolerance.
const QS_NEWTON = 8
const QS_NEWTON_CAP = 40
_auto_newton(alg::AbstractImplicitFieldAlgorithm, exact, switch, iterate, seen, ρin, h, θ, smin) =
    _newton_count(exact, switch, seen, ρin, _gamma_count(alg), h, θ)
function _auto_newton(::QuasiSteady, exact, switch, iterate, seen, ρin, h, θ, smin)
    exact && return switch || iterate ? QS_NEWTON : 1
    seen || return QS_NEWTON_CAP
    ρ = ρin == 0 ? θ : smin > 0 ? ρin / smin + θ : Inf
    ρ < 1 || return QS_NEWTON_CAP
    return clamp(ceil(Int, log(NEWTON_EPS) / log(ρ)) + 1, QS_NEWTON, QS_NEWTON_CAP)
end
# the automatic Newton count of a coupled solve (F3-12d): its operator is the whole Jacobian, so
# a group linear in its state takes 1 (the solve is the step, or the steady state); a nonlinear
# steady group the checked `QS_NEWTON` (8; a host executor stops at the tolerance); a nonlinear
# time stepper 1, 2 with a switch (one Newton step with the exact Jacobian keeps the method's
# order, as the local nonlinear rows of the per-row path)
_coupled_newton(::QuasiSteady, linear::Bool, switch::Bool) = linear ? 1 : QS_NEWTON
# the smallest shift the operator of the rows `keys` keeps with no time-step term at `p` (the
# decay `−J_loc`); NaN when a row's operator varies by site (no number bounds it)
_steady_shift(op::OperatorSpec, keys, p) =
    minimum((r.field ? NaN : max(-_coefsum(r.jloc, p), 0.0) for r in op.rows if r.key in keys); init = Inf)
# whether the automatic count's second iteration is a switch's flip pass (no budget hit): the
# time steppers' exact switch groups; a steady solve's iterations are all checked
_flips(alg::AbstractImplicitFieldAlgorithm, exact, switch) =
    (alg.nlsolve === nothing) && exact && switch
_flips(::QuasiSteady, exact, switch) = false
function _newton_count(exact::Bool, switch::Bool, seen::Bool, ρin::Float64, γ::Float64, h::Float64, θ::Float64 = 0.0)
    exact && return switch ? 2 : 1
    seen || return 4
    ρc = γ * h * ρin + θ
    cap = θ > 0 ? NEWTON_CAP_THETA : NEWTON_CAP
    k = ρc <= 0 ? 2 : ρc >= 1 ? cap : clamp(ceil(Int, log(NEWTON_EPS) / log(ρc)) + (θ > 0), 2, cap)
    return switch ? max(k, 2) : k
end
# once per group and term (the F2 key): a term no bound sees is corrected by Newton iterations,
# checked on the device
# The rows' diffusion multipliers that read the coordinates and may be negative at a site center
# at parameters `p` (F3-24): the scaled row drops the diffusion where `m < 0` (anti-diffusion), so
# the operator is not exact there; `texts` name each term and its multiplier
function _sign_bounds(op::OperatorSpec, keys, p)
    texts = Tuple{String, String, Float64}[]
    for r in op.rows
        r.key in keys || continue
        for (f, mtext, text) in r.msign
            v = Float64(f(p))
            v >= 0 || push!(texts, (text, mtext, v))
        end
    end
    return (; neg = !isempty(texts), texts)
end
function _warn_antidiffusion(keys, texts, alg)
    fs = join(("`$k`" for k in keys), ", ")
    for (text, mtext, v) in texts
        _warn_once(string("implicit-antidiffusion#", join(keys, ","), "#", text, "#", v)) || continue
        @warn string(_algname(alg), ": field", length(keys) == 1 ? " " : "s ", fs, ": in ", text, " the multiplier ",
            mtext, " of the diffusion is negative at some site centers (", isnan(v) ? "no bound sees its sign" :
            string("down to ", round(v; sigdigits = 3)), "): a negative diffusion is anti-diffusion, an ill-posed ",
            "problem, and the implicit operator leaves it out there, so Newton iterations correct it (a budget hit is ",
            "warned, a divergence ends the run with `ReturnCode.ConvergenceFailure`); keep the multiplier ≥ 0 at every ",
            "site, or step an intentionally signed coefficient with `ExplicitEuler`, with care")
    end
    return nothing
end
function _warn_unseen(keys, unseen, alg)
    fs = join(("`$k`" for k in keys), ", ")
    for u in unique(unseen)
        _warn_once(string("implicit-unseen#", join(keys, ","), "#", u)) || continue
        @warn string(_algname(alg), ": field", length(keys) == 1 ? " " : "s ", fs, ": ", u, " is not in the implicit ",
            "operator and no bound sees it, so it is corrected by Newton iterations (`",
            alg isa QuasiSteady ? QS_NEWTON_CAP : 4, "`), checked on the device at every ",
            alg isa QuasiSteady ? "window" : "substep", ": a budget hit is counted and warned with its route, a divergence ends the run with ",
            "`ReturnCode.ConvergenceFailure`. Give `nlsolve = LatticeNewton(; max_iter = k)` to choose the count"
        )
    end
    return nothing
end

# whether the kernels of program `p` read data that change every window: the time, the clock's
# slot, a filled input, or a field the group steps
function _reads_moving(p::Program, ks, spec::GroupSpec)
    filled = Set(i.key for i in spec.inputs if i.filled)
    cs = clock_slot(spec)
    for k in ks, n in k.nodes
        n.op == RUNTIME && n.imm == RT_T && return true
        n.op == PARAM && cs != 0 && n.imm == cs && return true
    end
    for k in ks, n in k.nodes                   # (the loads: an `INSIDE_OP` test reads no value)
        n.op == LOAD || continue
        f = p.fields[k.accesses[n.imm].field]
        (f.key in filled || f.key in spec.state || f.key in spec.external) && return true
    end
    return false
end
# whether the operator program reads the time (its value changes within a window: each
# substep's operator is built at that substep's end time)
_reads_time(p::Program) = any(n -> n.op == RUNTIME && n.imm == RT_T, (n for k in p.kernels for n in k.nodes))
_jac_moving(::Nothing, spec) = false
_jac_moving(jp::Program, spec) = _reads_moving(jp, jp.kernels, spec)
_masks_moving(s::Program, spec) = _reads_moving(s, [k for k in s.kernels if k.key in spec.init], spec)

# the step `h` of the coefficients (a count change, a rebind): the numeric shifts follow; the
# hierarchy is rebuilt before the next stage, and the next substep is a start (BDF2's formula
# holds for one `h`: every change of `h` restarts it, F3 design §3.3 Step changes)
function _set_step!(c::ImplicitCache, rt::GroupRuntime, h::Float64)
    c.h = h
    c.start = true
    _set_shift!(c, rt, _gamma_start(rt.alg); force = true)
    _set_newton!(c, rt.alg)
    return nothing
end
# the operator's γ (the shift `1/(γh)`): BDF2's start takes 1, its other substeps 2/3
function _set_shift!(c::ImplicitCache, rt::GroupRuntime, γ::Float64; force::Bool = false)
    (force || γ != c.γ) || return nothing
    s = group_program_of(rt)
    for r in c.rows
        _set_row_step!(r, s, rt.p, γ * c.h; coupled = c.cs !== nothing)
    end
    c.γ = γ
    c.stale = true
    return nothing
end
# a new count (a parameter write's recount): the step and the Newton count follow at once (R2-N3)
function _count_set!(c::ImplicitCache, rt::GroupRuntime)
    rt.n == 0 && return nothing
    h = rt.dt / rt.n
    h == c.h || _set_step!(c, rt, h)
    return nothing
end
function _set_newton!(c::ImplicitCache, alg)
    c.auto || return nothing
    c.newton = c.cs !== nothing ? _coupled_newton(alg, c.cs.linear, c.switch) :
               _auto_newton(alg, c.exact, c.switch, c.iterate, c.seen, c.ρin, c.h, c.θ, c.smin)
    c.check = c.newton > 1
    c.flip = _flips(alg, c.exact, c.switch)
    return nothing
end
group_program_of(rt::GroupRuntime) = rt.program
# the shift of a row at the stage step `hγ = γh` (`1/hγ`)
function _set_row_step!(r::ImplicitRow, s, p, hγ; coupled::Bool = false)
    if r.solver === nothing && r.lin === nothing
        r.s isa Number && (r.s = oftype(r.s, max(1 / hγ - _coefsum(r.op.jloc, p), 1 / (2hγ))))
        return nothing
    end
    r.numeric === nothing && return nothing
    op, _ = _numeric_operator(s, r.op, fieldid(s, r.key), p, hγ, 1.0, r.mask !== nothing; coupled)
    r.solver === nothing || Solvers.set_coefficients!(r.solver, op)
    if r.solver === nothing && r.lin !== nothing
        bop = Solvers.BoundOperator(r.bop.exec, op, eltype(r.bop), r.bop.solver_type, r.bop.inputs)
        Solvers.update_linear_operator!(r.lin, bop)
        r.bop = bop
    end
    r.numeric = op
    r.s = op.shift
    return nothing
end

# Rebuild the operator before a stage's solves (stale, moving or timed): the operator program at
# the stage's end time `t1`, each field row's shift (`1/hγ`) and solver mask, then each solver's
# hierarchy
function _rebuild!(c::ImplicitCache, rt::GroupRuntime, par::Int, t1::Float64, hγ::Float64, k::Int)
    c.jac === nothing || c.jac[par]((t1, hγ, k))
    c.walk(c.rows, _Rebuild(c.backend, hγ, 1.0, c.word, false, rt.totals.windows % Int32))     # (each row: the rows' types differ)
    c.stale = false
    c.rebuilds += 1
    return nothing
end
# … and at a Newton iteration of a group whose operator reads the iterate (`c.iterate`): the
# operator program at the iterate (slot `par` at the first iteration, the other slot after),
# then the rows that read it
function _rebuild_iterate!(c::ImplicitCache, rt::GroupRuntime, par::Int, first::Bool, t1::Float64, hγ::Float64, k::Int)
    c.jac[(first ? 0 : 2) + par]((t1, hγ, k))
    c.walk(c.rows, _Rebuild(c.backend, hγ, 1.0, c.word, true, rt.totals.windows % Int32))
    return nothing
end
struct _Rebuild{B, W}
    backend::B
    h::Float64
    γ::Float64
    word::W
    iterate::Bool                       # only the rows whose operator reads the iterate
    window::Int32
end
(r::ImplicitRow)(a::_Rebuild) = (a.iterate && !r.op.iterate) ? nothing : _rebuild_row!(r, a.backend, a.h, a.γ, a.word, a.window)
function _rebuild_row!(r::ImplicitRow, backend, h, γ, word, window)
    if r.s isa AbstractArray
        T = eltype(r.s)
        Exec.launch!(backend, _be_shift_body!, length(r.s), (r.s, r.j, r.d, r.m, r.smask, r.rmask, r.dom,
            T(1 / (γ * h)), T(1 / (2γ * h)), word, window))
    end
    if r.solver !== nothing
        Solvers.rebuild!(r.solver)
    elseif r.lin !== nothing
        if LinearSolve.needs_concrete_A(r.lin.alg)
            Solvers.sparse_operator!(r.lin.A, r.bop)
            r.lin.isfresh = true
        else
            r.lin.isfresh = true
            r.lin.precsisfresh = true
        end
    end
    return nothing
end

_zero_masked_body!(i, b, mask) = (@inbounds mask[i] != 0 && (b[i] = zero(eltype(b))); nothing)
function _lin_status!(word, sol, window, gate)
    (gate !== nothing && Array(gate)[1] != 0) && return nothing
    w = word isa Array ? word : Array(word)
    w[STATUS_SOLVES] += UInt32(1)
    if sol.retcode == SciMLBase.ReturnCode.MaxIters
        w[STATUS_BUDGET] += UInt32(1)
    elseif sol.retcode != SciMLBase.ReturnCode.Success && sol.retcode != SciMLBase.ReturnCode.Default
        w[STATUS_CODE] = UInt32(2)
        w[STATUS_CAUSE] |= UInt32(1)
        w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
    end
    word isa Array || copyto!(word, w)
    return nothing
end

# One Newton iteration of one row (`a = (parity, first, t1, h, k, last, window, backend, γ, word,
# it, check, hits)`, `hits`: the check counts a budget hit at this iteration): the residual at `tⁿ⁺¹`, the solve, the status, the update into the other slot,
# and with `check` the Newton check of iteration `it`
function (r::ImplicitRow)(a)
    par, first, t1, h, k, last, window, backend, γ, word, it, check, hits, gate, checkdiv, failbudget, auto, κ, abstol, reltol, gpart, gcnt = a
    r.res[(first ? 0 : 2) + par]((t1, h, k))
    gate === nothing || Exec.launch!(backend, _be_gate_body!, length(r.resarr), (r.resarr, gate))
    dst = r.bufs[3 - par]
    src = first ? r.bufs[par] : dst
    n = length(dst)
    if r.solver === nothing && r.lin === nothing
        Exec.launch!(backend, _be_update_body!, n, (dst, src, nothing, nothing, nothing, r.resarr, r.s, r.mask, r.mval,
                r.mvf, r.lo, last, gate,
            )
        )
        if check
            auto ? _newton_check!(r, backend, word, dst, r.bufs[par], nothing, it, hits, window, isinf(h), checkdiv, failbudget, gate) :
                _kappa_row_norms!(r, backend, dst, r.bufs[par], nothing, gpart, gcnt, gate, abstol, reltol)
        end
        return nothing
    end
    x = _row_correction!(r, backend, γ, h; word, window, gate)
    r.scal === nothing || Exec.launch!(backend, _be_status_body!, 1, (word, r.scal, Int32(window), isinf(h), gate))
    Exec.launch!(backend, _be_update_body!, n, (dst, src, x, r.smask, r.v, nothing, nothing, r.mask, r.mval, r.mvf,
            r.lo, last, gate,
        )
    )
    if check
        auto ? _newton_check!(r, backend, word, dst, r.bufs[par], x, it, hits, window, isinf(h), checkdiv, failbudget, gate) :
            _kappa_row_norms!(r, backend, dst, r.bufs[par], x, gpart, gcnt, gate, abstol, reltol)
    end
    return nothing
end
# the solve of a row with a solver from its residual `resarr` (a scaled row: the right side `G/m`
# and the own rows' δ first): the correction δ, the solver's solution array (also the tangent
# steps' solve of one derivative part, F3-21a)
function _row_correction!(r::ImplicitRow, backend, γ, h; word = nothing, window = Int32(0), gate = nothing)
    sv = r.solver
    if r.f !== nothing
        T = eltype(r.f)
        Exec.launch!(backend, _be_rhs_body!, length(r.f), (r.f, r.v, r.resarr, r.j, r.m, r.smask, r.rmask, r.dom, T(1 / (γ * h)),
            T(1 / (2γ * h))))
    end
    if sv === nothing
        rhs = r.f !== nothing ? r.f : r.resarr
        Exec.compiling() || r.lin.b === rhs || copyto!(r.lin.b, rhs)
        mk = r.smask !== nothing ? r.smask : r.mask
        mk === nothing || Exec.launch!(backend, _zero_masked_body!, length(r.lin.b), (r.lin.b, mk))
        Exec.compiling() && return r.lin.u
        sol = SciMLBase.solve!(r.lin)
        word === nothing || _lin_status!(word, sol, window, gate)
        return r.lin.u
    end
    for w in r.work                             # δ from 0
        Exec.launch!(backend, _zero_body!, length(w), (w,))
    end
    _solve_cache!(r.lin)
    return sv.slot[r.xid] == 1 ? r.xs[1] : r.xs[2]
end
struct _Clip{B}
    backend::B
    par::Int
end
function (r::ImplicitRow)(a::_Clip)
    r.lo === nothing && return nothing
    dst = r.bufs[3 - a.par]
    Exec.launch!(a.backend, _clip_body!, length(dst), (dst, r.lo))
    return nothing
end
function _kappa_row_norms!(r::ImplicitRow, backend, dst, un, x, part, cnt, gate, abstol, reltol)
    n = length(dst)
    nb = cld(n, NB)
    T = eltype(part)
    atol, rtol = T(abstol), T(reltol)
    if x === nothing
        Exec.launch!(backend, _be_kappa_norms_body!, nb, (part, cnt, r.off, dst, un, nothing, nothing, nothing, r.resarr, r.s, r.mask, r.dom, atol, rtol, n, gate))
    else
        Exec.launch!(backend, _be_kappa_norms_body!, nb, (part, cnt, r.off, dst, un, x, r.smask, r.v, nothing, nothing, r.mask, r.dom, atol, rtol, n, gate))
    end
    return nothing
end
function _newton_check!(r::ImplicitRow, backend, word, dst, un, x, it, last, window, steady::Bool, checkdiv::Bool, failbudget::Bool, gate = nothing, auto::Bool = true, κ = 1 // 100, abstol = 1 // 10^6, reltol = 1 // 10^3)
    n = length(dst)
    nb = cld(n, NB)
    T = eltype(r.part)
    if auto
        if x === nothing
            Exec.launch!(backend, _be_norms_body!, nb, (r.part, dst, un, nothing, nothing, nothing, r.resarr, r.s, r.mask, n, gate))
        else
            Exec.launch!(backend, _be_norms_body!, nb, (r.part, dst, un, x, r.smask, r.v, nothing, nothing, r.mask, n, gate))
        end
        # (a field stored in Float16: its rounding at each update is part of the floor, S1)
        fl = eltype(dst) === Float16 ? T(10 * eps(T) + 2 * eps(Float16)) : T(10 * eps(T))
        Exec.launch!(
            backend, _be_newton_body!, 1, (
                word, r.part, Int32(nb), r.hist, Int32(it), last, T(NEWTON_EPS),
                fl, window, steady, UInt32(16), checkdiv, failbudget,
            )
        )
    else
        atol, rtol = T(abstol), T(reltol)
        if x === nothing
            Exec.launch!(backend, _be_kappa_norms_body!, nb, (r.part, r.cnt, 0, dst, un, nothing, nothing, nothing, r.resarr, r.s, r.mask, r.dom, atol, rtol, n, gate))
        else
            Exec.launch!(backend, _be_kappa_norms_body!, nb, (r.part, r.cnt, 0, dst, un, x, r.smask, r.v, nothing, nothing, r.mask, r.dom, atol, rtol, n, gate))
        end
        Exec.launch!(
            backend, _be_kappa_newton_body!, 1, (
                word, r.part, r.cnt, Int32(nb), r.hist, Int32(it), last, T(κ),
                window, steady, UInt32(16), checkdiv, failbudget, gate, UInt32(1),
                T(1 // 10^5), T(3) / T(10), T(100) * sqrt(eps(one(T))),
            )
        )
    end
    return nothing
end

# The substeps of a window (F3 design §3.3): per substep the algorithm's stages (`_substep!`),
# each the Newton iterations over the rows in solve order from slot `par` into the other slot,
# then the slot swap. The operator is rebuilt at a stage when stale (bind, `reset!`, a new `h`
# or `γ`), at the window's first stage when it moves, and at every stage's end time when it
# reads the time.
function _substeps!(c::ImplicitCache, rt::GroupRuntime, t::Float64, h::Float64, k::Int, n::Integer)
    # a window of length 0 (front end A's at-init clamp: the masks, and the aux fields of the
    # state as it is) and a group with no state step as the explicit program does (`h = 0`
    # leaves the state unchanged)
    (n == 0 || h == 0) && return _substeps!(nothing, rt, t, h, k, n)
    h == c.h || _set_step!(c, rt, h)
    w = rt.totals.windows % Int32
    for j in 1:n
        _substep!(rt.alg, c, rt, t + (j - 1) * h, h, k, w, j == 1)
    end
    return nothing
end
# Backward Euler: one stage at `tⁿ⁺¹`
_substep!(::BackwardEuler, c, rt, t0, h, k, w, first) = _stage!(c, rt, t0 + h, 1.0, h, k, w, first)
# Crank–Nicolson: one stage at `tⁿ⁺¹` from `q = uⁿ + (h/2) r(uⁿ)` (`r` at `tⁿ`), or at a start (or
# the first substep of a window whose data can jump) two Backward Euler stages of `h/2` from
# `q = uⁿ` and then `q = uⁿ⁺¹ᐟ²`, with the same operator (the shift `2/h`)
function _substep!(::CrankNicolson, c, rt, t0, h, k, w, first)
    if c.start || (first && c.jumps)
        _set_q!(c, rt, nothing)
        _stage!(c, rt, t0 + h / 2, 0.5, h, k, w, first)
        _set_q!(c, rt, nothing)
        _stage!(c, rt, t0 + h, 0.5, h, k, w, false)
        c.start = false
        return nothing
    end
    c.qres[_parity(rt)]((t0, 0.5 * h, k))
    _stage!(c, rt, t0 + h, 0.5, h, k, w, first)
    return nothing
end
# BDF2: one stage at `tⁿ⁺¹` from `q = (4uⁿ − uⁿ⁻¹)/3` (γ = 2/3), or at a start one Backward Euler
# stage from `q = uⁿ` (γ = 1: the Backward Euler operator); the state it started from is kept
# as the next substep's `uⁿ⁻¹`
function _substep!(a::BDF2, c, rt, t0, h, k, w, first)
    γ = c.start ? 1.0 : _gamma(a)
    _set_q!(c, rt, !c.start)
    _keep_prev!(c, rt)
    _stage!(c, rt, t0 + h, γ, h, k, w, first)
    c.start = false
    return nothing
end
# QuasiSteady: one stage per window with no time-step term (γh = ∞), at the window's start time
_substep!(::QuasiSteady, c, rt, t0, h, k, w, first) = _stage!(c, rt, t0, Inf, h, k, w, first)
# each row's `q` at slot parity `par`: the start `uⁿ` (`bdf = false` or nothing), or BDF2's
# `(4uⁿ − uⁿ⁻¹)/3` (`bdf = true`)
_set_q!(c::ImplicitCache, rt::GroupRuntime, bdf) = (c.walk(c.rows, _SetQ(c.backend, _parity(rt), bdf === true)); nothing)
struct _SetQ{B}
    backend::B
    par::Int
    bdf::Bool
end
function (r::ImplicitRow)(a::_SetQ)
    un = r.bufs[a.par]
    a.bdf ? Exec.launch!(a.backend, _bdf2_q_body!, length(r.q), (r.q, un, r.prev)) :
            Exec.launch!(a.backend, _copy_body!, length(r.q), (r.q, un))
    return nothing
end
# BDF2: `uⁿ` (slot `par`, the stage's start) into each row's `uⁿ⁻¹` for the next substep (its
# `q` holds what this stage reads already)
_keep_prev!(c::ImplicitCache, rt::GroupRuntime) = (c.walk(c.rows, _KeepPrev(c.backend, _parity(rt))); nothing)
struct _KeepPrev{B}
    backend::B
    par::Int
end
(r::ImplicitRow)(a::_KeepPrev) = (Exec.launch!(a.backend, _copy_body!, length(r.prev), (r.prev, r.bufs[a.par])); nothing)

# One stage: the Newton iterations from slot `par` (the current parity) into the other slot at
# its end time `t1`, with the operator's `γ` (the shift `1/(γh)`; the residual's launches take
# `γh` as their step), then the swap. `first`: the window's first stage (a moving operator is
# rebuilt there).
function _stage!(c::ImplicitCache, rt::GroupRuntime, t1::Float64, γ::Float64, h::Float64, k::Int, w::Int32, first::Bool)
    _stage_iterations!(c, rt, t1, γ, h, k, w, first)
    _swap!(rt.store.cur, rt.swaps)
    _after_solve!(c.cs, _parity(rt), t1, γ * h)          # (a nonlinear coupled steady group's growth check)
    return nothing
end
# … its Newton iterations (the tangent steps run after them, before the swap: F3-21a)
function _stage_iterations!(c::ImplicitCache, rt::GroupRuntime, t1::Float64, γ::Float64, h::Float64, k::Int, w::Int32, first::Bool)
    γ == c.γ || _set_shift!(c, rt, γ)
    hγ = γ * h
    par = _parity(rt)
    rebuilt = c.stale || (first && c.moving) || c.timed
    rebuilt && _rebuild!(c, rt, par, t1, hγ, k)
    for it in 1:(c.newton)
        # (a stage's rebuild is its first iteration's)
        c.iterate && !(rebuilt && it == 1) && _rebuild_iterate!(c, rt, par, it == 1, t1, hγ, k)
        host = c.check && c.word isa Array
        host && (@inbounds c.word[STATUS_CONVERGED] = 0)     # (the word has 9 entries)
        # (the automatic count's flip pass of a switch counts no budget hit, M7)
        c.gate === nothing ||
            Exec.launch!(c.backend, _be_gate_iter_body!, 1, (c.word, c.gate, UInt32(length(c.rows)), it == 1))
        _iterate!(c.cs, c, (par, it == 1, t1, hγ, k, it == c.newton, w, c.backend, 1.0, c.word, it, c.check,
                it == c.newton && !c.flip, c.gate, c.check_div, c.fail_budget, c.auto, c.κ, c.abstol, c.reltol, c.gpart, c.gcnt,
            )
        )
        # a host executor stops early once every row met tolerance or on failure (a plain read);
        # when converged, the clip of the last iteration runs on its own
        if host && it < c.newton && (@inbounds(c.word[STATUS_CONVERGED]) == length(c.rows) || @inbounds(c.word[STATUS_CODE]) == UInt32(2))
            @inbounds(c.word[STATUS_CODE]) != UInt32(2) && c.walk(c.rows, _Clip(c.backend, par))
            break
        end
    end
    return nothing
end

# one Newton iteration of the group's rows: one by one, or coupled (F3-12d)
function _iterate!(::Nothing, c::ImplicitCache, a)
    c.walk(c.rows, a)
    if !c.auto && a[12]
        T = eltype(c.gpart)
        Exec.launch!(
            c.backend, _be_kappa_newton_body!, 1, (
                c.word, c.gpart, c.gcnt, Int32(c.gnbt), c.ghist, Int32(a[11]), a[13], T(c.κ),
                a[7], isinf(a[4]), UInt32(16), c.check_div, c.fail_budget, c.gate, UInt32(length(c.rows)),
                T(1 // 10^5), T(3) / T(10), T(100) * sqrt(eps(one(T))),
            )
        )
    end
    return nothing
end
_iterate!(cs, c::ImplicitCache, a) = _coupled_iteration!(cs, c, a)

"""
    compile_cache!(c::ImplicitCache, rt)

Compile the device kernels of an implicit runtime's substeps ahead of its first step (F3-15):
its launch sequence walked once per slot parity in compile mode (`Exec.COMPILE_ONLY`: each
device launch compiles its kernel and runs no work item): the operator program, each row's
rebuild (shift, solver hierarchy), a Newton iteration from the stage's start and after it
(the residual, the right side, the solve's lift and solve plans, the status, the update, the
Newton check), the clip, and Crank–Nicolson's and BDF2's right sides and history copy. The
solvers' plans it builds are the ones the steps use; their slots are restored (the walk runs
nothing). Host state is otherwise untouched.
"""
function compile_cache!(c::ImplicitCache, rt::GroupRuntime)
    h = isfinite(c.h) && c.h > 0 ? c.h : 1.0
    slots = Any[r.solver === nothing ? nothing : copy(r.solver.slot) for r in c.rows]
    w = Int32(0)
    Base.ScopedValues.with(Exec.COMPILE_ONLY => true) do
        for par in 1:2
            c.jac === nothing || foreach(j -> j((0.0, h, 0)), c.jac)
            c.walk(c.rows, _Rebuild(c.backend, h, 1.0, c.word, false, w))
            c.gate === nothing || Exec.launch!(c.backend, _be_gate_iter_body!, 1, (c.word, c.gate, UInt32(length(c.rows)), true))
            for first in (true, false)
                _iterate!(c.cs, c, (par, first, 0.0, h, 0, true, w, c.backend, 1.0, c.word, 1, c.check, false, c.gate, c.check_div, c.fail_budget, c.auto, c.κ, c.abstol, c.reltol, c.gpart, c.gcnt))
            end
            c.walk(c.rows, _Clip(c.backend, par))
            if c.rows[1].q !== nothing
                c.walk(c.rows, _SetQ(c.backend, par, false))
                rt.alg isa BDF2 && (c.walk(c.rows, _SetQ(c.backend, par, true)); c.walk(c.rows, _KeepPrev(c.backend, par)))
            end
            c.qres === nothing || c.qres[par]((0.0, h / 2, 0))
        end
        if !c.auto
            for r in c.rows
                Exec.launch!(c.backend, _reset_hist_body!, 1, (r.hist,))
            end
            c.ghist === nothing || Exec.launch!(c.backend, _reset_hist_body!, 1, (c.ghist,))
            c.cs === nothing || Exec.launch!(c.backend, _reset_hist_body!, 1, (c.cs.hist,))
        end
    end
    for (r, s) in zip(c.rows, slots)
        s === nothing || merge!(r.solver.slot, s)
    end
    return nothing
end

# a rebind (new parameter values): the residual and operator launches bound again, the numeric
# rows' coefficients set (`set_coefficients!`, no recompile); the hierarchy rebuilds at the
# next window. In two parts as `rebind_launches`/`install_launches!`: the first may throw.
function rebind_launches(rt::GroupRuntime{<:FieldStore, <:AbstractImplicitFieldAlgorithm}, p)
    steps = (_bind_steps(rt.backend, rt.program, rt.step, rt.store, p, rt.swaps, rt.all_state, rt.c),
        _bind_masks(rt.backend, rt.program, rt.init, rt.store, p, rt.swaps, rt.all_state, rt.c,
            Set(fieldid(rt.program, k) for k in rt.keys)))
    c = rt.cache
    c isa ImplicitCache || return (steps[1], steps[2], Base.inferencebarrier(_tangent_rebind)(c, rt, p))
    return (steps[1], steps[2], _rebind_cache(c, rt, p))
end
function _rebind_cache(c::ImplicitCache, rt::GroupRuntime, p)
    res, jac, qres, pres = c.rebind(p)
    hγ = c.γ * c.h
    ops = Any[r.numeric === nothing ? nothing :
              first(_numeric_operator(rt.program, r.op, fieldid(rt.program, r.key), p, hγ, 1.0, r.mask !== nothing;
                  coupled = c.cs !== nothing))
              for r in c.rows]
    shifts = Any[r.solver === nothing && r.s isa Number ? oftype(r.s, max(1 / hγ - _coefsum(r.op.jloc, p), 1 / (2hγ))) :
                 nothing for r in c.rows]
    # a row's mask value (`c ~ masked(pred, v)`, `v` may read a parameter): a write changes it
    mvals = Any[_row_mval(rt.program, r, p) for r in c.rows]
    return (res, jac, ops, shifts, p, qres, pres, mvals)
end
function _row_mval(s::Program, r::ImplicitRow, p)
    nv = findfirst(x -> x isa NodeValueRule && x.field == fieldid(s, r.key), s.rules)
    return nv === nothing ? r.mval : convert(typeof(r.mval), _coefval(s.rules[nv].value, p))
end
function install_launches!(rt::GroupRuntime{<:FieldStore, <:AbstractImplicitFieldAlgorithm}, (steps, masks, payload))
    rt.steps, rt.masks = steps, masks
    c = rt.cache
    c isa ImplicitCache ? _install_cache!(c, rt, rt.store, payload) : Base.inferencebarrier(_tangent_install!)(c, rt, payload)
    reset!(rt)
    return rt
end
function _install_cache!(c::ImplicitCache, rt::GroupRuntime, store::FieldStore, (res, jac, ops, shifts, p, qres, pres, mvals))
    for (i, r) in enumerate(c.rows)
        r.res = res[i]
        r.mval = mvals[i]                       # (a coupled row's update reads its row's, F3-21a r1 M1)
        if ops[i] !== nothing
            r.solver === nothing || Solvers.set_coefficients!(r.solver, ops[i])
            r.numeric = ops[i]
            r.s = ops[i].shift
            if r.solver === nothing && r.lin !== nothing
                bop = Solvers.BoundOperator(r.bop.exec, ops[i], eltype(r.bop), r.bop.solver_type, r.bop.inputs)
                Solvers.update_linear_operator!(r.lin, bop)
                r.bop = bop
            end
        end
        shifts[i] === nothing || (r.s = shifts[i])
    end
    c.jac = jac
    c.qres = qres
    if c.cs !== nothing
        for (cr, pr) in zip(c.cs.rows, pres)
            cr.pres = pr
        end
    end
    # (here, not in `rebind_launches`: front end A writes the tables between the two)
    bp = _bound_params(store, rt.program, c.op, c.keys, p)
    b, rb = inexact_bounds(c.op, c.keys, c.cyclic, bp), _robin_bounds(rt.program, c.op, _robin_keys(rt.alg, c.op, c.keys), bp)
    # the classification at the new parameters (a write may turn a Robin face negative), as a
    # fresh problem's (M2)
    sb = _sign_bounds(c.op, c.keys, bp)        # (and a coordinate multiplier turned negative, F3-24 r1 M1)
    c.exact = c.exact0 && !rb.neg && !sb.neg
    c.seen = isempty(b.unseen) && !rb.unseen && !sb.neg
    c.ρin = b.ρ + b.κ + rb.ρ
    c.θ = b.θ
    c.smin = _steady_shift(c.op, c.keys, p)
    c.cs !== nothing || c.exact || c.seen || !(rt.alg.nlsolve === nothing) || _warn_unseen(c.keys, [b.unseen; rb.texts], rt.alg)
    c.cs !== nothing || _warn_antidiffusion(c.keys, sb.texts, rt.alg)
    _set_newton!(c, rt.alg)
    return nothing
end

"""
    substeps(spec::GroupSpec, alg::AbstractImplicitFieldAlgorithm, dt, pp; fields = spec.state, stability = spec.stability,
             key = identity, texts = ProblemTexts(spec.texts.route)) -> Int

The substep count of an implicit algorithm (F3 design §3.7), the same policy as the explicit
one with the implicit rule (§3.6): the parameter refusals first (a negative diffusion
coefficient, a coefficient that is not finite where the inputs reach), then
`n = max(m, ⌈2γ dt g⌉, ⌈2γ dt (ρ_adv + κ_in + ρ_rob) / (1 − θ)⌉)`: `m` the user's count (when
left out 1, and 2 for Crank–Nicolson on data that can jump every window, so that a window is
not only its damped substep); `γ` the algorithm's (the shift `1/(γh)`: Backward Euler 1, Crank–Nicolson 1/2, BDF2
1, as its Backward Euler start); the growth rule, `g` the largest positive local derivative the
operator sees ([`growth`](@ref)), so the shift `1/(γh) − g` stays at least half of `1/(γh)`;
the convergence rule of the Newton correction, which converges with a contraction
`ρ_c ≤ (1 + θ)/2`: `ρ_adv` the upwind bound of the advection terms, `κ_in` the cross sum of a
cycle among the group's fields ([`inexact_bounds`](@ref)), `ρ_rob` the part `w |d⁻|` of a
Robin face with a negative diagonal, and `θ ≤ 1/2` the face-wise ratio of a diffusion term
left out of a scaled row to the one kept, which contracts at any step size (a ratio above 1/2,
or unknown, puts the term's Gershgorin bound in the sum instead). No stability bound is
needed: an unknown bound is no refusal (the device check decides). When a rule raises the
user's count, a warning says which, once per cause (`key`).
"""
function substeps(
        spec::GroupSpec, alg::AbstractImplicitFieldAlgorithm, dt::Real, pp; fields = spec.state, stability = spec.stability,
        key = identity, texts::AbstractPolicyTexts = ProblemTexts(spec.texts.route)
    )
    isempty(fields) && return 0
    dt = Float64(dt)
    r = bound_report(stability, pp)
    check_declared(stability, pp)
    ctx = (; stability, pp, r, fields = collect(String, fields), dt, least = alg.substeps)
    (isempty(r.negative) && !any(x -> x[3] isa Tuple, r.nonfinite)) || refuse_parameters(texts, ctx)
    (; op, keys, b, ρrob, n1, n2, m) = _implicit_rules(spec, alg, dt, pp, fields)
    if alg.substeps !== nothing && max(n1, n2) > m
        rule = n2 >= n1 ? 2 : 1
        _warn_once(key(string("implicit-raise#", rule))) && @warn _raise_text(op, keys, alg, max(n1, n2), rule, b.κ > 0, ρrob > 0)
    end
    return max(m, n1, n2)
end
# the parts of the implicit count (`substeps`, and `field_report`'s cause): `m` the user's count
# (or the least, `_least_count`), `n1` the growth rule (`g` the growth the operator sees), `n2`
# the convergence rule of the terms out of the operator (`b` their bounds, `ρrob` the Robin part)
function _implicit_rules(spec::GroupSpec, alg::AbstractImplicitFieldAlgorithm, dt::Float64, pp, fields)
    op = _operator(spec, alg)
    keys = collect(String, fields)
    g = growth(op, keys, pp)
    b = inexact_bounds(op, keys, last(_solve_order(spec.rate, keys)), pp)
    ρrob = _robin_bounds(spec.rate, op, keys, pp).ρ
    γ = _gamma_count(alg)
    # (the convergence rule on the sum: the parts out of the operator add in one correction)
    n1 = ceil(Int, 2γ * dt * g)
    n2 = ceil(Int, 2γ * dt * (b.ρ + b.κ + ρrob) / (1 - b.θ))
    m = something(alg.substeps, _least_count(spec, alg, keys))
    return (; op, keys, g, b, ρrob, γ, n1, n2, m)
end
# why an implicit count is above the user's (`substeps = m` is a minimum), in the manual's words
# (the growth rule, the convergence rule of the Newton correction)
function _raise_text(op::OperatorSpec, keys, alg, n, rule, cycle, robin)
    fs = join(("`$k`" for k in keys), ", ")
    sh = alg isa CrankNicolson ? "2/h" : "1/h"
    head = string(_algname(alg), "(substeps = ", alg.substeps, "): field", length(keys) == 1 ? " " : "s ", fs,
        length(keys) == 1 ? " takes " : " take ", n, " substeps, more than the ", alg.substeps, " requested: ")
    rule == 1 && return string(head, "a local growth `∂f/∂c` that the operator sees needs `", sh, "` at least twice it, so the shift `",
        sh, " − ∂f/∂c` keeps the step stable; fewer substeps are not stable")
    terms = unique([t for r in op.rows if r.key in keys for t in r.inexact])
    cycle && push!(terms, "the cycle among the group's fields")
    robin && push!(terms, "the negative part of a Robin face")
    return string(head, "the terms out of the implicit operator (", join(terms, ", "), ") are corrected by Newton ",
        "iterations, which converge only when the substep keeps their contraction at most 1/2; fewer substeps would ",
        "not converge")
end
substeps(g::FieldGroup, alg::AbstractImplicitFieldAlgorithm, dt::Real, pp; kw...) = substeps(g.spec, alg, dt, pp; kw...)
# QuasiSteady: one solve per window (no count), after the parameter refusals and the steady
# refusals (F3 design §3.5), at build and at every parameter write
function substeps(spec::GroupSpec, alg::QuasiSteady, dt::Real, pp; fields = spec.state, stability = spec.stability,
        key = identity, texts::AbstractPolicyTexts = ProblemTexts(spec.texts.route)
    )
    isempty(fields) && return 0
    r = bound_report(stability, pp)
    check_declared(stability, pp)
    ctx = (; stability, pp, r, fields = collect(String, fields), dt = Float64(dt), least = nothing)
    (isempty(r.negative) && !any(x -> x[3] isa Tuple, r.nonfinite)) || refuse_parameters(texts, ctx)
    op = _operator(spec, alg)
    keys = collect(String, fields)
    if coupled_solve(alg, op, spec.rate, keys)
        # the rows solved together: the coupled system decides (its modes, where they are known;
        # else the device), not each row on its own (a row's growth that the coupling damps is a
        # well-posed steady system, F3-12d)
        Base.inferencebarrier(_coupled_refusal)(spec.rate, op, keys, pp)      # (no compile for a single field, r1 M1)
    else
        _steady_refusals(spec, op, keys, pp)
    end
    return 1
end
# The steady refusals of the rows `keys` at raw parameters `p` (invalid input, F3 design §3.5):
# a positive local derivative the operator sees (a growth: the steady solve is indefinite and a
# growing row's steady state unstable or not unique), and a row with no shift (no decay, no
# nonlinear or switched local term) and no anchor (no Dirichlet or Robin face, no mask), whose
# `0 = rhs` has no solution or many. A row whose operator varies by site, or that reads another
# field of the group, is decided on the device (an island: no real reduction, S-a).
function _steady_refusals(spec::GroupSpec, op::OperatorSpec, keys, p)
    s = spec.rate
    for r in op.rows
        r.key in keys || continue
        r.field && continue
        g = _coefsum(r.jloc, p)
        g > 0 && throw(ArgumentError(string("QuasiSteady: field `", r.key, "`: its local derivative `∂f/∂c` = ", g,
            " is positive (a growth the operator sees): a growing field's steady state is unstable or not unique, and ",
            "its steady solve is indefinite; step the field with `BackwardEuler`")))
        id = fieldid(s, r.key)
        _steady_indefinite(s, r, id, -g, p)
        (g < 0 || r.iterate || r.switch || !isempty(r.cross)) && continue
        any(x -> x isa NodeValueRule && x.field == id, s.rules) && continue
        any(a -> !s.periodic[a] && any(k -> _face_kind(s, id, a, k, p)[1] !== :none, 1:2), eachindex(s.periodic)) && continue
        throw(ArgumentError(string("QuasiSteady: field `", r.key, "` has no unique steady state: it has no decay (a ",
            "local term `−k c` with k > 0) and no fixed value (a Dirichlet or Robin face, a mask), so `0 = rhs` has no ",
            "solution or many (a constant added to one is another); add a decay or a fixed value, or step it with ",
            "`BackwardEuler`")))
    end
    return nothing
end
# A numeric row with a Robin face whose diagonal is negative: the steady operator (which takes
# that part, `robin_full`) is `s + Σ_a A_a`, one symmetric tridiagonal `A_a` per axis (faces
# `w_a`, the boundary rows' face terms), so its smallest eigenvalue is `s + Σ_a λ_min(A_a)`.
# Not positive: the steady state is unstable or not unique, as with a growth (r3 S1; a mask only
# raises it, so a masked row is checked without its mask, and accepted when that passes)
function _steady_indefinite(s::Program{N}, r::RowOperator, id, shift, p) where {N}
    kinds = [ntuple(k -> s.periodic[a] ? (:none, 0.0, 0.0) : _face_kind(s, id, a, k, p), 2) for a in 1:N]
    any(ks -> any(f -> f[1] === :robin && Solvers.robin_parts(f[2], f[3], 0.0)[2] < 0, ks), kinds) || return nothing
    any(x -> x isa NodeValueRule && x.field == id, s.rules) && return nothing
    r.domain && return nothing
    dims = Tuple(Int.(leveldims(s, s.fields[id].levels[1])))
    # (a hexagonal row: its modes are not per axis; Lanczos on the row's operator, behind a barrier)
    _ishex(s) && return _steady_refuse(r, Base.inferencebarrier(_hex_steady_min)(r, kinds, dims, s.periodic, shift, p)...)
    λ, scale = shift, abs(shift)
    for a in 1:N
        w = _coefsum(r.faces[a], p)
        scale += 4abs(w)
        s.periodic[a] && continue                   # (a periodic axis: its smallest is 0)
        n = dims[a]
        d = fill(2w, n)
        for (k, i) in ((1, 1), (2, n))
            f = kinds[a][k]
            d[i] += f[1] === :dirichlet ? w : f[1] === :robin ? w * (f[2] / (f[2] / 2 + f[3])) - w : -w
        end
        λ += _tridiag_min(d, w)
    end
    return _steady_refuse(r, λ, scale)
end
function _steady_refuse(r::RowOperator, λ, scale)
    λ > 1e-10 * scale && return nothing
    throw(ArgumentError(string("QuasiSteady: field `", r.key, "`: its steady operator is indefinite (smallest ",
        "eigenvalue ", round(λ; sigdigits = 3), "): a Robin face `α c + β ∂c/∂n = g` with α and β of opposite signs ",
        "feeds the field more than its diffusion and decay remove, so the steady state is unstable or not unique; ",
        "step the field with `BackwardEuler`, or give the face a smaller |β| (or a larger decay)")))
end
# The smallest eigenvalue of a numeric hexagonal row's steady operator (F3-20 r2 M1): `s u + Σ_links
# w (u − u_n)`, a link that leaves the box taking its face's ghost diagonal `w d` (axis 1's face for a
# diagonal link that leaves along axis 1, else axis 2's; Dirichlet `d = 2`, Robin `α/(α/2 + β)`,
# either sign), by Lanczos from a fixed start (the operator is symmetric). A Ritz value θ is never
# below the smallest eigenvalue, so θ < 0 is a sure refusal; else the run stops when the Ritz
# residual bound `ρ` (an eigenvalue lies in θ ± ρ) is below θ/100, or after `4(n1 + n2) + 100` steps
# (the bottom gap is ~ w (π/n)², so convergence takes O(n) steps), and returns θ − ρ (θ when negative).
# Returns `(λ, scale)` for `_steady_refuse`
function _hex_steady_min(r::RowOperator, kinds, dims, per, shift, p)
    w = Float64(_coefsum(r.faces[1], p))
    n1, n2 = dims
    n = n1 * n2
    ghost(f) = f[1] === :dirichlet ? 2.0 : f[1] === :robin ? f[2] / (f[2] / 2 + f[3]) : 0.0
    dg = fill(Float64(shift), n)                   # the diagonal: shift, faces, ghosts
    for j in 1:n2, i in 1:n1, (di, dj) in _HEXLINKS
        in1 = per[1] || 1 <= i + di <= n1
        in2 = per[2] || 1 <= j + dj <= n2
        dg[i + (j - 1) * n1] += in1 && in2 ? w :
            w * (in1 ? ghost(kinds[2][dj < 0 ? 1 : 2]) : ghost(kinds[1][di < 0 ? 1 : 2]))
    end
    v = [sin(1.3q) + 0.5cos(0.7q) for q in 1:n]    # (a fixed start: no RNG state)
    v ./= LinearAlgebra.norm(v)
    vp, y = zeros(n), zeros(n)
    α, β = Float64[], Float64[]
    λ = Inf
    for k in 1:(4(n1 + n2) + 100)
        _hex_apply!(y, v, dg, w, n1, n2, (per[1], per[2]))
        k > 1 && (y .-= β[end] .* vp)
        a = LinearAlgebra.dot(v, y)
        push!(α, a)
        y .-= a .* v
        b = LinearAlgebra.norm(y)
        if k % 5 == 0 || b == 0 || k == n
            E = LinearAlgebra.eigen(LinearAlgebra.SymTridiagonal(α, β), 1:1)
            θ, ρ = E.values[1], b * abs(E.vectors[end, 1])
            λ = θ < 0 ? θ : θ - ρ
            (θ < 0 || ρ <= 1e-2 * θ || b == 0 || k == n) && break
        end
        push!(β, b)
        vp, v = v, y ./ b
    end
    return λ, abs(shift) + 12abs(w)
end
const _HEXLINKS = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
function _hex_apply!(y, x, dg, w, n1, n2, per::NTuple{2,Bool})
    @inbounds for j in 1:n2, i in 1:n1
        q = i + (j - 1) * n1
        acc = dg[q] * x[q]
        if 1 < i < n1 && 1 < j < n2                # (inside: no wrap, no ghost)
            acc -= w * (x[q + 1] + x[q - 1] + x[q + n1] + x[q - n1] + x[q + 1 - n1] + x[q - 1 + n1])
        else
            for (di, dj) in _HEXLINKS
                ii, jj = i + di, j + dj
                (per[1] || 1 <= ii <= n1) && (per[2] || 1 <= jj <= n2) || continue
                acc -= w * x[mod1(ii, n1) + (mod1(jj, n2) - 1) * n1]
            end
        end
        y[q] = acc
    end
    return y
end
# the smallest eigenvalue of the symmetric tridiagonal with diagonal `d` and off-diagonal `−w`
# (Sturm counts by bisection)
function _tridiag_min(d::Vector{Float64}, w::Float64)
    n = length(d)
    n == 1 && return d[1]
    lo, hi = minimum(d) - 2abs(w), maximum(d) + 2abs(w)
    below(x) = (q = d[1] - x; c = Int(q < 0); for i in 2:n
                    q = d[i] - x - w^2 / (q == 0 ? eps() : q); c += q < 0
                end; c)
    for _ in 1:200
        m = (lo + hi) / 2
        below(m) >= 1 ? (hi = m) : (lo = m)
        hi - lo <= 1e-14 * max(1.0, abs(hi)) && break
    end
    return (lo + hi) / 2
end
# the least automatic count: 1; Crank–Nicolson on data that can jump every window takes 2, so
# that each window has one Crank–Nicolson substep after its damped one (with one substep the
# window is Backward Euler in two halves: first order at twice the cost, batch 4 review r1 S1)
_least_count(spec::GroupSpec, alg::AbstractImplicitFieldAlgorithm, keys) = 1
_least_count(spec::GroupSpec, alg::CrankNicolson, keys) = _jumps(spec.rate, spec.rate, keys, spec, true) ? 2 : 1
