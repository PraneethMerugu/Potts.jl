# One buffered KernelAbstractions spine for conflict-aware Stage publication.
# Unique, Reduce, and Resolve differ only in candidate payload, validation,
# settlement, and final publication dispatch. Controls, reads, routing,
# grouping, diagnostics, and all-or-nothing visibility have one authority.

# Package-owned diagnostic precedence. Larger priority wins when one Stage
# observes several failures; this chooses the diagnostic receipt only and does
# not affect candidate, conflict, or numerical semantics.
const _CANDIDATE_FAILURE_PRIORITY = (
    success = Int32(0),
    coverage = Int32(1),
    conflict = Int32(2),
    duplicate_tie = Int32(3),
    rank_bounds = Int32(4),
    route_key = Int32(5),
    relation = Int32(6),
    invalid_control = Int32(7),
    invalid_value = Int32(8),
    empty_fold = Int32(9),
)
const _CANDIDATE_FAILURE_COVERAGE = Val(:coverage)
const _CANDIDATE_FAILURE_CONFLICT = Val(:conflict)
const _CANDIDATE_FAILURE_DUPLICATE_TIE = Val(:duplicate_tie)
const _CANDIDATE_FAILURE_RANK_BOUNDS = Val(:rank_bounds)
const _CANDIDATE_FAILURE_ROUTE_KEY = Val(:route_key)
const _CANDIDATE_FAILURE_RELATION = Val(:relation)
const _CANDIDATE_FAILURE_INVALID_CONTROL = Val(:invalid_control)
const _CANDIDATE_FAILURE_INVALID_VALUE = Val(:invalid_value)
const _CANDIDATE_FAILURE_EMPTY_FOLD = Val(:empty_fold)

@inline _candidate_failure_priority(::Val{:coverage}) =
    _CANDIDATE_FAILURE_PRIORITY.coverage
@inline _candidate_failure_priority(::Val{:conflict}) =
    _CANDIDATE_FAILURE_PRIORITY.conflict
@inline _candidate_failure_priority(::Val{:duplicate_tie}) =
    _CANDIDATE_FAILURE_PRIORITY.duplicate_tie
@inline _candidate_failure_priority(::Val{:rank_bounds}) =
    _CANDIDATE_FAILURE_PRIORITY.rank_bounds
@inline _candidate_failure_priority(::Val{:route_key}) =
    _CANDIDATE_FAILURE_PRIORITY.route_key
@inline _candidate_failure_priority(::Val{:relation}) =
    _CANDIDATE_FAILURE_PRIORITY.relation
@inline _candidate_failure_priority(::Val{:invalid_control}) =
    _CANDIDATE_FAILURE_PRIORITY.invalid_control
@inline _candidate_failure_priority(::Val{:invalid_value}) =
    _CANDIDATE_FAILURE_PRIORITY.invalid_value
@inline _candidate_failure_priority(::Val{:empty_fold}) =
    _CANDIDATE_FAILURE_PRIORITY.empty_fold

const _CANDIDATE_STATUS_SUCCESS = _CANDIDATE_FAILURE_PRIORITY.success
const _CANDIDATE_STATUS_COVERAGE = _candidate_failure_priority(
    _CANDIDATE_FAILURE_COVERAGE)
const _CANDIDATE_STATUS_CONFLICT = _candidate_failure_priority(
    _CANDIDATE_FAILURE_CONFLICT)
const _CANDIDATE_STATUS_DUPLICATE_TIE = _candidate_failure_priority(
    _CANDIDATE_FAILURE_DUPLICATE_TIE)
const _CANDIDATE_STATUS_RANK_BOUNDS = _candidate_failure_priority(
    _CANDIDATE_FAILURE_RANK_BOUNDS)
const _CANDIDATE_STATUS_ROUTE_KEY = _candidate_failure_priority(
    _CANDIDATE_FAILURE_ROUTE_KEY)
const _CANDIDATE_STATUS_RELATION = _candidate_failure_priority(
    _CANDIDATE_FAILURE_RELATION)
const _CANDIDATE_STATUS_INVALID_CONTROL = _candidate_failure_priority(
    _CANDIDATE_FAILURE_INVALID_CONTROL)

# Existing focused evidence refers to the semantic Unique names. They are
# constants, not a compatibility execution path or duplicated status scheme.
const _UNIQUE_STATUS_SUCCESS = _CANDIDATE_STATUS_SUCCESS
const _UNIQUE_STATUS_COVERAGE = _CANDIDATE_STATUS_COVERAGE
const _UNIQUE_STATUS_CONFLICT = _CANDIDATE_STATUS_CONFLICT
const _UNIQUE_STATUS_RELATION = _CANDIDATE_STATUS_RELATION
const _UNIQUE_STATUS_INVALID_CONTROL = _CANDIDATE_STATUS_INVALID_CONTROL

"""Exact counted physical layout for conflict-aware `Unique`."""
struct _CountedUniqueWorkspace{D,V,C,W,I}
    destinations::D
    values::V
    counts::C
    winners::W
    invalid_ordinal::I
    candidate_count::Int32
    destination_count::Int32
end

mutable struct _CandidateStageWorkspaceSeal end
const _CANDIDATE_STAGE_WORKSPACE_SEAL = _CandidateStageWorkspaceSeal()

struct _CandidateStageWorkspace{W,S,R,V,T,A}
    publications::W
    # Private, one-word arbitration scratch.  The receipt-visible status is
    # the standard lease-indexed validation matrix below.
    status::S
    route_invalid::R
    validation::V
    tree::T
    authority::A
    function _CandidateStageWorkspace(seal::_CandidateStageWorkspaceSeal,
            publications::W, status::S, validation::V, tree::T, authority::A,
        ) where {W,S,V,T,A}
        seal === _CANDIDATE_STAGE_WORKSPACE_SEAL ||
            error("invalid candidate-stage workspace seal")
        return new{W,S,typeof(tree.route_invalid),V,T,A}(
            publications, status, tree.route_invalid, validation, tree, authority)
    end
end

struct _CandidateStageExecution{Q,W,S,R}
    stage::Q
    workspaces::W
    status::S
    route_invalid::R
end

"""The exact diagnostic state shared by Candidate evaluation and validation."""
struct _CandidateDiagnostics{S,R}
    status::S
    route_invalid::R
end

"""Publication/control data used after evaluation; evaluator/access types are absent."""
struct _CandidatePublicationPhase{P,F,G}
    publications::P
    fields::F
    gate::G
end

Adapt.@adapt_structure _CountedUniqueWorkspace
Adapt.@adapt_structure _CandidateStageExecution
Adapt.@adapt_structure _CandidateDiagnostics
Adapt.@adapt_structure _CandidatePublicationPhase

"""Cold launch owner. Its backend never enters a kernel argument."""
struct _CandidateStagePreparation{B,E,V}
    backend::B
    execution::E
    validation::V
end

struct _DirectPointwiseSegmentPreparation{B,S,D,P,M,F,I,R}
    backend::B
    stages::S
    destinations::D
    empty_policies::P
    materializations::M
    forwarding::F
    logical_indices::I
    boundary_reason::R
