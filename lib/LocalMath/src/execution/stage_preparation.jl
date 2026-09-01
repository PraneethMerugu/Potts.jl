# The one bridge from a cold Stage projection to the descriptor-free warm ABI.

struct _StageRead{F,R,V}
    fields::F
    relation::R
    item::Int32
    validation::V
end

# Effect admission is intentionally performed against a host-compilable
# surrogate signature.  Array storage can be nested below the package-owned
# bounded-read capability (rather than appearing as a top-level argument), so
# recursively replace backend arrays only through the exact LocalMath
# execution wrappers that may contain them.  This proves the evaluator's
# scalar/load-only law without asking GPUArrays to lower host scalar indexing;
# the real prepared value and the warm kernel remain unchanged.
const _StageSurrogateContainer = Union{
    _PreparedRelationUse,
    _IdentityRelationView,
    _IndexRelationView,
    _FieldIndexRelationView,
    _GhostRelationBoundary,
    _MaskedRelationBoundary,
    _AffineRelationView,
    _FixedDegreeRelationView,
    _ProductRelationView,
    _ComposedRelationView,
    _PrefixInjectionRelationView,
    _IndexInjectionRelationView,
    _SelectedRelationView,
    _SourceMaskRelationView,
    _PackedIncidenceRelationView,
    _InverseRelationView,
    _GroupedInverseRelationView,
    _RuntimeKeyRelationView,
}

function _stage_surrogate_container_type(::Type{T}) where {T}
    concrete = Base.unwrap_unionall(T)
    parameters = map(concrete.parameters) do parameter
        parameter isa Type ? _pointwise_surrogate_type(parameter) : parameter
    end
    return Core.apply_type(Base.typename(concrete).wrapper, parameters...)
end

_pointwise_surrogate_type(::Type{T}) where {T<:_StageSurrogateContainer} =
    _stage_surrogate_container_type(T)
function _pointwise_surrogate_type(::Type{_StageRead{F,R,V}}) where {F,R,V}
    return _StageRead{
        _pointwise_surrogate_type(F),
        _pointwise_surrogate_type(R),
        V,
    }
end
function _pointwise_surrogate_type(
        ::Type{BoundedGroupView{K,T,R,V}}
    ) where {K,T,R,V}
    return BoundedGroupView{K,T,_pointwise_surrogate_type(R),V}
end

function Base.getproperty(::_StageRead, name::Symbol)
    throw(LocalMathValidationError(
        "Stage reads expose only bounded gather operations";
        stage = :plan, contract = :stage_access_protocol,
        expected = (:length, :getindex, :iterate), actual = name,
    ))
end
@inline Base.length(read::_StageRead) =
    Int(_relation_degree_bound(getfield(read, :relation)))

struct _StageSample{T}
    value::Union{Nothing,T}
    present::Bool
    exterior::Bool
    endpoint::Int32
end
@inline _stage_endpoint_field(fields::Tuple, ::_RelationEndpoint{S}) where {S<:_PreparedFieldSlot} = _prepared_stage_field(fields, S())
@inline function _stage_read_sample(read::_StageRead, lane::Integer)
    fields = getfield(read, :fields)
    endpoint = _relation_endpoint(
        getfield(read, :relation), fields, getfield(read, :item), lane)
    field = _stage_endpoint_field(fields, endpoint)
    ordinal = endpoint.present ? Int32(endpoint.index) : Int32(0)
    T = eltype(field)
    return endpoint.present ?
        _StageSample{T}(@inbounds(field[endpoint.index]), true,
            endpoint.exterior, ordinal) :
        _StageSample{T}(nothing, false, endpoint.exterior, Int32(0))
end
@inline Base.getindex(read::_StageRead, lane::Integer) = _stage_read_sample(read, lane)
@inline Base.iterate(read::_StageRead, lane::Int = 1) =
    lane > length(read) ? nothing : (read[lane], lane + 1)

# Required authored reads are admitted as a stronger scientific promise than
# sample-aware reads. This direct load keeps the warm ABI concrete; optional
# topology must use the `_StageSample` protocol instead.
@inline function _stage_read_required(read::_StageRead, lane::Integer)
    fields = getfield(read, :fields)
    endpoint = _relation_endpoint(
        getfield(read, :relation), fields, getfield(read, :item), lane)
    field = _stage_endpoint_field(fields, endpoint)
    # Preserve the ordinary Julia bounds failure on a missing required lane.
    # Optional topology instead uses `_StageSample` and never enters this path.
    index = endpoint.present ? endpoint.index : Int32(length(field) + 1)
    return field[index]
end

const _STAGE_ACCESS_FORBIDDEN_GLOBALS = (
    :fieldnames, :propertynames, :dump,
    :_relation_endpoint, :_prepared_stage_field, :_stage_read_sample,
)
const _STAGE_EXECUTION_MODULE = @__MODULE__

@inline function _stage_access_callee_name(callee)
    callee isa GlobalRef && return callee.name
    callee === Core.getfield && return :getfield
    callee === Base.getproperty && return :getproperty
    return nothing
end

function _stage_access_source_safe(value)
    value isa Expr || return true
    if value.head in (:call, :invoke) && !isempty(value.args)
        callee_index = value.head === :invoke ? 2 : 1
        callee = value.args[callee_index]
        name = _stage_access_callee_name(callee)
        callee isa GlobalRef && callee.mod === _STAGE_EXECUTION_MODULE &&
            name in _STAGE_ACCESS_FORBIDDEN_GLOBALS && return false
    end
    return all(_stage_access_source_safe, value.args)
end

_stage_evaluator_source_safe(value) =
    _pointwise_source_safe(value) && _stage_access_source_safe(value)

