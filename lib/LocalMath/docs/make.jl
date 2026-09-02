using Documenter
using LocalMath

makedocs(
    sitename = "LocalMath.jl",
    authors = "Praneeth Merugu",
    modules = [LocalMath],
    doctest = true,
    warnonly = false,
    pagesonly = true,
    checkdocs = :exports,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Quick start" => "learn/localmath-quickstart.md",
        "Relations and storage" => "learn/localmath-relations.md",
        "Scientific recipes" => "learn/localmath-recipes.md",
        "Troubleshooting" => "learn/localmath-troubleshooting.md",
        "Domain compilers" => "learn/localmath-domain-compiler.md",
        "API" => "api/localmath.md",
    ],
)
