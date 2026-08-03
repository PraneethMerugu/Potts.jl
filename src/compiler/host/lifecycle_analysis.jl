# Analyzed lifecycle facts are host compiler data and do not authorize or
# implement transaction execution.

struct LifecycleAnalysisFact
    source::QualifiedStatementID
    domain::Symbol
    domain_identity::Any
    anchor::Any
    effect::Symbol
    policies::NamedTuple
    root_roles::Tuple
    operation_abis::Tuple
    reads::Any
    writes::Any
    footprint::Any
    emission_bound::EffectBound
    tracker_requirements::Tuple
    rng_sites::Tuple
    workspace_maximum::Int
    capabilities::NamedTuple
    runtime_ready::Bool
    structural_key::String
end

function _lifecycle_metadata(source, record, value::AbstractPottsStatement)
    kind = statement_kind(value)
    resource = _resource_record(source, record, kind, value)
    return (
        kind,
        identity = resource === nothing ?
            QualifiedStatementID(record.identity.path, statement_id(value)) :
            resource.identity,
    )
end
_lifecycle_metadata(source, record, value::CellBinding) =
    (kind = :cell_binding, name = value.name)
_lifecycle_metadata(source, record, value::SiteBinding) =
    (kind = :site_binding, name = value.name)
_lifecycle_metadata(
    source,
    record,
    value::Union{
        Symbol, String, Number, Bool, Nothing, VersionNumber,
        StatementID, QualifiedStatementID,
    },
) = value
function _lifecycle_metadata(source, record, value::AbstractLifecyclePolicy)
    names = fieldnames(typeof(value))
    fields = NamedTuple{names}(Tuple(
        _lifecycle_metadata(source, record, getfield(value, name))
        for name in names
    ))
    return (kind = nameof(typeof(value)), fields)
end
_lifecycle_metadata(source, record, value::Pair) = (
    target = _lifecycle_metadata(source, record, first(value)),
    policy = _lifecycle_metadata(source, record, last(value)),
)
_lifecycle_metadata(source, record, value::Tuple) = Tuple(
    _lifecycle_metadata(source, record, item) for item in value
)
_lifecycle_metadata(source, record, value::NamedTuple) = NamedTuple{keys(value)}(
    Tuple(_lifecycle_metadata(source, record, item) for item in values(value))
)
function _lifecycle_metadata(source, record, value)
    symbolic = !(SymbolicIndexingInterface.symbolic_type(value) isa
        SymbolicIndexingInterface.NotSymbolic)
    return symbolic ? string(value) : value
end

function _lifecycle_effect_policies(source, record, effect::CreateCell)
    return (
        kind = _lifecycle_metadata(source, record, effect.kind),
        placement = _lifecycle_metadata(source, record, effect.placement),
        state = _lifecycle_metadata(source, record, effect.state),
        priority = effect.priority,
        on_inadmissible = _lifecycle_metadata(
            source, record, effect.on_inadmissible
        ),
    )
end
function _lifecycle_effect_policies(source, record, effect::RemoveCell)
    return (
        replacement = _lifecycle_metadata(source, record, effect.replacement),
        state = _lifecycle_metadata(source, record, effect.state),
        relationships = _lifecycle_metadata(
            source, record, effect.relationships
        ),
        priority = effect.priority,
        on_inadmissible = _lifecycle_metadata(
            source, record, effect.on_inadmissible
        ),
    )
end
function _lifecycle_effect_policies(source, record, effect::Retire)
    return (
        state = _lifecycle_metadata(source, record, effect.state),
        relationships = _lifecycle_metadata(
            source, record, effect.relationships
        ),
        priority = effect.priority,
        on_inadmissible = _lifecycle_metadata(
            source, record, effect.on_inadmissible
        ),
    )
end
function _lifecycle_effect_policies(source, record, effect::Transition)
    return (
        destination = _lifecycle_metadata(source, record, effect.kind),
        state = _lifecycle_metadata(source, record, effect.state),
        relationships = _lifecycle_metadata(
            source, record, effect.relationships
        ),
        priority = effect.priority,
        on_inadmissible = _lifecycle_metadata(
            source, record, effect.on_inadmissible
        ),
    )
