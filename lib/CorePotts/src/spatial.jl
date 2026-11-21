# Spatial queries: site predicates, per-cell reductions and the cell contact
# graph. Site predicates are device functions; `CellReduce` and `ContactPhase` are phases;
# the host `contact_graph` (CSR) is built at a synchronization point.

"""`true` if some in-domain `relation` neighbor of site `i` has a different owner."""
@inline function is_boundary_site(σ, ctx, i; relation = ctx.contact)
    lat = ctx.lattice
    x = coordinates(lat, i)
    # bounds: i ≤ nsites = length(σ); inside neighbors are ≤ nsites as well
    a = @inbounds σ[i]
    for k in 1:length(relation)
        inside, y = shift(lat, x, @inbounds relation.offsets[k])
        (inside && @inbounds(σ[linear_index(lat, y)]) != a) && return true
    end
    return false
end

"""Weighted count of in-domain `relation` neighbors `j` of site `i` with `pred(σ[j])`."""
@inline function count_neighbors(pred::F, σ, ctx, i; relation = ctx.contact) where {F}
    lat = ctx.lattice
    x = coordinates(lat, i)
    n = zero(weight(relation, 1))
    for k in 1:length(relation)
        # bounds: k ≤ length(relation); inside sites have linear indices ≤ nsites
        inside, y = shift(lat, x, @inbounds relation.offsets[k])
        (inside && pred(@inbounds σ[linear_index(lat, y)])) && (n += weight(relation, k))
    end
    return n
end

"""
    CellReduce((:cell, :name), f; op = +)

Phase: `st.cell.name[c] = op_{i ∈ c} f(st, p, ctx, key, mcs, i)` over every cell's sites
(`op ∈ (+, max, min)`). Covers owner sums, means (divide by volume), counts of sites
satisfying a predicate (return a `Bool`/`Int32`), and structured owner sums.

The result is the same for every order of the sites, so for every thread count and backend:

  - an integer column, and `max`/`min`, use atomics, which are exact;
  - a float sum (Float16, Float32, Float64) is an exact Int64 fixed-point sum with a
    power-of-two scale per cell, chosen from the largest value `m` in the cell (two passes
    over the sites). Each term is rounded to a unit of about `m * N * 2^-62` (`N` the number
    of lattice sites; 1.5e-11 m at 300³), so the cell average is within about
    `m * N * 2^-62` of the exact average. For a cell whose sum sits in values far below `m`,
    the relative error of the sum can reach `n_c * N * 2^-62` (`n_c` the cell's sites):
    3.7e-6 for one cell of 2048² with one site at `m`, coarser than a Float64 sum and no
    finer than a sequential Float32 sum. `f` may not read `dst` (the column keeps its old
    values until the sum is written). The integer sum cannot overflow. A NaN in a cell gives
    NaN; ±Inf give ±Inf (NaN if both). A sum beyond its column's number type is stored as
    ±Inf and the integrator warns at its next read point. On a device without 64-bit atomics
    (Metal) the sum is held in a pair of 32-bit words, with the same result;
  - any other number type (a `BigFloat`, a `Dual`) is summed in site order on the host, and
    is refused on a device.

A float sum needs the reduction scratch in the state:
`sc = CorePotts.reduce_scratch(ncell)`, merged into the cell and model state
(`initial_state(σ, kinds; cell = (; …, sc.cell...), model =
sc.model)`). Potts adds it to every model with an `integral`.
"""
struct CellReduce{D <: Part, F, O}
    dst::D
    f::F
    op::O
end
CellReduce(dst::Tuple{Symbol, Symbol}, f; op = +) = CellReduce(Part(dst), f, op)

_identity(::typeof(+), T) = zero(T)
_identity(::typeof(max), T) = typemin(T)
_identity(::typeof(min), T) = typemax(T)

@inline function _cell_reduce_body!(i, f, op, dst, st, p, ctx, key, mcs)
    # bounds: launched over i ∈ 1:nsites = length(st.ownership)
    c = @inbounds st.ownership[i]
    return if c != 0
        v = convert(eltype(dst), f(st, p, ctx, key, mcs, i))
        _atomic!(op, dst, c, v)
    end
