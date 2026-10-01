# 12 — Zajac, Jones & Glazier: convergent extension by anisotropic differential adhesion (paper-grounded spec)

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **12a** | M. Zajac, G.L. Jones, J.A. Glazier, "A Model of Convergent Extension in Animal Morphogenesis", arXiv:physics/9912038**v3** (24 Jan 2000). Published as *Phys. Rev. Lett.* **85**(9), 2022–2025 (2000), per 12b's reference list (p.259) | arXiv: physics/9912038. The PRL DOI is not printed in our PDFs (external) | `docs/references/12a_Zajac2000_PRL_convergent-extension_arXiv.pdf` (9 pp. + blank) |
| **12b** | M. Zajac, G.L. Jones, J.A. Glazier, "Simulating convergent extension by way of anisotropic differential adhesion", *J. Theor. Biol.* **222**, 247–259 (2003) | 10.1016/S0022-5193(03)00033-X (12b p.247) | `docs/references/12b_Zajac2003_JTheorBiol_anisotropic-differential-adhesion.pdf` (13 pp.) |

**Pages.** 12a pages are the arXiv page numbers (1–9). 12b pages are journal pages 247–259 (PDF page = journal page − 246).

**Text-layer caveats.** The 12b text layer drops minus signs and subscripts (for example I_xy prints without its minus). All equations below were checked against the rendered pages 250–252 and 257–258.

**Code.** None released. 12b cites Zajac's PhD thesis (Notre Dame, 2002) for implementation details (p.250, p.254, p.259). The thesis is **not on disk**.

**What each paper contains — important.**
- **12a** is **purely analytic** (bulk contact counting + a continuum boundary variational problem). It contains **no Potts simulation**: "We have initiated simulations … Nevertheless we believe the simulations will eventually substantiate our conclusions" (12a p.7). The interface-normal J(n̂·â) and the aspect-ratio law Eq. (7) belong to this analytic model.
- **12b** is the **CPM (Extended Potts Model) implementation**. Its anisotropic coupling is **not** a function of the interface normal. It is a product of per-cell factors that depend on the **position of the contact point relative to each cell's centre and long axis** (Eq. 2 below).

---

## 2. Mechanics

### 2.1 Analytic model (12a)

**Bulk contact energy, Eq. (1), 12a p.4.** Contacts are classified as long–long (ll), short–short (ss) and long–short (ls). With total lengths L_ll, L_ss, L_ls, and the constraints 2Nl = 2L_ll + L_ls, 2Ns = 2L_ss + L_ls:

E = L_ll J_ll + L_ss J_ss + L_ls J_ls = (J_ls − J_ll/2 − J_ss/2) L_ls + N(l J_ll + s J_ss)

**Ordering condition, Eq. (2), 12a p.4:**

γ_ls = J_ls − (J_ll + J_ss)/2 > 0

**Product form, 12a p.4–5.** J_ll = −j_l j_l, J_ss = −j_s j_s, J_ls = −j_l j_s, "where the sign is chosen [to] make all J < 0". This satisfies the ordering condition whenever j_l ≠ j_s (the text says "Eq. (1)"; it means Eq. 2).

**Elongation condition, Eq. (3), 12a p.5:**

J_ll < J_ss < 0 (or j_l > j_s > 0)

**Finite array, Eq. (4), 12a p.6.**
- J(n̂·â) is "negative, an even function … and is minimum at n̂·â = 0" (p.5).
- n̂ is the unit normal to the contact segment, and â the common alignment direction (Fig. 3, p.6).
- "missing adhesive energy" at a boundary with inert surroundings (p.6).

E = λA − ½ ∮ J(n̂·â) dl

