isdefined(@__MODULE__, :G5ExternalSurfaceOperation) ||
    include("fixtures/G5ExternalSurfaceOperation.jl")

function _g5_surface_model(
        engine;
        neighborhood = VonNeumann(),
        boundary = Closed(),
        target = 8.0,
        strength = 2.0,
        prefix_relation = false,
    )
    cell = CellKind(:surface_cell; extinction = RetireAtZero())
    medium = MediumKind(:surface_medium)
    anchor = CellBinding(:surface_anchor)
    model = PottsSystem(
        name = :surface_model,
        statements = StatementSet((
            Lattice(
                (5, 5);
                boundary,
                relations = prefix_relation ?
                    (
                        proposal = VonNeumann(),
                        a_unused = VonNeumann(),
                        surface = neighborhood,
                    ) :
                    (
                        proposal = VonNeumann(),
                        surface = neighborhood,
                    ),
            ),
            cell,
            medium,
            HamiltonianTerm(
                :surface_energy;
                domain = cells(cell),
                anchor,
                expression = strength * (cell_surface(anchor) - target)^2,
            ),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
    )
    executable = compile(
        complete(model);
        engine,
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    return executable, cell, medium
end

function _g5_surface_child(name::Symbol, neighborhood)
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = CellBinding(:cell_anchor)
    model = PottsSystem(
        name = name,
        statements = StatementSet((
            SpatialRelation(
                :surface;
                domain = :lattice,
                neighborhood,
            ),
            cell,
            medium,
            HamiltonianTerm(
                :surface_energy;
                domain = cells(cell),
                anchor,
                expression = (cell_surface(anchor) - 8.0)^2,
            ),
        )),
    )
    return model
end

function _g5_surface_runtime(executable, ownership)
    finite_kind = only(findall(!, executable.core_program.medium_kinds))
    cell_count = maximum(ownership; init = 0)
    initial = CorePotts.ProgramInitialState(
        Int32.(ownership),
        fill(Int16(finite_kind), cell_count);
        scalar_type = Float64,
    )
    return CorePotts.initialize_program(
        executable.core_program,
        initial,
        executable.core_program.parameter_defaults,
        UInt64(0x755),
        UInt32(1),
    )
end

function _g5_capacity_tracker_values(runtime, expected)
    result = zeros(eltype(expected), length(runtime.cell_kinds))
    copyto!(result, 1, expected, 1, length(expected))
    return result
end

_g5_surface_offsets(::VonNeumann) = (
    (-1, 0), (0, -1), (0, 1), (1, 0),
)

_g5_surface_offsets(::Moore) = Tuple(
    (row, column)
    for row in -1:1 for column in -1:1
    if (row, column) != (0, 0)
)

function _g5_surface_oracle(ownership, offsets; periodic = false)
    result = zeros(Int32, maximum(ownership; init = 0))
    rows, columns = size(ownership)
    for site in CartesianIndices(ownership)
        owner = ownership[site]
        owner > 0 || continue
        visited = CartesianIndex{2}[]
        for offset in offsets
            row = site[1] + offset[1]
            column = site[2] + offset[2]
            if periodic
                row = mod1(row, rows)
                column = mod1(column, columns)
            elseif !(1 <= row <= rows && 1 <= column <= columns)
                continue
            end
            neighbor = CartesianIndex(row, column)
            neighbor == site && continue
            neighbor in visited && continue
            push!(visited, neighbor)
            ownership[neighbor] == owner || (result[owner] += Int32(1))
        end
    end
    return result
end

_g5_von_neumann_surface(ownership; periodic = false) =
    _g5_surface_oracle(
        ownership, _g5_surface_offsets(VonNeumann()); periodic
    )

function _g5_surface_descriptor(executable)
    return only([
        descriptor
        for group in executable.core_program.descriptor_plan.groups
        for descriptor in group.launch.instances
        if descriptor.role isa CorePotts.HamiltonianRole
    ])
end

function _g5_surface_tracker(executable)
    return only(filter(
        item -> CorePotts.tracker_inspection(item).quantity === :cell_surface,
        CorePotts.tracker_instances(executable.core_program.tracker_plan),
    ))
end

_g5_surface_key(executable) =
    CorePotts.tracker_quantity(_g5_surface_tracker(executable))

function _g5_surface_context(runtime, source, target, attempt = 1)
    return CorePotts._ProposalEvaluationContext(
        runtime,
        source,
        target,
        @inbounds(runtime.ownership[target]),
        @inbounds(runtime.ownership[source]),
        attempt,
        0,
    )
end

@inline function _g5_surface_delta(descriptor, context)
    return CorePotts._compiled_hamiltonian_delta(
        descriptor.evaluator,
        descriptor.role,
        context,
        context.runtime.program.descriptor_plan.domain_resources,
    )
end

function _g5_global_surface_energy(
        ownership, offsets, target, strength; periodic = false
    )
    perimeters = _g5_surface_oracle(ownership, offsets; periodic)
    return sum(perimeters; init = Int32(0)) do perimeter
        strength * (perimeter - target)^2
    end
end

@testset "G5 generic surface tracker" begin
    @testset "contract, initialization, and relation selection" begin
        executable, _, _ = _g5_surface_model(SequentialEngine())
        tracker_report = executable.reports.execution.trackers
        @test tracker_report.quantities == (:cell_volume, :cell_surface)
        surface_report = only(filter(
            report -> report.quantity === :cell_surface,
            tracker_report.descriptors,
        ))
        @test surface_report.source.state === :ownership
        @test surface_report.source.relation_handle > 0
        @test surface_report.checkpoint === :reconstruct
        @test surface_report.proposal_cost == (
            class = :bounded_neighborhood,
            maximum_neighbors = Int16(4),
        )

        shifted, _, _ = _g5_surface_model(
            SequentialEngine(); prefix_relation = true
        )
        surface_descriptor = _g5_surface_tracker(executable)
        shifted_descriptor = _g5_surface_tracker(shifted)
        @test surface_descriptor.relation_handle !=
              shifted_descriptor.relation_handle
        @test typeof(surface_descriptor) === typeof(shifted_descriptor)
        @test typeof(executable.core_program) === typeof(shifted.core_program)

        fixtures = (
            (CartesianIndex(3, 3),) => 4,
            (CartesianIndex(3, 3), CartesianIndex(3, 4)) => 6,
            (
                CartesianIndex(3, 3), CartesianIndex(3, 4),
                CartesianIndex(4, 3), CartesianIndex(4, 4),
            ) => 8,
        )
        for (sites, expected) in fixtures
            ownership = zeros(Int32, 5, 5)
            ownership[collect(sites)] .= 1
            runtime = _g5_surface_runtime(executable, ownership)
            tracked = CorePotts.program_tracker_values(
                runtime, _g5_surface_key(executable)
            )
            @test tracked == _g5_capacity_tracker_values(
                runtime, Int32[expected]
            )
            @test tracked == _g5_capacity_tracker_values(
                runtime, _g5_von_neumann_surface(ownership)
            )
            @test CorePotts.validate_tracker_state!(
                runtime.program.tracker_plan,
                runtime.trackers,
                runtime.ownership,
                runtime.cell_kinds,
                runtime.program,
            ) === runtime.trackers
        end

        moore, _, _ = _g5_surface_model(
            SequentialEngine(); neighborhood = Moore()
        )
        single = zeros(Int32, 5, 5)
        single[3, 3] = 1
        moore_runtime = _g5_surface_runtime(moore, single)
        @test CorePotts.program_tracker_values(
            moore_runtime, _g5_surface_key(moore)
        ) == _g5_capacity_tracker_values(moore_runtime, Int32[8])

        periodic, _, _ = _g5_surface_model(
            SequentialEngine(); boundary = Periodic()
        )
        seam = zeros(Int32, 5, 5)
        seam[1, 3] = seam[5, 3] = 1
        seam_runtime = _g5_surface_runtime(periodic, seam)
        @test CorePotts.program_tracker_values(
            seam_runtime, _g5_surface_key(periodic)
        ) == _g5_capacity_tracker_values(seam_runtime, Int32[6])
        @test _g5_von_neumann_surface(seam; periodic = true) == Int32[6]
    end

    @testset "external operation receives the qualified tracker protocol" begin
        cell = CellKind(:external_surface_cell; extinction = RetireAtZero())
        medium = MediumKind(:external_surface_medium)
        anchor = CellBinding(:external_surface_anchor)
        model = PottsSystem(
            name = :external_surface_model,
            statements = StatementSet((
                Lattice(
                    (5, 5);
                    relations = (
                        proposal = VonNeumann(),
                        surface = Moore(),
                    ),
                ),
                cell,
                medium,
                HamiltonianTerm(
                    :external_surface_energy;
                    domain = cells(cell),
                    anchor,
                    expression = (
                        G5ExternalSurfaceOperation.external_cell_surface(
                            anchor_value(anchor)
                        ) -
                        8.0
                    )^2,
                ),
                Protocol(Sweep(); name = :main),
            )),
        )
        executable = compile(
            complete(model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        tracker = _g5_surface_tracker(executable)
        @test tracker.maximum_neighbors == 8
        @test CorePotts.tracker_quantity(tracker).source_handle ==
              tracker.relation_handle

        ownership = zeros(Int32, 5, 5)
        ownership[2:3, 2:3] .= 1
        runtime = _g5_surface_runtime(executable, ownership)
        descriptor = _g5_surface_descriptor(executable)
        context = _g5_surface_context(
            runtime, CartesianIndex(1, 2), CartesianIndex(2, 2)
        )
        after = copy(ownership)
        after[context.target] = ownership[context.source]
        offsets = _g5_surface_offsets(Moore())
        @test _g5_surface_delta(descriptor, context) ==
              _g5_global_surface_energy(after, offsets, 8.0, 1.0) -
              _g5_global_surface_energy(ownership, offsets, 8.0, 1.0)
        @test Core.Compiler.return_type(
            _g5_surface_delta,
            Tuple{typeof(descriptor), typeof(context)},
        ) === Float64
    end


    @testset "qualified relation-backed trackers compose" begin
        root = PottsSystem(
            name = :surface_root,
            statements = StatementSet((
                Lattice(
                    (5, 5);
                    relations = (proposal = VonNeumann(),),
                ),
                Protocol(Sweep(); name = :main),
            )),
        )
        composed = compose(root, [
            _g5_surface_child(:left, VonNeumann()),
            _g5_surface_child(:right, Moore()),
        ])
        executable = compile(
            complete(composed);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        surface_trackers = filter(
            descriptor -> CorePotts.tracker_inspection(descriptor).quantity ===
                          :cell_surface,
            CorePotts.tracker_instances(executable.core_program.tracker_plan),
        )
        @test length(surface_trackers) == 2
        @test length(executable.core_program.tracker_plan.descriptors) == 2
        surface_group = only(filter(
            descriptor -> descriptor isa CorePotts.DenseScalarTrackerGroup,
            executable.core_program.tracker_plan.descriptors,
        ))
        @test length(surface_group.descriptors) == 2
        @test allunique(getfield.(surface_trackers, :relation_handle))
        @test allequal(typeof.(surface_trackers))
        keys = CorePotts.tracker_quantity.(surface_trackers)
        @test allunique(keys)
        @test allequal(typeof.(keys))

        single_executable, _, _ = _g5_surface_model(SequentialEngine())
        @test typeof(single_executable.core_program.tracker_plan) ===
              typeof(executable.core_program.tracker_plan)
        @test typeof(CorePotts.tracker_kernel_plan(
            single_executable.core_program.tracker_plan
        )) === typeof(CorePotts.tracker_kernel_plan(
            executable.core_program.tracker_plan
        ))

        ownership = zeros(Int32, 5, 5)
        ownership[3, 3] = 1
        finite_kind = first(findall(!, executable.core_program.medium_kinds))
        initial = CorePotts.ProgramInitialState(
            ownership,
            Int16[finite_kind];
            scalar_type = Float64,
        )
        runtime = CorePotts.initialize_program(
            executable.core_program,
            initial,
            executable.core_program.parameter_defaults,
            UInt64(0x755),
            UInt32(1),
        )
        tracked = Set(
            first(CorePotts.program_tracker_values(runtime, key))
            for key in keys
        )
        @test tracked == Set((Int32(4), Int32(8)))
        @test CorePotts.validate_tracker_state!(
            executable.core_program.tracker_plan,
            runtime.trackers,
            runtime.ownership,
            runtime.cell_kinds,
            executable.core_program,
        ) === runtime.trackers

        structural_plans = map((1, 32, 1024)) do count
            group = CorePotts.DenseScalarTrackerGroup([
                CorePotts.CellSurfaceTracker(Int32(index), Int16(4))
                for index in 1:count
            ])
            CorePotts.TrackerExecutionPlan(
                (CorePotts.OwnershipCountTracker(), group),
                "surface-growth-$count",
            )
        end
        @test allequal(typeof.(structural_plans))
        @test allequal(typeof.(
            CorePotts.tracker_kernel_plan.(structural_plans)
        ))
        @test length.(CorePotts.tracker_instances.(structural_plans)) ==
              (2, 33, 1025)
    end

    @testset "immutable local delta equals independent global energy" begin
        target = 8.0
        strength = 2.0
        executable, _, _ = _g5_surface_model(
            SequentialEngine(); target, strength
        )
        ownership = zeros(Int32, 5, 5)
        ownership[2:3, 2:3] .= 1
        runtime = _g5_surface_runtime(executable, ownership)
        descriptor = _g5_surface_descriptor(executable)
        offsets = (
            CartesianIndex(-1, 0), CartesianIndex(0, -1),
            CartesianIndex(0, 1), CartesianIndex(1, 0),
        )
        attempt = 0
        for target_site in CartesianIndices(ownership), offset in offsets
            source_site = target_site + offset
            checkbounds(Bool, ownership, source_site) || continue
            ownership[source_site] == ownership[target_site] && continue
            attempt += 1
            context = _g5_surface_context(
                runtime, source_site, target_site, attempt
            )
            after = copy(ownership)
            after[target_site] = ownership[source_site]
            expected = _g5_global_surface_energy(
                after, offsets, target, strength
            ) - _g5_global_surface_energy(
                ownership, offsets, target, strength
            )
            @test _g5_surface_delta(descriptor, context) == expected
        end
        @test attempt > 0

        cell_to_cell = zeros(Int32, 5, 5)
        cell_to_cell[2:3, 2] .= 1
        cell_to_cell[2:3, 3] .= 2
        moore_ownership = copy(cell_to_cell)
        periodic_ownership = zeros(Int32, 5, 5)
        periodic_ownership[5, 3] = 1
        cases = (
            (
                neighborhood = VonNeumann(), boundary = Closed(),
                ownership = cell_to_cell,
                source = CartesianIndex(2, 3),
                target_site = CartesianIndex(2, 2), periodic = false,
            ),
            (
                neighborhood = Moore(), boundary = Closed(),
                ownership = moore_ownership,
                source = CartesianIndex(2, 3),
                target_site = CartesianIndex(2, 2), periodic = false,
            ),
            (
                neighborhood = VonNeumann(), boundary = Periodic(),
                ownership = periodic_ownership,
                source = CartesianIndex(5, 3),
                target_site = CartesianIndex(1, 3), periodic = true,
            ),
        )
        for fixture in cases
            candidate, _, _ = _g5_surface_model(
                SequentialEngine();
                neighborhood = fixture.neighborhood,
                boundary = fixture.boundary,
                target,
                strength,
            )
            candidate_runtime = _g5_surface_runtime(
                candidate, fixture.ownership
            )
            candidate_descriptor = _g5_surface_descriptor(candidate)
            context = _g5_surface_context(
                candidate_runtime,
                fixture.source,
                fixture.target_site,
            )
            after = copy(fixture.ownership)
            after[fixture.target_site] = fixture.ownership[fixture.source]
            candidate_offsets = _g5_surface_offsets(fixture.neighborhood)
            expected = _g5_global_surface_energy(
                after,
                candidate_offsets,
                target,
                strength;
                periodic = fixture.periodic,
            ) - _g5_global_surface_energy(
                fixture.ownership,
                candidate_offsets,
                target,
                strength;
                periodic = fixture.periodic,
            )
            @test _g5_surface_delta(candidate_descriptor, context) == expected
            tracked = CorePotts.program_tracker_values(
                candidate_runtime, _g5_surface_key(candidate)
            )
            @test tracked == _g5_capacity_tracker_values(
                candidate_runtime,
                _g5_surface_oracle(
                    fixture.ownership,
                    candidate_offsets;
                    periodic = fixture.periodic,
                ),
            )
        end

        context = _g5_surface_context(
            runtime, CartesianIndex(2, 3), CartesianIndex(2, 4)
        )
        _g5_surface_delta(descriptor, context)
        @test @allocated(_g5_surface_delta(descriptor, context)) == 0
        @test Core.Compiler.return_type(
            _g5_surface_delta,
            Tuple{typeof(descriptor), typeof(context)},
        ) === Float64
        source_view = CorePotts.tracker_source_view(
            runtime.program, runtime.ownership
        )
        surface_tracker = _g5_surface_tracker(executable)
        @test Core.Compiler.return_type(
            CorePotts.tracker_proposal_delta,
            Tuple{
                typeof(surface_tracker), typeof(source_view),
                CartesianIndex{2}, Int32, Int32,
            },
        ) === CorePotts.SourceTargetScalarDelta{Int32}
    end

    @testset "commit atomicity, reconstruction, and checkerboard exclusion" begin
        executable, _, _ = _g5_surface_model(SequentialEngine())
        ownership = zeros(Int32, 5, 5)
        ownership[2:3, 2:3] .= 1
        runtime = _g5_surface_runtime(executable, ownership)
        before_ownership = copy(runtime.ownership)
        before_surface = copy(CorePotts.program_tracker_values(
            runtime, _g5_surface_key(executable)
        ))

        rejected = _g5_surface_context(
            runtime, CartesianIndex(2, 3), CartesianIndex(2, 4)
        )
        @test !CorePotts._attempt_selected!(
            runtime,
            rejected.source,
            rejected.target,
            rejected.attempt,
            rejected.subround,
            Val(:scripted),
            prevfloat(1.0),
        )
        @test runtime.ownership == before_ownership
        @test CorePotts.program_tracker_values(
            runtime, _g5_surface_key(executable)
        ) == before_surface

        noop = _g5_surface_context(
            runtime, CartesianIndex(2, 2), CartesianIndex(2, 3)
        )
        @test !CorePotts._attempt_selected!(
            runtime,
            noop.source,
            noop.target,
            noop.attempt,
            noop.subround,
            Val(:scripted),
            0.0,
        )
        @test runtime.ownership == before_ownership
        @test CorePotts.program_tracker_values(
            runtime, _g5_surface_key(executable)
        ) == before_surface

        concave = zeros(Int32, 5, 5)
        concave[2:4, 2:4] .= 1
        concave[3, 3] = 0
        relaxation = _g5_surface_runtime(executable, concave)
        perimeter_before = first(CorePotts.program_tracker_values(
            relaxation, _g5_surface_key(executable)
        ))
        @test CorePotts._attempt_selected!(
            relaxation,
            CartesianIndex(2, 3),
            CartesianIndex(3, 3),
            1,
            0,
            Val(:scripted),
            0.5,
        )
        perimeter_after = first(CorePotts.program_tracker_values(
            relaxation, _g5_surface_key(executable)
        ))
        @test (perimeter_before, perimeter_after) == (16, 12)

        accepted = _g5_surface_context(
            runtime, CartesianIndex(1, 2), CartesianIndex(2, 2)
        )
        CorePotts._commit_copy!(
            runtime,
            accepted.target,
            accepted.old_owner,
            accepted.new_owner,
            accepted,
        )
        @test CorePotts.program_tracker_values(
            runtime, _g5_surface_key(executable)
        ) == _g5_capacity_tracker_values(
            runtime, _g5_von_neumann_surface(runtime.ownership)
        )

        saved = CorePotts.program_checkpoint(runtime)
        @test saved.snapshot.trackers.values[2] === nothing
        restored = CorePotts.restore_program_checkpoint(
            runtime.program, saved
        )
        @test CorePotts.program_tracker_values(
            restored, _g5_surface_key(executable)
        ) == CorePotts.program_tracker_values(
            runtime, _g5_surface_key(executable)
        )

        checkerboard, _, _ = _g5_surface_model(CheckerboardEngine())
        conflicts = Set(
            Tuple(checkerboard.core_program.checkerboard_plan.conflict_displacements[:, column])
            for column in axes(
                checkerboard.core_program.checkerboard_plan.conflict_displacements, 2
            )
        )
        @test Set(((-1, 0), (0, -1), (0, 1), (1, 0))) <= conflicts
        checkerboard_runtime = _g5_surface_runtime(checkerboard, ownership)
        CorePotts.advance_mcs!(checkerboard_runtime)
        snapshot = CorePotts.program_snapshot(checkerboard_runtime)
        @test CorePotts.program_tracker_values(
            checkerboard.core_program,
            snapshot,
            _g5_surface_key(checkerboard),
        ) == _g5_capacity_tracker_values(
            checkerboard_runtime,
            _g5_von_neumann_surface(checkerboard_runtime.ownership),
        )
    end
end