end
@inline _atomic!(::typeof(+), a, c, v) = (Atomix.@atomic a[c] += v; nothing)
@inline function _atomic!(op::Union{typeof(max), typeof(min)}, a, c, v::Integer)
    op === max ? (Atomix.@atomic a[c] max v) : (Atomix.@atomic a[c] min v)
    return nothing
end
# floats: a CAS loop that writes `op(old, v)` and stops when that equals `old` (`isequal`: a
# NaN stays, as `max` and `min` propagate it in either order)
@inline function _atomic!(op::Union{typeof(max), typeof(min)}, a, c, v)
    # bounds: c is a cell id ≤ capacity = length(a)
    old = @inbounds a[c]
    while true
        new = op(old, v)
        isequal(new, old) && break
        old, ok = Atomix.@atomicreplace a[c] old => new
        ok && break
    end
    return nothing
end

function (ph::CellReduce{D, F, O})(st, p, ctx, key, mcs, backend) where {D, F, O}
    return _cell_reduce!(ph.op, ph.f, ph.dst(st), D, st, p, ctx, key, mcs, backend)
end

# integer sums, and max/min of any type: one atomic per site (exact, order-free)
function _cell_reduce!(op::O, f::F, dst, ::Type, st, p, ctx, key, mcs, backend) where {O, F}
    return _cell_reduce_atomic!(op, f, dst, st, p, ctx, key, mcs, backend)
end
function _cell_reduce!(
        ::typeof(+), f::F, dst::AbstractArray{<:Integer},
        ::Type, st, p, ctx, key, mcs, backend
    ) where {F}
    return _cell_reduce_atomic!(+, f, dst, st, p, ctx, key, mcs, backend)
end
function _cell_reduce_atomic!(op::O, f::F, dst, st, p, ctx, key, mcs, backend) where {O, F}
    _device_fill!(backend, dst, _identity(op, eltype(dst)))
    Exec.launch!(
        backend, _cell_reduce_body!, length(st.ownership), (
            f, op, dst, st, p, ctx, key, mcs,
        )
    )
    return 2
end

# ---------------------------------------------------------------------------------------
# Float sums in Int64 fixed point
#
#   zero      (cells)  the scratch
#   exponent  (sites)  `exp[c]` = the largest biased exponent of a finite nonzero value in c
#                      (an Int32 atomic max); a NaN/±Inf sets bit 1/2/4 of `flag[c]` instead
#   sum       (sites)  `acc[c] += round(ldexp(v, e_c))`, e_c = 62 − (exp[c] − bias + 1) − L,
#                      L = ⌈log₂ N⌉: every |term| < 2^(62 − L), so |acc| < 2^62 + N
#   finalize  (cells)  `dst[c] = T(ldexp(W(acc[c]), −e_c))`, or the flags' NaN/±Inf
#
# The work type `W` widens Float16 to Float32 (v·2^e reaches 2^62). Without 64-bit atomics
# the accumulator is a pair: a UInt32 low word (its carry read from the returned sum) and an
# Int32 high word, exact modulo 2^64.

const _CR_ACC = Symbol("#cr_acc")
const _CR_LO = Symbol("#cr_lo")
const _CR_HI = Symbol("#cr_hi")
const _CR_EXP = Symbol("#cr_exp")
const _CR_FLAG = Symbol("#cr_flag")
"""
`st.model` key of the cell-sum status word (`UInt32[1]`, `reduce_scratch`): bit
`STATUS_SUM_RANGE` is set when a cell sum exceeded the range of its column's number type
(stored as ±Inf), and bits 9–32 hold the position of that column in the cell state (the
largest one, if several). The integrator warns at its next host read point, naming the
column, and clears the word; the run continues.
"""
const REDUCE_STATUS = Symbol("#cr_status")
"""Status bit of `REDUCE_STATUS`: a cell sum exceeded its column's number type."""
const STATUS_SUM_RANGE = UInt32(1)

"""
    reduce_scratch(ncell) -> (; cell, model)

The state a float-sum `CellReduce` needs, as two `NamedTuple`s to merge into the cell state
(columns for `ncell` slots, grown with the state by `with_capacity`) and the model state.
Names start with `#cr_`; a division daughter never copies them. The scratch is zero between
reductions.
"""
function reduce_scratch(ncell::Integer)
    return (;
        cell = NamedTuple{(_CR_ACC, _CR_LO, _CR_HI, _CR_EXP, _CR_FLAG)}(
            (
                zeros(Int64, ncell), zeros(UInt32, ncell),
                zeros(Int32, ncell), zeros(Int32, ncell), zeros(Int32, ncell),
            )
        ),
        model = NamedTuple{(REDUCE_STATUS,)}((zeros(UInt32, 1),)),
    )
