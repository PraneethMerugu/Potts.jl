# Composition: MTK's `extend(sys, base)` merges two Potts models, and
# `@extend names = base = Model()` inside `@potts_model` binds names of a base model.
#
# Kinds are numbered, and expressions refer to kinds by number, so the base's kinds must be
# a prefix of the extension's (an extension may add kinds after them).

"""
    extend(sys::PottsSystem, base::PottsSystem; name = nameof(sys))

MTK's `extend` for two Potts models: the model with everything in `base` and `sys`. `sys` wins where both define something
(parameters and variables by name, relations, the lattice and sweep of a `@potts_model`
extension that declares them). A vector replaces the base's vector of its name as a whole and
may be longer, not shorter (the base may read the components a shorter one would drop). Structural replacement: an update of `sys` replaces the base's
updates of the same target in the same phase (whatever their cadences; a warning names a
changed cadence), an equation the base's equation for the same
variable, an observed quantity the base's of the same name. Energies, drives, constraints,
divisions, relationships and link rules accumulate, base first (a division rule for kinds
the base divides at another cadence warns: both rules apply, each at its own `Every`).
A `@schedule` of `sys` replaces the base's; a `@convert` pass of `sys` replaces the base's pass of the same
name as a whole (in the base's place). A name keeps its category: a name that is, say, a parameter of `base` and a variable of `sys`
is an `ArgumentError` naming both. An edge variable keeps its relationship too: an edge
variable of `sys` that re-declares one of `base` (to change its default) is the base
relationship's (an unscoped `x(edge)` takes it), and one scoped to another relationship is an
`ArgumentError` naming the variable and both relationships. Components (`@components`, and
the components of a `compose`
result) are merged by name: a component of `sys` replaces the base's component of the same name
as a whole. MTK's other `extend` keywords (`description`, `gui_metadata`) are an
`ArgumentError` that names them.
"""
function ModelingToolkitBase.extend(sys::PottsSystem, base::PottsSystem; name::Symbol = nameof(sys), kw...)
    isempty(kw) || throw(
        ArgumentError(
            string(
                "extend: a Potts model takes the keyword `name` only; ",
                join(("`$k`" for k in keys(kw)), ", "), " is not supported"
            )
        )
    )
    sys = _lower_inner(sys, "extend")
    base = _lower_inner(base, "extend")
    length(_p(sys, :kinds)) >= length(_p(base, :kinds)) && _p(sys, :kinds)[1:length(_p(base, :kinds))] == _p(base, :kinds) ||
        throw(ArgumentError("extend: the kinds of $(nameof(base)) $(_p(base, :kinds)) must come first in $(nameof(sys)) $(_p(sys, :kinds))"))
    sys = _renumber_draws(sys, base)
    for u in _p(sys, :updates), b in _p(base, :updates)
        _target_key(u) == _target_key(b) && u.every != b.every &&
            @warn "extend: `$(u.eq.lhs)` @$(u.phase) Every($(u.every)) replaces the base's Every($(b.every)) update"
    end
    # division rules accumulate: a rule of `sys` for kinds the base already divides at another
    # cadence adds a check, it does not replace the base's (both fire at their own MCS)
    for u in _p(sys, :divisions), b in _p(base, :divisions)
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
    # an edge variable keeps its relationship (D-127)
    svars = _inherit_edge_scope(name, inbase, _p(sys, :variables), _p(base, :variables))
    # a vector replaces the base's vector of its name as a whole, so it may not be shorter
    # (the base's statements may read the components it would drop)
    key(x) = (i = info(x); something(get(i.options, :vector, nothing), i.name))
    _check_vector_lengths(name, inbase, Iterators.flatten((_p(base, :parameters), _p(base, :variables))),
        Iterators.flatten((_p(sys, :parameters), _p(sys, :variables))))
    byname(xs, ys) = (seen = Set(key(y) for y in ys); Any[filter(x -> !(key(x) in seen), xs)..., ys...])
    # kind classes (D-135): the base's, then the extension's new ones; a restated class must
    # keep its members in order (`x ∈ g` unrolls in member order)
    classes = copy(_p(base, :kind_classes))
    for g in _p(sys, :kind_classes)
        i = findfirst(h -> h.name === g.name, classes)
        if i === nothing
            push!(classes, g)
        elseif classes[i].kinds != g.kinds
            here, there = (Tuple(get(_p(sys, :kinds), k + 1, k) for k in h.kinds) for h in (g, classes[i]))   # kind names
            throw(ArgumentError("extend: kind class `$(g.name)` is $here in $(nameof(sys)) but $there $inbase; " *
                                "restate it with the same members in the same order (the order is in the generated code), or rename it"))
        end
    end
    return PottsSystem(; name, kinds = _p(sys, :kinds), frozen_kinds = sort!(union(_p(base, :frozen_kinds), _p(sys, :frozen_kinds))),
        kind_classes = classes,
        lattice = _p(sys, :lattice), parameters = byname(_p(base, :parameters), _p(sys, :parameters)),
        variables = map(_settle_edge_scope, byname(_p(base, :variables), svars)), relations = merge(_p(base, :relations), _p(sys, :relations)),
        energies = [_p(base, :energies); _p(sys, :energies)], drives = [_p(base, :drives); _p(sys, :drives)],
        constraints = [_p(base, :constraints); _p(sys, :constraints)],
        updates = [_unreplaced(_p(base, :updates), _p(sys, :updates), _target_key); _p(sys, :updates)],
        equations = [_unreplaced(_p(base, :equations), _p(sys, :equations), eq -> string(eq.lhs)); _p(sys, :equations)],
        initialization_eqs = [_p(base, :initialization_eqs); _p(sys, :initialization_eqs)],
        divisions = [_p(base, :divisions); _p(sys, :divisions)],
        converts = _merged_converts(_p(base, :converts), _p(sys, :converts)),
        relationships = unique(r -> r.name, [_p(sys, :relationships); _p(base, :relationships)]),
        link_rules = [_p(base, :link_rules); _p(sys, :link_rules)],
        observed = [_unreplaced(_p(base, :observed), _p(sys, :observed), o -> info(o.lhs).name); _p(sys, :observed)],
        components = unique(c -> c.name, [_p(sys, :components); _p(base, :components)]),
        discrete = unique(b -> b.name, [_p(sys, :discrete); _p(base, :discrete)]),
        sweep = _p(sys, :sweep), structural = merge(_p(base, :structural), _p(sys, :structural)),
        schedule = isempty(_p(sys, :schedule)) ? _p(base, :schedule) : _p(sys, :schedule),
        sources = merge(_p(base, :sources), _p(sys, :sources)),
        bcs = [_p(base, :bcs); _p(sys, :bcs)], bindings = [_p(base, :bindings); _p(sys, :bindings)],
        metadata = _merged_metadata(base, sys))
