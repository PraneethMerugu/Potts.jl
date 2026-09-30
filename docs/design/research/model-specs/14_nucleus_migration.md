# 14 — Compartmentalised 3D crawling cell (nucleus/cytoplasm/lamellipodium): Fortuna base, Thomas polarization, Dal-Castel chemotaxis (paper-grounded spec)

## 1. Sources

| Prefix | Citation | DOI | PDF on disk | Role |
|---|---|---|---|---|
| **14a** | I. Fortuna, G.C. Perrone, M.S. Krug, E. Susin, J.M. Belmonte, G.L. Thomas, J.A. Glazier, R.M.C. de Almeida, "CompuCell3D Simulations Reproduce Mesenchymal Cell Migration on Flat Substrates", *Biophys. J.* **118** (2020) 2801–2815 | 10.1016/j.bpj.2020.04.024 | `docs/references/14a_Fortuna2020_BiophysJ_nucleus-migration.pdf` (15 pp.) | **Base model (primary definition)** |
| **14a-code** | I. Fortuna, G.L. Thomas et al., CC3D project `SF1_Code.zip` ("written between 2014-2015", codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:9), cited as 14b ref. [14] | – | `docs/references/codebases/14a_Fortuna2020_Crawling/`: `SF1_Code.zip` plus extracted `Published/CellMig3D.cc3d` (5 lines), `Published/Simulation/CellMig3D.py` (302 lines), `Published/Simulation/CellMig3D_Steppables.py` (416 lines), `Published/Simulation/ParameterScanSpecs.xml` (20 lines). Source: https://lief.if.ufrgs.br/pub/biosoftwares/Crawling/SF1_Code.zip. Zip entry dates: 2017-08-16 (`.cc3d`), 2021-08-12/13 (Python, XML), i.e. repackaged after 14a appeared. | **Released code for the base model** (§2.9) |
| **14b** | G.L. Thomas, I. Fortuna, G.C. Perrone, F. Graner, R.M.C. de Almeida, "Shape–velocity correlation defines polarization in migrating cell simulations", *Physica A* **587** (2022) 126511. On disk as arXiv:2103.12879v3 (7 Oct 2021). | 10.1016/j.physa.2021.126511 (DOI not printed in the arXiv PDF; taken from 14c ref. [12]) | `docs/references/14b_Thomas2022_PhysicaA_shape-velocity-polarization_arXiv.pdf` (16 pp.) | Polarization observables; restates the model |
| **14c** | P.C. Dal-Castel, G.L. Thomas, G.C. Perrone, R.M.C. de Almeida, "CompuCell3D Model of Cell Migration Reproduces Chemotaxis", *Physica A* (2025). On disk as **arXiv:2312.00776v1 (1 Dec 2023)**. | not printed in the PDF on disk | `docs/references/14c_DalCastel2025_PhysicaA_chemotaxis_arXiv.pdf` (35 pp.) | **Chemotaxis variant** |
| **14c-code** | P.C. Dal-Castel, *Single_Cell_Chemotaxis_2.3* (CC3D 4.2.3 project), cited as 14c ref. [23] | – | https://github.com/pdalcastel/Single_Cell_Chemotaxis_2.3 @ `c1353d35286ba3ef0362356fbc6b6f4c1f69a670` (23 Jan 2023). Files: `SCellSign_DISTRIBUTED/Simulation/SCellSign.py` (180 lines), `SCellSign_DISTRIBUTED/Simulation/SCellSignSteppables.py` (329 lines) | Released code for 14c |
| **14c-SM** | P.C. Dal-Castel, *CC3D-Chemotaxis-SuppMat*, cited as 14c ref. [30] | – | https://github.com/pdalcastel/CC3D-Chemotaxis-SuppMat @ `21974b8cc47a4f8d9fcaa7cfdcfd4ba9598799b1` (`SuppMat_Chemotaxis_CC3D_2024.pdf`, 14 pp., dated 8 Nov 2024) | Supplementary tables S1–S2 (**not in `docs/references`**) |
| **14a-S1** | Fortuna et al. 2020, Supporting Material, Document S1 ("Supporting Materials and Methods, Figs. S1–S5, and Table S1"), 12 pp., PDF dated 28 May 2020 | – | **On disk** (obtained 2026-09-30): `docs/references/supplementary/14a_Fortuna2020_DocumentS1_mmc1.pdf`, from the publisher's supplementary CDN (https://ars.els-cdn.com/content/image/1-s2.0-S0006349520303490-mmc1.pdf; the same file PMC7264849 lists as mmc1.pdf). Cited by PDF page. | Run instructions (S2), fitting procedure (S1), lattice rule (Eq. S1), output-file columns, Table S1 |
| **14a-instr** | `Instructions_To_Run.pdf`, 4 pp., PDF dated 28 Aug 2021 | – | **On disk**: `docs/references/codebases/14a_Fortuna2020_Crawling/Instructions_To_Run.pdf` (https://lief.if.ufrgs.br/pub/biosoftwares/Crawling/Instructions_To_Run.pdf). A lightly edited copy of 14a-S1 §S2, shipped next to `SF1_Code.zip`. | Run instructions for 14a-code |
| **14a-nH** | nanoHUB tool `gltcellcrawl`, "CompuCell3D - Simulation of cell crawling in 3D", v1.0, published 3 Feb 2022, submitters J. Ferrari Gianlupi and T.J. Sego, GPL-3 | 10.21981/YXKM-4E26 | **On disk** (obtained 2026-09-30): `docs/references/codebases/14a_Fortuna2020_nanoHUB_gltcellcrawl-r3/` (`gltcellcrawl-r3.tar.gz` + extracted), from the public source download https://nanohub.org/resources/sourcecode?tool=gltcellcrawl_r3. Files `main/Simulation/CellMig3D_P3.py` (**nH:P3**) and `main/Simulation/CellMig3D_P3_Steppables.py` (**nH:P3S**). | Python 3 / CC3D 4.2.2 port of 14a-code (§2.9.8) |
| **CC3D-src** | CompuCell3D C++ sources, https://github.com/CompuCell3D/CompuCell3D, branch `3.7.9` @ `ca3d6472be6956768c413d248bbe900ecd327e8b` and branch `3.6.2` @ `afc402799d076d8e3524ac172ebaa5f334ddb382` | – | **On disk** (sparse subsets): `docs/references/codebases/14a_CC3D-3.7.9_DiffusionSolverFE/` (`steppables/PDESolvers/`, `plugins/Chemotaxis/`) and `docs/references/codebases/14a_CC3D-3.6.2_DiffusionSolverFE/` (`steppables/PDESolvers/`). Cited as **CC379:** and **CC362:** + path below `CompuCell3D/core/CompuCell3D/`. | Solver order, secretion neighbourhood, chemotaxis formula (§2.9.2, §2.9.4) |

**Page conventions.**
- 14a uses journal pages 2801–2815; PDF page = journal page − 2800.
- 14b and 14c use the printed arXiv page numbers, which equal the PDF page numbers.
- 14c-SM pages are its own printed pages.
- Code citations are `file:line` at the commits above. `SCellSign.py` is abbreviated **SC**, and `SCellSignSteppables.py` is abbreviated **SS**.
- 14a-code citations are written in full as `(codebases/14a_Fortuna2020_Crawling/<path>:line)`, with paths relative to `docs/references/`.
- "(CC3D-external)" marks a statement about CompuCell3D internals that comes from general CC3D knowledge, not from a file on disk. The solver order, the secretion-on-contact neighbourhood and the chemotaxis formula **have now been checked** against CC3D-src (2026-09-30; §2.9.2, §2.9.4) and are cited as CC379:/CC362: instead. The Potts → C++ steppable → Python steppable order (§2.9.6) and the z-boundary default remain CC3D-external.

**Version caveat.** The 14c on disk is arXiv **v1 (2023)**, not the 2025 Physica A version of record (*Physica A* **666** (2025) 130524, doi 10.1016/j.physa.2025.130524). Checked 2026-09-30: arXiv has **only v1** (no later revision), and the version of record is **closed access** (Elsevier licence; Unpaywall reports no open copy). The diff could not be made; parameters and equations may differ in the published version. The code commit (Jan 2023) predates the arXiv v1.

**Not read.**
- 14a Video S1 (`mmc2.mp4`) and Document S2 (`mmc3.pdf`, "Article plus Supporting Material"). Not needed: Document S1 is on disk.
- 14b Supplementary (Tables S1–S2, Figs. S1–S21). Not on disk.
- 14c version of record (see the version caveat).

**Read 2026-09-30 (pre-send checks).** 14a-S1 in full; 14a-instr in full; 14a-nH diffed against 14a-code (§2.9.8); CC3D-src `DiffusionSolverFE` and `Chemotaxis` (§2.9.2, §2.9.4). 14a-S1 does **not** contain the code itself (its §S2 describes the project files; PMC lists no code file), so it was compared with 14a-code by content (§2.9, §2.9.7 items 5, 6, 12, 16). The code (`SF1_Code.zip`) **has been read in full**; see §2.9.

**Scope rule used below.** "14a" means the base model as the Fortuna paper defines it. "14c" and "14c-code" mean the chemotaxis variant. Where the 14c code differs from 14a, both values are listed and the conflict is flagged. Code values are not treated as 14a facts. Likewise "14a-code" (the Fortuna `SF1_Code.zip`) is kept separate from "14a" (the paper); every paper-vs-code difference is listed in §2.9.7.

---

## 2. Mechanics — BASE MODEL (Fortuna, 14a)

### 2.1 Representation: one cell = three compartments

- Lattice sites carry a cell label σ and a compartment label **C**: nucleus C = 1, cytoplasm C = 2, lamellipodium C = 3 (14a p.2805).
- In CompuCell3D terms, "each cell compartment … as a single CompuCell3D generalized cell and the modeled cell as a CompuCell3D cell cluster" (14a p.2805).
- **Substrate** and **medium** are "additional types of generalized cell" (14a p.2805).
- Only single-cell simulations are reported. The energy "generalizes easily to arbitrary numbers of cells" (14a p.2805). Contact energies between compartments of **different** cells are UNSPECIFIED.

### 2.2 Effective energy (Eq. 3, 14a p.2805)

E = E_interface + E_target volume + E_F-actin.

The paper's conceptual section also says "Volume and interfacial area constraints over all cell compartments" (14a p.2805). However, **Eq. 3 contains no surface or area term**, and Table 1 lists no surface parameter. This spec follows Eq. 3; see §9.

**Interface energy, Eq. 4** (14a p.2805):

E_interface = Σ_r Σ_{v(r)} J(σ(r), C(r); σ(v), C(v)) · [1 − δ(σ(r) − σ(v))] · [1 − δ(C(r) − C(v))]

- The sum over v(r) covers the "fourth-neighbor range around r (32 neighbors) to reduce lattice anisotropy" (14a p.2805).
- The double sum over r and v counts each pair twice, and no ½ factor is printed. This matches CC3D convention.
- Note on the delta product as printed: J is zero whenever the two sites share **either** σ **or** C. Read literally, two compartments of the same cell (same σ, different C) would have **no** contact energy. That contradicts the intra-cell J values in Table 1 (for example J_cyto-nucleus). The text says J = 0 "for neighboring lattice sites that belong to the same cell and compartment". So the intended rule is J = 0 only when **both** labels match. See §9.
- All other J values are positive ("ferromagnetic", 14a p.2805). The hierarchy is chosen so the cytoplasm surrounds the nucleus and the lamellipodium stays attached to cytoplasm, substrate and medium (14a p.2805–2806).

**Volume energy, Eq. 5** (14a p.2805):

E_target volume = Σ_{C=1}^{3} λ_C (V_C − V_C^target)².

- Target volumes: V_cell^target = (4π/3) R_cell³, V_1^target = φ_n V_cell and V_3^target = φ_l V_cell (14a p.2806).
- V_2^target is not stated. It is **derived** as (1 − φ_n − φ_l) V_cell, assuming the compartments sum to the cell volume. 14c-code does exactly this: `phiC=1.-phiN-phiF` (SC:28).
- Compartment volumes stay "within 1% of their target values" (14a p.2806).

### 2.3 F-actin field (Eq. 6, 14a p.2805)

∂F(r,t)/∂t = D_F ∇²F(r,t) + k_source δ(C(x,y,1) − 3) − k_decay F(r,t).

- **Source.** Only at lamellipodium sites **in the z = 1 layer**, the sites "that touch the substrate" (14a p.2806). This implies the substrate occupies z = 0, although the text does not say so. **14a-code:** `SecretionOnContact` of FRONT with SUBS_A at rate 0.9, and SUBS_A is exactly the z = 0 plane (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:253; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–81). See §2.9.2.
- **Decay.** Represents depolymerisation. It also "cleans up the model artifact" that F-actin leaks out of a moving cell (14a p.2806).
- The field is defined on the whole lattice. It is not confined to the cell, and the paper states no field boundary conditions (UNSPECIFIED). **14a-code:** also whole-lattice and unconfined (no confinement option in codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253), despite the header comment "confined to the cell volume" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:3).
- The PDE solver, its time step and the number of solver steps per MCS are UNSPECIFIED. The paper refers to CC3D. 14b says Eq. 9 "is solved during the simulations by a tool included in the CC3D environment" (14b p.4). **14a-code:** CC3D `DiffusionSolverFE`, called once per MCS (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244). Internal sub-stepping is CC3D-internal (§9 item 1).
- Intended profile: roughly constant inside the lamellipodium and nearly zero outside (14a p.2806; Fig. 3).

