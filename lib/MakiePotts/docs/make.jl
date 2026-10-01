using Documenter
using MakiePotts

include(joinpath(dirname(@__DIR__), "dev", "ci_telemetry.jl"))

makedocs(
    sitename = "MakiePotts.jl",
    authors = "Praneeth Merugu",
    modules = [MakiePotts],
    doctest = true,
    warnonly = false,
    pagesonly = true,
    checkdocs = :exports,
    remotes = nothing,
    format = Documenter.HTML(
        repolink = "https://github.com/PraneethMerugu/MakiePotts.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Saved-state channels" => "saved_state_channels.md",
        "API" => "api/makiepotts.md",
    ],
)
