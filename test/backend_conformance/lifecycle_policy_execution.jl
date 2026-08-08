using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

if !isdefined(Main, :LifecycleOperationFixtures)
    include("../fixtures/LifecycleOperationFixtures.jl")
end
using .LifecycleOperationFixtures

function _direct_lifecycle_runtimes(completed, initial, device_array; seed)
    reference_executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    device_executable = compile(
        completed;
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    reference_initial = PottsToolkit._core_initial_state(
        reference_executable, initial, UInt64(seed), UInt32(1)
    )
    device_initial = PottsToolkit._core_initial_state(
        device_executable, initial, UInt64(seed), UInt32(1)
    )
    reference = CorePotts.initialize_program(
        reference_executable.core_program,
        reference_initial,
        reference_executable.core_program.parameter_defaults,
        UInt64(seed),
        UInt32(1),
    )
    host_candidate = CorePotts.initialize_program(
        device_executable.core_program,
        device_initial,
        device_executable.core_program.parameter_defaults,
        UInt64(seed),
        UInt32(1),
    )
    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, host_candidate.engine_workspace
    )
    return reference_executable, reference, device_executable, workspace
end

function _enqueue_direct_lifecycle_sequence!(reference, workspace, boundaries)
    for boundary in boundaries
        reference.mcs = boundary - 1
        CorePotts.execute_lifecycle!(reference)
        reference.mcs = boundary
        state = CorePotts._checkerboard_state_at_mcs(
            workspace.state, boundary - 1
        )
        CorePotts.enqueue_lifecycle_backend_index!(state)
    end
    backend = CorePotts.KernelAbstractions.get_backend(
        workspace.state.ownership
    )
    CorePotts.KernelAbstractions.synchronize(backend)
    return workspace
end

function _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    state = workspace.state
    @test only(to_host(state.lifecycle_workspace.status)).code ===
        CorePotts.ProgramStatusSuccess
    @test to_host(state.ownership) == reference.ownership
    @test to_host(state.cell_kinds) == reference.cell_kinds
    @test to_host(state.cell_generations) == reference.cell_generations
    @test CorePotts.Adapt.adapt(Array, state.trackers).values ==
        reference.trackers.values
    device_relationships = CorePotts.Adapt.adapt(Array, state.relationships)
    @test device_relationships.slots == reference.relationships.slots
    for slot in eachindex(reference.relationships)
        device_relationship = device_relationships[slot]
        reference_relationship = reference.relationships[slot]
        @test device_relationship.active == reference_relationship.active
        @test device_relationship.endpoint_a == reference_relationship.endpoint_a
        @test device_relationship.endpoint_b == reference_relationship.endpoint_b
        @test device_relationship.generation_a == reference_relationship.generation_a
        @test device_relationship.generation_b == reference_relationship.generation_b
        @test device_relationship.payload == reference_relationship.payload
        @test device_relationship.degree == reference_relationship.degree
        @test device_relationship.incident_edges ==
            reference_relationship.incident_edges
    end
    device_descriptor_state = CorePotts.Adapt.adapt(
        Array, state.descriptor_state
    )
    @test map(bank -> bank.values, device_descriptor_state.banks) ==
        map(bank -> bank.values, reference.descriptor_state.banks)
    return nothing
end

