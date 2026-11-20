# The boundary-condition parser. PDEBase's `parse_bcs` cannot read masked
# markers or per-component array bcs, so the classification is ours: initial,
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
_cval(x) = (v = _numval(unwrap(x)); v isa Number ? v : nothing)
# the value of an expression of numbers alone (`2π`, `π / 2 + ℯ`, kept symbolically as
# `identity(Const(π))` terms), or nothing
function _numval(u)
    v = unwrap_const(_unid(u))
    v isa Number && return v
    iscall(v) || return nothing
    f = operation(v)
    any(g -> f === g, (+, -, *, /, ^)) || return nothing
    a = map(y -> _numval(unwrap(y)), arguments(v))
    any(isnothing, a) && return nothing
    return f(a...)
end
# SymbolicUtils keeps an irrational as `identity(Const(π))` (`π * x`, `x + ℯ`): its value
_unid(u) = iscall(u) && operation(u) === identity && length(arguments(u)) == 1 ? _unid(unwrap(arguments(u)[1])) : u

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
        _bcerr(eq, "`$(ivs[i]) = $v` is not on a face of $lo .. $hi: the low face is `$(ivs[i]) = $lo` and the high face is " *
                   "`$(ivs[i]) = $hi` (the domain's extent)")
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
            # (terms on one read add up: `g1 c + g2 c` has α = g1 + g2; the last one was once kept)
            if isder
                d = operation(core)
                (d.order == 1 && isequal(d.x, ivs[axis])) ||
                    _bcerr(eq, "the derivative must be first order along the pinned `$(ivs[axis])`")
                β = isequal(β, 0) ? coef : β + coef
            else
                α = isequal(α, 0) ? coef : α + coef
            end
        end
        rr = _fieldread(rhs, fields)
        # a periodic pair reads the same field on the other face; a read of another field (an
        # input, an aux field) is a face value (`c(t, 1, y) ~ G(t, 1, y)` was
        # taken for a pair)
        if rr !== nothing && isequal(β, 0) && isequal(α, 1) && isequal((rr.op, rr.comp), (r.op, r.comp))
            p2 = _pins(eq, rr.args, ivs, ends)
            length(p2) == 1 && p2[1][1] == axis &&
                p2[1][2] != side || _bcerr(eq, "a periodic pair joins the two opposite faces of one axis")
            axis == 1 && _bcerr(eq, "time cannot be periodic")
            push!(out, BC(:periodic, r.op, r.comp, axis - 1, 0, 1, 0, 0, nothing, eq))
        elseif axis == 1
            (side == -1 && isequal(β, 0)) || _bcerr(eq, "an initial condition pins the start of time")
            (length(terms) == 1 && isequal(α, 1)) || _bcerr(eq, "an initial condition is written `c(0, x, y) ~ value`")
            push!(out, BC(:initial, r.op, r.comp, 0, 0, α, 0, _bc_value(eq, rhs, r.op, fields), nothing, eq))
        else
            kind = isequal(β, 0) ? :dirichlet : isequal(α, 0) ? :neumann : :robin
            push!(out, BC(kind, r.op, r.comp, axis - 1, side, α, β, _bc_value(eq, rhs, r.op, fields), nothing, eq))
        end
    end
    return out
end

# The value of a face or initial condition with its derivatives worked out: `Dy(sin(x y))` is
# `x cos(x y)`. A later substitution of the pinned coordinate (the face's own `x`) does not
# enter a `Differential`, so none may stay. A derivative of a field read stays unevaluated and
# is refused in words.
function _bc_value(eq, v, op = nothing, fields = Dict{Any, Bool}())
    u = unwrap(v)
    _hasdiff(u) || return v
    w = unwrap(Symbolics.expand_derivatives(u))
    if _hasdiff(w)
        d = _firstdiff(w)
        ops = Any[]
        walk(y) = iscall(y) && (haskey(fields, operation(y)) ? push!(ops, operation(y)) : foreach(a -> walk(unwrap(a)), arguments(y)))
        walk(unwrap(d))
        own = op !== nothing && any(o -> isequal(o, op), ops)
        input = !isempty(ops) && all(o -> fields[o], ops)          # (`fields`: operation → is an input)
        # the route: an input's derivative is an input of its own; the
        # condition's own field takes its flux form; another state field has none yet
        route = own ? "a condition on the field's own normal derivative is its flux form, with the derivative on " *
                      "the left: `Dx(c) ~ g` (Neumann) or `α c + β Dx(c) ~ g` (Robin); a derivative along the face " *
                      "has no condition form in this version" :
                input ? "give the input's derivative as an input field of its own and read that" :
                "a derivative of another state field in a condition's value is not lowered in this version: write " *
                "the condition with that field's value, or with a value of the time, the coordinates and parameters"
        _bcerr(eq, "its value holds `$d`, a derivative of a field; a condition's value may differentiate " *
                   "expressions of the time, the coordinates and parameters only ($route)")
    end
    return w
