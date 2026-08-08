# Deterministic structural scheduling for pure Potts systems.
#
# This layer projects the single frozen completion/source-graph authority.  It
# deliberately contains no selected algorithm, backend, scalar type, CorePotts
# program, runtime, or workspace.

"""
Stable, vector-backed structural scheduling authority.

All record-count-sized collections stay type-erased here.  This prevents the
heterogeneous source topology from being propagated into `mtkcompile` method
specializations.  Inspection converts these tables to the immutable tuple
surface promised to authors.
"""
struct ScheduledPottsData
    schema_version::VersionNumber
    schedule::Vector{QualifiedStatement}
    provenance::NamedTuple
    parameters::NamedTuple
    states::Vector{NamedTuple}
    relationships::Vector{NamedTuple}
    observations::Vector{NamedTuple}
    native_components::Vector{ScheduledNativeComponent}
    capability_requirements::NamedTuple
    fingerprint::ScheduledSystemFingerprint
end

function _scheduled_symbolic_name(value)
    return try
        Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value)))
    catch
        Symbol(string(value))
    end
end

function _scheduled_reference_name(path::Tuple, value)
    local_name = _scheduled_symbolic_name(value)
    relative_path = length(path) <= 1 ? () : path[2:end]
    isempty(relative_path) && return local_name
    return Symbol(join(String.((relative_path..., local_name)), "₊"))
end

function _scheduled_public_name(identity::QualifiedStatementID)
    relative_path = length(identity.path) <= 1 ? () : identity.path[2:end]
    return Symbol(join(
        String.((relative_path..., Symbol(identity.local_id))), "₊"
    ))
end

function _scheduled_option(record::QualifiedStatement, name::Symbol, default = nothing)
    options = last(record.normalized_payload)
    options isa NamedTuple || return default
    return get(options, name, default)
end

function _scheduled_parameter_schema(data::CompletedPottsData)
    references = data.source_graph.references
    input_names = Set(
        _scheduled_reference_name(reference.path, reference.value)
        for reference in references if reference.kind === :input
    )
    output_names = Set(
        _scheduled_reference_name(reference.path, reference.value)
        for reference in references if reference.kind === :output
    )
    runtime = NamedTuple[]
    seen = Set{Symbol}()
    for reference in references
        reference.kind === :parameter || continue
        name = _scheduled_reference_name(reference.path, reference.value)
        name in seen && throw(ArgumentError(
            "scheduled parameter identity `$name` is ambiguous"
        ))
        push!(seen, name)
        has_default = ModelingToolkitBase.hasdefault(reference.value)
        default = has_default ?
                  _defensive_copy(ModelingToolkitBase.getdefault(reference.value)) :
                  nothing
        push!(runtime, (
            name,
            identity = (
                path = reference.path,
                local_name = _scheduled_symbolic_name(reference.value),
            ),
            symbolic = reference.value,
            role = :runtime,
            required = !has_default,
            default,
            input = name in input_names,
            output = name in output_names,
        ))
    end
    structural = NamedTuple[]
    for entry in data.parameter_roles.structural
        push!(structural, (
            name = entry.name,
            identity = (path = (), local_name = entry.name),
            symbolic = nothing,
            role = :structural,
            required = false,
            default = _defensive_copy(entry.value),
            input = false,
            output = false,
        ))
    end
    return (runtime = runtime, structural = structural)
end

function _scheduled_initial_values(data::CompletedPottsData)
    result = Dict{Symbol, Any}()
    for reference in data.source_graph.references
        reference.kind === :initial_condition || continue
        pair = reference.value
        name = _scheduled_reference_name(reference.path, first(pair))
        haskey(result, name) && throw(ArgumentError(
            "scheduled initial-condition identity `$name` is ambiguous"
        ))
        result[name] = _defensive_copy(last(pair))
    end
    return result
end

function _scheduled_state_schema(data::CompletedPottsData)
    initial_conditions = _scheduled_initial_values(data)
    domains = filter(record -> record.kind === :LatticeDomain, data.records)
    lattice_shape = length(domains) == 1 ?
                    _scheduled_option(only(domains), :shape, ()) : ()
    entries = NamedTuple[]
    for record in data.records
        record.kind in (
            :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
            :HistoryState,
        ) || continue
        arguments = first(record.normalized_payload)
        haskey(arguments, :variable) || continue
        key = _scheduled_symbolic_name(arguments.variable)
        declared_initial = get(arguments, :initial, nothing)
        initial_source = haskey(initial_conditions, key) ? :system : :statement
        initial = haskey(initial_conditions, key) ?
                  initial_conditions[key] : _defensive_copy(declared_initial)
        storage = record.kind in (:SiteState, :FieldState) ? :site :
                  record.kind === :CellState ? :cell :
                  record.kind === :MediumState ? :medium :
                  record.kind === :ModelState ? :model : :history
        role = record.kind === :FieldState ? :field :
               record.kind === :HistoryState ? :history : :stored
        extent = storage === :site ? lattice_shape :
                 storage === :cell ? :cells :
                 storage === :history ? (
                     lattice_shape...,
                     _scheduled_option(record, :depth, 1),
                 ) : ()
        push!(entries, (
            key,
            name = _scheduled_public_name(record.identity),
            identity = record.identity,
            variable = arguments.variable,
            kind = record.kind,
            role,
            storage,
            extent,
            declared_shape = record.shape,
            initial,
            initial_source,
            units = record.units,
            reference_conversion = record.reference_conversion,
            ownership = record.ownership,
            persistence = record.persistence,
        ))
    end
    return entries
