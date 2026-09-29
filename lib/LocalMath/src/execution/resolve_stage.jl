# Resolve specialization of the common buffered candidate-stage spine.
# Canonical ties are the intrinsic item-major/lane-minor ordinal. Explicit
# ties use the same destination segmentation sort with a physical rank/tie
# policy so duplicate complete keys are adjacent and deterministically found.

struct _ResolveCandidateOrder{R,I}
    ranks::R
    ties::I
end
Adapt.@adapt_structure _ResolveCandidateOrder

@inline function _intra_destination_precedes(
        order::_ResolveCandidateOrder, left::Int32, right::Int32)
    rank_comparison = _rank_compare(
        @inbounds(order.ranks[left]), @inbounds(order.ranks[right]))
    rank_comparison != 0 && return rank_comparison < 0
    tie_comparison = _rank_compare(
        @inbounds(order.ties[left]), @inbounds(order.ties[right]))
    tie_comparison != 0 && return tie_comparison < 0
    return left < right
end

struct _CanonicalResolveWorkspace{G,R,V,X}
    grouping::G
    ranks::R
    values::V
    invalid_rank_ordinal::X
end

struct _ExplicitResolveWorkspace{G,V,X}
    grouping::G
    values::V
    invalid_rank_ordinal::X
end

"""Exact two-pass Resolve for 32-bit ranks with intrinsic ordinal ties."""
struct _AtomicCanonicalResolveWorkspace{D,R,V,B,W,X,Y,L}
    destinations::D
    ranks::R
    values::V
    best_ranks::B
    winners::W
    invalid_rank_ordinal::X
    invalid_relation_ordinal::Y
    direction::L
    candidate_count::Int32
    destination_count::Int32
end

Adapt.@adapt_structure _CanonicalResolveWorkspace
Adapt.@adapt_structure _ExplicitResolveWorkspace
Adapt.@adapt_structure _AtomicCanonicalResolveWorkspace

_atomic_canonical_resolve(::Resolve{R,I,T,K,D,<:CanonicalSourceLaneTie}) where {
    R<:Union{Int32,UInt32},I,T,K,D} = true
_atomic_canonical_resolve(::Resolve) = false

@inline _resolve_rank_identity(::Type{R}, ::ArgMin) where {R} = typemax(R)
@inline _resolve_rank_identity(::Type{R}, ::ArgMax) where {R} = typemin(R)
@inline _resolve_rank_claim!(array, index, value, ::ArgMin) =
    _candidate_atomic_min!(array, index, value)
@inline _resolve_rank_claim!(array, index, value, ::ArgMax) =
    _candidate_atomic_max!(array, index, value)

@inline _resolve_ranks(workspace::_CanonicalResolveWorkspace) = workspace.ranks
@inline _resolve_ranks(workspace::_ExplicitResolveWorkspace) =
    workspace.grouping.ordering.ranks
@inline _resolve_ties(workspace::_ExplicitResolveWorkspace) =
    workspace.grouping.ordering.ties

