# Cold CorePotts lowering from scientific descriptor expressions to bounded
# LocalMath requirements. The ordinary records built here are construction
# scratch and never enter a Plan, PreparedPlan, or kernel argument.

_contextual_operation_identity(::ContextOperation{Identity}) where {Identity} =
    Identity
_contextual_operation_identity(::ResourceOperation{Identity}) where {Identity} =
    Identity
_contextual_operation_identity(
    operation::QualifiedTrackerOperation,
) = (
    operation = _contextual_operation_identity(operation.operation),
    quantity = operation.quantity,
    source_handle = operation.source_handle,
)
_contextual_operation_identity(operation::AbstractContextualOperation) =
    typeof(operation)

function _proposal_descriptor_source(plan::DescriptorExecutionPlan, handle::Int32)
    1 <= handle <= length(plan.source_table) || throw(ArgumentError(
        "proposal descriptor source handle $(handle) is outside the source table"
    ))
    return plan.source_table[Int(handle)]
end

function _proposal_descriptors_in_source_order(plan::DescriptorExecutionPlan)
    descriptors = ProposalDescriptor[]
    for group in plan.groups, descriptor in group.launch.instances
        descriptor isa ProposalDescriptor || throw(ArgumentError(
            "checkerboard compilation requires proposal descriptors"
        ))
        push!(descriptors, descriptor)
    end
    sort!(descriptors; by = descriptor -> descriptor.source_handle)
    for (left, right) in zip(descriptors, Iterators.drop(descriptors, 1))
        left.source_handle != right.source_handle || throw(ArgumentError(
            "proposal source $(left.source_handle) has more than one descriptor occurrence"
        ))
    end
    return descriptors
end

function _validate_proposal_footprint(footprint, source)
    footprint isa Union{
        EmptyFootprint,
        ModelFootprint,
        ProposalContextFootprint,
        OwnerFootprint,
        ContactFootprint,
        FiniteSpatialFootprint,
        IncidentRelationshipFootprint,
    } && return nothing
    if footprint isa FootprintUnion
        foreach(part -> _validate_proposal_footprint(part, source),
            footprint.footprints)
        return nothing
    end
    if footprint isa FootprintMinkowski
        _validate_proposal_footprint(footprint.left, source)
        _validate_proposal_footprint(footprint.right, source)
        return nothing
    end
    throw(ArgumentError(
        "proposal source $(repr(source)) has unsupported or unbounded footprint " *
        string(typeof(footprint))
    ))
end

function _record_proposal_expression!(
        records,
        expression::LiteralExpression,
        descriptor,
        source,
        path::Tuple,
    )
    return records
end

function _record_proposal_expression!(
        records,
        expression::ParameterExpression,
        descriptor,
        source,
        path::Tuple,
    )
    expression.index == 0 || push!(records, (
        kind = :parameter,
        identity = expression.index,
        source_handle = descriptor.source_handle,
        source,
        role = descriptor.role,
        access = descriptor.access,
        path,
        expression,
    ))
    return records
end

function _record_proposal_expression!(
        records,
        expression::StateExpression,
        descriptor,
        source,
        path::Tuple,
    )
    push!(records, (
        kind = :state_handle,
        identity = expression.handle,
        source_handle = descriptor.source_handle,
        source,
        role = descriptor.role,
        access = descriptor.access,
        path,
        expression,
    ))
    return records
end

function _record_proposal_expression!(
        records,
        expression::ContextExpression,
        descriptor,
        source,
        path::Tuple,
    )
    operation = expression.operation
    push!(records, (
        kind = :context,
        identity = _contextual_operation_identity(operation),
        source_handle = descriptor.source_handle,
        source,
        role = descriptor.role,
        access = descriptor.access,
        path,
        operation,
    ))
    return records
end

function _record_proposal_expression!(
        records,
        expression::OperationExpression,
        descriptor,
        source,
        path::Tuple,
    )
    operation = expression.operation
    if operation isa AbstractContextualOperation
        push!(records, (
            kind = :operation,
            identity = _contextual_operation_identity(operation),
            source_handle = descriptor.source_handle,
            source,
            role = descriptor.role,
            access = descriptor.access,
            path,
            operation,
        ))
    end
    for (index, argument) in pairs(expression.arguments)
        _record_proposal_expression!(
            records, argument, descriptor, source, (path..., Int32(index)))
    end
    return records
end

function _record_proposal_expression!(
        records,
        expression::AbstractStaticExpression,
        descriptor,
        source,
        path::Tuple,
    )
    throw(ArgumentError(
        "proposal source $(repr(source)) contains unsupported expression " *
        string(typeof(expression)) * " at path " * repr(path)
    ))
end

function _proposal_gather_inventory(plan::DescriptorExecutionPlan)
    records = Any[]
    descriptors = _proposal_descriptors_in_source_order(plan)
    for descriptor in descriptors
        source = _proposal_descriptor_source(plan, descriptor.source_handle)
        _validate_proposal_footprint(descriptor.access.footprint, source)
        _record_proposal_expression!(
            records,
            descriptor.evaluator.expression,
            descriptor,
            source,
            (),
        )
    end
    return (
        descriptors = Tuple(descriptors),
        records = Tuple(records),
        source_count = Int32(length(plan.source_table)),
    )
end

function _proposal_parameter_count(inventory)
    maximum((Int(record.identity) for record in inventory.records
        if record.kind === :parameter); init = 0)
end

function _proposal_state_handles(inventory)
    handles = StateHandle[]
    for record in inventory.records
        record.kind === :state_handle || continue
        handle = record.identity
        any(==(handle), handles) || push!(handles, handle)
    end
    return Tuple(handles)
end

_state_handle_element_type(
    ::StateHandle{StateStorageRepresentation{
        ElementType,Dimensions,Layout,Adaptation}},
) where {ElementType,Dimensions,Layout,Adaptation} = ElementType

# Executable scalar terms produced by the cold proposal compiler. These are
# ordinary concrete callable values, not StaticEvaluator syntax, and are the
# only form admitted to a LocalMath evaluator.
struct _ExecutableLiteral{T}
    value::T
end

struct _ExecutableDefaultParameter{T}
    value::T
end

struct _ExecutableParameter{Index,T}
    default::T
end

struct _ExecutableStateReference{Index,H}
    handle::H
end
@inline _executable_state_slot(::_ExecutableStateReference{Index}) where {Index} =
    Index

struct _ExecutableProposalContext{Identity} end

struct _ExecutableScalarCall{F,A<:Tuple}
    operation::F
    arguments::A
end

struct _ExecutableIntegerPower{N,A}
    argument::A
end

function _static_integer_power_expression(value, exponent::Int)
    iszero(exponent) && return :(one($value))
    exponent == 1 && return value
    if exponent < 0
        exponent == typemin(Int) && throw(ArgumentError(
            "the minimum machine integer is not a supported static exponent"))
        return :(inv($(_static_integer_power_expression(value, -exponent))))
    end
    half = gensym(:half)
    half_expression = _static_integer_power_expression(value, exponent >>> 1)
    product = iseven(exponent) ? :($half * $half) : :($half * $half * $value)
    return :(let $half = $half_expression
        $product
    end)
end

@generated function _static_integer_power(value, ::Val{N}) where {N}
    N isa Int || return :(throw(ArgumentError("static exponent must be Int")))
    return Expr(:block, Expr(:meta, :inline),
        _static_integer_power_expression(:value, N))
end

struct _ExecutableContextualCall{F,A<:Tuple}
    operation::F
    arguments::A
end

struct _GatheredQualifiedTrackerCall{Q,F,A<:Tuple}
    operation::F
    arguments::A
    source_handle::Int32
end

struct _ExecutableProposalTerm{E,R}
    evaluator::E
    role::R
    source_handle::Int32
end

struct _ExecutableAcceptedSiteTerm{C,V,H}
    condition::C
    value::V
    target::H
    source_handle::Int32
    buffer_slot::Int32
    descriptor_ordinal::Int32
end

struct _ExecutableAcceptedRelationshipTerm{C,A,B,P,Z}
    condition::C
    endpoint_a::A
    endpoint_b::B
    payload::P
    payload_zero::Z
    relationship_slot::Int32
    bank_index::Int32
    bank_slot::Int32
    priority::Int32
    source_handle::Int32
    descriptor_ordinal::Int32
    relationship_ordinal::Int32
    evaluation_offset::Int32
end

function _accepted_site_descriptors(stage_plan::StageExecutionPlan)
    records = NamedTuple[]
    ordinal = Int32(0)
    for group in stage_plan.accepted_copy, descriptor in group.instances
        ordinal += Int32(1)
        descriptor.effect isa SiteAssignmentEffect || continue
        push!(records, (; descriptor, ordinal))
    end
    return Tuple(records)
end

function _accepted_relationship_descriptors(stage_plan::StageExecutionPlan)
    records = NamedTuple[]
    ordinal = Int32(0)
    for group in stage_plan.accepted_copy, descriptor in group.instances
        ordinal += Int32(1)
        descriptor.effect isa RelationshipCreateEffect || continue
        push!(records, (; descriptor, ordinal))
    end
    return Tuple(records)
end

_record_expression_requirements!(handles, parameter_count, ::LiteralExpression) =
    nothing
function _record_expression_requirements!(
        handles, parameter_count, expression::ParameterExpression)
    parameter_count[] = max(parameter_count[], Int(expression.index))
    return nothing
end
function _record_expression_requirements!(
        handles, parameter_count, expression::StateExpression)
    any(==(expression.handle), handles) || push!(handles, expression.handle)
    return nothing
end
_record_expression_requirements!(
    handles, parameter_count, ::ContextExpression) = nothing
function _record_expression_requirements!(
        handles, parameter_count, expression::OperationExpression)
    foreach(expression.arguments) do argument
        _record_expression_requirements!(handles, parameter_count, argument)
    end
    return nothing
end
function _record_expression_requirements!(
        handles, parameter_count, expression::AbstractStaticExpression)
    throw(ArgumentError(
        "checkerboard compilation encountered unsupported stage expression " *
        string(typeof(expression))))
end

_record_tracker_requirements!(keys, ::AbstractStaticExpression) = nothing
function _record_tracker_requirements!(
        keys, expression::OperationExpression)
    operation = expression.operation
    if operation isa QualifiedTrackerOperation
        key = QualifiedTrackerKey(
            operation.quantity, operation.source_handle)
        any(isequal(key), keys) || push!(keys, key)
    end
    foreach(expression.arguments) do argument
        _record_tracker_requirements!(keys, argument)
    end
    return nothing
end

_record_moment_requirement!(required, ::AbstractStaticExpression) = nothing
function _record_moment_requirement!(required, expression::OperationExpression)
    operation = expression.operation
    if operation isa Union{
            ResourceOperation{:cell_center},
            ResourceOperation{:unwrapped_center},
            ResourceOperation{:cell_elongation},
        }
        required[] = true
    end
    foreach(expression.arguments) do argument
        _record_moment_requirement!(required, argument)
    end
    return nothing
end

_record_relationship_requirements!(handles, ::AbstractStaticExpression) = nothing
function _record_relationship_requirements!(
        handles, expression::OperationExpression)
    operation = expression.operation
    if operation isa Union{
            ResourceOperation{:degree},
            ResourceOperation{:linked},
        }
        first_argument = first(expression.arguments)
        first_argument isa LiteralExpression || throw(ArgumentError(
            "checkerboard relationship operations require a compiled " *
            "literal relationship handle"))
        handle = Int32(first_argument.value)
        any(==(handle), handles) || push!(handles, handle)
    end
    foreach(expression.arguments) do argument
        _record_relationship_requirements!(handles, argument)
    end
    return nothing
end

function _tracker_requirement_descriptors(keys, tracker_plan)
    instances = tracker_instances(tracker_plan)
    return Tuple(map(keys) do key
        index = findfirst(
            descriptor -> isequal(tracker_quantity(descriptor), key),
            instances)
        index === nothing && throw(ArgumentError(
            "checkerboard compilation requires unavailable tracker " *
            repr(key)))
        descriptor = instances[index]
        tracker_storage(descriptor) isa DenseOwnerScalarStorage || throw(
            ArgumentError(
                "checkerboard gathered tracker reads require dense scalar storage for " *
                repr(key)))
        descriptor
    end)
end


function _moment_requirement_descriptor(required::Bool, tracker_plan)
    required || return nothing
    instances = tracker_instances(tracker_plan)
    index = findfirst(descriptor -> descriptor isa CellMomentsTracker, instances)
    index === nothing && throw(ArgumentError(
        "checkerboard compilation requires the cell-moment tracker for " *
        "cell_center, unwrapped_center, or cell_elongation"))
    return instances[index]
end

function _checkerboard_scientific_requirements(
        inventory, stage_plan, ownership_change_handles, tracker_plan)
    handles = StateHandle[_proposal_state_handles(inventory)...]
    parameter_count = Ref(_proposal_parameter_count(inventory))
    affected_handles = StateHandle[]
    tracker_keys = QualifiedTrackerKey[]
    relationship_handles = Int32[]
    moment_required = Ref(false)
    for descriptor in inventory.descriptors
        role = descriptor.role
        if role isa HamiltonianRole{
                <:RelationshipEnergyDomainPlan,
                <:IncidentRelationshipsAffectedPlan}
            handle = role.domain.relationship_handle
            any(==(handle), relationship_handles) ||
                push!(relationship_handles, handle)
        end
        _record_tracker_requirements!(
            tracker_keys, descriptor.evaluator.expression)
        _record_moment_requirement!(
            moment_required, descriptor.evaluator.expression)
        _record_relationship_requirements!(
            relationship_handles, descriptor.evaluator.expression)
    end
    for record in _accepted_site_descriptors(stage_plan)
        descriptor = record.descriptor
        _record_expression_requirements!(
            handles, parameter_count, descriptor.condition.expression)
        _record_expression_requirements!(
            handles, parameter_count, descriptor.value.expression)
        _record_tracker_requirements!(
            tracker_keys, descriptor.condition.expression)
        _record_tracker_requirements!(
            tracker_keys, descriptor.value.expression)
        _record_moment_requirement!(
            moment_required, descriptor.condition.expression)
        _record_moment_requirement!(
            moment_required, descriptor.value.expression)
        _record_relationship_requirements!(
            relationship_handles, descriptor.condition.expression)
        _record_relationship_requirements!(
            relationship_handles, descriptor.value.expression)
        any(==(descriptor.effect.target), handles) ||
            push!(handles, descriptor.effect.target)
        any(==(descriptor.effect.target), affected_handles) ||
            push!(affected_handles, descriptor.effect.target)
    end
    for record in _accepted_relationship_descriptors(stage_plan)
        descriptor = record.descriptor
        effect = descriptor.effect
        _record_expression_requirements!(
            handles, parameter_count, descriptor.condition.expression)
        _record_expression_requirements!(
            handles, parameter_count, effect.endpoint_a.expression)
        _record_expression_requirements!(
            handles, parameter_count, effect.endpoint_b.expression)
        _record_tracker_requirements!(
            tracker_keys, descriptor.condition.expression)
        _record_tracker_requirements!(
            tracker_keys, effect.endpoint_a.expression)
        _record_tracker_requirements!(
            tracker_keys, effect.endpoint_b.expression)
        _record_moment_requirement!(
            moment_required, descriptor.condition.expression)
        _record_moment_requirement!(
            moment_required, effect.endpoint_a.expression)
        _record_moment_requirement!(
            moment_required, effect.endpoint_b.expression)
        _record_relationship_requirements!(
            relationship_handles, descriptor.condition.expression)
        _record_relationship_requirements!(
            relationship_handles, effect.endpoint_a.expression)
        _record_relationship_requirements!(
            relationship_handles, effect.endpoint_b.expression)
        for evaluator in effect.payload
            _record_expression_requirements!(
                handles, parameter_count, evaluator.expression)
            _record_tracker_requirements!(tracker_keys, evaluator.expression)
            _record_moment_requirement!(moment_required, evaluator.expression)
            _record_relationship_requirements!(
                relationship_handles, evaluator.expression)
        end
    end
    for handle in ownership_change_handles
        any(==(handle), handles) || push!(handles, handle)
        any(==(handle), affected_handles) || push!(affected_handles, handle)
    end
    return (; state_handles = Tuple(handles),
        accepted_state_handles = Tuple(affected_handles),
        parameter_count = parameter_count[],
        tracker_keys = Tuple(tracker_keys),
        tracker_descriptors = _tracker_requirement_descriptors(
            tracker_keys, tracker_plan),
        moment_descriptor = _moment_requirement_descriptor(
            moment_required[], tracker_plan),
        relationship_handles = Tuple(relationship_handles))
end


function _accepted_descriptor_source(
        descriptor_plan::DescriptorExecutionPlan, source_handle::Int32)
    return 1 <= source_handle <= length(descriptor_plan.source_table) ?
        _proposal_descriptor_source(descriptor_plan, source_handle) :
        source_handle
end


function _compile_accepted_relationship_terms(
        stage_plan::StageExecutionPlan,
        descriptor_plan::DescriptorExecutionPlan,
        state_handles::Tuple,
        relationship_schemas::RelationshipStorage,
        relationship_state::RelationshipStorage,
    )
    length(relationship_schemas) == length(relationship_state) || throw(
        ArgumentError("relationship schemas and packed state are misaligned"))
    records = _accepted_relationship_descriptors(stage_plan)
    offset = Int32(1)
    terms = map(enumerate(records)) do indexed
        relationship_ordinal, record = indexed
        descriptor = record.descriptor
        effect = descriptor.effect
        source = _accepted_descriptor_source(
            descriptor_plan, descriptor.source_handle)
        _validate_proposal_footprint(descriptor.access.footprint, source)
        location = _relationship_location(
            relationship_schemas, Int(effect.relationship_slot))
        bank = relationship_state.banks[Int(location.bank)]
        bank isa PackedRelationshipBank || throw(ArgumentError(
            "checkerboard relationship compilation requires packed banks"))
        payload_zero = map(values -> zero(eltype(values)), bank.payload)
        length(payload_zero) == length(effect.payload) || throw(ArgumentError(
            "relationship payload evaluator count disagrees with packed storage"))
        term = _ExecutableAcceptedRelationshipTerm(
            _compile_proposal_expression(
                descriptor.condition.expression, source, state_handles),
            _compile_proposal_expression(
                effect.endpoint_a.expression, source, state_handles),
            _compile_proposal_expression(
                effect.endpoint_b.expression, source, state_handles),
            map(effect.payload) do evaluator
                _compile_proposal_expression(
                    evaluator.expression, source, state_handles)
            end,
            payload_zero,
            effect.relationship_slot,
            location.bank,
            location.slot,
            effect.priority,
            descriptor.source_handle,
            record.ordinal,
            Int32(relationship_ordinal),
            offset,
        )
        offset += Int32(3 + length(payload_zero))
        return term
    end
    return Tuple(terms)
end

function _accepted_relationship_fields(source::LocalMath.Space, terms::Tuple)
    names = Symbol[]
    fields = Any[]
    for (term_index, term) in enumerate(terms)
        push!(names, Symbol(:accepted_relationship_, term_index, :_code))
        push!(fields, LocalMath.Field(source, UInt8))
        push!(names, Symbol(:accepted_relationship_, term_index, :_endpoints))
        push!(fields, LocalMath.Field(source, Tuple{Int32,Int32}))
        for (payload_index, prototype) in enumerate(term.payload_zero)
            push!(names, Symbol(:accepted_relationship_, term_index,
                :_payload_, payload_index))
            push!(fields, LocalMath.Field(source, typeof(prototype)))
        end
    end
    return NamedTuple{Tuple(names)}(Tuple(fields))
end

function _accepted_site_fields(
        source::LocalMath.Space, terms::Tuple, ::Type{T}) where {T}
    names = Symbol[]
    fields = Any[]
    for index in eachindex(terms)
        push!(names, Symbol(:accepted_site_, index, :_code))
        push!(fields, LocalMath.Field(source, UInt8))
        push!(names, Symbol(:accepted_site_, index, :_value))
        push!(fields, LocalMath.Field(source, T))
    end
    return NamedTuple{Tuple(names)}(Tuple(fields))
end

function _accepted_site_field_groups(fields::NamedTuple, terms::Tuple)
    storage = values(fields)
    return ntuple(length(terms)) do index
        (code = getfield(storage, 2index - 1),
            value = getfield(storage, 2index))
    end
end

function _accepted_relationship_field_groups(fields::NamedTuple, terms::Tuple)
    storage = values(fields)
    offset = 1
    groups = map(terms) do term
        payload_count = length(term.payload_zero)
        group = (
            code = getfield(storage, offset),
            endpoints = getfield(storage, offset + 1),
            payload = ntuple(payload_count) do payload
                getfield(storage, offset + 1 + payload)
            end,
        )
        offset += 2 + payload_count
        return group
    end
    return Tuple(groups)
end

function _compile_accepted_site_terms(
        stage_plan::StageExecutionPlan,
        descriptor_plan::DescriptorExecutionPlan,
        state_handles::Tuple,
    )
    records = _accepted_site_descriptors(stage_plan)
    return Tuple(map(records) do record
        descriptor = record.descriptor
        source = _accepted_descriptor_source(
            descriptor_plan, descriptor.source_handle)
        _validate_proposal_footprint(descriptor.access.footprint, source)
        _ExecutableAcceptedSiteTerm(
            _compile_proposal_expression(
                descriptor.condition.expression, source, state_handles),
            _compile_proposal_expression(
                descriptor.value.expression, source, state_handles),
            descriptor.effect.target,
            descriptor.source_handle,
            descriptor.buffer_slot,
            record.ordinal,
        )
    end)
end

_gathered_contextual_operation_supported(
    ::ResourceOperation{:occupancy}) = true
_gathered_contextual_operation_supported(
    ::ResourceOperation{:cell_volume}) = true
_gathered_contextual_operation_supported(
    ::ResourceOperation{:field_value}) = true
_gathered_contextual_operation_supported(
    ::ResourceOperation{:draw}) = true
_gathered_contextual_operation_supported(
    ::ResourceOperation{:bounded_fold}) = true
_gathered_contextual_operation_supported(
    ::ResourceOperation{:distance}) = true
_gathered_contextual_operation_supported(::Union{
    ResourceOperation{:cell_center},
    ResourceOperation{:unwrapped_center},
    ResourceOperation{:cell_elongation},
}) = true
_gathered_contextual_operation_supported(
    ::Union{
        ResourceOperation{:contact_owner_a},
        ResourceOperation{:contact_owner_b},
        ResourceOperation{:contact_kind_a},
        ResourceOperation{:contact_kind_b},
        ResourceOperation{:endpoint_a},
        ResourceOperation{:endpoint_b},
        ResourceOperation{:edge_payload},
        ResourceOperation{:degree},
        ResourceOperation{:linked},
        ResourceOperation{:new_contact},
        ResourceOperation{:lost_contact},
    }) = true
_gathered_contextual_operation_supported(::Union{
    ContextOperation{:source_site},
    ContextOperation{:target_site},
    ContextOperation{:source_cell},
    ContextOperation{:target_cell},
    ContextOperation{:source_kind},
    ContextOperation{:target_kind},
    ContextOperation{:is_extension},
    ContextOperation{:is_retraction},
    ContextOperation{:energy_anchor_site},
    ContextOperation{:energy_anchor_cell},
    ContextOperation{:energy_anchor_contact},
    ContextOperation{:energy_anchor_relationship},
}) = true
_gathered_contextual_operation_supported(::ContextOperation) = false
_gathered_contextual_operation_supported(::QualifiedTrackerOperation) = true
_gathered_contextual_operation_supported(
    ::Union{ResourceOperation,QualifiedTrackerOperation}) = false
_gathered_contextual_operation_supported(
    operation::AbstractContextualOperation,
) = operation_context_supported(
    operation, AbstractProposalEvaluationContext)

function _validate_gathered_operation_arguments(
    ::ResourceOperation{:field_value}, arguments, source)
    length(arguments) == 2 && arguments[1] isa StateExpression &&
        arguments[2] isa ContextExpression &&
        _contextual_operation_identity(arguments[2].operation) in
            (:source_site, :target_site) || throw(ArgumentError(
        "proposal source $(repr(source)) requires field_value at the " *
        "bounded source or target proposal site"
    ))
    return nothing
end


function _validate_gathered_operation_arguments(
        ::ResourceOperation{:bounded_fold}, arguments, source)
    length(arguments) == 4 &&
    arguments[1] isa LiteralExpression &&
    arguments[1].value isa LocalMath.BoundedFold &&
    arguments[2] isa StateExpression &&
    arguments[3] isa LiteralExpression &&
    arguments[3].value isa Integer || throw(ArgumentError(
        "proposal source $(repr(source)) requires bounded_fold with a " *
        "literal LocalMath.BoundedFold, a bound state, and a declared " *
        "bounded relation handle"))
    return nothing
end

_validate_gathered_operation_arguments(
    ::AbstractContextualOperation, arguments, source) = nothing

function _validate_gathered_operation_arguments(
        ::QualifiedTrackerOperation, arguments, source)
    length(arguments) == 1 || throw(ArgumentError(
        "proposal source $(repr(source)) requires a unary qualified tracker operation"))
    return nothing
end

function _compile_proposal_expression(
        expression::LiteralExpression, source, state_handles)
    return _ExecutableLiteral(expression.value)
end

function _compile_proposal_expression(
        expression::ParameterExpression, source, state_handles)
    iszero(expression.index) && return _ExecutableDefaultParameter(
        expression.default)
    return _ExecutableParameter{
        Int(expression.index), typeof(expression.default)}(expression.default)
end

function _compile_proposal_expression(
        expression::ContextExpression, source, state_handles)
    operation = expression.operation
    operation isa ContextOperation &&
        _gathered_contextual_operation_supported(operation) || throw(ArgumentError(
        "proposal source $(repr(source)) requires contextual operation " *
        "$(repr(_contextual_operation_identity(operation))) without a " *
        "bounded gathered lowering"
    ))
    return _ExecutableProposalContext{
        _contextual_operation_identity(operation)}()
end

function _compile_proposal_expression(
        expression::StateExpression, source, state_handles)
    slot = findfirst(==(expression.handle), state_handles)
    slot === nothing && throw(ArgumentError(
        "proposal source $(repr(source)) references an uninventoried state handle"
    ))
    return _ExecutableStateReference{
        Int(slot), typeof(expression.handle)}(expression.handle)
end

function _compile_proposal_expression(
        expression::OperationExpression, source, state_handles)
    operation = expression.operation
    arguments = map(expression.arguments) do argument
        _compile_proposal_expression(argument, source, state_handles)
    end
    if operation isa AbstractContextualOperation
        _gathered_contextual_operation_supported(operation) || throw(
            ArgumentError(
                "proposal source $(repr(source)) requires contextual operation " *
                "$(repr(_contextual_operation_identity(operation))) without a " *
                "bounded gathered lowering"
            ))
        _validate_gathered_operation_arguments(
            operation, expression.arguments, source)
        if operation isa QualifiedTrackerOperation
            quantity = only(typeof(operation.quantity).parameters)
            return _GatheredQualifiedTrackerCall{
                quantity,typeof(operation.operation),typeof(arguments)}(
                operation.operation, arguments, operation.source_handle)
        end
        return _ExecutableContextualCall(operation, arguments)
    end
    if operation === (^) && length(expression.arguments) == 2 &&
            expression.arguments[2] isa LiteralExpression &&
            expression.arguments[2].value isa Integer
        exponent = Int(expression.arguments[2].value)
        argument = first(arguments)
        return _ExecutableIntegerPower{exponent,typeof(argument)}(argument)
    end
    return _ExecutableScalarCall(operation, arguments)
