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
algebraic_decision_path =
    require_file("spec/decisions/0036-algebraicjulia-process-bigraph-foundation.md")
composition_decision_path =
    require_file("spec/decisions/0037-process-bigraph-open-composition.md")
serial_alpha_decision_path =
    require_file("spec/decisions/0038-process-bigraph-serial-alpha.md")
semantics_path = require_file("spec/process-bigraph-runtime-semantics.md")
audit_path = require_file(
    "design/audits/process-bigraph-runtime-parity-and-parallel-development-audit.md")
interview_path = require_file(
    "design/audits/process-bigraph-runtime-owner-interview.md")
algebraic_interview_path = require_file(
    "design/audits/process-bigraph-algebraicjulia-owner-interview.md")
composition_interview_path = require_file(
    "design/audits/process-bigraph-phase15b-open-composition-owner-interview.md")
composition_plan_path = require_file(
    "design/audits/process-bigraph-phase15b-open-composition-plan.md")
serial_alpha_interview_path = require_file(
    "design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md")
serial_alpha_plan_path = require_file(
    "design/audits/process-bigraph-phase15c-serial-alpha-plan.md")
serial_alpha_entry_path = require_file("spec/process-bigraph-phase15c-entry-v1.toml")
serial_alpha_entry_audit_path = require_file(
    "design/audits/process-bigraph-phase15c-entry-audit.md")
charter_path = require_file("spec/project-charter.md")
architecture_path = require_file("design/repository-architecture-standard.md")
roadmap_path = require_file("design/refactor-roadmap.md")
decision_index_path = require_file("spec/decisions/README.md")
spec_index_path = require_file("spec/README.md")
evidence_index_path = require_file("spec/conformance-evidence.md")
package_project_path = require_file("lib/ProcessBigraphs/Project.toml")
package_registry_path = require_file("lib/ProcessBigraphs/parity-registry.toml")
package_runner_path = require_file("lib/ProcessBigraphs/test/runtests.jl")
pb0_audit_path = require_file(
    "design/audits/process-bigraph-pb0-implementation-audit.md")
pb0_evidence_path = require_file(
    "design/evidence/process-bigraph-pb0-evidence-v1.toml")
pb0_checker_path = require_file("scripts/process-bigraph-pb0-check.jl")
phase15a_audit_path = require_file(
    "design/audits/process-bigraph-phase15a-canonical-structure-audit.md")
phase15a_evidence_path = require_file(
    "design/evidence/process-bigraph-phase15a-evidence-v1.toml")
phase15a_checker_path = require_file("scripts/process-bigraph-phase15a-check.jl")
phase15a_test_path = require_file(
    "lib/ProcessBigraphs/test/test_phase15a_algebraic_structure.jl")
phase15b_audit_path = require_file(
    "design/audits/process-bigraph-phase15b-open-composition-audit.md")
phase15b_evidence_path = require_file(
    "design/evidence/process-bigraph-phase15b-evidence-v1.toml")
phase15b_checker_path = require_file("scripts/process-bigraph-phase15b-check.jl")
phase15b_test_path = require_file(
    "lib/ProcessBigraphs/test/test_phase15b_open_composition.jl")
algebraic_source_path = require_file(
    "lib/ProcessBigraphs/src/algebraic_structure.jl")
composition_source_path = require_file(
    "lib/ProcessBigraphs/src/composition.jl")
lowering_source_path = require_file("lib/ProcessBigraphs/src/lowering.jl")
runtime_source_path = require_file("lib/ProcessBigraphs/src/runtime.jl")

registry = TOML.parsefile(registry_path)
sources = registry["sources"]
features = registry["features"]
oracles = registry["oracles"]
source_ids = unique_ids(sources, "source registry")
feature_ids = unique_ids(features, "feature registry")
oracle_ids = unique_ids(oracles, "oracle registry")

check(registry["schema_version"] == "1.3.0", "unexpected parity-registry schema")
check(registry["registry_status"] in (
        "phase15c-entry-frozen-runtime-not-started",
        "phase15c-implementation-candidate-awaiting-attestation",
        "phase15c-qualified-serial-internal-alpha",
    ),
    "parity registry has an unknown Phase 15.C lifecycle state")
check(registry["package_name"] == "ProcessBigraphs.jl",
    "runtime package identity is not ProcessBigraphs.jl")
check(registry["incubation_path"] == "lib/ProcessBigraphs",
    "runtime incubation path changed")
