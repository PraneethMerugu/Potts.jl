"""Cold inspection of planned and prepared LocalMath programs.

This file projects facts from the semantic law, validated binding, physical
lowering, and prepared runtime. Execution never consumes these projections.
"""

@inline function _stage_parameter_slot_inspection(
        slot::_StageParameterSlot{T}) where {T}
    bounds = slot.bounds isa _ClosedParameterBounds ?
        (lower = slot.bounds.lower, upper = slot.bounds.upper) : nothing
    return (name = slot.name, type = T, bounds)
end
_stage_parameter_layout_inspection(layout::_StageParameterLayout) =
    map(_stage_parameter_slot_inspection, layout.slots)

_lowering_identity(::_StageProgramLowering) =
    :stage_local_erased_kernelabstractions_v1

_parameter_inspection(declaration::Parameter) = (
    name = declaration.name,
    type = _parameter_type(declaration),
    bounds = declaration.bounds isa _ClosedParameterBounds ?
        (lower = declaration.bounds.lower,
            upper = declaration.bounds.upper) : nothing,
)

_space_kind_inspection(::Space{_IndexSpaceKind}) = :index
_space_kind_inspection(::Space{_ProductSpaceKind}) = :product
_space_kind_inspection(::Space{K}) where {K} = K
_space_structure_inspection(::Space{K,N,_PlainSpaceStructure}) where {K,N} = nothing
_space_structure_inspection(
        space::Space{_ProductSpaceKind,N,S}) where {N,S<:_ProductSpaceStructure} =
    (factors = map(_space_inspection, _space_factors(space)),)

_space_inspection(space::Space) = (
    identity = semantic_identity(space),
    kind = _space_kind_inspection(space),
    extent = size(space),
    structure = _space_structure_inspection(space),
)

_relation_representation_inspection(::_IdentityRelation) = (family = :identity,)
_relation_representation_inspection(value::_AffineRelation) =
    (family = :affine, offsets = value.offsets, origin = value.origin)
_relation_representation_inspection(value::_FixedRelation) =
    (family = :fixed, degree = value.degree)
_relation_representation_inspection(value::_ProductRelation) =
    (family = :product, factors = map(semantic_identity, value.factors),
        degree = value.degree)
_relation_representation_inspection(value::_ComposedRelation) =
    (family = :composed, factors = map(semantic_identity, value.factors),
        degree = value.degree)
_relation_representation_inspection(value::_BoundaryRelation) =
    (family = :boundary, base = semantic_identity(value.base),
        policy = _boundary_policy_facts(value.policy), degree = value.degree)
_relation_representation_inspection(value::_RuntimeRelation) =
    (family = :runtime, degree = value.degree, key_type = value.key_type,
        ownership = value.ownership)
_relation_representation_inspection(value::_FieldIndexRelation) =
    (family = :field_index, keys = semantic_identity(value.keys),
        degree = value.degree, optional = value.optional)
_relation_representation_inspection(value::_MaskedRelation) =
    (family = :masked, base = semantic_identity(value.base),
        mask = semantic_identity(value.mask), degree = value.degree)
_relation_representation_inspection(value::_SelectedRelation) =
    (family = :selected, base = semantic_identity(value.base),
        injection = semantic_identity(value.injection), degree = value.degree)
_relation_representation_inspection(value::_InverseRelation) =
    (family = :inverse, forward = semantic_identity(value.forward),
        degree = value.degree)
_relation_representation_inspection(value::_PackedRelation) =
    (family = :packed, degree = value.degree, capacity = value.capacity,
        layout = value.layout, ownership = value.ownership)

_relation_footprint_inspection(relation::Relation{_IdentityRelation}) =
    (strength = :exact, kind = :identity)
_relation_footprint_inspection(relation::Relation{<:_AffineRelation}) =
    merge((strength = :exact,), _relation_footprint(relation))
