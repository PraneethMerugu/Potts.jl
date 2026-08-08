const AUTHORITATIVE_G5H_TESTS = (
    "test_public_api_v2.jl",
    "test_system_contract.jl",
    "test_statements_and_traversal.jl",
    "test_completion_and_diagnostics.jl",
    "test_units_and_parameters.jl",
    "test_mtkcompile.jl",
    "test_initial_problem_remake.jl",
    "test_runtime_solution_sii.jl",
    "test_source_traversal_authority.jl",
    "test_native_authoring.jl",
    "test_sciml_lifecycle_v2.jl",
    "test_lifecycle_public_v2.jl",
    "test_relationship_host_transactions_v2.jl",
    "test_external_compiler_spi_v2.jl",
    "test_scientific_operation_spi.jl",
    "test_scientific_witnesses_v2.jl",
    "test_fresh_process_v2.jl",
    "test_core_spi_boundary.jl",
    "test_package_quality.jl",
)

const G5H_TEST_SUPPORT_FILES = (
    "runtests.jl",
    "setup.jl",
    "platform_smoke.jl",
    "test_runner_authority.jl",
)

function verify_authoritative_runner(test_root::AbstractString, files::Tuple)
    @testset "authoritative runner closure" begin
        @test !isempty(files)
        @test length(unique(files)) == length(files)
        @test all(file -> isfile(joinpath(test_root, file)), files)

        # Every top-level test file is either an authoritative G5H test or a
        # named runner/support file. This prevents superseded suites from
        # surviving silently outside `Pkg.test` after witness migration.
        actual_top_level = Set(
            name for name in readdir(test_root) if endswith(name, ".jl")
        )
        expected_top_level = Set((
            AUTHORITATIVE_G5H_TESTS...,
            G5H_TEST_SUPPORT_FILES...,
        ))
        @test actual_top_level == expected_top_level || begin
            @info "non-authoritative top-level test inventory" missing =
                setdiff(expected_top_level, actual_top_level) unexpected =
                setdiff(actual_top_level, expected_top_level)
            false
        end

        # Literal repository-owned fixture includes are part of the
        # authoritative source boundary too. Follow them transitively so a
        # clean top-level test cannot hide stale APIs or private Core reach in
        # an included helper module.
        sources = String[]
        pending = normpath.(joinpath.(test_root, collect(files)))
        seen = Set{String}()
        while !isempty(pending)
            file = popfirst!(pending)
            file in seen && continue
            push!(seen, file)
            push!(sources, file)
            source = read(file, String)
            for matched in eachmatch(r"include\(\"([^\"]+\.jl)\"\)", source)
                included = normpath(joinpath(dirname(file), matched.captures[1]))
                relative = relpath(included, normpath(test_root))
                (relative == ".." || startswith(relative, ".." * string(Base.Filesystem.path_separator))) &&
                    continue
                isfile(included) && push!(pending, included)
            end
        end

        # ModelingToolkitBase's `isscheduled` helper is intentionally private
        # in the pinned upstream release. Potts systems query their own
        # structural state through `PottsToolkit.is_scheduled`; native MTK
        # systems may use the generated public `get_isscheduled` accessor.
        project_root = dirname(normpath(test_root))
        for relative_root in ("src", "ext", "integration", "test")
            scan_root = joinpath(project_root, relative_root)
            isdir(scan_root) || continue
            for (directory, _, names) in walkdir(scan_root)
                for name in names
                    endswith(name, ".jl") || continue
                    file = joinpath(directory, name)
                    @test !occursin(
                        r"ModelingToolkitBase\.isscheduled\s*\(",
                        read(file, String),
                    ) || begin
                        @info "private upstream scheduling predicate reach" file
                        false
                    end
                end
            end
        end

        stale_invocations = (
            r"(?<![A-Za-z0-9_])compile\s*\(",
            r"\bPottsExecutable\s*\(",
            r"\bSequentialEngine\s*\(",
            r"\bCheckerboardEngine\s*\(",
        )
        for file in sources
            source = read(file, String)
            for pattern in stale_invocations
                @test isnothing(match(pattern, source)) || begin
                    @info "stale public lifecycle invocation in authoritative test" file pattern
                    false
                end
            end

            # Root tests may consume the narrow stable Core package API or one
            # of its two named SPIs. They may not couple to Core's private file
            # topology, underscored helpers, or formerly broad top-level API.
            @test !occursin(r"CorePotts\._[A-Za-z_]", source) || begin
                @info "private underscored Core reach in authoritative root test" file
                false
            end
            for found in eachmatch(
                    r"CorePotts\.([A-Za-z_][A-Za-z0-9_!]*)(?:\.([A-Za-z_][A-Za-z0-9_!]*))?",
                    source,
                )
                owner = Symbol(found.captures[1])
                member = found.captures[2]
                if owner in (:CompilerSPI, :BackendSPI)
                    member === nothing && continue
                    spi = getproperty(CorePotts, owner)
                    @test Base.ispublic(spi, Symbol(member)) || begin
                        @info "non-public named Core SPI reach" file owner member
                        false
                    end
                else
                    @test Base.ispublic(CorePotts, owner) || begin
                        @info "unscoped private Core reach" file owner
                        false
                    end
                end
            end
            for found in eachmatch(
                    r"(?<!\.)\b(CompilerSPI|BackendSPI)\.([A-Za-z_][A-Za-z0-9_!]*)",
                    source,
                )
                owner = Symbol(found.captures[1])
                member = Symbol(found.captures[2])
                spi = getproperty(CorePotts, owner)
                @test Base.ispublic(spi, member) || begin
                    @info "non-public aliased Core SPI reach" file owner member
                    false
                end
            end
        end
    end
    return nothing
end
