# `mtkcompile(sys::PottsSystem)`: validate the model, derive the energy change of a copy
# from the authored Hamiltonian, and decide trackers, relations and the footprint.
# The result is still symbolic; `codegen.jl` lowers it for a scalar type.

"""
    CompiledPottsSystem

A `PottsSystem` after `mtkcompile`: energy terms classified by domain with their derived
copy deltas, the trackers and relations the model needs, and its footprint.
"""
struct CompiledPottsSystem
    sys::PottsSystem
    cell_terms::Vector{Tuple{Vector{Int}, Any}}       # (kinds, E) with E in volume/surface/…
    cluster_terms::Vector{Tuple{Vector{Int}, Any}}    # (root kinds, E) with E in cluster_volume/…
    contact_terms::Dict{Symbol, Any}                  # relation name → symmetrized pair energy
    site_terms::Vector{Any}
    drive::Any                                        # sum of drives (proposal scope)
    constraints::Vector{Constraint}
    updates::Dict{Tuple{Symbol, Symbol}, Vector{Update}}   # (phase, scope) → updates
    fields::Vector{Tuple{Any, Any}}                   # (field variable, rate)
    cell_odes::Vector{Tuple{Any, Any}}                # (cell variable, rate)
    model_odes::Vector{Tuple{Any, Any}}               # (model variable, rate)
    divisions::Vector{DivideRule}
    relationships::Vector{RelationshipSpec}           # in declaration order (P6.0b)
    edge_terms::Vector{Tuple{Symbol, Any}}            # (relationship, E(a, b, distance, its edge vars))
    edge_vars::Dict{Symbol, Vector{Any}}              # relationship → its edge variables
    link_rules::Vector{LinkRule}
    uses_surface::Bool
    uses_clusters::Bool                               # `st.cell.cluster` and `cluster_volume`
    uses_cluster_surface::Bool
    cluster_division::Bool
    needs_moments::Bool
    relations::Dict{Symbol, Any}                      # ctx relation name → spec (excl. contact)
    contact_spec::Any
    proposal_spec::Any                                # `@relations proposal = …`, or `VonNeumann(1)`
    gather_names::Dict{Any, Symbol}
    footprint::Footprint
    scratch::Set{Symbol}                              # field variables (double-buffered steps)
    schedule::Dict{Symbol, Vector{Stage}}             # :before_mcs/:after_mcs → ordered stages (D-042)
    pre_snapshots::Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}   # block → (scope, x) copied to x__pre
    update_pops::Vector{Pair{Symbol, Any}}            # model slots of folds hoisted from updates and integrals
    energy_snapshots::Vector{Pair{Symbol, Any}}       # model slots of folds in energies (D-041)
    cell_ode_pops::Vector{Pair{Symbol, Any}}          # model slots of folds in cell ODEs
    discrete::Vector{DiscreteBlock}                   # discrete components' ticks (P6.0k), folds hoisted
    discrete_pops::Vector{Pair{Symbol, Any}}          # model slots of folds in cell-scope ticks
end

Base.nameof(c::CompiledPottsSystem) = nameof(c.sys)

const _CELL_ENERGY_BUILTINS = (:volume, :surface, :kind, :id, :generation, :cluster, :major_length)
# cell updates, division rules (cluster trackers change with copies of other members, so
# they are readable here but not in cell energies)
const _CELL_BUILTINS = (_CELL_ENERGY_BUILTINS..., :mcs, :cluster_volume, :cluster_surface)
const _CLUSTER_BUILTINS = (:cluster_volume, :cluster_surface, :kind, :id)
const _CONTACT_BUILTINS = (:kind, :kind′, :owner, :owner′, :weight, :site′)   # `site′`: from `x′`
const _SITE_BUILTINS = (:owner, :kind, :position, :site, :mcs)
const _PROPOSAL_BUILTINS = (:source, :target, :old, :new, :local_components, :ring_arcs, :ring_cells, :ring_medium)
const _EDGE_BUILTINS = (:a, :b, :distance)
const _LINK_BUILTINS = (:a, :b, :distance, :mcs)

# Replace population folds by placeholders; return them for separate checking.
function _strip_populations(x)
    pops = Any[]
    _walk(y -> (iscall(y) && operation(y) === population && push!(pops, y)), x)
    isempty(pops) && return x, pops
    return Symbolics.substitute(x, Dict{Any, Any}(p => 0 for p in pops); fold = Val(false)), pops
end

# Built-in names used bare (not as the array of an explicit index like `kind[new]`).
function _bare_builtins(x, out = Set{Symbol}())
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return out
    i = info(x)
    i !== nothing && i.role === :builtin && push!(out, i.name)
    if iscall(x) && !(i !== nothing && i.role in SCOPES)
        args = arguments(x)
        skip = operation(x) === at || operation(x) === at2
        for (j, a) in enumerate(args)
            (skip && j == 1) || _bare_builtins(a, out)
        end
    end
    return out
end

const _INDEXABLE = (:owner, :kind, :volume, :surface, :generation, :cluster)

# names a user can write (`site′` only arises from `x′`)
_visible(names) = filter(!=(:site′), collect(names))