function _relation_footprint_inspection(
        relation::Relation{<:_BoundaryRelation})
    relation.representation.base.representation isa _AffineRelation ||
        return merge((strength = :bounded,), _relation_footprint(relation))
    return merge((strength = :exact,), _relation_footprint(relation))
end
_relation_footprint_inspection(
        relation::Relation{<:Union{_RuntimeRelation,_PackedRelation}}) =
    (strength = :opaque, kind = :runtime_bounded,
        degree = degree_bound(relation))
_relation_footprint_inspection(relation::Relation{<:_FieldIndexRelation}) =
    (strength = :opaque, kind = :bounded_indirect,
        degree = degree_bound(relation),
        keys = semantic_identity(relation.representation.keys))
_relation_footprint_inspection(relation::Relation) =
    merge((strength = :bounded,), _relation_footprint(relation))

_ownership_inspection(::_ComputedOwnership) = :computed
_ownership_inspection(::_LocalOwnership) = :local
_ownership_inspection(::_SharedOwnership) = :shared
_ownership_inspection(::_GhostOwnership) = :ghost
_ownership_inspection(::_ExternalOwnership) = :external
_ownership_inspection(::_TemporaryOwnership) = :temporary

function _relation_inspection(relation::Relation, proof)
    proof_value = proof === nothing ? nothing : (
        ownership = _ownership_inspection(proof.binding_schema.ownership),
        bounds = proof.evidence.bounds,
        multiplicity = proof.evidence.multiplicity,
        coverage = proof.evidence.coverage,
        canonical_order = proof.evidence.canonical_order,
        physical_representation = proof.binding_schema.representation,
        physical_leaves = proof.binding_schema.physical_leaves,
    )
    return (
        identity = semantic_identity(relation),
        domain = semantic_identity(domain(relation)),
        codomain = semantic_identity(codomain(relation)),
        schema_epoch = schema_epoch(relation),
        representation = _relation_representation_inspection(
            relation.representation),
        proof = proof_value,
        footprint = _relation_footprint_inspection(relation),
    )
end

_collection_access_law_inspection(::_BoundedGroup{K}) where {K} =
    (kind = :bounded_group, maximum = K)
_collection_access_law_inspection(::_SourcePositionsAccess{K,L}) where {K,L} =
    (kind = :source_position, width = K, lane = L)

_dependency_inspection(::Nothing) = nothing
_dependency_inspection(value::_ExternalFieldDependency) =
    (kind = :external, resource = :field, identity = value.field_id)
_dependency_inspection(value::_PrecedingFieldDependency) =
    (kind = :stage, resource = :field, identity = value.field_id,
        stage = value.stage)
_dependency_inspection(value::_PrecedingCollectionDependency) =
    (kind = :stage, resource = :collection,
        identity = value.collection_id, stage = value.stage,
        role = value.role)
_dependency_inspection(value::_RelationUse) =
    (kind = :relation, identity = value.relation_id)

function _read_inspection(role::Symbol, access::Access, dependency = nothing)
    return (
        role,
        kind = :field,
        identity = semantic_identity(access.field),
        value_type = eltype(access.field),
        space = semantic_identity(access.field.space),
        relation = semantic_identity(access.relation),
        version = :stage_entry,
        mode = access.mode isa _RequiredAccess ? :required : :samples,
        ghost = access.ghost === nothing ? nothing :
            semantic_identity(access.ghost),
        producer = _dependency_inspection(dependency),
    )
end
function _read_inspection(
        role::Symbol, access::CollectionAccess, dependency = nothing)
    return (
        role,
        kind = :collection,
        identity = semantic_identity(access.collection),
        value_type = eltype(access.collection),
        capacity = access.collection.capacity,
        law = _collection_access_law_inspection(access.law),
        producer = _dependency_inspection(dependency),
    )
end

_control_part_inspection(::_NoPrefix) = (kind = :none,)
_control_part_inspection(value::_ParameterPrefix) =
    (kind = :parameter, parameter = value.parameter.name)
_control_part_inspection(value::_FieldPrefix) =
    (kind = :field, identity = semantic_identity(value.field))
