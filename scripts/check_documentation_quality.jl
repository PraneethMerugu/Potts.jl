module DocumentationQuality

using TOML
using SHA

export load_spec, validate_spec, validate_repository, run_check

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_SPEC = joinpath(ROOT, "spec", "documentation-quality-v1.toml")
const INSTALL_SMOKE_SOURCE = joinpath(
    "docs", "models", "tutorials", "install_and_verify.jl")
const PAGE_FIELDS = (
    "id", "title", "kind", "path", "audience", "support", "owner", "state",
    "required", "in_navigation", "runtime_class", "visual", "capabilities",
)
const MEDIA_EXTENSIONS = Set([".gif", ".mp4", ".webm", ".mov"])

load_spec(path::AbstractString = DEFAULT_SPEC) = TOML.parsefile(path)

function _strings(value)
    value isa Vector || return nothing
    all(item -> item isa AbstractString, value) || return nothing
    return String.(value)
end

function _allowed(spec, key)
    policy = get(spec, "policy", Dict{String, Any}())
    values = _strings(get(policy, key, Any[]))
    return values === nothing ? Set{String}() : Set(values)
end

function _duplicates(values)
    seen = Set{eltype(values)}()
    duplicates = Set{eltype(values)}()
    for value in values
        value in seen ? push!(duplicates, value) : push!(seen, value)
    end
    return sort!(collect(duplicates))
end

function _require_fields!(errors, table, fields, label)
    for field in fields
        haskey(table, field) || push!(errors, "$label is missing `$field`")
    end
end

function _installation_source_digest(root::AbstractString)
    context = SHA2_256_CTX()
    for relative_path in (
            "Project.toml",
            joinpath("lib", "CorePotts", "Project.toml"),
            INSTALL_SMOKE_SOURCE)
        portable_path = replace(relative_path, '\\' => '/')
        update!(context, codeunits(portable_path))
        portable_source = replace(
            read(joinpath(root, relative_path), String), "\r\n" => "\n")
        update!(context, codeunits(portable_source))
    end
    return bytes2hex(digest!(context))
end

