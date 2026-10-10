# Renders the "Paper models: status" page, `docs/src/status.md` (generated, gitignored),
# at docs build time, so its counts never go stale.
#
#     include(joinpath(@__DIR__, "status", "render.jl"))     # from docs/make.jl
#     render_status(; published = WITH_PUBLISHED)           # -> "status.md"
#
# - The per-model rows (status, open deviations, links) come from `docs/status/models.toml`.
# - The PASS / FAIL / PARKED counts are computed from the committed verdict TSVs,
#   `lib/PottsModels/reproductions/data/<NN>/<record>/verdicts*.tsv` (D-146).
# - The remaining build order marks each ROADMAP item open or done from `docs/design/ROADMAP.md`.
#
# Counting rules (stated on the page):
# - the `result` column is read; PASS, FAIL and PARKED are counted, every other value
#   (`info: …`, `reported`) is information;
# - a negative-control row (case `control`, or a band saying "control: must FAIL") is not a
#   verdict on the model; the records table shows how many control rows fail, of how many;
# - a summary row ("… (all rows)") restates other rows and is not counted, nor is a per-point
#   line (`check` "point …") that its curve's row judges;
# - a PARKED row is superseded, and not counted, when another record of the same model has a
#   PASS or FAIL row for the same target id (its first word, e.g. `V-A6`).
using TOML: TOML

const STATUS_DIR = @__DIR__
const STATUS_ROOT = dirname(dirname(STATUS_DIR))
const STATUS_DATA = joinpath(STATUS_ROOT, "lib", "PottsModels", "reproductions", "data")

function _read_tsv(path)
    lines = filter(!isempty ∘ strip, readlines(path))
    head = String.(split(lines[1], '\t'))
    return head, [Dict(zip(head, String.(split(l, '\t')))) for l in lines[2:end]]
end

_is_control(r) = get(r, "case", "") == "control" || get(r, "control", "") == "true" ||
                 any(v -> occursin("control: must FAIL", v), values(r))
_target(r) = get(r, "target", get(r, "criterion", ""))
# a per-point line (`check` "point …", 01b) is judged inside its curve's row
_is_summary(r) = occursin("(all rows)", _target(r)) || startswith(get(r, "check", ""), "point ")
_target_id(r) = first(split(_target(r) * " "))

# one record directory: its verdict rows, tagged with the file they came from
function _record_rows(dir)
    rows = Dict{String, String}[]
    for f in sort(readdir(dir))
        startswith(f, "verdicts") && endswith(f, ".tsv") || continue
        _, rs = _read_tsv(joinpath(dir, f))
        for r in rs
            r["_file"] = f
            push!(rows, r)
        end
    end
    return rows
end

function _count(rows, all_rows)
    c = Dict("PASS" => 0, "FAIL" => 0, "PARKED" => 0, "controls" => 0, "controls_failing" => 0,
        "info" => 0, "superseded" => 0)
    for r in rows
        res = strip(get(r, "result", ""))
        _is_summary(r) && continue
        if _is_control(r)
            c["controls"] += 1
            res == "FAIL" && (c["controls_failing"] += 1)
        elseif res == "PARKED"
            id = _target_id(r)
            sup = any(o -> o["_file"] != r["_file"] && _target_id(o) == id &&
                               strip(get(o, "result", "")) in ("PASS", "FAIL"), all_rows)
            sup ? (c["superseded"] += 1) : (c["PARKED"] += 1)
        elseif res in ("PASS", "FAIL")
            c[res] += 1
        else
            c["info"] += 1
        end
    end
    return c
end

_short_machine(cpu) = occursin(r"ryzen"i, cpu) ? "PC (AMD Ryzen AI Max+ 395)" :
                      occursin("Apple", cpu) ? "Mac ($(strip(cpu)))" : strip(cpu)

function _provenance(dir)
    p = joinpath(dir, "provenance.toml")
    isfile(p) || return (; machine = "—", run = "—", commit = "—")
    t = TOML.parsefile(p)
    m = get(t, "machine", nothing)
    cpu = m isa AbstractDict ? get(m, "cpu", "—") : get(t, "cpu", "—")
    backend = m isa AbstractDict && haskey(m, "backend") ? m["backend"] :
              haskey(t, "threads") ? "CPU, $(t["threads"]) thread$(t["threads"] == 1 ? "" : "s")" : "CPU"
    wall = haskey(t, "wall_s") ? "$(round(t["wall_s"] / 60; digits = 1)) min wall" :
           haskey(t, "main_wall_s") ? "$(round(t["main_wall_s"] / 60; digits = 1)) min wall" :
           haskey(get(t, "execution", Dict()), "replicate_wall_summed_h") ?
           "$(t["execution"]["replicate_wall_summed_h"]) h summed over replicate processes" :
           haskey(t, "replicate_wall_summed_h") ? "$(t["replicate_wall_summed_h"]) h summed over replicates" : "—"
    return (; machine = _short_machine(cpu) * ", " * backend, run = wall,
            commit = haskey(t, "commit") ? "`" * t["commit"][1:8] * "`" : "—")
