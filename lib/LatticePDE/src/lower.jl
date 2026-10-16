# The canonical lowering (moved from Potts `lower.jl`, v3 §5.1): an MTK term becomes IR nodes
# in a `KernelBuilder`. Order independence (D-107) comes from the builder: every node is
# interned and the operands of a commutative op are sorted structurally, so Symbolics' hash
# order of a sum's operands never reaches the IR. Literals stay Float64 in the IR and are
# rounded once to `T` at emission; `ifelse` is lazy (COND, D-014).
#
# Spatial operators lower to the face-flux form (§5.2): one per-axis second difference
# `(1/h²) Σ± K_face (c± − c)`, summed over axes for `Δ` and `DivKGrad`. A raw `Dx(Dx(c))` or
# `Dx(K * Dx(c))` lowers through the same primitive, so it gives the same IR (P3-rev item 5).
# Neighbor values of `c` are `RESOLVE` loads (pass 2 applies the face rules); a coefficient is
# evaluated at the neighbor with `CLAMP` loads (at a face of the box it takes the inner value).

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
end
_shift(e::Env{N}, o) where {N} = Env(e.kb, e.fields, e.params, e.tables, e.spacing, e.t, e.xs, e.lo, e.h, e.map,
                                     ntuple(d -> e.offset[d] + o[d], N), CLAMP, e.leaf)
_unit(::Env{N}, d, s) where {N} = ntuple(i -> i == d ? s : 0, N)
_lerr(x, msg) = throw(ArgumentError("cannot lower `$x`: $msg"))
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
    any(!iszero, o) &&                       # map read: wraps on a periodic axis, else 0 outside
        return load!(e.kb, f, lane; offset = ntuple(d -> o[d] + e.offset[d], N), policy = ZERO)
    pol = any(!iszero, e.offset) ? CLAMP : e.policy
    return load!(e.kb, f, lane; offset = e.offset, policy = pol)
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
    ids, lane = e.fields[operation(u)]
    ld(o) = load!(e.kb, ids[max(comp, 1)], lane; offset = o, policy = RESOLVE)
    c0 = ld(e.offset)
    Kc = K === nothing ? nothing : _real(e, lower(K, e))
    terms = map((-1, 1)) do s
        o = _unit(e, d, s)
        diff = _op(e, ADD, ld(o), arith!(e.kb, NEG, c0))
        K === nothing && return diff
        Kn = _real(e, lower(K, _shift(e, o)))
        sum_ = _op(e, ADD, Kc, Kn)
        face = mean === :arithmetic ? _op(e, MUL, constant!(e.kb, 0.5), sum_) :
               select!(e.kb, _cmp(e, EQ, sum_, constant!(e.kb, 0.0)), constant!(e.kb, 0.0),
                       _op(e, DIV, _op(e, MUL, constant!(e.kb, 2.0), Kc, Kn), sum_))
        return _op(e, MUL, face, diff)
    end
    return _op(e, MUL, constant!(e.kb, 1 / e.h[d]^2), _op(e, ADD, terms...))
end
_axis(e::Env, x) = (d = findfirst(v -> isequal(v, x), e.xs); d === nothing ? _lerr(x, "not a spatial variable") : d)

"""First-order upwind `∇⋅(u c)`; a closed face carries no advective flux."""
function _advect(e::Env{N}, uvel, c) where {N}
    v = unwrap(uvel)
    _isfield(e, v) && length(e.fields[operation(v)][1]) == N ||
        _lerr(uvel, "`Advect` takes the velocity array field `u(t, x, y)` with $N components")
    vel(d, o) = _real(e, load!(e.kb, e.fields[operation(v)][1][d], e.fields[operation(v)][2];
                               offset = o, policy = CLAMP))
    u, comp = _fieldarg(e, c)
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

# matched with `===`, never through a hash (D-107: another build hashes functions differently)
const _UNARY = ((sqrt, SQRT), (exp, EXP), (log, LOG), (abs, ABS))
const _CMP = (((<), LT, false), ((<=), LE, false), ((>), LT, true), ((>=), LE, true), ((==), EQ, false))

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
    if f === getindex
        b = unwrap(a[1])
        _isfield(e, b) && return _load(e, b, Int(unwrap_const(a[2])))
        haskey(e.tables, b) && return table!(e.kb, e.tables[b]..., cast!(e.kb, _literal(e, unwrap_const(a[2])), I32))
        _lerr(u, "indexing is defined for array fields and array parameters only")
    end
    (f isa Shift || f isa Hold || f isa Sample || f isa Pre) &&
        _lerr(u, "`$f` has no meaning on the right side; $SHIFT_HINT")
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
