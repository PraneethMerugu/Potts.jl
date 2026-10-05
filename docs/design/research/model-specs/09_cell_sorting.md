# 09 — Differential-adhesion cell sorting (Graner–Glazier 1992; Osborne et al. 2017 CP benchmark), paper-grounded spec

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **09a** | F. Graner, J.A. Glazier, "Simulation of Biological Cell Sorting Using a Two-Dimensional Extended Potts Model", *Phys. Rev. Lett.* **69**(13), 2013–2016 (28 Sep 1992) | 10.1103/PhysRevLett.69.2013 | `docs/references/09a_GranerGlazier1992_PRL_cell-sorting.pdf` (4 pp.) |
| **09b** | J.M. Osborne, A.G. Fletcher, J.M. Pitt-Francis, P.K. Maini, D.J. Gavaghan, "Comparing individual-based approaches to modelling the self-organization of multicellular tissues", *PLoS Comput Biol* **13**(2): e1005387 (2017) | 10.1371/journal.pcbi.1005387 | `docs/references/09b_Osborne2017_PLoSCB_comparing-individual-based-models.pdf` (34 pp.) |
| **09c** | J.A. Glazier, F. Graner, "Simulation of the differential adhesion driven rearrangement of biological cells", *Phys. Rev. E* **47**(3), 2128–2154 (Mar 1993) | 10.1103/PhysRevE.47.2128 | `docs/references/09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf` (40 pp.; see §8) |

**Page conventions.** 09a pages are journal pages 2013–2016 (PDF p.1 = 2013). The 09a text layer is OCR and garbles every equation, so the equations below were transcribed from the rendered page images. 09b pages are the PLoS "n / 34" numbers.

**Code (09b).** 09b p.9 points to `https://chaste.cs.ox.ac.uk/trac/wiki/PaperTutorials/CellBasedComparison2017`. It does **not** give a GitHub URL. The GitHub repository `https://github.com/Chaste/CellBasedComparison2017` (README: "contains the code used to produce results in the following paper", with the same DOI) mirrors that tutorial. It was read at commit `8bb7287d0dfb55316892707faab2945cca3d48ea` and is cited as `CBC:path:line`. **`CBC:…:N` abbreviates `CBC:test/TestCellSortingLiteratePaper.hpp:N`.** The Chaste core update rules it calls were read from `https://github.com/Chaste/Chaste` at develop commit `44724ebfbf775e100a48c5398064eb705b5da478` and are cited as `Chaste:file:line`. It is marked "external (not in our PDFs)". **Equivalence to the paper's core: VERIFIED 2026-09-30.** The CBC `Summary.wiki:19–29` says the paper used "a specific tagged development version of Chaste", tag `paper/CellBasedComparison`. That tag (`8593aabd1cc8191e802d07ea3dcc4116e8fb0ba9`, 2016-08-29) and `release_2017.1` (`84a42f8f2205b2c2b5bbe05e718cd807aabc4695`, 2017-12-21) were fetched from https://github.com/Chaste/Chaste and diffed against develop 44724eb for `PottsMesh`, `PottsMeshGenerator`, `PottsBasedCellPopulation`, every `*PottsUpdateRule` and `HeterotypicBoundaryLengthWriter`. The only differences are copyright years, comments, formatting, `NULL` → `nullptr`, pointer ownership in `PottsMeshGenerator`, removed helpers unrelated to the update (`IsPdeNodeAssociatedWithApoptoticCell`, `WriteDataToVisualizerSetupFile`) and an immersed-boundary visitor added later to the writer. The VN contact loop (release_2017.1 `cell_based/src/population/update_rules/AdhesionPottsUpdateRule.cpp:80`), the VN perimeter (`cell_based/src/mesh/PottsMesh.cpp:198–230`, `local_edges = 2*DIM` at :211), the VN surface-area rule (`SurfaceAreaConstraintPottsUpdateRule.cpp:87`) and the Moore proposal (`cell_based/src/population/PottsBasedCellPopulation.cpp:269–289`) are at the same lines as the develop citations below. Files: `docs/references/codebases/09b_Chaste_release_2017.1_Potts/` (with `DIFFS_vs_paper-tag_and_develop.txt`).

The two sources describe **two different models** that share a mechanism (differential adhesion + area constraint + Metropolis copies):
- **Variant GG (09a).** A light/dark aggregate in medium. Contacts are next-nearest-neighbour. There is an area constraint and no perimeter term. T = 10.
- **Variant OS (09b CP).** Chaste Potts. 20×20 cells of 4×4 sites, labelled/unlabelled, in medium. There is an area **and a perimeter** constraint. Contacts are von Neumann and proposals are Moore. T = 0.2, in time units of hours.

---

## 2. Mechanics

### 2.1 Variant GG (09a)

**Hamiltonian, Eq. (2), 09a p.2014 (top):**

H_sort = Σ_{(i,j),(i′,j′) neighbors} J(τ(σ(i,j)), τ(σ(i′,j′))) [1 − δ_{σ(i,j),σ(i′,j′)}] + λ Σ_{spin types σ} [a(σ) − A_{τ(σ)}]² θ(A_{τ(σ)})

- τ(σ) ∈ {l, d, M} (light, dark, medium). J(τ,τ′) is the surface energy. λ is a "Lagrange multiplier specifying the strength of the area constraint". a(σ) is the cell area and A_τ the target area for type τ (09a p.2014).
- Medium is "a single cell with associated type, interaction energies, and unconstrained volume". "We set the target area A_M of the medium to be negative", and θ(x) = [0: x < 0; 1: x > 0] suppresses its constraint (09a p.2014).
- Eq. (1) (09a p.2013) is the plain large-Q Potts Hamiltonian Σ(1 − δ). Eq. (2) is the model used.

**Neighbourhood.**
- Hamiltonian: "the neighbors may be of any desired range" (p.2013). "We therefore employ a next-nearest-neighbor square lattice which has a low anisotropy" (p.2014). This is the 8-neighbour (Moore-1) set.
- Proposals: "requiring that a lattice site flip only to a spin belonging to one of its neighbors" (p.2014). The range of "neighbors" here is not restated. The natural reading is the same NNN set (see A-GG2).

**Acceptance (09a p.2013).**
- "At each step we select a lattice site at random and change its spin from σ to σ′ with Monte Carlo probability".
- T > 0: P = exp(−ΔH/kT) if ΔH > 0, and P = 1 if ΔH ≤ 0.
- T = 0: P = 0 if ΔH > 0, 0.5 if ΔH = 0, and 1 if ΔH < 0.
- k is not given a value. We treat it as k = 1, with T in energy units.

**MCS.** "one Monte Carlo time step (MCS) defined to be 16 times the number of spins in the array" (09a p.2014). Under our convention (INTERNALS F8: 1 MCS = N attempts), **1 paper MCS = 16 of our MCS**.

**Temperature and λ.** "We choose T=10 and this effectively fixes λ of order 1 … We employ λ=1" (p.2014).

**Contact energies.** Symmetric energies are assumed, with J(l,M) = J(d,M), "leaving four parameters" (p.2015). The sorting hierarchy is Eq. (3), p.2015:
0 < J(d,d) < [J(d,d)+J(l,l)]/2 < J(d,l) < J(l,l) < J(l,M) = J(d,M).
The values are "J(d,d)=2, J(d,l)=11, J(l,l)=14, and J(d,M)=J(l,M)=16" (p.2015). The intra-cell energy is "here set to zero" (p.2015). J(M,M) is not stated, and it is irrelevant because the medium is a single spin.

**Boundary conditions and lattice size.** **UNSPECIFIED** in 09a (neither the lattice dimensions nor periodic/fixed edges). Fig. 1 shows a round aggregate surrounded by medium.

**Initial condition (09a p.2015).**
1. Equilibrate "a square homotypic aggregate of rectangular cells of various sizes (A=40)". "After 400 MCS the initial symmetries have totally disappeared and the aggregate has become round".
2. "We use this equilibrated rounded aggregate [Fig. 1(a)], with random assignment of cell types, as the initial condition". The type fraction is not stated. The number of cells is not stated.

The parameters of the 400-MCS relaxation run (J values, T) are **not given in 09a**.

**Measurement protocol.**
- "we perform two T=0 annealing steps to reduce ⟨n⟩ very close to 6, before calculating the statistical properties" (p.2014).
- Fig. 1 caption (p.2015): "displayed patterns and statistics are shown after two annealing steps".
- It is not stated whether the annealing is done on a copy or on the live trajectory (A-GG4).

**No growth, division or death.** Sorting "involves neither cell division nor differentiation" (p.2013).

### 2.2 Variant OS (09b, Chaste CP)

**Hamiltonian, Eq. (4), 09b p.6:**

H = Σ_{i=1}^{N_Cells(t)} [ α (A_i − A_i^(0))² + β (C_i − C_i^(0))² ] + Σ_{(i,j)∈N} (1 − δ_{σ(i),σ(j)}) γ(τ(i), τ(j))

- A_i is the area (site count) and C_i the perimeter.
- σ = 0 is the "void" (medium). "N is the set of all neighbouring lattice sites" (p.6). The paper does not specify the order.
- All cells are identical: A^(0), C^(0) (p.6).

The Chaste implementation (external) fixes the details the paper leaves open:

| Item | Implementation | Source |
|---|---|---|
| Contact neighbourhood | **von Neumann** (4). ΔH_adh loops over `GetVonNeumannNeighbouringNodeIndices(targetNodeIndex)` | Chaste:AdhesionPottsUpdateRule.cpp:52–150 (VN loop at :80) |
| Perimeter C | Count of VN edges of each cell site not shared with the same cell. It includes edges to void **and** edges at the lattice edge (`local_edges = 2*DIM`, decremented only for same-cell neighbours) | Chaste:PottsMesh.cpp:198–230 |
| Perimeter ΔH | Uses the local lookup `{4,2,0,−2,−4}` indexed by the number of same-cell VN neighbours | Chaste:SurfaceAreaConstraintPottsUpdateRule.cpp:53–150 (VN loop at :87) |
| Area ΔH | α[(ΔA±1)² − ΔA²] for the gaining (+1) and losing (−1) cells. No term for void | Chaste:VolumeConstraintPottsUpdateRule.cpp:53–99 |
| Differential adhesion | Both labelled → `LabelledCellLabelledCell`. One labelled → `LabelledCellCell`. Neither → `CellCell`. Cell–void → `LabelledCellBoundary` if labelled, else `CellBoundary` | Chaste:DifferentialAdhesionPottsUpdateRule.cpp:55–82 |
| Lattice-edge contacts | A neighbour outside the mesh is absent from the VN set, so the lattice edge carries **no** contact energy | Chaste:AdhesionPottsUpdateRule.cpp:80–84 (loop over existing neighbours only) |

**Proposal.**
- 09b p.5: "selecting a lattice site and a neighbouring site (from the Moore neighbourhood) at random and calculating the change in total energy resulting from copying the spin of the first site to the second".
- The Chaste code does the reverse labelling. It picks the **target** node uniformly (`randMod(num_nodes)`), then a uniform random Moore neighbour as the **source**, and copies source → target (Chaste:PottsBasedCellPopulation.cpp:241–336).
- At the lattice edge, the neighbour is drawn from the existing Moore set, so the draw is renormalised, not counted as null (Chaste:PottsBasedCellPopulation.cpp:285–299).
- Pairs of the same cell or void–void are skipped but consume the attempt (lines 303–307).

**Acceptance, Eq. (3), 09b p.5.** p_copy = min(1, e^{−ΔH/T}). Chaste: accept if `delta_H <= 0 || ranf() < exp(-delta_H/T)` (Chaste:PottsBasedCellPopulation.cpp:320–324).

**Time step and MCS.**
- 09b p.5: "At each time step, Δt, we choose to sample with replacement N × N lattice sites", so 1 Δt = 1 MCS.
- Δt = 0.01 h (Table 1, p.10; CBC:test/TestCellSortingLiteratePaper.hpp:226). `mNumSweepsPerTimestep = 1` (Chaste:PottsBasedCellPopulation.cpp:84).
- **Hence 1 h = 100 MCS**, where the MCS counts all 240² sites, void included.

**Lattice, BCs, layout (code).**
- `element_size = 4`. `domain_size = 20·4·3 = 240` ("Three times the initial domain size"). `PottsMeshGenerator<2>(240, 20, 4, 240, 20, 4)` (CBC:test/TestCellSortingLiteratePaper.hpp:200–203).
- The generator defaults are `startAtBottomLeft=false` (cells centred, gap (240−80)/2 = 80) and non-periodic in x and y (Chaste:PottsMeshGenerator.hpp:89–92; .cpp:67–76).
- 09b p.10: "the edge of the domain is a free boundary".
- Paper (Table 2, p.11): L_x = L_y = 20 CD initial tissue, 1 CD² = 16 sites (p.5).

**Protocol (code).**
1. Build 400 unlabelled cells (`DifferentiatedCellProliferativeType`, so no division; CBC:…:206–209). T = 0.2.
2. Solve to `M_TIME_TO_STEADY_STATE` = **10 h** (1000 MCS) (CBC:…:219, 226–228).
3. Label each cell independently with probability 0.5 (`ranf() < labelledRatio`, CBC:…:94–104, 252–254). The labelled count is therefore Binomial(400, 0.5), **not exactly 200**.
4. Set T = 0.2·k_pert (`M_CELL_FLUCTUATION`, CBC:…:257).
5. Solve to 10 + `M_TIME_FOR_SIMULATION`.

The "original parameter values" block (commented out, CBC:…:76–79) has `M_TIME_FOR_SIMULATION = 100`. The **active** block (CBC:…:81–84) uses 11 for continuous testing, so the repository as checked out does not run the paper's length.

**Labels vs paper types.**
- 09b p.9: "γ(A,A) = γ(B,B) < γ(A,B) and γ(A,void) < γ(B,void) to drive type-A cells to engulf type-B cells".
- Code: labelled–void = 1.0 > unlabelled–void = 0.2, so **B = labelled, A = unlabelled**. This agrees with Table 2 (γ(B,void) = 1.0) and the S1 Movie caption "Engulfment of type-B cells" (p.30). See A-OS1 for the contradicting sentence.

**Metric (09b p.11; Fig. 3).**
- "the fractional length, defined as the total length of edges between cells of different types … normalised by the length at t = 0".
- Code: `HeterotypicBoundaryLengthWriter` counts VN site edges between differently labelled cells. Void edges are excluded, and each edge is counted from both sides, so the ratio is unaffected (Chaste:HeterotypicBoundaryLengthWriter.cpp:276–330).
- The division by the t = 0 value is done in post-processing that is **not** in the repository.
- Sampling is every 100 steps = 1 h (`SetSamplingTimestepMultiple(100)`, CBC:…:227).

**Fluctuation metric (Fig. 3 right, p.12).** "mean squared error between the original curves and smoothed versions of the same curves, using a 10 hour smoothing range". The smoother type is **UNSPECIFIED**.

---

## 3. Parameter tables

### 3.1 Variant GG (09a)

