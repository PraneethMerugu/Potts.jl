# Finite-sequence physical realization of the common admitted Stage ABI.
# This owns no semantic descriptor: Collection identity, Field/Relation
# descriptors, evaluator labels, and mathematical laws have been erased by
# stage preparation.  The existing bounded scan/sort primitives are reused as
# physical KA kernels; this unit supplies their Stage-shaped workspace and
# atomic publication boundary.

const _COLLECT_STATUS_SUCCESS = Int32(0)
const _COLLECT_STATUS_INVALID_CONTROL = Int32(5)
const _COLLECT_BLOCK = _COMPACTED_BLOCK

struct _CollectScanLevel{A}
    storage::A
    offset::Int32
    count::Int32
end
Adapt.@adapt_structure _CollectScanLevel
Base.length(level::_CollectScanLevel) = Int(level.count)
@inline Base.getindex(level::_CollectScanLevel, index::Integer) =
    @inbounds level.storage[Int(level.offset) + Int(index)]
@inline function Base.setindex!(level::_CollectScanLevel, value, index::Integer)
    @inbounds level.storage[Int(level.offset) + Int(index)] = value
    return value
end

@inline _collect_scan_level(storage, offset::Int, count::Int) =
    _CollectScanLevel(storage, Int32(offset), Int32(count))

function _collect_scan_storage_lengths(items::Int)
    prefix_count = 0
    sums_count = 0
    current = items
    while true
        blocks = max(cld(current, _COLLECT_BLOCK), 1)
        prefix_count <= typemax(Int32) - current &&
            sums_count <= typemax(Int32) - blocks || throw(
            LocalMathValidationError(
                "Collect scan workspace exceeds Int32 device addressing";
                stage = :prepare, contract = :collect_scan_capacity,
                expected = 0:typemax(Int32),
                actual = (prefix_count + current, sums_count + blocks)))
        prefix_count += current
        sums_count += blocks
        current <= _COLLECT_BLOCK && break
        current = blocks
    end
    return prefix_count, sums_count
end

@inline function _collect_scan_level_count(items::Int)
    levels = 1
    while items > _COLLECT_BLOCK
        items = max(cld(items, _COLLECT_BLOCK), 1)
        levels += 1
    end
    return levels
end

struct _CollectPortPhysical{K,T,G,O,KT,IT}
    capacity::Int32
    candidate_count::Int32
    groups::G
    order::O
    sort_required::Bool
    merge_passes::Int32
end

_collect_width(::_CollectPortPhysical{K}) where {K} = K
_collect_grouped(::_OneGroup) = Val(false)
_collect_grouped(::_GroupBy) = Val(true)
_collect_grouped(::_RoutedGroups) = Val(true)
_collect_directory_extent(::_OneGroup) = 1
_collect_directory_extent(groups::_GroupBy) = Int(groups.count) + 1
_collect_directory_extent(groups::_RoutedGroups) = Int(groups.count) + 1

function _collect_port_physical(stage, publication::_PreparedStagePublication{C,<:_PreparedCollectLaw{T,K}}) where {C,T,K}
    storage = only(publication.components).storage
    # Collect uses `candidate_count + 1` as its invalid-position sentinel.
    # Qualify that arithmetic on the host once so device kernels can consume
    # an already-safe Int32 value without retaining checked conversions or
    # exception paths in GPU IR.
    candidates = _candidate_record_capacity(
        Int(stage.source_count), K, :collect_candidate_capacity;
        int32_index = true, terminal = true,
    )
    law = publication.law
    order = law.order
    key_type, identity_type = _is_canonical_order(order) ?
        _prepared_order_types(order) : (Nothing, Nothing)
    # Prepared ordering is already effect/type admitted; the type parameters
    # merely specialize recursive record scratch and comparison kernels.
    sort_required = _is_grouped(law.groups) || _is_canonical_order(order)
    merges = sort_required && candidates > _COLLECT_BLOCK ?
        ceil(Int, log2(cld(candidates, _COLLECT_BLOCK))) : 0
    return _CollectPortPhysical{K,T,typeof(law.groups),typeof(order),
        key_type,identity_type}(
        Int32(length(storage.records)), Int32(candidates), law.groups, order,
        sort_required, Int32(merges),
    )
end