- λ is the (negative) bulk energy per unit area, or a Lagrange multiplier.
- Parameterisation: dl = (ẋ² + ẏ²)^{1/2} du, (n̂·â) = (a_y ẋ − a_x ẏ)/(ẋ² + ẏ²)^{1/2}, A = ∫₀¹ y ẋ du, and 𝓛 = λ y ẋ − J(n̂·â)(ẋ² + ẏ²)^{1/2}/2 (p.6).

**Euler–Lagrange first integral, Eq. (5), 12a p.6:**

2λ r = â J′(n̂·â) + n̂ [J(n̂·â) − (n̂·â) J′(n̂·â)]

**Turning points, Eq. (6), 12a p.7:** λ d(r·r)/du = 2λ(ṙ·r) = (ṙ·â) J′(n̂·â).

**Aspect ratio, Eq. (7), 12a p.7:**

D⊥ / D∥ = J(0) / J(1)

with J(0) ≡ J_ll and J(1) ≡ J_ss (p.7). For J constant, the solution is a circle of radius J/(2λ) (p.7).

Numerical check (p.7): J is chosen "to be a gaussian function". The boundary is a polygon of ≥ 100 sides, relaxed by constant-area gradient descent from "many initial configurations". "The final boundary curve is always the same and with the correct aspect ratio Eq. (7)". Gaussian width and amplitude are **not given**.

### 2.2 CPM model (12b)

**Isotropic base energy, Eq. (1), 12b p.250:**

E = Σ_{i,j,k,l}^{sites} (1 − δ_{σ_ij, σ_kl}) J_{τ(σ)τ(σ′)} + Σ_σ^{cells} λ_{τ(σ)} (A(σ) − A∘)²

- "i and j [are] site coordinates … k and l [are] coordinates of nearby sites" (p.250). The neighbour range is **UNSPECIFIED**.
- A∘ is the target area. The medium is "a wide border of lattice sites, assigned to a generalized cell of unlimited size, with λ_{τ(σ)} set equal to zero" (p.251).

**Anisotropic coupling, Eq. (2), 12b p.251 (verbatim structure):**

J(r, r′) = J_{τ(σ)τ(σ′)} − Δ(r) Δ(r′)
Δ(r) = α_{τ(σ)} ε(σ) r sin(θ)

- **r, r′**: "vectors r and r′ which locate a common boundary point (Fig. 4) relative to the respective centers of neighboring cells" (p.251).
- **(r, θ), (r′, θ′)**: polar coordinates of r and r′, "with angles measured from the long axes of cells σ and σ′, respectively" (p.251). Fig. 4 caption: θ, θ′ ∈ [0, π], "so there is no need to distinguish between complementary angles" (p.251). Hence r sin θ ≥ 0 is the **perpendicular distance of the contact point from the cell's long axis**.
- **Long axis**: "the principle axis (Appendix A) with the least moment of inertia gives the direction of elongation" (p.251).
- **ε(σ)**: "a measure of the cell elongation, derived (Appendix A) from the principle moments of inertia". It is the eccentricity for an ellipse (p.251): ε = √(1 − λ_a/λ_b) (Eq. A.4, p.257).
- **α_{τ(σ)}**: "sets an upper limit on anisotropy". It "is positive for coupling between cells but vanishes otherwise so that coupling to the culture medium does not depend on cell orientation" (p.251).
- Consequence (derived from Eq. 2):
  - A contact at the side of both cells (θ ≈ π/2) gets the largest reduction α²εε′ r r′.
  - An end-to-end contact (θ ≈ 0) gets none (J = J_ττ′).
  - So "ll" contacts are the most adhesive, in line with 12a Eq. (3).

**Shape constraint (12b p.251–252).** It is "formally equivalent to the constraint on cell size from Eq. (1) but with κ_{τ(σ)}, I(σ) and I∘ replacing λ_{τ(σ)}, A(σ) and A∘", i.e.

E_shape = Σ_σ κ_{τ(σ)} (I(σ) − I∘)²

**Eq. (3), 12b p.252:**

I∘ = (A∘/4)(a² + b²), A∘ = π a b

