# Foam observables of reproduction 04 (Jiang, Swart, Saxena, Asipauskas & Glazier, Phys.
# Rev. E 59, 5819 (1999), "04b"; spec docs/design/research/model-specs/04_foam.md §2.8,
# D-186, D-187): the stored energy φ (Eq. 8), side counts and topology moments, per-MCS T1
# detection from neighbour lists, power spectra (Eq. 9) and their exponents, N̄ and the yield
# strain.

# ---------------------------------------------------------------------------------------
# Stored energy φ, Eq. (8)

"""
    stored_energy(σ, lattice::Lattice; neighborhood = NeighborOrder(4), θ = 1) -> Real

Return the stored energy φ of a foam, Eq. (8) of Jiang et al. 1999 (p. 5823;
`docs/design/research/model-specs/04_foam.md` §2.8): φ ≡ Σ_{i,j} θ (1 − δ_{σ_i, σ_j}).

The result is `θ` times the number of unordered neighbor pairs `{i, j}` under
`neighborhood` with `σ_i ≠ σ_j`, each pair counted once. Only φ/φ(0) is plotted in the
paper, so the factor 2 of the ordered sum cancels. The default shell is the paper's
fourth-nearest neighborhood (p. 5822). Pairs wrap on `Periodic()` axes; a pair that leaves
a `Closed()` axis, or the lattice mask, does not exist. Every owner counts, the medium (0)
included. Weights of a `Weighted` relation are ignored.

# Arguments
- `σ::AbstractArray{<:Integer, N}`: the ownership.
- `lattice::Lattice{N}`: a lattice of the size of `σ`. Throws an `ArgumentError` for
  another size.

# Keywords
- `neighborhood = NeighborOrder(4)`: the neighbor pairs. It must be symmetric (each
  offset's negation also in it); throws an `ArgumentError` otherwise.
- `θ::Real = 1`: the energy per unlike pair.

# Returns
- `Real`: φ, of the type of `θ` times an `Int`.

# Examples
```jldoctest
julia> using PottsModels.Analysis, Potts

julia> σ = repeat([1 1 2 2], 4); lattice = Lattice((4, 4); boundary = Closed());

julia> stored_energy(σ, lattice; neighborhood = VonNeumann(1))
4
```

See also [`side_counts`](@ref), [`topology_moments`](@ref).
"""
function stored_energy(
        σ::AbstractArray{<:Integer, N}, lat::Lattice{N}; neighborhood = NeighborOrder(4),
        θ::Real = 1
    ) where {N}
    size(σ) == lat.dims ||
        throw(ArgumentError("stored_energy: σ has size $(size(σ)), the \
            lattice $(lat.dims)"))
    half = _half_offsets(relation(neighborhood, lat).offsets)
    return θ * _unlike_pairs(σ, lat.dims, lat.periodic, lat.mask, half)
end

# The offsets whose first nonzero component is positive: one of each ±o pair. A relation
# that is not symmetric would count some pairs once from one side only.
function _half_offsets(offs::Tuple)
    for o in offs
        all(iszero, o) || map(-, o) in offs ||
            throw(ArgumentError("stored_energy: the neighborhood is not symmetric \
                (offset $o without $(map(-, o)))"))
    end
    return [o for o in offs if _positive(o)]
end
function _positive(o)
    for c in o
        c == 0 || return c > 0
    end
    return false
end

function _unlike_pairs(
        σ, dims::NTuple{N, Int}, periodic::NTuple{N, Bool}, mask, half
    ) where {N}
    n = 0
    # x and y = x + o (wrapped) are checked to be in `σ`
    @inbounds for x in CartesianIndices(σ)
        a = σ[x]
        _in_mask(mask, x) || continue
        for o in half
            inside, y = _neighbor(Tuple(x), o, dims, periodic)
            inside || continue
            yi = CartesianIndex(y)
            _in_mask(mask, yi) || continue
            n += a != σ[yi]
        end
    end
    return n
end
_in_mask(::Nothing, x) = true
_in_mask(mask, x) = @inbounds mask[x]         # mask has the lattice's (= σ's) size
# coordinate `v` wrapped once onto `1:n`
function _wrap_once(v, n)
    v < 1 && return v + n
    v > n && return v - n
    return v
