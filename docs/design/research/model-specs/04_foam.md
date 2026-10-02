# 04 — Sheared 2D foam (Jiang et al. 1999) — paper-grounded spec

## 1. Source

| Prefix | Citation | Identifier | PDF on disk |
|---|---|---|---|
| **04b** (primary) | Y. Jiang, P.J. Swart, A. Saxena, M. Asipauskas, J.A. Glazier, "Hysteresis and avalanches in two-dimensional foam rheology simulations", *Phys. Rev. E* **59**(5), 5819–5832 (May 1999). Received 13 Jul 1998, revised 4 Dec 1998 | **DOI 10.1103/PhysRevE.59.5819**. PII S1063-651X(99)11405-3 is printed on 04b p.5819. The DOI is not printed in the PDF; it was checked against Crossref (title, authors, vol. 59, issue 5, pp. 5819–5832 all match) | `docs/references/04b_Jiang1999_PRE_foam-rheology_published.pdf` (14 pp., **with figures**) |
| **04a** (secondary) | Same authors, "Hysteresis and Avalanches in Two Dimensional Foam Rheology Simulations" | arXiv:cond-mat/9902111v1 (9 Feb 1999) | `docs/references/04a_Jiang1999_PRE_foam-rheology_arXiv.pdf` (39 pp.; figures missing, PDF pp. 15–39 are GIF placeholders) |

- **Citation form:** (04b p.NNNN) uses the journal page number. The arXiv page is given as (04a p.N) only where it still helps. Journal page map:
  - 5819: abstract and introduction
  - 5820: introduction, Fig. 1
  - 5821: model, Eqs. 1–2
  - 5822: Eqs. 3–7, simulation details, lattices, neighbourhood
  - 5823: initialisation, Γ, J, T, T1 detection, Eq. 8, start of §IV
  - 5824: Fig. 2, periodic shear, J sweep, phase diagram, bulk shear
  - 5825: Fig. 3, disordered hysteresis
  - 5826: Figs. 4–5, zero-strain crossing note, start of §V
  - 5827: Figs. 6–7, Eq. 9
  - 5828: Fig. 8, T1 spectra
  - 5829: Figs. 9–10, N̄, sandpile comparison
  - 5830: yield strain, Fig. 11, μ2(n)
  - 5831: conclusions
  - 5832: references
- **Figure digitisation:** by eye, from 300 dpi renders of 04b (`pdftoppm -r 300`), against the printed axis ticks. Stated uncertainties are digitisation uncertainties only. Run-to-run scatter is unknown: every figure is a single run, except Fig. 3, which is averaged over 10 periods.

### 1.1 arXiv (04a) vs journal (04b) differences

A word-level diff of the two full texts (`pdftotext` + `difflib`) found **no change to physics content**:
- identical equations (1)–(9), including the ambiguous Eq. 2;
- identical figure captions and parameter values;
- identical body text apart from hyphenation and spelling ("solid like" → "solidlike", "grey" → "gray", "three fold" → "threefold").