_control_part_inspection(value::_CollectionCount) =
    (kind = :collection_count,
        identity = semantic_identity(value.collection))
_control_part_inspection(::_NoMask) = (kind = :none,)
_control_part_inspection(value::_MaskSelection) =
    (kind = :field, identity = semantic_identity(value.field))
_control_part_inspection(::_NoSubset) = (kind = :none,)
_control_part_inspection(value::_SubsetSelection) =
    (kind = :relation, identity = semantic_identity(value.relation))
_control_part_inspection(::_NoGate) = (kind = :none,)
_control_part_inspection(value::_ParameterGate) =
    (kind = :parameter, parameter = value.parameter.name)
_control_part_inspection(value::_FieldGate) =
    (kind = :field, identity = semantic_identity(value.field))
_control_part_with_producer(value, ::Nothing) =
    _control_part_inspection(value)
_control_part_with_producer(value, dependency) = merge(
    _control_part_inspection(value),
    (producer = _dependency_inspection(dependency),),
)
function _control_inspection(control::Control, dependencies = nothing)
    producers = dependencies === nothing ?
        (prefix = nothing, mask = nothing, subset = nothing, gate = nothing) :
        (prefix = dependencies.collection_prefix === nothing ?
                dependencies.control.prefix : dependencies.collection_prefix,
            mask = dependencies.control.mask,
            subset = dependencies.control.subset,
            gate = dependencies.control.gate)
    return (
        prefix = _control_part_with_producer(
            control.prefix, producers.prefix),
        mask = _control_part_with_producer(control.mask, producers.mask),
        subset = _control_part_with_producer(
            control.subset, producers.subset),
        gate = _control_part_with_producer(control.gate, producers.gate),
    )
end

function _stage_reads_inspection(stage::Stage, dependencies = nothing)
    names = keys(stage.accesses)
    access_values = Base.values(stage.accesses)
    dependency_values = dependencies === nothing ?
        ntuple(_ -> nothing, length(access_values)) :
        Base.values(dependencies.accesses)
    reads = Any[ntuple(index -> _read_inspection(
            names[index], access_values[index], dependency_values[index]),
        length(access_values))...]
    for publication in stage.publications
        publication.law isa OrderedFold || continue
        state_dependencies = dependencies === nothing ? nothing :
            dependencies.state
        state_names = keys(publication.law.state.components)
        for (index, component) in enumerate(
                values(publication.law.state.components))
            field = component.source isa _FoldInPlace ?
                component.target : component.source
            dependency = state_dependencies === nothing ? nothing : begin
                pair = getfield(state_dependencies, index)
                component.source isa _FoldInPlace ? pair.target : pair.source
            end
            push!(reads, (
                role = Symbol(:fold_state_, state_names[index]),
                kind = :fold_state,
                identity = semantic_identity(field),
                value_type = eltype(field),
                space = semantic_identity(field.space),
                relation = nothing,
                version = :stage_entry,
                ghost = nothing,
                producer = _dependency_inspection(dependency),
            ))
        end
    end
    return Tuple(reads)
end

function _stage_relation_uses(stage::Stage)
    uses = Any[]
    for access in values(stage.accesses)
        access isa Access && push!(uses, (
            relation = semantic_identity(access.relation), direction = :read))
    end
    for publication in stage.publications, component in publication.components
        component isa FieldPublication && push!(uses, (
            relation = semantic_identity(component.relation),
            direction = :publication))
    end
    stage.control.subset isa _SubsetSelection && push!(uses, (
        relation = semantic_identity(stage.control.subset.relation),
        direction = :control))
    return Tuple(unique(uses))
end

function _semantic_stage_inspection(stage::Stage, index::Int;
        dependencies = nothing, planning = nothing)
    return (
        index,
        source = _space_inspection(stage.source),
        origin = stage.origin,
        reads = _stage_reads_inspection(stage, dependencies),
        control = _control_inspection(stage.control, dependencies),
        publications = map(_stage_publication_context, stage.publications),
        planning,
    )
