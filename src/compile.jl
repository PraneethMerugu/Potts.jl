# `mtkcompile(sys::PottsSystem)`: validate the model, derive the energy change of a copy
# from the authored Hamiltonian, and decide trackers, relations and the footprint.
# The result is still symbolic; `codegen.jl` lowers it for a scalar type.

"""
    CompiledPottsSystem

A `PottsSystem` after `mtkcompile`: a complete ModelingToolkit `AbstractSystem`.

MTK's accessors (`equations`, `unknowns`, `parameters`, `observed`, `initial_conditions`,
`guesses`, `inputs`, `outputs`, `independent_variable`, the metadata) and `csys.x` answer
as for the model it was compiled from. SymbolicIndexingInterface getters built from it
(`getp(csys, p)`) work on its problems, integrators and solutions.

It also holds what a CPM sweep needs and no MTK system holds: the energy terms classified
by domain with their derived copy deltas, the trackers and relations that the model needs,
and its footprint.

It is read-only. `setmetadata`, `rename`, `compose`, `extend`, `toggle_namespacing` and its
use as a component of an MTK System (`system ∘ csys`) throw an `ArgumentError`: apply them
to the model, then compile it. [`Potts.inner`](@ref)`(csys)` is the System of the model as
compiled.

The fields are not public. Read it through the MTK accessors and [`Potts.inner`](@ref).

# Examples
```julia
csys = mtkcompile(sys)
prob = PottsProblem(csys, op, (0, 100); seed = 1)
```

See also [`PottsSystem`](@ref), [`generated_code`](@ref), [`Potts.ode_system`](@ref).
"""
struct CompiledPottsSystem <: ModelingToolkitBase.AbstractSystem
    sys::PottsSystem
    # (kinds, E) with E in volume/surface/…
    cell_terms::Vector{Tuple{Vector{Int}, Any}}
    # (root kinds, E) with E in cluster_volume/…
    cluster_terms::Vector{Tuple{Vector{Int}, Any}}
    # relation name → symmetrized pair energy
    contact_terms::Dict{Symbol, Any}
    site_terms::Vector{Any}
    drive::Any                                        # sum of drives (proposal scope)
    constraints::Vector{Constraint}
    updates::Dict{Tuple{Symbol, Symbol}, Vector{Update}}   # (phase, scope) → updates
    fields::Vector{Tuple{Any, Any}}                   # (field variable, rate)
    cell_odes::Vector{Tuple{Any, Any}}                # (cell variable, rate)
    model_odes::Vector{Tuple{Any, Any}}               # (model variable, rate)
    divisions::Vector{DivideRule}
    relationships::Vector{RelationshipSpec}           # in declaration order
    # (relationship, E(a, b, distance, its edge vars))
    edge_terms::Vector{Tuple{Symbol, Any}}
    # (ordered relationship, E(a, pivot, b, angle, curvature))
    angle_terms::Vector{Tuple{Symbol, Any}}
    edge_vars::Dict{Symbol, Vector{Any}}              # relationship → its edge variables
    link_rules::Vector{LinkRule}
    uses_surface::Bool
    # `st.cell.cluster` and `cluster_volume`
    uses_clusters::Bool
    uses_cluster_surface::Bool
    uses_euler::Bool                                  # `euler` (face adjacency)
    # `euler(; adjacency = :full)` (not on hex)
    uses_euler_full::Bool
    # the column it reads: `:euler` on hex (D-192 Q4)
    euler_full_column::Symbol
    cluster_division::Bool
    needs_moments::Bool
    # ctx relation name → spec (excl. contact)
    relations::Dict{Symbol, Any}
    contact_spec::Any
    # `@relations proposal = …`, or `VonNeumann(1)`
    proposal_spec::Any
    gather_names::Dict{Any, Symbol}
    footprint::Footprint
    # field variables (double-buffered steps)
    scratch::Set{Symbol}
    # :before_mcs/:after_mcs → ordered stages (D-042)
    schedule::Dict{Symbol, Vector{Stage}}
    # block → (scope, x) copied to x__pre
    pre_snapshots::Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}
    # model slots of folds hoisted from updates and integrals
    update_pops::Vector{Pair{Symbol, Any}}
    # model slots of folds in energies (D-041)
    energy_snapshots::Vector{Pair{Symbol, Any}}
    cell_ode_pops::Vector{Pair{Symbol, Any}}          # model slots of folds in cell ODEs
    # discrete components' ticks, folds hoisted
    discrete::Vector{DiscreteBlock}
    # model slots of folds in cell-scope ticks
    discrete_pops::Vector{Pair{Symbol, Any}}
    # contact folds (name, relation, kind mask), D-150
    contact_trackers::Vector{Tuple{Symbol, Symbol, UInt64}}
    # the system as authored, before `_bind_components` lowers its components (`sys` is the
    # bound one): `hamiltonian`, `drives` and the `PottsSweepSpec` payload read it (D-160);
    # never read by codegen, so never in the code or the fingerprint
    authored::PottsSystem
    # the cell and model ODE templates as compiled by MTK (`ode_system`, odes.jl), by scope;
    # never read by codegen
    ode_systems::Dict{Symbol, Any}
    # the cell and model `@initialization_equations` (`initialization_system`,
    # initialization.jl), by scope; run when a problem is built, never read by codegen
    initialization::Dict{Symbol, Any}
    # cell-scope `pieces`/`largest_piece`: the face and full trackers read; on a
    # hexagonal lattice `:full` reads the `:face` columns (one adjacency, D-193)
    uses_pieces::Bool
    uses_pieces_full::Bool
    pieces_hex::Bool
    # cell serials (D-066 item 3): whether the model reads `birth`, directly
    # (`birth`, `birth[ref]`) or through `sibling` (its lowest-birth rule, E5) or a
    # `@convert` pass (whose `from`/`to` default to `sibling(k)`). A dividing model that
    # reads none of them carries no `birth` column, so neither planner runs the serial pass
    # (`_tracks_births`)
    uses_birth::Bool
    # the lowered field groups (`GroupSpec`s, fields.jl), by partition and state type: the
    # group of all fields in Float64 is lowered here, and problems reuse it; never read by
    # codegen
    field_specs::Dict{Any, Any}
end

Base.nameof(c::CompiledPottsSystem) = nameof(getfield(c, :sys))
fields(c::CompiledPottsSystem) = fields(getfield(c, :sys))

# `csys.x` is the model's quantity or component, as `sys.x` of the model compiled from
# (MTK's `getproperty`), whatever its name: Potts reads the compiled payload with
# `getfield`, as MTK reads a system's fields
Base.getproperty(c::CompiledPottsSystem, n::Symbol) = getproperty(getfield(c, :authored), n)
function Base.propertynames(c::CompiledPottsSystem; private::Bool = false)
    return private ? fieldnames(CompiledPottsSystem) : propertynames(getfield(c, :authored))
end

# MTK's accessors: the model's own (`authored`, before its components are lowered)
_MTKB.get_systems(::CompiledPottsSystem) = _MTKB.AbstractSystem[]
for f in (
        :equations, :unknowns, :observed, :initial_conditions, :bindings,
        :independent_variable, :guesses,
        :inputs, :outputs,
    )
    @eval _MTKB.$f(c::CompiledPottsSystem) = _MTKB.$f(getfield(c, :authored))
end
function _MTKB.parameters(c::CompiledPottsSystem; kw...)
    return _MTKB.parameters(getfield(c, :authored); kw...)
end
function _MTKB.full_equations(c::CompiledPottsSystem; kw...)
    return _MTKB.full_equations(getfield(c, :authored); kw...)
end
_MTKB.iscomplete(::CompiledPottsSystem) = true
_MTKB.complete(c::CompiledPottsSystem; kw...) = (_refuse_complete_keywords(c, kw); c)
_MTKB.get_iv(c::CompiledPottsSystem) = _MTKB.get_iv(getfield(c, :authored))
inner(c::CompiledPottsSystem) = inner(getfield(c, :sys))

# MTK's operations that build a new system: a compiled system is read-only, so each is an
# `ArgumentError` that names the route (apply it to the model, then `mtkcompile`). MTK's
# `extend`, `setmetadata` and `toggle_namespacing` refuse it already (`extend` in
# compose.jl, `setmetadata` in sweep_spec.jl, `toggle_namespacing` in MTK: a Potts system
# has no `namespacing` flag).
function Symbolics.rename(c::CompiledPottsSystem, name::Symbol)
    throw(
        ArgumentError(
            "rename($(nameof(c)), :$name): a compiled system is read-only; rename the " *
                "model, then compile it: `mtkcompile(rename(sys, :$name))`"
        )
    )
end
function ModelingToolkitBase.compose(c::CompiledPottsSystem, ::AbstractArray; kw...)
    throw(
        ArgumentError(
            "compose($(nameof(c)), …): a compiled system is read-only; compose the " *
                "model, then compile it: `mtkcompile(compose(sys, components))`"
        )
    )
end
# a compiled system among an MTK System's components (`clock ∘ csys`, `System(…; systems)`)
function Base.convert(::Type{ModelingToolkitBase.System}, c::CompiledPottsSystem)
    throw(
        ArgumentError(
            "the compiled system `$(nameof(c))` is not a component of an MTK System; " *
                "compose the model the other way round, `compose(sys, [system])`, then \
                    compile it"
        )
    )
end

function Base.show(io::IO, c::CompiledPottsSystem)
    (print(io, "Compiled"); show(io, getfield(c, :authored)))
end
# the authored model's `@description` (MTK's fallback would read the compiled container's)
_MTKB.description(c::CompiledPottsSystem) = _MTKB.description(getfield(c, :authored))
function Base.show(io::IO, ::MIME"text/plain", c::CompiledPottsSystem)
    print(io, "CompiledPottsSystem of ")
    return show(io, MIME"text/plain"(), getfield(c, :authored))
end

const _CELL_ENERGY_BUILTINS = (
    :volume, :surface, :kind, :id, :generation, :cluster, :major_length, :euler,
    :euler_full,
    :pieces, :pieces_full, :largest_piece, :largest_piece_full, :birth,
)
# the cell-scope pieces trackers: the face pair, the full pair
const _PIECES_NAMES = (:pieces, :largest_piece, :pieces_full, :largest_piece_full)
# cell updates, division rules (cluster trackers change with copies of other members, so
# they are readable here but not in cell energies)
const _CELL_BUILTINS = (_CELL_ENERGY_BUILTINS..., :mcs, :cluster_volume, :cluster_surface)
const _CLUSTER_BUILTINS = (:cluster_volume, :cluster_surface, :kind, :id)
const _CONTACT_BUILTINS = (
    :kind, :neighbor_kind, :owner, :neighbor_owner, :weight, :neighbor_site,
)   # `neighbor_site`: from `x′`
const _SITE_BUILTINS = (:owner, :kind, :position, :site, :mcs)
# `direction`, `position[s][k]` and `mcs` (D-188): the copy's source→target offset,
# a site's position, and the number of completed MCS
const _PROPOSAL_BUILTINS = (
    :source, :target, :old, :new, :local_components, :ring_arcs, :ring_cells, :ring_medium,
    :direction, :position, :mcs,
)
const _EDGE_BUILTINS = (:a, :b, :distance)
const _ANGLE_BUILTINS = (:a, :b, :pivot, :angle, :curvature)
const _LINK_BUILTINS = (:a, :b, :distance, :mcs)

# Replace population folds by placeholders; return them for separate checking.
function _strip_populations(x)
    pops = Any[]
    _walk(y -> (iscall(y) && operation(y) === population && push!(pops, y)), x)
    isempty(pops) && return x, pops
    return Symbolics.substitute(x, Dict{Any, Any}(p => 0 for p in pops); fold = Val(false)),
        pops
end