function _validate_pages!(errors, spec)
    pages = get(spec, "pages", Any[])
    pages isa Vector || begin
        push!(errors, "`pages` must be an array of tables")
        return
    end

    audiences = _allowed(spec, "audiences")
    supports = _allowed(spec, "support_levels")
    kinds = _allowed(spec, "page_kinds")
    states = _allowed(spec, "page_states")
    runtimes = _allowed(spec, "runtime_classes")
    visuals = _allowed(spec, "visual_classes")
    provenances = _allowed(spec, "provenance_classes")
    forbidden = _allowed(spec, "forbidden_public_capability_tags")

    ids = String[]
    paths = String[]
    for (index, page) in enumerate(pages)
        label = "pages[$index]"
        page isa AbstractDict || begin
            push!(errors, "$label must be a table")
            continue
        end
        _require_fields!(errors, page, PAGE_FIELDS, label)
        all(haskey(page, field) for field in PAGE_FIELDS) || continue

        id = page["id"]
        path = page["path"]
        id isa AbstractString || push!(errors, "$label.id must be a string")
        path isa AbstractString || push!(errors, "$label.path must be a string")
        id isa AbstractString && push!(ids, String(id))
        path isa AbstractString && push!(paths, String(path))

        id isa AbstractString && match(r"^[a-z0-9][a-z0-9-]*$", id) === nothing &&
            push!(errors, "$label.id `$id` is not a lowercase kebab-case identifier")
        path isa AbstractString &&
            !(startswith(path, "docs/src/") && endswith(path, ".md")) &&
            push!(errors, "$label.path `$path` must be a Markdown file under docs/src")

        for (field, allowed) in (
                ("audience", audiences), ("support", supports), ("kind", kinds),
                ("state", states), ("runtime_class", runtimes), ("visual", visuals))
            value = page[field]
            value isa AbstractString || begin
                push!(errors, "$label.$field must be a string")
                continue
            end
            String(value) in allowed ||
                push!(errors, "$label.$field `$value` is not an allowed value")
        end

        page["required"] isa Bool || push!(errors, "$label.required must be Boolean")
        page["in_navigation"] isa Bool ||
            push!(errors, "$label.in_navigation must be Boolean")
        page["owner"] isa AbstractString && !isempty(strip(page["owner"])) ||
            push!(errors, "$label.owner must be a nonempty string")

        capabilities = _strings(page["capabilities"])
        capabilities === nothing && begin
            push!(errors, "$label.capabilities must be an array of strings")
            capabilities = String[]
        end
        overlap = sort!(collect(intersect(Set(capabilities), forbidden)))
        isempty(overlap) || push!(errors,
            "$label publishes excluded Phase 16 capability tags: $(join(overlap, ", "))")

        kind = get(page, "kind", "")
        state = get(page, "state", "")
        required = get(page, "required", false)
        if required === true && state == "target" && kind in ("learn", "example")
            source = get(page, "canonical_source", nothing)
            source isa AbstractString && startswith(source, "docs/models/") &&
                endswith(source, ".jl") || push!(errors,
                "$label requires a canonical Julia source under docs/models")
        end

        if kind == "example"
            provenance = get(page, "provenance", nothing)
            provenance isa AbstractString && String(provenance) in provenances ||
                push!(errors, "$label requires an allowed provenance classification")
            if provenance == "concept_inspired" || provenance == "adapted"
                sources = _strings(get(page, "inspiration_sources", Any[]))
                sources !== nothing && !isempty(sources) ||
                    push!(errors, "$label requires at least one inspiration source")
            end
        end

        if get(page, "support", "") == "experimental"
            get(page, "visible_status", false) === true ||
                push!(errors, "$label is experimental but lacks visible_status = true")
        end
    end

    for duplicate in _duplicates(ids)
        push!(errors, "duplicate page id `$duplicate`")
    end
    for duplicate in _duplicates(paths)
        push!(errors, "duplicate page path `$duplicate`")
    end

    gate = get(spec, "quality_gate", Dict{String, Any}())
    required_learn = get(gate, "required_learn_pages", nothing)
    required_examples = get(gate, "required_examples", nothing)
    learn_count = count(page -> page isa AbstractDict &&
        get(page, "kind", "") == "learn" &&
        get(page, "state", "") == "target" &&
        get(page, "required", false) === true, pages)
    example_count = count(page -> page isa AbstractDict &&
        get(page, "kind", "") == "example" &&
        get(page, "state", "") == "target" &&
        get(page, "required", false) === true, pages)
    required_learn isa Integer && learn_count == required_learn ||
        push!(errors, "target registers $learn_count required Learn pages; expected $required_learn")
    required_examples isa Integer && example_count == required_examples ||
        push!(errors,
            "target registers $example_count required examples; expected $required_examples")
end

function _validate_api_policy!(errors, spec)
    api = get(spec, "api", nothing)
    api isa AbstractDict || begin
        push!(errors, "missing [api] policy")
        return
    end
    _require_fields!(errors, api, (
        "phase13_inventory", "phase14_allowlist", "makie_inventory",
        "phase14_provisional_class", "phase14_required_status", "act_class",
        "phase13_class_map", "makie_class_map",
    ), "api")

    allowed = _allowed(spec, "api_classes")
    for map_name in ("phase13_class_map", "makie_class_map")
        mapping = get(api, map_name, nothing)
        mapping isa AbstractDict || continue
        for (source_class, target_class) in mapping
            target_class isa AbstractString && String(target_class) in allowed ||
                push!(errors,
                    "api.$map_name maps `$source_class` to invalid class `$target_class`")
        end
    end
    get(api, "phase14_provisional_class", nothing) == "experimental" ||
        push!(errors, "Phase 14 provisional exports must classify as experimental")
    get(api, "act_class", nothing) == "experimental" ||
        push!(errors, "Act must remain experimental while the Phase 14 registry is provisional")
end