- a and b are the target ellipse semi-axes.
- I is "the moment of inertia for a flat elliptical cell about an axis through the center of mass, perpendicular to the plane of the lamina" (p.252). This is the **polar** second moment Σ|x − x̄|² = I_xx + I_yy of the cell's sites (A.1), with unit mass per site. It is inferred from the wording plus A.1; the paper does not write I = I_xx + I_yy explicitly.
- a = b favours round cells; a ≠ b favours elongated cells (p.252).

**Inertia tensor and axes, Appendix A, Eqs. (A.1)–(A.4), 12b p.257.** Lattice row/column indices serve as coordinates; N sites; x̄, ȳ is the centre of mass.

I_xx = Σ (y_i − ȳ)², I_xy = I_yx = −Σ (x_i − x̄)(y_i − ȳ), I_yy = Σ (x_i − x̄)² (A.1)

λ_b = ½(I_xx + I_yy) + ½ √((I_xx − I_yy)² + 4 I_xy²) (A.2)

b = x̂ I_xy + ŷ (λ_b − I_xx) (A.3)

ε = √(1 − λ_a/λ_b) (A.4)

- λ_b is the larger eigenvalue, and b points "along the semiminor axis".
- λ_a (the minus sign on the radical), with its eigenvector a from (A.3), gives the **long axis / orientation**.
- The eigenvectors are unnormalised.
- "2√λ_b is the length of the semimajor axis" (p.257). This holds only per unit mass, i.e. with λ_b/N (A-Z6).

**Acceptance, Eq. (4), 12b p.252:**

P(ΔE) = e^{−E₁/T} / e^{−E₀/T} for E₁ > E₀, and 1 for E₁ ≤ E₀

**Proposal (12b p.252).**
- "a lattice site is chosen at random and provisionally altered to match the sites in a different, randomly selected domain".
- "cell simulations only consider sites at a boundary between domains for modification, with modified sites reassigned to the domain of a randomly selected nearby site".
- The authors note this variant "does not have … microscopic reversibility" (p.252).
- The "nearby" range is **UNSPECIFIED**.

**Sweep.** "the number of pattern modifications attempted in one sweep equal to the number of lattice sites" (p.254).

**Axis / coupling update (critical; 12b p.252–253).**
1. "As an advancing cell gains one lattice site from a retreating neighbor the centroid and orientation (Appendix A) of each changes slightly. It follows that coupling changes at all points where either of the altered domains contacts any adjacent cell, not just at points in the neighborhood of a single modified site."
2. "Rather than laboriously updating polar coordinates for all lattice sites at multiple cell boundaries whenever a single site changes, current simulations replace individual site coordinates r and θ with **average values for segments of contact** between adjacent cells. Consequently, updated coupling requires a visit to each boundary segment, rather than visiting each boundary site, for a modified cell pair."
3. "This faster algorithm … may be regarded as an approximation of the original scheme or simply adopted as an alternative" (p.253).

**Verdict on per-copy vs lagged.**
- The published scheme updates each cell's centroid, axis and ε **per copy**, i.e. exactly, not lagged.
- It re-evaluates the coupling over **all contact segments of both modified cells**, using segment-averaged (r, θ) instead of per-site values.
- The paper does not state explicitly that the trial ΔE uses the post-copy axes of both cells, but "updated coupling … for a modified cell pair" implies it.
- **A lagged per-MCS director is NOT what the paper did.** It is an additional approximation. It removes the energetic term by which a single copy rotates or re-elongates a cell and changes every interface of that cell (the "non-local on the scale of the size of a cell" effect, 12a p.7). Validation (§5) is therefore required before substituting it.

**Initial condition (12b p.253).** "starting from a roughly square block (Fig. 5a) of weakly elongated, randomly oriented cells". Cell count, sizes and lattice size are **not stated**. Fig. 5a shows on the order of 50–70 cells (visual estimate only).