_stage_ir_type(type) = type
_stage_ir_type(value::Core.Const) = typeof(value.val)
function _stage_ir_operand_type(value, info)
    info isa Core.CodeInfo || return Any
    if value isa Core.Argument || value isa Core.SlotNumber
        index = Int(getfield(value, :n))
        return 1 <= index <= length(info.slottypes) ?
            _stage_ir_type(info.slottypes[index]) : Any
    elseif value isa Core.SSAValue
        index = Int(getfield(value, :id))
        return 1 <= index <= length(info.ssavaluetypes) ?
            _stage_ir_type(info.ssavaluetypes[index]) : Any
    end
    return typeof(value)
end

function _stage_execution_capability_type(type)
    type isa Type || return false
    return typeintersect(
        type, Union{
            _StageRead,_PreparedRelationUse,_AdmittedStage,_PreparedFoldRead,
            BoundedGroupView,
        }
    ) !== Union{}
end

function _stage_access_typed_safe(value, info)
    value isa Expr && value.head in (:call, :invoke) || return true
    callee_index = value.head === :invoke ? 2 : 1
    length(value.args) > callee_index || return true
    callee = value.args[callee_index]
    name = _stage_access_callee_name(callee)
    # Explicit package-owned `getfield` calls are the implementation of the
    # bounded read protocol after inlining. User code resolves the builtin in
    # its own module and remains subject to the capability-type rejection
    # below, so this does not expose `_StageRead` or prepared relation state.
    callee isa GlobalRef && callee.mod === _STAGE_EXECUTION_MODULE &&
        name === :getfield && return true
    receiver = value.args[callee_index + 1]
    receiver_type = _stage_ir_operand_type(receiver, info)
    if name in (:getfield, :getproperty, :propertynames, :dump) &&
            _stage_execution_capability_type(receiver_type)
        return false
    end
    if callee isa GlobalRef && callee.mod === _STAGE_EXECUTION_MODULE &&
            name in _STAGE_ACCESS_FORBIDDEN_GLOBALS
        return false
    end
    return true
end

function _package_owned_stage_read_protocol(read_type::Type)
    _storage_value_type(read_type) && return true
    signatures = (
        (Base.length, Tuple{read_type}),
        (Base.getindex, Tuple{read_type,Int}),
        (Base.getindex, Tuple{read_type,Int32}),
        (Base.iterate, Tuple{read_type}),
        (Base.iterate, Tuple{read_type,Int}),
    )
    return all(signatures) do (operation, signature)
        method = try
            which(operation, signature)
        catch
            return false
        end
        method.module === _STAGE_EXECUTION_MODULE
    end
end

function _validate_stage_read_methods(signature)
    reads = signature.parameters[2]
    reads <: Tuple || return false
    return all(_package_owned_stage_read_protocol, reads.parameters)
end

struct _PreparedStageAccess{R}; relation::R; end
struct _PreparedCollectionAccess{L,S}; law::L; storage::S; end
struct _PreparedStageComponent{R}; relation::R; end
struct _PreparedStageCollection{S}; storage::S; end
struct _PreparedFoldStateField{T,S}; target::T; source::S; end
struct _PreparedFoldState{C<:NamedTuple}; components::C; end
struct _PreparedFoldComponent{S}; state::S; end
"""Read-only typed Field view admitted as one Fold accumulator component."""
struct _PreparedFoldRead{T,S}
    storage::S
end
function Base.getproperty(::_PreparedFoldRead, name::Symbol)
    throw(LocalMathValidationError(
        "Fold accumulator components expose only bounded read operations";
        stage = :prepare, contract = :ordered_fold_accumulator_protocol,
        expected = (:length, :size, :axes, :getindex), actual = name,
    ))
end
Base.eltype(::Type{_PreparedFoldRead{T}}) where {T} = T
Base.length(view::_PreparedFoldRead) = length(getfield(view, :storage))
Base.size(view::_PreparedFoldRead) = size(getfield(view, :storage))
Base.axes(view::_PreparedFoldRead) = axes(getfield(view, :storage))
@inline Base.getindex(view::_PreparedFoldRead, indices...) =
    @inbounds getfield(view, :storage)[indices...]

struct _PreparedFoldAccumulatorView{Names,C<:NamedTuple}
    components::C
end
@generated function Base.getproperty(
        view::_PreparedFoldAccumulatorView{Names}, name::Symbol,
    ) where {Names}
    branches = map(eachindex(Names)) do index
        :(name === $(QuoteNode(Names[index])) && return getfield(
            getfield(view, :components), $index,
        ))
    end
    return quote
        name === :components && return getfield(view, :components)
        $(branches...)
        throw(ArgumentError("unknown prepared ordered-fold accumulator component $name"))
    end
end
struct _PreparedCollectLaw{T,K,G,O,P}
    groups::G
    order::O
    projection::P
end
struct _PreparedOrderedFoldLaw{T,F,O}
    transition::F
    order::O
end
_publication_value_type(::_PreparedCollectLaw{T}) where {T} = T
_publication_width(::_PreparedCollectLaw{T,K}) where {T,K} = K
_publication_value_type(::_PreparedOrderedFoldLaw{T}) where {T} = T
_publication_width(::_PreparedOrderedFoldLaw) = 1
struct _PreparedStagePublication{C,L}; components::C; law::L; end
struct _PreparedNoPrefix end
struct _PreparedParameterPrefix{S}; slot::S; end
struct _PreparedFieldPrefix{S<:_PreparedFieldSlot}; slot::S; end
struct _PreparedCollectionPrefix{S}; storage::S; end
struct _PreparedNoMask end
struct _PreparedMask{S<:_PreparedFieldSlot}; slot::S; end
struct _PreparedNoSubset end
struct _PreparedIdentitySubset{E}; extent::E; end
struct _PreparedMaskedSubset{B,S<:_PreparedFieldSlot}; base::B; mask::S; end
struct _PreparedNoGate end
struct _PreparedParameterGate{S}; slot::S; end
struct _PreparedFieldGate{S<:_PreparedFieldSlot}; slot::S; end
struct _PreparedStageControl{P,M,S,G}
    prefix::P; mask::M; subset::S; gate::G
