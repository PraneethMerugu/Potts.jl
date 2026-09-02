using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase
using SymbolicIndexingInterface
using Sundials: IDA
import Catalyst
using Catalyst: @reaction_network

const IMPURE_CALL_COUNT = Ref(0)
function impure_identity(value)
    IMPURE_CALL_COUNT[] += 1
    return value
end

@testset "per-cell serial native ODE runtime" begin
    @independent_variables cell_ode_t
    @variables cell_ode_x(cell_ode_t) = 1.0 cell_ode_drive(cell_ode_t)
    cell_ode_D = ModelingToolkitBase.Differential(cell_ode_t)
    @named cell_ode_system = ModelingToolkit.System(
        [cell_ode_D(cell_ode_x) ~ cell_ode_drive], cell_ode_t
    )
    @variables potts_cell_drive potts_cell_output
    drive_state = CellState(
        potts_cell_drive;
        name = :potts_cell_drive,
        initial = 2.0,
        retirement = RetireTo(0.0),
    )
    output_state = CellState(
        potts_cell_output;
        name = :potts_cell_output,
        initial = 0.0,
        retirement = RetireTo(0.0),
    )
    component = NativeComponent(
        cell_ode_system;
        name = :cell_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(
            cell_ode_drive, drive_state; value_type = Float64
        ),),
        outputs = (NativeOutput(
            cell_ode_x, output_state; value_type = Float64
        ),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = ResetTo((cell_ode_x => cell_ode_x + 3.0,)),
            division = TransformDaughters(
                (cell_ode_x => cell_ode_x / 2,),
                (cell_ode_x => cell_ode_x / 2,),
            ),
        ),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :per_cell_coupled,
        statements = StatementSet((
            Lattice((3, 3); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            drive_state,
            output_state,
            ProposalConstraint(:freeze_per_cell_native, false),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [potts_cell_drive, potts_cell_output],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:per_cell_coupled, :cell_island)
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = (cell_ode_x => 1.0,)
        ),),
    )
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x504)
    profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-per-cell-fixed-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    checkerboard_error = try
        init(
            problem,
            CheckerboardSweepCPM();
            native_profiles = (profile,),
        )
        nothing
    catch error
        error
    end
    @test checkerboard_error isa Potts.NativeCapabilityError
    @test checkerboard_error.capability === :execution_profile
    integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,)
    )
    identity = CellIdentity(
        1, integrator.u.cell_generations[1], integrator.u.cell_kinds[1]
    )
    @test native_value(integrator, path, identity, cell_ode_x) == 1.0
    @test integrator.u.potts_cell_output[1] == 1.0
    policy = integrator.native_states[1].policy
    candidate_bank = Potts.CorePotts.BackendSPI.component_state_snapshot(
        integrator.native_states[1].storage
    )
    transition_event = Potts.CorePotts.TransitionLifecycleEvent(
        Potts.CorePotts.QualifiedLifecycleRequestIdentity(1, 1, 1, 1),
        identity,
        CellIdentity(identity.slot, identity.generation, identity.kind + 1),
    )
    Potts.transition_component_state!(
        policy, candidate_bank, transition_event
    )
    @test Potts.native_cell_state(policy, candidate_bank, 1).u == (4.0,)
    divide_event = Potts.CorePotts.DivideLifecycleEvent(
        Potts.CorePotts.QualifiedLifecycleRequestIdentity(2, 1, 1, 1),
        identity,
        identity,
        CellIdentity(2, 1, identity.kind),
    )
    Potts.divide_component_state!(policy, candidate_bank, divide_event)
    @test Potts.native_cell_state(policy, candidate_bank, 1).u == (2.0,)
    @test Potts.native_cell_state(policy, candidate_bank, 2).u == (2.0,)
    step!(integrator)
    @test native_value(integrator, path, identity, cell_ode_x) ≈ 1.2
    @test integrator.u.potts_cell_output[1] ≈ 1.2
    saved = checkpoint(integrator)
    restored = init(
        problem,
        SequentialCPM();
        checkpoint = saved,
        native_profiles = (profile,),
    )
    @test native_value(restored, path, identity, cell_ode_x) ≈ 1.2
    step!(integrator)
    step!(restored)
    @test native_value(restored, path, identity, cell_ode_x) ==
        native_value(integrator, path, identity, cell_ode_x)
    @test restored.u.potts_cell_output == integrator.u.potts_cell_output
    @test native_state(restored.u, path, identity).u ==
        native_state(integrator.u, path, identity).u
    stale_identity = CellIdentity(
        identity.slot, identity.generation + 1, identity.kind
    )
    @test_throws ArgumentError native_state(restored.u, path, stale_identity)
    @test_throws ArgumentError native_value(restored, path, cell_ode_x)
    solution = solve(
        problem, SequentialCPM(); native_profiles = (profile,)
    )
    @test native_value(solution, path, identity, cell_ode_x) ≈ 1.4
    @test_throws ArgumentError native_value(solution, path, cell_ode_x)

    adaptive_batch = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "adaptive-batch-rejected",
        execution = BatchedNativeExecution(4),
        deterministic = true,
        adaptive = true,
    )
    adaptive_error = try
        init(
            problem,
            SequentialCPM();
            native_profiles = (adaptive_batch,),
        )
        nothing
    catch error
        error
    end
    @test adaptive_error isa Potts.NativeCapabilityError
    @test adaptive_error.capability === :native_execution_mode

    failing_batch = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-per-cell-batch-failure-v1",
        execution = BatchedNativeExecution(4),
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
        maxiters = 1,
    )
    failing = init(
        problem,
        SequentialCPM();
        native_profiles = (failing_batch,),
    )
    before_failure = failing.u
    @test_throws Potts.NativeSolveFailure step!(failing)
    @test failing.t == 0
    @test failing.retcode == SciMLBase.ReturnCode.Failure
    @test failing.u.ownership == before_failure.ownership
    @test only(failing.u.native).active == only(before_failure.native).active
    @test map(value -> value === nothing ? nothing : value.u,
        only(failing.u.native).states) ==
        map(value -> value === nothing ? nothing : value.u,
            only(before_failure.native).states)