end

# `@convert` passes (R8, D-233): a pass of the extension replaces the base's pass of its name
# as a whole, in the base's place; the extension's other passes follow, in declaration order
function _merged_converts(base, mine)
    out = ConvertSpec[get(() -> b, Dict(v.name => v for v in mine), b.name) for b in base]
    for v in mine
        any(b -> b.name === v.name, base) || push!(out, v)
    end
    return out
end

# Potts' build record (`_BuiltFeatures`): the base's entries, then the extension's, so the newest
# value of a key wins. An `ImmutableDict` iterates newest first, so each system's entries are
# re-inserted oldest first.
function _merged_metadata(base::PottsSystem, sys::PottsSystem)
    meta = Base.ImmutableDict{DataType, Any}()
    for s in (base, sys), kv in Iterators.reverse(collect(_p(s, :metadata)))
        meta = Base.ImmutableDict(meta, kv)
    end
    return meta
end

# A compiled model is not an ODE or jump system either: the same refusals as a `PottsSystem`'s
# (system.jl), so that MTK's problem constructors for an `AbstractSystem` never run on it
for (M, n) in ((:JumpProcesses, :JumpProblem), ((:SciMLBase, n) for n in _REFUSED_PROBLEMS)...)
    P = Expr(:., M, QuoteNode(n))
    msg = String(n)
    @eval begin
        $P{iip}(::CompiledPottsSystem, args...; kw...) where {iip} = throw(ArgumentError(_problem_msg($msg)))
        $P{iip, spec}(::CompiledPottsSystem, args...; kw...) where {iip, spec} = throw(ArgumentError(_problem_msg($msg)))
    end
    n === :JumpProblem || @eval $P(::CompiledPottsSystem, args...; kw...) = throw(ArgumentError(_problem_msg($msg)))