# `between_copies`: `x` is evaluated between copy attempts (updates, divisions, equations),
# not inside ΔH, so population bodies may read cluster trackers.
function _check_names(x, allowed, what; between_copies::Bool = false)
    x, pops = _strip_populations(x)
    for p in pops                                  # population bodies have their own scope
        n, body, cond = arguments(p)
        inner = info(n).role !== :bound_cell ? _SITE_BUILTINS :
                between_copies ? (_CELL_ENERGY_BUILTINS..., :cluster_volume, :cluster_surface) : _CELL_ENERGY_BUILTINS
        _check_names(body, (allowed..., inner...), what; between_copies)
        _check_names(cond, (allowed..., inner...), what; between_copies)
    end
    for n in _bare_builtins(x)
        n === :site′ && !(n in allowed) &&
            throw(ArgumentError("a primed site variable `x′` (its value at the pair's other site) is only available in contact terms, not in $what"))
        n in allowed || throw(ArgumentError("`$n` is not available in $what (available: $(join(_visible(allowed), ", ")); index `owner`, `kind`, `volume` explicitly, e.g. `kind[new]`)"))
    end
    for (r, n) in _uses(x)
        r === :builtin && !(n in allowed) && !(n in _INDEXABLE) &&
            throw(ArgumentError("`$n` is not available in $what (available: $(join(_visible(allowed), ", ")))"))
    end
    return nothing
end

# Relationships (P6.0b): names are unique; each edge variable belongs to one relationship,
# named by its scope (`rest(bond)`) or, with a single relationship, `rest(edge)`.
function _relationships(sys::PottsSystem)
    rels = sys.relationships
    names = [r.name for r in rels]
    for (i, n) in enumerate(names)
        n in view(names, 1:(i - 1)) && throw(ArgumentError("@relationship `$n` is declared twice"))
        n in SCOPES && throw(ArgumentError("@relationship `$n`: the name is a variable scope " *
                                           "($(join(SCOPES, ", "))); choose another"))
    end
    edge_vars = Dict{Symbol, Vector{Any}}(n => Any[] for n in names)
    edge_rel = Dict{Symbol, Symbol}()                 # edge variable name → relationship
    for x in sys.variables
        i = info(x)
        i.role === :edge || continue
        r = get(i.options, :relationship, nothing)
        if r === nothing
            isempty(names) && throw(ArgumentError("edge variable `$(i.name)` needs a @relationship"))
            length(names) == 1 || throw(ArgumentError(
                "edge variable `$(i.name)(edge)` is ambiguous: the model has relationships " *
                "$(join(names, ", ")); name one as its scope, e.g. `$(i.name)($(first(names)))`"))
            r = only(names)
        else
            r in names || throw(ArgumentError(
                "variable `$(i.name)($r)`: `$r` is neither a scope ($(join(SCOPES, ", "))) nor a @relationship" *
                (isempty(names) ? "" : " (the model has $(join(names, ", ")))")))
        end
        edge_rel[i.name] = r
        push!(edge_vars[r], x)
    end
    return rels, edge_vars, edge_rel
end

# An edge term or link rule of relationship `r` reads only `r`'s edge variables (another
# relationship's payload has no slot for this link).
function _check_edge_vars(x, r, edge_rel, what)
    for (role, n) in _uses(x)
        role === :edge && edge_rel[n] !== r && throw(ArgumentError(
            "$what reads `$n`, an edge variable of relationship `$(edge_rel[n])`"))
    end
    return nothing
end

