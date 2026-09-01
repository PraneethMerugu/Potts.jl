# Generation-qualified relation-content admission for the sole Stage spine.
# Descriptor closure remains the one semantic dependency authority.  The warm
# value contains only device references and one generation receipt per exact
# Stage dependency and submission lease.

struct _NoRelationContentValidator end

struct _FixedRelationContentValidator{E,C}
    endpoints::E
    counts::C
    domain_count::Int32
    codomain_count::Int32
    degree::Int32
end
Adapt.@adapt_structure _FixedRelationContentValidator

struct _InverseLaneContentValidator{D,I}
    degrees::D
    incidents::I
    domain_count::Int32
    incident_count::Int32
    degree::Int32
end
Adapt.@adapt_structure _InverseLaneContentValidator

struct _GroupedInverseContentValidator{O,I}
    offsets::O
    incidents::I
    domain_count::Int32
    incident_count::Int32
    degree::Int32
end
Adapt.@adapt_structure _GroupedInverseContentValidator

struct _PackedRelationContentValidator{A,E,O,C}
    active::A
    endpoints::E
    offsets::O
    counts::C
    slot::Int32
    domain_count::Int32
    codomain_count::Int32
    capacity::Int32
    degree::Int32
end
Adapt.@adapt_structure _PackedRelationContentValidator

struct _GhostRelationContentValidator{M}
    mapping::M
    domain_count::Int32
    ghost_count::Int32
end
Adapt.@adapt_structure _GhostRelationContentValidator

function _relation_content_validator(binding::_RelationStorageBinding)
    _relation_uses_dynamic_content(binding) ||
        return _NoRelationContentValidator()
    relation = binding.relation
    representation = relation.representation
    storage = binding.storage
    if representation isa _FixedRelation
        counts = hasproperty(storage, :counts) ? storage.counts : nothing
        return _FixedRelationContentValidator(storage.endpoints, counts,
            Int32(length(domain(relation))), Int32(length(codomain(relation))),
            Int32(degree_bound(relation)))
    elseif representation isa _PackedRelation
        return _PackedRelationContentValidator(storage.active,
            storage.endpoints, storage.offsets, storage.counts,
            binding.generation.slot, Int32(length(domain(relation))),
            Int32(length(codomain(relation))),
            Int32(representation.capacity), Int32(degree_bound(relation)))
    elseif representation isa _InverseRelation
        if hasproperty(storage, :degrees)
            return _InverseLaneContentValidator(storage.degrees,
                storage.incidents, Int32(length(domain(relation))),
                Int32(length(codomain(relation))),
                Int32(degree_bound(relation)))
        end
        return _GroupedInverseContentValidator(storage.offsets,
            storage.incidents, Int32(length(domain(relation))),
            Int32(length(codomain(relation))),
            Int32(degree_bound(relation)))
    elseif representation isa _BoundaryRelation &&
            representation.policy isa GhostBoundary
        return _GhostRelationContentValidator(storage.mapping,
            Int32(length(storage.mapping)),
            Int32(length(representation.policy.ghost_space)))
    end
    return _NoRelationContentValidator()
end

struct _StageRelationDependency{G,S<:_RelationStatusRef,V}
    generation::G
    status::S
    validator::V
end
Adapt.@adapt_structure _StageRelationDependency

struct _NoStageRelationGuard end

struct _StageRelationGuard{D<:Tuple,R}
    dependencies::D
    receipts::R
end
Adapt.@adapt_structure _StageRelationGuard

function _stage_dynamic_relation_dependencies(
        validated::_ValidatedStructuralBinding, stage::Stage)
    _, relations, _ = _stage_descriptor_closure(stage)
    return _stage_dynamic_relation_dependencies(validated, relations)
end

_stage_dynamic_relation_dependencies(validated, ::Tuple{}) = ()
function _stage_dynamic_relation_dependencies(validated, relations::Tuple)
    relation = first(relations)
    binding = _relation_binding(validated,
        _resolve_relation_slot(validated, relation))
    generation, status = binding.generation, binding.status
    suffix = _stage_dynamic_relation_dependencies(validated,
        Base.tail(relations))
    status === nothing && generation === nothing && return suffix
    status isa _RelationStatusRef &&
        (generation === nothing ||
            generation isa _RelationContentGenerationRef) || throw(
        LocalMathValidationError(
            "relation content generation requires a device status reference";
            stage = :plan, contract = :relation_content_receipt,
            expected = (Union{Nothing,_RelationContentGenerationRef},
                _RelationStatusRef),
            actual = (typeof(generation), typeof(status)),
        ))
    return (_StageRelationDependency(generation, status,
        _relation_content_validator(binding)), suffix...)