end
for T in _JUMP_TSPANS
    @eval function JumpProcesses.JumpProblem(::CompiledPottsSystem, op, tspan::$T, args...; kw...)
        throw(ArgumentError(_problem_msg("JumpProblem")))
    end
end
for T in _JUMP_OPS
    @eval JumpProcesses.JumpProblem(::CompiledPottsSystem, op::$T; kw...) = throw(ArgumentError(_problem_msg("JumpProblem")))
end
function SciMLBase.ODEProblem{iip, SciMLBase.FunctionWrapperSpecialize}(::CompiledPottsSystem, args...; kw...) where {iip}
    throw(ArgumentError(_problem_msg("ODEProblem")))
end

"""
The variables `xs` of an extension, each edge variable that re-declares one of the base's
(`bxs`) bound to that variable's relationship: an unscoped one, or one bound only because
its body had one relationship (`implicit_relationship`), takes it; one scoped to another
relationship is an `ArgumentError` (a payload column belongs to one relationship; moving it
would strip the base's terms and rules of it), and so is a re-declaration that turns an
edge variable into another scope, or another variable into an edge variable.
"""
function _inherit_edge_scope(model, inbase, xs, bxs)
    inherited = _edge_relationships(bxs)
    roles = Dict{Symbol, Symbol}()
    for x in bxs
        i = info(x)
        i === nothing || (roles[i.name] = i.role)
    end
    return map(xs) do x
        i = info(x)
        i === nothing && return x
        old = get(roles, i.name, nothing)
        (old === :edge) == (i.role === :edge) || old === nothing || throw(ArgumentError(
            "$model: `$(i.name)` is $(_scope_description(old, get(inherited, i.name, nothing))) $inbase; " *
            "re-declaring it as $(_scope_description(i.role, get(i.options, :relationship, nothing))) would change " *
            "its scope (an edge variable's values live on links); keep its scope or choose another name"))
        (i.role === :edge && haskey(inherited, i.name)) || return x
        rb = inherited[i.name]
        r = get(i.options, :relationship, nothing)
        if r === nothing || get(i.options, :implicit_relationship, false) === true
            opts = _without_implicit(i.options)
            return _tag(x, Entity(:edge, i.name, i.default, (; opts..., relationship = rb)))
        end
        r === rb || throw(ArgumentError("$model: `$(i.name)` is an edge variable of relationship `$rb` $inbase; " *
            "re-declaring it as `$(i.name)($r)` would move it to relationship `$r`. Re-declare it as " *
            "`$(i.name)($rb)` or `$(i.name)(edge)`, or give the `$r` variable another name"))
        return x
    end
end
"""
`x′` is the contact-pair value of a site or field variable `x`: no quantity of the system
(parameter, variable or observed quantity, inherited through `@extend` or not) may carry
that name as well. Checked whenever a `PottsSystem` is constructed (`@potts_model`,
`extend` or a programmatic build).
"""
function _check_primed_names(sys::PottsSystem)
    names = Set{Symbol}()
    for x in Iterators.flatten((_p(sys, :parameters), _p(sys, :variables), (o.lhs for o in _p(sys, :observed))))
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
    foreach(k -> claim(k, "kind"), _p(sys, :kinds))
    foreach(g -> claim(g.name, "kind class"), _p(sys, :kind_classes))
    for (what, xs) in (("parameter", _p(sys, :parameters)), ("variable", _p(sys, :variables)))
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
    foreach(o -> (i = info(o.lhs); i === nothing || claim(i.name, "observed quantity")), _p(sys, :observed))
    foreach(k -> k === :contact || claim(k, "relation"), keys(_p(sys, :relations)))
    foreach(r -> claim(r.name, "relationship"), _p(sys, :relationships))
    for c in _p(sys, :components)
        claim(c.name, "component")
        for u in Iterators.flatten((ModelingToolkitBase.unknowns(c.system), ModelingToolkitBase.parameters(c.system)))
            claim(Symbol(c.name, :₊, SymbolicIndexingInterface.getname(u)), "quantity of the component `$(c.name)`")
        end
    end
    return seen