end
# x + o on the lattice: wraps on periodic axes, `inside = false` off a closed one. The
# relation rejects offsets that alias under a periodic axis, so |o_d| < dims_d and one wrap
# suffices.
@inline function _neighbor(x::NTuple{N, Int}, o::NTuple{N, Int32}, dims, periodic) where {N}
    y = ntuple(d -> x[d] + Int(o[d]), Val(N))
    inside = all(ntuple(d -> periodic[d] || 1 <= y[d] <= dims[d], Val(N)))
    w = ntuple(d -> _wrap_once(y[d], dims[d]), Val(N))
    return inside, w
end

# ---------------------------------------------------------------------------------------
# Sides, ρ(n) and moments

"""
    side_counts(σ, lattice::Lattice; neighborhood = VonNeumann(1)) -> Vector{Int}

Return the number of sides `n` of each bubble `1:maximum(σ)`:
`length.(cell_graph(σ, lattice; neighborhood))`.

A bubble's sides are its distinct neighbors (Jiang et al. 1999, p. 5823;
`docs/design/research/model-specs/04_foam.md` §2.8). Edge sharing (`VonNeumann(1)`) is the
default; `Moore(1)` also counts corner-only contacts, which inflates `n`. Contacts wrap on
`Periodic()` axes; a closed boundary is not a side, and neither is the medium.

!!! warning

    The result is indexed by cell number: a number in `1:maximum(σ)` that owns no site is
    not a bubble but still gets an entry, `0`. Drop those entries (keep `n[i]` only for the
    `i` with sites) before passing `n` to [`topology_distribution`](@ref) or
    [`central_moment`](@ref); [`topology_moments`](@ref) does this itself.

# Arguments
- `σ::AbstractArray`: the ownership.
- `lattice::Lattice`: a lattice of the size of `σ`.

# Keywords
- `neighborhood = VonNeumann(1)`: the contacts that make a side.

# Returns
- `Vector{Int}`: the side count of each cell number.

# Examples
```jldoctest
julia> using PottsModels.Analysis, Potts

julia> σ = repeat([1 1 2 2], 4); lattice = Lattice((4, 4); boundary = Closed());

julia> side_counts(σ, lattice)
2-element Vector{Int64}:
 1
 1
```

See also [`topology_distribution`](@ref), [`topology_moments`](@ref).
"""
function side_counts(σ::AbstractArray, lat::Lattice; neighborhood = VonNeumann(1))
    return length.(cell_graph(σ, lat; neighborhood))
end

"""
    topology_distribution(n) -> (; n, ρ)

Return the topology distribution ρ(n) (Jiang et al. 1999, p. 5823;
`docs/design/research/model-specs/04_foam.md` §2.8): the sorted distinct values of `n` and
the fraction ρ of entries taking each.

!!! warning

    Every entry of `n` counts as a bubble. [`side_counts`](@ref) gives a cell number that
    owns no site an entry of `0`; drop such entries first, as [`topology_moments`](@ref)
    does.

# Arguments
- `n::AbstractVector{<:Integer}`: the side counts, for example from [`side_counts`](@ref).
  Throws an `ArgumentError` when empty.

# Returns
- `NamedTuple`: `(; n, ρ)`, with `n::Vector{Int}` and `ρ::Vector{Float64}`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> topology_distribution([5, 6, 6, 7])
(n = [5, 6, 7], ρ = [0.25, 0.5, 0.25])
```

See also [`central_moment`](@ref), [`topology_moments`](@ref).
"""
function topology_distribution(n::AbstractVector{<:Integer})
    isempty(n) && throw(ArgumentError("topology_distribution: no bubbles"))
    s = sort(n)
    vals = Int[]
    ρ = Float64[]
    N = length(s)
    i = 1
    while i <= N
        j = i
        while j < N && s[j + 1] == s[i]
            j += 1
        end
        push!(vals, s[i])
        push!(ρ, (j - i + 1) / N)
        i = j + 1
    end
    return (n = vals, ρ = ρ)
end

