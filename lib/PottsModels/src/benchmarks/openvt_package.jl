# The OpenVT monolayer submission package (spec 15 §4.0.1; P6.15j, D-180): the
# `implementations/Potts.jl/` and `results/Potts.jl/` trees of the consortium layout, built
# from the committed D-146 records under `reproductions/data/15/`. No simulation runs here.
#
# Determinism: every file is a function of the records and the sources only. Records,
# cases, seeds and rows are visited in sorted order, TOML is printed with sorted keys, and
# nothing reads the clock, the host or an absolute path.

const _OPENVT_PKG_DATA = normpath(joinpath(
    @__DIR__, "..", "..", "reproductions", "data", "15"))
const _OPENVT_PKG_SRC = normpath(joinpath(@__DIR__, ".."))
const _OPENVT_PKG_URL = "https://github.com/PraneethMerugu/Potts.jl"
const _OPENVT_PKG_CYCLE = 775                 # MCS per cycle, 5T = A₀/α (C1, C16)
const _OPENVT_PKG_GRID = 39                   # save cadence of the monolayer records (D-173)
const _OPENVT_PKG_CASES = ("a", "b", "e", "f")
const _OPENVT_PKG_LAMBDAS = (1, 2, 3, 5)
const _OPENVT_PKG_PARKED = "FULL run parked (D-174)"

# ROADMAP item => what its record carries (P6.15i convention: `provenance.toml`'s `item`)
const _OPENVT_PKG_ITEMS = (
    calib = "P6.15b", f5 = "P6.15e", f3f8 = "P6.15f", f1f4 = "P6.15h", sweeps = "P6.15g")
const _OPENVT_PKG_FIGURES = (
    calib = "Figure 2, Table S5", f5 = "Figure 5", f3f8 = "Figures 3 and 8",
    f1f4 = "Figures 1 and 4", sweeps = "Figure 6, Table 1, Figure 7")

"""
    PottsModels.openvt_submission_package(outdir::AbstractString) -> outdir

Build the Potts.jl submission to the OpenVT growing-monolayer benchmark in the consortium
repository's layout (spec 15 §4.0.1): `outdir/implementations/Potts.jl/` (the
`@potts_model` sources, the record runners, a README on rerunning everything, and
`parameters.csv`) and `outdir/results/Potts.jl/` (the O4 relaxation widths and Table S5,
the O6 metrics per run with their replicate means and neighbour histograms, the Fig 1
close-up, each record's provenance without its host name, and a README with the units,
seeds, the deviations table and what is still pending).

Everything is read from the committed records under `lib/PottsModels/reproductions/data/15/`
(D-146); nothing is simulated. An item's record is the newest directory (by name) whose
`provenance.toml` names its ROADMAP item. The sweep outputs (O3, O5) are packaged as soon
as a P6.15g record is merged and are listed as pending until then.

Two calls on the same commit write byte-identical trees. `outdir` must lie outside any git
checkout (the package is not committed) and must not exist or be an empty directory;
otherwise this is an `ArgumentError`.
"""
function openvt_submission_package(outdir::AbstractString)
    out = abspath(outdir)
    _openvt_pkg_in_git(out) &&
        throw(ArgumentError("openvt_submission_package: $outdir is inside a git checkout; build the package outside git"))
    if ispath(out)
        isdir(out) ||
            throw(ArgumentError("openvt_submission_package: $outdir exists and is not a directory"))
        isempty(readdir(out)) ||
            throw(ArgumentError("openvt_submission_package: $outdir is not empty"))
    end
    recs = _openvt_pkg_records()
    for k in (:calib, :f5, :f3f8, :f1f4)
        haskey(recs, k) ||
            throw(ArgumentError("openvt_submission_package: no $(_OPENVT_PKG_ITEMS[k]) record in data/15"))
    end
    impl = joinpath(out, "implementations", "Potts.jl")
    res = joinpath(out, "results", "Potts.jl")
    mkpath(impl)
    mkpath(res)
    prov = Dict(k => TOML.parsefile(joinpath(_OPENVT_PKG_DATA, d, "provenance.toml"))
    for (k, d) in recs)

    # implementations/Potts.jl
    mkpath(joinpath(impl, "src"))
    for f in ("openvt_reference.jl", "openvt_chain.jl")
        cp(joinpath(_OPENVT_PKG_SRC, f), joinpath(impl, "src", f))
    end
    scripts = Dict{Symbol, Vector{String}}()
    for k in _openvt_pkg_keys(recs)
        d = recs[k]
        dir = joinpath(impl, "scripts", d)
        mkpath(dir)
        scripts[k] = sort(filter(
            f -> endswith(f, ".jl") && isfile(joinpath(_OPENVT_PKG_DATA, d, f)),
            readdir(joinpath(_OPENVT_PKG_DATA, d))))
        for f in scripts[k]
            cp(joinpath(_OPENVT_PKG_DATA, d, f), joinpath(dir, f))
        end
    end
    calib_meta = TOML.parsefile(joinpath(_OPENVT_PKG_DATA, recs[:calib], "meta.toml"))
    _openvt_pkg_write(joinpath(impl, "parameters.csv"), _openvt_pkg_parameters(calib_meta))
    _openvt_pkg_write(joinpath(impl, "README.md"), _openvt_pkg_impl_readme(recs, prov, scripts))

    # results/Potts.jl
    cp(joinpath(_OPENVT_PKG_DATA, recs[:f1f4], "fig1.png"), joinpath(res, "closeup.png"))
    mkpath(joinpath(res, "provenance"))
    for k in _openvt_pkg_keys(recs)
        p = copy(prov[k])
        delete!(p, "hostname")
        _openvt_pkg_write(joinpath(res, "provenance", recs[k] * ".toml"),
            sprint(io -> TOML.print(io, p; sorted = true)))
    end
    _openvt_pkg_relaxation(joinpath(res, "Relaxation"), joinpath(_OPENVT_PKG_DATA, recs[:calib]), calib_meta)
    f3f8_meta = TOML.parsefile(joinpath(_OPENVT_PKG_DATA, recs[:f3f8], "meta.toml"))
    _openvt_pkg_monolayer(joinpath(res, "Monolayer"), joinpath(_OPENVT_PKG_DATA, recs[:f3f8]))
    present = Set{Symbol}()
    _openvt_pkg_optional!(present, joinpath(res, "Monolayer"), recs)
    _openvt_pkg_write(joinpath(res, "README.md"),
        _openvt_pkg_results_readme(recs, prov, calib_meta, f3f8_meta, present))
    return outdir