end

function _compile_proposal_terms(
        plan::DescriptorExecutionPlan,
        state_handles::Tuple = _proposal_state_handles(
            _proposal_gather_inventory(plan)),
    )
    inventory = _proposal_gather_inventory(plan)
    return Tuple(map(inventory.descriptors) do descriptor
        source = _proposal_descriptor_source(plan, descriptor.source_handle)
        role = descriptor.role
        role isa Union{
            ProposalDriveRole,
            ProposalEnergyDriveRole,
            ProposalModifierRole,
            ProposalConstraintRole,
        HamiltonianRole{<:SiteEnergyDomainPlan,<:TargetSiteAffectedPlan},
        HamiltonianRole{<:SiteEnergyDomainPlan,<:NeighborhoodSitesAffectedPlan},
            HamiltonianRole{<:CellEnergyDomainPlan,<:SourceTargetCellsAffectedPlan},
            HamiltonianRole{<:ContactEnergyDomainPlan,<:IncidentContactsAffectedPlan},
            HamiltonianRole{<:RelationshipEnergyDomainPlan,<:IncidentRelationshipsAffectedPlan},
        } || throw(ArgumentError(
            "proposal source $(repr(source)) requires unsupported Hamiltonian " *
            "domain or affected-anchor lowering $(typeof(role))"
        ))
        _ExecutableProposalTerm(
            _compile_proposal_expression(
                descriptor.evaluator.expression, source, state_handles),
            role,
            descriptor.source_handle,
        )
    end)
end

@inline _execute_proposal_scalar(value::_ExecutableLiteral, context) =
    value.value
@inline _execute_proposal_scalar(value::_ExecutableDefaultParameter, context) =
    value.value
@inline _execute_proposal_scalar(
    ::_ExecutableParameter{Index}, context) where {Index} =
    getfield(_proposal_parameters(context), Index)
@inline _execute_proposal_scalar(
    value::_ExecutableStateReference, context) = value
@inline _gathered_proposal(context) = context
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:source_site}, context) =
    _gathered_proposal(context).source
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:target_site}, context) =
    _gathered_proposal(context).target
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:source_cell}, context) =
    _gathered_proposal(context).new_owner
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:target_cell}, context) =
    _gathered_proposal(context).old_owner
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:source_kind}, context) =
    _gathered_proposal(context).new_kind
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:target_kind}, context) =
    _gathered_proposal(context).old_kind
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:is_extension}, context) =
    _gathered_proposal(context).old_owner <= 0 &&
        _gathered_proposal(context).new_owner > 0
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:is_retraction}, context) =
    _gathered_proposal(context).old_owner > 0 &&
        _gathered_proposal(context).new_owner <= 0
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:energy_anchor_site}, context) = context.anchor
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:energy_anchor_cell}, context) = context.anchor
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:energy_anchor_contact}, context) = context.anchor
@inline _execute_proposal_scalar(
    ::_ExecutableProposalContext{:energy_anchor_relationship}, context) =
    context.anchor

@inline _execute_proposal_arguments(::Tuple{}, context) = ()
@inline function _execute_proposal_arguments(arguments::Tuple, context)
    return (
        _execute_proposal_scalar(first(arguments), context),
        _execute_proposal_arguments(Base.tail(arguments), context)...,
    )
end

@inline function _execute_proposal_ordered_tail(
        operation, ::Tuple{}, context, accumulator)
    return accumulator
end
@inline function _execute_proposal_ordered_tail(
        operation, arguments::Tuple, context, accumulator)
    value = _execute_proposal_scalar(first(arguments), context)
    return _execute_proposal_ordered_tail(
        operation, Base.tail(arguments), context,
        operation(accumulator, value))
end

@inline function _execute_proposal_ordered(
        operation, arguments::Tuple{A}, context) where {A}
    return operation(_execute_proposal_scalar(first(arguments), context))
end
@inline function _execute_proposal_ordered(
        operation, arguments::Tuple{A,B}, context) where {A,B}
    first_value = _execute_proposal_scalar(getfield(arguments, 1), context)
    second_value = _execute_proposal_scalar(getfield(arguments, 2), context)
    return operation(first_value, second_value)
end
@inline function _execute_proposal_ordered(
        operation, arguments::Tuple{A,B,C,Vararg}, context) where {A,B,C}
    accumulator = _execute_proposal_scalar(first(arguments), context)
    return _execute_proposal_ordered_tail(
        operation, Base.tail(arguments), context, accumulator)
end

@inline function _execute_proposal_scalar(
        call::_ExecutableScalarCall{<:OrderedFold}, context)
    operation = getfield(getfield(call, :operation), :operation)
    return _execute_proposal_ordered(
        operation, getfield(call, :arguments), context)
end

@inline function _execute_proposal_scalar(
        call::_ExecutableScalarCall, context)
    arguments = _execute_proposal_arguments(call.arguments, context)
    return call.operation(arguments...)
end


@inline function _execute_proposal_scalar(
    call::_ExecutableIntegerPower{N}, context) where {N}
    value = _execute_proposal_scalar(call.argument, context)
    return _static_integer_power(value, Val(N))
end

@inline function _execute_proposal_scalar(
        call::_ExecutableContextualCall{
            ResourceOperation{:bounded_fold},Tuple{A,B,C,D}}, context,
    ) where {A,B,C,D}
    arguments = getfield(call, :arguments)
    fold = _execute_proposal_scalar(getfield(arguments, 1), context)
    reference = _execute_proposal_scalar(getfield(arguments, 2), context)
    relation_handle = _execute_proposal_scalar(getfield(arguments, 3), context)
    _execute_proposal_scalar(getfield(arguments, 4), context)
    return _gathered_bounded_fold(
        fold, reference, relation_handle, context)
end

@inline function _execute_proposal_scalar(
        call::_ExecutableContextualCall, context)
    arguments = _execute_proposal_arguments(call.arguments, context)
    return call.operation(arguments, context)
end


@inline function _execute_proposal_scalar(
        call::_GatheredQualifiedTrackerCall{Quantity}, context) where {Quantity}
    arguments = _execute_proposal_arguments(call.arguments, context)
    return qualified_tracker_operation_call(
        call.operation, arguments, context, Val(Quantity), call.source_handle)
end

struct _GatheredProposalContext{
        I,T,P,V,S,O,K,RS,RO,RK,R,TV,TD,MF,MS,MD,RR,
    }
    source::I
    target::I
    target_linear::Int32
    old_owner::Int32
    new_owner::Int32
    old_kind::Int16
    new_kind::Int16
    volumes::NTuple{2,Int32}
    semantic::Int32
    mcs::Int64
    color::Int32
    trajectory_seed::UInt64
    scalar_zero::T
    parameters::P
    state_values::V
    contact_sites::S
    contact_owners::O
    contact_kinds::K
    reverse_contact_sites::RS
    reverse_contact_owners::RO
    reverse_contact_kinds::RK
    contact_ranges::R
    tracker_values::TV
    tracker_descriptors::TD
    moment_first::MF
    moment_second::MS
    moment_descriptor::MD
    relationship_resources::RR
end

@generated function _gathered_proposal_context(arguments...)
    length(arguments) == 28 || error(
        "gathered proposal context construction schema changed")
    context_type = _GatheredProposalContext{
        arguments[1],arguments[13:28]...}
    values = (:(getfield(arguments, $index)) for index in 1:28)
    return :($context_type($(values...)))
end

struct _GatheredAnchorEnergyContext{C,I}
    proposal::C
    after::Bool
    anchor::I
    relationship_handle::Int32
end
_GatheredAnchorEnergyContext(proposal, after::Bool, anchor) =
    _GatheredAnchorEnergyContext(proposal, after, anchor, Int32(0))

struct _GatheredContactAnchor
    first::Int32
    second::Int32
end

@inline _gathered_contact_lookup(
    site::Int32, ::Tuple{}, ::Tuple{}, fallback,
) = fallback
@inline function _gathered_contact_lookup(
        site::Int32, sites::Tuple, values::Tuple, fallback)
    site == first(sites) && return first(values)
    return _gathered_contact_lookup(
        site, Base.tail(sites), Base.tail(values), fallback)
end

@inline function _gathered_site_owner(
        context::_GatheredAnchorEnergyContext, site::Int32)
    proposal = context.proposal
    site == proposal.target_linear &&
        return context.after ? proposal.new_owner : proposal.old_owner
    forward = _gathered_contact_lookup(
        site, proposal.contact_sites, proposal.contact_owners, Int32(0))
    forward != 0 && return forward
    return _gathered_contact_lookup(
        site, proposal.reverse_contact_sites,
        proposal.reverse_contact_owners, Int32(0))
end

@inline function _gathered_site_kind(
        context::_GatheredAnchorEnergyContext, site::Int32)
    proposal = context.proposal
    site == proposal.target_linear &&
        return context.after ? proposal.new_kind : proposal.old_kind
    forward = _gathered_contact_lookup(
        site, proposal.contact_sites, proposal.contact_kinds, Int16(0))
    forward != 0 && return forward
    return _gathered_contact_lookup(
        site, proposal.reverse_contact_sites,
        proposal.reverse_contact_kinds, Int16(0))
end

@inline _gathered_proposal(context::_GatheredAnchorEnergyContext) =
    context.proposal

@inline function owner_kind(
        context::_GatheredProposalContext, owner::Integer)
    value = Int32(owner)
    value == context.old_owner && return context.old_kind
    value == context.new_owner && return context.new_kind
    value < 0 && return Int16(-value)
    return Int16(0)
end
@inline owner_kind(
    context::_GatheredAnchorEnergyContext, owner::Integer,
) = owner_kind(context.proposal, owner)

@inline _proposal_parameters(context::_GatheredProposalContext) =
    context.parameters
@inline _proposal_parameters(context::_GatheredAnchorEnergyContext) =
    context.proposal.parameters

@inline function state_value(
        context::_GatheredAnchorEnergyContext,
        reference::_ExecutableStateReference, site,
    )
    return _gathered_state_value(context.proposal, reference, site)
end

@inline function _gathered_state_value(
        context::_GatheredProposalContext,
        ::_ExecutableStateReference{Index}, site,
    ) where {Index}
    values = getfield(context.state_values, Index)
    site == context.target && return values.sites[1]
    site == context.source && return values.sites[2]
    for sample in values.contacts
        sample.present && sample.endpoint == site && return something(sample.value)
    end
    for sample in values.reverse_contacts
        sample.present && sample.endpoint == site && return something(sample.value)
    end
    return values.sites[1]
end

@inline _gathered_fold_anchor(context::_GatheredProposalContext) =
    context.target_linear
@inline function _gathered_fold_anchor(context::_GatheredAnchorEnergyContext)
    anchor = context.anchor
    return anchor isa Int32 ? anchor : context.proposal.target_linear
end

@inline _gathered_tuple_position(
    value::Int32, ::Tuple{}, index::Int32 = Int32(1),
) = Int32(0)
@inline function _gathered_tuple_position(
        value::Int32, values::Tuple, index::Int32 = Int32(1))
    value == first(values) && return index
    return _gathered_tuple_position(
        value, Base.tail(values), index + Int32(1))
end

@inline state_value(
    context::_GatheredProposalContext,
    reference::_ExecutableStateReference,
    site,
) = _gathered_state_value(context, reference, site)

@inline function apply_resource_operation(
        ::ResourceOperation{:field_value}, arguments,
        context::_GatheredProposalContext)
    return state_value(context, first(arguments), last(arguments))
end

@inline function apply_resource_operation(
        ::ResourceOperation{:field_value}, arguments,
        context::_GatheredAnchorEnergyContext)
    return state_value(context, first(arguments), last(arguments))
end

@inline function _gathered_bounded_fold(
        fold, reference, relation_handle, context)
    relation_handle = Int32(relation_handle)
    proposal = _gathered_proposal(context)
    start, count = _gathered_contact_range(
        relation_handle, proposal.contact_ranges...)
    values = getfield(proposal.state_values, _executable_state_slot(reference))
    anchor = _gathered_fold_anchor(context)
    center_lane = anchor == proposal.target_linear ? Int32(0) :
        _gathered_tuple_position(anchor, proposal.reverse_contact_sites)
    first_lane = iszero(center_lane) ? start :
        (center_lane - Int32(1)) * Int32(length(proposal.contact_sites)) + start
    samples = iszero(center_lane) ? values.contacts : values.affected_contacts
    outcome = LocalMath.evaluate_bounded(fold, samples, first_lane, count)
    outcome.valid && return outcome.value
    value = outcome.value
    return value isa AbstractFloat ? oftype(value, NaN) : value
end

@inline _gathered_bounded_fold(arguments, context) =
    _gathered_bounded_fold(
        getfield(arguments, 1), getfield(arguments, 2),
        getfield(arguments, 3), context)

@inline apply_resource_operation(
    ::ResourceOperation{:bounded_fold}, arguments,
    context::_GatheredProposalContext) = _gathered_bounded_fold(arguments, context)
@inline apply_resource_operation(
    ::ResourceOperation{:bounded_fold}, arguments,
    context::_GatheredAnchorEnergyContext) = _gathered_bounded_fold(arguments, context)

@inline apply_resource_operation(
    ::ResourceOperation{:distance}, arguments::Tuple{A,B},
    ::Union{_GatheredProposalContext,_GatheredAnchorEnergyContext},
) where {A,B} = _center_distance(
    getfield(arguments, 1), getfield(arguments, 2))

@inline function apply_resource_operation(
        ::ResourceOperation{:draw}, arguments,
        context::_GatheredProposalContext)
    T = typeof(context.scalar_zero)
    family = Int(first(arguments))
    first_parameter = T(arguments[2])
    second_parameter = T(arguments[3])
    operation = UInt16(arguments[4])
    first_address = _program_address(
        ExplicitProposalDrawStream, context.mcs, operation,
        context.semantic; subround = context.color, draw = 0)
    first_uniform = uniform_open01(
        T, Philox4x32x10V2(), context.trajectory_seed, first_address)
    family == 1 && return first_uniform < first_parameter
    family == 2 && return muladd(
        first_uniform, second_parameter - first_parameter, first_parameter)
    if family == 3
        iszero(second_parameter) && return first_parameter
        second_address = _program_address(
            ExplicitProposalDrawStream, context.mcs, operation,
            context.semantic; subround = context.color, draw = 1)
        second_uniform = uniform_open01(
            T, Philox4x32x10V2(), context.trajectory_seed, second_address)
        normal = sqrt(-T(2) * log(first_uniform)) *
            cos(T(2pi) * second_uniform)
        return muladd(second_parameter, normal, first_parameter)
    end
    return T(NaN)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:occupancy}, arguments,
        context::_GatheredAnchorEnergyContext)
    kind = Int16(first(arguments))
    proposal = context.proposal
    site = last(arguments)
    linear = site == proposal.target ? proposal.target_linear : Int32(site)
    owner_kind = _gathered_site_kind(context, linear)
    return owner_kind == kind
end

@inline apply_resource_operation(
    ::ResourceOperation{:contact_owner_a}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_site_owner(context, only(arguments).first)
@inline apply_resource_operation(
    ::ResourceOperation{:contact_owner_b}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_site_owner(context, only(arguments).second)
@inline apply_resource_operation(
    ::ResourceOperation{:contact_kind_a}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_site_kind(context, only(arguments).first)
@inline apply_resource_operation(
    ::ResourceOperation{:contact_kind_b}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_site_kind(context, only(arguments).second)

@inline function _gathered_relationship_resource(
        handle::Int32, resources::Tuple)
    resource = first(resources)
    resource.handle == handle && return resource
    return _gathered_relationship_resource(handle, Base.tail(resources))
end
@inline _gathered_relationship_resource(handle::Int32, ::Tuple{}) = throw(
    ArgumentError("compiled gathered relationship resource is unavailable"))

@inline function _gathered_relationship_sample(
        read, edge::Int32, edge_offset::Int32)
    global_edge = edge_offset + edge - Int32(1)
    lane = Int32(1)
    while lane <= length(read)
        sample = @inbounds read[Int(lane)]
        sample.present && sample.endpoint == global_edge && return sample
        lane += Int32(1)
    end
    return nothing
end

@inline function _gathered_relationship_lane(
        read, edge::Int32, edge_offset::Int32)
    global_edge = edge_offset + edge - Int32(1)
    lane = Int32(1)
    while lane <= length(read)
        sample = @inbounds read[Int(lane)]
        sample.present && sample.endpoint == global_edge && return lane
        lane += Int32(1)
    end
    return Int32(0)
end

@inline function _gathered_relationship_owner_lane(
        resource, anchor, owner::Int32)
    lane = _gathered_relationship_lane(
        resource.active, Int32(anchor), resource.edge_offset)
    lane > 0 || return Int32(0)
    endpoint_a = @inbounds resource.endpoint_a[Int(lane)]
    endpoint_b = @inbounds resource.endpoint_b[Int(lane)]
    endpoint_a.present && something(endpoint_a.value) == owner &&
        return Int32(2) * lane - Int32(1)
    endpoint_b.present && something(endpoint_b.value) == owner &&
        return Int32(2) * lane
    return Int32(0)
end

@generated function _gathered_relationship_components(
        components::Tuple, slot::Int32)
    values = Expr(:tuple)
    for component in 1:fieldcount(components)
        push!(values.args, quote
            local sample = @inbounds getfield(components, $component)[Int(slot)]
            something(sample.value)
        end)
    end
    return values
end

@inline _gathered_relationship_owner_volume(
    handle::Int32, anchor, owner::Int32, ::Tuple{},
) = nothing
@inline function _gathered_relationship_owner_volume(
        handle::Int32, anchor, owner::Int32, resources::Tuple)
    resource = first(resources)
    if resource.handle == handle
        slot = _gathered_relationship_owner_lane(resource, anchor, owner)
        slot > 0 || return nothing
        sample = @inbounds resource.endpoint_volumes[Int(slot)]
        return sample.present ? Int32(something(sample.value)) : nothing
    end
    return _gathered_relationship_owner_volume(
        handle, anchor, owner, Base.tail(resources))
end

@inline _gathered_relationship_owner_moments(
    handle::Int32, anchor, owner::Int32, ::Tuple{},
) = nothing
@inline function _gathered_relationship_owner_moments(
        handle::Int32, anchor, owner::Int32, resources::Tuple)
    resource = first(resources)
    if resource.handle == handle
        slot = _gathered_relationship_owner_lane(resource, anchor, owner)
        slot > 0 || return nothing
        return (
            _gathered_relationship_components(resource.moment_first, slot),
            _gathered_relationship_components(resource.moment_second, slot),
        )
    end
    return _gathered_relationship_owner_moments(
        handle, anchor, owner, Base.tail(resources))
end

@inline function _gathered_relationship_endpoint(
        context::_GatheredAnchorEnergyContext, ::Val{Endpoint}) where {Endpoint}
    edge = Int32(context.anchor)
    resource = _gathered_relationship_resource(
        context.relationship_handle,
        context.proposal.relationship_resources)
    read = Endpoint === :a ? resource.endpoint_a : resource.endpoint_b
    sample = _gathered_relationship_sample(
        read, edge, resource.edge_offset)
    sample === nothing && throw(ArgumentError(
        "compiled gathered relationship endpoint is unavailable"))
    return something(sample.value)
end

@inline apply_resource_operation(
    ::ResourceOperation{:endpoint_a}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_relationship_endpoint(context, Val(:a))
@inline apply_resource_operation(
    ::ResourceOperation{:endpoint_b}, arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_relationship_endpoint(context, Val(:b))

@inline function apply_resource_operation(
        ::ResourceOperation{:edge_payload}, arguments,
        context::_GatheredAnchorEnergyContext)
    edge = Int32(first(arguments))
    payload_slot = Int(last(arguments))
    resource = _gathered_relationship_resource(
        context.relationship_handle,
        context.proposal.relationship_resources)
    1 <= payload_slot <= length(resource.payload) || throw(ArgumentError(
        "compiled gathered relationship payload slot is unavailable"))
    sample = _gathered_relationship_sample(
        getfield(resource.payload, payload_slot), edge,
        resource.edge_offset)
    sample === nothing && throw(ArgumentError(
        "compiled gathered relationship payload is unavailable"))
    return something(sample.value)
end

@inline function _gathered_relationship_edge_seen(
        read, edge::Int32, lane::Int32)
    prior = Int32(1)
    while prior < lane
        sample = @inbounds read[Int(prior)]
        sample.present && sample.endpoint == edge && return true
        prior += Int32(1)
    end
    return false
end

@inline function apply_resource_operation(
        ::ResourceOperation{:degree}, arguments,
        context::_GatheredProposalContext)
    handle = Int32(first(arguments))
    owner = Int32(last(arguments))
    owner > 0 || return Int32(0)
    resource = _gathered_relationship_resource(
        handle, context.relationship_resources)
    count = Int32(0)
    lane = Int32(1)
    while lane <= length(resource.active)
        active = @inbounds resource.active[Int(lane)]
        if active.present && something(active.value) &&
                !_gathered_relationship_edge_seen(
                    resource.active, active.endpoint, lane)
            a = something(@inbounds resource.endpoint_a[Int(lane)].value)
            b = something(@inbounds resource.endpoint_b[Int(lane)].value)
            count += (a == owner || b == owner)
        end
        lane += Int32(1)
    end
    return count
end

@inline function apply_resource_operation(
        ::ResourceOperation{:linked}, arguments,
        context::_GatheredProposalContext)
    handle = Int32(arguments[1])
    endpoint_a = Int32(arguments[2])
    endpoint_b = Int32(arguments[3])
    (endpoint_a > 0 && endpoint_b > 0) || return false
    expected_a, expected_b = _canonical_endpoints(endpoint_a, endpoint_b)
    resource = _gathered_relationship_resource(
        handle, context.relationship_resources)
    lane = Int32(1)
    while lane <= length(resource.active)
        active = @inbounds resource.active[Int(lane)]
        if active.present && something(active.value)
            a = something(@inbounds resource.endpoint_a[Int(lane)].value)
            b = something(@inbounds resource.endpoint_b[Int(lane)].value)
            a == expected_a && b == expected_b && return true
        end
        lane += Int32(1)
    end
    return false
end

@inline apply_resource_operation(
    ::Union{ResourceOperation{:new_contact},ResourceOperation{:lost_contact}},
    arguments,
    context::Union{_GatheredProposalContext,_GatheredAnchorEnergyContext},
) = _proposal_endpoint_pair(arguments, _gathered_proposal(context))

@inline _gathered_contact_range(
    handle::Int32, ::Tuple{}, ::Tuple{}, index::Int32 = Int32(1),
) = (Int32(0), Int32(0))
@inline function _gathered_contact_range(
        handle::Int32, starts::Tuple, counts::Tuple,
        index::Int32 = Int32(1))
    handle == index && return (first(starts), first(counts))
    return _gathered_contact_range(
        handle, Base.tail(starts), Base.tail(counts), index + Int32(1))
end

@inline function _gathered_owner_volume(proposal::_GatheredProposalContext,
        owner::Int32)
    owner <= 0 && return Int32(0)
    return owner == proposal.old_owner ? proposal.volumes[1] :
        owner == proposal.new_owner ? proposal.volumes[2] : Int32(0)
end

@inline function _gathered_owner_volume(context::_GatheredAnchorEnergyContext,
        owner::Int32)
    proposal = context.proposal
    volume = _gathered_owner_volume(proposal, owner)
    if owner != proposal.old_owner && owner != proposal.new_owner
        relationship_volume = _gathered_relationship_owner_volume(
            context.relationship_handle, context.anchor, owner,
            proposal.relationship_resources)
        relationship_volume === nothing || (volume = relationship_volume)
    end
    if context.after && proposal.old_owner != proposal.new_owner
        owner == proposal.old_owner && (volume -= Int32(1))
        owner == proposal.new_owner && (volume += Int32(1))
    end
    return volume
end

@inline _gathered_owner_moment(::Tuple{}, owner_lane::Int) = ()
@inline function _gathered_owner_moment(values::Tuple, owner_lane::Int)
    return (
        getfield(first(values), owner_lane),
        _gathered_owner_moment(Base.tail(values), owner_lane)...,
    )
end

@inline _gathered_target_coordinates(target, ::Tuple{}, ::Type{T}, dimension::Int) where {T} = ()
@inline function _gathered_target_coordinates(
        target, components::Tuple, ::Type{T}, dimension::Int = 1,
    ) where {T}
    return (
        T(target[dimension]) - T(0.5),
        _gathered_target_coordinates(
            target, Base.tail(components), T, dimension + 1)...,
    )
end

@inline _gathered_update_first(
    ::Tuple{}, ::Tuple{}, remove::Bool, add::Bool,
) = ()
@inline function _gathered_update_first(
        values::Tuple, coordinates::Tuple, remove::Bool, add::Bool)
    value = first(values)
    remove && (value -= first(coordinates))
    add && (value += first(coordinates))
    return (
        value,
        _gathered_update_first(
            Base.tail(values), Base.tail(coordinates), remove, add)...,
    )
end

@inline _gathered_update_second(
    ::Tuple{}, coordinates::Tuple, remove::Bool, add::Bool, slot::Int,
) = ()
@inline function _gathered_update_second(
        values::Tuple, coordinates::Tuple,
        remove::Bool, add::Bool, slot::Int = 1)
    dimensions = length(coordinates)
    row = rem(slot - 1, dimensions) + 1
    column = div(slot - 1, dimensions) + 1
    value = first(values)
    product = coordinates[row] * coordinates[column]
    remove && (value -= product)
    add && (value += product)
    return (
        value,
        _gathered_update_second(
            Base.tail(values), coordinates, remove, add, slot + 1)...,
    )
end

@inline _gathered_scale_tuple(::Tuple{}, inverse) = ()
@inline function _gathered_scale_tuple(values::Tuple, inverse)
    return (
        first(values) * inverse,
        _gathered_scale_tuple(Base.tail(values), inverse)...,
    )
end

@inline _gathered_covariance_tuple(
    ::Tuple{}, center::Tuple, inverse, slot::Int,
) = ()
@inline function _gathered_covariance_tuple(
        second::Tuple, center::Tuple, inverse, slot::Int = 1)
    dimensions = length(center)
    row = rem(slot - 1, dimensions) + 1
    column = div(slot - 1, dimensions) + 1
    return (
        first(second) * inverse - center[row] * center[column],
        _gathered_covariance_tuple(
            Base.tail(second), center, inverse, slot + 1)...,
    )
end

@inline function _gathered_moment_totals(
        context::_GatheredAnchorEnergyContext,
        owner::Int32,
        ::CellMomentsTracker{N,T},
    ) where {N,T}
    proposal = context.proposal
    lane = owner == proposal.old_owner ? 1 :
        owner == proposal.new_owner ? 2 : 0
    if lane == 0
        moments = _gathered_relationship_owner_moments(
            context.relationship_handle, context.anchor, owner,
            proposal.relationship_resources)
        moments === nothing && return nothing
        first, second = moments
    else
        first = _gathered_owner_moment(proposal.moment_first, lane)
        second = _gathered_owner_moment(proposal.moment_second, lane)
    end
    count = _gathered_owner_volume(context, owner)
    if context.after && proposal.old_owner != proposal.new_owner
        coordinates = _gathered_target_coordinates(
            proposal.target, first, T)
        remove = owner == proposal.old_owner
        add = owner == proposal.new_owner
        first = _gathered_update_first(first, coordinates, remove, add)
        second = _gathered_update_second(second, coordinates, remove, add)
    end
    return count, first, second
end

@inline function _gathered_cell_center(
        context::_GatheredAnchorEnergyContext, owner::Int32)
    owner > 0 || return nothing
    descriptor = context.proposal.moment_descriptor
    descriptor === nothing && throw(ArgumentError(
        "compiled gathered cell-center tracker is unavailable"))
    totals = _gathered_moment_totals(context, owner, descriptor)
    totals === nothing && return nothing
    count, first, _ = totals
    count > 0 || return nothing
    T = eltype(first)
    inverse = inv(T(count))
    return _gathered_scale_tuple(first, inverse)
end

@inline function _gathered_cell_elongation(
        context::_GatheredAnchorEnergyContext, owner::Int32)
    owner > 0 || return context.proposal.scalar_zero
    descriptor = context.proposal.moment_descriptor
    descriptor === nothing && throw(ArgumentError(
        "compiled gathered cell-moment tracker is unavailable"))
    totals = _gathered_moment_totals(context, owner, descriptor)
    totals === nothing && return context.proposal.scalar_zero
    count, first, second = totals
    count > 0 || return context.proposal.scalar_zero
    T = eltype(first)
    N = length(first)
    inverse = inv(T(count))
    center = _gathered_scale_tuple(first, inverse)
    covariance = _gathered_covariance_tuple(second, center, inverse)
    maximum_variance = _maximum_covariance_eigenvalue(Val(N), covariance)
    return T(4) * sqrt(max(zero(T), maximum_variance))
end

@inline function _gathered_tracker_slot(
        quantity::Val, source_handle::Int32,
        descriptors::Tuple{Any,Vararg{Any}},
        values::Tuple{Any,Vararg{Any}})
    key = tracker_quantity(first(descriptors))
    key isa QualifiedTrackerKey && key.quantity === quantity &&
        key.source_handle == source_handle &&
        return (first(descriptors), first(values))
    return _gathered_tracker_slot(
        quantity, source_handle,
        Base.tail(descriptors), Base.tail(values))
end
@inline _gathered_tracker_slot(
    quantity, source_handle, ::Tuple{}, ::Tuple{},
) =
    throw(ArgumentError("compiled gathered tracker key is unavailable"))

@inline function _gathered_tracker_value(
        context::_GatheredAnchorEnergyContext,
        quantity::Val, source_handle::Int32, owner::Int32)
    owner <= 0 && return Int32(0)
    proposal = context.proposal
    descriptor, pair = _gathered_tracker_slot(
        quantity, source_handle, proposal.tracker_descriptors,
        proposal.tracker_values)
    value = owner == proposal.old_owner ? pair[1] :
        owner == proposal.new_owner ? pair[2] : zero(first(pair))
    context.after || return value
    delta = _checkerboard_scalar_tracker_delta(
        descriptor, proposal.contact_sites, proposal.contact_owners,
        proposal.contact_ranges,
        (proposal.target_linear, proposal.target),
        proposal.old_owner, proposal.new_owner)
    return _scalar_value_after(
        value, delta, owner, proposal.old_owner, proposal.new_owner)
end

@inline tracker_operation_value(
    context::_GatheredAnchorEnergyContext,
    quantity::Val,
    source_handle::Int32,
    owner::Int32,
) = _gathered_tracker_value(context, quantity, source_handle, owner)

@inline qualified_tracker_operation_call(
    ::ResourceOperation{:cell_surface},
    arguments::Tuple,
    context::_GatheredAnchorEnergyContext,
    quantity::Val,
    source_handle::Int32,
) = tracker_operation_value(
    context, quantity, source_handle, Int32(only(arguments)))


@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume}, arguments,
        context::_GatheredProposalContext)
    return _gathered_owner_volume(context, Int32(only(arguments)))
end

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume}, arguments,
        context::_GatheredAnchorEnergyContext)
    return _gathered_owner_volume(context, Int32(only(arguments)))
end

@inline apply_resource_operation(
    ::Union{ResourceOperation{:cell_center},ResourceOperation{:unwrapped_center}},
    arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_cell_center(context, Int32(only(arguments)))

@inline apply_resource_operation(
    ::ResourceOperation{:cell_elongation},
    arguments,
    context::_GatheredAnchorEnergyContext,
) = _gathered_cell_elongation(context, Int32(only(arguments)))

@inline evaluator_parameters(context::_GatheredAnchorEnergyContext) =
    context.proposal.parameters
@inline _compiled_evaluator_parameters(context::_GatheredAnchorEnergyContext) =
    context.proposal.parameters

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:ProposalDriveRole}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    value = T(_execute_proposal_scalar(term.evaluator, context))
    return ProposalEvaluation(zero(T), zero(T), value, zero(T), true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:ProposalEnergyDriveRole}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    value = T(_execute_proposal_scalar(term.evaluator, context))
    return ProposalEvaluation(zero(T), value, zero(T), zero(T), true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:ProposalModifierRole}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    value = T(_execute_proposal_scalar(term.evaluator, context))
    return ProposalEvaluation(zero(T), zero(T), zero(T), value, true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:ProposalConstraintRole}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    value = _execute_proposal_scalar(term.evaluator, context)
    value isa Bool || throw(ArgumentError(
        "proposal constraint source $(term.source_handle) does not return Bool"))
    return ProposalEvaluation(zero(T), zero(T), zero(T), zero(T), value)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole{
            <:SiteEnergyDomainPlan,<:TargetSiteAffectedPlan}}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    before = _GatheredAnchorEnergyContext(context, false, context.target)
    after = _GatheredAnchorEnergyContext(context, true, context.target)
    value = T(_execute_proposal_scalar(term.evaluator, after)) -
            T(_execute_proposal_scalar(term.evaluator, before))
    return ProposalEvaluation(value, zero(T), zero(T), zero(T), true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole{
            <:SiteEnergyDomainPlan,<:NeighborhoodSitesAffectedPlan}}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    role = term.role
    starts, counts = context.contact_ranges
    start, count = _gathered_contact_range(
        role.affected.relation_handle, starts, counts)
    target = context.target_linear
    before = _gathered_anchor_energy(
        term.evaluator, context, target, false, true, T)
    after = _gathered_anchor_energy(
        term.evaluator, context, target, true, true, T)
    delta = after - before
    accepted = Int32(1)
    lane = Int32(0)
    while lane < count
        center = @inbounds context.reverse_contact_sites[Int(start + lane)]
        if center > 0 && center != target
            duplicate = false
            prior = Int32(0)
            while prior < lane
                duplicate |= @inbounds(
                    context.reverse_contact_sites[Int(start + prior)]) == center
                prior += Int32(1)
            end
            if !duplicate
                accepted += Int32(1)
                accepted <= role.affected.maximum || return
                    ProposalEvaluation(T(NaN), zero(T), zero(T), zero(T), true)
                before = _gathered_anchor_energy(
                    term.evaluator, context, center, false, true, T)
                after = _gathered_anchor_energy(
                    term.evaluator, context, center, true, true, T)
                delta += after - before
            end
        end
        lane += Int32(1)
    end
    return ProposalEvaluation(delta, zero(T), zero(T), zero(T), true)
end

@inline function _gathered_anchor_energy(
        evaluator, context, anchor, after::Bool, present::Bool, ::Type{T},
    ) where {T<:AbstractFloat}
    present || return zero(T)
    return T(_execute_proposal_scalar(
        evaluator, _GatheredAnchorEnergyContext(context, after, anchor)))
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole{
            <:CellEnergyDomainPlan,<:SourceTargetCellsAffectedPlan}}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    role = term.role
    kind = role.domain.kind
    old_owner = context.old_owner
    new_owner = context.new_owner
    delta = zero(T)
    if old_owner > 0 && context.old_kind == kind
        before = _gathered_anchor_energy(
            term.evaluator, context, old_owner, false, true, T)
        after = _gathered_anchor_energy(
            term.evaluator, context, old_owner, true,
            _gathered_owner_volume(context, old_owner) > Int32(1), T)
        delta += after - before
    end
    if new_owner > 0 && new_owner != old_owner && context.new_kind == kind
        before = _gathered_anchor_energy(
            term.evaluator, context, new_owner, false,
            _gathered_owner_volume(context, new_owner) > Int32(0), T)
        after = _gathered_anchor_energy(
            term.evaluator, context, new_owner, true, true, T)
        delta += after - before
    end
    return ProposalEvaluation(delta, zero(T), zero(T), zero(T), true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole{
            <:ContactEnergyDomainPlan,<:IncidentContactsAffectedPlan}}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    starts, counts = context.contact_ranges
    start, count = _gathered_contact_range(
        term.role.domain.relation_handle, starts, counts)
    delta = zero(T)
    lane = Int32(0)
    accepted = Int32(0)
    while lane < count
        slot = start + lane
        neighbor = @inbounds context.contact_sites[Int(slot)]
        if neighbor > 0
            duplicate = false
            prior = Int32(0)
            while prior < lane
                duplicate |= @inbounds(
                    context.contact_sites[Int(start + prior)]) == neighbor
                prior += Int32(1)
            end
            if !duplicate
                accepted += Int32(1)
                accepted <= term.role.affected.maximum || return
                    ProposalEvaluation(T(NaN), zero(T), zero(T), zero(T), true)
                target = context.target_linear
                anchor = target <= neighbor ?
                    _GatheredContactAnchor(target, neighbor) :
                    _GatheredContactAnchor(neighbor, target)
                before = _gathered_anchor_energy(
                    term.evaluator, context, anchor, false, true, T)
                after = _gathered_anchor_energy(
                    term.evaluator, context, anchor, true, true, T)
                delta += after - before
            end
        end
        lane += Int32(1)
    end
    return ProposalEvaluation(delta, zero(T), zero(T), zero(T), true)
