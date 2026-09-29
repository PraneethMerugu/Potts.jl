# Exact sparse-key reduction within the sole StageProgram/KernelAbstractions
# execution path. The destination Collection is read only into private scratch;
# publication occurs once, after every count, key, control, and capacity check.

const _KEYED_REDUCE_STATUS_SUCCESS = Int32(0)
const _KEYED_REDUCE_STATUS_CAPACITY = Int32(1)
const _KEYED_REDUCE_STATUS_PRIOR_COUNT = Int32(2)
const _KEYED_REDUCE_STATUS_DUPLICATE = Int32(3)
const _KEYED_REDUCE_STATUS_INVALID_CONTROL = Int32(5)

# Storage was type-admitted during preparation; this sealed reconstruction keeps
# that device path independent of the validating public outer constructor.
@inline _compacted_reconstruct_value(::Type{KeyedValue{K,V}}, key::K,
    value::V) where {K,V} = KeyedValue(_CONSTRUCTION_TOKEN, key, value)

struct _KeyedReduceBounds
    capacity::Int32
    includes_stage_entry::Bool
    candidate_count::Int32
    merge_passes::Int32
end
struct _KeyedReduceEmission{W}
    first_candidate::Int32
end
struct _KeyedReduceKeyOrder{K} end
_compacted_order_types(::_KeyedReduceKeyOrder{K}) where {K} = (K, K)
struct _KeyedReduceFold{K,V,F,R}
    prior_capacity::Int32
    operation::F
    identity::V
    retention::R
end
struct _KeyedReducePublication{K,V} end
struct _KeyedReducePhysical{B,E,O,F,P}
    bounds::B
    emission::E
    key_order::O
    fold::F
    publication::P
end

_keyed_reduce_width(::_KeyedReduceEmission{W}) where {W} = W

function _keyed_reduce_physical(stage,
        publication::_PreparedStagePublication{C,<:_PreparedKeyedReduceLaw{K,V,W}},
    ) where {C,K,V,W}
    storage = only(publication.components).storage
    emitted = _candidate_record_capacity(Int(stage.source_count), W,
        :keyed_reduce_emission_capacity; int32_index = true)
    law = publication.law
    capacity = Int32(length(storage.records))
    includes_stage_entry = law.includes_stage_entry
    prior_capacity = includes_stage_entry ? capacity : Int32(0)
    total = _candidate_record_capacity(1, Int(prior_capacity) + emitted,
        :keyed_reduce_candidate_capacity; int32_index = true, terminal = true)
    merges = total > _COMPACTED_BLOCK ?
        ceil(Int, log2(cld(total, _COMPACTED_BLOCK))) : 0
    bounds = _KeyedReduceBounds(capacity, includes_stage_entry,
        Int32(total), Int32(merges))
    emission = _KeyedReduceEmission{W}(prior_capacity)
    key_order = _KeyedReduceKeyOrder{K}()
    fold = _KeyedReduceFold{K,V,typeof(law.operation),typeof(law.retention)}(
        prior_capacity, law.operation, law.identity, law.retention)
    publication = _KeyedReducePublication{K,V}()
    return _KeyedReducePhysical(bounds, emission, key_order, fold, publication)
end

function _keyed_reduce_component_workspace_spec(root::Tuple,
        name_prefix::Symbol, label::Symbol, ::Type{T}, count::Int,
        path::Tuple = ()) where {T}
    if fieldcount(T) == 0
        suffix = isempty(path) ? :scalar : Symbol(join(string.(path), :_))
        return (_workspace_leaf(
            Symbol(name_prefix, :_keyed_reduce_, label, :_, suffix),
            (root..., :keyed_reduce, label, path...), T, (count,);
            role = Symbol(:keyed_reduce_, label, :_component)),)
    end
    return reduce(1:fieldcount(T); init = ()) do leaves, field_index
        (leaves..., _keyed_reduce_component_workspace_spec(
            root, name_prefix, label, fieldtype(T, field_index), count,
            (path..., fieldname(T, field_index)))...)
    end
