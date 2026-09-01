# Domain-owned records and scalar compilation for lifecycle materialization.
# LocalMath owns bounded collection, grouping, canonical order, publication,
# and the shared KernelAbstractions execution family.

struct _LifecycleOwnedSite
    owner::Int32
    site::Int32
end

struct _LifecycleRequestSource
    priority::Int32
    source_high::UInt32
    source_low::UInt32
    action_high::UInt32
    action_low::UInt32
    anchor::Int32
    generation::UInt32
    active::Bool
end

struct _LifecycleEmissionRecord
    descriptor::Int32
    anchor::Int32
    generation::UInt32
    priority::Int32
    source_high::UInt32
    source_low::UInt32
    action_high::UInt32
    action_low::UInt32
    occurrence::Int32
    active::Bool
    status_code::ProgramStatusCode
    status_detail::ProgramStatusDetailCode
end

struct _LifecycleCanonicalRequest
    slot::Int32
    key::Tuple{Int32, UInt32, UInt32, UInt32}
    identity::Tuple{UInt32, Int32, UInt32, Int32}
end

struct _LifecycleSiteView{R}
    records::R
    first::Int32
    count::Int32
end
Base.length(view::_LifecycleSiteView) = Int(view.count)
@inline Base.getindex(view::_LifecycleSiteView, index::Integer) =
    @inbounds view.records[view.first + Int32(index) - Int32(1)]
@inline Base.iterate(view::_LifecycleSiteView, index::Int32=Int32(1)) =
    index > view.count ? nothing : (view[index], index + Int32(1))

struct _SequentialLifecycleOpenGate{S} <: AbstractVector{Bool}
    status::S
end

Base.size(::_SequentialLifecycleOpenGate) = (1,)
Base.length(::_SequentialLifecycleOpenGate) = 1
Base.strides(::_SequentialLifecycleOpenGate) = (1,)
Base.IndexStyle(::Type{<:_SequentialLifecycleOpenGate}) = IndexLinear()
@inline function Base.getindex(
        gate::_SequentialLifecycleOpenGate, index::Integer
    )
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.status[1]).code === ProgramStatusSuccess
end
KernelAbstractions.get_backend(gate::_SequentialLifecycleOpenGate) =
    KernelAbstractions.get_backend(gate.status)

struct _LifecycleDecisionDescriptorPlan{R}
    domain_resources::R
end

struct _LifecycleDecisionProgram{N, TP, D, L}
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    medium_kind::Int16
    tracker_plan::TP
    descriptor_plan::D
    lifecycle_plan::L
end

Adapt.@adapt_structure _LifecycleDecisionDescriptorPlan
Adapt.@adapt_structure _LifecycleDecisionProgram