_collect_port_physicals(stage, ::Tuple{}) = ()
function _collect_port_physicals(stage, publications::Tuple)
    return (_collect_port_physical(stage, first(publications)),
        _collect_port_physicals(stage, Base.tail(publications))...)
end
_collect_port_physicals(stage) =
    _collect_port_physicals(stage, stage.publications)

function _collect_component_workspace_spec(
        root::Tuple, index::Int, label::Symbol, ::Type{T}, count::Int, path::Tuple,
    ) where {T}
    if fieldcount(T) == 0
        suffix = isempty(path) ? :scalar : Symbol(join(string.(path), :_))
        name = Symbol(:collect_, index, :_, label, :_, suffix)
        return (_workspace_leaf(name, (root..., :collect, :ports, index, label, path...),
            T, (count,); role = Symbol(:collect_, label, :_component)),)
    end
    return reduce(1:fieldcount(T); init = ()) do leaves, field_index
        field = fieldname(T, field_index)
        (leaves..., _collect_component_workspace_spec(
            root, index, label, fieldtype(T, field_index), count, (path..., field),
        )...)
    end
end

function _collect_port_workspace_spec(
        root::Tuple, index::Int, port::_CollectPortPhysical{K,T},
    ) where {K,T}
    candidates, items = Int(port.candidate_count), div(Int(port.candidate_count), K)
    leaves = (
        _collect_component_workspace_spec(root, index, :values, T, candidates, ())...,
        _workspace_leaf(Symbol(:collect_, index, :_valid),
            (root..., :collect, :ports, index, :valid), UInt8, (candidates,);
            role = :collect_candidate_participation),
        _workspace_leaf(Symbol(:collect_, index, :_item_counts),
            (root..., :collect, :ports, index, :item_counts), Int32, (items,);
            role = :collect_item_emission_counts),
        _workspace_leaf(Symbol(:collect_, index, :_order_a),
            (root..., :collect, :ports, index, :order_a), Int32, (candidates,);
            role = :collect_order_ping),
        _workspace_leaf(Symbol(:collect_, index, :_order_b),
            (root..., :collect, :ports, index, :order_b), Int32, (candidates,);
            role = :collect_order_pong),
        _workspace_leaf(Symbol(:collect_, index, :_positions),
            (root..., :collect, :ports, index, :positions), Int32, (candidates,);
            role = :collect_candidate_position),
        _workspace_leaf(Symbol(:collect_, index, :_count),
            (root..., :collect, :ports, index, :count), Int32, (1,);
            role = :collect_private_count),
        _workspace_leaf(Symbol(:collect_, index, :_invalid_group),
            (root..., :collect, :ports, index, :invalid_group), Int32, (1,);
            role = :collect_invalid_group_diagnostic),
        _workspace_leaf(Symbol(:collect_, index, :_duplicate_position),
            (root..., :collect, :ports, index, :duplicate_position), Int32, (1,);
            role = :collect_duplicate_diagnostic),
    )
    grouped = _is_grouped(port.groups) ? (
        _workspace_leaf(Symbol(:collect_, index, :_groups),
            (root..., :collect, :ports, index, :groups), Int32, (candidates,);
            role = :collect_dense_groups),
        _workspace_leaf(Symbol(:collect_, index, :_starts),
            (root..., :collect, :ports, index, :starts), Int32,
            (Int(port.groups.count) + 1,); role = :collect_private_directory),
    ) : ()
    ordered = _is_canonical_order(port.order) ? (
        _collect_component_workspace_spec(root, index, :keys,
            typeof(port).parameters[5], candidates, ())...,
        _collect_component_workspace_spec(root, index, :identities,
            typeof(port).parameters[6], candidates, ())...,
    ) : ()
    prefix_count, sums_count = _collect_scan_storage_lengths(items)
    scan = (
        _workspace_leaf(Symbol(:collect_, index, :_prefix),
            (root..., :collect, :ports, index, :prefix), Int32,
            (prefix_count,); role = :collect_scan_prefix),
        _workspace_leaf(Symbol(:collect_, index, :_sums),
            (root..., :collect, :ports, index, :sums), Int32,
            (sums_count,); role = :collect_scan_block_sums),
    )
    return (leaves..., grouped..., ordered..., scan...)
end

