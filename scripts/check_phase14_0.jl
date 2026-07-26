#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function load_toml(relative_path)
    path = joinpath(REPO, relative_path)
    isfile(path) || error("missing Phase 14.0 artifact: $relative_path")
    return TOML.parsefile(path)
end

function unique_ids(rows, label)
    ids = [get(row, "id", "") for row in rows]
    check(all(id -> !isempty(id), ids), "$label contains an empty id")
    check(length(ids) == length(unique(ids)), "$label contains duplicate ids")
    return Set(ids)
end

function require_fields(row, fields, label)
    for field in fields
        check(haskey(row, field), "$label is missing field '$field'")
        haskey(row, field) || continue
        value = row[field]
        if value isa AbstractString
            check(!isempty(strip(value)), "$label has an empty '$field'")
        end
    end
end

sources = load_toml("design/audits/phase-14-model-source-records-v1.toml")
closures = load_toml("design/audits/phase-14-source-closure-v1.toml")
matrix = load_toml("design/audits/phase-14-model-capability-matrix-v1.toml")
work = load_toml("design/audits/phase-14-d9-work-items-v1.toml")
morpheus = load_toml("design/audits/phase-14-morpheus-continuous-semantics-v1.toml")
wang_order = load_toml("design/audits/phase-14-wang-order-oracle-v1.toml")
g3b_entry = load_toml("design/audits/phase-14-g3b-entry-contract-v1.toml")
wang_order_evidence = load_toml("design/evidence/phase-14/wang-order/index.toml")
old_registry = load_toml("spec/phase-14-contract-registry-v1.toml")
registry = load_toml("spec/phase-14-contract-registry-v2.toml")
phase14_public_api = load_toml("design/audits/phase-14-public-api-v2.toml")
wortel_evidence_path = joinpath(
    REPO, "design", "audits", "phase-14-wortel-vertical-slice-evidence.md")
check(isfile(wortel_evidence_path),
    "missing Wortel vertical-slice evidence record")
gpu_plan_path = joinpath(
    REPO, "design", "audits", "phase-14-gpu-native-implementation-plan.md")
check(isfile(gpu_plan_path), "missing Phase 14 GPU-native implementation plan")
gpu_decision_path = joinpath(
    REPO, "spec", "decisions", "0032-phase-14-gpu-native-promotion.md")
check(isfile(gpu_decision_path), "missing Phase 14 GPU-native promotion decision")
generic_authoring_decision_path = joinpath(
    REPO, "spec", "decisions", "0033-phase-14-generic-hierarchical-authoring.md")
check(isfile(generic_authoring_decision_path),
    "missing Phase 14 generic hierarchical authoring decision")
generic_authoring_audit_path = joinpath(
    REPO, "design", "audits", "phase-14-generic-authoring-simplification-audit.md")
check(isfile(generic_authoring_audit_path),
    "missing Phase 14 generic authoring simplification audit")
wang_order_audit_path = joinpath(
    REPO, "design", "audits", "phase-14-wang-order-audit.md")
check(isfile(wang_order_audit_path), "missing Wang execution-order audit")
g3b_closure_audit_path = joinpath(
    REPO, "design", "audits", "phase-14-g3b-closure-spec-audit.md")
check(isfile(g3b_closure_audit_path),
    "missing G3-B closure specification audit")

source_rows = sources["models"]
closure_rows = closures["models"]
capability_rows = matrix["capabilities"]
work_rows = work["work_items"]
morpheus_sources = morpheus["sources"]
morpheus_rows = morpheus["features"]
contract_rows = registry["contracts"]
old_contract_rows = old_registry["contracts"]
disposition_rows = registry["old_contract_dispositions"]