end

# Without 64-bit atomics (`_atomic64`, Metal) the sum takes the paired 32-bit form;
# `_FORCE_PAIRED` (tests) takes it on any backend
const _FORCE_PAIRED = Ref(false)
_paired(backend) = _FORCE_PAIRED[] || !_atomic64(backend)
# Negative controls only (tests): `true` restores the float atomics (order-dependent) of a
# float cell sum, of the weight-unit sums (`_units_for`) and of the `@convert` compound
# writes
const _FLOAT_ATOMICS = Ref(false)

_has_reduce_scratch(st) = haskey(st.cell, _CR_ACC) && haskey(st.model, REDUCE_STATUS)
@inline function _cr(st)
    return (;
        acc = getfield(st.cell, _CR_ACC), lo = getfield(st.cell, _CR_LO),
        hi = getfield(st.cell, _CR_HI),
        exp = getfield(st.cell, _CR_EXP), flag = getfield(st.cell, _CR_FLAG),
        status = getfield(
            st.model, REDUCE_STATUS
        ),
    )
end

# ⌈log₂ N⌉ for N lattice sites (every cell has at most N); refused above 2^61 sites, where
# the Int64 sum could no longer hold N terms below 2^(62 − L)
function _reduce_bits(n::Integer)
    n <= 2^61 || throw(
        ArgumentError(
            "a float cell sum (`integral`, `CellReduce`) over $n lattice sites cannot be " *
                "held exactly in Int64 fixed point (at most 2^61 sites); use a smaller \
                    lattice"
        )
    )
    return n <= 1 ? 0 : 64 - leading_zeros(n - 1)
end

_cr_work(::Type{Float16}) = Float32
_cr_work(::Type{T}) where {T <: Union{Float32, Float64}} = T
# (unsigned type, significand bits, exponent bias) of the work type
_cr_bits(::Type{Float32}) = (UInt32, 23, 127)
_cr_bits(::Type{Float64}) = (UInt64, 52, 1023)
# the biased exponent of finite nonzero `w`, at least 1 (a subnormal's bound is the smallest
# normal's)
@inline function _cr_biased(w::W) where {W}
    U, m, _ = _cr_bits(W)
    return max((reinterpret(U, abs(w)) >> m) % Int32, Int32(1))
end
# the scale e_c of a cell whose largest biased exponent is `b`
@inline function _cr_shift(::Type{W}, b::Int32, L::Int) where {W}
    return 62 -
        (Int(b) - _cr_bits(W)[3] + 1) - L
end
# the value of site `i` in the column's type, then in the work type
@inline function _cr_value(f::F, ::Type{T}, st, p, ctx, key, mcs, i) where {F, T}
    return _cr_work(T)(convert(T, f(st, p, ctx, key, mcs, i)))
end

@inline function _cr_zero_body!(c, sc)
    @inbounds begin                                  # c ≤ capacity = length of every column
        sc.acc[c] = 0
        sc.lo[c] = 0
        sc.hi[c] = 0
        sc.exp[c] = 0
        sc.flag[c] = 0
    end
    return nothing
end

# The site passes take a run of `k` consecutive sites per work item and keep a local
# exponent maximum or integer sum while the owner stays the same (sites of a cell are mostly
# contiguous along the first axis): one atomic per run of a cell instead of one per site. A
# local integer sum is exact, so the result is unchanged; a partial sum is bounded by the
# cell's. Measured on ROCm (300³, Float32): runs of 1, 4, 8, 16 sites take 3.8, 2.9, 4.0,
# 8.2 ms; on the
# CPU (-t 8, Float64) runs of 1, 64, 256, 1024 take 48, 23, 22, 40 ms.
# `_CR_RUN_DEVICE` / `_CR_RUN_HOST` are Refs for such probes.
const _CR_RUN_HOST = Ref(256)
const _CR_RUN_DEVICE = Ref(4)
_cr_run_length(backend) = Exec.ishost(backend) ? _CR_RUN_HOST[] : _CR_RUN_DEVICE[]
@inline _cr_runs(n, k) = cld(n, k)
@inline _cr_run(j, n, k) = ((j - 1) * k + 1):min(j * k, n)

