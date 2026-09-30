# Published-model specs: index, unified features, decisions

This directory holds one paper-grounded spec per published model. This README ties them
together:

- §1 lists the 12 models with their sources and reproducibility grade.
- §2 gives one renumbered feature list (G1–G21) and a crosswalk from each spec's local ids.
- §3 is the feature × model matrix.
- §4 lists the per-model decisions (all approved by the maintainer on 2026-09-30).
- §5 lists questions for the authors, grouped by recipient.
- §6 gives the recommended build sequence.

Each published model ships a reproduction tutorial written to
[`TUTORIAL_TEMPLATE.md`](TUTORIAL_TEMPLATE.md).

**Conventions.**
- "(01 §7.9 D-12)" means spec `01_merks.md`, section 7.9, item D-12. Every factual
  statement about a model cites its spec. The specs cite the PDFs and code.
- Reference files live in `docs/references/`: the PDFs, `supplementary/` and `codebases/`
  (see `codebases/SOURCES.md`).
- Status evidence cites the design docs (AUTHORING, AUDIT, DECISIONS, ROADMAP) or code
  files. It was re-checked against the tree at `d154fc9`.
- Policy (D-029, D-048): validation is ensemble/statistical with pre-registered tolerances.
  There is no bitwise or trajectory parity with any author's code.

Items 2 and 3 of the original list are deferred; the user handles them. Item 11 is Jafari
Nivlouei et al. 2021 (11 §8). Andasari et al. 2012 is kept only as the G9 ODE-component
conformance test (11 §8).

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
| 6 | [06_jiang2005_tumor.md](06_jiang2005_tumor.md) | `06_Jiang2005_BiophysJ_multiscale-avascular-tumor.pdf`; erratum external (06 §3.4) | none | **C** | T, Eq 4 α and θ, lattice size, neighbourhood and γ are missing, and the Rb → E2F polarity blocks implementation (06 §3.3, §7.1 item 2) | **Medium.** Single-run simulation curves against experimental points: growth, rim, phase fractions (06 §5 T1–T12) |
| 7 | [07_bauer2007_sprouting.md](07_bauer2007_sprouting.md) | `07_Bauer2007_BiophysJ_sprouting-angiogenesis.pdf` | none | **C** | Pixel size, tissue-cell layout, degradation rate and baseline proliferating cell are UNSPECIFIED (07 §3.3) | **Medium–strong.** Table 2 speeds and diameters with n = 12 (07 §5 W2–W3) |
| 8 | [08_fbca.md](08_fbca.md) | `08a_Graudenzi2020_JCellAutomata_FBCA.pdf`, `08b_Maspero2020_FundInform_FBCA-nutrient-diffusion.pdf` | none; the ACRI 2018 base paper and the HMR CORE model file are not on disk (08 §1) | **C** | 08b's parameters are "as in [18]" (unavailable). The averaging coefficient D, the starvation rule and the edge efflux are UNSPECIFIED (08 §3, §7) | **Medium.** 20-run distributions for 08a SC1/SC2; digitised 08b curves (08 §5) |
| 9 | [09_cell_sorting.md](09_cell_sorting.md) | `09a_GranerGlazier1992_PRL_cell-sorting.pdf`, `09b_Osborne2017_PLoSCB_comparing-individual-based-models.pdf` | `codebases/09b_Osborne2017_Chaste_CellBasedComparison2017/` (09 §1) | **A** (Osborne CP) / **B** (Graner–Glazier) | OS: paper Table 1–2 plus Chaste code (the core rules were read at 2026 develop, not the 2017 release) (09 §1). GG: energies and T are complete; lattice size, cell count and the relaxation recipe are in PRE 47, 2128 (1993), which is not on disk (09 §7 A-GG5) | **Strong.** OS Fig 3 curves with n = 10 across k_pert; GG Fig 2 log-law fractions (09 §5) |
| 10 | [10_akeeb_invasion.md](10_akeeb_invasion.md) | `10_Akeeb2026_PLoSCB_tumor-invasion-fingering.pdf` | `codebases/10_Akeeb2026_Leader_Follower_Invasion_Model/` @ `0b9673f` with 13,310-run `Data/invasion_metrics.csv` (10 §1, §5.1) | **A** | CC3D XML and steppables plus the authors' full sweep output (10 §5.1) | **Strongest.** Per-point ensemble means ± SD from the authors' own data (10 §5.1–5.2) |
| 11 | [11_multiscale.md](11_multiscale.md) (item 11 = 11a) | `11a_JafariNivlouei2021_PLoSCB_multiscale-tumor-angiogenesis.pdf` (`11b_Andasari2012_…` for the ODE test only) | `supplementary/11a_JafariNivlouei2021_S1Data.xlsx` (plotted data only); no code (11 §1, §9) | **C** | χ values, hypoxia and necrosis rules, the nutrient unit conversion, the Wnt input and the PDE solver are UNSPECIFIED (11 §7 items 1–8) | **Strong data, weak provenance.** S1 Data backs 10 figures, but most series are single runs and several are internally inconsistent (11 §9.3) |
| 12 | [12_zajac_convergent_extension.md](12_zajac_convergent_extension.md) | `12a_Zajac2000_PRL_convergent-extension_arXiv.pdf` (analytic), `12b_Zajac2003_JTheorBiol_anisotropic-differential-adhesion.pdf` (CPM) | none; the 2002 thesis is unavailable (12 §1) | **C** | Almost every numeric value of the CPM is absent; only acceptance rates and anisotropy % are given (12 §3, §7 A-Z2) | **Weak.** One trajectory "chosen unscientifically" (12 §7 A-Z10). The analytic Eq. 7 is an exact unit test (12 §5 V-Z8) |
| 13 | [13_starruss_myxobacteria.md](13_starruss_myxobacteria.md) | `13_Starruss2007_JStatPhys_myxobacteria.pdf` | none (13 §1) | **B** | Table I gives every energy parameter. The lattice size, MCS definition, θ normalisation and run lengths are UNSPECIFIED (13 §3, §7 items 1, 5) | **Medium–strong.** Ψ̄(κ) at 3 densities, velocity and efficiency vs κ with n = 15 (13 §5 V4–V12) |
| 14 | [14_nucleus_migration.md](14_nucleus_migration.md) | `14a_Fortuna2020_BiophysJ_nucleus-migration.pdf` (base), `14b_Thomas2022_…_arXiv.pdf`, `14c_DalCastel2025_…_arXiv.pdf` | `codebases/14a_Fortuna2020_Crawling/` (SF1_Code), `codebases/14c_DalCastel2025_Single_Cell_Chemotaxis_2.3/`, `codebases/14c_DalCastel2025_CC3D-Chemotaxis-SuppMat/` (14 §1) | **A** | Both codes are released with Table 1/2 and SM tables. Provenance caveat: the 14a zip was repackaged in 2021 (14 §9 item 17) | **Strong.** Table 2 Fürth fits, the regime map and the 14c-SM efficiency tables (14 §7) |