end

function _semantic_equivalence(law::LocalLaw)
    _, relations, _ = _law_descriptor_requirements(law)
    stages = Tuple(map(enumerate(law.stages)) do (index, stage)
        report = _semantic_stage_inspection(stage, index)
        publications = map(report.publications) do publication
            merge(publication, (origin = nothing,))
        end
        return merge(report,
            (origin = nothing, publications, planning = nothing))
    end)
    return (
        parameters = map(_parameter_inspection,
            law.parameters.declarations),
        relations = map(relation -> _relation_inspection(relation, nothing),
            relations),
        stages,
        evaluators = map(stage -> (
                value = stage.evaluator.evaluator,
                type = typeof(stage.evaluator.evaluator),
                parameters = map(_parameter_inspection,
                    stage.evaluator.parameters),
            ), law.stages),
    )
end

function _inspect_local_law(law::LocalLaw)
    _, relations, _ = _law_descriptor_requirements(law)
    return (
        lifecycle = :LocalLaw,
        parameters = map(_parameter_inspection,
            law.parameters.declarations),
        relations = map(relation -> _relation_inspection(relation, nothing),
            relations),
        stages = Tuple(map(enumerate(law.stages)) do (index, stage)
            _semantic_stage_inspection(stage, index)
        end),
        planning = nothing,
        equivalence = _semantic_equivalence(law),
    )
end

function _planned_relation_phases(entry::_StageLoweringEntry;
        reset_fused::Bool = false)
    isempty(entry.relation_dependencies) && return ()
    validators = count(dependency ->
        !(dependency.validator isa _NoRelationContentValidator),
        entry.relation_dependencies)
    launches_per_validator = reset_fused ? 2 : 3
    validation = validators == 0 ? () :
        (_phase_fact(:relationship_validation,
            launches_per_validator * validators),)
    return (validation..., _phase_fact(:relationship_receipt))
end

_planned_stage_phases(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_DirectIdentityUniqueLayout}}) where {A,W} =
    (_phase_fact(:direct_identity_unique),)
function _planned_stage_phases(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_GroupedCandidateLayout}}) where {A,W}
    phases = Any[_phase_fact(:candidate_reset)]
    append!(phases, _planned_relation_phases(entry; reset_fused = true))
    push!(phases, _phase_fact(:candidate_evaluate))
    for shape in entry.workspace.ports
        if hasproperty(shape, :atomic_selection)
            push!(phases, _phase_fact(:resolve_atomic_winner))
            continue
        end
        hasproperty(shape, :grouping_shape) || continue
        push!(phases, _phase_fact(:destination_grouping_local_sort))
        shape.grouping_shape.merge_passes == 0 || push!(phases,
            _phase_fact(:destination_grouping_merge,
                shape.grouping_shape.merge_passes))
        push!(phases, _phase_fact(:destination_grouping_directory))
    end
    push!(phases, _phase_fact(:candidate_validate))
    publications = entry.admission.stage.publications
    _candidate_phase_required(publications,
        _candidate_atomic_initialization_required) && push!(phases,
            _phase_fact(:candidate_atomic_initialize))
    _candidate_phase_required(publications,
        _candidate_atomic_required) && push!(phases,
            _phase_fact(:candidate_atomic))
    push!(phases, _phase_fact(:candidate_finalize_publish))
    return Tuple(phases)
