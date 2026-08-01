# Backend-portable checkerboard candidate, claim, evaluation, and commit kernels.

@inline function _checkerboard_priority(state, semantic_id, color)
    address = _program_address(
        CheckerboardPriorityStream,
        state.mcs + 1,
        4,
        semantic_id;
        subround = color,
    )
    return _rng_word(
        Philox4x32x10V1(),
        _trajectory_seed(state.seed, state.replica, state.repeat),
        address,
    )
end

@kernel function _checkerboard_candidates_kernel!(
        target_sites,
        source_sites,
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        state,
        color::Int32,
    )
    local_index = @index(Global, Linear)
    plan = state.program.checkerboard_plan
    first_index = @inbounds plan.color_offsets[Int(color)]
    stop_index = @inbounds plan.color_offsets[Int(color) + 1] - Int32(1)
    color_size = stop_index - first_index + Int32(1)
    batch_size = color_size * state.program.attempts_per_site
    if local_index <= batch_size
        zero_based = Int32(local_index - 1)
        site_offset = rem(zero_based, color_size)
        attempt_round = div(zero_based, color_size) + Int32(1)
        schedule_index = first_index + site_offset
        target_linear = @inbounds plan.sites[Int(schedule_index)]
        semantic_id = (attempt_round - Int32(1)) *
                      Int32(length(state.ownership)) + target_linear
        target = CartesianIndices(state.ownership)[Int(target_linear)]
        direction = _program_bounded(
            state,
            ProposalDirectionStream,
            2,
            semantic_id,
            size(state.program.proposal_offsets, 2);
            subround = color,
        )
        source = _neighbor_index(
            state.program,
            target,
            state.program.proposal_offsets,
            direction,
        )
        @inbounds begin
            target_sites[local_index] = target_linear
            source_sites[local_index] = source === nothing ?
                                        Int32(0) : Int32(LinearIndices(
                                            state.ownership
                                        )[source])
            old_owner = state.ownership[target]
            old_owners[local_index] = old_owner
            new_owner = source === nothing ? old_owner : state.ownership[source]
            new_owners[local_index] = new_owner
            actionable = source !== nothing && old_owner != new_owner
            priorities[local_index] = actionable ?
                _checkerboard_priority(state, semantic_id, color) : UInt32(0)
            semantic_ids[local_index] = semantic_id
            dispositions[local_index] = actionable ?
                _PROGRAM_CHECKERBOARD_PENDING : _PROGRAM_CHECKERBOARD_NULL
        end
    end
end

@inline function _checkerboard_claim_priority!(claims, owner, priority)
    owner > 0 || return nothing
    Atomix.@atomic max(claims[Int(owner)], priority)
    return nothing
end

