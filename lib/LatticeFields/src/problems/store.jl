# The arrays of a program on a backend: one or two buffers per field (contract item 2) and
# one array per table. A two-buffer field has a current slot; a step's slot swaps flip it.

"""
    FieldStore(backend, p::Program; flat = String[], E = nothing, nbuf = nothing, TE = nothing)

Zero-filled arrays for every field of `p` on `backend` (KernelAbstractions allocation), one
per buffer, `nsites × ncomp` elements of the field's storage lane; and an empty slot per
table (set with [`settable!`](@ref)). `cur[f]` is the current slot of field `f` (1 or 2).

`E` is the problem's element type (P5 role model): a float lane holds
[`lanetype`](@ref LatticeFields.Compile.lanetype)`(lane, value_type(E), :state, fixed)` wrapped like `E`
(a field with a declared storage, `fixed`, holds its own lane type, FE-17)
(a Dual of it when `E` is a Dual): the state lanes hold the problem's value type (BigFloat
under `T = BigFloat`, Float64 after a Float64 `u0`), and Dual parameters give Dual fields.
Integer lanes keep their type; tables take the value type, and a Dual of it only when the
tables themselves carry derivative parts (`TE`, the element type of the problem's table
values, is a Dual; then `E` is one too). `nothing`: each lane's own Julia type.

The fields named in `flat` (the state, in that order) are packed: each buffer slot is one
flat array per slot (`st.flat[slot]`), and the field's buffers are contiguous views of it at
`st.slots[f]`. The packed fields share one lane and one buffer count, so they swap together
and `st.flat[st.cur[f]]` is the whole current state. `nbuf` is the buffer count an algorithm
declares for them (`nbuffers(alg)`): with more than the program's two, the extra buffers are
the algorithm's (history, `c__prev`); the steps use the first two.

State fields with different storage (a declared `lattice_storage` beside the problem's type,
batch 5 review S2) are not packed: each has its own arrays, as in a coupled `PottsProblem`; `st.flat` is
empty and `st.slots` still places each in the flat state vector ([`mixed_state`](@ref)).
"""
struct FieldStore{B}
    backend::B
    bufs::Vector{Vector{Any}}
    cur::Vector{Int}
    tables::Vector{Any}
    flat::Vector{Any}
    slots::Vector{UnitRange{Int}}
end
_eltype(lane, ::Nothing, fixed::Bool = false) = juliatype(lane)
function _eltype(lane, ::Type{E}, fixed::Bool = false) where {E}
    isfloat(lane) || return juliatype(lane)
    return withvaltype(E, lanetype(lane, value_type(E), :state, fixed))
end
_tabletype(lane, ::Nothing, _) = juliatype(lane)
function _tabletype(lane, ::Type{E}, TE) where {E}
    isfloat(lane) || return juliatype(lane)
    V = lanetype(lane, value_type(E), :state)
    return TE === nothing || value_type(TE) === TE ? V : withvaltype(E, V)
end
# The front ends' generic device bodies (copies, clamps, the implicit steps' bodies) and
# GPUArrays' fill, registered for the D-157 scan once a store on a device whose default float
# is Float32 holds Float64 (a declared `lattice_storage`, or a declared T = Float64: R-F3c)
_generic_bodies() = (_copy_body!, _clamp_body!, _clamp_field_body!, _zero_body!, _clip_body!, _be_norms_body!,
    _be_newton_body!, _be_kappa_norms_body!, _be_kappa_newton_body!, _reset_hist_body!,
    _be_gate_iter_body!, _be_gate_body!, _be_update_body!, _be_shift_body!, _be_rhs_body!,
    _be_status_body!, _bdf2_q_body!)
