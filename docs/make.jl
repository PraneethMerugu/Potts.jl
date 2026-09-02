using Documenter
using Potts

makedocs(
    sitename = "Potts.jl",
    authors = "Praneeth Merugu",
    modules = [Potts],
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://praneethmerugu.github.io/Potts.jl/",
        repolink = "https://github.com/PraneethMerugu/Potts.jl",
        edit_link = "main",
        size_threshold = nothing,
        size_threshold_warn = nothing,
        assets = ["assets/docs.css"],
    ),
    doctest = true,
    linkcheck = get(ENV, "POTTS_DOCS_LINKCHECK", "false") == "true",
    warnonly = false,
    # Only pages in the curated manual execute. Generated media and historical drafts are not
    # documentation inputs merely because they remain in the repository.
    pagesonly = true,
    # Exported constructors and operations require attached help. Qualified-public
    # extension SPI is inventoried separately by package tests and the extension manual.
    checkdocs = :exports,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Learn" => [
            "Author and compose" => "learn/authoring.md",
            "Initialize and execute" => "learn/execution.md",
            "Lifecycle and relationships" => "learn/state-lifecycle.md",
            "Native MTK components" => "learn/native-components.md",
            "Fields, batching, and ensembles" => "learn/fields-and-ensembles.md",
            "Observe, checkpoint, and reproduce" => "learn/reproducibility.md",
        ],
        "Published-model integration" => [
            "Wortel 2021" => "published-models/wortel-2021.md",
            "Merks 2006" => "published-models/merks-2006.md",
            "OpenVT monolayer" => "published-models/openvt-monolayer.md",
        ],
        "Concepts and support" => [
            "Architecture" => "concepts/architecture.md",
            "Runtime boundary" => "concepts/runtime-boundary.md",
            "Capability status" => "concepts/capability-status.md",
            "Extension boundary" => "concepts/extension-boundary.md",
        ],
        "API" => [
            "Potts" => "api/potts.md",
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
