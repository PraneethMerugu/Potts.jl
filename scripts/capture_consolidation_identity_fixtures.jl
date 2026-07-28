#!/usr/bin/env julia

VERSION == v"1.12.6" ||
    error("consolidation identity fixtures require Julia 1.12.6; found $VERSION")

using ProcessBigraphs
using SHA
using TOML

import ProcessBigraphs: encode_semantic_model, ports, invoke,
    semantic_parameters

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "design",
    "evidence",
    "consolidation-baseline",
    "identity-fixtures-v1.toml",
)

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    isnothing(argument) ? default :
        ARGS[argument][(length(prefix) + 1):end]
end

struct ConsolidationBaselineIncrement <: AbstractProcess
    amount::Int
end

ports(::ConsolidationBaselineIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)

semantic_parameters(process::ConsolidationBaselineIncrement) =
    (amount=process.amount,)

function invoke(process::ConsolidationBaselineIncrement, inputs, context)
    InvocationResult((
        emit(context, :increment, AdditiveUpdate(), process.amount),
    ))
end

function semantic_model()
    scale = TimeScale(1)
    compose(:ConsolidationBaselineIdentity; scale, profile=:reproducible) do model
        state = store!(
            model,
            :state,
            LeafSchema(Int; default=0, update_law=:add),
        )
        increment = mount!(
            model,
            :increment,
            ConsolidationBaselineIncrement(2),
        )
        schedule!(model, increment, Every(Duration(1, scale)))
        attach!(model, increment, (state=state, increment=state))
        parameter!(
            model,
            :gain,
            2.0;
            units="dimensionless",
            description="Identity fixture parameter",
        )
        observable!(model, :state_value, state)
    end
end

function component_encoder(process)
    process isa ConsolidationBaselineIncrement ||
        error("unexpected identity-fixture component $(typeof(process))")
    (
        id="consolidation.baseline.increment",
        version="1.0.0",
        payload=(amount=process.amount,),
    )
end

function capture()
    model = semantic_model()
    lowered = lower(model)
    plan = compile(lowered)
    problem = SimulationProblem(
        model;
        initial=(model.state.state => 1,),
        parameters=(model.parameters.gain => 3.0,),
        observations=(model.observables.state_value,),
    )
    executor = SerialExecutor(root_seed=0x434f4e534f4c4944)
    runtime = initialize_runtime(plan, executor)
    run_until!(runtime, LogicalTime(4, TimeScale(1)))
    checkpoint_value = logical_checkpoint(runtime)
    checkpoint_bytes = encode_checkpoint(checkpoint_value)
    semantic_bytes =
        encode_semantic_model(model; encode_component=component_encoder)
    trace = event_trace(runtime)
    final_snapshot = current_snapshot(runtime)
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" =>
            "semantic-preserving-consolidation-baseline-identity-fixtures-v1",
        "status" => "frozen",
        "qualified_commit" =>
            "d2f4d40e78fb68ee20da483d9784b55d25bf6147",
        "julia_version" => string(VERSION),
        "architecture" => string(Sys.ARCH),
        "fixture" => Dict(
            "name" => "ConsolidationBaselineIdentity",
            "events" => 4,
            "root_seed" => string(executor.root_seed),
            "final_state" => final_snapshot[path("state")],
            "observation_count" => length(observation_records(runtime)),
        ),
        "fingerprints" => Dict(
            "semantic_model" => semantic_fingerprint(model),
            "canonical_ir" => ir_fingerprint(lowered),
            "plan" => plan_fingerprint(plan),
            "model" => model_fingerprint(plan),
            "canonical_structure" => structural_fingerprint(plan),
            "execution_plan" => execution_plan_fingerprint(plan),
            "problem" => problem_fingerprint(problem),
            "runtime" => runtime_fingerprint(executor, plan),
            "final_snapshot" => snapshot_fingerprint(final_snapshot),
            "event_trace" => canonical_fingerprint(trace),
            "checkpoint" => checkpoint_fingerprint(checkpoint_value),
        ),
        "canonical_bytes" => Dict(
            "semantic_model_length" => length(semantic_bytes),
            "semantic_model_sha256" => bytes2hex(sha256(semantic_bytes)),
            "checkpoint_format" => checkpoint_value.format_version,
            "checkpoint_length" => length(checkpoint_bytes),
            "checkpoint_sha256" => bytes2hex(sha256(checkpoint_bytes)),
            "checkpoint_roundtrip_equal" =>
                encode_checkpoint(decode_checkpoint(checkpoint_bytes)) ==
                checkpoint_bytes,
        ),
        "adopted_fixtures" => [
            Dict(
                "name" => "serial-runtime-qualified-matrix",
                "authority" =>
                    "design/evidence/process-bigraph-phase15c-evidence-v1.toml",
                "covers" => [
                    "model fingerprints",
                    "eight runtime fixtures",
                    "33 restart cuts",
                    "failure-stage traces",
                ],
            ),
            Dict(
                "name" => "logical-checkpoint-v2-canonical-bytes",
                "authority" =>
                    "lib/ProcessBigraphs/test/phase15c/test_checkpoint_v2.jl",
                "canonical_length" => 4609,
                "canonical_sha256" =>
                    "8b28675481d06fa7ffa6389ec63e0dbb9f43408e3a71d190a040bea67bb2b929",
            ),
            Dict(
                "name" => "managed-engine-checkpoint-v3",
                "authority" =>
                    "lib/ProcessBigraphs/test/phase16/test_phase16e_checkpoint.jl",
                "covers" => [
                    "canonical bytes roundtrip",
                    "checkpoint fingerprint",
                    "exact restore",
                    "legacy conversion",
                    "corruption rejection",
                ],
            ),
            Dict(
                "name" => "bounded-merks-observations",
                "authority" =>
                    "design/evidence/process-bigraph-phase16g-evidence-v1.toml",
                "covers" => [
                    "native, SciML, and independent-adapter observations",
                    "restart",
                    "rollback",
                ],
            ),
            Dict(
                "name" => "bounded-cnv-full-domain-one-mcs",
                "authority" =>
                    "design/evidence/process-bigraph-phase16h-evidence-v1.toml",
                "covers" => [
                    "occupied voxels",
                    "identity count",
                    "four field summaries",
                    "finite-field envelope",
                ],
            ),
        ],
    )
end

function rendered(value)
    io = IOBuffer()
    TOML.print(io, value; sorted=true)
    write(io, '\n')
    take!(io)
end

output = option("output", DEFAULT_OUTPUT)
bytes = rendered(capture())
if "--check" in ARGS
    isfile(output) || error("missing identity fixture artifact: $output")
    read(output) == bytes || error("identity fixture artifact changed: $output")
    println("verified ", relpath(output, ROOT))
else
    mkpath(dirname(output))
    open(output, "w") do io
        write(io, bytes)
    end
    println("wrote ", relpath(output, ROOT))
end
