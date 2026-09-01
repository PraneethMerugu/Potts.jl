# Cold, non-executable planning facts for the stage-tuple LocalLaw waist.
# This file deliberately does not construct a Plan: exact evaluator
# signature/effect admission belongs to the prepared-access ABI boundary.

struct _ExternalFieldDependency{S}
    field::S
    field_id::UUIDs.UUID
end

struct _PrecedingFieldDependency{S}
    field::S
    field_id::UUIDs.UUID
    stage::Int
end

struct _PrecedingCollectionDependency{S}
    collection::S
    collection_id::UUIDs.UUID
    stage::Int
    role::Symbol
end

struct _RelationUse{S}
    relation::S
    relation_id::UUIDs.UUID
end

"""The sole cold descriptor-to-stage-local-slot mapping authority."""
struct _StageFieldLayout{F,R,C,FI,RI,CI}
    fields::F
    relations::R
    collections::C
    field_ids::FI
    relation_ids::RI
    collection_ids::CI
end

struct _NoPreparedTarget end
struct _NoPreparedGhost end

struct _ProjectedRelationUse{R,T,G}
    relation::R
    target::T
    ghost::G
end
struct _ProjectedCollectionUse{S}
    slot::S
end
struct _ProjectedCollectionAccess{S,L}
    slot::S
    law::L
end
struct _ProjectedFoldStateField{T,S}
    target::T
    source::S
end
struct _ProjectedFoldState{C<:NamedTuple}
    components::C
end

struct _ProjectedStageControl{P,M,S,G}
    prefix::P
    mask::M
    subset::S
    gate::G
end

struct _StageProjection{L,A,U,C,P}
    layout::L
    accesses::A
    publications::U
    control::C
    parameters::P
end

function _resolve_parameter_slot(
        schema::ParameterSchema, declaration::Parameter,
    )
    for index in eachindex(schema.declarations)
        candidate = schema.declarations[index]
        candidate.name === declaration.name || continue
        _same_parameter_declaration(candidate, declaration) || throw(
            LocalMathValidationError(
                "a Stage parameter declaration conflicts with the program ParameterSchema";
                stage = :plan, contract = :parameter_slot_schema,
                expected = declaration, actual = candidate,
            )
        )
        return _ParameterSlot{index}()
    end
    throw(LocalMathValidationError(
        "a Stage parameter declaration has no program positional slot";
        stage = :plan, contract = :parameter_slot,
        expected = declaration, actual = :missing,
    ))
end

_parameter_prefix_slot(::ParameterSchema, ::_NoPrefix) = nothing
_parameter_prefix_slot(schema::ParameterSchema, value::_ParameterPrefix) =
    _resolve_parameter_slot(schema, value.parameter)
_parameter_prefix_slot(::ParameterSchema, ::_FieldPrefix) = nothing
_parameter_prefix_slot(::ParameterSchema, ::_CollectionCount) = nothing

_parameter_gate_slot(::ParameterSchema, ::_NoGate) = nothing
_parameter_gate_slot(schema::ParameterSchema, value::_ParameterGate) =
    _resolve_parameter_slot(schema, value.parameter)
_parameter_gate_slot(::ParameterSchema, ::_FieldGate) = nothing

function _stage_parameter_slots(schema::ParameterSchema, stage::Stage)
    evaluator_values = Any[]
    sizehint!(evaluator_values, length(stage.evaluator.parameters))
    for declaration in stage.evaluator.parameters
        push!(evaluator_values, _resolve_parameter_slot(schema, declaration))
    end
    return (
        evaluator = Tuple(evaluator_values),
        prefix = _parameter_prefix_slot(schema, stage.control.prefix),
        gate = _parameter_gate_slot(schema, stage.control.gate),
    )
end

function _stage_descriptor_closure(stage::Stage)
    fields = Any[]
    relations = Any[]
    collections = Any[]
    _append_stage_requirements!(fields, relations, collections, stage)
    closed_fields, closed_relations = _required_descriptor_closure(
        Tuple(fields), Tuple(relations),
    )
    return closed_fields, closed_relations, Tuple(collections)
end