### 2.4 F-actin protrusion work term (Eq. 7, 14a p.2806)

ΔE_F-actin = λ_F-actin [F(v) − F(r)] · δ(C(r) − 3) · δ(σ(v) − medium).

- r is the **source** site, which is lamellipodium. v is the **target** site, which is medium. The term applies only to copies that extend the lamellipodium into medium.
- F(r) > F(v) inside the lamellipodium, so ΔE < 0 and extension is favoured.
- The term is added to ΔE at copy time. It is a work term, not a potential ("non-conservative", 14b p.4).
- It acts as a force of magnitude −ΔE/(copy distance) along v − r, with copy distance = 1 (14a p.2805–2806).
- λ_F-actin > 0 is the "force per area per unit F-actin" (14a p.2806).
- **14a-code:** CC3D `Chemotaxis` plugin, `Type="FRONT"`, `ChemotactTowards="Medium"`, `Lambda=-150` (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48, 260–263). In CC3D's sign convention this equals Eq. 7 with λ_F-actin = +150 (CC3D-external; §2.9.4).

### 2.5 Lamellipodium creation (site conversion), 14a p.2806

- "after each Monte Carlo step, we convert any cytoplasm lattice site that touches substrate into a lamellipodium lattice site with a probability proportional to (1 − V_3/V_3^target)".
- The proportionality constant is **UNSPECIFIED**. The behaviour when V_3 > V_3^target (negative "probability") is **UNSPECIFIED**; presumably no conversion.
- "Touches substrate" is taken to mean z = 1 cytoplasm sites (derived from the Eq. 6 source convention). The neighbourhood used for "touches" is UNSPECIFIED.
- There is **no reverse conversion** (lamellipodium → cytoplasm) by rule. Lamellipodium volume also changes through ordinary copies (cytoplasm overwriting lamellipodium, 14a Fig. 3 step 2).
- This process matters "only when the lamellipodium volume V_3 is much different from its target value", that is, at early times (14a p.2806).
- **14a-code:** p = 0.1·(1 − V_3^target/(φ_l · V_total^target)), using the lamellipodium **target** volume, which starts at 1.5 and grows only through conversion. Candidates are cytoplasm sites at z = 1. Conversion is sequential, with p recomputed after each conversion (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:127–165). See §2.9.5.

### 2.6 Dynamics and acceptance (14a p.2805)

- Pick a random source site and an **adjacent** target site. If they differ in σ or C, propose copying (σ, C) from source to target.
- Accept if ΔE ≤ 0. Otherwise accept with probability exp(−ΔE/T_B).
- **Copy distance = 1.** Together with "adjacent", this is consistent with first-neighbour (6-neighbour) proposals. 14b states "a pair of nearest neighbors" (14b p.3), and 14c-code uses `NeighborOrder 1` (SC:76).
- **MCS** = N = L_x L_y L_z copy attempts (14a p.2805).
- **Order within one MCS.** N copy attempts, then conversion (§2.5). The ordering of the PDE solve relative to these is UNSPECIFIED. **14a-code:** Potts sweep, then `DiffusionSolverFE`, then the `Cell` (conversion) and `Calc` (analysis) Python steppables (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244, 290–300; the C++-then-Python steppable order is CC3D-external).
- **Stability guideline** (14a p.2806). The CPM "numerical stability speed limit of 0.1–0.2 lattice sites/MCS". Parameters are chosen so that typical e^{−ΔE/T_B} ≲ 0.1, and E_interface/T_B ≈ 1.

### 2.7 Lattice, boundaries, initial condition (14a p.2806)

- 3D cubic lattice, "periodic boundary conditions in the (x, y) plane", with **L_z = 2.1 R_cell** and **L_x = L_y ∈ [8 R_cell, 14 R_cell]**. The exact L_x per run is UNSPECIFIED.
- The z boundaries are UNSPECIFIED. The substrate is described as a "two-dimensional substrate plane" (14a p.2805). The paper does not say whether it is frozen, and says nothing about a top wall. **14a-code:** a frozen adherent SUBS_A plane at z = 0 and a frozen non-adherent SUBS_NA plane at z = L_z − 1, with no z boundary setting (CC3D default, non-periodic) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:104–105, 113–114; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–83). The rule is L_x = L_y = int(8R), or 10R when R ≥ 20 and φ_l ≥ 0.2 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–75).
- **Initial condition.** "Initially, the cell consists of two compartments, the cytoplasm and nucleus, with no lamellipodium." A lamellipodium forms once the cell contacts the substrate (14a p.2806). Fig. 4A shows "an initially suspended, nonpolar cell coming into contact with a substrate". The geometric details are in Supporting Material Section S2, which is not on disk. **14a-code:** a ball of radius int(R), tangent to the substrate from t = 0, with a 6×6×6 cubic nucleus and no lamellipodium (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:72, 84–105). This matches 14b, not the "suspended" cell of Fig. 4A.
- Statistics are collected only after stationary behaviour is reached (14a p.2806). The warm-up length is UNSPECIFIED in 14a. 14b waits 1000 MCS (14b p.8).

### 2.8 Observables (14a)

- **MSD and the modified Fürth equation, Eq. 1** (14a p.2804):
  ⟨|Δr|²⟩ = 2D(Δt − P(1 − e^{−Δt/P})) + (2DS/(1−S)) Δt, with 0 ≤ S < 1.
- **Natural units.** τ = t/P and ρ = r/√(2DP/(1−S)). **Eq. 2**: ⟨|Δρ|²⟩ = Δτ − (1−S)(1 − e^{−Δτ}).
- **Derived quantities.** D_fast = DS/(1−S), D_slow = D/(1−S), v_eff = (1/(1−S))√(D/P). The crossovers are at Δt = SP and Δt = P (14a p.2804).
- **Fit procedure** (14a p.2804). Fit D and P from the second derivative of the MSD. Subtract the fit, then take a linear fit at short Δt; its slope gives S and its intercept gives the localisation error. The full procedure is in SM S1, which is not on disk.
- **Velocity autocorrelation, Eq. 8.** Mean velocity u(τ, δ) = (ρ(τ+δ) − ρ(τ))/δ (**Eq. 9**) and ψ_δ(Δτ) (**Eq. 10**) (14a p.2807–2809). This is valid only for δ < Δτ.
- **Displacement after 10⁵ MCS** (Fig. 5). The regime classification (Fig. 6) is: confined (cyan), migrating (gray), lamellipodium detachment (light red).
- **Polarization in 14a** is "the distance between the lamellipodium and nucleus centers of mass" (14a p.2813, Fig. 12). **14b** later prefers a different definition (§3).
- **S vs D collapse.** S = D_fast/(D_fast + D), with D_fast(R) = 0.127 R_cell^−2 in (lattice sites)^{2/3}/MCS (14a Fig. 11, p.2812).

### 2.9 Fortuna released code (SF1_Code.zip)

This is the CC3D project that 14b ref. [14] cites for the 14a model. Its header says it implements "eq. 6" and "eq. 7" of Fortuna et al. 2020, was "written between 2014-2015", and "only runs on the CompuCell3D version 3.7.9" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:4–13). The XML block declares version 3.7.5 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:94), and the `.cc3d` file declares 3.5.1 (codebases/14a_Fortuna2020_Crawling/Published/CellMig3D.cc3d:1). The Python and XML files are dated August 2021 inside the zip. So it is **not known** whether this is byte-for-byte the version that produced the 14a figures (§9 item 17).

**Provenance evidence (checked 2026-09-30).**
- 14a-S1 p.2 says "The published simulations were executed using CC3D version 3.5.1, but execute and reproduce the original results in CompuCell3D version 3.7.9". 14a-instr p.1 repeats the sentence but names **3.6.2** instead of 3.5.1. The two author documents therefore disagree on the version used for the paper; both say 3.7.9 reproduces it.
- 14a-S1 p.3 reproduces the `.cc3d` file with `<Simulation version="3.5.1">`, matching `CellMig3D.cc3d:1`, and says its ParameterScan "generates all of the individual simulations used in the paper": 10 seeds × R ∈ {10, 15, 20} × φ_F ∈ {0.05, 0.1, 0.2, 0.3} × λ ∈ {−75, −100, −125, −150, −175, −200, −250} (it prints the total as 830; 10 × 3 × 4 × 7 = 840). The seeds are a superset of the 5 in `ParameterScanSpecs.xml:5`. The zip's XML is the single-set, 5-replica form (R = 10, φ_F = 0.05, λ = −150), not the full scan (§2.9.7 items 5, 13).
- 14a-S1 p.5 says `CellMig3D_Steppables.py` "specifies all other simulation parameters, as given in Table 2 of the main text"; 14a Table 2 holds fit results, so this presumably means Table 1. 14a-S1 lists **no J values**, so it does not settle §9 item 3.
- 14a-nH (2022) is a port of 14a-code, not an independent source. Its energies, field and conversion rule are identical (§2.9.8).

The model is written in Python `ElementCC3D` calls (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:89–268) plus two steppables (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py). Energy and dynamics are entirely CC3D plugins. The only custom model logic is the conversion rule (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:121–165).

#### 2.9.1 Lattice, dynamics, types, initial condition

| Item | 14a-code | Cite |
|---|---|---|
| Lattice | L_x = L_y = int(8R). It becomes 10R if R ≥ 20 and φ_F ≥ 0.2, 12R if R ≥ 30 and φ_F ≥ 0.2, and 14R if R ≥ 40 and φ_F ≥ 0.2. L_z = int(2.1R). Derived sizes: R = 10 gives 80×80×21; R = 15 gives 120×120×31; R = 20 gives 160×160×42 (φ_F < 0.2) or 200×200×42 (φ_F ≥ 0.2). For the paper's R ≤ 20, only 8R and 10R ever occur. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–75, 99 |
| Boundaries | Potts x and y `Periodic`. z is not set, so it uses the CC3D default (non-periodic; CC3D-external). | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:104–105 |
| T | 100 | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:80, 101 |
| Proposal neighbourhood | `NeighborOrder 1` (6 face neighbours) | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:103 |
| Run length | tSim = 100001 MCS | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:84, 100 |
| Seeds | The Potts `RandomSeed` is RANDOM_SEED (default 1). The ParameterScan uses 68721, 198463, 206497, 211561 and 217236. The Python `random` stream used by the conversion rule is seeded with a **fixed `seed(1000)`**, independent of RANDOM_SEED. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:39, 102; codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:4–6; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:57 |
| Types | Medium (0), SUBS_A (1, `Freeze`), SUBS_NA (2, `Freeze`), CYTO (3), FRONT (4, lamellipodium), NUCL (5) | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:111–117 |
| Substrate and top lid | SUBS_A fills the whole z = 0 plane, and SUBS_NA fills the whole z = L_z − 1 plane. Each is a single frozen generalized cell. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:59–64, 80–83 |
| Plugins | VolumeLocalFlex, Surface, CenterOfMass, NeighborTracker, BoundaryPixelTracker (`NeighborOrder 1`), Contact, ContactInternal and Chemotaxis, plus the steppable DiffusionSolverFE. Surface has no target surface or λ_surface anywhere, so it only tracks and adds **no surface energy**. There is no Connectivity plugin. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:140–151, 162, 218, 244, 260 |
| Volume constraint | λ = 10 for NUCL, CYTO and FRONT. V_cell = 4.19 R³ (not exactly 4π/3). NUCL target = int(φ_N V) + 0.5. The CYTO target starts at int((φ_C + φ_F) V) + 0.5, so the cytoplasm initially holds the lamellipodium's share. The FRONT target starts at 1.5 when FRONT is created and grows by conversion (§2.9.5). Derived at R = 15: V = 14141.25, NUCL target 2121.5, initial CYTO target 12020.5. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:45–47, 60; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:109–115, 155–157, 162–163 |
| Cluster | NUCL is placed in the CYTO cell's cluster by `reassignClusterId`, and so is FRONT when it is created. So CYTO, NUCL and FRONT form **one CC3D cluster**. **ContactInternal** governs their mutual contacts, and **Contact** governs contacts with Medium, SUBS_A and SUBS_NA. This is **the opposite of 14c-code**, which never clusters (§4.2). | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:116, 154 |
| Initial condition | Cytoplasm: the discrete ball {\|r − c\| < int(R)}, centred at (L_x/2, L_y/2, z = int(R)). It is therefore **tangent to the substrate at t = 0**; its z = 0 point is overwritten by SUBS_A. Nucleus: a **6×6×6 cube** (`range(-3,3)`; the comment says 7×7×7) at the integer CYTO COM. There is no FRONT at t = 0. Derived: at R = 10 the z = 1 contact disc is x² + y² < 2R − 1 = 19, about 60 sites. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:65–72, 78–105 |
| Output | Every deltaT = 50 MCS, the code records these quantities, periodic-unwrapped and divided by R: the COMs of CYTO, FRONT, NUCL and the volume-weighted CN (CYTO+NUCL) COM; `dcm_F_CN`, the **xy** distance between the FRONT COM and the CN COM; the nucleus COM height; the CYTO–FRONT contact area; and the volume fractions. 14a-S1 p.4 documents the two output files: `…_Displacement.dat` (time and the COMs of C, F, N and the whole cell) and `…_SBAn.dat` (column 2 = "the distance between the center-of-mass of the F compartment and the center of mass of the combined C and N compartments"; it does not say xy-only or ÷R). | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:41; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:303–402; 14a-S1 p.4 |
| Detachment stop | If the CYTO–FRONT common surface area is 0 at a sampling time with mcs > 10, the output files are renamed `_BROKEN…` and the run stops. The rename uses the Windows `move` command. | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:404–411 |