---

## 2. Unified feature list

> **Pending revision (2026-09-30).** The architecture review
> [`../feature-roadmap-review.md`](../feature-roadmap-review.md) (commits 91873f0, f53dc29;
> a *proposal*, not yet approved) regroups G1–G21 into R0–R16 and corrects this list:
> - G1: CorePotts has no create event (`lifecycle.jl` has divide, remove, transition only).
> - G4 soft connectivity is an additive drive over a connectivity *value*
>   (`@drive copy => E₀*(components(old) > 1)`), not a new constraint kind.
> - G8: kind-restricted sources (`@constraint kind[new] == k`) and time-in-drive (a model
>   variable) already work.
> - G16 = frozen kinds + layouts; G18 (gathers) and G19 (`integral` with a mask) are covered;
>   G20 is needed only for multi-cell 14c.
> - New gaps not in G1–G21: division plane from an expression/draw (FBCA), field writes at
>   copy time (08b), kind classes, ownership hooks on every ownership change, component
>   scope across transitions, explicit phase order, declared footprints for non-local
>   reads, a solver per field.
>
> Once the maintainer decides on the review, §2, §3 and §6 will be rewritten against the
> R-list. Until then, G-ids here remain the spec-facing ids.

### 2.1 Crosswalk: spec-local G14+ ids → unified ids

The base list G1–G13 is shared by every spec. Each spec proposed its own G14+, and the
numbers collide. The unified ids are:

| Spec | Local id | Local description | Unified id |
|---|---|---|---|
| 01 | G14 | saturating/receptor-occupancy chemotaxis law (01 §6) | **G3** (expression over `c[source]`, `c[target]`); library `Chemotaxis(law = Saturating(s))` is planned (AUTHORING §12.2) |
| 01 | G15 | frozen border sites with their own J (01 §6) | **G16** |
| 04 | G16 | explicit time in energy terms (04 §6) | **G8** (time in proposal scope) |
| 04 | G17 | multi-phase protocol: anneal → relax → coarsen → relax (04 §6) | **G14** |
| 04 | G18 | row-restricted energy terms (04 §6) | **G3** (position in contact scope) |
| 05 | G15 | coupled operator-split schedule (05 §6) | **G15** |
| 06 | G14 | absorb/merge-retire into a collective cell (06 §6) | **G17** |
| 06 | G15 | operator split ¼ MCS ↔ 45 min PDE (06 §6) | **G15** |
| 07 | G15 | operator split 1 MCS ↔ 1 h PDE (07 §6) | **G15** |
| 08 | G14 | user-defined discrete field operator (08 §6) | **G18** |
| 08 | G15 | explicit per-MCS step schedule (08 §6) | **G15** |
| 09 | G14 | timed parameter change / staged protocol (09 §6) | **G14** |
| 10 | G14 | "repeat until ratio" at init (10 §6) | **G13** (no new feature) |
| 11 | G14 | "as in 08", not required (11 §6) | **G18** (not needed by item 11) |
| 11 | G16 | timed parameter and intervention schedule (11 §6) | **G14** |
| 11 | G17 | population-level gates (division cap) (11 §6) | **G1** (population fold in a lifecycle `when`) |
| 12 | G14 | cell-pair contact-segment aggregation (12 §6) | **G21** |
| 13 | G14 | hexagonal 2D lattice with neighbour shells (13 §6) | core, **EXISTS** (2D `Hexagonal()`, M2.1b; AUDIT fix log group 1b) |
| 13 | G15 | per-sub-cell freeze/pin (13 §6) | **G16** |
| 14 | G14 | derived site fields from lattice predicates (14 §8) | **G18** |
| 14 | G14b | site-set reductions: mean and std over filtered cell sites (14 §8) | **G19** |
| 14 | G15 | windowed average / ring-buffer history (14 §8) | **G20** |

### 2.2 The features

Status legend:
- **EXISTS**: usable from the public `@potts_model` surface.
- **PARTIAL**: part exists (named), and the rest is missing.
- **PLANNED**: specified in AUTHORING but not implemented (AUDIT §6).
- **MISSING**: not specified anywhere yet.

Every feature must land as a general public feature. A model may not get a hook named after
it (ROADMAP rules; AUDIT P-15).