end

@inline function _gathered_relationship_owner_present(
        context, owner::Int32, after::Bool)
    owner > 0 || return false
    proposal = context
    if owner == proposal.old_owner || owner == proposal.new_owner
        view = _GatheredAnchorEnergyContext(proposal, after, owner)
        return _gathered_owner_volume(view, owner) > 0
    end
    # Packed relationship integrity proves unaffected endpoints are live at
    # stage entry. Only the proposal's old/new owners can change volume here.
    return true
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole{
            <:RelationshipEnergyDomainPlan,
            <:IncidentRelationshipsAffectedPlan}}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    role = term.role
    handle = role.domain.relationship_handle
    resource = _gathered_relationship_resource(
        handle, context.relationship_resources)
    delta = zero(T)
    accepted = Int32(0)
    lane = Int32(1)
    while lane <= length(resource.active)
        active_sample = @inbounds resource.active[Int(lane)]
        if active_sample.present && something(active_sample.value)
            global_edge = active_sample.endpoint
            edge = global_edge - resource.edge_offset + Int32(1)
            duplicate = false
            prior = Int32(1)
            while prior < lane
                sample = @inbounds resource.active[Int(prior)]
                duplicate |= sample.present && sample.endpoint == global_edge
                prior += Int32(1)
            end
            if !duplicate
                accepted += Int32(1)
                accepted <= role.affected.maximum || return
                    ProposalEvaluation(T(NaN), zero(T), zero(T), zero(T), true)
                a = something(@inbounds resource.endpoint_a[Int(lane)].value)
                b = something(@inbounds resource.endpoint_b[Int(lane)].value)
                before_present =
                    _gathered_relationship_owner_present(context, a, false) &&
                    _gathered_relationship_owner_present(context, b, false)
                after_present =
                    _gathered_relationship_owner_present(context, a, true) &&
                    _gathered_relationship_owner_present(context, b, true)
                before = before_present ? T(_execute_proposal_scalar(
                    term.evaluator,
                    _GatheredAnchorEnergyContext(
                        context, false, edge, handle))) : zero(T)
                after = after_present ? T(_execute_proposal_scalar(
                    term.evaluator,
                    _GatheredAnchorEnergyContext(
                        context, true, edge, handle))) : zero(T)
                delta += after - before
            end
        end
        lane += Int32(1)
    end
    return ProposalEvaluation(delta, zero(T), zero(T), zero(T), true)
end

@inline function _proposal_term_evaluation(
        term::_ExecutableProposalTerm{E,<:HamiltonianRole}, context,
        ::Type{T}) where {E,T<:AbstractFloat}
    throw(ArgumentError(
        "Hamiltonian source $(term.source_handle) requires affected-anchor lowering"
    ))
end

@inline _fold_executable_proposal_terms(
    ::Tuple{}, context, ::Type{T}, result::ProposalEvaluation{T},
) where {T<:AbstractFloat} = result

@inline function _fold_executable_proposal_terms(
        terms::Tuple, context, ::Type{T}, result::ProposalEvaluation{T},
    ) where {T<:AbstractFloat}
    contribution = _proposal_term_evaluation(
        first(terms), context, T)::ProposalEvaluation{T}
    combined = ProposalEvaluation(
        getfield(result, :delta_h) + getfield(contribution, :delta_h),
        getfield(result, :drive_energy) +
            getfield(contribution, :drive_energy),
        getfield(result, :drive_log_bias) +
            getfield(contribution, :drive_log_bias),
        getfield(result, :kinetic_modifier) +
            getfield(contribution, :kinetic_modifier),
        getfield(result, :constraints_allowed) &
            getfield(contribution, :constraints_allowed),
    )
    return _fold_executable_proposal_terms(
        Base.tail(terms), context, T, combined)
end

@inline function _fold_executable_proposal_terms(
        terms::Tuple, context, ::Type{T}) where {T<:AbstractFloat}
    return _fold_executable_proposal_terms(
        terms, context, T, _neutral_proposal_evaluation(T))
end

struct _CheckerboardProposalDomain end
struct _CheckerboardLatticeDomain end
struct _CheckerboardCellDomain end

struct _CheckerboardGeometryEvaluator{N,O}
    shape::NTuple{N,Int}
    periodic::NTuple{N,Bool}
    offsets::O
    trajectory_seed::UInt64
    site_count::Int32
end

@inline function _checkerboard_neighbor_linear(
        shape::NTuple{N,Int},
        periodic::NTuple{N,Bool},
        target_linear::Int32,
        offset::NTuple{N,Int8},
    ) where {N}
    target = CartesianIndices(shape)[Int(target_linear)]
    coordinates = Tuple(target)
    source = ntuple(Val(N)) do dimension
        value = coordinates[dimension] + Int(offset[dimension])
        periodic[dimension] ? mod1(value, shape[dimension]) :
            1 <= value <= shape[dimension] ? value : 0
    end
    any(iszero, source) && return Int32(0)
    return Int32(LinearIndices(shape)[CartesianIndex(source)])
end

@inline function (evaluator::_CheckerboardGeometryEvaluator)(
        item::Int32, reads, parameters,
    )
    target_options = something(@inbounds reads[1][1].value)
    mcs = getfield(parameters, 1)
    color = getfield(parameters, 2)
    attempt_round = getfield(parameters, 3)
    target = @inbounds target_options[color]
    semantic = (attempt_round - Int32(1)) * evaluator.site_count + target
    direction_address = _program_address(
        ProposalDirectionStream, Int(mcs), 2, semantic; subround = color)
    direction = Int(bounded_uint(
        Philox4x32x10V2(), evaluator.trajectory_seed,
        direction_address, UInt32(length(evaluator.offsets)))) + 1
    source = _checkerboard_neighbor_linear(
        evaluator.shape, evaluator.periodic, target,
        getfield(evaluator.offsets, direction))
    priority_address = _program_address(
        CheckerboardPriorityStream, Int(mcs), 4, semantic; subround = color)
    priority = _rng_word(
        Philox4x32x10V2(), evaluator.trajectory_seed, priority_address)
    return (
        target = LocalMath.UniqueValue(target),
        sites = LocalMath.UniqueValue((target, source)),
        semantic = LocalMath.UniqueValue(semantic),
        priority = LocalMath.UniqueValue(priority),
    )
end

function _proposal_offsets_tuple(
        offsets::AbstractMatrix{<:Integer}, dimensions::Integer)
    size(offsets, 1) == dimensions || throw(ArgumentError(
        "proposal offsets do not match the checkerboard dimensionality"))
    size(offsets, 2) > 0 || throw(ArgumentError(
        "proposal geometry requires at least one source offset"))
    size(offsets, 2) <= typemax(UInt32) || throw(ArgumentError(
        "proposal geometry offset count exceeds the semantic RNG bound"))
    return ntuple(size(offsets, 2)) do column
        ntuple(dimensions) do dimension
            value = offsets[dimension, column]
            typemin(Int8) <= value <= typemax(Int8) || throw(ArgumentError(
                "proposal geometry offset exceeds the Int8 execution ABI"))
            Int8(value)
        end
    end
end

_checkerboard_scratch_unique(::Type{T}) where {T} = LocalMath.Unique(
    T; coverage = LocalMath.PartialCoverage(),
    onempty = LocalMath.PreserveEmpty())

function _checkerboard_geometry_declaration(
        plan::CheckerboardPlan,
        proposal_offsets::AbstractMatrix{<:Integer},
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
    )
    maximum_batch = Int(plan.maximum_color_size)
    source_space = LocalMath.Space(_CheckerboardProposalDomain, maximum_batch)
    target_options = LocalMath.Field(
        source_space, NTuple{Int(plan.color_count),Int32})
    target = LocalMath.Field(source_space, Int32)
    sites = LocalMath.Field(source_space, NTuple{2,Int32})
    semantic = LocalMath.Field(source_space, Int32)
    priority = LocalMath.Field(source_space, UInt32)
    identity = LocalMath.IdentityRelation(source_space)
    mcs = LocalMath.Parameter(:mcs, Int64;
        bounds = (Int64(1), typemax(Int64)))
    color = LocalMath.Parameter(:color, Int32;
        bounds = (Int32(1), plan.color_count))
    attempt_round = LocalMath.Parameter(:attempt_round, Int32;
        bounds = (Int32(1), typemax(Int32)))
    batch_size = LocalMath.Parameter(:batch_size, Int32;
        bounds = (Int32(0), plan.maximum_color_size))
    evaluator = _CheckerboardGeometryEvaluator(
        plan.shape,
        plan.periodic,
        _proposal_offsets_tuple(proposal_offsets, length(plan.shape)),
        _trajectory_seed(seed, replica, repeat),
        Int32(prod(plan.shape; init = 1)),
    )
    publication(field, name, type) = LocalMath.Publication((
        LocalMath.FieldPublication(
            field, identity, LocalMath.PublicationValue(name)),),
        _checkerboard_scratch_unique(type))
    stage = LocalMath.Stage(
        source_space,
        (target_options = LocalMath.Access(
            target_options, identity; required = true),),
        (
            publication(target, :target, Int32),
            publication(sites, :sites, NTuple{2,Int32}),
            publication(semantic, :semantic, Int32),
            publication(priority, :priority, UInt32),
        ),
        LocalMath.Evaluator(
            evaluator, (mcs, color, attempt_round, batch_size)),
        LocalMath.Control(; prefix = batch_size),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_proposal_geometry),
    )
    law = LocalMath.LocalLaw(stage;
        parameters = LocalMath.ParameterSchema(
            mcs, color, attempt_round, batch_size))
    return (; law, target_options, target, sites, semantic, priority, evaluator,
        source_space, identity, mcs, color, attempt_round, batch_size)
end

struct _CheckerboardOwnerEvaluator end

@inline function (::_CheckerboardOwnerEvaluator)(
        item::Int32, reads, parameters,
    )
    owner_samples = getfield(reads, 1)
    old_owner = something(@inbounds owner_samples[1].value)
    source_sample = @inbounds owner_samples[2]
    new_owner = source_sample.present ? something(source_sample.value) : old_owner
    actionable = source_sample.present && old_owner != new_owner
    raw_priority = something(@inbounds getfield(reads, 2)[1].value)
    return (
        owners = LocalMath.UniqueValue((old_owner, new_owner)),
        priority = LocalMath.UniqueValue(
            actionable ? raw_priority : UInt32(0)),
        actionable = LocalMath.UniqueValue(actionable),
    )
end

function _checkerboard_proposal_topology_declaration(
        plan::CheckerboardPlan,
        proposal_offsets::AbstractMatrix{<:Integer},
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
    )
    geometry = _checkerboard_geometry_declaration(
        plan, proposal_offsets, seed, replica, repeat)
    lattice_space = LocalMath.Space(_CheckerboardLatticeDomain, plan.shape)
    ownership = LocalMath.Field(lattice_space, Int32)
    owner_relation = LocalMath.IndexRelation(
        geometry.sites => lattice_space; optional = true)
    owners = LocalMath.Field(geometry.source_space, NTuple{2,Int32})
    actionable = LocalMath.Field(geometry.source_space, Bool)
    publication(field, name, type) = LocalMath.Publication((
        LocalMath.FieldPublication(
            field, geometry.identity, LocalMath.PublicationValue(name)),),
        _checkerboard_scratch_unique(type))
    owner_stage = LocalMath.Stage(
        geometry.source_space,
        (
            ownership = LocalMath.Access(ownership, owner_relation),
            raw_priority = LocalMath.Access(
                geometry.priority, geometry.identity; required = true),
        ),
        (
            publication(owners, :owners, NTuple{2,Int32}),
            publication(geometry.priority, :priority, UInt32),
            publication(actionable, :actionable, Bool),
        ),
        LocalMath.Evaluator(_CheckerboardOwnerEvaluator()),
        LocalMath.Control(; prefix = geometry.batch_size),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_proposal_owners),
    )
    law = LocalMath.sequence(
        geometry.law, LocalMath.LocalLaw(owner_stage))
    return merge(geometry, (;
        law, lattice_space, ownership, owner_relation,
        owners, qualified_priority = geometry.priority, actionable))
end

struct _CheckerboardCellResourceEvaluator end
struct _CheckerboardTrackerResourceEvaluator{Names,Types} end

@generated function (::_CheckerboardTrackerResourceEvaluator{Names,Types})(
        item::Int32, reads, parameters) where {Names,Types}
    results = map(enumerate(Names)) do (index, name)
        T = Types.parameters[index]
        quote
            read = getfield(reads, $index)
            left = @inbounds read[1]
            right = @inbounds read[2]
            LocalMath.UniqueValue((
                left.present ? something(left.value) : zero($T),
                right.present ? something(right.value) : zero($T)))
        end
    end
    return :(NamedTuple{$(QuoteNode(Names))}(($(results...),)))
end

struct _CheckerboardContactGatherEvaluator{Degree} end
struct _CheckerboardReverseContactGatherEvaluator{Degree} end

Base.@noinline function _checkerboard_contact_sample(samples, lane::Int)
    return @inbounds samples[lane]
end

function _checkerboard_contact_result(::Val{Reverse}, ::Val{Degree}) where {Reverse,Degree}
    samples = [gensym(:sample) for _ in 1:Degree]
    loads = [:( $(samples[lane]) =
                    _checkerboard_contact_sample(source, $lane) )
             for lane in 1:Degree]
    owners = Expr(:tuple, (
        :($(samples[lane]).present ?
            something($(samples[lane]).value) : Int32(0))
        for lane in 1:Degree)...)
    sites = Expr(:tuple, (
        :($(samples[lane]).present ?
            $(samples[lane]).endpoint : Int32(0))
        for lane in 1:Degree)...)
    owner_name = Reverse ? :reverse_contact_owners : :contact_owners
    site_name = Reverse ? :reverse_contact_sites : :contact_sites
    result = Reverse ?
        :(($site_name = LocalMath.UniqueValue($sites),
           $owner_name = LocalMath.UniqueValue($owners))) :
        :(($owner_name = LocalMath.UniqueValue($owners),
           $site_name = LocalMath.UniqueValue($sites)))
    return quote
        source = getfield(reads, 1)
        $(loads...)
        $result
    end
end

@generated function (::_CheckerboardContactGatherEvaluator{Degree})(
        item::Int32, reads, parameters) where {Degree}
    return _checkerboard_contact_result(Val(false), Val(Degree))
end

@generated function (::_CheckerboardReverseContactGatherEvaluator{Degree})(
        item::Int32, reads, parameters) where {Degree}
    return _checkerboard_contact_result(Val(true), Val(Degree))
end


struct _CheckerboardContactKindEvaluator{Degree} end
struct _CheckerboardReverseContactKindEvaluator{Degree} end

function _checkerboard_contact_kind_result(
        ::Val{Reverse}, ::Val{Degree}) where {Reverse,Degree}
    samples = [gensym(:sample) for _ in 1:Degree]
    loads = [:( $(samples[lane]) = @inbounds(source[$lane]) )
             for lane in 1:Degree]
    kinds = Expr(:tuple, (
        :($(samples[lane]).present ?
            something($(samples[lane]).value) : Int16(0))
        for lane in 1:Degree)...)
    name = Reverse ? :reverse_contact_kinds : :contact_kinds
    return quote
        source = getfield(reads, 1)
        $(loads...)
        ($name = LocalMath.UniqueValue($kinds),)
    end
end

@generated function (::_CheckerboardContactKindEvaluator{Degree})(
        item::Int32, reads, parameters) where {Degree}
    return _checkerboard_contact_kind_result(Val(false), Val(Degree))
end

@generated function (::_CheckerboardReverseContactKindEvaluator{Degree})(
        item::Int32, reads, parameters) where {Degree}
    return _checkerboard_contact_kind_result(Val(true), Val(Degree))
end

@inline function (::_CheckerboardCellResourceEvaluator)(
        item::Int32, reads, parameters)
    kind_samples = getfield(reads, 1)
    volume_samples = getfield(reads, 2)
    old_sample = @inbounds kind_samples[1]
    new_sample = @inbounds kind_samples[2]
    old_kind = old_sample.present ? something(old_sample.value) : Int16(0)
    new_kind = new_sample.present ? something(new_sample.value) : Int16(0)
    old_volume_sample = @inbounds volume_samples[1]
    new_volume_sample = @inbounds volume_samples[2]
    old_volume = old_volume_sample.present ?
        something(old_volume_sample.value) : Int32(0)
    new_volume = new_volume_sample.present ?
        something(new_volume_sample.value) : Int32(0)
    return (
        kinds = LocalMath.UniqueValue((old_kind, new_kind)),
        volumes = LocalMath.UniqueValue((old_volume, new_volume)),
    )
