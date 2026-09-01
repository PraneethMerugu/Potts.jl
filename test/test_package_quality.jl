@testset "package quality" begin
    Aqua.test_all(PottsToolkit; ambiguities = false, persistent_tasks = false)
    ExplicitImports.test_explicit_imports(PottsToolkit)

    ambiguities = Test.detect_ambiguities(PottsToolkit, Base; recursive = true)
    owned = filter(ambiguities) do pair
        any(method -> method.module === PottsToolkit, pair)
    end
    @test isempty(owned)

    project = TOML.parsefile(joinpath(pkgdir(PottsToolkit), "Project.toml"))
    dependencies = Set(keys(get(project, "deps", Dict())))
    weak_dependencies = Set(keys(get(project, "weakdeps", Dict())))

    # Optional integrations remain extensions rather than hard requirements.
    @test isempty(intersect(
        dependencies,
        Set(("DiffEqGPU", "Metal", "MethodOfLines", "ModelingToolkit",
            "StaticArrays", "Unitful")),
    ))
    @test Set(("DiffEqGPU", "Metal", "MethodOfLines", "ModelingToolkit",
        "StaticArrays", "Unitful")) ⊆ weak_dependencies

    repository = pkgdir(PottsToolkit)
    live_manifests = String[]
    for (directory, subdirectories, files) in walkdir(repository)
        filter!(name -> name != ".git" && name != "design" &&
            !(directory == repository && name == "scripts"), subdirectories)
        "Manifest.toml" in files && push!(live_manifests,
            joinpath(directory, "Manifest.toml"))
    end

    @testset "live path-manifest closure" begin
        for manifest_path in sort!(live_manifests)
            manifest = TOML.parsefile(manifest_path)
            for (recorded_name, entries) in get(manifest, "deps", Dict())
                for entry in (entries isa AbstractVector ? entries : (entries,))
                    haskey(entry, "path") || continue
                    package_directory = normpath(joinpath(
                        dirname(manifest_path), entry["path"]))
                    target_project_path = joinpath(package_directory, "Project.toml")
                    @test isfile(target_project_path)
                    isfile(target_project_path) || continue
                    target = TOML.parsefile(target_project_path)
                    recorded_dependencies = Set(get(entry, "deps", String[]))
                    target_dependencies = Set(keys(get(target, "deps", Dict())))
                    @test recorded_name == target["name"]
                    @test entry["uuid"] == target["uuid"]
                    @test get(entry, "version", nothing) == get(target, "version", nothing)
                    @test recorded_dependencies == target_dependencies
                end
            end
        end
    end
end
