#!/usr/bin/env julia

using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function load(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing required file: $relative")
    return isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
end

api = load("spec/process-bigraph-phase17-api-v1.toml")
entry = load("spec/process-bigraph-phase17-entry-v1.toml")
required_roots = String.(api["scanner"]["required_roots"])

forbidden = [
    r"\bManagedFieldAdvanceProcess\b",
    r"\binit_coupled\b",
    r"\bCoupledIntegrator\b",
    r"\bCoupledState\b",
    r"\bMCSPlan\b",
    r"\.children\b",
    r"\b(?:integrator|coupled|scientific|potts)\.mcs\b",
    r"\b(?:integrator|coupled|scientific|potts)\.algorithm\b",
]

status = get(entry, "implementation_status", "")
scan_active = status in (
    "17.C-model-migration",
    "17.D-independent-manual",
    "17.E-scientific-case-studies",
    "17.F-reconciliation-and-attestation",
    "complete",
)
violations = String[]
if scan_active
    for relative in required_roots
        check(ispath(joinpath(ROOT, relative)),
            "required internal-use scanner root is absent: $relative")
    end
    for relative in ("src/reference_models", "lib/ProcessBigraphs/docs")
        root = joinpath(ROOT, relative)
        isdir(root) || continue
        for (directory, _, files) in walkdir(root)
            for file in files
                any(suffix -> endswith(file, suffix), (".jl", ".md")) ||
                    continue
                path = joinpath(directory, file)
                for (line_number, line) in enumerate(eachline(path))
                    for pattern in forbidden
                        occursin(pattern, line) || continue
                        push!(violations,
                            "$(relpath(path, ROOT)):$line_number: $(pattern.pattern)")
                    end
                end
            end
        end
    end
end
append!(failures, violations)

if isempty(failures)
    println("ProcessBigraphs Phase 17 internal-use boundary passed:")
    println("  registered scanner roots: $(length(required_roots))")
    println("  canonical source scan enforced: $scan_active")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 internal-use check failed with $(length(failures)) error(s)")
end