| Id | Feature | Needed by (● required, ○ variant/observable) | Status (evidence) | Accuracy vs performance choice it implies |
|---|---|---|---|---|
| **G1** | Lifecycle rules `@transition`/`@create`/`@retire` plus `rand(Bernoulli(p))`, `rand(Uniform)`. Includes population gates such as "no division once N > 500" (11-G17) | 05, 06, 07, 08, 10, 11, 09 (init labels) | **PARTIAL.** CorePotts lifecycle has divide, remove, transition and create (M2.8; `lib/CorePotts/src/lifecycle.jl`). The symbolic layer exposes only `@divide` (`src/macro.jl:396`). `@retire`/`@create`/`@transition` and `rand(Bernoulli)` are documented but unsupported (AUDIT §6). Uniform `rand()` exists (AUTHORING §12.6) | Rules are evaluated at the MCS boundary. Per-copy triggers are not planned; no model needs them |
| **G2** | Shape descriptors in energies: inertia tensor, `major_length`, eccentricity ε, orientation; perimeter | 01 (E), 12, 09 (OS perimeter), 13 (segment COMs) | **PARTIAL.** `major_length` is an energy built-in with exact ΔH (`src/compile.jl:47`; `CorePotts.major_length_after`; D-049 F-3). `surface` exists. `inertia`, eccentricity and orientation in energies are not available (AUDIT §6), and `centroid` is barred from energies (AUTHORING §12.2) | Exact per-copy eigen-update (Zajac per paper, 12 §2.2) vs a per-MCS lagged value. Merks' exact form already exists |
| **G3** | Contact/copy-scope quantities: source/target roles, interface type, field at both sites, position, copy direction `d = target − source`, cell state of both owners, lagged vector cell variables | 01, 04, 05, 07, 10, 11, 12, 13, 14 | **PARTIAL.** Drives read `source`/`target`/`new`/`old`, `kind[·]`, `c[·]` (AUTHORING §5). Contacts read `y[owner]` and `y[owner′]` (§4). `displacement(c, k)` is scalar (§12.2). `position` is Cartesian (D-043). The vector names `direction`, `normal`, `δcentroid` are planned (§12.2). Lags of cell variables are rejected (AUTHORING §6) | Zajac: exact per-copy axes vs a lagged director (12 §5 acceptance test). Merks: Float vs integer-truncated ΔH (01 §7.9 D-7) |
| **G4** | Generalised connectivity: local ring rule, soft penalty (including a threshold-shift form), exact BFS component count | 01 (E), 05, 10, 11; 13 and 14 (diagnostic only) | **PARTIAL.** Hard veto `connectivity(kinds; rule = :local \| :merks)` (`src/vocabulary.jl:362–371`, `src/codegen.jl:274–278`, `lib/CorePotts/src/drives.jl`). There is no soft penalty and no BFS. The model-named rule `:merks` and `merks_connectivity` are open hygiene (AUDIT P-15) | An exact BFS per copy costs O(cell size) (Bauer 2009 α = 300; Jafari α = 300) vs a local-ring approximation. Soft vs hard (Akeeb 1e5 ≈ hard at T = 10, 10 §7.1 P2) |
| **G5** | Fields: symbolic per-face BCs (Dirichlet/periodic/absorbing, moving kind-defined Dirichlet), SteadyState solve, implicit transient step, coarse grid, static analytic fields | 01, 05, 06, 07, 08, 10 (static), 11, 14 | **PARTIAL.** Explicit Euler with automatically stable substeps and `Δ` (AUTHORING §6; AUDIT fix log A-64). CorePotts supports per-face Dirichlet (`lib/CorePotts/src/fields.jl:14–39`), but Potts does not expose it (AUDIT A-04). `@boundary` and quasi-steady `0 ~ …` are planned (AUTHORING §12.5; AUDIT §6). No coarse grid | Paper substeps (Merks 15 × Δt = 2 s) vs the fewest stable substeps (D-049; 01 §2.7). Jiang 2005: transient 45 min vs quasi-steady (06 §2.5, §3.2) |
| **G6** | Conservative per-cell or per-site secrete/uptake: min(β, V) sinks, site-set sums, sequential randomised-order sharing | 01, 05, 06, 07, 08, 11 | **PLANNED.** `secrete`/`uptake`/`consume` (AUTHORING §12.5). Masked source/sink terms in `D(c) ~ …` work today (Merks, `lib/PottsModels/src/merks.jl`) | FBCA impermeable cells: sequential random-order LP + field write-back (exact, 08 §2.2) vs parallel |
| **G7** | Site conversion `@convert`: kind changes of individual sites between siblings or collectives, with budgets and sequential re-evaluation | 05 (degradation), 07, 08 (08b nutrient displacement), 14 | **MISSING** | Sequential conversion with p recomputed after each conversion (14 §2.9.5) is inherently serial; it runs at the MCS boundary, off the hot path |
| **G8** | Pluggable proposal and acceptance law: boundary-only / unlike-neighbour proposals, kind-restricted copy sources, declared proposal relation ≠ contact relation, attempts per MCS, threshold offset, T = 0 tie policy, time `t` in proposal scope | 01, 04, 07, 08, 09, 10, 12 | **PARTIAL.** `Metropolis(; temperature, offset)`, `Barker`, and the T ≤ 0 tie at ½ (AUTHORING §12.1). Models declare `@relations proposal = …` (D-049 F-1). Custom proposal distributions and a time-in-drive scope are MISSING | Foam and Zajac boundary-only proposals change the time normalisation (04 §7 A-5; 12 §2.2). Checkerboard vs sequential for cluster-coupled energies (see G10) |
| **G9** | Per-cell component protocol: ODE, Boolean network (or lookup table), FBA LP. Inputs from fields and contacts; outputs to kind and parameters; inherit on division | 06 (Boolean), 08 (FBA), 11 (Boolean; 11b ODE test), 10 (clock state) | **PARTIAL.** MTK ODE components per cell (D-038; M4.1 partial). Boolean networks are planned (AUTHORING §12.6). FBA via COBREXA as a package extension is planned (D-030) and absent | FBA per cell per MCS dominates the cost (08 §2.2: 3–6 s/MCS in MATLAB). Degenerate optima need a fixed tie-break (08 §5 policy). Boolean: table lookup (what 11a ran) vs the full network (11 §2A) |
| **G10** | Cluster scope: cluster trackers, `sibling(kind)`, retain-empty members, intra- vs inter-cluster contact, collective generalized cells, contact-graph BFS | 05, 06, 07, 09 (obs.), 10 (obs.), 12 (array), 13, 14 | **PARTIAL.** Clusters with `clusters(k)` energies and `cluster_volume`/`cluster_surface` (D-036; M2.10a). The contact graph is host-side (M2.7; `lib/CorePotts/src/spatial.jl:85`). `sibling`, retain-empty and `neighbors(c)` are MISSING or PLANNED (AUTHORING §12.3) | Energies reading other members' state need `cluster_claims`: at most one change per cluster per colour on checkerboard (D-036). Myxobacteria sequential vs checkerboard (§4) |
| **G11** | Ordered relationships (chain index ν) and 2- and 3-body geometry energies on member COMs (distance, circumradius) | 13 | **PARTIAL.** `@relationship`, `@link`/`@unlink` and `edges(name) => f(distance)` exist (M2.9; AUTHORING §7). Ordering and 3-body terms are MISSING | Incremental ΔH touches ≤ 3 triplets and 2 pairs per copy (13 §6) |
| **G12** | Observables library: boundary-length decomposition, compactness/hull, morphometry, T1 detection and topology moments, spectra, cluster tracking, MSD/Fürth fits, front profile/peaks, IVD, lineage | all | **PARTIAL (minimal).** `@observed`, `integral(x)` and SII indexing exist (AUTHORING §12.3). No library | Fit routines belong in analysis, not the core (14 §8). Some observables are measured on an annealed copy (09 §2.1) |
| **G13** | Initial layout generators: tilings, random scatter in a sub-region, Eden blobs + splits, brick wall, fibre networks, chains/rods, spheres/hemispheres, "insert until fraction" | all | **MISSING.** The `UniformSeeds`… layouts do not exist (AUDIT §6). Per-model state functions exist (`merks_state`, `akeeb_state`, `graner_glazier_state`) | – |
| **G14** | Staged protocols and timed interventions: parameter or kind changes at a given MCS, phases with stop criteria, receptor clamps from day d | 04, 09, 11, 11b | **PARTIAL.** SciML callbacks, `setp`/`integ.ps[:λ] = v` (from the next MCS), `remake` and checkpoint continuation (AUTHORING §8; M3.3). `@terminate` is planned (§12.7). No declarative protocol | None: this is off the hot path |
| **G15** | Explicit step schedule and operator splitting: ordered per-MCS phases, fractional-MCS sweeps (¼ MCS), physical time per MCS for field steps | 05, 06, 07, 08, 01 (PDE before CPM, 01 §7.4) | **PARTIAL.** `@before_mcs`/`@after_mcs`, dependency ordering (D-042), `mcs_duration` and field substeps (AUTHORING §6). Fractional sweeps are MISSING | Jiang 2005 ¼-MCS interleave (06 §2.4) |
| **G16** | Frozen/pinned sites and walls with their own contact energies (frozen border ring, substrate planes, per-cell pin) | 01, 14, 13 (pinned head), 04 (y-walls, A-2) | **PARTIAL.** `@kinds x[frozen]` exists (AUTHORING §2). `Wall(kind)` is documented but unsupported (AUDIT §6). A per-cell pin is MISSING | – |
| **G17** | Absorb-retire into a collective cell: the dead cell's sites join an existing collective, whose target volume grows | 06 | **MISSING** | – |
| **G18** | User-defined discrete field operators and derived site fields: masked averaging, reset-to-mean, indicator fields from lattice predicates at a declared cadence | 08 (08b), 14 (14c) | **PARTIAL.** Site/field updates with gather comprehensions over relations (AUTHORING §6) can express these; not yet exercised | Refresh cadence per MCS (stale within the MCS, 14 §4.2) vs per copy |
| **G19** | Filtered per-cell site-set reductions (sum, mean, std over sites matching a predicate) | 14 (14c), 08, 11 | **PARTIAL.** `integral(x)` in cell scope (AUTHORING §12.3); std via `integral(x²)`. Not usable in energies or drives | Recomputed at the MCS boundary (AUTHORING §12.3) |
| **G20** | Windowed and lagged cell histories (ring buffer, k-MCS moving average) | 14 (14c), 12 (lagged variant), 11b | **MISSING.** Lags of cell variables are rejected (AUTHORING §6) | Memory ∝ window × cells |
| **G21** | Cell-pair interface quantities: per-pair contact length, aggregated contact-point geometry, contact fraction per cell, and their per-MCS change | 12, 11 (11a inputs; 11b Eqs 10–11), 13 (cluster predicate), 10 (obs.) | **PLANNED.** `neighbors(c)`/`contact(c, n)` (AUTHORING §12.3; AUDIT §6). The CorePotts contact graph exists host-side (M2.7) | Zajac exact ΔE: O(neighbours of two cells) per copy with pair aggregation (12 §6) |

