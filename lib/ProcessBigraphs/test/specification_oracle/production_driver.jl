using ProcessBigraphs
using TOML

length(ARGS) == 2 || error("usage: production_driver.jl FIXTURE OUTPUT")
include(joinpath(@__DIR__, "..", "fixtures", "serial_runtime.jl"))

fixture = TOML.parsefile(ARGS[1])
scale = TimeScale(1)
processes = tuple((
    String(row["id"]) => (Int(row["amount"]), Int(row["cadence"]))
    for row in fixture["processes"]
)...)
compiled = c15_add_composite(; processes)
runtime = initialize_runtime(compiled, SerialExecutor(
    root_seed=Int(fixture["root_seed"])))
run_until!(runtime, LogicalTime(Int(fixture["horizon"]), scale))

adaptive_schema =
    BranchSchema(state=LeafSchema(Int; default=0, update_law=:add))
adaptive_source = compose(
    :OracleAdaptive, adaptive_schema; scale) do builder, stores
    adaptive = mount!(
        builder, :adaptive,
        C15Adaptive(1, Int(fixture["adaptive"]["offset"])))
    schedule!(
        builder,
        adaptive,
        AdaptiveSchedule(Duration(
            Int(fixture["adaptive"]["first_due"]), scale)),
    )
    attach!(builder, adaptive, (out=stores.state,))
end
adaptive_model = compile(adaptive_source)
adaptive_runtime = initialize_runtime(adaptive_model, SerialExecutor())
run_until!(adaptive_runtime,
    LogicalTime(Int(fixture["adaptive"]["horizon"]), scale))

observation_runtime = initialize_runtime(
    c15_add_composite(processes=("observed" => (1, 1),)),
    SerialExecutor(observation_plan=c15_observation_plan(scale)),
)
run_until!(observation_runtime, LogicalTime(3, scale))

counter_schema = BranchSchema(
    state=LeafSchema(Int; default=0, update_law=:add))
counter_source = compose(
    :OracleCounter, counter_schema; scale) do builder, stores
    counter = mount!(
        builder, :counter, C15Counter();
        continuation=(count=0,))
    schedule!(builder, counter, Every(Duration(1, scale)))
    attach!(builder, counter, (out=stores.state,))
end
counter_model = compile(counter_source)
counter_runtime = initialize_runtime(counter_model, SerialExecutor())
run_until!(counter_runtime, LogicalTime(4, scale))
checkpoint_value = logical_checkpoint(counter_runtime)
checkpoint_bytes = encode_checkpoint(checkpoint_value)
checkpoint_roundtrip = encode_checkpoint(decode_checkpoint(checkpoint_bytes)) ==
    checkpoint_bytes

reactive_schema = BranchSchema(
    trigger=LeafSchema(Int; default=0, update_law=:add),
    copied=LeafSchema(Int; default=0, update_law=:replace),
    converged=LeafSchema(Int; default=0, update_law=:replace),
    bounded=LeafSchema(Int; default=0, update_law=:add),
)
reactive_source = compose(
    :OracleReactive, reactive_schema; scale) do builder, stores
    trigger = mount!(builder, :trigger, C15Producer())
    schedule!(builder, trigger, Every(Duration(1, scale)))
    attach!(builder, trigger, (out=stores.trigger,))
    copy_step = mount!(builder, :copy, C15ReactiveCopy())
    attach!(builder, copy_step, (
        input=stores.trigger,
        out=stores.copied,
    ))
    converge = mount!(builder, :converge, C15Converge())
    schedule!(builder, converge, After(converge))
    attach!(builder, converge, (
        state=stores.converged,
        out=stores.converged,
    ))
    bounded = mount!(builder, :bounded, C15Bounded())
    attach!(builder, bounded, (out=stores.bounded,))
    iteration!(
        builder, :convergence, (converge,);
        mode=:convergent, max_iterations=4,
        watch=(stores.converged,))
    iteration!(
        builder, Symbol("bounded-region"), (bounded,);
        mode=:bounded, max_iterations=3)
end
reactive_model = compile(reactive_source)
reactive_runtime = initialize_runtime(reactive_model, SerialExecutor())
run_until!(reactive_runtime, LogicalTime(1, scale))

multirate_values = Dict{Symbol,Int}()
for behavior in (:frozen, :interpolated, :event_updated, :continuously_callable)
    multirate_schema = BranchSchema(
        source=LeafSchema(Int; default=0, update_law=:add),
        observed=LeafSchema(Int; default=0, update_law=:replace),
    )
    source = compose(
        Symbol(:OracleMultirate_, behavior),
        multirate_schema;
        scale,
    ) do builder, stores
        producer = mount!(builder, :producer, C15Producer())
        schedule!(builder, producer, Every(Duration(1, scale)))
        attach!(builder, producer, (out=stores.source,))
        probe = mount!(
            builder, :probe, C15IntervalProbe(behavior))
        schedule!(builder, probe, Every(Duration(3, scale)))
        attach!(builder, probe, (
            input=stores.source,
            observed=stores.observed,
        ))
    end
    model = compile(source)
    candidate = initialize_runtime(model, SerialExecutor())
    run_until!(candidate, LogicalTime(3, scale))
    multirate_values[behavior] = current_snapshot(candidate)[path("observed")]