**No growth, division or death.** "negligible cell division and little change in cell volume" (12a p.3). 12b simulates a block of cells from one tissue plus medium (p.251).

---

## 3. Parameter table

Almost every numerical value of the 12b simulation is **absent** from the paper. The thesis (Zajac 2002) presumably holds them.

| Symbol | Value | Units | Meaning | Source | Stated/derived |
|---|---|---|---|---|---|
| J_ll, J_ss, J_ls (analytic) | J_ll < J_ss < 0; γ_ls > 0 | energy/length | analytic contact energies | 12a Eqs. (2), (3) p.4–5 | stated (inequalities only) |
| J(n̂·â) (analytic) | even, negative, min at n̂·â = 0; Gaussian in numerics | — | orientation-dependent energy density | 12a p.5, p.7 | form stated; parameters UNSPECIFIED |
| λ (analytic) | < 0 | energy/area | bulk energy density | 12a p.5 | stated (sign) |
| J_{cell,cell} (CPM base) | > 0 ("positive cell couplings") | energy | isotropic coupling | 12b p.252, p.254 | sign stated; value UNSPECIFIED |
| J_{cell,medium} | — | energy | isotropic | 12b p.251 | UNSPECIFIED |
| α_τ | > 0 for cell–cell, 0 for medium | energy^{1/2}/length | anisotropy amplitude | 12b p.251 | value UNSPECIFIED; must keep J(r,r′) > 0 (Fig. 6, p.254) |
| Anisotropy (relative) | 57% gives two-column arrays (Fig. 5h). < 35%: little/no extension. > 65%: single column | % | "relative difference … between binding for aligned and unaligned cells" | 12b p.254 | stated. The definition in terms of α, ε, J is UNSPECIFIED |
| λ_τ | — | energy/site² | area strength (0 for medium) | 12b p.250–251 | UNSPECIFIED |
| A∘ | πab | sites | target area | 12b Eq. (3) p.252 | form stated; value UNSPECIFIED |
| κ_τ | — | energy/site⁴ | shape (inertia) strength | 12b p.251 | UNSPECIFIED. "roughly equal contributions" of adhesion and shape to ΔE works; ×10 or ÷10 changes outcomes (p.255) |
| a, b | — | sites | target ellipse semi-axes | 12b Eq. (3) | UNSPECIFIED (a ≠ b "elliptical" or a = b "circular" both tried, p.254–255) |
| I∘ | (A∘/4)(a² + b²) | site·site² | target polar moment | 12b Eq. (3) | stated form |
| T | set to give ≈ 46% acceptance (works). 72% too hot, 21% too cold | energy | temperature | 12b p.255 | stated only as acceptance rates |
| Neighbour ranges (energy, proposal) | "nearby sites" | — | — | 12b p.250, p.252 | UNSPECIFIED |
| Lattice, BCs | "wide border" of medium | — | — | 12b p.251 | size UNSPECIFIED |
| N cells | — | — | — | Fig. 5 | UNSPECIFIED (≈ 50–70 by eye) |
| Run length | ≈ 800 kilosweeps (Fig. 5 axis) | sweeps | — | 12b Fig. 5 p.253 | stated (plot) |
| Cost | > 72 h per simulation at 750 MHz | — | — | 12b p.256 | stated |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence / correction |
|---|---|---|---|
| 1 | J depends on interface normal relative to each cell's long axis | **CORRECTED** | Only the **analytic** 12a model uses the interface normal: J(n̂·â) with a *common* alignment â (12a p.5, Fig. 3). The **CPM** in 12b uses J(r,r′) = J_ττ′ − Δ(r)Δ(r′), Δ = α ε r sin θ. Here r is the contact point's position relative to each cell's **centre of mass** and θ its angle from **that cell's** long axis (12b Eq. 2 p.251, Fig. 4). This is a product of per-cell, position-based factors weighted by elongation ε, not a normal-based J |
| 2 | J_ll < J_ss < 0 | CONFIRMED (analytic only) | 12a Eq. (3) p.5. In the 12b CPM, couplings are **positive** ("positive cell couplings", p.252; negative coupling is the "catastrophe", p.254). The anisotropy lowers J for side contacts. The ordering J_ll < J_ss survives; the sign does not |
| 3 | γ_ls = J_ls − (J_ll + J_ss)/2 > 0 | CONFIRMED | 12a Eq. (2) p.4 ("ordering condition") |
| 4 | area constraint + length constraint λ_L(l − L0)², l = 4√λ_max(inertia) | **CORRECTED / NOT IN PAPER** | 12b uses an area constraint (Eq. 1) and a **moment-of-inertia** shape constraint κ(I − I∘)², I∘ = (A∘/4)(a² + b²) (12b p.251–252, Eq. 3). There is no length constraint and no l = 4√λ_max formula in 12a or 12b. That formula is the Merks 2006 length constraint (see `01_merks.md`) |
| 5 | predicted final tissue aspect ratio D⊥/D∥ = J(0)/J(1) | CONFIRMED (analytic only) | 12a Eq. (7) p.7, with J(0) = J_ll and J(1) = J_ss. Caveat: 12a p.7 then says "If J(1) < J(0) < 0 then D⊥/D∥ > 1". That contradicts Eq. (7) combined with Eq. (3); it should read J(0) < J(1) < 0 (A-Z1). 12b does not test Eq. (7) quantitatively ("These numbers are not especially meaningful", p.254) |
| 6 | independent of initial layout and elongation | CONFIRMED (analytic only) | Initial configuration: 12a abstract (p.1) and p.7 ("final aspect ratio is independent of the initial configuration"). Elongation: 12a p.5 ("independent of the degree of elongation", for a rectangular array of rectangular cells) |
| 7 | energy non-local on cell scale (a copy rotates the axis, changing every interface of the cell) | CONFIRMED | 12a p.7 ("the energy becomes non-local on the scale of the size of a cell"). 12b p.252 ("coupling changes at all points where either of the altered domains contacts any adjacent cell") |

