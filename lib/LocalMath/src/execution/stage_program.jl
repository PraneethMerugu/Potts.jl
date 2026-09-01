# The sole execution lifecycle for the Stage tuple. This unit owns no
# alternate scheduler: `execute!` enters it through `_execute_lowering!`, and all
# physical work remains ordered KernelAbstractions launches on the provider
# tail.

struct _GroupedCandidateLayout end
struct _DirectIdentityUniqueLayout end
struct _CandidateStageExecutor{L}
    layout::L
end
struct _CollectStageExecutor end
struct _OrderedFoldStageExecutor end

struct _StageEntryContext
    origin::SourceOrigin
    publications::Tuple
    dynamic_relations::Tuple
    executor::Symbol
end

abstract type _AbstractStageLoweringEntry end

struct _StageLoweringEntry{A,W,X,D,R} <: _AbstractStageLoweringEntry
    admission::A
    workspace::W
    executor::X
    context::_StageEntryContext
    relation_dependencies::D
    relation_receipts::R
    logical_index::Int
end


const _POINTWISE_SEGMENT_LIMIT = 4

"""One bounded physical launch containing ordinary direct pointwise entries."""
struct _PointwiseSegmentEntry{M,F,P,R} <: _AbstractStageLoweringEntry
    members::M
    forwarded_values::F
    materializations::P
    retained_materializations::R
    boundary_reason::Symbol
end

struct _StageLoweringInput{S,T,D,I,R}
    semantic::S
    draft::T
    relation_dependencies::D
    dynamic_relation_ids::I
    relation_receipts::R
    index::Int
end

struct _StageProgramLowering
    launches::Vector{_AbstractStageLoweringEntry}
    workspace
    callable_admissions::Vector{_CallableAdmissionFact}
end

abstract type _AbstractPreparedStageLaunch end

struct _PreparedStageLaunch{S,T,G} <: _AbstractPreparedStageLaunch
    stage::S
    status::T
    guard::G
end

struct _PreparedStageProgram{E}
    launches::Vector{_AbstractPreparedStageLaunch}
    execution_gate::E
end


_physical_launch_members(entry::_StageLoweringEntry) = (entry,)
_physical_launch_members(entry::_PointwiseSegmentEntry) = entry.members

function _logical_lowering_entries(lowering::_StageProgramLowering)
    return Tuple(member for launch in lowering.launches
        for member in _physical_launch_members(launch))
end

_candidate_stage_executor(::Tuple{}) =
    _CandidateStageExecutor(_GroupedCandidateLayout())
_collect_stage_executor(::Tuple{}) = _CollectStageExecutor()
function _stage_executor(publications::Tuple{
        <: _PreparedStagePublication{C,L},Vararg,
    }) where {C,L<:Union{Unique,Reduce,Resolve}}
    return _candidate_stage_executor(publications)
end
function _candidate_stage_executor(publications::Tuple{
        <: _PreparedStagePublication{C,L},Vararg,
    }) where {C,L<:Union{Unique,Reduce,Resolve}}
    return _candidate_stage_executor(Base.tail(publications))
end
function _stage_executor(publications::Tuple{
        <: _PreparedStagePublication{C,L},Vararg,
    }) where {C,L<:_PreparedCollectLaw}
    return _collect_stage_executor(publications)
end
function _collect_stage_executor(publications::Tuple{
        <: _PreparedStagePublication{C,L},Vararg,
    }) where {C,L<:_PreparedCollectLaw}
    return _collect_stage_executor(Base.tail(publications))
end
_stage_executor(::Tuple{<:_PreparedStagePublication{C,L}}) where {
    C,L<:_PreparedOrderedFoldLaw} = _OrderedFoldStageExecutor()

_stage_executor_name(::_CandidateStageExecutor) = :candidate
_stage_executor_name(::_CollectStageExecutor) = :collect
_stage_executor_name(::_OrderedFoldStageExecutor) = :ordered_fold

_direct_identity_unique_lane(::Type, ::Unique) = false
_direct_identity_unique_lane(
    ::Type{UniqueValue{T}}, ::Unique{T,1},
) where {T} = true
_direct_identity_unique_lane(
    ::Type{ConditionalUniqueValue{T}},
    law::Unique{T,1,<:PartialCoverage},
) where {T} = law.onempty isa Union{PreserveEmpty,FillEmpty}

function _direct_identity_unique_result(result_type::Type, publications::Tuple)
    result_type <: NamedTuple || return false
    lanes = fieldtypes(result_type)
    length(lanes) == length(publications) || return false
    return all(eachindex(lanes)) do index
        _direct_identity_unique_lane(
            lanes[index], publications[index].law)
    end
end

_direct_relation_keys_infallible(use::_PreparedRelationUse) =
    _direct_relation_keys_infallible(use.view)
_direct_relation_keys_infallible(view::_FieldIndexRelationView) = view.optional
_direct_relation_keys_infallible(view::_ProductRelationView) =
    all(_direct_relation_keys_infallible, view.factors)
_direct_relation_keys_infallible(view::_ComposedRelationView) =
    all(_direct_relation_keys_infallible, view.factors)
_direct_relation_keys_infallible(view::_SourceMaskRelationView) =
    _direct_relation_keys_infallible(view.base)
_direct_relation_keys_infallible(view::_SelectedRelationView) =
    _direct_relation_keys_infallible(view.injection) &&
    _direct_relation_keys_infallible(view.base)
_direct_relation_keys_infallible(view) = true

_direct_relation_total(use::_PreparedRelationUse) =
    _direct_relation_total(use.view)
_direct_relation_total(::_IdentityRelationView) = true
_direct_relation_total(::_IndexRelationView) = true
_direct_relation_total(view::_FixedDegreeRelationView) =
    view.counts === nothing
_direct_relation_total(view::_ProductRelationView) =
    all(_direct_relation_total, view.factors)
_direct_relation_total(view::_ComposedRelationView) =
    all(_direct_relation_total, view.factors)
_direct_relation_total(view::_SelectedRelationView) =
    _direct_relation_total(view.injection) && _direct_relation_total(view.base)
_direct_relation_total(view) = false

function _direct_affine_axis_total(view::_AffineRelationView, axis::Int)
    boundary = view.boundary
    boundary isa _PeriodicRelationBoundary && boundary.axes[axis] &&
        return view.codomain_extent[axis] > 0
    return all(view.offsets) do offset
        Int64(1) + Int64(offset[axis]) >= 1 &&
        Int64(view.domain_extent[axis]) + Int64(offset[axis]) <=
            Int64(view.codomain_extent[axis])
    end
end
_direct_relation_total(view::_AffineRelationView) =
    !(view.boundary isa Union{
        _MaskedRelationBoundary,_ExteriorRelationBoundary,
        _GhostRelationBoundary,
    }) && all(axis -> _direct_affine_axis_total(view, axis),
        eachindex(view.domain_extent))

function _direct_stage_accesses_infallible(
        semantic_accesses::NamedTuple, prepared_accesses::Tuple)
    length(semantic_accesses) == length(prepared_accesses) || return false
    return all(zip(values(semantic_accesses), prepared_accesses)) do pair
        semantic, prepared = pair
        semantic isa Access || return false
        prepared isa _PreparedStageAccess || return false
        _direct_relation_keys_infallible(prepared.relation) || return false
        semantic.mode isa _SampleAccess ||
            _direct_relation_total(prepared.relation)
    end
end

function _direct_stage_aliases_are_pointwise(stage::Stage)
    destinations = Tuple(component.field
        for publication in stage.publications
        for component in publication.components)
    return all(values(stage.accesses)) do access
        access isa Access || return false
        any(field -> semantic_identity(field) == semantic_identity(access.field),
            destinations) || return true
        access.relation.representation isa _IdentityRelation
    end
end

_direct_control_can_skip(control::_PreparedStageControl) =
    !(control.prefix isa _PreparedNoPrefix &&
      control.mask isa _PreparedNoMask &&
      control.subset isa _PreparedNoSubset &&
      control.gate isa _PreparedNoGate)

function _direct_identity_publications(publications::Tuple)
    return all(publications) do publication
        law = publication.law
        law isa Unique || return false
        length(publication.components) == 1 || return false
        only(publication.components).relation.view isa Union{
            _IdentityRelationView,_IndexRelationView}
    end
