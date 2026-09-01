# Reduce specialization of the common buffered candidate-stage spine.
# Canonical reductions preserve exact item-major/lane-minor left-fold order.
# Relaxed reductions may reassociate only inside a private accumulator and
# publish through the same stage-wide success gate.

struct _CanonicalReduceWorkspace{G,V}
    grouping::G
    values::V
end

struct _AtomicReduceWorkspace{D,P,V,A,I}
    destinations::D
    valid::P
    values::V
    accumulator::A
    invalid_ordinal::I
    candidate_count::Int32
    destination_count::Int32
end
@inline _candidate_route_destinations(workspace::_AtomicReduceWorkspace) =
    workspace.destinations

Adapt.@adapt_structure _CanonicalReduceWorkspace
Adapt.@adapt_structure _AtomicReduceWorkspace

@inline _reduce_value(value::Contribution) = value.value
@inline _reduce_participates(value::Contribution) = value.participates

@inline function _claim_reduce_lane!(
        publication::_PreparedStagePublication{C,<:Reduce{T,K}},
        workspace::_CanonicalReduceWorkspace, value, fields, item, ::Val{L},
        execution, context::Int32,
    ) where {C,T,K,L}
    component = first(publication.components)
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    if !_relation_keys_valid(component.relation, fields, item)
        @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    participates = _reduce_participates(value) &&
        endpoint.present && !endpoint.exterior
    @inbounds workspace.grouping.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.grouping.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = _reduce_value(value)
        end
    end
    return nothing
end


@inline function _claim_reduce_lane!(
        publication::_PreparedStagePublication{C,<:Reduce{T,K}},
        workspace::_CanonicalReduceWorkspace,
        value::RoutedContribution, fields, item, ::Val{L}, execution,
        context::Int32,
    ) where {C,T,K,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.grouping.valid[ordinal] = UInt8(0)
    value.participates || return nothing
    component = first(publication.components)
    endpoint = _runtime_route_endpoint!(execution, workspace,
        component.relation, fields, value.key, ordinal, context)
    participates = endpoint.present && !endpoint.exterior
    @inbounds workspace.grouping.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.grouping.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = value.value
        end
    end
    return nothing
end

@inline function _claim_reduce_lane!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace, value, fields, item, ::Val{L},
        execution, context::Int32,
    ) where {C,T,K,F,S,L}
    component = first(publication.components)
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    if !_relation_keys_valid(component.relation, fields, item)
        @inbounds workspace.valid[ordinal] = UInt8(0)
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        return nothing
    end
    endpoint = _relation_endpoint(component.relation, fields, item, L)
    participates = _reduce_participates(value) &&
        endpoint.present && !endpoint.exterior
    @inbounds workspace.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = _reduce_value(value)
        end
    end
    return nothing
end


@inline function _claim_reduce_lane!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace,
        value::RoutedContribution, fields, item, ::Val{L}, execution,
        context::Int32,
    ) where {C,T,K,F,S,L}
    ordinal = (item - Int32(1)) * Int32(K) + Int32(L)
    @inbounds workspace.valid[ordinal] = UInt8(0)
    value.participates || return nothing
    component = first(publication.components)
    endpoint = _runtime_route_endpoint!(execution, workspace,
        component.relation, fields, value.key, ordinal, context)
    participates = endpoint.present && !endpoint.exterior
    @inbounds workspace.valid[ordinal] =
        participates ? UInt8(1) : UInt8(0)
    if participates
        @inbounds begin
            workspace.destinations[ordinal] = endpoint.index
            workspace.values[ordinal] = value.value
        end
    end
    return nothing
end

@generated function _claim_publication!(
        publication::_PreparedStagePublication{C,<:Reduce{T,K}},
        workspace::Union{_CanonicalReduceWorkspace,_AtomicReduceWorkspace},
        port, fields, item, execution, context::Int32,
    ) where {C,T,K}
    calls = Any[]
    for lane in 1:K
        value = K == 1 ? :port : :(getfield(port, $lane))
        push!(calls, :(_claim_reduce_lane!(
            publication, workspace, $value, fields, item, Val($lane),
            execution, context)))
    end
    return Expr(:block, calls..., :(nothing))
end

@inline _reset_candidate_payload!(
    workspace::_CanonicalReduceWorkspace, index) = nothing
