# Proposal-law clues for the open deviations (research only, 2026-10-09)

The maintainer suspected that "some of these deviations may come from the proposal law problem
and not enough info to determine it", and asked for research before any sensitivity runs.

**Scope.**
- Read-only: the papers and the authors' and consortium code. No simulation was run.
- Source precedence (maintainer ruling, 2026-10-09): the paper is the target, and code is
  evidence for unstated details or suspected causes. For OpenVT, the manuscript wins over TST
  wherever it is accurate.

**Bottom line.**
- **Proposal law.** For every deviation examined, the papers either state a proposal law we
  already follow, or every reference implementation is equivalent to ours per MCS.
- **No sensitivity study needed.** The proposal-law study is not warranted. Each deviation has a
  better-supported lead (table below).

## 1. Summary

| Deviation | What the sources say about proposals | Ours | Proposal-law cause? | Better lead |
|---|---|---|---|---|
| Sorting V-PRE5 (late coarsening slow) | PRE p.2130: random site; copy from "one of the eight neighboring sites"; 1 MCS = 16 × lattice sites; Metropolis, ½ ties at T = 0 only | Moore(1); 1 paper MCS = 16 our MCS (spec 09 D9) | **Ruled out** (documented and matched) | n = 1 paper runs vs our bimodal replicates; unstated light:dark share and lattice size; contact-energy counting (§2.2) |
| Sorting V-PRE7 (T = 80 cell loss) | as above | as above | **Ruled out** | contact-energy counting (§2.2), weak; unstated lattice size or boundary conditions (detached cells) |
| Sorting V-PRE4 (66,850 vs ≈ 37,000 total bonds) | "total number of mismatched bonds" on the 8-neighbour lattice; counting not stated | Moore bonds, each pair once | n/a (a measurement) | most likely about 2× counting (§2.1); cancels in fractions |
| Merks V-C12 (displacement ratio 1.26 vs [1.5, 2.5]) | 01b p.11: source from "the twenty, first- to fourth-nearest neighbors"; N attempts per MCS. TST v0.1.3 is identical except 198² vs 200² attempts | NeighborOrder(4), the same 20 sites, for both energy and proposals | **Ruled out** | **displacement reference time**: Fig. 6E measures from MCS 0 (before relaxation), we measure from MCS 100 (§3) |
| OpenVT V1, V3b, rim V4.2/V4.3/V4.5 | manuscript: random neighbour, trial count ∝ lattice sites (neighbourhood unstated). TST, CC3D, Morpheus and Artistoo all use Moore(1); boundary-only samplers shrink the MCS to match | Moore(1), N attempts, exact interior skipping | **Ruled out** (all four are equivalent per MCS) | framework deviations from the manuscript, chiefly TST dividing on *target* area (§4) |
| Akeeb V-A2 | matches CC3D 4.3.1 NeighborOrder 1 exactly (cc3d-connectivity-source-check.md) | VonNeumann(1) | Ruled out | sampling noise (unchanged) |
| Foam DV1 | Jiang 1999: wall sites only, unlike neighbour only, MCS = N trials, credited to Radhakrishnan & Zacharia 1995 | uniform proposals | **Yes, by construction** (known) | needs P6.4b `UnlikeNeighbor` (unchanged) |

## 2. Cell sorting (Graner & Glazier 1992 PRL; Glazier & Graner 1993 PRE)

### 2.1 Documented conventions (all matched)
- **Site selection.** "At each step we select a lattice site at random" (PRL p.2013), with no
  boundary restriction.
- **Proposal.** One of the 8 neighbours, chosen at random (PRE p.2130). Relaxing the
  neighbour-only rule makes "essentially no change in the results" (p.2130).
- **Time.** 1 MCS = 16 × lattice sites (PRL p.2014; PRE p.2130). No reason for the 16 is given.
  Our mapping is 1 paper MCS = 16 of our MCS (spec 09 D9).
- **Acceptance.** Metropolis. The ½ rule for ΔH = 0 applies at T = 0 only.
- **Contact neighbourhood.** A second-nearest-neighbour lattice, n = 8 (PRE p.2129, 2132).