end

# ── records and small I/O helpers ───────────────────────────────────────────────────────────

function _openvt_pkg_in_git(path::AbstractString)
    d = path
    while true
        ispath(joinpath(d, ".git")) && return true
        p = dirname(d)
        p == d && return false
        d = p
    end
end

function _openvt_pkg_records()
    recs = Dict{Symbol, String}()
    isdir(_OPENVT_PKG_DATA) || return recs
    for d in sort(readdir(_OPENVT_PKG_DATA))
        p = joinpath(_OPENVT_PKG_DATA, d, "provenance.toml")
        isfile(p) || continue
        item = get(TOML.parsefile(p), "item", "")
        for k in keys(_OPENVT_PKG_ITEMS)
            _OPENVT_PKG_ITEMS[k] == item && (recs[k] = d)     # sorted by name: the newest wins
        end
    end
    return recs
end

# the record keys in their fixed order
_openvt_pkg_keys(recs) = [k for k in keys(_OPENVT_PKG_ITEMS) if haskey(recs, k)]

function _openvt_pkg_write(path, text::AbstractString)
    (mkpath(dirname(path)); write(path, text); path)
end

function _openvt_pkg_lines(path)
    filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
end

function _openvt_pkg_tsv(path)
    ls = _openvt_pkg_lines(path)
    head = String.(split(ls[1], '\t'))
    return head, [Dict(zip(head, String.(split(l, '\t')))) for l in ls[2:end]]
end

_openvt_pkg_f(s) = parse(Float64, strip(s))

function _openvt_pkg_csv(path, header, rows)
    io = IOBuffer()
    print(io, header, '\n')
    for r in rows
        print(io, join((x isa AbstractString ? x : _openvt_float(x) for x in r), ','), '\n')
    end
    return _openvt_pkg_write(path, String(take!(io)))
end

# ── parameters.csv ─────────────────────────────────────────────────────────────────────────

function _openvt_pkg_parameters(calib_meta)
    T2 = calib_meta["T_ours"]["2"]
    rows = [
        ("A0", 50.0, "px (A*(0); Table S1)"),
        ("lambda", 2.0, "1 (area stiffness; Table S1)"),
        ("temperature", 20.0, "1 (fluctuation amplitude T; Table S1)"),
        ("J_cell_cell", 20.0, "1 (Table S1)"),
        ("J_cell_medium", 10.0, "1 (Table S1)"),
        ("alpha", 50 / 775, "px/MCS (6.452e-2 = A0/775; Table S1)"),
        ("mu_X", 2.0, "1 (mean division threshold X; mu_Amax = mu_X A0 = 100 px)"),
        ("sigma_X", 0.4, "1 (SD of X; 0 in the deterministic case (f))"),
        ("beta", 0.0, "1 (type 1 threshold; 0.8 in case (e))"),
        ("gamma", 0.0, "1 (type 2 threshold; 1e-4 in our negative control)"),
        ("cycle_MCS", Float64(_OPENVT_PKG_CYCLE), "MCS (one cell cycle 5T = A0/alpha)"),
        ("T_relax_lambda2_MCS", Float64(T2),
            "MCS (mechanical time scale T at lambda = 2; Table S5)"),
        ("R_px", sqrt(50 / pi),
            "px (length unit R = sqrt(A0/pi); the initial cell radius)"),
        ("CD_px", 10.0, "px (cell diameter in the relaxation files)"),
        ("save_interval_MCS", Float64(_OPENVT_PKG_GRID), "MCS (monolayer saves)"),
        ("edge_guard_sites", 5.0,
            "sites (a run stops if a cell comes this close to the lattice edge)"),
        ("lattice_1000_cells", 400.0, "sites per side (cases b and f)"),
        ("lattice_10000_cells", 1400.0, "sites per side (cases a and e)"),
        ("neighbourhood", "Moore(1)", "- (energy and copy-attempt neighbourhood)"),
        ("boundary", "closed", "- (no wrap; see the edge guard)"),
        ("algorithm", "SequentialCPM",
            "- (random-site Metropolis sweep; 1 MCS = one attempt per site)"),
        ("division_plane", "random", "- (RandomPlane)")
    ]
    io = IOBuffer()
    print(io, "name,value,unit\n")
    for (n, v, u) in rows
        print(io, n, ',', v isa AbstractString ? v : _openvt_float(v),
            ',', replace(u, ',' => ';'), '\n')
    end
    return String(take!(io))
end

# ── Relaxation (O4, Table S5) ──────────────────────────────────────────────────────────────