# Built-in names used bare (not as the array of an explicit index like `kind[new]`).
function _bare_builtins(x, out = Set{Symbol}())
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return out
    i = info(x)
    i !== nothing && i.role === :builtin && push!(out, i.name)
    if iscall(x) && !_is_quantity_call(i)
        args = arguments(x)
        skip = operation(x) === value_at
        for (j, a) in enumerate(args)
            (skip && j == 1) || _bare_builtins(a, out)
        end
    end
    return out
end

const _INDEXABLE = (
    :owner, :kind, :volume, :surface, :generation, :cluster,
    :euler, :euler_full, _PIECES_NAMES..., :birth,
)

# names a user can write (`neighbor_site` only arises from `x′`)
function _visible(names)
    return filter(
        n -> !(n in (:neighbor_site, :euler_full, :pieces_full, :largest_piece_full)),
        collect(names)
    )
end

# `between_copies`: `x` is evaluated between copy attempts (updates, divisions, equations),
# not inside ΔH, so population bodies may read cluster trackers.
function _check_names(x, allowed, what; between_copies::Bool = false)
    # an integral's operand is a site expression, lowered in site scope: checked there (the
    # owner reads of `integral(x; over = cluster)`'s operand, `volume[owner]`, D-243)
    ints = Dict{Any, Any}()
    _walk(y -> (iscall(y) && operation(y) === cell_integral && (ints[y] = 0)), _unwrap(x))
    if !isempty(ints)
        foreach(
            y -> _check_names(
                arguments(y)[1], _SITE_BUILTINS,
                "the site expression of `integral`"
            ),
            keys(ints)
        )
        x = Symbolics.substitute(_unwrap(x), ints; fold = Val(false))
    end
    x, pops = _strip_populations(x)
    for p in pops                                  # population bodies have their own scope
        n, body, cond = arguments(p)
        inner = if info(n).role !== :bound_cell
            _SITE_BUILTINS
        elseif between_copies
            (_CELL_ENERGY_BUILTINS..., :cluster_volume, :cluster_surface)
        else
            _CELL_ENERGY_BUILTINS
        end
        _check_names(body, (allowed..., inner...), what; between_copies)
        _check_names(cond, (allowed..., inner...), what; between_copies)
    end
    for n in _bare_builtins(x)
        n === :neighbor_site && !(n in allowed) &&
            throw(PottsCompileError("a primed site variable `x′` (its value at the pair's \
                other site) is only available in contact terms, not in $what"))
        n in allowed ||
            throw(PottsCompileError("`$n` is not available in $what \
                (available: $(join(_visible(allowed), ", ")); index `owner`, `kind`, \
                    `volume` explicitly, e.g. `kind[new]`)"))
    end
    for (r, n) in _uses(x)
        r === :builtin && !(n in allowed) && !(n in _INDEXABLE) &&
            throw(PottsCompileError("`$n` is not available in $what \
                (available: $(join(_visible(allowed), ", ")))"))
        # a contact fold (D-150) is a cell quantity read between sweeps
        r === :contact_count && !(between_copies && :volume in allowed) && throw(
            PottsCompileError(
                "`count(… for _ in contacts)` is not available in $what: it is a cell " *
                    "quantity, exact between sweeps, for cell updates and equations, \
                        division conditions and rules, and cell observed quantities"
            )
        )
    end
    return nothing
end

# Relationships: names are unique; each edge variable belongs to one relationship,
# named by its scope (`rest(bond)`) or, with a single relationship, `rest(edge)`.
function _relationships(sys::PottsSystem)
    rels = _p(sys, :relationships)
    names = [r.name for r in rels]
    for (i, n) in enumerate(names)
        n in view(names, 1:(i - 1)) &&
            throw(PottsCompileError("@relationship `$n` is declared twice"))
        n in SCOPES && throw(
            PottsCompileError(
                "@relationship `$n`: the name is a variable scope " *
                    "($(join(SCOPES, ", "))); choose another"
            )
        )
    end
    edge_vars = Dict{Symbol, Vector{Any}}(n => Any[] for n in names)
    edge_rel = Dict{Symbol, Symbol}()                 # edge variable name → relationship
    for x in _p(sys, :variables)
        i = info(x)
        i.role === :edge || continue
        r = get(i.options, :relationship, nothing)
        if r === nothing
            isempty(names) &&
                throw(PottsCompileError("edge variable `$(i.name)` needs a @relationship"))
            length(names) == 1 || throw(
                PottsCompileError(
                    "edge variable `$(i.name)(edge)` is ambiguous: the model has " *
                        "relationships $(join(names, ", ")); name one as its scope, e.g. \
                            `$(i.name)($(first(names)))`"
                )
            )
            r = only(names)
        else
            r in names || throw(
                PottsCompileError(
                    "variable `$(i.name)($r)`: `$r` is neither a scope \
                        ($(join(SCOPES, ", "))) nor a @relationship" *
                        (isempty(names) ? "" : " (the model has $(join(names, ", ")))")
                )
            )
        end
        edge_rel[i.name] = r
        push!(edge_vars[r], x)
    end
    return rels, edge_vars, edge_rel
end

# An angle term reads the triple's static values and its geometry: no edge variable (a
# triple has two links), nothing a copy changes, no references
function _check_angle_term(E, d, relationships)
    r = findfirst(x -> x.name === d.relationship, relationships)
    r === nothing &&
        throw(PottsCompileError("angles($(d.relationship)): no @relationship \
            $(d.relationship)"))
    relationships[r].ordered || throw(
        PottsCompileError(
            "angles($(d.relationship)): the relationship is not ordered; declare it \
                `@relationship $(d.relationship)(cell, cell) ordered = true` so each \
                member has a predecessor and a successor"
        )
    )
    _check_names(E, _ANGLE_BUILTINS, "an angle term")
    _check_static(_strip_populations(E)[1], "an angle term")
    for (role, n) in _uses(E)
        role === :edge && throw(
            PottsCompileError(
                "angles($(d.relationship)) reads the edge variable `$n`; an angle term \
                    spans two links, so it reads no edge variable"
            )
        )
    end
    isempty(_gathers(E)) || throw(
        PottsCompileError(
            "angle terms reading neighbors are not supported; read neighbors in a \
                `cells(…)` or `contacts` term instead"
        )
    )
    return nothing
end

# `prev`, `next`, `rank` read an ordered relationship; `linked` any relationship
function _check_relationship_queries(exprs, relationships)
    for x in exprs
        _walk(x) do y
            iscall(y) || return
            op = operation(y)
            op isa RelationshipQuery || return
            r = findfirst(z -> z.name === op.relationship, relationships)
            r === nothing && throw(
                PottsCompileError(
                    "`$(op.what)($(op.relationship), …)`: no @relationship \
                        $(op.relationship)"
                )
            )
            op.what === :linked || relationships[r].ordered || throw(
                PottsCompileError(
                    "`$(op.what)($(op.relationship), …)` reads the order of a chain, but \
                        @relationship $(op.relationship) is not ordered; declare it with \
                        `ordered = true`"
                )
            )
        end
    end
    return nothing
end

# An edge term or link rule of relationship `r` reads only `r`'s edge variables (another
# relationship's payload has no slot for this link).
function _check_edge_vars(x, r, edge_rel, what)
    for (role, n) in _uses(x)
        role === :edge && edge_rel[n] !== r && throw(
            PottsCompileError(
                "$what reads `$n`, an edge variable of relationship `$(edge_rel[n])`"
            )
        )
    end
    return nothing
end

"""
    mtkcompile(sys::PottsSystem) -> CompiledPottsSystem

Validate and analyze a Potts model (the symbolic half of compilation; code is generated
per scalar type by `PottsProblem`). MTK's `mtkcompile` keywords (`inputs`, `outputs`,
`simplify`, …) are an `ArgumentError` that names them: they apply to an MTK `System`, so
give them to `mtkcompile(Potts.inner(sys); …)`, which compiles the cell and model equations
alone. `mtkcompile` of a `CompiledPottsSystem` returns it.
"""
function ModelingToolkitBase.mtkcompile(authored::PottsSystem; kw...)
    _refuse_compile_keywords(authored, kw)
    authored = _lower_inner(authored, "mtkcompile")
    # the model's own cell and model ODEs through MTK's `mtkcompile` first (odes.jl)
    routed, ode_systems, origin = _compile_odes(authored)
    # entity-local initialization through MTK's `InitializationProblem` (initialization.jl)
    initialization = _compile_initialization(routed)
    return _via_algebraic(
        () -> _compile_bound(
            authored, _bind_components(routed), ode_systems,
            initialization
        ),
        routed,
        origin
    )
end

function ModelingToolkitBase.mtkcompile(c::CompiledPottsSystem; kw...)
    (_refuse_compile_keywords(c, kw); c)
end

function _refuse_compile_keywords(sys, kw)
    isempty(kw) && return nothing
    throw(
        ArgumentError(
            string(
                "mtkcompile(", nameof(sys), "; ", join(keys(kw), ", "),
                "): a Potts model takes no ",
                "`mtkcompile` keywords; MTK's keywords apply to an MTK System: \
                    `mtkcompile(Potts.inner(sys); …)` compiles the cell ",
                "and model equations alone"
            )
        )
    )
end

# a condition as written: built-ins without their time argument (`kind`, not `kind(t)`),
# and a kind by its name (`kind == border`, not the number `kind == 2`)
function _bc_text(b, kinds)
    s = _builtin_text(string(b))
    return replace(
        s, r"kind (==|!=|≠) (\d+)" =>
            m -> begin
            op, n = match(r"kind (==|!=|≠) (\d+)", m).captures
            k = parse(Int, n)
            "kind $op " * (0 <= k < length(kinds) ? string(kinds[k + 1]) : n)
        end
    )
end

