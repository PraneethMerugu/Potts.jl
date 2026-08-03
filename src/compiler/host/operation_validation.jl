# Closed schema and normalized-graph validation.

const _RESULT_TRANSFER_RULES = Set((
    :promote_numeric,
    :boolean,
    :branch_promote,
    :preserve_numeric,
    :integer,
    :real,
))
const _UNIT_TRANSFER_RULES = Set((
    :arithmetic,
    :comparison,
    :dimensionless,
    :branch,
    :unary,
    :square_root,
    :declared,
    :distribution,
    :lattice_volume,
))
const _PURITY_TRANSFER_RULES = Set((:pure, :semantic_rng))
const _TOTALITY_TRANSFER_RULES = Set((
    :total, :domain_checked, :requires_prelaunch_validation
))
const _OPERAND_TRANSFER_RULES = Set((
    :any, :numeric, :boolean, :integer, :same_type, :ifelse,
))
const _OPERATION_CONTEXT_RULES = Set((
    :any, :proposal, :hamiltonian, :iteration, :relationship,
    :lifecycle_trigger, :lifecycle_placement, :lifecycle_partition,
    :lifecycle_state_transform,
))

function _lifecycle_operation_abi_error(
        transfer::OperationTransfer,
        abi::LifecycleOperationABI,
    )
    abi.role in _LIFECYCLE_OPERATION_ROLES ||
        return "unknown lifecycle operation role $(repr(abi.role))"
    abi.input_context in _LIFECYCLE_INPUT_CONTEXTS ||
        return "unknown lifecycle input context $(repr(abi.input_context))"
    abi.result_shape in _LIFECYCLE_RESULT_SHAPES ||
        return "unknown lifecycle result shape $(repr(abi.result_shape))"
    abi.validator in _LIFECYCLE_VALIDATORS ||
        return "unknown lifecycle validator $(repr(abi.validator))"
    abi.rng_entity in _LIFECYCLE_RNG_ENTITIES ||
        return "unknown lifecycle RNG entity $(repr(abi.rng_entity))"
    abi.emission_maximum >= 0 ||
        return "lifecycle emission maximum must be nonnegative"
    abi.workspace_maximum >= 0 ||
        return "lifecycle workspace maximum must be nonnegative"
    role = abi.role === :binary_partition ? :lifecycle_partition :
           Symbol(:lifecycle_, abi.role)
    role in transfer.allowed_roles ||
        return "lifecycle ABI role $role is absent from allowed_roles"
    :Lifecycle in transfer.allowed_phases ||
        return "lifecycle ABI operations must admit the Lifecycle phase"
    transfer.required_context === abi.input_context ||
        return "required_context must equal lifecycle ABI input_context"
    expected_shape = abi.role === :trigger ? :scalar_boolean :
                     abi.role === :placement ? :bounded_site_selection :
                     abi.role === :binary_partition ? :site_region_label : nothing
    expected_shape === nothing || abi.result_shape === expected_shape ||
        return "lifecycle role $(abi.role) requires result shape $expected_shape"
    abi.role === :trigger && transfer.result_rule !== :boolean &&
        return "lifecycle triggers must use the boolean result transfer"
    abi.role in (:placement, :binary_partition) &&
        transfer.result_rule !== :integer &&
        return "lifecycle placement/partition operations must return integers"
    abi.role === :placement && abi.emission_maximum <= 0 &&
        return "lifecycle placement must declare a positive finite emission maximum"
    validator = abi.role === :trigger ? :trigger_boolean :
                abi.role === :placement ? :placement_selection :
                abi.role === :binary_partition ? :binary_partition :
                :state_schema
    abi.validator === validator ||
        return "lifecycle role $(abi.role) requires validator $validator"
    return nothing
end