function _openvt_pkg_relaxation(dir, rec, meta)
    H_W = "Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)"
    H_I = "Normalized time (T),Mean inner width (CD),STD inner width (CD)"
    _, r11 = _openvt_pkg_tsv(joinpath(rec, "timeseries_11chain.tsv"))
    _, r21 = _openvt_pkg_tsv(joinpath(rec, "timeseries_21chain.tsv"))
    lam(λ) = filter(r -> r["lambda"] == string(λ), r11)
    cols(rows, c...) = [Tuple(_openvt_pkg_f(r[x]) for x in c) for r in rows]
    _openvt_pkg_csv(joinpath(dir, "11cells", "width.csv"), H_W, cols(lam(2), "t_over_T", "w11_mean", "w11_sd"))
    _openvt_pkg_csv(joinpath(dir, "11+10cells", "width.csv"), H_W, cols(r21, "t_over_T", "w21_mean", "w21_sd"))
    _openvt_pkg_csv(joinpath(dir, "11+10cells", "inner_width.csv"), H_I,
        cols(r21, "t_over_T", "inner_w11_mean", "inner_w11_sd"))
    for λ in _OPENVT_PKG_LAMBDAS
        _openvt_pkg_csv(joinpath(dir, "lambda_scan", "11cells_lambda$(λ)_width.csv"), H_W,
            cols(lam(λ), "t_over_T", "w11_mean", "w11_sd"))
    end
    _, ref = _openvt_pkg_tsv(joinpath(rec, "reference.tsv"))
    rt = [_openvt_pkg_f(r["t_over_T"]) for r in ref]
    rw = [_openvt_pkg_f(r["w"]) for r in ref]
    s5 = Tuple{String, String, Float64}[]
    for λ in _OPENVT_PKG_LAMBDAS
        T = meta["T_ours"][string(λ)]
        post = filter(r -> _openvt_pkg_f(r["t_mcs"]) >= 0, lam(λ))
        mse = Analysis.relaxation_mse([_openvt_pkg_f(r["t_mcs"]) for r in post],
            [_openvt_pkg_f(r["w11_mean"]) for r in post], T, rt, rw)
        push!(s5, (string(λ), string(T), mse))
    end
    _openvt_pkg_csv(joinpath(dir, "table_S5.csv"), "lambda,T (MCS),MSE", s5)
    return nothing
end

# ── Monolayer metrics (O6) ─────────────────────────────────────────────────────────────────

function _openvt_pkg_timeseries(rec)
    _, rows = _openvt_pkg_tsv(joinpath(rec, "timeseries.tsv"))
    runs = Dict{Tuple{String, Int}, Vector{Vector{Float64}}}()
    for r in rows
        r["case"] in _OPENVT_PKG_CASES || continue
        v = [_openvt_pkg_f(r[c]) for c in ("mcs", "N", "r", "A", "C", "w", "g")]
        push!(get!(runs, (r["case"], parse(Int, r["seed"])), Vector{Vector{Float64}}()), v)
    end
    for v in values(runs)
        sort!(v; by = first)
    end
    return runs
end

function _openvt_pkg_monolayer(dir, rec)
    ts = _openvt_pkg_timeseries(rec)
    _, nb = _openvt_pkg_tsv(joinpath(rec, "neighbors.tsv"))
    for case in _OPENVT_PKG_CASES
        seeds = sort([s for (c, s) in keys(ts) if c == case])
        for s in seeds
            rows = [(Int(v[1]), v[1] / _OPENVT_PKG_CYCLE, v[2:7]...) for v in ts[(case, s)]]
            _openvt_pkg_csv(joinpath(dir, "metrics", case, "measurements_s$(s).csv"), "MCS,t,N,r,A,C,w,g", rows)
        end
        # the replicate mean (schema "Data Collection"): MCS on the save grid saved by every run
        grids = [Set(Int(v[1]) for v in ts[(case, s)] if Int(v[1]) % _OPENVT_PKG_GRID == 0)
                 for s in seeds]
        grid = isempty(grids) ? Int[] : sort(collect(reduce(intersect, grids)))
        byrun = [Dict(Int(v[1]) => v for v in ts[(case, s)]) for s in seeds]
        mrows = Vector{Tuple}()
        for m in grid
            row = Any[m, m / _OPENVT_PKG_CYCLE]
            for j in 2:7
                vals = filter(!isnan, [b[m][j] for b in byrun])
                push!(row, isempty(vals) ? NaN : sum(vals) / length(vals))
            end
            push!(row, length(seeds))
            push!(mrows, Tuple(row))
        end
        _openvt_pkg_csv(joinpath(dir, "metrics", "measurements_$(case)_mean.csv"),
            "MCS,t,N,r,A,C,w,g,runs", mrows)
        # the pooled final neighbour-number histogram (metrics.cpp's `n,p`, p in %)
        c = Dict{Int, Float64}()
        for r in nb
            r["case"] == case || continue
            n = parse(Int, r["n"])
            c[n] = get(c, n, 0.0) + _openvt_pkg_f(r["count"])
        end
        tot = sum(values(c); init = 0.0)
        _openvt_pkg_csv(joinpath(dir, "metrics", "neighbors_$(case).csv"), "n,p",
            [(n, 100 * c[n] / tot) for n in sort(collect(keys(c))) if c[n] > 0])
    end
    return nothing
end

# ── optional items: copied when a record carries them ─────────────────────────────────────

function _openvt_pkg_optional!(present, dir, recs)
    # O2: the F5 snapshots, if a record ever carries them (D-168 kept them out of git)
    o2 = joinpath(_OPENVT_PKG_DATA, recs[:f5], "Potts.jl_5T_MonolayerGrowth_1000_Data")
    if isdir(o2)
        fs = sort(filter(f -> occursin(r"^cell_data_no_inhibition_\d+\.csv$", f), readdir(o2)))
        if !isempty(fs)
            mkpath(joinpath(dir, "Potts.jl_5T_MonolayerGrowth_1000_Data"))
            for f in fs
                cp(joinpath(o2, f), joinpath(dir, "Potts.jl_5T_MonolayerGrowth_1000_Data", f))
            end
            push!(present, :O2)
        end
    end
    # O3 and O5: the P6.15g sweeps record (D-174): its O3 tables and its f7/ O5 snapshots
    haskey(recs, :sweeps) || return present
    sw = joinpath(_OPENVT_PKG_DATA, recs[:sweeps])
    for (key, f) in ((:O3b, "Potts.jl_time_to_10k_vs_beta.csv"), (
        :O3g, "Potts.jl_time_to_10k_vs_gamma.csv"))
        isfile(joinpath(sw, f)) || continue
        mkpath(dir)
        cp(joinpath(sw, f), joinpath(dir, f))
        push!(present, key)
    end
    f7 = joinpath(sw, "f7")
    if isdir(f7)
        fs = sort(filter(f -> occursin(r"^Potts\.jl_gamma_[0-9.eE+-]+_\d+MCS\.csv$", f), readdir(f7)))
        if !isempty(fs)
            mkpath(joinpath(dir, "final_snapshot_data"))
            for f in fs
                cp(joinpath(f7, f), joinpath(dir, "final_snapshot_data", f))
            end
            push!(present, :O5)
        end
    end
    return present
