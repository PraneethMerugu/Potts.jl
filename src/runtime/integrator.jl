struct PottsSavePolicy{T <: Tuple, O <: Tuple}
    saveat::T
    save_start::Bool
    save_end::Bool
    save_everystep::Bool
    observables::O
    maxiters::Int
    progress::Bool
    progress_steps::Int
    verbose::Bool
end

mutable struct PottsIntegrator{P, A, B, L, R, S, C, N, F, Q}
    prob::P
    alg::A
    backend::B
    scalar_type::DataType
    plan::L
    runtime::R
    t::Int
    u::S
    policy::PottsSavePolicy
    callbacks::C
    callbacks_initialized::Bool
    callbacks_finalized::Bool
    saved_times::Vector{Int}
    saved_states::Vector{S}
    parameter_history::Vector{Pair{Int, Any}}
    pending_parameters::Any
    iterations::Int
    terminated::Bool
    retcode::SciMLBase.ReturnCode.T
    failure_report::Any
    native_states::N
    native_profiles::F
    capability_report::Q
end

function _normalize_saveat(saveat, tspan)
    saveat === nothing && return ()
    saveat isa Integer && begin
        saveat > 0 || throw(ArgumentError("saveat cadence must be positive"))
        return Tuple((tspan[1] + saveat):saveat:tspan[2])
    end
    all(value -> value isa Integer, saveat) ||
        throw(ArgumentError("saveat contains a noninteger MCS"))
    values = Tuple(Int(value) for value in saveat)
    all(value -> tspan[1] <= value <= tspan[2], values) ||
        throw(ArgumentError("saveat lies outside the problem time span"))
    length(unique(values)) == length(values) ||
        throw(ArgumentError("saveat boundaries must be unique"))
    return Tuple(sort(collect(values)))
end

function _normalize_observables(plan::_PottsExecutionPlan, observables)
    requested = Tuple(_state_name(value) for value in observables)
    declared = Set{Symbol}((
        :ownership, :cell_kinds, :cell_generations, :volumes,
    ))
    union!(declared, entry.name for entry in plan.reports.states)
    union!(declared, entry.name for entry in plan.reports.relationship_states)
    union!(declared, value.name for value in plan.observations)
    unknown = setdiff(Set(requested), declared)
    isempty(unknown) || throw(ArgumentError(
        "unknown scheduled observation$(length(unknown) == 1 ? "" : "s"): " *
        join(string.(sort!(collect(unknown))), ", ")
    ))
    return requested
end

function _save_policy(
        problem::PottsProblem,
        plan::_PottsExecutionPlan;
        saveat = (),
        save_start::Bool = true,
        save_end::Bool = true,
        save_everystep::Bool = false,
        observables = (),
        maxiters::Integer = problem.tspan[2] - problem.tspan[1],
        progress::Bool = false,
        progress_steps::Integer = 1,
        verbose::Bool = true,
        kwargs...,
    )
    isempty(kwargs) || throw(ArgumentError(
        "unsupported Potts solve control$(length(kwargs) == 1 ? "" : "s"): " *
        join(string.(keys(kwargs)), ", ")
    ))
    maxiters >= 0 || throw(ArgumentError("maxiters must be nonnegative"))
    progress_steps > 0 || throw(ArgumentError("progress_steps must be positive"))
    return PottsSavePolicy(
        _normalize_saveat(saveat, problem.tspan),
        save_start,
        save_end,
        save_everystep,
        _normalize_observables(plan, observables),
        Int(maxiters),
        progress,
        Int(progress_steps),
        verbose,
    )
end

function _normalize_callbacks(callback)
    callbacks = SciMLBase.CallbackSet(callback)
    isempty(callbacks.continuous_callbacks) || throw(ArgumentError(
        "Potts time is discrete integer MCS; continuous callbacks are unsupported"
    ))
    return callbacks
end

_callbacks_empty(integrator::PottsIntegrator) =
    isempty(integrator.callbacks.discrete_callbacks)

function _named_runtime_observations(runtime, plan, requested_names)
    requested = Set(requested_names)
    pairs = Pair{Symbol, Any}[]
    for entry in plan.observations
        entry.name in requested || continue
        push!(pairs, entry.name => _evaluate_observation(entry.evaluator, runtime))
    end
    names = Tuple(first(pair) for pair in pairs)
    return NamedTuple{names}(Tuple(last(pair) for pair in pairs))
end