@inline function _reset_candidate_payload!(
        workspace::_AtomicReduceWorkspace, index)
    if index <= workspace.candidate_count
        @inbounds begin
            workspace.valid[index] = UInt8(0)
            workspace.destinations[index] = Int32(0)
        end
    end
    index == 1 &&
        (@inbounds workspace.invalid_ordinal[1] = typemax(Int32))
    return nothing
end

@inline _reset_candidate_grouping_index!(
    workspace::_CanonicalReduceWorkspace, index) =
    _reset_destination_grouping_index!(workspace.grouping, index)
@inline _reset_candidate_grouping_index!(
    workspace::_AtomicReduceWorkspace, index) = nothing

@inline _group_candidate_workspace!(backend,
    workspace::_CanonicalReduceWorkspace) =
    _group_destinations!(backend, workspace.grouping)
@inline _group_candidate_workspace!(backend,
    workspace::_AtomicReduceWorkspace) = workspace

@inline _candidate_workspace_extent(workspace::_CanonicalReduceWorkspace) =
    max(Int(workspace.grouping.sort_capacity),
        Int(workspace.grouping.candidate_count),
        Int(workspace.grouping.destination_count) + 1)
@inline _candidate_workspace_extent(workspace::_AtomicReduceWorkspace) =
    max(Int(workspace.candidate_count), Int(workspace.destination_count))

@inline function _validate_publication!(
        publication::_PreparedStagePublication{C,<:Reduce},
        workspace::_CanonicalReduceWorkspace, execution, destination,
    ) where {C}
    destination == 1 && !_destination_grouping_success(workspace.grouping) &&
        _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
    return nothing
end

@inline function _candidate_publication_diagnostic(
        publication::_PreparedStagePublication{C,<:Reduce},
        workspace::_CanonicalReduceWorkspace, code::Int32,
        context::Int32) where {C}
    if code == _CANDIDATE_STATUS_RELATION
        ordinal = @inbounds workspace.grouping.invalid_ordinal[1]
        ordinal == typemax(Int32) || return _CandidateDiagnostic(context,
            _candidate_source_item(publication, ordinal), ordinal,
            reinterpret(UInt32,
                @inbounds(workspace.grouping.destinations[ordinal])))
    end
    return _candidate_no_diagnostic()
end

@inline function _candidate_publication_diagnostic(
        publication::_PreparedStagePublication{C,<:Reduce},
        workspace::_AtomicReduceWorkspace, code::Int32,
        context::Int32) where {C}
    if code == _CANDIDATE_STATUS_RELATION
        ordinal = @inbounds workspace.invalid_ordinal[1]
        ordinal == typemax(Int32) || return _CandidateDiagnostic(context,
            _candidate_source_item(publication, ordinal), ordinal,
            reinterpret(UInt32, @inbounds(workspace.destinations[ordinal])))
    end
    return _candidate_no_diagnostic()
end

@inline function _validate_publication!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace, execution, ordinal,
    ) where {C,T,K,F,S}
    if ordinal <= workspace.candidate_count &&
            @inbounds(workspace.valid[ordinal] != UInt8(0))
        destination = @inbounds workspace.destinations[ordinal]
        if destination < 1 || destination > workspace.destination_count
            _candidate_atomic_min!(
                workspace.invalid_ordinal, 1, Int32(ordinal))
            _candidate_fail!(execution, _CANDIDATE_FAILURE_RELATION)
        end
    end
    return nothing
end

@inline function _reduce_seed(
        law::Reduce{T,K,F,<:IdentitySeed}, destination, index,
    ) where {T,K,F}
    return law.seed.value
end
@inline function _reduce_seed(
        law::Reduce{T,K,F,<:ExistingSeed}, destination, index,
    ) where {T,K,F}
    return @inbounds destination[index]
end

@inline function _atomic_initialize_publication!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,<:IdentitySeed,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace, fields, destination_index,
    ) where {C,T,K,F}
    destination_index <= workspace.destination_count || return nothing
    @inbounds workspace.accumulator[destination_index] =
        publication.law.seed.value
    return nothing
end

@inline function _atomic_reduce!(array, index, value, ::typeof(+))
    Atomix.@atomic array[index] += value
    return nothing
end
@inline function _atomic_reduce!(array, index, value, ::typeof(min))
    Atomix.@atomic min(array[index], value)
    return nothing
end
@inline function _atomic_reduce!(array, index, value, ::typeof(max))
    Atomix.@atomic max(array[index], value)
    return nothing
end

