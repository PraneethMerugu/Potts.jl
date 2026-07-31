# Top-level compiler orchestration.

function _validate_compilation_choices(
        completed::PottsSystem,
        engine,
        backend,
        scalar_type,
    )
    iscomplete(completed) ||
        throw(ArgumentError("compile requires a completed PottsSystem"))
    engine isa AbstractPottsEngine ||
        throw(ArgumentError("engine must be SequentialEngine() or CheckerboardEngine()"))
    backend isa CPUBackend ||
        throw(ArgumentError("V1 currently admits only CPUBackend()"))
    scalar_type isa Type && scalar_type <: AbstractFloat ||
        throw(ArgumentError("scalar_type must be a concrete AbstractFloat type"))
    isconcretetype(scalar_type) ||
        throw(ArgumentError("scalar_type must be concrete"))
    capabilities = inspect(completed, Capabilities())
    engine isa SequentialEngine && !capabilities.sequential &&
        throw(ArgumentError("completed system is not admitted by SequentialEngine"))
    if engine isa CheckerboardEngine && !capabilities.checkerboard
        reasons = join(
            ("$(identity): $reason"
             for (identity, reason) in capabilities.checkerboard_rejections),
            "; ",
        )
        throw(ArgumentError(
            "completed system is not admitted by CheckerboardEngine: $reasons"
        ))
    end
    return nothing
end

function _statement_by_id(statements, id)
    index = findfirst(
        statement -> statement_id(statement) == statement_id(id), statements
    )
    return index === nothing ? nothing : statements[index]
end

function _compiled_activity_declaration(statements)
    index = findfirst(statement ->
        statement isa ProposalDrive &&
        _statement_option(statement, :mechanism) === :activity, statements)
    return index === nothing ? nothing : statements[index]
end

function _compiled_relationship_declaration(statements)
    resources = filter(statement -> statement isa RelationshipState, statements)
    return length(resources) == 1 ? only(resources) : nothing
end

_same_statement_resource(left, right) =
    left isa AbstractPottsStatement &&
    right isa AbstractPottsStatement &&
    statement_id(left) == statement_id(right)

function _accepted_copy_rejection(statement, statements)
    effects = _statement_arguments(statement).effects
    length(effects) == 1 ||
        return "accepted-copy lowering requires exactly one bounded V1 effect"
    effect = only(effects)
    condition = _statement_arguments(statement).expression
    if effect isa Assign
        activity = _compiled_activity_declaration(statements)
        activity === nothing &&
            return "Assign has no matching compiled activity declaration"
        isequal(effect.target, _statement_option(activity, :activity)) ||
            return "Assign target is not the compiled activity state"
        isequal(effect.value, _statement_option(activity, :maximum)) ||
            return "activity activation must assign the declared maximum"
        copy = ProposalContext(:copy)
        isequal(condition, copy.is_extension) ||
            return "activity activation condition must be copy.is_extension"
        return nothing
    elseif effect isa Create
        relationship = _compiled_relationship_declaration(statements)
        relationship === nothing &&
            return "Create has no matching compiled relationship state"
        _same_statement_resource(effect.relationship, relationship) ||
            return "Create has no matching compiled relationship state"
        payload = _statement_option(relationship, :payload, NamedTuple())
        all(name -> haskey(effect.payload, name) &&
                    isequal(getproperty(effect.payload, name), getproperty(payload, name)),
            keys(payload)) ||
            return "Create payload must match the compiled relationship payload"
        copy = ProposalContext(:copy)
        expected = new_contact(copy.source_cell, copy.target_cell) &
                   !linked(
            relationship, copy.source_cell, copy.target_cell
        )
        isequal(condition, expected) ||
            return "relationship creation condition must be new-contact and unlinked"
        return nothing
    end
    return "accepted-copy lowering does not support $(nameof(typeof(effect)))"
end