"""
    mtkcompile(sys::PottsSystem) -> CompiledPottsSystem

Validate and analyse a Potts model (the symbolic half of compilation; code is generated
per scalar type by `PottsProblem`).
"""
function ModelingToolkitBase.mtkcompile(sys::PottsSystem)
    sys = _bind_components(sys)
    _check_discrete_slots(sys)
    cell_terms = Tuple{Vector{Int}, Any}[]
    cluster_terms = Tuple{Vector{Int}, Any}[]
    contact_terms = Dict{Symbol, Any}()
    site_terms = Any[]
    edge_terms = Tuple{Symbol, Any}[]
    relationships, edge_vars, edge_rel = _relationships(sys)
    for e in sys.energies
        d = e.domain
        _located(sys, e) do
        if d isa CellDomain
            0 in d.kinds && throw(ArgumentError("cells(…) cannot include the medium kind"))
            _check_names(e.expr, _CELL_ENERGY_BUILTINS, "a cell term")
            push!(cell_terms, (_all_kinds(sys, d.kinds), e.expr))
        elseif d isa ClusterDomain
            0 in d.kinds && throw(ArgumentError("clusters(…) cannot include the medium kind"))
            _check_names(e.expr, _CLUSTER_BUILTINS, "a cluster term")
            isempty(_gathers(e.expr)) || throw(ArgumentError("cluster terms reading neighbours are not supported"))
            push!(cluster_terms, (_all_kinds(sys, d.kinds), e.expr))
        elseif d isa ContactDomain
            _check_names(e.expr, _CONTACT_BUILTINS, "a contact term")
            _check_static(_strip_populations(e.expr)[1], "a contact term")
            E = _symmetrize(_cellvars_at_owner(e.expr))
            contact_terms[d.relation] = haskey(contact_terms, d.relation) ? contact_terms[d.relation] + E : E
        elseif d isa EdgeDomain
            haskey(edge_vars, d.relationship) ||
                throw(ArgumentError("edges($(d.relationship)): no @relationship $(d.relationship)"))
            _check_names(e.expr, _EDGE_BUILTINS, "an edge term")
            _check_static(_strip_populations(e.expr)[1], "an edge term")
            _check_edge_vars(e.expr, d.relationship, edge_rel, "edges($(d.relationship))")
            push!(edge_terms, (d.relationship, e.expr))
        elseif d isa SiteDomain
            _check_names(e.expr, _SITE_BUILTINS, "a site term")
            _check_static(_strip_populations(e.expr)[1], "a site term")
            isempty(_gathers(e.expr)) || throw(ArgumentError("site terms reading neighbours are not supported yet"))
            push!(site_terms, e.expr)
        else
            throw(ArgumentError("unknown energy domain $d"))
        end
        end
    end
    # energies may read on-copy-written variables only where ΔH can apply the write (D-045):
    # cell terms at the written cell (`x[new]`, `x[old]`), site and contact terms (`x`, `x′`)
    # at the target
    for u in sys.updates
        u.phase === :on_copy || continue
        lhs = _unwrap(u.eq.lhs)
        (iscall(lhs) && operation(lhs) === at) || continue
        x, idx = arguments(lhs)
        i = info(x)
        i === nothing && continue
        readers = Any[(E for (_, E) in cluster_terms)..., last.(edge_terms)...,
            (i.role === :cell ? (site_terms..., values(contact_terms)...) : last.(cell_terms))...]
        ok = _oncopy_side(i, idx) !== nothing
        if !ok
            readers = Any[readers..., last.(cell_terms)..., site_terms..., values(contact_terms)...]
        end
        any(E -> any(==((i.role, i.name)), _uses(E)), readers) && _located(sys, u) do
            throw(ArgumentError("an energy reads `$(i.name)`, which this on-copy update writes; ΔH applies the " *
                                "write only for cell terms reading `$(i.name)[new]`/`[old]`, and site and contact terms " *
                                "reading a site variable written at the target"))
        end
    end
    drive = isempty(sys.drives) ? nothing : sum(d -> d.expr, sys.drives)
    for d in sys.drives
        _located(() -> _check_names(d.expr, _PROPOSAL_BUILTINS, "a drive"), sys, d)
    end
    for c in sys.constraints
        c.kind === :expr && _located(() -> _check_names(c.expr, _PROPOSAL_BUILTINS, "a constraint"), sys, c)
    end

    # updates by phase and scope
    updates = Dict{Tuple{Symbol, Symbol}, Vector{Update}}()
    for u in sys.updates
        lhs = _unwrap(u.eq.lhs)
        scope = _located(sys, u) do
        if u.phase === :on_copy
            (iscall(lhs) && operation(lhs) === at) || throw(ArgumentError("@on_copy updates assign at a site or cell, e.g. `act[target] ~ …`"))
            u.every == 1 || throw(ArgumentError("`Every` does not apply to @on_copy updates: they run at every accepted copy"))
            _check_names(u.eq.rhs, _PROPOSAL_BUILTINS, "an on-copy update")
            :proposal
        else
            i = info(lhs)
            (i !== nothing && i.role in SCOPES) || throw(ArgumentError("update target `$lhs` is not a declared variable"))
            allowed = i.role === :cell ? _CELL_BUILTINS : i.role === :model ? (:mcs,) : _SITE_BUILTINS
            _check_names(u.eq.rhs, allowed, "a $(i.role) update"; between_copies = true)
            i.role === :field ? :site : i.role
        end
        end
        push!(get!(updates, (u.phase, scope), Update[]), u)
    end

    # differential equations: fields (lattice PDEs) and per-cell ODEs
    fields = Tuple{Any, Any}[]
    cell_odes = Tuple{Any, Any}[]
    model_odes = Tuple{Any, Any}[]
    derivatives = Dict{Symbol, Any}()
    for eq in sys.equations
        _located(sys, eq) do
        lhs = _unwrap(eq.lhs)
        (iscall(lhs) && operation(lhs) isa Differential) ||
            throw(ArgumentError("equations are `D(x) ~ rhs`; got $eq"))
        x = arguments(lhs)[1]
        i = info(x)
        i === nothing && throw(ArgumentError("`$x` is not a declared variable"))
        haskey(derivatives, i.name) && throw(ArgumentError(
            "`D($(i.name))` is already given by `$(derivatives[i.name])`; one equation per variable (add the terms)"))
        derivatives[i.name] = eq
        if i.role === :field || i.role === :site
            _check_names(eq.rhs, _SITE_BUILTINS, "a field equation"; between_copies = true)
            push!(fields, (x, eq.rhs))
        elseif i.role === :cell
            _check_names(eq.rhs, (_CELL_BUILTINS..., :time), "a cell equation"; between_copies = true)
            push!(cell_odes, (x, eq.rhs))
        elseif i.role === :model
            _check_names(eq.rhs, (:mcs, :time), "a model equation"; between_copies = true)
            push!(model_odes, (x, eq.rhs))
        else
            throw(ArgumentError("equations are for field, site, cell and model variables; `$x` is $(i.role)"))
        end
        end
    end
    for d in sys.divisions
        _located(() -> _check_names(d.when, _CELL_BUILTINS, "a division condition"; between_copies = true),
            sys, d)
    end
    # each rule divides by its own domain (P6.0a); a kind is divided by one domain only
    cluster_division = any(d -> d.domain isa ClusterDomain, sys.divisions)
    domain_kinds(D) = unique(Iterators.flatten(isempty(d.domain.kinds) ? (1:(length(sys.kinds) - 1)) : d.domain.kinds
                                               for d in sys.divisions if d.domain isa D))
    both = intersect(domain_kinds(CellDomain), domain_kinds(ClusterDomain))
    isempty(both) || throw(ArgumentError("kind$(length(both) == 1 ? "" : "s") " *
                                         join(("`$(sys.kinds[k + 1])`" for k in sort(both)), ", ") *
                                         " divided by both @divide cells(…) and @divide clusters(…); a kind divides alone or with its cluster, not both"))
    for r in sys.link_rules
        _located(sys, r) do
            haskey(edge_vars, r.relationship) ||
                throw(ArgumentError("@$(r.action) $(r.relationship): no @relationship $(r.relationship)"))
            _check_names(r.when, _LINK_BUILTINS, "a link rule"; between_copies = true)
            _check_edge_vars(r.when, r.relationship, edge_rel, "@$(r.action) $(r.relationship)")
        end
    end

    # discrete components (P6.0k): a tick reads the pre-tick state, between copies
    for b in sys.discrete
        _located(sys, b) do
            for x in b.next
                _check_names(x, b.scope === :cell ? _CELL_BUILTINS : (:mcs,), "a discrete component"; between_copies = true)
            end
        end
    end
    tick_exprs = Any[x for b in sys.discrete for x in b.next]

    # one writer per target, phase and cadence (combine contributions with `+=`)
    writers = Dict{Any, Update}()
    for u in sys.updates
        k = (_target_key(u)..., u.every)
        haskey(writers, k) && _located(sys, u) do
            throw(ArgumentError("`$(u.eq.lhs)` is already written @$(u.phase)$(u.every == 1 ? "" : " Every($(u.every))") " *
                                "by `$(writers[k].eq)`; combine contributions with `+=` or in one equation"))
        end
        writers[k] = u
    end
    geometric(x) = _has_op(x, cell_centroid) || _has_op(x, copy_displacement) || _uses_builtin(x, :major_length)
    needs_moments = !isempty(sys.divisions) || !isempty(relationships) ||
                    any(geometric, Any[(e.expr for e in sys.energies)..., (d.expr for d in sys.drives)...,
                        (u.eq.rhs for u in sys.updates)..., (eq.rhs for eq in sys.equations)...,
                        (o.expr for o in sys.observed)..., (c.expr for c in sys.constraints if c.kind === :expr)...,
                        (r.when for r in sys.link_rules)..., sys.sweep.temperature,
                        (r for d in sys.divisions for (_, r) in d.rules if !(r isa Split))..., tick_exprs...])

    # relations: contact (ctx.contact), surface, named, gathers
    contact_spec = get(sys.relations, :contact, sys.lattice.neighborhood)
    proposal_spec = get(sys.relations, :proposal, CorePotts.VonNeumann(1))
    relations = Dict{Symbol, Any}()
    for (k, v) in sys.relations
        k in (:contact, :proposal) || (relations[k] = v)
    end
    for r in keys(contact_terms)
        r === :contact || haskey(relations, r) || throw(ArgumentError("contacts($r): relation `$r` is not declared in @relations"))
    end
    gather_names = Dict{Any, Symbol}()
    all_exprs = Any[last.(cell_terms)..., last.(cluster_terms)..., values(contact_terms)..., site_terms...,
        (drive === nothing ? () : (drive,))..., (c.expr for c in sys.constraints if c.kind === :expr)...,
        (u.eq.rhs for u in sys.updates)..., (last(f) for f in fields)..., (last(f) for f in cell_odes)..., (last(f) for f in model_odes)...,
        sys.sweep.temperature, tick_exprs...]
    # everything evaluated against the state, including division rules, observed quantities
    # and link rules: every tracker flag scans the same set (A-35)
    scanned = Any[all_exprs..., (d.when for d in sys.divisions)...,
        (r for d in sys.divisions for (_, r) in d.rules if !(r isa Split))..., (o.expr for o in sys.observed)...,
        (r.when for r in sys.link_rules)...]
    uses_surface = any(x -> _uses_builtin(x, :surface), scanned)
    uses_cluster_surface = any(x -> _uses_builtin(x, :cluster_surface), scanned)
    uses_clusters = cluster_division || uses_cluster_surface ||
                    any(x -> _uses_builtin(x, :cluster) || _uses_builtin(x, :cluster_volume), scanned)
    (uses_surface || uses_cluster_surface) && !haskey(relations, :surface) &&
        (relations[:surface] = sys.lattice.neighborhood)
    radius_read = 1
    # gather relations numbered in statement order and, within one, by content (D-107)
    for x in all_exprs
        specs = unique!(Any[ni.options.relation for (ni, _) in _gathers(x)
                            if !(ni.options.relation isa RelationRef) && !haskey(gather_names, ni.options.relation)])
        for spec in specs[sortperm(map(_canonical_value, specs))]
            gather_names[spec] = Symbol(:gather, length(gather_names) + 1)
            relations[gather_names[spec]] = spec
        end
    end

    # footprint: largest distance from the target read by the per-copy functions
    lat = core_lattice(sys.lattice)
    rad(spec) = CP.radius(CP.relation(spec, lat))
    isempty(contact_terms) || (radius_read = max(radius_read, maximum(r -> rad(r === :contact ? contact_spec : relations[r]), keys(contact_terms))))
    (uses_surface || uses_cluster_surface) && (radius_read = max(radius_read, rad(relations[:surface])))
    # per-copy reads anchored at the target count from it; at the source, from the source
    # (CorePotts adds the proposal radius: `reach`)
    source_read = -1
    source_write = -1
    oncopy = get(updates, (:on_copy, :proposal), Update[])
    for x in Any[(drive === nothing ? () : (drive,))..., (c.expr for c in sys.constraints if c.kind === :expr)...,
            (u.eq.rhs for u in oncopy)..., sys.sweep.temperature]
        for (ni, anchor) in _gathers(x)
            spec = ni.options.relation
            r = rad(spec isa RelationRef ? sys.relations[spec.name] : spec)
            if _uses_builtin(anchor, :source)
                source_read = max(source_read, r)
            else
                radius_read = max(radius_read, r)
            end
        end
    end
    for u in oncopy                                  # `act[source] ~ …` writes at the source
        idx = arguments(_unwrap(u.eq.lhs))[2]
        _uses_builtin(idx, :source) && (source_write = max(source_write, 0))
    end

    # fields step double-buffered; synchronous updates read previous values from snapshots
    scratch = Set{Symbol}(info(x).name for (x, _) in fields)

    # population folds: snapshots in energies (D-041), hoisted from updates and cell ODEs
    energy_snapshots = Pair{Symbol, Any}[]
    snap(x) = _hoist_populations(x, energy_snapshots, gather_names, :__snap; strict = true)
    cell_terms = [(k, snap(E)) for (k, E) in cell_terms]
    cluster_terms = [(k, snap(E)) for (k, E) in cluster_terms]
    contact_terms = Dict{Symbol, Any}(r => snap(E) for (r, E) in contact_terms)
    site_terms = Any[snap(E) for E in site_terms]
    edge_terms = Any[snap(E) for E in edge_terms]
    update_pops = Pair{Symbol, Any}[]
    schedule = Dict{Symbol, Vector{Stage}}()
    pre_snapshots = Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}()
    for ph in (:before_mcs, :after_mcs)
        schedule[ph], pre_snapshots[ph] = _schedule_block(sys, Update[u for u in sys.updates if u.phase === ph],
            gather_names, update_pops)
    end
    # folds hoisted out of integral operands: model slots too, computed by the integrals' refresh
    for fs in last(_integrals_folds(sys; observed = true)), sl in fs
        any(q -> q.first === sl.first, update_pops) || push!(update_pops, sl)
    end
    cell_ode_pops = Pair{Symbol, Any}[]
    cell_odes = Tuple{Any, Any}[(x, _hoist_populations(r, cell_ode_pops, gather_names, :__odepop)) for (x, r) in cell_odes]
    # folds in a cell-scope tick are computed once per tick, before it (as for cell ODEs)
    discrete_pops = Pair{Symbol, Any}[]
    discrete = DiscreteBlock[b.scope === :cell ?
                             DiscreteBlock(b.name, b.scope, b.kinds, b.slots,
        Any[_hoist_populations(x, discrete_pops, gather_names, :__tickpop) for x in b.next], b.every, b.offset) : b
                             for b in sys.discrete]

    _dry_lower(sys, gather_names, fields, cell_odes)
    _check_units(sys)

    return CompiledPottsSystem(sys, cell_terms, cluster_terms, contact_terms, site_terms, drive,
        sys.constraints, updates, fields, cell_odes, model_odes, sys.divisions, relationships, edge_terms, edge_vars,
        sys.link_rules, uses_surface, uses_clusters, uses_cluster_surface, cluster_division,
        needs_moments, relations, contact_spec, proposal_spec, gather_names,
        Footprint(; read = radius_read, source_read, source_write),
        scratch, schedule, pre_snapshots, update_pops, energy_snapshots, cell_ode_pops, discrete, discrete_pops)
