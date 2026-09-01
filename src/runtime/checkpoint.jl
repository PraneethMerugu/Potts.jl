# PottsToolkit contributes a deterministic logical extension block to the one
# CorePotts checkpoint envelope.  There is one outer schema and one checksum;
# native-component blocks join this same envelope.
"""Checkpoint payload for exact continuation of an admitted Potts runtime."""
const PottsCheckpoint = CorePotts.ProgramCheckpoint
const _POTTS_CHECKPOINT_BLOCK_SCHEMA = v"1.1.0"
const _NATIVE_CHECKPOINT_BLOCK_SCHEMA = v"1.0.0"

function _native_checkpoint_blocks(integrator::PottsIntegrator)
    components = scheduled_native_components(integrator.prob.system)
    length(components) == length(integrator.native_states) ==
        length(integrator.native_profiles) || error(
            "native component, logical-state, and profile vectors are misaligned"
    )
    return Tuple(
        let state = integrator.native_states[index]
            profile = integrator.native_profiles[index]
            component = components[index]
            evidence = integrator.capability_report.evidence.native[index]
            common = (
                schema = _NATIVE_CHECKPOINT_BLOCK_SCHEMA,
                path = _native_runtime_path(state),
                original_fingerprint =
                    native_original_fingerprint(component).hex,
                scheduled_fingerprint =
                    native_scheduled_fingerprint(component).hex,
                profile_fingerprint = _native_profile_fingerprint(profile),
                profile_id = profile.profile_id,
                deterministic = profile.deterministic,
                exact_replay = profile.exact_replay,
                replay_evidence = evidence === nothing ? nothing : (
                    authority = evidence.authority,
                    suite = evidence.suite,
                    revision = evidence.revision,
                    profile_fingerprint = evidence.profile_fingerprint,
                ),
                replay_class = :exact_pinned_deterministic_profile,
            )
            if state isa NativeLogicalState
                merge(common, (
                    scope = :global,
                    u = state.u,
                    p = state.p,
                    du = state.du,
                    t = state.t,
                    retcode = state.retcode,
                ))
            else
                logical = native_cell_state_snapshot(state)
                merge(common, (
                    scope = :per_cell,
                    capacity = logical.capacity,
                    completed_mcs = logical.completed_mcs,
                    last_transaction_identity =
                        logical.last_transaction_identity,
                    active = logical.active,
                    generations = logical.generations,
                    kinds = logical.kinds,
                    identities = Tuple(
                        identity === nothing ? nothing : (
                            slot = identity.slot,
                            generation = identity.generation,
                            kind = identity.kind,
                        ) for identity in logical.identities
                    ),
                    states = Tuple(
                        value === nothing ? nothing : (
                            u = value.u,
                            p = value.p,
                            du = value.du,
                            t = value.t,
                            retcode = value.retcode,
                        ) for value in logical.states
                    ),
                ))
            end
        end
        for index in eachindex(components)
    )
end

function _potts_checkpoint_block(integrator::PottsIntegrator)
    history = Tuple((
        mcs = Int(time),
        values = Tuple(parameters.values),
    ) for (time, parameters) in integrator.parameter_history)
    native_blocks = _native_checkpoint_blocks(integrator)
    replay_class = isempty(native_blocks) ?
        :exact_same_scheduled_system_and_profile :
        :exact_pinned_native_profiles
    conjunction = integrator.capability_report.evidence.conjunction
    return (
        schema = _POTTS_CHECKPOINT_BLOCK_SCHEMA,
        scheduled_fingerprint =
            scheduled_system_fingerprint(integrator.prob.system).hex,
        profile_fingerprint = _execution_plan_fingerprint(integrator.plan).hex,
        capability_fingerprint = integrator.capability_report.key.fingerprint,
        conjunction_evidence = conjunction === nothing ? nothing : (
            authority = conjunction.authority,
            suite = conjunction.suite,
            revision = conjunction.revision,
            profile_fingerprint = conjunction.profile_fingerprint,
        ),
        parameter_history = history,
        native_components = native_blocks,
        replay_class,
    )
end

"""Capture a restartable checkpoint of the integrator's authorized runtime state."""
function checkpoint(integrator::PottsIntegrator)
    integrator.retcode == SciMLBase.ReturnCode.Failure && throw(ArgumentError(
        "a failed PottsIntegrator cannot be checkpointed"
    ))
    integrator.terminated && throw(ArgumentError(
        "a terminated PottsIntegrator cannot be checkpointed until callback/termination state has a replay codec"
    ))
    _callbacks_empty(integrator) || throw(ArgumentError(
        "checkpointing with outer Potts callbacks is not admitted because callback identity and state are not checkpointed"
    ))
    isempty(integrator.native_states) ||
        integrator.capability_report.exact_replay ||
        throw(ArgumentError(
            "native checkpointing requires exact-replay evidence for the " *
            "complete composed runtime profile"
        ))
    integrator.pending_parameters === nothing || throw(ArgumentError(
        "finalize the staged parameter transaction before checkpointing"
    ))
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.CheckpointSettlement
    )
    return CorePotts.program_checkpoint(
        integrator.runtime;
        extensions = (PottsToolkit = _potts_checkpoint_block(integrator),),
    )