function _collect_local_workspace_leaf(
        leaf::_WorkspaceLeaf, root::Tuple,
    )
    prefix = (root..., :collect)
    length(leaf.path) >= length(prefix) &&
        leaf.path[1:length(prefix)] == prefix || error(
        "Collect workspace leaf is outside its declared Stage root")
    return _workspace_leaf(leaf.name,
        leaf.path[(length(root) + 1):end], leaf.element_type, leaf.size;
        strides = leaf.strides, role = leaf.role)
end

function _collect_stage_workspace_spec(stage; path::Tuple = (),
        name_prefix::Symbol = :collect_stage)
    ports = _collect_port_physicals(stage)
    leaves = Tuple(leaf for (index, port) in enumerate(ports)
        for leaf in _collect_port_workspace_spec(path, index, port))
    gate_name = Symbol(name_prefix, :_gate)
    status_name = Symbol(name_prefix, :_status)
    validation_name = Symbol(name_prefix, :_validation)
    all_leaves = (leaves...,
        _workspace_leaf(gate_name, (path..., :collect, :gate), Bool, (1,);
            role = :collect_publication_gate),
        _workspace_leaf(status_name, (path..., :collect, :status), Int32, (1,);
            role = :collect_diagnostic),
        _workspace_leaf(validation_name, (path..., :collect, :validation), UInt32,
            (_VALIDATION_STATUS_FIELDS, 1); role = :validation_status),
    )
    local_leaves = Tuple(_collect_local_workspace_leaf(leaf, path)
        for leaf in all_leaves)
    template = _workspace_template_from_leaves(local_leaves)
    return (leaves = all_leaves, template, ports, path)
end

mutable struct _CollectStageWorkspaceSeal end
const _COLLECT_STAGE_WORKSPACE_SEAL = _CollectStageWorkspaceSeal()
struct _CollectStageWorkspace{P,G,S,V,T,A,X}
    ports::P
    gate::G
    status::S
    validation::V
    tree::T
    authority::A
    spec::X
    function _CollectStageWorkspace(seal::_CollectStageWorkspaceSeal,
            ports::P, gate::G, status::S, validation::V, tree::T, authority::A,
            spec::X) where {P,G,S,V,T,A,X}
        seal === _COLLECT_STAGE_WORKSPACE_SEAL || error(
            "invalid Collect-stage workspace seal")
        new{P,G,S,V,T,A,X}(ports, gate, status, validation, tree, authority, spec)
    end
end

function _collect_workspace_port(raw)
    merge(raw, (
        groups = hasproperty(raw, :groups) ? raw.groups : nothing,
        keys = hasproperty(raw, :keys) ? raw.keys : nothing,
        identities = hasproperty(raw, :identities) ? raw.identities : nothing,
        starts = hasproperty(raw, :starts) ? raw.starts : nothing,
    ))
end

_collect_workspace_ports(::Tuple{}) = ()
function _collect_workspace_ports(ports::Tuple)
    return (_collect_workspace_port(first(ports)),
        _collect_workspace_ports(Base.tail(ports))...)
end

function _collect_stage_workspace_from_tree(tree, spec)
    authority = _WorkspaceAuthority(Tuple(_collect_local_workspace_leaf(
        leaf, spec.path) for leaf in spec.leaves), spec.template)
    collect = tree.collect
    ports = _collect_workspace_ports(collect.ports)
    return _CollectStageWorkspace(_COLLECT_STAGE_WORKSPACE_SEAL, ports,
        collect.gate, collect.status, collect.validation, tree, authority, spec)
end

function Adapt.adapt_structure(to, workspace::_CollectStageWorkspace)
    tree = Adapt.adapt(to, workspace.tree)
    return _collect_stage_workspace_from_tree(tree, workspace.spec)
end