end

function _candidate_physical_layout(
        input::_StageLoweringInput, admission::_StageAdmission)
    isempty(input.relation_dependencies) || return _GroupedCandidateLayout()
    stage = admission.stage
    _direct_identity_publications(stage.publications) ||
        return _GroupedCandidateLayout()
    if _direct_control_can_skip(stage.control)
        all(publication -> publication.law.coverage isa PartialCoverage,
            stage.publications) || return _GroupedCandidateLayout()
    end
    _contains_bounded_fold_type(typeof(stage.evaluator)) &&
        return _GroupedCandidateLayout()
    _direct_stage_accesses_infallible(
        input.semantic.accesses, stage.accesses) ||
        return _GroupedCandidateLayout()
    _direct_stage_aliases_are_pointwise(input.semantic) ||
        return _GroupedCandidateLayout()
    _direct_identity_unique_result(
        admission.result_type, stage.publications) ||
        return _GroupedCandidateLayout()
    return _DirectIdentityUniqueLayout()
end

_physical_stage_executor(executor, input, admission) = executor
_physical_stage_executor(::_CandidateStageExecutor, input, admission) =
    _CandidateStageExecutor(_candidate_physical_layout(input, admission))

function _stage_workspace_spec(
        ::_CandidateStageExecutor{<:_GroupedCandidateLayout},
        admission::_StageAdmission, index::Int,
    )
    return _candidate_stage_workspace_spec(admission.stage;
        path = (:stages, index), name_prefix = Symbol(:stage_, index))
end
_stage_workspace_spec(
    ::_CandidateStageExecutor{<:_DirectIdentityUniqueLayout},
    ::_StageAdmission, ::Int) = _WorkspaceAuthority((), ())
function _stage_workspace_spec(
        ::_CollectStageExecutor, admission::_StageAdmission, index::Int,
    )
    return _collect_stage_workspace_spec(admission.stage;
        path = (:stages, index), name_prefix = Symbol(:stage_, index))
end
function _stage_workspace_spec(
        ::_OrderedFoldStageExecutor, admission::_StageAdmission, index::Int,
    )
    return _ordered_fold_stage_workspace_spec(admission.stage;
        path = (:stages, index), name_prefix = Symbol(:stage_, index))
end

_publication_component_inspection(component::FieldPublication) = (
    kind = :field,
    field = semantic_identity(component.field),
    field_space = semantic_identity(component.field.space),
    relation = semantic_identity(component.relation),
    relation_domain = semantic_identity(domain(component.relation)),
    relation_codomain = semantic_identity(codomain(component.relation)),
    port = _evaluator_value_name(component.role),
)
_publication_component_inspection(component::CollectionPublication) = (
    kind = :collection,
    collection = semantic_identity(component.collection),
    element_type = eltype(component.collection),
    capacity = component.collection.capacity,
    port = _evaluator_value_name(component.role),
)
_publication_component_inspection(component::FoldPublication) = (
    kind = :fold_value,
    port = _evaluator_value_name(component.role),
)

_fold_state_source_inspection(::_FoldInPlace) = (kind = :in_place,)
_fold_state_source_inspection(source::Field) =
    (kind = :field, field = semantic_identity(source))
_fold_state_component_inspection(component::FoldComponent) = (
    target = semantic_identity(component.target),
    target_space = semantic_identity(component.target.space),
    value_type = eltype(component.target),
    source = _fold_state_source_inspection(component.source),
)

_publication_law_inspection(law::Unique{T}) where {T} = (
    kind = :unique, value_type = T, maximum = _publication_width(law),
    coverage = law.coverage, conflicts = :reject_multiple,
    onempty = law.onempty,
)
_publication_law_inspection(law::Reduce{T}) where {T} = (
    kind = :reduce, value_type = T, maximum = _publication_width(law),
    operation = law.operation, seed = law.seed, order = law.order,
    conflicts = :fold,
)
_publication_law_inspection(law::Resolve{R,I,T}) where {R,I,T} = (
    kind = :resolve, rank_type = R, tie_type = I, value_type = T,
    maximum = _publication_width(law), direction = law.direction,
    tie = law.tie, lower = law.lower, upper = law.upper,
    conflicts = :resolve, onempty = law.onempty,
)
_publication_law_inspection(law::Collect{T}) where {T} = (
    kind = :collect, value_type = T, maximum = _publication_width(law),
    groups = law.groups, order = law.order, projection = law.projection,
    conflicts = :collect, overflow = law.overflow, onempty = law.onempty,
)
_publication_law_inspection(law::OrderedFold{T}) where {T} = (
    kind = :ordered_fold, value_type = T,
    state = map(_fold_state_component_inspection, law.state.components),
    transition = law.transition, order = law.order,
    conflicts = :ordered_recurrence, onempty = :identity_state,
)

function _stage_publication_context(publication::Publication)
    ports = map(component -> _evaluator_value_name(component.role),
        publication.components)
    components = map(_publication_component_inspection,
        publication.components)
    law = _publication_law_inspection(publication.law)
    details = publication.law isa OrderedFold ? (;
        components, law,
        fold_components = keys(publication.law.state.components),
    ) : (; components, law)
    return (law = typeof(publication.law), ports,
        origin = publication.origin, details)
end

function _stage_lowering_entry(input::_StageLoweringInput,
        admission::_StageAdmission)
    semantic, index = input.semantic, input.index
    executor = _physical_stage_executor(
        _stage_executor(admission.stage.publications), input, admission)
    workspace = _stage_workspace_spec(executor, admission, index)
    context = _StageEntryContext(semantic.origin,
        map(_stage_publication_context, semantic.publications),
        input.dynamic_relation_ids,
        _stage_executor_name(executor))
    return _StageLoweringEntry(admission, workspace, executor, context,
        input.relation_dependencies, input.relation_receipts, input.index)
end

function _stage_program_workspace(launches::Vector{_AbstractStageLoweringEntry})
    gate = _workspace_leaf(:stage_execution_gate, (:execution_gate,),
    UInt32, (_VALIDATION_STATUS_FIELDS, 1);
        role = :validation_status)
    leaves, scopes = Any[], Any[]
    logical_count = sum(length(_physical_launch_members(launch))
        for launch in launches; init = 0)
    stage_templates = Vector{Any}(undef, logical_count)
    receipt_templates = Vector{Any}(undef, logical_count)
    for launch in launches
        for entry in _physical_launch_members(launch)
            index = entry.logical_index
            append!(leaves, entry.workspace.leaves)
            append!(scopes,
                ntuple(_ -> index, length(entry.workspace.leaves)))
            append!(leaves, entry.relation_receipts.leaves)
            append!(scopes, ntuple(
                _ -> :persistent, length(entry.relation_receipts.leaves)))
            stage_templates[index] = entry.workspace.template
            receipt_templates[index] = entry.relation_receipts.template
        end
    end
    push!(leaves, gate)
    push!(scopes, :persistent)
    template = (
        stages = stage_templates,
        relation_receipts = receipt_templates,
        execution_gate = _WorkspaceLeafSlot(:stage_execution_gate),
    )
    return _WorkspaceAuthority(Tuple(leaves), template, Tuple(scopes))
end


_direct_pointwise_entry(entry::_StageLoweringEntry) =
    entry.executor isa _CandidateStageExecutor{<:_DirectIdentityUniqueLayout}

const _POINTWISE_SEGMENT_PORT_LIMIT = 4

_pointwise_port_count(entry::_StageLoweringEntry) =
    length(entry.admission.stage.publications)

function _pointwise_prefix_infallible(input::_StageLoweringInput,
        entry::_StageLoweringEntry)
    prefix = input.semantic.control.prefix
    prefix isa _NoPrefix && return true
    prefix isa _ParameterPrefix || return false
    bounds = prefix.parameter.bounds
    return bounds isa _ClosedParameterBounds &&
        bounds.lower >= 0 && bounds.upper <= entry.admission.stage.source_count
end

function _pointwise_semantic_destinations(stage::Stage)
    return Tuple(component.field for publication in stage.publications
        for component in publication.components)
end

