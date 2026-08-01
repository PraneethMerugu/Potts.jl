# Compiled manifests, external I/O, initial values, and time contracts.

_manifest_identity(identity::QualifiedStatementID) = (
    path = identity.path,
    local_id = Symbol(identity.local_id),
)

function _manifest_symbol(value)
    value isa AbstractPottsStatement && return Symbol(statement_id(value))
    name = _try_symbolic_name(value)
    name === nothing && return Symbol(string(value))
    return name
end

function _compiled_statement_manifest(completed::PottsSystem)
    return NamedTuple[
        (
            identity = _manifest_identity(record.identity),
            kind = record.kind,
            schema_version = record.schema_version,
            source = record.source isa SourceLocation ? (
                file = record.source.file,
                line = record.source.line,
                module_name = record.source.module_name,
            ) : nothing,
            provenance = record.provenance,
            result_type = record.result_type isa Type ?
                          nameof(record.result_type) : record.result_type,
            shape = record.shape,
            units = record.units,
            reference_conversion = record.reference_conversion,
            reads = Tuple(_manifest_symbol(value) for value in record.reads),
            writes = Tuple(_manifest_symbol(value) for value in record.writes),
            ownership = record.ownership,
            persistence = record.persistence,
            resources = record.resources,
            effect = nameof(typeof(record.effect)),
            bound = (
                maximum = record.bound.maximum,
                basis = record.bound.basis,
            ),
            transaction_identity = record.transaction_identity === nothing ?
                                   nothing :
                                   _manifest_identity(record.transaction_identity),
            lifecycle = record.lifecycle,
            random_operations = Tuple(
                (
                    identity = operation.identity,
                    family = operation.family,
                    reserved = operation.reserved,
                )
                for operation in record.random_operations
            ),
            phase = record.phase === nothing ? nothing : nameof(typeof(record.phase)),
            ordering_dependencies = Tuple(string.(record.ordering_dependencies)),
            engine_admission = Tuple(
                (
                    engine = admission.engine,
                    admitted = admission.admitted,
                    reason = admission.reason,
                )
                for admission in record.engine_admission
            ),
            lowering_identity = record.lowering_identity,
        )
        for record in inspect(completed, Statements())
    ]
end

function _compiled_external_io(
        completed::PottsSystem,
        manifest::ParameterManifest,
        states,
        observations,
        shape,
        ::Type{T},
    ) where {T <: AbstractFloat}
    entries = NamedTuple[]
    endpoints = Set{Symbol}()
    input_names = Set(
        _symbolic_name(value; context = "external input identity")
        for value in ModelingToolkitBase.inputs(completed)
    )
    output_names = Set(
        _symbolic_name(value; context = "external output identity")
        for value in ModelingToolkitBase.outputs(completed)
    )
    overlap = intersect(input_names, output_names)
    isempty(overlap) || throw(ArgumentError(
        "external identities cannot be both input and output: " *
        join(string.(sort!(collect(overlap))), ", ")
    ))
    for (direction, values) in (
            :input => ModelingToolkitBase.inputs(completed),
            :output => ModelingToolkitBase.outputs(completed),
        )
        for value in values
            key = _symbolic_name(value; context = "external IO identity")
            parameter_index = _parameter_index(manifest, value)
            state_index = findfirst(
                entry -> entry.key === key || entry.name === key, states
            )
            observation_index = findfirst(entry -> entry.name === key, observations)
            builtin = key === :ownership ? :ownership : nothing
            if direction === :input &&
                    (observation_index !== nothing || builtin !== nothing)
                throw(ArgumentError(
                    "external input `$key` is not a mutable input authority"
                ))
            end
            if direction === :input && state_index !== nothing
                runtime_writers = Tuple(
                    record.identity
                    for record in inspect(completed, Statements())
                    if !(record.effect isa PureRead) &&
                       any(
                           write -> _manifest_symbol(write) in
                                    (key, states[state_index].name),
                           record.writes,
                       )
                )
                isempty(runtime_writers) || throw(ArgumentError(
                    "external input `$key` is also written by Potts statement" *
                    (length(runtime_writers) == 1 ? " " : "s ") *
                    join(string.(runtime_writers), ", ")
                ))
            end
            if direction === :output && parameter_index !== nothing
                throw(ArgumentError(
                    "runtime parameter `$key` is an input, not a settled output"
                ))
            end
            parameter_index === nothing && state_index === nothing &&
                observation_index === nothing && builtin === nothing &&
                throw(ArgumentError(
                    "external IO `$key` is not a compiled parameter, state, " *
                    "observation, or logical ownership output"
                ))
            parameter = parameter_index === nothing ? nothing :
                        manifest[parameter_index]
            state = state_index === nothing ? nothing : states[state_index]
            observation = observation_index === nothing ?
                          nothing : observations[observation_index]
            value_shape = if builtin === :ownership
                shape
            elseif state !== nothing && state.shape isa Tuple
                state.shape
            elseif observation !== nothing && observation.kind === :state_export
                shape
            else
                ()
            end
            descriptor = parameter !== nothing ? parameter.unit :
                         state !== nothing ? state.unit : nothing
            unit = descriptor === nothing ? nothing : (
                name = descriptor.name,
                dimension = descriptor.dimension,
                scale = descriptor.scale,
            )
            element_type = builtin === :ownership ? Int32 : T
            endpoint_hash = _sha256_hex(
                "potts-external-endpoint-v1", key, direction
            )
            endpoint = Symbol("potts_", first(endpoint_hash, 20))
            endpoint in endpoints && throw(ArgumentError(
                "external IO endpoint collision for `$key`"
            ))
            push!(endpoints, endpoint)
            push!(entries, (
                identity = key,
                endpoint,
                direction,
                access = direction === :input ? :read : :write,
                element_type,
                shape = value_shape,
                unit,
                ownership = :process,
                persistence = :required,
                update_law = :replace,
                residency = :host,
                codec = :canonical_v1,
                interval_behavior = direction === :input ? :frozen : :published,
                cadence = :whole_mcs,
                parameter_index,
                state_index,
                observation_index,
                builtin,
                source = parameter !== nothing ? :parameter :
                         state !== nothing && state.role === :activity ? :activity :
                         state !== nothing && state.role === :field ? :field :
                         state !== nothing ? state.name :
                         observation !== nothing ? observation.name : builtin,
            ))
        end
    end
    sort!(entries; by = entry -> (entry.direction, String(entry.identity)))
    return Tuple(entries)