end

function _potts_checkpoint_block(checkpoint_value::PottsCheckpoint)
    hasproperty(checkpoint_value.extensions, :PottsToolkit) ||
        throw(ArgumentError(
            "checkpoint has no PottsToolkit logical extension block"
        ))
    block = getproperty(checkpoint_value.extensions, :PottsToolkit)
    block isa NamedTuple || throw(ArgumentError(
        "invalid PottsToolkit checkpoint extension block"
    ))
    required = (
        :schema,
        :scheduled_fingerprint,
        :profile_fingerprint,
        :capability_fingerprint,
        :conjunction_evidence,
        :parameter_history,
        :native_components,
        :replay_class,
    )
    all(name -> hasproperty(block, name), required) || throw(ArgumentError(
        "incomplete PottsToolkit checkpoint extension block"
    ))
    return block
end

function _validate_checkpoint(
        problem::PottsProblem,
        plan::_PottsExecutionPlan,
        checkpoint_value::PottsCheckpoint,
    )
    checkpoint_value.schema == v"3.0.0" ||
        throw(ArgumentError("unsupported logical checkpoint schema"))
    block = _potts_checkpoint_block(checkpoint_value)
    block.schema == _POTTS_CHECKPOINT_BLOCK_SCHEMA ||
        throw(ArgumentError("unsupported PottsToolkit checkpoint block schema"))
    block.scheduled_fingerprint ==
        scheduled_system_fingerprint(problem.system).hex ||
        throw(ArgumentError("checkpoint scheduled-system fingerprint mismatch"))
    block.profile_fingerprint == _execution_plan_fingerprint(plan).hex ||
        throw(ArgumentError("checkpoint runtime-profile fingerprint mismatch"))
    block.replay_class in (
        :exact_same_scheduled_system_and_profile,
        :exact_pinned_native_profiles,
    ) ||
        throw(ArgumentError("unsupported checkpoint replay class"))
    checkpoint_value.seed == problem.seed ||
        throw(ArgumentError("checkpoint seed does not match the problem"))
    checkpoint_value.replica == problem.replica ||
        throw(ArgumentError("checkpoint replica does not match the problem"))
    checkpoint_value.repeat == problem.repeat ||
        throw(ArgumentError("checkpoint repeat does not match the problem"))
    completed_mcs = checkpoint_value.snapshot.mcs
    problem.tspan[1] <= completed_mcs <= problem.tspan[2] ||
        throw(ArgumentError("checkpoint MCS lies outside the problem horizon"))
    return block
end

