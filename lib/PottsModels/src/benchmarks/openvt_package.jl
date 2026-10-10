# The OpenVT monolayer submission package (spec 15 §4.0.1; P6.15j, D-180, D-204, D-206): the
# `implementations/Potts.jl/` and `results/Potts.jl/` trees of the consortium layout, built
# from the committed D-146 records under `reproductions/data/15/` and the bulk directory (the
# O1 archives and O2 files, too large for git, whose sha256s the P6.15j record pins). No
# simulation runs here.
#
# Determinism: every file is a function of the records, the bulk files, the sources and the
# model defaults only. Records, cases, seeds and rows are visited in sorted order, TOML is
# printed with sorted keys, bulk files are copied byte for byte, and nothing reads the clock,
# the host or an absolute path.

const _OPENVT_PKG_DATA = normpath(joinpath(@__DIR__, "..", "..", "reproductions", "data", "15"))
const _OPENVT_PKG_SRC = normpath(joinpath(@__DIR__, ".."))
const _OPENVT_PKG_URL = "https://github.com/PraneethMerugu/Potts.jl"
const _OPENVT_PKG_SPEC = "docs/design/research/model-specs/15_openvt_monolayer.md"
const _OPENVT_PKG_GRID = 39                   # save cadence of the monolayer records (D-173)
const _OPENVT_PKG_CASES = ("a", "b", "e", "f")
const _OPENVT_PKG_LAMBDAS = (1, 2, 3, 5)
# A3 (spec §4.0): cases (a) and (e), and the sweep cases (c), (d) where the O1 record has them
const _OPENVT_PKG_A3 = ("a", "e")
const _OPENVT_PKG_A3_SWEEPS = ("c", "d")
const _OPENVT_PKG_BULK_ENV = "OPENVT_PACKAGE_BULK"

"""
    PottsModels.OPENVT_FRAMEWORK_TOKEN

The framework token of the Potts.jl entry in the OpenVT consortium repository (D-215 (9)):
the folder name under `implementations/` and `results/` and the stem of every file name
that carries one. No spaces (the consortium's `run_metrics.sh` splits on them). The
checkerboard entry of D-214 will use `"Potts.jl_checkerboard"`.
"""
const OPENVT_FRAMEWORK_TOKEN = "Potts.jl"
const _OPENVT_PKG_FW = OPENVT_FRAMEWORK_TOKEN

"""
    PottsModels.OPENVT_BULK_RELEASE_TAG

The tag of the public Potts.jl release that is to hold the bulk files of the split
OpenVT package (D-213 (b)); the core README and `EMAIL.md` link each bulk file as
`https://github.com/PraneethMerugu/Potts.jl/releases/download/<tag>/<file>`. Nothing creates
the release: the maintainer creates it under this tag (or rebuilds with another
`release_tag`).
"""
const OPENVT_BULK_RELEASE_TAG = "openvt-monolayer-submission-2026-10-10"

# the sweeps record's O3 tables (record names) => the package names (D-215: the token)
const _OPENVT_PKG_O3 = ("Potts.jl_time_to_10k_vs_beta.csv" => "$(_OPENVT_PKG_FW)_time_to_10k_vs_beta.csv",
    "Potts.jl_time_to_10k_vs_gamma.csv" => "$(_OPENVT_PKG_FW)_time_to_10k_vs_gamma.csv")
# D-215 (5): descriptive O1 zip stems per case, members `<stem>/s<seed>/potts_<case>_s<seed>_<MCS:06d>.csv`
const _OPENVT_PKG_O1_STEM = Dict("a" => "$(_OPENVT_PKG_FW)_beta0.0_gamma0.0", "b" => "$(_OPENVT_PKG_FW)_No_CI_stochastic",
    "e" => "$(_OPENVT_PKG_FW)_beta0.8_gamma0.0", "f" => "$(_OPENVT_PKG_FW)_No_CI_deterministic")
_openvt_pkg_o1_zip(case) = _OPENVT_PKG_O1_STEM[case] * ".zip"
# D-215 (3): the O2 files, zipped with their folder, k = 0…99
const _OPENVT_PKG_O2_DIR = "$(_OPENVT_PKG_FW)_5T_MonolayerGrowth_1000_Data"
const _OPENVT_PKG_O2_ZIP = _OPENVT_PKG_O2_DIR * ".zip"
const _OPENVT_PKG_O1_MANIFEST = "$(_OPENVT_PKG_FW)_centroids_manifest.csv"
const _OPENVT_PKG_TABLE1 = "$(_OPENVT_PKG_FW)_table1.csv"
# the bulk side of the split (D-215 (7)): file names in results/<token>/Monolayer/
_openvt_pkg_isbulk(name) = name in (_OPENVT_PKG_O2_ZIP, _OPENVT_PKG_O1_MANIFEST) || name in (_openvt_pkg_o1_zip(c) for c in keys(_OPENVT_PKG_O1_STEM))
const _OPENVT_PKG_RELEASES = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"
# the O5 names of the P6.15g record (`string(γ)`, e.g. 0.0, 0.12, 1.0e-4), β = 0
const _OPENVT_PKG_O5 = r"^Potts\.jl_gamma_(\d+\.\d+(?:e-?\d+)?)_(\d+)MCS\.csv$"
# the Figure 8 colonies of the P6.15k record (D-211 R2; `openvt_filename(:O5; beta, mcs)`), γ = 0
const _OPENVT_PKG_O5_BETA = r"^Potts\.jl_beta_(\d+\.\d+(?:e-?\d+)?)_(\d+)MCS\.csv$"
# the package name of an O5 colony (D-215 (4)): both parameters, as TST and CC3D name theirs
_openvt_pkg_o5_name(beta, gamma, mcs) = "$(_OPENVT_PKG_FW)_beta_$(beta)_gamma_$(gamma)_$(mcs)MCS.csv"
# M's shared Figure 5 distance-bin edges (9 Oct 2026 draft; D-211 R4), in R
const _OPENVT_PKG_F5_EDGES = (0.0, 18.6, 37.2, 55.8, 74.4, 93.0)
# what the decipher pass found about M's Figure 5 unit (spec 15 §7 Q15, 2026-10-10)
const _OPENVT_PKG_F5_UNIT = "M's axis is consistent with distance in units of R/2 (fitted 1.84–2.23 units per R across all nine consortium rows); the unit and origin are Q15 on our open question list"
# scripts that need a local clone of the consortium repository stay out of the package
const _OPENVT_PKG_NEEDS_G = "OPENVT_MONOLAYER_REPO"

# ROADMAP item => what its record carries (P6.15i convention: `provenance.toml`'s `item`)
const _OPENVT_PKG_ITEMS = (calib = "P6.15b", f5 = "P6.15e", f3f8 = "P6.15f", f1f4 = "P6.15h", sweeps = "P6.15g",
    o1 = "P6.15j", f8beta = "P6.15k", o1g = "P6.15l")
const _OPENVT_PKG_FIGURES = (calib = "Figure 2, Table S5", f5 = "Figure 5", f3f8 = "Figures 3 and 9",
    f1f4 = "Figures 1 and 4", sweeps = "Figure 6, Table 1, Figure 7",
    o1 = "O1 per-cell time series (cases a, b, e, f re-run), O2 files",
    f8beta = "Figure 8 (the colonies at the T1 β values, area inhibition)",
    o1g = "O1 and O2 in the consortium scripts' form (column g, descriptive zips, O2 k = 0…99; no re-run)")
# records a draft build may do without (`allow_pending = true`): the P6.15k β colonies run on
# the PC after the rest is merged; a draft leaves out Figure 8 and its O5 files and says
# "Figure 8: pending". The default build requires them, so a build for upload is complete.
const _OPENVT_PKG_LATER = (:f8beta,)

