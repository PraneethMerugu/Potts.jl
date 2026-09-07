using Aqua
using ExplicitImports

@testset "package quality" begin
    Aqua.test_all(Potts; ambiguities = false, persistent_tasks = false)
    ExplicitImports.test_explicit_imports(Potts)

    ambiguities = Test.detect_ambiguities(Potts, Base; recursive = true)
    owned = filter(ambiguities) do pair
        any(method -> method.module === Potts, pair)
    end
    @test isempty(owned)

    project = TOML.parsefile(joinpath(pkgdir(Potts), "Project.toml"))
    dependencies = Set(keys(get(project, "deps", Dict())))
    weak_dependencies = Set(keys(get(project, "weakdeps", Dict())))

    # Optional integrations remain extensions rather than hard requirements.
    @test isempty(
        intersect(
            dependencies,
            Set(
                (
                    "DiffEqGPU", "Metal", "MethodOfLines", "ModelingToolkit",
                    "StaticArrays", "Unitful",
                )
            ),
        )
    )
    @test Set(
        (
            "DiffEqGPU", "Metal", "MethodOfLines", "ModelingToolkit",
            "StaticArrays", "Unitful",
        )
    ) ⊆ weak_dependencies

    repository = pkgdir(Potts)
    # Ordinary package, docs, examples, and integration environments resolve
    # from Project.toml. Only exact scientific replay and backend
    # qualification intentionally commit manifests.
    live_manifests = (
        joinpath(repository, "integration", "replay", "Manifest.toml"),
        joinpath(repository, "benchmark", "backends", "metal", "Manifest.toml"),
    )
    @test all(isfile, live_manifests)

    @testset "exact environments pin standalone upstream repositories" begin
        exact_manifests = (
            joinpath(repository, "integration", "replay", "Manifest.toml") =>
                "1.12.6",
            joinpath(repository, "benchmark", "backends", "metal", "Manifest.toml") =>
                "1.12.6",
        )
        upstream_urls = Dict(
            "CorePotts" => "https://github.com/PraneethMerugu/CorePotts.jl",
            "LocalMath" => "https://github.com/PraneethMerugu/LocalMath.jl",
            "Potts" => "https://github.com/PraneethMerugu/Potts.jl",
        )
        full_revision = r"^[0-9a-f]{40}$"
        for (manifest_path, julia_version) in exact_manifests
            manifest = TOML.parsefile(manifest_path)
            @test manifest["julia_version"] == julia_version
            dependencies = manifest["deps"]
            for (name, url) in upstream_urls
                entries = dependencies[name]
                entry = entries isa AbstractVector ? only(entries) : entries
                @test !haskey(entry, "path")
                @test entry["repo-url"] == url
                @test match(full_revision, entry["repo-rev"]) !== nothing
                @test match(full_revision, entry["git-tree-sha1"]) !== nothing
            end

            path_dependencies = String[]
            for (name, records) in dependencies
                for entry in (records isa AbstractVector ? records : (records,))
                    haskey(entry, "path") && push!(path_dependencies, name)
                end
            end
            @test isempty(path_dependencies)
        end
    end
end
