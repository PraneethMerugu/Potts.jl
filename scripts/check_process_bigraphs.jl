using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PACKAGE = joinpath(ROOT, "lib", "ProcessBigraphs")
const REGISTRY_PATH = joinpath(PACKAGE, "parity-registry.toml")
const PROJECT_PATH = joinpath(PACKAGE, "Project.toml")
const MODULE_PATH = joinpath(PACKAGE, "src", "ProcessBigraphs.jl")

failures = String[]
check(condition, message) = condition || push!(failures, message)

registry = TOML.parsefile(REGISTRY_PATH)
project = TOML.parsefile(PROJECT_PATH)

check(registry["schema_version"] == "2.0.0",
    "current capability registry must use schema 2.0.0")
check(registry["registry_id"] == "process-bigraphs-current-capabilities-v1",
    "current capability registry has an unexpected identity")
check(registry["maturity"] == "internal_beta" && !registry["public_release"],
    "ProcessBigraphs must remain an unpublished internal beta")

for dependency in ("CorePotts", "PottsToolkit", "Metal", "AMDGPU", "CUDA", "SciMLBase")
    check(!haskey(project["deps"], dependency),
        "forbidden ProcessBigraphs direct dependency: $dependency")
end
check(Set(keys(project["weakdeps"])) == Set(("CommonSolve", "SciMLBase")),
    "ProcessBigraphs weak dependency boundary changed")
check(project["extensions"]["ProcessBigraphsSciMLExt"] ==
      ["CommonSolve", "SciMLBase"],
    "SciML extension trigger set changed")

for feature in registry["features"]
    path = normpath(joinpath(PACKAGE, feature["test"]))
    check(isfile(path), "feature $(feature["id"]) has no current test: $(feature["test"])")
end

module_text = read(MODULE_PATH, String)
includes = [match.captures[1] for match in
            eachmatch(r"""include\("([^"]+)"\)""", module_text)]
check(length(includes) == length(unique(includes)),
    "ProcessBigraphs entry module includes a file more than once")
for include_path in includes
    check(isfile(joinpath(PACKAGE, "src", include_path)),
        "entry module includes a missing file: $include_path")
end
check(last(includes) == "compatibility.jl",
    "compatibility aliases must be loaded after canonical implementations")

for model in (
    joinpath(ROOT, "lib", "CorePotts", "src", "coupled", "merks2006.jl"),
    joinpath(ROOT, "lib", "CorePotts", "src", "coupled", "shirinifard2012.jl"),
)
    text = read(model, String)
    for raw_name in ("StaticComposite", "ProcessDeclaration", "PortBinding",
                     "compile_composite")
        check(!occursin(raw_name, text),
            "$(relpath(model, ROOT)) bypasses authoring with $raw_name")
    end
    check(occursin("compose(", text),
        "$(relpath(model, ROOT)) must use the high-level compose API")
end

quality_entrypoints = filter(readdir(joinpath(ROOT, "scripts"); join=true)) do path
    isfile(path) && endswith(path, ".jl") &&
        occursin("process_bigraph", replace(basename(path), '-' => '_'))
end
check(length(quality_entrypoints) <= 6,
    "more than six active ProcessBigraph quality entrypoints remain")

if isempty(failures)
    println("Current ProcessBigraphs architecture and capability check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs current-state check failed with $(length(failures)) error(s)")
end
