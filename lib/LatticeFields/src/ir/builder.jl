# The interning builder (hash-consing, R3 §2: no separate canonicalize pass). Every node is
# interned on (op, type, operands, imm); commutative operands are flattened (ADD, MUL) and
# sorted by a structural order that never looks at node ids, so equal expressions get equal
# ids whatever the build order. `finish` renumbers nodes, accesses and constants in a
# canonical depth-first order from the sorted stores. Passes never mutate nodes: they rebuild
# through this builder (`rebuild`), so a folded DAG is canonical again.

mutable struct KernelBuilder{N}
    fieldkeys::Vector{String}
    fieldlanes::Vector{Scalar}
    tablekeys::Vector{String}
    space::Space{N}
    nodes::Vector{Node}
    operands::Vector{Int32}
    consts::Vector{Float64}
    accesses::Vector{Access{N}}
    calls::Vector{Symbol}
    stores::Vector{Store{N}}
    reductions::Vector{Reduction}
    interned::Dict{Tuple{Op, Scalar, Vector{Int32}, Int64}, Int32}
    constid::Dict{UInt64, Int32}
    accid::Dict{Access{N}, Int32}
end
function KernelBuilder{N}(fieldkeys, fieldlanes, tablekeys, space::Space{N}) where {N}
    return KernelBuilder{N}(
        fieldkeys, fieldlanes, tablekeys, space, Node[], Int32[], Float64[],
        Access{N}[], Symbol[], Store{N}[], Reduction[],
        Dict{Tuple{Op, Scalar, Vector{Int32}, Int64}, Int32}(),
        Dict{UInt64, Int32}(), Dict{Access{N}, Int32}())
end

"""
A node handle for writing expressions with ordinary operators.
"""
struct Ex{B}
    b::B
    id::Int32
end

nodeargs(b::KernelBuilder, i) = view(b.operands, b.nodes[i].args)

# ---- structural order (never uses node ids, so it is build-order independent) ----------
_cmp(a, b) = isless(a, b) ? -1 : isless(b, a) ? 1 : 0
function _accesscmp(b::KernelBuilder, x::Access, y::Access)
    c = _cmp(b.fieldkeys[x.field], b.fieldkeys[y.field])
    c == 0 || return c
    c = _cmp((x.class, x.comp.a, x.comp.b, x.offset.a, x.offset.b, x.level, Int(x.policy)),
        (y.class, y.comp.a, y.comp.b, y.offset.a, y.offset.b, y.level, Int(y.policy)))
    c == 0 || return c
    c = scmp(b, x.comp.cond, y.comp.cond)
    return c != 0 ? c : scmp(b, x.offset.cond, y.offset.cond)
end

function _payloadcmp(b::KernelBuilder, n::Node, m::Node)
    op = n.op
    op == CONST && return _cmp(b.consts[n.imm], b.consts[m.imm])
    op in (LOAD, INSIDE_OP) && return _accesscmp(b, b.accesses[n.imm], b.accesses[m.imm])
    op == TABLE && return _cmp(b.tablekeys[n.imm], b.tablekeys[m.imm])
    op == CALL && return _cmp(b.calls[n.imm], b.calls[m.imm])
    return _cmp(n.imm, m.imm)
end

"""
Structural comparison of nodes `i` and `j` (−1, 0, 1); `0` is the absent node.
"""
function scmp(b::KernelBuilder, i::Integer, j::Integer)
    i == j && return 0
    i == 0 && return -1
    j == 0 && return 1
    n, m = b.nodes[i], b.nodes[j]
    c = _cmp((opname(n.op), string(n.type)), (opname(m.op), string(m.type)))
    c == 0 || return c
    c = _payloadcmp(b, n, m)
    c == 0 || return c
    c = _cmp(length(n.args), length(m.args))
    c == 0 || return c
    for (x, y) in zip(nodeargs(b, i), nodeargs(b, j))
        c = scmp(b, x, y)
        c == 0 || return c
    end
    return 0
end

# ---- interning ---------------------------------------------------------------------------
"""
Intern a node; flattens and sorts commutative operands.
"""
function node!(b::KernelBuilder, op::Op, type::Scalar,
        args::Vector{Int32} = Int32[], imm::Integer = 0;
        flatten = true)
    if flatten && op in (ADD, MUL)
        flat = Int32[]
        for a in args
            n = b.nodes[a]
            n.op == op && n.type == type ? append!(flat, nodeargs(b, a)) : push!(flat, a)
        end
        args = flat
        length(args) == 1 && return args[1]
    end
    op in COMMUTATIVE && sort!(args; lt = (x, y) -> scmp(b, x, y) < 0)
    key = (op, type, args, Int64(imm))
    id = get(b.interned, key, Int32(0))
    id != 0 && return id
    lo = Int32(length(b.operands) + 1)
    append!(b.operands, args)
    push!(b.nodes, Node(op, type, lo:Int32(length(b.operands)), Int64(imm)))
    id = Int32(length(b.nodes))
    b.interned[key] = id
    return id
