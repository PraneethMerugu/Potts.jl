module PottsToolkitProcessBigraphsExt

using PottsToolkit
import ProcessBigraphs
import ProcessBigraphs:
    capabilities,
    complete_operation!,
    discard_candidate!,
    invoke,
    ports,
    prepare_engine,
    publish_candidate!,
    semantic_parameters,
    semantic_version,
    stage_operation!

struct PottsEngineAdapter{P} <: ProcessBigraphs.AbstractEngineAdapter
    problem::P
end

mutable struct PottsEngineInstance{I} <: ProcessBigraphs.AbstractEngineInstance
    published::I
    staged::Union{Nothing, I}
end

struct PottsCompletionHandle{C} <: ProcessBigraphs.AbstractCompletionHandle
    candidate::C
end

struct PottsProcessComponent{P, D, M} <: ProcessBigraphs.AbstractProcess
    problem::P
    declaration::D
    manifest::M
end

function _value_type(element_type, shape)
    isempty(shape) && return element_type
    return Array{element_type, length(shape)}
end

function _bridge_manifest(problem::PottsProblem)
    executable = problem.executable
    inputs = NamedTuple[]
    outputs = NamedTuple[]
    for entry in inspect(executable, PottsToolkit.ExternalIO())
        value_type = _value_type(entry.element_type, entry.shape)
        item = merge(entry, (; value_type))
        push!(entry.direction === :input ? inputs : outputs, item)
    end

    fingerprint = string(PottsToolkit.executable_fingerprint(executable))
    endpoints = Symbol[entry.endpoint for entry in (inputs..., outputs...)]
    length(endpoints) == length(unique(endpoints)) ||
        throw(ArgumentError("compiled ProcessBigraph endpoint collision"))
    return (
        identity = Symbol("potts_", first(fingerprint, 20)),
        executable_fingerprint = fingerprint,
        inputs = Tuple(inputs),
        outputs = Tuple(outputs),
        time = inspect(executable, Kernels()).time,
        execution = inspect(executable, Kernels()),
        capability = inspect(executable, Capabilities()),
        replay = inspect(executable, PottsToolkit.ReplayContract()),
        failures = (
            :nonintegral_mcs,
            :horizon_exceeded,
            :input_schema_mismatch,
            :checkpoint_mismatch,
            :engine_failure,
        ),
    )
end

function _engine_declaration(problem, manifest)
    scalar_type = inspect(problem.executable, Kernels()).scalar_type
    precision = scalar_type === Float32 ? :float32 : :float64
    capabilities = ProcessBigraphs.EngineCapabilities(
        operation_families = (:interval_advance,),
        problem_envelopes = ("potts-v1",),
        backends = (:cpu,),
        precisions = (precision,),
        residencies = (:host,),
        input_modes = (:frozen,),
        continuation_actions = (:preserve, :reconstruct, :reject),
        replay_class = :exact,
        diagnostics = true,
        bridges = ("PottsToolkit-v1",),
    )
    adapter = PottsEngineAdapter(problem)
    endpoint_manifest = _semantic_endpoint_manifest(manifest)
    return ProcessBigraphs.EngineDeclaration(
        String(manifest.identity),
        adapter;
        semantic_version = "1.0.0",
        capabilities,
        parameters = (
            executable_fingerprint = manifest.executable_fingerprint,
            endpoint_manifest,
            time = manifest.time,
            checkpoint_schema = string(manifest.replay.checkpoint.schema),
        ),
    )
end

function _semantic_manifest_entry(entry)
    return (
        identity = entry.identity,
        endpoint = entry.endpoint,
        direction = entry.direction,
        access = entry.access,
        element_type = string(entry.element_type),
        shape = entry.shape,
        unit = entry.unit,
        ownership = entry.ownership,
        persistence = entry.persistence,
        update_law = entry.update_law,
        residency = entry.residency,
        codec = entry.codec,
        interval_behavior = entry.interval_behavior,
        cadence = entry.cadence,
    )
end

_semantic_endpoint_manifest(manifest) = (
    inputs = Tuple(_semantic_manifest_entry(entry) for entry in manifest.inputs),
    outputs = Tuple(_semantic_manifest_entry(entry) for entry in manifest.outputs),
)

_bridge_observables(problem) = Tuple(
    entry.source
    for entry in inspect(problem.executable, PottsToolkit.ExternalIO())
    if entry.direction === :output && entry.observation_index !== nothing
)

function PottsToolkit.process_component(problem::PottsProblem)
    manifest = _bridge_manifest(problem)
    declaration = _engine_declaration(problem, manifest)
    return PottsProcessComponent(problem, declaration, manifest)
end

