function independent_cell_center(ownership, owner::Int32)
    sites = findall(==(owner), ownership)
    isempty(sites) && return nothing
    return ntuple(2) do dimension
        sum(site[dimension] - 0.5 for site in sites) / length(sites)
    end
end

function independent_cell_length(ownership, owner::Int32)
    sites = findall(==(owner), ownership)
    isempty(sites) && return 0.0
    center = independent_cell_center(ownership, owner)
    covariance = zeros(Float64, 2, 2)
    for site in sites
        point = (site[1] - 0.5, site[2] - 0.5)
        displacement = (point[1] - center[1], point[2] - center[2])
        for row in 1:2, column in 1:2
            covariance[row, column] +=
                displacement[row] * displacement[column]
        end
    end
    covariance ./= length(sites)
    trace = covariance[1, 1] + covariance[2, 2]
    discriminant = max(
        0.0,
        (covariance[1, 1] - covariance[2, 2])^2 +
        4.0 * covariance[1, 2]^2,
    )
    largest = (trace + sqrt(discriminant)) / 2.0
    return 4.0 * sqrt(max(0.0, largest))
end

function independent_spring_energy(ownership, first_owner, second_owner)
    first_center = independent_cell_center(ownership, first_owner)
    second_center = independent_cell_center(ownership, second_owner)
    first_center === nothing && return 0.0
    second_center === nothing && return 0.0
    distance = sqrt(sum(
        (first_center[index] - second_center[index])^2 for index in 1:2
    ))
    return 1.5 * (distance - 3.0)^2
end

@testset "cell geometry matches independent global energy oracles" begin
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            CorePotts.CellMomentsTracker{2, Float64}(),
        ),
        "scientific-geometry-trackers-v1",
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); tracker_plan
    )
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    runtime = CorePotts.initialize_program(
        program,
        CorePotts.ProgramInitialState(
            ownership, Int16[2, 2]; scalar_type = Float64
        ),
        Float64[],
        UInt64(0xe10),
        UInt32(1),
    )

    for owner in Int32(1):Int32(2)
        observed_center = CorePotts._cell_center(runtime, owner)
        expected_center = independent_cell_center(ownership, owner)
        @test all(isapprox.(observed_center, expected_center))
        @test CorePotts._cell_length(runtime, owner) ≈
              independent_cell_length(ownership, owner)
    end

    cases = (
        (CartesianIndex(2, 4), Int32(1)),
        (CartesianIndex(2, 2), Int32(0)),
        (CartesianIndex(3, 3), Int32(2)),
    )
    for (target_site, new_owner) in cases
        old_owner = ownership[target_site]
        affected = unique(filter(>(0), (old_owner, new_owner)))
        core_elongation_delta = sum(affected; init = 0.0) do owner
            before = CorePotts._cell_length(runtime, owner)
            after = CorePotts._cell_length(
                runtime,
                owner;
                replaced_site = target_site,
                replacement_owner = new_owner,
            )
            (after - 4.0)^2 - (before - 4.0)^2
        end
        after_ownership = copy(ownership)
        after_ownership[target_site] = new_owner
        independent_elongation_delta = sum(affected; init = 0.0) do owner
            (independent_cell_length(after_ownership, owner) - 4.0)^2 -
            (independent_cell_length(ownership, owner) - 4.0)^2
        end
        @test core_elongation_delta ≈ independent_elongation_delta

        before_first = CorePotts._cell_center(runtime, Int32(1))
        before_second = CorePotts._cell_center(runtime, Int32(2))
        after_first = CorePotts._cell_center(
            runtime,
            Int32(1);
            replaced_site = target_site,
            replacement_owner = new_owner,
        )
        after_second = CorePotts._cell_center(
            runtime,
            Int32(2);
            replaced_site = target_site,
            replacement_owner = new_owner,
        )
        function spring(center_a, center_b)
            if center_a === nothing || center_b === nothing
                return 0.0
            end
            separation = sqrt(sum(
                (center_a[index] - center_b[index])^2 for index in 1:2
            ))
            return 1.5 * (separation - 3.0)^2
        end
        core_spring_delta = spring(after_first, after_second) -
                            spring(before_first, before_second)
        independent_delta = independent_spring_energy(
            after_ownership, Int32(1), Int32(2)
        ) - independent_spring_energy(ownership, Int32(1), Int32(2))
        @test core_spring_delta ≈ independent_delta
        @test runtime.ownership == ownership
    end
end
