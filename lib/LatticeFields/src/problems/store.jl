# The arrays of a program on a backend: one or two buffers per field (contract item 2) and
# one array per table. A two-buffer field has a current slot; a step's slot swaps flip it.

"""
    FieldStore(backend, p::Program; flat = String[], E = nothing, nbuf = nothing)

Zero-filled arrays for every field of `p` on `backend` (KernelAbstractions allocation), one
per buffer, `nsites × ncomp` elements of the field's storage lane; and an empty slot per
table (set with [`settable!`](@ref)). `cur[f]` is the current slot of field `f` (1 or 2).

`E` is the problem's element type (P5 role model): a float lane holds
[`lanetype`](@ref LatticeFields.Compile.lanetype)`(lane, valtype(E), :state)` wrapped like `E`
(a Dual of it when `E` is a Dual): the state lanes hold the problem's value type (BigFloat
under `T = BigFloat`, Float64 after a Float64 `u0`), and Dual parameters give Dual fields.
Integer lanes keep their type; tables take the value type, never a Dual. `nothing`: each
lane's own Julia type.

The fields named in `flat` (the state, in that order) are packed: each buffer slot is one
flat array per slot (`st.flat[slot]`), and the field's buffers are contiguous views of it at
`st.slots[f]`. The packed fields share one lane and one buffer count, so they swap together
and `st.flat[st.cur[f]]` is the whole current state. `nbuf` is the buffer count an algorithm
declares for them (`nbuffers(alg)`): with more than the program's two, the extra buffers are
the algorithm's (history, `c__prev`); the steps use the first two.
"""
struct FieldStore{B}
    backend::B
    bufs::Vector{Vector{Any}}
    cur::Vector{Int}
    tables::Vector{Any}
    flat::Vector{Any}
    slots::Vector{UnitRange{Int}}
end
_eltype(lane, ::Nothing) = juliatype(lane)
function _eltype(lane, ::Type{E}) where {E}
    isfloat(lane) || return juliatype(lane)
    return withvaltype(E, lanetype(lane, valtype(E), :state))
end
_tabletype(lane, ::Nothing) = juliatype(lane)
_tabletype(lane, ::Type{E}) where {E} = isfloat(lane) ? lanetype(lane, valtype(E), :state) : juliatype(lane)
function FieldStore(backend, p::Program; flat = String[], E = nothing, nbuf = nothing)
    ids = Int[fieldid(p, k) for k in flat]
    slots, flatbufs = state_layout(p, ids), Any[]
    if !isempty(ids)
        fs = p.fields[ids]
        all(f -> f.storage == fs[1].storage && f.buffers == fs[1].buffers, fs) ||
            throw(ArgumentError("packed fields need one storage lane and one buffer count"))
        n = maximum(last, slots[ids])
        flatbufs = Any[_zeros(backend, _eltype(fs[1].storage, E), n)
                       for _ in 1:(nbuf === nothing ? fs[1].buffers : max(fs[1].buffers, nbuf))]
    end
    bufs = map(enumerate(p.fields)) do (i, f)
        i in ids && return Any[view(a, slots[i]) for a in flatbufs]
        n = nsites(p, f.levels[1]) * ncomp(f)
        Any[_zeros(backend, _eltype(f.storage, E), n) for _ in 1:(f.buffers)]
    end
    tables = Any[_zeros(backend, _tabletype(t.storage, E), 1) for t in p.tables]
    return FieldStore(backend, bufs, ones(Int, length(p.fields)), tables, flatbufs, slots)
end
function FieldStore(backend, bufs, cur, tables)
    FieldStore(backend, bufs, cur, tables, Any[],
        fill(1:0, length(bufs)))
end

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