#### 2.9.2 F-actin field (resolves §9 item 1 for 14a)

- **PDE, not binary.** CC3D `DiffusionSolverFE` with one field `FActin`, `GlobalDiffusionConstant` 1e-04 and `GlobalDecayConstant` 0.9 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–250).
- **Source.** `SecretionOnContact` with `Type="FRONT"`, `SecreteOnContactWith="SUBS_A"` and rate 0.9 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:253). The comment says FRONT secretes "ONLY when it is in contact with" SUBS_A (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:253–254). SUBS_A is exactly the z = 0 plane (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–81), so this reproduces **14a Eq. 6**: a source on z = 1 lamellipodium sites. **Verified:** the contact test loops over neighbour order 1 only, i.e. the 6 face neighbours (`maxNeighborIndex = getMaxNeighborIndexFromNeighborOrder(1)`, CC379:steppables/PDESolvers/DiffusableVectorCommon.h:78; loop at CC379:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:316), skips neighbours of the same cell (:329), and writes `c + secrConst` from the value read before the loop (:335), so a site secretes **once** per call however many SUBS_A faces it touches. CC362 is identical (CC362:steppables/PDESolvers/DiffusionSolverFE.cpp:692, 705, 711). It does **not** match 14b Eq. 9 (all lamellipodium sites). It also does not match the code's own header formula, "k_source (if inside lamellipodium)" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:5).
- **Not confined.** Nothing restricts diffusion to the cell, so the field covers the whole lattice, including medium and both substrate planes. This contradicts the header comment "confined to the cell volume" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:3). No field boundary conditions are set. By CC3D default they follow the lattice: periodic in x and y, and zero-flux in z (CC3D-external).
- **Cadence and order (RESOLVED 2026-09-30 from CC3D-src; §9 item 15).** The solver runs once per MCS (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244 comment).
  - Sub-stepping: the number of solver calls per MCS is ceil(max D / D_max,stable) (CC379:steppables/PDESolvers/DiffusionSolverFE.cpp:136), with D_max,stable = 0.14 on a 3D square lattice (:218–230). For D_F = 1e-4 that is **1 call**, so no rescaling of decay or secretion.
  - Order within the call: `scaleSecretion` defaults to true (CC379:steppables/PDESolvers/DiffusionSolverFE.cpp:91) and 14a-code does not set `DoNotScaleSecretion`, so each call runs **diffusion + decay first, then secretion** (CC379:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:835–841). Decay is explicit, c ← diffusion term + (1 − k_decay) c (CC379:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:1204).
  - CC3D 3.6.2 has the same order, diffuse then secrete, with no `scaleSecretion` switch (CC362:steppables/PDESolvers/DiffusionSolverFE.cpp:537–557; decay CC362:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:199). The 3.5.1 source named by 14a-S1 p.2 is not on the official GitHub (the earliest version branch is 3.6.2) and was not checked.
- **Derived consequence.** The diffusion length √(D_F/k_decay) ≈ 0.011 lattice sites, so diffusion is negligible. At a source site the update is c ← 0.1c + 0.9, so **F → 1** (fixed point) during the next Potts sweep. Elsewhere F is 0 except for a trail on sites that recently were source sites, decaying ×0.1 per MCS. The rejected alternative (secretion then decay, F ≈ 0.1) does not occur in either CC3D version checked.

  In practice the released 14a model is therefore close to a **binary z = 1 lamellipodium indicator with value 1**. That is the simplification 14c-code later made explicit (§4.2).

#### 2.9.3 Contact energies (J₀ = 20, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:81; both tables `NeighborOrder 4` = 32 neighbours, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:163, 219)

| Pair | Contact (different cells) codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:174–209 | ContactInternal (same cluster) codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:229–240 | 14a Table 1 |
|---|---|---|---|
| Medium–Medium | 1 | – | – |
| Medium–SUBS_A | 20 | – | 20 |
| Medium–SUBS_NA | **−20** | – | not in paper |
| Medium–CYTO | 20 | – | 20 |
| Medium–FRONT | 40/3 | – | 40/3 |
| Medium–NUCL | 100 | – | 100 |
| SUBS_A–SUBS_A, SUBS_A–SUBS_NA, SUBS_NA–SUBS_NA | 1, 1, 1 | – | – |
| SUBS_A–CYTO | 20 | – | 20 |
| SUBS_A–FRONT | 20/3 | – | 20/3 |
| SUBS_A–NUCL | 100 | – | 100 |
| SUBS_NA–CYTO / FRONT / NUCL | 20 / 40/3 / 100 | – | not in paper |
| CYTO–FRONT | 40 | **10** (J₀/2, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:230) | **20** |
| CYTO–NUCL | 100 | 20 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:231) | 20 |
| FRONT–NUCL | 100 | 40 (2J₀, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:236) | 40 (J_front–nucleus) |
| CYTO–CYTO / FRONT–FRONT / NUCL–NUCL | 40 / 40 / 100 | 0 / 0 / 0 | 0 (same compartment) |

- The single cell is one cluster (§2.9.1), so the **effective** values are: the Contact column for medium and substrate pairs, and the ContactInternal column for pairs within the cell.
- All effective values equal 14a Table 1 **except CYTO–FRONT = 10 vs 20**.
- The effective values are identical to 14c-code. 14c-code puts them in its external table because it does not cluster (§4.2).
- The Contact-table CYTO/FRONT/NUCL cross values (40 and 100) would apply only between different cells. The code comments say they are unused in these single-cell runs (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:168–170). They are the only explicit inter-cell values in any source, but they are untested.

#### 2.9.4 Protrusion term (resolves §9 item 2 for 14a)

- The code uses the CC3D `Chemotaxis` plugin on `FActin` with `ChemotaxisByType Type="FRONT" ChemotactTowards="Medium" Lambda=lambCHEM` (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:260–263).
- `lambCHEM = -150` by default (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48), and the ParameterScan also uses −150 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:10–12). The comment lists 0, −50, −100, −150, −175 and −200 as used values (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48).
- The comments say the term acts on "the boundary between lamellipodium and medium only" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:6) and "always pushes the edge away from the soma" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:264–265).
- **Sign (verified 2026-09-30).** 14a-code sets no `<Algorithm>`, so CC3D uses its default "merks" algorithm (CC379:plugins/Chemotaxis/ChemotaxisPlugin.cpp:36, 100–102, 196–199) with the simple formula ΔE = λ_CC3D [c(source) − c(target)], i.e. `(flipNeighborConc − conc) * lambda` where `conc` is the target site (CC379:plugins/Chemotaxis/ChemotaxisPlugin.cpp:272–273, 441–445). So λ_CC3D = −150 gives ΔE = +150 [F(target) − F(source)]. That is 14a Eq. 7 with **λ_F-actin = +150**. The paper's positive magnitudes are the negated code values.
- **Scope (RESOLVED 2026-09-30; decision changed and approved, D-067; §9 item 16).** The merks algorithm applies the FRONT parameters in **both** directions: when FRONT overwrites Medium (extension; the new cell's type data, CC379:plugins/Chemotaxis/ChemotaxisPlugin.cpp:434–455) and, if no term was applied yet, when Medium overwrites FRONT (retraction; the old cell's type data with `okToChemotact(newCell, oldCell)`, :487–502). `okToChemotact` checks the *other* cell's type against `ChemotactTowards`, treating Medium as type 0 (CC379:plugins/Chemotaxis/ChemotaxisData.h:154–175). The same formula is used in both cases, so a retraction of a high-F FRONT site into Medium costs +150 [F(FRONT site) − F(Medium site)]. This is "extension–retraction" chemotaxis, not the extension-only reading of Eq. 7. CC3D 3.6.2 behaves the same (default "merks", CC362:plugins/Chemotaxis/ChemotaxisPlugin.cpp:57; formula :295; retraction branches with `okToChemotact(newCell)` at :491, :513). Specs README §4 C7 now follows the code (both directions, for 14a and 14c; changed 2026-09-30, approved by the maintainer 2026-09-30, D-067); Eq. 7 extension-only is a variant. The code does not restrict the term by position, but F ≈ 0 except at z = 1 FRONT sites (§2.9.2), so the drive is effectively z = 1-only, as in 14c-code.

#### 2.9.5 Lamellipodium conversion (resolves §9 item 7)

- The `Cell.step` steppable runs every MCS (`_frequency=1`, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:293).
- The volumes it reads are **target** volumes, despite comments saying "actual volume". FRONTvol is the FRONT `targetVolume`, NUCLvol is the NUCL `targetVolume`, and CELLvol = CYTO target + FRONT target + NUCL target (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:127–138).
- **Law:** pFRONT = 0.1 · (1 − FRONTvol/CELLvol/φ_F) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:139).
  - The proportionality constant is **0.1**.
  - The paper's V_3/V_3^target becomes FRONT target / (φ_F × total target).
- **Gate:** the step is skipped if pFRONT ≤ 0 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:140). No clipping is needed, because `random() < p` is never true for p ≤ 0.
- **Candidates:** CYTO boundary pixels with z == 1 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:141–144). Boundary means BoundaryPixelTracker with `NeighborOrder 1` (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:150–151). All of z = 0 is SUBS_A, so every CYTO site at z = 1 is a boundary pixel. The candidates are therefore **all CYTO sites at z = 1** (derived). They are visited in Python-`shuffle` order (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:145).
- **Conversion.** Each candidate converts with probability pFRONT (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:147).
  - The first conversion creates FRONT (target 1.5, λ = 10), joins it to the cluster, and lowers the CYTO target by 1.5 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:149–159).
  - Each later conversion adds 1 to the FRONT target and subtracts 1 from the CYTO target (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:160–164).
  - pFRONT is recomputed after each conversion (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:165), so conversion is **sequential**. The total target volume is conserved.
- **Derived consequence.** The FRONT target only ever grows, so conversion **stops permanently** once the FRONT target reaches φ_F × total target. After this build-up, the lamellipodium is kept up only by its volume constraint (λ = 10) and ordinary copies.
  - This agrees with 14b ("until the lamellipodium target volume is attained", 14b p.8) and with 14a's "only … at early times" (p.2806).
  - It does not agree with a literal reading of 14a, where V_3 is the current volume and the rule re-fires whenever V_3 < V_3^target, and V_3^target = φ_l V is fixed from t = 0.
- **Edge case.** If FRONT's volume reaches 0, CC3D removes the cell (CC3D-external). A new FRONT would then be seeded with target 1.5 while the CYTO target stays reduced. In practice the detachment check (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:407–411) normally stops the run first.
- There is no reverse conversion.

#### 2.9.6 Order within one MCS

1. Potts sweep: N copy attempts, with Contact, ContactInternal, Volume and Chemotaxis evaluated on each attempt.
2. DiffusionSolverFE: one call of diffusion + decay, then secretion (verified, §2.9.2).
3. Python steppables in registration order: `Cell` (conversion), then `Calc` (analysis) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:290–300).

The Potts → C++ steppable → Python steppable order is CC3D-external. So the conversion at the end of MCS n sees the F-actin field updated in MCS n. The next Potts sweep uses that field, and it goes stale during the sweep.

#### 2.9.7 Paper-vs-code discrepancies (complete list)

Where they agree: T = 100; φ_n = 0.15; λ_c = λ_l = λ_n = 10; D_F = 1e-4; k_decay = 0.9; k_source = 0.9; 4th-order (32-neighbour) contacts; order-1 proposals; periodic x and y; L_z = 2.1R; every medium and substrate J; J_cyto–nucleus = 20; J_front–nucleus = 40; source only on lamellipodium touching the substrate.

Where they differ:

1. **J_cyto–lamellipodium.** Table 1 gives 20. The code gives **10** (ContactInternal CYTO–FRONT = J₀/2, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:230). 14c-code also uses 10 (SC:120, 139), and so does 14a-nH (nH:P3:139). 14a-S1 gives no J values.
2. **Conversion law.** The paper uses p ∝ (1 − V_3/V_3^target) with a fixed V_3^target = φ_l V_cell. The code uses p = 0.1 (1 − V_3^target(t)/(φ_F V_total^target)), where the FRONT *target* starts at 1.5 and grows, and the current volume is never used (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:132–139, 155, 162).
3. **Cell volume.** The paper uses (4π/3) R³. The code uses 4.19 R³, with `int` truncation and +0.5 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:60; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:109, 114).
4. **λ_F-actin sign.** The paper gives positive values. The code gives negative values in CC3D's chemotaxis convention (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48, 263). They are equivalent under the CC3D formula (CC3D-external).
5. **λ_F-actin values.** The paper covers 0–250, and Table 2 and Fig. 6 include 160, 165, 170 and 250. The code comment lists 0, −50, −100, −150, −175 and −200, and the ParameterScan contains only −150 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48; codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:10–12). 14a-S1 p.3 gives a third list, −75, −100, −125, −150, −175, −200, −250, as the scan that "generates all of the individual simulations used in the paper"; it still lacks Table 2's 160, 165 and 170.
6. **R values.** The paper uses 10–20. The code comment lists 10, 15, 20 and 30 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:56), and it has lattice rules for R ≥ 30 and R ≥ 40 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:69–72) that no paper run uses. 14a-S1 p.3 scans R ∈ {10, 15, 20}; its lattice rule (Eq. S1, p.6) is the code's rule written in units of (lattice sites)^{1/3}.
7. **Lattice.** The paper gives "L_x ∈ [8R, 14R]". The code picks L_x by a deterministic rule, and for R ≤ 20 only 8R or 10R occurs (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–72).
8. **Substrate, top lid and z boundary.** The paper is silent on all three. The code has a frozen SUBS_A at z = 0, and a frozen SUBS_NA at z = L_z − 1 with J = −20 to Medium, 20 to CYTO, 40/3 to FRONT and 100 to NUCL. It leaves the z boundary at the CC3D default (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:113–114, 176, 191–194; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–83).
9. **Initial condition.** 14a Fig. 4A shows a "suspended" cell. The code starts with a ball tangent to the substrate and a 6×6×6 cubic nucleus, with no FRONT (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:72, 84, 101–105). This matches 14b p.8. The code comment says 7×7×7. 14a-S1 p.6 (and 14a-instr p.4) describe a sphere "centered on coordinates (L_x/2, L_y/2, L_z/2)" made of a central nucleus sphere and a cytoplasm shell; the code's centre height int(R) is close to L_z/2 = 1.05R, but its nucleus is a cube.
10. **F-actin description in the code comments.** The header says "confined to the cell volume" and "k_source (if inside lamellipodium)" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:3, 5). The XML actually uses an unconfined field with a source only on FRONT in contact with SUBS_A (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253). The XML agrees with 14a Eq. 6. The header comment agrees with neither 14a Eq. 6 nor the XML.
11. **Surface.** 14a p.2805 mentions "interfacial area constraints". The code loads the Surface plugin with no energy parameters (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:146), so there is no surface energy. This agrees with 14a Eq. 3.
12. **Polarization observable.** 14a Fig. 12 uses the "lamellipodium–nucleus" COM distance. The code logs `dcm_F_CN`, the xy distance between the FRONT COM and the CN COM (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:359–369). 14a-S1 p.4 documents the same quantity as column 2 of `…_SBAn.dat` and also documents `…_Displacement.dat`, which holds the separate C, F and N COMs, so a true lamellipodium–nucleus distance could have been computed from the released outputs. Which quantity Fig. 12 plots is still unknown (§9 item 19); 14a-nH logs the same `dcm_F_CN` (nH:P3S:376–385).
13. **Replicates.** The ParameterScan has 5 seeds for a single set, R = 10, φ_F = 0.05, λ = 150 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:4–18). That fits the 5 replicas of Fig. 5. The sets for Table 2 and Fig. 9 (30 replicates) are not in the file.
14. **Run length.** The code runs 100001 MCS; the paper says 10⁵. This is trivial.
15. **Fixed conversion seed.** `seed(1000)` for the Python RNG (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:57) is not in the paper. The conversion stream is the same in every replicate, and replicates diverge only through the Potts RNG.
16. **CC3D version.** The header says 3.7.9 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:13), the XML says 3.7.5 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:94), and the `.cc3d` file says 3.5.1 (codebases/14a_Fortuna2020_Crawling/Published/CellMig3D.cc3d:1). For the version that produced the paper's runs, 14a-S1 p.2 says **3.5.1** and 14a-instr p.1 says **3.6.2**; both say 3.7.9 reproduces the results. The solver behaviour that matters (§2.9.2) is the same in 3.6.2 and 3.7.9.
17. **Detachment criterion.** Paper Fig. 6 shades "lamellipodium detachment" light red. The code defines it operationally as zero CYTO–FRONT contact at a 50-MCS sample, and then stops the run (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:407–411). The paper does not state this.
18. **Equation numbers in comments.** The body comments call the chemotaxis term "equation 9" and the field "equation 10" (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:30, 242, 258, 266), and call the contact and volume energies Eqs. 7 and 8. The paper numbers these Eqs. 7, 6, 4 and 5. Only the header (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:4–6) uses the paper's numbering. This is cosmetic.
19. **Protrusion on retraction.** 14a Eq. 7 (p.2806) and the code comment (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:6) describe an extension-only term (lamellipodium source → medium target). Through CC3D's default "merks" chemotaxis algorithm the code also applies it when Medium overwrites FRONT, with the same formula (CC379:plugins/Chemotaxis/ChemotaxisPlugin.cpp:487–502; CC362:plugins/Chemotaxis/ChemotaxisPlugin.cpp:491, 513; §2.9.4). 14c-code inherits this (SC:147–149).
20. **Document S1 vs 14a-code and 14a.** (a) 14a-S1's scan list (p.3) lacks Table 2's λ = 160, 165, 170 (item 5); (b) it prints 830 runs where 10 × 3 × 4 × 7 = 840 (p.3); (c) it describes the initial nucleus as a central sphere with the cell centred at L_z/2 (p.6), where the code uses a 6×6×6 cube in a ball centred at z = int(R) (item 9). All are minor; see §9 item 20.

#### 2.9.8 nanoHUB port (14a-nH) vs 14a-code (diffed 2026-09-30)

Method: both main scripts and both steppable files were diffed after stripping comments and whitespace.
- **Steppables: identical model logic.** The 252 normalised lines differ only in the CC3D 3 → 4 Python API (`every_pixel`, `get_cluster_cells`, `get_cell_neighbor_data_list`, plot calls), Python 3 `print`, two debug prints, and a header "2020-11-30 bugfixing by Juliano Ferrari Gianlupi" (nH:P3S:1). The conversion rule, the fixed `seed(1000)`, the outputs and `dcm_F_CN` are unchanged.
- **Main script: identical energies and field.** Same J₀ = 20 (nH:P3:54), same Contact and ContactInternal tables including CYTO–FRONT = J₀/2 (nH:P3:105–145, :139), same T, lattice rule, `DiffusionSolverFE` settings and `SecretionOnContact` FRONT–SUBS_A 0.9 (nH:P3:155–164), same Chemotaxis block (nH:P3:147–149).
- **Differences.**
  1. The CC3D version is 4.2.2 (`CellMig3D_P3.cc3d:1`; nH:P3 XML `Version 4.2.2`).
  2. An **extra `Secretion` plugin** makes FRONT secrete FActin 0.9 on contact with **SUBS_NA** (the top lid) (nH:P3:151–153). 14a-code has no such source. It matters only if the lamellipodium reaches z = L_z − 2. It is a port addition, not in the paper.
  3. `VolumeLocalFlex` → `Volume`, the `Surface` tracker and `PlayerSettings` are dropped. Neither changes the energy (Surface had no parameters, §2.9.1).
  4. Default R = 10 instead of 15 (nH:P3:31); there is no `ParameterScanSpecs.xml`.
  5. The output directory is the path of the steppable file itself (`Dir = os.path.abspath(__file__)`, nH:P3S:202–206) instead of CC3D's screenshot directory, so output files are named `CellMig3D_P3_Steppables.py_R…_Displacement.dat` next to the script (two such sample files ship in the archive).
- **Conclusion.** 14a-nH confirms 14a-code rather than adding independent evidence. It is a third-party port (submitters Ferrari Gianlupi and Sego), so it does not settle §9 items 3 or 17.

---

## 3. Mechanics — POLARIZATION STUDY (Thomas, 14b)

14b restates the 14a model with the following differences in wording. All are flagged.

- **Energy.** Eq. 5 is E = E_interface + E_volume, and the 4th-neighbour range is again 32 neighbours (14b p.3).
- **Proposals.** "Randomly picking a pair of nearest neighbors cell-lattice sites" (14b p.3). The temperature is called T_m.
- **Protrusion, Eq. 8.** ΔE_F-actin = λ_F-actin [F(s) − F(r)], with r the source and s the target. It is restricted to the lamellipodium–medium boundary (14b p.4). The Kronecker deltas are omitted from the printed formula but stated in the text.
- **F-actin, Eq. 9.** ∂F/∂t = D_F ∇²F + k_s δ(C(r,t) − 3) − k_d F (14b p.4). **Conflict with 14a Eq. 6.** Here the source covers *all* lamellipodium sites, with no z = 1 restriction.
- **Parameters.** Energy and temperature parameters are kept "as in Ref.[9]" (that is, 14a). The scans are λ_F-actin ∈ {150, 175, 200}, φ ∈ {0.05, 0.10, 0.20, 0.30} and R_cell ∈ {10, 15, 20}. Each set has 10 runs of 10⁵ MCS (14b p.8).
- **Initial condition** (14b p.8). "A spherical cell with no lamellipodium engulfing a cubic nucleus resting over the substrate." Cytoplasm sites touching the substrate transform into lamellipodium "until the lamellipodium target volume is attained". Warm-up is 1000 MCS. **Conflict with 14a Fig. 4A**, which shows a suspended cell that then contacts the substrate.
- **Polarization definitions, Eq. 10** (14b p.6). There are five xy-projected COM-difference vectors: Π_{L−N}, Π_{L−CN}, Π_{C−N}, Π_{CN−N} and Π_{C−CN}. Here CN is the combined cytoplasm+nucleus COM.
  - Eq. 11 relates them: Π_{C−N} = ((V_C+V_N)/V_C) Π_{CN−N}, and Π_{C−CN} = (V_N/V_C) Π_{CN−N}.
  - **The selected definition is Π_{CN−N} = r_CN − r_N** (14b p.11). It excludes the lamellipodium.
- **Optimal interval, Eq. 12** (14b p.7). α(Δτ) = d log⟨|Δρ|²⟩ / d log Δτ = Δτ(1 − (1−S)e^{−Δτ}) / (Δτ − (1−S)(1 − e^{−Δτ})). Δτ_opt^theor maximises α.
  - Fits: **Δτ_opt^theor = 1.932(±0.0086) S^{0.455(±0.002)}** and **α_opt = 2.022(±0.00239) − 1.115(±0.00456) S^{0.397(±0.0039)}**, both with R² > 0.999 (14b p.10).
- **Other observables.**
  - Correlation index ξ_β = ⟨cos θ_β⟩/⟨sin θ_β⟩ (Eq. 14).
  - Relative speed error ε = σ_speed/⟨u⟩ (Eq. 15).
  - Parallel speed u_{∥,β} = Π_β · (ρ(τ+δ) − ρ(τ))/δ (Eq. 16). As printed, Eq. 16 is not normalised by |Π|. By contrast, 14c Eq. 13 divides by |Π|.

---

## 4. Mechanics — CHEMOTAXIS VARIANT (Dal-Castel, 14c + 14c-code)

### 4.1 As stated in the paper (14c)

- **Structure.** The same three objects, named Lamel, Nuc and Cyto. Labels are σ (cell) and τ (compartment) (14c p.4–5).
- **Acceptance.** P = e^{−ΔE/T_B} (Eq. 1). MCS = N_MCS attempts, where N_MCS is the number of voxels (14c p.5).
- **Energy.** E_total = E_contact + E_volume (Eqs. 2–4, 14c p.5). J is zero for "neighboring sites of same type", and E_volume = Σ_σ λ_σ (V_current^σ − V_target^σ)². **No surface or connectivity terms** appear.
- **Protrusion, Eq. 5** (14c p.6). ΔE_protrusive = −λ_F-actin [F(i_Medium) − F(j_Lamel)]. It is "calculated only for Lamel voxels in contact with the substrate" (14c p.5).
  - **F is binary.** "F is a discrete field set equal to one in Lamel voxels and to zero otherwise" (14c p.6; Fig. 1 caption, p.7). **There is no PDE.**
  - **Sign problem.** With F(Lamel) = 1, F(Medium) = 0 and a positive λ, Eq. 5 gives ΔE = +λ > 0. That *opposes* protrusion. The paper reports positive λ ∈ {125, 150, 175}. The code resolves this with λ = −175 (see §4.2).
