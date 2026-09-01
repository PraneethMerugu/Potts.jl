# Portable checkerboard candidate, deterministic claim, evaluation, and commit.

const _PROGRAM_CHECKERBOARD_PENDING = UInt8(0)
const _PROGRAM_CHECKERBOARD_NULL = UInt8(1)
const _PROGRAM_CHECKERBOARD_CONFLICT = UInt8(2)
const _PROGRAM_CHECKERBOARD_CONSTRAINT = UInt8(3)
const _PROGRAM_CHECKERBOARD_ENERGY = UInt8(4)
const _PROGRAM_CHECKERBOARD_ACCEPTED = UInt8(5)
const _PROGRAM_CHECKERBOARD_NONFINITE = UInt8(6)
const _PROGRAM_CHECKERBOARD_ZERO_T_DRIVE = UInt8(7)

_empty_checkerboard_receipt_bank() =
    (LocalMath.ExecutionReceipt[], LocalMath.ExecutionReceipt[])

@inline _record_checkerboard_receipt!(bank, index, ::Nothing) = nothing
@inline function _record_checkerboard_receipt!(
        bank, index, receipt::LocalMath.ExecutionReceipt,
    )
    push!(bank[Int(index)], receipt)
    return receipt
end

function _empty_checkerboard_receipts()
    return (
        mechanics = _empty_checkerboard_receipt_bank(),
        lifecycle = (
            direct = _empty_checkerboard_receipt_bank(),
            planning = _empty_checkerboard_receipt_bank(),
            site_index = _empty_checkerboard_receipt_bank(),
            request_index = _empty_checkerboard_receipt_bank(),
            emission = _empty_checkerboard_receipt_bank(),
            selection = _empty_checkerboard_receipt_bank(),
        ),
    )
end

"""Mutable queued, completed, committed, and materialized MCS position."""
mutable struct ProgramExecutionPosition
    submitted_mcs::Int
    drained_mcs::Int
    committed_mcs::Int
    materialized_mcs::Int
    settlement_count::Int
    synchronization_count::Int
    control_transfer_count::Int
    snapshot_transfer_count::Int
    lifecycle_transfer_count::Int
end

ProgramExecutionPosition(initial_mcs::Integer = 0) = ProgramExecutionPosition(
    Int(initial_mcs), Int(initial_mcs), Int(initial_mcs), Int(initial_mcs),
    0, 0, 0, 0, 0,
)

struct _CheckerboardRelationshipBankLayout{O,C}
    edge_offsets::O
    edge_counts::C
    payload_count::Int32
end

struct _CheckerboardRelationshipLayout{S,B}
    slots::S
    banks::B
end

struct CheckerboardKernelProgram{T, N, O, R, TP, DR, L, H, C, E, RL}
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::O
    medium_kind::Int16
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    relationships::R
    tracker_plan::TP
    domain_resources::DR
    lifecycle_plan::L
    ownership_change_handles::H
    checkerboard_plan::C
    extinction_policies::E
    relationship_layout::RL
    topology_epoch::UInt64
end

struct CheckerboardExecutionState{
        P, O, K, G, TS, R, D, L, C, PS, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
    lifecycle_workspace::L
    lifecycle_control::C
    program_status::PS
    parameters::A
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
end

Adapt.@adapt_structure CheckerboardKernelProgram
Adapt.@adapt_structure CheckerboardExecutionState

function _checkerboard_logical_topology_epoch(
        plan::CheckerboardPlan, proposal_offsets
    )
    for (name, storage) in (
            (:sites, plan.sites),
            (:color_offsets, plan.color_offsets),
            (:conflict_displacements, plan.conflict_displacements),
            (:proposal_offsets, proposal_offsets),
        )
        backend = KernelAbstractions.get_backend(storage)
        backend isa KernelAbstractions.CPU || throw(ArgumentError(
            "checkerboard logical topology epoch requires host-resident canonical $name"
        ))
    end
    io = IOBuffer()
    write(io, "corepotts/checkerboard-logical-topology/v1")
    foreach(value -> write(io, Int64(value)), plan.shape)
    foreach(value -> write(io, UInt8(value)), plan.periodic)
    write(io, Int64(plan.color_count))
    write(io, Int64(plan.maximum_color_size))
    write(io, Int64(length(plan.sites)))
    foreach(value -> write(io, Int64(value)), plan.sites)
    write(io, Int64(length(plan.color_offsets)))
    foreach(value -> write(io, Int64(value)), plan.color_offsets)
    write(io, Int64(size(plan.conflict_displacements, 1)))
    write(io, Int64(size(plan.conflict_displacements, 2)))
    foreach(
        value -> write(io, Int64(value)), plan.conflict_displacements
    )
    write(io, Int64(size(proposal_offsets, 1)))
    write(io, Int64(size(proposal_offsets, 2)))
    foreach(value -> write(io, Int64(value)), proposal_offsets)
    digest = SHA.sha256(take!(io))
    epoch = foldl(@view(digest[1:8]); init = zero(UInt64)) do value, byte
        (value << 8) | UInt64(byte)
    end
    return iszero(epoch) ? one(UInt64) : epoch
end

"""Prepared checkerboard banks, laws, receipts, and execution position."""
struct CheckerboardWorkspace{
        S, T, O, N, P, D, M, I, U, A, Z, CO, X, EP,
    }
    state::S
    alternate_state::S
    target_sites::T
    source_sites::O
    old_owners::N
    new_owners::P
    priorities::D
    semantic_ids::M
    dispositions::I
    report::U
    capability_report::A
    color_sizes::Z
    color_order::CO
    source_table::X
    execution::EP
end

const _CHECKERBOARD_EXECUTION_SCHEMA = v"9.0.0"
const _CHECKERBOARD_CHECKPOINT_SCHEMA = v"9.0.0"
const _CHECKERBOARD_MECHANISM_IDENTITY =
    :corepotts_localmath_mechanics_v2

"""One immutable identity for capability, checkpoint, replay, and settlement."""
struct CheckerboardExecutionIdentity{D, F, G, L, R, V, Q}
    schema::VersionNumber
    mechanism_identity::Symbol
    scientific_abi::Symbol
    descriptor_fingerprint::D
    capability_fingerprint::F
    topology_epoch::UInt64
    rng_identity::G
    lowerings::L
    provider::R
    provider_compiler::V
    queue_policy::Q
    checkpoint_schema::VersionNumber
end

"""The sole checkerboard graph, including bank initialization, compiled color
mechanics, reporting, and the remaining Core-owned lifecycle boundaries."""
mutable struct _CheckerboardExecutionWorkspace{
        W, C, Z, B, L, G, Q, I, R,
    }
    core::W
    color_laws::C
    clear_report::Z
    stage_boundaries::B
    lifecycle_reductions::L
    gates::G
    receipts::Q
    identity::I
    capability_report::R
end

struct _PreparedLifecycleStatusReduction{P,C,S,O,N,G,B}
    planning::P
    candidate_status::C
    status::S
    canonical_slots::O
    canonical_count::N
    gate::G
    backend::B
    lease_capacity::Int
end

function LocalMath.submission_capacity(
        prepared::_PreparedLifecycleStatusReduction)
    capacity = prepared.lease_capacity
    outstanding = 0
    return (; capacity, outstanding,
        available = capacity, submitted = 0, drained = 0)
end
function LocalMath.submission_capacity(prepared::_PreparedLifecycleEmission)
    capacity = typemax(Int)
    outstanding = 0
    return (; capacity, outstanding,
        available = capacity, submitted = 0, drained = 0)
end

@kernel function _lifecycle_status_reduction_kernel!(
        planning::Bool, candidate_status, status, canonical_slots,
        canonical_count, gate, limit::Int32,
    )
    index = @index(Global, Linear)
    if index == 1 && @inbounds(gate[1])
        count = planning ? @inbounds(canonical_count[1]) : limit
        for position in Int32(1):count
            request = planning ?
                @inbounds(canonical_slots[position]) : position
            candidate = @inbounds candidate_status[request]
            candidate.code === ProgramStatusSuccess && continue
            @inbounds status[1] = candidate
            break
        end
    end
end

function _run_lifecycle_status!(
        prepared::_PreparedLifecycleStatusReduction, limit::Integer)
    _lifecycle_status_reduction_kernel!(prepared.backend)(
        prepared.planning, prepared.candidate_status, prepared.status,
        prepared.canonical_slots, prepared.canonical_count, prepared.gate,
        Int32(limit); ndrange = 1)
    return nothing
end

struct _LifecycleStatusGate{S, C, D} <: AbstractVector{Bool}
    status::S
    counters::C
end

Base.size(::_LifecycleStatusGate) = (1,)
Base.length(::_LifecycleStatusGate) = 1
Base.strides(::_LifecycleStatusGate) = (1,)
Base.IndexStyle(::Type{<:_LifecycleStatusGate}) = IndexLinear()
@inline function Base.getindex(
        gate::_LifecycleStatusGate{S,C,D}, index::Integer
    ) where {S,C,D}
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.status[1]).code === ProgramStatusSuccess &&
        (!D || @inbounds(gate.counters[_LIFECYCLE_CONTROL_DUE]) != Int32(0))