end

struct _NoPointwiseForward end
struct _PointwiseForward{Member,Port} end
struct _MaterializePointwise end
struct _ForwardOnlyPointwise end
struct _ForwardedPointwiseField{T,A}
    value::T
    storage::A
    item::Int32
end
Base.eltype(::Type{<:_ForwardedPointwiseField{T}}) where {T} = T
Base.length(field::_ForwardedPointwiseField) = length(field.storage)
Base.size(field::_ForwardedPointwiseField) = size(field.storage)
Base.axes(field::_ForwardedPointwiseField) = axes(field.storage)
@inline function Base.getindex(field::_ForwardedPointwiseField, index::Integer)
    index == field.item && return field.value
    return @inbounds field.storage[index]
end

@inline function _direct_unique_publish!(
        destination, value::UniqueValue, empty, item::Int32,
        ::_MaterializePointwise)
    @inbounds destination[item] = value.value
    return nothing
end
@inline function _direct_unique_publish!(
        destination, value::ConditionalUniqueValue,
        empty::PreserveEmpty, item::Int32, ::_MaterializePointwise)
    value.participates && (@inbounds destination[item] = value.value)
    return nothing
end
@inline function _direct_unique_publish!(
        destination, value::ConditionalUniqueValue,
        empty::FillEmpty, item::Int32, ::_MaterializePointwise)
    @inbounds destination[item] = value.participates ? value.value : empty.value
    return nothing
end
@inline _direct_unique_publish!(destination, value, empty, item::Int32,
    ::_ForwardOnlyPointwise) = nothing
@inline _direct_unique_publish_all!(
    ::Tuple{}, ::Tuple{}, ::Tuple{}, ::Tuple{}, item::Int32) = ()
@inline function _direct_unique_publish_all!(
        destinations::Tuple, values::Tuple, empties::Tuple,
        materializations::Tuple, item::Int32)
    destination, value, empty, materialization = first(destinations),
        first(values), first(empties), first(materializations)
    published = if value isa UniqueValue || value.participates
        value.value
    elseif empty isa FillEmpty
        empty.value
    else
        @inbounds destination[item]
    end
    _direct_unique_publish!(destination, value, empty, item, materialization)
    return (published, _direct_unique_publish_all!(Base.tail(destinations),
        Base.tail(values), Base.tail(empties), Base.tail(materializations),
        item)...)
end
@inline _direct_unique_publish_empty!(
    destination, ::PreserveEmpty, item::Int32, ::_MaterializePointwise) = nothing
@inline function _direct_unique_publish_empty!(
        destination, empty::FillEmpty, item::Int32, ::_MaterializePointwise)
    @inbounds destination[item] = empty.value
    return nothing
end
@inline _direct_unique_publish_empty!(
    destination, ::UnreachableEmpty, item::Int32,
    ::_MaterializePointwise) = nothing
@inline _direct_unique_publish_empty!(destination, empty, item::Int32,
    ::_ForwardOnlyPointwise) = nothing
@inline _direct_unique_publish_all_empty!(
    ::Tuple{}, ::Tuple{}, ::Tuple{}, item::Int32) = ()
@inline function _direct_unique_publish_all_empty!(
        destinations::Tuple, empties::Tuple, materializations::Tuple,
        item::Int32)
    destination, empty, materialization = first(destinations),
        first(empties), first(materializations)
    published = empty isa FillEmpty ? empty.value : @inbounds(destination[item])
    _direct_unique_publish_empty!(
        destination, empty, item, materialization)
    return (published, _direct_unique_publish_all_empty!(
        Base.tail(destinations), Base.tail(empties),
        Base.tail(materializations), item)...)
end

@inline _pointwise_forward_field(field, ::_NoPointwiseForward,
    cache, item::Int32) = field
@inline function _pointwise_forward_field(field,
        ::_PointwiseForward{Member,Port}, cache, item::Int32
    ) where {Member,Port}
    value = getfield(getfield(cache, Member), Port)
    return _ForwardedPointwiseField(value, field, item)
end
@inline _pointwise_forward_fields(::Tuple{}, ::Tuple{}, cache, item::Int32) = ()
@inline function _pointwise_forward_fields(fields::Tuple, forwarding::Tuple,
        cache, item::Int32)
    return (_pointwise_forward_field(first(fields), first(forwarding),
            cache, item),
        _pointwise_forward_fields(Base.tail(fields), Base.tail(forwarding),
            cache, item)...)
end

@inline function _pointwise_stage_with_fields(stage::_StageEvaluation,
        fields::Tuple)
    return _StageEvaluation(stage.evaluator, fields, stage.accesses,
        stage.control, stage.source_count)
end

@inline function _pointwise_current_values(destinations::Tuple, item::Int32)
    return map(destination -> @inbounds(destination[item]), destinations)
end

@inline function _direct_pointwise_member!(qualified, destinations,
        empty_policies, materializations, forwarding, cache, predecessors,
        program_validation, lease_index::Int32, item::Int32)
    fields = _pointwise_forward_fields(
        qualified.stage.fields, forwarding, cache, item)
    stage = _pointwise_stage_with_fields(qualified.stage, fields)
    local_qualified = _QualifiedEvaluation(stage, qualified.parameters)
    published = _pointwise_current_values(destinations, item)
    if _candidate_prefix_succeeded(predecessors, lease_index) &&
            _stage_gate_open(stage.control.gate, stage, local_qualified.parameters)
        prefix = _stage_prefix_value(
            stage.control.prefix, stage, local_qualified.parameters)
        valid = prefix isa Integer && !(prefix isa Bool) &&
            0 <= prefix <= stage.source_count
        if item == 1 && !valid
            _store_program_validation_status!(program_validation,
                lease_index, _CANDIDATE_STATUS_INVALID_CONTROL,
                Int32(0), Int32(0), Int32(0), UInt32(0))
        elseif item <= stage.source_count && valid
            active = item <= Int32(prefix) &&
                _stage_mask_active(stage.control.mask, stage, item) &&
                _stage_subset_active(stage.control.subset, stage, item)
            if active
                result = _call_stage_evaluator(local_qualified, item,
                    _stage_reads(stage, item), local_qualified.parameters)
                published = _direct_unique_publish_all!(destinations, result,
                    empty_policies, materializations, item)
            else
                published = _direct_unique_publish_all_empty!(
                    destinations, empty_policies, materializations, item)
            end
        end
    end
    return published
end

@generated function _direct_pointwise_members!(qualified::Q,
        destinations::D, empty_policies::P, materializations::M,
        forwarding::F, ::Tuple{},
        predecessors, program_validation, lease_index::Int32,
        item::Int32) where {Q<:Tuple,D<:Tuple,P<:Tuple,M<:Tuple,F<:Tuple}
    count = fieldcount(Q)
    fieldcount(D) == fieldcount(P) == fieldcount(M) == fieldcount(F) == count ||
        return :(throw(ArgumentError(
            "pointwise segment physical tuples are misaligned")))
    published = [gensym(:published) for _ in 1:count]
    statements = Expr[]
    for index in 1:count
        cache = Expr(:tuple, published[1:(index - 1)]...)
        push!(statements, :(local $(published[index]) =
            _direct_pointwise_member!(
                getfield(qualified, $index),
                getfield(destinations, $index),
                getfield(empty_policies, $index),
                getfield(materializations, $index),
                getfield(forwarding, $index),
                $cache, predecessors, program_validation,
                lease_index, item)))
    end
    return quote
        $(statements...)
        nothing
    end
