# The canonical lowering (moved from Potts `lower.jl`, v3 §5.1): an MTK term becomes IR nodes
# in a `KernelBuilder`. Order independence (D-107) comes from the builder: every node is
# interned and the operands of a commutative op are sorted structurally, so Symbolics' hash
# order of a sum's operands never reaches the IR. Literals stay Float64 in the IR and are
# rounded once to `T` at emission; `ifelse` is lazy (COND, D-014).
#
# Spatial operators lower to the face-flux form (§5.2): one per-axis second difference
# `(1/h²) Σ± K_face (c± − c)`, summed over axes for `Δ` and `DivKGrad`. A raw `Dx(Dx(c))` or
# `Dx(K * Dx(c))` lowers through the same primitive, so it gives the same IR (P3-rev item 5).
# Neighbor values of `c` are `RESOLVE` loads (pass 2 applies the face rules). A face
# coefficient is evaluated at the neighbor with `RESOLVE` loads of the fields that have face
# rules (the rate fields: at a face of the box it takes the field's ghost value, the value the
# face rule gives the gradient; F3-ghost, user OK 2026-10-26) and `CLAMP` loads of the others
# (an input or aux field takes the inner value).

const RAW_HINT = "write a spatial operator as `Δ(c)`, `DivKGrad(:harmonic)(K, c)`, `Dx(Dx(c))` or `Dx(K * Dx(c))`"

"""
Everything a lowering needs. `fields` maps a dependent variable's operation to its field ids
(one per component) and lanes; `params` a scalar parameter to its slot; `tables` an array
parameter to its table id; `spacing` a `lattice_spacing` parameter to its axis. `offset` and
`policy` shift every load (a coefficient evaluated at a neighbor). `map`: offset reads are
allowed. `leaf(x, env)` may lower a term itself (CPM reads from Potts) or return `nothing`.
"""
struct Env{N, B, L}
    kb::B
    fields::Dict{Any, Tuple{Vector{Int32}, Scalar}}
    params::Dict{Any, Int}
    tables::Dict{Any, Tuple{Int32, Scalar}}
    spacing::Dict{Any, Int}
    t::Any
    xs::Vector
    lo::NTuple{N, Float64}
    h::NTuple{N, Float64}
    map::Bool
    offset::NTuple{N, Int}
    policy::Bpolicy
    leaf::L
    hex::Bool                          # hexagonal grid (axial coordinates, 2D)
    domain::Int32                      # field id of the domain's Bool input, 0 for the box
    ghosted::Vector{Int32}             # the fields whose face-coefficient reads take the ghost value
    # `Coarse` levels (F3-16): the kernel's level (`h` is its spacing), each field's level by
    # its operation (a field missing from it is fine), the fine dims (an axis of size 1 is never
    # coarsened), and `child > 0` inside a fold over the children `child` levels down
    level::Int
    flev::Dict{Any, Int}
    dims::NTuple{N, Int}
    child::Int
end
Env(kb, fields, params, tables, spacing, t, xs, lo::NTuple{N}, h, map, offset, policy, leaf, hex, domain) where {N} =
    Env(kb, fields, params, tables, spacing, t, xs, lo, h, map, offset, policy, leaf, hex, domain, Int32[])
Env(kb, fields, params, tables, spacing, t, xs, lo::NTuple{N}, h, map, offset, policy, leaf, hex, domain, ghosted) where {N} =
    Env(kb, fields, params, tables, spacing, t, xs, lo, h, map, offset, policy, leaf, hex, domain, ghosted, 0,
        Dict{Any, Int}(), ntuple(_ -> 2, N), 0)
# a coefficient at a neighbor: `face = true` (a face coefficient of a second difference) reads
# the ghosted fields with `RESOLVE`, the others with `CLAMP`
_shift(e::Env{N}, o; face::Bool = false) where {N} = Env(e.kb, e.fields, e.params, e.tables, e.spacing, e.t, e.xs, e.lo, e.h,
    e.map, ntuple(d -> e.offset[d] + o[d], N), face ? RESOLVE : CLAMP, e.leaf, e.hex, e.domain, e.ghosted, e.level,
    e.flev, e.dims, e.child)
# the environment inside a fold over the children `m` levels down (F3-16)
_infold(e::Env, m) = Env(e.kb, e.fields, e.params, e.tables, e.spacing, e.t, e.xs, e.lo, e.h, e.map, e.offset, e.policy,
    e.leaf, e.hex, e.domain, e.ghosted, e.level, e.flev, e.dims, m)