end

struct _CheckerboardScientificEvaluator{
        T,N,Degree,HasParameters,Terms,Accepted,Relationships,
        SiteNames,RelationshipNames,Handles,Ranges,TrackerDescriptors,
        MomentDescriptor,RelationshipSchemas,
    }
    shape::NTuple{N,Int}
    trajectory_seed::UInt64
    terms::Terms
    accepted_site_terms::Accepted
    accepted_relationship_terms::Relationships
    state_handles::Handles
    contact_ranges::Ranges
    tracker_descriptors::TrackerDescriptors
    moment_descriptor::MomentDescriptor
    relationship_schemas::RelationshipSchemas
end

const _ACCEPTED_SITE_DISABLED = UInt8(0x00)
const _ACCEPTED_SITE_READY = UInt8(0x01)
const _ACCEPTED_SITE_INVALID_CONDITION = UInt8(0x02)
const _ACCEPTED_SITE_INVALID_VALUE = UInt8(0x03)

@inline _evaluate_accepted_site_terms(
    ::Tuple{}, context, ::Type{T}) where {T<:AbstractFloat} = ()
@inline function _evaluate_accepted_site_terms(
        terms::Tuple, context, ::Type{T}) where {T<:AbstractFloat}
    term = first(terms)
    condition = _execute_proposal_scalar(term.condition, context)
    code, value = if !(condition isa Bool)
        (_ACCEPTED_SITE_INVALID_CONDITION, zero(T))
    elseif !condition
        (_ACCEPTED_SITE_DISABLED, zero(T))
    else
        value = T(_execute_proposal_scalar(term.value, context))
        isfinite(value) ? (_ACCEPTED_SITE_READY, value) :
            (_ACCEPTED_SITE_INVALID_VALUE, zero(T))
    end
    return (code, value,
        _evaluate_accepted_site_terms(Base.tail(terms), context, T)...)
end

@inline _disabled_accepted_site_terms(
    ::Tuple{}, ::Type{T}) where {T<:AbstractFloat} = ()
@inline function _disabled_accepted_site_terms(
        terms::Tuple, ::Type{T}) where {T<:AbstractFloat}
    return (_ACCEPTED_SITE_DISABLED, zero(T),
        _disabled_accepted_site_terms(Base.tail(terms), T)...)
end

const _ACCEPTED_RELATIONSHIP_DISABLED = UInt8(0x00)
const _ACCEPTED_RELATIONSHIP_READY = UInt8(0x01)
const _ACCEPTED_RELATIONSHIP_INVALID_CONDITION = UInt8(0x02)
const _ACCEPTED_RELATIONSHIP_INVALID_VALUE = UInt8(0x03)

@inline _execute_accepted_relationship_payload(::Tuple{}, context) = ()
@inline function _execute_accepted_relationship_payload(
        payload::Tuple, context)
    return (_execute_proposal_scalar(first(payload), context),
        _execute_accepted_relationship_payload(Base.tail(payload), context)...)
end

@inline function _evaluate_accepted_relationship_term(term, context)
    condition = _execute_proposal_scalar(term.condition, context)
    condition isa Bool || return (
        _ACCEPTED_RELATIONSHIP_INVALID_CONDITION,
        Int32(0), Int32(0), term.payload_zero...)
    condition || return (
        _ACCEPTED_RELATIONSHIP_DISABLED,
        Int32(0), Int32(0), term.payload_zero...)
    valid_a, endpoint_a = _checkerboard_endpoint_value(
        _execute_proposal_scalar(term.endpoint_a, context))
    valid_b, endpoint_b = _checkerboard_endpoint_value(
        _execute_proposal_scalar(term.endpoint_b, context))
    payload = _execute_accepted_relationship_payload(term.payload, context)
    valid_payload, converted_payload = _checkerboard_payload_values(
        term.payload_zero, payload)
    code = valid_a & valid_b & valid_payload ?
        _ACCEPTED_RELATIONSHIP_READY :
        _ACCEPTED_RELATIONSHIP_INVALID_VALUE
    return (code, endpoint_a, endpoint_b, converted_payload...)
end

@inline _evaluate_accepted_relationship_terms(::Tuple{}, context) = ()
@inline function _evaluate_accepted_relationship_terms(terms::Tuple, context)
    return (_evaluate_accepted_relationship_term(first(terms), context)...,
        _evaluate_accepted_relationship_terms(Base.tail(terms), context)...)
end

@inline _disabled_accepted_relationship_terms(::Tuple{}) = ()
@inline function _disabled_accepted_relationship_terms(terms::Tuple)
    term = first(terms)
    return (_ACCEPTED_RELATIONSHIP_DISABLED,
        Int32(0), Int32(0), term.payload_zero...,
        _disabled_accepted_relationship_terms(Base.tail(terms))...)
end

@inline function _checkerboard_scientific_result(evaluation, ::Tuple{})
    return (
        delta_h = LocalMath.UniqueValue(evaluation.delta_h),
        drive_energy = LocalMath.UniqueValue(evaluation.drive_energy),
        drive_log_bias = LocalMath.UniqueValue(evaluation.drive_log_bias),
        kinetic_modifier = LocalMath.UniqueValue(evaluation.kinetic_modifier),
        constraints_allowed =
            LocalMath.UniqueValue(evaluation.constraints_allowed),
    )
end

@generated function _accepted_site_scientific_result(
        ::Val{Names}, ::Terms, evaluations::Tuple,
    ) where {Names,Terms<:Tuple}
    values = Expr[]
    for index in 1:fieldcount(Terms)
        push!(values, :(LocalMath.UniqueValue(
            getfield(evaluations, $(2index - 1)))))
        push!(values, :(LocalMath.UniqueValue(
            getfield(evaluations, $(2index)))))
    end
    return :(NamedTuple{$(QuoteNode(Names))}(($(values...),)))
end

@generated function _accepted_relationship_scientific_result(
        ::Val{Names}, ::Terms, evaluations::Tuple,
    ) where {Names,Terms<:Tuple}
    values = Expr[]
    offset = 1
    for term_type in Terms.parameters
        payload_type = term_type.parameters[5]
        push!(values, :(LocalMath.UniqueValue(
            getfield(evaluations, $offset))))
        push!(values, :(LocalMath.UniqueValue((
            getfield(evaluations, $(offset + 1)),
            getfield(evaluations, $(offset + 2)),
        ))))
        for payload in 1:fieldcount(payload_type)
            push!(values, :(LocalMath.UniqueValue(
                getfield(evaluations, $(offset + 2 + payload)))))
        end
        offset += 3 + fieldcount(payload_type)
    end
    return :(NamedTuple{$(QuoteNode(Names))}(($(values...),)))
end

@inline function _checkerboard_scientific_result(
        evaluation, accepted_site_terms::Tuple,
        accepted_site_evaluations::Tuple, site_names,
        accepted_relationship_terms::Tuple,
        accepted_relationship_evaluations::Tuple,
        relationship_names,
    )
    base = _checkerboard_scientific_result(evaluation, ())
    sites = _accepted_site_scientific_result(
        site_names, accepted_site_terms, accepted_site_evaluations)
    relationships = _accepted_relationship_scientific_result(
        relationship_names, accepted_relationship_terms,
        accepted_relationship_evaluations)
    return merge(base, sites, relationships)
end

struct _CheckerboardParameterView{
        N,T,A<:AbstractVector{T},
    } <: AbstractVector{NTuple{N,T}}
    values::A
    extent::Int
end

struct _GatheredRelationshipSchema{P,D,N}
    handle::Int32
    edge_offset::Int32
end

struct _GatheredRelationshipReads{A,EA,EB,P,V,MF,MS}
    handle::Int32
    edge_offset::Int32
    active::A
    endpoint_a::EA
    endpoint_b::EB
    payload::P
    endpoint_volumes::V
    moment_first::MF
    moment_second::MS
end

@generated function _gathered_relationship_reads(arguments...)
    length(arguments) == 9 || error(
        "gathered relationship construction schema changed")
    relationship_type = _GatheredRelationshipReads{arguments[3:9]...}
    values = (:(getfield(arguments, $index)) for index in 1:9)
    return :($relationship_type($(values...)))
end

struct _CheckerboardRelationshipEndpointKeyEvaluator{D} end

struct _CheckerboardRelationshipEdgeKeyEvaluator{D}
    edge_offset::Int32
end

@inline function _checkerboard_relationship_edge_key(
        sample, offset::Int32)
    sample.present || return Int32(0)
    sample.value === nothing && return Int32(0)
    value = Int32(something(sample.value))
    return value > 0 ? offset + value - Int32(1) : Int32(0)
end

@generated function (
        evaluator::_CheckerboardRelationshipEdgeKeyEvaluator{D})(
        item::Int32, reads, parameters) where {D}
    keys = Expr(:tuple, (
        :(_checkerboard_relationship_edge_key(
            @inbounds(getfield(reads, 1)[$lane]),
            evaluator.edge_offset)) for lane in 1:D)...)
    return :((edge_keys = LocalMath.UniqueValue($keys),))
end

@inline _checkerboard_relationship_endpoint_key(sample) =
    sample.present ? Int32(something(sample.value)) : Int32(0)

@generated function (
        ::_CheckerboardRelationshipEndpointKeyEvaluator{D})(
        item::Int32, reads, parameters) where {D}
    keys = Expr(:tuple)
    for lane in 1:D
        push!(keys.args, :(_checkerboard_relationship_endpoint_key(
            @inbounds getfield(reads, 1)[$lane])))
        push!(keys.args, :(_checkerboard_relationship_endpoint_key(
            @inbounds getfield(reads, 2)[$lane])))
    end
    return :((endpoint_keys = LocalMath.UniqueValue($keys),))
end

function _checkerboard_relationship_science_declarations(
        handles::Tuple,
        source_space::LocalMath.Space,
        batch_size::LocalMath.Parameter,
        cell_space::LocalMath.Space,
        cell_volumes::LocalMath.Field,
        owner_relation::LocalMath.Relation,
        moment_source_fields::Tuple,
        moment_descriptor,
        bank_field_authorities::Tuple,
        domain_resources::HamiltonianDomainResources,
        relationship_schemas::RelationshipStorage,
        relationship_state::RelationshipStorage)
    return Tuple(map(handles) do handle
        storage_slot = _relationship_domain_slot(domain_resources, handle)
        1 <= storage_slot <= length(relationship_state) || throw(ArgumentError(
            "checkerboard relationship-energy handle is outside packed storage"))
        schema_location = _relationship_location(
            relationship_schemas, Int(storage_slot))
        # The host schema is the location authority. Adapted runtime slot
        # tables may live on the device and are never scalar-indexed cold.
        state_location = schema_location
        bank = relationship_state.banks[Int(state_location.bank)]
        bank isa PackedRelationshipBank || throw(ArgumentError(
            "checkerboard relationship energy requires packed storage"))
        schema_bank = relationship_schemas.banks[Int(schema_location.bank)]
        schema = schema_bank[Int(schema_location.slot)]
        edge_offsets, _ = _relationship_offsets(
            map(entry -> entry.capacity, schema_bank))
        incident_offsets, _ = _relationship_offsets(map(
            entry -> length(cell_space) * Int(entry.maximum_degree),
            schema_bank))
        edge_offset = edge_offsets[Int(schema_location.slot)]
        incident_offset = incident_offsets[Int(schema_location.slot)]
        maximum_degree = Int(schema.maximum_degree)
        selected_degree = 2maximum_degree
        bank_fields = bank_field_authorities[Int(state_location.bank)]
        incident_slot_relation = LocalMath.FixedRelation(
            cell_space => bank_fields.incident_edges.space;
            degree = maximum_degree)
        incidence = LocalMath.SelectedRelation(
            incident_slot_relation, owner_relation)
        edge_keys = LocalMath.Field(
            source_space, NTuple{selected_degree,Int32})
        edge_relation = LocalMath.IndexRelation(
            edge_keys => bank_fields.active.space; optional = true)
        endpoint_keys = LocalMath.Field(
            source_space, NTuple{2selected_degree,Int32})
        endpoint_relation = LocalMath.IndexRelation(
            endpoint_keys => cell_space; optional = true)
        payload = ntuple(length(schema.payload_defaults)) do index
            getfield(bank_fields, 5 + index)
        end
        fields = (
            active = bank_fields.active,
            endpoint_a = bank_fields.endpoint_a,
            endpoint_b = bank_fields.endpoint_b,
            payload,
        )
        edge_stage = LocalMath.Stage(
            source_space,
            (incident_edges = LocalMath.Access(
                bank_fields.incident_edges, incidence),),
            (LocalMath.Publication((LocalMath.FieldPublication(
                edge_keys, LocalMath.IdentityRelation(source_space),
                LocalMath.PublicationValue(:edge_keys)),),
        _checkerboard_scratch_unique(NTuple{selected_degree,Int32})),),
            LocalMath.Evaluator(
                _CheckerboardRelationshipEdgeKeyEvaluator{selected_degree}(
                    edge_offset)),
            LocalMath.Control(; prefix = batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_relationship_edge_keys),
        )
        endpoint_stage = LocalMath.Stage(
            source_space,
            (endpoint_a = LocalMath.Access(fields.endpoint_a, edge_relation),
             endpoint_b = LocalMath.Access(fields.endpoint_b, edge_relation)),
            (LocalMath.Publication((LocalMath.FieldPublication(
                endpoint_keys, LocalMath.IdentityRelation(source_space),
                LocalMath.PublicationValue(:endpoint_keys)),),
        _checkerboard_scratch_unique(NTuple{2selected_degree,Int32})),),
            LocalMath.Evaluator(
                _CheckerboardRelationshipEndpointKeyEvaluator{
                    selected_degree}()),
            LocalMath.Control(; prefix = batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_relationship_endpoint_keys),
        )
        dimensions = moment_descriptor === nothing ? 0 :
            typeof(moment_descriptor).parameters[1]
        (; handle, storage_slot, state_location, maximum_degree,
            incident_offset,
            incident_slot_relation, incidence, edge_keys, edge_relation,
            edge_stage, fields, endpoint_keys, endpoint_relation,
            endpoint_stage, incident_edges_field = bank_fields.incident_edges,
            cell_volumes,
            moment_source_fields,
            schema = _GatheredRelationshipSchema{
                length(fields.payload),selected_degree,dimensions}(
                    handle, edge_offset))
    end)
end

function _checkerboard_relationship_science_reads(declarations::Tuple)
    names = Symbol[]
    reads = Any[]
    for (ordinal, declaration) in enumerate(declarations)
        prefix = Symbol(:proposal_relationship_, ordinal)
        push!(names, Symbol(prefix, :_active))
        push!(reads, LocalMath.Access(
            declaration.fields.active, declaration.edge_relation))
        push!(names, Symbol(prefix, :_endpoint_a))
        push!(reads, LocalMath.Access(
            declaration.fields.endpoint_a, declaration.edge_relation))
        push!(names, Symbol(prefix, :_endpoint_b))
        push!(reads, LocalMath.Access(
            declaration.fields.endpoint_b, declaration.edge_relation))
        for (payload_index, field) in enumerate(declaration.fields.payload)
            push!(names, Symbol(prefix, :_payload_, payload_index))
            push!(reads, LocalMath.Access(field, declaration.edge_relation))
        end
        push!(names, Symbol(prefix, :_endpoint_volumes))
        push!(reads, LocalMath.Access(
            declaration.cell_volumes, declaration.endpoint_relation))
        for (moment_index, field) in enumerate(
                declaration.moment_source_fields)
            push!(names, Symbol(prefix, :_endpoint_moment_, moment_index))
            push!(reads, LocalMath.Access(field, declaration.endpoint_relation))
        end
    end
    return NamedTuple{Tuple(names)}(Tuple(reads))
end

@generated function _checkerboard_relationship_read_count(
        ::Schemas) where {Schemas<:Tuple}
    count = sum(begin
            payload_count, _, dimensions = schema_type.parameters
            4 + payload_count + dimensions + dimensions * dimensions
        end for schema_type in Schemas.parameters; init = 0)
    return :($count)
end

@inline _checkerboard_materialize_read(read, ::Val{0}, lane::Int) = ()
@inline function _checkerboard_materialize_read(
        read, ::Val{N}, lane::Int = 1) where {N}
    return (
        @inbounds(read[lane]),
        _checkerboard_materialize_read(read, Val(N - 1), lane + 1)...,
    )
end

@inline _checkerboard_relationship_payload(
    reads, ::Val{0}, degree::Val, ::Val{Offset},
) where {Offset} = ()
@inline function _checkerboard_relationship_payload(
        reads, ::Val{P}, degree::Val, ::Val{Offset},
    ) where {P,Offset}
    return (
        _checkerboard_materialize_read(
            getfield(reads, Offset + 4), degree),
        _checkerboard_relationship_payload(
            reads, Val(P - 1), degree, Val(Offset + 1))...,
    )
end

@generated function _checkerboard_materialize_components(
        reads, ::Val{Count}, degree::Val, ::Val{Index},
    ) where {Count,Index}
    values = Expr(:tuple, (
        :(_checkerboard_materialize_read(
            getfield(reads, $(Index + component - 1)), degree))
        for component in 1:Count)...)
    return Expr(:block, Expr(:meta, :inline), values)
end

@inline _checkerboard_scientific_relationships(
    reads, ::Tuple{}, moment_descriptor, offset,
) = ()
@inline function _checkerboard_scientific_relationships(
        reads,
        schemas::Tuple{_GatheredRelationshipSchema{P,D,N},Vararg},
        moment_descriptor,
        ::Val{Offset},
    ) where {P,D,N,Offset}
    schema = first(schemas)
    degree = Val(D)
    endpoint_degree = Val(2D)
    moments = _checkerboard_materialize_components(
        reads, Val(N + N * N), endpoint_degree, Val(Offset + 5 + P))
    moment_first, moment_second = _checkerboard_split_moment_values(
        moments, moment_descriptor)
    resource = _gathered_relationship_reads(
        schema.handle,
        schema.edge_offset,
        _checkerboard_materialize_read(
            getfield(reads, Offset + 1), degree),
        _checkerboard_materialize_read(
            getfield(reads, Offset + 2), degree),
        _checkerboard_materialize_read(
            getfield(reads, Offset + 3), degree),
        _checkerboard_relationship_payload(
            reads, Val(P), degree, Val(Offset)),
        _checkerboard_materialize_read(
            getfield(reads, Offset + 4 + P), endpoint_degree),
        moment_first,
        moment_second,
    )
    return (
        resource,
        _checkerboard_scientific_relationships(
            reads, Base.tail(schemas), moment_descriptor,
            Val(Offset + 4 + P + N + N * N))...,
    )
end

function _checkerboard_parameter_view(
        values::AbstractVector{T}, ::Val{N}, extent::Integer,
    ) where {T,N}
    length(values) >= N || throw(ArgumentError(
        "checkerboard parameter storage is shorter than its compiled schema"))
    extent >= 0 || throw(ArgumentError(
        "checkerboard parameter view extent cannot be negative"))
    return _CheckerboardParameterView{N,T,typeof(values)}(
        values, Int(extent))
end

Base.IndexStyle(::Type{<:_CheckerboardParameterView}) = IndexLinear()
Base.size(view::_CheckerboardParameterView) = (view.extent,)
Base.length(view::_CheckerboardParameterView) = view.extent
Base.strides(::_CheckerboardParameterView) = (1,)
@inline function Base.getindex(
        view::_CheckerboardParameterView{N}, index::Int,
    ) where {N}
    @boundscheck checkbounds(view, index)
    return ntuple(N) do slot
        @inbounds view.values[slot]
    end
end
KernelAbstractions.get_backend(view::_CheckerboardParameterView) =
    KernelAbstractions.get_backend(view.values)
Adapt.adapt_structure(to, view::_CheckerboardParameterView{N}) where {N} =
    _checkerboard_parameter_view(
        Adapt.adapt(to, view.values), Val(N), view.extent)

@inline _checkerboard_cartesian_site(
    shape::NTuple{1,<:Integer}, linear::Int32,
) = CartesianIndex(linear)
@inline function _checkerboard_cartesian_site(
        shape::NTuple{2,<:Integer}, linear::Int32)
    offset = linear - Int32(1)
    first = rem(offset, Int32(shape[1])) + Int32(1)
    second = div(offset, Int32(shape[1])) + Int32(1)
    return CartesianIndex(first, second)
end
@inline function _checkerboard_cartesian_site(
        shape::NTuple{3,<:Integer}, linear::Int32)
    offset = linear - Int32(1)
    first_extent = Int32(shape[1])
    second_extent = Int32(shape[2])
    first = rem(offset, first_extent) + Int32(1)
    plane_offset = div(offset, first_extent)
    second = rem(plane_offset, second_extent) + Int32(1)
    third = div(plane_offset, second_extent) + Int32(1)
    return CartesianIndex(first, second, third)
end
@generated function _checkerboard_scientific_gathers(
        reads::R, ::Val{Count}, ::Val{Offset}, ::Val{Degree},
    ) where {R,Count,Offset,Degree}
    records = Expr[]
    for index in 1:Count
        read = gensym(:site_read)
        target = gensym(:target_value)
        source = gensym(:source_value)
        contact_read = gensym(:contact_read)
        reverse_read = gensym(:reverse_read)
        affected_read = gensym(:affected_read)
        push!(records, quote
            $read = getfield(reads, $(index + Offset))
            $target = something(@inbounds($read[1].value))
            $source = something(@inbounds($read[2].value), $target)
            $contact_read = $(iszero(Degree) ? :(nothing) :
                :(getfield(reads, $(Offset + Count + index))))
            $reverse_read = $(iszero(Degree) ? :(nothing) :
                :(getfield(reads, $(Offset + 2 * Count + index))))
            $affected_read = $(iszero(Degree) ? :(nothing) :
                :(getfield(reads, $(Offset + 3 * Count + index))))
            (sites = ($target, $source),
                contacts = $(iszero(Degree) ? :(()) : contact_read),
                reverse_contacts = $(iszero(Degree) ? :(()) : reverse_read),
                affected_contacts = $(iszero(Degree) ? :(()) : affected_read))
        end)
    end
    return Expr(:tuple, records...)
end

@generated function _checkerboard_scientific_tracker_values(
        reads, ::Val{Count}, ::Val{Offset}) where {Count,Offset}
    return Expr(:tuple, (
        :(something(@inbounds getfield(reads, $(Offset + index))[1].value))
        for index in 1:Count)...)
end

@generated function _checkerboard_scientific_moment_values(
        reads, ::Val{Count}, ::Val{Offset}, ::Type{T}) where {Count,Offset,T}
    return Expr(:tuple, (
        quote
            local read = getfield(reads, $(Offset + index))
            local left = @inbounds read[1]
            local right = @inbounds read[2]
            (
                left.present ? something(left.value) : zero($T),
                right.present ? something(right.value) : zero($T),
            )
        end for index in 1:Count)...)
end

@generated function _checkerboard_split_moment_values(
        values::Tuple, ::CellMomentsTracker{N}) where {N}
    first = Expr(:tuple, (:(getfield(values, $index)) for index in 1:N)...)
    second = Expr(:tuple, (
        :(getfield(values, $(N + index))) for index in 1:(N * N))...)
    return :(($first, $second))
end

@inline _checkerboard_split_moment_values(values::Tuple, ::Nothing) = ((), ())

@inline _checkerboard_scientific_moments(
    reads, ::Nothing, ::Val,
) = ((), ())
@generated function _checkerboard_scientific_moments(
        reads, descriptor::CellMomentsTracker{N,T},
        ::Val{Offset}) where {N,T,Offset}
    count = N + N * N
    values = :(_checkerboard_scientific_moment_values(
        reads, Val($count), Val($Offset), $T))
    return :(_checkerboard_split_moment_values($values, descriptor))
end

_checkerboard_moment_component_count(::Nothing) = 0
_checkerboard_moment_component_count(::CellMomentsTracker{N}) where {N} =
    N + N * N


@inline _checkerboard_scientific_parameters(reads, ::Val{false}) = ()
@inline _checkerboard_scientific_parameters(reads, ::Val{true}) =
    something(@inbounds getfield(reads, 7)[1].value)

@generated function _checkerboard_scientific_contact(
        reads, ::Val{Degree}, ::Val{HasParameters},
    ) where {Degree,HasParameters}
    iszero(Degree) && return :(((), (), (), (), (), ()))
    offset = HasParameters ? 1 : 0
    return quote
        (
            something(@inbounds getfield(reads, $(7 + offset))[1].value),
            something(@inbounds getfield(reads, $(8 + offset))[1].value),
            something(@inbounds getfield(reads, $(9 + offset))[1].value),
            something(@inbounds getfield(reads, $(10 + offset))[1].value),
            something(@inbounds getfield(reads, $(11 + offset))[1].value),
            something(@inbounds getfield(reads, $(12 + offset))[1].value),
        )
    end
end

Base.@noinline function (evaluator::_CheckerboardScientificEvaluator{
        T,N,Degree,HasParameters,Terms,Accepted,Relationships,
        SiteNames,RelationshipNames,Handles,Ranges,TrackerDescriptors,
        MomentDescriptor,RelationshipSchemas})(
        item::Int32, reads, parameters,
    ) where {
        T,N,Degree,HasParameters,Terms,Accepted,Relationships,
        SiteNames,RelationshipNames,Handles,Ranges,TrackerDescriptors,
        MomentDescriptor,RelationshipSchemas,
    }
    sites = something(@inbounds getfield(reads, 1)[1].value)
    owners = something(@inbounds getfield(reads, 2)[1].value)
    kinds = something(@inbounds getfield(reads, 3)[1].value)
    volumes = something(@inbounds getfield(reads, 4)[1].value)
    actionable = something(@inbounds getfield(reads, 5)[1].value)
    semantic = something(@inbounds getfield(reads, 6)[1].value)
    science_parameters = _checkerboard_scientific_parameters(
        reads, Val(HasParameters))
    contact_sites, contact_owners, contact_kinds,
    reverse_contact_sites, reverse_contact_owners, reverse_contact_kinds =
        _checkerboard_scientific_contact(
            reads, Val(Degree), Val(HasParameters))
    tracker_values = _checkerboard_scientific_tracker_values(
        reads, Val(length(evaluator.tracker_descriptors)),
        Val(6 + (HasParameters ? 1 : 0) + (iszero(Degree) ? 0 : 6)))
    tracker_offset = 6 + (HasParameters ? 1 : 0) +
        (iszero(Degree) ? 0 : 6)
    moment_first, moment_second = _checkerboard_scientific_moments(
        reads, evaluator.moment_descriptor,
        Val(tracker_offset + length(evaluator.tracker_descriptors)))
    relationship_offset = tracker_offset +
        length(evaluator.tracker_descriptors) +
        _checkerboard_moment_component_count(evaluator.moment_descriptor)
    relationship_resources = _checkerboard_scientific_relationships(
        reads, evaluator.relationship_schemas, evaluator.moment_descriptor,
        Val(relationship_offset))
    state_values = _checkerboard_scientific_gathers(
        reads, Val(length(evaluator.state_handles)),
        Val(6 + (HasParameters ? 1 : 0) + (iszero(Degree) ? 0 : 6) +
            length(evaluator.tracker_descriptors) +
            _checkerboard_moment_component_count(
                evaluator.moment_descriptor) +
            _checkerboard_relationship_read_count(
                evaluator.relationship_schemas)),
        Val(Degree))
    target_linear, source_linear = sites
    target = _checkerboard_cartesian_site(evaluator.shape, target_linear)
    source = source_linear > 0 ?
        _checkerboard_cartesian_site(evaluator.shape, source_linear) : target
    context = _gathered_proposal_context(
        source,
        target,
        target_linear,
        owners[1],
        owners[2],
        kinds[1],
        kinds[2],
        volumes,
        semantic,
        getfield(parameters, 1),
        getfield(parameters, 2),
        evaluator.trajectory_seed,
        zero(T),
        science_parameters,
        state_values,
        contact_sites,
        contact_owners,
        contact_kinds,
        reverse_contact_sites,
        reverse_contact_owners,
        reverse_contact_kinds,
        evaluator.contact_ranges,
        tracker_values, evaluator.tracker_descriptors,
        moment_first, moment_second, evaluator.moment_descriptor,
        relationship_resources,
    )
    evaluation = actionable ?
        _fold_executable_proposal_terms(evaluator.terms, context, T) :
        _neutral_proposal_evaluation(T)
    accepted_site_evaluations = actionable ?
        _evaluate_accepted_site_terms(
            evaluator.accepted_site_terms, context, T) :
        _disabled_accepted_site_terms(evaluator.accepted_site_terms, T)
    accepted_relationship_evaluations = actionable ?
        _evaluate_accepted_relationship_terms(
            evaluator.accepted_relationship_terms, context) :
        _disabled_accepted_relationship_terms(
            evaluator.accepted_relationship_terms)
    return _checkerboard_scientific_result(
        evaluation, evaluator.accepted_site_terms,
        accepted_site_evaluations, Val(SiteNames),
        evaluator.accepted_relationship_terms,
        accepted_relationship_evaluations,
        Val(RelationshipNames))