### 2.2 Pair counting
- **The Hamiltonian is written without ½ or "pairs"**, so the notation fits either convention.
- **Once-counting is more likely.**
  - The paper's own estimates are per spin over 8 neighbours: T_dd = 16 = 8 × J_dd, and "at
    most 16" for a light–light spin (p.2132–2133). These read as each bond counted once, which
    is ours.
  - Ordered-pair counting would double ΔH, and the estimates would read 2nJ.
  - The evidence is weak (order of magnitude), but it is the paper's only statement.
- **Boundary total.** Crossing bonds per unit length are:
  - Moore once: 3 (37,000, ours);
  - 12-neighbour once: 5, i.e. ≈ 1.67× (≈ 61.7k);
  - 20-neighbour once: ≈ 3.7× (ruled out);
  - Moore counted twice: 2× (≈ 74k).

  The paper's 66,850 (≈ 1.8×) is best read as twice-counting on boundaries about 10% smoother.
  Its counts come after 2–10 MCS of T = 0 annealing, and Fig. 15c shows little T dependence.
  This affects the reported total only, not the dynamics.
- **If contact ΔH were in fact doubled** (J → 2J at fixed λ, T), both V-PRE5 (faster late
  coarsening) and V-PRE7 (more loss at T = 80) would move in the paper's direction. This is
  qualitative only. Because the paper's n·J statements point the other way, it is an author
  question, not a model change.

### 2.3 What remains
- Each paper figure is one run, but our late-time largest-cluster share is bimodal per replicate
  (spec 09 §9.5).
- The light:dark share, lattice size and boundary conditions are unstated (spec 09 §8.4).
- None of these is a proposal-law question.

## 3. Merks 2008 (V-C12)

- **Proposal and energy.**
  - Both use the same 20 sites (first to fourth neighbours) in the paper (p.11, Eq. 2), in TST
    v0.1.3 (`ca.cpp` `nbh_level`, l.62/75/206) and in ours (`merks.jl`, `NeighborOrder(4)`).
  - Site selection is uniform with replacement. Null moves count.
  - The chemotaxis gate is the same (`ca.cpp:264–272`).
  - The only difference is TST's 198² attempts against the paper's 200² N, about 2%, which
    cannot move the ratio.
- **The measurement clue (Fig. 6E, page 7).**
  - The paper measures displacement "from original positions". Both curves start at 0 at t = 0,
    jump to about 20–25 µm within about 1 h, dip (CI to ≈ 22 µm, no-CI to ≈ 12 µm, by about
    5 h), then rise to ≈ 85 and ≈ 42 µm.
  - A non-monotone mean |x(t) − x(0)| means the reference is the MCS-0 state, before the
    100-MCS relaxation (≈ 0.83 h). In that window, about 17-px fragments inflate to A = 50, a
    radial outward shift of about 20 µm.
  - Measured from MCS 0, that shift adds to CI cells' outward sprouting and is mostly cancelled
    by the no-CI contraction.
  - We measure from MCS 100 (`01_merks.jl:383`). That predicts our CI value low (68 vs 85) and
    our no-CI value high (54 vs 42), which is the observed direction of both misses.
- **Caveat.** The A–D trajectories start at MCS 100, so the paper is internally ambiguous. The
  6E curve shape favours MCS 0.
- **Check, no new dynamics needed.** Rebuild σ(0) from `layout(merks2008_sprout(; seed), (202, 202))`
  and recompute `p63d_displacement(σ0, σ(19_300))` on the stored C12 snapshots (PC,
  `~/potts-ci/p6-3f-out/snap`).
  - If the ratio moves toward 2, redefine V-C12 from MCS 0 to about MCS 19,800, the paper's
    axis, under the paper-over-code rule.
  - Optionally save dense early times to reproduce the jump-and-dip.

## 4. OpenVT monolayer

### 4.1 Proposal laws: equivalent per MCS
- Interior attempts are no-ops, so each law gives every directed unlike pair the same rate of
  1/8 per MCS:
  - **CC3D:** proposal NeighborOrder 2 (Moore), uniform site, N attempts per MCS.
  - **TST:** an edge list of directed unlike pairs, `loop = |E|/n_nb`.
  - **Morpheus:** edge tracker, `updates_per_mcs = 2|E|/n_nb`.
  - **Artistoo:** border pixels, `Δt = 1/|B|` per attempt.
