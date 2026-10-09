# Build the documentation offline: `julia --project=docs docs/make.jl`.
#
# The "Paper models" section (D-185) has one page per paper, after the status page:
#
# - Default build: the model pages rendered from the Literate scripts in `docs/models/` (see
#   `docs/models/render.jl`), at `models/<name>/`.
# - `POTTS_DOCS_PUBLISHED=true`: the paper reproductions in
#   `lib/PottsModels/reproductions/*.jl` are rendered by Literate into `docs/src/published/`
#   (generated, gitignored) and replace the model page of their paper. The old URL
#   `models/<name>/` becomes a short page linking to `published/<NN_name>/`. A model with no
#   reproduction page (Wortel Act) keeps its model page in both builds.
#
# Either way the heading of each paper's page carries the `@id model-<name>`, so
# `[…](@ref model-merks)` reaches the paper's page in both builds.
# `POTTS_FULL_REPRODUCTION=true` makes the reproduction pages run their full-size ensembles.
using Documenter, Literate, TOML
using Potts, CorePotts, PottsModels, MakiePotts

const SRC = joinpath(@__DIR__, "src")
const REPRODUCTIONS = joinpath(dirname(@__DIR__), "lib", "PottsModels", "reproductions")
const PUBLISHED = joinpath(SRC, "published")
const MODELS = joinpath(SRC, "models")
const WITH_PUBLISHED = get(ENV, "POTTS_DOCS_PUBLISHED", "false") == "true"

# One page per paper, in the order of the status page: the reproduction page's stem, the
# model page it replaces (`docs/models/<name>.jl`, `@id model-<name>`), and its title in
# the navigation. A reproduction script not listed here is added after these, under its
# own heading. A paper with no model page (no `docs/models/<name>.jl`) gets no short page at
# `models/<name>/`, and appears only in the published build.
const PAPER_PAGES = [
    ("01_merks", "merks", "Vasculogenesis (Merks et al. 2006, 2008)"),
    ("04_foam", "foam", "Foam rheology (Jiang et al. 1999)"),            # no model page (`docs/models/foam.jl`)
    ("09_cell_sorting", "graner_glazier", "Cell sorting (Graner & Glazier 1992)"),
    ("10_akeeb", "akeeb", "Leader–follower invasion (Akeeb, Marcus & Jiang 2026)"),
    ("15_openvt_monolayer", "openvt", "Growing monolayer (OpenVT benchmark)"),
]
# model pages that are not reproductions of a paper's results
const NOT_REPRODUCTIONS = [("wortel_act", "Actin-driven migration (not a reproduction)")]

_model_id(name) = "model-" * replace(name, "_" => "-")

# Give a reproduction page's first heading the `@id` of the model page it replaces, unless
# the heading already has an `@id`. Returns the script's text and whether it got the id.
function _with_model_id(src, name)
    lines = String.(split(src, '\n'))
    i = findfirst(l -> startswith(l, "# # "), lines)
    (i === nothing || occursin("(@id ", lines[i])) && return src, occursin("(@id $(_model_id(name)))", src)
    lines[i] = "# # [" * strip(lines[i][5:end]) * "](@id $(_model_id(name)))"
    return join(lines, '\n'), true
end

# stale generated pages would be built even when they are not in `pages`
for f in (isdir(PUBLISHED) ? readdir(PUBLISHED) : String[])
    endswith(f, ".md") && rm(joinpath(PUBLISHED, f))
end
published = String[]       # every rendered reproduction page, `published/<stem>.md`
has_model_id = Set{String}()   # reproduction stems whose heading carries `model-<name>`
if WITH_PUBLISHED
    for f in sort(readdir(REPRODUCTIONS))
        endswith(f, ".jl") || continue
        stem = splitext(f)[1]
        k = findfirst(p -> p[1] == stem, PAPER_PAGES)
        Literate.markdown(joinpath(REPRODUCTIONS, f), PUBLISHED; documenter = true, credit = false,
            preprocess = s -> begin
                k === nothing && return s
                s, ok = _with_model_id(s, PAPER_PAGES[k][2])
                ok && push!(has_model_id, stem)
                s
            end)
        push!(published, joinpath("published", stem * ".md"))
    end
    # the old index page of the "Published models" section, now a page linking onward
    write(joinpath(PUBLISHED, "index.md"), """
    # [Published models (moved)](@id published-models)

    !!! note "This section has moved"
        The reproduction pages are now in the **Paper models** section, one page per paper,
        listed on [Paper models: status](../status.md). Their addresses are unchanged.
    """)
end

# The model pages (`docs/models/render.jl`): a model whose reproduction page is built gets a
# short page at its old URL instead (`render_model_stub`), linking to the reproduction page.
include(joinpath(@__DIR__, "models", "render.jl"))
paper_pages = Any[]
let built = Set(basename.(published))
    rendered = String[]
    for (stem, name, title) in PAPER_PAGES
        has_model_page = isfile(joinpath(@__DIR__, "models", name * ".jl"))
        if stem * ".md" in built && !has_model_page
            push!(paper_pages, title => joinpath("published", stem * ".md"))
        elseif !has_model_page
            continue
        elseif stem * ".md" in built
            render_model_stub(name, joinpath("published", stem * ".md"), title;
                id = stem in has_model_id ? nothing : _model_id(name))
            push!(paper_pages, title => joinpath("published", stem * ".md"))
        else
            append!(rendered, render_models(; names = [name]))
            push!(paper_pages, title => joinpath("models", name * ".md"))
        end
    end
    # reproduction pages with no model page of their own, under their own headings
    for p in published
        any(q -> q[1] * ".md" == basename(p), PAPER_PAGES) || push!(paper_pages, p)
    end
    for (name, title) in NOT_REPRODUCTIONS
        render_models(; names = [name])
        push!(paper_pages, title => joinpath("models", name * ".md"))
    end
end

# Names that a model or reproduction page documents with an `@docs` block; the API page
# leaves them out, since Documenter allows each docstring on one page only. A name that no
# page documents (e.g. on a moved model's short page) is listed on the API page.
const MODEL_PAGE_NAMES = let names = Set{Symbol}()
    for d in (MODELS, PUBLISHED), f in (isdir(d) ? readdir(d; join = true) : String[])
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

# `models/index.md` and `published/index.md` (the old section index pages) are built at their
# old URLs but are not in the navigation.
pages = Any[
    "Home" => "index.md",
    "Getting started" => "getting_started.md",
    "Tutorials" => tutorials,
    "Paper models" => Any["Paper models: status" => STATUS_PAGE; paper_pages],
    "Workshop" => "workshop.md",
    "Manual" => manual,
]
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
