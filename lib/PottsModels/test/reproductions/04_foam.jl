# P6.4r (ROADMAP Phase 6; D-186 foam streams 3–5): reproduction 04, Jiang, Swart, Saxena,
# Asipauskas & Glazier, "Hysteresis and avalanches in two-dimensional foam rheology
# simulations", Phys. Rev. E 59, 5819 (1999) ("04b"). Frozen (AUTONOMY §7.3). The
# pre-registered targets are spec 04 §5.2 V1–V20 (docs/design/research/model-specs/04_foam.md);
# every band below is copied from §5.2's "Acceptance" column, with the observable, the
# protocol, the run lengths, the replicate counts and the seeds fixed here. Decisions: D-186
# (streams), D-155/D-156 (ship provisional; unstated parameters are calibrated and labelled),
# D-146 (FULL offline, record under reproductions/data/04/), D-153 (test form), D-154
# (deviations table), D-158 (pins), D-048 (oracles, negative controls).
#
# ── APIs this file names that do not exist on the freeze base (d7fc5793) ──────────────────
# - P6.4b2 (feat/p6-4b2, frozen test acceptance/p6_4b2_foam_analysis.jl), in
#   PottsModels.Analysis: stored_energy, side_counts, contact_changes, t1_events,
#   central_moment, topology_moments, power_spectrum, spectral_exponent, mean_t1,
#   yield_strain (and the existing cell_graph). Used exactly as that file pins them.
# - P6.4a1 (feat/p6-4a1, frozen test acceptance/p6_4a1_copy_direction.jl): the copy-scope
#   `direction[1]` (x_target − x_source, minimum image on the periodic x axis),
#   `position[target][2]` and `mcs` in a drive.
#
# ── Gating ─────────────────────────────────────────────────────────────────────────────────
# Every no-shear row (V1, V1b, PREP, V19 on the relaxed foam, the observable oracles) needs
# only P6.4b2 and binds as soon as it lands. The sheared model `P64RShearedFoam` is built by
# `p64r_build_shear()`; on a tree without P6.4a1 that build fails with
# `UndefVarError(:direction)` or "… is not available in a drive", and ONLY those two errors
# close the gate (any other error is rethrown). Gate closed: every shear testset records one
# `@test_broken` per row and runs nothing; FULL refuses to run. Gate open: the rows bind.
# The FULL record tier: no record and gate closed → `@test_broken` (pending P6.4a1); no
# record and gate open → fails (the FULL run is due).
#
# ── Protocol (pre-registered) ──────────────────────────────────────────────────────────────
# Lattice 256² (L_x × L_y), `boundary = (Periodic(), Closed())` (04b p.5822). Contacts
# `NeighborOrder(4)` (20 neighbours, 04b p.5822) with J = 3; area term Γ(a − A)² with Γ = 1
# (04b p.5823); dry foam, no medium site. Proposals `NeighborOrder(4)` under
# `BoundarySiteCPM()` (deviation DV1 below). T = 0 is `Metropolis(; temperature = 1e-6)`, the
# T → 0⁺ limit of spec A-6 (ties accepted with P = 1, uphill rejected; integer contact and
# area ΔH ≥ 1; P6.4a1 item 5 shows the residual band 0 < ΔH < 1e-4 is negligible).
# Start: the brick wall, 16² bricks in common bond (brick row r = 0..15 from y = 1, odd rows
# shifted by 8 in x with wrap; id = 16r + column + 1), A_n = 256 (04b p.5823).
# Ordered foam (04b p.5823 steps 1–3): anneal at T_A = 3 for N_A = 10 MCS, then relax at
# T = 0 for N_R = 1000 MCS (A-8 calibration).
# Disordered foam (steps 4–5): from the ordered foam (same seed), Γ = 0 at T_C = 3; every 10
# MCS μ2(n) of the current state (`topology_moments`) is read and coarsening stops at the
# first read ≥ the target (at most 20 000 MCS); A_n := the bubble's area at the stop; relax
# at T = 0, Γ = 1 for N_R MCS. Accepted when |μ2(n)(relaxed) − target| ≤ 0.3; otherwise the
# next try (seed + 1), at most 5 tries (PREP row). Foams:
#   ordered (256²); d081, d165, d172, d202 (targets 0.81, 1.65, 1.72, 2.02; 256²);
#   d095, d107 (targets 0.95, 1.07; 320², 400 bricks; A-14 reading, deviation DV4).
# Replicate k of a configuration runs on foam k of its kind (paired design across a scan).
# Shear (A-1 calibration F1, D-155): copying σ_j into site i adds
#   ΔH_shear = γ(y_i, t)·direction[1],  direction[1] = x_i − x_j (minimum image),
#   Eq. 6 boundary: γ = +γ0·G on y = 1, −γ0·G on y = L_y, 0 elsewhere;
#   Eq. 7 bulk:     γ = −β·(y − (L_y + 1)/2)·G (y from the mid-plane, A-3);
#   G = 1 (steady) or sin(ω·mcs), ω = 2π/(4000τ) (periodic, 4000 paper MCS; 04b p.5822).
#   Sign: γ > 0 biases copies toward −x (04b p.5822), so the top (y = L_y) moves +x and the
#   bottom −x, as the arrows of Figs. 2(a), 4(a), 5(a).
# Time calibration τ (A-5 reading, DV1). The paper picks a site at random, counts every pick
# as a trial, and proposes only at wall sites and only to an unlike neighbour (04b p.5822).
# Under DV1 a pick proposes a uniform neighbour among the 20 and the like ones are null, so
# each wall site is updated ū times as often per MCS as in the paper, ū = the mean over
# boundary sites of (unlike offsets)/20 (`p64r_ubar`, off-lattice offsets are null). One
# paper MCS is therefore τ = 1/ū of ours; τ is measured on ordered foams 1–5 before any
# shear run (≈ 3.3 on the brick wall) and every shear duration, period, bin, window,
# t_first and spectral frequency below is in PAPER MCS (our MCS m is paper time m/τ;
# `power_spectrum(x; dt = 1/τ)`). Foam preparation (A-8) is in our MCS. When P6.4b's
# `UnlikeNeighbor` replaces DV1, τ = 1 by construction (a new D-entry re-runs).
# γ-scale calibration κ (A-1, "γ0/J ≈ 1.9"): model field = κ × paper field, for γ0 AND β.
# Stage 1 (set "cal"): J = 3, model r = γ0_model/J on the geometric grid 2^(−2:0.25:6)
# (0.25 … 64); r* = the first r at which the median over replicates of the mean T1 events
# per cycle crosses 0.5 (linear interpolation; a crossing at the first grid point or none at
# all leaves κ undefined and FULL stops: a science question); κ = 3r*/5.8 (paper: butterfly
# → U between γ0 = 5.7 and 5.8 at J = 3, Fig. 3(a)). Stage 2 (set "scan", V5) and every
# other row run at κ × the paper value. V3's "transition 5.8 ± 1.2" is consumed by the
# calibration (reported, not a target). Feasibility probe on the freeze base (reference
# shear model with site coordinates, 1 period of 4000 of OUR MCS, J = 3): no T1 up to
# γ0_model = 24 and loop height 1.1 % there, so κ is large without τ; hence the wide grid.
# T1 counting unit (A-15 calibration): `t1_events(prev, next; unit = :t1)` on the
# VonNeumann(1) `cell_graph` of consecutive MCS (one T1 = 1, a half-completed T1 = ½). The
# paper's even-valued bars (Figs. 4b, 5b) are `:pairs` = 2 × `:t1`; no target uses absolute
# bar heights. "k T1s per cycle" means the count rounds to k: thresholds at k − ½.
# Wall type (A-2 calibration): `Closed()` y edges, no wall cells, a wall is not a side. The
# brick wall then has μ2(n) = 7/16 = 0.4375 exactly (paper Fig. 11(c) ≈ 0.437); the
# alternatives give 0.109 (wall counted as a side) and 0 (periodic y): negative controls.
# Eq. 6 rows are y = 1 and y = L_y.
#
# ── Observables ────────────────────────────────────────────────────────────────────────────
# φ = `stored_energy(σ, lat)` (Eq. 8, unordered NeighborOrder(4) pairs, θ = 1);
# φ̂ = φ/φ(start of the run). n = `side_counts` (VonNeumann(1)). A bubble is live if it owns
# a site; an edge bubble touches y = 1 or y = L_y; interior = live and not edge. Hexagon
# fraction = interior bubbles with n = 6 over interior bubbles. Area fraction (V19) =
# E_a/(E_a + J·φ), E_a = Γ Σ_live (a − A)². Centroid y = mean y of the bubble's sites;
# "mid" = |y_c − (L_y + 1)/2| ≤ 32 (the two rows beside the mid-plane and one more each
# side; the next rows sit at 40). t_first = `yield_strain((1:T)/τ, N; threshold = 1,
# window = 100τ)` on the per-MCS T1 series N (the first T1 avalanche, paper MCS; none → −1).
# ε_y = β_paper·t_first (A-9: only ratios are targets; c ≈ 0.023 of spec §3.2 is info).
# N̄ = `mean_t1([total]; bubbles = live bubbles at t = 0, strain = β_paper·T_run)` (A-9:
# unit shear = β·t, as spec §3.2 and claim 14 read it). Spectra: `power_spectrum` of the
# per-MCS series (T1 events, φ̂) over 2^17 paper MCS (f to 0.5, lowest 7.6e-6, as Fig. 8),
# averaged into 20 log bins per decade (edges 10^(−5.2:0.05:−0.3); bin f = geometric mean
# of its f_k, S = mean of its S_k), then averaged over replicates; α =
# `spectral_exponent(f_bin, S_bin; range)` over [1e-4, 1e-2] unless stated; bins with S ≤ 0
# are dropped and fewer than 2 bins give NaN (the row fails). Window α: every
# [f_b, 10 f_b] with f_b a bin frequency inside the row's span. Peak (V7 iii): the raw T1
# periodogram smoothed by a centred 5-point mean; f* = its argmax over [2e-4, 5e-3];
# prominence = smoothed peak / median of the raw S over the same span.
# Drops: a zigzag filter with threshold h on φ̂ (a peak is confirmed when φ̂ falls h below
# the running maximum, a trough when it rises h above the running minimum; a final falling
# leg ends at its running minimum); drop amplitude = peak − following trough.
# Bursts: maximal runs of non-zero 50-MCS T1 bins, single empty bins bridged; quiet share =
# empty bins / bins. Loops: φ̂ every 10 of our MCS, phase bin b = 1..40 = ⌊40·mod(m, P)/P⌋ + 1
# with P = ⌈4000τ⌉ (strain at its centre γ0_paper·sin(2π(b − ½)/40)); per-replicate curve = bin means over
# the 10 periods; ensemble curve = mean of the replicate curves; height = max − min of the
# ensemble curve; noise = mean over replicates and bins of the std over the 10 periods of
# the per-period bin means; T1 per cycle = mean over the 10 cycles; "median" = over
# replicates.
#
# ── Rows (FULL; 5 replicates unless stated) ────────────────────────────────────────────────
# | Row  | Target (spec §5.2) | Rule | Tier |
# |------|--------------------|------|------|
# | V1   | relaxed ordered foam all-hexagonal | hexagon fraction ≥ 0.95 in every replicate (10) | SMOKE (2), FULL |
# | V1b  | μ2(n) baseline from truncated rows | μ2(n) ∈ [0.3, 0.6] in every replicate (10) | SMOKE (2), FULL |
# | PREP | disordered foams hit their μ2(n) | every foam accepted (|Δ| ≤ 0.3); mean μ2(a) of d165, d172 > of d095, d107 | SMOKE (d081 ×1), FULL |
# | V2   | ordered, steady boundary γ0 = 7 (A-12), 10⁴ MCS | (i) pooled interior n = 6 share over 50-MCS frames > 0.95; (ii) per replicate, zigzag h = 0.002 on 50-MCS φ̂: ≥ 3 drops, median drop ∈ [0.005, 0.02], CV of peak spacings ≤ 0.3, in ≥ 4/5; (iii) per replicate ≥ 3 bursts and quiet share ≥ 0.3, in ≥ 4/5 | FULL |
# | V3   | J = 3 loops vs γ0 (10 periods) | γ0 = 1: height < 0.002, median T1/cycle < 0.5; γ0 = 3.5: median < 0.5, height ∈ [0.01, 0.03]; γ0 = 7: median ≥ 0.5, argmax of the curve at |strain| > 0.8γ0 | FULL |
# | V4   | J sweep at γ0 = 7 | median T1/cycle: J = 10, 5 < 0.5; J = 3 ∈ [0.5, 2.5); J = 1 ≥ 1.5; non-increasing in J | FULL |
# | V5   | (J, γ0) boundaries through the origin | J ∈ {1,3,5,10}, paper r = γ0/J ∈ 0.25:0.25:6.0 (model γ0 = κJr); boundaries (paper γ0 = J·r_b): elastic e = height crossing 0.002, first-T1 1 = median crossing 0.5, 2 = 1.5, 3 = 2.5 (a crossing at the first grid point is unresolved); fit γ0 = a + sJ: s_e ∈ [0.7, 1.4], s_1 ∈ [1.4, 2.5], |a| ≤ 1.6 for both; order r_e < r_1 ≤ r_2 ≤ r_3 where found | FULL |
# | V6   | T ∈ {0, 5, 10, 15}, J = 3, γ0 = 4 | median mean φ̂ strictly increasing in T; height/noise > 3 at T = 0, < 1 at T = 15; slope per unit T vs 0.014 ± 50 % is info | FULL |
# | V7   | ordered bulk β = 0.01 | (i) mid share of non-hexagonal interior bubble-frames (100-MCS frames after t_first, pooled) ≥ 0.9; (ii) median drop (h = 0.001, 100-MCS φ̂) ≤ 0.6 × V2's (V2 φ̂ subsampled to 100 MCS); (iii) f* ∈ (5e-4, 1.5e-3) with prominence ≥ 3 in ≥ 4/5 | FULL |
# | V8   | ordered bulk β = 0.05 delocalised | mid share (as V7 i) < 0.5 | FULL |
# | V9   | d165, steady boundary γ0 = 7 | t_first < 100 in ≥ 4/5 | FULL |
# | V10  | ordered T1 spectra | α(0.05) ∈ [0.7, 1.3]; |α(0.02)| < 0.3 | FULL |
# | V11  | d081 T1 spectra, β ∈ {0.001, 0.005, 0.01, 0.02, 0.05} | Spearman(β, α) ≥ 0.8; α(0.05) ∈ [0.7, 1.2]; α(0.001) < 0.4 | FULL |
# | V12  | d165, β ∈ {0.001, 0.01, 0.05}: no T1 power law | max window α over f_b ∈ [1e-4, 1e-2] ≤ 0.5 | FULL |
# | V13  | φ spectra 1/f-like | every (foam, β) of the spectral set: α_φ ∈ [0.5, 1.2] and max window α_φ (f_b ∈ [1e-5, 0.05]) < 1.5; d165 β = 0.005: α_φ on [1e-4, 1e-3] and [1e-3, 1e-2] ∈ [0.5, 1.2] | FULL |
# | V14  | N̄(β), foams d165, d172 (high μ2(a)) and d107, d095 (low), β ∈ {1e-4, 1e-3, 5e-3, 1e-2, 5e-2}, 2^15 MCS | per foam N̄(1e-4)/N̄(1e-3) ∈ [4, 25] and N̄(1e-3)/N̄(5e-2) ≥ 10; at β ≥ 5e-3 mean N̄(high pair)/mean N̄(low pair) ≥ 5 (means over replicates) | FULL |
# | V15  | yield strain (spectral set) | ordered: (max − min)/mean of median ε_y over β ∈ {0.001, 0.005, 0.01} ≤ 0.10; median ε_y(0.05)/median ε_y(0.01) ∈ [0.25, 0.6]; every ordered run yields with t_first ≥ 100. d081, d165 at β ≥ 0.01: median ε_y ≤ 0.045 × the ordered plateau (= 0.05/1.11, c-free) | FULL |
# | V16  | d081, d165, d172, d202 at β = 0.01, 10⁴ MCS | mean μ2(n) over windows ending in [2000, 10⁴] − μ2(n)(0) ≥ 0.1 in ≥ 4/5, each foam | FULL |
# | V17  | ordered β = 0.01 | baseline = median μ2(n) of the 100-MCS windows; excursions = runs of windows > baseline + 0.01; ≥ 80 % of them (pooled, ≥ 3 needed) overlap a falling leg [peak, trough] of the zigzag (h = 0.001) | FULL |
# | V18  | no system-wide avalanches | every bulk and steady run: max share of live bubbles in a contact change within a 100-MCS window < 0.5 | FULL |
# | V19  | area energy ≪ total at T = 0 | area fraction < 5e-3: every relaxed ordered foam; mean over the windows of the ordered β = 0.01 runs | SMOKE (relaxed), FULL |
# | V20  | bulk/boundary drop ratio | median drop (bulk, β = 0.01) / median drop (V2, at 100 MCS), h = 0.001 ∈ [0.2, 0.6] | FULL |
#
# Negative controls (D-048): C-V1b (hand-built: the brick wall with the wall counted as a
# side, 0.109, and with periodic y, 0, both outside V1b's band); C-V1 (the d081 foam:
# hexagon fraction < 0.95); C-V9 (the ordered foam under V9's shear: t_first ≥ 100 in
# ≥ 4/5); C-V12 (V12's statistic on the ordered β = 0.05 spectrum > 0.5); C-V16 (d165 at
# β = 0: the V16 rise < 0.1 in ≥ 4/5); C-V18 (hand-built: a row shift changes every
# neighbour list, share 1); SMOKE: C-S1 (β = 0: no drift), C-S2 (β = 0: no T1).
# Info (reported, not gating): r*, κ, τ, V3's transition in paper units (5.8 by construction),
# V6's slope, V15 absolute ε_y with c = 0.023, V5 boundaries 2 and 3.
#
# ── Labelled deviations (D-154 rows) ───────────────────────────────────────────────────────
# DV1 proposal: `BoundarySiteCPM` with a uniform neighbour among the 20 (D-186) instead of
#     the paper's unlike-neighbour draw (P6.4b `UnlikeNeighbor`); same move given an unlike
#     draw, different per-site rates; the mean rate is corrected by τ (A-5), the per-site
#     spread is not.
# DV2 T = 0 as T = 1e-6 (A-6 T → 0⁺).
# DV3 γ scale calibrated (κ), displacement form of Eq. 2 (A-1, F1, D-155); time scale τ.
# DV4 d095/d107 on 320² (A-14: 377/380 bubbles cannot come from 16² bricks on 256²).
# DV5 unstated values chosen here: steady boundary γ0 = 7 (Figs. 2, 6; A-12), β = 0.01 for
#     Fig. 11(b) (V16), run lengths of V14 (2^15) and V16 (10⁴), A-8 numbers above.
#
# ── Spec readings flagged (closest to the paper) ───────────────────────────────────────────
# R1 "≥ 5 seeds" → 5 replicates, each on its own foam (paired across a scan).
# R2 V2 (i) "rows 2..N−1" → interior bubbles = not touching y = 1 or y = L_y.
# R3 V3 "zero T1s" / "≥ 1 T1 per cycle" → median mean count < 0.5 / ≥ 0.5 (rounding).
# R4 V6 "loop area / noise" → ensemble height / mean per-period bin std.
# R5 V7 "within ±1 bubble row of mid-height" → |y_c − y_mid| ≤ 32 (see Observables).
# R6 V12 "no fit range of more than 1 decade with α > 0.5" → 1-decade windows with
#    f_b ∈ [1e-4, 1e-2] (below 1e-4 is the paper's finite-record ringing, above 0.1 its
#    sharp high-f drop).
# R7 V14 "N̄(high)/N̄(low)" → mean of the pair over mean of the pair (min/max fails on
#    the paper's own Fig. 9 at 5e-2: 0.013/0.006).
# R8 V15 "ε_y ≤ 0.05" (absolute) → ε_dis ≤ (0.05/1.11) × ordered plateau (c-free).
# R9 V18 "fraction changing neighbours" → bubbles in any lost or gained contact
#    (`contact_changes`) between consecutive MCS within the window.
#
# ── Cost (estimate; the per-MCS rate under shear is measured on the Mac only) ─────────────
# Measured on the freeze base (Apple M-series, one thread): 256² NeighborOrder(4) under
# BoundarySiteCPM at T → 0⁺ ≈ 1.4 ms/MCS without shear; ≈ 3.8 ms/MCS with the per-MCS
# neighbour diff under boundary shear (reference shear model, stub analysis functions);
# a reduced end-to-end FULL (stubs) averaged ≈ 4.2 ms/MCS. Foams ≈ 2 s (ordered), ≈ 4 s
# (disordered). Not measured: the PC, and the real P6.4a1/P6.4b2 code (spec §8 guessed
# 5 ms/MCS, ≈ 10 min per 10⁵ MCS). Paper MCS per block (× τ ≈ 3.3 for ours): κ stage
# 33 × 5 × 4e4 = 6.6e6; V5 scan 4 × 24 × 5 × 4e4 = 1.9e7; V3/V4/V6 50 × 4e4 = 2e6; V2/V9
# 1e5; spectral set 75 × 2^17 = 9.8e6; V14 100 × 2^15 = 3.3e6; V16 25 × 1e4 = 2.5e5.
# Total ≈ 4.1e7 paper = 1.35e8 of our MCS ≈ 140–190 CPU-h at 4 ms (loops ≈ 68 %, spectral
# set ≈ 24 %), ≈ 6–8 h on the PC's 24 threads. SMOKE: ≈ 30 s of runs plus model
# compilation (no-shear ≈ 15 s, shear ≈ 10 s).
#
# Tiers. always: rules on synthetic series and hand-built states (oracles). SMOKE (default):
# the no-shear rows at full size, then (gate open) the κ-free shear checks. FULL record
# (always): reads the one directory reproductions/data/04/full-*, recomputes τ, κ and every
# row; a failing row must be listed in its deviations.tsv (D-154) and is then
# `@test_broken`. FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full; offline on the PC,
# D-146, D-157): reruns everything; with P64R_RECORD_OUT=<dir> it also writes the record.
#
# Record schema (TSV, one header line; vectors comma-joined; NaN as "NaN"): see
# P64R_SCHEMA; plus provenance.toml (commit, seeds, threads, machine, wall time),
# verdicts.tsv (id, kind, value, band, result) and an optional deviations.tsv (id, ours,
# paper, cause, question).
using Potts, PottsModels, Test
using Statistics: mean, median, std

