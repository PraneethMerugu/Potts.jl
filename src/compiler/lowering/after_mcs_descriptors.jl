# Field, history, and other after-MCS descriptor lowering.

function _field_stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    options = _record_options(record)
    target = state_handles[record.identity]
    variable = _state_record_variable(record)
    process_index = findfirst(eachindex(ir.source.records)) do index
        candidate = ir.source.records[index]
        candidate.kind === :EquationProcess || return false
        arguments = first(candidate.normalized_payload)
        any(write -> isequal(write, variable), arguments.writes)
    end
    process_index === nothing && return nothing
    process = ir.source.records[process_index]
    process_options = _record_options(process)
    solver = get(process_options, :solver, nothing)
    solver isa ExplicitDiffusion || throw(ArgumentError(
        "V1 FieldState evolution requires ExplicitDiffusion"
    ))
    substeps = Int(get(process_options, :substeps, 1))
    substeps > 0 || throw(ArgumentError(
        "field evolution substeps must be positive"
    ))
    duration_value = get(process_options, :duration_per_mcs, 1.0)
    duration = T(_numeric_value(
        duration_value,
        _reference_for(manifest.reference_units, duration_value),
    ))
    isfinite(duration) && duration > zero(T) || throw(ArgumentError(
        "field evolution duration_per_mcs must be finite and positive"
    ))
    stencil = get(options, :stencil, :field_stencil)
    stencil isa Symbol || throw(ArgumentError(
        "FieldState stencil must name a declared SpatialRelation"
    ))
    relation = _resource_record(
        ir.source, record, :SpatialRelation, stencil
    )
    relation === nothing && throw(ArgumentError(
        "FieldState stencil `$stencil` does not resolve to a SpatialRelation"
    ))
    relation_handle = only(findall(
        candidate -> candidate.identity == relation.identity,
        ir.source.records,
    ))
    neighborhood = get(_record_options(relation), :neighborhood, nothing)
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "field stencil must use a closed finite neighborhood"
    ))
    dimensions = length(_lattice_shape(ir))
    relation_offsets = _neighborhood_offsets(neighborhood, dimensions)
    read_offsets = Tuple(sort!(unique!([
        ntuple(_ -> 0, dimensions),
        (
            Tuple(Int.(relation_offsets[:, column]))
            for column in axes(relation_offsets, 2)
        )...,
    ])))
    source_kind_value = get(options, :source_kind, nothing)
    source_kind = if source_kind_value === nothing
        Int16(0)
    else
        index = _compiled_kind_index(ir, record, source_kind_value)
        index === nothing && throw(ArgumentError(
            "field source kind is not declared"
        ))
        index
    end
    diffusion = _static_parameter(
        get(options, :diffusion, zero(T)), manifest, T
    )
    decay = _static_parameter(
        get(options, :decay, zero(T)), manifest, T
    )
    secretion = _static_parameter(
        get(options, :secretion, zero(T)), manifest, T
    )
    value = _static_evaluator(
        _compiler_operation_expression(
            _potts_explicit_field_euler,
            (
                CorePotts.StateExpression(target),
                CorePotts.LiteralExpression(Int32(relation_handle)),
                diffusion,
                decay,
                secretion,
                CorePotts.LiteralExpression(source_kind),
                CorePotts.LiteralExpression(duration / T(substeps)),
            ),
            record,
        ),
        CorePotts.AbstractSiteStageEvaluationContext,
        record,
    )
    return CorePotts.CompiledStageDescriptor(
        _static_evaluator(
            CorePotts.LiteralExpression(true),
            CorePotts.AbstractSiteStageEvaluationContext,
            record,
        ),
        value,
        CorePotts.IteratedSiteAssignmentEffect(target, substeps),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (target,),
            (target,),
            CorePotts.FiniteSpatialFootprint(
                CorePotts.IterationSiteFootprintAnchor(), read_offsets
            ),
            _site_write_footprint(ir, CorePotts.AfterMCSStage()),
            CorePotts.ExclusiveWriteAccess(),
        ),
        _stage_support(ir, process_index),
        process_index,
        slot,
    )
end
