# Terminal OrderedFold execution over the descriptor-free prepared Stage ABI.
# Only the scientific recurrence is serial. State initialization, evaluator
# application, participation compaction, and canonical ordering are parallel KA
# kernels over package-owned bounded scratch.

const _ORDERED_FOLD_BLOCK = 256

struct _OrderedFoldStageWorkspace{V,O,S,X,R,T}
    values::V; order::O; status::S; validation::X; state::R; tree::T
end
struct _OrderedFoldRecurrenceStage{F,A,P,G}
    fields::F
    accesses::A
    prefix::P
    gate::G
    source_count::Int32
end
struct _OrderedFoldStagePreparation{B,S,W,V}
    backend::B; stage::S; workspace::W; validation::V
    state_extent::Int32
end
Adapt.@adapt_structure _OrderedFoldStageWorkspace
Adapt.@adapt_structure _OrderedFoldRecurrenceStage

function _ordered_fold_stage_workspace_spec(stage; path::Tuple, name_prefix::Symbol)
    law = only(stage.publications).law
    law isa _PreparedOrderedFoldLaw || error("ordered-fold workspace requires OrderedFold")
    state = only(only(stage.publications).components).state
    state_names = keys(state.components)
    n = Int(stage.source_count)
    order_capacity = nextpow(2, max(n, 1))
    T = _publication_value_type(law)
    names = (values = Symbol(name_prefix, :_values), order = Symbol(name_prefix, :_order),
        status = Symbol(name_prefix, :_status),
        validation = Symbol(name_prefix, :_validation))
    base_leaves = (
        _workspace_leaf(names.values, (path..., :values), T, (n,); role = :ordered_fold_value),
        _workspace_leaf(names.order, (path..., :order), Int32,
            (order_capacity,); role = :ordered_fold_order),
        _workspace_leaf(names.status, (path..., :status), Int32, (1,); role = :ordered_fold_diagnostic),
        _workspace_leaf(names.validation, (path..., :validation), UInt32,
            (_VALIDATION_STATUS_FIELDS, 1); role = :validation_status),
    )
    state_leaves = map(eachindex(state_names)) do index
        component = getfield(state.components, index)
        storage = _prepared_stage_field(stage.fields, component.target)
        name = Symbol(name_prefix, :_state_, state_names[index])
        _workspace_leaf(name, (path..., :state, state_names[index]),
            eltype(storage), size(storage); role = :ordered_fold_state)
    end
    leaves = (base_leaves..., state_leaves...)
    state_template = NamedTuple{state_names}(Tuple(map(eachindex(state_names)) do index
        _WorkspaceLeafSlot(Symbol(
            name_prefix, :_state_, state_names[index]))
    end))
    template = (; values = _WorkspaceLeafSlot(names.values),
        order = _WorkspaceLeafSlot(names.order),
        status = _WorkspaceLeafSlot(names.status),
        validation = _WorkspaceLeafSlot(names.validation),
        state = state_template)
    return (; leaves, template)
end

function _ordered_fold_stage_workspace_from_tree(tree, spec)
    _OrderedFoldStageWorkspace(tree.values, tree.order, tree.status,
        tree.validation, tree.state, tree)
end

@inline function _ordered_fold_stage_fail!(run, code::Int32,
        component::Int32 = Int32(0), source_item::Int32 = Int32(0),
        position::Int32 = Int32(0), witness::Int32 = Int32(0))
    @inbounds run.workspace.status[1] = code
    _store_validation_status!(run.workspace.validation,
        run.lease_index, code, component, source_item, position,
        reinterpret(UInt32, witness))
    return nothing
end
@inline _ordered_fold_stage_success(run) = @inbounds(run.workspace.status[1]) == 0
@inline _ordered_fold_stage_prefix_ok(run) =
    _candidate_prefix_succeeded(run.predecessors, run.lease_index)
@generated function _stage_reads(
        stage::_OrderedFoldRecurrenceStage{F,A}, item::Int32,
    ) where {F,A<:Tuple}
    reads = map(1:fieldcount(A)) do index
        :(_stage_read(stage, getfield(stage.accesses, $index), item))
    end
    return Expr(:tuple, reads...)
