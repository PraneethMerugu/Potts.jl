# reproduction 04, Jiang, Swart, Saxena,
# Asipauskas & Glazier, "Hysteresis and avalanches in two-dimensional foam rheology
# simulations", Phys. Rev. E 59, 5819 (1999) ("04b"). The
# pre-registered targets are spec 04 §5.2 V1–V20 (docs/design/research/model-specs/04_foam.md);
# every band below is copied from §5.2's "Acceptance" column, with the observable, the
# protocol, the run lengths, the replicate counts and the seeds fixed here. Decisions: D-186
# (streams), D-155/D-156 (ship provisional; unstated parameters are calibrated and labelled),
# D-146 (FULL offline, record under reproductions/data/04/), D-153 (test form), D-154
# (deviations table), D-158 (pins), D-048 (oracles, negative controls).
#
# ── APIs this file names that do not exist on the base commit (d7fc5793) ──────────────────
# - The foam analysis (test acceptance/foam_analysis_tests.jl), in
#   PottsModels.Analysis: stored_energy, side_counts, contact_changes, t1_events,
#   central_moment, topology_moments, power_spectrum, spectral_exponent, mean_t1,
#   yield_strain (and the existing cell_graph). Used exactly as that file pins them.
# - The copy direction (test acceptance/copy_direction_tests.jl): the copy-scope
#   `direction[1]` (x_target − x_source, minimum image on the periodic x axis),
#   `position[target][2]` and `mcs` in a drive.
#
# ── Protocol (pre-registered) ──────────────────────────────────────────────────────────────
# Lattice 256² (L_x × L_y), `boundary = (Periodic(), Closed())` (04b p.5822). Contacts
# `NeighborOrder(4)` (20 neighbours, 04b p.5822) with J = 3; area term Γ(a − A)² with Γ = 1
# (04b p.5823); dry foam, no medium site. Proposals `NeighborOrder(4)` under
# `BoundarySiteCPM()` (deviation DV1 below). T = 0 is `Metropolis(; temperature = 1e-6)`, the
# T → 0⁺ limit of spec A-6 (ties accepted with P = 1, uphill rejected; integer contact and
# area ΔH ≥ 1; `copy_direction_tests.jl` item 5 shows the residual band 0 < ΔH < 1e-4 is negligible).
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
# boundary sites of (unlike offsets)/20 (`foam_ubar`, off-lattice offsets are null). One
# paper MCS is therefore τ = 1/ū of ours; τ is measured on ordered foams 1–5 before any
# shear run (≈ 3.3 on the brick wall) and every shear duration, period, bin, window,
# t_first and spectral frequency below is in PAPER MCS (our MCS m is paper time m/τ;
# `power_spectrum(x; dt = 1/τ)`). Foam preparation (A-8) is in our MCS. When the boundary-site proposal's
# `UnlikeNeighbor` replaces DV1, τ = 1 by construction (a new D-entry re-runs).
# γ-scale calibration κ (A-1, "γ0/J ≈ 1.9"): model field = κ × paper field, for γ0 AND β.
# Stage 1 (set "cal"): J = 3, model r = γ0_model/J on the geometric grid 2^(−2:0.25:6)
# (0.25 … 64); r* = the first r at which the median over replicates of the mean T1 events
# per cycle crosses 0.5 (linear interpolation; a crossing at the first grid point or none at
# all leaves κ undefined and FULL stops: a science question); κ = 3r*/5.8 (paper: butterfly
# → U between γ0 = 5.7 and 5.8 at J = 3, Fig. 3(a)). Stage 2 (set "scan", V5) and every
# other row run at κ × the paper value. V3's "transition 5.8 ± 1.2" is consumed by the
# calibration (reported, not a target). Feasibility probe on the base commit (reference
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
# N̄ = `mean_t1([total], live bubbles at t = 0, β_paper·T_run)` (A-9:
# unit shear = β·t, as spec §3.2 and claim 14 read it). Spectra: `power_spectrum` of the
# per-MCS series (T1 events, φ̂) over 2^17 paper MCS (f to 0.5, lowest 7.6e-6, as Fig. 8),
# averaged into 20 log bins per decade (edges 10^(−5.2:0.05:−0.3); bin f = geometric mean
# of its f_k, S = mean of its S_k), then averaged over replicates; α =
# `spectral_exponent(f_bin, S_bin, range)` over [1e-4, 1e-2] unless stated; bins with S ≤ 0
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
#     the paper's unlike-neighbour draw (`UnlikeNeighbor`); same move given an unlike
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
# Measured on the base commit (Apple M-series, one thread): 256² NeighborOrder(4) under
# BoundarySiteCPM at T → 0⁺ ≈ 1.4 ms/MCS without shear; ≈ 3.8 ms/MCS with the per-MCS
# neighbour diff under boundary shear (reference shear model, stub analysis functions);
# a reduced end-to-end FULL (stubs) averaged ≈ 4.2 ms/MCS. Foams ≈ 2 s (ordered), ≈ 4 s
# (disordered). Not measured: the PC, and the real copy-direction and foam-analysis code (spec §8 guessed
# 5 ms/MCS, ≈ 10 min per 10⁵ MCS). Paper MCS per block (× τ ≈ 3.3 for ours): κ stage
# 33 × 5 × 4e4 = 6.6e6; V5 scan 4 × 24 × 5 × 4e4 = 1.9e7; V3/V4/V6 50 × 4e4 = 2e6; V2/V9
# 1e5; spectral set 75 × 2^17 = 9.8e6; V14 100 × 2^15 = 3.3e6; V16 25 × 1e4 = 2.5e5.
# Total ≈ 4.1e7 paper = 1.35e8 of our MCS ≈ 140–190 CPU-h at 4 ms (loops ≈ 68 %, spectral
# set ≈ 24 %), ≈ 6–8 h on the PC's 24 threads. SMOKE: ≈ 30 s of runs plus model
# compilation (no-shear ≈ 15 s, shear ≈ 10 s).
#
# Tiers. always: rules on synthetic series and hand-built states (oracles). SMOKE (default):
# the no-shear rows at full size, then the κ-free shear checks. FULL record
# (always): reads the one directory reproductions/data/04/full-*, recomputes τ, κ and every
# row; a failing row must be listed in its deviations.tsv (D-154) and is then
# `@test_broken`. FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full; offline on the PC,
# D-146, D-157): reruns everything; with RECORD_OUT=<dir> it also writes the record.
#
# Record schema (TSV, one header line; vectors comma-joined; NaN as "NaN"): see
# SCHEMA; plus provenance.toml (commit, seeds, threads, machine, wall time),
# verdicts.tsv (id, kind, value, band, result) and an optional deviations.tsv (id, ours,
# paper, cause, question).