@inline function _claim_resolve_lane!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::_CanonicalResolveWorkspace, candidate, fields, item,
        ::Val{L}, execution, context::Int32,
    ) where {C,R,I,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    if !candidate.participates
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        return nothing
    end
    if !_rank_in_bounds(
            candidate.rank, publication.law.lower, publication.law.upper)
        @inbounds workspace.ranks[ordinal] = candidate.rank
        _candidate_atomic_min!(
            workspace.invalid_rank_ordinal, 1, ordinal)
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        return nothing
    end
    component = first(publication.components)
    if !_relation_keys_valid(component.relation, fields, item)
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    participates = endpoint.present && !endpoint.exterior
    @inbounds workspace.grouping.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.grouping.destinations[ordinal] = endpoint.index
            workspace.ranks[ordinal] = candidate.rank
            workspace.values[ordinal] = candidate.value
        end
    end
    return nothing
end

@inline function _claim_resolve_lane!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::_AtomicCanonicalResolveWorkspace, candidate, fields, item,
        ::Val{L}, execution, context::Int32,
    ) where {C,R,I,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.destinations[ordinal] = Int32(0)
    candidate.participates || return nothing
    if !_rank_in_bounds(
            candidate.rank, publication.law.lower, publication.law.upper)
        @inbounds workspace.ranks[ordinal] = candidate.rank
        _candidate_atomic_min!(workspace.invalid_rank_ordinal, 1, ordinal)
        return nothing
    end
    component = first(publication.components)
    if !_relation_keys_valid(component.relation, fields, item)
        _candidate_atomic_min!(workspace.invalid_relation_ordinal, 1, ordinal)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    if endpoint.present && !endpoint.exterior
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.ranks[ordinal] = candidate.rank
            workspace.values[ordinal] = candidate.value
        end
        _resolve_rank_claim!(workspace.best_ranks, endpoint.index,
            candidate.rank, workspace.direction)
    end
    return nothing
end

@inline function _claim_resolve_lane!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::_ExplicitResolveWorkspace, candidate, fields, item,
        ::Val{L}, execution, context::Int32,
    ) where {C,R,I,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    if !candidate.participates
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        return nothing
    end
    if !_rank_in_bounds(
            candidate.rank, publication.law.lower, publication.law.upper)
        @inbounds _resolve_ranks(workspace)[ordinal] = candidate.rank
        _candidate_atomic_min!(
            workspace.invalid_rank_ordinal, 1, ordinal)
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        return nothing
    end
    component = first(publication.components)
    if !_relation_keys_valid(component.relation, fields, item)
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    participates = endpoint.present && !endpoint.exterior
    @inbounds workspace.grouping.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.grouping.destinations[ordinal] = endpoint.index
            _resolve_ranks(workspace)[ordinal] = candidate.rank
            _resolve_ties(workspace)[ordinal] = candidate.tie
            workspace.values[ordinal] = candidate.value
        end
    end
    return nothing
end


@inline function _claim_routed_resolve_lane!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::Union{_CanonicalResolveWorkspace,_ExplicitResolveWorkspace},
        candidate::RoutedResolutionValue, fields, item, ::Val{L}, execution,
        context::Int32,
    ) where {C,R,I,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
    candidate.participates || return nothing
    if !_rank_in_bounds(
            candidate.rank, publication.law.lower, publication.law.upper)
        @inbounds _resolve_ranks(workspace)[ordinal] = candidate.rank
        _candidate_atomic_min!(workspace.invalid_rank_ordinal, 1, ordinal)
        return nothing
    end
    component = first(publication.components)
    endpoint = _runtime_route_endpoint!(execution, workspace,
        component.relation, fields, candidate.key, ordinal, context)
    participates = endpoint.present && !endpoint.exterior
    @inbounds workspace.grouping.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.grouping.destinations[ordinal] = endpoint.index
            _resolve_ranks(workspace)[ordinal] = candidate.rank
            workspace.values[ordinal] = candidate.value
        end
        if workspace isa _ExplicitResolveWorkspace
            @inbounds _resolve_ties(workspace)[ordinal] = candidate.tie
        end
    end
    return nothing
end

@inline _claim_resolve_lane!(
    publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
    workspace::_CanonicalResolveWorkspace,
    candidate::RoutedResolutionValue, fields, item, lane::Val{L}, execution,
    context::Int32,
) where {C,R,I,T,K,L} = _claim_routed_resolve_lane!(
    publication, workspace, candidate, fields, item, lane, execution, context)

@inline function _claim_resolve_lane!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::_AtomicCanonicalResolveWorkspace,
        candidate::RoutedResolutionValue, fields, item, ::Val{L}, execution,
        context::Int32,
    ) where {C,R,I,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.destinations[ordinal] = Int32(0)
    candidate.participates || return nothing
    if !_rank_in_bounds(
            candidate.rank, publication.law.lower, publication.law.upper)
        @inbounds workspace.ranks[ordinal] = candidate.rank
        _candidate_atomic_min!(workspace.invalid_rank_ordinal, 1, ordinal)
        return nothing
    end
    endpoint = _runtime_route_endpoint!(execution, workspace,
        first(publication.components).relation, fields, candidate.key,
        ordinal, context)
    if endpoint.present && !endpoint.exterior
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.ranks[ordinal] = candidate.rank
            workspace.values[ordinal] = candidate.value
        end
        _resolve_rank_claim!(workspace.best_ranks, endpoint.index,
            candidate.rank, workspace.direction)
    end
    return nothing
end

@inline _claim_resolve_lane!(
    publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
    workspace::_ExplicitResolveWorkspace,
    candidate::RoutedResolutionValue, fields, item, lane::Val{L}, execution,
    context::Int32,
) where {C,R,I,T,K,L} = _claim_routed_resolve_lane!(
    publication, workspace, candidate, fields, item, lane, execution, context)

@generated function _claim_publication!(
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T,K}},
        workspace::Union{
            _CanonicalResolveWorkspace,_ExplicitResolveWorkspace,
            _AtomicCanonicalResolveWorkspace},
        port, fields, item, execution, context::Int32,
    ) where {C,R,I,T,K}
    calls = Any[]
    for lane in 1:K
        candidate = K == 1 ? :port : :(getfield(port, $lane))
        push!(calls, :(_claim_resolve_lane!(publication, workspace,
            $candidate, fields, item, Val($lane), execution, context)))
    end
    return Expr(:block, calls..., :(nothing))
