function surface_program(periodic::NTuple{2, Bool}, offsets::Matrix{Int8})
    resources = CorePotts.HamiltonianDomainResources(
        offsets,
        Int32[1],
        Int32[size(offsets, 2)],
        Int32[0],
    )
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        Int32(0),
        "surface-tracker-descriptor-plan-v1",
        resources,
    )
    surface = CorePotts.CellSurfaceTracker(
        Int32(1), Int16(size(offsets, 2))
    )
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(), surface),
        "surface-tracker-plan-v1",
    )
    program = CorePotts.CompiledPottsProgram(
        (6, 6),
        periodic,
        offsets,
        2,
        1,
        CorePotts.CompiledScalar(0.0),
        1,
        Float64[],
        (),
        tracker_plan,
        descriptor_plan,
        CorePotts.StageExecutionPlan(),
        CorePotts.SequentialProgramEngine(),
        CorePotts.CPUProgramBackend(),
        "surface-tracker-program-v1",
    )
    return program, surface
end

function independent_surface_counts(
        ownership::AbstractMatrix{Int32},
        offsets::Matrix{Int8};
        periodic::NTuple{2, Bool},
        capacity::Integer,
    )
    counts = zeros(Int32, capacity)
    shape = size(ownership)
    for site in CartesianIndices(ownership)
        owner = ownership[site]
        owner > 0 || continue
        observed = Set{CartesianIndex{2}}()
        for column in axes(offsets, 2)
            coordinates = ntuple(2) do dimension
                value = site[dimension] + Int(offsets[dimension, column])
                periodic[dimension] ? mod1(value, shape[dimension]) : value
            end
            all(
                dimension -> 1 <= coordinates[dimension] <= shape[dimension],
                1:2,
            ) || continue
            neighbor = CartesianIndex(coordinates)
            neighbor == site && continue
            neighbor in observed && continue
            push!(observed, neighbor)
            ownership[neighbor] == owner || (counts[Int(owner)] += 1)
        end
    end
    return counts
end

@testset "surface tracker equals an independent ownership oracle" begin
    von_neumann = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    for periodic in ((false, false), (true, true))
        program, descriptor = surface_program(periodic, von_neumann)
        key = CorePotts.tracker_quantity(descriptor)
        @test key isa CorePotts.QualifiedTrackerKey
        @test CorePotts.tracker_contract(descriptor).checkpoint isa
              CorePotts.ReconstructTrackerCheckpoint

        fixtures = Matrix{Int32}[]
        single = zeros(Int32, 6, 6)
        single[3, 3] = 1
        push!(fixtures, single)
        pair = zeros(Int32, 6, 6)
        pair[3, 3:4] .= 1
        push!(fixtures, pair)
        square = zeros(Int32, 6, 6)
        square[3:4, 3:4] .= 1
        push!(fixtures, square)
        seam = zeros(Int32, 6, 6)
        seam[1, 3] = seam[6, 3] = 1
        push!(fixtures, seam)

        for ownership in fixtures
            runtime = CorePotts.initialize_program(
                program,
                CorePotts.ProgramInitialState(
                    ownership, Int16[2]; scalar_type = Float64
                ),
                Float64[],
                UInt64(0x5fa),
                UInt32(1),
            )
            expected = independent_surface_counts(
                ownership,
                von_neumann;
                periodic,
                capacity = 1,
            )
            @test CorePotts.program_tracker_values(runtime, key) == expected
            @test CorePotts.validate_tracker_state!(
                program.tracker_plan,
                runtime.trackers,
                runtime.ownership,
                runtime.cell_kinds,
                program,
            ) === runtime.trackers

            checkpoint = CorePotts.program_checkpoint(runtime)
            @test checkpoint.snapshot.trackers.values[2] === nothing
            restored = CorePotts.restore_program_checkpoint(program, checkpoint)
            @test CorePotts.program_tracker_values(restored, key) == expected
        end

        ownership = zeros(Int32, 6, 6)
        ownership[3:4, 3:4] .= 1
        runtime = CorePotts.initialize_program(
            program,
            CorePotts.ProgramInitialState(
                ownership, Int16[2]; scalar_type = Float64
            ),
            Float64[],
            UInt64(0x5fb),
            UInt32(1),
        )
        target = CartesianIndex(3, 3)
        source = CorePotts.tracker_source_view(program, runtime.ownership)
        CorePotts.commit_tracker_updates!(
            runtime.trackers,
            program.tracker_plan,
            source,
            target,
            Int32(1),
            Int32(0),
        )
        runtime.ownership[target] = 0
        @test CorePotts.program_tracker_values(runtime, key) ==
              independent_surface_counts(
                  runtime.ownership,
                  von_neumann;
                  periodic,
                  capacity = 1,
              )
        @test CorePotts.validate_tracker_state!(
            program.tracker_plan,
            runtime.trackers,
            runtime.ownership,
            runtime.cell_kinds,
            program,
        ) === runtime.trackers
    end
end
