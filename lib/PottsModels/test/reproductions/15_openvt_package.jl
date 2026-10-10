# P6.15j (ROADMAP Step 3b): the OpenVT monolayer submission package, in the consortium layout,
# prepared locally. Frozen (AUTONOMY §7.3). Submitting it is the maintainer's call; this test
# never contacts anyone and needs neither the PC nor the consortium clone (G).
#
# D-204 amendment (the package completed): every item the first freeze listed as optional or
# "Pending" is now REQUIRED: O1 (per-cell time series of cases a, b, e, f, re-run from the
# recorded seeds), O2 (case b), A3 (inhibition shares over time, from O1), O3 and O5 (the
# P6.15g sweeps record is merged), the MIT line (D-181), and a deterministic build outside
# git. The O1 files and the O2 files are too large for git (D-168, D-204): they live in a BULK
# directory outside git, `ENV["OPENVT_PACKAGE_BULK"]`, and git pins their MANIFEST (names, row
# counts, byte counts, inhibition-code counts, sha256), never their bytes. See "BULK inputs",
# "The O1 re-run record" and "The O1 recorder" below. On a machine without the bulk directory
# this test is red by design: a package without its data is not a submission. Reading the
# archives needs Info-ZIP `unzip` (`unzip -Z1`, `unzip -p`), present on macOS and on the PC.
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
# D-168, D-173, D-174 (+ amendment), D-175, D-178, D-185; amended under D-181 and D-204.
#
# Consortium layout (G at 54f375f, read on the PC; nothing copied), against which the D-204
# items are pinned where spec 15 agrees:
# - per-cell time series ship as .zip archives under results/<FW>/Monolayer/ (TST_No_CI_*.zip,
#   polyhoop noCI/*.zip, Morpheus per-replicate zips, PhysiCell pc_run<k>.zip); spec §4.0.1
#   says "compressed archives" without a format, so .zip.
# - their columns differ by framework (TST x_pos,y_pos,radius_i,a_i,f_i; Morpheus "x","y","g",
#   "n"; PhysiCell x,y,g,n; Artistoo cell_id,x,y,active,neighbors) and metrics.cpp reads x,y,
#   g,n. The spec (M, C8) says x,y,i,n: followed (disagreement 1).
# - their file names stamp the time point (Morpheus_timepoint_%05d, cell_data_no_inhibition_
#   <MCS>, pc_%03d, centroids_neighbors_mcs_<n>), one directory per run; the spec's
#   potts_<case>_s<seed>_<MCS:06d>.csv carries the seed instead: followed (disagreement 2).
#   run_metrics.sh's `seq 0 10000` index loop would skip our MCS stamps above 10 000 (a limit
#   of the script, not of the names).
# - TST ships the F5 1000-cell files zipped (TST_5T_MonolayerGrowth_1000_Data.zip); the spec
#   names the loose directory, which the first freeze checks file by file: kept loose
#   (disagreement 3).
# - lengths in R and time stamps in MCS with 5T = 775 MCS (TST README, Morpheus README): agree.
#
# ---------------------------------------------------------------------------------------------
# The generator (pinned)
# ---------------------------------------------------------------------------------------------
#   PottsModels.openvt_submission_package(outdir::AbstractString;
#                                         bulk = get(ENV, "OPENVT_PACKAGE_BULK", nothing)) -> outdir
#
# builds, under `outdir`, exactly two trees: `implementations/Potts.jl/` and `results/Potts.jl/`,
# from the merged records under `lib/PottsModels/reproductions/data/15/` (D-146) and the bulk
# directory `bulk` (D-204). It runs no simulation. It throws `ArgumentError` when `outdir` is
# inside this git checkout (the package lives outside git) or exists and is not empty (no stale
# files), and (D-204) when `bulk` is `nothing`, is not a directory, lies inside a git checkout,
# or lacks a file of the BULK layout below or holds one whose sha256 differs from the git
# manifest; a failed build leaves nothing behind (D-180). Two calls on the same commit and the
# same bulk directory give byte-identical trees (no timestamps, no absolute paths, fixed row
# order; the archives are copied byte for byte, never re-zipped). This test passes `bulk`
# through the environment variable only, so that it also runs against the first-freeze
# generator (which ignores it).
#
# Records are found the way the page test (P6.15i) finds them: the directories of `data/15/`
# whose `provenance.toml` names the ROADMAP item: P6.15b calibration (F2, S5), P6.15e F5,
# P6.15f F3/F8, P6.15h F1/F4, P6.15g the sweeps (F6, T1, F7; merged, D-174/D-178), and
# (D-204) P6.15j the O1 re-run record. The newest directory (by name) wins when an item has
# several.
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
#                        closeup's colours (D-185: area on coolwarm, provisional scale limits),
#                        a "Pending" section (see below)
#   closeup.png          byte-identical to the P6.15h record's fig1_panel.png, the bare Potts.jl
#                        panel without the banner, which the .tex adds (G:results/<FW>/closeup.png)
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
# Formerly OPTIONAL items: REQUIRED since D-204 (none may be named in a "Pending" section)
# ---------------------------------------------------------------------------------------------
# key  path under results/Potts.jl/                                      columns
# O1   Monolayer/Potts.jl_centroids_<case>.zip, case ∈ {a, b, e, f} (plus c, d only if the O1
#      record has them). A zip whose members are exactly, in this order, the record manifest's
#      files `centroids/<case>/potts_<case>_s<seed>_<MCS:06d>.csv` (spec §3.1 names; unzipped
#      in `Monolayer/` they land where the first freeze put loose O1 files). Each member: the
#      header `x,y,i,n`, one row per live cell. Bytes equal to the bulk archive and to the
#      record's archives.tsv sha256. Loose O1 files are no longer allowed (allowlist).
# O1m  Monolayer/Potts.jl_centroids_manifest.csv                        archive,file,rows,bytes,
#      sha256: the record's o1_manifest.tsv rows in its order (archive = the zip's name)
# O2   Monolayer/Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv, k = 1:100
#                                                                        x,y,r,f,a (F5; checked
#      against the F5 record as before, and their sha256 against the record's o2_manifest.tsv)
# A3   Monolayer/metrics/<case>/inhibition_s<seed>.csv                   MCS,t,f0,f1,f2,f3
#      for every run of cases a and e, and of c and d where O1 has them (spec §4.0 A3); one row
#      per O1 save in MCS order; t = MCS/775; f_k = (count of cells with i = k)/(cells), the
#      counts and cells of that save's O1 file (= the manifest's i0…i3 and rows).
# O3   Monolayer/Potts.jl_time_to_10k_vs_beta.csv, …_vs_gamma.csv        beta|gamma,Time to 10k
#      (MCS),Time to 10k (5T)   (F6, T1; byte copies of the P6.15g record's files)
# O5   Monolayer/final_snapshot_data/Potts.jl_gamma_<γ>_<MCS>MCS.csv    x_pos,y_pos,radius_i,
#      inhibited   (F7; byte copies of the P6.15g record's f7/ files, at least 5)
# The results README may keep a "Pending" section for other things, but it names none of the
# items above (their stems are in P615J_REQUIRED) and none of the first freeze's required ones.
# Both READMEs carry the MIT line (D-181): one line with "MIT", "licence"/"license" and
# "LICENSE" (the repository's LICENSE file). The copyright holder's name is not written into
# the package: the privacy scan (10) bans it, and the LICENSE file in the repository carries it.
#
# ---------------------------------------------------------------------------------------------
# BULK inputs (outside git; ENV["OPENVT_PACKAGE_BULK"])
# ---------------------------------------------------------------------------------------------
#   <bulk>/Potts.jl_centroids_<case>.zip              one per case of the O1 record
#   <bulk>/Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv, k = 1:100
# Nothing else is read from it. Expected volume (rows from the F3/F8 record's timeseries.tsv,
# about 44 B per O1 row and 20 B zipped with full-precision write_openvt floats, measured on
# the F5 O2 centroids): (a) 3 030 files, 4.34 M rows, ~190 MB raw, ~90 MB zipped; (e) 3 244,
# 5.74 M, ~250 MB, ~115 MB; (b) 20 741, 3.13 M, ~140 MB, ~65 MB; (f) 19 956, 2.40 M, ~105 MB,
# ~50 MB; O2 ~8 MB. About 320 MB zipped in all: D-204's ask-before-upload threshold applies.
#
# ---------------------------------------------------------------------------------------------
# The O1 re-run record (git; D-146 form; provenance.toml `item = "P6.15j"`)
# ---------------------------------------------------------------------------------------------
# data/15/<name>/ (e.g. o1-2026-10-10/), small files only, no verdicts.tsv or deviations.tsv:
#   provenance.toml   item "P6.15j", runner (in this directory), commit, threads, wall times,
#                     manifest_sha256 (as the other records; the package drops hostname/work)
#   runs.tsv          case k seed mcs N saves: one row per re-run; for a, b, e, f equal to the
#                     F3/F8 record's runs.tsv on these columns (D-204: the record reproduced)
#   o1_manifest.tsv   case seed mcs file rows bytes i0 i1 i2 i3 sha256: one row per O1 file,
#                     sorted by file; file = the archive member path; rows = data rows
#                     (header excluded); bytes = file size; i_k = cells with code k; sha256 of
#                     the file's bytes (lower-case hex)
#   archives.tsv      case archive members bytes sha256: one row per case,
#                     archive = Potts.jl_centroids_<case>.zip
#   o2_manifest.tsv   k file rows bytes sha256: k = 1:100, file =
#                     Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv
#   run_o1.jl         the runner
# Header-only templates of the four TSVs: test/reproductions/data/15j/ (tab-separated, '\n').
#
# ---------------------------------------------------------------------------------------------
# The O1 recorder (what the runner must write, and when; not implemented here)
# ---------------------------------------------------------------------------------------------
# - Runs: cases a, b, e, f of the frozen F3/F8 test (`P615F_CASES`, its seeds k ↦ seed, its
#   lattices, `P615F_ALG` = SequentialCPM(Moore(1)), the closed lattice, edge_guard(5;
#   terminate = true), stop_at_cells), i.e. `p615f_problem` and `p615f_run` reused, not copied.
# - When: exactly at the saves `p615f_run` records, by extending its `record(integ)`: MCS 0
#   (the callback's `initialize`), every MCS with t % 39 == 0, and the stopping MCS (first MCS
#   with ≥ cells live cells). Same callback, so the O1 stamps are the timeseries.tsv saves by
#   construction. At each save, after `p615f_row`:
#     fr = PottsModels.openvt_frame(integ.u; β = c.beta, γ = c.gamma)       # x, y in R, i, n
#     write_openvt(joinpath(stage, "centroids", case,
#                  openvt_filename(:O1; case, seed, mcs = Int(integ.t))), :O1, fr)
#   (`openvt_frame` takes the centroids from `openvt_snapshot`, as `p615f_row` does, so
#   `openvt_metrics` of the written file equals the record's r, A, C, w, g bit for bit; this
#   test recomputes them.) After each run, assert its series equals the F3/F8 record's rows.
# - Then: hash every file into o1_manifest.tsv, write runs.tsv, and zip each case with sorted
#   members, no directory entries and no extra attributes, from inside the staging directory:
#     find centroids/<case> -type f | LC_ALL=C sort | zip -X -D -9 -q -@ Potts.jl_centroids_<case>.zip
#   then archives.tsv. The zips go to the bulk directory; only the small files are committed.
# - O2: copy the surviving F5 files (the F5 runner's F5_O2_DIR) into the bulk directory; if
#   they are gone, write them from the case-b re-run's stop state with `openvt_snapshot`
#   (x, y, r, f, a; `write_openvt(…, :O2, …)`). Either way the F5 checks below must hold and
#   their x, y must equal the O1 stop file of the same seed (seed 15000 + k).
#
# ---------------------------------------------------------------------------------------------
# Content rules
# ---------------------------------------------------------------------------------------------
# - Allowlist: every file under outdir matches a required path; nothing else, so no
#   G file, figure or archive can ride along. Opt-in (OPENVT_MONOLAYER_REPO = a local G clone):
#   no package file is byte-identical to a G file.
# - Deviations (D-154; as the page test, D-178): results README has a level-2 heading with
#   "Deviations" or "Differences"; its Markdown tables have header cells "Ours", a paper column
#   ("Paper", "Manuscript" or "M"), "cause" and "Author question"; rows (keyed by first cell):
#   every C# of spec §1.1; every row of every data/15/*/deviations.tsv (its first decimal number
#   and FAIL when the target says FAIL); every non-control FAIL verdict (with FAIL); V1 (15.17,
#   13.57, C13, "actual area", "target area", not PASS); the F1 colour row (D-185: area on
#   coolwarm, the scale limits marked provisional);
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
    :sweeps => "P6.15g", :o1 => "P6.15j")