---

## 3. Feature × model matrix

● required for the default reproduction. ○ needed only by a variant, an observable, or a
diagnostic. The item 11 column is 11a; 11b (Andasari) needs G1, G3, G9 (ODE) and G14 (11 §6).

| | 01 Merks | 04 Foam | 05 Bauer09 | 06 Jiang05 | 07 Bauer07 | 08 FBCA | 09 Sorting | 10 Akeeb | 11 Jafari | 12 Zajac | 13 Myxo | 14 Fortuna |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| G1 lifecycle + draws | | | ● | ● | ● | ● | ● | ● | ● | | | ● |
| G2 shape in energies | ● (E) | | | | | | ● (OS) | | | ● | ○ | |
| G3 copy/contact scope | ● | ● | ● | | ● | | | ● | ● | ● | ● | ● |
| G4 connectivity | ● (E) | | ● | | ○ | ○ | | ● | ● | | ○ | ○ |
| G5 fields / BCs / solvers | ● | | ● | ● | ● | ● | | ○ | ● | | | ● |
| G6 secrete / uptake | ● | | ● | ● | ● | ● | | | ● | | | |
| G7 `@convert` | | | ○ | | ● | ○ | | | | | | ● |
| G8 proposal / acceptance | ● | ● | ○ | | ● | ● | ● | ● | | ● | | |
| G9 components | | | ○ | ● | ○ | ● | | ● | ● | | | |
| G10 cluster scope | ○ | ○ | ● | ● | ● | ○ | ○ | ○ | ● | ● | ● | ● |
| G11 ordered rel. / angles | | | | | | | | | | | ● | |
| G12 observables | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| G13 layouts | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| G14 protocols | ○ | ● | | | ○ | ● | ● | | ● | ○ | | |
| G15 schedule / splitting | ● | | ● | ● | ● | ● | | | ○ | | | ○ |
| G16 frozen / pinned | ● | ○ | | | | | | | | | ○ | ● |
| G17 absorb-retire | | | | ● | | | | | | | | |
| G18 field operators | | | | | | ● | | | | | | ○ (14c) |
| G19 site-set reductions | | | | ○ | | ● | | | ● | | | ○ (14c) |
| G20 windowed history | | | | | | | | | | ○ | | ○ (14c) |
| G21 pair interface | | | | | | | | ○ | ● | ● | ○ | |
| hex lattice (core) | | | | | | | | | | | ● | |

Notes on the matrix:
- Item 10's G9 entry is the per-cell integer clock state (10 §6). It works today as cell
  variables.
- Item 09's G1 entry is the timed Bernoulli label draw (09 §6).
- Items 06 and 14 are **3D**; item 11b is 3D and is out of scope as a reproduction (11 §8).