@testsetup module FoamSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "shared", "foam.jl"))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "04 rules on synthetic series" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "04 rules on synthetic series" begin
        # zigzag: 1 → 1.01 → 1.002 → 1.012 → 1.004 (h = 0.005): peaks 2, 4; troughs 3, 5
        x = [1.0, 1.01, 1.002, 1.012, 1.004]
        @test zigzag(x, 0.005) == ([2, 4], [3, 5])
        @test drops(x, 0.005) ≈ [0.008, 0.008]
        @test zigzag(x, 0.02) == (Int[], Int[])                         # nothing reaches h
        # a sawtooth of period 6 and drop 0.01: 4 drops, equal spacing (CV 0)
        saw = repeat([1.0, 1.002, 1.004, 1.006, 1.008, 1.01], 4)
        p, t = zigzag(saw, 0.002)
        @test p == [6, 12, 18] && diff(p) == [6, 6] && drops(saw, 0.002) ≈ fill(0.01, 3)
        # bursts: [0 3 4 0 2 0 0 0 5 0 0 1] → bursts {3,4,0,2} (gap of one bridged), {5}, {1}: 3
        b = foam_bursts([0, 3, 4, 0, 2, 0, 0, 0, 5, 0, 0, 1])
        @test b.bursts == 3 && b.quiet == 7 / 12
        @test foam_bursts(fill(1, 10)) == (; bursts = 1, quiet = 0.0)
        # crossing
        @test foam_crossing([1.0, 2.0, 3.0], [0.0, 0.2, 1.0], 0.5) ≈ 2 + 0.3 / 0.8
        @test foam_crossing([1.0, 2.0], [0.6, 1.0], 0.5) === nothing && foam_crossing([1.0, 2.0], [0.0, 0.1], 0.5) === nothing
        # Spearman: monotone 1, reversed −1; ties averaged
        @test spearman([1, 2, 3, 4], [0.1, 0.5, 0.7, 2.0]) ≈ 1 && spearman([1, 2, 3], [3.0, 2.0, 1.0]) ≈ -1
        @test ranks([1.0, 2.0, 2.0, 3.0]) == [1.0, 2.5, 2.5, 4.0]
        @test ols([1.0, 2.0, 3.0], [3.0, 5.0, 7.0]) == (a = 1.0, s = 2.0)
        # log bins: f_k = k/2^17, S = f^−1 exactly → α = 1 on the bins in every window; a peak
        f = (1:(2^16)) ./ 2^17
        fb, Sb = foam_bin(f, f .^ -1.0)
        @test issorted(fb) && fb[1] < 1.0e-5 && isapprox(fb[end], 0.5; rtol = 0.1) && length(fb) == 86   # empty narrow bins at low f are skipped
        @test all(i -> BIN_EDGES[1] <= fb[i] <= BIN_EDGES[end], eachindex(fb))
        @test alpha(fb, Sb, 1.0e-4, 1.0e-2) ≈ 1 atol = 0.02                # bin means of f^−1 (convex) bias it slightly
        @test window_alpha(fb, Sb, 1.0e-4, 1.0e-2) ≈ 1 atol = 0.05
        @test isnan(alpha(fb, zero(Sb), 1.0e-4, 1.0e-2))                   # all-zero T1 spectrum: no α
        fw, Sw = foam_bin(f, ones(length(f)))
        @test abs(alpha(fw, Sw, 1.0e-4, 1.0e-2)) < 1.0e-8                    # white
        S = ones(length(f))
        S[105] = 100.0                                                          # f = 8.0e-4
        pk = foam_peak(collect(f), S)
        @test abs(pk.f - f[105]) <= 2 / 2^17 && pk.prom ≈ (4 + 100) / 5         # the 5-point mean flattens a spike over 5 bins
        @test bincentre_strain(10) ≈ sin(2π * 950 / 4000) && abs(bincentre_strain(30)) > 0.8
        # paper-MCS bins at τ = 2.5: our MCS 1..125 are paper 0.4..50 (bin 1), 126 starts bin 2
        @test pbin(1, 50, 2.5) == 1 && pbin(125, 50, 2.5) == 1 && pbin(126, 50, 2.5) == 2
        @test ours(4000, 3.3) == 13_200 && ours(50, 1.0) == 50
        # τ of the brick wall: the mean unlike share over its boundary sites, by hand: a site at
        # distance 1 from a straight vertical wall sees 8 of the 20 offsets across it, at distance
        # 2 it sees 3; corners differ, so only a band is pinned here and the exact value below
        @test 0.25 < foam_ubar(brick(FOAM_L)) < 0.35
        # record round trip of one row of every type
        @test foam_parse(Vector{Float64}, fmt([1.5, NaN, -2.0]))[[1, 3]] == [1.5, -2.0]
        @test foam_parse(Float64, fmt(0.1 + 0.2)) === 0.1 + 0.2
    end
