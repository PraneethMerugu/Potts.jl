using Test
using CorePotts
using KernelAbstractions
using SciMLBase
using HDF5
using Zarr

function persistence_integrator_fixture(algorithm = SequentialCPM(temperature = 2.0f0))
    energy = QuadraticVolumeHamiltonian(number_type = Float32)
    owners = fill(MediumOwner(1), 6, 6)
    fill!(view(owners, 2:5, 2:3), CellOwner(1))
    fill!(view(owners, 2:5, 4:5), CellOwner(2))
    logical = LogicalPottsState(owners, CellCapacity(4);
        cell_types = Dict(CellID(1) => CellTypeID(1), CellID(2) => CellTypeID(2)),
        medium_domains = (MediumID(1),), property_schema = required_properties(energy))
    property_values(logical, :target_volume)[1:2] .= Float32[8, 8]
    property_values(logical, :volume_strength)[1:2] .= Float32[1, 1]
    domain = CartesianDomain((6, 6))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    state = compile_scientific_state(logical, domain, tracker)
    plan = ExecutionPlan(KernelAbstractions.CPU())
    lifecycle_event = LifecycleEvent(ActiveCellsTarget(), EveryMCS(),
        AlwaysLifecycleTrigger(), AddCellProperty(:target_volume, 0.25f0);
        semantic_id = 901)
    lifecycle = compile_lifecycle((lifecycle_event,), state, plan)
    return init_scientific(state, proposal,
        ScientificComponentSet(energies = (energy,)), algorithm;
        seed = 0x7065727369737401, plan, lifecycle)
end

