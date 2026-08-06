@testset "package quality and clean-break boundary" begin
    Aqua.test_all(PottsToolkit; ambiguities = false, persistent_tasks = false)
    ExplicitImports.test_explicit_imports(PottsToolkit)

    project = TOML.parsefile(joinpath(pkgdir(PottsToolkit), "Project.toml"))
    dependencies = Set(keys(get(project, "deps", Dict())))
    @test isempty(intersect(
        dependencies,
        Set((
            "AlgebraicRewriting",
            "Dagger",
            "KernelAbstractions",
            "Unitful",
        )),
    ))

    forbidden = (
        "Lottery",
        "TiledCheckerboard",
        "scientific_contract_versions",
        "Authoring.",
    )
    source_root = joinpath(pkgdir(PottsToolkit), "src")
    source = join(
        (
            read(joinpath(root, file), String)
            for (root, _, files) in walkdir(source_root)
            for file in files
            if endswith(file, ".jl")
        ),
        "\n",
    )
    @test all(name -> !occursin(name, source), forbidden)
end