end
Adapt.@adapt_structure _PreparedStageAccess
Adapt.@adapt_structure _PreparedCollectionAccess
Adapt.@adapt_structure _PreparedStageComponent
Adapt.@adapt_structure _PreparedStageCollection
Adapt.@adapt_structure _PreparedFoldStateField
Adapt.@adapt_structure _PreparedFoldState
Adapt.@adapt_structure _PreparedFoldComponent
Adapt.@adapt_structure _PreparedFoldRead
Adapt.@adapt_structure _PreparedFoldAccumulatorView
# The admitted transition and order are storage-free law values; adapting them
# would create a second semantic authority rather than adapting device state.
Adapt.adapt_structure(to, law::_PreparedOrderedFoldLaw) = law
Adapt.adapt_structure(to, law::_PreparedCollectLaw) = law
Adapt.adapt_structure(to, publication::_PreparedStagePublication) =
    _PreparedStagePublication(
        Adapt.adapt(to, publication.components), publication.law)
Adapt.@adapt_structure _PreparedMaskedSubset
Adapt.@adapt_structure _PreparedCollectionPrefix
Adapt.@adapt_structure _PreparedStageControl

"""Prepared structure before evaluator admission; it is not executable."""
struct _StageDraft{F,A,P,C,U}
    fields::F; accesses::A; parameter_slots::P; control::C; publications::U
    source_count::Int32
end

mutable struct _AdmittedStageSeal end
const _ADMITTED_STAGE_SEAL = _AdmittedStageSeal()
struct _PortProjector{E}; evaluator::E; end
@inline function (projector::_PortProjector)(item, reads, parameters)
    return values(projector.evaluator(item, reads, parameters))
end
"""The sole warm stage authority after exact evaluator admission."""
struct _AdmittedStage{E,F,A,P,C,U}
    evaluator::E; fields::F; accesses::A; parameter_slots::P
    control::C; publications::U; source_count::Int32
    function _AdmittedStage(seal::_AdmittedStageSeal, evaluator::E,
            draft::_StageDraft{F,A,P,C,U}) where {E,F,A,P,C,U}
        seal === _ADMITTED_STAGE_SEAL || throw(ArgumentError("admitted Stages require the package-owned admission seal"))
        return new{E,F,A,P,C,U}(evaluator, draft.fields, draft.accesses,
            draft.parameter_slots, draft.control, draft.publications, draft.source_count)
    end
end
"""Cold proof that exactly one admitted Stage specialization passed C2."""
struct _StageAdmission{B,T,S,R}
    backend::B
    stage::T
    signature::S
    result_type::R
end
struct _StageEvaluation{E,F,A,C}
    evaluator::E
    fields::F
    accesses::A
    control::C
    source_count::Int32
end
struct _QualifiedEvaluation{S,P}; stage::S; parameters::P; end
struct _StageRuntimeParameters{E,P,G}
    evaluator::E
    prefix::P
    gate::G
end
Adapt.adapt_structure(to, projector::_PortProjector) =
    _PortProjector(projector.evaluator)
function Adapt.adapt_structure(to, stage::_AdmittedStage)
    draft = _StageDraft(
        Adapt.adapt(to, stage.fields),
        Adapt.adapt(to, stage.accesses),
        stage.parameter_slots,
        Adapt.adapt(to, stage.control),
        Adapt.adapt(to, stage.publications),
        stage.source_count,
    )
    return _AdmittedStage(
        _ADMITTED_STAGE_SEAL, Adapt.adapt(to, stage.evaluator), draft)
end
Adapt.@adapt_structure _StageEvaluation
Adapt.@adapt_structure _QualifiedEvaluation
Adapt.@adapt_structure _StageRuntimeParameters

function _require_stage_storage_operation(
        backend, storage, operation::Symbol, role::Symbol,
    )
    leaves = _structural_physical_leaves(role, storage)
    all(leaves) do (_, leaf)
        return _centrally_qualified_stage_storage_value(
            backend, eltype(leaf), operation,
        ) || _centrally_qualified_stage_record(
            backend, eltype(leaf), operation,
        )
    end || throw(LocalMathValidationError(
        "the backend lacks a centrally reviewed Stage storage operation";
        stage = :prepare, contract = :stage_backend_capability,
        expected = (role = role, operation = operation, address_space = :global),
        actual = (backend = typeof(backend), leaves = map(
            pair -> (first(pair), eltype(last(pair))), leaves)),
    ))
    return nothing
end

function _require_stage_field_operation(
        backend, validated, field::Field, operation::Symbol, role::Symbol,
    )
    slot = _resolve_field_slot(validated, field)
    binding = _field_binding(validated, slot)
    _require_stage_storage_operation(backend, binding.storage, operation, role)
end

function _require_stage_relation_loads(backend, validated, relation::Relation)
    slot = _resolve_relation_slot(validated, relation)
    binding = _relation_binding(validated, slot)
    binding.storage === nothing || _require_stage_storage_operation(
        backend, binding.storage, :load, :relation)
    binding.generation === nothing || _require_stage_storage_operation(
        backend, binding.generation.generations, :load, :relation_generation)
    binding.status === nothing || _require_stage_storage_operation(
        backend, binding.status.statuses, :load, :relation_status)
    return nothing
