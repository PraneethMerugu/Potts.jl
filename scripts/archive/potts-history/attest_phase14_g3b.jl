#!/usr/bin/env julia

using InteractiveUtils
using Pkg
using SHA
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const CONTRACT_PATH = joinpath(
    REPO, "design", "audits",
    "phase-14-g3b-entry-contract-v1.toml")
const LEDGER_PATH = joinpath(
    REPO, "design", "audits",
    "phase-14-g3b-closure-ledger-v1.toml")
const EVIDENCE_ROOT = joinpath(
    REPO, "design", "evidence",
    "phase-14", "g3b-closure")
const MANIFEST_PATH = joinpath(
    EVIDENCE_ROOT, "manifest-v1.toml")
const SOURCE_ROOT = "/tmp/paper/wang-source"

git(arguments...) = readchomp(Cmd(
    vcat(["git", "-C", REPO], collect(arguments))))
sha256_file(path) = bytes2hex(open(sha256, path))

function require_clean_implementation()
    isempty(git("status", "--porcelain", "--untracked-files=all")) ||
        error("G3-B attestation must start from a clean implementation commit")
    ispath(EVIDENCE_ROOT) && error(
        "G3-B evidence root already exists: $EVIDENCE_ROOT")
    contract = TOML.parsefile(CONTRACT_PATH)
    ledger = TOML.parsefile(LEDGER_PATH)
    contract["closure_protocol"]["status"] == "passed" ||
        error("G3-B contract is not closed")
    ledger["overall_status"] == "passed" ||
        error("G3-B ledger is not closed")
    ledger["contract_revision"] == contract["revision"] ||
        error("G3-B ledger targets a stale contract revision")
    return contract
end

function assertion_count(output)
    counts = Int[]
    for line in eachline(IOBuffer(output))
        match_result = match(
            r"\|\s+([0-9]+)\s+[0-9]+(?:\s+[0-9]+(?:\.[0-9]+)?(?:ms|s|m[0-9.]*s)?)?\s*$",
            line)
        match_result === nothing ||
            push!(counts, parse(Int, only(match_result.captures)))
    end
    return sum(counts; init = 0)
end

function execute_commands(contract, temporary_root)
    results = Dict{String, Any}[]
    for row in contract["closure_command"]
        id = row["id"]
        command = row["command"]
        buffer = IOBuffer()
        process = run(pipeline(
            ignorestatus(Cmd(Cmd(
                ["/bin/zsh", "-lc", command]);
                dir = REPO)),
            stdout = buffer, stderr = buffer))
        output = String(take!(buffer))
        output_path = joinpath(
            temporary_root, "command-$id.txt")
        write(output_path, output)
        if !success(process)
            print(output)
            error("closure command '$id' failed with exit code $(process.exitcode)")
        end
        assertions = assertion_count(output)
        push!(results, Dict{String, Any}(
            "id" => id,
            "command" => command,
            "status" => "passed",
            "exit_code" => process.exitcode,
            "assertion_count" => assertions,
            "validation_count" =>
                iszero(assertions) ? 1 : 0,
            "temporary_output" => output_path,
        ))
        println("attestation command PASS: ", id)
    end
    return results
end