end

function _scheduled_relationship_schema(data::CompletedPottsData)
    entries = NamedTuple[]
    for record in data.records
        record.kind === :RelationshipState || continue
        arguments, options = record.normalized_payload
        push!(entries, (
            name = _scheduled_public_name(record.identity),
            identity = record.identity,
            capacity = get(options, :capacity, nothing),
            maximum_degree = get(options, :maximum_degree, nothing),
            endpoints = get(options, :endpoints, nothing),
            payload = get(options, :payload, NamedTuple()),
            initial = get(arguments, :initial, nothing),
            lifecycle = record.lifecycle,
            units = record.units,
            persistence = record.persistence,
        ))
    end
    return entries
end

function _scheduled_observation_schema(data::CompletedPottsData)
    entries = NamedTuple[]
    for record in data.records
        record.kind === :Observation || continue
        push!(entries, (
            name = _scheduled_public_name(record.identity),
            identity = record.identity,
            expression = get(first(record.normalized_payload), :expression, nothing),
            reads = record.reads,
            result_type = record.result_type,
            shape = record.shape,
            units = record.units,
            persistence = record.persistence,
            source = record.source,
        ))
    end
    return entries
end

function _schedule_native_components(components)
    isempty(components) && return ScheduledNativeComponent[]
    scheduled = ScheduledNativeComponent[]
    for component in components
        applicable(mtkcompile_native, component) || throw(ArgumentError(
            "scheduling NativeComponent $(repr(nameof(component.declaration))) " *
            "requires loading full ModelingToolkit so the " *
            "PottsToolkitModelingToolkitExt extension can call upstream mtkcompile"
        ))
        result = mtkcompile_native(component)
        result isa ScheduledNativeComponent || error(
            "mtkcompile_native must return ScheduledNativeComponent, got " *
            string(typeof(result))
        )
        result.path == component.path || error(
            "mtkcompile_native changed the native component path"
        )
        result.declaration === component.declaration || error(
            "mtkcompile_native changed the native component declaration"
        )
        push!(scheduled, result)
    end
    return scheduled
end

function _scheduled_native_provenance(components)
    summaries = [_scheduled_native_fingerprint_payload(component)
                 for component in components]
    sort!(summaries; by = summary -> join(String.(summary.path), "\0"))
    return NamedTuple[summary for summary in summaries]
end

function _scheduled_capability_requirements(
        data::CompletedPottsData, native_components = ()
    )
    domains = filter(record -> record.kind === :LatticeDomain, data.records)
    domain_requirements = NamedTuple[]
    for record in domains
        push!(domain_requirements, (
            identity = record.identity,
            shape = _scheduled_option(record, :shape, ()),
            dimension = length(_scheduled_option(record, :shape, ())),
            boundary = nameof(typeof(_scheduled_option(record, :boundary, Periodic()))),
            max_cells = _scheduled_option(record, :max_cells, nothing),
        ))
    end
    engine_admission = NamedTuple[]
    for record in data.records
        requirements = NamedTuple[]
        for admission in record.engine_admission
            push!(requirements, (
                engine = admission.engine,
                admitted = admission.admitted,
                reason = admission.reason,
            ))
        end
        push!(engine_admission, (
            identity = record.identity,
            requirements,
        ))
    end
    kinds = sort!(unique(record.kind for record in data.records); by = String)
    native_requirements = NamedTuple[]
    for component in native_components
        push!(native_requirements, (
            path = component.path,
            family = nameof(typeof(native_family(component.declaration))),
            scope = getfield(component.declaration, :scope),
            split = nameof(typeof(getfield(component.declaration, :split))),
            cadence = native_cadence_stride(component.declaration),
            initialization = nameof(typeof(getfield(component.declaration, :initialization))),
            events = nameof(typeof(getfield(component.declaration, :events))),
            lifecycle = getfield(component.declaration, :lifecycle),
            algorithm = nameof(typeof(getfield(component.declaration, :algorithm))),
            capability_policy = nameof(typeof(getfield(component.declaration, :capabilities))),
        ))
    end
    return (
        domains = domain_requirements,
        statement_kinds = Symbol[kinds...],
        engine_admission,
        has_relationships = any(
            record -> record.kind === :RelationshipState, data.records
        ),
        has_lifecycle = any(
            record -> record.kind === :LifecycleProcess, data.records
        ),
        has_random_operations = any(
            record -> !isempty(record.random_operations), data.records
        ),
        native_components = native_requirements,
        completion = data.capabilities,
    )
