# The linearity table: `Symbolics.linear_expansion` cannot see
# through registered operators, so the classification is ours. Each additive term of a rate
# right-hand side gets one class with respect to the equation's own field `c`:
#
#   Diffusion     laplacian(c), DivKGrad(K, c), raw Dx(Dx(c)), Dx(K * Dx(c)), times a
#                 constant or parameter
#   SiteDiffusion the same times a multiplier `m` that reads inputs only through table reads
#                 (`value_at(T, k)`, `T[k]`, `value_at`) and indicators (kind sets,
#                 comparisons): `value_at(Dk, k) * laplacian(c)`, `ifelse(k == 2, Da, Db) *
#                 laplacian(c)`. `m A` is not conservative (not symmetric), so it is not
#                 plain Diffusion; the stability bound takes max|m| over the site and max K
#                 over the faces independently
#   LinearLocal   coefficient × c
#   LaggedSwitch  coefficient × max(a, 0) or ifelse(·, a, 0), a affine in c (a LinearLocal
#                 term whose switch the implicit solvers lag, §5.2)
#   Advection     Advect(u, c)
#   CrossLinear   linear in one other field and free of c
#   Source        reads no field
#   Other         everything else (treated explicitly)
#
# The rule is conservative: a term is linear only when every coefficient (a factor, a
# divisor, `K`, `u`, the switch's other terms) reads no unknown field of the system, only
# constants, parameters and inputs. Unknowns are every non-input field, aux fields included
# (`K ~ c^2` makes `DivKGrad(K, c)` Other), because the solve groups are not known here. A
# multiplier of a diffusion or advection term must also read no input: `kind * laplacian(c)`
# is not conservative (the one exception is SiteDiffusion, a diffusion multiplier that reads
# inputs through table reads and indicators only). A term that reads an aux field at all is
# Other (its dependence is hidden).
#
# Operator classes match with `isa` on the struct's UnionAll (`Advect{S}` is parametric),
# and literals are read through `unwrap_const` (SymbolicUtils 4 wraps them in `Const`).

# A field is named by its operation (`c` for `c(t, x, y)`), a component of an array field by
# a `_Comp` (`u[2]`, read as `getindex(u(t, x, y), 2)`): a component row's own field is its
# component only, and another component of the same array is another field
struct _Comp
    op::Any
    i::Int
end
Base.isequal(a::_Comp, b::_Comp) = isequal(a.op, b.op) && a.i == b.i
Base.hash(a::_Comp, h::UInt) = hash(a.i, hash(a.op, hash(:_Comp, h)))
# whether the call `u` is a read of the field `o`
_hit(o, u) = isequal(o, operation(u))
function _hit(o::_Comp, u)
    operation(u) === getindex || return false
    a = arguments(u)
    length(a) == 2 || return false
    w = unwrap(a[1])
    return iscall(w) && isequal(operation(w), o.op) &&
        isequal(unwrap_const(unwrap(a[2])), o.i)
end
# the field `x` names: its `_Comp` for a component read `u(t, x, y)[i]`, else its operation
function _ref(x)
    u = unwrap(x)
    iscall(u) || return u
    if operation(u) === getindex
        w = unwrap(arguments(u)[1])
        i = unwrap_const(unwrap(arguments(u)[2]))
        return iscall(w) && i isa Integer ? _Comp(operation(w), Int(i)) : operation(u)
    end
    return operation(u)
end
# a field list's entry as a field: an operation, or a component read as its `_Comp`
function _asref(f)
    return if f isa _Comp
        f
    else
        (u = unwrap(f); iscall(u) && operation(u) === getindex ? _ref(u) : f)
    end
end
function _reads(x, ops)
    (
        u = unwrap(x);
        iscall(u) && (any(o -> _hit(o, u), ops) || any(a -> _reads(a, ops), arguments(u)))
    )
end
# whether `x` reads the inputs `I` only inside a table read's index (`value_at(T, k)`,
# `T[k]`, `value_at(J, a, b)`) or an indicator (a comparison or `ismember`): a site factor
# whose values a table-aware bound can enumerate
function _site_factor(x, I)
    function ok(u, inside)
        iscall(u) || return true
        f, a = operation(u), arguments(u)
        any(o -> isequal(o, f), I) && return inside
        if f === value_at || f === getindex
            return ok(unwrap(a[1]), inside) && all(y -> ok(unwrap(y), true), a[2:end])
        elseif f === ismember || f in (==, <, <=, >, >=, !=)
            return all(y -> ok(unwrap(y), true), a)
        end
        return all(y -> ok(unwrap(y), inside), a)
    end
    return ok(unwrap(x), false)
