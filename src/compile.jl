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
    relationship::Union{Nothing, RelationshipSpec}
    edge_terms::Vector{Any}                           # link energies E(a, b, distance, edge vars)
    link_rules::Vector{LinkRule}
    uses_surface::Bool
    uses_clusters::Bool                               # `st.cell.cluster` and `cluster_volume`
    uses_cluster_surface::Bool
    cluster_division::Bool
    needs_moments::Bool
    relations::Dict{Symbol, Any}                      # ctx relation name → spec (excl. contact)
    contact_spec::Any
    gather_names::Dict{Any, Symbol}
    footprint::Footprint
    scratch::Set{Symbol}                              # site variables that need a scratch buffer
end

Base.nameof(c::CompiledPottsSystem) = nameof(c.sys)

const _CELL_ENERGY_BUILTINS = (:volume, :surface, :kind, :id, :generation, :cluster)
# cell updates, division rules (cluster trackers change with copies of other members, so
# they are readable here but not in cell energies)
const _CELL_BUILTINS = (_CELL_ENERGY_BUILTINS..., :mcs, :cluster_volume, :cluster_surface)
const _CLUSTER_BUILTINS = (:cluster_volume, :cluster_surface, :kind, :id)
const _CONTACT_BUILTINS = (:kind, :kind′, :owner, :owner′, :weight)
const _SITE_BUILTINS = (:owner, :kind, :position, :mcs)
const _PROPOSAL_BUILTINS = (:source, :target, :old, :new)
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
        n in allowed || throw(ArgumentError("`$n` is not available in $what (available: $(join(allowed, ", ")); index `owner`, `kind`, `volume` explicitly, e.g. `kind[new]`)"))
    end
    for (r, n) in _uses(x)
        r === :builtin && !(n in allowed) && !(n in _INDEXABLE) &&
            throw(ArgumentError("`$n` is not available in $what (available: $(join(allowed, ", ")))"))
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
    cell_terms = Tuple{Vector{Int}, Any}[]
    cluster_terms = Tuple{Vector{Int}, Any}[]
    contact_terms = Dict{Symbol, Any}()
    site_terms = Any[]
    edge_terms = Any[]
    length(sys.relationships) <= 1 || throw(ArgumentError("one @relationship per model is supported so far"))
    relationship = isempty(sys.relationships) ? nothing : only(sys.relationships)
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
            _check_static(e.expr, "a contact term")
            E = _symmetrize(_cellvars_at_owner(e.expr))
            contact_terms[d.relation] = haskey(contact_terms, d.relation) ? contact_terms[d.relation] + E : E
        elseif d isa EdgeDomain
            (relationship !== nothing && relationship.name === d.relationship) ||
                throw(ArgumentError("edges($(d.relationship)): no @relationship $(d.relationship)"))
            _check_names(e.expr, _EDGE_BUILTINS, "an edge term")
            _check_static(e.expr, "an edge term")
            push!(edge_terms, e.expr)
        elseif d isa SiteDomain
            _check_names(e.expr, _SITE_BUILTINS, "a site term")
            _check_static(e.expr, "a site term")
            isempty(_gathers(e.expr)) || throw(ArgumentError("site terms reading neighbours are not supported yet"))
            push!(site_terms, e.expr)
        else
            throw(ArgumentError("unknown energy domain $d"))
        end
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
    for eq in sys.equations
        _located(sys, eq) do
        lhs = _unwrap(eq.lhs)
        (iscall(lhs) && operation(lhs) isa Differential) ||
            throw(ArgumentError("equations are `D(x) ~ rhs`; got $eq"))
        x = arguments(lhs)[1]
        i = info(x)
        i === nothing && throw(ArgumentError("`$x` is not a declared variable"))
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
    cluster_division = any(d -> d.domain isa ClusterDomain, sys.divisions)
    cluster_division && !all(d -> d.domain isa ClusterDomain, sys.divisions) &&
        throw(ArgumentError("a model divides either cells or clusters; mix of @divide cells(…) and clusters(…)"))
    for r in sys.link_rules
        _located(sys, r) do
            (relationship !== nothing && relationship.name === r.relationship) ||
                throw(ArgumentError("@$(r.action) $(r.relationship): no @relationship $(r.relationship)"))
            _check_names(r.when, _LINK_BUILTINS, "a link rule"; between_copies = true)
        end
    end
    for x in sys.variables
        info(x).role === :edge && relationship === nothing &&
            throw(ArgumentError("edge variable `$(info(x).name)` needs a @relationship"))
    end

    # one writer per target, phase and cadence (combine contributions with `+=`)
    writers = Dict{Any, Update}()
    for u in sys.updates
        k = _target_key(u)
        haskey(writers, k) && _located(sys, u) do
            throw(ArgumentError("`$(u.eq.lhs)` is already written @$(u.phase)$(u.every == 1 ? "" : " Every($(u.every))") " *
                                "by `$(writers[k].eq)`; combine contributions with `+=` or in one equation"))
        end
        writers[k] = u
    end
    geometric(x) = _has_op(x, cell_centroid) || _has_op(x, copy_displacement)
    needs_moments = !isempty(sys.divisions) || relationship !== nothing ||
                    any(geometric, Any[(e.expr for e in sys.energies)..., (d.expr for d in sys.drives)...,
                        (u.eq.rhs for u in sys.updates)..., (eq.rhs for eq in sys.equations)...,
                        (o.expr for o in sys.observed)..., (c.expr for c in sys.constraints if c.kind === :expr)...])

    # relations: contact (ctx.contact), surface, named, gathers
    contact_spec = get(sys.relations, :contact, sys.lattice.neighborhood)
    relations = Dict{Symbol, Any}()
    for (k, v) in sys.relations
        k === :contact || (relations[k] = v)
    end
    for r in keys(contact_terms)
        r === :contact || haskey(relations, r) || throw(ArgumentError("contacts($r): relation `$r` is not declared in @relations"))
    end
    gather_names = Dict{Any, Symbol}()
    all_exprs = Any[last.(cell_terms)..., last.(cluster_terms)..., values(contact_terms)..., site_terms...,
        (drive === nothing ? () : (drive,))..., (c.expr for c in sys.constraints if c.kind === :expr)...,
        (u.eq.rhs for u in sys.updates)..., (last(f) for f in fields)..., (last(f) for f in cell_odes)..., (last(f) for f in model_odes)...,
        sys.sweep.temperature]
    uses_surface = any(x -> _uses_builtin(x, :surface), all_exprs) ||
                   any(d -> _uses_builtin(d.when, :surface), sys.divisions)
    # everything evaluated against the state, including division rules and observed quantities
    scanned = Any[all_exprs..., (d.when for d in sys.divisions)...,
        (r for d in sys.divisions for (_, r) in d.rules if !(r isa Split))..., (o.expr for o in sys.observed)...]
    uses_cluster_surface = any(x -> _uses_builtin(x, :cluster_surface), scanned)
    uses_clusters = cluster_division || uses_cluster_surface ||
                    any(x -> _uses_builtin(x, :cluster) || _uses_builtin(x, :cluster_volume), scanned)
    (uses_surface || uses_cluster_surface) && !haskey(relations, :surface) &&
        (relations[:surface] = sys.lattice.neighborhood)
    radius_read = 1
    for x in all_exprs, (ni, anchor) in _gathers(x)
        spec = ni.options.relation
        if !(spec isa RelationRef) && !haskey(gather_names, spec)
            gather_names[spec] = Symbol(:gather, length(gather_names) + 1)
            relations[gather_names[spec]] = spec
        end
    end

    # footprint: largest distance from the target read by the per-copy functions
    lat = core_lattice(sys.lattice)
    rad(spec) = CP.radius(CP.relation(spec, lat))
    isempty(contact_terms) || (radius_read = max(radius_read, maximum(r -> rad(r === :contact ? contact_spec : relations[r]), keys(contact_terms))))
    (uses_surface || uses_cluster_surface) && (radius_read = max(radius_read, rad(relations[:surface])))
    for x in Any[(drive === nothing ? () : (drive,))..., (c.expr for c in sys.constraints if c.kind === :expr)...,
            (u.eq.rhs for u in get(updates, (:on_copy, :proposal), Update[]))...]
        for (ni, anchor) in _gathers(x)
            spec = ni.options.relation
            r = rad(spec isa RelationRef ? sys.relations[spec.name] : spec)
            radius_read = max(radius_read, r + (_uses_builtin(anchor, :source) ? 1 : 0))
        end
    end

    # site variables whose synchronous updates read neighbours need a scratch buffer
    scratch = Set{Symbol}()
    for ((phase, scope), us) in updates
        scope === :site || continue
        written = Set(info(_unwrap(u.eq.lhs)).name for u in us)
        for u in us
            neighbour_reads = Set{Symbol}()
            _walk(u.eq.rhs) do y
                if iscall(y) && (operation(y) === gather || operation(y) === Δ)
                    foreach(z -> (i = info(z); i !== nothing && i.role in (:site, :field) && push!(neighbour_reads, i.name)),
                        _leaves(y))
                end
            end
            isempty(intersect(neighbour_reads, written)) || union!(scratch, written)
        end
    end
    for (x, _) in fields
        push!(scratch, info(x).name)
    end

    _dry_lower(sys, gather_names, fields, cell_odes)
    _check_units(sys)

    return CompiledPottsSystem(sys, cell_terms, cluster_terms, contact_terms, site_terms, drive,
        sys.constraints, updates, fields, cell_odes, model_odes, sys.divisions, relationship, edge_terms,
        sys.link_rules, uses_surface, uses_clusters, uses_cluster_surface, cluster_division,
        needs_moments, relations, contact_spec, gather_names, Footprint(read = radius_read),
        scratch)
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