end

@testset "per-cell lifecycle receipts and slot reuse" begin
    @independent_variables lifecycle_native_t
    @variables lifecycle_native_x(lifecycle_native_t) = 1.0
    @parameters lifecycle_native_rate = 0.0
    lifecycle_native_D = ModelingToolkitBase.Differential(lifecycle_native_t)
    @named lifecycle_native_system = ModelingToolkit.System(
        [lifecycle_native_D(lifecycle_native_x) ~ lifecycle_native_rate],
        lifecycle_native_t,
    )
    component = NativeComponent(
        lifecycle_native_system;
        name = :lifecycle_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = ResetTo((
                lifecycle_native_x => lifecycle_native_x + 3.0,
            )),
            division = TransformDaughters(
                (lifecycle_native_x => lifecycle_native_x / 2,),
                (lifecycle_native_x => lifecycle_native_x / 2,),
            ),
        ),
    )
    cell = CellKind(:lifecycle_native_cell; extinction = RetireAtZero())
    daughter = CellKind(
        :lifecycle_native_daughter; extinction = RetireAtZero()
    )
    medium = MediumKind(:lifecycle_native_medium)
    relation = SpatialRelation(
        :lifecycle_native_division; neighborhood = VonNeumann()
    )
    anchor = CellBinding(:lifecycle_native_anchor)
    create_site = LinearIndices((6, 6))[CartesianIndex(5, 2)]
    reuse_site = LinearIndices((6, 6))[CartesianIndex(2, 2)]
    create = LifecycleProcess(
        :lifecycle_native_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                create_site, ((0, 0), (1, 0)); relation
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :lifecycle_native_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :lifecycle_native_divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :lifecycle_native_remove;
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
        :lifecycle_native_reuse;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            daughter;
            placement = SeedAt(reuse_site),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(5),
    )
    source = PottsSystem(
        name = :per_cell_lifecycle_model,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 4),
            cell,
            daughter,
            medium,
            relation,
            ProposalConstraint(:freeze_native_lifecycle, false),
            create,
            transition,
            divide,
            remove,
            reuse,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:per_cell_lifecycle_model, :lifecycle_island)
    labels = zeros(Int, 6, 6)
    labels[2:5, 4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = (
                lifecycle_native_x => 1.0,
                lifecycle_native_rate => 0.0,
            )
        ),),
    )
    problem = PottsProblem(scheduled, initial, (0, 5); seed = 0x505)
    profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-per-cell-lifecycle-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    batched_profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-per-cell-lifecycle-batched-v1",
        execution = BatchedNativeExecution(3),
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    solution = solve(
        problem,
        SequentialCPM();
        native_profiles = (profile,),
        save_everystep = true,
    )
    batched_solution = solve(
        problem,
        SequentialCPM();
        native_profiles = (batched_profile,),
        save_everystep = true,
    )
    logical_tuple = value -> value === nothing ? nothing : (
        value.u, value.p, value.du, value.t, value.retcode
    )
    for index in eachindex(solution.u, batched_solution.u)
        serial_saved = solution.u[index]
        batched_saved = batched_solution.u[index]
        @test batched_saved.ownership == serial_saved.ownership
        @test batched_saved.cell_kinds == serial_saved.cell_kinds
        @test batched_saved.cell_generations == serial_saved.cell_generations
        serial_native = only(serial_saved.native)
        batched_native = only(batched_saved.native)
        @test batched_native.active == serial_native.active
        @test batched_native.generations == serial_native.generations
        @test batched_native.kinds == serial_native.kinds
        @test logical_tuple.(batched_native.states) ==
            logical_tuple.(serial_native.states)
    end
    first_identity = CellIdentity(
        1, solution(0).cell_generations[1], solution(0).cell_kinds[1]
    )
    @test native_value(
        solution, path, first_identity, lifecycle_native_x; index = 1
    ) == 1.0
    @test count(!iszero, solution(1).cell_kinds) == 2
    for slot in findall(!iszero, solution(2).cell_kinds)
        identity = CellIdentity(
            slot,
            solution(2).cell_generations[slot],
            solution(2).cell_kinds[slot],
        )
        @test native_value(
            solution, path, identity, lifecycle_native_x; index = 3
        ) == 4.0
    end
    @test count(!iszero, solution(3).cell_kinds) == 4
    for slot in findall(!iszero, solution(3).cell_kinds)
        identity = CellIdentity(
            slot,
            solution(3).cell_generations[slot],
            solution(3).cell_kinds[slot],
        )
        @test native_value(
            solution, path, identity, lifecycle_native_x; index = 4
        ) == 2.0
    end
    @test all(iszero, solution(4).cell_kinds)
    reused_slot = only(findall(!iszero, solution(5).cell_kinds))
    reused_identity = CellIdentity(
        reused_slot,
        solution(5).cell_generations[reused_slot],
        solution(5).cell_kinds[reused_slot],
    )
    @test reused_identity.generation == 2
    @test native_value(
        solution, path, reused_identity, lifecycle_native_x; index = 6
    ) == 1.0
    @test_throws ArgumentError native_state(
        solution, path, first_identity; index = 6
    )

    checkpointed = init(
        problem,
        SequentialCPM();
        native_profiles = (batched_profile,),
        save_everystep = true,
    )
    step!(checkpointed)
    step!(checkpointed)
    step!(checkpointed)
    captured = checkpoint(checkpointed)
    resumed = solve!(init(
        problem,
        SequentialCPM();
        checkpoint = captured,
        native_profiles = (batched_profile,),
        save_everystep = true,
    ))
    @test last(resumed).ownership == batched_solution(5).ownership
    @test last(resumed).cell_kinds == batched_solution(5).cell_kinds
    @test last(resumed).cell_generations == batched_solution(5).cell_generations
    resumed_native = only(last(resumed).native)
    expected_native = only(batched_solution(5).native)
    @test resumed_native.active == expected_native.active
    @test resumed_native.generations == expected_native.generations
    @test resumed_native.kinds == expected_native.kinds
    @test resumed_native.identities == expected_native.identities
    @test logical_tuple.(resumed_native.states) ==
        logical_tuple.(expected_native.states)
    @test resumed_native.completed_mcs == expected_native.completed_mcs
    @test resumed_native.last_transaction_identity ==
        expected_native.last_transaction_identity
