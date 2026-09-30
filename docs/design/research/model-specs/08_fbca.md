# 08 — FBCA: Flux Balance Cellular Automata (CPM × per-cell FBA)

Paper-grounded spec. Every claim cites a PDF in `docs/references/`. Claims not in the PDFs are
marked **UNSPECIFIED** or **NOT IN PAPER**.

## 1. Header

| Tag | Citation | DOI | File |
|---|---|---|---|
| **08a** (base FBCA) | Graudenzi A, Maspero D, Damiani C. "FBCA, A Multiscale Modeling Framework Combining Cellular Automata and Flux Balance Analysis." *Journal of Cellular Automata* **15**:75–95 (©2019, Old City Publishing; received 25 Feb 2019, accepted 23 Mar 2019). | Not printed anywhere in the PDF. | `08a_Graudenzi2020_JCellAutomata_FBCA.pdf` |
| **08b** (diffusion extension) | Maspero D, Damiani C, Antoniotti M, Graudenzi A, Di Filippo M, Vanoni M, Caravagna G, Colombo R, Ramazzotti D, Pescini D. "The Influence of Nutrients Diffusion on a Metabolism-driven Model of a Multi-cellular System." *Fundamenta Informaticae* **171**:279–295 (2020). | 10.3233/FI-2020-1883 (08b p.279) | `08b_Maspero2020_FundInform_FBCA-nutrient-diffusion.pdf` |

Page convention: citations use the **printed journal page**. 08a: journal p.75 = PDF p.1, so PDF page = journal page − 74 (PDF p.22 is a publisher copyright page). 08b: journal p.279 = PDF p.1, so PDF page = journal page − 278.

**Lineage (as each paper states it).** 08a says FBCA was "originally introduced in [1]" (Graudenzi et al., ACRI 2018, LNCS 11115) and adds DAH adhesion, the density limit, and a basic therapy model (08a p.76, p.78). 08b cites as its own [18] that ACRI 2018 paper (doi 10.1007/978-3-319-99813-8_2), **not** 08a. It cites the density-sensing mechanism to [23] (Maspero et al. 2019, "Synchronization effects…", doi 10.1007/978-3-030-21733-4_9) (08b p.281, p.293). 08b's default parameters come "as in [18]" (08b p.285), which is the ACRI 2018 paper. We do **not** have that paper on disk.

**Public code / model links.** Neither PDF has a URL, repository, SBML file, or data-availability statement.
- 08a says the implementation is "in MATLAB" with the COBRA Toolbox [25] for FBA (08a p.82).
- 08b says the code was "written from scratch in Matlab" with the COBRA Toolbox [30] (08b p.288).
- The metabolic model is cited only as literature: "HMR CORE introduced in [12]" (Di Filippo et al. 2016, *Comput Biol Chem* 62:60–69) (08a p.83), or [25] = same paper, doi 10.1016/j.compbiolchem.2016.03.002 (08b p.282, p.294).
- Neither paper mentions SBML.
- **Result: no public code or model URL is cited in either paper.**

