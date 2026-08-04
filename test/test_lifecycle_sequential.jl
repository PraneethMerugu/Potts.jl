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

function _lifecycle_workspace_slices(expression)
    slices = Tuple{Int32, Int32}[]
    if expression isa CorePotts.OperationExpression
        operation = expression.operation
        operation isa CorePotts.LifecycleWorkspaceOperation && push!(
            slices, (operation.offset, operation.maximum)
        )
        for argument in expression.arguments
            append!(slices, _lifecycle_workspace_slices(argument))
        end
    elseif expression isa CorePotts.ContextExpression
        operation = expression.operation
        operation isa CorePotts.LifecycleWorkspaceOperation && push!(
            slices, (operation.offset, operation.maximum)
        )
    end
    return slices
end

function _lifecycle_evaluator(storage, index)
    location = storage.slots[Int(index)]
    return storage.banks[Int(location.bank)][Int(location.slot)]
end

function _lifecycle_state_rule(storage, index)
    location = storage.slots[Int(index)]
    return storage.banks[Int(location.bank)][Int(location.slot)]
end

function _lifecycle_workspace_with(workspace, name::Symbol, replacement)
    names = fieldnames(typeof(workspace))
    values = ntuple(length(names)) do index
        names[index] === name ? replacement : getfield(workspace, index)
    end
    return CorePotts.LifecycleWorkspace(values...)
end

function _lifecycle_relationship_values(storage)
    return Tuple(begin
        state = storage[slot]
        (
            active = copy(state.active),
            endpoint_a = copy(state.endpoint_a),
            endpoint_b = copy(state.endpoint_b),
            generation_a = copy(state.generation_a),
            generation_b = copy(state.generation_b),
            payload = map(copy, state.payload),
            degree = copy(state.degree),
            incident_edges = copy(state.incident_edges),
        )
    end for slot in eachindex(storage))
end

