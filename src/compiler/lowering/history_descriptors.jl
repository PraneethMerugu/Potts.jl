# Lower each declared sampling law once. Read projections and the final stage
# plan reuse these exact descriptors; no second source-binding inventory exists.
function _lower_history_descriptors(ir::AnalyzedTermIR, ::Type{T}, state_handles, state_layout) where {T <: AbstractFloat}
    descriptors = CorePotts.CompilerSPI.CompiledStageDescriptor[]
    for (record_index, record) in enumerate(ir.source.records)
        record.kind === :HistoryState || continue
        source_record = _state_sample_record(ir.source, record)
        target = state_handles[record.identity]
        source = state_handles[source_record.identity]
        target_entry = only(entry for entry in state_layout.entries if entry.handle == target)
        cadence, cadence_value = _completed_mcs_cadence(_statement_option(record, :cadence, EveryMCS()))
        footprint = source_record.kind === :ModelState ? CorePotts.CompilerSPI.ModelFootprint() :
            source_record.kind === :CellState ? CorePotts.CompilerSPI.OwnerFootprint() :
            _site_write_footprint(ir, CorePotts.CompilerSPI.AfterMCSStage())
        descriptor = CorePotts.CompilerSPI.CompiledStageDescriptor(
            _static_evaluator(CorePotts.CompilerSPI.LiteralExpression(true), CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext, record),
            _static_evaluator(CorePotts.CompilerSPI.LiteralExpression(zero(T)), CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext, record),
            CorePotts.CompilerSPI.ShiftAppendEffect(target, source, length(target_entry.schema.shape); cadence, cadence_value),
            CorePotts.CompilerSPI.AfterMCSStage(),
            CorePotts.CompilerSPI.ResourceAccess((target, source), (target,), footprint, footprint, CorePotts.CompilerSPI.ExclusiveWriteAccess()),
            _stage_support(ir, record_index), record_index, 0,
        )
        CorePotts.CompilerSPI.history_source((descriptor,), state_layout, target)
        push!(descriptors, descriptor)
    end
    return Tuple(descriptors)
end