end
function _planned_stage_phases(entry::_StageLoweringEntry{
        A,W,<:_CollectStageExecutor}) where {A,W}
    phases = Any[_phase_fact(:collect_reset)]
    append!(phases, _planned_relation_phases(entry))
    push!(phases, _phase_fact(:collect_evaluate))
    for port in entry.workspace.ports
        items = div(Int(port.candidate_count), _collect_width(port))
        levels = _compacted_scan_level_count(items)
        push!(phases, _phase_fact(:collect_scan_block, levels))
        levels == 1 || push!(phases,
            _phase_fact(:collect_scan_add, levels - 1))
    end
    for port in entry.workspace.ports
        push!(phases, _phase_fact(:collect_scatter))
        port.sort_required || continue
        push!(phases, _phase_fact(:collect_local_bitonic))
        port.merge_passes == 0 || push!(phases,
            _phase_fact(:collect_merge, port.merge_passes))
        _is_grouped(port.groups) && push!(phases,
            _phase_fact(:collect_directory))
        _is_canonical_order(port.order) && push!(phases,
            _phase_fact(:collect_validate_order))
    end
    append!(phases, (_phase_fact(:collect_finalize),
        _phase_fact(:collect_publish,
            cld(length(entry.admission.stage.publications),
                _POINTWISE_SEGMENT_LIMIT))))
    return Tuple(phases)
end
function _planned_stage_phases(entry::_StageLoweringEntry{
        A,W,<:_KeyedReduceStageExecutor}) where {A,W}
    plan = entry.workspace.plan
    levels = _compacted_scan_level_count(Int(plan.bounds.candidate_count))
    phases = Any[_phase_fact(:keyed_reduce_reset)]
    append!(phases, _planned_relation_phases(entry))
    append!(phases, (
        _phase_fact(:keyed_reduce_evaluate),
        _phase_fact(:keyed_reduce_scan_block, levels),
    ))
    levels == 1 || push!(phases,
        _phase_fact(:keyed_reduce_scan_add, levels - 1))
    append!(phases, (
        _phase_fact(:keyed_reduce_scatter),
        _phase_fact(:keyed_reduce_local_bitonic),
    ))
    plan.bounds.merge_passes == 0 || push!(phases,
        _phase_fact(:keyed_reduce_merge, plan.bounds.merge_passes))
    push!(phases, _phase_fact(:keyed_reduce_segment))
    push!(phases, _phase_fact(:keyed_reduce_segment_prefix_scan_block, levels))
    levels == 1 || push!(phases,
        _phase_fact(:keyed_reduce_segment_prefix_scan_add, levels - 1))
    append!(phases, (
        _phase_fact(:keyed_reduce_unique_count),
        _phase_fact(:keyed_reduce_clear_retention),
        _phase_fact(:keyed_reduce_fold),
    ))
    push!(phases, _phase_fact(:keyed_reduce_retention_prefix_scan_block, levels))
    levels == 1 || push!(phases,
        _phase_fact(:keyed_reduce_retention_prefix_scan_add, levels - 1))
    append!(phases, (_phase_fact(:keyed_reduce_final_count),
        _phase_fact(:keyed_reduce_finalize), _phase_fact(:keyed_reduce_publish)))
    return Tuple(phases)
end
function _planned_stage_phases(entry::_StageLoweringEntry{
        A,W,<:_OrderedFoldStageExecutor}) where {A,W}
    phases = Any[_phase_fact(:ordered_fold_reset)]
    append!(phases, _planned_relation_phases(entry))
    push!(phases, _phase_fact(:ordered_fold_evaluate))
    order = only(entry.admission.stage.publications).law.order
    if !(order isa _SourceOrder)
        extent = nextpow(2, max(Int(entry.admission.stage.source_count), 1))
        bitonic = 0
        width = 2
        while width <= extent
            distance = width >>> 1
            while distance >= 1
                bitonic += 1
                distance >>>= 1
            end
            width <<= 1
        end
        bitonic == 0 || push!(phases,
            _phase_fact(:ordered_fold_bitonic, bitonic))
    end
    append!(phases, (_phase_fact(:ordered_fold_validate_initialize),
        _phase_fact(:ordered_fold_apply),
        _phase_fact(:ordered_fold_finalize)))
    return Tuple(phases)
end

_phase_count(phases) = sum(phase.count for phase in phases; init = 0)

_stage_layout_name(::_CandidateStageExecutor{<:_GroupedCandidateLayout}) =
    :grouped_candidate