function _pointwise_cross_dependencies_safe(left::Stage, right::Stage)
    destinations = _pointwise_semantic_destinations(left)
    right_destinations = _pointwise_semantic_destinations(right)
    for prior in destinations
        any(current -> semantic_identity(current) == semantic_identity(prior),
            right_destinations) && return false
        for access in values(right.accesses)
            access isa Access || continue
            semantic_identity(access.field) == semantic_identity(prior) ||
                continue
            access.relation.representation isa _IdentityRelation ||
                return false
        end
        control = right.control
        control.gate isa _FieldGate &&
            semantic_identity(control.gate.field) == semantic_identity(prior) &&
            return false
        control.prefix isa _FieldPrefix &&
            semantic_identity(control.prefix.field) == semantic_identity(prior) &&
            return false
    end
    return true
end

function _pointwise_destination_arrays(entry::_StageLoweringEntry)
    stage = entry.admission.stage
    return map(stage.publications) do publication
        component = only(publication.components)
        _prepared_stage_field(stage.fields,
            _relation_target_slot(component.relation.view))
    end
end

function _pointwise_destinations_nonaliasing(left::_StageLoweringEntry,
        right::_StageLoweringEntry)
    for left_array in _pointwise_destination_arrays(left)
        for right_array in _pointwise_destination_arrays(right)
            _arrays_mightalias(:pointwise_left, left_array,
                :pointwise_right, right_array) === nothing || return false
        end
    end
    return true
end

function _pointwise_entries_compatible(left_input::_StageLoweringInput,
        left::_StageLoweringEntry, right_input::_StageLoweringInput,
        right::_StageLoweringEntry)
    _direct_pointwise_entry(left) && _direct_pointwise_entry(right) ||
        return false, :physical_family
    _pointwise_prefix_infallible(left_input, left) &&
        _pointwise_prefix_infallible(right_input, right) ||
        return false, :runtime_prefix
    left_input.semantic.source == right_input.semantic.source &&
        left.admission.stage.source_count == right.admission.stage.source_count ||
        return false, :traversal
    _pointwise_cross_dependencies_safe(
        left_input.semantic, right_input.semantic) ||
        return false, :stage_visibility
    _pointwise_destinations_nonaliasing(left, right) ||
        return false, :physical_alias
    return true, :compatible
end

function _temporary_live_after(field::Field, stages)
    for stage in stages
        _field_used_at_stage_entry(stage, field) && return true
        for publication in stage.publications
            any(publication.components) do component
                component isa FieldPublication &&
                    _same_descriptor(component.field, field)
            end || continue
            _publication_initializes_field(stage, publication, field) &&
                return false
            return true
        end
    end
    return false
end

function _pointwise_segment_entries(inputs, entries, binding)
    temporary = Set(semantic_identity(value.field) for value in binding.fields
        if value.ownership isa _TemporaryOwnership)
    launches = _AbstractStageLoweringEntry[]
    index = 1
    while index <= length(entries)
        entry = entries[index]
        if !_direct_pointwise_entry(entry)
            push!(launches, entry)
            index += 1
            continue
        end
        members = (entry,)
        boundary = :end_of_program
        while index + length(members) <= length(entries)
            next_index = index + length(members)
            if length(members) == _POINTWISE_SEGMENT_LIMIT
                boundary = :segment_limit
                break
            end
            if sum(_pointwise_port_count, members; init = 0) +
                    _pointwise_port_count(entries[next_index]) >
                    _POINTWISE_SEGMENT_PORT_LIMIT
                boundary = :compile_complexity
                break
            end
            compatible, reason = _pointwise_entries_compatible(
                inputs[next_index - 1], last(members), inputs[next_index],
                entries[next_index])
            if !compatible
                boundary = reason
                break
            end
            members = (members..., entries[next_index])
        end
        produced = Set{Any}()
        forwarded = Any[]
        for logical_index in index:(index + length(members) - 1)
            stage = inputs[logical_index].semantic
            for access in values(stage.accesses)
                access isa Access || continue
                identity = semantic_identity(access.field)
                identity in produced && identity ∉ forwarded &&
                    push!(forwarded, identity)
            end
            control_fields = (
                stage.control.mask isa _MaskSelection ?
                    (stage.control.mask.field,) : (),
                stage.control.subset isa _SubsetSelection &&
                        stage.control.subset.relation.representation isa
                            _MaskedRelation ?
                    (stage.control.subset.relation.representation.mask,) : (),
            )
            for field in (control_fields[1]..., control_fields[2]...)
                identity = semantic_identity(field)
                identity in produced && identity ∉ forwarded &&
                    push!(forwarded, identity)
            end
            foreach(field -> push!(produced, semantic_identity(field)),
                _pointwise_semantic_destinations(stage))
        end
        retained = Any[]
        final_index = index + length(members) - 1
        later_stages = (inputs[value].semantic
            for value in (final_index + 1):length(inputs))
        later = Tuple(later_stages)
        materializations = ntuple(length(members)) do member_offset
            stage = inputs[index + member_offset - 1].semantic
            map(stage.publications) do publication
                component = only(publication.components)
                identity = semantic_identity(component.field)
                elide = identity in temporary &&
                    !_temporary_live_after(component.field, later)
                elide || push!(retained, identity)
                return elide ? _ForwardOnlyPointwise() :
                    _MaterializePointwise()
            end
        end
        push!(launches, _PointwiseSegmentEntry(
            members, Tuple(forwarded), materializations,
            Tuple(retained), boundary))
        index += length(members)
    end
    return launches
end

Base.@nospecializeinfer Base.@noinline function _stage_binding_slice(
        validated::_ValidatedStructuralBinding, stage::Stage)
    Base.@nospecialize validated stage
    cold = Base.inferencebarrier(validated)::_ValidatedStructuralBinding
    semantic = Base.inferencebarrier(stage)::Stage
    required_fields, required_relations, required_collections =
        _stage_descriptor_closure(semantic)
    field_values, field_fact_values = Any[], Any[]
    for field in required_fields
        index = Int(_resolve_field_slot(cold, field).index)
        push!(field_values, cold.fields[index])
        push!(field_fact_values, cold.field_facts[index])
    end
    relation_values, proof_values = Any[], Any[]
    for relation in required_relations
        index = Int(_resolve_relation_slot(cold, relation).index)
        push!(relation_values, cold.relations[index])
        push!(proof_values, cold.proofs[index])
    end
    collection_values, collection_fact_values = Any[], Any[]
    for collection in required_collections
        index = Int(_resolve_collection_slot(cold, collection).index)
        push!(collection_values, cold.collections[index])
        push!(collection_fact_values, cold.collection_facts[index])
    end
    fields, relations, collections =
        Tuple(field_values), Tuple(relation_values), Tuple(collection_values)
    structural = _StructuralBinding(fields, relations, collections)
    binding = _ValidatedStructuralBinding(
        _VALIDATED_BINDING_SEAL, structural,
        fields, relations, collections, Tuple(proof_values),
        Tuple(field_fact_values), Tuple(collection_fact_values),
        ntuple(_FieldSlot, length(fields)),
        ntuple(_RelationSlot, length(relations)),
        ntuple(_CollectionSlot, length(collections)),
    )
    return (; binding, relations = required_relations)
end

Base.@nospecializeinfer Base.@noinline function _stage_lowering_input(
        bound::_BoundLaw{<:LocalLaw,<:_ValidatedStructuralBinding},
        backend, index::Int, analysis_cache::Dict{Any,Any})
    Base.@nospecialize bound
    cold_bound = Base.inferencebarrier(bound)::_BoundLaw
    semantic = Base.inferencebarrier(cold_bound.law.stages[index])::Stage
    slice = Base.inferencebarrier(
        _stage_binding_slice(cold_bound.binding, semantic))
    local_bound = _BoundLaw(_BOUND_LAW_SEAL, cold_bound.law, slice.binding)
    planning = Base.inferencebarrier(
        _stage_planning_entry(local_bound, index))
    projection = Base.inferencebarrier(planning.projection)::_StageProjection
    draft = Base.inferencebarrier(_stage_draft_from_projection(
        slice.binding, semantic, projection; backend, analysis_cache))
    dependencies = Base.inferencebarrier(
        _stage_dynamic_relation_dependencies(slice.binding, semantic))
    dynamic_relation_ids = Any[]
    for relation in slice.relations
        slot = _resolve_relation_slot(slice.binding, relation)
        binding = _relation_binding(slice.binding, slot)
        (binding.generation !== nothing || binding.status !== nothing) &&
            push!(dynamic_relation_ids, semantic_identity(relation))
    end
    receipts = _stage_relation_receipt_workspace_spec(dependencies, index)
    return _StageLoweringInput(semantic, draft, dependencies,
        Tuple(dynamic_relation_ids), receipts, index)
