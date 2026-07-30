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
    inspect(executable.completed_system, Statements())
inspect(executable::PottsExecutable, ::Variables) =
    inspect(executable.completed_system, Variables())
inspect(executable::PottsExecutable, ::Effects) =
    inspect(executable.completed_system, Effects())
inspect(executable::PottsExecutable, ::RandomOperations) =
    inspect(executable.completed_system, RandomOperations())
inspect(executable::PottsExecutable, ::Schedule) =
    executable.reports.schedule
inspect(executable::PottsExecutable, ::Capabilities) =
    executable.reports.capability
inspect(executable::PottsExecutable, ::Fingerprints) = (
    semantic = semantic_fingerprint(executable.completed_system),
    completed = completed_system_fingerprint(executable.completed_system),
    executable = executable.fingerprint,
)
inspect(executable::PottsExecutable, ::StoragePlan) =
    executable.reports.storage
inspect(executable::PottsExecutable, ::Kernels) = (
    engine = executable.reports.execution.engine,
    backend = executable.reports.execution.backend,
    phases = (:proposal, :commit, :after_mcs),
    live_state_allocated = false,
)
