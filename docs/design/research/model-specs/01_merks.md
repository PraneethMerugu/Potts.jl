# 01 — Merks vasculogenesis / contact-inhibited chemotaxis (paper-grounded spec)

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **01a** | R.M.H. Merks, S.V. Brodsky, M.S. Goligorsky, S.A. Newman, J.A. Glazier, "Cell elongation is key to in silico replication of in vitro vasculogenesis and subsequent remodeling", *Developmental Biology* **289** (2006) 44–54 | 10.1016/j.ydbio.2005.10.003 | `docs/references/01a_Merks2006_DevBiol_vasculogenesis-elongation.pdf` (11 pp.) |
| **01b** | R.M.H. Merks, E.D. Perryn, A. Shirinifard, J.A. Glazier, "Contact-Inhibited Chemotaxis in De Novo and Sprouting Blood-Vessel Growth", *PLoS Comput Biol* **4**(9): e1000163 (2008) | 10.1371/journal.pcbi.1000163 | `docs/references/01b_Merks2008_PLoSCB_contact-inhibited-chemotaxis.pdf` (16 pp.) |

How to read the citations: 01a pages are journal pages 44–54 (PDF page = journal page − 43). 01b pages are the PLoS page numbers, which match the PDF pages.
**Now on disk (added later):**
- 01b Dataset S1 (parameter files): `docs/references/supplementary/01b_Merks2008_DatasetS1_parameter-files/`.
- 01b Protocol S1 (Tissue Simulation Toolkit v0.1.3 source): `docs/references/codebases/01b_Merks2008_TissueSimulationToolkit-v0.1.3/`.

Both are analysed in **§7**. §§2–6 remain paper-grounded. Where the code fills a gap, the table entry gives the code value with a pointer to §7. For 01a, such values are always labelled "2008-code value, assumed for 2006".