end

# every record of a model that has a verdict table
function _records(nn)
    base = joinpath(STATUS_DATA, nn)
    isdir(base) || return []
    out = []
    for rec in sort(readdir(base))
        d = joinpath(base, rec)
        isdir(d) || continue
        rows = _record_rows(d)
        isempty(rows) || push!(out, (; name = rec, dir = d, rows))
    end
    return out
end

# ROADMAP checkbox state of an item: "done", "open" or "planned" (Steps 6–12 bullets)
function _roadmap_state(roadmap, id)
    for l in roadmap
        occursin("**$id**", l) || continue
        s = lstrip(l)
        startswith(s, "- [x]") && return "done"
        startswith(s, "- [ ]") && return "open"
        return "planned"
    end
    return "not in ROADMAP"
end

const BUILD_ORDER = [
    ("In flight (offline FULL runs on the PC)", [
        ("P6.15g", "OpenVT Figure 6, Table 1 and Figure 7: the threshold sweeps (V1–V3b). Estimated about 45 core-hours with `SequentialCPM(; skip_interior = true)` (PC, AMD Ryzen AI Max+ 395, CPU; from the 2.83× case (a) speed-up, D-174)."),
        ("P6.3f", "Merks: the FULL run and the digitised 01b figure targets."),
    ]),
    ("Step 4: foam", [
        ("P6.4a", "copy-scope `direction`, `time`, `mcs`; initialization at `at_init`"),
        ("P6.4b", "general proposal laws with Hastings acceptance"),
        ("P6.4c", "`@retire`, `@transition`, discrete events, `@terminate`"),
        ("P6.4d", "brick-wall tilings; T1 counts and topology moments"),
        ("P6.4e", "reproduction 04 (ships with the provisional F1 default)"),
    ]),
    ("Step 5: Fortuna, 3D", [
        ("P6.5a", "cell references; liveness"),
        ("P6.5b", "the shared ownership-delta routine; `@convert`"),
        ("P6.5c", "`Fill`, `Objects`, `Group`; predicate-sourced PDEs; MSD fits"),
        ("P6.5d", "reproduction 14a / 14b (and 14c)"),
    ]),
    ("Steps 6–12 (expanded into items when Step 5 merges)", [
        ("P6.6", "myxobacteria (13)"),
        ("P6.7", "Zajac convergent extension (12)"),
        ("P6.7b", "the 14c chemotaxis variant"),
        ("P6.8", "Bauer 2007 sprouting (07)"),
        ("P6.9", "Bauer 2009 ECM topography (05)"),
        ("P6.10", "Andasari / Jafari Nivlouei multiscale (11)"),
        ("P6.11", "Jiang 2005 tumour, 3D (06)"),
        ("P6.12", "FBCA (08)"),
    ]),
    ("After all paper models", [
        ("P6.0bi", "Metal verification batch"),
    ]),
]

_cell(s) = replace(String(s), "|" => "∣")

