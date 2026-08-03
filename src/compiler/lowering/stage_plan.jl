# Closed accepted-copy and after-MCS stage-plan orchestration.

function _lower_stage_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        state_layout::CorePotts.StateLayout,
        relationship_endpoint_policies,
    ) where {T <: AbstractFloat}
    accepted = Any[]
    after_mcs_assignments = Any[]
    after_mcs_iterated = Any[]
    after_mcs_relationships = Any[]
    after_mcs_commits = Any[]
    after_mcs_slot = 0
    relationship_slot = 0
    for (record_index, record) in enumerate(ir.source.records)
        if record.kind === :AcceptedCopyProcess
            arguments = first(record.normalized_payload)
            length(arguments.effects) == 1 || continue
            effect = only(arguments.effects)
            descriptor = if effect isa Assign
                _stage_descriptor(
                    ir,
                    record_index,
                    manifest,
                    T,
                    state_handles,
                    draw_handles,
                    CorePotts.AcceptedCopyStage(),
                    length(accepted) + 1,
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
                )
            else
                continue
            end
            push!(accepted, descriptor)
        elseif record.kind === :SynchronousProcess
            arguments = first(record.normalized_payload)
            length(arguments.effects) == 1 &&
                only(arguments.effects) isa Assign || continue
            after_mcs_slot += 1
            push!(after_mcs_assignments, _stage_descriptor(
                ir,
                record_index,
                manifest,
                T,
                state_handles,
                draw_handles,
                CorePotts.AfterMCSStage(),
                after_mcs_slot,
            ))
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
            options = last(record.normalized_payload)
            haskey(options, :of) || throw(ArgumentError(
                "HistoryState requires an explicit `of` source in V1"
            ))
            target = state_handles[record.identity]
            source = _stage_state_handle(
                ir, record, options.of, state_handles
            )
            target_entry = only(filter(
                entry -> entry.handle == target,
                state_layout.entries,
            ))
            source_entry = only(filter(
                entry -> entry.handle == source,
                state_layout.entries,
            ))
            target_shape = Tuple(target_entry.schema.shape)
            source_shape = Tuple(source_entry.schema.shape)
            length(target_shape) == length(source_shape) + 1 &&
                target_shape[1:end-1] == source_shape ||
                throw(ArgumentError(
                    "HistoryState source and target storage shapes are incompatible"
                ))
            condition = _static_evaluator(
                CorePotts.LiteralExpression(true),
                CorePotts.AbstractSiteStageEvaluationContext,
                record,
            )
            value = _static_evaluator(
                CorePotts.LiteralExpression(zero(T)),
                CorePotts.AbstractSiteStageEvaluationContext,
                record,
            )
            push!(after_mcs_commits, CorePotts.CompiledStageDescriptor(
                condition,
                value,
                CorePotts.ShiftAppendEffect(
                    target, source, length(target_shape)
                ),
                CorePotts.AfterMCSStage(),
                CorePotts.ResourceAccess(
                    (target, source),
                    (target,),
                    CorePotts.FiniteSpatialFootprint(
                        CorePotts.IterationSiteFootprintAnchor(),
                        (ntuple(_ -> 0, length(_lattice_shape(ir))),),
                    ),
                    _site_write_footprint(
                        ir, CorePotts.AfterMCSStage()
                    ),
                    CorePotts.ExclusiveWriteAccess(),
                ),
                _stage_support(ir, record_index),
                record_index,
                0,
            ))
        elseif record.kind === :FieldState
            descriptor = _field_stage_descriptor(
                ir,
                record_index,
                manifest,
                T,
                state_handles,
                after_mcs_slot + 1,
            )
            if descriptor !== nothing
                after_mcs_slot += 1
                push!(after_mcs_iterated, descriptor)
            end
        end
    end
    targets = map(
        descriptor -> descriptor.effect.target,
        after_mcs_assignments,
    )
    allunique(targets) || throw(ArgumentError(
        "V1 permits at most one synchronous assignment per state block"
    ))
    accepted_groups = _stage_descriptor_groups(accepted)
    before_lifecycle = (
        after_mcs_assignments...,
        after_mcs_relationships...,
    )
    after_lifecycle = (
        after_mcs_iterated...,
        after_mcs_commits...,
    )
    after_mcs = (before_lifecycle..., after_lifecycle...)
    before_groups = _stage_descriptor_groups(before_lifecycle)
    lifecycle_after_groups = _stage_descriptor_groups(after_lifecycle)
    after_groups = (before_groups..., lifecycle_after_groups...)
    fingerprint = _sha256_hex(
        "potts-stage-execution-plan-v1",
        Tuple((
            typeof(descriptor),
            descriptor.source_handle,
            descriptor.buffer_slot,
            descriptor.effect,
        ) for descriptor in (accepted..., after_mcs...)),
    )
    return CorePotts.StageExecutionPlan(
        accepted_groups,
        before_groups,
        lifecycle_after_groups,
        after_groups,
        length(accepted),
        after_mcs_slot,
        fingerprint,
    )
end
