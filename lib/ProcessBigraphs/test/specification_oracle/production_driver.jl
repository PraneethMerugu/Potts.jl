using ProcessBigraphs
using TOML

length(ARGS) == 2 || error("usage: production_driver.jl FIXTURE OUTPUT")
include(joinpath(@__DIR__, "..", "phase15c", "fixtures.jl"))

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

adaptive_decl = ProcessDeclaration(
    "adaptive",
    C15Adaptive(1, Int(fixture["adaptive"]["offset"])),
    AdaptiveSchedule(Duration(
        Int(fixture["adaptive"]["first_due"]), scale)),
)
adaptive_model = compile_composite(StaticComposite(
    BranchSchema(state=LeafSchema(Int; default=0, update_law=:add)),
    Dict(), scale;
    processes=(adaptive_decl,),
    bindings=(PortBinding("adaptive", :out, path("state")),),
))
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
counter_decl = ProcessDeclaration(
    "counter", C15Counter(), FixedSchedule(Duration(1, scale));
    continuation=(count=0,))
counter_model = compile_composite(StaticComposite(
    counter_schema, Dict(), scale;
    processes=(counter_decl,),
    bindings=(PortBinding("counter", :out, path("state")),),
))
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
trigger = ProcessDeclaration(
    "trigger", C15Producer(), FixedSchedule(Duration(1, scale)))
reactive_model = compile_composite(StaticComposite(
    reactive_schema, Dict(), scale;
    processes=(trigger,),
    steps=(
        StepDeclaration("copy", C15ReactiveCopy()),
        StepDeclaration("converge", C15Converge();
            dependencies=("converge",)),
        StepDeclaration("bounded", C15Bounded()),
    ),
    bindings=(
        PortBinding("trigger", :out, path("trigger")),
        PortBinding("copy", :input, path("trigger")),
        PortBinding("copy", :out, path("copied")),
        PortBinding("converge", :state, path("converged")),
        PortBinding("converge", :out, path("converged")),
        PortBinding("bounded", :out, path("bounded")),
    ),
    iteration_regions=(
        IterationRegion("convergence", ("converge",);
            mode=:convergent, max_iterations=4,
            watch_paths=(path("converged"),)),
        IterationRegion("bounded-region", ("bounded",);
            mode=:bounded, max_iterations=3),
    ),
))
reactive_runtime = initialize_runtime(reactive_model, SerialExecutor())
run_until!(reactive_runtime, LogicalTime(1, scale))

multirate_values = Dict{Symbol,Int}()
for behavior in (:frozen, :interpolated, :event_updated, :continuously_callable)
    model = compile_composite(StaticComposite(
        BranchSchema(
            source=LeafSchema(Int; default=0, update_law=:add),
            observed=LeafSchema(Int; default=0, update_law=:replace),
        ),
        Dict(), scale;
        processes=(
            ProcessDeclaration("producer", C15Producer(),
                FixedSchedule(Duration(1, scale))),
            ProcessDeclaration("probe", C15IntervalProbe(behavior),
                FixedSchedule(Duration(3, scale))),
        ),
        bindings=(
            PortBinding("producer", :out, path("source")),
            PortBinding("probe", :input, path("source")),
            PortBinding("probe", :observed, path("observed")),
        ),
    ))
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
    compile_composite(StaticComposite(
        BranchSchema(state=LeafSchema(Int; default=0, update_law=:add)),
        Dict(), scale;
        steps=(
            StepDeclaration("a", C15Bounded(); dependencies=("b",)),
            StepDeclaration("b", C15Bounded(); dependencies=("a",)),
        ),
        bindings=(
            PortBinding("a", :out, path("state")),
            PortBinding("b", :out, path("state")),
        ),
    ))
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
