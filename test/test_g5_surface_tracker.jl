function _g5_surface_model(
        engine;
        neighborhood = VonNeumann(),
        boundary = Closed(),
        target = 8.0,
        strength = 2.0,
        prefix_relation = false,
    )
    cell = CellKind(:surface_cell)
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

function _g5_surface_runtime(executable, ownership)
    finite_kind = only(findall(!, executable.core_program.medium_kinds))
    initial = CorePotts.ProgramInitialState(
        Int32.(ownership),
        Int16[finite_kind];
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

function _g5_von_neumann_surface(ownership; periodic = false)
    result = zeros(Int32, maximum(ownership; init = 0))
    rows, columns = size(ownership)
    for site in CartesianIndices(ownership)
        owner = ownership[site]
        owner > 0 || continue
        for offset in ((-1, 0), (0, -1), (0, 1), (1, 0))
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
            ownership[neighbor] == owner || (result[owner] += Int32(1))
        end
    end
    return result
end

function _g5_surface_descriptor(executable)
    return only([
        descriptor
        for group in executable.core_program.descriptor_plan.groups
        for descriptor in group.launch.instances
        if descriptor.role isa CorePotts.HamiltonianRole
    ])
end

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

function _g5_global_surface_energy(ownership, target, strength)
    any(==(1), ownership) || return 0.0
    perimeter = only(_g5_von_neumann_surface(ownership))
    return strength * (perimeter - target)^2
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
        surface_descriptor = only(filter(
            item -> CorePotts.tracker_quantity(item) === Val(:cell_surface),
            executable.core_program.tracker_plan.descriptors,
        ))
        shifted_descriptor = only(filter(
            item -> CorePotts.tracker_quantity(item) === Val(:cell_surface),
            shifted.core_program.tracker_plan.descriptors,
        ))
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
                runtime, Val(:cell_surface)
            )
            @test tracked == Int32[expected]
            @test tracked == _g5_von_neumann_surface(ownership)
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
            moore_runtime, Val(:cell_surface)
        ) == Int32[8]

        periodic, _, _ = _g5_surface_model(
            SequentialEngine(); boundary = Periodic()
        )
        seam = zeros(Int32, 5, 5)
        seam[1, 3] = seam[5, 3] = 1
        seam_runtime = _g5_surface_runtime(periodic, seam)
        @test CorePotts.program_tracker_values(
            seam_runtime, Val(:cell_surface)
        ) == Int32[6]
        @test _g5_von_neumann_surface(seam; periodic = true) == Int32[6]
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
            expected = _g5_global_surface_energy(after, target, strength) -
                       _g5_global_surface_energy(ownership, target, strength)
            @test _g5_surface_delta(descriptor, context) == expected
        end
        @test attempt > 0

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
        surface_tracker = only(filter(
            item -> CorePotts.tracker_quantity(item) === Val(:cell_surface),
            runtime.program.tracker_plan.descriptors,
        ))
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
            runtime, Val(:cell_surface)
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
            runtime, Val(:cell_surface)
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
            runtime, Val(:cell_surface)
        ) == before_surface

        concave = zeros(Int32, 5, 5)
        concave[2:4, 2:4] .= 1
        concave[3, 3] = 0
        relaxation = _g5_surface_runtime(executable, concave)
        perimeter_before = only(CorePotts.program_tracker_values(
            relaxation, Val(:cell_surface)
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
        perimeter_after = only(CorePotts.program_tracker_values(
            relaxation, Val(:cell_surface)
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
            runtime, Val(:cell_surface)
        ) == _g5_von_neumann_surface(runtime.ownership)

        saved = CorePotts.program_checkpoint(runtime)
        @test saved.snapshot.trackers.values[2] === nothing
        restored = CorePotts.restore_program_checkpoint(
            runtime.program, saved
        )
        @test CorePotts.program_tracker_values(
            restored, Val(:cell_surface)
        ) == CorePotts.program_tracker_values(runtime, Val(:cell_surface))

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
        @test CorePotts.program_snapshot(checkerboard_runtime).trackers.values[2] ==
              _g5_von_neumann_surface(checkerboard_runtime.ownership)
    end
end