end

# A slot of a discrete component is written by its ticks only.
function _check_discrete_slots(sys)
    isempty(sys.discrete) && return nothing
    slots = Dict{Symbol, Symbol}(info(x).name => b.name for b in sys.discrete for x in b.slots)
    target(lhs) = (x = _standin_var(lhs);
        iscall(x) && (operation(x) === at || operation(x) isa Differential) ? _standin_var(arguments(x)[1]) : x)
    for s in Iterators.flatten((sys.updates, sys.equations))
        lhs = _unwrap(s isa Update ? s.eq.lhs : s.lhs)
        i = info(target(lhs))
        (i !== nothing && haskey(slots, i.name)) || continue
        _located(sys, s) do
            throw(ArgumentError("`$(i.name)` is a node of the discrete component `$(slots[i.name])`: only its ticks " *
                                "write it (no updates or equations for it)"))
        end
    end
    return nothing
end

# A kind filter naming every cell kind is no filter (the generated code skips the test).
_all_kinds(sys::PottsSystem, kinds) = sort(unique(kinds)) == 1:(length(sys.kinds) - 1) ? Int[] : kinds

# Quantities a copy changes cannot appear in contact, site or edge terms: their deltas are
# derived only for cell terms.
function _check_static(x, what)
    for n in (:volume, :surface, :cluster_volume, :cluster_surface)
        _uses_builtin(x, n) && throw(ArgumentError("`$n` changes with the copy; it can only appear in cell terms, not in $what"))
    end
    return nothing