function _validate_gate!(errors, spec)
    gate = get(spec, "quality_gate", nothing)
    gate isa AbstractDict || begin
        push!(errors, "missing [quality_gate]")
        return
    end
    get(gate, "minimum_rubric_score", 0) >= 90 ||
        push!(errors, "minimum rubric score must be at least 90")
    get(gate, "stable_docstring_coverage", 0.0) == 1.0 ||
        push!(errors, "stable docstring coverage must be 1.0")
    get(gate, "public_name_classification_coverage", 0.0) == 1.0 ||
        push!(errors, "public-name classification coverage must be 1.0")
    get(gate, "strict_documenter", false) === true ||
        push!(errors, "strict Documenter must be required")
    get(gate, "weekly_external_links", false) === true ||
        push!(errors, "weekly external-link checking must be required")
    get(gate, "visible_canonical_programs", false) === true ||
        push!(errors, "visible canonical programs must be required")
    get(gate, "forbid_reader_includes", false) === true ||
        push!(errors, "reader-facing include calls must be forbidden")
    get(gate, "visual_examples_use_makiepotts", false) === true ||
        push!(errors, "visual examples must exercise MakiePotts")
    get(gate, "visual_examples_use_backend", false) === true ||
        push!(errors, "visual examples must exercise a Makie backend")
    get(gate, "forbid_custom_example_images", false) === true ||
        push!(errors, "custom example images must be forbidden")
    platforms = Set(something(_strings(get(gate, "required_platform_smokes", Any[])), String[]))
    platforms == Set(["macos", "linux", "windows"]) ||
        push!(errors, "platform smokes must be macos, linux, and windows")
    reviews = Set(something(_strings(get(gate, "required_task_reviews", Any[])), String[]))
    reviews == Set(["beginner", "model_builder", "extension_author"]) ||
        push!(errors, "task reviews must cover beginner, model_builder, and extension_author")
end

function _validate_evidence_shape!(errors, spec)
    evidence = get(spec, "current_evidence", nothing)
    evidence isa AbstractDict || begin
        push!(errors, "missing [current_evidence]")
        return
    end
    score = get(evidence, "rubric_score", nothing)
    score isa Integer && 0 <= score <= 100 ||
        push!(errors, "current evidence rubric_score must be an integer from 0 to 100")
    for (list_key, map_key) in (
            ("platform_smokes", "platform_evidence"),
            ("task_reviews", "task_review_evidence"))
        accepted = _strings(get(evidence, list_key, Any[]))
        accepted === nothing && begin
            push!(errors, "current_evidence.$list_key must be a string array")
            continue
        end
        paths = get(evidence, map_key, nothing)
        paths isa AbstractDict || begin
            push!(errors, "missing [current_evidence.$map_key]")
            continue
        end
        for id in accepted
            path = get(paths, id, nothing)
            path isa AbstractString && !isempty(strip(path)) ||
                push!(errors, "accepted $id in $list_key lacks an evidence path")
        end
    end
end

function _validate_legacy_media!(errors, spec)
    pages = get(spec, "pages", Any[])
    page_ids = Set(String(page["id"]) for page in pages
        if page isa AbstractDict && get(page, "id", nothing) isa AbstractString)
    records = get(spec, "legacy_media", Any[])
    records isa Vector || begin
        push!(errors, "`legacy_media` must be an array of tables")
        return
    end
    paths = String[]
    for (index, record) in enumerate(records)
        label = "legacy_media[$index]"
        record isa AbstractDict || begin
            push!(errors, "$label must be a table")
            continue
        end
        _require_fields!(errors, record,
            ("path", "status", "replacement_page", "release_blocker"), label)
        path = get(record, "path", nothing)
        path isa AbstractString && push!(paths, String(path))
        get(record, "status", nothing) == "pending_canonical_replacement" ||
            push!(errors, "$label has unsupported status")
        replacement = get(record, "replacement_page", nothing)
        replacement isa AbstractString && String(replacement) in page_ids ||
            push!(errors, "$label replacement_page is not a registered page id")
        get(record, "release_blocker", nothing) isa Bool ||
            push!(errors, "$label.release_blocker must be Boolean")
    end
    for duplicate in _duplicates(paths)
        push!(errors, "duplicate legacy media path `$duplicate`")
    end
end

function _validate_commands!(errors, spec)
    commands = get(spec, "commands", Any[])
    commands isa Vector || begin
        push!(errors, "`commands` must be an array of tables")
        return
    end
    expected = Dict(
        "documentation_structure" =>
            "julia --project=. --startup-file=no scripts/check_documentation_quality.jl",
        "strict_documenter" =>
            "julia --project=docs --startup-file=no docs/make.jl",
        "phase13_api" =>
            "julia --project=docs --startup-file=no scripts/check_phase13_api_inventory.jl",
        "makie_api" =>
            "julia --project=. --startup-file=no scripts/check_makiepotts_contract.jl",
    )
    seen = Set{String}()
    for (index, record) in enumerate(commands)
        label = "commands[$index]"
        record isa AbstractDict || begin
            push!(errors, "$label must be a table")
            continue
        end
        _require_fields!(errors, record,
            ("id", "command", "required_for_release"), label)
        id = get(record, "id", nothing)
        command = get(record, "command", nothing)
        id isa AbstractString || begin
            push!(errors, "$label.id must be a string")
            continue
        end
        push!(seen, String(id))
        get(expected, String(id), nothing) == command ||
            push!(errors, "$label does not match the accepted `$id` command")
        get(record, "required_for_release", false) === true ||
            push!(errors, "$label must be required for release")
    end
    seen == Set(keys(expected)) ||
        push!(errors, "required commands do not match the accepted release checks")
