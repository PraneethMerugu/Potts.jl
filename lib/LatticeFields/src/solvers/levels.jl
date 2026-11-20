# Generic level code (package bodies, the same for every operator): the rule-M hierarchy
# build and the in-workgroup bottom V-cycle. Every level stores the same arrays, so these
# bodies never vary with the model: `active` (U8, 1 = unknown), `w[a]` (face to +e_a, raw: the
# active and mask role of a face follows from `active` on both sides), `s` (shift), `sbox`
# (box face-Dirichlet absorption) and `sint` (absorption folded inside coarse cells). For an
# active site, A x = (s + sbox + sint) x + Σ_faces w (x − active_j x_j) (flux-difference form).
# Indices: every index below is built from the level's own dims (wrapped on periodic axes,
# a face across a non-periodic box face has w = 0 and is skipped), which is the bounds
# argument for each `@inbounds`.

# (`prod`/`sum` widen Int32 to Int; these folds keep the index type.)
@inline _stride(dims::NTuple{N, Int32}, a) where {N} = foldl(*, ntuple(
    d -> d < a ?
         dims[d] :
         one(Int32), N))
@inline function _coords(i::Int32, dims::NTuple{N, Int32}) where {N}
    t = i - one(Int32)
    return ntuple(d -> rem(div(t, _stride(dims, d)), dims[d]) + one(Int32), N)
end
@inline _lin(x::NTuple{N, Int32}, dims::NTuple{N, Int32}) where {N} = one(Int32) +
                                                                      foldl(
    +, ntuple(d -> (x[d] - one(Int32)) * _stride(dims, d), N))
"""
Neighbor of `x` along axis `a` by `σ = ±1`: `(x′, exists)`; periodic axes wrap.
"""
@inline function _nb(x::NTuple{N, Int32}, a, σ, dims, per) where {N}
    v0 = x[a] + Int32(σ)
    ok = one(Int32) <= v0 <= dims[a]
    v = ok ? v0 : per[a] ? (v0 < one(Int32) ? dims[a] : one(Int32)) : x[a]
    return ntuple(d -> d == a ? v : x[d], N), ok | per[a]
end
"""
Neighbor of `x` by the offset `o` (each entry −1, 0 or 1): `(x′, exists)`; periodic axes wrap.
"""
@inline function _nbo(x::NTuple{N, Int32}, o, dims, per) where {N}
    y = ntuple(N) do d
        v0 = x[d] + Int32(o[d])
        ok = one(Int32) <= v0 <= dims[d]
        ok ? v0 : per[d] ? (v0 < one(Int32) ? dims[d] : one(Int32)) : x[d]
    end
    return y, all(ntuple(d -> (one(Int32) <= x[d] + Int32(o[d]) <= dims[d]) | per[d], N))
end
"""
Children of coarse coordinate `X` along one axis: `lo:hi` (a triple at the last site of an
odd axis; the identity on an axis of size 1).
"""
@inline function _kids(X::Int32, nf::Int32, nc::Int32)
    nf == one(Int32) && return X, X
    lo = Int32(2) * (X - one(Int32)) + one(Int32)
    return lo, (X == nc && nf > Int32(2) * nc) ? lo + Int32(2) : lo + one(Int32)
end
"""
Physical width (in finest cells) of cell `i` of a level with `n` cells, `ℓ` coarsenings
below a finest axis of `n0` cells: 2^ℓ, the last cell takes the rest.
"""
@inline _width(i::Int32, n::Int32, n0::Int32, ℓ::Int32) = n0 == one(Int32) ? one(Int32) :
                                                          i < n ? (one(Int32) << ℓ) :
                                                          n0 -
                                                          (n - one(Int32)) *
                                                          (one(Int32) << ℓ)

"""
Rule-M weights of the hierarchy build: `inside` for a mask face inside a coarse
cell, `plane` for a mask face on a plane between two active coarse cells, `inherited` for
absorption folded on a finer level, `box` for box face-Dirichlet absorption; `majority`
selects the Majority fold (real child count) instead of Any; `diagonal` weighs the diagonal
fine faces of a hexagonal lattice in the coarse faces (`build_hex!`). Values, not types: the
negative controls of the tests pass other weights.
"""
Base.@kwdef struct RuleWeights
    inside::Float64 = 1.0
    plane::Float64 = 1.0
    inherited::Float64 = 1.0
    box::Float64 = 0.5
    majority::Bool = false
    diagonal::Float64 = 1.0
end
const RULE_M = RuleWeights()

