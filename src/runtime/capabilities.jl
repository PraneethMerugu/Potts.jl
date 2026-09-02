# Exact Potts-level capability composition.  Scheduled systems expose
# requirements; only a concrete runtime profile can produce a support row.

"""Complete immutable identity of a Potts runtime capability request."""
struct PottsCapabilityKey{C, N <: Tuple, E, O, S, R}
    core::C
    scheduled_fingerprint::String
    native::N
    events::E
    outer_events::O
    observation_save::S
    checkpoint::Symbol
    replay::R
    fingerprint::String
end

"""Preflight support result, reason, replay class, and backend evidence."""
struct PottsCapabilityReport{K <: PottsCapabilityKey, E}
    key::K
    status::CorePotts.BackendSPI.CapabilitySupportStatus
    exact_replay::Bool
    reason::String
    evidence::E
end

_capability_evidence_identity(authority, suite, revision, profile_fingerprint) =
    (; authority, suite, revision, profile_fingerprint)

function _native_event_contract(component::ScheduledNativeComponent)
    original = native_original_system(component)
    scheduled = native_scheduled_system(component)
    continuous = ModelingToolkitBase.continuous_events(original)
    discrete = ModelingToolkitBase.discrete_events(original)
    scheduled_continuous = ModelingToolkitBase.continuous_events(scheduled)
    scheduled_discrete = ModelingToolkitBase.discrete_events(scheduled)
    retained = length(continuous) == length(scheduled_continuous) &&
        length(discrete) == length(scheduled_discrete)
    event_free = isempty(continuous) && isempty(discrete)
    admitted = retained && event_free
    reason = if !retained
        "upstream structural compilation changed recursive native event counts"
    elseif event_free
        "native system has no events"
    else
        "native events are retained structurally, but coupled runtime profiles must be event-free because the pinned public API has no stable affect-classification accessors"
    end
    return (
        continuous = length(continuous),
        discrete = length(discrete),
        scheduled_continuous = length(scheduled_continuous),
        scheduled_discrete = length(scheduled_discrete),
        admitted,
        runtime_policy = event_free ? :event_free : :rejected_event_profile,
        structural_retention = retained ? :recursive_public_MTK_events :
            :event_count_mismatch,
        reason,
    )
end

function _host_capture_identity(value)
    if value === nothing || value === missing ||
            value isa Union{Bool, Number, Symbol, AbstractString, Enum,
                VersionNumber, DataType, Module}
        return (kind = :value, type = string(typeof(value)), value = repr(value))
    elseif ismutabletype(typeof(value))
        # Callback checkpointing is forbidden. For supported in-process
        # execution, bind the exact captured object identity without claiming
        # that it can be reconstructed in another process.
        return (
            kind = :process_local_object,
            type = string(typeof(value)),
            object_id = objectid(value),
        )
    elseif isstructtype(typeof(value))
        return (
            kind = :immutable_capture,
            type = string(typeof(value)),
            fields = Tuple(
                field => _host_capture_identity(getfield(value, field))
                for field in fieldnames(typeof(value))
            ),
        )
    end
    return (kind = :opaque, type = string(typeof(value)), value = repr(value))
end

function _host_callable_identity(callable)
    reflected_methods = try
        Tuple((
            module_name = string(method.module),
            file = string(method.file),
            line = method.line,
            signature = string(method.sig),
        ) for method in methods(callable))
    catch
        return nothing
    end
    captures = try
        Tuple(
            field => _host_capture_identity(getfield(callable, field))
            for field in fieldnames(typeof(callable))
        )
    catch
        return nothing
    end
    isempty(reflected_methods) && return nothing
    return (
        callable_type = string(typeof(callable)),
        methods = reflected_methods,
        captures,
    )
end

