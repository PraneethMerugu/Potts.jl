using Dagger
using PottsToolkit
using SciMLBase

function benchmark_problem()
    cell = CellKind(:dagger_cell; extinction = RetireAtZero())
    medium = MediumKind(:dagger_medium)
    source = PottsSystem(
        name = :dagger_model,
        statements = StatementSet((
            Lattice((48, 48); boundary = Periodic()),
            cell,
            medium,
            Volume(cell; target = 64.0, strength = 1.0),
            Protocol(Sweep(; temperature = 8.0); name = :main),
        )),
    )
    labels = zeros(Int, 48, 48)
    labels[21:28, 21:28] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    return PottsProblem(mtkcompile(source), initial, (0, 20); seed = 0x550)
end

function solve_one(problem)
    return solve(problem, SequentialCPM(); scalar_type = Float32)
end

function dagger_solve(problem, trajectories)
    tasks = [Dagger.spawn(solve_one, remake(problem; replica = index))
        for index in 1:trajectories]
    return fetch.(tasks)
end

function measurement(f)
    GC.gc()
    timed = @timed f()
    return (
        value = timed.value,
        seconds = timed.time,
        bytes = timed.bytes,
        gctime = timed.gctime,
    )
end

problem = benchmark_problem()
trajectories = 8
ensemble = SciMLBase.EnsembleProblem(problem)

# Warm all paths before recording scheduler overhead.
solve(ensemble, SequentialCPM(), SciMLBase.EnsembleSerial();
    trajectories = 2, scalar_type = Float32)
solve(ensemble, SequentialCPM(), SciMLBase.EnsembleThreads();
    trajectories = 2, scalar_type = Float32)
dagger_solve(problem, 2)

serial = measurement() do
    solve(ensemble, SequentialCPM(), SciMLBase.EnsembleSerial();
        trajectories, scalar_type = Float32)
end
threaded = measurement() do
    solve(ensemble, SequentialCPM(), SciMLBase.EnsembleThreads();
        trajectories, scalar_type = Float32)
end
dagger = measurement() do
    dagger_solve(problem, trajectories)
end

serial_states = [last(solution).ownership for solution in serial.value.u]
threaded_states = [last(solution).ownership for solution in threaded.value.u]
dagger_states = [last(solution).ownership for solution in dagger.value]
serial_states == threaded_states == dagger_states ||
    error("Dagger/SciML comparison changed trajectory semantics")

println((;
    julia = VERSION,
    threads = Threads.nthreads(),
    dagger = Base.pkgversion(Dagger),
    trajectories,
    lattice = (48, 48),
    mcs = 20,
    serial = Base.structdiff(serial, (; value = serial.value)),
    threaded = Base.structdiff(threaded, (; value = threaded.value)),
    dagger_tasks = Base.structdiff(dagger, (; value = dagger.value)),
    threaded_speedup = serial.seconds / threaded.seconds,
    dagger_speedup = serial.seconds / dagger.seconds,
))