end

@kernel function _direct_pointwise_segment_kernel!(
        qualified, destinations, empty_policies, materializations,
        forwarding, predecessors, program_validation, lease_index::Int32)
    raw_item = @index(Global, Linear)
    item = Int32(raw_item)
    _direct_pointwise_members!(qualified, destinations, empty_policies,
        materializations, forwarding, (), predecessors,
        program_validation, lease_index, item)
end

function _execute_direct_pointwise_segment!(
        prepared::_DirectPointwiseSegmentPreparation, parameters::Tuple,
        lease_index::Int32, predecessors::Tuple, program_validation)
    qualified = map(prepared.stages) do stage
        _QualifiedEvaluation(_stage_evaluation(stage),
            _stage_runtime_parameters(parameters, stage))
    end
    extent = maximum(stage -> Int(stage.source_count), prepared.stages;
        init = 1)
    _direct_pointwise_segment_kernel!(prepared.backend)(
        qualified, prepared.destinations, prepared.empty_policies,
        prepared.materializations, prepared.forwarding,
        predecessors, program_validation, lease_index; ndrange = extent)
    return prepared
end

@inline function _candidate_atomic_max!(array, index, value)
    Atomix.@atomic max(array[index], value)
    return nothing
end
@inline function _candidate_atomic_min!(array, index, value)
    Atomix.@atomic min(array[index], value)
    return nothing
end

@inline _parameter_at(parameters::Tuple, ::_ParameterSlot{N}) where {N} =
    getfield(parameters, N)

@inline _stage_prefix_value(::_PreparedNoPrefix, stage, parameters) =
    stage.source_count
@inline _stage_prefix_value(prefix::_PreparedParameterPrefix, stage, parameters) =
    parameters.prefix
@inline function _stage_prefix_value(prefix::_PreparedFieldPrefix, stage, parameters)
    @inbounds _prepared_stage_field(stage.fields, prefix.slot)[1]
end
@inline _stage_prefix_value(prefix::_PreparedCollectionPrefix, stage, parameters) =
    @inbounds prefix.storage.count[1]

@inline _stage_gate_open(::_PreparedNoGate, stage, parameters) = true
@inline _stage_gate_open(gate::_PreparedParameterGate, stage, parameters) =
    parameters.gate
@inline function _stage_gate_open(gate::_PreparedFieldGate, stage, parameters)
    @inbounds _prepared_stage_field(stage.fields, gate.slot)[1]
end

@inline _stage_mask_active(::_PreparedNoMask, stage, item) = true
@inline function _stage_mask_active(mask::_PreparedMask, stage, item)
    @inbounds _prepared_stage_field(stage.fields, mask.slot)[item]
end

@inline _stage_subset_active(::_PreparedNoSubset, stage, item) = true
@inline _stage_subset_active(subset, stage, item) =
    _subset_participates(subset, stage.fields, item)

@inline function _stage_control_state(stage, parameters, item)
    prefix = _stage_prefix_value(stage.control.prefix, stage, parameters)
    valid = prefix isa Integer && !(prefix isa Bool) &&
        0 <= prefix <= stage.source_count
    valid || return (false, false)
    active = item <= Int32(prefix) &&
        _stage_mask_active(stage.control.mask, stage, item) &&
        _stage_subset_active(stage.control.subset, stage, item)
    return (true, active)
end

@inline function _candidate_fail!(execution, reason::Val)
    _candidate_atomic_max!(
        execution.status, 1, _candidate_failure_priority(reason))
    return nothing
end

@inline _candidate_prefix_succeeded(::Tuple{}, ::Int32) = true
@inline function _candidate_predecessor_succeeded(status, lease::Int32)
    return @inbounds status[_VALIDATION_FAILURE_CLASS, lease] == UInt32(0)
end
@inline function _candidate_prefix_succeeded(statuses::Tuple, lease::Int32)
    _candidate_predecessor_succeeded(first(statuses), lease) ||
        return false
    return _candidate_prefix_succeeded(Base.tail(statuses), lease)
end

@inline _reset_candidate_workspace_indices!(::Tuple{}, index) = nothing
@inline function _reset_candidate_workspace_indices!(workspaces::Tuple, index)
    workspace = first(workspaces)
    _reset_candidate_grouping_index!(workspace, index)
    _reset_candidate_payload!(workspace, index)
    _reset_candidate_workspace_indices!(Base.tail(workspaces), index)
    return nothing
end

@kernel function _candidate_stage_reset_kernel!(
        workspaces, diagnostics, validation, relation_guard,
        lease::Int32, extent::Int32)
    index = @index(Global, Linear)
    _reset_stage_relation_validators!(relation_guard, index)
    index <= length(diagnostics.route_invalid) &&
        (@inbounds diagnostics.route_invalid[index] = typemax(Int32))
    if index == 1
        @inbounds diagnostics.status[1] = _CANDIDATE_STATUS_SUCCESS
        _clear_validation_status!(validation, lease)
    end
    index <= extent &&
        _reset_candidate_workspace_indices!(workspaces, index)
end

@inline function _reset_candidate_payload!(
        workspace::_CountedUniqueWorkspace, index)
    if index <= workspace.candidate_count
        @inbounds workspace.destinations[index] = Int32(0)
    end
    if index <= workspace.destination_count
        @inbounds begin
            workspace.counts[index] = Int32(0)
            workspace.winners[index] = typemax(Int32)
        end
    end
    index == 1 &&
        (@inbounds workspace.invalid_ordinal[1] = typemax(Int32))
    return nothing
end
@inline _reset_candidate_grouping_index!(
    workspace::_CountedUniqueWorkspace, index) = nothing
@inline _group_candidate_workspace!(backend,
    workspace::_CountedUniqueWorkspace) = workspace
@inline _candidate_workspace_extent(workspace::_CountedUniqueWorkspace) =
    max(Int(workspace.candidate_count), Int(workspace.destination_count))
@inline _unique_value(value::UniqueValue) = value.value
@inline _unique_value(value::ConditionalUniqueValue) = value.value
@inline _unique_participates(::UniqueValue) = true
@inline _unique_participates(value::ConditionalUniqueValue) = value.participates

@inline function _runtime_route_endpoint!(
        execution, workspace, relation, fields, key::K, ordinal::Int32,
        context::Int32,
    ) where {K<:Union{Int32,UInt32}}
    key == zero(K) && return _missing_relation_endpoint(
        _relation_target_slot(relation.view))
    endpoint = _relation_runtime_endpoint(relation, fields, key)
    if !endpoint.present
        @inbounds _candidate_route_destinations(workspace)[ordinal] =
            reinterpret(Int32, _validation_encode(key))
        _candidate_atomic_min!(execution.route_invalid, context, ordinal)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_ROUTE_KEY)
    end
    return endpoint
