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
