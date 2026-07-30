struct PottsCheckpoint{C, H}
    schema::VersionNumber
    executable_fingerprint::ExecutableFingerprint
    core::C
    parameter_history::H
    replay_class::Symbol
    checksum::String
end

function _checkpoint_checksum(
        schema, fingerprint, core, parameter_history, replay_class
    )
    payload = string(
        schema, '\n',
        fingerprint.hex, '\n',
        core.checksum, '\n',
        replay_class, '\n',
        join(
            (
                string(time, ':', join(parameters.values, ','))
                for (time, parameters) in parameter_history
            ),
            '\n',
        ),
    )
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function checkpoint(integrator::PottsIntegrator)
    integrator.runtime.settled || throw(ArgumentError(
        "checkpoint capture requires a settled complete-MCS boundary"
    ))
    core = CorePotts.program_checkpoint(integrator.runtime)
    schema = v"1.0.0"
    fingerprint = executable_fingerprint(integrator.prob.executable)
    history = Tuple(
        time => parameters for (time, parameters) in integrator.parameter_history
    )
    replay_class = :exact_same_executable
    checksum = _checkpoint_checksum(
        schema, fingerprint, core, history, replay_class
    )
    return PottsCheckpoint(
        schema, fingerprint, core, history, replay_class, checksum
    )
end

function _validate_checkpoint(
        problem::PottsProblem, checkpoint_value::PottsCheckpoint
    )
    checkpoint_value.schema == v"1.0.0" ||
        throw(ArgumentError("unsupported PottsCheckpoint schema"))
    checkpoint_value.executable_fingerprint ==
        executable_fingerprint(problem.executable) ||
        throw(ArgumentError("checkpoint executable fingerprint mismatch"))
    checkpoint_value.replay_class === :exact_same_executable ||
        throw(ArgumentError("unsupported checkpoint replay class"))
    expected = _checkpoint_checksum(
        checkpoint_value.schema,
        checkpoint_value.executable_fingerprint,
        checkpoint_value.core,
        checkpoint_value.parameter_history,
        checkpoint_value.replay_class,
    )
    expected == checkpoint_value.checksum ||
        throw(ArgumentError("PottsCheckpoint integrity checksum mismatch"))
    checkpoint_value.core.seed == problem.seed ||
        throw(ArgumentError("checkpoint seed does not match the problem"))
    checkpoint_value.core.replica == problem.replica ||
        throw(ArgumentError("checkpoint replica does not match the problem"))
    completed_mcs = checkpoint_value.core.snapshot.mcs
    problem.tspan[1] <= completed_mcs <= problem.tspan[2] ||
        throw(ArgumentError("checkpoint MCS lies outside the problem horizon"))
    return nothing
end

function _init_from_checkpoint(
        problem::PottsProblem,
        checkpoint_value::PottsCheckpoint,
        policy::PottsSavePolicy,
    )
    _validate_checkpoint(problem, checkpoint_value)
    runtime = CorePotts.restore_program_checkpoint(
        problem.executable.core_program, checkpoint_value.core
    )
    state = _saved_state(
        CorePotts.program_snapshot(runtime),
        _runtime_observations(runtime, policy.observables),
    )
    history = Pair{Int, Any}[
        time => parameters
        for (time, parameters) in checkpoint_value.parameter_history
    ]
    integrator = PottsIntegrator(
        problem,
        runtime,
        runtime.mcs,
        state,
        policy,
        Int[],
        typeof(state)[],
        history,
        0,
        false,
        SciMLBase.ReturnCode.Default,
    )
    policy.save_start && _save_current!(integrator)
    return integrator
end

