function _storage_report(program::CorePotts.CompiledPottsProgram)
    site_count = prod(program.shape)
    return (
        shape = program.shape,
        site_count,
        ownership = (element = Int32, count = site_count),
        cell_kind = Int16,
        volume = Int,
        activity = program.activity === nothing ? nothing :
                   (element = eltype(program.parameter_defaults), count = site_count),
        field = program.field === nothing ? nothing :
                (element = eltype(program.parameter_defaults), count = site_count),
        relationships = nothing,
    )
end

function _workspace_report(program::CorePotts.CompiledPottsProgram)
    return (
        field_scratch = program.field === nothing ? 0 : prod(program.shape),
        proposal_scratch = 0,
        relationship_requests = 0,
        live_state_allocated = false,
    )
end

function _assert_concrete_core_boundary(value; path = "program", seen = IdSet())
    value === nothing && return nothing
    value isa Union{
        Number, Symbol, String, Bool, DataType, Type, VersionNumber,
    } && return nothing
    value in seen && return nothing
    push!(seen, value)
    value isa Function && throw(ArgumentError(
        "host closure crossed the CorePotts boundary at $path"
    ))
    value isa AbstractPottsStatement && throw(ArgumentError(
        "symbolic statement crossed the CorePotts boundary at $path"
    ))
    _is_quantity(value) && throw(ArgumentError(
        "unit quantity crossed the CorePotts boundary at $path"
    ))
    if !(Symbolics.symbolic_type(value) isa
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