| Symbol | Value | Units | Meaning | Source | Stated/derived |
|---|---|---|---|---|---|
| J(d,d) | 2 | energy | dark–dark | 09a p.2015 | stated |
| J(d,l) | 11 | energy | dark–light | 09a p.2015 | stated |
| J(l,l) | 14 | energy | light–light | 09a p.2015 | stated |
| J(d,M) = J(l,M) | 16 | energy | cell–medium | 09a p.2015 | stated |
| J(M,M) | — | — | irrelevant (single medium spin) | — | UNSPECIFIED (not needed) |
| intra-cell | 0 | energy | same-spin bond | 09a p.2015 "here set to zero" | stated |
| λ | 1 | energy/area² | area-constraint strength | 09a p.2014 | stated |
| A_d, A_l | 40 | sites | target area | 09a p.2015 "(A=40)". The phrase describes the initial cells; that it is the target of both types is inferred | stated (ambiguous, A-GG1) |
| A_M | < 0 | — | switches off the medium constraint via θ | 09a p.2014 | stated |
| T | 10 | energy (k=1) | temperature | 09a p.2014 | stated |
| MCS | 16 N attempts | — | paper time unit | 09a p.2014 | stated |
| γ_dl | 3 | energy | J(d,l) − [J(d,d)+J(l,l)]/2 | 09a p.2015 | derived in paper |
| Hamiltonian nbhd | NNN (8) | — | contact range | 09a p.2014 | stated |
| Proposal nbhd | "one of its neighbors" | — | copy source | 09a p.2014 | range UNSPECIFIED (A-GG2) |
| Lattice size | — | — | — | — | UNSPECIFIED |
| BCs | — | — | — | — | UNSPECIFIED |
| N cells | — | — | — | — | UNSPECIFIED |
| light:dark fraction | — | — | "random assignment of cell types" | 09a p.2015 | UNSPECIFIED |
| Pre-sort relaxation | 400 MCS, square aggregate of rectangular cells | — | build rounded aggregate | 09a p.2015 | stated. Its J, T, λ are UNSPECIFIED |
| Annealing before stats | 2 steps at T = 0 | MCS | stats pre-processing | 09a p.2014; Fig. 1 caption | stated |
| Run length | ≥ 10⁴ MCS | paper MCS | Fig. 1(f) at 10000 MCS; Fig. 2 to 10⁴ | 09a p.2015–2016 | stated |

### 3.2 Variant OS (09b, CP only)

| Symbol | Value | Units | Meaning | Source | Stated/derived |
|---|---|---|---|---|---|
| Lattice | 240 × 240 | sites | domain | CBC:…:200–202 | code only (paper: "N × N", p.5) |
| Cells | 20 × 20 = 400, each 4 × 4 sites | — | initial tissue | Table 2 (L_x = L_y = 20 CD) p.11; p.5 (16 sites/cell); CBC:…:200–202 | stated + code |
| Placement | centred (gap 80 sites) | sites | — | Chaste:PottsMeshGenerator.cpp:67–76 | code (external) |
| BCs | non-periodic, free boundary | — | — | 09b p.10; Chaste:PottsMeshGenerator.hpp:89–92 | stated + code |
| A^(0) | 16 | sites (1 CD²) | target area | Table 1 p.10; CBC:…:232 | stated |
| α | 0.1 | energy/site² | area strength | Table 1 p.10; CBC:…:233 | stated |
| C^(0) | 16 | site edges (4 CD) | target perimeter | Table 1 p.10; CBC:…:237 | stated |
| β | 0.01 | energy/edge² | perimeter strength | Table 1 p.10; CBC:…:238 | stated |
| γ(A,A) = γ(unlab,unlab) | 0.1 | energy | homotypic | Table 1 "γ(cell,cell)" p.10; CBC:…:244 | stated |
| γ(B,B) = γ(lab,lab) | 0.1 | energy | homotypic | p.9 (γ(A,A) = γ(B,B)); CBC:…:242 | stated (via equality) + code |
| γ(A,B) | 0.5 | energy | heterotypic | Table 2 p.11; CBC:…:243 | stated |
| γ(A,void) | 0.2 | energy | unlabelled–void | Table 1 "γ(cell,void)" p.10; CBC:…:245 | stated |
| γ(B,void) | 1.0 | energy | labelled–void | Table 2 p.11; CBC:…:246 | stated |
| T (base) | 0.2 | energy | temperature, adhesion study | Table 2 p.11; CBC:…:219, 257 | stated. Table 1 lists CP T = 0.1 as the cross-study default |
| k_pert | 10^{−2} … 10^{2} (9 values at half-decades per Fig. 3 legend) | — | T multiplier after labelling | Table 2 p.11; Fig. 3 p.13 | stated |
| Δt | 0.01 | h | one MCS | Table 1 p.10; CBC:…:226 | stated |
| Equilibration | 10 h (1000 MCS), unlabelled, T = 0.2 | h | pre-labelling relaxation | CBC:…:81, 228 | **code only (not in paper)** |
| t_end | 100 | h (10,000 MCS) | run after labelling | Table 2 p.11; CBC:…:77 (original block) | stated |
| Label probability | 0.5 per cell (Bernoulli) | — | "50% type-A … 50% type-B" | 09b p.10; CBC:…:100, 254 | stated (paper says 50%; code is Bernoulli) |
| Replicates | 10 | — | per k_pert | 09b p.10 "We simulate each model ten times"; Fig. 3 caption | stated |
| Proposal nbhd | Moore (8) | — | copy source | 09b p.5; Chaste:PottsBasedCellPopulation.cpp:285 | stated |
| Contact / perimeter nbhd | von Neumann (4) | — | ΔH_adh, C | Chaste:AdhesionPottsUpdateRule.cpp:80; PottsMesh.cpp:210 | **code only (external)** |
| Sampling | every 1 h | — | output | CBC:…:227 | code |
| t_cycle | 16 h | h | "Mean cell cycle duration", All models | Table 2 p.11 | stated but **unused** (no proliferation, p.9; differentiated cells in code) |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence / correction |
|---|---|---|---|
| **Graner–Glazier 1992** ||||
| 1 | H = ΣJ(τ,τ′)(1−δ) + λΣ(V−V0)² | CONFIRMED (with detail) | Eq. (2), 09a p.2014. The area term carries θ(A_τ) with A_M < 0 to exempt the medium. It is per type τ, so A_τ, not a single V0 |
| 2 | J_dd = 2 | CONFIRMED | 09a p.2015 |
| 3 | J_dl = 11 | CONFIRMED | 09a p.2015 |
| 4 | J_ll = 14 | CONFIRMED | 09a p.2015 |
| 5 | J_cM = 16 | CONFIRMED | "J(d,M)=J(l,M)=16", 09a p.2015 |
| 6 | λ = 1 | CONFIRMED | 09a p.2014 |
| 7 | V0 = 40 | CONFIRMED (ambiguous wording) | "rectangular cells of various sizes (A=40)", 09a p.2015. The only area number in the paper; it is not explicitly called the target (A-GG1) |
| 8 | T = 10 | CONFIRMED | 09a p.2014 |
| 9 | Moore(1) proposals | CONFIRMED for the Hamiltonian; proposal range NOT IN PAPER | The Hamiltonian uses a "next-nearest-neighbor square lattice" (p.2014). Proposals must copy "a spin belonging to one of its neighbors" (p.2014); the range of that neighbour set is not restated |
| 10 | periodic BCs | NOT IN PAPER | 09a states no lattice size or BC. The system is an aggregate in medium (Fig. 1) |
| **Osborne 2017 CP sorting** ||||
| 11 | 20×20 cells of 4×4 sites in 240² domain | CONFIRMED (paper + code) | 20 CD × 20 CD tissue (Table 2 p.11), 16 sites per CD² (p.5). The 240² domain is from code only (CBC:…:200–202) |
| 12 | 50/50 random labels | CONFIRMED (with nuance) | "comprising 50% type-A cells and 50% type-B cells" (p.10). The code draws an independent Bernoulli(0.5) per cell (CBC:…:100) |
| 13 | V0 = 16, λ_V = 0.1 | CONFIRMED | Table 1 p.10 (A^(0) = 16 LS, α = 0.1); CBC:…:232–233 |
| 14 | S0 = 16, λ_S = 0.01 | CONFIRMED | Table 1 p.10 (C^(0) = 16 LS (4 CD), β = 0.01); CBC:…:237–238 |
| 15 | J labelled–labelled 0.1 | CONFIRMED | γ(B,B) = γ(A,A) (p.9) with γ(cell,cell) = 0.1 (Table 1). Code CBC:…:242 |
| 16 | J labelled–unlabelled 0.5 | CONFIRMED | Table 2 γ(A,B) = 0.5 (p.11); CBC:…:243 |
| 17 | J unlabelled–unlabelled 0.1 | CONFIRMED | Table 1 p.10; CBC:…:244 |
| 18 | J cell–boundary 0.2 | CONFIRMED | Table 1 γ(cell,void) = 0.2 p.10; CBC:…:245. "Boundary" means **void/medium**, not the lattice edge, which has no energy in Chaste |
| 19 | J labelled–boundary 1.0 (2.0 variant) | 1.0 CONFIRMED; "2.0 variant" NOT IN PAPER | Table 2 γ(B,void) = 1.0 p.11. "2.0" appears only as a trailing code comment `// 2.0` (CBC:…:246). Similar unexplained comments suggest 1.0 for two other parameters (CBC:…:243, 245) |
| 20 | T = 0.2 | CONFIRMED | Table 2 p.11 (CP base temperature); CBC:…:219. Note Table 1 lists CP T = 0.1 as the cross-study default |
| 21 | dt = 0.01 | CONFIRMED | Table 1 p.10 (0.01 h); CBC:…:226 |
| 22 | end time 10 | **CORRECTED** | t_end = **100 h** (Table 2 p.11; the original code block M_TIME_FOR_SIMULATION = 100, CBC:…:77). The code **also** runs a 10-h unlabelled equilibration first (M_TIME_TO_STEADY_STATE = 10, CBC:…:76/81), so total simulated time is 110 h. The value 10 is the equilibration, not the end time. The active code block uses 11 h (CI shortening, CBC:…:82) |
| 23 | metric = heterotypic boundary length normalised by t=0 value | CONFIRMED | "total length of edges between cells of different types … normalised by the length at t = 0" (p.11). Code: VN edges between differently labelled cells, void excluded (Chaste:HeterotypicBoundaryLengthWriter.cpp:276–330). The normalisation step is not in the repository |

---

## 5. Validation targets

Tolerance policy (D-029): ensemble/statistical agreement only, no bitwise or trajectory parity. Plot-read values carry about ±0.03 (fractions) digitisation error.

### 5.1 Variant GG

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-GG1 | Heterotypic boundary fraction falls roughly logarithmically: ≈ 0.40 at 1 MCS, ≈ 0.25 at ~40 MCS, ≈ 0.12 at 10³, ≈ 0.05 at 10⁴ (read from plot). Log fits 5–4000 MCS with R² > 0.97 | 09a Fig. 2(a) p.2016 | Quantitative (from plot) | Ensemble mean (n ≥ 5), after 2 T=0 annealing steps, within ±0.05 at 10, 100, 1000, 10⁴ paper MCS. Linear-in-log10(t) fit over 5–4000 MCS has R² > 0.95 and negative slope |
| V-GG2 | Dark homotypic fraction rises ≈ 0.33 → ≈ 0.5 by ~10³ MCS. Light homotypic ≈ 0.21 → ≈ 0.36 by 10⁴ (read from plot) | 09a Fig. 2(a) | Quantitative (from plot) | Same bands; positive log slopes |
| V-GG3 | "The homotypic boundary rapidly (in about 4 MCS) replaces the initially dominant heterotypic boundary" | 09a p.2015 | Semi-quantitative | Crossover of dark-homotypic and heterotypic fractions at t ∈ [2, 10] paper MCS |
| V-GG4 | Dark-cell edge (medium) boundary → 0 by ≈ 300 MCS. Light edge rises ≈ 0.03 → ≈ 0.057 plateau. "After 300 MCS a monolayer of light cells surrounds the dark cluster" | 09a p.2015; Fig. 2(b) p.2016 | Quantitative (from plot) | Dark edge fraction < 0.005 by 500 paper MCS. Light plateau within 0.045–0.07 |
| V-GG5 | Pattern sequence: small clusters within first steps (1 MCS), merging (100 MCS), partial sorting with trapped light cells (1000), a single dark cluster rounding slowly (4000, 10000) | 09a Fig. 1(a–f) p.2015 | Qualitative | Visual/cluster-count: number of dark clusters monotone non-increasing (ensemble mean); a single dominant dark cluster by 10⁴ |
| V-GG6 | Light cells have slightly smaller mean area than dark cells | 09a p.2014 | Qualitative | ⟨a_l⟩ < ⟨a_d⟩ in the ensemble mean |

**Time mapping.** Paper MCS × 16 = our MCS (09a p.2014; INTERNALS F8). All the times above are paper MCS. Boundary lengths are "fractions of the total boundary length" (Fig. 2 caption). The lattice length measure (bond counts on the NNN lattice vs weighted) is UNSPECIFIED (A-GG3). Bond counts are the default proposal.

**Status (2026-09-30).** V-GG1–V-GG5 are superseded and not frozen. PRL Fig. 2 is a second paper run whose values widen the V-PRE1–V-PRE3 bands. V-GG6 is kept with a noise criterion and a control. See §9.1.

### 5.2 Variant OS (CP) — comparison with Chaste

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-OS1 | Mean (n = 10) normalised heterotypic length for k_pert = 1 (black curve). Read from plot: 1.0 at t = 0, ≈ 0.40 @10 h, ≈ 0.33 @20 h, ≈ 0.29 @40 h, ≈ 0.26 @60 h, ≈ 0.22 @100 h. Optimal-engulfment reference (dashed) ≈ 0.14 | 09b Fig. 3 left, CP row, p.13 | Quantitative (from plot) | Ensemble mean (n ≥ 10) within ±0.05 at 10, 20, 40, 100 h; monotone decreasing after 1 h; value at 100 h in [0.17, 0.27] |
| V-OS2 | Noise dependence. k_pert ≤ 10^{−1}: curve drops at once to ≈ 0.83 and stays flat. k_pert = 10^{−0.5}: ≈ 0.5 at 100 h. k_pert = 10^{0.5}: ≈ black curve. k_pert = 10: slower, ≈ 0.23 at 100 h. k_pert ≥ 10^{1.5}: falls to 0 within a few hours (dissociation) | 09b Fig. 3 CP p.13; p.11 "large amounts of noise can cause disassociation"; p.14 | Semi-quantitative | Ordering of curves plus flat/dissociated regimes reproduced; ±0.07 at 100 h for k_pert ∈ {10^{−0.5}, 1, 10} |
| V-OS3 | Fluctuation magnitude (MSE vs 10-h smoothed curve) rises with k_pert from ≈ 7×10⁻⁴ (10⁻²) to ≈ 1.2×10⁻² at k_pert = 1 (cross) to a peak ≈ 6×10⁻² near 10, then ≈ 0 when dissociated | 09b Fig. 3 right p.13; p.14 | Semi-quantitative (depends on unspecified smoother) | Order of magnitude at k_pert = 1 (10⁻³–10⁻¹); rise-then-collapse shape |
| V-OS4 | Snapshots: k_pert = 1 CP forms two B (green) clusters inside A (purple) at "t=100", then one engulfed B cluster at "t=1000"/"t=10000" | 09b Fig. 2 p.12; Fig. 4 p.14 | Qualitative | B cluster count decreases to 1 with A surrounding it (see A-OS2 on time labels) |
| V-OS5 | k_pert = 10²: cells dissociate and leave the view by t = 3 h | 09b Fig. 4 caption p.14 | Qualitative | Majority of cells not in the largest connected component by 3 h |

**Mapping our MCS to Chaste time.**
- 1 Chaste step = Δt = 0.01 h = 1 MCS = 240² = 57,600 attempts (09b p.5; Chaste:PottsBasedCellPopulation.cpp:252–265).
- Our MCS is N attempts, N = number of mutable sites. With a 240² lattice and void as ordinary mutable medium, **t[h] = MCS / 100**.
- The 10-h equilibration is MCS 0–1000. The paper's t = 0 is MCS 1000 (the labelling instant), so Fig. 3's t = 100 h is MCS 11,000 (A-OS3).
- Normalise by the heterotypic length measured immediately after labelling.

**Two semantics must match Chaste, or the time axis will stretch.**
1. Target-uniform site selection with a renormalised Moore source.
2. Attempts spent on same-cell or void–void pairs count toward the MCS.