check(registry["decisions"] == [
    "decisions/0034-process-bigraph-runtime-platform.md",
    "decisions/0036-algebraicjulia-process-bigraph-foundation.md",
    "decisions/0037-process-bigraph-open-composition.md",
    "decisions/0038-process-bigraph-serial-alpha.md",
    "decisions/0039-phase-16-compute-ownership-and-scope.md",
], "parity registry decision authorities changed")
check(registry["owner_interviews"] == [
    "../design/audits/process-bigraph-runtime-owner-interview.md",
    "../design/audits/process-bigraph-algebraicjulia-owner-interview.md",
    "../design/audits/process-bigraph-phase15b-open-composition-owner-interview.md",
    "../design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md",
    "../design/audits/process-bigraph-phase16-owner-interview.md",
], "parity registry owner-interview authorities changed")

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
check("pinned_python" ∉ allowed_oracle_kinds,
    "live pinned-Python oracle kind must not be admitted")
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
    check(oracle["kind"] != "pinned_python",
        "oracle '$id' attempts to execute a pinned Python runtime")
end

required_algebraic_features = Set([
    "canonical-process-bigraph-acset",
    "structured-cospan-open-composition",
    "derived-directed-wiring-view",
    "compiled-structural-epoch",
    "algebraic-rewriting-structural-transactions",
    "algebraicdynamics-scientific-extension",
    "independent-julia-specification-oracle",
])
check(required_algebraic_features <= feature_ids,
    "registry omits an accepted AlgebraicJulia or independent-conformance feature")
required_algebraic_oracles = Set([
    "oracle-algebraic-structure",
    "oracle-algebraic-invariance",
    "oracle-algebraic-rewriting",
    "oracle-algebraicdynamics-extension",
    "oracle-independent-specification",
])
check(required_algebraic_oracles <= oracle_ids,
    "registry omits an accepted AlgebraicJulia or independent-conformance oracle")

algebraic_policy = registry["algebraicjulia_policy"]
check(algebraic_policy["phase15_direct_dependencies"] == ["ACSets.jl", "Catlab.jl"],
    "Phase 15 AlgebraicJulia dependencies changed")
check(algebraic_policy["phase16_direct_dependency"] == "AlgebraicRewriting.jl",
    "Phase 16 rewriting dependency changed")
check(algebraic_policy["phase17_weak_dependency"] == "AlgebraicDynamics.jl",
    "Phase 17 AlgebraicDynamics extension boundary changed")
check(algebraic_policy["row_identity"] == "nonsemantic",
    "ACSet row identity became semantic")
check(occursin("no ACSet traversal", algebraic_policy["hot_path"]),
    "compiled hot-path boundary no longer excludes ACSet traversal")
check(occursin("ProcessBigraphs exclusively owns", algebraic_policy["runtime_authority"]),
    "ProcessBigraphs is no longer the sole runtime authority")

conformance_policy = registry["conformance_policy"]
check(conformance_policy["upstream_runtime_execution"] == "forbidden",
    "upstream runtime execution is not fail-closed")
check(occursin("independent", lowercase(conformance_policy["specification_oracle"])),
    "independent Julia specification oracle is not required")
check(Set(conformance_policy["forbidden_runtimes"]) ==
      Set(["Vivarium", "Process-Bigraph Python", "Bigraph-Schema Python"]),
    "forbidden upstream runtime list changed")

feature_by_id = Dict(feature["id"] => feature for feature in features)
expected_pb0_implemented = Set([
    "stable-typed-paths",
    "typed-hierarchical-store",
    "structural-schema-realization",
    "typed-input-output-ports",
    "workflow-cycle-rejection",
    "exact-integer-logical-time",
    "actual-elapsed-partial-interval",
    "same-time-common-snapshot",
    "typed-process-deltas",
    "deterministic-conflict-reconciliation",
    "atomic-event-commit",
])
expected_phase15a_implemented = Set([
    "canonical-process-bigraph-acset",
    "compiled-structural-epoch",
])
expected_phase15b_implemented = Set([
    "structured-cospan-open-composition",
    "derived-directed-wiring-view",
])
check(all(feature_by_id[id]["status"] in (
        "implemented", "oracle_passing", "qualified")
      for id in expected_pb0_implemented),
    "a PB0 row regressed below implemented")
check(all(occursin("direct_passing_pb0",
          feature_by_id[id]["evidence_status"])
      for id in expected_pb0_implemented),
    "a PB0 row lost its direct evidence history")