end

function _stage_relation_receipt_workspace_spec(
        dependencies::Tuple, stage_index::Int)
    isempty(dependencies) && return (leaves = (), template = ())
    name = Symbol(:stage_, stage_index, :_relation_content_receipts)
    leaf = _workspace_leaf(name, (:relation_receipts, stage_index), UInt64,
        (length(dependencies), 1); role = :relation_content_receipt)
    return (leaves = (leaf,), template = _WorkspaceLeafSlot(name))
end

_prepare_stage_relation_guard(::Tuple{}, ::Tuple{}, validation) =
    _NoStageRelationGuard()
function _prepare_stage_relation_guard(dependencies::Tuple, receipts, validation)
    eltype(receipts) === UInt64 && ndims(receipts) == 2 &&
        size(receipts, 1) == length(dependencies) &&
        size(receipts, 2) == size(validation, 2) || throw(
        LocalMathValidationError(
            "relation-content receipt workspace has the wrong exact schema";
            stage = :prepare, contract = :relation_content_receipt_workspace,
            expected = (UInt64, (length(dependencies), size(validation, 2))),
            actual = (eltype(receipts), size(receipts)),
        ))
    return _StageRelationGuard(dependencies, receipts)
end

@inline _stage_relation_guard_succeeded(
    ::_NoStageRelationGuard, ::Int32) = true
@inline _stage_relation_guard_succeeded(
    guard::_StageRelationGuard, lease::Int32) =
    _stage_relation_dependencies_succeeded(
        guard.dependencies, guard.receipts, lease, Int32(1))

@inline _stage_relation_dependencies_succeeded(
    ::Tuple{}, receipts, lease::Int32, dependency::Int32) = true
@inline function _stage_relation_dependencies_succeeded(
        dependencies::Tuple, receipts, lease::Int32, dependency::Int32)
    current = first(dependencies)
    ready = _stage_relation_dependency_succeeded(
        current, receipts, lease, dependency)
    return ready && _stage_relation_dependencies_succeeded(
        Base.tail(dependencies), receipts, lease, dependency + Int32(1))
end

@inline _stage_relation_dependency_succeeded(
        current::_StageRelationDependency{Nothing}, receipts,
        lease::Int32, dependency::Int32) =
    _relation_content_status(current.status) == 0
@inline function _stage_relation_dependency_succeeded(
        current::_StageRelationDependency{<:_RelationContentGenerationRef},
        receipts, lease::Int32, dependency::Int32)
    generation = _relation_content_generation(current.generation)
    return _relation_content_status(current.status) == 0 &&
        _relation_validated_generation(current.status) == generation &&
        @inbounds(receipts[dependency, lease]) == generation
end

@inline function _record_stage_relation_generations!(
        ::Tuple{}, receipts, lease::Int32, dependency::Int32)
    return Int32(0)
end
@inline function _record_stage_relation_generations!(
        dependencies::Tuple, receipts, lease::Int32, dependency::Int32)
    current = first(dependencies)
    status = _relation_content_status(current.status)
    current_generation = current.generation === nothing ? nothing :
        _relation_content_generation(current.generation)
    validated_generation = _relation_validated_generation(current.status)
    valid = status == 0 && (current_generation === nothing ||
        validated_generation == current_generation)
    _record_stage_relation_generation!(current, receipts, lease, dependency)
    suffix_failure = _record_stage_relation_generations!(
        Base.tail(dependencies), receipts, lease, dependency + Int32(1))
    return valid ? suffix_failure : dependency
end

@inline function _record_stage_relation_generation!(
        current::_StageRelationDependency{Nothing}, receipts,
        lease::Int32, dependency::Int32)
    @inbounds receipts[dependency, lease] = UInt64(0)
    return nothing
end

@inline _relation_content_item_valid(
    ::_NoRelationContentValidator, item::Int32) = true

@inline function _relation_content_item_valid(
        validator::_FixedRelationContentValidator, item::Int32)
    item <= validator.domain_count || return true
    raw_count = validator.counts === nothing ? validator.degree :
        @inbounds validator.counts[item]
    zero(raw_count) <= raw_count <= validator.degree || return false
    count = Int32(raw_count)
    for lane in Int32(1):count
        endpoint = _fixed_relation_endpoint(
            validator.endpoints, item, lane)
        one(endpoint) <= endpoint <= validator.codomain_count || return false
    end
    return true