end

function _checkerboard_scientific_declaration(
        checkerboard::CheckerboardPlan,
        proposal_offsets::AbstractMatrix{<:Integer},
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
        descriptor_plan::DescriptorExecutionPlan,
        stage_plan::StageExecutionPlan,
        tracker_plan,
        ownership_change_handles::Tuple,
        relationship_schemas::RelationshipStorage,
        relationship_state::RelationshipStorage,
        minimum_parameter_count::Integer,
        cell_capacity::Integer,
        ::Type{T},
    ) where {T<:AbstractFloat}
    cell_capacity >= 0 || throw(ArgumentError(
        "checkerboard cell capacity cannot be negative"))
    topology = _checkerboard_proposal_topology_declaration(
        checkerboard, proposal_offsets, seed, replica, repeat)
    inventory = _proposal_gather_inventory(descriptor_plan)
    requirements = _checkerboard_scientific_requirements(
        inventory, stage_plan, ownership_change_handles, tracker_plan)
    state_handles = requirements.state_handles
    terms = _compile_proposal_terms(descriptor_plan, state_handles)
    accepted_site_terms = _compile_accepted_site_terms(
        stage_plan, descriptor_plan, state_handles)
    accepted_relationship_terms = _compile_accepted_relationship_terms(
        stage_plan, descriptor_plan, state_handles,
        relationship_schemas, relationship_state)
    cell_space = LocalMath.Space(_CheckerboardCellDomain, Int(cell_capacity))
    cell_kinds = LocalMath.Field(cell_space, Int16)
    cell_generations = LocalMath.Field(cell_space, UInt32)
    cell_volumes = LocalMath.Field(cell_space, Int32)
    kind_relation = LocalMath.IndexRelation(
        topology.owners => cell_space; optional = true)
    kinds = LocalMath.Field(topology.source_space, NTuple{2,Int16})
    volumes = LocalMath.Field(topology.source_space, NTuple{2,Int32})
    tracker_keys = requirements.tracker_keys
    tracker_descriptors = requirements.tracker_descriptors
    moment_descriptor = requirements.moment_descriptor
    tracker_source_fields = map(tracker_descriptors) do descriptor
        LocalMath.Field(cell_space,
            _tracker_storage_eltype(tracker_storage(descriptor)))
    end
    tracker_pair_fields = map(tracker_source_fields) do field
        LocalMath.Field(topology.source_space, NTuple{2,eltype(field)})
    end
    tracker_names = ntuple(
        index -> Symbol(:proposal_tracker_, index), length(tracker_pair_fields))
    moment_source_fields = if moment_descriptor === nothing
        ()
    else
        dimensions = typeof(moment_descriptor).parameters[1]
        moment_type = typeof(moment_descriptor).parameters[2]
        ntuple(dimensions + dimensions * dimensions) do _
            LocalMath.Field(cell_space, moment_type)
        end
    end
    moment_names = ntuple(index -> Symbol(:proposal_moment_, index),
        length(moment_source_fields))
    relationship_bank_fields = Tuple(map(
        _checkerboard_relationship_state_fields,
        relationship_state.banks))
    relationship_science = _checkerboard_relationship_science_declarations(
        requirements.relationship_handles, topology.source_space,
        topology.batch_size, cell_space, cell_volumes, kind_relation,
        moment_source_fields, moment_descriptor,
        relationship_bank_fields,
        descriptor_plan.domain_resources,
        relationship_schemas, relationship_state)
    relationship_schemas_compiled = map(
        declaration -> declaration.schema, relationship_science)
    evaluation = (
        delta_h = LocalMath.Field(topology.source_space, T),
        drive_energy = LocalMath.Field(topology.source_space, T),
        drive_log_bias = LocalMath.Field(topology.source_space, T),
        kinetic_modifier = LocalMath.Field(topology.source_space, T),
        constraints_allowed = LocalMath.Field(topology.source_space, Bool),
    )
    all(handle -> Tuple(Int.(handle_shape(handle))) == checkerboard.shape,
        state_handles) || throw(ArgumentError(
            "checkerboard proposal state fields must match the lattice shape"))
    state_fields = map(state_handles) do handle
        LocalMath.Field(topology.lattice_space,
            _state_handle_element_type(handle))
    end
    accepted_state_handles = requirements.accepted_state_handles
    accepted_state_fields = map(accepted_state_handles) do handle
        slot = findfirst(==(handle), state_handles)
        slot === nothing && error("accepted state handle was not gathered")
        getfield(state_fields, slot)
    end
    proposal_site_relation = LocalMath.IndexRelation(
        topology.sites => topology.lattice_space; optional = true)
    parameter_count = max(
        requirements.parameter_count, Int(minimum_parameter_count))
    science_parameters = iszero(parameter_count) ? nothing :
        LocalMath.Field(topology.source_space, NTuple{parameter_count,T})
    publication(field, name, type) = LocalMath.Publication((
        LocalMath.FieldPublication(
            field, topology.identity, LocalMath.PublicationValue(name)),),
        _checkerboard_scratch_unique(type))
    contact_offset_table = descriptor_plan.domain_resources.contact_offsets
    contact_offsets = if iszero(size(contact_offset_table, 2))
        ()
    else
        size(contact_offset_table, 1) == length(checkerboard.shape) || throw(
            ArgumentError(
                "Hamiltonian contact offsets do not match the checkerboard dimensionality"))
        _proposal_offsets_tuple(
            contact_offset_table, length(checkerboard.shape))
    end
    contact_degree = length(contact_offsets)
    contact_ranges = (
        Tuple(descriptor_plan.domain_resources.contact_starts),
        Tuple(descriptor_plan.domain_resources.contact_counts),
    )
    contact = if iszero(contact_degree)
        nothing
    else
        target_selection = LocalMath.IndexRelation(
            topology.target => topology.lattice_space; optional = false)
        affine = LocalMath.AffineRelation(
            topology.lattice_space => topology.lattice_space;
            offsets = contact_offsets)
        boundary = LocalMath.BoundaryRelation(
            affine, LocalMath.PeriodicBoundary(Tuple(checkerboard.periodic)))
        relation = LocalMath.compose(target_selection, boundary)
        reverse_affine = LocalMath.AffineRelation(
            topology.lattice_space => topology.lattice_space;
            offsets = map(offset -> map(-, offset), contact_offsets))
        reverse_boundary = LocalMath.BoundaryRelation(
            reverse_affine,
            LocalMath.PeriodicBoundary(Tuple(checkerboard.periodic)))
        reverse_relation = LocalMath.compose(target_selection, reverse_boundary)
        affected_relation = LocalMath.compose(
            target_selection, reverse_boundary, boundary)
        contact_owners = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int32})
        reverse_contact_owners = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int32})
        contact_sites = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int32})
        contact_kinds = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int16})
        reverse_contact_kinds = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int16})
        reverse_contact_sites = LocalMath.Field(
            topology.source_space, NTuple{contact_degree,Int32})
        kind_selection = LocalMath.IndexRelation(
            contact_owners => cell_space; optional = true)
        reverse_kind_selection = LocalMath.IndexRelation(
            reverse_contact_owners => cell_space; optional = true)
        owner_stage = LocalMath.Stage(
            topology.source_space,
            (ownership = LocalMath.Access(topology.ownership, relation),),
            (
                publication(contact_owners, :contact_owners,
                    NTuple{contact_degree,Int32}),
                publication(contact_sites, :contact_sites,
                    NTuple{contact_degree,Int32}),
            ),
            LocalMath.Evaluator(
                _CheckerboardContactGatherEvaluator{contact_degree}()),
            LocalMath.Control(; prefix = topology.batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_contact_ownership),
        )
        reverse_owner_stage = LocalMath.Stage(
            topology.source_space,
            (ownership = LocalMath.Access(
                topology.ownership, reverse_relation),),
            (
                publication(reverse_contact_sites, :reverse_contact_sites,
                    NTuple{contact_degree,Int32}),
                publication(reverse_contact_owners, :reverse_contact_owners,
                    NTuple{contact_degree,Int32}),
            ),
            LocalMath.Evaluator(
                _CheckerboardReverseContactGatherEvaluator{contact_degree}()),
            LocalMath.Control(; prefix = topology.batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_reverse_contact_ownership),
        )
        kind_stage = LocalMath.Stage(
            topology.source_space,
            (cell_kinds = LocalMath.Access(cell_kinds, kind_selection),),
            (publication(contact_kinds, :contact_kinds,
                NTuple{contact_degree,Int16}),),
            LocalMath.Evaluator(
                _CheckerboardContactKindEvaluator{contact_degree}()),
            LocalMath.Control(; prefix = topology.batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_contact_kinds),
        )
        reverse_kind_stage = LocalMath.Stage(
            topology.source_space,
            (cell_kinds = LocalMath.Access(
                cell_kinds, reverse_kind_selection),),
            (publication(reverse_contact_kinds, :reverse_contact_kinds,
                NTuple{contact_degree,Int16}),),
            LocalMath.Evaluator(
                _CheckerboardReverseContactKindEvaluator{contact_degree}()),
            LocalMath.Control(; prefix = topology.batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_reverse_contact_kinds),
        )
        (; relation, reverse_relation, affected_relation,
            owners = contact_owners, sites = contact_sites,
            kinds = contact_kinds, reverse_sites = reverse_contact_sites,
            reverse_owners = reverse_contact_owners,
            reverse_kinds = reverse_contact_kinds,
            kind_selection, reverse_kind_selection,
            law = LocalMath.sequence(
                LocalMath.LocalLaw(owner_stage),
                LocalMath.LocalLaw(reverse_owner_stage),
                LocalMath.LocalLaw(kind_stage),
                LocalMath.LocalLaw(reverse_kind_stage)))
    end
    state_accesses = map(state_fields) do field
        LocalMath.Access(field, proposal_site_relation)
    end
    contact_state_accesses = contact === nothing ? () : map(state_fields) do field
        LocalMath.Access(field, contact.relation)
    end
    reverse_contact_state_accesses = contact === nothing ? () : map(state_fields) do field
        LocalMath.Access(field, contact.reverse_relation)
    end
    affected_contact_state_accesses = contact === nothing ? () : map(state_fields) do field
        LocalMath.Access(field, contact.affected_relation)
    end
    state_names = ntuple(
        index -> Symbol(:proposal_state_, index), length(state_fields))
    contact_state_names = contact === nothing ? () : ntuple(
        index -> Symbol(:contact_state_, index), length(state_fields))
    reverse_contact_state_names = contact === nothing ? () : ntuple(
        index -> Symbol(:reverse_contact_state_, index), length(state_fields))
    affected_contact_state_names = contact === nothing ? () : ntuple(
        index -> Symbol(:affected_contact_state_, index), length(state_fields))
    cell_resource_stage = LocalMath.Stage(
        topology.source_space,
        (
            cell_kinds = LocalMath.Access(cell_kinds, kind_relation),
            cell_volumes = LocalMath.Access(cell_volumes, kind_relation),
        ),
        (
            publication(kinds, :kinds, NTuple{2,Int16}),
            publication(volumes, :volumes, NTuple{2,Int32}),
        ),
        LocalMath.Evaluator(_CheckerboardCellResourceEvaluator()),
        LocalMath.Control(; prefix = topology.batch_size),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_owner_kinds),
    )
    tracker_stage = if isempty(tracker_pair_fields)
        nothing
    else
        tracker_accesses = NamedTuple{tracker_names}(map(
            field -> LocalMath.Access(field, kind_relation),
            tracker_source_fields))
        tracker_publications = map(
            tracker_pair_fields, tracker_names) do field, name
            publication(field, name, eltype(field))
        end
        LocalMath.Stage(
            topology.source_space, tracker_accesses, tracker_publications,
            LocalMath.Evaluator(
                _CheckerboardTrackerResourceEvaluator{
                    tracker_names,Tuple{map(eltype, tracker_source_fields)...}}()),
            LocalMath.Control(; prefix = topology.batch_size),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_tracker_resources))
    end
    accepted_relationship_fields = _accepted_relationship_fields(
        topology.source_space, accepted_relationship_terms)
    accepted_site_fields = _accepted_site_fields(
        topology.source_space, accepted_site_terms, T)
    site_port_names = keys(accepted_site_fields)
    relationship_port_names = keys(accepted_relationship_fields)
    scientific_evaluator = _CheckerboardScientificEvaluator{
        T, length(checkerboard.shape), contact_degree,
        !iszero(parameter_count),
        typeof(terms), typeof(accepted_site_terms),
        typeof(accepted_relationship_terms),
        site_port_names,
        relationship_port_names,
        typeof(state_handles), typeof(contact_ranges),
        typeof(tracker_descriptors),typeof(moment_descriptor),
        typeof(relationship_schemas_compiled)}(
            checkerboard.shape,
            _trajectory_seed(seed, replica, repeat), terms,
            accepted_site_terms, accepted_relationship_terms, state_handles,
            contact_ranges, tracker_descriptors, moment_descriptor,
            relationship_schemas_compiled)
    core_reads = (
        sites = LocalMath.Access(
            topology.sites, topology.identity; required = true),
        owners = LocalMath.Access(
            topology.owners, topology.identity; required = true),
        kinds = LocalMath.Access(kinds, topology.identity; required = true),
        volumes = LocalMath.Access(volumes, topology.identity; required = true),
        actionable = LocalMath.Access(
            topology.actionable, topology.identity; required = true),
        semantic = LocalMath.Access(
            topology.semantic, topology.identity; required = true),
    )
    parameter_reads = science_parameters === nothing ? NamedTuple() : (
        science_parameters = LocalMath.Access(
            science_parameters, topology.identity; required = true),)
    base_reads = merge(core_reads, parameter_reads)
    contact_reads = contact === nothing ? NamedTuple() : (
        contact_sites = LocalMath.Access(
            contact.sites, topology.identity; required = true),
        contact_owners = LocalMath.Access(
            contact.owners, topology.identity; required = true),
        contact_kinds = LocalMath.Access(
            contact.kinds, topology.identity; required = true),
        reverse_contact_sites = LocalMath.Access(
            contact.reverse_sites, topology.identity; required = true),
        reverse_contact_owners = LocalMath.Access(
            contact.reverse_owners, topology.identity; required = true),
        reverse_contact_kinds = LocalMath.Access(
            contact.reverse_kinds, topology.identity; required = true),
    )
    tracker_reads = NamedTuple{tracker_names}(map(
        field -> LocalMath.Access(
            field, topology.identity; required = true),
        tracker_pair_fields))
    moment_reads = NamedTuple{moment_names}(map(
        field -> LocalMath.Access(field, kind_relation),
        moment_source_fields))
    relationship_reads = _checkerboard_relationship_science_reads(
        relationship_science)
    scientific_reads = NamedTuple{(
        keys(base_reads)..., keys(contact_reads)..., keys(tracker_reads)...,
        keys(moment_reads)..., keys(relationship_reads)...,
        state_names..., contact_state_names..., reverse_contact_state_names...,
        affected_contact_state_names...)}((
            values(base_reads)..., values(contact_reads)...,
            values(tracker_reads)..., values(moment_reads)...,
            values(relationship_reads)...,
            state_accesses..., contact_state_accesses...,
            reverse_contact_state_accesses...,
            affected_contact_state_accesses...))
    base_publications = (
        publication(evaluation.delta_h, :delta_h, T),
        publication(evaluation.drive_energy, :drive_energy, T),
        publication(evaluation.drive_log_bias, :drive_log_bias, T),
        publication(evaluation.kinetic_modifier, :kinetic_modifier, T),
        publication(evaluation.constraints_allowed,
            :constraints_allowed, Bool),
    )
    site_publications = map(
        site_port_names, values(accepted_site_fields)) do name, field
        publication(field, name, eltype(field))
    end
    relationship_publications = map(
        relationship_port_names, values(accepted_relationship_fields)) do name, field
        publication(field, name, eltype(field))
    end
    scientific_publications = (
        base_publications..., site_publications...,
        relationship_publications...)
    scientific_stage = LocalMath.Stage(
        topology.source_space,
        scientific_reads,
        scientific_publications,
        LocalMath.Evaluator(
            scientific_evaluator, (topology.mcs, topology.color)),
        LocalMath.Control(; prefix = topology.batch_size),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_scientific_evaluation),
    )
    tracker_laws = tracker_stage === nothing ? () :
        (LocalMath.LocalLaw(tracker_stage),)
    contact_laws = contact === nothing ? () : (contact.law,)
    relationship_geometry_laws = map(relationship_science) do declaration
        LocalMath.sequence(
            LocalMath.LocalLaw(declaration.edge_stage),
            LocalMath.LocalLaw(declaration.endpoint_stage))
    end
    law = LocalMath.sequence(
        topology.law,
        LocalMath.LocalLaw(cell_resource_stage),
        tracker_laws...,
        contact_laws...,
        relationship_geometry_laws...,
        LocalMath.LocalLaw(scientific_stage),
    )
    return merge(topology, (;
        law, terms, shape = checkerboard.shape,
        cell_space, cell_kinds, cell_generations, cell_volumes,
        kind_relation,
        kinds, volumes,
        evaluation, accepted_site_terms, accepted_site_fields,
        accepted_relationship_terms, accepted_relationship_fields,
        accepted_count = stage_plan.accepted_count,
        scientific_evaluator, state_handles, state_fields,
        accepted_state_handles, accepted_state_fields,
        ownership_change_handles,
        proposal_site_relation, science_parameters, parameter_count, contact,
        contact_ranges, tracker_keys, tracker_descriptors,
        tracker_source_fields, tracker_pair_fields,
        moment_descriptor, moment_source_fields,
        relationship_science, relationship_bank_fields))
end

struct _AcceptanceTemperature{Index,T}
    default::T
end

_acceptance_temperature(scalar::CompiledScalar{T}) where {T} =
    _AcceptanceTemperature{Int(scalar.parameter_index),T}(scalar.value)

@inline _acceptance_temperature_value(
    temperature::_AcceptanceTemperature{0}, parameters,
) = temperature.default
@inline _acceptance_temperature_value(
    ::_AcceptanceTemperature{Index}, parameters,
) where {Index} = getfield(parameters, Index)

struct _CompiledProposalAcceptanceEvaluator{HasParameters,T,F,R}
    trajectory_seed::UInt64
    temperature::T
    forbid_extinction::F
    retire_at_zero::R
end


_compiled_proposal_acceptance_evaluator(
    ::Val{HasParameters}, trajectory_seed, temperature, forbid, retire,
) where {HasParameters} = _CompiledProposalAcceptanceEvaluator{
    HasParameters,typeof(temperature),typeof(forbid),typeof(retire)}(
        trajectory_seed, temperature, forbid, retire)

@inline _compiled_acceptance_parameters(reads, ::Val{false}) = ()
@inline _compiled_acceptance_parameters(reads, ::Val{true}) =
    something(@inbounds getfield(reads, 11)[1].value)

@inline function _compiled_extinction_admitted(
        evaluator::_CompiledProposalAcceptanceEvaluator,
        owners::NTuple{2,Int32}, kinds::NTuple{2,Int16},
        volumes::NTuple{2,Int32},
    )
    old_owner, new_owner = owners
    old_owner > 0 && old_owner != new_owner || return true
    volumes[1] == Int32(1) || return true
    kind = kinds[1]
    kind > 0 || return false
    index = Int(kind)
    1 <= index <= length(evaluator.forbid_extinction) || return false
    @inbounds evaluator.forbid_extinction[index] && return false
    return @inbounds evaluator.retire_at_zero[index]
end

@inline function (evaluator::_CompiledProposalAcceptanceEvaluator{
        HasParameters})(
        item::Int32, reads, parameters,
    ) where {HasParameters}
    actionable = something(@inbounds getfield(reads, 1)[1].value)
    owners = something(@inbounds getfield(reads, 2)[1].value)
    kinds = something(@inbounds getfield(reads, 3)[1].value)
    volumes = something(@inbounds getfield(reads, 4)[1].value)
    semantic = something(@inbounds getfield(reads, 5)[1].value)
    delta_h = something(@inbounds getfield(reads, 6)[1].value)
    drive_energy = something(@inbounds getfield(reads, 7)[1].value)
    drive_log_bias = something(@inbounds getfield(reads, 8)[1].value)
    kinetic_modifier = something(@inbounds getfield(reads, 9)[1].value)
    constraints_allowed = something(
        @inbounds getfield(reads, 10)[1].value)
    science_parameters = _compiled_acceptance_parameters(
        reads, Val(HasParameters))
    disposition = _PROGRAM_CHECKERBOARD_NULL
    failure_code = UInt8(ProposalAcceptanceReady)
    if actionable
        if !_compiled_extinction_admitted(
                evaluator, owners, kinds, volumes)
            disposition = _PROGRAM_CHECKERBOARD_CONSTRAINT
        else
            temperature = _acceptance_temperature_value(
                evaluator.temperature, science_parameters)
            log_ratio, acceptance_code = _proposal_acceptance_values(
                delta_h, drive_energy, drive_log_bias,
                kinetic_modifier, constraints_allowed, temperature)
            if acceptance_code === ProposalAcceptanceConstraintRejected
                disposition = _PROGRAM_CHECKERBOARD_CONSTRAINT
            elseif acceptance_code === ProposalAcceptanceNonfinite
                disposition = _PROGRAM_CHECKERBOARD_NONFINITE
                failure_code = UInt8(acceptance_code)
            elseif acceptance_code === ProposalAcceptanceZeroTemperatureDrive
                disposition = _PROGRAM_CHECKERBOARD_ZERO_T_DRIVE
                failure_code = UInt8(acceptance_code)
            else
                accepted = log_ratio >= zero(temperature)
                if !accepted && isfinite(log_ratio)
                    mcs = getfield(parameters, 1)
                    color = getfield(parameters, 2)
                    address = _program_address(
                        AcceptanceStream, mcs, 3, semantic;
                        subround = color)
                    draw = uniform_open01(
                        typeof(temperature), Philox4x32x10V2(),
                        evaluator.trajectory_seed, address)
                    accepted = log(draw) < log_ratio
                end
                disposition = accepted ? _PROGRAM_CHECKERBOARD_ACCEPTED :
                    _PROGRAM_CHECKERBOARD_ENERGY
            end
        end
    end
    return (
        disposition = LocalMath.UniqueValue(disposition),
        failure_code = LocalMath.UniqueValue(failure_code),
        failure_identity = LocalMath.UniqueValue(
            iszero(failure_code) ? Int32(0) : semantic),
    )
end

function _checkerboard_acceptance_declaration(
        scientific,
        temperature::CompiledScalar{T},
        forbid_extinction::Tuple,
        retire_at_zero::Tuple,
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
    ) where {T<:AbstractFloat}
    length(forbid_extinction) == length(retire_at_zero) ||
        throw(ArgumentError(
            "checkerboard extinction policy tuples must share one kind range"))
    all(value -> value isa Bool, forbid_extinction) &&
        all(value -> value isa Bool, retire_at_zero) ||
        throw(ArgumentError(
            "checkerboard extinction policies must be Boolean tuples"))
    temperature.parameter_index <= scientific.parameter_count ||
        throw(ArgumentError(
            "checkerboard temperature parameter is outside the scientific parameter schema"))
    disposition = LocalMath.Field(scientific.source_space, UInt8)
    failure_code = LocalMath.Field(scientific.source_space, UInt8)
    failure_identity = LocalMath.Field(scientific.source_space, Int32)
    evaluator = _compiled_proposal_acceptance_evaluator(
        Val(!iszero(scientific.parameter_count)),
        _trajectory_seed(seed, replica, repeat),
        _acceptance_temperature(temperature),
        forbid_extinction,
        retire_at_zero)
    publication(field, name, type) = LocalMath.Publication((
        LocalMath.FieldPublication(
            field, scientific.identity, LocalMath.PublicationValue(name)),),
        _checkerboard_scratch_unique(type))
    core_reads = (
        actionable = LocalMath.Access(
            scientific.actionable, scientific.identity; required = true),
        owners = LocalMath.Access(
            scientific.owners, scientific.identity; required = true),
        kinds = LocalMath.Access(
            scientific.kinds, scientific.identity; required = true),
        volumes = LocalMath.Access(
            scientific.volumes, scientific.identity; required = true),
        semantic = LocalMath.Access(
            scientific.semantic, scientific.identity; required = true),
        delta_h = LocalMath.Access(
            scientific.evaluation.delta_h,
            scientific.identity; required = true),
        drive_energy = LocalMath.Access(
            scientific.evaluation.drive_energy,
            scientific.identity; required = true),
        drive_log_bias = LocalMath.Access(
            scientific.evaluation.drive_log_bias,
            scientific.identity; required = true),
        kinetic_modifier = LocalMath.Access(
            scientific.evaluation.kinetic_modifier,
            scientific.identity; required = true),
        constraints_allowed = LocalMath.Access(
            scientific.evaluation.constraints_allowed,
            scientific.identity; required = true),
    )
    parameter_reads = scientific.science_parameters === nothing ?
        NamedTuple() : (
            science_parameters = LocalMath.Access(
                scientific.science_parameters,
                scientific.identity; required = true),)
    stage = LocalMath.Stage(
        scientific.source_space,
        merge(core_reads, parameter_reads),
        (
            publication(disposition, :disposition, UInt8),
            publication(failure_code, :failure_code, UInt8),
            publication(failure_identity, :failure_identity, Int32),
        ),
        LocalMath.Evaluator(
            evaluator, (scientific.mcs, scientific.color)),
        LocalMath.Control(; prefix = scientific.batch_size),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_proposal_acceptance),
    )
    law = LocalMath.sequence(
        scientific.law, LocalMath.LocalLaw(stage))
    return merge(scientific, (;
        law, disposition, failure_code, failure_identity,
        acceptance_evaluator = evaluator))
