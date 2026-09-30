# 09 — Differential-adhesion cell sorting (Graner–Glazier 1992; Osborne et al. 2017 CP benchmark), paper-grounded spec

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **09a** | F. Graner, J.A. Glazier, "Simulation of Biological Cell Sorting Using a Two-Dimensional Extended Potts Model", *Phys. Rev. Lett.* **69**(13), 2013–2016 (28 Sep 1992) | 10.1103/PhysRevLett.69.2013 | `docs/references/09a_GranerGlazier1992_PRL_cell-sorting.pdf` (4 pp.) |
| **09b** | J.M. Osborne, A.G. Fletcher, J.M. Pitt-Francis, P.K. Maini, D.J. Gavaghan, "Comparing individual-based approaches to modelling the self-organization of multicellular tissues", *PLoS Comput Biol* **13**(2): e1005387 (2017) | 10.1371/journal.pcbi.1005387 | `docs/references/09b_Osborne2017_PLoSCB_comparing-individual-based-models.pdf` (34 pp.) |
| **09c** | J.A. Glazier, F. Graner, "Simulation of the differential adhesion driven rearrangement of biological cells", *Phys. Rev. E* **47**(3), 2128–2154 (Mar 1993) | 10.1103/PhysRevE.47.2128 | `docs/references/09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf` (40 pp.; see §8) |

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
- **A-GG5 (missing inputs).** Lattice size, BCs, cell count, type fraction, and the 400-MCS relaxation parameters are absent from 09a. The companion PRE 47, 2128 (1993) (09a ref. [18] "to be published"; external, not in our PDFs) is cited elsewhere as giving them. **Obtaining that PDF would settle A-GG1…A-GG5.** *Update: the PRE is now on disk as 09c; see §8.4 for which items it resolves.*
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
| A-GG5: light:dark fraction | **STILL OPEN** | Only "randomly select the cells types, with a seed" (p.2135). Figures look roughly 1:1. Use Bernoulli(0.5) or exactly 50%, and report which |
| A-GG5: lattice size | **STILL OPEN** | Not stated. The aggregate is ≈ 4×10⁴ sites. **This matters for time:** the MCS is normalised by all lattice sites, so the per-cell attempt rate depends on the medium fraction, which is unknown (see §8.5 time note) |
| A-GG5: boundary conditions | **STILL OPEN** | Not stated. The aggregate never reaches the edge except in the dispersal runs (Figs. 25–27 frames) |
| Replicates and seeds | **RESOLVED (n = 1)** | Single runs; tables give time-averaged moments ± 1 s.d. (Tables I–III). Scans share one type assignment |
| "Type-type correlation" definition | **OPEN (new)** | Plotted in Figs. 13(d), 21(b) but never defined |
| k (Boltzmann) | **STILL OPEN (immaterial)** | Not given. Take k = 1 |
| J(M,M) | Not needed | Medium is a single spin, and like-spin bonds have energy 0 (p.2129) |

### 8.5 Validation targets from 09c

Tolerance policy (D-029 and performance-over-exactness): **ensemble and statistical agreement only.** There is no bitwise or trajectory parity.
- The paper reports **single runs**. Its curves carry run-to-run noise that we must not treat as exact.
- Default acceptance is an ensemble mean over n ≥ 5 runs (independent type assignments) within the stated band, with the paper's value inside our ensemble's 5–95% range.
- Plot-read values carry about ±0.01 (fractions < 0.1) or ±0.02 (fractions > 0.1) digitisation error.
- Times are **paper MCS** (× 16 = our MCS).
- All statistics are on a **T = 0-annealed copy** (2 paper MCS = 32 of our MCS) unless noted.
- Fractions use **all** mismatched Moore bonds, medium included, as the denominator.

**Time-axis caveat (open lattice size).** A paper MCS spends 16 attempts per lattice site, including medium sites. A smaller medium fraction in our lattice gives cells more attempts per paper MCS than in the paper. Until the lattice size is known, targets with a timing component carry an extra factor-of-~2 time tolerance. Comparisons should prefer **ordering, shape and log-slope** over absolute times.

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-PRE1 | Sorting (J_ll = 14, J_dd = 2, J_ld = 11, J_M = 16, T = 10). Heterotypic cell–cell fraction ≈ 0.43 @1, 0.37 @10, 0.25 @100, 0.14 @10³, 0.05 @10⁴ MCS. Dark–dark homotypic ≈ 0.28 → 0.32 → 0.39 → 0.44 → 0.485. Light–light ≈ 0.23 → 0.255 → 0.31 → 0.35 → 0.40 (read) | Fig. 13(c), p.2142 | Quantitative (plot) | Ensemble means within ±0.05 at 10, 100, 10³, 10⁴. Heterotypic linear in log₁₀ t over 5–4000 with R² > 0.95 and negative slope. Supersedes and agrees with V-GG1/V-GG2 (09a Fig. 2 is the same run) |
| V-PRE2 | Heterotypic curve crosses dark–dark at ≈ 20 MCS and light–light at ≈ 45 MCS (read). The text says homotypic "rapidly (in about four MCS) replaces the initially dominant heterotypic boundary" (p.2140), which fits the **summed** homotypic fraction | Fig. 13(c); p.2140 | Semi-quantitative | Summed homotypic > heterotypic by t ≤ 10. Crossings with dd and ll within [5, 100] MCS, dd before ll. Replaces V-GG3's [2, 10] window, which the figure contradicts for the per-type curves |
| V-PRE3 | Medium contacts. Dark–medium fraction ≈ 0.027 @1, 0.022 @10, 0.008 @100, ≈ 0 by 300–600. Light–medium ≈ 0.037 → plateau 0.062–0.063 from ~200 MCS | Fig. 13(b), p.2142; p.2140 | Quantitative (plot) | Dark–medium < 0.003 by 10³. Light–medium plateau within 0.050–0.075, reached before 10³ (±2× time). The absolute plateau depends on aggregate size (perimeter/area): scale by our perimeter/area if N ≠ 1000 |
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