function _collect_require_port_workspace(port, workspace)
    candidates = Int(port.candidate_count)
    items = div(candidates, _collect_width(port))
    T = typeof(port).parameters[2]
    length(workspace.valid) == candidates && eltype(workspace.valid) === UInt8 &&
        length(workspace.item_counts) == items && eltype(workspace.item_counts) === Int32 &&
        length(workspace.order_a) == candidates && eltype(workspace.order_a) === Int32 &&
    length(workspace.order_b) == candidates && eltype(workspace.order_b) === Int32 &&
    length(workspace.positions) == candidates && eltype(workspace.positions) === Int32 &&
    length(workspace.count) == 1 && eltype(workspace.count) === Int32 || throw(
            LocalMathValidationError("Collect workspace does not match its physical law";
                stage = :prepare, contract = :collect_workspace_specialization,
        expected = (candidates, items, T), actual = :mismatched))
    prefix_count, sums_count = _collect_scan_storage_lengths(items)
    length(workspace.prefix) == prefix_count &&
        eltype(workspace.prefix) === Int32 &&
        length(workspace.sums) == sums_count &&
        eltype(workspace.sums) === Int32 || throw(LocalMathValidationError(
        "Collect scan workspace has an invalid packed layout";
        stage = :prepare, contract = :collect_scan_workspace,
        expected = (prefix_count, sums_count, Int32),
        actual = (length(workspace.prefix), length(workspace.sums),
            eltype(workspace.prefix), eltype(workspace.sums))))
    if _is_grouped(port.groups)
        workspace.groups !== nothing && workspace.starts !== nothing &&
            length(workspace.groups) == candidates && eltype(workspace.groups) === Int32 &&
            length(workspace.starts) == Int(port.groups.count) + 1 &&
            eltype(workspace.starts) === Int32 || throw(LocalMathValidationError(
                "grouped Collect workspace has an invalid directory";
                stage = :prepare, contract = :collect_workspace_specialization))
    else
        workspace.groups === nothing && workspace.starts === nothing || throw(
            LocalMathValidationError("one-group Collect owns no directory scratch";
                stage = :prepare, contract = :collect_workspace_specialization))
    end
    if _is_canonical_order(port.order)
        workspace.keys !== nothing && workspace.identities !== nothing || throw(
            LocalMathValidationError("canonical Collect requires key scratch";
                stage = :prepare, contract = :collect_workspace_specialization))
    else
        workspace.keys === nothing && workspace.identities === nothing || throw(
            LocalMathValidationError("source-order Collect owns no key scratch";
                stage = :prepare, contract = :collect_workspace_specialization))
    end
    return nothing
end

function _require_collect_stage_capabilities(backend, stage, workspace)
    all(operation -> _centrally_qualified_atomic_capability(
            backend, Int32, operation, :global), (:min, :max)) ||
        throw(LocalMathValidationError("Collect requires Int32 atomic minimum and maximum";
            stage = :prepare, contract = :collect_backend_capability))
    for leaf in workspace.authority.leaves
        all(operation -> _centrally_qualified_value_capability(
            backend, leaf.element_type, operation, :global),
            (:load, :store)) || throw(LocalMathValidationError(
            "Collect workspace leaf lacks a reviewed global memory capability";
            stage = :prepare, contract = :collect_backend_capability,
            workspace_leaf = leaf.name,
            expected = (leaf.element_type, :load, :store),
            actual = typeof(backend)))
    end
    for publication in stage.publications
        publication.law isa _PreparedCollectLaw || throw(LocalMathValidationError(
            "Collect execution admits only prepared Collect publications";
            stage = :prepare, contract = :collect_publication_law,
            actual = typeof(publication.law)))
    end
    return nothing
end

struct _CollectStageExecution{Q,P,W,S,G,R}
    stage::Q
    plans::P
    workspaces::W
    status::S
    gate::G
    storages::R
end
struct _CollectStagePreparation{B,E,V}
    backend::B
    execution::E
    validation::V
end
Adapt.@adapt_structure _CollectStageExecution

_collect_storages(::Tuple{}) = ()
function _collect_storages(publications::Tuple)
    return (only(first(publications).components).storage,
        _collect_storages(Base.tail(publications))...)
end
_collect_storages(stage) = _collect_storages(stage.publications)

_collect_require_port_workspaces!(::Tuple{}, ::Tuple{}) = nothing
function _collect_require_port_workspaces!(plans::Tuple, workspaces::Tuple)
    _collect_require_port_workspace(first(plans), first(workspaces))
    return _collect_require_port_workspaces!(
        Base.tail(plans), Base.tail(workspaces))
end

