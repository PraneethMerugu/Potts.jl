# Generic accepted-copy and after-MCS staged-effect lowering.

function _stage_root(
        ir::AnalyzedTermIR,
        record_index::Integer,
        role::Symbol,
    )
    index = findfirst(root ->
        root.record == record_index && root.role === role,
        ir.graph.roots,
    )
    return index === nothing ? nothing : ir.graph.roots[index].node
end

function _stage_state_handle(
        ir::AnalyzedTermIR,
        owner::QualifiedStatement,
        value,
        handles,
    )
    for record in ir.source.records
        haskey(handles, record.identity) || continue
        variable = _state_record_variable(record)
        variable !== nothing && isequal(variable, value) &&
            return handles[record.identity]
        if value isa AbstractPottsStatement &&
                statement_id(value) == record.identity.local_id &&
                record.identity in owner.resources
            return handles[record.identity]
        end
    end
    throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :unresolved_stage_write,
            owner.identity,
            repr(value),
            owner.identity.path,
            "one declared writable state resource",
            "no matching state handle",
            (),
            owner.source,
        ),),
    ))
end

function _stage_evaluator(
        ir::AnalyzedTermIR,
        record_index::Integer,
        role::Symbol,
        fallback,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        binding::Union{Nothing, CorePotts.AbstractStageSiteSelector},
    ) where {T <: AbstractFloat}
    root = _stage_root(ir, record_index, role)
    expression = if root === nothing
        _static_literal(fallback, manifest, T)
    else
        _lower_static_node(
            ir.graph,
            ir,
            root,
            manifest,
            T,
            state_handles,
            draw_handles,
            Dict{Int32, CorePotts.AbstractStaticExpression}(),
            binding,
        )
    end
    execution_context = binding isa CorePotts.ProposalTargetStageSite ?
        CorePotts.AbstractProposalEvaluationContext :
        binding isa CorePotts.IterationStageSite ?
        CorePotts.AbstractSiteStageEvaluationContext :
        CorePotts.AbstractRelationshipStageEvaluationContext
    return _static_evaluator(
        expression,
        execution_context,
        ir.source.records[record_index],
    )
end

function _stage_support(
        ir::AnalyzedTermIR,
        record_index::Integer,
    )
    candidate_index = findfirst(
        candidate -> candidate.record == record_index,
        ir.candidates,
    )
    if candidate_index !== nothing
        return _descriptor_support(ir, ir.candidates[candidate_index])
    end
    record = ir.source.records[record_index]
    sequential = any(admission ->
        admission.engine === :sequential && admission.admitted,
        record.engine_admission,
    )
    checkerboard = any(admission ->
        admission.engine === :checkerboard && admission.admitted,
        record.engine_admission,
    )
    return CorePotts.DescriptorSupport(
        sequential, checkerboard, true, true
    )
end
