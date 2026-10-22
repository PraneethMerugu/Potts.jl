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
                 tables = [])

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
p = [Dk => values])` gives new values; `integ.ps[Dk]`, `getp(prob, Dk)` read them). Any other
symbol given as a parameter is an error naming the parameters. Every symbol is looked up as
`key(sym)`.
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
end
function LatticeIndex(; key::F = identity, variables = Pair[], parameters = Pair[],
        independent_variables = Any[], defaults = Dict{Any, Any}(), inputs = Pair[],
        inputnames = Pair[], boolinputs = String[], inputbounds = Pair[], derived = Pair[], observed = Pair[],
        tables = Pair[]) where {F}
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
    # inputs first, so a shared name would route a read or write to the wrong one (F1)
    names = Dict{String, String}(String(k) => String(v) for (k, v) in inputnames)
    ins = Dict{Any, String}()
    for (ss, k) in inputs, s in syms(ss)
        kk = key(s)
        o = get(ins, kk, nothing)
        o === nothing || o == k || throw(ArgumentError(string("two input fields have the name `", s, "`: `",
            o, "` and `", k, "`; give each input its own name (`lattice_input_name`)")))
        what = haskey(vars, kk) ? "a field" : haskey(params, kk) ? "a parameter" : nothing
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
                                                       for (ss, k) in tables for s in syms(ss)))
end

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
    return "#$i"
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
# (SciMLBase's `fill_p` asks `parameter_index` for every key) or `setp` of it is refused (F1)
_scalar(sym) = !(sym isa Union{AbstractArray, Tuple})
SII.is_parameter(ix::LatticeIndex, sym) = _scalar(sym) && haskey(ix.params, ix.key(sym))
SII.is_observed(ix::LatticeIndex, sym) = _scalar(sym) && haskey(ix.observed, ix.key(sym))
SII.parameter_observed(ix::LatticeIndex, sym) = _scalar(sym) ? get(ix.observed, ix.key(sym), nothing) :
                                               _observed_list(ix, sym)
function SII.observed(ix::LatticeIndex, sym)
    f = SII.parameter_observed(ix, sym)
    f === nothing && throw(ArgumentError("`$sym` is not observed"))
    return (u, p, t) -> f(p, t)
end
# a list of parameters and computed parameters, read together (`getp(sol, [a, k2])`)
function _observed_list(ix::LatticeIndex, syms)
    fs = map(collect(syms)) do s
        k = ix.key(s)
        haskey(ix.observed, k) && return ix.observed[k]
        i = get(ix.params, k, nothing)
        i === nothing && throw(ArgumentError("`$s` is not a parameter of the problem"))
        return (p, t) -> p[i]
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
    if haskey(ix.tables, k)
        t = first(ix.tables[k])
        throw(ArgumentError(string("`", t, "` is a table (an array parameter), set where the problem is built: ",
            "on an owned problem (a FieldProblem), `remake(prob; p = [", t, " => values])` gives it new values, ",
            "and on its integrator `integ.ps[", t, "] = values`; an ODE problem's tables are fixed (give them to ",
            "`discretize(…; p = [", t, " => values])`)")))
    end
    _scalar(sym) || return nothing
    i = get(ix.params, k, nothing)
    i === nothing || return i
    haskey(ix.derived, k) && throw(ArgumentError("`$sym` is not a parameter of the problem: $(ix.derived[k])"))
    # a variable, an input or the time is not a parameter (`nothing`); any other symbol is a
    # typo, an error rather than a key `remake` would skip
    (haskey(ix.vars, k) || haskey(ix.inputs, k) || SII.is_independent_variable(ix, sym)) && return nothing
    # an expression (`2c`) is not an index (SII's contract: `nothing`); a name is
    sym isa Union{Symbol, AbstractString} || SII.hasname(sym) || return nothing
    throw(ArgumentError(string("`", sym, "` is not a parameter of the problem (its parameters: ",
        join(("`$q`" for q in ix.paramsyms), ", "), ")")))
end
# every key of a parameter map names a parameter: `parameter_index` throws for a table, a
# computed parameter or an unknown name, and gives `nothing` for what is no parameter (a field,
# an input, an expression such as `2k`), which SciMLBase's `remake` would skip silently (F1)
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
table_entry(ix::LatticeIndex, sym) = (sym isa Tuple || sym isa Integer) ? nothing :
                                     (t = get(ix.tables, ix.key(sym), nothing); t === nothing ? nothing : last(t))
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
