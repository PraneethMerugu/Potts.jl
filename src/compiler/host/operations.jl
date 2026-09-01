# Versioned authority for symbolic operations admitted to the normalized DAG.

"""Supertype of cold resource requirements declared by symbolic operations."""
abstract type AbstractOperationSourceRequirement end

"""Require a lattice of one exact spatial rank."""
struct LatticeRankRequirement <: AbstractOperationSourceRequirement
    rank::Int
end

"""Require a bounded spatial relation supplied by one operation operand."""
struct SpatialRelationRequirement <: AbstractOperationSourceRequirement
    operand::Int
    neighborhood::Symbol
    radius::Int
end

"""Require one lexically resolved spatial relation with a fixed local name."""
struct NamedSpatialRelationRequirement <: AbstractOperationSourceRequirement
    name::Symbol
end

"""Qualified resource identity proven for one operation source requirement."""
struct OperationSourceBinding
    requirement_index::Int16
    kind::Symbol
    identity::QualifiedStatementID
end

const _LIFECYCLE_OPERATION_ROLES = (
    :trigger, :placement, :binary_partition, :state_transform,
)
const _LIFECYCLE_INPUT_CONTEXTS = (
    :lifecycle_trigger,
    :lifecycle_placement,
    :lifecycle_partition,
    :lifecycle_state_transform,
)
const _LIFECYCLE_RESULT_SHAPES = (
    :scalar_boolean,
    :bounded_site_selection,
    :site_region_label,
    :state_value,
    :state_pair,
)
const _LIFECYCLE_VALIDATORS = (
    :trigger_boolean,
    :placement_selection,
    :binary_partition,
    :state_schema,
)
const _LIFECYCLE_RNG_ENTITIES = (
    :none, :bound_anchor, :model_occurrence, :cell_generation, :destination,
)

"""Bounded execution contract for a lifecycle symbolic operation."""
struct LifecycleOperationABI
    role::Symbol
    input_context::Symbol
    result_shape::Symbol
    emission_maximum::Int
    workspace_maximum::Int
    validator::Symbol
    rng_entity::Symbol
end

function LifecycleOperationABI(
        role::Symbol;
        input_context,
        result_shape,
        emission_maximum::Integer = 0,
        workspace_maximum::Integer = 0,
        validator,
        rng_entity = :none,
    )
    emission_maximum >= 0 || throw(ArgumentError(
        "lifecycle operation emission_maximum must be nonnegative"
    ))
    workspace_maximum >= 0 || throw(ArgumentError(
        "lifecycle operation workspace_maximum must be nonnegative"
    ))
    return LifecycleOperationABI(
        role,
        input_context,
        result_shape,
        Int(emission_maximum),
        Int(workspace_maximum),
        validator,
        rng_entity,
    )
end

"""Versioned compiler contract for one registered symbolic operation."""
struct OperationTransfer
    identity::Symbol
    schema_version::VersionNumber
    serialization_identity::String
    arity::UnitRange{Int}
    result_rule::Symbol
    unit_rule::Symbol
    purity::Symbol
    totality::Symbol
    footprint_rule::AbstractFootprintTransferRule
    cpu::Bool
    gpu::Bool
    tracker_requirements::Tuple{Vararg{Symbol}}
    operand_rule::Symbol
    allowed_roles::Tuple{Vararg{Symbol}}
    allowed_phases::Tuple{Vararg{Symbol}}
    required_context::Symbol
    owner::Symbol
    callable_identity::String
    source_requirements::Tuple
    lifecycle_abi::Union{Nothing, LifecycleOperationABI}
end