end

@inline _candidate_route_destinations(workspace) =
    workspace.grouping.destinations
@inline _candidate_route_destinations(workspace::_CountedUniqueWorkspace) =
    workspace.destinations

@inline function _counted_unique_claim!(workspace, ordinal::Int32,
        destination::Int32)
    Atomix.@atomic workspace.counts[destination] += Int32(1)
    _candidate_atomic_min!(workspace.winners, destination, ordinal)
    return nothing
end

@inline function _claim_candidate_lane!(
        publication::_PreparedStagePublication{C,<:Unique{T,K}},
        workspace::_CountedUniqueWorkspace, value, fields, item, ::Val{L},
        execution, context::Int32,
    ) where {C,T,K,L}
    component = first(publication.components)
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.destinations[ordinal] = Int32(0)
    if !_relation_keys_valid(component.relation, fields, item)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        _candidate_atomic_min!(workspace.invalid_ordinal, 1, ordinal)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    participates = _unique_participates(value) &&
        endpoint.present && !endpoint.exterior
    if participates
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = _unique_value(value)
        end
        _counted_unique_claim!(workspace, ordinal, endpoint.index)
    end
    return nothing
end


@inline _routed_unique_participates(::RoutedUniqueValue) = true
@inline _routed_unique_participates(value::ConditionalRoutedUniqueValue) =
    value.participates
