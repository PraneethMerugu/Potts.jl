# 13 — Starruß myxobacteria: segmented rod cells and collective migration (paper-grounded spec)

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **13** | J. Starruß, Th. Bley, L. Søgaard-Andersen, A. Deutsch, "A New Mechanism for Collective Migration in *Myxococcus xanthus*", *J. Stat. Phys.* **128**(1/2) (2007) 269–286 | 10.1007/s10955-007-9298-9 | `docs/references/13_Starruss2007_JStatPhys_myxobacteria.pdf` (18 pp.) |

**Page numbers.** The citations use journal page numbers 269–286. PDF page = journal page − 268.

**Code.** The paper cites no code. None was used here.

**Method.** I extracted the whole text with `pdftotext -layout`. I checked Eqs. 2–10 and Table I against 300-dpi renders of the page images, because the text extraction garbles the math: it drops the "≠" in Eq. 6 and the minus sign in Eq. 7 is unclear. I read Figs. 2, 3, 5 and 8 from the page images. Values marked "read from figure" are digitised by eye at about ±0.02 in Ψ̄ and about ±0.01 in velocity.

---

## 2. Mechanics

### 2.1 Representation: a rod is a chain of CPM sub-cells ("segmented cell")

- Each model cell µ "is subdivided into cell segments ν, that are formed by original Cellular Potts model cells" (13 p.272 §2). The authors assign "no biological interpretation of this segmentation" (13 p.272).
- **Two-component site state, Eq. 1** (13 p.272):
  σ(i) = (µ, ν) ∈ S = {(0,0), (k,l) : k ∈ {1..c}, l ∈ {1..s}},
  where c is the number of cells and s the number of segments per cell. Medium is σ₀ = (0,0).
- **Ordering.** Segment ν = 1 is the "head" and ν = s is the "tail" (13 p.272). Segments form "a connected row of CPM cells" (13 p.272 §1).
- **Per-segment centre of mass.** S_{µ,ν} is "the centre of mass of the νth segment of cell µ" (13 p.273 §2.1). Footnote 4 (13 p.275): the centres of mass "were calculated in a non-periodic space after projection L → Z²". This means the COMs are unwrapped and are not taken modulo the periodic box.
- **Cell-level structure.** A cell has no cell-level energy term (no cell volume, no cell perimeter). All cell-level behaviour comes from the pairwise and triplet segment terms below.
- **No explicit connectivity constraint** appears anywhere. The authors report that segments "always remain connected" for the 'xanthus' parameters (13 p.279 §3.1). They also say the ranges of ω and T "are limited" in order to avoid interpenetration and keep segments connected (13 p.279).

### 2.2 Hamiltonian (Eq. 5, 13 p.274)

```
H = Σ_{(i,j) neighbours} ½ J_{σ(i),σ(j)}
  + λ Σ_{µ=1..c} Σ_{ν=1..s}   (a_{µ,ν} − A)²
  + ζ Σ_{µ=1..c} Σ_{ν=1..s−1} (|S_{µ,ν} − S_{µ,ν+1}| − D)²
  + ξ Σ_{µ=1..c} Σ_{ν=1..s−2} (1 / R_curve(S_{µ,ν}, S_{µ,ν+1}, S_{µ,ν+2}))²
```

- **Term 1: boundary energy.** The sum runs over ordered neighbour pairs with a factor ½, so each unordered pair counts once. "Second-nearest neighbours were used for the calculation of node interaction energy" (13 p.275 §2.3).
- **Term 2: segment volume (area) constraint.** a_{µ,ν} is the number of nodes of the segment and A is its target area (13 p.274). λ is **per segment**. There is no cell-level area term.
- **Term 3: length energy, Eq. 4** (13 p.273). E_length(µ) = ζ Σ_{ν=1}^{s−1} (|S_{µ,ν} − S_{µ,ν+1}| − D)². It penalises deviation of consecutive segment-COM distances from D.
- **Term 4: curvature ("bending") energy, Eq. 3** (13 p.273). E_curve(µ) = ξ Σ_{ν=1}^{s−2} (1/R_curve)². The paper calls it "comparable to the bending energy of solid bodies" (13 p.273).
- **Radius of curvature, Eq. 2** (13 p.273). It is the circumradius of three consecutive segment COMs:
  R_curve(S_ν, S_{ν+1}, S_{ν+2}) = |S_{ν+2} − S_ν| / (2 sin ∠(S_ν, S_{ν+1}, S_{ν+2})).
  The angle is taken at the middle point S_{ν+1}. The paper justifies it "under the assumption of low curvature" (13 p.273). For collinear points the angle is π, sin = 0, R = ∞ and the curvature energy is 0. The paper does not say how degenerate cases are handled (see §7).

