#!/usr/bin/env julia

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RAW_IR_CONSTRUCTOR =
    r"\b(?:StaticComposite|ProcessDeclaration|StepDeclaration|PortBinding)\s*\("

const ALLOWED_RAW_IR = Set([
    "lib/ProcessBigraphs/src/authoring/lowering.jl",
    "lib/ProcessBigraphs/src/composites.jl",
    "lib/ProcessBigraphs/src/composition.jl",
    "lib/ProcessBigraphs/src/declarations.jl",
    "lib/ProcessBigraphs/src/lowering.jl",
    "lib/ProcessBigraphs/test/phase15c/test_authoring_equivalence.jl",
    "lib/ProcessBigraphs/test/test_composite_preflight.jl",
    "lib/ProcessBigraphs/test/test_high_level_authoring.jl",
    "lib/ProcessBigraphs/test/test_phase15a_algebraic_structure.jl",
    "lib/ProcessBigraphs/test/test_phase15b_open_composition.jl",
    "benchmark/phase16hc_authoring_qualification.jl",
])

function julia_files(relative_root)
    root = joinpath(ROOT, relative_root)
    isdir(root) || return String[]
    sort!([
        relpath(joinpath(directory, file), ROOT)
        for (directory, _, files) in walkdir(root)
        for file in files
        if endswith(file, ".jl")
    ])
end

files = unique(vcat(
    julia_files("lib/ProcessBigraphs/src"),
    julia_files("lib/ProcessBigraphs/test"),
    julia_files("lib/CorePotts/src"),
    julia_files("lib/CorePotts/test"),
    julia_files("src"),
    julia_files("test"),
    julia_files("integration"),
    julia_files("benchmark"),
))

violations = String[]
for relative in files
    relative in ALLOWED_RAW_IR && continue
    for (line_number, line) in enumerate(eachline(joinpath(ROOT, relative)))
        occursin(RAW_IR_CONSTRUCTOR, line) || continue
        push!(violations, "$(relative):$(line_number): $(strip(line))")
    end
end

if isempty(violations)
    println(
        "ProcessBigraphs Phase 16.HC raw-IR guard passed: ordinary library and test models use high-level composition.",
    )
else
    foreach(value -> println(stderr, "ERROR: ", value), violations)
    error(
        "raw ProcessBigraph IR construction is allowed only in lowering internals and explicit IR conformance tests",
    )
end
