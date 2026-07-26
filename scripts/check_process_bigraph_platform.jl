#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing required artifact: $relative_path")
    return path
end

function unique_ids(rows, label)
    ids = [get(row, "id", "") for row in rows]
    check(all(id -> id isa String && !isempty(strip(id)), ids),
        "$label contains an empty id")
    check(length(ids) == length(unique(ids)), "$label contains duplicate ids")
    return Set(ids)
end

function check_local_links(path)
    text = read(path, String)
    check(iseven(length(collect(eachmatch(r"```", text)))),
        "$(relpath(path, ROOT)) has an unbalanced fenced code block")
    for match in eachmatch(r"!?\[[^\]]*\]\(([^)]+)\)", text)
        target = strip(match.captures[1])
        (startswith(target, "http://") || startswith(target, "https://") ||
         startswith(target, "mailto:") || startswith(target, "#")) && continue
        target = strip(first(split(target, '#')), ['<', '>'])
        isempty(target) && continue
        check(ispath(normpath(joinpath(dirname(path), target))),
            "$(relpath(path, ROOT)) has a missing local link target '$target'")
    end
end

registry_path = require_file("spec/process-bigraph-parity-registry-v1.toml")
decision_path = require_file("spec/decisions/0034-process-bigraph-runtime-platform.md")
semantics_path = require_file("spec/process-bigraph-runtime-semantics.md")
audit_path = require_file(
    "design/audits/process-bigraph-runtime-parity-and-parallel-development-audit.md")
interview_path = require_file(
    "design/audits/process-bigraph-runtime-owner-interview.md")
charter_path = require_file("spec/project-charter.md")
architecture_path = require_file("design/repository-architecture-standard.md")
roadmap_path = require_file("design/refactor-roadmap.md")
decision_index_path = require_file("spec/decisions/README.md")
spec_index_path = require_file("spec/README.md")
evidence_index_path = require_file("spec/conformance-evidence.md")

registry = TOML.parsefile(registry_path)
sources = registry["sources"]
features = registry["features"]
oracles = registry["oracles"]
source_ids = unique_ids(sources, "source registry")
feature_ids = unique_ids(features, "feature registry")
oracle_ids = unique_ids(oracles, "oracle registry")

check(registry["schema_version"] == "1.0.0", "unexpected parity-registry schema")
check(registry["registry_status"] == "accepted-scope-specified-implementation-open",
    "parity registry overclaims implementation maturity")
check(registry["package_name"] == "ProcessBigraphs.jl",
    "runtime package identity is not ProcessBigraphs.jl")
check(registry["incubation_path"] == "lib/ProcessBigraphs",
    "runtime incubation path changed")

minimums = registry["checker"]
check(length(sources) >= minimums["minimum_source_count"],
    "parity registry has too few pinned sources")
check(length(features) >= minimums["minimum_feature_count"],
    "parity registry has too few classified features")
check(length(oracles) >= minimums["minimum_oracle_count"],
    "parity registry has too few registered oracles")

expected_pins = Dict(
    "process-bigraph" => "305ea826191e9f897f0c6e207bc303bbc44a9eef",
    "bigraph-schema" => "4b208e13620e09e877af52ea07273bc9429a3a17",
    "vivarium-core-context" => "60b1570ed20bddd1229e621e670621566c0dafd3",
    "spatio-flux-reference" => "6fece7bb9af8e3b374affe02f30b6b022de1d134",
    "vecoli-reference" => "0c4bc21731b07d0d395b5e5b1d8f5afe11466626",
)
source_by_id = Dict(row["id"] => row for row in sources)
for (id, revision) in expected_pins
    check(id in source_ids, "missing exact source pin '$id'")
    id in source_ids || continue
    check(get(source_by_id[id], "revision", "") == revision,
        "source pin '$id' changed without registry qualification")
    check(occursin(r"^[0-9a-f]{40}$", revision),
        "source pin '$id' is not a full lowercase commit")
end
check("process-bigraph-paper" in source_ids, "missing Process-Bigraph paper authority")
if "process-bigraph-paper" in source_ids
    check(get(source_by_id["process-bigraph-paper"], "revision", "") == "2512.23754",
        "Process-Bigraph paper identifier changed")
end

allowed_statuses = Set(registry["status_vocabulary"]["allowed"])
allowed_classes = Set(registry["classification_vocabulary"]["allowed"])
allowed_oracle_kinds = Set(registry["evidence_vocabulary"]["oracle_kinds"])
required_feature_fields = registry["checker"]["required_feature_fields"]
required_oracle_fields = registry["checker"]["required_oracle_fields"]
excluded_release_classes = Set([
    "compatibility_mode", "optional_ecosystem", "excluded_legacy", "deferred_rewrite"])

for feature in features
    id = feature["id"]
    for field in required_feature_fields
        check(haskey(feature, field), "feature '$id' is missing '$field'")
    end
    check(feature["status"] in allowed_statuses,
        "feature '$id' uses an unknown status")
    check(feature["classification"] in allowed_classes,
        "feature '$id' uses an unknown classification")
    referenced_oracles = Set(feature["oracle_ids"])
    check(referenced_oracles <= oracle_ids,
        "feature '$id' references an unknown oracle")
    if feature["classification"] in ("normative_parity", "normative_julia")
        check(!isempty(referenced_oracles),
            "normative feature '$id' has no registered oracle")
    end
    if feature["required_for_pinned_parity"]
        check(feature["required_for_first_public_release"],
            "pinned-parity feature '$id' does not block public release")
    end
    if feature["classification"] in excluded_release_classes
        check(!feature["required_for_pinned_parity"],
            "excluded/optional feature '$id' incorrectly blocks pinned parity")
    end