# In a contact term a bare cell variable means its value at the owner (`x[owner]`), so that
# mirroring (owner ↔ owner′) sees it; bare site variables are ambiguous there.
function _cellvars_at_owner(E)
    sub = Dict{Any, Any}()
    for x in _bare_vars(E)
        i = info(x)
        i.role === :cell && (sub[x] = _unwrap(at(Symbolics.wrap(x), B.owner)))
        i.role in (:site, :field) && throw(ArgumentError("site variable `$(i.name)` in a contact term: the pair has two sites; not supported"))
    end
    isempty(sub) && return E
    return Symbolics.substitute(E, sub; fold = Val(false), filterer = _not_indexed)
end
_not_indexed(ex) = !(iscall(ex) && (operation(ex) === at || operation(ex) === at2)) &&
                   SymbolicUtils.default_substitute_filter(ex)

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
# with its mirror (kind ↔ kind′, owner ↔ owner′).
# Kind tables used in contact terms must be symmetric (checked against their values when the
# problem is built), so their entries are compared up to index order.
function _symmetrize(E)
    swap = Dict(_unwrap(B.kind) => _unwrap(B.kind′), _unwrap(B.kind′) => _unwrap(B.kind),
        _unwrap(B.owner) => _unwrap(B.owner′), _unwrap(B.owner′) => _unwrap(B.owner))
    M = Symbolics.substitute(E, swap; fold = Val(false))
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
function _cell_delta(E, dv::Int)
    sub = Dict(_unwrap(B.volume) => B.volume + dv, _unwrap(B.surface) => B.surface + DSURFACE,
        _unwrap(B.cluster_volume) => B.cluster_volume + dv,
        _unwrap(B.cluster_surface) => B.cluster_surface + DCSURFACE)
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
_describe(d::DivideRule) = "@divide $(_domain_string(d.domain)) when = $(d.when)"
_describe(r::LinkRule) = "@$(r.action) $(r.relationship) when = $(r.when)"
_describe(o::ObservedEq) = "@observed $(o.var) ~ $(o.expr)"

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
            d isa ContactDomain ? lower(_cellvars_at_owner(e.expr), _contact_env(T, :a, :ka, :n, :kn, :w, :i, rn)) :
            d isa SiteDomain ? lower(e.expr, _site_env(T, :i, rn)) :
            d isa EdgeDomain ? lower(e.expr, _edge_env(T, :ea, :eb, :ek, :ed, rn)) : nothing
        end
    end
    for d in sys.drives
        _located(() -> lower(d.expr, _proposal_env(T, rn)), sys, d)
    end
    for c in sys.constraints
        c.kind === :expr && _located(() -> lower(c.expr, _proposal_env(T, rn)), sys, c)
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