end

@testitem "04 observables on hand-built states" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "04 observables on hand-built states" begin
        lat = foam_lat(FOAM_L)
        σ = brick(FOAM_L)
        @test maximum(σ) == 256 && all(==(256), [count(==(c), σ) for c in 1:256])
        # A-2 calibration: closed y, no wall cells → μ2(n) = 7/16 (V1b band), interior all hexagons
        @test foam_mu2n(σ) ≈ 7 / 16 && foam_in(foam_mu2n(σ), 0.3, 0.6)
        @test hexfrac(σ, 256) == 1
        @test sides(σ, lat, 256) == sides_oracle(σ, 256)
        @test FOAM_AN.stored_energy(σ, lat) == phi_oracle(σ)
        # C-V1b (negative controls): the wall counted as a side (wall id 257 on rows 1 and 258)
        # gives 7/64; periodic y gives 0. Both are outside V1b's band.
        σw = fill(Int32(257), 256, 258)
        σw[:, 2:257] .= σ
        nw = FOAM_AN.side_counts(σw, Lattice((256, 258); boundary = (Periodic(), Closed())))[1:256]
        @test FOAM_AN.central_moment(nw) ≈ 7 / 64 && !foam_in(7 / 64, 0.3, 0.6)
        mp = FOAM_AN.topology_moments(σ, Lattice(FOAM_L; boundary = (Periodic(), Periodic()))).mu2_n
        @test mp == 0 && !foam_in(mp, 0.3, 0.6)
        # C-V18: shifting every odd brick row by one more brick (offset 24) changes every
        # bubble's contact list (the bricks above and below are other ids)
        σs = Int32[(r = (y - 1) ÷ 16; r * 16 + mod(x - 1 - (isodd(r) ? 24 : 0), 256) ÷ 16 + 1) for x in 1:256, y in 1:256]
        cc = FOAM_AN.contact_changes(FOAM_AN.cell_graph(σ, lat), FOAM_AN.cell_graph(σs, lat))
        changed = Set(Iterators.flatten(Iterators.flatten((cc.lost, cc.gained))))
        @test length(changed) / 256 == 1 && !(length(changed) / 256 < 0.5)
        # V19 premise: the brick wall at A = 256 has no area energy
        @test foam_area_frac(σ, fill(256.0, 256), fill(256.0, 256)) == 0
        # V7/V8 classification: the brick wall's mid rows (centroids 120.5, 136.5, 104.5,
        # 152.5) are mid; the next rows (88.5, 168.5) are away
        c = foam_cells(σ, 256)
        @test sort(unique(round.(abs.(c.cy .- 128.5); digits = 6)))[1:4] == [8.0, 24.0, 40.0, 56.0]
        @test count(b -> abs(c.cy[b] - 128.5) <= MID, 1:256) == 64
    end