@inline function _atomic_publication!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace, ordinal,
    ) where {C,T,K,F,S}
    if ordinal <= workspace.candidate_count &&
            @inbounds(workspace.valid[ordinal] != UInt8(0))
        destination = @inbounds workspace.destinations[ordinal]
        value = @inbounds workspace.values[ordinal]
        _atomic_reduce!(workspace.accumulator, destination, value,
            publication.law.operation)
    end
    return nothing
end

@inline function _atomic_publication!(
        publication::_PreparedStagePublication{C,<:Reduce},
        workspace::_CanonicalReduceWorkspace, ordinal,
    ) where {C}
    return nothing
end

@inline function _publish_publication!(
        publication::_PreparedStagePublication{C,<:Reduce},
        workspace::_CanonicalReduceWorkspace, fields, destination_index,
    ) where {C}
    grouping = workspace.grouping
    destination_index <= grouping.destination_count || return nothing
    component = first(publication.components)
    slot = _relation_target_slot(component.relation.view)
    destination = _prepared_stage_field(fields, slot)
    value = _reduce_seed(publication.law, destination, destination_index)
    first_index = @inbounds grouping.starts[destination_index]
    stop_index = @inbounds grouping.starts[destination_index + 1]
    order = _destination_grouping_order(grouping)
    position = first_index
    while position < stop_index
        ordinal = @inbounds order[position]
        value = publication.law.operation(
            value, @inbounds(workspace.values[ordinal]))
        position += Int32(1)
    end
    @inbounds destination[destination_index] = value
    return nothing
end

@inline function _publish_publication!(
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace, fields, destination_index,
    ) where {C,T,K,F,S}
    destination_index <= workspace.destination_count || return nothing
    component = first(publication.components)
    slot = _relation_target_slot(component.relation.view)
    destination = _prepared_stage_field(fields, slot)
    @inbounds destination[destination_index] =
        workspace.accumulator[destination_index]
    return nothing
end

function _candidate_workspace_spec(stage,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:CanonicalLeftFold}};
        path::Tuple, name_prefix::Symbol,
    ) where {C,T,K,F,S}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :reduce_candidate_capacity)
    grouping = _destination_grouping_workspace_spec(
        candidates, destination_count;
        path = (path..., :grouping),
        name_prefix = Symbol(name_prefix, :_grouping))
    values_name = Symbol(name_prefix, :_values)
    values_leaf = _workspace_leaf(values_name, (path..., :values), T,
        (candidates,); role = :reduce_candidate_value)
    template = (
        grouping = grouping.template,
        values = _WorkspaceLeafSlot(values_name),
    )
    return (
        leaves = (grouping.leaves..., values_leaf),
        template,
        grouping_shape = grouping.shape,
    )
end

function _candidate_workspace_spec(stage,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}};
        path::Tuple, name_prefix::Symbol,
    ) where {C,T,K,F,S}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :reduce_candidate_capacity)
    names = NamedTuple{(:destinations, :valid, :values, :accumulator,
        :invalid_ordinal)}(Tuple(Symbol(name_prefix, :_, suffix) for suffix in
        (:destinations, :valid, :values, :accumulator, :invalid_ordinal)))
    types = (Int32, UInt8, T, T, Int32)
    sizes = ((candidates,), (candidates,), (candidates,),
        (destination_count,), (1,))
    roles = (:candidate_destination, :candidate_participation,
        :reduce_candidate_value, :reduce_private_accumulator,
        :candidate_invalid_destination)
    leaves = Tuple(_workspace_leaf(
        getfield(names, index), (path..., getfield(keys(names), index)),
        getfield(types, index), getfield(sizes, index);
        role = getfield(roles, index)) for index in eachindex(types))
    template = NamedTuple{keys(names)}(Tuple(
        _WorkspaceLeafSlot(getfield(names, index))
        for index in eachindex(types)))
    return (leaves, template,
        shape = (candidate_count = Int32(candidates),
            destination_count = Int32(destination_count)))
end

function _candidate_workspace_from_tree(tree, spec,
        ::Reduce{T,K,F,S,<:CanonicalLeftFold}) where {T,K,F,S}
    return _CanonicalReduceWorkspace(
        _destination_grouping_from_workspace(
            tree.grouping, spec.grouping_shape),
        tree.values)
end

@inline _candidate_workspace_shape(spec,
    ::Reduce{T,K,F,S,<:CanonicalLeftFold}) where {T,K,F,S} =
    (grouping_shape = spec.grouping_shape,)
