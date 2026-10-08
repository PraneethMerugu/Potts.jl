# Build the documentation offline: `julia --project=docs docs/make.jl`.
#
# The Models pages are rendered from the Literate scripts in `docs/models/` (see
# `docs/models/render.jl`). The paper reproductions in `lib/PottsModels/reproductions/*.jl`
# are not part of the site yet; `POTTS_DOCS_PUBLISHED=true` renders them by Literate into
# `docs/src/published/` (generated, gitignored) and adds a "Published models" section.
# `POTTS_FULL_REPRODUCTION=true` makes those pages run their full-size ensembles.
using Documenter, Literate, TOML
using Potts, CorePotts, PottsModels, MakiePotts

const SRC = joinpath(@__DIR__, "src")
const REPRODUCTIONS = joinpath(dirname(@__DIR__), "lib", "PottsModels", "reproductions")
const PUBLISHED = joinpath(SRC, "published")
const MODELS = joinpath(SRC, "models")
const WITH_PUBLISHED = get(ENV, "POTTS_DOCS_PUBLISHED", "false") == "true"

# stale generated pages would be built even when they are not in `pages`
for f in (isdir(PUBLISHED) ? readdir(PUBLISHED) : String[])
    endswith(f, ".md") && rm(joinpath(PUBLISHED, f))
end
published = String[]
if WITH_PUBLISHED
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
end

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

# Names that a Models page documents with an `@docs` block; the API page leaves them out,
# since Documenter allows each docstring on one page only.
const MODEL_PAGE_NAMES = let names = Set{Symbol}()
    for f in (isdir(MODELS) ? readdir(MODELS; join = true) : String[])
        endswith(f, ".md") || continue
        for m in eachmatch(r"```@docs\n(.*?)```"s, read(f, String)), l in split(m[1], '\n')
            l = strip(l)
            isempty(l) || push!(names, Symbol(l))
        end
    end
    names
end
on_model_page(x) = x isa Union{Function, Type} && nameof(x) in MODEL_PAGE_NAMES

const PAPER_RUNS = joinpath(SRC, "assets", "paper_runs")

# The "Paper models: status" page, generated from the committed verdict records at build
# time (`docs/status/render.jl`; the page itself is gitignored).
include(joinpath(@__DIR__, "status", "render.jl"))
const STATUS_PAGE = render_status(; published = WITH_PUBLISHED)

"""
    paper_run(stem, prefix = "")

HTML for the committed full paper run of a published model: the video
`docs/src/assets/paper_runs/<stem>.mp4` with a caption from its sidecar `<stem>.toml` (the
`caption` entry; the other entries are provenance). `prefix` is the path from the
page's built location to the build root (`""` for `index.md`, `"../"` for a top-level page,
`"../../"` for a page in a section folder, with pretty URLs). A missing video gives a short
note instead. Used by the tutorials as `Main.paper_run(…) # hide` in an `@example` block.
"""
function paper_run(stem::AbstractString, prefix::AbstractString = "")
    video = joinpath(PAPER_RUNS, stem * ".mp4")
    isfile(video) || return Base.Docs.HTML("<p><em>The full paper run of this model is being generated " *
                                           "and will appear here.</em></p>")
    side = joinpath(PAPER_RUNS, stem * ".toml")
    caption = isfile(side) ? strip(get(TOML.parsefile(side), "caption", "")) : ""
    esc_html(s) = replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "*" => "&#42;", "_" => "&#95;")  # `*`/`_` would read as emphasis
    return Base.Docs.HTML("""<figure><video src="$(prefix)assets/paper_runs/$stem.mp4" controls loop muted playsinline width="480"></video>""" *
                          "<figcaption>$(esc_html(caption))</figcaption></figure>")
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
    "manual/algorithms.md",
    "manual/indexing.md",
    "manual/observables.md",
    "manual/analysis.md",
    "manual/callbacks.md",
    "manual/layouts.md",
    "manual/plotting.md",
]

pages = Any[
    "Home" => "index.md",
    "Paper models: status" => STATUS_PAGE,
    "Getting started" => "getting_started.md",
    "Tutorials" => tutorials,
]
isempty(models) || push!(pages, "Models" => models)
push!(pages, "Workshop" => "workshop.md", "Manual" => manual)
WITH_PUBLISHED && push!(pages, "Published models" => ["published/index.md"; published])
append!(pages, Any[
    "Coming from CompuCell3D or Morpheus" => "coming_from.md",
    "FAQ and common errors" => "faq.md",
    "Relation to ModelingToolkit" => "modelingtoolkit.md",
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
