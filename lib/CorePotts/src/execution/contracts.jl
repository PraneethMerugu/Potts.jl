@enum BackendFamily::UInt8 begin
    CPUFamily = 1
    CUDAFamily = 2
    AMDGPUFamily = 3
    MetalFamily = 4
end

@enum BackendContractStatus::UInt8 begin
    QualifiedBackend = 1
    DeferredBackend = 2
end

"""Host-side declaration of capabilities which have been implemented and qualified."""
struct BackendCapabilities{F, R <: Tuple}
    family::F
    contract_status::BackendContractStatus
    functional::Bool
    ordered_launches::Bool
    device_float64::Bool
    subgroup_intrinsics::Bool
    qualified_rng_contracts::R
end

abstract type AbstractBackendCapability end
struct QualifiedBackendCapability <: AbstractBackendCapability end
struct FunctionalBackendCapability <: AbstractBackendCapability end
struct OrderedLaunchCapability <: AbstractBackendCapability end
struct DeviceFloat64Capability <: AbstractBackendCapability end
struct SubgroupIntrinsicCapability <: AbstractBackendCapability end
struct SemanticRNGCapability <: AbstractBackendCapability
    version::VersionNumber
end

struct UnsupportedBackendCapability{F, C} <: Exception
    family::F
    capability::C
end

struct UnsupportedBackendType <: Exception
    backend_type::DataType
end

Base.showerror(io::IO, error::UnsupportedBackendType) =
    print(io, "CorePotts has no capability contract for backend ", error.backend_type)

function Base.showerror(io::IO, error::UnsupportedBackendCapability)
    print(io, "backend ", error.family, " does not provide the required qualified capability `",
        error.capability, "`")
end

"""Return only capabilities CorePotts is prepared to claim for this backend."""
function backend_capabilities(backend::KernelAbstractions.Backend)
    throw(UnsupportedBackendType(typeof(backend)))
end

backend_capabilities(::KernelAbstractions.CPU) = BackendCapabilities(
    CPUFamily, QualifiedBackend, true, true, true, false, (v"1.0.0",))

supports(capabilities::BackendCapabilities, ::QualifiedBackendCapability) =
    capabilities.contract_status === QualifiedBackend
supports(capabilities::BackendCapabilities, ::FunctionalBackendCapability) =
    capabilities.functional
supports(capabilities::BackendCapabilities, ::OrderedLaunchCapability) =
    capabilities.ordered_launches
supports(capabilities::BackendCapabilities, ::DeviceFloat64Capability) =
    capabilities.device_float64
supports(capabilities::BackendCapabilities, ::SubgroupIntrinsicCapability) =
    capabilities.subgroup_intrinsics
supports(capabilities::BackendCapabilities, capability::SemanticRNGCapability) =
    capability.version in capabilities.qualified_rng_contracts

function require_capability(capabilities::BackendCapabilities,
        capability::AbstractBackendCapability)
    supported = supports(capabilities, capability)
    supported || throw(UnsupportedBackendCapability(capabilities.family, capability))
    return capabilities
end

# Frozen legacy callers use symbols. New execution code and backend extensions use typed values.
_typed_capability(::Val{:qualified_backend}) = QualifiedBackendCapability()
_typed_capability(::Val{:functional}) = FunctionalBackendCapability()
_typed_capability(::Val{:ordered_launches}) = OrderedLaunchCapability()
_typed_capability(::Val{:device_float64}) = DeviceFloat64Capability()
_typed_capability(::Val{:subgroup_intrinsics}) = SubgroupIntrinsicCapability()
_typed_capability(::Val{:semantic_rng_v1}) = SemanticRNGCapability(v"1.0.0")
function require_capability(capabilities::BackendCapabilities, capability::Symbol)
    typed = try
        _typed_capability(Val(capability))
    catch
        throw(UnsupportedBackendCapability(capabilities.family, capability))
    end
    return require_capability(capabilities, typed)
end

"""Host-only information required to reconstruct and validate compiled state."""
struct CompiledStateDescriptor{N, S <: PropertySchema, M <: Tuple}
    lattice_dims::NTuple{N, Int}
    capacity::CellCapacity
    property_schema::S
    medium_ids::M
end

"""Device-valid structure-of-arrays storage. This is the only adaptable state boundary."""
struct CompiledStateStorage{O, A, G, C, R, RC, P}
    ownership::O
    active::A
    generations::G
    cell_types::C
    reusable_slots::R
    reusable_count::RC
    properties::P
