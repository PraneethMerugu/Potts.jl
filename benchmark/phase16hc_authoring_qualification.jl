VERSION == v"1.12.6" ||
    error("Phase 16.HC authoring qualification requires Julia 1.12.6; found $VERSION")

using ProcessBigraphs
using Statistics
using TOML

import ProcessBigraphs: StaticComposite, ProcessDeclaration, PortBinding,
    compile_composite, ports, invoke

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    isnothing(argument) ? default :
        ARGS[argument][(length(prefix) + 1):end]
end

struct Phase16HCBenchmarkIncrement <: AbstractProcess end

ports(::Phase16HCBenchmarkIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)

function invoke(
    ::Phase16HCBenchmarkIncrement,
    inputs,
    context,
)
    InvocationResult((
        emit(context, :increment, AdditiveUpdate(), 1),
    ))
end

const SCALE = TimeScale(1)
const EVENTS = parse(Int, option("events", "128"))
const REPETITIONS = parse(Int, option("repetitions", "9"))
const OUTPUT = option("output", "")

EVENTS > 0 || error("--events must be positive")
REPETITIONS >= 5 || error("--repetitions must be at least 5")

function semantic_model()
    compose(:Phase16HCAuthoringBenchmark; scale=SCALE) do model
        state = store!(
            model,
            :state,
            LeafSchema(Int; default=0, update_law=:add),
        )
        increment = mount!(
            model,
            :increment,
            Phase16HCBenchmarkIncrement(),
        )
        schedule!(model, increment, Every(Duration(1, SCALE)))
        connect!(model, state, increment.state, increment.increment)
    end
end

function direct_plan()
    compile_composite(StaticComposite(
        BranchSchema(
            state=LeafSchema(Int; default=0, update_law=:add),
        ),
        Dict(),
        SCALE;
        processes=(
            ProcessDeclaration(
                "increment",
                Phase16HCBenchmarkIncrement(),
                FixedSchedule(Duration(1, SCALE)),
            ),
        ),
        bindings=(
            PortBinding("increment", :state, path("state")),
            PortBinding("increment", :increment, path("state")),
        ),
    ))
end

function median_measure(operation; repetitions=REPETITIONS)
    times = Float64[]
    allocations = Int[]
    for _ in 1:repetitions
        measurement = @timed operation()
        push!(times, measurement.time)
        push!(allocations, measurement.bytes)
    end
    (
        median_seconds=median(times),
        median_allocated_bytes=median(allocations),
    )
end

# Compile and execute once before measurement so these are warm-stage budgets,
# not Julia startup or first-specialization measurements.
warm_model = semantic_model()
warm_lowered = lower(warm_model)
warm_plan = compile(warm_lowered)
warm_runtime = initialize_runtime(warm_plan)
run_until!(warm_runtime, LogicalTime(EVENTS, SCALE))
current_snapshot(warm_runtime)[path("state")] == EVENTS ||
    error("warm semantic execution produced the wrong state")

warm_direct = direct_plan()
model_fingerprint(warm_plan) == model_fingerprint(warm_direct) ||
    error("semantic and direct-IR plans differ in model identity")
structural_fingerprint(warm_plan) == structural_fingerprint(warm_direct) ||
    error("semantic and direct-IR plans differ structurally")
execution_plan_fingerprint(warm_plan) ==
    execution_plan_fingerprint(warm_direct) ||
    error("semantic and direct-IR execution plans differ")

construction = median_measure(semantic_model)
validation = median_measure(() -> validate(warm_model))
lowering = median_measure(() -> lower(warm_model))
compilation = median_measure(() -> compile(warm_lowered))
initialization = median_measure(() -> initialize_runtime(warm_plan))

semantic_runtimes = [initialize_runtime(warm_plan) for _ in 1:REPETITIONS]
direct_runtimes = [initialize_runtime(warm_direct) for _ in 1:REPETITIONS]
semantic_times = Float64[]
direct_times = Float64[]
semantic_allocations = Int[]
direct_allocations = Int[]
target = LogicalTime(EVENTS, SCALE)
for index in 1:REPETITIONS
    semantic_measurement = @timed run_until!(semantic_runtimes[index], target)
    direct_measurement = @timed run_until!(direct_runtimes[index], target)
    push!(semantic_times, semantic_measurement.time)
    push!(direct_times, direct_measurement.time)
    push!(semantic_allocations, semantic_measurement.bytes)
    push!(direct_allocations, direct_measurement.bytes)
end

semantic_execution_seconds = median(semantic_times)
direct_execution_seconds = median(direct_times)
semantic_execution_bytes = median(semantic_allocations)
direct_execution_bytes = median(direct_allocations)
runtime_ratio = semantic_execution_seconds / direct_execution_seconds
allocation_ratio = semantic_execution_bytes /
    max(direct_execution_bytes, 1)

