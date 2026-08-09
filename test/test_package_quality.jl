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

    project_root = pkgdir(PottsToolkit)
    active_roots = (
        "src",
        "ext",
        "test",
        "integration",
        joinpath("lib", "CorePotts", "src"),
        joinpath("lib", "CorePotts", "test"),
        joinpath("lib", "MakiePotts", "src"),
        joinpath("lib", "MakiePotts", "test"),
        joinpath("docs", "src"),
        "examples",
    )
    active_files = String[]
    for relative in active_roots
        directory = joinpath(project_root, relative)
        isdir(directory) || continue
        append!(
            active_files,
            (
                joinpath(root, name)
                for (root, _, names) in walkdir(directory)
                for name in names
                if any(suffix -> endswith(name, suffix), (".jl", ".md", ".toml"))
            ),
        )
    end

    retired_invocations = (
        r"\bPottsModel\s*\(",
        r"\bPottsExecutable\s*\(",
        r"\bSequentialEngine\s*\(",
        r"\bCheckerboardEngine\s*\(",
        r"\bExplicitDiffusion\s*\(",
        r"\bCUDABackend\s*\(",
        r"\bROCmBackend\s*\(",
    )
    private_upstream = r"\b(?:ModelingToolkit|ModelingToolkitBase|MethodOfLines|SciMLBase|Symbolics)\._[A-Za-z_]"
    for file in active_files
        contents = read(file, String)
        @test all(pattern -> isnothing(match(pattern, contents)), retired_invocations)
        @test isnothing(match(private_upstream, contents))
        relative = relpath(file, project_root)
        owns_core_internals = startswith(
            relative, joinpath("lib", "CorePotts", "test")
        ) || startswith(relative, joinpath("test", "backend_conformance"))
        owns_core_internals ||
            @test !occursin(r"CorePotts\._[A-Za-z_]", contents)
    end

    docs_source = joinpath(project_root, "docs", "src")
    documented_pages = Set(
        relpath(joinpath(root, name), docs_source)
        for (root, _, names) in walkdir(docs_source)
        for name in names
        if endswith(name, ".md")
    )
    make_source = read(joinpath(project_root, "docs", "make.jl"), String)
    curated_pages = Set(
        matched.captures[1]
        for matched in eachmatch(r"\"([^\"]+\.md)\"", make_source)
    )
    @test documented_pages == curated_pages

    @test dependencies == Set((
        "CorePotts",
        "DynamicQuantities",
        "ModelingToolkitBase",
        "SHA",
        "SciMLBase",
        "SymbolicIndexingInterface",
        "Symbolics",
    ))
    @test Set(keys(get(project, "weakdeps", Dict()))) == Set((
        "DiffEqGPU",
        "Metal",
        "MethodOfLines",
        "ModelingToolkit",
        "StaticArrays",
        "Unitful",
    ))
end