end

function _require_prepared_stage_capabilities(
        backend, validated::_ValidatedStructuralBinding, stage::Stage)
    for access in values(stage.accesses)
        if access isa Access
            _require_stage_field_operation(
                backend, validated, access.field, :load, :access_field)
            access.ghost === nothing || _require_stage_field_operation(
                backend, validated, access.ghost, :load, :ghost_field)
        else
            slot = _resolve_collection_slot(validated, access.collection)
            _require_stage_storage_operation(backend,
                _collection_binding(validated, slot).storage, :load,
                :collection_access)
        end
    end
    control = stage.control
    control.prefix isa _FieldPrefix && _require_stage_field_operation(
        backend, validated, control.prefix.field, :load, :prefix_field)
    if control.prefix isa _CollectionCount
        slot = _resolve_collection_slot(validated, control.prefix.collection)
        _require_stage_storage_operation(backend,
            _collection_binding(validated, slot).storage, :load,
            :collection_prefix)
    end
    control.mask isa _MaskSelection && _require_stage_field_operation(
        backend, validated, control.mask.field, :load, :mask_field)
    control.gate isa _FieldGate && _require_stage_field_operation(
        backend, validated, control.gate.field, :load, :gate_field)
    _, relations, _ = _stage_descriptor_closure(stage)
    relation_fields, _ = _required_descriptor_closure((), relations)
    foreach(field -> _require_stage_field_operation(
        backend, validated, field, :load, :relation_policy_field),
        relation_fields)
    for publication in stage.publications
        for component in publication.components
            component isa FieldPublication || continue
            _require_stage_field_operation(
                backend, validated, component.field, :store, :publication_field)
            publication.law isa Reduce &&
                publication.law.seed isa ExistingSeed &&
                _require_stage_field_operation(
                    backend, validated, component.field, :load,
                    :reduce_existing_field)
        end
        if publication.law isa Collect
            component = only(publication.components)
            binding = _collection_binding(
                validated, _resolve_collection_slot(validated, component.collection),
            )
            _require_stage_storage_operation(
                backend, binding.storage, :store, :collection_storage,
            )
        elseif publication.law isa OrderedFold
            for state in values(publication.law.state.components)
                _require_stage_field_operation(
                    backend, validated, state.target, :load, :fold_state_target)
                _require_stage_field_operation(
                    backend, validated, state.target, :store, :fold_state_target)
                state.source isa Field && _require_stage_field_operation(
                    backend, validated, state.source, :load, :fold_state_source)
            end
        end
    end
    foreach(relation -> _require_stage_relation_loads(
        backend, validated, relation), relations)
    return nothing
end

_require_prepared_stage_capabilities(backend, bound::_BoundLaw, stage::Stage) =
    _require_prepared_stage_capabilities(backend, bound.binding, stage)

_materialize_stage_fields(validated, ::Tuple{}) = ()
function _materialize_stage_fields(validated, slots::Tuple)
    return (_validated_field_binding(validated, first(slots)).storage,
        _materialize_stage_fields(validated, Base.tail(slots))...)
end
_materialize_stage_fields(
    validated::_ValidatedStructuralBinding, layout::_StageFieldLayout) =
    _materialize_stage_fields(validated, layout.fields)

function _projected_relation_view(validated::_ValidatedStructuralBinding,
        layout::_StageFieldLayout, use::_ProjectedRelationUse)
    use.target isa _PreparedFieldSlot || throw(LocalMathValidationError(
        "a Field-valued relation use requires a planned local target";
        stage = :prepare, contract = :stage_relation_target))
    binding = _relation_binding(validated, use.relation)
    proof = _relation_proof(validated, use.relation)
    view = _prepare_relation_view(validated, binding, proof, use.target,
        use.ghost isa _NoPreparedGhost ? nothing : use.ghost,
        field -> _local_field_slot(layout, field),
        relation -> _planned_relation_slot(layout, relation))
    return _PreparedRelationUse(view, binding.generation, binding.status)
end

_prepare_stage_access(validated, layout, use::_ProjectedRelationUse) =
    _PreparedStageAccess(_projected_relation_view(validated, layout, use))
_prepare_stage_access(validated, layout, use::_ProjectedCollectionAccess) =
    _PreparedCollectionAccess(use.law,
        _collection_binding(validated, use.slot).storage)

_prepare_stage_accesses(validated, layout, ::Tuple{}) = ()
function _prepare_stage_accesses(validated, layout, uses::Tuple)
    return (_prepare_stage_access(validated, layout, first(uses)),
        _prepare_stage_accesses(validated, layout, Base.tail(uses))...)
end
_prepare_stage_accesses(validated, projection::_StageProjection) =
    _prepare_stage_accesses(validated, projection.layout, projection.accesses)