check(all(feature["evidence_status"] == "direct_passing_phase15a"
          for feature in features if feature["id"] in expected_phase15a_implemented),
    "every Phase 15.A row must cite direct_passing_phase15a evidence")
check(all(feature["evidence_status"] == "direct_passing_phase15b"
          for feature in features if feature["id"] in expected_phase15b_implemented),
    "every Phase 15.B row must cite direct_passing_phase15b evidence")

pb0 = registry["pb0_implementation"]
check(pb0["status"] == "passed_bounded_foundation",
    "PB0 implementation status is not the bounded foundation claim")
check(Set(pb0["implemented_direct_rows"]) == expected_pb0_implemented,
    "PB0 registry summary does not match implemented feature rows")

package_project = TOML.parsefile(package_project_path)
check(package_project["name"] == "ProcessBigraphs",
    "PB0 package name changed")
check(package_project["uuid"] == "efcc6515-205e-41e3-b553-f38f05ad529c",
    "PB0 package UUID changed")
check(get(package_project["compat"], "julia", "") == "1.12.6",
    "PB0 package must target Julia 1.12.6 exactly")
check(Set(keys(get(package_project, "deps", Dict{String,Any}()))) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]),
    "Phase 16 package dependencies must include bounded AlgebraicRewriting")
check(get(package_project["compat"], "ACSets", "") == "0.2.29" &&
      get(package_project["compat"], "Catlab", "") == "0.17.6" &&
      get(package_project["compat"], "AlgebraicRewriting", "") == "0.5",
    "Phase 16 AlgebraicJulia compatibility bounds changed")

package_registry = TOML.parsefile(package_registry_path)
check(package_registry["schema_version"] == "1.3.0",
    "package-local parity registry has not closed Decision 0037")
check(package_registry["status_policy"]["upstream_runtime_execution"] == "forbidden",
    "package-local parity registry permits upstream runtime execution")
check(package_registry["maturity"] in (
        "phase_15b_open_composition",
        "phase_15c_implementation_candidate",
        "phase_15c_serial_internal_alpha",
    ),
    "package-local registry no longer preserves Phase 15.B maturity")
check(package_registry["accepted_next_architecture"]["phase15a_status"] ==
      "passed_canonical_structure",
    "package-local registry does not close the bounded Phase 15.A slice")
check(package_registry["accepted_next_architecture"]["phase15b_status"] ==
      "passed_open_composition",
    "package-local registry does not close Phase 15.B")
check(package_registry["accepted_next_architecture"]["phase16_status"] in
      ("phase16b_candidate", "phase16b_qualified") &&
      package_registry["accepted_next_architecture"]["phase16_internal_beta"] == false &&
      package_registry["accepted_next_architecture"]["phase16_public_release"] == false,
    "package-local registry must record the current Phase 16.B state without beta")
check(package_registry["accepted_next_architecture"]["phase15_direct_dependencies"] ==
      ["ACSets.jl", "Catlab.jl"],
    "package-local Phase 15 dependency decision changed")

phase15a = registry["phase15a_implementation"]
check(phase15a["status"] == "passed_canonical_structure",
    "root registry does not close the bounded Phase 15.A slice")
check(Set(phase15a["implemented_rows"]) == expected_phase15a_implemented,
    "Phase 15.A summary does not match implemented registry rows")
phase15b = registry["phase15b_implementation"]
expected_phase15b_targets = Set([
    "structured-cospan-open-composition",
    "derived-directed-wiring-view",
])
check(phase15b["status"] == "passed_open_composition",
    "root registry does not close Phase 15.B")
check(Set(phase15b["target_rows"]) == expected_phase15b_targets &&
      Set(phase15b["implemented_rows"]) == expected_phase15b_targets,
    "Phase 15.B registry summary omits or misstates its target rows")
feature_by_id = Dict(feature["id"] => feature for feature in features)
check(all(feature_by_id[id]["status"] == "implemented" &&
          feature_by_id[id]["evidence_status"] == "direct_passing_phase15b"
          for id in expected_phase15b_targets),
    "Phase 15.B target rows do not preserve direct implementation evidence")
phase15b_evidence = TOML.parsefile(phase15b_evidence_path)
check(phase15b_evidence["status"] == "passed_open_composition",
    "Phase 15.B evidence does not record its bounded pass")
check(Set(phase15b_evidence["qualification"]["implemented_rows"]) ==
      expected_phase15b_targets,
    "Phase 15.B evidence rows disagree with the root registry")