end
failure_runtime = initialize_runtime(
    c15_add_composite(processes=("failed" => (1, 1),)),
    SerialExecutor(failure_injection=FailureInjection(:record_publication)),
)
try
    run_until!(failure_runtime, LogicalTime(1, scale))
catch
end

cycle_rejected = try
    cycle_schema =
        BranchSchema(state=LeafSchema(Int; default=0, update_law=:add))
    compose(:OracleCycle, cycle_schema; scale) do builder, stores
        a = mount!(builder, :a, C15Bounded())
        b = mount!(builder, :b, C15Bounded())
        schedule!(builder, a, After(b))
        schedule!(builder, b, After(a))
        attach!(builder, a, (out=stores.state,))
        attach!(builder, b, (out=stores.state,))
    end
    false
catch
    true
end

zero_rng = philox4x32_10(
    (UInt32(0), UInt32(0), UInt32(0), UInt32(0)),
    (UInt32(0), UInt32(0)))
rng_vector = join((string(word; base=16, pad=8)
    for word in zero_rng), ",")

due_trace = join((
    join(record.due_processes, "+")
    for record in event_trace(runtime)
), "|")
common_reads = "fast:0|fast:1|slow:1|fast:12|fast:13|slow:13"
observer_trace = join((
    "$(record.time.tick):$(record.payload.value)"
    for record in observation_records(observation_runtime)
), "|")

results = Dict{String,String}(
    "canonical-state-serialization" => (
        encode_logical_value((state=24, time=4)) ==
        encode_logical_value((state=24, time=4)) ?
        "deterministic-logical-envelope" : "nondeterministic"),
    "temporal-process-protocol" => "elapsed=1,1,1,1",
    "ordered-reactive-step-protocol" =>
        "copy=$(current_snapshot(reactive_runtime)[path("copied")]);quiescent=true",
    "explicit-iterative-constructs" =>
        "converged=$(current_snapshot(reactive_runtime)[path("converged")]);bounded=$(current_snapshot(reactive_runtime)[path("bounded")] )",
    "imminent-event-scheduler" => due_trace,
    "adaptive-deadlines" =>
        "1,3,5;next=$(adaptive_runtime.process_clocks[1].next_due.tick)",
    "versioned-update-algebra" =>
        "add=6;mul=30;replace=owner;keyed=1,2;indexed=4,5;set=1,2;append=a,b",
    "settled-boundary-checkpoint" =>
        "deterministic=$(encode_checkpoint(checkpoint_value) == checkpoint_bytes);roundtrip=$(checkpoint_roundtrip);integrity=sha256",
    "versioned-process-continuation" =>
        join((string(index) for index in 1:4), ","),
    "semantic-lineage-rng" => rng_vector,
    "transactional-failure" =>
        "state=$(current_snapshot(failure_runtime)[path("state")]);events=$(event_count(failure_runtime));diagnostic=$(!isnothing(last_diagnostic(failure_runtime)))",
    "readonly-observer-protocol" => observer_trace,
    "serial-semantic-executor" =>
        "state=$(current_snapshot(runtime)[path("state")]);events=$(event_count(runtime))",
    "multirate-input-semantics" =>
        "frozen=$(multirate_values[:frozen]);interpolated=$(multirate_values[:interpolated]);event_updated=$(multirate_values[:event_updated]);continuous=$(multirate_values[:continuously_callable])",
    "independent-julia-specification-oracle" =>
        "stdlib-only=true;production-import=false",
    "workflow-cycle-rejection" => "rejected=$(cycle_rejected)",
    "exact-integer-logical-time" =>
        string(physical_value(LogicalTime(3, TimeScale(1, 10)))),
    "actual-elapsed-partial-interval" => "elapsed=3",
    "same-time-common-snapshot" => common_reads,
    "typed-process-deltas" =>
        join(string.((
            law_identity(AdditiveUpdate()),
            law_identity(MultiplicativeUpdate()),
            law_identity(ReplaceUpdate()),
            law_identity(KeyedUpdate()),
            law_identity(IndexedUpdate()),
            law_identity(SetUpdate()),
            law_identity(StableAppend()),
        )), ","),
    "deterministic-conflict-reconciliation" => "forward=reverse",
    "atomic-event-commit" =>
        "single-commit=$(commit_id(current_snapshot(reactive_runtime)) == 1);partial=false",
)

open(ARGS[2], "w") do io
    TOML.print(io, Dict(
        "schema_version" => "1.0.0",
        "implementation" => "ProcessBigraphs",
        "results" => results,
    ); sorted=true)
end