end

# ── implementations README ────────────────────────────────────────────────────────────────

_openvt_pkg_threads(p) = get(p, "threads", 1)

function _openvt_pkg_wall(p)
    s = get(p, "wall_s", nothing)
    s === nothing && return "—"
    return s < 120 ? @sprintf("%.0f s", s) :
           s < 7200 ? @sprintf("%.0f min", s / 60) : @sprintf("%.1f h", s / 3600)
end

function _openvt_pkg_impl_readme(recs, prov, scripts)
    io = IOBuffer()
    print(io,
        """
# Potts.jl: OpenVT growing monolayer

The Potts.jl implementation of the OpenVT growing-monolayer benchmark: a cellular Potts
model (CPM) with the Table S1 parameters, written in the `@potts_model` authoring
surface of [Potts.jl]($(_OPENVT_PKG_URL)). Every result under `results/Potts.jl/` was
produced by the scripts below at the commits listed, and the result files were built from
the committed run records by `PottsModels.openvt_submission_package`.

## Contents

| Path | What it is |
|---|---|
| `src/openvt_reference.jl` | `OpenVTReferenceMonolayer`, the monolayer model (Table S1), and `openvt_reference_state`, the one-cell disc start |
| `src/openvt_chain.jl` | `OpenVTChain`, the 1D chain model of the mechanical calibration (Figure 2, Table S5), with `openvt_chain` and `openvt_release` |
| `parameters.csv` | every parameter and Potts.jl setting used, with units |
| `scripts/<record>/` | the runner and plotting scripts of each run record, unchanged |

Both model files are copies of `lib/PottsModels/src/` in the Potts.jl repository, where
they are part of the `PottsModels` package (`using PottsModels`).

## The model in brief

- Hamiltonian: area constraint `λ (A − A*)²` plus adhesion `J` over Moore(1) pairs
  (cell–cell 20, cell–medium 10), temperature T = 20, Metropolis acceptance, one copy
  attempt per lattice site per MCS (`SequentialCPM` with `Moore(1)` proposals).
- Growth: every growing cell's target area A* increases by α = 50/775 px per MCS, so one
  cell cycle is 5T = 775 MCS.
- Division: when the actual area reaches `X · A*(0)`, along a random plane. Both daughters take half the mother's A* and draw their own X ~ N(2, 0.4),
  redrawn while X ≤ 0 (`σ_X = 0` gives the deterministic X ≡ 2 of case (f)).
- Inhibition: a cell grows only while `a = A/A* ≥ β` (else it is type-1 inhibited) and
  its free-surface fraction `f ≥ γ` (else type-2 inhibited); f is the share of the cell's
  unlike Moore(1) contact pairs that face medium.
- Start: one disc of radius R = √(A₀/π) at the lattice centre, on a closed lattice with
  a 5-site edge guard (a run stops if a cell comes that close to the edge; no recorded
  run did).

## Install

Potts.jl needs Julia 1.12 or newer.

```sh
git clone $(_OPENVT_PKG_URL).git
cd Potts.jl
julia --project=lib/PottsModels/test -e 'using Pkg; Pkg.instantiate()'
```

Every command below runs from the repository root in that test environment,
`--project=lib/PottsModels/test`, which holds `Potts`, `PottsModels` and the plotting
packages.

## Run the model

```julia
using Potts, PottsModels
sys = mtkcompile(OpenVTReferenceMonolayer(; name = :monolayer, lattice = (400, 400)))
prob = PottsProblem(sys, openvt_reference_state(; lattice = (400, 400)), (0, 775); capacity = 2000)
sol = solve(prob, SequentialCPM())
```

## Rerun the records

Each record lives in `lib/PottsModels/reproductions/data/15/<record>/` of the repository;
`scripts/<record>/` here holds the same files. A runner reruns the protocol of the
record's acceptance test (`lib/PottsModels/test/reproductions/15_openvt_*.jl`) from that
file's source, so it must be run inside a checkout. For a bit-for-bit rerun, check out
the record's commit first (`git checkout <commit>`); seeds are fixed in the runners.

| Record | Results | Runner | Commit | Threads | Wall time | Command |
|---|---|---|---|---|---|---|
""")
    for k in _openvt_pkg_keys(recs)
        d, p = recs[k], prov[k]
        runner = basename(p["runner"])
        print(io, "| `", d, "` | ", _OPENVT_PKG_FIGURES[k],
            " | `scripts/", d, "/", runner, "` | `", p["commit"][1:8],
            "` | ", _openvt_pkg_threads(p), " | ", _openvt_pkg_wall(p), " | `julia -t ",
            _openvt_pkg_threads(p), " --project=lib/PottsModels/test ",
            p["runner"], "` |\n")
    end
    print(
        io, """

  The other scripts of a record are listed below; each one's header says what it does and
  how to run it. `plot_*.jl` redraw the figures from the record's own data files,
  `video_*.jl` rerun run 1 of each case to render the videos (not part of this package), and
  `probe_causes.jl` reruns the 20-run cause probes quoted in the V4 rows.

  """)
    for k in _openvt_pkg_keys(recs)
        others = filter(!=(basename(prov[k]["runner"])), scripts[k])
        isempty(others) && continue
        print(
            io, "- `scripts/", recs[k], "/`: ", join(("`$f`" for f in others), ", "), "\n")
    end
    print(io,
        """

The plotting scripts that begin with `julia --project=docs` in their header use the docs
environment (`julia --project=docs -e 'using Pkg; Pkg.instantiate()'` once). Scripts whose
names end in `_on_g.jl`, and `compose_f1.jl`, overlay the consortium's public data from a
local clone of the benchmark repository (`OPENVT_MONOLAYER_REPO`); they are information
only and nothing they read is part of this package.

The wall times above are those of the recorded runs; the exact machine, Julia version
and timings of each run are in `results/Potts.jl/provenance/`.

## Rebuild this package

```sh
julia --project=lib/PottsModels/test -e 'using PottsModels; PottsModels.openvt_submission_package("../openvt-potts-package")'
```

`openvt_submission_package` reads only the committed records (no simulation), refuses a
target inside a git checkout or a non-empty directory, and writes byte-identical trees on
every call at the same commit. The acceptance test
`lib/PottsModels/test/reproductions/15_openvt_package.jl` checks every file against the
records.

## Citation

Cite the repository URL and the commit of the record you use.
""")
    return String(take!(io))