### 2.3 Contact energies (Eq. 6, 13 p.274; checked against the page image)

```
J_{(µ1,ν1),(µ2,ν2)} = 0      if σ1 = σ2
                      J_CM   if either σ1 = (0,0) or σ2 = (0,0)
                      J_SS   if µ1 = µ2 ≠ 0 and |ν1 − ν2| = 1
                      J_CC   else
```

- J_SS is "a reduced interaction energy … between nodes of neighbouring segments", used "to keep the segments of one cell attached but unmixed" (13 p.274).
- **Consequence of "else".** Two **non-adjacent segments of the same cell** (|ν1 − ν2| ≥ 2) that touch pay J_CC, the same as contacts between different cells. This is how the equation reads. The paper does not discuss it.
- J_CC = 3 J_CM gives "a short-range repulsion … between neighbouring cells" that "mimics a thin film of medium between cells" (13 p.276). Footnote 5: the effective penalty is 50%, since "energetically neutral interaction is obtained for J_CC = 2J_CM" (13 p.276).

### 2.4 Active motion: the propulsion work term (Eqs. 8–10, 13 p.274–275)

- **Where it enters.** Propulsion is **not** part of H. It is added to ΔH at copy time. Eq. 8: ΔH′ = ΔH + ΔD (13 p.274).
- **Moving direction per segment, Eq. 9** (13 p.275; checked against the page image):
  ```
  θ_σ = θ_{µ,ν} = 0                       if µ = ν = 0 (medium)
                  θ_{µ,ν+1}               if ν = 1   (head copies its successor)
                  θ_{µ,ν−1}               if ν = s   (tail copies its predecessor)
                  ||S_{µ,ν−1} − S_{µ,ν+1}||  else
  ```
  The text says "a segment's moving direction is directed from its succeeding to its preceding cell segment". So interior segments point toward the **head** along the local chord S_{ν+1} → S_{ν−1}. Edge segments inherit the direction of their single neighbour. θ is recomputed from the current segment COMs, so it is **not** a stored or persistent polarity and has no separate update rule.
  - The notation ||·|| is ambiguous. It is printed with double bars, and it can be read either as a scalar norm (which cannot be right for a direction) or as the normalised vector (see §7). Nothing states whether θ is a unit vector.
- **Update direction.** A copy is written as σ(i) → σ(j): "a node i is selected at random and its state is converted to the state of one of its nearest neighbours j" (13 p.274). Here i is the target and j is the source. The update direction is **d = i − j** (13 p.275), pointing from source to target.
- **Propulsion work, Eq. 10** (13 p.275):
  ΔD(σ(i) → σ(j)) = −ω (d ∘ θ_{σ(i)} + d ∘ θ_{σ(j)}),
  where ∘ is the scalar product. Both the segment that loses node i and the segment that gains it contribute. If either is medium, its term vanishes because θ(σ₀) = 0 (13 p.275).
- **Scope.** Propulsion applies to **all segments**, not only the head. The head's direction is simply copied from segment 2.
- **Reversals.** The model has none. The authors "consider non-reversing cells, which move unidirectionally" (13 p.271). The model cell "corresponds to a non-reversing myxobacterial cell, which moves by A-motility" (13 p.278). "In the present study we have not included cell reversals" (13 p.285).

### 2.5 Dynamics and acceptance

- The algorithm is "as described for the original CPM" (Graner & Glazier 1992) (13 p.274 §2.2). Pick a node i at random and copy the state of one of its **nearest neighbours** j into it.
- **Acceptance, Eq. 7** (13 p.274): p = 1 if ΔH′ < 0, and p = e^{(…)ΔH′/kT} if ΔH′ ≥ 0.
  - On the page image the exponent reads ΔH′/kT, and the minus sign is not visible (see the 300-dpi render). This is almost certainly a typesetting omission. The spec uses the standard Metropolis form exp(−ΔH′/kT), because an exponent of +ΔH′/kT would give p > 1 for every ΔH′ > 0.
  - "Metropolis-Kinetics (7)" refers to the equation, not to reference 7.
