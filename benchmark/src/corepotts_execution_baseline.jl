using PottsToolkit
using Statistics

import LocalMath

const COREPOTTS_BASELINE_SIDE = 32
const COREPOTTS_BASELINE_SAMPLES = 12

function corepotts_baseline_fixture()
    cell = CellKind(:corepotts_baseline_cell; extinction = ForbidExtinction())
    medium = MediumKind(:corepotts_baseline_medium)
    source = PottsSystem(
        name = :corepotts_execution_baseline,
        statements = StatementSet((
            Lattice(
                (COREPOTTS_BASELINE_SIDE, COREPOTTS_BASELINE_SIDE);
                boundary = Periodic(),
                max_cells = 4,
            ),
            cell,
            medium,
            Volume(cell; target = 64.0, strength = 1.0),
            Protocol(
                Sweep(; attempts = AttemptsPerSite(1), temperature = 2.0);
                name = :main,
            ),
        )),
    )
    labels = zeros(Int, COREPOTTS_BASELINE_SIDE, COREPOTTS_BASELINE_SIDE)
    labels[13:20, 13:20] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    return mtkcompile(complete(source)), initial
end

function measure_algorithm(system, initial, algorithm)
    problem = PottsProblem(
        system,
        initial,
        (0, COREPOTTS_BASELINE_SAMPLES + 1);
        seed = 0x1a00_0001,
        replica = 2,
        repeat = 3,
    )
    integrator = init(
        problem,
        algorithm;
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
        save_end = false,
    )
    step!(integrator)
    times = Float64[]
    allocations = Int[]
    for _ in 1:COREPOTTS_BASELINE_SAMPLES
        GC.gc()
        sample = @timed step!(integrator)
        push!(times, sample.time)
        push!(allocations, sample.bytes)
    end
    capability = inspect(integrator, Capabilities())
    core = capability.key.core
    runtime = integrator.runtime
    workspace = runtime.engine_workspace
    color_count = algorithm isa CheckerboardSweepCPM ?
                  Int(runtime.program.checkerboard_plan.color_count) : 0
    position = color_count == 0 ? nothing : workspace.core.execution
    checkerboard_body_launches = if color_count == 0
        0
    else
        clear_report = LocalMath.inspect(
            workspace.clear_report[1])
        color_mechanics = LocalMath.inspect(
            workspace.color_laws.prepared[1])
        clear_report.planning.base_provider_launch_count +
            color_count * color_mechanics.planning.base_provider_launch_count
    end
    execution = color_count == 0 ? nothing : (
        submitted_mcs = position.submitted_mcs,
        drained_mcs = position.drained_mcs,
        committed_mcs = position.committed_mcs,
        materialized_mcs = position.materialized_mcs,
        settlements = position.settlement_count,
        synchronizations = position.synchronization_count,
        control_transfers = position.control_transfer_count,
        snapshot_transfers = position.snapshot_transfer_count,
        lifecycle_transfers = position.lifecycle_transfer_count,
    )
    return (
        algorithm = nameof(typeof(algorithm)),
        median_seconds_per_mcs = median(times),
        minimum_seconds_per_mcs = minimum(times),
        median_allocated_bytes_per_mcs = Int(median(allocations)),
        attempts_per_mcs = COREPOTTS_BASELINE_SIDE^2,
        mcs_per_second = inv(median(times)),
        attempted_sites_per_second =
            COREPOTTS_BASELINE_SIDE^2 / median(times),
        color_count,
        checkerboard_body_launches_per_mcs = checkerboard_body_launches,
        capability_status = capability.status,
        exact_replay = capability.exact_replay,
        rng_contract_version = core.mechanisms.rng_contract_version,
        rng_lowering_identity = core.mechanisms.rng_lowering_identity,
        execution,
    )
end

system, initial = corepotts_baseline_fixture()
println("corepotts_execution_baseline_v1")
println((; julia = VERSION, threads = Threads.nthreads(), side = COREPOTTS_BASELINE_SIDE))
println(measure_algorithm(system, initial, SequentialCPM()))
println(measure_algorithm(system, initial, CheckerboardSweepCPM()))