end

@inline function _relation_content_item_valid(
        validator::_InverseLaneContentValidator, item::Int32)
    item <= validator.domain_count || return true
    raw_count = @inbounds validator.degrees[item]
    zero(raw_count) <= raw_count <= validator.degree || return false
    count = Int32(raw_count)
    for lane in Int32(1):count
        incident = _inverse_incident(validator.incidents, item, lane)
        one(incident) <= incident <= validator.incident_count || return false
    end
    return true
end

@inline function _relation_content_item_valid(
        validator::_GroupedInverseContentValidator, item::Int32)
    item <= validator.domain_count || return true
    raw_start = @inbounds validator.offsets[item]
    raw_stop = @inbounds validator.offsets[item + Int32(1)]
    terminal = Int32(length(validator.incidents)) + Int32(1)
    one(raw_start) <= raw_start <= terminal || return false
    raw_start <= raw_stop <= terminal || return false
    raw_stop - raw_start <= validator.degree || return false
    start, stop = Int32(raw_start), Int32(raw_stop)
    for position in start:(stop - Int32(1))
        incident = @inbounds validator.incidents[position]
        one(incident) <= incident <= validator.incident_count || return false
    end
    return true
end

@inline function _relation_content_item_valid(
        validator::_PackedRelationContentValidator, item::Int32)
    raw_offset = @inbounds validator.offsets[validator.slot]
    raw_count = @inbounds validator.counts[validator.slot]
    zero(raw_offset) < raw_offset || return false
    zero(raw_count) <= raw_count <= validator.capacity || return false
    storage_limit = min(length(validator.active),
        _packed_endpoint_storage_length(validator.endpoints))
    raw_offset <= storage_limit + 1 || return false
    raw_count == zero(raw_count) && return true
    raw_offset <= storage_limit || return false
    raw_count <= storage_limit - raw_offset + 1 || return false
    item <= raw_count || return true
    position = raw_offset + item - one(raw_offset)
    @inbounds validator.active[position] || return true
    for lane in Int32(1):validator.degree
        endpoint = _packed_relation_endpoint(
            validator.endpoints, lane, position)
        one(endpoint) <= endpoint <= validator.codomain_count || return false
    end
    return true
end

@inline function _relation_content_item_valid(
        validator::_GhostRelationContentValidator, item::Int32)
    item <= validator.domain_count || return true
    endpoint = @inbounds validator.mapping[item]
    return zero(endpoint) <= endpoint <= validator.ghost_count
end

@kernel function _reset_relation_content_validation_kernel!(dependency)
    index = @index(Global, Linear)
    if index == 1
        status = dependency.status
        @inbounds begin
            status.statuses[status.slot] = Int32(0)
            status.validated_generations[status.slot] = UInt64(0)
        end
    end
end

@inline _reset_stage_relation_validators!(
    ::_NoStageRelationGuard, index) = nothing
@inline _reset_stage_relation_validators!(::Tuple{}, index) = nothing
@inline function _reset_stage_relation_validators!(
        dependencies::Tuple, index)
    dependency = first(dependencies)
    if index == 1 && !(dependency.validator isa _NoRelationContentValidator)
        status = dependency.status
        @inbounds begin
            status.statuses[status.slot] = Int32(0)
            status.validated_generations[status.slot] = UInt64(0)
        end
    end
    _reset_stage_relation_validators!(Base.tail(dependencies), index)
    return nothing
end
@inline _reset_stage_relation_validators!(
    guard::_StageRelationGuard, index) =
    _reset_stage_relation_validators!(guard.dependencies, index)

@kernel function _validate_relation_content_kernel!(dependency)
    ordinal = @index(Global, Linear)
    item = Int32(ordinal)
    if !_relation_content_item_valid(dependency.validator, item)
        status = dependency.status
        Atomix.@atomic max(status.statuses[status.slot], Int32(1))
    end
end

@kernel function _finalize_relation_content_validation_kernel!(dependency)
    index = @index(Global, Linear)
    if index == 1
        status = dependency.status
        if @inbounds(status.statuses[status.slot]) == Int32(0)
            @inbounds status.validated_generations[status.slot] =
                _relation_content_generation(dependency.generation)
        end
    end