const P64R_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P64R_DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "04")
const P64R_RECORD_OUT = get(ENV, "P64R_RECORD_OUT", "")
const P64R_AN = PottsModels.Analysis

# ---------------------------------------------------------------------------------------------
# Constants (pre-registered)
# ---------------------------------------------------------------------------------------------

const P64R_L = (256, 256)
const P64R_L_LOW = (320, 320)                          # DV4: d095, d107
const P64R_BRICK = 16
const P64R_J = 3.0
const P64R_Γ = 1.0
const P64R_T0 = 1.0e-6                                 # T → 0⁺ (A-6, DV2)
const P64R_TA, P64R_NA, P64R_NR = 3.0, 10, 1000        # anneal T, MCS; relax MCS (A-8)
const P64R_TC, P64R_CHECK, P64R_CMAX = 3.0, 10, 20_000 # coarsening T, μ2 read cadence, cap (A-8)
const P64R_PREP_TOL, P64R_TRIES = 0.3, 5
const P64R_PERIOD, P64R_CYCLES, P64R_NBIN = 4000, 10, 40   # paper MCS per period
const P64R_TSPEC, P64R_T14, P64R_T16 = 2^17, 2^15, 10_000
const P64R_TV2, P64R_TV9 = 10_000, 5000
const P64R_REPS = 5
const P64R_MID = 32.0
const P64R_FOAMS = (ordered = (target = 0.0, L = P64R_L, code = 0), d081 = (target = 0.81, L = P64R_L, code = 1),
    d095 = (target = 0.95, L = P64R_L_LOW, code = 2), d107 = (target = 1.07, L = P64R_L_LOW, code = 3),
    d165 = (target = 1.65, L = P64R_L, code = 4), d172 = (target = 1.72, L = P64R_L, code = 5),
    d202 = (target = 2.02, L = P64R_L, code = 6))
