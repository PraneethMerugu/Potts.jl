# Published-model specs: index, unified features, decisions

This directory holds one paper-grounded spec per published model. This README ties them
together:

- §1 lists the 12 models with their sources and reproducibility grade.
- §2 gives the unified feature list R0–R16 (feature roadmap review, D-051), with a crosswalk
  from the former G1–G21 and each spec's local ids, plus the answers to the roadmap questions.
- §3 is the feature × model matrix.
- §4 lists the per-model decisions (all approved by the maintainer on 2026-09-30).
- §5 lists questions for the authors, grouped by recipient.
- §6 gives the recommended build sequence against R0–R16.

Each published model ships a reproduction tutorial written to
[`TUTORIAL_TEMPLATE.md`](TUTORIAL_TEMPLATE.md).

**Conventions.**
- "(01 §7.9 D-12)" means spec `01_merks.md`, section 7.9, item D-12. Every factual
  statement about a model cites its spec. The specs cite the PDFs and code.
- Reference files live in `docs/references/`: the PDFs, `supplementary/` and `codebases/`
  (see `codebases/SOURCES.md`).
- Status evidence cites the design docs (AUTHORING, AUDIT, DECISIONS, ROADMAP) or code
  files. It was re-checked against the tree at `340a936` (R0 at `db7eea2`).
- Policy (D-029, D-048): validation is ensemble/statistical with pre-registered tolerances.
  There is no bitwise or trajectory parity with any author's code.

Items 2 and 3 of the original list are deferred; the user handles them. Item 11 is Jafari
Nivlouei et al. 2021 (11 §8). Andasari et al. 2012 is kept only as the G9 ODE-component
conformance test (11 §8); ODE components exist (D-038, §2.3).

---

## 1. The 12 models

**Grades.**
- **A**: code and parameters released.
- **B**: full parameters in the paper, no code.
- **C**: key parameters missing, so calibration is needed.

A split grade (for example "A / C") applies to two variants covered by one spec.

| # | Spec | Primary papers (`docs/references/`) | Code / supplementary on disk | Grade | Why | Validation-target strength |
|---|---|---|---|---|---|---|
| 1 | [01_merks.md](01_merks.md) | `01a_Merks2006_DevBiol_vasculogenesis-elongation.pdf`, `01b_Merks2008_PLoSCB_contact-inhibited-chemotaxis.pdf` | `codebases/01b_Merks2008_TissueSimulationToolkit-v0.1.3/` (TST 0.1.3 C++) and `supplementary/01b_Merks2008_DatasetS1_parameter-files/` (12 `.par` files) (01 §7) | **A** (2008) / **C** (2006) | 2008: Dataset S1 plus TST fix every parameter of the Figs 5–11 runs (01 §7.1). 2006: λ, A, λ_L, E₀, field BC and scheme are absent from the paper; the only source is 2008-release files "assumed for 2006", and L conflicts (01 §8 A-1, §7.9 D-12) | **Strong.** Digitised curves (lacunae, branch points, compactness vs χ, J, s, D, T) with n = 10–100 (01 §5 V-E2/E3, V-C3…V-C11). The Fig 5/12/13 analysis code is not released (01 §7.9 D-18) |
| 4 | [04_foam.md](04_foam.md) | `04b_Jiang1999_PRE_foam-rheology_published.pdf` (primary), `04a_…_arXiv.pdf` | none (04 §1) | **C** | J, Γ, T, β and γ₀ are stated, but the shear-term index structure is ambiguous and its γ₀ scale must be calibrated against Fig 3(c) (04 §7 A-1). The y-wall type and anneal protocol are also missing (A-2, A-8) | **Medium.** Every figure is a single run (Fig 3 averages 10 periods). Targets are ratios, shapes and regime boundaries (04 §5.2 V1–V20) |
| 5 | [05_bauer2009_ecm.md](05_bauer2009_ecm.md) | `05_Bauer2009_PLoSCB_ECM-topography-angiogenesis.pdf` | none; Figs S1/S2 not on disk (05 §2.6) | **C** | Pixel size, lattice and neighbourhood, recruitment trigger, phenotype assignment and PDE scheme are UNSPECIFIED (05 §3.3) | **Medium.** Speed/thickness vs ρ, alignment and cord counts; ≥ 10 replicates (05 §5 V1–V18). Internal speed inconsistency (05 §7.1 item 2) |
| 6 | [06_jiang2005_tumor.md](06_jiang2005_tumor.md) | `06_Jiang2005_BiophysJ_multiscale-avascular-tumor.pdf`; erratum `06b_Jiang2006_BiophysJ_erratum.html` (read; 06 §3.4) | none | **C** | T, Eq 4 α and θ, lattice size, neighbourhood and γ are missing, and the Rb → E2F polarity blocks implementation (06 §3.3, §7.1 item 2) | **Medium.** Single-run simulation curves against experimental points: growth, rim, phase fractions (06 §5 T1–T12) |
| 7 | [07_bauer2007_sprouting.md](07_bauer2007_sprouting.md) | `07_Bauer2007_BiophysJ_sprouting-angiogenesis.pdf` | none | **C** | Pixel size, tissue-cell layout, degradation rate and baseline proliferating cell are UNSPECIFIED (07 §3.3) | **Medium–strong.** Table 2 speeds and diameters with n = 12 (07 §5 W2–W3) |
| 8 | [08_fbca.md](08_fbca.md) | `08a_Graudenzi2020_JCellAutomata_FBCA.pdf`, `08b_Maspero2020_FundInform_FBCA-nutrient-diffusion.pdf` | `supplementary/08_DiFilippo2016_CompBiolChem_mmc1–4.xls` (HMR core and three tissue models, 08 §1); the ACRI 2018 base paper is not on disk (closed access) | **C** | 08b's parameters are "as in [18]" (unavailable). The averaging coefficient D, the starvation rule and the edge efflux are UNSPECIFIED (08 §3, §7) | **Medium.** 20-run distributions for 08a SC1/SC2; digitised 08b curves (08 §5) |
| 9 | [09_cell_sorting.md](09_cell_sorting.md) | `09a_GranerGlazier1992_PRL_cell-sorting.pdf`, `09b_Osborne2017_PLoSCB_comparing-individual-based-models.pdf`, `09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf` | `codebases/09b_Osborne2017_Chaste_CellBasedComparison2017/`, `codebases/09b_Chaste_release_2017.1_Potts/` (09 §1) | **A** (Osborne CP) / **B** (Graner–Glazier) | OS: paper Table 1–2 plus Chaste code (the core rules were read at 2026 develop and checked unchanged against the paper tag and `release_2017.1`) (09 §1). GG: energies, T, the time unit, the cell count (≈ 1000) and the relaxation recipe are stated (09a; PRE 09c §II D3). Lattice size, boundary conditions and the type fraction are not (09 §8.4) | **Strong.** OS Fig 3 curves with n = 10 across k_pert; GG: PRE Fig 13 fractions and two independent paper runs of the sorting set (PRL Fig 2, PRE Fig 13), single runs each (09 §8.5, §9) |
| 10 | [10_akeeb_invasion.md](10_akeeb_invasion.md) | `10_Akeeb2026_PLoSCB_tumor-invasion-fingering.pdf` | `codebases/10_Akeeb2026_Leader_Follower_Invasion_Model/` @ `0b9673f` with 13,310-run `Data/invasion_metrics.csv` (10 §1, §5.1) | **A** | CC3D XML and steppables plus the authors' full sweep output (10 §5.1) | **Strongest.** Per-point ensemble means ± SD from the authors' own data (10 §5.1–5.2) |
| 11 | [11_multiscale.md](11_multiscale.md) (item 11 = 11a) | `11a_JafariNivlouei2021_PLoSCB_multiscale-tumor-angiogenesis.pdf` (`11b_Andasari2012_…` for the ODE test only) | `supplementary/11a_JafariNivlouei2021_S1Data.xlsx` (plotted data only); no code (11 §1, §9) | **C** | χ values, hypoxia and necrosis rules, the nutrient unit conversion, the Wnt input and the PDE solver are UNSPECIFIED (11 §7 items 1–8) | **Strong data, weak provenance.** S1 Data backs 10 figures, but most series are single runs and several are internally inconsistent (11 §9.3) |
| 12 | [12_zajac_convergent_extension.md](12_zajac_convergent_extension.md) | `12a_Zajac2000_PRL_convergent-extension_arXiv.pdf` (analytic), `12b_Zajac2003_JTheorBiol_anisotropic-differential-adhesion.pdf` (CPM) | none; the 2002 thesis is unavailable (12 §1) | **C** | Almost every numeric value of the CPM is absent; only acceptance rates and anisotropy % are given (12 §3, §7 A-Z2) | **Weak.** One trajectory "chosen unscientifically" (12 §7 A-Z10). The analytic Eq. 7 is an exact unit test (12 §5 V-Z8) |
| 13 | [13_starruss_myxobacteria.md](13_starruss_myxobacteria.md) | `13_Starruss2007_JStatPhys_myxobacteria.pdf` | none (13 §1) | **B** | Table I gives every energy parameter. The lattice size, MCS definition, θ normalisation and run lengths are UNSPECIFIED (13 §3, §7 items 1, 5) | **Medium–strong.** Ψ̄(κ) at 3 densities, velocity and efficiency vs κ with n = 15 (13 §5 V4–V12) |
| 14 | [14_nucleus_migration.md](14_nucleus_migration.md) | `14a_Fortuna2020_BiophysJ_nucleus-migration.pdf` (base), `14b_Thomas2022_…_arXiv.pdf`, `14c_DalCastel2025_…_arXiv.pdf` | `codebases/14a_Fortuna2020_Crawling/` (SF1_Code), `codebases/14c_DalCastel2025_Single_Cell_Chemotaxis_2.3/`, `codebases/14c_DalCastel2025_CC3D-Chemotaxis-SuppMat/` (14 §1) | **A** | Both codes are released with Table 1/2 and SM tables. Provenance caveat: the 14a zip was repackaged in 2021 (14 §9 item 17). Document S1, `Instructions_To_Run.pdf`, the nanoHUB port and the CC3D solver source are now on disk (14 §1) | **Strong.** Table 2 Fürth fits, the regime map and the 14c-SM efficiency tables (14 §7) |