phase15a_evidence = TOML.parsefile(phase15a_evidence_path)
check(phase15a_evidence["status"] == "passed_canonical_structure",
    "Phase 15.A evidence does not record its bounded pass")
check(Set(phase15a_evidence["qualification"]["implemented_rows"]) ==
      expected_phase15a_implemented,
    "Phase 15.A evidence rows disagree with the root registry")

pb0_evidence = TOML.parsefile(pb0_evidence_path)
check(pb0_evidence["status"] == "passed_bounded_foundation",
    "PB0 evidence does not record its bounded pass")
check(Set(pb0_evidence["qualification"]["implemented_direct_rows"]) ==
      expected_pb0_implemented,
    "PB0 evidence implemented rows disagree with the root registry")
check(pb0_evidence["pinned_python_oracles"] == "not_run" &&
      pb0_evidence["gpu_evidence"] == "not_run" &&
      pb0_evidence["threads_or_dagger_evidence"] == "not_run",
    "PB0 evidence must prove Python was not run and leave GPU/parallel qualification open")
check(!all(feature["status"] == "qualified" for feature in features
          if feature["required_for_first_public_release"]),
    "registry incorrectly declares the first public release ready")
check(registry["executor_policy"]["equivalence_reference"] == "SerialExecutor",
    "serial executor is not the alternate-executor equivalence reference")
check(occursin("independent", registry["executor_policy"]["specification_oracle"]),
    "production SerialExecutor is incorrectly serving as the specification oracle")
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
algebraic_interview = read(algebraic_interview_path, String)
check(occursin("Status: Complete; all 34 owner decisions resolved", algebraic_interview),
    "AlgebraicJulia owner interview is not complete")
composition_interview = read(composition_interview_path, String)
check(occursin("Status: Complete; all 22 owner decisions resolved", composition_interview),
    "Phase 15.B owner interview is not complete")
serial_alpha_interview = read(serial_alpha_interview_path, String)
check(occursin("Status: Complete; all 64 owner decisions resolved", serial_alpha_interview),
    "Phase 15.C owner interview is not complete")

decision = read(decision_path, String)
algebraic_decision = read(algebraic_decision_path, String)
composition_decision = read(composition_decision_path, String)
serial_alpha_decision = read(serial_alpha_decision_path, String)
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
for n in 1:34
    check(occursin(Regex("(?m)^$(n)\\."), algebraic_decision),
        "Decision 0036 is missing owner decision $n")
end
for n in 1:22
    check(occursin(Regex("(?m)^$(n)\\."), composition_decision),
        "Decision 0037 is missing owner decision $n")
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
    "AlgebraicJulia structural foundation",
    "Imminent-event scheduler",
    "Hierarchical state and schemas",
    "### Reconciliation",
    "Structural transactions",
    "Dagger",
    "Whole-cell acceptance ladder",
    "source-derived registered traces",
    "Open-composite semantics",
    "canonical semantic composition declaration is n-ary",
]
    check(occursin(phrase, semantics), "runtime semantics are missing '$phrase'")
end
check(occursin("ProcessBigraphs.jl", charter),
    "project charter omits ProcessBigraphs.jl")
check(occursin("`ProcessBigraphs` MUST NOT depend on `CorePotts`", architecture) &&
      occursin("`CorePotts` depends on `ProcessBigraphs`", architecture) &&
      occursin("`PottsToolkit` depends on `CorePotts`", architecture) &&
      occursin("`ACSets.jl` and `Catlab.jl`", architecture),
    "repository architecture omits the target dependency direction")
for phase in 14:20
    check(occursin("Phase $phase", roadmap), "roadmap omits Phase $phase")
end
for phrase in ["Potts workstream", "Runtime workstream", "Adapter", "Evidence"]
    check(occursin(phrase, roadmap), "roadmap omits the '$phrase' workstream")
end
check(occursin("G3-B", roadmap) && occursin("G4", roadmap) &&
      occursin("retired", lowercase(roadmap)),
    "roadmap omits the Wang GPU disposition and G3-B-to-G4 boundary")
check(occursin("0034-process-bigraph-runtime-platform.md", indices),
    "Decision 0034 is absent from specification indexes")
check(occursin("0036-algebraicjulia-process-bigraph-foundation.md", indices),
    "Decision 0036 is absent from specification indexes")
check(occursin("0037-process-bigraph-open-composition.md", indices),
    "Decision 0037 is absent from specification indexes")