end
@generated function _stage_reads(
        stage::_OrderedFoldRecurrenceStage{F,A}, item::Int32, validation,
    ) where {F,A<:Tuple}
    reads = map(1:fieldcount(A)) do index
        :(_stage_read(stage, getfield(stage.accesses, $index), item,
            validation))
    end
    return Expr(:tuple, reads...)
end
@kernel function _ordered_fold_stage_reset_kernel!(
        order, status, validation, lease_index, extent::Int32)
    index = @index(Global, Linear)
    index <= extent && (@inbounds order[index] = Int32(0))
    if index == 1
        @inbounds status[1] = Int32(0)
        _clear_validation_status!(validation, lease_index)
    end
end

@generated function _ordered_fold_stage_initialize_item!(
        state::_PreparedFoldState{C}, fields, scratch, item::Int32,
    ) where {C}
    names = C.parameters[1]
    body = Any[]
    for i in eachindex(names)
        push!(body, quote
            component = getfield(state.components, $i)
            target = getfield(scratch, $(QuoteNode(names[i])))
            source = _prepared_stage_field(fields, component.source)
            item <= length(target) &&
                (@inbounds target[item] = source[item])
        end)
    end
    Expr(:block, body..., :(nothing))
end

@kernel function _ordered_fold_stage_validate_initialize_kernel!(
        order_law, state, fields, workspace, lease_index::Int32,
        predecessors, order_extent::Int32, state_extent::Int32)
    item = @index(Global, Linear)
    if _candidate_prefix_succeeded(predecessors, lease_index)
        if Int32(2) <= item <= order_extent
            order = workspace.order
            previous = @inbounds order[item - 1]
            current = @inbounds order[item]
            if previous != 0 && current != 0 && _ordered_fold_stage_equal(
                    order_law, workspace.values, previous, current)
                _candidate_atomic_max!(workspace.status, 1,
                    Int32(_ORDERED_FOLD_DUPLICATE_ORDER))
            end
        end
        # Initialization targets only private shadow state.  It is deliberately
        # unconditional with respect to order validation; recurrence is a later
        # launch and observes the completed diagnostic status.
        item <= state_extent && _ordered_fold_stage_initialize_item!(
            state, fields, workspace.state, Int32(item))
    end
end

@kernel function _ordered_fold_stage_evaluate_kernel!(
        qualified, workspace, lease_index::Int32, predecessors,
        extent::Int32)
    item = @index(Global, Linear)
    if item <= extent &&
            _candidate_prefix_succeeded(predecessors, lease_index)
        stage = qualified.stage
        valid_control, enabled = _stage_control_state(
            stage, qualified.parameters, Int32(item))
        if !valid_control
            _candidate_atomic_max!(workspace.status, 1,
                Int32(_CANDIDATE_STATUS_INVALID_CONTROL))
        elseif !_stage_accesses_valid(
                stage.accesses, stage.fields, Int32(item))
            _candidate_atomic_max!(workspace.status, 1,
                Int32(_CANDIDATE_STATUS_RELATION))
        elseif enabled
            validation = _OrderedFoldEvaluationValidation(workspace.status)
            result = _call_stage_evaluator(qualified, Int32(item),
                _stage_reads(stage, Int32(item), validation),
                qualified.parameters)
            value = getfield(result, 1)
            if value.participates
                @inbounds begin
                    workspace.values[item] = value.value
                    workspace.order[item] = Int32(item)
                end
            end
        end
    end
end

@inline function _ordered_fold_stage_validate_writes(writes::BoundedWrites{K}, extent,
        component::Int32) where {K}
    0 <= writes.count <= K || return (
        Int32(_ORDERED_FOLD_UPDATE_COUNT), Int32(writes.count))
    for left in Int32(1):writes.count
        key = @inbounds writes.keys[left]
        1 <= key <= extent || return (
            Int32(_ORDERED_FOLD_DESTINATION), Int32(key))
        for right in Int32(1):(left - 1)
            key == @inbounds(writes.keys[right]) && return (
                Int32(_ORDERED_FOLD_DUPLICATE_UPDATE), Int32(key))
        end
    end
    return (Int32(0), Int32(0))