---

## 2. Unified feature list (R0–R16)

> **Source.** This list is R0–R16 from the architecture review
> [`../feature-roadmap-review.md`](../feature-roadmap-review.md) §3 (commits 91873f0,
> f53dc29), which replaced the earlier list G1–G21. The maintainer's answers are in
> DECISIONS D-051:
> - the guardrails and R0 are adopted now (item 1);
> - fractional MCS are allowed, as one sweep keyword that costs nothing when unused
>   (item 2, amends D-031);
> - exact Zajac is the reference (item 3);
> - coarse field grids will be built (item 4);
> - global connectivity is allowed on the checkerboard, and features must work on both
>   algorithms (item 5);
> - analysis lives in the docs unless a package has real merit (item 6).
>
> Every other R-row stays a proposal until its step is taken up (D-051 preamble). The specs
> still use G-ids, which §2.3 maps to R-ids. Review §7 questions 6–10 are answered (§2.5, D-065).

### 2.1 Rules for every feature

- **General and public.** Every feature lands as a general public primitive. It covers
  its mechanism family as CC3D, Morpheus, Artistoo, Chaste and TST implement it (review
  goals). No model gets a hook named after it (AUDIT P-15). This is enforced by guardrails
  (b) and (c) (review §6; D-051 item 1).
- **Composability checklist** (review §4):
  - no required companion feature;
  - no model-named context field;
  - works on square, hex and 3D lattices;
  - adds its reads to the footprint and claim set;
  - is filtered by kind in the model's expression, not in the engine.
- **Both algorithms.** Every feature works under the Sequential and the Checkerboard
  sweep. A feature that cannot needs an explicit exception in DECISIONS (D-051 item 5).
  For energies that read cells other than the copy's owners, Sequential is the reference,
  and a Checkerboard variant is validated statistically (§4.12, Y2; D-065 Q7).
- **SciML where it fits.** Delegate to SciML wherever a package or interface fits. Only
  the CPM sweep, the explicit-stencil `FieldStep` and the fused cell ODEs are ours
  (review §3, "Hand-rolled code").

Status legend:
- **EXISTS**: usable from the public `@potts_model` surface.
- **IN PROGRESS**: adopted and being implemented now.
- **PARTIAL**: part exists (named), and the rest is missing.
- **PLANNED**: specified in AUTHORING or DECISIONS but not implemented (AUDIT §6).
- **MISSING**: not specified anywhere before the review.

Algorithm column: "Both" means Sequential and Checkerboard, and the note says what the
Checkerboard needs. "n/a" means the feature runs outside the sweep.

### 2.2 The features

"Needed by" is taken from the review's per-model sketches (review §5). ● means required
for the default reproduction, ○ a variant, observable or diagnostic, and † an entry the
review's sketch omits that the spec needs (derived from the old G-matrix through §2.3).
Status was re-checked at `340a936`; the R0 row at `db7eea2`.