end

Base.@noinline function _lower_stage_entry(
        input::I, backend::B,
        analysis_cache::Dict{Any,Any}) where {I<:_StageLoweringInput,B}
    admission = _admit_stage_evaluator(
        backend, input.semantic, input.draft, analysis_cache)
    return (_stage_lowering_entry(input, admission),
        _stage_callable_admissions(admission, analysis_cache))
end

Base.@nospecializeinfer Base.@noinline function _stage_program_lowering(
        bound::_BoundLaw{<:LocalLaw,<:_ValidatedStructuralBinding},
        backend::KernelAbstractions.Backend)
    Base.@nospecialize bound backend
    cold_bound = Base.inferencebarrier(bound)::_BoundLaw
    inputs = _StageLoweringInput[]
    entries = _AbstractStageLoweringEntry[]
    callable_admissions = _CallableAdmissionFact[]
    analysis_cache = Dict{Any,Any}()
    sizehint!(entries, length(cold_bound.law.stages))
    sizehint!(inputs, length(cold_bound.law.stages))
    for index in eachindex(cold_bound.law.stages)
        try
            input = Base.inferencebarrier(
                _stage_lowering_input(cold_bound, backend, index,
                    analysis_cache))::_StageLoweringInput
            entry, facts = _lower_stage_entry(input, backend, analysis_cache)
            push!(inputs, input)
            push!(entries, entry)
            append!(callable_admissions, facts)
        catch error
            annotated = _with_source_origin(error,
                cold_bound.law.stages[index].origin,
                :plan, :stage_lowering)
            annotated === error ? rethrow() : throw(annotated)
        end
    end
    launches = _pointwise_segment_entries(inputs, entries, cold_bound.binding)
    return _StageProgramLowering(launches,
        _stage_program_workspace(launches),
        callable_admissions)
end

function _materialize_temporary_field(binding::_FieldStorageBinding, backend)
    request = binding.storage
    request isa _TemporaryStorageRequest || return binding
    typeof(request.backend) === typeof(backend) && request.backend == backend ||
        throw(LocalMathValidationError(
            "Temporary must be planned on its declared backend";
            stage = :plan, contract = :temporary_backend,
            expected = request.backend, actual = backend))
    storage = _field_allocation(binding.field, Allocate(undef), backend)
    return _field_storage_binding(binding.field, storage;
        binding_id = binding.binding_id, ownership = :temporary)
end

function _materialize_temporary_bound(bound::_BoundLaw, backend)
    binding = bound.binding
    any(value -> value.storage isa _TemporaryStorageRequest,
        binding.fields) || return bound
    fields = map(value -> _materialize_temporary_field(value, backend),
        binding.fields)
    materialized = _StructuralBinding(
        fields, binding.relations, binding.collections)
    return _BoundLaw(_BOUND_LAW_SEAL, bound.law, materialized)
end

"""Plan one directly bound Stage program; the StructuralBinding is the only binding authority."""
Base.@nospecializeinfer Base.@noinline function plan(
        bound::_BoundLaw{<:LocalLaw,<:_StructuralBinding};
        backend::KernelAbstractions.Backend)
    Base.@nospecialize bound
    materialized_bound = Base.inferencebarrier(
        _materialize_temporary_bound(bound, backend))::_BoundLaw
    planned_bound = Base.inferencebarrier(
        _validate_bound_law(materialized_bound))::_BoundLaw
    lowering = Base.inferencebarrier(
        _stage_program_lowering(planned_bound, backend))::_StageProgramLowering
    return Plan(planned_bound, backend, lowering)
end

plan(work::LocalLaw, binding::_StructuralBinding;
    backend::KernelAbstractions.Backend) = plan(_bind_law(work, binding); backend)

function _validate_stage_program_leaf_facts(storage, prefix::Symbol, facts)
    leaves = storage === nothing ? () : _structural_physical_leaves(prefix, storage)
    length(leaves) == length(facts) || throw(LocalMathValidationError(
        "prepared Stage binding leaf count changed";
        stage = :execute, contract = :prepared_structural_binding,
        expected = length(facts), actual = length(leaves),
    ))
    for (pair, fact) in zip(leaves, facts)
        first(pair) == fact.name || throw(LocalMathValidationError(
            "prepared Stage binding leaf schema changed";
            stage = :execute, contract = :prepared_structural_binding,
            expected = fact.name, actual = first(pair),
        ))
        typeof(last(pair)) === fact.storage_type || throw(LocalMathValidationError(
            "prepared Stage binding leaf type changed";
            stage = :execute, contract = :prepared_structural_binding,
            expected = fact.storage_type, actual = typeof(last(pair)),
        ))
        _binding_logical_facts(last(pair)) == fact.logical || throw(
            LocalMathValidationError(
                "prepared Stage binding logical layout changed";
                stage = :execute, contract = :prepared_structural_binding,
                expected = fact.logical, actual = _binding_logical_facts(last(pair)),
            )
        )
        _validate_cached_static_array_fact(last(pair), fact.prepared, fact.name)
    end
    return nothing
end

function _validate_stage_program_bindings(bound::_BoundLaw)
    validated = bound.binding
    for (binding, facts) in zip(validated.fields, validated.field_facts)
        _validate_stage_program_leaf_facts(binding.storage, :field, facts)
    end
    for (binding, proof) in zip(validated.relations, validated.proofs)
        facts = proof.binding_schema.physical_leaves
        leaves = (
            binding.storage === nothing ? () :
                _structural_physical_leaves(:relation, binding.storage),
            binding.generation === nothing ? () :
                _structural_physical_leaves(:relation_generation,
                    binding.generation.generations),
            binding.status === nothing ? () :
                _structural_physical_leaves(:relation_status,
                    binding.status.statuses),
            binding.status === nothing ||
                binding.status.validated_generations === nothing ? () :
                _structural_physical_leaves(:relation_validated_generation,
                    binding.status.validated_generations),
        )
        flattened = (leaves[1]..., leaves[2]..., leaves[3]..., leaves[4]...)
        length(flattened) == length(facts) || throw(LocalMathValidationError(
            "prepared Stage relation leaf count changed";
            stage = :execute, contract = :prepared_structural_binding,
            expected = length(facts), actual = length(flattened),
        ))
        for (pair, fact) in zip(flattened, facts)
            first(pair) == fact.name && typeof(last(pair)) === fact.storage_type ||
                throw(LocalMathValidationError(
                    "prepared Stage relation schema changed";
                    stage = :execute, contract = :prepared_structural_binding,
                    expected = (fact.name, fact.storage_type),
                    actual = (first(pair), typeof(last(pair))),
                ))
            _validate_cached_static_array_fact(last(pair), fact.prepared, fact.name)
        end
    end
    for (binding, facts) in zip(validated.collections, validated.collection_facts)
        _validate_stage_program_leaf_facts(binding.storage, :collection, facts)
    end
    return nothing
end

function _validate_fresh_topology(plan::Plan{<:_BoundLaw};
        structural::Bool = true)
    if structural
        _validate_stage_program_bindings(plan.bound)
    end
    return nothing
end
_plan_law(plan) = plan.law
_plan_law(plan::Plan{<:_BoundLaw}) = plan.bound.law

function _stage_entry_workspace_spec(entry::_StageLoweringEntry,
        lease_capacity::Int)
    leaves = map(leaf -> _prepared_workspace_leaf(leaf, lease_capacity),
        entry.workspace.leaves)
    return merge(entry.workspace, (; leaves = Tuple(leaves)))
end

_stage_program_workspace(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_GroupedCandidateLayout}},
    tree, lease_capacity::Int) where {A,W} =
    _candidate_stage_workspace_from_tree(tree,
        _stage_entry_workspace_spec(entry, lease_capacity), entry.admission.stage)