_flevel(e::Env, op) = get(e.flev, op, 0)
"""
    level_spacing(h, dims, level) -> NTuple

The spacing of `Coarse` level `level` (the factor `2^level`) of a grid of spacing `h` and
`dims` sites: `2^level h` on every axis but one of size 1, which is never coarsened.
"""
level_spacing(h::NTuple{N}, dims, level::Integer) where {N} = ntuple(d -> dims[d] == 1 ? h[d] : h[d] * 2^level, N)
_unit(::Env{N}, d, s) where {N} = ntuple(i -> i == d ? s : 0, N)
_lerr(x, msg) = throw(ArgumentError(as_written("cannot lower `$x`: $msg")))   # the term as written (review R3)
_type(e::Env, i) = e.kb.nodes[i].type

# numeric operands: a Bool counts as 0/1 (I32, or REAL next to a float)
function _num(e::Env, ids)
    t = any(i -> isfloat(_type(e, i)), ids) ? REAL : nothing
    return [_type(e, i) == BOOL ? cast!(e.kb, i, t === nothing ? I32 : t) : i for i in ids]
end
_op(e::Env, op, ids...) = arith!(e.kb, op, _num(e, collect(Int32, ids))...)
_real(e::Env, i) = cast!(e.kb, _num(e, [i])[1], REAL)
_bool(e::Env, i) = _type(e, i) == BOOL ? i : node!(e.kb, NOT, BOOL, Int32[_cmp(e, EQ, i, constant!(e.kb, 0, I32))])
_cmp(e::Env, op, a, b) = compare!(e.kb, op, _num(e, [a, b])...)

function _literal(e::Env, v)
    v isa Bool && return constant!(e.kb, v, BOOL)
    v isa Integer && return constant!(e.kb, v, I32)
    v isa Real && return constant!(e.kb, v)
    _lerr(v, "a literal of type $(typeof(v)) has no lattice value")
end

# integer lattice offset of the argument `arg` of axis `d`: `x + a*dx` with `dx` tagged axis d
function _offset(e::Env, arg, d)
    x = e.xs[d]
    isequal(arg, x) && return 0
    δ = unwrap(Symbolics.expand(arg - x))
    _iszero(δ) && return 0
    vs = Symbolics.get_variables(δ)
    length(vs) == 1 && get(e.spacing, only(vs), 0) == d ||
        _lerr(arg, "an offset read is `$x + a * dx` with `dx` a parameter tagged `lattice_spacing = $d`")
    a = unwrap_const(unwrap(substitute(δ, Dict(only(vs) => 1))))
    (a isa Real && isinteger(a) && _iszero(Symbolics.expand(δ - Int(a) * only(vs)))) ||
        _lerr(arg, "the lattice offset must be `a * dx` with `a` an integer literal")
    return Int(a)
end

"""Load of a field read `c(t, x + a*dx, …)` (component `comp`)."""
function _load(e::Env{N}, u, comp) where {N}
    ids, lane = e.fields[operation(u)]
    a = arguments(u)
    (length(a) == N + 1 && isequal(a[1], e.t)) || _lerr(u, "a field is read as `c($(join([e.t; e.xs], ", ")))`")
    o = ntuple(d -> _offset(e, a[d + 1], d), N)
    any(!iszero, o) && !e.map &&
        _lerr(u, "offset reads are allowed only in map equations `Shift(t, 1)(c) ~ rhs`; $RAW_HINT")
    (comp == 0 ? length(ids) == 1 : 1 <= comp <= length(ids)) ||
        _lerr(u, "an array field is read per component, `u(t, x, y)[i]`")
    f = ids[max(comp, 1)]
    rel = _flevel(e, operation(u)) - e.level
    rel == 0 || return _level_load(e, u, f, lane, o, rel)
    e.level > 0 && any(!iszero, o) && (o = _level_offset(e, u, o, e.level))
    any(!iszero, o) &&                       # map read: wraps on a periodic axis, else 0 outside
        return load!(e.kb, f, lane; offset = ntuple(d -> o[d] + e.offset[d], N), policy = ZERO)
    pol = any(!iszero, e.offset) ? (e.policy == RESOLVE && f in e.ghosted ? RESOLVE : CLAMP) : e.policy
    return load!(e.kb, f, lane; offset = e.offset, policy = pol)
