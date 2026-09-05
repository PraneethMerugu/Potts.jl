# Semantic fact inference and descriptor-candidate analysis.

struct AnalyzedFactTable
    result_type::Vector{Any}
    shape::Vector{Any}
    units::Vector{Any}
    parameter_role::Vector{Symbol}
    purity::Vector{Symbol}
    totality::Vector{Symbol}
    reads::Vector{Any}
    writes::Vector{Any}
    footprint::Vector{Any}
    locality::Vector{Symbol}
    affected_region::Vector{Any}
    effect::Vector{Any}
    emission_bound::Vector{EffectBound}
    scientific_category::Vector{Symbol}
    stage::Vector{Any}
    dependencies::Vector{Any}
    rng_sites::Vector{Any}
    state_participation::Vector{Bool}
    workspace_participation::Vector{Bool}
    adaptation_participation::Vector{Bool}
    checkpoint_participation::Vector{Bool}
    engine_admission::Vector{Any}
    backend_admission::Vector{Any}
    source_chain::Vector{Any}
    source_bindings::Vector{Any}
end

struct DescriptorCandidate
    source::QualifiedStatementID
    record::Int32
    category::Symbol
    roots::Vector{Int32}
    energy_domain::Any
    affected_anchors::Any
    affected_proof::Any
    structural_key::String
    provenance::Any
end

struct AnalyzedTermIR
    source::FrozenSourceGraph
    graph::NormalizedTermGraph
    facts::AnalyzedFactTable
    candidates::Vector{DescriptorCandidate}
    lifecycle::Vector{LifecycleAnalysisFact}
    structural_key::String
end

# Operation admission and source requirements.
function _record_operation_role(record::QualifiedStatement)
    record.kind === :HamiltonianTerm && return :hamiltonian
    record.kind === :ProposalDrive && return :drive
    record.kind === :ProposalConstraint && return :constraint
    record.kind === :ProposalModifier && return :modifier
    record.kind === :Observation && return :observation
    if record.kind === :LifecycleProcess
        arguments = first(record.normalized_payload)
        any(_cell_lifecycle_effect, arguments.effects) && return :lifecycle
        return :relationship
    end
    record.kind in (:RelationshipProcess, :RelationshipState) &&
        return :relationship
    record.kind in (
        :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
        :HistoryState,
    ) && return :state
    return :process
end

_record_operation_phase(record::QualifiedStatement) =
    record.phase === nothing ? :none : nameof(typeof(record.phase))

function _operation_context_admitted(
        required::Symbol,
        role::Symbol,
        phase::Symbol,
    )
    required === :any && return true
    required === :proposal && return phase in (:Proposal, :AcceptedCopy)
    required === :hamiltonian && return role === :hamiltonian
    required === :iteration && return phase === :AfterMCS
    required === :relationship && return role === :relationship
    required === :lifecycle_trigger && return role === :lifecycle_trigger
    required === :lifecycle_placement && return role === :lifecycle_placement
    required === :lifecycle_partition && return role === :lifecycle_partition
    required === :lifecycle_state_transform &&
        return role === :lifecycle_state_transform
    return false
end

function _operation_operand_admitted(rule::Symbol, types::Tuple)
    rule === :any && return true
    rule === :numeric && return all(type -> type <: Number, types)
    rule === :boolean && return all(type -> type <: Bool, types)
    rule === :integer && return all(type -> type <: Integer, types)
    rule === :same_type && return isempty(types) || all(==(first(types)), types)
    rule === :ifelse && return length(types) == 3 && types[1] <: Bool &&
        promote_type(types[2], types[3]) !== Any
    return false
end