end

function KernelAbstractions.get_backend(gate::_LifecycleStatusGate)
    backend = KernelAbstractions.get_backend(gate.status)
    KernelAbstractions.get_backend(gate.counters) == backend || throw(
        ArgumentError("lifecycle status-gate parents belong to different backends")
    )
    return backend
end

function Adapt.adapt_structure(to, gate::_LifecycleStatusGate{S,C,D}) where {S,C,D}
    status = Adapt.adapt(to, gate.status)
    counters = Adapt.adapt(to, gate.counters)
    return _LifecycleStatusGate{
        typeof(status),
        typeof(counters),
        D,
    }(status, counters)
end

function _prepare_localmath_lifecycle_reductions(
        workspace::CheckerboardWorkspace,
        backend,
        epoch::UInt64,
        queue_mcs_capacity::Integer,
    )
    first_control = workspace.state.lifecycle_control
    first_control isa NoLifecycleBackendControl && return nothing
    capacity = length(first_control.candidate_status)
    lifecycle_plan = workspace.state.program.lifecycle_plan
    site_count = length(workspace.state.ownership)
    site_spec = _lifecycle_site_compaction_work(
        size(workspace.state.ownership), Int(lifecycle_plan.cell_capacity)
    )
    request_spec = _lifecycle_request_compaction_work(lifecycle_plan)
    site_gate_endpoints = similar(
        workspace.state.ownership, Int32, 1, site_count)
    request_gate_endpoints = similar(
        workspace.state.ownership, Int32, 1,
        Int(lifecycle_plan.maximum_requests))
    _fill_lifecycle_singleton_endpoints_kernel!(backend)(
        site_gate_endpoints; ndrange = site_count)
    _fill_lifecycle_singleton_endpoints_kernel!(backend)(
        request_gate_endpoints;
        ndrange = Int(lifecycle_plan.maximum_requests))
    KernelAbstractions.synchronize(backend)
    relation_authority = _allocate_lifecycle_relation_authority(backend, 2)
    relation_declaration(endpoints, slot) = LocalMath.MutableRelationStorage(
        (; endpoints);
        generation = relation_authority.generations,
        status = relation_authority.statuses,
        validated_generations = relation_authority.validated_generations,
        slot,
    )
    direct_leases = Int(queue_mcs_capacity)
    planning_leases = Int(queue_mcs_capacity) * 3
    return map(
            (workspace.state, workspace.alternate_state)
        ) do bank
        control = bank.lifecycle_control
        lifecycle = bank.lifecycle_workspace
        direct_gate = _LifecycleStatusGate{
            typeof(lifecycle.status), typeof(control.counters), false
        }(lifecycle.status, control.counters)
        planning_gate = _LifecycleStatusGate{
            typeof(lifecycle.status), typeof(control.counters), true
        }(lifecycle.status, control.counters)
        site_storage = _lifecycle_site_compacted_storage(nothing, lifecycle)
        request_storage = _lifecycle_request_compacted_storage(nothing, lifecycle)
        site_index = LocalMath.prepare(site_spec.law,
            site_spec.ownership => bank.ownership,
            site_spec.gate => planning_gate,
            site_spec.gate_relation => relation_declaration(
                site_gate_endpoints, 1),
            site_spec.sites => site_storage;
            backend, lease_capacity = Int(queue_mcs_capacity))
        request_index = LocalMath.prepare(request_spec.law,
            request_spec.requests => _lifecycle_request_source(lifecycle),
            request_spec.gate => planning_gate,
            request_spec.gate_relation => relation_declaration(
                request_gate_endpoints, 2),
            request_spec.canonical => request_storage;
            backend, lease_capacity = Int(queue_mcs_capacity))
        emission = _PreparedLifecycleEmission(
            bank, control.request_offsets,
            _lifecycle_emission_destination(lifecycle, control),
            lifecycle.status, planning_gate, backend)
        selection = _prepare_lifecycle_selection(
            lifecycle_plan,
            lifecycle,
            bank,
            planning_gate;
            lease_capacity = Int(queue_mcs_capacity),
        )
        direct = _PreparedLifecycleStatusReduction(
            false, control.candidate_status, lifecycle.status,
            lifecycle.request_index.records.slot,
            lifecycle.request_index.count, direct_gate, backend, direct_leases)
        planning = _PreparedLifecycleStatusReduction(
            true, control.candidate_status, lifecycle.status,
            lifecycle.request_index.records.slot,
            lifecycle.request_index.count, planning_gate, backend,
            planning_leases)
        (
            ; direct,
            planning,
            site_index,
            request_index,
            emission,
            selection,
            direct_gate,
            planning_gate,
        )
    end
end

@inline _checkerboard_core(workspace::_CheckerboardExecutionWorkspace) =
    workspace.core
@inline _checkerboard_execution_position(workspace) =
    _checkerboard_core(workspace).execution
@inline _checkerboard_runtime_capability(
    workspace::_CheckerboardExecutionWorkspace
) = workspace.capability_report
@inline _is_checkerboard_execution_workspace(
    ::_CheckerboardExecutionWorkspace
) = true
@inline _is_checkerboard_execution_workspace(::Any) = false

"""Read-only device projection of the exact Core program/lifecycle open state."""
struct _CheckerboardOpenGate{P, L} <: AbstractVector{Bool}
    program_status::P
    lifecycle_status::L
end

"""Read-only device projection for a checkerboard with no lifecycle workspace."""
struct _CheckerboardNoLifecycleOpenGate{P} <: AbstractVector{Bool}
    program_status::P
end

Base.IndexStyle(::Type{<:_CheckerboardOpenGate}) = IndexLinear()
Base.IndexStyle(::Type{<:_CheckerboardNoLifecycleOpenGate}) = IndexLinear()
Base.size(::_CheckerboardOpenGate) = (1,)
Base.size(::_CheckerboardNoLifecycleOpenGate) = (1,)
Base.length(::_CheckerboardOpenGate) = 1
Base.length(::_CheckerboardNoLifecycleOpenGate) = 1
Base.strides(::_CheckerboardOpenGate) = (1,)
Base.strides(::_CheckerboardNoLifecycleOpenGate) = (1,)

@inline function Base.getindex(gate::_CheckerboardOpenGate, index::Int)
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.program_status[1]).code === ProgramStatusSuccess &&
           (@inbounds gate.lifecycle_status[1]).code === ProgramStatusSuccess
end

@inline function Base.getindex(
        gate::_CheckerboardNoLifecycleOpenGate, index::Int
    )
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.program_status[1]).code === ProgramStatusSuccess
end

function KernelAbstractions.get_backend(gate::_CheckerboardOpenGate)
    backend = KernelAbstractions.get_backend(gate.program_status)
    KernelAbstractions.get_backend(gate.lifecycle_status) == backend ||
        throw(ArgumentError(
            "checkerboard open-gate parents belong to different backends"
        ))
    return backend
end


KernelAbstractions.get_backend(gate::_CheckerboardNoLifecycleOpenGate) =
    KernelAbstractions.get_backend(gate.program_status)

_checkerboard_gate_storage(gate) = KernelAbstractions.allocate(
    KernelAbstractions.get_backend(gate), Bool, (1,))

function Adapt.adapt_structure(to, gate::_CheckerboardOpenGate)
    return _CheckerboardOpenGate(
        Adapt.adapt(to, gate.program_status),
        Adapt.adapt(to, gate.lifecycle_status),
    )
end

function Adapt.adapt_structure(to, gate::_CheckerboardNoLifecycleOpenGate)
    return _CheckerboardNoLifecycleOpenGate(
        Adapt.adapt(to, gate.program_status)
    )
end

function _checkerboard_open_gate(state::CheckerboardExecutionState)
    workspace = state.lifecycle_workspace
    workspace isa NoLifecycleWorkspace &&
        return _CheckerboardNoLifecycleOpenGate(state.program_status)
    workspace isa LifecycleWorkspace || throw(ArgumentError(
        "checkerboard state has an unsupported lifecycle gate"
    ))
    return _CheckerboardOpenGate(state.program_status, workspace.status)
end

struct _ProgramStateCopyEvaluator{N} end
_ProgramStateCopyEvaluator() = _ProgramStateCopyEvaluator{1}()

