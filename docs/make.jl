# Build the documentation offline: `julia --project=docs docs/make.jl`.
# Every `lib/PottsModels/reproductions/*.jl` is rendered by Literate into
# `docs/src/published/` (generated, gitignored) and executed by Documenter.
# `POTTS_FULL_REPRODUCTION=true` makes the tutorials run their full-size ensembles.
using Documenter, Literate, TOML
using Potts, CorePotts, PottsModels, MakiePotts

const SRC = joinpath(@__DIR__, "src")
const REPRODUCTIONS = joinpath(dirname(@__DIR__), "lib", "PottsModels", "reproductions")
const PUBLISHED = joinpath(SRC, "published")
const MODELS = joinpath(SRC, "models")

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

# The "Models" section: rendered by `docs/models/render.jl` when it exists (its pages go to
# `docs/src/models/`); otherwise `models/index.md` and every other `models/*.md` found at
# build time. Neither: no section.
models = if isfile(joinpath(@__DIR__, "models", "render.jl"))
    include(joinpath(@__DIR__, "models", "render.jl"))
    ["models/index.md"; render_models()]
elseif isdir(MODELS)
    rest = sort([joinpath("models", f) for f in readdir(MODELS) if endswith(f, ".md") && f != "index.md"])
    isfile(joinpath(MODELS, "index.md")) ? ["models/index.md"; rest] : rest
else
    String[]
end

"""
    model_links(pairs...)

Markdown for a "see also" line linking the per-model pages, used by the tutorials through
`@eval` blocks: each `file => (id, text)` becomes `[text](@ref id)` when
`docs/src/models/file` exists, and plain `text` otherwise (so the tutorials build with or
without the Models section).
"""
function model_links(pairs::Pair...)
    items = map(pairs) do (file, (id, text))
        isfile(joinpath(MODELS, file)) ? "[`$text`](@ref $id)" : "`$text`"
    end
    return join(items, ", ")
end

const PAPER_RUNS = joinpath(SRC, "assets", "paper_runs")

"""
    paper_run(stem, prefix = "")

HTML for the committed full paper run of a published model: the video
`docs/src/assets/paper_runs/<stem>.mp4` with a caption from its sidecar `<stem>.toml` (the
`caption` entry, else its scalar entries as `key = value`). `prefix` is the path from the
page's built location to the build root (`""` for `index.md`, `"../"` for a top-level page,
`"../../"` for a page in a section folder, with pretty URLs). A missing video gives a short
note instead. Used by the tutorials as `Main.paper_run(…) # hide` in an `@example` block.
"""
function paper_run(stem::AbstractString, prefix::AbstractString = "")
    video = joinpath(PAPER_RUNS, stem * ".mp4")
    isfile(video) || return Base.Docs.HTML("<p><em>The full paper run of this model is being generated " *
                                           "and will appear here.</em></p>")
    side = joinpath(PAPER_RUNS, stem * ".toml")
    caption = ""
    if isfile(side)
        meta = TOML.parsefile(side)
        caption = get(meta, "caption", "")
        if isempty(caption)
            caption = join(("$k = $v" for (k, v) in sort!(collect(meta); by = first)
                            if v isa Union{AbstractString, Number, Bool}), "; ")
        end
    end
    esc_html(s) = replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
    return Base.Docs.HTML("""<figure><video src="$(prefix)assets/paper_runs/$stem.mp4" controls loop muted playsinline width="480"></video>""" *
                          "<figcaption>Full paper run. $(esc_html(caption))</figcaption></figure>")
end

tutorials = [
    "tutorials/energies.md",
    "tutorials/chemotaxis.md",
    "tutorials/growth.md",
    "tutorials/layouts.md",
    "tutorials/cell_odes.md",
    "tutorials/links.md",
    "tutorials/scans.md",
    "tutorials/gpu.md",
]

manual = [
    "manual/models.md",
    "manual/kinds.md",
    "manual/parameters.md",
    "manual/variables.md",
    "manual/lattice.md",
    "manual/energy.md",
    "manual/drive.md",
    "manual/constraint.md",
    "manual/updates.md",
    "manual/equations.md",
    "manual/lifecycle.md",
    "manual/relationships.md",
    "manual/sweep.md",
    "manual/problems.md",
    "manual/indexing.md",
    "manual/observables.md",
    "manual/callbacks.md",
    "manual/layouts.md",
    "manual/plotting.md",
]

pages = Any[
    "Home" => "index.md",
    "Getting started" => "getting_started.md",
    "Tutorials" => tutorials,
    "Workshop" => "workshop.md",
    "Manual" => manual,
]
isempty(models) || push!(pages, "Models" => models)
append!(pages, Any[
    "Published models" => ["published/index.md"; published],
    "Coming from CompuCell3D or Morpheus" => "coming_from.md",
    "FAQ and common errors" => "faq.md",
    "API" => "api.md",
    "Roadmap" => "roadmap.md",
])

makedocs(;
    sitename = "Potts.jl",
    modules = [Potts, CorePotts, PottsModels, PottsModels.Analysis, MakiePotts],
    remotes = nothing,
    format = Documenter.HTML(; prettyurls = true, edit_link = nothing, repolink = nothing,
        size_threshold = nothing, size_threshold_warn = nothing),
    checkdocs = :exports,
    pages)