end

"""
A constant (Float64, interned by bit pattern so `0.0` and `-0.0` stay distinct).
"""
function constant!(b::KernelBuilder, v::Real, type::Scalar = REAL)
    v = Float64(v)
    k = get!(b.constid, reinterpret(UInt64, v)) do
        push!(b.consts, v)
        Int32(length(b.consts))
    end
    return node!(b, CONST, type, Int32[], k)
end

function access!(b::KernelBuilder{N}, a::Access{N}) where {N}
    return get!(b.accid, a) do
        push!(b.accesses, a)
        Int32(length(b.accesses))
    end
end

"""
Element type a LOAD of field `f` produces: integer lanes keep their type, floats compute.
"""
loadtype(s::Scalar) = isfloat(s) ? REAL : s

function load!(
        b::KernelBuilder{N}, field::Integer, storage::Scalar; offset = ntuple(_ -> 0, N),
        comp = 1, level = 0, policy = RESOLVE, class = 0) where {N}
    off = offset isa Sel ? offset : Sel(NTuple{N, Int16}(offset))
    cmp = comp isa Sel ? comp : Sel(Int16(comp))
    a = Access{N}(Int32(field), Int8(class), cmp, off, Int8(level), policy)
    return node!(b, LOAD, loadtype(storage), Int32[], access!(b, a))
end

param!(b::KernelBuilder, slot::Integer) = node!(b, PARAM, REAL, Int32[], slot)
runtime!(b::KernelBuilder, slot::Integer) = node!(b, RUNTIME, REAL, Int32[], slot)
coord!(b::KernelBuilder, axis::Integer) = node!(b, COORD, I32, Int32[], axis)
function table!(b::KernelBuilder, table::Integer, storage::Scalar, index::Integer)
    node!(
        b, TABLE, loadtype(storage), Int32[cast!(b, index, I32)], table)
end
function call!(b::KernelBuilder, f::Symbol, x::Integer)
    f in CALLS || error("CALL: `$f` is not in the whitelist $(CALLS)")
    k = findfirst(==(f), b.calls)
    k === nothing && (push!(b.calls, f); k = length(b.calls))
    return node!(b, CALL, REAL, Int32[cast!(b, x, REAL)], k)
end

# ---- typing -------------------------------------------------------------------------------
function cast!(b::KernelBuilder, x::Integer, t::Scalar)
    b.nodes[x].type == t && return Int32(x)
    n = b.nodes[x]
    if n.op == CONST
        c = b.consts[n.imm]
        return constant!(b, t in (F16, F32) ? Float64(juliatype(t)(c)) : c, t)
    end
    return node!(b, CAST, t, Int32[x])
end

"""
Common type of numeric operands: any float makes `REAL`; mixed integers promote to I32.
"""
function jointype(b::KernelBuilder, xs)
    ts = [b.nodes[x].type for x in xs]
    any(isfloat, ts) && return REAL
    return all(==(ts[1]), ts) ? ts[1] : I32
end

function arith!(b::KernelBuilder, op::Op, xs::Integer...; type = jointype(b, xs))
    return node!(b, op, type, Int32[cast!(b, x, type) for x in xs])
end
function compare!(b::KernelBuilder, op::Op, x::Integer, y::Integer)
    t = jointype(b, (x, y))
    return node!(b, op, BOOL, Int32[cast!(b, x, t), cast!(b, y, t)])
end
"""
Eager select (both arms computed, emitted as `ifelse`).
"""
function select!(b::KernelBuilder, c, x, y; op = SELECT)
    (t = jointype(b, (x, y));
        node!(b, op, t, Int32[c, cast!(b, x, t), cast!(b, y, t)]))
end
"""
Lazy conditional (user `ifelse`, D-014): emitted as a branch.
"""
cond!(b::KernelBuilder, c, x, y) = select!(b, c, x, y; op = COND)
function bittest!(b::KernelBuilder, x::Integer, bit::Integer)
    (isunsigned_lane(b.nodes[x].type) ||
            error("BITTEST needs an unsigned operand");
        node!(b, BITTEST, BOOL, Int32[x], bit))
end