function _prepare_collect_stage(admission::_StageAdmission,
        workspace::_CollectStageWorkspace)
    stage = admission.stage
    _require_collect_stage_capabilities(admission.backend, stage, workspace)
    plans = _collect_port_physicals(stage)
    length(plans) == length(workspace.ports) || throw(LocalMathValidationError(
        "Collect workspace port arity disagrees with admitted Stage";
        stage = :prepare, contract = :collect_workspace_arity,
        expected = length(plans), actual = length(workspace.ports)))
    _collect_require_port_workspaces!(plans, workspace.ports)
    length(workspace.gate) == 1 && eltype(workspace.gate) === Bool &&
        length(workspace.status) == 1 && eltype(workspace.status) === Int32 ||
        throw(LocalMathValidationError("Collect status workspace has invalid schema";
            stage = :prepare, contract = :collect_workspace_specialization))
    eltype(workspace.validation) === UInt32 &&
        size(workspace.validation, 1) == _VALIDATION_STATUS_FIELDS || throw(
        LocalMathValidationError("Collect validation workspace has invalid schema";
            stage = :prepare, contract = :collect_workspace_specialization,
            expected = (UInt32, _VALIDATION_STATUS_FIELDS, :lease_columns),
            actual = (eltype(workspace.validation), size(workspace.validation))))
    return _CollectStagePreparation(admission.backend, _CollectStageExecution(
        stage, plans, workspace.ports, workspace.status, workspace.gate,
        _collect_storages(stage),
    ), workspace.validation)
end

@inline _emission_enabled(value::CollectedValue) = value.participates
@inline _emission_value(value::CollectedValue) = value.value
@inline _emission_enabled(value::GroupedCollectedValue) = value.participates
@inline _emission_value(value::GroupedCollectedValue) = value.value
@inline _emission_group(groups, value::CollectedValue) =
    _compacted_group(groups, value.value)
@inline _emission_group(::_RoutedGroups, value::GroupedCollectedValue) = value.key
@inline _collect_emission_lane(value::CollectedValue, ::Val{1}, ::Val{1}) = value
@inline _collect_emission_lane(value::GroupedCollectedValue, ::Val{1}, ::Val{1}) = value
@inline _collect_emission_lane(values::Tuple, width, lane) =
    _emission_lane(values, width, lane)

@inline function _collect_materialize_lane!(
        port::_CollectPortPhysical{K}, workspace, emission, item::Int32,
        ::Val{L},
    ) where {K,L}
    candidate = L + K * (Int(item) - 1)
    enabled = _emission_enabled(emission)
    @inbounds workspace.valid[candidate] = enabled ? UInt8(1) : UInt8(0)
    enabled || return Int32(0)
    value = _emission_value(emission)
    @inbounds begin
        _compacted_store_value!(workspace.values, candidate, value)
        workspace.groups === nothing ||
            (workspace.groups[candidate] = _emission_group(port.groups, emission))
        if workspace.keys !== nothing
            _compacted_store_value!(workspace.keys, candidate,
                _ordering_extract(port.order.key, value))
            _compacted_store_value!(workspace.identities, candidate,
                _ordering_extract(port.order.identity, value))
        end
    end
    if workspace.groups !== nothing
        group = @inbounds workspace.groups[candidate]
        if !(Int32(1) <= group <= port.groups.count)
            _collect_atomic_min!(workspace.invalid_group, 1, Int32(candidate))
        end
    end
    return Int32(1)
end

@generated function _collect_materialize_port!(
        port::_CollectPortPhysical{K}, workspace, emissions, item::Int32
    ) where {K}
    lanes = [quote
        local emission = _collect_emission_lane(emissions, Val($K), Val($lane))
        count += _collect_materialize_lane!(
            port, workspace, emission, item, Val($lane)
        )
    end for lane in 1:K]
    return quote
        local count = Int32(0)
        $(lanes...)
        @inbounds workspace.item_counts[item] = count
        nothing
    end
end

@generated function _collect_materialize_ports!(plans::P, workspaces::W,
        result::R, item::Int32) where {P<:Tuple,W<:Tuple,R<:Tuple}
    length(P.parameters) == length(W.parameters) == length(R.parameters) ||
        return :(throw(ArgumentError("Collect port arity mismatch")))
    calls = [:( _collect_materialize_port!(
        getfield(plans, $index), getfield(workspaces, $index),
        getfield(result, $index), item)) for index in eachindex(P.parameters)]
    return Expr(:block, calls..., :(nothing))
