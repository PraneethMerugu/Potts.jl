# Composition: `extend(sys, base)` merges two Potts models (MTK's `extend`), and
# `@extend names = base = Model()` inside `@potts_model` binds names of a base model.
#
# Kinds are numbered, and expressions refer to kinds by number, so the base's kinds must be
# a prefix of the extension's (an extension may add kinds after them).

"""
    extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))

The model with everything in `base` and `sys`. `sys` wins where both define something
(parameters and variables by name, relations, the lattice and sweep of a `@potts_model`
extension that declares them). A vector replaces the base's vector of its name as a whole and
may be longer, not shorter (the base may read the components a shorter one would drop). Structural replacement: an update of `sys` replaces the base's
updates of the same target in the same phase (whatever their cadences; a warning names a
changed cadence), an equation the base's equation for the same
variable, an observed quantity the base's of the same name. Energies, drives, constraints,
divisions, relationships and link rules accumulate, base first (a division rule for kinds
the base divides at another cadence warns: both rules apply, each at its own `Every`).
A name keeps its category: a name that is, say, a parameter of `base` and a variable of `sys`
is an `ArgumentError` naming both.
"""
function ModelingToolkitBase.extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))
    length(sys.kinds) >= length(base.kinds) && sys.kinds[1:length(base.kinds)] == base.kinds ||
        throw(ArgumentError("extend: the kinds of $(nameof(base)) $(base.kinds) must come first in $(nameof(sys)) $(sys.kinds)"))
    sys = _renumber_draws(sys, base)
    for u in sys.updates, b in base.updates
        _target_key(u) == _target_key(b) && u.every != b.every &&
            @warn "extend: `$(u.eq.lhs)` @$(u.phase) Every($(u.every)) replaces the base's Every($(b.every)) update"
    end
    # division rules accumulate: a rule of `sys` for kinds the base already divides at another
    # cadence adds a check, it does not replace the base's (both fire at their own MCS)
    for u in sys.divisions, b in base.divisions
        typeof(u.domain) == typeof(b.domain) && u.every != b.every && _kinds_overlap(u.domain, b.domain) &&
            @warn "extend: $(_describe(u)) adds to the base's $(_describe(b)) (division rules accumulate: " *
                  "both fire at their own cadence; the base's rule is not replaced)"
    end
    # a name keeps its category: say which side came from the base
    # (`@extend Base()` without a name calls the base `__base`)
    mine = _name_categories(sys)
    inbase = nameof(base) === :__base ? "in the base" : "in the base `$(nameof(base))`"
    for (n, old) in _name_categories(base)
        what = get(mine, n, old)
        what == old || throw(_category_clash(name, n, what, "$old $inbase"))
    end
    # a vector replaces the base's vector of its name as a whole, so it may not be shorter
    # (the base's statements may read the components it would drop)
    key(x) = (i = info(x); something(get(i.options, :vector, nothing), i.name))
    _check_vector_lengths(name, inbase, Iterators.flatten((base.parameters, base.variables)),
        Iterators.flatten((sys.parameters, sys.variables)))
    byname(xs, ys) = (seen = Set(key(y) for y in ys); Any[filter(x -> !(key(x) in seen), xs)..., ys...])
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
        discrete = unique(b -> b.name, [sys.discrete; base.discrete]),
        sweep = sys.sweep, structural = merge(base.structural, sys.structural),
        sources = merge(base.sources, sys.sources))
end

"""
`x′` is the contact-pair value of a site or field variable `x`: no quantity of the system
(parameter, variable or observed quantity, inherited through `@extend` or not) may carry
that name as well. Checked whenever a `PottsSystem` is constructed (`@potts_model`,
`extend` or a programmatic build).
"""
function _check_primed_names(sys::PottsSystem)
    names = Set{Symbol}()
    for x in Iterators.flatten((sys.parameters, sys.variables, (o.var for o in sys.observed)))
        i = info(x)
        i === nothing && continue
        push!(names, i.name)
        v = get(i.options, :vector, nothing)
        v === nothing || push!(names, v)
    end
    for n in names
        s = string(n)
        endswith(s, '′') || continue
        x = Symbol(chop(s))
        _is_site_quantity(sys, x) && throw(ArgumentError(
            "$(nameof(sys)): `$n` is declared, but `$n` already means the contact-pair value of the " *
            "site variable `$x` (primes exist only for site/field variables); rename one of them"))
    end
    return sys
end

