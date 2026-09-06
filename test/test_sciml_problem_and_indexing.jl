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
@testset "validation-only problem boundary" begin
    fixture = _lifecycle_fixture(:lifecycle_validation)
    @test is_scheduled(fixture.system)
    @test mtkcompile(fixture.system) === fixture.system
    @test :compile ∉ names(Potts)
    @test :PottsExecutable ∉ names(Potts)

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
        Potts.CorePotts.BackendSPI.ProgramCapabilityError
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