function _host_discrete_callback_identity(callback)
    identity = try
        (
            callback_type = string(typeof(callback)),
            condition = _host_callable_identity(callback.condition),
            affect = _host_callable_identity(callback.affect!),
            initialize = _host_callable_identity(callback.initialize),
            finalize = _host_callable_identity(callback.finalize),
            save_positions = Tuple(callback.save_positions),
            initialize_algorithm = _host_capture_identity(
                callback.initializealg
            ),
            saved_clock_partitions = _host_capture_identity(
                callback.saved_clock_partitions
            ),
            initialize_save_discretes = callback.initialize_save_discretes,
        )
    catch
        return nothing
    end
    any(field -> field === nothing, (
        identity.condition,
        identity.affect,
        identity.initialize,
        identity.finalize,
    )) && return nothing
    return _sha256_hex("potts-host-discrete-callback-v1", identity)
end

function _outer_event_fact(callbacks)
    continuous_count = length(callbacks.continuous_callbacks)
    discrete_count = length(callbacks.discrete_callbacks)
    empty = continuous_count == 0 && discrete_count == 0
    identities = Tuple(
        _host_discrete_callback_identity(callback)
        for callback in callbacks.discrete_callbacks
    )
    qualified = all(identity -> identity !== nothing, identities)
    mode = empty ? :none :
        continuous_count == 0 && qualified ?
            :imperative_host_discrete_callbacks :
            :unqualified_host_callbacks
    return (
        mode,
        continuous_count,
        discrete_count,
        callback_types = Tuple(
            string(typeof(callback))
            for callback in callbacks.discrete_callbacks
        ),
        callback_identities = identities,
        identity_codec = empty ? :not_applicable :
            qualified ? :process_local_code_and_capture_v1 : :unavailable,
        state_codec = empty ? :not_applicable : :unavailable,
        checkpoint = empty ? :admitted : :unsupported_callback_state,
    )
end

function _observation_save_fact(policy)
    return (
        observation_mode = isempty(policy.observables) ?
            :settled_default_state : :settled_named_observations,
        observables = policy.observables,
        evaluator_binding = :scheduled_system_fingerprint,
        saveat = policy.saveat,
        save_start = policy.save_start,
        save_end = policy.save_end,
        save_everystep = policy.save_everystep,
        maxiters = policy.maxiters,
        progress = policy.progress,
        progress_steps = policy.progress_steps,
        verbose = policy.verbose,
    )
end

function _mode_evidence(suite::Symbol, exact_replay::Bool, family::Symbol)
    return (
        status = CorePotts.BackendSPI.Supported,
        exact_replay,
        evidence = _capability_evidence_identity(
            :Potts,
            suite,
            v"1.0.0",
            _sha256_hex("potts-runtime-mode-family-v1", family),
        ),
    )
end

function _outer_event_evidence(fact)
    if fact.mode === :none && fact.continuous_count == 0 &&
            fact.discrete_count == 0 && fact.callback_identities == ()
        return _mode_evidence(
            :no_outer_event_mode,
            true,
            :no_outer_events,
        )
    elseif fact.mode === :imperative_host_discrete_callbacks &&
            fact.continuous_count == 0 && fact.discrete_count > 0 &&
            length(fact.callback_identities) == fact.discrete_count &&
            all(identity -> identity isa String,
                fact.callback_identities) &&
            fact.identity_codec === :process_local_code_and_capture_v1 &&
            fact.state_codec === :unavailable &&
            fact.checkpoint === :unsupported_callback_state
        return _mode_evidence(
            :host_discrete_callback_functional,
            false,
            :host_discrete_callback_protocol_v1,
        )
    end
    return nothing
end

function _observation_save_evidence(fact)
    fact.observation_mode in (
        :settled_default_state, :settled_named_observations
    ) || return nothing
    fact.observables isa Tuple &&
        all(observable -> observable isa Symbol, fact.observables) ||
        return nothing
    fact.evaluator_binding === :scheduled_system_fingerprint || return nothing
    fact.saveat isa Tuple &&
        all(boundary -> boundary isa Int, fact.saveat) || return nothing
    issorted(fact.saveat) && allunique(fact.saveat) || return nothing
    all(value -> value isa Bool, (
        fact.save_start,
        fact.save_end,
        fact.save_everystep,
        fact.progress,
        fact.verbose,
    )) || return nothing
    fact.maxiters isa Int && fact.maxiters >= 0 || return nothing
    fact.progress_steps isa Int && fact.progress_steps > 0 || return nothing
    return _mode_evidence(
        :settled_observation_save_policy,
        true,
        :settled_observation_save_policy_v1,
    )
