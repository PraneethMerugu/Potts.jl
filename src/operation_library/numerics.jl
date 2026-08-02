# Numerical stage operation admissions owned outside biological mechanisms.

function _potts_explicit_field_euler end

operation_transfer(::typeof(_potts_explicit_field_euler), ::Int) =
    _transfer(
        :explicit_field_euler,
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
        owner = :PottsToolkitNumerics,
    )

struct ExplicitFieldEulerCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::ExplicitFieldEulerCallable,
    ::Type{CorePotts.AbstractSiteStageEvaluationContext},
) = true

function CorePotts.operation_callable(
        ::Val{:explicit_field_euler},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported explicit-field-Euler operation version $version"
    ))
    return ExplicitFieldEulerCallable()
end

@inline function (operation::ExplicitFieldEulerCallable)(
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
    site = CorePotts.stage_site(CorePotts.IterationStageSite(), context)
    center = T(CorePotts.state_value(context, state_handle, site))
    laplace = zero(T)
    for direction in 1:CorePotts.relation_count(context, relation_handle)
        neighbor = CorePotts.relation_neighbor_site(
            context, relation_handle, site, direction
        )
        neighbor === nothing && continue
        laplace += T(CorePotts.state_value(
            context, state_handle, neighbor
        )) - center
    end
    owner = CorePotts.site_owner(context, site)
    source = owner > 0 && source_kind != 0 &&
             CorePotts.owner_kind(context, owner) == source_kind ?
             T(secretion) : zero(T)
    return max(
        zero(T),
        center + T(timestep) * (
            T(diffusion) * laplace - T(decay) * center + source
        ),
    )
end

numerical_operation_requirements(::ExplicitDiffusion) =
    ((_potts_explicit_field_euler, 7),)

function numerical_process_rejection(
        ::ExplicitDiffusion, statement, statements, system
    )
    arguments = _statement_arguments(statement)
    fields = filter(candidate -> candidate isa FieldState, statements)
    length(fields) == 1 ||
        return "equation lowering requires exactly one FieldState"
    variable = _statement_arguments(only(fields)).variable
    length(arguments.writes) == 1 && isequal(only(arguments.writes), variable) ||
        return "EquationProcess writes must identify the compiled FieldState"
    isempty(arguments.equations) &&
        return "EquationProcess requires at least one equation"
    all(equation -> any(isequal(equation), ModelingToolkitBase.equations(system)),
        arguments.equations) ||
        return "EquationProcess equations must be present in PottsSystem.equations"
    return nothing
end

function numerical_field_stage_descriptor(
        ::ExplicitDiffusion,
        ir,
        record_index::Integer,
        process_index::Integer,
        manifest,
        ::Type{T},
        state_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    options = _record_options(record)
    target = state_handles[record.identity]
    process = ir.source.records[process_index]
    process_options = _record_options(process)
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
        _compiler_synthesized_operation_expression(
            ir.graph,
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
            semantic_role = :process,
            semantic_phase = :AfterMCS,
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