- **Neighbourhoods.** Proposals use **nearest** neighbours, which is 6 on the hexagonal lattice. Energy uses **second-nearest** neighbours (13 p.275 §2.3). The paper does not say whether "second-nearest" means the 1st+2nd shells together (12 sites on a hex lattice) or only the 2nd shell (see §7).
- **MCS.** Time is reported in MCS (Figs. 2–5). The number of attempts per MCS is not defined in the paper. It is assumed to be Graner–Glazier style, one attempt per lattice site (UNSPECIFIED).
- **Update order.** Only random sequential single-site copies are described. There are no other per-MCS processes: no fields, no growth, no conversion.

### 2.6 Lattice, boundaries, temperature

- **Lattice.** 2D **hexagonal**, L ⊂ Z², with **periodic boundary conditions** (13 p.275 §2.3). The paper explains that the lattice geometry and neighbourhood give "a sufficently high number of possible moving directions" (13 p.275).
- **Lattice size.** UNSPECIFIED, for all figures.
- **Anisotropy.** Single cells show a slight preference to move along the hex symmetry axes. The paper says this "was not detectable in the simulations of interacting cell populations" (13 p.279).
- **Temperature.** kT = 0.8 E (Table I). Low T gives incomplete relaxation of a bent cell (13 p.277).

### 2.7 Initial conditions

- **Population runs.** "Started from random initial configurations, where position and orientation of each cell were chosen at random" (13 p.276). Fig. 6 starts "from 100 randomly dropped cells" (13 p.280). The paper does not say how cells are laid out: whether straight, whether overlap is rejected, or what the initial segment shape is.
- **Stiffness test (Fig. 2).** A cell is artificially bent (13 p.277). The initial bend geometry is shown only as a snapshot and is UNSPECIFIED.
- **Snake test (Fig. 3).** A cell has its head "fortuitously fixed in the agar" (13 p.277–278). The paper does not say how the head is fixed in the simulation, for example a frozen head segment or suppressed copies (see §7).

### 2.8 Aspect ratio κ

- κ is the "length-to-width aspect ratio" of the cell. The paper says "κ was adjusted through the number of segments s per cell" (Fig. 5 caption, 13 p.279). It also says: "we previously determined for Myxococcus xanthus (κ ≈ 6, ξ = 300 E)" (13 p.282). No formula for κ(s) is given.
- **Derived (my inference, not stated).** The κ abscissae in Figs. 5 and 8 are about 2.5, 3.4, 4.3, 5.2, 6.9, 10.3, 13.9 and 17.3. These are consistent with κ ≈ 0.86·s for s = 3, 4, 5, 6, 8, 12, 16, 20. That fits s = 8 → κ ≈ 6.9, reported as "≈ 6". Treat this mapping as a hypothesis.
- **Inconsistency.** Fig. 6 states κ ≈ 10, but the text says it used "the parameter set previously estimated for M. xanthus" (13 p.280), which has s = 8 (κ ≈ 6–7). See §7.

### 2.9 Observables defined in the paper

- **Curvature energy vs time.** E_curve (Eq. 3) of a bent single cell, as in Fig. 2.
- **Single-cell velocity.** Reported in nodes/100 MCS (Fig. 5a y-axis, read at 600 dpi). The paper does not give the measurement interval.
- **Motion efficiency.** The "ratio of net distance covered and the total path length" (13 p.279). Net distance is the "absolute distance between start and endpoint" (footnote 8). The paper does not say what the "given total path length" or the sampling interval is.
- **Aligned-cluster criterion, Eqs. 11–12** (13 p.281). Cells α and β are "next to each other within same cluster" if both of these hold:
  - D_max > min over all segment pairs (ν, ν′) of |S_{α,ν} − S_{β,ν′}|, which is the minimum segment-COM distance (Eq. 11);
  - φ_max > ∠(θ_{α,1}, θ_{β,1}), which is the angle between the **head** moving directions (Eq. 12).
  - D_max = 8 nodes and φ_max = π/4. The criteria are applied "iteratively for all cell pairs", so a cluster is the connected component (transitive closure) of the pair relation.