- **External field.** Q is "linear constant" in x and "sensed in the cell base" (14c p.7). The images show z = 1 (Fig. 2 caption, p.8). 14c-SM p.4 defines the base as "all voxels of the cell (Cyto or Lamel) in the xy plane of z = 1".
- **Memory switch, Eq. 6** (14c p.8). Switch = (⟨φ_f⟩_{n−100}^{n} − φ_f^{n}) / |⟨φ_f⟩_{n−100}^{n} − φ_f^{n}|.
  - This is a sign function. Conversion is allowed only when the current Lamel volume fraction is **below** its mean over the previous 100 MCS.
  - The choice of 100 MCS lies between "pure Potts fluctuations (10 MCS or lower)" and migration persistence (≥ 1000 MCS) (14c p.8–9).
- **Conversion probability, Eq. 7** (14c p.9). P_convert(i) = ρ [tanh(µ (Q(i) − ⟨Q⟩_cell)/σ_{Q,cell}) + 1] × Switch.
  - ρ = 1/2.
  - µ is the steepness. It is 0 for the isotropic case and a "saturation value µ = 10⁶" for the gradient runs (14c p.15).
  - σ_{Q,cell} = √(⟨Q²⟩ − ⟨Q⟩²) over the base (14c-SM p.5).
  - It applies to Cyto voxels at the base. It is independent of the copy acceptance (14c-SM p.5).
- **Runs.** Main results use R = 10 (14c p.15). Scans are λ_F-actin ∈ {125, 150, 175} and φ_f ∈ {0.05, 0.10, 0.20}, plus R ∈ {10, 15, 20} in Fig. 3. There are 10 replicas (14c p.31). One cell at R = 10 for 10⁵ MCS takes about 4 h on an i7-3770K (14c p.9).
- **Lattice.** "we adjust the lattice to the cell" (14c p.9). No dimensions are given in the paper.
- **Initial condition.** "a symmetrical semi-sphere over the flat substrate" (Fig. 1a caption, 14c p.7). The figure shows a Lamel ring already present.

### 4.2 As implemented in the released code (14c-code @ c1353d3)

| Item | Code | Cite |
|---|---|---|
| Lattice | L_x = L_y = int(4·√(φ_F V/3.14 + ((1−φ_F) V·2/4.19)^{2/3})) and L_z = int(2.1 R). For R = 10 and φ_F = 0.05 this gives L_x = 59 (about 5.9R, derived), which is **outside 14a's [8R, 14R]**. | SC:32–33 |
| Cell volume | V = 4.19 R³, with R = 10 by default | SC:12–14 |
| Target volumes | φ·V + 0.5 for each compartment; φ_N = 0.15, φ_C = 1 − φ_N − φ_F, φ_F = 0.05 by default | SC:26–28, 41 |
| λ_volume | 10 for CYTO, LAMEL and NUC | SC:91–93 |
| T | 100 | SC:20, 74 |
| Proposal neighbourhood | `NeighborOrder 1` | SC:76 |
| Boundaries | x and y `Periodic`. z uses the CC3D default, which is non-periodic (external: CC3D default, not in our PDFs). | SC:77–78 |
| Types | Medium; **SUBS_A** (frozen; adherent substrate); **SUBS_NA** (frozen; non-adherent); CYTO; LAMEL; NUC | SC:82–87 |
| Substrate geometry | SUBS_A fills the whole z = 0 plane. SUBS_NA fills the whole z = L_z − 1 plane (the top lid). | SS:70–73 |
| Contact (external table) | NeighborOrder 4, with J₀ = 20. See §5.2 for all values. | SC:103–125 |
| ContactInternal (intra-cluster table) | NeighborOrder 4: CYTO–LAMEL 10, CYTO–NUC 20, LAMEL–NUC 40, LAMEL–LAMEL 0, CYTO–CYTO 0, NUC–NUC 0, and SUBS_*–anything 10 | SC:128–144 |
| Clusters | **The compartments are never joined into one cluster.** Each is a separate `createCell()`, and neither file contains a cluster reassignment call. Under CC3D semantics (external; my understanding, not in our PDFs), Contact then applies between CYTO, LAMEL and NUC, and **ContactInternal is inert** for this single-cell setup. The effective CYTO–LAMEL value is 10 in both tables, so the outcome does not depend on this. **By contrast, 14a-code does cluster the compartments** (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:116, 154) and puts these same effective values in ContactInternal (§2.9.3). So 14c-code's external table reproduces 14a-code's effective single-cell energies. | SS:48–57 |
| Protrusion | CC3D `Chemotaxis` plugin on field `FActin`, with `ChemotactTowards="Medium"`, `Lambda=-175`, `Type="LAMEL"`. Comment: "Negative sign makes the protrusion happen down gradient of FActin". | SC:22, 147–149 |
| F field | The CC3D diffusion solver is declared with D = 0 and decay = 0, so it is effectively unused (SC:152–158). Every MCS the steppable runs `F[:,:,1] = 0` and then sets F = 1 on **LAMEL boundary pixels with z == 1** (BoundaryPixelTracker, NeighborOrder 1, SC:99–100). **F is never set above z = 1**, so the protrusion drive exists only for copies from or into z = 1 Lamel pixels: extension from a z = 1 Lamel pixel into Medium, and, because 14c-code also uses CC3D's default "merks" chemotaxis algorithm (no `Algorithm` element, SC:147–149), retraction of a z = 1 Lamel pixel with F = 1 by Medium, which costs +175 (§2.9.4, §9 item 16; established for CC3D 3.6.2 and 3.7.9; 14c-code's CC3D 4.2.3 was not checked but is very likely the same). Within one MCS, F is stale: pixels gained or lost during the MCS keep their old value until the next step. | SS:88–95 |
| Base statistics | The base is the set of CYTO **boundary** pixels plus LAMEL boundary pixels at z = 1. Q(pixel) = x, unwrapped relative to the Cyto COM (±L_x when the COM and pixel are on opposite thirds). ⟨Q⟩ and σ_Q are computed over this set. Candidates are the CYTO base pixels, in shuffled order. | SS:121–149 |
| Conversion probability | pLAMEL = ρ·(χ·tanh(µ (x − x̄)/σ) + 1). Defaults: ρ = 0.5, χ = 1, µ = 0, δ = 0. With µ = 0 this gives pLAMEL = 0.5. | SC:45–51; SS:156–159 |
| Gate | `random() < pLAMEL and LAMELvol/CELLvol − δ ≤ φ_EST`, where CELLvol = **Cyto target volume** + current Lamel + current Nuc. LAMELvol is incremented after each conversion, so the gate is re-evaluated pixel by pixel within the loop. | SS:107, 162–172 |
| φ_EST | A ring buffer of the last 100 per-MCS values of LAMELvol/CELLvol. **It includes the current MCS.** For mcs < 100, φ_EST keeps its initial value φ_F, the target fraction. | SS:41, 110–114 |
| Reverse conversion | None | whole file |
| Surface / connectivity plugins | None. The plugins are CellType, Volume, CenterOfMass, NeighborTracker, PixelTracker, BoundaryPixelTracker, Contact, ContactInternal and Chemotaxis. | SC:81–149 |
| Initial condition | Cyto is a hemisphere of radius R_C = ((1−φ_F)V·2/4.19)^{1/3}, centred at (L_x/2, L_y/2, z = 1). Nuc is a sphere of radius R·φ_N^{1/3}, centred at z = R_C/2. **Lamel starts as a one-voxel-thick ring at z = 1** between R_C and R_F = √(φ_F V/3.14 + R_C²). | SS:59–80 |
| Order per MCS | CC3D Potts sweep, then the steppable at frequency 1: first the F update, then the φ_EST update, then conversions. The ordering relative to the Potts sweep follows the standard CC3D steppable order (external). | SS:82–172; SC:172–173 |
| Run length and seed | 100000 MCS, `random_seed = 1` | SC:8, 57 |
| README suggestion | "try the parameters delta=0.01 and mu=1000000" for an intense chemotactic response | README / INSTRUCTIONS.txt |

---

## 5. Parameter tables

### 5.1 Base model (14a Table 1, p.2807, plus text)

Units follow 14a Table 1's footnote: energy is "rescaled by the typical fluctuation energy T", time is in MCS, and length is in (lattice sites)^{1/3}.

The last column gives the 14a-code value (§2.9). A **bold** code value differs from the paper.

| Symbol | Value (paper) | Units | Meaning | Source | Stated / derived | 14a-code |
|---|---|---|---|---|---|---|
| T_B | 100 | energy | fluctuation amplitude | 14a Table 1 | stated | 100 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:80) |
| φ_n | 0.15 | – | nucleus volume fraction | 14a Table 1; p.2806 | stated | 0.15 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:46) |
| φ_l | 0.05–0.30 (0.05, 0.10, 0.20, 0.30 used) | – | lamellipodium volume fraction | 14a p.2806; Figs. 5–6 | stated | 0.05 by default; the comment lists 0.05, 0.10, 0.20, 0.30 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:45; codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:13–15) |
| φ_c | 1 − φ_n − φ_l | – | cytoplasm fraction | – | **derived** | 1 − φ_N − φ_F (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:47) |
| R_cell | 10–20 (10, 15, 20 used) | (lattice sites)^{1/3} | equivalent radius | 14a p.2806 | stated | 15 by default; the scan uses 10; the comment lists **10, 15, 20, 30** (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:56; codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:7–9) |
| V_cell^target | (4π/3) R_cell³ | sites | cell target volume | 14a p.2806 | stated | **4.19 R³**, with int truncation and +0.5 per compartment (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:60; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:109, 114) |
| λ_c, λ_l, λ_n | 10, 10, 10 | energy/(sites)² | inverse compressibility | Table 1 | stated | 10, 10, 10 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:110, 115, 156) |
| D_F | 0.0001 | (sites)^{2/3}/MCS | F-actin diffusion | Table 1 | stated | 1e-04 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:249) |
| k_decay | 0.9 | 1/MCS | F-actin decay | Table 1 | stated | 0.9, applied on the whole lattice (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:250) |
| k_source | 0.9 | 1/MCS | F-actin source (lamellipodium at z = 1) | Table 1 | stated | 0.9 via `SecretionOnContact` FRONT/SUBS_A (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:253) |
| λ_F-actin | range 0–250; used 75–250 | energy per unit F per area | protrusion strength | 14a p.2806; Table 2; Fig. 6 | stated | **−150** in the CC3D chemotaxis convention, equivalent to +150; the comment lists 0 to −200 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48, 263) |
| J_medium–substrate | 20 | energy/(sites)^{2/3} | – | Table 1 | stated | 20 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:175) |
| J_medium–cyto | 20 | " | – | Table 1 | stated | 20 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:177) |
| J_medium–lamellipodium | 40/3 | " | – | Table 1 | stated | 40/3 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:178) |
| J_medium–nucleus | 100 | " | – | Table 1 | stated | 100 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:179) |
| J_substrate–cyto | 20 | " | – | Table 1 | stated | 20 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:185) |
| J_substrate–lamellipodium | 20/3 | " | – | Table 1 | stated | 20/3 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:186) |
| J_substrate–nucleus | 100 | " | – | Table 1 | stated | 100 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:187) |
| J_cyto–lamellipodium | 20 | " | – | Table 1 | stated | **10** (ContactInternal, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:230); 14c-code also uses 10 |
| J_cyto–nucleus | 20 | " | – | Table 1 | stated | 20 (ContactInternal, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:231) |
| J_front–nucleus | 40 | " | lamellipodium ("front") – nucleus | Table 1 | stated ("front" read as lamellipodium) | 40 (ContactInternal, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:236); the code's type is literally named FRONT |
| J_medium–top lid, J_top lid–(cyto, lamellipodium, nucleus) | not in paper | " | non-adherent top wall | – | – | **−20; 20, 40/3, 100** (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:176, 192–194) |
| J (same σ and C) | 0 | – | – | 14a p.2805 | stated | 0 (ContactInternal diagonal, codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:229, 235, 240) |
| J between different cells | UNSPECIFIED | – | – | – | – | Contact table: CYTO–CYTO 40, CYTO–FRONT 40, CYTO–NUCL 100, FRONT–FRONT 40, FRONT–NUCL 100, NUCL–NUCL 100 (not exercised; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:198–209) |
| contact neighbourhood | 4th order, 32 neighbours | – | – | 14a p.2805 | stated | `NeighborOrder 4`, both tables (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:163, 219) |
| proposal neighbourhood | "adjacent", copy distance 1 | – | – | 14a p.2805 | stated; order 1 is inferred (explicit in 14b p.3 and SC:76) | `NeighborOrder 1` (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:103) |
| L_z | 2.1 R_cell | sites | – | 14a p.2806 | stated | int(2.1R) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:75) |
| L_x = L_y | ∈ [8, 14] R_cell | sites | – | 14a p.2806 | stated (the exact value is UNSPECIFIED) | int(8R); 10R if R ≥ 20 and φ_F ≥ 0.2 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–74) |
| BCs | periodic in x, y; z UNSPECIFIED | – | – | 14a p.2806 | stated / UNSPECIFIED | periodic in x, y; z default; frozen planes at z = 0 (SUBS_A) and z = L_z − 1 (SUBS_NA) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:104–105; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–83) |
| conversion prob. | ∝ (1 − V_3/V_3^target), after each MCS | – | cytoplasm → lamellipodium at the substrate | 14a p.2806 | stated; the constant is UNSPECIFIED | **0.1 · (1 − V_3^target/(φ_F V_tot^target))**, on target volumes, CYTO at z = 1, sequential (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:139–165) |
| PDE BCs, solver, substeps | UNSPECIFIED | – | – | – | – | CC3D `DiffusionSolverFE`, once per MCS, field on the whole lattice; BCs and substeps CC3D-internal (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253) |
| run length | 10⁵ MCS | MCS | – | 14a Figs. 5–6 | stated | 100001 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:84) |
| replicates | 5 (Figs. 5 and 7); 30 (Fig. 9) | – | – | 14a Fig. 5 and Fig. 7 captions; p.2809 | stated | 5 seeds in the ParameterScan (codebases/14a_Fortuna2020_Crawling/Published/Simulation/ParameterScanSpecs.xml:4–6) |
| initial condition | suspended cell (Fig. 4A); SM S2 | – | – | 14a p.2806 | stated | **ball tangent to the substrate, 6×6×6 cubic nucleus, no FRONT** (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:72–105) |