end
Symbolics.@register_symbolic impure_identity(value)

function _native_runtime_fixture(
        name::Symbol;
        native_system,
        native_family,
        native_input,
        native_output,
        potts_input_initial = 2.0,
        potts_output_initial = 0.0,
        cadence = EveryMCS(),
        duration = 0.1,
        operating_values = (),
        operating_guesses = (),
    )
    @variables potts_drive potts_output
    drive_state = ModelState(
        potts_drive; name = :potts_drive, initial = potts_input_initial
    )
    output_state = ModelState(
        potts_output; name = :potts_output, initial = potts_output_initial
    )
    component = NativeComponent(
        native_system;
        name = :island,
        family = native_family,
        time = FixedPhysicalTime(0.0, duration),
        cadence,
        inputs = (NativeInput(
            native_input, drive_state; value_type = Float64
        ),),
        outputs = (NativeOutput(
            native_output, output_state; value_type = Float64
        ),),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((3, 3); boundary = Closed()),
            cell,
            medium,
            drive_state,
            output_state,
            Synchronous(
                :raise_native_drive,
                Assign(potts_drive, potts_drive + potts_output);
                phase = AfterMCS(),
            ),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [potts_drive, potts_output],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (name, :island)
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = operating_values, guesses = operating_guesses
        ),),
    )
    return (;
        source,
        scheduled,
        path,
        component,
        cell,
        medium,
        potts_drive,
        potts_output,
        initial,
    )