end

"""Reject a vector of `mine` with fewer components than the base's vector of its name."""
function _check_vector_lengths(model, inbase, theirs, mine)
    function components(xs)
        out = Dict{Symbol, Vector{Symbol}}()
        for x in xs
                i = info(x)
                v = i === nothing ? nothing : get(i.options, :vector, nothing)
                v === nothing || push!(get!(out, v, Symbol[]), i.name)
            end
        return out
    end
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
function _labelled(what, n)
    i = findfirst(" (", what)
    return if i === nothing
            "$what `$n`"
        else
            "$(what[1:prevind(what, first(i))]) `$n`$(what[first(i):end])"
        end
end

function _category_clash(model, n, what, old)
    return ArgumentError(
        "$model: $(_labelled(what, n)): `$n` is already declared as $(_with_article(old)) (kinds, parameters, variables, " *
        "observed quantities, relations, relationships and components share one namespace); rename one of them")
end

_kinds_overlap(a, b) = isempty(a.kinds) || isempty(b.kinds) || !isempty(intersect(a.kinds, b.kinds))

"""Items of `base` whose key no item of `new` shares."""
_unreplaced(base, new, key) = (keys = Set(key(x) for x in new); filter(x -> !(key(x) in keys), base))
"""What an update writes: its phase and target (`x`, `act[target]`, …). An extension's update
replaces the base's whatever their cadences."""
_target_key(u::Update) = (u.phase, string(u.eq.lhs))

# Draws are numbered per model (`random_uniform(k)`); two separately built models both start
# at 1, so the extension's draws move past the base's to keep their streams independent.
function _draw_indices(xs)
    out = Int[]
    foreach(x -> _walk_all(y -> (iscall(y) && operation(y) === random_uniform &&
        push!(out, Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[1]))))), x), xs)
    return out
end
function _random_exprs(s::PottsSystem)
    return Any[(u.eq.rhs for u in _p(s, :updates))..., (eq.rhs for eq in _p(s, :equations))...,
        (d.when for d in _p(s, :divisions))..., (r for d in _p(s, :divisions) for (_, r) in d.rules)..., (r.when for r in _p(s, :link_rules))...,
        (x for b in _p(s, :discrete) for x in b.next)...]
end
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
    return _replace(sys; merge(m, (; sources = merge(_p(sys, :sources), m.sources)))...)
end


"""
    lookup(sys::PottsSystem, name::Symbol)

The quantity called `name` in a model: a parameter, variable, observed quantity, kind
(its number), relation or relationship; `x′` for a site or field variable `x` is its value
at the other site of a contact pair. `@extend` binds names with it.
"""
function lookup(sys::PottsSystem, name::Symbol)
    x = _lookup_primed(sys, name)
    x === nothing || return x
    for x in Iterators.flatten((_p(sys, :parameters), _p(sys, :variables)))
        info(x).name === name && return x
    end
    for o in _p(sys, :observed)
        info(o.lhs).name === name && return Symbolics.wrap(o.lhs)
    end
    # a vector quantity: its components (tagged `vector = name`) in order (A-37)
    comps = [x for x in Iterators.flatten((_p(sys, :parameters), _p(sys, :variables))) if get(info(x).options, :vector, nothing) === name]
    isempty(comps) || return QuantityVector(name, Num[Symbolics.wrap(x) for x in sort!(comps; by = x -> info(x).options.index)])
    k = findfirst(==(name), _p(sys, :kinds))
    k === nothing || return k - 1
    g = findfirst(h -> h.name === name, _p(sys, :kind_classes))
    g === nothing || return _p(sys, :kind_classes)[g]
    haskey(_p(sys, :relations), name) && return RelationRef(name)
    any(r -> r.name === name, _p(sys, :relationships)) && return RelationshipRef(name)
    throw(ArgumentError("$(nameof(sys)) has no parameter, variable, kind, kind class or relation `$name`"))
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
        _p(sys, :variables))
end