---

## 5. Validation targets

Policy: statistical/qualitative agreement (D-029). 12b gives **one** archetypal trajectory (Fig. 5) and no ensemble. Its parameters are unspecified, so quantitative targets are shape-of-curve only.

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-Z1 | Order of events: elongation first (inset: mean ε ≈ 0.6 → ≈ 0.78 within ≈ 0.1–0.2 kilosweeps, then flat ≈ 0.75–0.8). Alignment rises from ≈ 0.6 to ≈ 0.9 with a large jump near ≈ 450 kilosweeps (stages e–f). Extension rises ≈ 1.5 → ≈ 6 by ≈ 600 kilosweeps, then plateaus (read from plot) | 12b Fig. 5 p.253; text p.253 | Qualitative + plot-read | t(ε reaches 90% of plateau) < t(alignment reaches 0.8) ≤ t(extension reaches 80% of plateau), in ≥ 4/5 runs. Plateau ε ∈ [0.65, 0.85]; final alignment ≥ 0.85; final extension ≥ 3 |
| V-Z2 | Extension direction ⟂ alignment direction | 12b p.253; 12a p.5 | Qualitative | Angle between the tissue long axis (eigvec a of the whole-array tensor) and the alignment director ≥ 70° at the end |
| V-Z3 | Anisotropy sweep: < 35% little/no extension; 57% two columns; > 65% single column | 12b p.254 | Semi-quantitative (definition of % unspecified) | Monotone increase of final extension with anisotropy; a column count of 2 at an intermediate value and 1 at a high value |
| V-Z4 | Temperature: ≈ 46% acceptance aligns and extends. ≈ 72% extends but alignment "fluctuating wildly". ≈ 21% aligns but fails to converge | 12b p.255; Fig. 8 p.256 | Qualitative | Reproduce the three regimes when T is tuned to those acceptance rates |
| V-Z5 | No anisotropy (α = 0) plus shape constraint: elongated cells form compact clusters (three cells → "a crude, rounded triangle") | 12b p.255 | Qualitative | Final array extension < 1.5 with α = 0 |
| V-Z6 | Excessive anisotropy (negative J) → hyper-elongation, commingling, disintegration | 12b Fig. 6 p.254 | Qualitative (negative control) | Detect J(r,r′) < 0 and flag; not a success criterion |
| V-Z7 | Weak cohesion → array curvature or spurious branches | 12b Fig. 7 p.255 | Qualitative (negative control) | — |
| V-Z8 (analytic) | For a J(n̂·â) Wulff-type boundary, the extremal aspect ratio equals J(0)/J(1) independent of the start shape | 12a Eq. (7), p.7 | Quantitative (continuum) | A unit test of a boundary-relaxation solver, not a CPM target. A CPM equivalent would need an explicit mapping from Eq. (2) to J(n̂·â), which neither paper gives (A-Z3) |