end

@inline function _reset_candidate_payload!(workspace::Union{
        _CanonicalResolveWorkspace,_ExplicitResolveWorkspace}, index)
    index == 1 && (@inbounds workspace.invalid_rank_ordinal[1] =
        typemax(Int32))
    return nothing
end

@inline function _reset_candidate_payload!(
        workspace::_AtomicCanonicalResolveWorkspace, index)
    if index <= workspace.candidate_count
        @inbounds workspace.destinations[index] = Int32(0)
    end
    if index <= workspace.destination_count
        @inbounds begin
            workspace.best_ranks[index] = _resolve_rank_identity(
                eltype(workspace.best_ranks), workspace.direction)
            workspace.winners[index] = typemax(Int32)
        end
    end
    if index == 1
        @inbounds begin
            workspace.invalid_rank_ordinal[1] = typemax(Int32)
            workspace.invalid_relation_ordinal[1] = typemax(Int32)
        end
    end
    return nothing
end

@inline _reset_candidate_grouping_index!(
    workspace::Union{_CanonicalResolveWorkspace,_ExplicitResolveWorkspace},
    index) = _reset_destination_grouping_index!(workspace.grouping, index)
@inline _group_candidate_workspace!(backend,
    workspace::Union{_CanonicalResolveWorkspace,_ExplicitResolveWorkspace}) =
    _group_destinations!(backend, workspace.grouping)
@inline _candidate_workspace_extent(workspace::Union{
    _CanonicalResolveWorkspace,_ExplicitResolveWorkspace}) =
    max(Int(workspace.grouping.sort_capacity),
        Int(workspace.grouping.candidate_count),
        Int(workspace.grouping.destination_count) + 1)

@inline _reset_candidate_grouping_index!(
    workspace::_AtomicCanonicalResolveWorkspace, index) = nothing
@inline _candidate_workspace_extent(workspace::_AtomicCanonicalResolveWorkspace) =
    max(Int(workspace.candidate_count), Int(workspace.destination_count))
@inline _candidate_route_destinations(
    workspace::_AtomicCanonicalResolveWorkspace) = workspace.destinations

@kernel function _atomic_resolve_winner_kernel!(workspace)
    raw_ordinal = @index(Global, Linear)
    ordinal = Int32(raw_ordinal)
    if ordinal <= workspace.candidate_count
        destination = @inbounds workspace.destinations[ordinal]
        if destination > 0 && _rank_equal(
                @inbounds(workspace.ranks[ordinal]),
                @inbounds(workspace.best_ranks[destination]))
            _candidate_atomic_min!(workspace.winners, destination, ordinal)
        end
    end
end

@inline function _group_candidate_workspace!(backend,
        workspace::_AtomicCanonicalResolveWorkspace)
    _atomic_resolve_winner_kernel!(backend)(workspace;
        ndrange = max(Int(workspace.candidate_count), 1))
    return workspace
end

