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
    return CorePotts.StaticEvaluator(expression)
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

function _stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        stage::CorePotts.AbstractCompiledStage,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    effects = arguments.effects
    length(effects) == 1 || throw(ArgumentError(
        "V1 staged assignment descriptors require exactly one effect"
    ))
    effect = only(effects)
    effect isa Assign || throw(ArgumentError(
        "V1 staged assignment descriptors require Assign"
    ))
    binding = stage isa CorePotts.AcceptedCopyStage ?
              CorePotts.ProposalTargetStageSite() :
              CorePotts.IterationStageSite()
    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        true,
        manifest,
        T,
        state_handles,
        draw_handles,
        binding,
    )
    value = _stage_evaluator(
        ir,
        record_index,
        :effect_1_value,
        effect.value,
        manifest,
        T,
        state_handles,
        draw_handles,
        binding,
    )
    target = _stage_state_handle(ir, record, effect.target, state_handles)
    reads = _record_state_handles(ir, record, state_handles)
    target in reads || (reads = (reads..., target))
    footprint = stage isa CorePotts.AcceptedCopyStage ?
                CorePotts.ProposalContextFootprint() :
                CorePotts.FiniteSpatialFootprint(())
    return CorePotts.CompiledStageDescriptor(
        condition,
        value,
        CorePotts.SiteAssignmentEffect(target),
        stage,
        CorePotts.ResourceAccess(reads, (target,), footprint),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end

function _relationship_create_stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    length(arguments.effects) == 1 && only(arguments.effects) isa Create ||
        throw(ArgumentError(
            "a relationship-create stage requires exactly one Create effect"
        ))
    effect = only(arguments.effects)
    relationship = _resource_record(
        ir.source, record, :RelationshipState, effect.relationship
    )
    relationship === nothing && throw(ArgumentError(
        "relationship-create effect does not resolve to a declared store"
    ))
    relationships = filter(
        candidate -> candidate.kind === :RelationshipState,
        ir.source.records,
    )
    length(relationships) == 1 || throw(ArgumentError(
        "V1 relationship effects require exactly one relationship store"
    ))
    relationship.identity == only(relationships).identity ||
        throw(ArgumentError(
            "relationship-create effect resolves to an unavailable store"
        ))

    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        true,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )
    endpoint_a = _stage_evaluator(
        ir,
        record_index,
        :effect_1_endpoint_a,
        effect.endpoint_a,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )
    endpoint_b = _stage_evaluator(
        ir,
        record_index,
        :effect_1_endpoint_b,
        effect.endpoint_b,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )

    relationship_options = _record_options(relationship)
    declared_payload = get(
        relationship_options, :payload, NamedTuple()
    )
    declared_payload isa NamedTuple && effect.payload isa NamedTuple ||
        throw(ArgumentError(
            "relationship payload declarations and requests must be named tuples"
        ))
    keys(effect.payload) == keys(declared_payload) || throw(ArgumentError(
        "relationship-create payload must exactly match its declared schema"
    ))
    payload = Tuple(
        _stage_evaluator(
            ir,
            record_index,
            Symbol(:effect_1_payload_, name),
            getproperty(effect.payload, name),
            manifest,
            T,
            state_handles,
            draw_handles,
            CorePotts.ProposalTargetStageSite(),
        )
        for name in keys(declared_payload)
    )

    endpoints = get(relationship_options, :endpoints, nothing)
    endpoints isa Undirected || throw(ArgumentError(
        "V1 relationship creation currently requires Undirected endpoints"
    ))
    kind_a = _compiled_kind_index(ir, _kind_name(endpoints.kind_a))
    kind_b = _compiled_kind_index(ir, _kind_name(endpoints.kind_b))
    (kind_a === nothing || kind_b === nothing) && throw(ArgumentError(
        "relationship endpoint kind is not declared"
    ))
    kind_condition = CorePotts.OperationExpression(
        RelationshipEndpointKindsCallable(),
        endpoint_a.expression,
        endpoint_b.expression,
        CorePotts.LiteralExpression(kind_a),
        CorePotts.LiteralExpression(kind_b),
    )
    compiled_condition = CorePotts.StaticEvaluator(
        CorePotts.OperationExpression(
            CorePotts.OrderedFold(&),
            condition.expression,
            kind_condition,
        )
    )
    priority = _numeric_value(effect.priority)
    priority isa Real && isinteger(priority) || throw(ArgumentError(
        "relationship request priority must be structurally resolved"
    ))
    reads = _record_state_handles(ir, record, state_handles)
    return CorePotts.CompiledStageDescriptor(
        compiled_condition,
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(zero(T))),
        CorePotts.RelationshipCreateEffect(
            1,
            endpoint_a,
            endpoint_b,
            payload,
            Int(priority),
        ),
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            reads,
            (),
            CorePotts.ProposalContextFootprint(),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end