function _synchronous_rejection(statement, statements)
    effects = _statement_arguments(statement).effects
    length(effects) == 1 ||
        return "synchronous lowering requires exactly one bounded assignment"
    effect = only(effects)
    effect isa Assign ||
        return "synchronous lowering currently requires Assign"
    activity = _compiled_activity_declaration(statements)
    activity === nothing &&
        return "Assign has no matching compiled activity declaration"
    isequal(effect.target, _statement_option(activity, :activity)) ||
        return "Assign target is not the compiled activity state"
    decay = _statement_option(statement, :decay, nothing)
    decay === nothing &&
        return "activity decay requires an explicit `decay` value"
    expected = max(effect.target - decay, 0)
    isequal(effect.value, expected) ||
        return "activity decay expression must be max(activity - decay, 0)"
    return nothing
end

function _relationship_process_rejection(statement, statements)
    relationship = _compiled_relationship_declaration(statements)
    relationship === nothing &&
        return "relationship process requires exactly one relationship state"
    arguments = _statement_arguments(statement)
    arguments.domain isa Edges &&
        _same_statement_resource(arguments.domain.relationship, relationship) ||
        return "relationship process domain must be edges(relationship)"
    length(arguments.effects) == 1 &&
        only(arguments.effects) isa Remove &&
        _same_statement_resource(
            only(arguments.effects).relationship, relationship
        ) ||
        return "relationship process must emit one Remove request"
    arguments.expression === nothing &&
        return "relationship removal requires an explicit bounded condition"
    expression = string(arguments.expression)
    all(token -> occursin(token, expression), (
        "distance", "unwrapped_center", "__potts_payload__maximum",
    )) || return "relationship removal must compare unwrapped distance to edge.maximum"
    return nothing
end

function _equation_process_rejection(statement, statements, system)
    arguments = _statement_arguments(statement)
    options = _statement_options(statement)
    options.solver isa ExplicitDiffusion ||
        return "V1 executable equation lowering currently requires ExplicitDiffusion"
    fields = filter(candidate -> candidate isa FieldState, statements)
    length(fields) == 1 ||
        return "equation lowering requires exactly one FieldState"
    variable = _statement_arguments(only(fields)).variable
    length(arguments.writes) == 1 && isequal(only(arguments.writes), variable) ||
        return "EquationProcess writes must identify the compiled FieldState"
    isempty(arguments.equations) &&
        return "EquationProcess requires at least one equation"
    all(equation -> any(isequal(equation), ModelingToolkitBase.equations(system)),
        arguments.equations) ||
        return "EquationProcess equations must be present in PottsSystem.equations"
    return nothing
end

function _statement_lowering_rejection(statement, statements, system)
    if statement isa Union{ProposalDrive, ProposalModifier}
        return nothing
    elseif statement isa ProposalConstraint
        return nothing
    elseif statement isa HamiltonianTerm
        mechanism = _statement_option(statement, :mechanism)
        mechanism === nothing || mechanism === :symbolic || mechanism in (
            :volume, :contact, :relationship, :elongation,
        ) || return "unsupported HamiltonianTerm mechanism $(repr(mechanism))"
        if mechanism === :relationship
            expression = string(_statement_arguments(statement).expression)
            all(token -> occursin(token, expression), (
                "distance", "unwrapped_center", "__potts_payload__strength",
                "__potts_payload__target",
            )) || return "relationship energy must be the canonical unwrapped spring"
        end
    elseif statement isa SynchronousProcess
        return _synchronous_rejection(statement, statements)
    elseif statement isa AcceptedCopyProcess
        return _accepted_copy_rejection(statement, statements)
    elseif statement isa Union{RelationshipProcess, LifecycleProcess}
        return _relationship_process_rejection(statement, statements)
    elseif statement isa EquationProcess
        return _equation_process_rejection(statement, statements, system)
    elseif statement isa Protocol
        all(stage -> stage isa Union{SweepStage, ObserveStage},
            _statement_arguments(statement).stages) ||
            return "Protocol contains an unsupported stage"
    elseif statement isa RegisteredStatement
        return "RegisteredStatement was not lowered during completion"
    end
    return nothing
end