# `mtkcompile` of the model with its ODEs simplified and its components bound (`sys`)
function _compile_bound(
        authored::PottsSystem, sys::PottsSystem, ode_systems,
        initialization
    )
    _check_discrete_slots(sys)
    cell_terms = Tuple{Vector{Int}, Any}[]
    cluster_terms = Tuple{Vector{Int}, Any}[]
    contact_terms = Dict{Symbol, Any}()
    site_terms = Any[]
    edge_terms = Tuple{Symbol, Any}[]
    angle_terms = Tuple{Symbol, Any}[]
    relationships, edge_vars, edge_rel = _relationships(sys)
    copy_sites, copy_cells = _copy_written_vars(sys)
    for e in _p(sys, :energies)
        d = e.domain
        _located(sys, e) do
            _check_energy_geometry(e.expr)
            d isa Union{CellDomain, EdgeDomain, ContactDomain, AngleDomain} &&
                _check_copy_reads(e.expr, d, copy_sites, copy_cells)
            _check_energy_refs(e.expr, d)
            if d isa CellDomain
                0 in d.kinds &&
                    throw(PottsCompileError("cells(…) cannot include the medium kind \
                        (kind 0); list only cell kinds"))
                _check_names(e.expr, _CELL_ENERGY_BUILTINS, "a cell term")
                push!(cell_terms, (_all_kinds(sys, d.kinds), e.expr))
            elseif d isa ClusterDomain
                0 in d.kinds &&
                    throw(PottsCompileError("clusters(…) cannot include the medium kind \
                        (kind 0); list only cell kinds"))
                _check_names(e.expr, _CLUSTER_BUILTINS, "a cluster term")
                isempty(_gathers(e.expr)) || throw(
                    PottsCompileError(
                        "cluster terms reading neighbors are not supported; read \
                            neighbors in a `cells(…)` or `contacts` term instead"
                    )
                )
                push!(cluster_terms, (_all_kinds(sys, d.kinds), e.expr))
            elseif d isa ContactDomain
                _check_names(e.expr, _CONTACT_BUILTINS, "a contact term")
                _check_static(_strip_populations(e.expr)[1], "a contact term")
                E = _symmetrize(_cellvars_at_owner(e.expr))
                contact_terms[d.relation] = if haskey(contact_terms, d.relation)
                    contact_terms[d.relation] + E
                else
                    E
                end
            elseif d isa EdgeDomain
                haskey(edge_vars, d.relationship) ||
                    throw(PottsCompileError("edges($(d.relationship)): no \
                        @relationship $(d.relationship)"))
                _check_names(e.expr, _EDGE_BUILTINS, "an edge term")
                _check_static(_strip_populations(e.expr)[1], "an edge term")
                _check_edge_vars(
                    e.expr, d.relationship, edge_rel,
                    "edges($(d.relationship))"
                )
                push!(edge_terms, (d.relationship, e.expr))
            elseif d isa AngleDomain
                _check_angle_term(e.expr, d, relationships)
                push!(angle_terms, (d.relationship, e.expr))
            elseif d isa SiteDomain
                _check_names(e.expr, _SITE_BUILTINS, "a site term")
                _check_static(_strip_populations(e.expr)[1], "a site term")
                isempty(_gathers(e.expr)) || throw(
                    PottsCompileError(
                        "site terms reading neighbors are not supported yet; use a \
                            `contacts` term or snapshot in `@before_mcs`/`@after_mcs`"
                    )
                )
                push!(site_terms, e.expr)
            else
                throw(PottsCompileError("unknown energy domain `$d`; expected `cells(…)`, \
                    `clusters(…)`, `contacts(…)`, `edges(…)`, `angles(…)` or `sites`"))
            end
        end
    end
    # energies may read on-copy-written variables only where ΔH can apply the write (D-045):
    # cell terms at the written cell (`x[new]`, `x[old]`), site and contact terms (`x`,
    # `x′`) at the target
    for u in _p(sys, :updates)
        u.phase === :on_copy || continue
        lhs = _unwrap(u.eq.lhs)
        (iscall(lhs) && (operation(lhs) === value_at && length(arguments(lhs)) == 2)) ||
            continue
        x, idx = arguments(lhs)
        i = info(x)
        i === nothing && continue
        readers = Any[
            (E for (_, E) in cluster_terms)..., last.(edge_terms)..., last.(angle_terms)...,
            (
                if i.role === :cell
                    (site_terms..., values(contact_terms)...)
                else
                    last.(cell_terms)
                end
            )...,
        ]
        ok = _oncopy_side(i, idx) !== nothing
        if !ok
            readers = Any[
                readers..., last.(cell_terms)..., site_terms..., values(contact_terms)...,
            ]
        end
        any(E -> any(==((i.role, i.name)), _uses(E)), readers) && _located(sys, u) do
            throw(
                PottsCompileError(
                    "an energy reads `$(i.name)`, which this on-copy update writes; ΔH " *
                        "applies the write only for cell terms reading " *
                        "`$(i.name)[new]`/`[old]`, and site and contact terms reading a \
                            site variable written at the target"
                )
            )
        end
    end
    drive = isempty(_p(sys, :drives)) ? nothing : sum(d -> d.expr, _p(sys, :drives))
    for d in _p(sys, :drives)
        _located(
            () -> (
                _check_names(d.expr, _PROPOSAL_BUILTINS, "a drive");
                _check_ref_sources(d.expr, "drives")
            ),
            sys,
            d
        )
    end
    for c in _p(sys, :constraints)
        c.kind === :expr && _located(
            () -> (
                _check_names(c.expr, _PROPOSAL_BUILTINS, "a constraint");
                _check_ref_sources(c.expr, "constraints")
            ), sys, c
        )
    end
    _located(
        () -> _check_ref_sources(_p(sys, :sweep).temperature, "the @sweep temperature"),
        sys, _p(sys, :sweep)
    )

    # updates by phase and scope
    updates = Dict{Tuple{Symbol, Symbol}, Vector{Update}}()
    for u in _p(sys, :updates)
        lhs = _unwrap(u.eq.lhs)
        scope = _located(sys, u) do
            if u.phase === :on_copy
                (
                    iscall(lhs) &&
                        (operation(lhs) === value_at && length(arguments(lhs)) == 2)
                ) ||
                    throw(PottsCompileError("@on_copy updates assign at a site or cell, \
                        e.g. `act[target] ~ …`"))
                u.every == 1 ||
                    throw(PottsCompileError("`Every` does not apply to @on_copy updates: \
                        they run at every accepted copy"))
                _check_names(u.eq.rhs, _PROPOSAL_BUILTINS, "an on-copy update")
                _check_ref_sources(u.eq.rhs, "on-copy updates")
                _is_ref(arguments(lhs)[2]) && throw(
                    PottsCompileError(
                        "@on_copy writes `$(_indexed_string(lhs))` through a reference; " *
                            "an on-copy update writes at the copy's cells or sites \
                                (`x[new]`, `x[old]`, `x[target]`)"
                    )
                )
                _is_ref_var(arguments(lhs)[1]) &&
                    _check_ref_value(info(arguments(lhs)[1]).name, u.eq.rhs)
                :proposal
            else
                i = info(lhs)
                (i !== nothing && i.role in SCOPES) ||
                    throw(PottsCompileError("update target `$lhs` is not a declared \
                        variable"))
                if i.role === :edge
                    # once per existing link, in the environment of `edges(rel)` and
                    # `@unlink` (D-169)
                    _check_names(
                        u.eq.rhs, _LINK_BUILTINS, "an edge update";
                        between_copies = true
                    )
                    _has_op(u.eq.rhs, random_uniform) && throw(
                        PottsCompileError(
                            "`rand()` is not available in an edge update: draws are not \
                                addressed per link"
                        )
                    )
                    (
                        _has_op(u.eq.rhs, random_normal) ||
                            _has_op(u.eq.rhs, random_normal_above)
                    ) && throw(
                        PottsCompileError(
                            "`randn()` is not available in an edge update: draws are not \
                                addressed per link"
                        )
                    )
                    _check_edge_vars(
                        u.eq.rhs, edge_rel[i.name], edge_rel,
                        "an edge update of `$(i.name)($(edge_rel[i.name]))`"
                    )
                else
                    allowed = if i.role === :cell
                        _CELL_BUILTINS
                    elseif i.role === :model
                        (:mcs,)
                    else
                        _SITE_BUILTINS
                    end
                    _check_names(
                        u.eq.rhs, allowed, "a $(i.role) update";
                        between_copies = true
                    )
                    _is_ref_var(lhs) && _check_ref_value(i.name, u.eq.rhs)
                end
                i.role === :field ? :site : i.role
            end
        end
        push!(get!(updates, (u.phase, scope), Update[]), u)
    end

    # differential equations: fields (lattice PDEs) and per-cell ODEs
    fields = Tuple{Any, Any}[]
    field_aux = Tuple{Any, Any}[]                  # aux fields `K ~ rhs` (not stepped)
    cell_odes = Tuple{Any, Any}[]
    model_odes = Tuple{Any, Any}[]
    derivatives = Dict{Symbol, Any}()
    for eq in _p(sys, :equations)
        _located(sys, eq) do
            lhs = _unwrap(eq.lhs)
            # a map `Shift(t, 1)(m) ~ rhs` or an aux `K ~ rhs` of a field
            fl = _field_lhs(eq, sys)
            if fl !== nothing && fl[2] !== :rate
                x, kind = fl
                n = info(x).name
                haskey(derivatives, n) && throw(
                    PottsCompileError(
                        "`$n` is already given by `$(derivatives[n])`; one equation per \
                            field"
                    )
                )
                derivatives[n] = eq
                _check_names(
                    eq.rhs, (_SITE_BUILTINS..., :time),
                    kind === :map ? "a map" : "a field definition";
                    between_copies = true
                )
                push!(kind === :map ? fields : field_aux, (x, eq.rhs))
                return
            end
            steady = fl !== nothing && fl[3] === :steady
            steady || (iscall(lhs) && operation(lhs) isa Differential) || throw(
                PottsCompileError(
                    "equations are `D(x) ~ rhs` (a rate), `Shift(t, 1)(m) ~ rhs` (a map " *
                        "of a field), `K ~ rhs` (a field defined by its value) or `0 ~ \
                            rhs` (a steady field); got $eq"
                )
            )
            x = steady ? fl[1] : arguments(lhs)[1]
            i = info(x)
            i === nothing &&
                throw(PottsCompileError("`$x` is not a declared variable; declare it in \
                    `@variables`"))
            haskey(derivatives, i.name) && throw(
                PottsCompileError(
                    "`D($(i.name))` is already given by `$(derivatives[i.name])`; one \
                        equation per variable (add the terms)"
                )
            )
            derivatives[i.name] = eq
            if i.role === :field || i.role === :site
                # `time` reads the field's own time `t` (the window's start plus `j h` per
                # substep)
                _check_names(
                    eq.rhs, (_SITE_BUILTINS..., :time), "a field equation";
                    between_copies = true
                )
                push!(fields, (x, eq.rhs))
            elseif i.role === :cell
                _check_names(
                    eq.rhs, (_CELL_BUILTINS..., :time), "a cell equation";
                    between_copies = true
                )
                push!(cell_odes, (x, eq.rhs))
            elseif i.role === :model
                _check_names(
                    eq.rhs, (:mcs, :time), "a model equation";
                    between_copies = true
                )
                push!(model_odes, (x, eq.rhs))
            else
                throw(PottsCompileError("equations are for field, site, cell and model \
                    variables; `$x` is $(i.role)"))
            end
        end
    end
    for d in _p(sys, :divisions)
        _located(sys, d) do
            _check_names(
                d.when, _CELL_BUILTINS, "a division condition";
                between_copies = true
            )
            for (x, r) in d.rules
                _is_ref_var(x) || continue
                r isa Split && throw(
                    PottsCompileError(
                        "@divide: `$(info(x).name) => Split()` halves a number; " *
                            "`$(info(x).name)` is a reference (a `CellRef`)"
                    )
                )
                _check_ref_value(info(x).name, r)
            end
        end
    end
    # each rule divides by its own domain; a kind is divided by one domain only
    cluster_division = any(d -> d.domain isa ClusterDomain, _p(sys, :divisions))
    function domain_kinds(D)
        return unique(
            Iterators.flatten(
                isempty(d.domain.kinds) ? (1:(length(_p(sys, :kinds)) - 1)) : d.domain.kinds
                    for d in _p(sys, :divisions) if d.domain isa D
            )
        )
    end
    both = intersect(domain_kinds(CellDomain), domain_kinds(ClusterDomain))
    isempty(both) || throw(
        PottsCompileError(
            "kind$(length(both) == 1 ? "" : "s") " *
                join(("`$(_p(sys, :kinds)[k + 1])`" for k in sort(both)), ", ") *
                " divided by both @divide cells(…) and @divide clusters(…); a kind \
                    divides alone or with its cluster, not both"
        )
    )
    for r in _p(sys, :link_rules)
        _located(sys, r) do
            haskey(edge_vars, r.relationship) ||
                throw(PottsCompileError("@$(r.action) $(r.relationship): no \
                    @relationship $(r.relationship)"))
            _check_names(r.when, _LINK_BUILTINS, "a link rule"; between_copies = true)
            _check_edge_vars(
                r.when, r.relationship, edge_rel,
                "@$(r.action) $(r.relationship)"
            )
        end
    end

    # discrete components: a tick reads the pre-tick state, between copies
    for b in _p(sys, :discrete)
        _located(sys, b) do
            for x in b.next
                _check_names(
                    x, b.scope === :cell ? _CELL_BUILTINS : (:mcs,),
                    "a discrete component"; between_copies = true
                )
            end
        end
    end
    tick_exprs = Any[x for b in _p(sys, :discrete) for x in b.next]
    # site conversion passes (R8, D-233)
    converts = _p(sys, :converts)
    _check_converts(sys)
    convert_exprs = Any[x for v in converts for x in _convert_exprs(v)]

    # one writer per target, phase and cadence (combine contributions with `+=`)
    writers = Dict{Any, Update}()
    for u in _p(sys, :updates)
        k = (_target_key(u)..., u.every)
        haskey(writers, k) && _located(sys, u) do
            throw(
                PottsCompileError(
                    "`$(u.eq.lhs)` is already written " *
                        "@$(u.phase)$(u.every == 1 ? "" : " Every($(u.every))") by \
                            `$(writers[k].eq)`; combine contributions with `+=` or in one \
                            equation"
                )
            )
        end
        writers[k] = u
    end
    function geometric(x)
        return _has_op(x, cell_centroid) || _has_op(x, copy_displacement) ||
            _uses_builtin(x, :major_length) ||
            _has_op(x, ref_centroid) || _has_op(x, ref_separation)
    end
    needs_moments = !isempty(_p(sys, :divisions)) || !isempty(relationships) ||
        !isempty(converts) || any(
        geometric, Any[
            (e.expr for e in _p(sys, :energies))..., (
                d.expr
                    for d in _p(sys, :drives)
            )...,
            (u.eq.rhs for u in _p(sys, :updates))..., (
                eq.rhs
                    for eq in _p(sys, :equations)
            )...,
            (o.rhs for o in _p(sys, :observed))..., (
                c.expr
                    for c in _p(sys, :constraints) if c.kind === :expr
            )...,
            (r.when for r in _p(sys, :link_rules))..., _p(sys, :sweep).temperature,
            (
                r for d in _p(sys, :divisions)
                    for (_, r) in d.rules if !(r isa Split)
            )..., tick_exprs...,
            _bcs_exprs(sys)...,
        ]
    )

    # relations: contact (ctx.contact), surface, named, gathers
    contact_spec = get(_p(sys, :relations), :contact, _p(sys, :lattice).neighborhood)
    proposal_spec = _proposal_spec(sys)
    relations = Dict{Symbol, Any}()
    for (k, v) in _p(sys, :relations)
        # `contact` and `proposal` are declarable roles (split out above); the other names
        # CorePotts reserves are run-context fields, so a relation may not take them (the
        # fingerprint resolves every relation the code reads by its context name, D-124)
        k in (:lattice, :mobility, :spacing) && throw(
            PottsCompileError(
                "relation names `contact`, `proposal`, `lattice`, `mobility`, `spacing` \
                    are reserved"
            )
        )
        k in (:contact, :proposal) || (relations[k] = v)
    end
    for r in keys(contact_terms)
        r === :contact || haskey(relations, r) ||
            throw(PottsCompileError("contacts($r): relation `$r` is not declared in \
                @relations"))
    end
    gather_names = Dict{Any, Symbol}()
    all_exprs = Any[
        last.(cell_terms)..., last.(cluster_terms)..., values(contact_terms)...,
        site_terms...,
        (drive === nothing ? () : (drive,))..., (
            c.expr
                for c in _p(sys, :constraints) if c.kind === :expr
        )...,
        (u.eq.rhs for u in _p(sys, :updates))..., (last(f) for f in fields)..., (
            last(f)
                for f in field_aux
        )...,
        (last(f) for f in cell_odes)..., (last(f) for f in model_odes)...,
        _p(sys, :sweep).temperature, tick_exprs...,
    ]
    # everything evaluated against the state: the copy-step expressions, then the sites
    # evaluated outside the copy step (division conditions and rules, link rules, edge
    # energies, on-copy update indices) and observed quantities last. One list serves both
    # the tracker flags (A-35, order-free) and gather numbering (D-107: statement order, and
    # new sites append after the existing ones so their numbers stay; observed quantities
    # are not fingerprinted, D-124), so the two always cover the same sites.
    scanned = Any[
        all_exprs..., (d.when for d in _p(sys, :divisions))...,
        (r for d in _p(sys, :divisions) for (_, r) in d.rules if !(r isa Split))...,
        (r.when for r in _p(sys, :link_rules))..., last.(edge_terms)...,
        (u.eq.lhs for u in _p(sys, :updates) if u.phase === :on_copy)..., (
            o.rhs
                for o in _p(sys, :observed)
        )...,
        convert_exprs..., last.(angle_terms)...,
    ]
    _check_relationship_queries(scanned, relationships)
    uses_surface = any(x -> _uses_builtin(x, :surface), scanned)
    uses_cluster_surface = any(x -> _uses_builtin(x, :cluster_surface), scanned)
    uses_euler = any(x -> _uses_builtin(x, :euler), scanned)
    uses_euler_full = any(x -> _uses_builtin(x, :euler_full), scanned)
    # hex has one self-dual adjacency: `:full` reads the `:face` column and its shell (D-192
    # Q4)
    hex = core_lattice(_p(sys, :lattice)).geometry isa CP.Hexagonal
    euler_full_column = hex ? :euler : :euler_full
    if hex && uses_euler_full
        uses_euler, uses_euler_full = true, false
    end
    # cell-scope pieces: one tracker pair per adjacency read; hex has one adjacency
    uses_pieces = any(
        x -> _uses_builtin(x, :pieces) || _uses_builtin(x, :largest_piece),
        scanned
    )
    uses_pieces_full = any(
        x -> _uses_builtin(x, :pieces_full) || _uses_builtin(x, :largest_piece_full),
        scanned
    )
    if hex && uses_pieces_full
        uses_pieces, uses_pieces_full = true, false
    end
    # cell serials: read by `birth`, `sibling` (lowest birth) and every `@convert`
    # pass; the algebraic and initialization equations, the authored energies and drives
    # and the division planes are scanned too (lowered elsewhere, so a reader there keeps
    # the serials)
    reads_birth(x) = _uses_builtin(x, :birth) || _has_op(x, cluster_sibling)
    uses_birth = !isempty(converts) || any(reads_birth, scanned) || any(
        reads_birth, Any[
            (eq.rhs for eq in _p(sys, :equations))...,
            (eq.rhs for eq in _p(sys, :initialization_eqs))...,
            (e.expr for e in _p(sys, :energies))..., (
                d.expr
                    for d in _p(sys, :drives)
            )...,
            (c.expr for c in _p(sys, :constraints) if c.kind === :expr)...,
            (
                x for d in _p(sys, :divisions)
                    for x in (d.along isa Tuple ? d.along : (d.along,))
            )...,
        ]
    )
    (uses_pieces || uses_pieces_full) && !isempty(converts) && throw(
        PottsCompileError(
            "@convert $(first(converts).name): cell-scope `pieces`/`largest_piece` " *
                "trackers are not maintained by a conversion pass yet; a model with \
                    `@convert` cannot read them"
        )
    )
    uses_clusters = cluster_division || uses_cluster_surface ||
        any(v -> v.domain isa ClusterDomain, converts) || any(
        x -> _uses_builtin(x, :cluster) ||
            _uses_builtin(x, :cluster_volume) ||
            _has_op(x, cluster_integral_sum), scanned
    )
    (uses_surface || uses_cluster_surface) && !haskey(relations, :surface) &&
        (relations[:surface] = _p(sys, :lattice).neighborhood)
    radius_read = 1
    # gather relations numbered in `scanned` order and, within one, by content (D-107)
    for x in scanned
        specs = unique!(
            Any[
                ni.options.relation
                    for (ni, _) in _gathers(x)
                    if !(ni.options.relation isa Union{RelationRef, ShellRelation}) &&
                    !haskey(gather_names, ni.options.relation)
            ]
        )
        # D-130
        ckeys = map(
            r -> _canonical_checked(() -> "the relation `$(_key_string(r))`", r),
            specs
        )
        for spec in specs[sortperm(ckeys)]
            gather_names[spec] = Symbol(:gather, length(gather_names) + 1)
            relations[gather_names[spec]] = spec
        end
    end

    # footprint: largest distance from the target read by the per-copy functions
    lat = core_lattice(_p(sys, :lattice))
    rad(spec) = CP.radius(CP.relation(spec, lat))
    isempty(contact_terms) || (
        radius_read = max(
            radius_read,
            maximum(
                r -> rad(r === :contact ? contact_spec : relations[r]),
                keys(contact_terms)
            )
        )
    )
    (uses_surface || uses_cluster_surface) &&
        (radius_read = max(radius_read, rad(relations[:surface])))
    # D-150
    fold_radius, contact_trackers = _check_contact_folds(sys, relations, contact_spec, lat)
    radius_read = max(radius_read, fold_radius)
    # per-copy reads anchored at the target count from it; at the source, from the source
    # (CorePotts adds the proposal radius: `reach`)
    source_read = -1
    source_write = -1
    oncopy = get(updates, (:on_copy, :proposal), Update[])
    for x in Any[
            (drive === nothing ? () : (drive,))..., (
                c.expr
                    for c in _p(sys, :constraints) if c.kind === :expr
            )...,
            (u.eq.rhs for u in oncopy)..., (u.eq.lhs for u in oncopy)...,
            _p(sys, :sweep).temperature,
        ]
        for (ni, anchor) in _gathers(x)
            spec = ni.options.relation
            r = if spec isa ShellRelation
                1
            else
                rad(spec isa RelationRef ? _p(sys, :relations)[spec.name] : spec)
            end
            if _uses_builtin(anchor, :source)
                source_read = max(source_read, r)
            else
                radius_read = max(radius_read, r)
            end
        end
    end
    # `act[source] ~ …` writes at the source
    for u in oncopy
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
    angle_terms = Any[snap(E) for E in angle_terms]
    update_pops = Pair{Symbol, Any}[]
    schedule = Dict{Symbol, Vector{Stage}}()
    pre_snapshots = Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}()
    for ph in (:before_mcs, :after_mcs)
        schedule[ph], pre_snapshots[ph] = _schedule_block(
            sys, Update[u for u in _p(sys, :updates) if u.phase === ph],
            gather_names, update_pops
        )
    end
    # folds hoisted out of integral operands: model slots too, computed by the integrals'
    # refresh
    for fs in last(_integrals_folds(sys; observed = true)), sl in fs
        any(q -> q.first === sl.first, update_pops) || push!(update_pops, sl)
    end
    cell_ode_pops = Pair{Symbol, Any}[]
    cell_odes = Tuple{Any, Any}[
        (
            x,
            _hoist_populations(r, cell_ode_pops, gather_names, :__odepop),
        )
            for (x, r) in cell_odes
    ]
    # folds in a cell-scope tick are computed once per tick, before it (as for cell ODEs)
    discrete_pops = Pair{Symbol, Any}[]
    function hoisted(b)
        b.scope === :cell || return b
        return DiscreteBlock(
            b.name, b.scope, b.kinds, b.slots,
            Any[
                _hoist_populations(x, discrete_pops, gather_names, :__tickpop)
                    for x in b.next
            ], b.every, b.offset
        )
    end
    discrete = DiscreteBlock[hoisted(b) for b in _p(sys, :discrete)]

    _dry_lower(sys, gather_names, fields, cell_odes)
    _check_algebraic_lowering(sys, gather_names)
    fieldsys, field_specs = _check_fields(sys, gather_names)
    isempty(_p(sys, :schedule)) || _placed_schedule(_p(sys, :schedule), _convert_names(sys))
    _check_units(sys)

    # the lowered model's inner System is rebuilt from its lowered payload, so MTK's
    # accessors on `Potts.inner(csys)` list what the lowering kept (an eliminated algebraic
    # variable is observed)
    fsys = something(fieldsys, getfield(sys, :fields), Some(nothing))
    # the PDESystem's digest is recorded in the payload, so the compiled `sys` composes
    # again
    fsys === nothing || (
        sys = _replace(
            sys;
            metadata = Base.ImmutableDict(
                _p(sys, :metadata), _FieldsFrom =>
                    _pde_digest(fsys)
            )
        )
    )
    sys = _wrap_payload(nameof(sys), fsys, getfield(sys, :part))
    return CompiledPottsSystem(
        sys, cell_terms, cluster_terms, contact_terms, site_terms, drive,
        _p(sys, :constraints), updates, fields, cell_odes, model_odes,
        _p(sys, :divisions), relationships, edge_terms, angle_terms, edge_vars,
        _p(sys, :link_rules), uses_surface, uses_clusters, uses_cluster_surface, uses_euler,
        uses_euler_full,
        euler_full_column, cluster_division,
        needs_moments, relations, contact_spec, proposal_spec, gather_names,
        Footprint(; read = radius_read, source_read, source_write),
        scratch, schedule, pre_snapshots, update_pops, energy_snapshots,
        cell_ode_pops, discrete, discrete_pops,
        contact_trackers, authored, ode_systems, initialization, uses_pieces,
        uses_pieces_full, hex, uses_birth, field_specs
    )
