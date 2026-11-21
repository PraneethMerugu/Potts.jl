# The per-run recorder of the Fortuna FULL runs (`run_full.jl` includes it after
# `protocol.jl`, whose `KIND` it reads).
#
# `record_run` steps one run and records, every `every` MCS, the protocol's quantities plus
# the compartment centroids and a lid flag (the track), and every `DIAG_EVERY` MCS two
# info-only diagnostics (the diagnostic series):
#
# - Seam contact. The lateral box is int(8R) and the lamellipodium front runs well ahead of
#   the nucleus, so in a long run it may touch the cell's own rear across the periodic xy
#   seam. The cell's sites (cytoplasm, lamellipodium, nucleus) are given one image each by a
#   breadth-first walk over face neighbors from the nucleus. Two cell sites within 1.5 sites
#   of each other (face or edge neighbors, d = 1 or √2) whose images disagree with the
#   lattice step between them touch only through another periodic image, so the cell closes
#   a loop around the periodic box. A sample is flagged when it has such a pair (`seam`, the
#   number of pairs); `direct` counts the lamellipodium–body pairs within 1.5 sites that one
#   image explains. `lam_unreached` counts the lamellipodium sites the walk from the nucleus
#   never reaches (fragments cut off from the body: a cheap detachment signal).
# - Nucleus shape. The ratio of the smallest to the largest eigenvalue of the nucleus sites'
#   covariance tensor, unwrapped across the seam by minimum image (1 for a ball, → 0 for a
#   rod or a disc), and the exposed nucleus faces over 3/2·(36π)^(1/3)·V^(2/3), the expected
#   face count of a digitized ball of V sites, so a digitized ball reads ≈ 1 and a rougher
#   shape more.
using LinearAlgebra: Symmetric, eigvals
using CodecZlib: GzipCompressorStream

const KIND = FortunaProtocol.KIND
const DIAG_EVERY = 50                                   # MCS
const FACES = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
const NEAR = Tuple(o for o in Iterators.product(-1:1, -1:1, -1:1) if 1 <= count(!=(0), o) <= 2)   # d = 1, √2
const BALL_FACES = 1.5 * cbrt(36π)                      # faces of a digitized ball per V^(2/3)

"""
The mean z of the sites of each compartment (cytoplasm, lamellipodium, nucleus; z is
closed, so a plain mean), NaN for an absent one: one pass over σ.
"""
function zcentroids(σ::AbstractArray{<:Integer, 3}, kd)
    s = zeros(3)
    n = zeros(Int, 3)
    for I in CartesianIndices(σ)
        c = σ[I]
        c > 0 || continue
        k = kd[c]
        j = k == KIND.cytoplasm ? 1 : k == KIND.lamellipodium ? 2 : k == KIND.nucleus ? 3 : 0
        j == 0 && continue
        s[j] += I[3]
        n[j] += 1
    end
    return ntuple(j -> n[j] > 0 ? s[j] / n[j] : NaN, 3)
end

# the site one step `o` from `x` (periodic x, y; closed z) and the image shift of the step
# (−1, 0, +1 per periodic axis); `nothing` past a z wall
function _step(x::NTuple{3, Int}, o, dims)
    z = x[3] + o[3]
    1 <= z <= dims[3] || return nothing
    xs = x[1] + o[1]
    ys = x[2] + o[2]
    wx = xs < 1 ? -1 : xs > dims[1] ? 1 : 0
    wy = ys < 1 ? -1 : ys > dims[2] ? 1 : 0
    return ((mod1(xs, dims[1]), mod1(ys, dims[2]), z), (wx, wy))
end

host_array(a) = a isa Array ? a : Array(a)
_cellkind(k) = k == KIND.cytoplasm || k == KIND.lamellipodium || k == KIND.nucleus

