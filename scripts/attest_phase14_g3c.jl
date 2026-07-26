#!/usr/bin/env julia

using Dates
using SHA
using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const AUDITS = joinpath(REPO, "design", "audits")
const LEDGER_PATH = joinpath(
    AUDITS, "phase-14-g3c-closure-ledger-v1.toml")
const EVIDENCE_PARENT = joinpath(
    REPO, "design", "evidence", "phase-14")
const EVIDENCE_ROOT = joinpath(
    EVIDENCE_PARENT, "g3c-closure")
const CHECKER = joinpath(
    REPO, "scripts", "check_phase14_g3c_closure.jl")

function option(name)
    prefix = "--$name="
    index = findfirst(argument ->
        startswith(argument, prefix), ARGS)
    index === nothing &&
        error("missing required option --$name=PATH")
    return abspath(
        ARGS[index][(length(prefix) + 1):end])
end

metal = option("metal")
amdgpu = option("amdgpu")
metal_code = option("metal-device-code")
amdgpu_code = option("amdgpu-device-code")

ispath(EVIDENCE_ROOT) && error(
    "G3-C evidence root already exists; refusing to overwrite $EVIDENCE_ROOT")
dirty = readchomp(
    `git -C $REPO status --porcelain --untracked-files=all`)
isempty(dirty) || error(
    "G3-C attestation must start from the clean implementation commit")

validation = Cmd([
    Base.julia_cmd().exec...,
    "--project=$REPO",
    "--startup-file=no",
    CHECKER,
    "--evidence-only",
    "--metal=$metal",
    "--amdgpu=$amdgpu",
    "--metal-device-code=$metal_code",
    "--amdgpu-device-code=$amdgpu_code",
])
run(validation)

metal_result = TOML.parsefile(metal)
amdgpu_result = TOML.parsefile(amdgpu)
head = readchomp(`git -C $REPO rev-parse HEAD`)
tree = readchomp(`git -C $REPO show -s --format=%T HEAD`)
for (backend, result) in (
        "metal" => metal_result,
        "amdgpu" => amdgpu_result)
    provenance = result["provenance"]
    provenance["git_commit"] == head || error(
        "$backend hardware evidence does not target the clean implementation HEAD")
    provenance["implementation_commit"] == head || error(
        "$backend implementation_commit does not equal the attested HEAD")
end

function copy_device_code(source, destination)
    if isfile(source)
        mkpath(destination)
        cp(source, joinpath(destination, basename(source)))
        return
    end
    isdir(source) || error(
        "device-code source does not exist: $source")
    for (root, directories, files) in walkdir(source)
        any(name -> islink(joinpath(root, name)),
            (directories..., files...)) &&
            error("device-code source contains a symlink: $root")
        relative = relpath(root, source)
        target = relative == "." ?
            destination : joinpath(destination, relative)
        mkpath(target)
        for file in files
            cp(joinpath(root, file), joinpath(target, file))
        end
    end
end

mkpath(EVIDENCE_PARENT)
staging = mktempdir(EVIDENCE_PARENT;
    prefix = ".g3c-attestation-")
success = false
try
    cp(metal, joinpath(staging, "metal-paper.toml"))
    cp(amdgpu, joinpath(staging, "amdgpu-paper.toml"))
    copy_device_code(
        metal_code,
        joinpath(staging, "metal-device-code"))
    copy_device_code(
        amdgpu_code,
        joinpath(staging, "amdgpu-device-code"))

    artifacts = Any[]
    for (root, _, files) in walkdir(staging)
        for file in sort(files)
            path = joinpath(root, file)
            relative_inside = relpath(path, staging)
            relative = joinpath(
                "design", "evidence", "phase-14",
                "g3c-closure", relative_inside)
            kind = endswith(file, ".toml") ?
                "backend-paper-result" : "device-code"
            push!(artifacts, Dict(
                "id" => replace(relative_inside, '/' => ':'),
                "path" => relative,
                "kind" => kind,
                "bytes" => filesize(path),
                "sha256" =>
                    bytes2hex(open(sha256, path)),
            ))
        end
    end
    sort!(artifacts; by = row -> row["id"])
    manifest = Dict(
        "schema_version" => "1.0.0",
        "claim" => "G3-C complete",
        "generated_at_utc" => string(now(UTC)),
        "implementation_commit" => head,
        "implementation_tree" => tree,
        "contract_revision" => 7,
        "suite" =>
            "phase14-wang-g3c-gpu-native-qualification-v1",
        "metal_result" =>
            "design/evidence/phase-14/g3c-closure/metal-paper.toml",
        "amdgpu_result" =>
            "design/evidence/phase-14/g3c-closure/amdgpu-paper.toml",
        "metal_device_code" =>
            "design/evidence/phase-14/g3c-closure/metal-device-code",
        "amdgpu_device_code" =>
            "design/evidence/phase-14/g3c-closure/amdgpu-device-code",
        "artifact" => artifacts,
    )
    open(joinpath(staging, "manifest-v1.toml"), "w") do io
        TOML.print(io, manifest; sorted = true)
    end

    ledger = TOML.parsefile(LEDGER_PATH)
    ledger["overall_status"] = "passed"
    ledger["manifest"] =
        "design/evidence/phase-14/g3c-closure/manifest-v1.toml"
    ledger["attested_implementation_commit"] = head
    ledger["attested_implementation_tree"] = tree
    ledger["attested_at"] = string(now(UTC))
    for row in ledger["requirement"]
        row["status"] = "passed"
        row["remaining"] = String[]
    end
    for row in ledger["process"]
        row["metal"] = "passed"
        row["amdgpu"] = "passed"
    end
    boundaries = ledger["claim_boundaries"]
    boundaries["metal_qualified"] = true
    boundaries["rocm_qualified"] = true
    boundaries["g3c_complete"] = true
    boundaries["g4_open"] = true
    boundaries["g3b_semantics_changed"] = false

    ledger_staging, io = mktemp(AUDITS)
    try
        TOML.print(io, ledger; sorted = true)
        close(io)
        mv(staging, EVIDENCE_ROOT)
        mv(ledger_staging, LEDGER_PATH; force = true)
        success = true
    finally
        isopen(io) && close(io)
        isfile(ledger_staging) &&
            rm(ledger_staging; force = true)
    end
finally
    !success && isdir(staging) &&
        rm(staging; recursive = true, force = true)
end

println("Phase 14 G3-C attestation staged successfully")
println("  implementation_commit=", head)
println("  implementation_tree=", tree)
println("  evidence_root=", EVIDENCE_ROOT)
println("Commit the ledger/evidence-only attestation, then run from the clean checkout:")
println(
    "julia --project=. --startup-file=no scripts/check_phase14_g3c_closure.jl ",
    "--metal=design/evidence/phase-14/g3c-closure/metal-paper.toml ",
    "--amdgpu=design/evidence/phase-14/g3c-closure/amdgpu-paper.toml ",
    "--metal-device-code=design/evidence/phase-14/g3c-closure/metal-device-code ",
    "--amdgpu-device-code=design/evidence/phase-14/g3c-closure/amdgpu-device-code")