end

# ---------------------------------------------------------------------------------------
# Site conversion passes (R8, D-233)

_convert_names(sys::PottsSystem) = Symbol[v.name for v in _p(sys, :converts)]

# the expressions of a pass, as they are evaluated against the state (tracker flags,
# gathers)
function _convert_exprs(v::ConvertSpec)
    return Any[
        v.from, v.to, (v.at isa Bool ? () : (v.at,))..., v.p,
        (x for t in v.transfers for x in (t.from, t.to, t.per_site))..., (
            x
                for (a, b) in v.writes for x in (a, b)
        )...,
    ]
end

const _CONVERT_SITE_BUILTINS = (_SITE_BUILTINS..., :from, :to)

# Names, scopes and kinds of the `@convert` passes: each pass is a phase of the MCS, so its
# name is none of the canonical phases and no two passes share one; `from`/`to` are
# references in the entity's scope; `at`/`p` site expressions (with `from`, `to`); the
# writes add to a model variable or to a cell variable of a cell (with `created`); no draws
# (the pass's one draw per site is its own). With frozen kinds, the cells a pass moves sites
# between are `sibling(k)` of non-frozen kinds (the frozen mask then never changes).
function _check_converts(sys::PottsSystem)
    seen = Set{Symbol}()
    kinds = _p(sys, :kinds)
    for v in _p(sys, :converts)
        _located(sys, v) do
            v.name in SCHEDULE_PHASES && throw(
                PottsCompileError(
                    "@convert $(v.name): `$(v.name)` is a phase of the MCS (the phases " *
                        "are $(join(SCHEDULE_PHASES, ", "))); name the pass otherwise"
                )
            )
            v.name in seen &&
                throw(PottsCompileError("@convert $(v.name): two passes are named \
                    `$(v.name)`; name each once"))
            push!(seen, v.name)
            for k in v.domain.kinds
                1 <= k < length(kinds) || throw(
                    PottsCompileError(
                        "@convert $(v.name): kind number $k is not a cell kind (cell \
                            kinds are 1:$(length(kinds) - 1))"
                    )
                )
            end
            v.fresh == 0 || 1 <= v.fresh < length(kinds) || throw(
                PottsCompileError(
                    "@convert $(v.name): `Fresh($(v.fresh))` is not a cell kind (cell \
                        kinds are 1:$(length(kinds) - 1))"
                )
            )
            for x in _convert_exprs(v)
                (
                    _has_op(x, random_uniform) || _has_op(x, random_normal) ||
                        _has_op(x, random_normal_above)
                ) && throw(
                    PottsCompileError(
                        "@convert $(v.name): `rand()`/`randn()` are not available in a " *
                            "conversion pass (each candidate's draw is the pass's own, `u \
                                < p`)"
                    )
                )
            end
            for (what, r) in (("from", v.from), ("to", v.to))
                _check_names(
                    r, _CELL_BUILTINS, "`$what` of @convert $(v.name)";
                    between_copies = true
                )
            end
            v.at isa Bool ||
                _check_names(v.at, _CONVERT_SITE_BUILTINS, "`at` of \
                    @convert $(v.name)"; between_copies = true)
            _check_names(
                v.p, _CONVERT_SITE_BUILTINS, "`p` of @convert $(v.name)";
                between_copies = true
            )
            for t in v.transfers
                _check_names(
                    t.per_site, (_CELL_BUILTINS..., :from, :to),
                    "a transfer of @convert $(v.name)"; between_copies = true
                )
                for r in (t.from, t.to)
                    _is_ref(r) ||
                        throw(PottsCompileError("@convert $(v.name): a transfer moves \
                            between cells, `from => to`; got `$r`"))
                end
            end
            for (lhs, d) in v.writes
                i = info(lhs)
                if i !== nothing
                    i.role === :model || throw(
                        PottsCompileError(
                            "@convert $(v.name): `$(i.name) += …` writes a model " *
                                "variable; write a cell variable at a cell, \
                                    `$(i.name)[to] += …`"
                        )
                    )
                else
                    (
                        iscall(lhs) &&
                            (operation(lhs) === value_at && length(arguments(lhs)) == 2) &&
                            (
                            xi = info(arguments(lhs)[1]); xi !== nothing &&
                                xi.role === :cell &&
                                get(xi.options, :reference, false) !==
                                true
                        )
                    ) || throw(
                        PottsCompileError(
                            "@convert $(v.name): a write adds to a model variable (`m += " *
                                "…`) or to a cell variable at a cell (`x[to] += …`); got \
                                    `$(_indexed_string(lhs))`"
                        )
                    )
                    _check_names(
                        arguments(lhs)[2], _CONVERT_SITE_BUILTINS,
                        "a write of @convert $(v.name)"; between_copies = true
                    )
                    _is_ref(arguments(lhs)[2]) || throw(
                        PottsCompileError(
                            "@convert $(v.name): a write adds to a cell variable at a " *
                                "cell named by a reference (`from`, `to`, `sibling(k)`, a \
                                    `CellRef`); got `$(_indexed_string(lhs))`"
                        )
                    )
                end
                _check_names(
                    d, (_CONVERT_SITE_BUILTINS..., :created),
                    "a write of @convert $(v.name)"; between_copies = true
                )
            end
            _check_convert_order(v)
            if !isempty(_p(sys, :frozen_kinds))
                fz = _p(sys, :frozen_kinds)
                ks = Int[
                    v.fresh, (_implicit_fresh(r) for r in (v.from, v.to))...,
                    v.domain.kinds...,
                ]
                (
                    _implicit_fresh(v.from) > 0 && _implicit_fresh(v.to) > 0 &&
                        !any(in(fz), ks)
                ) || throw(
                    PottsCompileError(
                        "@convert $(v.name): with frozen kinds, `from` and `to` are " *
                            "`sibling(k)` of kinds that are not frozen (a conversion must \
                                not change the frozen sites)"
                    )
                )
            end
        end
    end
    return nothing