"""
    PottsModels.openvt_submission_package(outdir::AbstractString;
                                          bulk = get(ENV, "OPENVT_PACKAGE_BULK", nothing),
                                          allow_pending::Bool = false,
                                          split = nothing,
                                          release_tag = PottsModels.OPENVT_BULK_RELEASE_TAG)

Build the Potts.jl submission to the OpenVT growing-monolayer benchmark in the consortium
repository's layout (spec 15 §4.0.1, conforming to the consortium's scripts per D-215). The
framework token `<FW>` is `PottsModels.OPENVT_FRAMEWORK_TOKEN`.

With `split = nothing` (the default) it writes `outdir/implementations/<FW>/` (the
`@potts_model` sources, the record runners, a README on rerunning everything, and
`parameters.csv`) and `outdir/results/<FW>/` (the O4 relaxation widths and Table S5, the O6
metrics per run with their replicate means and neighbour histograms, the bare Fig 1 panel as
`closeup.png`, each record's provenance without its host name, Table 1 as a CSV, and a README
with the units, seeds, the notes for the consortium scripts and the deviations table), plus
the bulk items: the O1 per-cell time series (`x,y,i,n,g`) as one descriptively named zip per
case with their manifest, the A3 inhibition shares derived from that manifest, the O2
Figure 5 zip (k = 0…99), and the O3 and O5 sweep files. It returns `outdir`.

With `split = :email` it writes the same package, split for sending by mail (D-213 (a)–(d)):
`outdir/core.zip` (every file except the bulk ones, unpacking at the consortium
repository's root; its results README links each bulk file by name, sha256 and its
release-download URL under `release_tag`), `outdir/bulk/` (the O1 zips, the O2 zip and the O1
manifest, byte copies, to be attached to a public release; nothing here creates one) and
`outdir/EMAIL.md` (a plain-text draft cover note). It returns
`(; outdir, core_bytes, bulk_bytes, bulk)` with the size of `core.zip`, the summed size of
`bulk/` and the bulk file sizes. Any other `split` is an `ArgumentError`.

Everything is read from the committed records under `lib/PottsModels/reproductions/data/15/`
(D-146), the model defaults and the bulk directory; nothing is simulated. An item's record is
the newest directory (by name) whose `provenance.toml` names its ROADMAP item. Every record
(P6.15b, e, f, g, h, j, k and l) is required. `allow_pending = true` (default `false`) allows a
draft build without the P6.15k record (M's Figure 8 colonies, D-211): Figure 8 and its O5
files are left out and the results README says "Figure 8: pending". Never upload a draft build.

`results/<FW>/figures/` holds byte copies of the records' renders of M's Figures 5
(`fig5_shared.png`), 7 (`fig7_grid.png`) and 8 (`fig8_grid.png`).

`bulk` is a directory outside git holding the O1 zips and the O2 zip that the P6.15l
record's `archives.tsv` names (written by its `post_o1.jl`), each with the size and sha256
pinned there. Nothing else is read from it, and its files are copied byte for byte.

Two calls on the same commit and bulk directory write byte-identical files (zip time stamps
are fixed, not read from the clock). `outdir` must lie outside any git checkout (the package
is not committed) and must not exist or be an empty directory; `bulk` must be given, be a
directory outside git and hold the pinned bytes; otherwise this is an `ArgumentError`, raised
before anything is written. A build that fails part-way removes what it wrote, so the same
`outdir` can be used again.
"""
function openvt_submission_package(outdir::AbstractString; bulk = get(ENV, _OPENVT_PKG_BULK_ENV, nothing),
        allow_pending::Bool = false, split = nothing, release_tag::AbstractString = OPENVT_BULK_RELEASE_TAG)
    split === nothing || split === :email ||
        throw(ArgumentError("openvt_submission_package: split must be nothing or :email, not $(repr(split))"))
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", release_tag) ||
        throw(ArgumentError("openvt_submission_package: release_tag $(repr(release_tag)) is not a valid tag"))
    out = abspath(outdir)
    _openvt_pkg_in_git(out) &&
        throw(ArgumentError("openvt_submission_package: $outdir is inside a git checkout; build the package outside git"))
    existed = ispath(out)
    if existed
        isdir(out) || throw(ArgumentError("openvt_submission_package: $outdir exists and is not a directory"))
        isempty(readdir(out)) || throw(ArgumentError("openvt_submission_package: $outdir is not empty"))
    end
    split === :email && return _openvt_pkg_split(outdir, out, existed, bulk, allow_pending, release_tag)
    recs = _openvt_pkg_records()
    for k in keys(_OPENVT_PKG_ITEMS)
        haskey(recs, k) || (allow_pending && k in _OPENVT_PKG_LATER) ||
            throw(ArgumentError("openvt_submission_package: no $(_OPENVT_PKG_ITEMS[k]) record in data/15" *
                                (k in _OPENVT_PKG_LATER ? " (pass allow_pending = true for a draft build without it)" : "")))
    end
    o1 = _openvt_pkg_o1(joinpath(_OPENVT_PKG_DATA, recs[:o1g]), recs[:o1],
        _openvt_pkg_o2_runs(joinpath(_OPENVT_PKG_DATA, recs[:f5])))
    bulkdir = _openvt_pkg_bulk(bulk, o1)
    try
        _openvt_pkg_build(out, recs, o1, bulkdir)
    catch
        _openvt_pkg_clean(out, existed)
        rethrow()
    end
    return outdir
end

function _openvt_pkg_clean(out, existed)
    if existed
        foreach(f -> rm(joinpath(out, f); recursive = true, force = true), readdir(out))
    else
        rm(out; recursive = true, force = true)
    end
    return nothing
end

function _openvt_pkg_build(out, recs, o1, bulk)
    impl = joinpath(out, "implementations", _OPENVT_PKG_FW)
    res = joinpath(out, "results", _OPENVT_PKG_FW)
    mkpath(impl)
    mkpath(res)
    rec(k) = joinpath(_OPENVT_PKG_DATA, recs[k])
    prov = Dict(k => TOML.parsefile(joinpath(rec(k), "provenance.toml")) for k in keys(recs))
    meta = Dict(k => (isfile(joinpath(rec(k), "meta.toml")) ? TOML.parsefile(joinpath(rec(k), "meta.toml")) :
                      Dict{String, Any}()) for k in keys(recs))
    facts = _openvt_pkg_facts(recs, meta)

    # implementations/Potts.jl
    mkpath(joinpath(impl, "src"))
    for f in ("openvt_reference.jl", "openvt_chain.jl")
        cp(joinpath(_OPENVT_PKG_SRC, f), joinpath(impl, "src", f))
    end
    scripts = Dict{Symbol, Vector{String}}()
    for k in _openvt_pkg_keys(recs)
        dir = joinpath(impl, "scripts", recs[k])
        mkpath(dir)
        scripts[k] = _openvt_pkg_scripts(rec(k))
        for f in scripts[k]
            cp(joinpath(rec(k), f), joinpath(dir, f))
        end
    end
    _openvt_pkg_write(joinpath(impl, "parameters.csv"), _openvt_pkg_parameters(facts))
    _openvt_pkg_write(joinpath(impl, "README.md"), _openvt_pkg_impl_readme(recs, prov, scripts, facts))

    # results/Potts.jl
    cp(joinpath(rec(:f1f4), "fig1_panel.png"), joinpath(res, "closeup.png"))
    mkpath(joinpath(res, "provenance"))
    for k in _openvt_pkg_keys(recs)
        p = copy(prov[k])
        delete!(p, "hostname"); delete!(p, "work")
        _openvt_pkg_write(joinpath(res, "provenance", recs[k] * ".toml"), sprint(io -> TOML.print(io, p; sorted = true)))
    end
    _openvt_pkg_relaxation(joinpath(res, "Relaxation"), rec(:calib), meta[:calib])
    _openvt_pkg_monolayer(joinpath(res, "Monolayer"), rec(:f3f8), facts.cycle)
    _openvt_pkg_bulk_items(joinpath(res, "Monolayer"), o1, bulk, facts.cycle)
    _openvt_pkg_sweeps(joinpath(res, "Monolayer"), rec(:sweeps))
    _openvt_pkg_table1(joinpath(res, "Monolayer", _OPENVT_PKG_TABLE1), rec(:sweeps))
    _openvt_pkg_figures(res, recs)
    _openvt_pkg_write(joinpath(res, "README.md"), _openvt_pkg_results_readme(recs, prov, meta, facts, o1))
    return nothing
end

# ── records and small I/O helpers ───────────────────────────────────────────────────────────

# the path with symbolic links resolved (through its nearest existing ancestor), so that a link
# into a checkout counts as inside it
function _openvt_pkg_real(path::AbstractString)
    d, rest = abspath(path), String[]
    while !ispath(d)
        pushfirst!(rest, basename(d))
        dirname(d) == d && break
        d = dirname(d)
    end
    return joinpath(ispath(d) ? realpath(d) : d, rest...)
end

function _openvt_pkg_in_git(path::AbstractString)
    d = _openvt_pkg_real(path)
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

# a record's scripts, without those that read a consortium clone
function _openvt_pkg_scripts(dir)
    fs = filter(f -> endswith(f, ".jl") && isfile(joinpath(dir, f)), readdir(dir))
    return sort(filter(f -> !occursin(_OPENVT_PKG_NEEDS_G, read(joinpath(dir, f), String)), fs))
end

function _openvt_pkg_write(path, text::AbstractString)
    mkpath(dirname(path))
    write(path, text)
    return path
end

_openvt_pkg_lines(path) = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))

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

# ── facts: model defaults and record values used in the READMEs ────────────────────────────

# the parameter defaults of `OpenVTReferenceMonolayer` (Table S1), read from the model
function _openvt_pkg_defaults()
    sys = mtkcompile(OpenVTReferenceMonolayer(; name = :openvt_package, lattice = (24, 24)))
    p = PottsProblem(sys, openvt_reference_state(; lattice = (24, 24)), (0, 1); capacity = 4).p
    # kinds (medium, cell): J[2, 2] is cell–cell, J[1, 2] cell–medium
    return (; A0 = p.A₀, lambda = p.λ, T = p.T, alpha = p.α, mu_X = p.μ_X, sigma_X = p.σ_X, beta = p.β, gamma = p.γ,
        J_cc = p.J[2, 2], J_cm = p.J[1, 2])
end

_openvt_pkg_guard(s) = (m = match(r"edge_guard\((\d+)", s); m === nothing ? nothing : parse(Int, m.captures[1]))

function _openvt_pkg_facts(recs, meta)
    d = _openvt_pkg_defaults()
    m3 = meta[:f3f8]
    cycle = Int(get(m3, "cycle_mcs", round(Int, d.A0 / d.alpha)))
    lattices = sort(unique([m3["cases"][c]["lattice"] for c in _OPENVT_PKG_CASES]))
    lattice_of(n) = sort(unique([m3["cases"][c]["lattice"] for c in _OPENVT_PKG_CASES if m3["cases"][c]["cells"] == n]))
    # the closest any recorded monolayer run came to the lattice edge
    gaps = Int[]
    for k in (:f5, :f3f8)
        _, rows = _openvt_pkg_tsv(joinpath(_OPENVT_PKG_DATA, recs[k], "runs.tsv"))
        append!(gaps, (parse(Int, r["edge_gap_px"]) for r in rows if haskey(r, "edge_gap_px")))
    end
    _, v3 = _openvt_pkg_tsv(joinpath(_OPENVT_PKG_DATA, recs[:f3f8], "verdicts.tsv"))
    f34 = findfirst(r -> startswith(r["target"], "F3.4") && r["case"] == "f", v3)
    m1 = meta[:f1f4]
    return (; defaults = d, cycle, R = sqrt(d.A0 / pi), CD = meta[:calib]["CD_px"], T2 = meta[:calib]["T_ours"]["2"],
        guard = _openvt_pkg_guard(get(m3, "edge_guard", "")), lattices, small = lattice_of(1000),
        large = lattice_of(10000), min_gap = isempty(gaps) ? nothing : minimum(gaps),
        f34 = f34 === nothing ? nothing : (ours = _openvt_pkg_f(v3[f34]["ours"]), band = v3[f34]["band"]),
        window = m1["window"], closeup = (case = m1["case"], run = m1["run"], seed = m1["seed"], N = m1["N"],
            mcs = m1["mcs"], cells = m1["window_cells"], medium = m1["window_medium_sites"]))
end

_openvt_pkg_g(x) = isinteger(x) ? string(Int(x)) : string(x)

# ── parameters.csv ─────────────────────────────────────────────────────────────────────────