@kernel function _checkerboard_claim_priorities_kernel!(
        old_owners,
        new_owners,
        priorities,
        dispositions,
        cell_max_priority,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index <= batch_size &&
            @inbounds(dispositions[index] == _PROGRAM_CHECKERBOARD_PENDING)
        priority = @inbounds priorities[index]
        old_owner = @inbounds old_owners[index]
        new_owner = @inbounds new_owners[index]
        _checkerboard_claim_priority!(
            cell_max_priority, old_owner, priority
        )
        _checkerboard_claim_priority!(
            cell_max_priority, new_owner, priority
        )
    end
end

@inline function _checkerboard_claim_identity!(
        maximums, identities, owner, priority, identity
    )
    owner > 0 || return nothing
    if @inbounds maximums[Int(owner)] == priority
        Atomix.@atomic min(identities[Int(owner)], identity)
    end
    return nothing
end

@kernel function _checkerboard_claim_identities_kernel!(
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        cell_max_priority,
        cell_min_identity,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index <= batch_size &&
            @inbounds(dispositions[index] == _PROGRAM_CHECKERBOARD_PENDING)
        priority = @inbounds priorities[index]
        identity = UInt32(@inbounds semantic_ids[index])
        old_owner = @inbounds old_owners[index]
        new_owner = @inbounds new_owners[index]
        _checkerboard_claim_identity!(
            cell_max_priority,
            cell_min_identity,
            old_owner,
            priority,
            identity,
        )
        _checkerboard_claim_identity!(
            cell_max_priority,
            cell_min_identity,
            new_owner,
            priority,
            identity,
        )
    end
end

@inline function _checkerboard_wins_claim(
        maximums, identities, owner, priority, identity
    )
    owner > 0 || return true
    return @inbounds maximums[Int(owner)] == priority &&
                     identities[Int(owner)] == identity
end

@kernel function _checkerboard_select_kernel!(
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        cell_max_priority,
        cell_min_identity,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index <= batch_size &&
            @inbounds(dispositions[index] == _PROGRAM_CHECKERBOARD_PENDING)
        priority = @inbounds priorities[index]
        identity = UInt32(@inbounds semantic_ids[index])
        old_owner = @inbounds old_owners[index]
        new_owner = @inbounds new_owners[index]
        wins = _checkerboard_wins_claim(
                   cell_max_priority,
                   cell_min_identity,
                   old_owner,
                   priority,
                   identity,
               ) && _checkerboard_wins_claim(
                   cell_max_priority,
                   cell_min_identity,
                   new_owner,
                   priority,
                   identity,
               )
        wins || (@inbounds dispositions[index] =
            _PROGRAM_CHECKERBOARD_CONFLICT)
    end
end

@inline function _checkerboard_log_ratio(evaluation, temperature)
    evaluation.constraints_allowed || return -typeof(temperature)(Inf)
    if iszero(temperature)
        effective = evaluation.delta_h + evaluation.drive_energy
        return effective <= zero(temperature) ?
               zero(temperature) : -typeof(temperature)(Inf)
    end
    return -(evaluation.delta_h + evaluation.drive_energy) / temperature +
           evaluation.drive_log_bias + evaluation.kinetic_modifier
end

@kernel function _checkerboard_evaluate_kernel!(
        contributions,
        target_sites,
        source_sites,
        old_owners,
        new_owners,
        semantic_ids,
        dispositions,
        state,
        color::Int32,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index <= batch_size &&
            @inbounds(dispositions[index] == _PROGRAM_CHECKERBOARD_PENDING)
        target = CartesianIndices(state.ownership)[Int(
            @inbounds target_sites[index]
        )]
        source = CartesianIndices(state.ownership)[Int(
            @inbounds source_sites[index]
        )]
        semantic_id = @inbounds semantic_ids[index]
        context = _ProposalEvaluationContext(
            state,
            source,
            target,
            @inbounds(old_owners[index]),
            @inbounds(new_owners[index]),
            Int(semantic_id),
            Int(color),
        )
        source_count = state.program.descriptor_plan.source_count
        column = CheckerboardContributionColumn(
            contributions, Int32(index), source_count
        )
        evaluate_proposal_contributions!(
            column, state.program.descriptor_plan, context
        )
        evaluation = fold_proposal_contributions(
            state.program.descriptor_plan, column
        )
        if !evaluation.constraints_allowed
            @inbounds dispositions[index] = _PROGRAM_CHECKERBOARD_CONSTRAINT
        else
            temperature = compiled_scalar_value(
                state.program.temperature, state.parameters
            )
            log_ratio = _checkerboard_log_ratio(evaluation, temperature)
            accepted = log_ratio >= zero(temperature)
            if !accepted && isfinite(log_ratio)
                draw = _program_uniform(
                    typeof(temperature),
                    state,
                    AcceptanceStream,
                    3,
                    semantic_id;
                    subround = color,
                )
                accepted = log(draw) < log_ratio
            end
            @inbounds dispositions[index] = accepted ?
                _PROGRAM_CHECKERBOARD_ACCEPTED : _PROGRAM_CHECKERBOARD_ENERGY
        end
    end
end

@kernel function _checkerboard_commit_kernel!(
        target_sites,
        old_owners,
        new_owners,
        dispositions,
        state,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index <= batch_size &&
            @inbounds(dispositions[index] == _PROGRAM_CHECKERBOARD_ACCEPTED)
        target = CartesianIndices(state.ownership)[Int(
            @inbounds target_sites[index]
        )]
        old_owner = @inbounds old_owners[index]
        new_owner = @inbounds new_owners[index]
        @inbounds state.ownership[target] = new_owner
        commit_tracker_updates!(
            state.trackers,
            state.program.tracker_plan,
            target,
            old_owner,
            new_owner,
        )
    end
end

@kernel function _checkerboard_report_kernel!(
        report,
        dispositions,
        batch_size::Int32,
    )
    index = @index(Global, Linear)
    if index == 1
        accepted = UInt64(0)
        rejected = UInt64(0)
        null_attempts = UInt64(0)
        constraint_rejections = UInt64(0)
        energy_rejections = UInt64(0)
        for candidate in 1:Int(batch_size)
            disposition = @inbounds dispositions[candidate]
            accepted += UInt64(disposition == _PROGRAM_CHECKERBOARD_ACCEPTED)
            rejected += UInt64(
                disposition == _PROGRAM_CHECKERBOARD_CONFLICT ||
                disposition == _PROGRAM_CHECKERBOARD_CONSTRAINT ||
                disposition == _PROGRAM_CHECKERBOARD_ENERGY
            )
            null_attempts += UInt64(disposition == _PROGRAM_CHECKERBOARD_NULL)
            constraint_rejections +=
                UInt64(disposition == _PROGRAM_CHECKERBOARD_CONSTRAINT)
            energy_rejections +=
                UInt64(disposition == _PROGRAM_CHECKERBOARD_ENERGY)
        end
        @inbounds begin
            report[1] += accepted
            report[2] += rejected
            report[3] += null_attempts
            report[4] += constraint_rejections
            report[5] += energy_rejections
        end
    end
end