### 5.2 Chemotaxis variant (14c paper and 14c-code)

| Symbol | Paper (14c) | Code (14c-code) | Notes |
|---|---|---|---|
| R | 10 in the main results; 10, 15, 20 in Fig. 3 | 10 (SC:12) | – |
| V_cell | – | 4.19 R³ (SC:14) | Close to (4π/3)R³ |
| φ_f (Lamel) | 0.05, 0.10, 0.20 | 0.05 (SC:26) | – |
| φ_N | – | 0.15 (SC:28) | Matches 14a |
| λ_vol | – | 10 for each compartment (SC:91–93) | Matches 14a |
| T_B | not stated | 100 (SC:20) | Matches 14a |
| λ_F-actin | 125, 150, 175 (magnitudes) | **−175** (SC:22) | Sign convention conflict; see §4.1 |
| F field | binary: 1 in Lamel, else 0 (p.6) | 1 only on LAMEL boundary pixels at z = 1 (SS:88–95) | **Conflict with 14a's PDE.** A minor paper-vs-code difference within 14c. |
| ρ | 1/2 | 0.5 (SC:45) | – |
| µ | 0 (isotropic) or 10⁶ (gradient) (p.15) | 0 (SC:49) | – |
| χ | absent (equivalent to 1) | 1.0 (SC:51) | Code-only parameter |
| δ | absent (Switch is strict) | 0.0 (SC:47); the README suggests 0.01 | Code-only parameter. The value used for the paper's figures is **UNSPECIFIED**. |
| memory window | 100 MCS | 100 (SS:110–114) | The code includes the current MCS in the average |
| Q | linear in x, constant in time | Q = x, unwrapped (SS:137–145) | – |
| Contact J (Contact plugin, SC:104–125) | – | Medium–SUBS_A 20; **Medium–SUBS_NA −20**; Medium–CYTO 20; Medium–LAMEL 40/3; Medium–NUC 100; SUBS_A–CYTO 20; SUBS_A–LAMEL 20/3; SUBS_A–NUC 100; SUBS_NA–CYTO 20; SUBS_NA–LAMEL 40/3; SUBS_NA–NUC 100; **CYTO–LAMEL 10**; CYTO–NUC 20; LAMEL–NUC 40; LAMEL–LAMEL 40; CYTO–CYTO 0; NUC–NUC 0; Medium–Medium 1; SUBS_A–SUBS_A 1; SUBS_A–SUBS_NA 1; SUBS_NA–SUBS_NA 1 | Everything else matches 14a Table 1, except that CYTO–LAMEL is 10 instead of 20. |
| ContactInternal J (SC:128–144) | – | CYTO–LAMEL 10; CYTO–NUC 20; LAMEL–NUC 40; LAMEL–LAMEL 0; CYTO–CYTO 0; NUC–NUC 0; SUBS_*–* 10 | Probably inert (see §4.2) |
| lattice | "adjusted to the cell" | L_x = L_y = 59 and L_z = 21 at R = 10, φ_F = 0.05 (**derived** from SC:32–33) | – |
| run length | 10⁵ MCS (p.9) | 100000 (SC:57) | – |
| replicas | 10 (p.31) | – | – |

---

## 6. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| F1 | Fortuna: 3D | **CONFIRMED** | "3D square lattice" (14a p.2806) |
| F2 | periodic x, y | **CONFIRMED** | 14a p.2806 |
| F3 | L_z = 2.1R | **CONFIRMED** | 14a p.2806. It also fixes L_x = L_y ∈ [8R, 14R]. 14a-code: int(2.1R) and int(8R) or int(10R) (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–75). |
| F4 | frozen substrate at z = 0 (adherent) | **NOT IN PAPER; CONFIRMED in 14a-code** | 14a mentions only a "two-dimensional substrate plane" (p.2805). z = 0 is only implied by the z = 1 source in Eq. 6. **14a-code:** SUBS_A `Freeze`, filling z = 0 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:113; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–81). The same holds in 14c-code (SC:83; SS:70–71). |
| F5 | non-adherent top | **NOT IN PAPER; CONFIRMED in 14a-code** | **14a-code:** SUBS_NA `Freeze` at z = L_z − 1, with Medium–SUBS_NA = −20 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:114, 176; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:82–83). The same holds in 14c-code (SC:84, 106; SS:72–73). |
| F6 | T = 100 | **CONFIRMED** | T_B = 100 (14a Table 1). Caveat: the units footnote says energies are rescaled by T (see §9). |
| F7 | NeighborOrder(4) contacts | **CONFIRMED** | "fourth-neighbor range … (32 neighbors)" (14a p.2805). Also 14b p.3, SC:125 and 144, and 14a-code (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:163, 219). |
| F8 | order-1 proposals | **CONFIRMED (indirect for 14a)** | 14a gives "adjacent target" with copy distance = 1 (p.2805). It is explicit as "nearest neighbors" in 14b p.3, as `NeighborOrder 1` in SC:76, and in 14a-code (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:103). |
| F9 | compartments nucleus, cytoplasm, lamellipodium | **CONFIRMED** | C = 1, 2, 3 (14a p.2805) |
| F10 | φ_n = 0.15 | **CONFIRMED** | Table 1; p.2806 |
| F11 | φ_l = 0.05–0.30 | **CONFIRMED** | 14a p.2806 |
| F12 | volume λ = 10 per compartment | **CONFIRMED** | λ_c = λ_l = λ_n = 10 (Table 1) |
| F13 | J: medium–substrate 20, medium–cyto 20, medium–lamel 40/3, medium–nucleus 100, substrate–cyto 20, substrate–lamel 20/3, substrate–nucleus 100, cyto–lamel 20, cyto–nucleus 20 | **CONFIRMED (incomplete)** | All nine match Table 1. **Missing:** J_front(lamellipodium)–nucleus = 40 (Table 1). **Both released codes use cyto–lamel = 10**, not 20: 14a-code ContactInternal (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:230) and 14c-code (SC:120, 139). All other values match 14a-code (§2.9.3). |
| F14 | F-actin drive ΔE = λ_F[F(v) − F(r)] only when lamellipodium copies into medium | **CONFIRMED** | Eq. 7 with δ(C(r) − 3)·δ(σ(v) − medium) (14a p.2806) |
| F15 | λ_F = 75–200 | **CORRECTED** | The stated scanned range is **0 ≤ λ_F-actin ≤ 250** (14a p.2806). Table 2 lists 75–200. Fig. 6 shows 125–250, and Fig. 5 about 100–200. |
| F16 | ∂F = D_F∇²F + k_src δ(lamel at z = 1) − k_decay F | **CONFIRMED (paper and 14a-code)** | Eq. 6 (14a p.2805). 14a-code: DiffusionSolverFE with `SecretionOnContact` FRONT/SUBS_A (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253), which is the z = 1 source. 14b Eq. 9 drops the z = 1 restriction; the code shows that is a misstatement. 14c and 14c-code replace the PDE with a binary field. With D_F = 1e-4 the 14a field is nearly binary anyway (§2.9.2). |
| F17 | D_F = 1e-4, k_decay = 0.9 | **CONFIRMED** | Table 1, and 14a-code (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:249–250). Also **k_source = 0.9**, which the claim omits (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:253). |
| F18 | after each MCS, cytoplasm touching substrate → lamellipodium with prob ∝ (1 − V_l/V_l⁰) | **CONFIRMED; made precise by 14a-code** | 14a p.2806. 14a-code: the constant is **0.1**. V_l is the FRONT **target** volume, which grows from 1.5 by conversion, and V_l⁰ = φ_F × total target. Candidates are CYTO sites at z = 1, converted sequentially (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:127–165). Conversion therefore stops permanently once the target is reached (§2.9.5). |
| F19 | spontaneous polarization, then persistent random walk | **CONFIRMED** | Fig. 4 (A→D), p.2806. There is intermittent splitting and reorientation. |
| F20 | MSD fits the modified Fürth model with 3 regimes | **CONFIRMED** | Eqs. 1–2; Fig. 7; p.2809–2810 |
| F21 | R = 15, φ_l = 0.3, λ_F = 160 → S ≈ 0.02 | **CONFIRMED** | Table 2 gives S = 2.12E−2, P = 8327 and D = 1.13E−4. Fig. 9 used 30 replicates (p.2809). |
| F22 | persistence time rises with λ_F | **CORRECTED** | It rises for most (R, φ_l) series in Table 2, but **not monotonically**. For R = 15, φ = 0.30: P = 11987 (150), 8327 (160), 11507 (165), 15079 (170), 7491 (175), 10124 (200). For R = 20, φ = 0.20: 26853 (175) → 12613 (200). For R = 20, φ = 0.30: 14932 → 7775. The text says only that the parameters "determine the persistence time" and that increasing φ_l at fixed λ_F *decreases* it (p.2807). |
| F23 | λ_F = 0 is diffusive | **NOT IN PAPER** | No λ_F = 0 run is reported. What is reported: for small λ_F, displacement is below 2R_cell, motion stays in the short-time diffusive regime, the MSD slope is 1, and the cells are "nonmotile" (p.2807; Figs. 5–6, where λ = 125 is cyan for φ ≥ 0.10). |
| T1 | Thomas: polarization defined as nucleus–centroid distance | **CONFIRMED (made more precise)** | The chosen definition is Π_{CN−N} = (r_CN − r_N) projected on xy. CN is the cytoplasm+nucleus COM, which excludes the lamellipodium (14b Eq. 10, p.6; chosen at p.11). Five definitions were compared. 14a had used the lamellipodium–nucleus distance (Fig. 12). |
| T2 | nucleus–centroid offset predicts velocity direction | **CONFIRMED (conditional)** | It correlates best when displacement is measured over δ = Δτ_opt^theor (Fig. 4). The error σ_θ falls with ⟨Π⟩ (Fig. 7A). It fails for poorly polarised sets, for example φ = 0.30 with λ = 150 (p.10, p.14). |
| T3 | starts as a spherical cell with no lamellipodium around a cubic nucleus on the substrate | **CONFIRMED (paper and 14a-code)** | 14b p.8. 14a-code: a ball tangent to the substrate, with a 6×6×6 cube nucleus and no FRONT (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:72–105). It **conflicts** with 14a Fig. 4A (suspended cell) and with the 14c-code hemisphere plus initial Lamel ring (SS:59–80). |
| D1 | Dal-Castel: separate ContactInternal table (CYTO–LAMEL 10, LAMEL–LAMEL 0 vs 40 external) | **CONFIRMED (code only; NOT IN PAPER)** | SC:120–122 and 139–141. Caveat: the compartments are not clustered (SS:48–57), so ContactInternal is likely inert. The external CYTO–LAMEL is also 10. The Internal/external split is inherited from 14a-code, which *does* cluster (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:218–240; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:116, 154). |
| D2 | Medium–SUBS_NA −20 | **CONFIRMED (code only)** | SC:106 |
| D3 | no surface or connectivity constraints | **CONFIRMED** | Paper Eq. 2 has contact + volume only (14c p.5). The code has no Surface or Connectivity plugin (SC:81–149). |
| D4 | F binary = 1 on lamellipodium boundary sites at z = 1 | **CONFIRMED (code)** | SS:88–95. The paper text says "one in Lamel voxels and … zero otherwise" (14c p.6, Fig. 1), which is a paper/code difference. |
| D5 | conversion probability ρ(χ tanh(µ(x − x̄)/sd) + 1) | **CONFIRMED (code)** | SS:156–159. The paper's Eq. 7 has no χ and multiplies by the Switch. |
| D6 | gated by V_l/V_cell − δ ≤ φ_EST | **CONFIRMED (code)** | SS:162. V_cell uses the **Cyto target** volume (SS:107). The paper uses a strict sign-function Switch with no δ (Eq. 6). |
| D7 | φ_EST = lamellipodium fraction averaged over the last 100 MCS | **CONFIRMED** | Paper Eq. 6 (p.8) and code SS:110–114. The code includes the current MCS and uses φ_F for mcs < 100. |
| D8 | defaults ρ = 0.5, χ = 1, δ = 0, µ = 0 | **CONFIRMED (code)** | SC:45–51. The paper's gradient runs use µ = 10⁶ (p.15). |
| D9 | no reverse conversion | **CONFIRMED** | No such rule exists in the paper or the code |
| D10 | F-actin drive −175 as the CC3D chemotaxis λ | **CONFIRMED (code)** | SC:22 and 149. The paper reports positive magnitudes 125, 150 and 175, and its Eq. 5 sign then opposes protrusion (§4.1). |
| D11 | χ > 0 → positive drift and chemotactic index | **CORRECTED** | The paper never varies χ and defines no "chemotactic index". Gradient response is switched on through **µ = 10⁶**. **Drift speed V_d (along polarization) does not change** with the gradient (Fig. 4, p.15). The response shows up as a polarization angle θ peaked at 0 (Fig. 5), a long-time ballistic MSD term B·Δt² (Eq. 17) and a chemotactic **efficiency** ε = V_T/V_d (Eq. 16). |
| D12 | χ = 0 gives zero mean drift | **NOT IN PAPER** | χ = 0 is not studied. In the isotropic case (µ = 0) the θ distribution is flat (Fig. 5) and B = 0. V_d along the polarization is still **non-zero** (Fig. 3; 14c-SM Table S1). |
| F24 | 14a F-actin is a PDE (not binary), sourced only at the substrate | **CONFIRMED (14a-code)** | codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253. It is unconfined, on the whole lattice, and solved once per MCS. Because D_F is so small, it is effectively a z = 1 indicator with a ×0.1/MCS memory (§2.9.2). |
| F25 | protrusion sign: ΔE = λ[F(target) − F(source)], λ > 0 | **CONFIRMED (14a-code, via the CC3D convention)** | Lambda = −150 with `ChemotactTowards="Medium"` on FRONT (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48, 263). The CC3D formula is CC3D-external. |
| F26 | the three compartments form one cluster, with internal vs external contact tables | **CONFIRMED (14a-code)** | `reassignClusterId` (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:116, 154). Contact and ContactInternal are used (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:162, 218). |
| D13 | smaller lamellipodia improve chemotaxis | **CONFIRMED** | ε decreases with φ_f, and also with λ_F-actin (Fig. 8, p.23; Fig. 6 values) |

