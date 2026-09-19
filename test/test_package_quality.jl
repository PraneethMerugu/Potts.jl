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
                    "Unitful",
                )
            ),
        )
    )
    @test Set(
        (
            "DiffEqGPU", "Metal", "MethodOfLines", "ModelingToolkit",
            "Unitful",
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
        exact_profiles = (
            (
                manifest = joinpath(repository, "integration", "replay", "Manifest.toml"),
                julia = "1.12.6",
                revision = :replay_revision,
            ),
            (
                manifest = joinpath(
                    repository,
                    "benchmark",
                    "backends",
                    "metal",
                    "Manifest.toml",
                ),
                julia = "1.12.6",
                revision = :metal_revision,
            ),
        )
        upstream_sources = Dict(
            "CorePotts" => (
                url = "https://github.com/PraneethMerugu/CorePotts.jl",
                replay_revision = "3bab07f1a04fd3d1c96e555aa0d2a4da6c347fb4",
                metal_revision = "1cfc7781f7d21e0d0c37a95f96e74e4303cbd73e",
            ),
            "LocalMath" => (
                url = "https://github.com/PraneethMerugu/LocalMath.jl",
                replay_revision = "b699002a05f84e240e34162d509d6b952bf7d437",
                metal_revision = "22e7b42905522e53e04b4c0febadb96e30189a80",
            ),
            # Potts cannot pin the commit containing its own exact manifest.
            # Its immutable self revision is still syntax-checked below.
            "Potts" => (
                url = "https://github.com/PraneethMerugu/Potts.jl",
                replay_revision = nothing,
                metal_revision = nothing,
            ),
        )
        full_revision = r"^[0-9a-f]{40}$"
        for profile in exact_profiles
            manifest = TOML.parsefile(profile.manifest)
            @test manifest["julia_version"] == profile.julia
            dependencies = manifest["deps"]
            for (name, source) in upstream_sources
                entries = dependencies[name]
                entry = entries isa AbstractVector ? only(entries) : entries
                @test !haskey(entry, "path")
                @test entry["repo-url"] == source.url
                @test match(full_revision, entry["repo-rev"]) !== nothing
                @test match(full_revision, entry["git-tree-sha1"]) !== nothing
                qualified_revision = getproperty(source, profile.revision)
                if qualified_revision !== nothing
                    @test entry["repo-rev"] == qualified_revision
                end
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