end

@inline _collect_set_failure!(status, code::Int32) = begin
    Atomix.@atomic max(status[1], code)
    nothing
end

@inline _collect_initialize_ports!(::Tuple{}, index) = nothing
@inline function _collect_initialize_ports!(workspaces::Tuple, index)
    workspace = first(workspaces)
    _initialize_compacted_port!(workspace, index,
        Int32(length(workspace.valid)) + Int32(1))
    return _collect_initialize_ports!(Base.tail(workspaces), index)
end

@kernel function _collect_stage_reset_kernel!(workspaces,
        status, gate, validation, lease::Int32, extent::Int32)
    index = @index(Global, Linear)
    if index <= extent
        # Tuple-recursive expansion keeps every device store monomorphic even
        # when Collect publishes heterogeneous ports.
        _collect_initialize_ports!(workspaces, index)
    end
    if index == 1
        @inbounds begin
            status[1] = _COLLECT_STATUS_SUCCESS
            gate[1] = false
            _clear_validation_status!(validation, lease)
        end
    end
end

@kernel function _collect_stage_evaluate_kernel!(qualified, plans, workspaces,
        status, predecessors, lease::Int32)
    raw = @index(Global, Linear)
    item = Int32(raw)
    stage = qualified.stage
    gate_open = _stage_gate_open(stage.control.gate, stage,
        qualified.parameters)
    if _candidate_prefix_succeeded(predecessors, lease) && gate_open
        prefix = _stage_prefix_value(stage.control.prefix, stage,
            qualified.parameters)
        valid_prefix = prefix isa Integer && !(prefix isa Bool) &&
            0 <= prefix <= stage.source_count
        item == 1 && !valid_prefix && _collect_set_failure!(
            status, _COLLECT_STATUS_INVALID_CONTROL)
        if item <= stage.source_count && valid_prefix
            _, active = _stage_control_state(stage, qualified.parameters, item)
            access_valid = _stage_accesses_valid(
                stage.accesses, stage.fields, item)
            access_valid || _collect_set_failure!(
                status, _COLLECT_STATUS_INVALID_CONTROL)
            if active && access_valid
                result = _call_stage_evaluator(qualified, item,
                    _stage_reads(stage, item), qualified.parameters)
                _collect_materialize_ports!(plans, workspaces,
                    result, item)
            end
        end
    end
end

@inline function _collect_final_order(plan, workspace)
    plan.sort_required || return workspace.order_a
    return isodd(plan.merge_passes) ? workspace.order_b : workspace.order_a
end

@inline _collect_valid_diagnostic() = _compacted_valid_diagnostic()
@inline function _collect_validate_ports!(::Tuple{}, ::Tuple{}, index::Int32)
    _collect_valid_diagnostic()
end
@inline function _collect_validate_ports!(plans::Tuple, workspaces::Tuple,
        index::Int32)
    diagnostic = _compacted_validate_port(first(plans), first(workspaces),
        _collect_final_order(first(plans), first(workspaces)), index)
    diagnostic.code == _COMPACTED_VALID || return diagnostic
    return _collect_validate_ports!(Base.tail(plans), Base.tail(workspaces),
        index + Int32(1))
end

@kernel function _collect_stage_finalize_kernel!(plans, workspaces, status,
        gate, validation, program_validation, predecessors, lease::Int32)
    index = @index(Global, Linear)
    if index == 1
        if _candidate_prefix_succeeded(predecessors, lease) &&
                @inbounds(status[1]) == _COLLECT_STATUS_SUCCESS
            diagnostic = _collect_validate_ports!(plans,
                workspaces, Int32(1))
            if diagnostic.code == _COMPACTED_VALID
                @inbounds gate[1] = true
            else
                @inbounds begin
                    gate[1] = false
                    status[1] = Int32(diagnostic.code)
                end
                _store_validation_status!(validation, lease,
                    diagnostic.code, diagnostic.port, diagnostic.primary,
                    diagnostic.secondary, diagnostic.witness)
                _store_program_validation_status!(program_validation,
                    lease, diagnostic.code, diagnostic.port,
                    diagnostic.primary, diagnostic.secondary,
                    diagnostic.witness)
            end
        elseif _candidate_prefix_succeeded(predecessors, lease)
            _store_validation_status!(validation, lease,
                @inbounds(status[1]), Int32(0), Int32(0), Int32(0),
                UInt32(0))
            _store_program_validation_status!(program_validation,
                lease, @inbounds(status[1]),
                Int32(0), Int32(0), Int32(0), UInt32(0))
        end
    end