---

## 7. Validation targets

Policy: agreement is statistical, over ensembles, with no bitwise parity. MSD-fit parameters are noisy (Table 2 is non-monotone), so compare them on a log scale and with the published replicate counts.

### 7.1 Base model (14a)

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| B1 | Onset sequence: symmetric cell → symmetric lamellipodium halo → competing leading edges → single leading edge with the nucleus trailing. Intermittent splitting and reorientation. | Fig. 4, p.2806–2807 | qualitative | Visual, plus Π_{CN−N} going from about 0 to a finite value |
| B2 | Compartment volumes within 1% of target in steady state | p.2806 | quantitative | mean \|V_C − V_C^t\|/V_C^t ≤ 2% |
| B3 | Regime map at R = 15 (Fig. 6). φ = 0.05: λ = 125–175 migrating, 200–250 detachment. φ = 0.10–0.30: λ = 125 confined, 150–200 migrating, 250 detachment. | Fig. 6 (read from figure) | semi-quantitative | Classification matches in ≥ 80% of cells (10 trajectories × 10⁵ MCS per cell) |
| B4 | Displacement after 10⁵ MCS vs λ_F. Below 2R for small λ; rising steeply between 125 and 175; about 10–40 R at λ = 175–200 for R = 10–15. | Fig. 5 (5 replicas, SE bars) | semi-quantitative | Within the published SE × 2, or a factor of 2 on a log scale |
| B5 | Modified-Fürth fits (S, P, D) per Table 2. Key points at R = 15, φ = 0.10: λ = 150 gives P = 6878, D = 2.83E−4, S = 9.68E−3; λ = 175 gives P = 12546, D = 2.37E−3, S = 9.84E−4; λ = 200 gives P = 23265, D = 5.66E−3, S = 3.93E−4. | Table 2, p.2810 | quantitative | S within ×2 (log), P within ±50%, D within ×2 (log). Averaged over ≥ 5 runs. |
| B6 | **Metzner match.** R = 15, φ_l = 0.30, λ_F = 160, 30 replicates → S = 0.02. The MSD and ψ_δ (δ = 0.515) overlap the MDA-MB-231 data. | Fig. 9; Table 2 (S = 2.12E−2) | quantitative (headline) | S ∈ [0.01, 0.04], with a collapsed MSD within 20% of Eq. 2 at S = 0.02 |
| B7 | Collapse: all MSDs fall onto Eq. 2 in natural units | Fig. 7 | quantitative | Residual RMS in log(MSD) ≤ 0.1 after the fit |
| B8 | S–D relation: S = D_fast/(D_fast + D), with D_fast = 0.127 R^−2 in (sites)^{2/3}/MCS. Collapse in D·R². | Fig. 11 | quantitative | D_fast within ±30% of 0.127 R^−2 |
| B9 | Mean speed \|u(τ, δ)\| diverges as δ → 0; ψ_δ behaves as in Fig. 8 | Fig. 8 | qualitative | Monotone increase as δ → 0 |
| B10 | Polarization (lamellipodium–nucleus distance) correlates with displacement only for S < Δτ < 1 | Fig. 12 | qualitative | Positive correlation in the ballistic window, and none for Δτ < S |
| B11 | Cost: R = 15, 10⁵ MCS ≈ 200 min on an i7-3770K; cost ∝ L_x L_y L_z | p.2810–2811 | performance | Informational (a performance-first target) |

### 7.2 Polarization study (14b)

| ID | Target | Source | Type | Tolerance |
|---|---|---|---|---|
| P1 | Δτ_opt^theor(S) = 1.932 S^0.455 and α_opt(S) = 2.022 − 1.115 S^0.397, obtained by maximising Eq. 12 | 14b p.10, Fig. 5 | analytic (deterministic) | Our numerical maximiser reproduces the fits to within 3% over S ∈ [10⁻⁴, 0.4]. This is a pure-math check. |
| P2 | Δτ_opt = 0.048 at R = 15, φ = 0.10, λ = 200. Δτ_opt = 0.672 at φ = 0.30, λ = 150, with S = 9.46E−2. | Fig. 4 caption; p.10 | quantitative | Our fitted S gives Δτ_opt within ±30% |
| P3 | ξ_{CN−N}(δ) peaks near Δτ_opt for φ = 0.10, λ = 200. All definitions fail for φ = 0.30, λ = 150. | Fig. 4 | qualitative | Peak location within a factor of 2 of Δτ_opt |
| P4 | ⟨u(Δτ_opt)⟩ increases and ε decreases with ⟨\|Π_{CN−N}\|⟩. ⟨u⟩ falls with φ. | Fig. 6 | qualitative / trend | Same monotonic trends |
| P5 | σ_θ decreases with ⟨Π⟩ and increases with φ. ⟨Π⟩ decreases with φ. | Fig. 7A–C | trend | Same monotonic trends |
| P6 | ⟨u_∥⟩_δ converges as δ → 0 while ⟨u⟩_δ diverges | Fig. 7D; Fig. 3B | qualitative | Relative change of ⟨u_∥⟩ over the smallest decade of δ is ≤ 10% |

### 7.3 Chemotaxis variant (14c; R = 10; 10 replicas)

| ID | Target | Source | Type | Tolerance |
|---|---|---|---|---|
| C1 | Isotropic case (µ = 0): flat θ histogram. Gradient case (µ = 10⁶): θ peaked at 0. The peak is sharpest at low λ and low φ_f. | Fig. 5 | qualitative | KS test: flat at µ = 0 (p > 0.05); peaked at µ = 10⁶ (mean cos θ > 0.3 for φ = 0.05, λ = 125) |
| C2 | Drift speed V_d is unchanged by the gradient. ⟨\|V_∥\|⟩ and ⟨\|V_⊥\|⟩ diverge as δ → 0; ⟨V_⊥⟩ → 0. | Figs. 3–4 | quantitative / qualitative | V_d(µ = 10⁶)/V_d(µ = 0) ∈ [0.8, 1.25] |
| C3 | Efficiencies ε = V_T/V_d. φ_f = 0.05: 0.57 (λ = 125), 0.42 (150), 0.27 (175). φ_f = 0.10: 0.34, 0.27, 0.17. φ_f = 0.20: –, 0.19, 0.13. | Fig. 6 labels; Fig. 8; 14c-SM Table S2 (0.570, 0.416, 0.267, 0.339, 0.274, 0.174, 0.191, 0.134) | quantitative | ±0.1 absolute. The ordering (decreasing in λ and in φ_f) must hold. |
| C4 | Four-regime MSD (Eq. 17) with SP < δ_opt < P < t_taxis (Eq. 19). t_taxis = 2D/(B(1−S)). | p.18–20; Fig. 6 | quantitative | The ordering holds for all moving sets |
| C5 | Table S2 fits (µ = 10⁶). Example: φ = 0.10, λ = 150 gives D = 1.73E−3 R²/MCS, P = 2.76E3, S = 1.11E−2, B = 4.61E−8, V_d = 7.83E−4 R/MCS, V_T = 2.15E−4. | 14c-SM p.7 | quantitative | D and B within ×2 (log), P ±50%, V_d ±25% |
| C6 | Table S1 fits (µ = 0): V_d between 3.81E−4 and 9.65E−4 R/MCS, and P between 1.05E3 and 7.20E3 MCS | 14c-SM p.7 | quantitative | V_d ±25%, P ±50%. **Do not target the S column in S1** (see §9). |
| C7 | mVACF tends to V_T² at large Δτ with a gradient, and to 0 without one. It shows a negative short-Δτ correlation. C_rr(Δt) < 0 at small Δt. | Figs. 9–10 | qualitative | Sign and asymptote |
| C8 | λ = 125, φ_f = 0.20 does not move enough to fit | Fig. 6 caption | qualitative | Confined behaviour reproduced |
| C9 | Cost: R = 10, 10⁵ MCS ≈ 4 h (i7-3770K) | p.9 | performance | Informational |

---

## 8. Required general features

