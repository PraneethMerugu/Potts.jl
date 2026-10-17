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
    LatticeIndex(; key = identity, variables, parameters, independent_variables, defaults)

The symbol table of a field problem (the `sys` of its `ODEFunction`, and the symbolic
container of `FieldProblem`, `FieldSolution` and `FieldIntegrator`). `variables` is a vector
of `symbols => FieldSlot` (one or more spellings per field; the first is the canonical one),
`parameters` of `symbols => index` into the raw parameter vector; `independent_variables`
the time symbols. Every symbol is looked up as `key(sym)`.
"""
struct LatticeIndex{F}
    key::F
    vars::Dict{Any, FieldSlot}
    varsyms::Vector{Any}
    params::Dict{Any, Int}
    paramsyms::Vector{Any}
    ivs::Vector{Any}
    defaults::Dict{Any, Any}
end
function LatticeIndex(; key::F = identity, variables = Pair[], parameters = Pair[],
        independent_variables = Any[], defaults = Dict{Any, Any}()) where {F}
    vars, varsyms = Dict{Any, FieldSlot}(), Any[]
    for (syms, slot) in variables
        syms = syms isa Union{Tuple, AbstractVector} ? syms : (syms,)
        push!(varsyms, first(syms))
        foreach(s -> vars[key(s)] = slot, syms)
    end
    params, paramsyms = Dict{Any, Int}(), Any[]
    for (syms, i) in parameters
        syms = syms isa Union{Tuple, AbstractVector} ? syms : (syms,)
        push!(paramsyms, first(syms))
        foreach(s -> params[key(s)] = i, syms)
    end
    return LatticeIndex(key, vars, varsyms, params, paramsyms,
        Any[independent_variables...], Dict{Any, Any}(defaults))
end

_slot(ix::LatticeIndex, sym) = get(ix.vars, ix.key(sym), nothing)

SII.is_variable(ix::LatticeIndex, sym) = _slot(ix, sym) !== nothing
function SII.variable_index(ix::LatticeIndex, sym)
    s = _slot(ix, sym)
    return s === nothing ? nothing : indices(s)
end
SII.variable_symbols(ix::LatticeIndex) = ix.varsyms
SII.is_parameter(ix::LatticeIndex, sym) = haskey(ix.params, ix.key(sym))
SII.parameter_index(ix::LatticeIndex, sym) = get(ix.params, ix.key(sym), nothing)
SII.parameter_symbols(ix::LatticeIndex) = ix.paramsyms
function SII.is_independent_variable(ix::LatticeIndex, sym)
    any(v -> isequal(ix.key(v), ix.key(sym)),
        ix.ivs)
end
SII.independent_variable_symbols(ix::LatticeIndex) = ix.ivs
SII.is_observed(::LatticeIndex, sym) = false
SII.is_time_dependent(::LatticeIndex) = true
SII.constant_structure(::LatticeIndex) = true
SII.all_variable_symbols(ix::LatticeIndex) = ix.varsyms
SII.all_symbols(ix::LatticeIndex) = vcat(ix.varsyms, ix.paramsyms, ix.ivs)
SII.default_values(ix::LatticeIndex) = ix.defaults
