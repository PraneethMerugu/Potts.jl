using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FREEZE_FILE = joinpath(ROOT, "design", "audits", "phase-7-legacy-freeze.toml")

const DELETED_TOOLKIT_PATHS = (
    "src/models.jl",
    "src/domains.jl",
    "src/problems.jl",
    "src/models/test_problems.jl",
    "src/rules/events.jl",
    "src/rules/macros.jl",
    "ext/PottsToolkitMermaidExt.jl",
)

const REMOVED_TOOLKIT_DEPENDENCIES =
    ("Adapt", "MLStyle", "Random", "Reexport")

const FORBIDDEN_PATTERNS = [
    r"HST[A-Za-z_]*Penalty",
    r"\bVolumePenalty\b",
    r"\bAdhesionPenalty\b",
    r"\bChemotaxisPenalty\b",
    r"\bFocalPointSpringPenalty\b",
    r"\bAbstractPenalty\b",
    r"\bAbstractSampler\b",
    r"\bMetropolisSampler\b",
    r"\bMetropolisAlgorithm\b",
    r"\bVolumeTracker\b",
    r"\bSurfaceAreaTracker\b",
    r"\bevaluate_penalty\b",
    r"\bexecute_step!",
    r"\bupdate_sweep_auxiliary!",
    r"\bPottsState\b",
    r"\bPottsParameters\b",
    r"\bPottsCache\b",
    r"\bParallelMetropolis\b",
    r"\bCheckerboardMetropolis\b",
    r"\bIntrinsicCheckerboardMetropolis\b",
    r"\bSequentialMetropolis\b",
    r"\bactive_fraction\b",
    r"\bsweeps_per_step\b",
    r"\bLegacyPottsProblem\b",
    r"\bLegacyPottsIntegrator\b",
    r"\bLegacyPottsSolution\b",
]

function require(condition, message)
    condition || error(message)
end

function relative_julia_sources(root)
    sources = String[]
    for search_root in ["src", "lib", "benchmark/src", "test", "integration", "docs", "examples"]
        absolute = joinpath(root, search_root)
        isdir(absolute) || continue
        for (directory, directories, files) in walkdir(absolute)
            filter!(name -> name != "build" && name != "results", directories)
            for file in files
                endswith(file, ".jl") || continue
                push!(sources, relpath(joinpath(directory, file), root))
            end
        end
    end
    return sort!(unique!(sources))
end

function protected_scientific_source(path)
    startswith(path, "lib/CorePotts/src/algorithms/") && return true
    startswith(path, "lib/CorePotts/src/components/scientific_") && return true
    path == "lib/CorePotts/src/sciml/interface.jl" && return true
    return path in (
        "lib/CorePotts/src/execution/contracts.jl",
        "lib/CorePotts/src/initialization/logical.jl",
        "lib/CorePotts/src/protocols/scientific.jl",
        "lib/CorePotts/src/reference/engine.jl",
        "lib/CorePotts/src/rng/semantic.jl",
        "lib/CorePotts/src/spatial/cartesian.jl",
        "lib/CorePotts/src/state/logical.jl",
        "lib/CorePotts/src/state/semantics.jl",
    )
end

function production_source(path)
    startswith(path, "src/") && return true
    startswith(path, "benchmark/src/") && return true
    return startswith(path, "lib/") &&
           (occursin("/src/", path) || occursin("/ext/", path))
end

function forbidden_matches(text)
    return [string(pattern) for pattern in FORBIDDEN_PATTERNS if occursin(pattern, text)]
end

function quarantined_signature(path)
    matching_lines = [line for line in eachline(path)
                      if !isempty(forbidden_matches(line))]
    return bytes2hex(sha256(codeunits(join(matching_lines, "\n") * "\n")))
end

require(isfile(FREEZE_FILE), "missing legacy freeze manifest")

for path in DELETED_TOOLKIT_PATHS
    require(!isfile(joinpath(ROOT, path)),
        "deleted PottsToolkit legacy path `$path` was reintroduced")
end

root_project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
root_dependencies = get(root_project, "deps", Dict{String, Any}())
for dependency in REMOVED_TOOLKIT_DEPENDENCIES
    require(!haskey(root_dependencies, dependency),
        "removed PottsToolkit legacy dependency `$dependency` was reintroduced")
end

freeze = TOML.parsefile(FREEZE_FILE)
require(get(freeze, "version", nothing) == 2,
    "legacy closure requires the closed version-2 manifest")
require(get(freeze, "status", nothing) == "closed",
    "legacy manifest is not closed")
frozen_files = get(freeze, "files", Dict{String, Any}())
frozen_signatures = get(freeze, "signatures", Dict{String, Any}())
consumer_signatures = get(freeze, "consumer_signatures", Dict{String, Any}())
require(isempty(frozen_files),
    "closed legacy manifest must not retain historical implementation files")
require(isempty(frozen_signatures),
    "closed legacy manifest must not retain mixed production signatures")
require(isempty(consumer_signatures),
    "closed legacy manifest must not retain executable consumer signatures")

for (path, expected_digest) in sort!(collect(frozen_files); by = first)
    absolute = joinpath(ROOT, path)
    require(isfile(absolute),
        "frozen legacy file `$path` disappeared; remove it from the manifest in the owning migration")
    actual_digest = bytes2hex(sha256(read(absolute)))
    require(actual_digest == expected_digest,
        "frozen legacy file `$path` changed; historical code is read-only")
end

for (path, expected_digest) in sort!(collect(frozen_signatures); by = first)
    absolute = joinpath(ROOT, path)
    require(isfile(absolute), "mixed legacy consumer `$path` disappeared without manifest cleanup")
    actual_digest = quarantined_signature(absolute)
    require(actual_digest == expected_digest,
        "quarantined lines in mixed source `$path` changed; update only through an explicit audit")
end


for (path, expected_digest) in sort!(collect(consumer_signatures); by = first)
    absolute = joinpath(ROOT, path)
    require(isfile(absolute),
        "legacy test/tutorial consumer `$path` disappeared without manifest cleanup")
    actual_digest = quarantined_signature(absolute)
    require(actual_digest == expected_digest,
        "quarantined lines in consumer `$path` changed; update only through an explicit migration audit")
end

all_sources = relative_julia_sources(ROOT)
production_inventory = union(Set(keys(frozen_files)), Set(keys(frozen_signatures)))
for path in all_sources
    matches = forbidden_matches(read(joinpath(ROOT, path), String))
    if production_source(path)
        require(isempty(matches) || path in production_inventory,
            "production legacy consumer `$path` is absent from the frozen inventory: " *
            join(matches, ", "))
    elseif path != "scripts/check_legacy_containment.jl"
        require(isempty(matches) || haskey(consumer_signatures, path),
            "test/tutorial legacy consumer `$path` is absent from the frozen inventory: " *
            join(matches, ", "))
    end
    protected_scientific_source(path) || continue
    require(isempty(matches),
        "scientific source `$path` references quarantined vocabulary: $(join(matches, ", "))")
end

println("Legacy closure passes: the historical engine, Toolkit compiler, " *
        "mixed production paths, and executable legacy consumers are absent")