@inline function _cr_exp_flush!(sc, c, b)
    # an atomic (monotonic) load: a stale value only adds an atomic; c ≤ capacity
    (c != 0 && b > (@inbounds Atomix.@atomic :monotonic sc.exp[c])) &&
        Atomix.@atomic sc.exp[c] max b
    return nothing
end
@inline function _cr_exp_body!(j, k, f::F, dst, sc, st, p, ctx, key, mcs) where {F}
    σ = st.ownership
    cur = zero(eltype(σ))
    b = Int32(0)
    for i in _cr_run(j, length(σ), k)                       # i ≤ length(σ)
        # bounds: i ≤ length(σ), from the run's range
        c = @inbounds σ[i]
        c != cur && (_cr_exp_flush!(sc, cur, b); cur = c; b = Int32(0))
        c == 0 && continue
        w = _cr_value(f, eltype(dst), st, p, ctx, key, mcs, i)
        if !isfinite(w)
            bit = if isnan(w)
                Int32(1)
            elseif w > 0
                Int32(2)
            else
                Int32(4)
            end
            # (rare: no local form)
            Atomix.@atomic sc.flag[c] |= bit
        elseif !iszero(w)
            b = max(b, _cr_biased(w))
        end
    end
    _cr_exp_flush!(sc, cur, b)
    return nothing
end

# the fixed-point term of value `w` at scale `e` (0 for a zero or non-finite value)
@inline function _cr_term(w, e)
    (isfinite(w) && !iszero(w)) || return Int64(0)
    return unsafe_trunc(Int64, round(ldexp(w, e)))       # |ldexp(w, e)| < 2^(62 − L)
end

@inline function _cr_add!(sc, c, q, ::Val{false})
    q != 0 && Atomix.@atomic sc.acc[c] += q
    return nothing
end
@inline function _cr_add!(sc, c, q, ::Val{true})
    q == 0 && return nothing
    lo = q % UInt32
    hi = (q >> 32) % Int32
    new = Atomix.@atomic sc.lo[c] += lo
    hi += (new < lo) % Int32                              # the low word's carry
    hi != 0 && Atomix.@atomic sc.hi[c] += hi
    return nothing
end

@inline function _cr_sum_body!(
        j, k, f::F, dst, L, sc, st, p, ctx, key, mcs, paired::Val
    ) where {F}
    σ = st.ownership
    W = _cr_work(eltype(dst))
    cur = zero(eltype(σ))
    q = Int64(0)
    e = 0
    for i in _cr_run(j, length(σ), k)                       # i ≤ length(σ)
        # bounds: i ≤ length(σ), from the run's range
        c = @inbounds σ[i]
        if c != cur
            cur != 0 && _cr_add!(sc, cur, q, paired)
            cur = c
            q = Int64(0)
            c != 0 && (e = _cr_shift(W, @inbounds(sc.exp[c]), L))
        end
        c == 0 && continue
        q += _cr_term(_cr_value(f, eltype(dst), st, p, ctx, key, mcs, i), e)
    end
    cur != 0 && _cr_add!(sc, cur, q, paired)
    return nothing
end

# bounds: c ≤ length of the accumulator columns (a cell id, or a cell's pair row)
@inline _cr_acc(sc, c, ::Val{false}) = @inbounds sc.acc[c]
# bounds: as above, for the paired (hi, lo) accumulator columns
@inline function _cr_acc(sc, c, ::Val{true})
    return (Int64(@inbounds sc.hi[c]) << 32) +
        Int64(@inbounds sc.lo[c])
end

@inline function _cr_final_body!(c, dst, L, sc, paired::Val, col::UInt32)
    T = eltype(dst)
    fl = @inbounds sc.flag[c]
    b = @inbounds sc.exp[c]
    v = if fl != 0
        if fl & Int32(1) != 0 || fl & Int32(6) == Int32(6)
            T(NaN)
        elseif fl & Int32(2) != 0
            T(Inf)
        else
            T(-Inf)
        end
    elseif b == 0
        zero(T)
    else
        W = _cr_work(T)
        s = T(ldexp(W(_cr_acc(sc, c, paired)), -_cr_shift(W, b, L)))
        # finite terms, sum out of T's range: the bit and the column's position
        isinf(s) && Atomix.@atomic sc.status[1] max ((col << 8) | STATUS_SUM_RANGE)
        s
    end
    @inbounds dst[c] = v                                  # c ≤ capacity = length(dst)
    return nothing