function _current_saved_state(integrator::PottsIntegrator)
    snapshot = CorePotts.program_snapshot(integrator.runtime)
    observations = _named_runtime_observations(
        integrator.runtime,
        integrator.plan,
        integrator.policy.observables,
    )
    return _saved_state(
        integrator.plan,
        snapshot,
        observations,
        (entry.name for entry in integrator.plan.observations),
        integrator.native_states,
    )
end

function _save_current!(
        integrator::PottsIntegrator;
        allow_duplicate::Bool = false,
    )
    if !allow_duplicate && !isempty(integrator.saved_times) &&
            last(integrator.saved_times) == integrator.t
        return integrator
    end
    state = _current_saved_state(integrator)
    push!(integrator.saved_times, integrator.t)
    push!(integrator.saved_states, state)
    integrator.u = state
    return integrator
end

function _save_due(integrator::PottsIntegrator)
    policy = integrator.policy
    integrator.t in policy.saveat && return true
    policy.save_everystep && return true
    policy.save_end && integrator.t == integrator.prob.tspan[2] && return true
    return false
end

function _request_integrator_settlement!(
        integrator::PottsIntegrator,
        reason::CorePotts.BackendSPI.ProgramSettlementReason,
    )
    integrator.runtime.settled && return nothing
    CorePotts.BackendSPI.supports_queued_program_execution(integrator.runtime) ||
        throw(ArgumentError("the unsettled runtime has no qualified settlement path"))
    start_mcs = integrator.t
    receipt = CorePotts.BackendSPI.settle_program!(
        integrator.runtime,
        CorePotts.BackendSPI.ProgramSettlementRequest(
            reason; full_snapshot = true
        ),
    )
    failure_report = CorePotts.program_failure_report(integrator.runtime)
    if failure_report === nothing
        integrator.iterations += integrator.runtime.mcs - start_mcs
    else
        integrator.iterations += max(1, failure_report.mcs - start_mcs)
        integrator.failure_report = failure_report
        integrator.retcode = SciMLBase.ReturnCode.Failure
    end
    integrator.t = integrator.runtime.mcs
    integrator.u = _current_saved_state(integrator)
    return receipt
end

SciMLBase.derivative_discontinuity!(::PottsIntegrator, ::Bool) = nothing

function _initialize_callbacks!(integrator::PottsIntegrator)
    integrator.callbacks_initialized && return integrator
    for callback in integrator.callbacks.discrete_callbacks
        callback.initialize(callback, integrator.u, integrator.t, integrator)
    end
    integrator.callbacks_initialized = true
    integrator.u = _current_saved_state(integrator)
    return integrator
end

function _run_callbacks!(integrator::PottsIntegrator)
    _callbacks_empty(integrator) && return integrator
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.HostCallbackSettlement
    )
    runtime_before = integrator.runtime
    parameters_before = copy(integrator.runtime.parameters)
    history_length = length(integrator.parameter_history)
    pending_before = integrator.pending_parameters === nothing ? nothing :
                     copy(integrator.pending_parameters)
    saved_length = length(integrator.saved_times)
    terminated_before = integrator.terminated
    try
        for callback in integrator.callbacks.discrete_callbacks
            condition = callback.condition(
                integrator.u, integrator.t, integrator
            )
            condition isa Bool || throw(ArgumentError(
                "a Potts discrete callback condition must return Bool"
            ))
            condition || continue
            callback.save_positions[1] &&
                _save_current!(integrator; allow_duplicate = true)
            callback.affect!(integrator)
            integrator.u = _current_saved_state(integrator)
            callback.save_positions[2] &&
                _save_current!(integrator; allow_duplicate = true)
            integrator.terminated && break
        end
    catch error
        # Public callback mutations are transactional at one settled MCS
        # boundary.  In particular, a later failing callback cannot leave an
        # earlier setp! or save_positions effect half-published.
        integrator.runtime = runtime_before
        CorePotts.update_program_parameters!(integrator.runtime, parameters_before)
        resize!(integrator.parameter_history, history_length)
        integrator.pending_parameters = pending_before
        resize!(integrator.saved_times, saved_length)
        resize!(integrator.saved_states, saved_length)
        integrator.terminated = terminated_before
        integrator.u = _current_saved_state(integrator)
        integrator.retcode = SciMLBase.ReturnCode.Failure
        integrator.failure_report = error
        rethrow()
    end
    return integrator
end

