# Final executable storage reports and CorePotts boundary validation.

function _storage_report(program::CorePotts.CompilerSPI.CompiledPottsProgram)
    site_count = prod(program.shape)
    return (
        shape = program.shape,
        site_count,
        max_cells = program.lifecycle_plan isa CorePotts.CompilerSPI.LifecycleExecutionPlan ?
            Int(program.lifecycle_plan.cell_capacity) : nothing,
        ownership = (element = Int32, count = site_count),
        cell_kind = (
            element = Int16,
            count = program.lifecycle_plan isa CorePotts.CompilerSPI.LifecycleExecutionPlan ?
                Int(program.lifecycle_plan.cell_capacity) : nothing,
        ),
        cell_generation = (
            element = UInt32,
            count = program.lifecycle_plan isa CorePotts.CompilerSPI.LifecycleExecutionPlan ?
                Int(program.lifecycle_plan.cell_capacity) : nothing,
        ),
        volume = Int,
        declared_state_blocks = Tuple(
            CorePotts.CompilerSPI.state_schema_metadata(entry.schema)
            for entry in program.descriptor_plan.state_layout.entries
        ),
        relationships = Tuple((
            capacity = schema.capacity,
            maximum_degree = schema.maximum_degree,
            endpoint = Int32,
            generation = UInt32,
            payload = eltype(program.parameter_defaults),
        ) for schema in program.relationships),
    )
end

function _workspace_report(program::CorePotts.CompilerSPI.CompiledPottsProgram)
    lifecycle = CorePotts.CompilerSPI.lifecycle_workspace_layout(
        program.lifecycle_plan, prod(program.shape)
    )
    return (
        stage_site_scratch = sum((
            1
            for group in program.stage_plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa Union{
                CorePotts.CompilerSPI.SiteAssignmentEffect,
                CorePotts.CompilerSPI.IteratedSiteAssignmentEffect,
            }
        ); init = 0) * prod(program.shape),
        stage_model_scratch = sum((
            1
            for group in program.stage_plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa CorePotts.CompilerSPI.ModelAssignmentEffect
        ); init = 0),
        proposal_scratch = length(program.descriptor_plan.source_table),
        relationship_requests = sum(
            schema.capacity for schema in program.relationships; init = 0
        ),
        relationship_lifecycle_scratch =
            sum((
                program.relationships[Int(descriptor.effect.relationship_slot)].capacity
                for group in program.stage_plan.after_mcs
                for descriptor in group.instances
                if descriptor.effect isa Union{
                    CorePotts.CompilerSPI.RelationshipRemoveEffect,
                    CorePotts.CompilerSPI.RelationshipRetuneEffect,
                }
            ); init = 0),
        lifecycle,
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