end

function _keyed_reduce_stage_workspace_spec(stage; path::Tuple = (),
        name_prefix::Symbol = :keyed_reduce_stage)
    publication = only(stage.publications)
    plan = _keyed_reduce_physical(stage, publication)
    K = typeof(plan.key_order).parameters[1]
    V = typeof(plan.fold).parameters[2]
    candidates = Int(plan.bounds.candidate_count)
    prefix_count, sums_count = _compacted_scan_storage_lengths(candidates)
    leaves = (
        _keyed_reduce_component_workspace_spec(
            path, name_prefix, :keys, K, candidates)...,
        _keyed_reduce_component_workspace_spec(
            path, name_prefix, :values, V, candidates)...,
        _keyed_reduce_component_workspace_spec(
            path, name_prefix, :reduced_keys, K, candidates)...,
        _keyed_reduce_component_workspace_spec(
            path, name_prefix, :reduced_values, V, candidates)...,
        _workspace_leaf(Symbol(name_prefix, :_valid),
            (path..., :keyed_reduce, :valid), UInt8, (candidates,);
            role = :keyed_reduce_candidate_participation),
        _workspace_leaf(Symbol(name_prefix, :_item_counts),
            (path..., :keyed_reduce, :item_counts), Int32, (candidates,);
            role = :keyed_reduce_scan_input),
        _workspace_leaf(Symbol(name_prefix, :_segment_flags),
            (path..., :keyed_reduce, :segment_flags), Int32, (candidates,);
            role = :keyed_reduce_segment_starts),
        _workspace_leaf(Symbol(name_prefix, :_order_a),
            (path..., :keyed_reduce, :order_a), Int32, (candidates,);
            role = :keyed_reduce_order_ping),
        _workspace_leaf(Symbol(name_prefix, :_order_b),
            (path..., :keyed_reduce, :order_b), Int32, (candidates,);
            role = :keyed_reduce_order_pong),
        _workspace_leaf(Symbol(name_prefix, :_positions),
            (path..., :keyed_reduce, :positions), Int32, (candidates,);
            role = :keyed_reduce_candidate_position),
        _workspace_leaf(Symbol(name_prefix, :_prefix),
            (path..., :keyed_reduce, :prefix), Int32, (prefix_count,);
            role = :keyed_reduce_scan_prefix),
        _workspace_leaf(Symbol(name_prefix, :_sums),
            (path..., :keyed_reduce, :sums), Int32, (sums_count,);
            role = :keyed_reduce_scan_block_sums),
        _workspace_leaf(Symbol(name_prefix, :_count),
            (path..., :keyed_reduce, :count), Int32, (1,);
            role = :keyed_reduce_candidate_count),
        _workspace_leaf(Symbol(name_prefix, :_unique_count),
            (path..., :keyed_reduce, :unique_count), Int32, (1,);
            role = :keyed_reduce_unique_count),
        _workspace_leaf(Symbol(name_prefix, :_final_count),
            (path..., :keyed_reduce, :final_count), Int32, (1,);
            role = :keyed_reduce_final_count),
        _workspace_leaf(Symbol(name_prefix, :_duplicate),
            (path..., :keyed_reduce, :duplicate), Int32, (1,);
            role = :keyed_reduce_duplicate_diagnostic),
        _workspace_leaf(Symbol(name_prefix, :_gate),
            (path..., :keyed_reduce, :gate), Bool, (1,);
            role = :keyed_reduce_publication_gate),
        _workspace_leaf(Symbol(name_prefix, :_status),
            (path..., :keyed_reduce, :status), Int32, (1,);
            role = :keyed_reduce_diagnostic),
        _workspace_leaf(Symbol(name_prefix, :_validation),
            (path..., :keyed_reduce, :validation), UInt32,
            (_VALIDATION_STATUS_FIELDS, 1); role = :validation_status),
    )
    local_leaves = Tuple(_workspace_leaf(leaf.name,
        leaf.path[(length(path) + 1):end], leaf.element_type, leaf.size;
        strides = leaf.strides, role = leaf.role) for leaf in leaves)
    return (leaves, template = _workspace_template_from_leaves(local_leaves),
        plan, path)