"""
    seam_contacts(σ, kd) -> (seam, direct, lam_unreached)

`seam`: the pairs of cell sites within 1.5 sites whose images, from a breadth-first walk over
face neighbors from the nucleus, disagree with the lattice step between them (the cell
touches itself across the periodic seam). `direct`: the lamellipodium–body pairs within 1.5
sites that the images explain. `lam_unreached`: the lamellipodium sites that the walk from
the nucleus does not reach over face neighbors of cell sites (fragments cut off from the
body; a cheap detachment signal). See the file header.
"""
function seam_contacts(σ::AbstractArray{<:Integer, 3}, kd)
    dims = size(σ)
    img = Dict{NTuple{3, Int}, NTuple{2, Int}}()       # site => image counts (x, y)
    starts = NTuple{3, Int}[]
    for I in CartesianIndices(σ)
        c = σ[I]
        (c > 0 && _cellkind(kd[c])) || continue
        kd[c] == KIND.nucleus ? pushfirst!(starts, Tuple(I)) : push!(starts, Tuple(I))
    end
    queue = NTuple{3, Int}[]
    lam_unreached = -1
    for s in starts                                     # the nucleus first, then any unreached piece
        if lam_unreached < 0 && !(kd[σ[s...]] == KIND.nucleus)
            # the walk from the nucleus is done: count the lamellipodium sites it missed
            lam_unreached = count(x -> !haskey(img, x) && kd[σ[x...]] == KIND.lamellipodium, starts)
        end
        haskey(img, s) && continue
        img[s] = (0, 0)
        push!(queue, s)
        while !isempty(queue)
            x = popfirst!(queue)
            wx = img[x]
            for o in FACES
                st = _step(x, o, dims)
                st === nothing && continue
                y, w = st
                c = σ[y...]
                (c > 0 && _cellkind(kd[c]) && !haskey(img, y)) || continue
                img[y] = (wx[1] + w[1], wx[2] + w[2])
                push!(queue, y)
            end
        end
    end
    seam = direct = 0
    for (x, wx) in img
        islam = kd[σ[x...]] == KIND.lamellipodium
        for o in NEAR
            st = _step(x, o, dims)
            st === nothing && continue
            y, w = st
            haskey(img, y) || continue
            if img[y] != (wx[1] + w[1], wx[2] + w[2])
                seam += 1
            elseif islam && kd[σ[y...]] != KIND.lamellipodium
                direct += 1
            end
        end
    end
    lam_unreached < 0 && (lam_unreached = 0)            # only nucleus sites: nothing to miss
    return (seam ÷ 2, direct, lam_unreached)            # every inconsistent pair is seen from both ends
end

"""
    fused_pass(σ, kd) -> (z, lid, lam_cyto)

One pass over σ for the fast recorder: the z centroids of `zcentroids` (sums of integer z,
exact in Float64 in any order, so the same values), the lid flag (a lamellipodium site at
z = L_z − 1) and the `lam_cyto` observable (lamellipodium sites with a face neighbor of kind
cytoplasm; one cell per run, so the cluster sum is the lattice sum). The planes z = 1 and
z = L_z are skipped: the substrate and the lid own them for the whole run.
"""
function fused_pass(σ::Array{<:Integer, 3}, kd::AbstractVector)
    dims = size(σ)
    Lx, Ly, Lz = dims
    cyto, lamk, nuc = KIND.cytoplasm, KIND.lamellipodium, KIND.nucleus
    sc = sl = sn = 0
    nc = nl = nn = 0
    lid = false
    lc = 0
    for z in 2:(Lz - 1), y in 1:Ly, x in 1:Lx
        c = @inbounds σ[x, y, z]                        # in bounds: x, y, z range over size(σ)
        c > 0 || continue
        k = kd[c]
        if k == cyto
            sc += z
            nc += 1
        elseif k == nuc
            sn += z
            nn += 1
        elseif k == lamk
            sl += z
            nl += 1
            z == Lz - 1 && (lid = true)
            for o in FACES
                st = _step((x, y, z), o, dims)
                st === nothing && continue
                d = σ[st[1]...]
                if d > 0 && kd[d] == cyto
                    lc += 1
                    break
                end
            end
        end
    end
    zc(s, n) = n > 0 ? Float64(s) / n : NaN
    return ((zc(sc, nc), zc(sl, nl), zc(sn, nn)), lid, Float64(lc))
end

