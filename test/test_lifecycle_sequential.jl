if !isdefined(Main, :LifecycleOperationFixtures)
    include("fixtures/LifecycleOperationFixtures.jl")
end
using .LifecycleOperationFixtures

struct LifecycleProbeAdaptor end
struct LifecycleProbeArray{T, N, A <: Array{T, N}} <: AbstractArray{T, N}
    values::A
end
Base.size(values::LifecycleProbeArray) = size(values.values)
Base.getindex(values::LifecycleProbeArray, indices...) =
    getindex(values.values, indices...)
Base.setindex!(values::LifecycleProbeArray, value, indices...) =
    setindex!(values.values, value, indices...)
Base.IndexStyle(::Type{<:LifecycleProbeArray}) = IndexLinear()
CorePotts.Adapt.adapt_storage(
    ::LifecycleProbeAdaptor, values::AbstractArray{T, N}
) where {T, N} = LifecycleProbeArray(Array(values))

function _lifecycle_runtime(executable, initial; seed = 0x51f3)
    problem = PottsProblem(executable, initial, (0, 1); seed)
    return init(problem).runtime
end

function _execute_lifecycle_at!(runtime, mcs)
    runtime.mcs = mcs - 1
    CorePotts.execute_lifecycle!(runtime)
    runtime.mcs = mcs
    return runtime
end

function _assert_lifecycle_recomputation(runtime)
    expected = zeros(Int, length(runtime.cell_kinds))
    for owner in runtime.ownership
        owner > 0 && (expected[owner] += 1)
    end
    tracked = CorePotts.program_tracker_values(runtime, Val(:cell_volume))
    @test tracked == expected
    @test map(!iszero, runtime.cell_kinds) == map(!iszero, expected)
    for slot in eachindex(runtime.relationships)
        @test CorePotts.validate_relationship_integrity(
            runtime.relationships[slot],
            runtime.program.relationships[slot],
            runtime.cell_kinds,
            runtime.cell_generations,
        ) === runtime.relationships[slot]
    end
    return nothing
end