function PottsToolkit.EquationComponent(
        ::PottsProcessComponent,
        ::PottsToolkit.EquationProcess;
        name = nothing,
    )
    throw(ArgumentError(
        "a ProcessBigraph-managed Potts component already has an outer scheduling " *
        "owner and cannot also be assimilated as an EquationComponent"
    ))
end

function prepare_engine(
        adapter::PottsEngineAdapter,
        ::ProcessBigraphs.EngineDeclaration,
    )
    observables = _bridge_observables(adapter.problem)
    integrator = PottsToolkit.init(
        adapter.problem;
        save_start = false,
        save_end = false,
        observables,
    )
    return PottsEngineInstance(integrator, nothing)
end

function _validate_mcs_interval(instance, invocation)
    operation = invocation.operation
    operation isa ProcessBigraphs.IntervalAdvance ||
        throw(ArgumentError("the Potts bridge accepts only interval advances"))
    start = operation.start_time
    target = operation.target_time
    target.scale == start.scale ||
        throw(ArgumentError("Potts invocation time scales do not match"))
    contract = inspect(
        instance.published.prob.executable, Kernels()
    ).time
    duration = contract.duration_per_mcs
    mcs_at = if start.scale.unit === :mcs
        start.scale.numerator == 1 &&
            start.scale.denominator == 1 || throw(ArgumentError(
                "the native :mcs scale must be exactly one tick per MCS"
            ))
        time -> Int(time.tick)
    else
        duration === nothing && throw(ArgumentError(
            "physical ProcessBigraph time requires a compiled duration_per_mcs"
        ))
        start.scale.unit === duration.unit || throw(ArgumentError(
            "physical ProcessBigraph time unit does not match duration_per_mcs"
        ))
        function (time)
            elapsed = (Int128(time.tick) * Int128(start.scale.numerator) *
                       Int128(duration.denominator)) //
                      (Int128(start.scale.denominator) *
                       Int128(duration.numerator))
            denominator(elapsed) == 1 || throw(ArgumentError(
                "ProcessBigraph boundary does not map to an integral MCS"
            ))
            value = numerator(elapsed)
            typemin(Int) <= value <= typemax(Int) || throw(ArgumentError(
                "ProcessBigraph time exceeds the Potts MCS range"
            ))
            Int(value)
        end
    end
    start_mcs = mcs_at(start)
    target_mcs = mcs_at(target)
    target_mcs - start_mcs == 1 ||
        throw(ArgumentError("one Potts invocation must advance exactly one MCS"))
    instance.published.t == start_mcs ||
        throw(ArgumentError("Potts invocation start does not match its settled state"))
    target_mcs <= instance.published.prob.tspan[2] ||
        throw(ArgumentError("Potts invocation exceeds the problem horizon"))
    return target, target_mcs
end

function _external_input_values(instance, invocation)
    manifest = inspect(
        instance.published.prob.executable, PottsToolkit.ExternalIO()
    )
    values = Pair{Symbol, Any}[]
    for projection in invocation.inputs
        entry_index = findfirst(
            entry -> entry.direction === :input &&
                     entry.endpoint === projection.name,
            manifest,
        )
        entry_index === nothing &&
            throw(ArgumentError("unknown Potts external input `$(projection.name)`"))
        push!(
            values,
            manifest[entry_index].endpoint =>
                ProcessBigraphs.projection_value(projection),
        )
    end
    return values
end

function _output_value(saved, entry)
    source = haskey(entry, :source) ? entry.source : entry.identity
    source === :ownership && return copy(saved.ownership)
    if entry.state_index !== nothing
        source === :activity && return copy(saved.activity)
        source === :field && return copy(saved.field)
    end
    return copy(saved[source])
end

function stage_operation!(
        instance::PottsEngineInstance,
        invocation::ProcessBigraphs.EngineInvocation,
    )
    target, target_mcs = _validate_mcs_interval(instance, invocation)
    base_checkpoint = PottsToolkit.checkpoint(instance.published)
    staged = PottsToolkit.init(
        instance.published.prob;
        checkpoint = base_checkpoint,
        save_start = false,
        save_end = false,
        observables = _bridge_observables(instance.published.prob),
    )
    PottsToolkit.stage_external_inputs!(
        staged, _external_input_values(instance, invocation)
    )
    PottsToolkit.step!(staged)
    staged.t == target_mcs ||
        throw(ArgumentError("Potts engine did not reach its exact MCS target"))
    instance.staged = staged
    component_manifest = _bridge_manifest(staged.prob)
    effects = Tuple(
        entry.endpoint => _output_value(staged.u, entry)
        for entry in component_manifest.outputs
    )
    stats = PottsToolkit.runtime_statistics(staged)
    checkpoint_value = PottsToolkit.checkpoint(staged)
    candidate = ProcessBigraphs.EngineCandidate(
        target,
        (integrator = staged, checkpoint = checkpoint_value);
        effects,
        continuation = checkpoint_value,
        diagnostics = (
            mcs = staged.t,
            accepted = stats.accepted,
            rejected = stats.rejected,
        ),
        fingerprint = ProcessBigraphs.canonical_fingerprint((
            :potts_engine_candidate_v1,
            component_manifest.executable_fingerprint,
            staged.t,
            checkpoint_value.checksum,
        )),
    )
    return PottsCompletionHandle(candidate)