| R | Feature (as adopted) | Needed by | Status (evidence) | Sequential / Checkerboard | Absorbs |
|---|---|---|---|---|---|
| **R0** | **Hygiene.** Family-general replacements for the privileged paths (review §2):<br>• topology values `local_components(old; relation)` and `ring_cells`, with `connectivity(…)` kept as shorthand;<br>• `Chemotaxis(c; strength, response, when)`, which replaces `extension_only`;<br>• `neighborhood_mean(x; relation, fold)`, optionally wrapped by `ActivityMemory`, which replaces `act_mean`, `act_delta`, `ctx.act` and `geomean_shifted` (`act_*` move to the test ports).<br>Unknown DSL options throw. Generic CorePotts names get `public` declarations. Guardrails (a)–(e) go into the tests (review §6) | ● 01 (M3, M7), ● 10 (rename only, review §5). The guardrails cover all 12, since each model has a sibling test (e) | **DONE** (`db7eea2`, D-051 item 1; all suites pass). `rule = :merks`, `merks_connectivity` and `extension_only` are removed. Public surface: copy-scope built-ins `local_components`, `ring_arcs`, `ring_cells`; `@constraint connectivity(k)` (= `local_components <= 1`, CC3D/Morpheus) and `connectivity(k; rule = :arc_or_pair)` (the former ring rule); soft penalty `@drive copy => λ * (local_components > 1)`; unknown rules throw. `Chemotaxis(c; strength, response = identity \| saturating(s) \| saturating_linear(s), kinds, when)` with `when = old == 0` for extension-only. Act family: DSL folds `geomean`, `mean`, `log1p_geomean` (was `geomean_shifted`); CorePotts `neighborhood_mean(x, σ, ctx, site, owner; relation, fold = GeometricMean() \| ArithmeticMean() \| Log1pGeometricMean())`. Guardrails: ExplicitImports on PottsModels, bare `using Potts`, DSL surface snapshot (`lib/PottsModels/test/guardrails.jl`), per-model siblings (`lib/PottsModels/test/siblings.jl`), model/author-name scan of `src/`, `lib/CorePotts/src`, `lib/MakiePotts/src` (allowlist `test/privileged_allow.txt`) | Both (sibling tests, review §6 (e)) | AUDIT P-15; the renames in G3 and G4 |
| **R1** | **Copy-scope names.** `position`, `direction` (d = target − source) and `mcs`/`time` in drive and proposal scope, where `time` is SciMLBase `integ.t`. A `Metropolis(tie)` policy for ΔH = 0 at T = 0 | ● 04 (shear on `direction`/`time`; F2 tie = accept), ●† 13 (copy direction d). Elsewhere sugar only | **PARTIAL.**<br>Exists: `Metropolis(; temperature, offset)`, `Barker`, and the T ≤ 0 tie at ½ (AUTHORING §12.1); `position` is Cartesian (D-043); time works as a model variable updated `@before_mcs` (review §1 finding 1).<br>Missing: `direction` is planned (AUTHORING §12.2); there is no tie option | Both (copy-local reads) | G3, G8a |
| **R2** | **Layout library with an overlay algebra:** `Tiling`, `Scatter`, `Eden` (+ splits), `BrickWall`, `Chains`, `Spheres`, `Fibres`, `InsertUntil`, `Frame`, `Plane`. The output is an SII operating point. A frame or wall is a frozen kind placed by a layout. A per-cell pin is a cell variable plus `@constraint` (review §1) | ● 01, 04, 05, 07, 08, 09, 10, 11, 12, 13, 14; ○ 06 (one central cell, 06 §6 G13) | **MISSING** as a library: the `UniformSeeds`… layouts do not exist (AUDIT §6). Per-model state functions exist (`merks_state`, `akeeb_state`, `graner_glazier_state`). Frozen kinds exist (`@kinds x[frozen]`, AUTHORING §2) | n/a (host-side initial state) | G13, G16 |
| **R3** | **Discrete rules and draws:** `@retire`, `@transition`, `rand(dist)`, `hazard(k)` (a per-MCS Bernoulli), `@discrete_events` (lowered to SciMLBase `DiscreteCallback` via MTK `SymbolicDiscreteCallback`), `@terminate`. Population gates are folds in a rule's `when`. Per-MCS Bernoulli gates stay `rand() < p` | ● 04 (`@terminate`), 05, 06, 08, 11; ●† 07 (`@transition`); ○ 09 (Binomial labels already work as cell updates, review §1); 11b | **PARTIAL.** CorePotts lifecycle has divide, remove and transition (`lib/CorePotts/src/lifecycle.jl:13–16`). The symbolic layer exposes only `@divide` (`src/macro.jl:396`). Uniform `rand()` exists (AUTHORING §12.6). SciML callbacks, `setp` and `remake` exist (AUTHORING §8). `@terminate` is planned (§12.7) | Both (rules run at the MCS boundary) | G1a, G1c, G14 |
| **R4** | **Topology values.** Local rules dispatched on the geometry (square, hex, 3D), plus `components(old; scope = Global())`, which runs a BFS only when the local test fails. Hard rule: `@constraint … <= 1`. Soft rule: `@drive copy => E₀*(… > 1)` (review §2) | ● 01 (E₀ drive, M3), 05 (Global, B5), 11 (N5); ○ 05/11 (local variant), 07, 08, 13, 14 (diagnostic) | **PARTIAL.** Only the hard veto exists (`connectivity(kinds; rule)`); soft and global rules cannot be written (review §2). Guardrail (e)'s soft-connectivity sibling is R4's acceptance test | Both. `Global()` is allowed on the checkerboard (D-051 item 5): the BFS reads only the claimed cell's sites, at O(V) cost and with GPU divergence | G4 |
| **R5** | **Field boundaries, placement and grids.**<br>• `@boundary` per face (Dirichlet, periodic, absorbing, flux, moving kind-defined Dirichlet) as a masked clamp applied every substep;<br>• field phase placement and an explicit phase order;<br>• fields on their own grid, coarser than the lattice, with restriction and prolongation (D-051 item 4).<br>Discrete field operators and indicator fields are site updates with gathers (conformance tests) | ● 01 (absorbing frame each substep, PDE before the sweep), 05, 06 (moving Dirichlet, coarse grid), 07, 08 (flux BC), 11 (EC clamp), ●† 14 (predicate-sourced PDE); ○ 14c (indicator field) | **PARTIAL.** Explicit Euler with stable substeps exists (AUTHORING §6). CorePotts per-face Dirichlet exists (`lib/CorePotts/src/fields.jl:14–39`) but is not exposed (AUDIT A-04). `@boundary` is planned (AUTHORING §12.5). `@before_mcs`/`@after_mcs` dependency ordering exists (D-042). Coarse grids are MISSING (to build, D-051 item 4) | Both (field phases run between sweeps) | G5a, G15a, G18 |
| **R6** | **Cell references:** `sibling`, `root`, `partner`, `x[ref]`, and `members(c, kind)` folds. Liveness is standard (D-066, amending D-035/D-037): alive ⇔ owns a site (`alive(c) ≡ volume[c] > 0`); a created or divided cell is born only by receiving a site (X2), with no `retain_empty` and no empty-but-alive state; slots are reused, and a monotone `birth` serial is the user-visible id; references to dead cells read as ref = 0 and are reset at boundaries. Claim sets widen automatically to referenced cells | ● 13 (related centroids in drives; `no_extinction` on segments), 14 (sibling, cluster fold, members created on demand by `@convert`); ○ 05/07 (collectives; optional `no_extinction(matrix, fluid)`) | **PARTIAL.** Clusters with `clusters(k)` energies and `cluster_volume`/`cluster_surface` exist (D-036). References are MISSING (AUTHORING §12.3). Liveness is volume > 0 today (D-035), which D-066 keeps; `birth` ids, reference reset and the dead-partner link skip are to build (D-066 items 3, 5) | Both. The Checkerboard adds referenced cells to the claim set (review §4), and Sequential is the reference; the Checkerboard is validated statistically, not required to be exact (D-065 Q7) | G10 |
| **R7** | **Moment-derived builtins with exact after-values:** centroid, covariance, minor length, orientation, eccentricity. `centroid` becomes allowed in energies, and clusters get moments | ● 12 (tensor ΔH), 13 (unwrapped centroids); ○ 12 lagged variant (cell scope only) | **PARTIAL.** `major_length` has an exact ΔH (`src/compile.jl:47`, `CorePotts.major_length_after`, D-049 F-3). `surface` exists. `centroid` is barred from energies (AUTHORING §12.2) | Both. Cluster moments need `cluster_claims` on the Checkerboard (D-036). Float32 on Metal must agree with Float64 statistically (D-065 Q10) | G2 |
| **R8** | **Site-ownership events:** `@create`, `@convert` (any `from`/`to`, predicate, probability, budget, field writes), `@retire … sites => ref`, and scatter-add rules. One shared host routine applies each ownership delta to trackers, links, cluster roots, integrals and mobility, with a fixed priority remove > convert > transition > divide > create. The routine fires the site hooks on every ownership change | ● 05 (`@create`, convert), 06 (retire into the necrotic cell), 07 (convert), 14 (`@convert`); ○ 08 (08b) | **MISSING.** CorePotts has no create event (`lifecycle.jl:13–16`; review §1 finding 3). There is no `@convert` | Both (host routine at the MCS boundary). Sequential conversion is serial by design, off the hot path (14 §2.9.5) | G1b, G7, G17 |
| **R9** | **Relationship 3-body terms and several relationships.** Angle terms, with chain order as a mutable cell index. Several named relationships per model, each with its own link store and claim set | ● 13 | **PARTIAL.** `@relationship`, `@link`/`@unlink` and `edges(name) => f(distance)` exist (M2.9; AUTHORING §7). There is one relationship per model (`compile.jl:118`). 3-body terms are MISSING | Both, with claims for related members. Sequential is the reference (Y2) | G11 |
| **R10** | **`ProposalLaw` dispatch:** `UniformNeighbor`, `UnlikeNeighbor`, `BoundarySite`. Attempts are counted over all sites. Fractional attempts per MCS are **one sweep keyword**, and the whole-MCS path compiles to exactly today's loops (D-051 item 2, amends D-031) | ● 04, 07 (unlike-neighbour), 08 (attempts), 12 (boundary-only), 06 (¼-MCS sweeps) | **PARTIAL.** Declared proposal relations exist (`@sweep Metropolis(; proposal = …)`, D-049 F-1). The laws and fractional attempts are MISSING. An opt-in `MetropolisHastings()` acceptance for non-symmetric laws is built with R10 (D-052) | Both. The Checkerboard draws among unlike neighbours locally and counts all-site attempts (review §4) | G8b, G15 (fractional) |
| **R11** | **Contacts.** (a) `neighbors(c)` and `contact(c, n)` at MCS cadence. (b) Per-copy pair trackers with an `interfaces => E(a, b)` energy over both cells' tensors and interface aggregates. The exact per-copy form is the Zajac reference (D-051 item 3) | (a) ●† 11 (contact fractions), ○ 10, 12, 13. (b) ● 12 | (a) **PLANNED** (AUTHORING §12.3). The host-side contact graph exists (`ContactPhase`, `lib/CorePotts/src/spatial.jl`, M2.7). (b) **MISSING** | (a) Both (MCS cadence). (b) Sequential in practice (review question 4). The Checkerboard needs neighbour-pair claims, or an explicit exception in DECISIONS (D-051 item 5) | G21a, G21b |
| **R12** | **`Pre(x, k)` on cell variables.** Ring buffers grow with capacity and follow division | ○ 14c (100-MCS window), 12 lagged variant, 11b | **PARTIAL.** `Pre(x, k)` exists for site, field and model quantities (`src/vocabulary.jl:224–233`). Cell-variable lags are rejected (`src/lower.jl:65`) | Both | G20 |
| **R13** | **Integer-indexed tables and Boolean networks** as MTK clocked/discrete components (review §4). Catalyst, and JumpProcesses inside components, via extensions | ● 06 (Boolean with stochastic gating); ●† 11 (Fig 3 lookup table, N4) | **PLANNED.** Boolean networks are in AUTHORING §12.6. They are MTK discrete-time (clocked, `Shift`) components with no Potts truth-table helper (D-065 Q9) | Both (component updates at the MCS boundary) | G9b |
| **R14** | **Implicit and steady fields** (extension): OrdinaryDiffEq IMEX/implicit with LinearSolve; SteadyStateDiffEq / NonlinearSolve. A solver per field or equation block | ● 06 (implicit 45-min transient, J7), 07 (steady-state init, B7); ○ 05 (steady init), 06 (quasi-steady variant) | **PLANNED.** Quasi-steady `0 ~ …` is planned (AUTHORING §12.5; AUDIT §6). There is one global `field_solver` (review §4 [e]) | Both (field phases run between sweeps) | G5b |
| **R15** | **Per-cell host operators:** `CellOperator(f!; inputs, outputs, order, every)`, FBA (COBREXA/JuMP, HiGHS, warm start, pFBA), rim reductions, and `uptake`/`secrete` sugar. Uptake site sets are a site predicate relative to the cell | ● 05, 06, 07, 11 (uptake), 08 (FBA with sequential write-back, X2); ○ 14c (site-set mean/std) | **PLANNED.**<br>Planned: `secrete`/`uptake` (AUTHORING §12.5); FBA via COBREXA as an extension (D-030).<br>Exists: masked source terms in `D(c) ~ …` (`lib/PottsModels/src/merks.jl`); `integral(x)` with a mask (AUTHORING §12.3). The uptake/secretion split runs once per MCS (D-065 Q8) | Both. The operator runs on the host once per MCS and copies only its declared inputs and outputs (review §4) | G6, G9c, G19 |
| **R16** | **Analysis:** observables, fits, graph components, annealed-copy measurement. By D-051 item 6 it is clean, teachable Julia in the docs and tutorials, using MTK `@observed` through SII where that performs. A `lib/PottsAnalysis` package only if it has real merit | ● 01, 04, 05, 08, 09, 10, 11, 12, 13, 14; ○ 06, 07 | **PARTIAL (minimal).** `@observed`, `integral(x)` and SII indexing exist (AUTHORING §12.3). The Akeeb metrics exist as a test file (`lib/PottsModels/test/akeeb_metrics.jl`) | n/a (analysis of solutions) | G12 |

Always available, with no R-row: MTK ODE components per cell (D-038, the G9 ODE part), hex 2D
lattices (`Hexagonal()`, M2.1b), 3D lattices, and kind-restricted copy sources
(`@constraint kind[new] == k`, review §1).

### 2.3 Crosswalk: G-ids → R-ids

The specs cite G-ids: G1–G13 are shared, and each spec's own G14+ ids are listed in the
second table. G-ids resolve through these tables. "exists" means the review found the item
already expressible, so it needs tests and sugar rather than a feature (review §1 finding 1).

**Unified G1–G21 → R.**

| G | Former feature | R-id(s) | Notes |
|---|---|---|---|
| G1 | Lifecycle rules plus draws; population gates | R3 (G1a `@transition`/`@retire`/draws, G1c population gates), R8 (G1b `@create`) | README correction: CorePotts has no create event (review §1 finding 3). Binomial labels and staged temperature already work (review §1) |
| G2 | Shape descriptors in energies | R7 | `major_length` already has an exact ΔH (D-049 F-3). VN perimeter (09 OS) uses `surface` |
| G3 | Contact/copy-scope quantities | R1 (position, direction, time); R0 (`Chemotaxis(response, when)`) | χ(c,c)/χ(c,M) is `ifelse(old == 0 \|\| new == 0, χcM, χcc)` (exists). Lagged vector cell variables → R12 |
| G4 | Generalised connectivity | R0 (renames, local topology values), R4 (soft, `Global()`, geometry dispatch) | Soft E₀ is an additive drive over a connectivity value, not a new constraint kind (review §1) |
| G5 | Fields: BCs, steady, implicit, coarse grid | R5 (G5a BCs, coarse grids), R14 (G5b implicit and steady) | Coarse grids to be built (D-051 item 4). Static analytic fields are site updates (exists) |
| G6 | Conservative secrete/uptake | R15 | Masked source terms work today |
| G7 | Site conversion `@convert` | R8 | Must take any `from`/`to`, a predicate, a probability, a budget and field writes (review §4) |
| G8 | Proposal and acceptance law | R1 (G8a time, tie policy), R10 (G8b laws, attempts) | Kind-restricted sources and the threshold offset exist (review §1) |
| G9 | Per-cell components | exists (ODE, D-038), R13 (G9b tables, Boolean), R15 (G9c FBA) | The 10 clock state is cell variables (exists) |
| G10 | Cluster scope | R6 (references, liveness per D-066, claim widening), R7 (cluster moments), R11a (`neighbors`) | Clusters exist (D-036). Contact-graph BFS for analysis → R16 |
| G11 | Ordered relationships, 3-body energies | R9 | Narrowed to 3-body terms plus several relationships (review §3) |
| G12 | Observables library | R16 | Docs/tutorials first (D-051 item 6) |
| G13 | Initial layout generators | R2 | – |
| G14 | Staged protocols, timed interventions | R3 (`@discrete_events`, `@terminate`) | Callbacks, `setp` and `remake` exist (AUTHORING §8) |
| G15 | Step schedule, operator splitting, fractional sweeps | R5 (G15a phase placement and order), R10 (fractional attempts) | Fractional MCS: one sweep keyword, zero-cost when unused (D-051 item 2, amends D-031) |
| G16 | Frozen/pinned sites and walls | R2 (`Frame`, `Plane` place frozen kinds) | Per-cell pin = cell variable + `@constraint` (exists) |
| G17 | Absorb-retire into a collective | R8 (`@retire … sites => ref`) | – |
| G18 | Discrete field operators, indicator fields | R5 (conformance tests) | Site updates with gathers (exists, D-042) |
| G19 | Filtered site-set reductions | R15 (rim reductions); conformance test | `integral` with a mask (exists) |
| G20 | Windowed/lagged cell histories | R12 | Needed only by 14c's multi-cell variant, the 12 lagged variant, and 11b |
| G21 | Cell-pair interface quantities | R11 (G21a `neighbors`/`contact`, G21b pair trackers) | Zajac exact = R11b (D-051 item 3) |