function _openvt_pkg_parameters(facts)
    d = facts.defaults
    rows = Tuple{String, Any, String}[
        ("A0", d.A0, "px (A*(0); Table S1)"),
        ("lambda", d.lambda, "1 (area stiffness; Table S1)"),
        ("temperature", d.T, "1 (fluctuation amplitude T; Table S1)"),
        ("J_cell_cell", d.J_cc, "1 (Table S1)"),
        ("J_cell_medium", d.J_cm, "1 (Table S1)"),
        ("alpha", d.alpha, "px/MCS (reference-area growth rate; Table S1)"),
        ("mu_X", d.mu_X, "1 (mean division threshold X; mu_Amax = mu_X A0)"),
        ("sigma_X", d.sigma_X, "1 (SD of X; 0 in the deterministic case (f))"),
        ("beta", d.beta, "1 (type 1 threshold; by case)"),
        ("gamma", d.gamma, "1 (type 2 threshold; by case)"),
        ("cycle_MCS", Float64(facts.cycle), "MCS (one cell cycle 5T = A0/alpha)"),
        ("T_relax_lambda2_MCS", Float64(facts.T2), "MCS (mechanical time scale T at lambda = 2; Table S5)"),
        ("R_px", facts.R, "px (length unit R = sqrt(A0/pi); the initial cell radius)"),
        ("CD_px", Float64(facts.CD), "px (cell diameter in the relaxation files)"),
        ("save_interval_MCS", Float64(_OPENVT_PKG_GRID), "MCS (monolayer saves)"),
    ]
    facts.guard === nothing ||
        push!(rows, ("edge_guard_sites", Float64(facts.guard), "sites (a run stops if a cell comes this close to the lattice edge)"))
    length(facts.small) == 1 && push!(rows, ("lattice_1000_cells", Float64(only(facts.small)), "sites per side"))
    length(facts.large) == 1 && push!(rows, ("lattice_10000_cells", Float64(only(facts.large)), "sites per side"))
    append!(rows, [
        ("neighbourhood", "Moore(1)", "- (energy and copy-attempt neighbourhood)"),
        ("boundary", "closed", "- (no wrap; see the edge guard)"),
        ("algorithm", "SequentialCPM", "- (random-site Metropolis sweep; 1 MCS = one attempt per site)"),
        ("division_plane", "random", "- (RandomPlane)"),
    ])
    io = IOBuffer()
    print(io, "name,value,unit\n")
    for (n, v, u) in rows
        print(io, n, ',', v isa AbstractString ? v : _openvt_float(v), ',', replace(u, ',' => ';'), '\n')
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

function _openvt_pkg_monolayer(dir, rec, cycle)
    ts = _openvt_pkg_timeseries(rec)
    _, nb = _openvt_pkg_tsv(joinpath(rec, "neighbors.tsv"))
    for case in _OPENVT_PKG_CASES
        seeds = sort([s for (c, s) in keys(ts) if c == case])
        for s in seeds
            rows = [(Int(v[1]), v[1] / cycle, v[2:7]...) for v in ts[(case, s)]]
            _openvt_pkg_csv(joinpath(dir, "metrics", case, "measurements_s$(s).csv"), "MCS,t,N,R,A,C,w,g", rows)
        end
        # the replicate mean (schema "Data Collection"): MCS on the save grid saved by every run
        grids = [Set(Int(v[1]) for v in ts[(case, s)] if Int(v[1]) % _OPENVT_PKG_GRID == 0) for s in seeds]
        grid = isempty(grids) ? Int[] : sort(collect(reduce(intersect, grids)))
        byrun = [Dict(Int(v[1]) => v for v in ts[(case, s)]) for s in seeds]
        mrows = Vector{Tuple}()
        for m in grid
            row = Any[m, m / cycle]
            for j in 2:7
                vals = filter(!isnan, [b[m][j] for b in byrun])
                push!(row, isempty(vals) ? NaN : sum(vals) / length(vals))
            end
            push!(row, length(seeds))
            push!(mrows, Tuple(row))
        end
        _openvt_pkg_csv(joinpath(dir, "metrics", "measurements_$(case)_mean.csv"), "MCS,t,N,R,A,C,w,g,runs", mrows)
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

# ── bulk and sweep items (D-204): the O1 archives and their manifest, A3, O2, O3, O5 ──────────

_openvt_pkg_sha(path) = bytes2hex(open(sha256, path))

# the P6.15j record's manifests: O1 members by case (in member order), archives, O2 files
# the case (b) runs of the P6.15e record: k => seed
function _openvt_pkg_o2_runs(rec)
    _, rows = _openvt_pkg_tsv(joinpath(rec, "runs.tsv"))
    return Dict(parse(Int, r["k"]) => parse(Int, r["seed"]) for r in rows if r["case"] == "b")
end

# the P6.15l record (the D-215 post-processing of the P6.15j record `raw`): O1 members by case
# (in member order), the archives (O1 per case and the O2 zip), the O2 files
function _openvt_pkg_o1(rec, raw, o2runs)
    need(f) = (p = joinpath(rec, f); isfile(p) ? _openvt_pkg_tsv(p)[2] :
                                     throw(ArgumentError("openvt_submission_package: the P6.15l record has no $f")))
    src = get(TOML.parsefile(joinpath(rec, "provenance.toml")), "source", "")
    src == raw || throw(ArgumentError("openvt_submission_package: the P6.15l record maps $(repr(src)), not the P6.15j record $raw"))
    members = Dict{String, Vector{Any}}()
    for r in need("o1_manifest.tsv")
        e = (; case = r["case"], seed = parse(Int, r["seed"]), mcs = parse(Int, r["mcs"]), file = r["file"],
            rows = parse(Int, r["rows"]), bytes = r["bytes"], i = Tuple(parse(Int, r["i$(k)"]) for k in 0:3),
            sha = r["sha256"])
        push!(get!(members, e.case, Any[]), e)
    end
    foreach(v -> sort!(v; by = e -> e.file), values(members))
    rows = need("archives.tsv")
    archives = sort(filter(r -> r["case"] != "O2", rows); by = r -> r["case"])
    o2zip = filter(r -> r["case"] == "O2", rows)
    o2 = sort(need("o2_manifest.tsv"); by = r -> parse(Int, r["k"]))
    ok = !isempty(archives) && sort([r["case"] for r in archives]) == sort(collect(keys(members))) &&
         all(r -> haskey(_OPENVT_PKG_O1_STEM, r["case"]) && r["archive"] == _openvt_pkg_o1_zip(r["case"]) &&
                   parse(Int, r["members"]) == length(members[r["case"]]), archives) &&
         length(o2zip) == 1 && only(o2zip)["archive"] == _OPENVT_PKG_O2_ZIP &&
         parse(Int, only(o2zip)["members"]) == length(o2) &&
         [parse(Int, r["k"]) + 1 for r in o2] == sort(collect(keys(o2runs))) &&
         all(r -> r["file"] == "$(_OPENVT_PKG_O2_DIR)/cell_data_no_inhibition_$(r["k"]).csv", o2)
    ok || throw(ArgumentError("openvt_submission_package: the P6.15l record's manifests are incomplete: archives.tsv " *
                              "must list one zip per case of o1_manifest.tsv with its member count and the O2 zip, " *
                              "and o2_manifest.tsv one file per case (b) run of the P6.15e record (k = run − 1)"))
    return (; members, archives, o2zip = only(o2zip), o2, o2runs, cases = sort(collect(keys(members))))
end

# the bulk directory, checked against the record's manifests before anything is written
function _openvt_pkg_bulk(bulk, o1)
    (bulk === nothing || isempty(bulk)) &&
        throw(ArgumentError("openvt_submission_package: no bulk directory; pass `bulk` or set $(_OPENVT_PKG_BULK_ENV) " *
                            "to the directory holding the O1 zips and the O2 zip"))
    dir = abspath(bulk)
    isdir(dir) || throw(ArgumentError("openvt_submission_package: the bulk directory $bulk does not exist"))
    _openvt_pkg_in_git(dir) &&
        throw(ArgumentError("openvt_submission_package: the bulk directory $bulk is inside a git checkout"))
    for r in [o1.archives; o1.o2zip]
        f = r["archive"]
        p = joinpath(dir, f)
        isfile(p) || throw(ArgumentError("openvt_submission_package: the bulk directory lacks $f (written by the P6.15l record's post_o1.jl)"))
        (string(filesize(p)) == r["bytes"] && _openvt_pkg_sha(p) == r["sha256"]) ||
            throw(ArgumentError("openvt_submission_package: $f in the bulk directory differs from the P6.15l record's sha256"))
    end
    return dir
end

function _openvt_pkg_bulk_items(dir, o1, bulk, cycle)
    mkpath(dir)
    # O1: the zips, byte for byte, and the package manifest in archive and member order
    foreach(r -> cp(joinpath(bulk, r["archive"]), joinpath(dir, r["archive"])), o1.archives)
    _openvt_pkg_csv(joinpath(dir, _OPENVT_PKG_O1_MANIFEST), "archive,file,rows,bytes,sha256",
        [(_openvt_pkg_o1_zip(c), e.file, string(e.rows), e.bytes, e.sha) for c in o1.cases for e in o1.members[c]])
    # A3: the inhibition-code shares of every O1 save, from the manifest's counts
    for c in o1.cases
        (c in _OPENVT_PKG_A3 || c in _OPENVT_PKG_A3_SWEEPS) || continue
        for s in sort(unique(e.seed for e in o1.members[c]))
            rows = [(e.mcs, e.mcs / cycle, (k / e.rows for k in e.i)...)
                    for e in sort(filter(e -> e.seed == s, o1.members[c]); by = e -> e.mcs)]
            _openvt_pkg_csv(joinpath(dir, "metrics", c, "inhibition_s$(s).csv"), "MCS,t,f0,f1,f2,f3", rows)
        end
    end
    # O2: the Figure 5 zip of case (b), byte for byte
    cp(joinpath(bulk, o1.o2zip["archive"]), joinpath(dir, o1.o2zip["archive"]))
    return nothing
end

# O3 and O5: byte copies of the P6.15g sweeps record's tables and its f7/ snapshots (β = 0)
function _openvt_pkg_sweeps(dir, sw)
    mkpath(dir)
    for (f, name) in _OPENVT_PKG_O3
        isfile(joinpath(sw, f)) || throw(ArgumentError("openvt_submission_package: the sweeps record has no $f"))
        cp(joinpath(sw, f), joinpath(dir, name))
    end
    _openvt_pkg_copyall(joinpath(sw, "f7"), joinpath(dir, "final_snapshot_data"), _OPENVT_PKG_O5,
        m -> _openvt_pkg_o5_name("0.0", m[1], m[2])) ||
        throw(ArgumentError("openvt_submission_package: the sweeps record has no f7/ snapshots"))
    return nothing