function _register_float64_store!(backend, bufs)
    (Exec.ishost(backend) || Exec.default_float(backend) === Float64) && return nothing
    any(b -> any(a -> eltype(a) <: AbstractFloat && value_type(eltype(a)) === Float64, b), bufs) || return nothing
    # keyed on a Float64 device array in the signature (batch 5 review N4): an instance of these
    # bodies over Float32 arrays that reaches a Float64 scalar is still flagged
    foreach(f -> Exec.register_float64!(string(typeof(f)), Exec.FLOAT64_ARRAY), _generic_bodies())
    Exec.register_float64!("gpu_fill_kernel", Exec.FLOAT64_ARRAY)
    return nothing
end
function FieldStore(backend, p::Program; flat = String[], E = nothing, nbuf = nothing, TE = nothing)
    ids = Int[fieldid(p, k) for k in flat]
    slots, flatbufs = state_layout(p, ids), Any[]
    packed = false
    if !isempty(ids)
        fs = p.fields[ids]
        all(f -> f.buffers == fs[1].buffers, fs) ||
            throw(ArgumentError("the state fields need one buffer count (a stepped field has two)"))
        # one element type: packed in one flat array per slot; mixed storage: each field its own
        packed = all(f -> _eltype(f.storage, E, f.fixed) === _eltype(fs[1].storage, E, fs[1].fixed), fs)
        if packed
            n = maximum(last, slots[ids])
            flatbufs = Any[_zeros(backend, _eltype(fs[1].storage, E, fs[1].fixed), n)
                           for _ in 1:(nbuf === nothing ? fs[1].buffers : max(fs[1].buffers, nbuf))]
        end
    end
    bufs = map(enumerate(p.fields)) do (i, f)
        packed && i in ids && return Any[view(a, slots[i]) for a in flatbufs]
        n = nsites(p, f.levels[1]) * ncomp(f)
        nb = i in ids && nbuf !== nothing ? max(f.buffers, nbuf) : f.buffers
        Any[_zeros(backend, _eltype(f.storage, E, f.fixed), n) for _ in 1:nb]
    end
    tables = Any[_zeros(backend, _tabletype(t.storage, E, TE), 1) for t in p.tables]
    _register_float64_store!(backend, bufs)
    return FieldStore(backend, bufs, ones(Int, length(p.fields)), tables, flatbufs, slots)
end
function FieldStore(backend, bufs, cur, tables)
    _register_float64_store!(backend, bufs)
    FieldStore(backend, bufs, cur, tables, Any[],
        fill(1:0, length(bufs)))
end

"""
    mixed_state(st) -> Bool

Whether the state fields of store `st` have different storage (no flat arrays; each field its
own arrays, placed in the flat state vector by `st.slots`; batch 5 review S2).
"""
mixed_state(st::FieldStore) = isempty(st.flat) && any(!isempty, st.slots)
# the state fields of a mixed store, in flat order (by their slots)
_state_ids(st::FieldStore) = sort!([i for i in eachindex(st.slots) if !isempty(st.slots[i])]; by = i -> first(st.slots[i]))

"""
    MixedState(st, E)

The current state of a mixed store ([`mixed_state`](@ref)) as one flat vector of element type
`E` (SciML's `state_values`): a read gathers from each field's current array, a write
scatters into it (each field in its own storage type). A host copy per access: a write path,
not a step path.
"""
struct MixedState{E, ST <: FieldStore} <: AbstractVector{E}
    st::ST
end
MixedState(st::FieldStore, ::Type{E}) where {E} = MixedState{E, typeof(st)}(st)
Base.size(m::MixedState) = (sum(length, m.st.slots),)
Base.IndexStyle(::Type{<:MixedState}) = IndexLinear()
function _field_at(st::FieldStore, k::Integer)
    for i in eachindex(st.slots)
        k in st.slots[i] && return i, k - first(st.slots[i]) + 1
    end
    throw(BoundsError(MixedState(st, Float64), k))
end
function Base.getindex(m::MixedState{E}, k::Integer) where {E}
    i, j = _field_at(m.st, k)
    return E(Array(view(array(m.st, i, :cur), j:j))[1])