**Spec-local G14+ ids.** The unified G-id is the id §2 used before the review.

| Spec | Local id | Local description | Unified G | R-id |
|---|---|---|---|---|
| 01 | G14 | saturating/receptor-occupancy chemotaxis law (01 §6) | G3 | R0 (`Chemotaxis(response = saturating(s))`, review §2) |
| 01 | G15 | frozen border sites with their own J (01 §6) | G16 | R2 (`Frame`) |
| 04 | G16 | explicit time in energy terms (04 §6) | G8 | R1 |
| 04 | G17 | multi-phase protocol: anneal → relax → coarsen → relax (04 §6) | G14 | R3 |
| 04 | G18 | row-restricted energy terms (04 §6) | G3 | R1 (`position`) |
| 05 | G15 | coupled operator-split schedule (05 §6) | G15 | R5 |
| 06 | G14 | absorb/merge-retire into a collective cell (06 §6) | G17 | R8 |
| 06 | G15 | operator split ¼ MCS ↔ 45 min PDE (06 §6) | G15 | R10 (fractional), R5 (order), R14 (implicit) |
| 07 | G15 | operator split 1 MCS ↔ 1 h PDE (07 §6) | G15 | R5 |
| 08 | G14 | user-defined discrete field operator (08 §6) | G18 | R5 (conformance) |
| 08 | G15 | explicit per-MCS step schedule (08 §6) | G15 | R5 (explicit phase order) |
| 09 | G14 | timed parameter change / staged protocol (09 §6) | G14 | R3 |
| 10 | G14 | "repeat until ratio" at init (10 §6) | G13 | R2 (`InsertUntil`) |
| 11 | G14 | "as in 08", not required (11 §6) | G18 | R5 (not needed by item 11) |
| 11 | G16 | timed parameter and intervention schedule (11 §6) | G14 | R3 |
| 11 | G17 | population-level gates (division cap) (11 §6) | G1 | R3 (population fold in `when`) |
| 12 | G14 | cell-pair contact-segment aggregation (12 §6) | G21 | R11b |
| 13 | G14 | hexagonal 2D lattice with neighbour shells (13 §6) | core | **EXISTS** (2D `Hexagonal()`, M2.1b; AUDIT fix log group 1b) |
| 13 | G15 | per-sub-cell freeze/pin (13 §6) | G16 | exists (cell variable + `@constraint`) |
| 14 | G14 | derived site fields from lattice predicates (14 §8) | G18 | R5 (conformance) |
| 14 | G14b | site-set reductions: mean and std over filtered cell sites (14 §8) | G19 | R15 / exists (`integral` with a mask) |
| 14 | G15 | windowed average / ring-buffer history (14 §8) | G20 | R12 |

### 2.4 Gaps outside G1–G21, and composition fixes

