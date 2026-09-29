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
updates of the same target in the same phase, an equation the base's equation for the same
variable, an observed quantity the base's of the same name. Energies, drives, constraints,
divisions, relationships and link rules accumulate, base first.
"""
function ModelingToolkitBase.extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))
    length(sys.kinds) >= length(base.kinds) && sys.kinds[1:length(base.kinds)] == base.kinds ||
        throw(ArgumentError("extend: the kinds of $(nameof(base)) $(base.kinds) must come first in $(nameof(sys)) $(sys.kinds)"))
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
"""What an update writes: its phase and target (`x`, `act[target]`, …)."""
_target_key(u::Update) = (u.phase, string(u.eq.lhs), u.every)

"""
    lookup(sys::PottsSystem, name::Symbol)

The quantity called `name` in a model: a parameter, variable, observed quantity, kind
(its number), relation or relationship. `@extend` binds names with it.
"""
function lookup(sys::PottsSystem, name::Symbol)
    for x in Iterators.flatten((sys.parameters, sys.variables))
        info(x).name === name && return x
    end
    for o in sys.observed
        info(o.var).name === name && return o.var
    end
    k = findfirst(==(name), sys.kinds)
    k === nothing || return k - 1
    haskey(sys.relations, name) && return RelationRef(name)
    any(r -> r.name === name, sys.relationships) && return RelationshipRef(name)
    throw(ArgumentError("$(nameof(sys)) has no parameter, variable, kind or relation `$name`"))
end