_stage_layout_name(::_CandidateStageExecutor{<:_DirectIdentityUniqueLayout}) =
    :direct_identity_unique
_stage_layout_name(::_CollectStageExecutor) = :compacted_sequence
_stage_layout_name(::_KeyedReduceStageExecutor) = :sparse_keyed_sequence
_stage_layout_name(::_OrderedFoldStageExecutor) = :ordered_recurrence

function _segment_materializations(law::LocalLaw, indices)
    return Tuple(semantic_identity(component.field)
        for index in indices
        for publication in law.stages[index].publications
        for component in publication.components
        if component isa FieldPublication)
end

function _physical_segment_inspection(
        launch::_PointwiseSegmentEntry, law::LocalLaw)
    indices = map(member -> member.logical_index, launch.members)
    source = law.stages[first(indices)].source
    return (
        logical_stages = indices,
        family = :direct_pointwise,
        launch_count = 1,
        traversal = semantic_identity(source),
        retained_materializations = launch.retained_materializations,
        forwarded_values = launch.forwarded_values,
        boundary_reason = launch.boundary_reason,
    )
end

function _physical_segment_inspection(
        entry::_StageLoweringEntry, law::LocalLaw)
    index = entry.logical_index
    phases = _planned_stage_phases(entry)
    return (
        logical_stages = (index,),
        family = _stage_layout_name(entry.executor),
        launch_count = _phase_count(phases),
        traversal = semantic_identity(law.stages[index].source),
        retained_materializations = _segment_materializations(law, (index,)),
        forwarded_values = (),
        boundary_reason = :semantic_barrier,
    )
end

function _stage_planning_inspection(entry::_StageLoweringEntry,
        stage::Stage, phases)
    executor = _stage_executor_name(entry.executor)
    layout = _stage_layout_name(entry.executor)
    parameter_slots = entry.admission.stage.parameter_slots
    prefix_slot = _stage_control_parameter_slot(
        entry.admission.stage.control.prefix)
    gate_slot = _stage_control_parameter_slot(
        entry.admission.stage.control.gate)
    projection = (
        evaluator = map(slot -> typeof(slot).parameters[1], parameter_slots),
        prefix = prefix_slot === nothing ? nothing :
            typeof(prefix_slot).parameters[1],
        gate = gate_slot === nothing ? nothing :
            typeof(gate_slot).parameters[1],
    )
    specialization = (
        executor = typeof(entry.executor),
        evaluator_signature = entry.admission.signature,
        result_type = entry.admission.result_type,
        publication_types = map(typeof,
            entry.admission.stage.publications),
        parameter_projection = projection,
    )
    return (
        executor,
        layout,
        evaluator_signature = entry.admission.signature,
        evaluator_result_type = entry.admission.result_type,
        specialization_signature = specialization,
        relationship_receipts = map(entry.context.dynamic_relations,
                entry.relation_dependencies) do identity, dependency
            (relation = identity,
                content_validation = !(
                    dependency.validator isa _NoRelationContentValidator))
        end,
        relation_uses = _stage_relation_uses(stage),
        workspace_paths = (map(leaf -> leaf.path,
                entry.workspace.leaves)...,
            map(leaf -> leaf.path, entry.relation_receipts.leaves)...),
        phases,
    )
end