@inline function _claim_candidate_lane!(
        publication::_PreparedStagePublication{C,<:Unique{T,K}},
        workspace::_CountedUniqueWorkspace,
        value::Union{RoutedUniqueValue,ConditionalRoutedUniqueValue},
        fields, item, ::Val{L}, execution, context::Int32,
    ) where {C,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.destinations[ordinal] = Int32(0)
    _routed_unique_participates(value) || return nothing
    component = first(publication.components)
    endpoint = _runtime_route_endpoint!(execution, workspace,
        component.relation, fields, value.key, ordinal, context)
    if endpoint.present && !endpoint.exterior
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = value.value
        end
        _counted_unique_claim!(workspace, ordinal, endpoint.index)
    end
    return nothing
end

@generated function _claim_publication!(
        publication::_PreparedStagePublication{C,<:Unique{T,K}},
        workspace::_CountedUniqueWorkspace, port, fields, item, execution,
        context::Int32,
    ) where {C,T,K}
    calls = Any[]
    for lane in 1:K
        value = K == 1 ? :port : :(getfield(port, $lane))
        push!(calls, :(_claim_candidate_lane!(
            publication, workspace, $value, fields, item, Val($lane),
            execution, context)))
    end
    return Expr(:block, calls..., :(nothing))
end

@inline _claim_publications!(::Tuple{}, ::Tuple{}, result, fields, item, port,
    execution) =
    nothing
@inline function _claim_publications!(
        publications::Tuple, workspaces::Tuple, result, fields, item, port,
        execution)
    _claim_publication!(first(publications), first(workspaces),
        getfield(result, port), fields, item, execution, Int32(port))
    _claim_publications!(Base.tail(publications), Base.tail(workspaces),
        result, fields, item, port + 1, execution)
end

@inline _stage_read(stage, access::_PreparedStageAccess, item::Int32) =
    _StageRead(stage.fields, access.relation, item, _NoEvaluationValidation())
@inline _stage_read(stage, access::_PreparedStageAccess, item::Int32,
        validation) =
    _StageRead(stage.fields, access.relation, item, validation)
@inline function _stage_read(stage,
        access::_PreparedCollectionAccess{<:_BoundedGroup{K}}, item::Int32
    ) where {K}
    storage = access.storage
    first = @inbounds storage.segment_starts[item]
    stop = @inbounds storage.segment_starts[item + Int32(1)]
    return BoundedGroupView(_CONSTRUCTION_TOKEN, Val(K), eltype(storage.records),
        storage.records, first, stop - first, _NoEvaluationValidation())
end
@inline function _stage_read(stage,
        access::_PreparedCollectionAccess{<:_BoundedGroup{K}}, item::Int32,
        validation,
    ) where {K}
    storage = access.storage
    first = @inbounds storage.segment_starts[item]
    stop = @inbounds storage.segment_starts[item + Int32(1)]
    return BoundedGroupView(_CONSTRUCTION_TOKEN, Val(K), eltype(storage.records),
        storage.records, first, stop - first, validation)
end
@inline function _stage_read(stage,
        access::_PreparedCollectionAccess{<:_SourcePositionsAccess{K,L}}, item::Int32
    ) where {K,L}
    return @inbounds access.storage.source_position[
        (Int(item) - 1) * K + L]
end
@inline _stage_read(stage,
        access::_PreparedCollectionAccess{<:_SourcePositionsAccess},
        item::Int32, validation) = _stage_read(stage, access, item)
@generated function _stage_reads(
        stage::_AdmittedStage{E,F,A}, item::Int32,
    ) where {E,F,A<:Tuple}
    reads = map(1:fieldcount(A)) do index
        :(_stage_read(stage, getfield(getfield(stage, :accesses), $index), item))
    end
    return Expr(:tuple, reads...)
end
@generated function _stage_reads(
        stage::_StageEvaluation{E,F,A}, item::Int32,
    ) where {E,F,A<:Tuple}
    reads = map(1:fieldcount(A)) do index
        :(_stage_read(stage, getfield(stage.accesses, $index), item))
    end
    return Expr(:tuple, reads...)
end
@generated function _stage_reads(
        stage::_StageEvaluation{E,F,A}, item::Int32, validation,
    ) where {E,F,A<:Tuple}
    reads = map(1:fieldcount(A)) do index
        :(_stage_read(stage, getfield(stage.accesses, $index), item, validation))
    end
    return Expr(:tuple, reads...)
end

@inline _collection_access_valid(access::_PreparedStageAccess, item::Int32) = true
@inline _stage_access_valid(access::_PreparedStageAccess,
        fields::Tuple, item::Int32) =
    _relation_keys_valid(access.relation, fields, item)
@inline _stage_access_valid(access::_PreparedCollectionAccess,
        fields::Tuple, item::Int32) = _collection_access_valid(access, item)
@generated function _stage_accesses_valid(
        accesses::A, fields::Tuple, item::Int32) where {A<:Tuple}
    result = :(true)
    for index in fieldcount(A):-1:1
        result = :(_stage_access_valid(
            getfield(accesses, $index), fields, item) && $result)
    end
    return result
end
@inline function _collection_access_valid(
        access::_PreparedCollectionAccess{<:_BoundedGroup{K}}, item::Int32
    ) where {K}
    storage = access.storage
    starts = storage.segment_starts
    item + Int32(1) <= length(starts) || return false
    first = @inbounds starts[item]
    stop = @inbounds starts[item + Int32(1)]
    count = stop - first
    live = @inbounds storage.count[1]
    return Int32(1) <= first <= stop <= live + Int32(1) && count <= Int32(K)
end
@inline function _collection_access_valid(
        access::_PreparedCollectionAccess{<:_SourcePositionsAccess{K,L}}, item::Int32
    ) where {K,L}
    projection = access.storage.source_position
    return projection !== nothing && K >= L &&
        (Int64(item) - 1) * Int64(K) + Int64(L) <= length(projection)
end
@inline _collection_accesses_valid(::Tuple{}, item::Int32) = true
@inline function _collection_accesses_valid(accesses::Tuple, item::Int32)
    return _collection_access_valid(first(accesses), item) &&
        _collection_accesses_valid(Base.tail(accesses), item)
end

@kernel function _candidate_stage_evaluate_kernel!(
        qualified, publications, workspaces, diagnostics,
        predecessors, lease::Int32)
    raw_item = @index(Global, Linear)
    item = Int32(raw_item)
    stage = qualified.stage
    gate_open = _stage_gate_open(
        stage.control.gate, stage, qualified.parameters)
    if _candidate_prefix_succeeded(predecessors, lease) && gate_open
        prefix = _stage_prefix_value(
            stage.control.prefix, stage, qualified.parameters)
        prefix_valid = prefix isa Integer && !(prefix isa Bool) &&
            0 <= prefix <= stage.source_count
        if item == 1
            prefix_valid || _candidate_fail!(
                diagnostics, _CANDIDATE_FAILURE_INVALID_CONTROL)
        end
        if item <= stage.source_count && prefix_valid
            _, active = _stage_control_state(
                stage, qualified.parameters, item)
            access_valid = _stage_accesses_valid(
                stage.accesses, stage.fields, item)
            access_valid || _candidate_fail!(
                diagnostics, _CANDIDATE_FAILURE_RELATION)
            if active && access_valid
                result = _call_stage_evaluator(qualified, item,
                    _stage_reads(stage, item,
                        _CandidateEvaluationValidation(diagnostics)),
                    qualified.parameters)
                _claim_publications!(
                    publications, workspaces,
                    result, stage.fields, item, 1, diagnostics)
            end
        end
    end
end

@inline function _validate_publication!(
        publication::_PreparedStagePublication{C,<:Unique},
        workspace::_CountedUniqueWorkspace, execution, destination,
    ) where {C}
    if destination <= workspace.destination_count
        count = @inbounds workspace.counts[destination]
        count <= 1 || _candidate_fail!(
            execution, _CANDIDATE_FAILURE_CONFLICT)
        publication.law.coverage isa TotalCoverage && count != 1 &&
            _candidate_fail!(execution, _CANDIDATE_FAILURE_COVERAGE)
    end
    return nothing
end

@inline _validate_publications!(::Tuple{}, ::Tuple{}, execution, destination) =
    nothing
@inline function _validate_publications!(
        publications::Tuple, workspaces::Tuple, execution, destination)
    _validate_publication!(first(publications), first(workspaces),
        execution, destination)
    _validate_publications!(Base.tail(publications), Base.tail(workspaces),
        execution, destination)
end

@kernel function _candidate_stage_validate_kernel!(phase, gate_parameters,
        workspaces, diagnostics, predecessors, lease::Int32, extent::Int32)
    destination = @index(Global, Linear)
    if _candidate_prefix_succeeded(predecessors, lease) && destination <= extent &&
            _stage_gate_open(phase.gate, phase, gate_parameters)
        _validate_publications!(
            phase.publications, workspaces, diagnostics, destination)
    end
end

@inline _candidate_stage_success(status) =
    @inbounds(status[1]) == _CANDIDATE_STATUS_SUCCESS

@inline _candidate_empty_write!(destination, index, ::PreserveEmpty) = nothing
@inline function _candidate_empty_write!(destination, index, empty::FillEmpty)
    @inbounds destination[index] = empty.value
    return nothing
end
@inline _candidate_empty_write!(destination, index, ::UnreachableEmpty) = nothing

@inline function _publish_publication!(
        publication::_PreparedStagePublication{C,<:Unique},
        workspace::_CountedUniqueWorkspace, fields, destination_index,
    ) where {C}
    destination_index <= workspace.destination_count || return nothing
    component = first(publication.components)
    destination = _prepared_stage_field(
        fields, _relation_target_slot(component.relation.view))
    count = @inbounds workspace.counts[destination_index]
    if count == 0
        _candidate_empty_write!(
            destination, destination_index, publication.law.onempty)
    else
        ordinal = @inbounds workspace.winners[destination_index]
        @inbounds destination[destination_index] = workspace.values[ordinal]
    end
    return nothing
end

@inline _publish_publications!(::Tuple{}, ::Tuple{}, fields, destination) =
    nothing
@inline function _publish_publications!(
        publications::Tuple, workspaces::Tuple, fields, destination)
    _publish_publication!(first(publications), first(workspaces),
        fields, destination)
    _publish_publications!(Base.tail(publications), Base.tail(workspaces),
        fields, destination)
end

@kernel function _candidate_stage_publish_kernel!(phase, gate_parameters,
        workspaces, diagnostics, validation, program_validation,
        predecessors, lease::Int32, extent::Int32)
    destination = @index(Global, Linear)
    code = @inbounds diagnostics.status[1]
    if destination == 1 && _candidate_prefix_succeeded(predecessors, lease)
        diagnostic = _candidate_diagnostic(
            phase.publications, workspaces, diagnostics.route_invalid, code)
        _store_validation_status!(validation, lease,
            code, diagnostic.context, diagnostic.primary,
            diagnostic.secondary, diagnostic.witness)
        code == _CANDIDATE_STATUS_SUCCESS ||
            _store_program_validation_status!(program_validation,
                lease, code, diagnostic.context,
                diagnostic.primary, diagnostic.secondary,
                diagnostic.witness)
    end
    if _candidate_prefix_succeeded(predecessors, lease) && destination <= extent &&
            code == _CANDIDATE_STATUS_SUCCESS &&
            _stage_gate_open(phase.gate, phase, gate_parameters)
        _publish_publications!(phase.publications, workspaces,
            phase.fields, destination)
    end
end

@inline _atomic_initialize_publication!(publication, workspace, fields,
    destination) = nothing
@inline _atomic_initialize_publications!(::Tuple{}, ::Tuple{}, fields,
    destination) = nothing
@inline function _atomic_initialize_publications!(
        publications::Tuple, workspaces::Tuple, fields, destination)
    _atomic_initialize_publication!(first(publications), first(workspaces),
        fields, destination)
    _atomic_initialize_publications!(Base.tail(publications),
        Base.tail(workspaces), fields, destination)
end
@kernel function _candidate_stage_atomic_initialize_kernel!(phase, gate_parameters,
        workspaces, status, predecessors, lease::Int32, extent::Int32)
    destination = @index(Global, Linear)
    if _candidate_prefix_succeeded(predecessors, lease) && destination <= extent &&
            _candidate_stage_success(status) &&
            _stage_gate_open(phase.gate, phase, gate_parameters)
        _atomic_initialize_publications!(phase.publications, workspaces,
            phase.fields, destination)
    end
end

@inline _candidate_atomic_initialization_required(::_PreparedStagePublication) = false
@inline _candidate_atomic_initialization_required(
    ::_PreparedStagePublication{
        C,<:Reduce{T,K,F,S,<:RelaxedAtomic}}) where {C,T,K,F,S} = true
@inline _candidate_atomic_required(::_PreparedStagePublication) = false
@inline _candidate_atomic_required(
    ::_PreparedStagePublication{
        C,<:Reduce{T,K,F,S,<:RelaxedAtomic}}) where {C,T,K,F,S} = true

@inline _candidate_phase_required(::Tuple{}, requirement) = false
@inline function _candidate_phase_required(publications::Tuple, requirement)
    requirement(first(publications)) ||
        _candidate_phase_required(Base.tail(publications), requirement)
end
@inline _atomic_publications!(::Tuple{}, ::Tuple{}, ordinal) = nothing
@inline _atomic_publication!(publication, workspace, ordinal) = nothing
@inline function _atomic_publications!(
        publications::Tuple, workspaces::Tuple, ordinal)
    _atomic_publication!(first(publications), first(workspaces), ordinal)
    _atomic_publications!(Base.tail(publications), Base.tail(workspaces), ordinal)
end
@kernel function _candidate_stage_atomic_kernel!(phase, gate_parameters,
        workspaces, status, predecessors, lease::Int32, extent::Int32)
    ordinal = @index(Global, Linear)
    if _candidate_prefix_succeeded(predecessors, lease) && ordinal <= extent &&
            _candidate_stage_success(status) &&
            _stage_gate_open(phase.gate, phase, gate_parameters)
        _atomic_publications!(
            phase.publications, workspaces, ordinal)
    end
end

function _candidate_workspace_spec(
        stage, publication::_PreparedStagePublication{C,<:Unique};
        path::Tuple, name_prefix::Symbol,
    ) where {C}
    law = publication.law
    candidates, destination_count = _candidate_publication_dimensions(
        stage, publication, :unique_candidate_capacity)
    destinations_name = Symbol(name_prefix, :_destinations)
    values_name = Symbol(name_prefix, :_values)
    counts_name = Symbol(name_prefix, :_counts)
    winners_name = Symbol(name_prefix, :_winners)
    invalid_name = Symbol(name_prefix, :_invalid_ordinal)
    destinations_leaf = _workspace_leaf(destinations_name,
        (path..., :destinations), Int32, (candidates,);
        role = :unique_candidate_destination)
    values_leaf = _workspace_leaf(values_name, (path..., :values),
        _unique_value_type(law), (candidates,);
        role = :unique_candidate_value)
    counts_leaf = _workspace_leaf(counts_name, (path..., :counts), Int32,
        (destination_count,); role = :unique_destination_count)
    winners_leaf = _workspace_leaf(winners_name, (path..., :winners), Int32,
        (destination_count,); role = :unique_destination_winner)
    invalid_leaf = _workspace_leaf(invalid_name, (path..., :invalid_ordinal),
        Int32, (1,); role = :candidate_invalid_destination)
    template = (
        destinations = _WorkspaceLeafSlot(destinations_name),
        values = _WorkspaceLeafSlot(values_name),
        counts = _WorkspaceLeafSlot(counts_name),
        winners = _WorkspaceLeafSlot(winners_name),
        invalid_ordinal = _WorkspaceLeafSlot(invalid_name),
    )
    return (
        leaves = (destinations_leaf, values_leaf, counts_leaf, winners_leaf,
            invalid_leaf),
        template,
        candidate_count = Int32(candidates),
        destination_count = Int32(destination_count),
    )
end

function _candidate_publication_dimensions(stage,
        publication::_PreparedStagePublication, purpose::Symbol)
    candidates = _candidate_record_capacity(
        Int(stage.source_count), _publication_width(publication.law), purpose;
        int32_index = true)
    destination_count = _relation_count(_relation_codomain_extent(
        first(publication.components).relation))
    _checked_int32_count(destination_count,
        Symbol(purpose, :_destination_count); terminal = true,
        stage = :prepare)
    return candidates, destination_count
end

_candidate_port_workspace_specs(stage, ::Tuple{}, path::Tuple,
    name_prefix::Symbol, index::Int) = ()
function _candidate_port_workspace_specs(stage,
    publications::Tuple, path::Tuple, name_prefix::Symbol, index::Int)
    port = _candidate_workspace_spec(stage, first(publications);
        path = (path..., :publications, index),
        name_prefix = Symbol(name_prefix, :_publication_, index))
    return (port, _candidate_port_workspace_specs(stage,
        Base.tail(publications), path, name_prefix, index + 1)...)
end

_candidate_port_templates(::Tuple{}) = ()
function _candidate_port_templates(ports::Tuple)
    return (first(ports).template,
        _candidate_port_templates(Base.tail(ports))...)
end

_candidate_port_leaves(::Tuple{}) = ()
function _candidate_port_leaves(ports::Tuple)
    return (first(ports).leaves...,
        _candidate_port_leaves(Base.tail(ports))...)
end

@inline _candidate_workspace_shape(spec, ::Unique) =
    (candidate_count = spec.candidate_count,
        destination_count = spec.destination_count)
_candidate_port_shapes(::Tuple{}, ::Tuple{}) = ()
function _candidate_port_shapes(ports::Tuple, publications::Tuple)
    shape = _candidate_workspace_shape(
        first(ports), first(publications).law)
    return (shape, _candidate_port_shapes(
        Base.tail(ports), Base.tail(publications))...)
end

function _candidate_stage_workspace_spec(
    stage; path::Tuple, name_prefix::Symbol)
    ports = _candidate_port_workspace_specs(
        stage, stage.publications, path, name_prefix, 1)
    port_shapes = _candidate_port_shapes(ports, stage.publications)
    status_name = Symbol(name_prefix, :_status)
    status_leaf = _workspace_leaf(status_name, (path..., :status), Int32,
        (1,); role = :candidate_stage_diagnostic)
    route_invalid_name = Symbol(name_prefix, :_route_invalid)
    route_invalid_leaf = _workspace_leaf(route_invalid_name,
        (path..., :route_invalid), Int32, (length(stage.publications),);
        role = :candidate_invalid_route_ordinal)
    validation_name = Symbol(name_prefix, :_validation)
    validation_leaf = _workspace_leaf(validation_name, (path..., :validation),
        UInt32, (_VALIDATION_STATUS_FIELDS, 1); role = :validation_status)
    template = (
        publications = _candidate_port_templates(ports),
        status = _WorkspaceLeafSlot(status_name),
        route_invalid = _WorkspaceLeafSlot(route_invalid_name),
        validation = _WorkspaceLeafSlot(validation_name),
    )
    return (
        leaves = (_candidate_port_leaves(ports)...,
        status_leaf, route_invalid_leaf, validation_leaf),
        template,
        ports = port_shapes,
        root_path = path,
    )
end

_candidate_workspace_from_tree(tree, spec, ::Unique) =
    _CountedUniqueWorkspace(
        tree.destinations, tree.values, tree.counts, tree.winners,
        tree.invalid_ordinal, spec.candidate_count, spec.destination_count)

function _candidate_local_workspace_leaf(
        leaf::_WorkspaceLeaf, root_path::Tuple)
    prefix_length = length(root_path)
    length(leaf.path) >= prefix_length &&
        leaf.path[1:prefix_length] == root_path || error(
        "candidate-stage workspace leaf is outside its declared root")
    local_path = leaf.path[(prefix_length + 1):end]
    return _workspace_leaf(leaf.name, local_path, leaf.element_type, leaf.size;
        strides = leaf.strides, role = leaf.role)
end

@generated function _candidate_stage_workspace_from_tree(
        tree::Tree, spec::Spec, stage::Stage) where {Tree,Spec,Stage}
    port_count = length(fieldtype(Spec, :ports).parameters)
    leaf_count = fieldcount(fieldtype(Spec, :leaves))
    workspace_values = [:(
        _candidate_workspace_from_tree(
            getfield(getfield(tree, :publications), $index),
            getfield(getfield(spec, :ports), $index),
            getfield(getfield(stage, :publications), $index).law))
        for index in 1:port_count]
    leaf_values = [:(
        _candidate_local_workspace_leaf(
            getfield(getfield(spec, :leaves), $index),
            getfield(spec, :root_path))) for index in 1:leaf_count]
    return quote
        workspaces = ($(workspace_values...),)
        local_leaves = ($(leaf_values...),)
        authority = _WorkspaceAuthority(local_leaves, getfield(spec, :template))
        _CandidateStageWorkspace(_CANDIDATE_STAGE_WORKSPACE_SEAL,
            workspaces, getfield(tree, :status), getfield(tree, :validation),
            tree, authority)
    end
end

function _require_candidate_workspace_match(
        stage, publication::_PreparedStagePublication{C,<:Unique},
        workspace::_CountedUniqueWorkspace) where {C}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :unique_candidate_capacity)
    T = _unique_value_type(publication.law)
    workspace.candidate_count == candidates &&
        workspace.destination_count == destination_count &&
        length(workspace.destinations) == candidates &&
        eltype(workspace.destinations) === Int32 &&
        length(workspace.values) == candidates && eltype(workspace.values) === T &&
        length(workspace.counts) == destination_count &&
        eltype(workspace.counts) === Int32 &&
        length(workspace.winners) == destination_count &&
        eltype(workspace.winners) === Int32 &&
        length(workspace.invalid_ordinal) == 1 || throw(
        LocalMathValidationError(
            "Unique workspace does not match its admitted publication";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destination_count, T),
            actual = (workspace.candidate_count, workspace.destination_count,
                length(workspace.values), eltype(workspace.values))))
    return nothing
