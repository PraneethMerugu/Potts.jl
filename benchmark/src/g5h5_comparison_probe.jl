using PottsToolkit
using Serialization
using Statistics

const IS_G5H0 = isdefined(PottsToolkit, :SequentialEngine)
const SIDE = 32

function comparison_source()
    cell = CellKind(:comparison_cell; extinction=ForbidExtinction())
    medium = MediumKind(:comparison_medium)
    anchor = CellBinding(:comparison_anchor)
    dormant = LifecycleProcess(
        :dormant_transition;
        domain=cells(cell),
        anchor,
        expression=false,
        effects=(Transition(
            anchor,
            cell;
            on_inadmissible=ErrorOnInadmissible(),
        ),),
        cadence=EveryMCS(),
    )
    source = PottsSystem(
        name=:g5h5_comparison,
        statements=StatementSet((
            Lattice((SIDE, SIDE); boundary=Periodic(), max_cells=4),
            cell,
            medium,
            Volume(cell; target=64.0, strength=1.0),
            dormant,
            Protocol(Sweep(; temperature=2.0); name=:main),
        )),
    )
    labels = zeros(Int, SIDE, SIDE)
    labels[13:20, 13:20] .= 1
    initial = PottsInitialState(
        ownership=LabelledCells(labels; cells=[cell], medium),
    )
    return source, initial
end

function structural_compile(completed)
    if IS_G5H0
        return PottsToolkit.compile(
            completed;
            engine=PottsToolkit.SequentialEngine(),
            backend=CPUBackend(),
            scalar_type=Float32,
        )
    end
    return mtkcompile(completed)
end

function initialize(problem)
    if IS_G5H0
        return init(problem; save_start=false, save_end=false)
    end
    return init(
        problem,
        SequentialCPM();
        backend=CPUBackend(),
        scalar_type=Float32,
        save_start=false,
        save_end=false,
    )
end

source, initial = comparison_source()
completion = @timed complete(source)
structural = @timed structural_compile(completion.value)
problem_build = @timed PottsProblem(
    structural.value, initial, (0, 12); seed=0x5150
)
initialization = @timed initialize(problem_build.value)
integrator = initialization.value

step!(integrator)
step_times = Float64[]
step_allocations = Int[]
for _ in 1:7
    GC.gc()
    sample = @timed step!(integrator)
    push!(step_times, sample.time)
    push!(step_allocations, sample.bytes)
end

checkpoint(integrator)
GC.gc()
checkpoint_sample = @timed checkpoint(integrator)
checkpoint_value = checkpoint_sample.value
buffer = IOBuffer()
serialize(buffer, checkpoint_value)

runtime = integrator.runtime
lifecycle_workspace_bytes = hasproperty(runtime, :lifecycle_workspace) ?
    Base.summarysize(getproperty(runtime, :lifecycle_workspace)) : missing

println("g5h5_comparison_probe_v1")
println("candidate=", IS_G5H0 ? "g5h0" : "final")
println("julia=", VERSION)
println("threads=", Threads.nthreads())
println("complete_seconds=", completion.time)
println("complete_compile_seconds=", completion.compile_time)
println("complete_allocated_bytes=", completion.bytes)
println("structural_seconds=", structural.time)
println("structural_compile_seconds=", structural.compile_time)
println("structural_allocated_bytes=", structural.bytes)
println("problem_seconds=", problem_build.time)
println("problem_allocated_bytes=", problem_build.bytes)
println("init_seconds=", initialization.time)
println("init_compile_seconds=", initialization.compile_time)
println("init_allocated_bytes=", initialization.bytes)
println("median_seconds_per_mcs=", median(step_times))
println("minimum_seconds_per_mcs=", minimum(step_times))
println("median_allocated_bytes_per_mcs=", median(step_allocations))
println("runtime_heap_bytes=", Base.summarysize(runtime))
println("lifecycle_workspace_heap_bytes=", lifecycle_workspace_bytes)
println("checkpoint_seconds=", checkpoint_sample.time)
println("checkpoint_allocated_bytes=", checkpoint_sample.bytes)
println("checkpoint_heap_bytes=", Base.summarysize(checkpoint_value))
println("checkpoint_serialized_bytes=", sizeof(take!(buffer)))