function source_records()
    cc3d = joinpath(
        SOURCE_ROOT, "compucell3d-4.2.5")
    wang = joinpath(
        SOURCE_ROOT, "git", "s4_figures",
        "Figure3", "Radial", "Simulation")
    records = [
        (
            id = "wang-radial-xml",
            path = joinpath(
                wang, "fpp_polarity_force.xml"),
            sha256 =
                "50f2c66d58ff85532bad671d90e6a247a101444a86324cca2b486f5ff98a6ee9",
            identity =
                "Wang commit 60ebcf013aafefdff39ebe566114ee79f2a6e54d; radial XML",
            relevant =
                "11-18,27-33,50-55,66-126",
        ),
        (
            id = "wang-radial-steppables",
            path = joinpath(
                wang,
                "fpp_polarity_force_Steppables.py"),
            sha256 =
                "2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30",
            identity =
                "Wang commit 60ebcf013aafefdff39ebe566114ee79f2a6e54d; radial steppables",
            relevant =
                "36-50,79-147,180-238,241-305",
        ),
        (
            id = "cc3d-potts",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "Potts3D",
                "Potts3D.cpp"),
            sha256 =
                "f50b155ca036c469d135d2bc292b5f9cf3048b2748e032aa42a19c07fec77574",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; Potts3D.cpp",
            relevant = "metropolisFast 793-918; update 1487-1507",
        ),
        (
            id = "cc3d-boundary",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "Boundary",
                "BoundaryStrategy.cpp"),
            sha256 =
                "8e71bea1b987abfbdcabcde1cc082814d8367ed154c2341854a36c26a71573a4",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; BoundaryStrategy.cpp",
            relevant =
                "58-70,384-472,945-1039,1124-1183",
        ),
        (
            id = "cc3d-fpp",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "plugins",
                "FocalPointPlasticity",
                "FocalPointPlasticityPlugin.cpp"),
            sha256 =
                "900adcfcc6559aa1ff897b100689ef00014f9482fb955057b9fc87c7c0c4a94f",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; FocalPointPlasticityPlugin.cpp",
            relevant =
                "proposal, energy, accepted-copy, and removal symbols indexed by the accepted study",
        ),
        (
            id = "cc3d-external-potential",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "plugins",
                "ExternalPotential",
                "ExternalPotentialPlugin.cpp"),
            sha256 =
                "7e87a6d130b6195db1da33f3743167faf081c48a66edb4053e03e2a1645324ba",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; ExternalPotentialPlugin.cpp",
            relevant = "95-130,571-685",
        ),
        (
            id = "cc3d-diffusion",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "steppables",
                "PDESolvers",
                "DiffusionSolverFE.cpp"),
            sha256 =
                "f75f95843334a809af2a71f06d9486ddd839368455eded5462fd960a1537d130",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; DiffusionSolverFE.cpp",
            relevant = "80-95,136-183,255-272",
        ),
        (
            id = "cc3d-diffusion-cpu",
            path = joinpath(
                cc3d, "CompuCell3D", "core",
                "CompuCell3D", "steppables",
                "PDESolvers",
                "DiffusionSolverFE_CPU.cpp"),
            sha256 =
                "47cd9884780d9b964b432b7512006c591e0e40f54fcb0584583380d5c18de4ae",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; DiffusionSolverFE_CPU.cpp",
            relevant = "346-448,821-857,867-1275",
        ),
        (
            id = "cc3d-roadrunner",
            path = joinpath(
                cc3d, "cc3d", "core",
                "RoadRunnerPy.py"),
            sha256 =
                "57a8135f6d606ef1a1a7f3f7cb771435778a9cde560759014759cc5ccc9108bf",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; RoadRunnerPy.py",
            relevant = "9-22,30-43",
        ),
        (
            id = "cc3d-sbml-helper",
            path = joinpath(
                cc3d, "cc3d", "core",
                "SBMLSolverHelper.py"),
            sha256 =
                "f12bdba99bd7a5734f28c0abe03e57cc1c0a57b3d70df3068d14b2e6e6d81dd5",
            identity =
                "CompuCell3D 4.2.5 commit 4ca1f2919a5da53111d2027d2e00b626aba1cd28; SBMLSolverHelper.py",
            relevant = "457-517,846-862,1009-1017",
        ),
    ]
    for record in records
        isfile(record.path) || error(
            "missing pinned source input $(record.path)")
        sha256_file(record.path) == record.sha256 ||
            error("pinned source hash changed for $(record.id)")
    end
    return records
end