**Added 2026-09-30 (pre-send checks; sha256 in `docs/references/codebases/SOURCES.md`):**
- **01a-mov.** 01a supplementary movie, `docs/references/supplementary/01a_Merks2006_DevBiol_mmc1_supplementary-movie.mp4` (publisher CDN https://ars.els-cdn.com/content/image/1-s2.0-S0012160605007098-mmc1.mp4; 256 × 256 px, 1000 frames, 40 s, no time stamps). It is the only 01a supplementary file the CDN serves (probed mmc1–mmc6 with common extensions).
- **01a-PMC.** The PMC author manuscript (PMC2562951, NIHMS66086), saved as HTML: `docs/references/supplementary/01a_Merks2006_PMC2562951_author-manuscript.html`. For the Q1 statements it has the same text as the journal PDF: "about 100 μm", "E 0 > 2000", 282 cells over a 333 × 333 px area in a 500 × 500 lattice. It includes no supplementary methods.
- **01c.** J.T. Daub, R.M.H. Merks, "Cell-Based Computational Modeling of Vascular Morphogenesis Using Tissue Simulation Toolkit", *Methods Mol Biol* **1214** (2015) 67–127, doi 10.1007/978-1-4939-1462-3_6; CWI repository preprint (65 pp.), `docs/references/supplementary/01a_DaubMerks2015_MethodsMolBiol1214_TST-tutorial_CWI-preprint.pdf`, from https://ir.cwi.nl/pub/23059/23059B.pdf. Cited by preprint page.

**Not on disk:** the 01a "Supplementary methods" cited in the Fig. 2 caption (01a p.46): not served by the publisher CDN, and the ScienceDirect article page refuses scripted access (HTTP 403), so it could not be located. 01b Figures S1–S2 and Videos S1–S56 (01b p.12–15).

The two papers describe **two model variants that share a core**:
- **Variant E (elongation; 01a).** An area constraint, a length constraint, chemotaxis at every interface, a dissipation threshold E0 and a local connectivity constraint, on a 2nd-order neighbourhood.
- **Variant CI (contact-inhibited chemotaxis; 01b).** An area constraint and chemotaxis at cell–ECM interfaces only (optionally saturating, optionally extension-only), on a 4th-order neighbourhood. There is no length constraint (unless stated), no E0, and no connectivity constraint is mentioned.

---

## 2. Mechanics

### 2.1 Lattice, representation, neighbourhood

| Item | 01a (Variant E) | 01b (Variant CI) |
|---|---|---|
| Lattice | 2D square; "a patch of identical non-zero values represents a cell and a value of 0 identifies the ECM" (01a p.46) | 2D; "square or triangular lattice" (01b p.11). The lattice used for the results is not stated explicitly; "twenty, first- to fourth-nearest neighbors" implies square (01b p.11) |
| Medium | ECM = "generalized CPM cell without a volume constraint and with σ = 0" (01a p.47) | Thin extracellular-fluid layer = generalized cell, no volume constraint, σ = 0. The chemoattractant lives in an **unrepresented** rigid ECM under the cells, and the fluid "does not disturb" it (01b p.11) |
| Hamiltonian neighbourhood | "the eight second-order neighbors" (01a p.47, below Eq. 1) | "up to fourth-order neighbors" (01b p.11, below Eq. 2) |
| Copy-target neighbourhood | "randomly chosen neighboring lattice site" (01a p.47). The order is **not stated separately** | "we select the source site from the twenty, first- to fourth-nearest neighbors" (01b p.11). See ambiguity A-8 |
| Site size | 2 µm × 2 µm (01a p.48 Fig. 4 caption; p.49 "Δx = 2 µm") | 2 µm × 2 µm (01b p.11) |
| Boundary | Frozen border pixels of type B with J_c,B = 100 (01a p.48) | "fixed boundary conditions", J(c,B) = 100 (01b p.11) |

### 2.2 Effective energy

**01a Eq. (1), p.47:**
E = Σ_{x,x′} J_{σ(x),σ(x′)} (1 − δ_{σ(x),σ(x′)}) + λ Σ_σ (a_σ − A_σ)²
λ is "resistance to compression". The sum runs over x′ in the 8 second-order neighbours of x.

**01a Eq. (4), p.48 (length constraint):**
E′ = E + λ_L Σ_σ (l_σ − L_σ)²
l_σ is the length along the longest axis, L_σ the target length and λ_L the strength.

**01a length estimator, p.48:** l_σ = 4 √(λ_b,σ / a_σ), where λ_b,σ is the largest eigenvalue of the inertia tensor I. The paper warns that it "overestimates the cell length by about 33%" (ends thicker than the middle). The source is Zajac et al. 2003 (01a p.48).

**01a Eq. (5), p.49 (inertia tensor from site moments):**
I = [[Σx² − (1/a)(Σx)², −Σxy + (1/a)ΣxΣy], [−Σxy + (1/a)ΣxΣy, Σy² − (1/a)(Σy)²]]
The moments are updated incrementally on each extension or retraction, "without lengthy non-local calculations" (01a p.49).

**01b Eq. (2), p.11:**
H = Σ_neighbors J(σ(x),σ(x′))(1 − δ(σ(x),σ(x′))) + λ Σ_σ (a(σ) − A_target(σ))²
There is no length term unless stated. Only Fig. 3A–C and Fig. S1 use the length constraint "see [22]" (01b p.5, p.12).

### 2.3 Chemotaxis term (evaluated at copy time, not part of H)

**01a Eq. (2), p.47:** ΔH_chemotaxis = γ (c(x) − c(x′))
x′ is "the neighbor into which site x copies its spin" and γ = 1000. This is equivalent to −γ(c(x′) − c(x)). It favours copies into higher concentration. **Scope: all copies**, including cell→ECM, ECM→cell and cell→cell. 01a has no restriction by interface type in the standard model.

**01b Eq. (3), p.12 (saturating, Savill–Hogeweg):**
ΔH_chemotaxis = −μ ( c(x′)/(1 + s c(x′)) − c(x)/(1 + s c(x)) )
- x′ is the target and x the source. s is the saturation parameter, default s = 0 ("Unless we specify otherwise", p.12).
- Saturation is applied **to each concentration separately (a receptor-occupancy form)**, not to the difference.
- "μ = χ(c,M) at cell-ECM interfaces and μ = χ(c,c) at cell-cell interfaces" (p.12).
- Default: χ(c,c) = 0 and χ(c,M) = 500 (p.12).
- "Both extending and retracting pseudopods contribute" (p.12).

**01b Eq. (4), p.12 (extension-only variant, Figs. 11–13):**
ΔH_chemotaxis = −(1 − δ(σ(x),0)) μ ( c(x′)/(1+s c(x′)) − c(x)/(1+s c(x)) )
The term applies only if the **source** site belongs to an EC. Retractions (ECM copying into a cell site) are chemotactically neutral.

**01a contact-inhibition variant (Fig. 9c, p.50):** "we suppress formation of chemotactic filopodia and lamellipodia at endothelial cell contacts", and p.51 describes it as "suppressing the chemotaxis energy term at endothelial cell interfaces". This is the precursor of 01b's χ(c,c) = 0.

### 2.4 Acceptance rule

**01a Eq. (3), p.48:** P(ΔE) = exp(−(ΔE + E0)/T) if ΔE ≥ −E0, and P = 1 if ΔE < −E0. T = 50.
"E0 is an energy threshold which models viscous dissipation and energy loss during bond breakage and formation" (Hogeweg 2000). **The numerical value of the dissipation E0 is not given.** See A-2. *Code (§7.3):* TST's only E0 is `conn_diss`, applied only to connectivity-breaking copies. Otherwise E0 = 0 (2008-code value, assumed for 2006).

**01b, p.11:** P(ΔH) = exp(−ΔH/T) if ΔH ≥ 0, and 1 if ΔH < 0. There is no threshold. T = 50 in all simulations "except those in Figures 11–13". T is "the intrinsic cell motility".

ΔH in both papers is the adhesion + area (+ length) change plus the chemotaxis ΔH.

### 2.5 Monte Carlo step

- 01a p.47: "During a Monte Carlo Step (MCS), we attempt n copies, where n is the number of sites in the lattice." The source site is random and the target a random neighbour.
- 01b p.11: "N copy attempts, with N the number of sites in the lattice".
- Neither paper states whether sites are drawn with or without replacement, or whether same-spin picks count as attempts. UNSPECIFIED in the papers. *Code (§7.3):* there are (sizex−2)(sizey−2) attempts. The target is drawn with replacement and the source is a random neighbour. Same-spin and border-source picks count as attempts.

### 2.6 Connectivity (01a only)

The local test is on p.49 with Fig. 3 on p.47. For target site x with neighbours x_i taken in cyclic (clockwise) order, compute
Σ_i δ_{σ(x),σ(x_i)} (2 − δ_{σ(x),σ(x_{i+1})} − δ_{σ(x),σ(x_{i−1})}).
If this is > 2 "and we have more than two (non-medium) cells in the local neighborhood", changing the site "will destroy the local connectivity".

The Fig. 3 caption rules, where a "collision" is a neighbour pair with the same index as x next to one with a different index:
- (a) exactly two collisions → accept;
- (b) more than two → reject, unless rule (c) applies;
- (c) more than two with exactly two non-ECM cells involved → accept;
- (d) more than two with one non-ECM cell → reject;
- (e) false rejects are possible.

**Implementation as stated:** "we make cell fragmentation energetically costly by assigning a large energy penalty (we currently use E0 > 2000) to updates that change local connectivity" (p.49). So it is a **soft penalty**, not a hard reject. The symbol E0 is reused (A-3). The neighbour ring used (8 second-order neighbours, presumably) is not stated.

### 2.7 Chemoattractant field

**01a Eq. (6), p.49, as printed:**
∂c/∂t = α δ_{σ(x),0} − (1 − δ_{σ(x),0}) ε c + D∇²c
It is followed by "where δ_{σ(x),0} = 1 inside the cells". The prose says "Every site within a cell secretes the chemoattractant, which only decays at sites within the ECM". So the δ symbol is used **inverted** relative to the paper's own Kronecker definition (A-4). **Intended semantics (from prose, and matching 01b Eq. 1):** secrete α at cell sites and decay εc at ECM sites.

**01b Eq. (1), p.3:** ∂c/∂t = α(1 − δ(σ(x),0)) − ε δ(σ(x),0) c + D∇²c, with δ = 0 inside cells and 1 in the ECM. This is consistent.

**Solver:**
- 01a p.49: "finite-difference scheme on a lattice that matches the CPM lattice, using 15 diffusion steps per MCS with Δt = 2 s and Δx = 2 µm".
- 01b p.12: "15 diffusion steps per MCS, with Δt = 2 s".
- Neither paper states explicit/implicit, the stencil, the field boundary condition, or the initial c. The initial c and field BC are UNSPECIFIED in the papers. *Code (§7.4):* explicit FTCS with a 5-point stencil, absorbing c = 0 BC and c₀ = 0.
- No advection: "chemoattractant diffuses much more rapidly than the cells move" (01a p.49–50; 01b p.12).

**Coupling order:** the paper says only "15 diffusion steps per MCS". Whether the PDE runs before or after the CPM sweep is UNSPECIFIED in the papers. *Code (§7.4):* the PDE runs before the CPM sweep, as 15 × (secretion/decay, then diffusion), with absorbing BC and c₀ = 0.

### 2.8 Growth / division / death / state changes

None. 01b p.11: "we assume that ECs do not divide or grow during patterning". 01a has no proliferation or death either; the cell number is fixed.

### 2.9 Initial conditions

- **01a standard (Fig. 4, p.48; p.50):** "We randomly distributed 282 virtual endothelial cells over a 333 × 333 pixel area, which we positioned in a 500 × 500 lattice". The text also says "a simulated area of 666 µm × 666 µm", and the caption says "total simulated area is 1000 µm × 1000 µm". The initial cell shape and size at seeding are UNSPECIFIED (single pixels vs. target-area blobs). TST seeds point cells and grows them by Eden growth (§7.6). That is a 2008-code method, assumed for 2006, and the 2006-labelled files do not reproduce the 282-cell geometry.
- **01b vasculogenesis (Fig. 2, p.4):** "randomly distributed 1,000 ECs, each with an area of ~200 µm² over an area of ≈700 µm × 700 µm (333×333 lattice sites …) … inside a larger lattice of 1,00 µm×1,00 µm". The enclosing lattice size is garbled in the PDF (A-9).
- **01b sprouting:** "a large cluster of endothelial cells representing a blood vessel's surface after degradation of the ECM" (p.5). "rounded clusters" (p.5). Fig. 4A shows a disc (p.6). The packing method is UNSPECIFIED in the paper. *Code (§7.6):* one central Eden blob (50 rounds), split 7× into 128 cells, then 100 relaxation MCS. Cluster sizes and lattices per figure are in §3.3.

### 2.10 Time scale

- 01a p.50: "Each MCS corresponds to 30 s". Mean and mode of cell velocity are then "5 µm/h with some cells moving up to 30 µm/h".
- 01b p.11: "experimental time per MCS to 30 s". Captions: 10 MCS ≈ 5 min, 1000 MCS ≈ 8 h, 10,000 MCS ≈ 80 h (01b p.4 Fig. 2).
- Derived: 15 × 2 s = 30 s = 1 MCS, so the PDE sub-steps exactly cover one MCS of physical time.

---

## 3. Parameter tables

Citation shorthand in these tables:
- Bare TST file names (`ca.cpp:236`, `pde.cpp:104`, `vessel.cpp:86`, `longcells.par:8`, `default.par:8`) mean (codebases/01b_.../TST0.1.3/<file>:line).
- `sprout_*.par` / `denovo_*.par` mean (supplementary/01b_.../<file>:line).

### 3.1 Variant E — 01a standard model

| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| J_c,c | 40 | energy | EC–EC bond energy | 01a p.48 (col. 2) |
| J_c,M | 20 | energy | EC–ECM bond energy ("neutral binding energy settings") | 01a p.48 |
| J_c,B | 100 | energy | EC–frozen-border energy | 01a p.48 |
| J_M,B | UNSPECIFIED in paper. **0** (2008-code value, assumed for 2006) | — | ECM–border energy | ca.cpp:236-238, §7.2 |
| T | 50 | energy | Metropolis temperature | 01a p.48 |
| E0 (dissipation) | UNSPECIFIED in paper. **0 for connectivity-preserving copies**: TST has no separate dissipation constant (2008-code value, assumed for 2006) | energy | Threshold in Eq. 3 | 01a p.48 Eq. 3; ca.cpp:442-448, §7.3 |
| E0 (connectivity penalty) | "> 2000". Code: 2000 (default.par:8) or 5000 (longcells.par:12) (2008-code values, assumed for 2006; D-13) | energy | Same variable as the E0 above, applied only when local connectivity breaks | 01a p.49; §7.3 |
| λ | UNSPECIFIED in paper. **50** (2008-code value, assumed for 2006) | energy/px⁴ | Area constraint strength | 01a p.47; longcells.par:9 |
| A_σ | UNSPECIFIED in paper (inferred 100). **100** (2008-code value, assumed for 2006) | px | Target area | longcells.par:7 |
| λ_L | UNSPECIFIED in paper. **5.0** (2008-code value, assumed for 2006) | energy/px² | Length constraint strength | 01a p.48; longcells.par:10 |
| L_σ | "about 100 µm" (= 50 px). Code files: 60 px = 120 µm (D-12, STILL OPEN) | µm | Target length | 01a p.50; longcells.par:8 |
| γ (chemotaxis) | 1000 | energy/conc. | Chemotactic strength | 01a p.47 Eq. 2 |
| α | 1.8 × 10⁻⁴ | s⁻¹ (conc/s) | Secretion rate | 01a p.49 |
| ε | 1.8 × 10⁻⁴ | s⁻¹ | ECM decay rate | 01a p.49; p.50 |
| D | 10⁻¹³ | m² s⁻¹ | Diffusion coefficient | 01a p.49 |
| Δt | 2 | s | PDE step | 01a p.49 |
| steps/MCS | 15 | — | PDE sub-steps | 01a p.49 |
| Δx | 2 | µm | Site size | 01a p.49; Fig. 4 caption p.48 |
| MCS | 30 | s | Time per MCS | 01a p.50 |
| N_cells | 282 | — | Cell count | 01a p.48 Fig. 4; p.50 |
| Seed region | 333 × 333 | px | Random-placement area | 01a p.48 Fig. 4 |
| Lattice | 500 × 500 | px | Domain | 01a p.48 Fig. 4 |
| Neighbourhood | 2nd order (8) for H. Proposal also 8 (2008-code value, assumed for 2006) | — | Hamiltonian / copy | 01a p.47; longcells.par:18, §7.3 |
| Initial c | UNSPECIFIED in paper. 0 (2008-code value, assumed for 2006) | — | — | pde.cpp:104-106 |
| Field BC | UNSPECIFIED in paper. Absorbing c = 0 on the outer ring (2008-code value, assumed for 2006) | — | — | pde.cpp:189-194, :270-285 |
| PDE scheme / order | UNSPECIFIED in paper. Operator-split forward Euler (secretion/decay then FTCS 5-point diffusion) × 15, before the CPM sweep (2008-code value, assumed for 2006) | — | — | vessel.cpp:86-94, §7.4 |
| Chemotaxis scope | all copies (literal Eq. 2). Code: `vecadherinknockout = true` in 2006-labelled files (2008-code value, assumed for 2006) | — | — | longcells.par:13; ca.cpp:264 |
| Run length | ≥ 50 h (Fig. 5 axis) | h | — | 01a p.48 Fig. 5 |

**Derived (01a):**

| Quantity | Value | Derivation |
|---|---|---|
| Standard A | ≈ 400 µm² = 100 px (inferred) | Fig. 8 (p.50) keeps the covered area constant: 141×800 = 94×1200 ≈ 112,800 µm² ≈ 70×1600 = 56×2000 = 112,000 µm². Fig. 8 also keeps L:A fixed (200/800 … 500/2000 µm/µm²). Dividing by 282 cells gives 400 µm² = 100 px, and L = 100 µm = 50 px, which matches "about 100 µm". **Inference, not stated.** |
| L in lattice units | 50 px | 100 µm / 2 µm |
| Run length in MCS | 6000 MCS for 50 h | 50 × 3600 / 30 |
| Diffusion number | D Δt/Δx² = 10⁻¹³ × 2 / (2×10⁻⁶)² = 0.05 | explicit-FTCS-stable if explicit |
| Diffusion length | √(D/ε) = √(10⁻¹³/1.8×10⁻⁴) ≈ 23.6 µm ≈ 11.8 px | 01b p.5 defines L = √(D/ε) |
| Surface tension γ_c,M | J_c,M − J_c,c/2 = 0 | "neutral binding" (01a p.48). 01b p.6 states this identity explicitly |
| Cell area fraction in seed region | 282×100 / 333² ≈ 0.25 | uses derived A |

**01a variant/parameter sweeps (stated):**

| Figure | Change | Source |
|---|---|---|
| Fig. 6 | L = 20, 40, 60, 80, 100 µm | 01a p.49 caption |
| Fig. 7 | J_c,c = 20, 15, 10, 5, 1 (J_c,M = 20) | 01a p.49 caption |
| Fig. 8 | (L, A, N) = (200 µm, 800 µm², 141), (300, 1200, 94), (400, 1600, 70), (500, 2000, 56) | 01a p.50 caption |
| Fig. 9a | α = ε = 1.25×10⁻³ s⁻¹, λ_L = 0, 415 cells, A = 100 px; round control L = 10, λ_L = 50 | 01a p.50 caption |
| Fig. 9b | A = 50 px (no networks). Adhesion ref. (Merks 2004 rescaled): 1000 cells, ε = 1.25×10⁻³, α = 2.5×10⁻³, J_c,c = 1; round control L = 0, λ_L = 50 | 01a p.50 caption |
| Fig. 9c | contact inhibition, round cells L = 10, λ_L = 50 | 01a p.50 caption |
| p.53 | VEGF165-like D ≈ 10⁻¹¹ m² s⁻¹, half-life 30–60 min → islands (not shown) | 01a p.53 |

### 3.2 Variant CI — 01b standard model

| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| J(c,c) | 40 | energy | EC–EC | 01b p.11 |
| J(c,M) | 20 | energy | EC–medium | 01b p.11 |
| J(c,B) | 100 | energy | EC–border | 01b p.11 |
| J(M,B) | **0** (code) | energy | medium–border | codebases/01b_.../TST0.1.3/ca.cpp:236-238 |
| J(M,M) | 0 | energy | — | supplementary/01b_.../J.dat:2 |
| λ | 25 | energy/px⁴ | Area constraint | 01b p.11 |
| A_target | 50 | px (= 200 µm²) | Target area; "cell diameter of about 16 µm" | 01b p.11 |
| T | 50 (Figs. 11–13: swept / 200) | energy | Cell motility | 01b p.11 |
| χ(c,M) | 500 | energy/conc. | Chemotaxis at cell–ECM | 01b p.12 |
| χ(c,c) | 0 | energy/conc. | Chemotaxis at cell–cell (contact inhibition) | 01b p.12 |
| s | 0 | 1/conc. | Saturation | 01b p.12 |
| α | 10⁻³ | s⁻¹ | Secretion | 01b p.3 |
| ε | = α = 10⁻³ | s⁻¹ | Decay in ECM | 01b p.3 |
| D | 10⁻¹³ | m² s⁻¹ | Diffusion | 01b p.3 |
| Δt | 2 s, 15 steps/MCS | s | PDE | 01b p.12 |
| Δx | 2 µm | µm | Site | 01b p.11 |
| MCS | 30 s | s | — | 01b p.11 |
| Neighbourhood | up to 4th order (20) | — | Hamiltonian and copy (target uniform, source = 1 of 20 neighbours) | 01b p.11; `neighbours = 3` (sprout_extensionretraction_t50.par:18); ca.cpp:62, :389-397 |
| Boundary | fixed. 1-px frozen frame σ = −1 | — | — | 01b p.11; ca.cpp:97-105 |
| E0 / connectivity | none (`conn_diss = 0`) | energy | — | sprout_extensionretraction_t50.par:11 |
| Initial c | 0 | — | — | pde.cpp:104-106 |
| Field BC | absorbing c = 0 on the outer 1-px ring | — | — | pde.cpp:189-194, :270-285 |
| PDE scheme | per MCS: 15 × (forward-Euler secretion/decay, then FTCS 5-point diffusion), then the CPM sweep | — | — | vessel.cpp:86-94, :151-168; pde.cpp:178-219 |
| Relaxation | first 100 MCS without PDE (so without chemotaxis) — **not in paper** | MCS | — | sprout_extensionretraction_t50.par:40; vessel.cpp:86 |
| Initial cells (files) | sprout: 1 Eden blob (50 rounds) → 7 divisions = 128 cells on 200². denovo: 360 seeds × 10 Eden rounds on 200² | — | see D-1, D-2 | sprout_*.par:32-36; denovo_*.par:32-36 |
| Energy arithmetic | integer ΔH, each term truncated | — | — | ca.cpp:197-270 (D-7) |

**Derived (01b):**

| Quantity | Value | Derivation |
|---|---|---|
| Diffusion length L | √(10⁻¹³/10⁻³) = 10 µm = 5 px | 01b p.5 formula |
| L at D = 3×10⁻¹³ | 17.3 µm | matches 01b p.8 "(L>17.3 µm)" |
| Cell area | 50 × 4 µm² = 200 µm² | 01b p.11 |
| Area fraction (Fig. 2) | 1000×50 / 333² ≈ 0.45 | — |
| γ_c,M | 20 − 40/2 = 0 | 01b p.6 "equivalent to setting the surface tension … to zero" |

### 3.3 01b experiment table (per figure)

| Fig. | Setup | Readout | Source |
|---|---|---|---|
| 2A–C | 1000 cells, 333² seed, χ(c,c) = χ(c,M) (no CI), snapshots at 10, 1000, 10,000 MCS | islands | 01b p.4 |
| 2D | same with CI | network | 01b p.4 |
| 3A–C | sprouting without CI via length constraint, L = 22, 24, 32 µm | — | 01b p.5 |
| 3D–F | adhesion-driven, J(c,c) = 1, 5, 10 | — | 01b p.5 |
| 3G–I | D = 1, 2, 3 × 10⁻¹⁴ | — | 01b p.5 |
| 4 | cluster; CI vs. none (χcc/χcM = 1), 10 / 1000 / 10,000 MCS. Cluster size not stated in caption (Videos S4–S6: 256 cells) | — | 01b p.6, p.12–13 |
| 5 | 128 cells, 400 µm × 400 µm lattice, compactness at 10,000 MCS vs χcc/χcM; n = 10 | transition ≈ 0.5 | 01b p.5–6 |
| 6 | 128-cell clusters, trajectories. Displacement over 10 sims. Velocity with Δt = 300 MCS (≈2.5 h) | — | 01b p.6–7 |
| 7 | 128 cells, 200×200 px, C at 5000 MCS vs J(c,c) ∈ [0, 80] | — | 01b p.8 |
| 8 | same, vs χ(c,M) ∈ [0, 5000] | — | 01b p.8 |
| 9 | same, vs s ∈ [0, 0.25] | — | 01b p.8 |
| 10 | 128 cells @ 200×200 and 1024 cells @ 400×400 px: "1,024-cell clusters (dashed-dotted curve) on 400×400-pixel lattices (∼800 µm×800 µm)" (01b p.9, Fig. 10 caption; see A-10), vs D ∈ [~0, 5×10⁻¹³] | — | 01b p.9 |
| 11 | 128 cells, "400×400-pixel lattices (~400 µm×400 µm)" (see A-10), C at 5000 MCS vs T ∈ [0, 1000] step 10, 100 sims per T; ext-retr vs ext-only | — | 01b p.9 |
| 12 | 256 cells, 500×500 px, C(t) to 5000 MCS, T = 50 & 200 ext-retr, T = 200 ext-only, 100 sims | — | 01b p.10 |
| 13 | cumulative ΔH (H − H0) vs t, same runs | — | 01b p.10 |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence / correction |
|---|---|---|---|
| **Merks 2006** ||||
| 1 | H = ΣJ(1−δ) + λ_A(a−A)² + λ_L(l−L)² | CONFIRMED | Eq. 1 (01a p.47) + Eq. 4 (p.48). The paper's symbols are λ and λ_L |
| 2 | l = 4√(λ_max(I)/a) | CONFIRMED | 01a p.48: l_σ = 4√(λ_b,σ/a_σ). The paper notes a ~33% overestimate. I is defined in Eq. 5 (p.49) |
| 3 | J_cc = 40, J_cM = 20, J_cB = 100 (frozen border) | CONFIRMED | 01a p.48 |
| 4 | 2nd-order neighbourhood | CONFIRMED (for H) | "eight second-order neighbors" 01a p.47. The copy-target order is not stated separately |
| 5 | T = 50 | CONFIRMED | 01a p.48 |
| 6 | Dissipation threshold E0 | CONFIRMED (form; value NOT IN PAPER) | Eq. 3 p.48: P = exp(−(ΔE+E0)/T) for ΔE ≥ −E0. No value is given |
| 7 | Chemotaxis ΔH = −χ(c(x′) − c(x)), χ = 1000 | CONFIRMED (symbol differs) | Eq. 2 p.47: ΔH = γ(c(x) − c(x′)), γ = 1000. The paper's symbol is γ, not χ |
| 8 | Soft connectivity penalty > 2000 | CONFIRMED, with caveat | p.49 "we currently use E0 > 2000". The penalty reuses the symbol E0. Fig. 3 (p.47) describes accept/reject rules as if hard (A-3) |
| 9 | ∂c/∂t = D∇²c + α[cell] − ε[medium]c | CONFIRMED (semantics) | Eq. 6 p.49, but the printed δ usage is inverted (A-4) |
| 10 | D = 10⁻¹³ m²/s, α = ε = 1.8×10⁻⁴ s⁻¹ | CONFIRMED | 01a p.49 |
| 11 | 15 Euler steps/MCS, Δt = 2 s | CORRECTED (partly) | 15 steps, Δt = 2 s confirmed (p.49). "Euler" is NOT IN PAPER: it says only "a finite-difference scheme". *Code addendum:* TST uses forward Euler / FTCS (codebases/01b_.../TST0.1.3/pde.cpp:178-219; INSTALL "forward Euler"). This is a 2008-code value, assumed for 2006 |
| 12 | Δx = 2 µm | CONFIRMED | p.49; Fig. 4 caption p.48 |
| 13 | 1 MCS = 30 s | CONFIRMED | p.50 |
| 14 | 282 cells in 333² within 500² lattice | CONFIRMED | Fig. 4 caption p.48. The text on p.50 says "666 µm × 666 µm" (consistent) |
| 15 | Networks need L above threshold; λ_L = 0 → islands (Figs. 6/8) | CORRECTED | Fig. 6 (p.49) varies **L** (20–100 µm) with λ_L unchanged: 20 and 40 µm give islands, 60 µm and above give networks (threshold between 40 and 60 µm, read from Fig. 6a–c). **Fig. 8 varies L and A together at constant covered area and shows lacuna size does not depend on cell size (p.50); it is not a λ_L = 0 test.** "Networks do not form if we prevent cell elongation using an energy constraint that enforces cell isotropy (not shown)" (p.51). No figure shows λ_L = 0 islands for the standard parameters. Fig. 9a uses λ_L = 0 with *steep* gradients and **does** form networks |
| 16 | Lacuna count falls then plateaus (Fig. 5) | CONFIRMED | Fig. 5 p.48; text p.50 "initially drops quickly, with non-exponential dynamics, then slowly stabilizes". Note the caption/panel mislabel (A-5) |
| **Merks 2008** ||||
| 17 | J_cc = 40, J_cM = 20 | CONFIRMED | 01b p.11 |
| 18 | λ = 25, A = 50 | CONFIRMED | 01b p.11 |
| 19 | T = 50 | CONFIRMED | 01b p.11 (except Figs. 11–13) |
| 20 | χ_cM = 500, χ_cc = 0 | CONFIRMED | 01b p.12 |
| 21 | Saturating chemotaxis μΔc/(1+s\|Δc\|) | CORRECTED | Eq. 3 p.12: ΔH = −μ[c(x′)/(1+s·c(x′)) − c(x)/(1+s·c(x))]. Each concentration is saturated separately, there is no absolute value, and the sign is negative |
| 22 | Extension-only vs extension+retraction variants | CONFIRMED | Eq. 4 p.12; Figs. 11–13 |
| 23 | 4th-order (20) neighbourhood | CONFIRMED | 01b p.11 |
| 24 | 333² network / 200² sprouting | CONFIRMED (with exceptions) | 333² seed region for Fig. 2 (p.4). 200×200 for Figs. 7–10 (128 cells). But Fig. 11 caption says 400×400 px, Fig. 12 uses 500×500 (256 cells), Fig. 10 has 1024 cells on 400×400, and the Fig. 5 text gives "400 µm×400 µm" |
| 25 | 1000 cells | CONFIRMED | Fig. 2 setup, 01b p.4 |
| 26 | Compactness transition near χ_cc/χ_cM ≈ 0.5 | CONFIRMED | 01b p.6 "phase transition at (χ(c,c)/χ(c,M))≈0.5"; Fig. 5 |

**Tally (this file, 26 claims):** 23 CONFIRMED (several with caveats: #4, #6, #7, #8, #9, #24), 3 CORRECTED (#11 "Euler" not stated; #15 Fig. 6/8 misattribution; #21 saturation form), 0 wholly NOT IN PAPER.
Sub-items that are absent from the paper: the numerical E0 (#6) and the explicit Euler scheme (#11).

---

## 5. Validation targets

Tolerance policy: ensemble/statistical agreement, no bitwise parity. "Read from plot" values carry about ±5–10% digitisation error.

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-E1 | Standard Variant E forms a connected polygonal network from 282 dispersed cells that coarsens over 4→48 h (snapshots 4, 9, 12, 24, 48 h) | 01a Fig. 4 p.48 | Qualitative | A network (single dominant connected component of cells + ≥ several lacunae) at 12 h; coarser at 48 h |
| V-E2 | In-silico lacuna count vs time. Rapid rise to peak ≈ 80–90 at ~1–2 h, then non-exponential decay to ≈ 10 at 50 h. Read from plot: ≈ 40 @10 h, ≈ 22 @20 h, ≈ 15 @30 h, ≈ 10–12 @40–50 h. n = 10 | 01a Fig. 5 panel "a" (see A-5) p.48 | Quantitative (from plot) | Ensemble mean (n ≥ 10) within ±1 SD band of the paper curve at 10, 20, 30, 50 h; peak time < 5 h |
| V-E3 | In-silico branch points vs time. Peak ≈ 210–230 at ~1–2 h. ≈ 110 @10 h, ≈ 65 @20 h, ≈ 45 @30 h, ≈ 33 @50 h | 01a Fig. 5 panel "b" | Quantitative (from plot) | As V-E2 |
| V-E4 | Shape match to in vitro: lacunae 20 → 10.7 → 7.9 → 4.2 → 3.7 and branch points 73 → 43 → 34 → 21 → 21 at 4/9/12/24/48 h (n = 28; different field of view) | 01a Fig. 5 panels "c,d" | Quantitative, relative only | Normalised decay (value/value@4h) of the simulation within in-vitro error bars |
| V-E5 | Cell length sweep: L = 20, 40 µm give rounded islands; L ≥ 60 µm gives a network | 01a Fig. 6 p.49; p.50 | Qualitative | Island vs network classification matches per L (≥ 8/10 replicates) |
| V-E6 | Adhesion sweep J_c,c = 20 … 5 leaves the network unchanged; J_c,c = 1 gives slightly larger, more regular lacunae | 01a Fig. 7 p.49; p.50 | Qualitative | Network persists for all J_c,c; lacuna count at J_c,c = 1 ≤ standard |
| V-E7 | Lacuna size independent of cell size at constant covered area | 01a Fig. 8 p.50 | Qualitative ("not shown" metric) | Mean lacuna area across the 4 settings within ±25% |
| V-E8 | Alternative mechanisms (steep gradients / adhesion / contact inhibition) converge fast to polygons and show little or very rapid coarsening | 01a Figs. 9–10 p.50–51 | Qualitative | Lacuna count flat after the initial transient (Fig. 10) vs decaying standard |
| V-E9 | Mean and mode cell speed ≈ 5 µm/h, max ≈ 30 µm/h (at 30 s/MCS) | 01a p.50 | Quantitative (stated) | Ensemble mean within 2.5–10 µm/h. The speed-measurement interval is UNSPECIFIED |
| V-E10 | Elongated cells random-walk faster along the long axis | 01a Fig. 11 p.52 | Qualitative | MSD anisotropy ratio > 1 in the body frame |
| V-C1 | Without CI (χcc = χcM): 1000 cells form isolated round clusters by 10,000 MCS; with CI: a network | 01b Fig. 2 p.4 | Qualitative | Cluster count / connectivity classification |
| V-C2 | Cluster sprouts with CI; stays compact without CI at 10,000 MCS | 01b Fig. 4 p.6 | Qualitative | C(with CI) < C(without CI) − 0.3 |
| V-C3 | Compactness vs χcc/χcM at 10,000 MCS: C ≈ 0.35 ± 0.05 for ratio ≲ 0.45; steep rise between ≈ 0.5 and 0.6; C ≈ 0.9 for ratio ≳ 0.6. n = 10 | 01b Fig. 5 p.6 | Quantitative (from plot) | Transition midpoint within 0.45–0.65; plateau levels within ±0.07 |
| V-C4 | C vs J(c,c) at 5000 MCS. With CI: ≈ 0.3 for J_cc ≲ 40, rising to ≈ 0.85 at 80. Without CI: ≈ 0.35 at 0 → ≈ 0.83 by J_cc ≈ 15, plateau | 01b Fig. 7 p.8 | Quantitative (from plot) | Monotone trends; plateau/low levels within ±0.1 |
| V-C5 | C vs χ(c,M). With CI: ≈ 0.9 at 0, fast drop to ≈ 0.35 by ~500, ≈ 0.2 at 5000. Without CI: ≈ 0.95 → ≈ 0.7 | 01b Fig. 8 p.8 | Quantitative (from plot) | ±0.1 at χ = 0, 500, 2000, 5000 |
| V-C6 | Cord width: two cells at χcM = 500, one cell wide for χcM > 500 | 01b p.8 | Qualitative | Median cord width in cells |
| V-C7 | C vs s. With CI: ≈ 0.4 for s ≲ 0.08, rising to ≈ 0.95 by s ≈ 0.13. Without CI: ≈ 0.93–0.97 flat | 01b Fig. 9 p.8 | Quantitative (from plot) | Transition in s ∈ [0.07, 0.15] |
| V-C8 | C vs D. 1024-cell clusters sprout for D > 3×10⁻¹³ (L > 17.3 µm) while 128-cell clusters do not; longer L gives thicker cords | 01b p.8, Fig. 10 p.9 | Semi-quantitative | Qualitative sprout/no-sprout at D = 4×10⁻¹³ for both sizes |
| V-C9 | C vs T (100 sims per T). Ext-retr sprouts at T < 100, ext-only does not (C ≈ 1 → drop near T ≈ 100). Both sprout for 100 < T < 400. Break-up for T > 400 (C → ≈ 0.17 at T = 1000) | 01b p.9, Fig. 11 | Quantitative (from plot) | Ext-only C(T = 50) > 0.85; ext-retr C(T = 50) < 0.5; both < 0.3 at T = 800 |
| V-C10 | C(t) for 256 cells: ext-retr T = 50 drops fastest (≈ 0.97 → ≈ 0.4 at 5000 MCS); ext-only T = 200 slowest (≈ 0.5 at 5000). After 2500 MCS, rates equal | 01b Fig. 12 p.10 | Quantitative (from plot) | Ordering of the curves plus ±0.07 at 1000/5000 MCS |
| V-C11 | Cumulative ΔH: ext-retr negative (≈ −3×10⁸ at T = 50, ≈ −4×10⁸ at T = 200 by 5000 MCS); ext-only positive (≈ +1×10⁸) | 01b Fig. 13 p.10 | Quantitative (from plot) | Sign and order of magnitude only (depends on lattice size and exact ΔH bookkeeping). The code sums the integer ΔH of accepted copies, including the chemotaxis term and excluding E0 (§7.7, D-17) |
| V-C12 | Mean displacement over 165 h: CI ≈ 85 µm vs no-CI ≈ 42 µm. Velocity (Δt = 300 MCS) peak ≈ 5 µm/h at ~8 h with CI vs ≈ 2–3 µm/h without | 01b Fig. 6E–F p.7 | Quantitative (from plot) | Ratio CI/no-CI displacement at 160 h in [1.5, 2.5] |

Compactness C = A_cluster / A_hull, where A_hull is the convex-hull area (01b p.5). The treatment of multi-fragment clusters is UNSPECIFIED in the paper (A-14). The released `Compactness()` uses all cell sites and the hull of their pixel centres (§7.7, D-18).

---

## 6. Required general features

| ID | Needed? | Use in this model |
|---|---|---|
| G1 @transition/@create/@retire + Bernoulli | No | No division, death or state change |
| **G2** shape descriptors in energies | **Yes (Variant E)** | λ_L (l − L)² with l = 4√(λ_max(I)/a). This needs an incrementally maintained second-moment tensor per cell (Eq. 5) and its largest eigenvalue inside ΔH |
| **G3** contact-scope direction/position | **Yes (Variant CI)** | The chemotaxis coefficient depends on the **interface type** (cell–ECM vs cell–cell) of the copy. It also needs the source/target **roles** (Eq. 4 gates on the source site being an EC) and field values at both source and target positions. No lagged vector variables are needed |
| **G4** generalized connectivity | **Yes (Variant E)** | Local cyclic-neighbour collision count (Fig. 3 rules) used as a **soft penalty** (≥ 2000) in ΔH, with the option of a hard reject. Variant CI does not mention connectivity |
| **G5** field BCs + solver | **Yes** | Reaction–diffusion field on the CPM grid (same resolution, not coarse). Explicit time stepping with 15 sub-steps per MCS and Δt = 2 s. The BC must be declarable because the paper does not specify it. The SteadyState solver is not required |
| **G6** per-cell secrete/uptake | **Yes** | Secretion α at every cell site. Decay ε only at medium sites (site-type-dependent linear sink). Not "conservative per-cell" but per-site source/sink masks |
| G7 @convert | No | — |
| **G8** pluggable proposal law | **Yes** | (a) The dissipation-threshold acceptance P = exp(−(ΔH+E0)/T) (01a Eq. 3) vs plain Metropolis (01b). (b) Per-copy ΔH extras (chemotaxis) that are not part of H |
| G9 per-cell component protocol | No | — |
| **G10** cluster-scope quantities | **Yes (observables)** | Cluster area and convex-hull area for compactness. Connected components of the cell mask |
| G11 ordered relationships / angle energies | No | — |
| **G12** observables library | **Yes** | Compactness (convex hull). Morphometry pipeline (01a p.46): top-hat (disk r = 7), threshold min + (max − min)/10, remove patches < 50 px, closing (disk r = 10), skeletonise, 15 pruning steps for simulations, nodes = skeleton pixels with ≥ 3 first-order neighbours, lacunae = connected components of the inverted skeleton. Also centre-of-mass trajectories, displacement, and velocity V = (x(t+Δt) − x(t−Δt))/2Δt |
| **G13** initial layout generators | **Yes** | Random scatter of N cells in a centred sub-square of a larger lattice. A round cluster of N cells (disc packing) |
| **G14 (new)** saturating/receptor-occupancy chemotaxis law | Yes, *possibly* covered by G3+expressions | ΔH uses f(c) = c/(1 + s c) evaluated at source and target separately. **Justification:** if the core only offers a linear "χ Δc" chemotaxis primitive, Eq. 3 cannot be expressed. It requires user-expression chemotaxis on f(c(x′)) − f(c(x)). If G3 already allows arbitrary expressions of field values at source and target, G14 folds into G3 |
| **G15 (new)** frozen/immutable border sites with their own J | Yes | "frozen pixels of type B" that are never copied into or out of, with a contact energy J_c,B. **Justification:** this is distinct from lattice BCs (it adds energy) and from medium. It may already exist as a "wall" cell kind; if so, map to it |

---

## 7. Merks 2008 released code and parameter files

**Sources (now on disk, under `docs/references/`):**
- **Dataset S1** (01b parameter files): `supplementary/01b_Merks2008_DatasetS1_parameter-files/ParameterFiles/`. It has 12 `.par` files (`{denovo,sprout}_{extensionretraction,extensiononly}_{t50,t200,t50_vecadko}.par`), plus `J.dat`, `default.ctb` (colour table only), `README` and `index.html`. Cited as (supplementary/01b_.../<file>:line).
- **Protocol S1** (Tissue Simulation Toolkit v0.1.3 C++ source): `codebases/01b_Merks2008_TissueSimulationToolkit-v0.1.3/TST0.1.3/`. Cited as (codebases/01b_.../TST0.1.3/<file>:line). The files that matter are `vessel.cpp` (main loop, secretion), `ca.cpp` (CPM), `cell.h`/`cell.cpp` (J table, moments, length), `pde.cpp` (diffusion), `dish.cpp` (set-up) and `parameter.cpp` (defaults). The build compiles `vessel.cpp` as the main file (codebases/01b_.../TST0.1.3/CellularPotts2.pro:11).

All statements below were read from source. None were checked by compiling or running TST. The only exception is the Eden-growth area estimates in §7.6, which come from a quick independent Python re-implementation of `GrowInCells` (2 seeds). Treat them as estimates.

### 7.1 Dataset S1: the 2008 parameter set (all 12 files)

All 12 files share every value except `T`, `extensiononly`, `vecadherinknockout` and the initial-condition block (verified by `diff` against `sprout_extensionretraction_t50.par`). Line numbers are identical across files.

| Key (file line) | Value | Meaning in code | Paper symbol / 01b value |
|---|---|---|---|
| `T` (:5) | 50 or 200 | Metropolis temperature | T = 50; 200 in Figs. 11–13 ✓ |
| `target_area` (:6) | 50 | A for every cell (reset for all cells after set-up, codebases/01b_.../TST0.1.3/dish.cpp:54-57) | A = 50 ✓ |
| `target_length` (:7) | 0 | L | no length term ✓ |
| `lambda` (:8) | 25 | λ (area) | 25 ✓ |
| `lambda2` (:9) | 0 | λ_L | 0 ✓ |
| `Jtable` (:10) | `J.dat` | 2 types. J(M,M) = 0, J(c,M) = 20, J(c,c) = 40 (supplementary/01b_.../J.dat:1-3). The format is lower-triangular, starting with row 0 (codebases/01b_.../TST0.1.3/cell.cpp:142-175) | 40 / 20 ✓ |
| `conn_diss` (:11) | 0 | Connectivity penalty, also the acceptance offset E0 (§7.3) | no connectivity, no E0 ✓ |
| `vecadherinknockout` (:12) | false; true in `*_vecadko` | false: chemotaxis only when source or target is medium. true: chemotaxis at every copy | χ(c,c) = 0 vs χ(c,c) = χ(c,M) |
| `extensiononly` (:13) | false / true | Eq. 4 gate | Eq. 3 vs Eq. 4 ✓ |
| `chemotaxis` (:14) | 500 | χ(c,M) | 500 ✓ |
| `border_energy` (:15) | 100 | J(c,B) | 100 ✓ |
| `neighbours` (:18) | 3 | **Index** into `nbh_level = {0,4,8,20,24}`, so 3 → **20 sites** (codebases/01b_.../TST0.1.3/ca.cpp:62, :74-75) | "twenty, first- to fourth-nearest" ✓ |
| `periodic_boundaries` (:19) | false | fixed border | ✓ |
| `n_chem` (:22) | 1 | one field | — |
| `diff_coeff` (:23) | 1e-13 | D (m² s⁻¹) | ✓ |
| `decay_rate` (:24) | 1e-3 | ε (s⁻¹) | ✓ |
| `secr_rate` (:25) | 1e-3 | α (s⁻¹) | ✓ |
| `saturation` (:26) | 0. | s | ✓ |
| `dt` (:27) | 2. | Δt (s) | ✓ |
| `dx` (:28) | 2e-6 | Δx (m) | ✓ |
| `pde_its` (:29) | 15 | PDE sub-steps per MCS | ✓ |
| `n_init_cells` (:32) | sprout 1 / denovo 360 | seed count | see D-1, D-2 |
| `size_init_cells` (:33) | sprout 50 / denovo 10 | **number of Eden-growth rounds**, not an area (§7.6) | — |
| `sizex`, `sizey` (:34-35) | 200 × 200 | lattice including the 1-px frozen frame | see D-1, D-2 |
| `divisions` (:36) | sprout 7 / denovo 0 | Blob halved 7× → **128 cells** | Figs. 5–11 (128 cells) |
| `mcs` (:37) | 20001 | run length | see D-4 |
| `rseed` (:38) | -1 | time-based seed | — |
| `subfield` (:39) | 1 | seed region = whole interior | see D-1 |
| `relaxation` (:40) | 100 | MCS with no secretion, diffusion or (effective) chemotaxis | **not in paper** (D-5) |

The per-file differences are as follows. `denovo_*` has n_init_cells = 360, size_init_cells = 10, divisions = 0 (supplementary/01b_.../denovo_extensionretraction_t50.par:32-36). `*_t200` has T = 200 (:5). `*_extensiononly_*` has extensiononly = true (:13). `*_vecadko` has vecadherinknockout = true (:12). `index.html` labels vecadko as "no contact-inhibition" (supplementary/01b_.../index.html:44, :50, :58, :64), but those four links point at the non-vecadko file (a link bug in the HTML only; the `_vecadko.par` files exist).

### 7.2 Hamiltonian and ΔH (codebases/01b_.../TST0.1.3/ca.cpp:195-304)

- **Copy direction.** `DeltaH(x,y,xp,yp)`: (x,y) is the **target**, whose current owner is `sxy`, the "retracting" cell. (xp,yp) is the **source**, `sxyp`, the "expanding" cell (comment at ca.cpp:266, :281). `ConvertSpin` sets σ(x,y) ← σ(xp,yp) (ca.cpp:335).
- **Adhesion.** The sum runs over the `n_nb` neighbours of the **target** (ca.cpp:206-243): ΔH += J(τ(sxyp), τ(nb)) − J(τ(sxy), τ(nb)). J = 0 for the same σ (cell.cpp:178-186). The **energy neighbourhood equals the proposal neighbourhood** (both `n_nb`): 20 for 2008 files, 8 for `neighbours = 2`.
- **Border in the adhesion sum.** Any neighbour with x ≤ 0, y ≤ 0, x ≥ sizex−1 or y ≥ sizey−1 counts as border, including off-lattice sites reached by the distance-2 stencil (ca.cpp:228-230). Its contribution is `border_energy` for a non-medium spin and **0 for medium** (ca.cpp:236-238). So **J(M,B) = 0**.
- **Area.** The exact ΔH of λ(a−A)² with no ½ (ca.cpp:249-260): λ(1 − 2(a−A)) for the losing cell and λ(1 + 2(a−A)) for the gaining cell, with the two-cell form combined.
- **Chemotaxis** (ca.cpp:264-274). This block is added when `vecadherinknockout || sxyp==0 || sxy==0`, i.e. when the copy is between a cell and medium (either direction), or at every copy for the no-CI knockout. It is skipped if `extensiononly && sxyp==0` (the source is medium, i.e. a retraction). The term is ΔH −= (int)(χ·(sat(c(target)) − sat(c(source)))), with sat(c) = c/(s·c + 1) (ca.cpp:188-193). This is exactly 01b Eq. 3/4 with x′ = target. It is also the sign of 01a Eq. 2 (γ(c(x) − c(x′)), x = source).
- **Length** (ca.cpp:277-301): λ_L[(l_new − L)² − (l_old − L)²] for the gaining and/or losing cell. The new lengths come from the incrementally updated raw moments (cell.h:346-441). **Length estimator** (cell.h:397-421): I_xx = Σy² − (Σy)²/n, I_yy = Σx² − (Σx)²/n, I_xy = −Σxy + ΣxΣy/n. λ_b = largest eigenvalue, and **l = 4√(λ_b/n)**. This equals 01a p.48 and Eq. 5. The comment at cell.h:410-419 records that the Zajac 2003 formula (2√λ_b) was corrected to divide by mass.
- **Integer energies.** DH is an `int`. The area, chemotaxis and length contributions are each cast with `(int)` (truncation toward zero) before summing (ca.cpp:250, :270, :284). A chemotactic |χ Δsat(c)| < 1 therefore contributes 0.

### 7.3 Monte Carlo step, acceptance, connectivity, E0 (codebases/01b_.../TST0.1.3/ca.cpp:308-459, :1166-1226)

- **Attempts per MCS**: `(sizex−2)(sizey−2)`, i.e. the number of **interior** sites, not all sites (ca.cpp:385).
- **Proposal** (ca.cpp:389-397). The **target** is drawn uniformly from the interior **with replacement**. The **source** is a uniformly chosen index 1..n_nb from the neighbour table (ca.cpp:59-60). If the source is border (−1) the attempt is skipped (ca.cpp:433). If source and target have the same σ the attempt is consumed with no energy evaluation (ca.cpp:437). Both skipped and same-σ picks **count toward the loop**.
- **Neighbour table** (ca.cpp:59-62): indices 1–4 are 1st-order, 5–8 diagonals, 9–12 distance 2 and 13–20 distance √5. `neighbours = 4` (24) repeats the distance-2 sites at 21–24 instead of adding (±2,±2), which is a latent bug. It is unused by 2006/2008.
- **Acceptance** (`CopyvProb`, ca.cpp:342-356). With s = H_diss: accept with P = 1 if ΔH ≤ −s, else with P = exp(−(ΔH + s)/T). A lookup table of 1024 entries is used (sticky.h:31; ca.cpp:358-362), with on-the-fly exp beyond it. This is identical to 01a Eq. 3, since exp(0) = 1 at the boundary.
- **E0 is the connectivity penalty.** H_diss = `conn_diss` if `ConnectivityPreservedP(x,y)` is false, else 0 (ca.cpp:442-443). **There is no separate dissipation constant anywhere in TST.** The E0 of 01a Eq. 3 and the "E0 > 2000" connectivity penalty of 01a p.49 are the **same variable**. It is 0 for connectivity-preserving copies and `conn_diss` for connectivity-breaking ones. It is a soft penalty that enters as a threshold shift, not as an addition to ΔH. It is not included in the returned SumDH (ca.cpp:450).
- **Connectivity test** (ca.cpp:1166-1226). It is evaluated on the **target** site for its **current owner** (the losing cell). It is never evaluated for medium (returns true, :1176). It uses the fixed **8-site cyclic ring** starting at (−1,0), whatever `neighbours` is. `n_borders` counts the ring-adjacent pairs where exactly one member equals σ(target). The copy is flagged as connectivity-breaking iff n_borders > 2 **and** (more than 2 distinct non-zero spins in the ring, counting the target's own σ and the border state −1, **or** any ring site is medium). With n_borders > 2 it therefore passes only when no ring site is medium and at most one other non-medium spin is present. This matches 01a Fig. 3 (c)/(d). The gaining cell's connectivity is **not** checked. With 20-neighbour proposals (source up to √5 away) a cell can therefore gain a disconnected pixel. That is irrelevant in 2008 (conn_diss = 0) and cannot happen with 8-neighbour proposals.
- **Cell loss.** A cell whose area reaches 0 is marked apoptosed (ca.cpp:324-327). This is not mentioned in either paper.

### 7.4 PDE (codebases/01b_.../TST0.1.3/vessel.cpp:86-94, :151-168; pde.cpp:178-285)

- **Per MCS order.** If MCS index ≥ `relaxation`, run 15 × {`Secrete` (one Δt), then `Diffuse(1)`}. **Then** the CPM sweep `AmoebaeMove` (vessel.cpp:86-94). So the PDE runs **before** the CPM each MCS, and not at all during the first `relaxation` MCS.
- **Secretion/decay** (vessel.cpp:151-168). This is operator-split forward Euler over all sites: c += α·Δt where σ ≠ 0, and c −= ε·Δt·c where σ = 0. The σ = −1 frame counts as "inside cells", but is zeroed by the BC before diffusion.
- **Diffusion** (pde.cpp:178-219). Explicit FTCS with a **5-point** Laplacian (1st-order neighbours only, not the 20-site CPM stencil) and double buffering: c′ = c + D·Δt/Δx²·(Σ₄c − 4c). "Cells are transparent" (pde.cpp:180): diffusion runs everywhere. D·Δt/Δx² = 0.05.
- **Field BC** (pde.cpp:189-194, :269-285). With `periodic_boundaries = false` the scheme applies **absorbing (Dirichlet c = 0) boundaries on the outer 1-px ring**, reset before every sub-step. No-flux exists but is commented out.
- **Initial c = 0** (pde.cpp:104-106). The PDE grid equals the CPM grid (dish.cpp:47-49).
- The PDE clock (`thetime`) advances Δt per sub-step (pde.cpp:216), so after relaxation 1 MCS = 30 s of field time.

### 7.5 Lattice and border

- The lattice is square, `sizex × sizey` including a **1-px frozen frame** with σ = −1 (ca.cpp:97-105; re-applied at :1048-1066). The frame is never selected as a target (targets are drawn in [1, size−2]) and never copied from (:433). J(c,B) = `border_energy`, J(M,B) = 0 (§7.2). The PDE's absorbing ring coincides with the frame.

### 7.6 Initial condition (codebases/01b_.../TST0.1.3/vessel.cpp:47-69; ca.cpp:663-706, :901-1163; dish.cpp:43-60)

- **`GrowInCells`** (ca.cpp:1071-1163). For n > 1: n seeds at uniform random interior positions within a centred sub-square of side (size−2)/subfield. Positions are drawn **with replacement**, so coinciding seeds merge and yield < n cells. For n = 1: a single seed at (sizex/2, sizey/2). This is followed by `size_init_cells` rounds of **synchronous Eden growth**: every medium site copies a uniformly chosen 8-neighbour if that neighbour belongs to a newly seeded cell.
- **`DivideCells`** (ca.cpp:901-1002). Each cell is split by the line through its centroid perpendicular to its long axis, so `divisions = 7` turns one blob into 128 cells. After `Init`, all target areas are reset to `target_area` (dish.cpp:54-57).
- **Estimated resulting geometry** (Python re-implementation, not TST itself; 2 seeds):
  - **denovo:** 354–359 cells of ≈ 47–48 px, ≈ 17,000 px total on a 198² interior. Area fraction ≈ 0.43 (target: 360 × 50 / 198² ≈ 0.46).
  - **sprout:** one Eden blob of ≈ 1,800–2,000 px split into 128 cells of ≈ 15 px. These are far below A = 50 and inflate to ≈ 6,400 px during the 100 relaxation MCS.
- **Relaxation.** For the first 100 MCS the field stays at 0, so chemotaxis ΔH = 0 and cells relax under adhesion and area only.

### 7.7 Observables in the release

- **`Compactness()`** (ca.cpp:1376-1448) computes C = (Σ over all cells of area) / (convex-hull area). The hull is taken over the centres of **all** non-medium interior sites, using Andrew's monotone chain (hull.cpp) with a shoelace area. It is **not called** anywhere in `vessel.cpp`, so the Figs. 5–13 analysis scripts are **not** in the release.
- `AmoebaeMove` returns SumDH, the sum of the integer ΔH of accepted copies (ca.cpp:450). This includes chemotaxis and excludes H_diss. `vessel.cpp:94` discards it. Fig. 13's "H − H0" was presumably this accumulated quantity. It is **not** a state function, because it includes the chemotaxis ΔH, which is not part of H.

### 7.8 TST defaults and non-2008 parameter files — transfer to Merks 2006

TST 0.1.3's hard-coded defaults (codebases/01b_.../TST0.1.3/parameter.cpp:36-72) and `default.par` are a Variant-E parameter set. Four shipped files say in their header that they are "Cf. Fig. 4 of Merks et al. 2006, Dev. Biol. on small field (200x200)" (codebases/01b_.../TST0.1.3/longcells.par:1-3; chemotaxis.par:1-3; roundcells.par:1-3; adhesion.par:1-3). `roundcellsko.par:1` says "Parameter file for Fig. 4 in Merks et al, Dev. Biol. 289 (2006)". These are the strongest evidence available for 01a, but they ship with the **2008** release. They are therefore labelled **"2008-code value, assumed for 2006"** everywhere in this spec.

| Quantity | `longcells.par` (2006 Fig. 4 "small field") | `default.par` / parameter.cpp defaults | 01a paper | Transfer verdict |
|---|---|---|---|---|
| T | 50 (:6) | 50 | 50 | agrees |
| A (px) | 100 (:7) | 100 | UNSPEC (inferred 100) | 2008-code value, assumed for 2006. Confirms the §3.1 inference |
| L (px) | **60** (:8) = 120 µm | 60 | "about 100 µm" = 50 px | 2008-code value, assumed for 2006. **Conflicts** with the paper text (D-12) |
| λ | 50 (:9) | 50 | UNSPEC | 2008-code value, assumed for 2006 |
| λ_L | 5.0 (:10) | 5.0 | UNSPEC | 2008-code value, assumed for 2006 |
| J | `J.dat`: 40 / 20 / M–M 0 | same | 40 / 20 | agrees |
| J(M,B) | 0 (code) | 0 | UNSPEC | 2008-code value, assumed for 2006 |
| conn_diss (E0) | **5000** (:12) | **2000** (default.par:8) | "E0 > 2000" | 2008-code value, assumed for 2006. The two files disagree (D-13) |
| Dissipation E0 for non-breaking copies | 0 (no such parameter exists) | 0 | UNSPEC | 2008-code value, assumed for 2006 (§7.3) |
| chemotaxis scope | vecadherinknockout = true (:13) → all copies | true | all copies (A-7) | agrees |
| γ / χ | 1000 (:14) | 1000 | 1000 | agrees |
| J(c,B) | 100 | 100 | 100 | agrees |
| neighbours | 2 (:18) → 8 for **both** energy and proposal | 2 | 8 for H; proposal UNSPEC | 2008-code value, assumed for 2006. The comment "do not change … for 'long' cells (lambda2>0)" (:17) ties the 8-neighbourhood to the length constraint |
| α = ε | 1.8e-4 (:24-25) | 1.8e-4 | 1.8e-4 | agrees |
| D, Δt, Δx, pde_its | 1e-13, 2, 2e-6, 15 | same | same | agrees |
| PDE scheme, BC, c₀, order | FTCS 5-pt, absorbing, 0, PDE before CPM | same code | UNSPEC | 2008-code value, assumed for 2006 |
| Initial cells | 100 cells, 10 Eden rounds, 200², subfield 1, relaxation 0 (:32-40) | same | 282 cells in 333² of 500² | **The paper set-up is not in the files**. For 01a, keep the paper's 282/333²/500² |
| s | 0 | 0 | — | n/a |

Other shipped files:
- `roundcells.par`: L = 10, λ_L = 5.0 (:8, :10). 01a Fig. 9a/c round controls say λ_L = **50** (D-14).
- `adhesion.par`: `adhesiveJ.dat` J(c,c) = 1, λ_L = 0, L = 10, α = ε = 1e-4, 100 cells (:7-33). 01a Fig. 9b adhesion reference: 1000 cells, α = 2.5e-3, ε = 1.25e-3 (D-15).
- `angiogenesis.par`: A = 50, L = 10, λ = 50, λ_L = 50, α = 2.5e-3, ε = 1.25e-3, 1 blob and 6 divisions, relaxation 100. It is labelled for Merks & Glazier 2006 *Nonlinearity* (angiogenesis.par:1), not for 01a/01b.

### 7.9 Paper-vs-code discrepancies (complete list)

| # | Topic | Paper | Code / Dataset S1 | Impact |
|---|---|---|---|---|
| D-1 | 01b Fig. 2 de novo set-up | 1000 ECs of ~200 µm² over a 333² seed region inside a larger lattice (01b p.4) | 360 seeds (≤ 360 cells) × 10 Eden rounds (≈ 47 px) on **200 × 200, subfield = 1** (supplementary/01b_.../denovo_extensionretraction_t50.par:32-39). `index.html:39` says "as in Figure 2" | About the same area fraction (≈ 0.45), but a 2.8× smaller domain. Use the paper geometry for Fig. 2 validation. The files give a density-matched smaller variant |
| D-2 | Sprouting set-up | Fig. 4 unspecified (Videos S4–S6: 256 cells). Fig. 12: 256 cells on 500² | 128 cells (1 blob, 7 divisions) on 200² in **all** sprout files (sprout_*.par:32-36). `index.html` claims "as in Figs. 4-13" | Matches Figs. 5–11 (128 cells, 200²). **No file for Fig. 12/13 (256 cells, 500²)** or the 1024-cell Fig. 10 runs; those need divisions = 8 and sizex = sizey = 500 (inferred) |
| D-3 | χ(c,c)/χ(c,M) sweeps (Figs. 4, 5, 7–9 no-CI curves) | continuous ratio 0…1 | Only a boolean: χ(c,c) ∈ {0, χ(c,M)} (ca.cpp:264) | The Fig. 5 ratio sweep **cannot be run** with the released code. The authors' sweep code is not released |
| D-4 | Run length | 10,000 MCS (Figs. 2, 4, 5); 5000 (Figs. 7–12) | `mcs = 20001` (:37) | Harmless; truncate |
| D-5 | Relaxation phase | not mentioned | 100 MCS with no secretion or diffusion at the start (:40; vessel.cpp:86) | MCS 0 in the paper is presumably MCS 100 of the code, or the paper's clock includes it. **STILL OPEN** which |
| D-6 | MC attempts | N = number of lattice sites (01b p.11; 01a p.47) | (sizex−2)(sizey−2) interior sites (ca.cpp:385) | ~2% at 200²; negligible |
| D-7 | Energy arithmetic | real-valued ΔH | integer ΔH, each term `(int)`-truncated (ca.cpp:250-270) | Small chemotactic differences are silently dropped (|χΔsat c| < 1 → 0). Our implementation will use Float ΔH (performance-over-exactness policy); expect a small, statistically benign deviation |
| D-8 | Proposal wording | 01b p.11 draws the source first, then says the source comes from the 20 neighbours (A-8) | target uniform, source = random one of n_nb neighbours (ca.cpp:389-397) | Same ordered-pair distribution away from the border |
| D-9 | Neighbourhood parameter name | "fourth-order" | `neighbours = 3` (index into {0,4,8,20,24}) | Naming only; 20 sites as stated |
| D-10 | PDE scheme and BC | "finite-difference scheme" (01a p.49); BC unstated | forward-Euler FTCS, 5-point, operator-split secretion/decay, absorbing c = 0 ring, c₀ = 0, PDE before CPM (§7.4) | Fills UNSPECIFIED; not a contradiction. The absorbing BC depresses c near the edge, which matters for de novo on 200² |
| D-11 | Cell deletion | "ECs do not divide or grow" (01b p.11); no death | cells reaching area 0 are marked apoptosed (ca.cpp:324-327) | Rare with λ = 25, A = 50 |
| D-12 | 01a target length | "about 100 µm" (01a p.50), i.e. 50 px | L = 60 px = 120 µm in all "Fig. 4 of Merks 2006" files and defaults (longcells.par:8; parameter.cpp:38) | 2006 fidelity choice: paper 50 px vs code 60 px. **STILL OPEN**; the paper text takes precedence for 01a unless the authors confirm |
| D-13 | 01a connectivity penalty | "E0 > 2000" (01a p.49) | 2000 (default.par:8; parameter.cpp:42); 5000 (longcells.par:12, tumor.par:12) | Both satisfy "≥ 2000"; which was used for Fig. 4 is **STILL OPEN** |
| D-14 | 01a round-cell controls | L = 10, λ_L = 50 (01a Fig. 9a/c p.50) | L = 10, λ_L = 5.0 (roundcells.par:8-10) | Use the paper value for 01a validation |
| D-15 | 01a adhesion reference (Fig. 9b) | 1000 cells, α = 2.5e-3, ε = 1.25e-3, J(c,c) = 1 | 100 cells, α = ε = 1e-4, J(c,c) = 1 (adhesion.par:24-32; adhesiveJ.dat) | Use the paper value |
| D-16 | 01a Fig. 4 geometry | 282 cells, 333² in 500² | 100 cells, 200² ("small field") in all 2006-labelled files | Files are a demo, not the published run |
| D-17 | Fig. 13 "H − H0" | plotted as an energy difference | code accumulates accepted ΔH including the chemotaxis term (ca.cpp:450) and discards it in vessel.cpp:94 | V-C11 must define the bookkeeping explicitly (see §5) |
| D-18 | Compactness | C = A_cluster/A_hull (01b p.5) | `Compactness()` uses all cell sites, not the largest cluster; hull over pixel centres (ca.cpp:1376-1448); never called | Resolves the hull convention; the paper-figure analysis code is absent |
| D-19 | Dataset S1 `index.html` | "no contact-inhibition" links | Point at the non-vecadko files (index.html:44, :50, :58, :64) | Documentation bug only |

---

## 8. Ambiguities and open questions

Status legend: **RESOLVED (2008)** means settled for Variant CI by the released code or Dataset S1. **RESOLVED-by-assumption (2006)** means that for 01a only a 2008-code value exists, labelled "2008-code value, assumed for 2006". **STILL OPEN** means neither papers nor release settle it. Abbreviations: codebases/01b_.../TST0.1.3/ = Protocol S1 source; supplementary/01b_.../ = Dataset S1 (full paths in §7).

- **A-1 (01a unspecified core parameters).** λ (area strength), A (target area), λ_L (length strength), dissipation E0, J_M,B, initial concentration, field BC and PDE scheme are all absent from 01a's main text. A ≈ 100 px and L ≈ 50 px can only be *inferred* (§3.1). → **RESOLVED-by-assumption (2006)** for λ = 50, A = 100, λ_L = 5.0, J(M,B) = 0, c₀ = 0, absorbing BC and FTCS. These are the 2008-code values, assumed for 2006, from the files headed "Cf. Fig. 4 of Merks et al. 2006" (codebases/01b_.../TST0.1.3/longcells.par:1-40; parameter.cpp:36-72), §7.8. A = 100 matches the §3.1 inference. **STILL OPEN:** L. The code uses 60 px = 120 µm; the paper says about 100 µm = 50 px (D-12). Checked 2026-09-30: the PMC manuscript repeats "about 100 μm" (01a-PMC); 01c p.11 (step 14) recommends "target_length = 60 (L = 120 µm, if dx=2.0e-6)" as "a good value to start with", citing 01a for the length constraint, but does not say it is the 01a value. The 01a supplementary methods could not be located (§1).
- **A-2 (dissipation E0 value).** → **RESOLVED-by-assumption (2006).** TST has no general dissipation constant. The only acceptance offset is H_diss = `conn_diss` for connectivity-breaking copies, and 0 otherwise (codebases/01b_.../TST0.1.3/ca.cpp:442-448, :342-356). So E0 = 0 for all ordinary copies (2008-code value, assumed for 2006). **RESOLVED (2008):** conn_diss = 0, so plain Metropolis (supplementary/01b_.../sprout_extensionretraction_t50.par:11).
- **A-3 (connectivity: hard or soft; symbol clash).** → **RESOLVED (code), assumed for 2006.** The dissipation E0 and the connectivity penalty are one variable. It is soft: it enters as a threshold shift, P = exp(−(ΔH + E0)/T) with P = 1 if ΔH ≤ −E0 (ca.cpp:342-356, :442-448). The test uses the fixed 8-site cyclic ring (ca.cpp:1170-1173). It is evaluated only for the **losing** (current-owner) cell at the target site, never for medium or for the gaining cell (ca.cpp:1175-1176). Value: 2000 (default.par:8) or 5000 (longcells.par:12). **STILL OPEN:** which of those two was used for 01a Fig. 4 (D-13).
- **A-4 (Eq. 6 δ inversion).** The implementation follows the prose. → **RESOLVED (code):** c += α·Δt where σ ≠ 0, and c −= ε·Δt·c where σ = 0 (codebases/01b_.../TST0.1.3/vessel.cpp:155-166). This confirms the prose reading.
- **A-5 (01a Fig. 5 caption vs panels).** The caption is wrong; the text and plot style agree. Validation uses (a,b) as in silico. **STILL OPEN** (paper-internal; the code does not bear on it). The reading used here stands.
- **A-6 (01a Fig. 10 caption cross-references).** "(compare Fig. 7a)" almost certainly means Fig. 9a–c. **STILL OPEN** (paper-internal).
- **A-7 (chemotaxis scope in 01a).** → **RESOLVED-by-assumption (2006).** All 2006-labelled files set `vecadherinknockout = true` (longcells.par:13; default.par:9). This applies chemotaxis at every copy, including cell→cell and ECM→cell retractions (ca.cpp:264-274). 2008-code value, assumed for 2006. It agrees with the literal reading of Eq. 2.
- **A-8 (01b source/target neighbourhood wording).** → **RESOLVED (2008).** The target is drawn uniformly (with replacement) from interior sites. The source is a uniformly chosen one of the 20 neighbours of the target. The same 20-site set is used for the adhesion ΔH (ca.cpp:206, :389-397; `neighbours = 3` → 20, ca.cpp:62). For 01a: 8 for both proposal and energy (`neighbours = 2`, longcells.par:18), 2008-code value, assumed for 2006.
- **A-9 (01b enclosing lattice for Fig. 2).** **STILL OPEN.** Dataset S1's de novo files do not reproduce Fig. 2's geometry. They use 360 cells on a 200² lattice with no enclosing margin (subfield = 1) (supplementary/01b_.../denovo_extensionretraction_t50.par:32-39; D-1). 500 × 500 remains the likely reading.
- **A-10 (01b lattice sizes inconsistent).** → **Partly RESOLVED (2008).** All sprout files use 200 × 200 px with 128 cells (sprout_*.par:32-36). This supports "400 µm × 400 µm = 200 × 200 px" for Figs. 5–11, so the Fig. 11 caption's "400×400-pixel" is the error. **RESOLVED (paper) for Fig. 10's 1024-cell runs:** the Fig. 10 caption reads "1,024-cell clusters (dashed-dotted curve) on 400×400-pixel lattices (∼800 µm×800 µm)" (Merks et al. 2008, PLoS Comput Biol 4:e1000163, p.9), i.e. 400 × 400 px at 2 µm/px. **STILL OPEN** only in that no parameter files exist for Fig. 10's 1024-cell runs or Fig. 12 (256 cells, 500²) (D-2).
- **A-11 (01b Fig. 11 legend vs caption).** The legend is correct and the caption is wrong. **STILL OPEN** (figure-internal). The reading is unchanged and consistent with the code semantics (extension-only skips retraction chemotaxis, ca.cpp:269).
- **A-12 (01b text typo).** "100<T>400" means 100 < T < 400. **STILL OPEN** (paper-internal; trivially read as stated).
- **A-13 (μ assignment in 01b Eq. 3).** → **RESOLVED (2008).** Interface = the (source, target) pair of the copy. Chemotaxis applies iff source or target is medium (or always, if the vecadko flag is set). So ECM→cell retractions do contribute with χ(c,M) in extension–retraction mode, and are skipped in extension-only mode (ca.cpp:264-274).
- **A-14 (compactness definition details).** → **Partly RESOLVED (2008).** The released `Compactness()` uses **all** cell sites (no largest-component selection), the convex hull of pixel centres (Andrew's monotone chain) and the sum of cell areas (ca.cpp:1376-1448). **STILL OPEN** whether the paper figures used this function, since it is never called in `vessel.cpp` and the analysis code is not released (D-18).
- **A-15 (initial seeding).** → **RESOLVED (2008 files).** Random point seeds plus synchronous Eden growth for `size_init_cells` rounds (ca.cpp:1087-1163). Sprout: one central seed, 50 rounds, then 7 splits perpendicular to the long axis gives 128 cells (vessel.cpp:52-61; ca.cpp:901-1002). All target areas are then set to 50 (dish.cpp:54-57), followed by 100 relaxation MCS without chemotaxis. For 01a the "100 cells × 10 rounds" demo files do not match the published 282-cell set-up. The seeding *method* (Eden growth) is a 2008-code value, assumed for 2006. Checked 2026-09-30: 01c p.14 documents TST's `GrowInCells` (single-pixel seeds grown by Eden growth over `sizex/subfield`) and p.12 (step 20) the optional `relaxation` MCS, but not what 01a used. The first frame of 01a-mov already shows compact, irregular multi-pixel cells scattered over a central square about two-thirds of the frame wide (consistent with 333 of 500 px); it cannot show whether they were grown by Eden rounds or relaxed before t = 0. The 01a seeding and any pre-run relaxation remain **STILL OPEN**.
- **A-16 (PDE ↔ CPM ordering and BCs).** → **RESOLVED (2008), assumed for 2006.** Each MCS runs 15 × (secrete/decay forward-Euler step, then one FTCS 5-point diffusion step), **then** the CPM sweep (vessel.cpp:86-94). Absorbing c = 0 on the 1-px outer ring (pde.cpp:189-194, :270-285). c₀ = 0 (pde.cpp:104-106). The PDE is skipped for the first `relaxation` MCS (100 in 2008; 0 in the 2006-labelled files).
- **A-17 (Conflicts between papers).** Unchanged: two distinct parameter sets, not to be mixed. The code **confirms** each side: 2008 files use α = ε = 1e-3, 20-neighbourhood, conn_diss = 0, A = 50, λ = 25. 2006-labelled files use 1.8e-4, 8-neighbourhood, conn_diss = 2000/5000, A = 100, λ = 50. Status: RESOLVED as a distinction.
- **A-18 (morphometry pixel scale).** **STILL OPEN.** No morphometry code ships in TST 0.1.3 (`overview.dat` lists a `morphometry.cpp` that is absent from the release).
- **A-19 (new: relaxation phase).** 2008 runs have 100 MCS of no-PDE relaxation (D-5). **STILL OPEN** whether the paper's MCS counts include these 100 MCS. Checked 2026-09-30: 01c pp.12, 15–16 describe the relaxation as CPM-only MCS before the PDE starts, with one counter `i` over all MCS (`if (i>=par.relaxation)`), but say nothing about the time axis of 01b's figures.
- **A-20 (new: continuous χ(c,c)/χ(c,M) sweeps).** The released code supports only χ(c,c) ∈ {0, χ(c,M)} (D-3). **STILL OPEN:** the exact code for Fig. 5 is unavailable. Our implementation should expose χ(c,c) as a real parameter (G3), which is a superset.

**Still needed from authors / supplements:**
- the 01a supplementary methods (for L, the conn_diss value and the actual Fig. 4 geometry); not locatable online on 2026-09-30 (§1);
- the 01b analysis scripts (compactness, H − H0);
- the parameter files for 01b Figs. 3, 5, 7–10 and 12–13.