for runtime in semantic_runtimes
    current_snapshot(runtime)[path("state")] == EVENTS ||
        error("semantic execution produced the wrong state")
end
for runtime in direct_runtimes
    current_snapshot(runtime)[path("state")] == EVENTS ||
        error("direct-IR execution produced the wrong state")
end

# These are deliberately workload-specific guardrails, not a fastest-runtime
# claim. Plan equality is the primary no-authoring-penalty invariant; paired
# medians catch accidental hot-path retention of semantic authoring objects.
budgets = Dict(
    "construction_median_seconds_max" => 0.250,
    "construction_median_allocated_bytes_max" => 20_000_000,
    "validation_median_seconds_max" => 0.100,
    "validation_median_allocated_bytes_max" => 10_000_000,
    "lowering_median_seconds_max" => 0.500,
    "lowering_median_allocated_bytes_max" => 50_000_000,
    "compilation_median_seconds_max" => 0.500,
    "compilation_median_allocated_bytes_max" => 50_000_000,
    "initialization_median_seconds_max" => 0.250,
    "initialization_median_allocated_bytes_max" => 20_000_000,
    "warm_runtime_ratio_max" => 1.50,
    "warm_allocation_ratio_max" => 1.10,
)

checks = Dict(
    "construction_time" =>
        construction.median_seconds <=
        budgets["construction_median_seconds_max"],
    "construction_allocations" =>
        construction.median_allocated_bytes <=
        budgets["construction_median_allocated_bytes_max"],
    "validation_time" =>
        validation.median_seconds <=
        budgets["validation_median_seconds_max"],
    "validation_allocations" =>
        validation.median_allocated_bytes <=
        budgets["validation_median_allocated_bytes_max"],
    "lowering_time" =>
        lowering.median_seconds <=
        budgets["lowering_median_seconds_max"],
    "lowering_allocations" =>
        lowering.median_allocated_bytes <=
        budgets["lowering_median_allocated_bytes_max"],
    "compilation_time" =>
        compilation.median_seconds <=
        budgets["compilation_median_seconds_max"],
    "compilation_allocations" =>
        compilation.median_allocated_bytes <=
        budgets["compilation_median_allocated_bytes_max"],
    "initialization_time" =>
        initialization.median_seconds <=
        budgets["initialization_median_seconds_max"],
    "initialization_allocations" =>
        initialization.median_allocated_bytes <=
        budgets["initialization_median_allocated_bytes_max"],
    "steady_runtime" => runtime_ratio <= budgets["warm_runtime_ratio_max"],
    "steady_allocations" =>
        allocation_ratio <= budgets["warm_allocation_ratio_max"],
)

result = Dict(
    "schema_version" => "1.0.0",
    "evidence_id" => "process-bigraph-phase16hc-authoring-performance-v1",
    "julia_version" => string(VERSION),
    "architecture" => string(Sys.ARCH),
    "events" => EVENTS,
    "repetitions" => REPETITIONS,
    "plan_identity_equal" => true,
    "budgets" => budgets,
    "checks" => checks,
    "construction" => Dict(
        "median_seconds" => construction.median_seconds,
        "median_allocated_bytes" =>
            Int(construction.median_allocated_bytes),
    ),
    "validation" => Dict(
        "median_seconds" => validation.median_seconds,
        "median_allocated_bytes" =>
            Int(validation.median_allocated_bytes),
    ),
    "lowering" => Dict(
        "median_seconds" => lowering.median_seconds,
        "median_allocated_bytes" =>
            Int(lowering.median_allocated_bytes),
    ),
    "compilation" => Dict(
        "median_seconds" => compilation.median_seconds,
        "median_allocated_bytes" =>
            Int(compilation.median_allocated_bytes),
    ),
    "initialization" => Dict(
        "median_seconds" => initialization.median_seconds,
        "median_allocated_bytes" =>
            Int(initialization.median_allocated_bytes),
    ),
    "warm_execution" => Dict(
        "semantic_median_seconds" => semantic_execution_seconds,
        "direct_ir_median_seconds" => direct_execution_seconds,
        "semantic_median_allocated_bytes" =>
            Int(semantic_execution_bytes),
        "direct_ir_median_allocated_bytes" =>
            Int(direct_execution_bytes),
        "time_ratio" => runtime_ratio,
        "allocation_ratio" => allocation_ratio,
    ),
)

all(values(checks)) ||
    error("Phase 16.HC authoring performance budget failed: $(checks)")

if !isempty(OUTPUT)
    mkpath(dirname(abspath(OUTPUT)))
    open(OUTPUT, "w") do io
        TOML.print(io, result; sorted=true)
    end
end

println("PHASE16HC_AUTHORING_QUALIFICATION=", result)