end

function validate_spec(spec::AbstractDict)
    errors = String[]
    get(spec, "schema_version", nothing) == "1.0.0" ||
        push!(errors, "schema_version must be 1.0.0")
    get(spec, "status", nothing) == "accepted-target" ||
        push!(errors, "status must be accepted-target")
    get(spec, "phase16_publication_excluded", false) === true ||
        push!(errors, "Phase 16 publication must remain excluded")

    authorities = _strings(get(spec, "authorities", Any[]))
    authorities !== nothing && length(authorities) == 4 ||
        push!(errors, "exactly four accepted audit/interview authorities are required")

    sections = _strings(get(spec, "required_navigation_sections", Any[]))
    required_sections = Set([
        "Home", "Learn", "Examples", "Published Models",
        "Concepts and Guarantees", "API",
    ])
    sections !== nothing && Set(sections) == required_sections ||
        push!(errors, "required navigation sections do not match the accepted architecture")

    budgets = get(spec, "budgets", Dict{String, Any}())
    get(budgets, "fast_example_seconds", nothing) == 15 ||
        push!(errors, "fast example budget must be 15 seconds")
    get(budgets, "warm_suite_seconds", nothing) == 300 ||
        push!(errors, "warm suite budget must be 300 seconds")

    _validate_gate!(errors, spec)
    _validate_evidence_shape!(errors, spec)
    _validate_pages!(errors, spec)
    _validate_api_policy!(errors, spec)
    _validate_legacy_media!(errors, spec)
    _validate_commands!(errors, spec)
    return errors
end

function _validate_phase13_inventory!(errors, spec, root)
    api = spec["api"]
    path = joinpath(root, api["phase13_inventory"])
    isfile(path) || begin
        push!(errors, "missing Phase 13 API inventory: $(relpath(path, root))")
        return
    end
    inventory = TOML.parsefile(path)
    modules = get(inventory, "modules", Dict{String, Any}())
    class_map = api["phase13_class_map"]
    allowed_target = _allowed(spec, "api_classes")
    for module_name in ("CorePotts", "PottsToolkit")
        module_inventory = get(modules, module_name, nothing)
        module_inventory isa AbstractDict || begin
            push!(errors, "Phase 13 inventory lacks $module_name")
            continue
        end
        entries = get(module_inventory, "exports", Any[])
        counts = get(module_inventory, "counts", Dict{String, Any}())
        sum(values(counts)) == get(module_inventory, "export_count", -1) ||
            push!(errors, "$module_name Phase 13 classifications do not cover every export")
        isempty(get(module_inventory, "undocumented_stable", Any[])) ||
            push!(errors, "$module_name has undocumented frozen stable API")
        seen = Set{String}()
        for entry in entries
            entry isa AbstractDict || continue
            name = String(get(entry, "name", ""))
            name in seen && push!(errors, "$module_name inventory repeats `$name`")
            push!(seen, name)
            source_class = String(get(entry, "classification", ""))
            map_key = source_class == "stable" ?
                (module_name == "CorePotts" ? "stable_corepotts" : "stable_pottstoolkit") :
                source_class
            target_class = get(class_map, map_key, nothing)
            target_class isa AbstractString && String(target_class) in allowed_target ||
                push!(errors,
                    "$module_name `$name` has unmapped Phase 13 class `$source_class`")
            source_class == "stable" && get(entry, "documented", false) !== true &&
                push!(errors, "$module_name stable API `$name` lacks a docstring")
        end
        length(seen) == get(module_inventory, "export_count", -1) ||
            push!(errors, "$module_name Phase 13 export count does not match unique entries")
    end
end