end

# ── results README ────────────────────────────────────────────────────────────────────────

# a Markdown table cell: no pipes, no line breaks
_openvt_pkg_cell(s) = replace(strip(String(s)), '|' => '∣', '\n' => ' ', '\t' => ' ')

_openvt_pkg_row(cells...) = string("| ", join(map(_openvt_pkg_cell, cells), " | "), " |\n")

_openvt_pkg_key(target) = String(split(target)[1])

function _openvt_pkg_status(s)
    q = _openvt_pkg_cell(s)
    occursin(r"^(not an author question|not asked|resolved)"i, q) || (q = "not asked; " * q)
    occursin(r"\bQ\d+\b", q) && !occursin("our open question list", q) &&
        (q *= " (our open question list)")
    return q
end

# hand-written rows for the record deviations and failures (keyed by row id); each is used
# only while it still carries the record's value, else the record's own row is printed
const _OPENVT_PKG_RECORD_ROWS = Dict(
    "V4.2" => ("V4.2 peak of nonzero f (FAIL)",
        "0.425 (100 runs, 11,226 cells with f > 0); 0.395–0.435 for smoothing windows of 1–11 bins; mean nonzero f 0.346",
        "0.25–0.35 (TST and Morpheus pooled); TST alone 0.295, mean nonzero f 0.288",
        "leading: Potts.jl divides on actual area, TST on target area (C13). Not the Morpheus f definition or σ_X (C17): TST alone uses our f and σ_X = 0.4 and passes. Ruled out on 20 runs each: the division axis and a connectivity constraint",
        "not asked; on our open question list as Q20 (leading) and Q23"),
    "V4.3" => ("V4.3 max f (FAIL)",
        "0.847; 606 of 11,226 rim cells (5.4 %) above 0.56",
        "at most 0.56, no cell above (TST max 0.553)",
        "the same upward shift of the rim cells' f as V4.2; causes as for V4.2",
        "not asked; on our open question list as Q20 (leading) and Q23"),
    "V4.5" => ("V4.5 range of a (FAIL)",
        "0.066–1.130; 30 of 100,029 cells below 0.42, all small interior cells born shortly before, 10 of them sister pairs",
        "0.42–1.09; TST 0.425–1.092 with no cell below 0.42",
        "squeezed young daughters, cause unresolved; leading candidate the target-area division (C13). A connectivity constraint raises the minimum but not the count",
        "not asked; on our open question list as Q20 (leading) and Q24")
)