function _validate_compilation_coverage!(
        diagnostics, system::PottsSystem, parent_path::Tuple = ()
    )
    path = (parent_path..., nameof(system))
    local_statements = statements(system)
    all_statements = _all_system_statements(system)
    for statement in local_statements
        reason = _statement_lowering_rejection(
            statement, all_statements, system
        )
        reason === nothing && continue
        push!(diagnostics, PottsDiagnostic(
            :unsupported_v1_lowering,
            QualifiedStatementID(path, statement_id(statement)),
            _statement_expression(statement),
            path,
            "a concrete, semantics-preserving V1 lowering",
            reason,
            (),
            statement_source(statement),
        ))
    end
    for child in getfield(system, :systems)
        _validate_compilation_coverage!(diagnostics, child, path)
    end
    return diagnostics
end

function _validate_equation_and_event_coverage!(diagnostics, system::PottsSystem)
    records = inspect(system, Statements())
    equation_records = filter(
        record -> record.kind === :EquationProcess, records
    )
    for equation in ModelingToolkitBase.equations(system)
        owners = filter(equation_records) do record
            arguments = first(record.normalized_payload)
            any(candidate -> isequal(candidate, equation), arguments.equations)
        end
        if isempty(owners)
            push!(diagnostics, PottsDiagnostic(
                :unowned_equation,
                _try_symbolic_name(equation.lhs),
                string(equation),
                (nameof(system),),
                "exactly one explicit EquationProcess owner",
                "no owner",
                (),
                UnknownSource(),
            ))
        elseif length(owners) > 1
            for owner in owners
                push!(diagnostics, PottsDiagnostic(
                    :duplicate_equation_owner,
                    owner.identity,
                    string(equation),
                    owner.identity.path,
                    "exactly one explicit EquationProcess owner",
                    join(string.(getfield.(owners, :identity)), ", "),
                    (),
                    owner.source,
                ))
            end
        end
    end
    written = Tuple(
        (record, value)
        for record in equation_records
        for value in first(record.normalized_payload).writes
    )
    for (record, value) in written
        owners = filter(item -> isequal(last(item), value), written)
        length(owners) <= 1 && continue
        push!(diagnostics, PottsDiagnostic(
            :duplicate_equation_write_owner,
            record.identity,
            record.source isa SourceLocation ?
            record.source.expression : string(record.identity),
            record.identity.path,
            "one EquationProcess writer per phase",
            join((string(item[1].identity) for item in owners), ", "),
            (),
            record.source,
        ))
    end
    for (kind, events) in (
            :continuous_event => ModelingToolkitBase.continuous_events(system),
            :discrete_event => ModelingToolkitBase.discrete_events(system),
        )
        isempty(events) && continue
        push!(diagnostics, PottsDiagnostic(
            :unsupported_v1_event_lowering,
            nameof(system),
            join(string.(events), "; "),
            (nameof(system),),
            "symbolic event effects lowerable into the closed V1 effect language",
            "$(length(events)) $kind declaration(s) have no concrete lowering",
            (),
            UnknownSource(),
        ))
    end
    return diagnostics