@inline function _fold(X, active, dimsf, dimsc, majority)
    lo = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[1], length(X))
    hi = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[2], length(X))
    cnt = zero(Int32)
    nch = zero(Int32)
    for c in CartesianIndices(ntuple(d -> lo[d]:hi[d], length(X)))
        nch += one(Int32)
        @inbounds cnt += active[_lin(Int32.(Tuple(c)), dimsf)] != 0 ? one(Int32) : zero(Int32)
    end
    return majority ? Int32(2) * cnt > nch : cnt > zero(Int32)
end

"""
    build_site!(J, S, P, G)

One coarse site of the rule-M build (§6.3): Any fold, `S_c = ΣS_f`, box absorption `box·Σ`,
active–active faces rediscretized with physical widths, mask faces folded by rule M.
`S = ((active, w..., s, sbox, sint) fine, (…) coarse)`, `P = (inside, plane, inherited, box)`,
`G = (n, dimsf, dimsc, n0, ℓ, per, majority)`.
"""
function build_site!(j, S::Tuple{F, C}, P, G) where {F, C}
    (af, wf, sf, bf, if_), (ac, wc, sc, bc, ic) = S
    T = eltype(sf)
    dimsf, dimsc, per, n0, ℓ = G.dimsf, G.dimsc, G.per, G.n0, G.level
    N = length(dimsf)
    J = Int32(j)
    X = _coords(J, dimsc)
    lo = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[1], N)
    hi = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[2], N)
    activeJ = _fold(X, af, dimsf, dimsc, G.majority)
    s, sb, si = zero(T), zero(T), zero(T)
    for ci in CartesianIndices(ntuple(d -> lo[d]:hi[d], N))
        c = Int32.(Tuple(ci))
        i = _lin(c, dimsf)
        @inbounds active = af[i] != 0
        if active
            @inbounds s += sf[i]
            @inbounds sb += T(P[4]) * bf[i]
            @inbounds si += T(P[3]) * if_[i]
        end
        for a in 1:N
            cn, ok = _nb(c, a, 1, dimsf, per)
            ok || continue
            internal = c[a] < hi[a] || (dimsc[a] == one(Int32) && dimsf[a] > one(Int32))
            internal || continue                              # plane faces below
            @inbounds w = wf[a][i]
            @inbounds xor_ = active != (af[_lin(cn, dimsf)] != 0)
            xor_ && (si += T(P[1]) * w)
        end
    end
    for a in 1:N                                              # high planes: J -> J + e_a
        acc = zero(T)
        if dimsc[a] > one(Int32) && (per[a] || X[a] < dimsc[a])
            Xn, _ = _nb(X, a, 1, dimsc, per)
            actn = _fold(Xn, af, dimsf, dimsc, G.majority)
            fd = T(_width(X[a], dimsc[a], n0[a], ℓ) + _width(Xn[a], dimsc[a], n0[a], ℓ))
            for ci in CartesianIndices(ntuple(d -> (d == a ? hi[a] : lo[d]):hi[d], N))
                c = Int32.(Tuple(ci))
                cn, _ = _nb(c, a, 1, dimsf, per)
                i = _lin(c, dimsf)
                @inbounds w, x, y = wf[a][i], af[i] != 0, af[_lin(cn, dimsf)] != 0
                f = T(_width(c[a], dimsf[a], n0[a], ℓ - one(Int32)) +
                      _width(cn[a], dimsf[a], n0[a], ℓ - one(Int32))) / fd
                cf, dcf = (x & y) ? w : zero(T), (x != y) ? w : zero(T)
                if activeJ & actn
                    acc += f * cf
                    x && (si += T(P[2]) * dcf)
                else
                    acc += f * (cf + dcf)
                end
            end
        end
        @inbounds wc[a][J] = acc
    end
    for a in 1:N                                              # low planes: mask faces into J
        (dimsc[a] == one(Int32) || (!per[a] && X[a] == one(Int32))) && continue
        Xp, _ = _nb(X, a, -1, dimsc, per)
        (activeJ && _fold(Xp, af, dimsf, dimsc, G.majority)) || continue
        for ci in CartesianIndices(ntuple(d -> lo[d]:(d == a ? lo[a] : hi[d]), N))
            c = Int32.(Tuple(ci))
            cp, _ = _nb(c, a, -1, dimsf, per)
            @inbounds x, y = af[_lin(c, dimsf)] != 0, af[_lin(cp, dimsf)] != 0
            @inbounds (x & !y) && (si += T(P[2]) * wf[a][_lin(cp, dimsf)])
        end
    end
    @inbounds ac[J] = activeJ ? 0x01 : 0x00
    @inbounds sc[J] = activeJ ? s : zero(T)
    @inbounds bc[J] = activeJ ? sb : zero(T)
    @inbounds ic[J] = activeJ ? si : zero(T)
    return nothing
