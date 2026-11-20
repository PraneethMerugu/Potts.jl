# Symbolic indexing (SymbolicIndexingInterface) of field problems, solutions and integrators.
# The state is one flat vector; each field has a `FieldSlot` (its range and grid dims), and
# `variable_index` returns the slot's range reshaped to the grid, so `sol[c]` is a vector of
# grid-shaped arrays. LatticeFields does not know the symbolic types: the front end gives the
# symbols and a normalizing `key` function (e.g. `Symbolics.unwrap`).

"""
    FieldSlot(range, dims)

Where a field lives in the flat state: `range`, holding the grid `dims` (column-major).
"""
struct FieldSlot{N}
    range::UnitRange{Int}
    dims::NTuple{N, Int}
end
indices(s::FieldSlot) = reshape(s.range, s.dims)

"""
    LatticeIndex(; key = identity, variables, parameters, independent_variables, defaults,
                 inputs = [], inputnames = [], boolinputs = [], inputbounds = [], derived = [], observed = [],
                 tables = [], aux = [])

The symbol table of a field problem (the `sys` of its `ODEFunction`, and the symbolic
container of `FieldProblem`, `FieldSolution` and `FieldIntegrator`). `variables` is a vector
of `symbols => FieldSlot` (one or more spellings per field; the first is the canonical one),
`parameters` of `symbols => index` into the raw parameter vector; `independent_variables`
the time symbols. `inputs` maps `symbols => key`, the input fields of the program (set
with the problem's `inputs` keyword, `remake(prob; inputs)` or `integ[sym] = values`), and
`inputnames` maps an input key to the name messages print (its user-facing name), and
`boolinputs` lists the keys of inputs declared `Bool` (they take only Bool or 0/1);
`inputbounds` maps an input key to its declared bounds `(lo, hi)` (its values must lie in
them: a bound such as `lo ≥ 1` tells the stability bound that a table index is never 0);
`derived` maps the symbols of quantities that are not parameters of the problem (a computed
parameter, folded into the equations) to the sentence that says why; `observed` maps such
symbols to how they read, `(p, t) -> value` from the raw parameters (a function, or an `Expr`
compiled here), so `getp(sol, k2)`, `sol.ps[k2]` and `integ.ps[k2]` read them while `remake` and
`setp` refuse them (their `parameter_index` throws); `tables` maps the symbols of array
parameters to their table keys, or an entry's symbol to `(key, i)` (`remake(prob::FieldProblem;
p = [Dk => values])` gives new values; `integ.ps[Dk]`, `getp(prob, Dk)` read them); `aux` maps
`symbols => key`, the aux fields of the program (`K ~ rhs`): not part of the
state, they are evaluated from it and read by `sol[K]` and `integ[K]` ([`aux_key`](@ref); on the
ODE path they are observed, `rhs(u(t), t)`, through the evaluator `ode_problem` sets); `coordinates`
maps `symbols => centers`, each spatial coordinate to its site centers (a range: `sol[x]`, and
`sol(t, x, y)` interpolates between them); `maskevents` holds the switch functions of the
moving masks, `(p, t) -> lhs - rhs` from the raw parameters (an `Expr` is compiled here), whose
roots an OrdinaryDiffEq solve locates, and `maskunlocated` says that a mask predicate reads the
time in a switch with no such function ([`MaskSync`](@ref)). Any
other symbol given as a parameter is an error naming the parameters. Every symbol is looked up
as `key(sym)`.
"""
struct LatticeIndex{F}
    key::F
    vars::Dict{Any, FieldSlot}
    varsyms::Vector{Any}
    params::Dict{Any, Int}
    paramsyms::Vector{Any}
    ivs::Vector{Any}
    defaults::Dict{Any, Any}
    inputs::Dict{Any, String}
    inputnames::Dict{String, String}
    boolinputs::Set{String}
    inputbounds::Dict{String, Tuple{Float64, Float64}}
    derived::Dict{Any, String}
    observed::Dict{Any, Any}
    tables::Dict{Any, Tuple{String, Int}}       # symbol → (table key, entry; 0 for the whole table)
    parambounds::Dict{Int, Tuple{Float64, Float64}}   # slot → declared `bounds`, checked at every write
    derive::Any                                 # `nothing`, or `(Derivation, sources, slots)`: the computed slots
    aux::Dict{Any, String}                      # symbol → aux field key
    auxsyms::Vector{Any}                        # the canonical symbol of each aux field
    auxeval::Ref{Any}                           # the ODE path's aux evaluator `(u, p, t, key)`, or nothing
    program::Ref{Any}                           # the semantic program (the checks of an input write), or nothing
    coords::Dict{Any, Any}                      # a spatial coordinate → its site centers (a range; `sol[x]`)
    coordsyms::Vector{Any}                      # the spatial coordinates, in order
    maskevents::Vector{Any}                     # the masks' switch functions `(p, t) -> lhs - rhs` (an ODE path's events)
    maskunlocated::Bool                         # a mask predicate reads the time in a switch with no event