# Preserve the established full positional construction contract while the
# lifecycle ABI remains an optional schema extension.
OperationTransfer(
    identity::Symbol,
    schema_version::VersionNumber,
    serialization_identity::String,
    arity::UnitRange{Int},
    result_rule::Symbol,
    unit_rule::Symbol,
    purity::Symbol,
    totality::Symbol,
    footprint_rule::AbstractFootprintTransferRule,
    cpu::Bool,
    gpu::Bool,
    tracker_requirements::Tuple{Vararg{Symbol}},
    operand_rule::Symbol,
    allowed_roles::Tuple{Vararg{Symbol}},
    allowed_phases::Tuple{Vararg{Symbol}},
    required_context::Symbol,
    owner::Symbol,
    callable_identity::String,
    source_requirements::Tuple,
) = OperationTransfer(
    identity,
    schema_version,
    serialization_identity,
    arity,
    result_rule,
    unit_rule,
    purity,
    totality,
    footprint_rule,
    cpu,
    gpu,
    tracker_requirements,
    operand_rule,
    allowed_roles,
    allowed_phases,
    required_context,
    owner,
    callable_identity,
    source_requirements,
    nothing,
)

const _CLOSED_OPERATION_ROLES = (
    :hamiltonian,
    :drive,
    :constraint,
    :modifier,
    :process,
    :observation,
    :relationship,
    :lifecycle_trigger,
    :lifecycle_placement,
    :lifecycle_partition,
    :lifecycle_state_transform,
    :lifecycle_priority,
    :state,
)
const _CLOSED_OPERATION_PHASES = (
    :none,
    :Proposal,
    :AcceptedCopy,
    :AfterMCS,
    :RelationshipCommit,
    :Lifecycle,
)

OperationTransfer(
    identity::Symbol,
    schema_version::VersionNumber,
    serialization_identity::String,
    arity::UnitRange{Int},
    result_rule::Symbol,
    unit_rule::Symbol,
    purity::Symbol,
    totality::Symbol,
    footprint_rule::AbstractFootprintTransferRule,
    cpu::Bool,
    gpu::Bool,
    ;
    tracker_requirements = (),
    operand_rule = :any,
    allowed_roles = _CLOSED_OPERATION_ROLES,
    allowed_phases = _CLOSED_OPERATION_PHASES,
    required_context = :any,
    owner = :external,
    callable_identity = "CorePotts.CompilerSPI.operation_callable:" * String(identity) *
        ":" * string(schema_version),
    source_requirements = (),
    lifecycle_abi = nothing,
) = OperationTransfer(
    identity,
    schema_version,
    serialization_identity,
    arity,
    result_rule,
    unit_rule,
    purity,
    totality,
    footprint_rule,
    cpu,
    gpu,
    Tuple(tracker_requirements),
    operand_rule,
    Tuple(allowed_roles),
    Tuple(allowed_phases),
    required_context,
    owner,
    String(callable_identity),
    Tuple(source_requirements),
    lifecycle_abi,
)

OperationTransfer(
    identity::Symbol,
    schema_version::VersionNumber,
    arity::UnitRange{Int},
    result_rule::Symbol,
    unit_rule::Symbol,
    purity::Symbol,
    totality::Symbol,
    footprint_rule::AbstractFootprintTransferRule,
    cpu::Bool,
    gpu::Bool,
    tracker_requirements::Tuple{Vararg{Symbol}} = ();
    operand_rule = :any,
    allowed_roles = _CLOSED_OPERATION_ROLES,
    allowed_phases = _CLOSED_OPERATION_PHASES,
    required_context = :any,
    owner = :external,
    callable_identity = "CorePotts.CompilerSPI.operation_callable:" * String(identity) *
        ":" * string(schema_version),
    source_requirements = (),
    lifecycle_abi = nothing,
) = OperationTransfer(
    identity,
    schema_version,
    "potts-operation:" * String(identity) * ":" * string(schema_version),
    arity,
    result_rule,
    unit_rule,
    purity,
    totality,
    footprint_rule,
    cpu,
    gpu,
    tracker_requirements,
    operand_rule,
    Tuple(allowed_roles),
    Tuple(allowed_phases),
    required_context,
    owner,
    String(callable_identity),
    Tuple(source_requirements),
    lifecycle_abi,
)

"""Return the registered `OperationTransfer` for a symbolic operation."""
function operation_transfer end