---

## 4. Decisions (approved)

The user chose "decide per model" for paper-vs-code conflicts. **On 2026-09-30 the
maintainer approved every recommendation in §4.1–§4.12 as written ("approve all"),
including the items marked "(reopens D-049)".** Each "Recommendation" column below is
therefore the decided default, and each named alternative is the documented variant.
Items that depend on an unanswered author question (§5) keep the recommended default
until the author answers.

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
| M2 | 2006 target length L: paper "about 100 µm" = 50 px vs 60 px in every "Fig. 4 of Merks 2006" file (01 §7.9 D-12) | 50 / 60 | **50 px** default, `L = 60` variant | The files are a 200² "small field" demo, not the published run (01 §7.9 D-16). The paper text is the only statement about Fig 4. Ask Merks (§5) |
| M3 | 2006 connectivity: soft threshold shift E₀ on 8-ring-breaking copies (code), vs today's hard one-arc veto (D-049) (01 §7.3) | soft E₀ = 5000 / soft 2000 / hard veto | **Soft E₀ = 5000** once G4 soft exists; hard veto as a variant (**reopens D-049**) | 5000 is in `longcells.par`, the file labelled for Fig 4, and satisfies "E₀ > 2000" strictly. 2000 is only the generic default (01 §7.9 D-13). The code applies E₀ only to the losing cell (01 §7.3) |
| M4 | Frozen 1-px border with J(c,B) = 100, J(M,B) = 0 vs free closed walls (D-049) (01 §7.5) | frame / free walls | **Frame** via G16 (**reopens D-049**) | The paper states it (01 §2.1) and the code implements it |
| M5 | Field: 15 FTCS 5-point substeps of Δt = 2 s, PDE **before** the CPM sweep, absorbing c = 0 ring, c₀ = 0; vs the fewest stable substeps (D-049) (01 §7.4) | paper/code schedule / fewest stable | **Paper/code schedule** (**reopens D-049**) | It costs almost nothing (D·Δt/Δx² = 0.05 is already stable, 01 §3.1). The absorbing BC matters on 200² (01 §7.9 D-10) |
| M6 | 2008 relaxation: 100 MCS with no PDE (and so no chemotaxis) in every Dataset S1 file, not in the paper (01 §7.9 D-5). The 2006-labelled files use 0 (01 §7.8), which corrects AUDIT P-14's wording | include / omit | **Include for 2008, omit for 2006.** Report time both from code MCS 0 and from the end of relaxation until Merks answers | The code produced the figures. The time origin is open (01 §8 A-19) |
| M7 | 2008 chemotaxis scope. The current `contact_inhibited = true` gate is `old == 0 && kind[new] == endothelial` (extension into the medium only). The 01b default is **extension + retraction** at cell–medium interfaces with χ(c,c) = 0 (01 §7.2, §7.9 D-3) | model χ(c,c) and χ(c,M) as real parameters, plus a `mode = :extension_retraction \| :extension_only` switch | **Adopt**. Default `:extension_retraction` with χ(c,c) = 0 and χ(c,M) = 500 | The current option reproduces only the Figs 11–13 variant. The continuous χ(c,c) is a superset the paper's Fig 5 sweep needs (01 §8 A-20). It also removes the model-named `extension_only` (P-15) |
| M8 | Saturating chemotaxis c/(1 + s c) per site (01 §2.3) | expression / library law | Expression in the drive now, `Chemotaxis(law = Saturating(s))` later | G3 already allows it |
| M9 | Integer-truncated ΔH (01 §7.9 D-7) | Float / Int | **Float**, with no variant | D-029. The spec expects a statistically benign deviation. Fig 13's cumulative ΔH bookkeeping must be defined explicitly (V-C11) |
| M10 | 01b Fig 2 geometry: paper (1000 cells, 333² in ~500²) vs files (360 seeds on 200²) (01 §7.9 D-1) | paper / files | **Paper** for V-C1. Files as a density-matched small variant | The figure is the target. The enclosing lattice is garbled (A-9): ask |
| M11 | Seeding: Eden growth plus splits (code) vs square blocks (current `merks_state`) (01 §7.6) | Eden (G13) / blocks | **Eden** for 2008 (sprout 1 blob, 7 splits = 128 cells); blocks acceptable for 2006 until G13 | The 2008 relaxation inflates 15-px cells to A = 50; the start state matters for Figs 5–11 |

### 4.2 Foam (04), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| F1 | Shear term: literal Σ_i γ(y_i,t) x_i (1 − δ) vs per-flip displacement γ(y_i,t)·(x_i − x_j) with minimum image (04 §7 A-1, A-10) | literal / displacement | **Displacement**, with γ₀ **calibrated via γ₀/J scaling** against V3/V5 (transition γ₀/J ≈ 1.9). Literal as a variant, documented as ill-posed on periodic x | Fig 3(c) boundaries are lines through the origin, which a position-independent per-flip bias explains (04 §3.2, A-1). Ask Jiang/Glazier |
| F2 | T = 0 with ΔH′ = 0: accept (T → 0⁺), ½ (engine default, GG convention), or reject (04 §7 A-6) | 1 / ½ / 0 | **Accept (1)**, the spec's recommendation, recorded as a choice. ½ as a variant | Eq 3 puts ΔH′ = 0 in the exponential branch, and exp(−0/T) → 1 as T → 0⁺. Needs a G8 tie-policy option |
| F3 | Lattice: text 400 × 100 with 20² bubbles vs figures 256² with 16² (04 §7 A-7) | – | **256², 16²** | Every shown figure (resolved) |
| F4 | y-boundary type (04 §7 A-2) | free closed wall / frozen wall rows (G16) | Pick the option whose relaxed ordered foam gives μ₂(n) ≈ 0.44 (V1b). Report both | Unstated. V1b is the only discriminating target |
| F5 | Proposals: boundary-only, unlike-neighbour (04 §2.3) vs plain Metropolis; attempt counting for non-wall picks (A-5) | exact law / plain | **Exact law** (G8). Count all-site attempts per MCS, and compare only timing-free targets | At T = 0, interior picks are null anyway. Only the time axis differs, and targets avoid absolute MCS (04 §7 A-5) |
| F6 | T1 counting unit (even bars suggest double counting, A-15) | configurable | Configurable; ratios only | – |