end

function _scheduled_provenance(
        data::CompletedPottsData, analysis, native_components = ()
    )
    systems = NamedTuple[]
    for node in data.source_graph.systems
        push!(systems, (
            name = node.name,
            path = node.path,
            parent = node.parent,
        ))
    end
    records = NamedTuple[]
    for record in data.records
        push!(records, (
            identity = record.identity,
            schema_version = record.schema_version,
            lowering_identity = record.lowering_identity,
            source = record.source,
            provenance = record.provenance,
        ))
    end
    return (
        schema = v"1.0.0",
        semantic = data.fingerprints.semantic,
        completed = data.fingerprints.completed,
        source_graph = data.source_graph.structural_key,
        normalized_graph = data.normalized_graph.structural_key,
        analysis = analysis.structural_key,
        systems,
        records,
        native_components = _scheduled_native_provenance(native_components),
    )
end

# Fingerprints describe the public logical scheduling schema, whose collection
# surface is tuple-based.  Build that view only for encoding and force the
# canonical encoder through its `Any` method so tuple length cannot become a
# compilation specialization key.  The emitted bytes are identical to the
# original tuple-backed representation.
function _fingerprint_completion_capabilities(capabilities::NamedTuple)
    return (
        sequential = capabilities.sequential,
        checkerboard = capabilities.checkerboard,
        checkerboard_rejections = Tuple(capabilities.checkerboard_rejections),
        cpu = capabilities.cpu,
    )
end

function _fingerprint_scheduled_provenance(provenance::NamedTuple)
    return (
        schema = provenance.schema,
        semantic = provenance.semantic,
        completed = provenance.completed,
        source_graph = provenance.source_graph,
        normalized_graph = provenance.normalized_graph,
        analysis = provenance.analysis,
        systems = Tuple(provenance.systems),
        records = Tuple(provenance.records),
        native_components = Tuple(provenance.native_components),
    )
end

_fingerprint_scheduled_parameters(parameters::NamedTuple) = (
    runtime = Tuple(parameters.runtime),
    structural = Tuple(parameters.structural),
)

function _fingerprint_scheduled_capabilities(requirements::NamedTuple)
    engine_admission = Tuple((
        identity = entry.identity,
        requirements = Tuple(entry.requirements),
    ) for entry in requirements.engine_admission)
    return (
        domains = Tuple(requirements.domains),
        statement_kinds = Tuple(requirements.statement_kinds),
        engine_admission,
        has_relationships = requirements.has_relationships,
        has_lifecycle = requirements.has_lifecycle,
        has_random_operations = requirements.has_random_operations,
        native_components = Tuple(requirements.native_components),
        completion = _fingerprint_completion_capabilities(
            requirements.completion
        ),
    )
end

@noinline function _erased_canonical_digest(parts::Vector{Any})
    encoded = String[_CANONICAL_VALUE_SCHEMA]
    for part in parts
        push!(encoded, invoke(_canonical_value, Tuple{Any}, part))
    end
    payload = _canonical_frame("digest", encoded)
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function _stable_scheduled_fingerprint(
        completed::CompletedSystemFingerprint,
        schedule::Vector{QualifiedStatement},
        provenance::NamedTuple,
        parameters::NamedTuple,
        states::Vector{NamedTuple},
        relationships::Vector{NamedTuple},
        observations::Vector{NamedTuple},
        capability_requirements::NamedTuple,
        native_components::Vector{NamedTuple},
    )
    parts = Any[
        "potts-scheduled-system-v1",
        completed.hex,
        Tuple(schedule),
        _fingerprint_scheduled_provenance(provenance),
        _fingerprint_scheduled_parameters(parameters),
        Tuple(states),
        Tuple(relationships),
        Tuple(observations),
        _fingerprint_scheduled_capabilities(capability_requirements),
        Tuple(native_components),
    ]
    return ScheduledSystemFingerprint(_erased_canonical_digest(parts))
end