function _operation_transfer_error(transfer::OperationTransfer, arity::Int)
    isempty(String(transfer.identity)) &&
        return "operation identity must be nonempty"
    transfer.schema_version > v"0.0.0" ||
        return "operation schema version must be positive"
    isempty(transfer.serialization_identity) &&
        return "operation serialization identity must be nonempty"
    arity in transfer.arity ||
        return "arity $arity is outside $(transfer.arity)"
    transfer.result_rule in _RESULT_TRANSFER_RULES ||
        return "unknown result transfer rule $(transfer.result_rule)"
    transfer.unit_rule in _UNIT_TRANSFER_RULES ||
        return "unknown unit transfer rule $(transfer.unit_rule)"
    transfer.purity in _PURITY_TRANSFER_RULES ||
        return "unknown purity transfer rule $(transfer.purity)"
    transfer.totality in _TOTALITY_TRANSFER_RULES ||
        return "unknown totality transfer rule $(transfer.totality)"
    transfer.operand_rule in _OPERAND_TRANSFER_RULES ||
        return "unknown operand rule $(transfer.operand_rule)"
    !isempty(transfer.allowed_roles) &&
        all(role -> role in _V1_OPERATION_ROLES, transfer.allowed_roles) ||
        return "allowed_roles must be a nonempty subset of the closed V1 roles"
    length(unique(transfer.allowed_roles)) == length(transfer.allowed_roles) ||
        return "allowed_roles must be unique"
    !isempty(transfer.allowed_phases) &&
        all(phase -> phase in _V1_OPERATION_PHASES, transfer.allowed_phases) ||
        return "allowed_phases must be a nonempty subset of the closed V1 phases"
    length(unique(transfer.allowed_phases)) == length(transfer.allowed_phases) ||
        return "allowed_phases must be unique"
    transfer.required_context in _OPERATION_CONTEXT_RULES ||
        return "unknown required context $(transfer.required_context)"
    isempty(String(transfer.owner)) && return "operation owner must be nonempty"
    isempty(transfer.callable_identity) &&
        return "operation callable identity must be nonempty"
    transfer.footprint_rule isa AbstractFootprintTransferRule ||
        return "operation footprint transfer must use the closed rule algebra"
    all(requirement -> !isempty(String(requirement)),
        transfer.tracker_requirements) ||
        return "tracker requirement identities must be nonempty"
    Tuple(sort!(unique!(collect(transfer.tracker_requirements)))) ==
        transfer.tracker_requirements ||
        return "tracker requirements must be unique and canonically ordered"
    all(requirement -> requirement isa AbstractOperationSourceRequirement,
        transfer.source_requirements) ||
        return "source requirements must use the closed requirement algebra"
    for requirement in transfer.source_requirements
        if requirement isa LatticeRankRequirement
            requirement.rank > 0 ||
                return "lattice-rank requirements must be positive"
        elseif requirement isa SpatialRelationRequirement
            1 <= requirement.operand <= arity ||
                return "spatial-relation requirement operand is outside the operation arity"
            requirement.neighborhood in (:von_neumann, :moore) ||
                return "spatial-relation requirement uses an unknown neighborhood"
            requirement.radius > 0 ||
                return "spatial-relation requirement radius must be positive"
        elseif requirement isa NamedSpatialRelationRequirement
            isempty(String(requirement.name)) &&
                return "named spatial-relation requirements must be nonempty"
        else
            return "unknown source requirement $(nameof(typeof(requirement)))"
        end
    end
    if transfer.lifecycle_abi !== nothing
        problem = _lifecycle_operation_abi_error(
            transfer, transfer.lifecycle_abi
        )
        problem === nothing || return problem
    end
    transfer.cpu ||
        return "V1 operations must admit the CPU reference backend"
    return nothing
end

function _normalized_payload_error(node::NormalizedTermNode)
    expected = if node.payload_kind === :literal
        LiteralPayload
    elseif node.payload_kind === :parameter
        ParameterBindingPayload
    elseif node.payload_kind === :variable
        Union{VariableBindingPayload, StateBindingPayload}
    elseif node.payload_kind === :state
        StateBindingPayload
    elseif node.payload_kind === :proposal_context
        ContextBindingPayload
    elseif node.payload_kind in (
            :site_anchor, :cell_anchor, :contact_anchor,
            :relationship_context,
        )
        AnchorBindingPayload
    elseif node.payload_kind in (:relationship_set, :spatial_relation)
        ResourceBindingPayload
    elseif node.payload_kind === :kind
        KindBindingPayload
    elseif node.payload_kind === :relationship_payload
        RelationshipPayloadBindingPayload
    elseif node.payload_kind === :draw
        DrawBindingPayload
    elseif node.payload_kind === :operation
        Nothing
    else
        return "unknown normalized payload tag $(repr(node.payload_kind))"
    end
    node.payload isa expected || return
        "payload tag $(repr(node.payload_kind)) requires $expected, got $(typeof(node.payload))"
    node.payload_kind === :operation && node.transfer === nothing &&
        return "operation payload requires a frozen operation transfer"
    node.payload_kind !== :operation && node.transfer !== nothing &&
        return "leaf payload cannot carry an operation transfer"
    return nothing