end

"""
    build_hex!(J, S, P, G)

One coarse site of the rule-M build on a hexagonal lattice (axial coordinates; coarsening by 2
per axis keeps the lattice hexagonal): as `build_site!`, with three face directions `e₁`, `e₂`,
`e₁ − e₂`. A fine face crosses from the children of `J` to those of `J + Δ`, `Δ` one of
`±e₁`, `±e₂`, `±(e₁ − e₂)` (a diagonal fine face can cross an axial plane: it then feeds that
axial coarse face). A coarse face is the mean of the fine faces that cross it, times its
rediscretized factor (the fine faces of its own direction, with the physical widths as in
`build_site!`; the one diagonal fine face of a diagonal coarse face takes the sum of its axial
factors), so a constant coefficient keeps its value on every level and in every direction;
mask faces fold by rule M. `P = (inside, plane, inherited, box, diagonal)`, `diagonal` the
weight of the diagonal fine faces in the coarse faces (1; 0 drops them, the negative control).
"""
# the tuple `t` with entry `e` replaced by `v`
@inline _tset(t::NTuple{3, T}, v, e) where {T} = ntuple(q -> q == e ? T(v) : t[q], 3)
# the factor of a fine face `c → cn` along axis `a` in the coarse face `X → Xn`: fine over
# coarse center distance, from the physical widths (`build_site!`)
@inline function _hexfac(::Type{T}, a, c, cn, X, Xn, dimsf, dimsc, n0, ℓ) where {T}
    T(_width(c[a], dimsf[a], n0[a], ℓ - one(Int32)) + _width(cn[a], dimsf[a], n0[a], ℓ - one(Int32))) /
    T(_width(X[a], dimsc[a], n0[a], ℓ) + _width(Xn[a], dimsc[a], n0[a], ℓ))