end
function _lifecycle_effect_policies(source, record, effect::Divide)
    return (
        geometry = _lifecycle_metadata(source, record, effect.geometry),
        relation = _lifecycle_metadata(source, record, effect.relation),
        side = _lifecycle_metadata(source, record, effect.side),
        parent_kind = _lifecycle_metadata(source, record, effect.parent_kind),
        daughter_kind = _lifecycle_metadata(
            source, record, effect.daughter_kind
        ),
        state = _lifecycle_metadata(source, record, effect.state),
        relationships = _lifecycle_metadata(
            source, record, effect.relationships
        ),
        priority = effect.priority,
        on_inadmissible = _lifecycle_metadata(
            source, record, effect.on_inadmissible
        ),
    )
end

function _lifecycle_domain_fact(source, record, domain)
    if domain isa ModelDomain
        return (:model, record.identity.path)
    elseif domain isa Cells
        resource = _resource_record(source, record, :CellKind, domain.kind)
        resource === nothing && throw(PottsValidationError(
            :analysis,
            (PottsDiagnostic(
                :unresolved_lifecycle_domain,
                record.identity,
                repr(domain),
                record.identity.path,
                "a qualified CellKind identity",
                "the cells(kind) resource did not resolve",
                (),
                record.source,
            ),),
        ))
        return (:cells, resource.identity)
    end
    throw(ArgumentError("unsupported cell-lifecycle domain $(typeof(domain))"))
end

function _lifecycle_anchor_fact(source, record, domain, anchor)
    domain isa ModelDomain && return (
        kind = :model,
        name = :model,
        identity = record.identity.path,
    )
    anchor isa CellBinding || return nothing
    _, identity = _lifecycle_domain_fact(source, record, domain)
    return (kind = :cell, name = anchor.name, identity)
end

function _reachable_nodes(graph, roots)
    visited = Set{Int32}()
    function visit(index::Int32)
        index in visited && return
        push!(visited, index)
        foreach(visit, graph.nodes[Int(index)].operands)
    end
    foreach(visit, roots)
    return sort!(collect(visited))
end

function _lifecycle_role_roots(graph, record_index)
    return Tuple(
        root for root in graph.roots
        if root.record == record_index && root.role in _LIFECYCLE_ROOT_ROLES
    )
end

function _require_external_policy_abi!(record, graph, roots, role, expected)
    selected = filter(root -> root.role === role, roots)
    isempty(selected) && throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :missing_lifecycle_policy_expression,
            record.identity,
            String(role),
            record.identity.path,
            "one normalized registered $expected operation",
            "no $role root",
            (),
            record.source,
        ),),
    ))
    for root in selected
        node = graph.nodes[Int(root.node)]
        abi = node.transfer === nothing ? nothing : node.transfer.lifecycle_abi
        abi !== nothing && abi.role === expected && return nothing
    end
    throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :missing_lifecycle_policy_abi,
            record.identity,
            String(role),
            record.identity.path,
            "a top-level operation with LifecycleOperationABI($(repr(expected)))",
            "the registered policy root has no matching lifecycle ABI",
            (),
            record.source,
        ),),
    ))
end

