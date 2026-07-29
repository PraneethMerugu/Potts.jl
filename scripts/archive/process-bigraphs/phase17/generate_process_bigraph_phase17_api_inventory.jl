#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const CONTRACT_PATH =
    joinpath(ROOT, "spec", "process-bigraph-phase17-api-v1.toml")
const ENTRYPOINT =
    joinpath(ROOT, "lib", "ProcessBigraphs", "src", "ProcessBigraphs.jl")
const OUTPUT_PATH =
    joinpath(ROOT, "spec", "process-bigraph-phase17-api-inventory-v1.toml")

function walk_expressions!(visitor, value)
    value isa Expr || return
    visitor(value)
    foreach(argument -> walk_expressions!(visitor, argument), value.args)
end

function declared_names(path, head)
    syntax = Meta.parseall(read(path, String); filename=path)
    result = Set{String}()
    walk_expressions!(syntax) do expression
        expression.head === head || return
        for argument in expression.args
            argument isa Symbol && push!(result, string(argument))
        end
    end
    return result
end

function owning_page(name, classification)
    classification == "public_extension" &&
        return "lib/ProcessBigraphs/docs/src/api/extension-experimental.md"
    classification == "deprecated_compat" &&
        return "lib/ProcessBigraphs/docs/src/concepts/capability-migration-troubleshooting.md"
    classification == "internal" && return ""
    name in (
        "CompositeModel", "SimulationProblem", "Every", "At", "On", "After",
        "compose", "store!", "mount!", "connect!", "attach!", "expose!",
        "schedule!", "iteration!", "parameter!", "observable!",
        "allow_instances!", "lower", "compile", "validate", "describe",
        "diagram", "explain", "remake", "parameter_names",
        "with_parameters", "managed_field_process",
    ) && return "lib/ProcessBigraphs/docs/src/api/user-authoring.md"
    name in (
        "schema_at", "schema_leaves", "semantic_fingerprint",
        "problem_fingerprint", "origin_map",
    ) && return "lib/ProcessBigraphs/docs/src/api/semantic-values.md"
    name in (
        "observation_records", "checkpoint", "restore",
    ) && return "lib/ProcessBigraphs/docs/src/api/runtime-checkpoint.md"
    name in ("spawn", "divide", "remove", "move") &&
        return "lib/ProcessBigraphs/docs/src/api/composition-structure.md"
    return "lib/ProcessBigraphs/docs/src/api/extension-experimental.md"
end

contract = TOML.parsefile(CONTRACT_PATH)
exports = declared_names(ENTRYPOINT, :export)
publics = declared_names(ENTRYPOINT, :public)

required_users = Set{String}(
    contract["process_bigraphs"]["user_existing_required"]["exported"])
union!(required_users,
    contract["process_bigraphs"]["user_additions"]["exported"])
required_extensions = Set{String}(vcat(
    contract["process_bigraphs"]["extension_required"]["public_unexported_functions"],
    contract["process_bigraphs"]["extension_required"]["public_unexported_types"],
))
required_internals = Set{String}(
    contract["process_bigraphs"]["internal_required"]["bindings"])
deprecated = Set([
    "PHASE16_CHECKPOINT_VERSION",
    "PHASE16_CHECKPOINT_SCHEMA",
    "LogicalCheckpointV3",
    "RestoredPhase16Checkpoint",
    "phase16_checkpoint",
    "decode_phase16_checkpoint",
    "restore_phase16_checkpoint",
])

all_names = union(
    exports, publics, required_users, required_extensions,
    required_internals, deprecated)
rows = Dict{String,Any}[]
for name in sort!(collect(all_names))
    classification =
        name in required_extensions ? "public_extension" :
        name in required_users ? "exported_user" :
        name in required_internals ? "internal" :
        name in deprecated ? "deprecated_compat" :
        "experimental_beta"
    desired_exported =
        classification in ("exported_user", "experimental_beta")
    desired_public = classification == "public_extension"
    page = owning_page(name, classification)
    push!(rows, Dict(
        "module" => "ProcessBigraphs",
        "name" => name,
        "class" => classification,
        "desired_exported" => desired_exported,
        "desired_public" => desired_public,
        "owner_page" => page,
        "docstring_required" =>
            classification in ("exported_user", "public_extension"),
        "support_label" =>
            classification == "exported_user" ? "supported-internal-beta" :
            classification == "public_extension" ? "qualified-extension" :
            classification == "experimental_beta" ? "experimental-internal-beta" :
            classification == "deprecated_compat" ? "deprecated-compatibility" :
            "internal",
        "compatibility_action" =>
            classification == "public_extension" ?
                "de-export-and-declare-public" :
            classification == "deprecated_compat" ?
                "retain-with-migration-and-removal-policy" :
            "retain",
        "positive_test" =>
            classification in ("exported_user", "public_extension") ?
                "required" : "not-required-by-phase17-admitted-api-policy",
        "misuse_test" =>
            classification in ("exported_user", "public_extension") ?
                "required-when-meaningful" : "not-required",
        "tutorial_use" =>
            classification == "internal" ? "forbidden" : "by-owning-page",
    ))
end

inventory = Dict{String,Any}(
    "schema_version" => "1.0.0",
    "inventory_id" => "process-bigraph-phase17-api-inventory-v1",
    "phase" => "17",
    "status" => "frozen",
    "module" => "ProcessBigraphs",
    "scope" =>
        "all exported and Julia-public bindings plus mandated internal and compatibility bindings",
    "generated_from_commit" =>
        "9fe40fbfa2bf8c9f01d180f0ba29368815bb87be",
    "unclassified_allowed" => 0,
    "binding_count" => length(rows),
    "bindings" => rows,
)

open(OUTPUT_PATH, "w") do io
    TOML.print(io, inventory; sorted=true)
    println(io)
end
println("Wrote $(length(rows)) classified bindings to $(relpath(OUTPUT_PATH, ROOT))")