*Checked against our sampler (2026-09-30):* `SequentialCPM` draws the target uniformly over all mobile sites and a uniform neighbour as the source, and a same-owner pair still spends the attempt (`lib/CorePotts/src/sequential.jl:7–20`), so (2) and the target-first half of (1) match. At a **closed** lattice edge an out-of-lattice neighbour draw is a wasted attempt in ours (`inside || continue`, line 16), whereas Chaste redraws among the existing Moore neighbours. Only sites on the edge of the 240² domain are affected, which the tissue reaches only after dissociation (k_pert ≥ 10^1.5, V-OS5); there ours wastes 3 of 8 draws on an edge site (5 of 8 at a corner). This slows copies only on the outermost ring of sites and cannot change the V-OS5 verdict.

**Things that must NOT be expected to match.** Trajectories, and the exact 200/200 split (Chaste draws Binomial).

---

## 6. Required general features

| ID | Needed? | Use in this model |
|---|---|---|
| G1 @transition/@create/@retire + rand(Bernoulli) | **Yes (OS)**, init-time only | Per-cell Bernoulli(0.5) label at t = 10 h (a timed, one-off state assignment). This is also the GG random type assignment. It needs a scheduled event at a given MCS that sets a cell kind |
| G2 shape descriptors in energies | **Yes (OS)** | The perimeter constraint β(C − C⁰)² needs a per-cell VN-edge perimeter maintained incrementally, including lattice-edge and void edges |
| G3 contact-scope direction/position | No | Isotropic contacts |
| G4 generalized connectivity | No | Neither paper uses a connectivity constraint. 09a accepts multiply connected cells (p.2014) |
| G5 field BCs / solvers | No | No fields |
| G6 secrete/uptake | No | — |
| G7 site conversion | No | — |
| **G8** pluggable proposal law | **Yes** | (a) GG: the T = 0 rule "P = 0.5 at ΔH = 0" for the annealing steps (09a p.2013). (b) Chaste target-first sampling with the neighbour renormalised at the lattice edge. (c) Per-model proposal nbhd ≠ contact nbhd (OS: Moore proposals, VN contacts) |
| G9 per-cell component protocol | No | — |
| **G10** cluster-scope quantities | **Yes (observables)** | Number of same-type clusters (V-GG5, V-OS4). Largest-component membership (V-OS5) |
| G11 ordered relationships / angles | No | — |
| **G12** observables library | **Yes** | Boundary-length decomposition by type pair (homotypic d/l, heterotypic, cell–medium per type) as fractions of the total. Heterotypic length normalised by the t₀ value. Curve-minus-smoothed MSE. "Annealed-copy" measurement: run k T = 0 steps on a copy before measuring (GG) |
| **G13** initial layout generators | **Yes** | (a) A block of k×k-site square cells centred in a larger lattice (OS). (b) A square aggregate of rectangular cells relaxed into a round aggregate (GG). (c) Random type assignment, either exact fraction or Bernoulli |
| **G14 (new)** timed parameter change / staged protocol | Yes | Chaste runs two stages: equilibrate unlabelled at T = 0.2, then relabel and set T = 0.2·k_pert. GG relaxes, then assigns types, then anneals at T = 0 before measuring. **Justification:** a model-level "protocol/stage" (a parameter change plus an event at a given MCS) is a general need. It could be served by a `remake`/continue-solve API rather than a new core feature. If that API exists, G14 folds into it |

---

## 7. Ambiguities, discrepancies and open questions

- **A-GG1 (target area).** "(A=40)" is attached to the initial rectangular cells (09a p.2015). That it is the target area A_τ for both light and dark cells is inferred. The text notes light cells end "slightly smaller" than dark (p.2014).
- **A-GG2 (proposal range).** The copy source must be "one of its neighbors" (p.2014). Whether that is the same NNN set as the Hamiltonian is not stated.
- **A-GG3 (boundary length measure).** How lengths are measured on the NNN lattice (first-neighbour bonds only, all 8 bonds, weighted) is not stated. The existing port counts Moore bonds (provenance `metric_definition`).
- **A-GG4 (annealing).** Were the "two T=0 annealing steps" applied to a copy (non-destructive) or to the trajectory? The paper says only "before calculating the statistical properties". Were they paper MCS (16N attempts each)?
- **A-GG5 (missing inputs).** Lattice size, BCs, cell count, type fraction, and the 400-MCS relaxation parameters are absent from 09a. The companion PRE 47, 2128 (1993) (09a ref. [18] "to be published"; external, not in our PDFs) is cited elsewhere as giving them. **Obtaining that PDF would settle A-GG1…A-GG5.** *Update: the PRE is now on disk as 09c; see §8.4 for which items it resolves.*
- **A-OS1 (engulfment direction contradiction, 09b).** p.9 and S1 Movie (p.30) and the parameters (γ(B,void) > γ(A,void)) all say **B is engulfed by A**. p.11 says "type-A cells are eventually completely engulfed". Fig. 3's caption for the dashed line (p.11) says "a circular region of 200 type A cells surrounded by type B cells". Fig. 2 shows green = B inside. We take **A engulfs B**. The p.11 wording appears to be an error. Author confirmation is desirable.
- **A-OS2 (time labels in Figs 2/4).** Fig. 2 columns are labelled t = 0, 100, 1000, 10000. Fig. 4 says its central column "corresponds to the t = 100 snapshots in Fig 2", and its other snapshots are "at t = 100" (hours, with a 100 h t_end). If Fig. 2 labels were hours, t = 1000/10000 would exceed t_end. If they were time steps, t = 100 steps = 1 h, which contradicts the sorted state shown and Fig. 3 (≈ 0.8 at 1 h). **Units of Fig. 2 labels are unresolved.** Use Fig. 3 (explicit hours) as the quantitative target.
- **A-OS3 (Fig. 3 time origin).** The code labels after 10 h of equilibration and continues simulator time to 110 h. Fig. 3's axis is 0–100 h. We assume t = 0 is the labelling instant. The post-processing script is not in the repository.
- **A-OS4 (contact neighbourhood). RESOLVED 2026-09-30.** The paper says only "N is the set of all neighbouring lattice sites" (p.6). The VN contact / Moore proposal split is the same in the paper's tagged Chaste revision (`paper/CellBasedComparison`), in `release_2017.1` and in develop 44724eb (§1; release_2017.1 `AdhesionPottsUpdateRule.cpp:80`, `PottsMesh.cpp:198–230`, `PottsBasedCellPopulation.cpp:283`). Not asked.
- **A-OS5 (t_cycle).** Table 2 lists t_cycle = 16 h for "All" models in a study stated to be "in the absence of cell proliferation" (p.9). The code uses differentiated (non-dividing) cells, so t_cycle is inert.
- **A-OS6 (fluctuation smoother).** "10 hour smoothing range" (p.12). The kernel (moving average? LOESS?) is unspecified. Also unstated: whether the MSE is taken per run or on the 10-run mean curve, and on normalised or raw lengths. The CP value at k_pert = 1 (≈ 1.2×10⁻²) is far larger than the wiggles of the plotted mean curve (≈ 0.005, which would give an MSE of about 10⁻⁵) (§9.1 V-OS3).

### 7.1 Discrepancies in our existing port `lib/PottsModels/src/graner_glazier.jl` (read-only review)

| # | Port | Paper (09a) | Assessment |
|---|---|---|---|
| P1 | `Lattice((72,72); boundary = Periodic(), neighborhood = Moore(1))` | Lattice size and BC UNSPECIFIED; an aggregate in medium | Not a contradiction. The docstring should not imply periodicity is the paper's. Check that 2839 medium sites of 5184 keep the aggregate from touching its periodic image |
| P2 | 64 cells (32 dark / 32 light, exact) from a legacy pre-equilibrated state | Cell count and type fraction UNSPECIFIED. Fig. 1 shows many more cells (uncounted) | The docstring's "about 1000 in the paper" is not in 09a (possibly from PRE 1993; external). Mark it as such |
| P3 | Initial cells are 32–42 sites, from 6×6 cells (area 36) relaxed with uniform J = 8 and `ForbidExtinction` (data/graner/provenance.toml `scientific_gaps`) | Square aggregate of rectangular cells "(A=40)", relaxed 400 MCS, parameters unstated | Known deviation, documented in provenance. Keep it flagged |
| P4 | `@relations proposal = Moore(1)` with the comment "the paper copies from the 8 neighbours" | The paper says only "one of its neighbors" (p.2014) | The comment overstates the source. The Hamiltonian range (NNN) is stated; the proposal range is inferred |
| P5 | `J = [0 16 16; 16 2 11; 16 11 14]`, λ = 1, V₀ = 40, T = 10, area term only on dark/light | Matches Eq. (2) and p.2014–2015 values, with θ(A_M) exemption | CONFIRMED |
| P6 | Docstring: paper time t = our 16t | 09a p.2014 | CONFIRMED |
| P7 | Docstring cites "Glazier & Graner, Phys. Rev. E 47, 2128, 1993" for differences, including T = 0 annealing on a copy | Not in our PDFs. 09a says "two T=0 annealing steps" without "on a copy" | Mark external. "On a copy" is an interpretation (A-GG4) |
| P8 | No annealed-measurement observable in the model file | 09a Figs 1–2 statistics are post-annealing | Needed for V-GG1…4 (G12) |
| P9 | legacy `metrics.tsv` covers 100 (our) MCS ≈ 6 paper MCS | Paper runs to 10⁴ paper MCS = 1.6×10⁵ our MCS | Validation needs the long run; legacy data cannot test V-GG1/2/4 |

There is no existing port of the Osborne CP variant.

*The P1–P9 review above predates 09c. §8.6 re-audits the port against the PRE and supersedes it where the two differ. In particular, P3 describes an older generator (6×6 cells, J = 8, `ForbidExtinction`) that no longer matches `data/graner/generate.jl`.*

---

## 8. Graner & Glazier 1993 PRE (09c)

### 8.1 Source and page conventions

- 09c is the companion long paper that 09a cites as ref. [18]. It was received on 7 Aug 1992 and published in March 1993.
- **Page convention.** "09c p.N" means journal page N (2128–2154). PDF pages 1–27 are the journal pages in order (PDF p.k = journal 2127+k).
- PDF pages 28–40 have no text layer. They are higher-resolution reprints of Figs. 6, 7, 10, 12, 17, 18, 20, 22, 25–28 and add no new text.
- The text layer is OCR. Equations, figure captions and table values below were checked against the rendered page images.
- **Numbering.** The paper numbers its equations as (1) the continuum Hamiltonian, (2) the Potts Hamiltonian and (3) the acceptance law. The surface-tension definitions in §II A3 carry no visible equation number.

### 8.2 Model definition (09c)

**Hamiltonian, Eq. (2), 09c p.2129 (§II A1).** It is identical to 09a Eq. (2):

H_Potts = Σ_{(i,j),(i′,j′) neighbors} J(τ(σ(i,j)), τ(σ(i′,j′))) [1 − δ_{σ(i,j),σ(i′,j′)}] + λ Σ_{spins σ} [a(σ) − A_{τ(σ)}]² θ(A_{τ(σ)})

- θ(x) = 0 for x < 0 and 1 for x > 0.
- Medium is τ = M with "its target area A_M negative, to suppress the area constraint" (p.2130 §II A2).
- "Bonds between like spins have energy 0, that is, the energy inside a cell is zero" (p.2129).
- The paper calls the Hamiltonian "nearly identical to the lowest-order expansion for the magnetic bubble Hamiltonian" (p.2129–2130).

**Surface tensions (§II A3, p.2130).** These are the paper's parameterisation of the regimes:
- γ_ld = J_ld − (J_dd + J_ll)/2
- γ_lM = J_lM − J_ll/2
- γ_dM = J_dM − J_dd/2

They are invariant when a constant is added to both J_ii/2 and J_ij. The evolution is invariant when all J and T are multiplied together by the same C > 0 (p.2130).

**Neighbourhoods.**
- **Energy:** "All our simulations employ a second-nearest-neighbor square lattice" (p.2129 §II A2). The number of neighbours is "n = 8 in the next-nearest-neighbor lattice" (p.2132 §II C1). This is the Moore(1) set with unweighted bonds.
- **Proposals:** "We convert its spin value σ(i,j) to the spin value σ′ of one of the eight neighboring sites, chosen at random" (p.2130). **The proposal set is Moore(1), the same set as the energy.**
- Copies come only from a neighbour. The paper calls this "suppressing the nucleation of heterogeneous spins" and says relaxing it to allow medium-filled vacancies gives "essentially no change" (p.2130). Fig. 28 is the only run with the nucleation constraint removed.

**Acceptance, Eq. (3), 09c p.2130.**
- T > 0: P = exp(−ΔH/kT) if ΔH > 0, and 1 if ΔH ≤ 0.
- T = 0: P = 0 if ΔH > 0, 0.5 if ΔH = 0, and 1 if ΔH < 0.
- Each step selects a lattice site (i,j) at random. The value of k is still not given; we use k = 1.

**Time unit.** "We define one Monte Carlo step (MCS) to be 16 times as many time steps as there are lattice sites" (p.2130). Lattice sites include medium sites, so **1 paper MCS = 16 × (total lattice sites) attempts = 16 of our MCS**. This matches 09a.

**Area.**
- "Typically, each cell in our simulations covers approximately 40 lattice sites" (p.2129).
- "up to 1000 cells of target area 40 lattice sites" (p.2130 §II B1).
- "Each cell area is constrained to be around 40 spins" (Fig. 3 caption, p.2134).
- The only run with type-dependent targets is Fig. 28 (A_l = 20, A_d = 40, p.2151). This confirms that the default is **A_l = A_d = 40**.

**λ.**
- The default is λ = 1 in all runs except the λ scan.
- The λ scan uses λ ∈ {0.1, 0.2, 0.5, 1, 2, 5, 10} at T = 5 (§III B5, Fig. 16, Table III, p.2144–2145).
- At λ = 0.1 all cells vanish. At λ = 0.2 the light cells vanish. At λ = 0.5 "a few light cells disappear". For λ > 0.5 all cells are conserved (p.2144).

**Cell count.** "we treat approximately N = 1000 cells" (p.2129). The paper also says "for about 1000 cells" (p.2133).

**Lattice size and boundary conditions.** **Not stated anywhere in 09c.**
- Indirect evidence: the aggregate of ~1000 × 40 ≈ 4×10⁴ sites is surrounded by medium in every figure. Figs. 25–27 (dispersal) are drawn inside a rectangular frame, and dispersed cells approach but do not cross it.
- "Phase transitions occur chiefly for patterns with no free boundaries" (p.2132), which implies that the simulated aggregate has a free boundary against medium.
- The total mismatched-bond count is about 6.6–6.8×10⁴ (Figs. 5(a), 13(a), p.2135, 2142). This is consistent with ~10³ cells of area 40. The paper does not say whether each bond is counted once or twice.

**Temperature.**
- The usual value is T = 10. The pre-relaxation and several regimes use T = 5.
- Critical temperatures (§II C1, p.2132):
  - T_c1 ~ n·δE, where δE ≡ J_ld − (J_dd + J_ll)/2 and n = 8. At it, cells dissociate.
  - Per interface, the paper gives T_dd = 16 ("crumple somewhat" at T = 10) and T_ll = 96.
  - The spinodal-decomposition temperature is T_c2 = 40 δE = 120 for the sorting parameters.
  - Sorting therefore runs at T_dd ≲ T ≪ T_ll, T_c2.
- At high T the dominant failure is loss of cells (light cells first), not a phase transition (p.2132).
- Pinning of the dark–medium interface can occur because J_dM ≫ T (p.2131 §II B3).