model_ids = unique_ids(source_rows, "source records")
closure_ids = unique_ids(closure_rows, "source-closure records")
capability_ids = unique_ids(capability_rows, "capability matrix")
work_ids = unique_ids(work_rows, "D9 work-item registry")
morpheus_source_ids = unique_ids(morpheus_sources, "Morpheus sources")
morpheus_feature_ids = unique_ids(morpheus_rows, "Morpheus feature matrix")
contract_ids = unique_ids(contract_rows, "contract registry")
old_contract_ids = unique_ids(old_contract_rows, "old contract registry")
disposition_ids = Set(get(row, "old_id", "") for row in disposition_rows)

expected_models = Set([
    "graner-glazier-1992-sorting",
    "mombach-1995-3d-sorting",
    "merks-2006-vasculogenesis",
    "wortel-2021-act-cpm",
    "shirinifard-2012-cnv",
    "wang-2025-collective-tumor-migration",
])

check(sources["status"] == "accepted", "source record set is not accepted")
check(sources["portfolio_size"] == 6, "source record portfolio_size is not 6")
check(model_ids == expected_models, "source records do not contain the frozen six-model portfolio")
check(closures["status"] == "accepted", "source-closure record is not accepted")
check(Set(closures["portfolio_ids"]) == expected_models, "source-closure portfolio_ids differ from source records")
check(closure_ids == expected_models, "source-closure rows differ from the frozen portfolio")
check(matrix["status"] == "accepted-requirements-baseline", "capability matrix is not an accepted requirements baseline")
check(work["status"] == "accepted-phase14.1-simplified-gpu-native-planning", "D9 work-item registry is not accepted for the simplified GPU-native Phase 14.1 architecture")
check(morpheus["status"] == "accepted-requirements-baseline", "Morpheus matrix is not an accepted requirements baseline")
check(wang_order["status"] == "accepted-source-and-runtime-order",
    "Wang execution-order authority is not accepted")
check(wang_order_evidence["status"] == "pass",
    "Wang CompuCell3D 4.2.5 runtime oracle did not pass")
check(wang_order["history_discrepancy"]["classification"] ==
      "paper-t-minus-5_source-t-minus-4",
    "Wang paper/source history discrepancy is not registered")
check(g3b_entry["schema_version"] == "1.6.0" &&
      g3b_entry["revision"] == 7,
    "G3-B entry contract is not the revision-7 fail-closed closure contract")
check(g3b_entry["source_time_mapping"]["source_first"] == 0 &&
      g3b_entry["source_time_mapping"]["target_first"] == 1 &&
      g3b_entry["source_time_mapping"]["source_last"] == 499 &&
      g3b_entry["source_time_mapping"]["target_last"] == 500,
    "G3-B source MCS mapping is not 0:499 -> target 1:500")
check(occursin("phase14.1-owner-approved-simplified", registry["status"]), "contract registry is not the owner-approved simplified Phase 14.1 set")
expected_contracts = Set([
    "state",
    "process",
    "plan",
    "lifecycle",
    "observation",
    "spatial-roles",
    "potts-algorithm-identities",
])
check(contract_ids == expected_contracts, "registry v2 does not contain exactly the seven accepted semantic areas")
check(Set(registry["canonical_model"]["areas"]) == expected_contracts, "canonical model areas differ from registered contracts")
check(length(contract_rows) == 7, "expected exactly seven registry v2 contracts")
check(haskey(registry, "gpu_native_policy"), "registry v2 is missing the GPU-native promotion policy")
if haskey(registry, "gpu_native_policy")
    gpu_policy = registry["gpu_native_policy"]
    check(Set(gpu_policy["stable_targets"]) == Set(["CPU", "Metal", "ROCm"]),
        "GPU-native policy must require CPU, Metal, and ROCm")
    check(gpu_policy["portable_floating_precision"] == "Float32",
        "GPU-native portable floating-point profile must be Float32")
    check("CUDA" in gpu_policy["deferred_targets"],
        "GPU-native policy must preserve CUDA as deferred")
