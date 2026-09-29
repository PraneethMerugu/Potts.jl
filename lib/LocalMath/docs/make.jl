using Documenter
using LocalMath

pages = [
    "Home" => "index.md",
    "Quick start" => "learn/localmath-quickstart.md",
    "Relations and storage" => "learn/localmath-relations.md",
    "Scientific recipes" => "learn/localmath-recipes.md",
    "Troubleshooting" => "learn/localmath-troubleshooting.md",
    "Domain compilers" => "learn/localmath-domain-compiler.md",
    "API" => "api/localmath.md",
]

function documented_pages(items)
    paths = String[]
    for item in items
        value = item isa Pair ? last(item) : item
        if value isa AbstractString
            push!(paths, String(value))
        else
            append!(paths, documented_pages(value))
        end
    end
    return paths
end

source_root = joinpath(@__DIR__, "src")
source_pages = sort!(String[
    relpath(joinpath(root, file), source_root)
    for (root, _, files) in walkdir(source_root)
    for file in files if endswith(file, ".md")
])
navigation_pages = sort!(documented_pages(pages))
source_pages == navigation_pages || error(
    "Documenter navigation must own every Markdown page; source=$(source_pages), " *
    "navigation=$(navigation_pages)",
)

makedocs(
    sitename = "LocalMath.jl",
    authors = "Praneeth Merugu",
    modules = [LocalMath],
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://praneethmerugu.github.io/LocalMath.jl/",
        repolink = "https://github.com/PraneethMerugu/LocalMath.jl",
        edit_link = "main",
        size_threshold = nothing,
        size_threshold_warn = nothing,
    ),
    doctest = true,
    warnonly = false,
    pagesonly = true,
    checkdocs = :exports,
    remotes = nothing,
    pages = pages,
)

if get(ENV, "LOCALMATH_DEPLOY_DOCS", "false") == "true"
    get(ENV, "GITHUB_ACTIONS", "false") == "true" ||
        error("Documentation deployment is only permitted inside GitHub Actions")
    get(ENV, "GITHUB_EVENT_NAME", "") == "pull_request" &&
        error("Documentation deployment is forbidden for pull requests")
    deploydocs(
        repo = "github.com/PraneethMerugu/LocalMath.jl.git",
        devbranch = "main",
        push_preview = false,
    )
end