end
function LatticeIndex(; key::F = identity, variables = Pair[], parameters = Pair[],
        independent_variables = Any[], defaults = Dict{Any, Any}(), inputs = Pair[],
        inputnames = Pair[], boolinputs = String[], inputbounds = Pair[], derived = Pair[], observed = Pair[],
        tables = Pair[], parambounds = Pair[], derive = nothing, aux = Pair[], coordinates = Pair[],
        maskevents = Any[], maskunlocated::Bool = false) where {F}
    syms(x) = x isa Union{Tuple, AbstractVector} ? x : (x,)
    vars, varsyms = Dict{Any, FieldSlot}(), Any[]
    for (ss, slot) in variables
        push!(varsyms, first(syms(ss)))
        foreach(s -> vars[key(s)] = slot, syms(ss))
    end
    params, paramsyms = Dict{Any, Int}(), Any[]
    for (ss, i) in parameters
        push!(paramsyms, first(syms(ss)))
        foreach(s -> params[key(s)] = i, syms(ss))
    end
    # an input's names never shadow another input, a variable or a parameter: lookups try the
    # inputs first, so a shared name would route a read or write to the wrong one
    names = Dict{String, String}(String(k) => String(v) for (k, v) in inputnames)
    ins = Dict{Any, String}()
    for (ss, k) in inputs, s in syms(ss)
        kk = key(s)
        o = get(ins, kk, nothing)
        o === nothing || o == k || throw(ArgumentError(string("two input fields have the name `", s, "`: `",
            o, "` and `", k, "`; give each input its own name (`lattice_input_name`)")))
        what = if haskey(vars, kk)
            "a field"
        elseif haskey(params, kk)
            "a parameter"
        else
            nothing
        end
        what === nothing || throw(ArgumentError(string("the input field `", k, "` has the name `", s,
            "` (its `lattice_input_name`), which is also ", what, " of the problem; give the input another name")))
        ins[kk] = String(k)
    end
    der = Dict{Any, String}()
    for (ss, why) in derived
        foreach(s -> der[key(s)] = String(why), syms(ss))
    end
    obs = Dict{Any, Any}()
    for (ss, f) in observed
        g = f isa Expr ? rgf(f) : f
        foreach(s -> obs[key(s)] = g, syms(ss))
    end
    return LatticeIndex(key, vars, varsyms, params, paramsyms,
        Any[independent_variables...], Dict{Any, Any}(defaults), ins,
        names, Set{String}(String.(boolinputs)),
        Dict{String, Tuple{Float64, Float64}}(String(k) => Float64.((b[1], b[2])) for (k, b) in inputbounds), der, obs, Dict{Any, Tuple{String, Int}}(key(s) => (k isa Tuple ? (String(k[1]), Int(k[2])) : (String(k), 0))
                                                       for (ss, k) in tables for s in syms(ss)),
        Dict{Int, Tuple{Float64, Float64}}(Int(i) => Float64.((b[1], b[2])) for (i, b) in parambounds), derive,
        Dict{Any, String}(key(s) => String(k) for (ss, k) in aux for s in syms(ss)), Any[first(syms(ss)) for (ss, _) in aux],
        Ref{Any}(nothing), Ref{Any}(nothing), Dict{Any, Any}(key(s) => r for (ss, r) in coordinates for s in syms(ss)),
        Any[first(syms(ss)) for (ss, _) in coordinates], Any[f isa Expr ? rgf(f) : f for f in maskevents], maskunlocated)
end

# `ix.K` for a name that is not a field of the index: its canonical symbol, as an MTK system
# gives `sys.K` (SciMLBase looks an observed name up this way: `sol[:K]` on the ODE path)
@inline Base.getproperty(ix::LatticeIndex, s::Symbol) = hasfield(LatticeIndex, s) ? getfield(ix, s) : _symbol_of(ix, s)
function _symbol_of(ix::LatticeIndex, s::Symbol)
    k = aux_key(ix, s)
    if k !== nothing
        for a in getfield(ix, :auxsyms)
            aux_key(ix, a) == k && return a
        end
    end
    obs = getfield(ix, :observed)
    f = get(obs, getfield(ix, :key)(s), nothing)
    if f !== nothing
        for (q, g) in obs
            q isa Symbol || g !== f || return q
        end
    end
    throw(ArgumentError("`$s` is not an aux field or observed quantity of the problem"))