end

@testitem "04 SMOKE: V1, V1b, V19 — ordered foams 256² (2 replicates)" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    if !FOAM_FULL
        @testset "04 SMOKE: V1, V1b, V19 — ordered foams 256² (2 replicates)" begin
            foams = smoke_ordered_foams()
            for (st, row) in foams
                @info "04 SMOKE ordered foam" row["hex"] row["mu2n"] row["area_frac"] row["nbub"]
                @test row["nbub"] == 256                                         # no bubble lost at Γ = 1
                @test row["hex"] >= 0.95                                         # V1
                @test foam_in(row["mu2n"], 0.3, 0.6)                             # V1b
                @test row["area_frac"] < 5.0e-3                                    # V19 (relaxed)
                # the library's φ and n on a simulated state, against the oracles
                @test FOAM_AN.stored_energy(st.ownership, foam_lat(FOAM_L)) == phi_oracle(st.ownership)
                @test sides(st.ownership, foam_lat(FOAM_L), 256) == sides_oracle(st.ownership, 256)
                @test FOAM_AN.stored_energy(st.ownership, foam_lat(FOAM_L)) < FOAM_AN.stored_energy(brick(FOAM_L), foam_lat(FOAM_L))
            end
        end
        @testset "04 SMOKE: PREP and C-V1 — one d081 foam" begin
            st, row = make_foam(:d081, 1; seedf = t -> smoke_seed(10 + t))
            @info "04 SMOKE d081 foam" row["mu2n"] row["try"] row["stop"] row["nbub"] row["hex"]
            @test row["ok"] && abs(row["mu2n"] - 0.81) <= PREP_TOL           # PREP
            @test row["hex"] < 0.95                                               # C-V1: V1's measure rejects a disordered foam
            @test row["nbub"] < 256 && row["stop"] > 0
            @test row["mu2n"] > maximum(r["mu2n"] for (_, r) in smoke_ordered_foams())
            @test row["area_frac"] < 5.0e-3
        end
    end
end

@testitem "04 SMOKE: shear sign, T1 detection and V19 under shear" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    if !FOAM_FULL
        @testset "04 SMOKE: shear sign, T1 detection and V19 under shear" begin
            foam_template(true, FOAM_L)
            st = smoke_ordered_foams()[1][1]
            sh = foam_drift(st, 0.05, 500, smoke_seed(21))
            nul = foam_drift(st, 0.0, 500, smoke_seed(22))
            @info "04 SMOKE shear (β_model = 0.05 and 0, 500 MCS)" sh nul
            @test sh.top > 1 && sh.bottom < -1                                # S1: top → +x, bottom → −x (Figs. 4a, 5a)
            @test max(abs(nul.top), abs(nul.bottom)) < 0.25 * min(sh.top, -sh.bottom)   # C-S1: no shear, no drift
            @test sh.t1 >= 1                                                  # S2: T1s are detected under shear
            @test nul.t1 == 0                                                 # C-S2: none in a relaxed foam at T → 0⁺
            @test sh.area < 5.0e-3                                              # S3: V19 on a sheared state
        end
    end
end