end

function _native_output_fixture(
        name::Symbol;
        native_system,
        native_family,
        native_output,
        potts_output_initial = 0.0,
        cadence = EveryMCS(),
        duration = 0.1,
        operating_values = (),
        operating_guesses = (),
    )
    @variables potts_output
    output_state = ModelState(
        potts_output; name = :potts_output, initial = potts_output_initial
    )
    component = NativeComponent(
        native_system;
        name = :island,
        family = native_family,
        time = FixedPhysicalTime(0.0, duration),
        cadence,
        outputs = (NativeOutput(
            native_output, output_state; value_type = Float64
        ),),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((3, 3); boundary = Closed()),
            cell,
            medium,
            output_state,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [potts_output],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (name, :island)
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = operating_values, guesses = operating_guesses
        ),),
    )
    return (;
        source,
        scheduled,
        path,
        component,
        cell,
        medium,
        potts_output,
        initial,
    )
end

@testset "coupled native ODE runtime" begin
    @independent_variables ode_t
    @variables ode_x(ode_t) = 1.0 ode_drive(ode_t)
    @variables ode_seen(ode_t)
    ode_D = ModelingToolkitBase.Differential(ode_t)
    @named ode_system = ModelingToolkit.System(
        [ode_D(ode_x) ~ -ode_x + ode_drive],
        ode_t;
        observed = [ode_seen ~ 2ode_x],
    )
    source_fingerprint = Potts.native_source_fingerprint(ode_system)
    changed_observation = ModelingToolkit.System(
        [ode_D(ode_x) ~ -ode_x + ode_drive],
        ode_t;
        name = :ode_system,
        observed = [ode_seen ~ 3ode_x],
    )
    @test Potts.native_source_fingerprint(changed_observation) !=
        source_fingerprint
    fixture = _native_runtime_fixture(
        :ode_coupled;
        native_system = ode_system,
        native_family = ODEComponent(),
        native_input = ode_drive,
        native_output = ode_x,
        operating_values = (ode_x => 1.0,),
    )
    @test Potts.native_source_fingerprint(ode_system) ==
        source_fingerprint
    problem = PottsProblem(
        fixture.scheduled, fixture.initial, (0, 2); seed = 0x503
    )
    profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "tsit5-fixed-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    reordered_profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "tsit5-fixed-v1",
        deterministic = true,
        exact_replay = true,
        dt = 0.01,
        adaptive = false,
    )
    @test keys(profile.options) == (:adaptive, :dt)
    @test profile.options == reordered_profile.options
    @test Potts._native_profile_fingerprint(profile) ==
        Potts._native_profile_fingerprint(reordered_profile)
    values_forward = Dict(ode_x => 1.0, ode_drive => 2.0)
    values_reverse = Dict(ode_drive => 2.0, ode_x => 1.0)
    point_forward = NativeOperatingPoint(
        fixture.path; values = values_forward
    )
    point_reverse = NativeOperatingPoint(
        fixture.path; values = Tuple(reverse(collect(values_reverse)))
    )
    @test point_forward.values == point_reverse.values
    @test_throws ArgumentError init(problem, SequentialCPM())
    global_batch = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "global-batch-rejected",
        execution = BatchedNativeExecution(4),
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    global_batch_error = try
        init(
            problem,
            SequentialCPM();
            native_profiles = (global_batch,),
        )
        nothing
    catch error
        error
    end
    @test global_batch_error isa Potts.NativeCapabilityError
    @test global_batch_error.capability === :native_execution_mode
    functional_profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    functional = init(
        problem, SequentialCPM(); native_profiles = (functional_profile,)
    )
    @test functional.capability_report.status ===
        Potts.CorePotts.BackendSPI.Supported
    @test !functional.capability_report.exact_replay
    @test functional.capability_report.evidence.conjunction === nothing
    step!(functional)
    @test functional.u[:potts_output] ≈ 3 - 2exp(-0.1) atol = 2e-8
    @test_throws ArgumentError checkpoint(functional)

    invalid_solver_profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        definitely_not_a_solver_option = true,
    )
    preflight_error = try
        init(
            problem,
            SequentialCPM();
            native_profiles = (invalid_solver_profile,),
        )
        nothing
    catch caught
        caught
    end
    @test preflight_error isa Potts.NativeExecutionError
    integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    @test integrator.u[:potts_output] === 1.0
    @test native_value(integrator, fixture.path, ode_seen) === 2.0
    step!(integrator)
    # The CPM process consumes the previously published native output (1),
    # stages drive 2 -> 3, and that same candidate snapshot drives the island.
    @test integrator.u[:potts_drive] === 3.0
    @test integrator.u[:potts_output] ≈ 3 - 2exp(-0.1) atol = 2e-8
    @test native_value(integrator, fixture.path, ode_seen) ≈
        2integrator.u[:potts_output]
    saved = integrator.u
    @test saved.native[1].t === 0.1
    @test saved.native[1].du === nothing

    scheduled_requirements = inspect(fixture.scheduled, Capabilities())
    @test scheduled_requirements.support_status ===
        :requires_concrete_runtime_profile
    @test !hasproperty(
        only(scheduled_requirements.native_components), :support
    )
    @test inspect(problem, Capabilities()).support_status ===
        :requires_concrete_runtime_profile
    replay_contract = only(
        inspect(fixture.scheduled, ReplayContract()).native_components
    )
    @test replay_contract.restart === :exact_configuration_only
    report = inspect(integrator, Capabilities())
    @test report.evidence.conjunction.profile_fingerprint ==
        report.key.fingerprint
    @test only(report.key.native).evidence.profile_fingerprint ==
        only(report.evidence.native).profile_fingerprint
    @test only(report.key.native).native_stack.ModelingToolkit.version ==
        v"11.37.1"
    @test report.key.outer_events.mode === :none
    @test report.key.outer_events.checkpoint === :admitted
    @test report.key.observation_save.save_everystep
    @test report.key.observation_save.observables == ()

    custom_limiter! = (_u, _integrator, _p, _t) -> nothing
    custom_algorithm_profile = NativeSolveProfile(
        fixture.path,
        Tsit5(; stage_limiter! = custom_limiter!);
        profile_id = "tsit5-custom-limiter-unqualified",
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    custom_integrator = init(
        problem, SequentialCPM();
        native_profiles = (custom_algorithm_profile,),
    )
    custom_report = inspect(custom_integrator, Capabilities())
    @test custom_report.status === report.status
    @test !custom_report.exact_replay
    custom_checkpoint_error = try
        checkpoint(custom_integrator)
        nothing
    catch caught
        caught
    end
    @test custom_checkpoint_error isa ArgumentError
    @test occursin(
        "exact-replay evidence", sprint(showerror, custom_checkpoint_error))

    uninterrupted = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    step!(uninterrupted)
    captured = checkpoint(uninterrupted)
    checkpoint_block = captured.extensions.Potts
    @test checkpoint_block.replay_class === :exact_pinned_native_profiles
    @test only(checkpoint_block.native_components).replay_class ===
        :exact_pinned_deterministic_profile
    @test checkpoint_block.capability_fingerprint ==
        uninterrupted.capability_report.key.fingerprint
    @test checkpoint_block.conjunction_evidence.profile_fingerprint ==
        checkpoint_block.capability_fingerprint
    resumed = init(
        problem, SequentialCPM(); native_profiles = (reordered_profile,),
        checkpoint = captured, save_everystep = true,
    )
    @test resumed.t == uninterrupted.t == 1
    step!(uninterrupted)
    step!(resumed)
    @test resumed.u.ownership == uninterrupted.u.ownership
    @test resumed.u[:potts_drive] === uninterrupted.u[:potts_drive]
    @test resumed.u[:potts_output] === uninterrupted.u[:potts_output]
    @test resumed.native_states == uninterrupted.native_states
    @test checkpoint(resumed).checksum == checkpoint(uninterrupted).checksum

    direct_solution = solve(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    @test last(direct_solution.t) == 2
    @test only(last(direct_solution.u).native).t === 0.2
    @test last(direct_solution.u)[:potts_output] ≈
        uninterrupted.u[:potts_output]
    in_place = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    in_place_solution = solve!(in_place)
    @test in_place.t == 2
    @test only(in_place.native_states).t === 0.2
    @test last(in_place_solution.u)[:potts_output] ≈
        uninterrupted.u[:potts_output]

    remade = remake(problem; seed = problem.seed + 1)
    @test remade.seed == problem.seed + 1
    @test only(remade.u0.native).path == fixture.path
    @test only(remade.u0.native).values == only(problem.u0.native).values

    failure_profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "tsit5-bounded-failure-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.001,
        maxiters = 1,
    )
    failing = init(
        problem, SequentialCPM(); native_profiles = (failure_profile,),
        save_everystep = true,
    )
    @test failing.capability_report.exact_replay
    @test checkpoint(failing).snapshot.mcs == 0
    before_failure = failing.u
    before_native = only(failing.native_states)
    native_error = try
        step!(failing)
        nothing
    catch caught
        caught
    end
    @test native_error isa Potts.NativeSolveFailure
    @test failing.retcode === SciMLBase.ReturnCode.Failure
    @test failing.t == 0
    @test failing.runtime.mcs == 0
    @test failing.u[:potts_drive] === before_failure[:potts_drive]
    @test failing.u[:potts_output] === before_failure[:potts_output]
    @test only(failing.native_states) == before_native
    @test_throws ArgumentError checkpoint(failing)

    cancel_callback = SciMLBase.DiscreteCallback(
        (_u, time, _integrator) -> time == 1,
        terminate!;
        save_positions = (false, false),
    )
    @test_throws Potts.NativeCapabilityError init(
        problem, SequentialCPM(); native_profiles = (profile,),
        callback = cancel_callback, save_everystep = true,
    )
    terminated = init(
        problem, SequentialCPM(); native_profiles = (profile,)
    )
    step!(terminated)
    terminal_state = terminated.u
    terminal_native = copy(terminated.native_states)
    terminate!(terminated)
    @test terminated.t == 1
    @test terminated.retcode === SciMLBase.ReturnCode.Terminated
    @test terminated.u == terminal_state
    @test terminated.native_states == terminal_native
    @test_throws ArgumentError step!(terminated)
    @test terminated.u == terminal_state
    @test terminated.native_states == terminal_native
    @test_throws ArgumentError checkpoint(terminated)
end

@testset "native event retention and public-only rejection" begin
    @independent_variables event_t
    @variables event_x(event_t) = 0.0
    event_D = ModelingToolkitBase.Differential(event_t)
    @named event_system = ModelingToolkit.System(
        [event_D(event_x) ~ 1.0],
        event_t;
        continuous_events = ([event_x ~ 0.06] => [event_x ~ 0.0]),
    )
    fixture = _native_output_fixture(
        :event_coupled;
        native_system = event_system,
        native_family = ODEComponent(),
        native_output = event_x,
        operating_values = (event_x => 0.0,),
    )
    problem = PottsProblem(
        fixture.scheduled, fixture.initial, (0, 1); seed = 0x504
    )
    compiled = only(scheduled_native_components(fixture.scheduled))
    @test length(ModelingToolkitBase.continuous_events(
        Potts.native_original_system(compiled)
    )) == 1
    @test length(ModelingToolkitBase.continuous_events(
        Potts.native_scheduled_system(compiled)
    )) == 1
    profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "tsit5-symbolic-event-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.005,
    )
    event_error = try
        init(problem, SequentialCPM(); native_profiles = (profile,))
        nothing
    catch caught
        caught
    end
    @test event_error isa Potts.NativeCapabilityError
    @test occursin("event-free", sprint(showerror, event_error))