"""
One name, one category: kinds, parameters, variables (every scope), observed quantities,
relations, relationships and components share one namespace. A vector quantity claims its
vector name and each component name (`bias` and `bias_1`, `bias_2`, …), and a component
system its namespaced quantities (`clk₊y` for the unknown or parameter `y` of the
component `clk`). `@potts_model` rejects a second category within one model (`_declare!`);
this rejects it however the `PottsSystem` was built (`@extend`, `extend`, a programmatic
build), so `lookup`, `observe` and `getu` agree on every name. A name declared twice in one
category is not a clash (`extend` keeps the extension's), but a scalar named like a
component of a vector is (it would leave part of the vector).
"""
_check_name_categories(sys::PottsSystem) = (_name_categories(sys); sys)

"""The category of every name of `sys` (name → category); throws on a name in two."""
function _name_categories(sys::PottsSystem)
    seen = Dict{Symbol, String}()
    function claim(n::Symbol, what::String)
        old = get!(seen, n, what)
        old == what || throw(_category_clash(nameof(sys), n, what, old))
        return nothing
    end
    foreach(k -> claim(k, "kind"), sys.kinds)
    for (what, xs) in (("parameter", sys.parameters), ("variable", sys.variables))
        for x in xs
            i = info(x)
            i === nothing && continue
            v = get(i.options, :vector, nothing)
            if v === nothing
                claim(i.name, what)
            else
                claim(v, what)
                claim(i.name, "$what (a component of the vector `$v`)")
            end
        end
    end
    foreach(o -> (i = info(o.var); i === nothing || claim(i.name, "observed quantity")), sys.observed)
    foreach(k -> k === :contact || claim(k, "relation"), keys(sys.relations))
    foreach(r -> claim(r.name, "relationship"), sys.relationships)
    for c in sys.components
        claim(c.name, "component")
        for u in Iterators.flatten((ModelingToolkitBase.unknowns(c.system), ModelingToolkitBase.parameters(c.system)))
            claim(Symbol(c.name, :₊, SymbolicIndexingInterface.getname(u)), "quantity of the component `$(c.name)`")
        end
    end
    return seen
end

"""Reject a vector of `mine` with fewer components than the base's vector of its name."""
function _check_vector_lengths(model, inbase, theirs, mine)
    components(xs) = (out = Dict{Symbol, Vector{Symbol}}();
        for x in xs
            i = info(x)
            v = i === nothing ? nothing : get(i.options, :vector, nothing)
            v === nothing || push!(get!(out, v, Symbol[]), i.name)
        end; out)
    ours = components(mine)
    for (v, names) in components(theirs)
        new = get(ours, v, nothing)
        (new === nothing || length(new) >= length(names)) && continue
        dropped = join(("`$n`" for n in names if !(n in new)), ", ")
        throw(ArgumentError("$model: `$v` has $(length(names)) components $inbase; the extension's " *
                            "`$v[1:$(length(new))]` would drop $dropped (an extension's vector may be longer, not shorter)"))
    end
    return nothing
end

"""`parameter `bias_2` (a component of the vector `bias`)`: a category label with its name."""
_labelled(what, n) = (i = findfirst(" (", what); i === nothing ? "$what `$n`" :
                                                 "$(what[1:prevind(what, first(i))]) `$n`$(what[first(i):end])")

_category_clash(model, n, what, old) = ArgumentError(
    "$model: $(_labelled(what, n)): `$n` is already declared as $(_with_article(old)) (kinds, parameters, variables, " *
    "observed quantities, relations, relationships and components share one namespace); rename one of them")

_kinds_overlap(a, b) = isempty(a.kinds) || isempty(b.kinds) || !isempty(intersect(a.kinds, b.kinds))

"""Items of `base` whose key no item of `new` shares."""
_unreplaced(base, new, key) = (keys = Set(key(x) for x in new); filter(x -> !(key(x) in keys), base))
"""What an update writes: its phase and target (`x`, `act[target]`, …). An extension's update
replaces the base's whatever their cadences."""
_target_key(u::Update) = (u.phase, string(u.eq.lhs))

# Draws are numbered per model (`random_uniform(k)`); two separately built models both start
# at 1, so the extension's draws move past the base's to keep their streams independent.
_draw_indices(xs) = (out = Int[]; foreach(x -> _walk_all(y -> (iscall(y) && operation(y) === random_uniform &&
    push!(out, Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[1]))))), x), xs); out)
_random_exprs(s::PottsSystem) = Any[(u.eq.rhs for u in s.updates)..., (eq.rhs for eq in s.equations)...,
    (d.when for d in s.divisions)..., (r for d in s.divisions for (_, r) in d.rules)..., (r.when for r in s.link_rules)...,
    (x for b in s.discrete for x in b.next)...]
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
    return any(x -> (i = info(x); i !== nothing && i.role in (:site, :field) && (i.name === name || get(i.options, :vector, nothing) === name)),
        sys.variables)
end
