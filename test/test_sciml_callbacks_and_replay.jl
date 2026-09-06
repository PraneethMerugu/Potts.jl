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
    @test_throws Potts.PottsUnsavedTimeError endpoints(2)

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
    @test hasproperty(captured.extensions, :Potts)
    @test captured.extensions.Potts.schema == v"2.0.0"
    @test !hasproperty(captured.extensions.Potts, :checksum)
    obsolete_extensions = (PottsToolkit = captured.extensions.Potts,)
    obsolete_identity = CorePotts.ProgramCheckpoint(
        captured.schema,
        captured.program_fingerprint,
        captured.snapshot,
        captured.parameters,
        captured.seed,
        captured.replica,
        captured.repeat,
        captured.accepted,
        captured.rejected,
        captured.null_attempts,
        captured.constraint_rejections,
        captured.energy_rejections,
        captured.retired_cells,
        obsolete_extensions,
        captured.checksum,
    )
    @test_throws ArgumentError Potts._potts_checkpoint_block(obsolete_identity)
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