@inline function _resolve_grouping_failure!(workspace, execution, index)
    if index == 1
        !_destination_grouping_success(workspace.grouping) &&
            _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        @inbounds(workspace.invalid_rank_ordinal[1]) == typemax(Int32) ||
            _candidate_fail!(execution, _CANDIDATE_FAILURE_RANK_BOUNDS)
    end
    return nothing
end

@inline function _validate_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::_CanonicalResolveWorkspace, execution, index,
    ) where {C}
    _resolve_grouping_failure!(workspace, execution, index)
    return nothing
end

@inline function _validate_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::_AtomicCanonicalResolveWorkspace, execution, index,
    ) where {C}
    if index == 1
        @inbounds(workspace.invalid_rank_ordinal[1]) == typemax(Int32) ||
            _candidate_fail!(execution, _CANDIDATE_FAILURE_RANK_BOUNDS)
        @inbounds(workspace.invalid_relation_ordinal[1]) == typemax(Int32) ||
            _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
    end
    return nothing
end

@inline function _candidate_publication_diagnostic(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::Union{_CanonicalResolveWorkspace,_ExplicitResolveWorkspace},
        code::Int32, context::Int32) where {C}
    if code == _CANDIDATE_STATUS_RANK_BOUNDS
        ordinal = @inbounds workspace.invalid_rank_ordinal[1]
        ordinal == typemax(Int32) || return _CandidateDiagnostic(context,
            _candidate_source_item(publication, ordinal), ordinal, UInt32(0))
    elseif code == _CANDIDATE_STATUS_RELATION
        ordinal = @inbounds workspace.grouping.invalid_ordinal[1]
        ordinal == typemax(Int32) || return _CandidateDiagnostic(context,
            _candidate_source_item(publication, ordinal), ordinal,
            reinterpret(UInt32,
                @inbounds(workspace.grouping.destinations[ordinal])))
    elseif code == _CANDIDATE_STATUS_DUPLICATE_TIE &&
            workspace isa _ExplicitResolveWorkspace
        grouping = workspace.grouping
        order = _destination_grouping_order(grouping)
        for position in Int32(2):grouping.candidate_count
            previous = @inbounds order[position - Int32(1)]
            current = @inbounds order[position]
            if previous != 0 && current != 0 &&
                    @inbounds(grouping.valid[previous] != UInt8(0)) &&
                    @inbounds(grouping.valid[current] != UInt8(0)) &&
                    @inbounds(grouping.destinations[previous]) ==
                        @inbounds(grouping.destinations[current]) &&
                    _rank_equal(@inbounds(_resolve_ranks(workspace)[previous]),
                        @inbounds(_resolve_ranks(workspace)[current])) &&
                    _rank_equal(@inbounds(_resolve_ties(workspace)[previous]),
                        @inbounds(_resolve_ties(workspace)[current]))
                return _CandidateDiagnostic(context,
                    _candidate_source_item(publication, previous), current,
                    reinterpret(UInt32,
                        @inbounds(grouping.destinations[current])))
            end
        end
    end
    return _candidate_no_diagnostic()
end

@inline function _candidate_publication_diagnostic(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::_AtomicCanonicalResolveWorkspace,
        code::Int32, context::Int32) where {C}
    ordinal = if code == _CANDIDATE_STATUS_RANK_BOUNDS
        @inbounds workspace.invalid_rank_ordinal[1]
    elseif code == _CANDIDATE_STATUS_RELATION
        @inbounds workspace.invalid_relation_ordinal[1]
    else
        typemax(Int32)
    end
    ordinal == typemax(Int32) && return _candidate_no_diagnostic()
    witness = code == _CANDIDATE_STATUS_RELATION ? reinterpret(UInt32,
        @inbounds(workspace.destinations[ordinal])) : UInt32(0)
    return _CandidateDiagnostic(context,
        _candidate_source_item(publication, ordinal), ordinal, witness)
end