function _prepare_collect_storage(
        validated::_ValidatedStructuralBinding, stage::Stage,
        component::CollectionPublication, use::_ProjectedCollectionUse,
        law::Collect,
    )
    binding = _collection_binding(validated, use.slot)
    binding.collection == component.collection || throw(LocalMathValidationError(
        "Collection projection resolves a conflicting semantic descriptor";
        stage = :prepare, contract = :collection_projection_schema,
        expected = component.collection, actual = binding.collection,
    ))
    storage = binding.storage
    capacity = Int(component.collection.capacity)
    try
        _validate_compacted_record_storage(
            storage.records, _publication_value_type(law), capacity,
        )
        eltype(storage.count) === Int32 && size(storage.count) == (1,) ||
            throw(ArgumentError("count"))
        grouped = _is_grouped(law.groups)
        if grouped
            expected = Int(_compacted_group_count(law.groups)) + 1
            storage.segment_starts !== nothing &&
                eltype(storage.segment_starts) === Int32 &&
                size(storage.segment_starts) == (expected,) ||
                throw(ArgumentError("group directory"))
        else
            storage.segment_starts === nothing || throw(ArgumentError(
                "one-group directory",
            ))
        end
        expected_projection = law.projection isa _PersistentSourcePosition ?
            length(stage.source) * _publication_width(law) : nothing
        if expected_projection === nothing
            storage.source_position === nothing || throw(ArgumentError(
                "unrequested source position",
            ))
        else
            storage.source_position !== nothing &&
                eltype(storage.source_position) === Int32 &&
                size(storage.source_position) == (expected_projection,) ||
                throw(ArgumentError("source position"))
        end
        all(provenance -> eltype(provenance) === Int32 &&
            size(provenance) == (capacity,),
            (storage.source_item, storage.source_lane)) ||
            throw(ArgumentError("provenance"))
    catch error
        throw(LocalMathValidationError(
            "Collection storage does not exactly realize its Collect law";
            stage = :prepare, contract = :collect_storage_schema,
            expected = (
                value_type = _publication_value_type(law), capacity = capacity,
                groups = law.groups, projection = law.projection,
            ), actual = sprint(showerror, error),
        ))
    end
    return _PreparedStageCollection(storage)
end

function _prepare_fold_state(
        projected::_ProjectedFoldState, law::OrderedFold,
    )
    names = keys(projected.components)
    components = NamedTuple{names}(Tuple(
        _PreparedFoldStateField(
            value.target,
            value.source === nothing ? value.target : value.source,
        ) for value in values(projected.components)
    ))
    return _PreparedFoldState(components)
end

@inline _prepared_fold_read(storage::S) where {S} =
    _PreparedFoldRead{eltype(storage),S}(storage)

@generated function _prepared_fold_accumulator(
        fields::F, state::_PreparedFoldState{C},
    ) where {F<:Tuple,C<:NamedTuple}
    names = C.parameters[1]
    views = map(eachindex(names)) do index
        quote
            component = getfield(getfield(state, :components), $index)
            _prepared_fold_read(_prepared_stage_field(fields,
                getfield(component, :target)))
        end
    end
    components = :(NamedTuple{$names}(($(views...),)))
    return quote
        prepared_components = $components
        _PreparedFoldAccumulatorView{
            $names, typeof(prepared_components),
        }(prepared_components)
    end
end

@generated function _prepared_fold_accumulator(state::C) where {C<:NamedTuple}
    names = C.parameters[1]
    views = map(eachindex(names)) do index
        :(_prepared_fold_read(getfield(state, $index)))
    end
    components = :(NamedTuple{$names}(($(views...),)))
    return quote
        prepared_components = $components
        _PreparedFoldAccumulatorView{
            $names, typeof(prepared_components),
        }(prepared_components)
    end
end

_stage_reads_type(fields::Tuple, accesses::Tuple) = Core.apply_type(
    Tuple, map(access -> _stage_read_type(fields, access), accesses)...,
)

function _validate_prepared_fold_transition(
        backend, law::OrderedFold{T}, state::_PreparedFoldState,
        fields::Tuple, accesses::Tuple, analysis_cache::Dict{Any,Any},
    ) where {T}
    accumulator = _prepared_fold_accumulator(fields, state)
    signature = Tuple{
        typeof(accumulator), T, Int32, _stage_reads_type(fields, accesses),
    }
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_ordered_fold_transition, law.transition, signature,
        method_signature -> length(method_signature) == 5)
    analysis.qualified || throw(LocalMathValidationError(
        "the selected backend cannot prove OrderedFold transition effects";
        stage = :prepare, contract = :ordered_fold_transition_effects,
        expected = :closed_storage_free_load_only_callable,
        actual = (purpose = :ordered_fold_transition,
            callable_type = typeof(law.transition), signature,
            selected_method = analysis.method,
            return_type = analysis.return_type,
            reason = analysis.reason, operation = analysis.operation),
        hint = analysis.hint,
    ))
    names = keys(state.components)
    value_types = Tuple(eltype(_prepared_stage_field(fields, component.target))
        for component in values(state.components))
    _validate_ordered_fold_step_type(
        analysis.return_type, names, value_types;
        stage = :prepare, prefix = :ordered_fold,
    )
    return nothing
end

function _prepare_stage_order(backend, order, ::Type{T}, prefix::Symbol,
        analysis_cache::Dict{Any,Any};
        require_integer_identity::Bool = false,
    ) where {T}
    token, key_type, identity_type = _ordering_token(
        order, T;
        key_purpose = "$(prefix) canonical key",
        identity_purpose = "$(prefix) semantic identity",
        effects_contract = Symbol(prefix, :_extractor_effects),
        extractor_contract = Symbol(prefix, :_order_extractor),
        type_contract = Symbol(prefix, :_order_key_type),
        allow_callables = true,
        analysis_cache,
    )
    token isa _CanonicalBy || return token
    _centrally_qualified_rank_type(backend, key_type) &&
        _centrally_qualified_rank_type(backend, identity_type) || throw(
            LocalMathValidationError(
                "$(prefix) ordering types lack centrally reviewed comparison operations";
                stage = :prepare, contract = Symbol(prefix, :_order_key_type),
                expected = :qualified_rank, actual = (key_type, identity_type),
            ))
    !require_integer_identity || identity_type in (Int32, UInt32) || throw(
        LocalMathValidationError(
            "$(prefix) semantic identity must be one exact integer";
            stage = :prepare, contract = Symbol(prefix, :_identity_type),
            expected = (Int32, UInt32), actual = identity_type,
        ))
    return _PreparedCanonicalBy{key_type,identity_type,
        typeof(token.key),typeof(token.identity)}(token.key, token.identity)
