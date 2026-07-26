struct CoupledCapabilityRow
    capability::Symbol
    backend::BackendFamily
    status::Symbol
    evidence::String
    diagnostic::String
end

struct CoupledBackendReport
    backend::BackendFamily
    rows::Tuple
    executable::Bool
end

struct UnsupportedCoupledCapabilities <: Exception
    backend::BackendFamily
    rows::Tuple
end
function Base.showerror(io::IO, error::UnsupportedCoupledCapabilities)
    capabilities = join(
        (String(row.capability) for row in error.rows), ", ")
    print(io, "backend ", error.backend,
        " does not support Phase 14 coupled capabilities: ",
        capabilities,
        ". Remove or replace the unqualified declarations; Phase 13 backend qualification ",
        "does not imply coupled-state support.")
end

function _plan_processes(plan::MCSPlan)
    if plan.timeline === nothing
        return Tuple(invocation_process(invocation)
            for entry in plan.entries if entry isa CoupledPhase
            for invocation in entry.invocations)
    end
    return Tuple(_scheduled_process(entry)
        for entry in plan.timeline.entries
        if entry isa Union{
            ScheduledSystem, ScheduledEvent, ScheduledProcess})
end

function _capability_for_state(state)
    state isa SitePropertyState && return :site_state
    state isa CellHistoryState && return :cell_history
    state isa RelationshipState && return :relationships
    state isa EvolvingFieldState && return :evolving_field
    state isa ContinuousSystemState && return :continuous_system
    state isa GlobalPropertyState && return :global_property
    state isa FieldExchangeState && return :field_exchange_state
    state isa AffineCellRuntime && return :affine_cell_runtime
    state isa MembranePropertyState && return :membrane_property
    state isa DelayStateStorage && return :delay_state
    state isa EventRuntimeState && return :continuous_event
    return Symbol(nameof(typeof(state)))
end

function _capability_for_process(process)
    process isa SiteDynamics && return :site_dynamics
    process isa HistorySample && return :cell_history
    process isa Union{
        CentroidHistorySample,
        CentroidHistorySampleExecution} &&
        return :centroid_history_sample
    process isa Union{
        HistoryDisplacementDirection,
        HistoryDisplacementDirectionExecution} &&
        return :history_displacement_direction
    process isa Union{
        NeighborPolarityAlignment,
        NeighborPolarityAlignmentExecution} &&
        return :neighbor_polarity_alignment
    process isa Union{
        HillVectorForce,
        HillVectorForceExecution} &&
        return :hill_vector_force
    process isa ElasticLinkRetuneExecution &&
        return :relationship_retune
    process isa RelationshipCleanupExecution &&
        return :relationship_cleanup
    process isa RelationshipDynamics && return :relationship_dynamics
    process isa FieldDynamics && return :field_dynamics
    process isa FieldExchange && return :field_exchange
    process isa ContinuousSystem && return :continuous_system
    process isa DelayState && return :delay_state
    process isa ContinuousEvent && return :continuous_event
    process isa SymbolMap && return :symbol_mapping
    return Symbol(nameof(typeof(process)))
end

function _coupled_capability_set(plan::MCSPlan, state::CoupledState)
    capabilities = Symbol[]
    plan.timeline === nothing || push!(capabilities, :multirate_schedule)
    for family in (
            state.site_states, state.histories, state.relationships,
            state.fields, state.globals, state.membranes, state.delays)
        append!(capabilities, map(_capability_for_state, family))
    end
    append!(capabilities, map(_capability_for_process, _plan_processes(plan)))
    observation = only(entry for entry in plan.entries
        if entry isa ObservationPhase)
    isempty(observation.observations) ||
        push!(capabilities, :paper_observation)
    sort!(unique!(capabilities); by = String)
    return Tuple(capabilities)
end