end

# The transfers and writes of a pass run in parallel, once per entity or converted site, so
# none of their expressions (amounts, indices, the referents they name) may read a variable
# the pass transfers or writes: the value read would depend on the order of the atomics.
function _check_convert_order(v::ConvertSpec)
    written = Set{Symbol}(info(t.var).name for t in v.transfers)
    for (lhs, _) in v.writes
        i = info(lhs)
        push!(written, i !== nothing ? i.name : info(arguments(lhs)[1]).name)
    end
    isempty(written) && return nothing
    reads = Any[]
    for t in v.transfers
        push!(reads, t.per_site, t.from, t.to)
    end
    for (lhs, d) in v.writes
        push!(reads, d)
        info(lhs) === nothing && push!(reads, arguments(lhs)[2])
    end
    for x in reads
        _walk(x) do y
            i = info(y)
            (i !== nothing && i.role in (:cell, :model) && i.name in written) || return
            throw(
                PottsCompileError(
                    "@convert $(v.name): a transfer or write reads `$(i.name)`, which " *
                        "the pass itself transfers or writes; the value read would " *
                        "depend on the order of the parallel updates. Read a snapshot \
                            (`@after_mcs`) or another variable instead"
                )
            )
        end
    end
    return nothing
end

# the proposal neighbourhood: `@relations proposal = …`, or `VonNeumann(1)`
function _proposal_spec(sys::PottsSystem)
    return get(_p(sys, :relations), :proposal, CorePotts.VonNeumann(1))
end

# The field equations and conditions as a `PDESystem`, lowered once through
# LatticePDE's `lower_group` (in Float64) so that a term the field compiler cannot lower is
# an error here, with the CPM inputs dry-lowered in site scope. Returns the PDESystem and
# the cache of lowered groups (`CompiledPottsSystem.field_specs`) holding the group of all
# fields, which a `PottsProblem` with one group in Float64 reuses; `nothing` and an empty
# cache for a model without fields.
function _check_fields(sys::PottsSystem, rn)
    specs = Dict{Any, Any}()
    eqs = _field_equations(sys)
    # a condition sets a stepped field (never dropped)
    isempty(eqs) && !isempty(_p(sys, :bcs)) &&
        _located(sys, _BcsLine(first(_p(sys, :bcs)))) do
        throw(
            PottsCompileError(
                string(
                    "the condition `", _bc_text(first(_p(sys, :bcs)), _p(sys, :kinds)),
                    "` of `",
                    nameof(sys), "`: the model has no field equation (`Differential(t)(c(",
                    join(
                        ("t", "x", "y", "z")[1:(length(_p(sys, :lattice).dims) + 1)],
                        ", "
                    ),
                    ")) ~ …`); a condition applies to a field the model steps"
                )
            )
        )
    end
    # a model whose only fields are aux fields `K ~ rhs` has one group with no state, which
    # evaluates them once per MCS
    isempty(eqs) && isempty(_field_aux(sys)) && return nothing, specs
    known = _located(
        () -> _field_inputs(sys, Float64), sys,
        _field_equation_of(sys, nothing)
    )
    names = Symbol[info(x).name for (x, _) in eqs]
    # (the stability bound is built at the first problem: `mtkcompile` only checks the
    # lowering) a refusal of the lowering names the equation it was lowering (LatticePDE's
    # note)
    delete!(task_local_storage(), :lattice_equation)
    g = try
        _lower_field_group(sys, names, Float64; known, bound = false)
    catch e
        k = pop!(task_local_storage(), :lattice_equation, nothing)
        e isa Union{ArgumentError, PottsCompileError, LatticeFields.IR.IRError} || rethrow()
        _located(() -> throw(e), sys, _field_equation_of(sys, k))
    finally
        delete!(task_local_storage(), :lattice_equation)
    end
    env = _site_env(Float64, :i, rn; mcs = :mcs, key = :key)
    foreach(e -> _fill_value(e[2], env), g.filled)
    specs[(:inputs, Float64)] = known
    specs[(names, Float64)] = g
    return g.pdesys, specs
end

# the equation of the field with key `k` (`"c"`, `"u[1]"`); with no key or no such field,
# the one field equation, else the fields' PDESystem as a whole (`_FieldSystemLine`; not the
# model's first equation, which may be a cell ODE)
function _field_equation_of(sys::PottsSystem, k)
    eqs = [
        eq
            for eq in _p(sys, :equations)
            if (f = _field_lhs(eq, sys); f !== nothing && f[1] !== nothing)
    ]
    if k !== nothing
        name = first(split(k, '['))
        i = findfirst(eq -> string(info(_field_lhs(eq, sys)[1]).name) == name, eqs)
        i === nothing || return eqs[i]
    end
    return length(eqs) == 1 ? only(eqs) : _FieldSystemLine()
end
# the fields' PDESystem as a whole, as a located statement
struct _FieldSystemLine end
_describe_text(::_FieldSystemLine, kinds = nothing) = "the fields' PDESystem"

# A slot of a discrete component is written by its ticks only.
function _check_discrete_slots(sys)
    isempty(_p(sys, :discrete)) && return nothing
    slots = Dict{Symbol, Symbol}(
        info(x).name => b.name for b in _p(sys, :discrete)
            for x in b.slots
    )
    function target(lhs)
        x = _standin_var(lhs)
        return if iscall(x) && (
                (operation(x) === value_at && length(arguments(x)) == 2) ||
                    operation(x) isa Differential
            )
            _standin_var(arguments(x)[1])
        else
            x
        end
    end
    for s in Iterators.flatten((_p(sys, :updates), _p(sys, :equations)))
        lhs = _unwrap(s isa Update ? s.eq.lhs : s.lhs)
        i = info(target(lhs))
        (i !== nothing && haskey(slots, i.name)) || continue
        _located(sys, s) do
            throw(
                PottsCompileError(
                    "`$(i.name)` is a node of the discrete component `$(slots[i.name])`: " *
                        "only its ticks write it (no updates or equations for it)"
                )
            )
        end
    end
    return nothing