end

struct _KeyedReduceStageWorkspace{T,A,X}
    tree::T
    authority::A
    spec::X
end

function _keyed_reduce_stage_workspace_from_tree(tree, spec)
    local_leaves = Tuple(_workspace_leaf(leaf.name,
        leaf.path[(length(spec.path) + 1):end], leaf.element_type, leaf.size;
        strides = leaf.strides, role = leaf.role) for leaf in spec.leaves)
    authority = _WorkspaceAuthority(local_leaves, spec.template)
    return _KeyedReduceStageWorkspace(tree, authority, spec)
end

function Adapt.adapt_structure(to, workspace::_KeyedReduceStageWorkspace)
    _keyed_reduce_stage_workspace_from_tree(Adapt.adapt(to, workspace.tree),
        workspace.spec)
end

struct _KeyedReduceStageExecution{Q,P,W,S,G,R}
    stage::Q
    plan::P
    states::W
    status::S
    gate::G
    storage::R
end
struct _KeyedReduceStagePreparation{B,E,V}
    backend::B
    execution::E
    validation::V
end
Adapt.@adapt_structure _KeyedReduceStageExecution

function _keyed_reduce_state_views(stored)
    ordering = (
        valid = stored.valid, item_counts = stored.item_counts,
        prefix = stored.prefix, sums = stored.sums,
        order_a = stored.order_a, order_b = stored.order_b,
        positions = stored.positions, count = stored.count,
        groups = nothing, keys = stored.keys, identities = stored.keys,
    )
    return (
        reset = (
            valid = stored.valid, item_counts = stored.item_counts,
            segment_flags = stored.segment_flags,
            order_a = stored.order_a, order_b = stored.order_b,
            positions = stored.positions, keys = stored.keys,
            values = stored.values, status = stored.status,
            gate = stored.gate, count = stored.count,
            unique_count = stored.unique_count,
            final_count = stored.final_count, duplicate = stored.duplicate,
        ),
        emission = (valid = stored.valid, item_counts = stored.item_counts,
            keys = stored.keys, values = stored.values),
        ordering,
        segment = (count = stored.count, keys = stored.keys,
            segment_flags = stored.segment_flags,
            item_counts = stored.item_counts, prefix = stored.prefix,
            duplicate = stored.duplicate,
            unique_count = stored.unique_count),
        fold = (count = stored.count, segment_flags = stored.segment_flags,
            prefix = stored.prefix, keys = stored.keys, values = stored.values,
            reduced_keys = stored.reduced_keys,
            reduced_values = stored.reduced_values,
            item_counts = stored.item_counts),
        final = (unique_count = stored.unique_count, prefix = stored.prefix,
            item_counts = stored.item_counts, final_count = stored.final_count,
            duplicate = stored.duplicate),
        publication = (gate = stored.gate,
            unique_count = stored.unique_count,
            item_counts = stored.item_counts, prefix = stored.prefix,
            reduced_keys = stored.reduced_keys,
            reduced_values = stored.reduced_values,
            final_count = stored.final_count),
    )
end

function _prepare_keyed_reduce_stage(admission::_StageAdmission,
        raw::_KeyedReduceStageWorkspace)
    stored = raw.tree.keyed_reduce
    states = _keyed_reduce_state_views(stored)
    plan = _keyed_reduce_physical(admission.stage,
        only(admission.stage.publications))
    candidates = Int(plan.bounds.candidate_count)
    ordering = states.ordering
    length(ordering.valid) == candidates &&
        length(ordering.item_counts) == candidates &&
        length(ordering.order_a) == candidates &&
        length(ordering.order_b) == candidates &&
        length(ordering.positions) == candidates || throw(LocalMathValidationError(
            "KeyedReduce workspace does not match its physical law";
            stage = :prepare, contract = :keyed_reduce_workspace_specialization))
    for leaf in raw.authority.leaves
        _centrally_qualified_value_capability(admission.backend,
            leaf.element_type, :load, :global) &&
        _centrally_qualified_value_capability(admission.backend,
            leaf.element_type, :store, :global) || throw(LocalMathValidationError(
            "KeyedReduce workspace leaf lacks reviewed memory operations";
            stage = :prepare, contract = :keyed_reduce_backend_capability,
            workspace_leaf = leaf.name, actual = typeof(admission.backend)))
    end
    storage = only(only(admission.stage.publications).components).storage
    return _KeyedReduceStagePreparation(admission.backend,
        _KeyedReduceStageExecution(admission.stage, plan, states,
            stored.status, stored.gate, storage), stored.validation)