@testset "lifecycle and persistence canonical persistence" begin
    initial = persistence_integrator_fixture()
    root = capture_checkpoint(initial)
    @test root.mcs == 0
    @test root.initial_state_fingerprint != ntuple(_ -> UInt8(0), 32)
    @test root.schema_version == CHECKPOINT_SCHEMA_VERSION
    @test root.profile.algorithm_contract == SEQUENTIAL_ALGORITHM_CONTRACT_VERSION
    @test root.profile.rng_contract == RNG_CONTRACT_VERSION
    @test root.profile.numerical_mode == "native_backend"
    @test "Float32" in root.profile.scalar_types
    @test "ownership_id=UInt32" in root.profile.index_types
    @test any(identity -> startswith(identity, "KernelAbstractions@"),
        root.profile.dependency_identities)
    @test startswith(root.profile.backend_runtime_identity,
        "KernelAbstractions@")
    @test validate_checkpoint(root) === root

    snapshot = analysis_snapshot(initial; observables = (cell_count = 2,))
    @test snapshot isa ScientificAnalysisSnapshot
    @test !(snapshot isa CanonicalCheckpoint)
    @test !hasproperty(snapshot, :seed)

    store = MemoryCheckpointStore()
    write_checkpoint!(store, "root", root)
    loaded = read_checkpoint(store, "root")
    @test loaded.checksum == root.checksum
    @test checkpoint_storage_payload(loaded) == checkpoint_storage_payload(root)
    @test_throws ErrorException write_checkpoint!(store, "failed", root;
        fail_after = :payload)
    @test !haskey(store.records, "failed")

    payload = checkpoint_storage_payload(root)
    @test payload.algorithm_contract == string(SEQUENTIAL_ALGORITHM_CONTRACT_VERSION)
    corrupt_active = copy(payload.active)
    corrupt_active[1] = xor(corrupt_active[1], UInt8(1))
    corrupt = merge(payload, (active = corrupt_active,))
    @test_throws CheckpointIntegrityError checkpoint_from_storage_payload(corrupt)
    incomplete = merge(payload, (complete = UInt8(0),))
    @test_throws IncompleteCheckpointError checkpoint_from_storage_payload(incomplete)
    unknown_version = merge(payload, (schema_version = "999.0.0",))
    @test_throws CheckpointCompatibilityError checkpoint_from_storage_payload(
        unknown_version)
    wrong_capacity = merge(payload, (capacity = payload.capacity + UInt32(1),))
    @test_throws CheckpointIntegrityError checkpoint_from_storage_payload(wrong_capacity)
    invalid_tag = copy(payload.ownership_tags)
    invalid_tag[1] = UInt8(99)
    @test_throws CheckpointIntegrityError checkpoint_from_storage_payload(
        merge(payload, (ownership_tags = invalid_tag,)))
    truncated_properties = copy(payload.property_values)
    truncated_properties[1] = truncated_properties[1][1:(end - 1)]
    @test_throws CheckpointIntegrityError checkpoint_from_storage_payload(
        merge(payload, (property_values = truncated_properties,)))

    incompatible_energy = QuadraticVolumeHamiltonian(target = :other_target,
        number_type = Float32)
    @test_throws CheckpointCompatibilityError checkpoint_logical_state(root,
        required_properties(incompatible_energy))

    for algorithm in (SequentialCPM(temperature = 2.0f0),
            CheckerboardSweepCPM(temperature = 2.0f0),
            LotteryCPM(temperature = 2.0f0))
        uninterrupted = persistence_integrator_fixture(algorithm)
        step!(uninterrupted, 2)
        checkpoint = capture_checkpoint(uninterrupted; ancestry = root)
        @test checkpoint.initial_state_fingerprint == root.initial_state_fingerprint
        step!(uninterrupted, 3)
        expected = logical_state(uninterrupted)

        resumed = restore_checkpoint(checkpoint, uninterrupted; adaptor = Array)
        @test resumed.mcs == 2
        step!(resumed, 3)
        observed = logical_state(resumed)
        @test resumed.mcs == uninterrupted.mcs == 5
        @test lattice_storage(observed) == lattice_storage(expected)
        @test property_values(observed, :target_volume) ==
            property_values(expected, :target_volume)
        @test current_mcs_report(resumed) == current_mcs_report(uninterrupted)
    end

    source = persistence_integrator_fixture()
    step!(source)
    checkpoint = capture_checkpoint(source; ancestry = root)
    different = persistence_integrator_fixture(LotteryCPM(temperature = 2.0f0))
    @test_throws CheckpointCompatibilityError restore_checkpoint(checkpoint, different)
    imported, report = import_checkpoint(checkpoint, different)
    @test imported.mcs == checkpoint.mcs
    @test report.guarantee == :statistical_or_weaker
    @test report.source_checksum == checkpoint.checksum

    mktempdir() do directory
        hdf5_store = HDF5CheckpointStore(joinpath(directory, "checkpoint.h5"))
        zarr_store = ZarrCheckpointStore(joinpath(directory, "checkpoint.zarr"))
        write_checkpoint!(hdf5_store, "paper", checkpoint)
        write_checkpoint!(zarr_store, "paper", checkpoint)
        hdf5_checkpoint = read_checkpoint(hdf5_store, "paper")
        zarr_checkpoint = read_checkpoint(zarr_store, "paper")
        @test checkpoint_storage_payload(hdf5_checkpoint) ==
            checkpoint_storage_payload(checkpoint)
        @test checkpoint_storage_payload(zarr_checkpoint) ==
            checkpoint_storage_payload(checkpoint)
        @test checkpoint_storage_payload(hdf5_checkpoint) ==
            checkpoint_storage_payload(zarr_checkpoint)

        @test_throws ErrorException write_checkpoint!(hdf5_store, "paper", checkpoint;
            fail_after = :payload)
        @test_throws ErrorException write_checkpoint!(zarr_store, "paper", checkpoint;
            fail_after = :payload)
        @test read_checkpoint(hdf5_store, "paper").checksum == checkpoint.checksum
        @test read_checkpoint(zarr_store, "paper").checksum == checkpoint.checksum
    end
end