@testset "conservative split fractions are construction-safe" begin
    function split_error(fraction)
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
                    state => SplitConservatively(fraction; rounding = :exact),
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
        return try
            complete(system)
            nothing
        catch caught
            caught
        end
    end
    for fraction in (1.5, 0.5u"μm")
        error = split_error(fraction)
        @test error isa PottsToolkit.PottsValidationError
        @test only(error.diagnostics).kind ===
            :invalid_lifecycle_split_fraction
    end
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
                    external_lifecycle_transform(Symbolics.Num(2)) +
                    external_lifecycle_transform(Symbolics.Num(3))
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    invalid_create = LifecycleProcess(
        :external_invalid_create;
        domain = model(),
        expression = external_lifecycle_trigger(Symbolics.Num(1)),
        effects = (CreateCell(
            cell;
            placement = external_lifecycle_placement(Symbolics.Num(5)),
            state = (
                state => InitializeFrom(
                    external_lifecycle_transform(Symbolics.Num(-1))
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
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
            invalid_create,
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
    @test adapted_plan.relations.data isa LifecycleProbeArray
    @test adapted_plan.relations.offsets isa LifecycleProbeArray
    @test !(:fingerprint in fieldnames(typeof(adapted_plan)))
    @test maximum(
        descriptor.state_workspace_maximum for descriptor in adapted_plan.descriptors
    ) == 2
    two_slice_descriptor = only(filter(
        descriptor -> descriptor.state_workspace_maximum == 2,
        adapted_plan.descriptors,
    ))
    two_slice_rule = _lifecycle_state_rule(
        adapted_plan.state_rules,
        two_slice_descriptor.state_rule_offset,
    )
    two_slice_evaluator = _lifecycle_evaluator(
        adapted_plan.evaluators, two_slice_rule.evaluator_a
    )
    @test sort(_lifecycle_workspace_slices(two_slice_evaluator.expression)) ==
        [(Int32(0), Int32(1)), (Int32(1), Int32(1))]
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    runtime = _lifecycle_runtime(
        executable,
        PottsInitialState(ownership = LabelledCells(
            labels; cells = [cell], medium
        )),
    )
    adapted_workspace = CorePotts.Adapt.adapt(
        LifecycleProbeAdaptor(), runtime.lifecycle_workspace
    )
    @test adapted_workspace.partition_labels isa LifecycleProbeArray
    @test adapted_workspace.partition_scratch isa LifecycleProbeArray
    @test adapted_workspace.policy_workspace isa LifecycleProbeArray

    checkerboard_executable = compile(
        complete(system);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    checkerboard_runtime = _lifecycle_runtime(
        checkerboard_executable,
        PottsInitialState(ownership = LabelledCells(
            labels; cells = [cell], medium
        )),
    )
    backend_state = checkerboard_runtime.engine_workspace.state
    CorePotts.enqueue_lifecycle_backend_index!(backend_state)
    backend_lifecycle = backend_state.lifecycle_workspace
    backend_status = CorePotts.lifecycle_backend_status(backend_lifecycle)
    @test backend_status == CorePotts.LifecycleStatusPayload()
    @test backend_lifecycle.cell_site_counts == Int32[4, 0, 0, 0]
    @test backend_lifecycle.cell_sites[1:4] == Int32[14, 15, 16, 17]
    @test count(backend_lifecycle.active) == 1
    @test only(backend_lifecycle.anchor[backend_lifecycle.active]) == 1

    lookups = LifecycleOperationFixtures.CALLABLE_LOOKUPS[]
    _execute_lifecycle_at!(runtime, 1)
    @test count(!iszero, runtime.cell_kinds) == 2
    @test sort(filter(!iszero, CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    ))) == Int32[2, 2]
    saved = CorePotts.program_checkpoint(runtime)
    resumed = CorePotts.restore_program_checkpoint(
        executable.core_program, saved
    )
    measured = CorePotts.restore_program_checkpoint(
        executable.core_program, saved
    )
    runtime.mcs = resumed.mcs = measured.mcs = 1
    CorePotts.execute_lifecycle!(runtime)
    @test @inferred(CorePotts.execute_lifecycle!(resumed)) === resumed
    @test @allocated(CorePotts.execute_lifecycle!(measured)) == 0
    runtime.mcs = resumed.mcs = measured.mcs = 2
    @test count(!iszero, runtime.cell_kinds) == 3
    @test runtime.ownership == resumed.ownership == measured.ownership
    @test runtime.cell_kinds == resumed.cell_kinds == measured.cell_kinds
    @test runtime.cell_generations ==
        resumed.cell_generations == measured.cell_generations
    state_handle = only(executable.reports.states).handle
    @test CorePotts.state_block(
        runtime.descriptor_state, state_handle
    ).values[3] == 5
    @test CorePotts.state_block(
        runtime.descriptor_state, state_handle
    ).values == CorePotts.state_block(
        resumed.descriptor_state, state_handle
    ).values
    before_failure = CorePotts.program_snapshot(runtime)
    failure = try
        _execute_lifecycle_at!(runtime, 3)
        nothing
    catch error
        error
    end
    @test failure isa CorePotts.LifecycleEvaluatorFailure
    @test failure.reason === :nonfinite_result
    @test runtime.ownership == before_failure.ownership
    @test runtime.cell_kinds == before_failure.cell_kinds
    @test runtime.cell_generations == before_failure.cell_generations
    @test runtime.trackers.values == before_failure.trackers.values
    @test CorePotts.state_block(
        runtime.descriptor_state, state_handle
    ).values == CorePotts.state_block(
        before_failure.descriptor_state, state_handle
    ).values
    @test _lifecycle_relationship_values(runtime.relationships) ==
        _lifecycle_relationship_values(before_failure.relationships)
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
    @test executable.reports.lifecycle.division_variants == 4
    @test count_ones(
        executable.core_program.lifecycle_plan.division_variant_mask
    ) == 4
    labels = zeros(Int, 8, 8)
    labels[1:2, 1:2] .= 1
    labels[1:2, 5:6] .= 2
    labels[5:6, 1:2] .= 3
    labels[5:6, 5:6] .= 4
    runtime = _lifecycle_runtime(executable, PottsInitialState(
        ownership = LabelledCells(labels; cells = fill(cell, 4), medium)
    ))
    @test @allocated(CorePotts.execute_lifecycle!(runtime)) == 0
    @test count(!iszero, runtime.cell_kinds) == 8
    @test all(>(0), CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    )[1:8])
    _assert_lifecycle_recomputation(runtime)
end

@testset "exact-fit and overflow capacity atomicity" begin
    @variables capacity_time capacity_value(capacity_time)
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    state = CellState(
        capacity_value;
        initial = 0,
        retirement = RetireTo(0),
        division = CopyToDaughters(),
    )
    links = RelationshipState(
        :capacity_links;
        endpoints = Undirected(cell, cell),
        capacity = 2,
        maximum_degree = 2,
        lifecycle = RejectEndpointRetirement(),
    )
    births = ntuple(2) do index
        LifecycleProcess(
            Symbol(:birth_, index);
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(index),
                state = (state => InitializeFrom(index),),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
        )
    end
    executables = Dict{Int, Any}()
    function capacity_executable(max_cells)
        haskey(executables, max_cells) && return executables[max_cells]
        system = PottsSystem(
            name = Symbol(:Capacity_, max_cells),
            statements = StatementSet((
                Lattice((3, 3); max_cells),
                cell,
                medium,
                state,
                links,
                births...,
                Protocol(Sweep(); name = :main),
            )),
            unknowns = [capacity_value],
            independent_variables = [capacity_time],
        )
        executable = compile(
            complete(system);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
        executables[max_cells] = executable
        return executable
    end
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, 3, 3); cells = [], medium
    ))
    exact = _lifecycle_runtime(capacity_executable(2), initial)
    site_count = length(exact.ownership)
    @test CorePotts.lifecycle_workspace_conforms(
        exact.lifecycle_workspace, exact.program.lifecycle_plan, site_count
    )
    conforming_workspace = exact.lifecycle_workspace
    exact.lifecycle_workspace = _lifecycle_workspace_with(
        conforming_workspace, :planned_sites, zeros(Int32, 1, 1)
    )
    @test !CorePotts.lifecycle_workspace_conforms(
        exact.lifecycle_workspace, exact.program.lifecycle_plan, site_count
    )
    exact.lifecycle_workspace = conforming_workspace
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
    overflow_status = CorePotts.lifecycle_workspace_status(
        overflow.lifecycle_workspace
    )
    @test overflow_status.code ==
        CorePotts.LifecycleStatusCellCapacity
    @test overflow_status.required == 2
    @test overflow_status.available == 1
    @test overflow_status.maximum == 1
    @test overflow.ownership == before.ownership
    @test overflow.cell_kinds == before.cell_kinds
    @test overflow.cell_generations == before.cell_generations
    state_handle = only(filter(
        entry -> entry.schema.identity.name === :capacity_value,
        overflow.program.descriptor_plan.state_layout.entries,
    )).handle
    @test CorePotts.state_block(
        overflow.descriptor_state, state_handle
    ).values == CorePotts.state_block(
        before.descriptor_state, state_handle
    ).values
    @test _lifecycle_relationship_values(overflow.relationships) ==
        _lifecycle_relationship_values(before.relationships)
    @test overflow.relationships.slots == before.relationships.slots
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
    @test CorePotts.lifecycle_workspace_status(
        generation_overflow.lifecycle_workspace
    ).code ==
        CorePotts.LifecycleStatusGenerationOverflow
    @test generation_overflow.ownership == generation_before.ownership
    @test generation_overflow.cell_kinds == generation_before.cell_kinds
    @test generation_overflow.cell_generations ==
        generation_before.cell_generations

    footprint = _lifecycle_runtime(capacity_executable(1), initial)
    footprint_before = CorePotts.program_snapshot(footprint)
    footprint.lifecycle_workspace = _lifecycle_workspace_with(
        footprint.lifecycle_workspace, :descriptor, Int32[]
    )
    footprint_error = try
        CorePotts.execute_lifecycle!(footprint)
        nothing
    catch caught
        caught
    end
    @test footprint_error isa CorePotts.LifecycleFootprintFailure
    @test CorePotts.lifecycle_workspace_status(
        footprint.lifecycle_workspace
    ).detail ===
        CorePotts.LifecycleDetailRequestBoundExceeded
    @test footprint.ownership == footprint_before.ownership
    @test footprint.cell_kinds == footprint_before.cell_kinds
    @test footprint.cell_generations == footprint_before.cell_generations

    invariant = _lifecycle_runtime(capacity_executable(1), initial)
    invariant.ownership[1] = 2
    invariant_before = (
        ownership = copy(invariant.ownership),
        cell_kinds = copy(invariant.cell_kinds),
        cell_generations = copy(invariant.cell_generations),
        trackers = deepcopy(invariant.trackers.values),
    )
    invariant_error = try
        CorePotts.execute_lifecycle!(invariant)
        nothing
    catch caught
        caught
    end
    @test invariant_error isa CorePotts.LifecycleInvariantFailure
    @test CorePotts.lifecycle_workspace_status(
        invariant.lifecycle_workspace
    ).detail ===
        CorePotts.LifecycleDetailOwnershipExceedsCellCapacity
    @test invariant.ownership == invariant_before.ownership
    @test invariant.cell_kinds == invariant_before.cell_kinds
    @test invariant.cell_generations == invariant_before.cell_generations
    @test invariant.trackers.values == invariant_before.trackers
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
    for status in (
            payload(CorePotts.LifecycleStatusInadmissible),
            payload(CorePotts.LifecycleStatusConflict),
            payload(CorePotts.LifecycleStatusCellCapacity),
            payload(CorePotts.LifecycleStatusRelationshipCapacity),
            payload(CorePotts.LifecycleStatusGenerationOverflow),
            payload(
                CorePotts.LifecycleStatusEvaluator;
                detail = CorePotts.LifecycleDetailNonfiniteResult,
            ),
            payload(
                CorePotts.LifecycleStatusEvaluator;
                detail = CorePotts.LifecycleDetailSplitFractionOutOfBounds,
            ),
            payload(
                CorePotts.LifecycleStatusEvaluator;
                detail = CorePotts.LifecycleDetailStateValueInvalid,
            ),
        )
        @test CorePotts.lifecycle_status_is_expected(status)
    end
    for status in (
            payload(CorePotts.LifecycleStatusStaleGeneration),
            payload(CorePotts.LifecycleStatusFootprint),
            payload(CorePotts.LifecycleStatusInvariant),
            payload(CorePotts.LifecycleStatusBackend),
            payload(
                CorePotts.LifecycleStatusEvaluator;
                detail = CorePotts.LifecycleDetailEvaluationError,
            ),
            payload(
                CorePotts.LifecycleStatusEvaluator;
                detail = CorePotts.LifecycleDetailTriggerNotBoolean,
            ),
        )
        @test !CorePotts.lifecycle_status_is_expected(status)
    end
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
    @test CorePotts.lifecycle_workspace_status(
        uninterrupted.lifecycle_workspace
    ).code == CorePotts.lifecycle_workspace_status(
        resumed.lifecycle_workspace
    ).code ==
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
                    cell_volume(anchor_value(anchor)),
                    cell_volume(anchor_value(anchor)) + 10.0,
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
    # State transforms see the immutable request-local planned-after tracker
    # view: the four-site source has already become two two-site descendants.
    @test first_values[5][1:2] == [2.0, 12.0]
    @test 6.0 < first_values[6][1] < 7.0
    @test 8.0 < first_values[6][2] < 9.0
    @test first_values[6][1:2] != other_values[6][1:2]
    @test first_runtime.cell_generations == other_runtime.cell_generations
end

@testset "state policies observe only their request-local planned result" begin
    @variables t payload(t)
    dividing = CellKind(:private_plan_dividing; extinction = RetireAtZero())
    removed = CellKind(:private_plan_removed; extinction = RetireAtZero())
    medium = MediumKind(:private_plan_medium)
    relation = SpatialRelation(
        :private_plan_division; neighborhood = VonNeumann()
    )
    state = CellState(
        payload;
        initial = 7.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:private_plan_anchor)
    divide = LifecycleProcess(
        :private_plan_divide;
        domain = cells(dividing),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (state => TransformDaughters(
                cell_volume(Symbolics.Num(2)),
                cell_volume(Symbolics.Num(2)),
            ),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    remove = LifecycleProcess(
        :private_plan_remove;
        domain = cells(removed),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = :RequestPrivateLifecycleState,
        statements = StatementSet((
            Lattice((7, 7); max_cells = 3),
            dividing,
            removed,
            medium,
            relation,
            state,
            divide,
            remove,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [payload],
        independent_variables = [t],
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 7, 7)
    labels[2:5, 2] .= 1
    labels[2:3, 6] .= 2
    runtime = _lifecycle_runtime(
        executable,
        PottsInitialState(ownership = LabelledCells(
            labels; cells = [dividing, removed], medium
        )),
    )

    CorePotts.execute_lifecycle!(runtime)

    values = CorePotts.state_block(
        runtime.descriptor_state, only(executable.reports.states).handle
    ).values
    @test values[1] == 2.0
    @test values[2] == 0.0
    @test values[3] == 2.0
    @test CorePotts.program_tracker_value(runtime, Val(:cell_volume), 2) == 0
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
    filtered_request = only(findall(runtime.lifecycle_workspace.filtered))
    @test runtime.lifecycle_workspace.filtered_detail[filtered_request] ===
        CorePotts.LifecycleDetailPartitionEmptyDescendant
    @test runtime.lifecycle_workspace.anchor[filtered_request] == 1
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
    @test CorePotts.lifecycle_workspace_status(
        first_runtime.lifecycle_workspace
    ).code == CorePotts.lifecycle_workspace_status(
        second_runtime.lifecycle_workspace
    ).code ==
        CorePotts.LifecycleStatusSuccess
end

@testset "priority resolves direct conflicts without transitive suppression" begin
    function chain_runtime(order)
        cell = CellKind(:chain_cell; extinction = RetireAtZero())
        medium = MediumKind(:chain_medium)
        starts = (1, 2, 3)
        priorities = (10, 0, 10)
        names = (:chain_left, :chain_bridge, :chain_right)
        births = ntuple(3) do index
            LifecycleProcess(
                names[index];
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = external_lifecycle_placement(
                        Symbolics.Num(starts[index])
                    ),
                    priority = priorities[index],
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
            )
        end
        system = PottsSystem(
            name = :DirectConflictChain,
            statements = StatementSet((
                Lattice((2, 3); max_cells = 3),
                cell,
                medium,
                (births[index] for index in order)...,
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
        initial = PottsInitialState(ownership = LabelledCells(
            zeros(Int, 2, 3); cells = [], medium
        ))
        return executable, _lifecycle_runtime(executable, initial)
    end

    first_executable, first_runtime = chain_runtime((1, 2, 3))
    second_executable, second_runtime = chain_runtime((3, 2, 1))
    CorePotts.execute_lifecycle!(first_runtime)
    CorePotts.execute_lifecycle!(second_runtime)
    owners = vec(first_runtime.ownership)[1:4]
    @test owners[1] == owners[2] > 0
    @test owners[3] == owners[4] > 0
    @test owners[1] != owners[3]
    @test first_runtime.ownership == second_runtime.ownership
    @test first_runtime.cell_kinds == second_runtime.cell_kinds
    @test count(first_runtime.lifecycle_workspace.selected) == 2
    @test first_executable.reports.lifecycle.fingerprint ==
        second_executable.reports.lifecycle.fingerprint
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
    @test CorePotts.lifecycle_workspace_status(
        first_runtime.lifecycle_workspace
    ) == CorePotts.lifecycle_workspace_status(
        second_runtime.lifecycle_workspace
    )
end
