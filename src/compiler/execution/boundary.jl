# Final executable storage reports and CorePotts boundary validation.

function _storage_report(program::CorePotts.CompiledPottsProgram)
    site_count = prod(program.shape)
    return (
        shape = program.shape,
        site_count,
        ownership = (element = Int32, count = site_count),
        cell_kind = Int16,
        cell_generation = UInt32,
        volume = Int,
        activity = program.activity === nothing ? nothing :
                   (element = eltype(program.parameter_defaults), count = site_count),
        field = program.field === nothing ? nothing :
                (element = eltype(program.parameter_defaults), count = site_count),
        history = program.history === nothing ? nothing : (
            element = eltype(program.parameter_defaults),
            depth = Int(program.history.depth),
            count = site_count * Int(program.history.depth),
        ),
        elongation = program.elongation === nothing ? nothing :
                     (moments = :recomputed_reference, dimension = length(program.shape)),
        relationships = program.relationships === nothing ? nothing : (
            capacity = program.relationships.capacity,
            maximum_degree = program.relationships.maximum_degree,
            endpoint = Int32,
            generation = UInt32,
            payload = eltype(program.parameter_defaults),
        ),
    )
end

function _workspace_report(program::CorePotts.CompiledPottsProgram)
    return (
        field_scratch = program.field === nothing ? 0 : prod(program.shape),
        proposal_scratch = length(program.descriptor_plan.source_table),
        relationship_requests = program.relationships === nothing ? 0 :
                                program.relationships.capacity,
        live_state_allocated = false,
    )
end

function _is_named_singleton_callable(value::Function)
    Base.issingletontype(typeof(value)) || return false
    return !startswith(String(nameof(value)), "#")
end

function _assert_concrete_core_boundary(value; path = "program", seen = IdSet())
    value === nothing && return nothing
    value isa Union{
        Number, Symbol, String, Bool, DataType, Type, VersionNumber,
    } && return nothing
    value in seen && return nothing
    push!(seen, value)
    value isa Function &&
        !_is_named_singleton_callable(value) &&
        throw(ArgumentError(
            "host closure crossed the CorePotts boundary at $path"
        ))
    value isa AbstractPottsStatement && throw(ArgumentError(
        "symbolic statement crossed the CorePotts boundary at $path"
    ))
    _is_quantity(value) && throw(ArgumentError(
        "unit quantity crossed the CorePotts boundary at $path"
    ))
    if !(SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic)
        throw(ArgumentError("Symbolics value crossed the CorePotts boundary at $path"))
    end
    if value isa AbstractArray || value isa Tuple || value isa NamedTuple
        for (index, item) in enumerate(value)
            _assert_concrete_core_boundary(
                item; path = "$path[$index]", seen
            )
        end
    elseif isstructtype(typeof(value))
        for field in fieldnames(typeof(value))
            _assert_concrete_core_boundary(
                getfield(value, field); path = "$path.$field", seen
            )
        end
    end
    return nothing
end