end

struct _CheckerboardAcceptedValidation{S,R,M}
    site_terms::S
    relationship_terms::R
    maximum_batch::M
end

struct _CheckerboardAcceptedStatePublication{N,HasAssignments,H,A,C}
    handles::H
    assignments::A
    clear_handles::C
end

_checkerboard_accepted_state_publication(
        ::Val{Names}, ::Val{HasAssignments}, handles, assignments,
        clear_handles) where {Names,HasAssignments} =
    _CheckerboardAcceptedStatePublication{
        Names,HasAssignments,typeof(handles),typeof(assignments),
        typeof(clear_handles)}(handles, assignments, clear_handles)

@generated function _checkerboard_terminal_state_values(
        reads, ::Val{Count}, ::Val{Offset}) where {Count,Offset}
    return Expr(:tuple, (
        :(something(@inbounds getfield(reads, $(index + Offset))[1].value))
        for index in 1:Count)...)
end

@inline _apply_accepted_site_assignments(
    ::Tuple{}, ::Tuple{}, handle, value) = value
@inline function _apply_accepted_site_assignments(
        assignments::Tuple, evaluations::Tuple, handle, value)
    assignment = first(assignments)
    code = getfield(evaluations, 1)
    evaluation = getfield(evaluations, 2)
    updated = assignment.target == handle && code == _ACCEPTED_SITE_READY ?
        convert(typeof(value), evaluation) : value
    return _apply_accepted_site_assignments(
        Base.tail(assignments), Base.tail(Base.tail(evaluations)),
        handle, updated)
end

@inline _accepted_state_publications(
    ::Tuple{}, ::Tuple{}, assignments, evaluations, clear_handles,
    ownership_changed, accepted) = ()
@inline function _accepted_state_publications(
        handles::Tuple, values::Tuple, assignments, evaluations,
        clear_handles, ownership_changed, accepted)
    handle = first(handles)
    value = first(values)
    baseline = ownership_changed && handle in clear_handles ?
        zero(value) : value
    result = _apply_accepted_site_assignments(
        assignments, evaluations, handle, baseline)
    return (LocalMath.ConditionalUniqueValue(result, accepted),
        _accepted_state_publications(
            Base.tail(handles), Base.tail(values), assignments,
            evaluations, clear_handles, ownership_changed, accepted)...)
end

@inline function _checkerboard_accepted_state_result(
        evaluator::_CheckerboardAcceptedStatePublication{Names},
        reads, evaluations, values) where {Names}
    disposition = something(@inbounds getfield(reads, 1)[1].value)
    owners = something(@inbounds getfield(reads, 2)[1].value)
    accepted = disposition == _PROGRAM_CHECKERBOARD_ACCEPTED
    results = _accepted_state_publications(
        evaluator.handles, values, evaluator.assignments, evaluations,
        evaluator.clear_handles, owners[1] != owners[2], accepted)
    return NamedTuple{Names}((
        LocalMath.ConditionalUniqueValue(owners[2], accepted),
        results...,
    ))
end

@inline function (evaluator::_CheckerboardAcceptedStatePublication{
        Names,true})(item::Int32, reads, parameters) where {Names}
    evaluations = _accepted_site_evaluations(
        reads, evaluator.assignments, Val(3))
    values = _checkerboard_terminal_state_values(
        reads, Val(length(evaluator.handles)),
        Val(2 + 2length(evaluator.assignments)))
    return _checkerboard_accepted_state_result(
        evaluator, reads, evaluations, values)
end

@inline function (evaluator::_CheckerboardAcceptedStatePublication{
        Names,false})(item::Int32, reads, parameters) where {Names}
    values = _checkerboard_terminal_state_values(
        reads, Val(length(evaluator.handles)), Val(2))
    return _checkerboard_accepted_state_result(
        evaluator, reads, (), values)
end

@generated function _accepted_site_evaluations(
        reads, ::Terms, ::Val{Offset}) where {Terms<:Tuple,Offset}
    return Expr(:tuple, (
        :(something(@inbounds getfield(reads, $(Offset + index - 1))[1].value))
        for index in 1:(2fieldcount(Terms)))...)
end

@generated function (evaluator::_CheckerboardAcceptedValidation{S,R})(
        item::Int32, reads, parameters) where {S<:Tuple,R<:Tuple}
    checks = Expr[]
    read_index = 3
    for index in 1:fieldcount(S)
        push!(checks, quote
            local term = getfield(evaluator.site_terms, $index)
            local code = something(
                @inbounds getfield(reads, $read_index)[1].value)
            if (code == _ACCEPTED_SITE_INVALID_CONDITION ||
                    code == _ACCEPTED_SITE_INVALID_VALUE) &&
                    term.descriptor_ordinal < descriptor_ordinal
                invalid = true
                descriptor_ordinal = term.descriptor_ordinal
                source_handle = term.source_handle
                stage = ProgramStageState
                detail = code == _ACCEPTED_SITE_INVALID_CONDITION ?
                    LifecycleDetailTriggerNotBoolean :
                    LifecycleDetailNonfiniteResult
            end
        end)
        read_index += 2
    end
    for (index, term_type) in enumerate(R.parameters)
        push!(checks, quote
            local term = getfield(evaluator.relationship_terms, $index)
            local code = something(
                @inbounds getfield(reads, $read_index)[1].value)
            if (code == _ACCEPTED_RELATIONSHIP_INVALID_CONDITION ||
                    code == _ACCEPTED_RELATIONSHIP_INVALID_VALUE) &&
                    term.descriptor_ordinal < descriptor_ordinal
                invalid = true
                descriptor_ordinal = term.descriptor_ordinal
                source_handle = term.source_handle
                stage = ProgramStageRelationships
                detail = code == _ACCEPTED_RELATIONSHIP_INVALID_CONDITION ?
                    LifecycleDetailTriggerNotBoolean :
                    LifecycleDetailNonfiniteResult
            end
        end)
        read_index += 2 + fieldcount(term_type.parameters[5])
    end
    return quote
        local semantic = something(@inbounds getfield(reads, 1)[1].value)
        local disposition = something(@inbounds getfield(reads, 2)[1].value)
        local invalid = false
        local source_handle = Int32(1)
        local descriptor_ordinal = typemax(Int32)
        local stage = ProgramStageState
        local detail = LifecycleDetailNonfiniteResult
        $(checks...)
        local enabled =
            disposition == _PROGRAM_CHECKERBOARD_ACCEPTED && invalid
        invalid || (descriptor_ordinal = Int32(1))
        local status = ProgramStatus(
            ProgramStatusEvaluator,
            getfield(parameters, 1),
            stage,
            source_handle,
            UInt64(semantic),
            Int32(0),
            item,
            detail,
            Int32(0), Int32(0), Int32(0))
        local rank = (descriptor_ordinal - Int32(1)) *
            evaluator.maximum_batch + item
        (status = LocalMath.RoutedResolutionValue(
            Int32(1), rank, status, enabled),)
    end
end

struct _CheckerboardRelationshipEndpointEvaluator{N} end
struct _CheckerboardRelationshipFoldEvaluator{P,T}
    terms::T
    accepted_count::Int32
end
struct _CheckerboardRelationshipOrderKey{P} end
struct _CheckerboardRelationshipOrderIdentity{P} end

struct _CheckerboardCompiledRelationshipTransition{P,S}
    schema::S
end

struct _CheckerboardScalarTrackerEvaluator{N,D,R,S}
    descriptors::D
    contact_ranges::R
    shape::S
    owner_capacity::Int32
    first_column::Int32
end

struct _CheckerboardMomentTrackerEvaluator{N,C,T,S}
    shape::S
    owner_capacity::Int32
    component_count::Int32
end

@inline function _checkerboard_tracker_contribution(
        key::Int32, value, participates::Bool)
    return LocalMath.RoutedContribution(
        participates ? key : Int32(1), value, participates)
end

@inline function _checkerboard_surface_tracker_delta(
        descriptor::CellSurfaceTracker,
        contact_sites,
        contact_owners,
        contact_ranges,
        target::Int32,
        old_owner::Int32,
        new_owner::Int32,
    )
    starts, counts = contact_ranges
    handle = Int(descriptor.relation_handle)
    start = Int(@inbounds starts[handle])
    count = Int(@inbounds counts[handle])
    count == Int(descriptor.maximum_neighbors) || throw(ArgumentError(
        "surface tracker relation degree differs from its compiled bound"))
    old_amount = Int32(0)
    new_amount = Int32(0)
    for direction in 1:count
        lane = start + direction - 1
        neighbor = @inbounds contact_sites[lane]
        neighbor > 0 || continue
        neighbor == target && continue
        duplicate = false
        for prior in 1:(direction - 1)
            if @inbounds(contact_sites[start + prior - 1]) == neighbor
                duplicate = true
                break
            end
        end
        duplicate && continue
        neighbor_owner = @inbounds contact_owners[lane]
        old_owner > 0 && (old_amount += neighbor_owner == old_owner ?
            Int32(1) : Int32(-1))
        new_owner > 0 && (new_amount += neighbor_owner == new_owner ?
            Int32(-1) : Int32(1))
    end
    return SourceTargetScalarDelta(old_amount, new_amount)
end

@inline _checkerboard_scalar_tracker_delta(
    ::OwnershipCountTracker, contact_sites, contact_owners, contact_ranges,
    target, old_owner, new_owner,
) = OwnerScalarDelta(Int32(1))

@inline _checkerboard_scalar_tracker_delta(
    descriptor::CellSurfaceTracker, contact_sites, contact_owners,
    contact_ranges, target, old_owner, new_owner,
) = _checkerboard_surface_tracker_delta(
    descriptor, contact_sites, contact_owners, contact_ranges,
    target[1], old_owner, new_owner)

@inline _checkerboard_scalar_tracker_delta(
    descriptor::AbstractTrackerDescriptor, contact_sites, contact_owners,
    contact_ranges, target, old_owner, new_owner,
) = tracker_proposal_delta(
    descriptor, nothing, target[2], old_owner, new_owner)

@inline function _checkerboard_scalar_tracker_pair(
        delta::OwnerScalarDelta,
        old_owner::Int32,
        new_owner::Int32,
        column::Int32,
        owner_capacity::Int32,
        accepted::Bool,
    )
    offset = (column - Int32(1)) * owner_capacity
    return (
        _checkerboard_tracker_contribution(
            offset + old_owner, -delta.amount, accepted && old_owner > 0),
        _checkerboard_tracker_contribution(
            offset + new_owner, delta.amount, accepted && new_owner > 0),
    )
end

@inline function _checkerboard_scalar_tracker_pair(
        delta::SourceTargetScalarDelta,
        old_owner::Int32,
        new_owner::Int32,
        column::Int32,
        owner_capacity::Int32,
        accepted::Bool,
    )
    offset = (column - Int32(1)) * owner_capacity
    return (
        _checkerboard_tracker_contribution(
            offset + old_owner, delta.old_amount,
            accepted && old_owner > 0),
        _checkerboard_tracker_contribution(
            offset + new_owner, delta.new_amount,
            accepted && new_owner > 0),
    )
end

@inline _checkerboard_scalar_tracker_contributions(
    ::Tuple{}, contact_sites, contact_owners, contact_ranges, target,
    old_owner, new_owner, column, owner_capacity, accepted,
) = ()

@inline function _checkerboard_scalar_tracker_contributions(
        descriptors::Tuple,
        contact_sites,
        contact_owners,
        contact_ranges,
        target,
        old_owner,
        new_owner,
        column,
        owner_capacity,
        accepted,
    )
    delta = _checkerboard_scalar_tracker_delta(
        first(descriptors), contact_sites, contact_owners, contact_ranges,
        target, old_owner, new_owner)
    return (
        _checkerboard_scalar_tracker_pair(
            delta, old_owner, new_owner, column, owner_capacity, accepted)...,
        _checkerboard_scalar_tracker_contributions(
            Base.tail(descriptors), contact_sites, contact_owners,
            contact_ranges, target, old_owner, new_owner, column + Int32(1),
            owner_capacity, accepted)...,
    )
end

@inline function (evaluator::_CheckerboardScalarTrackerEvaluator{Name})(
        item::Int32, reads, parameters) where {Name}
    disposition = something(@inbounds getfield(reads, 1)[1].value)
    owners = something(@inbounds getfield(reads, 2)[1].value)
    sites = something(@inbounds getfield(reads, 3)[1].value)
    contact_sites = fieldcount(typeof(reads)) >= 4 ?
        something(@inbounds getfield(reads, 4)[1].value) : ()
    contact_owners = fieldcount(typeof(reads)) >= 5 ?
        something(@inbounds getfield(reads, 5)[1].value) : ()
    accepted = disposition == _PROGRAM_CHECKERBOARD_ACCEPTED
    contributions = _checkerboard_scalar_tracker_contributions(
        evaluator.descriptors, contact_sites, contact_owners,
        evaluator.contact_ranges,
        (sites[1], _checkerboard_cartesian_site(evaluator.shape, sites[1])),
        owners[1], owners[2],
        evaluator.first_column, evaluator.owner_capacity, accepted)
    return NamedTuple{(Name,)}((contributions,))
end

@generated function (evaluator::_CheckerboardMomentTrackerEvaluator{
        Name,Components,T})(item::Int32, reads, parameters) where {
        Name,Components,T}
    contributions = Expr[]
    for owner_lane in 1:2, (component, row, column) in Components
        row = Int(row)
        column = Int(column)
        owner = :(getfield(owners, $owner_lane))
        left = :($T(target[$row]) - $T(0.5))
        value = iszero(column) ? left :
            :($left * ($T(target[$column]) - $T(0.5)))
        signed = owner_lane == 1 ? :(-$value) : value
        push!(contributions, :(_checkerboard_tracker_contribution(
            Int32($(Int32(component)) +
                ($owner - Int32(1)) * evaluator.component_count),
            $signed, accepted && $owner > 0)))
    end
    return quote
        local disposition = something(
            @inbounds getfield(reads, 1)[1].value)
        local owners = something(@inbounds getfield(reads, 2)[1].value)
        local sites = something(@inbounds getfield(reads, 3)[1].value)
        local target = _checkerboard_cartesian_site(
            evaluator.shape, getfield(sites, 1))
        local accepted =
            disposition == _PROGRAM_CHECKERBOARD_ACCEPTED
        NamedTuple{$(QuoteNode((Name,)))}((($(contributions...),),))
    end
end

_checkerboard_tracker_contains_surface(::Tuple{}) = false
function _checkerboard_tracker_contains_surface(descriptors::Tuple)
    return first(descriptors) isa CellSurfaceTracker ||
        _checkerboard_tracker_contains_surface(Base.tail(descriptors))
end


function _checkerboard_tracker_reads(accepted, descriptors::Tuple)
    base = (
        disposition = LocalMath.Access(
            accepted.disposition, accepted.identity; required = true),
        owners = LocalMath.Access(
            accepted.owners, accepted.identity; required = true),
        sites = LocalMath.Access(
            accepted.sites, accepted.identity; required = true),
    )
    _checkerboard_tracker_contains_surface(descriptors) || return base
    accepted.contact === nothing && throw(ArgumentError(
        "surface tracker compilation requires a bounded contact relation"))
    return merge(base, (
        contact_sites = LocalMath.Access(
            accepted.contact.sites, accepted.identity; required = true),
        contact_owners = LocalMath.Access(
            accepted.contact.owners, accepted.identity; required = true),
    ))
end

function _checkerboard_tracker_field(array::AbstractArray)
    return LocalMath.Field(LocalMath.Space(size(array)), eltype(array))
end

_checkerboard_tracker_scratch(field::LocalMath.Field) =
    LocalMath.Field(field.space, eltype(field))

function _checkerboard_transactional_tracker_group(laws_builder,
        tracker_index, source_fields, paths, terminal_gate)
    fields = map(_checkerboard_tracker_scratch, source_fields)
    initialization_laws = Tuple(_checkerboard_field_copy_law(source, scratch,
            terminal_gate, Symbol(:checkerboard_tracker_initialize_,
                tracker_index, :_, index))
        for (index, (source, scratch)) in enumerate(zip(source_fields, fields)))
    commit_laws = Tuple(_checkerboard_field_copy_law(scratch, source,
            terminal_gate, Symbol(:checkerboard_tracker_commit_,
                tracker_index, :_, index))
        for (index, (source, scratch)) in enumerate(zip(source_fields, fields)))
    laws = laws_builder(fields)
    return (; tracker_index = Int32(tracker_index), source_fields, fields,
        paths, initialization_laws, laws, commit_laws)
end

function _checkerboard_scalar_tracker_laws(
        accepted,
        field,
        descriptors::Tuple,
        first_column::Integer,
        owner_capacity::Integer,
        terminal_gate,
        label_prefix::Symbol,
    )
    isempty(descriptors) && return ()
    chunk_count = min(length(descriptors), 16)
    chunk = ntuple(index -> descriptors[index], chunk_count)
    remaining = length(descriptors) == chunk_count ? () :
        ntuple(index -> descriptors[chunk_count + index],
            length(descriptors) - chunk_count)
    name = Symbol(label_prefix, :_, first_column)
    relation = LocalMath.RuntimeRelation(
        accepted.source_space => field.space;
        degree_bound = 2chunk_count, key_type = Int32)
    evaluator = _CheckerboardScalarTrackerEvaluator{
        name,typeof(chunk),typeof(accepted.contact_ranges),
        typeof(accepted.shape)}(
            chunk, accepted.contact_ranges, accepted.shape,
            Int32(owner_capacity), Int32(first_column))
    stage = LocalMath.Stage(
        accepted.source_space,
        _checkerboard_tracker_reads(accepted, chunk),
        (LocalMath.Publication((LocalMath.FieldPublication(
            field, relation, LocalMath.PublicationValue(name)),),
            LocalMath.Reduce(eltype(field), +;
                maximum = 2chunk_count,
                seed = LocalMath.ExistingSeed(),
                order = LocalMath.CanonicalLeftFold())),),
        LocalMath.Evaluator(evaluator),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = terminal_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = Symbol(label_prefix, :_publication)),
    )
    return (
        LocalMath.LocalLaw(stage),
        _checkerboard_scalar_tracker_laws(
            accepted, field, remaining,
            first_column + chunk_count, owner_capacity, terminal_gate,
            label_prefix)...,
    )
end

function _checkerboard_moment_tracker_laws(
        accepted,
        field,
        components::Tuple,
        ::Type{T},
        component_count::Integer,
        owner_capacity::Integer,
        terminal_gate,
        label_prefix::Symbol,
    ) where {T}
    isempty(components) && return ()
    chunk_count = min(length(components), 16)
    chunk = ntuple(index -> components[index], chunk_count)
    remaining = length(components) == chunk_count ? () :
        ntuple(index -> components[chunk_count + index],
            length(components) - chunk_count)
    name = Symbol(label_prefix, :_, first(chunk)[1])
    relation = LocalMath.RuntimeRelation(
        accepted.source_space => field.space;
        degree_bound = 2chunk_count, key_type = Int32)
    evaluator = _CheckerboardMomentTrackerEvaluator{
        name,chunk,T,typeof(accepted.shape)}(
            accepted.shape, Int32(owner_capacity),
            Int32(component_count))
    stage = LocalMath.Stage(
        accepted.source_space,
        _checkerboard_tracker_reads(accepted, ()),
        (LocalMath.Publication((LocalMath.FieldPublication(
            field, relation, LocalMath.PublicationValue(name)),),
            LocalMath.Reduce(T, +;
                maximum = 2chunk_count,
                seed = LocalMath.ExistingSeed(),
                order = LocalMath.CanonicalLeftFold())),),
        LocalMath.Evaluator(evaluator),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = terminal_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = Symbol(label_prefix, :_publication)),
    )
    return (
        LocalMath.LocalLaw(stage),
        _checkerboard_moment_tracker_laws(
            accepted, field, remaining, T, component_count, owner_capacity,
            terminal_gate, label_prefix)...,
    )
end

function _checkerboard_tracker_group(
        accepted, descriptor, value, tracker_index::Integer,
        owner_capacity::Integer, terminal_gate)
    if descriptor isa DenseScalarTrackerGroup
        descriptors = Tuple(descriptor.descriptors)
        source_fields = map(enumerate(descriptors)) do indexed
            column, instance = indexed
            match = findfirst(==(instance), accepted.tracker_descriptors)
            match === nothing ? _checkerboard_tracker_field(view(value, :, column)) :
                getfield(accepted.tracker_source_fields, match)
        end
        paths = ntuple(length(source_fields)) do column
            findfirst(==(descriptors[column]), accepted.tracker_descriptors) ===
                nothing ? Int32(column) : nothing
        end
        return _checkerboard_transactional_tracker_group(
            tracker_index, source_fields, paths, terminal_gate) do fields
            Tuple(law for (column, field) in enumerate(fields)
                for law in _checkerboard_scalar_tracker_laws(
                    accepted, field, (descriptors[column],), 1,
                    owner_capacity, terminal_gate,
                    Symbol(:checkerboard_tracker_, tracker_index, :_, column)))
        end
    elseif descriptor isa OwnershipCountTracker
        return _checkerboard_transactional_tracker_group(
            tracker_index, (accepted.cell_volumes,), (nothing,),
            terminal_gate) do fields
            _checkerboard_scalar_tracker_laws(
                accepted, only(fields), (descriptor,), 1, owner_capacity,
                terminal_gate, Symbol(:checkerboard_tracker_, tracker_index))
        end
    elseif tracker_storage(descriptor) isa DenseOwnerScalarStorage
        if !(descriptor isa Union{OwnershipCountTracker,CellSurfaceTracker})
            target_type = CartesianIndex{length(accepted.shape)}
            hasmethod(tracker_proposal_delta, Tuple{
                typeof(descriptor),Nothing,target_type,Int32,Int32}) || throw(
                ArgumentError(
                    "custom checkerboard scalar tracker delta must be " *
                    "computable from its descriptor, target, and owners"))
        end
        match = findfirst(==(descriptor), accepted.tracker_descriptors)
        source = match === nothing ? _checkerboard_tracker_field(value) :
            getfield(accepted.tracker_source_fields, match)
        return _checkerboard_transactional_tracker_group(
            tracker_index, (source,),
            (match === nothing ? :self : nothing,), terminal_gate) do fields
            _checkerboard_scalar_tracker_laws(
                accepted, only(fields), (descriptor,), 1, owner_capacity,
                terminal_gate, Symbol(:checkerboard_tracker_, tracker_index))
        end
    elseif descriptor isa CellMomentsTracker
        if accepted.moment_descriptor == descriptor
            dimensions = typeof(descriptor).parameters[1]
            first_fields = ntuple(
                index -> getfield(accepted.moment_source_fields, index),
                dimensions)
            second_fields = ntuple(
                index -> getfield(
                    accepted.moment_source_fields, dimensions + index),
                dimensions * dimensions)
            paths = ntuple(_ -> nothing, dimensions + dimensions * dimensions)
            return _checkerboard_transactional_tracker_group(
                tracker_index, (first_fields..., second_fields...), paths,
                terminal_gate) do fields
                first_targets = ntuple(index -> fields[index], dimensions)
                second_targets = ntuple(index -> fields[dimensions + index],
                    dimensions * dimensions)
                first_laws = Tuple(law
                    for (row, field) in enumerate(first_targets)
                    for law in _checkerboard_moment_tracker_laws(
                        accepted, field,
                        ((Int32(1), Int32(row), Int32(0)),),
                        eltype(value.first), 1, owner_capacity, terminal_gate,
                        Symbol(:checkerboard_tracker_, tracker_index,
                            :_first_, row)))
                second_laws = Tuple(law
                    for (slot, field) in enumerate(second_targets)
                    for law in _checkerboard_moment_tracker_laws(
                        accepted, field,
                        ((Int32(1), Int32(mod1(slot, dimensions)),
                            Int32(fld(slot - 1, dimensions) + 1)),),
                        eltype(value.second), 1, owner_capacity, terminal_gate,
                        Symbol(:checkerboard_tracker_, tracker_index,
                            :_second_, slot)))
                (first_laws..., second_laws...)
            end
        end
        first_field = _checkerboard_tracker_field(value.first)
        second_field = _checkerboard_tracker_field(value.second)
        dimensions = size(value.first, 1)
        first_components = ntuple(
            row -> (Int32(row), Int32(row), Int32(0)), dimensions)
        second_components = ntuple(dimensions * dimensions) do slot
            row = mod1(slot, dimensions)
            column = fld(slot - 1, dimensions) + 1
            (Int32(slot), Int32(row), Int32(column))
        end
        return _checkerboard_transactional_tracker_group(
            tracker_index, (first_field, second_field), (:first, :second),
            terminal_gate) do fields
            first_laws = _checkerboard_moment_tracker_laws(
                accepted, fields[1], first_components, eltype(value.first),
                dimensions, owner_capacity, terminal_gate,
                Symbol(:checkerboard_tracker_, tracker_index, :_first))
            second_laws = _checkerboard_moment_tracker_laws(
                accepted, fields[2], second_components, eltype(value.second),
                dimensions * dimensions, owner_capacity, terminal_gate,
                Symbol(:checkerboard_tracker_, tracker_index, :_second))
            (first_laws..., second_laws...)
        end
    end
    throw(ArgumentError(
        "checkerboard LocalMath commit does not support tracker entry " *
        string(typeof(descriptor))))
end

function _checkerboard_tracker_groups(
        accepted, tracker_plan, tracker_state, terminal_gate,
        owner_capacity::Integer)
    length(tracker_plan.descriptors) == length(tracker_state.values) ||
        throw(ArgumentError(
            "checkerboard tracker plan and state are misaligned"))
    return map(eachindex(tracker_plan.descriptors)) do index
        _checkerboard_tracker_group(
            accepted, tracker_plan.descriptors[index],
            tracker_state.values[index], index, owner_capacity, terminal_gate)
    end |> Tuple
end

@inline function _checkerboard_optional_pair(read, ::Type{T}) where {T}
    left = @inbounds read[1]
    right = @inbounds read[2]
    return (
        left.present ? convert(T, something(left.value)) : zero(T),
        right.present ? convert(T, something(right.value)) : zero(T),
    )
end