# D-204: the bulk directory (outside git) and the O1 re-run record
const P615J_BULK_ENV = "OPENVT_PACKAGE_BULK"
const P615J_BULK = get(ENV, P615J_BULK_ENV, "")
const P615J_O1_CASES = ["a", "b", "e", "f"]   # re-run from the P6.15f seeds (D-204 a)
const P615J_A3_CASES = ["a", "e"]             # spec §4.0 A3; c and d too where O1 has them
const P615J_SWEEP_CASE = Dict("c" => "beta", "d" => "gamma")
const P615J_O2_DIR = "Potts.jl_5T_MonolayerGrowth_1000_Data"
const P615J_O1_MANIFEST = "Potts.jl_centroids_manifest.csv"
p615j_o1_zip(case) = "Potts.jl_centroids_$(case).zip"
const P615J_O1_MEMBER = r"^centroids/([a-z]+)/potts_([a-z]+)_s(\d+)_(\d{6})\.csv$"
const P615J_H_O1M = ["case", "seed", "mcs", "file", "rows", "bytes", "i0", "i1", "i2", "i3", "sha256"]
const P615J_H_ARCH = ["case", "archive", "members", "bytes", "sha256"]
const P615J_H_O2M = ["k", "file", "rows", "bytes", "sha256"]
const P615J_H_O1RUNS = ["case", "k", "seed", "mcs", "N", "saves"]
const P615J_H_O1PKG = "archive,file,rows,bytes,sha256"
const P615J_LICENCE = "MIT"

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