- **Order parameter Ψ̄, the "average maximum cluster size"** (13 p.282). Reach a quasi-steady state, then sample the cluster-size distribution ψ "at regular time intervals". Ψ̄ is the time-average of the largest cluster size divided by the population size. Ψ̄ = 1 means all cells are in one cluster, and Ψ̄ → 0 means no collective migration. The warm-up length, sampling interval and run length are all UNSPECIFIED.
- **Density.** "10, 20 or 30% of the nodes were occupied by cells" (Fig. 8 caption).

---

## 3. Parameter table

The energy unit is E, which is arbitrary (Table I).

| Symbol | Value | Units | Meaning | Source | Stated / derived |
|---|---|---|---|---|---|
| A | 12 | nodes | target area of a segment | 13 p.276 Table I | stated |
| D | √A ≈ 3.464 | nodes | target distance between consecutive segment COMs | 13 p.276 Table I | stated (√A); the numeric value is derived |
| J_CM | 1 | E | cell–medium contact energy | Table I | stated |
| J_CC | 3 | E | cell–cell contact (and same-cell non-adjacent segments, by Eq. 6 "else") | Table I; p.276 | stated |
| J_SS | 0.3 | E | contact between adjacent segments (|Δν| = 1) of the same cell | Table I | stated |
| J(σ,σ) | 0 | E | same segment | Eq. 6 | stated |
| kT | 0.8 | E | temperature | Table I | stated |
| s | 8 | – | segments per cell ('xanthus'); varied to set κ | Table I; Fig. 5 caption | stated |
| λ | 0.7 | E | per-segment area constraint strength | Table I | stated |
| ω | 0.5 | E | propulsion strength | Table I; p.277 | stated |
| ξ | 300 | E | curvature sensitivity; scanned 0 to about 2200 in Fig. 8 right | Table I; p.277 | stated |
| ζ | 35 | E | length sensitivity | Table I | stated |
| κ | ≈ 6 for s = 8 | – | length-to-width aspect ratio | 13 p.282 | stated (≈); the κ(s) mapping is UNSPECIFIED (inferred ≈ 0.86 s, §2.8) |
| D_max | 8 | nodes | cluster distance threshold | 13 p.281 | stated |
| φ_max | π/4 | rad | cluster angle threshold | 13 p.281 | stated |
| density | 10, 20, 30 | % of nodes occupied | population density (Fig. 8) | Fig. 8 caption | stated |
| c | 100 | cells | cell count in Fig. 6 | 13 p.280 | stated (Fig. 6 only); for Fig. 8 runs UNSPECIFIED |
| lattice | hexagonal, 2D, periodic | – | – | 13 p.275 | stated |
| L_x × L_y | UNSPECIFIED | nodes | lattice size | – | – |
| proposal neighbourhood | nearest (6 on hex) | – | copy source j | 13 p.274 | stated ("nearest neighbours"); 6 is derived from the hex geometry |
| energy neighbourhood | "second-nearest" | – | J sum | 13 p.275 | stated; the shell interpretation is UNSPECIFIED |
| MCS definition | UNSPECIFIED | – | – | – | – |
| replicates | 15 | runs | Fig. 5 (mean ± SD) | Fig. 5 caption | stated |
| replicates (Fig. 8) | UNSPECIFIED | – | error bars shown | – | – |
| time scale | 1050 MCS = 49 s; 7850 MCS = 368 s | – | calibration from the snake experiment, about 0.047 s/MCS | Fig. 3 right panel labels | stated in the figure; the per-MCS rate is derived |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| S1 | Each rod is a chain of CPM sub-cells | **CONFIRMED** | "each model cell µ is subdivided into cell segments ν, that are formed by original Cellular Potts model cells" (13 p.272 §2). The state is σ = (µ, ν) (Eq. 1). Head is ν = 1 and tail is ν = s. |
| S2 | …with a bending/stiffness energy | **CONFIRMED (made more precise)** | Stiffness comes from **two** terms on segment COMs. The curvature energy ξ Σ (1/R_curve)² uses the 3-point circumradius (Eqs. 2–3, p.273). The length energy ζ Σ (|ΔS| − D)² is Eq. 4. Both are in Eq. 5 (p.274). ξ = 300 E and ζ = 35 E (Table I). It is not an angle-based (1 − cos) potential. |
| S3 | Active motion along the rod axis, driven from the head | **CORRECTED** | Every segment is propelled. θ_{µ,ν} = ||S_{ν−1} − S_{ν+1}|| for interior segments, and head and tail copy their neighbour's θ (Eq. 9, p.275). The work ΔD = −ω(d·θ_{σ(i)} + d·θ_{σ(j)}) uses the loser's and gainer's directions (Eq. 10). Directions point toward the head, but the drive is distributed along the whole rod, not applied at the head. There are no reversals (p.271, p.278, p.285). |
| S4 | Volume exclusion only, no signalling | **CONFIRMED** | Cells "interact via volume exclusion" (abstract, p.269). The mechanism "does not depend on diffusive signals" (p.269). "No cooperation is involved" (p.284). The only extra interaction is the J_CC = 3J_CM short-range repulsion (p.276), and there is no adhesion. |
| S5 | Collective clustering controlled by length-to-width aspect ratio | **CONFIRMED** | "controlled by the cells' length-to-width aspect ratio" (abstract). "critical κ_cr ≈ 4–5, below which the intensity of collective migration is low" (p.283). Note that a **minimal stiffness** ξ is also required (Fig. 8 right, p.282). |