end

function _verify_normalized_graph!(
        diagnostics,
        graph::NormalizedTermGraph,
    )
    for (expected, node) in enumerate(graph.nodes)
        node.identity == expected || push!(
            diagnostics,
            PottsDiagnostic(
                :noncanonical_term_identity,
                node.source,
                string(node.operation),
                node.source.path,
                string(expected),
                string(node.identity),
                (),
                UnknownSource(),
            ),
        )
        all(operand -> 0 < operand < node.identity, node.operands) || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_term_dag_edge,
                node.source,
                string(node.operation),
                node.source.path,
                "operands defined before their consumer",
                repr(node.operands),
                (),
                UnknownSource(),
            ),
        )
        payload_reason = _normalized_payload_error(node)
        payload_reason === nothing || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_normalized_payload,
                node.source,
                string(node.operation),
                node.source.path,
                "one payload in the closed normalized grammar",
                payload_reason,
                (),
                UnknownSource(),
            ),
        )
        node.payload_kind === :operation || continue
        transfer = node.transfer
        if transfer === nothing
            push!(
                diagnostics,
                PottsDiagnostic(
                    :missing_normalized_transfer,
                    node.source,
                    string(node.operation),
                    node.source.path,
                    "a frozen operation transfer",
                    "nothing",
                    (),
                    UnknownSource(),
                ),
            )
            continue
        end
        reason = _operation_transfer_error(transfer, length(node.operands))
        reason === nothing || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_operation_transfer,
                node.source,
                string(node.operation),
                node.source.path,
                "a valid frozen operation transfer",
                reason,
                (),
                UnknownSource(),
            ),
        )
        transfer.identity === node.operation || push!(
            diagnostics,
            PottsDiagnostic(
                :operation_identity_transfer_mismatch,
                node.source,
                string(node.operation),
                node.source.path,
                String(node.operation),
                String(transfer.identity),
                (),
                UnknownSource(),
            ),
        )
        transfer.schema_version == node.schema_version || push!(
            diagnostics,
            PottsDiagnostic(
                :operation_version_transfer_mismatch,
                node.source,
                string(node.operation),
                node.source.path,
                string(node.schema_version),
                string(transfer.schema_version),
                (),
                UnknownSource(),
            ),
        )
        operation = node.callable
        operation === nothing &&
            push!(
                diagnostics,
                PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    node.source,
                    string(node.operation),
                    node.source.path,
                    "the concrete callable frozen during completion",
                    "nothing",
                    (),
                    UnknownSource(),
                ),
            )
        operation === nothing || isbits(operation) || push!(
            diagnostics,
            PottsDiagnostic(
                :device_illegal_operation_callable,
                node.source,
                string(node.operation),
                node.source.path,
                "an isbits concrete operation callable",
                string(typeof(operation)),
                (),
                UnknownSource(),
            ),
        )
    end
    for root in graph.roots
        0 < root.node <= length(graph.nodes) || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_term_root,
                QualifiedStatementID((), StatementID(:compiler)),
                string(root.role),
                (),
                "a node in the normalized graph",
                string(root.node),
                (),
                UnknownSource(),
            ),
        )
    end
    for schema in graph.operation_snapshot
        any(node -> node.transfer == schema.transfer, graph.nodes) && continue
        reason = _operation_transfer_error(schema.transfer, schema.arity)
        reason === nothing || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_frozen_operation_schema,
                QualifiedStatementID((), StatementID(:compiler)),
                String(schema.transfer.identity),
                (),
                "a complete operation contract frozen during completion",
                reason,
                (),
                UnknownSource(),
            ),
        )
        isbits(schema.callable) || push!(
            diagnostics,
            PottsDiagnostic(
                :device_illegal_operation_callable,
                QualifiedStatementID((), StatementID(:compiler)),
                String(schema.transfer.identity),
                (),
                "an isbits concrete operation callable",
                string(typeof(schema.callable)),
                (),
                UnknownSource(),
            ),
        )
    end
    return diagnostics
end
