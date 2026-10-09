# Renders the model pages of the "Paper models" section: every Literate script `docs/models/<name>.jl` becomes
# `docs/src/models/<name>.md` (generated, gitignored), executed later by Documenter.
#
#     include(joinpath(@__DIR__, "models", "render.jl"))     # from docs/make.jl
#     model_pages = render_models()     # ["models/graner_glazier.md", …], relative to docs/src
#     pages = [..., "Paper models" => [...; model_pages], ...]
#
# When the reproduction pages are built (`POTTS_DOCS_PUBLISHED=true`), a model whose paper has
# a reproduction page is not rendered; `render_model_stub` writes a short page at its old URL
# that links to the reproduction page (D-185).
#
# `docs/src/models/index.md` (hand-written, committed) is a short page at the old URL of the
# former Models section, linking to the pages. Each script builds one model,
# whose finished `@potts_model` lives in `docs/models/src/<name>_model.jl`; that file is
# also included by lib/PottsModels/test/tutorial_models.jl, which checks that it compiles to
# the same problem as the shipped constructor. Two placeholders in the scripts read it:
#
# - a markdown line `# <<fragment NAME>>` becomes a (non-executed) code listing of the lines
#   after the marker `#> NAME` in the model file, up to the next `#>` or `#<` marker;
# - a markdown line `# <<model>>` becomes an executed code block with the whole model file,
#   without its header comment and markers;
# - a markdown line `# <<paper_run>>` becomes the video `docs/src/assets/paper_runs/<name>.mp4`
#   (made outside the build) with a caption read from its sidecar `<name>.toml`, or a note
#   when the video is not there yet. Pages are rendered at build time, so the caption
#   follows the committed sidecar.
#
# The fragments are cut from the file that runs, so the listings cannot drift from the model.
using Literate: Literate
using TOML: TOML

const MODEL_PAGES = ["graner_glazier", "merks", "akeeb", "wortel_act", "openvt"]
const MODELS_DIR = @__DIR__
const PAPER_RUNS = joinpath(dirname(MODELS_DIR), "src", "assets", "paper_runs")

_is_marker(line) = startswith(lstrip(line), "#>") || startswith(lstrip(line), "#<")

# the model file without the header comment (the lines before the first code line)
function _model_lines(name)
    lines = readlines(joinpath(MODELS_DIR, "src", name * "_model.jl"))
    first_code = findfirst(l -> !isempty(strip(l)) && !startswith(lstrip(l), "#"), lines)
    return lines[first_code:end]
end

function _fragment(lines, fragment, name)
    start = findfirst(l -> strip(l) == "#> " * fragment, lines)
    start === nothing && error("docs/models: no fragment `$fragment` in $(name)_model.jl")
    stop = findnext(_is_marker, lines, start + 1)
    body = lines[(start + 1):((stop === nothing ? length(lines) + 1 : stop) - 1)]
    indent = minimum(l -> length(l) - length(lstrip(l)), filter(!isempty ∘ strip, body))
    return [isempty(strip(l)) ? "" : l[(indent + 1):end] for l in body]
end

# the paper-run video of each page (file stem in docs/src/assets/paper_runs/)
const PAPER_RUN_STEMS = Dict("graner_glazier" => "graner_glazier", "merks" => "merks_vasculogenesis",
    "akeeb" => "akeeb_invasion", "wortel_act" => "wortel_act", "openvt" => "openvt_monolayer")

# the sidecar's one-line `caption` entry (the other entries are provenance, not for readers)
_caption(meta) = replace(strip(get(meta, "caption", "")), r"\s*\n\s*" => " ")

function _paper_run(name)
    stem = get(PAPER_RUN_STEMS, name, name)
    video, sidecar = joinpath.(PAPER_RUNS, stem .* (".mp4", ".toml"))
    if isfile(video)
        caption = isfile(sidecar) ? _caption(TOML.parsefile(sidecar)) : ""
        # raw HTML, not Markdown emphasis: `A*(0)` and `J_cc` would otherwise read as emphasis
        html = replace(caption, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "*" => "&#42;", "_" => "&#95;")
        lines = ["```@raw html",
            "<video src=\"../../assets/paper_runs/$stem.mp4\" controls loop muted playsinline width=\"560\"></video>",
            isempty(caption) ? "" : "<p><em>$html</em></p>",
            "```"]
    else
        lines = ["!!! note \"Paper run\"", "    The video of the paper run is being generated and will appear here."]
    end
    return [isempty(l) ? "#" : "# " * l for l in lines]
end

function _expand(content, name)
    lines = _model_lines(name)
    out = String[]
    for line in split(content, '\n')
        m = match(r"^# <<fragment (\S+)>>\s*$", line)
        if m !== nothing
            push!(out, "# ```julia")
            append!(out, [isempty(l) ? "#" : "# " * l for l in _fragment(lines, m[1], name)])
            push!(out, "# ```")
        elseif strip(line) == "# <<paper_run>>"
            append!(out, _paper_run(name))
        elseif strip(line) == "# <<model>>"
            append!(out, filter(!_is_marker, lines))
            push!(out, "nothing #hide")
        else
            push!(out, line)
        end
    end
    return join(out, '\n')
end

"""
    render_models(; outdir = docs/src/models, names = MODEL_PAGES) -> Vector{String}

Render the model tutorials `names` to Markdown in `outdir` and return their paths
relative to `docs/src` (without the hand-written `models/index.md`), in section order.
"""
function render_models(; outdir = joinpath(dirname(MODELS_DIR), "src", "models"), names = MODEL_PAGES)
    pages = String[]
    for name in names
        Literate.markdown(joinpath(MODELS_DIR, name * ".jl"), outdir; documenter = true, credit = false,
            preprocess = s -> _expand(s, name))
        push!(pages, joinpath("models", name * ".md"))
    end
    return pages
end

"""
    render_model_stub(name, target, title; id = nothing, outdir = docs/src/models) -> String

Write `docs/src/models/<name>.md` as a short page that links to `target` (a page path
relative to `docs/src`, e.g. `"published/01_merks.md"`), for a Models page whose content
moved to its paper's page (D-185). Its URL, `models/<name>/`, keeps working. `id` is the
page's `@id` (normally `nothing`: the moved page carries `model-<name>`). The stub has no
`@docs` block. Returns the stub's path relative to `docs/src`.
"""
function render_model_stub(name, target, title; id = nothing,
                           outdir = joinpath(dirname(MODELS_DIR), "src", "models"))
    heading = id === nothing ? "# $title (moved)" : "# [$title (moved)](@id $id)"
    write(joinpath(outdir, name * ".md"), """
    $heading

    !!! note "This page has moved"
        This model is now documented on its paper's page, **[$title]($(relpath(target, "models")))**,
        which builds the model, runs it and compares it with the paper. All paper models are
        listed on [Paper models: status](../status.md).
    """)
    return joinpath("models", name * ".md")
end
