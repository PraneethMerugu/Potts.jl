using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PACKAGE_ROOT = joinpath(ROOT, "lib", "MakiePotts")
const PROJECT_PATH = joinpath(PACKAGE_ROOT, "Project.toml")
const ACCEPTANCE_PATH = joinpath(
    ROOT, "design", "makiepotts", "acceptance-matrix.toml")
const REFERENCE_PATH = joinpath(
    PACKAGE_ROOT, "test", "reference", "makiepotts-v02.png")
const BACKEND_MANIFEST_PATH = joinpath(
    PACKAGE_ROOT, "test", "backends", "Manifest.toml")
const AUDIT_B_RECORD_PATH = joinpath(
    ROOT, "design", "makiepotts", "visual-audit-b.md")

project = TOML.parsefile(PROJECT_PATH)
project["name"] == "MakiePotts" || error("unexpected MakiePotts package name")
project["uuid"] == "95794c00-c762-4965-bf31-de18bcca2bc9" ||
    error("unexpected MakiePotts UUID")
project["version"] == "0.2.0" || error("MakiePotts release target must be 0.2.0")
!isempty(get(project, "authors", String[])) ||
    error("MakiePotts authorship metadata is missing")

dependencies = project["deps"]
haskey(dependencies, "Makie") || error("Makie must be a direct dependency")
for backend in ("CairoMakie", "GLMakie", "WGLMakie")
    haskey(dependencies, backend) &&
        error("$backend must remain caller-selected, not a MakiePotts dependency")
end

compatibility = project["compat"]
compatibility["Makie"] == "0.24" ||
    error("MakiePotts v0.2 must remain qualified against Makie 0.24")
compatibility["julia"] == "1.12.6" ||
    error("MakiePotts must declare its qualified Julia target")

for required in (
        joinpath(ROOT, "LICENSE"),
        joinpath(PACKAGE_ROOT, "README.md"),
        joinpath(ROOT, "docs", "src", "makiepotts.md"),
        joinpath(ROOT, "examples", "makiepotts_native.jl"),
        joinpath(ROOT, "design", "makiepotts", "public-api-v0.2.toml"),
        joinpath(ROOT, "design", "makiepotts",
            "hardening-through-visual-audit-b.md"),
        joinpath(ROOT, "design", "makiepotts", "visual-audit-a.md"),
        AUDIT_B_RECORD_PATH,
        joinpath(PACKAGE_ROOT, "benchmark", "Project.toml"),
        joinpath(PACKAGE_ROOT, "benchmark", "README.md"),
        joinpath(PACKAGE_ROOT, "benchmark", "benchmarks.jl"),
        joinpath(PACKAGE_ROOT, "test", "clean_install_smoke.jl"),
        joinpath(PACKAGE_ROOT, "test", "visual_regression.jl"),
        joinpath(PACKAGE_ROOT, "test", "visual_audit_b.jl"),
        REFERENCE_PATH,
        BACKEND_MANIFEST_PATH,
    )
    isfile(required) || error("required MakiePotts release artifact is missing: $required")
end

isfile(joinpath(PACKAGE_ROOT, "benchmark", "Manifest.toml")) &&
    error("the portable MakiePotts benchmark must not commit a local Manifest.toml")

acceptance = TOML.parsefile(ACCEPTANCE_PATH)
expected_reference = acceptance["hardening"]["visual_reference_sha256"]
actual_reference = bytes2hex(open(sha256, REFERENCE_PATH))
actual_reference == expected_reference ||
    error("the accepted MakiePotts visual reference digest changed")

expected_audit_b = acceptance["hardening"]["visual_audit_b_sha256"]
audit_b_record = read(AUDIT_B_RECORD_PATH, String)
occursin(expected_audit_b, audit_b_record) ||
    error("Visual Audit B evidence does not contain its accepted digest")
acceptance["hardening"]["visual_audit_b"] == "accepted" ||
    error("Visual Audit B has not been accepted")

backend_manifest = TOML.parsefile(BACKEND_MANIFEST_PATH)
for (backend, expected) in (
        "CairoMakie" => "0.15.13",
        "GLMakie" => "0.13.13",
        "WGLMakie" => "0.13.13",
        "Makie" => "0.24.13",
    )
    entries = backend_manifest["deps"][backend]
    entry = entries isa AbstractVector ? only(entries) : entries
    entry["version"] == expected ||
        error("$backend backend qualification drifted from $expected")
end

reference = normpath(REFERENCE_PATH)
generated_extensions = Set((".gif", ".mp4", ".webm", ".html", ".png"))
for (directory, _, files) in walkdir(PACKAGE_ROOT)
    for file in files
        path = normpath(joinpath(directory, file))
        lowercase(splitext(path)[2]) in generated_extensions || continue
        path == reference || error(
            "generated render artifact must not live in package source: $path")
    end
end

println("MakiePotts v0.2 release metadata, manifests, and artifact hygiene passed")
