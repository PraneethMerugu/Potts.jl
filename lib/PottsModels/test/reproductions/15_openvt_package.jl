# P6.15j (ROADMAP Step 3b): the OpenVT monolayer submission package, in the consortium layout,
# prepared locally. Frozen (AUTONOMY §7.3). Submitting it is the maintainer's call; this test
# never contacts anyone and needs neither the PC nor the consortium clone (G).
#
# Sources: spec 15 (docs/design/research/model-specs/15_openvt_monolayer.md) §3.1 (O1–O6),
# §4.0 (inventory), §4.0.1 (submission requirements), §1.1 (C1–C17); G at 54f375f, read on the
# PC only (nothing copied): G:README.md ("Each framework has a subfolder with its name in the
# "implementations" (for source code, scripts etc.) and "results" (for main simulation output)
# directories"), G:schema/README.md "Data Collection" (mean of 10 replicates for stochastic
# frameworks; a time series of centroid files, one per time point; CSV with a header line) and
# "Data Analysis" (lengths in R = √(A₀(0)/π), times in T), and the layouts of
# G:results/TST/ (Relaxation/11cells/width.csv, Relaxation/11+10cells/{width,inner_width}.csv,
# TST_time_to_10k_vs_{beta,gamma}.csv, final_snapshot_data/TST_beta_<b>_gamma_<g>_<MCS>MCS.csv,
# TST_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv), G:results/<FW>/closeup.png
# and G:implementations/<FW>/ (model files, runner scripts, a README). Decisions: D-146, D-154,
# D-168, D-173, D-174 (+ amendment), D-175, D-178.
#
# ---------------------------------------------------------------------------------------------
# The generator (pinned)
# ---------------------------------------------------------------------------------------------
#   PottsModels.openvt_submission_package(outdir::AbstractString) -> outdir
#
# builds, under `outdir`, exactly two trees: `implementations/Potts.jl/` and `results/Potts.jl/`,
# from the merged records under `lib/PottsModels/reproductions/data/15/` (D-146). It runs no
# simulation. It throws `ArgumentError` when `outdir` is inside this git checkout (the package
# lives outside git) or exists and is not empty (no stale files). Two calls on the same commit
# give byte-identical trees (no timestamps, no absolute paths, fixed row order).
#
# Records are found the way the page test (P6.15i) finds them: the directories of `data/15/`
# whose `provenance.toml` names the ROADMAP item: P6.15b calibration (F2, S5), P6.15e F5,
# P6.15f F3/F8, P6.15h F1/F4, P6.15g the sweeps (F6, T1, F7; parked, D-174). The newest
# directory (by name) wins when an item has several.
#
# ---------------------------------------------------------------------------------------------
# REQUIRED files (all derivable from git records; values must equal the records)
# ---------------------------------------------------------------------------------------------
# implementations/Potts.jl/
#   README.md            how to run: the repo URL, `Pkg.instantiate`, the test environment
#                        `--project=lib/PottsModels/test`, each runner's package path, the record
#                        commits (8 hex), and `openvt_submission_package` to rebuild the package
#   parameters.csv       `name,value,unit`; the Table S1 values and the Potts settings below
#   src/openvt_reference.jl, src/openvt_chain.jl
#                        byte-identical to lib/PottsModels/src/ (the `@potts_model` listings)
#   scripts/<record>/<runner>.jl
#                        the runner named in each record's provenance.toml, byte-identical; other
#                        scripts/<record>/<name>.jl may be added only as byte copies of that
#                        record's <name>.jl
# results/Potts.jl/
#   README.md            units, seeds, a Deviations table (D-154), the readings C1–C17, the
#                        per-cell colour choice (D-175), a "Pending" section (see below)
#   closeup.png          byte-identical to the P6.15h record's fig1.png (G:results/<FW>/closeup.png)
#   provenance/<record>.toml
#                        each record's provenance.toml, with the key `hostname` removed
#                        (spec §4.0.1 item 6; nothing private)
#   Relaxation/11cells/width.csv                       (O4; λ = 2, the λ the cycle uses)
#   Relaxation/11+10cells/width.csv, inner_width.csv   (O4; λ = 2, T(2) with no refit, P10)
#   Relaxation/lambda_scan/11cells_lambda<λ>_width.csv (λ = 1, 2, 3, 5; Table S5's runs)
#       headers exactly as TST's mean/STD columns (G:results/TST/Relaxation/…):
#         `Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)` and
#         `Normalized time (T),Mean inner width (CD),STD inner width (CD)`;
#       one row per record row (burn-in at t < 0 included, TST does the same), in record order,
#       values equal to the record's t_over_T and mean/sd columns. Per-replicate columns are not
#       in the record and are not required.
#   Relaxation/table_S5.csv  `lambda,T (MCS),MSE`; λ = 1, 2, 3, 5; T = the record's T_ours; MSE =
#       PottsModels.Analysis.relaxation_mse on the record's t ≥ 0 rows against reference.tsv (P9)
#   Monolayer/metrics/<case>/measurements_s<seed>.csv   (O6 per run, cases a, b, e, f)
#       `MCS,t,N,r,A,C,w,g`, t = MCS/775 (cycles; D-173 cycle_mcs), one row per record save, in
#       MCS order, values equal to timeseries.tsv (NaN where the record has nan)
#   Monolayer/metrics/measurements_<case>_mean.csv     (schema: report the arithmetic mean)
#       `MCS,t,N,r,A,C,w,g,runs`; rows at the MCS that are multiples of 39 and saved by every run
#       of the case; each column the mean over runs of its non-NaN values (NaN if none); `runs`
#       the case's run count
#   Monolayer/metrics/neighbors_<case>.csv              (O6 `n,p`; Category 3 histogram)
#       `n,p`, p in % of the case's final cells pooled over its runs (neighbors.tsv), rows for
#       every n with a nonzero count, ascending
#
# ---------------------------------------------------------------------------------------------
# OPTIONAL items: present and checked, or named in the README "Pending" section (never faked)
# ---------------------------------------------------------------------------------------------
# key  path under results/Potts.jl/                                      columns
# O1   Monolayer/centroids/<case>/potts_<case>_s<seed>_<MCS:06d>.csv     x,y,i,n   (schema "Data
#      Collection"; per-cell files are not in the D-146 records, which keep per-save metrics)
# O2   Monolayer/Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv, k = 1:100
#                                                                        x,y,r,f,a (F5; D-168
#      kept them out of git for this package)
# A3   Monolayer/metrics/<case>/inhibition_s<seed>.csv (cases a, e)      MCS,t,f0,f1,f2,f3
# O3   Monolayer/Potts.jl_time_to_10k_vs_beta.csv, …_vs_gamma.csv        beta|gamma,Time to 10k
#      (MCS),Time to 10k (5T)   (F6, T1; P6.15g)
# O5   Monolayer/final_snapshot_data/Potts.jl_gamma_<γ>_<MCS>MCS.csv    x_pos,y_pos,radius_i,
#      inhibited   (F7; P6.15g; at least 5 files)
# An absent item's stem (the constant P615J_OPTIONAL) appears in the Pending section; a present
# item's stem does not. While no P6.15g record is merged, the O3 and O5 entries also say
# "FULL run parked (D-174)"; once one is merged they must be present (no re-freeze needed;
# their values against that record are pinned when it lands).
#
# ---------------------------------------------------------------------------------------------
# Content rules
# ---------------------------------------------------------------------------------------------
# - Allowlist: every file under outdir matches a required or optional path; nothing else, so no
#   G file, figure or archive can ride along. Opt-in (OPENVT_MONOLAYER_REPO = a local G clone):
#   no package file is byte-identical to a G file.
# - Deviations (D-154; as the page test, D-178): results README has a level-2 heading with
#   "Deviations" or "Differences"; its Markdown tables have header cells "Ours", a paper column
#   ("Paper", "Manuscript" or "M"), "cause" and "Author question"; rows (keyed by first cell):
#   every C# of spec §1.1; every row of every data/15/*/deviations.tsv (its first decimal number
#   and FAIL when the target says FAIL); every non-control FAIL verdict (with FAIL); V1 (15.17,
#   13.57, C13, "actual area", "target area", not PASS); the F1 per-cell colour row (D-175);
#   the boundary row (a closed lattice with an edge guard instead of the schema's unbounded
#   plane). Last cell starts with "not an author question", "not asked" or "resolved"; a row
#   naming Q# says "our open question list".
# - Units and seeds: the results README names "775", "156" (T(λ = 2) in MCS), R as the cell
#   radius, CD = 10 px, and every case's seed range from the P6.15f meta.toml.
# - Nothing private, nothing implying contact (all text files): the page test's list, plus
#   the user name (except inside "PraneethMerugu/Potts.jl", the public repository), host names,
#   absolute paths, the PC's address and "PI".
using Test, TOML, SHA, PottsModels