end

function Adapt.adapt_structure(to, storage::CompiledStateStorage)
    return CompiledStateStorage(
        Adapt.adapt(to, storage.ownership),
        Adapt.adapt(to, storage.active),
        Adapt.adapt(to, storage.generations),
        Adapt.adapt(to, storage.cell_types),
        Adapt.adapt(to, storage.reusable_slots),
        Adapt.adapt(to, storage.reusable_count),
        Adapt.adapt(to, storage.properties),
    )
end

"""Host descriptor paired with compiled storage; kernels receive `execution_storage(state)`."""
struct CompiledPottsState{D <: CompiledStateDescriptor, S <: CompiledStateStorage}
    descriptor::D
    storage::S
end

execution_storage(state::CompiledPottsState) = state.storage
lattice_storage(state::CompiledPottsState) = state.storage.ownership.ids

function compile_state(state::LogicalPottsState)
    assert_valid_state(state)
    slot_count = nslots(capacity(state))
    reusable = zeros(UInt32, slot_count)
    for (index, slot) in enumerate(state._reusable)
        reusable[index] = value(slot)
    end
    storage = CompiledStateStorage(
        compile_ownership(state),
        UInt8.(state._active),
        value.(state._generations),
        copy(state._cell_types),
        reusable,
        UInt32[length(state._reusable)],
        map(copy, state.properties.columns),
    )
    descriptor = CompiledStateDescriptor(
        lattice_size(state), capacity(state), state.properties.schema,
        Tuple(value.(state._medium_ids)),
    )
    return CompiledPottsState(descriptor, storage)
end

"""Move compiled arrays while deliberately retaining the host-only descriptor."""
function adapt_execution(to, state::CompiledPottsState)
    return CompiledPottsState(state.descriptor, Adapt.adapt(to, state.storage))
end

function _device_array_value(array)
    return array isa AbstractArray && isbitstype(eltype(array))
end

_storage_arrays(storage::CompiledStateStorage) = (
    storage.ownership.tags, storage.ownership.ids, storage.active,
    storage.generations, storage.cell_types, storage.reusable_slots, storage.reusable_count,
    values(storage.properties)...)

_storage_backend(storage::CompiledStateStorage) =
    KernelAbstractions.get_backend(storage.active)

_array_bytes(array::AbstractArray) = sizeof(eltype(array)) * length(array)

"""Conservatively validate that every runtime field passed to kernels is an isbits array tree."""
function device_storage_valid(storage::CompiledStateStorage)
    arrays = _storage_arrays(storage)
    all(_device_array_value, arrays) || return false
    backends = map(KernelAbstractions.get_backend, arrays)
    return all(isequal(first(backends)), backends)
end

function _logical_snapshot(state::CompiledPottsState, to_host)
    descriptor = state.descriptor
    storage = state.storage
    tags = to_host(storage.ownership.tags)
    ids = to_host(storage.ownership.ids)
    owners = similar(ids, OwnerRef)
    for index in eachindex(owners)
        owners[index] = OwnerRef(tags[index], ids[index])
    end
    active = to_host(storage.active)
    generations = CellGeneration.(to_host(storage.generations))
    cell_types_raw = to_host(storage.cell_types)
    cell_types = Dict(CellID(index) => CellTypeID(cell_types_raw[index])
        for index in eachindex(active) if active[index] != 0)
    reusable_raw = to_host(storage.reusable_slots)
    reusable_count = Int(only(to_host(storage.reusable_count)))
    reusable_count <= length(reusable_raw) || throw(LogicalStateInvariantError(
        ["compiled reusable-slot count exceeds fixed storage capacity"]))
    reusable = CellSlot.(reusable_raw[1:reusable_count])
    logical = LogicalPottsState(owners, descriptor.capacity;
        active_ids = CellID.(findall(!iszero, active)),
        reusable_slots = reusable,
        generations = generations,
        cell_types = cell_types,
        medium_domains = MediumID.(descriptor.medium_ids),
        property_schema = descriptor.property_schema)
    for key in property_keys(descriptor.property_schema)
        copyto!(property_values(logical, key),
            to_host(getproperty(storage.properties, key)))
    end
    rebuild_derived_state!(logical)
    return assert_valid_state(logical)
end

"""Reconstruct a host snapshot from CPU storage that has no outstanding asynchronous work."""
function logical_snapshot(state::CompiledPottsState)
    _storage_backend(state.storage) isa KernelAbstractions.CPU || throw(ArgumentError(
        "GPU logical snapshots require `logical_snapshot(plan, state)` so synchronization and transfers are recorded"))
    return _logical_snapshot(state, Array)