function _checkerboard_relationship_endpoint_fields(
        source::LocalMath.Space, term_count::Integer)
    names = Symbol[]
    fields = Any[]
    for index in 1:term_count
        push!(names, Symbol(:relationship_, index, :_endpoint_status))
        push!(fields, LocalMath.Field(source, Tuple{Int16,Int16}))
        push!(names, Symbol(:relationship_, index, :_endpoint_generations))
        push!(fields, LocalMath.Field(source, Tuple{UInt32,UInt32}))
    end
    return NamedTuple{Tuple(names)}(Tuple(fields))
end

function _checkerboard_relationship_endpoint_accesses(accepted, term_fields)
    names = Symbol[]
    accesses = Any[]
    for (index, fields) in enumerate(term_fields)
        relation = LocalMath.IndexRelation(
            fields.endpoints => accepted.cell_space; optional = true)
        push!(names, Symbol(:relationship_, index, :_status))
        push!(accesses, LocalMath.Access(accepted.cell_kinds, relation))
        push!(names, Symbol(:relationship_, index, :_generations))
        push!(accesses, LocalMath.Access(
            accepted.cell_generations, relation))
    end
    return NamedTuple{Tuple(names)}(Tuple(accesses))
end

@generated function (::_CheckerboardRelationshipEndpointEvaluator{Names})(
        item::Int32, reads, parameters) where {Names}
    outputs = Expr[]
    for index in 1:(length(Names) ÷ 2)
        push!(outputs, :(LocalMath.UniqueValue(
            _checkerboard_optional_pair(
                getfield(reads, $(2index - 1)), Int16))))
        push!(outputs, :(LocalMath.UniqueValue(
            _checkerboard_optional_pair(
                getfield(reads, $(2index)), UInt32))))
    end
    return :(NamedTuple{$(QuoteNode(Names))}(($(outputs...),)))
end

@generated function (evaluator::_CheckerboardRelationshipFoldEvaluator{
        P,Terms})(item::Int32, reads, parameters) where {P,Terms<:Tuple}
    branches = Expr(:block)
    term_count = fieldcount(Terms)
    for lane in 1:term_count
        offset = 2 + (lane - 1) * (P + 4)
        payload = [:(something(@inbounds getfield(
            reads, $(offset + 1 + index))[1].value)) for index in 1:P]
        status_index = offset + P + 2
        generation_index = status_index + 1
        condition = lane == term_count ? :(true) :
            :(request_lane == $(Int32(lane)))
        push!(branches.args, quote
            if $condition
                local term = getfield(evaluator.terms, $lane)
                local code = something(
                    @inbounds getfield(reads, $offset)[1].value)
                local endpoints = something(
                    @inbounds getfield(reads, $(offset + 1))[1].value)
                local statuses = something(
                    @inbounds getfield(reads, $status_index)[1].value)
                local generations = something(
                    @inbounds getfield(reads, $generation_index)[1].value)
                local disposition = something(
                    @inbounds getfield(reads, 1)[1].value)
                local enabled =
                    disposition == _PROGRAM_CHECKERBOARD_ACCEPTED &&
                    code == _ACCEPTED_RELATIONSHIP_READY
                return (event = LocalMath.FoldValue((
                    term.bank_slot,
                    getfield(endpoints, 1), getfield(endpoints, 2),
                    getfield(generations, 1), getfield(generations, 2),
                    $(payload...),
                    term.relationship_slot,
                    term.priority,
                    UInt32((candidate - Int32(1)) *
                        evaluator.accepted_count +
                        term.descriptor_ordinal),
                    getfield(statuses, 1), getfield(statuses, 2),
                    enabled,
                )),)
            end
        end)
    end
    return quote
        local request_lane = Int32(mod(item - Int32(1), $term_count) + 1)
        local candidate = Int32(fld(item - Int32(1), $term_count) + 1)
        $branches
    end
end

@generated function (::_CheckerboardRelationshipOrderKey{P})(value) where {P}
    logical_slot = 6 + P
    priority = logical_slot + 1
    enabled = logical_slot + 5
    return quote
        getfield(value, $enabled) || return (
            typemax(Int32), typemax(Int32), typemax(Int32), typemax(Int32))
        local a, b = _canonical_endpoints(
            getfield(value, 2), getfield(value, 3))
        return (getfield(value, $logical_slot),
            getfield(value, $priority), a, b)
    end
end

@generated function (::_CheckerboardRelationshipOrderIdentity{P})(
        value) where {P}
    order_identity = 8 + P
    return :(getfield(value, $order_identity))
end

@generated function (transition::_CheckerboardCompiledRelationshipTransition{P})(
        state, value, item::Int32, reads) where {P}
    payload_names = ntuple(index -> Symbol(:payload_, index), P)
    names = (
        :active,
        :endpoint_a,
        :endpoint_b,
        :generation_a,
        :generation_b,
        payload_names...,
        :degree,
        :incident_edges,
    )
    logical_slot = 6 + P
    priority = logical_slot + 1
    order_identity = priority + 1
    status_a = order_identity + 1
    status_b = status_a + 1
    enabled = status_b + 1
    incident_values = Symbol[]
    incident_initializers = Expr[]
    for lane in 1:_CHECKERBOARD_RELATIONSHIP_INCIDENT_WRITES
        value_name = Symbol(:incident_write_, lane)
        push!(incident_values, value_name)
        push!(incident_initializers, :($value_name = apply ?
            _checkerboard_fold_incident_write(
                state, fold_reads, slot, a, position_a, degree_a,
                b, position_b, degree_b, available_edge, $(Int32(lane))) :
            (Int32(1), Int32(0))))
    end
    incident_keys = Expr(:tuple,
        [:(getfield($value_name, 1)) for value_name in incident_values]...)
    incident_replacements = Expr(:tuple,
        [:(getfield($value_name, 2)) for value_name in incident_values]...)
    payload_updates = map(1:P) do index
        :(LocalMath.BoundedWrites(
            (flat_edge,), (getfield(value, $(5 + index)),), write_count))
    end
    payload_comparisons = map(1:P) do index
        payload_name = QuoteNode(payload_names[index])
        :(isequal(
            @inbounds(getproperty(state, $payload_name)[existing_flat]),
            getfield(value, $(5 + index)),
        ))
    end
    payload_matches = isempty(payload_comparisons) ? :(true) :
        foldl((left, right) -> :($left && $right), payload_comparisons)
    updates = Any[
        :(LocalMath.BoundedWrites(
            (active_key,), (true,), active_write_count)),
        :(LocalMath.BoundedWrites((flat_edge,), (a,), write_count)),
        :(LocalMath.BoundedWrites((flat_edge,), (b,), write_count)),
        :(LocalMath.BoundedWrites(
            (flat_edge,), (generation_a,), write_count)),
        :(LocalMath.BoundedWrites(
            (flat_edge,), (generation_b,), write_count)),
        payload_updates...,
        :(LocalMath.BoundedWrites(
            (
                _checkerboard_fold_degree_index(fold_reads, slot, a),
                _checkerboard_fold_degree_index(fold_reads, slot, b),
            ),
            (Int16(degree_a + Int32(1)), Int16(degree_b + Int32(1))),
            apply ? Int32(2) : Int32(0))),
        :(LocalMath.BoundedWrites(
            $incident_keys, $incident_replacements, incident_count)),
    ]
    update_tuple = Expr(:tuple, updates...)
    return quote
        local endpoint_a = getfield(value, 2)
        local endpoint_b = getfield(value, 3)
        local schema = transition.schema
        local fold_reads = (
            edge_offsets = getfield(schema, 1),
            edge_counts = getfield(schema, 2),
            endpoint_offsets = getfield(schema, 3),
            endpoint_counts = getfield(schema, 4),
            incident_offsets = getfield(schema, 5),
            maximum_degrees = getfield(schema, 6),
        )
        local slot = getfield(value, 1)
        local a, b = _canonical_endpoints(endpoint_a, endpoint_b)
        local generation_a, generation_b = endpoint_a == a ?
            (getfield(value, 4), getfield(value, 5)) :
            (getfield(value, 5), getfield(value, 4))
        local endpoint_status_a, endpoint_status_b = endpoint_a == a ?
            (getfield(value, $status_a), getfield(value, $status_b)) :
            (getfield(value, $status_b), getfield(value, $status_a))
        local admission = !getfield(value, $enabled) ?
            _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT :
            endpoint_a == endpoint_b ?
            _RELATIONSHIP_CREATE_SELF_EDGE : iszero(endpoint_status_a) ||
            iszero(endpoint_status_b) ?
            _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT :
            _RELATIONSHIP_CREATE_APPLY
        local existing = Int32(0)
        if admission == _RELATIONSHIP_CREATE_APPLY
            existing = _checkerboard_fold_relationship_edge(
                state, fold_reads, slot, a, b)
            if existing > 0
                local existing_flat =
                    _checkerboard_fold_edge_offset(fold_reads, slot) +
                    existing - Int32(1)
                admission = @inbounds(
                    state.generation_a[existing_flat] == generation_a &&
                    state.generation_b[existing_flat] == generation_b) &&
                    $payload_matches ?
                    _RELATIONSHIP_CREATE_IDEMPOTENT :
                    _RELATIONSHIP_CREATE_CONTRADICTORY
            end
        end
        local degree_a = admission == _RELATIONSHIP_CREATE_APPLY ?
            Int32(@inbounds state.degree[
                _checkerboard_fold_degree_index(fold_reads, slot, a)]) :
            Int32(0)
        local degree_b = admission == _RELATIONSHIP_CREATE_APPLY ?
            Int32(@inbounds state.degree[
                _checkerboard_fold_degree_index(fold_reads, slot, b)]) :
            Int32(0)
        local maximum_degree =
            _checkerboard_fold_maximum_degree(fold_reads, slot)
        if admission == _RELATIONSHIP_CREATE_APPLY &&
                (degree_a >= maximum_degree || degree_b >= maximum_degree)
            admission = _RELATIONSHIP_CREATE_MAXIMUM_DEGREE
        end
        local available_edge = admission == _RELATIONSHIP_CREATE_APPLY ?
            _checkerboard_fold_available_edge(state, fold_reads, slot) :
            Int32(0)
        if admission == _RELATIONSHIP_CREATE_APPLY && available_edge <= 0
            admission = _RELATIONSHIP_CREATE_CAPACITY
        end
        local apply = admission == _RELATIONSHIP_CREATE_APPLY
        local contradictory =
            admission == _RELATIONSHIP_CREATE_CONTRADICTORY
        local flat_edge = apply ?
            _checkerboard_fold_edge_offset(fold_reads, slot) +
            available_edge - Int32(1) : Int32(1)
        local position_a = apply ?
            _checkerboard_fold_insertion_position(
                state, fold_reads, slot, a, available_edge, degree_a) :
            Int32(1)
        local position_b = apply ?
            _checkerboard_fold_insertion_position(
                state, fold_reads, slot, b, available_edge, degree_b) :
            Int32(1)
        $(incident_initializers...)
        local incident_count = apply ?
            degree_a - position_a + degree_b - position_b + Int32(4) :
            Int32(0)
        local write_count = apply ? Int32(1) : Int32(0)
        # Use the fold protocol's invalid key to reject a contradictory
        # duplicate without publishing any relationship-bank writes.
        local active_key = contradictory ? Int32(0) : flat_edge
        local active_write_count = apply || contradictory ?
            Int32(1) : Int32(0)
        local updates = NamedTuple{$(QuoteNode(names))}($update_tuple)
        return LocalMath.FoldStep(updates)
    end
end

struct _CheckerboardImmutableRelationshipSchema{EO,EC,PO,PC,IO,MD}
    edge_offsets::EO
    edge_counts::EC
    endpoint_offsets::PO
    endpoint_counts::PC
    incident_offsets::IO
    maximum_degrees::MD
end

function _checkerboard_immutable_relationship_schema(bank)
    schema = _packed_relationship_schema(bank)
    schema_values = map(Base.values(schema)) do array
        Tuple(Int32.(Adapt.adapt(Array, array)))
    end
    return _CheckerboardImmutableRelationshipSchema(schema_values...)
end

function _checkerboard_relationship_state_fields(bank)
    science = _packed_relationship_science(bank)
    spaces = Dict{Int,Any}()
    fields = map(values(science)) do array
        space = get!(spaces, length(array)) do
            LocalMath.Space(length(array))
        end
        LocalMath.Field(space, eltype(array))
    end
    return NamedTuple{keys(science)}(fields)
end

function _checkerboard_relationship_groups(
        accepted, relationships, bank_field_authorities, terminal_gate)
    isempty(accepted.accepted_relationship_terms) && return ()
    field_groups = _accepted_relationship_field_groups(
        accepted.accepted_relationship_fields,
        accepted.accepted_relationship_terms)
    bank_indices = Int32[]
    for term in accepted.accepted_relationship_terms
        term.bank_index in bank_indices || push!(bank_indices, term.bank_index)
    end
    groups = map(bank_indices) do bank_index
        term_indices = Tuple(index for index in eachindex(
            accepted.accepted_relationship_terms)
            if accepted.accepted_relationship_terms[index].bank_index ==
                bank_index)
        terms = map(index -> accepted.accepted_relationship_terms[index],
            term_indices)
        term_fields = map(index -> field_groups[index], term_indices)
        payload_zero = first(terms).payload_zero
        all(term -> map(typeof, term.payload_zero) == map(typeof, payload_zero),
            terms) || throw(ArgumentError(
                "relationship terms sharing a packed bank have inconsistent payload schemas"))
        request_count = Base.Checked.checked_mul(
            length(accepted.source_space), length(terms))
        request_space = LocalMath.Space(request_count)
        endpoint_fields = _checkerboard_relationship_endpoint_fields(
            accepted.source_space, length(terms))
        endpoint_accesses = _checkerboard_relationship_endpoint_accesses(
            accepted, term_fields)
        endpoint_identity = LocalMath.IdentityRelation(accepted.source_space)
        endpoint_publications = map(
                keys(endpoint_fields), values(endpoint_fields)) do name, field
            LocalMath.Publication((LocalMath.FieldPublication(
                field, endpoint_identity, LocalMath.PublicationValue(name)),),
                _checkerboard_scratch_unique(eltype(field)))
        end
        endpoint_stage = LocalMath.Stage(
            accepted.source_space,
            endpoint_accesses,
            endpoint_publications,
            LocalMath.Evaluator(
                _CheckerboardRelationshipEndpointEvaluator{
                    keys(endpoint_fields)}()),
            LocalMath.Control(;
                prefix = accepted.batch_size, gate = terminal_gate),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_relationship_endpoints),
        )
        bank = relationships.banks[Int(bank_index)]
        bank isa PackedRelationshipBank || throw(ArgumentError(
            "checkerboard relationship compilation requires packed banks"))
        live_fields = bank_field_authorities[Int(bank_index)]
        shadow_fields = NamedTuple{keys(live_fields)}(map(values(live_fields)) do field
            LocalMath.Field(field.space, eltype(field))
        end)
        state = LocalMath.InitializedState(; map(
            (shadow, live) -> LocalMath.FoldComponent(shadow; from = live),
            shadow_fields, live_fields)...)
        payload_count = length(payload_zero)
        fold_value_type = Tuple{
            Int32,Int32,Int32,UInt32,UInt32,
            map(typeof, payload_zero)...,
            Int32,Int32,UInt32,Int16,Int16,Bool,
        }
        transition = _CheckerboardCompiledRelationshipTransition{
            payload_count,
            typeof(_checkerboard_immutable_relationship_schema(bank))}(
                _checkerboard_immutable_relationship_schema(bank))
        fold = LocalMath.OrderedFold(
            fold_value_type, state, transition;
            order = LocalMath.canonical_by(
                _CheckerboardRelationshipOrderKey{payload_count}(),
                _CheckerboardRelationshipOrderIdentity{payload_count}()))
        candidate_relation = LocalMath.FixedRelation(
            request_space => accepted.source_space; degree = 1)
        access_names = Symbol[:disposition]
        access_values = Any[LocalMath.Access(
            accepted.disposition, candidate_relation; required = true)]
        for (index, fields) in enumerate(term_fields)
            prefix = Symbol(:relationship_, index)
            push!(access_names, Symbol(prefix, :_code))
            push!(access_values, LocalMath.Access(
                fields.code, candidate_relation; required = true))
            push!(access_names, Symbol(prefix, :_endpoints))
            push!(access_values, LocalMath.Access(
                fields.endpoints, candidate_relation; required = true))
            for (payload_index, field) in enumerate(fields.payload)
                push!(access_names, Symbol(prefix, :_payload_, payload_index))
                push!(access_values, LocalMath.Access(
                    field, candidate_relation; required = true))
            end
            push!(access_names, Symbol(prefix, :_status))
            push!(access_values, LocalMath.Access(
                getfield(endpoint_fields, 2index - 1),
                candidate_relation; required = true))
            push!(access_names, Symbol(prefix, :_generations))
            push!(access_values, LocalMath.Access(
                getfield(endpoint_fields, 2index),
                candidate_relation; required = true))
        end
        fold_accesses = NamedTuple{Tuple(access_names)}(Tuple(access_values))
        fold_stage = LocalMath.Stage(
            request_space,
            fold_accesses,
            (LocalMath.Publication((LocalMath.FoldPublication(
                LocalMath.PublicationValue(:event)),), fold),),
            LocalMath.Evaluator(
                _CheckerboardRelationshipFoldEvaluator{
                    payload_count,typeof(terms)}(
                        terms, Int32(accepted.accepted_count))),
            LocalMath.Control(; gate = terminal_gate),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_relationship_settlement),
        )
        return (;
            bank_index, terms, request_space, endpoint_fields,
            candidate_relation, live_fields, shadow_fields,
            law = LocalMath.sequence(
                LocalMath.LocalLaw(endpoint_stage),
                LocalMath.LocalLaw(fold_stage)))
    end
    return Tuple(groups)
end


function _checkerboard_field_copy_law(source::LocalMath.Field,
        destination::LocalMath.Field, gate, label::Symbol)
    source.space == destination.space && eltype(source) === eltype(destination) ||
        throw(ArgumentError(
            "checkerboard transactional field copies require identical schemas"))
    identity = LocalMath.IdentityRelation(source.space)
    stage = LocalMath.Stage(
        source.space,
        (source = LocalMath.Access(source, identity; required = true),),
        (LocalMath.Publication((LocalMath.FieldPublication(
            destination, identity, LocalMath.PublicationValue(:value)),),
            LocalMath.Unique(eltype(destination))),),
        LocalMath.Evaluator(_ProgramStateCopyEvaluator()),
        gate === nothing ? LocalMath.Control() : LocalMath.Control(; gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__; label),
    )
    return LocalMath.LocalLaw(stage)
end

function _checkerboard_relationship_commit_laws(groups, gate)
    return Tuple(_checkerboard_field_copy_law(shadow, live, gate,
            Symbol(:checkerboard_relationship_commit_, group.bank_index,
                :_, name))
        for group in groups
        for (name, shadow, live) in zip(keys(group.shadow_fields),
            values(group.shadow_fields), values(group.live_fields)))
end

function _checkerboard_color_declaration(
        accepted,
        owner_capacity::Integer,
        relationships,
        tracker_plan,
        tracker_state,
    )
    owner_capacity >= 0 || throw(ArgumentError(
        "checkerboard owner capacity cannot be negative"))
    owners_space = LocalMath.Space(
        _CheckerboardClaimOwner, Int(owner_capacity))
    status_space = LocalMath.Space(_CheckerboardAcceptanceStatus, 1)
    report_space = LocalMath.Space(_CheckerboardReportBin, 5)
    gate_space = LocalMath.Space(_CheckerboardAcceptanceGate, 1)

    winners = LocalMath.Field(owners_space, Int32)
    status = LocalMath.Field(status_space, ProgramStatus)
    report = LocalMath.Field(report_space, UInt64)
    report_scratch = LocalMath.Field(report_space, UInt64)
    ownership_scratch = LocalMath.Field(
        accepted.ownership.space, eltype(accepted.ownership))
    state_scratch = map(accepted.accepted_state_fields) do field
        LocalMath.Field(field.space, eltype(field))
    end
    external_gate = LocalMath.Field(gate_space, Bool)
    initial_gate = LocalMath.Field(gate_space, Bool)
    refreshed_gate = LocalMath.Field(gate_space, Bool)
    terminal_gate = LocalMath.Field(gate_space, Bool)
    relationship_groups = _checkerboard_relationship_groups(
        accepted, relationships, accepted.relationship_bank_fields,
        terminal_gate)
    tracker_groups = _checkerboard_tracker_groups(
        accepted, tracker_plan, tracker_state, terminal_gate,
        owner_capacity)

    gate_identity = LocalMath.IdentityRelation(gate_space)
    owner_relation = LocalMath.IndexRelation(
        accepted.owners => owners_space; optional = true)
    status_relation = LocalMath.RuntimeRelation(
        accepted.source_space => status_space;
        degree_bound = 1, key_type = Int32)
    report_route = LocalMath.RuntimeRelation(
        accepted.source_space => report_space;
        degree_bound = 5, key_type = Int32)

    gate_stage(destination, label) = LocalMath.Stage(
        gate_space,
        (gate = LocalMath.Access(external_gate, gate_identity),),
        (LocalMath.Publication((LocalMath.FieldPublication(
            destination, gate_identity,
            LocalMath.PublicationValue(:gate)),), LocalMath.Unique(Bool)),),
        LocalMath.Evaluator(_CheckerboardAcceptedGateCopy()),
        LocalMath.Control(),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__; label),
    )
    failure_stage = LocalMath.Stage(
        accepted.source_space,
        (
            dispositions = LocalMath.Access(
                accepted.disposition, accepted.identity; required = true),
            semantic_ids = LocalMath.Access(
                accepted.semantic, accepted.identity; required = true),
        ),
        (LocalMath.Publication((LocalMath.FieldPublication(
            status, status_relation,
            LocalMath.PublicationValue(:status)),), LocalMath.Resolve(
                Int32, ProgramStatus;
                lower = Int32(1), upper = typemax(Int32),
                onempty = LocalMath.PreserveEmpty())),),
        LocalMath.Evaluator(_CheckerboardAcceptanceEvaluator(),
            (accepted.batch_size, accepted.mcs)),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = initial_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_acceptance_failure),
    )
    resolve_stage = LocalMath.Stage(
        accepted.source_space,
        (
            owners = LocalMath.Access(
                accepted.owners, accepted.identity; required = true),
            priorities = LocalMath.Access(
                accepted.qualified_priority, accepted.identity;
                required = true),
            semantics = LocalMath.Access(
                accepted.semantic, accepted.identity; required = true),
            dispositions = LocalMath.Access(
                accepted.disposition, accepted.identity; required = true),
        ),
        (LocalMath.Publication((LocalMath.FieldPublication(
            winners, owner_relation,
            LocalMath.PublicationValue(:winner)),), LocalMath.Resolve(
                UInt32, Int32; maximum = 2,
                direction = LocalMath.ArgMax(),
                tie = LocalMath.TieMin{Int32}(),
                lower = UInt32(0), upper = typemax(UInt32),
                onempty = LocalMath.FillEmpty(typemax(Int32)))),),
        LocalMath.Evaluator(
            _CheckerboardClaimResolver(), (accepted.batch_size,)),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = refreshed_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_owner_resolution),
    )
    conjunction_stage = LocalMath.Stage(
        accepted.source_space,
        (
            owners = LocalMath.Access(
                accepted.owners, accepted.identity; required = true),
            winners = LocalMath.Access(winners, owner_relation),
            semantics = LocalMath.Access(
                accepted.semantic, accepted.identity; required = true),
            dispositions = LocalMath.Access(
                accepted.disposition, accepted.identity; required = true),
        ),
        (LocalMath.Publication((LocalMath.FieldPublication(
            accepted.disposition, accepted.identity,
            LocalMath.PublicationValue(:disposition)),),
            LocalMath.Unique(UInt8;
                coverage = LocalMath.PartialCoverage(),
                onempty = LocalMath.PreserveEmpty())),),
        LocalMath.Evaluator(
            _CheckerboardClaimConjunction(), (accepted.batch_size,)),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = refreshed_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_mutual_maxima),
    )
    accepted_validation_stage = if isempty(accepted.accepted_site_terms) &&
            isempty(accepted.accepted_relationship_terms)
        nothing
    else
        evaluator = _CheckerboardAcceptedValidation(
            accepted.accepted_site_terms,
            accepted.accepted_relationship_terms,
            Int32(length(accepted.source_space)))
        base_reads = (
            semantic = LocalMath.Access(
                accepted.semantic, accepted.identity; required = true),
            disposition = LocalMath.Access(
                accepted.disposition, accepted.identity; required = true),
        )
        site_reads = NamedTuple{keys(accepted.accepted_site_fields)}(map(
            field -> LocalMath.Access(
                field, accepted.identity; required = true),
            values(accepted.accepted_site_fields)))
        relationship_reads = NamedTuple{
            keys(accepted.accepted_relationship_fields)}(map(
                field -> LocalMath.Access(
                    field, accepted.identity; required = true),
                values(accepted.accepted_relationship_fields)))
        maximum_ordinal = maximum((
            term.descriptor_ordinal for term in (
                accepted.accepted_site_terms...,
                accepted.accepted_relationship_terms...)); init = Int32(1))
        LocalMath.Stage(
            accepted.source_space,
            merge(base_reads, site_reads, relationship_reads),
            (LocalMath.Publication((LocalMath.FieldPublication(
                status, status_relation,
                LocalMath.PublicationValue(:status)),), LocalMath.Resolve(
                    Int32, ProgramStatus;
                    lower = Int32(1),
                    upper = Int32(length(accepted.source_space) *
                        maximum_ordinal),
                    onempty = LocalMath.PreserveEmpty())),),
            LocalMath.Evaluator(evaluator, (accepted.mcs,)),
            LocalMath.Control(;
                prefix = accepted.batch_size, gate = refreshed_gate),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_accepted_validation),
        )
    end
    accepted_state_stage = let
        state_port_names = ntuple(
            index -> Symbol(:accepted_state_, index),
            length(accepted.accepted_state_handles))
        port_names = (:accepted_ownership, state_port_names...)
        target_relation = LocalMath.IndexRelation(
            accepted.target => accepted.lattice_space; optional = false)
        state_read_names = ntuple(
            index -> Symbol(:state_, index),
            length(accepted.accepted_state_fields))
        state_reads = NamedTuple{state_read_names}(map(
            field -> LocalMath.Access(
                field, target_relation; required = true),
            accepted.accepted_state_fields))
        evaluation_reads = NamedTuple{keys(accepted.accepted_site_fields)}(map(
            field -> LocalMath.Access(
                field, accepted.identity; required = true),
            values(accepted.accepted_site_fields)))
        reads = merge((
            disposition = LocalMath.Access(
                accepted.disposition, accepted.identity; required = true),
            owners = LocalMath.Access(
                accepted.owners, accepted.identity; required = true),
        ), evaluation_reads, state_reads)
        state_publications = map(
            state_scratch, state_port_names) do field, name
            LocalMath.Publication((LocalMath.FieldPublication(
                field, target_relation,
                LocalMath.PublicationValue(name)),), LocalMath.Unique(
                    eltype(field);
                    coverage = LocalMath.PartialCoverage(),
                    onempty = LocalMath.PreserveEmpty()))
        end
        ownership_publication = LocalMath.Publication((
            LocalMath.FieldPublication(
                ownership_scratch, target_relation,
                LocalMath.PublicationValue(:accepted_ownership)),),
            LocalMath.Unique(Int32;
                coverage = LocalMath.PartialCoverage(),
                onempty = LocalMath.PreserveEmpty()))
        publications = (ownership_publication, state_publications...)
        evaluator = _checkerboard_accepted_state_publication(
            Val(port_names),
            Val(!isempty(accepted.accepted_site_terms)),
            accepted.accepted_state_handles,
            accepted.accepted_site_terms,
            accepted.ownership_change_handles)
        LocalMath.Stage(
            accepted.source_space,
            reads,
            publications,
            LocalMath.Evaluator(evaluator),
            LocalMath.Control(;
                prefix = accepted.batch_size, gate = terminal_gate),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :checkerboard_accepted_state_publication),
        )
    end
    report_stage = LocalMath.Stage(
        accepted.source_space,
        (dispositions = LocalMath.Access(
            accepted.disposition, accepted.identity; required = true),),
        (LocalMath.Publication((LocalMath.FieldPublication(
            report_scratch, report_route,
            LocalMath.PublicationValue(:counts)),), LocalMath.Reduce(
                UInt64, +; maximum = 5,
                seed = LocalMath.ExistingSeed(),
                order = LocalMath.CanonicalLeftFold())),),
        LocalMath.Evaluator(
            _CheckerboardReportEvaluator(), (accepted.batch_size,)),
        LocalMath.Control(;
            prefix = accepted.batch_size, gate = terminal_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_report_counts),
    )
    validation_laws = accepted_validation_stage === nothing ? () :
        (LocalMath.LocalLaw(accepted_validation_stage),)
    state_laws = (LocalMath.LocalLaw(accepted_state_stage),)
    state_initialization_laws = (
        _checkerboard_field_copy_law(accepted.ownership, ownership_scratch,
            terminal_gate, :checkerboard_ownership_shadow_initialize),
        Tuple(_checkerboard_field_copy_law(source, scratch, terminal_gate,
                Symbol(:checkerboard_state_shadow_initialize_, index))
            for (index, (source, scratch)) in enumerate(zip(
                accepted.accepted_state_fields, state_scratch)))...,
    )
    state_commit_laws = (
        _checkerboard_field_copy_law(ownership_scratch, accepted.ownership,
            terminal_gate, :checkerboard_ownership_commit),
        Tuple(_checkerboard_field_copy_law(scratch, destination, terminal_gate,
                Symbol(:checkerboard_state_commit_, index))
            for (index, (scratch, destination)) in enumerate(zip(
                state_scratch, accepted.accepted_state_fields)))...,
    )
    report_initialization_law = _checkerboard_field_copy_law(
        report, report_scratch, terminal_gate, :checkerboard_report_initialize)
    report_commit_law = _checkerboard_field_copy_law(
        report_scratch, report, terminal_gate, :checkerboard_report_commit)
    relationship_laws = map(group -> group.law, relationship_groups)
    relationship_commit_laws = _checkerboard_relationship_commit_laws(
        relationship_groups, terminal_gate)
    tracker_laws = (
        (law for group in tracker_groups
            for law in (group.initialization_laws..., group.laws...))...,)
    tracker_commit_laws = (
        (law for group in tracker_groups for law in group.commit_laws)...,)
    selection_laws = (
        validation_laws...,
        LocalMath.LocalLaw(gate_stage(
            terminal_gate, :checkerboard_selection_terminal_gate)),
        relationship_laws...,
        tracker_laws...,
        state_initialization_laws...,
        state_laws...,
        report_initialization_law,
    )
    law = LocalMath.sequence(
        accepted.law,
        LocalMath.LocalLaw(gate_stage(
            initial_gate, :checkerboard_selection_initial_gate)),
        LocalMath.LocalLaw(failure_stage),
        LocalMath.LocalLaw(gate_stage(
            refreshed_gate, :checkerboard_selection_refreshed_gate)),
        LocalMath.LocalLaw(resolve_stage),
        LocalMath.LocalLaw(conjunction_stage),
        selection_laws...,
        LocalMath.LocalLaw(report_stage),
        state_commit_laws...,
        tracker_commit_laws...,
        relationship_commit_laws...,
        report_commit_law,
    )
    return merge(accepted, (;
        law, winners, status, report, report_scratch,
        ownership_scratch, state_scratch, external_gate,
        initial_gate, refreshed_gate, terminal_gate, owner_relation,
        status_relation, report_route, relationship_groups, tracker_groups))