Base.@nospecializeinfer Base.@noinline function _stage_field_layout(
        validated::_ValidatedStructuralBinding, stage::Stage)
    Base.@nospecialize validated stage
    fields, relations, collections = _stage_descriptor_closure(stage)
    field_slots, relation_slots, collection_slots = Any[], Any[], Any[]
    field_ids, relation_ids, collection_ids = Any[], Any[], Any[]
    for field in fields
        push!(field_slots, _resolve_field_slot(validated, field))
        push!(field_ids, semantic_identity(field))
    end
    for relation in relations
        push!(relation_slots, _resolve_relation_slot(validated, relation))
        push!(relation_ids, semantic_identity(relation))
    end
    for collection in collections
        push!(collection_slots,
            _resolve_collection_slot(validated, collection))
        push!(collection_ids, semantic_identity(collection))
    end
    return _StageFieldLayout(Tuple(field_slots), Tuple(relation_slots),
        Tuple(collection_slots), Tuple(field_ids), Tuple(relation_ids),
        Tuple(collection_ids))
end

_stage_field_layout(bound::_BoundLaw, stage::Stage) =
    _stage_field_layout(bound.binding, stage)

function _local_collection_slot(layout::_StageFieldLayout, collection::Collection)
    index = findfirst(==(semantic_identity(collection)), layout.collection_ids)
    index === nothing && throw(LocalMathValidationError(
        "a Stage Collection is absent from its planned local layout";
        stage = :plan, contract = :stage_local_collection_layout,
        actual = semantic_identity(collection),
    ))
    return @inbounds layout.collections[index]
end

function _local_field_slot(layout::_StageFieldLayout, field::Field)
    index = findfirst(==(semantic_identity(field)), layout.field_ids)
    index === nothing && throw(LocalMathValidationError(
        "a Stage Field is absent from its planned local layout";
        stage = :plan, contract = :stage_local_field_layout,
        actual = semantic_identity(field),
    ))
    return _PreparedFieldSlot{index}()
end

function _planned_relation_slot(layout::_StageFieldLayout, relation::Relation)
    index = findfirst(==(semantic_identity(relation)), layout.relation_ids)
    index === nothing && throw(LocalMathValidationError(
        "a Stage Relation is absent from its planned local layout";
        stage = :plan, contract = :stage_local_relation_layout,
        actual = semantic_identity(relation),
    ))
    return @inbounds layout.relations[index]
end

function _project_relation_use(
        layout::_StageFieldLayout, relation::Relation, target;
        ghost = _NoPreparedGhost(),
    )
    return _ProjectedRelationUse(
        _planned_relation_slot(layout, relation), target, ghost,
    )
end

function _project_fold_state(
        layout::_StageFieldLayout, law::OrderedFold,
    )
    names = keys(law.state.components)
    values = Any[]
    sizehint!(values, length(names))
    for component in Base.values(law.state.components)
        push!(values, _ProjectedFoldStateField(
            _local_field_slot(layout, component.target),
            component.source isa _FoldInPlace ? nothing :
                _local_field_slot(layout, component.source),
        ))
    end
    components = NamedTuple{names}(Tuple(values))
    return _ProjectedFoldState(components)
end

function _project_publication(
        layout::_StageFieldLayout, publication::Publication,
    )
    law = publication.law
    if law isa Collect
        component = only(publication.components)
        return (_ProjectedCollectionUse(
            _local_collection_slot(layout, component.collection),
        ),)
    elseif law isa OrderedFold
        return (_project_fold_state(layout, law),)
    end
    projected = Any[]
    sizehint!(projected, length(publication.components))
    for component in publication.components
        push!(projected, _project_relation_use(layout, component.relation,
            _local_field_slot(layout, component.field)))
    end
    return Tuple(projected)
end