function _plan_inspection(plan::Plan, lifecycle::Symbol;
        prepared = nothing)
    law = plan.bound.law
    _, relations, _ = _law_descriptor_requirements(law)
    binding = plan.bound.binding
    proofs = map(relations) do relation
        identity = semantic_identity(relation)
        for index in eachindex(binding.relations)
            candidate = binding.relations[index].relation
            semantic_identity(candidate) == identity || continue
            candidate == relation || throw(LocalMathValidationError(
                "inspection found a relation identity with conflicting schema";
                stage = :inspect, contract = :relation_schema_identity,
                expected = relation, actual = candidate))
            return binding.proofs[index]
        end
        throw(LocalMathValidationError(
            "inspection could not find the validated relation proof";
            stage = :inspect, contract = :relation_proof,
            expected = identity, actual = :missing))
    end
    stages = Any[]
    phase_values = Any[]
    logical_entries = _logical_lowering_entries(plan.lowering)
    for (index, entry) in enumerate(logical_entries)
        semantic = law.stages[index]
        phases = _planned_stage_phases(entry)
        push!(phase_values, phases)
        stage_planning = _stage_planning_inspection(entry, semantic, phases)
        dependencies = _stage_planning_entry(
            plan.bound, index).dependencies
        push!(stages, _semantic_stage_inspection(semantic, index;
            dependencies,
            planning = stage_planning))
    end
    workspace = prepared === nothing ?
        _workspace_requirement_facts(plan.lowering) :
        _workspace_requirement_facts(plan.lowering,
            length(prepared.leases))
    physical_segments = map(plan.lowering.launches) do launch
        _physical_segment_inspection(launch, law)
    end
    stage_local = sum(segment -> segment.launch_count,
        physical_segments; init = 0)
    program_phases = _program_phases(plan.lowering)
    program_reset_count = _phase_count(program_phases)
    planning = (
        backend_environment = _backend_environment(plan.backend),
        compiler = _lowering_identity(plan.lowering),
        workspace,
        workspace_bytes = sum(fact.bytes for fact in workspace; init = 0),
        program_phases,
        stage_phases = Tuple(phase_values),
        physical_segments = Tuple(physical_segments),
        stage_local_launch_count = stage_local,
        program_reset_count,
        base_provider_launch_count = stage_local + program_reset_count,
    )
    return (
        lifecycle,
        parameters = map(_parameter_inspection,
            law.parameters.declarations),
        relations = map(_relation_inspection, relations, proofs),
        stages = Tuple(stages),
        planning,
        equivalence = _semantic_equivalence(law),
    )
end

"""
    LocalMath.inspect(plan::Plan)

Return the semantic projection together with validated relation proofs,
producer dependencies, workspace requirements, specialization signatures, and
the currently planned physical phases. Physical planning fields describe the
current implementation and are not additional scientific semantics.
"""
inspect(plan::Plan{<:_BoundLaw}; level = nothing) =
    _inspection_projection(_plan_inspection(plan, :Plan), level)

_structural_leaf_inspection(fact::_StructuralLeafFact) = (
    name = fact.name,
    storage_type = fact.storage_type,
    logical = fact.logical,
    prepared = fact.prepared,
)

function _binding_realization(binding::_ValidatedStructuralBinding)
    fields = map(binding.fields, binding.field_facts) do value, facts
        (identity = semantic_identity(value.field),
            binding_identity = value.binding_id,
            ownership = _ownership_inspection(value.ownership),
            leaves = map(_structural_leaf_inspection, facts))
    end
    relations = map(binding.relations, binding.proofs) do value, proof
        (identity = semantic_identity(value.relation),
            binding_identity = value.binding_id,
            ownership = _ownership_inspection(value.ownership),
            dynamic_generation = value.generation !== nothing,
            dynamic_status = value.status !== nothing,
            leaves = map(_structural_leaf_inspection,
                proof.binding_schema.physical_leaves))
    end
    collections = map(binding.collections,
            binding.collection_facts) do value, facts
        (identity = semantic_identity(value.collection),
            binding_identity = value.binding_id,
            leaves = map(_structural_leaf_inspection, facts))
    end
    return (; fields, relations, collections)
end