end

function _require_destination_grouping_match(
        grouping, candidates::Integer, destination_count::Integer;
        ordering::Type = _OrdinalCandidateOrder)
    sort_capacity = _destination_grouping_capacity(candidates)
    merge_passes = sort_capacity <= _DESTINATION_GROUP_BLOCK ? 0 :
        ceil(Int, log2(cld(sort_capacity, _DESTINATION_GROUP_BLOCK)))
    grouping.candidate_count == candidates &&
        grouping.destination_count == destination_count &&
        grouping.sort_capacity == sort_capacity &&
        grouping.merge_passes == merge_passes &&
        grouping.ordering isa ordering &&
        eltype(grouping.destinations) === Int32 &&
        eltype(grouping.valid) === UInt8 &&
        eltype(grouping.order_a) === Int32 &&
        eltype(grouping.order_b) === Int32 &&
        eltype(grouping.starts) === Int32 &&
        eltype(grouping.invalid_ordinal) === Int32 &&
        length(grouping.destinations) == candidates &&
        length(grouping.valid) == candidates &&
        length(grouping.order_a) == sort_capacity &&
        length(grouping.order_b) == sort_capacity &&
        length(grouping.starts) == destination_count + 1 &&
        length(grouping.invalid_ordinal) == 1 || throw(
        LocalMathValidationError(
            "destination-grouping workspace does not match its admitted publication";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destination_count, sort_capacity,
                merge_passes, Int32, UInt8),
            actual = (grouping.candidate_count,
                grouping.destination_count, grouping.sort_capacity,
                grouping.merge_passes)))
    return nothing