function _state_policy_completed_system()
    @variables policy_time
    @variables copy_value(policy_time) preserve_reset(policy_time)
    @variables reset_both(policy_time) split_value(policy_time)
    @variables transform_value(policy_time) redraw_value(policy_time)
    cell = CellKind(:policy_cell; extinction = RetireAtZero())
    daughter = CellKind(:policy_daughter; extinction = RetireAtZero())
    medium = MediumKind(:policy_medium)
    relation = SpatialRelation(
        :policy_division; neighborhood = VonNeumann()
    )
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
            initial = Float32(10 * index),
            retirement = RetireTo(0.0f0),
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
                state => InitializeFrom(Float32(10 * index))
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
                states[2] => ResetTo(22.0f0),
                states[3] => Transform(reset_both + 3.0f0),
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
            geometry = SpecifiedNormalPlane((1.0f0, 0.0f0)),
            relation,
            side = CanonicalSide(),
            parent_kind = PreserveKind(),
            daughter_kind = SetKind(daughter),
            state = (
                states[1] => CopyToDaughters(),
                states[2] => PreserveParentResetDaughter(2.0f0),
                states[3] => ResetBoth(3.0f0, 4.0f0),
                states[4] => SplitConservatively(
                    0.25f0; rounding = :exact
                ),
                states[5] => TransformDaughters(
                    cell_volume(anchor_value(anchor)),
                    cell_volume(anchor_value(anchor)) + 10.0f0,
                ),
                states[6] => RedrawDaughters(
                    Uniform(6.0f0, 7.0f0),
                    Uniform(8.0f0, 9.0f0);
                    parent_draw = :redraw_parent,
                    daughter_draw = :redraw_daughter,
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :policy_remove;
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
    system = PottsSystem(
        name = :LifecycleStatePolicyBackendFixture,
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
            remove,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = collect(variables),
        independent_variables = [policy_time],
    )
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, 5, 5); cells = [], medium
    ))
    return complete(system), initial
end

function run_lifecycle_state_policy_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    completed, initial = _state_policy_completed_system()
    _, reference, executable, workspace = _direct_lifecycle_runtimes(
        completed, initial, device_array; seed = 0x81
    )
    @test executable.reports.lifecycle.state_action_pairs == 12
    _enqueue_direct_lifecycle_sequence!(reference, workspace, 1:4)
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    @test all(iszero, reference.cell_kinds)
    for entry in reference.program.descriptor_plan.state_layout.entries
        @test all(iszero, CorePotts.state_block(
            reference.descriptor_state, entry.handle
        ).values[1:2])
    end
    return (backend = backend_name, boundaries = 4, active_cells = 0)
end

function _planned_tracker_completed_system()
    @variables tracker_time planned_tracker_value(tracker_time)
    cell = CellKind(:tracker_cell; extinction = RetireAtZero())
    medium = MediumKind(:tracker_medium)
    surface = SpatialRelation(:surface; neighborhood = VonNeumann())
    state = CellState(
        planned_tracker_value;
        name = :planned_tracker_state,
        initial = 0.0f0,
        retirement = RetireTo(0.0f0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:tracker_anchor)
    planned_value = cell_volume(anchor_value(anchor)) +
                    cell_surface(anchor) + cell_elongation(anchor)
    divide = LifecycleProcess(
        :tracker_divide;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0f0, 0.0f0)),
            relation = surface,
            side = CanonicalSide(),
            state = (state => TransformDaughters(
                planned_value, planned_value + 10.0f0
            ),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = :LifecyclePlannedTrackerFixture,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 2),
            cell,
            medium,
            surface,
            state,
            divide,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [planned_tracker_value],
        independent_variables = [tracker_time],
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return complete(system), initial
end

function run_lifecycle_planned_tracker_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    completed, initial = _planned_tracker_completed_system()
    _, reference, _, workspace = _direct_lifecycle_runtimes(
        completed, initial, device_array; seed = 0x91
    )
    _enqueue_direct_lifecycle_sequence!(reference, workspace, 1:1)
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    entry = only(reference.program.descriptor_plan.state_layout.entries)
    values = CorePotts.state_block(
        reference.descriptor_state, entry.handle
    ).values
    @test values[1] == 10.0f0
    @test values[2] == 20.0f0
    return (
        backend = backend_name,
        parent = values[1],
        daughter = values[2],
    )
end