const P64R_SCAN_J = [1.0, 3.0, 5.0, 10.0]
const P64R_CAL_R = 2.0 .^ (-2:0.25:6)                 # κ stage: model γ0/J at J = 3 (0.25 … 64)
const P64R_SCAN_R = collect(0.25:0.25:6.0)              # V5 stage: paper γ0/J, model γ0 = κ·J·r
const P64R_BETAS = [0.001, 0.005, 0.01, 0.02, 0.05]
const P64R_BETAS14 = [1e-4, 1e-3, 5e-3, 1e-2, 5e-2]
const P64R_V6_T = [P64R_T0, 5.0, 10.0, 15.0]
const P64R_BIN_EDGES = 10 .^ (-5.2:0.05:-0.3)
const P64R_C_YIELD = 0.023                             # spec §3.2 c (info only)

# seeds: foam k of kind f, try t; run (block, index, replicate)
p64r_prep_seed(f::Symbol, k, t = 0) = 4_000_000 + 100_000 * P64R_FOAMS[f].code + 100k + t
p64r_run_seed(block, idx, k) = 5_000_000 + 1_000_000block + 10idx + k
p64r_smoke_seed(k) = 9_400_000 + k
const P64R_BLOCK = (scan = 1, v3 = 2, v4 = 3, v6 = 4, v2 = 5, v9 = 6, v9c = 7, spec = 8, v14 = 9, v16 = 10, v16c = 11, cal = 12)

# ---------------------------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------------------------

@potts_model P64RFoam begin
    @structural_parameters begin
        lattice = (256, 256)
    end
    @kinds medium bubble
    @parameters begin
        J = 3.0
        Γ = 1.0
        T = 1.0e-6
    end
    @variables begin
        A(cell) = 256.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    @sweep Metropolis(; temperature = T)
end

# Eq. 1 + Eq. 2 in the displacement form (A-1). ytop = L_y and ymid = (L_y + 1)/2 are set
# per lattice by p64r_problem. bulk = 1: Eq. 7; else Eq. 6. periodic = 1: G = sin(ω mcs).
const P64R_SHEAR_EXPR = :(@potts_model P64RShearedFoam begin
    @structural_parameters begin
        lattice = (256, 256)
    end
    @kinds medium bubble
    @parameters begin
        J = 3.0
        Γ = 1.0
        T = 1.0e-6
        γ0 = 0.0
        β = 0.0
        bulk = 0.0
        periodic = 0.0
        ω = 2π / 4000
        ytop = 256.0
        ymid = 128.5
    end
    @variables begin
        A(cell) = 256.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    @drive copy => ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
                   ifelse(bulk > 0.5, -β * (position[target][2] - ymid),
        γ0 * (ifelse(position[target][2] < 1.5, 1.0, 0.0) - ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0))) *
                   direction[1]
    @sweep Metropolis(; temperature = T)
end)

"""Build `P64RShearedFoam` and a tiny problem from it: true, or false iff the tree lacks
P6.4a1 (`direction` undefined, or `mcs`/`position` rejected in a drive)."""
function p64r_build_shear()
    try
        Core.eval(@__MODULE__, P64R_SHEAR_EXPR)
        M = Base.invokelatest(getfield, @__MODULE__, :P64RShearedFoam)
        σ = Int32[(x - 1) ÷ 8 + 1 for x in 1:16, y in 1:16]
        Base.invokelatest(() -> PottsProblem(M(; name = :p64r_probe, lattice = (16, 16)),
            [ownership => σ, kind => [:bubble, :bubble], :A => [128.0, 128.0], :ytop => 16.0, :ymid => 8.5], (0, 1)))
        return true
    catch e
        err = e isa LoadError ? e.error : e
        (err isa UndefVarError && err.var === :direction) && return false
        (err isa ArgumentError && occursin("is not available in a drive", err.msg)) && return false
        rethrow()
    end
end
const P64R_SHEAR_READY = p64r_build_shear()
P64R_SHEAR_READY || @info "04 foam: P6.4a1 (`direction`) is not on this tree; the shear rows are gated (@test_broken)"

const P64R_ALG = BoundarySiteCPM()
const P64R_TEMPLATES = Dict{Tuple{Bool, Tuple{Int, Int}}, Any}()

p64r_brick(L) = Int32[(r = (y - 1) ÷ P64R_BRICK; r * (L[1] ÷ P64R_BRICK) + mod(x - 1 - (isodd(r) ? P64R_BRICK ÷ 2 : 0), L[1]) ÷ P64R_BRICK + 1)
                      for x in 1:L[1], y in 1:L[2]]
p64r_lat(L) = Lattice(L; boundary = (Periodic(), Closed()))

"""The template problem of (shear?, L); built once, outside any threaded loop."""
function p64r_template(shear::Bool, L)
    get!(P64R_TEMPLATES, (shear, L)) do
        σ = p64r_brick(L)
        n = Int(maximum(σ))
        op = Pair[ownership => σ, kind => fill(:bubble, n), :A => fill(256.0, n)]
        if shear
            M = Base.invokelatest(getfield, @__MODULE__, :P64RShearedFoam)
            sys = Base.invokelatest(() -> M(; name = :p64r_shear, lattice = L))
            append!(op, [:ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2])
        else
            sys = P64RFoam(; name = :p64r, lattice = L)
        end
        PottsProblem(sys, op, (0, 1); seed = 1)
    end
end
"""A problem from a state (; σ, A) for `tend` MCS. Every parameter is set explicitly."""
function p64r_problem(st, tend; shear = false, J = P64R_J, Γ = P64R_Γ, T = P64R_T0, γ0 = 0.0, β = 0.0,
        bulk = false, periodic = false, ω = 2π / P64R_PERIOD, seed)
    L = size(st.σ)
    n = length(st.A)
    n == maximum(st.σ) || throw(ArgumentError("p64r_problem: A has $n entries, the largest id is $(maximum(st.σ))"))
    p = Pair{Symbol, Float64}[:J => J, :Γ => Γ, :T => T]
    shear && append!(p, [:γ0 => γ0, :β => β, :bulk => Float64(bulk), :periodic => Float64(periodic), :ω => ω,
        :ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2])
    return remake(P64R_TEMPLATES[(shear, L)]; u0 = Pair[ownership => st.σ, kind => fill(:bubble, n), :A => st.A], p,
        tspan = (0, tend), seed)
end

# ---------------------------------------------------------------------------------------------
# Observables on a state
# ---------------------------------------------------------------------------------------------

"""Per-bubble site count, centroid y and edge flag; ids 1:n."""
function p64r_cells(σ, n)
    Y = size(σ, 2)
    cnt = zeros(Int, n)
    sy = zeros(n)
    edge = falses(n)
    for y in 1:Y, x in 1:size(σ, 1)
        c = σ[x, y]
        cnt[c] += 1
        sy[c] += y
        (y == 1 || y == Y) && (edge[c] = true)
    end
    return (; cnt, cy = sy ./ max.(cnt, 1), edge)
end
"""n per id 1:n (0 for ids above maximum(σ))."""
p64r_sides(σ, lat, n) = (s = P64R_AN.side_counts(σ, lat); [c <= length(s) ? s[c] : 0 for c in 1:n])
"""Interior hexagons, interior bubbles, and the non-hexagonal interior bubbles mid / away."""
function p64r_frame(σ, lat, n)
    c = p64r_cells(σ, n)
    s = p64r_sides(σ, lat, n)
    ymid = (size(σ, 2) + 1) / 2
    hex = tot = mid = away = 0
    for b in 1:n
        (c.cnt[b] > 0 && !c.edge[b]) || continue
        tot += 1
        if s[b] == 6
            hex += 1
        elseif abs(c.cy[b] - ymid) <= P64R_MID
            mid += 1
        else
            away += 1
        end
    end
    return (; hex, tot, mid, away)
end
p64r_hexfrac(σ, n) = (f = p64r_frame(σ, p64r_lat(size(σ)), n); f.hex / f.tot)
p64r_mu2n(σ) = P64R_AN.topology_moments(σ, p64r_lat(size(σ))).mu2_n
"""V19: E_a / (E_a + J φ)."""
function p64r_area_frac(σ, vol, A; J = P64R_J)
    Ea = P64R_Γ * sum((vol[c] - A[c])^2 for c in eachindex(A) if vol[c] > 0; init = 0.0)
    return Ea / (Ea + J * P64R_AN.stored_energy(σ, p64r_lat(size(σ))))
end
p64r_vol(u, n) = Float64.(u.cell.volume[1:n])
const P64R_N4 = [(a, b) for a in -2:2 for b in -2:2 if 0 < a^2 + b^2 <= 5]   # NeighborOrder(4): 20 offsets
"""ū: the mean over boundary sites (≥ 1 unlike site among the 20 offsets, on the lattice:
periodic x, closed y) of the unlike share, unlike / 20. τ = 1/ū (A-5)."""
function p64r_ubar(σ)
    X, Y = size(σ)
    s = 0.0
    nb = 0
    for x in 1:X, y in 1:Y
        u = 0
        for (a, b) in P64R_N4
            q = y + b
            1 <= q <= Y || continue
            u += σ[x, y] != σ[mod1(x + a, X), q]
        end
        u > 0 && (s += u / 20; nb += 1)
    end
    return s / nb
end

# ---------------------------------------------------------------------------------------------
# Foams
# ---------------------------------------------------------------------------------------------

function p64r_ordered(seed; L = P64R_L)
    σ0 = p64r_brick(L)
    n = Int(maximum(σ0))
    A = fill(Float64(P64R_BRICK^2), n)
    u = solve(p64r_problem((; σ = σ0, A), P64R_NA; T = P64R_TA, seed), P64R_ALG).u[end]
    u = solve(p64r_problem((; σ = Array(u.σ), A), P64R_NR; seed), P64R_ALG).u[end]
    return (; σ = Array(u.σ), A, stop = 0)
end
function p64r_disordered(target, seed; L = P64R_L)
    o = p64r_ordered(seed; L)
    n = length(o.A)
    integ = init(p64r_problem(o, P64R_CMAX; T = P64R_TC, Γ = 0.0, seed), P64R_ALG)
    m = 0
    while m < P64R_CMAX
        for _ in 1:P64R_CHECK
            step!(integ)
        end
        m += P64R_CHECK
        p64r_mu2n(Array(integ.u.σ)) >= target && break
    end
    σc = Array(integ.u.σ)
    A = p64r_vol(integ.u, n)[1:Int(maximum(σc))]                # ids above the largest survivor are dropped
    u = solve(p64r_problem((; σ = σc, A), P64R_NR; seed), P64R_ALG).u[end]
    return (; σ = Array(u.σ), A, stop = m)
