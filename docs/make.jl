using Documenter
using CorePotts
using PottsToolkit

makedocs(
    sitename = "Potts.jl",
    authors = "Praneeth Merugu",
    modules = [CorePotts, PottsToolkit],
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
    # Stability is assigned by the curated API inventories and guarantee metadata. Export status
    # alone is not a support promise, so a broad exported-name check enforces the wrong boundary.
    checkdocs = :none,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Hardening status" => [
            "Architecture" => "concepts/architecture.md",
            "Runtime boundary" => "concepts/runtime-boundary.md",
            "Capability status" => "concepts/capability-status.md",
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
