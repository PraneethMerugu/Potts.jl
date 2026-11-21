# Spatial operators across `Coarse` grids. A spatial operator reads its
# operand on the operand's own grid, so one whose operand lives on another grid than the row
# (`D(u) ~ 0.5 laplacian(c)` with `c` on `Coarse(4)`, or the reverse) is written as the aux
# field of the manual route: `X ~ laplacian(c)` on the grid of `c`, and the row reads `X` as
# it reads any field of another grid:
# - a coarse operand in a fine row: the coarse operator read at the node of the site's
#   block;
# - a fine operand in a coarse row: the block mean of the fine operator, the net flux
#   through the faces of the block over its volume (the fold of `Coarse` fields).
# The pass runs before the equations are classified, so a hoisted term is an aux row for the
# rest of the lowering, the solvers, and callers.

"""
    is_crossgrid_key(k::AbstractString) -> Bool

Whether the field key `k` is an aux field that the cross-grid pass added (`laplacian(c)`,
`DivKGrad(c)`: a call, which no field of a model is). Callers that manage their fields
separately keep such a field as scratch of the binding, not as state.

# Examples
```jldoctest
julia> using LatticePDE

julia> LatticePDE.is_crossgrid_key("laplacian(c)"), LatticePDE.is_crossgrid_key("c")
(true, false)
```
"""
is_crossgrid_key(k::AbstractString) = occursin('(', k)

# the operand of a spatial operator call `u`: a field read `c(t, x, y)` or `c(t, x, y)[i]`
function _xg_operand(u)
    f, a = operation(u), arguments(u)
    f === laplacian && return a[1]
    (f isa DivKGrad || f isa Advect) && return a[end]
    f isa Differential || return nothing
    r = _raw_flux(u)
    return r === nothing ? nothing : r[2]
end
function _xg_isop(u)
    return iscall(u) &&
        (
        operation(u) === laplacian ||
            operation(u) isa Union{DivKGrad, Advect, Differential}
    )
end
function _xg_label(f)
    if f === laplacian
        return "laplacian"
    elseif f isa DivKGrad
        return "DivKGrad"
    elseif f isa Advect
        return "Advect"
    else
        return "flux"
    end
end

"""
    crossgrid_form(sys) -> sys

`sys` with every spatial operator whose operand lives on another `Coarse` level than its
row's field hoisted into an aux field of the operand's level (`X ~ op(c)`, named as the
term is written: `laplacian(c)`, `DivKGrad(c)`, `Advect(c)`, `flux(c)`), the row reading it.
The same term in several rows is one aux field. A system with no such term is returned as it
is.
"""
function crossgrid_form(sys::PDESystem)
    lev = Dict{Any, Int}()
    meta = Dict{Any, Any}()
    for v in get_dvs(sys)
        L = get_lattice_level(v)
        lev[_opof(v)] = L isa Coarse ? level_of(L) : 0
        L isa Coarse && (meta[_opof(v)] = L)
    end
    isin = Dict{Any, Bool}(op => true for op in Base.keys(lev))
    function lhslevel(eq)
        l = unwrap(eq.lhs)
        a = iscall(l) && operation(l) isa Union{Differential, Shift} ? arguments(l)[1] : l
        r = _fieldread(a, isin)
        return r === nothing ? nothing : lev[r.op]
    end
    # (term, the aux read, the operand's level)
    rules = Tuple{Any, Any, Int}[]
    auxs = Any[]                                  # the aux variables
    auxeqs = Equation[]
    taken = Set{String}(_name(op) for op in Base.keys(lev))
    ivs = unwrap.(get_ivs(sys))
    function hoist(u, op)
        for (k, v, _) in rules
            isequal(k, u) && return v
        end
        base = string(_xg_label(operation(u)), "(", _name(op), ")")
        name, i = base, 1
        while name in taken
            i += 1
            name = string(base, "#", i)
        end
        push!(taken, name)
        x = unwrap(
            Symbolics.variable(
                Symbol(name); T = SymbolicUtils.FnType{
                    Tuple, Real, Nothing,
                }
            )
        )(ivs...)
        haskey(meta, op) && (x = SymbolicUtils.setmetadata(x, LatticeLevel, meta[op]))
        push!(rules, (u, x, lev[op]))
        push!(auxs, x)
        push!(auxeqs, Symbolics.wrap(x) ~ Symbolics.wrap(u))
        return x
    end
    function walk(u, level)
        u = unwrap(u)
        iscall(u) || return nothing
        if _xg_isop(u)
            o = _xg_operand(u)
            r = o === nothing ? nothing : _fieldread(o, isin)
            r !== nothing && lev[r.op] != level && hoist(u, r.op)
            return nothing
        end
        foreach(y -> walk(y, level), arguments(u))
        return nothing
    end
    for eq in get_eqs(sys)
        l = lhslevel(eq)
        l === nothing || walk(eq.rhs, l)
    end
    isempty(rules) && return sys
    # (a term reads its aux only in the rows of another grid than its operand's: the
    # operand's own row keeps the operator on the grid, `D(c) ~ laplacian(c)`)
    function sub(x, l)
        return substitute(
            x, Dict{Any, Any}(k => v for (k, v, lo) in rules if lo != l);
            fold = Val(false)
        )
    end
    eqs = Equation[
        lhslevel(eq) === nothing ? eq : eq.lhs ~ sub(eq.rhs, lhslevel(eq))
            for eq in get_eqs(sys)
    ]
    return PDESystem(
        [eqs; auxeqs], get_bcs(sys), get_domain(sys), get_ivs(sys), Any[get_dvs(sys); auxs],
        _params(sys);
        name = nameof(sys), initial_conditions = _ics(sys)
    )
end

"""
    operand_reads(eqs, ops) -> Vector

The fields of `ops` (operations, `c`) that a spatial operator in the right sides of `eqs`
reads as its operand (`laplacian(c)`, `DivKGrad(K, c)`, `Advect(v, c)`, a raw flux), or
that a term reads at an offset (`c(t, x + dx, y)` in a map): its value past a face needs
the field's face conditions, and its neighbors its own periodicity. A group that reads
another group's field so marks it `LatticeCutField`, as the whole system reads it.

# Arguments
- `eqs`: the equations.
- `ops`: the field operations to look for.

# Returns
- The operations of `ops` read in this way, each once, in the order they are found.
"""
function operand_reads(eqs, ops)
    out = Any[]
    function walk(u)
        u = unwrap(u)
        iscall(u) || return nothing
        # an offset read: a space argument that is not the bare variable
        f = operation(u)
        if any(op -> isequal(op, f), ops) && any(iscall ∘ unwrap, arguments(u)[2:end]) &&
                !any(x -> isequal(x, f), out)
            push!(out, f)
        end
        if _xg_isop(u) && (o = _xg_operand(u)) !== nothing
            for op in ops
                _reads(o, (op,)) && !any(x -> isequal(x, op), out) && push!(out, op)
            end
        end
        foreach(walk, arguments(u))
        return nothing
    end
    foreach(eq -> walk(eq.rhs), eqs)
    return out
end