function _validate_phase14_allowlist!(errors, spec, root)
    api = spec["api"]
    path = joinpath(root, api["phase14_allowlist"])
    isfile(path) || begin
        push!(errors, "missing Phase 14 API allowlist: $(relpath(path, root))")
        return
    end
    registry = TOML.parsefile(path)
    get(registry, "status", nothing) == api["phase14_required_status"] ||
        push!(errors, "Phase 14 API status changed; re-interview Act and additive classifications")
    modules = get(registry, "modules", Dict{String, Any}())
    toolkit = Set(String.(get(modules, "PottsToolkit", Any[])))
    "Act" in toolkit || push!(errors, "Phase 14 allowlist no longer contains Act")
    get(api, "phase14_provisional_class", nothing) == "experimental" ||
        push!(errors, "Phase 14 provisional allowlist must map to experimental")
end

function _validate_makie_inventory!(errors, spec, root)
    api = spec["api"]
    path = joinpath(root, api["makie_inventory"])
    isfile(path) || begin
        push!(errors, "missing MakiePotts API inventory: $(relpath(path, root))")
        return
    end
    inventory = TOML.parsefile(path)
    groups = Dict(
        "stable" => Set(String.(get(inventory, "stable_exports", Any[]))),
        "limited" => Set(String.(get(inventory, "limited_exports", Any[]))),
        "experimental" => Set(String.(get(inventory, "experimental_exports", Any[]))),
    )
    names = String[]
    for group in values(groups)
        append!(names, group)
    end
    duplicates = _duplicates(names)
    isempty(duplicates) ||
        push!(errors, "MakiePotts API classes overlap: $(join(duplicates, ", "))")
    mapping = api["makie_class_map"]
    allowed = _allowed(spec, "api_classes")
    for source_class in keys(groups)
        target_class = get(mapping, source_class, nothing)
        target_class isa AbstractString && String(target_class) in allowed ||
            push!(errors, "MakiePotts class `$source_class` is not mapped")
    end
end

function _navigation_pages(source)
    result = Set{String}()
    for matched in eachmatch(r"\"([^\"]+\.md)\"", source)
        push!(result, matched.captures[1])
    end
    return result
end

function _validate_documenter_config!(errors, spec, root)
    make_path = joinpath(root, spec["navigation_file"])
    isfile(make_path) || return
    source = read(make_path, String)
    requirements = (
        (r"\bdoctest\s*=\s*true\b", "Documenter must execute doctests"),
        (r"\blinkcheck\s*=\s*get\(ENV,\s*\"POTTS_DOCS_LINKCHECK\"",
            "Documenter must expose the scheduled external-link audit"),
        (r"\bwarnonly\s*=\s*false\b", "Documenter errors must not be downgraded to warnings"),
        (r"\bpagesonly\s*=\s*true\b", "Documenter must build only the curated manual"),
        (r"\bcheckdocs\s*=\s*:none\b",
            "Documenter export coverage must defer to the stability-aware API registries"),
    )
    for (pattern, message) in requirements
        occursin(pattern, source) || push!(errors, message)
    end
    occursin(r"\bwarnonly\s*=\s*true\b", source) &&
        push!(errors, "Documenter configuration silences errors with warnonly = true")

    link_workflow_path = joinpath(root, ".github", "workflows", "docs-links.yml")
    if !isfile(link_workflow_path)
        push!(errors, "weekly documentation link-check workflow is missing")
        return
    end
    workflow = read(link_workflow_path, String)
    for (needle, message) in (
            ("schedule:", "documentation link checking is not scheduled"),
            ("POTTS_DOCS_LINKCHECK: 'true'",
                "scheduled documentation build does not enable external-link checking"),
            ("julia --project=docs --startup-file=no docs/make.jl",
                "scheduled documentation link workflow does not run Documenter"))
        occursin(needle, workflow) || push!(errors, message)
    end
end

function _registered_relative_pages(spec)
    result = Dict{String, AbstractDict}()
    for page in spec["pages"]
        path = String(page["path"])
        result[replace(path, r"^docs/src/" => "")] = page
    end
    return result
end

