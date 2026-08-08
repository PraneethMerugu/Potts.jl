using Distributed

function _g5h4_distributed_problem()
    cell = CellKind(:distributed_cell; extinction = RetireAtZero())
    medium = MediumKind(:distributed_medium)
    source = PottsSystem(
        name = :distributed_model,
        statements = StatementSet((
            Lattice((5, 5); boundary = Periodic()),
            cell,
            medium,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
    )
    labels = zeros(Int, 5, 5)
    labels[2:4, 2:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    return PottsProblem(mtkcompile(source), initial, (0, 3); seed = 0x54f)
end

@testset "SciML distributed ensemble authority" begin
    problem = _g5h4_distributed_problem()
    ensemble = SciMLBase.EnsembleProblem(problem)
    serial = solve(
        ensemble,
        SequentialCPM(),
        SciMLBase.EnsembleSerial();
        trajectories = 4,
        scalar_type = Float32,
    )

    original_workers = Set(workers())
    project = dirname(Base.active_project())
    added = addprocs(2; exeflags = Cmd([
        "--project=$(project)", "--startup-file=no",
    ]))
    try
        for worker in added
            remotecall_wait(worker) do
                Core.eval(Main, :(using PottsToolkit, SciMLBase))
                nothing
            end
        end
        distributed = solve(
            ensemble,
            SequentialCPM(),
            SciMLBase.EnsembleDistributed();
            trajectories = 4,
            scalar_type = Float32,
        )
        @test [solution.prob.replica for solution in distributed.u] ==
            UInt32[1, 2, 3, 4]
        @test [solution.prob.repeat for solution in distributed.u] ==
            fill(UInt32(1), 4)
        @test all(
            left.t == right.t &&
            all(a.ownership == b.ownership for (a, b) in zip(left.u, right.u))
            for (left, right) in zip(serial.u, distributed.u)
        )

        reduced_problem = SciMLBase.EnsembleProblem(
            problem;
            output_func = (solution, _) -> (
                count(!iszero, last(solution).ownership), false
            ),
            reduction = (accumulator, batch, _) -> begin
                append!(accumulator, batch)
                (accumulator, length(accumulator) >= 2)
            end,
            u_init = Int[],
        )
        reduced = solve(
            reduced_problem,
            SequentialCPM(),
            SciMLBase.EnsembleDistributed();
            trajectories = 8,
            batch_size = 1,
            scalar_type = Float32,
        )
        @test length(reduced.u) == 2

        failing = SciMLBase.EnsembleProblem(
            problem;
            prob_func = (candidate, context) -> begin
                context.sim_id == 2 &&
                    error("intentional distributed trajectory failure")
                candidate
            end,
        )
        @test_throws Exception solve(
            failing,
            SequentialCPM(),
            SciMLBase.EnsembleDistributed();
            trajectories = 3,
            scalar_type = Float32,
        )
    finally
        removable = [worker for worker in added if !(worker in original_workers)]
        isempty(removable) || rmprocs(removable)
    end
end
