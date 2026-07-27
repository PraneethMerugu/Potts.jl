using Documenter
using CorePotts
using MakiePotts
using PottsToolkit

makedocs(
    sitename = "Potts.jl",
    authors = "Praneeth Merugu",
    modules = [CorePotts, PottsToolkit, MakiePotts],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://praneethmerugu.github.io/Potts.jl/",
        repolink = "https://github.com/PraneethMerugu/Potts.jl",
        size_threshold = nothing,
        size_threshold_warn = nothing,
    ),
    doctest = true,
    warnonly = false,
    # Phase 14 owns the model-driven capability audit, manual documentation rebuild, published
    # models, and satellite migration. Phase 13 builds only the frozen paper-core pages listed
    # below, so unlisted historical drafts must not execute as if they were already supported.
    pagesonly = true,
    # Phase 13 freezes the curated inventory recorded in its owner packet. Export status alone is
    # not a stability claim, so Documenter's broad export check would enforce the wrong boundary.
    checkdocs = :none,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Scientific Contracts" => "corepotts/contracts.md",
        "CorePotts API" => "corepotts/api.md",
        "PottsToolkit API" => "pottstoolkit/api.md",
        "MakiePotts" => "makiepotts.md",
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
