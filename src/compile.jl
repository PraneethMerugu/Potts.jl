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
    contact_terms::Dict{Symbol, Any}                  # relation name → symmetrized pair energy
    site_terms::Vector{Any}
    drive::Any                                        # sum of drives (proposal scope)
    constraints::Vector{Constraint}
    updates::Dict{Tuple{Symbol, Symbol}, Vector{Update}}   # (phase, scope) → updates
    fields::Vector{Tuple{Any, Any}}                   # (field variable, rate)
    cell_odes::Vector{Tuple{Any, Any}}                # (cell variable, rate)
    divisions::Vector{DivideRule}
    relationship::Union{Nothing, RelationshipSpec}
    edge_terms::Vector{Any}                           # link energies E(a, b, distance, edge vars)
    link_rules::Vector{LinkRule}
    uses_surface::Bool
    needs_moments::Bool
    relations::Dict{Symbol, Any}                      # ctx relation name → spec (excl. contact)
    contact_spec::Any
    gather_names::Dict{Any, Symbol}
    footprint::Footprint
    scratch::Set{Symbol}                              # site variables that need a scratch buffer
end

Base.nameof(c::CompiledPottsSystem) = nameof(c.sys)

const _CELL_ENERGY_BUILTINS = (:volume, :surface, :kind, :id, :generation)
const _CELL_BUILTINS = (_CELL_ENERGY_BUILTINS..., :mcs)      # cell updates, division rules
const _CONTACT_BUILTINS = (:kind, :kind′, :owner, :owner′, :weight)
const _SITE_BUILTINS = (:owner, :kind, :position, :mcs)
const _PROPOSAL_BUILTINS = (:source, :target, :old, :new)
const _EDGE_BUILTINS = (:a, :b, :distance)
const _LINK_BUILTINS = (:a, :b, :distance, :mcs)

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

const _INDEXABLE = (:owner, :kind, :volume, :surface, :generation)

function _check_names(x, allowed, what)
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
    cell_terms = Tuple{Vector{Int}, Any}[]
    contact_terms = Dict{Symbol, Any}()
    site_terms = Any[]
    edge_terms = Any[]
    length(sys.relationships) <= 1 || throw(ArgumentError("one @relationship per model is supported so far"))
    relationship = isempty(sys.relationships) ? nothing : only(sys.relationships)
    for e in sys.energies
        d = e.domain
        if d isa CellDomain
            0 in d.kinds && throw(ArgumentError("cells(…) cannot include the medium kind"))
            _check_names(e.expr, _CELL_ENERGY_BUILTINS, "a cell term")
            push!(cell_terms, (d.kinds, e.expr))
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
    drive = isempty(sys.drives) ? nothing : sum(d -> d.expr, sys.drives)
    drive === nothing || _check_names(drive, _PROPOSAL_BUILTINS, "a drive")
    for c in sys.constraints
        c.kind === :expr && _check_names(c.expr, _PROPOSAL_BUILTINS, "a constraint")
    end

    # updates by phase and scope
    updates = Dict{Tuple{Symbol, Symbol}, Vector{Update}}()
    for u in sys.updates
        lhs = _unwrap(u.eq.lhs)
        scope = if u.phase === :on_copy
            (iscall(lhs) && operation(lhs) === at) || throw(ArgumentError("@on_copy updates assign at a site or cell, e.g. `act[target] ~ …`"))
            _check_names(u.eq.rhs, _PROPOSAL_BUILTINS, "an on-copy update")
            :proposal
        else
            i = info(lhs)
            (i !== nothing && i.role in SCOPES) || throw(ArgumentError("update target `$lhs` is not a declared variable"))
            i.role === :model && throw(ArgumentError("model-scope updates are not supported yet"))
            _check_names(u.eq.rhs, i.role === :cell ? _CELL_BUILTINS : _SITE_BUILTINS, "a $(i.role) update")
            i.role === :field ? :site : i.role
        end
        push!(get!(updates, (u.phase, scope), Update[]), u)
    end

    # differential equations: fields (lattice PDEs) and per-cell ODEs
    fields = Tuple{Any, Any}[]
    cell_odes = Tuple{Any, Any}[]
    for eq in sys.equations
        lhs = _unwrap(eq.lhs)
        (iscall(lhs) && operation(lhs) isa Differential) ||
            throw(ArgumentError("equations are `D(x) ~ rhs`; got $eq"))
        x = arguments(lhs)[1]
        i = info(x)
        i === nothing && throw(ArgumentError("`$x` is not a declared variable"))
        if i.role === :field || i.role === :site
            _check_names(eq.rhs, _SITE_BUILTINS, "a field equation")
            push!(fields, (x, eq.rhs))
        elseif i.role === :cell
            _check_names(eq.rhs, _CELL_BUILTINS, "a cell equation")
            push!(cell_odes, (x, eq.rhs))
        else
            throw(ArgumentError("model-scope equations are not supported yet"))
        end
    end
    for d in sys.divisions
        _check_names(d.when, _CELL_BUILTINS, "a division condition")
    end
    for r in sys.link_rules
        (relationship !== nothing && relationship.name === r.relationship) ||
            throw(ArgumentError("@$(r.action) $(r.relationship): no @relationship $(r.relationship)"))
        _check_names(r.when, _LINK_BUILTINS, "a link rule")
    end
    for x in sys.variables
        info(x).role === :edge && relationship === nothing &&
            throw(ArgumentError("edge variable `$(info(x).name)` needs a @relationship"))
    end

    needs_moments = !isempty(sys.divisions) || relationship !== nothing

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
    all_exprs = Any[last.(cell_terms)..., values(contact_terms)..., site_terms...,
        (drive === nothing ? () : (drive,))..., (c.expr for c in sys.constraints if c.kind === :expr)...,
        (u.eq.rhs for u in sys.updates)..., (last(f) for f in fields)..., (last(f) for f in cell_odes)...,
        sys.sweep.temperature]
    uses_surface = any(x -> _uses_builtin(x, :surface), all_exprs) ||
                   any(d -> _uses_builtin(d.when, :surface), sys.divisions)
    uses_surface && !haskey(relations, :surface) && (relations[:surface] = sys.lattice.neighborhood)
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
    uses_surface && (radius_read = max(radius_read, rad(relations[:surface])))
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

    return CompiledPottsSystem(sys, cell_terms, contact_terms, site_terms, drive,
        sys.constraints, updates, fields, cell_odes, sys.divisions, relationship, edge_terms,
        sys.link_rules, uses_surface,
        needs_moments, relations, contact_spec, gather_names, Footprint(read = radius_read),
        scratch)
end

# Quantities a copy changes cannot appear in contact, site or edge terms: their deltas are
# derived only for cell terms.
function _check_static(x, what)
    for n in (:volume, :surface)
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

# Copy delta of a cell term for one side: E(q + δq) − E(q), expanded when that is cheaper.
function _cell_delta(E, dv::Int)
    sub = Dict(_unwrap(B.volume) => B.volume + dv, _unwrap(B.surface) => B.surface + DSURFACE)
    naive = Symbolics.substitute(E, sub; fold = Val(false)) - E
    expanded = Symbolics.expand(naive)
    return _nops(expanded) <= _nops(naive) ? expanded : naive
end
function _nops(x)
    n = Ref(0)
    _walk(y -> (iscall(y) && (n[] += 1)), x)
    return n[]
end