@generated function (::_ProgramStateCopyEvaluator{N})(
        item::Int32, reads, parameters) where {N}
    names = N == 1 ? (:value,) :
        ntuple(index -> Symbol(:value_, index), N)
    values = ntuple(N) do index
        :(LocalMath.UniqueValue(something(
            @inbounds(getfield(reads, $index)[1].value))))
    end
    return :(NamedTuple{$names}(($(values...),)))
end

function _program_state_copy_law(destinations, sources, gate_field, space)
    length(destinations) == length(sources) || throw(ArgumentError(
        "program state copy ports have inconsistent arity"))
    port_count = length(destinations)
    1 <= port_count <= 4 || throw(ArgumentError(
        "program state copy stages require one to four ports"))
    all(array -> length(array) == length(space), destinations) &&
        all(array -> length(array) == length(space), sources) ||
        throw(ArgumentError(
            "program state copy ports disagree with their shared extent"))
    source_fields = map(source -> LocalMath.Field(space, eltype(source)), sources)
    destination_fields = map(
        destination -> LocalMath.Field(space, eltype(destination)), destinations)
    identity = LocalMath.IdentityRelation(space)
    control = gate_field === nothing ? LocalMath.Control() :
        LocalMath.Control(; gate = gate_field)
    access_names = ntuple(index -> Symbol(:source_, index), port_count)
    accesses = NamedTuple{access_names}(map(source_field ->
        LocalMath.Access(source_field, identity; required = true), source_fields))
    publications = ntuple(port_count) do index
        port = port_count == 1 ? :value : Symbol(:value_, index)
        LocalMath.Publication((LocalMath.FieldPublication(
            destination_fields[index], identity,
            LocalMath.PublicationValue(port)),),
            LocalMath.Unique(eltype(destinations[index])))
    end
    stage = LocalMath.Stage(
        space,
        accesses,
        publications,
        LocalMath.Evaluator(_ProgramStateCopyEvaluator{port_count}()),
        control,
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :program_state_bank_copy),
    )
    return LocalMath.LocalLaw(stage),
        (map(Pair, source_fields, sources)...,
            map(Pair, destination_fields, destinations)...)
end

function _program_state_copy_sequence(targets, values, gate_field)
    laws = Any[]
    bindings = Pair[]
    groups = Pair{Int,Vector{Int}}[]
    for index in eachindex(targets, values)
        isempty(targets[index].linear) && continue
        extent = length(targets[index].linear)
        group = findfirst(pair -> first(pair) == extent &&
            length(last(pair)) < 4, groups)
        if group === nothing
            push!(groups, extent => Int[index])
        else
            push!(last(groups[group]), index)
        end
    end
    spaces = Dict{Int,LocalMath.Space}()
    for (extent, indices) in groups
        space = get!(spaces, extent) do
            LocalMath.Space(extent)
        end
        destinations = Tuple(targets[index].linear for index in indices)
        sources = Tuple(values[index].linear for index in indices)
        law, leaf_bindings = _program_state_copy_law(
            destinations, sources, gate_field, space)
        push!(laws, law)
        append!(bindings, leaf_bindings)
    end
    isempty(laws) && throw(ArgumentError(
        "program state requires at least one nonempty scientific copy leaf"))
    return (; laws = Tuple(laws), bindings = Tuple(bindings))
end

_program_copy_linear(array::AbstractVector) = array
_program_copy_linear(array::AbstractArray) = reshape(array, length(array))

struct _ProgramStateCopyLeaf{A, L, X, S, B, D}
    path::Symbol
    original::A
    linear::L
    axes::X
    strides::S
    backend::B
    device::D
end

function _program_array_device_identity(array)
    backend = KernelAbstractions.get_backend(array)
    device = KernelAbstractions.device(backend)
    return (backend = typeof(backend), device = device)
end

function _program_state_copy_leaf(path::Symbol, array::AbstractArray)
    return _ProgramStateCopyLeaf(
        path,
        array,
        _program_copy_linear(array),
        axes(array),
        strides(array),
        KernelAbstractions.get_backend(array),
        _program_array_device_identity(array),
    )
end

function _program_state_copy_schema(state)
    Base.@nospecialize state
    leaves = Any[
        _program_state_copy_leaf(:ownership, state.ownership),
        _program_state_copy_leaf(:cell_kinds, state.cell_kinds),
        _program_state_copy_leaf(:cell_generations, state.cell_generations),
    ]
    for (index, tracker) in enumerate(state.trackers.values)
        if tracker isa CellMomentsState
            push!(leaves,
                _program_state_copy_leaf(
                    Symbol(:tracker_, index, :_first), tracker.first
                ))
            push!(leaves,
                _program_state_copy_leaf(
                    Symbol(:tracker_, index, :_second), tracker.second
                ))
        else
            tracker isa AbstractArray || error(
                "unsupported mutable tracker state $(typeof(tracker))"
            )
            push!(leaves,
                _program_state_copy_leaf(Symbol(:tracker_, index), tracker))
        end
    end
    for (bank_index, bank) in enumerate(state.relationships.banks)
        bank isa PackedRelationshipBank || error(
            "runtime relationship storage must be packed"
        )
        for (name, array) in pairs(_packed_relationship_science(bank))
            push!(leaves,
                _program_state_copy_leaf(
                    Symbol(:relationship_, bank_index, :_, name), array
                ))
        end
    end
    for (index, bank) in enumerate(state.descriptor_state.banks)
        push!(leaves,
            _program_state_copy_leaf(Symbol(:descriptor_, index), bank.values))
    end
    return Tuple(leaves)
end

_program_state_copy_leaves(state) = map(
    leaf -> leaf.path => leaf.linear, _program_state_copy_schema(state)
)

function _validate_program_copy_array(target, source, path; values = false)
    axes(target) == axes(source) && eltype(target) === eltype(source) &&
        typeof(target) === typeof(source) && strides(target) == strides(source) &&
        KernelAbstractions.get_backend(target) ==
            KernelAbstractions.get_backend(source) &&
        _program_array_device_identity(target) ==
            _program_array_device_identity(source) || throw(ArgumentError(
        "program state banks have incompatible copy schema at $path"
    ))
    values && Adapt.adapt(Array, target) != Adapt.adapt(Array, source) && throw(ArgumentError(
        "program state banks have incompatible canonical metadata at $path"
    ))
    return nothing
end

function _validate_relationship_copy_schema(destination, source)
    Adapt.adapt(Array, destination.slots) == Adapt.adapt(Array, source.slots) ||
        throw(ArgumentError(
        "program state banks have incompatible relationship slots"
    ))
    length(destination.banks) == length(source.banks) || throw(ArgumentError(
        "program state banks have incompatible relationship bank counts"
    ))
    for bank_index in eachindex(destination.banks, source.banks)
        target = destination.banks[bank_index]
        values = source.banks[bank_index]
        target isa PackedRelationshipBank && values isa PackedRelationshipBank ||
            throw(ArgumentError("runtime relationship storage must be packed"))
        keys(_packed_relationship_science(target)) ==
            keys(_packed_relationship_science(values)) || throw(ArgumentError(
            "program state banks have incompatible relationship payload arity"
        ))
        target_schema = _packed_relationship_schema(target)
        source_schema = _packed_relationship_schema(values)
        keys(target_schema) == keys(source_schema) || throw(ArgumentError(
            "program state banks have incompatible relationship metadata"
        ))
        for name in keys(target_schema)
            _validate_program_copy_array(
                getproperty(target_schema, name),
                getproperty(source_schema, name),
                Symbol(:relationship_, bank_index, :_, name);
                values = true,
            )
        end
    end
    return nothing
end

function _require_nonalias_program_copy_schema(leaves, label)
    for left in eachindex(leaves), right in (left + 1):length(leaves)
        first = leaves[left].original
        second = leaves[right].original
        (first === second || Base.mightalias(first, second)) && throw(
            ArgumentError(
                "$label aliases copy leaves $(leaves[left].path) and " *
                "$(leaves[right].path)"
            )
        )
    end
    return nothing
end

function _validated_program_state_copy_schema(destination, source)
    Base.@nospecialize destination source
    _validate_relationship_copy_schema(
        destination.relationships, source.relationships
    )
    targets = _program_state_copy_schema(destination)
    values = _program_state_copy_schema(source)
    length(targets) == length(values) || throw(ArgumentError(
        "program state banks have incompatible scientific leaf counts"
    ))
    for index in eachindex(targets, values)
        target = targets[index]
        value = values[index]
        target.path === value.path || throw(ArgumentError(
            "program state banks have incompatible semantic copy paths"
        ))
        _validate_program_copy_array(
            target.original, value.original, target.path
        )
    end
    _require_nonalias_program_copy_schema(targets, "destination bank")
    _require_nonalias_program_copy_schema(values, "source bank")
    return targets, values
end

