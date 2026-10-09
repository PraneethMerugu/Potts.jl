# Foam observables of reproduction 04 (Jiang, Swart, Saxena, Asipauskas & Glazier, Phys.
# Rev. E 59, 5819 (1999), "04b"; spec docs/design/research/model-specs/04_foam.md §2.8,
# D-186, D-187): the stored energy φ (Eq. 8), side counts and topology moments, per-MCS T1
# detection from neighbour lists, power spectra (Eq. 9) and their exponents, N̄ and the yield
# strain.

# ---------------------------------------------------------------------------------------
# Stored energy φ, Eq. (8)

"""
    stored_energy(σ, lattice::Lattice; neighborhood = NeighborOrder(4), θ = 1) -> Real

The stored energy φ of Eq. (8) (04b p.5823; spec 04 §2.8),
φ ≡ Σ_{i,j} θ (1 − δ_{σ_i, σ_j}): `θ` times the number of unordered neighbour pairs
`{i, j}` under `neighborhood` with `σ_i ≠ σ_j`, each pair counted once (D-187 reading (a):
only φ/φ(0) is plotted, so the factor 2 of the ordered sum cancels). The default shell is the
paper's fourth-nearest neighbourhood (04b p.5822; spec §8). Pairs wrap on `Periodic()` axes;
a pair that leaves a `Closed()` axis, or the lattice domain, does not exist. Every owner
counts, the medium (0) included. The neighbourhood must be symmetric (each offset's
negation also in it); weights of a `Weighted` relation are ignored.

One pass over the sites with half the offsets, no allocation beyond the relation.
"""
function stored_energy(σ::AbstractArray{<:Integer, N}, lat::Lattice{N}; neighborhood = NeighborOrder(4),
        θ::Real = 1) where {N}
    size(σ) == lat.dims || throw(ArgumentError("stored_energy: σ has size $(size(σ)), the lattice $(lat.dims)"))
    half = _half_offsets(relation(neighborhood, lat).offsets)
    return θ * _unlike_pairs(σ, lat.dims, lat.periodic, lat.mask, half)
end

# The offsets whose first nonzero component is positive: one of each ±o pair. A relation
# that is not symmetric would count some pairs once from one side only.
function _half_offsets(offs::Tuple)
    for o in offs
        all(iszero, o) || map(-, o) in offs ||
            throw(ArgumentError("stored_energy: the neighbourhood is not symmetric (offset $o without $(map(-, o)))"))
    end
    return [o for o in offs if _positive(o)]
end
function _positive(o)
    for c in o
        c == 0 || return c > 0
    end
    return false
end

function _unlike_pairs(σ, dims::NTuple{N, Int}, periodic::NTuple{N, Bool}, mask, half) where {N}
    n = 0
    @inbounds for x in CartesianIndices(σ)     # x and y = x + o (wrapped) are checked to be in `σ`
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
# x + o on the lattice: wraps on periodic axes, `inside = false` off a closed one. The
# relation rejects offsets that alias under a periodic axis, so |o_d| < dims_d and one wrap
# suffices.
@inline function _neighbor(x::NTuple{N, Int}, o::NTuple{N, Int32}, dims, periodic) where {N}
    y = ntuple(d -> x[d] + Int(o[d]), Val(N))
    inside = all(ntuple(d -> periodic[d] || 1 <= y[d] <= dims[d], Val(N)))
    w = ntuple(d -> y[d] < 1 ? y[d] + dims[d] : (y[d] > dims[d] ? y[d] - dims[d] : y[d]), Val(N))
    return inside, w
end

# ---------------------------------------------------------------------------------------
# Sides, ρ(n) and moments

"""
    side_counts(σ, lattice::Lattice; neighborhood = VonNeumann(1)) -> Vector{Int}

The number of sides `n` of each bubble `1:maximum(σ)` (04b p.5823: a bubble's sides are its
distinct neighbours; spec 04 §2.8): `length.(cell_graph(σ, lattice; neighborhood))`. Edge
sharing (`VonNeumann(1)`) is the default; `Moore(1)` also counts corner-only contacts, which
inflates n (spec §2.8, topology audit 2026-10-01). Contacts wrap on `Periodic()` axes; a
`Closed()` wall is not a side (D-187 reading (b)), and neither is the medium.
"""
function side_counts(σ::AbstractArray, lat::Lattice; neighborhood = VonNeumann(1))
    length.(cell_graph(σ, lat; neighborhood))
