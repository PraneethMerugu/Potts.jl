include(joinpath(@__DIR__, "..", "scripts", "check_documentation_quality.jl"))

using .DocumentationQuality
using TOML

function documentation_page(spec, id)
    only(page for page in spec["pages"] if page["id"] == id)
end

@testset "documentation quality executable specification" begin
    spec_path = joinpath(
        @__DIR__, "..", "spec", "documentation-quality-v1.toml")
    accepted = DocumentationQuality.load_spec(spec_path)

    @test isempty(DocumentationQuality.validate_spec(accepted))

    duplicate = deepcopy(accepted)
    push!(duplicate["pages"], deepcopy(first(duplicate["pages"])))
    duplicate_errors = DocumentationQuality.validate_spec(duplicate)
    @test any(message -> occursin("duplicate page id `home`", message),
        duplicate_errors)
    @test any(message -> occursin("duplicate page path `docs/src/index.md`", message),
        duplicate_errors)

    unsupported = deepcopy(accepted)
    documentation_page(unsupported, "home")["support"] = "unreviewed"
    unsupported_errors = DocumentationQuality.validate_spec(unsupported)
    @test any(message -> occursin(
            "support `unreviewed` is not an allowed value", message),
        unsupported_errors)

    unattributed = deepcopy(accepted)
    relaxing_cell = documentation_page(unattributed, "relaxing-cell")
    delete!(relaxing_cell, "inspiration_sources")
    unattributed_errors = DocumentationQuality.validate_spec(unattributed)
    @test any(message -> occursin(
            "requires at least one inspiration source", message),
        unattributed_errors)

    phase16_leak = deepcopy(accepted)
    push!(documentation_page(phase16_leak, "home")["capabilities"], "phase16")
    phase16_errors = DocumentationQuality.validate_spec(phase16_leak)
    @test any(message -> occursin(
            "publishes excluded Phase 16 capability tags: phase16", message),
        phase16_errors)

    promoted_act = deepcopy(accepted)
    promoted_act["api"]["act_class"] = "stable_user"
    promoted_act_errors = DocumentationQuality.validate_spec(promoted_act)
    @test any(message -> occursin(
            "Act must remain experimental", message),
        promoted_act_errors)

    softened_build = deepcopy(accepted)
    strict_command = only(command for command in softened_build["commands"]
        if command["id"] == "strict_documenter")
    strict_command["required_for_release"] = false
    command_errors = DocumentationQuality.validate_spec(softened_build)
    @test any(message -> occursin("must be required for release", message),
        command_errors)

    unproven_platform = deepcopy(accepted)
    delete!(unproven_platform["current_evidence"]["platform_evidence"], "windows")
    evidence_errors = DocumentationQuality.validate_spec(unproven_platform)
    @test any(message -> occursin(
            "accepted windows in platform_smokes lacks an evidence path", message),
        evidence_errors)

    unproven_review = deepcopy(accepted)
    delete!(unproven_review["current_evidence"]["task_review_evidence"], "beginner")
    review_errors = DocumentationQuality.validate_spec(unproven_review)
    @test any(message -> occursin(
            "accepted beginner in task_reviews lacks an evidence path", message),
        review_errors)

    disabled_link_audit = deepcopy(accepted)
    disabled_link_audit["quality_gate"]["weekly_external_links"] = false
    link_errors = DocumentationQuality.validate_spec(disabled_link_audit)
    @test any(message -> occursin(
            "weekly external-link checking must be required", message),
        link_errors)

    hidden_programs = deepcopy(accepted)
    hidden_programs["quality_gate"]["visible_canonical_programs"] = false
    hidden_program_errors = DocumentationQuality.validate_spec(hidden_programs)
    @test any(message -> occursin(
            "visible canonical programs must be required", message),
        hidden_program_errors)

    reader_includes = deepcopy(accepted)
    reader_includes["quality_gate"]["forbid_reader_includes"] = false
    reader_include_errors = DocumentationQuality.validate_spec(reader_includes)
    @test any(message -> occursin(
            "reader-facing include calls must be forbidden", message),
        reader_include_errors)

    skipped_makiepotts = deepcopy(accepted)
    skipped_makiepotts["quality_gate"]["visual_examples_use_makiepotts"] = false
    skipped_makiepotts_errors = DocumentationQuality.validate_spec(skipped_makiepotts)
    @test any(message -> occursin(
            "visual examples must exercise MakiePotts", message),
        skipped_makiepotts_errors)

    skipped_backend = deepcopy(accepted)
    skipped_backend["quality_gate"]["visual_examples_use_backend"] = false
    skipped_backend_errors = DocumentationQuality.validate_spec(skipped_backend)
    @test any(message -> occursin(
            "visual examples must exercise a Makie backend", message),
        skipped_backend_errors)

    custom_images = deepcopy(accepted)
    custom_images["quality_gate"]["forbid_custom_example_images"] = false
    custom_image_errors = DocumentationQuality.validate_spec(custom_images)
    @test any(message -> occursin(
            "custom example images must be forbidden", message),
        custom_image_errors)

    mktempdir() do fixture_root
        repository_root = normpath(joinpath(@__DIR__, ".."))
        for relative_path in (
                "Project.toml",
                joinpath("lib", "CorePotts", "Project.toml"),
                joinpath("docs", "models", "tutorials", "install_and_verify.jl"))
            destination = joinpath(fixture_root, relative_path)
            mkpath(dirname(destination))
            cp(joinpath(repository_root, relative_path), destination)
        end

        digest = DocumentationQuality._installation_source_digest(fixture_root)
        for (platform, relative_path) in
                accepted["current_evidence"]["platform_evidence"]
            destination = joinpath(fixture_root, relative_path)
            mkpath(dirname(destination))
            open(destination, "w") do io
                TOML.print(io, Dict(
                    "status" => "passed",
                    "platform" => platform,
                    "smoke_source" =>
                        "docs/models/tutorials/install_and_verify.jl",
                    "source_digest" => digest,
                ))
            end
        end
        for (_, relative_path) in
                accepted["current_evidence"]["task_review_evidence"]
            destination = joinpath(fixture_root, relative_path)
            mkpath(dirname(destination))
            cp(joinpath(repository_root, relative_path), destination)
        end
        complete_evidence_errors = String[]
        DocumentationQuality._validate_current_evidence!(
            complete_evidence_errors, accepted, fixture_root)
        @test isempty(complete_evidence_errors)

        linux_path = joinpath(fixture_root,
            accepted["current_evidence"]["platform_evidence"]["linux"])
        linux_record = TOML.parsefile(linux_path)
        linux_record["source_digest"] = "stale"
        open(linux_path, "w") do io
            TOML.print(io, linux_record)
        end
        stale_evidence_errors = String[]
        DocumentationQuality._validate_current_evidence!(
            stale_evidence_errors, accepted, fixture_root)
        @test any(message -> occursin(
                "linux CPU smoke evidence is stale", message),
            stale_evidence_errors)
    end
end
