using PottsToolkit
using Statistics

const LW0_SIDE = 32
const LW0_SAMPLES = 12

function lw0_fixture()
    cell = CellKind(:lw0_cell; extinction = ForbidExtinction())
    medium = MediumKind(:lw0_medium)
    source = PottsSystem(
        name = :lw0_corepotts_baseline,
        statements = StatementSet((
            Lattice(
                (LW0_SIDE, LW0_SIDE);
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
    labels = zeros(Int, LW0_SIDE, LW0_SIDE)
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
        (0, LW0_SAMPLES + 1);
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
    for _ in 1:LW0_SAMPLES
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
    # execute_checkerboard_mcs! has one bulk-clear launch plus nine launches
    # per realized color. State-copy, lifecycle, publication, and settlement
    # are deliberately reported separately by the execution counters.
    checkerboard_body_launches = color_count == 0 ? 0 : 1 + 9 * color_count
    execution = color_count == 0 ? nothing : (
        submitted_mcs = workspace.execution.submitted_mcs,
        drained_mcs = workspace.execution.drained_mcs,
        committed_mcs = workspace.execution.committed_mcs,
        materialized_mcs = workspace.execution.materialized_mcs,
        settlements = workspace.execution.settlement_count,
        synchronizations = workspace.execution.synchronization_count,
        control_transfers = workspace.execution.control_transfer_count,
        snapshot_transfers = workspace.execution.snapshot_transfer_count,
        lifecycle_transfers = workspace.execution.lifecycle_transfer_count,
    )
    return (
        algorithm = nameof(typeof(algorithm)),
        median_seconds_per_mcs = median(times),
        minimum_seconds_per_mcs = minimum(times),
        median_allocated_bytes_per_mcs = Int(median(allocations)),
        attempts_per_mcs = LW0_SIDE^2,
        mcs_per_second = inv(median(times)),
        attempted_sites_per_second =
            LW0_SIDE^2 / median(times),
        color_count,
        checkerboard_body_launches_per_mcs = checkerboard_body_launches,
        capability_status = capability.status,
        capability_maturity = capability.maturity,
        capability_fingerprint = capability.key.fingerprint,
        rng_contract_version = core.mechanisms.rng_contract_version,
        rng_lowering_identity = core.mechanisms.rng_lowering_identity,
        execution,
    )
end

system, initial = lw0_fixture()
println("lw0_corepotts_baseline_v1")
println((; julia = VERSION, threads = Threads.nthreads(), side = LW0_SIDE))
println(measure_algorithm(system, initial, SequentialCPM()))
println(measure_algorithm(system, initial, CheckerboardSweepCPM()))