end
# A read of a field on another `Coarse` level than the kernel's (F3-16). A coarser field (`rel >
# 0`) reads the node whose block holds the site (piecewise-constant prolongation), at a neighbor
# the node of the neighbor's block (no ghost value: the boundary node). A finer field (`rel < 0`)
# is read inside a fold only (`_fold`), at each child; its offsets are in its own level's sites.
# (Inside a fold, a field of the term's own grid or a coarser one is read at the node: it is
# constant over the block.) A map's offset `x + a dx` counts fine sites, so `a` must be a whole
# number of the level's.
function _level_load(e::Env{N}, u, f, lane, o, rel) where {N}
    lf = e.level + rel
    rel < 0 && e.child == 0 &&
        _lerr(u, "a field on a finer grid is read in a term of a coarser one only through a fold of fine reads (an internal error: please report it)")
    # the map offset in sites of the frame of the access: the kernel's (a coarser field) or the
    # field's own (a finer field, inside a fold)
    fr = rel >= 0 ? e.level : lf
    o = _level_offset(e, u, o, fr)
    off = ntuple(d -> o[d] + (rel < 0 && e.dims[d] != 1 ? e.offset[d] * 2^(-rel) : e.offset[d]), N)
    pol = all(iszero, off) ? INSIDE : any(!iszero, o) ? ZERO : CLAMP
    return load!(e.kb, f, lane; offset = off, level = rel, policy = pol)
end

# a map's offset `x + a dx` (fine sites: `dx` is the fine spacing) in sites of level `fr`
function _level_offset(e::Env{N}, u, o, fr) where {N}
    fr == 0 && return o
    any(d -> e.dims[d] != 1 && o[d] % 2^fr != 0, 1:N) &&
        _lerr(u, "the offset read counts fine sites (`dx` is the fine spacing), and this field lives on a grid coarsened by $(2^fr): give an offset that is a multiple of $(2^fr) sites (`$(2^fr) * dx`)")
    return ntuple(d -> e.dims[d] == 1 ? o[d] : o[d] ÷ 2^fr, N)
end

# Folds of fine reads in a term on a `Coarse` grid (F3-16; F3 design §3.9, review r1 M2 and S1).
# A term of a coarse field that reads fields of a finer grid (the CPM inputs, a fine field)
# reads them through the block of children of each coarse node:
# - an integer input (`kind`) reads the block's plurality owner, the most frequent value of its
#   children, computed once per node and window (`owner:<input>:<level>`; ties go to the
#   smallest nonzero value, 0 last). A part of a term that reads no other fine field is
#   evaluated at that owner, so `(kind == 1) + 0.5 (kind == 2)` and `at(R, kind)` agree, and
#   complementary conditions never both fail (v3 §6.3 T-1: the node takes the full rate of its
#   owner);
# - the largest subterm that reads a fine real field (a fine field, a real or Bool input) and is
#   not linear in its fine reads is folded as a whole by the mean over the children, each fine
#   read (the integer inputs too) at the child and each read of the term's own grid at the node.
#   A sum is folded per summand and a product keeps its factors without fine reads outside the
#   fold, so the coarse sum times the block size is the fine sum of the term (the restriction
#   conserves mass: `max(g − gT, 0)`, `g/(K + g)`, `at(S, kind) g` are restricted exactly);
# - a condition on a fine real field where a condition is used (a mask, `&`, `|`, `!`) is folded
#   by Majority (true when more than half the children are); in a sum or a product it is a 0/1
#   value and folds by the mean.
function _fold_kind(u, e::Env)
    (e.level > 0 && e.child == 0) || return nothing
    fine = _fine_ops(e)
    isempty(fine) && return nothing
    _reads(u, fine) || return nothing
    if _isfield(e, u) || (iscall(u) && operation(u) === getindex && _isfield(e, unwrap(arguments(u)[1])))
        op = _isfield(e, u) ? operation(u) : operation(unwrap(arguments(u)[1]))
        _isint(e, op) && return :owner
        SymbolicUtils.symtype(u) <: Bool && return :majority
        return :mean
    end
    _reads(u, _real_ops(e, fine)) || return nothing    # integer inputs only: evaluated at the owner
    _isbool_term(u) && return :majority
    f = operation(u)
    # a spatial operator runs on the term's grid: its coefficients fold at each face (`_secdiff`)
    (f === Δ || f isa DivKGrad || f isa Advect || f isa Differential) && return nothing
    f === (+) && return :sum
    f === (*) && return :product
    (f === (-) || f === identity) && return nothing
    f === (/) && !_reads(arguments(u)[2], fine) && return nothing
    return :mean
