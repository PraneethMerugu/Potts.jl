#!/usr/bin/env julia

using SHA
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const AUDITS = joinpath(REPO, "design", "audits")
const CONTRACT_PATH =
    joinpath(AUDITS, "phase-14-g3b-entry-contract-v1.toml")
const LEDGER_PATH =
    joinpath(AUDITS, "phase-14-g3b-closure-ledger-v1.toml")

isfile(CONTRACT_PATH) || error("missing G3-B contract")
isfile(LEDGER_PATH) || error("missing G3-B closure ledger")

contract = TOML.parsefile(CONTRACT_PATH)
ledger = TOML.parsefile(LEDGER_PATH)
failures = String[]

check(condition, message) = condition || push!(failures, message)

function unique_rows(rows, label)
    result = Dict{String, Any}()
    for row in rows
        id = get(row, "id", "")
        isempty(id) && (check(false, "$label contains an empty id"); continue)
        haskey(result, id) &&
            check(false, "$label contains duplicate id '$id'")
        result[id] = row
    end
    return result
end

function git_output(arguments...)
    command = Cmd(vcat(["git", "-C", REPO], collect(arguments)))
    return readchomp(command)
end

function regular_file_beneath(path::AbstractString, root::AbstractString)
    resolved = normpath(joinpath(REPO, path))
    relative = relpath(resolved, root)
    beneath = relative != ".." && !startswith(relative, "../") &&
        !isabspath(relative)
    return beneath && isfile(resolved) && !islink(resolved), resolved
end

contract_rows =
    unique_rows(contract["closure_requirement"], "contract requirements")
ledger_rows = unique_rows(ledger["requirement"], "ledger requirements")
contract_processes = unique_rows(contract["process"], "contract processes")
ledger_processes =
    unique_rows(ledger["process_evidence"], "ledger process evidence")
contract_commands =
    unique_rows(contract["closure_command"], "contract closure commands")
contract_studies =
    unique_rows(
        contract["semantic_studies"],
        "contract source-semantic studies")

check(contract["schema_version"] == "1.6.0" && contract["revision"] == 7,
    "closure checker requires revision-7 schema 1.6.0")
check(ledger["schema_version"] == "1.1.0",
    "closure checker requires ledger schema 1.1.0")
check(Set(keys(contract_rows)) == Set(keys(ledger_rows)),
    "closure ledger and contract requirement identities differ")
check(Set(keys(contract_processes)) == Set(keys(ledger_processes)),
    "closure process matrix and canonical process identities differ")
check(ledger["contract_revision"] == contract["revision"],
    "closure ledger targets contract revision $(ledger["contract_revision"]), not $(contract["revision"])")

for id in sort!(collect(keys(contract_rows)))
    haskey(ledger_rows, id) || continue
    row = ledger_rows[id]
    check(row["status"] == "passed",
        "OPEN $id: status is $(row["status"]); remaining=$(join(get(row, "remaining", String[]), " | "))")
    check(row["proof_ids"] == ["requirement:$id"],
        "OPEN $id: requirement proof identity is missing or ambiguous")
    for evidence in row["evidence"]
        path = joinpath(AUDITS, evidence)
        check(isfile(path), "OPEN $id: missing evidence file $evidence")
    end
end

required_facets = Set(contract["process_proof"]["required_facets"])
check(required_facets == Set(ledger["process_matrix"]["required_facets"]),
    "contract and ledger process facets differ")
for id in contract["plan"]["ordered_processes"]
    haskey(ledger_processes, id) || continue
    row = ledger_processes[id]
    passed = Set(row["passed_facets"])
    remaining = Set(row["remaining_facets"])
    check(isempty(intersect(passed, remaining)) &&
          union(passed, remaining) == required_facets,
        "OPEN process $id: facet partition is invalid")
    check(row["status"] == "passed" && passed == required_facets &&
          isempty(remaining),
        "OPEN process $id: status=$(row["status"]); remaining=$(join(sort!(collect(remaining)), " | "))")
end

all_ledger_rows_passed =
    all(row -> row["status"] == "passed", values(ledger_rows)) &&
    all(row -> row["status"] == "passed", values(ledger_processes))
check(ledger["overall_status"] == "passed" && all_ledger_rows_passed,
    "OPEN overall_status: all requirement and process rows must be passed")
check(contract["closure_protocol"]["status"] == "passed",
    "OPEN contract closure_protocol.status: expected passed, found $(contract["closure_protocol"]["status"])")