The review found gaps that no G-row covered (review §3, "New gaps"; §4, "More composition
gaps"). A † marks an assignment made here where the review names no R-id.

| Gap | Why (review) | Lands in | Models |
|---|---|---|---|
| Division plane from an expression or a discrete draw | FBCA (review §3) | R3 (`rand(dist)` in the division rule). The CorePotts `normal` already takes any vector (`lifecycle.jl`) † | 08 |
| Field writes at copy time | FBCA 08b nutrient displacement (review §3) | R5 (field placement), with a declared footprint (below) † | 08 (08b) |
| Kind classes | Gates like `old == 0` assume the matrix is the medium. In Bauer, fluid and matrix are cells (review §4 [j]) | Step 0 composition fixes: `@kinds` groups, `kind[x] ∈ ecm` † | 05, 07 |
| Ownership hooks | `@convert`, divide, retire and create skip `@on_copy` / `clear_on_ownership_change`, so site state goes stale (review §4 [f]) | R8 (the shared ownership-delta routine) | 05, 06, 07, 14 |
| Component scope across transitions | Components and drives scoped to one kind are lost after `@transition` (review §4 [g]) | R3 (scope by kind set or predicate; component state survives) † | 06, 11 |
| Explicit phase order | The order between components, host operators and lifecycle is undefined (review §4 [h]) | R5 (with field placement) | 06, 08, 11 |
| Declared footprints for non-local reads | Related centroids, BFS and pair energies silently break Checkerboard exactness (review §4 [i]) | R6 (claim widening). The compiler adds claims or rejects the Checkerboard with a clear error, and any rejection needs a D-051 item 5 exception | 05, 11, 12, 13 |
| A solver per field | One global `field_solver` (review §4 [e]) | Step 0 composition fixes (solver metadata per equation or component); R14 | 06, 07 |

The step 0 composition fixes are the cheap pairwise fixes (review §4):
- both division kinds per rule domain (`compile.jl:236–238`);
- several relationships (`compile.jl:118`);
- per-equation solvers;
- a frozen-mask refresh on events;
- contact terms that bind `x`/`x′`;
- a per-rule `Every(n)` cadence;
- one `alive` definition (D-066: `alive(c) ≡ volume[c] > 0`).

The ownership-delta routine lands with R8 and claim widening with R6 (review §4).

### 2.5 Roadmap questions (all answered)

D-051 answers review [§7](../feature-roadmap-review.md#7-questions-for-the-maintainer)
questions 11, 1, 4, 5, 2 and 12 (its items 1–6, in that order). Question 3 was answered by
the maintainer on 2026-09-30 (D-052): default
acceptance is plain Metropolis on the model's proposal law, as in the papers and every
reproduction tutorial; an opt-in `MetropolisHastings()` acceptance type (each R10 proposal
law defines `proposal_ratio`) is built alongside R10, zero-cost when unused, on both
algorithms, and validated against exact Boltzmann enumeration on a tiny lattice.
Questions 6–10 were answered by the maintainer on 2026-09-30 (D-065, amending D-053
items 6, 7 and 9):

6. **Explicit liveness (R6): follow standard CPM behaviour where performance allows.** A
   survey of CompuCell3D, Morpheus and Artistoo (`../liveness-survey.md`, P6.5a0) leads to a
   new decision amending D-035 (id reuse) and D-037 (empty-cell energy). Each deviation that
   keeps our faster mechanism, because the standard one costs warm-MCS time or allocations
   on the performance gate, is recorded. **Adopted as D-066** (2026-09-30): alive ⇔ owns a
   site; a cell must receive a site to be born (X2); D-053 item 6's `retain_empty` and
   explicit liveness are dropped; slots are reused and a monotone `birth` serial is the
   user-visible id (X1).
7. **Cell references and claim sets (R6): approved.** Sequential is the reference for every
   energy that reads a cell reference. Checkerboard is validated statistically, as with Y2
   (it is not required to be exact).
8. **Uptake split (R15): approved, once per MCS.**
9. **Boolean networks (R13): MTK discrete (clocked, `Shift`) components**, extending D-038,
   with a well-tested lowering into the per-cell phases. No Potts expansion helper is
   built. Any gaps in MTK's discrete support are recorded with their workaround.
10. **Float32 moment after-values on Metal (R7): approved.** Statistical agreement with
    Float64 (D-029).

(Question 11, adopting guardrails (a)–(e) with the R0 renames, is answered by D-051 item 1.)

No review question remains open. The R-rows above cite these answers (R6: Q6, Q7; R7: Q10;
R13: Q9; R15: Q8; R10: question 3).

---

## 3. Feature × model matrix

● required for the default reproduction. ○ needed only by a variant, an observable or a
diagnostic. † required, but omitted by the review's sketch (derived through §2.3). The
source is the review's per-model sketches (review §5), and the ○ entries come from the
spec decisions in §4. Column 11 is 11a. 11b (Andasari) needs R3 (`@transition`,
`@discrete_events`), ODE components (exists, D-038) and ○ R12 (11 §6).

| | 01 Merks | 04 Foam | 05 Bauer09 | 06 Jiang05 | 07 Bauer07 | 08 FBCA | 09 Sorting | 10 Akeeb | 11 Jafari | 12 Zajac | 13 Myxo | 14 Fortuna |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R0 hygiene (renames, guardrails) | ● | | | | | | | ● | | | | |
| R1 copy scope, tie policy | | ● | | | | | | | | | ●† | |
| R2 layouts | ● | ● | ● | ○ | ● | ● | ● | ● | ● | ● | ● | ● |
| R3 rules, draws, events | | ● | ● | ● | ●† | ● | ○ | | ● | | | |
| R4 topology values | ● | | ● | | ○ | ○ | | | ● | | ○ | ○ |
| R5 boundaries, phase order, grids | ● | | ● | ● | ● | ● | | | ● | | | ●† |
| R6 cell references | | | ○ | | ○ | | | | | | ● | ● |
| R7 exact moments | | | | | | | | | | ● | ● | |
| R8 ownership events | | | ● | ● | ● | ○ | | | | | | ● |
| R9 3-body, several relationships | | | | | | | | | | | ● | |
| R10 proposal laws, fractional attempts | | ● | | ● | ● | ● | | | | ● | | |
| R11a `neighbors`/`contact` | | | | | | | | ○ | ●† | ○ | ○ | |
| R11b pair trackers (exact) | | | | | | | | | | ● | | |
| R12 cell-variable lags | | | | | | | | | | ○ | | ○ (14c) |
| R13 tables, Boolean networks | | | | ● | | | | | ●† | | | |
| R14 implicit / steady fields | | | ○ | ● | ● | | | | | | | |
| R15 host operators, uptake, FBA | | | ● | ● | ● | ● | | | ● | | | ○ (14c) |
| R16 analysis (docs-first) | ● | ● | ● | ○ | ○ | ● | ● | ● | ● | ● | ● | ● |
| hex lattice (exists) | | | | | | | | | | | ● | |
| 3D (exists) | | | | ● | | | | | | | | ● |

Notes on the matrix:
- Item 01's R0 entries are M3 (the soft E₀ needs the renamed topology values) and M7 (the
  `Chemotaxis(response, when)` form that replaces `extension_only`). `major_length`
  already exists for the length constraint, so 01 needs no R7.
- Item 10 needs only the `rule = :local` rename, with nothing blocking (review §5). Its
  clock state is cell variables (10 §6).
- Item 09's Binomial labels and staged temperature already work as cell and model updates
  (review §1). R3 is needed only for the declarative protocol form.
- Items 06 and 14 are **3D**. Item 11b is 3D and out of scope as a reproduction (11 §8).
- The §2.4 composition fixes are not columns here. Their models are listed in §2.4.

---

## 4. Decisions (approved)

The user chose "decide per model" for paper-vs-code conflicts. **On 2026-09-30 the
maintainer approved every recommendation in §4.1–§4.12 as written ("approve all"),
including the items marked "(reopens D-049)".** Each "Recommendation" column below is
therefore the decided default, and each named alternative is the documented variant.
Items that depend on an unanswered author question (§5) keep the recommended default
until the author answers.

**Feature ids.** The decisions below cite the former G-ids as approved. Bracketed R-ids
were added for resolution via §2.3; they do not change any decision.

**Heuristic.** Default to whatever produced the published figures, which is usually the
released code. Ship the other reading as a documented variant keyword. Where no code
exists, default to the reading the figures support. Every default is listed in the
tutorial's deviations table.

**Status.** "(reopens D-049)" marks an item that D-049 settled, where a spec found new
evidence. Such items need explicit re-approval.

### 4.1 Merks (01)

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| M1 | **Current defaults mix variants** (AUDIT P-14, pending). `MerksVasculogenesis` uses A = 50, λ = 25 (2008) with L = 30 px, λ_L = 5 and 282 cells in 333² of 500² (2006) | (a) two parameter sets, `variant = :merks2006 \| :merks2008`; (b) keep the mix | **(a)**. 2006: λ = 50, A = 100, λ_L = 5, 8-neighbourhood, α = ε = 1.8e-4 s⁻¹ (01 §7.8). 2008: Dataset S1 values (01 §7.1) | The spec says the two sets must not be mixed (01 §8 A-17). L = 30 px (60 µm) matches neither the paper (≈ 50 px) nor the code (60 px) (01 §7.9 D-12) |
| M2 | 2006 target length L: paper "about 100 µm" = 50 px vs 60 px in every "Fig. 4 of Merks 2006" file (01 §7.9 D-12); the 2015 TST chapter suggests `target_length = 60` "(L = 120 µm, if dx=2.0e-6)" (01 §8 A-1) | 50 / 60 | **50 px** default, `L = 60` variant | The files are a 200² "small field" demo, not the published run (01 §7.9 D-16). The paper text is the only statement about Fig 4. Ask Merks (§5) |
| M3 | 2006 connectivity: soft threshold shift E₀ on 8-ring-breaking copies (code), vs today's hard one-arc veto (D-049) (01 §7.3) | soft E₀ = 5000 / soft 2000 / hard veto | **Soft E₀ = 5000** once G4 soft [R4] exists; hard veto as a variant (**reopens D-049**) | 5000 is in `longcells.par`, the file labelled for Fig 4, and satisfies "E₀ > 2000" strictly. 2000 is only the generic default (01 §7.9 D-13). The code applies E₀ only to the losing cell (01 §7.3) |
| M4 | Frozen 1-px border with J(c,B) = 100, J(M,B) = 0 vs free closed walls (D-049) (01 §7.5) | frame / free walls | **Frame** via G16 [R2 `Frame`] (**reopens D-049**) | The paper states it (01 §2.1) and the code implements it |
| M5 | Field: 15 FTCS 5-point substeps of Δt = 2 s, PDE **before** the CPM sweep, absorbing c = 0 ring, c₀ = 0; vs the fewest stable substeps (D-049) (01 §7.4) | paper/code schedule / fewest stable | **Paper/code schedule** (**reopens D-049**) | It costs almost nothing (D·Δt/Δx² = 0.05 is already stable, 01 §3.1). The absorbing BC matters on 200² (01 §7.9 D-10) |
| M6 | 2008 relaxation: 100 MCS with no PDE (and so no chemotaxis) in every Dataset S1 file, not in the paper (01 §7.9 D-5). The 2006-labelled files use 0 (01 §7.8), which corrects AUDIT P-14's wording | include / omit | **Include for 2008, omit for 2006.** Report time both from code MCS 0 and from the end of relaxation until Merks answers | The code produced the figures. The time origin is open (01 §8 A-19) |
| M7 | 2008 chemotaxis scope. The current `contact_inhibited = true` gate is `old == 0 && kind[new] == endothelial` (extension into the medium only). The 01b default is **extension + retraction** at cell–medium interfaces with χ(c,c) = 0 (01 §7.2, §7.9 D-3) | model χ(c,c) and χ(c,M) as real parameters, plus a `mode = :extension_retraction \| :extension_only` switch | **Adopt**. Default `:extension_retraction` with χ(c,c) = 0 and χ(c,M) = 500 | The current option reproduces only the Figs 11–13 variant. The continuous χ(c,c) is a superset the paper's Fig 5 sweep needs (01 §8 A-20). It also removes the model-named `extension_only` (P-15) |
| M8 | Saturating chemotaxis c/(1 + s c) per site (01 §2.3) | expression / library law | Expression in the drive now, `Chemotaxis(law = Saturating(s))` later | G3 already allows it [R0 `Chemotaxis(response)`] |
| M9 | Integer-truncated ΔH (01 §7.9 D-7) | Float / Int | **Float**, with no variant | D-029. The spec expects a statistically benign deviation. Fig 13's cumulative ΔH bookkeeping must be defined explicitly (V-C11) |
| M10 | 01b Fig 2 geometry: paper (1000 cells, 333² in ~500²) vs files (360 seeds on 200²) (01 §7.9 D-1) | paper / files | **Paper** for V-C1. Files as a density-matched small variant | The figure is the target. The enclosing lattice is garbled (A-9): ask |
| M11 | Seeding: Eden growth plus splits (code) vs square blocks (current `merks_state`) (01 §7.6) | Eden (G13 [R2]) / blocks | **Eden** for 2008 (sprout 1 blob, 7 splits = 128 cells); blocks acceptable for 2006 until G13 [R2] | The 2008 relaxation inflates 15-px cells to A = 50; the start state matters for Figs 5–11 |

### 4.2 Foam (04), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| F1 | Shear term: literal Σ_i γ(y_i,t) x_i (1 − δ) vs per-flip displacement γ(y_i,t)·(x_i − x_j) with minimum image (04 §7 A-1, A-10) | literal / displacement | **Displacement**, with γ₀ **calibrated via γ₀/J scaling** against V3/V5 (transition γ₀/J ≈ 1.9). Literal as a variant, documented as ill-posed on periodic x | Fig 3(c) boundaries are lines through the origin, which a position-independent per-flip bias explains (04 §3.2, A-1). Ask Jiang/Glazier |
| F2 | T = 0 with ΔH′ = 0: accept (T → 0⁺), ½ (engine default, GG convention), or reject (04 §7 A-6) | 1 / ½ / 0 | **Accept (1)**, the spec's recommendation, recorded as a choice. ½ as a variant | Eq 3 puts ΔH′ = 0 in the exponential branch, and exp(−0/T) → 1 as T → 0⁺. Needs a G8 tie-policy option [R1 `Metropolis(tie)`] |
| F3 | Lattice: text 400 × 100 with 20² bubbles vs figures 256² with 16² (04 §7 A-7) | – | **256², 16²** | Every shown figure (resolved) |
| F4 | y-boundary type (04 §7 A-2) | free closed wall / frozen wall rows (G16 [R2]) | Pick the option whose relaxed ordered foam gives μ₂(n) ≈ 0.44 (V1b). Report both | Unstated. V1b is the only discriminating target |
| F5 | Proposals: boundary-only, unlike-neighbour (04 §2.3) vs plain Metropolis; attempt counting for non-wall picks (A-5) | exact law / plain | **Exact law** (G8 [R10]). Count all-site attempts per MCS, and compare only timing-free targets | At T = 0, interior picks are null anyway. Only the time axis differs, and targets avoid absolute MCS (04 §7 A-5) |
| F6 | T1 counting unit (even bars suggest double counting, A-15) | configurable | Configurable; ratios only | – |

### 4.3 Bauer 2009 (05) and Bauer 2007 (07), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| B1 | Two parameterisations (05 §7.3) | one model with variants / two models | **Two models, two tutorials** | Every parameter, the time scale and the rules differ (05 §7.3; 07 §7.2) |
| B2 | Pixel size unknown. (0.55 µm)² degradation and 1.1 µm bundles fit 0.55 µm/px, but that "must not be adopted without author confirmation" (05 §7.2) | wait / provisional 0.55 µm | **Block both tutorials on Jiang's answer.** Develop with 0.55 µm labelled as a hypothesis | The spec forbids silently adopting it |
| B3 | 2009 domain 166 × 106 µm (figure axes) vs "100 µm by 160 µm" (p.6) (05 §7.1 item 1) | – | **166 × 106** | The figures use it |
| B4 | 2009 speed: Table 2 16.0 µm/h "averaged over 14 hours" vs Fig 1A ≈ 10 µm/h at 14 h (05 §7.1 item 2) | – | Validate against the **Fig 1A curve** (V1). Record Table 2 as unexplained | The curve is the primary data |
| B5 | Continuity: exact BFS soft penalty α = 300 (05 §2.3) vs a local-ring approximation | exact / local | **Exact BFS** default. Local ring as a validated performance variant | Table 3's kT < 0.25 regime depends on it (05 §6 G4) |
| B6 | Uptake B = min(β, V) per EC site vs per EC (β is per cell per hour) (05 §7.2; 07 §7.1 item 4) | per site / per cell | **Per cell** (G6 [R15], conservative) default; per site as a variant | The units say per cell; per-site uptake multiplies uptake by cell area |
| B7 | 2007 IC: V = 0 vs steady state (07 §7.1 item 1) | – | **Steady state** (G5 SteadyState [R14]) | That is what the hybridization section describes |
| B8 | 2007 kind-restricted copy sources ("only ECs invade") (07 §6 G8) | restricted / free | **Restricted** (G8; exists as `@constraint kind[new] == k`, §2.3) | The text says so. Ask |
| B9 | 2007 baseline proliferating cell = the one immediately behind the tip (07 §7.1 item 3) | – | Adopt as a flagged inference | Table 2's baseline equals the Fig 5 8.9 µm point |

### 4.4 Jiang 2005 (06), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| J1 | Glucose rate b₀(P): 162 (PDF) vs 216 (erratum 06b, read 2026-09-30; it also corrects the unit to [mM/h]; it does not say which value the simulations used, which stays open) (06 §3.4, §7.1 item 4) | 162 / 216 | **162 default, `erratum = true` → 216.** This departs from the spec's suggestion | C₀ = 240 ≈ 1.5 × 162 and Q/P ≈ ½ only hold with 162. That suggests the published simulations were built on 162. Ask Jiang which produced Figs 5–8 |
| J2 | Unfavourable chemistry: Fig 3 flow chart (P dies) vs text (P → Q, Q → N) (06 §7.1 item 1) | text / chart | **Text**; flow chart as a variant | Biologically coherent; the chart labels look swapped |
| J3 | Rb → E2F drawn stimulatory, which gives inverted biology (06 §7.1 item 2) | as drawn / inhibitory | **Blocking: ask first.** Provisional default inhibitory, flagged | As drawn, E2F turns on only when the CKIs are on |
| J4 | Necrosis conditions AND vs OR (06 §2.4) | – | **OR**, flagged | "are conditions for cell necrosis". Ask |
| J5 | GF/IF diffusivity: Table 1 10⁻⁶ both vs text 10⁻⁷/10⁻⁶ (06 §7.1 item 3) | – | **Table 1**, plus a sweep (T10) | – |
| J6 | Necrotic inhibitor secretion: 2 %/h/cm³ (Table 1) vs 0.1 ml/h (Appendix) (06 §7.1 item 5) | – | **Table 1** | Unit-compatible with the other rates |
| J7 | Transient 45-min solve per ¼ MCS vs quasi-steady (06 §2.5, §3.2) | implicit transient / SteadyState | **Implicit transient** (G5 + LinearSolve ext [R14]), quasi-steady as a performance variant | D_O₂ ≈ 2.5 × 10⁶ voxel²/MCS makes O₂ quasi-static anyway (06 §3.2) |
| J8 | The lattice-size artefact of Fig 8 (06 §5 T9) | reproduce / larger lattice | **Larger lattice** (deliberate deviation) | The spec says not to reproduce the artefact |

### 4.5 FBCA (08), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| X1 | Degenerate LP optima (08 §2.2, §7 item 5) | plain FBA / pFBA / lexicographic | **pFBA** (a deterministic tie-break), declared | Lactate phenotype classification depends on it |
| X2 | Impermeable cells: sequential random-order FBA with write-back (08 §2.2) vs parallel | sequential / parallel | **Sequential**, as written | It is a conservation rule, and LP cost dominates regardless |
| X3 | Eq 6 averaging is non-conservative for D ≠ 1 (08 §2.2) | as written / conservative | **As written** (G18 [R5]), with D as a calibration parameter | The paper's operator. Ask the authors for the D values |
| X4 | Biomass on division (08 §6 G9) | halve / by area | **Halve** | Consistent with ρ = 1/F at initialisation |
| X5 | Metabolic model: HMR CORE (240 × 272) (08 §7 item 13) | published file / authors' variant | **Published HMR core as the default, flagged:** Di Filippo 2016 supplementary `mmc1.xls` (on disk; taken to be the core model, since the article text that labels the files was not read). It has 274 reactions (272 without `biomass_synthesis` and `Ex_biomass[s]`) and 252 metabolites, vs the stated 272 × 240 (08 §1); ask how the papers counted and what changed. (changed 2026-09-30 on new evidence; approved by the maintainer 2026-09-30; D-067) Previously: **Blocking**: obtain it (Di Filippo 2016 supplementary). | The only released core model |

### 4.6 Cell sorting (09)

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| S1 | GG initial state follows PRE 47, 2128 (1993) §II D3 (D-049 F-2); the PRE is on disk as `09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf` (09 §8) | – | **Keep it.** Recipe verified on disk (09 §8.2, §8.4 A-GG5). The paper-size start `graner_glazier_aggregate` (a centroidal Voronoi disk, not Potts-relaxed, D-063) is used by the FULL run | Provenance honesty; the PRE settles the recipe (09 §8.4) |
| S2 | GG "two T = 0 annealing steps": on a copy vs on the trajectory (09 §7 A-GG4) | copy / trajectory | **On a copy** (a measurement), with a trajectory variant | "before calculating the statistical properties" reads as a measurement |
| S3 | OS: which type is engulfed (09 §7 A-OS1) | – | **A engulfs B** (B = labelled) | Parameters, S1 Movie and Fig 2 agree; the p.11 wording is the outlier |
| S4 | OS: VN contact / Moore proposal from 2026 Chaste develop, not the 2017 release (09 §7 A-OS4) | – | **Follow the code**, flagged | The only concrete source. Evidence 2026-09-30: the paper tag `paper/CellBasedComparison` (2016-08-29) and `release_2017.1` have the same Potts rules as develop (09 §1), so the flag can be dropped |
| S5 | OS: Binomial(400, 0.5) labels vs exactly 200 (09 §2.2) | – | **Binomial** (code) | What produced the figure |
| S6 | OS: 10 h unlabelled equilibration (code only) and time origin (09 §7 A-OS3) | – | **Include**; t = 0 at labelling | Code |

### 4.7 Akeeb (10), code released

The code is authoritative: the paper reports the code's quantities (10 §7 D12).

| # | Conflict | Recommendation | Why |
|---|---|---|---|
| A1 | D1 leader creation: insertion of one-pixel leaders (code) vs reassignment (paper) | **Code** default; `leaders = :reassign` variant | The sample and CSV counts (1559 cells) come from the code (10 §4 #23) |
| A2 | D3 division: per-MCS hazard (code) vs U(25, 125) draw (paper) | **Code** (already the port, 10 §7.1 P5) | – |
| A3 | D6 chemotaxis: Merks ΔH (code) vs absolute potential (Eq 1) | **Code** (already) | Magnitudes differ by orders |
| A4 | D12–D18 metrics: code definitions vs paper definitions | **Code definitions** for validation. Paper definitions ship as extra observables | The paper numbers reproduce only from the code quantities |
| A5 | μ default 30 (port, `lib/PottsModels/src/akeeb.jl:33`) vs 24 (sample point) (10 §7.1 P1) | **24** | The default should reproduce the reference sample |
| A6 | 700 vs 701 sweeps (10 §7 open q. 4) | Run 701, report MCS 700; ask | – |

### 4.8 Jafari Nivlouei 2021 (11a), no code

| # | Conflict | Recommendation | Why |
|---|---|---|---|
| N1 | Nutrient source: S_n term vs Dirichlet clamp on EC sites (11 §7 item 2) | **Clamp** default, source-term variant | Both are printed. Ask |
| N2 | β in mol/cell/s vs n in pg/voxel (11 §7 item 1) | Per-cell conservative uptake (G6 [R15]), converted by the cell volume inferred from Table 4 (flagged inference) | – |
| N3 | χ values missing (11 §7 item 7) | **Calibrate** χ_EC to V11a-2 sprout speed and χ_tumour to V11a-5, and label them as calibrations | No other source |
| N4 | Boolean: Fig 3 lookup table (runtime) vs full network (11 §2A) | **Table** default. The network is a unit test (V11a-1) with β-Catenin = Wnt ∨ (Akt ∧ ¬cad ∧ ¬APC), which reproduces 15 of the 16 Fig 3 cells; the precedence is RESOLVED from Fig 3 and Table 1 (11 §7 item 9). The cell ITG RTK Wnt = 100 / Cadherin OFF (printed 0011) is flagged as a figure error, still open; the lookup table uses the printed value | What the paper ran |
| N5 | Continuity a′ (Eq 3): exact BFS vs local | Same choice as B5 | Same α = 300 lineage |
| N6 | S1 Data vs text numbers (11 §9.3) | **Sheet values** are targets; text values are recorded, not enforced | The sheets are the plotted data |

### 4.9 Zajac (12), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| Z1 | **Exact per-copy axis** (segment-averaged, both cells re-evaluated) **vs lagged per-MCS director** (12 §2.2) | exact / lagged | **Exact** is the reference default (needs G21 + G2 [R11b + R7]; D-051 item 3). Lagged ships as a performance variant **only if** it passes the pre-registered acceptance test (12 §5) | The paper updates per copy. The lagged director removes the non-local energetic effect (12 §2.2) |
| Z2 | All numeric parameters missing (12 §7 A-Z2) | – | Calibrate T to ≈ 46 % acceptance and α to 57 % anisotropy, under a stated definition (A-Z3). Label the tutorial a **reconstruction** | No other source until the thesis is found |
| Z3 | Shape constraint I = polar moment (12 §7 A-Z7) | – | Polar moment I_xx + I_yy, flagged | Our reading of p.252 |

### 4.10 Starruß myxobacteria (13), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| Y1 | θ = normalised chord vs raw chord (13 §7 item 1) | unit / raw | **Unit vector**; raw as a variant | A norm cannot be a direction. The scale changes by ≈ 2D ≈ 7 |
| Y2 | **Checkerboard vs sequential.** Segment energies and θ read sibling COMs, so on the checkerboard each cluster may change at most once per colour (`cluster_claims`, D-036) | sequential / checkerboard + claims | **Sequential** for the reference. Checkerboard as a performance variant that must match V8–V12 within tolerance | Claims change which copies are possible per colour; sequential is the paper's dynamics |
| Y3 | "Second-nearest" contact shell: shells 1+2 (12) vs shell 2 only (13 §7 item 4) | – | **Shells 1+2** (`Hex(2)`) | CPM convention |
| Y4 | Eq 10 loser term as printed (13 §7 item 3) | – | **As printed** | Implement exactly, then ask |
| Y5 | Same-cell non-adjacent contact = J_CC (13 §7 item 12) | – | **As printed** | – |
| Y6 | Fig 6 κ ≈ 10 vs s = 8 (13 §2.8) | – | s = 8 for 'xanthus'; κ(s) ≈ 0.86 s is a labelled hypothesis | – |

### 4.11 Fortuna / Thomas / Dal-Castel (14), code released

| # | Conflict | Recommendation | Why |
|---|---|---|---|
| C1 | J_cyto–lamellipodium: 20 (Table 1) vs 10 (both released codes) (14 §9 item 3) | **10** default, `J_CL = 20` variant | Both codes agree. Ask which produced the figures |
| C2 | Conversion law: paper p ∝ (1 − V₃/V₃ᵗ) vs code 0.1·(1 − V₃ᵗ(t)/(φ_F V_totᵗ)) on target volumes, which stops permanently (14 §2.9.5) | **Code** default; a paper-literal variant | Code, and 14b agrees ("until the lamellipodium target volume is attained") |
| C3 | F-actin: PDE (14a code) vs binary indicator (14c) (14 §9 item 1) | **PDE** for 14a/14b; **indicator** (G18 [R5]) for 14c | Each paper's own code |
| C4 | Secretion vs decay order inside CC3D `DiffusionSolverFE`: F ≈ 1 vs F ≈ 0.1 at the source, a **10× difference in protrusion strength** (14 §9 item 15) | **Blocking**: read the CC3D 3.7.9 source or ask. Calibrate against Table 2 in the meantime. **Done 2026-09-30:** the 3.7.9 and 3.6.2 sources give **F ≈ 1** (one call per MCS; diffusion + decay, then secretion; face-neighbour contact test), so the question is not asked | CC3D source (14 §2.9.2) |
| C5 | Initial condition: suspended cell (Fig 4A) vs tangent ball + 6³ nucleus (code, 14b) | **Code** | Resolved (14 §9 item 9) |
| C6 | 14c gate: δ, strict "<" vs "≤", window includes the current MCS (14 §9 item 10) | **Code** (δ = 0, ≤, includes current) | – |
| C7 | Protrusion on retraction (Medium overwriting FRONT/LAMEL) (14 §9 item 16) | **Code:** both extension (FRONT → Medium) and retraction (Medium → FRONT), same formula, for 14a and 14c; the paper's extension-only Eq 7 is a variant. (changed 2026-09-30 on new evidence; approved by the maintainer 2026-09-30; D-067) Previously: **Eq 7** (FRONT source → Medium target only) | CC3D's default `merks` chemotaxis algorithm, which both codes use without an `Algorithm` element, applies the term in both directions (CC3D 3.6.2 and 3.7.9 source, 14 §2.9.4; 14c's CC3D 4.2.3 not checked but very likely the same). Asked in the letter as part of the provenance question |

### 4.12 Cross-cutting accuracy-vs-performance choices

| Choice | Models | Recommendation |
|---|---|---|
| Float vs integer ΔH | 01 | Float (D-029) |
| Exact BFS continuity vs local ring | 05, 11 | Exact default, local variant validated |
| Exact per-copy shape/axis vs lagged | 12 (01 is already exact) | Exact default; lagged only after the 12 §5 test |
| Sequential vs checkerboard for cluster-coupled energies | 13, 14, 12 | Sequential reference; checkerboard variant validated statistically |
| Paper field substeps vs fewest stable | 01 | Paper substeps (cheap) |
| Transient vs quasi-steady fields | 06, 05/07 (init only) | Transient default; quasi-steady variant |
| Per-cell LP every MCS | 08 | Required. Warm-start the LPs (COBREXA/JuMP ext) and keep the model variant-free |
| Boundary-only proposal laws | 04, 12 | Implement as G8 laws [R10]; compare only timing-free targets |

---

## 5. Questions for the authors (invitations to collaborate)

Blocking questions come first in each list, marked **[B]**. The tutorial's §6 repeats each
model's list.

### Yi Jiang (PI): Jiang 1999, Jiang 2005, Bauer 2007/2009, Akeeb 2026

1. **[B] Bauer 2007/2009:** µm per pixel, lattice geometry, and the neighbourhood order for copies, adhesion and the BFS (05 §7.4 q1; 07 §7.3 q1).
2. **[B] Jiang 2005:** Rb → E2F polarity in Fig 2, and each node's on-state meaning (06 §7.3 q2).
3. **[B] Jiang 2005:** values of T, α, θ (Eq 4), γ_P, "large" γ_N and the lattice size (06 §7.3 q1).
4. **[B] Jiang 2005:** 162 vs 216 for the published figures (06 §7.3 q5). The Table 1 unit is settled by the erratum: [mM/h] (06b; 06 §3.4).
5. **[B] Foam:** the exact per-bond form of the Eq 2 shear term and the γ₀ scale (04 §7 A-1).
6. **[B] Bauer 2009:** recruitment trigger, new-cell size and phenotype; tip/stalk/proliferating assignment (05 §7.4 q4–q5).
7. Foam: the y-boundary implementation (A-2); the T = 0 tie (A-6); anneal/coarsen temperatures and lengths (A-8); the Fig 9 bubble counts 377/380 (A-14); the T1 counting unit (A-15); φ(0) in Fig 7 (A-16).
8. Bauer 2009: degradation product and site choice (05 §7.4 q6); matrix/fluid target volumes (q7); χ_σΔV evaluation (q8); B per site or per cell and the PDE scheme (q9); fibre generation (q10); the Table 3 χ thresholds (q11); speed averaging (q3); domain size (q2); dissertation code (q12).
9. Bauer 2007: MCS = 1 h and run length (07 §7.3 q2); tip identity and baseline proliferating cell (q3); degradation (q4); Eq 3 roles (q5); EC-only invasion (q6); tissue cells (q7); fibres (q8); steep-gradient BC (q9); PDE and B (q10); code (q11).
10. Jiang 2005: Eq 4 below-threshold semantics and E2F check timing (06 §7.3 q3); P/Q death branch and AND/OR (q4); GF/IF diffusivities (q6); necrotic secretion (q7); volume checkpoint (q8); surface definition (q9); consumption cap (q10); solver and ECM factor (q11); code (q12).
11. Akeeb: which classifier produced Fig 5 and S1 Table; Eq 1 vs the CC3D Merks ΔH; the repository/commit for the 13,310 runs; the MCS-0 sweep; NeighborTracker adjacency; the off-grid λ runs (10 §7 q1–q6).

### James A. Glazier: Zajac, Fortuna, Graner–Glazier, foam

1. **[B] Zajac:** access to the 2002 thesis, or the J, α, λ, κ, A∘, a, b, T, lattice size and cell count values (12 §7 A-Z2).
2. **[B] Zajac:** the definition of "57 % anisotropy" (A-Z3); segment definition and averaging (A-Z4); trial-energy evaluation order (A-Z8).
3. **[B] Fortuna:** ~~secretion/decay order in CC3D 3.7.9 `DiffusionSolverFE`~~ (RESOLVED 2026-09-30 from the CC3D source: diffusion + decay, then secretion; steady F ≈ 1 at source sites, effective λ_F = nominal; 14 §9 item 15), and whether the SF1 code produced the figures (14 §9 item 17).
4. Zajac: the extension measure plotted in Fig 5 (A-Z5); I in the shape constraint (A-Z7); the proposal neighbourhood (A-Z9).
5. Graner–Glazier: lattice size, boundary conditions and the dark/light fraction of the PRE runs; the "type-type correlation" of PRE Figs 13(d), 21(b); whether PRL Fig 2 and PRE Fig 13 are different runs of the sorting set (they differ by up to 0.07 in the dark–dark fraction); the cell-adjacency rule behind the neighbour counts n of Tables I–III (09 §8.4, §9.3). How the total boundary length of Fig. 13(a) (≈ 66 850) is counted: pairs once or twice, and over which neighbour range (our Moore(1) count, each pair once, gives ≈ 37 000 for 1000 cells; 09 §9.1 V-PRE4). N, the relaxation parameters and annealing on a copy are settled by the PRE (09 §8.4).
6. Foam (co-author): the same as items 5 and 7 of the Jiang list.

### Roeland Merks

1. **[B]** 01a supplementary methods: L (50 vs 60 px), E₀ (2000 vs 5000) and the real Fig 4 geometry (01 §7.9 D-12, D-13, D-16; §8 last list).
2. **[B]** Whether the paper's MCS counts include the 100-MCS relaxation (01 §8 A-19).
3. The analysis scripts for compactness and H − H₀ (01 §7.9 D-17, D-18; A-14); morphometry code (A-18).
4. Parameter files for 01b Figs 3, 5, 7–10, 12–13, and the code for the continuous χ(c,c)/χ(c,M) sweep (D-2, D-3; A-20).
5. The enclosing lattice for Fig 2 (A-9) and the Fig 10/12 lattices (A-10).

### Rita de Almeida, Gilberto Thomas, Pedro Dal-Castel

1. **[B]** J_cyto–lamellipodium: 20 (Table 1) or 10 (code) for the 14a figures (14 §9 item 3).
2. ~~**[B]** The F-actin magnitude at source sites (solver order) (item 15).~~ RESOLVED 2026-09-30 from the CC3D 3.6.2/3.7.9 source (14 §2.9.2); not asked.
3. The 14c gate details: δ used for the figures, "<" vs "≤", and whether the current MCS is in the window (item 10).
4. The 14c-SM Table S1 S column (item 11); the Fig 8 caption (item 12); a diff of arXiv v1 against the 2025 version of record (item 13; checked 2026-09-30: arXiv has only v1 and the version of record is closed access, so the diff is still pending).
5. ~~The chemotaxis plugin on retraction (item 16)~~ (RESOLVED 2026-09-30 from the CC3D 3.7.9 source); which polarization measure Fig 12 used (14 §2.9.7 item 12, §9 item 19).

### James Osborne / Alexander Fletcher

1. **[B]** The engulfment-direction sentence on p.11 (09 §7 A-OS1).
2. The units of the Fig 2/4 time labels (A-OS2); the Fig 3 time origin and the normalisation script (A-OS3).
3. ~~Whether the 2017 Chaste core used VN contacts and perimeter (A-OS4)~~ (RESOLVED 2026-09-30: the paper tag `paper/CellBasedComparison` and `release_2017.1` match develop, 09 §1); the smoother used for the fluctuation metric (A-OS6).

### Andreas Deutsch / Jörn Starruß

1. **[B]** θ: unit vector or raw chord (13 §7 item 1); the Eq 7 sign (item 2); the Eq 10 loser term (item 3).
2. **[B]** Lattice size, MCS definition, warm-up, sampling and run lengths for Ψ̄ (item 5).
3. The "second-nearest" shell (item 4); κ(s) and Fig 6 (item 6); density and κ for the Fig 8 right panel (item 7); initial conditions (item 8); head fixation (item 9); measurement intervals (item 10); degenerate curvature (item 11); same-cell J (item 12).

### Chiara Damiani / Alex Graudenzi / Davide Maspero

1. **[B]** MATLAB sources, and how the 272 reactions / 240 metabolites were counted relative to the published HMR core `mmc1.xls` (274 × 252; 08 §1) and what changed; the ACRI 2018 parameters (λ, k_BT, attempts, initial fields) (08 §7 items 12–13).
2. **[B]** The starvation-death rule (item 10); Eq 6 D values and sweeps per MCS (item 8); the edge efflux value (item 9).
3. Units (item 1); the periodic axis and top boundary (item 2); ρ definition (item 3); biomass split (item 4); tie-breaking of degenerate optima (item 5); the uptake bound form (item 6); SC1/SC2 nutrient bookkeeping (item 7); SC2 reaction ids and O₂ bands (item 11).

### Sahar Jafari Nivlouei / Madjid Soltani / Rui Travasso

1. **[B]** The CC3D project (11 §7 item 12).
2. **[B]** χ values and signs, and the neighbour order (item 7); the hypoxia, necrosis and apoptosis rules (item 5).
3. **[B]** Nutrient unit conversion (item 1); source term vs clamp (item 2); the PDE solver and steps (item 3).
4. The Wnt input and contact normalisation (item 4); host-cell parameters (item 8); ~~β-catenin precedence~~ (RESOLVED from Fig 3 and Table 1, 11 §7 item 9; ask only about the Fig 3 cell ITG RTK Wnt = 100 / Cadherin OFF printed 0011) (item 9); the clamped receptor (item 10); vessel geometry (item 11); the S1 Data inconsistencies (item 14).

---

## 6. Recommended build sequence

The model order is the approved revised order (hygiene → sorting → Akeeb → Merks → foam →
Fortuna → myxo → Zajac → Bauer07 → Bauer09 → item 11 → Jiang05 → FBCA). Each step now
introduces R-features. The R-list is in dependency order (review §3), and each R-feature
first lands at the earliest step whose model needs it.

The review fixes these placements:
- the step 0 composition fixes (§2.4);
- the ownership-delta routine lands with R8;
- claim widening lands with R6 (review §4).

D-051 adds three more:
- R0 and the guardrails came first and are **done** (`db7eea2`, item 1);
- fractional attempts are one sweep keyword and cost nothing when unused (item 2);
- the exact Zajac pair trackers are the reference, with the lagged director as a variant
  (item 3).

Rationale for the order:
- **Fortuna comes at step 5.** It is grade A with strong targets, and it introduces R6 and
  R8, which the Bauer models, Jiang 2005 and myxobacteria reuse.
- **Myxobacteria follows at step 6.** It shares the "cluster of sub-cells" abstraction and
  R6 with Fortuna (13 §6; 14 §8).
- **Zajac comes at step 7.** It is grade C with weak targets, and it carries the heaviest
  sweep machinery (R11b, which is L, sequential in practice). D-051 item 3 keeps the exact
  form as its reference.
- **The Bauer models and Jiang 2005 are blocked** on answers from Yi Jiang. The questions
  go out at step 0.
- **Every feature must work under both algorithms** (D-051 item 5). Any Checkerboard
  exception, R11b being the likely one, is recorded in DECISIONS at the step that
  introduces it.

| Step | Model(s) | R-features introduced | Gate |
|---|---|---|---|
| 0 | **Hygiene and infrastructure** | **R0 (done, `db7eea2`, D-051 item 1):**<br>• the topology values `local_components`/`ring_cells` behind `connectivity(…)`, `Chemotaxis(response, when)` and `neighborhood_mean(fold)`;<br>• unknown options throw; `public` declarations;<br>• guardrails (a)–(e) in `test/qa.jl` and `lib/PottsModels/test` (review §6).<br>**Step 0 composition fixes (§2.4):** both division kinds, several relationships, per-equation solvers, frozen-mask refresh, contact `x`/`x′`, per-rule `Every(n)`, one `alive` definition, kind classes.<br>**Other:** the Literate + Documenter "Published models" pipeline and `TUTORIAL_TEMPLATE.md`; send author question batch 1 (§5) | Guardrails pass; the siblings for Act and saturating chemotaxis pass |
| 1 | **Sorting** (GG + Osborne CP): pilot tutorial | R2 first slice (`Tiling`, `Scatter`, `Frame` for the Osborne frozen ring); R16 in the docs (boundary-length decomposition, annealed-copy measurement, D-051 item 6). Declared proposal and tie at ½ already exist | S1 cleared (PRE on disk, recipe verified; §4.6 S1, 09 §8) |
| 2 | **Akeeb** | R2 `InsertUntil`; R16 code-definition metrics (per-column areas, peaks, BFS clusters) | A5 default μ |
| 3 | **Merks** (2006 + 2008) | **R4:** soft E₀ drive over a topology value, and the geometry dispatch; the soft-connectivity sibling (guardrail (e)) is its acceptance test.<br>**R5:** `@boundary` absorbing frame applied every substep; PDE before the sweep; explicit phase order.<br>**R2:** `Eden` + splits.<br>**R16:** compactness, morphometry | M1–M7 sign-off |
| 4 | **Foam** | R1 (`direction`, `time`, `Metropolis(tie)`); R10 `BoundarySite` law with all-site attempt counting; R3 (`@discrete_events`, `@terminate`, with the rest of R3); R2 `BrickWall`; R16 (T1, topology moments, spectra) | Provisional until F1 is answered |
| 5 | **Fortuna** (14a/14b) | 3D run. **R6:** `sibling`/`members`, liveness per D-066 (no `retain_empty`; FRONT created on demand and dying when it empties, FRONT deaths counted; `birth` ids), claim widening. **R8:** `@convert` (sequential) with the shared ownership-delta routine and ownership hooks. R2 `Plane`/`Spheres`; R5 predicate-sourced PDE; R16 MSD/Fürth | C4 settled by the CC3D source (F ≈ 1); C7 per D-067 |
| 6 | **Myxobacteria** | R9 (3-body angle terms, ordered chains); R7 (unwrapped centroids, cluster moments); R6 related centroids in drives with declared footprints; R2 `Chains`; R16 cluster-graph Ψ̄. Hex exists | Y1, Y2 |
| 7 | **Zajac** | R7 (eccentricity, orientation, tensor ΔH); R11a `neighbors`/`contact`; **R11b** per-copy pair trackers, exact (D-051 item 3); R10 boundary-only law (reused); the exact-vs-lagged acceptance test (12 §5); the 12a Eq 7 unit test | Label as a reconstruction |
| 7b | **14c chemotaxis variant** | R12 (`Pre(x, k)` on cell variables, 100-MCS window); R5 indicator field (conformance); site-set mean/std via `integral` with a mask | – |
| 8 | **Bauer 2007** | **R3:** symbolic `@transition`, with component scope across transitions. **R14:** steady-state init and a switchable source. **R15:** `CellOperator` first slice and per-cell `uptake`. **R8:** degradation via `@convert` (reused). **R10:** `UnlikeNeighbor`. **R2:** `Fibres` + tissue grid | B2 (pixel size) |
| 9 | **Bauer 2009** | R4 `Global()` soft BFS penalty, on both algorithms (D-051 item 5); R8 `@create` at the wall; R16 branch and loop detection | B2 |
| 10 | **Jafari Nivlouei 2021** (item 11) and the **Andasari ODE test** | R13 (the Fig 3 lookup table; the Boolean-network unit test); R11a contact fractions; R5 two periodic PDEs with EC clamps; R3 therapy clamps as `@discrete_events`; the ODE conformance test (11b Eqs 10–12) | N1–N3 |
| 11 | **Jiang 2005** | 3D. **R10:** fractional attempts, the ¼-MCS keyword (D-051 item 2). **R5:** coarse field grids (D-051 item 4) and moving Dirichlet. **R14:** implicit 45-min transient. **R13:** Boolean with stochastic gating. **R8:** `@retire … sites => ref`. **R15:** state-dependent uptake | J3 blocking |
| 12 | **FBCA** | **R15:** FBA `CellOperator` (COBREXA/JuMP extension, D-030; pFBA, warm start) with sequential write-back. **R5:** the Eq 6 averaging operator, the flux BC and an explicit 6-phase order. **R3:** division plane by draw. **R5:** a field write at copy time. **R16:** lineage and clone sizes | X5: published HMR core `mmc1.xls` as the default, flagged (D-067) |
