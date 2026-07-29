#!/usr/bin/env julia

using SHA
using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function load(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing required file: $relative")
    return isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
end

function normalized_source(source)
    normalized = replace(source, "\r\n" => "\n")
    normalized = replace(normalized, r"[ \t]+$"m => "")
    strip(normalized)
end

function example_blocks(source)
    String[match.captures[1] for match in
        eachmatch(r"```@example[^\n]*\n([\s\S]*?)\n```", source)]
end

function sha256_file(relative)
    bytes2hex(sha256(read(joinpath(ROOT, relative))))
end

contract =
    load("spec/process-bigraph-phase17-documentation-quality-v1.toml")
entry = load("spec/process-bigraph-phase17-entry-v1.toml")
pages = get(contract, "pages", Any[])
paths = String[row["path"] for row in pages]
ids = String[row["id"] for row in pages]

check(length(pages) == get(contract, "required_page_count", -1),
    "registered documentation page count is stale")
check(length(paths) == length(unique(paths)),
    "documentation registry contains duplicate paths")
check(length(ids) == length(unique(ids)),
    "documentation registry contains duplicate ids")
check(all(row -> row["required"] == true, pages),
    "all registered Phase 17 pages must be required")

section_counts = Dict(
    section => count(row -> row["section"] == section, pages)
    for section in contract["top_level_sections"])
check(section_counts == Dict(
        "Home" => 1,
        "Learn" => 10,
        "Examples" => 7,
        "Scientific Case Studies" => 3,
        "Concepts and Guarantees" => 9,
        "API" => 5,
    ), "registered documentation section counts changed")
check(count(row -> row["kind"] == "example", pages) ==
      contract["required_example_program_count"],
    "complete example program count changed")
check(count(row -> occursin("case-study", row["kind"]), pages) ==
      contract["required_case_study_count"] + 1,
    "case-study page count changed")

status = get(entry, "implementation_status", "")
docs_active = status in (
    "17.D-independent-manual",
    "17.E-scientific-case-studies",
    "17.F-reconciliation-and-attestation",
    "complete",
)
if docs_active
    for relative in paths
        check(isfile(joinpath(ROOT, relative)),
            "missing registered documentation page: $relative")
    end

    required_environment = (
        "lib/ProcessBigraphs/docs/Project.toml",
        "lib/ProcessBigraphs/docs/Manifest.toml",
        "lib/ProcessBigraphs/docs/make.jl",
        "lib/ProcessBigraphs/docs/README.md",
        "lib/ProcessBigraphs/docs/src/assets/docs.css",
        "lib/ProcessBigraphs/docs/src/assets/beta.js",
        "lib/ProcessBigraphs/docs/src/assets/provenance.toml",
    )
    for relative in required_environment
        check(isfile(joinpath(ROOT, relative)),
            "missing independent documentation environment file: $relative")
    end

    project = load("lib/ProcessBigraphs/docs/Project.toml")
    manifest = load("lib/ProcessBigraphs/docs/Manifest.toml")
    check(haskey(project["deps"], "Documenter") &&
          haskey(project["deps"], "ProcessBigraphs"),
        "docs project must directly depend on Documenter and ProcessBigraphs")
    check(project["compat"]["Documenter"] == "1" &&
          project["compat"]["julia"] == "1.12.6",
        "docs project compatibility pins changed")
    check(manifest["julia_version"] == "1.12.6" &&
          haskey(manifest["deps"], "Documenter") &&
          haskey(manifest["deps"], "ProcessBigraphs"),
        "docs manifest is not a pinned Julia 1.12.6 environment")

    make = read(joinpath(ROOT, contract["build"]["make"]), String)
    required_make_fragments = (
        "warnonly = false",
        "doctest = true",
        "pagesonly = true",
        "dirname = \"ProcessBigraphs\"",
        "tag_prefix = \"ProcessBigraphs-\"",
        "push_preview = false",
    )
    for fragment in required_make_fragments
        check(occursin(fragment, make),
            "strict docs make.jl omits `$fragment`")
    end
    for row in pages
        relative = relpath(
            joinpath(ROOT, row["path"]),
            joinpath(ROOT, contract["build"]["source_root"]),
        )
        quoted = "\"$(relative)\""
        check(count(==(quoted), [match.match for match in
              eachmatch(Regex(replace(quoted, "." => "\\.")), make)]) == 1,
            "make.jl navigation must contain registered path exactly once: $relative")
    end

    forbidden = (
        r"\binclude\s*\(" => "reader-facing include",
        r"ReferenceModels\.(Wortel2021|Merks2006)\.(model|problem|composite)\s*\(" =>
            "prebuilt case-study constructor",
        r"#\s*hide\b" => "hidden executable setup",
    )
    required_contract_markers = (
        "outcome",
        "prerequisites",
        "support level",
        "complete executed source",
        "material defaults",
        "expected result",
        "establishes",
        "does not establish",
        "backend / runtime / seed",
        "reproduction command",
        "next step",
    )
    executable_pages = filter(row -> haskey(row, "canonical_source"), pages)
    check(length(executable_pages) == 18,
        "registered executable-page count must remain 18")
    for row in executable_pages
        relative = row["path"]
        source = read(joinpath(ROOT, relative), String)
        lowered = lowercase(source)
        for marker in required_contract_markers
            check(occursin(marker, lowered),
                "$relative omits page-contract marker `$marker`")
        end
        blocks = example_blocks(source)
        check(length(blocks) == 1,
            "$relative must contain exactly one complete executed source block")
        canonical = row["canonical_source"]
        check(isfile(joinpath(ROOT, canonical)),
            "missing canonical source: $canonical")
        if length(blocks) == 1 && isfile(joinpath(ROOT, canonical))
            check(normalized_source(only(blocks)) ==
                  normalized_source(read(joinpath(ROOT, canonical), String)),
                "$relative drifts from canonical source $canonical")
        end
        for (pattern, label) in forbidden
            check(!occursin(pattern, source),
                "$relative contains forbidden $label")
        end
    end
    for relative in paths
        source = read(joinpath(ROOT, relative), String)
        for (pattern, label) in first(forbidden, 2)
            check(!occursin(pattern, source),
                "$relative contains forbidden $label")
        end
    end

    provenance = load(
        "lib/ProcessBigraphs/docs/src/assets/provenance.toml")
    assets = get(provenance, "assets", Any[])
    asset_paths = String[row["path"] for row in assets]
    check(length(assets) == 7 && length(asset_paths) == length(unique(asset_paths)),
        "media provenance must contain seven unique generated assets")
    for row in assets
        relative = row["path"]
        check(isfile(joinpath(ROOT, relative)),
            "missing generated asset: $relative")
        isfile(joinpath(ROOT, relative)) || continue
        check(sha256_file(relative) == row["sha256"],
            "generated asset hash drift: $relative")
        check(!isempty(get(row, "command", "")),
            "generated asset lacks reproduction command: $relative")
        check(get(row, "alt_text_required", false) == true,
            "generated asset lacks alt-text requirement: $relative")
        if haskey(row, "source")
            check(isfile(joinpath(ROOT, row["source"])),
                "generated asset source is missing: $(row["source"])")
            if haskey(row, "source_sha256") &&
                    isfile(joinpath(ROOT, row["source"]))
                check(sha256_file(row["source"]) == row["source_sha256"],
                    "generated asset source hash drift: $(row["source"])")
            end
        end
        if haskey(row, "model_source")
            check(isfile(joinpath(ROOT, row["model_source"])),
                "generated asset model source is missing: $(row["model_source"])")
            if haskey(row, "model_source_sha256") &&
                    isfile(joinpath(ROOT, row["model_source"]))
                check(
                    sha256_file(row["model_source"]) ==
                        row["model_source_sha256"],
                    "generated asset model-source hash drift: $(
                        row["model_source"])",
                )
            end
        end
        if row["kind"] == "case-study-animation"
            check(get(row, "reduced_motion", false) == true &&
                  isfile(joinpath(ROOT, row["static_fallback"])) &&
                  isfile(joinpath(ROOT, row["text_summary_page"])),
                "animation lacks reduced-motion fallback or text summary: $relative")
            check(endswith(relative, ".mp4") &&
                  get(row, "framework", "") ==
                    "MakiePotts 0.2 / CairoMakie 0.15" &&
                  get(row, "codec", "") == "H.264" &&
                  get(row, "frames", 0) > 1 &&
                  get(row, "framerate", 0) > 0,
                "case-study animation is not pinned native Makie MP4: $relative")
            check(filesize(joinpath(ROOT, relative)) <=
                  contract["asset_budgets_bytes"]["video_each_max"],
                "case-study animation exceeds its video budget: $relative")
        end
    end
    generated_total = sum((
        filesize(joinpath(ROOT, row["path"]))
        for row in assets if isfile(joinpath(ROOT, row["path"]))
    ); init=0)
    check(generated_total <=
          contract["asset_budgets_bytes"]["new_generated_media_total_max"],
        "generated media exceeds total asset budget")
    raster_assets = filter(
        row -> endswith(row["path"], ".png"), assets)
    check(all(row -> filesize(joinpath(ROOT, row["path"])) <=
          contract["asset_budgets_bytes"]["raster_each_max"], raster_assets),
        "generated media contains an over-budget individual asset")
    media_generator =
        read(joinpath(ROOT,
            "lib/ProcessBigraphs/docs/generate_case_media.jl"), String)
    for marker in (
            "using CairoMakie",
            "using MakiePotts",
            "PottsRenderFrame",
            "record_potts",
            "wortel-animation.mp4",
            "merks-animation.mp4")
        check(occursin(marker, media_generator),
            "native Makie media generator omits `$marker`")
    end
    check(isempty(filter(
        name -> endswith(name, "-animation.svg"),
        readdir(joinpath(ROOT,
            "lib/ProcessBigraphs/docs/src/assets")))),
        "scientific animations must be native Makie video, not animated SVG")

    for id in (
            "pulse-and-decay", "nested-composites", "n-way-junctions",
            "sciml-field-adapter", "custom-engine-adapter",
            "divide-fail-recover")
        row = only(filter(page -> page["id"] == id, pages))
        source = read(joinpath(ROOT, row["path"]), String)
        check(occursin("../assets/example-results.svg", source),
            "$(row["path"]) omits its result visual")
    end
    for id in ("wortel-2021", "merks-2006")
        row = only(filter(page -> page["id"] == id, pages))
        source = read(joinpath(ROOT, row["path"]), String)
        prefix = id == "wortel-2021" ? "wortel" : "merks"
        for asset in (
                "$(prefix)-state.png",
                "case-traces.png",
                "$(prefix)-animation.mp4")
            check(occursin(asset, source),
                "$(row["path"]) omits required case-study media $asset")
        end
    end

    root_cross_links = (
        "docs/src/index.md",
        "docs/src/published-models/index.md",
        "docs/src/concepts/runtime-boundary.md",
    )
    for relative in root_cross_links
        source = read(joinpath(ROOT, relative), String)
        check(occursin(
            "https://praneethmerugu.github.io/Potts.jl/ProcessBigraphs/dev/",
            source),
            "$relative omits the independent manual cross-link")
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 17 documentation contract passed:")
    println("  registered pages: $(length(pages))")
    println("  executable canonical programs: $(
        count(row -> haskey(row, "canonical_source"), pages))")
    println("  complete site enforced: $docs_active")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 documentation check failed with $(length(failures)) error(s)")
end