**Measured quantities (§II D1, p.2133).**
- **Total boundary length** = "the total number of mismatched bonds between neighboring lattice sites".
- **Fractional boundary length** between τ₁ and τ₂ = "the number of mismatched bonds between a spin of type τ₁ and a spin of type τ₂ divided by the total number of mismatched bonds". The denominator therefore **includes cell–medium bonds**.
- Topology is reported as p(n), ⟨n⟩ and the moments μ_l = Σ p(n)(n − ⟨n⟩)^l. Only "bulk" cells (not touching the medium) are used, and the medium cell is excluded.
- A "type-type correlation" function is plotted (Figs. 13(d), 21(b)) but **never defined**.

**Annealing (§II D2, p.2133–2134).**
- "unless otherwise noted, perform two MCS of T = 0 annealing for all displays and statistics. **We anneal the displayed data only and do not change the spin array used in the simulation**" (p.2134).
- Annealing MCS are paper MCS (16N attempts under Eq. (3), T = 0).
- Two steps bring bulk ⟨n⟩ to within 0.2% of 5.999 ± 0.004. μ₂ comes within 9% of 0.601 ± 0.006. μ₄ still needs about 20 MCS to reach 3%. Persistent two-part cells are accepted as a ~10% limit on moment accuracy (Figs. 2–3, p.2133–2134).
- **Exceptions:**
  - The §II D3 statistics use **ten** MCS of annealing (Fig. 5 caption, p.2135).
  - Fig. 25 and Figs. 4(a,b) are displayed unannealed.
  - The Fig. 23 caption says "two MCS of T = 10 annealing". This is almost certainly a typo for T = 0.

**Initial condition, §II D3 (p.2134–2135; Figs. 4–5).**
1. Start from "an arbitrary pattern, here rectangular cells". Fig. 4(a) shows a **square aggregate** of **staggered** (brick-wall) rectangles of equal height and **various widths**. The design goal is to force "the small-scale breaking of the symmetry of the parallel cell walls … and the large-scale rearrangement of the pattern to eliminate its overall square shape" (p.2134–2135).
2. Relax with "only one cell type [with J_ll = 2 and J_lM = 8 (yielding γ_lM = 7), intermediate between future dark and light cells, T = 5, λ = 1]" (p.2135). The target area is 40 (see Area above).
3. Run for **400 MCS**. Total boundary length (Fig. 5(a)), bulk moments (Fig. 5(b)) and light–medium fraction (Fig. 5(c)) are "stable after 400 MCS, the transient being definitely over". Statistics use 10 MCS of T = 0 annealing.
4. The result (Fig. 4(b)) has ⟨n⟩ = 6.04 ± 0.01, μ₂ = 0.69 ± 0.03, μ₃ = 0.03 ± 0.05, μ₄ = 1.43 ± 0.12.
5. **This single pattern is reused as the initial condition of every later run.** "We then randomly select the cells types, with a seed that we can choose to keep or change" (p.2135).
6. A brief 1–5 MCS topological transient follows, as the pattern adjusts to the new J (p.2135).
7. Temperature and λ scans use an "identical random initial cell type assignment" for each value (Figs. 9, 15, 16 captions).

The light:dark fraction is **not stated**. The Fig. 12(a) and 20(a) images look roughly 1:1. The engulfment run (Fig. 18) instead assigns the "upper half light, lower half dark".

**Replicates.** Each condition is one run. The ± values in Tables I–III are one standard deviation of time-averaged bulk moments over the evolved run, not across replicates (Table I–III captions).

### 8.3 Parameter sets and regimes (09c)

J values are as printed. γ values are the paper's.

| Regime | §, figs | J_ll | J_dd | J_ld | J_lM | J_dM | γ_ld, γ_lM, γ_dM | T | λ | IC | Run length (paper MCS) | Stated outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Pre-relaxation (one type) | §II D3, Figs. 4–5, p.2134–2135 | 2 | — | — | 8 | — | —, 7, — | 5 | 1 | square brick aggregate | 400 (stats to ~650) | rounded, equilibrated pattern |
| Annealing study | §II D2, Figs. 2–3, p.2133–2134 | 2 | — | — | 8 | — | —, 7, — | 0 | 1 | Fig. 4(b) unannealed | 40 | 2 MCS suffice for ⟨n⟩ |
| Checkerboard | §III A, Figs. 7–9, Table I, p.2135–2138 | 10 | 8 | 6 | 12 | 12 | −3, 7, 8 | 10; scan {0, 2, 5, 10, 15, 40} | 1 | random types | 2000 | checkerboard patches in the first few MCS; log-slow defect removal; frozen at T = 0 after ~100 MCS; mixing/liquid transition near T = 15 |
| Cell sorting | §III B, Figs. 12–16, Tables II–III, p.2139–2145 | 14 | 2 | 11 | 16 | 16 | 3, 9, 15 | 10; scan {0, 2, 5, 10, 15, 20, 40, 80}; λ scan at T = 5 | 1; scan {0.1 … 10} | random types | 13 500 | light monolayer by 600 MCS; single dark cluster, round by 13 500 |
| Engulfment | §III C, Figs. 18–19, p.2145 | 14 | 2 | 11 | 16 | 16 | 3, 9, 15 | 10 | 1 | top half light, bottom half dark | 10 000 | slow, not logarithmic; monolayer incomplete at 10⁴; linear extrapolation (R² = 0.987) gives ≈ 11 000 MCS |
| Position reversal | §III D, Figs. 20–21, p.2146–2147 | 14 | 2 | 11 | **30** | 16 | 3, 23, 15 | 10 | 1 | random types | 5000 (Fig. 21 to 10⁴) | dark monolayer outside, complete by 40 MCS; sorting accelerates to ~200 MCS; multiple light regions at 5000 |
| Partial sorting | §III E, Figs. 22–24, p.2147–2148 | **11** | 2 | **14** | 16 | 16 | 7.5, 10.5, 15 | 5 | 1 | random types | 2000 | no light monolayer; small dark inclusions persist; heterotypic length logarithmic at all times |
| Light–light dispersal | §III F1, Fig. 25, p.2150–2151 | 14 | **4** | 11 | **2** | 16 | 2, −5, 14 | 5 | 1 | random types | 480 | surface light cells detach into medium; dark clusters coalesce |
| Light–dark dispersal | §III F2, Fig. 26, p.2150–2151 | 14 | 2 | **35** | 16 | 16 | 27, 9, 15 | 5 | 1 | random types | 2000 | light and dark clusters separate |
| Extreme partial sorting | §III F2, Fig. 27, p.2150–2151 | 14 | 2 | **29** | 16 | 16 | 21, 9, 15 | 5 | 1 | random types | 2000 | compact clusters that do not separate |
| Cavity (vacancy nucleation) | §III F3, Fig. 28, p.2150–2151 | 14 | 2 | 11 | 16 | 16 | 3, 9, 15 | 5 | 1; **A_l = 20, A_d = 40** | random types; nucleation constraint removed | 200 | light-lined central cavity forms; not stable later |

The sorting J set is identical to 09a (p.2139). The PRE adds the regime table, the T and λ scans, and the IC recipe.

**PRL vs PRE wording on the monolayer.** 09a says a light monolayer surrounds the dark cluster "after 300 MCS". 09c says "After 600 MCS a monolayer of light cells surrounds the aggregate" (p.2140) and describes a "quick boundary-driven phase (600 MCS)" (p.2143). In Fig. 13(b) the dark–medium fraction reaches ≈ 0 by about 300–600 MCS. Both are read from the same run; use the figure.

### 8.4 Status of items left open by 09a

| Item | Status | Evidence |
|---|---|---|
| A-GG1: target area 40 for both types | **RESOLVED** | "approximately 40 lattice sites" (p.2129); "1000 cells of target area 40" (p.2130); Fig. 3 caption "constrained to be around 40 spins" (p.2134). Fig. 28 is the only run with A_l ≠ A_d (p.2151) |
| A-GG2: proposal range | **RESOLVED: Moore(1)** | "one of the eight neighboring sites, chosen at random" (p.2130) |
| A-GG3: boundary length measure | **RESOLVED (mostly)** | Unweighted counts of mismatched neighbour bonds. The fraction's denominator is **all** mismatched bonds, medium included (p.2133 §II D1). "Neighboring" is the model's 8-neighbour lattice (p.2129, 2132). Once-vs-twice counting is still unstated, but it cancels in fractions |
| A-GG4: annealing on a copy? | **RESOLVED: on a copy** | "We anneal the displayed data only and do not change the spin array used in the simulation" (p.2134). Two paper MCS at T = 0 under Eq. (3); ten MCS for the §II D3 statistics (p.2135) |
| A-GG4b: annealing unit | **RESOLVED** | Paper MCS: Figs. 2–3 axis "Time (MCS)" (p.2133–2134) |
| A-GG5: 400-MCS relaxation parameters | **RESOLVED** | J_ll = 2, J_lM = 8, T = 5, λ = 1, one cell type (p.2135) |
| A-GG5: cell count | **RESOLVED (approximate)** | "approximately N = 1000 cells" (p.2129) |
| A-GG5: shape of the initial aggregate | **RESOLVED** | A square aggregate of staggered rectangles of varied width (Fig. 4(a), p.2134; "eliminate its overall square shape", p.2135) |
| A-GG5: light:dark fraction | **STILL OPEN** | Only "randomly select the cells types, with a seed" (p.2135). Figures look roughly 1:1. Use Bernoulli(0.5) or exactly 50%, and report which. **Evidence 2026-10-05 (§9.5):** our t = 1 fractions against the dark share p (1000 cells, 4 seeds) are dd/ll/dl = 0.235/0.274/0.432 (p = 0.45), 0.281/0.225/0.435 (0.50), 0.333/0.183/0.424 (0.55), 0.389/0.146/0.406 (0.60). PRE Fig. 13 at t = 1 (0.28/0.23/0.43) matches p = 0.50 on all three. PRL Fig. 2 at t = 1 (0.33/0.22/0.40) matches no single p (dd → 0.55, ll → 0.50, dl → 0.60) |
| A-GG5: lattice size | **STILL OPEN (immaterial for time)** | Not stated. The aggregate is ≈ 4×10⁴ sites. It does **not** affect the time axis: attempts go to uniformly random lattice sites and 1 paper MCS = 16 × (all lattice sites) attempts (p.2130), so every site, cell or medium, receives 16 attempts per paper MCS on average whatever the medium share (§8.5 time mapping). It matters only for how far detached cells can travel (V-PRE14/15) |
| A-GG5: boundary conditions | **STILL OPEN** | Not stated. The aggregate never reaches the edge except in the dispersal runs (Figs. 25–27 frames) |
| Replicates and seeds | **RESOLVED (n = 1)** | Single runs; tables give time-averaged moments ± 1 s.d. (Tables I–III). Scans share one type assignment |
| "Type-type correlation" definition | **OPEN (new)** | Plotted in Figs. 13(d), 21(b) but never defined |
| k (Boltzmann) | **STILL OPEN (immaterial)** | Not given. Take k = 1 |
| J(M,M) | Not needed | Medium is a single spin, and like-spin bonds have energy 0 (p.2129) |

### 8.5 Validation targets from 09c

Tolerance policy (D-029 and performance-over-exactness): **ensemble and statistical agreement only.** There is no bitwise or trajectory parity.
- The paper reports **single runs**. Its curves carry run-to-run noise that we must not treat as exact.
- Default acceptance is an ensemble mean over n ≥ 5 runs (independent type assignments) within the stated band. *(Revised 2026-09-30, §9.2: the earlier extra clause "with the paper's value inside our ensemble's 5–95% range" is withdrawn. A 1000-cell ensemble has a replicate SD of order 0.01, while the two published runs of the same parameter set differ by up to 0.075, so that clause would fail on paper-run noise alone.)*
- Plot-read values carry about ±0.01 (fractions < 0.1) or ±0.02 (fractions > 0.1) digitisation error at the 200-dpi reads of the first pass. The §9 re-reads at 400 dpi are good to about ±0.005 (fractions) and ±0.001 (medium fractions).
- Times are **paper MCS** (× 16 = our MCS).
- All statistics are on a **T = 0-annealed copy** (2 paper MCS = 32 of our MCS) unless noted.
- Fractions use **all** mismatched Moore bonds, medium included, as the denominator.

**Time mapping (revised 2026-09-30; replaces the earlier "±2× time" caveat).** The earlier caveat argued that a smaller medium share gives cells more attempts per paper MCS. That premise is wrong for both the paper and our sampler:
- The paper selects "a lattice site (i,j) at random" and defines the MCS as 16 × (all lattice sites) attempts (09c p.2130).
- `SequentialCPM` draws each attempt's target uniformly over all mobile sites and makes `nmobile` attempts per MCS (`lib/CorePotts/src/sequential.jl:7–12`; `nmobile(::AllMobile, l) = nsites(l)`, `lib/CorePotts/src/lattice.jl:363`). `GranerGlazier` has no frozen kind, so all lattice sites, medium included, are mobile.
- So every site, cell or medium, receives on average 16 attempts per paper MCS in both, independent of the medium share. Attempts on medium-bulk sites are null moves in both.
- Measured (coordinator, 2026-09-30): the same 64-cell aggregate on 72² and on a padded 144² lattice (n = 4) gives the same bond counts at 10, 100 and 10³ paper MCS within noise: heterotypic 761/756, 571/566, 460/459; dark–medium 181/174, 117/122, 0/5.5.