end

"""
    topology_distribution(n) -> (; n, ρ)

The topology distribution ρ(n) (04b p.5823; spec 04 §2.8): the sorted distinct values of
`n` (a `Vector{Int}`, e.g. from [`side_counts`](@ref)) and the fraction ρ of entries taking
each. Empty input is an `ArgumentError`.
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
    central_moment(x, m = 2) -> Float64

The `m`-th central moment μ_m ≡ Σ_v ρ(v)(v − ⟨v⟩)^m (04b p.5823; spec 04 §2.8) of the values
`x`, which is the population moment (1/N) Σ_i (x_i − x̄)^m. μ2(n) and μ2(a) of the paper are
`central_moment(n)` and `central_moment(a)`. Empty `x` is an `ArgumentError`.
"""
function central_moment(x::AbstractVector{<:Real}, m::Integer = 2)
    isempty(x) && throw(ArgumentError("central_moment: no values"))
    N = length(x)
    x̄ = sum(float, x) / N
    return sum(v -> (v - x̄)^m, x) / N
end

"""
    topology_moments(σ, lattice::Lattice; neighborhood = VonNeumann(1)) -> (; mean_n, mu2_n, mean_a, mu2_a)

⟨n⟩, μ2(n), ⟨a⟩ and μ2(a) (04b p.5823; spec 04 §2.8, [`central_moment`](@ref)) over the
bubbles of `σ`: the ids in `1:maximum(σ)` that own at least one site (an id with no site is
not a bubble). `n` is from [`side_counts`](@ref) with `neighborhood`, `a` is the bubble's
site count (areas stay in sites; any rescaling of μ2(a) is a calibration, D-187).
"""
function topology_moments(σ::AbstractArray{<:Integer}, lat::Lattice; neighborhood = VonNeumann(1))
    n = side_counts(σ, lat; neighborhood)
    area = zeros(Int, length(n))
    for s in σ
        s > 0 && (area[s] += 1)
    end
    live = findall(>(0), area)
    isempty(live) && throw(ArgumentError("topology_moments: σ has no bubbles"))
    nl = n[live]
    al = area[live]
    return (mean_n = sum(nl) / length(nl), mu2_n = central_moment(nl), mean_a = sum(al) / length(al),
        mu2_a = central_moment(al))
end

# ---------------------------------------------------------------------------------------
# T1 detection

"""
    contact_changes(prev, next) -> (; lost, gained)

The contacts that changed between two neighbour lists in [`cell_graph`](@ref)'s form
(`g[c]` the sorted neighbours of bubble `c`): `lost` holds the unordered pairs `(a, b)`,
`a < b`, adjacent in `prev` but not in `next`, and `gained` those adjacent in `next` but not
in `prev`, both sorted. A bubble missing from the shorter list has no neighbours there. The
lists are assumed symmetric (`b ∈ g[a]` iff `a ∈ g[b]`), as `cell_graph`'s are.

Per-MCS T1 detection (04b p.5823; spec 04 §2.8) counts these changes: see
[`t1_events`](@ref).
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

The T1 events between two consecutive neighbour lists (04b p.5823: "A change in the neighbor
list indicates a topological change which … has to be a T1 event"; spec 04 §2.8), in the
counting unit `unit` (A-15). With `L` and `G` the numbers of lost and gained contacts of
[`contact_changes`](@ref):

  - `:t1`: `(L + G) / 2`. One full T1 (one pair parts, another meets) is 1; half of a T1
    seen through a transient four-fold vertex is 1/2 (the half-integers of the Fig. 5 inset).
  - `:pairs`: `L + G`. One T1 is 2 (the even-valued bars of Figs. 4(b) and 5(b)).
  - `:bubbles`: the number of bubbles whose neighbour list changed. One T1 is 4.

Any other `unit` is an `ArgumentError`. The result is a `Float64` in every unit, so a series
of counts has one element type. Nothing is allocated: the sorted lists are merged in place,
so a call costs one pass over both lists.
"""
function t1_events(prev::AbstractVector, next::AbstractVector; unit::Symbol = :t1)
    unit in (:t1, :pairs, :bubbles) ||
        throw(ArgumentError("t1_events: unit must be :t1, :pairs or :bubbles, got $(repr(unit))"))
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