### 4.3 Bauer 2009 (05) and Bauer 2007 (07), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| B1 | Two parameterisations (05 §7.3) | one model with variants / two models | **Two models, two tutorials** | Every parameter, the time scale and the rules differ (05 §7.3; 07 §7.2) |
| B2 | Pixel size unknown. (0.55 µm)² degradation and 1.1 µm bundles fit 0.55 µm/px, but that "must not be adopted without author confirmation" (05 §7.2) | wait / provisional 0.55 µm | **Block both tutorials on Jiang's answer.** Develop with 0.55 µm labelled as a hypothesis | The spec forbids silently adopting it |
| B3 | 2009 domain 166 × 106 µm (figure axes) vs "100 µm by 160 µm" (p.6) (05 §7.1 item 1) | – | **166 × 106** | The figures use it |
| B4 | 2009 speed: Table 2 16.0 µm/h "averaged over 14 hours" vs Fig 1A ≈ 10 µm/h at 14 h (05 §7.1 item 2) | – | Validate against the **Fig 1A curve** (V1). Record Table 2 as unexplained | The curve is the primary data |
| B5 | Continuity: exact BFS soft penalty α = 300 (05 §2.3) vs a local-ring approximation | exact / local | **Exact BFS** default. Local ring as a validated performance variant | Table 3's kT < 0.25 regime depends on it (05 §6 G4) |
| B6 | Uptake B = min(β, V) per EC site vs per EC (β is per cell per hour) (05 §7.2; 07 §7.1 item 4) | per site / per cell | **Per cell** (G6, conservative) default; per site as a variant | The units say per cell; per-site uptake multiplies uptake by cell area |
| B7 | 2007 IC: V = 0 vs steady state (07 §7.1 item 1) | – | **Steady state** (G5 SteadyState) | That is what the hybridization section describes |
| B8 | 2007 kind-restricted copy sources ("only ECs invade") (07 §6 G8) | restricted / free | **Restricted** (G8) | The text says so. Ask |
| B9 | 2007 baseline proliferating cell = the one immediately behind the tip (07 §7.1 item 3) | – | Adopt as a flagged inference | Table 2's baseline equals the Fig 5 8.9 µm point |

### 4.4 Jiang 2005 (06), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| J1 | Glucose rate b₀(P): 162 (PDF) vs 216 (external erratum) (06 §3.4, §7.1 item 4) | 162 / 216 | **162 default, `erratum = true` → 216.** This departs from the spec's suggestion | C₀ = 240 ≈ 1.5 × 162 and Q/P ≈ ½ only hold with 162. That suggests the published simulations were built on 162. Ask Jiang which produced Figs 5–8 |
| J2 | Unfavourable chemistry: Fig 3 flow chart (P dies) vs text (P → Q, Q → N) (06 §7.1 item 1) | text / chart | **Text**; flow chart as a variant | Biologically coherent; the chart labels look swapped |
| J3 | Rb → E2F drawn stimulatory, which gives inverted biology (06 §7.1 item 2) | as drawn / inhibitory | **Blocking: ask first.** Provisional default inhibitory, flagged | As drawn, E2F turns on only when the CKIs are on |
| J4 | Necrosis conditions AND vs OR (06 §2.4) | – | **OR**, flagged | "are conditions for cell necrosis". Ask |
| J5 | GF/IF diffusivity: Table 1 10⁻⁶ both vs text 10⁻⁷/10⁻⁶ (06 §7.1 item 3) | – | **Table 1**, plus a sweep (T10) | – |
| J6 | Necrotic inhibitor secretion: 2 %/h/cm³ (Table 1) vs 0.1 ml/h (Appendix) (06 §7.1 item 5) | – | **Table 1** | Unit-compatible with the other rates |
| J7 | Transient 45-min solve per ¼ MCS vs quasi-steady (06 §2.5, §3.2) | implicit transient / SteadyState | **Implicit transient** (G5 + LinearSolve ext), quasi-steady as a performance variant | D_O₂ ≈ 2.5 × 10⁶ voxel²/MCS makes O₂ quasi-static anyway (06 §3.2) |
| J8 | The lattice-size artefact of Fig 8 (06 §5 T9) | reproduce / larger lattice | **Larger lattice** (deliberate deviation) | The spec says not to reproduce the artefact |

### 4.5 FBCA (08), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| X1 | Degenerate LP optima (08 §2.2, §7 item 5) | plain FBA / pFBA / lexicographic | **pFBA** (a deterministic tie-break), declared | Lactate phenotype classification depends on it |
| X2 | Impermeable cells: sequential random-order FBA with write-back (08 §2.2) vs parallel | sequential / parallel | **Sequential**, as written | It is a conservation rule, and LP cost dominates regardless |
| X3 | Eq 6 averaging is non-conservative for D ≠ 1 (08 §2.2) | as written / conservative | **As written** (G18), with D as a calibration parameter | The paper's operator. Ask the authors for the D values |
| X4 | Biomass on division (08 §6 G9) | halve / by area | **Halve** | Consistent with ρ = 1/F at initialisation |
| X5 | Metabolic model: HMR CORE (240 × 272) is not on disk (08 §7 item 13) | – | **Blocking**: obtain it (Di Filippo 2016 supplementary) | – |

### 4.6 Cell sorting (09)

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| S1 | GG initial state follows PRE 47, 2128 (1993) §II D3 (D-049 F-2), a paper **not on disk** (09 §7 A-GG5) | – | Keep it, but mark it "external source, not verified on disk" in the tutorial until the PDF is added | Provenance honesty |
| S2 | GG "two T = 0 annealing steps": on a copy vs on the trajectory (09 §7 A-GG4) | copy / trajectory | **On a copy** (a measurement), with a trajectory variant | "before calculating the statistical properties" reads as a measurement |
| S3 | OS: which type is engulfed (09 §7 A-OS1) | – | **A engulfs B** (B = labelled) | Parameters, S1 Movie and Fig 2 agree; the p.11 wording is the outlier |
| S4 | OS: VN contact / Moore proposal from 2026 Chaste develop, not the 2017 release (09 §7 A-OS4) | – | **Follow the code**, flagged | The only concrete source |
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
| N2 | β in mol/cell/s vs n in pg/voxel (11 §7 item 1) | Per-cell conservative uptake (G6), converted by the cell volume inferred from Table 4 (flagged inference) | – |
| N3 | χ values missing (11 §7 item 7) | **Calibrate** χ_EC to V11a-2 sprout speed and χ_tumour to V11a-5, and label them as calibrations | No other source |
| N4 | Boolean: Fig 3 lookup table (runtime) vs full network (11 §2A) | **Table** default. The network is a unit test (V11a-1) after fixing β-catenin precedence | What the paper ran |
| N5 | Continuity a′ (Eq 3): exact BFS vs local | Same choice as B5 | Same α = 300 lineage |
| N6 | S1 Data vs text numbers (11 §9.3) | **Sheet values** are targets; text values are recorded, not enforced | The sheets are the plotted data |

