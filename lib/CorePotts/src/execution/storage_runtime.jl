# Mechanism-free state/workspace allocation, adaptation, and logical codecs.

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

function _assemble_block_banks(entries, blocks)
    isempty(entries) && return ()
    maximum_bank = maximum(
        Int(handle_bank(entry.handle)) for entry in entries
    )
    banks = ()
    for bank_index in 1:maximum_bank
        selected_pairs = [
            (entry, block)
            for (entry, block) in zip(entries, blocks)
            if handle_bank(entry.handle) == bank_index
        ]
        isempty(selected_pairs) &&
            error("compiled block-bank ordinals must be contiguous")
        representation = handle_representation(
            first(selected_pairs)[1].handle
        )
        all(
            pair -> handle_representation(pair[1].handle) === representation,
            selected_pairs,
        ) || error("one physical bank contains multiple storage representations")
        total = sum(length(last(pair).values) for pair in selected_pairs)
        element_type = eltype(first(selected_pairs)[2].values)
        values = Vector{element_type}(undef, total)
        expected_offset = 1
        for (entry, block) in selected_pairs
            offset = Int(handle_offset(entry.handle))
            offset == expected_offset || error(
                "compiled block locations must be contiguous within a bank"
            )
            source = vec(block.values)
            copyto!(values, offset, source, 1, length(source))
            expected_offset += length(source)
        end
        banks = (
            banks...,
            BlockBank{representation, typeof(values)}(values),
        )
    end
    return banks
end

"""Allocate and initialize all compiler-declared auxiliary-state blocks."""
function allocate_auxiliary_state(
        layout::StateLayout,
        initial_values = fill(nothing, length(layout.entries)),
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

@inline function _copy_state_bank(
        bank::BlockBank{Representation},
    ) where {Representation}
    values = copy(bank.values)
    return BlockBank{Representation, typeof(values)}(values)
end

"""Return an independent copy of validated auxiliary scientific state."""
function copy_auxiliary_state(::StateLayout, state::AuxiliaryState)
    banks = map(_copy_state_bank, state.banks)
    return AuxiliaryState(banks)
end

function copy_auxiliary_state(state::AuxiliaryState)
    banks = map(_copy_state_bank, state.banks)
    return AuxiliaryState(banks)
end

@inline _copyto_auxiliary_banks!(::Tuple{}, ::Tuple{}) = nothing
@inline function _copyto_auxiliary_banks!(destination::Tuple, source::Tuple)
    copyto!(first(destination).values, first(source).values)
    return _copyto_auxiliary_banks!(Base.tail(destination), Base.tail(source))
end

function _require_auxiliary_copy_compatible(
        destination::AuxiliaryState, source::AuxiliaryState
    )
    typeof(destination.banks) === typeof(source.banks) || throw(ArgumentError(
        "auxiliary states have incompatible physical layouts or element types"
    ))
    for (destination_bank, source_bank) in zip(
            destination.banks, source.banks
        )
        axes(destination_bank.values) == axes(source_bank.values) || throw(
            ArgumentError("auxiliary states have incompatible bank shapes")
        )
    end
    return destination
end

function _validate_auxiliary_state_candidate(
        layout::StateLayout,
        expected::AuxiliaryState,
        candidate::AuxiliaryState,
    )
    _require_auxiliary_copy_compatible(expected, candidate)
    for entry in layout.entries
        validate_state_block(entry.schema, state_block(candidate, entry.handle))
    end
    return candidate
end

function copyto_auxiliary_state!(
        destination::AuxiliaryState, source::AuxiliaryState
    )
    _require_auxiliary_copy_compatible(destination, source)
    _copyto_auxiliary_banks!(destination.banks, source.banks)
    return destination
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
    banks = map(bank -> Adapt.adapt(to, bank), state.banks)
    return AuxiliaryState(banks)
end

function adapt_runtime_workspaces(
        to,
        layout::WorkspaceLayout,
        workspaces::RuntimeWorkspaces,
    )
    banks = map(bank -> Adapt.adapt(to, bank), workspaces.banks)
    return RuntimeWorkspaces(banks)
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