function _validated_program_state_copy_leaves(destination, source)
    targets, values = _validated_program_state_copy_schema(destination, source)
    return map(leaf -> leaf.path => leaf.linear, targets),
        map(leaf -> leaf.path => leaf.linear, values)
end

function _require_distinct_program_state_copy_leaves(destination, source)
    Base.@nospecialize destination source
    targets, values = _validated_program_state_copy_schema(destination, source)
    for target in targets, value in values
            (target.original === value.original ||
                Base.mightalias(target.original, value.original)) && throw(
                ArgumentError(
                    "checkerboard state banks alias scientific copy leaves " *
                    "$(target.path) and $(value.path)"
                )
            )
    end
    return nothing
end

function _program_state_copy_declaration(workspace, gate_field)
    Base.@nospecialize workspace
    destination = workspace.alternate_state
    source = workspace.state
    targets, values = _validated_program_state_copy_schema(destination, source)
    return (
        _program_state_copy_sequence(values, targets, gate_field),
        _program_state_copy_sequence(targets, values, gate_field),
    )
end

function _validate_checkerboard_identity_order(plan::CheckerboardPlan)
    for color in 1:Int(plan.color_count)
        first_index = Int(plan.color_offsets[color])
        stop_index = Int(plan.color_offsets[color + 1]) - 1
        sites = @view plan.sites[first_index:stop_index]
        issorted(sites; lt = <) && all(>(Int32(0)), sites) ||
            throw(ArgumentError(
                "LocalMath candidate requires canonical increasing color sites"
            ))
    end
    return nothing
end

function _checked_checkerboard_capacity_mul(
        left::Integer, right::Integer, quantity::Symbol
    )
    try
        return Base.Checked.checked_mul(Int(left), Int(right))
    catch error
        error isa Union{OverflowError, InexactError} || rethrow()
        throw(ArgumentError(
            "LocalMath checkerboard $quantity exceeds the bounded Int capacity"
        ))
    end
end

function _checked_checkerboard_capacity_sub(
        left::Integer, right::Integer, quantity::Symbol
    )
    try
        value = Base.Checked.checked_sub(Int(left), Int(right))
        value >= 0 || throw(ArgumentError(
            "LocalMath checkerboard $quantity cannot be negative"
        ))
        return value
    catch error
        error isa Union{OverflowError, InexactError} || rethrow()
        throw(ArgumentError(
            "LocalMath checkerboard $quantity exceeds the bounded Int capacity"
        ))
    end
end

function _validate_checkerboard_stage_program_preparation(
        workspace::CheckerboardWorkspace,
        plan::CheckerboardPlan,
        host_plan::CheckerboardPlan,
        canonical_proposal_offsets,
        plan_mismatch::String,
    )
    _validate_checkerboard_identity_order(host_plan)
    host_plan.shape == plan.shape &&
        host_plan.periodic == plan.periodic &&
        host_plan.color_count == plan.color_count &&
        host_plan.maximum_color_size == plan.maximum_color_size ||
        throw(ArgumentError(plan_mismatch))
    state = workspace.state
    size(canonical_proposal_offsets) == size(state.program.proposal_offsets) ||
        throw(ArgumentError(
            "canonical and execution proposal-offset layouts disagree"
        ))
    maximum_batch = Int(plan.maximum_color_size)
    maximum_batch > 0 || throw(ArgumentError(
        "checkerboard candidate capacity must be positive"
    ))
    maximum_semantic_id = _checked_checkerboard_capacity_mul(
        Int(state.program.attempts_per_site),
        length(state.ownership),
        :maximum_semantic_identity,
    )
    maximum_semantic_id <= typemax(Int32) || throw(ArgumentError(
        "checkerboard semantic identities exceed the positive Int32 domain"
    ))
    candidate_epoch = _checkerboard_logical_topology_epoch(
        host_plan, canonical_proposal_offsets
    )
    candidate_epoch == state.program.topology_epoch &&
        candidate_epoch == workspace.alternate_state.program.topology_epoch ||
        throw(ArgumentError(
            "canonical and executing checkerboard topology contents disagree"
        ))
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    return (; maximum_batch, candidate_epoch, backend)
end

struct _CheckerboardReportSite end
struct _CheckerboardReportBin end
struct _CheckerboardReportGate end

struct _CheckerboardReportClear end
@inline (::_CheckerboardReportClear)(item::Int32, reads, parameters) =
    (value = LocalMath.UniqueValue(UInt64(0)),)

@inline function _localmath_failure_status(
        next_mcs::Int32, stage::ProgramExecutionStage,
    )
    return ProgramStatus(
        ProgramStatusInvariant,
        next_mcs,
        stage,
        Int32(0),
        UInt64(0),
        Int32(0),
        Int32(0),
        LifecycleDetailEvaluationError,
        Int32(0),
        Int32(0),
        Int32(0),
    )
end

@kernel function _localmath_failure_bridge_kernel!(
        success, status, next_mcs::Int32, stage::ProgramExecutionStage,
    )
    item = @index(Global, Linear)
    if item == 1 &&
            (@inbounds status[1]).code === ProgramStatusSuccess &&
            !(@inbounds success[1])
        @inbounds status[1] = _localmath_failure_status(next_mcs, stage)
    end
end

function _enqueue_localmath_failure_bridge!(
        receipt::LocalMath.ExecutionReceipt, parent, status,
        next_mcs::Integer, stage::ProgramExecutionStage,
    )
    gate = LocalMath.success_gate(receipt, parent)
    backend = KernelAbstractions.get_backend(status)
    _localmath_failure_bridge_kernel!(backend)(
        gate, status, Int32(next_mcs), stage; ndrange = 1)
    return receipt
end

struct _CheckerboardReportEvaluator end
@inline function (::_CheckerboardReportEvaluator)(
        item::Int32, reads, parameters,
    )
    disposition = something(@inbounds(reads[1][1].value))
    accepted = disposition == _PROGRAM_CHECKERBOARD_ACCEPTED
    rejected = disposition == _PROGRAM_CHECKERBOARD_CONFLICT ||
        disposition == _PROGRAM_CHECKERBOARD_CONSTRAINT ||
        disposition == _PROGRAM_CHECKERBOARD_ENERGY
    null = disposition == _PROGRAM_CHECKERBOARD_NULL
    constraint = disposition == _PROGRAM_CHECKERBOARD_CONSTRAINT
    energy = disposition == _PROGRAM_CHECKERBOARD_ENERGY
    return (counts = (
        LocalMath.RoutedContribution(Int32(1), UInt64(accepted)),
        LocalMath.RoutedContribution(Int32(2), UInt64(rejected)),
        LocalMath.RoutedContribution(Int32(3), UInt64(null)),
        LocalMath.RoutedContribution(Int32(4), UInt64(constraint)),
        LocalMath.RoutedContribution(Int32(5), UInt64(energy)),
    ),)
end

struct _CheckerboardAcceptanceSite end
struct _CheckerboardAcceptanceStatus end
struct _CheckerboardAcceptanceGate end

struct _CheckerboardAcceptanceEvaluator end
@inline function (::_CheckerboardAcceptanceEvaluator)(
        item::Int32, reads, parameters,
    )
    disposition = something(@inbounds(reads[1][1].value))
    semantic = something(@inbounds(reads[2][1].value))
    next_mcs = parameters[2]
    failed = disposition == _PROGRAM_CHECKERBOARD_NONFINITE ||
        disposition == _PROGRAM_CHECKERBOARD_ZERO_T_DRIVE
    code = disposition == _PROGRAM_CHECKERBOARD_NONFINITE ?
        ProposalAcceptanceNonfinite : ProposalAcceptanceZeroTemperatureDrive
    status = _acceptance_failure_status(code, next_mcs, semantic)
    return (status = LocalMath.RoutedResolutionValue(
        Int32(1), semantic, status, failed),)
end