end
function build_hex!(j, S::Tuple{F, C}, P, G) where {F, C}
    (af, wf, sf, bf, if_), (ac, wc, sc, bc, ic) = S
    T = eltype(sf)
    dimsf, dimsc, per, n0, ℓ = G.dimsf, G.dimsc, G.per, G.n0, G.level
    J = Int32(j)
    X = _coords(J, dimsc)
    lo = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[1], 2)
    hi = ntuple(d -> _kids(X[d], dimsf[d], dimsc[d])[2], 2)
    activeJ = _fold(X, af, dimsf, dimsc, G.majority)
    # the coarse neighbors J + E (E = e₁, e₂, e₁ − e₂) and J − E: active after the fold
    E = ((Int32(1), Int32(0)), (Int32(0), Int32(1)), (Int32(1), Int32(-1)))
    actp = ntuple(e -> (Y = _nbo(X, E[e], dimsc, per); Y[2] && _fold(Y[1], af, dimsf, dimsc, G.majority)), 3)
    actm = ntuple(e -> (Y = _nbo(X, (-E[e][1], -E[e][2]), dimsc, per); Y[2] && _fold(Y[1], af, dimsf, dimsc, G.majority)), 3)
    s, sb, si = zero(T), zero(T), zero(T)
    cf = (zero(T), zero(T), zero(T))         # per coarse direction: Σ active–active fine faces,
    dcf = cf                                 # Σ mask faces, Σ mask faces with an active child of J,
    dcx = cf
    nc = (zero(T), zero(T), zero(T))         # the count of crossing faces, the rediscretized factor
    gf = nc
    for ci in CartesianIndices((lo[1]:hi[1], lo[2]:hi[2]))
        c = Int32.(Tuple(ci))
        i = _lin(c, dimsf)
        @inbounds active = af[i] != 0
        if active
            @inbounds s += sf[i]
            @inbounds sb += T(P[4]) * bf[i]
            @inbounds si += T(P[3]) * if_[i]
        end
        for d in 1:3, σ in (1, -1)
            o = (σ * E[d][1], σ * E[d][2])
            cn, ok = _nbo(c, o, dimsf, per)
            ok || continue
            jn = _lin(cn, dimsf)
            @inbounds w = σ > 0 ? wf[d][i] : wf[d][jn]
            @inbounds y = af[jn] != 0
            # the coarse step Δ of the face (an axis of one coarse site: no step)
            Δ = ntuple(a -> dimsc[a] == one(Int32) ? zero(Int32) :
                            o[a] == 1 && c[a] == hi[a] ? one(Int32) :
                            o[a] == -1 && c[a] == lo[a] ? -one(Int32) : zero(Int32), 2)
            if Δ == (zero(Int32), zero(Int32))           # inside J: once per face
                σ > 0 && active != y && (si += T(P[1]) * w)
                continue
            end
            e = Δ[2] == zero(Int32) ? 1 : Δ[1] == zero(Int32) ? 2 : 3
            if Δ == E[e]                                 # J → J + E: the coarse face of J
                d == 3 && (w *= T(P[5]))
                x2 = active & y
                cf = _tset(cf, cf[e] + (x2 ? w : zero(T)), e)
                dcf = _tset(dcf, dcf[e] + (active != y ? w : zero(T)), e)
                dcx = _tset(dcx, dcx[e] + (active & !y ? w : zero(T)), e)
                nc = _tset(nc, nc[e] + one(T), e)
                if d == e && σ > 0                       # its own direction: the physical widths
                    Xn = _nbo(X, E[e], dimsc, per)[1]
                    f1 = _hexfac(T, 1, c, cn, X, Xn, dimsf, dimsc, n0, ℓ)
                    f2 = _hexfac(T, 2, c, cn, X, Xn, dimsf, dimsc, n0, ℓ)
                    gf = _tset(gf, gf[e] + (e == 3 ? f1 + f2 : e == 1 ? f1 : f2), e)
                end
            elseif activeJ && actm[e] && active && !y    # J − E → J: a mask face on its plane
                si += T(P[2]) * w
            end
        end
    end
    for e in 1:3
        acc = zero(T)
        if nc[e] > zero(T)
            m = gf[e] / nc[e]
            if activeJ & actp[e]
                acc = m * cf[e]
                si += T(P[2]) * dcx[e]
            else
                acc = m * (cf[e] + dcf[e])
            end
        end
        @inbounds wc[e][J] = acc
    end
    @inbounds ac[J] = activeJ ? 0x01 : 0x00
    @inbounds sc[J] = activeJ ? s : zero(T)
    @inbounds bc[J] = activeJ ? sb : zero(T)
    @inbounds ic[J] = activeJ ? si : zero(T)
    return nothing
end

# ---- the bottom: one workgroup, barrier-separated phases (contract item 5) -----------------
"""
`(b − A x)ᵢ` and the diagonal `Dᵢ` of site `i` on a level (0 at masked sites).
"""
@inline function _resid(i::Int32, active, w, s, sb, si, x, b, dims, per)
    T = eltype(x)
    @inbounds active[i] != 0 || return zero(T), one(T)
    X = _coords(i, dims)
    @inbounds xi = x[i]
    @inbounds d0 = s[i] + sb[i] + si[i]
    D, Ax = d0, d0 * xi
    for a in 1:length(dims)
        for σ in (1, -1)
            Y, ok = _nb(X, a, σ, dims, per)
            ok || continue
            j = _lin(Y, dims)
            @inbounds wf = σ > 0 ? w[a][i] : w[a][j]
            @inbounds xj = active[j] != 0 ? x[j] : zero(T)
            D += wf
            Ax += wf * (xi - xj)
        end
    end
    if length(w) > length(dims)                     # hexagonal: the faces to ±(e₁ − e₂)
        for σ in (1, -1)
            Y, ok = _nbo(X, (σ, -σ), dims, per)
            ok || continue
            j = _lin(Y, dims)
            @inbounds wf = σ > 0 ? w[3][i] : w[3][j]
            @inbounds xj = active[j] != 0 ? x[j] : zero(T)
            D += wf
            Ax += wf * (xi - xj)
        end
    end
    @inbounds return b[i] - Ax, D
end

# phase kinds of the bottom schedule
const KZ, KR, KU, KRS, KRT, KP = Int32.(1:6)

"""
Chebyshev coefficients `(c₁, c₂)` of step `k` on `[lo, hi]` (`lo == hi`: Richardson 1/θ;
an empty level, θ = 0: no correction).
"""
@inline function _coarse_coefs(k::Int32, lo::T, hi::T) where {T}
    θ, δ = (hi + lo) / 2, (hi - lo) / 2
    θ == zero(T) && return zero(T), zero(T)
    σ = δ > eps(T) * θ ? θ / δ : zero(T)
    (k == one(Int32) || σ == zero(T)) && return zero(T), inv(θ)
    ρ, c1, c2 = inv(σ), zero(T), zero(T)
    for _ in 2:k
        ρn = inv(2σ - ρ)
        c1, c2, ρ = ρn * ρ, 2ρn / δ, ρn
    end
    return c1, c2