Differences:
1. The journal adds the header, the received/revised dates and the PII. The arXiv "Contact author" line becomes a footnote.
2. **Reference renumbering.** arXiv [4] (Prud'homme, Soc. Rheol. meeting 1981) is dropped, and the constitutive-model sentence now cites only Princen [4]. So arXiv [n] = journal [n−1] for n ≥ 5. The fast-algorithm reference is arXiv [24] = **journal [23]** (Radhakrishnan & Zacharia, Metall. Mater. Trans. A 26, 167, 1995). The Khan & Armstrong "ibid" entries are merged into journal [5].
3. Figures are present only in 04b.

Typos present in **both** versions (not introduced by the journal):
- 04b p.5829–5830: "Fig. 8(c) shows a complicated trend" refers to the φ spectra, which are **Fig. 10(c)**.
- 04b p.5829: "three different foams", but Fig. 9 shows four.
- The Fig. 10(c) caption writes "μ2(N)".

---

## 2. Mechanics

### 2.1 Representation

- Square lattice. Site i = (x_i, y_i) carries a spin σ_i ∈ {1..Q}. A domain of like spins is a bubble; a link between unlike spins is a wall (04b p.5821).
- Dry-foam limit: no liquid phase or medium (04b p.5822, "we assume the dry foam limit"). Every site belongs to a bubble.
- No coarsening: every bubble has an area constraint, and there are no T2 events (04b p.5821).

### 2.2 Hamiltonian

**Eq. (1), 04b p.5821:** H = Σ_ij J_ij (1 − δ_{σi σj}) + Γ Σ_n (a_n − A_n)²
- J_ij is the coupling "between neighboring spins … summed over the entire lattice".
- a_n is the area of bubble n; A_n is its area "under zero applied stress".
- Γ is "inversely proportional to the gas compressibility". Setting Γ = 0 re-enables coarsening.

**Eq. (2), 04b p.5821 (shear driving), re-checked against the journal typesetting:** H′ = H + Σ_i γ(y_i, t) x_i (1 − δ_{σi σj})
- The sum runs over i only, and j is free. This is **exactly the arXiv form**; the journal did not fix it.
- The accompanying text says the term applies shear strain "to the wall between neighboring bubbles σ_i and σ_j", with "(x_i, y_i) [the] coordinate of spin σ_i and (1,0) … the direction of the strain" (04b p.5821). That supports a per-unlike-bond reading (a sum over neighbour pairs, as in the J term). See A-1.
- The term acts on walls only (04b p.5822).
- Sign (04b p.5822): the term "biases the probability of spin reassignment in the direction of increasing x_i (if γ < 0) or decreasing x_i (if γ > 0)". "From dimensional analysis of H′, γ has units of force."

**Boundary shear, Eq. (6), 04b p.5822:**
- γ = +γ0 G(t) for y_i = y_min;
- γ = −γ0 G(t) for y_i = y_max;
- γ = 0 otherwise.
The paper calls this "equivalent to moving the boundary of the foam with no-slip". γ0 is "the amplitude of the strain field and G(t) is a normalized function of time".

**Bulk shear, Eq. (7), 04b p.5822:** γ = β y_i G(t), with y_i between y_min and y_max. "The gradient of strain rate is the shear rate, β."
- 04b p.5824: the strain varies linearly "from γ0 at the top of the foam to −γ0 at the bottom".
- 04b p.5830: "the zero strain is in the middle of the foam".
- The velocity-profile arrows in Figs. 4(a), 5(a) and 7(a) are antisymmetric about mid-height: zero at the centre, +x at the top, −x at the bottom.
- So **y is measured from the mid-plane** (A-3 RESOLVED), and γ at the walls is ±β·L_y/2 (±6.4 for β = 0.05 on 256 rows).

**Time dependence (04b p.5822, p.5824):**
- "G(t) = 1 for steady shear, and G(t) = sin(ωt) for periodic shear."
- For periodic runs "we keep the period 2π/ω fixed and vary the amplitude, γ0".
- "A shear cycle in the periodic shear case takes about 4000 MCS" (04b p.5822).

**Strain interpretation (not an update rule):**
- Eq. (4), 04b p.5822: v ∝ √γ P. The journal typesetting confirms the square root.
- Eq. (5): ε ∝ ∫₀ᵗ √γ(t′) P dt′.
- For steady shear "the strain is a constant times time, or √γ P t", so plotting against time is equivalent to plotting against strain (04b p.5822).
- **Figure evidence for the "Strain" axis of the periodic-shear plots:** in every Fig. 3 panel, the horizontal extent of the loop is ≈ ±γ0 (±10%): ±1 for γ0 = 1, ±3.5 for 3.5, ±7 for 7, ±4 in Fig. 3(d). So in Fig. 3 **"Strain" is the applied field γ(t) = γ0 sin(ωt)**, not a measured displacement (partly resolves A-9).

### 2.3 Update rule (proposal + acceptance)

- **Proposal (04b p.5822):** "we choose a spin at random, but only reassign it if it is at a bubble wall and then only to one of its unlike neighbors." Boundary-only, unlike-neighbour-only.
- The neighbour set for "at a bubble wall" and for picking the unlike neighbour is not stated separately from the 4th-order interaction set (A-4, STILL OPEN).
- Whether a non-wall pick uses up one of the MCS "spin trials" is not stated (A-5, STILL OPEN).
- **Acceptance, Eq. (3), 04b p.5822** (typeset "P ∼" in both versions, not "P ="): P ∼ 1 if ΔH′ < 0; P ∼ exp(−ΔH′/T) if ΔH′ ≥ 0.
  - ΔH′ = 0 falls in the exponential branch. At T = 0 the value is undefined (A-6, STILL OPEN).
  - **Recommendation:** use the T → 0⁺ limit, which accepts ΔH′ = 0 moves (P = 1). This must be recorded as a choice, not as a paper fact.
- **MCS (04b p.5822):** "one MCS consists of as many spin trials as there are lattice sites". The algorithm "reproduces the same scaling as classic Monte Carlo methods … but significantly reduces the simulation time [23]".
- **Temperature:**
  - "Most of the simulations … are run at zero temperature except when we study temperature effects on hysteresis" (04b p.5823).
  - "A finite but low temperature speeds the simulations, but does not appear to change the results qualitatively" (04b p.5823).
  - The Fig. 3(d) panel titles give the finite temperatures used: **T = 0, 5, 10, 15** (at J = 3).
- **MC timing caveat (04b p.5821):** the algorithm gives "uncertainties in the relative timing of events on the order of a few percent of a Monte Carlo step".

### 2.4 Neighbourhood

"All our runs use a fourth-nearest-neighbor interaction on a square lattice, which has a lattice anisotropy of 1.03" (04b p.5822).

### 2.5 Boundary conditions and lattice

- "periodic boundary conditions in the x direction" (04b p.5822).
- y is non-periodic. Bubbles are "truncated bubbles touching the top and bottom boundaries" (04b p.5822).
  - Figs. 2(a), 4(a), 5(a) and 6(a) show straight top and bottom edges with half-height boundary bubbles.
  - **The wall type is still not stated** (frozen spins, hard edge, or special J) (A-2, STILL OPEN).
- **Ordered, boundary shear:**
  - Text: 400 × 100 lattice, bubbles 20 × 20 (04b p.5822).
  - Fig. 2 caption: 256 × 256 (04b p.5824). The Fig. 2(a) snapshots are **square**, with ≈ 16 columns of bubbles. This agrees with 256 × 256 and 16² bubbles and rules out 400 × 100 (4:1 aspect) for Fig. 2.
  - The Fig. 3 lattice is not stated and has no snapshot (A-7, partly resolved).
- **Ordered, bulk shear:** 256 × 256, 16 × 16 sites per bubble (04b p.5822). The Fig. 4(a) and 5(a) snapshots are square with ≈ 16 columns, which is consistent.
- **Disordered:** 256 × 256 "with various area distributions" (04b p.5822). The Fig. 6 and Fig. 7 captions give 256 × 256.
- **Lattice-size checks:** 1024² with 64² bubbles and 1024² with 16² bubbles gave no qualitative difference. "we used bubbles of size 16² in all the simulations reported in this paper" (04b p.5822). Taken with the Fig. 2 evidence, **the 400 × 100 / 20² statement appears to describe runs not shown**. Treat 256² with 16² bubbles as canonical for every figure.
- **New conflict (A-14, STILL OPEN): Fig. 9 bubble counts.** The foams have 180, 246, 377 and 380 bubbles (Fig. 9 caption, 04b p.5829).
  - A 256² lattice tiled with 16² bricks starts with 256 bubbles, and coarsening (§2.6) can only lower the count.
  - So 377 and 380 cannot come from the stated protocol on 256². Either smaller initial bricks or a larger lattice was used for those foams.
  - On 256², the mean areas would be about 364, 266, 174 and 172 sites.

### 2.6 Initial condition protocol (04b p.5823)

1. Partition the lattice into equal 16 × 16 squares, with offsets alternating every other row ("a brick wall arranged in common bond").
2. Run with area constraints and **no strain** at finite temperature "for a few Monte Carlo steps".
3. Lower the temperature to zero and let the pattern relax. This gives the hexagonal ordered foam.
4. Disordered foams: "continue to evolve the hexagonal pattern without area constraints at finite temperature so that the bubbles coarsen". Monitor μ2(n) and stop at the desired disorder.
5. Relax at T = 0 with area constraints, "to guarantee that they have equilibrated".

Still UNSPECIFIED in 04b (A-8, STILL OPEN):
- the anneal and coarsening temperatures;
- the "few MCS";
- the length of the T = 0 relaxation;
- how A_n is set after coarsening.

### 2.7 Fields, growth, division, death

None. Bubble number is conserved, there are no T2 events, and gas diffusion is ignored (04b p.5821–5822).

### 2.8 Observables defined in the paper

- **Stored energy φ, Eq. (8), 04b p.5823:** φ ≡ Σ_{i,j} θ(1 − δ_{σi,σj}) over neighbour pairs, with θ = 1.
  - At T = 0 the area terms are ≈ 10⁻³ of the total energy.
  - φ is plotted as φ(t)/φ(0) (04b p.5823).
  - Fig. 11(c) labels the same quantity "Stress".
  - **Note:** the figures show that φ(0) is not one common reference. Fig. 3(b) J = 10 sits flat at φ ≈ 1.027, and Fig. 7 runs at φ ≈ 0.98 < 1. Only shapes and relative amplitudes can be compared across panels, not baselines.
- **T1 detection (04b p.5823):**
  - Each bubble keeps a neighbour list. "A change in the neighbor list indicates a topological change which … has to be a T1 event."
  - A bubble's number of sides is its number of distinct neighbours. The relation for "neighbour" is UNSTATED. Use `VonNeumann(1)` (edge sharing) by default: on `Moore(1)`, bubbles touching only at a corner count as neighbours, which inflates n, μ₂(n) and T1 counts. `Moore(1)` is a variant (topology audit 2026-10-01).
  - A T1 "by definition takes one MCS" (04b p.5822).
  - **Counting unit (A-15, STILL OPEN):** the steady-bulk-shear bars in Figs. 4(b) and 5(b) take only even values (2, 4, 6, 8, 12), which suggests each T1 is counted twice (for example, once per bubble pair that loses or gains contact). The Fig. 5 inset (1-MCS resolution) shows 0.5 to 3, including half-integers.
- **Topology moments (04b p.5823):** ρ(n) is the fraction of bubbles with n sides; μ_m ≡ Σ_n ρ(n)(n − ⟨n⟩)^m. μ2(a) is the same moment for areas.
- **Power spectrum, Eq. (9), 04b p.5827:** p_N(f) = ∫dt ∫dτ e^{−ifτ} N(t) N(t+τ), with N(t) the number of T1s per time step and f in MCS⁻¹.
  - The Fig. 8 and Fig. 10 axes run from ≈ 10⁻⁵ to **0.5 = Nyquist**, so f is in **cycles per MCS** with one sample per MCS.
  - The lowest plotted f ≈ 7–8 × 10⁻⁶ in Fig. 8 implies records of ≈ 1.3 × 10⁵ MCS (about 2¹⁷).
  - The same analysis is applied to φ (Fig. 10).
  - Curves are **vertically offset** for display. Absolute S(f) levels carry no meaning.
- **N̄ (04b p.5829):** "the average number of T1 events per bubble per unit shear" (Fig. 9). The normalisation of "unit shear" is not stated (A-9).
- **Yield strain (04b p.5830):** "at which the first T1 avalanches occur", defined as "the displacement at the top boundary of the foam divided by half the height of the foam … rescaled by the average bubble width". How the displacement is measured is not stated (A-9). §3.2 gives an empirical calibration.
- **Binning:** 50-MCS bins (Fig. 2b) and 100-MCS bins (Fig. 6b). Bin widths for Figs. 4, 5 and 7 are not stated; the Fig. 5 inset is per MCS.
- **Averaging:** the hysteresis plots in Fig. 3 are "averaged over 10 periods" (04b p.5825).

---

## 3. Parameters

### 3.1 Stated (or read from figures)

| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| J_ij | 3 (default); 1, 3, 5, 10 in Fig. 3(b); 0–10 in Fig. 3(c) | energy | Wall coupling | 04b p.5823; Fig. 3 |
| Γ | 1 | energy/site² | Area constraint ("sufficiently large to enforce air incompressibility") | 04b p.5823 |
| T | 0 (default); **0, 5, 10, 15** in Fig. 3(d) | energy | Temperature | 04b p.5823; Fig. 3(d) panel titles, p.5825 |
| θ | 1 | lattice units | Wall thickness in φ | 04b p.5823 |
| γ0 (Fig. 3a, J = 3) | **1.0, 2.0, 3.5, 3.7, 5.5, 5.6, 5.7, 5.8, 7.0** (panel titles) | force (= "strain" axis units) | Periodic boundary-shear amplitude | Fig. 3(a), p.5825 |
| γ0 (Fig. 3b) | 7 | — | J sweep | Fig. 3(b) caption |
| γ0 (Fig. 3c) | 0–16 | — | Phase-diagram axis ("Shear Amplitude") | Fig. 3(c) |
| γ0 (Fig. 3d) | 4 (J = 3) | — | Temperature sweep | Fig. 3(d) caption |
| Period 2π/ω | ≈ 4000 | MCS | Periodic shear | 04b p.5822 |
| β (bulk shear) | Fig. 4: 0.01; Fig. 5: 0.05; Fig. 7: 0.01; Fig. 8(a)/10(a): 0.01, 0.02, 0.05; Fig. 8(b)/10(b): 0.001, 0.005, 0.01, 0.02, 0.05; Fig. 8(c): 0.001, 0.01, 0.05; Fig. 10(c): 0.001, 0.005, 0.01, 0.02, 0.05; Fig. 9: **1e-4**, 1e-3, 5e-3, 1e-2, 5e-2; Fig. 11(a): 0.001, 0.005, 0.01, 0.02, 0.05 | 1/length | Shear rate | curve labels in Figs. 8–11 |
| Localised → non-localised T1 transition | 1×10⁻² < \|β\| < 5×10⁻² | — | Regime boundary | 04b p.5824 |
| Relaxation time | deformed bubble in a foam ~10 MCS; single bubble "a few MCS"; cluster 10–100 MCS | MCS | — | 04b p.5822, p.5824 |
| Neighbourhood | 4th-nearest (square) | — | — | 04b p.5822 |
| Lattice (all shown figures) | 256 × 256, 16² bubbles (Figs. 2, 4, 5, 6, 7 verified by caption or snapshot aspect) | sites | 400 × 100 / 20² stated in text but not seen in any figure | 04b p.5822, p.5824, p.5827 |
| Initial brick | 16 × 16 | sites | — | 04b p.5823 |
| Initial μ2(n) range | 0.81–2.02 | — | Disordered foams | 04b p.5830 |
| Fig. 8(b)/10(b) foam | μ2(n) = 0.81, μ2(a) = 7.25 | — | — | captions p.5828–5829 |
| Fig. 8(c)/10(c) foam | μ2(n) = 1.65, μ2(a) = 21.33 | — | — | captions |
| Fig. 9 foams | 180 bubbles (μ2(n) = 1.65, μ2(a) = 21.33); 246 (1.72, 15.1); 377 (1.07, 2.50); 380 (0.95, 2.35; legend 2.36) | — | See A-14 | p.5829 |
| Fig. 11(a) foams | μ2(n) = 0 (ordered), 0.81, 1.65 | — | — | legend |
| Fig. 11(b) foams | initial μ2(n) = 0.81, 1.65, 1.72, 2.02; β not stated | — | — | legend |
| Max bubble stretch | "up to 60% of its original length" at conserved area | — | — | 04b p.5821 |
| Anneal T, anneal MCS, relax MCS | UNSPECIFIED | — | A-8 | — |
| y-boundary type / J to boundary | UNSPECIFIED | — | A-2 | — |

### 3.2 Derived (including from digitised figures)

| Quantity | Value | Derivation |
|---|---|---|
| ω | 2π/4000 ≈ 1.571 × 10⁻³ rad/MCS | From "about 4000 MCS" per cycle |
| A_n (ordered) | 256 sites | 16 × 16 bricks |
| Bubble count, ordered 256² | ≈ 256 (≈ 16 × 16 visible in the Fig. 2(a)/4(a) snapshots; the boundary rows are truncated) | 256²/16² |
| Hexagon side (16²) | ≈ 10 sites (stated) | 04b p.5822 |
| Smallest resolvable tilt | ≈ 5.7° (stated) | 04b p.5822 |
| Ordered yield-strain upper bound | 2/√3 ≈ 1.155 (stated) | 04b p.5830 |
| **Phase-diagram boundaries (Fig. 3c)** | Straight lines through the origin, so the regime depends on **γ0/J** alone. Digitised slopes γ0/J (±5% digitisation): **elastic \| viscoelastic ≈ 1.0**, **viscoelastic \| 1 T1/cycle ≈ 1.9**, **1 T1 \| ≈2 T1 ≈ 2.5**, **≈2 T1 \| ≥3 T1 ≈ 4.4** | Fig. 3(c). Cross-checks: at J = 3, Fig. 3(a) switches from butterfly to U-shape between γ0 = 5.7 and 5.8 (5.8/3 ≈ 1.93); γ0 = 2.0 is still near-flat. Fig. 3(b) at γ0 = 7 places J = 10, 5, 3, 1 in regions 1, 2, 3, 5, matching the caption |
| Why γ0/J scaling is expected | At T = 0 acceptance depends only on sign(ΔH′). If the Γ term is negligible (≈ 10⁻³ of the energy), the dynamics are invariant under J, γ → λJ, λγ | Consequence of Eq. 3; supports linear boundaries through the origin |
| Sliding-plane period, ordered bulk shear at β = 0.01 | ≈ 1250–1300 MCS between φ peaks (Fig. 4b inset, and ≈ 75 peaks over 10⁵ MCS in the main panel) | Matches the Fig. 8(a) T1-spectrum peak at f ≈ 8 × 10⁻⁴ MCS⁻¹, with a harmonic at ≈ 1.6 × 10⁻³ (1/1275 ≈ 7.8 × 10⁻⁴) |
| Boundary-shear yield period, ordered (Fig. 2b) | ≈ 615 ± 30 MCS between φ peaks (peaks at ≈ 450, 1120, 1780, 2370, 2970, 3580, 4230, 4760 MCS) | Fig. 2(b) |
| Yield-strain calibration, ordered bulk shear | ε_yield ≈ c·β·t_firstT1 with **c ≈ 0.020–0.026 MCS⁻¹·β⁻¹**: β = 0.01, first T1 ≈ 4300 MCS, ε = 1.11; β = 0.05, first T1 ≈ 420 MCS, ε = 0.43 | Figs. 4(b), 5(b), 11(a). The ≈ 25% mismatch between the two estimates marks the limits of this calibration |
| γ at the walls under bulk shear | ±β·128 = ±1.28 (β = 0.01), ±6.4 (β = 0.05) | Eq. 7 with y from the mid-plane, L_y = 256 |
| Mean area, Fig. 9 foams (if 256²) | 364, 266, 174, 172 sites | 65536 / N_bubbles (see A-14) |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence / correction |
|---|---|---|---|
| 1 | H = ΣJ(1−δ) + ΓΣ(a−A)² + Σγ(y,t)·x·(1−δ) | CONFIRMED | Eqs. 1–2, 04b p.5821. The shear-term index structure is unchanged in the journal and still ambiguous (A-1) |
| 2 | J = 3, Γ large | CORRECTED | J = 3 (04b p.5823). **Γ = 1**, "sufficiently large" (04b p.5823) |
| 3 | Boundary shear γ = ±γ0 G(t) on the y_min/y_max rows | CONFIRMED | Eq. 6, 04b p.5822 |
| 4 | Bulk shear γ = β y G(t) | CONFIRMED | Eq. 7, 04b p.5822. y is measured from the mid-plane (04b p.5830; arrow profiles in Figs. 4a, 5a, 7a) |
| 5 | G = 1 or sin(ωt), ~4000 MCS/cycle | CONFIRMED | 04b p.5822 |
| 6 | Only wall sites proposed, only to unlike neighbours | CONFIRMED | 04b p.5822 |
| 7 | 4th-order neighbours | CONFIRMED | 04b p.5822 |
| 8 | Periodic x, walls in y | CONFIRMED (x) / NOT IN PAPER (y wall type) | 04b p.5822. The snapshots show straight y edges; the type is unstated |
| 9 | 400×100 with 20² bubbles, or 256² with 16² | CORRECTED | Every shown figure is 256² with 16² bubbles (Fig. 2 caption and snapshot aspect; 04b p.5822, "16² in all the simulations reported") |
| 10 | Brick-wall initial condition annealed to T = 0 | CONFIRMED | 04b p.5823 |
| 11 | T sweep in Fig. 3(d) | CONFIRMED + VALUES | T = 0, 5, 10, 15 at J = 3, γ0 = 4 (Fig. 3d) |
| 12 | Elastic → viscoelastic → fluid regimes | CONFIRMED | 04b p.5824; Fig. 3 |
| 13 | Yield strain vs J phase diagram (Fig. 3c) | CORRECTED | Fig. 3(c) is a **hysteresis-regime diagram in (J, γ0)** with **five** shaded regions (elastic, viscoelastic, then three flow regions with increasing loop complexity) and linear boundaries through the origin. Yield strain vs β is **Fig. 11(a)** |
| 14 | T1 rate ∝ strain rate | CORRECTED | That is the Gopal & Durian experiment (04b p.5820). In Fig. 9, N̄ falls ≈ 10× from β = 10⁻⁴ to 10⁻³, so at low β the T1 rate per MCS (N̄·β) is roughly **constant**, not ∝ β. It is roughly β-independent in N̄ only at large β (04b p.5829) |
| 15 | Avalanche statistics broaden with disorder μ2(n) | CORRECTED | Non-monotone. T1 spectra go from white toward 1/f with disorder and rate (Fig. 8b, α ≈ 0.95 at β = 0.05). The very disordered foam (μ2(n) = 1.65) shows no power law (Fig. 8c) |

**Tally:** 9 CONFIRMED (#1, 3, 4, 5, 6, 7, 10, 11, 12), 5 CORRECTED (#2, 9, 13, 14, 15), 1 partly NOT IN PAPER (#8). #9 moved from "confirmed with conflict" to CORRECTED on the published figures.

---

## 5. Validation targets (figure-grounded)

**Policy:** performance over exactness. Targets are ensemble or statistical, over ≥ 5 seeds unless stated. There is no bitwise or trajectory parity. The paper's curves are single runs (Fig. 3 averages 10 periods), so paper-derived tolerances are loose.

Classes:
- **Q** = qualitative (shape or ordering only);
- **SQ** = semi-quantitative (numbers within wide bands);
- **QN** = quantitative (a number with a tolerance).

Because φ(0) normalisation differs between panels (§2.8), **no target uses an absolute φ baseline**; they use amplitudes and ratios.

### 5.1 Per-figure digitised data

**Fig. 1** (04b p.5820): schematic of a T1. No data.

**Fig. 2** (04b p.5824): ordered foam, steady boundary shear.
- Conditions: 256², 16² bubbles, J = 3, T = 0 (defaults). γ0 not stated. G = 1.
- (a) Three snapshots; top boundary moves +x, bottom −x. 5- and 7-sided bubbles appear only in the top and bottom boundary rows.
- (b) x = time, 0–5000 MCS. Left y = T1 count per 50-MCS bin (0–40). Right y = φ/φ(0) (ticks 1, 1.01).
- φ climbs from ≈ 0.999 to a first peak ≈ 1.012 at ≈ 450 MCS. It then forms a sawtooth: peaks rise slowly (1.012 → ≈ 1.017, the "slow long-time accumulation" of 04b p.5831) and troughs sit at ≈ 1.002–1.006.
- Drop amplitude per cycle ≈ 0.008–0.012. Period ≈ 615 MCS (8 cycles in 5000 MCS).
- The first T1s appear at ≈ 350–400 MCS.
- Each T1 burst lasts ≈ 250–300 MCS (5–7 bins), peaks at 20–31 per bin, and totals ≈ 80–100 counted T1s per burst. There are no T1s between bursts.
- Uncertainty: φ ±0.001, t ±30 MCS, counts ±1.

**Fig. 3** (04b p.5825): ordered foam, periodic boundary shear, averaged over 10 periods. Axes: x = "Strain" = γ(t) (§2.2), y = φ.
- **(a) J = 3, γ0 sweep:**
  - γ0 = 1.0: a flat segment at φ ≈ 0.998, loop height < 0.001.
  - γ0 = 2.0: nearly flat, height ≈ 0.001–0.002.
  - γ0 = 3.5: butterfly, φ ∈ [0.988, 1.006] (height ≈ 0.018).
  - γ0 = 3.7: [0.986, 1.009].
  - γ0 = 5.5: [0.975, 1.013].
  - γ0 = 5.6: [0.980, 1.011].
  - γ0 = 5.7: [0.978, 1.014], still butterfly.
  - γ0 = 5.8: **U-shape**, [0.994, 1.038].
  - γ0 = 7.0: U-shape with sharp spikes at the strain extremes, [0.99, 1.045].
  - Loop x-extent ≈ ±γ0.
  - Butterfly branches cross near zero strain (04b p.5826 explains this as an artefact of φ being orientation-blind).
- **(b) γ0 = 7, J sweep** (x ±10):
  - J = 10: flat line at ≈ 1.027.
  - J = 5: butterfly, [1.013, 1.027].
  - J = 3: U-shape, trough ≈ 1.015–1.022, spikes to ≈ 1.043.
  - J = 1: V/U shape, [1.004, 1.044], with small secondary loops on both wings.
- **(c) Phase diagram:** x = coupling strength J (0–10), y = shear amplitude γ0 (0–16). Five regions with linear boundaries through the origin; slopes in §3.2.
  - Region insets: flat line (elastic), butterfly (viscoelastic), U crossing (one T1), U with one small wing loop per side, U with two small wing loops per side.
  - Built from 44 simulations (04b p.5824).
- **(d) J = 3, γ0 = 4, T = 0, 5, 10, 15** (x ±4):
  - Mean φ ≈ 1.015, 1.067, 1.142, 1.225.
  - Loop half-height ≈ 0.008, ≈ 0.006, comparable to the noise (± 0.005), and fully masked by noise (± 0.006), respectively.
  - Mean φ rises roughly linearly with T: Δφ ≈ +0.014 per unit T.

**Fig. 4** (04b p.5826): ordered foam, steady bulk shear, β = 0.01.
- (a) The defects (5/7 pairs) lie in **one row at mid-height**.
- (b) x = time, 0–10⁵ MCS (inset 0–2 × 10⁴). Left = T1s (0–8). Right = φ (1–1.02).
- φ rises linearly from ≈ 0.998 to ≈ 1.0135 at ≈ 4200 MCS.
- It then oscillates with peaks 1.013–1.016 and troughs 1.009–1.011. Drop amplitude ≈ 0.003–0.005, **about 2.5× smaller than in Fig. 2**; the baseline is higher (04b p.5824).
- Period ≈ 1250–1300 MCS. The first T1 appears at ≈ 4300 MCS.
- T1 bars take the value 2, occasionally 4, clustered in bursts at each φ drop.

**Fig. 5** (04b p.5826): ordered foam, steady bulk shear, β = 0.05.
- (a) The defects spread through the bulk.
- (b) x = 0–3000 MCS. Left = T1s (0–15). Right = φ (1–1.15).
- φ jumps to ≈ 1.05 within the first tens of MCS, rises to ≈ 1.115 at ≈ 550 MCS, dips to ≈ 1.095, wanders between 1.095 and 1.11 until ≈ 2400 MCS, then climbs to ≈ 1.13 by 3000 MCS. It is not periodic.
- The first T1 appears at ≈ 400–420 MCS. After that, T1s occur almost every MCS: 2–4 typical, 6–8 bursts, maximum ≈ 12.
- The inset (500–600 MCS, per MCS) shows 0–3 T1s per MCS and φ fluctuating ±0.005.

**Fig. 6** (04b p.5827): disordered foam, steady boundary shear, 256².
- (a) Snapshots; bubbles in the interior also change topology.
- (b) 100-MCS bins, 0–5000 MCS. Left = T1s (0–100). Right = φ (ticks 1, 1.01).
- The **first bin has ≈ 88 T1s**, so the yield strain is 0.
- Later bins hold 10–60 (mean ≈ 40 for t < 2500, ≈ 25 afterwards).
- φ fluctuates between ≈ 1.010 and 1.0145, with no sawtooth.

**Fig. 7** (04b p.5827): disordered foam, steady bulk shear, β = 0.01, 256².
- x = 0–2 × 10⁴ MCS. Left = T1s (0–3). Right = φ (0.97–0.99).
- **φ < 1 throughout.** It starts ≈ 0.99, drops to ≈ 0.979 by 10³ MCS, sits at 0.977–0.981 until ≈ 1.1 × 10⁴, then at 0.981–0.985.
- T1 bars are mostly 2, with occasional ≥ 3, and intermittent throughout. No periodicity.

**Fig. 8** (04b p.5828): T1 power spectra.
- Axes: log–log, f ∈ [≈ 7 × 10⁻⁶, 0.5] MCS⁻¹, S(f) in arbitrary units with offset curves.
- **(a) Ordered, β = 0.01 / 0.02 / 0.05:**
  - β = 0.01: shallow decline plus a **sharp peak at f ≈ 8 × 10⁻⁴** (harmonic ≈ 1.6 × 10⁻³).
  - β = 0.02: flat (white) to ≈ 7 × 10⁻⁴, a small bump there, then a gentle decline.
  - β = 0.05: **f^−1.0 guide line** fits from ≈ 10⁻⁵ to ≈ 10⁻² (≈ 3 decades), flattening above ≈ 2 × 10⁻².
  - Low-f ringing (dips at ≈ 3 × 10⁻⁵, 5 × 10⁻⁵, …) is a finite-record/window artefact.
- **(b) Disordered, μ2(n) = 0.81, β = 0.001–0.05:**
  - β = 0.05: **f^−0.95 guide** from ≈ 10⁻⁵ to ≈ 5 × 10⁻³.
  - Low-f slope magnitude decreases monotonically with β. My estimate: α ≈ 0.95, ≈ 0.7, ≈ 0.6, ≈ 0.3, ≈ 0.1 for β = 0.05, 0.02, 0.01, 0.005, 0.001 (±0.2).
  - All flatten at high f.
- **(c) Very disordered, μ2(n) = 1.65, β = 0.001 / 0.01 / 0.05:**
  - β = 0.001 and 0.01: essentially flat, with noisy dips.
  - β = 0.05: a steep drop from 10⁻⁵ to 10⁻⁴ (ringing), a weak slope (≈ 0.3–0.5) to ≈ 10⁻¹, then a sharp drop.
  - The paper says "no power law".

**Fig. 9** (04b p.5829): N̄ vs shear rate. x = shear rate (log, 10⁻⁴–10⁻¹); y = N̄ (linear 0–10; inset log 10⁻³–10¹). Digitised values:

| β | 180 bubbles, μ2(a) = 21.3 | 246, 15.1 | 377, 2.5 | 380, 2.36 |
|---|---|---|---|---|
| 1e-4 | 9.0 | 8.2 | 6.2 | 6.1 |
| 1e-3 | 0.9 | 0.8 | 0.7 | 0.6 |
| 5e-3 | 0.17 | 0.14 | 0.013 | 0.005 |
| 1e-2 | 0.14 | 0.12 | 0.011 | 0.003 |
| 5e-2 | 0.03 | 0.013 | 0.006 | 0.002 |

Uncertainty: ±5% in the linear panel; ±0.15 decade in the inset. Observations:
- Between β = 5 × 10⁻³ and 5 × 10⁻², N̄ separates by **one to two decades** between the high-μ2(a) pair and the low-μ2(a) pair.
- Ordering by μ2(a) holds at every β.

**Fig. 10** (04b p.5829): φ power spectra (same runs as Fig. 8; (c) has five rates).
- (a) Ordered: **f^−0.81 guide** on β = 0.05. β = 0.01 shows the ≈ 8 × 10⁻⁴ peak.
- (b) μ2(n) = 0.81: **f^−0.80 guide** on β = 0.05 (≈ 10⁻⁴–10⁻²). All five rates show similar negative slopes.
- (c) μ2(n) = 1.65: an **f^−0.8 guide** on β = 0.05 (≈ 10⁻⁴–10⁻²), and an unlabeled straight line on β = 0.005 spanning ≈ 3 × 10⁻⁵ to 0.5 (the text's "f^−0.8 spanning over four decades", 04b p.5830).
- Nowhere f^−2.

**Fig. 11** (04b p.5830):
- **(a) Yield strain vs β** (0–0.05):

| β | ordered (μ2(n) = 0) | μ2(n) = 0.81 | μ2(n) = 1.65 |
|---|---|---|---|
| 0.001 | 1.13 | 0.51 | 1.05 |
| 0.005 | 1.10 | 0.12 | 0.20 |
| 0.01 | 1.11 | 0.00 | 0.01 |
| 0.02 | 0.80 | — | 0.00 |
| 0.05 | 0.43 | — | 0.00 |

  Uncertainty ±0.02.
- **(b) μ2(n)(t)**, 0–10⁴ MCS, constant bulk shear, β not stated:
  - initial 0.81 (plotted start ≈ 0.9) → ≈ 1.5 by 1000 MCS, then 1.3–1.55;
  - 1.65 → overshoot ≈ 3.1 at ≈ 1700 MCS, then 2.3–2.8;
  - 1.72 → ≈ 1.9–2.15;
  - 2.02 → ≈ 2.1–2.5.
  - None returns to its initial value.
- **(c) Ordered, β = 0.01** (same run as Fig. 4 inset), 0–2 × 10⁴ MCS:
  - left "Stress" (= φ, 1–1.02); right μ2(n) (0.44–0.50).
  - **μ2(n) baseline ≈ 0.437**, not 0: truncated boundary bubbles, even though the Fig. 11(a) legend says μ2(n) = 0.
  - Rectangular excursions to 0.46–0.50, each ≈ 300–600 MCS long, coincide with the φ-drop phases.

### 5.2 Target table

| ID | Target | Source | Class | Acceptance (ensemble) |
|---|---|---|---|---|
| V1 | Brick-wall 16² → brief finite-T anneal → T = 0 relaxation gives an all-hexagonal interior | 04b p.5823; Fig. 2(a) first panel | Q | ≥ 95% of interior bubbles have n = 6 |
| V1b | Ordered 256² foam: μ2(n) baseline from truncated boundary rows | Fig. 11(c) | SQ | μ2(n) of the relaxed ordered foam ∈ [0.3, 0.6] (paper ≈ 0.44). Depends on the y-boundary choice (A-2) |
| V2 | Ordered, steady boundary shear: defects only in the boundary rows; φ sawtooth; almost simultaneous boundary T1 bursts | Fig. 2 | SQ | (i) interior (rows 2..N−1) keep n = 6 in > 95% of frames. (ii) φ is periodic, with drop amplitude 0.5–2% of φ. (iii) **T1s occur only in bursts** separated by quiet intervals, with ≥ 3 bursts in 5 periods. The period in MCS depends on γ0 (unstated), so no absolute period target |
| V3 | Periodic boundary shear, J = 3: loop shape vs γ0 (flat → butterfly → U-shape) with the transition γ0 ≈ 5.7–5.8 | Fig. 3(a) | SQ | Averaged over 10 periods and ≥ 5 seeds: γ0 = 1: loop height < 0.2% of φ, zero T1s. γ0 = 3.5: butterfly, zero T1s per cycle, loop height 1–3%. γ0 = 7: ≥ 1 T1 per cycle (paper: 1), U-shape with the maxima of φ at \|strain\| > 0.8 γ0. Transition γ0 (first cycle with ≥ 1 T1) within 5.8 ± 1.2 (±20%) |
| V4 | J sweep at γ0 = 7: J = 10 elastic, 5 viscoelastic, 3 one T1, 1 several T1s per cycle | Fig. 3(b) | SQ | Median T1s/cycle over seeds: 0, 0, 1–2, ≥ 2, monotone non-increasing in J |
| V5 | Regime boundaries in (J, γ0) are straight lines through the origin, with slopes ≈ 1.0, 1.9, 2.5, 4.4 | Fig. 3(c) | SQ | Scan J ∈ {1, 3, 5, 10} × γ0 grid. Each boundary fits γ0 = s·J with the intercept ≤ 10% of the range. Elastic slope s1 ∈ [0.7, 1.4]; first-T1 slope s2 ∈ [1.4, 2.5]. Higher boundaries are Q only (order preserved) |
| V6 | T sweep at J = 3, γ0 = 4: mean φ rises with T and the loop becomes noise-dominated | Fig. 3(d) | SQ | Mean φ monotone in T ∈ {0, 5, 10, 15}. Loop area / noise ratio > 3 at T = 0 and < 1 at T = 15. The ≈ 1.4% per unit T slope is a soft check (±50%) |
| V7 | Ordered bulk shear, β = 0.01: one sliding plane at mid-height; periodic φ; drops smaller than in V2; T1 spectrum peak | Figs. 4, 8(a) | SQ | (i) ≥ 90% of non-hexagonal bubble-frames lie within ±1 bubble row of mid-height. (ii) The φ drop amplitude is ≤ 0.6× the V2 amplitude. (iii) The T1 spectrum has a peak at f* = 1/(period) with 5 × 10⁻⁴ < f* < 1.5 × 10⁻³ (paper 8 × 10⁻⁴) |
| V8 | Ordered bulk shear, β = 0.05: delocalised T1s; non-periodic φ; T1s near-continuous after yield | Fig. 5 | Q / threshold | The fraction of non-hexagonal bubbles away from the mid-plane is > 50% after yield. The localisation index switches between β = 0.01 and 0.05 |
| V9 | Disordered foam, boundary shear: zero yield strain; T1s in the first bin; no sawtooth | Fig. 6 | Q | For the broad-distribution foam, T1s occur within the first 100 MCS in ≥ 80% of seeds |
| V10 | T1 spectra, ordered bulk shear: 0.01 peaked, 0.02 white, 0.05 ~ f^−1 | Fig. 8(a) | SQ | Low-f log–log slope (fit over 10⁻⁴–10⁻²) at β = 0.05: α ∈ [0.7, 1.3]. At β = 0.02: \|α\| < 0.3. Peak for β = 0.01 as in V7 |
| V11 | Disordered (μ2(n) ≈ 0.8): the T1 spectral exponent grows with β | Fig. 8(b) | SQ | α(β) monotone non-decreasing over {0.001, 0.005, 0.01, 0.02, 0.05} (Spearman ρ ≥ 0.8). α(0.05) ∈ [0.7, 1.2]. α(0.001) < 0.4 |
| V12 | Very disordered (μ2(n) ≈ 1.65): no T1 power law at any β | Fig. 8(c) | Q | No fit range of more than 1 decade with α > 0.5 |
| V13 | φ spectra are 1/f-like, never f^−2 | Fig. 10 | SQ | For all runs, fitted α_φ over 10⁻⁴–10⁻² ∈ [0.5, 1.2] (paper 0.8–0.81), with α_φ < 1.5 everywhere. The μ2(n) = 1.65, β = 0.005 slope holds over ≥ 2 decades |
| V14 | N̄(β): steep fall with β; separation by μ2(a) | Fig. 9 | SQ | For each foam: N̄(1e-4)/N̄(1e-3) ∈ [4, 25] (paper ≈ 10). N̄(1e-3)/N̄(5e-2) ≥ 10. At β ≥ 5e-3, N̄(high-μ2(a) foam) / N̄(low-μ2(a) foam) ≥ 5 (paper 10–70). The absolute N̄ depends on the unit-shear convention (A-9) and on the T1 counting unit (A-15), so it is not a target |
| V15 | Yield strain vs β and disorder | Fig. 11(a) | SQ | Ordered: ε_y(0.001 … 0.01) roughly constant (spread ≤ 10%) and ≤ 1.155; ε_y(0.05)/ε_y(0.01) ∈ [0.25, 0.6] (paper 0.39); ε_y > 0 at every β. Disordered: ε_y ≤ 0.05 at β ≥ 0.01. The absolute scale needs the A-9 calibration: use c from §3.2 or report ratios only |
| V16 | No shear-induced ordering: μ2(n) rises and stays above its initial value | Fig. 11(b) | SQ | For initial μ2(n) ∈ {0.8, 1.65, 1.7, 2.0}: the time-average of μ2(n) over [2000, 10⁴] MCS exceeds the initial value by ≥ 0.1 in ≥ 80% of seeds (paper: +0.3 to +0.9) |
| V17 | μ2(n) excursions coincide with φ drops (ordered, β = 0.01) | Fig. 11(c) | SQ | ≥ 80% of μ2(n) excursions (> baseline + 0.01) overlap a φ-decreasing phase. (Replaces the earlier Pearson > 0.5 target: the μ2(n) signal is rectangular and spiky, not sinusoidal) |
| V18 | No system-wide avalanches | 04b p.5828 | Q | The maximum fraction of bubbles changing neighbours within one 100-MCS window is < 0.5 |
| V19 | Area-term energy ≈ 10⁻³ of the total at T = 0 | 04b p.5823 | QN | Ratio < 5 × 10⁻³ |
| V20 | Bulk-shear φ drop ratio: ordered boundary shear vs ordered bulk shear at β = 0.01 | Figs. 2(b), 4(b) | SQ | Drop amplitude (bulk) / drop amplitude (boundary) ∈ [0.2, 0.6] (paper ≈ 0.4) |

**Not usable as targets:**
- absolute φ baselines (normalisation differs, §2.8);
- absolute time to first T1 in the boundary-shear runs (γ0 for Fig. 2 and Fig. 6 not stated);
- Fig. 7's φ < 1 (unexplained; see A-16).

---

## 6. Required general features

| ID | Needed? | Use |
|---|---|---|
| G1 | No | No creation, retirement or transitions |
| G2 | No | Only area and contact terms |
| **G3** contact-scope position | **Yes** | The shear term per unlike bond uses the site coordinates (x_i, y_i), and possibly j's, or the copy displacement x_i − x_j (A-1, A-10). Needs position in contact scope. Periodic x makes absolute x discontinuous at the seam |
| G4 | No | — |
| G5, G6 | No | No fields |
| G7 | No | — |
| **G8** pluggable proposal law + time | **Yes** | (a) Boundary-only, unlike-neighbour-only proposals. (b) sin(ωt) time dependence. (c) T = 0 acceptance with an explicit ΔH′ = 0 policy |
| G9 | No | — |
| G10 | Maybe | Per-bubble neighbour lists (better as G12) |
| G11 | No | — |
| **G12** observables | **Yes** | φ (Eq. 8). Per-bubble neighbour list and n. T1 detection with a **configurable counting unit** (A-15). ρ(n), μ2(n), μ2(a). Per-MCS series for spectra (f in cycles/MCS, Nyquist 0.5). N̄. Yield-strain detection (first T1 avalanche) |
| **G13** initial layouts | **Yes** | Brick-wall ("common bond") tiling |
| **G16 (new)** explicit time in energy terms | Yes | γ(y, t) = γ0 sin(ωt) or β y sin(ωt). Merge into G8 if G8's time scope is general |
| **G17 (new)** multi-phase protocol | Yes | Anneal at T > 0, then T = 0 relax, then coarsen (Γ = 0) stopped by a μ2(n) target, then reset A_n and relax at T = 0 |
| **G18 (new)** row-restricted energy terms | Probably covered by G3 | Eq. 6 applies only on the y_min/y_max rows |

---

## 7. Ambiguities and open questions (status after reading 04b)

- **A-1 Shear-term indexing and γ0 scale — STILL OPEN (partly narrowed).**
  - Eq. 2 in 04b p.5821 is typeset exactly as in 04a: Σ_i with a free j. The accompanying text ("to the wall between neighboring bubbles σ_i and σ_j") favours a **per-unlike-bond** reading.
  - A literal absolute-x_i reading makes the per-bond cost γ·x_i, which grows with x up to 256. The effective surface tension would then vary across the lattice, and the regime could not depend on γ0/J alone.
  - Fig. 3(c) shows regime boundaries that are **straight lines through the origin in (J, γ0)**, with elastic onset at γ0 ≈ J. This points to a **position-independent per-flip bias of order γ0**, comparable to J.
  - **Recommended implementation (a documented deviation, not paper fact):** a copy of σ_j into site i adds ΔH_shear = γ(y_i, t)·(x_i − x_j), using the minimum-image displacement. The sign is chosen so that the top boundary moves +x (§2.2).
  - Calibrate the γ0 scale against V3 and V5 (transition γ0/J ≈ 1.9) rather than from the equation. Asking the authors would still settle it.
- **A-2 y-boundary type — STILL OPEN.** The snapshots show straight edges and truncated boundary bubbles; the type is not stated. It affects V1b (μ2(n) baseline ≈ 0.44).
- **A-3 y origin for bulk shear — RESOLVED (04b p.5830; Figs. 4a, 5a, 7a).**
  - y is measured from the mid-plane: "the zero strain is in the middle of the foam", and the arrow profiles are antisymmetric.
  - The residual sign clash between Eq. 6 (+γ0 at y_min) and Eq. 7 (+ at the top for β > 0) is **immaterial**: every figure shows the top moving +x and the bottom −x, and all targets are reflection-symmetric. Fix the sign to reproduce the arrows.
- **A-4 Proposal neighbour set — STILL OPEN.** 04b p.5822 is unchanged.
- **A-5 Trial counting — STILL OPEN.** Unchanged. Because of this, and A-1, targets avoid absolute MCS timings: V3/V4 use cycles, V7 uses a spectral-peak band, and V14 uses ratios.
- **A-6 T = 0 with ΔH′ = 0 — STILL OPEN.** Eq. 3 is typeset "P ∼" in both versions and puts ΔH′ = 0 in the exponential branch. The recommendation (§2.3) is to accept, as the T → 0⁺ limit, and to flag it as a choice.
- **A-7 Lattice/bubble-size conflict — RESOLVED for all shown figures (04b p.5822, p.5824).**
  - Fig. 2 is 256² by caption and by its square snapshot; Figs. 4–7 are 256². "16² in all the simulations reported".
  - The 400 × 100 / 20² statement matches no shown figure. The Fig. 3 lattice is unstated; assume 256².
- **A-8 Annealing and disorder protocol numbers — STILL OPEN.**
- **A-9 Strain axis, "unit shear" and yield-strain measurement — PARTLY RESOLVED.**
  - Fig. 3's "Strain" axis is γ(t) itself (loop extents ≈ ±γ0), so V3–V6 need no prefactor.
  - The steady-shear plots use time (MCS).
  - Still open: the prefactor in ε ∝ √γ P t, the displacement measurement behind the yield strain, and the "unit shear" in N̄.
  - Empirically, ε_yield ≈ (0.020–0.026)·β·t_firstT1 for the ordered bulk-shear runs (§3.2).
- **A-10 Periodic x with an x-proportional energy — STILL OPEN.** Not discussed in 04b. It disappears under the displacement form recommended in A-1.
- **A-11 Fig. 3(b) caption wording — STILL OPEN (confirmed present in 04b p.5825).** "Progressively decreasing liquid viscosity (increasing J_ij …)" contradicts "Smaller coupling strength corresponds to lower viscosity" (04b p.5824). The figure data are unambiguous (J = 10 flat … J = 1 multi-loop).
- **A-12 T values and run lengths — PARTLY RESOLVED.**
  - Fig. 3(d) uses T = 0, 5, 10, 15.
  - Plotted run lengths: Fig. 2, 5000 MCS; Fig. 4, 10⁵; Fig. 5, 3000; Fig. 6, 5000; Fig. 7, 2 × 10⁴; Fig. 11(b), 10⁴; Fig. 11(c), 2 × 10⁴.
  - The spectral records are ≈ 1.3 × 10⁵ MCS (Fig. 8 lower f bound).
  - The γ0 for the steady boundary-shear runs (Figs. 2, 6) and the β for Fig. 11(b) remain unstated.
- **A-13 Figures unavailable — RESOLVED.** 04b contains all figures (§5.1).
- **A-14 (new) Fig. 9 bubble counts vs protocol — STILL OPEN.** 377 and 380 bubbles exceed the 256 obtainable by coarsening 16² bricks on 256². Either the lattice or the brick size differed for those foams.
- **A-15 (new) T1 counting unit — STILL OPEN.** The steady-shear T1 bars are even integers (Figs. 4b, 5b), which suggests double counting per T1. Make the unit configurable and compare ratios only.
- **A-16 (new) φ/φ(0) < 1 in Fig. 7 — STILL OPEN.** The disordered bulk-shear run sits at 0.977–0.985. This suggests φ(0) was taken before the final T = 0 relaxation, or that the sheared state has shorter total wall length. Unexplained.
- **A-17 (new) Text vs figure inconsistencies — STILL OPEN (documented).**
  - (i) 04b p.5827 says the ordered yield strain "remains almost the same" from β = 0.01 (Fig. 4) to 0.05 (Fig. 5), but Fig. 11(a) gives 1.11 → 0.43. The first-T1 times (≈ 4300 vs ≈ 420 MCS) agree with Fig. 11(a).
  - (ii) Fig. 11(a) at β = 0.001 has the more disordered foam (μ2(n) = 1.65, ε ≈ 1.05) yielding later than μ2(n) = 0.81 (ε ≈ 0.51). This contradicts "decreases drastically to zero as disorder increases" (04b p.5830) at the lowest rate; it holds at β ≥ 0.005.
  - V15 therefore asserts disorder monotonicity only at β ≥ 0.01.