Base.@nospecializeinfer Base.@noinline function _stage_slot_projection(
        validated::_ValidatedStructuralBinding, schema::ParameterSchema,
        stage::Stage)
    Base.@nospecialize validated schema stage
    layout = _stage_field_layout(validated, stage)
    access_values = Any[]
    sizehint!(access_values, length(stage.accesses))
    for access in values(stage.accesses)
        projected = access isa Access ? _project_relation_use(
            layout, access.relation, _local_field_slot(layout, access.field);
            ghost = access.ghost === nothing ? _NoPreparedGhost() :
                _local_field_slot(layout, access.ghost),
        ) : _ProjectedCollectionAccess(
            _local_collection_slot(layout, access.collection), access.law)
        push!(access_values, projected)
    end
    publication_values = Any[]
    sizehint!(publication_values, length(stage.publications))
    for publication in stage.publications
        push!(publication_values, _project_publication(layout, publication))
    end
    accesses = Tuple(access_values)
    publications = Tuple(publication_values)
    control = stage.control
    projected_control = _ProjectedStageControl(
        control.prefix isa _FieldPrefix ?
            _local_field_slot(layout, control.prefix.field) :
            control.prefix isa _CollectionCount ?
                _local_collection_slot(layout, control.prefix.collection) : nothing,
        control.mask isa _MaskSelection ?
            _local_field_slot(layout, control.mask.field) : nothing,
        control.subset isa _SubsetSelection ? _project_relation_use(
            layout, control.subset.relation, _NoPreparedTarget(),
        ) : nothing,
        control.gate isa _FieldGate ?
            _local_field_slot(layout, control.gate.field) : nothing,
    )
    return _StageProjection(
        layout, accesses, publications, projected_control,
        _stage_parameter_slots(schema, stage),
    )
end

_stage_slot_projection(bound::_BoundLaw, stage::Stage) =
    _stage_slot_projection(bound.binding, bound.law.parameters, stage)

function _stage_publishes_field(
        stage::Stage, field::Field; total::Bool = false,
    )
    for publication in stage.publications
        if publication.law isa OrderedFold
            for component in values(publication.law.state.components)
                semantic_identity(component.target) == semantic_identity(field) ||
                    continue
                component.target == field || throw(LocalMathValidationError(
                    "a fold target Field identity has conflicting schema";
                    stage = :plan, contract = :field_dependency_schema,
                    expected = field, actual = component.target,
                ))
                # A terminal recurrence is not a pointwise total publication;
                # it cannot satisfy a field-derived Control's totality proof.
                return !total
            end
            continue
        end
        for component in publication.components
            component isa FieldPublication || continue
            semantic_identity(component.field) == semantic_identity(field) || continue
            component.field == field || throw(LocalMathValidationError(
                "a published Field identity has conflicting schema";
                stage = :plan, contract = :field_dependency_schema,
                expected = field, actual = component.field,
            ))
            !total || publication.law.coverage isa TotalCoverage || return false
            return true
        end
    end
    return false
end

Base.@nospecializeinfer Base.@noinline function _nearest_preceding_publication(
        stages::Tuple, index::Int, field::Field)
    # This is cold semantic analysis.  Specializing the reverse scan on the
    # complete heterogeneous program tuple emits one enormous machine function
    # for long programs without improving execution code.
    Base.@nospecialize stages
    for prior in (index - 1):-1:1
        _stage_publishes_field(stages[prior], field) && return prior
    end
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _field_dependency(
        bound::_BoundLaw, index::Int, field::Field, slot;
        require_total::Bool = false, control::Symbol = :access,
    )
    Base.@nospecialize bound field slot
    prior = _nearest_preceding_publication(bound.law.stages, index, field)
    if require_total
        prior === nothing && throw(LocalMathValidationError(
            "a Field-derived Control requires a preceding total Field publication";
            stage = :plan, contract = :control_field_producer,
            expected = :preceding_total_publication,
            actual = (control = control, field = semantic_identity(field)),
        ))
        _stage_publishes_field(bound.law.stages[prior], field; total = true) ||
            throw(LocalMathValidationError(
                "a Field-derived Control requires its nearest preceding Field publication to be total";
                stage = :plan, contract = :control_field_totality,
                expected = :total_publication,
                actual = (control = control, stage = prior),
            ))
    end
    return prior === nothing ?
        _ExternalFieldDependency(slot, semantic_identity(field)) :
        _PrecedingFieldDependency(slot, semantic_identity(field), prior)
end

_control_field_dependency(:: _NoPrefix, projection, bound, index) = nothing
_control_field_dependency(:: _ParameterPrefix, projection, bound, index) = nothing
_control_field_dependency(:: _CollectionCount, projection, bound, index) = nothing
function _control_field_dependency(
        control::_FieldPrefix, projection, bound::_BoundLaw, index::Int,
    )
    return _field_dependency(
        bound, index, control.field, projection.control.prefix;
        require_total = true, control = :field_prefix,
    )
end