"""
    central_moment(x, m = 2) -> AbstractFloat

Return the `m`-th central moment μ_m ≡ Σ_v ρ(v)(v − ⟨v⟩)^m of the values `x` (Jiang et
al. 1999, p. 5823; `docs/design/research/model-specs/04_foam.md` §2.8).

This is the population moment (1/N) Σ_i (x_i − x̄)^m. μ2(n) and μ2(a) of the paper are
`central_moment(n)` and `central_moment(a)`.

# Arguments
- `x::AbstractVector{<:Real}`: the values. Throws an `ArgumentError` when empty.
- `m::Integer = 2`: the order.

# Returns
- `AbstractFloat`: the moment, in `float(eltype(x))` (`Float64` for integer `x`,
  `Float32` for `Float32` `x`).

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> central_moment([5, 6, 6, 7])
0.5
```

See also [`topology_moments`](@ref).
"""
function central_moment(x::AbstractVector{<:Real}, m::Integer = 2)
    isempty(x) && throw(ArgumentError("central_moment: no values"))
    N = length(x)
    x̄ = sum(float, x) / N
    return sum(v -> (v - x̄)^m, x) / N
end

"""
    topology_moments(σ, lattice::Lattice; neighborhood = VonNeumann(1))
        -> (; mean_n, mu2_n, mean_a, mu2_a)

Return ⟨n⟩, μ2(n), ⟨a⟩ and μ2(a) (Jiang et al. 1999, p. 5823;
`docs/design/research/model-specs/04_foam.md` §2.8) over the bubbles of `σ`.

The bubbles are the cell numbers in `1:maximum(σ)` that own at least one site. `n` is from
[`side_counts`](@ref) with `neighborhood`, and `a` is the bubble's site count (areas stay
in sites; any rescaling of μ2(a) is a calibration). The moments are
[`central_moment`](@ref)s.

# Arguments
- `σ::AbstractArray{<:Integer}`: the ownership. Throws an `ArgumentError` when it has no
  bubble.
- `lattice::Lattice`: a lattice of the size of `σ`.

# Keywords
- `neighborhood = VonNeumann(1)`: the contacts that make a side.

# Returns
- `NamedTuple`: `(; mean_n, mu2_n, mean_a, mu2_a)`, each a `Float64`.

# Examples
```jldoctest
julia> using PottsModels.Analysis, Potts

julia> σ = repeat([1 1 2 2], 4); lattice = Lattice((4, 4); boundary = Closed());

julia> topology_moments(σ, lattice)
(mean_n = 1.0, mu2_n = 0.0, mean_a = 8.0, mu2_a = 0.0)
```

See also [`side_counts`](@ref), [`central_moment`](@ref).
"""
function topology_moments(
        σ::AbstractArray{<:Integer}, lat::Lattice;
        neighborhood = VonNeumann(1)
    )
    n = side_counts(σ, lat; neighborhood)
    area = zeros(Int, length(n))
    for s in σ
        s > 0 && (area[s] += 1)
    end
    live = findall(>(0), area)
    isempty(live) && throw(ArgumentError("topology_moments: σ has no bubbles"))
    nl = n[live]
    al = area[live]
    return (
        mean_n = sum(nl) / length(nl), mu2_n = central_moment(nl), mean_a = sum(al) /
            length(al),
        mu2_a = central_moment(al),
    )
end

# ---------------------------------------------------------------------------------------
# T1 detection

"""
    contact_changes(prev, next) -> (; lost, gained)

Return the contacts that changed between two neighbor lists in [`cell_graph`](@ref)'s form
(`g[c]` the sorted neighbors of bubble `c`).

`lost` holds the unordered pairs `(a, b)`, `a < b`, adjacent in `prev` but not in `next`,
and `gained` those adjacent in `next` but not in `prev`, both sorted. A bubble missing from
the shorter list has no neighbors there. Per-MCS T1 detection (Jiang et al. 1999, p. 5823)
counts these changes: see [`t1_events`](@ref).

# Arguments
- `prev::AbstractVector`, `next::AbstractVector`: the neighbor lists. They are assumed
  symmetric (`b ∈ g[a]` if and only if `a ∈ g[b]`), as those of `cell_graph` are.

# Returns
- `NamedTuple`: `(; lost, gained)`, each a `Vector{Tuple{Int, Int}}`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> contact_changes([[2], [1]], [[3], Int[], [1]])
(lost = [(1, 2)], gained = [(1, 3)])
```

See also [`t1_events`](@ref), [`cell_graph`](@ref).
"""
function contact_changes(prev::AbstractVector, next::AbstractVector)
    lost = Tuple{Int, Int}[]
    gained = Tuple{Int, Int}[]
    for a in 1:max(length(prev), length(next))
        _walk_changes(_list(prev, a), _list(next, a), a) do b, side
            side < 0 ? push!(lost, (a, Int(b))) : push!(gained, (a, Int(b)))
        end
    end
    return (; lost, gained)
