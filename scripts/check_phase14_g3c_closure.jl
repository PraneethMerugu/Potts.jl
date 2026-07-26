#!/usr/bin/env julia

using TOML
using SHA

const REPO = normpath(joinpath(@__DIR__, ".."))
const AUDITS = joinpath(REPO, "design", "audits")
const LEDGER = TOML.parsefile(joinpath(
    AUDITS, "phase-14-g3c-closure-ledger-v1.toml"))
const SCHEMA = TOML.parsefile(joinpath(
    AUDITS, "phase-14-g3c-evidence-schema-v1.toml"))
const STATUS_DOCUMENTS = (
    "design/refactor-roadmap.md",
    "design/audits/phase-14-gpu-native-implementation-plan.md",
    "spec/README.md",
    "spec/phase-14-semantic-kernel.md",
    "spec/conformance-evidence.md",
    "spec/phase-14-contract-registry-v2.toml",
)

function option(name)
    prefix = "--$name="
    index = findfirst(argument ->
        startswith(argument, prefix), ARGS)
    index === nothing && return nothing
    return ARGS[index][(length(prefix) + 1):end]
end

metal_path = option("metal")
amdgpu_path = option("amdgpu")
metal_code = option("metal-device-code")
amdgpu_code = option("amdgpu-device-code")
evidence_only = "--evidence-only" in ARGS

failures = String[]
check(condition, message) =
    condition || push!(failures, message)

function device_code_bytes(path)
    path === nothing && return 0
    isfile(path) && return filesize(path)
    isdir(path) || return 0
    return sum(
        filesize(joinpath(root, file))
        for (root, _, files) in walkdir(path)
        for file in files; init = 0)
end

function validate_status_document(relative)
    path = joinpath(REPO, relative)
    isfile(path) || begin
        check(false, "G3-C status document is missing: $relative")
        return
    end
    content = read(path, String)
    g3c_passed = occursin(
        r"g3-c(?:\s+metal/rocm\s+qualification)?\s+(?:is\s+)?(?:complete|completed|passed|closed)"i,
        content)
    g4_current = occursin(
        r"g4(?:\s+[^.\n|]{0,120})?\s+(?:is\s+)?(?:current|open|opened|next)"i,
        content)
    check(g3c_passed,
        "$relative does not state that G3-C passed or completed")
    check(g4_current,
        "$relative does not state that G4 is current, open, or next")
end