_stage_program_workspace(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_DirectIdentityUniqueLayout}},
    tree, lease_capacity::Int) where {A,W} = nothing
_stage_program_workspace(entry::_StageLoweringEntry{A,W,<:_CollectStageExecutor},
    tree, lease_capacity::Int) where {A,W} =
    _collect_stage_workspace_from_tree(tree,
        _stage_entry_workspace_spec(entry, lease_capacity))
_stage_program_workspace(entry::_StageLoweringEntry{A,W,<:_OrderedFoldStageExecutor},
    tree, lease_capacity::Int) where {A,W} =
    _ordered_fold_stage_workspace_from_tree(tree,
        _stage_entry_workspace_spec(entry, lease_capacity))

function _stage_program_status(index::Int, context::_StageEntryContext,
        program_validation, program_host)
    return _ValidatedPublicationStatus(program_validation, program_host,
        context, :stage, index)
end

_prepare_stage_entry(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_GroupedCandidateLayout}},
        raw) where {A,W} =
    _prepare_candidate_stage(entry.admission, raw)
function _prepare_stage_entry(entry::_StageLoweringEntry{
        A,W,<:_CandidateStageExecutor{<:_DirectIdentityUniqueLayout}},
        raw) where {A,W}
    stage = entry.admission.stage
    destinations = map(stage.publications) do publication
        component = only(publication.components)
        _prepared_stage_field(stage.fields,
            _relation_target_slot(component.relation.view))
    end
    empty_policies = map(publication -> publication.law.onempty,
        stage.publications)
    return (; stage, destinations, empty_policies)
end
_prepare_stage_entry(entry::_StageLoweringEntry{A,W,<:_CollectStageExecutor},
        raw) where {A,W} =
    _prepare_collect_stage(entry.admission, raw)
_prepare_stage_entry(entry::_StageLoweringEntry{A,W,<:_OrderedFoldStageExecutor},
        raw) where {A,W} =
    _prepare_ordered_fold_stage(entry.admission, raw)

_stage_entry_validation(raw, ::_StageLoweringEntry) = raw.validation
_stage_entry_validation(::Nothing, ::_StageLoweringEntry{
    A,W,<:_CandidateStageExecutor{<:_DirectIdentityUniqueLayout}}) where {A,W} =
    nothing

Base.@noinline function _prepare_stage_launch(
        entry::_StageLoweringEntry, tree, receipt_tree,
        lease_capacity::Int,
        program_validation, program_host)
    raw = _stage_program_workspace(entry, tree, lease_capacity)
    stage = _prepare_stage_entry(entry, raw)
    status = _stage_program_status(
        entry.logical_index, entry.context, program_validation, program_host)
    guard = _prepare_stage_relation_guard(entry.relation_dependencies,
        receipt_tree, _stage_entry_validation(raw, entry))
    return _PreparedStageLaunch(stage, status, guard)
end


function _prepare_stage_launch(entry::_PointwiseSegmentEntry, workspace,
        lease_capacity::Int, program_validation, program_host)
    prepared = map(entry.members) do member
        _prepare_stage_entry(member, nothing)
    end
    first_member = first(entry.members)
    forwarding = ntuple(length(prepared)) do member_index
        stage = prepared[member_index].stage
        map(stage.fields) do field
            for producer_index in (member_index - 1):-1:1
                port_index = findfirst(destination -> destination === field,
                    prepared[producer_index].destinations)
                port_index === nothing || return _PointwiseForward{
                    producer_index,port_index}()
            end
            return _NoPointwiseForward()
        end
    end
    segment = _DirectPointwiseSegmentPreparation(
        first_member.admission.backend,
        map(value -> value.stage, prepared),
        map(value -> value.destinations, prepared),
        map(value -> value.empty_policies, prepared),
        entry.materializations,
        forwarding,
        map(member -> member.logical_index, entry.members),
        entry.boundary_reason,
    )
    status = _stage_program_status(first_member.logical_index,
        first_member.context, program_validation, program_host)
    return _PreparedStageLaunch(segment, status, _NoStageRelationGuard())
end

function _prepare_stage_launch(entry::_StageLoweringEntry, workspace,
        lease_capacity::Int, program_validation, program_host)
    index = entry.logical_index
    return _prepare_stage_launch(entry, workspace.stages[index],
        workspace.relation_receipts[index], lease_capacity,
        program_validation, program_host)
end

Base.@nospecializeinfer Base.@noinline function _prepare_stage_program(
        lowering::_StageProgramLowering, workspace,
        backend, lease_capacity::Int)
    Base.@nospecialize lowering workspace backend
    launches = _AbstractPreparedStageLaunch[]
    program_host = Matrix{UInt32}(undef, size(workspace.execution_gate))
    for entry in lowering.launches
        try
            push!(launches, _prepare_stage_launch(entry, workspace,
                lease_capacity, workspace.execution_gate, program_host))
        catch error
            context = first(_physical_launch_members(entry)).context
            annotated = _with_source_origin(error, context.origin,
                :prepare, :stage_preparation)
            annotated === error ? rethrow() : throw(annotated)
        end
    end
    return _PreparedStageProgram(launches, workspace.execution_gate)
end

# `_BoundLaw` already proves that the scientific bindings are mutually legal.
# Preparation must additionally prove that caller-owned scratch neither aliases
# one of those physical leaves nor crosses its device/context boundary.  The
# workspace is executable state, so this is deliberately checked here rather
# than trusting the cold structural proof alone.
function _stage_program_bound_arrays(bound::_BoundLaw)
    arrays = Pair{Symbol,Any}[]
    for (index, binding) in pairs(bound.binding.fields)
        for (leaf_index, array) in pairs(_binding_arrays(binding))
            push!(arrays, Symbol(:field_, index, :_, leaf_index) => array)
        end
    end
    for (index, binding) in pairs(bound.binding.relations)
        for (leaf_index, array) in pairs(_relation_data_arrays(binding))
            push!(arrays, Symbol(:relation_data_, index, :_, leaf_index) => array)
        end
        for (leaf_index, array) in pairs(_relation_generation_arrays(binding))
            push!(arrays, Symbol(:relation_generation_, index, :_, leaf_index) => array)
        end
        for (leaf_index, array) in pairs(_relation_status_arrays(binding))
            push!(arrays, Symbol(:relation_status_, index, :_, leaf_index) => array)
        end
    end
    for (index, binding) in pairs(bound.binding.collections)
        for (leaf_index, array) in pairs(_collection_arrays(binding))
            push!(arrays, Symbol(:collection_, index, :_, leaf_index) => array)
        end
    end
    return Tuple(arrays)
end

function _validate_stage_program_workspace(bound::_BoundLaw, workspace_arrays)
    bindings = _stage_program_bound_arrays(bound)
    for (binding_name, binding) in bindings
        for (workspace_name, scratch) in workspace_arrays
            aliased_leaves = _arrays_mightalias(
                binding_name, binding, workspace_name, scratch)
            aliased_leaves === nothing || throw(LocalMathValidationError(
                "Stage binding $binding_name aliases workspace $workspace_name";
                stage = :prepare, contract = :workspace_alias,
                binding = binding_name, workspace_leaf = workspace_name,
                expected = :nonaliasing,
                actual = (binding = binding_name, workspace = workspace_name,
                    physical_leaves = aliased_leaves),
            ))
        end
    end
    identities = Any[_array_device_identity(last(pair)) for pair in bindings]
    append!(identities, (_array_device_identity(array)
        for (_, array) in workspace_arrays))
    isempty(identities) || all(==(first(identities)), identities) || throw(
        LocalMathValidationError(
            "Stage bindings and workspace span devices or contexts";
            stage = :prepare, contract = :device_coherence,
            expected = first(identities), actual = Tuple(identities),
        )
    )
    return nothing
end

@inline function _stage_candidate_failure(code::Int32)
    code == _CANDIDATE_STATUS_COVERAGE && return :coverage
    code == _CANDIDATE_STATUS_CONFLICT && return :conflict
    code == _CANDIDATE_STATUS_DUPLICATE_TIE && return :duplicate_tie
    code == _CANDIDATE_STATUS_RANK_BOUNDS && return :rank_bounds
    code == _CANDIDATE_STATUS_ROUTE_KEY && return :invalid_route_key
    code == _CANDIDATE_STATUS_RELATION && return :invalid_relation_endpoint
    code == _CANDIDATE_STATUS_INVALID_CONTROL && return :invalid_control
    return :invalid_failure_class