# required items (optional in the first freeze): key => (stem that a Pending section must not
# name, path regex under results/Potts.jl/)
const P615J_REQUIRED = [
    (:O1, "centroids", r"^Monolayer/Potts\.jl_centroids_([a-z]+)\.zip$"),
    (:O1m, "centroids_manifest", r"^Monolayer/Potts\.jl_centroids_manifest\.csv$"),
    (:O2, "Potts.jl_5T_MonolayerGrowth_1000_Data", r"^Monolayer/Potts\.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_(\d+)\.csv$"),
    (:A3, "inhibition_s", r"^Monolayer/metrics/([a-z]+)/inhibition_s(\d+)\.csv$"),
    (:O3b, "Potts.jl_time_to_10k_vs_beta.csv", r"^Monolayer/Potts\.jl_time_to_10k_vs_beta\.csv$"),
    (:O3g, "Potts.jl_time_to_10k_vs_gamma.csv", r"^Monolayer/Potts\.jl_time_to_10k_vs_gamma\.csv$"),
    (:O5, "final_snapshot_data", r"^Monolayer/final_snapshot_data/Potts\.jl_gamma_([0-9.eE+-]+)_(\d+)MCS\.csv$"),
]

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
# the bulk directory reaches the generator through the environment only (see the header)
p615j_withbulk(f, bulk) = withenv(f, P615J_BULK_ENV => (bulk === nothing || isempty(bulk) ? nothing : bulk))
function p615j_build()
    P615J_BUILT[] && return true
    p615j_withbulk(P615J_BULK) do
        PottsModels.openvt_submission_package(P615J_A)
        sleep(1.1)                          # a clock tick between the two builds
        PottsModels.openvt_submission_package(P615J_B)
    end
    P615J_BUILT[] = true
