#!/usr/bin/env julia

using Dates
using Pkg
using SHA
using TOML
using ProcessBigraphs

import ProcessBigraphs: PortBinding, ProcessDeclaration, StaticComposite,
    compile_composite, invoke, ports, semantic_parameters

const ROOT = normpath(joinpath(@__DIR__, ".."))
length(ARGS) == 1 ||
    error("usage: process-bigraph-phase15c-guardrails.jl OUTPUT")
const OUTPUT = abspath(ARGS[1])

struct GuardrailCounter <: AbstractProcess
    amount::Int
end

ports(::GuardrailCounter) =
    (OutputPort(Int, :out; update_law=:add),)
semantic_parameters(law::GuardrailCounter) = (amount=law.amount,)
invoke(law::GuardrailCounter, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

function guardrail_composite()
    scale = TimeScale(1)
    compile_composite(StaticComposite(
        BranchSchema(
            state=LeafSchema(Int; default=0, update_law=:add),
        ),
        Dict(),
        scale;
        processes=(
            ProcessDeclaration(
                "counter",
                GuardrailCounter(1),
                FixedSchedule(Duration(1, scale)),
            ),
        ),
        bindings=(
            PortBinding("counter", :out, path("state")),
        ),
    ))
end

function measure_run(compiled, horizon::Int)
    runtime = initialize_runtime(compiled, SerialExecutor())
    GC.gc()
    allocation = @allocated begin
        started = time_ns()
        run_until!(runtime, LogicalTime(horizon, TimeScale(1)))
        elapsed = time_ns() - started
    end
    (
        elapsed_ns=elapsed,
        allocation_bytes=allocation,
        events=event_count(runtime),
        snapshot=snapshot_fingerprint(current_snapshot(runtime)),
    )
end

function contains_any(text::AbstractString, needles)
    any(needle -> occursin(needle, text), needles)
end

hot_sources = [
    joinpath(ROOT, "lib", "ProcessBigraphs", "src", name)
    for name in (
        "executor.jl",
        "runtime.jl",
        "scheduling.jl",
        "semantic_rng.jl",
        "continuations.jl",
        "observation.jl",
        "transactions.jl",
        "checkpoint_codec.jl",
    )
]
hot_text = join(read.(hot_sources, String), "\n")

authoring_traversal_tokens = (
    "ACSets.",
    "_rows(",
    "_attr(",
    "StructuredCospan",
    "AnnotatedWiringDiagram",
    "wiring_diagram(",
)
hidden_transfer_tokens = (
    "Adapt.adapt",
    "CUDA.cu",
    "CuArray(",
    "MtlArray(",
    "ROCArray(",
    "allowscalar",
)

started_compile = time_ns()
compiled = guardrail_composite()
compile_elapsed_ns = time_ns() - started_compile

# Warm all code paths before recording steady event-loop measurements.
warm = initialize_runtime(compiled, SerialExecutor())
run_until!(warm, LogicalTime(4, TimeScale(1)))

short = measure_run(compiled, 64)
long = measure_run(compiled, 256)
short.events == 64 || error("short guardrail run did not publish 64 events")
long.events == 256 || error("long guardrail run did not publish 256 events")

short_bytes_per_event = short.allocation_bytes / short.events
long_bytes_per_event = long.allocation_bytes / long.events
allocation_growth_limit = short_bytes_per_event * 1.25 + 4096

plan_field_types = collect(string.(fieldtypes(ExecutionPlan)))
no_runtime_traversal =
    !contains_any(hot_text, authoring_traversal_tokens)
no_authoring_structure =
    !contains_any(join(plan_field_types, "\n"),
        ("ACSet", "Cospan", "Wiring", "CanonicalModel"))
no_hidden_transfer =
    !contains_any(hot_text, hidden_transfer_tokens)
bounded_event_loop =
    long_bytes_per_event <= allocation_growth_limit

all((
    no_runtime_traversal,
    no_authoring_structure,
    no_hidden_transfer,
    bounded_event_loop,
)) || error("one or more Phase 15.C performance guardrails failed")

report = Dict(
    "schema_version" => "1.0.0",
    "report_kind" => "phase15c-performance-guardrails",
    "generated_at_utc" => string(now(UTC)),
    "julia_version" => string(VERSION),
    "julia_arch" => string(Sys.ARCH),
    "julia_kernel" => string(Sys.KERNEL),
    "fastest_runtime_claim" => false,
    "model_identity" => Dict(
        "model_fingerprint" => model_fingerprint(compiled),
        "execution_plan_fingerprint" =>
            execution_plan_fingerprint(compiled),
        "runtime_fingerprint" =>
            runtime_fingerprint(SerialExecutor(), compiled),
        "initial_snapshot_fingerprint" =>
            snapshot_fingerprint(compiled.initial),
    ),
    "dependency_resolution" => Dict(
        string(uuid) => Dict(
            "name" => info.name,
            "version" => isnothing(info.version) ?
                "stdlib-or-unversioned" : string(info.version),
            "direct" => info.is_direct_dep,
        )
        for (uuid, info) in Pkg.dependencies()
    ),
    "guardrails" => Dict(
        "no-runtime-acset-traversal" => Dict(
            "passed" => no_runtime_traversal,
            "files" => relpath.(hot_sources, ROOT),
            "rejected_tokens" => collect(authoring_traversal_tokens),
        ),
        "no-authoring-structure-in-execution-plan" => Dict(
            "passed" => no_authoring_structure,
            "field_types" => plan_field_types,
        ),
        "no-hidden-transfer" => Dict(
            "passed" => no_hidden_transfer,
            "rejected_tokens" => collect(hidden_transfer_tokens),
        ),
        "bounded-event-loop-regression-tracking" => Dict(
            "passed" => bounded_event_loop,
            "allocation_growth_limit_bytes_per_event" =>
                allocation_growth_limit,
        ),
    ),
    "measurements" => Dict(
        "compile_elapsed_ns" => compile_elapsed_ns,
        "short_horizon" => Dict(
            "events" => short.events,
            "elapsed_ns" => short.elapsed_ns,
            "allocation_bytes" => short.allocation_bytes,
            "bytes_per_event" => short_bytes_per_event,
            "events_per_second" =>
                short.events / (short.elapsed_ns / 1.0e9),
            "snapshot_fingerprint" => short.snapshot,
        ),
        "long_horizon" => Dict(
            "events" => long.events,
            "elapsed_ns" => long.elapsed_ns,
            "allocation_bytes" => long.allocation_bytes,
            "bytes_per_event" => long_bytes_per_event,
            "events_per_second" =>
                long.events / (long.elapsed_ns / 1.0e9),
            "snapshot_fingerprint" => long.snapshot,
        ),
    ),
)

mkpath(dirname(OUTPUT))
open(OUTPUT, "w") do io
    TOML.print(io, report; sorted=true)
end
println("Phase 15.C performance guardrails passed")
println("report=$(OUTPUT)")
println("sha256=$(bytes2hex(sha256(read(OUTPUT))))")