end

function _cell_reduce!(
        ::typeof(+), f::F, dst::AbstractArray{T}, ::Type{D}, st, p, ctx, key, mcs,
        backend
    ) where {F, T <: Union{Float16, Float32, Float64}, D}
    _FLOAT_ATOMICS[] &&
        return _cell_reduce_atomic!(+, f, dst, st, p, ctx, key, mcs, backend)
    _has_reduce_scratch(st) || throw(
        ArgumentError(
            string(
                "the cell sum into the ", T, " column `", _part_name(D),
                "` (`CellReduce`) needs the reduction scratch in the ",
                "state: merge `sc = CorePotts.reduce_scratch(ncell)` into it \
                    (`initial_state(σ, kinds; cell = (; …, sc.cell...), ",
                "model = sc.model)`)"
            )
        )
    )
    sc = _cr(st)
    n = length(st.ownership)
    L = _reduce_bits(n)
    ncap = length(dst)
    # for the range warning
    col = UInt32(something(findfirst(==(_part_name(D)), keys(st.cell)), 0))
    Exec.launch!(backend, _cr_zero_body!, ncap, (sc,))
    k = _cr_run_length(backend)
    Exec.launch!(
        backend, _cr_exp_body!, _cr_runs(n, k), (
            k, f, dst, sc, st, p, ctx, key, mcs,
        )
    )
    if _paired(backend)
        Exec.launch!(
            backend, _cr_sum_body!, _cr_runs(n, k),
            (k, f, dst, L, sc, st, p, ctx, key, mcs, Val(true))
        )
        Exec.launch!(backend, _cr_final_body!, ncap, (dst, L, sc, Val(true), col))
    else
        Exec.launch!(
            backend, _cr_sum_body!, _cr_runs(n, k),
            (k, f, dst, L, sc, st, p, ctx, key, mcs, Val(false))
        )
        Exec.launch!(backend, _cr_final_body!, ncap, (dst, L, sc, Val(false), col))
    end
    return 4
end

# any other number type (BigFloat, Dual, Rational): summed in site order on the host
function _cell_reduce!(
        ::typeof(+), f::F, dst::AbstractArray{T}, ::Type{D}, st, p, ctx, key, mcs,
        backend
    ) where {F, T, D}
    Exec.ishost(backend) || throw(
        ArgumentError(
            string(
                "run on the CPU: the cell sum into the ", T, " column `", _part_name(D),
                "` (`CellReduce`) runs on the host ",
                "only, because a device has no atomics for ", T,
                (T <: AbstractFloat ? "; or use a Float32 or Float64 column" : "")
            )
        )
    )
    fill!(dst, zero(T))
    σ = st.ownership
    for i in eachindex(σ)
        c = σ[i]
        c != 0 && (dst[c] += convert(T, f(st, p, ctx, key, mcs, i)))
    end
    return 1
end
_part_name(::Type{Part{A, B}}) where {A, B} = B

# ---------------------------------------------------------------------------------------
# Integer weight units. A float sum of relation weights over the sites (the device
# lifecycle's surface and cluster surface recomputes, `ContactPhase`) adds each weight as an
# integer number of units 2^-e, in Int64, so the sum is exact and does not depend on the
# order. The scale is static: one site adds at most W = Σ_k |w_k| to an entry and at most n
# sites add to it, so e = 62 − ⌈log₂ n⌉ − ⌈log₂ W⌉ − 1 keeps the sum below 2^62. A weight is
# held to 2^-e (2^-31 for Moore(1) 1/|o| weights at 300³; 2^-40 at 512²), and the sum of the
# quantized weights is then exact. Unweighted relations (`weight` = 1) and integer columns
# keep their atomic adds: their sums are integers, exact in any order (in a float column,
# below 2^24 for Float32 and 2^53 for Float64 per entry).