function _partition_policy_completed_system()
    cell = CellKind(:partition_cell; extinction = RetireAtZero())
    medium = MediumKind(:partition_medium)
    relation = SpatialRelation(
        :partition_relation; neighborhood = VonNeumann()
    )
    anchor = CellBinding(:partition_anchor)
    geometries = (
        RandomPlane(draw = :partition_random),
        PrincipalAxisPlane(:major),
        PrincipalAxisPlane(:minor),
        SpecifiedNormalPlane((1.0f0, 0.0f0)),
    )
    variants = Tuple(
        (geometry, side)
        for geometry in geometries
        for side in (CanonicalSide(), StableRandomSide(:partition_side))
    )
    divisions = map(enumerate(variants)) do (cell_id, variant)
        geometry, side = variant
        LifecycleProcess(
            Symbol(:partition_policy_, cell_id);
            domain = cells(cell),
            anchor,
            expression = anchor_value(anchor) == cell_id,
            effects = (Divide(
                anchor;
                geometry,
                relation,
                side,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    system = PottsSystem(
        name = :LifecyclePartitionPolicyBackendFixture,
        statements = StatementSet((
            Lattice((12, 12); max_cells = 16),
            cell,
            medium,
            relation,
            divisions...,
            Protocol(Sweep(); name = :main),
        )),
    )
    labels = zeros(Int, 12, 12)
    origins = (
        (1, 1), (1, 5), (1, 9), (5, 1),
        (5, 5), (5, 9), (9, 1), (9, 5),
    )
    for (cell_id, (row, column)) in enumerate(origins)
        labels[row:(row + 1), column:(column + 1)] .= cell_id
    end
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = fill(cell, length(origins)), medium
    ))
    return complete(system), initial
end

function run_lifecycle_partition_policy_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    completed, initial = _partition_policy_completed_system()
    _, reference, executable, workspace = _direct_lifecycle_runtimes(
        completed, initial, device_array; seed = 0x82
    )
    @test count_ones(
        executable.core_program.lifecycle_plan.division_variant_mask
    ) == 8
    _enqueue_direct_lifecycle_sequence!(reference, workspace, (1,))
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    @test count(!iszero, reference.cell_kinds) == 16
    return (backend = backend_name, variants = 8, active_cells = 16)
end

function _relationship_policy_completed_system()
    cell = CellKind(:policy_link_cell; extinction = RetireAtZero())
    transitioned = CellKind(
        :policy_link_destination; extinction = RetireAtZero()
    )
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
        name = :LifecycleRelationshipPolicyBackendFixture,
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
    labels = zeros(Int, 4, 4)
    labels[1:10] .= 1:10
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = fill(cell, 10), medium
        ),
        values = [links => [(1, 2), (3, 4), (5, 6), (7, 8), (9, 10)]],
    )
    return complete(system), initial
end

function run_lifecycle_relationship_policy_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    completed, initial = _relationship_policy_completed_system()
    _, reference, _, workspace = _direct_lifecycle_runtimes(
        completed, initial, device_array; seed = 0x83
    )
    _enqueue_direct_lifecycle_sequence!(reference, workspace, (1,))
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    @test count(only(reference.relationships).active) == 3
    @test count(reference.lifecycle_workspace.filtered) == 2
    return (backend = backend_name, active_relationships = 3, filtered = 2)
end