---

## 5. Validation targets

Policy: agreement is statistical, over ensembles. Bitwise parity is not expected. The paper does not give lattice size, MCS definition, run lengths or sampling intervals, so I recommend comparing **shapes and trends** first, and the quantitative levels only with loose tolerances.

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| V1 | **Bent-cell relaxation.** E_curve of an artificially bent 'xanthus' cell (s = 8) decays "almost exponential[ly]" from about 120 E toward a small residual (below about 10 E) within about 5000–6000 MCS. The decay is noisy. | Fig. 2 (p.277, read from figure) | semi-quantitative | A single exponential fit to the ensemble mean has R² ≥ 0.9. The residual at 6000 MCS is below 15% of the initial value. Initial geometry is UNSPECIFIED, so match the trend only. |
| V2 | **Low T gives incomplete relaxation** | p.277 | qualitative | With kT ≪ 0.8, the plateau of E_curve is higher than at kT = 0.8. |
| V3 | **Snake-like motion with the head pinned** (ω = 0.5, ξ ≈ 300) | Fig. 3 (p.278) | qualitative | Visual: a sinusoidal body deformation develops within about 1000–2000 MCS. The pinning mechanism is UNSPECIFIED. |
| V4 | **Single-cell velocity vs κ.** About 1.90–1.91 nodes/100 MCS at κ ≈ 2.5–3.4, falling to about 1.74 at κ ≥ 14. The variation is "minimal" (s scanned; mean of 15 runs ± SD). | Fig. 5a (p.279, read from figure) | quantitative (weak) | Each κ point within ±10% of the digitised value. The curve decreases monotonically for κ ≳ 3.4. |
| V5 | **Motion efficiency vs κ.** About 0.36 (κ ≈ 2.5), 0.54 (3.4), 0.61 (4.3), 0.75 (5.2), then a plateau at about 0.68–0.73 up to κ ≈ 17. SDs are large (±0.1–0.2). | Fig. 5b (read from figure) | semi-quantitative | Rises up to κ ≈ 5, then plateaus. Values lie within the published ±1 SD bars. The path-length window is UNSPECIFIED. |
| V6 | **Single-cell trajectories** are not straight; there are random direction changes over about 10⁴ MCS | Fig. 4 | qualitative | Visual only. |
| V7 | **Collective migration at 'xanthus' parameters.** Starting from 100 random cells, a quasi-steady state is reached with aligned, co-moving clusters and "arrow-like" arrangements. | Fig. 6 (p.280) | qualitative | Visual only. Ψ̄ is clearly above the κ < 4 baseline. |
| V8 | **Ψ̄ vs κ at 30% density.** About 0.36 (κ ≈ 2.5), 0.50 (3.4), 0.79 (4.3), 0.90 (5.2), 0.89 (6.9), 0.86 (10.3), 0.78 (13.9), 0.66 (17.3) | Fig. 8 left (p.282, read from figure) | quantitative | Within ±0.1 absolute per point, or within the published error bars if those are wider. Must show the sharp rise across κ ≈ 4–5 and the decline at large κ. |
| V9 | **Ψ̄ vs κ at 20% density.** About 0.14, 0.21, 0.42, 0.61, 0.59, 0.60, 0.61, 0.53 at the same κ values | Fig. 8 left | quantitative | ±0.1 absolute. Plateau from κ ≈ 5. |
| V10 | **Ψ̄ vs κ at 10% density.** About 0.07, 0.09, 0.15, 0.21, 0.18, 0.24, 0.19, 0.21 | Fig. 8 left | quantitative | ±0.07 absolute. |
| V11 | **Critical aspect ratio** κ_cr ≈ 4–5 at all three densities. Ψ̄ plateaus for κ ≥ 5. | p.282–283; Fig. 8 caption | quantitative (threshold) | The steepest rise of Ψ̄(κ) lies within κ ∈ [3.4, 5.2] at every density. |
| V12 | **Ψ̄ vs ξ.** About 0.21 (ξ ≈ 10), 0.39 (100), 0.55 (200), 0.63 (300), 0.65 (600), 0.77 (1000), 0.70 (2000). Saturates for ξ ≥ 350 E. | Fig. 8 right (read from figure) | semi-quantitative | ±0.1 absolute. Monotone rise to ξ ≈ 300–350. The **density and κ for this panel are UNSPECIFIED** (plausibly 'xanthus', s = 8), so match the trend. |
| V13 | **Large κ at high density lowers Ψ̄** (traffic-jam deformation) | p.282–283 | qualitative | At 30% density, Ψ̄(κ ≈ 17) < Ψ̄(κ ≈ 5–7). |
| V14 | **Segments stay connected** at 'xanthus' parameters, with no annealing | p.279 | qualitative / invariant | Count disconnected segments over time. The expectation is rare and transient (the paper claims "always"). |