Consequences:
- **Verdicts are taken at the paper's nominal times** (paper MCS × 16 = our MCS). No target carries a time tolerance factor.
- Timing differences from the paper come from **aggregate size** (64 cells in the smoke run vs ≈ 1000 in the paper), which changes the kinetics themselves (a small aggregate forms its monolayer from fewer cells and levels off early). That is a model-size deviation, tested by the FULL variant (`graner_glazier_aggregate(1000)`), not a time-unit uncertainty.
- **Endorsed diagnostic:** a tutorial may report one global time scale s ∈ [½, 2] (the s that makes the most timed rows pass, all rows read at s × nominal time) as **information only**. It never changes a verdict and is not a tolerance. It tells the reader whether a mismatch looks like a uniform rescaling of time (pointing to kinetics, e.g. aggregate size) or not. It should not be labelled as a spec tolerance or as "premise under revision".

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-PRE1 | Sorting (J_ll = 14, J_dd = 2, J_ld = 11, J_M = 16, T = 10). **Re-read at 400 dpi (§9.2):** heterotypic cell–cell fraction 0.43 @1, 0.36 @10, 0.245 @100, 0.136 @10³, 0.050 @10⁴. Dark–dark 0.28, 0.30, 0.39, 0.44, 0.485. Light–light 0.23, 0.255, 0.31, 0.36, 0.40. (First-pass values 0.37 heterotypic and 0.32 dark–dark @10 were misreads.) A second published run of the same set, PRL Fig. 2(a), reads heterotypic 0.40, 0.333, 0.206, 0.122, ≈ 0.04; dark–dark 0.33, 0.375, 0.416, 0.489, off-scale (> 0.5); light–light 0.22, 0.238, 0.289, 0.328, 0.362 | Fig. 13(c), p.2142; 09a Fig. 2(a), p.2016 | Quantitative (plot) | **Revised (§9):** ensemble mean at 10, 100, 10³, 10⁴ inside the two-run envelope widened by 0.03 (bounds in §9.1). Heterotypic linear in log₁₀ t over [5, 4000] with R² > 0.95 and slope in [−0.15, −0.07] per decade (both paper runs ≈ −0.10 to −0.11). FULL only |
| V-PRE2 | Heterotypic curve crosses dark–dark at ≈ 18 MCS and light–light at ≈ 49 MCS (PRE Fig. 13(c), 400-dpi read); in PRL Fig. 2(a) at ≈ 5 and ≈ 38. The text "rapidly (in about four MCS) replaces the initially dominant heterotypic boundary" (09c p.2140) repeats 09a p.2015 word for word and describes the PRL run's dark–dark crossing (≈ 5), not PRE Fig. 13 | Fig. 13(c); 09a Fig. 2(a); p.2140 | Semi-quantitative | **Revised (§9):** first save with dark–dark > heterotypic in [2.5, 40]; first save with light–light > heterotypic in [19, 100]; dark–dark first. Summed homotypic > heterotypic at every save from t = 1 (true at t = 1 in both paper runs: 0.51 vs 0.43 and 0.55 vs 0.40; a weak, non-discriminating row). Replaces V-GG3's [2, 10] window. FULL only |
| V-PRE3 | Medium contacts. **Re-read at 400 dpi:** dark–medium 0.0268 @1, 0.022 @10, 0.0073 @100, 0.0026 @200, ≈ 0.001 @300, 0 from ≈ 600. Light–medium 0.0367 @1, 0.041 @10, 0.0555 @100, 0.0607 @200, 0.0628 @10³. Total medium share 0.0635 @1 and 0.063 at every later time. PRL Fig. 2(b): dark 0.0275 → 0 by 300; light 0.030 → plateau 0.057 from ≈ 300 | Fig. 13(b), p.2142; 09a Fig. 2(b); p.2140 | Quantitative (plot) | **Revised (§9):** (a) first save with mean dark–medium < 0.003 at t ≤ 10³. (b) Plateau reached: the first save after which mean light–medium stays within 5% of its last saved value is ≤ 10³, and the least-squares slope of light–medium against log₁₀ t over the saves in [t_end/10, t_end] is within ±5% of the last value per decade. (c) Level, size-free form: R = F_lM(10³) / [F_dM(1) + F_lM(1)] in [0.85, 1.10] (paper 0.989 PRE, ≈ 0.99 PRL). (d) Raw light–medium at 10³ in [0.050, 0.075]. (a)–(d) are verdicts in FULL; in smoke only (a) is binding |
| V-PRE4 | Total mismatched-bond length drops ≈ 1.2% (≈ 66 800 → ≈ 66 000) and plateaus by ~100 MCS | Fig. 13(a); p.2140 | Semi-quantitative (relative) | Relative drop 0.5–3% and plateau (slope ≈ 0) by 10³ |
| V-PRE5 | Sorting morphology: small clusters by 10 MCS; merging at 100; light monolayer by ~600; last isolated light cluster breaks through by ~5000; a single dark cluster, round but off-centre, at 13 500 | Fig. 12(a–h), p.2141–2142; p.2139–2140 | Qualitative | Dark cluster count non-increasing (ensemble mean); one dominant dark cluster (> 90% of dark cells) by 10⁴–1.35×10⁴; dark–medium ≈ 0 |
| V-PRE6 | Bulk topology of evolved sorting vs T (Table II): ⟨n⟩ = 5.994 (T = 2), 6.02 (5), 6.12 (10), 6.30 (15), 6.50 (20), 6.82 (40). μ₂ = 0.48, 0.50, 0.77, 1.18, 1.64, 2.52 | Table II, p.2140 | Quantitative (n = 1; needs ≳ 10³ cells for bulk statistics) | ⟨n⟩ within ±0.05 and μ₂ within ±25% for T ≤ 10. Monotone increase with T. Only testable at N ≈ 10³ |
| V-PRE7 | Sorting temperature regimes. T = 0 freezes, no sorting. T = 2 sorts very slowly, no monolayer (heterotypic ≈ 0.3 at 3×10³). T = 5 is slower but joins the group. T = 10, 15, 20 reach heterotypic ≈ 0.05 by 10⁴. T = 40 plateaus (heterotypic ≈ 0.1) but forms the monolayer by ~50 MCS. T = 80: all cells disappear, heterotypic → 0 by ~100 | Fig. 15(a–c), p.2143; p.2144 | Semi-quantitative | Ordering reproduced. T = 0: heterotypic changes < 0.02 after 100. T = 40: heterotypic plateau > 0.07. T = 80: > 50% of cells lost by 500 |
| V-PRE8 | λ scan at T = 5. λ = 0.1: all cells vanish (total length → 0 by ~800). λ = 0.2: light cells vanish, dark survive (plateau ≈ 3×10⁴ total length). λ = 0.5: a few light cells lost. λ > 0.5: all survive. Bulk sorting at λ = 10 is ~10× slower than at 0.5, and monolayer formation ~50× slower | Fig. 16, Table III, p.2144–2145 | Semi-quantitative | Survival pattern exact per class by 10³. Ratio of times to reach a fixed heterotypic fraction (λ = 10 vs 0.5) within [3, 30] |
| V-PRE9 | Checkerboard (J_ll = 10, J_dd = 8, J_ld = 6, J_M = 12, T = 10). Heterotypic fraction ≈ 0.58 @1 → ≈ 0.82 @2000. ll and dd ≈ 0.2 → ≈ 0.07. Total length falls ~log without saturation (≈ 67 000 → 65 300). ⟨n⟩ and moments flat after 10 MCS | Figs. 7–8, p.2137–2138 | Quantitative (plot) | Heterotypic ≥ 0.72 by 10³ and increasing in log t. ll, dd ≤ 0.12 by 10³ |
| V-PRE10 | Checkerboard vs T. T = 0 freezes after ~100 MCS (ll ≈ 0.19, heterotypic ≈ 0.58 flat). T = 2, 5, 10 evolve in parallel after 10 MCS. T = 15, 40 level off (heterotypic ≈ 0.7). Light–medium rises ≈ 0.031 → 0.04 but no monolayer. Table I: ⟨n⟩ ≈ 6.02–6.09 for T ≤ 15, 6.25 at T = 40 | Fig. 9, Table I, p.2136–2139 | Semi-quantitative | Frozen/normal/disordered ordering reproduced. T = 40 has the largest μ₂ |
| V-PRE11 | Engulfment (top light, bottom dark, sorting J, T = 10). Light–medium rises ≈ 0.03 → ≈ 0.06 and dark–medium falls ≈ 0.03 → ≈ 0 over 10⁴ MCS, **accelerating on log axes** (not logarithmic). Monolayer not complete at 10⁴ | Figs. 18–19, p.2145–2147 | Semi-quantitative | Dark–medium > 0.005 at 10³ and decreasing. Curve convex in log t (not linear). Completion estimate 5×10³–3×10⁴ |
| V-PRE12 | Position reversal (J_lM = 30). Dark monolayer outside, complete by ~40 MCS. Light–medium correlation → 0 by ~50. Heterotypic ≈ 0.43 → ≈ 0.06 at 10⁴. Multiple light regions at 5000 | Figs. 20–21, p.2146–2149 | Semi-quantitative | Light–medium fraction < 0.005 by 200. Heterotypic within ±0.05 of Fig. 21(a) at 10, 100, 10³ |
| V-PRE13 | Partial sorting (J_ll = 11, J_ld = 14, T = 5). No monolayer: dark–medium stays ≈ 0.028 → ≈ 0.018 at 2000; light–medium ≈ 0.035 → 0.046. Heterotypic ≈ 0.40 → 0.14 at 2000, logarithmic at all times (fit R² ≈ 0.94). Small dark inclusions persist | Figs. 22–24, p.2147–2149 | Quantitative (plot) | Dark–medium > 0.01 at 2000 (vs ≈ 0 for normal sorting). Heterotypic within ±0.05 at 10, 100, 10³ |
| V-PRE14 | Light–light dispersal (J_lM = 2, J_dd = 4, T = 5). Surface light cells detach into medium by 480 MCS; dark clusters stay compact | Fig. 25, p.2151 | Qualitative (unannealed) | > 20% of light cells not in the aggregate's largest component by 500. **Needs a lattice large enough (or non-periodic) for dispersal** |
| V-PRE15 | Light–dark dispersal (J_ld = 35) gives clusters that separate. At J_ld = 29 they do not separate (extreme partial sorting). T = 5, 2000 MCS | Figs. 26–27, p.2151 | Qualitative | J_ld = 35: ≥ 2 disconnected light/dark cluster groups with medium between them. J_ld = 29: a single connected aggregate |
| V-PRE16 | Pre-relaxation (§II D3). Total length jumps and then plateaus. Light–medium fraction 0.067 → 0.061 by ~400. Moments stable by 400: ⟨n⟩ = 6.04 ± 0.01, μ₂ = 0.69 ± 0.03 (with 10-MCS annealing) | Figs. 4–5, p.2134–2135 | Quantitative (n = 1; bulk statistics need ≳ 10³ cells) | For the IC generator: light–medium fraction and total length flat (slope within noise) over the last 100 of 400 MCS. ⟨n⟩_bulk within 6.04 ± 0.05 if N ≳ 500 |
| V-PRE17 | Annealing efficacy: 2 T = 0 MCS bring bulk ⟨n⟩ within 0.2% of 6 (from ≈ 6.25), with μ₂ within 9% of its limit | Fig. 2, p.2133 | Quantitative | On a copy of a T = 5 pattern: ⟨n⟩_bulk after 2 annealing MCS within 6.00 ± 0.02 |

**Supersession (revised 2026-09-30).** PRL Fig. 2 and PRE Fig. 13 are **two different runs** of the sorting parameter set, not one: they differ by up to 0.075 (dark–dark at 10 MCS), their crossings differ ≈ 4× in time, and their light–medium plateaus are 0.057 and 0.063. PRE Fig. 13 is "the simulation shown in Fig. 12" (caption); 09a does not say which run its Fig. 2 is. V-GG1–V-GG4 are therefore not frozen as separate targets: their values enter V-PRE1–V-PRE3 as the second run of the envelope (§9). V-GG5 is covered by V-PRE5. V-GG6 (light smaller than dark) has no PRE counterpart and stays.

**Why the size-free plateau form R (V-PRE3 (c)).** At t = 1 the medium share of all mismatched bonds is set by the aggregate's perimeter over its total boundary. Once the light monolayer forms, every medium bond is light–medium, and neither the perimeter nor the total boundary changes much (total length −1.2%, Fig. 13(a); the aggregate stays round, Fig. 12). So the plateau ≈ the t = 1 medium share, and R ≈ 1 whatever the aggregate size. Both paper runs give R ≈ 0.99 (PRE 0.0628/0.0635; PRL 0.057/0.0575), and the PRE medium share stays at 0.063–0.064 at every time (Fig. 13(b)). R replaces the earlier "scale by our perimeter/area" instruction, which had no computable form. A 64-cell aggregate needs about 27 surface cells (circumference ≈ 180 sites, ≈ 6.5 sites of surface per cell) and has only about 31 light cells, so its monolayer can stay incomplete and R may fall short there; R is reported, not binding, in smoke.

### 8.6 Audit of our port against 09c (read-only)

> **Status update (commit 2a6697c, 2026-09-30, reported by the architecture session).**
> Fixed: D3 (square 51×50 aggregate of staggered mixed-width bricks, height 5), D4 (plateau
> check over the last 100 paper MCS), D5 (types drawn with p = ½; realised 33 dark / 31
> light), D6 (measurements on a copy annealed 32 of our MCS at T = 0), D7 (fractions
> include cell–medium bonds), D11 (λ survival at 800 paper MCS; a few light losses allowed
> at λ = 0.5). Also added: engulfment check at 10³ paper MCS, log-law fit over 4–512 paper
> MCS, checkerboard threshold > 0.45. Documented, not fixed: D1, D2, D14 (docstring and
> provenance `differences`). D15: `metric_definition` was removed deliberately in the D-049
> F-2 rewrite, so that reference below is stale. The audit text below describes the port
> *before* these fixes.
>
> **Status update (2026-09-30, peer session).** D1: the paper-size generator `graner_glazier_aggregate` exists (D-063; see D1). D9: revised to MATCH; the ±2× time caveat is withdrawn (§8.5 time mapping). Pre-freeze audit of every V-target: §9.

Files:
- `lib/PottsModels/src/graner_glazier.jl` (GG)
- `lib/PottsModels/data/graner/generate.jl` (GEN)
- `lib/PottsModels/data/graner/provenance.toml` (PROV)
- For measurement, `lib/PottsModels/test/papers.jl` (TEST)
- `lib/CorePotts/src/algorithms.jl` (ALG)

**Matches**

| # | Code | 09c | Verdict |
|---|---|---|---|
| M1 | GG:25 `J = [0 16 16; 16 2 11; 16 11 14]` (medium, dark, light) | Sorting J (p.2139) | MATCH |
| M2 | GG:22–24 λ = 1, V₀ = 40, T = 10 | λ = 1, A = 40 (p.2129–2130), T = 10 (p.2139) | MATCH |
| M3 | GG:30 `cells(dark, light) => λ*(volume − V₀)^2` (no medium term) | θ(A_M), A_M < 0 (p.2130) | MATCH |
| M4 | GG:27 `neighborhood = Moore(1)` for contacts | "second-nearest-neighbor square lattice", n = 8 (p.2129, 2132) | MATCH |
| M5 | GG:28 `proposal = Moore(1)` and its comment "copies from the 8 neighbours" | "one of the eight neighboring sites" (p.2130) | MATCH. The comment is now justified (supersedes P4) |
| M6 | GG:33 Metropolis; ALG:29–35 T ≤ 0 accepts ties with probability ½ | Eq. (3) incl. P = 0.5 at ΔH = 0 for T = 0 (p.2130) | MATCH. The annealing law is available |
| M7 | GG:12 "paper time t is ours 16t" | "16 times as many time steps as there are lattice sites" (p.2130) | MATCH |
| M8 | GG:13–14 "about 1000 in the paper … 2 MCS of T = 0 annealing on a copy" | N ≈ 1000 (p.2129); anneal displayed data only (p.2134) | MATCH (supersedes P2/P7: now sourced) |
| M9 | GEN:2–4, 29–30: one type, `J = [0 8 8; 8 2 2; 8 2 2]` all-light, T = 5, λ = 1, V₀ = 40 | J_ll = 2, J_lM = 8, T = 5, λ = 1 (p.2135) | MATCH. The unused dark entries are inert |
| M10 | GEN:30 `(0, 6400)` = 400 × 16 | 400 MCS (p.2135) | MATCH |
| M11 | GEN:22 bricks 8 × 5 = 40 sites | Target and typical area 40 | MATCH on area (see D3 for shape) |
| M12 | GEN:33 random type assignment with its own seed (SEED + 1; PROV:13) | "randomly select the cells types, with a seed that we can choose to keep or change" (p.2135) | MATCH |
| M13 | GEN:31 `SequentialCPM` | Random-site sequential dynamics (p.2130) | MATCH |
| M14 | TEST:41, 43, 65 J matrices for partial sorting, checkerboard, position reversal | §III E (J_ll = 11, J_ld = 14, T = 5), §III A (10/8/6/12, T = 10), §III D (J_lM = 30) | MATCH |

**Discrepancies**