end

"""
Phases of the bottom over `K` levels: per level above the coarsest Chebyshev(ν₁) from zero
(`1 + 2(ν₁ − 1)`), residual and restriction (2); the coarsest level's fixed-degree
Chebyshev (`1 + 2(degree − 1)`); per level prolongation and Chebyshev(ν₂) (`1 + 2ν₂`).
"""
function bottom_phases(K, nu1, nu2, degree)
    (K - 1) * (2nu1 + 1) + 2degree - 1 + (K - 1) * (2nu2 + 1)
end

"""
Phase `ph` of the bottom (see `bottom_phases`): `(kind, level, k, coarse)`, `k` the
Chebyshev step (on the coarsest interval when `coarse`, else on `[λ/4, λ]`, λ = 2).
Arithmetic on `ph` (no schedule table: a long tuple indexed at run time would allocate).
"""
@inline function _phase(ph::Int32, K::Int32, nu1::Int32, nu2::Int32, degree::Int32)
    o = one(Int32)
    D, C, U = Int32(2) * nu1 + o, Int32(2) * degree - o, Int32(2) * nu2 + o
    j = ph - o
    if j < (K - o) * D                                      # down
        l, i = divrem(j, D)
        i == zero(Int32) && return _ph(KZ, l + o, o, false)
        i == D - o && return _ph(KRT, l + o, o, false)
        i == D - Int32(2) && return _ph(KRS, l + o, o, false)
        return _ph(isodd(i) ? KR : KU, l + o, (i >> 1) + o, false)
    end
    j -= (K - o) * D
    if j < C                                                # coarsest
        j == zero(Int32) && return _ph(KZ, K, o, true)
        return _ph(isodd(j) ? KR : KU, K, (j >> 1) + o, true)
    end
    u, i = divrem(j - C, U)                                 # up
    i == zero(Int32) && return _ph(KP, K - o - u, o, false)
    return _ph(isodd(i) ? KR : KU, K - o - u, i >> 1, false)
end
@inline _ph(kind, l, k, coarse::Bool) = (Int32(kind), Int32(l), Int32(k), coarse)

"""
    bottom!(ph, g, t, lds, S, P, G)

The bottom V-cycle over levels `ℓB…L` as one workgroup: phase `ph` runs step `_phase(ph)`
(see `bottom_phases`) with item `t` on sites `t, t + G.wg, …`. `S` holds
per-level tuples `(acts, ws, ss, sboxs, sints, xs, bs, rs, ds)` (`ws[a][l]`: faces per axis), the device scalars and the
coarsest Gershgorin interval `gb`; gated on the `done` flag (every phase returns at once,
the barriers stay uniform).
"""
function bottom!(ph, g, t, lds, S, P, G)
    acts, ws, ss, sbs, sis, xs, bs, rs, ds, scal, gb = S
    T = eltype(xs[1])
    @inbounds scal[1] != zero(T) && return nothing                 # DONE is scal[1]
    kind, l, k, coarse = _phase(Int32(ph), Int32(length(G.dims)), Int32(G.nu1),
        Int32(G.nu2), Int32(G.degree))
    dims, per, W = G.dims, G.per, Int32(G.wg)
    @inbounds lo, hi = coarse ? (gb[1], gb[2]) : (T(0.5), T(2))   # gb has 2 entries
    c1, c2 = _coarse_coefs(k, lo, hi)
    @inbounds active, s, sb, si = acts[l], ss[l], sbs[l], sis[l]       # l ≤ K
    w = ntuple(a -> (@inbounds ws[a][l]), length(ws))               # l ≤ K
    @inbounds x, b, r, d, dl = xs[l], bs[l], rs[l], ds[l], dims[l]
    n = Int32(length(x))
    if kind == KRT
        @inbounds bc, dc = bs[l + 1], dims[l + 1]                  # KRT has l < K
        for J in t:W:Int32(length(bc))
            _restrict_site!(bc, r, J, dl, dc)
        end
        return nothing
    end
    if kind == KP
        @inbounds xc, dp = xs[l + 1], dims[l + 1]                  # KP has l < K
        for i in t:W:n
            X = _coords(i, dl)
            Pc = ntuple(
                e -> dl[e] == one(Int32) ? X[e] :
                     min((X[e] - one(Int32)) >> 1 + one(Int32), dp[e]),
                length(X))
            @inbounds active[i] != 0 && (x[i] += xc[_lin(Pc, dp)])   # i ≤ n
        end
        return nothing
    end
    for i in t:W:n                                                  # i ≤ n = length(x)
        if kind == KZ
            rr, D = _resid(i, active, w, s, sb, si, x, b, dl, per)
            @inbounds bi = active[i] != 0 ? b[i] : zero(T)
            v = D == zero(T) ? zero(T) : c2 * bi / D               # from x = 0: r = b
            @inbounds d[i], x[i] = v, v
        elseif kind == KR
            rr, D = _resid(i, active, w, s, sb, si, x, b, dl, per)
            @inbounds r[i] = D == zero(T) ? zero(T) : rr / D       # a singular row (s = 0)
        elseif kind == KU
            @inbounds d[i] = c1 * d[i] + c2 * r[i]
            @inbounds x[i] += d[i]
        else                                                        # KRS
            rr, _ = _resid(i, active, w, s, sb, si, x, b, dl, per)
            @inbounds r[i] = rr
        end
    end
    return nothing