end

# Table 1 (D-215 (6)) from the sweeps record's table1.tsv, row for row; "—" is NaN and the
# bands are split into their two edges
function _openvt_pkg_table1(path, sw)
    p = joinpath(sw, "table1.tsv")
    isfile(p) || throw(ArgumentError("openvt_submission_package: the sweeps record has no table1.tsv"))
    _, rows = _openvt_pkg_tsv(p)
    num(x) = (x = strip(x); x in ("", "—") ? "NaN" : x)
    edges(x) = (m = match(r"^\[\s*([^,\]]+?)\s*,\s*([^\]]+?)\s*\]$", strip(x)); m === nothing ? ("NaN", "NaN") : (m[1], m[2]))
    io = IOBuffer()
    print(io, "parameter,multiple,threshold,tau_cycles,interpolated,TST,Artistoo,spread_lo,spread_hi,band_lo,band_hi\n")
    for r in rows
        print(io, join((r["parameter"], num(r["multiple"]), num(r["threshold"]), num(r["tau_cycles"]),
            num(r["interpolated"]), num(r["TST"]), num(r["Artistoo"]), edges(r["spread"])..., edges(r["band"])...), ','), '\n')
    end
    return _openvt_pkg_write(path, String(take!(io)))
end

# M's Figures 5, 7 and 8 (D-211): byte copies of the records' renders, and the Figure 8
# colonies (O5) of the P6.15k record
function _openvt_pkg_figures(res, recs)
    mkpath(joinpath(res, "figures"))
    for (k, f, name) in ((:f5, "fig5_shared.png", "fig5.png"), (:sweeps, "fig7_grid.png", "fig7.png"),
        (:f8beta, "fig8_grid.png", "fig8.png"))
        haskey(recs, k) || continue
        src = joinpath(_OPENVT_PKG_DATA, recs[k], f)
        isfile(src) || throw(ArgumentError("openvt_submission_package: the $(_OPENVT_PKG_ITEMS[k]) record has no $f"))
        cp(src, joinpath(res, "figures", name))
    end
    if haskey(recs, :f8beta)
        _openvt_pkg_copyall(joinpath(_OPENVT_PKG_DATA, recs[:f8beta], "f8"), joinpath(res, "Monolayer", "final_snapshot_data"),
            _OPENVT_PKG_O5_BETA, m -> _openvt_pkg_o5_name(m[1], "0.0", m[2])) || throw(ArgumentError("openvt_submission_package: the P6.15k record has no f8/ snapshots"))
    end
    return nothing
end

# copy the files of `src` whose names match `re`, each to `dst/name(match)`
function _openvt_pkg_copyall(src, dst, re, name::F) where {F}
    isdir(src) || return false
    fs = sort(filter(f -> occursin(re, f) && isfile(joinpath(src, f)), readdir(src)))
    isempty(fs) && return false
    mkpath(dst)
    foreach(f -> cp(joinpath(src, f), joinpath(dst, name(match(re, f)))), fs)
    return true
end

# ── implementations README ────────────────────────────────────────────────────────────────

_openvt_pkg_threads(p) = get(p, "threads", 1)

function _openvt_pkg_wall(p)
    s = get(p, "wall_s", nothing)
    s === nothing && return "—"
    s < 120 && return @sprintf("%.0f s", s)
    s < 7200 && return @sprintf("%.0f min", s / 60)
    return @sprintf("%.1f h", s / 3600)
end