end
_fine_ops(e::Env) = Any[op for (op, l) in e.flev if l < e.level]
_isint(e::Env, op) = haskey(e.fields, op) && e.fields[op][2] in (I32, U32)
_real_ops(e::Env, fine) = Any[op for op in fine if !_isint(e, op)]
_isbool_term(u) = (iscall(u) && (operation(u) === ismember || operation(u) === (!) || operation(u) === (!=) ||
                                 operation(u) === (&) || operation(u) === (|) || any(r -> r[1] === operation(u), _CMP))) ||
                  SymbolicUtils.symtype(u) <: Bool
# a sum on a coarse grid: per summand, a condition on a fine real field by the mean (a 0/1 value)
function _fold_sum(u, e::Env)
    real = _real_ops(e, _fine_ops(e))
    ids = Int32[_isbool_term(y) && _reads(y, real) ? _fold(y, e, :mean) : lower(y, e) for y in arguments(u)]
    return _op(e, ADD, ids...)
end
# a product on a coarse grid: the factors without fine reads stay outside; the factors with fine
# reads fold together by the mean when one of them reads a fine real field and they are not a
# single factor (a single one is lowered as itself, a single condition as a 0/1 value)
function _fold_product(u, e::Env)
    fine = _fine_ops(e)
    real = _real_ops(e, fine)
    a = arguments(u)
    F = [y for y in a if _reads(y, fine)]
    ids = Int32[lower(y, e) for y in a if !_reads(y, fine)]
    if any(y -> _reads(y, real), F) && (length(F) >= 2 || _isbool_term(only(F)))
        push!(ids, _fold(length(F) == 1 ? only(F) : *(F...), e, :mean))
    else
        append!(ids, Int32[lower(y, e) for y in F])
    end
    return _op(e, MUL, ids...)
end
# an integer input read at the block's plurality owner (`owner:<input>:<level>`, a field of the
# term's grid; at a neighbor, the neighbor node's, clamped at a face of the box)
function _owner_load(e::Env{N}, u) where {N}
    v = _isfield(e, u) ? u : unwrap(arguments(u)[1])
    key = (:owner, operation(v), e.level)
    haskey(e.fields, key) ||
        _lerr(u, "the owner of an integer input on a coarse grid is not computed (an internal error: please report it)")
    ids, lane = e.fields[key]
    a = arguments(v)
    o = ntuple(d -> _offset(e, a[d + 1], d), N)
    any(!iszero, o) && !e.map &&
        _lerr(u, "offset reads are allowed only in map equations `Shift(t, 1)(c) ~ rhs`; $RAW_HINT")
    any(!iszero, o) &&
        return load!(e.kb, ids[1], lane; offset = ntuple(d -> _level_offset(e, u, o, e.level)[d] + e.offset[d], N), policy = ZERO)
    return load!(e.kb, ids[1], lane; offset = e.offset, policy = any(!iszero, e.offset) ? CLAMP : e.policy)
end
# at a neighbor (an operator coefficient, a velocity), the fold reads the neighbor node's block,
# clamped onto the box in the coarse frame: across a closed face of the box, the node's own block
# (as a field of the coarse grid is read there; review r1 S2), one select per shifted axis
function _fold(u, e::Env{N}, kind, axes = [d for d in 1:N if e.offset[d] != 0]) where {N}
    isempty(axes) && return _fold_children(u, e, kind)
    ax = axes[1]
    abs(e.offset[ax]) == 1 ||
        _lerr(u, "a fine read at a coarse neighbor more than one node away (an internal error: please report it)")
    lid = minimum(ids[1] for (op, (ids, _)) in e.fields if !(op isa Tuple) && _flevel(e, op) == e.level)
    ins = node!(e.kb, INSIDE_OP, BOOL, Int32[], access!(e.kb, Access{N}(lid, Int8(0), Sel(Int16(1)),
        Sel(NTuple{N, Int16}(ntuple(d -> d == ax ? e.offset[d] : 0, N))), Int8(0), INSIDE)))
    out = Env(e.kb, e.fields, e.params, e.tables, e.spacing, e.t, e.xs, e.lo, e.h, e.map,
        ntuple(d -> d == ax ? 0 : e.offset[d], N), e.policy, e.leaf, e.hex, e.domain, e.ghosted, e.level, e.flev, e.dims, e.child)
    return select!(e.kb, ins, _fold(u, e, kind, axes[2:end]), _fold(u, out, kind, axes[2:end]))
