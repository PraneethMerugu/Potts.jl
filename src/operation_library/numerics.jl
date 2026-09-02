# Numerical stage operation admissions owned outside biological mechanisms.

function _potts_discrete_field_euler end

operation_transfer(::typeof(_potts_discrete_field_euler), ::Int) =
    _transfer(
        :discrete_field_euler,
        7,
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

struct DiscreteFieldEulerCallable <: CorePotts.CompilerSPI.AbstractContextualOperation end

CorePotts.CompilerSPI.operation_context_supported(
    ::DiscreteFieldEulerCallable,
    ::Type{CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext},
) = true

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:discrete_field_euler},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported discrete-field-Euler operation version $version"
    ))
    return DiscreteFieldEulerCallable()
end

@inline function (operation::DiscreteFieldEulerCallable)(
        arguments::Tuple, context
    )
    state_handle = arguments[1]
    relation_handle = Int32(arguments[2])
    diffusion = arguments[3]
    decay = arguments[4]
    secretion = arguments[5]
    source_kind = Int16(arguments[6])
    timestep = arguments[7]
    T = promote_type(
        typeof(diffusion), typeof(decay), typeof(secretion), typeof(timestep)
    )
    site = CorePotts.CompilerSPI.stage_site(CorePotts.CompilerSPI.IterationStageSite(), context)
    center = T(CorePotts.CompilerSPI.state_value(context, state_handle, site))
    laplace = zero(T)
    for direction in 1:CorePotts.CompilerSPI.relation_count(context, relation_handle)
        neighbor = CorePotts.CompilerSPI.relation_neighbor_site(
            context, relation_handle, site, direction
        )
        neighbor === nothing && continue
        laplace += T(CorePotts.CompilerSPI.state_value(
            context, state_handle, neighbor
        )) - center
    end
    owner = CorePotts.CompilerSPI.site_owner(context, site)
    source = owner > 0 && source_kind != 0 &&
             CorePotts.CompilerSPI.owner_kind(context, owner) == source_kind ?
             T(secretion) : zero(T)
    return max(
        zero(T),
        center + T(timestep) * (
            T(diffusion) * laplace - T(decay) * center + source
        ),
    )
end

numerical_operation_requirements(::DiscreteFieldEuler) =
    ((_potts_discrete_field_euler, 7),)

function numerical_field_rejection(
        ::DiscreteFieldEuler, statement, statements, system
    )
    statement isa FieldState ||
        return "DiscreteFieldEuler must be owned by a FieldState declaration"
    return nothing
end

function numerical_field_stage_descriptor(
        ::DiscreteFieldEuler,
        ir,
        record_index::Integer,
        manifest,
        ::Type{T},
        state_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    options = _record_options(record)
    target = state_handles[record.identity]
    substeps = Int(get(options, :substeps, 1))
    substeps > 0 || throw(ArgumentError(
        "field evolution substeps must be positive"
    ))
    duration_value = get(options, :duration_per_mcs, 1.0)
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
        _compiler_synthesized_operation_expression(
            ir.graph,
            _potts_discrete_field_euler,
            (
                CorePotts.CompilerSPI.StateExpression(target),
                CorePotts.CompilerSPI.LiteralExpression(Int32(relation_handle)),
                diffusion,
                decay,
                secretion,
                CorePotts.CompilerSPI.LiteralExpression(source_kind),
                CorePotts.CompilerSPI.LiteralExpression(duration / T(substeps)),
            ),
            record,
            semantic_role = :process,
            semantic_phase = :AfterMCS,
        ),
        CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext,
        record,
    )
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
            (target,),
            (target,),
            CorePotts.CompilerSPI.FiniteSpatialFootprint(
                CorePotts.CompilerSPI.IterationSiteFootprintAnchor(), read_offsets
            ),
            _site_write_footprint(ir, CorePotts.CompilerSPI.AfterMCSStage()),
            CorePotts.CompilerSPI.ExclusiveWriteAccess(),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