end

function _require_candidate_workspace_matches(
        stage, publications::Tuple, workspaces::Tuple)
    length(publications) == length(workspaces) || throw(
        LocalMathValidationError(
            "candidate preparation requires one workspace per publication";
            stage = :prepare, contract = :candidate_workspace_arity,
            expected = length(publications), actual = length(workspaces)))
    for index in eachindex(publications)
        applicable(_require_candidate_workspace_match,
            stage, publications[index], workspaces[index]) || throw(
            LocalMathValidationError(
                "candidate workspace physical specialization does not match its law";
                stage = :prepare,
                contract = :candidate_workspace_specialization,
                expected = typeof(publications[index].law),
                actual = typeof(workspaces[index])))
        _require_candidate_workspace_match(
            stage, publications[index], workspaces[index])
    end
    return nothing
end

function _require_candidate_publication_capabilities(
        backend, publication::_PreparedStagePublication{C,<:Unique}) where {C}
    _centrally_qualified_atomic_capability(backend, Int32, :add, :global) &&
        _centrally_qualified_atomic_capability(
            backend, Int32, :min, :global) || throw(LocalMathValidationError(
        "the backend lacks exact counted Unique atomics";
        stage = :prepare, contract = :unique_backend_capability,
        expected = (Int32, :atomic_add, :atomic_min),
        actual = typeof(backend)))
    value_type = _unique_value_type(publication.law)
    scalar_storage = all(operation -> _centrally_qualified_value_capability(
        backend, value_type, operation, :global), (:load, :store))
    record_storage = all(operation -> _centrally_qualified_stage_record(
        backend, value_type, operation), (:load, :store))
    (scalar_storage || record_storage) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed Unique candidate-value capability";
            stage = :prepare, contract = :unique_backend_capability,
            expected = (value_type, :load, :store),
            actual = typeof(backend)))
    return nothing
end

function _require_candidate_stage_capabilities(backend, stage)
    _centrally_qualified_atomic_capability(
        backend, Int32, :max, :global) &&
        all(operation -> _centrally_qualified_value_capability(
            backend, Int32, operation, :global), (:load, :store)) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed candidate-stage diagnostic capability";
            stage = :prepare,
            contract = :candidate_stage_backend_capability,
            expected = (Int32, :load, :store, :atomic_max),
            actual = typeof(backend)))
    foreach(publication -> _require_candidate_publication_capabilities(
        backend, publication), stage.publications)
    return nothing
end