function _prepare_localmath_checkerboard_initialization(
        workspace, validated, gates, queue_mcs_capacity::Integer,
    )
    bins = LocalMath.Space(_CheckerboardReportBin, 5)
    gate_space = LocalMath.Space(_CheckerboardReportGate, 1)
    report = LocalMath.Field(bins, UInt64)
    external_gate = LocalMath.Field(gate_space, Bool)
    validated_gate = LocalMath.Field(gate_space, Bool)
    bin_identity = LocalMath.IdentityRelation(bins)
    gate_identity = LocalMath.IdentityRelation(gate_space)
    gate_stage = LocalMath.Stage(
        gate_space,
        (gate = LocalMath.Access(external_gate, gate_identity),),
        (LocalMath.Publication((LocalMath.FieldPublication(
            validated_gate, gate_identity,
            LocalMath.PublicationValue(:gate)),), LocalMath.Unique(Bool)),),
        LocalMath.Evaluator(_CheckerboardAcceptedGateCopy()),
        LocalMath.Control(),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_report_gate),
    )
    clear_stage = LocalMath.Stage(
        bins, NamedTuple(),
        (LocalMath.Publication((LocalMath.FieldPublication(
            report, bin_identity, LocalMath.PublicationValue(:value)),),
            LocalMath.Unique(UInt64)),),
        LocalMath.Evaluator(_CheckerboardReportClear()),
        LocalMath.Control(; gate = validated_gate),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :checkerboard_report_reset),
    )
    state_initialization = _program_state_copy_declaration(
        workspace, validated_gate)
    return map(state_initialization, gates) do initialization, gate
        clear_law = LocalMath.sequence(
            LocalMath.LocalLaw(gate_stage), initialization.laws...,
            LocalMath.LocalLaw(clear_stage))
        LocalMath.prepare(clear_law, initialization.bindings...,
            report => workspace.report,
            external_gate => gate,
            validated_gate => _checkerboard_gate_storage(gate);
            backend = validated.backend,
            lease_capacity = Int(queue_mcs_capacity),
        )
    end
end

function _prepare_core_checkerboard_mechanics(
        workspace, validated, queue_mcs_capacity, canonical_stage_plan)
    state = workspace.state
    maximum_batch = Int32(validated.maximum_batch)
    gates = (
        _checkerboard_open_gate(workspace.state),
        _checkerboard_open_gate(workspace.alternate_state),
    )
    initialization = _prepare_localmath_checkerboard_initialization(
        workspace, validated, gates, queue_mcs_capacity)
    lifecycle_reductions = _prepare_localmath_lifecycle_reductions(
        workspace, validated.backend, validated.candidate_epoch,
        queue_mcs_capacity)
    canonical_stage_plan isa StageExecutionPlan || throw(ArgumentError(
        "checkerboard preparation requires the Core-owned stage plan"))
    stage_boundaries = _prepare_checkerboard_stage_boundaries(
        workspace, canonical_stage_plan, validated.backend,
        queue_mcs_capacity)
    return (; clear_report = initialization,
        stage_boundaries, lifecycle_reductions, gates)
end

function _prepare_localmath_checkerboard_mechanics(
        workspace::CheckerboardWorkspace;
        queue_mcs_capacity::Integer = 12,
        canonical_plan = nothing,
        canonical_proposal_offsets = workspace.state.program.proposal_offsets,
        canonical_stage_plan = nothing,
    )
    state = workspace.state
    plan = state.program.checkerboard_plan
    host_plan = canonical_plan === nothing ? plan : canonical_plan
    validated = _validate_checkerboard_stage_program_preparation(
        workspace,
        plan,
        host_plan,
        canonical_proposal_offsets,
        "host and adapted checkerboard mechanical capacities disagree",
    )
    return _prepare_core_checkerboard_mechanics(
        workspace, validated, queue_mcs_capacity, canonical_stage_plan)
end

struct _CheckerboardClaimSite end
struct _CheckerboardClaimOwner end
struct _CheckerboardClaimGate end

struct _CheckerboardClaimResolver end
@inline function (::_CheckerboardClaimResolver)(item::Int32, reads, parameters)
    owners = something(@inbounds(reads[1][1].value))
    priority = something(@inbounds(reads[2][1].value))
    semantic = something(@inbounds(reads[3][1].value))
    accepted = something(@inbounds(reads[4][1].value)) ==
        _PROGRAM_CHECKERBOARD_ACCEPTED
    return (winner = (
        LocalMath.ResolutionValue(priority, semantic, semantic,
            accepted && @inbounds(owners[1]) > 0),
        LocalMath.ResolutionValue(priority, semantic, semantic,
            accepted && @inbounds(owners[2]) > 0),
    ),)
end

struct _CheckerboardClaimConjunction end
@inline function (::_CheckerboardClaimConjunction)(
        item::Int32, reads, parameters,
    )
    owners = something(@inbounds(reads[1][1].value))
    winners = @inbounds reads[2]
    semantic = something(@inbounds(reads[3][1].value))
    disposition = something(@inbounds(reads[4][1].value))
    accepted = disposition == _PROGRAM_CHECKERBOARD_ACCEPTED
    first = @inbounds winners[1]
    second = @inbounds winners[2]
    selected = accepted &&
        (@inbounds(owners[1]) <= 0 ||
            (first.present && first.value == semantic)) &&
        (@inbounds(owners[2]) <= 0 ||
            (second.present && second.value == semantic))
    result = selected ? disposition :
        (disposition == _PROGRAM_CHECKERBOARD_ACCEPTED ?
            _PROGRAM_CHECKERBOARD_CONFLICT : disposition)
    return (disposition = LocalMath.UniqueValue(result),)
end