| # | Code | 09c | Assessment |
|---|---|---|---|
| D1 | GG:18, GEN:11 lattice 72 × 72; GEN:12, PROV:7 64 cells | ≈ 1000 cells (p.2129); lattice size unstated | Known, documented (GG:13, PROV:16). **Consequences:** bulk-topology targets (V-PRE6, V-PRE16, V-PRE17) are untestable, since 64 cells leave only a few bulk cells. Plateau fractions scale with perimeter/area (V-PRE3). The `scale` tiling in GG:43–51 multiplies aggregates, not cells per aggregate, so it does not approach the paper's single ~1000-cell aggregate **Update 2026-09-30 (D-063):** `graner_glazier_aggregate(n = 1000; seed)` (`lib/PottsModels/src/graner_glazier.jl`) builds one round paper-size aggregate: the `VoronoiBall` layout (a centroidal Voronoi disk of area 40n, 30 Lloyd iterations; since P6.1a5 built on core `Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = 30)`, byte-identical, D-138), dark and light in equal numbers (±1) at random places, a 10-site medium margin, on a square lattice sized to fit (247² for n = 1000; `lattice = size(labels)`, periodic through `GranerGlazier`). It is not Potts-relaxed: area SD 7.6 against 1.6 after a relaxation, but heterotypic fractions from it and from a paper-relaxed start agree within 0.005 at 1, 10 and 100 paper MCS (6 seeds, P6.1b2 review). The tutorial's FULL run draws one aggregate per replicate (`seed = replica`). The 64-cell `graner_glazier_state` remains the smoke start. Size-dependent targets are verdicts only in FULL (§9). **Margin ruling 2026-09-30 (P6.1c):** the 10-site margin stays. Base vs doubled periodic lattice, scaled-down FULL, n = 6, to 10³: largest \|Δ\|/SE = 1.10 at margin 10 (101² vs 202²) and 1.25 at margin 30; the earlier 3.4 SE was n = 2 noise. `graner_glazier_aggregate(n; seed, margin = 10)` now takes the margin; V-PRE14/15 need margin ≥ 60. **Superseded 2026-10-05 (§9.4):** the check ran only to 10³; over the FULL run's 2×10⁴ paper MCS a margin of 10 lets aggregates touch their periodic image. FULL uses margin 60 (347²) |
| D2 | GG:27 `boundary = Periodic()` (also used by GEN via the model) | BC unstated; free aggregate in medium | Not a contradiction for sorting. The aggregate (~57 sites across) leaves a ~15-site medium gap to its periodic image. **Inadequate for dispersal (V-PRE14/15)**, where detached cells would wrap around. GG:5 "on a periodic lattice" should not be read as the paper's choice |
| D3 | GEN:15–25 `brick_aggregate`: uniform 8 × 5 bricks on an **unstaggered** grid (GEN:19, 22), keeping the 64 slots **nearest the centre** (GEN:20–21), so the start is already round | Fig. 4(a): a **square** aggregate of **staggered** rectangles of **various widths**. The recipe exists to test large-scale rounding and symmetry breaking (p.2134–2135) | **Discrepancy.** The generator skips the large-scale equilibration the recipe was designed to exercise, and uses uniform cells. The effect on the sorting outcome is probably small once 400 paper MCS have run, but GEN:1–4 and GG:39 ("following … §II D3") overstate fidelity. Fix: start from a square block of staggered bricks of mixed widths (mean area 40), or document it as a deviation in PROV `differences` |
| D4 | GEN:32 aborts if any cell vanishes; no equilibration check | Equilibration verified by flat total length, bulk moments and light–medium fraction over 400 MCS, with 10-MCS T = 0 annealing (Fig. 5, p.2135) | Missing check. Add a V-PRE16-style plateau check (total length and light–medium fraction over the last 100 paper MCS) when regenerating |
| D5 | GEN:33 exactly 32 dark / 32 light (shuffle) | Fraction unstated (A-GG5, still open) | Not a contradiction. An exact 50% split is a choice. Record it in PROV `differences` as an assumption |
| D6 | No annealed-copy measurement. TEST:14–27 measure raw states | All 09c statistics use 2 paper MCS (32 of ours) of T = 0 annealing on a **copy** (p.2134). §II D3 uses 10 | Discrepancy in the validation harness, not the model (still P8). Unannealed fractions at T = 10 carry extra crumpled-boundary bonds, mostly dark–dark (T_dd = 16, p.2132) |
| D7 | TEST:27 `hetero = dl/(dl + dd + ll)` | Fractional length divides by **all** mismatched bonds, medium included (p.2133) | Normalisation differs by the medium share (≈ 6%). Heterotypic values read from Figs. 13(c)/8(b) are ~6% lower than TEST's definition would give. TEST:26 `medium_fraction` matches the paper's definition |
| D8 | TEST bond counting: Moore bonds, each pair once (TEST:13–25) | "mismatched bonds between neighboring lattice sites" on the 8-neighbour lattice (p.2133) | MATCH on the bond set. Once-vs-twice counting cancels in fractions |
| D9 | GG:12 time mapping, with our MCS normalised by all lattice sites | Same normalisation (p.2130) | **MATCH (revised 2026-09-30).** Attempts go to uniformly random lattice sites in both (`lib/CorePotts/src/sequential.jl:7–12`; 09c p.2130), so each site gets 16 attempts per paper MCS whatever the medium share; the earlier premise ("per-cell attempt rate differs with the cell-site share") was wrong. Measured: the same aggregate on 72² and 144² gives matching bond counts at 10, 100, 10³ paper MCS (§8.5). The ±2× time tolerance is withdrawn; timing differences come from aggregate size (D1) |
| D10 | TEST:34–38 claims "no dark–medium boundary is left (PRL Fig. 2b)" at 10 000 our MCS = 625 paper MCS | Dark–medium ≈ 0 by ~300–600 paper MCS (Fig. 13(b)); monolayer "after 600 MCS" (p.2140) | Consistent, at the edge of the window |
| D11 | TEST:58 λ ∈ {0.1, 0.2, 0.5} → survivors {(0,0), (32,0), (32,32)} after 1600 our MCS = 100 paper MCS | Fig. 16(a): at 100 paper MCS, λ = 0.1 total length is still ≈ half its initial value (cells not all gone until ~800), λ = 0.2 reaches its plateau ≈ 200. λ = 0.5 loses "a few" light cells (p.2144) | The survival **classes** match. The test's timing is faster than the paper's. The attempt rate per site is the same (D9, revised); the difference is the small aggregate's own kinetics (D1). λ = 0.5 with zero losses is stricter than "a few light cells disappear". Acceptable as a class test; do not read it as a timing match |
| D12 | TEST:54–55 "frozen at T = 0 (PRE §III B4)" over our MCS 100–1000 | "At T = 0 the pattern rapidly freezes and does not sort" (p.2144) | MATCH (qualitative) |
| D13 | GG docstring (GG:4–6) cites only the PRL for defaults | Defaults are also stated in 09c p.2139 | Cosmetic. Could cite both |
| D14 | Not implemented: engulfment IC (top/bottom halves), cavity run (A_l ≠ A_d with nucleation allowed), T and λ scans as tests beyond TEST:54–58 | §III C, §III F3, Figs. 15–16 | Coverage gap, not an error. A_l ≠ A_d needs `V₀` per kind (GG:23 is a scalar). The "nucleation constraint removed" variant needs a non-neighbour proposal (G8) |
| D15 | PROV has no `metric_definition` field (cited in §7 A-GG3 and P-table) | — | The spec's earlier reference is stale. The metric now lives only in TEST:13–27 |

**Previously open port items (§7.1)**
- P1: STILL OPEN (BC unstated; see D2).
- P2: RESOLVED. The ≈ 1000 count is sourced (09c p.2129).
- P3: SUPERSEDED. The generator was rewritten; see M9–M11 and D3–D5.
- P4: RESOLVED (M5).
- P5: CONFIRMED again (M1–M3).
- P6: CONFIRMED (M7).
- P7: RESOLVED. "On a copy" is the paper's (09c p.2134).
- P8: STILL OPEN (D6).
- P9: STILL OPEN. Long runs (≥ 10⁴ paper MCS = 1.6×10⁵ our MCS) are needed for V-PRE1/5.

---

## 9. Pre-registration audit (for freezing)

Audit date 2026-09-30 (peer session), before the coordinator freezes the reproduction 09 acceptance tests (D-053; AUTONOMY §7.3). After freezing, any change to a target, tolerance, n or run length below needs a new DECISIONS entry.

### 9.0 Common definitions

These definitions apply to every row unless the row says otherwise.

- **Variants.**
  - **SMOKE:** `graner_glazier_state()`, 64 cells (33 dark, 31 light) on 72² periodic, n = 4 replicates sharing that start, `SequentialCPM(; proposal = Moore(1))`, `seed = 1`, replicas 1:n.
  - **FULL:** `graner_glazier_aggregate(1000; seed = i, margin = 60)` for replicate i (one aggregate per replicate, D-063), 500 dark / 500 light, 347² periodic, n = 10, same solver, run to 2×10⁴ paper MCS. *(Revised 2026-10-05, §9.4: was margin 10 on 247², which let aggregates touch their periodic image after ≈ 3000 paper MCS.)*
  - **Isolation guard (FULL, binding as run validity, not a paper target).** At every save of every replicate the raw state has at least one all-medium lattice row and one all-medium column, so no aggregate touches its periodic image. If the guard fails, the run's verdicts are void from the first touching save on, whatever the rows say; the fix is the lattice, never a target (§9.4).
  - A row marked FULL is a paper comparison and has a verdict only in the full run; in smoke it is reported as information. A row marked SMOKE+FULL is size-independent and binding in both.
- **Time.** Paper MCS; one paper MCS = 16 of our MCS (§8.5 time mapping). Verdicts are read at the nominal times; saves are at exactly 16t. There is no time tolerance. The global time scale s of §8.5 is information only.
- **Fractions.** F_xy(t) = N_xy / N_mm. Here N_mm is the number of mismatched bonds: unordered pairs of Moore(1) neighbour sites (each pair once, periodic minimum image) whose owners differ. N_xy counts the pairs whose kinds are x and y (dd, ll, dl, dM, lM).
  - Measured on a copy annealed 2 paper MCS (32 of our MCS) at T = 0 with the run's own J, λ and V₀ (09c p.2134; D-059). The copy is discarded. Our T ≤ 0 rule accepts ties with probability ½ (09c Eq. (3)).
  - "Heterotypic" is F_dl, "total medium share" is F_dM + F_lM, and "total length" is N_mm.
- **Ensemble statistic.** Unless stated otherwise, a verdict uses the mean over replicates of the per-replicate value, compared with the pass band.
- **Crossing time** of curve A over curve B: the first save t at which mean A > mean B. On the FULL save grid (1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 32, 40, 50, 64, 80, 100, …) it is at or after the true crossing.
- **Log-law fit.** Least squares of mean F_dl against log₁₀ t over the saves in the window. It reports R² and the slope per decade.
- **Cell adjacency** (for clusters and components): two cells are adjacent if they share at least one Moore(1) bond.
- **Negative control NC1** (symmetric contacts): J = [0 16 16; 16 11 11; 16 11 11], all else default, the same starts and n.
- **Paper values.** Values marked "400 dpi" were re-read from 400-dpi renders of the PDF pages, and are good to about ±0.005 for fractions and ±0.001 for medium fractions. Other values are 110–300-dpi reads, good to about ±0.01–0.02.

### 9.1 Audit table