function validate_result(path, backend)
    path === nothing && begin
        check(false, "missing --$backend paper result")
        return nothing
    end
    isfile(path) || begin
        check(false, "$backend result does not exist: $path")
        return nothing
    end
    result = try
        TOML.parsefile(path)
    catch error
        check(false,
            "$backend result is not valid TOML: $(sprint(showerror, error))")
        return nothing
    end
    check(get(result, "schema_version", "") ==
          SCHEMA["schema_version"],
        "$backend result schema differs")
    check(get(result, "suite", "") == SCHEMA["suite"],
        "$backend result suite differs")
    provenance = get(
        result, "provenance", Dict{String, Any}())
    qualification = get(
        result, "qualification", Dict{String, Any}())
    check(get(qualification, "backend", "") == backend,
        "$backend qualification backend identity differs")
    check(get(qualification, "profile", "") == "paper" &&
          get(qualification, "side", 0) == 256 &&
          get(qualification, "target_mcs", 0) == 500,
        "$backend did not run the 256x256x500 paper profile")
    check(get(qualification, "number_type", "") == "Float32" &&
          get(qualification, "algorithm", "") == "SequentialCPM" &&
          get(qualification, "semantic_rng", "") == "Philox4x32x10V1" &&
          get(qualification, "g3b_contract_revision", 0) == 7,
        "$backend numerical/algorithm contract differs")
    check(get(qualification, "coupled_preflight", "") ==
          "qualified_gpu_native",
        "$backend exact Wang preflight did not pass")

    unobserved = get(
        qualification, "unobserved", Dict{String, Any}())
    check(get(unobserved, "target_mcs", 0) == 2 &&
          get(unobserved, "status_scalar_transfers", -1) == 9 &&
          get(unobserved, "status_boundaries", -1) == 5 &&
          get(unobserved, "scientific_payload_transfers", -1) == 0,
        "$backend unobserved transfer contract differs")
    metrics = get(
        unobserved, "metrics", Dict{String, Any}())
    check(get(metrics, "host_to_device_transfers", -1) == 0 &&
          get(metrics, "device_to_host_transfers", -1) == 9 &&
          get(metrics, "device_allocations", -1) == 0,
        "$backend unobserved resource counters differ")

    continuation = get(
        qualification, "continuation", Dict{String, Any}())
    check(get(continuation, "same_backend_replay", false) === true &&
          get(continuation, "completed_mcs_restart", false) === true &&
          get(continuation, "capture_mcs", 0) == 3 &&
          get(continuation, "continued_mcs", 0) == 6 &&
          get(continuation, "mid_phase_capture_admitted", true) === false,
        "$backend replay/restart contract did not pass")

    comparison = get(
        qualification, "cpu_comparison", Dict{String, Any}())
    check(get(comparison, "integer_schedule_exact", false) === true &&
          get(comparison, "field_maximum_absolute_error", Inf) <=
              get(comparison, "field_relative_tolerance", 0.0) *
              max(get(qualification["invariants"],
                  "field_maximum", 0.0), 1.0) &&
          get(comparison, "rac_maximum_absolute_error", Inf) <=
              get(comparison, "rac_relative_tolerance", 0.0) *
              max(abs(get(qualification["invariants"],
                  "rac_maximum", 0.0)), 1.0),
        "$backend CPU comparison exceeds its recorded tolerance")

    performance = get(
        qualification, "performance", Dict{String, Any}())
    check(get(performance, "measured_mcs", 0) == 498 &&
          get(performance, "seconds", 0.0) > 0.0 &&
          get(performance, "seconds_per_mcs", 0.0) > 0.0,
        "$backend paper performance record is absent")
    check(get(qualification, "scientific_state_bytes", 0) > 0 &&
          get(qualification, "coupled_array_bytes", 0) > 0 &&
          get(qualification, "coupled_array_count", 0) > 0,
        "$backend memory/residency record is absent")

    check(get(provenance, "git_dirty", true) === false &&
          get(provenance, "harness_git_dirty", true) === false,
        "$backend evidence was generated from a dirty tree")
    check(get(provenance, "julia_version", "") == "1.12.6",
        "$backend evidence used the wrong Julia version")
    check(!isempty(get(provenance, "device", "")) &&
          get(provenance, "device", "") != "unknown",
        "$backend device identity is missing")
    check(!isempty(get(provenance, "hardware_id", "")) &&
          get(provenance, "hardware_id", "") != "unreported",
        "$backend hardware identity is missing")
    return result
end

metal = validate_result(metal_path, "metal")
amdgpu = validate_result(amdgpu_path, "amdgpu")
check(device_code_bytes(metal_code) >=
      SCHEMA["device_code"]["minimum_bytes"],
    "Metal AIR artifact is missing or empty")
check(device_code_bytes(amdgpu_code) >=
      SCHEMA["device_code"]["minimum_bytes"],
    "ROCm device-code artifact is missing or empty")

if metal !== nothing && amdgpu !== nothing
    metal_provenance = metal["provenance"]
    amdgpu_provenance = amdgpu["provenance"]
    for key in (
            "implementation_commit",
            "source_tree_sha256",
            "implementation_tree_sha256",
            "harness_tree_sha256",
            "benchmark_environment_sha256")
        check(get(metal_provenance, key, "") ==
              get(amdgpu_provenance, key, "") &&
              !isempty(get(metal_provenance, key, "")),
            "Metal and ROCm evidence differ at provenance '$key'")
    end
end