### 4.9 Zajac (12), no code

| # | Conflict | Options | Recommendation | Why |
|---|---|---|---|---|
| Z1 | **Exact per-copy axis** (segment-averaged, both cells re-evaluated) **vs lagged per-MCS director** (12 §2.2) | exact / lagged | **Exact** is the reference default (needs G21 + G2). Lagged ships as a performance variant **only if** it passes the pre-registered acceptance test (12 §5) | The paper updates per copy. The lagged director removes the non-local energetic effect (12 §2.2) |
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
| C3 | F-actin: PDE (14a code) vs binary indicator (14c) (14 §9 item 1) | **PDE** for 14a/14b; **indicator** (G18) for 14c | Each paper's own code |
| C4 | Secretion vs decay order inside CC3D `DiffusionSolverFE`: F ≈ 1 vs F ≈ 0.1 at the source, a **10× difference in protrusion strength** (14 §9 item 15) | **Blocking**: read the CC3D 3.7.9 source or ask. Calibrate against Table 2 in the meantime | – |
| C5 | Initial condition: suspended cell (Fig 4A) vs tangent ball + 6³ nucleus (code, 14b) | **Code** | Resolved (14 §9 item 9) |
| C6 | 14c gate: δ, strict "<" vs "≤", window includes the current MCS (14 §9 item 10) | **Code** (δ = 0, ≤, includes current) | – |
| C7 | Protrusion on retraction (Medium overwriting FRONT) (14 §9 item 16) | **Eq 7** (FRONT source → Medium target only) | – |

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
| Boundary-only proposal laws | 04, 12 | Implement as G8 laws; compare only timing-free targets |

---

## 5. Questions for the authors (invitations to collaborate)

Blocking questions come first in each list, marked **[B]**. The tutorial's §6 repeats each
model's list.

### Yi Jiang (PI): Jiang 1999, Jiang 2005, Bauer 2007/2009, Akeeb 2026

1. **[B] Bauer 2007/2009:** µm per pixel, lattice geometry, and the neighbourhood order for copies, adhesion and the BFS (05 §7.4 q1; 07 §7.3 q1).
2. **[B] Jiang 2005:** Rb → E2F polarity in Fig 2, and each node's on-state meaning (06 §7.3 q2).
3. **[B] Jiang 2005:** values of T, α, θ (Eq 4), γ_P, "large" γ_N and the lattice size (06 §7.3 q1).
4. **[B] Jiang 2005:** 162 vs 216 for the published figures; units of Table 1 (06 §7.3 q5).
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
3. **[B] Fortuna:** secretion/decay order in CC3D 3.7.9 `DiffusionSolverFE`, and whether the SF1 code produced the figures (14 §9 items 15, 17).
4. Zajac: the extension measure plotted in Fig 5 (A-Z5); I in the shape constraint (A-Z7); the proposal neighbourhood (A-Z9).
5. Graner–Glazier: the PRE 47, 2128 (1993) set-up (lattice, BCs, N, type fraction, relaxation parameters); annealing on a copy or not (09 §7 A-GG1…A-GG5).
6. Foam (co-author): the same as items 5 and 7 of the Jiang list.

### Roeland Merks

1. **[B]** 01a supplementary methods: L (50 vs 60 px), E₀ (2000 vs 5000) and the real Fig 4 geometry (01 §7.9 D-12, D-13, D-16; §8 last list).
2. **[B]** Whether the paper's MCS counts include the 100-MCS relaxation (01 §8 A-19).
3. The analysis scripts for compactness and H − H₀ (01 §7.9 D-17, D-18; A-14); morphometry code (A-18).
4. Parameter files for 01b Figs 3, 5, 7–10, 12–13, and the code for the continuous χ(c,c)/χ(c,M) sweep (D-2, D-3; A-20).
5. The enclosing lattice for Fig 2 (A-9) and the Fig 10/12 lattices (A-10).

### Rita de Almeida, Gilberto Thomas, Pedro Dal-Castel

1. **[B]** J_cyto–lamellipodium: 20 (Table 1) or 10 (code) for the 14a figures (14 §9 item 3).
2. **[B]** The F-actin magnitude at source sites (solver order) (item 15).
3. The 14c gate details: δ used for the figures, "<" vs "≤", and whether the current MCS is in the window (item 10).
4. The 14c-SM Table S1 S column (item 11); the Fig 8 caption (item 12); a diff of arXiv v1 against the 2025 version of record (item 13).
5. The chemotaxis plugin on retraction (item 16); which polarization measure Fig 12 used (14 §2.9.7 item 12).

### James Osborne / Alexander Fletcher

1. **[B]** The engulfment-direction sentence on p.11 (09 §7 A-OS1).
2. The units of the Fig 2/4 time labels (A-OS2); the Fig 3 time origin and the normalisation script (A-OS3).
3. Whether the 2017 Chaste core used VN contacts and perimeter (A-OS4); the smoother used for the fluctuation metric (A-OS6).

### Andreas Deutsch / Jörn Starruß

1. **[B]** θ: unit vector or raw chord (13 §7 item 1); the Eq 7 sign (item 2); the Eq 10 loser term (item 3).
2. **[B]** Lattice size, MCS definition, warm-up, sampling and run lengths for Ψ̄ (item 5).
3. The "second-nearest" shell (item 4); κ(s) and Fig 6 (item 6); density and κ for the Fig 8 right panel (item 7); initial conditions (item 8); head fixation (item 9); measurement intervals (item 10); degenerate curvature (item 11); same-cell J (item 12).

