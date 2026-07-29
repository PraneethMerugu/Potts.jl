using Test
using CorePotts

@testset "logical state initialization finalization" begin
    provenance = ComponentIdentity(:logical_initialization_test, v"1.0.0", :test)
    schema = PropertySchema(PropertyDescriptor(:age, UInt16, ConstantInitializer(UInt16(0));
        requester = provenance))
    cell_nine = InitialCellLayout(9, 2, Bool[true false false; false false false])
    cell_three = InitialCellLayout(3, 1, Bool[false true false; false true false])
    vanished = InitialCellLayout(6, 1, falses(2, 3))
    medium_two = InitialMediumLayout(2, Bool[false false true; false false false])
    nine_properties = InitialCellProperties(9, 2, (age = UInt16(7),); dimensions = 2)
    initialized = finalize_initial_state((2, 3), nine_properties, cell_nine, cell_three,
        vanished, medium_two;
        capacity = CellCapacity(4), medium_domains = MediumID[MediumID(1), MediumID(2)],
        property_schema = schema)
    state = logical_state(initialized)
    report = initialization_report(initialized)

    # Surviving provisional IDs are compacted in deterministic ascending order: 3 -> 1, 9 -> 2.
    @test report.provisional_to_runtime ==
          [ProvisionalCellID(3) => CellID(1), ProvisionalCellID(9) => CellID(2)]
    @test report.discarded_provisional_ids == ProvisionalCellID[ProvisionalCellID(6)]
    @test active_cell_ids(state) == CellID[CellID(1), CellID(2)]
    @test cell_type(state, CellID(1)) == CellTypeID(1)
    @test cell_type(state, CellID(2)) == CellTypeID(2)
    @test owner_at(state, 1, 1) == CellOwner(2)
    @test owner_at(state, 1, 2) == CellOwner(1)
    @test owner_at(state, 1, 3) == MediumOwner(2)
    @test finite_volume(state, CellID(1)) == 2
    @test finite_volume(state, CellID(2)) == 1
    @test medium_occupancy(state, MediumID(1)) == 2
    @test medium_occupancy(state, MediumID(2)) == 1
    @test property_values(state, :age) == UInt16[0, 7, 0, 0]
    @test assert_valid_state(state) === state

    first = InitialCellLayout(4, 1, Bool[true false; false false])
    second = InitialCellLayout(5, 2, Bool[true false; false false])
    @test_throws InitialLayoutOverlapError finalize_initial_state((2, 2), first, second;
        capacity = CellCapacity(2), medium_domains = MediumID[MediumID(1)])
    prioritized_first = InitialCellLayout(4, 1, Bool[true false; false false]; priority = 2)
    prioritized_second = InitialCellLayout(5, 2, Bool[true false; false false]; priority = 3)
    preserved = logical_state(finalize_initial_state((2, 2), prioritized_first, second;
        capacity = CellCapacity(2), medium_domains = MediumID[MediumID(1)],
        overlap_policy = StableInitialPriority()))
    replaced = logical_state(finalize_initial_state((2, 2), first, prioritized_second;
        capacity = CellCapacity(2), medium_domains = MediumID[MediumID(1)],
        overlap_policy = StableInitialPriority()))
    @test cell_type(preserved, CellID(1)) == CellTypeID(1)
    @test cell_type(replaced, CellID(1)) == CellTypeID(2)
    @test_throws InitialLayoutOverlapError finalize_initial_state((2, 2), first, second;
        capacity = CellCapacity(2), medium_domains = MediumID[MediumID(1)],
        overlap_policy = StableInitialPriority())

    @test_throws CellCapacityError finalize_initial_state((2, 3), cell_nine, cell_three;
        capacity = CellCapacity(1), medium_domains = MediumID[MediumID(1)])
    @test_throws ArgumentError finalize_initial_state((2, 2),
        InitialMediumLayout(2, trues(2, 2)); capacity = CellCapacity(0),
        medium_domains = MediumID[MediumID(1)])

    state_3d = logical_state(finalize_initial_state((2, 2, 2),
        InitialCellLayout(11, 3, reshape(Bool[true, false, false, false, false, false, false, false], 2, 2, 2));
        capacity = CellCapacity(1), medium_domains = MediumID[MediumID(1)]))
    @test lattice_size(state_3d) == (2, 2, 2)
    @test finite_volume(state_3d, CellID(1)) == 1
