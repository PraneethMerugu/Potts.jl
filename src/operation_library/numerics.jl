# Numerical stage operation admissions owned outside biological mechanisms.

function _potts_discrete_field_stencil_rate end

operation_transfer(::typeof(_potts_discrete_field_stencil_rate), ::Int) =
    _transfer(
    :discrete_field_stencil_rate,
    6,
    :real,
    :declared;
    footprint_rule = NeighborhoodFootprintRule(
        IterationNeighborhoodAnchor()
    ),
    gpu = false,
    allowed_roles = (:process,),
    allowed_phases = (:AfterMCS,),
    required_context = :iteration,
    owner = :PottsNumerics,
)

struct DiscreteFieldStencilRateCallable <: CorePotts.CompilerSPI.AbstractContextualOperation end

CorePotts.CompilerSPI.operation_context_supported(
    ::DiscreteFieldStencilRateCallable,
    ::Type{CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext},
) = true

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:discrete_field_stencil_rate},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(
        ArgumentError(
            "unsupported discrete-field stencil-rate operation version $version"
        )
    )
    return DiscreteFieldStencilRateCallable()
end

@inline function (operation::DiscreteFieldStencilRateCallable)(
        arguments::Tuple, context
    )
    state_handle = arguments[1]
    relation_handle = Int32(arguments[2])
    diffusion = arguments[3]
    decay = arguments[4]
    secretion = arguments[5]
    source_kind = Int16(arguments[6])
    T = promote_type(
        typeof(diffusion), typeof(decay), typeof(secretion)
    )
    site = CorePotts.CompilerSPI.stage_site(CorePotts.CompilerSPI.IterationStageSite(), context)
    center = T(CorePotts.CompilerSPI.state_value(context, state_handle, site))
    laplace = zero(T)
    for direction in 1:CorePotts.CompilerSPI.relation_count(context, relation_handle)
        neighbor = CorePotts.CompilerSPI.relation_neighbor_site(
            context, relation_handle, site, direction
        )
        neighbor === nothing && continue
        laplace += T(
            CorePotts.CompilerSPI.state_value(
                context, state_handle, neighbor
            )
        ) - center
    end
    owner = CorePotts.CompilerSPI.site_owner(context, site)
    source = owner > 0 && source_kind != 0 &&
        CorePotts.CompilerSPI.owner_kind(context, owner) == source_kind ?
        T(secretion) : zero(T)
    return T(diffusion) * laplace - T(decay) * center + source
end

function numerical_operation_requirements(::DiscreteFieldEuler, record::QualifiedStatement)
    common = (((+), 2), ((*), 2), (max, 2), (_potts_iteration_bound_state_value, 1))
    return haskey(_record_options(record), :rhs) ? common :
        (common..., (_potts_discrete_field_stencil_rate, 6))
end

function numerical_field_rejection(
        ::DiscreteFieldEuler, statement, statements, system
    )
    statement isa FieldState ||
        return "DiscreteFieldEuler must be owned by a FieldState declaration"
    options = _statement_options(statement)
    if haskey(options, :rhs)
        any(name -> haskey(options, name), (:diffusion, :decay, :secretion, :source_kind)) &&
            return "an explicit field rhs is the complete rate and cannot be combined with diffusion, decay, secretion, or source_kind shorthand"
    end
    _statement_phase(statement) isa AfterMCS ||
        return "DiscreteFieldEuler evolves at the AfterMCS boundary"
    return nothing
end

function _discrete_field_stencil_expression(
        ir,
        record,
        manifest,
        ::Type{T},
        target,
    ) where {T <: AbstractFloat}
    options = _record_options(record)
    stencil = get(options, :stencil, :field_stencil)
    stencil isa Symbol || throw(
        ArgumentError(
            "FieldState stencil must name a declared SpatialRelation"
        )
    )
    relation = _resource_record(
        ir.source, record, :SpatialRelation, stencil
    )
    relation === nothing && throw(
        ArgumentError(
            "FieldState stencil `$stencil` does not resolve to a SpatialRelation"
        )
    )
    relation_handle = only(
        findall(
            candidate -> candidate.identity == relation.identity,
            ir.source.records,
        )
    )
    neighborhood = get(_record_options(relation), :neighborhood, nothing)
    neighborhood isa Union{VonNeumann, Moore} || throw(
        ArgumentError(
            "field stencil must use a closed finite neighborhood"
        )
    )
    dimensions = length(_lattice_shape(ir))
    relation_offsets = _neighborhood_offsets(neighborhood, dimensions)
    read_offsets = Tuple(
        sort!(
            unique!(
                [
                    ntuple(_ -> 0, dimensions),
                    (
                        Tuple(Int.(relation_offsets[:, column]))
                            for column in axes(relation_offsets, 2)
                    )...,
                ]
            )
        )
    )
    source_kind_value = get(options, :source_kind, nothing)
    source_kind = if source_kind_value === nothing
        Int16(0)
    else
        index = _compiled_kind_index(ir, record, source_kind_value)
        index === nothing && throw(
            ArgumentError(
                "field source kind is not declared"
            )
        )
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
    expression = _compiler_synthesized_operation_expression(
        ir.graph,
        _potts_discrete_field_stencil_rate,
        (
            CorePotts.CompilerSPI.StateExpression(target),
            CorePotts.CompilerSPI.LiteralExpression(Int32(relation_handle)),
            diffusion,
            decay,
            secretion,
            CorePotts.CompilerSPI.LiteralExpression(source_kind),
        ),
        record,
        semantic_role = :process,
        semantic_phase = :AfterMCS,
    )
    footprint = CorePotts.CompilerSPI.FiniteSpatialFootprint(
        CorePotts.CompilerSPI.IterationSiteFootprintAnchor(), read_offsets
    )
    return (; expression, footprint)