function store!(b::KernelBuilder{N}, field::Integer, storage::Scalar, value::Integer;
        comp = 1, law = :owned) where {N}
    isfloat(storage) && (value = cast!(b, value, REAL))
    a = Access{N}(Int32(field), Int8(0), Sel(Int16(comp)),
        Sel(ntuple(_ -> Int16(0), N)), Int8(0), INSIDE)
    push!(b.stores, Store{N}(a, Int32(value), law))
    return nothing
end

# ---- operators on handles -----------------------------------------------------------------
_id(b, x::Ex) = x.id
_id(b, x::Real) = constant!(b, x)
# Written out (no `@eval Base.$f`): the frozen seed scan reads definition names literally.
_bin(op, x::Ex, y::Union{Ex, Real}) = Ex(x.b, arith!(x.b, op, x.id, _id(x.b, y)))
_bin(op, x::Real, y::Ex) = Ex(y.b, arith!(y.b, op, _id(y.b, x), y.id))
_un(op, x::Ex) = Ex(x.b, arith!(x.b, op, x.id;
    type = op in (NEG, ABS) ? jointype(x.b, (x.id,)) : REAL))
Base.:+(x::Ex, y::Union{Ex, Real}) = _bin(ADD, x, y)
Base.:+(x::Real, y::Ex) = _bin(ADD, x, y)
Base.:*(x::Ex, y::Union{Ex, Real}) = _bin(MUL, x, y)
Base.:*(x::Real, y::Ex) = _bin(MUL, x, y)
Base.:/(x::Ex, y::Union{Ex, Real}) = _bin(DIV, x, y)
Base.:/(x::Real, y::Ex) = _bin(DIV, x, y)
Base.min(x::Ex, y::Union{Ex, Real}) = _bin(MIN, x, y)
Base.min(x::Real, y::Ex) = _bin(MIN, x, y)
Base.max(x::Ex, y::Union{Ex, Real}) = _bin(MAX, x, y)
Base.max(x::Real, y::Ex) = _bin(MAX, x, y)
Base.:-(x::Ex) = _un(NEG, x)
Base.abs(x::Ex) = _un(ABS, x)
Base.sqrt(x::Ex) = _un(SQRT, x)
Base.exp(x::Ex) = _un(EXP, x)
Base.log(x::Ex) = _un(LOG, x)
Base.:-(x::Ex, y::Ex) = x + (-y)
Base.:-(x::Ex, y::Real) = x + Ex(x.b, constant!(x.b, -y))
Base.:-(x::Real, y::Ex) = Ex(y.b, constant!(y.b, x)) + (-y)
function Base.:^(x::Ex, n::Integer)
    t = x.b.nodes[x.id].type
    n < 0 && !isfloat(t) && error("POWI: negative exponent on an integer ($t) operand")
    return Ex(x.b, node!(x.b, POWI, t, Int32[x.id], n))
end
Base.:<(x::Ex, y::Union{Ex, Real}) = Ex(x.b, compare!(x.b, LT, x.id, _id(x.b, y)))
Base.:<(x::Real, y::Ex) = Ex(y.b, compare!(y.b, LT, _id(y.b, x), y.id))
Base.:<=(x::Ex, y::Union{Ex, Real}) = Ex(x.b, compare!(x.b, LE, x.id, _id(x.b, y)))
Base.:<=(x::Real, y::Ex) = Ex(y.b, compare!(y.b, LE, _id(y.b, x), y.id))
eq(x::Ex, y) = Ex(x.b, compare!(x.b, EQ, x.id, _id(x.b, y)))
select(c::Ex, x, y) = Ex(c.b, select!(c.b, c.id, _id(c.b, x), _id(c.b, y)))
cond(c::Ex, x, y) = Ex(c.b, cond!(c.b, c.id, _id(c.b, x), _id(c.b, y)))

# ---- canonical finish ---------------------------------------------------------------------
"""
Node dependencies, including `Sel` conditions carried by accesses.
"""
function deps(b::KernelBuilder, i::Integer)
    n = b.nodes[i]
    d = collect(Int32, nodeargs(b, i))
    if n.op in (LOAD, INSIDE_OP)
        a = b.accesses[n.imm]
        a.comp.cond != 0 && push!(d, a.comp.cond)
        a.offset.cond != 0 && push!(d, a.offset.cond)
    end
    return d
end

function _storeless(b::KernelBuilder, s::Store, t::Store)
    c = _accesscmp(b, s.access, t.access)
    return c != 0 ? c < 0 : scmp(b, s.value, t.value) < 0
end