end
check(disposition_ids == old_contract_ids, "registry v2 does not disposition every registry v1 contract")
check(length(disposition_rows) == length(old_contract_rows), "registry v2 has duplicate or missing old-contract dispositions")
for row in disposition_rows
    require_fields(row, ["old_id", "disposition", "target"], "old-contract disposition")
    check(row["target"] in contract_ids, "old contract '$(row["old_id"])' maps to unknown v2 target '$(row["target"])'")
end

source_required = [
    "source_record_version", "portfolio_status", "release_status", "author_coverage",
    "title", "citation", "doi", "paper_url", "supplementary_sources", "data_sources",
    "primary_target", "target_kind",
    "source_simulator", "source_revision", "source_code_license", "paper_asset_license",
    "permitted_repository_assets", "authority_order", "domain", "boundary_conditions",
    "proposal_relation", "contact_relation", "surface_relation", "query_relation",
    "field_relation", "algorithm", "attempt_budget", "precision", "simulation_horizon",
    "temperature", "initialization", "initialization_checksum", "staged_protocol",
    "update_schedule", "field_splitting", "lifecycle",
    "seed_policy", "source_replicates", "observation_schedule", "analysis", "mechanisms",
    "mechanism_traceability", "parameters", "parameter_ownership", "capability_ids",
    "unresolved_ambiguities", "source_closure", "validation_target_id",
    "sensitivity_plan_id", "license_disposition", "paper_hash_scope",
    "source_simulator_version",
]

source_by_id = Dict(row["id"] => row for row in source_rows)
closure_by_id = Dict(row["id"] => row for row in closure_rows)
capability_by_id = Dict(row["id"] => row for row in capability_rows)

for row in source_rows
    id = row["id"]
    require_fields(row, source_required, "source record '$id'")
    check(row["source_record_version"] == "1.0.0", "source record '$id' is not version 1.0.0")
    check(row["portfolio_status"] == "frozen", "source record '$id' is not frozen")
    check(row["release_status"] == "Reimplementation in Progress", "source record '$id' overclaims its reproduction status")
    check(row["validation_target_id"] == closure_by_id[id]["validation_target_id"], "validation target mismatch for '$id'")
    check(row["sensitivity_plan_id"] == closure_by_id[id]["sensitivity_plan_id"], "sensitivity-plan mismatch for '$id'")
    mapped_mechanisms = Set{String}()
    for mapping in row["mechanism_traceability"]
        pieces = split(mapping, "=>"; limit=2)
        check(length(pieces) == 2, "source record '$id' has malformed mechanism mapping '$mapping'")
        length(pieces) == 2 || continue
        mechanism = strip(pieces[1])
        push!(mapped_mechanisms, mechanism)
        check(mechanism in row["mechanisms"], "source record '$id' maps unknown mechanism '$mechanism'")
        mapped_capabilities = [strip(capability) for capability in split(pieces[2], ",")]
        check(!isempty(mapped_capabilities) && all(!isempty, mapped_capabilities),
            "source record '$id' has an empty capability in mechanism mapping '$mapping'")
        for capability in mapped_capabilities
            check(capability in row["capability_ids"],
                "source record '$id' mechanism '$mechanism' maps to undeclared capability '$capability'")
            check(capability in capability_ids,
                "source record '$id' mechanism '$mechanism' maps to unknown capability '$capability'")
        end
    end
    check(mapped_mechanisms == Set(row["mechanisms"]),
        "source record '$id' does not map every mechanism exactly once")
    for capability in row["capability_ids"]
        check(capability in capability_ids, "source record '$id' references unknown capability '$capability'")
    end
end

closure_required = [
    "source_closure", "validation_target_id", "validation_target", "baseline_policy",
    "claim_boundary", "authority_order", "license_disposition", "sensitivity_plan_id",
]
for row in closure_rows
    id = row["id"]
    require_fields(row, closure_required, "source closure '$id'")
    check(row["source_closure"] == source_by_id[id]["source_closure"], "source-closure class mismatch for '$id'")
    if startswith(row["source_closure"], "closed-with")
        require_fields(row, ["sensitivity_axes", "failure_rule", "clarification_questions"], "paper-only source closure '$id'")
    elseif startswith(row["source_closure"], "pinned-source")
        require_fields(row, ["transcribed_execution", "source_file_sha256"], "pinned source closure '$id'")
    else
        fail("source closure '$id' has unknown class '$(row["source_closure"])'")
    end