function run_lifecycle_retirement_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    cell = CellKind(:retirement_cell; extinction = RetireAtZero())
    medium = MediumKind(:retirement_medium)
    system = PottsSystem(
        name = :LifecycleRetirementBackendFixture,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 2),
            cell,
            medium,
            Protocol(Sweep(); name = :main),
        )),
    )
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    completed = complete(system)
    _, reference, _, host_workspace = _direct_lifecycle_runtimes(
        completed, initial, Array; seed = 0x84
    )
    host_candidate_state = host_workspace.state
    for state in (reference, host_candidate_state)
        occupied = findfirst(==(Int32(1)), vec(state.ownership))
        @test occupied !== nothing
        site = CartesianIndices(state.ownership)[occupied]
        source = CorePotts.tracker_source_view(
            state.program, state.ownership
        )
        CorePotts.commit_tracker_updates!(
            state.trackers,
            state.program.tracker_plan,
            source,
            site,
            Int32(1),
            Int32(0),
        )
        state.ownership[site] = Int32(0)
    end
    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, host_workspace
    )
    _enqueue_direct_lifecycle_sequence!(reference, workspace, (1,))
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    @test all(iszero, reference.cell_kinds)
    @test reference.retired_cells == 1
    statistics = to_host(workspace.state.lifecycle_control.statistics)
    @test statistics[CorePotts._PROGRAM_STAT_RETIRED] == 1
    return (backend = backend_name, retired = 1)
end

function _forbid_extinction_fixture()
    cell = CellKind(:persistent_cell; extinction = ForbidExtinction())
    medium = MediumKind(:persistent_medium)
    system = PottsSystem(
        name = :ForbidExtinctionBackendFixture,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 1),
            cell,
            medium,
            Protocol(Sweep(; temperature = 100.0); name = :main),
        )),
    )
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    executable = compile(
        complete(system);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    return executable, PottsToolkit._core_initial_state(
        executable, initial, UInt64(1), UInt32(1)
    )
end

function run_forbid_extinction_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    executable, initial = _forbid_extinction_fixture()
    program = executable.core_program
    selected_seed = nothing
    reference = nothing
    for seed in UInt64(1):UInt64(64)
        candidate = CorePotts.initialize_program(
            program, initial, program.parameter_defaults, seed, UInt32(1)
        )
        CorePotts.execute_checkerboard_mcs!(candidate.engine_workspace, 0)
        if candidate.engine_workspace.report[4] > 0
            selected_seed = seed
            reference = candidate
            break
        end
    end
    @test selected_seed !== nothing
    @test reference !== nothing
    candidate = CorePotts.initialize_program(
        program,
        initial,
        program.parameter_defaults,
        something(selected_seed),
        UInt32(1),
    )
    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, candidate.engine_workspace
    )
    CorePotts.execute_checkerboard_mcs!(workspace, 0)
    backend = CorePotts.KernelAbstractions.get_backend(
        workspace.state.ownership
    )
    CorePotts.KernelAbstractions.synchronize(backend)
    report = to_host(workspace.report)
    @test report == reference.engine_workspace.report
    @test report[4] > 0
    @test to_host(workspace.state.ownership) ==
        reference.engine_workspace.state.ownership
    @test count(==(Int32(1)), reference.engine_workspace.state.ownership) == 1
    @test CorePotts.Adapt.adapt(Array, workspace.state.trackers).values ==
        reference.engine_workspace.state.trackers.values
    return (
        backend = backend_name,
        seed = something(selected_seed),
        constraint_rejections = Int(report[4]),
    )
end