end


@testset "deterministic and stochastic lifecycle and persistence layouts" begin
    dense = DenseCellLabels(Int[9 0 3; 0 3 0], [9 => 2, 3 => 1])
    dense_state = logical_state(finalize_initial_state((2, 3), dense;
        capacity = CellCapacity(2), medium_domains = (MediumID(1),)))
    @test finite_volume(dense_state, CellID(1)) == 2
    @test finite_volume(dense_state, CellID(2)) == 1

    explicit = CoordinateCellLayout(5, 1, CartesianIndex{2}[CartesianIndex(1, 1)])
    seeds_a = UniformSiteSeeds([30 => 2, 10 => 1], trues(3, 3); operation = 41)
    seeds_b = UniformSiteSeeds([10 => 1, 30 => 2], trues(3, 3); operation = 41)
    initialized_a = finalize_initial_state((3, 3), seeds_a, explicit;
        capacity = CellCapacity(3), medium_domains = (MediumID(1),), seed = 0x1234)
    initialized_b = finalize_initial_state((3, 3), explicit, seeds_b;
        capacity = CellCapacity(3), medium_domains = (MediumID(1),), seed = 0x1234)
    @test lattice_storage(logical_state(initialized_a)) == lattice_storage(logical_state(initialized_b))
    @test initialization_report(initialized_a).provisional_to_runtime ==
          [ProvisionalCellID(5) => CellID(1), ProvisionalCellID(10) => CellID(2),
           ProvisionalCellID(30) => CellID(3)]
    @test owner_at(logical_state(initialized_a), 1, 1) == CellOwner(1)
    @test_throws ArgumentError finalize_initial_state((1, 1),
        UniformSiteSeeds([1 => 1, 2 => 1], trues(1, 1); operation = 1);
        capacity = CellCapacity(2), medium_domains = (MediumID(1),), seed = 1)

    rejection = SequentialRejectionPlacement([20 => 1, 10 => 1], LatticeBall(0.0f0),
        trues(3, 3); attempt_limit = 256, operation = 52)
    rejected_a = finalize_initial_state((3, 3), rejection;
        capacity = CellCapacity(2), medium_domains = (MediumID(1),), seed = 99)
    rejected_b = finalize_initial_state((3, 3), rejection;
        capacity = CellCapacity(2), medium_domains = (MediumID(1),), seed = 99)
    @test lattice_storage(logical_state(rejected_a)) == lattice_storage(logical_state(rejected_b))
    @test finite_volume(logical_state(rejected_a), CellID(1)) == 1
    @test finite_volume(logical_state(rejected_a), CellID(2)) == 1
    @test_throws InitialPlacementError finalize_initial_state((1, 1),
        SequentialRejectionPlacement([1 => 1, 2 => 1], LatticeBall(0.0f0), trues(1, 1);
            attempt_limit = 2, operation = 53);
        capacity = CellCapacity(2), medium_domains = (MediumID(1),), seed = 1)

    periodic_ball = ShapeCellLayout(7, 1, (1, 1), LatticeBall(1.0f0);
        periodic = (true, true))
    periodic_state = logical_state(finalize_initial_state((5, 5), periodic_ball;
        capacity = CellCapacity(1), medium_domains = (MediumID(1),)))
    @test finite_volume(periodic_state, CellID(1)) == 5
    @test owner_at(periodic_state, 5, 1) == CellOwner(1)
    @test owner_at(periodic_state, 1, 5) == CellOwner(1)
    @test_throws ArgumentError finalize_initial_state((2, 2),
        ShapeCellLayout(1, 1, (1, 1), LatticeBox((1, 1)); periodic = (true, true));
        capacity = CellCapacity(1), medium_domains = (MediumID(1),))
    @test_throws ArgumentError finalize_initial_state((5, 5),
        ShapeCellLayout(1, 1, (1, 1), LatticeBall(1.0f0));
        capacity = CellCapacity(1), medium_domains = (MediumID(1),))
end