@inline _candidate_workspace_shape(spec,
    ::Reduce{T,K,F,S,<:RelaxedAtomic}) where {T,K,F,S} =
    (shape = spec.shape,)

function _require_candidate_workspace_match(stage,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:CanonicalLeftFold}},
        workspace::_CanonicalReduceWorkspace) where {C,T,K,F,S}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :reduce_candidate_capacity)
    grouping = workspace.grouping
    _require_destination_grouping_match(
        grouping, candidates, destination_count)
    length(workspace.values) == candidates && eltype(workspace.values) === T || throw(
        LocalMathValidationError(
            "canonical Reduce workspace does not match its admitted publication";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destination_count, T),
            actual = (grouping.candidate_count, grouping.destination_count,
                length(workspace.values), eltype(workspace.values))))
    return nothing
end

function _require_candidate_workspace_match(stage,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}},
        workspace::_AtomicReduceWorkspace) where {C,T,K,F,S}
    candidates, destination_count =
        _candidate_publication_dimensions(
            stage, publication, :reduce_candidate_capacity)
    workspace.candidate_count == candidates &&
        workspace.destination_count == destination_count &&
        length(workspace.destinations) == candidates &&
        eltype(workspace.destinations) === Int32 &&
        length(workspace.valid) == candidates &&
        eltype(workspace.valid) === UInt8 &&
        length(workspace.values) == candidates &&
        eltype(workspace.values) === T &&
        length(workspace.accumulator) == destination_count &&
        eltype(workspace.accumulator) === T &&
        length(workspace.invalid_ordinal) == 1 &&
        eltype(workspace.invalid_ordinal) === Int32 || throw(
        LocalMathValidationError(
            "relaxed Reduce workspace does not match its admitted publication";
            stage = :prepare, contract = :candidate_workspace_specialization,
            expected = (candidates, destination_count, T, Int32, UInt8),
            actual = (workspace.candidate_count,
                workspace.destination_count, length(workspace.values),
                eltype(workspace.values), length(workspace.accumulator),
                eltype(workspace.accumulator))))
    return nothing
end
function _candidate_workspace_from_tree(tree, spec,
        ::Reduce{T,K,F,S,<:RelaxedAtomic}) where {T,K,F,S}
    return _AtomicReduceWorkspace(
        tree.destinations, tree.valid, tree.values, tree.accumulator,
        tree.invalid_ordinal, spec.shape.candidate_count,
        spec.shape.destination_count)
end

function _require_reduce_value_capabilities(backend, ::Type{T}) where {T}
    all(operation -> _centrally_qualified_value_capability(
        backend, T, operation, :global), (:load, :store)) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed Reduce value capability";
            stage = :prepare, contract = :reduce_backend_capability,
            expected = (T, :load, :store), actual = typeof(backend)))
    return nothing
end

function _require_candidate_publication_capabilities(backend,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:CanonicalLeftFold}}) where {C,T,K,F,S}
    _require_destination_grouping_capabilities(backend)
    _require_reduce_value_capabilities(backend, T)
    return nothing
end

function _require_candidate_publication_capabilities(backend,
        publication::_PreparedStagePublication{
            C,<:Reduce{T,K,F,S,<:RelaxedAtomic}}) where {C,T,K,F,S}
    _require_reduce_value_capabilities(backend, T)
    all(requirement -> _centrally_qualified_value_capability(
        backend, first(requirement), last(requirement), :global),
        ((Int32, :load), (Int32, :store),
         (UInt8, :load), (UInt8, :store))) &&
        _centrally_qualified_atomic_capability(
            backend, Int32, :min, :global) || throw(
        LocalMathValidationError(
            "the backend lacks the reviewed relaxed Reduce routing capability";
            stage = :prepare, contract = :reduce_relaxed_routing_capability,
            expected = (Int32, UInt8, :load, :store, :atomic_min),
            actual = typeof(backend)))
    operation = _reduce_atomic_operation(publication.law.operation, T)
    operation !== nothing && _centrally_qualified_atomic_capability(
        backend, T, operation, :global) || throw(LocalMathValidationError(
            "the backend lacks the reviewed relaxed Reduce atomic capability";
            stage = :prepare, contract = :reduce_relaxed_backend_capability,
            expected = (T, operation, :global), actual = typeof(backend)))
    return nothing
end