end

"""
Coarse site `J`: `bc[J] = Σ` of the fine residual over its children.
"""
@inline function _restrict_site!(bc, rf, J, dimsf, dimsc)
    X = _coords(J, dimsc)
    acc = zero(eltype(bc))
    for ci in CartesianIndices(ntuple(
        e -> range(_kids(X[e], dimsf[e], dimsc[e])...), length(X)))
        @inbounds acc += rf[_lin(Int32.(Tuple(ci)), dimsf)]        # children of J are in rf
    end
    @inbounds bc[J] = acc                                           # J ≤ length(bc)
    return nothing
end

"""
Gershgorin bounds `(1 − off/D, 1 + off/D)` of D⁻¹A at site `i` (`(floatmax, 0)` at a masked
or singular row).
"""
@inline function _gersh_site(i::Int32, active, w, s, sb, si, dims, per)
    T = eltype(s)
    @inbounds active[i] != 0 || return floatmax(T), zero(T)
    X = _coords(i, dims)
    @inbounds D = s[i] + sb[i] + si[i]
    off = zero(T)
    for a in 1:length(dims), σ in (1, -1)

        Y, ok = _nb(X, a, σ, dims, per)
        ok || continue
        j = _lin(Y, dims)
        @inbounds wf = σ > 0 ? w[a][i] : w[a][j]
        D += wf
        @inbounds active[j] != 0 && j != i && (off += wf)
    end
    if length(w) > length(dims)                     # hexagonal: the faces to ±(e₁ − e₂)
        for σ in (1, -1)
            Y, ok = _nbo(X, (σ, -σ), dims, per)
            ok || continue
            j = _lin(Y, dims)
            @inbounds wf = σ > 0 ? w[3][i] : w[3][j]
            D += wf
            @inbounds active[j] != 0 && j != i && (off += wf)
        end
    end
    D == zero(T) && return floatmax(T), zero(T)
    return one(T) - off / D, one(T) + off / D
end

"""
    gershgorin!(ph, g, t, lds, S, P, G)

The coarsest level's Gershgorin interval `[lo, hi]` of D⁻¹A (lo ≥ 0) into `gb[1:2]`, as one
workgroup in 9 phases (strided partials, then the halving tree). Run in the rebuild.
"""
function gershgorin!(ph, g, t, lds, S, P, G)
    active, w, s, sb, si, gb = S
    T = eltype(s)
    W = Int32(G.wg)
    if ph == one(ph)
        lo, hi = floatmax(T), zero(T)
        for i in t:W:Int32(length(s))
            a, b = _gersh_site(i, active, w, s, sb, si, G.dims, G.per)
            lo, hi = min(lo, a), max(hi, b)
        end
        @inbounds lds[t], lds[t + W] = lo, hi                     # t ≤ W, lds has 2W
    else
        stride = W >> (ph - one(ph))
        if t <= stride
            @inbounds lds[t] = min(lds[t], lds[t + stride])        # t + stride ≤ W
            @inbounds lds[t + W] = max(lds[t + W], lds[t + stride + W])
        end
        if (ph == Int32(9)) & (t == one(t))
            @inbounds lo = max(lds[1], zero(T))
            @inbounds gb[1], gb[2] = lo, max(lds[1 + W], lo)       # gb has 2 entries
        end
    end
    return nothing
end