end

# A kind filter naming every cell kind is no filter (the generated code skips the test).
function _all_kinds(sys::PottsSystem, kinds)
    return sort(unique(kinds)) == 1:(length(_p(sys, :kinds)) - 1) ? Int[] : kinds
end

# Quantities a copy changes cannot appear in contact, site or edge terms: their deltas are
# derived only for cell terms.
function _check_static(x, what)
    for n in (
            :volume, :surface, :cluster_volume, :cluster_surface, :euler, :euler_full,
            _PIECES_NAMES...,
        )
        _uses_builtin(x, n) &&
            throw(PottsCompileError("`$n` changes with the copy; it can only appear in \
                cell terms, not in $what"))
    end
    return nothing
end

# Cell, edge and contact energies read only what a copy changes in ways ΔH applies (D-209).
# ΔH evaluates a cell term for the copy's two cells with their own `volume`, `surface`, …
# substituted, an edge term on their links, and a contact term on the pairs at the target.
# So σ read anywhere else (`owner[i]`, `kind[i]`, `x[owner[i]]`, in a gather body, filter or
# anchor, or at an explicit site), an indexed copy-varying cell quantity (`volume[id]`,
# `y[id]` with `@on_copy y[…]`), or a copy-written site variable in a gather would change
# `H` without entering ΔH.

# site and field variables a copy writes (by an `@on_copy` update, or cleared on a change of
# ownership), and cell variables written by an `@on_copy` update
function _copy_written_vars(sys::PottsSystem)
    sites, cells = Set{Symbol}(), Set{Symbol}()
    for x in _p(sys, :variables)
        i = info(x)
        i !== nothing && i.role in (:site, :field) &&
            get(i.options, :clear_on_ownership_change, false) === true &&
            push!(sites, i.name)
    end
    for u in _p(sys, :updates)
        u.phase === :on_copy || continue
        lhs = _unwrap(u.eq.lhs)
        (iscall(lhs) && (operation(lhs) === value_at && length(arguments(lhs)) == 2)) ||
            continue
        i = info(arguments(lhs)[1])
        i === nothing && continue
        i.role in (:site, :field) && push!(sites, i.name)
        i.role === :cell && push!(cells, i.name)
    end
    return sites, cells
end

# the bound variable of a population fold (`for c in cells`, `for s in sites`): reads at it
# are exact (D-041), so they are exempt
_pop_bound(x) = (i = info(x); i !== nothing && i.role in (:bound_cell, :bound_site))
# `owner[…]` or `kind[…]`: σ at a site (not at a population fold's bound variable)
# (`kind[ref]` reads the referent's kind column, not σ: R6)
function _is_sigma_at(y)
    return iscall(y) && (operation(y) === value_at && length(arguments(y)) == 2) &&
        !_pop_bound(arguments(y)[2]) && !_is_ref(arguments(y)[2]) &&
        (
        i = info(arguments(y)[1]);
        i !== nothing && i.role === :builtin && i.name in (:owner, :kind)
    )
end
function _reads_sigma(x)
    (found = Ref(false); _walk(y -> (_is_sigma_at(y) && (found[] = true)), x); found[])
end
# cell builtins a copy changes, which ΔH substitutes only when read bare
const _COPY_VARYING_INDEXED = (:volume, :surface, :euler, :euler_full, _PIECES_NAMES...)
# an explicit site index: not a pair's own site (`x′` is `x[neighbor_site]`), not a bound
# variable
function _explicit_index(i)
    r = info(i)
    return r === nothing || !(
        r.role in (:bound, :bound_cell, :bound_site) ||
            (r.role === :builtin && r.name in (:site, :neighbor_site))
    )
end

# The first read in `x` that a copy changes (outermost first), as (read as written, bare
# form to suggest or `nothing`), or `nothing`. `sites`: copy-written site variables, refused
# at any index and bare (`:all`, in fold bodies) or at an explicit index only (`:explicit`),
# or not checked (`nothing`); `cells`: on-copy cell variables (`nothing`: indexed cell
# quantities not checked).
function _copy_varying_read(x, sites, cells; mode = :all)
    hit = Ref{Any}(nothing)
    bare = Ref{Any}(nothing)
    _walk(x) do y
        hit[] === nothing || return
        if iscall(y) && (operation(y) === value_at && length(arguments(y)) == 2)
            a = arguments(y)
            i = info(a[1])
            if _is_sigma_at(y) || _reads_sigma(a[2])
                # `x[owner[i]]`, `owner[i]`, `kind[i]`
                hit[] = y
                # `kind[id]`: the cell's own kind, read bare
                i.name === :kind &&
                    (
                    r = info(a[2]);
                    r !== nothing && r.role === :builtin && r.name === :id
                ) &&
                    (bare[] = "kind")
            elseif i !== nothing && sites !== nothing && i.role in (:site, :field) &&
                    i.name in sites &&
                    (mode === :all || _explicit_index(a[2]))
                hit[] = y                                 # `act[n]`, `act[40]`
            elseif i !== nothing && cells !== nothing && !_pop_bound(a[2]) &&
                    (
                    (i.role === :builtin && i.name in _COPY_VARYING_INDEXED) ||
                        (i.role === :cell && i.name in cells)
                )
                # `volume[id]`, `y[id]` with `@on_copy y[…]`
                hit[] = y
                # `volume[partner]` (R6)
                bare[] = _is_ref(a[2]) ? :reference : _authored_name(i)
            end
        elseif iscall(y) && operation(y) === value_at && length(arguments(y)) == 3 &&
                any(_reads_sigma, arguments(y)[2:end])
            hit[] = y                                     # `J[kind[n], …]`
        elseif sites !== nothing && mode === :all
            i = info(y)
            i !== nothing && i.role in (:site, :field) && i.name in sites && (hit[] = y)
        end
    end
    hit[] === nothing && return nothing
    # bound variables as authored
    return replace(_indexed_string(hit[]), r"\b([a-z])_\d+\b" => s"\1"), bare[]
end

# a scoped variable or builtin by its authored name: `y`, not `y(t)`; a vector component
# `v[1]`
function _authored_name(i)
    v = get(i.options, :vector, nothing)
    v === nothing && return string(i.name)
    k = get(i.options, :index, nothing)
    return k === nothing ? string(v) : string(v, "[", k, "]")
end

# `x[i]`, `J[i, j]` as authored (not `Potts.at(x(t), i)`)
function _indexed_string(x)
    x = _unwrap(x)
    if x isa SymbolicUtils.BasicSymbolic && iscall(x) && operation(x) === value_at
        a = arguments(x)
        return string(
            _indexed_string(a[1]), "[",
            join(map(_indexed_string, a[2:end]), ", "), "]"
        )
    end
    i = info(x)
    i !== nothing && (i.role in SCOPES || i.role in (:builtin, :parameter, :kindtable)) &&
        return _authored_name(i)
    return string(x)
end

function _copy_read_error(s, bare, where)
    bare === :reference && return PottsCompileError(
        "this energy reads `$s`$where through a reference, which a copy changes during " *
            "the sweep; ΔH evaluates the term only for the copy's two cells, so a change " *
            "of the referent by another copy would be missing from it. Through a " *
            "reference a cell energy reads only what no copy changes: cell variables no " *
            "@on_copy update writes, `kind`, `birth`, `alive(ref)`. Read it in a " *
            "`@drive` (evaluated per copy, e.g. `volume[partner[old]]`, the referent's \
                current value) or snapshot it with `@after_mcs` (a cell variable `v ~ $s`, \
                read bare as `v` in the energy)"
    )
    hint = if bare === nothing
        ""
    else
        " Read the cell's own value bare, as `$bare`: ΔH updates it for the copy's cells."
    end
    return PottsCompileError(
        "this energy reads `$s`$where, which a copy changes; ΔH evaluates the term only " *
            "where the copy acts (its two cells with their own `volume`, `surface`, …; " *
            "their links; the pairs at the target), so the change would be missing from " *
            "it.$hint A fold over a relation, its anchor and any explicit site in a " *
            "cell, edge or contact energy may read static values only: a site variable " *
            "no copy writes (a static field), a parameter, a constant, `id`, or the edge \
                ends `a`, `b` compared with static values. To respond to the ownership \
                around a copy, use a `@drive` (it reads `owner`, `kind` at the copy)"
    )
end

# D-209: refuse a term of domain `d` that reads something a copy changes beyond what ΔH
# applies
function _check_copy_reads(E, d, sites, cells)
    # σ at an explicit site, anywhere in the term (cell and edge terms have no site of their
    # own; a contact term's pair is the bare `owner`, `neighbor_owner`, `kind`,
    # `neighbor_kind`), indexed copy-varying cell quantities in cell terms, and copy-written
    # site variables at an explicit site, in every domain (a contact term's bare `x`, `x′`
    # read the pair and stay allowed)
    r = _copy_varying_read(
        E, sites, d isa Union{CellDomain, AngleDomain} ? cells : nothing; mode = :explicit
    )
    r === nothing || throw(_copy_read_error(r..., ""))
    # gather bodies and filters: also copy-written site variables
    _walk(E) do y
        (iscall(y) && operation(y) === gather) || return
        _, _, body, cond = arguments(y)
        r = something(
            _copy_varying_read(body, sites, nothing),
            _copy_varying_read(cond, sites, nothing), Some(nothing)
        )
        r === nothing || throw(_copy_read_error(r..., " in a fold over a relation"))
    end
    return nothing
end

# Cell references in energies (R6, D-231): a cell term reads its referents' static values
# (`_check_copy_reads` refuses the copy-varying ones) and `root(…)`; `sibling` and `members`
# read every cell of a cluster (refused, `_check_ref_sources`); other domains read none.
function _check_energy_refs(E, d)
    d isa CellDomain && return _check_ref_sources(E, "energies")
    (
        _mentions_refs(E) || _has_op(E, as_ref) || _has_op(E, cluster_sibling) ||
            _has_op(E, outer_value)
    ) && throw(
        PottsCompileError(
            "this energy reads a cell through a reference; references are read in cell " *
                "energies (`cells(…) => …`), drives and constraints, not in \
                    $(_domain_string(d)) terms"
        )
    )
    return nothing
end

# `sibling` and `members` scan a whole cluster, which a copy changes: they are sources
# of the cell scope (updates, division conditions and rules, `@observed`), not of the sweep
function _check_ref_sources(x, what)
    (_has_op(x, cluster_sibling) || _has_op(x, outer_value)) && throw(
        PottsCompileError(
            "`sibling(…)` and `members(…)` read every cell of a cluster, which a copy " *
                "changes; they are available in cell updates, division conditions and " *
                "rules and @observed, not in $what. Keep the reference in a `CellRef` \
                    variable updated between sweeps (`@after_mcs nuc ~ sibling(nucleus)`) \
                    and read through it"
        )
    )
    return nothing
end

# A `CellRef` is written with a cell id: a reference, `id`, `old`/`new`, `cluster`, an
# integer (0: none), or a choice between them
function _check_ref_value(name, x)
    _ref_valued(x) || throw(
        PottsCompileError(
            "`$name` is a reference (a `CellRef`); it is written with a cell: another " *
                "reference, `sibling(k)`, `root(cluster)`, `id`, `old`, `new`, `cluster`, \
                    a cell id or 0, or `ifelse` between them; got `$x`"
        )
    )
    return nothing