- Residual differences are O(1/N).
- Boundary-only sampling is always renormalised, so it cannot speed or slow growth per MCS as
  colonies grow.

### 4.2 Our model follows the manuscript (checked: `openvt_reference.jl`)
- Division at actual `volume ≥ X·A₀` (ms:97). Both daughters take half the mother's `A_star`
  and redraw `X ~ N(2, 0.4)`.
- f is Moore medium pairs over unlike pairs, matching the Fig. 4 caption.
- Adhesion is `J = [0 10; 10 20]` on Moore(1); λ = 2, T = 20, α = 50/775 (Table S1).

### 4.3 Where the frameworks depart from the manuscript (evidence for the deviations)

| Framework | Departure | Bears on |
|---|---|---|
| TST | divides on **target** area (`openvt-monolayer-type1-tst.cpp:169`); integer-truncated ΔH (`ca.cpp:620–631`); `max_cell_count = 1000` hard exit; periodic 1601² | V1 (TST divides sooner in crowded tissue, where A < A*), V3b, V4.5 |
| CC3D | contact energy at NeighborOrder 4 (20 sites); λ = 10, A* = 25; threshold not redrawn at division; Connectivity penalty 10⁵ | rim shape (V4.2/V4.3), V4.5 |
| Morpheus | J_cM = 20; λ = 20; daughters' A0 = their actual area; σ_X passed as 0.16 | rim shape, V4.5 |
| Artistoo | J_cM = 20; λ = 20, A* = 25; von Neumann free fraction | rim free surface (V4.2/V4.3) |

**Reading.**
- **V1** (10% slow to 10⁴ beyond 10³ cells) is the expected sign if TST, the reference, divides
  on target area and we divide on actual area. Under the paper-over-code rule this is a
  framework deviation, not ours.
  - Open: TST's released model hard-exits at 1000 cells. Which TST build produced the
    consortium's beyond-10³ curves should be confirmed against `results/`.
- **Rim free surface (V4.2/V4.3).** Three of four frameworks use stronger cell–medium adhesion or
  a stiffer area term than Table S1, which flattens rims. Our Table S1 parameters may simply be
  the faithful ones.
- **V4.5** (squeezed daughters). CC3D's connectivity veto, TST's last-pixel guard and Morpheus'
  daughter A0 rule all differ from the manuscript. None is in the manuscript.

## 5. Questions for the PI sheet

1. **Glazier (sorting).** Was contact ΔH in the 1992/93 code summed once per unordered bond over
   the 8 neighbours (as T_dd = 8 J_dd implies)? Was the reported total boundary length counted
   per ordered pair (about 2× our count)?
2. **Glazier (sorting).** Lattice size, boundary conditions and the light:dark share for PRE Figs.
   12–15. Why is 1 MCS 16 × lattice sites?
3. **Merks (V-C12).** Is the Fig. 6E displacement measured from MCS 0 (before the 100-MCS
   relaxation) or from the end of relaxation? Fig. 6A–D start at MCS 100.
4. **OpenVT consortium.** Which division trigger is normative: ms:97 (actual area ≥ X·A*(0)) or
   Sec. 4.1 (Ai ≥ µAmax)? TST divides on target area. Which TST build produced the beyond-10³
   curves, given `max_cell_count = 1000`?
5. **OpenVT consortium.** Are the per-framework parameter differences intentional: CC3D λ = 10 /
   A* = 25 / contact order 4, and Morpheus and Artistoo J_cM = 20 / λ = 20?

## 6. Follow-up reading (2026-10-09, maintainer: "fetch any needed papers")

**Fetched.** All open access, saved under `docs/references/background/` (gitignored):
- Mombach, Glazier, Raphael, Zajac, PRL 75:2244 (1995), UFRGS repository;
- Durand, PLoS CB 17:e1008576 (2021), the bioRxiv CC-BY preprint;
- Franke et al., arXiv:2109.00364 (2022).