end

function _prepare_collect_groups(
        backend, groups::_OneGroup, ::Type, analysis_cache)
    return groups
end
function _prepare_collect_groups(
        backend, groups::_RoutedGroups, ::Type, analysis_cache)
    return groups
end
function _prepare_collect_groups(backend, groups::_GroupBy, ::Type{T},
        analysis_cache::Dict{Any,Any}) where {T}
    token, result_type = _ordering_extractor_type(
        groups.extractor, T, "Collect group extractor";
        effects_contract = :collect_extractor_effects,
        extractor_contract = :collect_group_extractor,
        type_contract = :collect_group_key_type,
        allow_callables = true,
        analysis_cache,
    )
    result_type === Int32 || throw(LocalMathValidationError(
        "Collect dense group keys must be exactly Int32";
        stage = :prepare, contract = :collect_group_key_type,
        expected = Int32, actual = result_type,
    ))
    return _GroupBy(token, groups.count)
end

function _prepared_collect_law(backend, law::Collect{T,K},
        analysis_cache::Dict{Any,Any}) where {T,K}
    groups = _prepare_collect_groups(backend, law.groups, T, analysis_cache)
    order = _prepare_stage_order(
        backend, law.order, T, :collect, analysis_cache)
    return _PreparedCollectLaw{T,K,typeof(groups),typeof(order),typeof(law.projection)}(
        groups, order, law.projection,
    )
end

function _prepared_fold_law(backend, law::OrderedFold{T},
        analysis_cache::Dict{Any,Any}) where {T}
    order = _prepare_stage_order(
        backend, law.order, T, :ordered_fold, analysis_cache;
        require_integer_identity = true,
    )
    _PreparedOrderedFoldLaw{T,typeof(law.transition),typeof(order)}(
        law.transition, order,
    )
end

function _prepare_stage_publication(
        validated::_ValidatedStructuralBinding, projection::_StageProjection,
        stage::Stage, publication::Publication, uses::Tuple, fields::Tuple,
        accesses::Tuple, backend, analysis_cache::Dict{Any,Any},
    )
    law = publication.law
    if law isa Collect
        component = only(publication.components)
        use = only(uses)
        use isa _ProjectedCollectionUse || throw(LocalMathValidationError(
            "Collect requires a positional Collection projection";
            stage = :prepare, contract = :collect_projection,
        ))
        return _PreparedStagePublication(
            (_prepare_collect_storage(validated, stage, component, use, law),),
            _prepared_collect_law(backend, law, analysis_cache),
        )
    elseif law isa OrderedFold
        projected = only(uses)
        projected isa _ProjectedFoldState || throw(LocalMathValidationError(
            "OrderedFold requires projected Field state";
            stage = :prepare, contract = :ordered_fold_projection,
        ))
        state = _prepare_fold_state(projected, law)
        _validate_prepared_fold_transition(
            backend, law, state, fields, accesses, analysis_cache,
        )
        return _PreparedStagePublication(
            (_PreparedFoldComponent(state),),
            _prepared_fold_law(backend, law, analysis_cache),
        )
    end
    return _PreparedStagePublication(
        _prepare_stage_components(validated, projection.layout, uses), law,
    )
end

_prepare_stage_components(validated, layout, ::Tuple{}) = ()
function _prepare_stage_components(validated, layout, uses::Tuple)
    return (_PreparedStageComponent(_projected_relation_view(
            validated, layout, first(uses))),
        _prepare_stage_components(validated, layout, Base.tail(uses))...)
end

_prepare_stage_publications(validated, projection, stage, ::Tuple{}, ::Tuple{},
    fields, accesses, backend, analysis_cache) = ()
function _prepare_stage_publications(validated, projection, stage,
        publications::Tuple, projected::Tuple, fields, accesses, backend,
        analysis_cache)
    return (_prepare_stage_publication(validated, projection, stage,
            first(publications), first(projected), fields, accesses, backend,
            analysis_cache),
        _prepare_stage_publications(validated, projection, stage,
            Base.tail(publications), Base.tail(projected), fields, accesses,
            backend, analysis_cache)...)
end
_prepare_stage_publications(validated, projection::_StageProjection,
        stage::Stage, fields::Tuple, accesses::Tuple, backend,
        analysis_cache) =
    _prepare_stage_publications(validated, projection, stage,
        stage.publications, projection.publications, fields, accesses, backend,
        analysis_cache)


_validate_stage_publication_operation(backend, publication::Publication{C,<:Unique}) where {C} =
    nothing

_validate_stage_publication_operation(
        backend, publication::Publication{C,<:Collect},
    ) where {C} = nothing

_validate_stage_publication_operation(
        backend, publication::Publication{C,<:OrderedFold},
    ) where {C} = nothing

function _reduce_atomic_operation(operation, ::Type{T}) where {T}
    operation === (+) && return :add
    T in (Int32, UInt32) && operation === min && return :min
    T in (Int32, UInt32) && operation === max && return :max
    return nothing
end

_reduce_operation_identity(::Type{T}, ::Val{:add}) where {T} = zero(T)
_reduce_operation_identity(::Type{T}, ::Val{:min}) where {T} = typemax(T)
_reduce_operation_identity(::Type{T}, ::Val{:max}) where {T} = typemin(T)