end
function _ref_valued(x)
    x = _unwrap(x)
    x isa Integer && !(x isa Bool) && return x >= 0
    x isa SymbolicUtils.BasicSymbolic || return false
    SymbolicUtils.isconst(x) && return _ref_valued(SymbolicUtils.unwrap_const(x))
    _is_ref(x) && return true
    i = info(x)
    i !== nothing && return i.role === :builtin && i.name in (:id, :old, :new, :cluster) ||
        i.role === :bound_cell
    iscall(x) || return false
    op = operation(x)
    op isa ModelingToolkitBase.Pre && return _ref_valued(arguments(x)[1])
    op === ifelse && return _ref_valued(arguments(x)[2]) && _ref_valued(arguments(x)[3])
    # `cluster[c]`, `owner[s]`
    if op === value_at && length(arguments(x)) == 2
        a = info(arguments(x)[1])
        return a !== nothing && a.role === :builtin && a.name in (:cluster, :owner)
    end
    return false
end

# In a contact term a bare cell variable means its value at the owner (`x[owner]`) and a
# bare site variable its value at the pair's first site (`x[site]`; `x′` is
# `x[neighbor_site]`), so that mirroring (owner ↔ neighbor_owner, site ↔ neighbor_site) sees
# them.
function _cellvars_at_owner(E)
    sub = Dict{Any, Any}()
    for x in _bare_vars(E)
        i = info(x)
        i.role === :cell && (sub[x] = _unwrap(value_at(Symbolics.wrap(x), B.owner)))
        i.role in (:site, :field) && (sub[x] = _unwrap(value_at(Symbolics.wrap(x), B.site)))
    end
    isempty(sub) && return E
    return Symbolics.substitute(E, sub; fold = Val(false), filterer = _pair_scope)
end
function _not_indexed(ex)
    return !(iscall(ex) && operation(ex) === value_at) &&
        SymbolicUtils.default_substitute_filter(ex)
end
# the pair's names, not inside a population fold (its body reads the bound cell or site)
function _outside_population(ex)
    return !(iscall(ex) && operation(ex) === population) &&
        SymbolicUtils.default_substitute_filter(ex)
end
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
        skip = operation(x) === value_at
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
# with its mirror (kind ↔ neighbor_kind, owner ↔ neighbor_owner, site ↔ neighbor_site).
# Kind tables used in contact terms must be symmetric (checked against their values when the
# problem is built), so their entries are compared up to index order.
function _symmetrize(E)
    swap = Dict(
        _unwrap(B.kind) => _unwrap(B.neighbor_kind), _unwrap(B.neighbor_kind) =>
            _unwrap(B.kind),
        _unwrap(B.owner) => _unwrap(B.neighbor_owner), _unwrap(B.neighbor_owner) =>
            _unwrap(B.owner),
        _unwrap(B.site) => _unwrap(B.neighbor_site), _unwrap(B.neighbor_site) =>
            _unwrap(B.site)
    )
    M = Symbolics.substitute(E, swap; fold = Val(false), filterer = _outside_population)
    flips = Dict{Any, Any}()
    _walk(M) do y
        if iscall(y) && operation(y) === value_at && length(arguments(y)) == 3 &&
                role(arguments(y)[1]) === :kindtable
            J, a, b = arguments(y)
            flips[y] = _unwrap(
                value_at(Symbolics.wrap(J), Symbolics.wrap(b), Symbolics.wrap(a))
            )
        end
    end
    M = isempty(flips) ? M : Symbolics.substitute(M, flips; fold = Val(false))
    return isequal(Symbolics.simplify(E - M), 0) ? E : (E + M) / 2
end

"""Kind tables referenced by contact terms (their values must be symmetric)."""
function _contact_tables(c::CompiledPottsSystem)
    out = Set{Symbol}()
    for E in values(getfield(c, :contact_terms))
        _walk(y -> (role(y) === :kindtable && push!(out, info(y).name)), E)
    end
    return out
end

# Copy delta of a cell (or cluster) term for one side: E(q + δq) − E(q), expanded when that
# is cheaper.
function _cell_delta(E, dv::Int; after = Dict{Any, Any}())
    sub = Dict{Any, Any}(
        _unwrap(B.volume) => B.volume + dv, _unwrap(B.surface) => B.surface + DSURFACE,
        _unwrap(B.cluster_volume) => B.cluster_volume + dv,
        _unwrap(B.cluster_surface) => B.cluster_surface + DCSURFACE,
        _unwrap(B.major_length) =>
            DMAJOR,
        _unwrap(B.euler) => B.euler + DEULER, _unwrap(B.euler_full) =>
            B.euler_full + DEULER_FULL,
        # not deltas: the exact after-values of the copy
        _unwrap(B.pieces) => DPIECES, _unwrap(B.largest_piece) => DLARGEST,
        _unwrap(B.pieces_full) => DPIECES_FULL, _unwrap(B.largest_piece_full) =>
            DLARGEST_FULL, after...
    )
    naive = Symbolics.substitute(E, sub; fold = Val(false)) - E
    # `expand` rebuilds call terms, which strips the metadata of scoped variables and
    # built-ins `x(t)`: expand over placeholders instead
    hide, show = Dict{Any, Any}(), Dict{Any, Any}()
    _walk(naive) do y
        i = info(y)
        if _is_quantity_call(i) && !haskey(hide, y)
            p = _sym(Symbol(:__scoped_, length(hide) + 1))
            hide[y] = p
            show[p] = y
        end
    end
    expanded = Symbolics.expand(
        if isempty(hide)
            naive
        else
            Symbolics.substitute(naive, hide; fold = Val(false))
        end
    )
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
function _located(f, sys::PottsSystem, x; compile::Bool = true)
    try
        return f()
    catch e
        e isa Union{ArgumentError, PottsCompileError, LatticeFields.IR.IRError} || rethrow()
        occursin("\n  in ", e.msg) && rethrow()
        function wrap(m)
            throw(
                if compile ||
                        e isa Union{PottsCompileError, LatticeFields.IR.IRError}
                    PottsCompileError(m)
                else
                    ArgumentError(m)
                end
            )
        end
        ln = get(_p(sys, :sources), _source_key(x), nothing)
        loc = ln === nothing ? "" : " at $(ln.file):$(ln.line)"
        msg = _builtin_text(e.msg)
        # a condition a PDESystem brought (`@fields`, `Potts.couple`) is named as its
        # condition
        o = x isa _BcsLine ? _bcs_origin(sys, x.eq) : nothing
        if o !== nothing
            wrap(
                string(
                    msg, "\n  in the condition `",
                    _bc_text(x.eq, _p(sys, :kinds)), "` of the PDESystem `", o, "`", loc
                )
            )
        end
        # a field equation is named as the equation of its field in its PDESystem, as the
        # user wrote it (`c(t, x, y)`)
        fl = x isa Equation ? _field_lhs(x, sys) : nothing
        if fl !== nothing && fl[1] !== nothing
            o = _bcs_origin(sys, x)
            wrap(
                string(
                    msg, _algebraic_note(x, msg), "\n  in the equation of `",
                    info(fl[1]).name, "` in ",
                    if o === nothing
                        "the fields' PDESystem"
                    else
                        string("the PDESystem `", o, "`")
                    end, ": `",
                    _nopkg(_builtin_text(_field_eq_text(x, sys))), "`", loc
                )
            )
        end
        wrap("$msg$(_algebraic_note(x, msg))\n  in $(_describe(x, _p(sys, :kinds)))$loc")
    end
end

# a field equation as the user wrote it in its PDESystem: each field or site variable read
# at its site, `c(t)`, as `c(t, x, y)`, and `Differential(t, 1)` as `Differential(t)`
function _field_eq_text(eq::Equation, sys::PottsSystem)
    s = replace(_eq_text(eq, _p(sys, :kinds)), "Differential(t, 1)(" => "Differential(t)(")
    names = Set{String}(
        string(info(x).name)
            for x in _p(sys, :variables)
            if info(x) !== nothing && info(x).role in (:field, :site)
    )
    at = string("(t, ", join(("x", "y", "z")[1:length(_p(sys, :lattice).dims)], ", "), ")")
    return replace(
        s, r"([\w₊]+)\(t\)" =>
            m -> (n = chop(m; tail = 3); n in names ? string(n, at) : m)
    )
end

# a condition as a located statement (an error used to name the first `@equations` line); a
# condition a PDESystem brought is named with it
struct _BcsLine
    eq::Any
end
_source_key(x) = x
_source_key(b::_BcsLine) = b.eq
function _describe_text(b::_BcsLine, kinds = nothing)
    return "the condition `" *
        (kinds === nothing ? _builtin_text(string(b.eq)) : _bc_text(b.eq, kinds)) *
        "` of the fields' PDESystem"
end

# descriptions are built only when reporting (printing symbolic expressions is slow); a
# built-in shows as written (`volume`, not the input `volume(t)`), and an operator of the
# field compiler as the model writes it (`laplacian(c)`, `Advect(Upwind1())`, `[ux, 0.0]`)
_describe(x, kinds...) = _nopkg(_builtin_text(_describe_text(x, kinds...)))
function _describe_text(e::EnergyTerm, kinds = nothing)
    return "@energy $(_domain_string(e.domain, kinds)) => $(e.expr)"
end
_describe_text(d::Drive) = "@drive copy => $(d.expr)"
_describe_text(c::Constraint) = "@constraint $(c.expr)"
_describe_text(u::Update) = "@$(u.phase) $(u.eq)"
function _describe_text(eq::Equation, kinds = nothing)
    i = info(eq.lhs)
    return if i !== nothing && i.role === :observed
        "@observed $(eq.lhs) ~ $(eq.rhs)"
    else
        "@equations " * _eq_text(eq, kinds)
    end
end
# an equation as written: a condition inside arithmetic keeps its parentheses
# (Symbolics prints `(kind == 1) - c` as `kind == 1 - c`), and a kind compared by number is
# named
function _eq_text(eq::Equation, kinds)
    s = string(_paren_conditions(eq.lhs), " ~ ", _paren_conditions(eq.rhs))
    # (the condition's stand-in prints quoted)
    s = replace(s, r"var\"(\([^\"]*\))\"" => s"\1")
    kinds === nothing && return s
    return replace(
        s, r"kind(?:\(t\))? (==|!=|≠) (\d+)" =>
            m -> begin
            op, n = match(r"kind(?:\(t\))? (==|!=|≠) (\d+)", m).captures
            k = parse(Int, n)
            "kind $op " * (0 <= k < length(kinds) ? string(kinds[k + 1]) : n)
        end
    )
end
_iscondition(y) = iscall(y) && any(f -> operation(y) === f, (==, !=, <, <=, >, >=))
function _paren_conditions(x)
    reps = Dict{Any, Any}()
    function walk(y, top)
        iscall(y) || return
        if _iscondition(y) && !top
            reps[y] = Symbolics.unwrap(Symbolics.variable(Symbol("(", y, ")")))
        else
            foreach(a -> walk(Symbolics.unwrap(a), false), arguments(y))
        end
        return
    end
    walk(Symbolics.unwrap(x), true)
    return isempty(reps) ? x : Symbolics.substitute(x, reps; fold = Val(false))
end
function _describe_text(v::ConvertSpec, kinds = nothing)
    return "@convert $(v.name) $(_domain_string(v.domain, kinds))"
end
function _describe_text(d::DivideRule, kinds = nothing)
    return "@divide $(_domain_string(d.domain, kinds))$(_cadence_string(d.every)) when \
        = $(d.when)"
end
_cadence_string(n) = n == 1 ? "" : " Every($n)"
_describe_text(x, ::Any) = _describe_text(x)
function _describe_text(r::LinkRule)
    return "@$(r.action) $(r.relationship)$(_cadence_string(r.every)) when = $(r.when)"
end
_describe_text(s::SweepSpec) = "@sweep temperature = $(s.temperature)"
function _describe_text(b::DiscreteBlock)
    return "@components $(b.scope === :model ? "model" : "cells") $(b.name) (discrete)"