"""
Canonical kernel: nodes renumbered depth-first from the sorted stores and reductions;
unused nodes, accesses and constants dropped.
"""
function finish(b::KernelBuilder{N}, key::AbstractString) where {N}
    stores = sort(b.stores; lt = (s, t) -> _storeless(b, s, t))
    order = Int32[]
    seen = falses(length(b.nodes))
    visit(i) = (
        seen[i] && return; seen[i] = true; foreach(visit, deps(b, i)); push!(order, i))
    foreach(s -> visit(s.value), stores)
    foreach(r -> visit(r.value), b.reductions)
    newid = zeros(Int32, length(b.nodes))
    newid[order] .= 1:length(order)
    nodes, operands, consts, accesses, calls = Node[], Int32[], Float64[], Access{N}[],
    Symbol[]
    remapc(c) = c == 0 ? Int32(0) : newid[c]
    function slot!(v, x)
        k = findfirst(isequal(x), v)
        k === nothing ? (push!(v, x); length(v)) : k
    end
    for i in order
        n = b.nodes[i]
        lo = Int32(length(operands) + 1)
        append!(operands, newid[nodeargs(b, i)])
        imm = n.imm
        if n.op == CONST
            imm = slot!(consts, b.consts[n.imm])
        elseif n.op in (LOAD, INSIDE_OP)
            a = b.accesses[n.imm]
            imm = slot!(accesses,
                Access{N}(a.field, a.class, Sel(a.comp.a, a.comp.b, remapc(a.comp.cond)),
                    Sel(a.offset.a, a.offset.b, remapc(a.offset.cond)), a.level, a.policy))
        elseif n.op == CALL
            imm = slot!(calls, b.calls[n.imm])
        end
        push!(nodes, Node(n.op, n.type, lo:Int32(length(operands)), imm))
    end
    st = [Store{N}(s.access, newid[s.value], s.law) for s in stores]
    red = [Reduction(r.op, newid[r.value], r.target) for r in b.reductions]
    tabs = Int32[n.imm for n in nodes if n.op == TABLE]
    return Kernel{N}(
        String(key), b.space, nodes, operands, consts, accesses, unique!(tabs),
        calls, st, red)
end

"""
    rebuild(f, k, keys; space, fieldmap, tablemap)

Rebuild kernel `k` through a fresh builder. For each node in order, `f(b, k, i, newargs, ctx)`
returns the new id, with `ctx = (newids, fieldmap, tablemap)`; `copy_node!` re-interns it unchanged. `fieldmap`/`tablemap` renumber
field and table ids; `keys = (fieldkeys, fieldlanes, tablekeys)` of the target program.
This is how every semantic pass changes a kernel.
"""
function rebuild(f::F, k::Kernel{N}, keys::Tuple; space = k.space, fieldmap = identity,
        tablemap = identity, key = k.key, storefn = (b, s, v) -> v) where {F, N}
    b = KernelBuilder{N}(keys..., space)
    new = zeros(Int32, length(k.nodes))
    for i in eachindex(k.nodes)
        new[i] = f(b, k, i, Int32[new[a] for a in args(k, i)], (new, fieldmap, tablemap))
    end
    for s in k.stores
        a = s.access
        s2 = Store{N}(
            Access{N}(
                Int32(fieldmap(a.field)), a.class, a.comp, a.offset, a.level, a.policy),
            new[s.value], s.law)
        push!(b.stores, Store{N}(s2.access, storefn(b, s2, s2.value), s.law))
    end
    append!(b.reductions, (Reduction(r.op, new[r.value], r.target) for r in k.reductions))
    return finish(b, key)
end

"""
Re-intern node `i` of `k` with new operands (the default `rebuild` callback).
"""
function copy_node!(b::KernelBuilder{N}, k::Kernel{N}, i, newargs, ctx) where {N}
    new, fieldmap, tablemap = ctx
    n = k.nodes[i]
    n.op == CONST && return constant!(b, k.consts[n.imm], n.type)
    n.op == CALL && return call!(b, k.calls[n.imm], newargs[1])
    imm = n.imm
    if n.op in (LOAD, INSIDE_OP)
        imm = access!(b, remap_access(k.accesses[n.imm], new, fieldmap))
    elseif n.op == TABLE
        imm = tablemap(n.imm)
    end
    return node!(b, n.op, n.type, newargs, imm)
end
function remap_access(a::Access{N}, new, fieldmap) where {N}
    rc(c) = c == 0 ? Int32(0) : new[c]
    return Access{N}(
        Int32(fieldmap(a.field)), a.class, Sel(a.comp.a, a.comp.b, rc(a.comp.cond)),
        Sel(a.offset.a, a.offset.b, rc(a.offset.cond)), a.level, a.policy)
end