@inline function _validate_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::_ExplicitResolveWorkspace, execution, position,
    ) where {C}
    _resolve_grouping_failure!(workspace, execution, position)
    grouping = workspace.grouping
    if 2 <= position <= grouping.candidate_count
        order = _destination_grouping_order(grouping)
        previous = @inbounds order[position - 1]
        current = @inbounds order[position]
        if previous != 0 && current != 0 &&
                @inbounds(grouping.valid[previous] != UInt8(0)) &&
                @inbounds(grouping.valid[current] != UInt8(0)) &&
                @inbounds(grouping.destinations[previous]) ==
                    @inbounds(grouping.destinations[current]) &&
                _rank_equal(@inbounds(_resolve_ranks(workspace)[previous]),
                    @inbounds(_resolve_ranks(workspace)[current])) &&
                _rank_equal(@inbounds(_resolve_ties(workspace)[previous]),
                    @inbounds(_resolve_ties(workspace)[current]))
            _candidate_fail!(execution, _CANDIDATE_FAILURE_DUPLICATE_TIE)
        end
    end
    return nothing
end

@inline _resolve_rank_better(left, right, ::ArgMin) =
    _rank_better(left, right, Val(:min))
@inline _resolve_rank_better(left, right, ::ArgMax) =
    _rank_better(left, right, Val(:max))
@inline _resolve_tie_better(left, right, ::TieMin) =
    _rank_better(left, right, Val(:min))
@inline _resolve_tie_better(left, right, ::TieMax) =
    _rank_better(left, right, Val(:max))

@inline function _resolve_candidate_better(
        workspace::_CanonicalResolveWorkspace, law, candidate, winner)
    candidate_rank = @inbounds workspace.ranks[candidate]
    winner_rank = @inbounds workspace.ranks[winner]
    return _resolve_rank_better(
        candidate_rank, winner_rank, law.direction) ||
        (_rank_equal(candidate_rank, winner_rank) && candidate < winner)
end

@inline function _resolve_candidate_better(
        workspace::_ExplicitResolveWorkspace, law, candidate, winner)
    candidate_rank = @inbounds _resolve_ranks(workspace)[candidate]
    winner_rank = @inbounds _resolve_ranks(workspace)[winner]
    rank_better = _resolve_rank_better(
        candidate_rank, winner_rank, law.direction)
    rank_better && return true
    _rank_equal(candidate_rank, winner_rank) || return false
    return _resolve_tie_better(
        @inbounds(_resolve_ties(workspace)[candidate]),
        @inbounds(_resolve_ties(workspace)[winner]), law.tie)
end

@inline function _atomic_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::Union{
            _CanonicalResolveWorkspace,_ExplicitResolveWorkspace}, ordinal,
    ) where {C}
    return nothing
end
@inline _atomic_publication!(
    publication::_PreparedStagePublication{C,<:Resolve},
    workspace::_AtomicCanonicalResolveWorkspace, ordinal) where {C} = nothing

@inline function _publish_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::Union{
            _CanonicalResolveWorkspace,_ExplicitResolveWorkspace},
        fields, destination_index,
    ) where {C}
    destination_index <= workspace.grouping.destination_count || return nothing
    component = first(publication.components)
    slot = _relation_target_slot(component.relation.view)
    destination = _prepared_stage_field(fields, slot)
    first_index = @inbounds workspace.grouping.starts[destination_index]
    stop_index = @inbounds workspace.grouping.starts[destination_index + 1]
    winner = Int32(0)
    order = _destination_grouping_order(workspace.grouping)
    position = first_index
    while position < stop_index
        candidate = @inbounds order[position]
        (winner == 0 || _resolve_candidate_better(
            workspace, publication.law, candidate, winner)) &&
            (winner = candidate)
        position += Int32(1)
    end
    if winner == 0
        _candidate_empty_write!(
            destination, destination_index, publication.law.onempty)
    else
        @inbounds destination[destination_index] = workspace.values[winner]
    end
    return nothing
end

@inline function _publish_publication!(
        publication::_PreparedStagePublication{C,<:Resolve},
        workspace::_AtomicCanonicalResolveWorkspace,
        fields, destination_index,
    ) where {C}
    destination_index <= workspace.destination_count || return nothing
    component = first(publication.components)
    destination = _prepared_stage_field(
        fields, _relation_target_slot(component.relation.view))
    winner = @inbounds workspace.winners[destination_index]
    if winner == typemax(Int32)
        _candidate_empty_write!(
            destination, destination_index, publication.law.onempty)
    else
        @inbounds destination[destination_index] = workspace.values[winner]
    end
    return nothing