end
@generated function _ordered_fold_stage_validate_step!(state::_PreparedFoldState{C}, scratch,
        step::FoldStep) where {C}
    names = C.parameters[1]
    checks = Any[]
    for i in eachindex(names)
        push!(checks, quote
            component = getfield(state.components, $i)
            code, witness = _ordered_fold_stage_validate_writes(getfield(step.updates, $(QuoteNode(names[i]))),
                length(getfield(scratch, $(QuoteNode(names[i])))), Int32($i))
            code == 0 || return (code, Int32($i), witness)
        end)
    end
    Expr(:block, checks..., :((Int32(0), Int32(0), Int32(0))))
end
@inline function _ordered_fold_stage_apply_writes!(storage, writes::BoundedWrites)
    for j in Int32(1):writes.count
        @inbounds storage[writes.keys[j]] = writes.values[j]
    end
end
@generated function _ordered_fold_stage_apply_step!(state::_PreparedFoldState{C}, scratch,
        step::FoldStep) where {C}
    names = C.parameters[1]
    Expr(:block, [:(begin
        component = getfield(state.components, $i)
        _ordered_fold_stage_apply_writes!(getfield(scratch, $(QuoteNode(names[i]))),
            getfield(step.updates, $(QuoteNode(names[i]))))
    end) for i in eachindex(names)]..., :(nothing))
end

@inline function _ordered_fold_stage_less(order, values, left, right)
    order isa _SourceOrder && return left < right
    comparison = _canonical_order_compare(_ordering_extract(order.key, @inbounds(values[left])),
        _ordering_extract(order.identity, @inbounds(values[left])),
        _ordering_extract(order.key, @inbounds(values[right])),
        _ordering_extract(order.identity, @inbounds(values[right])))
    return comparison < 0
end
@inline function _ordered_fold_stage_equal(order, values, left, right)
    order isa _SourceOrder && return false
    _canonical_order_equal(_ordering_extract(order.key, @inbounds(values[left])),
        _ordering_extract(order.identity, @inbounds(values[left])),
        _ordering_extract(order.key, @inbounds(values[right])),
        _ordering_extract(order.identity, @inbounds(values[right])))
end

@inline function _ordered_fold_stage_index_less(order, values,
        left::Int32, right::Int32)
    left == 0 && return false
    right == 0 && return true
    return _ordered_fold_stage_less(order, values, left, right)
end

@kernel function _ordered_fold_stage_bitonic_kernel!(
        order_law, values, order, distance::Int32, width::Int32, extent::Int32)
    item = @index(Global, Linear)
    if item <= extent
        partner = Int32(xor(item - 1, distance)) + Int32(1)
        if partner > item && partner <= extent
            left, right = @inbounds(order[item]), @inbounds(order[partner])
            ascending = (Int32(item - 1) & width) == 0
            right_less = _ordered_fold_stage_index_less(
                order_law, values, right, left)
            left_less = _ordered_fold_stage_index_less(
                order_law, values, left, right)
            swap = ascending ? right_less : left_less
            if swap
                @inbounds order[item], order[partner] = right, left
            end
        end
    end
end

function _ordered_fold_stage_launch_order!(backend, order_law, workspace)
    extent = length(workspace.order)
    width = 2
    while width <= extent
        distance = width >>> 1
        while distance >= 1
            _ordered_fold_stage_bitonic_kernel!(backend,
                min(extent, _ORDERED_FOLD_BLOCK), extent)(order_law,
                workspace.values, workspace.order,
                Int32(distance), Int32(width), Int32(extent);
                ndrange = extent)
            distance >>>= 1
        end
        width <<= 1
    end
    return nothing
end