function _restore_native_states(
        problem::PottsProblem,
        block::NamedTuple,
        profiles,
        completed_mcs::Integer,
        capability_report::PottsCapabilityReport,
        prepared_native,
    )
    components = scheduled_native_components(problem.system)
    block.capability_fingerprint == capability_report.key.fingerprint ||
        throw(ArgumentError(
            "checkpoint composed-capability fingerprint mismatch"
        ))
    conjunction = capability_report.evidence.conjunction
    expected_conjunction = conjunction === nothing ? nothing : (
        authority = conjunction.authority,
        suite = conjunction.suite,
        revision = conjunction.revision,
        profile_fingerprint = conjunction.profile_fingerprint,
    )
    block.conjunction_evidence == expected_conjunction ||
        throw(ArgumentError(
            "checkpoint composed-capability evidence identity mismatch"
        ))
    entries = try
        Tuple(block.native_components)
    catch
        throw(ArgumentError("checkpoint native component blocks must be a tuple"))
    end
    length(entries) == length(components) == length(profiles) ||
        throw(ArgumentError(
            "checkpoint native component count does not match the runtime profile"
        ))
    states = Any[]
    for index in eachindex(components)
        entry = entries[index]
        component = components[index]
        profile = profiles[index]
        path = native_component_path(component)
        common_required = (
            :schema, :path, :original_fingerprint, :scheduled_fingerprint,
            :profile_fingerprint, :profile_id, :deterministic,
            :exact_replay, :replay_evidence, :replay_class, :scope,
        )
        entry isa NamedTuple &&
            all(name -> hasproperty(entry, name), common_required) ||
            throw(ArgumentError(
                "incomplete native checkpoint block for $(_native_path_string(path))"
            ))
        entry.schema == _NATIVE_CHECKPOINT_BLOCK_SCHEMA ||
            throw(ArgumentError(
                "unsupported native checkpoint schema at $(_native_path_string(path))"
            ))
        Tuple(entry.path) == path || throw(ArgumentError(
            "checkpoint native component path/order mismatch at $(_native_path_string(path))"
        ))
        entry.original_fingerprint == native_original_fingerprint(component).hex ||
            throw(ArgumentError(
                "checkpoint original native-system fingerprint mismatch at " *
                _native_path_string(path)
            ))
        entry.scheduled_fingerprint == native_scheduled_fingerprint(component).hex ||
            throw(ArgumentError(
                "checkpoint scheduled native-system fingerprint mismatch at " *
                _native_path_string(path)
            ))
        entry.profile_fingerprint == _native_profile_fingerprint(profile) ||
            throw(ArgumentError(
                "checkpoint native solve-profile fingerprint mismatch at " *
                _native_path_string(path)
            ))
        entry.profile_id == profile.profile_id &&
            entry.deterministic == profile.deterministic &&
            entry.exact_replay == profile.exact_replay || throw(ArgumentError(
                "checkpoint native replay qualification mismatch at " *
                _native_path_string(path)
            ))
        evidence = capability_report.evidence.native[index]
        expected_evidence = evidence === nothing ? nothing : (
            authority = evidence.authority,
            suite = evidence.suite,
            revision = evidence.revision,
            profile_fingerprint = evidence.profile_fingerprint,
        )
        entry.replay_evidence == expected_evidence || throw(ArgumentError(
            "checkpoint native evidence identity mismatch at " *
            _native_path_string(path)
        ))
        expected_class = :exact_pinned_deterministic_profile
        entry.replay_class === expected_class || throw(ArgumentError(
            "checkpoint native replay class mismatch at " *
            _native_path_string(path)
        ))
        declaration = getfield(component, :declaration)
        stride = native_cadence_stride(declaration)
        last_due = completed_mcs - mod(completed_mcs, stride)
        expected_time = native_time_at(declaration, last_due)
        if getfield(declaration, :scope) isa Global
            entry.scope === :global || throw(ArgumentError(
                "checkpoint native scope mismatch at $(_native_path_string(path))"
            ))
            all(name -> hasproperty(entry, name), (:u, :p, :du, :t, :retcode)) ||
                throw(ArgumentError("incomplete global native checkpoint state"))
            isequal(entry.t, expected_time) || throw(ArgumentError(
                "checkpoint native time does not match completed MCS at " *
                _native_path_string(path)
            ))
            push!(states, NativeLogicalState(
                path,
                Tuple(entry.u),
                Tuple(entry.p),
                entry.du === nothing ? nothing : Tuple(entry.du),
                entry.t,
                entry.retcode,
            ))
        else
            entry.scope === :per_cell || throw(ArgumentError(
                "checkpoint native scope mismatch at $(_native_path_string(path))"
            ))
            required = (
                :capacity, :completed_mcs, :last_transaction_identity,
                :active, :generations, :kinds, :identities, :states,
            )
            all(name -> hasproperty(entry, name), required) || throw(
                ArgumentError("incomplete per-cell native checkpoint state")
            )
            template_pool = prepared_native[index]
            template_pool isa NativeCellStatePool || error(
                "prepared per-cell native state is not a fixed-capacity pool"
            )
            entry.capacity == length(template_pool) || throw(ArgumentError(
                "checkpoint per-cell native capacity mismatch"
            ))
            entry.completed_mcs == completed_mcs || throw(ArgumentError(
                "checkpoint per-cell native publication boundary mismatch"
            ))
            0 <= entry.last_transaction_identity <= typemax(UInt64) ||
                throw(ArgumentError(
                    "checkpoint per-cell transaction identity is invalid"
                ))
            encoded_identities = Tuple(entry.identities)
            encoded_states = Tuple(entry.states)
            identities = Tuple(
                value === nothing ? nothing : CorePotts.CellIdentity(
                    value.slot, value.generation, value.kind
                ) for value in encoded_identities
            )
            logical_states = Tuple(
                value === nothing ? nothing : NativeLogicalState(
                    path,
                    Tuple(value.u),
                    Tuple(value.p),
                    value.du === nothing ? nothing : Tuple(value.du),
                    value.t,
                    value.retcode,
                ) for value in encoded_states
            )
            length(identities) == length(logical_states) == entry.capacity ||
                throw(ArgumentError("checkpoint per-cell native tables have wrong width"))
            active = BitVector(entry.active)
            generations = UInt32.(entry.generations)
            kinds = Int16.(entry.kinds)
            length(active) == length(generations) == length(kinds) ==
                entry.capacity || throw(ArgumentError(
                    "checkpoint per-cell metadata tables have wrong width"
                ))
            all(eachindex(identities)) do slot
                identity = identities[slot]
                active[slot] == (identity !== nothing) &&
                    (identity === nothing || (
                        identity.generation == generations[slot] &&
                        identity.kind == kinds[slot]
                    ))
            end || throw(ArgumentError(
                "checkpoint per-cell identities disagree with slot metadata"
            ))
            bank = NativeCellStateBank(
                template_pool.policy.template, entry.capacity
            )
            for slot in eachindex(logical_states)
                logical_states[slot] === nothing && continue
                value = logical_states[slot]
                value isa NativeLogicalState || throw(ArgumentError(
                    "checkpoint per-cell state has an invalid logical value"
                ))
                isequal(value.t, expected_time) || throw(ArgumentError(
                    "checkpoint per-cell native time does not match completed MCS"
                ))
                _write_native_cell_state!(bank, slot, value)
            end
            push!(states, NativeCellStatePool(
                path,
                active,
                generations,
                kinds,
                bank,
                template_pool.policy;
                completed_mcs = entry.completed_mcs,
                last_transaction_identity = entry.last_transaction_identity,
            ))
        end
    end
    expected_outer = isempty(entries) ?
        :exact_same_scheduled_system_and_profile :
        :exact_pinned_native_profiles
    block.replay_class === expected_outer || throw(ArgumentError(
        "checkpoint outer and native replay classes disagree"
    ))
    return states
