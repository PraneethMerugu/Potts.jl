#!/usr/bin/env julia

using SHA
using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end

function tracked_files(root::AbstractString)
    output = read(Cmd(`git ls-files -z`; dir=root), String)
    return filter(!isempty, split(output, '\0'))
end

function qualifying_digest(root::AbstractString)
    entry = TOML.parsefile(joinpath(root, "spec/process-bigraph-phase17-entry-v1.toml"))
    prefixes = String.(entry["closure"]["qualifying_path_prefixes"])
    exclusions = String.(entry["closure"]["evidence_only_prefixes"])
    qualifies(path) =
        any(prefix -> path == prefix || startswith(path, prefix), prefixes) &&
        !any(prefix -> path == prefix || startswith(path, prefix), exclusions)

    context = SHA.SHA256_CTX()
    selected = sort!(filter(qualifies, tracked_files(root)))
    for relative in selected
        bytes = read(joinpath(root, relative))
        update!(context, codeunits(relative))
        update!(context, UInt8[0])
        update!(context, codeunits(string(length(bytes))))
        update!(context, UInt8[0])
        update!(context, bytes)
        update!(context, UInt8[0])
    end
    return bytes2hex(digest!(context)), length(selected)
end

digest, count = qualifying_digest(ROOT)
if "--print" in ARGS
    println(digest)
    exit()
end

evidence_path = joinpath(
    ROOT, "design/evidence/phase-17/phase17-qualification-v1.toml")
entry = TOML.parsefile(joinpath(ROOT, "spec/process-bigraph-phase17-entry-v1.toml"))
if !isfile(evidence_path)
    get(entry, "implementation_status", "") == "complete" &&
        error("missing Phase 17 qualification report: " *
              "design/evidence/phase-17/phase17-qualification-v1.toml")
    println("ProcessBigraphs qualifying-content digest computed (attestation pending):")
    println("  qualifying files: $count")
    println("  sha256: $digest")
    exit()
end

evidence = TOML.parsefile(evidence_path)
expected = get(evidence, "qualifying_content_sha256", "")
expected == digest || error(
    "qualifying content digest mismatch: expected $expected, computed $digest")
println("ProcessBigraphs qualifying-content digest passed:")
println("  qualifying files: $count")
println("  sha256: $digest")