end
p615j_pkg(rel...) = joinpath(P615J_A, rel...)
p615j_res(rel...) = joinpath(P615J_A, P615J_RES, rel...)
p615j_impl(rel...) = joinpath(P615J_A, P615J_IMPL, rel...)

# ---- D-204 helpers: git manifests, the bulk directory, zip members ------------------------------
function p615j_in_git(path)
    d = abspath(path)
    while true
        ispath(joinpath(d, ".git")) && return true
        p = dirname(d)
        p == d && return false
        d = p
    end
end
p615j_hex(s) = occursin(r"^[0-9a-f]{64}$", s)
p615j_sha(path) = bytes2hex(open(sha256, path))
p615j_has(rec, f) = isfile(joinpath(rec, f))
function p615j_tsv_or_empty(path)
    isfile(path) || return String[], Dict{String, String}[]
    head, rows = p615j_tsv(path)
    return String.(head), [Dict(String(k) => String(v) for (k, v) in r) for r in rows]
end
# o1_manifest.tsv as (case, seed) => rows sorted by mcs (each a NamedTuple)
function p615j_o1_manifest(rec)
    _, rows = p615j_tsv_or_empty(joinpath(rec, "o1_manifest.tsv"))
    out = Dict{Tuple{String, Int}, Vector{Any}}()
    for r in rows
        all(c -> haskey(r, c), P615J_H_O1M) || continue
        e = (; case = r["case"], seed = parse(Int, r["seed"]), mcs = parse(Int, r["mcs"]), file = r["file"],
            rows = parse(Int, r["rows"]), bytes = parse(Int, r["bytes"]),
            i = (parse(Int, r["i0"]), parse(Int, r["i1"]), parse(Int, r["i2"]), parse(Int, r["i3"])), sha = r["sha256"])
        push!(get!(out, (e.case, e.seed), Any[]), e)
    end
    foreach(v -> sort!(v; by = e -> e.mcs), values(out))
    return out
end
p615j_o1_rec() = haskey(P615J_RECS, :o1) ? p615j_rec(:o1) : ""
p615j_o1_cases(man) = sort(unique(first.(collect(keys(man)))))
# the manifest rows of one case in member order (by file name)
p615j_o1_members(man, case) = sort([e for ((c, _), v) in man if c == case for e in v]; by = e -> e.file)

# a bulk directory with every expected name but wrong bytes (for the refusal check)
function p615j_bogus_bulk(cases)
    d = mktempdir()
    foreach(c -> write(joinpath(d, p615j_o1_zip(c)), "not a zip\n"), cases)
    mkpath(joinpath(d, P615J_O2_DIR))
    foreach(k -> write(joinpath(d, P615J_O2_DIR, "cell_data_no_inhibition_$(k).csv"), "x,y,r,f,a\n"), 1:100)
    return d
end

# the names of a zip's entries, in archive order (Info-ZIP `unzip -Z1`)
p615j_zip_names(zip) = filter(!isempty, readlines(`unzip -Z1 $zip`))

# one O1 member's bytes: header, data rows, code counts, n ≥ 0 and well-formed rows
function p615j_o1_scan(buf::Vector{UInt8})
    nl = findfirst(==(0x0a), buf)
    nl === nothing && return (; header = "", rows = 0, i = (0, 0, 0, 0), ok = false)
    header = String(buf[1:(nl - 1)])
    cnt = zeros(Int, 4)
    rows, ok, k, n = 0, true, nl + 1, length(buf)
    comma, zero, nine = UInt8(','), UInt8('0'), UInt8('9')
    while k <= n
        j = findnext(==(0x0a), buf, k)
        j === nothing && (ok = false; break)           # last line without '\n'
        c1 = findnext(==(comma), buf, k)
        c2 = c1 === nothing ? nothing : findnext(==(comma), buf, c1 + 1)
        c3 = c2 === nothing ? nothing : findnext(==(comma), buf, c2 + 1)
        if c3 === nothing || c3 >= j || c3 != c2 + 2 || !(zero <= buf[c2 + 1] <= zero + 3) || c3 + 1 > j - 1 ||
           !all(b -> zero <= b <= nine, view(buf, (c3 + 1):(j - 1))) || c1 == k || c2 == c1 + 1
            ok = false
        else
            cnt[buf[c2 + 1] - zero + 1] += 1
        end
        rows += 1
        k = j + 1
    end
    return (; header, rows, i = Tuple(cnt), ok)
end
function p615j_o1_parse(buf::Vector{UInt8})
    ls = split(String(copy(buf)), '\n'; keepempty = false)[2:end]
    f = [split(l, ',') for l in ls]
    return (; x = [parse(Float64, r[1]) for r in f], y = [parse(Float64, r[2]) for r in f],
        i = [parse(Int, r[3]) for r in f], n = [parse(Int, r[4]) for r in f])
end

# the F3/F8 runs.tsv as (case, seed) => row
function p615j_runs3()
    _, rows = p615j_tsv(joinpath(p615j_rec(:f3f8), "runs.tsv"))
    return Dict((String(r["case"]), parse(Int, r["seed"])) => r for r in rows)
end