function environment_report(commit, tree)
    io = IOBuffer()
    println(io, "tested_commit = ", commit)
    println(io, "tested_tree = ", tree)
    println(io, "julia_version = ", VERSION)
    println(io, "kernel = ", Sys.KERNEL)
    println(io, "architecture = ", Sys.ARCH)
    versioninfo(io; verbose = true)
    println(io)
    Pkg.status(io = io; mode = Pkg.PKGMODE_MANIFEST)
    return String(take!(io))
end

function attest()
    contract = require_clean_implementation()
    tested_commit = git("rev-parse", "HEAD")
    tested_tree = git(
        "show", "-s", "--format=%T", tested_commit)
    records = source_records()
    mktempdir() do temporary_root
        command_rows =
            execute_commands(contract, temporary_root)
        isempty(git(
            "status", "--porcelain",
            "--untracked-files=all")) || error(
            "closure commands changed the tested worktree")

        mkpath(EVIDENCE_ROOT)
        artifacts = Dict{String, Any}[]
        function write_artifact(
                id, filename, kind, payload)
            path = joinpath(EVIDENCE_ROOT, filename)
            write(path, payload)
            relative = relpath(path, REPO)
            push!(artifacts, Dict{String, Any}(
                "id" => id,
                "path" => relative,
                "kind" => kind,
                "bytes" => filesize(path),
                "sha256" => sha256_file(path),
            ))
            return id
        end

        for row in command_rows
            output_id = "command-" * row["id"]
            output = read(
                row["temporary_output"], String)
            write_artifact(
                output_id,
                "command-$(row["id"]).txt",
                "command-output", output)
            row["tested_commit"] = tested_commit
            row["output_artifact_ids"] = [output_id]
            delete!(row, "temporary_output")
        end

        source_index = Dict{String, Any}(
            "schema_version" => "1.0.0",
            "wang_commit" =>
                "60ebcf013aafefdff39ebe566114ee79f2a6e54d",
            "cc3d_version" => "4.2.5",
            "cc3d_commit" =>
                "4ca1f2919a5da53111d2027d2e00b626aba1cd28",
            "wang_archive_sha256" =>
                "1aa5c426a24075091761c2fc80873b1d7582b32bc038d761e71630c867c3e984",
            "cc3d_archive_sha256" =>
                "03448f96cbba3d98eeac45dea6fc336fc0c11895607395e761b6f2c20c50d88f",
            "paper_sha256" =>
                "69fad81266dd41e1ba1e69fba3a7bed88efbac9dec2818e055cb4fd15beaa600",
            "provenance" =>
                "Wang source was retrieved from https://github.com/xing-lab-pitt/tumor-migration-model at the pinned commit; CC3D source was retrieved from the 4.2.5 source archive. No new external runtime execution is required.",
            "license_note" =>
                "This evidence records identities, hashes, and line/symbol indices rather than redistributing third-party source. Consult each upstream project for license terms.",
            "source" => [
                Dict{String, Any}(
                    "id" => record.id,
                    "identity" => record.identity,
                    "sha256" => record.sha256,
                    "relevant" => record.relevant,
                )
                for record in records
            ],
        )
        source_io = IOBuffer()
        TOML.print(source_io, source_index)
        source_id = write_artifact(
            "source-index",
            "source-index.toml",
            "source-provenance-index",
            String(take!(source_io)))

        study_files = Dict(
            "analysis-potts-fpp" =>
                "phase-14-g3b-potts-fpp-source-study.md",
            "analysis-roadrunner" =>
                "phase-14-g3b-roadrunner-source-study.md",
            "analysis-field" =>
                "phase-14-g3b-field-source-study.md",
        )
        for (id, filename) in study_files
            source = joinpath(
                REPO, "design", "audits", filename)
            write_artifact(
                id, filename, "source-study-analysis",
                read(source, String))
        end
        environment_id = write_artifact(
            "environment",
            "environment.txt",
            "environment-manifest",
            environment_report(
                tested_commit, tested_tree))

        studies = [
            Dict{String, Any}(
                "id" =>
                    "wang-cc3d-potts-fpp-source-study",
                "status" => "accepted",
                "tested_commit" => tested_commit,
                "source_identity" =>
                    "Wang 60ebcf013aafefdff39ebe566114ee79f2a6e54d and CC3D 4.2.5/4ca1f2919a5da53111d2027d2e00b626aba1cd28",
                "conclusion" =>
                    "Pinned source determines Potts boundaries, neighborhood sets, FPP topology/energy, and external-potential consumption; controlled Potts.jl fixtures qualify the implementation without a live CC3D oracle.",
                "source_artifact_ids" => [source_id],
                "analysis_artifact_ids" =>
                    ["analysis-potts-fpp"],
                "uncertainty_artifact_ids" =>
                    ["analysis-potts-fpp"],
                "fixture_artifact_ids" => [
                    "command-g3b-assembled-conformance",
                    "command-corepotts-full",
                ],
            ),
            Dict{String, Any}(
                "id" =>
                    "wang-roadrunner-coupling-study",
                "status" => "accepted",
                "tested_commit" => tested_commit,
                "source_identity" =>
                    "Wang 60ebcf013aafefdff39ebe566114ee79f2a6e54d and CC3D 4.2.5 RoadRunner wrapper source",
                "conclusion" =>
                    "The affine law, 2880-unit cadence, startup advance, and publication order are exact; solver-build bitwise equivalence is explicitly unclaimed.",
                "source_artifact_ids" => [source_id],
                "analysis_artifact_ids" =>
                    ["analysis-roadrunner"],
                "uncertainty_artifact_ids" =>
                    ["analysis-roadrunner"],
                "fixture_artifact_ids" => [
                    "command-g3b-assembled-conformance",
                    "command-corepotts-full",
                ],
            ),
            Dict{String, Any}(
                "id" =>
                    "wang-cc3d-field-source-study",
                "status" => "accepted",
                "tested_commit" => tested_commit,
                "source_identity" =>
                    "Wang 60ebcf013aafefdff39ebe566114ee79f2a6e54d and CC3D 4.2.5 DiffusionSolverFE source",
                "conclusion" =>
                    "Pinned source determines the five-substep periodic Float32 stencil and per-substep Medium overwrite; controlled fixtures qualify the normalized logical layout.",
                "source_artifact_ids" => [source_id],
                "analysis_artifact_ids" =>
                    ["analysis-field"],
                "uncertainty_artifact_ids" =>
                    ["analysis-field"],
                "fixture_artifact_ids" => [
                    "command-g3b-failure-matrix",
                    "command-corepotts-full",
                ],
            ),
        ]

        requirement_commands = Dict(
            "source-provenance-lock" =>
                ["g3b-entry-contract"],
            "canonical-wang-assembly" =>
                ["g3b-assembled-conformance"],
            "generic-api-and-composability" => [
                "g3a-generic-authoring",
                "phase13-api-inventory",
            ],
            "sequential-cpu-conformance" => [
                "g3b-assembled-conformance",
                "corepotts-full",
            ],
            "order-and-boundaries" => [
                "wang-order-oracle",
                "g3b-assembled-conformance",
            ],
            "transaction-and-failure-atomicity" => [
                "g3b-failure-matrix",
                "corepotts-full",
            ],
            "completed-mcs-restart" =>
                ["g3b-restart-matrix"],
            "steady-state-resource-contract" =>
                ["g3b-resource-matrix"],
            "portable-abi-readiness" =>
                ["g3b-portable-abi"],
            "source-semantic-study" => [
                "g3b-entry-contract",
                "corepotts-full",
            ],
            "observation-schema" =>
                ["g3b-observation-matrix"],
            "regression-and-api-freeze" => [
                "corepotts-full",
                "pottstoolkit-full",
                "phase13-api-inventory",
                "repository-structure",
                "legacy-containment",
            ],
            "evidence-reproducibility" => [
                "g3b-entry-contract",
                "repository-structure",
            ],
        )
        requirement_artifact = Dict(
            "source-provenance-lock" =>
                source_id,
            "canonical-wang-assembly" =>
                "command-g3b-assembled-conformance",
            "generic-api-and-composability" =>
                "command-g3a-generic-authoring",
            "sequential-cpu-conformance" =>
                "command-g3b-assembled-conformance",
            "order-and-boundaries" =>
                "analysis-potts-fpp",
            "transaction-and-failure-atomicity" =>
                "command-g3b-failure-matrix",
            "completed-mcs-restart" =>
                "command-g3b-restart-matrix",
            "steady-state-resource-contract" =>
                "command-g3b-resource-matrix",
            "portable-abi-readiness" =>
                "command-g3b-portable-abi",
            "source-semantic-study" =>
                "analysis-field",
            "observation-schema" =>
                "command-g3b-observation-matrix",
            "regression-and-api-freeze" =>
                "command-corepotts-full",
            "evidence-reproducibility" =>
                environment_id,
        )
        proofs = [
            Dict{String, Any}(
                "id" => "requirement:$id",
                "kind" => "requirement",
                "subject" => id,
                "status" => "passed",
                "command_ids" =>
                    requirement_commands[id],
                "artifact_ids" =>
                    [requirement_artifact[id]],
            )
            for id in keys(requirement_commands)
        ]

        required_facets =
            contract["process_proof"]["required_facets"]
        process_analysis = Dict(
            "potts_metropolis" =>
                "analysis-potts-fpp",
            "secretome_field_advance" =>
                "analysis-field",
            "centroid_sample" =>
                "analysis-potts-fpp",
            "self_polarity_from_history" =>
                "analysis-potts-fpp",
            "secretome_signal_exchange" =>
                "analysis-field",
            "intracellular_advance" =>
                "analysis-roadrunner",
            "focal_parameter_retune" =>
                "analysis-potts-fpp",
            "neighbor_polarity_alignment" =>
                "analysis-potts-fpp",
            "protrusion_force_update" =>
                "analysis-potts-fpp",
            "relationship_lifecycle_cleanup" =>
                "analysis-potts-fpp",
            "wang_observations" =>
                "command-g3b-observation-matrix",
        )
        process_proofs = [
            Dict{String, Any}(
                "id" => "process:$id",
                "process_id" => id,
                "status" => "passed",
                "facets" => required_facets,
                "command_ids" => [
                    "g3b-assembled-conformance",
                    "corepotts-full",
                ],
                "artifact_ids" =>
                    [process_analysis[id]],
            )
            for id in contract["plan"]["ordered_processes"]
        ]

        manifest = Dict{String, Any}(
            "schema_version" =>
                contract["closure_attestation"]["schema_version"],
            "claim" =>
                contract["closure_protocol"]["completion_claim"],
            "contract_revision" => contract["revision"],
            "tested_commit" => tested_commit,
            "tested_tree" => tested_tree,
            "dirty_state" => "clean",
            "environment_artifact_ids" =>
                [environment_id],
            "claim_boundaries" => Dict(
                "real_metal_qualified" => false,
                "real_rocm_qualified" => false,
                "performance_qualified" => false,
                "phase14_3_classifier_closed" => false,
                "paper_reproduction_claimed" => false,
                "cc3d_std_rand_bitwise_replay" => false,
            ),
            "artifact" => artifacts,
            "command" => command_rows,
            "study" => studies,
            "proof" => proofs,
            "process_proof" => process_proofs,
        )
        open(MANIFEST_PATH, "w") do io
            TOML.print(io, manifest)
        end
        println(
            "Phase 14 G3-B attestation generated for ",
            tested_commit)
        println("Commit only ", relpath(EVIDENCE_ROOT, REPO))
    end
end

attest()