struct _LifecycleDecisionRuntime{
        P, O, K, G, T, R, D, W, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::T
    relationships::R
    descriptor_state::D
    lifecycle_workspace::W
    parameters::A
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
end

Adapt.@adapt_structure _LifecycleDecisionRuntime

struct _SequentialLifecycleCompaction{O, S, R, E, L, G}
    ownerships::O
    site_indices::S
    request_index::R
    emission::E
    selection::L
    gate::G
end

struct _LifecycleSiteCompactionOperation
    cell_capacity::Int32
end

struct _LifecycleSiteSource end
struct _LifecycleRequestSlot end
struct _LifecycleGateNode end
struct _LifecycleSiteOwnerKey end
struct _LifecycleRequestKey end
struct _LifecycleRequestIdentity end

@inline (::_LifecycleSiteOwnerKey)(record::_LifecycleOwnedSite) = record.owner
@inline (::_LifecycleRequestKey)(record::_LifecycleCanonicalRequest) = record.key
@inline (::_LifecycleRequestIdentity)(record::_LifecycleCanonicalRequest) =
    record.identity

@inline function (operation::_LifecycleSiteCompactionOperation)(
        site::Int32, reads, parameters
    )
    owner = something(@inbounds reads[1][1].value)
    open = something(@inbounds reads[2][1].value)
    enabled = open && Int32(1) <= owner <= operation.cell_capacity
    return (sites = LocalMath.CollectedValue(
        _LifecycleOwnedSite(owner, site), enabled),)
end

struct _LifecycleRequestCompactionOperation end

@inline function _lifecycle_descriptor_for_request(offsets, request::Int32)
    lower = 1
    upper = length(offsets)
    while lower < upper
        middle = lower + ((upper - lower + 1) >>> 1)
        if @inbounds(offsets[middle]) <= request
            lower = middle
        else
            upper = middle - 1
        end
    end
    return lower
end

@inline function _emit_lifecycle_request!(
        base_runtime, request_offsets, destination, request::Int32,
        current_mcs::Int64,
    )
    runtime = _lifecycle_evaluation_state(base_runtime, current_mcs)
    workspace = runtime.lifecycle_workspace
    descriptor_index = _lifecycle_descriptor_for_request(
        request_offsets, request
    )
    descriptor = @inbounds runtime.program.lifecycle_plan.descriptors[
        descriptor_index
    ]
    first_request = @inbounds request_offsets[descriptor_index]
    lane = request - first_request + Int32(1)
    anchor = descriptor.domain === ModelLifecycleDomain ? Int32(0) : lane
    eligible = _lifecycle_due(descriptor, Int(current_mcs) + 1) &&
        !(descriptor.domain === ModelLifecycleDomain && lane != 1)
    if eligible && anchor > 0
        eligible = @inbounds(runtime.cell_kinds[anchor]) == descriptor.domain_kind
    end
    generation = anchor > 0 ?
        @inbounds(runtime.cell_generations[anchor]) : UInt32(0)
    status_code = ProgramStatusSuccess
    status_detail = LifecycleDetailNone
    if eligible && anchor > 0 && iszero(generation)
        status_code = ProgramStatusStaleGeneration
        eligible = false
    elseif eligible
        context = _LifecycleTriggerContext(
            runtime,
            descriptor.source_identity,
            descriptor.action_identity,
            descriptor.trigger_workspace_maximum,
            Int32(0),
            request,
            anchor,
            generation,
            _lifecycle_context_site(runtime, workspace, anchor),
            Int32(0),
            UInt16(descriptor.source_handle),
        )
        enabled = evaluate_lifecycle(
            runtime.program.lifecycle_plan.evaluators,
            descriptor.trigger_evaluator,
            context,
        )
        if enabled isa AbstractFloat && !isfinite(enabled)
            status_code = ProgramStatusEvaluator
            status_detail = LifecycleDetailNonfiniteResult
            eligible = false
        elseif !(enabled isa Bool)
            status_code = ProgramStatusEvaluator
            status_detail = LifecycleDetailTriggerNotBoolean
            eligible = false
        else
            eligible = enabled
        end
    end
    record = _LifecycleEmissionRecord(
        Int32(descriptor_index),
        anchor,
        generation,
        descriptor.priority,
        _lifecycle_identity_high(descriptor.source_identity),
        _lifecycle_identity_low(descriptor.source_identity),
        _lifecycle_identity_high(descriptor.action_identity),
        _lifecycle_identity_low(descriptor.action_identity),
        Int32(0),
        eligible,
        status_code,
        status_detail,
    )
    @inbounds destination[request] = record
    return nothing
end

@kernel function _lifecycle_request_emission_kernel!(
        runtime, request_offsets, destination, gate, current_mcs::Int64,
    )
    index = @index(Global, Linear)
    request = Int32(index)
    if @inbounds(gate[1]) && request <= length(destination)
        _emit_lifecycle_request!(
            runtime, request_offsets, destination, request, current_mcs)
    end
end

@kernel function _lifecycle_emission_status_kernel!(
        runtime, requests, status, gate, current_mcs::Int64,
    )
    index = @index(Global, Linear)
    if index == 1 && @inbounds(gate[1])
        for request in Int32(1):Int32(length(requests))
            record = @inbounds requests[request]
            code = record.status_code
            code === ProgramStatusSuccess && continue
            descriptor = @inbounds runtime.program.lifecycle_plan.descriptors[
                Int(record.descriptor)]
            @inbounds status[1] = _lifecycle_backend_status(
                code;
                mcs = Int32(current_mcs + Int64(1)),
                stage = ProgramStageEmission,
                source = Int32(descriptor.source_handle),
                action_identity = descriptor.action_identity,
                anchor = record.anchor,
                detail = record.status_detail,
            )
            break
        end
    end
end

@inline _lifecycle_identity_high(value::UInt64) = UInt32(value >> 32)
@inline _lifecycle_identity_low(value::UInt64) =
    UInt32(value & UInt64(typemax(UInt32)))

@inline function (::_LifecycleRequestCompactionOperation)(
        slot::Int32, reads, parameters
    )
    source = something(@inbounds reads[1][1].value)
    open = something(@inbounds reads[2][1].value)
    enabled = open && source.active
    record = _LifecycleCanonicalRequest(
        slot,
        (
            source.priority,
            source.source_high,
            source.source_low,
            source.action_high,
        ),
        (
            source.action_low,
            source.anchor,
            source.generation,
            -slot,
        ),
    )
    return (canonical_requests = LocalMath.CollectedValue(record, enabled),)
end

@kernel function _fill_lifecycle_singleton_endpoints_kernel!(endpoints)
    item = @index(Global, Linear)
    item <= size(endpoints, 2) &&
        (@inbounds endpoints[1, item] = Int32(1))
end

@kernel function _initialize_lifecycle_relation_authority_kernel!(
        generations, statuses, validated_generations
    )
    slot = @index(Global, Linear)
    if slot <= length(generations)
        @inbounds begin
            generations[slot] = UInt64(1)
            statuses[slot] = Int32(0)
            validated_generations[slot] = UInt64(0)
        end
    end
end

@kernel function _initialize_lifecycle_compacted_count_kernel!(count)
    index = @index(Global, Linear)
    index == 1 && (@inbounds count[1] = Int32(0))
end

function _allocate_lifecycle_relation_authority(backend, count::Integer)
    slots = Int(count)
    generations = KernelAbstractions.allocate(backend, UInt64, (slots,))
    statuses = KernelAbstractions.allocate(backend, Int32, (slots,))
    validated_generations = KernelAbstractions.allocate(
        backend, UInt64, (slots,))
    _initialize_lifecycle_relation_authority_kernel!(backend)(
        generations, statuses, validated_generations; ndrange = slots)
    KernelAbstractions.synchronize(backend)
    return (; generations, statuses, validated_generations)
end

function _allocate_lifecycle_compaction_results(
        plan::LifecycleExecutionPlan, ownership, selection
    )
    backend = KernelAbstractions.get_backend(ownership)
    site_count = length(ownership)
    request_count = Int(plan.maximum_requests)
    site_index = LocalMath.CompactedStorage(
        backend,
        _LifecycleOwnedSite,
        site_count;
        group_count = Int(plan.cell_capacity),
        source_items = site_count,
        source_position = true,
    )
    request_index = LocalMath.CompactedStorage(
        backend,
        _LifecycleCanonicalRequest,
        request_count;
        source_items = request_count,
        source_position = true,
    )
    _initialize_lifecycle_compacted_count_kernel!(backend)(
        site_index.count; ndrange = 1)
    _initialize_lifecycle_compacted_count_kernel!(backend)(
        request_index.count; ndrange = 1)
    for storage in (
            selection.free_cells,
            selection.demands,
            selection.selected_requests,
        )
        _initialize_lifecycle_compacted_count_kernel!(backend)(
            storage.count; ndrange = 1)
    end
    KernelAbstractions.synchronize(backend)
    return site_index, request_index
end

function _lifecycle_site_compaction_work(site_shape, cell_capacity::Int)
    source = LocalMath.Space(_LifecycleSiteSource, site_shape)
    site_count = length(source)
    gate_space = LocalMath.Space(_LifecycleGateNode, 1)
    ownership = LocalMath.Field(source, Int32)
    gate = LocalMath.Field(gate_space, Bool)
    ownership_relation = LocalMath.IdentityRelation(source)
    gate_relation = LocalMath.FixedRelation(source => gate_space; degree = 1)
    sites = LocalMath.Collection(_LifecycleOwnedSite, site_count)
    publication = LocalMath.Publication((
        LocalMath.CollectionPublication(
            sites, LocalMath.PublicationValue(:sites)),
    ), LocalMath.Collect(
        _LifecycleOwnedSite;
        maximum = 1,
        groups = LocalMath.group_by(
            _LifecycleSiteOwnerKey(); count = cell_capacity),
        order = LocalMath.source_order(),
        projection = LocalMath.persistent_source_position(),
    ))
    stage = LocalMath.Stage(
        source,
        (
            ownership = LocalMath.Access(ownership, ownership_relation),
            gate = LocalMath.Access(gate, gate_relation),
        ),
        (publication,),
        LocalMath.Evaluator(
            _LifecycleSiteCompactionOperation(Int32(cell_capacity))),
        LocalMath.Control(),
        LocalMath.SourceOrigin(
            @__FILE__, @__LINE__; label = :corepotts_lifecycle_site_index),
    )
    return (; law = LocalMath.LocalLaw(stage), ownership, gate, sites,
        ownership_relation, gate_relation)
end

function _lifecycle_request_compaction_work(capacity::Integer)
    capacity = Int(capacity)
    capacity >= 0 || throw(ArgumentError(
        "lifecycle request capacity must be nonnegative"))
    source = LocalMath.Space(_LifecycleRequestSlot, capacity)
    gate_space = LocalMath.Space(_LifecycleGateNode, 1)
    requests = LocalMath.Field(source, _LifecycleRequestSource)
    gate = LocalMath.Field(gate_space, Bool)
    request_relation = LocalMath.IdentityRelation(source)
    gate_relation = LocalMath.FixedRelation(source => gate_space; degree = 1)
    canonical = LocalMath.Collection(_LifecycleCanonicalRequest, capacity)
    publication = LocalMath.Publication((
        LocalMath.CollectionPublication(
            canonical,
            LocalMath.PublicationValue(:canonical_requests)),
    ), LocalMath.Collect(
        _LifecycleCanonicalRequest;
        maximum = 1,
        groups = LocalMath.one_group(),
        order = LocalMath.canonical_by(
            _LifecycleRequestKey(), _LifecycleRequestIdentity()),
        projection = LocalMath.persistent_source_position(),
    ))
    stage = LocalMath.Stage(
        source,
        (
            requests = LocalMath.Access(requests, request_relation),
            gate = LocalMath.Access(gate, gate_relation),
        ),
        (publication,),
        LocalMath.Evaluator(_LifecycleRequestCompactionOperation()),
        LocalMath.Control(),
        LocalMath.SourceOrigin(
            @__FILE__, @__LINE__; label = :corepotts_lifecycle_requests),
    )
    return (; law = LocalMath.LocalLaw(stage), requests, gate, canonical,
        request_relation, gate_relation)
end

_lifecycle_request_compaction_work(plan::LifecycleExecutionPlan) =
    _lifecycle_request_compaction_work(plan.maximum_requests)

struct _PreparedLifecycleEmission{R,O,D,S,G,B}
    runtime::R
    request_offsets::O
    destination::D
    status::S
    gate::G
    backend::B
end

function _run_lifecycle_emission!(prepared::_PreparedLifecycleEmission, mcs::Integer)
    capacity = length(prepared.destination)
    _lifecycle_request_emission_kernel!(prepared.backend)(
        prepared.runtime, prepared.request_offsets, prepared.destination,
        prepared.gate, Int64(mcs); ndrange = capacity)
    _lifecycle_emission_status_kernel!(prepared.backend)(
        prepared.runtime, prepared.destination, prepared.status,
        prepared.gate, Int64(mcs); ndrange = 1)
    return nothing
end

function _prepare_sequential_lifecycle_compaction(
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
        ownerships::Tuple,
        sciences::Tuple,
    )
    length(sciences) == length(ownerships) || throw(ArgumentError(
        "sequential lifecycle science banks must align with ownership banks"
    ))
    all(zip(ownerships, sciences)) do (ownership, science)
        science.ownership === ownership
    end || throw(ArgumentError(
        "each sequential lifecycle decision runtime must own its positional " *
        "ownership bank"
    ))
    backend = KernelAbstractions.get_backend(first(ownerships))
    all(ownership -> KernelAbstractions.get_backend(ownership) == backend,
        ownerships) || throw(ArgumentError(
        "sequential ownership banks must share one backend"
    ))
    site_spec = _lifecycle_site_compaction_work(
        size(first(ownerships)), Int(plan.cell_capacity)
    )
    capacity = Int(plan.maximum_requests)
    request_spec = _lifecycle_request_compaction_work(plan)
    gate = _SequentialLifecycleOpenGate(workspace.status)
    site_indices = map(ownerships) do ownership
        length(ownership) == length(first(ownerships)) || throw(ArgumentError(
            "sequential ownership banks must have equal lengths"
        ))
        endpoints = similar(ownership, Int32, 1, length(ownership))
        _fill_lifecycle_singleton_endpoints_kernel!(backend)(
            endpoints; ndrange = length(ownership))
        KernelAbstractions.synchronize(backend)
        LocalMath.prepare(site_spec.law,
            site_spec.ownership => ownership,
            site_spec.gate => gate,
            site_spec.gate_relation => (endpoints = endpoints,),
            site_spec.sites => workspace.site_index;
            backend, lease_capacity = 1)
    end
    request_endpoints = similar(first(ownerships), Int32, 1, capacity)
    _fill_lifecycle_singleton_endpoints_kernel!(backend)(
        request_endpoints; ndrange = capacity)
    KernelAbstractions.synchronize(backend)
    request_index = LocalMath.prepare(request_spec.law,
        request_spec.requests => _lifecycle_request_source(workspace),
        request_spec.gate => gate,
        request_spec.gate_relation => (endpoints = request_endpoints,),
        request_spec.canonical => workspace.request_index;
        backend, lease_capacity = 1)
    emission_status_code = fill(ProgramStatusSuccess, capacity)
    emission_status_detail = fill(LifecycleDetailNone, capacity)
    emission = map(sciences) do science
        _PreparedLifecycleEmission(
            science, _lifecycle_request_offsets(plan),
            _lifecycle_emission_destination(
                workspace, emission_status_code, emission_status_detail),
            workspace.status, gate, backend)
    end
    selection = map(sciences) do science
        _prepare_lifecycle_selection(
            plan, workspace, science, gate; lease_capacity = 1
        )
    end
    return _SequentialLifecycleCompaction(
        ownerships, site_indices, request_index, emission, selection, gate
    )
end

function _active_lifecycle_operations(runtime)
    compaction = runtime.engine_workspace.lifecycle_compaction
    compaction isa _SequentialLifecycleCompaction || throw(ArgumentError(
        "lifecycle execution lacks prepared operations"
    ))
    bank = findfirst(ownership -> ownership === runtime.ownership,
        compaction.ownerships)
    bank === nothing && throw(ArgumentError(
        "active sequential ownership is not a prepared physical bank"
    ))
    return (
        site_index = compaction.site_indices[bank],
        request_index = compaction.request_index,
        emission = compaction.emission[bank],
        selection = compaction.selection[bank],
    )
end

function _run_host_lifecycle_site_index!(runtime, workspace)
    operations = _active_lifecycle_operations(runtime)
    wait(LocalMath.execute!(operations.site_index))
    return workspace
end

function _run_host_lifecycle_request_index!(runtime, workspace)
    operations = _active_lifecycle_operations(runtime)
    wait(LocalMath.execute!(operations.request_index))
    return workspace
end

function _run_host_lifecycle_emission!(runtime, workspace)
    prepared = _active_lifecycle_operations(runtime).emission
    _run_lifecycle_emission!(prepared, runtime.mcs)
    KernelAbstractions.synchronize(prepared.backend)
    return _lifecycle_succeeded(workspace)
end

function _run_host_lifecycle_selection!(runtime, workspace)
    prepared = _active_lifecycle_operations(runtime).selection
    wait(LocalMath.execute!(
        prepared; parameters = (current_mcs = Int64(runtime.mcs),)
    ))
    return _lifecycle_succeeded(workspace)
end

function _lifecycle_request_source(workspace::LifecycleWorkspace)
    return StructArrays.StructArray{_LifecycleRequestSource}((
        priority = workspace.request_priority,
        source_high = workspace.request_source_high,
        source_low = workspace.request_source_low,
        action_high = workspace.request_action_high,
        action_low = workspace.request_action_low,
        anchor = workspace.anchor,
        generation = workspace.generation,
        active = workspace.active,
    ))
end

function _lifecycle_emission_destination(
        workspace::LifecycleWorkspace, control
    )
    return _lifecycle_emission_destination(
        workspace,
        control.emission_status_code,
        control.emission_status_detail,
    )
end


function _lifecycle_emission_destination(
        workspace::LifecycleWorkspace, status_code, status_detail
    )
    return StructArrays.StructArray{_LifecycleEmissionRecord}((
        descriptor = workspace.descriptor,
        anchor = workspace.anchor,
        generation = workspace.generation,
        priority = workspace.request_priority,
        source_high = workspace.request_source_high,
        source_low = workspace.request_source_low,
        action_high = workspace.request_action_high,
        action_low = workspace.request_action_low,
        occurrence = workspace.occurrence,
        active = workspace.active,
        status_code,
        status_detail,
    ))
end

function _lifecycle_site_compacted_storage(plan, workspace::LifecycleWorkspace)
    return workspace.site_index
end

function _lifecycle_request_compacted_storage(
        plan, workspace::LifecycleWorkspace
    )
    return workspace.request_index
end

@inline function _lifecycle_site_records(workspace, cell::Int32)
    storage = workspace.site_index
    first = @inbounds storage.segment_starts[cell]
    stop = @inbounds storage.segment_starts[cell + Int32(1)]
    return _LifecycleSiteView(storage.records, first, stop - first)
end

@inline _lifecycle_site_count(workspace, cell::Int32) =
    length(_lifecycle_site_records(workspace, cell))

@inline function _lifecycle_site_position(workspace, site::Integer)
    @inbounds return workspace.site_index.source_position[site]
end

@inline _lifecycle_canonical_request_count(workspace) =
    @inbounds workspace.request_index.count[1]

@inline function _lifecycle_canonical_request(workspace, position::Integer)
    @inbounds return workspace.request_index.records[position]
end

@inline _lifecycle_canonical_request_slot(workspace, position::Integer) =
    _lifecycle_canonical_request(workspace, position).slot