end

@inline _keyed_reduce_set_failure!(status, code::Int32) = begin
    Atomix.@atomic max(status[1], code)
    nothing
end

@kernel function _keyed_reduce_reset_kernel!(bounds, state, storage,
        validation, lease::Int32)
    candidate = @index(Global, Linear)
    if candidate <= bounds.candidate_count
        @inbounds begin
            state.valid[candidate] = UInt8(0)
            state.item_counts[candidate] = Int32(0)
            state.segment_flags[candidate] = Int32(0)
            state.order_a[candidate] = -Int32(candidate)
            state.order_b[candidate] = -Int32(candidate)
            state.positions[candidate] = Int32(0)
        end
    end
    live = Int32(0)
    valid_live = true
    if bounds.includes_stage_entry
        live = @inbounds storage.count[1]
        valid_live = Int32(0) <= live <= bounds.capacity
    end
    if candidate <= bounds.capacity && valid_live && candidate <= live
        record = _compacted_load_value(eltype(storage.records),
            _compacted_record_components(storage.records), candidate)
        @inbounds begin
            _compacted_store_value!(state.keys, candidate, record.key)
            _compacted_store_value!(state.values, candidate, record.value)
            state.valid[candidate] = UInt8(1)
            state.item_counts[candidate] = Int32(1)
        end
    end
    if candidate == 1
        @inbounds begin
            state.status[1] = valid_live ? _KEYED_REDUCE_STATUS_SUCCESS :
                _KEYED_REDUCE_STATUS_PRIOR_COUNT
            state.gate[1] = false
            state.count[1] = Int32(0)
            state.unique_count[1] = Int32(0)
            state.final_count[1] = Int32(0)
            state.duplicate[1] = bounds.candidate_count + Int32(1)
            _clear_validation_status!(validation, lease)
        end
    end
end

@inline _keyed_reduce_lane(value::KeyedContribution, ::Val{1}, ::Val{1}) = value
@inline _keyed_reduce_lane(values::Tuple, width, lane) =
    _emission_lane(values, width, lane)

@inline function _keyed_reduce_materialize_lane!(emission_layout, state,
        emission, item::Int32, ::Val{L}) where {L}
    candidate = Int(emission_layout.first_candidate) + L +
        _keyed_reduce_width(emission_layout) * (Int(item) - 1)
    enabled = emission.participates
    @inbounds begin
        state.valid[candidate] = enabled ? UInt8(1) : UInt8(0)
        state.item_counts[candidate] = enabled ? Int32(1) : Int32(0)
    end
    enabled || return nothing
    @inbounds begin
        _compacted_store_value!(state.keys, candidate, emission.key)
        _compacted_store_value!(state.values, candidate, emission.value)
    end
    return nothing
end

@generated function _keyed_reduce_materialize!(
        emission_layout::_KeyedReduceEmission{W}, state, emissions,
        item::Int32) where {W}
    calls = [quote
        emission = _keyed_reduce_lane(emissions, Val($W), Val($lane))
        _keyed_reduce_materialize_lane!(emission_layout, state, emission, item,
            Val($lane))
    end for lane in 1:W]
    return Expr(:block, calls..., :(nothing))
end