end

paper_only = count(row -> startswith(row["source_closure"], "closed-with"), closure_rows)
pinned = count(row -> startswith(row["source_closure"], "pinned-source"), closure_rows)
check(paper_only == 3, "expected three paper-only sensitivity closures, found $paper_only")
check(pinned == 3, "expected three pinned-source closures, found $pinned")

capability_required = [
    "name", "classification", "models", "current_evidence", "required_work", "owner",
    "decision_dependency", "conformance_plan", "persistence_impact", "api_layer",
    "backend_claim", "implementation_chunk", "freeze_impact", "unresolved",
]
allowed_classes = Set(keys(matrix["classes"]))
for row in capability_rows
    id = row["id"]
    require_fields(row, capability_required, "capability '$id'")
    check(row["classification"] in allowed_classes, "capability '$id' has unknown classification")
    backend_claim = lowercase(row["backend_claim"])
    check(occursin("metal", backend_claim) && occursin("rocm", backend_claim),
        "capability '$id' does not state its Metal and ROCm promotion boundary")
    for model in row["models"]
        check(model in model_ids, "capability '$id' references unknown model '$model'")
        model in model_ids || continue
        check(id in source_by_id[model]["capability_ids"], "capability '$id' -> model '$model' is not bidirectional")
    end
end
for row in source_rows, capability in row["capability_ids"]
    check(row["id"] in capability_by_id[capability]["models"], "model '$(row["id"])' -> capability '$capability' is not bidirectional")
end

contract_required = [
    "version", "family", "specification", "semantic_status", "implementation_status", "public_values",
    "source_models", "capability_ids", "snapshot", "reads", "writes", "persistence",
    "fingerprint", "cpu", "metal", "rocm", "freeze_impact", "acceptance_requires",
]
covered_capabilities = Set{String}()
for row in contract_rows
    id = row["id"]
    require_fields(row, contract_required, "contract '$id'")
    check(row["semantic_status"] == "provisional", "Phase 14.1 must not mark unimplemented contract '$id' accepted")
    check(row["implementation_status"] in (
        "specified-only", "wortel-cpu-reference-proven"),
        "contract '$id' has an unregistered implementation maturity")
    check(row["cpu"] == "reference_required",
        "contract '$id' does not require a CPU reference")
    check(row["metal"] == "qualification_required" &&
          row["rocm"] == "qualification_required",
        "contract '$id' does not require both Metal and ROCm qualification")
    spec_path = normpath(joinpath(REPO, "spec", row["specification"]))
    check(isfile(spec_path), "contract '$id' references missing specification '$(row["specification"])'")
    for model in row["source_models"]
        check(model in model_ids, "contract '$id' references unknown model '$model'")
    end
    for capability in row["capability_ids"]
        push!(covered_capabilities, capability)
        check(capability in capability_ids, "contract '$id' references unknown capability '$capability'")
    end
end

coverage_exclusions = union(
    Set(registry["coverage"]["existing_or_paper_specific_capability_ids"]),
    Set(registry["coverage"]["derived_tooling_capability_ids"]),
)
check(isempty(setdiff(capability_ids, union(covered_capabilities, coverage_exclusions))),
    "one or more capability rows lack a contract or explicit existing/paper-specific classification")
check(isempty(setdiff(covered_capabilities, capability_ids)), "contract registry contains unknown capability ids")

authoring = registry["authoring_composition"]
require_fields(authoring, [
    "root_model", "hierarchy", "requirements", "exports", "plan", "lowering",
    "identity", "paper_boundary", "backend_boundary", "acceptance_fixtures",
], "generic authoring composition policy")
check(occursin("ModelFragment", authoring["hierarchy"]),
    "generic authoring policy does not use ModelFragment as the sole hierarchy")