end

# In a contact term a bare cell variable means its value at the owner (`x[owner]`) and a
# bare site variable its value at the pair's first site (`x[site]`; `x′` is `x[site′]`), so
# that mirroring (owner ↔ owner′, site ↔ site′) sees them.
function _cellvars_at_owner(E)
    sub = Dict{Any, Any}()
    for x in _bare_vars(E)
        i = info(x)
        i.role === :cell && (sub[x] = _unwrap(at(Symbolics.wrap(x), B.owner)))
        i.role in (:site, :field) && (sub[x] = _unwrap(at(Symbolics.wrap(x), B.site)))
    end
    isempty(sub) && return E
    return Symbolics.substitute(E, sub; fold = Val(false), filterer = _pair_scope)
end
_not_indexed(ex) = !(iscall(ex) && (operation(ex) === at || operation(ex) === at2)) &&
                   SymbolicUtils.default_substitute_filter(ex)
# the pair's names, not inside a population fold (its body reads the bound cell or site)
_outside_population(ex) = !(iscall(ex) && operation(ex) === population) && SymbolicUtils.default_substitute_filter(ex)
_pair_scope(ex) = _not_indexed(ex) && _outside_population(ex)

# Scoped variables used bare (not as the array of `x[i]`).
function _bare_vars(x, out = Set{Any}())
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return out
    i = info(x)
    if i !== nothing && i.role in SCOPES
        push!(out, x)
        return out
    end
    if iscall(x)
        skip = operation(x) === at || operation(x) === at2
        for (j, a) in enumerate(arguments(x))
            (skip && j == 1) || _bare_vars(a, out)
        end
    end
    return out
