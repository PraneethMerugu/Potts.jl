using KernelAbstractions

@kernel function _phase5_increment!(output, input)
    index = @index(Global, Linear)
    @inbounds output[index] = input[index] + UInt32(1)
end

@kernel function _phase5_double!(output, input)
    index = @index(Global, Linear)
    @inbounds output[index] = input[index] * UInt32(2)
end

@testset "Phase 5 compiled execution contracts" begin
    provenance = ComponentIdentity(:phase5_execution_test, v"1.0.0", :test)
    schema = PropertySchema(PropertyDescriptor(:target_volume, Int32,
        ConstantInitializer(Int32(0)); requester = provenance))
    logical = LogicalPottsState(reshape(OwnerRef[
            CellOwner(1), CellOwner(1), MediumOwner(1), CellOwner(2),
        ], 2, 2), CellCapacity(4);
        reusable_slots = CellSlot[CellSlot(3)],
        generations = CellGeneration[CellGeneration(5), CellGeneration(2),
            CellGeneration(0), CellGeneration(0)],
        cell_types = Dict(CellID(1) => CellTypeID(2), CellID(2) => CellTypeID(3)),
        medium_domains = MediumID[MediumID(1)], property_schema = schema)
    set_cell_property!(logical, :target_volume, CellID(1), Int32(12))
    set_cell_property!(logical, :target_volume, CellID(2), Int32(7))

    compiled = compile_state(logical)
    @test compiled.descriptor.lattice_dims == (2, 2)
    @test compiled.storage.active == UInt8[1, 1, 0, 0]
    @test compiled.storage.reusable_slots == UInt32[3, 0, 0, 0]
    @test compiled.storage.reusable_count == UInt32[1]
    @test device_storage_valid(compiled.storage)
    @test execution_storage(compiled) === compiled.storage
    @test adapt_execution(Array, compiled).descriptor === compiled.descriptor

    snapshot = logical_snapshot(compiled)
    @test lattice_storage(snapshot) == lattice_storage(logical)
    @test active_cell_ids(snapshot) == active_cell_ids(logical)
    @test reusable_cell_slots(snapshot) == reusable_cell_slots(logical)
    @test property_values(snapshot, :target_volume) == Int32[12, 7, 0, 0]
    @test generation(snapshot, CellID(1)) == CellGeneration(5)

    requirements = WorkspaceRequirements(4, 4; scratch_uint32 = 4,
        scratch_float32 = 4, flags = 4)
    @test workspace_bytes(requirements) == 36
    workspace = allocate_workspace(compiled, requirements)
    @test workspace.scratch_uint32 == zeros(UInt32, 4)
    @test workspace.scratch_float32 == zeros(Float32, 4)
    @test workspace.flags == zeros(UInt8, 4)
    transaction_requirements = TransactionRequirements(4)
    @test transaction_workspace_bytes(transaction_requirements) == 52
    transaction = allocate_transaction_workspace(compiled, transaction_requirements)
    @test transaction.candidate_ids == zeros(UInt32, 4)
    @test transaction.priorities == zeros(UInt32, 4)
    @test transaction.accepted == zeros(UInt8, 4)
    @test transaction.integer_deltas == zeros(Int32, 4)

    backend = KernelAbstractions.CPU()
    capabilities = backend_capabilities(backend)
    @test capabilities.family === CPUFamily
    @test capabilities.contract_status === QualifiedBackend
    @test require_capability(capabilities, :qualified_backend) === capabilities
    @test require_capability(capabilities, :semantic_rng_v1) === capabilities
    @test_throws UnsupportedBackendCapability require_capability(capabilities, :subgroup_intrinsics)
    deferred = BackendCapabilities(CUDAFamily, DeferredBackend,
        true, true, true, true, ())
    @test_throws UnsupportedBackendCapability require_capability(deferred, :qualified_backend)

    initialization_metrics = ExecutionMetrics()
    initialization_plan = ExecutionPlan(backend; block_size = 64,
        metrics = initialization_metrics)
    instrumented_compiled = adapt_execution(initialization_plan, Array, compiled)
    @test instrumented_compiled.storage.active == compiled.storage.active
    instrumented_workspace = allocate_workspace(
        initialization_plan, instrumented_compiled, requirements)
    instrumented_transaction = allocate_transaction_workspace(
        initialization_plan, instrumented_compiled, transaction_requirements)
    @test instrumented_workspace.scratch_uint32 == workspace.scratch_uint32
    @test instrumented_transaction.candidate_ids == transaction.candidate_ids
    @test initialization_metrics.host_allocations == 7
    @test initialization_metrics.host_allocated_bytes == 88
    @test initialization_metrics.device_allocations == 0
    @test initialization_metrics.host_to_device_transfers == 0
    instrumented_snapshot = logical_snapshot(initialization_plan, instrumented_compiled)
    @test lattice_storage(instrumented_snapshot) == lattice_storage(logical)
    @test initialization_metrics.host_synchronizations == 1
    @test initialization_metrics.device_to_host_transfers == 0

    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 64, metrics)
    input = UInt32[1, 2, 3, 4]
    stage = similar(input)
    output = similar(input)
    increment = _phase5_increment!(backend, 64)
    double = _phase5_double!(backend, 64)
    launch!(plan, increment, stage, input; ndrange = length(input))
    launch!(plan, double, output, stage; ndrange = length(input))
    @test metrics.host_synchronizations == 0
    synchronize_observation!(plan)
    @test output == UInt32[4, 6, 8, 10]
    @test metrics.launches == 2
    @test metrics.host_synchronizations == 1

    cpu_grained_output = similar(input)
    cpu_grained_kernel = CorePotts._execution_kernel(
        plan, _phase5_increment!, length(input))
    launch!(plan, cpu_grained_kernel, cpu_grained_output, input;
        ndrange = length(input))
    @test cpu_grained_output == UInt32[2, 3, 4, 5]
    record_transfer!(plan, :host_to_device)
    record_transfer!(plan, :device_to_host)
    @test metrics.host_to_device_transfers == 1
    @test metrics.device_to_host_transfers == 1
    @test_throws ArgumentError record_transfer!(plan, :unknown)
    record_allocation!(plan, :host, 36)
    record_allocation!(plan, :device, 52)
    @test (metrics.host_allocations, metrics.host_allocated_bytes) == (1, 36)
    @test (metrics.device_allocations, metrics.device_allocated_bytes) == (1, 52)
    @test_throws ArgumentError record_allocation!(plan, :unknown, 1)

    contract = Philox4x32x10V1()
    address = RNGAddress(stream = AcceptanceStream, mcs = 17,
        entity_kind = SiteEntity, entity = 91)
    seed = UInt64(0x1234)
    rng_words(contract, seed, address)
    @test @allocated(rng_words(contract, seed, address)) == 0
    table = CategoricalTable((0.2f0, 0.3f0, 0.5f0))
    categorical_index(table, contract, seed, address)
    @test @allocated(categorical_index(table, contract, seed, address)) == 0
end