check(occursin("one normalized root plan", lowercase(authoring["plan"])),
    "generic authoring policy does not preserve one root plan")
check(occursin("named", lowercase(authoring["requirements"])) &&
      occursin("typed", lowercase(authoring["requirements"])) &&
      occursin("named", lowercase(authoring["exports"])),
    "generic authoring policy lacks named typed requirements/exports")
check(occursin("transitively", lowercase(authoring["backend_boundary"])),
    "generic authoring policy does not derive backend requirements transitively")

paper_export_tokens = (
    "wang", "wortel", "merks", "mombach", "shirinifard", "graner", "glazier", "cnv",
)
phase14_exports = String[]
for module_exports in Base.values(phase14_public_api["modules"])
    append!(phase14_exports, module_exports)
end
for row in contract_rows
    append!(phase14_exports, row["public_values"])
end
for exported in phase14_exports
    lowered = lowercase(exported)
    check(!any(token -> occursin(token, lowered), paper_export_tokens),
        "paper-specific public API value '$exported' is forbidden by Decision 0033")
end

work_contracts = Set{String}()
work_capabilities = Set{String}()
work_required = [
    "semantic_family", "specification", "contracts", "capabilities", "owner",
    "implementation_chunk", "first_proving_models", "source_gate", "conformance_plan",
    "persistence_impact", "api_layer", "backend_claim", "d10_classification",
]
for row in work_rows
    id = row["id"]
    require_fields(row, work_required, "D9 work item '$id'")
    backend_claim = lowercase(row["backend_claim"])
    check(occursin("metal", backend_claim) && occursin("rocm", backend_claim) &&
          occursin("required", backend_claim),
        "D9 work item '$id' does not require both Metal and ROCm qualification")
    check(isfile(normpath(joinpath(REPO, "design", "audits", row["specification"]))),
        "D9 work item '$id' references a missing specification")
    for contract in row["contracts"]
        push!(work_contracts, contract)
        check(contract in contract_ids, "D9 work item '$id' references unknown contract '$contract'")
    end
    for capability in row["capabilities"]
        push!(work_capabilities, capability)
        check(capability in capability_ids, "D9 work item '$id' references unknown capability '$capability'")
    end
    for model in row["first_proving_models"]
        check(model in model_ids, "D9 work item '$id' references unknown proving model '$model'")
    end
end
check(work_contracts == contract_ids, "D9 work items do not cover every registered contract exactly as a set")
check(isempty(setdiff(capability_ids, union(work_capabilities, coverage_exclusions))),
    "D9 work items do not cover every new capability")

morpheus_contracts = Set{String}()
for row in morpheus_rows
    id = row["id"]
    require_fields(row, ["name", "classification", "semantic_requirement", "source_ids", "required_contract_ids", "phase14_status", "acceptance_fixture"], "Morpheus feature '$id'")
    for source in row["source_ids"]
        check(source in morpheus_source_ids, "Morpheus feature '$id' references unknown source '$source'")
    end
    for contract in row["required_contract_ids"]
        push!(morpheus_contracts, contract)
        check(contract in contract_ids, "Morpheus feature '$id' references unknown contract '$contract'")
    end
end
check(length(morpheus_feature_ids) == 20, "expected 20 Morpheus semantic feature rows")
check(!isempty(morpheus_contracts), "Morpheus matrix does not trace to Phase 14 contracts")