end

function _leaves(x)
    out = Any[]
    _walk(y -> (info(y) !== nothing && push!(out, y)), x)
    return out
end

# Contact energies are summed over unordered pairs; an asymmetric expression is averaged
# with its mirror (kind ↔ kind′, owner ↔ owner′, site ↔ site′).
# Kind tables used in contact terms must be symmetric (checked against their values when the
# problem is built), so their entries are compared up to index order.
function _symmetrize(E)
    swap = Dict(_unwrap(B.kind) => _unwrap(B.kind′), _unwrap(B.kind′) => _unwrap(B.kind),
        _unwrap(B.owner) => _unwrap(B.owner′), _unwrap(B.owner′) => _unwrap(B.owner),
        _unwrap(B.site) => _unwrap(B.site′), _unwrap(B.site′) => _unwrap(B.site))
    M = Symbolics.substitute(E, swap; fold = Val(false), filterer = _outside_population)
    flips = Dict{Any, Any}()
    _walk(M) do y
        if iscall(y) && operation(y) === at2 && role(arguments(y)[1]) === :kindtable
            J, a, b = arguments(y)
            flips[y] = _unwrap(at2(Symbolics.wrap(J), Symbolics.wrap(b), Symbolics.wrap(a)))
        end
    end
    M = isempty(flips) ? M : Symbolics.substitute(M, flips; fold = Val(false))
    return isequal(Symbolics.simplify(E - M), 0) ? E : (E + M) / 2
end

"""Kind tables referenced by contact terms (their values must be symmetric)."""
function _contact_tables(c::CompiledPottsSystem)
    out = Set{Symbol}()
    for E in values(c.contact_terms)
        _walk(y -> (role(y) === :kindtable && push!(out, info(y).name)), E)
    end
    return out
end