end
"""Foam k of kind f with its PREP row (tries until accepted, at most P64R_TRIES)."""
function p64r_foam(f::Symbol, k; seedf = t -> p64r_prep_seed(f, k, t))
    spec = P64R_FOAMS[f]
    local st, mu, t
    for outer t in 0:(P64R_TRIES - 1)
        st = f === :ordered ? p64r_ordered(seedf(t); spec.L) : p64r_disordered(spec.target, seedf(t); spec.L)
        mu = p64r_mu2n(st.σ)
        (f === :ordered || abs(mu - spec.target) <= P64R_PREP_TOL) && break
    end
    m = P64R_AN.topology_moments(st.σ, p64r_lat(size(st.σ)))
    n = length(st.A)
    row = Dict{String, Any}("foam" => string(f), "k" => k, "seed" => seedf(t), "try" => t, "ly" => size(st.σ, 2),
        "target" => spec.target, "mu2n" => m.mu2_n, "mu2a" => m.mu2_a, "nbub" => count(>(0), p64r_cells(st.σ, n).cnt),
        "hex" => p64r_hexfrac(st.σ, n), "area_frac" => p64r_area_frac(st.σ, Float64.(p64r_cells(st.σ, n).cnt), st.A),
        "stop" => st.stop, "ok" => f === :ordered || abs(m.mu2_n - spec.target) <= P64R_PREP_TOL,
        "ubar" => p64r_ubar(st.σ))
    return (; σ = st.σ, A = st.A), row
end

# ---------------------------------------------------------------------------------------------
# Rules (pure functions of series; checked on synthetic input below)
# ---------------------------------------------------------------------------------------------

"""Zigzag extrema with threshold h: confirmed peaks and their troughs (index vectors)."""
function p64r_zigzag(x, h)
    peaks, troughs = Int[], Int[]
    isempty(x) && return peaks, troughs
    up = true
    imax = imin = 1
    for i in 2:length(x)
        if up
            x[i] > x[imax] && (imax = i)
            if x[imax] - x[i] >= h
                push!(peaks, imax)
                up = false
                imin = i
            end
        else
            x[i] < x[imin] && (imin = i)
            if x[i] - x[imin] >= h
                push!(troughs, imin)
                up = true
                imax = i
            end
        end
    end
    up || push!(troughs, imin)
    return peaks, troughs
end
p64r_drops(x, h) = ((p, t) = p64r_zigzag(x, h); [x[p[i]] - x[t[i]] for i in eachindex(p)])
"""Bursts of non-zero bins (single empty bins bridged) and the share of empty bins."""
function p64r_bursts(c)
    n = length(c)
    bursts = 0
    i = 1
    while i <= n
        if c[i] > 0
            bursts += 1
            j = i
            while true
                if j + 1 <= n && c[j + 1] > 0
                    j += 1
                elseif j + 2 <= n && c[j + 1] == 0 && c[j + 2] > 0
                    j += 2
                else
                    break
                end
            end
            i = j + 1
        else
            i += 1
        end
    end
    return (; bursts, quiet = n == 0 ? 0.0 : count(==(0), c) / n)
end
"""The first crossing of v ≥ thr along r, linearly interpolated; nothing if v never reaches
thr or already does at r[1] (the boundary is not resolved by the grid)."""
function p64r_crossing(r, v, thr)
    i = findfirst(>=(thr), v)
    (i === nothing || i == 1) && return nothing
    return r[i - 1] + (thr - v[i - 1]) / (v[i] - v[i - 1]) * (r[i] - r[i - 1])
end
p64r_ranks(x) = (p = sortperm(x); r = similar(x, Float64); for (j, i) in enumerate(p)
    r[i] = j
end; [mean(r[findall(==(x[i]), x)]) for i in eachindex(x)])
function p64r_spearman(x, y)
    a, b = p64r_ranks(x), p64r_ranks(y)
    return sum((a .- mean(a)) .* (b .- mean(b))) / sqrt(sum(abs2, a .- mean(a)) * sum(abs2, b .- mean(b)))
end
p64r_ols(x, y) = (xm = mean(x); ym = mean(y); s = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm); (a = ym - s * xm, s = s))
"""Log-binned spectrum (20 bins per decade)."""
function p64r_bin(f, S)
    E = P64R_BIN_EDGES
    fb, Sb = Float64[], Float64[]
    for i in 1:(length(E) - 1)
        idx = findall(x -> E[i] <= x < E[i + 1], f)
        isempty(idx) && continue
        push!(fb, 10^mean(log10.(f[idx])))
        push!(Sb, mean(S[idx]))
    end
    return fb, Sb
end
"""α over [lo, hi] on positive bins; NaN if fewer than 2."""
function p64r_alpha(fb, Sb, lo, hi)
    k = findall(i -> lo <= fb[i] <= hi && Sb[i] > 0, eachindex(fb))
    length(k) < 2 && return NaN
    return P64R_AN.spectral_exponent(fb[k], Sb[k]; range = (lo, hi))
end
"""Largest α over the 1-decade windows [f_b, 10 f_b], lo ≤ f_b ≤ hi (and 10 f_b ≤ 0.5); NaN
if any window has no α (an empty spectrum cannot pass a "no power law" row)."""
function p64r_window_alpha(fb, Sb, lo, hi)
    a = [p64r_alpha(fb, Sb, f, 10f) for f in fb if lo <= f <= hi && 10f <= 0.5]
    return isempty(a) || any(isnan, a) ? NaN : maximum(a)
end
"""V7 (iii) peak on a raw periodogram."""
function p64r_peak(f, S)
    sm = [mean(S[max(1, i - 2):min(end, i + 2)]) for i in eachindex(S)]
    k = findall(x -> 2e-4 <= x <= 5e-3, f)
    i = k[argmax(sm[k])]
    return (; f = f[i], prom = sm[i] / median(S[k]))
end
p64r_bincentre_strain(b) = sinpi(2(b - 0.5) / P64R_NBIN)

# ---------------------------------------------------------------------------------------------
# Runs (gate open only). Durations are in paper MCS; our MCS m is paper time m/τ (A-5).
# ---------------------------------------------------------------------------------------------

"""Paper bin of width w (paper MCS) that our MCS m (1-based) falls in, at time scale τ."""
p64r_pbin(m, w, τ) = floor(Int, (m - 1) / (w * τ)) + 1
"""Our MCS that cover `tp` paper MCS."""
p64r_ours(tp, τ) = ceil(Int, tp * τ)

"""Periodic boundary shear, 10 periods of 4000 paper MCS (V3–V6, the calibration and the scan)."""
function p64r_loop(st, J, γ0m, T, seed, τ)
    lat = p64r_lat(size(st.σ))
    P = p64r_ours(P64R_PERIOD, τ)                                # one period in our MCS
    integ = init(p64r_problem(st, P64R_CYCLES * P; shear = true, J, T, γ0 = γ0m, periodic = true, ω = 2π / P, seed),
        P64R_ALG)
    φ0 = P64R_AN.stored_energy(st.σ, lat)
    g = P64R_AN.cell_graph(st.σ, lat)
    t1 = zeros(P64R_CYCLES)
    acc = zeros(P64R_CYCLES, P64R_NBIN)
    cnt = zeros(Int, P64R_CYCLES, P64R_NBIN)
    all = Float64[]
    for m in 1:(P64R_CYCLES * P)
        step!(integ)
        σ = integ.u.σ
        g2 = P64R_AN.cell_graph(σ, lat)
        c = (m - 1) ÷ P + 1
        t1[c] += P64R_AN.t1_events(g, g2; unit = :t1)
        g = g2
        if m % 10 == 0
            v = P64R_AN.stored_energy(σ, lat) / φ0
            b = floor(Int, P64R_NBIN * mod(m, P) / P) + 1
            acc[c, b] += v
            cnt[c, b] += 1
            push!(all, v)
        end
    end
    per = acc ./ max.(cnt, 1)                                   # per-period bin means
    return Dict{String, Any}("J" => J, "gamma0" => γ0m, "T" => T, "seed" => seed, "t1_cycles" => t1,
        "phi_bins" => vec(mean(per; dims = 1)), "phi_noise" => mean(std(per[:, b]) for b in 1:P64R_NBIN),
        "phi_mean" => mean(all))
end

"""Steady boundary shear for `tp` paper MCS (V2, V9): 50-MCS bins of T1s, φ̂ and frames."""
function p64r_steady(st, γ0m, tp, seed, τ)
    n = length(st.A)
    lat = p64r_lat(size(st.σ))
    T = p64r_ours(tp, τ)
    nb = tp ÷ 50
    integ = init(p64r_problem(st, T; shear = true, γ0 = γ0m, seed), P64R_ALG)
    φ0 = P64R_AN.stored_energy(st.σ, lat)
    g = P64R_AN.cell_graph(st.σ, lat)
    N = zeros(T)
    t1 = zeros(nb)
    phi = fill(NaN, nb)
    hexp = hext = 0
    changed = Set{Int}()
    cmax = 0.0
    for m in 1:T
        step!(integ)
        σ = integ.u.σ
        g2 = P64R_AN.cell_graph(σ, lat)
        N[m] = P64R_AN.t1_events(g, g2; unit = :t1)
        cc = P64R_AN.contact_changes(g, g2)
        for (a, b) in Iterators.flatten((cc.lost, cc.gained))
            push!(changed, a, b)
        end
        g = g2
        i = min(p64r_pbin(m, 50, τ), nb)
        t1[i] += N[m]
        if m == T || p64r_pbin(m + 1, 50, τ) > i                     # the last MCS of a 50-MCS bin
            phi[i] = P64R_AN.stored_energy(σ, lat) / φ0
            fr = p64r_frame(σ, lat, n)
            hexp += fr.hex
            hext += fr.tot
        end
        if m == T || p64r_pbin(m + 1, 100, τ) > p64r_pbin(m, 100, τ)     # the last MCS of a 100-MCS window
            cmax = max(cmax, length(changed) / count(>(0), p64r_cells(σ, n).cnt))
            empty!(changed)
        end
    end
    tf = P64R_AN.yield_strain(collect(1:T) ./ τ, N; threshold = 1, window = round(Int, 100τ))
    return Dict{String, Any}("gamma0" => γ0m, "seed" => seed, "t1_50" => t1, "phi_50" => phi, "hex_pairs" => hexp,
        "hex_total" => hext, "t_first" => tf === nothing ? -1 : round(Int, tf), "changed_max" => cmax)
end

"""Steady bulk shear at paper β (model κβ) for `tp` paper MCS: run row, 100-MCS windows and
(spectral runs) the binned spectra in cycles per paper MCS."""
function p64r_bulk(st, βp, κ, tp, seed, τ; spectra = false)
    n = length(st.A)
    lat = p64r_lat(size(st.σ))
    T = p64r_ours(tp, τ)
    nw = tp ÷ 100
    integ = init(p64r_problem(st, T; shear = true, β = κ * βp, bulk = true, seed), P64R_ALG)
    φ0 = P64R_AN.stored_energy(st.σ, lat)
    g = P64R_AN.cell_graph(st.σ, lat)
    nb0 = count(>(0), p64r_cells(st.σ, n).cnt)
    N = zeros(T)
    Φ = spectra ? zeros(T) : Float64[]
    W = Dict{String, Any}[]
    changed = Set{Int}()
    tw = 0.0
    for m in 1:T
        step!(integ)
        σ = integ.u.σ
        g2 = P64R_AN.cell_graph(σ, lat)
        N[m] = P64R_AN.t1_events(g, g2; unit = :t1)
        cc = P64R_AN.contact_changes(g, g2)
        for (a, b) in Iterators.flatten((cc.lost, cc.gained))
            push!(changed, a, b)
        end
        g = g2
        tw += N[m]
        spectra && (Φ[m] = P64R_AN.stored_energy(σ, lat) / φ0)
        w = p64r_pbin(m, 100, τ)
        if w <= nw && (m == T || p64r_pbin(m + 1, 100, τ) > w)
            fr = p64r_frame(σ, lat, n)
            vol = p64r_vol(integ.u, n)
            push!(W, Dict{String, Any}("w" => w, "t1" => tw,
                "phi" => spectra ? Φ[m] : P64R_AN.stored_energy(σ, lat) / φ0, "mu2n" => p64r_mu2n(σ),
                "nonhex_mid" => fr.mid, "nonhex_away" => fr.away,
                "changed_frac" => length(changed) / count(>(0), vol), "area_frac" => p64r_area_frac(σ, vol, st.A)))
            empty!(changed)
            tw = 0.0
        end
    end
    tf = P64R_AN.yield_strain(collect(1:T) ./ τ, N; threshold = 1, window = round(Int, 100τ))
    run = Dict{String, Any}("beta" => βp, "beta_model" => κ * βp, "seed" => seed, "mcs" => tp, "nbub" => nb0,
        "mu2n0" => p64r_mu2n(st.σ), "t1_total" => sum(N), "t_first" => tf === nothing ? -1 : round(Int, tf),
        "peak_f" => NaN, "peak_prom" => NaN)
    spec = Dict{String, Any}[]
    if spectra
        for (name, x) in (("t1", N), ("phi", Φ))
            P = P64R_AN.power_spectrum(x; dt = 1 / τ)                  # f in cycles per paper MCS
            name == "t1" && ((pk = p64r_peak(P.f, P.S)); run["peak_f"] = pk.f; run["peak_prom"] = pk.prom)
            fb, Sb = p64r_bin(P.f, P.S)
            append!(spec, [Dict{String, Any}("series" => name, "f" => fb[i], "S" => Sb[i]) for i in eachindex(fb)])
        end
    end
    return run, W, spec