---

## 6. Required general features

Rule: models declare needs only through general public features. The core has no model-specific hooks.

| Need (paper) | Feature ID | Notes |
|---|---|---|
| Rod made of s sub-cells, ordered head→tail; state is (cell, segment index) | **G10** cluster scope, member lookup; **G11** ordered relationships | A "segmented cell" is a cluster whose members carry an **index** ν. Energies need predecessor/successor lookups (ν ± 1, ν ± 2). No cell-level energy term exists. **Segment extinction (D-066; `../liveness-survey.md` §5):** a segment that loses its last site through copies dies at once, and its siblings' references would read ref = 0 (medium), so the rod would silently lose a segment. The paper keeps s fixed, so the port declares `@constraint no_extinction(segment kinds…)`, and a **diagnostic counts segment deaths per run and asserts zero** (a rod must never lose a segment). |
| Per-segment area constraint λ(a − A)² | core volume term | Standard, per sub-cell. |
| Contact J depends on (medium? / same cluster? / \|Δν\| = 1?) | **G3** contact scope + **G11** relationship predicate in contact energies | Contact energy must see whether two sub-cells are in the same cluster and how far apart their indices are: J_SS for adjacent, J_CC for non-adjacent in the same cell (Eq. 6). A pure type-pair table cannot express this. |
| Length energy on consecutive segment COMs; curvature energy (circumradius) on COM triplets | **G11** ordered relationships + angle/geometry energies; **G2** shape descriptors (COM) in energies | These are 2-body (distance) and 3-body (circumradius) terms on sub-cell COMs. ΔH of a copy changes at most two COMs. The incremental update needs the terms that involve those segments (up to about 3 triplets and 2 pairs per segment). |
| COMs in "non-periodic space after projection" (unwrapped across the periodic box) | **G2/G12** periodic-aware (unwrapped) centroid | Must be consistent between energy use and observables. |
| Propulsion ΔD = −ω(d·θ_loser + d·θ_gainer), added to ΔH but not to H | **G3** copy direction d in proposal/contact scope + **G10** sibling lookup (θ from neighbour-segment COMs) | This is a non-conservative work term in the acceptance only. θ is a derived vector computed from sibling COMs (S_{ν−1} − S_{ν+1}), with head/tail inheritance. It needs no stored polarity, and no "lagged" variable is required. |
| Metropolis with kT | core | – |
| 2D **hexagonal** lattice; nearest-neighbour proposals; "second-nearest" contact shell; periodic BCs | **G14 (new, if not already core): hexagonal 2D lattice with neighbour shells** | Justification: the paper uses a hex lattice to get more movement directions (p.275). A square-lattice substitute would change the anisotropy results, so a substitute must be flagged as a deviation. |
| Random initial rods (position and orientation) at a target density; a bent single cell; 100 dropped cells | **G13** initial layout generators | Needs a "chain of s blobs of area A along a random line/arc" generator, with overlap handling (UNSPECIFIED in the paper). |
| Pinned head (Fig. 3) | **G15 (new): per-sub-cell freeze/pin** (or reuse core frozen-type support, if it can apply to one member of a cluster) | The paper does not describe the mechanism. The feature is needed only for V3. |
| Observables: E_curve(t); velocity; motion efficiency; Eqs. 11–12 cluster graph (min segment-COM distance plus head-direction angle); connected components; Ψ̄ | **G12** observables library | Needs a generic "pairwise predicate → connected components" observable over clusters, and max-component/N time averages. |
| Connectivity | **G4**: not required by the paper | The paper relies on energetics. Optional as a diagnostic (V14). |
| G1, G5, G6, G7, G8, G9 | not required | No fields, no birth/death, no conversion, no custom proposal law. |