"""
    _weight_units(rel, n) -> (; e, q) or nothing

The integer weight units of relation `rel` for sums over at most `n` sites: `q[k]` is
`round(weight(rel, k) · 2^e)` (`Int64`). `nothing` for an unweighted relation. A weight
below half a unit, `2^-(e+1)`, rounds to 0 units (its bonds add nothing); its contribution
is then below `2^-(e+1)` per bond. Copies add the float weights, so a weighted tracker can
differ from `recompute_surface` by up to `4 N W 2^-62` per division, plus the tracker
column's own rounding, about `eps(T)/2` of its value per add (each copy commit and each
division round; the larger term in Float32): compare with a tolerance.
"""
_weight_units(::Relation{N, K, Nothing}, n::Integer) where {N, K} = nothing
function _weight_units(rel::Relation{N, K}, n::Integer) where {N, K}
    W = sum(k -> abs(Float64(weight(rel, k))), 1:K; init = 0.0)
    e = W == 0 ? 0 : 62 - _reduce_bits(n) - (exponent(W) + 1) - 1
    return (; e, q = ntuple(k -> round(Int64, ldexp(Float64(weight(rel, k)), e)), Val(K)))
end
# the units of a sum into a column of type T: float columns of a weighted relation (and
# Float16, whose integers are exact only to 2048), else nothing (atomic adds)
_units_for(::Type{T}, rel, n, backend) where {T} = nothing
function _units_for(::Type{T}, rel, n, backend) where {T <: AbstractFloat}
    _FLOAT_ATOMICS[] && return nothing                    # negative controls only (tests)
    u = _weight_units(rel, n)
    if u === nothing
        T <: Float16 || return nothing
        u = _unit_weights(rel, n)
    end
    return (; u.e, u.q, paired = Val(_paired(backend)))
end
function _unit_weights(::Relation{N, K}, n) where {N, K}
    e = 62 - _reduce_bits(n) - (exponent(Float64(K)) + 1) - 1
    return (; e, q = ntuple(_ -> Int64(1) << e, Val(K)))
end
# the k-th weight as added: units, or the weight in the column's type
@inline _wt(::Nothing, rel, k, ::Type{T}) where {T} = T(weight(rel, k))
# bounds: k ≤ length(rel) = length(u.q), one unit weight per offset
@inline _wt(u::NamedTuple, rel, k, ::Type{T}) where {T} = @inbounds u.q[k]
@inline _wzero(::Nothing, ::Type{T}) where {T} = zero(T)
@inline _wzero(::NamedTuple, ::Type{T}) where {T} = Int64(0)
# the value of `a` units in type T
@inline _wvalue(::Type{T}, a::Int64, e) where {T} = T(ldexp(_cr_work(T)(a), -e))

"""
Warn when a cell sum exceeded its column's number type since the last read point
(`REDUCE_STATUS`), and clear the word. The run continues (the sum is ±Inf in the state).
"""
function _check_reduce_status!(stats, st, t, backend)
    model = st.model
    haskey(model, REDUCE_STATUS) || return nothing
    w = getfield(model, REDUCE_STATUS)
    s = _readback(stats, w)
    s & STATUS_SUM_RANGE == 0 && return nothing
    j = Int(s >> 8)
    names = keys(st.cell)
    name, T = if 1 <= j <= length(names)
        (names[j], eltype(getfield(st.cell, names[j])))
    else
        (Symbol("?"), Float32)
    end
    route = if T <: Float64
        "rescale the summed expression"
    elseif _atomic64(backend)
        "build the problem in Float64 (`PottsProblem(…; T = Float64)`) or rescale the \
            summed expression"
    else
        "rescale the summed expression (this device has no Float64)"
    end
    @warn string(
        "the cell sum `", name, "` (`integral`, `CellReduce`) exceeded floatmax(", T,
        ") = ", floatmax(T),
        " by MCS ", t, " and is stored as ±Inf; ", route
    )
    fill!(w, zero(eltype(w)))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Contact graph (host)

"""
    ContactGraph

Cells that touch over a relation and their shared interface measure (weighted bond count),
in CSR form: the neighbors of `c` are `col[row_ptr[c]:row_ptr[c+1]-1]` with `measure`
alongside; `medium[c]` is `c`'s interface with the medium.
"""
struct ContactGraph{T}
    row_ptr::Vector{Int32}
    col::Vector{Int32}
    measure::Vector{T}
    medium::Vector{T}
end

