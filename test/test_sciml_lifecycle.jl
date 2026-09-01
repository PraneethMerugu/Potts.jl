const LIFECYCLE_SII = SymbolicIndexingInterface

@parameters begin
    lifecycle_target = 4.0
    lifecycle_strength = 2.0
    lifecycle_temperature = 3.0
end
@variables lifecycle_marker

function _lifecycle_fixture(
        name::Symbol;
        marker_value = 1.25,
        attempts = AttemptsPerSite(1),
    )
    cell = CellKind(:lifecycle_cell; extinction = RetireAtZero())
    medium = MediumKind(:lifecycle_medium)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice(
                (6, 6);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            SiteState(
                lifecycle_marker;
                name = :lifecycle_marker,
                owner = cell,
                initial = 0.25,
            ),
            Volume(
                cell;
                target = lifecycle_target,
                strength = lifecycle_strength,
            ),
            Observation(:lifecycle_marker_snapshot, lifecycle_marker),
            Protocol(
                Sweep(; temperature = lifecycle_temperature, attempts);
                name = :lifecycle_protocol,
            ),
        )),
        unknowns = [lifecycle_marker],
        parameters = [
            lifecycle_target,
            lifecycle_strength,
            lifecycle_temperature,
        ],
        initial_conditions = Dict(lifecycle_marker => 0.25),
    )
    labels = zeros(Int, 6, 6)
    labels[2:3, 2:3] .= 1
    labels[4:5, 4:5] .= 2
    marker = fill(marker_value, 6, 6)
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [cell, cell],
            medium,
        ),
        values = (lifecycle_marker => marker,),
    )
    return (
        source,
        system = mtkcompile(source),
        initial,
        cell,
        medium,
        labels,
        marker,
    )
end

function _lifecycle_problem(
        fixture;
        tspan = (0, 6),
        seed = 0x6a5b_0002,
        replica = 1,
        repeat = 1,
    )
    return PottsProblem(
        fixture.system,
        fixture.initial,
        tspan;
        p = (
            lifecycle_target => 5.0,
            lifecycle_strength => 1.5,
            lifecycle_temperature => 2.5,
        ),
        seed,
        replica,
        repeat,
    )
end

@testset "public algorithms retain their qualified attempt budget" begin
    fixture = _lifecycle_fixture(
        :lifecycle_nonunit_attempts;
        attempts = AttemptsPerSite(2),
    )
    problem = _lifecycle_problem(fixture; tspan = (0, 1))
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        error = try
            solve(
                problem,
                algorithm;
                backend = CPUBackend(),
                scalar_type = Float32,
                save_start = false,
            )
            nothing
        catch thrown
            thrown
        end
        @test error isa ArgumentError
        @test occursin("implements only AttemptsPerSite(1)",
            sprint(showerror, error))
    end
end

function _lifecycle_same_state(left, right)
    return left.mcs == right.mcs &&
           left.ownership == right.ownership &&
           left.cell_kinds == right.cell_kinds &&
           left.cell_generations == right.cell_generations &&
           left.volumes == right.volumes &&
           left[:lifecycle_marker] == right[:lifecycle_marker] &&
           left[:lifecycle_marker_snapshot] ==
           right[:lifecycle_marker_snapshot]
end

