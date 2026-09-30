# Build the documentation offline: `julia --project=docs docs/make.jl`.
# Every `lib/PottsModels/reproductions/*.jl` is rendered by Literate into
# `docs/src/published/` (generated, gitignored) and executed by Documenter.
# `POTTS_FULL_REPRODUCTION=true` makes the tutorials run their full-size ensembles.
using Documenter, Literate
using Potts, CorePotts, PottsModels

const REPRODUCTIONS = joinpath(dirname(@__DIR__), "lib", "PottsModels", "reproductions")
const PUBLISHED = joinpath(@__DIR__, "src", "published")

for f in readdir(PUBLISHED)
    endswith(f, ".md") && rm(joinpath(PUBLISHED, f))
end
published = String[]
for f in sort(readdir(REPRODUCTIONS))
    endswith(f, ".jl") || continue
    Literate.markdown(joinpath(REPRODUCTIONS, f), PUBLISHED; documenter = true, credit = false)
    push!(published, joinpath("published", splitext(f)[1] * ".md"))
end

# the section's index page lists the generated pages
write(joinpath(PUBLISHED, "index.md"), """
# [Published models](@id published-models)

Each page reproduces one paper from the public constructor in `PottsModels`. The pages
are generated from the Literate scripts in `lib/PottsModels/reproductions/`. The docs
build runs a reduced ensemble; `POTTS_FULL_REPRODUCTION=true` runs the full one.

```@contents
Pages = $(repr([basename(p) for p in published]))
Depth = 1
```
""")

makedocs(;
    sitename = "Potts.jl",
    modules = [Potts, CorePotts, PottsModels],
    remotes = nothing,
    format = Documenter.HTML(; prettyurls = true, edit_link = nothing, repolink = nothing,
        size_threshold = nothing, size_threshold_warn = nothing),
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Learn" => "learn.md",
        "Published models" => ["published/index.md"; published],
        "API" => "api.md",
    ])