function _validate_stage_publication_operation(
        backend, publication::Publication{C,<:Reduce{T}},
        analysis_cache = nothing,
    ) where {C,T}
    law = publication.law
    signature = Tuple{T,T}
    analysis = analysis_cache === nothing ? _closed_callable_effect_analysis(
        law.operation, signature,
        method_signature -> length(method_signature) == 3) :
        _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_stage_reduce, law.operation, signature,
            method_signature -> length(method_signature) == 3)
    analysis.qualified && analysis.return_type === T || throw(
        LocalMathValidationError(
            "Reduce operation fails its exact closed typed-IR contract";
            stage = :plan, contract = :reduce_operation_effects,
            expected = (signature = signature, return_type = T),
            actual = (purpose = :reduce_operation,
                callable_type = typeof(law.operation),
                selected_method = analysis.method,
                signature, qualified = analysis.qualified,
                return_type = analysis.return_type,
                reason = analysis.reason, operation = analysis.operation),
            hint = analysis.hint,
        )
    )
    if law.order isa RelaxedAtomic
        operation = _reduce_atomic_operation(law.operation, T)
        operation === nothing && throw(LocalMathValidationError(
            "the relaxed Reduce operation is outside the package-owned atomic catalog";
            stage = :plan, contract = :reduce_relaxed_operation,
            expected = (:add, :min, :max), actual = typeof(law.operation),
        ))
        law.seed isa IdentitySeed || throw(LocalMathValidationError(
            "relaxed atomic Reduce requires an identity seed";
            stage = :plan, contract = :reduce_relaxed_seed,
            expected = IdentitySeed, actual = typeof(law.seed),
        ))
        expected_identity = _reduce_operation_identity(T, Val(operation))
        law.seed.value === expected_identity || throw(
            LocalMathValidationError(
                "relaxed atomic Reduce seed does not match its curated identity";
                stage = :plan, contract = :reduce_relaxed_identity,
                expected = expected_identity, actual = law.seed.value,
            )
        )
        _centrally_qualified_atomic_capability(
            backend, T, operation, :global) || throw(
                LocalMathValidationError(
                    "the backend lacks the requested relaxed atomic Reduce operation";
                    stage = :plan, contract = :reduce_relaxed_capability,
                    expected = (T, operation, :global),
                    actual = typeof(backend),
                )
            )
    end
    return nothing
end
function _validate_stage_publication_operation(
        backend, publication::Publication{C,<:Resolve{R,I,T}},
    ) where {C,R,I,T}
    _centrally_qualified_rank_type(backend, R) || throw(
        LocalMathValidationError(
            "Resolve rank type lacks centrally reviewed backend operations";
            stage = :plan, contract = :resolve_rank_capability,
            expected = (R, :global_load_store), actual = typeof(backend),
        )
    )
    I === _CanonicalOrdinal || _centrally_qualified_rank_type(backend, I) ||
        throw(LocalMathValidationError(
            "Resolve tie type lacks centrally reviewed backend operations";
            stage = :plan, contract = :resolve_tie_capability,
            expected = (I, :global_load_store), actual = typeof(backend),
        ))
    return nothing
end

_validate_stage_publication_operation(backend, publication, analysis_cache) =
    _validate_stage_publication_operation(backend, publication)

function _validate_stage_publication_operations(
        backend, publications::Tuple, analysis_cache)
    foreach(publication -> _validate_stage_publication_operation(
        backend, publication, analysis_cache), publications)
    return nothing
end

_prepare_stage_subset(relation::Relation{_IdentityRelation}, layout) =
    _PreparedIdentitySubset(size(domain(relation)))
function _prepare_stage_subset(relation::Relation{<:_MaskedRelation}, layout)
    representation = relation.representation
    _PreparedMaskedSubset(_prepare_stage_subset(representation.base, layout),
        _local_field_slot(layout, representation.mask))
end
@inline _subset_participates(view::_PreparedIdentitySubset, fields::Tuple, item::Integer) =
    1 <= item <= _relation_count(view.extent)
@inline function _subset_participates(view::_PreparedMaskedSubset, fields::Tuple, item::Integer)
    _subset_participates(view.base, fields, item) && @inbounds(_prepared_stage_field(fields, view.mask)[item])
end

function _prepare_stage_control(validated::_ValidatedStructuralBinding,
        projection::_StageProjection, stage::Stage)
    control, projected = stage.control, projection.control
    prefix = control.prefix isa _NoPrefix ? _PreparedNoPrefix() :
        control.prefix isa _ParameterPrefix ? _PreparedParameterPrefix(projection.parameters.prefix) :
        control.prefix isa _FieldPrefix ? _PreparedFieldPrefix(projected.prefix) :
        _PreparedCollectionPrefix(
            _collection_binding(validated, projected.prefix).storage)
    mask = control.mask isa _NoMask ? _PreparedNoMask() : _PreparedMask(projected.mask)
    subset = control.subset isa _NoSubset ? _PreparedNoSubset() :
        _prepare_stage_subset(control.subset.relation, projection.layout)
    gate = control.gate isa _NoGate ? _PreparedNoGate() :
        control.gate isa _ParameterGate ? _PreparedParameterGate(projection.parameters.gate) :
        _PreparedFieldGate(projected.gate)
    _PreparedStageControl(prefix, mask, subset, gate)
end

Base.@nospecializeinfer Base.@noinline function _stage_draft_from_projection(
        validated::_ValidatedStructuralBinding, stage::Stage,
        projection::_StageProjection; backend,
        analysis_cache::Dict{Any,Any})
    Base.@nospecialize validated stage projection
    cold_binding = Base.inferencebarrier(validated)::_ValidatedStructuralBinding
    semantic = Base.inferencebarrier(stage)::Stage
    projected = Base.inferencebarrier(projection)::_StageProjection
    _require_prepared_stage_capabilities(backend, cold_binding, semantic)
    fields = _materialize_stage_fields(cold_binding, projected.layout)
    accesses = _prepare_stage_accesses(cold_binding, projected)
    return _StageDraft(fields, accesses, projected.parameters.evaluator,
        _prepare_stage_control(cold_binding, projected, semantic),
        _prepare_stage_publications(cold_binding, projected, semantic,
            fields, accesses, backend, analysis_cache),
        _checked_relation_view_int32(length(semantic.source),
            :prepared_stage_source_count))