**Sources obtained or checked on 2026-09-30 (pre-send checks).**
- **HMR core (on disk).** The Di Filippo 2016 supplementary spreadsheets `mmc1.xls`–`mmc4.xls` (publisher CDN, https://ars.els-cdn.com/content/image/1-s2.0-S1476927115300141-mmc{1..4}.xls) are in `docs/references/supplementary/08_DiFilippo2016_CompBiolChem_mmc{1..4}.xls` (sha256 in `codebases/SOURCES.md`). Each has sheets `reactions` (columns abbreviation, officialNames, reactions, GPR, genes, proteins, subSystem, lowerBound, upperBound, confidenceScore) and `metabolites`. `mmc1.xls` is the generic core: its objective is `biomass_synthesis` → `biomass[s]` with export `Ex_biomass[s]`. `mmc2`–`mmc4` are smaller tissue-specific models with `Ex_cancer-biomass[s]`. The article text (which would label the files) was not read.
  - **Counts (derived, `mmc1.xls`).** 274 reactions (28 of them `Ex_` exchanges; subsystem "Objective-function" 1) and 252 metabolites (189 [c], 48 [m], 15 [s]; 237 excluding [s]). The FBCA papers state **272 reactions and 240 metabolites** (08a p.83; 08b p.282). Neither `mmc1` nor the tissue models match (mmc2 258/242, mmc3 243/233, mmc4 235/230). So the FBCA model is not the published file unchanged, or the papers count differently. Two sheet inconsistencies: `ferrocytocrome-C[m]` in the metabolite sheet vs `ferrocytochrome-C[m]` in the equations, and `isopentenyl-pPP` used in an equation but not declared.
- **ACRI 2018 (not obtained).** Graudenzi, Maspero, Damiani, LNCS 11115:16–29, doi 10.1007/978-3-319-99813-8_2: closed access (Springer); Unpaywall reports no open copy; the Milano-Bicocca repository record (https://hdl.handle.net/10281/294151) has no file attached.

---

## 2. Mechanics

### 2.1 Base FBCA (08a)

**Lattice and geometry**
- 2D rigid square lattice, h × w. It is "opened and rolled out onto a rectangular h × w lattice L through periodic boundary condition" to mimic a crypt, a lower-side open cylinder (08a p.79).
- The **lower boundary is open**: cells that reach it are deleted, modelling "expulsion of cells in the intestinal lumen" (08a p.82; Fig 1 caption p.80).
- The paper does not say which axis is periodic. The cylinder reading implies periodic left/right. The top boundary condition is not stated. → UNSPECIFIED (see §7).
- **No stem cells and no crypt-base niche.** Cells just grow, divide, and are pushed toward the open boundary (08a p.82).
- A cell is a connected domain, C(σ_i) = {l = σ_i | l ∈ L} (Eq 3, 08a p.80). The paper does not say whether connectivity is enforced.

**Update rule (Eq 4, 08a p.81)**
- Pick a lattice site l uniformly at random. Pick l′ uniformly from its Moore neighbourhood N(l).
- l is assigned to the cell containing l′ with P(l ← l′) = min{1, exp(−ΔH / k_bT)}.
- h × w × k flips are attempted per MCS, with k = 4 (Table 1, 08a p.81).
- Neighbourhood: Moore, "size" N = 1 (Table 1).

**Hamiltonian (Eq 5, 08a p.82)**

  H(L) = ½ Σ_{σi,σj∈N} J(τ(σi), τ(σj)) (1 − δ(σi,σj)) + λ Σ_i [ |C(σi)| − A_target(B_σi) ]²

- The first term is DAH adhesion between cell types, plus an abstract "empty space" type (08a p.82).
- The second term is an area constraint. Its target is a function of the accumulated biomass. The link is "a conversion factor" F = 0.02 (area/biomass) (Table 1; 08a p.82).
- The spec reads this as A_target = F·B. That form is stated explicitly only in 08b (A⊕ = B/φ with φ = 50 = 1/F; 08b Eq 5, p.284), so for 08a it is *derived*.
- There is no surface, chemotaxis, or connectivity term.

**Intracellular FBA (Eqs 1–2, 08a p.78–79)**
- The stoichiometric matrix S is built from the reactions R_j: Σ α_ji M_i ↔ Σ β_ji M_i.
- Steady state is assumed: d[M_i]/dt = 0.
- LP (Eq 2): **maximize B_σ subject to S v = 0, v_L ≤ v ≤ v_U**. The biomass rate is approximated by a biomass pseudo-reaction flux (08a p.79).
- The objective is "typically" max biomass (08a p.79). A 2018 precursor used max-ATP "normal" cells (08a p.83).
- Exchange reactions have the form M_i ↔ ∅ (08a p.79).
- Model: **HMR CORE, 240 metabolites × 272 reactions**, for every cell (08a p.83).
- **Exchange bounds (08a p.83):** each cell gets an uptake upper bound proportional to its area: U_j^{σi} = Σ_{l∈C(σi)} [M_j^l]. The sum runs over the cell's own sites, for every metabolite j with a lattice abundance.
- Table 1 abundances are per lattice site for O2, Glc, and Lact (SC1) and Gln (SC2). They are **per cell** for Gln (SC1) and Arg (both).
- Nutrient supply is "constant … across the lattice: at each MCS" (08a p.83). Consumption does not deplete the lattice, except that in SC2 lactate "relies on overall uptake and secretion" (Table 1). SC2-A says the total lactate "is influenced by the consumption/secretion of each cell", with initial value 0 and a uniform distribution (08a p.87). The lactate update rule itself is UNSPECIFIED.
- Solved each MCS for each cell ("computed via Flux Balance Analysis at each MCS", 08a p.82).
- Cell-type metabolic variants:
  - SC1: type 1 may take up lactate but not secrete it ("oxydative"); type 2 is the reverse ("fermentative") (08a p.83).
  - SC2: type 1 has pyruvate→lactate max flux reduced 70%; type 2 has proline biosynthesis reduced 100%; type 3 has cholesterol biosynthesis reduced 70% (08a p.85–86).
  - Reaction IDs are not given (UNSPECIFIED).

**Biomass → growth and the density limit (08a p.82, p.87)**
- Biomass accumulates per MCS. SC1 uses γ = 1, independent of density (08a p.87).
- SC2 adds density sensing "following [17]": the per-MCS biomass increment is multiplied by

  γ = 1 if ρ(σi) ≤ 1/F; otherwise γ = 1 − min(1, 2(F·ρ(σi) − 1))²   (08a p.87, unnumbered)

  Accumulation stops when ρ exceeds 1.5× its initial value (08a p.87). ρ is cell density. 08b defines it as ρ_c = B/A_c (08b p.283). 08a never defines ρ explicitly; it says "ρ = 1/F" at initialisation (08a p.87).
- Note: as printed, γ = 0 already at F·ρ = 1.5 (2·0.5 = 1 → 1 − 1² = 0). This matches the "1.5 times" text.

**Division (08a p.82)**
- A cell divides when |C(σi)| = A_mitosis = 50 sites. This is "initially set as double" the initial 25-site area.
- The split is "along a randomly chosen direction (either horizontal or vertical)". It is symmetric: each daughter is ≈ A_mitosis/2 and "will inherit the metabolic network of the parent cell".
- How accumulated biomass is split between daughters: UNSPECIFIED. In SC2 the initial biomass is set by ρ = 1/F, which suggests B is halved, but this is not stated.

**Death**
- Only two mechanisms:
  - (i) deletion at the open lower boundary (08a p.82);
  - (ii) the SC2-B therapy: from MCS = 2000, each cell of the most abundant type dies with probability 0.5 per MCS (08a p.88).
- No starvation death is described in 08a.

**Update order in 08a:** not given as an algorithm. The text says FBA runs "at each MCS" and the biomass determines A_target, which enters Eq 5. The spec therefore reads FBA → biomass/target update → CPM sweep, but the paper does not state the order (UNSPECIFIED; 08b gives an explicit order, see §2.2).

**Initial conditions (08a p.83–84, p.87)**
- SC1: 620 cells of 5 × 5 sites fill the whole 155 × 100 lattice (620·25 = 15500 = 155·100, derived). Each has biomass 1250 pg. Types alternate so that each cell's left and right neighbours are of the other type. 20 runs.
- SC1-B: two lateral hypoxic regions of 3875 sites each with [O2] = 0.5 fmol/site (08a p.83).
- SC2: about 250 cells with random area in [25, 50] and biomass such that ρ = 1/F. They fill half the lattice, with empty horizontal stripes (08a p.87, Fig 4E). O2 has "four different concentration levels … increased from the borders toward the center" within [0.1, 2.25] (08a p.87–88; Table 1). The individual level values are not listed (UNSPECIFIED, only the range).

**Units:** 1 site = "1 μm" (Table 1; this should be μm², see §7). 1 MCS = 1/10 h (Table 1), so 2000 MCS = 200 h (08a p.88).

### 2.2 Diffusion extension (08b) — only the differences from 08a

**Explicit per-step algorithm (08b p.282)**
1. FBA computation
2. Biomass accumulation
3. "Removal of cell death by lacking of nutrient"
4. Minimization of the Hamiltonian
5. Cell cycle phase evaluation
6. Nutrient diffusion

**FBA (08b Eqs 1–2, p.283)**
- Same LP: maximize v_b s.t. S v = 0, v_L ≤ v ≤ v_U, solved each MCS for each cell, on the same 272-reaction / 240-metabolite model [25] (08b p.282).
- Uptake bound: "constrained to be lower than the sum of the corresponding concentration values in all of the lattice sites in that cell closeness" (08b p.283). Uptake fluxes are "assumed to be proportional to the concentration".
- Which sites count depends on permeability:
  - permeable: the sites under the cell (08b p.286–287, Fig 2D);
  - impermeable: the empty sites adjacent to the cell perimeter (08b p.287, Fig 2C).

**Biomass (08b Eq 3, p.283):** B(c, s) = B(c, s−1) + γ·v_b, with ρ_c = B(c,s)/A_c.
- γ = 1 if ρ_c ≤ φ; otherwise 1 − min(1, 2(ρ_c/φ − 1))² (08b p.283).
- The same φ is the biomass→area conversion, A⊕ = B/φ, "usually set to 50" (08b p.284). This matches 08a's F = 0.02 = 1/50.

**Hamiltonian (08b Eqs 4–5, p.284):** H = D(L) + G(L).
- D = ½ Σ_{i,j∈N} J(τi,τj)(1 − δ), over the Moore neighbourhood.
- G = λ Σ_c (A_c − A⊕(B(c,s)))².
- One cell type c plus empty E: J(c,c) = 8, J(c,E) = 2 (08b p.285).
- Other parameters "as in [18]" (the ACRI 2018 paper, not on disk).

**Division (08b p.284):** each cell grows to twice its base area A_B, then splits in half along a random horizontal or vertical direction. The daughter inherits the parent's properties. 08b Fig 4 text says the "mitotic area set to 50" (08b p.288).

**Death (08b p.282, p.285):** "cellular death by starving is the only way to remove cells" in a fully closed lattice. **The starvation criterion is UNSPECIFIED** (no threshold, rule, or equation).

**Diffusion operator (08b Eq 6, p.284).** This is **not a PDE**. It is neighbourhood averaging:

  [N(l_i)] ← (D/|I|) Σ_{j∈I} [N(l_j)]

- Permeable cells: I = N ∪ l_i. Diffusion ignores the cells, and cells secrete into the sites under themselves (08b p.287).
- Impermeable cells: I = C_E ∩ (N ∪ l_i), i.e. only empty-space sites. Cells secrete into the sites on their perimeter (08b p.287).
- D is "chosen based on the nutrient species". **No values are given** (UNSPECIFIED).
- Number of averaging sweeps per MCS: UNSPECIFIED. The paper cites Dan et al. 2005 [27] only as motivation.
- The paper says the sum is weighted "D/|I|". With D ≠ 1 this operator does not conserve mass (see §7).

**Impermeable-case bookkeeping (08b p.287)**
- Nutrient concentrations are updated after each cell's FBA, and the FBA order is randomized "to avoid bias". This is sequential, conservative sharing of a limiting nutrient between neighbouring cells.
- If a cell grows into a previously empty site, that site's nutrient "is shifted … and then splitted among its neighborhood belonging to the set of empty sites".

**Scenarios (08b p.285–286)**

| Scenario | Lattice | Initial cells | Nutrient field | Sources / sinks | Duration |
|---|---|---|---|---|---|
| Closed environment ("chemostat") | 150 × 100 | 4 cells of equal area | Each step every site is reset to the lattice mean; secreted metabolites "instantaneously diffuse"; bounds v_U, v_L = [N]·A_c | None stated | 1000 steps, 10 runs (Fig 5) |
| Tissue, cross-section | 175 × 115, closed | Random cells with different initial areas | Eq 6 | 5 square vessel sources: 121 sites (top and bottom), 81 sites (three central) | 2000 MCS (Fig 7 axes), 10 runs |
| Tissue, longitudinal | 175 × 115, closed | Random cells with different initial areas | Eq 6 | One 11 × 115 central vessel | 2000 MCS, 10 runs |

- At each diffusion step, source sites are clamped (Dirichlet) to O2 = 100 fmol, glucose = 50 fmol, glutamine = 50 fmol (08b p.286).
- Lactate is not supplied; it comes only from secretion.
- At the lattice edges, unconsumed nutrients "are removed … through a constant flux value" (08b p.286). That flux value is UNSPECIFIED.
- Initial field values for the closed and tissue cases are UNSPECIFIED, except "as in [18]".
- Each tissue geometry is run with both permeable and impermeable cells, giving 4 tissue scenarios (08b p.289).

**Phenotype classification used in results (08b Fig 6–7 captions, p.290–291):**
- lactate produced (green);
- lactate consumed (orange);
- "both produced or consumed with a flux less than 0.1 fmol" (purple, i.e. no net lactate).

**Implementation:** MATLAB + COBRA. One MCS takes about 3–6 s (08b p.288).

---

## 3. Parameter table

"stated" = printed in the paper; "derived" = computed from stated values.

| Symbol | Value | Units | Meaning | Source | Kind |
|---|---|---|---|---|---|
| h × w (08a SC1) | 155 × 100 | sites | lattice | 08a p.81 Table 1 | stated |
| h × w (08a SC2) | 150 × 105 | sites | lattice | 08a p.81 Table 1 | stated |
| h × w (08b closed) | 150 × 100 | sites | lattice | 08b p.285 §2.2.1 | stated |
| h × w (08b tissue) | 175 × 115 | sites | lattice | 08b p.285 §2.2.1 | stated |
| space unit | 1 site = "1 μm" | — | conversion (area reading ambiguous) | 08a p.81 Table 1 | stated |
| time unit | 1 MCS = 0.1 h | h | conversion | 08a p.81 Table 1 | stated |
| k | 4 | flips/site/MCS | attempts per MCS = h·w·k | 08a p.81 Table 1, Eq 4 | stated |
| N | 1 (Moore) | — | neighbourhood for flips and adhesion | 08a p.81 Table 1; 08b p.284 | stated |
| k_BT | 3 | energy | temperature | 08a p.81 Table 1 | stated |
| λ | 1 (SC1), 4 (SC2) | — | area rigidity | 08a p.81 Table 1 | stated |
| λ (08b) | UNSPECIFIED ("as in [18]") | — | area rigidity | 08b p.285 | — |
| A_mitosis | 50 | sites | division area (2× initial 25) | 08a p.81 Table 1, p.82; 08b p.288 | stated |
| J(A,A) | 4 (SC1), 4 (SC2) | — | same-type adhesion | 08a Table 1 | stated |
| J(A,B) | 4 (SC1), 8 (SC2) | — | different-type adhesion | 08a Table 1 | stated |
| J(cell, empty) | 0.5 (SC1), 2 (SC2) | — | cell–empty adhesion | 08a Table 1 | stated |
| J(c,c), J(c,E) (08b) | 8, 2 | — | single type + empty | 08b p.285 | stated |
| F | 0.02 | sites/pg | area/biomass conversion | 08a Table 1 | stated |
| φ (08b) | 50 (= 1/F) | pg/site | biomass→area and density threshold | 08b p.283–284 | stated ("usually") |
| γ | piecewise, see §2.1 | — | density growth limit (1 in SC1) | 08a p.87; 08b p.283 | stated |
| [O2] | 6 (SC1); [0.1, 2.25] in 4 levels (SC2); 0.5 in hypoxic zones (SC1-B) | fmol/site | abundance | 08a Table 1, p.83, p.87 | stated (SC2 level values UNSPECIFIED) |
| [Glc] | 0.5 (SC1), 0.4 (SC2) | fmol/site | abundance | 08a Table 1 | stated |
| [Lact] | 0.5 (SC1); dynamic from 0 (SC2) | fmol/site | abundance | 08a Table 1, p.87 | stated |
| [Gln] | 20 fmol/cell (SC1); 0.4 fmol/site (SC2) | — | abundance | 08a Table 1 | stated |
| [Arg] | 20 | fmol/cell | abundance | 08a Table 1 | stated |
| hypoxic zones (SC1-B) | 2 × 3875 | sites | low-O2 regions | 08a p.83 | stated |
| initial cells SC1 | 620, 5×5, B = 1250 pg | — | IC | 08a p.84 | stated |
| initial ρ | 1250/25 = 50 = 1/F | pg/site | IC density | 08a p.84, p.87 | derived |
| initial cells SC2 | ≈250, area U[25,50], ρ = 1/F | — | IC | 08a p.87 | stated |
| therapy death prob. | 0.5 per MCS, from MCS 2000, dominant type | — | SC2-B | 08a p.88 | stated |
| SC2 flux caps | −70% (rxn 1), −100% (rxn 2), −70% (rxn 3) | — | type 1/2/3 max flux reductions | 08a p.86 | stated (reaction IDs UNSPECIFIED) |
| metabolic model | HMR CORE, 240 met × 272 rxn | — | per-cell network | 08a p.83; 08b p.282 | stated |
| source clamps (08b) | O2 100, Glc 50, Gln 50 | fmol per source site | vessel Dirichlet | 08b p.286 | stated |
| vessel areas (08b) | 121 (×2), 81 (×3); 11×115 | sites | source geometry | 08b p.285–286 | stated |
| D (08b Eq 6) | UNSPECIFIED | — | averaging coefficient per species | 08b p.284 | — |
| edge efflux | UNSPECIFIED ("constant flux value") | — | boundary loss | 08b p.286 | — |
| lactate phenotype cut | 0.1 | fmol | "no lactate flux" band | 08b p.290 Fig 6 | stated |
| runs | 20 (08a SC1, SC2-A); 5 (SC2-B, Fig 6A); 10 (08b) | — | ensemble size | 08a p.84, p.91; 08b Fig 5, 7 | stated |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | 2D CPM of intestinal crypt with adhesion + volume | **CONFIRMED** (08a); **CORRECTED** for 08b | 08a Eq 5, p.79–82: 2D, DAH adhesion plus an *area* term. 08b models a generic culture or tissue, not a crypt (08b p.284–285). |
| 2 | Stem cells at base, cells leave at top | **CORRECTED** | 08a has no stem cells. The lattice is open at the **lower** side and cells reaching it are deleted (08a p.82, Fig 1 p.80). 08b is fully closed; the only removal is starvation (08b p.285). |
| 3 | Each cell has its own FBA model, human central-carbon core, 272 reactions × 240 metabolites (from FI 2020) | **CONFIRMED** | 08b p.282. Also 08a p.83: "HMR CORE … 240 metabolites and 272 reactions". The network is inherited at division (08a p.82). |
| 4 | Objective = max biomass | **CONFIRMED** | 08a Eq 2 p.79 ("typically"); 08b Eq 2 p.283. |
| 5 | Exchange bounds from local nutrient availability (glucose/glutamine under the cell's sites) | **CORRECTED** (broader) | The bound is U_j = Σ_{l∈C(σ)} [M_j^l] for **every** supplied metabolite (O2, Glc, Lact, Gln, Arg), not only Glc and Gln (08a p.83). Some are given per cell rather than per site (Table 1). In 08b the sites are those under the cell (permeable) or adjacent empty sites (impermeable) (08b p.287). |
| 6 | Biomass flux → target-volume growth | **CONFIRMED** (as target *area*) | 08a p.82, Eq 5, F = 0.02; 08b Eq 3 and A⊕ = B/φ (φ = 50), p.283–284. |
| 7 | Divide at volume threshold | **CONFIRMED** | Area = A_mitosis = 50 (2× initial), random horizontal or vertical split (08a p.82; 08b p.284). |
| 8 | FI 2020 adds nutrient and lactate diffusion with uptake/secretion as field sinks/sources over the cell's sites | **CORRECTED** | Diffusion is **neighbourhood averaging** (Eq 6), not a PDE. Vessel sites are clamped sources (Dirichlet); edges lose mass by an unspecified constant flux. Uptake and secretion are over the cell's own sites **only for permeable cells**; impermeable cells exchange with adjacent empty perimeter sites (08b p.284–287). |
| 9 | Population oscillations from synchronized divisions unless density-dependent growth control | **CORRECTED** (supported by figures only, not by the text) | Supporting figures: 08a Fig 2E/F/I (p.84) show **sustained sawtooth oscillations** of cell number, mean area and mean biomass in SC1 (γ = 1, no density control, synchronous 5×5 initial cells), period ≈110–120 MCS by eye. 08b Fig 5B (p.289) shows **damped** oscillations of mean cell area (≈25–45 sites, period ≈75 MCS) with the density limit on (08b p.285), starting from 4 identical cells. Correction: neither text discusses oscillations or attributes them to synchrony. 08a motivates the density factor only as preventing "unrestrained increase in cell density" (p.87), and 08b's abstract mentions "population oscillations" generically (p.279). 08b oscillates even with density control, so "unless density control" is **not** established. The dedicated study [17]/[23] (Maspero 2019) is not on disk. |
| 10 | Clonal takeover | **CONFIRMED** | 08a p.89: from 620 clones to about 10 by MCS 2000 (Fig 2G); a clone of about 430 cells in SC1-B (p.89); type 1 dominates SC2-A in all runs (p.90); type 2 or 3 recolonises after therapy (p.90–92). |
| 11 | Spatial nutrient depletion | **CORRECTED** | 08a: supply is constant each MCS, so there is no depletion (p.83); spatial heterogeneity is *prescribed* (hypoxic zones, O2 levels). 08b closed environment: *temporal* depletion of glucose then a switch to lactate (Fig 5A, p.288–289). 08b tissue: cells stay near vessels (Fig 7C, D, G, H). No depletion map is shown. |

Counts: CONFIRMED 6 (claims 1, 3, 4, 6, 7, 10; claim 1 is confirmed for 08a only). CORRECTED 5 (claims 2, 5, 8, 9, 11). NOT IN PAPER 0. Part of claim 9 (density control suppressing oscillations) is not in either paper.

---

## 5. Validation targets

Policy: ensemble or statistical agreement, no bitwise parity. FBA optima can be degenerate, so compare biomass and fluxes, not flux vectors, unless a tie-break rule is fixed.

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| V08a-1 | SC1-A: type-1 count "constantly decrease[s], in all 20 runs, approaching values close to zero after around 1500 MCSs"; type 2 rises from 310 to ≈500–600 | 08a p.88, Fig 2E | qualitative + timing | type-1 count at MCS 2000 below 30% of its initial 310 in ≥ 18/20 runs (Fig 2E shows several runs still at ≈100–170, so do not require extinction); type-2 ensemble median at 2000 in [450, 650] |
| V08a-1b | SC1-A: sustained sawtooth oscillation of cell number, mean area (≈20–32 sites) and mean biomass (≈2000–2500 pg) with period ≈110–120 MCS (by eye) | 08a Fig 2E/F/I (p.84) | semi-quantitative (digitised) | dominant period from FFT within ±20%; oscillation persists to MCS 2000 |
| V08a-2 | SC1-A: type 1 makes 11% more biomass than type 2 (per-cell FBA) | 08a p.88 | quantitative (LP-level) | FBA biomass ratio 1.11 ± 0.02 at SC1 abundances (tests the FBA component alone) |
| V08a-3 | SC1-A: 620 clones → "around 10" by MCS 2000; median clone size about 60 at end | 08a p.89, Fig 2G | quantitative, stochastic | ensemble median clone count in [5, 20] |
| V08a-4 | SC1-A: type-2 duplication-time histogram shifted right of type 1. By eye from Fig 2H: range ≈40–170 MCS; type-2 mode ≈120; type-1 mass ≈60–110 | 08a p.88–89, Fig 2H | qualitative + semi-quantitative | median(type 2) > median(type 1), Mann–Whitney p < 0.05; overall range within ±20% |
| V08a-5 | Vertical-stripe clonal patterns | 08a p.88, Fig 2A–D | qualitative | visual / anisotropy of clone shapes (vertical correlation length > horizontal) |
| V08a-6 | SC1-B: two outcome classes, takeover (mostly type 1) or coexistence; no full extinction by 2000 MCS | 08a p.89, Fig 3E | qualitative, distributional | both outcomes present in 20 runs; type 1 wins in the majority |
| V08a-7 | SC1-B: duplication-time distribution has a long right tail | 08a p.89, Fig 3H | qualitative | skewness > 0 and larger than SC1-A |
| V08a-8 | SC2-A: type 1 dominates in all runs; types 2 and 3 have similar trajectories; biomass distributions similar across types; advantage comes from faster duplication | 08a p.90, Fig 4B–D | qualitative | type 1 majority in ≥ 95% of runs; KS test on biomass distributions not significant |
| V08a-9 | SC2 LP surface: biomass ratio vs (O2, cell area) per type (Fig 4A) | 08a p.86–87, Fig 4A | quantitative (FBA only) | reproduce trends: type 1 limited at low O2; types 2 and 3 limited at high O2; type 3 also falls with area |
| V08a-10 | SC2-B: after therapy at 2000 MCS, type 1 is wiped out in a few MCS; type 2 **or** 3 recolonises in about 500 MCS (about 50 h) | 08a p.88, p.90–92, Figs 5–6 | qualitative + timing | recolonisation time within ±50% of 500 MCS; both winners observed across runs |
| V08a-11 | SC2-B: type-2 duplication time falls after therapy; type 3 about unchanged | 08a p.92, Fig 6B | qualitative | direction of change |
| V08b-1 | Closed environment: diauxie. Read by eye from Fig 5A (totals ×10⁵): glucose ≈15.5 → 0 at ≈780 MCS; glutamine ≈7.8 → ≈0 by 1000; lactate 0 until ≈300 MCS, peaks ≈18 at ≈780, then declines as it is consumed. Snapshots at 20/500/780/1000 MCS show red → blue (Fig 4) | 08b p.288–289, Figs 4–5A | semi-quantitative (digitised) | glucose-exhaustion MCS and lactate-peak MCS within ±20%; peak/initial ratios within ±30% (absolute totals depend on the unspecified initial field) |
| V08b-2 | Closed environment: mean cell area shows **damped oscillations** (≈25–45 sites; period ≈75 MCS by eye) from 4 synchronous cells, relaxing to ≈30–33 by 700–1000 MCS | 08b Fig 5B, p.289 | semi-quantitative (digitised) | period within ±20%; oscillation damped (third peak amplitude < first); late mean in [28, 36] |
| V08b-3 | Tissue, permeable: "no lactate flux" (purple) cells vanish by MCS 200; producers are more numerous and farther from vessels than consumers | 08b p.292, Fig 7A, C, E, G | qualitative | ordering of counts and mean distances |
| V08b-4 | Tissue, impermeable: all three lactate phenotypes persist; producers are least abundant; steady state after about 200 MCS; longitudinal geometry more variable than cross-section | 08b p.292, Fig 7B, D, F, H | qualitative | ordering; SD(longitudinal) > SD(cross) |
| V08b-5 | Diffusion operator only: impermeable cells shade the field and slow diffusion vs permeable (5 static cells) | 08b Fig 3, p.287 | qualitative | unit test of the field operator |

---

## 6. Required general features

| ID | Need in FBCA | Notes |
|---|---|---|
| G1 | `@retire` for lower-boundary expulsion (08a), starvation death (08b), and therapy death `rand(Bernoulli(0.5))` per MCS after t = 2000 for the dominant type (08a p.88); `@create` via division | "Dominant type" needs a population observable (G12) evaluated at trigger time |
| G2 | Not required (area term only) | — |
| G3 | Not required | — |
| G4 | Not required. The paper states connected domains but no enforcement (08a Eq 3) | Optional |
| G5 | 08a: per-site static fields with region layouts (hypoxic stripes, 4 O2 bands) and per-MCS reset to the prescribed values (constant supply). 08b: Dirichlet source regions, a boundary "constant flux" outflow BC, a **non-PDE averaging operator** (Eq 6) with a masked neighbourhood (impermeable: empty sites only), and a closed-environment "reset to lattice mean" operator | Needs G14 below (custom field operator), or an equivalent diffusion stencil. The masked stencil depends on the cell lattice |
| G6 | **Core requirement.** Per-cell uptake bound = Σ of field over a cell-dependent site set (own sites, or adjacent empty sites). Secretion is deposited over the same set. It must be **conservative** and **sequential with a randomized cell order** so that shared sites are not double-consumed (08b p.287) | The site-set choice (interior vs exterior perimeter) must be a parameter |
| G7 | 08b impermeable: when a cell takes an empty site, that site's nutrient is redistributed to neighbouring empty sites (08b p.287) | A hook on the copy event that moves field mass; generalises to "field carried or displaced by a site conversion" |
| G8 | Default Metropolis with Moore neighbourhood; k = 4 attempts per site per MCS (08a Table 1) | Attempts-per-MCS must be a parameter |
| G9 | **Per-cell FBA component.** See the interface below | Central feature |
| G10 | Clone lineage id (ancestor), sibling relation at division, clone-size distributions | Lineage tracking for Fig 2G, 3G |
| G11 | Not required | — |
| G12 | Cell counts per type; mean area and biomass per type; duplication-time histogram (needs a per-cell birth time); clone-size distribution; per-cell exchange-flux sign classification (lactate in/out/none with a 0.1 cutoff); distance from cell centroid to nearest source barycentre (08b Fig 7); total field amounts (08b Fig 5A) | — |
| G13 | Tiled 5×5 square cells filling the lattice with alternating types (08a SC1); random-area cells in horizontal stripes over half the lattice (SC2); a few equal cells (08b closed); random fill (08b tissue); geometric source regions (squares, rectangles) | — |
| **G14 (new)** | **User-defined discrete field operator.** A per-step stencil update with an arbitrary per-site neighbourhood mask derived from the cell lattice, run at a declared point in the step order. Justification: 08b Eq 6 is not a PDE discretisation (non-conservative D/|I| weight; mask from occupancy), so neither a PDE solver nor G5's SteadyState covers it | Could be satisfied by making G5's stencil pluggable |
| **G15 (new)** | **Explicit step schedule.** An ordered list of per-MCS phases (08b p.282: FBA → biomass → death → CPM → division → diffusion) | Could fold into G9 cadence plus a global schedule. Listed because 08b fixes the order |

### G9 — per-cell component interface required by FBCA

- **Component:** an LP over a shared stoichiometric matrix S (one model for all cells). Per-cell state is limited to (a) bound vectors v_L and v_U, which can be edited per cell type (flux caps for SC2 types; lactate uptake-only vs secretion-only for SC1 types), and (b) accumulated biomass B.
- **Inputs, each MCS:**
  - for each exchange reaction j, an upper uptake bound = Σ over the cell's site set of field_j (G6), or a per-cell constant (Gln and Arg per cell in 08a);
  - cell area A (for ρ = B/A in γ).
- **Solve:** maximize the biomass reaction; return v* (08a Eq 2; 08b Eq 2).
- **Outputs:**
  - v_b → B ← B + γ(ρ)·v_b (08b Eq 3);
  - target area A⊕ = F·B = B/φ, which feeds the CPM area term;
  - exchange fluxes v_ex, which become field sinks and sources over the site set (08b; 08a only for lactate in SC2).
- **Cadence:** every MCS (08a p.82; 08b p.283), before the CPM sweep (08b p.282). In the impermeable case, solves must run sequentially in random order with a field write-back after each solve (08b p.287).
- **On division:** the daughter "will inherit the metabolic network" (08a p.82), i.e. the bound edits. B partitioning is UNSPECIFIED; halving is the natural choice given ρ = 1/F initialisation.
- **On death:** discard. No release of cell contents to fields is described.
- **Solver:** the LP backend must be swappable (COBRA in the paper; COBREXA or JuMP in Julia per `legacy-spec-adjudication.md`). Degenerate optima: the paper does not say whether pFBA or any tie-break is used (UNSPECIFIED).

---

## 7. Ambiguities and open questions (what to ask the authors)

1. **Units:** "1 lattice site = 1 μm" (08a Table 1). Is that a 1 μm edge (1 μm² area)? A cell of 25 μm² is implausibly small for crypt epithelium. Is it perhaps 1 site = 1 μm²?
2. **Periodic axis and top boundary** in 08a: which axis wraps? Is the top wall closed?
3. **ρ in 08a** is not defined. Confirm ρ = B/|C|, as in 08b.
4. **Biomass on division:** is B halved between daughters, or split by area?
5. **Degenerate FBA optima:** is pFBA or a secondary objective used? This matters for lactate phenotype classification (08b Fig 6).
6. **Exchange bound form:** uptake flux "proportional to concentration" (08b p.283) versus an upper bound equal to the sum (08a p.83). Is there a rate constant, or is the bound simply equal to the local amount per MCS?
7. **08a SC1 nutrient bookkeeping:** is the field reset to Table 1 values every MCS (no depletion)? How exactly is SC2 lactate updated (global pool, or per site)?
8. **08b Eq 6:** the value(s) of D per species; how many sweeps per MCS; whether D < 1 is intended as decay (the operator is non-conservative).
9. **08b boundary efflux** "constant flux value": the value, and whether it applies to all four edges.
10. **08b starvation death rule:** a threshold on v_b? On infeasible LP? On biomass decrease?
11. **SC2 flux-capped reaction IDs** in HMR CORE, and the four O2 level values and band geometry.
12. **08b "parameters as in [18]"** (ACRI 2018): λ, k_BT, attempts per MCS, and initial field values for 08b. We need that paper or the authors' code. STILL OPEN: the paper is closed access and has no repository copy (checked 2026-09-30, §1).
13. **Code or model files:** none are linked. **Model file partly resolved 2026-09-30:** the published HMR core is on disk (`mmc1.xls`, §1), but it has 274 reactions × 252 metabolites, not the stated 272 × 240. STILL OPEN: which reactions and metabolites differ (and whether bounds or the biomass reaction changed), and the MATLAB sources.