function _finalize_callbacks!(integrator::PottsIntegrator)
    integrator.callbacks_finalized && return integrator
    try
        for callback in integrator.callbacks.discrete_callbacks
            callback.finalize(callback, integrator.u, integrator.t, integrator)
        end
    catch error
        integrator.retcode = SciMLBase.ReturnCode.Failure
        integrator.failure_report = error
        rethrow()
    finally
        integrator.callbacks_finalized = true
    end
    return integrator
end

function _materialize_integrator(
        problem::PottsProblem,
        algorithm::AbstractPottsAlgorithm,
        backend::AbstractPottsBackend,
        scalar_type::Type{<:AbstractFloat};
        checkpoint = nothing,
        callback = nothing,
        native_profiles = nothing,
        solve_controls...,
    )
    plan = _lower_execution_plan(problem.system, algorithm, backend, scalar_type)
    capability = plan.reports.capability
    CorePotts.BackendSPI.capability_authorizes_execution(capability) ||
        throw(CorePotts.BackendSPI.ProgramCapabilityError(:init, capability))
    profiles = _normalize_native_profiles(problem.system, native_profiles)
    callbacks = _normalize_callbacks(callback)
    isempty(profiles) || isempty(callbacks.discrete_callbacks) ||
        throw(NativeCapabilityError(
            (:runtime, :native_components),
            :outer_callbacks,
            "G5H-3 does not admit outer Potts callbacks with native components because callback identity and state are not in the capability key or checkpoint",
        ))
    _native_runtime_preflight(problem, algorithm, backend, profiles)
    parameters = _normalize_parameters(plan, problem.p)
    policy = _save_policy(problem, plan; solve_controls...)

    core_initial = _core_initial_state(
        plan,
        _problem_initial_state(problem),
        problem.seed,
        problem.replica,
        problem.repeat,
    )
    initial_descriptor =
        CorePotts.BackendSPI.program_initial_descriptor_state(core_initial)
    prepared_native = _initial_native_states!(
        problem, plan, initial_descriptor, profiles
    )
    if !isempty(prepared_native) && initial_descriptor !== nothing
        core_initial = CorePotts.BackendSPI.with_program_initial_descriptor_state(
            core_initial, initial_descriptor
        )
    end
    _require_native_replay_evidence(problem.system, profiles)
    capability_report = _require_runtime_capability(
        _compose_runtime_capability(
            problem,
            plan,
            algorithm,
            backend,
            scalar_type,
            profiles,
            prepared_native,
            callbacks,
            policy,
        )
    )

    host_runtime, history, native_states = if checkpoint === nothing
        runtime = CorePotts.initialize_program(
            plan.core_program,
            core_initial,
            _parameter_buffer(parameters),
            problem.seed,
            problem.replica;
            repeat = problem.repeat,
            initial_mcs = problem.tspan[1],
        )
        runtime,
        Pair{Int, Any}[problem.tspan[1] => parameters],
        prepared_native
    else
        _restore_checkpoint_materialization(
            problem, plan, checkpoint, profiles, capability_report
        )
    end
    runtime = _adapt_runtime_backend(plan.core_program.backend, host_runtime)
    initial_state = _saved_state(
        plan,
        CorePotts.program_snapshot(runtime),
        _named_runtime_observations(runtime, plan, policy.observables),
        (entry.name for entry in plan.observations),
        native_states,
    )
    integrator = PottsIntegrator(
        problem,
        algorithm,
        backend,
        scalar_type,
        plan,
        runtime,
        runtime.mcs,
        initial_state,
        policy,
        callbacks,
        false,
        false,
        Int[],
        typeof(initial_state)[],
        history,
        nothing,
        0,
        false,
        SciMLBase.ReturnCode.Default,
        nothing,
        native_states,
        profiles,
        capability_report,
    )
    _initialize_callbacks!(integrator)
    policy.save_start && _save_current!(integrator)
    return integrator
end

function init(
        problem::PottsProblem,
        algorithm::AbstractPottsAlgorithm;
        backend::AbstractPottsBackend = CPUBackend(),
        scalar_type::Type{<:AbstractFloat} = Float64,
        kwargs...,
    )
    return _materialize_integrator(
        problem, algorithm, backend, scalar_type; kwargs...
    )
end

init(problem::PottsProblem; alg = SequentialCPM(), kwargs...) =
    init(problem, alg; kwargs...)

