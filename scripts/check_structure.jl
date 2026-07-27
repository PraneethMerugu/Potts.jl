using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_TARGET = "1.12.6"
const STDLIBS = Set(["LinearAlgebra", "Random", "Serialization", "SHA", "Statistics", "Test"])
const INDEPENDENT_PROJECTS = [
    joinpath(ROOT, "Project.toml"),
    joinpath(ROOT, "lib", "CorePotts", "Project.toml"),
    joinpath(ROOT, "lib", "MakiePotts", "Project.toml"),
    joinpath(ROOT, "lib", "ProcessBigraphs", "Project.toml"),
]

function require(condition, message)
    condition || error(message)
end

function project_files()
    projects = String[]
    for (root, dirs, files) in walkdir(ROOT)
        filter!(dir -> dir != ".git" && dir != "build" && dir != "results", dirs)
        "Project.toml" in files && push!(projects, joinpath(root, "Project.toml"))
    end
    return sort(projects)
end

for project_file in project_files()
    project = TOML.parsefile(project_file)
    compat = get(project, "compat", Dict{String, Any}())
    require(get(compat, "julia", nothing) == JULIA_TARGET,
        "$(relpath(project_file, ROOT)) must target Julia $JULIA_TARGET exactly")
end

for project_file in INDEPENDENT_PROJECTS
    project = TOML.parsefile(project_file)
    deps = get(project, "deps", Dict{String, Any}())
    compat = get(project, "compat", Dict{String, Any}())
    require(!haskey(deps, "Test"), "Test must not be a runtime dependency of $(project["name"])")
    for dependency in keys(deps)
        dependency in STDLIBS && continue
        require(haskey(compat, dependency),
            "$(project["name"]) lacks a compat bound for $dependency")
    end
end

root_project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
require(root_project["name"] == "PottsToolkit", "the repository-root package must be PottsToolkit")
require(root_project["uuid"] == "e4c62a4c-8889-4cc8-ad3a-75efc86c53b9",
    "the PottsToolkit UUID changed")
require(isfile(joinpath(ROOT, "src", "PottsToolkit.jl")), "src/PottsToolkit.jl is missing")
require(!ispath(joinpath(ROOT, "src", "Potts.jl")), "the Potts umbrella source still exists")
nested_toolkit = joinpath(ROOT, "lib", "PottsToolkit")
nested_files = isdir(nested_toolkit) ?
               collect(Iterators.flatten(files for (_, _, files) in walkdir(nested_toolkit))) :
               String[]
require(isempty(nested_files), "the nested PottsToolkit package still contains files")

family_deps = Dict(
    "CorePotts" => Set(keys(get(TOML.parsefile(INDEPENDENT_PROJECTS[2]), "deps", Dict()))),
    "MakiePotts" => Set(keys(get(TOML.parsefile(INDEPENDENT_PROJECTS[3]), "deps", Dict()))),
    "ProcessBigraphs" =>
        Set(keys(get(TOML.parsefile(INDEPENDENT_PROJECTS[4]), "deps", Dict()))),
    "PottsToolkit" => Set(keys(get(root_project, "deps", Dict()))),
)
require(family_deps["ProcessBigraphs"] == Set(["ACSets", "Catlab", "SHA"]),
    "ProcessBigraphs Phase 15.A must depend directly on ACSets, Catlab, and SHA")
require(isempty(intersect(family_deps["CorePotts"], Set(["PottsToolkit", "MakiePotts", "NeuralPotts"]))),
    "CorePotts depends on an upward layer")
require(isempty(intersect(family_deps["ProcessBigraphs"],
    Set(["CorePotts", "PottsToolkit", "MakiePotts", "NeuralPotts"]))),
    "ProcessBigraphs depends on a Potts domain layer")
require(isempty(intersect(family_deps["PottsToolkit"], Set(["MakiePotts", "NeuralPotts"]))),
    "PottsToolkit depends on a satellite")
require(isempty(intersect(family_deps["MakiePotts"], Set(["NeuralPotts"]))),
    "MakiePotts depends on a deferred satellite")
workspace_projects = get(get(root_project, "workspace", Dict{String, Any}()),
    "projects", String[])
require(workspace_projects ==
        ["integration", "lib/CorePotts", "lib/MakiePotts", "lib/ProcessBigraphs"],
    "workspace must contain integration, the paper-core engine, MakiePotts, and independent " *
    "ProcessBigraphs")
neural_root = joinpath(ROOT, "lib", "NeuralPotts")
neural_files = isdir(neural_root) ?
               collect(Iterators.flatten(files for (_, _, files) in walkdir(neural_root))) :
               String[]
require(isempty(neural_files),
    "the pre-freeze NeuralPotts implementation must remain absent until its deferred redesign")

for runner in [
        joinpath(ROOT, "test", "runtests.jl"),
        joinpath(ROOT, "lib", "CorePotts", "test", "runtests.jl"),
        joinpath(ROOT, "lib", "MakiePotts", "test", "runtests.jl"),
        joinpath(ROOT, "lib", "ProcessBigraphs", "test", "runtests.jl"),
        joinpath(ROOT, "integration", "runtests.jl")]
    require(isfile(runner), "missing test owner: $(relpath(runner, ROOT))")
end

for manifest in [
        "Manifest.toml",
        "lib/CorePotts/Manifest.toml",
        "lib/ProcessBigraphs/Manifest.toml",
        "lib/MakiePotts/Manifest.toml",
        "lib/NeuralPotts/Manifest.toml"]
    tracked = readchomp(`git -C $ROOT ls-files -- $manifest`)
    require(isempty(tracked), "$manifest must not be tracked by an independently installable library")
end

for generated in ["docs/build", "benchmark/results"]
    tracked = readchomp(`git -C $ROOT ls-files -- $generated`)
    require(isempty(tracked), "$generated contains tracked generated output")
end

println("Repository structure satisfies the paper-core, MakiePotts, and ProcessBigraphs " *
        "package, dependency, test, manifest, workspace, and Julia-target contract")