function _build_scheduled_data(data::CompletedPottsData, analysis)
    schedule = data.schedule
    native_components = _schedule_native_components(data.native_components)
    native_provenance = _scheduled_native_provenance(native_components)
    provenance = _scheduled_provenance(data, analysis, native_components)
    parameters = _scheduled_parameter_schema(data)
    states = _scheduled_state_schema(data)
    relationships = _scheduled_relationship_schema(data)
    observations = _scheduled_observation_schema(data)
    capability_requirements = _scheduled_capability_requirements(
        data, native_components
    )
    fingerprint = _stable_scheduled_fingerprint(
        data.fingerprints.completed,
        schedule,
        provenance,
        parameters,
        states,
        relationships,
        observations,
        capability_requirements,
        native_provenance,
    )
    return ScheduledPottsData(
        v"1.0.0",
        schedule,
        provenance,
        parameters,
        states,
        relationships,
        observations,
        native_components,
        capability_requirements,
        fingerprint,
    )
end


function scheduled_native_components(system::PottsSystem)
    is_scheduled(system) || throw(ArgumentError(
        "scheduled_native_components requires a structurally scheduled PottsSystem"
    ))
    completion = getfield(system, :completion)
    completion isa CompletedPottsData || error(
        "scheduled PottsSystem is missing completed structural data"
    )
    scheduled = completion.scheduled
    scheduled isa ScheduledPottsData || error(
        "scheduled PottsSystem is missing scheduled structural data"
    )
    return Tuple(scheduled.native_components)
end

function _with_scheduled_data(data::CompletedPottsData, scheduled::ScheduledPottsData)
    return CompletedPottsData(
        data.registry,
        data.reference_units,
        data.parameter_roles,
        data.records,
        data.variables,
        data.schedule,
        data.capabilities,
        data.fingerprints,
        data.diagnostics,
        data.source_graph,
        data.normalized_graph,
        data.analysis,
        data.native_components,
        scheduled,
    )
end

const _MTKCOMPILE_RUNTIME_CHOICES = Set((
    :alg, :algorithm, :engine, :backend, :device, :scalar_type, :seed,
    :replica, :repeat,
))
const _MTKCOMPILE_IO_OVERRIDES = Set((
    :inputs, :outputs, :disturbance_inputs,
))

function _validate_mtkcompile_kwargs(kwargs)
    isempty(kwargs) && return nothing
    names = Tuple(keys(kwargs))
    runtime = sort!(collect(intersect(Set(names), _MTKCOMPILE_RUNTIME_CHOICES)); by = String)
    isempty(runtime) || throw(ArgumentError(
        "structural mtkcompile does not accept runtime choice" *
        (length(runtime) == 1 ? " " : "s ") *
        join(("`$(name)`" for name in runtime), ", ") *
        "; pass runtime choices to init or solve"
    ))
    :additional_passes in names && throw(ArgumentError(
        "pure-Potts structural mtkcompile does not support `additional_passes`"
    ))
    io = sort!(collect(intersect(Set(names), _MTKCOMPILE_IO_OVERRIDES)); by = String)
    isempty(io) || throw(ArgumentError(
        "pure-Potts structural mtkcompile does not accept input/output override" *
        (length(io) == 1 ? " " : "s ") *
        join(("`$(name)`" for name in io), ", ") *
        "; declare inputs and outputs on PottsSystem"
    ))
    throw(ArgumentError(
        "unsupported pure-Potts mtkcompile option" *
        (length(names) == 1 ? " " : "s ") *
        join(("`$(name)`" for name in sort!(collect(names); by = String)), ", ")
    ))
end

"""
    ModelingToolkitBase.mtkcompile(system::PottsSystem)

Complete and structurally schedule a pure Potts model.  The returned
`PottsSystem` remains symbolic; algorithm, backend, scalar, stochastic identity,
CorePotts lowering, and runtime materialization are intentionally later stages.
"""
function ModelingToolkitBase.mtkcompile(system::PottsSystem; kwargs...)
    _validate_mtkcompile_kwargs(kwargs)
    is_scheduled(system) && return system
    completed = ModelingToolkitBase.iscomplete(system) ?
                system : ModelingToolkitBase.complete(system)

    # Coverage and analysis project the one completion record/source-graph
    # authority.  Neither pass reconstructs the authored hierarchy.
    diagnostics = PottsDiagnostic[]
    _validate_compilation_coverage!(diagnostics, completed)
    _validate_equation_and_event_coverage!(diagnostics, completed)
    _throw_diagnostics(:scheduling, diagnostics)
    analysis = _analyze_completed_system(completed)

    completion = getfield(completed, :completion)::CompletedPottsData
    scheduled = _build_scheduled_data(completion, analysis)
    return _rebuild(
        completed;
        isscheduled = true,
        completion = _with_scheduled_data(completion, scheduled),
    )
end