**Metric definitions (for G12).**
- Elongation: per-cell ε (A.4), averaged over cells (12b p.254).
- Alignment: largest eigenvalue of A (A.5), with A_xx = (1/N)Σcos²θ_i, A_xy = (1/N)Σcos θ_i sin θ_i, A_yy = (1/N)Σsin²θ_i, where (cos θ_i, sin θ_i) is the normalised long-axis vector a of cell i. Range [1/2, 1] (12b p.258).
- Extension: λ_b/λ_a of the inertia tensor over all cell sites (12b p.257–258). Note this is a ratio of second moments (≈ the square of a length aspect ratio for an ellipse), although the text calls it the "aspect ratio" (A-Z5).
- Time: 1 sweep = N_sites attempts = 1 MCS in our convention.

**Lagged-director acceptance test (required before adopting the performance approximation).** Run exact (per-copy axis, segment-averaged) and lagged (per-MCS director) variants with identical parameters, n ≥ 5 seeds each. Accept the lagged variant if:
- the final extension, alignment and ε ensemble means agree within the larger of 15% or 2 pooled SEM; **and**
- the event order in V-Z1 is preserved.

---

## 6. Required general features

| ID | Needed? | Use |
|---|---|---|
| G1 @transition/@create/@retire | No | — |
| **G2** shape descriptors in energies | **Yes** | Per-cell second-moment tensor (A.1) maintained incrementally. Polar moment I for κ(I − I∘)². Eigen-decomposition for ε (A.4) and long axis a (A.2–A.3) used **inside** ΔE |
| **G3** contact-scope direction/position + lagged vector cell vars | **Yes (core of the model)** | The contact energy of a link needs the **position of the contact point relative to each cell's COM** and the angle to **each cell's** axis: J = J_ττ′ − (α ε r sin θ)(α′ ε′ r′ sin θ′). Exact per paper: cell vars (COM, axis, ε) are **current** (per copy), and ΔE must include the changes of J on **every contact segment of both cells** (cell-scope non-local ΔE). Performance variant: **lagged** vector cell vars (director, ε, COM snapshot per MCS). Then ΔE is local to the flipped site's links. This is a deviation (§2.2 verdict) |
| **G14 (new)** cell-pair contact-segment aggregation | **Yes** | The paper's algorithm averages r and θ over each **contact segment** between a cell pair and recomputes the coupling per segment (12b p.252). Requires a maintained per-pair contact list (length + summed contact-point positions) so that J per pair = J_ττ′ − α²εε′ ⟨r sin θ⟩⟨r′ sin θ′⟩ × length. **Justification:** no other G-feature provides per-pair aggregated geometry. It is also the natural way to make the exact (non-lagged) ΔE affordable: O(number of neighbours of the two cells) instead of O(boundary sites) |
| G4 connectivity | No (not mentioned) | Paper relies on positive couplings for compactness (p.254) |
| G5, G6, G7 | No | No fields or conversion |
| **G8** pluggable proposal law | **Yes** | Boundary-site-only selection with reassignment to a random nearby domain (12b p.252; non-reversible). Also an acceptance-rate monitor to tune T to ≈ 46% (p.255) |
| G9 per-cell component protocol | No | — |
| **G10** cluster-scope quantities | **Yes** | Array-level inertia tensor over all cell sites (extension). Alignment tensor over cells |
| G11 ordered relationships / angle energies | No (angles are per-contact, covered by G3/G14) | — |
| **G12** observables library | **Yes** | ε per cell, alignment eigenvalue (A.5), extension λ_b/λ_a, acceptance fraction per sweep |
| **G13** initial layout generators | **Yes** | Roughly square block of weakly elongated, randomly oriented cells inside a wide medium border |