end
function _fold_children(u, e::Env{N}, kind) where {N}
    m = e.level - minimum(_flevel(e, op) for op in _fine_ops(e) if _reads(u, Any[op]))
    n = prod(d -> e.dims[d] == 1 ? 1 : 2^m, 1:N)       # the children of a node
    v = lower(u, _infold(e, m))
    if kind === :majority
        cnt = node!(e.kb, RESTRICT, I32, Int32[cast!(e.kb, _bool(e, v), I32)], 0)
        return _cmp(e, LT, constant!(e.kb, n, I32), arith!(e.kb, MUL, constant!(e.kb, 2, I32), cnt))
    end
    return _op(e, MUL, constant!(e.kb, 1 / n), node!(e.kb, RESTRICT, REAL, Int32[_real(e, v)], 0))
end
# a spatial operator reads its field on the field's own grid: in a term of a field on another
# `Coarse` level it has no single meaning (the prolonged coarse Laplacian, or the Laplacian of the
# prolonged field, which vanishes inside each block)
function _same_level!(e::Env, u, what)
    _flevel(e, operation(u)) == e.level && return nothing
    lf = _flevel(e, operation(u))
    _lerr(u, string(what, " reads `", operation(u), "` on ", lf == 0 ? "the fine grid" : "`Coarse($(2^lf))`", ", and the ",
        "term is evaluated on ", e.level == 0 ? "the fine grid" : "`Coarse($(2^e.level))`", "; a spatial operator reads its ",
        "field on that field's own grid: write it as an aux field on the grid of `", operation(u), "` (`L ~ Δ(",
        operation(u), ")` with `lattice_level` as `", operation(u), "`'s) and read `L`"))
end
_isfield(e::Env, u) = iscall(u) && haskey(e.fields, operation(u))
_fieldarg(e::Env, u) = (u = unwrap(u);
                        _isfield(e, u) ? (u, 0) :
                        iscall(u) && operation(u) === getindex && _isfield(e, unwrap(arguments(u)[1])) ?
                        (unwrap(arguments(u)[1]), Int(unwrap_const(arguments(u)[2]))) :
                        _lerr(u, "the operand must be a field read `c(t, x, y)`"))

"""Per-axis flux-form second difference `(1/h²) Σ± K_face (c± − c)` (K = nothing: K ≡ 1)."""
function _secdiff(e::Env, d, K, c, mean)
    any(!iszero, e.offset) && _lerr(c, "a spatial operator inside an operator coefficient")
    u, comp = _fieldarg(e, c)
    e.fields[operation(u)][2] in (U8, I32, U32) && _lerr(c, "a spatial operator of an integer input")
    _same_level!(e, u, "the spatial operator")
    ids, lane = e.fields[operation(u)]
    ld(o) = load!(e.kb, ids[max(comp, 1)], lane; offset = o, policy = RESOLVE)
    c0 = ld(e.offset)
    Kc = K === nothing ? nothing : _real(e, lower(K, e))
    terms = map((-1, 1)) do s
        o = _unit(e, d, s)
        diff = _op(e, ADD, ld(o), arith!(e.kb, NEG, c0))
        K === nothing && return diff
        Kn = _real(e, lower(K, _shift(e, o; face = true)))
        sum_ = _op(e, ADD, Kc, Kn)
        face = mean === :arithmetic ? _op(e, MUL, constant!(e.kb, 0.5), sum_) :
               select!(e.kb, _cmp(e, EQ, sum_, constant!(e.kb, 0.0)), constant!(e.kb, 0.0),
                       _op(e, DIV, _op(e, MUL, constant!(e.kb, 2.0), Kc, Kn), sum_))
        return _op(e, MUL, face, diff)
    end
    return _op(e, MUL, constant!(e.kb, 1 / e.h[d]^2), _op(e, ADD, terms...))
end
# the six neighbors of a hexagonal site in axial coordinates
const HEX6 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))