**Mombach 1995.**
- 3D, on a 100³ lattice, with the method deferred to the 1993 PRE. No new convention.
- One relevant line: at T = 0 aggregates "do not evolve in time due to residual lattice
  anisotropy". This is consistent with the 8-neighbour lattice being only partly isotropic.

**Durand 2021: the most useful clue for V-PRE5.**
- **Lattice.** It confirms that GG 1992/93 used "a 2nd order neighborhood, composed of 8 lattice
  sites only". Its own runs use 20 sites to remove lattice anisotropy.
- **Late kinetics.** Late sorting in the CPM is *diffusion and coalescence of rounded clusters*
  (Γ ∼ t^(−1/4)). The last merges therefore depend on slow, stochastic cluster diffusion. That
  supports our reading of V-PRE5: the bimodal per-replicate outcome (one cluster, or two or three
  persistent domains) is intrinsic, and a single published run reaching one cluster by about 5000
  MCS can be a favourable draw.
- **Temperature.** It states that the "choice of running temperature has a strong influence on
  the cell sorting timescale". Within the small-ΔH/T regime, T only rescales time.
- **Fragmentation.** The standard algorithm fragments cells even at low T. Fragmentation "artificially
  slows down simulations", and its cost is a constant time factor.
  - GG's and our sampler both allow fragments.
  - A difference in fragment frequency, for example from the energy counting in §2.2, would show
    up as a time-scale factor, not a shape change.
- **Boundary conditions.** Periodic boundaries make spanning clusters that stop diffusing and
  change the late exponent. GG's boundary conditions are unstated (A-GG5). If the paper's lattice
  was small or periodic relative to the aggregate, late coarsening would differ. It is not
  evident that an isolated aggregate in medium, as ours is, is affected.

**Franke et al. 2022.**
- GG reported logarithmic decay. Later CPM studies find that this is the early, transitory regime,
  and that algebraic decay follows (Nakajima & Ishihara 2011: 1/3 for 50:50, 1/4 for uneven mixes;
  Durand: 1/4).
- The late-time rate depends on the type ratio. This adds weight to the unstated light:dark share
  (A-GG5) as a lever on V-PRE5.

**Holm, Glazier, Srolovitz, Grest, PRA 43:2662 (1991).** The maintainer supplied it; it is in
`docs/references/background/` as a scanned PDF and was read page by page.
- **Energy (Eq. 2).** H = J Σ over "(i,j),(i′,j′) neighbors" of (1 − δ), the same notation as the
  1993 PRE, with no ½ and no "pairs". **It does not settle once vs twice counting**, so §2.2
  stands as an author question.
- **Dynamics (p.2663).**
  - A random site is reoriented to a random new orientation (grain-growth style, not a
    neighbour copy).
  - "time is incremented by 1/N_σ Monte Carlo steps", i.e. **N attempts per MCS**.
  - GG 1992's neighbour-only copy and 16N MCS are therefore later choices of the 1992 paper,
    not inherited from this code. The reason for the 16 is still unstated anywhere read.
- **Lattice.** s(1,2), the NNN square lattice GG used, has Wulff anisotropy η = 1.116. With
  *equal* first and second neighbour bond strengths it grows normally at T = 0. With unequal
  strengths it pins (p.2667, citing Viñals & Grant). Our Moore(1) contacts use equal weights, as
  GG's did.
- **Kinetics (Fig. 1, p.2664).** "The initial stages of domain growth proceed faster with
  increasing temperature or decreasing anisotropy." Late-time growth is independent of T and of
  the lattice.
  - So T and lattice effects are early-time effects. They are unlikely to explain a *late*
    coarsening gap (V-PRE5), consistent with Durand.
- **Practice.** Holm et al. quench to T = 0 before counting and average 10 independent runs per
  curve (p.2663). The 1993 PRE shows one run per condition.

**Still unreadable.** No legal open copy exists; these are paywalled or behind a login. Not
bypassed.
- Glazier, Anderson, Grest, Phil Mag B 62:615 (1990).
- Glazier & Weaire, JPCM 4:1867 (1992).
- The 2007 *Single-Cell-Based Models* chapters.
- Radhakrishnan & Zacharia, MMTA 26:167 (1995).

These need library access or the authors.