function _relationship_remove_stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    length(arguments.effects) == 1 && only(arguments.effects) isa Remove ||
        throw(ArgumentError(
            "a relationship lifecycle stage requires exactly one Remove effect"
        ))
    effect = only(arguments.effects)
    relationship = _resource_record(
        ir.source, record, :RelationshipState, effect.relationship
    )
    relationship === nothing && throw(ArgumentError(
        "relationship removal does not resolve to a declared store"
    ))
    relationships = filter(
        candidate -> candidate.kind === :RelationshipState,
        ir.source.records,
    )
    length(relationships) == 1 &&
        relationship.identity == only(relationships).identity ||
        throw(ArgumentError(
            "V1 relationship effects require exactly one relationship store"
        ))
    arguments.domain isa Edges && _same_domain_resource(
        arguments.domain.relationship, effect.relationship
    ) || throw(ArgumentError(
        "relationship removal must iterate the affected relationship store"
    ))
    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        false,
        manifest,
        T,
        state_handles,
        draw_handles,
        nothing,
    )
    maximum_degree = Int(_numeric_value(get(
        _record_options(relationship), :maximum_degree, 0
    )))
    reads = _record_state_handles(ir, record, state_handles)
    return CorePotts.CompiledStageDescriptor(
        condition,
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(zero(T))),
        CorePotts.RelationshipRemoveEffect(1),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            reads,
            (),
            CorePotts.IncidentRelationshipFootprint(maximum_degree),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end

function _stage_descriptor_groups(descriptors)
    types = DataType[]
    grouped = Vector{Vector{Any}}()
    for descriptor in descriptors
        descriptor_type = typeof(descriptor)
        index = findfirst(==(descriptor_type), types)
        if index === nothing
            push!(types, descriptor_type)
            push!(grouped, Any[descriptor])
        else
            push!(grouped[index], descriptor)
        end
    end
    groups = ()
    for (descriptor_type, instances) in zip(types, grouped)
        typed = descriptor_type[instance for instance in instances]
        groups = (groups..., CorePotts.StageDescriptorGroup(typed))
    end
    return groups
end

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
    source_kind_value = get(options, :source_kind, nothing)
    source_kind = if source_kind_value === nothing
        Int16(0)
    else
        index = _compiled_kind_index(ir, _kind_name(source_kind_value))
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
    value = CorePotts.StaticEvaluator(CorePotts.OperationExpression(
        ExplicitFieldEulerCallable(),
        CorePotts.StateExpression(target),
        CorePotts.LiteralExpression(Int32(relation_handle)),
        diffusion,
        decay,
        secretion,
        CorePotts.LiteralExpression(source_kind),
        CorePotts.LiteralExpression(duration / T(substeps)),
    ))
    return CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        value,
        CorePotts.IteratedSiteAssignmentEffect(target, substeps),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (target,),
            (target,),
            CorePotts.FiniteSpatialFootprint((Int32(relation_handle),)),
        ),
        _stage_support(ir, process_index),
        process_index,
        slot,
    )
end

function _lower_stage_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        state_layout::CorePotts.StateLayout,
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
                only(arguments.effects) isa Remove || continue
            relationship_slot += 1
            push!(
                after_mcs_relationships,
                _relationship_remove_stage_descriptor(
                    ir,
                    record_index,
                    manifest,
                    T,
                    state_handles,
                    draw_handles,
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
            condition = CorePotts.StaticEvaluator(
                CorePotts.LiteralExpression(true)
            )
            value = CorePotts.StaticEvaluator(
                CorePotts.LiteralExpression(zero(T))
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
                    CorePotts.FiniteSpatialFootprint(()),
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
    after_mcs = (
        after_mcs_assignments...,
        after_mcs_iterated...,
        after_mcs_relationships...,
        after_mcs_commits...,
    )
    after_groups = _stage_descriptor_groups(after_mcs)
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
        after_groups,
        length(accepted),
        after_mcs_slot,
        fingerprint,
    )
end