"""Hexagonal `Δc ≈ 2/(3h²) Σₙ (cₙ − c)`: a neighbor outside a closed face or the domain reads `c`."""
function _hexlap(e::Env{N}, c) where {N}
    any(!iszero, e.offset) && _lerr(c, "a spatial operator inside an operator coefficient")
    u, comp = _fieldarg(e, c)
    e.fields[operation(u)][2] in (U8, I32, U32) && _lerr(c, "a spatial operator of an integer input")
    _same_level!(e, u, "the spatial operator")
    ids, lane = e.fields[operation(u)]
    f = ids[max(comp, 1)]
    c0 = load!(e.kb, f, lane; offset = (0, 0), policy = INSIDE)
    inside(fid, o) = node!(e.kb, INSIDE_OP, BOOL, Int32[], access!(e.kb, Access{N}(
        fid, Int8(0), Sel(Int16(1)), Sel(NTuple{N, Int16}(o)), Int8(0), INSIDE)))
    indom(o) = _indomain(e.kb, e.domain, N, o)
    terms = map(HEX6) do o
        ok = inside(f, o)
        e.domain == 0 || (ok = node!(e.kb, AND, BOOL, Int32[ok, indom(o), indom((0, 0))]))
        nb = select!(e.kb, ok, load!(e.kb, f, lane; offset = o, policy = CLAMP), c0)
        _op(e, ADD, nb, arith!(e.kb, NEG, c0))
    end
    return _op(e, MUL, constant!(e.kb, 2 / (3 * e.h[1]^2)), _op(e, ADD, terms...))
end

_axis(e::Env, x) = (d = findfirst(v -> isequal(v, x), e.xs); d === nothing ? _lerr(x, "not a spatial variable") : d)

"""
First-order upwind `∇⋅(u c)`; a closed face carries no advective flux. The velocity is an
array field `u(t, x, y)` with one component per axis, or a vector of one term per axis
(`[ux, uy]`: parameters, fields, any lowered term), each evaluated at the site and at its
neighbor as an operator coefficient is.
"""
function _advect(e::Env{N}, uvel, c) where {N}
    v = unwrap(uvel)
    comps = velocity_terms(v)
    if comps === nothing
        _isfield(e, v) && length(e.fields[operation(v)][1]) == N ||
            _lerr(uvel, "`Advect` takes the velocity array field `u(t, x, y)` with $N components, or a vector of " *
                        "$N terms (`[ux, uy]`)")
    else
        length(comps) == N || _lerr(uvel, "`Advect` takes a velocity of $N components (one per axis); got $(length(comps))")
    end
    # (a velocity field on another `Coarse` level is read as any field read is there)
    vel(d, o) = comps === nothing ?
                (_flevel(e, operation(v)) == e.level ?
                 _real(e, load!(e.kb, e.fields[operation(v)][1][d], e.fields[operation(v)][2]; offset = o, policy = CLAMP)) :
                 _real(e, lower(unwrap(Symbolics.wrap(v)[d]), _shift(e, o)))) :
                _real(e, lower(comps[d], _shift(e, o)))
    u, comp = _fieldarg(e, c)
    _same_level!(e, u, "`Advect`")
    cl(o) = load!(e.kb, e.fields[operation(u)][1][max(comp, 1)], e.fields[operation(u)][2];
                  offset = o, policy = RESOLVE)
    z = _unit(e, 1, 0)
    divs = map(1:N) do d
        fl = map((-1, 1)) do s
            o = _unit(e, d, s)
            uf = _op(e, MUL, constant!(e.kb, 0.5), _op(e, ADD, vel(d, z), vel(d, o)))
            up, dn = s > 0 ? (cl(z), cl(o)) : (cl(o), cl(z))      # upwind side for uf > 0
            F = select!(e.kb, _cmp(e, LT, constant!(e.kb, 0.0), uf), _op(e, MUL, uf, up), _op(e, MUL, uf, dn))
            ins = node!(e.kb, INSIDE_OP, BOOL, Int32[], access!(e.kb, Access{N}(
                e.fields[operation(u)][1][max(comp, 1)], Int8(0), Sel(Int16(1)), Sel(NTuple{N, Int16}(o)), Int8(0), INSIDE)))
            F = select!(e.kb, ins, F, constant!(e.kb, 0.0))
            return s > 0 ? F : arith!(e.kb, NEG, F)
        end
        _op(e, MUL, constant!(e.kb, 1 / e.h[d]), _op(e, ADD, fl...))
    end
    return _op(e, ADD, divs...)