function run_external_lifecycle_operation_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    @variables external_time external_state(external_time)
    cell = CellKind(:external_cell; extinction = RetireAtZero())
    medium = MediumKind(:external_medium)
    relation = SpatialRelation(
        :external_division; neighborhood = VonNeumann()
    )
    state = CellState(
        external_state;
        initial = 1.0f0,
        retirement = RetireTo(0.0f0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:external_anchor)
    divide = LifecycleProcess(
        :external_divide;
        domain = cells(cell),
        anchor,
        expression = external_lifecycle_trigger(
            cell_volume(anchor_value(anchor))
        ),
        effects = (Divide(
            anchor;
            geometry = external_lifecycle_partition(
                anchor_value(anchor)
            ),
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
    system = PottsSystem(
        name = :ExternalLifecycleBackendFixture,
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
        independent_variables = [external_time],
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    _, reference, executable, workspace = _direct_lifecycle_runtimes(
        complete(system), initial, device_array; seed = 0x85
    )
    @test length(executable.reports.compiler.lifecycle) == 3
    @test count(
        record -> !isempty(record.operation_abis),
        executable.reports.compiler.lifecycle,
    ) == 2
    _enqueue_direct_lifecycle_sequence!(reference, workspace, 1:2)
    _assert_direct_lifecycle_equivalence(reference, workspace, to_host)
    @test count(!iszero, reference.cell_kinds) == 3
    handle = only(executable.reports.states).handle
    @test CorePotts.state_block(
        reference.descriptor_state, handle
    ).values[3] == 5.0f0
    return (backend = backend_name, operations = 4, active_cells = 3)
end

function _resolution_policy_system(policy; stable::Bool)
    cell = CellKind(:resolution_cell; extinction = RetireAtZero())
    destination = CellKind(
        :resolution_destination; extinction = RetireAtZero()
    )
    medium = MediumKind(:resolution_medium)
    relation = SpatialRelation(
        :resolution_relation; neighborhood = VonNeumann()
    )
    anchor = CellBinding(:resolution_anchor)
    processes = if stable
        (
            LifecycleProcess(
                :filtered_high_priority;
                domain = cells(cell),
                anchor,
                expression = true,
                effects = (Divide(
                    anchor;
                    geometry = SpecifiedNormalPlane((1.0f0, 0.0f0)),
                    relation,
                    side = CanonicalSide(),
                    priority = 100,
                    on_inadmissible = FilterInadmissible(),
                ),),
            ),
            LifecycleProcess(
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
            ),
        )
    else
        (
            LifecycleProcess(
                :conflict_a;
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = SeedAt(1),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
            ),
            LifecycleProcess(
                :conflict_b;
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = SeedAt(1),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
            ),
        )
    end
    system = PottsSystem(
        name = stable ? :StableResolutionBackendFixture :
               :RejectResolutionBackendFixture,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 2),
            cell,
            destination,
            medium,
            relation,
            processes...,
            Protocol(Sweep(); name = :main, lifecycle_conflicts = policy),
        )),
    )
    labels = zeros(Int, 3, 3)
    stable && (labels[2, 2] = 1)
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = stable ? [cell] : [], medium
    ))
    return complete(system), initial
end

function run_lifecycle_resolution_policy_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    stable_completed, stable_initial = _resolution_policy_system(
        StableLifecyclePriority(); stable = true
    )
    _, stable_reference, _, stable_workspace = _direct_lifecycle_runtimes(
        stable_completed, stable_initial, device_array; seed = 0x86
    )
    _enqueue_direct_lifecycle_sequence!(
        stable_reference, stable_workspace, (1,)
    )
    _assert_direct_lifecycle_equivalence(
        stable_reference, stable_workspace, to_host
    )
    @test stable_reference.cell_kinds[1] != 0
    @test count(stable_reference.lifecycle_workspace.filtered) == 1

    reject_completed, reject_initial = _resolution_policy_system(
        RejectLifecycleAmbiguity(); stable = false
    )
    _, _, reject_executable, host_workspace = _direct_lifecycle_runtimes(
        reject_completed, reject_initial, Array; seed = 0x87
    )
    initial_ownership = copy(host_workspace.state.ownership)
    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, host_workspace
    )
    state = CorePotts._checkerboard_state_at_mcs(workspace.state, 0)
    CorePotts.enqueue_lifecycle_backend_index!(state)
    backend = CorePotts.KernelAbstractions.get_backend(state.ownership)
    CorePotts.KernelAbstractions.synchronize(backend)
    status = only(to_host(state.lifecycle_workspace.status))
    @test status.code === CorePotts.ProgramStatusConflict
    @test status.stage === CorePotts.ProgramStageSelection
    @test to_host(state.ownership) == initial_ownership
    @test reject_executable.reports.lifecycle.conflict_policy ===
        :RejectLifecycleConflicts
    return (backend = backend_name, filtered = 1, rejected_conflict = true)
end