@kernel function _keyed_reduce_evaluate_kernel!(qualified, emission_layout, state,
        predecessors, status, lease::Int32)
    raw = @index(Global, Linear)
    item = Int32(raw)
    stage = qualified.stage
    if _candidate_prefix_succeeded(predecessors, lease) &&
            _stage_gate_open(stage.control.gate, stage, qualified.parameters)
        prefix = _stage_prefix_value(stage.control.prefix, stage,
            qualified.parameters)
        valid_prefix = prefix isa Integer && !(prefix isa Bool) &&
            0 <= prefix <= stage.source_count
        item == 1 && !valid_prefix && _keyed_reduce_set_failure!(status,
            _KEYED_REDUCE_STATUS_INVALID_CONTROL)
        if item <= stage.source_count && valid_prefix
            _, active = _stage_control_state(stage, qualified.parameters, item)
            access_valid = _stage_accesses_valid(stage.accesses,
                stage.fields, item)
            access_valid || _keyed_reduce_set_failure!(status,
                _KEYED_REDUCE_STATUS_INVALID_CONTROL)
            if active && access_valid
                result = _call_stage_evaluator(qualified, item,
                    _stage_reads(stage, item), qualified.parameters)
                _keyed_reduce_materialize!(emission_layout, state,
                    getfield(result, 1), item)
            end
        end
    end
end

function _keyed_reduce_launch_order!(backend, bounds, key_order, state)
    candidates = Int(bounds.candidate_count)
    _compacted_launch_prefix_scan!(backend, state.item_counts,
        state.prefix, state.sums)
    prefix = _compacted_scan_level(state.prefix, 0, candidates)
    _launch_1d!(_compacted_scatter_kernel!, backend, max(candidates, 1),
        Val(_COMPACTED_BLOCK),
        state.valid, state.item_counts, prefix, state.order_a,
        state.positions, state.count, Val(1), Int32(candidates))
    local_extent = max(cld(candidates, _COMPACTED_BLOCK), 1) * _COMPACTED_BLOCK
    _launch_1d!(_compacted_local_bitonic_kernel!, backend, local_extent,
        Val(_COMPACTED_BLOCK),
        key_order, state, state.count, Int32(candidates))
    width, to_b = _COMPACTED_BLOCK, true
    while width < candidates
        source, destination = to_b ? (state.order_a, state.order_b) :
            (state.order_b, state.order_a)
        _launch_1d!(_compacted_merge_kernel!, backend, candidates,
            Val(_COMPACTED_BLOCK),
            key_order, state, source, destination, state.count,
            Int32(width), Int32(candidates))
        width *= 2
        to_b = !to_b
    end
    return nothing
end

@inline function _keyed_reduce_final_order(bounds, state)
    isodd(bounds.merge_passes) ? state.order_b : state.order_a
end

@inline _keyed_reduce_key(key_order::_KeyedReduceKeyOrder{K}, state,
        candidate::Int32) where {K} =
    _compacted_load_value(K, state.keys,
        Int(candidate))

@kernel function _keyed_reduce_segments_kernel!(key_order, state, order,
        prior_capacity::Int32, extent::Int32)
    raw = @index(Global, Linear)
    position = Int32(raw)
    live = @inbounds state.count[1]
    flag = Int32(0)
    if position <= live
        candidate = @inbounds order[position]
        flag = if position == 1
            Int32(1)
        else
            prior = @inbounds order[position - Int32(1)]
            _rank_equal(_keyed_reduce_key(key_order, state, prior),
                _keyed_reduce_key(key_order, state, candidate)) ? Int32(0) : Int32(1)
        end
        if flag == 0 && candidate <= prior_capacity
            prior = @inbounds order[position - Int32(1)]
            prior <= prior_capacity && Atomix.@atomic min(
                state.duplicate[1], position - Int32(1))
        end
    end
    if position <= extent
        @inbounds begin
            state.segment_flags[position] = flag
            state.item_counts[position] = flag
        end
    end
end