end

"""
    velocity_terms(v) -> Vector or nothing

The terms of a velocity written as a vector, one per axis: a symbolic array literal
(`Advect(Upwind1())([ux, uy], c)`) or a vector of numbers (`[0.3, 0.0]`, a constant); else
`nothing` (an array field `u(t, x, y)`).
"""
function velocity_terms(v)
    w = unwrap_const(unwrap(v))
    w isa AbstractVector{<:Number} && return collect(w)          # a constant velocity
    iscall(v) && operation(v) === SymbolicUtils.array_literal || return nothing
    # (the literal's shape, a tuple, comes first)
    return [y for y in arguments(v) if !(unwrap_const(y) isa Tuple)]
end

# matched with `===`, never through a hash (D-107: another build hashes functions differently)
const _UNARY = ((sqrt, SQRT), (exp, EXP), (log, LOG), (abs, ABS))
const _CMP = (((<), LT, false), ((<=), LE, false), ((>), LT, true), ((>=), LE, true), ((==), EQ, false))
# the other calls `lower` takes by identity: arithmetic, `ifelse` and the logic of conditions
const _OPS = (+, -, *, /, ^, min, max, ifelse, !=, !, &, |)

"""
    lowers_call(f) -> Bool

Whether the lattice lowering takes a call of `f` inside a term: arithmetic (`+ - * / ^`,
`min`, `max`), comparisons and logic (`== != < <= > >= ! & |`), `ifelse`, `sqrt`, `exp`,
`log`, `abs` and the calls of the IR (`sin`, `cos`, `tan`, `tanh`, `sinh`, `cosh`, `cbrt`,
`exp2`, `log2`, `log10`, `expm1`, `log1p`, `atan`, `floor`, `ceil`, `round`), and `identity`
(SymbolicUtils keeps `π` and `ℯ` as `identity(π)`). It is the one
allowlist of both front ends (F2 design §2.11): a front end that converts its own terms (Potts
`@equations`) asks it, so a call lowers in one front end exactly when it lowers in the other.
The operators (`Δ`, `DivKGrad`, `Advect`, `Differential`), the reads (`at`, `ismember`) and
the field reads are terms of their own, not calls in this sense.
"""
lowers_call(f) = f === identity || any(g -> g === f, _OPS) || any(r -> r[1] === f, _CMP) || any(r -> r[1] === f, _UNARY) ||
                 (f isa Function && nameof(f) in CALLS)