end

function _collect_launch_scan!(backend, workspace)
    current = length(workspace.item_counts)
    prefix_offset = 0
    sums_offset = 0
    blocks = max(cld(current, _COLLECT_BLOCK), 1)
    output = _collect_scan_level(workspace.prefix, prefix_offset, current)
    sums = _collect_scan_level(workspace.sums, sums_offset, blocks)
    extent = blocks * _COLLECT_BLOCK
    _compacted_scan_block_kernel!(backend, _COLLECT_BLOCK, extent)(
        workspace.item_counts, output, sums, Int32(current); ndrange = extent)
    prefix_offset += current
    sums_offset += blocks
    current = blocks
    input = sums
    while current > 1
        blocks = max(cld(current, _COLLECT_BLOCK), 1)
        output = _collect_scan_level(workspace.prefix, prefix_offset, current)
        sums = _collect_scan_level(workspace.sums, sums_offset, blocks)
        extent = blocks * _COLLECT_BLOCK
        _compacted_scan_block_kernel!(backend, _COLLECT_BLOCK, extent)(
            input, output, sums, Int32(length(input)); ndrange = extent)
        prefix_offset += current
        sums_offset += blocks
        current <= _COLLECT_BLOCK && break
        current = blocks
        input = sums
    end
    levels = _collect_scan_level_count(length(workspace.item_counts))
    for level in (levels - 1):-1:1
        size = length(workspace.item_counts)
        child_offset = 0
        for prior in 1:(level - 1)
            child_offset += size
            size = max(cld(size, _COLLECT_BLOCK), 1)
        end
        parent_size = max(cld(size, _COLLECT_BLOCK), 1)
        parent_offset = child_offset + size
        prefix = _collect_scan_level(workspace.prefix, child_offset, size)
        parent = _collect_scan_level(
            workspace.prefix, parent_offset, parent_size)
        extent = max(length(prefix), 1)
        _compacted_scan_add_kernel!(backend, min(extent, _COLLECT_BLOCK), extent)(
            prefix, parent, Int32(length(prefix)); ndrange = extent)
    end
    return nothing
end

function _collect_launch_order!(backend, plan, workspace)
    candidates = Int(plan.candidate_count)
    items = div(candidates, _collect_width(plan))
    prefix = _collect_scan_level(workspace.prefix, 0, items)
    extent = max(items, 1)
    _compacted_scatter_kernel!(backend, min(extent, _COLLECT_BLOCK), extent)(
        workspace.valid, workspace.item_counts, prefix, workspace.order_a,
        workspace.positions, workspace.count, Val(_collect_width(plan)),
        Int32(items); ndrange = extent)
    plan.sort_required || return nothing
    local_extent = max(cld(candidates, _COLLECT_BLOCK), 1) * _COLLECT_BLOCK
    _compacted_local_bitonic_kernel!(backend, _COLLECT_BLOCK, local_extent)(
        plan, workspace, workspace.count, Int32(candidates); ndrange = local_extent)
    width, to_b = _COLLECT_BLOCK, true
    while width < candidates
        source, destination = to_b ? (workspace.order_a, workspace.order_b) :
            (workspace.order_b, workspace.order_a)
        _compacted_merge_kernel!(backend, min(candidates, _COLLECT_BLOCK), candidates)(
            plan, workspace, source, destination, workspace.count, Int32(width),
            Int32(candidates); ndrange = candidates)
        width *= 2
        to_b = !to_b
    end
    if _is_grouped(plan.groups)
        groups = Int(plan.groups.count) + 1
        _compacted_directory_kernel!(backend, min(groups, _COLLECT_BLOCK), groups)(
            workspace, _collect_final_order(plan, workspace), Int32(plan.groups.count);
            ndrange = groups)
    end
    if _is_canonical_order(plan.order)
        extent = max(candidates, 1)
        _compacted_validate_order_kernel!(backend, min(extent, _COLLECT_BLOCK), extent)(
            plan, workspace, _collect_final_order(plan, workspace); ndrange = extent)
    end
    return nothing