end

@testset "native DAE functional execution" begin
    @independent_variables dae_t
    @variables dae_x(dae_t) [guess = 1.0]
    @variables dae_y(dae_t) [guess = 1.0]
    dae_D = ModelingToolkitBase.Differential(dae_t)
    @named dae_system = ModelingToolkit.System(
        [dae_D(dae_x) ~ dae_y, dae_x + dae_y ~ 2.0], dae_t
    )
    fixture = _native_output_fixture(
        :dae_coupled;
        native_system = dae_system,
        native_family = DAEComponent(),
        native_output = dae_x,
        operating_values = (dae_x => 1.0, dae_D(dae_x) => 1.0),
    )
    problem = PottsProblem(
        fixture.scheduled, fixture.initial, (0, 2); seed = 0x505
    )
    profile = NativeSolveProfile(
        fixture.path, IDA(); profile_id = "ida-logical-v1"
    )
    component = only(scheduled_native_components(fixture.scheduled))
    scheduled_dae = Potts.native_scheduled_system(component)
    standard_problem = SciMLBase.DAEProblem(
        scheduled_dae,
        [dae_x => 1.0, dae_D(dae_x) => 1.0],
        (0.0, 0.1),
    )
    standard_integrator = SciMLBase.init(
        standard_problem, profile.algorithm;
        initializealg = SciMLBase.OverrideInit(),
    )
    @test SymbolicIndexingInterface.current_time(standard_integrator) === 0.0
    @test SciMLBase.get_du(standard_integrator) !== nothing
    @test SymbolicIndexingInterface.getsym(
        scheduled_dae, dae_x
    )(standard_integrator) ≈ 1.0
    dae_integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,)
    )
    @test dae_integrator.capability_report.status ===
        Potts.CorePotts.BackendSPI.Supported
    @test !dae_integrator.capability_report.exact_replay
    @test native_value(dae_integrator, fixture.path, dae_x) ≈ 1.0
    step!(dae_integrator)
    @test dae_integrator.t == 1
    @test isfinite(native_value(dae_integrator, fixture.path, dae_x))
    @test_throws ArgumentError checkpoint(dae_integrator)