end

# ---------------------------------------------------------------------------------------------
# Record schema, reader, writer
# ---------------------------------------------------------------------------------------------

const P64R_SCHEMA = Dict(
    "foams" => ["foam" => String, "k" => Int, "seed" => Int, "try" => Int, "ly" => Int, "target" => Float64,
        "mu2n" => Float64, "mu2a" => Float64, "nbub" => Int, "hex" => Float64, "area_frac" => Float64, "stop" => Int,
        "ok" => Bool, "ubar" => Float64],
    "loops" => ["set" => String, "J" => Float64, "r" => Float64, "gp" => Float64, "gamma0" => Float64, "T" => Float64,
        "k" => Int, "seed" => Int, "t1_cycles" => Vector{Float64}, "phi_bins" => Vector{Float64},
        "phi_noise" => Float64, "phi_mean" => Float64],
    "steady" => ["set" => String, "foam" => String, "k" => Int, "seed" => Int, "gamma0" => Float64,
        "t1_50" => Vector{Float64}, "phi_50" => Vector{Float64}, "hex_pairs" => Int, "hex_total" => Int,
        "t_first" => Int, "changed_max" => Float64],
    "bulk" => ["set" => String, "foam" => String, "beta" => Float64, "beta_model" => Float64, "k" => Int,
        "seed" => Int, "mcs" => Int, "nbub" => Int, "mu2n0" => Float64, "t1_total" => Float64, "t_first" => Int,
        "peak_f" => Float64, "peak_prom" => Float64],
    "windows" => ["set" => String, "foam" => String, "beta" => Float64, "k" => Int, "w" => Int, "t1" => Float64,
        "phi" => Float64, "mu2n" => Float64, "nonhex_mid" => Int, "nonhex_away" => Int, "changed_frac" => Float64,
        "area_frac" => Float64],
    "spectra" => ["foam" => String, "beta" => Float64, "k" => Int, "series" => String, "f" => Float64, "S" => Float64],
    "calibration" => ["kappa" => Float64, "r_star" => Float64, "tau" => Float64])

p64r_fmt(x::AbstractVector) = join(map(p64r_fmt, x), ',')
p64r_fmt(x::AbstractFloat) = isnan(x) ? "NaN" : string(Float64(x))
p64r_fmt(x) = string(x)
p64r_parse(::Type{String}, s) = String(s)
p64r_parse(::Type{Bool}, s) = parse(Bool, s)
p64r_parse(::Type{T}, s) where {T <: Real} = parse(T, s)
p64r_parse(::Type{Vector{Float64}}, s) = isempty(s) ? Float64[] : parse.(Float64, split(s, ','))
function p64r_write(dir, R)
    mkpath(dir)
    for (name, cols) in P64R_SCHEMA
        open(joinpath(dir, "$name.tsv"), "w") do io
            println(io, join(first.(cols), '\t'))
            for r in R[name]
                println(io, join((p64r_fmt(r[c]) for c in first.(cols)), '\t'))
            end
        end
    end
end
function p64r_read(dir)
    R = Dict{String, Vector{Dict{String, Any}}}()
    for (name, cols) in P64R_SCHEMA
        l = split.(readlines(joinpath(dir, "$name.tsv")), '\t'; keepempty = true)
        @assert l[1] == first.(cols) "04 record: $name.tsv header $(l[1]) is not the schema's"
        R[name] = [Dict{String, Any}(c => p64r_parse(T, v) for ((c, T), v) in zip(cols, r)) for r in l[2:end]]
    end
    return R
end
p64r_sel(tab; kw...) = filter(r -> all(r[string(k)] == v for (k, v) in kw), tab)

# ---------------------------------------------------------------------------------------------
# Verdicts from the tables (shared by the record tier and FULL)
# ---------------------------------------------------------------------------------------------

"""τ = 1/ū over ordered foams 1:5 (the foams the shear runs start from)."""
p64r_tau(R) = 1 / mean(r["ubar"] for r in R["foams"] if r["foam"] == "ordered" && r["k"] <= P64R_REPS)
"""κ and r* from the calibration stage (J = 3, model r grid)."""
function p64r_kappa(R)
    lp = p64r_sel(R["loops"]; set = "cal", J = 3.0)
    rs = sort(unique(r["r"] for r in lp))
    m = [median(mean(x["t1_cycles"]) for x in lp if x["r"] == r) for r in rs]
    rstar = p64r_crossing(rs, m, 0.5)
    return rstar === nothing ? (kappa = NaN, r_star = NaN) : (kappa = 3rstar / 5.8, r_star = rstar)
end
p64r_t1c(rows) = median(mean(r["t1_cycles"]) for r in rows)
p64r_curve(rows) = mean(r["phi_bins"] for r in rows)
p64r_height(rows) = (c = p64r_curve(rows); maximum(c) - minimum(c))
p64r_in(x, lo, hi) = lo <= x <= hi
p64r_med(x) = isempty(x) ? NaN : median(x)
p64r_ens_spec(R, foam, β, series) = (rows = p64r_sel(R["spectra"]; foam, beta = β, series);
    fs = sort(unique(r["f"] for r in rows);); (fs, [mean(r["S"] for r in rows if r["f"] == f) for f in fs]))
"""V7 (i) / V8: the mid share of non-hexagonal interior bubble-frames after t_first, pooled."""
function p64r_mid_share(R, foam, β)
    m = a = 0
    for b in p64r_sel(R["bulk"]; set = "spec", foam, beta = β)
        b["t_first"] >= 0 || continue
        for w in p64r_sel(R["windows"]; set = "spec", foam, beta = β, k = b["k"])
            100w["w"] > b["t_first"] || continue
            m += w["nonhex_mid"]
            a += w["nonhex_away"]
        end
    end
    return m + a == 0 ? NaN : m / (m + a)
end
p64r_wseries(R, set, foam, β, k, col) = [w[col] for w in sort(p64r_sel(R["windows"]; set, foam, beta = β, k); by = w -> w["w"])]