end

function _checkerboard_color_schedule(
        plan::CheckerboardPlan, color::Integer)
    1 <= color <= Int(plan.color_count) || throw(ArgumentError(
        "checkerboard color is outside its prepared range"))
    maximum_batch = Int(plan.maximum_color_size)
    first_index = Int(@inbounds plan.color_offsets[color])
    stop_index = Int(@inbounds plan.color_offsets[color + 1]) - 1
    count = stop_index - first_index + 1
    schedule = zeros(Int32, maximum_batch)
    count > 0 && copyto!(schedule, 1, plan.sites, first_index, count)
    return schedule, Int32(count)
end

_checkerboard_state_field_bindings(::Tuple{}, ::Tuple{}, state) = ()
function _checkerboard_state_field_bindings(fields::Tuple, handles::Tuple, state)
    return (
        first(fields) => state_block(
            state.descriptor_state, first(handles)).values,
        _checkerboard_state_field_bindings(
            Base.tail(fields), Base.tail(handles), state)...,
    )
end


_checkerboard_parameter_binding(::Nothing, state, extent) = ()
function _checkerboard_parameter_binding(
        field::LocalMath.Field{T}, state, extent,
    ) where {T<:Tuple}
    N = fieldcount(T)
    N > 0 && all(==(fieldtype(T, 1)), fieldtypes(T)) || throw(ArgumentError(
        "checkerboard parameter fields require a nonempty homogeneous tuple"))
    return (field => _checkerboard_parameter_view(
        state.parameters, Val(N), extent),)
end

_checkerboard_storage_zero(::Type{T}) where {T} = zero(T)
@generated function _checkerboard_storage_zero(::Type{T}) where {T<:Tuple}
    types = fieldtypes(T)
    return Expr(:tuple, (
        :(_checkerboard_storage_zero($(types[index])))
        for index in eachindex(types))...)
end
_checkerboard_storage_zero(field::LocalMath.Field) =
    _checkerboard_storage_zero(eltype(field))

_checkerboard_contact_bindings(::Nothing) = ()
function _checkerboard_contact_bindings(contact)
    return (
        contact.owners => LocalMath.Allocate(_checkerboard_storage_zero(contact.owners)),
        contact.sites => LocalMath.Allocate(_checkerboard_storage_zero(contact.sites)),
        contact.kinds => LocalMath.Allocate(_checkerboard_storage_zero(contact.kinds)),
        contact.reverse_owners => LocalMath.Allocate(
            _checkerboard_storage_zero(contact.reverse_owners)),
        contact.reverse_sites => LocalMath.Allocate(
            _checkerboard_storage_zero(contact.reverse_sites)),
        contact.reverse_kinds => LocalMath.Allocate(
            _checkerboard_storage_zero(contact.reverse_kinds)),
    )
end

_checkerboard_tracker_source_bindings(
    ::Tuple{}, ::Tuple{}, state,
) = ()
function _checkerboard_tracker_source_bindings(
        fields::Tuple, keys::Tuple, state)
    return (
        first(fields) => tracker_values(
            state.program.tracker_plan, state.trackers, first(keys)),
        _checkerboard_tracker_source_bindings(
            Base.tail(fields), Base.tail(keys), state)...,
    )
end

_checkerboard_moment_source_bindings(::Tuple{}, ::Nothing, state) = ()
function _checkerboard_moment_source_bindings(
        fields::Tuple, descriptor::CellMomentsTracker, state)
    descriptors = state.program.tracker_plan.descriptors
    index = findfirst(==(descriptor), descriptors)
    index === nothing && throw(ArgumentError(
        "checkerboard cell-moment descriptor is unavailable at binding"))
    value = state.trackers.values[index]
    value isa CellMomentsState || throw(ArgumentError(
        "checkerboard cell-moment storage has an incompatible schema"))
    dimensions = size(value.first, 1)
    length(fields) == dimensions + dimensions * dimensions || throw(
        ArgumentError(
            "checkerboard cell-moment fields disagree with their descriptor"))
    return Tuple(map(enumerate(fields)) do indexed
        component, field = indexed
        storage = component <= dimensions ?
            view(value.first, component, :) :
            view(value.second, component - dimensions, :)
        field => storage
    end)
end

_checkerboard_relationship_science_bindings(::Tuple{}, state) = ()
function _checkerboard_relationship_science_bindings(
        declarations::Tuple, state)
    declaration = first(declarations)
    # Preparation retains the validated host location while binding the
    # corresponding packed arrays from the selected runtime bank.
    location = declaration.state_location
    bank = state.relationships.banks[Int(location.bank)]
    bank isa PackedRelationshipBank || throw(ArgumentError(
        "checkerboard relationship science binding requires packed storage"))
    degree = declaration.maximum_degree
    owner_count = length(declaration.cell_volumes.space)
    incident_offset = Int(declaration.incident_offset)
    incident_slots = reshape(Int32[
        incident_offset + (owner - 1) * degree + lane - 1
        for lane in 1:degree, owner in 1:owner_count
    ], degree, owner_count)
    execution_incident_slots = _checkerboard_similar(
        state.parameters, Int32, size(incident_slots)...
    )
    copyto!(execution_incident_slots, incident_slots)
    return (
        declaration.incident_slot_relation =>
            LocalMath.Allocate(execution_incident_slots),
        declaration.edge_keys =>
            LocalMath.Allocate(_checkerboard_storage_zero(
                declaration.edge_keys)),
        declaration.endpoint_keys =>
            LocalMath.Allocate(_checkerboard_storage_zero(
                declaration.endpoint_keys)),
        _checkerboard_relationship_science_bindings(
            Base.tail(declarations), state)...,
    )
end

function _checkerboard_accepted_site_binding(fields::NamedTuple, workspace)
    return map(values(fields)) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
end

function _checkerboard_accepted_relationship_binding(fields::NamedTuple)
    return map(values(fields)) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
end

_checkerboard_relationship_group_bindings(::Tuple{}, state) = ()
function _checkerboard_relationship_group_bindings(groups::Tuple, state)
    group = first(groups)
    bank = state.relationships.banks[Int(group.bank_index)]
    bank isa PackedRelationshipBank || throw(ArgumentError(
        "checkerboard relationship binding requires packed banks"))
    endpoint_bindings = map(values(group.endpoint_fields)) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
    lane_count = length(group.terms)
    endpoints = reshape(Int32[
        fld(item - 1, lane_count) + 1
        for item in 1:length(group.request_space)],
        1, length(group.request_space))
    execution_endpoints = _checkerboard_similar(
        state.parameters, Int32, size(endpoints)...
    )
    copyto!(execution_endpoints, endpoints)
    return (
        group.candidate_relation => execution_endpoints,
        endpoint_bindings...,
        map(field -> field => LocalMath.Allocate(
                _checkerboard_storage_zero(field)),
            values(group.shadow_fields))...,
        _checkerboard_relationship_group_bindings(Base.tail(groups), state)...,
    )
end

_checkerboard_tracker_storage(value, ::Val{:self}) = value
_checkerboard_tracker_storage(value, ::Val{:first}) = value.first
_checkerboard_tracker_storage(value, ::Val{:second}) = value.second
_checkerboard_tracker_storage(value, column::Int32) = view(value, :, Int(column))

_checkerboard_tracker_group_bindings(::Tuple{}, state) = ()
function _checkerboard_tracker_group_bindings(groups::Tuple, state)
    group = first(groups)
    value = state.trackers.values[Int(group.tracker_index)]
    source_bindings = Tuple(field => (path isa Int32 ?
            _checkerboard_tracker_storage(value, path) :
            _checkerboard_tracker_storage(value, Val(path)))
        for (field, path) in zip(group.source_fields, group.paths)
        if path !== nothing)
    scratch_bindings = map(group.fields) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
    return (
        source_bindings...,
        scratch_bindings...,
        _checkerboard_tracker_group_bindings(Base.tail(groups), state)...,
    )
end

function _checkerboard_extinction_policies(plan, kind_count::Integer)
    forbid = plan isa LifecycleExecutionPlan ? Tuple(plan.forbid_extinction) :
        ntuple(_ -> false, kind_count)
    length(forbid) >= kind_count || throw(ArgumentError(
        "checkerboard lifecycle extinction policy omits a declared kind"))
    retire = ntuple(length(forbid)) do kind
        _has_due_zero_volume_retirement(plan, Int16(kind))
    end
    return forbid, retire
end

function _checkerboard_relationship_bank_bindings(declaration, state)
    required = Any[]
    add_required!(field) = begin
        any(existing -> existing == field, required) || push!(required, field)
        nothing
    end
    for science in declaration.relationship_science
        add_required!(science.fields.active)
        add_required!(science.fields.endpoint_a)
        add_required!(science.fields.endpoint_b)
        foreach(add_required!, science.fields.payload)
        add_required!(science.incident_edges_field)
    end
    for group in declaration.relationship_groups
        foreach(add_required!, values(group.live_fields))
    end
    bindings = Pair[]
    for (bank_index, authority) in enumerate(
            declaration.relationship_bank_fields)
        storage = _packed_relationship_science(
            state.relationships.banks[bank_index])
        keys(authority) == keys(storage) || throw(ArgumentError(
            "checkerboard relationship authority disagrees with packed storage"))
        for (field, array) in zip(values(authority), values(storage))
            any(required_field -> required_field == field, required) &&
                push!(bindings, field => array)
        end
    end
    return Tuple(bindings)
end

function _checkerboard_color_bindings(
        declaration, workspace, state, schedule, gate,
    )
    maximum_batch = length(declaration.source_space)
    sites = StructArrays.StructArray{NTuple{2,Int32}}((
        workspace.target_sites, workspace.source_sites))
    owners = StructArrays.StructArray{NTuple{2,Int32}}((
        workspace.old_owners, workspace.new_owners))
    volumes = tracker_values(
        state.program.tracker_plan, state.trackers, Val(:cell_volume))
    parameter_binding = _checkerboard_parameter_binding(
        declaration.science_parameters, state, maximum_batch)
    state_bindings = _checkerboard_state_field_bindings(
        declaration.state_fields, declaration.state_handles, state)
    contact_bindings = _checkerboard_contact_bindings(declaration.contact)
    tracker_source_bindings = _checkerboard_tracker_source_bindings(
        declaration.tracker_source_fields, declaration.tracker_keys, state)
    moment_source_bindings = _checkerboard_moment_source_bindings(
        declaration.moment_source_fields,
        declaration.moment_descriptor, state)
    relationship_science_bindings =
        _checkerboard_relationship_science_bindings(
            declaration.relationship_science, state)
    relationship_bank_bindings =
        _checkerboard_relationship_bank_bindings(declaration, state)
    tracker_pair_bindings = map(declaration.tracker_pair_fields) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
    accepted_site_binding = _checkerboard_accepted_site_binding(
        declaration.accepted_site_fields, workspace)
    accepted_relationship_binding =
        _checkerboard_accepted_relationship_binding(
            declaration.accepted_relationship_fields)
    relationship_group_bindings =
        _checkerboard_relationship_group_bindings(
            declaration.relationship_groups, state)
    tracker_group_bindings = _checkerboard_tracker_group_bindings(
        declaration.tracker_groups, state)
    state_scratch_bindings = map(declaration.state_scratch) do field
        field => LocalMath.Allocate(_checkerboard_storage_zero(field))
    end
    generation_binding = isempty(declaration.relationship_groups) ? () :
        (declaration.cell_generations => state.cell_generations,)
    return (
        declaration.target_options => LocalMath.Allocate(schedule),
        declaration.target => LocalMath.Allocate(zero(Int32)),
        declaration.sites => sites,
        declaration.semantic => workspace.semantic_ids,
        declaration.priority => workspace.priorities,
        declaration.ownership => state.ownership,
        declaration.owners => owners,
        declaration.actionable => LocalMath.Allocate(false),
        declaration.cell_kinds => state.cell_kinds,
        declaration.cell_volumes => volumes,
        generation_binding...,
        declaration.kinds => LocalMath.Allocate(
            _checkerboard_storage_zero(declaration.kinds)),
        declaration.volumes => LocalMath.Allocate(
            _checkerboard_storage_zero(declaration.volumes)),
        parameter_binding...,
        state_bindings...,
        contact_bindings...,
        tracker_source_bindings...,
        moment_source_bindings...,
        relationship_bank_bindings...,
        relationship_science_bindings...,
        tracker_pair_bindings...,
        accepted_site_binding...,
        accepted_relationship_binding...,
        relationship_group_bindings...,
        tracker_group_bindings...,
        declaration.evaluation.delta_h => LocalMath.Allocate(
            zero(eltype(declaration.evaluation.delta_h))),
        declaration.evaluation.drive_energy => LocalMath.Allocate(
            zero(eltype(declaration.evaluation.drive_energy))),
        declaration.evaluation.drive_log_bias => LocalMath.Allocate(
            zero(eltype(declaration.evaluation.drive_log_bias))),
        declaration.evaluation.kinetic_modifier => LocalMath.Allocate(
            zero(eltype(declaration.evaluation.kinetic_modifier))),
        declaration.evaluation.constraints_allowed => LocalMath.Allocate(true),
        declaration.disposition => workspace.dispositions,
        declaration.failure_code => LocalMath.Allocate(zero(UInt8)),
        declaration.failure_identity => LocalMath.Allocate(zero(Int32)),
        declaration.winners => LocalMath.Allocate(typemax(Int32)),
        declaration.status => state.program_status,
        declaration.report => workspace.report,
        declaration.report_scratch => LocalMath.Allocate(zero(UInt64)),
        declaration.ownership_scratch => LocalMath.Allocate(zero(Int32)),
        state_scratch_bindings...,
        declaration.external_gate => gate,
        declaration.initial_gate => LocalMath.Allocate(false),
        declaration.refreshed_gate => LocalMath.Allocate(false),
        declaration.terminal_gate => LocalMath.Allocate(false),
    )
end

function _prepare_checkerboard_color_laws(
        workspace,
        checkerboard::CheckerboardPlan,
        proposal_offsets::AbstractMatrix{<:Integer},
        descriptor_plan::DescriptorExecutionPlan,
        stage_plan::StageExecutionPlan,
        ownership_change_handles::Tuple,
        relationship_schemas::RelationshipStorage,
        kind_count::Integer,
        queue_capacity::Integer,
    )
    queue_capacity > 0 || throw(ArgumentError(
        "checkerboard color preparation requires positive queue capacity"))
    state = workspace.state
    plan = state.program.checkerboard_plan
    validated = _validate_checkerboard_stage_program_preparation(
        workspace, plan, checkerboard, proposal_offsets,
        "host and adapted checkerboard compiler inputs disagree")
    T = eltype(state.parameters)
    kind_count = Int(kind_count)
    kind_count > 0 || throw(ArgumentError(
        "checkerboard compiler requires at least one cell kind"))
    cell_capacity = length(state.cell_kinds)
    forbid, retire = state.program.extinction_policies
    scientific = _checkerboard_scientific_declaration(
        checkerboard, proposal_offsets,
        state.seed, state.replica, state.repeat,
        descriptor_plan, stage_plan, state.program.tracker_plan,
        ownership_change_handles,
        relationship_schemas, state.relationships,
        state.program.temperature.parameter_index,
        cell_capacity, T)
    accepted = _checkerboard_acceptance_declaration(
        scientific, state.program.temperature, forbid, retire,
        state.seed, state.replica, state.repeat)
    declaration = _checkerboard_color_declaration(
        accepted, cell_capacity, state.relationships,
        state.program.tracker_plan, state.trackers)
    gates = (
        _checkerboard_open_gate(workspace.state),
        _checkerboard_open_gate(workspace.alternate_state),
    )
    schedules = ntuple(Int(checkerboard.color_count)) do color
        _checkerboard_color_schedule(checkerboard, color)
    end
    schedule_arrays = map(first, schedules)
    combined_schedule = collect(zip(schedule_arrays...))
    execution_schedule = _checkerboard_similar(
        state.parameters, eltype(combined_schedule), length(combined_schedule)
    )
    copyto!(execution_schedule, combined_schedule)
    prepare_bank = function (bank, gate)
        return LocalMath.prepare(
            declaration.law,
            _checkerboard_color_bindings(
                declaration, workspace, bank, execution_schedule, gate)...;
            backend = validated.backend, lease_capacity = queue_capacity,
            dependency_arity = 1)
    end
    prepared = (
        prepare_bank(workspace.state, gates[1]),
        prepare_bank(workspace.alternate_state, gates[2]),
    )
    typeof(prepared[1]) === typeof(prepared[2]) || throw(ArgumentError(
        "checkerboard banks produced different PreparedPlan types"))
    batch_sizes = Int32[last(schedule) for schedule in schedules]
    return (; declaration, prepared, batch_sizes, gates,
        backend = validated.backend)
end
const _CHECKERBOARD_RELATIONSHIP_MAXIMUM_DEGREE = Int32(16)
const _CHECKERBOARD_RELATIONSHIP_INCIDENT_WRITES = 32

@inline function _checkerboard_endpoint_value(value::Integer)
    value isa Bool && return (false, Int32(0))
    typemin(Int32) <= value <= typemax(Int32) || return (false, Int32(0))
    return (true, Int32(value))
end

@inline function _checkerboard_endpoint_value(value::AbstractFloat)
    isfinite(value) || return (false, Int32(0))
    lower = typeof(value)(-2147483648)
    upper = typeof(value)(2147483648)
    lower <= value < upper || return (false, Int32(0))
    trunc(value) == value || return (false, Int32(0))
    return (true, Int32(value))
end

@inline _checkerboard_endpoint_value(_value) = (false, Int32(0))

@inline function _checkerboard_payload_value(prototype::T, value) where {
        T <: AbstractFloat,
    }
    value isa Real || return (false, zero(T))
    converted = T(value)
    return (isfinite(converted), converted)
end

@generated function _checkerboard_payload_values(
        prototype::P, values::V
    ) where {P <: Tuple, V <: Tuple}
    fieldcount(P) == fieldcount(V) || return :((false, prototype))
    assignments = Expr[]
    valid = Expr(:call, :(&),
        [Symbol(:valid_, i) for i in 1:fieldcount(P)]...)
    converted = Expr(:tuple,
        [Symbol(:converted_, i) for i in 1:fieldcount(P)]...)
    for index in 1:fieldcount(P)
        push!(assignments, quote
            $(Symbol(:valid_, index)), $(Symbol(:converted_, index)) =
                _checkerboard_payload_value(
                    getfield(prototype, $index), getfield(values, $index))
        end)
    end
    isempty(assignments) && return :((true, ()))
    return Expr(:block, assignments..., :(($valid, $converted)))
end

@inline _checkerboard_fold_edge_offset(reads, slot::Int32) =
    @inbounds reads.edge_offsets[slot]
@inline _checkerboard_fold_endpoint_offset(reads, slot::Int32) =
    @inbounds reads.endpoint_offsets[slot]
@inline _checkerboard_fold_incident_offset(reads, slot::Int32) =
    @inbounds reads.incident_offsets[slot]
@inline _checkerboard_fold_maximum_degree(reads, slot::Int32) =
    @inbounds reads.maximum_degrees[slot]

@inline function _checkerboard_fold_degree_index(
        reads, slot::Int32, endpoint::Int32)
    return _checkerboard_fold_endpoint_offset(reads, slot) + endpoint - Int32(1)
end

@inline function _checkerboard_fold_incident_index(
        reads, slot::Int32, endpoint::Int32, position::Int32)
    return _checkerboard_fold_incident_offset(reads, slot) +
        (endpoint - Int32(1)) * _checkerboard_fold_maximum_degree(reads, slot) +
        position - Int32(1)
end

@inline function _checkerboard_fold_relationship_edge(
        state, reads, slot::Int32, a::Int32, b::Int32)
    degree_a = Int32(@inbounds state.degree[
        _checkerboard_fold_degree_index(reads, slot, a)])
    degree_b = Int32(@inbounds state.degree[
        _checkerboard_fold_degree_index(reads, slot, b)])
    endpoint = degree_a <= degree_b ? a : b
    degree = min(degree_a, degree_b)
    edge_offset = _checkerboard_fold_edge_offset(reads, slot)
    for position in Int32(1):degree
        edge = @inbounds state.incident_edges[
            _checkerboard_fold_incident_index(
                reads, slot, endpoint, position)]
        edge > 0 || continue
        flat_edge = edge_offset + edge - Int32(1)
        if @inbounds(state.active[flat_edge]) &&
                @inbounds(state.endpoint_a[flat_edge]) == a &&
                @inbounds(state.endpoint_b[flat_edge]) == b
            return edge
        end
    end
    return Int32(0)
end

@inline function _checkerboard_fold_available_edge(
        state, reads, slot::Int32)
    offset = _checkerboard_fold_edge_offset(reads, slot)
    count = @inbounds reads.edge_counts[slot]
    for edge in Int32(1):count
        @inbounds(state.active[offset + edge - Int32(1)]) || return edge
    end
    return Int32(0)
end

@inline function _checkerboard_fold_insertion_position(
        state, reads, slot::Int32, endpoint::Int32, edge::Int32,
        degree::Int32)
    position = degree + Int32(1)
    while position > Int32(1)
        previous = @inbounds state.incident_edges[
            _checkerboard_fold_incident_index(
                reads, slot, endpoint, position - Int32(1))]
        previous > edge || break
        position -= Int32(1)
    end
    return position
end

@inline function _checkerboard_fold_incident_write(
        state, reads, slot::Int32, endpoint_a::Int32,
        position_a::Int32, degree_a::Int32, endpoint_b::Int32,
        position_b::Int32, degree_b::Int32, edge::Int32, lane::Int32)
    count_a = degree_a - position_a + Int32(2)
    if lane <= count_a
        position = position_a + lane - Int32(1)
        destination = _checkerboard_fold_incident_index(
            reads, slot, endpoint_a, position)
        value = position == position_a ? edge : @inbounds(
            state.incident_edges[destination - Int32(1)])
        return (destination, value)
    end
    local_lane = lane - count_a
    count_b = degree_b - position_b + Int32(2)
    if local_lane <= count_b
        position = position_b + local_lane - Int32(1)
        destination = _checkerboard_fold_incident_index(
            reads, slot, endpoint_b, position)
        value = position == position_b ? edge : @inbounds(
            state.incident_edges[destination - Int32(1)])
        return (destination, value)
    end
    return (Int32(1), Int32(0))
end

struct _CheckerboardAcceptedGateCopy end
@inline function (::_CheckerboardAcceptedGateCopy)(
        item::Int32, reads, parameters,
    )
    return (gate = LocalMath.UniqueValue(
        something(@inbounds(reads[1][1].value))),)
end