"""
    contact_graph(σ, lattice, relation, ncell) -> ContactGraph

Build the graph from scratch (face-sharing neighbors with `VonNeumann(1)`, as CompuCell3D's
NeighborTracker; any relation, weighted or not, works).
"""
function contact_graph(σ, lat::Lattice, r::Relation, ncell::Integer)
    T = typeof(weight(r, 1))
    pairs = Dict{Tuple{Int32, Int32}, T}()
    medium = zeros(T, ncell)
    for i in 1:nsites(lat)
        a = σ[i]
        x = coordinates(lat, i)
        for k in 1:length(r)
            inside, y = shift(lat, x, r.offsets[k])
            inside || continue
            b = σ[linear_index(lat, y)]
            (a == b || a == 0) && continue
            w = weight(r, k)
            if b == 0
                medium[a] += w
            else
                pairs[(a, b)] = get(pairs, (a, b), zero(T)) + w
            end
        end
    end
    counts = zeros(Int32, ncell)
    for (a, _) in keys(pairs)
        counts[a] += 1
    end
    row_ptr = Int32[1; 1 .+ cumsum(counts)]
    col = zeros(Int32, length(pairs))
    measure = zeros(T, length(pairs))
    fill_ptr = copy(row_ptr[1:ncell])
    for ((a, b), m) in sort!(collect(pairs); by = first)
        col[fill_ptr[a]] = b
        measure[fill_ptr[a]] = m
        fill_ptr[a] += 1
    end
    return ContactGraph(row_ptr, col, measure, medium)
end

"""Neighboring cells of `c` (sorted ids)."""
contact_neighbors(g::ContactGraph, c) = view(g.col, g.row_ptr[c]:(g.row_ptr[c + 1] - 1))
"""Shared interface measure of cells `c` and `n` (zero if they do not touch)."""
function contact_measure(g::ContactGraph{T}, c, n) where {T}
    n == 0 && return g.medium[c]
    r = g.row_ptr[c]:(g.row_ptr[c + 1] - 1)
    j = searchsortedfirst(view(g.col, r), n)
    return j <= length(r) && g.col[r[j]] == n ? g.measure[r[j]] : zero(T)
end

# ---------------------------------------------------------------------------------------
# Contact table (device)

"""
    empty_contacts(maxdeg, ncell; T = Float32) -> NamedTuple

Device-resident contact table to merge into the cell state, filled by `ContactPhase`:
`contact_nbr[k, c]` (0 = empty slot, rows in no particular order), `contact_measure[k, c]`
(shared weighted bond count), `contact_medium[c]` and `contact_overflow[c]` (bonds dropped
because `c`'s row was full; nonzero means `maxdeg` is too small, and which bonds were
dropped then depends on the order). The `#ct_` columns are the scratch of a weighted
relation's exact sums (integer weight units).
"""
function empty_contacts(maxdeg::Integer, ncell::Integer; T::Type = Float32)
    return (;
        contact_nbr = zeros(Int32, maxdeg, ncell),
        contact_measure = zeros(T, maxdeg, ncell),
        contact_medium = zeros(T, ncell), contact_overflow = zeros(Int32, ncell),
        _CT_ACC => zeros(Int64, maxdeg + 1, ncell), _CT_LO =>
            zeros(UInt32, maxdeg + 1, ncell),
        _CT_HI => zeros(Int32, maxdeg + 1, ncell),
    )
end
const _CT_ACC = Symbol("#ct_acc")         # row maxdeg + 1: the medium
const _CT_LO = Symbol("#ct_lo")
const _CT_HI = Symbol("#ct_hi")

"""
    ContactPhase(relation = :contact)

Phase that rebuilds the contact table (`empty_contacts`) from `σ` over the named `ctx`
relation, on the device. Rows are built with atomic insertion, so their order varies;
query with `contact_slot`/`contact_measure`. The measures do not depend on the order: a
weighted relation in a float table is summed in integer weight units (`_units_for`), and
unit weights are integer counts.
"""
struct ContactPhase{R} end
ContactPhase(relation::Symbol = :contact) = ContactPhase{relation}()