@testset "validation-only problem boundary" begin
    fixture = _lifecycle_fixture(:lifecycle_validation)
    @test is_scheduled(fixture.system)
    @test mtkcompile(fixture.system) === fixture.system
    @test :compile ∉ names(PottsToolkit)
    @test :PottsExecutable ∉ names(PottsToolkit)

    problem = _lifecycle_problem(
        fixture;
        tspan = (1, 7),
        seed = 0x1234,
        replica = 3,
        repeat = 2,
    )
    @test problem isa SciMLBase.AbstractSciMLProblem
    @test problem.system === fixture.system
    @test problem.tspan == (1, 7)
    @test problem.seed == 0x1234
    @test problem.replica == 3
    @test problem.repeat == 2

    problem_fields = fieldnames(typeof(problem))
    @test problem_fields == (
        :system,
        :u0,
        :p,
        :tspan,
        :seed,
        :replica,
        :repeat,
        :policies,
    )
    @test isempty(intersect(
        Set(problem_fields),
        Set((
            :algorithm,
            :alg,
            :engine,
            :backend,
            :scalar_type,
            :plan,
            :core_program,
            :runtime,
            :workspace,
        )),
    ))
    @test all(
        !occursin("CorePotts", string(typeof(getfield(problem, field))))
        for field in problem_fields
    )

    unscheduled = complete(fixture.source)
    @test !is_scheduled(unscheduled)
    @test_throws ArgumentError PottsProblem(
        unscheduled,
        fixture.initial,
        (0, 1);
        seed = 1,
    )
    @test_throws UndefKeywordError PottsProblem(
        fixture.system,
        fixture.initial,
        (0, 1),
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        fixture.initial,
        (0.5, 1);
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        fixture.initial,
        (2, 1);
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        fixture.initial,
        (0, 1);
        seed = -1,
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        fixture.initial,
        (0, 1);
        seed = 1,
        replica = 0,
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        fixture.initial,
        (0, 1);
        seed = 1,
        repeat = 0,
    )

    wrong_shape = PottsInitialState(
        ownership = LabelledCells(
            zeros(Int, 5, 6);
            cells = [],
            medium = fixture.medium,
        ),
    )
    @test_throws ArgumentError PottsProblem(
        fixture.system,
        wrong_shape,
        (0, 1);
        seed = 1,
    )

    unsupported = try
        init(problem, SequentialCPM(); scalar_type = Float16)
        nothing
    catch caught
        caught
    end
    @test unsupported !== nothing
    @test occursin("Float16", sprint(showerror, unsupported))

    three_d_cell = CellKind(:three_d_cell; extinction = RetireAtZero())
    three_d_medium = MediumKind(:three_d_medium)
    three_d_system = mtkcompile(PottsSystem(
        name = :three_d_unsupported,
        statements = StatementSet((
            Lattice((3, 3, 3); boundary = Periodic()),
            three_d_cell,
            three_d_medium,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
    ))
    three_d_problem = PottsProblem(
        three_d_system,
        PottsInitialState(ownership = LabelledCells(
            zeros(Int, 3, 3, 3);
            cells = CellKind[],
            medium = three_d_medium,
        )),
        (0, 1);
        seed = 0x5203,
    )
    three_d_error = try
        init(three_d_problem, SequentialCPM())
        nothing
    catch caught
        caught
    end
    @test three_d_error isa
        PottsToolkit.CorePotts.BackendSPI.ProgramCapabilityError
    @test occursin("dimension=3", sprint(showerror, three_d_error))
    @test fieldnames(typeof(problem)) == problem_fields
end

@testset "late runtime profiles and SciML entry points" begin
    fixture = _lifecycle_fixture(:lifecycle_profiles)
    problem = _lifecycle_problem(fixture; tspan = (0, 2))

    default_integrator = init(
        problem;
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    sequential_integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    checkerboard_integrator = init(
        problem,
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    @test default_integrator.alg isa SequentialCPM
    @test sequential_integrator.alg isa SequentialCPM
    @test checkerboard_integrator.alg isa CheckerboardSweepCPM
    @test default_integrator.backend isa CPUBackend
    @test checkerboard_integrator.backend isa CPUBackend
    @test default_integrator.scalar_type === Float32
    @test sequential_integrator.scalar_type === Float64
    @test checkerboard_integrator.scalar_type === Float32
    @test eltype(LIFECYCLE_SII.parameter_values(default_integrator)) === Float32
    @test eltype(LIFECYCLE_SII.parameter_values(sequential_integrator)) === Float64
    @test LIFECYCLE_SII.getp(problem, lifecycle_target)(problem) == 5.0

    default_solution = solve(
        problem;
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    positional_solution = solve(
        problem,
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    float64_solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test default_solution.alg isa SequentialCPM
    @test positional_solution.alg isa CheckerboardSweepCPM
    @test float64_solution.alg isa SequentialCPM
    @test default_solution.retcode == SciMLBase.ReturnCode.Success
    @test positional_solution.retcode == SciMLBase.ReturnCode.Success
    @test float64_solution.retcode == SciMLBase.ReturnCode.Success
    @test first(default_solution) === default_solution.u[firstindex(default_solution)]
    @test last(default_solution) === default_solution.u[lastindex(default_solution)]
    @test default_solution[1] === default_solution.u[1]
    @test collect(default_solution) == default_solution.u
    @test default_solution.provenance.scheduled ==
          positional_solution.provenance.scheduled ==
          float64_solution.provenance.scheduled
    @test default_solution.provenance.runtime_profile !=
          positional_solution.provenance.runtime_profile
    @test default_solution.provenance.runtime_profile !=
          float64_solution.provenance.runtime_profile
    @test default_solution.provenance.algorithm === :SequentialCPM
    @test positional_solution.provenance.algorithm === :CheckerboardSweepCPM
    @test default_solution.provenance.backend === :CPUBackend
    @test default_solution.provenance.scalar_type === Float32

    @test_throws ArgumentError solve(problem; adaptive = true)
    @test_throws ArgumentError init(
        problem,
        SequentialCPM();
        backend = MetalBackend(),
    )
end

@testset "complete remake dimensions" begin
    fixture = _lifecycle_fixture(:lifecycle_remake)
    problem = _lifecycle_problem(fixture)
    replacement = fill(7.0, 6, 6)
    remade = remake(
        problem;
        u0 = Dict(lifecycle_marker => replacement),
        p = (
            lifecycle_target => 6.5,
            lifecycle_strength => 2.25,
            lifecycle_temperature => 1.75,
        ),
        tspan = (2, 5),
        seed = 0xbeef,
        replica = 4,
        repeat = 3,
        policies = (audit = :strict,),
    )
    replacement .= -1
    @test remade.system === problem.system
    @test remade.tspan == (2, 5)
    @test remade.seed == 0xbeef
    @test remade.replica == 4
    @test remade.repeat == 3
    @test remade.policies == (audit = :strict,)
    @test LIFECYCLE_SII.getp(remade, lifecycle_target)(remade) == 6.5
    @test LIFECYCLE_SII.getp(problem, lifecycle_target)(problem) == 5.0

    integrator = init(remade; scalar_type = Float32, save_start = false)
    @test integrator.t == 2
    @test all(==(7.0f0), integrator.u[:lifecycle_marker])
    @test LIFECYCLE_SII.getp(integrator, lifecycle_target)(integrator) == 6.5f0
    @test all(==(1.25), LIFECYCLE_SII.state_values(problem, 1))

    @test_throws ArgumentError remake(problem; algorithm = SequentialCPM())
    @test_throws ArgumentError remake(problem; backend = CPUBackend())
    @test_throws ArgumentError remake(
        problem;
        u0 = PottsInitialState(
            ownership = LabelledCells(
                zeros(Int, 5, 5);
                cells = [],
                medium = fixture.medium,
            ),
        ),
    )
end

@testset "SymbolicIndexingInterface contract" begin
    fixture = _lifecycle_fixture(:lifecycle_sii)
    system = fixture.system
    problem = _lifecycle_problem(fixture; tspan = (0, 3))
    integrator = init(
        problem;
        scalar_type = Float32,
        save_start = false,
        observables = (:lifecycle_marker_snapshot,),
    )

    @test LIFECYCLE_SII.symbolic_container(system) === system
    @test LIFECYCLE_SII.symbolic_container(problem) === system
    @test LIFECYCLE_SII.symbolic_container(integrator) === system
    @test LIFECYCLE_SII.is_parameter(system, lifecycle_target)
    @test LIFECYCLE_SII.parameter_index(system, lifecycle_target) == 1
    @test any(isequal(lifecycle_target), LIFECYCLE_SII.parameter_symbols(system))
    @test LIFECYCLE_SII.is_variable(system, lifecycle_marker)
    @test LIFECYCLE_SII.variable_index(system, lifecycle_marker) == 1
    @test any(isequal(lifecycle_marker), LIFECYCLE_SII.variable_symbols(system))
    @test LIFECYCLE_SII.is_observed(system, :lifecycle_marker_snapshot)
    @test :lifecycle_marker_snapshot in
          LIFECYCLE_SII.all_variable_symbols(system)
    @test :mcs in LIFECYCLE_SII.independent_variable_symbols(system)
    @test any(isequal(lifecycle_target), LIFECYCLE_SII.all_symbols(system))
    @test LIFECYCLE_SII.default_values(system)[lifecycle_marker] == 0.25

    problem_states = LIFECYCLE_SII.state_values(problem)
    @test isequal(LIFECYCLE_SII.state_values(problem, :), problem_states)
    @test length(problem_states) == 2
    @test problem_states[1] == fixture.marker
    @test ismissing(problem_states[2])
    state_index = LIFECYCLE_SII.variable_index(system, lifecycle_marker)
    @test hasmethod(
        LIFECYCLE_SII.state_values,
        Tuple{typeof(problem), typeof(state_index)},
    )
    @test LIFECYCLE_SII.state_values(problem, state_index) == fixture.marker
    @test LIFECYCLE_SII.state_values(integrator, state_index) ==
          fill(1.25f0, 6, 6)
    @test isequal(
        LIFECYCLE_SII.state_values(integrator, :),
        LIFECYCLE_SII.state_values(integrator),
    )
    @test LIFECYCLE_SII.current_time(problem) == 0
    @test LIFECYCLE_SII.current_time(integrator) == 0

    target_getter = LIFECYCLE_SII.getp(system, lifecycle_target)
    marker_getter = LIFECYCLE_SII.getsym(system, lifecycle_marker)
    @test target_getter(problem) == 5.0
    @test target_getter(integrator) == 5.0f0
    @test marker_getter(problem) == fixture.marker
    @test marker_getter(integrator) == fill(1.25f0, 6, 6)

    target_setter = LIFECYCLE_SII.setp(integrator, lifecycle_target)
    target_setter(integrator, 6.0)
    @test target_getter(integrator) == 6.0f0
    transaction = LIFECYCLE_SII.setp(
        integrator,
        (lifecycle_target, lifecycle_strength),
    )
    @test_throws ArgumentError transaction(integrator, (7.0, Inf))
    @test target_getter(integrator) == 6.0f0
    @test LIFECYCLE_SII.getp(system, lifecycle_strength)(integrator) == 1.5f0
    transaction(integrator, (7.0, 2.0))
    @test target_getter(integrator) == 7.0f0
    @test LIFECYCLE_SII.getp(system, lifecycle_strength)(integrator) == 2.0f0

    immutable_setter = LIFECYCLE_SII.setp(problem, lifecycle_target)
    @test_throws ArgumentError immutable_setter(problem, 9.0)
    @test target_getter(problem) == 5.0

    solution = solve!(integrator)
    @test LIFECYCLE_SII.symbolic_container(solution) === system
    @test LIFECYCLE_SII.is_timeseries(solution) isa LIFECYCLE_SII.Timeseries
    @test length(LIFECYCLE_SII.state_values(solution)) == length(solution.t)
    @test isequal(
        LIFECYCLE_SII.state_values(solution, :),
        LIFECYCLE_SII.state_values(solution),
    )
    @test LIFECYCLE_SII.state_values(solution, 1) ==
          LIFECYCLE_SII.state_values(solution)[1]
    @test LIFECYCLE_SII.current_time(solution, 1) == solution.t[1]
    @test LIFECYCLE_SII.current_time(solution, :) ==
        LIFECYCLE_SII.current_time(solution)
    @test marker_getter(solution, 1) == solution.u[1][:lifecycle_marker]
    observation_getter = LIFECYCLE_SII.getsym(
        system,
        :lifecycle_marker_snapshot,
    )
    @test observation_getter(solution, 1) ==
          solution.u[1][:lifecycle_marker_snapshot]
    @test target_getter(solution) == 7.0f0
end

@testset "saving, callbacks, and termination" begin
    fixture = _lifecycle_fixture(:lifecycle_callbacks)
    problem = _lifecycle_problem(fixture; tspan = (0, 4))

    endpoints = solve(
        problem;
        scalar_type = Float32,
        observables = (:lifecycle_marker_snapshot,),
    )
    @test endpoints.t == [0, 4]
    @test endpoints(4) === last(endpoints.u)
    @test endpoints(4; idxs = :lifecycle_marker) ==
          endpoints.u[end][:lifecycle_marker]
    @test_throws PottsToolkit.PottsUnsavedTimeError endpoints(2)

    every_step = solve(
        problem;
        scalar_type = Float32,
        save_everystep = true,
    )
    @test every_step.t == collect(0:4)
    selected = solve(
        problem;
        scalar_type = Float32,
        saveat = (1, 3),
        save_start = false,
        save_end = false,
    )
    @test selected.t == [1, 3]
    @test_throws ArgumentError solve(problem; saveat = (1, 1))
    @test_throws ArgumentError solve(problem; saveat = (1, 2.5))

    initialized_at = Int[]
    finalized_at = Int[]
    affected_at = Int[]
    duplicate_callback = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 2,
        integrator -> push!(affected_at, integrator.t);
        initialize = (_, _, time, _) -> push!(initialized_at, time),
        finalize = (_, _, time, _) -> push!(finalized_at, time),
        save_positions = (true, true),
    )
    duplicate_solution = solve(
        problem;
        scalar_type = Float32,
        callback = duplicate_callback,
        save_start = false,
        save_end = false,
        observables = (:lifecycle_marker_snapshot,),
    )
    @test initialized_at == [0]
    @test affected_at == [2]
    @test finalized_at == [4]
    @test duplicate_solution.t == [2, 2]
    @test duplicate_solution.u[1] !== duplicate_solution.u[2]
    @test duplicate_solution.u[1].ownership !==
          duplicate_solution.u[2].ownership
    @test duplicate_solution(2) === duplicate_solution.u[2]

    termination_finalized = Int[]
    termination_callback = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 2,
        terminate!;
        finalize = (_, _, time, _) -> push!(termination_finalized, time),
        save_positions = (false, false),
    )
    termination_integrator = init(
        problem;
        scalar_type = Float32,
        callback = termination_callback,
    )
    terminated = solve!(termination_integrator)
    @test terminated.retcode == SciMLBase.ReturnCode.Terminated
    @test terminated.t == [0, 2]
    @test last(terminated).mcs == 2
    @test termination_finalized == [2]
    @test_throws ArgumentError step!(termination_integrator)

    continuous = SciMLBase.ContinuousCallback(
        (_, time, _) -> Float64(time - 1),
        _ -> nothing,
    )
    @test_throws ArgumentError init(problem; callback = continuous)
end

@testset "checkpoint identity and exact continuation" begin
    fixture = _lifecycle_fixture(:lifecycle_checkpoint)
    problem = _lifecycle_problem(fixture; tspan = (0, 6), repeat = 2)
    algorithm = SequentialCPM()

    continued_integrator = init(
        problem,
        algorithm;
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
        observables = (:lifecycle_marker_snapshot,),
    )
    step!(continued_integrator)
    step!(continued_integrator)
    LIFECYCLE_SII.setp(
        continued_integrator,
        lifecycle_target,
    )(continued_integrator, 6.25)
    step!(continued_integrator)
    captured = checkpoint(continued_integrator)
    @test captured isa PottsCheckpoint
    @test captured.schema == v"3.0.0"
    @test length(captured.checksum) == 64
    @test hasproperty(captured.extensions, :PottsToolkit)
    @test !hasproperty(captured.extensions.PottsToolkit, :checksum)
    restore_callback = SciMLBase.DiscreteCallback(
        (_, _, _) -> false,
        _ -> nothing;
        save_positions = (false, false),
    )
    @test_throws ArgumentError init(
        problem,
        algorithm;
        backend = CPUBackend(),
        scalar_type = Float32,
        checkpoint = captured,
        callback = restore_callback,
        save_start = false,
        observables = (:lifecycle_marker_snapshot,),
    )

    continued = solve!(continued_integrator)
    resumed_integrator = init(
        remake(problem; p = (
            lifecycle_target => 99.0,
            lifecycle_strength => 99.0,
            lifecycle_temperature => 99.0,
        )),
        algorithm;
        backend = CPUBackend(),
        scalar_type = Float32,
        checkpoint = captured,
        save_start = false,
        observables = (:lifecycle_marker_snapshot,),
    )
    @test LIFECYCLE_SII.getp(
        resumed_integrator,
        lifecycle_target,
    )(resumed_integrator) == 6.25f0
    resumed = solve!(resumed_integrator)
    @test continued.retcode == SciMLBase.ReturnCode.Success
    @test resumed.retcode == SciMLBase.ReturnCode.Success
    @test _lifecycle_same_state(last(continued), last(resumed))
    @test continued.stats.candidate_attempts == resumed.stats.candidate_attempts
    @test continued.stats.accepted == resumed.stats.accepted
    @test continued.stats.rejected == resumed.stats.rejected
    @test checkpoint(continued_integrator).checksum ==
          checkpoint(resumed_integrator).checksum

    @test_throws ArgumentError init(
        problem,
        CheckerboardSweepCPM();
        scalar_type = Float32,
        checkpoint = captured,
    )
    @test_throws ArgumentError init(
        problem,
        SequentialCPM();
        scalar_type = Float64,
        checkpoint = captured,
    )

    other = _lifecycle_fixture(:lifecycle_checkpoint_other)
    other_problem = _lifecycle_problem(
        other;
        tspan = problem.tspan,
        seed = problem.seed,
        replica = problem.replica,
        repeat = problem.repeat,
    )
    @test_throws ArgumentError init(
        other_problem,
        algorithm;
        scalar_type = Float32,
        checkpoint = captured,
    )
    @test_throws ArgumentError init(
        remake(problem; repeat = 3),
        algorithm;
        scalar_type = Float32,
        checkpoint = captured,
    )
    @test_throws ArgumentError init(
        remake(problem; replica = 2),
        algorithm;
        scalar_type = Float32,
        checkpoint = captured,
    )
    @test_throws ArgumentError init(
        remake(problem; seed = problem.seed + 1),
        algorithm;
        scalar_type = Float32,
        checkpoint = captured,
    )
end

@testset "ensemble replica and repeat identity" begin
    fixture = _lifecycle_fixture(:lifecycle_ensemble)
    problem = _lifecycle_problem(fixture; tspan = (0, 2))
    exposed_u0 = problem.u0
    fill!(exposed_u0.ownership.labels, Int32(0))
    fill!(last(only(exposed_u0.values)), -99.0)
    ensemble = SciMLBase.EnsembleProblem(problem)
    serial = solve(
        ensemble,
        SequentialCPM(),
        SciMLBase.EnsembleSerial();
        trajectories = 3,
        backend = CPUBackend(),
        scalar_type = Float32,
        observables = (:lifecycle_marker_snapshot,),
    )
    threaded = solve(
        ensemble,
        SequentialCPM(),
        SciMLBase.EnsembleThreads();
        trajectories = 3,
        backend = CPUBackend(),
        scalar_type = Float32,
        observables = (:lifecycle_marker_snapshot,),
    )
    @test length(serial.u) == 3
    @test [solution.prob.replica for solution in serial.u] == UInt32[1, 2, 3]
    @test [solution.prob.repeat for solution in serial.u] == UInt32[1, 1, 1]
    @test [solution.provenance.replica for solution in serial.u] ==
          UInt32[1, 2, 3]
    @test [solution.provenance.repeat for solution in serial.u] ==
          UInt32[1, 1, 1]
    @test all(
        count(>(Int32(0)), first(solution).ownership) == 8 &&
        all(==(1.25f0), first(solution)[:lifecycle_marker])
        for solution in (serial.u..., threaded.u...)
    )
    @test all(
        _lifecycle_same_state(last(left), last(right))
        for (left, right) in zip(serial.u, threaded.u)
    )

    rerun_ensemble = SciMLBase.EnsembleProblem(
        problem;
        output_func = (solution, context) -> (
            solution,
            context.repeat == 1,
        ),
    )
    rerun = solve(
        rerun_ensemble,
        SequentialCPM(),
        SciMLBase.EnsembleSerial();
        trajectories = 1,
        backend = CPUBackend(),
        scalar_type = Float32,
        observables = (:lifecycle_marker_snapshot,),
    )
    rerun_solution = only(rerun.u)
    @test rerun_solution.prob.replica == 1
    @test rerun_solution.prob.repeat == 2
    @test rerun_solution.provenance.replica == 1
    @test rerun_solution.provenance.repeat == 2
end

@testset "surfaced callback failure" begin
    fixture = _lifecycle_fixture(:lifecycle_failure)
    problem = _lifecycle_problem(fixture; tspan = (0, 3))
    failing_callback = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 1,
        _ -> error("intentional callback failure");
        save_positions = (false, false),
    )
    integrator = init(
        problem;
        scalar_type = Float32,
        callback = failing_callback,
        save_start = false,
    )
    failure = try
        step!(integrator)
        nothing
    catch caught
        caught
    end
    @test failure isa ErrorException
    @test occursin("intentional callback failure", sprint(showerror, failure))
    @test integrator.retcode == SciMLBase.ReturnCode.Failure
    @test integrator.failure_report === failure
    @test_throws ArgumentError step!(integrator)
    @test_throws ArgumentError checkpoint(integrator)

    solution = solve!(integrator)
    @test solution.retcode == SciMLBase.ReturnCode.Failure
    @test solution.failure_report === failure
    @test last(solution.t) == 1

    finalized = Pair{Symbol, Int}[]
    mutate_then_save = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 1,
        callback_integrator -> LIFECYCLE_SII.setp(
            callback_integrator,
            lifecycle_target,
        )(callback_integrator, 8.0);
        finalize = (_, _, time, _) -> push!(
            finalized,
            :mutating_callback => time,
        ),
        save_positions = (true, true),
    )
    fail_after_mutation = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 1,
        _ -> error("failure after an earlier callback mutation");
        finalize = (_, _, time, _) -> push!(
            finalized,
            :failing_callback => time,
        ),
        save_positions = (false, false),
    )
    atomic_integrator = init(
        problem;
        scalar_type = Float32,
        callback = SciMLBase.CallbackSet(
            mutate_then_save,
            fail_after_mutation,
        ),
        save_start = true,
        save_end = false,
    )
    atomic_failure = try
        solve!(atomic_integrator)
        nothing
    catch caught
        caught
    end
    @test atomic_failure isa ErrorException
    @test occursin("earlier callback mutation", sprint(showerror, atomic_failure))
    @test LIFECYCLE_SII.getp(
        atomic_integrator,
        lifecycle_target,
    )(atomic_integrator) == 5.0f0
    @test finalized == [
        :mutating_callback => 1,
        :failing_callback => 1,
    ]
    @test atomic_integrator.retcode == SciMLBase.ReturnCode.Failure
    @test_throws ArgumentError checkpoint(atomic_integrator)

    atomic_solution = solve!(atomic_integrator)
    @test atomic_solution.retcode == SciMLBase.ReturnCode.Failure
    @test atomic_solution.t == [0]
    @test finalized == [
        :mutating_callback => 1,
        :failing_callback => 1,
    ]

    no_op_callback = SciMLBase.DiscreteCallback(
        (_, _, _) -> false,
        _ -> nothing;
        save_positions = (false, false),
    )
    no_op_integrator = init(
        problem; scalar_type = Float32, callback = no_op_callback
    )
    @test no_op_integrator.capability_report.key.outer_events.mode ===
        :imperative_host_discrete_callbacks
    @test no_op_integrator.capability_report.key.outer_events.state_codec ===
        :unavailable
    @test no_op_integrator.capability_report.key.checkpoint ===
        :unsupported_outer_callback_state
    @test no_op_integrator.capability_report.status ===
        CorePotts.BackendSPI.Supported
    @test !no_op_integrator.capability_report.exact_replay
    @test_throws ArgumentError checkpoint(no_op_integrator)

    callback_state = Ref(0)
    stateful_callback = SciMLBase.DiscreteCallback(
        (_, _, _) -> false,
        _ -> (callback_state[] += 1);
        save_positions = (false, false),
    )
    stateful_integrator = init(
        problem; scalar_type = Float32, callback = stateful_callback
    )
    @test_throws ArgumentError checkpoint(stateful_integrator)

    terminated_integrator = init(problem; scalar_type = Float32)
    step!(terminated_integrator)
    terminate!(terminated_integrator)
    @test_throws ArgumentError checkpoint(terminated_integrator)
end
