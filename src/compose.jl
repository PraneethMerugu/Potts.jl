# Composition: `extend(sys, base)` merges two Potts models (MTK's `extend`), and
# `@extend names = base = Model()` inside `@potts_model` binds names of a base model.
#
# Kinds are numbered, and expressions refer to kinds by number, so the base's kinds must be
# a prefix of the extension's (an extension may add kinds after them).

"""
    extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))

The model with everything in `base` and `sys`. `sys` wins where both define something
(parameters and variables by name, relations, the lattice and sweep of a `@potts_model`
extension that declares them). Structural replacement: an update of `sys` replaces the base's
updates of the same target in the same phase (whatever their cadences; a warning names a
changed cadence), an equation the base's equation for the same
variable, an observed quantity the base's of the same name. Energies, drives, constraints,
divisions, relationships and link rules accumulate, base first.
"""
function ModelingToolkitBase.extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))
    length(sys.kinds) >= length(base.kinds) && sys.kinds[1:length(base.kinds)] == base.kinds ||
        throw(ArgumentError("extend: the kinds of $(nameof(base)) $(base.kinds) must come first in $(nameof(sys)) $(sys.kinds)"))
    sys = _renumber_draws(sys, base)
    for u in sys.updates, b in base.updates
        _target_key(u) == _target_key(b) && u.every != b.every &&
            @warn "extend: `$(u.eq.lhs)` @$(u.phase) Every($(u.every)) replaces the base's Every($(b.every)) update"
    end
    byname(xs, ys) = (seen = Set(info(y).name for y in ys);
        Any[filter(x -> !(info(x).name in seen), xs)..., ys...])
    return PottsSystem(; name, kinds = sys.kinds, frozen_kinds = sort!(union(base.frozen_kinds, sys.frozen_kinds)),
        lattice = sys.lattice, parameters = byname(base.parameters, sys.parameters),
        variables = byname(base.variables, sys.variables), relations = merge(base.relations, sys.relations),
        energies = [base.energies; sys.energies], drives = [base.drives; sys.drives],
        constraints = [base.constraints; sys.constraints],
        updates = [_unreplaced(base.updates, sys.updates, _target_key); sys.updates],
        equations = [_unreplaced(base.equations, sys.equations, eq -> string(eq.lhs)); sys.equations],
        divisions = [base.divisions; sys.divisions],
        relationships = unique(r -> r.name, [sys.relationships; base.relationships]),
        link_rules = [base.link_rules; sys.link_rules],
        observed = [_unreplaced(base.observed, sys.observed, o -> info(o.var).name); sys.observed],
        components = unique(c -> c.name, [sys.components; base.components]),
        sweep = sys.sweep, structural = merge(base.structural, sys.structural),
        sources = merge(base.sources, sys.sources))
end

"""Items of `base` whose key no item of `new` shares."""
_unreplaced(base, new, key) = (keys = Set(key(x) for x in new); filter(x -> !(key(x) in keys), base))
"""What an update writes: its phase and target (`x`, `act[target]`, …). An extension's update
replaces the base's whatever their cadences (D-045)."""
_target_key(u::Update) = (u.phase, string(u.eq.lhs))

# Draws are numbered per model (`random_uniform(k)`); two separately built models both start
# at 1, so the extension's draws move past the base's to keep their streams independent.
_draw_indices(xs) = (out = Int[]; foreach(x -> _walk_all(y -> (iscall(y) && operation(y) === random_uniform &&
    push!(out, Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[1]))))), x), xs); out)
_random_exprs(s::PottsSystem) = Any[(u.eq.rhs for u in s.updates)..., (eq.rhs for eq in s.equations)...,
    (d.when for d in s.divisions)..., (r for d in s.divisions for (_, r) in d.rules)..., (r.when for r in s.link_rules)...]
function _renumber_draws(sys::PottsSystem, base::PottsSystem)
    mine = _draw_indices(_random_exprs(sys))
    theirs = _draw_indices(_random_exprs(base))
    (isempty(mine) || isempty(theirs) || minimum(mine) > maximum(theirs)) && return sys
    off = maximum(theirs)
    function shift(x)
        sub = Dict{Any, Any}()
        _walk_all(x) do y
            iscall(y) && operation(y) === random_uniform || return
            k = Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[1])))
            sub[y] = _unwrap(random_uniform(Num(k + off)))
        end
        isempty(sub) ? x : Symbolics.substitute(x, sub; fold = Val(false))
    end
    m = _map_statements(shift, sys)
    return _replace(sys; merge(m, (; sources = merge(sys.sources, m.sources)))...)
end

"""`sys` with some fields replaced."""
_replace(sys::PottsSystem; kw...) =
    PottsSystem(; (f => getfield(sys, f) for f in fieldnames(PottsSystem))..., kw...)

"""
    lookup(sys::PottsSystem, name::Symbol)

The quantity called `name` in a model: a parameter, variable, observed quantity, kind
(its number), relation or relationship; `x′` for a site or field variable `x` is its value
at the other site of a contact pair. `@extend` binds names with it.
"""
function lookup(sys::PottsSystem, name::Symbol)
    x = _lookup_primed(sys, name)
    x === nothing || return x
    for x in Iterators.flatten((sys.parameters, sys.variables))
        info(x).name === name && return x
    end
    for o in sys.observed
        info(o.var).name === name && return o.var
    end
    # a vector quantity: its components (tagged `vector = name`) in order (A-37)
    comps = [x for x in Iterators.flatten((sys.parameters, sys.variables)) if get(info(x).options, :vector, nothing) === name]
    isempty(comps) || return QuantityVector(name, Num[Symbolics.wrap(x) for x in sort!(comps; by = x -> info(x).options.index)])
    k = findfirst(==(name), sys.kinds)
    k === nothing || return k - 1
    haskey(sys.relations, name) && return RelationRef(name)
    any(r -> r.name === name, sys.relationships) && return RelationshipRef(name)
    throw(ArgumentError("$(nameof(sys)) has no parameter, variable, kind or relation `$name`"))
end

# `x′` of a site or field variable `x` (scalar or vector) of `sys`, or `nothing`
function _lookup_primed(sys::PottsSystem, name::Symbol)
    s = string(name)
    endswith(s, '′') || return nothing
    base = Symbol(chop(s))
    _is_site_quantity(sys, base) || return nothing
    return _primed(lookup(sys, base))
end
function _is_site_quantity(sys::PottsSystem, name::Symbol)
    return any(x -> (i = info(x); i.role in (:site, :field) && (i.name === name || get(i.options, :vector, nothing) === name)),
        sys.variables)
end