@inline function _ordered_fold_stage_execute!(run)
    workspace = run.workspace
    _ordered_fold_stage_prefix_ok(run) || return
    gate = _stage_gate_open(run.stage.gate, run.stage,
        run.boundary_parameters)
    gate || return
    prefix = _stage_prefix_value(
        run.stage.prefix, run.stage, run.boundary_parameters)
    prefix isa Integer && !(prefix isa Bool) &&
        0 <= prefix <= run.stage.source_count ||
        return _ordered_fold_stage_fail!(run, Int32(_CANDIDATE_STATUS_INVALID_CONTROL))
    _ordered_fold_stage_success(run) || return
    accumulator = _prepared_fold_accumulator(run.workspace.state)
    for position in Int32(1):run.stage.source_count
        item = @inbounds workspace.order[position]
        item == 0 && break
        step = run.transition(accumulator,
            @inbounds(workspace.values[item]), item,
            _stage_reads(run.stage, item,
                _OrderedFoldEvaluationValidation(workspace.status)))
        _ordered_fold_stage_success(run) || return
        code, component_index, witness =
            _ordered_fold_stage_validate_step!(
                run.state, run.workspace.state, step)
        code == 0 || return _ordered_fold_stage_fail!(run, code,
            component_index, item, position, witness)
        _ordered_fold_stage_apply_step!(run.state, run.workspace.state, step)
        step.halt && return
    end
end

@generated function _ordered_fold_stage_commit_item!(
        state::_PreparedFoldState{C}, fields, scratch, item::Int32,
    ) where {C}
    names = C.parameters[1]
    copies = map(eachindex(names)) do index
        quote
            component = getfield(state.components, $index)
            target = _prepared_stage_field(fields, component.target)
            source = getfield(scratch, $(QuoteNode(names[index])))
            item <= length(target) &&
                (@inbounds target[item] = source[item])
        end
    end
    Expr(:block, copies..., :(nothing))
end

@kernel function _ordered_fold_stage_kernel!(run)
    index = @index(Global, Linear)
    index == 1 && _ordered_fold_stage_execute!(run)
end

@kernel function _ordered_fold_stage_finalize_kernel!(run)
    index = @index(Global, Linear)
    if _ordered_fold_stage_prefix_ok(run)
        code = @inbounds run.workspace.status[1]
        if index == 1
            validation = run.workspace.validation
            existing = @inbounds validation[_VALIDATION_FAILURE_CLASS,
                run.lease_index]
            if existing != UInt32(0)
                _store_program_validation_status!(run.program_validation,
                    run.lease_index, existing,
                    @inbounds(validation[_VALIDATION_CONTEXT_INDEX,
                        run.lease_index]),
                    @inbounds(validation[_VALIDATION_PRIMARY_RECORD,
                        run.lease_index]),
                    @inbounds(validation[_VALIDATION_SECONDARY_RECORD,
                        run.lease_index]),
                    @inbounds(validation[_VALIDATION_WITNESS_BITS,
                        run.lease_index]))
            elseif code == Int32(_ORDERED_FOLD_DUPLICATE_ORDER)
                order = run.workspace.order
                for position in Int32(2):run.source_count
                    previous = @inbounds order[position - 1]
                    item = @inbounds order[position]
                    item == 0 && break
                    if previous != 0 && _ordered_fold_stage_equal(run.order,
                            run.workspace.values, previous, item)
                        _store_validation_status!(validation, run.lease_index,
                            code, Int32(0), previous, position - Int32(1),
                            reinterpret(UInt32, item))
                        _store_program_validation_status!(run.program_validation,
                            run.lease_index, code, Int32(0), previous,
                            position - Int32(1), reinterpret(UInt32, item))
                        break
                    end
                end
            elseif existing == UInt32(0)
                _store_validation_status!(validation, run.lease_index,
                    code, Int32(0), code, Int32(0), reinterpret(UInt32, code))
                _store_program_validation_status!(run.program_validation,
                    run.lease_index, code, Int32(0), code, Int32(0),
                    reinterpret(UInt32, code))
            end
        end
        code == 0 && _ordered_fold_stage_commit_item!(run.state,
            run.stage.fields, run.workspace.state, Int32(index))
    end