@testset "P6.15j (0) records present (D-146)" begin
    for k in (:calib, :f5, :f3f8, :f1f4)
        @test haskey(P615J_RECS, k)
    end
    # D-204: the sweeps record is merged and the O1 re-run record exists
    @test haskey(P615J_RECS, :sweeps)
    @test haskey(P615J_RECS, :o1)
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
    # D-204: the bulk directory is given, outside git, complete and equal to the git manifests;
    # otherwise the build is refused and leaves nothing behind
    @test !isempty(P615J_BULK) && isdir(P615J_BULK) && !p615j_in_git(P615J_BULK)
    for bulk in (nothing, P615J_DATA, mktempdir(), p615j_bogus_bulk(P615J_O1_CASES))
        out = joinpath(mktempdir(), "pkg")
        threw = try
            p615j_withbulk(() -> PottsModels.openvt_submission_package(out), bulk)
            false
        catch e
            e isa ArgumentError
        end
        @test threw
        @test !ispath(out) || isempty(readdir(out))
    end
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
    for k in (:calib, :f5, :f3f8, :f1f4, :sweeps, :o1)
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
    @test isfile(p) && read(p) == read(joinpath(p615j_rec(:f1f4), "fig1_panel.png"))
    for k in (:calib, :f5, :f3f8, :f1f4, :sweeps, :o1)
        haskey(P615J_RECS, k) || continue
        want = TOML.parsefile(joinpath(p615j_rec(k), "provenance.toml"))
        delete!(want, "hostname")
        q = p615j_res("provenance", P615J_RECS[k] * ".toml")
        @test isfile(q) && TOML.parsefile(q) == want
    end
    pd = p615j_res("provenance")
    @test isdir(pd) && sort(readdir(pd)) == sort([P615J_RECS[k] * ".toml" for k in keys(P615J_RECS)])
end

# the formerly optional items, all required (D-204) -----------------------------------------------
function p615j_present(rels, key)
    re = only(x[3] for x in P615J_REQUIRED if x[1] == key)
    return filter(f -> occursin(re, f), rels)
end

@testset "P6.15j (7) formerly optional items: all present and checked (D-204)" begin
    @test p615j_build()
    rels = p615j_tree(joinpath(P615J_A, P615J_RES))
    readme = isfile(p615j_res("README.md")) ? read(p615j_res("README.md"), String) : ""
    pend = p615j_section(readme, r"Pending"i)
    for (key, stem, _) in P615J_REQUIRED
        @test !isempty(p615j_present(rels, key))
        @test !occursin(stem, pend)
    end
    # required items are never "pending" (a Pending section may remain for other things)
    for stem in ("width.csv", "table_S5", "measurements_", "neighbors_", "closeup", "provenance",
                 "O1", "O2", "A3", "O3", "O5", "parked")
        @test !occursin(stem, pend)
    end

    ts = p615j_timeseries()
    rec = p615j_o1_rec()
    man = isempty(rec) ? Dict{Tuple{String, Int}, Vector{Any}}() : p615j_o1_manifest(rec)
    o1cases = p615j_o1_cases(man)
    # O1: one archive per case of the O1 record (their bytes and members: testsets 11 and 12)
    @test !isempty(o1cases)
    @test sort([match(P615J_REQUIRED[1][3], f).captures[1] for f in p615j_present(rels, :O1)]) == o1cases

    # O2: case (b), file k equals runs.tsv row k (N, n_f0, Σf, Σa, max f, min a, max a), and its
    # bytes equal the O2 manifest of the O1 record
    o2 = p615j_present(rels, :O2)
    _, fr = p615j_tsv(joinpath(p615j_rec(:f5), "runs.tsv"))
    fb = filter(r -> r["case"] == "b", fr)
    _, o2m = isempty(rec) ? (String[], Dict{String, String}[]) : p615j_tsv_or_empty(joinpath(rec, "o2_manifest.tsv"))
    o2row = Dict(r["file"] => r for r in o2m if haskey(r, "file"))
    @test sort([parse(Int, match(P615J_REQUIRED[3][3], f).captures[1]) for f in o2]) == 1:100
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
        m = get(o2row, "$(P615J_O2_DIR)/cell_data_no_inhibition_$(r["k"]).csv", nothing)
        @test m !== nothing && m["sha256"] == p615j_sha(f) && parse(Int, m["bytes"]) == filesize(f) &&
              parse(Int, m["rows"]) == length(rows)
    end

    # A3: shares of the inhibition codes per O1 save, for every run of cases a and e (and of c, d
    # where O1 has them); f_k = i_k/cells of that save's O1 file; f0 is the record's g
    a3 = p615j_present(rels, :A3)
    a3cases = sort(union(P615J_A3_CASES, intersect(o1cases, collect(keys(P615J_SWEEP_CASE)))))
    want = sort([(c, s) for (c, s) in keys(isempty(man) ? ts : man) if c in a3cases])
    got = sort([(m.captures[1], parse(Int, m.captures[2])) for f in a3 for m in (match(P615J_REQUIRED[4][3], f),)])
    @test !isempty(want) && got == want
    for f in a3
        m = match(P615J_REQUIRED[4][3], f)
        case, s = m.captures[1], parse(Int, m.captures[2])
        @test case in a3cases && haskey(man, (case, s))
        h, rows = p615j_csv(p615j_res(f))
        @test h == P615J_H_A3
        case in P615J_CASES &&
            @test [p615j_f(x[1]) for x in rows] == [r[1] for r in get(ts, (case, s), Vector{Float64}[])]
        @test all(x -> abs(sum(p615j_f.(x[3:6])) - 1) <= 1e-9 && all(>=(0), p615j_f.(x[3:6])), rows)
        mrows = get(man, (case, s), Any[])
        ok = length(rows) == length(mrows)
        for (x, e) in zip(rows, mrows)
            ok &= length(x) == 6 && p615j_f(x[1]) == e.mcs && p615j_eq(p615j_f(x[2]), e.mcs / P615J_CYCLE) &&
                  all(p615j_eq(p615j_f(x[2 + k]), e.i[k] / e.rows) for k in 1:4)
        end
        @test ok
        if haskey(ts, (case, s))
            w = ts[(case, s)]
            @test length(rows) == length(w) && all(p615j_eq(p615j_f(x[3]), r[7]) for (x, r) in zip(rows, w))
        end
    end

    # O3: header, ≥ 5 rows, 5T = MCS / 775 (or both non-finite for capped runs); byte copies of
    # the P6.15g record's tables
    sw = haskey(P615J_RECS, :sweeps) ? p615j_rec(:sweeps) : ""
    for (key, par) in ((:O3b, "beta"), (:O3g, "gamma"))
        files = p615j_present(rels, key)
        @test length(files) == 1
        for f in files
            h, rows = p615j_csv(p615j_res(f))
            @test h == P615J_H_O3[par]
            @test length(rows) >= 5
            @test all(rows) do x
                mcs, t = p615j_f(x[2]), p615j_f(x[3])
                length(x) == 3 && (isfinite(mcs) ? abs(t - mcs / P615J_CYCLE) <= 0.005 : !isfinite(t))
            end
            @test !isempty(sw) && read(p615j_res(f)) == read(joinpath(sw, basename(f)))
        end
    end
    # O5: ≥ 5 snapshots, header, inhibited ∈ {0, 1}; byte copies of the record's f7/ files
    o5 = p615j_present(rels, :O5)
    @test length(o5) >= 5
    f7 = isempty(sw) ? String[] : filter(n -> occursin(r"^Potts\.jl_gamma_.+MCS\.csv$", n), readdir(joinpath(sw, "f7")))
    @test sort(basename.(o5)) == sort(f7)
    for f in o5
        h, rows = p615j_csv(p615j_res(f))
        @test h == P615J_H_O5
        @test !isempty(rows) && all(x -> length(x) == 4 && x[4] in ("0", "1"), rows)
        @test !isempty(sw) && read(p615j_res(f)) == read(joinpath(sw, "f7", basename(f)))
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
                any(x -> occursin(x[3], f), P615J_REQUIRED)
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
    i = findfirst(r -> occursin(r"^F1"i, r[1]) && any(c -> occursin(r"coolwarm"i, c), r) && any(c -> occursin(r"area"i, c), r) &&
                       any(c -> occursin(r"provisional"i, c), r), rows)
    @test i !== nothing                                         # F1 colour row (D-185)
    @test findfirst(r -> any(c -> occursin(r"closed"i, c), r) && any(c -> occursin(r"edge[_ ]guard"i, c), r) &&
                         any(c -> occursin(r"unbounded"i, c), r), rows) !== nothing
    for r in rows
        @test occursin(r"^(not an author question|not asked|resolved)"i, r[end])
        any(c -> occursin(r"\bQ\d+\b", c), r) && @test any(c -> occursin("our open question list", c), r)
    end
    # the closeup's colours stated in the prose too (D-185)
    @test occursin(r"coolwarm", readme) && occursin(r"provisional"i, readme)
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