function p64r_verdicts(R)
    V = NamedTuple[]
    add!(id, kind, value, band, ok) = push!(V, (; id, kind, value, band, ok = ok === true))
    κ = p64r_kappa(R)
    add!("kappa", :info, κ.kappa, "γ_model / γ_paper", true)
    add!("r_star", :info, κ.r_star, "J = 3 first-T1 r (model)", true)
    add!("tau", :info, p64r_tau(R), "our MCS per paper MCS (1/ū)", true)
    # V1, V1b, V19 (relaxed), PREP
    ord = p64r_sel(R["foams"]; foam = "ordered")
    add!("V1", :row, minimum(r["hex"] for r in ord), "≥ 0.95 every foam", length(ord) == 10 && all(r -> r["hex"] >= 0.95, ord))
    add!("V1b", :row, extrema(r["mu2n"] for r in ord), "[0.3, 0.6] every foam", all(r -> p64r_in(r["mu2n"], 0.3, 0.6), ord))
    add!("V19a", :row, maximum(r["area_frac"] for r in ord), "< 5e-3", all(r -> r["area_frac"] < 5e-3, ord))
    dis = filter(r -> r["foam"] != "ordered", R["foams"])
    add!("PREP", :row, count(r -> r["ok"], dis), "all $(length(dis)) accepted", length(dis) == 30 && all(r -> r["ok"], dis))
    μa(f) = mean(r["mu2a"] for r in p64r_sel(R["foams"]; foam = f))
    add!("PREPa", :row, (μa("d165") + μa("d172"), μa("d095") + μa("d107")) ./ 2, "high > low",
        μa("d165") + μa("d172") > μa("d095") + μa("d107"))
    d081 = p64r_sel(R["foams"]; foam = "d081")
    add!("C-V1", :control, maximum(r["hex"] for r in d081), "< 0.95 (d081)", all(r -> r["hex"] < 0.95, d081))
    # V3, V4, V6
    v3(gp) = p64r_sel(R["loops"]; set = "v3", gp)
    add!("V3a", :row, (p64r_height(v3(1.0)), p64r_t1c(v3(1.0))), "height < 0.002, T1 < 0.5",
        p64r_height(v3(1.0)) < 0.002 && p64r_t1c(v3(1.0)) < 0.5)
    add!("V3b", :row, (p64r_height(v3(3.5)), p64r_t1c(v3(3.5))), "height ∈ [0.01, 0.03], T1 < 0.5",
        p64r_in(p64r_height(v3(3.5)), 0.01, 0.03) && p64r_t1c(v3(3.5)) < 0.5)
    c7 = p64r_curve(v3(7.0))
    sx = abs(p64r_bincentre_strain(argmax(c7)))
    add!("V3c", :row, (p64r_t1c(v3(7.0)), sx), "T1 ≥ 0.5, |strain| at max > 0.8γ0", p64r_t1c(v3(7.0)) >= 0.5 && sx > 0.8)
    add!("V3t", :info, 5.8, "transition = calibration (κ)", true)
    m4 = Dict(J => p64r_t1c(J == 3.0 ? v3(7.0) : p64r_sel(R["loops"]; set = "v4", J)) for J in (1.0, 3.0, 5.0, 10.0))
    add!("V4", :row, m4, "J10, J5 < 0.5; J3 ∈ [0.5, 2.5); J1 ≥ 1.5; non-increasing",
        m4[10.0] < 0.5 && m4[5.0] < 0.5 && 0.5 <= m4[3.0] < 2.5 && m4[1.0] >= 1.5 && m4[1.0] >= m4[3.0] >= m4[5.0] >= m4[10.0])
    v6 = [p64r_sel(R["loops"]; set = "v6", T) for T in P64R_V6_T]
    mφ = [median(r["phi_mean"] for r in rows) for rows in v6]
    hn = [p64r_height(rows) / mean(r["phi_noise"] for r in rows) for rows in v6]
    add!("V6a", :row, mφ, "strictly increasing in T", issorted(mφ) && allunique(mφ))
    add!("V6b", :row, (hn[1], hn[4]), "height/noise > 3 at T = 0, < 1 at T = 15", hn[1] > 3 && hn[4] < 1)
    add!("V6c", :info, p64r_ols([0.0, 5, 10, 15], mφ).s, "≈ 0.014 ± 50 %", true)
    # V5
    bnd = Dict{Tuple{Symbol, Float64}, Any}()
    for J in P64R_SCAN_J
        lp = p64r_sel(R["loops"]; set = "scan", J)
        rs = sort(unique(r["r"] for r in lp))
        h = [p64r_height(filter(x -> x["r"] == r, lp)) for r in rs]
        t = [p64r_t1c(filter(x -> x["r"] == r, lp)) for r in rs]
        bnd[(:e, J)] = p64r_crossing(rs, h, 0.002)
        bnd[(:b1, J)] = p64r_crossing(rs, t, 0.5)
        bnd[(:b2, J)] = p64r_crossing(rs, t, 1.5)
        bnd[(:b3, J)] = p64r_crossing(rs, t, 2.5)
    end
    for (b, id, lo, hi) in ((:e, "V5a", 0.7, 1.4), (:b1, "V5b", 1.4, 2.5))
        rb = [bnd[(b, J)] for J in P64R_SCAN_J]
        if any(isnothing, rb) || isnan(κ.kappa)
            add!(id, :row, rb, "s ∈ [$lo, $hi], |a| ≤ 1.6", false)
        else
            fit = p64r_ols(P64R_SCAN_J, P64R_SCAN_J .* rb)                # paper γ0 = J·r_b (r in paper units)
            add!(id, :row, (fit.s, fit.a), "s ∈ [$lo, $hi], |a| ≤ 1.6", p64r_in(fit.s, lo, hi) && abs(fit.a) <= 1.6)
        end
    end
    ordok = all(P64R_SCAN_J) do J
        e, b1, b2, b3 = (bnd[(b, J)] for b in (:e, :b1, :b2, :b3))
        (e !== nothing && b1 !== nothing && e < b1) && (b2 === nothing || b1 <= b2) && (b3 === nothing || (b2 !== nothing && b2 <= b3))
    end
    add!("V5c", :row, Dict(string(k) => v for (k, v) in bnd), "r_e < r_1 ≤ r_2 ≤ r_3", ordok)
    # V2, V9, V20 inputs
    v2 = p64r_sel(R["steady"]; set = "v2")
    add!("V2i", :row, sum(r["hex_pairs"] for r in v2) / sum(r["hex_total"] for r in v2), "> 0.95",
        sum(r["hex_pairs"] for r in v2) / sum(r["hex_total"] for r in v2) > 0.95)
    v2ii = map(v2) do r
        p, _ = p64r_zigzag(r["phi_50"], 0.002)
        d = p64r_drops(r["phi_50"], 0.002)
        sp = diff(p)
        length(d) >= 3 && p64r_in(median(d), 0.005, 0.02) && length(sp) >= 2 && std(sp) / mean(sp) <= 0.3
    end
    add!("V2ii", :row, count(v2ii), "≥ 4/5 replicates", count(v2ii) >= 4)
    v2iii = [(b = p64r_bursts(r["t1_50"]); b.bursts >= 3 && b.quiet >= 0.3) for r in v2]
    add!("V2iii", :row, count(v2iii), "≥ 4/5 replicates", count(v2iii) >= 4)
    early(set) = count(r -> 0 <= r["t_first"] < 100, p64r_sel(R["steady"]; set))
    add!("V9", :row, early("v9"), "t_first < 100 in ≥ 4/5", early("v9") >= 4)
    add!("C-V9", :control, early("v9c"), "ordered: t_first < 100 in ≤ 1/5", early("v9c") <= 1)
    # V7, V8, V17, V19b, V20
    dropb = median(p64r_med(p64r_drops(p64r_wseries(R, "spec", "ordered", 0.01, k, "phi"), 0.001)) for k in 1:P64R_REPS)
    drops2 = median(p64r_med(p64r_drops(r["phi_50"][2:2:end], 0.001)) for r in v2)
    l01, l05 = p64r_mid_share(R, "ordered", 0.01), p64r_mid_share(R, "ordered", 0.05)
    add!("V7i", :row, l01, "≥ 0.9", l01 >= 0.9)
    add!("V7ii", :row, dropb / drops2, "≤ 0.6", dropb / drops2 <= 0.6)
    pk = p64r_sel(R["bulk"]; set = "spec", foam = "ordered", beta = 0.01)
    npk = count(r -> 5e-4 < r["peak_f"] < 1.5e-3 && r["peak_prom"] >= 3, pk)
    add!("V7iii", :row, [r["peak_f"] for r in pk], "f* ∈ (5e-4, 1.5e-3), prominence ≥ 3 in ≥ 4/5", npk >= 4)
    add!("V8", :row, l05, "< 0.5", l05 < 0.5)
    add!("V20", :row, dropb / drops2, "∈ [0.2, 0.6]", p64r_in(dropb / drops2, 0.2, 0.6))
    af = mean(w["area_frac"] for w in p64r_sel(R["windows"]; set = "spec", foam = "ordered", beta = 0.01))
    add!("V19b", :row, af, "< 5e-3", af < 5e-3)
    exc = tot = 0
    for k in 1:P64R_REPS
        μ = p64r_wseries(R, "spec", "ordered", 0.01, k, "mu2n")
        φ = p64r_wseries(R, "spec", "ordered", 0.01, k, "phi")
        p, t = p64r_zigzag(φ, 0.001)
        falls = [p[i]:t[i] for i in eachindex(p)]
        b = median(μ)
        i = 1
        while i <= length(μ)
            if μ[i] > b + 0.01
                j = i
                while j + 1 <= length(μ) && μ[j + 1] > b + 0.01
                    j += 1
                end
                tot += 1
                exc += any(r -> !isempty(intersect(i:j, r)), falls)
                i = j + 1
            else
                i += 1
            end
        end
    end
    add!("V17", :row, (exc, tot), "≥ 80 % of ≥ 3 excursions", tot >= 3 && exc / tot >= 0.8)
    # spectra: V10–V13
    α(foam, β, s; lo = 1e-4, hi = 1e-2) = (S = p64r_ens_spec(R, foam, β, s); p64r_alpha(S[1], S[2], lo, hi))
    wα(foam, β, s, lo, hi) = (S = p64r_ens_spec(R, foam, β, s); p64r_window_alpha(S[1], S[2], lo, hi))
    a05, a02 = α("ordered", 0.05, "t1"), α("ordered", 0.02, "t1")
    add!("V10a", :row, a05, "∈ [0.7, 1.3]", p64r_in(a05, 0.7, 1.3))
    add!("V10b", :row, a02, "|α| < 0.3", abs(a02) < 0.3)
    a81 = [α("d081", β, "t1") for β in P64R_BETAS]
    ρ = any(isnan, a81) ? NaN : p64r_spearman(P64R_BETAS, a81)
    add!("V11a", :row, ρ, "Spearman ≥ 0.8", ρ >= 0.8)
    add!("V11b", :row, a81[end], "∈ [0.7, 1.2]", p64r_in(a81[end], 0.7, 1.2))
    add!("V11c", :row, a81[1], "< 0.4", a81[1] < 0.4)
    w12 = [wα("d165", β, "t1", 1e-4, 1e-2) for β in (0.001, 0.01, 0.05)]
    add!("V12", :row, w12, "every window α ≤ 0.5", all(<=(0.5), w12))
    c12 = wα("ordered", 0.05, "t1", 1e-4, 1e-2)
    add!("C-V12", :control, c12, "ordered β = 0.05: > 0.5", c12 > 0.5)
    φok = [(foam, β) => (α(foam, β, "phi"), wα(foam, β, "phi", 1e-5, 0.05)) for foam in ("ordered", "d081", "d165")
           for β in P64R_BETAS]
    add!("V13a", :row, Dict(φok), "α_φ ∈ [0.5, 1.2], every window < 1.5",
        all(((_, (a, w)),) -> p64r_in(a, 0.5, 1.2) && w < 1.5, φok))
    h1, h2 = α("d165", 0.005, "phi"; hi = 1e-3), α("d165", 0.005, "phi"; lo = 1e-3)
    add!("V13b", :row, (h1, h2), "both ∈ [0.5, 1.2]", p64r_in(h1, 0.5, 1.2) && p64r_in(h2, 0.5, 1.2))
    # V14
    nbar(foam, β) = mean(P64R_AN.mean_t1([r["t1_total"]]; bubbles = r["nbub"], strain = β * r["mcs"])
                         for r in p64r_sel(R["bulk"]; set = "v14", foam, beta = β))
    N14 = Dict((f, β) => nbar(f, β) for f in ("d165", "d172", "d107", "d095") for β in P64R_BETAS14)
    r1 = [N14[(f, 1e-4)] / N14[(f, 1e-3)] for f in ("d165", "d172", "d107", "d095")]
    r2 = [N14[(f, 1e-3)] / N14[(f, 5e-2)] for f in ("d165", "d172", "d107", "d095")]
    sep = [(N14[("d165", β)] + N14[("d172", β)]) / (N14[("d107", β)] + N14[("d095", β)]) for β in (5e-3, 1e-2, 5e-2)]
    add!("V14a", :row, r1, "∈ [4, 25] each foam", all(x -> p64r_in(x, 4, 25), r1))
    add!("V14b", :row, r2, "≥ 10 each foam (finite)", all(x -> isfinite(x) && x >= 10, r2))
    add!("V14c", :row, sep, "≥ 5 at β ≥ 5e-3 (finite)", all(x -> isfinite(x) && x >= 5, sep))
    # V15
    εy(foam, β) = (rs = p64r_sel(R["bulk"]; set = "spec", foam, beta = β);
        median(r["t_first"] < 0 ? Inf : β * r["t_first"] for r in rs))
    eo = [εy("ordered", β) for β in P64R_BETAS]
    plateau = median(eo[1:3])
    add!("V15a", :row, (maximum(eo[1:3]) - minimum(eo[1:3])) / mean(eo[1:3]), "≤ 0.10",
        (maximum(eo[1:3]) - minimum(eo[1:3])) / mean(eo[1:3]) <= 0.10)
    add!("V15b", :row, eo[5] / eo[3], "∈ [0.25, 0.6]", p64r_in(eo[5] / eo[3], 0.25, 0.6))
    allo = p64r_sel(R["bulk"]; set = "spec", foam = "ordered")
    add!("V15c", :row, minimum(r["t_first"] for r in allo), "every ordered run yields, t_first ≥ 100",
        all(r -> r["t_first"] >= 100, allo))
    ed = [εy(f, β) for f in ("d081", "d165") for β in (0.01, 0.02, 0.05)]
    add!("V15d", :row, ed ./ plateau, "≤ 0.045 (all yield)", isfinite(plateau) && all(x -> isfinite(x) && x <= 0.045 * plateau, ed))
    add!("V15e", :info, P64R_C_YIELD .* eo, "ε_y with c = 0.023 (paper 1.13, 1.10, 1.11, 0.80, 0.43)", true)
    # V16
    rise(set, foam, β) = map(p64r_sel(R["bulk"]; set, foam, beta = β)) do r
        ws = filter(w -> 2000 <= 100w["w"] <= 10_000, p64r_sel(R["windows"]; set, foam, beta = β, k = r["k"]))
        mean(w["mu2n"] for w in ws) - r["mu2n0"]
    end
    v16 = Dict(f => rise("v16", f, 0.01) for f in ("d081", "d165", "d172", "d202"))
    add!("V16", :row, v16, "rise ≥ 0.1 in ≥ 4/5, each foam", all(x -> count(>=(0.1), x) >= 4, values(v16)))
    c16 = rise("v16c", "d165", 0.0)
    add!("C-V16", :control, c16, "β = 0: rise < 0.1 in ≥ 4/5", count(<(0.1), c16) >= 4)
    # V18
    m18 = max(maximum(w["changed_frac"] for w in R["windows"]), maximum(r["changed_max"] for r in R["steady"]))
    add!("V18", :row, m18, "< 0.5", m18 < 0.5)
    return V
end

# ---------------------------------------------------------------------------------------------
# always: the rules on synthetic series and hand-built states
# ---------------------------------------------------------------------------------------------

"""Brute-force φ: unordered NeighborOrder(4) pairs, periodic x, closed y (no production code)."""
function p64r_phi_oracle(σ)
    X, Y = size(σ)
    offs = [(a, b) for a in -2:2 for b in -2:2 if 0 < a^2 + b^2 <= 5 && (a > 0 || (a == 0 && b > 0))]
    φ = 0
    for x in 1:X, y in 1:Y, (a, b) in offs
        q = y + b
        1 <= q <= Y || continue
        φ += σ[x, y] != σ[mod1(x + a, X), q]
    end
    return φ
end
"""Brute-force n: distinct other ids among VonNeumann(1) neighbours, periodic x, closed y."""
function p64r_sides_oracle(σ, n)
    X, Y = size(σ)
    S = [Set{Int}() for _ in 1:n]
    for x in 1:X, y in 1:Y, (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1))
        q = y + b
        1 <= q <= Y || continue
        c, d = σ[x, y], σ[mod1(x + a, X), q]
        c != d && push!(S[c], d)
    end
    return length.(S)