end

@inline function _stage_collect_failure(code::Int32)
    code == Int32(_COMPACTED_CAPACITY) && return :capacity_overflow
    code == Int32(_COMPACTED_GROUP) && return :invalid_group
    code == Int32(_COMPACTED_DUPLICATE) && return :duplicate_identity
    code == _COLLECT_STATUS_INVALID_CONTROL && return :invalid_control
    return :invalid_failure_class
end

function _validated_publication_error(
        status::_ValidatedPublicationStatus{D,H,C}, lease_index::Int
    ) where {D,H,C<:_StageEntryContext}
    recorded_stage = _validation_decode_int32(_validation_status_word(
        status, _VALIDATION_STAGE_INDEX, lease_index))
    recorded_stage == status.stage || return nothing
    code = _validation_decode_int32(_validation_status_word(
        status, _VALIDATION_FAILURE_CLASS, lease_index))
    code == 0 && return nothing
    context_index = _validation_decode_int32(_validation_status_word(
        status, _VALIDATION_CONTEXT_INDEX, lease_index))
    primary = _validation_decode_int32(_validation_status_word(
        status, _VALIDATION_PRIMARY_RECORD, lease_index))
    secondary = _validation_decode_int32(_validation_status_word(
        status, _VALIDATION_SECONDARY_RECORD, lease_index))
    witness = reinterpret(Int32, _validation_status_word(
        status, _VALIDATION_WITNESS_BITS, lease_index))
    relation_failure = code == _CANDIDATE_STATUS_RELATION
    publication = !relation_failure &&
            1 <= context_index <= length(status.context.publications) ?
        status.context.publications[context_index] :
        !relation_failure && length(status.context.publications) == 1 ?
            only(status.context.publications) : nothing
    relation = relation_failure &&
            1 <= context_index <= length(status.context.dynamic_relations) ?
        status.context.dynamic_relations[context_index] : nothing
    port = publication === nothing || isempty(publication.ports) ? nothing :
        only(publication.ports)
    fold_failure = code == _ORDERED_FOLD_UPDATE_COUNT ? :invalid_update_count :
        code == _ORDERED_FOLD_DESTINATION ? :invalid_destination :
        code == _ORDERED_FOLD_DUPLICATE_UPDATE ? :duplicate_destination :
        code == _ORDERED_FOLD_DUPLICATE_ORDER ? :duplicate_order_identity :
        code == _ORDERED_FOLD_INVALID_VALUE ? :invalid_bounded_value :
        code == _ORDERED_FOLD_EMPTY_INPUT ? :empty_bounded_input :
        :invalid_failure_class
    component = publication !== nothing &&
        hasproperty(publication.details, :fold_components) &&
        1 <= context_index <= length(publication.details.fold_components) ?
        publication.details.fold_components[context_index] : nothing
    contract = status.context.executor === :ordered_fold ?
        :runtime_ordered_fold_validation : :runtime_stage_validation
    failure_class = status.context.executor === :ordered_fold ? fold_failure :
        status.context.executor === :candidate ? _stage_candidate_failure(code) :
        status.context.executor === :collect ? _stage_collect_failure(code) :
        :invalid_failure_class
    origin = publication === nothing ||
        !_has_source_origin(publication.origin) ?
        status.context.origin : publication.origin
    return LocalMathValidationError(
        "Stage publication-law validation failed";
        stage = :wait, contract,
        port, origin,
        expected = :valid_bounded_publication_law,
        actual = (stage = status.stage, failure_code = code,
            failure_class,
            component, relation, relation_dependency = relation_failure ?
                context_index : nothing, source_item = primary,
            canonical_position = secondary, witness,
            context_index,
            publications = status.context.publications),
    )
end

Base.@noinline function _enqueue_stage!(
        launch::_PreparedStageLaunch{S,T,G}, parameters::Tuple,
        predecessors::Tuple, lease_index::Int32) where {S,T,G}
    prepared = launch.stage
    status = launch.status
    program_validation = _ProgramValidationTarget(
        status.device, Int32(status.stage))
    try
        _execute_stage_program_stage!(prepared, parameters, lease_index,
            predecessors, launch.guard, program_validation)
    catch error
        annotated = _with_source_origin(error, status.context.origin,
            :execute, :stage_enqueue)
        annotated === error ? rethrow() : throw(annotated)
    end
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _execute_stages!(
        stages::Vector{_AbstractPreparedStageLaunch}, parameters::Tuple,
        predecessors::Tuple, lease_index::Int32)
    Base.@nospecialize stages
    for stage in stages
        _enqueue_stage!(stage, parameters, predecessors, lease_index)
    end
    return nothing
end

_execute_stage_program_stage!(prepared::_CandidateStagePreparation,
    parameters::Tuple, lease_index::Int32, predecessors::Tuple, guard,
    program_validation) = _execute_candidate_stage!(prepared, parameters,
        lease_index, predecessors, guard, program_validation)
_execute_stage_program_stage!(prepared::_CollectStagePreparation,
    parameters::Tuple, lease_index::Int32, predecessors::Tuple, guard,
    program_validation) = _execute_collect_stage!(prepared, parameters,
        lease_index, predecessors, guard, program_validation)
_execute_stage_program_stage!(prepared::_OrderedFoldStagePreparation,
    parameters::Tuple, lease_index::Int32, predecessors::Tuple, guard,
    program_validation) = _execute_ordered_fold_stage!(prepared, parameters,
        lease_index, predecessors, guard, program_validation)
_execute_stage_program_stage!(prepared::_DirectPointwiseSegmentPreparation,
    parameters::Tuple, lease_index::Int32, predecessors::Tuple,
    ::_NoStageRelationGuard, program_validation) =
    _execute_direct_pointwise_segment!(
        prepared, parameters, lease_index, predecessors, program_validation)

@kernel function _stage_program_status_reset_kernel!(status, lease::Int32)
    index = @index(Global, Linear)
    index == 1 && _clear_validation_status!(status, lease)
end

@kernel function _execution_dependency_join_kernel!(
        target, target_lease::Int32, source, source_lease::Int32)
    index = @index(Global, Linear)
    if index == 1 &&
            @inbounds(target[_VALIDATION_FAILURE_CLASS, target_lease]) == UInt32(0) &&
            @inbounds(source[_VALIDATION_FAILURE_CLASS, source_lease]) != UInt32(0)
        # Device state owns publication suppression only. ExecutionReceipt traversal
        # remains the exact, argument-ordered dependency failure authority.
        @inbounds begin
            target[_VALIDATION_FAILURE_CLASS, target_lease] = UInt32(1)
            target[_VALIDATION_CONTEXT_INDEX, target_lease] = UInt32(0)
            target[_VALIDATION_PRIMARY_RECORD, target_lease] = UInt32(0)
            target[_VALIDATION_SECONDARY_RECORD, target_lease] = UInt32(0)
            target[_VALIDATION_WITNESS_BITS, target_lease] = UInt32(0)
            target[_VALIDATION_STAGE_INDEX, target_lease] = UInt32(0)
        end
    end
end

@kernel function _stage_program_reset_join_kernel!(
        target, target_lease::Int32, source, source_lease::Int32)
    index = @index(Global, Linear)
    if index == 1
        _clear_validation_status!(target, target_lease)
        if @inbounds(source[_VALIDATION_FAILURE_CLASS, source_lease]) != UInt32(0)
            # Only publication suppression is copied. Receipt traversal remains
            # the argument-ordered dependency failure authority.
            @inbounds begin
                target[_VALIDATION_FAILURE_CLASS, target_lease] = UInt32(1)
                target[_VALIDATION_CONTEXT_INDEX, target_lease] = UInt32(0)
                target[_VALIDATION_PRIMARY_RECORD, target_lease] = UInt32(0)
                target[_VALIDATION_SECONDARY_RECORD, target_lease] = UInt32(0)
                target[_VALIDATION_WITNESS_BITS, target_lease] = UInt32(0)
                target[_VALIDATION_STAGE_INDEX, target_lease] = UInt32(0)
            end
        end
    end