attestation = contract["closure_attestation"]
manifest_relative = attestation["manifest"]
check(ledger["manifest"] == manifest_relative,
    "ledger and contract closure manifest paths differ")
manifest_path = joinpath(REPO, manifest_relative)

if !isfile(manifest_path)
    check(false, "OPEN closure manifest: missing $manifest_relative")
else
    manifest = TOML.parsefile(manifest_path)
    check(manifest["schema_version"] == attestation["schema_version"],
        "closure manifest schema does not match the contract")
    check(manifest["contract_revision"] == contract["revision"],
        "closure manifest targets a stale contract revision")
    check(manifest["claim"] == contract["closure_protocol"]["completion_claim"],
        "closure manifest claim is not exactly 'G3-B complete'")

    tested_commit = get(manifest, "tested_commit", "")
    tested_tree = get(manifest, "tested_tree", "")
    check(occursin(r"^[0-9a-f]{40,64}$", tested_commit),
        "closure manifest tested_commit is not a full lowercase object id")
    check(occursin(r"^[0-9a-f]{40,64}$", tested_tree),
        "closure manifest tested_tree is not a full lowercase object id")
    check(get(manifest, "dirty_state", "") == "clean",
        "closure commands were not recorded from a clean tested worktree")

    evidence_root = normpath(joinpath(REPO, attestation["evidence_root"]))
    artifacts = unique_rows(get(manifest, "artifact", Any[]),
        "closure artifact registry")
    artifact_references = Set{String}()
    for (id, row) in artifacts
        path = get(row, "path", "")
        beneath, resolved = regular_file_beneath(path, evidence_root)
        check(beneath, "artifact '$id' is missing, symlinked, or outside evidence_root")
        beneath || continue
        expected_bytes = get(row, "bytes", -1)
        expected_hash = lowercase(get(row, "sha256", ""))
        check(expected_bytes == filesize(resolved),
            "artifact '$id' byte length does not match")
        actual_hash = bytes2hex(open(sha256, resolved))
        check(occursin(r"^[0-9a-f]{64}$", expected_hash) &&
              expected_hash == actual_hash,
            "artifact '$id' SHA-256 does not match")
        check(!isempty(get(row, "kind", "")),
            "artifact '$id' has no declared kind")
    end

    command_results =
        unique_rows(get(manifest, "command", Any[]), "command results")
    check(Set(keys(command_results)) == Set(keys(contract_commands)),
        "manifest command identities differ from the closure-command registry")
    for (id, expected) in contract_commands
        haskey(command_results, id) || continue
        row = command_results[id]
        check(row["command"] == expected["command"],
            "command '$id' text differs from the preregistered command")
        check(get(row, "tested_commit", "") == tested_commit &&
              get(row, "status", "") == "passed" &&
              get(row, "exit_code", -1) == 0,
            "command '$id' did not pass at tested_commit")
        assertion_count = get(row, "assertion_count", 0)
        validation_count = get(row, "validation_count", 0)
        check(assertion_count > 0 || validation_count > 0,
            "command '$id' records no assertions or validations")
        outputs = Set(get(row, "output_artifact_ids", String[]))
        check(!isempty(outputs) && issubset(outputs, Set(keys(artifacts))),
            "command '$id' has missing or unknown output artifacts")
        union!(artifact_references, outputs)
    end

    study_results =
        unique_rows(
            get(manifest, "study", Any[]),
            "source-semantic study results")
    check(Set(keys(study_results)) == Set(keys(contract_studies)),
        "manifest study identities differ from the source-semantic study registry")
    for (id, _) in contract_studies
        haskey(study_results, id) || continue
        row = study_results[id]
        check(get(row, "status", "") == "accepted" &&
              get(row, "tested_commit", "") == tested_commit,
            "source-semantic study '$id' is not accepted at tested_commit")
        check(!isempty(get(row, "source_identity", "")) &&
              !isempty(get(row, "conclusion", "")),
            "source-semantic study '$id' lacks source identity or conclusion")
        for field in ("source_artifact_ids", "analysis_artifact_ids",
                "uncertainty_artifact_ids", "fixture_artifact_ids")
            ids = Set(get(row, field, String[]))
            check(!isempty(ids) && issubset(ids, Set(keys(artifacts))),
                "source-semantic study '$id' has missing or unknown $field")
            union!(artifact_references, ids)
        end
    end

    requirement_proofs =
        unique_rows(get(manifest, "proof", Any[]), "requirement proofs")
    expected_requirement_proofs =
        Set("requirement:$id" for id in keys(contract_rows))
    check(Set(keys(requirement_proofs)) == expected_requirement_proofs,
        "manifest requirement-proof identities are incomplete")
    for proof_id in expected_requirement_proofs
        haskey(requirement_proofs, proof_id) || continue
        row = requirement_proofs[proof_id]
        subject = replace(proof_id, "requirement:" => "")
        check(get(row, "kind", "") == "requirement" &&
              get(row, "subject", "") == subject &&
              get(row, "status", "") == "passed",
            "requirement proof '$proof_id' is malformed or open")
        commands = Set(get(row, "command_ids", String[]))
        evidence = Set(get(row, "artifact_ids", String[]))
        check(!isempty(commands) &&
              issubset(commands, Set(keys(command_results))),
            "requirement proof '$proof_id' has no valid command evidence")
        check(!isempty(evidence) && issubset(evidence, Set(keys(artifacts))),
            "requirement proof '$proof_id' has no valid artifact evidence")
        union!(artifact_references, evidence)
    end

    process_proofs =
        unique_rows(get(manifest, "process_proof", Any[]), "process proofs")
    expected_process_proofs = Set(
        "process:$process_id" for process_id in keys(contract_processes))
    check(Set(keys(process_proofs)) == expected_process_proofs,
        "manifest process-proof identities are incomplete")
    for proof_id in expected_process_proofs
        haskey(process_proofs, proof_id) || continue
        row = process_proofs[proof_id]
        process_id = get(row, "process_id", "")
        facets = Set(get(row, "facets", String[]))
        check(proof_id == "process:$process_id" &&
              process_id in keys(contract_processes) &&
              facets == required_facets &&
              get(row, "status", "") == "passed",
            "process proof '$proof_id' is malformed or open")
        commands = Set(get(row, "command_ids", String[]))
        evidence = Set(get(row, "artifact_ids", String[]))
        check(!isempty(commands) &&
              issubset(commands, Set(keys(command_results))),
            "process proof '$proof_id' has no valid command evidence")
        check(!isempty(evidence) && issubset(evidence, Set(keys(artifacts))),
            "process proof '$proof_id' has no valid artifact evidence")
        union!(artifact_references, evidence)
    end

    environments = Set(get(manifest, "environment_artifact_ids", String[]))
    check(!isempty(environments) &&
          issubset(environments, Set(keys(artifacts))),
        "closure manifest has no valid environment artifacts")
    union!(artifact_references, environments)
    check(artifact_references == Set(keys(artifacts)),
        "closure artifact registry contains unreferenced or unregistered evidence")

    boundaries = get(manifest, "claim_boundaries", Dict{String, Any}())
    for key in ("real_metal_qualified", "real_rocm_qualified",
            "performance_qualified", "phase14_3_classifier_closed",
            "paper_reproduction_claimed", "cc3d_std_rand_bitwise_replay")
        check(get(boundaries, key, true) === false,
            "closure manifest overclaims '$key'")
    end

    if occursin(r"^[0-9a-f]{40,64}$", tested_commit)
        try
            resolved_commit = git_output("rev-parse", "$(tested_commit)^{commit}")
            check(resolved_commit == tested_commit,
                "tested_commit does not resolve to the recorded full commit id")
            actual_tree = git_output("show", "-s", "--format=%T", tested_commit)
            check(actual_tree == tested_tree,
                "tested_tree does not match tested_commit")
            run(Cmd(["git", "-C", REPO, "merge-base", "--is-ancestor",
                tested_commit, "HEAD"]))
            changed = split(git_output(
                "diff", "--name-only", "$tested_commit..HEAD"), '\n';
                keepempty = false)
            allowed_prefix = attestation["evidence_root"] * "/"
            disallowed = filter(path ->
                !startswith(path, allowed_prefix), changed)
            check(isempty(disallowed),
                "post-test diff is not attestation-only: $(join(disallowed, " | "))")
            dirty = git_output("status", "--porcelain", "--untracked-files=all")
            check(isempty(dirty),
                "closure checker must run from a clean attestation checkout")
        catch error
            check(false, "git attestation validation failed: $(sprint(showerror, error))")
        end
    end
end

if !isempty(failures)
    println("Phase 14.1 G3-B closure: OPEN")
    foreach(message -> println(" - ", message), failures)
    exit(1)
end

println("Phase 14.1 G3-B closure: PASS")