# Copy delta of a cell (or cluster) term for one side: E(q + δq) − E(q), expanded when that
# is cheaper.
function _cell_delta(E, dv::Int; after = Dict{Any, Any}())
    sub = Dict{Any, Any}(_unwrap(B.volume) => B.volume + dv, _unwrap(B.surface) => B.surface + DSURFACE,
        _unwrap(B.cluster_volume) => B.cluster_volume + dv,
        _unwrap(B.cluster_surface) => B.cluster_surface + DCSURFACE, _unwrap(B.major_length) => DMAJOR, after...)
    naive = Symbolics.substitute(E, sub; fold = Val(false)) - E
    # `expand` rebuilds the arguments of opaque (registered) functions, which would strip the
    # metadata of scoped variables `x(t)` inside them: expand over placeholders instead
    hide, show = Dict{Any, Any}(), Dict{Any, Any}()
    _walk(naive) do y
        i = info(y)
        if i !== nothing && i.role in SCOPES && !haskey(hide, y)
            p = _sym(Symbol(:__scoped_, length(hide) + 1))
            hide[y] = p
            show[p] = y
        end
    end
    expanded = Symbolics.expand(isempty(hide) ? naive : Symbolics.substitute(naive, hide; fold = Val(false)))
    isempty(show) || (expanded = Symbolics.substitute(expanded, show; fold = Val(false)))
    return _nops(expanded) <= _nops(naive) ? expanded : naive
end
function _nops(x)
    n = Ref(0)
    _walk(y -> (iscall(y) && (n[] += 1)), x)
    return n[]
end

# ---------------------------------------------------------------------------------------
# Diagnostics: errors name the offending statement and where it was written

_source!(d, x, ln) = (ln isa LineNumberNode && (d[x] = ln); x)

"""Run `f()`; an error it raises is re-raised naming statement `x` and its source line."""
function _located(f, sys::PottsSystem, x)
    try
        return f()
    catch e
        e isa Union{ArgumentError, ErrorException} || rethrow()
        occursin("\n  in ", e.msg) && rethrow()
        ln = get(sys.sources, x, nothing)
        loc = ln === nothing ? "" : " at $(ln.file):$(ln.line)"
        throw(ArgumentError("$(e.msg)\n  in $(_describe(x))$loc"))
    end
end

# descriptions are built only when reporting (printing symbolic expressions is slow)
_describe(e::EnergyTerm) = "@energy $(_domain_string(e.domain)) => $(e.expr)"
_describe(d::Drive) = "@drive copy => $(d.expr)"
_describe(c::Constraint) = "@constraint $(c.expr)"
_describe(u::Update) = "@$(u.phase) $(u.eq)"
_describe(eq::Equation) = "@equations $eq"
_describe(d::DivideRule) = "@divide $(_domain_string(d.domain))$(_cadence_string(d.every)) when = $(d.when)"
_cadence_string(n) = n == 1 ? "" : " Every($n)"
_describe(r::LinkRule) = "@$(r.action) $(r.relationship)$(_cadence_string(r.every)) when = $(r.when)"
_describe(o::ObservedEq) = "@observed $(o.var) ~ $(o.expr)"
_describe(b::DiscreteBlock) = "@components $(b.scope === :model ? "model" : "cells") $(b.name) (discrete)"