end

Base.@nospecializeinfer Base.@noinline function _enqueue_dependency_joins!(
        target, target_lease::Int32, dependencies::Tuple)
    Base.@nospecialize dependencies
    backend = KernelAbstractions.get_backend(target)
    for dependency in dependencies
        _receipt_settled(dependency) && continue
        source = dependency.prepared.runtime.execution_gate
        _execution_dependency_join_kernel!(backend)(target, target_lease,
            source, dependency.lease_index; ndrange = 1)
    end
    return nothing
end

Base.@nospecializeinfer Base.@noinline function
        _enqueue_reset_and_dependency_joins!(
        target, target_lease::Int32, dependencies::Tuple)
    Base.@nospecialize dependencies
    backend = KernelAbstractions.get_backend(target)
    reset_submitted = false
    for dependency in dependencies
        _receipt_settled(dependency) && continue
        source = dependency.prepared.runtime.execution_gate
        if reset_submitted
            _execution_dependency_join_kernel!(backend)(target, target_lease,
                source, dependency.lease_index; ndrange = 1)
        else
            _stage_program_reset_join_kernel!(backend)(target, target_lease,
                source, dependency.lease_index; ndrange = 1)
            reset_submitted = true
        end
    end
    reset_submitted || _stage_program_status_reset_kernel!(backend)(
        target, target_lease; ndrange = 1)
    return nothing
end

_program_phases(::_StageProgramLowering) =
    (_phase_fact(:program_status_reset),)

Base.@nospecializeinfer Base.@noinline function _execute_lowering!(
        runtime::_PreparedStageProgram,
        submission::Tuple, lease_index::Int,
        dependencies::Tuple)
    Base.@nospecialize dependencies
    _enqueue_reset_and_dependency_joins!(runtime.execution_gate,
        Int32(lease_index), dependencies)
    _execute_stages!(runtime.launches, submission,
        (runtime.execution_gate,), Int32(lease_index))
    return nothing
end

@inline function _stage_callable_admission(
        callback, signature, purpose::Symbol, admission::Symbol,
        analysis::NamedTuple,
    )
    analysis.qualified || error("callback facts require admitted analysis")
    return _CallableAdmissionFact(callback, signature, analysis.method,
        purpose, admission, analysis.return_type)
end

_stage_order_callable_admissions(
    ::_SourceOrder, ::Type, ::Symbol, ::Dict{Any,Any}) = ()
function _stage_order_callable_admissions(
        order::_CanonicalBy, ::Type{T}, purpose::Symbol,
        analysis_cache::Dict{Any,Any},
    ) where {T}
    signature = Tuple{T}
    key = order.key isa _OrderingField ? () : begin
        analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_ordering, order.key, signature,
            method_signature -> length(method_signature) == 2)
        (_stage_callable_admission(order.key, signature,
            Symbol(purpose, :_order_key), :closed_ordering, analysis),)
    end
    identity = order.identity isa _OrderingField ? () : begin
        analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_ordering, order.identity, signature,
            method_signature -> length(method_signature) == 2)
        (_stage_callable_admission(order.identity, signature,
            Symbol(purpose, :_order_identity), :closed_ordering, analysis),)
    end
    return (key..., identity...)
end
function _stage_order_callable_admissions(
        order::_PreparedCanonicalBy, ::Type{T}, purpose::Symbol,
        analysis_cache::Dict{Any,Any},
    ) where {T}
    signature = Tuple{T}
    key = order.key isa _OrderingField ? () : begin
        analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_ordering, order.key, signature,
            method_signature -> length(method_signature) == 2)
        (_stage_callable_admission(order.key, signature,
            Symbol(purpose, :_order_key), :closed_ordering, analysis),)
    end
    identity = order.identity isa _OrderingField ? () : begin
        analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_ordering, order.identity, signature,
            method_signature -> length(method_signature) == 2)
        (_stage_callable_admission(order.identity, signature,
            Symbol(purpose, :_order_identity), :closed_ordering, analysis),)
    end
    return (key..., identity...)
end

_stage_group_callable_admissions(
    ::_OneGroup, ::Type, ::Dict{Any,Any}) = ()
_stage_group_callable_admissions(
    ::_RoutedGroups, ::Type, ::Dict{Any,Any}) = ()
function _stage_group_callable_admissions(
        groups::_GroupBy, ::Type{T}, analysis_cache::Dict{Any,Any}) where {T}
    groups.extractor isa _OrderingField && return ()
    signature = Tuple{T}
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_ordering, groups.extractor, signature,
        method_signature -> length(method_signature) == 2)
    return (_stage_callable_admission(groups.extractor, signature,
        :collect_group_key, :closed_ordering, analysis),)
end

_stage_publication_callable_admissions(stage,
    ::_PreparedStagePublication{C,<:Unique}, analysis_cache) where {C} = ()
_stage_publication_callable_admissions(stage,
    ::_PreparedStagePublication{C,<:Resolve}, analysis_cache) where {C} = ()
function _stage_publication_callable_admissions(stage,
        publication::_PreparedStagePublication{C,<:Reduce{T}},
        analysis_cache::Dict{Any,Any},
    ) where {C,T}
    signature = Tuple{T,T}
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_stage_reduce, publication.law.operation, signature,
        method_signature -> length(method_signature) == 3)
    return (_stage_callable_admission(publication.law.operation, signature,
        :reduce_operation, :closed_stage_reduce, analysis),)
end
function _stage_publication_callable_admissions(stage,
        publication::_PreparedStagePublication{C,<:_PreparedCollectLaw{T}},
        analysis_cache::Dict{Any,Any},
    ) where {C,T}
    law = publication.law
    return (_stage_group_callable_admissions(law.groups, T, analysis_cache)...,
        _stage_order_callable_admissions(
            law.order, T, :collect, analysis_cache)...)
end
function _stage_publication_callable_admissions(stage,
        publication::_PreparedStagePublication{
            C,<:_PreparedOrderedFoldLaw{T}},
        analysis_cache::Dict{Any,Any},
    ) where {C,T}
    law = publication.law
    state = only(publication.components).state
    accumulator = _prepared_fold_accumulator(stage.fields, state)
    signature = Tuple{typeof(accumulator),T,Int32,
        _stage_reads_type(stage.fields, stage.accesses)}
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_ordered_fold_transition, law.transition, signature,
        method_signature -> length(method_signature) == 5)
    return (_stage_callable_admission(law.transition, signature,
            :ordered_fold_transition, :closed_ordered_fold_transition,
            analysis),
        _stage_order_callable_admissions(
            law.order, T, :ordered_fold, analysis_cache)...)
end

Base.@nospecializeinfer Base.@noinline function _stage_callable_admissions(
        admission::_StageAdmission, analysis_cache::Dict{Any,Any})
    Base.@nospecialize admission
    cold = Base.inferencebarrier(admission)::_StageAdmission
    stage = cold.stage
    evaluator = stage.evaluator.evaluator
    analysis_evaluator, analysis_signature, method_arity =
        _stage_evaluator_analysis_target(evaluator, cold.signature)
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_stage_evaluator, analysis_evaluator, analysis_signature,
        method_signature -> length(method_signature) == method_arity;
        source_policy = _stage_evaluator_source_safe,
        typed_policy = _stage_access_typed_safe)
    analysis.qualified || error("callback facts require admitted analysis")
    evaluator_method = which(evaluator, cold.signature)
    admissions = _CallableAdmissionFact[_CallableAdmissionFact(
        evaluator, cold.signature, evaluator_method, :stage_evaluator,
        :closed_stage_evaluator, analysis.return_type)]
    for publication in stage.publications
        append!(admissions, _stage_publication_callable_admissions(stage,
            Base.inferencebarrier(publication), analysis_cache))
    end
    return admissions
end

function _stage_parameter_type_witness(::Type{T}) where {T}
    sizeof(T) == 0 && return T()
    bytes = zeros(UInt8, sizeof(T))
    return only(reinterpret(T, bytes))
end
@inline _stage_parameter_witness(slot::_StageParameterSlot{T}) where {T} =
    slot.bounds isa _ClosedParameterBounds ? slot.bounds.lower :
        _stage_parameter_type_witness(T)
