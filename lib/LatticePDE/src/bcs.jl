# The boundary-condition parser (v3 §5.1, S-5). PDEBase's `parse_bcs` cannot read masked
# markers or per-component array bcs (R2 S-5), so the classification is ours: initial,
# Dirichlet, Neumann, Robin, periodic and masked interior conditions, arrays per component.
# The first independent variable is time; endpoints are compared numerically.

"""
One classified condition. Face conditions read `alpha * c + beta * ∂c/∂x_axis = value` at
side `-1` (low) or `+1` (high) of spatial axis `axis`. A masked condition holds `value` where
`pred` is true. `comp` is the component of an array field (0 for a scalar field).
"""
struct BC
    kind::Symbol                     # :initial :dirichlet :neumann :robin :periodic :masked
    op::Any                          # operation of the dependent variable (the field key)
    comp::Int
    axis::Int
    side::Int
    alpha::Any
    beta::Any
    value::Any
    pred::Any
    eq::Equation
end

_bcerr(eq, msg) = throw(ArgumentError("boundary condition `$eq`: $msg"))
_cval(x) = (v = unwrap_const(unwrap(x)); v isa Number ? v : nothing)

"""A read `c(args…)` or `u(args…)[i]` of a dependent variable: `(op, args, comp)`."""
function _fieldread(u, fields)
    u = unwrap(u)
    iscall(u) || return nothing
    if operation(u) === getindex
        a = arguments(u)
        r = _fieldread(a[1], fields)
        (r === nothing || r.comp != 0) && return nothing
        i = _cval(a[2])
        (length(a) == 2 && i isa Integer) || return nothing
        return (op = r.op, args = r.args, comp = Int(i))
    end
    haskey(fields, operation(u)) || return nothing
    return (op = operation(u), args = arguments(u), comp = 0)
end

# which independent variables are pinned to a domain endpoint: [(iv index, -1 | +1)]
function _pins(eq, args, ivs, ends)
    pins = Tuple{Int, Int}[]
    length(args) == length(ivs) || _bcerr(eq, "a field read needs $(length(ivs)) arguments")
    for (i, a) in enumerate(args)
        isequal(a, ivs[i]) && continue
        v = _cval(a)
        v === nothing && _bcerr(eq, "the argument `$a` is neither `$(ivs[i])` nor a number")
        lo, hi = ends[i]
        v == lo ? push!(pins, (i, -1)) : v == hi ? push!(pins, (i, 1)) :
        _bcerr(eq, "`$(ivs[i]) = $v` is not on a face of $lo .. $hi")
    end
    return pins
end

"""
    parse_bcs(bcs, fields, ivs, ends) -> Vector{BC}

Classify every condition. `fields` maps a dependent variable's operation to whether it is an
input; `ends[i]` is the `(low, high)` pair of `ivs[i]`. Refused, each with its message: an
off-face or interior face condition, a condition on an input, a mixed-field condition, a
one-sided or cross-axis periodic pair, a normal derivative along another axis, a masked
condition whose left side is not a field read, and a whole-array condition.
"""
function parse_bcs(bcs, fields, ivs, ends)
    out = BC[]
    for eq in bcs
        lhs, rhs = unwrap(eq.lhs), unwrap(eq.rhs)
        any(v -> v isa AbstractArray || SymbolicUtils.symtype(v) <: AbstractArray, (lhs, rhs)) &&
            _bcerr(eq, "array conditions are written per component, `u(t, 0, y)[i] ~ v`")
        if iscall(rhs) && operation(rhs) === masked
            r = _fieldread(lhs, fields)
            r === nothing && _bcerr(eq, "a masked condition needs a field read `c(t, x, y)` on the left")
            fields[r.op] && _bcerr(eq, "an input cannot carry a condition")
            isempty(_pins(eq, r.args, ivs, ends)) || _bcerr(eq, "a masked condition is interior: write `c(t, x, y) ~ masked(pred, v)`")
            p, v = arguments(rhs)
            push!(out, BC(:masked, r.op, r.comp, 0, 0, 1, 0, v, p, eq))
            continue
        end
        terms = iscall(lhs) && operation(lhs) === (+) ? arguments(lhs) : [lhs]
        α, β, r = 0, 0, nothing
        axis, side = 0, 0
        for tm in terms
            coef, core = 1, tm
            if iscall(tm) && operation(tm) === (*)
                fac = arguments(tm)
                k = findfirst(f -> _fieldread(f, fields) !== nothing ||
                                       (iscall(f) && operation(f) isa Differential), fac)
                k === nothing && _bcerr(eq, "the term `$tm` reads no field")
                core, coef = fac[k], prod(fac[setdiff(eachindex(fac), k)])
            end
            isder = iscall(core) && operation(core) isa Differential
            ri = _fieldread(isder ? arguments(core)[1] : core, fields)
            ri === nothing && _bcerr(eq, "the term `$core` reads no field")
            r === nothing || isequal((r.op, r.comp), (ri.op, ri.comp)) || _bcerr(eq, "it mixes fields")
            r = ri
            fields[r.op] && _bcerr(eq, "an input cannot carry a condition")
            p = _pins(eq, r.args, ivs, ends)
            length(p) == 1 || _bcerr(eq, "a face condition pins exactly one variable")
            axis == 0 || (axis, side) == p[1] || _bcerr(eq, "its terms sit on different faces")
            axis, side = p[1]
            if isder
                d = operation(core)
                (d.order == 1 && isequal(d.x, ivs[axis])) ||
                    _bcerr(eq, "the derivative must be first order along the pinned `$(ivs[axis])`")
                β = coef
            else
                α = coef
            end
        end
        rr = _fieldread(rhs, fields)
        if rr !== nothing && isequal(β, 0) && isequal(α, 1)
            p2 = _pins(eq, rr.args, ivs, ends)
            isequal((rr.op, rr.comp), (r.op, r.comp)) && length(p2) == 1 && p2[1][1] == axis &&
                p2[1][2] != side || _bcerr(eq, "a periodic pair joins the two opposite faces of one axis")
            axis == 1 && _bcerr(eq, "time cannot be periodic")
            push!(out, BC(:periodic, r.op, r.comp, axis - 1, 0, 1, 0, 0, nothing, eq))
        elseif axis == 1
            (side == -1 && isequal(β, 0)) || _bcerr(eq, "an initial condition pins the start of time")
            (length(terms) == 1 && isequal(α, 1)) || _bcerr(eq, "an initial condition is written `c(0, x, y) ~ value`")
            push!(out, BC(:initial, r.op, r.comp, 0, 0, α, 0, rhs, nothing, eq))
        else
            kind = isequal(β, 0) ? :dirichlet : isequal(α, 0) ? :neumann : :robin
            push!(out, BC(kind, r.op, r.comp, axis - 1, side, α, β, rhs, nothing, eq))
        end
    end
    return out
end