# the readings of spec 15 §1.1 and our choices that differ from M
const _OPENVT_PKG_FIXED_ROWS = [
    ("F1 panel colours",
        "per-cell identity colours (one categorical colour per cell), white medium, no outlines",
        "the other frameworks' panels colour cells by a blue-to-red variable (most likely cell area) with grey boundaries",
        "a stylistic choice: per-cell colours, never outlines (D-156, D-175)",
        "not asked; on our open question list as Q10 (the colour variable) and Q18 (the Potts.jl colour, RGB(8, 29, 88) proposed)"),
    ("F1 window",
        "a 64 × 64-site block (about 8 cell diameters) centred on the colony rim",
        "45 × 45 mm close-ups; the window size is not stated",
        "estimated from the TST close-up; the other panels show more colony than medium", "not an author question"),
    ("F2 consortium curves", "Potts.jl curves and the spring–dashpot reference only",
        "panels b, d, e overlay all frameworks",
        "the consortium's curves are compared through frozen spread values, not redrawn", "not an author question"),
    ("F3 time axis and framework",
        "t in 775-MCS cycles; TST shown as the comparison row",
        "axis \"[T]\"; the framework of M's Figure 3 is not named", "read as cycles, as the TST data imply",
        "not asked; on our open question list as Q2 (open part) and Q13"),
    ("F3.4 colony area, case (f)",
        "14.3 % above TST at t = 8.5 (inside the 20 % band, the largest margin used)",
        "TST deterministic",
        "division on actual area (C13): cells of one generation divide over 0.23–0.41 cycles, not in one MCS",
        "not asked; on our open question list as Q20"),
    ("F4 drawing", "cell i's outline and the in-panel names left out; counts as numbers",
        "a black outline of cell i, names, coloured count glyphs", "no outlines (D-156)", "not an author question"),
    ("F5 distance bins and origin",
        "5 equal bins from 0 to 1.05 times the furthest distance (0–8, …, 35–44 R), from the initial cell's centre",
        "legend 0–7, …, 31–39; the notebook uses 7 bins from the pooled centroid",
        "M's figure and text taken over its notebook (C11, C12)", "not asked; on our open question list as Q15"),
    ("F8 consortium curves",
        "only final values compared with the draft's CompuCell3D and Morpheus curves (converted from px to R)",
        "lengths in R, time in cycles", "the draft curves are earlier β = 0.8 runs in each framework's own cycle length",
        "not asked; on our open question list as Q7 and Q14"),
    ("Domain",
        "closed 400² or 1400² lattice with a 5-site edge guard (edge_guard); no run came closer than 33 sites",
        "unbounded plane", "a finite lattice the colony never reaches is equivalent",
        "not an author question"),
    ("Division axis", "random plane",
        "not stated for CPMs (CompuCell3D and Morpheus: random; TST: minor axis)",
        "majority practice; TST's minor axis tested on 20 runs and it does not change V4", "not an author question"),
    ("C1 cell-cycle length", "one cycle = 5T = 775 MCS",
        "M says the cycle is 5T but also, once, that time is in units of T",
        "M contradicts itself; its tables and the TST data fix 5T",
        "resolved: 5T = 775 MCS from the consortium data (Q2 on our open question list)"),
    ("C2 calibration compression",
        "target area halved during a burn-in, both chain ends free",
        "left to each framework",
        "the four CPM implementations all do this", "not an author question"),
    ("C3 truncation of X", "X redrawn while X ≤ 0", "silent; the schema redraws",
        "P(X ≤ 0) is about 3 × 10⁻⁷, so it never fires", "not an author question"),
    ("C4 replicates", "100 runs for Figures 2 and 5, 10 or more per Figure 3/8 case",
        "100 for Figure 5; the schema's floor is 10",
        "M where it states a number", "not an author question"),
    ("C5 sensitivity analysis", "not done",
        "not in M's analysis list (only in the schema)", "M's list taken as complete",
        "not an author question"),
    ("C6 literature comparisons", "not done", "not in M (only in the schema)",
        "M taken over the schema", "not an author question"),
    ("C7 cell diameter CD", "10 px, the relaxed length of a cell on the 5-px strip",
        "not defined numerically; the schema gives 7.98 px",
        "only 10 px makes the relaxed 11-chain 10 CD wide, as M's Figure 2 requires", "not an author question"),
    ("C8 output columns", "x, y, i, n, with g = (i == 0) derived for the analysis",
        "x, y, i, n (the analysis code reads x, y, g, n)", "M for submitted files", "not an author question"),
    ("C9 type 1 inequality", "a ≥ β", "a ≥ β (the schema has a > β)",
        "M, as Morpheus, TST and Artistoo", "not an author question"),
    ("C10 Figure 8 length units", "R",
        "R; the draft figure's lattice curves are in px", "M",
        "not asked; on our open question list as Q14"),
    ("C11 Figure 5 distance bins", "5 equal bins",
        "5 bins in the legend; 7 in the notebook", "M's figure",
        "not asked; on our open question list as Q15"),
    ("C12 Figure 5 distance origin", "the initial cell's centre (the lattice centre)",
        "the initial cell's centre; the notebook uses the pooled centroid", "M's text",
        "not asked; on our open question list as Q15"),
    ("C13 division trigger", "actual area ≥ X A*(0)",
        "actual area ≥ X A*(0); TST uses the target area",
        "M, with CompuCell3D and Morpheus. This is the leading candidate for the V4 failures and the slow V1 growth",
        "not asked; on our open question list as Q20"),
    ("C14 daughters' reference area", "half the mother's A*",
        "half the mother's A* (Morpheus sets it to the daughter's area)",
        "M, with CompuCell3D, TST and Artistoo", "not an author question"),
    ("C15 termination", "end of the first MCS with at least 10⁴ cells",
        "the same; CompuCell3D stops at 10,200", "M",
        "not an author question"),
    ("C16 growth rate", "α = 50/775 px/MCS",
        "6.452 × 10⁻² (Table S1); TST uses 50/770", "M", "not an author question"),
    ("C17 σ of X", "0.4", "0.4; Morpheus passes 0.16 as the standard deviation",
        "M; it cannot explain V4, since TST uses 0.4 and passes", "not asked; on our open question list as Q21")
]

# rows from the records: deviations.tsv rows, then non-control FAIL verdicts without one
function _openvt_pkg_record_rows(recs)
    out = String[]
    done = Set{String}()
    for k in _openvt_pkg_keys(recs)
        p = joinpath(_OPENVT_PKG_DATA, recs[k], "deviations.tsv")
        isfile(p) || continue
        _, rows = _openvt_pkg_tsv(p)
        for r in rows
            key = _openvt_pkg_key(r["target"])
            key in done && continue
            fail = occursin("FAIL", r["target"])
            m = match(r"\d+\.\d+", get(r, "ours", ""))
            cur = get(_OPENVT_PKG_RECORD_ROWS, key, nothing)
            line = cur === nothing ? "" : join(cur, " | ")
            if cur !== nothing && (m === nothing || occursin(m.match, line)) &&
               (!fail || occursin("FAIL", line))
                push!(out, _openvt_pkg_row(cur...))
            else
                tgt = haskey(r, "case") && !isempty(r["case"]) ?
                      "$(r["target"]), case ($(r["case"]))" : r["target"]
                push!(out,
                    _openvt_pkg_row(tgt, get(r, "ours", ""), get(r, "paper", ""),
                        get(r, "suspected_cause", ""),
                        _openvt_pkg_status(get(r, "author_question", "not asked"))))
            end
            push!(done, key)
        end
    end
    for k in _openvt_pkg_keys(recs)
        p = joinpath(_OPENVT_PKG_DATA, recs[k], "verdicts.tsv")
        isfile(p) || continue
        _, rows = _openvt_pkg_tsv(p)
        for r in rows
            get(r, "result", "") == "FAIL" || continue
            get(r, "case", "") == "control" && continue
            occursin(r"must FAIL"i, get(r, "band", "")) && continue
            occursin("(all rows)", r["target"]) && continue
            key = _openvt_pkg_key(r["target"])
            key in done && continue
            push!(out,
                _openvt_pkg_row(
                    "$(r["target"]) (FAIL)", get(r, "ours", ""), get(r, "paper", ""),
                    "band $(get(r, "band", get(r, "tolerance", ""))); cause not yet analysed", "not asked"))
            push!(done, key)
        end
    end
    return out