end
Base.propertynames(::LatticeIndex) = fieldnames(LatticeIndex)

"""
    aux_key(ix, sym) -> String or nothing

The aux field key of `sym` (a symbol of `ix`, or the key itself), else `nothing`.
"""
aux_key(ix::LatticeIndex, sym::AbstractString) = sym in values(ix.aux) ? String(sym) : get(ix.aux, ix.key(sym), nothing)
aux_key(ix::LatticeIndex, sym) = (sym isa Union{AbstractArray, Tuple} || sym isa Integer) ? nothing : get(ix.aux, ix.key(sym), nothing)
aux_key(ix, sym) = nothing

"""
    input_key(ix, sym) -> String or nothing

The input field key of `sym` (a symbol of `ix`, or the key itself), else `nothing`.
"""
input_key(ix::LatticeIndex, sym::AbstractString) = sym in values(ix.inputs) ? String(sym) : get(ix.inputs, ix.key(sym), nothing)
input_key(ix::LatticeIndex, sym) = get(ix.inputs, ix.key(sym), nothing)

"""The name of parameter slot `i` in `ix` (its canonical symbol), or `"#i"`."""
function parameter_name(ix::LatticeIndex, i::Integer)
    for s in ix.paramsyms
        get(ix.params, ix.key(s), 0) == i && return string(s)
    end
    k = computed_slot(ix, i)                     # a computed parameter's slot: its name
    k === nothing || return string(k)
    return "#$i"
end
# the computed parameter that slot `i` holds, or `nothing`
function computed_slot(ix::LatticeIndex, i::Integer)
    ix.derive === nothing && return nothing
    d, _, slots = ix.derive
    k = findfirst(==(i), slots)
    return k === nothing ? nothing : d.computed[k]
end

_slot(ix::LatticeIndex, sym) = get(ix.vars, ix.key(sym), nothing)

SII.is_variable(ix::LatticeIndex, sym) = _slot(ix, sym) !== nothing
function SII.variable_index(ix::LatticeIndex, sym)
    s = _slot(ix, sym)
    return s === nothing ? nothing : indices(s)
end
SII.variable_symbols(ix::LatticeIndex) = ix.varsyms
# A derived symbol (a computed parameter) is observed, not a parameter: it reads through
# `parameter_observed`, and its `parameter_index` is an error that says why, so a remake
# (SciMLBase's `fill_p` asks `parameter_index` for every key) or `setp` of it is refused
_scalar(sym) = !(sym isa Union{AbstractArray, Tuple})
# A table (or an entry) and an input are parameters too (`Constants` and
# `Discrete` of `LatticeParameters`), indexed by a `TableSlot` and an `InputSlot`
function SII.is_parameter(ix::LatticeIndex, sym)
    return (_scalar(sym) && haskey(ix.params, ix.key(sym))) || table_key(ix, sym) !== nothing ||
        (!(sym isa Union{AbstractArray, Tuple, Integer}) && input_key(ix, sym) !== nothing)
end
SII.is_observed(ix::LatticeIndex, sym) = _scalar(sym) && (haskey(ix.observed, ix.key(sym)) || _ode_aux(ix, sym) !== nothing)
# an aux field on the ODE path: observed, `rhs(u(t), t)` from the solver's state
_ode_aux(ix::LatticeIndex, sym) = ix.auxeval[] === nothing ? nothing : aux_key(ix, sym)
function SII.parameter_observed(ix::LatticeIndex, sym)
    if _scalar(sym)
        return _on_values(get(ix.observed, ix.key(sym), nothing))
    else
        return _observed_list(ix, sym)
    end
end
# an observed parameter reads the scalar values (`LatticeParameters` or a raw vector)
_on_values(f) = f === nothing ? nothing : (p, t) -> f(_pvals(p), t)
function SII.observed(ix::LatticeIndex, sym)
    k = _scalar(sym) ? _ode_aux(ix, sym) : nothing
    if k !== nothing
        ev = ix.auxeval[]
        return (u, p, t) -> ev(u, p, t, k)
    end
    f = SII.parameter_observed(ix, sym)
    f === nothing && throw(ArgumentError("`$sym` is not observed"))
    return (u, p, t) -> f(p, t)