function _validate_lifecycle_root_results!(record, graph, facts, roots)
    for root in roots
        index = Int(root.node)
        type = facts.result_type[index]
        unit = facts.units[index]
        if root.role === :lifecycle_trigger
            type <: Bool || throw(PottsValidationError(
                :analysis,
                (PottsDiagnostic(
                    :invalid_lifecycle_trigger_type,
                    record.identity,
                    String(root.role),
                    record.identity.path,
                    "Bool",
                    string(type),
                    (),
                    record.source,
                ),),
            ))
            _unit_compatible(unit, :dimensionless) || throw(PottsValidationError(
                :analysis,
                (PottsDiagnostic(
                    :invalid_lifecycle_trigger_units,
                    record.identity,
                    String(root.role),
                    record.identity.path,
                    "dimensionless",
                    repr(unit),
                    (),
                    record.source,
                ),),
            ))
        elseif root.role in (:lifecycle_placement, :lifecycle_partition)
            type <: Integer || throw(PottsValidationError(
                :analysis,
                (PottsDiagnostic(
                    :invalid_lifecycle_policy_result,
                    record.identity,
                    String(root.role),
                    record.identity.path,
                    "an integer site or region-label result",
                    string(type),
                    (),
                    record.source,
                ),),
            ))
        elseif root.role === :lifecycle_priority
            type <: Integer || throw(PottsValidationError(
                :analysis,
                (PottsDiagnostic(
                    :invalid_lifecycle_priority_type,
                    record.identity,
                    String(root.role),
                    record.identity.path,
                    "an Int32-representable integer",
                    string(type),
                    (),
                    record.source,
                ),),
            ))
        end
    end
    return nothing
end

function _lifecycle_tracker_requirements(graph, nodes)
    result = Symbol[]
    for index in nodes
        transfer = graph.nodes[Int(index)].transfer
        transfer === nothing && continue
        for tracker in transfer.tracker_requirements
            tracker in result || push!(result, tracker)
        end
    end
    return Tuple(sort!(result; by = String))
end

function _lifecycle_rng_sites(record, effect)
    result = Any[record.random_operations...]
    if effect isa Divide
        effect.geometry isa RandomPlane && push!(result, (
            identity = effect.geometry.draw,
            family = :division_geometry,
            entity = :cell_generation,
        ))
        effect.side isa StableRandomSide && push!(result, (
            identity = effect.side.draw_identity,
            family = :division_side,
            entity = :cell_generation,
        ))
    end
    for item in effect.state
        policy = _policy_value(item)
        policy isa RedrawDaughters || continue
        push!(result, (
            identity = policy.parent_draw,
            family = :state_redraw,
            entity = :destination,
            role = :parent,
        ))
        push!(result, (
            identity = policy.daughter_draw,
            family = :state_redraw,
            entity = :destination,
            role = :daughter,
        ))
    end
    return Tuple(result)
end

function _lifecycle_workspace_maximum(graph, nodes)
    maximum = 0
    for index in nodes
        transfer = graph.nodes[Int(index)].transfer
        transfer === nothing && continue
        abi = transfer.lifecycle_abi
        abi === nothing || (maximum += abi.workspace_maximum)
    end
    return maximum
end

function _lifecycle_operation_abis(graph, roots)
    return Tuple(begin
        node = graph.nodes[Int(root.node)]
        transfer = node.transfer
        abi = transfer === nothing ? nothing : transfer.lifecycle_abi
        (
            role = root.role,
            operation = node.operation,
            schema_version = node.schema_version,
            owner = transfer === nothing ? nothing : transfer.owner,
            callable_identity = transfer === nothing ? nothing :
                transfer.callable_identity,
            abi = abi === nothing ? nothing : (
                role = abi.role,
                input_context = abi.input_context,
                result_shape = abi.result_shape,
                emission_maximum = abi.emission_maximum,
                workspace_maximum = abi.workspace_maximum,
                validator = abi.validator,
                rng_entity = abi.rng_entity,
            ),
        )
    end for root in roots)
end

