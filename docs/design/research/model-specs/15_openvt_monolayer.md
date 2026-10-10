# 15 — OpenVT growing monolayer with contact inhibition (benchmark spec)

Status: v3 (verified 2026-10-05 by the coordinator's spec verifier; v2 and v1 the same day,
v2 grounds every item in the consortium repo, §1 row **G**; spec written by the peer session
"Potts.jl models and publications"; verification log at the end). Goal (user, 2026-10-05): "produce offline derived figures for the
monolayer project in line with this benchmark. we ultimately want to include Potts.jl in
that lineup". The user also ruled that public is fine and that the results "should naturally
live in the docs" as offline files.

**Rules (user, 2026-10-05):**
- "follow the manuscript whenever possible";
- "recreate every simulation specific figure, and required simulation submission requirement";
- "we should also include their initial benchmark of the Mechanical calibration on 1D cell chains".

What follows from them:
- Every choice follows M: parameters, protocols, analysis, figure layout, axis units and labels.
- A deviation is allowed only where M is silent or Potts cannot yet express M. Each deviation is listed in the docs page's differences table and in §7 as an author question.
- **Precedence: M > repo schema/README (G `schema/README.md`) > implementations and results in G.** Where M is silent, the schema applies; where both are silent, the CPM implementations' majority practice applies. Every conflict is in §1.1 with the winning source.
- Where M contradicts itself (A1, Q2, Q8), use M's schema section (§2.1) and the numbers in its tables, and record the reading.

Citation form: `G:path:line` is the consortium repo at 54f375f; `TSTgh:path:line` is the TST
OpenVT branch; `M p.N` is the manuscript page. `[unverified]` marks an inference not checked
against running code or an author statement.

## 1. Sources

| Prefix | Source | On disk |
|---|---|---|
| **M** | OpenVT consortium, "Reference Model for the Simulation of a Growing Tissue Monolayer with Contact Inhibition". **Target since 2026-10-09: the draft dated 9 October 2026, 14 pp.** (`docs/references/15_OpenVT2026_monolayer-manuscript-draft-2026-10-09.pdf`, gitignored); the changes are listed in §1.2. Before that: the draft dated 2 October 2026, 12 pp. (correspondence R. Vetter). Unpublished draft: its figure captions are still "DETAILED DESCRIPTION HERE" and §4.1.1–4.1.4 are empty | `docs/references/15_OpenVT2026_monolayer-manuscript-draft-2026-10-02.pdf` (gitignored) |
| **G** | Consortium repo `gitlab.com/rvet/monolayergrowth` (public read), HEAD **54f375f** (merge, R. Vetter, 2026-09-21; 409 commits). Holds `schema/README.md`, `implementations/<FW>/`, `results/<FW>/`, the figure `.tex` sources, `results/postprocessing/` (metrics.cpp, concaveman, run_metrics.sh, notebook) and `literature/`. **Most `implementations/` files are older than M** (last touched 2025-03 to 2025-12; §2.5). One LFS object is not fetched (`results/CompuCell3D/Monolayer/CC3D_5T_MonolayerGrowth_1000_Data_Deterministic.zip` is a 133-byte pointer to a 78.7 MB object); its Stochastic twin was deleted in fac8434 | scratch clone only, never in the monorepo |
| **TSTgh** | `github.com/sbr-shakibi/Tissue-Simulation-Toolkit`, branch `OpenVT`, commit 7ae1636 (2026-06-16). G's TST README points here (`G:implementations/Tissue-Simulation-Toolkit/README.md:8`). It is the **only CPM source that implements Table S1** | scratch clone only |
| **E** | R. Vetter, e-mail "OpenVT: Monolayer model specification, manuscript & git", 12 Oct 2024. It is the older baseline: deterministic division at exactly 2A₀ and β = 0.8 / γ = 0.5 cases. **M supersedes it.** | `github.com/OpenVT/reference_models` `monolayer/summary-Oct-12-2024.md` |
| **C** | Public CompuCell3D reference code. It is an older formulation (pressure relaxation, surface instability) and is NOT the M schema | `github.com/OpenVT/reference_models` `monolayer/CompuCell3D/` |

The shipped `OpenVTGrowingMonolayer` (`lib/PottsModels/src/openvt.jl`) implements the **2024
Artistoo set** (A₀ = 25, λ = 20, τ = 84, J_cc = J_cM = 20, deterministic division at 2A₀,
type 1 only). That set is exactly `G:implementations/Artistoo/monolayer.html:56-57,413-421`.
It is **not** the M schema; see §5.

### 1.1 Conflicts between sources and the reading taken (C#)