end

struct WorkspaceRequirements
    sites::Int
    cells::Int
    scratch_uint32::Int
    scratch_float32::Int
    flags::Int

    function WorkspaceRequirements(sites::Integer, cells::Integer;
            scratch_uint32::Integer = sites, scratch_float32::Integer = cells,
            flags::Integer = cells)
        all(>=(0), (sites, cells, scratch_uint32, scratch_float32, flags)) ||
            throw(ArgumentError("workspace sizes must be non-negative"))
        new(sites, cells, scratch_uint32, scratch_float32, flags)
    end
end

workspace_bytes(requirements::WorkspaceRequirements) =
    4 * requirements.scratch_uint32 + 4 * requirements.scratch_float32 + requirements.flags

struct ExecutionWorkspace{U, F, B}
    scratch_uint32::U
    scratch_float32::F
    flags::B
end

struct TransactionRequirements
    max_candidates::Int

    function TransactionRequirements(max_candidates::Integer)
        max_candidates >= 0 || throw(ArgumentError("transaction capacity must be non-negative"))
        new(max_candidates)
    end
end


"""Reusable staging buffers for snapshot/evaluate/commit algorithms."""
struct TransactionWorkspace{I, P, A, D}
    candidate_ids::I
    priorities::P
    accepted::A
    integer_deltas::D
end

transaction_workspace_bytes(requirements::TransactionRequirements) =
    13 * requirements.max_candidates

function allocate_transaction_workspace(state::CompiledPottsState,
        requirements::TransactionRequirements)
    prototype = state.storage.active
    workspace = TransactionWorkspace(
        similar(prototype, UInt32, requirements.max_candidates),
        similar(prototype, UInt32, requirements.max_candidates),
        similar(prototype, UInt8, requirements.max_candidates),
        similar(prototype, Int32, requirements.max_candidates),
    )
    fill!(workspace.candidate_ids, 0)
    fill!(workspace.priorities, 0)
    fill!(workspace.accepted, 0)
    fill!(workspace.integer_deltas, 0)
    return workspace
end

function allocate_workspace(state::CompiledPottsState, requirements::WorkspaceRequirements)
    prototype = state.storage.active
    workspace = ExecutionWorkspace(
        similar(prototype, UInt32, requirements.scratch_uint32),
        similar(prototype, Float32, requirements.scratch_float32),
        similar(prototype, UInt8, requirements.flags),
    )
    fill!(workspace.scratch_uint32, 0)
    fill!(workspace.scratch_float32, 0)
    fill!(workspace.flags, 0)
    return workspace
end

abstract type AbstractLaunchPolicy end
struct OrderedAsynchronousLaunches <: AbstractLaunchPolicy end
abstract type AbstractSynchronizationPolicy end
struct ExplicitObservationSynchronization <: AbstractSynchronizationPolicy end

mutable struct ExecutionMetrics
    launches::Int
    host_synchronizations::Int
    host_to_device_transfers::Int
    device_to_host_transfers::Int
    host_allocations::Int
    device_allocations::Int
    host_allocated_bytes::Int
    device_allocated_bytes::Int
end
ExecutionMetrics() = ExecutionMetrics(0, 0, 0, 0, 0, 0, 0, 0)

"""Immutable execution policy and backend paired with separately mutable instrumentation."""
struct ExecutionPlan{B, C <: BackendCapabilities, L <: AbstractLaunchPolicy,
        S <: AbstractSynchronizationPolicy, M <: ExecutionMetrics}
    backend::B
    capabilities::C
    launch_policy::L
    synchronization_policy::S
    block_size::Int
    metrics::M
end

function ExecutionPlan(backend::KernelAbstractions.Backend; block_size::Integer = DEFAULT_BLOCK_SIZE,
        metrics::ExecutionMetrics = ExecutionMetrics())
    block_size > 0 || throw(ArgumentError("block size must be positive"))
    capabilities = backend_capabilities(backend)
    require_capability(capabilities, QualifiedBackendCapability())
    require_capability(capabilities, FunctionalBackendCapability())
    require_capability(capabilities, OrderedLaunchCapability())
    return ExecutionPlan(backend, capabilities, OrderedAsynchronousLaunches(),
        ExplicitObservationSynchronization(), Int(block_size), metrics)
end

