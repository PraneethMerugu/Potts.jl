using DiffEqGPU
using ModelingToolkit
using SciMLBase
using Symbolics
using Test

using ModelingToolkitBase: @independent_variables, @named, @variables

function _metal_profile(
        path, width;
        algorithm = GPUTsit5(),
        adaptive = false,
        dt = 0.015625f0,
    )
    return NativeSolveProfile(
        path,
        algorithm;
        profile_id = "g5h4-metal-gputsit5-fixed-v1",
        execution = MetalNativeExecution(width),
        deterministic = true,
        exact_replay = true,
        adaptive,
        dt,
    )
end

function _metal_global_fixture()
    @independent_variables metal_global_t
    @variables metal_global_x(metal_global_t) = 1.0f0
    differential = ModelingToolkitBase.Differential(metal_global_t)
    @named native = ModelingToolkit.System(
        [differential(metal_global_x) ~ 2.0f0], metal_global_t
    )
    @variables metal_global_output
    output = ModelState(
        metal_global_output; name = :metal_global_output, initial = 0.0f0
    )
    component = NativeComponent(
        native;
        name = :global_island,
        family = ODEComponent(),
        scope = Global(),
        time = FixedPhysicalTime(0.0f0, 0.125f0),
        outputs = (NativeOutput(
            metal_global_x, output; value_type = Float32
        ),),
    )
    cell = CellKind(:metal_cell; extinction = RetireAtZero())
    medium = MediumKind(:metal_medium)
    source = PottsSystem(
        name = :metal_global_model,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed()),
            cell,
            medium,
            output,
            ProposalConstraint(:freeze_metal_global, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [metal_global_output],
        native_components = (component,),
    )
    path = (:metal_global_model, :global_island)
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(
            path; values = (metal_global_x => 1.0f0,)
        ),),
    )
    return PottsProblem(mtkcompile(source), initial, (0, 2); seed = 0x54c), path,
        metal_global_x
end

function _metal_per_cell_fixture()
    @independent_variables metal_cell_t
    @variables metal_cell_x(metal_cell_t) = 1.0f0
    differential = ModelingToolkitBase.Differential(metal_cell_t)
    @named native = ModelingToolkit.System(
        [differential(metal_cell_x) ~ 1.0f0], metal_cell_t
    )
    @variables metal_cell_output
    output = CellState(
        metal_cell_output;
        name = :metal_cell_output,
        initial = 0.0f0,
        retirement = RetireTo(0.0f0),
    )
    component = NativeComponent(
        native;
        name = :cell_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0f0, 0.125f0),
        outputs = (NativeOutput(
            metal_cell_x, output; value_type = Float32
        ),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    cell = CellKind(:metal_cell; extinction = RetireAtZero())
    medium = MediumKind(:metal_medium)
    source = PottsSystem(
        name = :metal_per_cell_model,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            output,
            ProposalConstraint(:freeze_metal_cell, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [metal_cell_output],
        native_components = (component,),
    )
    path = (:metal_per_cell_model, :cell_island)
    labels = zeros(Int, 4, 4)
    labels[1, 1] = 1
    labels[4, 4] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell, cell], medium),
        native = (NativeOperatingPoint(
            path; values = (metal_cell_x => 1.0f0,)
        ),),
    )
    return PottsProblem(mtkcompile(source), initial, (0, 2); seed = 0x54d), path,
        metal_cell_x
end