_transfer(identity, arity, result_rule, unit_rule;
        version = v"1.0.0",
        serialization_identity = "potts-operation:" * String(identity) * ":v1",
        purity = :pure,
        totality = :total,
        footprint_rule = InheritFootprintRule(),
        cpu = true,
        gpu = true,
        tracker_requirements = (),
        operand_rule = :any,
        allowed_roles = _CLOSED_OPERATION_ROLES,
        allowed_phases = _CLOSED_OPERATION_PHASES,
        required_context = :any,
        owner = :PottsToolkit,
        callable_identity = "CorePotts.CompilerSPI.operation_callable:" * String(identity) * ":" *
            string(version),
        source_requirements = (),
        lifecycle_abi = nothing,
    ) = OperationTransfer(
        identity,
        version,
        String(serialization_identity),
        arity isa Integer ? (Int(arity):Int(arity)) : arity,
        result_rule,
        unit_rule,
        purity,
        totality,
        footprint_rule,
        cpu,
        gpu,
        tracker_requirements,
        operand_rule,
        Tuple(allowed_roles),
        Tuple(allowed_phases),
        required_context,
        owner,
        String(callable_identity),
        Tuple(source_requirements),
        lifecycle_abi,
    )

function numerical_operation_requirements end
numerical_operation_requirements(::Any) = ()

function numerical_field_rejection end
numerical_field_rejection(::Any, statement, statements, system) =
    "executable field lowering does not admit the selected evolution policy"

function numerical_field_stage_descriptor end

for operation in (+, -, *, /, ^, max, min)
    identity = if operation === (+)
        :add
    elseif operation === (-)
        :subtract
    elseif operation === (*)
        :multiply
    elseif operation === (/)
        :divide
    elseif operation === (^)
        :power
    elseif operation === max
        :maximum
    else
        :minimum
    end
    admitted_arity = operation === (^) ? (2:2) : (1:typemax(Int))
    totality = operation === (^) ? :domain_checked : :total
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer($(QuoteNode(identity)), $admitted_arity,
            :promote_numeric, :arithmetic;
            totality = $(QuoteNode(totality)),
            operand_rule = :numeric)
end

for operation in (<, <=, >, >=, ==, !=)
    identity = if operation === (<)
        :less
    elseif operation === (<=)
        :less_equal
    elseif operation === (>)
        :greater
    elseif operation === (>=)
        :greater_equal
    elseif operation === (==)
        :equal
    else
        :not_equal
    end
    operand_rule = operation in (==, !=) ? :any : :numeric
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer($(QuoteNode(identity)), 2, :boolean, :comparison;
            operand_rule = $(QuoteNode(operand_rule)))
end

operation_transfer(::typeof(&), ::Int) =
    _transfer(:and, 2, :boolean, :dimensionless; operand_rule = :boolean)
operation_transfer(::typeof(|), ::Int) =
    _transfer(:or, 2, :boolean, :dimensionless; operand_rule = :boolean)
operation_transfer(::typeof(!), ::Int) =
    _transfer(:not, 1, :boolean, :dimensionless; operand_rule = :boolean)
operation_transfer(::typeof(ifelse), ::Int) =
    _transfer(:ifelse, 3, :branch_promote, :branch;
        operand_rule = :ifelse)

for operation in (abs, exp, log, sqrt)
    identity = if operation === abs
        :absolute
    elseif operation === exp
        :exponential
    elseif operation === log
        :logarithm
    else
        :square_root
    end
    unit_rule = operation in (exp, log) ? :dimensionless :
                operation === sqrt ? :square_root : :unary
    totality = operation in (log, sqrt) ? :domain_checked : :total
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)),
            1,
            :preserve_numeric,
            $(QuoteNode(unit_rule));
            totality = $(QuoteNode(totality)),
            operand_rule = :numeric,
        )
end

for operation in (
        source_site, target_site, source_cell, target_cell, source_kind,
        target_kind,
    )
    identity = nameof(operation)
    footprint_rule = operation in (source_site, source_cell, source_kind) ?
                     ProposalSourceFootprintRule() :
                     ProposalTargetFootprintRule()
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, :integer, :dimensionless;
            footprint_rule = $footprint_rule,
            allowed_roles = (:drive, :constraint, :modifier, :process),
            allowed_phases = (:Proposal, :AcceptedCopy),
            required_context = :proposal,
        )