end

# Lower every statement once, in the scope it will be generated in, so errors that lowering
# finds (a site variable without a site, a cell variable indexed by a site, …) surface at
# `mtkcompile` with their source instead of while building a problem.
function _dry_lower(sys::PottsSystem, rn, fields, cell_odes)
    T = Float64
    cellenv = _cell_env(T, :c, rn; mcs = :mcs, key = :key)
    for e in _p(sys, :energies)
        _located(sys, e) do
            d = e.domain
            if d isa CellDomain
                lower(e.expr, _cell_env(T, :c, rn))
            elseif d isa ClusterDomain
                lower(e.expr, _cluster_env(T, :r, rn))
            elseif d isa ContactDomain
                lower(
                    _cellvars_at_owner(e.expr), _contact_env(
                        T, :a, :ka, :n, :kn, :w, :i, :j, rn
                    )
                )
            elseif d isa SiteDomain
                lower(e.expr, _site_env(T, :i, rn))
            elseif d isa EdgeDomain
                lower(e.expr, _edge_env(T, :ea, :eb, :ek, :ed, rn))
            elseif d isa AngleDomain
                lower(e.expr, _angle_env(T, :ap, :aq, :an, :aθ, :aκ, rn))
            else
                nothing
            end
        end
    end
    # The integral check runs before lowering, which would otherwise fail on a bare
    # `integral` with the generic "is per cell" message (D-125).
    for d in _p(sys, :drives)
        _located(
            () -> (
                _check_copy_integral(d.expr, "drives"); lower(d.expr, _proposal_env(T, rn))
            ), sys, d
        )
    end
    for c in _p(sys, :constraints)
        c.kind === :expr && _located(
            () -> (
                _check_copy_integral(c.expr, "constraints");
                lower(c.expr, _proposal_env(T, rn))
            ),
            sys,
            c
        )
    end
    for u in _p(sys, :updates)
        _located(sys, u) do
            if u.phase === :on_copy
                # Both sides: an index on the left (`y[ifelse(…, new, old)]`) runs at the
                # copy too (D-129).
                foreach(
                    x -> _check_copy_integral(
                        x, "on-copy updates";
                        when = "every accepted copy"
                    ),
                    (u.eq.lhs, u.eq.rhs)
                )
                env = _proposal_env(T, rn)
                lower(u.eq.rhs, env)
                _write(_unwrap(u.eq.lhs), :v, env)
            else
                r = info(_unwrap(u.eq.lhs)).role
                renv = if r === :cell
                    cellenv
                elseif r === :model
                    _model_env(T, rn; key = :key)
                elseif r === :edge
                    _edge_env(T, :ea, :eb, :ek, :ed, rn; mcs = :mcs, mode = :edge_update)
                else
                    _site_env(T, :i, rn; mcs = :mcs, key = :key)
                end
                lower(u.eq.rhs, renv)
            end
        end
    end
    for eq in _p(sys, :equations)
        _located(sys, eq) do
            # the field compiler lowers these (`_check_fields`)
            _field_lhs(eq) === nothing || return
            x = arguments(_unwrap(eq.lhs))[1]
            r = info(x).role
            if r === :cell
                lower(
                    eq.rhs, _cell_env(
                        T, :c, rn; mcs = :mcs, key = :key, extra = (:time => :tt,)
                    )
                )
            else
                lower(eq.rhs, _model_env(T, rn; key = :key, extra = (:time => :tt,)))
            end
        end
    end
    for d in _p(sys, :divisions)
        _located(sys, d) do
            lower(d.when, cellenv)
            foreach(
                ((x, r),) -> r isa Split ||
                    lower(r, _cell_env(T, :parent, rn; mcs = :mcs, key = :key)),
                d.rules
            )
        end
    end
    for r in _p(sys, :link_rules)
        _located(
            () -> lower(r.when, _edge_env(T, :ea, :eb, :ek, :ed, rn; mcs = :mcs)), sys,
            r
        )
    end
    for b in _p(sys, :discrete)
        env = b.scope === :cell ? cellenv : _model_env(T, rn; key = :key)
        _located(
            () -> foreach(
                x -> (
                    lower(x, env); _check_geometry(
                        x, length(_p(sys, :lattice).dims);
                        hex = _is_hex(sys)
                    )
                ), b.next
            ), sys, b
        )
    end
    # geometry axes, and names the lowering environments cannot rule out
    N = length(_p(sys, :lattice).dims)
    hex = _is_hex(sys)
    for e in _p(sys, :energies)
        _located(() -> _check_geometry(e.expr, N; energy = true, hex), sys, e)
    end
    for (x, items) in (
            (d -> d.expr, _p(sys, :drives)), (
                c -> c.kind === :expr ? c.expr : 0, _p(sys, :constraints),
            ),
            (u -> u.eq.rhs, _p(sys, :updates)), (eq -> eq.rhs, _p(sys, :equations)),
            (
                d -> [d.when; [r for (_, r) in d.rules if !(r isa Split)]],
                _p(sys, :divisions),
            ),
            (_convert_exprs, _p(sys, :converts)), (r -> r.when, _p(sys, :link_rules)),
        )
        foreach(
            i -> _located(
                () -> foreach(y -> _check_geometry(y, N; hex), vcat(x(i))), sys,
                i
            ), items
        )
    end
    # the conditions of the coupled PDESystems: a masked condition's predicate and value, a
    # face's value, are lowered in site scope at the field step
    for b in _p(sys, :bcs)
        _located(() -> _check_geometry(b.rhs, N; hex), sys, _BcsLine(b))
    end
    _located(
        () -> _check_geometry(_p(sys, :sweep).temperature, N; hex), sys,
        _p(sys, :sweep)
    )
    # `integral(Pre(x))` is the block-start fold of an update block (D-042). Outside the
    # blocks `Pre(x)` is the stored value, so the integral would silently be another one.
    for (x, items) in (
            (eq -> eq.rhs, _p(sys, :equations)), (
                d -> [d.when; [r for (_, r) in d.rules if !(r isa Split)]],
                _p(sys, :divisions),
            ),
            (r -> r.when, _p(sys, :link_rules)), (b -> b.next, _p(sys, :discrete)), (
                o -> o.rhs, _p(sys, :observed),
            ),
        )
        foreach(
            i -> _located(() -> foreach(_check_integral_pre_outside, vcat(x(i))), sys, i),
            items
        )
    end
    # D-133
    _located(
        () -> _check_integral_pre_outside(_p(sys, :sweep).temperature), sys,
        _p(sys, :sweep)
    )
    for o in _p(sys, :observed)
        _located(sys, o) do
            _check_geometry(o.rhs, N; hex)
            _has_op(o.rhs, history_lag) &&
                throw(PottsCompileError("`Pre(x, k)` is not available in @observed; keep \
                    the lag in a variable updated @after_mcs"))
            _has_op(o.rhs, random_uniform) &&
                throw(PottsCompileError("`rand()` is not available in @observed (observed \
                    quantities are pure functions of the state)"))
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

function _check_integral_pre_outside(x, E::Type{<:Exception} = PottsCompileError)
    _integral_pre(x) && throw(
        E(
            "`integral(Pre(x))` is only available in update blocks, where it folds the " *
                "values before the block; elsewhere `Pre(x)` is the stored value. Keep " *
                "it in a cell variable updated in the block (`s ~ integral(Pre(x))`), or \
                    write `integral(x)`"
        )
    )
    return nothing
end

# Drives and expression constraints are evaluated at every copy attempt (D-125), and on-copy
# updates, both sides, at every accepted copy (D-129); σ changes with each accepted copy,
# while an integral is refreshed only between sweeps.
function _check_copy_integral(x, what; when = "every copy attempt")
    _has_op(x, cell_integral) && throw(
        PottsCompileError(
            "`integral` is not available in $what: they are evaluated at $when, while an " *
                "integral is refreshed only between sweeps. Keep it in a cell variable " *
                "updated @before_mcs (`s ~ integral(x)`) and read `s[new]`, `s[old]`"
        )
    )
    return nothing
end

# the sides of the conditions of the coupled PDESystems: a masked condition's predicate and
# value or a face's value read CPM quantities at the field step
_bcs_exprs(sys::PottsSystem) = Any[x for b in _p(sys, :bcs) for x in (b.lhs, b.rhs)]

_is_hex(sys) = core_lattice(_p(sys, :lattice)).geometry isa CorePotts.Hexagonal

function _energy_centroid_error(name)
    return PottsCompileError(
        "`$name` is not available in energies: a copy moves the centroids it " *
            "reads and that shift is not part of ΔH; read it in cell " *
            "updates or @observed, or use `displacement(c, k)` in a @drive"
    )
end

# The E7 helpers an energy may not read (D-243), refused before the reference checks so the
# error names the helper: `centroid(c, k)` and `separation` (no ΔH, D-032 until R7) and
# `integral(x; over = cluster)` (refreshed once per MCS, as `integral`)
function _check_energy_geometry(E)
    _has_op(E, ref_centroid) && throw(_energy_centroid_error("centroid"))
    _has_op(E, ref_separation) && throw(_energy_centroid_error("separation"))
    _has_op(E, cluster_integral_sum) && throw(
        PottsCompileError(
            "`integral(x; over = cluster)` is not available in energies (it is refreshed \
                once per MCS, so it has no ΔH)"
        )
    )
    return nothing
end

"""Axes of `centroid`/`displacement` and of the copy-scope `direction[k]` and
`position[s][k]` must be literal lattice axes; `centroid` has no ΔH in energies."""
function _check_geometry(x, N; energy = false, hex = false)
    _walk(x) do y
        iscall(y) || return
        op = operation(y)
        if op === ref_centroid || op === ref_separation || op === axis_minimum_image
            name = if op === ref_centroid
                "centroid"
            elseif op === ref_separation
                "separation"
            else
                "minimum_image"
            end
            energy && op !== axis_minimum_image && throw(_energy_centroid_error(name))
            hex && op === axis_minimum_image && throw(PottsCompileError(_HEX_MINIMUM_IMAGE))
            k = SymbolicUtils.unwrap_const(_unwrap(arguments(y)[end]))
            (k isa Real && isinteger(k) && 1 <= k <= N) ||
                throw(PottsCompileError("`$name`: axis `$k` is not an axis of the $(N)D \
                    lattice (a literal 1 to $N)"))
            return
        end
        if op === cell_integral
            energy && throw(
                PottsCompileError(
                    "`integral` is not available in energies (it is refreshed once per " *
                        "MCS, so it has no ΔH); write the site term in the energy instead"
                )
            )
            return
        end
        # `direction[k]`, `position[s][k]` (D-188): an axis
        if op === value_at && length(arguments(y)) == 2
            a = _unwrap(arguments(y)[1])
            ai = info(a)
            name = if ai !== nothing && ai.role === :builtin && ai.name === :direction
                "direction[k]"
            elseif _is_site_position(a)
                "position[s][k]"
            else
                nothing
            end
            name === nothing && return
            k = SymbolicUtils.unwrap_const(_unwrap(arguments(y)[2]))
            (k isa Real && isinteger(k) && 1 <= k <= N) ||
                throw(PottsCompileError("`$name`: the axis `k` is a literal axis of \
                    the $(N)D lattice (1 to $N); got `$k`"))
            return
        end
        (op === cell_centroid || op === copy_displacement) || return
        name = op === cell_centroid ? "centroid" : "displacement"
        energy && throw(
            PottsCompileError(
                "`$name` is not available in energies (the copy's centroid shift " *
                    "is not part of ΔH); use `displacement(c, k)` in a @drive"
            )
        )
        k = SymbolicUtils.unwrap_const(_unwrap(arguments(y)[end]))
        (k isa Real && isinteger(k) && 1 <= k <= N) ||
            throw(PottsCompileError("`$name`: axis `$k` is not an axis of the $(N)D \
                lattice (a literal 1 to $N)"))
    end
    return nothing
end