end

function _restore_parameter_history(
        plan::_PottsExecutionPlan, block::NamedTuple, completed_mcs::Integer
    )
    entries = try
        Tuple(block.parameter_history)
    catch
        throw(ArgumentError("checkpoint parameter history must be a tuple"))
    end
    isempty(entries) && throw(ArgumentError(
        "checkpoint parameter history cannot be empty"
    ))
    names = Tuple(entry.name for entry in plan.parameter_manifest)
    T = eltype(plan.core_program.parameter_defaults)
    history = Pair{Int, Any}[]
    previous_mcs = -1
    for entry in entries
        entry isa NamedTuple && hasproperty(entry, :mcs) &&
            hasproperty(entry, :values) || throw(ArgumentError(
                "invalid checkpoint parameter-history entry"
            ))
        mcs = entry.mcs
        mcs isa Integer && 0 <= mcs <= completed_mcs && mcs >= previous_mcs ||
            throw(ArgumentError(
                "checkpoint parameter history is not ordered within its horizon"
            ))
        values = try
            T[entry.values...]
        catch
            throw(ArgumentError(
                "checkpoint parameter history contains incompatible values"
            ))
        end
        length(values) == length(names) || throw(ArgumentError(
            "checkpoint parameter-history width does not match the runtime profile"
        ))
        all(isfinite, values) || throw(ArgumentError(
            "checkpoint parameter history contains a nonfinite value"
        ))
        CorePotts.CompilerSPI.validate_parameters(
            plan.core_program.descriptor_plan, values
        )
        parameters = PottsParameters(values, NamedTuple{names}(Tuple(values)))
        push!(history, Int(mcs) => parameters)
        previous_mcs = Int(mcs)
    end
    last(history).first <= completed_mcs || error(
        "validated checkpoint parameter history exceeds its horizon"
    )
    return history
end

function _restore_checkpoint_materialization(
        problem::PottsProblem,
        plan::_PottsExecutionPlan,
        checkpoint_value::PottsCheckpoint,
        profiles,
        capability_report::PottsCapabilityReport,
        prepared_native,
    )
    # Validate the one outer checksum, Core-program identity, and PottsToolkit
    # profile block before allocating either runtime domain.
    CorePotts.BackendSPI.validate_program_checkpoint(
        plan.core_program, checkpoint_value
    )
    block = _validate_checkpoint(problem, plan, checkpoint_value)
    history = _restore_parameter_history(
        plan, block, checkpoint_value.snapshot.mcs
    )
    native_states = _restore_native_states(
        problem,
        block,
        profiles,
        checkpoint_value.snapshot.mcs,
        capability_report,
        prepared_native,
    )
    _parameter_buffer(last(history).second) == checkpoint_value.parameters ||
        throw(ArgumentError(
            "checkpoint parameter history does not end at the published Core state"
        ))
    runtime = CorePotts.restore_program_checkpoint(
        plan.core_program, checkpoint_value
    )
    components = scheduled_native_components(problem.system)
    if !isempty(native_states) && _native_components_have_ports(components)
        snapshot = CorePotts.program_snapshot(runtime)
        descriptor_state =
            CorePotts.BackendSPI.program_snapshot_descriptor_state(snapshot)
        _validate_native_outputs(
            plan,
            descriptor_state,
            components,
            native_states,
        )
    end
    return runtime, history, native_states
end