end

function _native_algorithm_identity(profile::NativeSolveProfile)
    algorithm_type = typeof(profile.algorithm)
    algorithm_module = parentmodule(algorithm_type)
    package = _native_package_identity(algorithm_module)
    return (
        package = package.name,
        uuid = package.uuid,
        version = package.version,
        module_name = package.module_name,
        type = string(algorithm_type),
    )
end

function _native_profile_options_class(profile::NativeSolveProfile)
    names = Set(keys(profile.options))
    if names == Set((:adaptive, :dt)) &&
            profile.options.adaptive === false &&
            profile.options.dt isa Real && isfinite(profile.options.dt) &&
            profile.options.dt > 0
        return :fixed_step
    elseif names == Set((:adaptive, :dt, :maxiters)) &&
            profile.options.adaptive === false &&
            profile.options.dt isa Real && isfinite(profile.options.dt) &&
            profile.options.dt > 0 &&
            profile.options.maxiters isa Integer && profile.options.maxiters > 0
        return :fixed_step_bounded_failure
    elseif isempty(names)
        return :solver_defaults
    end
    return :unreviewed
end

function _native_logical_state_schema(state::NativeLogicalState)
    return (
        u = Tuple(typeof(value) for value in state.u),
        p = Tuple(typeof(value) for value in state.p),
        du = state.du === nothing ? nothing :
            Tuple(typeof(value) for value in state.du),
        time = typeof(state.t),
        retcode = typeof(state.retcode),
    )
end

function _native_logical_state_schema(state::NativeCellStatePool)
    return merge(
        _native_logical_state_schema(state.policy.template),
        (
            storage = :fixed_capacity_structure_of_arrays,
            capacity = length(state),
            lifecycle = nameof(typeof(getfield(state.policy, :division))),
        ),
    )
end

function _native_capability_fact(component, profile, state, evidence_row)
    declaration = getfield(component, :declaration)
    events = _native_event_contract(component)
    native_stack = applicable(_native_runtime_stack_identity, component) ?
        _native_runtime_stack_identity(component) : nothing
    replay_schema = applicable(_native_replay_schema, component) ?
        _native_replay_schema(component) :
        (family = :unreviewed, fingerprint = nothing)
    endpoints = Tuple((
        direction = endpoint.port isa NativeInput ? :input : :output,
        potts_kind = endpoint.potts_kind,
        value_type = native_value_type(endpoint),
    ) for endpoint in native_coupling_endpoints(component))
    return (
        path = native_component_path(component),
        family = nameof(typeof(native_family(declaration))),
        scope = nameof(typeof(getfield(declaration, :scope))),
        cadence = native_cadence_stride(declaration),
        clock = nameof(typeof(getfield(declaration, :time))),
        split = nameof(typeof(getfield(declaration, :split))),
        scheduled_fingerprint = native_scheduled_fingerprint(component).hex,
        native_stack,
        replay_schema,
        logical_state_schema = _native_logical_state_schema(state),
        algorithm = _native_algorithm_identity(profile),
        execution = profile.execution isa MetalNativeExecution ? (
            mode = :kernelabstractions_metal,
            width = profile.execution.width,
            transfer_boundary = :coupled_component_interval,
        ) : profile.execution isa BatchedNativeExecution ? (
            mode = :batched_cpu,
            width = profile.execution.width,
        ) : (
            mode = :serial,
            width = 1,
        ),
        profile_fingerprint = _native_profile_fingerprint(profile),
        options_class = _native_profile_options_class(profile),
        endpoints,
        events,
        initial_initialization =
            native_family(declaration) isa DAEComponent ?
            :MTK_problem_mapping_then_OverrideInit :
            :standard_MTK_problem_initialization,
        continuation_initialization =
            native_family(declaration) isa DAEComponent ?
            :logical_u_p_du_build_initializeprob_false_then_DefaultInit_CheckInit :
            :logical_u_p_build_initializeprob_false,
        logical_checkpoint = (:u, :p, :t, :du),
        requested_exact_replay = profile.exact_replay,
        evidence = evidence_row === nothing ? nothing : (
            authority = evidence_row.evidence.authority,
            suite = evidence_row.evidence.suite,
            revision = evidence_row.evidence.revision,
            profile_fingerprint =
                evidence_row.evidence.profile_fingerprint,
        ),
    )