freeze_decision = read(joinpath(REPO, "spec/decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md"), String)
architecture_decision = read(joinpath(REPO, "spec/decisions/0031-phase-14-single-semantic-kernel.md"), String)
gpu_decision = read(gpu_decision_path, String)
generic_authoring_decision = read(generic_authoring_decision_path, String)
generic_authoring_audit = read(generic_authoring_audit_path, String)
gpu_plan = read(gpu_plan_path, String)
kernel = read(joinpath(REPO, "spec/phase-14-semantic-kernel.md"), String)
coupled_api = read(joinpath(REPO, "spec/phase-14-coupled-dynamics-api.md"), String)
interview = read(joinpath(REPO, "design/audits/phase-14-semantics-focused-interview.md"), String)
audit = read(joinpath(REPO, "design/audits/phase-14-0-corpus-and-requirements-audit.md"), String)
roadmap = read(joinpath(REPO, "design/refactor-roadmap.md"), String)
check(occursin("Status: Accepted for Phase 14.0 architecture", freeze_decision), "Decision 0030 is not accepted at the Phase 14.0/D10 boundary")
check(occursin("Mermaid.jl integration is explicitly outside Phase 14.0", freeze_decision), "Decision 0030 does not preserve the Mermaid.jl scope exclusion")
check(occursin("Status: Accepted", architecture_decision), "Decision 0031 is not accepted")
check(occursin("seven stable contract areas", architecture_decision), "Decision 0031 does not freeze the seven-area kernel")
check(occursin("Status: Accepted", gpu_decision), "Decision 0032 is not accepted")
check(occursin("Metal", gpu_decision) && occursin("ROCm", gpu_decision),
    "Decision 0032 does not require Metal and ROCm")
check(occursin("Status: Accepted policy", generic_authoring_decision),
    "Decision 0033 is not accepted")
check(occursin("ModelFragment", generic_authoring_decision) &&
      occursin("named typed requirements", generic_authoring_decision) &&
      occursin("exports", generic_authoring_decision),
    "Decision 0033 does not freeze generic hierarchical fragment composition")
check(occursin("Status: Complete", generic_authoring_audit),
    "generic authoring simplification audit is not complete")
check(occursin("Wortel GPU closure", gpu_plan),
    "GPU-native implementation plan does not make Wortel closure explicit")
check(occursin("Status: Complete; all 15 owner decisions accepted", interview), "focused simplification interview is not complete")
check(occursin("sole normative architecture", kernel), "kernel specification is not the sole normative Phase 14 architecture")
check(occursin("Generic hierarchical composition", kernel) &&
      occursin("named typed requirements", kernel) &&
      occursin("named typed exports", kernel),
    "kernel specification lacks the generic hierarchical authoring boundary")
wang_heading = findfirst("### Wang collective migration", coupled_api)
cnv_heading = findfirst("### CNV", coupled_api)
merks_heading = findfirst("### Merks vasculogenesis", coupled_api)
if wang_heading === nothing || cnv_heading === nothing
    check(false, "coupled API is missing Wang or CNV representative headings")
else
    wang_section = coupled_api[first(wang_heading):prevind(coupled_api, first(cnv_heading))]
    check(occursin("model = compose(", wang_section),
        "Wang authoring sketch is not composed from generic fragments")
    check(occursin("ModelFragment(", wang_section) &&
          occursin("exports = (", wang_section),
        "Wang authoring sketch lacks named generic fragment exports")
    check(!occursin("model = PottsModel(\n    Tumor", wang_section),
        "Wang authoring sketch regressed to a flattened PottsModel declaration list")
    cnv_section = coupled_api[first(cnv_heading):end]
    check(occursin("model = compose(", cnv_section),
        "CNV authoring sketch is not composed from generic fragments")
end
if merks_heading === nothing || wang_heading === nothing
    check(false, "coupled API is missing Merks or Wang representative headings")
else
    merks_section = coupled_api[first(merks_heading):prevind(
        coupled_api, first(wang_heading))]
    check(occursin("ModelFragment(", merks_section) &&
          occursin("model = compose(", merks_section),
        "Merks authoring sketch is not composed from generic fragments")