function _openvt_pkg_impl_readme(recs, prov, scripts, facts)
    d = facts.defaults
    g = _openvt_pkg_g
    io = IOBuffer()
    print(io, """
    # Potts.jl: OpenVT growing monolayer

    The Potts.jl implementation of the OpenVT growing-monolayer benchmark: a cellular Potts
    model (CPM) with the Table S1 parameters, written in the `@potts_model` authoring
    surface of [Potts.jl]($(_OPENVT_PKG_URL)). Every result under `results/$(_OPENVT_PKG_FW)/` was
    produced by the scripts below at the commits listed, and the result files were built from
    the committed run records by `PottsModels.openvt_submission_package`.

    ## Contents

    | Path | What it is |
    |---|---|
    | `src/openvt_reference.jl` | `OpenVTReferenceMonolayer`, the monolayer model (Table S1), and `openvt_reference_state`, the one-cell disc start |
    | `src/openvt_chain.jl` | `OpenVTChain`, the 1D chain model of the mechanical calibration (Figure 2, Table S5), with `openvt_chain` and `openvt_release` |
    | `parameters.csv` | every parameter and Potts.jl setting used, with units |
    | `scripts/<record>/` | the runner, plotting and video scripts of each run record, unchanged |

    Both model files are copies of `lib/PottsModels/src/` in the Potts.jl repository, where
    they are part of the `PottsModels` package (`using PottsModels`).

    ## The model in brief

    - Hamiltonian: area constraint `λ (A − A*)²` with λ = $(g(d.lambda)), plus adhesion `J`
      over Moore(1) pairs (cell–cell $(g(d.J_cc)), cell–medium $(g(d.J_cm))), temperature
      T = $(g(d.T)), Metropolis acceptance, one copy attempt per lattice site per MCS
      (`SequentialCPM` with `Moore(1)` proposals).
    - Growth: every growing cell's target area A* increases by α = A*(0)/$(facts.cycle) px per
      MCS (A*(0) = $(g(d.A0)) px), so one cell cycle is 5T = $(facts.cycle) MCS.
    - Division: when the actual area reaches `X · A*(0)`, along a random plane. Both
      daughters take half the mother's A* and draw their own X ~ N($(g(d.mu_X)), $(g(d.sigma_X))),
      redrawn while X ≤ 0 (`σ_X = 0` gives the deterministic X ≡ $(g(d.mu_X)) of case (f)).
    - Inhibition: a cell grows only while `a = A/A* ≥ β` (else it is type-1 inhibited) and
      its free-surface fraction `f ≥ γ` (else type-2 inhibited); f is the share of the cell's
      unlike Moore(1) contact pairs that face medium.
    - Start: one disc of radius R = √(A*(0)/π) at the lattice centre, on a closed lattice
      with an edge guard (a run stops if a cell comes within $(facts.guard) sites of the edge).

    ## Install

    Potts.jl needs Julia 1.12 or newer.

    ```sh
    git clone $(_OPENVT_PKG_URL).git
    cd Potts.jl
    julia --project=lib/PottsModels/test -e 'using Pkg; Pkg.instantiate()'
    ```

    Every command below runs from the repository root in that test environment,
    `--project=lib/PottsModels/test`, which holds `Potts`, `PottsModels` and the plotting
    packages, unless a script's header names another one.

    ## Run the model

    ```julia
    using Potts, PottsModels
    sys = mtkcompile(OpenVTReferenceMonolayer(; name = :monolayer, lattice = (400, 400)))
    prob = PottsProblem(sys, openvt_reference_state(; lattice = (400, 400)), (0, $(facts.cycle)); capacity = 2000)
    sol = solve(prob, SequentialCPM())
    ```

    ## Rerun the records

    Each record lives in `lib/PottsModels/reproductions/data/15/<record>/` of the repository;
    `scripts/<record>/` here holds its scripts. A runner reruns the protocol of the record's
    acceptance test (`lib/PottsModels/test/reproductions/15_openvt_*.jl`) from that file's
    source, so it must be run inside a checkout, ideally at the record's commit
    (`git checkout <commit>`).

    The results are reproducible in distribution: a rerun with the stated seeds, Julia
    version and package versions gives statistically equivalent results, judged by the same
    acceptance tests. Individual values need not match the records exactly, since they can
    depend on the thread count, the machine and the package versions resolved at install
    (the repository ships no Manifest).

    | Record | Results | Runner | Commit | Threads | Wall time | Command |
    |---|---|---|---|---|---|---|
    """)
    for k in _openvt_pkg_keys(recs)
        r, p = recs[k], prov[k]
        runner = basename(p["runner"])
        print(io, "| `", r, "` | ", _OPENVT_PKG_FIGURES[k], " | `scripts/", r, "/", runner, "` | `", p["commit"][1:8],
            "` | ", _openvt_pkg_threads(p), " | ", _openvt_pkg_wall(p), " | `", k in (:o1, :o1g) ? "OPENVT_PACKAGE_BULK=../openvt-bulk " : "",
            "julia -t ", _openvt_pkg_threads(p),
            " --project=lib/PottsModels/test ", p["runner"], "` |\n")
    end
    print(io, """

    The other scripts of a record are listed below; each one's header says what it does and
    how to run it. `plot_*.jl` redraw the figures from the record's own data files,
    `video_*.jl` rerun run 1 of each case to render the videos (not part of this package), and
    `probe_causes.jl` reruns the cause probes quoted in the V4 rows.

    """)
    for k in _openvt_pkg_keys(recs)
        others = filter(!=(basename(prov[k]["runner"])), scripts[k])
        isempty(others) && continue
        print(io, "- `scripts/", recs[k], "/`: ", join(("`$f`" for f in others), ", "), "\n")
    end
    print(io, """

    The wall times above are those of the recorded runs; the exact machine, Julia version
    and timings of each run are in `results/$(_OPENVT_PKG_FW)/provenance/`.

    The O1 runner (`scripts/$(recs[:o1])/$(basename(prov[:o1]["runner"]))`) also needs
    `OPENVT_PACKAGE_BULK`, a directory outside git: it writes the O1 archives and the O2 files
    there, checks every run against the Figure 3/9 record save by save, and commits only their
    manifests (names, row counts, sizes, sha256) to the record. The post-processing script
    (`scripts/$(recs[:o1g])/$(basename(prov[:o1g]["runner"]))`) reads those files from the same
    directory and writes the files of this package next to them, with no re-run: the O1 files
    with the column `g` added, in one descriptively named zip per case, and the O2 files
    renumbered k = 0…99 in one zip. Its record pins their sha256s.

    ## Rebuild this package

    ```sh
    OPENVT_PACKAGE_BULK=../openvt-bulk julia --project=lib/PottsModels/test \\
        -e 'using PottsModels; PottsModels.openvt_submission_package("../openvt-potts-package")'
    ```

    `openvt_submission_package` reads only the committed records, the model defaults and the
    bulk directory `OPENVT_PACKAGE_BULK` (the O1 zips and the O2 zip, too large for git; no
    simulation). It refuses a target inside a git checkout or a non-empty directory, and a
    bulk directory that is missing, inside a git checkout or whose files differ from the
    sha256s the post-processing record pins. It writes byte-identical trees on every call at
    the same commit. Its `split` option writes the same files as a core zip of at most 20 MB,
    a flat directory of the large files and a plain-text cover note (see its docstring).
    The acceptance test `lib/PottsModels/test/reproductions/15_openvt_package.jl` checks every
    file against the records.

    ## Citation

    Cite the repository URL and the commit of the record you use.

    ## Licence

    $(_OPENVT_PKG_LICENCE)
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
    occursin(r"\bQ\d+\b", q) && !occursin("our open question list", q) && (q *= " (our open question list)")
    return q
end

# hand-written rows for the record deviations and failures (keyed by row id); each is used
# only while it still carries the record's value, else the record's own row is printed
# the status of a row on the division rule (D-213: M over TST), and of a row on another
# framework's departure from M (spec 15 §7: closed, not asked)
const _OPENVT_PKG_RULING_TST = "not asked (maintainer ruling: M over TST)"
const _OPENVT_PKG_RULING_FW = "not asked (M over the framework's code)"
# the division rule in one sentence (D-213)
const _OPENVT_PKG_DIVISION = "M is followed (actual area); the released TST model divides on target area"
const _OPENVT_PKG_RECORD_ROWS = Dict(
    "V4.2" => ("V4.2 peak of nonzero f (FAIL)",
        "0.425 (100 runs, 11,226 cells with f > 0); 0.395–0.435 for smoothing windows of 1–11 bins; mean nonzero f 0.346",
        "0.25–0.35 (TST and Morpheus pooled); TST alone 0.295, mean nonzero f 0.288",
        "leading: the division rule. $(_OPENVT_PKG_DIVISION) (C13). Not the Morpheus f definition or σ_X (C17): TST alone uses our f and σ_X = 0.4 and passes. Ruled out on 20 runs each: the division axis and a connectivity constraint",
        "$(_OPENVT_PKG_RULING_TST); any other TST detail behind the shift is Q23 on our open question list"),
    "V4.3" => ("V4.3 max f (FAIL)",
        "0.847; 606 of 11,226 rim cells (5.4 %) above 0.56",
        "at most 0.56, no cell above (TST max 0.553)",
        "the same upward shift of the rim cells' f as V4.2; causes as for V4.2 (C13)",
        "$(_OPENVT_PKG_RULING_TST); any other TST detail is Q23 on our open question list"),
    "V4.5" => ("V4.5 range of a (FAIL)",
        "0.066–1.130; 30 of 100,029 cells below 0.42, all small interior cells born shortly before, 10 of them sister pairs",
        "0.42–1.09; TST 0.425–1.092 with no cell below 0.42",
        "squeezed young daughters, cause unresolved; leading candidate the division rule (C13), which changes the daughters' state at birth. A connectivity constraint raises the minimum but not the count",
        "$(_OPENVT_PKG_RULING_TST); whether the frameworks remove crushed cells is Q24 on our open question list"),
    # the sweeps record's rows (its deviations.tsv cites the closed Q20)
    "V1" => ("V1 time to 10⁴ cells, uninhibited (FAIL)",
        "14.945 cycles (β = γ = 0, 10 runs, 14.48–15.31, sd 0.27), 0.12 % above the band's upper edge 14.927, +10.1 % on 13.57; our low-β plateau 14.72–14.77 for β = 0.25–0.6. The Figure 3/9 record measures 15.17 cycles (case (a), 10 runs on other seeds); the difference, 0.22 cycles, is about 1.9 standard errors",
        "13.57 cycles (PhysiCell's γ = 0 value), band ± 10 % = 12.213–14.927; TST plateau 13.77, Artistoo 13.856",
        "the gap opens beyond 10³ cells, past the Figure 3 window. Leading candidate: the division rule. M is followed and we divide on actual area; the released TST model divides on target area (C13)",
        "$(_OPENVT_PKG_RULING_TST); whether 13.57 is pooled or one framework's value is Q17 on our open question list"),
    "V2.1.1x" => ("V2.1.1x β threshold at 1.1× (FAIL)",
        "0.625 (bracket 0.625 / 0.6375, 14.831 / 15.120 cycles over 6 runs each); against our own uninhibited time the rule gives 0.80 (information)",
        "lattice spread 0.687–0.704 (TST 0.7037, Artistoo 0.698); band 0.667–0.724",
        "a consequence of V1: the 1.1× time 14.927 cycles lies on our flat low-β plateau (14.7–15.1 for β ≤ 0.65), so its first crossing is set by run-to-run noise (sd 0.27 cycles), not by the inhibition curve. The 2×–20× β thresholds pass, within 0.002 of TST",
        _OPENVT_PKG_RULING_FW),
    "V3b" => ("V3b time to 10⁴ cells at γ = 10⁻⁴ (FAIL)",
        "58.755 cycles (5 runs, 58.42–59.11, sd 0.25), 3.7 % below the band's lower edge 61; −4.3 % on TST",
        "TST 61.37 (γ = 10⁻⁴, one run), Artistoo 63.09 (γ = 0.0195); band 61–70",
        "unverified. Only cells with free surface grow here, so this measures rim-limited growth; we are faster than TST here but slower at γ = 0 (V1), which a plain rate offset cannot cause. Candidates: the division rule, where TST divides on target area and M and Potts.jl on actual area (C13), which changes rim cell shapes; and the band, which sits 0.6 % below TST's single run. Every γ threshold passes",
        _OPENVT_PKG_RULING_TST),
)

# our figure choices that differ from M, with values from the records
function _openvt_pkg_figure_rows(facts)
    w = facts.window
    rows = Tuple[
        ("F1 panel colours", "cells coloured by area with coolwarm, scaled to the panel's own cell-area min–max " *
                             "(areas from the full state); thin black pixel-edge boundaries; white medium",
            "the CompuCell3D, TST and Artistoo close-ups colour cells blue to red by area (coolwarm) with thin boundaries; " *
            "the limits of their colour scales are not stated",
            "the style follows the other frameworks' panels (D-185); the scale limits are our provisional reading",
            "not asked; on our open question list as Q10 (the colour variable and its limits) and Q18 (the Potts.jl colour, RGB(8, 29, 88) proposed)"),
        ("F1 window", @sprintf("a %d × %d-site block (about %.0f cell diameters 2R) centred on the colony rim", w, w, w / (2 * facts.R)),
            "45 × 45 mm close-ups; the window size is not stated",
            "estimated from the TST close-up; the other panels show more colony than medium", "not an author question"),
        ("F2 consortium curves", "Potts.jl curves and the spring–dashpot reference only", "panels b, d, e overlay all frameworks",
            "the consortium's curves are compared through frozen spread values, not redrawn", "not an author question"),
        ("F3 time axis and framework", "t in $(facts.cycle)-MCS cycles; TST shown as the comparison row",
            "axis \"[T]\"; the framework of M's Figure 3 is not named", "read as cycles, as the TST data imply",
            "not asked; on our open question list as Q2 (open part) and Q13"),
    ]
    facts.f34 === nothing || push!(rows,
        ("F3.4 colony area, case (f)",
            @sprintf("at most %.1f %% from TST on t = 4.5–8.5 and at the stop (band %s, the largest margin used)",
                100 * facts.f34.ours, facts.f34.band),
            "TST deterministic",
            "division on actual area (C13): cells of one generation divide over 0.23–0.41 cycles, not in one MCS",
            _OPENVT_PKG_RULING_FW))
    lat = join(("$(l)²" for l in facts.lattices), " or ")
    gap = facts.min_gap === nothing ? "" : "; no run came closer than $(facts.min_gap) sites"
    append!(rows, [
        ("F4 drawing", "cell i's outline and the in-panel names left out; counts as numbers",
            "a black outline of cell i, names, coloured count glyphs", "no outlines (D-156)", "not an author question"),
        ("F5 distance bins and origin",
            "M's shared edges $(join(_openvt_pkg_g.(_OPENVT_PKG_F5_EDGES), ", ")) for figures/fig5.png, binned in R (provisional). " *
            "$(_OPENVT_PKG_F5_UNIT). The F5 record's verdict " *
            "figure keeps 5 equal bins from 0 to 1.05 times the furthest distance; distances from the initial cell's centre",
            "one set of edges for all rows; how they were derived is not stated; the notebook uses 7 bins from the pooled centroid",
            "M's figure and text taken over its notebook (C11, C12)", "not asked; on our open question list as Q15"),
        ("F9 consortium curves", "only final values compared with the draft's CompuCell3D and Morpheus curves (converted from px to R)",
            "lengths in R, time in cycles", "the draft curves are earlier β = 0.8 runs in each framework's own cycle length",
            "not asked; on our open question list as Q7 and Q14"),
        ("Domain", "closed $lat lattice with a $(facts.guard)-site edge guard (edge_guard)$gap",
            "unbounded plane", "a finite lattice the colony never reaches is equivalent", "not an author question"),
        ("Division axis", "random plane", "not stated for CPMs (CompuCell3D and Morpheus: random; TST: minor axis)",
            "majority practice; TST's minor axis was probed on 20 runs and does not change V4", "not an author question"),
    ])
    return rows
end

# the readings of spec 15 §1.1 (C1–C17)
const _OPENVT_PKG_C_ROWS = [
    ("C1 cell-cycle length", "one cycle = 5T = 775 MCS", "M says the cycle is 5T but also, once, that time is in units of T",
        "M contradicts itself; its tables and the TST data fix 5T",
        "resolved: 5T = 775 MCS from the consortium data (Q2 on our open question list)"),
    ("C2 calibration compression", "target area halved during a burn-in, both chain ends free", "left to each framework",
        "the four CPM implementations all do this", "not an author question"),
    ("C3 truncation of X", "X redrawn while X ≤ 0", "silent; the schema redraws",
        "P(X ≤ 0) is about 3 × 10⁻⁷, so it never fires", "not an author question"),
    ("C4 replicates", "100 runs for Figures 2 and 5, 10 or more per Figure 3/9 case", "100 for Figure 5; the schema's floor is 10",
        "M where it states a number", "not an author question"),
    ("C5 sensitivity analysis", "not done", "not in M's analysis list (only in the schema)", "M's list taken as complete",
        "not an author question"),
    ("C6 literature comparisons", "not done", "not in M (only in the schema)", "M taken over the schema", "not an author question"),
    ("C7 cell diameter CD", "10 px, the relaxed length of a cell on the 5-px strip",
        "not defined numerically; the schema gives 7.98 px",
        "only 10 px makes the relaxed 11-chain 10 CD wide, as M's Figure 2 requires", "not an author question"),
    ("C8 output columns", "x, y, i, n, with g = (i == 0) derived for the analysis",
        "x, y, i, n (the analysis code reads x, y, g, n)", "M for submitted files", "not an author question"),
    ("C9 type 1 inequality", "a ≥ β", "a ≥ β (the schema has a > β)", "M, as Morpheus, TST and Artistoo", "not an author question"),
    ("C10 Figure 9 length units", "R", "R; the draft figure's lattice curves are in px", "M",
        "not asked; on our open question list as Q14"),
    ("C11 Figure 5 distance bins", "M's shared edges (0, 18.6, …, 93) in figures/fig5.png, binned in R (provisional); 5 equal bins in the verdict figure",
        "5 shared bins in the legend; 7 per-framework bins in the notebook", "M's figure",
        "not asked; on our open question list as Q15"),
    ("C12 Figure 5 distance origin", "the initial cell's centre (the lattice centre)",
        "the initial cell's centre; the notebook uses the pooled centroid", "M's text",
        "not asked; on our open question list as Q15"),
    ("C13 division trigger", "actual area ≥ X A*(0)", "actual area ≥ X A*(0); TST uses the target area",
        "M, with CompuCell3D and Morpheus. This is the leading candidate for the V4 failures and the slow V1 growth",
        _OPENVT_PKG_RULING_TST),
    ("C14 daughters' reference area", "half the mother's A*", "half the mother's A* (Morpheus sets it to the daughter's area)",
        "M, with CompuCell3D, TST and Artistoo", "not an author question"),
    ("C15 termination", "end of the first MCS with at least 10⁴ cells", "the same; CompuCell3D stops at 10,200", "M",
        "not an author question"),
    ("C16 growth rate", "α = 50/775 px/MCS", "6.452 × 10⁻² (Table S1); TST uses 50/770", "M", "not an author question"),
    ("C17 σ of X", "0.4", "0.4; Morpheus passes 0.16 as the standard deviation",
        "M; it cannot explain V4, since TST uses 0.4 and passes", _OPENVT_PKG_RULING_FW),
]

# rows from the records: deviations.tsv rows, then non-control FAIL verdicts without one;
# returns the rows and the row ids they cover
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
            if cur !== nothing && (m === nothing || occursin(m.match, line)) && (!fail || occursin("FAIL", line))
                push!(out, _openvt_pkg_row(cur...))
            else
                tgt = isempty(get(r, "case", "")) ? r["target"] : "$(r["target"]), case ($(r["case"]))"
                push!(out, _openvt_pkg_row(tgt, get(r, "ours", ""), get(r, "paper", ""), get(r, "suspected_cause", ""),
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
            push!(out, _openvt_pkg_row("$(r["target"]) (FAIL)", get(r, "ours", ""), get(r, "paper", ""),
                "band $(get(r, "band", get(r, "tolerance", ""))); cause not yet analysed", "not asked"))
            push!(done, key)
        end
    end
    return out, done
end

function _openvt_pkg_v1_row(recs, meta)
    _, runs = _openvt_pkg_tsv(joinpath(_OPENVT_PKG_DATA, recs[:f3f8], "runs.tsv"))
    ca = sort([_openvt_pkg_f(r["cycles"]) for r in runs if r["case"] == "a"])
    hi = 13.57 * 1.1
    ta = meta[:f3f8]["stats"]["a"]["t_stop"]
    te = meta[:f3f8]["stats"]["e"]["t_stop"]
    judged = haskey(recs, :sweeps) ? "judged in the sweeps record `$(recs[:sweeps])`" : "judged with the sweeps"
    return _openvt_pkg_row("V1 time to 10⁴ cells, uninhibited (measured in the Figure 3/9 record; $judged)",
        @sprintf("%.2f cycles (case (a), %d runs, %.2f–%.2f); %d of %d runs above the band; case (e) at β = 0.8: %.2f",
            ta, length(ca), first(ca), last(ca), count(>(hi), ca), length(ca), te),
        "13.57 cycles (PhysiCell's γ = 0 value), band ± 10 % = 12.21–14.93; TST low-β plateau 13.61–13.86; TST at β = 0.8: 16.15",
        @sprintf("about %.1f %% slow. The gap opens beyond 10³ cells, past the Figure 3 window. ", 100 * (ta / 13.57 - 1)) *
        "Leading candidate, as for V4: the division rule. M is followed and we divide on actual area; the released TST model divides on target area (C13)",
        "$(_OPENVT_PKG_RULING_TST); whether 13.57 is pooled or one framework's value is Q17 on our open question list")
end

# the "Figures" section of the results README (D-211): M's Figures 5, 7 and 8, their colours,
# the shared Figure 5 bins and each drawn colony's C/C_circle from the records' grid tables
function _openvt_pkg_figures_section(recs)
    io = IOBuffer()
    e = join(_openvt_pkg_g.(_OPENVT_PKG_F5_EDGES), ", ")
    f8 = haskey(recs, :f8beta)
    print(io, """

    ## Figures

    Our rows of M's Figures 5$(f8 ? ", 7 (γ) and 8 (β)" : " and 7") (9 Oct 2026 draft), byte copies of the renders in the
    records (`plot_f5_shared.jl`, `plot_f7_grid.jl`$(f8 ? ", `plot_f8_grid.jl`" : "") in `implementations/$(_OPENVT_PKG_FW)/scripts/`):

    - `figures/fig5.png`: Figure 5, case (b), 100 runs at 1000 cells, on M's shared distance-bin edges
      $e (record `$(recs[:f5])`), binned in R from the lattice centre. $(_OPENVT_PKG_F5_UNIT).
      Our row stays in R and is provisional.
    - `figures/fig7.png`: Figure 7, one colony at 10⁴ cells per Table 1 multiple at our γ thresholds
      (β = 0); 1.1× and 2× are empty (no γ threshold there); cells yellow (no inhibition) or teal
      (surface-inhibited) (record `$(recs[:sweeps])`).
    """)
    f8 || print(io, """
    - Figure 8: pending (the colonies at the T1 β values, area inhibition; their record is not merged yet).
    """)
    f8 && print(io, """
    - `figures/fig8.png`: Figure 8, one colony at 10⁴ cells at each of our Table 1 β thresholds (γ = 0),
      replayed from the sweeps seeds; cells yellow (no inhibition) or red (area-inhibited, a < β)
      (record `$(recs[:f8beta])`).
    """)
    print(io, """

    In the colony grids (Figure 7 for γ$(f8 ? ", Figure 8 for β" : "")) the black line is the tissue outline: the
    concave hull of the cell centroids as `metrics.cpp` computes it (concaveman, concavity 1.5, lengthThreshold 0). Each colony's
    C/C_circle (the outline's perimeter over that of a circle of the same area, `metrics.cpp`'s
    first roughness):

    | Figure | Multiple | Threshold | N | C/C_circle |
    |---|---|---|---|---|
    """)
    for (k, fig, sym) in ((:sweeps, "Figure 7 (γ)", "γ"), (:f8beta, "Figure 8 (β)", "β"))
        haskey(recs, k) || continue
        n = k === :sweeps ? 7 : 8
        p = joinpath(_OPENVT_PKG_DATA, recs[k], "fig$(n)_grid.tsv")
        isfile(p) || throw(ArgumentError("openvt_submission_package: the $(_OPENVT_PKG_ITEMS[k]) record has no fig$(n)_grid.tsv"))
        _, rows = _openvt_pkg_tsv(p)
        for r in rows
            print(io, "| ", fig, " | ", replace(r["multiple"], "x" => "×"), " | ", sym, " = ", r["value"], " | ", r["N"], " | ",
                @sprintf("%.2f", _openvt_pkg_f(r["C_rel"])), " |\n")
        end
    end
    print(io, """

    The panels carry no number. M's panels show a centred label whose quantity is unstated in M;
    it is on our open question list, and C/C_circle above is metrics.cpp's measure, not M's label.
    """)
    return String(take!(io))
end

_openvt_pkg_sweep_row(recs) =
    _openvt_pkg_row("F6, T1, F7", "run in the record `$(recs[:sweeps])`; its failing rows are listed above",
        "Figure 6, Table 1, Figure 7", "the protocol and targets were frozen before the run (D-174)",
        "not an author question")

# the licence line of both READMEs (D-181)
const _OPENVT_PKG_LICENCE = "Licence: Potts.jl and these files are released under the MIT license; see the `LICENSE` file of " *
                            "$(_OPENVT_PKG_URL) ($(_OPENVT_PKG_URL)/blob/main/LICENSE)."

function _openvt_pkg_backend(meta)
    a = get(meta, "algorithm", "")
    return isempty(a) ? "CPU" : "CPU, `$a`"
end

# a provenance fact about our measurements, for the results README only (D-219)
const _OPENVT_PKG_COMPILER_NOTE = "Our precomputed measurements were produced with metrics.cpp built with GCC 13 on Linux."

# D-215 (8): what the consortium's scripts need to know (results README and EMAIL.md)
function _openvt_pkg_note_lines(o1)
    big = maximum(r -> parse(Int, r["bytes"]), o1.archives)
    return [
        "`run_metrics.sh` loops over `seq 0 10000`, so it skips the files with MCS above 10000; our precomputed measurements in `Monolayer/metrics/` are complete (every save to the stop).",
        "The largest O1 zip is $(round(Int, big / 1e6)) MB, so it may need Git LFS on the consortium repository's side.",
        "Lengths are in R, the cell radius, with the origin at the lattice centre; the consortium's scripts are translation-invariant, so no shift is needed.",
        "Only R is shipped in the result files: no Monolayer file has lengths in px (parameters.csv gives the px values of A0, R and CD).",
        _OPENVT_PKG_COMPILER_NOTE,
        "Each framework list hard-coded in the consortium's scripts (`run_metrics.sh`, the Figure 5 notebook, `colors.tex` and the figure .tex files) needs one line added for this entry, under the folder name `$(_OPENVT_PKG_FW)`.",
        "The O1 zips, the O2 zip and the O1 manifest go into `results/$(_OPENVT_PKG_FW)/Monolayer/` and stay zipped there.",
    ]
end

_openvt_pkg_notes(o1) = "\n## Notes for the consortium scripts\n\n" * join(("- " * l * "\n" for l in _openvt_pkg_note_lines(o1))) 

function _openvt_pkg_results_readme(recs, prov, meta, facts, o1)
    d = facts.defaults
    g = _openvt_pkg_g
    cl = facts.closeup
    w = facts.window
    cases = meta[:f3f8]["cases"]
    io = IOBuffer()
    print(io, """
    # Potts.jl results: OpenVT growing monolayer

    Simulation output of the Potts.jl cellular Potts model (`implementations/$(_OPENVT_PKG_FW)/`) for
    the OpenVT growing-monolayer benchmark, in the layout of the benchmark repository. Every
    file was built by `PottsModels.openvt_submission_package` from the committed run records
    listed at the end; the per-record `provenance/*.toml` give the commit, Julia version,
    machine and timings of each run.

    ## Units

    - Lengths in the Monolayer files are in R = √(A*(0)/π) = $(@sprintf("%.4f", facts.R)) px, the initial
      cell radius (A*(0) = $(g(d.A0)) px).
    - Times in the Monolayer files are in cell cycles, t = MCS/$(facts.cycle) (one cycle is
      5T = A*(0)/α = $(facts.cycle) MCS); the MCS stamp is the first column.
    - The Relaxation files use the mechanical time scale: "Normalized time (T)" is MCS/T(λ),
      with T(λ = 2) = $(facts.T2) MCS for the 11cells and 11+10cells files and each λ's own T in
      `lambda_scan/` (`table_S5.csv`). Negative times are the compression burn-in, as in the
      TST files. Widths are in cell diameters, CD = $(g(facts.CD)) px.

    ## Files

    | Path | Content | Columns (units) |
    |---|---|---|
    | `closeup.png` | Figure 1 panel without its banner: case ($(cl.case)), run $(cl.run) (seed $(cl.seed)) at the stop (MCS $(cl.mcs), N = $(cl.N)), the $(w) × $(w)-site block on the colony rim ($(cl.cells) cells, $(cl.medium) medium sites) | PNG |
    | `Relaxation/11cells/width.csv` | 11-cell chain width, λ = 2, mean and SD over the runs | `Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)` |
    | `Relaxation/11+10cells/width.csv`, `inner_width.csv` | 11+10-cell chain: total and inner (11-cell) width, λ = 2, T(2) with no refit | as above (`Mean inner width (CD)`, `STD inner width (CD)`) |
    | `Relaxation/lambda_scan/11cells_lambda<λ>_width.csv` | 11-cell chain width for λ = $(join(_OPENVT_PKG_LAMBDAS, ", ")) (Table S5's runs) | as above |
    | `Relaxation/table_S5.csv` | Table S5: T(λ) (first crossing of 90 % of the plateau by the mean width) and the MSE against the spring–dashpot reference on t ≥ 0 | `lambda` (1), `T (MCS)`, `MSE` (CD²) |
    | `Monolayer/metrics/<case>/measurements_s<seed>.csv` | Figure 9 (metrics): per run and save (every $(_OPENVT_PKG_GRID) MCS and at the stop): cell count and the `metrics.cpp` values of the concave-hull boundary | `MCS`, `t` (cycles), `N` (cells), `R` (R, mean radius), `A` (R², area), `C` (R, perimeter), `w` (R, radius spread), `g` (fraction of growing cells) |
    | `Monolayer/metrics/measurements_<case>_mean.csv` | the arithmetic mean over the case's runs (schema "Data Collection") at the saves every run reached; NaN values skipped | as above, plus `runs` (count) |
    | `Monolayer/metrics/neighbors_<case>.csv` | final neighbour-number histogram pooled over the case's runs | `n` (neighbours), `p` (% of cells) |
    """)
    o1cases = join(("($c)" for c in o1.cases), ", ")
    o1zips = join(("($c) `$(_openvt_pkg_o1_zip(c))`" for c in o1.cases), ", ")
    a3cases = join(("($c)" for c in o1.cases if c in _OPENVT_PKG_A3 || c in _OPENVT_PKG_A3_SWEEPS), ", ")
    nfiles = sum(length, values(o1.members))
    # the case (b) seeds of the Figure 5 runs, as `seed = <offset> + k` when they are consecutive
    offs = unique(s - k for (k, s) in o1.o2runs)
    o2seed = length(offs) == 1 ? "seed $(only(offs)) + k" :
             "seeds $(minimum(values(o1.o2runs)))–$(maximum(values(o1.o2runs))), by run k in the P6.15e `runs.tsv`"
    print(io, """
    | `Monolayer/<stem>.zip` | O1 per-cell time series, one zip per case: $(o1zips). One file per run and save (MCS 0, every $(_OPENVT_PKG_GRID) MCS and the stop; $(nfiles) files in all), `<stem>/s<seed>/potts_<case>_s<seed>_<MCS:06d>.csv`, one row per live cell. Unzipped in `Monolayer/`, the files land in `Monolayer/<stem>/s<seed>/` | `x`, `y` (R, from the lattice centre), `i` (inhibition code: 0 growing, 1 type 1, 2 type 2, 3 both), `n` (number of neighbour cells), `g` (1 if i = 0, else 0; the column `metrics.cpp` reads) |
    | `Monolayer/$(_OPENVT_PKG_O1_MANIFEST)` | every O1 file: its zip, name, row count, size and sha256 | `archive`, `file`, `rows` (cells), `bytes`, `sha256` |
    | `Monolayer/metrics/<case>/inhibition_s<seed>.csv` | A3 for cases $(a3cases): the share of each inhibition code among the cells of every O1 save of the run | `MCS`, `t` (cycles), `f0`, `f1`, `f2`, `f3` (fractions of cells with i = 0, 1, 2, 3) |
    | `Monolayer/$(_OPENVT_PKG_O2_ZIP)` | Figure 5 snapshots at 1000 cells, case (b): `$(_OPENVT_PKG_O2_DIR)/cell_data_no_inhibition_<k>.csv`, k = 0…$(length(o1.o2) - 1), file k from run k + 1 ($(o2seed)) | `x`, `y` (R, from the lattice centre), `r` (R), `f` (fraction), `a` (A/A*) |
    | `Monolayer/$(_OPENVT_PKG_FW)_time_to_10k_vs_{beta,gamma}.csv` | Figure 6 / Table 1: time to 10⁴ cells per run (NaN for capped runs) | `beta` or `gamma` (1), `Time to 10k (MCS)`, `Time to 10k (5T)` (cycles) |
    | `Monolayer/$(_OPENVT_PKG_TABLE1)` | Table 1: our β and γ thresholds per multiple of the uninhibited time, with the TST and Artistoo values and the spread and band of our pre-registered check (NaN: no threshold) | `parameter`, `multiple` (1), `threshold` (1), `tau_cycles` (cycles), `interpolated` (1), `TST`, `Artistoo`, `spread_lo`, `spread_hi`, `band_lo`, `band_hi` |
    | `Monolayer/final_snapshot_data/$(_OPENVT_PKG_FW)_beta_0.0_gamma_<γ>_<MCS>MCS.csv` | Figure 7 final snapshots (β = 0, as in M's Figure 7) | `x_pos`, `y_pos` (R, from the lattice centre), `radius_i` (R), `inhibited` (0/1) |
    """)
    haskey(recs, :f8beta) && print(io, """
    | `Monolayer/final_snapshot_data/$(_OPENVT_PKG_FW)_beta_<β>_gamma_0.0_<MCS>MCS.csv` | Figure 8 final snapshots at the T1 β values (γ = 0); `inhibited` is area inhibition (a < β) | as above |
    """)
    print(io, """
    | `figures/fig5.png`, `figures/fig7.png`$(haskey(recs, :f8beta) ? ", `figures/fig8.png`" : "") | M's Figures 5, 7$(haskey(recs, :f8beta) ? " and 8 (β)" : ""): our rows, see Figures below | PNG |

    The O1 files of cases $(o1cases) come from a re-run of the Figure 3/9 runs from their
    recorded seeds (record `$(recs[:o1])`): every save's MCS, cell count and metrics equal the
    Figure 3/9 record's, and the run stops at the same MCS with the same cell count. The record
    `$(recs[:o1g])` then added the column `g` and repacked them, with no re-run.
    """)
    print(io, _openvt_pkg_notes(o1))
    print(io, _openvt_pkg_figures_section(recs))
    print(io, """

    ## Cases and seeds

    All monolayer runs use the Table S1 model (A*(0) = $(g(d.A0)), λ = $(g(d.lambda)), T = $(g(d.T)),
    α = $(g(d.A0))/$(facts.cycle), μ_X = $(g(d.mu_X)), J $(g(d.J_cc))/$(g(d.J_cm)), Moore(1)), start
    from one cell and stop at the end of the first MCS with the target cell count. Each run's
    seed is in its file name; runs of a case use consecutive seeds.

    | Case | β | γ | σ_X | Lattice | Stop (cells) | Runs | Seeds |
    |---|---|---|---|---|---|---|---|
    """)
    for c in _OPENVT_PKG_CASES
        m = cases[c]
        print(io, "| (", c, ") | ", m["beta"], " | ", m["gamma"], " | ", m["sigma_X"], " | ", m["lattice"], "² | ",
            m["cells"], " | ", m["runs"], " | ", m["seeds"], " |\n")
    end
    print(io, """

    Case (f) is deterministic division (X ≡ $(g(d.mu_X))). The relaxation runs use seeds
    $(meta[:calib]["seeds_11chain"]) (11-cell chain at each λ) and $(meta[:calib]["seeds_21chain"])
    (11+10-cell chain), $(meta[:calib]["replicates"]) runs each.

    ## Colours

    `closeup.png` follows the other frameworks' close-ups: each cell is coloured by its area
    (from the full state, so cells cut by the window keep their full area) with the `coolwarm`
    colour map, scaled to the min–max of the cell areas in the panel, on a white medium, with
    thin black boundaries along the pixel edges between unlike cells. The scale limits are our
    provisional reading. The banner colour proposed for Potts.jl is RGB(8, 29, 88). See the F1
    row below.

    ## Deviations from the manuscript

    One row per difference between our runs and the manuscript (M), per conflict between M
    and the benchmark's other sources together with the reading we took (C1–C17), and per
    failed or at-risk target. "Ours" is our value or choice, "Manuscript" M's, then the
    suspected cause and the status of the question: "not an author question", "not asked"
    (the question is on our open question list, §7 of `$(_OPENVT_PKG_SPEC)` in
    $(_OPENVT_PKG_URL)) or "resolved" (settled from the consortium's public data). Where
    another framework's code departs from M, M is the reference and the departure is recorded,
    not queried: those rows say "$(_OPENVT_PKG_RULING_TST)" or
    "$(_OPENVT_PKG_RULING_FW)". Row ids V# and F# are our acceptance targets.

    Division: $(_OPENVT_PKG_DIVISION). Potts.jl divides when a cell's actual area reaches
    X·A*(0), as M states; this is the leading candidate for the V1 and V4 rows below.

    | Item | Ours | Manuscript | Suspected cause | Author question |
    |---|---|---|---|---|
    """)
    rows, done = _openvt_pkg_record_rows(recs)
    foreach(r -> print(io, r), rows)
    "V1" in done || print(io, _openvt_pkg_v1_row(recs, meta))
    print(io, _openvt_pkg_sweep_row(recs))
    foreach(r -> print(io, _openvt_pkg_row(r...)), _openvt_pkg_figure_rows(facts))
    foreach(r -> print(io, _openvt_pkg_row(r...)), _OPENVT_PKG_C_ROWS)
    print(io, """

    ## Records

    | Record | Results | Commit | Backend | Machine | Threads |
    |---|---|---|---|---|---|
    """)
    for k in _openvt_pkg_keys(recs)
        p = prov[k]
        print(io, "| `", recs[k], "` | ", _OPENVT_PKG_FIGURES[k], " | `", p["commit"][1:8], "` | ", _openvt_pkg_backend(meta[k]),
            " | ", get(p, "cpu", ""), " | ", _openvt_pkg_threads(p), " |\n")
    end
    print(io, """

    The records are in `lib/PottsModels/reproductions/data/15/` of $(_OPENVT_PKG_URL); how to
    rerun them is in `implementations/$(_OPENVT_PKG_FW)/README.md`.

    ## Licence

    $(_OPENVT_PKG_LICENCE)
    """)
    return String(take!(io))
end

# ── the split for sending by mail (D-213 (a)–(d), D-215 (7)) ───────────────────────────────

_openvt_pkg_release_url(tag, f) = _OPENVT_PKG_RELEASES * tag * "/" * f

# the non-control FAIL row ids of the records (as the deviations table lists them)
function _openvt_pkg_fail_keys(recs)
    keys_ = String[]
    for k in _openvt_pkg_keys(recs)
        p = joinpath(_OPENVT_PKG_DATA, recs[k], "deviations.tsv")
        isfile(p) && append!(keys_, [_openvt_pkg_key(r["target"]) for r in _openvt_pkg_tsv(p)[2] if occursin("FAIL", r["target"])])
        p = joinpath(_OPENVT_PKG_DATA, recs[k], "verdicts.tsv")
        isfile(p) || continue
        for r in _openvt_pkg_tsv(p)[2]
            get(r, "result", "") == "FAIL" || continue
            get(r, "case", "") == "control" && continue
            occursin(r"must FAIL"i, get(r, "band", "")) && continue
            occursin("(all rows)", r["target"]) && continue
            push!(keys_, _openvt_pkg_key(r["target"]))
        end
    end
    return sort(unique(keys_))
end

# zip a staged tree with fixed time stamps (1980-01-01 00:00 UTC), sorted members, no
# directory entries and no extra attributes: the same files give the same bytes
function _openvt_pkg_zip(stage, z)
    Sys.which("zip") === nothing && throw(ArgumentError("openvt_submission_package: the split needs Info-ZIP `zip` on PATH"))
    sh = "find . -type f -exec touch -t 198001010000.00 {} + && " *
         "find . -type f | sed 's|^\\./||' | LC_ALL=C sort | zip -X -D -9 -q -@ " * Base.shell_escape(z)
    run(setenv(Cmd(`sh -c $sh`; dir = stage), merge(ENV, Dict("TZ" => "UTC", "LC_ALL" => "C"))))
    return z
end

function _openvt_pkg_split(outdir, out, existed, bulk, allow_pending, tag)
    tmp = mktempdir()
    try
        # the unsplit package (its own refusals: records, bulk directory)
        U = joinpath(tmp, "unsplit")
        openvt_submission_package(U; bulk, allow_pending)
        recs = _openvt_pkg_records()
        o1 = _openvt_pkg_o1(joinpath(_OPENVT_PKG_DATA, recs[:o1g]), recs[:o1],
            _openvt_pkg_o2_runs(joinpath(_OPENVT_PKG_DATA, recs[:f5])))
        mono = joinpath("results", _OPENVT_PKG_FW, "Monolayer")
        try
            mkpath(joinpath(out, "bulk"))
            stage = joinpath(tmp, "core")
            for (root, _, fs) in walkdir(U), f in fs
                rel = relpath(joinpath(root, f), U)
                if dirname(rel) == mono && _openvt_pkg_isbulk(f)
                    cp(joinpath(root, f), joinpath(out, "bulk", f))
                else
                    mkpath(dirname(joinpath(stage, rel)))
                    cp(joinpath(root, f), joinpath(stage, rel))
                end
            end
            bf = sort(readdir(joinpath(out, "bulk")))
            sha = Dict(f => _openvt_pkg_sha(joinpath(out, "bulk", f)) for f in bf)
            sz = Dict(f => filesize(joinpath(out, "bulk", f)) for f in bf)
            # the core's results README: the bulk files by name, sha256 and download URL
            rp = joinpath(stage, "results", _OPENVT_PKG_FW, "README.md")
            io = IOBuffer()
            readme = read(rp, String)
            k = findlast("\n## Licence\n", readme)
            k === nothing && error("openvt_submission_package: the results README has no Licence section")
            print(io, readme[1:first(k)], """
            ## Bulk files

            The files below are not in this zip. They are attached to the Potts.jl release
            `$tag`; download them into `results/$(_OPENVT_PKG_FW)/Monolayer/` and leave them zipped.
            Check each against its sha256.

            | File | Bytes | sha256 | URL |
            |---|---|---|---|
            """)
            foreach(f -> print(io, "| `", f, "` | ", sz[f], " | `", sha[f], "` | ", _openvt_pkg_release_url(tag, f), " |\n"), bf)
            print(io, "\n", readme[(first(k) + 1):end])
            write(rp, String(take!(io)))
            _openvt_pkg_zip(stage, joinpath(out, "core.zip"))
            _openvt_pkg_write(joinpath(out, "EMAIL.md"), _openvt_pkg_email(recs, o1, bf, sha, sz, tag))
        catch
            _openvt_pkg_clean(out, existed)
            rethrow()
        end
    finally
        rm(tmp; recursive = true, force = true)
    end
    bf = sort(readdir(joinpath(out, "bulk")))
    sizes = [f => filesize(joinpath(out, "bulk", f)) for f in bf]
    core_bytes = filesize(joinpath(out, "core.zip"))
    bulk_bytes = sum(last, sizes; init = 0)
    @info "openvt_submission_package: split" core_bytes bulk_bytes bulk = sizes
    return (; outdir, core_bytes, bulk_bytes, bulk = sizes)
end

# the plain-text cover note (D-213 (c)): a draft the maintainer pastes; nothing is sent
function _openvt_pkg_email(recs, o1, bf, sha, sz, tag)
    mb(b) = @sprintf("%.1f MB", b / 1e6)
    fails = _openvt_pkg_fail_keys(recs)
    io = IOBuffer()
    print(io, """
    Potts.jl results for the OpenVT growing monolayer benchmark

    Attached: core.zip. It unpacks at the root of the benchmark repository into
    implementations/$(_OPENVT_PKG_FW)/ (the model source, parameters.csv, the run scripts and a README on
    rerunning everything) and results/$(_OPENVT_PKG_FW)/ (the relaxation widths and Table S5, the
    per-run measurements, means and neighbour histograms, the inhibition shares, the time to
    10k cells for the beta and gamma sweeps, Table 1 as a CSV, the final snapshots, our rows of
    Figures 5, 7 and 8 as PNGs, the close-up, the provenance of every run record and a README
    with the units, seeds and deviations).

    Linked, too large to attach: one public Potts.jl release, tag
    $tag
    (each file's sha256 is also in the results README):
    """)
    for f in bf
        print(io, "\n", f, " (", mb(sz[f]), ")\n", _openvt_pkg_release_url(tag, f), "\nsha256 ", sha[f], "\n")
    end
    print(io, """

    Units: lengths are in R, the cell radius sqrt(A*(0)/pi), with the origin at the lattice
    centre; time is in cell cycles, one cycle = 775 MCS (5T); the MCS is in each O1 and O5
    file name and in the first column of the measurement files.

    Open questions on our list: Q15, the distance unit and origin of the Figure 5 axis (it is
    consistent with distance in units of R/2; our row is binned in R). Q26, the quantity behind the
    centre labels of Figures 7 and 8 (our panels carry no label; each colony's C/C_circle is
    in the results README).

    Deviations: $(_openvt_pkg_join(fails)) fail their pre-registered bands. The
    results README has one row per deviation with our value, the manuscript's and the
    suspected cause. Division follows the manuscript: a cell divides when its actual area
    reaches X times A*(0). The released TST model divides on target area instead, which is the
    leading candidate for the V1 and V4 rows.

    Notes for the consortium scripts:

    """)
    foreach(l -> print(io, "- ", replace(l, '`' => ""), "\n"), filter(!=(_OPENVT_PKG_COMPILER_NOTE), _openvt_pkg_note_lines(o1)))
    print(io, """

    Everything is built by PottsModels.openvt_submission_package from the run records committed
    in $(_OPENVT_PKG_URL) (lib/PottsModels/reproductions/data/15/). Licence: MIT.
    """)
    return String(take!(io))
end

_openvt_pkg_join(v) = length(v) <= 1 ? join(v) : join(v[1:(end - 1)], ", ") * " and " * v[end]