function _stage_collect_publication(stage::Stage, collection::Collection)
    for publication in stage.publications
        publication.law isa Collect || continue
        component = only(publication.components)
        semantic_identity(component.collection) == semantic_identity(collection) ||
            continue
        component.collection == collection || throw(LocalMathValidationError(
            "a Collection identity has conflicting schemas across Stages";
            stage = :plan, contract = :collection_dependency_schema,
            expected = collection, actual = component.collection))
        return publication
    end
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _nearest_preceding_collection_publication(
        stages::Tuple, index::Int, collection::Collection)
    Base.@nospecialize stages
    for prior in (index - 1):-1:1
        publication = _stage_collect_publication(stages[prior], collection)
        publication === nothing || return prior, publication
    end
    return nothing
end

function _validate_collection_access_law(
        access::CollectionAccess, publication::Publication, source::Space)
    producer_law = publication.law
    if access.law isa _BoundedGroup
        _is_grouped(producer_law.groups) || throw(LocalMathValidationError(
            "a bounded-group Collection access requires a densely grouped producer";
            stage = :plan, contract = :collection_grouping,
            expected = :group_by, actual = typeof(producer_law.groups)))
        Int(producer_law.groups.count) == length(source) || throw(
            LocalMathValidationError(
                "a bounded-group Collection access maps Stage items to exact dense group keys";
                stage = :plan, contract = :collection_group_domain,
                expected = length(source), actual = Int(producer_law.groups.count)))
    else
        producer_law.projection isa _PersistentSourcePosition || throw(
            LocalMathValidationError(
                "a source-position Collection access requires producer-owned persistent projection";
                stage = :plan, contract = :collection_source_position_projection,
                expected = :persistent_source_position,
                actual = typeof(producer_law.projection)))
        lane = typeof(access.law).parameters[2]
        lane <= _publication_width(producer_law) || throw(
            LocalMathValidationError(
                "a source-position Collection access lane exceeds the producer emission width";
                stage = :plan, contract = :collection_source_position_lane,
                expected = 1:_publication_width(producer_law), actual = lane))
    end
    return nothing
end

function _resolve_collection_access_law(
        bound::_BoundLaw, access::CollectionAccess,
        dependency::_PrecedingCollectionDependency)
    access.law isa _SourcePositionsAccess || return access.law
    publication = _stage_collect_publication(
        bound.law.stages[dependency.stage], access.collection)
    publication === nothing && error("validated Collection producer is missing")
    width = _publication_width(publication.law)
    lane = typeof(access.law).parameters[2]
    return _SourcePositionsAccess{width,lane}()
end

function _resolve_collection_access_projections(
        bound::_BoundLaw, stage::Stage, projection::_StageProjection,
        dependencies)
    projected = Any[]
    sizehint!(projected, length(projection.accesses))
    for index in eachindex(projection.accesses)
        use = projection.accesses[index]
        access = values(stage.accesses)[index]
        if access isa CollectionAccess
            law = _resolve_collection_access_law(
                bound, access, values(dependencies.accesses)[index])
            use = _ProjectedCollectionAccess(use.slot, law)
        end
        push!(projected, use)
    end
    return _StageProjection(projection.layout, Tuple(projected),
        projection.publications, projection.control, projection.parameters)
end

Base.@nospecializeinfer Base.@noinline function _collection_dependency(bound::_BoundLaw, index::Int,
        collection::Collection, slot, role::Symbol; access = nothing)
    Base.@nospecialize bound collection slot access
    found = _nearest_preceding_collection_publication(
        bound.law.stages, index, collection)
    found === nothing && throw(LocalMathValidationError(
        "a Collection consumer requires a preceding Collect publication in the same LocalLaw";
        stage = :plan, contract = :collection_producer,
        expected = :preceding_collect, actual = semantic_identity(collection)))
    prior, publication = found
    access === nothing || _validate_collection_access_law(
        access, publication, bound.law.stages[index].source)
    return _PrecedingCollectionDependency(
        slot, semantic_identity(collection), prior, role)
end
_control_field_dependency(:: _NoGate, projection, bound, index) = nothing
_control_field_dependency(:: _ParameterGate, projection, bound, index) = nothing
function _control_field_dependency(
        control::_FieldGate, projection, bound::_BoundLaw, index::Int,
    )
    return _field_dependency(
        bound, index, control.field, projection.control.gate;
        require_total = true, control = :field_gate,
    )
end
_control_mask_dependency(:: _NoMask, projection, bound, index) = nothing
function _control_mask_dependency(
        control::_MaskSelection, projection, bound::_BoundLaw, index::Int,
    )
    return _field_dependency(
        bound, index, control.field, projection.control.mask;
        control = :mask,
    )