@inline function _checkerboard_state_with_science(
        state,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        lifecycle_workspace,
    )
    program_status = lifecycle_workspace isa LifecycleWorkspace ?
                     lifecycle_workspace.status : state.program_status
    return CheckerboardExecutionState(
        state.program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        lifecycle_workspace,
        state.lifecycle_control,
        program_status,
        state.parameters,
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
end

function _checkerboard_state_banks(state::CheckerboardExecutionState)
    workspace = state.lifecycle_workspace
    if workspace isa NoLifecycleWorkspace
        alternate = _checkerboard_state_with_science(
            state,
            copy(state.ownership),
            copy(state.cell_kinds),
            copy(state.cell_generations),
            copy_tracker_state(state.trackers),
            copy(state.relationships),
            copy_auxiliary_state(state.descriptor_state),
            NoLifecycleWorkspace(),
        )
        return state, alternate
    end
    primary_workspace = _lifecycle_workspace_with_staged_state(
        workspace, state
    )
    primary = _checkerboard_state_with_science(
        state,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        primary_workspace,
    )
    secondary_science = (
        ownership = workspace.staged_ownership,
        cell_kinds = workspace.staged_cell_kinds,
        cell_generations = workspace.staged_cell_generations,
        trackers = workspace.staged_trackers,
        relationships = workspace.staged_relationships,
        descriptor_state = workspace.staged_descriptor_state,
    )
    secondary_workspace = _lifecycle_workspace_with_staged_state(
        workspace, secondary_science
    )
    secondary = _checkerboard_state_with_science(
        state,
        secondary_science.ownership,
        secondary_science.cell_kinds,
        secondary_science.cell_generations,
        secondary_science.trackers,
        secondary_science.relationships,
        secondary_science.descriptor_state,
        secondary_workspace,
    )
    return primary, secondary
end

function _require_checkerboard_lifecycle_staging_aliases(state)
    workspace = state.lifecycle_workspace
    workspace isa NoLifecycleWorkspace && return state
    pairs = (
        (:ownership, workspace.staged_ownership, state.ownership),
        (:cell_kinds, workspace.staged_cell_kinds, state.cell_kinds),
        (
            :cell_generations,
            workspace.staged_cell_generations,
            state.cell_generations,
        ),
        (:trackers, workspace.staged_trackers, state.trackers),
        (
            :relationships,
            workspace.staged_relationships,
            state.relationships,
        ),
        (
            :descriptor_state,
            workspace.staged_descriptor_state,
            state.descriptor_state,
        ),
    )
    for (name, staged, science) in pairs
        staged === science || throw(ArgumentError(
            "checkerboard lifecycle staged $(name) must alias its bank science"
        ))
    end
    return state
end

function _require_checkerboard_distinct_state_banks(primary, alternate)
    return _require_distinct_program_state_copy_leaves(primary, alternate)
end

_checkerboard_compiled_extinction_policies(
    program::CheckerboardKernelProgram) =
    program.extinction_policies

_checkerboard_compiled_extinction_policies(program) =
    _checkerboard_extinction_policies(
        program.lifecycle_plan, Int(program.kind_count))

_checkerboard_compiled_relationship_layout(
    program::CheckerboardKernelProgram) = program.relationship_layout

function _checkerboard_compiled_relationship_layout(program)
    storage = program.relationships
    banks = map(storage.banks) do schemas
        counts = Tuple(Int32(schema.capacity) for schema in schemas)
        offsets = Vector{Int32}(undef, length(counts))
        next_offset = Int32(1)
        for index in eachindex(counts)
            offsets[index] = next_offset
            next_offset += counts[index]
        end
        payload_count = isempty(schemas) ? Int32(0) :
            Int32(length(first(schemas).payload_defaults))
        all(schema -> length(schema.payload_defaults) == payload_count,
            schemas) || throw(ArgumentError(
            "packed relationship bank payload schemas disagree"))
        _CheckerboardRelationshipBankLayout(
            Tuple(offsets), counts, payload_count)
    end
    return _CheckerboardRelationshipLayout(Tuple(storage.slots), banks)
end

function _checkerboard_kernel_program(program, to)
    ownership_change_handles = program.ownership_change_handles
    tracker_kernel = to === nothing ?
                     tracker_kernel_plan(program.tracker_plan) :
                     adapt_tracker_kernel_plan(to, program.tracker_plan)
    topology_epoch = _checkerboard_logical_topology_epoch(
        program.checkerboard_plan, program.proposal_offsets
    )
    extinction_policies = _checkerboard_compiled_extinction_policies(program)
    relationship_layout = _checkerboard_compiled_relationship_layout(program)
    return CheckerboardKernelProgram(
        program.shape,
        program.periodic,
        to === nothing ? program.proposal_offsets :
        Adapt.adapt(to, program.proposal_offsets),
        program.medium_kind,
        program.temperature,
        program.attempts_per_site,
        to === nothing ? program.relationships :
        Adapt.adapt(to, program.relationships),
        tracker_kernel,
        _checkerboard_adapt(to, _checkerboard_domain_resources(program)),
        to === nothing ? program.lifecycle_plan :
        Adapt.adapt(to, program.lifecycle_plan),
        to === nothing ? ownership_change_handles :
        Adapt.adapt(to, ownership_change_handles),
        to === nothing ? program.checkerboard_plan :
        Adapt.adapt(to, program.checkerboard_plan),
        extinction_policies,
        relationship_layout,
        topology_epoch,
    )
end

_checkerboard_domain_resources(program::CheckerboardKernelProgram) =
    program.domain_resources
_checkerboard_domain_resources(program) =
    program.descriptor_plan.domain_resources

_checkerboard_adapt(to, value) =
    to === nothing ? value : Adapt.adapt(to, value)

function _checkerboard_execution_state(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        parameters,
        seed,
        replica,
        repeat,
        initial_mcs = 0,
        to = nothing,
    )
    kernel_program = _checkerboard_kernel_program(program, to)
    lifecycle_workspace = allocate_lifecycle_workspace(
        program.lifecycle_plan,
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    lifecycle_control = allocate_lifecycle_backend_control(
        program.lifecycle_plan, parameters, length(ownership)
    )
    @inbounds begin
        lifecycle_control.counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] =
            iseven(initial_mcs) ? Int32(1) : Int32(2)
        lifecycle_control.counters[_LIFECYCLE_CONTROL_COMMITTED_MCS] =
            Int32(initial_mcs)
    end
    program_status = if lifecycle_workspace isa LifecycleWorkspace
        lifecycle_workspace.status
    else
        StructArrays.StructArray(ProgramStatus[ProgramStatus()])
    end
    return CheckerboardExecutionState(
        kernel_program,
        _checkerboard_adapt(to, ownership),
        _checkerboard_adapt(to, cell_kinds),
        _checkerboard_adapt(to, cell_generations),
        _checkerboard_adapt(to, trackers),
        _checkerboard_adapt(to, relationships),
        _checkerboard_adapt(to, descriptor_state),
        _checkerboard_adapt(to, lifecycle_workspace),
        _checkerboard_adapt(to, lifecycle_control),
        _checkerboard_adapt(to, program_status),
        _checkerboard_adapt(to, parameters),
        UInt64(seed),
        UInt32(replica),
        UInt32(repeat),
        Int(initial_mcs),
    )
end

function _checkerboard_state_at_mcs(state::CheckerboardExecutionState, mcs)
    return CheckerboardExecutionState(
        state.program,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        state.lifecycle_workspace,
        state.lifecycle_control,
        state.program_status,
        state.parameters,
        state.seed,
        state.replica,
        state.repeat,
        Int(mcs),
    )
end

function _checkerboard_similar(prototype, ::Type{T}, dimensions...) where {T}
    values = similar(prototype, T, dimensions...)
    return values
end

function _checkerboard_color_sizes(plan::CheckerboardPlan)
    return Int32[
        plan.color_offsets[color + 1] - plan.color_offsets[color]
        for color in 1:Int(plan.color_count)
    ]
end

const _CHECKERBOARD_COLOR_ORDER_OPERATION = UInt16(5)

"""Fill one preallocated unbiased semantic-RNG permutation of realized colors."""
function _checkerboard_color_order!(
        order::Vector{Int32}, state, attempt_round::Integer
    )
    color_count = Int(state.program.checkerboard_plan.color_count)
    length(order) == color_count || throw(ArgumentError(
        "checkerboard color-order workspace has the wrong size"
    ))
    0 <= state.mcs < typemax(Int) || throw(ArgumentError(
        "checkerboard MCS is outside the semantic RNG domain"
    ))
    1 <= attempt_round <= typemax(UInt8) || throw(ArgumentError(
        "checkerboard attempt round is outside the semantic RNG domain"
    ))
    for color in 1:color_count
        @inbounds order[color] = Int32(color)
    end
    seed = _trajectory_seed(state.seed, state.replica, state.repeat)
    for position in color_count:-1:2
        address = RNGAddress(
            stream = CheckerboardColorOrderStream,
            mcs = state.mcs + 1,
            subround = attempt_round,
            operation = _CHECKERBOARD_COLOR_ORDER_OPERATION,
            entity_kind = GlobalEntity,
            entity = position,
        )
        selected = Int(bounded_uint(
            Philox4x32x10V2(), seed, address, UInt32(position)
        )) + 1
        @inbounds order[position], order[selected] =
            order[selected], order[position]
    end
    return order
end

function _allocate_checkerboard_workspace(
        state::CheckerboardExecutionState;
        capability_report,
        color_sizes = _checkerboard_color_sizes(
            state.program.checkerboard_plan
        ),
        color_order = collect(
            Int32, 1:Int(state.program.checkerboard_plan.color_count)
        ),
        source_table = (),
        alternate_state = nothing,
        execution = ProgramExecutionPosition(state.mcs),
    )
    if alternate_state === nothing
        state, alternate_state = _checkerboard_state_banks(state)
    end
    _require_checkerboard_lifecycle_staging_aliases(state)
    _require_checkerboard_lifecycle_staging_aliases(alternate_state)
    _require_checkerboard_distinct_state_banks(state, alternate_state)
    plan = state.program.checkerboard_plan
    plan isa CheckerboardPlan || error(
        "checkerboard workspace requires a realized-domain plan"
    )
    maximum_batch = Int(plan.maximum_color_size)
    maximum_batch > 0 || error("checkerboard schedule has no candidates")
    target_sites = _checkerboard_similar(
        state.parameters, Int32, maximum_batch
    )
    source_sites = similar(target_sites)
    old_owners = similar(target_sites)
    new_owners = similar(target_sites)
    priorities = _checkerboard_similar(
        state.parameters, UInt32, maximum_batch
    )
    semantic_ids = _checkerboard_similar(
        state.parameters, Int32, maximum_batch
    )
    dispositions = _checkerboard_similar(
        state.parameters, UInt8, maximum_batch
    )
    report = _checkerboard_similar(state.parameters, UInt64, 5)
    return CheckerboardWorkspace(
        state,
        alternate_state,
        target_sites,
        source_sites,
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        report,
        capability_report,
        color_sizes,
        color_order,
        source_table,
        execution,
    )
end

function allocate_program_engine_workspace(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        stage_buffers,
        parameters,
        seed,
        replica,
        repeat,
        initial_mcs = 0,
    )
    program.engine isa SequentialProgramEngine && return (
        allocate_sequential_transaction_workspace(
            program,
            ownership,
            cell_kinds,
            cell_generations,
            trackers,
            relationships,
            descriptor_state,
        )
    )
    program.engine isa CheckerboardProgramEngine || error(
        "unreachable program engine"
    )
    state = _checkerboard_execution_state(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        parameters,
        seed,
        replica,
        repeat,
        initial_mcs,
    )
    return _allocate_checkerboard_workspace(
        state;
        capability_report = program_capability_report(program),
        source_table = program.descriptor_plan.source_table,
    )
end

function initialize_program_execution_statistics!(
        workspace::CheckerboardWorkspace,
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
    )
    control = workspace.state.lifecycle_control
    values = (
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
    )
    for (index, value) in enumerate(values)
        value >= 0 || throw(ArgumentError(
            "program execution statistics must be nonnegative"
        ))
        @inbounds control.statistics[index] = UInt64(value)
    end
    return workspace
end

function _validate_gpu_descriptor_plan(
        plan::DescriptorExecutionPlan, source_table
    )
    for group in plan.groups
        for descriptor in group.launch.instances
            support = descriptor_support(descriptor)
            support isa DescriptorSupport || throw(ArgumentError(
                "descriptor support must be a DescriptorSupport value"
            ))
            source_handle = Int(descriptor_source_handle(descriptor))
            qualified_source = 1 <= source_handle <= length(source_table) ?
                repr(source_table[source_handle]) :
                "<missing qualified source for handle $source_handle>"
            support.gpu || throw(ArgumentError(
                "descriptor source $qualified_source " *
                "does not declare GPU support (reason code " *
                "$(support.reason_code))"
            ))
        end
    end
    return nothing
end


"""Adapt every checkerboard runtime bank to one storage constructor."""
function adapt_checkerboard_workspace(to, workspace::CheckerboardWorkspace)
    state = workspace.state
    primary_science = (
        ownership = Adapt.adapt(to, state.ownership),
        cell_kinds = Adapt.adapt(to, state.cell_kinds),
        cell_generations = Adapt.adapt(to, state.cell_generations),
        trackers = Adapt.adapt(to, state.trackers),
        relationships = Adapt.adapt(to, state.relationships),
        descriptor_state = Adapt.adapt(to, state.descriptor_state),
    )
    execution = ProgramExecutionPosition(
        workspace.execution.submitted_mcs,
        workspace.execution.drained_mcs,
        workspace.execution.committed_mcs,
        workspace.execution.materialized_mcs,
        workspace.execution.settlement_count,
        workspace.execution.synchronization_count,
        workspace.execution.control_transfer_count,
        workspace.execution.snapshot_transfer_count,
        workspace.execution.lifecycle_transfer_count,
    )
    capability_report = _adapted_program_capability_report(
        workspace.capability_report, to
    )
    if state.lifecycle_workspace isa NoLifecycleWorkspace
        alternate_source = workspace.alternate_state
        program_status = Adapt.adapt(to, state.program_status)
        adapted = CheckerboardExecutionState(
            _checkerboard_kernel_program(state.program, to),
            primary_science.ownership,
            primary_science.cell_kinds,
            primary_science.cell_generations,
            primary_science.trackers,
            primary_science.relationships,
            primary_science.descriptor_state,
            NoLifecycleWorkspace(),
            Adapt.adapt(to, state.lifecycle_control),
            program_status,
            Adapt.adapt(to, state.parameters),
            state.seed,
            state.replica,
            state.repeat,
            state.mcs,
        )
        alternate = _checkerboard_state_with_science(
            adapted,
            Adapt.adapt(to, alternate_source.ownership),
            Adapt.adapt(to, alternate_source.cell_kinds),
            Adapt.adapt(to, alternate_source.cell_generations),
            Adapt.adapt(to, alternate_source.trackers),
            Adapt.adapt(to, alternate_source.relationships),
            Adapt.adapt(to, alternate_source.descriptor_state),
            NoLifecycleWorkspace(),
        )
        return _allocate_checkerboard_workspace(
            adapted;
            capability_report,
            color_sizes = workspace.color_sizes,
            color_order = copy(workspace.color_order),
            source_table = workspace.source_table,
            alternate_state = alternate,
            execution,
        )
    end
    shared_workspace = Adapt.adapt(
        to,
        _lifecycle_workspace_with_staged_state(
            state.lifecycle_workspace, workspace.alternate_state
        ),
    )
    secondary_science = (
        ownership = shared_workspace.staged_ownership,
        cell_kinds = shared_workspace.staged_cell_kinds,
        cell_generations = shared_workspace.staged_cell_generations,
        trackers = shared_workspace.staged_trackers,
        relationships = shared_workspace.staged_relationships,
        descriptor_state = shared_workspace.staged_descriptor_state,
    )
    primary_workspace = _lifecycle_workspace_with_staged_state(
        shared_workspace, primary_science
    )
    secondary_workspace = _lifecycle_workspace_with_staged_state(
        shared_workspace, secondary_science
    )
    adapted = CheckerboardExecutionState(
        _checkerboard_kernel_program(state.program, to),
        primary_science.ownership,
        primary_science.cell_kinds,
        primary_science.cell_generations,
        primary_science.trackers,
        primary_science.relationships,
        primary_science.descriptor_state,
        primary_workspace,
        Adapt.adapt(to, state.lifecycle_control),
        primary_workspace.status,
        Adapt.adapt(to, state.parameters),
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
    alternate = _checkerboard_state_with_science(
        adapted,
        secondary_science.ownership,
        secondary_science.cell_kinds,
        secondary_science.cell_generations,
        secondary_science.trackers,
        secondary_science.relationships,
        secondary_science.descriptor_state,
        secondary_workspace,
    )
    return _allocate_checkerboard_workspace(
        adapted;
        capability_report,
        color_sizes = workspace.color_sizes,
        color_order = copy(workspace.color_order),
        source_table = workspace.source_table,
        alternate_state = alternate,
        execution,
    )
end

@inline function _program_backend_open(state)
    return (@inbounds state.program_status[1]).code === ProgramStatusSuccess &&
           _lifecycle_backend_open(state.lifecycle_workspace)
end

function _clear_checkerboard_bulk!(
        execution::_CheckerboardExecutionWorkspace, state
    )
    bank = _checkerboard_authorized_bank(execution, state)
    receipt = LocalMath.execute!(execution.clear_report[bank])
    _enqueue_localmath_failure_bridge!(
        receipt, execution.gates[bank], state.program_status,
        state.mcs + 1, ProgramStagePublication)
    _record_checkerboard_receipt!(execution.receipts.mechanics, bank, receipt)
    return receipt
end

_checkerboard_lifecycle_status_identity(::NoLifecycleWorkspace) = nothing
_checkerboard_lifecycle_status_identity(workspace::LifecycleWorkspace) =
    workspace.status

function _checkerboard_authorized_bank(execution, state)
    workspace = execution.core
    for (index, bank) in pairs((workspace.state, workspace.alternate_state))
        state.ownership === bank.ownership &&
            state.parameters === bank.parameters &&
            state.program === bank.program &&
            state.program_status === bank.program_status &&
            _checkerboard_lifecycle_status_identity(state.lifecycle_workspace) ===
                _checkerboard_lifecycle_status_identity(bank.lifecycle_workspace) &&
            return index
    end
    throw(ArgumentError(
        "checkerboard state does not belong to an authorized execution bank"
    ))
end

function _execute_compiled_checkerboard_color!(
        execution::_CheckerboardExecutionWorkspace,
        state,
        color,
        attempt_round,
        batch_size,
    )
    bank = _checkerboard_authorized_bank(execution, state)
    preparation = execution.color_laws.prepared[bank]
    mechanics = execution.receipts.mechanics[bank]
    tail = isempty(mechanics) ? nothing : last(mechanics)
    tail === nothing && throw(ArgumentError(
        "checkerboard color execution requires the initialized mechanics tail"
    ))
    dependencies = (tail,)
    try
        receipt = LocalMath.execute!(preparation;
            parameters = (
                mcs = Int64(state.mcs + 1),
                color = Int32(color),
                attempt_round = Int32(attempt_round),
                batch_size = Int32(batch_size),
            ),
            dependencies,
        )
        _enqueue_localmath_failure_bridge!(
            receipt, execution.gates[bank], state.program_status,
            state.mcs + 1, ProgramStageSelection)
        _record_checkerboard_receipt!(
            execution.receipts.mechanics, bank, receipt)
        return receipt
    catch error
        error isa LifecycleBackendFailure && rethrow()
        throw(LifecycleBackendFailure(error, state.mcs + 1, state.mcs + 1))
    end
end

function _execute_compiled_stage_boundary!(
        execution::_CheckerboardExecutionWorkspace,
        entries::Tuple,
        state,
    )
    isempty(entries) && return nothing
    bank = _checkerboard_authorized_bank(execution, state)
    receipts = execution.receipts.mechanics[bank]
    tail = isempty(receipts) ? nothing : last(receipts)
    tail === nothing && throw(ArgumentError(
        "checkerboard stage boundary requires an initialized mechanics tail"))
    for entry in entries
        preparation = entry.prepared[bank]
        for _ in 1:entry.repetitions
            try
                receipt = LocalMath.execute!(preparation;
                    parameters = (mcs = Int64(state.mcs + 1),),
                    dependencies = (tail,),
                )
                _enqueue_localmath_failure_bridge!(
                    receipt, execution.gates[bank], state.program_status,
                    state.mcs + 1, ProgramStageState)
                _record_checkerboard_receipt!(
                    execution.receipts.mechanics, bank, receipt)
                tail = receipt
            catch error
                error isa LifecycleBackendFailure && rethrow()
                throw(LifecycleBackendFailure(
                    error, state.mcs + 1, state.mcs + 1))
            end
        end
    end
    return tail
end

function _preflight_checkerboard_execution_configuration(
        workspace::CheckerboardWorkspace,
        mcs::Integer,
        state_bank::CheckerboardExecutionState,
        ;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    authorized_bank = any((workspace.state, workspace.alternate_state)) do bank
        state_bank.ownership === bank.ownership &&
            state_bank.parameters === bank.parameters &&
            state_bank.program === bank.program
    end
    authorized_bank || throw(ArgumentError(
        "checkerboard execution state is not owned by the authorized workspace"
    ))
    state = _checkerboard_state_at_mcs(state_bank, mcs)
    plan = state.program.checkerboard_plan
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    workgroup_size === nothing || workgroup_size > 0 || throw(ArgumentError(
        "checkerboard workgroup size must be positive"
    ))
    return (; state, plan, backend)
end

function _execute_checkerboard_mcs!(
        execution::_CheckerboardExecutionWorkspace,
        mcs::Integer,
        state_bank::CheckerboardExecutionState,
        ;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    workspace = execution.core
    configuration = _preflight_checkerboard_execution_configuration(
        workspace, mcs, state_bank; workgroup_size
    )
    state = configuration.state
    plan = configuration.plan
    backend = configuration.backend
    _clear_checkerboard_bulk!(execution, state)
    # The accepted CheckerboardSweep process uses one normalized sweep. Its
    # realized colors execute in an unbiased semantic-RNG permutation. The
    # preallocated host order is safe for queued CPU/GPU launches because
    # each kernel receives its color as a copied scalar argument.
    for attempt_round in 1:Int(state.program.attempts_per_site)
        color_order = _checkerboard_color_order!(
            workspace.color_order, state, attempt_round
        )
        for color_position in 1:Int(plan.color_count)
            color = Int(@inbounds color_order[color_position])
            color_size = Int(@inbounds workspace.color_sizes[color])
            batch_size = color_size
            bank = _checkerboard_authorized_bank(execution, state)
            # Geometry, bounded scientific evaluation, acceptance, owner
            # resolution, mutual-maxima conjunction, tracker/ownership
            # publication, relationships, and reporting are one ordered
            # LocalMath law and one logical receipt.
            _execute_compiled_checkerboard_color!(
                execution, state, color, attempt_round, batch_size)
        end
    end
    return workspace
end

"""Execute and settle one complete checkerboard MCS."""
function execute_checkerboard_mcs!(
        execution::_CheckerboardExecutionWorkspace,
        mcs::Integer = execution.core.state.mcs,
        state_bank::CheckerboardExecutionState = execution.core.state;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    _require_program_execution_capability(
        execution.capability_report;
        operation = :backend_execute_checkerboard_mcs,
    )
    _execute_checkerboard_mcs!(
        execution,
        mcs,
        state_bank;
        workgroup_size,
    )
    return execution
end


@inline function _checkerboard_transaction_banks(
        workspace::CheckerboardWorkspace, current_mcs::Integer
    )
    if iseven(current_mcs)
        return workspace.state, workspace.alternate_state, Int32(2)
    end
    return workspace.alternate_state, workspace.state, Int32(1)
end

"""
Validate one complete checkerboard submission without appending backend work.

ProgramRuntime uses this boundary before marking itself unsettled. Once that
mark is visible, any later rejection may have an ordered CorePotts prefix to
drain and must not make checkpointing or adaptation appear safe.
"""
function _preflight_checkerboard_mcs!(
        execution,
        current_mcs::Integer,
        ;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    workspace = _checkerboard_core(execution)
    capability = _checkerboard_runtime_capability(execution)
    _require_program_execution_capability(
        capability;
        operation = :backend_enqueue_checkerboard_mcs,
    )
    current_mcs >= 0 || throw(ArgumentError(
        "current MCS must be nonnegative"
    ))
    current_mcs == workspace.execution.submitted_mcs || throw(ArgumentError(
        "checkerboard submission must be contiguous: expected current MCS " *
        "$(workspace.execution.submitted_mcs), received $current_mcs"
    ))
    policy = execution.identity.queue_policy
    outstanding_mcs = _checked_checkerboard_capacity_sub(
        Int(current_mcs),
        workspace.execution.drained_mcs,
        :outstanding_checkerboard_mcs,
    )
    outstanding_mcs < policy.mcs_capacity || throw(ArgumentError(
        "checkerboard queue capacity cannot encode one complete MCS"
    ))
    _, destination, _ = _checkerboard_transaction_banks(
        workspace, current_mcs
    )
    destination = _checkerboard_state_at_mcs(destination, current_mcs)
    _preflight_checkerboard_execution_configuration(
        workspace, current_mcs, destination; workgroup_size
    )
    destination_bank_index = _checkerboard_authorized_bank(
        execution, destination
    )
    preparations = ((
        :clear_report,
        execution.clear_report[destination_bank_index],
        policy.clear_report_submissions_per_mcs,
    ), (
        :color_mechanics,
        execution.color_laws.prepared[destination_bank_index],
        policy.color_submissions_per_mcs,
    ))
    for (boundary, entries, required) in (
            (:before_lifecycle, execution.stage_boundaries.before,
                policy.before_lifecycle_submissions_per_mcs),
            (:after_lifecycle, execution.stage_boundaries.after,
                policy.after_lifecycle_submissions_per_mcs),
        )
        sum(entry.repetitions for entry in entries; init = 0) == required ||
            throw(ArgumentError(
                "checkerboard $boundary submission policy is inconsistent"))
        for entry in entries
            preparations = (preparations..., (
                boundary, entry.prepared[destination_bank_index],
                entry.repetitions))
        end
    end
    if execution.lifecycle_reductions !== nothing
        reductions = execution.lifecycle_reductions[destination_bank_index]
        preparations = (
            preparations...,
            (
                :lifecycle_status,
                reductions.direct,
                policy.lifecycle_status_submissions_per_mcs,
            ),
            (
                :lifecycle_planning_status,
                reductions.planning,
                policy.lifecycle_planning_status_submissions_per_mcs,
            ),
            (
                :lifecycle_site_index,
                reductions.site_index,
                policy.lifecycle_site_index_submissions_per_mcs,
            ),
            (
                :lifecycle_request_index,
                reductions.request_index,
                policy.lifecycle_request_index_submissions_per_mcs,
            ),
            (
                :lifecycle_emission,
                reductions.emission,
                policy.lifecycle_emission_submissions_per_mcs,
            ),
            (
                :lifecycle_selection,
                reductions.selection,
                policy.lifecycle_selection_submissions_per_mcs,
            ),
        )
    end
    for (name, prepared, required) in preparations
        capacity = LocalMath.submission_capacity(prepared)
        capacity.available >= required || throw(ArgumentError(
            "LocalMath $name preparation cannot encode one complete MCS"
        ))
    end
    return nothing
end

function _enqueue_checkerboard_mcs_after_preflight!(
        execution,
        current_mcs::Integer;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    workspace = _checkerboard_core(execution)
    source, destination, destination_bank = _checkerboard_transaction_banks(
        workspace, current_mcs
    )
    destination = _checkerboard_state_at_mcs(destination, current_mcs)
    execute_checkerboard_mcs!(execution, current_mcs, destination; workgroup_size)
    bank = _checkerboard_authorized_bank(execution, destination)
    _execute_compiled_stage_boundary!(
        execution, execution.stage_boundaries.before, destination)
    lifecycle_receipts = enqueue_lifecycle_backend_index!(
        destination,
        execution.lifecycle_reductions === nothing ? nothing :
            execution.lifecycle_reductions[bank];
        workgroup_size,
    )
    lifecycle_receipts === nothing || begin
        current = execution.receipts.lifecycle
        _record_checkerboard_receipt!(
            current.direct, bank, lifecycle_receipts.direct)
        _record_checkerboard_receipt!(
            current.planning, bank, lifecycle_receipts.planning)
        _record_checkerboard_receipt!(
            current.site_index, bank, lifecycle_receipts.site_index)
        _record_checkerboard_receipt!(
            current.request_index, bank, lifecycle_receipts.request_index)
        _record_checkerboard_receipt!(
            current.emission, bank, lifecycle_receipts.emission)
        _record_checkerboard_receipt!(
            current.selection, bank, lifecycle_receipts.selection)
    end
    _execute_compiled_stage_boundary!(
        execution, execution.stage_boundaries.after, destination)
    _enqueue_program_bank_publication!(
        destination, workspace.report, destination_bank, current_mcs + 1
    )
    workspace.execution.submitted_mcs = Int(current_mcs) + 1
    return destination
end

function _enqueue_checkerboard_mcs!(
        execution,
        current_mcs::Integer;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    _preflight_checkerboard_mcs!(execution, current_mcs; workgroup_size)
    return _enqueue_checkerboard_mcs_after_preflight!(
        execution, current_mcs; workgroup_size
    )
end

"""Enqueue one checkerboard MCS while leaving host mirrors unpublished."""
function enqueue_checkerboard_mcs!(
        execution::_CheckerboardExecutionWorkspace,
        current_mcs::Integer;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    return _enqueue_checkerboard_mcs!(
        execution, current_mcs; workgroup_size
    )
end