function _validate_repository_pages!(errors, spec, root)
    nav_path = joinpath(root, spec["navigation_file"])
    isfile(nav_path) || begin
        push!(errors, "missing navigation file: $(relpath(nav_path, root))")
        return
    end
    navigation = read(nav_path, String)
    actual_nav = _navigation_pages(navigation)
    registered = _registered_relative_pages(spec)

    for section in spec["required_navigation_sections"]
        occursin("\"$section\"", navigation) ||
            push!(errors, "navigation lacks required section `$section`")
    end

    expected_nav = Set{String}()
    for (relative, page) in registered
        get(page, "in_navigation", false) === true && push!(expected_nav, relative)
    end
    for missing in sort!(collect(setdiff(expected_nav, actual_nav)))
        push!(errors, "registered target page is absent from navigation: $missing")
    end
    for extra in sort!(collect(setdiff(actual_nav, Set(keys(registered)))))
        push!(errors, "navigation contains unregistered page: $extra")
    end

    docs_root = joinpath(root, spec["docs_root"])
    if isdir(docs_root)
        for (directory, _, files) in walkdir(docs_root)
            for file in files
                endswith(file, ".md") || continue
                relative = relpath(joinpath(directory, file), docs_root)
                haskey(registered, relative) ||
                    push!(errors, "docs/src contains unregistered Markdown page: $relative")
            end
        end
    end

    for page in spec["pages"]
        get(page, "state", "") == "target" || continue
        get(page, "required", false) === true || continue
        path = joinpath(root, page["path"])
        if !isfile(path)
            push!(errors, "required target page is missing: $(page["path"])")
            continue
        end
        get(page, "kind", "") == "home" && continue
        page_source = replace(read(path, String), "\r\n" => "\n")
        marker = "(@id $(page["id"]))"
        occursin(marker, page_source) ||
            push!(errors, "required page $(page["path"]) lacks `$marker`")
        if haskey(page, "canonical_source")
            source = joinpath(root, page["canonical_source"])
            if !isfile(source)
                push!(errors, "canonical source is missing: $(page["canonical_source"])")
                continue
            end

            kind = get(page, "kind", "")
            kind in ("learn", "example") || continue
            occursin(r"\b(?:Base\.)?include\s*\(", page_source) &&
                push!(errors,
                    "reader-facing include call hides the workflow in $(page["path"])")

            blocks = [
                match.captures[1] for match in eachmatch(
                    r"```@example[^\n]*\n(.*?)\n```"s, page_source)
            ]
            canonical = strip(replace(read(source, String), "\r\n" => "\n"))
            any(block -> occursin(canonical, block), blocks) ||
                push!(errors,
                    "canonical source is not visible in an evaluated block: $(page["path"])")

            if kind == "example" && get(page, "visual", "none") != "none"
                visible_code = join(blocks, "\n")
                occursin(r"!\[[^\]]*\]\([^)]+\)", page_source) &&
                    push!(errors,
                        "visual example references a custom image: $(page["path"])")
                occursin(r"\busing\s+MakiePotts\b", visible_code) ||
                    push!(errors,
                        "visual example does not import MakiePotts: $(page["path"])")
                occursin(r"\brenderframes?\s*\(", visible_code) ||
                    push!(errors,
                        "visual example does not materialize a MakiePotts frame: $(page["path"])")
                occursin(r"\busing\s+CairoMakie\b", visible_code) ||
                    push!(errors,
                        "visual example does not import a Makie backend: $(page["path"])")
                occursin(r"\b(?:plot|pottsplot!)\s*\(", visible_code) ||
                    push!(errors,
                        "visual example does not execute the MakiePotts recipe: $(page["path"])")
            end
        end
    end
end

function _validate_media!(errors, spec, root)
    legacy = Dict(String(record["path"]) => record for record in spec["legacy_media"])
    docs_root = joinpath(root, spec["docs_root"])
    if isdir(docs_root)
        for (directory, _, files) in walkdir(docs_root)
            for file in files
                extension = lowercase(splitext(file)[2])
                extension in MEDIA_EXTENSIONS || continue
                relative = replace(relpath(joinpath(directory, file), root), '\\' => '/')
                haskey(legacy, relative) ||
                    push!(errors, "generated media lacks a registry record: $relative")
            end
        end
    end
    for (path, record) in legacy
        full_path = joinpath(root, path)
        isfile(full_path) || continue
        get(record, "release_blocker", false) === true &&
            push!(errors, "legacy media remains a release blocker: $path")
    end
end