end
# a list of parameters and computed parameters, read together (`getp(sol, [a, k2])`)
function _observed_list(ix::LatticeIndex, syms)
    fs = map(collect(syms)) do s
        k = ix.key(s)
        haskey(ix.observed, k) && return _on_values(ix.observed[k])
        i = get(ix.params, k, nothing)
        i === nothing && throw(ArgumentError("`$s` is not a parameter of the problem"))
        return (p, t) -> _pvals(p)[i]
    end
    return (p, t) -> [f(p, t) for f in fs]
end
function SII.parameter_index(ix::LatticeIndex, sym)
    sym isa Tuple && return nothing
    sym isa Bool && throw(ArgumentError("`$sym` is not a parameter: give a parameter's name or its index (an integer)"))
    if sym isa Integer                              # a slot of the parameter vector
        n = maximum(values(ix.params); init = 0)
        1 <= sym <= n || throw(ArgumentError(string("parameter index ", sym, " is out of range: the problem has ", n,
            n == 1 ? " parameter" : " parameters")))
        return Int(sym)
    end
    k = ix.key(sym)
    haskey(ix.tables, k) && return TableSlot(ix.tables[k]...)
    _scalar(sym) || return nothing
    ki = input_key(ix, sym)
    ki === nothing || return InputSlot(ki, ix)
    i = get(ix.params, k, nothing)
    i === nothing || return i
    haskey(ix.derived, k) && throw(ArgumentError(ix.derived[k]))     # a computed parameter: read-only
    # a variable, an input or the time is not a parameter (`nothing`); any other symbol is a
    # typo, an error rather than a key `remake` would skip
    (haskey(ix.vars, k) || SII.is_independent_variable(ix, sym)) && return nothing
    # an expression (`2c`) is not an index (SII's contract: `nothing`); a name is
    sym isa Union{Symbol, AbstractString} || SII.hasname(sym) || return nothing
    throw(ArgumentError(string("`", sym, "` is not a parameter of the problem (its parameters: ",
        join(("`$q`" for q in ix.paramsyms), ", "), ")")))
end
# every key of a parameter map names a parameter: `parameter_index` throws for a table, a
# computed parameter or an unknown name, and gives `nothing` for what is no parameter (a field,
# an input, an expression such as `2k`), which SciMLBase's `remake` would skip silently
function check_parameter_keys(ix::LatticeIndex, keys)
    for k in keys
        SII.parameter_index(ix, k) === nothing || continue
        kk = k isa Tuple ? nothing : ix.key(k)
        named = kk !== nothing && (haskey(ix.vars, kk) || haskey(ix.inputs, kk) || SII.is_independent_variable(ix, k))
        throw(ArgumentError(string("`", k, "` is not a parameter of the problem (its parameters: ",
            join(("`$q`" for q in ix.paramsyms), ", "), ")", named ? "" : "; a key names a parameter, not an expression")))
    end
    return nothing
end

"""
    table_key(ix, sym) -> String or nothing

The table key of the array parameter `sym`, else `nothing`.
"""
function table_key(ix::LatticeIndex, sym)
    (sym isa Tuple || sym isa Integer) && return nothing
    t = get(ix.tables, ix.key(sym), nothing)
    return t === nothing ? nothing : first(t)
end
"""
    table_entry(ix, sym) -> Int or nothing

The entry of the table that `sym` names: `i` for `Dk[i]`, 0 for the whole table `Dk`; `nothing`
if `sym` names no table. (`table_key` gives the table.)
"""
function table_entry(ix::LatticeIndex, sym)
    if sym isa Tuple || sym isa Integer
        return nothing
    else
        return (t = get(ix.tables, ix.key(sym), nothing); t === nothing ? nothing : last(t))
    end
end
SII.parameter_symbols(ix::LatticeIndex) = ix.paramsyms
function SII.is_independent_variable(ix::LatticeIndex, sym)
    any(v -> isequal(ix.key(v), ix.key(sym)),
        ix.ivs)
end
SII.independent_variable_symbols(ix::LatticeIndex) = ix.ivs
SII.is_time_dependent(::LatticeIndex) = true
SII.constant_structure(::LatticeIndex) = true
SII.all_variable_symbols(ix::LatticeIndex) = ix.varsyms
SII.all_symbols(ix::LatticeIndex) = vcat(ix.varsyms, ix.paramsyms, ix.ivs)
SII.default_values(ix::LatticeIndex) = ix.defaults
