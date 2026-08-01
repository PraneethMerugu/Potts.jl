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
        declared_state_blocks = Tuple(
            CorePotts.state_schema_metadata(entry.schema)
            for entry in program.descriptor_plan.state_layout.entries
        ),
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
        stage_site_scratch = sum((
            1
            for group in program.stage_plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa Union{
                CorePotts.SiteAssignmentEffect,
                CorePotts.IteratedSiteAssignmentEffect,
            }
        ); init = 0) * prod(program.shape),
        proposal_scratch = length(program.descriptor_plan.source_table),
        relationship_requests = program.relationships === nothing ? 0 :
                                program.relationships.capacity,
        relationship_lifecycle_scratch =
            program.relationships === nothing ? 0 :
            sum((
                1
                for group in program.stage_plan.after_mcs
                for descriptor in group.instances
                if descriptor.effect isa CorePotts.RelationshipRemoveEffect
            ); init = 0) * program.relationships.capacity,
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