end

function _minimum_capability_status(values)
    code = minimum(Int(value) for value in values)
    return CorePotts.BackendSPI.CapabilitySupportStatus(code)
end

function _compose_runtime_capability(
        problem::PottsProblem,
        plan::_PottsExecutionPlan,
        algorithm::AbstractPottsAlgorithm,
        backend::AbstractPottsBackend,
        scalar_type::Type{<:AbstractFloat},
        profiles,
        native_states,
        callbacks,
        policy,
    )
    core = plan.reports.capability
    components = scheduled_native_components(problem.system)
    length(components) == length(profiles) == length(native_states) ||
        error("native capability composition requires aligned components, profiles, and prepared logical states")
    native_rows = Tuple(
        applicable(_native_profile_evidence, component, profile) ?
            _native_profile_evidence(component, profile) : nothing
        for (component, profile) in zip(components, profiles)
    )
    facts = Tuple(
        _native_capability_fact(component, profile, state, evidence_row)
        for (component, profile, state, evidence_row) in
            zip(components, profiles, native_states, native_rows)
    )
    events = Tuple(fact.events for fact in facts)
    outer_events = _outer_event_fact(callbacks)
    observation_save = _observation_save_fact(policy)
    outer_event_row = _outer_event_evidence(outer_events)
    observation_save_row = _observation_save_evidence(observation_save)
    runtime_profile_admitted =
        (algorithm isa SequentialCPM && backend isa CPUBackend &&
            scalar_type === Float64 && all(profile ->
                profile.execution isa Union{
                    SerialNativeExecution, BatchedNativeExecution,
                }, profiles)) ||
        (algorithm isa CheckerboardSweepCPM && backend isa MetalBackend &&
            scalar_type === Float32 && all(profile ->
                profile.execution isa MetalNativeExecution, profiles))
    profile_shape_admitted =
        runtime_profile_admitted &&
        all(component -> begin
            declaration = getfield(component, :declaration)
            scope = getfield(declaration, :scope)
            endpoints = native_coupling_endpoints(component)
            scope isa Global ? all(endpoint ->
                (endpoint.potts_kind === :ModelState ||
                    endpoint.potts_kind === :FieldState &&
                    endpoint.port isa NativeFieldOutput) &&
                native_value_type(endpoint) <: Real, endpoints) :
            scope isa PerCell && all(endpoint ->
                endpoint.potts_kind in (:ModelState, :CellState) &&
                native_value_type(endpoint) <: Real, endpoints)
        end, components)
    native_statuses = isempty(components) ?
        (core.status,) :
        Tuple(
            profile_shape_admitted &&
                    (!profile.exact_replay ||
                        row !== nothing &&
                        row.status === CorePotts.BackendSPI.Supported) ?
                CorePotts.BackendSPI.Supported :
                CorePotts.BackendSPI.Unsupported
            for (profile, row) in zip(profiles, native_rows)
        )
    replay = isempty(components) ? core.key.replay :
        all(profile -> profile.exact_replay, profiles) ?
            CorePotts.BackendSPI.ExactConfigurationReplay :
            :functional_native_execution
    mode_statuses = (
        outer_event_row === nothing ? CorePotts.BackendSPI.Unsupported :
            outer_event_row.status,
        observation_save_row === nothing ? CorePotts.BackendSPI.Unsupported :
            observation_save_row.status,
    )
    status = _minimum_capability_status((
        core.status, native_statuses..., mode_statuses...
    ))
    exact_replay = status === CorePotts.BackendSPI.Supported &&
        core.exact_replay &&
        all(profile -> profile.exact_replay, profiles) &&
        all(row -> row !== nothing && row.exact_replay, native_rows) &&
        outer_event_row !== nothing && outer_event_row.exact_replay &&
        observation_save_row !== nothing && observation_save_row.exact_replay
    core_profile_fingerprint =
        CorePotts.BackendSPI.capability_key_fingerprint(core.key)
    checkpoint_mode = if outer_events.checkpoint !== :admitted
        :unsupported_outer_callback_state
    elseif !exact_replay
        :unsupported_unqualified_replay
    else
        isempty(components) ? :core_logical : :core_plus_native_logical
    end
    payload = (
        # CorePotts owns the Core capability identity. Compose its exact
        # evidence fingerprint instead of depending on a repr of its key.
        core = core_profile_fingerprint,
        scheduled = scheduled_system_fingerprint(problem.system).hex,
        native = facts,
        events,
        outer_events,
        observation_save,
        checkpoint = checkpoint_mode,
        replay,
    )
    fingerprint = _sha256_hex("potts-capability-key-v1", payload)
    key = PottsCapabilityKey(
        core.key,
        payload.scheduled,
        facts,
        events,
        outer_events,
        observation_save,
        payload.checkpoint,
        replay,
        fingerprint,
    )
    native_evidence = Tuple(
        row === nothing ? nothing : row.evidence for row in native_rows
    )
    closed_conjunction = exact_replay &&
        outer_event_row !== nothing &&
        observation_save_row !== nothing &&
        all(row -> row !== nothing, native_rows)
    conjunction_evidence = closed_conjunction ?
        _capability_evidence_identity(
            :Potts,
            :composed_replay_conjunction,
            v"1.0.0",
            fingerprint,
        ) : nothing
    reason = status !== CorePotts.BackendSPI.Supported ?
        "The runtime profile violates a structural, numerical, or requested exact-replay requirement." :
        exact_replay ?
            "The complete runtime and checkpoint profile has a closed exact-replay conjunction." :
            "The structural and numerical runtime contract is supported; exact replay was not requested or is not available."
    return PottsCapabilityReport(
        key,
        status,
        exact_replay,
        reason,
        (
            conjunction = conjunction_evidence,
            core = (key = core.key, exact_replay = core.exact_replay),
            native = native_evidence,
            outer_events = outer_event_row === nothing ? nothing :
                outer_event_row.evidence,
            observation_save = observation_save_row === nothing ? nothing :
                observation_save_row.evidence,
        ),
    )
end

function _require_runtime_capability(report::PottsCapabilityReport)
    report.status === CorePotts.BackendSPI.Supported && return report
    throw(ArgumentError(
        "Potts capability preflight rejected runtime profile " *
        "$(report.key.fingerprint): $(report.reason)"
    ))
end

function _problem_capability_requirements(problem::PottsProblem)
    components = scheduled_native_components(problem.system)
    return (
        kind = :PottsCapabilityRequirements,
        scheduled_fingerprint = scheduled_system_fingerprint(problem.system).hex,
        runtime_choices = (:algorithm, :backend, :device, :scalar_type),
        core = _scheduled_data(problem.system).capability_requirements,
        native = Tuple((
            path = native_component_path(component),
            family = nameof(typeof(native_family(getfield(component, :declaration)))),
            scope = nameof(typeof(getfield(getfield(component, :declaration), :scope))),
            cadence = native_cadence_stride(getfield(component, :declaration)),
            endpoints = length(native_coupling_endpoints(component)),
            scheduled_fingerprint = native_scheduled_fingerprint(component).hex,
        ) for component in components),
        support_status = :requires_concrete_runtime_profile,
    )
end