@kernel function _keyed_reduce_unique_count_kernel!(state)
    index = @index(Global, Linear)
    if index == 1
        live = @inbounds state.count[1]
        @inbounds state.unique_count[1] = live == 0 ? Int32(0) :
            state.prefix[live] + state.item_counts[live]
    end
end

@inline _keyed_reduce_retains(::RetainAllKeys, value, identity) = true
@inline _keyed_reduce_retains(::DropIdentityKeys, value, identity) = value != identity

@kernel function _keyed_reduce_clear_counts_kernel!(state, extent::Int32)
    index = @index(Global, Linear)
    index <= extent && (@inbounds state.item_counts[index] = Int32(0))
end

@inline _keyed_reduce_fold_key(::_KeyedReduceFold{K}, state,
        candidate::Int32) where {K} =
    _compacted_load_value(K, state.keys, Int(candidate))

@inline function _keyed_reduce_fold_segment!(fold, state, order,
        position::Int32, live::Int32)
    if position <= live && @inbounds(state.segment_flags[position]) == 1
        group = @inbounds state.prefix[position] + Int32(1)
        candidate = @inbounds order[position]
        key = _keyed_reduce_fold_key(fold, state, candidate)
        value_type = typeof(fold).parameters[2]
        cursor = position
        accumulator = if candidate <= fold.prior_capacity
            cursor += Int32(1)
            _compacted_load_value(value_type, state.values, Int(candidate))
        else
            fold.identity
        end
        while cursor <= live
            next_candidate = @inbounds order[cursor]
            _rank_equal(key,
                _keyed_reduce_fold_key(fold, state, next_candidate)) || break
            contribution = _compacted_load_value(value_type,
                state.values, Int(next_candidate))
            accumulator = fold.operation(accumulator, contribution)
            cursor += Int32(1)
        end
        @inbounds begin
            _compacted_store_value!(state.reduced_keys, Int(group), key)
            _compacted_store_value!(state.reduced_values, Int(group), accumulator)
            retained = _keyed_reduce_retains(fold.retention, accumulator,
                fold.identity) ? Int32(1) : Int32(0)
            state.item_counts[group] = retained
        end
    end
    return nothing
end

@kernel function _keyed_reduce_fold_kernel!(fold, state, order,
        extent::Int32)
    raw = @index(Global, Linear)
    position = Int32(raw)
    live = @inbounds state.count[1]
    position <= extent &&
        _keyed_reduce_fold_segment!(fold, state, order, position, live)
end

@kernel function _keyed_reduce_final_count_kernel!(bounds, state, status)
    index = @index(Global, Linear)
    if index == 1
        unique_count = @inbounds state.unique_count[1]
        final_count = unique_count == 0 ? Int32(0) :
            @inbounds(state.prefix[unique_count] +
                state.item_counts[unique_count])
        @inbounds state.final_count[1] = final_count
        final_count > bounds.capacity && _keyed_reduce_set_failure!(status,
            _KEYED_REDUCE_STATUS_CAPACITY)
        @inbounds(state.duplicate[1]) <= bounds.candidate_count &&
            _keyed_reduce_set_failure!(status,
                _KEYED_REDUCE_STATUS_DUPLICATE)
    end
end

@kernel function _keyed_reduce_finalize_kernel!(gate, status, validation,
        program_validation, predecessors, lease::Int32)
    index = @index(Global, Linear)
    if index == 1 &&
            _candidate_prefix_succeeded(predecessors, lease)
        code = @inbounds status[1]
        if code == _KEYED_REDUCE_STATUS_SUCCESS
            @inbounds gate[1] = true
        else
            @inbounds gate[1] = false
            _store_validation_status!(validation, lease, code, Int32(1),
                Int32(0), Int32(0), UInt32(0))
            _store_program_validation_status!(program_validation, lease, code,
                Int32(1), Int32(0), Int32(0), UInt32(0))
        end
    end
end

@inline _keyed_reduce_publication_key(::_KeyedReducePublication{K}, state,
        group::Int32) where {K} =
    _compacted_load_value(K, state.reduced_keys, Int(group))
