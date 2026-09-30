# 09 — Differential-adhesion cell sorting (Graner–Glazier 1992; Osborne et al. 2017 CP benchmark), paper-grounded spec

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **09a** | F. Graner, J.A. Glazier, "Simulation of Biological Cell Sorting Using a Two-Dimensional Extended Potts Model", *Phys. Rev. Lett.* **69**(13), 2013–2016 (28 Sep 1992) | 10.1103/PhysRevLett.69.2013 | `docs/references/09a_GranerGlazier1992_PRL_cell-sorting.pdf` (4 pp.) |
| **09b** | J.M. Osborne, A.G. Fletcher, J.M. Pitt-Francis, P.K. Maini, D.J. Gavaghan, "Comparing individual-based approaches to modelling the self-organization of multicellular tissues", *PLoS Comput Biol* **13**(2): e1005387 (2017) | 10.1371/journal.pcbi.1005387 | `docs/references/09b_Osborne2017_PLoSCB_comparing-individual-based-models.pdf` (34 pp.) |

**Page conventions.** 09a pages are journal pages 2013–2016 (PDF p.1 = 2013). The 09a text layer is OCR and garbles every equation, so the equations below were transcribed from the rendered page images. 09b pages are the PLoS "n / 34" numbers.

**Code (09b).** 09b p.9 points to `https://chaste.cs.ox.ac.uk/trac/wiki/PaperTutorials/CellBasedComparison2017`. It does **not** give a GitHub URL. The GitHub repository `https://github.com/Chaste/CellBasedComparison2017` (README: "contains the code used to produce results in the following paper", with the same DOI) mirrors that tutorial. It was read at commit `8bb7287d0dfb55316892707faab2945cca3d48ea` and is cited as `CBC:path:line`. **`CBC:…:N` abbreviates `CBC:test/TestCellSortingLiteratePaper.hpp:N`.** The Chaste core update rules it calls were read from `https://github.com/Chaste/Chaste` at develop commit `44724ebfbf775e100a48c5398064eb705b5da478` and are cited as `Chaste:file:line`. **Caveat:** this is the 2026 develop branch, not the 2017 release used for the paper. It is marked "external (not in our PDFs)", and its equivalence to the 2017 core is assumed, not verified.

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
- **A-GG5 (missing inputs).** Lattice size, BCs, cell count, type fraction, and the 400-MCS relaxation parameters are absent from 09a. The companion PRE 47, 2128 (1993) (09a ref. [18] "to be published"; external, not in our PDFs) is cited elsewhere as giving them. **Obtaining that PDF would settle A-GG1…A-GG5.**
- **A-OS1 (engulfment direction contradiction, 09b).** p.9 and S1 Movie (p.30) and the parameters (γ(B,void) > γ(A,void)) all say **B is engulfed by A**. p.11 says "type-A cells are eventually completely engulfed". Fig. 3's caption for the dashed line (p.11) says "a circular region of 200 type A cells surrounded by type B cells". Fig. 2 shows green = B inside. We take **A engulfs B**. The p.11 wording appears to be an error. Author confirmation is desirable.
- **A-OS2 (time labels in Figs 2/4).** Fig. 2 columns are labelled t = 0, 100, 1000, 10000. Fig. 4 says its central column "corresponds to the t = 100 snapshots in Fig 2", and its other snapshots are "at t = 100" (hours, with a 100 h t_end). If Fig. 2 labels were hours, t = 1000/10000 would exceed t_end. If they were time steps, t = 100 steps = 1 h, which contradicts the sorted state shown and Fig. 3 (≈ 0.8 at 1 h). **Units of Fig. 2 labels are unresolved.** Use Fig. 3 (explicit hours) as the quantitative target.
- **A-OS3 (Fig. 3 time origin).** The code labels after 10 h of equilibration and continues simulator time to 110 h. Fig. 3's axis is 0–100 h. We assume t = 0 is the labelling instant. The post-processing script is not in the repository.
- **A-OS4 (contact neighbourhood).** The paper says only "N is the set of all neighbouring lattice sites" (p.6). The VN contact / Moore proposal split comes from the 2026 Chaste develop code (external). The 2017 core may differ.
- **A-OS5 (t_cycle).** Table 2 lists t_cycle = 16 h for "All" models in a study stated to be "in the absence of cell proliferation" (p.9). The code uses differentiated (non-dividing) cells, so t_cycle is inert.
- **A-OS6 (fluctuation smoother).** "10 hour smoothing range" (p.12). The kernel (moving average? LOESS?) is unspecified.

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
