# Typed storage schemas, layouts, and extension protocols.

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

struct StateLayout{E <: AbstractVector}
    entries::E
end

struct WorkspaceLayout{E <: AbstractVector}
    entries::E
end

StateLayout(entries::Tuple) = StateLayout(StateEntry[entries...])
WorkspaceLayout(entries::Tuple) = WorkspaceLayout(WorkspaceEntry[entries...])

function _schema_layout_entries(
        schemas::AbstractVector,
        storage_class,
        handle_type,
        entry_type,
    )
    classes = Any[]
    for schema in schemas
        representation = storage_class(schema)
        any(isequal(representation), classes) ||
            push!(classes, representation)
    end
    sort!(classes; by = representation ->
        "type:" * string(parentmodule(representation)) * "." *
        string(representation)
    )
    banks = [
        only(findall(isequal(storage_class(schema)), classes))
        for schema in schemas
    ]
    order = sortperm(eachindex(schemas); by = index -> banks[index])
    counts = zeros(Int, length(classes))
    offsets = zeros(Int, length(classes))
    entries = entry_type[]
    for index in order
        schema = schemas[index]
        representation = storage_class(schema)
        bank = banks[index]
        counts[bank] += 1
        shape = schema.shape isa Tuple ? Tuple(Int.(schema.shape)) :
                (Int(schema.capacity),)
        handle = handle_type(
            representation,
            bank,
            counts[bank],
            offsets[bank] + 1,
            shape,
        )
        offsets[bank] += prod(shape)
        push!(entries, entry_type(handle, schema))
    end
    return entries
end

function StateLayout(schemas::AbstractVector{<:StateBlockSchema})
    return StateLayout(
        _schema_layout_entries(
            schemas,
            state_storage_class,
            StateHandle,
            StateEntry,
        )
    )
end

function WorkspaceLayout(schemas::AbstractVector{<:WorkspaceSchema})
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

struct BlockView{
        T,
        N,
        A <: AbstractArray{T},
    } <: AbstractArray{T, N}
    storage::A
    offset::Int32
    dimensions::NTuple{N, Int32}
end

BlockView(
    storage::AbstractArray{T}, offset::Integer, shape::NTuple{N, <:Integer}
) where {T, N} = BlockView{T, N, typeof(storage)}(
    storage, Int32(offset), Int32.(shape)
)

Base.IndexStyle(::Type{<:BlockView}) = IndexLinear()
Base.size(view::BlockView) = Tuple(Int.(view.dimensions))
Base.length(view::BlockView) = prod(size(view))
Base.parent(view::BlockView) = view.storage
Base.similar(::BlockView, ::Type{T}, dimensions::Dims) where {T} =
    Array{T}(undef, dimensions)

@inline function Base.getindex(view::BlockView, index::Int)
    @boundscheck checkbounds(view, index)
    return @inbounds view.storage[Int(view.offset) + index - 1]
end

@inline function Base.setindex!(view::BlockView, value, index::Int)
    @boundscheck checkbounds(view, index)
    @inbounds view.storage[Int(view.offset) + index - 1] = value
    return value
end

struct BlockBank{
        Representation <: AbstractStorageRepresentation,
        V <: AbstractArray,
    }
    values::V
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

struct AuxiliaryStateCheckpoint{E <: AbstractVector}
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
    return DenseStateBlock(BlockView(
        bank.values,
        Int(handle.location.offset),
        handle.location.shape,
    ))
end

@inline function workspace_block(
        workspaces::RuntimeWorkspaces,
        handle::WorkspaceHandle{Representation},
    ) where {Representation}
    bank = _representation_bank(workspaces.banks, Representation)
    return DenseWorkspaceBlock(BlockView(
        bank.values,
        Int(handle.location.offset),
        handle.location.shape,
    ))
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