@inline _keyed_reduce_publication_value(
        ::_KeyedReducePublication{K,V}, state, group::Int32) where {K,V} =
    _compacted_load_value(V, state.reduced_values, Int(group))

@inline function _keyed_reduce_publish_record!(publication, state, storage,
        group::Int32, unique_count::Int32)
    if group <= unique_count && @inbounds(state.item_counts[group]) == 1
        output = @inbounds state.prefix[group] + Int32(1)
        key = _keyed_reduce_publication_key(publication, state, group)
        value = _keyed_reduce_publication_value(publication, state, group)
        _compacted_store_value!(_compacted_record_components(storage.records),
            Int(output), KeyedValue(_CONSTRUCTION_TOKEN, key, value))
        @inbounds begin
            storage.source_item[output] = Int32(0)
            storage.source_lane[output] = Int32(0)
        end
    end
    return nothing
end

@kernel function _keyed_reduce_publish_kernel!(publication, state, storage)
    raw = @index(Global, Linear)
    group = Int32(raw)
    if @inbounds state.gate[1]
        unique_count = @inbounds state.unique_count[1]
        _keyed_reduce_publish_record!(publication, state, storage, group,
            unique_count)
        group == 1 && (@inbounds storage.count[1] = state.final_count[1])
    end
end

function _execute_keyed_reduce_stage!(prepared::_KeyedReduceStagePreparation,
        parameters::Tuple, lease_index::Int32, predecessors::Tuple,
        relation_guard, program_validation)
    execution = prepared.execution
    backend = prepared.backend
    states, plan = execution.states, execution.plan
    bounds = plan.bounds
    qualified = _QualifiedEvaluation(_stage_evaluation(execution.stage),
        _stage_runtime_parameters(parameters, execution.stage))
    statuses = (relation_guard, predecessors...)
    extent = max(Int(bounds.candidate_count), 1)
    _launch_1d!(_keyed_reduce_reset_kernel!, backend, extent,
        Val(_COMPACTED_BLOCK),
        bounds, states.reset, execution.storage, prepared.validation, lease_index)
    _launch_stage_relation_receipt!(backend, relation_guard,
        prepared.validation, program_validation, lease_index)
    _keyed_reduce_evaluate_kernel!(backend)(qualified, plan.emission,
        states.emission,
        statuses, execution.status, lease_index;
        ndrange = max(Int(execution.stage.source_count), 1))
    _keyed_reduce_launch_order!(backend, bounds, plan.key_order,
        states.ordering)
    order = _keyed_reduce_final_order(bounds, states.ordering)
    _launch_1d!(_keyed_reduce_segments_kernel!, backend, extent,
        Val(_COMPACTED_BLOCK),
        plan.key_order, states.segment, order, plan.fold.prior_capacity,
        bounds.candidate_count)
    _compacted_launch_prefix_scan!(backend, states.segment.item_counts,
        states.segment.prefix, states.ordering.sums)
    _keyed_reduce_unique_count_kernel!(backend, 1, 1)(states.segment;
        ndrange = 1)
    _launch_1d!(_keyed_reduce_clear_counts_kernel!, backend, extent,
        Val(_COMPACTED_BLOCK),
        states.fold, bounds.candidate_count)
    _launch_1d!(_keyed_reduce_fold_kernel!, backend, extent,
        Val(_COMPACTED_BLOCK),
        plan.fold, states.fold, order, bounds.candidate_count)
    _compacted_launch_prefix_scan!(backend, states.fold.item_counts,
        states.fold.prefix, states.ordering.sums)
    _keyed_reduce_final_count_kernel!(backend, 1, 1)(
        bounds, states.final, execution.status; ndrange = 1)
    _keyed_reduce_finalize_kernel!(backend, 1, 1)(execution.gate,
        execution.status,
        prepared.validation, program_validation, statuses, lease_index;
        ndrange = 1)
    _launch_1d!(_keyed_reduce_publish_kernel!, backend, extent,
        Val(_COMPACTED_BLOCK),
        plan.publication, states.publication, execution.storage)
    return prepared
end
