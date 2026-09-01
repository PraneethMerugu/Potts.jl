function _completion_data(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) ||
        throw(ArgumentError("this inspection requires a completed PottsSystem"))
    return getfield(system, :completion)::CompletedPottsData
end

function _scheduled_data(system::PottsSystem)
    is_scheduled(system) || throw(ArgumentError(
        "this inspection requires a structurally scheduled PottsSystem; call mtkcompile"
    ))
    scheduled = _completion_data(system).scheduled
    scheduled isa ScheduledPottsData || error(
        "scheduled PottsSystem is missing its structural scheduling authority"
    )
    return scheduled
end

"""Inspect a completed/scheduled system or runtime with an inspection selector."""
inspect(system::PottsSystem, ::Statements) =
    Tuple(_completion_data(system).records)
inspect(system::PottsSystem, ::Variables) =
    Tuple(_completion_data(system).variables)
inspect(system::PottsSystem, ::Effects) =
    Tuple((record.identity, record.effect, record.bound) for record in inspect(system, Statements()))
inspect(system::PottsSystem, ::RandomOperations) =
    Tuple(
        (record.identity, record.random_operations)
        for record in inspect(system, Statements())
        if !isempty(record.random_operations)
    )
inspect(system::PottsSystem, ::Schedule) = is_scheduled(system) ?
    Tuple(_scheduled_data(system).schedule) :
    Tuple(_completion_data(system).schedule)
function inspect(system::PottsSystem, ::Capabilities)
    completion = _completion_data(system)
    is_scheduled(system) || return _fingerprint_completion_capabilities(
        completion.capabilities
    )
    native = Tuple((
        path = native_component_path(component),
        problem_family = nameof(typeof(native_family(
            getfield(component, :declaration)
        ))),
        initialization = :native_MTK_problem_constructor,
        events = :native_MTK_problem_callbacks,
        observations = :scheduled_MTK_SII_provider,
        requirements = (
            family = nameof(typeof(native_family(
                getfield(component, :declaration)
            ))),
            scope = nameof(typeof(getfield(
                getfield(component, :declaration), :scope
            ))),
            clock = nameof(typeof(getfield(
                getfield(component, :declaration), :time
            ))),
            split = nameof(typeof(getfield(
                getfield(component, :declaration), :split
            ))),
            cadence = native_cadence_stride(
                getfield(component, :declaration)
            ),
            io = Tuple((
                direction = endpoint.port isa NativeInput ? :input : :output,
                potts_kind = endpoint.potts_kind,
                value_type = native_value_type(endpoint),
            ) for endpoint in native_coupling_endpoints(component)),
            late_profile_dimensions = (
                :algorithm,
                :algorithm_package,
                :algorithm_version,
                :solver_options,
                :backend,
                :device,
                :scalar_type,
                :event_contract,
                :replay_contract,
            ),
        ),
    ) for component in scheduled_native_components(system))
    return (
        kind = :PottsCapabilityRequirements,
        scheduled_fingerprint = scheduled_system_fingerprint(system).hex,
        requirements = _fingerprint_scheduled_capabilities(
            _scheduled_data(system).capability_requirements
        ),
        native_components = native,
        support_status = :requires_concrete_runtime_profile,
    )
end
inspect(problem::PottsProblem, ::Capabilities) =
    _problem_capability_requirements(problem)
inspect(integrator::PottsIntegrator, ::Capabilities) =
    integrator.capability_report
inspect(solution::PottsSolution, ::Capabilities) =
    solution.provenance.capability
function inspect(system::PottsSystem, ::Fingerprints)
    completion = _completion_data(system)
    is_scheduled(system) || return completion.fingerprints
    return merge(
        completion.fingerprints,
        (scheduled = _scheduled_data(system).fingerprint,),
    )
end
inspect(system::PottsSystem, ::ParameterSchema) =
    _fingerprint_scheduled_parameters(_scheduled_data(system).parameters)
inspect(system::PottsSystem, ::StateSchema) = (
    states = Tuple(_scheduled_data(system).states),
    relationships = Tuple(_scheduled_data(system).relationships),
)
inspect(system::PottsSystem, ::Observations) =
    Tuple(_scheduled_data(system).observations)
function inspect(system::PottsSystem, ::ExternalIO)
    endpoints = NamedTuple[]
    for component in scheduled_native_components(system)
        for endpoint in native_coupling_endpoints(component)
            push!(endpoints, (
                component_path = native_component_path(component),
                direction = endpoint.port isa NativeInput ? :input : :output,
                native_variable = native_variable(endpoint),
                potts_identity = potts_endpoint(endpoint),
                potts_kind = endpoint.potts_kind,
                value_type = native_value_type(endpoint),
                hold = endpoint.port isa NativeInput ? :zero_order_hold : nothing,
                publication = :atomic_completed_mcs_boundary,
            ))
        end
    end
    return Tuple(endpoints)
end
function inspect(system::PottsSystem, ::ReplayContract)
    native = scheduled_native_components(system)
    return (
        core = :exact_same_scheduled_system_and_runtime_profile,
        native_components = Tuple((
            path = native_component_path(component),
            logical_state = (:u, :p, :t, :du),
            restart = :exact_configuration_only,
            exact_requires = (
                :pinned_profile_id,
                :deterministic_profile_assertion,
                :identical_scheduled_native_fingerprint,
                :identical_profile_fingerprint,
            ),
        ) for component in native),
        coupled_publication = :CPMThenComponents_atomic,
    )
end
inspect(system::PottsSystem, ::LifecyclePlans) =
    _lifecycle_analysis_report(_analyze_completed_system(system))

"""Return the semantic fingerprint of an authored `PottsSystem`."""
semantic_fingerprint(system::PottsSystem) = inspect(system, Fingerprints()).semantic
"""Return the completed-system fingerprint after semantic validation."""
completed_system_fingerprint(system::PottsSystem) =
    inspect(system, Fingerprints()).completed
"""Return the scheduled-system fingerprint after `mtkcompile`."""
scheduled_system_fingerprint(system::PottsSystem) =
    inspect(system, Fingerprints()).scheduled