end
function Base.setindex!(m::MixedState, v, k::Integer)
    i, j = _field_at(m.st, k)
    a = array(m.st, i, :cur)
    copyto!(view(a, j:j), eltype(a)[convert(eltype(a), v)])
    return v
end
# a whole range or index array: one host copy per field it touches
# (an index array inside one field reads in that field's own type, as `integ[c]` does)
function Base.getindex(m::MixedState{E}, I::AbstractArray{<:Integer}) where {E}
    isempty(I) && return Array{E}(undef, size(I))
    i1, _ = _field_at(m.st, first(I))
    one = all(k -> k in m.st.slots[i1], I)
    out = Array{one ? eltype(array(m.st, i1, :cur)) : E}(undef, size(I))
    hosts = Dict{Int, Any}()
    for (n, k) in enumerate(I)
        i, j = _field_at(m.st, k)
        h = get!(() -> Array(array(m.st, i, :cur)), hosts, i)
        out[n] = h[j]
    end
    return out
end
function Base.setindex!(m::MixedState, v, I::AbstractArray{<:Integer})
    hosts = Dict{Int, Any}()
    vals = v isa AbstractArray ? Array(v) : v
    for (n, k) in enumerate(I)
        i, j = _field_at(m.st, k)
        h = get!(() -> Array(array(m.st, i, :cur)), hosts, i)
        h[j] = vals isa AbstractArray ? vals[firstindex(vals) + n - 1] : vals
    end
    for (i, h) in hosts
        copyto!(array(m.st, i, :cur), h)
    end
    return v
end
Base.setindex!(m::MixedState, v, ::Colon) = setindex!(m, v, eachindex(m))

"""
    state_layout(p, ids) -> Vector{UnitRange{Int}}

Ranges of the fields `ids` (in order) in a flat state vector; empty ranges for the others.
"""
function state_layout(p::Program, ids)
    slots = fill(1:0, length(p.fields))
    off = 0
    for i in ids
        n = nsites(p, p.fields[i].levels[1]) * ncomp(p.fields[i])
        slots[i] = (off + 1):(off + n)
        off += n
    end
    return slots
end

_zeros(backend, ::Type{E}, n) where {E} = fill!(KA.allocate(backend, E, n), zero(E))

"""
    array(st, id, role, cur = st.cur[id]) -> array

The array bound to `(id, role)` (contract item 2): `:cur`/`:next` select the current or the
other slot of a two-buffer field (the only slot of a one-buffer field); `:table` a table.
"""
function array(st::FieldStore, id::Integer, role::Symbol, cur::Integer = st.cur[id])
    role == :table && return st.tables[id]
    b = st.bufs[id]
    length(b) == 1 && return b[1]
    return b[role == :next ? 3 - cur : cur]
end

"""
    current(st, p, key) -> array

The current array of field `key`.
"""
current(st::FieldStore, p::Program, key::AbstractString) = array(st, fieldid(p, key), :cur)

"""
    settable!(st, p, key, values)

Upload `values` into table `key` (in the table's element type in this store).
"""
function settable!(st::FieldStore, p::Program, key::AbstractString, values)
    i = findfirst(t -> t.key == key, p.tables)
    i === nothing && throw(ArgumentError("no table `$key` in the program"))
    E = eltype(st.tables[i])
    a = KA.allocate(st.backend, E, length(values))
    copyto!(a, E.(collect(values)))
    st.tables[i] = a
    return st
end

"""
    launch_arrays(st, spec, cur) -> S

The array tuple of a launch (contract item 2) with the current slots `cur` (a vector by
field id).
"""
function launch_arrays(st::FieldStore, spec::LaunchSpec, cur = st.cur)
    return Tuple(Tuple(array(st, id, role, role == :table ? 0 : cur[id])
                 for (id, role) in lane)
    for lane in spec.bind)
end
