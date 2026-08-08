using PottsToolkit
using ModelingToolkit
using ModelingToolkitBase
using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase
using Symbolics
using ModelingToolkitBase:
    @independent_variables, @named, @parameters, @variables

const CAPACITY = 32
const SIDE = 8

@independent_variables perf_t
@variables perf_x(perf_t) = 1.0 perf_drive(perf_t)
perf_D = ModelingToolkitBase.Differential(perf_t)
@named perf_native_system = ModelingToolkit.System(
    [perf_D(perf_x) ~ perf_drive], perf_t
)
@variables perf_potts_drive perf_potts_output
perf_drive_state = CellState(
    perf_potts_drive;
    name = :perf_drive,
    initial = 2.0,
    retirement = RetireTo(0.0),
)
perf_output_state = CellState(
    perf_potts_output;
    name = :perf_output,
    initial = 0.0,
    retirement = RetireTo(0.0),
)
perf_component = NativeComponent(
    perf_native_system;
    name = :perf_island,
    family = ODEComponent(),
    scope = PerCell(),
    time = FixedPhysicalTime(0.0, 0.1),
    inputs = (NativeInput(
        perf_drive, perf_drive_state; value_type = Float64
    ),),
    outputs = (NativeOutput(
        perf_x, perf_output_state; value_type = Float64
    ),),
    lifecycle = PerCellNativeLifecycle(
        creation = PreserveNativeInitialization(),
        transition = Preserve(),
        division = CopyToDaughters(),
    ),
)
perf_cell = CellKind(:perf_cell; extinction = RetireAtZero())
perf_medium = MediumKind(:perf_medium)
perf_source = PottsSystem(
    name = :native_cpu_performance,
    statements = StatementSet((
        Lattice((SIDE, SIDE); boundary = Closed(), max_cells = CAPACITY),
        perf_cell,
        perf_medium,
        perf_drive_state,
        perf_output_state,
        ProposalConstraint(:freeze_native_cpu_performance, false),
        Protocol(Sweep(; temperature = 0.0); name = :main),
    )),
    unknowns = [perf_potts_drive, perf_potts_output],
    native_components = (perf_component,),
)
perf_scheduled = mtkcompile(perf_source)
const PERF_PATH = (:native_cpu_performance, :perf_island)

function performance_problem(live::Int)
    0 <= live <= CAPACITY || throw(ArgumentError("invalid live-cell count"))
    labels = zeros(Int, SIDE, SIDE)
    for slot in 1:live
        labels[slot] = slot
    end
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = fill(perf_cell, live), medium = perf_medium
        ),
        native = (NativeOperatingPoint(
            PERF_PATH; values = (perf_x => 1.0,)
        ),),
    )
    return PottsProblem(perf_scheduled, initial, (0, 5); seed = 0x507)
end

function performance_profile(execution, label)
    return NativeSolveProfile(
        PERF_PATH,
        Tsit5();
        profile_id = "native-cpu-performance-$label",
        execution,
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
end

function measure_case(live, execution, label)
    integrator = init(
        performance_problem(live),
        SequentialCPM();
        native_profiles = (performance_profile(execution, label),),
        save_everystep = false,
    )
    first_seconds = @elapsed step!(integrator)
    GC.gc()
    warm_allocations = @allocated step!(integrator)
    samples = Float64[]
    for _ in 1:3
        push!(samples, @elapsed step!(integrator))
    end
    expected = 1.0 + 2.0 * 0.5
    state = integrator.u
    for slot in findall(!iszero, state.cell_kinds)
        identity = CellIdentity(
            slot, state.cell_generations[slot], state.cell_kinds[slot]
        )
        isapprox(
            native_value(integrator, PERF_PATH, identity, perf_x),
            expected;
            atol = 2e-12,
        ) || error("native CPU benchmark failed its analytic oracle")
    end
    median_seconds = sort(samples)[2]
    return (
        live,
        mode = label,
        first_seconds,
        median_seconds,
        warm_allocations,
        cell_steps_per_second = live / median_seconds,
    )
end

function logical_pool_bytes(capacity, width)
    path = (:benchmark, :logical_pool)
    template = PottsToolkit.NativeLogicalState(
        path,
        ntuple(index -> Float64(index), width),
        (),
        nothing,
        0.0,
        SciMLBase.ReturnCode.Success,
    )
    bank = PottsToolkit.NativeCellStateBank(template, capacity)
    return Base.summarysize(bank)
end

println("native_cpu_component_evidence_v1")
println("julia_threads=", Threads.nthreads())
println("capacity=", CAPACITY)
println("state_memory_bytes:")
for capacity in (4, 32, 256), width in (1, 4, 16)
    println((; capacity, width, bytes = logical_pool_bytes(capacity, width)))
end
println("execution:")
for live in (1, 8, 32)
    println(measure_case(live, SerialNativeExecution(), "serial"))
    for width in (4, 8, 16)
        println(measure_case(
            live, BatchedNativeExecution(width), "batch_width_$width"
        ))
    end
end