end

@testset "explicit Catalyst ODE conversion" begin
    reaction_system = @reaction_network begin
        1.0, X --> 0
    end
    reaction_x_symbol = only(Catalyst.get_species(reaction_system))
    reaction_x = Symbolics.wrap(reaction_x_symbol)
    raw_error = try
        _native_output_fixture(
            :raw_catalyst_rejected;
            native_system = reaction_system,
            native_family = ODEComponent(),
            native_output = reaction_x,
            operating_values = (reaction_x => 1.0,),
        )
        nothing
    catch caught
        caught
    end
    @test raw_error isa ArgumentError
    @test occursin("Catalyst.ode_model", sprint(showerror, raw_error))
    native_ode = Catalyst.ode_model(
        reaction_system;
        name = :catalyst_decay_ode,
        initial_conditions = Dict(reaction_x_symbol => 1.0),
    )
    fixture = _native_output_fixture(
        :catalyst_coupled;
        native_system = native_ode,
        native_family = ODEComponent(),
        native_output = reaction_x,
    )
    compiled = only(scheduled_native_components(fixture.scheduled))
    @test Potts.native_original_system(compiled) === native_ode
    @test !(Potts.native_original_system(compiled) isa
        Catalyst.ReactionSystem)
    problem = PottsProblem(
        fixture.scheduled, fixture.initial, (0, 1); seed = 0x506
    )
    profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "catalyst-ode-tsit5-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.005,
    )
    integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    step!(integrator)
    @test integrator.u[:potts_output] ≈ exp(-0.1) atol = 2e-8
