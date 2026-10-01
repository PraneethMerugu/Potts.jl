# Peak finding: a port of SciPy 1.7.x `scipy.signal.find_peaks`, `peak_prominences` and
# `peak_widths` (scipy/signal/_peak_finding.py, scipy/signal/_peak_finding_utils.pyx), and of
# the NumPy 1.21 `argsort` they rely on (numpy/core/src/npysort/quicksort.c.src
# `aquicksort_<type>`, heapsort.c.src `aheapsort_<type>`), per D-069. Read from the sources
# as text; indices are shifted to 1-based, and interpolated positions are computed on the
# 0-based offsets first, so every floating-point value matches SciPy's before the shift, for
# builds that do not fuse multiply-adds (e.g. x86_64 wheels; an arm64 SciPy build fuses
# `x[peak] - prom*rel_height`, so its widths can differ in the last bit).
#
# SciPy is distributed under the following license:
#
#   Copyright (c) 2001-2002 Enthought, Inc. 2003-2021, SciPy Developers.
#   All rights reserved.
#
# NumPy is distributed under the following license:
#
#   Copyright (c) 2005-2021, NumPy Developers.
#   All rights reserved.
#
# Both use the same terms:
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions
#   are met:
#
#   1. Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
#   2. Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials provided
#      with the distribution.
#
#   3. Neither the name of the copyright holder nor the names of its
#      contributors may be used to endorse or promote products derived
#      from this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# SciPy converts every signal to a contiguous float64 array (`_arg_x_as_expected`).
function _signal(x)
    x isa AbstractVector || throw(ArgumentError("expected a 1-D signal, got a $(typeof(x))"))
    return convert(Vector{Float64}, collect(x))
end

function _peak_indices(x, peaks)
    p = convert(Vector{Int}, collect(peaks))
    for q in p
        1 <= q <= length(x) || throw(ArgumentError("peak $q is not a valid index for `x`"))
    end
    return p
end

# `_local_maxima_1d`: strict local maxima and plateau midpoints (rounded down); the first
# and last samples are never peaks.
function _local_maxima(x::Vector{Float64})
    mids = Int[]
    i, imax = 2, length(x)                  # SciPy: i = 1, i_max = len - 1 (0-based)
    while i < imax
        if x[i - 1] < x[i]
            ahead = i + 1
            while ahead < imax && x[ahead] == x[i]
                ahead += 1
            end
            if x[ahead] < x[i]
                push!(mids, (i + ahead - 1) ÷ 2)   # (left + right) ÷ 2, right = ahead − 1
                i = ahead
            end
        end
        i += 1
    end
    return mids
end

# ---------------------------------------------------------------------------------------------
# NumPy 1.21 `np.argsort(v)` for float64 (default kind "quicksort"): introsort with
# median-of-3 partitioning, insertion sort for partitions of ≤ 16 elements and a heapsort
# fallback once the depth budget 2⌊log₂ n⌋ is spent. It is NOT stable: `find_peaks`'s tie
# order under `distance` depends on it. Positions `pl`, `pr` index `t`; `t` holds 1-based
# indices into `v`.

_np_lt(a, b) = a < b || (b != b && a == a)            # DOUBLE_LT: NaN sorts last
function _np_msb(n)                                   # npy_get_msb: ⌊log₂ n⌋, 0 for n ≤ 1
    k = 0
    while n > 1
        n >>= 1
        k += 1
    end
    return k
end
function _swap!(t, i, j)
    t[i], t[j] = t[j], t[i]
    return nothing
end

# `aheapsort_<type>` on t[off : off + n − 1]; `a[i]` is t[off + i − 1] (NumPy's `tosort - 1`).
function _np_aheapsort!(t, v, off, n)
    a = off - 1
    l = n >> 1
    while l > 0
        tmp = t[a + l]
        i, j = l, l << 1
        while j <= n
            j < n && _np_lt(v[t[a + j]], v[t[a + j + 1]]) && (j += 1)
            _np_lt(v[tmp], v[t[a + j]]) || break
            t[a + i] = t[a + j]
            i = j
            j += j
        end
        t[a + i] = tmp
        l -= 1
    end
    while n > 1
        tmp = t[a + n]
        t[a + n] = t[a + 1]
        n -= 1
        i, j = 1, 2
        while j <= n
            j < n && _np_lt(v[t[a + j]], v[t[a + j + 1]]) && (j += 1)
            _np_lt(v[tmp], v[t[a + j]]) || break
            t[a + i] = t[a + j]
            i = j
            j += j
        end
        t[a + i] = tmp
    end
    return t
end

const _NP_SMALL_QUICKSORT = 15