@inline function _contact_body!(i, nbr, measure, medium, overflow, σ, lat, r, u, sc)
    # bounds: i ≤ nsites = length(σ); a ≤ capacity, the columns of nbr and measure
    a = @inbounds σ[i]
    return if a != 0
        x = coordinates(lat, i)
        maxdeg = size(nbr, 1)
        for k in 1:length(r)
            inside, y = shift(lat, x, @inbounds r.offsets[k])
            inside || continue
            b = @inbounds σ[linear_index(lat, y)]
            b == a && continue
            w = _wt(u, r, k, eltype(measure))
            if b == 0
                _ct_add!(u, sc, medium, a, maxdeg + 1, a, w)
                continue
            end
            slot = 0
            for s in 1:maxdeg
                cur = @inbounds nbr[s, a]
                if cur == b
                    slot = s
                elseif cur == 0
                    old, ok = Atomix.@atomicreplace nbr[s, a] Int32(0) => b
                    (ok || old == b) && (slot = s)
                end
                slot != 0 && break
            end
            if slot == 0
                Atomix.@atomic overflow[a] += Int32(1)
            else
                _ct_add!(u, sc, measure, CartesianIndex(slot, a), slot, a, w)
            end
        end
    end
end

# a weight into the table: an atomic add, or its units into row `s` of column `a` of the
# scratch
@inline _ct_add!(::Nothing, sc, col, I, s, a, w) = (Atomix.@atomic col[I] += w; nothing)
@inline function _ct_add!(u::NamedTuple, sc, col, I, s, a, w)
    return _cr_add!(sc, (a - 1) * size(sc.acc, 1) + s, w, u.paired)
end
# cell a's measures from their units, the scratch cleared (s ≤ maxdeg + 1 = size(sc.acc, 1))
@inline function _contact_fold_body!(a, measure, medium, sc, u)
    M = size(sc.acc, 1)
    for s in 1:M
        j = (a - 1) * M + s
        v = _wvalue(eltype(measure), _cr_acc(sc, j, u.paired), u.e)
        if s < M
            # bounds: s ≤ M = size(measure, 1); a ≤ capacity = size(measure, 2)
            @inbounds measure[s, a] = v
        else
            @inbounds medium[a] = v
        end
        @inbounds begin
            sc.acc[j] = 0
            sc.lo[j] = 0
            sc.hi[j] = 0
        end
    end
    return nothing
end

function (ph::ContactPhase{R})(st, p, ctx, key, mcs, backend) where {R}
    c = st.cell
    rel = getfield(ctx, R)
    n = length(st.ownership)
    u = _units_for(eltype(c.contact_measure), rel, n, backend)
    u === nothing || haskey(c, _CT_ACC) || throw(
        ArgumentError(
            string(
                "the contact table (`ContactPhase`) over the weighted relation `", R,
                "` needs the `#ct_` scratch columns ",
                "of `empty_contacts`: build the table with `empty_contacts(maxdeg, ncell; \
                    T)` and merge all of its columns"
            )
        )
    )
    sc = if u === nothing
        nothing
    else
        (; acc = getfield(c, _CT_ACC), lo = getfield(c, _CT_LO), hi = getfield(c, _CT_HI))
    end
    _device_fill!(backend, c.contact_nbr, 0)
    _device_fill!(backend, c.contact_measure, 0)
    _device_fill!(backend, c.contact_medium, 0)
    _device_fill!(backend, c.contact_overflow, 0)
    Exec.launch!(
        backend, _contact_body!,
        n,
        (
            c.contact_nbr, c.contact_measure, c.contact_medium,
            c.contact_overflow, st.ownership, ctx.lattice, rel, u, sc,
        )
    )
    u === nothing && return 5
    Exec.launch!(
        backend, _contact_fold_body!, size(c.contact_measure, 2),
        (c.contact_measure, c.contact_medium, sc, u)
    )
    return 6
end

"""Slot of `b` in `a`'s contact row, or 0 (device or host)."""
@inline function contact_slot(cell, a, b)
    for k in 1:size(cell.contact_nbr, 1)
        # bounds: k over the rows of contact_nbr; a is a cell id ≤ capacity
        @inbounds(cell.contact_nbr[k, a]) == b && return k
    end
    return 0
end
"""
Shared interface measure of cells `a` and `b` from the contact table (`b = 0`: medium).
"""
@inline function contact_measure(cell, a, b)
    # bounds: a is a cell id ≤ capacity = length(cell.contact_medium)
    b == 0 && return @inbounds cell.contact_medium[a]
    k = contact_slot(cell, a, b)
    return if k == 0
        zero(eltype(cell.contact_measure))
    else
        @inbounds cell.contact_measure[k, a]
    end
end