# Lower every statement once, in the scope it will be generated in, so errors that lowering
# finds (a site variable without a site, a cell variable indexed by a site, …) surface at
# `mtkcompile` with their source instead of while building a problem.
function _dry_lower(sys::PottsSystem, rn, fields, cell_odes)
    T = Float64
    cellenv = _cell_env(T, :c, rn; mcs = :mcs, key = :key)
    for e in sys.energies
        _located(sys, e) do
            d = e.domain
            d isa CellDomain ? lower(e.expr, _cell_env(T, :c, rn)) :
            d isa ClusterDomain ? lower(e.expr, _cluster_env(T, :r, rn)) :
            d isa ContactDomain ? lower(_cellvars_at_owner(e.expr), _contact_env(T, :a, :ka, :n, :kn, :w, :i, :j, rn)) :
            d isa SiteDomain ? lower(e.expr, _site_env(T, :i, rn)) :
            d isa EdgeDomain ? lower(e.expr, _edge_env(T, :ea, :eb, :ek, :ed, rn)) : nothing
        end
    end
    # The integral check runs before lowering, which would otherwise fail on a bare
    # `integral` with the generic "is per cell" message (D-125).
    for d in sys.drives
        _located(() -> (_check_copy_integral(d.expr, "drives"); lower(d.expr, _proposal_env(T, rn))), sys, d)
    end
    for c in sys.constraints
        c.kind === :expr &&
            _located(() -> (_check_copy_integral(c.expr, "constraints"); lower(c.expr, _proposal_env(T, rn))), sys, c)
    end
    for u in sys.updates
        _located(sys, u) do
            if u.phase === :on_copy
                env = _proposal_env(T, rn)
                lower(u.eq.rhs, env)
                _write(_unwrap(u.eq.lhs), :v, env)
            else
                r = info(_unwrap(u.eq.lhs)).role
                lower(u.eq.rhs, r === :cell ? cellenv : r === :model ? _model_env(T, rn; key = :key) :
                                _site_env(T, :i, rn; mcs = :mcs, key = :key))
            end
        end
    end
    for eq in sys.equations
        _located(sys, eq) do
            x = arguments(_unwrap(eq.lhs))[1]
            r = info(x).role
            lower(eq.rhs, r === :cell ? _cell_env(T, :c, rn; mcs = :mcs, key = :key, extra = (:time => :tt,)) :
                          r === :model ? _model_env(T, rn; key = :key, extra = (:time => :tt,)) :
                          _site_env(T, :i, rn; mcs = :mcs, key = :key))
        end
    end
    for d in sys.divisions
        _located(sys, d) do
            lower(d.when, cellenv)
            foreach(((x, r),) -> r isa Split || lower(r, _cell_env(T, :parent, rn; mcs = :mcs, key = :key)), d.rules)
        end
    end
    for r in sys.link_rules
        _located(() -> lower(r.when, _edge_env(T, :ea, :eb, :ek, :ed, rn; mcs = :mcs)), sys, r)
    end
    for b in sys.discrete
        env = b.scope === :cell ? cellenv : _model_env(T, rn; key = :key)
        _located(() -> foreach(x -> (lower(x, env); _check_geometry(x, length(sys.lattice.dims))), b.next), sys, b)
    end
    # geometry axes, and names the lowering environments cannot rule out
    N = length(sys.lattice.dims)
    for e in sys.energies
        _located(() -> _check_geometry(e.expr, N; energy = true), sys, e)
    end
    for (x, items) in ((d -> d.expr, sys.drives), (c -> c.kind === :expr ? c.expr : 0, sys.constraints),
            (u -> u.eq.rhs, sys.updates), (eq -> eq.rhs, sys.equations),
            (d -> [d.when; [r for (_, r) in d.rules if !(r isa Split)]], sys.divisions))
        foreach(i -> _located(() -> foreach(y -> _check_geometry(y, N), vcat(x(i))), sys, i), items)
    end
    # `integral(Pre(x))` is the block-start fold of an update block (D-042). Outside the
    # blocks `Pre(x)` is the stored value, so the integral would silently be another one.
    for (x, items) in ((eq -> eq.rhs, sys.equations), (d -> [d.when; [r for (_, r) in d.rules if !(r isa Split)]], sys.divisions),
            (r -> r.when, sys.link_rules), (b -> b.next, sys.discrete), (o -> o.expr, sys.observed))
        foreach(i -> _located(() -> foreach(_check_integral_pre_outside, vcat(x(i))), sys, i), items)
    end
    _check_integral_pre_outside(sys.sweep.temperature)
    for o in sys.observed
        _located(sys, o) do
            _check_geometry(o.expr, N)
            _has_op(o.expr, history_lag) &&
                throw(ArgumentError("`Pre(x, k)` is not available in @observed; keep the lag in a variable updated @after_mcs"))
            _has_op(o.expr, random_uniform) &&
                throw(ArgumentError("`rand()` is not available in @observed (observed quantities are pure functions of the state)"))
        end
    end
    return nothing
end

"""
Dimensional analysis of a model whose parameters or variables carry units (`[unit = …]`):
every term of H (energies, drives, the temperature) has one unit, each update's right side
has its variable's unit, and equations, conditions and observed quantities are consistent.
Implemented by the DynamicQuantities extension; without it (or without units) a no-op.
"""
_check_units(sys) = nothing

function _check_integral_pre_outside(x)
    _integral_pre(x) && throw(ArgumentError(
        "`integral(Pre(x))` is only available in update blocks, where it folds the values before the " *
        "block; elsewhere `Pre(x)` is the stored value. Keep it in a cell variable updated in " *
        "the block (`s ~ integral(Pre(x))`), or write `integral(x)`"))
    return nothing
end

# Drives and expression constraints are evaluated at every copy attempt, where σ changes
# with each accepted copy, while an integral is refreshed only between sweeps (D-125).
function _check_copy_integral(x, what)
    _has_op(x, cell_integral) && throw(ArgumentError(
        "`integral` is not available in $what: they are evaluated at every copy attempt, while an " *
        "integral is refreshed only between sweeps. Keep it in a cell variable updated @before_mcs " *
        "(`s ~ integral(x)`) and read `s[new]`, `s[old]`"))
    return nothing
end

"""Axes of `centroid`/`displacement` must be lattice axes; `centroid` has no ΔH in energies."""
function _check_geometry(x, N; energy = false)
    _walk(x) do y
        iscall(y) || return
        op = operation(y)
        if op === cell_integral
            energy && throw(ArgumentError("`integral` is not available in energies (it is refreshed once per MCS, " *
                                          "so it has no ΔH); write the site term in the energy instead"))
            return
        end
        (op === cell_centroid || op === copy_displacement) || return
        name = op === cell_centroid ? "centroid" : "displacement"
        energy && throw(ArgumentError("`$name` is not available in energies (the copy's centroid shift " *
                                      "is not part of ΔH); use `displacement(c, k)` in a @drive"))
        k = SymbolicUtils.unwrap_const(_unwrap(arguments(y)[end]))
        (k isa Real && isinteger(k) && 1 <= k <= N) ||
            throw(ArgumentError("`$name`: axis $k is not an axis of the $(N)D lattice"))
    end
    return nothing
end