function _activity_gpu_storage_matches(state::CoupledState,
        backend::BackendCapabilities, plan::MCSPlan)
    length(state.site_states) == 1 || return false
    all(isempty, (state.histories, state.relationships, state.fields,
        state.globals, state.membranes, state.delays)) || return false
    site_state = only(state.site_states)
    declaration = site_state.declaration
    declaration.name === :activity || return false
    declaration.initial isa FillSites || return false
    declaration.invariant isa ActivityBounds || return false
    declaration.ownership isa AcceptedCopyManaged || return false
    eltype(site_state.values) === Float32 || return false
    actual = try
        backend_capabilities(
            KernelAbstractions.get_backend(site_state.values))
    catch
        return false
    end
    actual.family === backend.family || return false

    processes = _plan_processes(plan)
    length(processes) == 1 || return false
    process = only(processes)
    process isa SiteDynamics || return false
    process.property === :activity || return false
    process.update isa SaturatingSubtract{Float32} || return false

    potts_entry = only(entry for entry in plan.entries
        if entry isa PottsAttempts)
    length(potts_entry.on_accept) == 1 || return false
    accepted = only(potts_entry.on_accept)
    accepted.property === :activity || return false
    accepted.when isa GainingCellCopy || return false
    accepted.gained isa SetTo{Float32} || return false

    observation_entry = only(entry for entry in plan.entries
        if entry isa ObservationPhase)
    length(observation_entry.observations) == 1 || return false
    summary = only(observation_entry.observations).observable
    summary isa ActivitySummary || return false
    summary.property === :activity || return false
    summary_backend = try
        backend_capabilities(KernelAbstractions.get_backend(summary.total))
    catch
        return false
    end
    summary_count_backend = try
        backend_capabilities(
            KernelAbstractions.get_backend(summary.active_count))
    catch
        return false
    end
    return summary_backend.family === backend.family &&
           summary_count_backend.family === backend.family
end

function _gpu_activity_qualified(plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities)
    backend.family in (MetalFamily, AMDGPUFamily) || return false
    supports(backend, QualifiedBackendCapability()) || return false
    supports(backend, FunctionalBackendCapability()) || return false
    supports(backend, OrderedLaunchCapability()) || return false
    supports(backend, SemanticRNGCapability(v"1.0.0")) || return false
    return _activity_gpu_storage_matches(state, backend, plan)
end

const _WANG_G3C_PHASES_V1 = (
    :secretome_field_solve,
    :sample_centroids,
    :update_self_polarity,
    :secretome_uptake,
    :intracellular_dynamics,
    :retune_focal_relationships,
    :align_neighbor_polarity,
    :update_protrusion,
    :cleanup_relationships,
)

const _WANG_G3C_PROCESSES_V1 = (
    (:wang_secretome_dynamics, FieldDynamics),
    (:wang_centroid_sample, CentroidHistorySampleExecution),
    (:wang_history_direction, HistoryDisplacementDirectionExecution),
    (:wang_secretome_uptake, FieldExchange),
    (:wang_rac_dynamics, AffineCellAdvance),
    (:wang_focal_retune, ElasticLinkRetuneExecution),
    (:wang_neighbor_alignment, NeighborPolarityAlignmentExecution),
    (:wang_protrusion_force, HillVectorForceExecution),
    (:wang_relationship_cleanup, RelationshipCleanupExecution),
)

"""
Return every heap-backed array in a CorePotts runtime tree.

Static arrays are descriptor values and deliberately do not count as storage
leaves. The walk is host-side preflight only; it never enters device code.
"""
function _coupled_array_leaves(value)
    isbitstype(typeof(value)) && return ()
    value isa AbstractArray && return (value,)
    if value isa Union{Tuple, NamedTuple}
        return mapreduce(
            _coupled_array_leaves, (left, right) -> (left..., right...),
            value; init = ())
    end
    parentmodule(typeof(value)) === (@__MODULE__) || return ()
    return mapreduce(
        index -> _coupled_array_leaves(getfield(value, index)),
        (left, right) -> (left..., right...),
        1:fieldcount(typeof(value)); init = ())
end

function _coupled_tree_backend_valid(
        plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities)
    arrays = (
        _coupled_array_leaves(plan)...,
        _coupled_array_leaves(state)...,
    )
    isempty(arrays) && return false
    return all(arrays) do array
        isbitstype(eltype(array)) || return false
        actual = try
            backend_capabilities(
                KernelAbstractions.get_backend(array))
        catch
            return false
        end
        actual.family === backend.family
    end
end