end


_stage_read_type(fields::Tuple, access::_PreparedStageAccess) =
    Core.apply_type(_StageRead, typeof(fields), typeof(access.relation),
        _NoEvaluationValidation)
function _stage_read_type(fields::Tuple,
        access::_PreparedCollectionAccess{<:_BoundedGroup{K}}) where {K}
    records = access.storage.records
    return Core.apply_type(BoundedGroupView, K, eltype(records), typeof(records),
        _NoEvaluationValidation)
end
_stage_read_type(fields::Tuple,
    access::_PreparedCollectionAccess{<:_SourcePositionsAccess}) = Int32
function _stage_draft_signature(draft::_StageDraft, semantic::Stage)
    reads = Core.apply_type(Tuple, map(access -> _stage_read_type(draft.fields, access), draft.accesses)...)
    parameters = Core.apply_type(Tuple, map(_parameter_type, semantic.evaluator.parameters)...)
    Tuple{Int32,reads,parameters}
end

_stage_evaluator_analysis_target(evaluator, signature::Type{<:Tuple}) =
    (evaluator, signature, 4)
function _stage_evaluator_analysis_target(
        evaluator::_AuthoringTypedEvaluator{Ts},
        signature::Type{<:Tuple}) where {Ts}
    marker_types = _authoring_record_marker_types(Ts)
    analysis_signature = Core.apply_type(
        Tuple, signature.parameters..., marker_types)
    return evaluator.evaluator, analysis_signature, 5
end

function _admit_stage_evaluator(backend::KernelAbstractions.Backend, semantic::Stage,
        draft::_StageDraft, analysis_cache::Dict{Any,Any})
    _validate_stage_publication_operations(
        backend, semantic.publications, analysis_cache)
    signature = _stage_draft_signature(draft, semantic)
    _validate_stage_read_methods(signature) || throw(
        LocalMathValidationError(
            "the bounded Stage read protocol is not package-owned";
            stage = :plan, contract = :stage_access_method_ownership,
            actual = signature.parameters[2],
        )
    )
    evaluator, analysis_signature, method_arity =
        _stage_evaluator_analysis_target(
            semantic.evaluator.evaluator, signature)
    analysis = _cached_closed_callable_effect_analysis!(analysis_cache,
        :closed_stage_evaluator, evaluator, analysis_signature,
        method_signature -> length(method_signature) == method_arity;
        source_policy = _stage_evaluator_source_safe,
        typed_policy = _stage_access_typed_safe,
    )
    analysis.qualified || throw(LocalMathValidationError(
        "the Stage evaluator fails the closed typed-IR effect screen";
        stage = :plan, contract = :stage_evaluator_effects,
        expected = :closed_storage_free_load_only_callable,
        actual = (
            purpose = :stage_evaluator,
            reason = analysis.reason,
            operation = analysis.operation,
            evaluator_type = typeof(evaluator),
            signature = signature,
            selected_method = analysis.method,
            return_type = analysis.return_type,
        ), hint = analysis.hint))
    result_type = analysis.return_type
    _validate_evaluator_result_type(semantic.publications, result_type)
    admitted = _AdmittedStage(_ADMITTED_STAGE_SEAL,
        _PortProjector(semantic.evaluator.evaluator), draft)
    _StageAdmission(backend, admitted, signature, result_type)
end
@generated function _stage_evaluator_parameters(
        parameters::P, slots::S,
    ) where {P<:Tuple,S<:Tuple}
    indices = map(slot -> slot.parameters[1], S.parameters)
    return Expr(:tuple, (:(getfield(parameters, $index)) for index in indices)...)
end
@inline _stage_control_parameter(parameters::Tuple, ::Nothing) = nothing
@inline _stage_control_parameter(
        parameters::Tuple, ::_ParameterSlot{N}) where {N} =
    getfield(parameters, N)
@inline _stage_control_parameter_slot(::_PreparedNoPrefix) = nothing
@inline _stage_control_parameter_slot(::_PreparedFieldPrefix) = nothing
@inline _stage_control_parameter_slot(::_PreparedCollectionPrefix) = nothing
@inline _stage_control_parameter_slot(prefix::_PreparedParameterPrefix) =
    prefix.slot
@inline _stage_control_parameter_slot(::_PreparedNoGate) = nothing
@inline _stage_control_parameter_slot(::_PreparedFieldGate) = nothing
@inline _stage_control_parameter_slot(gate::_PreparedParameterGate) = gate.slot
@inline function _stage_runtime_parameters(parameters::Tuple, stage)
    return _StageRuntimeParameters(
        _stage_evaluator_parameters(parameters, stage.parameter_slots),
        _stage_control_parameter(parameters,
            _stage_control_parameter_slot(stage.control.prefix)),
        _stage_control_parameter(parameters,
            _stage_control_parameter_slot(stage.control.gate)),
    )
end
@inline function _stage_evaluation(stage::_AdmittedStage)
    return _StageEvaluation(stage.evaluator, stage.fields, stage.accesses,
        stage.control, stage.source_count)
end
@inline _call_stage_evaluator(stage::_QualifiedEvaluation, item::Int32, reads, parameters) =
    stage.stage.evaluator(item, reads, stage.parameters.evaluator)