### Chiara Damiani / Alex Graudenzi / Davide Maspero

1. **[B]** MATLAB sources and the HMR CORE model file; the ACRI 2018 parameters (λ, k_BT, attempts, initial fields) (08 §7 items 12–13).
2. **[B]** The starvation-death rule (item 10); Eq 6 D values and sweeps per MCS (item 8); the edge efflux value (item 9).
3. Units (item 1); the periodic axis and top boundary (item 2); ρ definition (item 3); biomass split (item 4); tie-breaking of degenerate optima (item 5); the uptake bound form (item 6); SC1/SC2 nutrient bookkeeping (item 7); SC2 reaction ids and O₂ bands (item 11).

### Sahar Jafari Nivlouei / Madjid Soltani / Rui Travasso

1. **[B]** The CC3D project (11 §7 item 12).
2. **[B]** χ values and signs, and the neighbour order (item 7); the hypoxia, necrosis and apoptosis rules (item 5).
3. **[B]** Nutrient unit conversion (item 1); source term vs clamp (item 2); the PDE solver and steps (item 3).
4. The Wnt input and contact normalisation (item 4); host-cell parameters (item 8); β-catenin precedence (item 9); the clamped receptor (item 10); vessel geometry (item 11); the S1 Data inconsistencies (item 14).

---

## 6. Recommended build sequence

**Earlier order:** hygiene → sorting → Akeeb → Merks → Zajac → foam → Bauer07 → Bauer09 →
item 11 → Jiang05 → FBCA → Fortuna → myxo.

**Revised order:** hygiene → sorting → Akeeb → Merks → foam → Fortuna → myxo → Zajac →
Bauer07 → Bauer09 → item 11 → Jiang05 → FBCA.

Rationale:
- **Fortuna moves up, to step 5.** It is grade A with strong quantitative targets, and it
  introduces the cluster features G7, G10 and G16 that the Bauer and myxobacteria models
  reuse.
- **Myxobacteria moves up, to step 6.** It shares the one "cluster of sub-cells"
  abstraction with Fortuna (13 §6; 14 §8), so it should be built right after it.
- **Zajac moves back, to step 7.** It is grade C with weak targets, and it needs the
  heaviest new machinery (G21, eigen-shape ΔE).
- **The Bauer models and Jiang 2005 are blocked** on answers from Yi Jiang. The questions
  go out at step 0, so the answers arrive before those steps.

| Step | Model(s) | New features introduced | Gate |
|---|---|---|---|
| 0 | **Hygiene and infrastructure** | Rename the model-named primitives: G4 local ring rule with descriptive names, soft-penalty form; drop `extension_only` for a G3 expression (AUDIT P-15). Basic G13 layouts. G12 core observables. G14 via callbacks. The Literate + Documenter "Published models" pipeline and `TUTORIAL_TEMPLATE.md`. Send author question batch 1 (§5) | – |
| 1 | **Sorting** (GG + Osborne CP): pilot tutorial | G8 tie policy and declared proposal (exists); G2 VN perimeter incl. lattice-edge edges; G1 timed Bernoulli labels; G14 staged protocol; G12 boundary-length decomposition and annealed-copy measurement | S1 provenance flag |
| 2 | **Akeeb** | G12 code-definition metrics (per-column areas, find_peaks, BFS clusters); G13 insert-until-fraction; G1 `@create` at init | A5 default μ |
| 3 | **Merks** (2006 + 2008) | G4 soft threshold penalty; G16 frozen frame J_cB; G5 exposed absorbing Dirichlet BC; G15 PDE-before-sweep with relaxation; G3 interface-typed χ(c,c)/χ(c,M) + saturation; G13 Eden + split; G12 compactness and morphometry | M1–M7 sign-off |
| 4 | **Foam** | G8 boundary-only proposal law and time in drive scope (sin ωt); G3 position and minimum-image displacement; G14 anneal/coarsen/relax protocol with a μ₂(n) stop; G13 brick wall; G12 T1 detection, topology moments, spectra | Provisional until F1 is answered |
| 5 | **Fortuna** (14a/14b; 14c later) | 3D run; G10 sibling-by-kind, retain-empty, intra/inter-cluster contact; G7 `@convert` (sequential); G16 frozen substrate/lid planes; G5 predicate-sourced PDE; G12 MSD/Fürth, Π vectors | C4 blocking for quantitative S/P/D |
| 6 | **Myxobacteria** | Hex lattice (exists); G11 ordered relationships + COM distance/circumradius energies; G3 copy direction d; G10 sibling COM lookup; G16 per-cell pin (V3 only); G12 cluster-graph Ψ̄ | Y1, Y2 |
| 7 | **Zajac** | G2 eccentricity and orientation in ΔE; G21 pair aggregation; G8 boundary-only proposal; G20 (for the lagged variant); exact-vs-lagged acceptance test; 12a Eq 7 unit test | Label as a reconstruction |
| 7b | **14c chemotaxis variant** | G18 indicator field; G19 site-set mean/std; G20 100-MCS window | – |
| 8 | **Bauer 2007** | G1 symbolic `@transition`/`@create`; G5 Dirichlet + periodic + SteadyState init + switchable source; G6 per-cell uptake; G7 degradation; G8 kind-restricted sources; G15 1 MCS ↔ 1 h; G13 fibre bundles + tissue grid | B2 (pixel size) |
| 9 | **Bauer 2009** | G4 exact-BFS soft penalty; G10 collective matrix/fluid; recruitment (G1 `@create` at the wall); G12 branch and loop detection | B2 |
| 10 | **Jafari Nivlouei 2021** (item 11) and the **Andasari ODE test** | G9 Boolean component (table + network test); G21 contact fractions; G5 two periodic PDEs with EC clamps; G14 therapy clamps; G9 ODE conformance test (11b Eqs 10–12) | N1–N3 |
| 11 | **Jiang 2005** | 3D; G9 Boolean with stochastic gating; G5 coarse grid, moving Dirichlet, implicit 45-min transient; G15 ¼-MCS sweeps; G17 absorb-retire; G6 state-dependent rates | J3 blocking |
| 12 | **FBCA** | G9 FBA component (COBREXA/JuMP extension, D-030); G6 sequential conservative sharing; G18 averaging operator; G15 explicit 6-phase order; G12 lineage/clone sizes | X5 blocking |