function _step_coupled!(integrator::PottsIntegrator)
    transaction = CorePotts.BackendSPI.stage_program_mcs!(integrator.runtime)
    if transaction === nothing
        integrator.failure_report =
            CorePotts.program_failure_report(integrator.runtime)
        integrator.retcode = SciMLBase.ReturnCode.Failure
        integrator.iterations += 1
        return integrator
    end
    candidates = nothing
    try
        snapshot = CorePotts.BackendSPI.program_step_snapshot(transaction)
        components = scheduled_native_components(integrator.prob.system)
        has_ports = _native_components_have_ports(components)
        descriptor_state = has_ports ?
            CorePotts.BackendSPI.program_snapshot_descriptor_state(snapshot) :
            nothing
        candidates, updates = _advance_native_candidates(
            integrator, descriptor_state, integrator.t + 1
        )
        _publish_native_outputs!(integrator.plan, descriptor_state, updates)
        has_ports && CorePotts.BackendSPI.stage_program_descriptor_state!(
            transaction, descriptor_state
        )
        CorePotts.BackendSPI.prevalidate_program_step_transaction(transaction)
    catch error
        CorePotts.BackendSPI.abort_program_step!(transaction)
        integrator.retcode = SciMLBase.ReturnCode.Failure
        integrator.failure_report = error
        integrator.iterations += 1
        rethrow()
    end
    # All external work and validation is complete. These two publications are
    # assignment-only and cannot invoke user or solver code.
    CorePotts.BackendSPI.publish_program_step_transaction!(transaction)
    integrator.native_states = candidates
    integrator.t = integrator.runtime.mcs
    integrator.iterations += 1
    if any(state -> state.retcode === SciMLBase.ReturnCode.Terminated, candidates)
        integrator.terminated = true
        integrator.retcode = SciMLBase.ReturnCode.Terminated
    end
    return integrator
end

function step!(integrator::PottsIntegrator)
    integrator.terminated &&
        throw(ArgumentError("cannot step a terminated PottsIntegrator"))
    integrator.retcode == SciMLBase.ReturnCode.Default || throw(ArgumentError(
        "cannot step a PottsIntegrator after a terminal solver result"
    ))
    integrator.t < integrator.prob.tspan[2] ||
        throw(ArgumentError("cannot advance beyond the PottsProblem horizon"))
    integrator.iterations < integrator.policy.maxiters || begin
        integrator.retcode = SciMLBase.ReturnCode.MaxIters
        return integrator
    end
    coupled = !isempty(integrator.native_states)
    if coupled
        _step_coupled!(integrator)
        integrator.retcode == SciMLBase.ReturnCode.Failure && return integrator
    else
        CorePotts.advance_mcs!(integrator.runtime)
    end
    failure_report = CorePotts.program_failure_report(integrator.runtime)
    if failure_report !== nothing
        integrator.failure_report = failure_report
        integrator.retcode = SciMLBase.ReturnCode.Failure
        integrator.iterations += 1
        return integrator
    end
    integrator.t = integrator.runtime.mcs
    coupled || (integrator.iterations += 1)
    integrator.u = _current_saved_state(integrator)
    _run_callbacks!(integrator)
    _save_due(integrator) && _save_current!(integrator)
    return integrator
end

SciMLBase.check_error(integrator::PottsIntegrator) = integrator.retcode

function terminate!(integrator::PottsIntegrator)
    integrator.terminated = true
    integrator.retcode = SciMLBase.ReturnCode.Terminated
    return integrator
end

function _integrator_stats(integrator::PottsIntegrator)
    runtime = integrator.runtime
    candidate_attempts = runtime.accepted + runtime.null_attempts +
                         runtime.constraint_rejections + runtime.energy_rejections
    return PottsStats(
        integrator.iterations,
        candidate_attempts,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    )
end

function runtime_statistics(integrator::PottsIntegrator)
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.StatisticsSettlement
    )
    return _integrator_stats(integrator)
end

function native_state(integrator::PottsIntegrator, path)
    component = _native_component_by_path(integrator.prob.system, path)
    state = _native_state_by_path(integrator.native_states, path)
    return native_state_view(component, state)
end

function native_value(integrator::PottsIntegrator, path, symbolic)
    component = _native_component_by_path(integrator.prob.system, path)
    state = _native_state_by_path(integrator.native_states, path)
    return native_component_value(component, state, symbolic)
end

function _set_runtime_parameters!(integrator::PottsIntegrator, values)
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexMutationSettlement
    )
    parameters = _normalize_parameters(integrator.plan, values)
    CorePotts.update_program_parameters!(
        integrator.runtime, _parameter_buffer(parameters)
    )
    push!(integrator.parameter_history, integrator.t => parameters)
    integrator.u = _current_saved_state(integrator)
    return parameters
end