"""
    nucleus_shape(σ, kd) -> (eig_ratio, surface)

The smallest over the largest eigenvalue of the nucleus sites' covariance tensor (unwrapped
by minimum image around one nucleus site), and the exposed nucleus faces over the face count
of a digitized ball of the same volume (see the file header). NaN for no nucleus.
"""
function nucleus_shape(σ::AbstractArray{<:Integer, 3}, kd)
    dims = size(σ)
    pts = NTuple{3, Float64}[]
    faces = 0
    ref = (0, 0)
    isnuc(c) = c > 0 && kd[c] == KIND.nucleus
    for I in CartesianIndices(σ)
        isnuc(σ[I]) || continue
        x = Tuple(I)
        isempty(pts) && (ref = (x[1], x[2]))
        dx = x[1] - ref[1]
        dy = x[2] - ref[2]
        push!(pts, (ref[1] + dx - dims[1] * round(dx / dims[1]), ref[2] + dy - dims[2] * round(dy / dims[2]), Float64(x[3])))
        for o in FACES
            st = _step(x, o, dims)
            faces += (st === nothing || !isnuc(σ[st[1]...]))
        end
    end
    n = length(pts)
    n > 1 || return (NaN, NaN)
    m = ntuple(d -> sum(p[d] for p in pts) / n, 3)
    C = [sum((p[a] - m[a]) * (p[b] - m[b]) for p in pts) / n for a in 1:3, b in 1:3]
    ev = eigvals(Symmetric(C))
    return (ev[end] > 0 ? ev[1] / ev[end] : NaN, faces / (BALL_FACES * n^(2 / 3)))
end

"""
    record_run(prob; T, every, L, Lz, diag = true, fast = true) -> (rec, dg)

One run recorded every `every` MCS from t = 0 by stepping the integrator, as the
protocol's `record`, plus the cytoplasm centroid in x and y (from the
nucleus centroid and Π_CN−N, wrapped into [1, L + 1)), the z centroids of the three
compartments, and a lid flag per sample: a lamellipodium site at z = L_z − 1. With
`diag = true`, also the seam-contact and nucleus-shape series every `DIAG_EVERY` MCS.

`fast = true` (the default) reads `lam_cyto`, the z centroids and the lid flag in one pass
over σ (`fused_pass`) instead of the `lam_cyto` observable (a fold over the whole lattice,
most of a sample's cost) and a separate scan; the six cheap centroid observables are read
with `observe` as before. `check_recorder` returns whether both paths record identical values.
"""
function record_run(prob; T, every, L, Lz, diag::Bool = true, fast::Bool = true)
    integ = init(
        prob, SequentialCPM(); save_everystep = false, save_start = false, save_end = false
    )
    rec = (
        t = Int[], nx = Float64[], ny = Float64[], lx = Float64[], ly = Float64[], Πx = Float64[], Πy = Float64[],
        lam_cyto = Float64[], vc = Float64[], vn = Float64[], vl = Float64[], alive = Bool[], births = Float64[],
        cx = Float64[], cy = Float64[], cz = Float64[], lz = Float64[], nz = Float64[], lid = Bool[],
    )
    dg = (
        t = Int[], seam = Int[], direct = Int[], flag = Bool[], lam_unreached = Int[], eig_ratio = Float64[],
        surface = Float64[],
    )
    foreach(v -> sizehint!(v, T ÷ every + 1), rec)
    diag && foreach(v -> sizehint!(v, T ÷ DIAG_EVERY + 1), dg)
    function sample!(t, u)
        kd, vol = Array(cell_kinds(u)), Array(volumes(u))
        vk(k) = sum((vol[c] for c in eachindex(vol) if vol[c] > 0 && kd[c] == k); init = 0)
        σ = host_array(ownership(u))
        push!(rec.t, t)
        for o in (:nx, :ny, :lx, :ly, :Πx, :Πy)
            push!(getfield(rec, o), observe(prob, o, u)[1])
        end
        if fast
            z, lid, lc = fused_pass(σ, kd)
            push!(rec.lam_cyto, lc)
        else
            push!(rec.lam_cyto, observe(prob, :lam_cyto, u)[1])
            z = zcentroids(σ, kd)
            lid = any(c -> c > 0 && kd[c] == KIND.lamellipodium, view(σ, :, :, Lz - 1))
        end
        push!(rec.vc, vk(KIND.cytoplasm))
        push!(rec.vn, vk(KIND.nucleus))
        push!(rec.vl, vk(KIND.lamellipodium))
        push!(rec.alive, vk(KIND.lamellipodium) > 0)
        push!(rec.births, observe(prob, :lam_births, u)[1])
        vc, vn = rec.vc[end], rec.vn[end]
        for (col, rn, Π) in ((rec.cx, rec.nx[end], rec.Πx[end]), (rec.cy, rec.ny[end], rec.Πy[end]))
            push!(col, vc > 0 ? 1 + mod(rn + Π * (vc + vn) / vc - 1, L) : NaN)
        end
        push!(rec.cz, z[1])
        push!(rec.lz, z[2])
        push!(rec.nz, z[3])
        return push!(rec.lid, lid)
    end
    function diagnose!(t, u)
        kd = Array(cell_kinds(u))
        σ = host_array(ownership(u))
        seam, direct, unreached = seam_contacts(σ, kd)
        ratio, surface = nucleus_shape(σ, kd)
        push!(dg.t, t)
        push!(dg.seam, seam)
        push!(dg.direct, direct)
        push!(dg.flag, seam > 0)
        push!(dg.lam_unreached, unreached)
        push!(dg.eig_ratio, ratio)
        return push!(dg.surface, surface)
    end
    sample!(0, prob.u0)
    diag && diagnose!(0, prob.u0)
    for t in 1:T
        step!(integ)
        t % every == 0 && sample!(t, integ.u)
        diag && t % DIAG_EVERY == 0 && diagnose!(t, integ.u)
    end
    return rec, dg