@testitem "04 FULL record: every row from reproductions/data/04/full-*" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "04 FULL record: every row from reproductions/data/04/full-*" begin
        dirs = isdir(DATA) ? filter(d -> startswith(d, "full-") && isdir(joinpath(DATA, d)), readdir(DATA)) :
            String[]
        length(dirs) == 1 || @info "04: expected exactly one reproductions/data/04/full-* directory" dirs
        @test length(dirs) == 1
        if length(dirs) == 1
            D = joinpath(DATA, only(dirs))
            for f in ("provenance.toml", "verdicts.tsv", ("$k.tsv" for k in keys(SCHEMA))...)
                @test isfile(joinpath(D, f))
            end
            R = foam_read(D)
            # the record is the pre-registered protocol
            @test sort([(r["foam"], r["k"]) for r in R["foams"]]) ==
                sort([[("ordered", k) for k in 1:10]; [(string(f), k) for f in keys(FOAMS) if f !== :ordered for k in 1:5]])
            @test all(r -> r["seed"] == prep_seed(Symbol(r["foam"]), r["k"], r["try"]), R["foams"])
            @test all(r -> r["ly"] == FOAMS[Symbol(r["foam"])].L[2], R["foams"])
            cal = sel(R["loops"]; set = "cal")
            @test sort([(r["J"], r["r"], r["k"]) for r in cal]) == sort([(3.0, r, k) for r in CAL_R for k in 1:5])
            @test all(r -> r["gamma0"] == r["J"] * r["r"], cal)
            sc = sel(R["loops"]; set = "scan")
            @test sort([(r["J"], r["gp"], r["k"]) for r in sc]) == sort([(J, J * r, k) for J in SCAN_J for r in SCAN_R for k in 1:5])
            @test all(r -> length(r["t1_cycles"]) == 10 && length(r["phi_bins"]) == 40, R["loops"])
            κ = foam_kappa(R)
            @test only(R["calibration"])["kappa"] ≈ κ.kappa rtol = 1.0e-12
            @test only(R["calibration"])["tau"] ≈ foam_tau(R) rtol = 1.0e-12
            for r in filter(r -> r["set"] != "cal", R["loops"])
                @test r["gamma0"] ≈ κ.kappa * r["gp"] rtol = 1.0e-12
            end
            @test all(r -> r["beta_model"] ≈ κ.kappa * r["beta"], R["bulk"])
            @test length(sel(R["bulk"]; set = "spec")) == 75 && all(r -> r["mcs"] == TSPEC, sel(R["bulk"]; set = "spec"))
            @test length(sel(R["bulk"]; set = "v14")) == 100 && all(r -> r["mcs"] == T14, sel(R["bulk"]; set = "v14"))
            @test length(sel(R["bulk"]; set = "v16")) == 20 && length(sel(R["bulk"]; set = "v16c")) == 5
            @test length(sel(R["steady"]; set = "v2")) == 5 && all(r -> length(r["phi_50"]) == TV2 ÷ 50, sel(R["steady"]; set = "v2"))
            V = foam_verdicts(R)
            dev_f = joinpath(D, "deviations.tsv")
            devs = isfile(dev_f) ? [Dict(zip(split(readline(dev_f), '\t'), split(l, '\t'))) for l in readlines(dev_f)[2:end]] :
                Dict{String, String}[]
            check(V, devs; broken_ok = true)
            vt = split.(readlines(joinpath(D, "verdicts.tsv"))[2:end], '\t')
            for v in V
                v.kind === :info && continue
                rr = filter(l -> l[1] == v.id, vt)
                @test length(rr) == 1 && rr[1][end] == (v.ok ? "PASS" : "FAIL")
            end
        end
    end
end

@testitem "04 FULL: every row, rerun" setup = [FoamSetup] tags = [:pottsmodels, :reproductions] begin
    if FOAM_FULL
        @testset "04 FULL: every row, rerun" begin
            t0 = time()
            R = foam_full()
            V = foam_verdicts(R)
            for v in V
                @info "04 FULL $(v.id) ($(v.kind))" v.value v.band v.ok
            end
            if !isempty(RECORD_OUT)
                foam_write(RECORD_OUT, R)
                open(joinpath(RECORD_OUT, "verdicts.tsv"), "w") do io
                    println(io, "id\tkind\tvalue\tband\tresult")
                    for v in V
                        println(io, join((v.id, v.kind, repr(v.value), v.band, v.ok ? "PASS" : "FAIL"), '\t'))
                    end
                end
                @info "04 FULL record written" RECORD_OUT wall = time() - t0 threads = Threads.nthreads()
            end
            check(V, Dict{String, String}[]; broken_ok = false)
        end
    end
end