check(occursin("0038-process-bigraph-serial-alpha.md", indices),
    "Decision 0038 is absent from specification indexes")
check(occursin("process-bigraph-runtime-semantics.md", indices),
    "runtime semantics are absent from specification indexes")
check(occursin("process-bigraph-parity-registry-v1.toml", indices),
    "parity registry is absent from specification indexes")

for path in [
    decision_path, algebraic_decision_path, composition_decision_path,
    serial_alpha_decision_path, semantics_path,
    audit_path, interview_path, algebraic_interview_path, composition_interview_path,
    composition_plan_path, serial_alpha_interview_path, serial_alpha_plan_path,
    serial_alpha_entry_path, serial_alpha_entry_audit_path, charter_path,
    architecture_path, roadmap_path, decision_index_path, spec_index_path,
    evidence_index_path, pb0_audit_path, phase15a_audit_path, phase15b_audit_path,
]
    check_local_links(path)
end

runtime_source = read(runtime_source_path, String)
check(!occursin("ACSets", runtime_source) &&
      !occursin("StaticComposite", runtime_source) &&
      !occursin("canonical_structure", runtime_source),
    "runtime hot path traverses an authoring representation")
algebraic_source = read(algebraic_source_path, String)
lowering_source = read(lowering_source_path, String)
composition_source = read(composition_source_path, String)
check(occursin("@acset_type ProcessBigraphACSet", algebraic_source) &&
      occursin("StructuralEpoch", algebraic_source) &&
      occursin("ExecutionPlan", algebraic_source),
    "canonical ACSet, structural epoch, or execution plan is missing")
check(occursin("compile_composite(model::CanonicalModel)", lowering_source) &&
      occursin("reverse_insertion", lowering_source),
    "typed lowering or row-order invariance hook is missing")
check(occursin("ProcessBigraphStructuredMulticospan", composition_source) &&
      occursin("function compose_open", composition_source) &&
      occursin("struct AnnotatedWiringDiagram", composition_source),
    "Phase 15.B composition or annotated wiring implementation is missing")

for relative_root in [".github", "scripts", "test", "lib/ProcessBigraphs/test"]
    root = joinpath(ROOT, relative_root)
    isdir(root) || continue
    for (directory, _, files) in walkdir(root)
        for file in files
            path = joinpath(directory, file)
            normpath(path) == normpath(@__FILE__) && continue
            text = try
                read(path, String)
            catch
                continue
            end
            forbidden = occursin(
                r"(?i)(pip|uv|conda)[^\n]*(process-bigraph|bigraph-schema|vivarium)", text) ||
                occursin(
                    r"(?i)\b(import|from)\s+(process_bigraph|bigraph_schema|vivarium)", text) ||
                occursin(
                    r"(?i)\bpython[0-9.]*\b[^\n]*(process-bigraph|bigraph-schema|vivarium)", text)
            check(!forbidden,
                "$(relpath(path, ROOT)) installs or executes a forbidden upstream runtime")
        end
    end
end

if isempty(failures)
    println("ProcessBigraphs platform specification passes:")
    println("  $(length(sources)) pinned research sources")
    println("  $(length(features)) classified features")
    println("  $(length(oracles)) registered conformance oracles")
    println("  all 48 owner decisions recorded")
    println("  all 34 AlgebraicJulia and independent-conformance decisions recorded")
    println("  all 22 Phase 15.B open-composition decisions recorded")
    println("  all 64 Phase 15.C serial-alpha decisions recorded")
    println("  $(length(expected_pb0_implemented)) PB0 direct rows implemented and locally tested")
    println("  $(length(expected_phase15a_implemented)) Phase 15.A canonical-structure rows implemented and locally tested")
    println("  $(length(expected_phase15b_implemented)) Phase 15.B open-composition rows implemented and locally tested")
    println("  canonical ACSet, open-composition semantics, AlgebraicJulia phase boundaries, and independent Julia oracle policy frozen")
    println("  no upstream Python runtime execution path found in CI, tests, examples, or release tooling")
    println(registry["registry_status"] == "phase15c-qualified-serial-internal-alpha" ?
        "  independent oracle and serial internal alpha qualified; GPU, parallel-executor, and public-release claims remain fail-closed" :
        "  independent-oracle, internal-alpha, GPU, parallel-executor, and public-release claims remain fail-closed")
else
    println(stderr,
        "ProcessBigraphs platform specification failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end
