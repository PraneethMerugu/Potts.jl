# Closed accepted-copy and after-MCS stage-plan orchestration.

function _lower_stage_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        state_layout::CorePotts.CompilerSPI.StateLayout,
        relationship_endpoint_policies,
        history_descriptors,
        ; tracker_handles = nothing,
    ) where {T <: AbstractFloat}
    accepted = Any[]
    after_mcs_assignments = Any[]
    after_mcs_iterated = Any[]
    after_mcs_relationships = Any[]
    after_mcs_commits = Any[]
    after_mcs_site_slot = 0
    after_mcs_model_slot = 0
    after_mcs_cell_slot = 0
    relationship_slot = 0
    for (record_index, record) in enumerate(ir.source.records)
        if record.kind === :AcceptedCopyProcess
            arguments = first(record.normalized_payload)
            for (effect_index, effect) in enumerate(arguments.effects)
                descriptor = if effect isa Assign
                    _stage_descriptor(
                        ir,
                        record_index,
                        manifest,
                        T,
                        state_handles,
                        draw_handles,
                        state_layout,
                        CorePotts.CompilerSPI.AcceptedCopyStage(),
                        length(accepted) + 1,
                        effect_index,
                        ; history_descriptors, tracker_handles,
                    )
                elseif effect isa Create
                    _relationship_create_stage_descriptor(
                        ir,
                        record_index,
                        manifest,
                        T,
                        state_handles,
                        draw_handles,
                        relationship_endpoint_policies,
                        length(accepted) + 1,
                        effect_index,
                    )
                else
                    continue
                end
                push!(accepted, descriptor)
            end
        elseif record.kind === :SynchronousProcess
            arguments = first(record.normalized_payload)
            for (effect_index, effect) in enumerate(arguments.effects)
                effect isa Assign || continue
                target_record = _stage_state_record(ir, record, effect.target)
                is_model_assignment =
                    target_record !== nothing && target_record.kind === :ModelState
                is_cell_assignment =
                    target_record !== nothing && target_record.kind === :CellState
                if is_model_assignment
                    after_mcs_model_slot += 1
                elseif is_cell_assignment
                    after_mcs_cell_slot += 1
                else
                    after_mcs_site_slot += 1
                end
                push!(
                    after_mcs_assignments, _stage_descriptor(
                        ir,
                        record_index,
                        manifest,
                        T,
                        state_handles,
                        draw_handles,
                        state_layout,
                        CorePotts.CompilerSPI.AfterMCSStage(),
                        is_model_assignment ?
                            after_mcs_model_slot : is_cell_assignment ?
                            after_mcs_cell_slot : after_mcs_site_slot,
                        effect_index,
                        ; history_descriptors, tracker_handles,
                    )
                )
            end
        elseif record.kind in (:RelationshipProcess, :LifecycleProcess)
            arguments = first(record.normalized_payload)
            length(arguments.effects) == 1 &&
                only(arguments.effects) isa Union{Remove, Retune} || continue
            relationship_slot += 1
            push!(
                after_mcs_relationships,
                _relationship_process_stage_descriptor(
                    ir,
                    record_index,
                    manifest,
                    T,
                    state_handles,
                    draw_handles,
                    relationship_endpoint_policies,
                    relationship_slot,
                ),
            )
        elseif record.kind === :HistoryState
            push!(
                after_mcs_commits, only(descriptor for descriptor in history_descriptors if descriptor.source_handle == record_index)
            )
        elseif record.kind === :FieldState
            descriptor = _field_stage_descriptor(
                ir,
                record_index,
                manifest,
                T,
                state_handles,
                draw_handles,
                state_layout,
                after_mcs_site_slot + 1,
                ; history_descriptors,
            )
            if descriptor !== nothing
                after_mcs_site_slot += 1
                push!(after_mcs_iterated, descriptor)
            end
        end
    end
    accepted_groups = _stage_descriptor_groups(accepted)
    before_lifecycle = (
        after_mcs_assignments...,
        after_mcs_relationships...,
    )
    after_lifecycle = (
        after_mcs_iterated...,
        after_mcs_commits...,
    )
    before_groups = _stage_descriptor_groups(before_lifecycle)
    lifecycle_after_groups = _stage_descriptor_groups(after_lifecycle)
    fingerprint = _sha256_hex(
        "potts-stage-execution-plan-v1",
        Tuple(
            (
                    typeof(descriptor),
                    descriptor.source_handle,
                    descriptor.buffer_slot,
                    descriptor.effect,
                ) for descriptor in (
                    accepted..., before_lifecycle..., after_lifecycle...,
                )
        ),
    )
    return CorePotts.CompilerSPI.StageExecutionPlan(
        accepted_groups,
        before_groups,
        lifecycle_after_groups,
        length(accepted),
        after_mcs_site_slot,
        fingerprint,
    )
end