end

@testset "zero-port native island" begin
    @independent_variables isolated_t
    @variables isolated_x(isolated_t) = 1.0
    isolated_D = ModelingToolkitBase.Differential(isolated_t)
    @named isolated_system = ModelingToolkit.System(
        [isolated_D(isolated_x) ~ -isolated_x], isolated_t
    )
    component = NativeComponent(
        isolated_system;
        name = :island,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :zero_port,
        statements = StatementSet((
            Lattice((3, 3); boundary = Closed()),
            cell,
            medium,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:zero_port, :island)
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = (isolated_x => 1.0,)
        ),),
    )
    problem = PottsProblem(scheduled, initial, (0, 1); seed = 0x507)
    profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "zero-port-tsit5-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.005,
    )
    integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    step!(integrator)
    @test native_value(integrator, path, isolated_x) ≈ exp(-0.1) atol = 2e-8
    @test isempty(inspect(scheduled, ExternalIO()))
end

@testset "simultaneous native-island publication" begin
    @independent_variables jacobi_t
    @variables producer_x(jacobi_t) = 2.0
    @variables consumer_x(jacobi_t) = 0.0 consumer_drive(jacobi_t)
    jacobi_D = ModelingToolkitBase.Differential(jacobi_t)
    @named producer_system = ModelingToolkit.System(
        [jacobi_D(producer_x) ~ 1.0], jacobi_t
    )
    @named consumer_system = ModelingToolkit.System(
        [jacobi_D(consumer_x) ~ consumer_drive], jacobi_t
    )
    @variables jacobi_bridge jacobi_result
    bridge_state = ModelState(
        jacobi_bridge; name = :jacobi_bridge, initial = 1.0
    )
    result_state = ModelState(
        jacobi_result; name = :jacobi_result, initial = 0.0
    )
    producer = NativeComponent(
        producer_system;
        name = :producer,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        outputs = (NativeOutput(
            producer_x, bridge_state; value_type = Float64
        ),),
    )
    consumer = NativeComponent(
        consumer_system;
        name = :consumer,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(
            consumer_drive, bridge_state; value_type = Float64
        ),),
        outputs = (NativeOutput(
            consumer_x, result_state; value_type = Float64
        ),),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    statements = StatementSet((
        Lattice((3, 3); boundary = Closed()),
        cell,
        medium,
        bridge_state,
        result_state,
        Protocol(Sweep(; temperature = 1.0); name = :main),
    ))
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1

    function jacobi_problem(name, components)
        scheduled = mtkcompile(PottsSystem(
            name = name,
            statements = statements,
            unknowns = [jacobi_bridge, jacobi_result],
            native_components = components,
        ))
        initial = PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            native = (
                NativeOperatingPoint(
                    (name, :producer); values = (producer_x => 2.0,)
                ),
                NativeOperatingPoint(
                    (name, :consumer); values = (consumer_x => 0.0,)
                ),
            ),
        )
        problem = PottsProblem(scheduled, initial, (0, 1); seed = 0x508)
        profiles = (
            NativeSolveProfile(
                (name, :producer), Tsit5();
                profile_id = "jacobi-producer-v1",
                deterministic = true,
                exact_replay = true,
                adaptive = false,
                dt = 0.005,
            ),
            NativeSolveProfile(
                (name, :consumer), Tsit5();
                profile_id = "jacobi-consumer-v1",
                deterministic = true,
                exact_replay = true,
                adaptive = false,
                dt = 0.005,
            ),
        )
        return problem, profiles
    end

    forward_problem, forward_profiles = jacobi_problem(
        :jacobi_forward, (producer, consumer)
    )
    reverse_problem, reverse_profiles = jacobi_problem(
        :jacobi_reverse, (consumer, producer)
    )
    forward = solve(
        forward_problem, SequentialCPM();
        native_profiles = forward_profiles,
        save_everystep = true,
    )
    reverse_integrator = init(
        reverse_problem, SequentialCPM();
        native_profiles = reverse_profiles,
        save_everystep = true,
    )
    reverse = solve!(reverse_integrator)
    @test last(forward.u)[:jacobi_bridge] ≈ 2.1 atol = 2e-9
    @test last(forward.u)[:jacobi_result] ≈ 0.2 atol = 2e-9
    @test last(reverse.u)[:jacobi_bridge] ≈
        last(forward.u)[:jacobi_bridge] atol = 2e-9
    @test last(reverse.u)[:jacobi_result] ≈
        last(forward.u)[:jacobi_result] atol = 2e-9
end

@testset "registered host functions cannot inherit replay evidence" begin
    @independent_variables impure_t
    @variables impure_x(impure_t) = 1.0
    impure_D = ModelingToolkitBase.Differential(impure_t)
    @named impure_system = ModelingToolkit.System(
        [impure_D(impure_x) ~ impure_identity(impure_x)], impure_t
    )
    fixture = _native_output_fixture(
        :impure_registered_function;
        native_system = impure_system,
        native_family = ODEComponent(),
        native_output = impure_x,
        operating_values = (impure_x => 1.0,),
    )
    problem = PottsProblem(
        fixture.scheduled, fixture.initial, (0, 1); seed = 0x509
    )
    profile = NativeSolveProfile(
        fixture.path,
        Tsit5();
        profile_id = "impure-function-must-not-qualify",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.005,
    )
    replay_error = try
        init(problem, SequentialCPM(); native_profiles = (profile,))
        nothing
    catch caught
        caught
    end
    @test replay_error isa Potts.NativeCapabilityError
    @test occursin("exact replay", sprint(showerror, replay_error)) ||
        occursin("exact-replay", sprint(showerror, replay_error))
end