end

function _compiled_state_initial(
        completed::PottsSystem,
        statement,
        manifest::ParameterManifest,
        ::Type{T},
    ) where {T <: AbstractFloat}
    arguments = _statement_arguments(statement)
    declared = arguments.initial
    variable = arguments.variable
    initial_conditions = ModelingToolkitBase.initial_conditions(completed)
    has_system_initial = haskey(initial_conditions, variable)
    if has_system_initial && declared !== nothing &&
            !isequal(initial_conditions[variable], declared)
        throw(ArgumentError(
            "state `$(statement_id(statement))` has conflicting declaration and " *
            "PottsSystem initial conditions"
        ))
    end
    value = has_system_initial ? initial_conditions[variable] : declared
    value === nothing && (value = zero(T))
    reference = _reference_for(manifest.reference_units, value)
    converted = T(_numeric_value(value, reference))
    isfinite(converted) ||
        throw(ArgumentError("state `$(statement_id(statement))` initial value must be finite"))
    return converted, reference
end

function _compiled_state_manifest(
        completed::PottsSystem,
        statements,
        activity_reference,
        manifest::ParameterManifest,
        state_layout::CorePotts.StateLayout,
        shape,
        ::Type{T},
    ) where {T <: AbstractFloat}
    result = NamedTuple[]
    for statement in statements
        statement isa Union{
            SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
        } || continue
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) || continue
        role = statement isa FieldState ? :field :
               statement isa HistoryState ? :history :
               statement isa SiteState &&
               isequal(arguments.variable, activity_reference) ? :activity : :stored
        storage = statement isa Union{SiteState, FieldState} ? :site :
                  statement isa CellState ? :cell :
                  statement isa MediumState ? :medium :
                  statement isa ModelState ? :model : :history
        initial, unit = _compiled_state_initial(
            completed, statement, manifest, T
        )
        state_shape = storage === :site ? shape :
                      storage === :cell ? :cells :
                      storage === :history ? (
                          shape...,
                          Int(_numeric_value(_statement_option(statement, :depth, 1))),
                      ) : ()
        matching_entries = filter(
            entry -> entry.schema.identity.name === Symbol(statement_id(statement)),
            state_layout.entries,
        )
        length(matching_entries) == 1 || throw(ArgumentError(
            "compiled state `$(statement_id(statement))` does not resolve to exactly " *
            "one canonical state-layout entry"
        ))
        layout_entry = only(matching_entries)
        push!(result, (
            key = _symbolic_name(arguments.variable),
            name = Symbol(statement_id(statement)),
            identity = layout_entry.schema.identity,
            handle = layout_entry.handle,
            kind = statement_kind(statement),
            role,
            storage,
            shape = state_shape,
            scalar_type = T,
            initial,
            unit,
        ))
    end
    return Tuple(result)
end

function _compiled_value_unit(value, manifest::ParameterManifest)
    index = _parameter_index(manifest, value)
    index === nothing || return manifest[index].unit
    return _reference_for(manifest.reference_units, value)
end

function _exact_physical_duration(value)
    _is_quantity(value) || return nothing
    magnitude = Float64(DynamicQuantities.ustrip(value))
    isfinite(magnitude) && magnitude > 0 || throw(ArgumentError(
        "duration_per_mcs must be finite and positive"
    ))
    exact = rationalize(
        Int64,
        magnitude;
        tol = max(eps(magnitude) * 4, eps(Float64)),
    )
    return (
        numerator = numerator(exact),
        denominator = denominator(exact),
        unit = Symbol(string(DynamicQuantities.dimension(value))),
    )
end

function _compiled_time_contract(statements)
    durations = Any[]
    for statement in statements
        value = _statement_option(statement, :duration_per_mcs, nothing)
        value === nothing || push!(durations, value)
    end
    physical = unique(filter(!isnothing, _exact_physical_duration.(durations)))
    length(physical) <= 1 || throw(ArgumentError(
        "all physical duration_per_mcs declarations must identify one exact interval"
    ))
    return (
        native_unit = :mcs,
        ticks_per_mcs = 1,
        duration_per_mcs = isempty(physical) ? nothing : only(physical),
        partial_advance = false,
        publication = :atomic_after_mcs,
    )
end