### One abstraction for both models?

I assess this against what 13 and 14a/c actually require. A single **cluster-of-sub-cells** abstraction covers both, on four conditions:
1. Members carry a kind (14: nucleus/cytoplasm/lamellipodium) **and/or** an index (13: ν = 1..s). Relationships between members are first-class: ordered adjacency for 13, sibling-by-kind for 14.
2. Contact energy can depend on the cluster relationship between the two sub-cells: same cluster or not, kinds, and index distance. 13 needs index distance. 14 (Dal-Castel code) has separate intra- and inter-cluster tables.
3. Energies and propulsion terms can read member COMs through relationships. 13 needs this for the length, curvature and θ terms. 14 needs no COM energies, only COM observables.
4. Members may be created on demand and may die (14: the lamellipodium is created by conversion and dies if it empties; 13: never, enforced by `no_extinction`), and may exchange sites (14 conversion; 13 does not). No member is ever kept empty (D-066).

13 needs no cluster-level volume and no conversion. 14 needs no ordering. Neither of these conflicts with the shared abstraction, so a single design is sufficient. The only 13-specific geometry is the 3-point circumradius, which should be an expression over member COMs (G11) and not a core primitive.

---

## 7. Ambiguities and open questions (what we would need from the authors)

1. **Eq. 9 notation "||S_{ν−1} − S_{ν+1}||".** Is θ the unit vector (normalised chord) or the raw chord vector? The choice changes the propulsion scale by a factor of about 2D ≈ 7. It also changes the meaning of ω = 0.5 E relative to kT = 0.8 E. My best guess is normalised, because a scalar norm cannot be a direction. This must be confirmed.
2. **Eq. 7 sign.** The printed exponent appears to lack the minus sign. The spec assumes exp(−ΔH′/kT).
3. **Eq. 10 sign and loser term.** d = i − j points from source j into target i. Including d·θ_{σ(i)} for the **losing** segment (the one whose node i is overwritten) means the drive favours the loser retreating *along* d. Physically, losing node i moves the loser's COM away from i, so it moves along −(i − COM) and not along d. The printed formula should be confirmed and implemented exactly as written.
4. **"Second-nearest neighbours" for J.** Does it mean the 1st and 2nd hex shells together (12 sites) or only the 2nd shell? The spec assumes 1st+2nd, the CPM convention.
5. **MCS definition, lattice size and run lengths** (warm-up, measurement window, sampling interval for ψ). All are UNSPECIFIED. They are needed for quantitative Ψ̄ reproduction.
6. **κ(s) mapping and width definition.** κ ≈ 6 for s = 8 (p.282), but Fig. 6 says κ ≈ 10 with the 'xanthus' set. Was s changed for Fig. 6? The digitised abscissae suggest κ ≈ 0.86 s.
7. **Density and κ for Fig. 8 (right, ξ scan).** Not stated.
8. **Initial condition details.** Shape of dropped cells, overlap rules, and the bent-cell geometry for Fig. 2.
9. **Head fixation (Fig. 3).** How was it implemented?
10. **Velocity measurement interval** (Fig. 5a) and the "given total path length" for motion efficiency (Fig. 5b).
11. **Degenerate curvature.** Handling of sin∠ = 0 (straight triplets give R = ∞ and energy 0, so this is fine) and of coincident COMs, which divide by zero.
12. **Same-cell non-adjacent contact.** Eq. 6 assigns J_CC. Is that intended, or should it be J_SS or 0?