function _operation_evaluation_context(role::Symbol, phase::Symbol)
    role === :lifecycle_trigger &&
        return CorePotts.CompilerSPI.AbstractLifecycleTriggerEvaluationContext
    role === :lifecycle_placement &&
        return CorePotts.CompilerSPI.AbstractLifecyclePlacementEvaluationContext
    role === :lifecycle_partition &&
        return CorePotts.CompilerSPI.AbstractLifecyclePartitionEvaluationContext
    role === :lifecycle_state_transform &&
        return CorePotts.CompilerSPI.AbstractLifecycleStateTransformEvaluationContext
    role === :lifecycle_priority && return nothing
    role === :hamiltonian &&
        return CorePotts.CompilerSPI.AbstractHamiltonianEvaluationContext
    # Observations lower through their closed observation manifest rather
    # than the generic static-evaluator path.
    role === :observation && return nothing
    phase in (:Proposal, :AcceptedCopy) &&
        return CorePotts.CompilerSPI.AbstractProposalEvaluationContext
    phase === :AfterMCS &&
        return CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext
    phase in (:RelationshipCommit, :Lifecycle) &&
        return CorePotts.CompilerSPI.AbstractRelationshipStageEvaluationContext
    return nothing
end

const _LIFECYCLE_ROOT_ROLES = (
    :lifecycle_trigger,
    :lifecycle_placement,
    :lifecycle_partition,
    :lifecycle_state_transform,
    :lifecycle_priority,
)

function _node_operation_roles(
        source::FrozenSourceGraph,
        graph::NormalizedTermGraph,
    )
    roles = [Symbol[] for _ in graph.nodes]
    function visit(index::Int32, role::Symbol)
        bucket = roles[Int(index)]
        role in bucket || push!(bucket, role)
        for operand in graph.nodes[Int(index)].operands
            visit(operand, role)
        end
        return nothing
    end
    for root in graph.roots
        record = source.records[Int(root.record)]
        role = root.role in _LIFECYCLE_ROOT_ROLES ? root.role :
               _record_operation_role(record)
        visit(root.node, role)
    end
    return Tuple(Tuple(sort!(bucket; by = String)) for bucket in roles)
end