end

@testset "04 rules on synthetic series" begin
    # zigzag: 1 → 1.01 → 1.002 → 1.012 → 1.004 (h = 0.005): peaks 2, 4; troughs 3, 5
    x = [1.0, 1.01, 1.002, 1.012, 1.004]
    @test p64r_zigzag(x, 0.005) == ([2, 4], [3, 5])
    @test p64r_drops(x, 0.005) ≈ [0.008, 0.008]
    @test p64r_zigzag(x, 0.02) == (Int[], Int[])                         # nothing reaches h
    # a sawtooth of period 6 and drop 0.01: 4 drops, equal spacing (CV 0)
    saw = repeat([1.0, 1.002, 1.004, 1.006, 1.008, 1.01], 4)
    p, t = p64r_zigzag(saw, 0.002)
    @test p == [6, 12, 18] && diff(p) == [6, 6] && p64r_drops(saw, 0.002) ≈ fill(0.01, 3)
    # bursts: [0 3 4 0 2 0 0 0 5 0 0 1] → bursts {3,4,0,2} (gap of one bridged), {5}, {1}: 3
    b = p64r_bursts([0, 3, 4, 0, 2, 0, 0, 0, 5, 0, 0, 1])
    @test b.bursts == 3 && b.quiet == 7 / 12
    @test p64r_bursts(fill(1, 10)) == (; bursts = 1, quiet = 0.0)
    # crossing
    @test p64r_crossing([1.0, 2.0, 3.0], [0.0, 0.2, 1.0], 0.5) ≈ 2 + 0.3 / 0.8
    @test p64r_crossing([1.0, 2.0], [0.6, 1.0], 0.5) === nothing && p64r_crossing([1.0, 2.0], [0.0, 0.1], 0.5) === nothing
    # Spearman: monotone 1, reversed −1; ties averaged
    @test p64r_spearman([1, 2, 3, 4], [0.1, 0.5, 0.7, 2.0]) ≈ 1 && p64r_spearman([1, 2, 3], [3.0, 2.0, 1.0]) ≈ -1
    @test p64r_ranks([1.0, 2.0, 2.0, 3.0]) == [1.0, 2.5, 2.5, 4.0]
    @test p64r_ols([1.0, 2.0, 3.0], [3.0, 5.0, 7.0]) == (a = 1.0, s = 2.0)
    # log bins: f_k = k/2^17, S = f^−1 exactly → α = 1 on the bins in every window; a peak
    f = (1:(2^16)) ./ 2^17
    fb, Sb = p64r_bin(f, f .^ -1.0)
    @test issorted(fb) && fb[1] < 1e-5 && isapprox(fb[end], 0.5; rtol = 0.1) && length(fb) == 86   # empty narrow bins at low f are skipped
    @test all(i -> P64R_BIN_EDGES[1] <= fb[i] <= P64R_BIN_EDGES[end], eachindex(fb))
    if isdefined(P64R_AN, :spectral_exponent)
        @test p64r_alpha(fb, Sb, 1e-4, 1e-2) ≈ 1 atol = 0.02                # bin means of f^−1 (convex) bias it slightly
        @test p64r_window_alpha(fb, Sb, 1e-4, 1e-2) ≈ 1 atol = 0.05
        @test isnan(p64r_alpha(fb, zero(Sb), 1e-4, 1e-2))                   # all-zero T1 spectrum: no α
        fw, Sw = p64r_bin(f, ones(length(f)))
        @test abs(p64r_alpha(fw, Sw, 1e-4, 1e-2)) < 1e-8                    # white
    else
        @test_broken isdefined(P64R_AN, :spectral_exponent)                 # P6.4b2
    end
    S = ones(length(f))
    S[105] = 100.0                                                          # f = 8.0e-4
    pk = p64r_peak(collect(f), S)
    @test abs(pk.f - f[105]) <= 2 / 2^17 && pk.prom ≈ (4 + 100) / 5         # the 5-point mean flattens a spike over 5 bins
    @test p64r_bincentre_strain(10) ≈ sin(2π * 950 / 4000) && abs(p64r_bincentre_strain(30)) > 0.8
    # paper-MCS bins at τ = 2.5: our MCS 1..125 are paper 0.4..50 (bin 1), 126 starts bin 2
    @test p64r_pbin(1, 50, 2.5) == 1 && p64r_pbin(125, 50, 2.5) == 1 && p64r_pbin(126, 50, 2.5) == 2
    @test p64r_ours(4000, 3.3) == 13_200 && p64r_ours(50, 1.0) == 50
    # τ of the brick wall: the mean unlike share over its boundary sites, by hand: a site at
    # distance 1 from a straight vertical wall sees 8 of the 20 offsets across it, at distance
    # 2 it sees 3; corners differ, so only a band is pinned here and the exact value below
    @test 0.25 < p64r_ubar(p64r_brick(P64R_L)) < 0.35
    # record round trip of one row of every type
    @test p64r_parse(Vector{Float64}, p64r_fmt([1.5, NaN, -2.0]))[[1, 3]] == [1.5, -2.0]
    @test p64r_parse(Float64, p64r_fmt(0.1 + 0.2)) === 0.1 + 0.2
end

@testset "04 observables on hand-built states (P6.4b2 names)" begin
    lat = p64r_lat(P64R_L)
    σ = p64r_brick(P64R_L)
    @test maximum(σ) == 256 && all(==(256), [count(==(c), σ) for c in 1:256])
    if all(s -> isdefined(P64R_AN, s), (:side_counts, :topology_moments, :stored_energy, :contact_changes, :central_moment))
        # A-2 calibration: closed y, no wall cells → μ2(n) = 7/16 (V1b band), interior all hexagons
        @test p64r_mu2n(σ) ≈ 7 / 16 && p64r_in(p64r_mu2n(σ), 0.3, 0.6)
        @test p64r_hexfrac(σ, 256) == 1
        @test p64r_sides(σ, lat, 256) == p64r_sides_oracle(σ, 256)
        @test P64R_AN.stored_energy(σ, lat) == p64r_phi_oracle(σ)
        # C-V1b (negative controls): the wall counted as a side (wall id 257 on rows 1 and 258)
        # gives 7/64; periodic y gives 0. Both are outside V1b's band.
        σw = fill(Int32(257), 256, 258)
        σw[:, 2:257] .= σ
        nw = P64R_AN.side_counts(σw, Lattice((256, 258); boundary = (Periodic(), Closed())))[1:256]
        @test P64R_AN.central_moment(nw) ≈ 7 / 64 && !p64r_in(7 / 64, 0.3, 0.6)
        mp = P64R_AN.topology_moments(σ, Lattice(P64R_L; boundary = (Periodic(), Periodic()))).mu2_n
        @test mp == 0 && !p64r_in(mp, 0.3, 0.6)
        # C-V18: shifting every odd brick row by one more brick (offset 24) changes every
        # bubble's contact list (the bricks above and below are other ids)
        σs = Int32[(r = (y - 1) ÷ 16; r * 16 + mod(x - 1 - (isodd(r) ? 24 : 0), 256) ÷ 16 + 1) for x in 1:256, y in 1:256]
        cc = P64R_AN.contact_changes(P64R_AN.cell_graph(σ, lat), P64R_AN.cell_graph(σs, lat))
        changed = Set(Iterators.flatten(Iterators.flatten((cc.lost, cc.gained))))
        @test length(changed) / 256 == 1 && !(length(changed) / 256 < 0.5)
        # V19 premise: the brick wall at A = 256 has no area energy
        @test p64r_area_frac(σ, fill(256.0, 256), fill(256.0, 256)) == 0
        # V7/V8 classification: the brick wall's mid rows (centroids 120.5, 136.5, 104.5,
        # 152.5) are mid; the next rows (88.5, 168.5) are away
        c = p64r_cells(σ, 256)
        @test sort(unique(round.(abs.(c.cy .- 128.5); digits = 6)))[1:4] == [8.0, 24.0, 40.0, 56.0]
        @test count(b -> abs(c.cy[b] - 128.5) <= P64R_MID, 1:256) == 64
    else
        @test_broken false                                                  # P6.4b2 not on this tree
    end
end

# ---------------------------------------------------------------------------------------------
# SMOKE: the no-shear rows at full size (binding once P6.4b2 lands)
# ---------------------------------------------------------------------------------------------

const P64R_SMOKE = Dict{Symbol, Any}()
if !P64R_FULL
    @testset "04 SMOKE: V1, V1b, V19 — ordered foams 256² (2 replicates)" begin
        p64r_template(false, P64R_L)
        foams = [p64r_foam(:ordered, k; seedf = _ -> p64r_smoke_seed(k)) for k in 1:2]
        P64R_SMOKE[:ordered] = foams
        for (st, row) in foams
            @info "04 SMOKE ordered foam" row["hex"] row["mu2n"] row["area_frac"] row["nbub"]
            @test row["nbub"] == 256                                         # no bubble lost at Γ = 1
            @test row["hex"] >= 0.95                                         # V1
            @test p64r_in(row["mu2n"], 0.3, 0.6)                             # V1b
            @test row["area_frac"] < 5e-3                                    # V19 (relaxed)
            # the library's φ and n on a simulated state, against the oracles
            @test P64R_AN.stored_energy(st.σ, p64r_lat(P64R_L)) == p64r_phi_oracle(st.σ)
            @test p64r_sides(st.σ, p64r_lat(P64R_L), 256) == p64r_sides_oracle(st.σ, 256)
            @test P64R_AN.stored_energy(st.σ, p64r_lat(P64R_L)) < P64R_AN.stored_energy(p64r_brick(P64R_L), p64r_lat(P64R_L))
        end
    end
    @testset "04 SMOKE: PREP and C-V1 — one d081 foam" begin
        st, row = p64r_foam(:d081, 1; seedf = t -> p64r_smoke_seed(10 + t))
        P64R_SMOKE[:d081] = (st, row)
        @info "04 SMOKE d081 foam" row["mu2n"] row["try"] row["stop"] row["nbub"] row["hex"]
        @test row["ok"] && abs(row["mu2n"] - 0.81) <= P64R_PREP_TOL           # PREP
        @test row["hex"] < 0.95                                               # C-V1: V1's measure rejects a disordered foam
        @test row["nbub"] < 256 && row["stop"] > 0
        @test row["mu2n"] > maximum(r["mu2n"] for (_, r) in P64R_SMOKE[:ordered])
        @test row["area_frac"] < 5e-3
    end
end

# ---------------------------------------------------------------------------------------------
# SMOKE: shear (κ-free checks; gate: P6.4a1)
# ---------------------------------------------------------------------------------------------

"""Per-bubble circular centroid x (sites) of ids 1:n."""
function p64r_cx(σ, n)
    X = size(σ, 1)
    s, c = zeros(n), zeros(n)
    for I in CartesianIndices(σ)
        b = σ[I]
        s[b] += sinpi(2I[1] / X)
        c[b] += cospi(2I[1] / X)
    end
    return [atan(s[b], c[b]) * X / 2π for b in 1:n]
end
"""Mean x drift (sites; minimum-image increments of circular centroids every 10 MCS) of the
top (start centroid y ≥ 192) and bottom (≤ 64) bubbles over `mcs` MCS of bulk shear at
model β; the T1 events; the final area fraction."""
function p64r_drift(st, βm, mcs, seed)
    n = length(st.A)
    X = size(st.σ, 1)
    lat = p64r_lat(size(st.σ))
    integ = init(p64r_problem(st, mcs; shear = true, β = βm, bulk = true, seed), P64R_ALG)
    cy = p64r_cells(st.σ, n).cy
    x0 = p64r_cx(st.σ, n)
    d = zeros(n)
    g = P64R_AN.cell_graph(st.σ, lat)
    t1 = 0.0
    for m in 1:mcs
        step!(integ)
        g2 = P64R_AN.cell_graph(integ.u.σ, lat)
        t1 += P64R_AN.t1_events(g, g2; unit = :t1)
        g = g2
        if m % 10 == 0
            x1 = p64r_cx(integ.u.σ, n)
            d .+= mod.(x1 .- x0 .+ X / 2, X) .- X / 2
            x0 = x1
        end
    end
    return (; top = mean(d[cy .>= 192]), bottom = mean(d[cy .<= 64]), t1,
        area = p64r_area_frac(integ.u.σ, p64r_vol(integ.u, n), st.A))