function _prepare_candidate_stage(
        admission::_StageAdmission, workspace::_CandidateStageWorkspace)
    stage = admission.stage
    _require_candidate_stage_capabilities(admission.backend, stage)
    length(workspace.status) == 1 && eltype(workspace.status) === Int32 ||
        throw(LocalMathValidationError(
            "candidate-stage status workspace has the wrong exact schema";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (Int32, (1,)),
            actual = (eltype(workspace.status), size(workspace.status))))
    length(workspace.route_invalid) == length(stage.publications) &&
        eltype(workspace.route_invalid) === Int32 || throw(
        LocalMathValidationError(
            "candidate route diagnostic workspace has the wrong exact schema";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (Int32, (length(stage.publications),)),
            actual = (eltype(workspace.route_invalid),
                size(workspace.route_invalid))))
    eltype(workspace.validation) === UInt32 &&
        size(workspace.validation, 1) == _VALIDATION_STATUS_FIELDS || throw(
        LocalMathValidationError(
            "candidate-stage validation status has the wrong exact schema";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (UInt32, _VALIDATION_STATUS_FIELDS, :lease_columns),
            actual = (eltype(workspace.validation), size(workspace.validation))))
    _require_candidate_workspace_matches(
        stage, stage.publications, workspace.publications)
    execution = _CandidateStageExecution(
        stage, workspace.publications, workspace.status,
        workspace.route_invalid)
    return _CandidateStagePreparation(admission.backend, execution,
        workspace.validation)
end

function _candidate_launch_extent(qualified, workspaces)
    extent = Int(qualified.stage.source_count)
    for workspace in workspaces
        extent = max(extent, _candidate_workspace_extent(workspace))
    end
    return max(extent, 1)
end

struct _CandidateDiagnostic
    context::Int32
    primary::Int32
    secondary::Int32
    witness::UInt32
end
@inline _candidate_no_diagnostic() = _CandidateDiagnostic(
    Int32(0), Int32(0), Int32(0), UInt32(0))
@inline _candidate_source_item(publication, ordinal::Int32) = Int32(
    div(ordinal - Int32(1), Int32(_publication_width(publication.law))) + 1)

@inline function _candidate_unique_diagnostic(publication,
        workspace::_CountedUniqueWorkspace, code::Int32, context::Int32)
    if code == _CANDIDATE_STATUS_CONFLICT
        for destination in Int32(1):workspace.destination_count
            @inbounds(workspace.counts[destination]) > 1 || continue
            first_ordinal = @inbounds workspace.winners[destination]
            second_ordinal = typemax(Int32)
            for ordinal in Int32(1):workspace.candidate_count
                ordinal != first_ordinal &&
                    @inbounds(workspace.destinations[ordinal]) == destination &&
                    (second_ordinal = ordinal; break)
            end
            return _CandidateDiagnostic(context,
                _candidate_source_item(publication, first_ordinal),
                second_ordinal, reinterpret(UInt32, destination))
        end
    elseif code == _CANDIDATE_STATUS_COVERAGE
        for destination in Int32(1):workspace.destination_count
            @inbounds(workspace.counts[destination]) == 0 &&
                return _CandidateDiagnostic(
                    context, destination, Int32(0), UInt32(0))
        end
    elseif code == _CANDIDATE_STATUS_RELATION
        ordinal = @inbounds workspace.invalid_ordinal[1]
        ordinal == typemax(Int32) || return _CandidateDiagnostic(context,
            _candidate_source_item(publication, ordinal), ordinal,
            reinterpret(UInt32,
                @inbounds(workspace.destinations[ordinal])))
    end
    return _candidate_no_diagnostic()
end

@inline _candidate_publication_diagnostic(
    publication::_PreparedStagePublication{C,<:Unique}, workspace,
    code::Int32, context::Int32) where {C} =
    _candidate_unique_diagnostic(publication, workspace, code, context)

@inline function _candidate_route_diagnostic(publication, workspace,
        ordinal::Int32, context::Int32)
    ordinal == typemax(Int32) && return _candidate_no_diagnostic()
    return _CandidateDiagnostic(context,
        _candidate_source_item(publication, ordinal), ordinal,
        reinterpret(UInt32,
            @inbounds(_candidate_route_destinations(workspace)[ordinal])))
end

@inline function _candidate_diagnostic(publications::Tuple,
        workspaces::Tuple, routes, code::Int32, context::Int32 = Int32(1))
    isempty(publications) && return _candidate_no_diagnostic()
    diagnostic = code == _CANDIDATE_STATUS_ROUTE_KEY ?
        _candidate_route_diagnostic(first(publications), first(workspaces),
            @inbounds(routes[context]), context) :
        _candidate_publication_diagnostic(first(publications),
            first(workspaces), code, context)
    diagnostic.context != 0 && return diagnostic
    return _candidate_diagnostic(Base.tail(publications),
        Base.tail(workspaces), routes, code, context + Int32(1))
end

@inline _candidate_publication_diagnostic(publication, workspace,
    code::Int32, context::Int32) = _candidate_no_diagnostic()

"""Enqueue one candidate Stage on the provider tail; never synchronize here."""
function _execute_candidate_stage!(prepared::_CandidateStagePreparation,
        parameters::Tuple, lease_index::Int32, predecessors::Tuple,
        relation_guard, program_validation)
    backend, execution = prepared.backend, prepared.execution
    qualified = _QualifiedEvaluation(_stage_evaluation(execution.stage),
        _stage_runtime_parameters(parameters, execution.stage))
    workspaces = execution.workspaces
    diagnostics = _CandidateDiagnostics(
        execution.status, execution.route_invalid)
    phase = _CandidatePublicationPhase(execution.stage.publications,
        execution.stage.fields, execution.stage.control.gate)
    gate_parameters = (; gate = qualified.parameters.gate)
    predecessor_statuses = (relation_guard, predecessors...)
    extent = _candidate_launch_extent(qualified, workspaces)
    _candidate_stage_reset_kernel!(backend)(
        workspaces, diagnostics, prepared.validation, relation_guard,
        lease_index,
        Int32(extent); ndrange = extent)
    _launch_stage_relation_receipt_after_reset!(backend, relation_guard,
        prepared.validation, program_validation, lease_index)
    _candidate_stage_evaluate_kernel!(backend)(qualified,
        execution.stage.publications, workspaces, diagnostics,
        predecessor_statuses, lease_index;
        ndrange = max(Int(execution.stage.source_count), 1))
    foreach(workspace -> _group_candidate_workspace!(backend, workspace),
        workspaces)
    _candidate_stage_validate_kernel!(backend)(
        phase, gate_parameters, workspaces, diagnostics,
        predecessor_statuses, lease_index, Int32(extent); ndrange = extent)
    _candidate_phase_required(execution.stage.publications,
        _candidate_atomic_initialization_required) &&
        _candidate_stage_atomic_initialize_kernel!(backend)(phase,
            gate_parameters, workspaces, diagnostics.status,
            predecessor_statuses, lease_index, Int32(extent); ndrange = extent)
    _candidate_phase_required(execution.stage.publications,
        _candidate_atomic_required) &&
        _candidate_stage_atomic_kernel!(backend)(phase, gate_parameters,
            workspaces, diagnostics.status, predecessor_statuses,
            lease_index, Int32(extent); ndrange = extent)
    _candidate_stage_publish_kernel!(backend)(phase, gate_parameters,
        workspaces, diagnostics, prepared.validation, program_validation,
        predecessor_statuses, lease_index, Int32(extent); ndrange = extent)
    return prepared
end