end

"""
    t1_events(prev, next; unit = :t1) -> Float64

Return the T1 events between two consecutive neighbor lists, in the counting unit `unit`.

The paper (Jiang et al. 1999, p. 5823) reads a change in the neighbor list as a T1 event;
see `docs/design/research/model-specs/04_foam.md` §2.8 for the units. With `L` and `G` the
numbers of lost and gained contacts of [`contact_changes`](@ref):

  - `:t1`: `(L + G) / 2`. One full T1 (one pair parts, another meets) is 1; half of a T1
    seen through a transient four-fold vertex is 1/2 (the half-integers of the Fig. 5
    inset).
  - `:pairs`: `L + G`. One T1 is 2 (the even-valued bars of Figs. 4(b) and 5(b)).
  - `:bubbles`: the number of bubbles whose neighbor list changed. One T1 is 4.

The sorted lists are merged in place, so a call costs one pass over both lists and
allocates nothing.

# Arguments
- `prev::AbstractVector`, `next::AbstractVector`: the neighbor lists, as from
  [`cell_graph`](@ref).

# Keywords
- `unit::Symbol = :t1`: `:t1`, `:pairs` or `:bubbles`. Throws an `ArgumentError`
  otherwise.

# Returns
- `Float64`: the count, in every unit, so a series of counts has one element type.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> prev, next = [[2], [1]], [[3], Int[], [1]];

julia> t1_events(prev, next), t1_events(prev, next; unit = :pairs)
(1.0, 2.0)
```

See also [`contact_changes`](@ref), [`mean_t1`](@ref).
"""
function t1_events(prev::AbstractVector, next::AbstractVector; unit::Symbol = :t1)
    unit in (:t1, :pairs, :bubbles) ||
        throw(ArgumentError("t1_events: unit must be :t1, :pairs or :bubbles, \
            got $(repr(unit))"))
    unit === :bubbles && return Float64(_changed_bubbles(prev, next))
    changes = 0
    for a in 1:max(length(prev), length(next))
        changes += _count_changes(_list(prev, a), _list(next, a), a)
    end
    return unit === :t1 ? changes / 2 : Float64(changes)
end

const _NO_NEIGHBORS = Int[]
_list(g, a) = a <= length(g) ? g[a] : _NO_NEIGHBORS

# Merge the sorted lists p and q of bubble a, calling f(b, -1) for each b > a only in p and
# f(b, +1) for each b > a only in q.
function _walk_changes(f::F, p, q, a) where {F}
    i = searchsortedfirst(p, a + 1)
    j = searchsortedfirst(q, a + 1)
    while i <= lastindex(p) || j <= lastindex(q)
        if j > lastindex(q) || (i <= lastindex(p) && p[i] < q[j])
            f(p[i], -1)
            i += 1
        elseif i > lastindex(p) || q[j] < p[i]
            f(q[j], 1)
            j += 1
        else
            i += 1
            j += 1
        end
    end
    return nothing
end
# The same walk, counting (a closure that adds to a captured counter would be boxed).
function _count_changes(p, q, a)
    i = searchsortedfirst(p, a + 1)
    j = searchsortedfirst(q, a + 1)
    n = 0
    while i <= lastindex(p) && j <= lastindex(q)
        if p[i] == q[j]
            i += 1
            j += 1
        elseif p[i] < q[j]
            n += 1
            i += 1
        else
            n += 1
            j += 1
        end
    end
    return n + (lastindex(p) - i + 1) + (lastindex(q) - j + 1)