function _np_argsort(v::AbstractVector{Float64})
    t = collect(1:length(v))
    pl, pr = 1, length(v)
    stack = Int[]                               # (pl, pr) pairs
    depths = Int[]
    cdepth = 2 * _np_msb(length(v))
    while true
        if cdepth < 0
            _np_aheapsort!(t, v, pl, pr - pl + 1)
        else
            while pr - pl > _NP_SMALL_QUICKSORT
                pm = pl + ((pr - pl) >> 1)
                _np_lt(v[t[pm]], v[t[pl]]) && _swap!(t, pm, pl)
                _np_lt(v[t[pr]], v[t[pm]]) && _swap!(t, pr, pm)
                _np_lt(v[t[pm]], v[t[pl]]) && _swap!(t, pm, pl)
                vp = v[t[pm]]
                pi, pj = pl, pr - 1
                _swap!(t, pm, pj)
                while true
                    pi += 1                     # do ++pi while v[t[pi]] < vp
                    while _np_lt(v[t[pi]], vp)
                        pi += 1
                    end
                    pj -= 1                     # do --pj while vp < v[t[pj]]
                    while _np_lt(vp, v[t[pj]])
                        pj -= 1
                    end
                    pi >= pj && break
                    _swap!(t, pi, pj)
                end
                _swap!(t, pi, pr - 1)
                # push the larger partition, continue with the smaller
                if pi - pl < pr - pi
                    push!(stack, pi + 1, pr)
                    pr = pi - 1
                else
                    push!(stack, pl, pi - 1)
                    pl = pi + 1
                end
                cdepth -= 1
                push!(depths, cdepth)
            end
            for p in (pl + 1):pr                # insertion sort
                vi = t[p]
                vv = v[vi]
                pj = p
                while pj > pl && _np_lt(vv, v[t[pj - 1]])
                    t[pj] = t[pj - 1]
                    pj -= 1
                end
                t[pj] = vi
            end
        end
        isempty(stack) && break
        pr = pop!(stack)
        pl = pop!(stack)
        cdepth = pop!(depths)
    end
    return t
end

# `_select_by_peak_distance`: peaks in NumPy argsort order of `priority`, from the end
# (highest first); each kept peak removes the peaks closer than ceil(distance) samples.
function _select_by_peak_distance(peaks, priority, distance)
    n = length(peaks)
    d = ceil(Float64(distance))
    keep = trues(n)
    order = _np_argsort(priority)
    for i in n:-1:1
        j = order[i]
        keep[j] || continue
        k = j - 1
        while 1 <= k && peaks[j] - peaks[k] < d
            keep[k] = false
            k -= 1
        end
        k = j + 1
        while k <= n && peaks[k] - peaks[j] < d
            keep[k] = false
            k += 1
        end
    end
    return keep
end

# `_peak_prominences` with `wlen = None`: the lowest sample on each side before a higher
# one (ties keep the base nearest the peak).
function _prominences(x::Vector{Float64}, peaks::Vector{Int})
    n = length(peaks)
    prom = Vector{Float64}(undef, n)
    lbase = Vector{Int}(undef, n)
    rbase = Vector{Int}(undef, n)
    zero_prom = false
    for (k, peak) in enumerate(peaks)
        i, lb, lmin = peak, peak, x[peak]
        while 1 <= i && x[i] <= x[peak]
            if x[i] < lmin
                lmin, lb = x[i], i
            end
            i -= 1
        end
        i, rb, rmin = peak, peak, x[peak]
        while i <= length(x) && x[i] <= x[peak]
            if x[i] < rmin
                rmin, rb = x[i], i
            end
            i += 1
        end
        prom[k] = x[peak] - max(lmin, rmin)
        prom[k] == 0 && (zero_prom = true)
        lbase[k], rbase[k] = lb, rb
    end
    zero_prom && @warn "some peaks have a prominence of 0"
    return prom, lbase, rbase
end

# `_peak_widths`: walk out from the peak while the signal is above the reference height (not
# past the bases), then interpolate linearly. Positions are 0-based until the return, as in
# SciPy, so widths match a non-FMA SciPy build bit for bit (see the file header).
function _widths(x::Vector{Float64}, peaks, rel_height, prom, lbase, rbase)
    rel_height < 0 && throw(ArgumentError("`rel_height` must be greater or equal to 0.0"))
    n = length(peaks)
    widths = Vector{Float64}(undef, n)
    heights = Vector{Float64}(undef, n)
    lips = Vector{Float64}(undef, n)
    rips = Vector{Float64}(undef, n)
    zero_width = false
    for (k, peak) in enumerate(peaks)
        lb, rb = lbase[k], rbase[k]
        (1 <= lb <= peak <= rb <= length(x)) || throw(ArgumentError("prominence data is invalid for peak $peak"))
        height = x[peak] - prom[k] * rel_height
        i = peak
        while lb < i && height < x[i]
            i -= 1
        end
        lip = Float64(i - 1)
        x[i] < height && (lip += (height - x[i]) / (x[i + 1] - x[i]))
        i = peak
        while i < rb && height < x[i]
            i += 1
        end
        rip = Float64(i - 1)
        x[i] < height && (rip -= (height - x[i]) / (x[i - 1] - x[i]))
        widths[k] = rip - lip
        widths[k] == 0 && (zero_width = true)
        heights[k] = height
        lips[k], rips[k] = lip + 1, rip + 1
    end
    zero_width && @warn "some peaks have a width of 0"
    return widths, heights, lips, rips