| Need | Feature ID | Notes |
|---|---|---|
| One cell = cluster of 3 compartment sub-cells (nucleus, cytoplasm, lamellipodium) with kind lookup | **G10** cluster scope + `sibling(kind)` lookup + **retain_empty** membership | The lamellipodium starts **empty** in 14a and 14b and must persist as a cluster member with V = 0 and target φ_l V. Contact energies need the (kind, kind) pair and, in 14c-code, intra- vs inter-cluster tables. |
| Per-compartment volume constraints | core volume | – |
| Type-pair contact on a 4th-order (32-neighbour) shell; order-1 proposals | core | Separate neighbourhoods for energy and proposal |
| Intra- vs inter-cluster contact tables (14c-code) | **G10/G3** | Contact scope must know whether both sites belong to the same cluster |
| Frozen substrate layers (adherent bottom, non-adherent top), and medium | core frozen types + **G13** | Planes at z = 0 and z = L_z − 1 |
| F-actin work term: lamellipodium ↔ medium copies, both extension (lamellipodium source → medium target) and retraction (medium overwriting lamellipodium), as both released codes do via CC3D's default chemotaxis algorithm (14a-code and 14c-code; §2.9.4, §9 item 16; D-067); Eq. 7 extension-only as a variant; uses F at source and target; position-restricted (z = 1 in 14c-code) | **G3** contact/proposal scope with source/target kinds, positions and field values | Non-conservative ΔE, not part of H |
| F-actin PDE (14a; 14a-code codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253): diffusion D_F, decay on the whole lattice, source on lamellipodium sites in contact with the substrate (z = 1); periodic x, y | **G5** symbolic field BCs + solver (explicit or implicit substeps per MCS) | A source term defined by a site predicate (kind and z). This is **not** conservative secretion, so G6 is not needed. |
| Binary indicator field (14c-code): F = 1 on lamellipodium **boundary** sites at z = 1, refreshed once per MCS (stale within an MCS) | **G14 (new): derived site fields from lattice predicates**, refreshed at a declared cadence (per MCS or per copy) | Justification: 14c replaces the PDE with a lattice-derived indicator. The per-MCS refresh with stale in-MCS values is a behavioural detail. Exact refresh cadence is not needed (performance over exactness), but the choice must be documented. Alternative: express the drive directly as a kind/position predicate in G3 and drop the field. |
| Cytoplasm → lamellipodium conversion after each MCS, probabilistic, at substrate-contact sites | **G7** `@convert` + **G1** `rand(Bernoulli)` | 14a: p ∝ (1 − V_l/V_l^t). 14c: ρ(χ tanh(µ(Q − ⟨Q⟩)/σ_Q) + 1) with a gate. **Sequential** conversion with running volume updates is required (the gate is re-evaluated after each conversion). |
| Per-cell reductions over a site subset (the base = boundary sites at z = 1): mean and SD of Q | **G14b (new): site-set reductions** (sum, mean, std over a cluster's sites filtered by a predicate such as boundary or z) | Justification: Eq. 7 normalises by the base-pixel statistics. This is not a shape descriptor (G2) and not a cluster scalar (G10). |
| 100-MCS moving average of φ_l, compared with the current value | **G3** lagged cell vars, extended to a **windowed average** (ring buffer) → proposed **G15** | Justification: G3 covers lagged vectors. A running window mean is a distinct, general history primitive. |
| Static linear external field Q(x), unwrapped relative to the cell's COM across the periodic x | **G5** static field + **G3** position (periodic-unwrapped) | – |
| Observables: per-compartment COM (periodic-unwrapped); CN combined COM; Π vectors (Eq. 10); MSD; modified-Fürth (3- and 4-regime) fits; u(τ, δ); ψ_δ / mVACF; drift speed V_d; θ histogram; ε; C_rr; cell-frame displacement histograms; α(Δτ) maximiser | **G12** observables library | The fit routines (14a SM S1 and 14c-SM §IV) belong in analysis, not in the core |
| Initial layouts: sphere + cubic nucleus (14b); hemisphere + nucleus sphere + one-voxel Lamel ring (14c-code); "suspended" cell (14a) | **G13** | – |
| Connectivity | **G4**: not used by any source | Optional. 14a counts detachment as an artefact (Fig. 6, light red), which a connectivity diagnostic would detect. |
| Proposal law | **G8**: not needed | Standard Metropolis |
| Ordered relationships and angle energies | **G11**: not needed | – |

### One compartment/linked-subcell abstraction for 13 and 14

The papers support **one** abstraction: a cluster of sub-cells whose members have a *kind* and optionally an *index*, with relationships between members.
- **14 (unordered, typed).** Needs sibling-by-kind lookup, retain_empty members, intra- vs inter-cluster contact, site conversion between siblings, and per-member COM observables.
- **13 (ordered, identical kind).** Needs index-ordered relationships, contact depending on index distance, and energies and work terms on member COMs (distance, circumradius, chord direction).

Neither model needs anything that contradicts the other:
- 14 needs no ordering and no COM energies.
- 13 needs no empty members and no conversion.

**Code caveat.** 14a-code *does* form a CC3D cluster and uses separate intra- and inter-cluster contact tables (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:116, 154; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:162, 218). This supports G10 intra/inter contact scope. 14c-code never actually forms a CC3D cluster (the compartments are independent cells). The paper-level model is still a single compartmentalised cell, and with one cell per simulation this is behaviourally equivalent, apart from which contact table applies.

---

## 9. Ambiguities, conflicts and questions for the authors

Each item is marked **RESOLVED** (with a citation) or **STILL OPEN**. Resolutions from 14a-code resolve what the released code does. Where the paper disagrees, the discrepancy stays listed in §2.9.7.

1. **F-actin field. RESOLVED for 14a.** 14a used a real PDE.
   - It runs through CC3D `DiffusionSolverFE` with D_F = 1e-4 and decay 0.9 on the whole lattice (unconfined).
   - The source is 0.9, placed only on FRONT sites in contact with SUBS_A (the z = 1 layer).
   - It is refreshed once per MCS after the Potts sweep (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:244–253; §2.9.2).
   - 14b Eq. 9 (source on all lamellipodium sites) and the code-header comment (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:3, 5) misdescribe it.
   - 14c's binary z = 1 field is a deliberate simplification. It is behaviourally close, because √(D_F/k_decay) ≈ 0.01 sites.
   - The sub-parts about solver internals are now RESOLVED from the CC3D source; see items 15 and 16.
2. **Protrusion sign. RESOLVED.** 14a-code uses λ_CC3D = −150 with `ChemotactTowards="Medium"` on FRONT (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:48, 263). Under CC3D's formula (CC3D-external) this is 14a Eq. 7 with λ = +150. The spec keeps the **14a Eq. 7 convention**, ΔE = λ[F(target) − F(source)] with λ > 0, and maps code values by λ = −λ_CC3D. The same mapping explains 14c-code's −175.
3. **J_cyto–lamellipodium. RESOLVED for code; the paper discrepancy remains.** Both released codes use **10**: 14a-code ContactInternal (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:230) and 14c-code (SC:120, 139). Table 1's 20 is either a typo or a different version. Use 10 for code-parity runs and flag the Table 1 value. 14a-nH also uses 10 (nH:P3:139); 14a-S1 lists no J values (checked 2026-09-30). STILL OPEN for the authors: which value produced the 14a figures.
4. **Eq. 4 delta product. RESOLVED.** In the code, the contact energy is zero only within the same generalized cell (the same compartment of the same cell). Different compartments of the same cell get the ContactInternal values (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:218–240). So the rule is "zero only if same σ **and** same C".
5. **Surface constraint. RESOLVED (none).** The Surface plugin is loaded for tracking only, with no target surface or λ (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:146). There is no surface energy.
6. **Temperature units. RESOLVED.** The code uses T = 100 and J₀ = 20 directly (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:80–81). The Table 1 numbers are the raw CC3D inputs, and the footnote's "rescaled by T" does not imply any further division.
7. **Conversion rule (14a). RESOLVED** (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:121–165; §2.9.5).
   - The constant is 0.1.
   - The rule uses **target** volumes: the FRONT target, growing from 1.5, over φ_F × total target.
   - It is skipped when p ≤ 0.
   - "Touches substrate" means CYTO boundary pixels at z == 1, which is every CYTO site at z = 1.
   - Conversion is sequential, with p recomputed after each conversion.
   - It runs after the Potts sweep and the PDE (the order is CC3D-external).
8. **Lattice size and z boundaries. RESOLVED.**
   - L_x = L_y = int(8R), or int(10R) when R ≥ 20 and φ_F ≥ 0.2. L_z = int(2.1R).
   - x and y are periodic, and z uses the CC3D default.
   - There is a frozen adherent SUBS_A plane at z = 0 and a frozen non-adherent SUBS_NA plane at z = L_z − 1 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:66–75, 104–105, 113–114; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:80–83).
   - 14c-code's ≈ 5.9R remains a 14c-only choice.
9. **Initial condition. RESOLVED for 14a-code; the warm-up is STILL OPEN.**
   - The code starts from a ball tangent to the substrate, with a 6×6×6 cubic nucleus and no lamellipodium (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:72–105). This matches 14b p.8.
   - 14a Fig. 4A's "suspended" cell is illustrative and is not the run IC.
   - 14c-code's hemisphere plus ring is a separate 14c choice.
   - The code has no built-in warm-up; statistics windows are chosen in post-processing. The 14a warm-up (SM S2) and 14b's 1000 MCS remain the only statements.
10. **14c gate details. STILL OPEN.** These are not addressed by 14a-code:
    - the δ used in the paper figures (the code default is 0; the README suggests 0.01);
    - strict "<" (the paper's sign function) vs "≤" (the code);
    - CELLvol using the Cyto *target* volume;
    - whether the current MCS is included in the 100-MCS average.

    Note that the use of target volumes in CELLvol is inherited from 14a-code (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:132–138).
11. **14c-SM Table S1 S column. STILL OPEN.** The values (0.81–0.95) are inconsistent with Table S2 (0.003–0.10) and with 14a Table 2 at similar parameters. The column may be mislabelled or computed from a different quantity. Do not use it as a target.
12. **14c Fig. 8 caption. STILL OPEN (paper-internal).** The caption says the non-fitting set is λ = 125, φ_f = 0.05. Fig. 6 caption and Table S2 show that it is λ = 125, φ_f = **0.20**.
13. **14c version. STILL OPEN.** The spec is based on arXiv v1 (2023). The version of record is *Physica A* 666 (2025) 130524, doi 10.1016/j.physa.2025.130524. Checked 2026-09-30: arXiv has only v1, and the version of record is closed access with no open copy (Unpaywall), so it could not be diffed. Items 10 and 12 stay open until it is.
14. **Multi-cell J values. PARTIALLY RESOLVED.** 14a-code's Contact table gives inter-cell compartment values: CYTO–CYTO 40, CYTO–FRONT 40, CYTO–NUCL 100, FRONT–FRONT 40, FRONT–NUCL 100, NUCL–NUCL 100 (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:198–209). No source runs multi-cell simulations, so these are unvalidated. 14c-code's external table cannot serve as an inter-cell table, because it doubles as the intra-cell table.
15. **F-actin magnitude at source sites. RESOLVED 2026-09-30 (CC3D source).** In both CC3D 3.7.9 and 3.6.2, `DiffusionSolverFE` makes one call per MCS for D_F = 1e-4 (no sub-stepping) and runs diffusion + decay **before** secretion (CC379:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:835–841; CC362:steppables/PDESolvers/DiffusionSolverFE.cpp:537–557). So c ← 0.1c + 0.9 at a source site and **F → 1** during the next Potts sweep. `SecretionOnContact` tests only the 6 face neighbours and adds the rate once per site per call (CC379:steppables/PDESolvers/DiffusableVectorCommon.h:78; CC379:steppables/PDESolvers/DiffusionSolverFE_CPU.cpp:316–335). Details in §2.9.2. Caveat: 14a-S1 p.2 names 3.5.1 as the version used; its source is not on the official GitHub and was not checked. `Instructions_To_Run.pdf` (now read) does not discuss the solver.
16. **Chemotaxis plugin scope on retraction. RESOLVED 2026-09-30 (CC3D 3.7.9 and 3.6.2 source); decision changed and approved (D-067).** With the default "merks" algorithm, `ChemotaxisByType Type="FRONT" ChemotactTowards="Medium"` contributes both when FRONT overwrites Medium and when Medium overwrites FRONT, with the same formula λ_CC3D [c(source) − c(target)] (CC379:plugins/Chemotaxis/ChemotaxisPlugin.cpp:272–273, 434–455, 487–502; §2.9.4). CC3D 3.6.2 is the same (CC362:plugins/Chemotaxis/ChemotaxisPlugin.cpp:57, 295, 491, 513). 14c-code uses the same plugin with no `Algorithm` element (SC:147–149), so there too Medium overwriting a z = 1 LAMEL pixel with F = 1 costs +175; its CC3D 4.2.3 was not checked but is very likely the same. This differs from a literal extension-only reading of 14a Eq. 7 and from the comment (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:6); it is listed as §2.9.7 item 19 and asked in the letter as part of the provenance question. **Decision changed** (specs README §4 C7; changed 2026-09-30 on new evidence; approved by the maintainer 2026-09-30; D-067): the default follows the code, applying the term in both directions for 14a and 14c; the paper's Eq. 7 extension-only form is a variant. Previously: Eq. 7, extension only.
17. **Code provenance. STILL OPEN (new).** The Python and XML files are dated 2021-08, after publication, and the CC3D version tags disagree (3.7.9 / 3.7.5 / 3.5.1; codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D.py:13, 94; codebases/14a_Fortuna2020_Crawling/Published/CellMig3D.cc3d:1). It is unconfirmed that this exact code produced the 14a figures. Discrepancies 1–2 in §2.9.7 (J_cyto–lamellipodium; the target-based conversion) are the ones that matter if it did not. **Checked 2026-09-30:** 14a-S1 does not contain the code; it describes the same project (same `.cc3d` content, same file roles and output columns) and a wider ParameterScan than the zip's XML, and it names CC3D **3.5.1** for the paper's runs while 14a-instr names **3.6.2** (§2.9). 14a-nH is a port of 14a-code with the same settings (§2.9.8). So the code is consistent with the documents, but no source states that the figures used J_cyto–lamellipodium = 10 and the target-based conversion. STILL OPEN for the authors, narrowed to: were those settings used for Figs. 5–12, and which CC3D version was used.
18. **Conversion RNG. RESOLVED (noted).** The conversion stream uses a fixed `seed(1000)`, independent of the Potts seed (codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:57). A reimplementation should use an independent per-replicate stream; per the performance-over-exactness policy, parity with this is not required.
19. **Fig. 12 polarization measure. STILL OPEN (from §2.9.7 item 12).** 14a Fig. 12 says "lamellipodium–nucleus"; the released outputs hold both `dcm_F_CN` (F to C+N, xy, ÷R) and the separate F and N COMs (14a-S1 p.4). Which was plotted is unknown.
20. **Document S1 inconsistencies. STILL OPEN (minor; deferred to batch 2).** The scan list lacks Table 2's λ = 160, 165, 170; it prints 830 where the product is 840; and it describes a spherical nucleus with the cell centred at L_z/2, while the code uses a 6³ cube (§2.9.7 item 20).