end
function _changed_bubbles(prev, next)
    n = 0
    for a in 1:max(length(prev), length(next))
        n += _list(prev, a) != _list(next, a)
    end
    return n
end

# ---------------------------------------------------------------------------------------
# Power spectra, Eq. (9)

"""
    power_spectrum(x; dt = 1) -> (; f, S)

Return the power spectrum of Eq. (9) of Jiang et al. 1999 (p. 5827;
`docs/design/research/model-specs/04_foam.md` §2.8),
p_N(f) = ∫dt ∫dτ e^{−ifτ} N(t) N(t+τ), of the series `x`.

By the Wiener–Khinchin theorem, this is the periodogram

    S_k = |Σ_{t=0}^{L−1} x_t e^{−2πi k t / L}|² / L,    f_k = k / (L·dt),    k = 1:L÷2,

for `L = length(x)`. With `dt = 1` the frequencies are in cycles per MCS and end at the
Nyquist frequency 0.5, as the axes of Figs. 8 and 10. The f = 0 bin is left out, so a
constant offset does not change `S`. No window is applied (the paper's low-f ringing in
Fig. 8 is the raw periodogram's).

The transform is FFTW's real-to-halfcomplex FFT, O(L log L) for any length. It is not
`rfft`: FFTA (a KernelDensity dependency) also extends `plan_rfft` for real arrays, and
the two methods are ambiguous when both packages are loaded.

# Arguments
- `x::AbstractVector{<:Real}`: the series, at least 2 samples. Throws an `ArgumentError`
  otherwise.

# Keywords
- `dt::Real = 1`: the sample interval, in MCS. It must be positive; throws an
  `ArgumentError` otherwise.

# Returns
- `NamedTuple`: `(; f, S)`, each a `Vector{Float64}` of length `L ÷ 2`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> power_spectrum([1, -1, 1, -1])
(f = [0.25, 0.5], S = [0.0, 4.0])
```

See also [`spectral_exponent`](@ref).
"""
function power_spectrum(x::AbstractVector{<:Real}; dt::Real = 1)
    L = length(x)
    L >= 2 || throw(ArgumentError("power_spectrum: need at least 2 samples, got $L"))
    dt > 0 || throw(ArgumentError("power_spectrum: dt must be positive, got $dt"))
    # halfcomplex: X[k + 1] and X[L − k + 1] are the real and imaginary parts of
    # Σ_t x_t e^{−2πi k t / L}; the imaginary part of k = L/2 (L even) is zero and not
    # stored
    X = r2r(Float64.(x), R2HC)
    K = L ÷ 2
    S = [(X[k + 1]^2 + (2k < L ? X[L - k + 1]^2 : 0.0)) / L for k in 1:K]
    f = [k / (L * dt) for k in 1:K]
    return (; f, S)
end

"""
    spectral_exponent(f, S, range) -> Float64

Return the exponent α of a power law S ∝ f^−α (the f^−α guides of Figs. 8 and 10 of
Jiang et al. 1999; `docs/design/research/model-specs/04_foam.md` §2.8).

`α` is minus the ordinary least-squares slope of `log10(S)` on `log10(f)` over the bins
with `range[1] ≤ f ≤ range[2]` and `S > 0`.

# Arguments
- `f::AbstractVector{<:Real}`: the frequencies.
- `S::AbstractVector{<:Real}`: the spectrum, as many values as `f`. Throws a
  `DimensionMismatch` otherwise.
- `range`: the frequency range `(lo, hi)` of the fit.

Throws an `ArgumentError` for fewer than two bins in the range, or bins that all share one
frequency.

# Returns
- `Float64`: α.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> spectral_exponent([1, 10, 100], [1, 0.01, 0.0001], (1, 100))
2.0
```

See also [`power_spectrum`](@ref).
"""
function spectral_exponent(f::AbstractVector{<:Real}, S::AbstractVector{<:Real}, range)
    length(f) == length(S) ||
        throw(DimensionMismatch("spectral_exponent: f and S have lengths $(length(f)) \
            and $(length(S))"))
    lo, hi = range[1], range[2]
    n = 0
    su = sv = 0.0
    fmin, fmax = Inf, -Inf
    for (fk, Sk) in zip(f, S)
        (lo <= fk <= hi && Sk > 0) || continue
        n += 1
        fmin, fmax = min(fmin, fk), max(fmax, fk)
        su += log10(fk)
        sv += log10(Sk)
    end
    n >= 2 ||
        throw(ArgumentError("spectral_exponent: $n bin(s) with $lo ≤ f ≤ $hi and S > 0, \
            need at least 2"))
    fmin < fmax ||
        throw(ArgumentError("spectral_exponent: the $n bins with $lo ≤ f ≤ $hi and S > 0 \
            all have f = $fmin"))
    ū, v̄ = su / n, sv / n
    suv = suu = 0.0
    for (fk, Sk) in zip(f, S)
        (lo <= fk <= hi && Sk > 0) || continue
        u = log10(fk) - ū
        suv += u * (log10(Sk) - v̄)
        suu += u * u
    end
    return -suv / suu