function _analyze_lifecycle_records(source, graph, facts)
    result = LifecycleAnalysisFact[]
    for (record_index, record) in enumerate(source.records)
        record.kind === :LifecycleProcess || continue
        arguments = first(record.normalized_payload)
        length(arguments.effects) == 1 || continue
        effect = only(arguments.effects)
        _cell_lifecycle_effect(effect) || continue
        roots = _lifecycle_role_roots(graph, Int32(record_index))
        _validate_lifecycle_root_results!(record, graph, facts, roots)
        if effect isa CreateCell &&
                !(effect.placement isa AbstractLifecyclePlacementPolicy)
            _require_external_policy_abi!(
                record, graph, roots, :lifecycle_placement, :placement
            )
        elseif effect isa Divide &&
                !(effect.geometry isa AbstractLifecyclePartitionPolicy)
            _require_external_policy_abi!(
                record, graph, roots, :lifecycle_partition, :binary_partition
            )
        end
        root_nodes = Int32[root.node for root in roots]
        nodes = _reachable_nodes(graph, root_nodes)
        root_footprint = isempty(root_nodes) ? EmptyAnalyzedFootprint() :
            _footprint_union(Tuple(facts.footprint[Int(root)] for root in root_nodes))
        domain, domain_identity = _lifecycle_domain_fact(
            source, record, arguments.domain
        )
        capabilities = (
            cpu = all(facts.backend_admission[Int(root)].cpu for root in root_nodes),
            gpu = all(facts.backend_admission[Int(root)].gpu for root in root_nodes),
            reason = join(unique(filter(!isempty, String[
                facts.backend_admission[Int(root)].reason for root in root_nodes
            ])), "; "),
        )
        options = _record_options(record)
        policies = merge(
            _lifecycle_effect_policies(source, record, effect),
            (resolution = (
                state = _lifecycle_metadata(
                    source,
                    record,
                    get(options, :resolved_state_policy_sources, ()),
                ),
                relationships = _lifecycle_metadata(
                    source,
                    record,
                    get(options, :resolved_relationship_policy_sources, ()),
                ),
                site_ownership = _lifecycle_metadata(
                    source,
                    record,
                    get(options, :resolved_site_ownership, ()),
                ),
            ),),
        )
        trackers = _lifecycle_tracker_requirements(graph, nodes)
        rng = _lifecycle_rng_sites(record, effect)
        workspace = _lifecycle_workspace_maximum(graph, nodes)
        root_roles = Tuple(root.role for root in roots)
        operation_abis = _lifecycle_operation_abis(graph, roots)
        writes = (
            identity = effect isa AbstractCellLifecycleEffect,
            ownership = effect isa Union{CreateCell, RemoveCell, Divide},
            kind = effect isa Union{CreateCell, RemoveCell, Retire, Transition, Divide},
            state = !isempty(effect.state),
            relationships = hasproperty(effect, :relationships) &&
                !isempty(effect.relationships),
        )
        key = _sha256_hex(
            "potts-lifecycle-analysis-v1",
            record.identity,
            domain,
            domain_identity,
            nameof(typeof(effect)),
            policies,
            root_roles,
            operation_abis,
            root_footprint,
            record.bound.maximum,
            record.bound.basis,
            trackers,
            rng,
            workspace,
            capabilities,
        )
        push!(result, LifecycleAnalysisFact(
            record.identity,
            domain,
            domain_identity,
            _lifecycle_anchor_fact(
                source, record, arguments.domain, arguments.anchor
            ),
            nameof(typeof(effect)),
            policies,
            root_roles,
            operation_abis,
            Tuple(string(read) for read in record.reads),
            writes,
            root_footprint,
            record.bound,
            trackers,
            rng,
            workspace,
            capabilities,
            false,
            key,
        ))
    end
    return result
end

function _lifecycle_analysis_report(ir)
    return Tuple((
        source = fact.source,
        domain = fact.domain,
        domain_identity = fact.domain_identity,
        anchor = fact.anchor,
        effect = fact.effect,
        policies = fact.policies,
        root_roles = fact.root_roles,
        operation_abis = fact.operation_abis,
        reads = fact.reads,
        writes = fact.writes,
        footprint = fact.footprint,
        emission_bound = fact.emission_bound,
        tracker_requirements = fact.tracker_requirements,
        rng_sites = fact.rng_sites,
        workspace_maximum = fact.workspace_maximum,
        capabilities = fact.capabilities,
        runtime_ready = fact.runtime_ready,
        structural_key = fact.structural_key,
    ) for fact in ir.lifecycle)
end