end
for contract in expected_contracts
    heading = contract == "potts-algorithm-identities" ? "Contract 7: Potts Algorithm Identities" :
        contract == "spatial-roles" ? "Contract 6: Spatial Roles" :
        contract == "observation" ? "Contract 5: Observation" :
        contract == "lifecycle" ? "Contract 4: Lifecycle" :
        contract == "plan" ? "Contract 3: Plan" :
        contract == "process" ? "Contract 2: Process" :
        "Contract 1: State"
    check(occursin(heading, kernel), "kernel specification is missing '$heading'")
end
check(occursin("Status: Complete; six-model portfolio frozen", audit), "Phase 14.0 audit is not marked complete")
check(occursin("Phase 14.0 complete", roadmap), "roadmap does not record Phase 14.0 completion")

phase14_markdown = [
    joinpath(REPO, "design/audits/phase-14-0-corpus-and-requirements-audit.md"),
    joinpath(REPO, "design/refactor-roadmap.md"),
    joinpath(REPO, "spec/README.md"),
    joinpath(REPO, "spec/decisions/README.md"),
    joinpath(REPO, "spec/decisions/0029-phase-14-model-driven-capability-and-documentation-policy.md"),
    joinpath(REPO, "spec/decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md"),
    joinpath(REPO, "spec/decisions/0031-phase-14-single-semantic-kernel.md"),
    gpu_decision_path,
    generic_authoring_decision_path,
    generic_authoring_audit_path,
    gpu_plan_path,
    wang_order_audit_path,
    joinpath(REPO, "design/audits/phase-14-semantics-simplification-audit.md"),
    joinpath(REPO, "design/audits/phase-14-semantics-focused-interview.md"),
]
append!(phase14_markdown, filter(
    path -> startswith(basename(path), "phase-14-") && endswith(path, ".md"),
    readdir(joinpath(REPO, "spec"); join = true),
))
for path in phase14_markdown
    text = read(path, String)
    fence_count = length(collect(eachmatch(r"```", text)))
    check(iseven(fence_count), "$(relpath(path, REPO)) has an unbalanced fenced code block")
    for match in eachmatch(r"!?\[[^\]]*\]\(([^)]+)\)", text)
        target = strip(match.captures[1])
        (startswith(target, "http://") || startswith(target, "https://") ||
         startswith(target, "mailto:") || startswith(target, "#")) && continue
        target = first(split(target, '#'))
        target = strip(target, ['<', '>'])
        isempty(target) && continue
        resolved = normpath(joinpath(dirname(path), target))
        check(ispath(resolved), "$(relpath(path, REPO)) has a missing local link target '$target'")
    end
end

stale_phrases = [
    "Phase 14.0 remains open",
    "not ready to freeze",
    "candidate-freeze",
    "In progress (14.0)",
    "ready for detailed source transcription",
    "not yet transcribed",
]
closure_text = join(read(path, String) for path in phase14_markdown)
for phrase in stale_phrases
    check(!occursin(phrase, closure_text), "stale Phase 14.0 status remains: '$phrase'")
end

if isempty(failures)
    println("Phase 14 corpus and simplified architecture closure passes:")
    println("  6 frozen source records and 6 source-closure records")
    println("  every named paper mechanism mapped through $(length(capability_ids)) bidirectional capability rows")
    println("  all $(length(old_contract_ids)) registry v1 contracts dispositioned into $(length(contract_ids)) registry v2 semantic areas")
    println("  $(length(contract_ids)) provisional kernel contracts covered by $(length(work_ids)) vertical work items")
    println("  $(length(morpheus_feature_ids)) Morpheus semantic requirements traced to registered contracts")
    println("  Decisions 0031–0033 and all 15 owner choices accepted; generic hierarchical authoring enforced")
    println("  no selected-paper names exported; Wang sketch uses generic fragments and one root plan")
    println("  Wortel CPU/Metal/ROCm G2 passed")
    println("  Wang source/runtime order and source 0:499 -> target 1:500 mapping accepted, including the explicit paper t-5 versus source t-4 history variant")
    println("  D10 additive classification preserved; Mermaid.jl remains out of scope")
else
    println(stderr, "Phase 14 architecture closure failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end
