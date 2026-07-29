using Documenter
using CairoMakie
using CorePotts
using MakiePotts
using PottsToolkit
using TOML

ENV["POTTS_DOCS_ROOT"] = @__DIR__
CairoMakie.activate!(type = "svg")

function classified_bindings(api_module, names)
    bindings = IdSet{Any}()
    for name in names
        symbol = Symbol(name)
        isdefined(api_module, symbol) &&
            push!(bindings, getfield(api_module, symbol))
    end
    return bindings
end

api_inventory = TOML.parsefile(joinpath(
    @__DIR__, "..", "design", "audits", "phase-13-api-inventory.toml"))
phase14_inventory = TOML.parsefile(joinpath(
    @__DIR__, "..", "design", "audits", "phase-14-public-api-v2.toml"))
makie_inventory = TOML.parsefile(joinpath(
    @__DIR__, "..", "design", "makiepotts", "public-api-v0.2.toml"))

function inventory_names(module_name, classifications)
    entries = api_inventory["modules"][module_name]["exports"]
    return [entry["name"] for entry in entries
            if entry["classification"] in classifications]
end

const STABLE_POTTSTOOLKIT_BINDINGS = classified_bindings(
    PottsToolkit, inventory_names("PottsToolkit", ("stable",)))
const EXPERIMENTAL_POTTSTOOLKIT_BINDINGS = union!(
    classified_bindings(PottsToolkit,
        inventory_names("PottsToolkit", ("limited", "experimental"))),
    classified_bindings(PottsToolkit,
        get(phase14_inventory["modules"], "PottsToolkit", String[])),
)
const STABLE_COREPOTTS_BINDINGS = classified_bindings(
    CorePotts, inventory_names("CorePotts", ("stable",)))
const EXPERIMENTAL_COREPOTTS_BINDINGS = union!(
    classified_bindings(CorePotts,
        inventory_names("CorePotts", ("limited", "experimental"))),
    classified_bindings(CorePotts,
        get(phase14_inventory["modules"], "CorePotts", String[])),
)
const STABLE_MAKIEPOTTS_BINDINGS = classified_bindings(
    MakiePotts, vcat(
        makie_inventory["stable_exports"], makie_inventory["limited_exports"]))
const EXPERIMENTAL_MAKIEPOTTS_BINDINGS = classified_bindings(
    MakiePotts, makie_inventory["experimental_exports"])

is_stable_pottstoolkit(binding) = binding in STABLE_POTTSTOOLKIT_BINDINGS
is_experimental_pottstoolkit(binding) =
    binding in EXPERIMENTAL_POTTSTOOLKIT_BINDINGS
is_stable_corepotts(binding) = binding in STABLE_COREPOTTS_BINDINGS
is_experimental_corepotts(binding) = binding in EXPERIMENTAL_COREPOTTS_BINDINGS
is_stable_makiepotts(binding) = binding in STABLE_MAKIEPOTTS_BINDINGS
is_experimental_makiepotts(binding) = binding in EXPERIMENTAL_MAKIEPOTTS_BINDINGS

makedocs(
    sitename = "Potts.jl",
    authors = "Praneeth Merugu",
    modules = [CorePotts, PottsToolkit, MakiePotts],
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://praneethmerugu.github.io/Potts.jl/",
        repolink = "https://github.com/PraneethMerugu/Potts.jl",
        edit_link = "main",
        size_threshold = nothing,
        size_threshold_warn = nothing,
        # Native Makie SVG output is intentionally larger than Documenter's 8 KiB
        # example default. Keep it vector-sharp instead of warning and falling back
        # to a raster representation.
        example_size_threshold = 512 * 2^10,
        assets = ["assets/docs.css"],
    ),
    doctest = true,
    linkcheck = get(ENV, "POTTS_DOCS_LINKCHECK", "false") == "true",
    warnonly = false,
    # Only pages in the curated manual execute. Generated media and historical drafts are not
    # documentation inputs merely because they remain in the repository.
    pagesonly = true,
    # Stability is assigned by the curated API inventories and guarantee metadata. Export status
    # alone is not a support promise, so a broad exported-name check enforces the wrong boundary.
    checkdocs = :none,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Learn" => [
            "Install and verify" => "learn/install-and-verify.md",
            "Cellular Potts concepts" => "learn/cellular-potts-concepts.md",
            "First simulation" => "learn/first-simulation.md",
            "Compose a biological model" => "learn/build-model.md",
            "Domains and initialization" => "learn/domains-and-initialization.md",
            "Adhesion and mechanics" => "learn/adhesion-and-mechanics.md",
            "Fields and chemotaxis" => "learn/fields-and-chemotaxis.md",
            "Rules and lifecycle" => "learn/rules-and-lifecycle.md",
            "Algorithms and guarantees" => "learn/algorithms-and-guarantees.md",
            "Observe and analyze" => "learn/observe-and-analyze.md",
            "Checkpoint and reproduce" => "learn/checkpoint-and-reproduce.md",
            "Visualize and export" => "learn/visualize-and-export.md",
            "Backends and performance" => "learn/backends-and-performance.md",
            "Research workflow" => "learn/research-workflow.md",
        ],
        "Examples" => [
            "Example gallery" => "examples/index.md",
            "Relaxing Cell" => "examples/relaxing-cell.md",
            "Two Populations Sort" => "examples/differential-adhesion.md",
            "Follow the Gradient" => "examples/chemotaxis.md",
            "Grow, Divide, Retire" => "examples/growth-and-division.md",
            "Elongated Network" => "examples/elongated-network.md",
            "Fluctuating Droplet" => "examples/fluctuating-droplet.md",
            "Boundaries and Obstacles" => "examples/boundaries-and-obstacles.md",
            "Same Model in 2D and 3D" => "examples/same-model-2d-3d.md",
            "Stop and Resume" => "examples/stop-and-resume.md",
            "Reproducible Ensemble" => "examples/reproducible-ensemble.md",
        ],
        "Published Models" => "published-models/index.md",
        "Concepts and Guarantees" => [
            "Architecture" => "concepts/architecture.md",
            "Execution model" => "concepts/execution.md",
            "Observation boundary" => "concepts/observation.md",
            "Reproducibility and persistence" => "concepts/reproducibility.md",
            "Scientific guarantees" => "concepts/guarantees.md",
            "Runtime and Phase 16 boundary" => "concepts/runtime-boundary.md",
            "Capability status" => "concepts/capability-status.md",
            "Troubleshooting" => "concepts/troubleshooting.md",
            "Glossary" => "concepts/glossary.md",
            "Version and migration guide" => "concepts/version-and-migration.md",
        ],
        "API" => [
            "PottsToolkit" => "api/pottstoolkit.md",
            "CorePotts" => "api/corepotts.md",
            "MakiePotts" => "api/makiepotts.md",
            "Extension author reference" => "api/extensions.md",
            "Experimental API" => "api/experimental.md",
        ],
    ],
)

if get(ENV, "POTTS_DEPLOY_DOCS", "false") == "true"
    get(ENV, "GITHUB_ACTIONS", "false") == "true" ||
        error("Documentation deployment is only permitted inside GitHub Actions")
    get(ENV, "GITHUB_EVENT_NAME", "") == "pull_request" &&
        error("Documentation deployment is forbidden for pull requests")
    deploydocs(
        repo = "github.com/PraneethMerugu/Potts.jl.git",
        devbranch = "main",
        push_preview = false,
    )
end