---

## 7. Ambiguities and open questions

- **A-Z1 (12a sign typo).** p.7: "If J(1) < J(0) < 0 then D⊥/D∥ > 1". With Eq. (7) D⊥/D∥ = J(0)/J(1) and both J negative, D⊥/D∥ > 1 requires |J(0)| > |J(1)|, i.e. J(0) < J(1) < 0. This agrees with Eq. (3) J_ll < J_ss and with J(0) = J_ll. The printed inequality is reversed.
- **A-Z2 (all numerical parameters).** J_ττ′ (cell–cell and cell–medium), α, λ, κ, A∘, a, b, T, lattice size, cell count and neighbour ranges are absent from 12b. Only acceptance rates and relative anisotropy percentages are given. **Need Zajac's 2002 PhD thesis or author input.**
- **A-Z3 (anisotropy definition).** The "relative difference of 57% between binding for aligned and unaligned cells" (p.254) is not defined in terms of Eq. (2). Is it α²ε²r r′/J_ττ′ at a representative side contact? Is it (J_max − J_min)/J_max over segments?
- **A-Z4 (segment averaging details).** How is a "segment of contact" defined (a maximal run of boundary links between one cell pair? all links between the pair?) Are r and θ averaged, or is r sin θ averaged? Is the segment's J multiplied by its link count? Which neighbour order defines links?
- **A-Z5 (extension measure).** It is defined as λ_b/λ_a (ratio of second moments, p.257–258) but described as an "aspect ratio" starting at one (p.253). If Fig. 5's "Extension ≈ 6" is λ_b/λ_a, the length aspect ratio is about √6 ≈ 2.4. We need to know which one is plotted.
- **A-Z6 (normalisation).** "2√λ_b is the length of the semimajor axis" (p.257) holds only if λ_b is per unit mass (divided by N). A.1 sums are unnormalised. Irrelevant for ε and the alignment direction; relevant if anyone uses the axis length.
- **A-Z7 (I in the shape constraint).** Is I(σ) the polar moment I_xx + I_yy (our reading of "about an axis … perpendicular to the plane", p.252)? Or something else? It is rotation-invariant, so the constraint does not orient cells.
- **A-Z8 (trial-energy evaluation).** Does ΔE for a trial copy use the axes and ε of both cells **after** the trial copy (exact)? The text implies per-copy updating but does not state the trial/commit order.
- **A-Z9 (proposal neighbourhood).** "randomly selected nearby site" / "nearby sites": range unknown.
- **A-Z10 (no ensemble).** Fig. 5 is a single run "chosen unscientifically" (Fig. 2 caption, p.249). Its shape is a target; its numbers are not.

### 7.1 Existing port

There is no Zajac model in `lib/PottsModels/src/` (the files are akeeb.jl, graner_glazier.jl, merks.jl, openvt.jl and wortel_act.jl), so there are no port discrepancies to list.