end

_launch_relation_content_validation!(backend,
    dependency::_StageRelationDependency{G,S,_NoRelationContentValidator}) where {G,S} =
    nothing
function _launch_relation_content_validation!(backend,
        dependency::_StageRelationDependency{G,S,V}) where {G,S,V}
    _reset_relation_content_validation_kernel!(backend)(dependency; ndrange = 1)
    _validate_relation_content_kernel!(backend)(dependency;
        ndrange = max(Int(dependency.validator.domain_count), 1))
    _finalize_relation_content_validation_kernel!(backend)(dependency; ndrange = 1)
    return nothing
end

_launch_relation_content_validation_after_reset!(backend,
    dependency::_StageRelationDependency{G,S,_NoRelationContentValidator}) where {G,S} =
    nothing
function _launch_relation_content_validation_after_reset!(backend,
        dependency::_StageRelationDependency{G,S,V}) where {G,S,V}
    _validate_relation_content_kernel!(backend)(dependency;
        ndrange = max(Int(dependency.validator.domain_count), 1))
    _finalize_relation_content_validation_kernel!(backend)(dependency; ndrange = 1)
    return nothing
end

_launch_relation_content_validations_after_reset!(backend, ::Tuple{}) = nothing
function _launch_relation_content_validations_after_reset!(backend,
        dependencies::Tuple)
    _launch_relation_content_validation_after_reset!(backend,
        first(dependencies))
    _launch_relation_content_validations_after_reset!(backend,
        Base.tail(dependencies))
    return nothing
end

_launch_relation_content_validations!(backend, ::Tuple{}) = nothing
function _launch_relation_content_validations!(backend, dependencies::Tuple)
    _launch_relation_content_validation!(backend, first(dependencies))
    _launch_relation_content_validations!(backend, Base.tail(dependencies))
    return nothing
end
@inline function _record_stage_relation_generation!(
        current::_StageRelationDependency{<:_RelationContentGenerationRef},
        receipts, lease::Int32, dependency::Int32)
    @inbounds receipts[dependency, lease] =
        _relation_content_generation(current.generation)
    return nothing
end

@kernel function _stage_relation_receipt_kernel!(
        guard, validation, program_validation, lease::Int32)
    index = @index(Global, Linear)
    if index == 1
        failure = _record_stage_relation_generations!(
            guard.dependencies, guard.receipts, lease, Int32(1))
        if failure != 0
            _store_validation_status!(validation, lease,
                _CANDIDATE_STATUS_RELATION, failure, Int32(0), Int32(0), UInt32(0))
            _store_program_validation_status!(program_validation, lease,
                _CANDIDATE_STATUS_RELATION, failure, Int32(0), Int32(0), UInt32(0))
        end
    end
end

_launch_stage_relation_receipt!(backend, ::_NoStageRelationGuard,
    validation, program_validation, lease::Int32) = nothing
function _launch_stage_relation_receipt!(backend,
        guard::_StageRelationGuard, validation, program_validation,
        lease::Int32)
    _launch_relation_content_validations!(backend, guard.dependencies)
    _stage_relation_receipt_kernel!(backend)(guard, validation,
        program_validation, lease; ndrange = 1)
    return nothing
end

_launch_stage_relation_receipt_after_reset!(backend,
    ::_NoStageRelationGuard, validation, program_validation,
    lease::Int32) = nothing
function _launch_stage_relation_receipt_after_reset!(backend,
        guard::_StageRelationGuard, validation, program_validation,
        lease::Int32)
    _launch_relation_content_validations_after_reset!(
        backend, guard.dependencies)
    _stage_relation_receipt_kernel!(backend)(guard, validation,
        program_validation, lease; ndrange = 1)
    return nothing
end

# Relation guards are one typed predecessor kind.  This keeps every executor
# on its existing all-kernel prefix gate and makes generation changes visible
# to every later kernel, rather than merely to the initial evaluator.
@inline function _candidate_prefix_succeeded(
        statuses::Tuple{<:_StageRelationGuard,Vararg}, lease::Int32)
    return _stage_relation_guard_succeeded(first(statuses), lease) &&
        _candidate_prefix_succeeded(Base.tail(statuses), lease)
end
@inline function _candidate_prefix_succeeded(
        statuses::Tuple{_NoStageRelationGuard,Vararg}, lease::Int32)
    return _candidate_prefix_succeeded(Base.tail(statuses), lease)
end