const CPU_SERIAL_GRAIN_LIMIT = 1024

"""Instantiate a bulk kernel with the qualified backend-specific grain policy."""
@inline function _execution_kernel(
        plan::ExecutionPlan{<:KernelAbstractions.CPU}, kernel, ndrange::Integer)
    ndrange <= CPU_SERIAL_GRAIN_LIMIT && return kernel(plan.backend)
    return kernel(plan.backend, plan.block_size)
end
@inline _execution_kernel(plan::ExecutionPlan, kernel, ::Integer) =
    kernel(plan.backend, plan.block_size)
@inline _fixed_execution_kernel(plan::ExecutionPlan, kernel) =
    kernel(plan.backend, plan.block_size)

@inline function launch!(plan::ExecutionPlan, kernel, args...; ndrange, workgroupsize = nothing)
    plan.metrics.launches += 1
    if workgroupsize === nothing
        return kernel(args...; ndrange)
    end
    return kernel(args...; ndrange, workgroupsize)
end

function synchronize_observation!(plan::ExecutionPlan)
    plan.metrics.host_synchronizations += 1
    KernelAbstractions.synchronize(plan.backend)
    return nothing
end

function record_transfer!(plan::ExecutionPlan, direction::Symbol)
    if direction === :host_to_device
        plan.metrics.host_to_device_transfers += 1
    elseif direction === :device_to_host
        plan.metrics.device_to_host_transfers += 1
    else
        throw(ArgumentError("transfer direction must be :host_to_device or :device_to_host"))
    end
    return plan
end


function record_allocation!(plan::ExecutionPlan, domain::Symbol, bytes::Integer)
    bytes >= 0 || throw(ArgumentError("allocated bytes must be non-negative"))
    if domain === :host
        plan.metrics.host_allocations += 1
        plan.metrics.host_allocated_bytes += bytes
    elseif domain === :device
        plan.metrics.device_allocations += 1
        plan.metrics.device_allocated_bytes += bytes
    else
        throw(ArgumentError("allocation domain must be :host or :device"))
    end
    return plan
end

function _require_plan_backend(plan::ExecutionPlan, storage::CompiledStateStorage)
    isequal(plan.backend, _storage_backend(storage)) || throw(ArgumentError(
        "execution plan backend does not match compiled state storage"))
    return plan
end

"""Instrumented initialization-time adaptation of the compiled storage boundary."""
function adapt_execution(plan::ExecutionPlan, to, state::CompiledPottsState)
    _storage_backend(state.storage) isa KernelAbstractions.CPU || throw(ArgumentError(
        "plan-aware adaptation currently requires canonical CPU compiled storage as its source"))
    adapted = adapt_execution(to, state)
    _require_plan_backend(plan, adapted.storage)
    if !(plan.backend isa KernelAbstractions.CPU)
        for array in _storage_arrays(adapted.storage)
            record_transfer!(plan, :host_to_device)
            record_allocation!(plan, :device, _array_bytes(array))
        end
    end
    return adapted
end

"""One synchronized, fully instrumented device-to-host logical observation."""
function logical_snapshot(plan::ExecutionPlan, state::CompiledPottsState)
    _require_plan_backend(plan, state.storage)
    synchronize_observation!(plan)
    if plan.backend isa KernelAbstractions.CPU
        return _logical_snapshot(state, Array)
    end
    to_host = function(array)
        record_transfer!(plan, :device_to_host)
        return Array(array)
    end
    return _logical_snapshot(state, to_host)
end

function allocate_workspace(plan::ExecutionPlan, state::CompiledPottsState,
        requirements::WorkspaceRequirements)
    _require_plan_backend(plan, state.storage)
    workspace = allocate_workspace(state, requirements)
    domain = plan.backend isa KernelAbstractions.CPU ? :host : :device
    for array in (workspace.scratch_uint32, workspace.scratch_float32, workspace.flags)
        record_allocation!(plan, domain, _array_bytes(array))
    end
    return workspace
end

function allocate_transaction_workspace(plan::ExecutionPlan, state::CompiledPottsState,
        requirements::TransactionRequirements)
    _require_plan_backend(plan, state.storage)
    workspace = allocate_transaction_workspace(state, requirements)
    domain = plan.backend isa KernelAbstractions.CPU ? :host : :device
    for array in (workspace.candidate_ids, workspace.priorities, workspace.accepted,
            workspace.integer_deltas)
        record_allocation!(plan, domain, _array_bytes(array))
    end
    return workspace
end