end

function _resolve_workspace_payload(::Val{false}, ::Type{R}, ::Type{I},
    ::Type{T}, candidates::Int, destination_count::Int,
    path::Tuple, name_prefix::Symbol) where {R,I,T}
    names = (
        ranks = Symbol(name_prefix, :_ranks),
        values = Symbol(name_prefix, :_values),
        invalid_rank_ordinal = Symbol(name_prefix, :_invalid_rank_ordinal),
    )
    leaves = (
        _workspace_leaf(names.ranks, (path..., :ranks), R, (candidates,);
            role = :resolve_candidate_rank),
        _workspace_leaf(names.values, (path..., :values), T, (candidates,);
            role = :resolve_candidate_value),
        _workspace_leaf(names.invalid_rank_ordinal,
            (path..., :invalid_rank_ordinal), Int32, (1,);
            role = :resolve_invalid_rank),
    )
    template = (
        ranks = _WorkspaceLeafSlot(names.ranks),
        values = _WorkspaceLeafSlot(names.values),
        invalid_rank_ordinal = _WorkspaceLeafSlot(names.invalid_rank_ordinal),
    )
    return (; leaves, template)
end

function _resolve_workspace_payload(::Val{true}, ::Type{R}, ::Type{I},
    ::Type{T}, candidates::Int, destination_count::Int,
    path::Tuple, name_prefix::Symbol) where {R,I,T}
    names = (
        ranks = Symbol(name_prefix, :_ranks),
        ties = Symbol(name_prefix, :_ties),
        values = Symbol(name_prefix, :_values),
        invalid_rank_ordinal = Symbol(name_prefix, :_invalid_rank_ordinal),
    )
    leaves = (
        _workspace_leaf(names.ranks, (path..., :ranks), R, (candidates,);
            role = :resolve_candidate_rank),
        _workspace_leaf(names.ties, (path..., :ties), I, (candidates,);
            role = :resolve_candidate_tie),
        _workspace_leaf(names.values, (path..., :values), T, (candidates,);
            role = :resolve_candidate_value),
        _workspace_leaf(names.invalid_rank_ordinal,
            (path..., :invalid_rank_ordinal), Int32, (1,);
            role = :resolve_invalid_rank),
    )
    template = (
        ranks = _WorkspaceLeafSlot(names.ranks),
        ties = _WorkspaceLeafSlot(names.ties),
        values = _WorkspaceLeafSlot(names.values),
        invalid_rank_ordinal = _WorkspaceLeafSlot(names.invalid_rank_ordinal),
    )
    return (; leaves, template)
end

function _resolve_workspace_spec(stage,
    publication::_PreparedStagePublication{C,<:Resolve{R,I,T}};
    path::Tuple, name_prefix::Symbol, explicit_tie::Val,
) where {C,R,I,T}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :resolve_candidate_capacity)
    grouping = _destination_grouping_workspace_spec(
        candidates, destination_count; path = (path..., :grouping),
        name_prefix = Symbol(name_prefix, :_grouping))
    payload = _resolve_workspace_payload(explicit_tie, R, I, T,
        candidates, destination_count, path, name_prefix)
    template = merge((grouping = grouping.template,), payload.template)
    return (leaves = (grouping.leaves..., payload.leaves...), template,
        grouping_shape = grouping.shape)
end