end

for operation in (is_extension, is_retraction, new_contact, lost_contact, linked)
    identity = nameof(operation)
    arity = operation === linked ? 3 : operation in (new_contact, lost_contact) ? 2 : 1
    footprint_rule = operation === linked ?
        IncidentRelationshipFootprintRule() :
        ProposalSourceTargetFootprintRule()
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), $arity, :boolean, :dimensionless;
            footprint_rule = $footprint_rule,
            allowed_roles = (:drive, :constraint, :modifier, :process),
            allowed_phases = (:Proposal, :AcceptedCopy),
            required_context = :proposal,
        )
end

operation_transfer(::typeof(_potts_proposal_bound_state_value), ::Int) =
    _transfer(
        :proposal_bound_state_value,
        1,
        :real,
        :declared;
        footprint_rule = ProposalTargetFootprintRule(),
        allowed_phases = (:Proposal, :AcceptedCopy),
        required_context = :proposal,
    )

operation_transfer(::typeof(_potts_iteration_bound_state_value), ::Int) =
    _transfer(
        :iteration_bound_state_value,
        1,
        :real,
        :declared;
        footprint_rule = IterationSiteFootprintRule(),
        allowed_phases = (:AfterMCS,),
        required_context = :iteration,
    )

operation_transfer(::typeof(_potts_model_bound_state_value), ::Int) =
    _transfer(
        :model_bound_state_value,
        1,
        :real,
        :declared;
        footprint_rule = InheritFootprintRule(),
        allowed_phases = (:AfterMCS,),
        required_context = :iteration,
    )

operation_transfer(::typeof(_potts_lifecycle_bound_state_value), ::Int) =
    _transfer(
        :lifecycle_bound_state_value,
        1,
        :real,
        :declared;
        footprint_rule = OwnerFootprintRule(),
        allowed_roles = (
            :lifecycle_trigger,
            :lifecycle_placement,
            :lifecycle_partition,
            :lifecycle_state_transform,
        ),
        allowed_phases = (:Lifecycle,),
        required_context = :any,
        owner = :PottsToolkitLifecycleCompiler,
    )

operation_transfer(::typeof(_potts_bounded_fold), ::Int) =
    _transfer(
        :bounded_fold,
        4,
        :real,
        :declared;
        totality = :transaction_checked,
        footprint_rule = NeighborhoodFootprintRule(OperandNeighborhoodAnchors()),
        allowed_roles = (:hamiltonian,),
        allowed_phases = (:Proposal,),
        required_context = :hamiltonian,
    )

for operation in (
        cell_elongation, cell_center, unwrapped_center, endpoint_a,
        endpoint_b,
    )
    identity = nameof(operation)
    result_rule = operation in (endpoint_a, endpoint_b) ? :integer : :real
    footprint_rule = operation in (endpoint_a, endpoint_b) ?
                     IncidentRelationshipFootprintRule() :
                     OwnerFootprintRule()
    tracker_requirements = operation in (
        cell_elongation, cell_center, unwrapped_center,
    ) ? (:cell_moments,) : ()
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, $(QuoteNode(result_rule)), :declared;
            footprint_rule = $footprint_rule,
            tracker_requirements = $(QuoteNode(tracker_requirements)),
        )
end


operation_transfer(::typeof(cell_volume), ::Int) =
    _transfer(
        :cell_volume,
        1,
        :real,
        :lattice_volume;
        footprint_rule = OwnerFootprintRule(),
    )


operation_transfer(::typeof(cell_surface), ::Int) =
    _transfer(
        :cell_surface,
        1,
        :real,
        :dimensionless;
        footprint_rule = OwnerFootprintRule(),
        tracker_requirements = (:cell_surface,),
        allowed_roles = (
            :hamiltonian,
            :lifecycle_trigger,
            :lifecycle_state_transform,
        ),
        allowed_phases = (:Proposal, :Lifecycle),
        required_context = :any,
        source_requirements = (NamedSpatialRelationRequirement(:surface),),
    )