if !evidence_only
    all_requirements_passed = all(row ->
        row["status"] == "passed", LEDGER["requirement"])
    all_processes_passed = all(row ->
        row["metal"] == "passed" &&
        row["amdgpu"] == "passed", LEDGER["process"])
    check(LEDGER["overall_status"] == "passed" &&
          all_requirements_passed && all_processes_passed,
        "G3-C ledger remains hardware_pending; attest the validated artifacts before claiming closure")
    boundaries = LEDGER["claim_boundaries"]
    check(boundaries["metal_qualified"] === true &&
          boundaries["rocm_qualified"] === true &&
          boundaries["g3c_complete"] === true &&
          boundaries["g4_open"] === true &&
          boundaries["g3b_semantics_changed"] === false,
        "G3-C passed claim boundaries are incomplete")

    manifest_relative = get(LEDGER, "manifest", "")
    manifest_path = normpath(joinpath(REPO, manifest_relative))
    if isempty(manifest_relative) || !isfile(manifest_path)
        check(false, "G3-C attestation manifest is missing")
    else
        manifest = TOML.parsefile(manifest_path)
        check(get(manifest, "schema_version", "") == "1.0.0" &&
              get(manifest, "claim", "") == "G3-C complete",
            "G3-C attestation manifest identity differs")
        implementation_commit =
            get(manifest, "implementation_commit", "")
        implementation_tree =
            get(manifest, "implementation_tree", "")
        check(implementation_commit ==
              get(LEDGER, "attested_implementation_commit", "") &&
              implementation_tree ==
              get(LEDGER, "attested_implementation_tree", ""),
            "G3-C ledger and manifest implementation identities differ")
        artifacts = get(manifest, "artifact", Any[])
        check(!isempty(artifacts),
            "G3-C attestation manifest has no artifacts")
        for artifact in artifacts
            relative = get(artifact, "path", "")
            path = normpath(joinpath(REPO, relative))
            check(startswith(
                    relpath(path, joinpath(
                        REPO, "design", "evidence",
                        "phase-14", "g3c-closure")),
                    "..") === false &&
                  isfile(path) && !islink(path),
                "attested artifact is missing, symlinked, or outside the G3-C evidence root: $relative")
            isfile(path) || continue
            check(get(artifact, "bytes", -1) == filesize(path),
                "attested artifact byte count differs: $relative")
            actual = bytes2hex(open(SHA.sha256, path))
            check(get(artifact, "sha256", "") == actual,
                "attested artifact SHA-256 differs: $relative")
        end
        try
            head = readchomp(`git -C $REPO rev-parse HEAD`)
            resolved = readchomp(
                `git -C $REPO rev-parse $(implementation_commit)^{commit}`)
            tree = readchomp(
                `git -C $REPO show -s --format=%T $implementation_commit`)
            check(resolved == implementation_commit &&
                  tree == implementation_tree,
                "attested implementation commit/tree does not resolve")
            run(`git -C $REPO merge-base --is-ancestor $implementation_commit $head`)
            changed = split(readchomp(
                `git -C $REPO diff --name-only $implementation_commit..$head`),
                '\n'; keepempty = false)
            allowed = all(path ->
                path == "design/audits/phase-14-g3c-closure-ledger-v1.toml" ||
                startswith(path,
                    "design/evidence/phase-14/g3c-closure/") ||
                path in STATUS_DOCUMENTS,
                changed)
            check(allowed,
                "post-implementation changes exceed evidence, ledger, and the narrowly whitelisted status documents")
            foreach(validate_status_document, STATUS_DOCUMENTS)
            check(isempty(readchomp(
                    `git -C $REPO status --porcelain --untracked-files=all`)),
                "G3-C closure checker requires a clean attestation checkout")
        catch error
            check(false,
                "G3-C git attestation validation failed: $(sprint(showerror, error))")
        end
    end
end

if !isempty(failures)
    println("Phase 14 G3-C closure: OPEN")
    foreach(message -> println(" - ", message), failures)
    exit(1)
end

println("Phase 14 G3-C closure: PASS")
if evidence_only
    println("  dual-backend hardware evidence is admissible for attestation")
else
    println("  exact canonical Wang paper profile passed on real Metal and ROCm")
    println("  G3-B revision-7 semantics remained unchanged")
end
