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
    state isa MembranePropertyState && return :membrane_property
    state isa DelayStateStorage && return :delay_state
    state isa EventRuntimeState && return :continuous_event
    return Symbol(nameof(typeof(state)))
end

function _capability_for_process(process)
    process isa SiteDynamics && return :site_dynamics
    process isa HistorySample && return :cell_history
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

function coupled_backend_report(plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities)
    capabilities = _coupled_capability_set(plan, state)
    cpu = backend.family === CPUFamily
    activity_gpu = _gpu_activity_qualified(plan, state, backend)
    rows = Tuple(CoupledCapabilityRow(
        capability, backend.family,
        cpu ? :qualified_reference :
        activity_gpu ? :qualified_gpu_native : :unsupported,
        cpu ? "phase14-cpu-reference-conformance-v1" :
        activity_gpu ? "phase14-wortel-gpu-native-qualification-v1" :
        "no exact Phase 14 real-hardware qualification",
        cpu ? "supported by the sequential CPU reference path" :
        activity_gpu ?
        "qualified for the Float32 backend-resident Wortel Act slice" :
        "explicitly Unsupported for this law/storage/backend combination")
        for capability in capabilities)
    return CoupledBackendReport(
        backend.family, rows,
        all(row -> row.status in (
            :qualified_reference, :qualified_gpu_native), rows))
end

function preflight_coupled(plan::MCSPlan, state::CoupledState,
        backend::BackendCapabilities)
    report = coupled_backend_report(plan, state, backend)
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
            by = pair -> String(first(pair)))))
    return CoupledInspectionReport(
        integrator.mcs, global_time(integrator),
        integrator.stage, integrator.stage_local_mcs,
        integrator.semantic_model === nothing ? nothing :
            _semantic_record(integrator.semantic_model),
        processes, blocks, observations,
        integrator.terminal_error !== nothing)
end