function _validate_current_evidence!(errors, spec, root)
    gate = spec["quality_gate"]
    evidence = get(spec, "current_evidence", Dict{String, Any}())
    score = get(evidence, "rubric_score", 0)
    score >= gate["minimum_rubric_score"] ||
        push!(errors,
            "current documentation rubric score $score is below $(gate["minimum_rubric_score"])")
    platforms = Set(something(
        _strings(get(evidence, "platform_smokes", Any[])), String[]))
    platform_evidence = get(evidence, "platform_evidence", Dict{String, Any}())
    for platform in gate["required_platform_smokes"]
        if !(platform in platforms)
            push!(errors, "missing accepted CPU installation smoke: $platform")
            continue
        end
        path = get(platform_evidence, platform, nothing)
        path isa AbstractString || begin
            push!(errors, "accepted $platform CPU smoke lacks an evidence path")
            continue
        end
        full_path = joinpath(root, path)
        if !isfile(full_path)
            push!(errors, "accepted $platform CPU smoke evidence is missing: $path")
            continue
        end
        record = TOML.parsefile(full_path)
        get(record, "status", nothing) == "passed" ||
            push!(errors, "$platform CPU smoke evidence is not passed")
        get(record, "platform", nothing) == platform ||
            push!(errors, "$platform CPU smoke evidence names a different platform")
        get(record, "smoke_source", nothing) == INSTALL_SMOKE_SOURCE ||
            push!(errors, "$platform CPU smoke evidence names a different source")
        get(record, "source_digest", nothing) == _installation_source_digest(root) ||
            push!(errors, "$platform CPU smoke evidence is stale")
    end
    reviews = Set(something(_strings(get(evidence, "task_reviews", Any[])), String[]))
    review_evidence = get(evidence, "task_review_evidence", Dict{String, Any}())
    for review in gate["required_task_reviews"]
        if !(review in reviews)
            push!(errors, "missing accepted task review: $review")
            continue
        end
        path = get(review_evidence, review, nothing)
        path isa AbstractString || begin
            push!(errors, "accepted $review task review lacks an evidence path")
            continue
        end
        full_path = joinpath(root, path)
        if !isfile(full_path)
            push!(errors, "accepted $review task review evidence is missing: $path")
            continue
        end
        record = TOML.parsefile(full_path)
        get(record, "status", nothing) == "passed" ||
            push!(errors, "$review task review evidence is not passed")
        get(record, "audience", nothing) == review ||
            push!(errors, "$review task review evidence names a different audience")
        get(record, "method", nothing) == "rendered_site_task_walkthrough" ||
            push!(errors, "$review task review did not exercise the rendered site")
        checks = get(record, "checks", Any[])
        if !(checks isa Vector) || isempty(checks)
            push!(errors, "$review task review has no recorded checks")
            continue
        end
        for (index, check) in enumerate(checks)
            label = "$review task review check $index"
            check isa AbstractDict || begin
                push!(errors, "$label is not a table")
                continue
            end
            get(check, "passed", false) === true ||
                push!(errors, "$label did not pass")
            detail = get(check, "evidence", nothing)
            detail isa AbstractString && !isempty(strip(detail)) ||
                push!(errors, "$label has no evidence")
        end
    end

end

function validate_repository(spec::AbstractDict; root::AbstractString = ROOT)
    errors = validate_spec(spec)
    isempty(errors) || return errors

    for authority in spec["authorities"]
        isfile(joinpath(root, authority)) ||
            push!(errors, "missing accepted authority: $authority")
    end
    _validate_phase13_inventory!(errors, spec, root)
    _validate_phase14_allowlist!(errors, spec, root)
    _validate_makie_inventory!(errors, spec, root)
    _validate_documenter_config!(errors, spec, root)
    _validate_repository_pages!(errors, spec, root)
    _validate_media!(errors, spec, root)
    _validate_current_evidence!(errors, spec, root)
    return errors
end

function run_check(args = String[])
    spec_path = DEFAULT_SPEC
    spec_only = false
    index = 1
    while index <= length(args)
        argument = args[index]
        if argument == "--spec-only"
            spec_only = true
        elseif argument == "--spec"
            index == length(args) && error("--spec requires a path")
            index += 1
            spec_path = abspath(args[index])
        else
            error("unknown argument: $argument")
        end
        index += 1
    end

    spec = load_spec(spec_path)
    errors = spec_only ? validate_spec(spec) : validate_repository(spec)
    if isempty(errors)
        mode = spec_only ? "specification structure" : "9/10 target"
        println("Documentation quality $mode passed")
        return 0
    end

    mode = spec_only ? "specification structure" : "9/10 target"
    println(stderr, "Documentation quality $mode failed with $(length(errors)) issue(s):")
    for error_message in errors
        println(stderr, "  - ", error_message)
    end
    return 1
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(DocumentationQuality.run_check(ARGS))
end