end

function _prepare_ordered_fold_stage(admission::_StageAdmission,
        workspace::_OrderedFoldStageWorkspace)
    stage = admission.stage
    only(stage.publications).law isa _PreparedOrderedFoldLaw || throw(LocalMathValidationError(
        "OrderedFold executor requires one prepared terminal OrderedFold law";
        stage = :prepare, contract = :ordered_fold_stage_law))
    state = only(only(stage.publications).components).state
    state_extent = maximum((length(_prepared_stage_field(stage.fields,
            component.target)) for component in values(state.components));
        init = 0)
    state_extent <= typemax(Int32) || throw(LocalMathValidationError(
        "OrderedFold state extent exceeds its device index type";
        stage = :prepare, contract = :ordered_fold_state_extent,
        expected = 0:typemax(Int32), actual = state_extent))
    _OrderedFoldStagePreparation(admission.backend, stage, workspace,
        workspace.validation, Int32(state_extent))
end

function _execute_ordered_fold_stage!(prepared::_OrderedFoldStagePreparation,
        parameters::Tuple, lease_index::Int32, predecessors::Tuple,
        relation_guard, program_validation)
    qualified = _QualifiedEvaluation(_stage_evaluation(prepared.stage),
        _stage_runtime_parameters(parameters, prepared.stage))
    prefix = (relation_guard, predecessors...)
    publication = only(prepared.stage.publications)
    state = only(publication.components).state
    law = publication.law
    recurrence_stage = _OrderedFoldRecurrenceStage(
        prepared.stage.fields, prepared.stage.accesses,
        prepared.stage.control.prefix, prepared.stage.control.gate,
        prepared.stage.source_count)
    boundary_parameters = (; prefix = qualified.parameters.prefix,
        gate = qualified.parameters.gate)
    recurrence = (; stage = recurrence_stage,
        boundary_parameters,
        transition = law.transition, state, workspace = prepared.workspace,
        lease_index, predecessors = prefix)
    finalization = (; order = law.order,
        source_count = prepared.stage.source_count,
        stage = recurrence_stage, state,
        workspace = prepared.workspace, lease_index,
        predecessors = prefix, program_validation)
    order_extent = length(prepared.workspace.order)
    _ordered_fold_stage_reset_kernel!(prepared.backend,
        min(order_extent, _ORDERED_FOLD_BLOCK), order_extent)(
        prepared.workspace.order, prepared.workspace.status,
        prepared.workspace.validation, lease_index, Int32(order_extent);
        ndrange = order_extent)
    _launch_stage_relation_receipt!(prepared.backend, relation_guard,
        prepared.validation, program_validation, lease_index)
    source_extent = max(Int(prepared.stage.source_count), 1)
    _ordered_fold_stage_evaluate_kernel!(prepared.backend,
        min(source_extent, _ORDERED_FOLD_BLOCK), source_extent)(qualified,
        prepared.workspace, lease_index, prefix,
        prepared.stage.source_count; ndrange = source_extent)
    _ordered_fold_stage_launch_order!(prepared.backend, law.order,
        prepared.workspace)
    state_extent = prepared.state_extent
    initialize_extent = max(source_extent, Int(state_extent), 1)
    _ordered_fold_stage_validate_initialize_kernel!(prepared.backend,
        min(initialize_extent, _ORDERED_FOLD_BLOCK), initialize_extent)(
        law.order, state, prepared.stage.fields, prepared.workspace,
        lease_index, prefix, prepared.stage.source_count, state_extent;
        ndrange = initialize_extent)
    _ordered_fold_stage_kernel!(prepared.backend)(recurrence; ndrange = 1)
    state_launch = max(Int(state_extent), 1)
    _ordered_fold_stage_finalize_kernel!(prepared.backend,
        min(state_launch, _ORDERED_FOLD_BLOCK), state_launch)(finalization;
        ndrange = state_launch)
    return prepared
end