| # | Item | Sources | Winner and why |
|---|---|---|---|
| C1 | Cell-cycle length | schema: calibration time T *is* the cycle, α = A₀/T (`G:schema/README.md:58`); M: cycle = **5T** (M p.3 §2.2). M contradicts itself: its own §2.1 (p.3, left column) still says "times in units of isolated cell cycle duration T = A\*(0)/α", the schema wording; Tables S2/S4 (α = π/5 R²/T, μ_Amax = 2π R², M p.11) imply A\*(0)/α = 5T. Results hold 1T/5T/10T variants (`G:results/Morpheus/Monolayer/*_{1,5,10}T_major2.zip`, `G:results/TST/TST_{1,5}T_*`) | **M**: explicit. The data confirm it: TST README `5T = 5 × 155 = 775 MCS` (`G:results/TST/contact_inhibited_timeseries/README.md:32`); every `Time to 10k (5T)` = MCS/775 (`G:results/TST/TST_time_to_10k_vs_beta.csv`) |
| C2 | Calibration compression | schema: compression "from both sides", then "removal of one of the two side constraints" (`G:schema/README.md:56-57`); M: "however that was performed in each framework" (M p.3) | **M** delegates the mechanism to each framework. All four CPMs compress by **halving the target area** during a burn-in, with **both chain ends free** (§4.2.1), and the spring–dashpot reference has both ends free (§4.2.2). Potts follows the CPM practice |
| C3 | X truncation | schema: redraw while X ≤ 0 (`G:schema/README.md:39`); M silent | **schema** (M silent). P(X ≤ 0) = Φ(−5) ≈ 3·10⁻⁷, so this never fires in practice. CC3D, Artistoo and Morpheus redraw; TST does not (§2.5) |
| C4 | Replicates | schema: stochastic frameworks report the mean of **10** replicates (`G:schema/README.md:61`); M: Fig 5 uses **100** runs (M p.3); F2 data use 10 (CC3D, old Morpheus) or 100 (TST, Morpheus "N100") | **M** where it states a number (F5: 100). Elsewhere the schema's 10 is the floor; Potts uses 100 for F2 (matches TST and Morpheus N100) and ≥ 10 per Fig 3/Fig 8 case |
| C5 | Sensitivity analysis (relative condition numbers per framework) | schema only (`G:schema/README.md:81`); absent from M's DATA ANALYSIS list (M p.2–3) and from every figure | **M** (the later, complete list). Not a submission requirement; kept as optional item S-opt1 |
| C6 | Literature comparisons (Drasdo 2005, Germano 2023, Killeen 2023) | schema only (`G:schema/README.md:71-79`); M has none. `G:results/comparison_experiment.tex` plots Bru 1998 radius data in h/µm, not used in M | **M**. Not required; optional item S-opt2 (needs a physical unit map) |
| C7 | Cell diameter CD | schema: 1 CD = 2√(A*(0)/π) = 7.98 px (`G:schema/README.md:55`); every CPM: **CD = 10 px** on a 5-px-high strip, i.e. the relaxed length of a 50-px cell (`G:implementations/Morpheus/Relaxation_11cells_Morpheus_V5.xml:10`; `TSTgh:openvt/model-monolayer-11cells.py:70`; CC3D and Artistoo boxes 10 × 5) | **Implementations** for the lattice protocol. M does not define CD numerically, and Fig 2 requires the relaxed w₁₁ to equal **10 CD**, which holds only for CD = relaxed cell length. With 7.98 px the relaxed chain would read 12.5 "CD" |
| C8 | Output columns | M: `x, y, i, n` with i ∈ {0,1,2,3} (M p.2); `metrics.cpp` requires `x, y, g, n` with g the growing flag 0/1 (`G:results/postprocessing/metrics.cpp:101-130`); CC3D, Morpheus and PhysiCell emit `g` | **M + G (D-215, replacing D-206's "spec over convention").** Submitted O1 files carry `x,y,i,n,g` with g = (i == 0): M's columns plus G's growing flag, because `metrics.cpp` exits without g. The Julia metrics port reads either |
| C9 | Type 1 inequality | schema `A/A0 > β` (`G:schema/README.md:33`); M `a_i ≥ β` (M p.2) | **M** (≥). Morpheus V11, TST and Artistoo use ≥; CC3D uses ≥ for type 1 alone and > in its `1_AND_2` branch (`…Steppables.py:114,123`) |
| C10 | Fig 8 length units | M: lengths in R (M p.3); the draft Fig 8 lattice curves come from centroid files in **px** (`G:results/postprocessing/measurements_compucell3d.csv` r = 270 at N = 10⁴, CC3D A₀ = 25 → 1 R = 2.82 px; Morpheus r = 395 px, 1 R = 3.99 px) | **M**. Potts plots r, a in R. Consortium overlays of these legacy files are divided by R_px (§4.4) |
| C11 | Fig 5 distance bins | notebook: `number_of_bins = 7`, edges `linspace(0, 1.05·max d, 8)` (`G:results/postprocessing/Monolayer02Plot_dists.ipynb` cell 5); M Fig 5 legend has **5** bins 0–7, 7–15, 15–23, 23–31, 31–39 | **M** (the figure): 5 equal bins from 0 to 1.05·max d, labels `int(edge)` |
| C12 | Fig 5 distance origin | M: "distance from the initial cell's center" (M p.4); notebook: mean of all centroids pooled over the 100 runs (cell 5) | **M**. Potts knows the initial centre exactly (lattice centre). Record the pooled-mean variant too; the per-run centre scatter is about ±1.5 R in TST (`TST_5T` pooled analysis) |
| C13 | Division trigger | M: actual area A_i ≥ X_i A\*(0) (M p.2); TST: **target** area ≥ X·A\*(0) (`TSTgh:src/models/openvt-monolayer-type1-tst.cpp:169`); Artistoo divides only when **not inhibited** (`G:implementations/Artistoo/monolayer.html:514`) | **M** (actual area; division decoupled from growth). CC3D (`G:…/ContactInhibitionMonolayerSteppables.py:62`) and Morpheus (`G:implementations/Morpheus/Monolayer_Type1and2_Morpheus_V11.xml:311`) agree with M |
| C14 | Daughters' A\* | M: half the mother's A\* (M p.3); Morpheus V11 sets A0 to the daughter's own volume (`…V11.xml:319-321`) | **M**. CC3D (`…Steppables.py:73`), TST (`…type1-tst.cpp:330-331`) and Artistoo (`monolayer.html:515`, floored) halve A\* |
| C15 | Termination | M: end of the first step with N ≥ 10⁴ (M p.2); CC3D stops at 10 200 (`…Steppables.py:39`); Morpheus freezes motion at N ≥ 10⁴ (`…V11.xml:415-417`) | **M** |
| C16 | Growth rate | Table S1 α = 6.452·10⁻² px/MCS = 50/775 (M p.11); TST α = 0.06493506 = 50/770, "T = 154" (`TSTgh:openvt/monolayer-type1.par:25-26`) | **M** |
| C17 | Morpheus σ of X | M σ = 0.4; Morpheus V11 `Stdev_X = 0.4^2` (`…V11.xml:463`) passed as the SD to `rand_norm` (`:323`), i.e. σ = 0.16 [unverified: Morpheus `rand_norm(mean, sd)` semantics] | **M** (σ = 0.4) |

## 1.2 Manuscript revision of 9 October 2026 (target from 2026-10-09; maintainer: "make this the new target manuscript")

Comparison method: the text of both drafts was diffed, and pages 1–4 were compared as rendered images.

**Unchanged.**
- **Text.** Pages 1–4 are identical apart from the date, so Figs 1–4, §2 (schema, Eqs 1–9) and the protocols are unchanged. The §4.1 CPM text (Eqs 10–12) is unchanged too. It still has both division statements (ms:97, and "Ai(t) ≥ µi,Amax"), so Q25(a) stands.
- **Tables.** Tables S1–S5 are unchanged, including the S1 parameters and the S5 values 290/155/110/75.
- **CPM subsections and code.** §4.1.1–4.1.4 are still empty, and Code Availability is still "TODO".
- **Fig 6.** Its series, axes and legend are unchanged in the text layer.
- **Page numbers.** Citations "M p.1–5" still hold. Later items moved: Fig 5 is on p.6, Figs 7 and 8 on p.10–11, the metrics figure on p.12, Table S1 on p.13 and Table S5 on p.14.

**Changed.**

| # | Item | 2 Oct draft | 9 Oct draft | Consequence for Potts |
|---|---|---|---|---|
| R1 | **Fig 7** "Monolayer of 10K cells: β = 0, varying γ thresholds" | one row per framework, five panels at that framework's T1 γ values, labelled "γ = …, T = …" (§4.0.2 F7) | a **grid**: one row per framework (CC3D, TST, Artistoo, Chaste VM, PolyHoop, PhysiCell, Chaste OS, TinyDEM) × columns **1.1×, 2×, 5×, 10×, 20×**, one colony per cell at the T1 γ of that multiple; **empty where T1 is "—"** (all four lattice/vertex rows at 1.1× and 2×). Cells are coloured **yellow = no inhibition, teal = surface-inhibited**; a black **concave-hull** line; a centred numeric label (1.37–3.45, rising with roughness). Title "Tissue Snapshots with Surface Inhibition" | Potts row: columns 5×/10×/20× at γ = 0.1625/0.5375/0.7625, with 1.1×/2× empty (our T1 is "—" there, as for CC3D/TST/Artistoo). Our O5 files (`sweeps-2026-10-08/f7/`) already hold these three colonies. **The label quantity is not stated** (R5) |
| R2 | **Fig 8 (new)** "Monolayer of 10K cells: γ = 0, varying β thresholds" | did not exist | the same grid for **β** at the T1 β values; cells coloured **yellow = no inhibition, red = area-inhibited**; concave hull; the same label. Title "Tissue Snapshots with Area Inhibition" | **New deliverable.** Potts row at β = 0.625/0.9375/0.9875/1.007/1.0212 (our T1 row). These colonies are **not** in our records (O5 was written for the γ panels only), so they need runs, replayed from the sweep seeds or new seeds at those β |
| R3 | **Metrics figure** | Fig 8 | **Fig 9**, content unchanged (panels a–g, caption still "DETAILED DESCRIPTION HERE") | Our record and page labels "F8" refer to M's Fig 9 from now on. Rename on the page; record names stay |
| R4 | **Fig 5** "100 runs of 1000 cells" | rows TST, Artistoo, PolyHoop, PhysiCell, Chaste (OS), TinyDEM; per-framework distance bins (0–7 … 31–39 radii) | rows **+ CompuCell3D, CHASTE (VM), CHASTE (VT)**; **one shared set of distance bins for all rows: 0–18, 18–37, 37–55, 55–74, 74–93 "radii"**, shown in a single legend | Our Fig 5 row should use the shared bin edges (0, 18.6, 37.2, 55.8, 74.4, 93), so it is comparable. The V4 rules are unaffected: they judge distributions, not display bins. **How the shared edges were derived is not in G** (R5) |
| R5 | Scripts for R1, R2 and R4 | — | **not in G** (G HEAD 14fa42c, 2026-10-06, has only CC3D `Fig7_Snapshot_to_10k.zip` and a snapshot PDF). G's notebook still bins per framework (`1.05·max distance`, 7 bins) | Ask: the Fig 7/8 label quantity (most likely C/C_circle of the concave hull; check against `metrics.cpp` on our O5 colonies before asking), the concave-hull parameters, and the shared Fig 5 bin edges and distance origin |
| R6 | **Table 1** | Chaste (VM) row "?" | Chaste (VM) row filled (β: 0.70140, 0.878550, 0.925650, 0.971540, 0.986860; γ: —, —, 0.006630, 0.31318, 0.33465) | None for Potts; CC3D/TST/Artistoo values unchanged, so our frozen T1 bands stand |

**R5 result (2026-10-09, D-211).** The Fig 7/8 label is **not** a metrics.cpp quantity of the G colonies.
- **What was run.** The consortium's unmodified `metrics.cpp` (concaveman, concavity 1.5) on the CC3D `Fig7_Snapshot_to_10k.zip` colonies and on TST's `final_snapshot_data`.
- **Candidates tested.** C/C_circle, C/(2πR), the inverse, the convex hull, compactness, concavity 1.0–2.0, lengthThreshold 2–5, and disc-point hulls. None reproduces the printed labels within 0.01. For example, CC3D γ gives 1.37/1.78/2.22 against the printed 1.68/2.14/2.89.
- **Not a mix-up.** No row or column reassignment fits. Near-round β colonies print ≈ 1.4–1.7 against C/C_circle 1.10–1.26, and the label/C_circle ratio varies (1.02–1.39).
- **Rendering rule.** Potts panels carry **no centre label** until Q26 is answered. Each Potts colony's C/C_circle (metrics.cpp roughness 1, named as such) is given under the figure, and the page states that M's label quantity is unstated and has been asked.

**Requirements added to §4 by this revision:**
- F7 in the new grid layout (R1);
- the new F8 β grid (R2) and its runs;
- the metrics figure relabelled Fig 9 (R3);
- the Fig 5 row on shared bins (R4).

The figure colours follow M (yellow/teal/red per inhibition state). The concave-hull line is a tissue outline drawn by M, not a cell outline, so the no-outline rule does not apply to it; the consortium-figure exception (D-185) covers it anyway.

## 1.3 Second Potts entry: "Potts.jl (checkerboard)" (D-214, maintainer 2026-10-10)

The submission carries **two** Potts rows. They share one model, one parameter set and one MCS clock, and differ only in the update algorithm:

| Entry | Algorithm | Hardware | Seeds |
|---|---|---|---|
| **Potts.jl** | `SequentialCPM` (random-site sequential Metropolis; `skip_interior = true` for the long sweeps) | CPU | the existing records |
| **Potts.jl (checkerboard)** | `CheckerboardCPM` | the PC's GPU (ROCm; maintainer: "definitely do it on gpu") | its own, disjoint from the sequential seeds |

**What the checkerboard entry is** (`lib/CorePotts/src/checkerboard.jl`, `algorithms.jl`):
- **Colouring.** Sites are coloured by residue class along each axis with stride s = read reach + write reach + 1, so same-colour targets lie outside each other's read/write footprints. On a periodic axis with n mod s ≠ 0, the trailing columns become singleton colours. The OpenVT lattice is closed, so that case does not arise.
- **One MCS** visits every site once, colour by colour, in a random colour order. Within a colour every site proposes in parallel: a uniform Moore source, the same ΔH and the same Metropolis law.
- **Conflicts.** Accepted proposals claim every cell they touch with a unique random priority, and commit only if they win every write claim and no higher-priority copy writes a cell they read. So each cell changes at most once per colour, and readers share. A losing proposal is dropped, not retried ("thinning").
- **Per-cell totals** (area, contact counts) that ΔH reads are updated between colours, not within one ("colour-lagged totals").

**Expected differences from sequential** (the D-214 characterisation list). Each one, if it exceeds the seed spread, becomes a deviation row with its cause:
1. update order (colour sweep vs random-site sequential);
2. colour-lagged totals;
3. claim widening (a commit can block neighbours that sequential would have allowed);
4. thinning of conflicting accepted proposals.

An unexplained difference is chased as a bug. Characterisation describes the entry; it does not gate it (maintainer: "none of these platforms are statistically perfect, but they do have understanding of their deviations").

**Figures and tables.** Every place that carries "Potts.jl" also carries "Potts.jl (checkerboard)", directly after it in the Lattice block:
- **F1:** a second 45 mm closeup panel and banner (case (a), 10⁴ cells, its own seed). The colour variable is as for Potts (§4.0.2 F1), and the banner is in the Q27 colour with a white bold label.
- **F2/S5:** its own chain calibration (11 and 11+10), a T(λ) row in Table S5, and its own legend and inset line. The calibration must be repeated, because T in MCS is a property of the update algorithm.
- **F3, F5, F6/T1, F7, F8, F9:** its own row, curve or legend entry, with insets where the figure has them (F2 b/d/e). Its own Table 1 row.
- **Time unit.** The cycle is 5T(λ = 2) **of the checkerboard calibration** if it differs significantly from 156 MCS. Otherwise it is the sequential 775 MCS; record which one and why.

**Manuscript text:** a subsection "Implementation in Potts.jl (checkerboard)", placed after "Implementation in Potts.jl" (`../openvt-manuscript-section.md`). It is short, because the model listing is shared. It covers:
- that the same `@potts_model` runs unchanged under `CheckerboardCPM`;
- the colouring and claim rule above, in two or three sentences;
- the GPU backend (KernelAbstractions on ROCm);
- its seeds;
- the measured differences from the sequential entry, as a short table that points to the deviation rows.

**Results folder:** `results/Potts.jl_checkerboard/{Relaxation,Monolayer}/`, next to `results/Potts.jl/`. There is also `implementations/Potts.jl_checkerboard/`, holding a README and a runner that point to `implementations/Potts.jl/src`. It uses the same O1–O5 formats and file names, and the framework token **`Potts.jl_checkerboard`** in the file stems that carry one. The token takes an underscore, not a space or hyphen: a space breaks `run_metrics.sh`, and G's precedent is `Chaste_OS_Log` (D-215). The colour keys are `PottsJL` and `PottsJLcheckerboard`. "Potts.jl (checkerboard)" stays the legend and banner text. In the email split it gets its own core section and bulk zips.

**Q27, colour:**
- **Proposal: RGB 0,109,44** (`#006d2c`, Greens-9 step 8).
- **Rejected:** the unused YlGnBu-9 steps (29,145,192; 34,94,168; 127,205,187; 199,233,180) all lie within CIE76 ΔE 11–19 of Morpheus, CC3D, TST or Artistoo, which is too close.
- **Distance from the existing colours:** dark green stays in the cool lattice family (the green end of YlGnBu). It is ΔE 48–110 from every `colors.tex` entry and ΔE 93 from Potts.jl's 8,29,88.
- **Fallback if the consortium prefers one hue per framework family:** 8,29,88 (the Potts.jl colour) with dashed lines and a hatched banner.

## 2. Model schema (M §2.1, p.2; Table S1 p.11)

### 2.1 Objects, processes and events

| Item | M | Potts form |
|---|---|---|
| Agents | individual cells; fields: none | one kind `cell`, no fields |
| Domain | "Unbounded 2D plane" | a closed square lattice large enough that the colony never comes within a guard margin of the edge. The run must fail loudly if it does (G6). CPM practice: Morpheus 1024², no-flux (`…V11.xml:14-20`); TST 1601², periodic (`TSTgh:openvt/monolayer-type1.par:16,22-23`) |
| Initial condition | "A single (approximately circular) cell with initial cell size A\*(0) in the domain center at rest" | one disc of area ≈ 50 sites at the centre (G5). Morpheus does the same: `Sphere radius="R"` at the centre (`…V11.xml:445-449`) |
| Size maintenance | H_volume = λ(A_i − A\*_i)² (Eq 11) | `cells => λ * (volume - A_star)^2` |
| Adhesion | H_adhesion = Σ_{j∈N(i), σ_i≠σ_j} J_{τ_i,τ_j} (Eq 10). No net adhesion ("only repulsion"); J_cc = 20, J_cm = 10 is the neutral point J_cc = 2J_cm | `contacts => J[kind, kind′]` on `Moore(1)` (§2.4) |
| Acceptance | Metropolis, Eq 9 | `@sweep Metropolis(; temperature = T)` |
| Growth | dA\*_i/dt = α if not inhibited, else 0 | `@after_mcs A_star ~ ifelse(inhibited, Pre(A_star), Pre(A_star) + α)`; once per MCS, as in all four CPMs (§2.5) |
| Type 1 inhibition | grow only if a_i = A_i/A\*_i ≥ β, 0 ≤ β ≤ 1 | `volume / A_star >= β` |
| Type 2 inhibition | grow only if f_i ≥ γ | **G1** |
| Combination | logical AND for growth. Growth and division are decoupled: a quiescent cell may still divide | as written (C13) |
| Division | divide when A_i(t) ≥ X_i A\*(0), X_i ~ N(μ = 2, σ = 0.4) | per-cell `X(cell)`, `@divide … when = volume >= X * A0` (G2). X redrawn while ≤ 0 (C3) |
| Daughters | "Both daughters inherit half their mother's actual and preferred area as their own (mass conservation). Both daughters draw a new random value X_i at birth." Odd A\* may go one unit to either daughter (M p.3) | `A_star => Split()`, `X => 2 + 0.4 * randn()` per daughter (G2) |
| Division axis | M silent for CPMs (M p.7 names a "randomly oriented axis" for PolyHoop) | `along = RandomPlane()`. CC3D (`divide_cell_random_orientation`, `…Steppables.py:68`) and Morpheus (`division-plane="random"`, `…V11.xml:310`) agree; TST splits along the minor axis (`…type1-tst.cpp:328-329`) |
| Termination | "The end of the timestep during which at least N = 10,000 cells have been reached" | stop at the end of the first MCS with `ncells ≥ 10⁴` (G7) |

**Ambiguity A1 (division threshold) — RESOLVED.** §2.1 says A_i ≥ X_i A\*(0) with a per-cell
random X_i; §4.1 (p.6) says "at least equal to the mean … μ_{i,Amax}". Three of four CPM
implementations compare the **actual** area with **X_i·A\*(0)**, X_i drawn per cell
(CC3D `…Steppables.py:51-55,62`; Morpheus `…V11.xml:311,322-324`; Artistoo
`monolayer.html:514`). **Use §2.1.** §4.1's sentence is read as shorthand.
M writes the threshold with a cell index, A_i ≥ X_i A\*_i(0) (M p.2 and p.3); the schema writes
X·A0(0) (`G:schema/README.md:39`), and every CPM multiplies by the constant initial area
(A00, `target_area`, A0 = 25). Read A\*_i(0) as the global A\*(0), not the cell's
preferred area at its own birth.

### 2.2 Parameters (Table S1, CPM frameworks CC3D, Morpheus, TST, Artistoo)

| Symbol | Value | Units | Meaning |
|---|---|---|---|
| J_cc | 20.0 | — | cell–cell adhesion |
| J_cm | 10.0 | — | cell–medium adhesion |
| λ | 2.0 | — | area stiffness |
| A\*(0) | 50 | px | initial reference area |
| T | 20 | — | fluctuation amplitude |
| α | 6.452 × 10⁻² | px/MCS | area growth rate (= 50/775) |
| μ_Amax | 100 | px | mean division area (= μ·A\*(0), μ = 2) |
| σ (of X) | 0.4 | — | SD of X_i (§2.1; Table S1 omits it) |

### 2.3 Units (M p.3, §2.2; Table S5 p.12)

- Length unit R = √(A\*(0)/π) = **3.989 px**. Morpheus and TST export centroids already divided by R (`G:results/Morpheus/Monolayer/README.md:3`; `TSTgh:…type1-tst.cpp:216,235`).
- Time: the cell cycle is **5T = 775 MCS** (C1), with mechanical T = 155 MCS at λ = 2 (Table S5; §4.2). **Plot time in cycles (t / 775 MCS)** and label each axis as M does: Fig 6 "(5T)", Fig 7 "T =", Fig 8 "[T]".
- The uninhibited stochastic model reaches 10⁴ cells in **13.57 × 5T** on average (Table 1 caption), about 10 517 MCS. The value equals PhysiCell's γ = 0 entry 13.5693 (`G:results/PhysiCell/Monolayer/gamma_time_10K.csv` row 2) [unverified that it is the source]. Fig 6's dashed lines are 13.57 × {1.1, 2, 5, 10, 20} = 14.927, 27.14, 67.85, 135.7, 271.4 (`G:results/time_to_10k.tex:52-56`).

### 2.4 Lattice-specific definitions

- **Free-surface fraction f_i (Fig 4, p.5, lattice panel).** Over every boundary site s of cell i and every Moore(1) neighbour s′ of s with σ(s′) ≠ i: f_i = #{pairs with σ(s′) = medium} / #{pairs with σ(s′) ≠ i}.
  - This is exactly TST's "method 3" (`TSTgh:src/cellular_potts/ca.cpp:287,295,346-360`), which M's Fig 4 lattice panel draws (`G:results/free_surface.tex:48-110`).
  - **G1:** the cell's medium-contact count over its total unlike-contact count on Moore(1).
  - Other CPMs differ: Morpheus uses a length-scaled medium-contact average (`…V11.xml:354-357`); CC3D the medium share of common surface area with contact order 4 (`…Steppables.py:99-106`; `…ContactInhibitionMonolayer.xml:53`); Artistoo the share of border pixels with no von-Neumann cell neighbour (`monolayer.html:344`). Recorded in §2.5, not followed.
- **Area fraction:** a_i = A_i / A\*_i. (CC3D's repo code divides by the constant A00 instead, `…Steppables.py:96`; not followed.)
- **Neighbour count n_i:** the number of distinct neighbouring cells over the Moore(1) neighbours of the cell's boundary sites, medium excluded. TST does this (`TSTgh:src/cellular_potts/ca.cpp:1685-1700`; its loop runs `i = 0 … n_nb−1`, so it includes the zero offset and skips offset (−1, −1), `ca.cpp:62-65`, a harmless bug). Q3 RESOLVED.
- **Inhibition code** in the output: 0 growing, 1 type 1, 2 type 2, 3 both (M p.2). Same coding as Morpheus `Cause_of_Arrest` (`…V11.xml:418-420`).

### 2.5 CPM implementations in G and TSTgh, compared with M and the Potts choice

| Item | CC3D (`G:implementations/CompuCell3D/Monolayer Growth/Monolayer_Type1_CC3D.zip`, 2025-03) | Morpheus V11 (`G:implementations/Morpheus/Monolayer_Type1and2_Morpheus_V11.xml`, 2025-11) | TST (`TSTgh` type1 model + par) | Artistoo (`G:implementations/Artistoo/monolayer.html`, `5x5/*.js`, 2025-07/12) | M / **Potts** |
|---|---|---|---|---|---|
| Parameter set | legacy: A00 = 25, λ = 10, J 20/**10** (cc/cm; Medium–Tumor 10, `XML:48-49`), T = 20, cycle 310 MCS (`…Steppables.py:12-14,34`; XML `:16,47-52`); Connectivity penalty 10⁵ (`XML:20-22`) | A00 = 50, λ = 20, J 20/**20**, T = 20, cycle **T = 86 MCS** (α = A00/86) (`:427-428,437,453-457`) | **Table S1**: A = 50, λ = 2, J 20/10, T = 20, α = 50/770 (`monolayer-type1.par:2-9,26`; `J20_10.dat`) | legacy 2024: A = 25, λ = 20, J 20/20, T = 20, α = 25/84 (`:413-421`) | Table S1 |
| Lattice | 1000², z = 1 (`XML:14`) | 1024², no-flux (`:10-21`) | 1601², periodic | 1100², non-torus (`:413-414`) | ≥ 1400², closed + guard (G6) |
| Neighbourhoods | Potts order 2; contact order **4** (`XML:17,53`) | sampler order 2, ShapeSurface order 2, scaling none (`:430-441`) | Moore (`neighbours = 2`, `TSTgh:src/parameters/parameters.hpp:115`) | Artistoo default | Moore(1) everywhere |
| Initial cell | `UniformInitializer` box (`XML:57-67`): region 499–501 with `Width` 5 [unverified whether this paints 2 × 2 or 5 × 5] | disc radius R | `GrowInCells(n_init_cells = 1, size_init_cells = 10 default)` (`…type1-tst.cpp:73`; `parameters.hpp:86`) [shape unverified] | 1 pixel (`:547`) | disc ≈ 50 sites |
| f_i | medium share of common surface | `NeighborhoodReporter` average | Moore pair count (= M Fig 4) | border-pixel share, von Neumann, recomputed every **20 MCS** (`:477`) | Moore pair count (G1) |
| a_i | volume / **A00** | volume / A0 | Area / TargetArea | volume / targetVol | A_i / A\*_i |
| n_i | NeighborTracker count | `NeighborhoodReporter` scaling=cell sum (`:388-392`) | Moore distinct (above) | von Neumann distinct (`:344`) | Moore distinct |
| Growth rule | every MCS; always grow for MCS ≤ 100 (`:108-109`) | Euler ODE, Δt = 1 MCS; stops at N > 10⁴ (`:331-349`) | every MCS, after division, before the sweep (`…type1-tst.cpp:114-115`) | every MCS after the sweep | once per MCS, after the sweep |
| Division test | volume ≥ X·A00 | volume ≥ X·A00 | **target** ≥ X·target_area (C13) | volume ≥ X·A0, only if growing (C13) | A_i ≥ X_i·A\*(0) |
| X draw, truncation | N(2, 0.4), redraw ≤ 0 (`:51-55`) | `rand_norm(2, 0.16)` (C17), redraw ≤ 0 (`:350-352`) | N(2, 0.4) × 50 at birth, no truncation (`TSTgh:src/cellular_potts/cell.cpp:101-102,149`) | N(2, 0.4), redraw ≤ 0 (`:91-95`) | N(2, 0.4), redraw ≤ 0 |
| Daughters' A\* | halved, then cloned (`:73-74`) | A0 := own volume (C14) | half of mother's target (`:330-331`) | ⌊A\*/2⌋ (`:515`) | half (`Split()`) |
| Axis | random | random | minor axis | `gm.divideCell` [unverified orientation] | random plane |
| Save cadence | every **20 MCS** (`:382`) | `Logger time-step="-1"` (end only, `:291-301`); a disabled 5-MCS logger (`:272-282`) | `cell_data_no_inhibition_<MCS>.csv` when `thetime % 39 == 0` or N ≥ 1000 (`…type1-tst.cpp:191,200`) | every **84 MCS** (`:57`) | every 39 MCS (Q4) |
| File / columns | `cell_centroids_<mcs>.csv`: `x,y,g,n` in px (`:383-392`) | `Morpheus_timepoint_%05d.csv` (`:287`): `"time","cell.id","x","y","g","n"`, x, y in R | `x_pos,y_pos,radius_i,a_i,f_i` in R (`:209,235`); older G files have px and swapped header (§3.4) | `centroids_neighbors_mcs_<mcs>.csv`: `cell_id,x,y,active,neighbors` in px (`:121`) | M format (§3.1) |
| Stop | N ≥ 10 200 (`:39`) | freeze at N ≥ 10⁴ (`:415-417`) | N > 1000 in the committed build (`:140-147`) | N ≥ 10⁴ | first MCS with N ≥ 10⁴ |

**Reading.** Only TST implements Table S1 (CC3D's growth file already has J 20/10 but A00 = 25, λ = 10). The Morpheus, CC3D and Artistoo growth files in G
predate M. The data they contributed to M (Fig 5 "5T" sets, Table 1 rows, Fig 2 "J10")
came from code not in G (Q12). Morpheus's Fig 1 colour map and arrest code are in V11
(§4.0.2 F1).

## 3. Output and analysis (M p.2–3; G `results/postprocessing/`)

### 3.1 Output formats (O#)

| # | Use | Format (Potts writes) | Precedent |
|---|---|---|---|
| O1 | M's DATA COLLECTION time series (F1, F3, F7, F8) | one headed CSV per save, one row per cell: `x,y,i,n,g` (g = (i == 0); C8, D-215). x, y = centroid in **R**, origin at the lattice centre; i ∈ {0,1,2,3}; n = Moore distinct neighbours. Name `potts_<case>_s<seed>_<MCS:06d>.csv`, in per-seed directories inside descriptively named zips per case, e.g. `<token>_No_CI_stochastic.zip` (D-215). The zips and the O1 manifest are on the bulk side of the email split | M p.2 (C8). Morpheus `Morpheus_timepoint_%05d.csv`, CC3D `cell_centroids_<mcs>.csv` |
| O2 | F5 snapshot at 1000 cells | `x,y,r,f,a`, comma-separated, x, y, r in R, r = √(A\*/π)/R; one file per run, `<token>_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv`, **k = 0…99** (D-215), zipped as `<token>_5T_MonolayerGrowth_1000_Data.zip` on the bulk side | notebook reader (`Monolayer02Plot_dists.ipynb` cell 1): columns 0–4 = x, y, r, f, a (Morpheus tab-separated with two leading columns; TST has a and f swapped) |
| O3 | F6 / T1 sweep table | `Potts.jl_time_to_10k_vs_beta.csv`, `…_vs_gamma.csv` with header `beta,Time to 10k (MCS),Time to 10k (5T)` (resp. `gamma,…`), one row per run (repeated parameter rows for replicates) | `G:results/TST/TST_time_to_10k_vs_beta.csv`, `G:results/Artistoo/Monolayer/time_to_10k_vs_gamma.csv` |
| O4 | F2 relaxation | `width.csv` per case (11, 11+10 total, 11+10 inner) with `Normalized time (T)`, one column per replicate, `Mean …`, `STD …` | `TSTgh:openvt/model-monolayer-11cells.py:77-103` |
| O5 | F7/F8 snapshots | `<token>_beta_<β>_gamma_<γ>_<MCS>MCS.csv` (both parameters, TST's pattern; D-215): `x_pos,y_pos,radius_i,inhibited` in R | `G:results/TST/final_snapshot_data/` |
| O6 | Metrics | `t,N,r,A,C,w,g,C_rel,w_rel` per save, t in cycles; `n,p` neighbour histogram (p in %) | `run_metrics.sh:14`, `metrics.cpp:241-249` (D1) |

### 3.2 `metrics.cpp` — exact pipeline (`G:results/postprocessing/metrics.cpp`)

1. Read the header; strip `"` and `'` from names (`:84-98`). Locate columns **`x`, `y`, `g`, `n`** by name; any missing one is a fatal error (`:101-130`). Extra columns are ignored.
2. Read rows: points (x, y), `grows` = g, `neighbors` = n (`:133-152`).
3. **Boundary:** a convex hull by Graham scan with collinear points excluded (`:33-63,157-158`). The scan sorts `points` in place (`:39-44`); `grows` and `neighbors` are not reordered, which is harmless because only their totals are used. Then `concaveman<double, 32>(points, hull, 1.5, 0)` (`:159`). The template's 32 is the R-tree node size, not a hull parameter (`G:results/postprocessing/concaveman.h:539-546`).
   - concaveman, as ported from mapbox/concaveman by S. Adaszewski (`concaveman.h:1-4`): if the hull already holds every point, return it (`:559-564`). Otherwise put the interior points in an R-tree, queue the hull edges, and for each edge (b, c) with squared length L² ≥ lengthThreshold² find the nearest interior candidate p. Insert p when min(|p−b|², |p−c|²) ≤ L²/concavity² and the new edges cross no existing edge (`:566-678`).
   - Neighbours are **not** computed geometrically: there is no Delaunay step. `n` comes from each framework's own CSV.
4. If the boundary has B > 2 vertices (`:163`):
   - centroid c = mean of the boundary vertices (`:165-181`);
   - r = mean ‖x_i − c‖ (`:185-191`);
   - A = |Σ (x_i y_j − y_i x_j)| / 2 (shoelace) (`:188,192`);
   - C = Σ ‖x_i − x_j‖ over the closed loop (`:189`);
   - w = √(Σ (‖x_i − c‖ − r)² / (B − 1)) (`:193-198`).
   - Otherwise r, A, C, w = NaN. With N < 3 the output is NaN, which is why the measurement files start with `nan`.
5. g = Σ grows / N (`:202-205`), the fraction of growing cells.
6. Optional files: the boundary path `x,y` (`:208-222`), and the neighbour histogram `n,p` with p = 100·count/N for n = 0…max (`:225-246`).
7. stdout: `N,r,A,C,w,g,C/(2√(πA)),w/r` — **8 fields** (`:249`).

**Potts port (G8):** port concaveman and these metrics to Julia. Validate against `metrics.cpp`
compiled in scratch on the G centroid files (e.g. `Parameter_Plane_Morpheus_Centroids.zip`
against `Parameter_Plane_Centroid_Data/metrics.csv`) to 1e-9 relative.

**The reference build must disable FMA contraction.** Verified 2026-10-05 on this machine
(arm64): `c++ -O2 -ffp-contract=off` (Apple clang 17) and `g++-15 -O2 -ffp-contract=off`
both reproduce all 25 rows of the committed `metrics.csv` (`file,N,r,A,C,w,g`, first six
output fields) **byte for byte** with the current `metrics.cpp` (w divided by B − 1). With
the compilers' default contraction the concave hull changes completely: C differs by up to
2× (β = 1.0, γ = 0.45: 2139 vs 1102) and w by up to 10× (β = 1.0, γ = 0: 7.83 vs 0.73), and
clang and gcc disagree with each other. Hence:
- the Julia port must not use `fma`/`muladd`/`@fastmath` in the orientation, squared-distance
  and segment-distance kernels (Julia does not contract by default);
- the hull is ill-conditioned: one ulp in an orientation test can change the boundary. Fig 8
  panels d and e are therefore fragile across frameworks, and Potts' own centroids
  (Float32 on Metal vs Float64) can move them; compute the metrics from Float64 centroids;
- the committed `measurements_*.csv` (F8) were made by the original 978e0bc binary (§3.3),
  which reads columns by position and divides w by B; recomputing them with the current
  binary changes w.

### 3.3 `run_metrics.sh` and the time scalings (`G:results/postprocessing/run_metrics.sh`)

- It writes the header `t,N,R,A,C,w,g` (`:14`, **7 names**). For i in 0…10000 it reads the file `$dir/$filename$(printf fmt i).csv` if it exists, sets **t = i·dt**, and appends the `metrics` stdout (`:15-23`).
- With the current `metrics.cpp` each row gets 8 values against 7 names (D1). The committed `measurements_*.csv` have 7 columns: all four were committed once, in 978e0bc (2025-03-31), by that commit's `metrics.cpp`. It read **x, y, g, n by position** (columns 0–3, no header lookup), divided w by **B** (not B − 1; changed in db5236e) and printed 6 fields. The roughness columns came later (9501e3c, "Add roughness values to metrics output").
  - The legacy Morpheus files behind the draft curve have the header `"cell.center.x","cell.center.y","g","n"`, which the current name-based `metrics.cpp` rejects ("Missing column x."). Rename the columns in a scratch copy before re-running.
- **dt converts the file index to cycles:**

| Line | Framework | Files | dt | Meaning |
|---|---|---|---|---|
| `:26` | PolyHoop | `../polyhoop/Monolayer/beta0.8_cmin0_s0/frame%06d.csv` | 1/4 | 4 frames per cycle |
| `:27` | CC3D | `…/Monolayer_Type1_CC3D_Centroid_data/cell_centroids_%d.csv` | 1/310 | index = MCS; legacy cycle = 310 MCS (`…Steppables.py:13`) |
| `:28` | Morpheus | `…/Benchmark_Monolayer_4178/Morpheus_timepoint_%05d.csv` | 1/97 | index = MCS; legacy cycle = 97 MCS (`G:results/Morpheus/Legacy/Monolayer_26032025_T97MCS/README.md:3`); job 4178 = `Legacy/…/Morpheus_beta0.8_gamma0.0_replicate1.zip` |
| `:29` | PhysiCell | `…/pc_run1/pc_%03d.csv` | 1/62 | 62 frames per cycle [unverified] |

- Note `seq 0 10000` silently drops any index above 10 000, i.e. CC3D or Morpheus MCS above 10⁴.
- `G:results/Morpheus/Monolayer/Parameter_Plane_Centroid_Data/run_metrics.sh` is a per-file variant: header `file,N,r,A,C,w,g` (`:7`).
- **Potts:** t = MCS/775 (cycles), no file-index arithmetic.

### 3.4 Fig 5 pipeline (`G:results/postprocessing/Monolayer02Plot_dists.ipynb`)

- **Inputs** (cell 1): `1000_Data/<Head>_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv`.
  - k = 1…100 for TST, Artistoo and Morpheus; 0…99 for the others; `%03d` padding for Artistoo and CC3D.
  - Columns are taken by position: x, y, r, f, a. For Morpheus they are tab-separated columns 2–6. For TST, f and a are **swapped** after reading; in `TST_5T` column 3 has mean 0.85 (that is a) and column 4 has mean 0.03 (f).
  - Negative f and a are clamped to 0.
- **Pooling:** all 100 runs concatenated. Distances are measured from the pooled mean (x₀, y₀) of all centroids (C12).
- **Distance bins:** `np.linspace(0, 1.05·max d, n+1)`, labels `f'{int(lo)}-{int(hi)}'`. Committed n = 7; M's figure has n = 5 (C11).
  - The bin edges are computed per framework, in that framework's units. `TST_5T` is in **px** (max d = 159 px, so its bins would read 0–33…); `Morpheus_5T` is in R (max d = 40.1 R, so 0–8, 8–16, …).
  - M's single legend (0–7 … 31–39, i.e. 1.05·max d ≈ 39.5) therefore belongs to one framework in R with max d ≈ 37.6 R [unverified which].
- **Histograms:** value bins `np.arange(-0.01, 1.01, 0.01)` (width 0.01), `density=False` (raw cell counts), stacked by distance bin.
  - Column 1: PDF of f, log y.
  - Column 2: CDF of f, `cumulative=True`, linear y (M: up to 10 × 10⁴).
  - Column 3: PDF of a, linear y (M: × 10³, up to 6).
  - Column 4: CDF of a.
  - Colours: `viridis_r` for f and `inferno_r` for a, sampled at `linspace(0, 1, nbins)`. The inner bin is yellow / pale; the outer is dark purple / black.
- **Extras not in M:** `plot_mean_std = True` draws μ and μ ± σ lines (cell 5); M's figure has none, so off. Axis titles say "Surface Fraction (γ)" in the notebook vs "(f)" in M; use **M's** labels.
- **Potts:** one row in M's 4-column layout with n = 5 bins in R, measured from the initial cell centre. Optionally render the TST, Morpheus and Potts rows from their raw files with the same code path (§4.4).

### 3.5 Fig 6 and Table 1 pipeline (`G:results/time_to_10k.tex`)

- **Panel a** (`:51-64`): `semilogyaxis`, x = β ∈ [0, 1], y = time to 10⁴ cells in 5T ∈ [10¹, 10³], title "γ = 0". Dashed lines at 271.4, 135.7, 67.85, 27.14, 14.927, labelled 20×, 10×, 5×, 2× at pos 0.2 and 1.1× at pos 0.95.
- **Panel b** (`:66-97`): x = γ ∈ [0, 1], title "β = 0", the same dashed lines unlabelled, legend outside right.
- **Series** (line width 1 pt): TST `x=beta|gamma, y="Time to 10k (5T)"`; Artistoo the same; PolyHoop `y = t/5` from `polyhoop/monolayer/time_to_10k_{beta,gamma}.csv`; PhysiCell `x, y=time`; Chaste OS `y=time_to_10000_cells`; TinyDEM `y = t/5`.
  - The **PolyHoop and TinyDEM inputs are missing from G** (D6).
  - The Chaste curve uses colour `ChasteOSquad` but is labelled "Chaste (OS logarithmic)" and reads `Chaste_OS_Log` data (`:62,93`; D7).
  - CC3D and Morpheus are absent from Fig 6, although CC3D has a Table 1 row.
- **Table 1 inference** (Q6, from the data):
  - TST and Artistoo refine the parameter near each target with bisection-like extra samples (TST β 0.7037, 0.7053, 0.7108, 0.717; Artistoo γ 0.117273, 0.447433, 0.450193, 0.487088, 0.715045).
  - The reported threshold is the **sampled value whose time is nearest the target**, not an interpolation. TST β row = 0.7037 (14.74), 0.9361 (27.07), 0.9867 (67.54), 1.006 (133.52), 1.02 (275.21), each a CSV row.
  - One exception: Artistoo's β at 1.1× is 0.6868 (14.54 × 5T), although its sample 0.698182 (15.19) is nearer the target 14.927. The rule is not applied uniformly [unverified why].
  - TST uses single runs except γ = 0.5 and 0.94 (two each); Artistoo's β file has single runs, and its γ file repeats 5 runs at γ ∈ {0.08, 0.12, 0.16, 0.45} and 6 runs at γ ∈ {0.5, 0.55, 0.7, 0.75, 0.8}.
- **Lattice γ → 0⁺ jump:** the γ curve starts at 61–63 × 5T for any γ > 0 (TST γ = 10⁻⁴: 61.37; Artistoo γ = 0.0195: 63.09), because interior cells have f = 0. Hence "—" at 1.1× and 2× for the lattice rows.
- **Potts:** reproduce M's rule (refine, report the nearest sample) **and** report a monotone-interpolated value of the seed mean; the table uses the former.

### 3.6 Pipeline defects found (D#; Potts does not copy them, it records them)

- D1 `run_metrics.sh` header (7 names) vs the `metrics.cpp` output (8 values).
- D2 The `g` vs `i` column mismatch (C8).
- D3 The draft Fig 8 lattice r and a are in px (C10).
- D4 The Fig 8 data are **legacy** β = 0.8 runs with framework-specific cycle definitions (CC3D 310 MCS, Morpheus 97 MCS), not M's calibrated 775 MCS (Q7).
- D5 The notebook bins and origin differ from M (C11, C12).
- D6 Fig 6 PolyHoop and TinyDEM inputs are missing.
- D7 The Chaste colour/label mismatch in Fig 6.
- D8 The `TST_5T` 1000-cell files are in px with a swapped header.
- D9 Artistoo's `Time to 10k (MCS)` column is not MCS: 187 ↔ 13.79 × 5T; the ratio is 13.55–13.60 in every row, i.e. the Table 1 normaliser 13.57 [unverified meaning].
- D10 CC3D's committed 11+10 relaxation code places all 10 uncompressed cells on the right (`Relaxation11+10cells/Simulation/Relaxation.xml` regions x 0–55 and 55–155). Its data start at w₂₁ = 14.51 CD, which matches 5 + 5, so the data came from other code (Q19).
- D11 `metrics.cpp` output depends on the compiler's floating-point contraction (§3.2); the reference build is `-ffp-contract=off`.
- D12 The Graham comparator of `metrics.cpp:39-44` is not a strict weak ordering for points collinear with p₀: `orientation` evaluates a·(b−c) + … on absolute coordinates, so for exactly or nearly collinear points the sign is rounding noise and need not be antisymmetric (Artistoo `Type 1/Centroid_data.zip:centroids_neighbors_mcs_1656.csv`: orientation(p₀, a, b) = 0 but orientation(p₀, b, a) = 3.6·10⁻¹²). `std::sort` with such a comparator has unspecified results; libc++ happens to give the 74-vertex convex hull there, while a stable sort leaves interior points on the "convex" hull (85 vertices, w_rel 0.44 instead of 0.0155). **Potts:** the orientation sign is exact (metrics.cpp's value when its rounding bound decides the sign, exact rational arithmetic otherwise), ties on one ray from p₀ go nearer first, and collinear points are popped, so the convex hull is strictly convex and independent of the sort. On frame 1656 Potts gives 74 vertices and metrics.cpp's line (w_rel 0.0155179).
- D13 concaveman's R-tree search (`concaveman.h` `findCandidate`) prunes a node when `sqSegBoxDist` exceeds maxDist, but that box distance (Dan Sunday's `sqSegSegDist`, its parallel case `D == 0` and near-parallel rounding) overestimates for near-parallel or axis-aligned edges, so boxes holding valid candidates are skipped. The result depends on the tree's layout. TST `final_snapshot_data/TST_beta_1.006_gamma_0_103480MCS.csv` (as `x,y,g,n`): metrics.cpp gives a 384-vertex boundary and `10001,111.761,39220.2,867.369,1.36516,0.0321968,1.2355,0.0122149`; the same C++ with box pruning disabled gives 385 vertices, as Potts does: `10001,111.759,39217.9,868.164,1.34766,0.0321968,1.23667,0.0120586`. A 37-point jittered lattice (P6.15d `test/openvt_analysis.jl`) shows it at concavity 1.5: the C++ omits the point near (5, 1). **Potts:** examines every live candidate within maxDist (a uniform grid with a safety margin), nearest first, which is concaveman's definition without the pruning error.

## 4. Figures, tables and submission requirements (complete inventory)

User, 2026-10-05: "recreate every simulation specific figure, and required simulation
submission requirement". Every item in M that a participating framework contributes is
listed below. Each one is recreated for Potts in M's layout: panel letters, axes, units,
log scales, colour bins and reference lines. Schematic-only items are listed too, with what
Potts contributes to them.

### 4.0 Inventory

| # | M item | Kind | Runs / input | Potts deliverable |
|---|---|---|---|---|
| F1 | Fig 1 "Overview of participating frameworks": one 45 × 45 mm closeup per framework, a banner in the framework colour (`G:results/introduction.tex:50-92`) | simulation | the case (a) 10⁴-cell run | a "Potts.jl" panel and banner. Colour variable: §4.0.2 F1 |
| F2 | Fig 2 mechanical calibration on 1D chains, panels a–e (`G:results/relaxation.tex`) | simulation | §4.2 | panels b, d and e as overlays on the consortium curves, plus the spring–dashpot reference; the a and c schematics redrawn |
| F3 | Fig 3 "Comparing monolayer growth over time": N, r [R], area [R²] vs time [T] 0–10, log y. One thick blue **deterministic** run (X ≡ 2: synchronous doublings, so N steps at t = 1, 2, …), thin red **stochastic** runs, dashed bulk line | simulation | case (f) and case (b) series | three panels. No .tex source in G; the framework shown is unidentified (Q13) |
| F4 | Fig 4 free-surface-fraction illustration, lattice panel (`G:results/free_surface.tex`) | schematic | — | a Potts-rendered lattice cell with medium and cell pairs marked; a required unit test that G1 equals the drawn count |
| F5 | Fig 5 "100 runs of 1000 cells", 4 columns × framework rows (§3.4) | simulation | case (b) | one row |
| F6 | Fig 6 time to 10⁴ cells vs β (γ = 0) and vs γ (β = 0) (§3.5) | simulation | cases (c), (d) | a Potts curve in both panels |
| T1 | Table 1 inferred thresholds at 1.1, 2, 5, 10, 20× | derived | §3.5 | a Potts row, to TST's precision |
| F7 | Fig 7 "Monolayer of 10K cells: β = 0, varying γ thresholds": one row per framework (PhysiCell, PolyHoop, TST in the draft). Five panels at the γ of that framework's T1 row, labelled "γ = …, T = …" with T in cycles (TST "γ=0.12, T=68.34" = 52 965 MCS / 775) | simulation | 5 runs at the Potts T1 γ values | a five-panel Potts row (O5), plus videos (docs rule) |
| F8 | Fig 8 quantitative comparison, 7 panels (`G:results/metrics.tex`) | simulation | §4.0.2 F8 | all seven panels |
| A3 | DATA ANALYSIS Category 3 (M p.3): fractions of uninhibited, type-1, type-2 and doubly inhibited cells over time | derived | O1 `i` column, cases (a), (c), (d), (e) | four time series per case (i = 0…3 shares). No figure in M shows them (Fig 8f has g only) and `metrics.cpp` computes only g, so the metrics port adds them |
| S1 | Table S1 CPM parameters | table | — | Potts uses it unchanged; the docs list Potts-only settings (neighbourhoods, lattice, sweep) |
| S2–S4 | PolyHoop, PhysiCell, TinyDEM parameter tables | table | — | none (non-CPM); the Potts table follows S1's layout |
| S5 | Table S5 λ → T (MCS), MSE | derived from F2 | §4.2 | a Potts table with the same columns |
| §4.x | "Implementation in ⟨framework⟩" subsection | text | — | "Implementation in Potts.jl": the `@potts_model` listing, how a_i, f_i and n_i are computed, the division rule, a Table S-style parameter table |
| — | Code availability ("TODO" in M) | text | — | Potts.jl repo URL, commit, paths of the model, scripts and data |

### 4.0.1 Submission requirements (M §2.1 DATA COLLECTION, §2.3; G layout)

1. **Simulation output data:** the O1 files for every case below (M p.2), plus O2 for (b), O3 for (c, d), O4 for F2, O5 for F7.
   - Store under `docs/src/assets/openvt_monolayer/data/` as compressed archives, with a manifest listing case, seed, parameters, commit and the MCS ↔ T conversion.
   - **G layout for upload:** `implementations/Potts.jl/` (the model and scripts) and `results/Potts.jl/{Relaxation,Monolayer}/` (data), as README.md:8 prescribes. Upload needs write access (Q11).
2. **Cases:**
   - **(a)** uninhibited (β = γ = 0) to 10⁴ cells, ≥ 10 seeds (C4): F1, F8;
   - **(b)** 100 stochastic runs to 1000 cells, uninhibited: F3 red, F5;
   - **(c)** β sweep, γ = 0, and **(d)** γ sweep, β = 0, to 10⁴ cells: F6, T1, F7. Extend β to about 1.03 (TST samples up to 1.031);
   - **(e)** β = 0.8, γ = 0 to 10⁴ cells, ≥ 10 seeds: the case Fig 8's draft uses (`run_metrics.sh:26-29`; Q7). Also γ = 0.5, β = 0 per E;
   - **(f)** **deterministic** division (X ≡ 2), uninhibited, 100 runs to 1000 cells: F3 blue. Precedent: `G:results/{TST,polyhoop,tinydem}/…No_CI_deterministic|noCI/deterministic.zip`. TST deterministic run40 first shows 2, 4, 8 cells in the files at 780, 1560 and 2340 MCS (saves every 39 MCS, so each doubling falls in the preceding 39-MCS window; TST's α = 50/770 puts the target at 100 after 770 MCS).
3. **Calibration:** the F2 chain runs at λ = 1, 2, 3, 5 with O4 data, the T(λ) table and the MSE (Table S5 format).
4. **Units in every file:** lengths in R, time in cycles (775 MCS); the MCS stamp in the file name.
5. **Parameters:** Table S1, plus a Potts parameter table.
6. **Reproducibility:** scripts, seeds, and a provenance TOML (commit, Julia version, backend, wall time). One command regenerates each figure from stored data; another reruns the simulations.
7. **Not required (C5, C6):** sensitivity analysis (S-opt1) and literature comparisons (S-opt2).

**G conformance and the email split (D-215, conformance audit 2026-10-10; decided where M is silent).**
- **Tokens:** `Potts.jl` and `Potts.jl_checkerboard` (§1.3).
- **Measurement files** use the header `MCS,t,N,R,A,C,w,g`, with an upper-case `R`, because `metrics.tex` reads `y=R`.
- **Core zip (≤ 20 MB):** README, parameters, model source, O3, O4, O5, per-run measurements and neighbours, A3, `table_S5.csv`, **Table 1 as a CSV**, figure PNGs, provenance and EMAIL.md.
- **Bulk side:** the O1 zips and the O1 manifest, and the O2 zip.
- **README/EMAIL notes:**
  - G's `run_metrics.sh` loops `seq 0 10000`, so saves past index 10000 are truncated;
  - large zips may need LFS in G;
  - each Potts entry needs a one-line addition to G's hard-coded framework lists (`run_metrics.sh`, the notebook, `colors.tex`, the figure .tex files).

### 4.0.2 Figure recreation specs (from the .tex sources)

Colours (`G:results/colors.tex:2-16`), RGB:

| Group | Framework | RGB |
|---|---|---|
| lattice | CompuCell | 37,52,148 |
| lattice | Morpheus | 44,127,184 |
| lattice | TST | 65,182,196 |
| lattice | Artistoo | 161,218,180 |
| polygonal | ChasteVM | 0,0,0 |
| polygonal | ChasteVT | 96,96,96 |
| polygonal | PolyHoop | 192,192,192 |
| centre | PhysiCell | 189,0,38 |
| centre | ChasteOSlog | 240,59,32 |
| centre | ChasteOSquad | 253,141,60 |
| centre | TinyDEM | 254,204,92 |

**Potts.jl: proposal RGB 8,29,88** (the YlGnBu-9 darkest, in the lattice family; Q18). **Potts.jl (checkerboard): proposal RGB 0,109,44** (Q27, §1.3).
Shared style: sans-serif, `scale only axis`, grid very thin black!20, tick length 0.8 mm,
minor 0.5 mm, legend in "Lattice / Polygonal / Center(oid) models" groups. Recreate with
CairoMakie at the same mm sizes.

- **F1** (`introduction.tex`): a 5 × 2 grid of 45 mm panels, 4 mm apart, with a 5 mm banner 1 mm above each, white bold label (black for TinyDEM). Inputs: `<FW>/closeup.png`, `Morpheus/Fig1_Morpheus.png`, `Chaste_*/Chaste_*.png`, and `physicell/closeup_improved` (lower-case directory in the .tex, `PhysiCell/` in G, `:58`).
  - **Colour variable (Q10 partly resolved):** Morpheus = `Cause_of_Arrest` with green = 0 growing, light-blue = 1 β-arrested, yellow = 2 γ-arrested, red = 3 both (`…V11.xml:97-106,418-420`). The Morpheus panel's yellow/red/green shows a γ-inhibited run [unverified which γ].
  - Morpheus V11 also renders `cell.volume` from blue (20) to red (120), min 30 max 120 (`:62-69`). This is the only blue→red map in G; it supports "blue→red = cell area" for the other panels [unverified for CC3D, TST, Artistoo].
  - Potts default: cell area on blue (A = 20) → red (A = 120), a light-grey cell-boundary line, the top-right quadrant crop.
- **F2** (`relaxation.tex`): panels 45 × 45 mm, xs 18, ys 14, line width 0.8 pt.
  - **(b)** x [0, 5] "Time (T)", y [5, 10.25] "Tissue width w₁₁ (CD)". Light-grey lines at y = 9 and x = 1; a thick densely dotted line at y = 10. Inset [0.95, 1.05] × [8.95, 9.05], scale 0.5, ticks 0.05.
    - Series (`:87-122`): CC3D `Tissue_Width_11_Cells.csv` (x=Time, y=Tissue_Width(CD)); Morpheus `Morpheus_1D_Relaxation_J10_11_cells_N100stats.csv` (time.relative, mean); TST `11cells/width.csv` (Normalized time (T), Mean Tissue width (CD)); Artistoo `average_sim1_11_cells.csv` (space-separated: Normalized_Time, Mean_Width_cell_diameters); Chaste VM/VT/OS headerless (t, w); PolyHoop `y = w11/2`; PhysiCell (time, width); TinyDEM (space: t, w11); reference `relaxation_exact.csv` (t, w), thin densely dashed.
  - **(d)** x [0, 10], y [14, 20.3] "Total tissue width w₂₁ (CD)", a densely dotted line at 20. Inset [0, 0.6] × [14.4, 14.8], scale 0.4, without Chaste OS quad. Series: the `…11+10…`/`…tissue_N100stats`/`11+10cells/width.csv`/`average_sim2_21_cells.csv` files (`:170-192`).
  - **(e)** x [0, 10], y [5, 10.25] "Width of inner cells w₁₁ (CD)". Series: `Inner_Tissue_Width_11+10_Cells.csv`, `…core_N100stats`, `11+10cells/inner_width.csv` (Mean inner width (CD)), `average_sim2_11_center_cells.csv` (`:226-246`).
  - d and e have **no** reference curve.
  - Schematics (`:250-305`): circles r = 1.6 mm, compressed fill `ca` = (233,163,201), uncompressed `cb` = (161,215,106), arrow `cc` = (223,194,125).
  - Chaste_CPM data exist (`G:results/Chaste_CPM/*`, 10 runs) but were removed from the figure (commit 70ffa01; `:203` commented out).
  - **Potts:** add a "Potts.jl" entry in the Lattice block of the legend and in all insets.
- **F5:** §3.4.
- **F6/T1:** §3.5. Panels 55 × 45 mm, xs 10, line width 1 pt, `axis on top`. Potts goes in the "Lattice models" legend block after Artistoo.
- **F7:** each framework row is five square panels: a colony on a white background, cells coloured by `inhibited` (TST file column 4). The draft shows growing boundary cells blue and inhibited interior cells orange/brown [unverified mapping for the PhysiCell and PolyHoop rows]. The TST row draws a thin blue colony outline. Potts uses O5 and the same labels "γ=<value>, T=<t₁₀ₖ/775 to 2 dp>".
- **F8** (`metrics.tex`): panels 45 × 45 mm, xs 18, ys 14, line width 1 pt. Inputs: `postprocessing/measurements_<fw>.csv` and `neighbors_<fw>.csv` (`:55-63`).
  - **a** semilog N, x [0, 20], y [1, 10⁵]. Dashed 2^t; dotted (π/4)t².
  - **b** semilog r [R], y [1, 10³]. Dashed 2^{t/2}; dotted √(π/2)/2 · t.
  - **c** semilog A [R²], y [1, 10⁵]. Dashed π2^t; dotted (πt/2)²/2.
  - **d** C/C_circle = C/(2π√(A/π)), y [1, 2].
  - **e** w/r, y [0, 1], with the legend.
  - **f** log-log g, x [1, 20], y [0.1, 1], major grid. Dashed g = 1; dotted 2/t from t = 2.
  - **g** bar chart n, p (%), x [1.5, 9.5], y [0, 80], `ybar=0.5pt`, bar width 0.15, no outline.
  - Category banners rotate 90° on the left; the bulk/boundary legend sits in a hidden axis.
  - **Potts:** lengths in R (C10). Overlay the legacy consortium curves only after unit conversion, footnoted as legacy β = 0.8 data (D4).

### 4.2 Mechanical calibration on 1D cell chains (M §2.2, Fig 2, Table S5)

This is the consortium's first benchmark. Every framework calibrates its time unit with it
before any growth run. Potts must do the same, and the result **sets T in MCS for every
other figure**.

**Protocol as M states it (§2.2):** eleven compressed cells in a horizontal chain, allowed to
relax "however that was performed in each framework". T is the time for the two outer centres
to reach 90% of the fully relaxed distance, and the cycle is 5T. Motivated by Osborne 2024
(M ref [5]).

#### 4.2.1 What the CPM frameworks did (Q5 RESOLVED from G and TSTgh)

| Item | Morpheus (`G:implementations/Morpheus/Relaxation_11cells_Morpheus_V5.xml`, `…11+10…`) | CC3D (`G:implementations/CompuCell3D/Relaxation/Relaxation11cells-withReplicates.zip` etc.) | TST (`TSTgh:openvt/monolayer-11cells.par`, `…/model-monolayer-11cells.py`, `src/models/openvt-monolayer-11cells-tst.cpp`) | Artistoo (`G:implementations/Artistoo/relax.html`) |
|---|---|---|---|---|
| Lattice (11 / 21 chain) | 150 × 5 / 250 × 5, periodic x and y (`:22-30`) | 200 × 5 / 250 × 5, periodic y only (`Relaxation.xml:14-18`) | 150 × 7 / 250 × 7 = 5 rows plus 2 frozen border rows (σ = −1), periodic (`.par:15-22`; `monolayer-11cells.json`) | 150 × 5 / 250 × 5, torus x, non-torus y (`:92-94,141-143`) |
| Lateral confinement | none needed: periodic y, so each cell spans the strip | periodic y | frozen border rows (border J default 100, `parameters.hpp:114`) | lattice edge |
| Compressed cells | boxes 5 × 5 (CD/2 × 5), packed (`:88-94`) | 5 × 5 boxes from x = 0 (`Relaxation.xml:54-62`) | 5 × 5 squares, packed | 1-pixel seeds every 5 px (`:365-367`), grown during burn-in |
| Compression mechanism | A\* = 25 (= 5CD/2) for the burn-in, then 50 (`:11-14`) | A\* = 25, ×2 at MCS 500 (`RelaxationSteppables.py:21-30`) | `SetTargetAreas(target/2)` at i = 0, `target` at i = relaxation (`…11cells-tst.cpp:102-106`) | V = 25, then V = 50 after burn-in (`:98,123`) |
| Chain ends | free (medium gap in periodic x) | left end against the lattice edge x = 0 | free | free |
| 11+10 geometry | 5 uncompressed 10 × 5 cells each side, A\* = 50 throughout (`11+10…V5.xml`) | code: all 10 on the right (D10) | 5 + 5 (`J20_10-11+10cells.dat`; json) | 5 + 5 at 10-px spacing, V = 50 (`:383-390`) |
| Burn-in | 100 MCS (`:9`) | 500 MCS | 200 MCS (`.par:25`; `.py:72`) | 100 MCS (`:82`) |
| λ, J_cc/J_cm, T | repo XML: λ = 5, 20/20, 20 (`:7-8,70-73`). Fig 2 data "J10": J_cm = 10, T = 155 [λ unverified, likely 2] | λ = 5 (`RelaxationSteppables.py:23`), 20/20 (`Relaxation.xml:46-52`), T = 20 (`Relaxation.xml:16`) | **λ = 2, 20/10, 20** (`.par:2-8`; `J20_10.dat`) | λ = 5, 20/20, 20 (`:95-97`) |
| Neighbourhoods | lattice order 1, sampler order 2, ShapeSurface order 2 (`:27-29,74-85`) | Potts order 2, contact order 2 | Moore | Moore (`:99`) |
| Width observable | max over cells of (x_c − min x_c)/CD (`:43-52`); inner = x_c(id 16) − x_c(id 6) | (max − min xCOM)/10 px | (max − min com_x)/CD, CD = 10 px (`.py:70,84-85`) | Euclidean distance between centroids of cells 1 and 11 (or 12 and 21) |
| Sampling | every MCS | code: every 10 MCS (`Relaxation.py:16`); committed data: 11-chain every MCS (Δt = 1/84 T), 11+10 every 10 MCS (Δt = 10/90 T) | every MCS (step 1/155) | every MCS |
| Replicates | 10 (`*_stats.csv`, `Relaxation/README.md:4`); "N100" for the Fig 2 files | 10 (`ParameterScanSpecs.json`) | **100** (`.py:12`) | [unverified] |
| T used (data Δt) | 86 MCS (V5 `:15`, 10-run files); **155** (J10 11-chain), **154** (J10 21-chain) | **84** (11-chain), **90** (21-chain) | **155** (`.py:71`) | **155** |
| How T was set | the first MCS with width ≥ 9 (`Event`, `:53-59`), then hard-coded | hard-coded | hard-coded T = 155 = Table S5 λ = 2 | hard-coded |
| Mean w at t = 1 T | 8.999 (crossing at 0.9995 T) | crossing 1.0015 T | crossing 1.0023 T | 9.0042 |

Commit f11fffc (J. Osborne, 2025-12-01) reads "fitting all timescales to 90% at t=1". So
**T is the 90% crossing of the replicate-mean curve**, rounded to whole MCS. The Table S5
MSE is a goodness-of-fit reported afterwards; "optimization" there means choosing λ.

#### 4.2.2 Spring–dashpot reference (`G:results/relaxation_exact.m`, `relaxation_exact.csv`)

- N = 11 beads; initial positions x_i = 0.5·i CD, i = 0…10, so w(0) = 5; rest length 1 CD. That is `x = linspace(0,(N-1)/2,N)'` and `b = x - (1:N)'`, which works on displacements from the rest positions 1…N (`:24,43`).
- Overdamped linear springs: η ẋ_i = k(x_{i+1} − x_i − 1) − k(x_i − x_{i−1} − 1), with **both ends free**. Checked twice: an explicit-Euler run (v2), and (v3) the matrix exponential of the free-chain Laplacian in Julia with k/η re-found by bisection on w(1) = 9 (18.28166472147, 2·10⁻¹³ relative from the .m value). It matches all 51 CSV rows to 4.8·10⁻¹³; w(0.1) = 6.0789, w(0.5) = 7.9022, w(1) = 9.0000, w(2) = 9.7726, w(5) = 9.9973. With x₀ pinned (the schema's "removal of one of the two side constraints"), w(1) = 7.17.
- **k/η = 18.2816647214633 per T**, from `fzero(w(k/η, 1) − 9)` (`:4`).
- Output: t = 0:0.1:5 (51 points), columns `t,w` (`:6-16`).
- **There is no 11+10 reference** in G; Fig 2d and 2e have none.

#### 4.2.3 Potts protocol (P#) — as close as possible to the CPMs, M first

- **P1 Lattice.** 150 × 5 for the 11-chain and 250 × 5 for the 21-chain, **periodic in x and y**. That is Morpheus's setup; CC3D is periodic in y and TST periodic overall. A 5-row periodic strip makes each cell span the strip with no lateral medium, so the chain is exactly 1D.
  - Variant P1b, run only if V6–V8 fail: TST's frozen border rows (7 rows, the outer two frozen).
- **P2 Initial state.** 11 compressed cells as 5 × 5 squares packed edge to edge, centred in x. For the 21-chain add 5 cells of 10 × 5 on each side, flush. IDs left to right as in Morpheus: uncompressed 1–5, compressed 6–16, uncompressed 17–21.
- **P3 Parameters.** Table S1: J_cc = 20, J_cm = 10, T = 20, A\* = 50 (TST, Morpheus-J10). λ ∈ {1, 2, 3, 5} (Table S5). No growth, no division.
- **P4 Neighbourhood.** Moore(1) for both energy and proposals.
- **P5 Compression and release.** Compressed cells have A\* = 25 for a burn-in of **100 MCS** (Morpheus, Artistoo); uncompressed cells have A\* = 50 throughout. At the end of the burn-in set A\* := 50 for the compressed cells; that MCS is **t = 0**. Variant: a 200-MCS burn-in (TST) as a sensitivity check.
- **P6 Observable.**
  - w₁₁ = (max − min of the centroid x over the 11 cells) / CD, with **CD = 10 px** (C7).
  - In the 21-chain: w₂₁ over all 21 cells, and inner w₁₁ = (x_c(16) − x_c(6)) / CD.
  - Centroids unwrapped across the periodic x boundary. Recorded every MCS for 0–5T (11-chain) and 0–10T (21-chain), plus the burn-in at negative t (TST does this).
- **P7 Replicates.** 100 seeds (TST, Morpheus N100; ≥ the schema's 10).
- **P8 T(λ).** The first MCS at which the replicate-mean w₁₁ ≥ 9 CD, rounded to whole MCS (f11fffc). Also report the per-run crossing distribution (Morpheus `Event`).
- **P9 MSE.** The mean of (w_Potts(t/T) − w_exact(t))² over the 51 points of `relaxation_exact.csv`, Potts linearly interpolated. This is our reading of Table S5's MSE [unverified definition]. With it, the G curves give TST 1.26·10⁻³, Morpheus-J10 1.59·10⁻³, Artistoo 7.4·10⁻⁴ (all at T = 155) and CC3D (λ = 5, T = 84) 1.09·10⁻²; Table S5 has 2.66·10⁻³ at λ = 2 and 1.38·10⁻² at λ = 5.
- **P10 Predictions.** The 21-chain uses the T from P8 at the same λ, with no refit (M Fig 2d, e). TST and Artistoo do this (both 155); CC3D refit to 90 MCS and Morpheus used 154. Record ours.
- **P11 Reference.** Solve §4.2.2 with OrdinaryDiffEq: 11 beads, free ends, k/η = 18.2816647214633. Check it against `relaxation_exact.csv` to 1e-6 (unit test). A 21-bead reference is Potts-only and stays out of the M-layout figure.
- **P12 Use.** Growth runs use M's α (775 MCS per cycle). Report 5 × T_Potts(λ = 2). If T_Potts(2) ∉ 155 ± 15%, state that it rescales Potts' time axis relative to the others (V6).

### 4.3 Sweep design for F6 / T1 / F7

- β ∈ [0, 1.03] and γ ∈ [0, 0.95] (TST's ranges), dense where the curves turn up: β ≥ 0.9 and γ ≥ 0.4. Include γ = 10⁻⁴ to reproduce the lattice γ → 0⁺ jump (§3.5).
- In a CPM a = A/A\* can exceed 1 under tension, so β > 1 thresholds exist (Table 1: 1.006–1.024).
- Per point, ≥ 5 seeds in total, but sampled the TST/Artistoo way. Bracket each target, refine by bisection, repeat 6 runs at the final points (Artistoo), and report the nearest sample (§3.5).
- Runs past 20× (≈ 2.1·10⁵ MCS) are capped and reported as "> 20×". TST went to 4.6·10⁵ MCS at β = 1.031.

### 4.1 Pre-registered targets (agreement with the other CPM frameworks)

M has no ground truth beyond cross-framework agreement. The targets are the **lattice-model
spread** in M and in G's data, widened by a margin set before running. Tolerances are to be
confirmed at the V-target audit before the reproduction freezes.

| ID | Target | Lattice-model values (source) | Proposed pass band |
|---|---|---|---|
| V1 | uninhibited time to 10⁴ cells | 13.57 × 5T (Table 1); TST low-β plateau 13.61–13.86; Artistoo β ≤ 0.52: 13.65–14.04 (G csv) | ensemble mean within ±10% of 13.57 |
| V2 | β at 1.1× / 2× / 5× / 10× / 20× | 0.687–0.704 / 0.936–0.943 / 0.9867–0.9916 / 1.006–1.011 / 1.020–1.024 (Table 1) | spread ± 0.02, except ± 0.005 at 5× and above |
| V2b | β curve shape | TST: 20.40 at β = 0.9, 32.11 at 0.95, 105.8 at 1.0; Artistoo: 18.59 at 0.873, 25.59 at 0.933 (G csv) | within ±25% of the TST/Artistoo curve at matched β |
| V3 | γ at 5× / 10× / 20× (1.1× and 2× are "—") | 0.076–0.12 / 0.45–0.50 / 0.715–0.76 (Table 1) | spread ± 0.05 |
| V3b | γ → 0⁺ jump | the time at γ = 10⁻⁴ … 0.02 is 61.4–63.1 × 5T (TST, Artistoo), against 13.6 at γ = 0 | Potts at γ = 10⁻⁴ within 61–70; a negative control at γ = 0 gives ≈ 13.6 |
| V4 | Fig 5 shape | pooled over 100 runs (TST_5T, Morpheus_5T; G zips): ≈ 89% of cells at f = 0; nonzero f peaked at 0.25–0.35 with no cell above f = 0.56; a peaked at 0.85–0.90, range 0.42–1.09; mean a = 0.85–0.86, mean f ≈ 0.03 | the same; a negative control (γ > 0 shifts f mass) |
| V5 | Fig 8 uninhibited N(t) tracks the bulk law N ≈ 2^{t/T} early | Fig 8a (its draft curves are legacy β = 0.8 runs, D4); TST No_CI stochastic (uninhibited, Table S1): slope 1.013, offset 0.45 | **P6.15f audit:** V5.1 slope of the mean log₂ N on t = 4.5:1:8.5 cycles ∈ [0.9, 1.1]; V5.2 max |mean log₂ N − t| on t = 0.5:1:8.5 ≤ 1.0; cases (a) and (e); negative control γ = 1e-4 fails V5.1 |
| V6 | T(λ) for λ = 1, 2, 3, 5 | 290, 155, 110, 75 MCS (Table S5); **155 at λ = 2 confirmed** by TST, Artistoo and Morpheus-J10 data | ±15% each, monotone decreasing in λ |
| V7 | w₁₁(t) shape (2b) | MSE vs reference: Table S5 7.6·10⁻⁴ (λ = 1) … 1.4·10⁻² (λ = 5); G data at λ = 2: 7.4·10⁻⁴–1.6·10⁻³ (P9). w₁₁(0.5 T) = 7.83–7.87 and w₁₁(2 T) = 9.78–9.80 across TST, Morpheus-J10 and Artistoo (reference 7.90, 9.77) | MSE ≤ 3× Table S5 at the same λ; w₁₁(0.5T), w₁₁(2T) within ±0.1 CD of the lattice spread |
| V8 | (2d, e) with T from (b) | w₂₁ at 1/5/10 T: 15.90–16.25 / 19.20–19.57 / 19.90–19.96 CD; plateau (w₂₁ < w₂₁(0) + 0.05) ends at 0.15–0.22 T; inner w₁₁ at 1/5/10 T: 7.20–7.51 / 9.46–9.71 / 9.92–9.96 (CC3D, Morpheus-J10, TST, Artistoo; G csv) | within the lattice spread ± 0.15 CD; plateau end within 0.1–0.3 T |

### 4.4 Consortium data available for overlay (G at 54f375f; sizes as committed; never copied into the monorepo)

The figure scripts read these from a local clone whose path comes from an environment
variable (`OPENVT_MONOLAYER_REPO`). The docs ship only the rendered figures and the Potts data.

| Figure | Path (under `results/`) | Size | Format and units | Overlay use |
|---|---|---|---|---|
| F2b | `CompuCell3D/Relaxation/Tissue_Width_11_Cells.csv` | 214 KB | `MCS,Time,Replicate_0..9,Mean_Tissue_Width,Tissue_Width(CD)`, T = 84 | as in `relaxation.tex` |
| F2b | `Morpheus/Relaxation/Morpheus_1D_Relaxation_J10_11_cells_N100stats.csv` | 36 KB | `time.relative,mean,std`, T = 155 | as is |
| F2b | `TST/Relaxation/11cells/width.csv` | 2.5 MB | 100 replicate columns + mean + STD; t from −1.284 T | as is |
| F2b | `Artistoo/Relax/average_sim1_11_cells.csv` | 41 KB | tab: `Normalized_Time Mean_Width_cell_diameters` (the .tex says space) | as is |
| F2b | `relaxation_exact.csv` | 1 KB | `t,w` | reference + P11 test |
| F2d/e | `CompuCell3D/Relaxation/{Tissue,Inner_Tissue}_Width_11+10_Cells.csv`; `Morpheus/Relaxation/Morpheus_1D_Relaxation_J10_11plus10_cells_{tissue,core}_N100stats.csv`; `TST/Relaxation/11+10cells/{width,inner_width}.csv`; `Artistoo/Relax/average_sim2_{21_cells,11_center_cells}.csv` | 39–40 KB; 71–72 KB; 2.5 MB each; 40–42 KB | as above; CC3D T = 90, Morpheus T = 154 | as is |
| F2 (other) | `Chaste_*`, `polyhoop/Relaxation/*.csv` (w in R, ÷2), `PhysiCell/Relaxation/*.csv`, `tinydem/Relaxation/*.csv`; `Chaste_CPM/*` (not in the figure) | ≤ 54 KB each | — | the full M figure |
| F3 | `TST/TST_No_CI_{deterministic,stochastic}.zip` | 47.3 / 48.5 MB | 100 runs each, `runK/cell_data_no_inhibition_<MCS>.csv` every 39 MCS to ~1000 cells: `x_pos,y_pos,radius_i,a_i,f_i`, all lengths in **R** (centre ≈ 200 R on the 1601² lattice), header in the true order | compute N, r, A with the metrics port (already in R) |
| F3 | `polyhoop/noCI/{deterministic,stochastic}.zip`; `tinydem/noCI/…` | 49.7 / 73.7 MB; 61.6 / 91.5 MB | 100 runs, `dataNNNNNN.csv` / `particlesNNNNNN.csv` with `x,y,r,a,f` in R, plus `timeline.txt` (index, t in cycles) | same |
| F5 | `TST/TST_5T_MonolayerGrowth_1000_Data.zip` (+ `TST_1T_…`, `TST_MonolayerGrowth_1000_Data.zip`) | 1.47 MB (+1.45, 1.45) | 100 files, px, a/f swapped (D8) | TST row |
| F5 | `Morpheus/Monolayer/Morpheus_MonolayerGrowth_1000_Data_{1T,5T,10T}_major2.zip` | 2.40–2.42 MB each | 100 files, tab, `time cell.id x y cell.radius f_i a_i`, R | Morpheus row (absent from M's Fig 5) |
| F5 | CC3D 5T deterministic | 78.7 MB, **LFS object not fetched** | — | needs `git lfs pull` (git-lfs is not installed here) |
| F6 | `TST/TST_time_to_10k_vs_{beta,gamma}.csv`; `Artistoo/Monolayer/time_to_10k_vs_{beta,gamma}.csv`; `PhysiCell/Monolayer/{beta,gamma}_time_10K.csv`; `Chaste_OS_Log/Chaste_OS_{beta,gamma}_data.csv` | 0.8, 0.75; 0.6, 1.4; 2.3, 2.4; 20.7, 18.8 KB | §3.5 | all M curves except PolyHoop and TinyDEM (D6) |
| F7 | `TST/final_snapshot_data/TST_beta_<b>_gamma_<g>_<MCS>MCS.csv` (8 files) | ≈ 270 KB each | `x_pos,y_pos,radius_i,inhibited`, R; inhibited fraction 0.96–0.99 for the γ cases | TST row of F7 |
| F7 | `TST/TST_10k_snapshots.pdf`, `TST/phase_diagram_TST.pdf` | 9.8, 8.2 MB | rendered | visual reference |
| F8 | `postprocessing/measurements_{polyhoop,compucell3d,morpheus,physicell}.csv`, `neighbors_*.csv` | 2.5–17 KB; ≤ 0.2 KB | `t,N,R,A,C,w,g` (D1, D3, D4) | legacy overlay after ÷R_px |
| F8 | `Morpheus/Monolayer/Morpheus_beta0.8_gamma0.0_replicate1.zip` | 7.95 MB | 317 files every 5 MCS to 1580 MCS, `x,y,g,n` in R, T = 86 MCS, 2025-04-23 | a β = 0.8 overlay in R (rescale t by 86 → cycles) |
| F8 | `Morpheus/Legacy/Monolayer_26032025_T97MCS/*.zip` (5 zips) | 4.8–7.2 MB | px, `"cell.center.x","cell.center.y","g","n"`, T = 97 | the source of the draft Fig 8 Morpheus curve |
| F8/sweep | `Morpheus/Monolayer/Parameter_Plane_Centroid_Data/{Parameter_Plane_Morpheus_Centroids.zip, metrics.csv}` | 3.7 MB, 2.5 KB | 25 final 10k snapshots, β ∈ {0, .9, .95, .99, 1} × γ ∈ {0, .3, .4, .45, .5}, `"time","cell.id","x","y","g","n"`, R | **the metrics-port validation set** (§3.2) |
| F8/sweep | `Artistoo/Monolayer/5x5_allreplicates.csv`, `Type 1/*`; `PhysiCell/results_5x5.csv`, `PhysiCell/Monolayer/pc_run{1,2}.zip` | 11 KB; 0.5 MB; 1.2 KB; 10.2 / 16.8 MB | Artistoo legacy (px, A = 25); PhysiCell R | context only |
| F1 | `<FW>/closeup.png`, `Morpheus/Fig1_Morpheus.png`, `Chaste_*/*.png` | 3 KB–1.9 MB | rendered | the F1 composite with the Potts panel |

## 5. Differences between the shipped model and M (decide: replace the defaults, or add M as the default with the 2024 set kept as a documented variant)

| Item | Shipped (2024 Artistoo set = `G:implementations/Artistoo/monolayer.html`) | M (= TSTgh except C13, C16, the division axis and X truncation; §2.5) |
|---|---|---|
| J_cc / J_cm | 20 / 20 | 20 / 10 |
| λ | 20 | 2 |
| A\*(0) | 25 | 50 |
| growth | A₀ / τ = 0.298 px/MCS | α = 0.06452 px/MCS |
| division | deterministic at 2A₀ (the 2024 E rule; Artistoo html already draws X ~ N(2, 0.4)) | X_i ~ N(2, 0.4) per cell, drawn at birth |
| daughters' A\* | reset to A₀ | half the mother's A\* (`Split()`) |
| type 2 inhibition | absent | f_i ≥ γ |
| initial cell | 5 × 5 square | disc, area ≈ 50 |
| lattice | 400² closed (cannot hold 10⁴ cells) | unbounded, so ≥ 1400² closed plus the guard (G6); CPM precedent 1024²–1601² |

## 6. Gaps in Potts (G#)

- **G1** Per-cell medium-contact and total unlike-contact counts on Moore(1), giving f_i (= TST method 3). It could be a cell-scope fold over the boundary sites' contacts, or a built-in. (v2 cited a D-075 `count(... for _ in contacts)` fold; D-075 has no such item. Site-scope folds over a relation exist, `for n in rel(site)` (P6.0at fingerprint tests); a cell-scope incremental form is [unverified]. D-139's `Potts.boundary_lengths` is a whole-state, host-only analysis function, usable for checks but not for the per-MCS growth rule.) It must be exact and incremental, because every cell's growth rule reads it every MCS. The neighbour count n_i is needed for output only and can be computed at the save.
- **G2** A random draw at division per daughter (`X => 2 + 0.4 * randn()`, redrawn while ≤ 0) on the counter RNG, with a stable stream; also an initial X for the first cell. (v2 cited D-075 Q6, which is about `components` on the checkerboard.) Today `rand()` exists (uniform, counter-based, per MCS and per cell) in updates, equations, division conditions and rules (`src/vocabulary.jl:299-305`, `src/lower.jl:155`); there is no `randn`, and daughter state rules `x => value` apply one value to parent and daughter (`src/vocabulary.jl:710`) [unverified whether a `rand()` there draws per daughter]. A workaround in Morpheus' style (`…V11.xml:350-352`): set `X => Inf` at division and redraw in an `@after_mcs` rule while X is not finite or ≤ 0, using Box–Muller from two `rand()` draws [unverified]. A deterministic mode X ≡ 2 is needed for case (f).
- **G5** A disc layout of a given area. `VoronoiBall` no longer exists (replaced by core `Voronoi` with shapes, D-138). Candidates today: `Voronoi([Center()]; region = Circle(Point(c), r), kinds = [:cell])` (`src/layouts.jl:924-945`) [unverified that one generator paints the whole disc], `Eden(Center(); …)` (D-141, TST's `GrowInCells` analogue), or a hand-made disc.
- **G6** A domain guard: stop with an error, or flag, if any cell comes within k sites of the lattice edge.
- **G7** Termination on a condition (`ncells ≥ 10⁴`): exists. `DiscreteCallback`s are checked after every MCS and `SciMLBase.terminate!(::PottsIntegrator)` is implemented (`lib/CorePotts/src/problem.jl:240,321-333,601`). Only the condition and a test are needed.
- **G8** The analysis module:
  - a concaveman port, a byte-faithful port of `metrics.cpp` (§3.2), validated on the Morpheus parameter-plane set;
  - writers for O1–O6;
  - figure scripts in M's layout (CairoMakie) reading G files from `OPENVT_MONOLAYER_REPO` (§4.4).
- **G9** Throughput for F6: about 30 points × ≥ 5 seeds, with runs near 20× lasting ≈ 2 × 10⁵ MCS on about 1400², i.e. roughly 10⁷–10⁸ MCS·runs. Needs boundary-only proposals (R10 `BoundarySite`, not implemented yet: ROADMAP P6.4b), Metal ensembles and Float32. Measure first.
- **G10** The F2 calibration fixture (§4.2.3):
  - strip layouts of given widths on a 5-row periodic lattice. `Tiling` takes one cell size per layer (`Tiling(size; spacing, region, kinds)`, `src/layouts.jl:290`), so use one `Tiling` per region (5 × 5 compressed, 10 × 5 uncompressed) combined with `overlay(layers...)` (`:1542-1551`), or paint by hand;
  - a mid-run A\* switch for the compressed cells (a time-dependent parameter or a callback);
  - the unwrapped outer-centroid observable;
  - the spring–dashpot ODE;
  - the 90%-crossing and MSE fits.
- **G11** The F3/F5 1000-cell stop (`ncells ≥ 1000`) and a per-run O2 snapshot writer (r = √(A\*/π)/R).

## 7. Open questions for the authors (R. Vetter)

- **Q1 RESOLVED** (§2.1 A1): actual area ≥ X_i·A\*(0), X_i per cell (M §2.1; CC3D, Morpheus, Artistoo code).
- **Q2 RESOLVED** (C1): cycle = 5T = 775 MCS (TST README `:32`; `Time to 10k (5T)` = MCS/775; Fig 7 "T=" = MCS/775). Fig 6 is in 5T, Fig 7 in cycles, and draft Fig 8 in each framework's legacy cycle (D4). Still open: Fig 3's "[T]" (assumed cycles).
- **Q3 RESOLVED** (§2.4): distinct cells over the Moore(1) neighbours of boundary sites (TST; Morpheus order 2). CC3D (NeighborTracker) and Artistoo (von Neumann) differ.
- **Q4 RESOLVED:** there is no common cadence (CC3D 20 MCS, Morpheus 5, TST 39, Artistoo 84, PolyHoop 1/25 cycle). Adopt TST's **39 MCS** (≈ 1/20 cycle) plus the final step.
- **Q5 RESOLVED** (§4.2.1): target-area halving with free ends on a 5-px strip, CD = 10 px, T at the 90% crossing of the mean, 10–100 replicates. Still open: the Morpheus "J10" XML and its λ (Q12), and Artistoo's replicate count.
- **Q6 RESOLVED** in part (§3.5): refined sampling, nearest-sample threshold, mostly single runs. Open: the CC3D, PolyHoop and center-model procedures.
- **Q7 RESOLVED** for the draft: Fig 8 shows legacy β = 0.8, γ = 0 runs (`run_metrics.sh:26-29`). Open: which cases the final Fig 8 will use, and whether they will be recomputed at 775 MCS/cycle in R (D3, D4).
- **Q8** Fig 6 caption "10³ cells" vs axis "10⁴": open. The data are 10⁴ (`Time to 10k` columns), so the caption is a typo.
- **Q9 RESOLVED** in part: only TST implements Table S1 (λ = 2, J 20/10, A = 50; α = 50/770, C16). The Morpheus, CC3D and Artistoo growth files in G are pre-M (§2.5). Every Morpheus XML in G uses `ShapeSurface scaling="none"`, i.e. no J normalisation. Open: Table S1 for the uncommitted Morpheus, CC3D and Artistoo versions, and their neighbourhood orders.
- **Q10 PARTLY RESOLVED** (§4.0.2 F1, F7): the Morpheus map is `Cause_of_Arrest`; the F7 rows are framework rows coloured by inhibited/growing. Open: the blue→red variable in the other F1 panels (cell area per Morpheus V11 is the best guess), and the colour map of the PhysiCell and PolyHoop F7 rows.
- **Q11 PARTLY RESOLVED:** layout `implementations/<FW>/`, `results/<FW>/` (README.md:8); file-name precedents in §3.1. Open: write access, and whether raw O1 series or only derived files are wanted.
- **Q12** The Morpheus files behind the M data are not in G: the "J10, N100" relaxation (T = 155/154), the 1T/5T/10T "major2" 1000-cell runs, and the Table S1 growth XML. The same holds for the CC3D and Artistoo versions that produced the Table 1 rows.
- **Q13** Fig 3: which framework, and how many runs? Is "deterministic" X ≡ 2 (TST data say yes)? No script in G.
- **Q14** Fig 8: confirm that lengths will be in R and time in 775-MCS cycles for all frameworks (currently px and legacy cycles; D3, D4).
- **Q15** Fig 5: 5 bins (figure) vs 7 (notebook); distance from the initial cell's centre (text) vs the pooled centroid (code); which framework's legend is shown; and whether stochastic or deterministic 1000-cell data feed it. **Update 2026-10-09 (the 9 Oct draft, §1.2 R4):** M now shows one shared set of bins for all rows (0–18 … 74–93 "radii"). On those edges, measured in R from the lattice centre, our case (b) row puts 27/72/1/0 % in the first four bins, while M's TST row reads ≈ 5/20/50/25 %, and our TST-equivalent colonies reach only ≈ 42 R. So M's "radii" are probably not R (≈ R/2.2?), or not measured from our origin. Ask for the unit and origin together with Q26. **Cross-check (2026-10-09, G 14fa42c, read-only).** We binned G's TST 1000-cell data on M's shared edges four ways: **Decipher pass (2026-10-10; scratch report `decipher/REPORT.md`): PARTIAL.**
  - **Exact shares.** M Fig 5 is vector graphics, so the exact per-row bin shares were read from the PDF's final stacked-CDF bars. In % for bins 0–18/18–37/37–55/55–74/74–93:
    - TST 8.7/24.7/37.7/27.9/1.0 (the earlier "≈ 5/20/50/25" was a low-resolution misreading);
    - Artistoo 9.5/26.9/40.4/22.8/0.5;
    - CC3D 8.1/24.6/40.9/26.1/0.3;
    - Chaste VM 6.5/19.0/30.0/36.9/7.6;
    - Chaste VT 7.4/20.9/31.0/34.3/6.4;
    - PolyHoop 7.2/21.2/33.4/34.8/3.3;
    - PhysiCell 8.1/23.0/34.6/31.8/2.7;
    - Chaste OS 7.8/22.5/34.4/32.6/2.6;
    - TinyDEM 8.2/23.4/34.4/31.3/2.7.
  - **The unit.** Fitting every row against G's TST colony shape gives **1.84–2.23 axis units per R** (TST 1.91), with 0.6–2.2 pp rms error. So M's axis is ≈ distance in R × 2 for all rows. That rules out R itself and each framework's raw units.
  - **The edges.** They fit "0 to 1.05 × the pooled maximum over all frameworks, 5 equal bins" (88.57 ≈ 44 R).
  - **Why TST is not exact.** No G TST set (plain = 1T, or 5T) reproduces M's TST row exactly: every fixed choice is 2.5–5 pp off, and none puts 1 % of cells beyond 74.4. So M's TST row comes from data not in G.
  - **Still to ask:**
    - (a) Is the distance in units of R/2 (i.e. ×2)?
    - (b) Which TST data set feeds Fig 5?
    - (c) Are the edges 0 to 1.05 × the pooled maximum?
  - in R, from the lattice centre or the pooled mean (≈ 30/70/0/0/0 %);
  - in px, from the pooled mean (≈ 55 % lands beyond 93);
  - the notebook's method (per-file raw units, per-framework `linspace(0, 1.05·max, 8)`);
  - and px / 2.1–2.2 (≈ 8/26/40/25/0 %, the closest).

  **None reproduces M's TST row** (read at the time as ≈ 5/20/50/25 %; the exact PDF reading is 8.7/24.7/37.7/27.9/1.0, see the decipher pass below). The implied unit is ≈ 2.0–2.2 TST px ≈ 0.5 R, i.e. "radii" may be diameters or px/2. Morpheus_5T in its native R gives 29/70/1/0/0, like ours. G does not define the shared edges, and its notebook loads the plain TST set (identical to 1T, not 5T). **Ask:** (a) M Fig 5's distance unit (R, 2R, px or px/2) and origin; (b) which TST set feeds it (1T or 5T); (c) how the shared edges are chosen. **Potts meanwhile:** the shared-bin row is rendered in R, labelled provisional, with one sentence noting that M's axis appears to be ≈ 2× ours.
- **Q16** Artistoo `Time to 10k (MCS)` units (D9).
- **Q17** Is 13.57 × 5T pooled over frameworks or PhysiCell's γ = 0 value?
- **Q18** The colour for Potts.jl in `colors.tex` (proposal 8,29,88).
- **Q19** CC3D 11+10 geometry: the code puts 10 cells on one side, while the data match 5 + 5 (D10). **CLOSED 2026-10-10, not asked: maintainer ruling (D-213) "paper holds provenance over the tst implementation", and the standing paper-over-code rule. Potts follows M; this framework's departure is recorded, not queried.**
- **Q20** TST divides on target area (C13) and draws X untruncated: intended? **CLOSED 2026-10-10, not asked: maintainer ruling (D-213) "paper holds provenance over the tst implementation", and the standing paper-over-code rule. Potts follows M; this framework's departure is recorded, not queried.**
- **Q21** Morpheus `Stdev_X = 0.4^2` (C17): is σ = 0.16 intended? **CLOSED 2026-10-10, not asked: maintainer ruling (D-213) "paper holds provenance over the tst implementation", and the standing paper-over-code rule. Potts follows M; this framework's departure is recorded, not queried.**
- **Q22** `metrics.cpp` boundary (D12, D13): its Graham order is undefined for points collinear with p₀, and its R-tree search can miss candidates next to near-parallel edges, so a few frames depend on the standard library and the tree layout (Artistoo frame 1656 with a stable sort; TST β = 1.006 final snapshot). Would the consortium accept the corrected hull (exact orientation, unpruned candidate search) as the reference, or pin the build (libc++, `-ffp-contract=off`) as the definition?
- **Q23** Fig 5 / V4 (P6.15e): which TST implementation detail differs from Potts' Table S1 model? TST_5T alone, with the same pair-count f and σ_X = 0.4, passes every V4 row (mean nonzero f 0.288), while Potts' rim cells are shifted up (0.346; peak 0.425 against 0.295). Leading candidate: division on target area (C13, Q20). Also asked: the exact Moore-pair loop TST uses for f_i (spec §2.4 records a skipped offset only for n_i, which could not plausibly explain a 20 % shift), the timing of growth vs division within an MCS (§2.5), and any rule acting on very small cells.
- **Q24** Fig 5 / V4 (P6.15e): do the CPM implementations suppress or remove crushed cells (a connectivity check, a minimum volume, extrusion)? Potts shows rare squeezed young daughters at the 1000-cell stop (30 of 10⁵ cells with a < 0.42, A\* 23–43), where the pooled data have none.
- **Q25** (2026-10-09; proposal-law-clues.md §4) **RESOLVED 2026-10-10 by maintainer ruling, not asked: "paper holds provenance over the tst implementation. current division trigger is good." Potts keeps division at actual A ≥ X·A\*(0); the frameworks' departures are theirs.** (a) Which division trigger is normative: actual A ≥ X·A\*(0) (M p.2) or A ≥ µA_max (§4.1)? (b) Which TST build produced the beyond-10³ curves, given the released model exits at `max_cell_count = 1000`? (c) Are the frameworks' departures from Table S1 intended (CC3D λ = 10, A\* = 25, contact order 4; Morpheus/Artistoo J_cM = 20, λ = 20; TST integer ΔH)?
- **Q26** (2026-10-09, the 9 Oct draft; §1.2 R1/R2/R5, D-211/D-212) Figs 7/8: which quantity is the centre label of each colony, and with which concave-hull parameters? metrics.cpp's C/C_circle and C/(2πR) on G's own CC3D/TST colonies do not reproduce it (§1.2 R5 result). Please push the Fig 5/7/8 scripts to G. **Decipher pass (2026-10-10): PARTIAL.**
  - **Which data match.** The CC3D colonies in G are the figure's own: `Fig7_Snapshot_to_10k.zip` is the renamed Fig 8 zip, holding all 8 CC3D colonies. TST's `final_snapshot_data` colonies are not the figure's.
  - **What the label is.** It behaves as the roughness C/(2√(πA)) of the black concave hull drawn in each panel. That hull is much more concave than metrics.cpp's (concavity 1.5), notching into the second and third cell layer, which is why round colonies print ≈ 1.5.
    - Measured from the figure's images and corrected for line-width bias, it reproduces the 8 CC3D labels to within 0.14 (±0.1 typical), not exactly.
    - Concaveman would need a concavity of ≈ 1.11–1.25 varying per colony. No single setting fits within 0.005, and the roughness is very sensitive (1.4 → 1.9 between concavity 1.15 and 1.0).
  - **Ruled out:** concaveman over concavity 0.3–5 and length threshold 0–4, with variants; shapely/GEOS ratio 0–0.15; alpha shapes at 1/α = 1.5–10; and a 300+ formula search.
  - **Still to ask:** the hull library, its parameters and the script for the Fig 7/8 labels.
- **Q27** (2026-10-10, D-214) The colour for "Potts.jl (checkerboard)" in `colors.tex`: proposal 0,109,44 (§1.3). Also, does the consortium accept two entries from one framework (sequential CPU, checkerboard GPU), as Chaste OS has log/quad?

## Verification log (v3, 2026-10-05, coordinator's spec verifier)

Sources read: M (all 12 pages, text and rendered figures), G at 54f375f, TSTgh at 7ae1636,
the worktree code (`feat/p6-15a`). Scripts ran in scratch only; nothing from G or M entered git.

**Checked and confirmed.**
- §2.2: every Table S1 value and unit (M p.11); σ = 0.4 is from M p.2. Table S5 (M p.12): 290/155/110/75 MCS; MSE 7.570·10⁻⁴, 2.664·10⁻³, 4.433·10⁻³, 1.378·10⁻².
- Table 1 (M p.7) lattice rows → V2 and V3 ranges; 13.57 × 5T; Fig 6 caption "10³" (Q8); Fig 7 rows (PhysiCell, PolyHoop, TST) and labels; Fig 8 axes, panel ranges and legend.
- §4.2.2: k/η = 18.2816647214633 and w(0.1), w(1), w(5) re-derived in Julia against `relaxation_exact.csv` (51 rows to 4.8·10⁻¹³); pinned-end w(1) = 7.17.
- §4.2.1, V6–V8, P9: crossings (Morpheus 0.9995, CC3D 1.0015, TST 1.0023 T), Artistoo w(1) = 9.0042, MSEs (TST 1.26·10⁻³, Morpheus-J10 1.59·10⁻³, Artistoo 7.4·10⁻⁴, CC3D 1.09·10⁻²), w₁₁(0.5T), w₁₁(2T), every V8 number and the plateau ends, all recomputed from the G csv files; data Δt confirm T = 84/90 (CC3D), 155/154 (Morpheus-J10), 155 (TST, Artistoo).
- §3.2 pipeline line by line against `metrics.cpp` and `concaveman.h`; §3.3 `run_metrics.sh` and the dt table; §3.4 notebook cells 1, 3, 5; §3.5 `time_to_10k.tex` and the TST/Artistoo csv files (V1, V2b, V3b values; nearest-sample rule); §4.0.2 `colors.tex`, `introduction.tex`, `relaxation.tex`, `metrics.tex`.
- C1–C17 and §2.5 citations in `schema/README.md`, Morpheus V11/V5 XML, the CC3D zips, `monolayer.html`/`relax.html`, TST par/cpp/py files: lines exist and say what is claimed, except as listed below. §4.4 sizes and formats. The C12 centre scatter (TST_5T per-run centre SD 1.36/1.44 R). V4 pooled means.
- §5 against `lib/PottsModels/src/openvt.jl`.

**Changed.**
1. §2.5 CC3D parameter set: J is 20/**10** (`ContactInhibitionMonolayer.xml:48-49`), not 20/20; Connectivity penalty added. CC3D initial cell marked [unverified] (region 499–501, `Width` 5).
2. §3.2: the reference `metrics.cpp` build needs `-ffp-contract=off`; with it, clang and gcc reproduce the committed parameter-plane `metrics.csv` byte for byte; default contraction changes C up to 2× and w up to 10×. New D11. Note on the in-place sort.
3. §3.3: the committed `measurements_*.csv` come from 978e0bc's positional, w/B binary, not merely "pre-9501e3c"; the legacy Morpheus header is rejected by the current binary.
4. §3.5: Artistoo replicate sets corrected (5 runs at γ ∈ {0.08, 0.12, 0.16, 0.45}, 6 at {0.5, 0.55, 0.7, 0.75, 0.8}); the Artistoo β 1.1× exception to the nearest-sample rule; TST duplicates at γ = 0.5, 0.94. D9 ratio is the 13.57 normaliser.
5. V4 rewritten from the data: f ≤ 0.56, nonzero f peaked at 0.25–0.35, a peaked at 0.85–0.90 (v2's "bounded below ≈ 0.7, peaked near 0.35–0.4" was wrong).
6. §4.4 F3: the TST No_CI files are in R with a correct header (v2 said px).
7. §4.0: added A3 (M's Category 3 inhibition-type fractions, a DATA ANALYSIS item missing from v2) and S2–S4 (N/A). Case (f) doubling times reworded (files at 780/1560/2340 MCS bound the doublings).
8. §4.2.1: CC3D λ citation (`RelaxationSteppables.py:23`); CC3D sampling (code every 10 MCS, committed 11-chain data every MCS). §4.2.2: `.m` line numbers (`:24,43`).
9. C1: M's own §2.1 sentence T = A\*(0)/α recorded as a further self-contradiction. A1: M's subscript in A\*_i(0) recorded with the reading. C9: CC3D's inequalities. C12: page p.4.
10. §6: G1 and G2 no longer cite D-075 (it has neither item); G2 records what `rand()` gives today; G5 (`VoronoiBall` was removed, D-138; `Voronoi(Center…)`/`Eden` candidates); G7 verified as existing; G10 `Tiling` has no `widths` (use per-region layers + `overlay`); G9 `BoundarySite` is ROADMAP P6.4b.
11. §5 header and §4.4 heading level; F1 PhysiCell input path; PhysiCell zip path.

**Not verified** (left or marked [unverified]): E and C (§1; not opened in this pass); the PhysiCell 1/62 dt; Morpheus `rand_norm` semantics (C17); Morpheus-J10 λ; Artistoo relaxation replicate count and division orientation; which framework's legend M's Fig 5 shows; F1 colour maps other than Morpheus; Fig 3's framework; whether one `Voronoi` generator paints a full disc; per-daughter `rand()` in division state rules; the CC3D and TST initial-cell shapes.

**v3.1 (2026-10-05, P6.15d review).** D12 and D13 added (and Q22) from 54 real frames in G (25 Morpheus parameter-plane, 21 Artistoo Type 1, 8 TST final snapshots) run through `metrics.cpp -ffp-contract=off` and the Potts port: 53 identical after the D12 fix; the TST β = 1.006 frame differs by D13, where Potts equals the unpruned C++.

**v3.2 (2026-10-08, P6.15f V-target audit).** Checked against G at 54f375f on the PC clone,
with the frozen rules of `lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl`:
- V5 had no numeric band ("qualitative"). It is now V5.1/V5.2 (row above). Fig 8a's draft
  lattice curves are legacy β = 0.8 runs in legacy cycles (D4, Q7), not uninhibited ones; in
  their own cycles they pass both rows (CompuCell3D slope 1.000, offset 0.50; Morpheus 0.985,
  0.55). TST No_CI deterministic gives slope 1.000, offset 0.50; stochastic 1.013, 0.45.
- F3 has no V-target in this spec; P6.15f pre-registers F3.1–F3.5 against TST No_CI (the only
  Table S1 CPM data in G). TST deterministic: all 100 runs identical, N = 2^k exactly from MCS
  780·k (target-area division every 770 MCS, C13, C16), 1024 cells at MCS 7761 (t = 10.01).
  TST stochastic: 98 of 100 runs end on their last 39-MCS save below 1000 cells (N = 960–996;
  the build stops at N > 1000 between saves), so the time to 1000 cells is interpolated in
  log₂ N between saves (9.58–10.89, mean 10.24 cycles); synchrony at t = k + 0.5, k = 0:3:
  0.91, 0.62, 0.42, 0.17.
- Both TST zips carry a `note.txt`: "155 MCS = 1 T", the mechanical T. Fig 3's axis "[T]" (Q2)
  stays read as cycles (775 MCS): only then does the 0–10 axis span the runs to 1000 cells.
- F8.3/F8.4 references: mean neighbour number of `neighbors_{compucell3d,morpheus}.csv` 5.842,
  6.480; g at the first row with N ≥ 10⁴ of `measurements_*` 0.4987, 0.3498 (legacy).

**v3.3 (2026-10-08, P6.15g V-target audit).** Checked against G at 54f375f on the PC clone,
with the frozen rules of `lib/PottsModels/test/reproductions/15_openvt_sweeps.jl`
(`p615g_mrule`, `p615g_g_reference`; its G tier recomputes every constant, 13/13):
- **V1.** 13.57 is PhysiCell's γ = 0 entry, 13.5693 (`G:results/PhysiCell/Monolayer/gamma_time_10K.csv`
  row 2), as §2.3 suspected (Q17 stays open). TST has no run below β = 0.25: its β ≤ 0.2 and
  0.3 rows are `nan`, and so is γ = 0. Its β = 0.25–0.5 runs give 13.61–13.86, with a mean of
  13.77. Artistoo's β ≤ 0.52 runs give 13.65–14.04, with a mean of 13.856. Both lie in the
  ±10 % band [12.213, 14.927], whose upper edge is the 1.1× target. The band is kept as
  proposed. D-173's case (a), at 15.17 cycles, lies outside it. A failure is a D-154 deviation,
  and the band is not widened for it.
- **V2 / V3: the threshold rule.** M's rule (§3.5) is the sample nearest the target, and G
  has two forms of it.
  - TST's Table 1 row is the nearest *run*: β 0.7037, 0.9361, 0.9867, 1.006, 1.02 and
    γ 0.12, 0.5, 0.75. With repeated γ rows averaged, its 10× γ would be 0.5113 (138.64,
    against 132.14 for the mean of the two γ = 0.5 runs).
  - Artistoo's row is the nearest *point mean*: γ 0.07562, 0.450193 (printed 0.45),
    0.715045. Its nearest run at 20× is γ = 0.7 (272.27). The 1.1× β is the known exception:
    the rule gives 0.698182, Table 1 has 0.6868.
  - Every value under either form lies inside the V2/V3 bands. Potts uses the point mean,
    because its final points are replicated as Artistoo's are.
  - The Table 1 spread includes values from frameworks without sweep data in G: 0.943 at 2×,
    0.9916 at 5×, 1.011 at 10×, 1.024 at 20× and γ 0.76. They are taken from M as v3 verified
    them. G's lattice γ rows give "—" at 1.1× and 2× under both forms.
- **V2b.** The Artistoo abscissae are 0.872727 and 0.933368; "0.873" and "0.933" are rounded.
  The references are 18.59, 20.40 (TST 0.9), 25.59, 32.11 (TST 0.95) and 105.76 (TST 1.0;
  "105.8" is rounded). Potts samples at 0.8727 and 0.9334, on its 10⁻⁴ grid.
- **V3b.** TST gives 61.37, 61.59 and 62.38 at γ = 10⁻⁴, 0.001 and 0.01. Artistoo's first
  sample, γ = 0.0195, gives 63.09. Both confirm 61.4–63.1. The band [61, 70] and the γ = 0
  control are kept.
- **Grids (§4.3).** TST sampled β = 0–1.031 (41 rows, of which 9 are `nan`) and γ = 0–0.95
  (36 rows, γ = 0 `nan`). Artistoo sampled β = 0.087–1.036 and γ = 0.0195–0.998.
  - In TST every γ ≥ 0.75 run is past 20× (278.78 at 0.75), and so is β = 1.02 (275.21). The
    Potts γ grid therefore stops at 0.8, one point past the 20× bracket. Fig 6 marks the capped
    points "> 20×".
  - Dense where the curves turn up: 14 β points ≥ 0.9 and 9 γ points ≥ 0.4. γ = 10⁻⁴ is
    included.
- **Run counts.** TST used single runs, except two each at γ = 0.5 and 0.94. Artistoo's β
  file is single runs; its γ file repeats 5 runs at {0.08, 0.12, 0.16, 0.45} and 6 at
  {0.5, 0.55, 0.7, 0.75, 0.8}. Both confirm §3.5.
  - "Per point, ≥ 5 seeds" is read as applying to every *reported* point: V1 (10, from C4),
    V2b (5), V3b (5), and the two final bracket ends of each threshold (6, Artistoo).
  - The bracketing and bisection samples are single runs, as TST's are.
  - Bisection takes 2 steps on a 10⁻⁴ grid. That gives a spacing of at most 0.0125 at
    1.1×/2× β and in γ, and at most 0.004 at 5× and above in β. The bands are ±0.02 and ±0.05,
    and ±0.005 at 5× and above in β.
- **The 20× cap.** 20 × 13.57 = 271.4 cycles = 210 335 MCS, the "≈ 2.1·10⁵" of §4.3. TST's own
  20× β sample (1.02, 213 287 MCS) and its 20× γ sample (0.75, 216 055 MCS) lie above the cap.
  So, under the cap, a Potts 20× threshold can only be a sample at or below 271.4: the end of
  the bracket that is not capped (or lo, when both are capped). TST's raw samples under the
  cap would give β 1.01 at 20×, outside the band, because TST has no sample between 1.01 and
  1.02; they would give γ 0.7, inside it. The bisection is what resolves the 20× β: on a
  synthetic curve through TST's Table 1 samples, the protocol gives 1.0187.
- **Lattices.** In TST's final 10⁴-cell snapshots the furthest centroid lies 491 px from the
  colony centre at β = 1.02, and 602 px at γ = 0.75. Inhibited fractions are 0.961, 0.978 and
  0.990 at γ = 0.12, 0.5 and 0.75. Potts' colonies are larger: (a) is about 10 % wider, and
  its γ colonies are less compact. The β sweep therefore runs on 1400² and the γ sweep on 1800².
- **Fig 7.** "Five panels at the T1 γ" are read as γ = 0, γ = 10⁻⁴ (standing in for the
  lattice "—" at 1.1× and 2×) and the three T1 γ values [unverified against M's panel list].
  F7.1 pre-registers an inhibited fraction ≥ 0.90 at the three T1 γ values.
- **Throughput (G9).** Measured on the PC, one pinned thread, no recorder.
  - SequentialCPM(Moore(1)) costs 13.9 ns/site/MCS on an empty 1000² lattice and 15.3 on
    1400²; occupied sites add 40–90 ns each.
  - Time to 10⁴ cells on 1400²: case (a) 428 s (11 264 MCS; 38.0 ms/MCS, 19.4 ns/site/MCS);
    β = 0.8 486 s (12 682 MCS; 38.3 ms/MCS).
  - D-173's 12-thread FULL took 1600–1750 s per such run, a contention factor of about 4
    (including its recorder).
  - The frozen sweep is about 160 runs and 11 M MCS·runs: ≈ 125 core-hours single-threaded,
    and about 1.5–2 days of wall time on 12 PC threads. The critical path is three sequential
    near-20× stages, each about 10 h contended.
  - The medium term, 15 ns per site, is 60–80 % of the cost, so `BoundarySite` (P6.4b)
    would roughly halve it.