operation_transfer(::typeof(degree), ::Int) =
    _transfer(
        :degree, 2, :integer, :declared;
        footprint_rule = IncidentRelationshipFootprintRule(),
    )

for operation in (
        contact_owner_a, contact_owner_b, contact_kind_a, contact_kind_b,
    )
    identity = nameof(operation)
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, :integer, :dimensionless;
            footprint_rule = ContactFootprintRule(),
        )
end

operation_transfer(::typeof(occupancy), ::Int) =
    _transfer(
        :occupancy, 2, :real, :declared;
        footprint_rule = InheritFootprintRule(),
    )

function _spatial_query_interface_transfer(
        identity::Symbol,
        arity::Integer,
        result_rule::Symbol,
    )
    return _transfer(
        identity,
        arity,
        result_rule,
        :declared;
        cpu = false,
        gpu = false,
        footprint_rule = InheritFootprintRule(),
        allowed_roles = (:observation,),
        allowed_phases = (:none,),
        required_context = :any,
        owner = :PottsToolkitSpatialQueryInterface,
    )
end

operation_transfer(::typeof(contact_edge_count), ::Int) =
    _spatial_query_interface_transfer(:contact_edge_count, 2, :integer)
operation_transfer(::typeof(contact_measure), ::Int) =
    _spatial_query_interface_transfer(:contact_measure, 3, :real)
operation_transfer(::typeof(boundary_site_count), ::Int) =
    _spatial_query_interface_transfer(:boundary_site_count, 2, :integer)
operation_transfer(::typeof(neighbor_cell_count), ::Int) =
    _spatial_query_interface_transfer(:neighbor_cell_count, 2, :integer)
operation_transfer(::typeof(neighbor_property_sum), ::Int) =
    _spatial_query_interface_transfer(:neighbor_property_sum, 3, :real)
operation_transfer(::typeof(neighbor_property_mean), ::Int) =
    _spatial_query_interface_transfer(:neighbor_property_mean, 4, :real)
operation_transfer(::typeof(global_interface_measure), ::Int) =
    _spatial_query_interface_transfer(:global_interface_measure, 3, :real)

const _INTERFACE_ONLY_SPATIAL_QUERY_OPERATIONS = (
    contact_edge_count,
    contact_measure,
    boundary_site_count,
    neighbor_cell_count,
    neighbor_property_sum,
    neighbor_property_mean,
    global_interface_measure,
)

const _INTERFACE_ONLY_SPATIAL_QUERY_IDENTITIES = (
    :contact_edge_count,
    :contact_measure,
    :boundary_site_count,
    :neighbor_cell_count,
    :neighbor_property_sum,
    :neighbor_property_mean,
    :global_interface_measure,
)

for operation in (
        distance, field_value, field_gradient, laplacian, history_value,
        edge_payload, lag,
    )
    identity = nameof(operation)
    result_rule = :real
    footprint_rule = if operation in (edge_payload, lag)
        IncidentRelationshipFootprintRule()
    elseif operation === laplacian
        NeighborhoodFootprintRule(IterationNeighborhoodAnchor())
    else
        InheritFootprintRule()
    end
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 2, $(QuoteNode(result_rule)), :declared;
            footprint_rule = $footprint_rule,
        )
end

operation_transfer(::typeof(_potts_draw), ::Int) =
    _transfer(
        :draw, 4, :real, :distribution;
        purity = :semantic_rng,
        totality = :requires_prelaunch_validation,
        footprint_rule = InheritFootprintRule(),
        allowed_roles = (
            :drive,
            :constraint,
            :modifier,
            :process,
            :lifecycle_trigger,
            :lifecycle_placement,
            :lifecycle_partition,
            :lifecycle_state_transform,
        ),
        allowed_phases = (:Proposal, :AcceptedCopy, :Lifecycle),
        required_context = :any,
    )