@testset "P6.15j (11) O1 re-run record: its manifest reproduces the F3/F8 record (D-204 a, b)" begin
    rec = p615j_o1_rec()
    @test !isempty(rec)
    if !isempty(rec)
        for f in ("provenance.toml", "runs.tsv", "o1_manifest.tsv", "archives.tsv", "o2_manifest.tsv")
            @test p615j_has(rec, f)
        end
        prov = p615j_has(rec, "provenance.toml") ? TOML.parsefile(joinpath(rec, "provenance.toml")) : Dict{String, Any}()
        @test get(prov, "item", "") == "P6.15j"
        @test occursin(r"^[0-9a-f]{40}$", get(prov, "commit", ""))
        @test p615j_has(rec, basename(get(prov, "runner", "-")))
        @test !haskey(prov, "work")                                  # no local paths (D-195)
        @test !p615j_has(rec, "verdicts.tsv") && !p615j_has(rec, "deviations.tsv")
        for (f, h) in (("o1_manifest.tsv", P615J_H_O1M), ("archives.tsv", P615J_H_ARCH), ("o2_manifest.tsv", P615J_H_O2M),
                       ("runs.tsv", P615J_H_O1RUNS))
            @test first(p615j_tsv_or_empty(joinpath(rec, f))) == h
        end
        man = p615j_o1_manifest(rec)
        cases = p615j_o1_cases(man)
        @test issubset(P615J_O1_CASES, cases) && issubset(cases, ["a", "b", "c", "d", "e", "f"])
        # rows well formed (spec §3.1 names), files unique and sorted
        _, raw = p615j_tsv_or_empty(joinpath(rec, "o1_manifest.tsv"))
        files = [r["file"] for r in raw if haskey(r, "file")]
        @test length(files) == length(raw) && files == sort(files) && allunique(files)
        ok = true
        for v in values(man), e in v
            m = match(P615J_O1_MEMBER, e.file)
            ok &= m !== nothing && m.captures[1] == e.case && m.captures[2] == e.case &&
                  parse(Int, m.captures[3]) == e.seed && parse(Int, m.captures[4]) == e.mcs &&
                  e.rows >= 1 && all(>=(0), e.i) && sum(e.i) == e.rows && e.bytes > ncodeunits(P615J_H_O1) + 1 &&
                  p615j_hex(e.sha)
        end
        @test ok
        # the F3/F8 record reproduced: every save's MCS and cell count, the growing fraction
        # (i = 0 share = g), the stop MCS, final N and save count of runs.tsv
        ts = p615j_timeseries()
        runs3 = p615j_runs3()
        meta3 = TOML.parsefile(joinpath(p615j_rec(:f3f8), "meta.toml"))
        for case in P615J_O1_CASES
            want = sort([s for (c, s) in keys(runs3) if c == case])
            @test sort([s for (c, s) in keys(man) if c == case]) == want
            γ0 = meta3["cases"][case]["gamma"] == 0
            for s in want
                v, w, r = get(man, (case, s), Any[]), ts[(case, s)], runs3[(case, s)]
                @test [e.mcs for e in v] == [Int(x[1]) for x in w]
                @test [e.rows for e in v] == [Int(x[2]) for x in w]
                @test length(v) == length(w) && all(p615j_eq(e.i[1] / e.rows, x[7]) for (e, x) in zip(v, w))
                @test !isempty(v) && last(v).mcs == parse(Int, r["mcs"]) && last(v).rows == parse(Int, r["N"]) &&
                      length(v) == parse(Int, r["saves"])
                γ0 && @test all(e -> e.i[3] == 0 && e.i[4] == 0, v)
            end
        end
        # cases c and d only where O1 has them: the sweeps record's stops; saves at 0, every 39 MCS, the stop
        if any(in(cases), ("c", "d"))
            inv = Dict(v => k for (k, v) in P615J_SWEEP_CASE)
            _, swr = p615j_tsv(joinpath(p615j_rec(:sweeps), "runs.tsv"))
            sweep = Dict((inv[String(r["sweep"])], parse(Int, r["seed"])) => r for r in swr)
            for ((c, s), v) in man
                c in ("c", "d") || continue
                r = get(sweep, (c, s), nothing)
                @test r !== nothing && last(v).mcs == parse(Int, r["mcs"]) && last(v).rows == parse(Int, r["N"])
                m = [e.mcs for e in v]
                @test m[1] == 0 && all(x -> x % P615J_GRID == 0, m[1:(end - 1)]) && all(diff(m) .> 0)
            end
        end
        # runs.tsv: one row per re-run, equal to the F3/F8 record's rows on these columns
        _, rr = p615j_tsv_or_empty(joinpath(rec, "runs.tsv"))
        got = Dict((r["case"], parse(Int, r["seed"])) => r for r in rr if haskey(r, "case") && haskey(r, "seed"))
        @test Set(keys(got)) == Set(keys(man))
        for ((c, s), r3) in runs3
            c in P615J_O1_CASES || continue
            r = get(got, (c, s), nothing)
            @test r !== nothing && all(get(r, k, "") == String(r3[k]) for k in ("k", "mcs", "N", "saves"))
        end
        # archives.tsv: one archive per case, with its member count
        _, ar = p615j_tsv_or_empty(joinpath(rec, "archives.tsv"))
        @test sort([get(r, "case", "") for r in ar]) == cases
        for r in ar
            @test get(r, "archive", "") == p615j_o1_zip(r["case"]) &&
                  parse(Int, r["members"]) == length(p615j_o1_members(man, r["case"])) &&
                  parse(Int, r["bytes"]) > 0 && p615j_hex(r["sha256"])
        end
        # o2_manifest.tsv (D-204 b): k = 1:100, the F5 names and cell counts
        _, o2m = p615j_tsv_or_empty(joinpath(rec, "o2_manifest.tsv"))
        _, fr = p615j_tsv(joinpath(p615j_rec(:f5), "runs.tsv"))
        nb = Dict(String(r["k"]) => parse(Int, r["N"]) for r in fr if r["case"] == "b")
        @test sort([parse(Int, get(r, "k", "0")) for r in o2m]) == 1:100
        for r in o2m
            @test get(r, "file", "") == "$(P615J_O2_DIR)/cell_data_no_inhibition_$(r["k"]).csv" &&
                  parse(Int, r["rows"]) == get(nb, r["k"], -1) && parse(Int, r["bytes"]) > 0 && p615j_hex(r["sha256"])
        end
    end