The power spectrum of Eq. (9) (04b p.5827; spec 04 §2.8),
p_N(f) = ∫dt ∫dτ e^{−ifτ} N(t) N(t+τ), of the series `x` (one sample every `dt` MCS): by the
Wiener–Khinchin theorem, the periodogram

    S_k = |Σ_{t=0}^{L−1} x_t e^{−2πi k t / L}|² / L,    f_k = k / (L·dt),    k = 1:L÷2,

for `L = length(x)`. With `dt = 1` the frequencies are in cycles per MCS and end at the
Nyquist frequency 0.5, as the axes of Figs. 8 and 10. The f = 0 bin is left out, so a
constant offset does not change `S`. No window is applied (the paper's low-f ringing in
Fig. 8 is the raw periodogram's). Fewer than two samples is an `ArgumentError`.

The transform is FFTW's real-input FFT, O(L log L) for any length.
"""
function power_spectrum(x::AbstractVector{<:Real}; dt::Real = 1)
    L = length(x)
    L >= 2 || throw(ArgumentError("power_spectrum: need at least 2 samples, got $L"))
    dt > 0 || throw(ArgumentError("power_spectrum: dt must be positive, got $dt"))
    X = rfft(Float64.(x))                     # X[k + 1] = Σ_t x_t e^{−2πi k t / L}, k = 0:L÷2
    K = L ÷ 2
    S = [abs2(X[k + 1]) / L for k in 1:K]
    f = [k / (L * dt) for k in 1:K]
    return (; f, S)
end

"""
    spectral_exponent(f, S; range) -> Float64

The exponent α of a power law S ∝ f^−α (spec 04 §2.8; the f^−α guides of Figs. 8 and 10):
`α = −` the ordinary least-squares slope of `log10(S)` on `log10(f)` over the bins with
`range[1] ≤ f ≤ range[2]` and `S > 0`. Fewer than two such bins is an `ArgumentError`.
"""
function spectral_exponent(f::AbstractVector{<:Real}, S::AbstractVector{<:Real}; range)
    length(f) == length(S) ||
        throw(DimensionMismatch("spectral_exponent: f and S have lengths $(length(f)) and $(length(S))"))
    lo, hi = range[1], range[2]
    n = 0
    su = sv = 0.0
    for (fk, Sk) in zip(f, S)
        (lo <= fk <= hi && Sk > 0) || continue
        n += 1
        su += log10(fk)
        sv += log10(Sk)
    end
    n >= 2 ||
        throw(ArgumentError("spectral_exponent: $n bin(s) with $lo ≤ f ≤ $hi, need at least 2"))
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
    mean_t1(N; bubbles, strain) -> Float64

N̄ (04b p.5829, Fig. 9; spec 04 §2.8), "the average number of T1 events per bubble per unit
shear": `sum(N) / (bubbles · strain)`. `N` is a T1 series in the caller's counting unit (see
[`t1_events`](@ref), A-15) and `strain` the total strain it spans, as the caller measures it
(A-9). `bubbles ≤ 0` or `strain ≤ 0` is an `ArgumentError`.
"""
function mean_t1(N::AbstractVector{<:Real}; bubbles::Real, strain::Real)
    bubbles > 0 || throw(ArgumentError("mean_t1: bubbles must be positive, got $bubbles"))
    strain > 0 || throw(ArgumentError("mean_t1: strain must be positive, got $strain"))
    return sum(N; init = 0.0) / (bubbles * strain)
end

"""
    yield_strain(strain, N; threshold = 1, window = 1) -> Real or nothing

The yield strain (04b p.5830; spec 04 §2.8), the strain "at which the first T1 avalanches
occur": `strain[i]` for the first sample `i` with `N[i] > 0` and
`sum(N[i:min(i + window − 1, end)]) ≥ threshold`, or `nothing` if no sample qualifies. `N`
is the T1 series sampled at `strain`; converting the boundary displacement to strain (A-9;
spec §3.2's calibration ε ≈ c·β·t) is the caller's. Different lengths are a
`DimensionMismatch`; `threshold ≤ 0` or `window < 1` is an `ArgumentError`.
"""
function yield_strain(strain::AbstractVector{<:Real}, N::AbstractVector{<:Real}; threshold::Real = 1,
        window::Integer = 1)
    length(strain) == length(N) ||
        throw(DimensionMismatch("yield_strain: strain and N have lengths $(length(strain)) and $(length(N))"))
    threshold > 0 || throw(ArgumentError("yield_strain: threshold must be positive, got $threshold"))
    window >= 1 || throw(ArgumentError("yield_strain: window must be at least 1, got $window"))
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