end
# (`_hasdiff` is operator.jl's)
_firstdiff(u) = operation(u) isa Differential ? u : _firstdiff(unwrap(arguments(u)[findfirst(a -> _hasdiff(unwrap(a)), arguments(u))]))

# A Robin coefficient α or β that is an expression of parameters (`(g1 + g2) c + ∂c/∂x ~ g`)
# is one value at every site; the face rule binds a number, a parameter or a number times one,
# so the expression becomes a computed parameter of its face, `c_x_low_α = g1 + g2` (read
# only, derived after every write, `_fold_computed`). A coefficient that reads the
# coordinates, the time or an input varies by site or in time: it is left as written here,
# and the discretizer makes it a value field (`_coef`).
function robin_slots(sys::PDESystem)
    ivs = unwrap.(get_ivs(sys))
    length(ivs) >= 2 || return sys
    fields = Dict{Any, Bool}(_opof(v) => ModelingToolkitBase.isinput(unwrap(v)) for v in get_dvs(sys))
    ps = _params(sys)
    params = Set{Any}(unwrap(q) for q in ps)
    taken = Set{String}(string(q) for q in ps)
    lows = map(ivs) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), get_domain(sys))
        k === nothing ? nothing : Float64(leftendpoint(get_domain(sys)[k].domain))
    end
    simple(c) = _cval(c) !== nothing || unwrap(c) in params ||
                (iscall(unwrap(c)) && operation(unwrap(c)) === (*) && count(y -> unwrap(y) in params, arguments(unwrap(c))) == 1 &&
                 all(y -> unwrap(y) in params || _cval(y) !== nothing, arguments(unwrap(c))))
    onlyparams(c) = (vs = Symbolics.get_variables(unwrap(c)); !isempty(vs) && all(v -> v in params, vs))
    extra, ic = Any[], Dict{Any, Any}(_ics(sys))
    bcs = map(get_bcs(sys)) do eq
        l = unwrap(eq.lhs)
        terms = iscall(l) && operation(l) === (+) ? collect(Any, arguments(l)) : Any[l]
        # the coefficient of each face read (`c(t, 0, y)`, `Dx(c(t, 0, y))`), summed over its terms
        other, cores, coefs = Any[], Any[], Any[]
        for tm in terms
            fac = iscall(tm) && operation(tm) === (*) ? arguments(tm) : Any[tm]
            k = findfirst(f -> _fieldread(f, fields) !== nothing || (iscall(unwrap(f)) && operation(unwrap(f)) isa Differential &&
                                                                     _fieldread(arguments(unwrap(f))[1], fields) !== nothing), fac)
            k === nothing && (push!(other, tm); continue)
            core = unwrap(fac[k])
            c = prod(Symbolics.wrap.(fac[setdiff(eachindex(fac), k)]); init = Symbolics.wrap(1))
            j = findfirst(o -> isequal(o, core), cores)
            j === nothing ? (push!(cores, core); push!(coefs, c)) : (coefs[j] += c)
        end
        changed = false
        for (i, (core, c)) in enumerate(zip(cores, coefs))
            (simple(c) || !onlyparams(c)) && continue
            isder = operation(core) isa Differential
            r = _fieldread(isder ? arguments(core)[1] : core, fields)
            a = findfirst(j -> !isequal(r.args[j], ivs[j]), 2:length(r.args))
            a === nothing && continue
            side = _cval(r.args[a + 1]) == lows[a + 1] ? "low" : "high"
            base = string(nameof(r.op), r.comp == 0 ? "" : string("_", r.comp), "_", ivs[a + 1], "_", side, "_", isder ? "β" : "α")
            n, j = base, 1
            while n in taken
                j += 1
                n = string(base, "_", j)
            end
            push!(taken, n)
            q = unwrap(only(ModelingToolkitBase.@parameters $(Symbol(n))))
            push!(extra, q)
            # the slot holds β of `α c + β ∂c/∂n = g` (outward normal):
            # on a low face `∂c/∂n = −∂c/∂x`, so the written coefficient is −β
            flip = isder && side == "low"
            ic[q] = unwrap(flip ? -c : c)
            coefs[i] = flip ? -Symbolics.wrap(q) : Symbolics.wrap(q)
            changed = true
        end
        changed || return eq
        return sum(Symbolics.wrap, other; init = Symbolics.wrap(0)) +
               sum(Symbolics.wrap(c) * Symbolics.wrap(core) for (core, c) in zip(cores, coefs)) ~ eq.rhs
    end
    isempty(extra) && return sys
    return PDESystem(
        get_eqs(sys), bcs, get_domain(sys), get_ivs(sys), get_dvs(sys), Any[ps; extra]; name = nameof(sys),
        initial_conditions = ic)
end