_stage_parameter_witness(layout::_StageParameterLayout) =
    map(_stage_parameter_witness, layout.slots)

@kernel function _stage_backend_qualification_gate_kernel!(
        gate, failure::Int32, leases::Int32)
    lease = @index(Global, Linear)
    if lease <= leases
        # Keep this qualification-only write fully explicit. Calling the
        # generic status helpers with KA's backend-native linear index caused
        # Metal to retain checked/dynamic array-set paths in this exact kernel.
        @inbounds begin
            gate[_VALIDATION_FAILURE_CLASS, lease] =
                failure == 0 ? UInt32(0) : reinterpret(UInt32, failure)
            gate[_VALIDATION_CONTEXT_INDEX, lease] = UInt32(0)
            gate[_VALIDATION_PRIMARY_RECORD, lease] = UInt32(0)
            gate[_VALIDATION_SECONDARY_RECORD, lease] = UInt32(0)
            gate[_VALIDATION_WITNESS_BITS, lease] = UInt32(0)
            gate[_VALIDATION_STAGE_INDEX, lease] = UInt32(0)
        end
    end
end

function _qualify_stage_backend!(runtime::_PreparedStageProgram,
        parameter_layout::_StageParameterLayout, backend,
        dependency_arity::Int)
    leases = Int32(size(runtime.execution_gate, 2))
    _stage_program_status_reset_kernel!(backend)(runtime.execution_gate,
        Int32(1); ndrange = 1)
    dependency_arity > 0 && _execution_dependency_join_kernel!(backend)(
        runtime.execution_gate, Int32(1), runtime.execution_gate, Int32(1);
        ndrange = 1)
    _stage_backend_qualification_gate_kernel!(backend)(
        runtime.execution_gate, Int32(1), leases; ndrange = Int(leases))
    _execute_stages!(runtime.launches,
        _stage_parameter_witness(parameter_layout),
        (runtime.execution_gate,), Int32(1))
    try
        KernelAbstractions.synchronize(backend)
    catch error
        throw(LocalMathValidationError(
            "the prepared Stage program failed exact KernelAbstractions backend qualification";
            stage = :prepare, contract = :stage_backend_qualification,
            expected = :compilable_exact_physical_stage_program,
            actual = sprint(showerror, error),
        ))
    end
    _stage_backend_qualification_gate_kernel!(backend)(
        runtime.execution_gate, Int32(0), leases; ndrange = Int(leases))
    KernelAbstractions.synchronize(backend)
    return nothing
end

function prepare(plan::Plan{<:_BoundLaw}; workspace = nothing,
        lease_capacity::Union{Nothing,Integer} = nothing,
        dependency_arity::Integer = 0)
    _validate_fresh_topology(plan)
    capacity = lease_capacity === nothing ? 1 : Int(lease_capacity)
    capacity > 0 || throw(LocalMathValidationError("lease_capacity must be positive";
        stage = :prepare, contract = :workspace_lease_capacity))
    arity = Int(dependency_arity)
    arity >= 0 || throw(LocalMathValidationError(
        "dependency_arity must be nonnegative";
        stage = :prepare, contract = :dependency_arity,
        expected = :nonnegative, actual = dependency_arity))
    package_workspace = workspace === nothing
    workspace_ownership = package_workspace ? :package : :caller
    package_workspace && (workspace = _automatic_workspace(
        plan.lowering, plan.backend, capacity))
    leases = _workspace_leases(workspace)
    length(leases) == capacity || throw(LocalMathValidationError(
        "workspace lease capacity disagrees with preparation";
        stage = :prepare, contract = :workspace_lease_capacity))
    if !package_workspace
        _validate_workspace(plan.lowering, workspace,
            plan.backend, capacity)
        workspace_arrays = _workspace_arrays(
            plan.lowering, workspace, capacity)
        _validate_workspace_structure(workspace, :workspace)
        _validate_stage_program_workspace(plan.bound, workspace_arrays)
    end
    parameter_layout = _stage_parameter_layout(plan.bound.law.parameters)
    runtime = _prepare_stage_program(plan.lowering, workspace,
        plan.backend, capacity)
    _qualify_stage_backend!(runtime, parameter_layout, plan.backend, arity)
    lane = _central_make_provider_lane(plan.backend, (;))
    return PreparedPlan(_CONSTRUCTION_TOKEN, plan, workspace,
        parameter_layout, lane, runtime, workspace_ownership,
        current_task(), UInt64(0), UInt64(0), leases,
        zeros(UInt64, capacity), 1, 0, arity, false, nothing)
end

"""Bind, plan, and prepare one law through the canonical production path."""
function prepare(law::LocalLaw, bindings::Pair...;
        backend::KernelAbstractions.Backend, workspace = nothing,
        lease_capacity::Union{Nothing,Integer} = nothing,
        dependency_arity::Integer = 0)
    bound = bind(law, bindings...; backend)
    planned = plan(bound; backend)
    return prepare(planned; workspace, lease_capacity, dependency_arity)
end

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

function _semantic_equivalence(work::LocalLaw)
    _, relations, _ = _law_descriptor_requirements(work)
    stages = Tuple(map(enumerate(work.stages)) do (index, stage)
        report = _semantic_stage_inspection(stage, index)
        publications = map(report.publications) do publication
            merge(publication, (origin = nothing,))
        end
        return merge(report,
            (origin = nothing, publications, planning = nothing))
    end)
    return (
        parameters = map(_parameter_inspection,
            work.parameters.declarations),
        relations = map(relation -> _relation_inspection(relation, nothing),
            relations),
        stages,
        evaluators = map(stage -> (
                value = stage.evaluator.evaluator,
                type = typeof(stage.evaluator.evaluator),
                parameters = map(_parameter_inspection,
                    stage.evaluator.parameters),
            ), work.stages),
    )
end

function _inspect_local_law(work::LocalLaw)
    _, relations, _ = _law_descriptor_requirements(work)
    return (
        lifecycle = :LocalLaw,
        parameters = map(_parameter_inspection,
            work.parameters.declarations),
        relations = map(relation -> _relation_inspection(relation, nothing),
            relations),
        stages = Tuple(map(enumerate(work.stages)) do (index, stage)
            _semantic_stage_inspection(stage, index)
        end),
        planning = nothing,
        equivalence = _semantic_equivalence(work),
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
        levels = _collect_scan_level_count(items)
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
        A,W,<:_OrderedFoldStageExecutor}) where {A,W}
    phases = Any[_phase_fact(:ordered_fold_reset)]
    append!(phases, _planned_relation_phases(entry))
    push!(phases, _phase_fact(:ordered_fold_evaluate))
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
_stage_layout_name(::_OrderedFoldStageExecutor) = :ordered_recurrence

function _segment_materializations(work::LocalLaw, indices)
    return Tuple(semantic_identity(component.field)
        for index in indices
        for publication in work.stages[index].publications
        for component in publication.components
        if component isa FieldPublication)
end

function _physical_segment_inspection(
        launch::_PointwiseSegmentEntry, work::LocalLaw)
    indices = map(member -> member.logical_index, launch.members)
    source = work.stages[first(indices)].source
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
        entry::_StageLoweringEntry, work::LocalLaw)
    index = entry.logical_index
    phases = _planned_stage_phases(entry)
    return (
        logical_stages = (index,),
        family = _stage_layout_name(entry.executor),
        launch_count = _phase_count(phases),
        traversal = semantic_identity(work.stages[index].source),
        retained_materializations = _segment_materializations(work, (index,)),
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
    work = plan.bound.law
    _, relations, _ = _law_descriptor_requirements(work)
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
        semantic = work.stages[index]
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
        _physical_segment_inspection(launch, work)
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
            work.parameters.declarations),
        relations = map(_relation_inspection, relations, proofs),
        stages = Tuple(stages),
        planning,
        equivalence = _semantic_equivalence(work),
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
            provider_completions = _lane_wait_count(prepared.lane),
            provider_scope_completions =
                _lane_scope_wait_count(prepared.lane),
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
        observed_provider_completions = _lane_wait_count(lane),
        observed_scope_completions = _lane_scope_wait_count(lane),
        observed_validation_transfers = _lane_transfer_count(lane),
    )
end