end

if !P64R_FULL
    @testset "04 SMOKE: shear sign, T1 detection and V19 under shear (gate P6.4a1)" begin
        if !P64R_SHEAR_READY
            for _ in ("S1 sign", "C-S1", "S2 T1", "C-S2", "S3 V19")
                @test_broken P64R_SHEAR_READY
            end
        else
            p64r_template(true, P64R_L)
            st = P64R_SMOKE[:ordered][1][1]
            sh = p64r_drift(st, 0.05, 500, p64r_smoke_seed(21))
            nul = p64r_drift(st, 0.0, 500, p64r_smoke_seed(22))
            @info "04 SMOKE shear (β_model = 0.05 and 0, 500 MCS)" sh nul
            @test sh.top > 1 && sh.bottom < -1                                # S1: top → +x, bottom → −x (Figs. 4a, 5a)
            @test max(abs(nul.top), abs(nul.bottom)) < 0.25 * min(sh.top, -sh.bottom)   # C-S1: no shear, no drift
            @test sh.t1 >= 1                                                  # S2: T1s are detected under shear
            @test nul.t1 == 0                                                 # C-S2: none in a relaxed foam at T → 0⁺
            @test sh.area < 5e-3                                              # S3: V19 on a sheared state
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL record (D-146): recompute every row from the committed record
# ---------------------------------------------------------------------------------------------

function p64r_check(V, devs; broken_ok)
    for v in V
        if v.kind === :info
            @info "04 info $(v.id)" v.value v.band
        elseif v.kind === :control
            @test v.ok                                                         # controls must behave as pre-registered
        elseif v.ok
            @test v.ok
        elseif broken_ok && any(d -> d["id"] == v.id, devs)
            @test_broken v.ok                                                  # a D-154 deviation
        else
            @error "04 row failed" v.id v.value v.band
            @test v.ok
        end
    end
    @test count(v -> v.kind === :row, V) == 42 && count(v -> v.kind === :control, V) == 4
end

@testset "04 FULL record: every row from reproductions/data/04/full-*" begin
    dirs = isdir(P64R_DATA) ? filter(d -> startswith(d, "full-") && isdir(joinpath(P64R_DATA, d)), readdir(P64R_DATA)) :
           String[]
    if isempty(dirs) && !P64R_SHEAR_READY
        @test_broken !isempty(dirs)                                            # pending P6.4a1 and the FULL run
    else
        length(dirs) == 1 || @info "04: expected exactly one reproductions/data/04/full-* directory" dirs
        @test length(dirs) == 1
        if length(dirs) == 1
            D = joinpath(P64R_DATA, only(dirs))
            for f in ("provenance.toml", "verdicts.tsv", ("$k.tsv" for k in keys(P64R_SCHEMA))...)
                @test isfile(joinpath(D, f))
            end
            R = p64r_read(D)
            # the record is the pre-registered protocol
            @test sort([(r["foam"], r["k"]) for r in R["foams"]]) ==
                  sort([[("ordered", k) for k in 1:10]; [(string(f), k) for f in keys(P64R_FOAMS) if f !== :ordered for k in 1:5]])
            @test all(r -> r["seed"] == p64r_prep_seed(Symbol(r["foam"]), r["k"], r["try"]), R["foams"])
            @test all(r -> r["ly"] == P64R_FOAMS[Symbol(r["foam"])].L[2], R["foams"])
            cal = p64r_sel(R["loops"]; set = "cal")
            @test sort([(r["J"], r["r"], r["k"]) for r in cal]) == sort([(3.0, r, k) for r in P64R_CAL_R for k in 1:5])
            @test all(r -> r["gamma0"] == r["J"] * r["r"], cal)
            sc = p64r_sel(R["loops"]; set = "scan")
            @test sort([(r["J"], r["gp"], r["k"]) for r in sc]) == sort([(J, J * r, k) for J in P64R_SCAN_J for r in P64R_SCAN_R for k in 1:5])
            @test all(r -> length(r["t1_cycles"]) == 10 && length(r["phi_bins"]) == 40, R["loops"])
            κ = p64r_kappa(R)
            @test only(R["calibration"])["kappa"] ≈ κ.kappa rtol = 1e-12
            @test only(R["calibration"])["tau"] ≈ p64r_tau(R) rtol = 1e-12
            for r in filter(r -> r["set"] != "cal", R["loops"])
                @test r["gamma0"] ≈ κ.kappa * r["gp"] rtol = 1e-12
            end
            @test all(r -> r["beta_model"] ≈ κ.kappa * r["beta"], R["bulk"])
            @test length(p64r_sel(R["bulk"]; set = "spec")) == 75 && all(r -> r["mcs"] == P64R_TSPEC, p64r_sel(R["bulk"]; set = "spec"))
            @test length(p64r_sel(R["bulk"]; set = "v14")) == 100 && all(r -> r["mcs"] == P64R_T14, p64r_sel(R["bulk"]; set = "v14"))
            @test length(p64r_sel(R["bulk"]; set = "v16")) == 20 && length(p64r_sel(R["bulk"]; set = "v16c")) == 5
            @test length(p64r_sel(R["steady"]; set = "v2")) == 5 && all(r -> length(r["phi_50"]) == P64R_TV2 ÷ 50, p64r_sel(R["steady"]; set = "v2"))
            V = p64r_verdicts(R)
            dev_f = joinpath(D, "deviations.tsv")
            devs = isfile(dev_f) ? [Dict(zip(split(readline(dev_f), '\t'), split(l, '\t'))) for l in readlines(dev_f)[2:end]] :
                   Dict{String, String}[]
            p64r_check(V, devs; broken_ok = true)
            vt = split.(readlines(joinpath(D, "verdicts.tsv"))[2:end], '\t')
            for v in V
                v.kind === :info && continue
                rr = filter(l -> l[1] == v.id, vt)
                @test length(rr) == 1 && rr[1][end] == (v.ok ? "PASS" : "FAIL")
            end
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL: rerun everything (offline on the PC; D-146, D-157)
# ---------------------------------------------------------------------------------------------

function p64r_tmap(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads :dynamic for i in eachindex(xs)
        out[i] = f(xs[i])
    end
    return out
end

function p64r_full()
    R = Dict{String, Vector{Dict{String, Any}}}(k => Dict{String, Any}[] for k in keys(P64R_SCHEMA))
    for L in (P64R_L, P64R_L_LOW), s in (false, true)
        p64r_template(s, L)
    end
    tag!(d; kw...) = (for (k, v) in kw
        d[string(k)] = v
    end; d)
    # foams, then τ (A-5)
    jobs = [[(:ordered, k) for k in 1:10]; [(f, k) for f in keys(P64R_FOAMS) if f !== :ordered for k in 1:P64R_REPS]]
    res = p64r_tmap(((f, k),) -> (f, k, p64r_foam(f, k)), jobs)
    F = Dict((f, k) => st for (f, k, (st, _)) in res)
    append!(R["foams"], [row for (_, _, (_, row)) in res])
    τ = p64r_tau(R)
    # κ stage (J = 3, model r grid), then κ
    cj = [(i, r, k) for (i, r) in enumerate(P64R_CAL_R) for k in 1:P64R_REPS]
    append!(R["loops"], p64r_tmap(cj) do (i, r, k)
        tag!(p64r_loop(F[(:ordered, k)], 3.0, 3.0 * r, P64R_T0, p64r_run_seed(P64R_BLOCK.cal, i, k), τ);
            set = "cal", r, gp = NaN, k)
    end)
    κ = p64r_kappa(R)
    push!(R["calibration"], Dict{String, Any}("kappa" => κ.kappa, "r_star" => κ.r_star, "tau" => τ))
    isnan(κ.kappa) && error("04 FULL: no first-T1 crossing at J = 3 on the calibration grid; κ cannot be calibrated")
    # V5 scan (paper r grid), V3, V4, V6: every γ0 = κ × paper γ0
    lj = [[("scan", J, J * r, P64R_T0, 100j + i) for (j, J) in enumerate(P64R_SCAN_J) for (i, r) in enumerate(P64R_SCAN_R)];
          [("v3", 3.0, gp, P64R_T0, i) for (i, gp) in enumerate((1.0, 3.5, 7.0))];
          [("v4", J, 7.0, P64R_T0, i) for (i, J) in enumerate((1.0, 5.0, 10.0))];
          [("v6", 3.0, 4.0, T, i) for (i, T) in enumerate(P64R_V6_T)]]
    lj = [(j..., k) for j in lj for k in 1:P64R_REPS]
    append!(R["loops"], p64r_tmap(lj) do (set, J, gp, T, i, k)
        tag!(p64r_loop(F[(:ordered, k)], J, κ.kappa * gp, T, p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), i, k), τ);
            set, r = gp / J, gp, k)
    end)
    # V2, V9 (steady boundary, paper γ0 = 7)
    sj = [[("v2", :ordered, P64R_TV2)]; [("v9", :d165, P64R_TV9)]; [("v9c", :ordered, P64R_TV9)]]
    sj = [(j..., k) for j in sj for k in 1:P64R_REPS]
    append!(R["steady"], p64r_tmap(sj) do (set, f, T, k)
        tag!(p64r_steady(F[(f, k)], κ.kappa * 7.0, T, p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), 0, k), τ);
            set, foam = string(f), k)
    end)
    # bulk: spectral set, V14, V16 (+ control)
    bj = [[("spec", f, β, P64R_TSPEC) for f in (:ordered, :d081, :d165) for β in P64R_BETAS];
          [("v14", f, β, P64R_T14) for f in (:d165, :d172, :d107, :d095) for β in P64R_BETAS14];
          [("v16", f, 0.01, P64R_T16) for f in (:d081, :d165, :d172, :d202)]; [("v16c", :d165, 0.0, P64R_T16)]]
    bj = [(j..., i, k) for (i, j) in enumerate(bj) for k in 1:P64R_REPS]
    out = p64r_tmap(bj) do (set, f, β, T, i, k)
        run, W, S = p64r_bulk(F[(f, k)], β, κ.kappa, T, p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), i, k), τ;
            spectra = set == "spec")
        (tag!(run; set, foam = string(f), k), [tag!(w; set, foam = string(f), beta = β, k) for w in W],
            [tag!(s; foam = string(f), beta = β, k) for s in S])
    end
    for (run, W, S) in out
        push!(R["bulk"], run)
        run["set"] == "v14" || append!(R["windows"], W)
        append!(R["spectra"], S)
    end
    return R
end

if P64R_FULL
    @testset "04 FULL: every row, rerun" begin
        @test P64R_SHEAR_READY                                                 # FULL needs P6.4a1
        if P64R_SHEAR_READY
            t0 = time()
            R = p64r_full()
            V = p64r_verdicts(R)
            for v in V
                @info "04 FULL $(v.id) ($(v.kind))" v.value v.band v.ok
            end
            if !isempty(P64R_RECORD_OUT)
                p64r_write(P64R_RECORD_OUT, R)
                open(joinpath(P64R_RECORD_OUT, "verdicts.tsv"), "w") do io
                    println(io, "id\tkind\tvalue\tband\tresult")
                    for v in V
                        println(io, join((v.id, v.kind, repr(v.value), v.band, v.ok ? "PASS" : "FAIL"), '\t'))
                    end
                end
                @info "04 FULL record written" P64R_RECORD_OUT wall = time() - t0 threads = Threads.nthreads()
            end
            p64r_check(V, Dict{String, String}[]; broken_ok = false)
        end
    end
end