end

function _openvt_pkg_v1_row(recs, f3f8_meta)
    _, runs = _openvt_pkg_tsv(joinpath(_OPENVT_PKG_DATA, recs[:f3f8], "runs.tsv"))
    ca = sort([_openvt_pkg_f(r["cycles"]) for r in runs if r["case"] == "a"])
    hi = 13.57 * 1.1
    ta = f3f8_meta["stats"]["a"]["t_stop"]
    te = f3f8_meta["stats"]["e"]["t_stop"]
    judged = haskey(recs, :sweeps) ? "judged in the sweeps record `$(recs[:sweeps])`" :
             "judged with the sweeps"
    return _openvt_pkg_row(
        "V1 time to 10⁴ cells, uninhibited (measured in the Figure 3/8 record; $judged)",
        @sprintf("%.2f cycles (case (a), %d runs, %.2f–%.2f); %d of %d runs above the band; case (e) at β = 0.8: %.2f",
            ta, length(ca), first(ca), last(ca), count(>(hi), ca), length(ca), te),
        "13.57 cycles (PhysiCell's γ = 0 value), band ± 10 % = 12.21–14.93; TST low-β plateau 13.61–13.86; TST at β = 0.8: 16.15",
        @sprintf("about %.1f %% slow. The gap opens beyond 10³ cells, past the Figure 3 window. ",
            100 * (ta / 13.57 - 1)) *
        "Leading candidate: division on actual area (M, C13) against TST's division on target area, as for V4",
        "not asked; on our open question list as Q20, and Q17 (whether 13.57 is pooled or one framework's value)")
end

function _openvt_pkg_sweep_row(recs)
    haskey(recs, :sweeps) &&
        return _openvt_pkg_row("F6, T1, F7",
            "run in the record `$(recs[:sweeps])`; its failing rows are listed above",
            "Figure 6, Table 1, Figure 7", "the protocol and targets frozen before the run (D-174)",
            "not an author question")
    return _openvt_pkg_row("F6, T1, F7", "not run yet; protocol and targets frozen",
        "Figure 6, Table 1, Figure 7",
        "the full sweep (about 125 core-hours) is parked until boundary-site sampling lands (D-174)", "not an author question")
end

