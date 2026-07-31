function _completion_data(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) ||
        throw(ArgumentError("this inspection requires a completed PottsSystem"))
    return getfield(system, :completion)::CompletedPottsData
end

inspect(system::PottsSystem, ::Statements) = _completion_data(system).records
inspect(system::PottsSystem, ::Variables) = _completion_data(system).variables
inspect(system::PottsSystem, ::Effects) =
    Tuple((record.identity, record.effect, record.bound) for record in inspect(system, Statements()))
inspect(system::PottsSystem, ::RandomOperations) =
    Tuple(
        (record.identity, record.random_operations)
        for record in inspect(system, Statements())
        if !isempty(record.random_operations)
    )
inspect(system::PottsSystem, ::Schedule) = _completion_data(system).schedule
inspect(system::PottsSystem, ::Capabilities) = _completion_data(system).capabilities
inspect(system::PottsSystem, ::Fingerprints) = _completion_data(system).fingerprints

semantic_fingerprint(system::PottsSystem) = inspect(system, Fingerprints()).semantic
completed_system_fingerprint(system::PottsSystem) =
    inspect(system, Fingerprints()).completed

inspect(executable::PottsExecutable, ::Statements) =
    executable.reports.statements
inspect(executable::PottsExecutable, ::Variables) =
    executable.reports.variables
inspect(executable::PottsExecutable, ::Effects) =
    Tuple(
        (record.identity, record.effect, record.bound)
        for record in executable.reports.statements
    )
inspect(executable::PottsExecutable, ::RandomOperations) =
    Tuple(
        (record.identity, record.random_operations)
        for record in executable.reports.statements
        if !isempty(record.random_operations)
    )
inspect(executable::PottsExecutable, ::Schedule) =
    executable.reports.schedule
inspect(executable::PottsExecutable, ::Capabilities) =
    executable.reports.capability
inspect(executable::PottsExecutable, ::Fingerprints) = (
    semantic = executable.reports.fingerprints.semantic,
    completed = executable.reports.fingerprints.completed,
    executable = executable.fingerprint,
)
inspect(executable::PottsExecutable, ::StoragePlan) =
    executable.reports.storage
inspect(executable::PottsExecutable, ::Kernels) = (
    engine = executable.reports.execution.engine,
    backend = executable.reports.execution.backend,
    scalar_type = executable.reports.execution.scalar_type,
    phases = (:proposal, :commit, :after_mcs),
    time = executable.reports.time,
    live_state_allocated = false,
    descriptors = executable.reports.descriptors,
)
inspect(executable::PottsExecutable, ::ParameterSchema) =
    executable.parameter_manifest
inspect(executable::PottsExecutable, ::StateSchema) =
    executable.reports.states
inspect(executable::PottsExecutable, ::Observations) =
    executable.observations
inspect(executable::PottsExecutable, ::ExternalIO) =
    executable.reports.external_io
inspect(executable::PottsExecutable, ::ReplayContract) = (
    replay = executable.reports.replay,
    checkpoint = executable.reports.checkpoint,
)