| Target | Source | Observable definition | Variant | n | Pass rule | Tolerance | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| V-GG1 | 09a Fig. 2(a) p.2016 | F_dl | — | — | — | — | SUPERSEDED (not frozen) | A second run of the sorting set, not the PRE run (§8.5 Supersession). Its values enter the V-PRE1 envelope (400 dpi: 0.40 @1, 0.333 @10, 0.206 @100, 0.122 @10³, ≈ 0.04 @10⁴) |
| V-GG2 | 09a Fig. 2(a) | F_dd, F_ll | — | — | — | — | SUPERSEDED (not frozen) | Enters V-PRE1 (400 dpi: dd 0.33, 0.375, 0.416, 0.489, > 0.5 off-scale; ll 0.22, 0.238, 0.289, 0.328, 0.362). The old "dark ≈ 0.5 by 10³" is 0.489 |
| V-GG3 | 09a p.2015 | crossing | — | — | — | — | SUPERSEDED (not frozen) | Its [2, 10] window contradicts PRE Fig. 13 (dd crossing ≈ 18). It fits the PRL run (≈ 5). Folded into V-PRE2's widened window |
| V-GG4 | 09a Fig. 2(b), p.2015 | F_dM, F_lM | — | — | — | — | SUPERSEDED (not frozen) | Enters V-PRE3: PRL dark → 0 by 300; light plateau 0.057; R ≈ 0.99 |
| V-GG5 | 09a Fig. 1 | dark clusters | — | — | — | — | SUPERSEDED (not frozen) | Covered by V-PRE5 |
| V-GG6 | 09a p.2014 ("light cells … slightly smaller average area than dark cells") | Per replicate, mean area (site count) of the light cells minus that of the dark cells, Δa = ⟨a_l⟩ − ⟨a_d⟩, on the raw (unannealed) state at 10³ | SMOKE+FULL | 4 / 10 | mean Δa < 0 and \|mean Δa\| > 2 SE (SE = SD/√n over replicates). **NC1:** \|mean Δa\| under NC1 < ½ \|mean Δa\| of the sorting run | sign test, 2 SE | FIX APPLIED | Expected Δa ≈ −2 sites from the area balance 2λ(a − A) = −∂E_surface/∂a with J_eff,l ≈ 14 vs J_eff,d ≈ 5 (estimate). The old rule had no noise criterion and no control |
| V-PRE1 dl | 09c Fig. 13(c) p.2142 (400 dpi) + 09a Fig. 2(a) | mean F_dl at 10, 100, 10³, 10⁴ | FULL | 10 | inside [lo, hi] | envelope of the two paper runs ± 0.03: @10 [0.303, 0.390]; @100 [0.176, 0.275]; @10³ [0.092, 0.166]; @10⁴ [0.010, 0.080] | FIX APPLIED | PRE 0.36, 0.245, 0.136, 0.050; PRL 0.333, 0.206, 0.122, 0.04. The first pass had 0.37 @10 (misread). The margin 0.03 covers the read (±0.005), the ensemble SE (≈ 0.003) and the Voronoi-vs-relaxed start (≤ 0.005, D-063), with room left |
| V-PRE1 dd | same | mean F_dd at 10, 100, 10³, 10⁴ | FULL | 10 | inside [lo, hi] | @10 [0.270, 0.405]; @100 [0.360, 0.446]; @10³ [0.410, 0.519]; @10⁴ [0.455, 0.550] | FIX APPLIED | PRE 0.30, 0.39, 0.44, 0.485; PRL 0.375, 0.416, 0.489, off-scale. The first pass had 0.32 @10 (misread). The PRE and PRL runs differ by 0.075 @10: **±0.05 around PRE alone would fail a model that reproduces the PRL run.** @10⁴: PRE ± 0.03, widened up to 0.55 because the PRL value is off-scale (> 0.5 from 2000) |
| V-PRE1 ll | same | mean F_ll at 10, 100, 10³, 10⁴ | FULL | 10 | inside [lo, hi] | @10 [0.208, 0.285]; @100 [0.259, 0.340]; @10³ [0.298, 0.390]; @10⁴ [0.332, 0.430] | FIX APPLIED | PRE 0.255, 0.31, 0.36, 0.40; PRL 0.238, 0.289, 0.328, 0.362 |
| V-PRE1 log law | 09a Fig. 2 caption ("logarithmic fits … between 5 and 4000 MCS, with R² > 0.97"); 09c Fig. 13(c) | log-law fit of mean F_dl over saves in [5, 4000] | FULL | 10 | R² > 0.95 and slope in [−0.15, −0.07] per decade | as stated | FIX APPLIED | Slope band added: PRE ≈ −0.11, PRL ≈ −0.105 per decade. "R² > 0.95, slope < 0" alone would pass a much slower or faster sorter. The 4–512 row of `test/papers.jl` is a smoke regression row, not this target |
| V-PRE2 | 09c Fig. 13(c) (400 dpi); 09a Fig. 2(a); 09c p.2140 | crossing times of dd and ll over dl; summed (dd + ll) vs dl | FULL | 10 | t×(dd) ∈ [2.5, 40]; t×(ll) ∈ [19, 100]; t×(dd) < t×(ll); mean F_dd + F_ll > F_dl at every save | windows = the two-run range [5, 18] and [38, 49], widened by ×2 either side for the save grid and run-to-run spread | FIX APPLIED | The "about four MCS" sentence describes the PRL run. The summed row is true at t = 1 in both runs, so it cannot discriminate; kept only as a sanity row. **NC1:** no dd or ll crossing by 10³ (under NC1 the per-type homotypic fractions stay near half the heterotypic one) |
| V-PRE3 (a) dark–medium | 09c Fig. 13(b) (400 dpi); 09a Fig. 2(b) | first save with mean F_dM < 0.003 | FULL (size-free form reported in smoke) | 4 / 10 | ≤ 10³ | as stated | READY | Paper: 0.0026 at 200 (PRE); 0 by 300 (PRL). Measured in smoke by the coordinator: 0 / 5.5 bonds at 10³. **CI tier (ruling 2026-09-30):** smoke's mean first drops below 0.003 exactly at the 10³ save (P6.1c), so the absolute threshold has no margin at 64 cells. The absolute rule stays the FULL verdict. In SMOKE, bind the size-free form instead: first save with mean F_dM(t) / mean F_dM(1) < 0.1 is ≤ 10³ (paper 0.0026/0.0268 = 0.097 at 200). Freeze it only if a calibration run on ≥ 20 seeds disjoint from the frozen ones reaches it by the 500 save; otherwise (a) is FULL-only and CI binds V-GG6, V-PRE13 (a) and NC1. **Calibration 2026-09-30 (P6.1c, seeds 1001–1020, smoke):** mean F_dM(t)/F_dM(1) = 0.119 at the 500 save, first < 0.1 at 640, 0.006 at 10³; 3 of 5 disjoint 4-seed sets fail by 500; per-seed crossing 256–800, 1 of 20 never. So (a) is **FULL-only**; the size-free form is reported in smoke. Its NC1 clause (F_dM(10³) ≥ 0.01 under NC1) stays binding. No later save and no replicate-only fix: more replicates do not move a mean crossing, and a later save loosens the paper target. **NC1:** mean F_dM(10³) ≥ 0.01 |
| V-PRE3 (b) plateau reached | same | t_p = first save after which mean F_lM stays within 5% of its last saved value; s = least-squares slope of mean F_lM against log₁₀ t over saves in [t_end/10, t_end] | FULL | 10 | t_p ≤ 10³ and \|s\| ≤ 0.05 × F_lM(t_end) per decade | as stated | READY (unchanged after the P6.1d run, §9.4) | Paper onset ≈ 200 (PRE: 0.0607 at 200 is within 3.4% of 0.0628) and ≈ 300 (PRL). PRE Fig. 13(b) stops at 10³, so the flatness clause is read from PRL Fig. 2(b), flat at ≈ 0.057 from ≈ 300 to 10⁴; PRE's own [100, 10³] slope (≈ +0.007 per decade) is still rising and is not a reference. The smoke run is still rising over [200, 2000]; that is expected at 64 cells (monolayer incomplete) and is not a verdict. **P6.1d (2026-10-05):** FAIL (t_p = 3200) because aggregates touched their periodic image at margin 10; with the image removed, the same rule gives t_p = 200 (§9.4) |
| V-PRE3 (c) plateau level, size-free | same; §8.5 "Why the size-free plateau form R" | R = mean F_lM(10³) / mean [F_dM(1) + F_lM(1)] | FULL (reported in smoke) | 10 | R ∈ [0.85, 1.10] | as stated | FIX APPLIED | Paper R: PRE 0.0628 / 0.0635 = 0.989; PRL ≈ 0.99. Replaces "scale by our perimeter/area", which had no computable form. The tutorial's [0.78, 1.17] (0.050/0.064 … 0.075/0.064) is looser than the evidence needs |
| V-PRE3 (d) plateau level, raw | same | mean F_lM(10³) | FULL | 10 | ∈ [0.050, 0.075] | as stated | READY | PRE 0.0628, PRL 0.057. Size-dependent: in smoke it is reported only |
| V-PRE4 | 09c Fig. 13(a) p.2142 | total length N_mm (annealed copy) | FULL | 10 | D = [N_mm(1) − mean of N_mm over saves in [100, 10³]] / N_mm(1) ∈ [0.005, 0.03], and \|log-slope of N_mm over [10³, 10⁴]\| ≤ 0.005 × N_mm(10³) per decade | as stated | FIX APPLIED | Paper: 66 850 → ≈ 65 900 (≈ 1.4%), flat after ≈ 20–100. **Before freezing, measure D from a Voronoi start against a paper-relaxed start** (like D-063's check): the unrelaxed start (area SD 7.6) may relax more boundary in the first MCS than the paper's start did. **Measured (P6.1c, 1000 cells, 6 seeds, to 10³):** D = 0.0214 from Voronoi, 0.0212 from a relaxed start, paper ≈ 0.014; the start does not matter. Our N_mm ≈ 37 000 against the paper's 66 850 (ratio ≈ 1.8, not exactly 2, so not simply double counting; the paper's counting rule is unstated). D is a ratio and is unaffected; added to the Glazier author questions next to the V-PRE6 neighbour rule |
| V-PRE5 | 09c Fig. 12, p.2139–2142 | dark clusters = connected components of dark cells under the cell adjacency, on the annealed copy | FULL | 10 | mean dark-cluster count non-increasing across 10, 100, 10³, 10⁴; at 10⁴ the largest dark cluster holds ≥ 90% of dark cells (mean); mean F_dM(10⁴) < 0.001 | as stated | FIX APPLIED; **P6.1f: one-cluster clause FAIL, kept as frozen (§9.5)** | Adjacency and the save set made explicit. Fig. 12(h) at 13 500 shows one round dark cluster; the text puts the last reattachment of an independent dark cluster at 3000–4000 (Figs. 12(e, f)) and a single dark cluster from 5000 (Fig. 12(g), p.2140). The ensemble-mean form rests on one paper run: the per-replicate value is bimodal (≈ 1, or ≈ 0.4–0.75 when two or three large dark domains persist), so with n = 10 its SE is ≈ 0.06 |
| V-PRE6 | 09c Table II p.2140 | bulk ⟨n⟩, μ₂ vs T | FULL + T scan | ≥ 5 per T | — | — | **PARKED** | The rule defining a neighbour for n on the pixel lattice (edge-sharing, Moore, or corner handling) is not stated. ⟨n⟩ ≈ 6 depends on it at the 0.01 level. Author question added (README §5, Glazier item 5). Values confirmed from the text layer |
| V-PRE7 | 09c Fig. 15 p.2143; p.2144 | F_dl vs t for T ∈ {0, 2, 5, 10, 15, 20, 40, 80}; cell survival | FULL + T scan | ≥ 5 per T | T = 0: \|F_dl(2000) − F_dl(100)\| < 0.02. Order at 10³: F_dl(T=2) > F_dl(T=5) > F_dl(T=10). T = 40: F_dl > 0.07 at every save in [10³, 10⁴]. T = 80: > 50% of cells gone (volume 0) by 500 | as stated | READY | Checked against Fig. 15(a,b) (110 dpi): T = 2 ≈ 0.3 at 3×10³; T = 80 → 0 by ≈ 100 |
| V-PRE8 | 09c Fig. 16, Table III, p.2144–2145 | per class, the share of cells alive at 10³ (T = 5); time t* to reach F_dl = 0.25 | FULL + λ scan | ≥ 5 per λ | λ = 0.1: 0 cells alive. λ = 0.2: 0 light, ≥ 90% dark alive. λ = 0.5: ≥ 90% light alive. λ ≥ 1: all alive. t*(λ = 10) / t*(λ = 0.5) ∈ [3, 30] | as stated | FIX APPLIED | The threshold 0.25 is ours (the paper says only "ten times slower", p.2144–2145). If either run never reaches 0.25 by 10⁴, the row fails. Table III confirms ⟨n⟩ and μ₂ at λ = 1 equal Table II at T = 5 (6.02, 0.50) |
| V-PRE9 | 09c Figs. 7–8 p.2137–2138 | F_dl, F_ll, F_dd (checkerboard J = [0 12 12; 12 8 6; 12 6 10], T = 10) | FULL | ≥ 5 | mean F_dl(10³) ≥ 0.72 and log-slope of F_dl over [10, 2000] > 0; F_ll(10³), F_dd(10³) ≤ 0.12 | as stated | READY | Checked (110 dpi): 0.58 @1 → ≈ 0.81 @2000; ll, dd ≈ 0.2 → ≈ 0.07 |
| V-PRE10 | 09c Fig. 9, Table I | checkerboard F_dl vs T | FULL + T scan | ≥ 5 per T | T = 0: \|F_dl(2000) − F_dl(100)\| < 0.02; F_dl(2000) at T = 15 and T = 40 < F_dl(2000) at T = 10 | as stated | FIX APPLIED | The "largest μ₂ at T = 40" clause moved to PARKED with V-PRE6 (same neighbour-rule gap) |
| V-PRE11 | 09c Figs. 18–19 p.2145–2147 | F_dM, F_lM from the engulfment start (top half light, bottom half dark: relabel a `graner_glazier_aggregate` by centroid height) | FULL | ≥ 5 | mean F_dM(10³) > 0.005 and decreasing across saves 10², 10³, 10⁴; log-slope of F_dM over [10³, 10⁴] < log-slope over [10², 10³] (accelerating on log axes); a linear-in-t fit of F_dM over [2000, 10⁴] reaches 0 at t ∈ [5×10³, 3×10⁴] | as stated | FIX APPLIED | Paper: linear extrapolation (R² = 0.987) ≈ 11 000 MCS (p.2145). Needs the relabelled start (a small generator; §8.6 D14) |
| V-PRE12 | 09c Figs. 20–21 p.2146–2149 | F_dl, F_lM (J_lM = 30) | FULL | ≥ 5 | mean F_lM < 0.005 at every save from 200; mean F_dl within ±0.05 of 0.38 @10, 0.25 @100, 0.13 @10³ (300-dpi read of Fig. 21(a)) | ±0.05 (one paper run) | FIX APPLIED | Values were missing from the old row. The light–medium rule is inferred from the light–medium *correlation* reaching 0 by ≈ 50 (Fig. 21(b); the correlation itself is undefined) and "complete by 40 MCS" (p.2146) |
| V-PRE13 | 09c Fig. 23(b) (dark–Medium, bullets; the same series is replotted in Fig. 24(b)) for F_dM; Fig. 23(a) for F_dl; p.2147–2150 | F_dM; F_dl (J = [0 16 16; 16 2 14; 16 14 11], T = 5) | SMOKE+FULL for (a); FULL for (b) | 4 / 10 | (a) mean F_dM(10³) > 0.01. (b) mean F_dl within ±0.05 of 0.325 @10, 0.245 @100, 0.17 @10³ (300-dpi read of Fig. 23(a)) | ±0.05 (one paper run) | FIX APPLIED | Paper F_dM 0.019 @10³, 0.018 @2000. (a) is the contrast with V-PRE3 (a) and is size-free. The Fig. 23 caption's "T = 10 annealing" is a typo for T = 0 (§8.2); anneal at T = 0 |
| V-PRE14 | 09c Fig. 25 p.2151 | share of light cells outside the largest connected component of all cells (J_lM = 2, J_dd = 4, T = 5), **unannealed** | FULL, margin ≥ 60 sites | ≥ 5 | > 20% at 480 | as stated | READY (needs a larger-margin start) | `graner_glazier_aggregate` has a 10-site margin on a periodic lattice; detached cells would wrap around (§8.6 D2). Embed it in a larger lattice |
| V-PRE15 | 09c Figs. 26–27 p.2151 | connected components of all cells at 2000 (T = 5) | FULL, larger margin | ≥ 5 | J_ld = 35: ≥ 2 components each holding ≥ 10% of cells. J_ld = 29: the largest component holds ≥ 95% of cells | as stated | FIX APPLIED | Component rule made explicit. Same margin caveat as V-PRE14 |
| V-PRE16 | 09c Figs. 4–5 p.2134–2135 | for the one-type pre-relaxation generator (`data/graner/generate.jl`): F_lM and N_mm over the last 100 of 400 paper MCS (10-MCS anneal) | generator (regeneration-time, not CI) | 1 | **Ruling 2026-09-30:** \|mean of the last 4 saves − mean of the first 4\| ≤ 2% of the window mean, over the last 100 of 400 paper MCS (saves every 6.25 paper MCS), for each of F_lM and N_mm, measured on a 10-MCS T = 0 annealed copy (the saved start stays unannealed). This is `generate.jl`'s own drift rule plus the anneal. The earlier ≤ 1%/decade slope was miscalibrated: over a 0.125-decade window it allows only 0.125% drift, below n = 1 noise | as stated | READY (plateau part); **PARKED** (⟨n⟩ part) | The ⟨n⟩_bulk part has the V-PRE6 neighbour-rule gap. It does not apply to the FULL start, which is not relaxed (D-063) |
| V-PRE17 | 09c Fig. 2 p.2133 | bulk ⟨n⟩ after 2 annealing MCS | — | — | — | — | **PARKED** | Same neighbour-rule gap as V-PRE6 |
| V-OS1 | 09b Fig. 3 left, CP row p.13 (400 dpi) | L(t)/L(0): L counts VN site edges between cells of different label (void and the lattice edge excluded, each edge once), unannealed; L(0) at the labelling instant (our MCS 1000); t[h] = (MCS − 1000)/100 | OS (no port yet) | 10 | mean within ±0.05 of 0.41 @10 h, 0.34 @20 h, 0.28 @40 h, 0.25 @60 h, 0.22 @100 h; non-increasing after 1 h | ±0.05 | READY | Re-read agrees with §5.2 within 0.01. Paper n = 10 (mean curves). Optimal-engulfment reference (dashed) ≈ 0.14. **NC (OS):** equal γ for all pairs and equal void γ: L(100 h)/L(0) > 0.8 |
| V-OS2 | 09b Fig. 3 CP p.13 | the same L(t)/L(0) for each k_pert | OS | 10 per k | k ≤ 10⁻¹: L(100 h) ∈ [0.75, 0.90] and \|L(100 h) − L(10 h)\| < 0.05. k = 10^−0.5: 0.50 ± 0.07 at 100 h. k = 10^0.5: within 0.05 of the k = 1 curve at 10, 40 and 100 h. k = 10: 0.23 ± 0.07 at 100 h and above the k = 1 curve at 20–60 h. k ≥ 10^1.5: L < 0.02 by 3 h | as stated | FIX APPLIED | Rules made per-curve. Read: k ≤ 10⁻¹ flat at 0.84 (0.81 for 10⁻¹) |
| V-OS3 | 09b Fig. 3 right p.13 | MSE against a 10-h smoothing | OS | 10 | — | — | **PARKED** | A-OS6: smoother unspecified. Also, 1.2×10⁻² at k = 1 is too large to come from the plotted mean curve (its wiggles are ≈ 0.005, MSE ≈ 10⁻⁵), so the MSE is presumably per run or on unnormalised lengths. Added to the A-OS6 question |
| V-OS4 | 09b Fig. 2 p.12; Fig. 4 p.14 | B-cluster count, snapshots | OS | 10 | — | — | **PARKED** | A-OS2 (units of the Fig. 2/4 time labels) |
| V-OS5 | 09b Fig. 4 caption p.14; Fig. 3 | L(t)/L(0) at k = 10² | OS | 10 | L < 0.02 by 3 h | as stated | FIX APPLIED | "Left the viewing window" is not computable. The Fig. 3 CP curve for 10² is 0 within ≈ 3 h. Our closed-edge rule differs from Chaste only on edge sites (§5.2) |
| NC1 | D-048; spec §5 | symmetric contacts (§9.0), at 10³ | SMOKE+FULL | 4 / 10 | mean of F_dl / (1 − F_dM − F_lM) at 10³ ≥ 0.40 (size-free heterotypic share of cell–cell bonds); mean F_dM(10³) ≥ 0.01; 0 of n engulfed (`engulfed` = F_dM < 0.003 and radius ratio < 0.75) | as stated | FIX APPLIED | Random mixing of equal types gives a cell–cell heterotypic share ≈ ½ at any size (paper size 0.47/(1 − 0.063) ≈ 0.50; 64 cells ≈ 0.40/0.8). **Ruling 2026-09-30:** the old raw F_dl ≥ 0.35 assumed the paper-size medium share and failed one disjoint 4-seed set in six at 64 cells (P6.1c: 24 seeds 7001–7024, mean 0.367, per-seed SD 0.040). The size-free form replaces it in SMOKE and FULL. Freeze it only if all six disjoint 4-seed means on seeds 7001–7024 clear 0.40; otherwise the dl clause is FULL-only and the dM and engulfed clauses stay binding |