end

"""
    check_recorder(prob; T, L, Lz) -> Bool

Record `T` MCS of `prob` every MCS with the fast and the observe-based path (same seed, so
the same run) and return whether every recorded column is identical (`isequal`, so NaN
equals NaN).
"""
function check_recorder(prob; T, L, Lz)
    a, _ = record_run(prob; T, every = 1, L, Lz, diag = false, fast = true)
    b, _ = record_run(prob; T, every = 1, L, Lz, diag = false, fast = false)
    return all(k -> isequal(getfield(a, k), getfield(b, k)), keys(a))
end

"""The per-run summary of a diagnostic series: flagged samples, their fraction, the most
seam pairs in a sample, and the means of the nucleus shape over the second half of the run."""
function diag_summary(dg, T)
    h = findall(>=(T / 2), dg.t)
    fin(v) = (w = filter(isfinite, v); isempty(w) ? NaN : sum(w) / length(w))
    return (;
        samples = length(dg.t), flagged = count(dg.flag), fraction = isempty(dg.t) ? NaN : count(dg.flag) / length(dg.t),
        max_pairs = isempty(dg.seam) ? 0 : maximum(dg.seam),
        unreached_mean = isempty(dg.t) ? NaN : sum(dg.lam_unreached) / length(dg.t),
        unreached_max = isempty(dg.t) ? 0 : maximum(dg.lam_unreached), eig_ratio = fin(dg.eig_ratio[h]),
        surface = fin(dg.surface[h]),
    )
end

const TRACK_COLS = (:t, :nx, :ny, :nz, :lx, :ly, :lz, :cx, :cy, :cz, :Πx, :Πy, :lam_cyto, :vc, :vn, :vl, :alive, :births, :lid)
const DIAG_COLS = (:t, :seam, :direct, :flag, :lam_unreached, :eig_ratio, :surface)
fmt(x::Bool) = x ? "1" : "0"
fmt(x::Integer) = string(x)
fmt(x::Real) = isnan(x) ? "NaN" : isinteger(x) && abs(x) < 1.0e9 ? string(Int(x)) : string(Float32(x))
# gzip TSV; read with `readdlm(GzipDecompressorStream(open(path)), '\t'; header = true)`
function write_series(path, rec, cols)
    tmp = path * ".tmp"
    open(GzipCompressorStream, tmp, "w") do io
        println(io, join(cols, '\t'))
        for j in eachindex(rec.t)
            println(io, join((fmt(getfield(rec, c)[j]) for c in cols), '\t'))
        end
    end
    return mv(tmp, path; force = true)
end