function _wang_g3c_state_matches(state::CoupledState)
    isempty(state.site_states) || return false
    length(state.histories) == 1 || return false
    length(state.relationships) == 1 || return false
    length(state.fields) == 1 || return false
    length(state.globals) == 2 || return false
    all(isempty, (state.membranes, state.delays)) || return false

    history = only(state.histories)
    history isa CellHistoryState || return false
    history.declaration.name === :wang_centroid_history || return false
    history.declaration.length == UInt32(5) || return false
    eltype(history.values) === SVector{2, Float32} || return false

    relationships = only(state.relationships)
    relationships isa RelationshipState || return false
    relationships.declaration.name === :wang_junctions || return false
    relationships.declaration.maximum_degree == UInt32(4) || return false
    length(relationships.endpoint_a) == 16 || return false
    relationships.payload isa ElasticLinkColumns{Float32} || return false

    field = only(state.fields)
    field isa EvolvingFieldState || return false
    field.name === :wang_secretome || return false
    eltype(field.values) === Float32 || return false
    ndims(field.values) == 2 || return false
    size(field.values, 1) == size(field.values, 2) || return false
    size(field.values, 1) >= 32 || return false
    field.boundary isa PeriodicFieldBoundary || return false

    exchange = _state_by_name(state.globals, :uptake_multiplier)
    exchange isa FieldExchangeState || return false
    eltype(exchange.value) === Float32 || return false
    eltype(exchange.workspace.raw_totals) === Float32 || return false
    rac = _state_by_name(state.globals, :wang_rac_dynamics)
    rac isa AffineCellRuntime || return false
    eltype(rac.workspace.candidate_state) === Float32 || return false
    return true
end

function _wang_g3c_plan_matches(plan::MCSPlan)
    plan.timeline === nothing || return false
    phases = Tuple(
        entry.name for entry in plan.entries
        if entry isa CoupledPhase)
    phases == _WANG_G3C_PHASES_V1 || return false

    processes = _plan_processes(plan)
    length(processes) == length(_WANG_G3C_PROCESSES_V1) ||
        return false
    for (process, (name, family)) in
            zip(processes, _WANG_G3C_PROCESSES_V1)
        process isa family || return false
        component_identity(process).key === name || return false
    end

    field = processes[1]
    field.law isa ReactionDiffusion{Float32} || return false
    field.law.diffusion == 1.0f0 || return false
    field.law.decay == 0.0f0 || return false
    field.method isa FixedStep{ExplicitEuler} || return false
    field.method.substeps == UInt32(5) || return false
    field.clock isa ContinuousClock{Float32} || return false
    field.clock.per_mcs == 1.0f0 || return false
    length(field.post_substep) == 1 || return false
    constraint = only(field.post_substep)
    constraint isa ConstantConcentration || return false
    constraint.scope === :medium || return false
    constraint.value == 1.0f0 || return false

    exchange = processes[4]
    exchange.calibration isa MaximumCalibration{Float32} || return false
    exchange.calibration.numerator == 4.0f0 || return false
    length(exchange.sinks) == 1 || return false
    sink = only(exchange.sinks)
    sink isa Uptake || return false
    sink.scope === :cells || return false
    sink.maximum == 1.0f0 || return false
    sink.relative_rate == 0.0025f0 || return false
    sink.output === :sensed_secretome || return false

    affine = processes[5]
    affine isa AffineCellAdvance || return false
    affine.decay == 0.1f0 || return false
    affine.duration == 2880.0f0 || return false

    observation = only(entry for entry in plan.entries
        if entry isa ObservationPhase)
    Tuple(item.name for item in observation.observations) ==
        (:wang_cell_records, :wang_geometry) || return false
    table = first(observation.observations).observable
    table isa BoundedCellTableObservation || return false
    length(table.workspace.present) == 2 || return false
    return true
end

function _wang_g3c_gpu_qualified(
        plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities; potts = nothing)
    backend.family in (MetalFamily, AMDGPUFamily) || return false
    supports(backend, QualifiedBackendCapability()) || return false
    supports(backend, FunctionalBackendCapability()) || return false
    supports(backend, OrderedLaunchCapability()) || return false
    supports(backend, SemanticRNGCapability(v"1.0.0")) || return false
    _wang_g3c_state_matches(state) || return false
    _wang_g3c_plan_matches(plan) || return false
    _coupled_tree_backend_valid(plan, state, backend) || return false
    if potts !== nothing
        potts isa ScientificPottsIntegrator || return false
        potts.algorithm isa SequentialCPM{Float32} || return false
        scientific_storage_valid(potts.state) || return false
        potts.plan.capabilities.family === backend.family || return false
    end
    return true
end