function _atomic_resolve_workspace_spec(stage,
        publication::_PreparedStagePublication{C,<:Resolve{R,I,T}};
        path::Tuple, name_prefix::Symbol) where {C,R,I,T}
    candidates, destinations = _candidate_publication_dimensions(
        stage, publication, :resolve_candidate_capacity)
    names = (
        destinations = Symbol(name_prefix, :_destinations),
        ranks = Symbol(name_prefix, :_ranks),
        values = Symbol(name_prefix, :_values),
        best_ranks = Symbol(name_prefix, :_best_ranks),
        winners = Symbol(name_prefix, :_winners),
        invalid_rank = Symbol(name_prefix, :_invalid_rank_ordinal),
        invalid_relation = Symbol(name_prefix, :_invalid_relation_ordinal),
    )
    leaves = (
        _workspace_leaf(names.destinations, (path..., :destinations), Int32,
            (candidates,); role = :resolve_candidate_destination),
        _workspace_leaf(names.ranks, (path..., :ranks), R, (candidates,);
            role = :resolve_candidate_rank),
        _workspace_leaf(names.values, (path..., :values), T, (candidates,);
            role = :resolve_candidate_value),
        _workspace_leaf(names.best_ranks, (path..., :best_ranks), R,
            (destinations,); role = :resolve_destination_rank),
        _workspace_leaf(names.winners, (path..., :winners), Int32,
            (destinations,); role = :resolve_destination_winner),
        _workspace_leaf(names.invalid_rank, (path..., :invalid_rank_ordinal),
            Int32, (1,); role = :resolve_invalid_rank),
        _workspace_leaf(names.invalid_relation,
            (path..., :invalid_relation_ordinal), Int32, (1,);
            role = :resolve_invalid_relation),
    )
    template = map(name -> _WorkspaceLeafSlot(name), names)
    return (; leaves, template, candidate_count = Int32(candidates),
        destination_count = Int32(destinations), atomic_selection = true)
end

function _candidate_workspace_spec(stage,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,<:CanonicalSourceLaneTie}};
        path::Tuple, name_prefix::Symbol,
    ) where {C,R,I,T,K,D}
    _atomic_canonical_resolve(publication.law) &&
        return _atomic_resolve_workspace_spec(stage, publication;
            path, name_prefix)
    return _resolve_workspace_spec(stage, publication;
        path, name_prefix, explicit_tie = Val(false))
end
function _candidate_workspace_spec(stage,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,L}};
        path::Tuple, name_prefix::Symbol,
    ) where {C,R,I,T,K,D,L<:Union{TieMin,TieMax}}
    return _resolve_workspace_spec(stage, publication;
        path, name_prefix, explicit_tie = Val(true))
end

function _candidate_workspace_from_tree(tree, spec,
        ::Resolve{R,I,T,K,D,<:CanonicalSourceLaneTie}) where {R,I,T,K,D}
    if hasproperty(spec, :atomic_selection)
        return _AtomicCanonicalResolveWorkspace(
            tree.destinations, tree.ranks, tree.values, tree.best_ranks,
            tree.winners, tree.invalid_rank, tree.invalid_relation,
            D(), spec.candidate_count, spec.destination_count)
    end
    grouping = _destination_grouping_from_workspace(
        tree.grouping, spec.grouping_shape)
    return _CanonicalResolveWorkspace(grouping, tree.ranks, tree.values,
        tree.invalid_rank_ordinal)
end

@inline _candidate_workspace_shape(spec, ::Resolve) =
    hasproperty(spec, :atomic_selection) ?
        (atomic_selection = true,
            candidate_count = spec.candidate_count,
            destination_count = spec.destination_count) :
        (grouping_shape = spec.grouping_shape,)
function _candidate_workspace_from_tree(tree, spec,
        ::Resolve{R,I,T,K,D,L}) where {R,I,T,K,D,L<:Union{TieMin,TieMax}}
    ordering = _ResolveCandidateOrder(tree.ranks, tree.ties)
    grouping = _destination_grouping_from_workspace(
        tree.grouping, spec.grouping_shape, ordering)
    return _ExplicitResolveWorkspace(grouping, tree.values,
        tree.invalid_rank_ordinal)
end

function _require_candidate_workspace_match(stage,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,<:CanonicalSourceLaneTie}},
        workspace::_CanonicalResolveWorkspace) where {C,R,I,T,K,D}
    candidates, destinations = _candidate_publication_dimensions(
        stage, publication, :resolve_candidate_capacity)
    _require_destination_grouping_match(
        workspace.grouping, candidates, destinations)
    length(workspace.ranks) == candidates && eltype(workspace.ranks) === R &&
        length(workspace.values) == candidates && eltype(workspace.values) === T &&
        length(workspace.invalid_rank_ordinal) == 1 &&
        eltype(workspace.invalid_rank_ordinal) === Int32 || throw(
        LocalMathValidationError(
            "canonical Resolve workspace does not match its admitted law";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destinations, R, T),
            actual = (typeof(workspace.ranks), typeof(workspace.values))))
    return nothing