end
_control_subset_use(:: _NoSubset, projection) = nothing
function _control_subset_use(control::_SubsetSelection, projection)
    return _RelationUse(
        projection.control.subset.relation, semantic_identity(control.relation),
    )
end

Base.@nospecializeinfer Base.@noinline function _stage_field_dependencies(
        bound::_BoundLaw, index::Int, projection,
    )
    Base.@nospecialize bound projection
    cold_bound = Base.inferencebarrier(bound)::_BoundLaw
    cold_projection = Base.inferencebarrier(projection)
    stage = Base.inferencebarrier(cold_bound.law.stages[index])::Stage
    names = keys(stage.accesses)
    # This is cold evidence construction.  A generator closure captures the
    # concrete heterogeneous program and silently recreates whole-program LLVM
    # specialization even behind the planning function barrier.  Accumulate
    # erased host values, then seal the exact NamedTuple schema at the boundary.
    access_values = Any[]
    sizehint!(access_values, length(names))
    for (position, name) in enumerate(names)
        access = getproperty(stage.accesses, name)
        projected = cold_projection.accesses[position]
        dependency = access isa Access ? _field_dependency(
            cold_bound, index, access.field, projected.target,
        ) : _collection_dependency(
            cold_bound, index, access.collection, projected.slot, :access;
            access,
        )
        push!(access_values, dependency)
    end
    accesses = NamedTuple{names}(Tuple(access_values))
    control = stage.control
    dependencies = (
        accesses,
        collection_prefix = control.prefix isa _CollectionCount ?
            _collection_dependency(cold_bound, index, control.prefix.collection,
                cold_projection.control.prefix, :prefix) : nothing,
        control = (
            prefix = _control_field_dependency(
                control.prefix, cold_projection, cold_bound, index,
            ),
            mask = _control_mask_dependency(control.mask, cold_projection, cold_bound, index),
            subset = _control_subset_use(control.subset, cold_projection),
            gate = _control_field_dependency(control.gate, cold_projection, cold_bound, index),
        ),
    )
    fold_values = Any[]
    for publication in stage.publications
        publication.law isa OrderedFold && push!(fold_values, publication)
    end
    folds = Tuple(fold_values)
    isempty(folds) && return dependencies
    law = only(folds).law
    names = keys(law.state.components)
    state_values = Any[]
    sizehint!(state_values, length(names))
    for component in values(law.state.components)
        target = _field_dependency(
            cold_bound, index, component.target,
            _local_field_slot(cold_projection.layout, component.target);
            control = :fold_target,
        )
        source = component.source isa _FoldInPlace ? nothing :
            _field_dependency(
                cold_bound, index, component.source,
                _local_field_slot(cold_projection.layout, component.source);
                control = :fold_source,
            )
        push!(state_values, (; target, source))
    end
    state = NamedTuple{names}(Tuple(state_values))
    return merge(dependencies, (state = state,))
end

Base.@nospecializeinfer Base.@noinline function _stage_planning_entry(
        bound::_BoundLaw, index::Int)
    # Planning resolves semantic identities in cold host data.  Its result is
    # still a concrete typed projection, but compiling this search against the
    # complete structural-binding tuple once per Stage makes the cost depend on
    # the Cartesian size of program × binding.  Keep that search deliberately
    # unspecialized; execution specialization begins from the returned value.
    Base.@nospecialize bound
    cold_bound = Base.inferencebarrier(bound)::_BoundLaw
    semantic = Base.inferencebarrier(cold_bound.law.stages[index])::Stage
    projection = Base.inferencebarrier(
        _stage_slot_projection(cold_bound, semantic))
    dependencies = Base.inferencebarrier(
        _stage_field_dependencies(cold_bound, index, projection))
    projection = Base.inferencebarrier(_resolve_collection_access_projections(
        cold_bound, semantic, projection, dependencies))
    return (; projection, dependencies)
end

function _validate_bound_backend(bound::_BoundLaw, backend)
    foreach(entry -> _validate_binding_backend(entry, backend, :field),
        bound.binding.fields)
    foreach(entry -> _validate_binding_backend(entry, backend, :relation),
        bound.binding.relations)
    foreach(entry -> _validate_binding_backend(entry, backend, :collection),
        bound.binding.collections)
    return nothing
end