function _source_requirement_problem(
        transfer::OperationTransfer,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    for requirement in transfer.source_requirements
        if requirement isa LatticeRankRequirement
            actual = length(_host_lattice_shape(source))
            actual == requirement.rank || return(
                "requires lattice rank $(requirement.rank), got $actual"
            )
        elseif requirement isa SpatialRelationRequirement
            operand_node = graph.nodes[Int(node.operands[requirement.operand])]
            payload = operand_node.payload
            payload isa ResourceBindingPayload &&
                payload.kind === :SpatialRelation || return(
                "operand $(requirement.operand) must resolve to a SpatialRelation"
            )
            relation_index = findfirst(
                record -> record.identity == payload.identity &&
                    record.kind === :SpatialRelation,
                source.records,
            )
            relation_index === nothing && return(
                "operand $(requirement.operand) has no qualified SpatialRelation"
            )
            neighborhood = get(
                _record_options(source.records[relation_index]),
                :neighborhood,
                nothing,
            )
            actual_kind = neighborhood isa Moore ? :moore :
                          neighborhood isa VonNeumann ? :von_neumann : :unknown
            actual_radius = hasproperty(neighborhood, :radius) ?
                            neighborhood.radius : nothing
            actual_kind === requirement.neighborhood &&
                actual_radius == requirement.radius || return(
                "operand $(requirement.operand) requires " *
                "$(requirement.neighborhood) radius $(requirement.radius), got " *
                    "$(actual_kind) radius $(repr(actual_radius))"
            )
        elseif requirement isa NamedSpatialRelationRequirement
            relation = _resource_record(
                source,
                source.records[Int(node.record)],
                :SpatialRelation,
                requirement.name,
            )
            relation === nothing && return(
                "requires a lexically visible SpatialRelation named " *
                repr(requirement.name)
            )
            neighborhood = get(
                _record_options(relation), :neighborhood, nothing
            )
            neighborhood isa Union{VonNeumann, Moore} || return(
                "relation $(repr(requirement.name)) must use a finite " *
                "VonNeumann or Moore neighborhood"
            )
        else
            return "unknown source requirement $(nameof(typeof(requirement)))"
        end
    end
    return nothing
end

function _tracker_projection_operand(node, graph)
    node.transfer === nothing && return nothing
    node.transfer.identity === :bounded_fold || return nothing
    length(node.operands) == 4 || return nothing
    operand = graph.nodes[Int(node.operands[2])]
    transfer = operand.transfer
    transfer === nothing && return nothing
    (!isempty(transfer.tracker_requirements) ||
        transfer.identity === :cell_volume) || return nothing
    return operand
end

function _is_tracker_projection_operand(node, graph)
    any(root -> root.node == node.identity, graph.roots) && return false
    consumers = filter(
        consumer -> node.identity in consumer.operands,
        graph.nodes,
    )
    isempty(consumers) && return false
    return all(consumers) do consumer
        _tracker_projection_operand(consumer, graph) === node
    end
end

function _resolved_operation_source_bindings(
        transfer::OperationTransfer,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    bindings = OperationSourceBinding[]
    for (requirement_index, requirement) in
            enumerate(transfer.source_requirements)
        identity = if requirement isa SpatialRelationRequirement
            payload = graph.nodes[
                Int(node.operands[requirement.operand])
            ].payload
            payload isa ResourceBindingPayload ? payload.identity : nothing
        elseif requirement isa NamedSpatialRelationRequirement
            relation = _resource_record(
                source,
                source.records[Int(node.record)],
                :SpatialRelation,
                requirement.name,
            )
            relation === nothing ? nothing : relation.identity
        else
            nothing
        end
        identity === nothing && continue
        push!(bindings, OperationSourceBinding(
            Int16(requirement_index), :SpatialRelation, identity
        ))
    end
    return Tuple(bindings)
end

function _validate_operation_use!(
        node::NormalizedTermNode,
        record::QualifiedStatement,
        operand_types::Tuple,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
        role::Symbol,
    )
    transfer = node.transfer
    transfer === nothing && return nothing
    phase = _record_operation_phase(record)
    tracker_projection = _is_tracker_projection_operand(node, graph)
    tracker_fold = transfer.identity === :bounded_fold &&
        _tracker_projection_operand(node, graph) !== nothing
    abi_role = transfer.lifecycle_abi === nothing ? nothing :
        transfer.lifecycle_abi.role === :binary_partition ?
        :lifecycle_partition :
        Symbol(:lifecycle_, transfer.lifecycle_abi.role)
    problem = if tracker_fold && role === :hamiltonian
        "folds over tracker gathers are proposal-snapshot inputs; use a proposal " *
        "drive, constraint, or modifier"
    elseif tracker_projection && phase !== :Proposal
        "tracker gathers are proposal-snapshot inputs"
    elseif abi_role !== nothing && role !== abi_role
        "lifecycle ABI role $(repr(abi_role)) cannot execute as $(repr(role))"
    elseif !tracker_projection && !(role in transfer.allowed_roles)
        "role $(repr(role)) is not in $(repr(transfer.allowed_roles))"
    elseif !(phase in transfer.allowed_phases)
        "phase $(repr(phase)) is not in $(repr(transfer.allowed_phases))"
    elseif !tracker_projection &&
            !_operation_context_admitted(transfer.required_context, role, phase)
        "required context $(repr(transfer.required_context)) is unavailable " *
        "for role $(repr(role)) in phase $(repr(phase))"
    elseif !_operation_operand_admitted(transfer.operand_rule, operand_types)
        "operand types $(repr(operand_types)) violate rule " *
        "$(repr(transfer.operand_rule))"
    elseif (source_problem = _source_requirement_problem(
                transfer, node, graph, source
            )) !== nothing
        source_problem
    elseif !tracker_projection &&
            (context = _operation_evaluation_context(role, phase)) !== nothing &&
            !CorePotts.CompilerSPI.operation_context_supported(node.callable, context)
        "frozen callable $(typeof(node.callable)) has no implementation for " *
        "$(nameof(context))"
    else
        nothing
    end
    problem === nothing && return nothing
    throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :illegal_operation_use,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "the frozen role, phase, context, and operand contract",
            problem,
            (),
            record.source,
        ),),
    ))
end

_is_unknown_unit(unit) = unit === :unknown
_is_polymorphic_zero_unit(unit) = unit === :polymorphic_zero
_unit_compatible(left, right) =
    _is_polymorphic_zero_unit(left) || _is_polymorphic_zero_unit(right) ||
    left == right

_is_native_dimension(unit) = unit isa DynamicQuantities.AbstractDimensions
_canonical_dimension(unit::DynamicQuantities.AbstractDimensions) =
    unit == one(unit) ? :dimensionless : unit