end

"""
    find_peaks(x; distance = nothing, prominence = nothing, width = nothing, rel_height = 0.5)
        -> Vector{Int}

Peaks of the signal `x`, as SciPy 1.7's `scipy.signal.find_peaks` finds them, with 1-based
indices.

1. Local maxima: samples higher than both neighbours. A flat top (a plateau) counts once, at
   its midpoint `(left + right) ÷ 2`. The first and last samples are never peaks.
2. `distance` (≥ 1): peaks are taken from the highest down, and each kept peak removes the
   peaks less than `ceil(distance)` samples from it. Equal heights are taken in the order of
   NumPy's (unstable) default `argsort`, ported exactly: for 16 peaks or fewer the rightmost
   comes first; for more it depends on the introsort partitioning.
3. `prominence`: keep the peaks with [`peak_prominences`](@ref) ≥ `prominence`.
4. `width`: keep the peaks with [`peak_widths`](@ref) at `rel_height` ≥ `width`.

The filters run in that order, each on the survivors of the previous one. SciPy's `height`,
`threshold`, `plateau_size` and `wlen` options are not ported (`wlen` is always `None`).
"""
function find_peaks(x; distance = nothing, prominence = nothing, width = nothing, rel_height = 0.5)
    distance !== nothing && distance < 1 && throw(ArgumentError("`distance` must be greater or equal to 1"))
    xs = _signal(x)
    peaks = _local_maxima(xs)
    if distance !== nothing
        peaks = peaks[_select_by_peak_distance(peaks, xs[peaks], distance)]
    end
    (prominence === nothing && width === nothing) && return peaks
    prom, lb, rb = _prominences(xs, peaks)
    if prominence !== nothing
        k = prominence .<= prom
        peaks, prom, lb, rb = peaks[k], prom[k], lb[k], rb[k]
    end
    if width !== nothing
        w, = _widths(xs, peaks, rel_height, prom, lb, rb)
        peaks = peaks[width .<= w]
    end
    return peaks
end

"""
    peak_prominences(x, peaks) -> (; prominences, left_bases, right_bases)

The prominence of each peak (SciPy 1.7's `scipy.signal.peak_prominences` with `wlen = None`,
1-based). On each side, scan outwards from the peak until a higher sample or the end of the
signal, and take the lowest sample seen as that side's base (ties keep the base nearest the
peak). The prominence is the peak height minus the higher of the two bases.
"""
function peak_prominences(x, peaks)
    xs = _signal(x)
    prom, lb, rb = _prominences(xs, _peak_indices(xs, peaks))
    return (; prominences = prom, left_bases = lb, right_bases = rb)
end

"""
    peak_widths(x, peaks; rel_height = 0.5, prominence_data = nothing)
        -> (; widths, width_heights, left_ips, right_ips)

The width of each peak at `rel_height` of its prominence (SciPy 1.7's
`scipy.signal.peak_widths`, 1-based). The reference height is `x[peak] − prominence ×
rel_height`; the width runs between the points where the signal crosses it on either side,
interpolated linearly and never past the prominence bases. `left_ips` and `right_ips` are
those crossing points (fractional indices). `prominence_data` is the output of
[`peak_prominences`](@ref), computed when not given.
"""
function peak_widths(x, peaks; rel_height = 0.5, prominence_data = nothing)
    xs = _signal(x)
    pk = _peak_indices(xs, peaks)
    pd = prominence_data === nothing ? peak_prominences(xs, pk) : prominence_data
    w, h, l, r = _widths(xs, pk, rel_height, pd.prominences, pd.left_bases, pd.right_bases)
    return (; widths = w, width_heights = h, left_ips = l, right_ips = r)
end

"""
    merge_peaks(peaks, gap) -> Vector{Int}

Thin sorted peak positions: keep a peak only if it lies more than `gap` samples after the
last kept one. The first peak is always kept.
"""
function merge_peaks(peaks, gap)
    out = Int[]
    for p in peaks
        (isempty(out) || p - last(out) > gap) && push!(out, p)
    end
    return out
end