end

complete_operation!(
    ::PottsEngineInstance, handle::PottsCompletionHandle
) = handle.candidate

function publish_candidate!(
        instance::PottsEngineInstance,
        ::ProcessBigraphs.EngineInvocation,
        candidate::ProcessBigraphs.EngineCandidate,
    )
    instance.staged === candidate.payload.integrator ||
        throw(ArgumentError("Potts publication candidate is not the staged state"))
    instance.published = instance.staged
    instance.staged = nothing
    return (
        mcs = instance.published.t,
        fingerprint = candidate.fingerprint,
    )
end

function discard_candidate!(
        instance::PottsEngineInstance,
        ::ProcessBigraphs.EngineInvocation,
        candidate,
    )
    instance.staged = nothing
    return nothing
end

function ports(component::PottsProcessComponent)
    inputs = Tuple(
        ProcessBigraphs.InputPort(
            entry.value_type,
            entry.endpoint;
            interval_behavior = :frozen,
            residency = :cpu,
        )
        for entry in component.manifest.inputs
    )
    outputs = Tuple(
        ProcessBigraphs.OutputPort(
            entry.value_type,
            entry.endpoint;
            interval_behavior = :frozen,
            residency = :cpu,
            update_law = :replace,
        )
        for entry in component.manifest.outputs
    )
    return (inputs..., outputs...)
end

capabilities(::PottsProcessComponent) =
    ProcessBigraphs.CapabilitySet((:cpu,))
semantic_version(::PottsProcessComponent) = "1.0.0"
semantic_parameters(component::PottsProcessComponent) = (
    executable_fingerprint = component.manifest.executable_fingerprint,
    engine_declaration = component.declaration.fingerprint,
    endpoint_manifest = _semantic_endpoint_manifest(component.manifest),
    time = component.manifest.time,
    scheduling_owner = :process_bigraphs_outer_corepotts_inner,
)

function invoke(
        component::PottsProcessComponent,
        inputs::ProcessBigraphs.PortView,
        context::ProcessBigraphs.InvocationContext,
    )
    instance = prepare_engine(
        component.declaration.adapter, component.declaration
    )
    if context.continuation !== nothing
        instance.published = PottsToolkit.init(
            component.problem;
            checkpoint = context.continuation,
            save_start = false,
            save_end = false,
            observables = _bridge_observables(component.problem),
        )
    end
    projections = Tuple(
        ProcessBigraphs.EngineInputProjection(
            entry.endpoint,
            inputs.snapshot_version,
            context.start_time,
            inputs[entry.endpoint];
            mode = :frozen,
        )
        for entry in component.manifest.inputs
    )
    precision = inspect(component.problem.executable, Kernels()).scalar_type ===
                Float32 ? :float32 : :float64
    invocation_value = ProcessBigraphs.EngineInvocation(
        string(context.event_id, "/potts"),
        :scheduled_potts_mcs,
        component.declaration,
        ProcessBigraphs.IntervalAdvance(
            context.start_time, context.end_time
        );
        structural_epoch = component.manifest.executable_fingerprint,
        inputs = projections,
        rng_context = context.rng,
        resource_authorization = (
            backend = :cpu,
            precision,
            residency = :host,
        ),
        expected_outputs = Tuple(
            entry.endpoint for entry in component.manifest.outputs
        ),
        expected_diagnostics = (:mcs, :accepted, :rejected),
    )
    transaction = ProcessBigraphs.execute_engine!(
        instance, invocation_value
    )
    transaction.status === :published ||
        throw(ArgumentError("Potts managed engine did not publish"))
    deltas = Tuple(
        ProcessBigraphs.emit(
            context,
            first(effect),
            ProcessBigraphs.ReplaceUpdate(),
            last(effect),
        )
        for effect in transaction.outcome.effects
    )
    return ProcessBigraphs.InvocationResult(
        deltas;
        continuation = transaction.outcome.continuation,
        diagnostics = (
            engine = component.declaration.id,
            publication = :committed,
            mcs = instance.published.t,
        ),
    )
end

end