@testset "conservative split fractions are construction-safe" begin
    @variables t conserved(t)
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    relation = SpatialRelation(:division; neighborhood = VonNeumann())
    state = CellState(
        conserved;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:cell)
    divide = LifecycleProcess(
        :invalid_split;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (
                state => SplitConservatively(1.5; rounding = :exact),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = :InvalidConservativeSplit,
        statements = StatementSet((
            Lattice((4, 4); max_cells = 2),
            cell,
            medium,
            relation,
            state,
            divide,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [conserved],
        independent_variables = [t],
    )
    error = try
        complete(system)
        nothing
    catch caught
        caught
    end
    @test error isa PottsToolkit.PottsValidationError
    @test only(error.diagnostics).kind === :invalid_lifecycle_split_fraction
end

@testset "frozen external lifecycle operations execute" begin
    @variables t external_state(t)
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    relation = SpatialRelation(:division; neighborhood = VonNeumann())
    state = CellState(
        external_state;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:external_cell)
    divide = LifecycleProcess(
        :external_divide;
        domain = cells(cell),
        anchor,
        expression = external_lifecycle_trigger(cell_volume(anchor_value(anchor))),
        effects = (Divide(
            anchor;
            geometry = external_lifecycle_partition(anchor_value(anchor)),
            relation,
            side = CanonicalSide(),
            state = (state => CopyToDaughters(),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    create = LifecycleProcess(
        :external_create;
        domain = model(),
        expression = external_lifecycle_trigger(Symbolics.Num(1)),
        effects = (CreateCell(
            cell;
            placement = external_lifecycle_placement(Symbolics.Num(1)),
            state = (
                state => InitializeFrom(
                    external_lifecycle_transform(Symbolics.Num(4))
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    system = PottsSystem(
        name = :ExternalLifecycleExecution,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 4),
            cell,
            medium,
            relation,
            state,
            divide,
            create,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [external_state],
        independent_variables = [t],
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    adapted_plan = CorePotts.Adapt.adapt(
        LifecycleProbeAdaptor(), executable.core_program.lifecycle_plan
    )
    @test adapted_plan isa CorePotts.LifecycleExecutionPlan
    @test adapted_plan.descriptors isa LifecycleProbeArray
    @test adapted_plan.forbid_extinction isa LifecycleProbeArray
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    runtime = _lifecycle_runtime(
        executable,
        PottsInitialState(ownership = LabelledCells(
            labels; cells = [cell], medium
        )),
    )
    lookups = LifecycleOperationFixtures.CALLABLE_LOOKUPS[]
    _execute_lifecycle_at!(runtime, 1)
    @test count(!iszero, runtime.cell_kinds) == 2
    @test sort(filter(!iszero, CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    ))) == Int32[2, 2]
    _execute_lifecycle_at!(runtime, 2)
    @test count(!iszero, runtime.cell_kinds) == 3
    state_handle = only(executable.reports.states).handle
    @test CorePotts.state_block(
        runtime.descriptor_state, state_handle
    ).values[3] == 4
    @test LifecycleOperationFixtures.CALLABLE_LOOKUPS[] == lookups
end

@testset "fixed-capacity sequential lifecycle transactions" begin
    @variables t activity(t)
    cell = CellKind(:cell; extinction = RetireAtZero(priority = -20))
    daughter = CellKind(:daughter; extinction = RetireAtZero(priority = -20))
    medium = MediumKind(:medium)
    relation = SpatialRelation(:division; neighborhood = VonNeumann())
    activity_state = CellState(
        activity;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:event_cell)
    create_site = LinearIndices((6, 6))[CartesianIndex(5, 2)]
    reuse_site = LinearIndices((6, 6))[CartesianIndex(2, 2)]
    create = LifecycleProcess(
        :create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                create_site, ((0, 0), (1, 0)); relation
            ),
            state = (activity_state => InitializeFrom(2.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (activity_state => Transform(activity + 1),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (
                activity_state => SplitConservatively(0.5; rounding = :exact),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :remove;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(4),
    )
    reuse = LifecycleProcess(
        :reuse;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            daughter;
            placement = SeedAt(reuse_site),
            state = (activity_state => InitializeFrom(5.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(5),
    )
    conflict_a = LifecycleProcess(
        :conflict_a;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            cell;
            state = (activity_state => Preserve(),),
            priority = 4,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(7),
    )
    conflict_b = LifecycleProcess(
        :conflict_b;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (activity_state => Preserve(),),
            priority = 4,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(7),
    )
    system = PottsSystem(
        name = :LifecycleSequential,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 6),
            cell,
            daughter,
            medium,
            relation,
            activity_state,
            create,
            transition,
            divide,
            remove,
            reuse,
            conflict_a,
            conflict_b,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [activity],
        independent_variables = [t],
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    @test executable.reports.lifecycle.cell_capacity == 6
    @test executable.reports.storage.max_cells == 6

    labels = zeros(Int, 6, 6)
    labels[2:5, 4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    runtime = _lifecycle_runtime(executable, initial)
    activity_handle = only(executable.reports.states).handle
    activity_values() = CorePotts.state_block(
        runtime.descriptor_state, activity_handle
    ).values

    @test length(runtime.cell_kinds) == 6
    @test length(runtime.cell_generations) == 6
    @test size(activity_values()) == (6,)
    @test runtime.lifecycle_workspace.planned_sites isa Matrix{Int32}

    _execute_lifecycle_at!(runtime, 1)
    @test count(!iszero, runtime.cell_kinds) == 2
    @test runtime.cell_generations[1:2] == UInt32[1, 1]
    @test activity_values()[1:2] == Float32[1, 2]
    _assert_lifecycle_recomputation(runtime)

    _execute_lifecycle_at!(runtime, 2)
    @test count(!iszero, runtime.cell_kinds) == 2
    @test activity_values()[1:2] == Float32[2, 3]
    _assert_lifecycle_recomputation(runtime)

    _execute_lifecycle_at!(runtime, 3)
    @test count(!iszero, runtime.cell_kinds) == 4
    @test sum(CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    )) == 6
    @test sum(activity_values()[1:4]) == 5
    _assert_lifecycle_recomputation(runtime)

    _execute_lifecycle_at!(runtime, 4)
    @test all(iszero, runtime.cell_kinds)
    @test all(runtime.ownership .<= 0)
    @test runtime.retired_cells == 4
    @test all(runtime.cell_generations[1:4] .== 1)
    _assert_lifecycle_recomputation(runtime)

    _execute_lifecycle_at!(runtime, 5)
    @test runtime.cell_kinds[1] != 0
    @test runtime.cell_generations[1] == 2
    @test activity_values()[1] == 5
    @test count(!iszero, runtime.cell_kinds) == 1
    _assert_lifecycle_recomputation(runtime)

    conflict_runtime = CorePotts.restore_program_checkpoint(
        executable.core_program, CorePotts.program_checkpoint(runtime)
    )
    conflict_before = CorePotts.program_snapshot(conflict_runtime)
    conflict_error = try
        _execute_lifecycle_at!(conflict_runtime, 7)
        nothing
    catch error
        error
    end
    @test conflict_error isa CorePotts.LifecycleConflictFailure
    @test conflict_runtime.ownership == conflict_before.ownership
    @test conflict_runtime.cell_kinds == conflict_before.cell_kinds
    @test conflict_runtime.cell_generations == conflict_before.cell_generations

    # A final accepted copy can expose the zero-volume transient; only the
    # synthesized RetireAtZero transaction consumes it, without advancing the
    # generation at retirement.
    retire_runtime = CorePotts.restore_program_checkpoint(
        executable.core_program, CorePotts.program_checkpoint(runtime)
    )
    occupied = findfirst(==(Int32(1)), vec(retire_runtime.ownership))
    @test occupied !== nothing
    site = CartesianIndices(retire_runtime.ownership)[occupied]
    source = CorePotts.tracker_source_view(
        retire_runtime.program, retire_runtime.ownership
    )
    CorePotts.commit_tracker_updates!(
        retire_runtime.trackers,
        retire_runtime.program.tracker_plan,
        source,
        site,
        Int32(1),
        Int32(0),
    )
    retire_runtime.ownership[site] = 0
    _execute_lifecycle_at!(retire_runtime, 6)
    @test retire_runtime.cell_kinds[1] == 0
    @test retire_runtime.cell_generations[1] == 2
end

@testset "built-in binary partition policies share one transaction path" begin
    cell = CellKind(:partition_cell; extinction = RetireAtZero())
    medium = MediumKind(:partition_medium)
    relation = SpatialRelation(:partition_relation; neighborhood = VonNeumann())
    anchor = CellBinding(:partition_anchor)
    geometries = (
        RandomPlane(draw = :partition_random),
        PrincipalAxisPlane(:major),
        PrincipalAxisPlane(:minor),
        SpecifiedNormalPlane((1.0, 0.0)),
    )
    divisions = map(enumerate(geometries)) do (cell_id, geometry)
        LifecycleProcess(
            Symbol(:partition_policy_, cell_id);
            domain = cells(cell),
            anchor,
            expression = anchor_value(anchor) == cell_id,
            effects = (Divide(
                anchor;
                geometry,
                relation,
                side = CanonicalSide(),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    system = PottsSystem(
        name = :PartitionPolicyConformance,
        statements = StatementSet((
            Lattice((8, 8); max_cells = 8),
            cell,
            medium,
            relation,
            divisions...,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 8, 8)
    labels[1:2, 1:2] .= 1
    labels[1:2, 5:6] .= 2
    labels[5:6, 1:2] .= 3
    labels[5:6, 5:6] .= 4
    runtime = _lifecycle_runtime(executable, PottsInitialState(
        ownership = LabelledCells(labels; cells = fill(cell, 4), medium)
    ))
    CorePotts.execute_lifecycle!(runtime)
    @test count(!iszero, runtime.cell_kinds) == 8
    @test all(>(0), CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    )[1:8])
    _assert_lifecycle_recomputation(runtime)
end

@testset "exact-fit and overflow capacity atomicity" begin
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    births = ntuple(2) do index
        LifecycleProcess(
            Symbol(:birth_, index);
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(index),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
    end
    function capacity_executable(max_cells)
        system = PottsSystem(
            name = Symbol(:Capacity_, max_cells),
            statements = StatementSet((
                Lattice((3, 3); max_cells),
                cell,
                medium,
                births...,
                Protocol(Sweep(); name = :main),
            )),
        )
        return compile(
            complete(system);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
    end
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, 3, 3); cells = [], medium
    ))
    exact = _lifecycle_runtime(capacity_executable(2), initial)
    site_count = length(exact.ownership)
    @test CorePotts.lifecycle_workspace_conforms(
        exact.lifecycle_workspace, exact.program.lifecycle_plan, site_count
    )
    conforming_planned_sites = exact.lifecycle_workspace.planned_sites
    exact.lifecycle_workspace.planned_sites = zeros(Int32, 1, 1)
    @test !CorePotts.lifecycle_workspace_conforms(
        exact.lifecycle_workspace, exact.program.lifecycle_plan, site_count
    )
    exact.lifecycle_workspace.planned_sites = conforming_planned_sites
    exact_cell_tables = (
        objectid(exact.cell_kinds),
        objectid(exact.cell_generations),
        length(exact.cell_kinds),
        length(exact.cell_generations),
    )
    exact_workspace_buffers = (
        objectid(exact.lifecycle_workspace.descriptor),
        objectid(exact.lifecycle_workspace.planned_sites),
        objectid(exact.lifecycle_workspace.partition_labels),
        objectid(exact.lifecycle_workspace.free_slots),
        size(exact.lifecycle_workspace.planned_sites),
        size(exact.lifecycle_workspace.partition_labels),
        length(exact.lifecycle_workspace.free_slots),
    )
    CorePotts.execute_lifecycle!(exact)
    @test count(!iszero, exact.cell_kinds) == 2
    @test exact_cell_tables == (
        objectid(exact.cell_kinds),
        objectid(exact.cell_generations),
        length(exact.cell_kinds),
        length(exact.cell_generations),
    )
    @test exact_workspace_buffers == (
        objectid(exact.lifecycle_workspace.descriptor),
        objectid(exact.lifecycle_workspace.planned_sites),
        objectid(exact.lifecycle_workspace.partition_labels),
        objectid(exact.lifecycle_workspace.free_slots),
        size(exact.lifecycle_workspace.planned_sites),
        size(exact.lifecycle_workspace.partition_labels),
        length(exact.lifecycle_workspace.free_slots),
    )

    overflow = _lifecycle_runtime(capacity_executable(1), initial)
    before = CorePotts.program_snapshot(overflow)
    error = try
        CorePotts.execute_lifecycle!(overflow)
        nothing
    catch caught
        caught
    end
    @test error isa CorePotts.CellCapacityFailure
    @test error.max_cells == 1
    @test overflow.lifecycle_workspace.status.code ==
        CorePotts.LifecycleStatusCellCapacity
    @test overflow.lifecycle_workspace.status.required == 2
    @test overflow.lifecycle_workspace.status.available == 1
    @test overflow.lifecycle_workspace.status.maximum == 1
    @test overflow.ownership == before.ownership
    @test overflow.cell_kinds == before.cell_kinds
    @test overflow.cell_generations == before.cell_generations
    @test CorePotts.program_tracker_values(overflow, Val(:cell_volume)) ==
        CorePotts.tracker_values(
            overflow.program.tracker_plan, before.trackers, Val(:cell_volume)
        )

    oversized_labels = zeros(Int, 3, 3)
    oversized_labels[1] = 1
    oversized_labels[2] = 2
    oversized_initial = PottsInitialState(ownership = LabelledCells(
        oversized_labels; cells = [cell, cell], medium
    ))
    initialization_error = try
        _lifecycle_runtime(capacity_executable(1), oversized_initial)
        nothing
    catch caught
        caught
    end
    @test initialization_error isa ArgumentError
    @test occursin("max_cells=1", sprint(showerror, initialization_error))

    generation_overflow = _lifecycle_runtime(capacity_executable(2), initial)
    generation_overflow.cell_generations[1] = typemax(UInt32)
    generation_before = CorePotts.program_snapshot(generation_overflow)
    generation_error = try
        CorePotts.execute_lifecycle!(generation_overflow)
        nothing
    catch caught
        caught
    end
    @test generation_error isa CorePotts.GenerationOverflowFailure
    @test generation_overflow.lifecycle_workspace.status.code ==
        CorePotts.LifecycleStatusGenerationOverflow
    @test generation_overflow.ownership == generation_before.ownership
    @test generation_overflow.cell_kinds == generation_before.cell_kinds
    @test generation_overflow.cell_generations ==
        generation_before.cell_generations
end

@testset "closed lifecycle status translation" begin
    @test isbitstype(CorePotts.LifecycleStatusPayload)
    payload(code; source = 3, secondary = 4, anchor = 5,
            detail = CorePotts.LifecycleDetailEvaluationError,
            required = 6, available = 7, maximum = 8) =
        CorePotts.LifecycleStatusPayload(
            code,
            Int32(source),
            Int32(secondary),
            Int32(anchor),
            detail,
            Int32(required),
            Int32(available),
            Int32(maximum),
        )
    cases = (
        payload(CorePotts.LifecycleStatusInadmissible) =>
            CorePotts.LifecycleInadmissibilityFailure,
        payload(CorePotts.LifecycleStatusConflict) =>
            CorePotts.LifecycleConflictFailure,
        payload(CorePotts.LifecycleStatusCellCapacity) =>
            CorePotts.CellCapacityFailure,
        payload(CorePotts.LifecycleStatusRelationshipCapacity) =>
            CorePotts.RelationshipCapacityFailure,
        payload(CorePotts.LifecycleStatusStaleGeneration) =>
            CorePotts.StaleGenerationFailure,
        payload(CorePotts.LifecycleStatusGenerationOverflow) =>
            CorePotts.GenerationOverflowFailure,
        payload(CorePotts.LifecycleStatusEvaluator) =>
            CorePotts.LifecycleEvaluatorFailure,
        payload(CorePotts.LifecycleStatusFootprint) =>
            CorePotts.LifecycleFootprintFailure,
        payload(CorePotts.LifecycleStatusInvariant) =>
            CorePotts.LifecycleInvariantFailure,
        payload(CorePotts.LifecycleStatusBackend) =>
            CorePotts.LifecycleBackendFailure,
    )
    for (status, expected) in cases
        before = status
        @test CorePotts._translate_lifecycle_status(status) isa expected
        @test status == before
    end
    @test CorePotts._translate_lifecycle_status(
        CorePotts.LifecycleStatusPayload()
    ) === nothing
end

@testset "public MCS ordering and checkpoint continuation" begin
    cell = CellKind(:continuation_cell; extinction = RetireAtZero())
    destination = CellKind(:continuation_destination; extinction = RetireAtZero())
    final_destination = CellKind(
        :continuation_final_destination; extinction = RetireAtZero()
    )
    medium = MediumKind(:continuation_medium)
    anchor = CellBinding(:continuation_anchor)
    transition = LifecycleProcess(
        :continuation_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            destination;
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition_again = LifecycleProcess(
        :continuation_transition_again;
        domain = cells(destination),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            final_destination;
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    remove = LifecycleProcess(
        :continuation_remove;
        domain = cells(final_destination),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    executable = compile(
        complete(PottsSystem(
            name = :LifecycleContinuation,
            statements = StatementSet((
                Lattice((3, 3); max_cells = 1),
                cell,
                destination,
                final_destination,
                medium,
                transition,
                transition_again,
                remove,
                Protocol(Sweep(); name = :main),
            )),
        ));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    initial = PottsInitialState(ownership = LabelledCells(
        ones(Int, 3, 3); cells = [cell], medium
    ))
    uninterrupted = _lifecycle_runtime(executable, initial; seed = 0x9a)
    CorePotts.advance_mcs!(uninterrupted)
    @test uninterrupted.mcs == 1
    @test count(!iszero, uninterrupted.cell_kinds) == 1
    saved = CorePotts.program_checkpoint(uninterrupted)
    resumed = CorePotts.restore_program_checkpoint(
        executable.core_program, saved
    )
    for _ in 1:2
        CorePotts.advance_mcs!(uninterrupted)
        CorePotts.advance_mcs!(resumed)
    end
    uninterrupted_snapshot = CorePotts.program_snapshot(uninterrupted)
    resumed_snapshot = CorePotts.program_snapshot(resumed)
    @test uninterrupted.mcs == resumed.mcs == 3
    @test uninterrupted_snapshot.ownership == resumed_snapshot.ownership
    @test uninterrupted_snapshot.cell_kinds == resumed_snapshot.cell_kinds
    @test uninterrupted_snapshot.cell_generations ==
        resumed_snapshot.cell_generations
    @test uninterrupted_snapshot.trackers.values ==
        resumed_snapshot.trackers.values
    @test uninterrupted_snapshot.relationships.banks ==
        resumed_snapshot.relationships.banks
    @test uninterrupted_snapshot.relationships.slots ==
        resumed_snapshot.relationships.slots
    @test uninterrupted.lifecycle_workspace.status.code ==
        resumed.lifecycle_workspace.status.code ==
        CorePotts.LifecycleStatusSuccess
end

@testset "lifecycle warm path is inferred and allocation-free" begin
    cell = CellKind(:allocation_cell; extinction = RetireAtZero())
    medium = MediumKind(:allocation_medium)
    birth = LifecycleProcess(
        :allocation_birth;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedAt(1),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    system = PottsSystem(
        name = :LifecycleAllocation,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 2),
            cell,
            medium,
            birth,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, 3, 3); cells = [], medium
    ))
    runtime() = _lifecycle_runtime(executable, initial; seed = 0x42)

    CorePotts.execute_lifecycle!(runtime())
    inferred_runtime = runtime()
    @test @inferred(CorePotts.execute_lifecycle!(inferred_runtime)) ===
        inferred_runtime
    measured_runtime = runtime()
    @test @allocated(CorePotts.execute_lifecycle!(measured_runtime)) == 0
end

@testset "lifecycle relationship consequences" begin
    cell = CellKind(:linked_cell; extinction = RetireAtZero())
    transitioned = CellKind(:transitioned_cell; extinction = RetireAtZero())
    medium = MediumKind(:linked_medium)
    links = RelationshipState(
        :links;
        endpoints = Undirected(cell, cell),
        capacity = 2,
        maximum_degree = 1,
        lifecycle = RejectEndpointRetirement(),
    )
    anchor = CellBinding(:linked_anchor)
    transition = LifecycleProcess(
        :unlinking_transition;
        domain = cells(cell),
        anchor,
        expression = anchor_value(anchor) == 1,
        effects = (Transition(
            anchor,
            transitioned;
            relationships = (links => RemoveIncompatible(),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    system = PottsSystem(
        name = :LifecycleRelationships,
        statements = StatementSet((
            Lattice((4, 4); max_cells = 3),
            cell,
            transitioned,
            medium,
            links,
            transition,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    labels[2, 3] = 2
    runtime = _lifecycle_runtime(
        executable,
        PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [cell, cell], medium
            ),
            values = [links => [(1, 2)]],
        ),
    )
    @test count(only(runtime.relationships).active) == 1
    CorePotts.execute_lifecycle!(runtime)
    @test count(only(runtime.relationships).active) == 0
    @test runtime.cell_kinds[1] != runtime.cell_kinds[2]
    @test CorePotts.validate_relationship_integrity(
        only(runtime.relationships),
        only(runtime.program.relationships),
        runtime.cell_kinds,
        runtime.cell_generations,
    ) === only(runtime.relationships)
end

@testset "closed relationship policy families share transaction authority" begin
    cell = CellKind(:policy_link_cell; extinction = RetireAtZero())
    transitioned = CellKind(:policy_link_destination; extinction = RetireAtZero())
    medium = MediumKind(:policy_link_medium)
    links = RelationshipState(
        :policy_links;
        endpoints = Undirected(cell, cell),
        capacity = 5,
        maximum_degree = 1,
        lifecycle = RejectEndpointRetirement(),
    )
    anchor = CellBinding(:policy_link_anchor)
    policies = (
        (1, RemoveCell(
            anchor;
            replacement = medium,
            relationships = (links => RejectWhileLinked(),),
            on_inadmissible = FilterInadmissible(),
        )),
        (3, RemoveCell(
            anchor;
            replacement = medium,
            relationships = (links => RemoveIncident(),),
            on_inadmissible = ErrorOnInadmissible(),
        )),
        (5, Transition(
            anchor,
            cell;
            relationships = (links => PreserveCompatible(),),
            on_inadmissible = ErrorOnInadmissible(),
        )),
        (7, Transition(
            anchor,
            transitioned;
            relationships = (links => RemoveIncompatible(),),
            on_inadmissible = ErrorOnInadmissible(),
        )),
        (9, Transition(
            anchor,
            transitioned;
            relationships = (links => RejectIncompatible(),),
            on_inadmissible = FilterInadmissible(),
        )),
    )
    processes = map(policies) do (cell_id, effect)
        LifecycleProcess(
            Symbol(:relationship_policy_, cell_id);
            domain = cells(cell),
            anchor,
            expression = anchor_value(anchor) == cell_id,
            effects = (effect,),
            cadence = AtMCS(1),
        )
    end
    system = PottsSystem(
        name = :RelationshipPolicyConformance,
        statements = StatementSet((
            Lattice((4, 4); max_cells = 10),
            cell,
            transitioned,
            medium,
            links,
            processes...,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 4, 4)
    labels[1:10] .= 1:10
    runtime = _lifecycle_runtime(
        executable,
        PottsInitialState(
            ownership = LabelledCells(
                labels; cells = fill(cell, 10), medium
            ),
            values = [links => [(1, 2), (3, 4), (5, 6), (7, 8), (9, 10)]],
        ),
    )
    CorePotts.execute_lifecycle!(runtime)
    @test count(only(runtime.relationships).active) == 3
    @test runtime.cell_kinds[1] != 0
    @test runtime.cell_kinds[3] == 0
    @test runtime.cell_kinds[5] != 0
    @test runtime.cell_kinds[7] != runtime.cell_kinds[5]
    @test runtime.cell_kinds[9] == runtime.cell_kinds[5]
    @test count(runtime.lifecycle_workspace.filtered) == 2
    _assert_lifecycle_recomputation(runtime)
end

@testset "closed state-policy families and addressed redraw" begin
    @variables t copy_value(t) preserve_reset(t) reset_both(t)
    @variables split_value(t) transform_value(t) redraw_value(t)
    cell = CellKind(:policy_cell; extinction = RetireAtZero())
    daughter = CellKind(:policy_daughter; extinction = RetireAtZero())
    medium = MediumKind(:policy_medium)
    relation = SpatialRelation(:policy_division; neighborhood = VonNeumann())
    variables = (
        copy_value,
        preserve_reset,
        reset_both,
        split_value,
        transform_value,
        redraw_value,
    )
    states = map(enumerate(variables)) do (index, variable)
        CellState(
            variable;
            name = Symbol(:policy_state_, index),
            initial = 10.0 * index,
            retirement = RetireTo(0.0),
            division = CopyToDaughters(),
        )
    end
    anchor = CellBinding(:policy_anchor)
    site = LinearIndices((5, 5))[CartesianIndex(2, 3)]
    create = LifecycleProcess(
        :policy_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                site, ((0, 0), (1, 0), (2, 0), (3, 0)); relation
            ),
            state = Tuple(
                state => InitializeFrom(10.0 * index)
                for (index, state) in enumerate(states)
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :policy_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (
                states[1] => Preserve(),
                states[2] => ResetTo(22.0),
                states[3] => Transform(reset_both + 3.0),
                states[4] => Preserve(),
                states[5] => Preserve(),
                states[6] => Preserve(),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :policy_divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (
                states[1] => CopyToDaughters(),
                states[2] => PreserveParentResetDaughter(2.0),
                states[3] => ResetBoth(3.0, 4.0),
                states[4] => SplitConservatively(0.25; rounding = :exact),
                states[5] => TransformDaughters(
                    transform_value + 1.0, transform_value + 2.0
                ),
                states[6] => RedrawDaughters(
                    Uniform(6.0, 7.0),
                    Uniform(8.0, 9.0);
                    parent_draw = :redraw_parent,
                    daughter_draw = :redraw_daughter,
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    system = PottsSystem(
        name = :LifecycleStatePolicies,
        statements = StatementSet((
            Lattice((5, 5); max_cells = 3),
            cell,
            daughter,
            medium,
            relation,
            states...,
            create,
            transition,
            divide,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = collect(variables),
        independent_variables = [t],
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, 5, 5); cells = [], medium
    ))
    function policy_result(seed)
        runtime = _lifecycle_runtime(executable, initial; seed)
        _execute_lifecycle_at!(runtime, 1)
        _execute_lifecycle_at!(runtime, 2)
        _execute_lifecycle_at!(runtime, 3)
        return runtime, Tuple(
            copy(CorePotts.state_block(
                runtime.descriptor_state, report.handle
            ).values)
            for report in executable.reports.states
        )
    end
    first_runtime, first_values = policy_result(0x81)
    replay_runtime, replay_values = policy_result(0x81)
    other_runtime, other_values = policy_result(0x82)
    @test first_runtime.ownership == replay_runtime.ownership
    @test first_values == replay_values
    @test first_values[1][1:2] == [10.0, 10.0]
    @test first_values[2][1:2] == [22.0, 2.0]
    @test first_values[3][1:2] == [3.0, 4.0]
    @test first_values[4][1:2] == [10.0, 30.0]
    @test first_values[5][1:2] == [51.0, 52.0]
    @test 6.0 < first_values[6][1] < 7.0
    @test 8.0 < first_values[6][2] < 9.0
    @test first_values[6][1:2] != other_values[6][1:2]
    @test first_runtime.cell_generations == other_runtime.cell_generations
end

@testset "filters inadmissible competitors before priority" begin
    cell = CellKind(:filter_cell; extinction = RetireAtZero())
    destination = CellKind(:filter_destination; extinction = RetireAtZero())
    medium = MediumKind(:filter_medium)
    relation = SpatialRelation(:filter_relation; neighborhood = VonNeumann())
    anchor = CellBinding(:filter_anchor)
    invalid_division = LifecycleProcess(
        :invalid_high_priority;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            priority = 100,
            on_inadmissible = FilterInadmissible(),
        ),),
    )
    valid_transition = LifecycleProcess(
        :valid_low_priority;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            destination;
            priority = -100,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    system = PottsSystem(
        name = :LifecycleFiltering,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 2),
            cell,
            destination,
            medium,
            relation,
            invalid_division,
            valid_transition,
            Protocol(
                Sweep();
                name = :main,
                lifecycle_conflicts = StableLifecyclePriority(),
            ),
        )),
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    runtime = _lifecycle_runtime(executable, PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    ))
    CorePotts.execute_lifecycle!(runtime)
    @test count(runtime.lifecycle_workspace.filtered) == 1
    destination_index = findfirst(
        entry -> entry.local_name === :filter_destination,
        executable.reports.kind_identities,
    )
    @test runtime.cell_kinds[1] == destination_index
end

@testset "lifecycle declaration permutation is semantically inert" begin
    function permutation_executable(reverse_order)
        cell = CellKind(:permutation_cell; extinction = RetireAtZero())
        medium = MediumKind(:permutation_medium)
        birth_a = LifecycleProcess(
            :permutation_birth_a;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
        birth_b = LifecycleProcess(
            :permutation_birth_b;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(2),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
        births = reverse_order ? (birth_b, birth_a) : (birth_a, birth_b)
        system = PottsSystem(
            name = :LifecyclePermutation,
            statements = StatementSet((
                Lattice((3, 3); max_cells = 2),
                cell,
                medium,
                births...,
                Protocol(Sweep(); name = :main),
            )),
        )
        return compile(
            complete(system);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        ), cell, medium
    end

    first_executable, _, first_medium =
        permutation_executable(false)
    second_executable, _, second_medium =
        permutation_executable(true)
    first_runtime = _lifecycle_runtime(
        first_executable,
        PottsInitialState(ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium = first_medium
        )),
    )
    second_runtime = _lifecycle_runtime(
        second_executable,
        PottsInitialState(ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium = second_medium
        )),
    )
    CorePotts.execute_lifecycle!(first_runtime)
    CorePotts.execute_lifecycle!(second_runtime)

    @test first_executable.reports.lifecycle.fingerprint ==
        second_executable.reports.lifecycle.fingerprint
    @test first_runtime.ownership == second_runtime.ownership
    @test first_runtime.cell_kinds == second_runtime.cell_kinds
    @test first_runtime.cell_generations == second_runtime.cell_generations
    @test first_runtime.trackers.values == second_runtime.trackers.values
    @test first_runtime.lifecycle_workspace.status.code ==
        second_runtime.lifecycle_workspace.status.code ==
        CorePotts.LifecycleStatusSuccess
end

@testset "conflict diagnostics are canonical under declaration permutation" begin
    function conflicting_executable(reverse_order)
        cell = CellKind(:canonical_conflict_cell; extinction = RetireAtZero())
        medium = MediumKind(:canonical_conflict_medium)
        birth_a = LifecycleProcess(
            :canonical_conflict_a;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
        birth_b = LifecycleProcess(
            :canonical_conflict_b;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
        births = reverse_order ? (birth_b, birth_a) : (birth_a, birth_b)
        executable = compile(
            complete(PottsSystem(
                name = :CanonicalConflictPermutation,
                statements = StatementSet((
                    Lattice((3, 3); max_cells = 2),
                    cell,
                    medium,
                    births...,
                    Protocol(
                        Sweep();
                        name = :main,
                        lifecycle_conflicts = RejectLifecycleAmbiguity(),
                    ),
                )),
            ));
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
        initial = PottsInitialState(ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium
        ))
        return executable, _lifecycle_runtime(executable, initial)
    end
    first_executable, first_runtime = conflicting_executable(false)
    second_executable, second_runtime = conflicting_executable(true)
    first_before = CorePotts.program_snapshot(first_runtime)
    second_before = CorePotts.program_snapshot(second_runtime)
    first_error = try
        CorePotts.execute_lifecycle!(first_runtime)
        nothing
    catch error
        error
    end
    second_error = try
        CorePotts.execute_lifecycle!(second_runtime)
        nothing
    catch error
        error
    end
    @test first_error isa CorePotts.LifecycleConflictFailure
    @test second_error isa CorePotts.LifecycleConflictFailure
    @test (first_error.first_source, first_error.second_source, first_error.anchor) ==
        (second_error.first_source, second_error.second_source, second_error.anchor)
    @test first_executable.reports.lifecycle.fingerprint ==
        second_executable.reports.lifecycle.fingerprint
    @test first_runtime.ownership == first_before.ownership
    @test second_runtime.ownership == second_before.ownership
    @test first_runtime.lifecycle_workspace.status ==
        second_runtime.lifecycle_workspace.status
end
