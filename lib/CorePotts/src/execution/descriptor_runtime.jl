# Generic, mechanism-free evaluator, storage, and descriptor runtime boundary.

abstract type AbstractStaticExpression end
abstract type AbstractContextualOperation end

abstract type AbstractStorageRepresentation end

struct StateStorageRepresentation{
        ElementType,
        Dimensions,
        Layout,
        Adaptation,
    } <: AbstractStorageRepresentation end

struct WorkspaceStorageRepresentation{
        ContainerType,
        ElementType,
        Dimensions,
        Adaptation,
    } <: AbstractStorageRepresentation end

struct DefaultStateStorageRepresentation <: AbstractStorageRepresentation end
struct DefaultWorkspaceStorageRepresentation <: AbstractStorageRepresentation end

struct StateHandle{Representation <: AbstractStorageRepresentation}
    bank::Int32
    slot::Int32
    function StateHandle{Representation}(
            bank::Integer,
            slot::Integer,
        ) where {Representation <: AbstractStorageRepresentation}
        bank > 0 ||
            throw(ArgumentError("a state bank ordinal must be positive"))
        slot > 0 || throw(ArgumentError("a state handle slot must be positive"))
        new{Representation}(Int32(bank), Int32(slot))
    end
end

StateHandle{Representation}(slot::Integer) where {
    Representation <: AbstractStorageRepresentation,
} = StateHandle{Representation}(1, slot)
StateHandle(
    ::Type{Representation}, bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    StateHandle{Representation}(bank, slot)
StateHandle(slot::Integer) =
    StateHandle{DefaultStateStorageRepresentation}(1, slot)
StateHandle(bank::Integer, slot::Integer) =
    StateHandle{DefaultStateStorageRepresentation}(bank, slot)

struct WorkspaceHandle{Representation <: AbstractStorageRepresentation}
    bank::Int32
    slot::Int32
    function WorkspaceHandle{Representation}(
            bank::Integer,
            slot::Integer,
        ) where {Representation <: AbstractStorageRepresentation}
        bank > 0 ||
            throw(ArgumentError("a workspace bank ordinal must be positive"))
        slot > 0 ||
            throw(ArgumentError("a workspace handle slot must be positive"))
        new{Representation}(Int32(bank), Int32(slot))
    end
end

WorkspaceHandle{Representation}(slot::Integer) where {
    Representation <: AbstractStorageRepresentation,
} = WorkspaceHandle{Representation}(1, slot)
WorkspaceHandle(
    ::Type{Representation}, bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    WorkspaceHandle{Representation}(bank, slot)
WorkspaceHandle(slot::Integer) =
    WorkspaceHandle{DefaultWorkspaceStorageRepresentation}(1, slot)
WorkspaceHandle(bank::Integer, slot::Integer) =
    WorkspaceHandle{DefaultWorkspaceStorageRepresentation}(bank, slot)

handle_bank(handle::Union{StateHandle, WorkspaceHandle}) = handle.bank
handle_slot(handle::Union{StateHandle, WorkspaceHandle}) = handle.slot
handle_representation(
    ::StateHandle{Representation}
) where {Representation} = Representation
handle_representation(
    ::WorkspaceHandle{Representation}
) where {Representation} = Representation

function Base.getproperty(
        handle::Union{StateHandle, WorkspaceHandle}, name::Symbol
    )
    name === :index && return getfield(handle, :slot)
    return getfield(handle, name)
end

struct LiteralExpression{T} <: AbstractStaticExpression
    value::T
end

struct ParameterExpression{T <: AbstractFloat} <: AbstractStaticExpression
    default::T
    index::Int32
    function ParameterExpression(default::T, index::Integer = 0) where {
            T <: AbstractFloat,
        }
        0 <= index <= typemax(Int32) ||
            throw(ArgumentError("parameter expression index is out of range"))
        new{T}(default, Int32(index))
    end
end

struct ContextExpression{T <: AbstractContextualOperation} <: AbstractStaticExpression
    operation::T
end

struct StateExpression{H <: StateHandle} <: AbstractStaticExpression
    handle::H
end

struct OperationExpression{
        T,
        A <: Tuple,
    } <: AbstractStaticExpression
    operation::T
    arguments::A
end

OperationExpression(operation, arguments...) =
    OperationExpression(operation, arguments)

struct StaticEvaluator{E <: AbstractStaticExpression}
    expression::E
end

struct OrderedFold{F}
    operation::F
end

struct ContextOperation{Identity} <: AbstractContextualOperation end
struct ResourceOperation{Identity} <: AbstractContextualOperation end

function context_value end
function apply_resource_operation end
function operation_callable end
function state_value end
function workspace_value end
function evaluator_parameters end

for (identity, operation) in (
        :add => OrderedFold(+),
        :subtract => OrderedFold(-),
        :multiply => OrderedFold(*),
        :divide => OrderedFold(/),
        :power => (^),
        :maximum => OrderedFold(max),
        :minimum => OrderedFold(min),
        :less => (<),
        :less_equal => (<=),
        :greater => (>),
        :greater_equal => (>=),
        :equal => (==),
        :not_equal => (!=),
        :and => (&),
        :or => (|),
        :not => (!),
        :ifelse => ifelse,
        :absolute => abs,
        :exponential => exp,
        :logarithm => log,
        :square_root => sqrt,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        $operation :
        throw(ArgumentError("unsupported operation schema version $version"))
end

for identity in (
        :source_site,
        :target_site,
        :source_cell,
        :target_cell,
        :source_kind,
        :target_kind,
        :is_extension,
        :is_retraction,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        ContextOperation{$(QuoteNode(identity))}() :
        throw(ArgumentError("unsupported operation schema version $version"))
end

for identity in (
        :cell_volume,
        :cell_surface,
        :cell_center,
        :unwrapped_center,
        :distance,
        :contact_measure,
        :boundary_measure,
        :neighbor_count,
        :neighbor_sum,
        :neighbor_mean,
        :neighbor_geomean,
        :field_value,
        :field_gradient,
        :laplacian,
        :occupancy,
        :history_value,
        :linked,
        :endpoint_a,
        :endpoint_b,
        :degree,
        :edge_payload,
        :lag,
        :new_contact,
        :lost_contact,
        :draw,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        ResourceOperation{$(QuoteNode(identity))}() :
        throw(ArgumentError("unsupported operation schema version $version"))
end

@inline evaluate_expression(
    expression::LiteralExpression, context
) = expression.value

@inline function evaluate_expression(
        expression::ParameterExpression,
        context,
    )
    index = expression.index
    return index == 0 ? expression.default :
           @inbounds evaluator_parameters(context)[index]
end

@inline evaluate_expression(
    expression::ContextExpression, context
) = context_value(expression.operation, context)

@inline evaluate_expression(
    expression::StateExpression, context
) = expression.handle

@inline function evaluate_expression(
        expression::OperationExpression,
        context,
    )
    arguments = map(
        argument -> evaluate_expression(argument, context),
        expression.arguments,
    )
    return execute_operation(expression.operation, arguments, context)
end

@inline evaluate_static(evaluator::StaticEvaluator, context) =
    evaluate_expression(evaluator.expression, context)

@inline function _ordered_fold(operation, arguments::Tuple)
    length(arguments) == 1 && return operation(only(arguments))
    return foldl(operation, Base.tail(arguments); init = first(arguments))
end

@inline (fold::OrderedFold)(arguments::Tuple) =
    _ordered_fold(fold.operation, arguments)

@inline execute_operation(
    operation::AbstractContextualOperation, arguments::Tuple, context
) = operation(arguments, context)
@inline execute_operation(
    operation::OrderedFold, arguments::Tuple, context
) = operation(arguments)
@inline execute_operation(
    operation, arguments::Tuple, context
) = operation(arguments...)

@inline (
    operation::ContextOperation
)(arguments::Tuple, context) =
    context_value(operation, context)
@inline (
    operation::ResourceOperation
)(arguments::Tuple, context) =
    apply_resource_operation(operation, arguments, context)

struct EvaluatorProbeContext{P, V, S, W}
    parameters::P
    values::V
    states::S
    workspaces::W
end

EvaluatorProbeContext(parameters, values) =
    EvaluatorProbeContext(parameters, values, (), ())
EvaluatorProbeContext(parameters, values, states) =
    EvaluatorProbeContext(parameters, values, states, ())

@inline evaluator_parameters(context::EvaluatorProbeContext) =
    context.parameters

for identity in (
        :source_site,
        :target_site,
        :source_cell,
        :target_cell,
        :source_kind,
        :target_kind,
        :is_extension,
        :is_retraction,
    )
    @eval @inline context_value(
        ::ContextOperation{$(QuoteNode(identity))},
        context::EvaluatorProbeContext,
    ) = getproperty(context.values, $(QuoteNode(identity)))
end

@inline apply_resource_operation(
    ::ResourceOperation{:cell_volume},
    arguments,
    context::EvaluatorProbeContext,
) = @inbounds context.values.cell_volumes[only(arguments)]

@inline state_value(
    context::EvaluatorProbeContext,
    handle::StateHandle,
    site,
) = @inbounds context.states[Int(handle.index)][site]

@inline workspace_value(
    context::EvaluatorProbeContext,
    handle::WorkspaceHandle,
) = workspace_block(context.workspaces, handle).values

@kernel function evaluator_probe_kernel!(
        output,
        evaluator,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(output)
        @inbounds output[index] = evaluate_static(evaluator, context)
    end
end

@kernel function descriptor_probe_kernel!(
        output,
        descriptor,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(output)
        @inbounds output[index] = descriptor_evaluate_proposal(
            descriptor, context
        )
    end
end

struct QualifiedResourceIdentity{P <: Tuple}
    path::P
    name::Symbol
end

struct StateBlockSchema
    identity::QualifiedResourceIdentity
    version::VersionNumber
    domain::Symbol
    element_type::Any
    shape::Any
    capacity::Int
    layout::Symbol
    initialization::Symbol
    validation::Symbol
    persistence::Symbol
    lifecycle::Any
    read_policy::Symbol
    write_policy::Symbol
    adaptation::Symbol
    settled_export::Symbol
    checkpoint_codec::Symbol
    inspection::Symbol
    checkpoint::Bool
end

struct WorkspaceSchema
    identity::QualifiedResourceIdentity
    version::VersionNumber
    element_type::Any
    shape::Any
    capacity::Int
    container_type::Any
    initialization::Symbol
    lifetime::Symbol
    access::Symbol
    adaptation::Symbol
    inspection::Symbol
    shareable::Bool
end

struct StateEntry{H <: StateHandle, S}
    handle::H
    schema::S
end

struct WorkspaceEntry{H <: WorkspaceHandle, S}
    handle::H
    schema::S
end

struct StateLayout{E <: Tuple}
    entries::E
end

struct WorkspaceLayout{E <: Tuple}
    entries::E
end

function _schema_layout_entries(
        schemas::AbstractVector,
        storage_class,
        handle_type,
        entry_type,
    )
    classes = Any[]
    counts = Int[]
    entries = ()
    for schema in schemas
        representation = storage_class(schema)
        bank = findfirst(==(representation), classes)
        if bank === nothing
            push!(classes, representation)
            push!(counts, 0)
            bank = length(classes)
        end
        counts[bank] += 1
        handle = handle_type(representation, bank, counts[bank])
        entries = (entries..., entry_type(handle, schema))
    end
    return entries
end

function StateLayout(schemas::AbstractVector)
    return StateLayout(
        _schema_layout_entries(
            schemas,
            state_storage_class,
            StateHandle,
            StateEntry,
        )
    )
end

function WorkspaceLayout(schemas::AbstractVector)
    return WorkspaceLayout(
        _schema_layout_entries(
            schemas,
            workspace_storage_class,
            WorkspaceHandle,
            WorkspaceEntry,
        )
    )
end

function Base.getproperty(layout::StateLayout, name::Symbol)
    name === :schemas &&
        return map(entry -> entry.schema, getfield(layout, :entries))
    return getfield(layout, name)
end

function Base.getproperty(layout::WorkspaceLayout, name::Symbol)
    name === :schemas &&
        return map(entry -> entry.schema, getfield(layout, :entries))
    return getfield(layout, name)
end

struct DenseStateBlock{A <: AbstractArray}
    values::A
end

struct DenseWorkspaceBlock{A <: AbstractArray}
    values::A
end

struct BlockBank{
        Representation <: AbstractStorageRepresentation,
        B <: Tuple,
    }
    blocks::B
end

struct AuxiliaryState{B <: Tuple}
    banks::B
end

struct RuntimeWorkspaces{B <: Tuple}
    banks::B
end

struct StateCheckpointEntry{I, P}
    identity::I
    version::VersionNumber
    payload::P
end

struct AuxiliaryStateCheckpoint{E <: Tuple}
    entries::E
end

@generated function _representation_bank(
        banks::Banks,
        ::Type{Representation},
    ) where {
        Banks <: Tuple,
        Representation <: AbstractStorageRepresentation,
    }
    matches = findall(
        bank_type -> bank_type <: BlockBank{Representation},
        fieldtypes(Banks),
    )
    length(matches) == 1 || return :(throw(ArgumentError(
        "runtime storage does not contain exactly one bank for " *
        $(string(Representation))
    )))
    return :(getfield(banks, $(only(matches))))
end

@inline function state_block(
        state::AuxiliaryState,
        handle::StateHandle{Representation},
    ) where {Representation}
    bank = _representation_bank(state.banks, Representation)
    return @inbounds bank.blocks[Int(handle.slot)]
end

@inline function workspace_block(
        workspaces::RuntimeWorkspaces,
        handle::WorkspaceHandle{Representation},
    ) where {Representation}
    bank = _representation_bank(workspaces.banks, Representation)
    return @inbounds bank.blocks[Int(handle.slot)]
end

@inline state_value(
    context::EvaluatorProbeContext{P, V, S, W},
    handle::StateHandle,
    site,
) where {P, V, S <: AuxiliaryState, W} = @inbounds state_block(
    context.states, handle
).values[site]

function state_schema_metadata end
function state_storage_class end
function allocate_state_block end
function validate_state_block end
function adapt_state_block end
function settled_state_export end
function encode_state_checkpoint end
function reconstruct_state_block end
function inspect_state_block end

function workspace_schema_metadata end
function workspace_storage_class end
function allocate_workspace_block end
function reset_workspace! end
function adapt_workspace_block end
function inspect_workspace_block end

state_schema_metadata(schema::StateBlockSchema) = (
    identity = schema.identity,
    version = schema.version,
    domain = schema.domain,
    element_type = schema.element_type,
    shape = schema.shape,
    capacity = schema.capacity,
    layout = schema.layout,
    persistence = schema.persistence,
    lifecycle = schema.lifecycle,
    read_policy = schema.read_policy,
    write_policy = schema.write_policy,
    adaptation = schema.adaptation,
    settled_export = schema.settled_export,
    checkpoint_codec = schema.checkpoint_codec,
)

function state_storage_class(schema::StateBlockSchema)
    dimensions = schema.shape isa Tuple ? length(schema.shape) : 1
    return StateStorageRepresentation{
        schema.element_type,
        dimensions,
        schema.layout,
        schema.adaptation,
    }
end

function _dense_shape(schema)
    schema.shape isa Tuple &&
        all(dimension -> dimension isa Integer && dimension > 0, schema.shape) &&
        return Tuple(Int.(schema.shape))
    schema.capacity > 0 && return (schema.capacity,)
    throw(ArgumentError(
        "dense block $(schema.identity) has no concrete positive shape"
    ))
end

function allocate_state_block(
        schema::StateBlockSchema, initial = nothing
    )
    schema.initialization in (:provided_or_zero, :declared) ||
        throw(ArgumentError(
            "unsupported state initialization policy $(schema.initialization)"
        ))
    values = if initial === nothing
        zeros(schema.element_type, _dense_shape(schema))
    else
        converted = Array{schema.element_type}(initial)
        size(converted) == _dense_shape(schema) ||
            throw(ArgumentError(
                "initial state shape for $(schema.identity) is incompatible"
            ))
        converted
    end
    block = DenseStateBlock(values)
    validate_state_block(schema, block)
    return block
end

function validate_state_block(
        schema::StateBlockSchema, block::DenseStateBlock
    )
    size(block.values) == _dense_shape(schema) ||
        throw(ArgumentError("state block shape is incompatible with its schema"))
    eltype(block.values) === schema.element_type ||
        throw(ArgumentError("state block element type is incompatible"))
    if schema.validation === :shape_and_finite &&
            eltype(block.values) <: AbstractFloat
        all(isfinite, block.values) ||
            throw(ArgumentError("state block contains a nonfinite value"))
    elseif !(schema.validation in (:shape_and_finite, :prelaunch))
        throw(ArgumentError(
            "unsupported state validation policy $(schema.validation)"
        ))
    end
    return nothing
end

function adapt_state_block(
        to, schema::StateBlockSchema, block::DenseStateBlock
    )
    schema.adaptation === :adapt_storage ||
        throw(ArgumentError("unsupported state adaptation policy"))
    return DenseStateBlock(Adapt.adapt(to, block.values))
end

function settled_state_export(
        schema::StateBlockSchema, block::DenseStateBlock
    )
    schema.settled_export === :copy ||
        throw(ArgumentError("unsupported settled-state export policy"))
    return copy(block.values)
end

function encode_state_checkpoint(
        schema::StateBlockSchema, block::DenseStateBlock
    )
    schema.checkpoint_codec in (:logical_copy, :reconstruct_from_initial) ||
        throw(ArgumentError("unsupported state checkpoint codec"))
    return schema.checkpoint_codec === :logical_copy ?
           copy(block.values) : nothing
end

function reconstruct_state_block(
        schema::StateBlockSchema, payload
    )
    schema.checkpoint_codec === :logical_copy &&
        return allocate_state_block(schema, payload)
    schema.checkpoint_codec === :reconstruct_from_initial &&
        return allocate_state_block(schema)
    throw(ArgumentError("unsupported state checkpoint codec"))
end

inspect_state_block(
    schema::StateBlockSchema, block::Union{Nothing, DenseStateBlock}
) = merge(
    state_schema_metadata(schema),
    (
        allocated = block !== nothing,
        storage_type = block === nothing ? nothing : typeof(block.values),
    ),
)

workspace_schema_metadata(schema::WorkspaceSchema) = (
    identity = schema.identity,
    version = schema.version,
    element_type = schema.element_type,
    shape = schema.shape,
    capacity = schema.capacity,
    container_type = schema.container_type,
    initialization = schema.initialization,
    lifetime = schema.lifetime,
    access = schema.access,
    adaptation = schema.adaptation,
    shareable = schema.shareable,
)

function workspace_storage_class(schema::WorkspaceSchema)
    dimensions = schema.shape isa Tuple ? length(schema.shape) : 1
    return WorkspaceStorageRepresentation{
        schema.container_type,
        schema.element_type,
        dimensions,
        schema.adaptation,
    }
end

function allocate_workspace_block(schema::WorkspaceSchema)
    schema.container_type === Array ||
        throw(ArgumentError("unsupported workspace container type"))
    schema.initialization in (:zero, :zero_before_observe) ||
        throw(ArgumentError("unsupported workspace initialization policy"))
    return DenseWorkspaceBlock(
        zeros(schema.element_type, _dense_shape(schema))
    )
end

function reset_workspace!(
        schema::WorkspaceSchema,
        block::DenseWorkspaceBlock,
    )
    schema.initialization in (:zero, :zero_before_observe) ||
        throw(ArgumentError("unsupported workspace reset policy"))
    fill!(block.values, zero(eltype(block.values)))
    return block
end

function adapt_workspace_block(
        to, schema::WorkspaceSchema, block::DenseWorkspaceBlock
    )
    schema.adaptation === :adapt_storage ||
        throw(ArgumentError("unsupported workspace adaptation policy"))
    return DenseWorkspaceBlock(Adapt.adapt(to, block.values))
end

inspect_workspace_block(
    schema::WorkspaceSchema,
    block::Union{Nothing, DenseWorkspaceBlock},
) = merge(
    workspace_schema_metadata(schema),
    (
        allocated = block !== nothing,
        storage_type = block === nothing ? nothing : typeof(block.values),
    ),
)

function _assemble_block_banks(entries::Tuple, blocks::Tuple)
    isempty(entries) && return ()
    maximum_bank = maximum(
        Int(handle_bank(entry.handle)) for entry in entries
    )
    banks = ()
    for bank_index in 1:maximum_bank
        selected_pairs = Tuple(
            (entry, block)
            for (entry, block) in zip(entries, blocks)
            if handle_bank(entry.handle) == bank_index
        )
        isempty(selected_pairs) &&
            error("compiled block-bank ordinals must be contiguous")
        representation = handle_representation(
            first(selected_pairs)[1].handle
        )
        all(
            pair -> handle_representation(pair[1].handle) === representation,
            selected_pairs,
        ) || error("one physical bank contains multiple storage representations")
        selected = map(last, selected_pairs)
        banks = (
            banks...,
            BlockBank{representation, typeof(selected)}(selected),
        )
    end
    return banks
end

function allocate_auxiliary_state(
        layout::StateLayout,
        initial_values::Tuple = ntuple(
            _ -> nothing, length(layout.entries)
        ),
    )
    length(initial_values) == length(layout.entries) ||
        throw(ArgumentError("initial auxiliary-state tuple has the wrong length"))
    blocks = map(
        (entry, initial) ->
            allocate_state_block(entry.schema, initial),
        layout.entries,
        initial_values,
    )
    return AuxiliaryState(
        _assemble_block_banks(layout.entries, blocks)
    )
end

function allocate_runtime_workspaces(layout::WorkspaceLayout)
    blocks = map(
        entry -> allocate_workspace_block(entry.schema),
        layout.entries,
    )
    return RuntimeWorkspaces(
        _assemble_block_banks(layout.entries, blocks)
    )
end

function adapt_auxiliary_state(
        to, layout::StateLayout, state::AuxiliaryState
    )
    blocks = map(layout.entries) do entry
        adapt_state_block(
            to, entry.schema, state_block(state, entry.handle)
        )
    end
    return AuxiliaryState(
        _assemble_block_banks(layout.entries, blocks)
    )
end

function adapt_runtime_workspaces(
        to,
        layout::WorkspaceLayout,
        workspaces::RuntimeWorkspaces,
    )
    blocks = map(layout.entries) do entry
        adapt_workspace_block(
            to,
            entry.schema,
            workspace_block(workspaces, entry.handle),
        )
    end
    return RuntimeWorkspaces(
        _assemble_block_banks(layout.entries, blocks)
    )
end

settled_state_export(
    layout::StateLayout, state::AuxiliaryState
) = map(layout.entries) do entry
    settled_state_export(
        entry.schema, state_block(state, entry.handle)
    )
end

function encode_auxiliary_state_checkpoint(
        layout::StateLayout, state::AuxiliaryState
    )
    entries = map(layout.entries) do entry
        StateCheckpointEntry(
            entry.schema.identity,
            entry.schema.version,
            encode_state_checkpoint(
                entry.schema, state_block(state, entry.handle)
            ),
        )
    end
    return AuxiliaryStateCheckpoint(entries)
end

function reconstruct_auxiliary_state(
        layout::StateLayout,
        checkpoint::AuxiliaryStateCheckpoint,
    )
    length(layout.entries) == length(checkpoint.entries) ||
        throw(ArgumentError(
            "auxiliary-state checkpoint entry count is incompatible"
        ))
    blocks = map(layout.entries, checkpoint.entries) do entry, encoded
        encoded.identity == entry.schema.identity &&
            encoded.version == entry.schema.version ||
            throw(ArgumentError(
                "auxiliary-state checkpoint schema is incompatible"
            ))
        reconstruct_state_block(entry.schema, encoded.payload)
    end
    return AuxiliaryState(
        _assemble_block_banks(layout.entries, blocks)
    )
end

inspect_auxiliary_state(
    layout::StateLayout, state::Union{Nothing, AuxiliaryState} = nothing
) = map(layout.entries) do entry
    block = state === nothing ? nothing :
            state_block(state, entry.handle)
    merge(
        (handle = entry.handle,),
        inspect_state_block(entry.schema, block),
    )
end

inspect_runtime_workspaces(
    layout::WorkspaceLayout,
    workspaces::Union{Nothing, RuntimeWorkspaces} = nothing,
) = map(layout.entries) do entry
    block = workspaces === nothing ? nothing :
            workspace_block(workspaces, entry.handle)
    merge(
        (handle = entry.handle,),
        inspect_workspace_block(entry.schema, block),
    )
end

function reset_runtime_workspaces!(
        layout::WorkspaceLayout,
        workspaces::RuntimeWorkspaces,
    )
    for entry in layout.entries
        reset_workspace!(
            entry.schema,
            workspace_block(workspaces, entry.handle),
        )
    end
    return workspaces
end

abstract type AbstractFootprint end
struct EmptyFootprint <: AbstractFootprint end
struct ProposalContextFootprint <: AbstractFootprint end
struct OwnerFootprint <: AbstractFootprint end
struct FiniteSpatialFootprint{O} <: AbstractFootprint
    offsets::O
end
struct IncidentRelationshipFootprint <: AbstractFootprint
    maximum_degree::Int32
end
struct FootprintUnion{F <: Tuple} <: AbstractFootprint
    footprints::F
end

struct ResourceAccess{R, W, F <: AbstractFootprint}
    reads::R
    writes::W
    footprint::F
end

struct DescriptorSupport
    sequential::Bool
    checkerboard::Bool
    cpu::Bool
    gpu::Bool
    reason_code::UInt16
end

DescriptorSupport(
    sequential::Bool,
    checkerboard::Bool,
    cpu::Bool,
    gpu::Bool,
    reason_code::Integer = 0,
) = DescriptorSupport(
    sequential,
    checkerboard,
    cpu,
    gpu,
    UInt16(reason_code),
)

function descriptor_state_requirements end
function descriptor_workspace_requirements end
function descriptor_resource_access end
function descriptor_stage end
function descriptor_role end
function descriptor_dependencies end
function descriptor_support end
function descriptor_evaluate_proposal end
function descriptor_emit_requests! end
function descriptor_apply_stage! end
function descriptor_adapt end
function descriptor_evaluator_node_count end
function descriptor_source_handle end
function descriptor_checkpoint_policy end
function descriptor_checkpoint_encode end
function descriptor_checkpoint_reconstruct end
function descriptor_checkpoint end
function descriptor_inspection end
function descriptor_payload_adapt end
function descriptor_payload_checkpoint_encode end
function descriptor_payload_checkpoint_reconstruct end
function descriptor_payload_inspection end

struct EmptyDescriptorPayload end

descriptor_payload_adapt(to, payload) = payload
descriptor_payload_checkpoint_encode(::EmptyDescriptorPayload) = nothing
descriptor_payload_checkpoint_reconstruct(
    payload::EmptyDescriptorPayload, ::Nothing
) = payload
descriptor_payload_inspection(::EmptyDescriptorPayload) = NamedTuple()

struct ProposalDescriptor{
        E <: StaticEvaluator,
        A <: ResourceAccess,
        S,
        H <: Tuple,
        W <: Tuple,
        R,
        P,
    }
    evaluator::E
    access::A
    support::S
    state_handles::H
    workspace_handles::W
    role::R
    source_handle::Int32
    payload::P
end

function ProposalDescriptor(
        evaluator::E,
        access::A,
        support::S,
        state_handles::H,
        workspace_handles::W,
        role::R,
        source_handle::Integer,
        payload::P,
    ) where {
        E <: StaticEvaluator,
        A <: ResourceAccess,
        S,
        H <: Tuple,
        W <: Tuple,
        R,
        P,
    }
    source_handle > 0 ||
        throw(ArgumentError("a descriptor source handle must be positive"))
    return ProposalDescriptor{E, A, S, H, W, R, P}(
        evaluator,
        access,
        support,
        state_handles,
        workspace_handles,
        role,
        Int32(source_handle),
        payload,
    )
end

ProposalDescriptor(
    evaluator::StaticEvaluator,
    access::ResourceAccess,
    support,
    state_handles::Tuple,
    workspace_handles::Tuple,
    role,
    source_handle::Integer,
) = ProposalDescriptor(
    evaluator,
    access,
    support,
    state_handles,
    workspace_handles,
    role,
    source_handle,
    EmptyDescriptorPayload(),
)

ProposalDescriptor(
    evaluator::StaticEvaluator,
    access::ResourceAccess,
    support,
    source_handle::Integer,
) = ProposalDescriptor(
    evaluator,
    access,
    support,
    (),
    (),
    ProposalEnergyRole(),
    source_handle,
    EmptyDescriptorPayload(),
)

abstract type AbstractProposalRole end
struct ProposalEnergyRole <: AbstractProposalRole end
struct ProposalDriveRole <: AbstractProposalRole end
struct ProposalConstraintRole <: AbstractProposalRole end
struct ProposalModifierRole <: AbstractProposalRole end

descriptor_state_requirements(descriptor::ProposalDescriptor) =
    descriptor.state_handles
descriptor_workspace_requirements(descriptor::ProposalDescriptor) =
    descriptor.workspace_handles
descriptor_resource_access(descriptor::ProposalDescriptor) = descriptor.access
descriptor_stage(::ProposalDescriptor) = :proposal
descriptor_role(descriptor::ProposalDescriptor) = descriptor.role
descriptor_dependencies(::ProposalDescriptor) = ()
descriptor_support(descriptor::ProposalDescriptor) = descriptor.support
@inline descriptor_evaluate_proposal(descriptor::ProposalDescriptor, context) =
    evaluate_static(descriptor.evaluator, context)
function descriptor_adapt(to, descriptor::ProposalDescriptor)
    payload = descriptor_payload_adapt(to, descriptor.payload)
    return ProposalDescriptor(
        descriptor.evaluator,
        descriptor.access,
        descriptor.support,
        descriptor.state_handles,
        descriptor.workspace_handles,
        descriptor.role,
        descriptor.source_handle,
        payload,
    )
end
descriptor_evaluator_node_count(descriptor::ProposalDescriptor) =
    evaluator_node_count(descriptor.evaluator)
descriptor_source_handle(descriptor::ProposalDescriptor) =
    descriptor.source_handle
descriptor_checkpoint_policy(::ProposalDescriptor) =
    :reconstruct_from_executable
descriptor_checkpoint_encode(descriptor::ProposalDescriptor) =
    descriptor_payload_checkpoint_encode(descriptor.payload)
descriptor_checkpoint_reconstruct(
    descriptor::ProposalDescriptor, payload
) = ProposalDescriptor(
    descriptor.evaluator,
    descriptor.access,
    descriptor.support,
    descriptor.state_handles,
    descriptor.workspace_handles,
    descriptor.role,
    descriptor.source_handle,
    descriptor_payload_checkpoint_reconstruct(
        descriptor.payload, payload
    ),
)
descriptor_checkpoint(descriptor::ProposalDescriptor) = (
    policy = descriptor_checkpoint_policy(descriptor),
    payload = descriptor_checkpoint_encode(descriptor),
)
descriptor_inspection(descriptor::ProposalDescriptor) = (
    source_handle = descriptor.source_handle,
    evaluator = nameof(typeof(descriptor.evaluator.expression)),
    stage = :proposal,
    role = nameof(typeof(descriptor.role)),
    state_handles = descriptor.state_handles,
    workspace_handles = descriptor.workspace_handles,
    payload = descriptor_payload_inspection(descriptor.payload),
)

struct DescriptorKernelStrategy{D, E, F, R, K} end

struct DescriptorLaunch{
        S,
        D,
        I <: AbstractVector{D},
        H <: Tuple,
        W <: Tuple,
    }
    strategy::S
    instances::I
    state_handles::H
    workspace_handles::W
end

struct DescriptorGroup{L, M}
    launch::L
    split::M
end

descriptor_launch(group::DescriptorGroup) = group.launch

struct ParameterDomainConstraint{E <: StaticEvaluator}
    evaluator::E
    predicate::UInt8
    source_handle::Int32
end

struct ConstraintGroup{C, V <: AbstractVector{C}}
    instances::V
end

struct DescriptorExecutionPlan{
        G <: Tuple,
        C <: Tuple,
        S <: AbstractVector,
    }
    groups::G
    state_layout::StateLayout
    workspace_layout::WorkspaceLayout
    constraints::C
    source_table::S
    occurrence_count::Int32
    fingerprint::String
end

Adapt.@adapt_structure LiteralExpression
Adapt.@adapt_structure ParameterExpression
Adapt.@adapt_structure ContextExpression
Adapt.@adapt_structure StateExpression
Adapt.@adapt_structure OperationExpression
Adapt.@adapt_structure StaticEvaluator
Adapt.@adapt_structure EvaluatorProbeContext
Adapt.@adapt_structure ResourceAccess
Adapt.@adapt_structure ProposalDescriptor
Adapt.@adapt_structure DenseStateBlock
Adapt.@adapt_structure DenseWorkspaceBlock
function Adapt.adapt_structure(
        to,
        bank::BlockBank{Representation},
    ) where {Representation}
    blocks = Adapt.adapt(to, bank.blocks)
    return BlockBank{Representation, typeof(blocks)}(blocks)
end
Adapt.@adapt_structure AuxiliaryState
Adapt.@adapt_structure RuntimeWorkspaces
Adapt.@adapt_structure DescriptorLaunch
Adapt.@adapt_structure ParameterDomainConstraint
Adapt.@adapt_structure ConstraintGroup

function adapt_descriptor_launch(to, group::DescriptorGroup)
    launch = descriptor_launch(group)
    adapted_descriptors = map(
        descriptor -> descriptor_adapt(to, descriptor),
        launch.instances,
    )
    adapted_instances = Adapt.adapt(to, adapted_descriptors)
    return DescriptorLaunch(
        launch.strategy,
        adapted_instances,
        launch.state_handles,
        launch.workspace_handles,
    )
end

@kernel function descriptor_group_probe_kernel!(
        output,
        launch,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(launch.instances)
        @inbounds output[index] = descriptor_evaluate_proposal(
            launch.instances[index], context
        )
    end
end

@inline function _constraint_passes(value, predicate::UInt8)
    predicate == 0x01 && return value > zero(value)
    predicate == 0x02 && return value >= zero(value)
    predicate == 0x03 && return value === true
    return false
end

function validate_parameters(plan::DescriptorExecutionPlan, parameters)
    context = EvaluatorProbeContext(parameters, NamedTuple())
    for group in plan.constraints
        for constraint in group.instances
            value = evaluate_static(constraint.evaluator, context)
            _constraint_passes(value, constraint.predicate) || throw(
                DomainError(
                    value,
                    "runtime parameter constraint failed for source handle " *
                    string(constraint.source_handle),
                ),
            )
        end
    end
    return nothing
end

function descriptor_plan_report(plan::DescriptorExecutionPlan)
    return (
        occurrences = Int(plan.occurrence_count),
        groups = length(plan.groups),
        instances = Tuple(
            length(group.launch.instances) for group in plan.groups
        ),
        evaluator_nodes = Tuple(
            descriptor_evaluator_node_count(
                first(group.launch.instances)
            )
            for group in plan.groups
        ),
        descriptor_inspections = Tuple(
            [
                merge(
                    (
                        qualified_source = plan.source_table[
                            descriptor_source_handle(descriptor)
                        ],
                    ),
                    descriptor_inspection(descriptor),
                )
                for descriptor in group.launch.instances
            ]
            for group in plan.groups
        ),
        specializations = length(plan.groups),
        state_blocks = length(plan.state_layout.schemas),
        workspaces = length(plan.workspace_layout.schemas),
        validation_groups = length(plan.constraints),
        group_splits = Tuple(group.split for group in plan.groups),
        kernel_families = Tuple(
            nameof(typeof(group.launch.strategy)) for group in plan.groups
        ),
        fingerprint = plan.fingerprint,
    )
end

_expression_node_count(::Union{LiteralExpression, ParameterExpression,
                               ContextExpression, StateExpression}) = 1
_expression_node_count(expression::OperationExpression) =
    1 + sum(_expression_node_count, expression.arguments; init = 0)
evaluator_node_count(evaluator::StaticEvaluator) =
    _expression_node_count(evaluator.expression)