end

@testset "P6.15j (12) O1 archives in the package: bytes and every member equal the manifest (D-204 a)" begin
    @test p615j_build()
    rec = p615j_o1_rec()
    man = isempty(rec) ? Dict{Tuple{String, Int}, Vector{Any}}() : p615j_o1_manifest(rec)
    cases = p615j_o1_cases(man)
    @test !isempty(cases)
    @test Sys.which("unzip") !== nothing
    # the package's manifest: the record's rows, archive by archive, in member order
    p = p615j_res("Monolayer", P615J_O1_MANIFEST)
    @test isfile(p)
    if isfile(p)
        h, rows = p615j_csv(p)
        @test h == P615J_H_O1PKG
        @test rows == [[p615j_o1_zip(c), e.file, string(e.rows), string(e.bytes), e.sha]
                       for c in cases for e in p615j_o1_members(man, c)]
    end
    _, ar = isempty(rec) ? (String[], Dict{String, String}[]) : p615j_tsv_or_empty(joinpath(rec, "archives.tsv"))
    arch = Dict(r["case"] => r for r in ar if haskey(r, "case"))
    ts = p615j_timeseries()
    _, nbr = p615j_tsv(joinpath(p615j_rec(:f3f8), "neighbors.tsv"))
    nbh = Dict{Tuple{String, Int}, Dict{Int, Int}}()
    for r in nbr
        d = get!(nbh, (String(r["case"]), parse(Int, r["seed"])), Dict{Int, Int}())
        d[parse(Int, r["n"])] = get(d, parse(Int, r["n"]), 0) + parse(Int, r["count"])
    end
    _, fr = p615j_tsv(joinpath(p615j_rec(:f5), "runs.tsv"))
    o2k = Dict(parse(Int, r["seed"]) => String(r["k"]) for r in fr if r["case"] == "b")
    for case in cases
        z = p615j_res("Monolayer", p615j_o1_zip(case))
        a = get(arch, case, nothing)
        @test isfile(z) && a !== nothing
        (isfile(z) && a !== nothing && Sys.which("unzip") !== nothing) || continue
        # bytes: the record's archive, and the bulk directory's (copied, never re-zipped)
        @test filesize(z) == parse(Int, a["bytes"]) && p615j_sha(z) == a["sha256"]
        bz = joinpath(P615J_BULK, p615j_o1_zip(case))
        @test isfile(bz) && filesize(bz) == filesize(z) && p615j_sha(bz) == a["sha256"]
        mem = p615j_o1_members(man, case)
        @test p615j_zip_names(z) == [e.file for e in mem]               # exactly these, in this order
        # every member: sha256, header x,y,i,n, rows, code counts, n ≥ 0 (byte scan). Spot set
        # (parsed): every save of the case's first seed and every run's stop: finite x, y; the
        # record's N, r, A, C, w, g recomputed by openvt_metrics; the stop's neighbour histogram
        # (neighbors.tsv); for case b, the stop's x, y equal to the O2 file of the same seed
        seeds = sort(unique(e.seed for e in mem))
        stop = Dict(s => maximum(e.mcs for e in mem if e.seed == s) for s in seeds)
        bad = String[]
        open(`unzip -p $z`) do io
            for e in mem
                buf = read(io, e.bytes)
                length(buf) == e.bytes || (push!(bad, "$(e.file): short"); break)
                bytes2hex(sha256(buf)) == e.sha || push!(bad, "$(e.file): sha256")
                sc = p615j_o1_scan(buf)
                (sc.ok && sc.header == P615J_H_O1 && sc.rows == e.rows && sc.i == e.i) || push!(bad, "$(e.file): content")
                (e.seed == first(seeds) || e.mcs == stop[e.seed]) || continue
                o = p615j_o1_parse(buf)
                (all(isfinite, o.x) && all(isfinite, o.y)) || push!(bad, "$(e.file): non-finite centroid")
                if haskey(ts, (case, e.seed))
                    j = findfirst(r -> Int(r[1]) == e.mcs, ts[(case, e.seed)])
                    if j === nothing
                        push!(bad, "$(e.file): no timeseries row")
                    else
                        w = ts[(case, e.seed)][j]
                        mt = PottsModels.openvt_metrics(o.x, o.y, Float64.(o.i .== 0))
                        (length(o.x) == Int(w[2]) && all(p615j_eq(getfield(mt, k), w[c]) for (k, c) in
                                                         ((:r, 3), (:A, 4), (:C, 5), (:w, 6), (:g, 7)))) ||
                            push!(bad, "$(e.file): metrics differ from timeseries.tsv")
                    end
                end
                e.mcs == stop[e.seed] || continue
                if haskey(nbh, (case, e.seed))
                    hist = Dict{Int, Int}()
                    foreach(n -> hist[n] = get(hist, n, 0) + 1, o.n)
                    hist == nbh[(case, e.seed)] || push!(bad, "$(e.file): neighbour histogram differs from neighbors.tsv")
                end
                if case == "b"
                    f = p615j_res("Monolayer", P615J_O2_DIR, "cell_data_no_inhibition_$(get(o2k, e.seed, "0")).csv")
                    if isfile(f)
                        _, r2 = p615j_csv(f)
                        (length(r2) == length(o.x) &&
                         all(p615j_f(r[1]) == x && p615j_f(r[2]) == y for (r, x, y) in zip(r2, o.x, o.y))) ||
                            push!(bad, "$(e.file): x, y differ from the O2 file")
                    else
                        push!(bad, "$(e.file): no O2 file for seed $(e.seed)")
                    end
                end
            end
            eof(io) || push!(bad, "$(case): bytes after the last member")
        end
        @test isempty(bad)
        isempty(bad) || @info "P6.15j (12) $(case)" first(bad, 10)
    end
end

@testset "P6.15j (13) MIT licence line in both READMEs (D-181, D-204 d)" begin
    @test p615j_build()
    for p in (p615j_impl("README.md"), p615j_res("README.md"))
        txt = isfile(p) ? read(p, String) : ""
        @test any(l -> occursin(Regex("\\b" * P615J_LICENCE * "\\b"), l) && occursin("LICENSE", l) &&
                       occursin(P615J_REPO_URL, l), split(txt, '\n'))
    end
end