end

function _collect_publish_chunk!(backend, plans::Tuple, workspaces::Tuple,
        storages::Tuple, gate)
    extents = map(plans) do plan
        Int32(max(max(Int(plan.capacity), Int(plan.candidate_count)),
            _collect_directory_extent(plan.groups), 1))
    end
    groupeds = map(plan -> _collect_grouped(plan.groups), plans)
    extent = maximum(Int, extents)
    _compacted_publish_ports_kernel!(backend,
        min(extent, _COLLECT_BLOCK), extent)(storages, workspaces, gate,
        groupeds, extents; ndrange = extent)
    return nothing
end

_collect_publish_chunks!(backend, ::Tuple{}, ::Tuple{}, ::Tuple{}, gate) =
    nothing
function _collect_publish_chunks!(backend,
        plans::Tuple{P}, workspaces::Tuple{W}, storages::Tuple{S}, gate
    ) where {P,W,S}
    _collect_publish_chunk!(backend, plans, workspaces, storages, gate)
end
function _collect_publish_chunks!(backend,
        plans::Tuple{P1,P2}, workspaces::Tuple{W1,W2},
        storages::Tuple{S1,S2}, gate
    ) where {P1,P2,W1,W2,S1,S2}
    _collect_publish_chunk!(backend, plans, workspaces, storages, gate)
end
function _collect_publish_chunks!(backend,
        plans::Tuple{P1,P2,P3}, workspaces::Tuple{W1,W2,W3},
        storages::Tuple{S1,S2,S3}, gate
    ) where {P1,P2,P3,W1,W2,W3,S1,S2,S3}
    _collect_publish_chunk!(backend, plans, workspaces, storages, gate)
end
function _collect_publish_chunks!(backend, plans::Tuple, workspaces::Tuple,
        storages::Tuple, gate)
    head_plans = (plans[1], plans[2], plans[3], plans[4])
    head_workspaces = (workspaces[1], workspaces[2],
        workspaces[3], workspaces[4])
    head_storages = (storages[1], storages[2], storages[3], storages[4])
    _collect_publish_chunk!(backend, head_plans, head_workspaces,
        head_storages, gate)
    _collect_publish_chunks!(backend,
        Base.tail(Base.tail(Base.tail(Base.tail(plans)))),
        Base.tail(Base.tail(Base.tail(Base.tail(workspaces)))),
        Base.tail(Base.tail(Base.tail(Base.tail(storages)))), gate)
    return nothing
end

"""Enqueue one Collect Stage on the provider tail; never synchronize here."""
function _execute_collect_stage!(prepared::_CollectStagePreparation,
        parameters::Tuple, lease_index::Int32, predecessors::Tuple,
        relation_guard, program_validation)
    execution = prepared.execution
    qualified = _QualifiedEvaluation(_stage_evaluation(execution.stage),
        _stage_runtime_parameters(parameters, execution.stage))
    backend = prepared.backend
    predecessor_statuses = (relation_guard, predecessors...)
    extent = max(Int(execution.stage.source_count),
        maximum((Int(plan.candidate_count) for plan in execution.plans); init = 0), 1)
    _collect_stage_reset_kernel!(backend, min(extent, _COLLECT_BLOCK), extent)(
        execution.workspaces, execution.status,
        execution.gate, prepared.validation, lease_index,
        Int32(extent); ndrange = extent)
    _launch_stage_relation_receipt!(backend, relation_guard,
        prepared.validation, program_validation, lease_index)
    _collect_stage_evaluate_kernel!(backend)(qualified, execution.plans,
        execution.workspaces, execution.status, predecessor_statuses,
        lease_index; ndrange = max(Int(execution.stage.source_count), 1))
    foreach(workspace -> _collect_launch_scan!(backend, workspace), execution.workspaces)
    foreach(pair -> _collect_launch_order!(backend, pair...),
        zip(execution.plans, execution.workspaces))
    _collect_stage_finalize_kernel!(backend, 1, 1)(execution.plans,
        execution.workspaces, execution.status, execution.gate,
        prepared.validation, program_validation, predecessor_statuses,
        lease_index; ndrange = 1)
    _collect_publish_chunks!(backend, execution.plans,
        execution.workspaces, execution.storages, execution.gate)
    return prepared
end
