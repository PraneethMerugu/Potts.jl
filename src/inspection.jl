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

