# Build only the model pages of the Paper models section, for checking them quickly:
#     julia --project=docs docs/make_models_preview.jl [page ...]
# e.g. `… make_models_preview.jl merks` builds the index and the Merks page only.
# Output: docs/build/models-preview/ (open models/index.html there). Pretty URLs as in
# docs/make.jl: each page is <page>/index.html, next to its movies. The full site is built by
# docs/make.jl, which includes docs/models/render.jl the same way.
using Documenter
using Potts, CorePotts, PottsModels

include(joinpath(@__DIR__, "models", "render.jl"))
model_pages = isempty(ARGS) ? render_models() : render_models(; names = ARGS)

makedocs(;
    sitename = "Potts.jl — Models (preview)",
    build = joinpath(@__DIR__, "build", "models-preview"),
    modules = [PottsModels],
    remotes = nothing,
    format = Documenter.HTML(; prettyurls = true, edit_link = nothing, repolink = nothing,
        size_threshold = nothing, size_threshold_warn = nothing),
    checkdocs = :none,
    pagesonly = true,
    # the links to the status and reproduction pages point outside this preview
    warnonly = [:cross_references],
    pages = ["Models" => ["models/index.md"; model_pages]])