function _openvt_pkg_results_readme(recs, prov, calib_meta, f3f8_meta, present)
    T2 = calib_meta["T_ours"]["2"]
    cases = f3f8_meta["cases"]
    io = IOBuffer()
    print(io,
        """
# Potts.jl results: OpenVT growing monolayer

Simulation output of the Potts.jl cellular Potts model (`implementations/Potts.jl/`) for
the OpenVT growing-monolayer benchmark, in the layout of the benchmark repository. Every
file was built by `PottsModels.openvt_submission_package` from the committed run records
listed at the end; the per-record `provenance/*.toml` give the commit, Julia version,
machine and timings of each run.

## Units

- Lengths in the Monolayer files are in R = √(A₀(0)/π) = $(@sprintf("%.4f", sqrt(50 / pi))) px, the initial
  cell radius (A₀(0) = 50 px), measured from the lattice centre where the first cell starts.
- Times in the Monolayer files are in cell cycles, t = MCS/775 (one cycle is 5T = A₀/α =
  775 MCS); the MCS stamp is the first column.
- The Relaxation files use the mechanical time scale: "Normalized time (T)" is MCS/T(λ),
  with T(λ = 2) = $(T2) MCS for the 11cells and 11+10cells files and each λ's own T in
  `lambda_scan/` (`table_S5.csv`). Negative times are the 100-MCS compression burn-in,
  as in the TST files. Widths are in cell diameters, CD = 10 px.

## Files

| Path | Content | Format |
|---|---|---|
| `closeup.png` | Figure 1 panel: case (a), run 1 (seed 15701) at 10⁴ cells, a 64 × 64-site block on the colony rim | PNG |
| `Relaxation/11cells/width.csv` | 11-cell chain width, λ = 2, mean and SD over 100 runs | `Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)` |
| `Relaxation/11+10cells/width.csv`, `inner_width.csv` | 11+10-cell chain: total and inner (11-cell) width, λ = 2, T(2) with no refit, 100 runs | as above (`Mean inner width (CD)`, `STD inner width (CD)`) |
| `Relaxation/lambda_scan/11cells_lambda<λ>_width.csv` | 11-cell chain width for λ = 1, 2, 3, 5 (Table S5's runs), 100 runs each | as above |
| `Relaxation/table_S5.csv` | Table S5: T(λ) (first crossing of 90 % of the plateau by the mean width) and the MSE against the spring–dashpot reference on t ≥ 0 | `lambda,T (MCS),MSE` |
| `Monolayer/metrics/<case>/measurements_s<seed>.csv` | per run and save (every 39 MCS and at the stop): cell count and the `metrics.cpp` values (concave-hull radius, area, perimeter, roughness, growing fraction) | `MCS,t,N,r,A,C,w,g` (R, R², R) |
| `Monolayer/metrics/measurements_<case>_mean.csv` | the arithmetic mean over the case's runs (schema "Data Collection") at the saves every run reached; NaN values skipped | `MCS,t,N,r,A,C,w,g,runs` |
| `Monolayer/metrics/neighbors_<case>.csv` | final neighbour-number histogram pooled over the case's runs, p in % | `n,p` |
""")
    :O2 in present &&
        print(io,
            "| `Monolayer/Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv` | Figure 5 snapshots at 1000 cells, case (b), k = 1:100 | `x,y,r,f,a` |\n")
    (:O3b in present || :O3g in present) &&
        print(io,
            "| `Monolayer/Potts.jl_time_to_10k_vs_{beta,gamma}.csv` | Figure 6 / Table 1: time to 10⁴ cells per run (NaN for capped runs) | `beta,Time to 10k (MCS),Time to 10k (5T)` |\n")
    :O5 in present &&
        print(io,
            "| `Monolayer/final_snapshot_data/Potts.jl_gamma_<γ>_<MCS>MCS.csv` | Figure 7 final snapshots | `x_pos,y_pos,radius_i,inhibited` |\n")
    print(io, """

    ## Cases and seeds

    All monolayer runs use the Table S1 model (A₀ = 50, λ = 2, T = 20, α = 50/775, μ_X = 2,
    J 20/10, Moore(1)), start from one cell and stop at the end of the first MCS with the
    target cell count. Each run's seed is listed in its file name; runs of a case use
    consecutive seeds.

    | Case | β | γ | σ_X | Lattice | Stop (cells) | Runs | Seeds |
    |---|---|---|---|---|---|---|---|
    """)
    for c in _OPENVT_PKG_CASES
        m = cases[c]
        print(io, "| (", c, ") | ", m["beta"], " | ", m["gamma"],
            " | ", m["sigma_X"], " | ", m["lattice"], "² | ",
            m["cells"], " | ", m["runs"], " | ", m["seeds"], " |\n")
    end
    print(
        io, """

  Case (f) is deterministic division (X ≡ 2). The relaxation runs use seeds
  $(calib_meta["seeds_11chain"]) (11-cell chain at each λ) and $(calib_meta["seeds_21chain"])
  (11+10-cell chain).

  ## Colours

  `closeup.png` colours each cell with its own categorical colour (Potts.jl's
  `CellIdentityEncoding`) on a white medium, with no cell outlines, rather than by area as
  the other frameworks' panels do; the banner colour proposed for Potts.jl is RGB(8, 29, 88).
  See the F1 row below.

  ## Deviations from the manuscript

  One row per difference between our runs and the manuscript (M), per conflict between M
  and the benchmark's other sources together with the reading we took (C1–C17), and per
  failed or at-risk target. "Ours" is our value or choice, "Manuscript" M's, then the
  suspected cause and the status of the question: "not an author question", "not asked"
  (the question is on our open question list) or "resolved" (settled from the consortium's
  public data). Row ids V# and F# are our acceptance targets.

  | Item | Ours | Manuscript | Suspected cause | Author question |
  |---|---|---|---|---|
  """)
    for r in _openvt_pkg_record_rows(recs)
        print(io, r)
    end
    print(io, _openvt_pkg_v1_row(recs, f3f8_meta))
    print(io, _openvt_pkg_sweep_row(recs))
    for r in _OPENVT_PKG_FIXED_ROWS
        print(io, _openvt_pkg_row(r...))
    end
    print(io, "\n## Pending\n\n")
    pend = String[]
    push!(pend,
        "- O1 per-cell time series, `Monolayer/centroids/<case>/potts_<case>_s<seed>_<MCS:06d>.csv` " *
        "(`x,y,i,n` per save): the records keep per-save metrics only, and the " *
        "current runners do not write per-cell files.")
    :O2 in present || push!(pend,
        "- O2 Figure 5 snapshots, `Monolayer/Potts.jl_5T_MonolayerGrowth_1000_Data/` " *
        "(`x,y,r,f,a`, 100 runs of case (b)): the Figure 5 runner writes them to `F5_O2_DIR` " *
        "(default `./o2`), and they are kept out of git (D-168); the record holds their per-run sums " *
        "and the histograms.")
    push!(pend,
        "- A3 inhibition shares over time, `Monolayer/metrics/<case>/inhibition_s<seed>.csv` (cases (a), (e)): " *
        "not in the records; in the uninhibited case (a) every cell grows (g = 1 at every save).")
    for (key, f) in ((:O3b, "Potts.jl_time_to_10k_vs_beta.csv"), (
        :O3g, "Potts.jl_time_to_10k_vs_gamma.csv"))
        key in present && continue
        push!(pend,
            "- O3 Figure 6 / Table 1, `Monolayer/$f`: " *
            (haskey(recs, :sweeps) ? "not in the sweeps record." :
             "$(_OPENVT_PKG_PARKED); the protocol and targets are frozen."))
    end
    :O5 in present || push!(pend,
        "- O5 Figure 7 snapshots, `Monolayer/final_snapshot_data/`: " *
        (haskey(recs, :sweeps) ? "not in the sweeps record." : "$(_OPENVT_PKG_PARKED)."))
    print(io, join(pend, "\n"), "\n")
    print(io, """

    ## Records

    | Record | Results | Commit | Machine | Threads |
    |---|---|---|---|---|
    """)
    for k in _openvt_pkg_keys(recs)
        p = prov[k]
        print(io, "| `", recs[k], "` | ", _OPENVT_PKG_FIGURES[k], " | `",
            p["commit"][1:8], "` | ", get(p, "cpu", ""), " | ",
            _openvt_pkg_threads(p), " |\n")
    end
    print(
        io, """

  The records are in `lib/PottsModels/reproductions/data/15/` of $(_OPENVT_PKG_URL); how to
  rerun them is in `implementations/Potts.jl/README.md`.
  """)
    return String(take!(io))
end