end
_iszero(x) = (v = unwrap_const(unwrap(x)); v isa Number && iszero(v))
_isread(x, op) = (u = unwrap(x); iscall(u) && _hit(op, u))

# Dx(K * Dx(c)) or Dx(Dx(c)) (collapsed to order 2): (K or nothing, c) when it is the flux
# form
function _raw_flux(u)
    d = operation(u)
    a = only(arguments(u))
    d.order == 2 && return (nothing, a)
    d.order == 1 || return nothing
    fs = iscall(a) && operation(a) === (*) ? arguments(a) : [a]
    k = findfirst(
        f -> iscall(f) && operation(f) isa Differential && operation(f).order == 1 &&
            isequal(operation(f).x, d.x), fs
    )
    k === nothing && return nothing
    K = length(fs) == 1 ? 1 : prod(fs[setdiff(eachindex(fs), k)])
    return (K, only(arguments(fs[k])))
end

function _linclass(u, op, S, I)
    free(x) = !_reads(x, S)
    _isread(u, op) && return :LinearLocal
    iscall(u) || return :Other
    f, a = operation(u), arguments(u)
    if f === laplacian || f isa DivKGrad
        return _isread(a[end], op) && all(free, a[1:(end - 1)]) ? :Diffusion : :Other
    elseif f isa Differential
        r = _raw_flux(u)
        return r !== nothing && _isread(r[2], op) && free(r[1]) ? :Diffusion : :Other
    elseif f isa Advect
        return _isread(a[2], op) && free(a[1]) ? :Advection : :Other
    elseif f === (*) || f === (/)
        dep = findall(x -> _reads(x, (op,)), a)
        (length(dep) == 1 && (f === (*) || dep[1] == 1)) || return :Other
        k = _linclass(unwrap(a[dep[1]]), op, S, I)
        rest = a[setdiff(eachindex(a), dep)]
        all(free, rest) || return :Other
        # a diffusion multiplier that reads inputs through tables and indicators only
        if k in (:Diffusion, :SiteDiffusion) && any(x -> _reads(x, I), rest)
            return all(x -> _site_factor(x, I), rest) ? :SiteDiffusion : :Other
        end
        k == :Advection && any(x -> _reads(x, I), rest) && return :Other
        return k
    elseif f === max || f === min || f === ifelse
        arms = f === ifelse ? a[2:3] : a
        f === ifelse && !all(t -> _affine(t, op, S, I), _cmpargs(a[1])) && return :Other
        any(_iszero, arms) && count(x -> _reads(x, (op,)), arms) == 1 &&
            all(x -> _affine(x, op, S, I), arms) && return :LaggedSwitch
    end
    return :Other
end
_cmpargs(c) = (u = unwrap(c); iscall(u) ? arguments(u) : [u])
function _affine(x, op, S, I)
    u = unwrap(x)
    terms = iscall(u) && operation(u) === (+) ? arguments(u) : [u]
    return all(t -> !_reads(t, S) || _linclass(unwrap(t), op, S, I) == :LinearLocal, terms)
end

"""
    linearity(rhs, c, fields; inputs = (), aux = ()) -> Vector{Pair{Any, Symbol}}

The class of each additive term of `rhs` with respect to field `c` (an applied dependent
variable, a component read `u(t, x, y)[i]`, or its operation). `fields` lists the operations
of the unknown fields of the system (every non-input field; an array field by its
components, as their reads `u(t, x, y)[i]`, so that another component is another field),
`inputs` those of the inputs and `aux` those of the algebraic (`K ~ expr`) fields; a term
that reads an aux field is `Other`. A coefficient that reads an unknown makes the term
`Other` (the conservative rule).

# Arguments
- `rhs`: the right side.
- `c`: the field.
- `fields`: the operations of the unknown fields.

# Keywords
- `inputs = ()`: the operations of the inputs.
- `aux = ()`: the operations of the algebraic fields.

# Returns
- One `term => class` pair per additive term of `rhs`.
"""
function linearity(rhs, c, fields; inputs = (), aux = ())
    op = c isa _Comp ? c : _ref(c)
    fields = map(_asref, fields)
    u = unwrap(rhs)
    terms = iscall(u) && operation(u) === (+) ? arguments(u) : [u]
    return map(terms) do t
        _reads(t, fields) || return t => :Source
        # an aux field hides its dependence
        _reads(t, aux) && return t => :Other
        _reads(t, (op,)) && return t => _linclass(t, op, fields, inputs)
        others = [f for f in fields if _reads(t, (f,))]
        cross = length(others) == 1 &&
            _linclass(t, only(others), fields, inputs) in (:LinearLocal, :Diffusion)
        return t => (cross ? :CrossLinear : :Other)
    end
end