function render_status(; published::Bool = false)
    models = TOML.parsefile(joinpath(STATUS_DIR, "models.toml"))["model"]
    roadmap = readlines(joinpath(STATUS_ROOT, "docs", "design", "ROADMAP.md"))
    io = IOBuffer()
    println(io, """
    # [Paper models: status](@id paper-status)

    One row per model of the Potts.jl paper: the 12 reference models and the OpenVT monolayer
    benchmark. The PASS, FAIL and PARKED counts are computed from the committed verdict tables of
    the full reproduction runs (`lib/PottsModels/reproductions/data/<NN>/`) each time these docs
    are built, so they always match the records. The status and the open deviations are kept by
    hand in `docs/status/models.toml`.

    !!! note "Policy"
        - **All 12 models.** The paper covers all 12 reference models; there is no reduced
          fallback set (D-154).
        - **Provisional defaults.** No open question to a paper's authors holds a model back.
          The model ships with a labelled provisional default, and every provisional default is
          a row of the deviations table on that model's page, with its author-question status
          (D-154, D-155).
        - **Author letters are sent by the PI.** Questions for the authors are collected on our
          open question list. Nothing on these pages is an answer from an author or from the
          OpenVT consortium unless its deviations row says "answered".

    ## Status

    | # | Model | Status | PASS | FAIL | PARKED | Open deviations | Page |
    |:--|:------|:-------|-----:|-----:|-------:|:----------------|:-----|""")
    details = IOBuffer()
    for m in models
        nn = m["spec"]
        recs = haskey(m, "data") ? _records(m["data"]) : []
        all_rows = reduce(vcat, (r.rows for r in recs); init = Dict{String, String}[])
        counts = isempty(recs) ? nothing : _count(all_rows, all_rows)
        status = "**" * m["status"] * "**" * (haskey(m, "status_note") ? " ($(m["status_note"]))" : "")
        if m["status"] == "partial" && isempty(recs)
            status = "**partial (smoke tier)** ($(m["status_note"]))"
        end
        pf(k) = counts === nothing ? "—" : string(counts[k])
        devs = join(("• " * _cell(d) for d in get(m, "deviations", String[])), " ")
        # the paper's page in the "Paper models" section: its reproduction page when that is
        # built, its model page otherwise (docs/make.jl, D-185)
        links = String[]
        if published && haskey(m, "published")
            push!(links, "[reproduction](published/$(m["published"]).md)")
        elseif haskey(m, "models_page")
            push!(links, "[model page](@ref $(m["models_page"]))")
        end
        println(io, "| $nn | $(_cell(m["name"])) | $status | $(pf("PASS")) | $(pf("FAIL")) | $(pf("PARKED")) | $devs | ",
                isempty(links) ? "—" : join(links, ", "), " |")
        isempty(recs) && continue
        println(details, "\n### $nn: $(m["name"])\n")
        println(details, "| Record | PASS | FAIL | PARKED | Control rows failing | Information rows | Machine and backend | Run time | Commit |")
        println(details, "|:--|--:|--:|--:|--:|--:|:--|:--|:--|")
        for r in recs
            c = _count(r.rows, all_rows)
            p = _provenance(r.dir)
            sup = c["superseded"] > 0 ? " (+$(c["superseded"]) superseded)" : ""
            ctl = c["controls"] == 0 ? "—" : "$(c["controls_failing"]) of $(c["controls"])"
            println(details, "| `data/$(m["data"])/$(r.name)/` | $(c["PASS"]) | $(c["FAIL"]) | $(c["PARKED"])$sup | ",
                    "$ctl | $(c["info"]) | $(p.machine) | $(p.run) | $(p.commit) |")
        end
    end
    println(io, """

    A dash means the model has no committed full-run record yet. A model whose results come only
    from the docs-build (SMOKE) tier is "partial (smoke tier)".""",
            published ? " Each row links its paper's page in this section: the reproduction page, which " *
                        "builds the model and runs it against the paper's targets." :
            " Each row links its paper's page in this section, the model page. The full reproduction " *
            "pages are built only with `POTTS_DOCS_PUBLISHED=true`; each row then links its reproduction page.")
    println(io, """

    The section also has one model page that is **not a reproduction**:
    [Actin-driven migration (the Act model)](@ref model-wortel-act) builds the Act model of
    Niculescu et al. (2015) and Wortel et al. (2021) as a tutorial, without comparing it with
    the papers' results.""")
    println(io, """

    ## How the counts are made

    - Each record's `verdicts*.tsv` is read, and its `result` column counted: PASS, FAIL and
      PARKED. Every other value (`info: in band`, `reported`) is an information row.
    - A negative-control row (a deliberately broken model or parameter set that the target
      must reject) is not a verdict on the model and is not counted. The records table shows
      how many control rows fail; the frozen tests decide which control rows must fail.
    - A summary row ("… (all rows)") repeats other rows and is not counted. Nor is a
      per-point line (`check` "point …"): its curve's row is the verdict.
    - A PARKED row is "superseded" when another record of the same model measures the same
      target (the same id, such as `V-A6`) with a PASS or FAIL; it is not counted as PARKED.
    - Targets that are parked or not yet run on a page, but have no row in a record, are not
      counted; they are listed under the open deviations.

    ## Records

    Every timing names its machine and backend. "PC" is an AMD Ryzen AI Max+ 395 workstation
    (16 cores, Ubuntu 24.04); "Mac" is an Apple M1 Pro. All records ran on the CPU.""")
    print(io, String(take!(details)))
    println(io, """

    ## Remaining build order

    In the order of the ROADMAP (`docs/design/ROADMAP.md`, Phase 6); each item's state is read
    from it when these docs are built.
    """)
    for (step, items) in BUILD_ORDER
        println(io, "**$step**\n")
        for (id, what) in items
            println(io, "- `$id` ($(_roadmap_state(roadmap, id))): $what")
        end
        println(io)
    end
    write(joinpath(dirname(STATUS_DIR), "src", "status.md"), String(take!(io)))
    return "status.md"
end