end

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
            elseif observation !== nothing && observation.kind === :field_state
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
        push!(result, (
            key = _symbolic_name(arguments.variable),
            name = Symbol(statement_id(statement)),
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

"""
    compile(completed; engine, backend, scalar_type)

Lower a completed symbolic system into one immutable, reusable executable.
All three execution choices are mandatory.
"""
function compile(
        completed::PottsSystem;
        engine,
        backend,
        scalar_type,
    )
    _validate_compilation_choices(completed, engine, backend, scalar_type)
    analyzed_ir = _analyze_completed_system(completed)
    diagnostics = PottsDiagnostic[]
    _validate_compilation_coverage!(diagnostics, completed)
    _validate_equation_and_event_coverage!(diagnostics, completed)
    _throw_diagnostics(:compilation, diagnostics)
    manifest = _build_parameter_manifest(completed, scalar_type)
    descriptor_plan = _lower_descriptor_plan(
        analyzed_ir, manifest, scalar_type
    )
    _assert_concrete_core_boundary(
        descriptor_plan; path = "descriptor_plan"
    )
    completion_fingerprint = completed_system_fingerprint(completed)
    seed = _sha256_hex(
        "potts-executable-seed-v1",
        completion_fingerprint.hex,
        nameof(typeof(engine)),
        nameof(typeof(backend)),
        scalar_type,
        Tuple((entry.name, entry.required, entry.unit)
            for entry in manifest),
    )
    core_program, kinds, observation_manifest = _lower_core_program(
        completed,
        engine,
        backend,
        scalar_type,
        manifest,
        descriptor_plan,
        seed,
    )
    _assert_concrete_core_boundary(core_program)
    execution = CorePotts.program_execution_report(core_program)
    capability = CorePotts.program_capability_report(core_program)
    storage = _storage_report(core_program)
    workspace = _workspace_report(core_program)
    statement_manifest = _compiled_statement_manifest(completed)
    completion_fingerprints = inspect(completed, Fingerprints())
    compiled_schedule = NamedTuple[
        (
            identity = _manifest_identity(record.identity),
            phase = record.phase === nothing ? nothing : nameof(typeof(record.phase)),
        )
        for record in inspect(completed, Schedule())
    ]
    all_statements = _all_system_statements(completed)
    activity_reference = let index = findfirst(statement ->
            statement isa ProposalDrive &&
            _statement_option(statement, :mechanism) === :activity,
            all_statements)
        index === nothing ? nothing :
        _statement_option(all_statements[index], :activity)
    end
    states = _compiled_state_manifest(
        completed,
        all_statements,
        activity_reference,
        manifest,
        core_program.shape,
        scalar_type,
    )
    relationship_states = Tuple(
        let
            payload = _statement_option(statement, :payload, NamedTuple())
            (
                name = Symbol(statement_id(statement)),
                capacity = Int(_numeric_value(
                    _statement_option(statement, :capacity)
                )),
                maximum_degree = Int(_numeric_value(
                    _statement_option(statement, :maximum_degree)
                )),
                endpoints = let endpoints =
                        _statement_option(statement, :endpoints)
                    (
                        direction = endpoints isa Undirected ? :undirected :
                                    :directed,
                        kind_a = _manifest_symbol(endpoints.kind_a),
                        kind_b = _manifest_symbol(endpoints.kind_b),
                    )
                end,
                lifecycle = nameof(typeof(_statement_option(
                    statement, :lifecycle, RejectEndpointRetirement()
                ))),
                payload_units = (
                    strength = haskey(payload, :strength) ?
                               _compiled_value_unit(payload.strength, manifest) :
                               nothing,
                    target = haskey(payload, :target) ?
                             _compiled_value_unit(payload.target, manifest) :
                             nothing,
                    maximum = haskey(payload, :maximum) ?
                              _compiled_value_unit(payload.maximum, manifest) :
                              nothing,
                ),
            )
        end
        for statement in all_statements
        if statement isa RelationshipState
    )
    time = _compiled_time_contract(all_statements)
    external_io = _compiled_external_io(
        completed,
        manifest,
        states,
        observation_manifest,
        core_program.shape,
        scalar_type,
    )
    reports = (
        execution,
        capability,
        compiler = _compiler_analysis_report(analyzed_ir),
        descriptors = CorePotts.descriptor_plan_report(descriptor_plan),
        storage,
        workspace,
        statements = statement_manifest,
        variables = Tuple(
            _manifest_symbol(value)
            for value in inspect(completed, Variables())
        ),
        schedule = compiled_schedule,
        replay = (
            class = :exact_same_executable,
            cross_engine = false,
            addressed_rng = true,
        ),
        checkpoint = (schema = v"1.0.0", logical_only = true),
        kinds,
        fingerprints = completion_fingerprints,
        states,
        relationship_states,
        external_io,
        time,
    )
    observations = observation_manifest
    fingerprint_states = Tuple(
        (
            key = state.key,
            name = state.name,
            kind = state.kind,
            role = state.role,
            storage = state.storage,
            shape = state.shape,
            scalar_type = state.scalar_type,
            unit = state.unit,
        )
        for state in states
    )
    fingerprint_reports = merge(reports, (states = fingerprint_states,))
    fingerprint = ExecutableFingerprint(_sha256_hex(
        "potts-executable-v1",
        seed,
        core_program.fingerprint,
        fingerprint_reports,
    ))
    executable = PottsExecutable(
        core_program,
        manifest,
        reports,
        observations,
        fingerprint,
    )
    _assert_concrete_core_boundary(executable; path = "executable")
    return executable
end