function _metal_field_fixture(;
        capabilities = RequireQualifiedNativeCapability(),
    )
    @independent_variables metal_field_t
    @variables metal_field_u(metal_field_t)[1:4, 1:4]
    @variables metal_field_output(metal_field_t)
    variables = Symbolics.scalarize(metal_field_u)
    differential = ModelingToolkitBase.Differential(metal_field_t)
    @named native = ModelingToolkit.System(
        vec(differential.(variables) .~ 0.5f0), metal_field_t
    )
    field = FieldState(
        metal_field_output;
        name = :metal_field_output,
        initial = 0.0f0,
        stencil = :field_stencil,
    )
    component = NativeComponent(
        native;
        name = :field_island,
        family = ODEComponent(),
        scope = Global(),
        time = FixedPhysicalTime(0.0f0, 0.125f0),
        outputs = (NativeFieldOutput(
            variables,
            field;
            coordinates = (
                Float32[0, 1, 2, 3], Float32[0, 1, 2, 3]
            ),
            value_type = Float32,
        ),),
        capabilities,
    )
    cell = CellKind(:metal_field_cell; extinction = RetireAtZero())
    medium = MediumKind(:metal_field_medium)
    source = PottsSystem(
        name = :metal_field_model,
        statements = StatementSet((
            Lattice(
                (4, 4);
                boundary = Periodic(),
                relations = (field_stencil = VonNeumann(),),
            ),
            cell,
            medium,
            field,
            ProposalConstraint(:freeze_metal_field, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [metal_field_output],
        native_components = (component,),
    )
    path = (:metal_field_model, :field_island)
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    initial_values = Float32.(reshape(1:16, 4, 4))
    operating_values = Tuple(
        variable => initial_values[index]
        for (index, variable) in enumerate(variables)
    )
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(path; values = operating_values),),
    )
    problem = PottsProblem(
        mtkcompile(source), initial, (0, 2); seed = 0x54f
    )
    return problem, path, variables, initial_values
end

@testset "G5H-4 real Metal native components" begin
    metal_extension = Base.get_extension(PottsToolkit, :PottsToolkitMetalExt)
    @test metal_extension._metal_core_environment_identity() ==
        metal_extension._G5H4_TESTED_METAL_CORE_ENVIRONMENT
    metal_native_extension = Base.get_extension(
        PottsToolkit, :PottsToolkitMetalNativeExt
    )
    @test metal_native_extension._metal_native_stack_identity() ==
        metal_native_extension._G5H4_TESTED_METAL_NATIVE_STACK
    global_problem, global_path, global_x = _metal_global_fixture()
    global_profile = _metal_profile(global_path, 1)
    global_solution = solve(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (global_profile,),
    )
    @test global_solution.retcode === SciMLBase.ReturnCode.Success
    @test native_value(global_solution, global_path, global_x) ≈ 1.5f0
    @test last(global_solution).metal_global_output[1] ≈ 1.5f0
    global_report = inspect(init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (global_profile,),
    ), Capabilities())
    @test only(global_report.evidence.native).suite ===
        :g5h4_global_metal_native_ode_exact_replay
    @test metal_extension._core_environment_digest(global_report.key.core) in
        metal_extension._G5H4_TESTED_CORE_ENVIRONMENT_DIGESTS

    sequential_metal_error = try
        init(
            global_problem,
            SequentialCPM();
            backend = PottsToolkit.MetalBackend(),
            scalar_type = Float32,
            native_profiles = (global_profile,),
        )
        nothing
    catch caught
        caught
    end
    @test sequential_metal_error isa ArgumentError
    @test occursin(
        "accelerator backends require CheckerboardSweepCPM",
        sprint(showerror, sequential_metal_error),
    )

    replay_a = init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (global_profile,),
    )
    replay_b = init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (global_profile,),
    )
    step!(replay_a)
    step!(replay_b)
    @test replay_a.u.ownership == replay_b.u.ownership
    @test native_value(replay_a, global_path, global_x) ==
        native_value(replay_b, global_path, global_x)
    execution = replay_a.runtime.engine_workspace.execution
    @test (
        execution.settlement_count,
        execution.synchronization_count,
        execution.control_transfer_count,
        execution.snapshot_transfer_count,
        execution.lifecycle_transfer_count,
    ) == (1, 2, 1, 1, 1)

    @test_throws PottsToolkit.NativeCapabilityError init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (_metal_profile(
            global_path, 1; algorithm = Val(:not_a_gpu_algorithm)
        ),),
    )
    @test_throws PottsToolkit.NativeCapabilityError init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (_metal_profile(
            global_path, 1; adaptive = true
        ),),
    )
    @test_throws PottsToolkit.CorePotts.BackendSPI.ProgramCapabilityError init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float64,
        native_profiles = (global_profile,),
    )

    failed = init(
        global_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (_metal_profile(
            global_path, 1; dt = 0.25f0
        ),),
    )
    before_ownership = copy(failed.u.ownership)
    before_native = native_value(failed, global_path, global_x)
    @test_throws PottsToolkit.NativeCapabilityError step!(failed)
    @test failed.runtime.mcs == 0
    @test failed.runtime.ownership == before_ownership
    @test native_value(failed, global_path, global_x) == before_native
    @test failed.runtime.engine_workspace.execution.submitted_mcs == 0
    @test failed.runtime.engine_workspace.execution.committed_mcs == 0

    cell_problem, cell_path, cell_x = _metal_per_cell_fixture()
    cell_profile = _metal_profile(cell_path, 4)
    integrator = init(
        cell_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (cell_profile,),
    )
    step!(integrator)
    saved = checkpoint(integrator)
    restored = init(
        cell_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        checkpoint = saved,
        native_profiles = (cell_profile,),
    )
    step!(integrator)
    step!(restored)
    @test integrator.u.metal_cell_output == restored.u.metal_cell_output
    for slot in 1:2
        identity = CellIdentity(
            slot,
            restored.u.cell_generations[slot],
            restored.u.cell_kinds[slot],
        )
        @test native_value(restored, cell_path, identity, cell_x) ≈ 1.25f0
    end
    report = inspect(restored, Capabilities())
    @test only(report.key.native).execution.mode === :metal_kernel
    @test only(report.evidence.native).suite ===
        :g5h4_per_cell_metal_native_ode_exact_replay
    @test only(report.key.native).evidence.profile_fingerprint ==
        only(report.evidence.native).profile_fingerprint
    restored_execution = restored.runtime.engine_workspace.execution
    @test restored_execution.settlement_count == 1
    @test restored_execution.synchronization_count == 2
    @test restored_execution.control_transfer_count == 1
    @test restored_execution.snapshot_transfer_count == 1

    field_problem, field_path, field_variables, initial_field =
        _metal_field_fixture()
    field_profile = _metal_profile(field_path, 1)
    field_integrator = init(
        field_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (field_profile,),
    )
    @test field_integrator.u.metal_field_output == initial_field
    step!(field_integrator)
    @test field_integrator.u.metal_field_output ≈ initial_field .+ 0.0625f0
    @test field_integrator.u.metal_field_output ≈ reshape([
        native_value(field_integrator, field_path, variable)
        for variable in field_variables
    ], 4, 4)
    field_report = inspect(field_integrator, Capabilities())
    @test only(field_report.evidence.native).suite ===
        :g5h4_native_field_metal_exact_replay
    field_checkpoint = checkpoint(field_integrator)
    field_restored = init(
        field_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        checkpoint = field_checkpoint,
        native_profiles = (field_profile,),
    )
    step!(field_integrator)
    step!(field_restored)
    @test field_integrator.u.metal_field_output ==
        field_restored.u.metal_field_output

    mol_field_problem, mol_field_path, _, _ = _metal_field_fixture(
        capabilities = PottsToolkit._MethodOfLinesNativeCapability(),
    )
    @test_throws PottsToolkit.NativeCapabilityError init(
        mol_field_problem,
        CheckerboardSweepCPM();
        backend = PottsToolkit.MetalBackend(),
        scalar_type = Float32,
        native_profiles = (_metal_profile(mol_field_path, 1),),
    )
end