end

# ---------------------------------------------------------------------------------------
# N̄ and the yield strain

"""
    mean_t1(N, bubbles, strain) -> Float64

Return N̄, "the average number of T1 events per bubble per unit shear" (Jiang et al. 1999,
p. 5829 and Fig. 9): `sum(N) / (bubbles · strain)`.

# Arguments
- `N::AbstractVector{<:Real}`: a T1 series in the caller's counting unit (see
  [`t1_events`](@ref)).
- `bubbles::Real`: the number of bubbles. It must be positive.
- `strain::Real`: the total strain the series spans, as the caller measures it. It must be
  positive.

Throws an `ArgumentError` when `bubbles ≤ 0` or `strain ≤ 0`.

# Returns
- `Float64`: N̄.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> mean_t1([1.0, 2.0, 1.0], 100, 0.5)
0.08
```

See also [`t1_events`](@ref), [`yield_strain`](@ref).
"""
function mean_t1(N::AbstractVector{<:Real}, bubbles::Real, strain::Real)
    bubbles > 0 || throw(ArgumentError("mean_t1: bubbles must be positive, got $bubbles"))
    strain > 0 || throw(ArgumentError("mean_t1: strain must be positive, got $strain"))
    return sum(N; init = 0.0) / (bubbles * strain)
end

"""
    yield_strain(strain, N; threshold = 1, window = 1) -> Union{Real, Nothing}

Return the yield strain, the strain "at which the first T1 avalanches occur" (Jiang et al.
1999, p. 5830; `docs/design/research/model-specs/04_foam.md` §2.8).

The result is `strain[i]` for the first sample `i` with `N[i] > 0` and
`sum(N[i:min(i + window − 1, end)]) ≥ threshold`, or `nothing` if no sample qualifies.
Converting the boundary displacement to strain is the caller's task.

# Arguments
- `strain::AbstractVector{<:Real}`: the strain of each sample.
- `N::AbstractVector{<:Real}`: the T1 series sampled at `strain`, as many values. Throws a
  `DimensionMismatch` otherwise.

# Keywords
- `threshold::Real = 1`: the T1 count of an avalanche. It must be positive.
- `window::Integer = 1`: the samples summed, at least 1.

Throws an `ArgumentError` when `threshold ≤ 0` or `window < 1`.

# Returns
- The element of `strain`, or `nothing`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> yield_strain([0.1, 0.2, 0.3], [0, 1, 3]; threshold = 2)
0.3
```

See also [`mean_t1`](@ref).
"""
function yield_strain(
        strain::AbstractVector{<:Real}, N::AbstractVector{<:Real}; threshold::Real = 1,
        window::Integer = 1
    )
    length(strain) == length(N) ||
        throw(DimensionMismatch("yield_strain: strain and N have \
            lengths $(length(strain)) and $(length(N))"))
    threshold > 0 ||
        throw(ArgumentError("yield_strain: threshold must be positive, got $threshold"))
    window >= 1 ||
        throw(ArgumentError("yield_strain: window must be at least 1, got $window"))
    n = length(N)
    for (k, i) in enumerate(eachindex(N))
        N[i] > 0 || continue
        total = zero(eltype(N))
        for j in i:(i + min(window, n - k + 1) - 1)
            total += N[j]
        end
        total >= threshold && return strain[firstindex(strain) + k - 1]
    end
    return nothing
end