**Supersession.** V-GG1/V-GG2 remain valid and agree with V-PRE1 within digitisation error. V-GG3 is refined by V-PRE2. V-GG4's "300 MCS" should be read with V-PRE3's 300–600 window. V-GG6 (light smaller than dark) has no PRE counterpart.

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
| D1 | GG:18, GEN:11 lattice 72 × 72; GEN:12, PROV:7 64 cells | ≈ 1000 cells (p.2129); lattice size unstated | Known, documented (GG:13, PROV:16). **Consequences:** bulk-topology targets (V-PRE6, V-PRE16, V-PRE17) are untestable, since 64 cells leave only a few bulk cells. Plateau fractions scale with perimeter/area (V-PRE3). The `scale` tiling in GG:43–51 multiplies aggregates, not cells per aggregate, so it does not approach the paper's single ~1000-cell aggregate |
| D2 | GG:27 `boundary = Periodic()` (also used by GEN via the model) | BC unstated; free aggregate in medium | Not a contradiction for sorting. The aggregate (~57 sites across) leaves a ~15-site medium gap to its periodic image. **Inadequate for dispersal (V-PRE14/15)**, where detached cells would wrap around. GG:5 "on a periodic lattice" should not be read as the paper's choice |
| D3 | GEN:15–25 `brick_aggregate`: uniform 8 × 5 bricks on an **unstaggered** grid (GEN:19, 22), keeping the 64 slots **nearest the centre** (GEN:20–21), so the start is already round | Fig. 4(a): a **square** aggregate of **staggered** rectangles of **various widths**. The recipe exists to test large-scale rounding and symmetry breaking (p.2134–2135) | **Discrepancy.** The generator skips the large-scale equilibration the recipe was designed to exercise, and uses uniform cells. The effect on the sorting outcome is probably small once 400 paper MCS have run, but GEN:1–4 and GG:39 ("following … §II D3") overstate fidelity. Fix: start from a square block of staggered bricks of mixed widths (mean area 40), or document it as a deviation in PROV `differences` |
| D4 | GEN:32 aborts if any cell vanishes; no equilibration check | Equilibration verified by flat total length, bulk moments and light–medium fraction over 400 MCS, with 10-MCS T = 0 annealing (Fig. 5, p.2135) | Missing check. Add a V-PRE16-style plateau check (total length and light–medium fraction over the last 100 paper MCS) when regenerating |
| D5 | GEN:33 exactly 32 dark / 32 light (shuffle) | Fraction unstated (A-GG5, still open) | Not a contradiction. An exact 50% split is a choice. Record it in PROV `differences` as an assumption |
| D6 | No annealed-copy measurement. TEST:14–27 measure raw states | All 09c statistics use 2 paper MCS (32 of ours) of T = 0 annealing on a **copy** (p.2134). §II D3 uses 10 | Discrepancy in the validation harness, not the model (still P8). Unannealed fractions at T = 10 carry extra crumpled-boundary bonds, mostly dark–dark (T_dd = 16, p.2132) |
| D7 | TEST:27 `hetero = dl/(dl + dd + ll)` | Fractional length divides by **all** mismatched bonds, medium included (p.2133) | Normalisation differs by the medium share (≈ 6%). Heterotypic values read from Figs. 13(c)/8(b) are ~6% lower than TEST's definition would give. TEST:26 `medium_fraction` matches the paper's definition |
| D8 | TEST bond counting: Moore bonds, each pair once (TEST:13–25) | "mismatched bonds between neighboring lattice sites" on the 8-neighbour lattice (p.2133) | MATCH on the bond set. Once-vs-twice counting cancels in fractions |
| D9 | GG:12 time mapping, with our MCS normalised by all 72² sites | Same normalisation, but the paper's medium fraction is unknown | The mapping is formally right. The per-cell attempt rate differs by (cell sites / lattice sites) ratio: ours ≈ 2560/5184 ≈ 0.49, the paper's is unknown. Keep the ±2× time tolerance (§8.5) |
| D10 | TEST:34–38 claims "no dark–medium boundary is left (PRL Fig. 2b)" at 10 000 our MCS = 625 paper MCS | Dark–medium ≈ 0 by ~300–600 paper MCS (Fig. 13(b)); monolayer "after 600 MCS" (p.2140) | Consistent, at the edge of the window |
| D11 | TEST:58 λ ∈ {0.1, 0.2, 0.5} → survivors {(0,0), (32,0), (32,32)} after 1600 our MCS = 100 paper MCS | Fig. 16(a): at 100 paper MCS, λ = 0.1 total length is still ≈ half its initial value (cells not all gone until ~800), λ = 0.2 reaches its plateau ≈ 200. λ = 0.5 loses "a few" light cells (p.2144) | The survival **classes** match. The test's timing is faster than the paper's (small aggregate, higher attempt rate per cell; see D9). λ = 0.5 with zero losses is stricter than "a few light cells disappear". Acceptable as a class test; do not read it as a timing match |
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