"""
    lower(x, env) -> node id

Lower the MTK term `x` into `env.kb`. Every term without a lattice meaning is an
`ArgumentError` that names it and the supported form.
"""
function lower(x, e::Env{N}) where {N}
    u = unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return _literal(e, u)
    SymbolicUtils.isconst(u) && return _literal(e, unwrap_const(u))
    if !(e.leaf isa Nothing)
        r = e.leaf(u, e)
        r === nothing || return r
    end
    fk = _fold_kind(u, e)                                  # fine reads in a coarse term (F3-16)
    fk === :owner && return _owner_load(e, u)
    fk === :sum && return _fold_sum(u, e)
    fk === :product && return _fold_product(u, e)
    fk === nothing || return _fold(u, e, fk)
    if SymbolicUtils.issym(u)
        haskey(e.params, u) && return param!(e.kb, e.params[u])
        isequal(u, e.t) && return runtime!(e.kb, RUNTIME_T)
        d = findfirst(v -> isequal(v, u), e.xs)        # cell-center coordinate lo + (i − ½) h
        d === nothing && _lerr(u, "not a declared parameter (`ps`), dependent or independent variable")
        i = _real(e, _op(e, ADD, coord!(e.kb, d), constant!(e.kb, e.offset[d], I32)))
        return _op(e, ADD, constant!(e.kb, e.lo[d] - e.h[d] / 2), _op(e, MUL, constant!(e.kb, e.h[d]), i))
    end
    f, a = operation(u), arguments(u)
    _isfield(e, u) && return _load(e, u, 0)
    # an irrational kept symbolically (`identity(Const(π))`, SymbolicUtils 4): its value
    f === identity && length(a) == 1 && return lower(a[1], e)
    if f === getindex
        b = unwrap(a[1])
        _isfield(e, b) && return _load(e, b, Int(unwrap_const(a[2])))
        haskey(e.tables, b) && return table!(e.kb, e.tables[b]..., cast!(e.kb, _literal(e, unwrap_const(a[2])), I32))
        _lerr(u, "indexing is defined for array fields and array parameters only")
    end
    (f isa Shift || f isa Hold || f isa Sample || f isa Pre) &&
        _lerr(u, "`$f` has no meaning on the right side; $SHIFT_HINT")
    e.hex && (f isa DivKGrad || f isa Differential || f isa Advect) &&
        _lerr(u, "only `Δ(c)` is defined on a hexagonal grid")
    f === Δ && e.hex && return _hexlap(e, a[1])
    f === Δ && return _op(e, ADD, (_secdiff(e, d, nothing, a[1], :harmonic) for d in 1:N)...)
    f isa DivKGrad && return _op(e, ADD, (_secdiff(e, d, a[1], a[2], f.mean) for d in 1:N)...)
    if f isa Differential
        r = _raw_flux(u)
        r === nothing && _lerr(u, "a raw derivative that is not a flux form; $RAW_HINT")
        return _secdiff(e, _axis(e, f.x), r[1], r[2], :harmonic)
    end
    f isa Advect && return _advect(e, a[1], a[2])
    if f === ismember
        k, s = lower(a[1], e), unwrap_const(a[2])
        s isa Tuple && all(v -> v isa Integer, s) || _lerr(u, "the kind set is a tuple of integer literals")
        eqs = Int32[_cmp(e, EQ, k, constant!(e.kb, v, I32)) for v in s]
        return length(eqs) == 1 ? eqs[1] : node!(e.kb, OR, BOOL, eqs)
    end
    if f === at
        haskey(e.tables, unwrap(a[1])) ||
            _lerr(u, "`at(T, k)` reads an array parameter `T`; site and cell reads are CPM terms")
        return table!(e.kb, e.tables[unwrap(a[1])]..., cast!(e.kb, _num(e, [lower(a[2], e)])[1], I32))
    end
    f === ifelse && return cond!(e.kb, _bool(e, lower(a[1], e)), _num(e, [lower(a[2], e), lower(a[3], e)])...)
    i = findfirst(r -> r[1] === f, _CMP)
    if i !== nothing
        _, op, swap = _CMP[i]
        p, q = lower(a[1], e), lower(a[2], e)
        return swap ? _cmp(e, op, q, p) : _cmp(e, op, p, q)
    end
    f === (!=) && return node!(e.kb, NOT, BOOL, Int32[_cmp(e, EQ, lower(a[1], e), lower(a[2], e))])
    f === (!) && return node!(e.kb, NOT, BOOL, Int32[_bool(e, lower(a[1], e))])
    (f === (&) || f === (|)) && return node!(e.kb, f === (&) ? AND : OR, BOOL, Int32[_bool(e, lower(y, e)) for y in a])
    ids = Int32[lower(y, e) for y in a]
    f === (+) && return _op(e, ADD, ids...)
    f === (*) && return _op(e, MUL, ids...)
    f === (-) && return length(ids) == 1 ? arith!(e.kb, NEG, _num(e, ids)...) :
                        _op(e, ADD, ids[1], arith!(e.kb, NEG, _num(e, ids[2:2])...))
    f === (/) && return arith!(e.kb, DIV, _real(e, ids[1]), _real(e, ids[2]))
    (f === min || f === max) && return _op(e, f === min ? MIN : MAX, ids...)
    if f === (^)
        p = unwrap_const(unwrap(a[2]))
        p isa Real && isinteger(p) && return node!(e.kb, POWI, _type(e, _num(e, ids[1:1])[1]), _num(e, ids[1:1]), Int(p))
        p isa Real && p == 0.5 && return arith!(e.kb, SQRT, _real(e, ids[1]))
        return arith!(e.kb, EXP, _op(e, MUL, _real(e, ids[2]), arith!(e.kb, LOG, _real(e, ids[1]))))
    end
    i = findfirst(r -> r[1] === f, _UNARY)
    i === nothing || return arith!(e.kb, _UNARY[i][2], _real(e, ids[1]); type = REAL)
    f isa Function && nameof(f) in CALLS && length(ids) == 1 && return call!(e.kb, nameof(f), ids[1])
    _lerr(u, "`$f` has no lattice lowering")
end