end

for oracle in oracles
    id = oracle["id"]
    for field in required_oracle_fields
        check(haskey(oracle, field), "oracle '$id' is missing '$field'")
    end
    check(oracle["kind"] in allowed_oracle_kinds,
        "oracle '$id' uses an unknown kind")
    check(oracle["status"] in allowed_statuses,
        "oracle '$id' uses an unknown status")
    check(Set(oracle["feature_ids"]) <= feature_ids,
        "oracle '$id' references an unknown feature")
    check(Set(get(oracle, "sources", String[])) <= source_ids,
        "oracle '$id' references an unknown source")
end

check(all(feature -> feature["status"] in ("not_started", "specified", "excluded"), features),
    "spec-only revision must not claim implemented, oracle-passing, or qualified runtime features")
check(!all(feature["status"] == "qualified" for feature in features
          if feature["required_for_first_public_release"]),
    "registry incorrectly declares the first public release ready")
check(registry["executor_policy"]["semantic_oracle"] == "SerialExecutor",
    "serial executor is not the semantic oracle")
check(occursin("never owns time", registry["executor_policy"]["dagger_boundary"]),
    "Dagger boundary does not exclude semantic scheduling authority")
check(registry["gpu_policy"]["hidden_transfer"] == "fail_preflight",
    "hidden transfer does not fail preflight")
check(registry["scheduler_policy"]["normative_mode"] == "imminent_event",
    "imminent-event execution is not normative")
check(registry["whole_cell_ladder"]["ordered_gates"] == [
    "runtime_microfixtures",
    "julia_biochemical_fba_composite",
    "selected_vecoli_slices",
    "well_stirred_syn3a",
    "full_vecoli_generation",
    "potts_population_environment_composition",
], "whole-cell acceptance ladder changed")

interview = read(interview_path, String)
check(occursin("Status: Complete; all 48 owner decisions resolved", interview),
    "owner interview is not complete")

decision = read(decision_path, String)
semantics = read(semantics_path, String)
charter = read(charter_path, String)
architecture = read(architecture_path, String)
roadmap = read(roadmap_path, String)
indices = join(read(path, String) for path in
    (decision_index_path, spec_index_path, evidence_index_path))

for n in 1:48
    check(occursin(Regex("(?m)^$(n)\\."), decision),
        "Decision 0034 is missing owner decision $n")
end

for phrase in [
    "complete pinned parity",
    "whole-cell-style composite",
    "Vivarium 1.x",
    "DaggerExecutor",
    "strangler",
]
    check(occursin(phrase, decision), "Decision 0034 is missing '$phrase'")
end
for phrase in [
    "Imminent-event scheduler",
    "Hierarchical state and schemas",
    "### Reconciliation",
    "Structural transactions",
    "Dagger",
    "Whole-cell acceptance ladder",
]
    check(occursin(phrase, semantics), "runtime semantics are missing '$phrase'")
end
check(occursin("ProcessBigraphs.jl", charter),
    "project charter omits ProcessBigraphs.jl")
check(occursin("`ProcessBigraphs` MUST NOT depend on `CorePotts`", architecture) &&
      occursin("`CorePotts` depends on `ProcessBigraphs`", architecture) &&
      occursin("`PottsToolkit` depends on `CorePotts`", architecture),
    "repository architecture omits the target dependency direction")
for phase in 14:20
    check(occursin("Phase $phase", roadmap), "roadmap omits Phase $phase")
end
for phrase in ["Potts workstream", "Runtime workstream", "Adapter", "Evidence"]
    check(occursin(phrase, roadmap), "roadmap omits the '$phrase' workstream")
end
check(occursin("G3-B", roadmap) && occursin("G3-C", roadmap),
    "roadmap omits the G3-B-to-G3-C boundary")
check(occursin("0034-process-bigraph-runtime-platform.md", indices),
    "Decision 0034 is absent from specification indexes")
check(occursin("process-bigraph-runtime-semantics.md", indices),
    "runtime semantics are absent from specification indexes")
check(occursin("process-bigraph-parity-registry-v1.toml", indices),
    "parity registry is absent from specification indexes")

for path in [
    decision_path, semantics_path, audit_path, interview_path, charter_path,
    architecture_path, roadmap_path, decision_index_path, spec_index_path,
    evidence_index_path,
]
    check_local_links(path)
end

if isempty(failures)
    println("ProcessBigraphs platform specification passes:")
    println("  $(length(sources)) pinned research sources")
    println("  $(length(features)) classified features")
    println("  $(length(oracles)) registered conformance oracles")
    println("  all 48 owner decisions recorded")
    println("  exact-time serial authority, Dagger boundary, GPU transfer policy, and whole-cell ladder frozen")
    println("  first public release remains fail-closed")
else
    println(stderr,
        "ProcessBigraphs platform specification failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end