function coupled_backend_report(plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities; potts = nothing)
    capabilities = _coupled_capability_set(plan, state)
    cpu = backend.family === CPUFamily
    activity_gpu = _gpu_activity_qualified(plan, state, backend)
    wang_gpu = _wang_g3c_gpu_qualified(
        plan, state, backend; potts)
    rows = Tuple(CoupledCapabilityRow(
        capability, backend.family,
        cpu ? :qualified_reference :
        activity_gpu || wang_gpu ? :qualified_gpu_native : :unsupported,
        cpu ? "phase14-cpu-reference-conformance-v1" :
        activity_gpu ? "phase14-wortel-gpu-native-qualification-v1" :
        wang_gpu ? "phase14-wang-g3c-gpu-native-qualification-v1" :
        "no exact Phase 14 real-hardware qualification",
        cpu ? "supported by the sequential CPU reference path" :
        activity_gpu ?
        "qualified for the Float32 backend-resident Wortel Act slice" :
        wang_gpu ?
        "qualified for the exact Float32 Wang G3-C law/storage profile" :
        "explicitly Unsupported for this law/storage/backend combination")
        for capability in capabilities)
    return CoupledBackendReport(
        backend.family, rows,
        all(row -> row.status in (
            :qualified_reference, :qualified_gpu_native), rows))
end

function preflight_coupled(plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities; potts = nothing)
    report = coupled_backend_report(
        plan, state, backend; potts)
    unsupported = Tuple(row for row in report.rows
        if row.status === :unsupported)
    isempty(unsupported) ||
        throw(UnsupportedCoupledCapabilities(backend.family, unsupported))
    return report
end

struct CoupledSemanticManifest{P, S, B}
    schema_version::VersionNumber
    contract_versions::Phase14ContractVersions
    base_model_fingerprint::NTuple{32, UInt8}
    coupled_model_fingerprint::NTuple{32, UInt8}
    initial_state_fingerprint::NTuple{32, UInt8}
    plan::P
    state_schema::S
    backend::B
    continuation::Symbol
end

struct CoupledInspectionReport{M, P, B, O}
    completed_mcs::UInt64
    global_time
    protocol_stage::Union{Nothing, Symbol}
    stage_local_mcs::UInt64
    semantic_model::M
    processes::P
    state_blocks::B
    observations::O
    terminal::Bool
end

function coupled_model_fingerprint(integrator::CoupledIntegrator)
    return _coupled_model_fingerprint(
        integrator, _coupled_blocks(integrator.state))
end

function coupled_state_fingerprint(integrator::CoupledIntegrator)
    blocks = _coupled_blocks(integrator.state)
    return _coupled_state_digest(
        blocks, _protocol_position(integrator),
        _observation_schedule(integrator))
end

function coupled_manifest(integrator::CoupledIntegrator)
    blocks = _coupled_blocks(integrator.state)
    schema = Tuple((
        family = block.family,
        name = block.name,
        contract = block.contract,
        version = block.version,
        metadata = block.metadata,
        required = block.required) for block in blocks)
    backend = coupled_backend_report(
        integrator.plan, integrator.state,
        integrator.potts.plan.capabilities)
    return CoupledSemanticManifest(
        COUPLED_CHECKPOINT_SCHEMA_VERSION,
        phase14_contract_versions(),
        scientific_model_fingerprint(integrator.potts),
        _coupled_model_fingerprint(integrator, blocks),
        integrator.initial_state_fingerprint,
        _semantic_record(something(
            integrator.semantic_model, integrator.plan)),
        schema, backend, :exact_completed_mcs)
end

function inspect_coupled(integrator::CoupledIntegrator)
    processes = Tuple((
        identity = _semantic_record(process),
        reads = process_reads(process),
        writes = process_writes(process))
        for process in _plan_processes(integrator.plan))
    blocks = Tuple((
        family = block.family, name = block.name,
        contract = block.contract, version = block.version,
        metadata = block.metadata)
        for block in _coupled_blocks(integrator.state))
    observations = (
        completed_mcs = integrator.observations.completed_mcs,
        last_published = Tuple(sort!(collect(
            integrator.observations.last_published);
            by = pair -> String(first(pair)))),
        publication_epochs = Tuple(sort!(collect(
            integrator.observations.publication_epochs);
            by = pair -> String(first(pair)))))
    return CoupledInspectionReport(
        integrator.mcs, global_time(integrator),
        integrator.stage, integrator.stage_local_mcs,
        integrator.semantic_model === nothing ? nothing :
            _semantic_record(integrator.semantic_model),
        processes, blocks, observations,
        integrator.terminal_error !== nothing)
end