const P615J_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615J_DATA = joinpath(P615J_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615J_SRC = joinpath(P615J_ROOT, "lib", "PottsModels", "src")
const P615J_SPEC = joinpath(P615J_ROOT, "docs", "design", "research", "model-specs", "15_openvt_monolayer.md")
const P615J_IMPL = joinpath("implementations", "Potts.jl")
const P615J_RES = joinpath("results", "Potts.jl")
const P615J_REPO_URL = "https://github.com/PraneethMerugu/Potts.jl"
const P615J_CYCLE = 775                       # MCS per cycle (5T), M's α = 50/775 (C1, C16)
const P615J_GRID = 39                         # D-173 save cadence
const P615J_CASES = ["a", "b", "e", "f"]      # spec §4.0.1 cases run by P6.15f (control is ours)
const P615J_LAMBDAS = [1, 2, 3, 5]            # Table S5
const P615J_ITEMS = Dict(:calib => "P6.15b", :f5 => "P6.15e", :f3f8 => "P6.15f", :f1f4 => "P6.15h",
    :sweeps => "P6.15g")
const P615J_PARKED = "FULL run parked (D-174)"

# headers (G:results/TST/Relaxation/*; spec §3.1 O3–O6)
const P615J_H_WIDTH = "Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)"
const P615J_H_INNER = "Normalized time (T),Mean inner width (CD),STD inner width (CD)"
const P615J_H_S5 = "lambda,T (MCS),MSE"
const P615J_H_RUN = "MCS,t,N,r,A,C,w,g"
const P615J_H_MEAN = "MCS,t,N,r,A,C,w,g,runs"
const P615J_H_NEIGH = "n,p"
const P615J_H_PARAM = "name,value,unit"
const P615J_H_O1 = "x,y,i,n"
const P615J_H_O2 = "x,y,r,f,a"
const P615J_H_A3 = "MCS,t,f0,f1,f2,f3"
const P615J_H_O3 = Dict("beta" => "beta,Time to 10k (MCS),Time to 10k (5T)",
    "gamma" => "gamma,Time to 10k (MCS),Time to 10k (5T)")
const P615J_H_O5 = "x_pos,y_pos,radius_i,inhibited"

# parameters.csv rows (Table S1; src/openvt_reference.jl; spec §4.0.1 item 5)
const P615J_PARAMS = Dict(
    "A0" => 50.0, "lambda" => 2.0, "temperature" => 20.0, "alpha" => 50 / 775, "mu_X" => 2.0,
    "sigma_X" => 0.4, "J_cell_cell" => 20.0, "J_cell_medium" => 10.0, "cycle_MCS" => 775.0,
    "T_relax_lambda2_MCS" => 156.0, "R_px" => sqrt(50 / pi), "CD_px" => 10.0)
const P615J_PARAM_STR = Dict("neighbourhood" => "Moore(1)", "boundary" => "closed")

# optional items: key => (stem in the Pending section, path regex under results/Potts.jl/)
const P615J_OPTIONAL = [
    (:O1, "centroids/", r"^Monolayer/centroids/([a-z]+)/potts_([a-z]+)_s(\d+)_(\d{6})\.csv$"),
    (:O2, "Potts.jl_5T_MonolayerGrowth_1000_Data", r"^Monolayer/Potts\.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_(\d+)\.csv$"),
    (:A3, "inhibition_s", r"^Monolayer/metrics/([a-z]+)/inhibition_s(\d+)\.csv$"),
    (:O3b, "Potts.jl_time_to_10k_vs_beta.csv", r"^Monolayer/Potts\.jl_time_to_10k_vs_beta\.csv$"),
    (:O3g, "Potts.jl_time_to_10k_vs_gamma.csv", r"^Monolayer/Potts\.jl_time_to_10k_vs_gamma\.csv$"),
    (:O5, "final_snapshot_data", r"^Monolayer/final_snapshot_data/Potts\.jl_gamma_([0-9.eE+-]+)_(\d+)MCS\.csv$"),
]
const P615J_SWEEP_KEYS = (:O3b, :O3g, :O5)

const P615J_FORBIDDEN = [
    # the page test's list (D-178 (h))
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
    # private: people, machines, local paths
    r"praneeth"i, r"merugu"i, r"jiang"i, r"\bPI\b", r"nucbox"i, r"tailscale"i, r"100\.107\.",
    r"/Users/", r"/home/", r"/private/", r"/tmp/", r"\.claude", r"scratchpad"i,
]

# ---- small readers -------------------------------------------------------------------------------
p615j_lines(path) = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
function p615j_tsv(path)
    ls = p615j_lines(path)
    head = split(ls[1], '\t')
    rows = [Dict(zip(head, split(l, '\t'))) for l in ls[2:end]]
    return head, rows
end
function p615j_csv(path)
    ls = p615j_lines(path)
    return String(ls[1]), [String.(split(l, ',')) for l in ls[2:end]]
end
p615j_f(s) = parse(Float64, strip(s))
p615j_eq(a, b; rtol = 1e-12, atol = 1e-12) = (isnan(a) && isnan(b)) || (a == b) ||
    (isfinite(a) && isfinite(b) && abs(a - b) <= atol + rtol * max(abs(a), abs(b)))
p615j_col(head, name) = findfirst(==(name), head)

# records by ROADMAP item (P6.15i convention)
function p615j_records()
    recs = Dict{Symbol, String}()
    isdir(P615J_DATA) || return recs
    for d in sort(readdir(P615J_DATA))
        p = joinpath(P615J_DATA, d, "provenance.toml")
        isfile(p) || continue
        item = get(TOML.parsefile(p), "item", "")
        for (k, v) in P615J_ITEMS
            v == item && (recs[k] = d)
        end
    end
    return recs
end
const P615J_RECS = p615j_records()
p615j_rec(k) = joinpath(P615J_DATA, P615J_RECS[k])

# every file under dir, relative, '/'-separated, sorted
function p615j_tree(dir)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            push!(out, replace(relpath(joinpath(root, f), dir), '\\' => '/'))
        end
    end
    return sort(out)
end

# Markdown helpers (page-test conventions)
function p615j_section(md, heading_re)
    ls = split(md, '\n')
    i = findfirst(l -> occursin(r"^##\s", l) && occursin(heading_re, l), ls)
    i === nothing && return ""
    j = findnext(l -> occursin(r"^#{1,2}\s", l), ls, i + 1)
    return join(ls[i:(j === nothing ? length(ls) : j - 1)], '\n')
end
p615j_cells(l) = strip.(split(strip(strip(l), '|'), '|'))
function p615j_tables(sec)
    tabs = Vector{Vector{Vector{String}}}()
    cur = Vector{Vector{String}}()
    for l in split(sec, '\n')
        s = strip(l)
        if startswith(s, "|") && endswith(s, "|")
            occursin(r"^\|[\s:|-]+\|$", s) || push!(cur, String.(p615j_cells(s)))
        elseif !isempty(cur)
            push!(tabs, cur); cur = Vector{Vector{String}}()
        end
    end
    isempty(cur) || push!(tabs, cur)
    return tabs
end
function p615j_rows(sec)
    rows = Vector{Vector{String}}()
    hdr_ok = true
    for t in p615j_tables(sec)
        h = t[1]
        hdr_ok &= any(==("Ours"), h) && any(c -> c in ("Paper", "Manuscript", "M"), h) &&
                  any(c -> occursin(r"cause"i, c), h) && any(c -> occursin(r"Author question"i, c), h)
        append!(rows, t[2:end])
    end
    return rows, hdr_ok && !isempty(rows)
end
# a row is keyed by its first cell's first token: "C1" matches "C1" and "C1 (cycle)", not "C13"
p615j_row(rows, key) = findfirst(r -> !isempty(r) && occursin(Regex("^\\Q" * key * "\\E(?![0-9A-Za-z.])"), r[1]), rows)
p615j_first_decimal(s) = (m = match(r"\d+\.\d+", s); m === nothing ? nothing : m.match)
p615j_spec_cs() = unique([m.captures[1] for m in eachmatch(r"^\| (C\d+) \|"m, read(P615J_SPEC, String))])

# expected values from the records ---------------------------------------------------------------
function p615j_timeseries()
    head, rows = p615j_tsv(joinpath(p615j_rec(:f3f8), "timeseries.tsv"))
    runs = Dict{Tuple{String, Int}, Vector{Vector{Float64}}}()
    for r in rows
        r["case"] in P615J_CASES || continue
        v = [p615j_f(r[c]) for c in ("mcs", "N", "r", "A", "C", "w", "g")]
        push!(get!(runs, (r["case"], parse(Int, r["seed"])), Vector{Vector{Float64}}()), v)
    end
    for v in values(runs)
        sort!(v; by = first)
    end
    return runs
end
function p615j_mean_rows(ts, case)
    seeds = sort([s for (c, s) in keys(ts) if c == case])
    grids = [Set(Int(r[1]) for r in ts[(case, s)] if Int(r[1]) % P615J_GRID == 0) for s in seeds]
    grid = sort(collect(reduce(intersect, grids)))
    out = Vector{Vector{Float64}}()
    for m in grid
        row = Float64[m, m / P615J_CYCLE]
        for j in 2:7
            vals = [r[j] for s in seeds for r in ts[(case, s)] if Int(r[1]) == m]
            vals = filter(!isnan, vals)
            push!(row, isempty(vals) ? NaN : sum(vals) / length(vals))
        end
        push!(row, length(seeds))
        push!(out, row)
    end
    return out
end
function p615j_neighbors(case)
    _, rows = p615j_tsv(joinpath(p615j_rec(:f3f8), "neighbors.tsv"))
    c = Dict{Int, Float64}()
    for r in rows
        r["case"] == case || continue
        c[parse(Int, r["n"])] = get(c, parse(Int, r["n"]), 0.0) + p615j_f(r["count"])
    end
    tot = sum(values(c))
    return [(n, 100 * c[n] / tot) for n in sort(collect(keys(c))) if c[n] > 0]
end

# ---- build the package (twice, for determinism) ------------------------------------------------
const P615J_OUT = mktempdir()
const P615J_A = joinpath(P615J_OUT, "a")
const P615J_B = joinpath(P615J_OUT, "b")
const P615J_BUILT = Ref(false)
function p615j_build()
    P615J_BUILT[] && return true
    PottsModels.openvt_submission_package(P615J_A)
    sleep(1.1)                              # a clock tick between the two builds
    PottsModels.openvt_submission_package(P615J_B)
    P615J_BUILT[] = true
end
p615j_pkg(rel...) = joinpath(P615J_A, rel...)
p615j_res(rel...) = joinpath(P615J_A, P615J_RES, rel...)
p615j_impl(rel...) = joinpath(P615J_A, P615J_IMPL, rel...)

@testset "P6.15j (0) records present (D-146)" begin
    for k in (:calib, :f5, :f3f8, :f1f4)
        @test haskey(P615J_RECS, k)
    end
    @test isfile(P615J_SPEC)
    @test length(p615j_spec_cs()) >= 17
end

@testset "P6.15j (1) generator: builds both trees, refuses git and non-empty dirs" begin
    @test p615j_build()
    @test sort(readdir(P615J_A)) == ["implementations", "results"]
    @test readdir(joinpath(P615J_A, "implementations")) == ["Potts.jl"]
    @test readdir(joinpath(P615J_A, "results")) == ["Potts.jl"]
    # outside git only
    ingit = joinpath(P615J_ROOT, "lib", "PottsModels", "p615j_must_not_exist")
    @test_throws ArgumentError PottsModels.openvt_submission_package(ingit)
    @test !ispath(ingit)
    # no stale files: a non-empty directory is refused
    @test_throws ArgumentError PottsModels.openvt_submission_package(P615J_A)
end

@testset "P6.15j (2) deterministic: same bytes twice" begin
    @test p615j_build()
    ta, tb = p615j_tree(P615J_A), p615j_tree(P615J_B)
    @test ta == tb
    for f in ta
        f in tb || continue
        @test read(joinpath(P615J_A, f)) == read(joinpath(P615J_B, f))
    end
end

@testset "P6.15j (3) implementations/Potts.jl: model, runners, README, parameters" begin
    @test p615j_build()
    for f in ("openvt_reference.jl", "openvt_chain.jl")
        p = p615j_impl("src", f)
        @test isfile(p) && read(p) == read(joinpath(P615J_SRC, f))
    end
    readme = isfile(p615j_impl("README.md")) ? read(p615j_impl("README.md"), String) : ""
    @test !isempty(readme)
    @test occursin(P615J_REPO_URL, readme)
    @test occursin("Pkg.instantiate", readme)
    @test occursin("--project=lib/PottsModels/test", readme)
    @test occursin("openvt_submission_package", readme)
    @test occursin(r"julia"i, readme)
    for k in (:calib, :f5, :f3f8, :f1f4, :sweeps)
        haskey(P615J_RECS, k) || continue
        prov = TOML.parsefile(joinpath(p615j_rec(k), "provenance.toml"))
        runner = basename(prov["runner"])
        p = p615j_impl("scripts", P615J_RECS[k], runner)
        @test isfile(p) && read(p) == read(joinpath(p615j_rec(k), runner))
        @test occursin("scripts/$(P615J_RECS[k])/$(runner)", readme)
        @test occursin(prov["commit"][1:8], readme)
    end
    # extra scripts only as byte copies of their record's .jl files
    sd = p615j_impl("scripts")
    for f in (isdir(sd) ? p615j_tree(sd) : String[])
        parts = split(f, '/')
        @test length(parts) == 2 && endswith(parts[2], ".jl")
        src = joinpath(P615J_DATA, parts...)
        @test isfile(src) && read(joinpath(sd, f)) == read(src)
    end
    # parameters.csv
    p = p615j_impl("parameters.csv")
    @test isfile(p)
    if isfile(p)
        head, rows = p615j_csv(p)
        @test head == P615J_H_PARAM
        got = Dict(r[1] => r[2] for r in rows if length(r) == 3)
        @test all(r -> length(r) == 3, rows)
        for (k, v) in P615J_PARAMS
            @test haskey(got, k) && p615j_eq(p615j_f(got[k]), v; rtol = 1e-12)
        end
        for (k, v) in P615J_PARAM_STR
            @test get(got, k, "") == v
        end
    end
end

@testset "P6.15j (4) Relaxation: O4 widths and Table S5 equal the calibration record" begin
    @test p615j_build()
    rec = p615j_rec(:calib)
    meta = TOML.parsefile(joinpath(rec, "meta.toml"))
    _, r11 = p615j_tsv(joinpath(rec, "timeseries_11chain.tsv"))
    _, r21 = p615j_tsv(joinpath(rec, "timeseries_21chain.tsv"))
    function check(path, header, rows, cols)
        @test isfile(path)
        isfile(path) || return
        h, got = p615j_csv(path)
        @test h == header
        @test length(got) == length(rows)
        length(got) == length(rows) || return
        ok = true
        for (g, r) in zip(got, rows)
            ok &= length(g) == 3 && all(p615j_eq(p615j_f(g[j]), p615j_f(r[cols[j]])) for j in 1:3)
        end
        @test ok
    end
    lam(λ) = filter(r -> r["lambda"] == string(λ), r11)
    check(p615j_res("Relaxation", "11cells", "width.csv"), P615J_H_WIDTH, lam(2), ("t_over_T", "w11_mean", "w11_sd"))
    check(p615j_res("Relaxation", "11+10cells", "width.csv"), P615J_H_WIDTH, r21, ("t_over_T", "w21_mean", "w21_sd"))
    check(p615j_res("Relaxation", "11+10cells", "inner_width.csv"), P615J_H_INNER, r21,
        ("t_over_T", "inner_w11_mean", "inner_w11_sd"))
    for λ in P615J_LAMBDAS
        check(p615j_res("Relaxation", "lambda_scan", "11cells_lambda$(λ)_width.csv"), P615J_H_WIDTH, lam(λ),
            ("t_over_T", "w11_mean", "w11_sd"))
    end
    # Table S5 (P8 T, P9 MSE) recomputed from the record
    _, ref = p615j_tsv(joinpath(rec, "reference.tsv"))
    rt, rw = [p615j_f(r["t_over_T"]) for r in ref], [p615j_f(r["w"]) for r in ref]
    p = p615j_res("Relaxation", "table_S5.csv")
    @test isfile(p)
    if isfile(p)
        h, got = p615j_csv(p)
        @test h == P615J_H_S5
        @test [g[1] for g in got] == string.(P615J_LAMBDAS)
        for g in got
            λ = parse(Int, g[1])
            T = meta["T_ours"][string(λ)]
            post = filter(r -> p615j_f(r["t_mcs"]) >= 0, lam(λ))
            mse = PottsModels.Analysis.relaxation_mse([p615j_f(r["t_mcs"]) for r in post],
                [p615j_f(r["w11_mean"]) for r in post], T, rt, rw)
            @test parse(Int, g[2]) == T
            @test p615j_eq(p615j_f(g[3]), mse; rtol = 1e-9)
        end
    end
end

@testset "P6.15j (5) Monolayer metrics: O6 per run, means, neighbours equal the F3/F8 record" begin
    @test p615j_build()
    ts = p615j_timeseries()
    _, runs = p615j_tsv(joinpath(p615j_rec(:f3f8), "runs.tsv"))
    for case in P615J_CASES
        seeds = sort([parse(Int, r["seed"]) for r in runs if r["case"] == case])
        @test !isempty(seeds)
        for s in seeds
            p = p615j_res("Monolayer", "metrics", case, "measurements_s$(s).csv")
            @test isfile(p)
            isfile(p) || continue
            h, got = p615j_csv(p)
            @test h == P615J_H_RUN
            want = ts[(case, s)]
            ok = length(got) == length(want)
            if ok
                for (g, w) in zip(got, want)
                    ok &= length(g) == 8 && p615j_eq(p615j_f(g[1]), w[1]) &&
                          p615j_eq(p615j_f(g[2]), w[1] / P615J_CYCLE) &&
                          all(p615j_eq(p615j_f(g[j + 1]), w[j]) for j in 2:7)
                end
            end
            @test ok
        end
        # the mean (schema "Data Collection")
        p = p615j_res("Monolayer", "metrics", "measurements_$(case)_mean.csv")
        @test isfile(p)
        if isfile(p)
            h, got = p615j_csv(p)
            @test h == P615J_H_MEAN
            want = p615j_mean_rows(ts, case)
            ok = length(got) == length(want) && length(want) > 10
            if ok
                for (g, w) in zip(got, want)
                    ok &= length(g) == 9 && all(p615j_eq(p615j_f(g[j]), w[j]; rtol = 1e-10, atol = 1e-10) for j in 1:9)
                end
            end
            @test ok
        end
        # neighbour histogram (Category 3)
        p = p615j_res("Monolayer", "metrics", "neighbors_$(case).csv")
        @test isfile(p)
        if isfile(p)
            h, got = p615j_csv(p)
            @test h == P615J_H_NEIGH
            want = p615j_neighbors(case)
            @test length(got) == length(want)
            @test all(length(g) == 2 && parse(Int, g[1]) == w[1] && p615j_eq(p615j_f(g[2]), w[2]; rtol = 1e-10)
                      for (g, w) in zip(got, want))
        end
    end
end

@testset "P6.15j (6) closeup and provenance equal the records" begin
    @test p615j_build()
    p = p615j_res("closeup.png")
    @test isfile(p) && read(p) == read(joinpath(p615j_rec(:f1f4), "fig1.png"))
    for k in (:calib, :f5, :f3f8, :f1f4, :sweeps)
        haskey(P615J_RECS, k) || continue
        want = TOML.parsefile(joinpath(p615j_rec(k), "provenance.toml"))
        delete!(want, "hostname")
        q = p615j_res("provenance", P615J_RECS[k] * ".toml")
        @test isfile(q) && TOML.parsefile(q) == want
    end
    pd = p615j_res("provenance")
    @test isdir(pd) && sort(readdir(pd)) == sort([P615J_RECS[k] * ".toml" for k in keys(P615J_RECS)])
end

# the optional items, present (checked) or pending (named) -----------------------------------------
function p615j_present(rels, key)
    re = only(x[3] for x in P615J_OPTIONAL if x[1] == key)
    return filter(f -> occursin(re, f), rels)
end

@testset "P6.15j (7) optional items: present and checked, or listed as pending" begin
    @test p615j_build()
    rels = p615j_tree(joinpath(P615J_A, P615J_RES))
    readme = isfile(p615j_res("README.md")) ? read(p615j_res("README.md"), String) : ""
    pend = p615j_section(readme, r"Pending"i)
    @test !isempty(pend)
    swept = haskey(P615J_RECS, :sweeps)
    for (key, stem, _) in P615J_OPTIONAL
        files = p615j_present(rels, key)
        if isempty(files)
            @test occursin(stem, pend)
            if key in P615J_SWEEP_KEYS
                @test !swept                         # a merged P6.15g record must be packaged
                @test occursin(P615J_PARKED, pend)
            end
        else
            @test !occursin(stem, pend)
        end
    end
    # required items are never "pending"
    for stem in ("width.csv", "table_S5", "measurements_", "neighbors_", "closeup", "provenance")
        @test !occursin(stem, pend)
    end

    ts = p615j_timeseries()
    # O1: one file per save of every run, N rows each (spot-check: every run's last save, all of run 1)
    o1 = p615j_present(rels, :O1)
    if !isempty(o1)
        stamps = Dict{Tuple{String, Int}, Vector{Int}}()
        for f in o1
            m = match(P615J_OPTIONAL[1][3], f)
            @test m.captures[1] == m.captures[2]
            push!(get!(stamps, (m.captures[1], parse(Int, m.captures[3])), Int[]), parse(Int, m.captures[4]))
        end
        @test Set(keys(stamps)) == Set(keys(ts))
        for (k, v) in ts
            @test sort(get(stamps, k, Int[])) == [Int(r[1]) for r in v]
            seedmin = minimum(s for (c, s) in keys(ts) if c == k[1])
            for r in (k[2] == seedmin ? v : v[end:end])
                f = p615j_res("Monolayer", "centroids", k[1], "potts_$(k[1])_s$(k[2])_$(lpad(Int(r[1]), 6, '0')).csv")
                h, rows = p615j_csv(f)
                @test h == P615J_H_O1 && length(rows) == Int(r[2])
                @test all(x -> length(x) == 4 && parse(Int, x[3]) in 0:3 && parse(Int, x[4]) >= 0, rows)
            end
        end
    end
    # O2: case (b), file k equals runs.tsv row k (N, n_f0, Σf, Σa, max f, min a, max a)
    o2 = p615j_present(rels, :O2)
    if !isempty(o2)
        _, fr = p615j_tsv(joinpath(p615j_rec(:f5), "runs.tsv"))
        fb = filter(r -> r["case"] == "b", fr)
        @test sort([parse(Int, match(P615J_OPTIONAL[2][3], f).captures[1]) for f in o2]) == 1:100
        for r in fb
            f = p615j_res("Monolayer", "Potts.jl_5T_MonolayerGrowth_1000_Data", "cell_data_no_inhibition_$(r["k"]).csv")
            isfile(f) || (@test false; continue)
            h, rows = p615j_csv(f)
            @test h == P615J_H_O2
            fv = [p615j_f(x[4]) for x in rows]
            av = [p615j_f(x[5]) for x in rows]
            N = parse(Int, r["N"])
            @test length(rows) == N
            @test count(==(0.0), fv) == parse(Int, r["n_f0"])
            @test abs(sum(fv) - p615j_f(r["sum_f"])) <= 1e-9 * N
            @test abs(sum(av) - p615j_f(r["sum_a"])) <= 1e-9 * N
            @test p615j_eq(maximum(fv), p615j_f(r["f_max"]); rtol = 1e-10)
            @test p615j_eq(minimum(av), p615j_f(r["a_min"]); rtol = 1e-10)
            @test p615j_eq(maximum(av), p615j_f(r["a_max"]); rtol = 1e-10)
        end
    end
    # A3: inhibition shares sum to 1, on the run's saves (cases a, e)
    for f in p615j_present(rels, :A3)
        m = match(P615J_OPTIONAL[3][3], f)
        case, s = m.captures[1], parse(Int, m.captures[2])
        @test case in ("a", "e") && haskey(ts, (case, s))
        h, rows = p615j_csv(p615j_res(f))
        @test h == P615J_H_A3
        @test [p615j_f(x[1]) for x in rows] == [r[1] for r in get(ts, (case, s), Vector{Float64}[])]
        @test all(x -> abs(sum(p615j_f.(x[3:6])) - 1) <= 1e-9 && all(>=(0), p615j_f.(x[3:6])), rows)
    end
    # O3: header, ≥ 5 rows, 5T = MCS / 775 (or both non-finite for capped runs)
    for (key, par) in ((:O3b, "beta"), (:O3g, "gamma"))
        for f in p615j_present(rels, key)
            h, rows = p615j_csv(p615j_res(f))
            @test h == P615J_H_O3[par]
            @test length(rows) >= 5
            @test all(rows) do x
                mcs, t = p615j_f(x[2]), p615j_f(x[3])
                length(x) == 3 && (isfinite(mcs) ? abs(t - mcs / P615J_CYCLE) <= 0.005 : !isfinite(t))
            end
        end
    end
    # O5: ≥ 5 snapshots, header, inhibited ∈ {0, 1}
    o5 = p615j_present(rels, :O5)
    @test isempty(o5) || length(o5) >= 5
    for f in o5
        h, rows = p615j_csv(p615j_res(f))
        @test h == P615J_H_O5
        @test !isempty(rows) && all(x -> length(x) == 4 && x[4] in ("0", "1"), rows)
    end
end

@testset "P6.15j (8) allowlist: nothing but the pinned files (no G data, no stray files)" begin
    @test p615j_build()
    tree = p615j_tree(P615J_A)
    impl_ok(f) = f in ("README.md", "parameters.csv", "src/openvt_reference.jl", "src/openvt_chain.jl") ||
                 occursin(r"^scripts/[^/]+/[^/]+\.jl$", f)
    lam_files = ["Relaxation/lambda_scan/11cells_lambda$(λ)_width.csv" for λ in P615J_LAMBDAS]
    res_fixed = Set(["README.md", "closeup.png", "Relaxation/11cells/width.csv", "Relaxation/11+10cells/width.csv",
        "Relaxation/11+10cells/inner_width.csv", "Relaxation/table_S5.csv", lam_files...])
    res_ok(f) = f in res_fixed || occursin(r"^provenance/[^/]+\.toml$", f) ||
                occursin(r"^Monolayer/metrics/[a-z]+/measurements_s\d+\.csv$", f) ||
                occursin(r"^Monolayer/metrics/(measurements_[a-z]+_mean|neighbors_[a-z]+)\.csv$", f) ||
                any(x -> occursin(x[3], f), P615J_OPTIONAL)
    stray = String[]
    for f in tree
        if startswith(f, "implementations/Potts.jl/")
            impl_ok(f[(length("implementations/Potts.jl/") + 1):end]) || push!(stray, f)
        elseif startswith(f, "results/Potts.jl/")
            res_ok(f[(length("results/Potts.jl/") + 1):end]) || push!(stray, f)
        else
            push!(stray, f)
        end
    end
    @test isempty(stray)
    # no consortium framework names in any path (G:results/<FW>/…)
    @test !any(f -> occursin(r"TST|Morpheus|CompuCell|CC3D|Artistoo|PhysiCell|Chaste|polyhoop|tinydem|relaxation_exact"i, f), tree)
    # metrics only for the cases run
    @test Set(m.captures[1] for f in tree for m in (match(r"/metrics/([a-z]+)/measurements_s", f),) if m !== nothing) ==
          Set(P615J_CASES)
    # opt-in: no package file is byte-identical to a G file
    g = get(ENV, "OPENVT_MONOLAYER_REPO", "")
    if !isempty(g) && isdir(g)
        gh = Set{Vector{UInt8}}()
        for (root, _, files) in walkdir(g)
            occursin("/.git", root) && continue
            for f in files
                push!(gh, open(sha256, joinpath(root, f)))
            end
        end
        @test !any(f -> open(sha256, joinpath(P615J_A, f)) in gh, tree)
    end
end

@testset "P6.15j (9) results README: deviations (D-154), readings, colours, units, seeds" begin
    @test p615j_build()
    readme = isfile(p615j_res("README.md")) ? read(p615j_res("README.md"), String) : ""
    @test !isempty(readme)
    sec = p615j_section(readme, r"Deviations|Differences"i)
    rows, hdr = p615j_rows(sec)
    @test hdr
    function has(key; must = String[], mustnot = String[])
        i = p615j_row(rows, key)
        i === nothing && return false
        line = join(rows[i], " | ")
        return all(m -> occursin(m, line), must) && !any(m -> occursin(m, line), mustnot)
    end
    for c in p615j_spec_cs()
        @test has(c)
    end
    for d in readdir(P615J_DATA)
        p = joinpath(P615J_DATA, d, "deviations.tsv")
        isfile(p) || continue
        _, drows = p615j_tsv(p)
        for r in drows
            key = String(split(r["target"])[1])
            must = String[]
            (dec = p615j_first_decimal(r["ours"])) === nothing || push!(must, dec)
            occursin("FAIL", r["target"]) && push!(must, "FAIL")
            @test has(key; must)
        end
    end
    for d in readdir(P615J_DATA)
        p = joinpath(P615J_DATA, d, "verdicts.tsv")
        isfile(p) || continue
        _, vrows = p615j_tsv(p)
        for r in vrows
            get(r, "result", "") == "FAIL" || continue
            get(r, "case", "") == "control" && continue
            occursin(r"must FAIL"i, get(r, "band", "")) && continue
            occursin("(all rows)", r["target"]) && continue
            @test has(String(split(r["target"])[1]); must = ["FAIL"])
        end
    end
    @test has("V1"; must = ["15.17", "13.57", "C13", "actual area", "target area"], mustnot = ["PASS"])
    i = findfirst(r -> any(c -> occursin(r"per[- ]cell"i, c), r) && any(c -> occursin(r"area"i, c), r), rows)
    @test i !== nothing                                         # F1 colour row (D-175)
    @test findfirst(r -> any(c -> occursin(r"closed"i, c), r) && any(c -> occursin(r"edge[_ ]guard"i, c), r) &&
                         any(c -> occursin(r"unbounded"i, c), r), rows) !== nothing
    for r in rows
        @test occursin(r"^(not an author question|not asked|resolved)"i, r[end])
        any(c -> occursin(r"\bQ\d+\b", c), r) && @test any(c -> occursin("our open question list", c), r)
    end
    # per-cell colour choice stated in the prose too
    @test occursin(r"CellIdentityEncoding", readme)
    # units and seeds
    @test occursin("775", readme) && occursin("156", readme)
    @test occursin(r"cell radi"i, readme) && occursin(r"CD = 10 px"i, readme)
    m3 = TOML.parsefile(joinpath(p615j_rec(:f3f8), "meta.toml"))
    for c in P615J_CASES
        @test occursin(m3["cases"][c]["seeds"], readme)
    end
    # a Q# anywhere uses "our open question list"
    occursin(r"\bQ\d+\b", readme) && @test occursin("our open question list", readme)
end

@testset "P6.15j (10) nothing private, nothing implying contact" begin
    @test p615j_build()
    bad = String[]
    for f in p615j_tree(P615J_A)
        any(e -> endswith(f, e), (".md", ".csv", ".toml", ".jl", ".txt")) || continue
        # the public repository's owner/name (URLs to it are required) is not private
        s = replace(read(joinpath(P615J_A, f), String), "PraneethMerugu/Potts.jl" => "")
        for re in P615J_FORBIDDEN
            occursin(re, s) && push!(bad, "$f: $(re.pattern)")
        end
        occursin(P615J_OUT, s) && push!(bad, "$f: outdir")
        occursin(P615J_ROOT, s) && push!(bad, "$f: checkout path")
    end
    @test isempty(bad)
end