end

function numerical_field_stage_descriptor(
        ::DiscreteFieldEuler, ir, record_index::Integer, manifest,
        ::Type{T}, state_handles, draw_handles, state_layout, slot::Integer;
        history_descriptors,
    ) where {T <: AbstractFloat}
    C = CorePotts.CompilerSPI
    record = ir.source.records[record_index]
    options = _record_options(record)
    target = state_handles[record.identity]
    substeps_value = get(options, :substeps, 1)
    substeps_value isa Integer && !(substeps_value isa Bool) && substeps_value > 0 ||
        throw(ArgumentError("field evolution substeps must be a positive integer, not Bool"))
    substeps = Int(substeps_value)
    duration_value = get(options, :duration_per_mcs, 1.0)
    duration = T(_numeric_value(duration_value, _reference_for(manifest.reference_units, duration_value)))
    isfinite(duration) && duration > zero(T) || throw(
        ArgumentError(
            "field evolution duration_per_mcs must be finite and positive"
        )
    )
    site_footprint = _site_write_footprint(ir, C.AfterMCSStage())
    rate, read_footprint, step_scale = if haskey(options, :rhs)
        root = _stage_root(ir, record_index, :field_rhs)
        root === nothing && error("an explicit field RHS has no normalized expression root")
        rate_unit = ir.facts.units[root]
        duration_unit = duration_value isa DynamicQuantities.UnionAbstractQuantity ?
            _canonical_dimension(DynamicQuantities.dimension(duration_value)) : :dimensionless
        state_unit = _declared_record_unit(record, ir.source)
        if !_is_polymorphic_zero_unit(rate_unit) && !_unit_compatible(state_unit, _unit_product(rate_unit, duration_unit))
            throw(
                PottsValidationError(
                    :descriptor_lowering, (
                        PottsDiagnostic(
                            :field_rhs_units, record.identity, repr(options.rhs), record.identity.path,
                            "rhs × duration with state dimension $(repr(state_unit))",
                            "rhs dimension $(repr(rate_unit)) and duration dimension $(repr(duration_unit))",
                            (), record.source,
                        ),
                    )
                )
            )
        end
        ir.facts.shape[root] == () && ir.facts.result_type[root] <: Real ||
            throw(ArgumentError("DiscreteFieldEuler requires a scalar real rate per site"))
        rhs = _stage_evaluator(
            ir, record_index, :field_rhs, options.rhs, manifest, T,
            state_handles, draw_handles, C.IterationStageSite(); state_layout, history_descriptors
        )
        # The authored rate and duration use independent reference dimensions;
        # their product must enter the field's normalized state coordinates.
        coefficient = setprecision(BigFloat, 256) do
            conversion = BigFloat(_expression_reference_scale(rate_unit, manifest)) *
                BigFloat(_expression_reference_scale(duration_unit, manifest)) /
                BigFloat(_expression_reference_scale(state_unit, manifest))
            T(BigFloat(duration) * conversion / substeps)
        end
        isfinite(coefficient) && coefficient > zero(T) ||
            throw(ArgumentError("field rate × duration reference conversion must be finite and positive at $T precision"))
        center_read = _spatial_anchor_fact(IterationSiteAnchor(), length(_lattice_shape(ir)))
        footprint = _record_read_footprint(ir, record_index; additional_reads = center_read)
        (rhs.expression, footprint, coefficient)
    else
        stencil = _discrete_field_stencil_expression(ir, record, manifest, T, target)
        (stencil.expression, stencil.footprint, duration / T(substeps))
    end
    operation(f, args) = _compiler_synthesized_operation_expression(
        ir.graph, f, args, record; semantic_role = :process, semantic_phase = :AfterMCS,
    )
    center = operation(_potts_iteration_bound_state_value, (C.StateExpression(target),))
    # Both declaration forms use this one clipped explicit-Euler update.
    delta = operation(*, (C.LiteralExpression(step_scale), rate))
    expression = operation(max, (C.LiteralExpression(zero(T)), operation(+, (center, delta))))
    value = _static_evaluator(expression, C.AbstractSiteStageEvaluationContext, record)
    reads = _record_state_handles(ir, record, state_handles; expressions = (expression,))
    target in reads || (reads = (reads..., target))
    return CorePotts.CompilerSPI.CompiledStageDescriptor(
        _static_evaluator(
            CorePotts.CompilerSPI.LiteralExpression(true),
            CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext,
            record,
        ),
        value,
        CorePotts.CompilerSPI.IteratedSiteAssignmentEffect(target, substeps),
        CorePotts.CompilerSPI.AfterMCSStage(),
        CorePotts.CompilerSPI.ResourceAccess(
            reads,
            (target,),
            read_footprint,
            site_footprint,
            CorePotts.CompilerSPI.ExclusiveWriteAccess(),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