"""
    LocalMath.inspect(prepared::PreparedPlan)

Return the plan projection plus concrete storage, callable admission, provider,
workspace, submission-layout, and mutable receipt-counter observations. The
operation is cold and does not submit or synchronize work.
"""
function inspect(prepared::PreparedPlan; level = nothing)
    report = _plan_inspection(prepared.plan, :PreparedPlan; prepared)
    callbacks = map(prepared.plan.lowering.callable_admissions) do entry
        (purpose = entry.purpose, signature = entry.signature,
            return_type = entry.return_type,
            admission = entry.admission,
            method = entry.method)
    end
    realized = (
        prepared_launch_types = Tuple(map(launch -> typeof(launch.stage),
            prepared.runtime.launches)),
        callback_methods = callbacks,
        provider = _lane_provider(prepared.lane),
        device = _lane_device(prepared.lane),
        bindings = _binding_realization(prepared.plan.bound.binding),
        parameter_layout = _stage_parameter_layout_inspection(
            prepared.submission_schema),
        dependency_arity = prepared.dependency_arity,
        lease_capacity = length(prepared.leases),
        workspace_ownership = prepared.workspace_ownership,
        state = (
            submitted = prepared.submitted,
            drained = prepared.drained,
            outstanding = prepared.outstanding,
            poisoned = prepared.poisoned,
            provider_completions = _lane_completion_count(prepared.lane),
            provider_scope_completions =
                _lane_scope_completion_count(prepared.lane),
            validation_transfers = _lane_transfer_count(prepared.lane),
        ),
    )
    return _inspection_projection(merge(report, (; realized)), level)
end

function _distinct_specialization_count(stages)
    signatures = map(stage -> stage.planning.specialization_signature, stages)
    return length(unique(signatures))
end

_callable_admission_inspection(entry::_CallableAdmissionFact) = (
    purpose = entry.purpose,
    callable_type = typeof(entry.callback),
    selected_method = entry.method,
    analyzed_signature = entry.signature,
    inferred_return_type = entry.return_type,
    admission_contract = entry.admission,
)

"""
    LocalMath.compilation_report(plan::Plan)

Return cold structural compiler facts: specialization families, callable
signatures, physical phases, relationship validation, and workspace shape.
The report contains no predicted wall time and is never consumed by planning.
"""
function compilation_report(plan::Plan{<:_BoundLaw})
    report = _plan_inspection(plan, :Plan)
    return (
        lifecycle = :PlanCompilationReport,
        compiler = report.planning.compiler,
        stage_count = length(report.stages),
        specialization_family_count = _distinct_specialization_count(
            report.stages),
        specialization_signatures = map(
            stage -> stage.planning.specialization_signature, report.stages),
        callable_signatures = map(
            stage -> stage.planning.evaluator_signature, report.stages),
        callable_admissions = map(_callable_admission_inspection,
            plan.lowering.callable_admissions),
        relationship_receipts = map(
            stage -> stage.planning.relationship_receipts, report.stages),
        stage_phases = report.planning.stage_phases,
        provider_launch_count = report.planning.base_provider_launch_count,
        workspace = report.planning.workspace,
        workspace_bytes = report.planning.workspace_bytes,
    )
end

"""
    LocalMath.compilation_report(prepared::PreparedPlan)

Return the plan report together with realized launch types, selected callback
methods, parameter layout, dependency arity, and provider facts. This operation
does not submit work or synchronize the provider.
"""
function compilation_report(prepared::PreparedPlan)
    planned = compilation_report(prepared.plan)
    report = inspect(prepared)
    return merge(planned, (
        lifecycle = :PreparedCompilationReport,
        prepared_launch_types = report.realized.prepared_launch_types,
        callback_methods = report.realized.callback_methods,
        parameter_layout = report.realized.parameter_layout,
        dependency_arity = report.realized.dependency_arity,
        provider = report.realized.provider,
        device = report.realized.device,
    ))
end

"""`execution_contract(prepared)` reports provider-scope receipt behavior without submitting work."""
function execution_contract(prepared::PreparedPlan)
    lane = prepared.lane
    return (
        provider = _lane_provider(lane),
        receipt_scope = _lane_wait_scope(lane),
        receipt_cumulative = _lane_cumulative(lane),
        receipt_selective = _lane_selective(lane),
        observed_provider_completions = _lane_completion_count(lane),
        observed_scope_completions = _lane_scope_completion_count(lane),
        observed_validation_transfers = _lane_transfer_count(lane),
    )
end