end

function _require_candidate_workspace_match(stage,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,<:CanonicalSourceLaneTie}},
        workspace::_AtomicCanonicalResolveWorkspace) where {C,R,I,T,K,D}
    candidates, destinations = _candidate_publication_dimensions(
        stage, publication, :resolve_candidate_capacity)
    workspace.candidate_count == candidates &&
        workspace.destination_count == destinations &&
        length(workspace.destinations) == candidates &&
        eltype(workspace.destinations) === Int32 &&
        length(workspace.ranks) == candidates && eltype(workspace.ranks) === R &&
        length(workspace.values) == candidates && eltype(workspace.values) === T &&
        length(workspace.best_ranks) == destinations &&
        eltype(workspace.best_ranks) === R &&
        length(workspace.winners) == destinations &&
        eltype(workspace.winners) === Int32 &&
        length(workspace.invalid_rank_ordinal) == 1 &&
        length(workspace.invalid_relation_ordinal) == 1 || throw(
        LocalMathValidationError(
            "atomic canonical Resolve workspace does not match its law";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destinations, R, T),
            actual = (typeof(workspace.destinations),
                typeof(workspace.best_ranks), typeof(workspace.values))))
    return nothing
end

function _require_candidate_workspace_match(stage,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,L}},
        workspace::_ExplicitResolveWorkspace) where {
            C,R,I,T,K,D,L<:Union{TieMin,TieMax}}
    candidates, destinations = _candidate_publication_dimensions(
        stage, publication, :resolve_candidate_capacity)
    _require_destination_grouping_match(
        workspace.grouping, candidates, destinations;
        ordering = _ResolveCandidateOrder)
    ranks, ties = _resolve_ranks(workspace), _resolve_ties(workspace)
    length(ranks) == candidates && eltype(ranks) === R &&
        length(ties) == candidates && eltype(ties) === I &&
        length(workspace.values) == candidates && eltype(workspace.values) === T &&
        length(workspace.invalid_rank_ordinal) == 1 &&
        eltype(workspace.invalid_rank_ordinal) === Int32 || throw(
        LocalMathValidationError(
            "explicit-tie Resolve workspace does not match its admitted law";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destinations, R, I, T),
            actual = (typeof(ranks), typeof(ties),
                typeof(workspace.values))))
    return nothing
end

function _require_resolve_value_capability(backend, ::Type{T}) where {T}
    all((:load, :store)) do operation
        _centrally_qualified_stage_storage_value(
            backend, T, operation,
        ) || _centrally_qualified_stage_record(backend, T, operation)
    end || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed Resolve value capability";
            stage = :prepare, contract = :resolve_backend_capability,
            expected = (T, :load, :store), actual = typeof(backend)))
    return nothing
end

function _require_candidate_publication_capabilities(backend,
        publication::_PreparedStagePublication{
            C,<:Resolve{R,I,T,K,D,L}}) where {C,R,I,T,K,D,L}
    if _atomic_canonical_resolve(publication.law)
        operations = D <: ArgMin ? (:min,) : (:max,)
        all(operation -> _centrally_qualified_atomic_capability(
            backend, R, operation, :global), operations) &&
            _centrally_qualified_atomic_capability(
                backend, Int32, :min, :global) || throw(
            LocalMathValidationError(
                "the backend lacks exact atomic Resolve selection";
                stage = :prepare, contract = :resolve_backend_capability,
                expected = (R, operations, Int32, :atomic_min),
                actual = typeof(backend)))
    else
        _require_destination_grouping_capabilities(backend)
    end
    _centrally_qualified_rank_type(backend, R) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed Resolve rank capability";
            stage = :prepare, contract = :resolve_rank_capability,
            expected = R, actual = typeof(backend)))
    L <: CanonicalSourceLaneTie ||
        _centrally_qualified_rank_type(backend, I) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed Resolve tie capability";
            stage = :prepare, contract = :resolve_tie_capability,
            expected = I, actual = typeof(backend)))
    _require_resolve_value_capability(backend, T)
    return nothing
end