**Counts.** 35 rows:
- READY: 8 (V-PRE3 (a), (b), (d), V-PRE7, V-PRE9, V-PRE14, V-OS1, NC1);
- FIX APPLIED: 17 (V-GG6, V-PRE1 ×4, V-PRE2, V-PRE3 (c), V-PRE4, V-PRE5, V-PRE8, V-PRE10, V-PRE11, V-PRE12, V-PRE13, V-PRE15, V-OS2, V-OS5);
- split: 1 (V-PRE16: plateau part READY, ⟨n⟩ part PARKED);
- PARKED: 4 (V-PRE6, V-PRE17, V-OS3, V-OS4), plus the ⟨n⟩/μ₂ clauses cut from V-PRE10 and V-PRE16;
- SUPERSEDED (not frozen): 5 (V-GG1 to V-GG5).

The §8.5 acceptance-policy change (§9.2) applies to all rows.

### 9.2 Evidence behind the fixes

- **Two published runs.** PRL Fig. 2 and PRE Fig. 13 use the same parameters but are different data:
  - dark–dark at 10 is 0.375 vs 0.30, and at 10³ 0.489 vs 0.44;
  - the dd crossing is at ≈ 5 vs ≈ 18;
  - the light–medium plateau is 0.057 vs 0.063.

  With ≈ 1000 cells, a replicate SD of order 0.01 cannot explain a difference of 0.075. Either the runs differ in start or protocol, or the paper-level spread is much larger than ours. In both cases a single paper curve ± 0.05 is not a fair band, so V-PRE1 and V-PRE2 use the two-run envelope. The paper does not say which run PRL Fig. 2 is (author question).
- **Tolerance vs ensemble size.**
  - A FULL ensemble of 10 × 1000 cells makes the SE of our means ≈ 0.003, which is negligible.
  - The limiting terms are the paper's single-run spread (above), the digitisation (±0.005 at 400 dpi) and the start (≤ 0.005, D-063). The widening margin of 0.03 covers these.
  - In smoke (n = 4, 64 cells) the replicate SD is larger and the size bias is systematic, so smoke rows other than the SMOKE+FULL ones carry no verdict.
- **Nominal time** (§8.5). The ±2× time caveat is withdrawn everywhere. V-PRE3's "(±2× time)" and D9/D11's attempt-rate argument are corrected.
- **Withdrawn clause.** The §8.5 clause "paper value inside our 5–95% range" is withdrawn (§8.5). It contradicted every band above.

### 9.3 For the coordinator before freezing

1. **Freeze from §9.1, not from §5 or the old §8.5 rows.** The tutorial's current V-PRE1 paper values (0.37 and 0.32 @10, 0.25 @100, 0.14 and 0.35 @10³) and its ±0.05 bands, V-PRE2's [5, 100] windows, and V-PRE3's ratio band [0.78, 1.17] all change.
2. **FULL-only verdicts.** Acceptance tests that must run in CI can only freeze the SMOKE+FULL rows: V-GG6, V-PRE13 (a), NC1 (size-free dl clause subject to its calibration) and the NC1 clause of V-PRE3 (a). V-PRE3 (a) itself is FULL-only after its calibration (§9.1). Everything else is a FULL-run target, recorded in the tutorial's pre-registered table.
3. **V-PRE4: measure before freezing.** Check the Voronoi-vs-relaxed start difference in the total-length drop first (§9.1 note).
4. **PARKED rows** (V-PRE6, V-PRE17, the ⟨n⟩ parts of V-PRE10 and V-PRE16, V-OS3, V-OS4) must not be frozen. V-OS1/2/5 wait on an OS port (G2 perimeter, G14 staged protocol).
5. **No row depends on an unanswered author question** other than the PARKED ones. The open lattice size, BCs and type fraction (A-GG5) do not affect any READY or FIX APPLIED row: time is exact, and the type fraction is set by our generator (500/500) and reported.

### 9.4 Post-run ruling: V-PRE3 (b) in the first FULL run (P6.1d, 2026-10-05)

**Ruling.** The P6.1d failure of V-PRE3 (b) is an artefact of the run's lattice, not a model deviation and not a defect of the target. The row, its tolerance, n and run length stay as frozen. The FULL fixture changes: margin 60 (347² periodic) instead of 10 (247²), plus the isolation guard of §9.0. The P6.1d verdict stays on record as FAIL with this cause, and the next FULL run decides the row. No deviations-table entry and no author question.

**What failed.** P6.1d (commit 8eb9d210; n = 10; margin 10 on 247²): t_p = 3200 against ≤ 10³, with the last-decade slope −0.003 per decade (limit 0.003). The ensemble mean F_lM reached 0.060 by 10³ and stayed there to 2000, then fell to 0.057 at 2×10⁴ while its replicate SD grew from < 0.0005 to 0.004 (4000), 0.005 (10⁴) and 0.006 (2×10⁴). That is the signature of a few replicates dropping by ≈ 0.012 each, not of a slow approach. The replicate-1 video shows the cause: by the last frame the aggregate has drifted to the top and right edges and wraps onto its own image.

**Diagnostic (peer session, 2026-10-05; not a verdict run).** Starts `graner_glazier_aggregate(1000; seed = i, margin = 10)` for i = 1, 2, 3, run to 2×10⁴ paper MCS on 247² and, the same start embedded in the middle of 494² (as in the page's periodic-variant run), with run seeds 101–103; the page's measurement (annealed copy, Moore bonds once, all mismatched bonds as denominator). "Clear" = the raw state has an all-medium row and an all-medium column.

| Replicate | 247²: first save not clear | 247²: F_lM at 10³ → 10⁴ → 2×10⁴ | 494²: F_lM at 10³ → 10⁴ → 2×10⁴ |
|---|---|---|---|
| 1 | 4000 (all-medium columns 27 → 0) | 0.0605 → 0.0452 → 0.0456 (N_lM 2190 → 1758 at the 4000 save) | 0.0604 → 0.0601 → 0.0600 |
| 2 | never | 0.0604 → 0.0604 → 0.0596 | 0.0602 → 0.0599 → 0.0605 |
| 3 | 2×10⁴ | 0.0609 → 0.0603 → 0.0505 | 0.0605 → 0.0612 → 0.0602 |

- Every drop of F_lM coincides with the save at which that replicate stops being clear; a replicate that stays clear never drops; none of the 494² runs drops.
- The frozen rule applied unchanged to the 3-replicate means: 247² gives t_p = 2×10⁴ (fail) and slope −0.0071 per decade; 494² gives **t_p = 200** and slope +0.0003 per decade (limit 0.0030), i.e. PASS, matching the paper's ≈ 200 (PRE) and ≈ 300 (PRL).
- No cell is lost (500 dark and 500 light alive at every save, in all six runs), and N_mm is unchanged (35 880–36 510 at every save from 100 on): the contact replaces light–medium bonds by light–light bonds across the seam.
- On 494² the aggregate's extent grows by up to ≈ 35 sites along an axis over 2×10⁴ paper MCS (all-medium columns 279 → 245 in replicate 3); on 247² the extent grew by 27 sites in replicate 1 before contact. A margin of 60 (gap 120 to the image) clears this with room; it is also the default of `graner_glazier_aggregate` and the minimum for V-PRE14/15.

**The three questions.**
1. *Is the target well posed?* Yes. "Within 5 % of the last saved value" reproduces the paper's own reading: PRE 0.0607 at 200 is within 3.4 % of its last value (0.0628 at 10³, where Fig. 13(b) ends), and PRL Fig. 2(b) is flat at ≈ 0.057 from ≈ 300 to its last point at 10⁴. Our 2×10⁴ reference reaches beyond both figures, but on an isolated aggregate the curve is flat to 2×10⁴, so the longer reference changes nothing. The only caveat (recorded in the row) is that the flatness clause rests on PRL alone, since PRE stops at 10³. No amendment is proposed: an amended reference time (e.g. 10⁴) would still fail on 247² (replicate 1 touches at 4000) and would hide the artefact.
2. *Start, shape, type placement, time unit?* None explains it. The same unrelaxed Voronoi starts reach the plateau at 200 on 494². Before 10³ the normalised curve F_lM(t)/F_lM(10³) of the FULL ensemble is 0.57, 0.65, 0.85 at 1, 10, 100, against 0.58, 0.65, 0.88 for PRE: the approach is on the paper's schedule. The time unit is settled by §8.5. The V-PRE4 start check (D = 0.02 from both starts) agrees.
3. *A model deviation?* No. It is a fixture deviation of our own making: the D-072 margin ruling (§8.6 D1) tested to 10³ only, while the FULL run lasts 2×10⁴.

**Other P6.1d rows read after ≈ 3000.** The contact moves ≈ 0.012 of the affected replicate's boundary from light–medium to light–light. With one to three of ten replicates affected, this shifts the ensemble F_ll at 10⁴ by about +0.001 to +0.004 and leaves F_dl, F_dd, F_dM and N_mm essentially unchanged; V-PRE1 ll @ 10⁴ (0.394 in [0.332, 0.430]), V-PRE4 flatness and V-PRE5 passed with margin, so no verdict changes sign. They are nevertheless re-decided by the next FULL run, which replaces P6.1d as the record.

**For the coordinator.**
1. This changes the frozen page (`MARGIN`, the guard row, the boundary-conditions deviation row, the variant-run prose, the changelog), so it needs a DECISIONS entry amending D-072's margin ruling. It changes no target, tolerance, n or run length.
2. Re-run FULL (cost ≈ 2× P6.1d per MCS, 347² vs 247²). The periodic-variant run then embeds 347² starts in 694² (to 10³ only, as now).
3. Report the P6.1d FAIL and this ruling in the phase report (AUTONOMY §7.5): it is a pre-registered failure explained after the fact, so the maintainer should see it even though no target moved.

### 9.5 Post-run ruling: V-PRE5 in the second FULL run (P6.1f, 2026-10-05)

**Ruling.** V-PRE5 stays as frozen, and the P6.1f FAIL of its one-cluster clause (mean largest dark-cluster share 0.815 at 10⁴ against ≥ 0.90) stands. Unlike V-PRE3 (b) (§9.4), no fixture defect explains it, and no correction of the target's reading rescues it: reading the clause at the paper's figure time (13 500) or at 2×10⁴ also fails. The evidence points to a real but modest difference in **late-stage coarsening**. Up to 10³ our ensemble matches the PRE run. After 10³ both published runs coarsen faster than almost all of our 22 replicates, and the cause is not found. It goes into the deviations table as an open item, to the maintainer as a science question (AUTONOMY §7.5), and to the authors (README §5).

**The data.**
- **P6.1f** (n = 10, margin 60, isolation guard clear):
  - per replicate at 10⁴ (dark clusters, largest share): (2, .992), (3, .76), (2, .636), (1, 1), (1, 1), (3, .904), (2, .748), (4, .51), (1, 1), (3, .604);
  - the count is non-increasing, 20.3 → 12.8 → 5.3 → 2.2, which passes;
  - per-replicate heterotypic F_dl at 10⁴ is 0.050–0.092, mean 0.068.
- **Diagnostic (peer session; not a verdict run).** `graner_glazier_aggregate(1000; seed, margin = 60)` with independent seeds 11–16, each run from the Voronoi start and from its one-type relaxed copy (PRE §II D3: J_ll = 2, J_lM = 8, T = 5, 400 paper MCS), to 2×10⁴. The measurement is the page's: annealed copy, `dark_clusters` copied verbatim.

| Start (n = 6) | mean largest share at 10³ / 10⁴ / 13 500 / 2×10⁴ | replicates ≥ 0.90 at 10⁴ / 2×10⁴ | mean F_dl at 10⁴ (range) |
|---|---|---|---|
| Voronoi (as in the FULL run) | 0.65 / 0.75 / 0.79 / 0.81 | 2 / 3 | 0.076 (0.069–0.080) |
| Relaxed copy (paper recipe) | 0.69 / 0.72 / 0.72 / 0.80 | 1 / 2 | 0.077 (0.067–0.083) |

- Several replicates are arrested with two or three large dark domains separated by a light band. For example, seed 11 (Voronoi) holds a largest share of 0.52–0.53 from 10³ to 2×10⁴, and seed 12 (relaxed) holds 0.49–0.51 from 2000 to 2×10⁴. Merging needs a light band to break, which the PRE describes as a slow "diffusive" breakthrough (p.2140).

**What it is not.**
1. *Not the periodic image.* The guard held at every save. The diagnostic also uses margin 60.
2. *P6.1d's 0.905 was not inflated by the image either.* Dark cells lose all medium contact by ≈ 320 (F_dM = 0 from then on in both runs). The dark mass is wrapped in the light monolayer, so no dark–dark bond can cross the periodic seam. 0.905 against 0.815 is ≈ 1 SE of the difference (per-replicate SD ≈ 0.19 at n = 10): run-to-run noise.
3. *Not the start.* The relaxed copies coarsen no faster than the Voronoi starts (table above).
4. *Not the reading time.* At 13 500, the time of Fig. 12(h), the means are 0.79 and 0.72. At 2×10⁴ they are 0.81 and 0.80.
5. *Not the type fraction.* PRE's t = 1 fractions match p = 0.50 on all three pairs (§8.4 A-GG5 evidence). PRL's do not match any single p, so its fraction stays an open question.

**Why it is a deviation and not only noise.** At 10³ the PRE run sits inside our ensemble: F_dl 0.136 against our 0.133, and Fig. 12(d) shows a main dark mass plus one ≈ 25-cell cluster, a largest share of ≈ 0.9, which 3 of our 10 replicates exceed. At 10⁴ the PRE run's F_dl (0.050) equals the smallest of our 22 replicates (0.0504), and PRL's (0.040) is below all of them. Suppose the two published runs were exchangeable draws from our distribution. Then the chance that both fall at or below our minimum is 2/(24 × 23) ≈ 0.004. The PRE run has one dark cluster from 5000. None of our 12 diagnostic runs is single (≥ 0.99) at 5000, and 2 are ≥ 0.90. The difference is confined to t > 10³. Every V-PRE1 row still passes: the 10⁴ heterotypic band [0.010, 0.080] contains our mean 0.068.

**Why the target is not amended.** The ensemble-mean form is a weak reading of a single run. The per-replicate value is bimodal, so a mean bound effectively demands that about 8 of 10 replicates be single, which one paper run cannot establish. A per-replicate criterion, or the paper value inside our replicate range, would have been the better pre-registration. Here it would pass (4 of 10 replicates are ≥ 0.99), but proposing it after a FAIL, with the F_dl evidence pointing the same way, would be a post-hoc fit. Future pre-registrations of event-driven single-run observables should use per-replicate statistics (a lesson for the spec template, not a change to this row).

**For the coordinator.**
1. Record P6.1f with this FAIL (already the rule), and add the open deviation row and the author question to the page. Both are text-only edits of the frozen page and need a DECISIONS entry. No verdict code, target, tolerance, n or run length changes.
2. Raise it as a science question in the phase report (AUTONOMY §7.5): "a frozen test fails for a reason that looks like the paper, not the code".
3. Candidate causes worth a later item (none is tested here):
   - T relative to the lattice's effective line tension (the breakthrough rate is thermally activated);
   - the cell-size distribution (A = 40 with λ = 1 gives us light cells ≈ 3 sites smaller, V-GG6);
   - the paper's aggregate size and run-to-run spread.

   A cheap first check is the distribution of the time to a single dark cluster over ≥ 20 replicates, against the paper's ≈ 5000.
