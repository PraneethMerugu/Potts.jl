# 12 — Zajac, Jones & Glazier 2000/2003 convergent extension: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** convergent extension by anisotropic differential adhesion. This is a CPM with
  a per-cell elongation and axis entering the contact energy (12b). The tutorial is labelled
  a **reconstruction**: almost every numeric parameter is missing and the 2002 thesis is
  not available (12 §3, §7 A-Z2; README §4.9 Z2).
- **Papers:**
  - M. Zajac, G.L. Jones, J.A. Glazier, *PRL* **85**, 2022 (2000), arXiv:physics/9912038.
    Analytic only.
  - *J. Theor. Biol.* **222**, 247–259 (2003). The CPM.
- **Spec:** [`../12_zajac_convergent_extension.md`](../12_zajac_convergent_extension.md).
  Decisions Z1–Z3 in README §4.9 and D-051 item 3 (the exact per-copy form is the
  reference). Build step 7 (ROADMAP P6.7).
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature, and `# [NEW]` means a feature not on the
roadmap. Untagged lines use syntax that exists today.

## 1. Sketch

```julia
using Potts

const UNSPECIFIED = NaN   # every value so marked is absent from 12b (12 §3, §7 A-Z2); the tutorial must choose it

@potts_model ZajacConvergentExtension begin
    @structural_parameters begin
        lattice = (200, 200)   # UNSPECIFIED (12 §3: a "wide border" of medium): placeholder
        lagged = false         # Z1: exact per-copy axes (default, D-051 item 3) | lagged per-MCS director
    end
    @kinds medium cell
    @parameters begin
        J[kind, kind] = [0.0 UNSPECIFIED; UNSPECIFIED UNSPECIFIED]   # J_cM, J_cc > 0 (12 §2.2 Eq 1; §3 "positive couplings")
        α = UNSPECIFIED        # anisotropy amplitude, cell–cell only (Eq 2); calibrate to "57 %" (Z2; A-Z3 undefined)
        λ = UNSPECIFIED        # area strength (Eq 1); 0 for the medium
        κ = UNSPECIFIED        # shape (inertia) strength (12 §2.2); adhesion and shape ΔE "roughly equal" (12b p.255)
        a₀ = UNSPECIFIED       # target ellipse semi-axes a, b (Eq 3); a = b and a ≠ b both used (12 §3).
        b₀ = UNSPECIFIED       # Renamed: `a`, `b` are the pair built-ins of `interfaces`/`edges`
        T = UNSPECIFIED        # calibrate to ≈ 46 % acceptance (12 §3; Z2)
    end
    @variables begin
        r(site)[1:2] = 0.0     # static Cartesian site coordinates (filled by the operating point)
        ε̄(cell) = 0.0          # lagged variant only: per-MCS snapshots (declarations cannot be conditional)
        ā(cell)[1:2] = 0.0
        x̄(cell)[1:2] = 0.0
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))   # contact range UNSPECIFIED (A-Z9)

    A₀ = π * a₀ * b₀                   # Eq 3
    I₀ = A₀ / 4 * (a₀^2 + b₀^2)        # Eq 3: polar moment of the target ellipse
    cross2(u, v) = u[1] * v[2] - u[2] * v[1]
    # α ε r sin θ (Eq 2): α × elongation × distance of the contact point p from the cell's long axis
    lever(c, p) = α * eccentricity[c] * abs(cross2(p - centroid[c], orientation[c]))   # [R7]
    lever_lagged(c, p) = α * ε̄[c] * abs(cross2(p - x̄[c], ā[c]))

    @energy begin
        cells(cell) => λ * (volume - A₀)^2 + κ * (polar_moment - I₀)^2       # Eq 1; §2.2 shape term; Z3   [R7]
        contacts => J[kind, kind′]                                            # Eq 1, isotropic part of Eq 2
    end
    if !lagged
        # Eq 2 with 12b p.252's segment averaging: one term per touching cell pair, re-evaluated for
        # every interface of `old` and `new` on each copy (their axes and ε change).
        @energy interfaces(cell, cell) => -contact * lever(a, interface_centroid) *   # [R11b] [R7]
                                                     lever(b, interface_centroid)
    else
        # Variant: director, ε and COM frozen at the start of each MCS; per-site contact points
        # (the paper's "original scheme"), so ΔH is local. Adopt only after the 12 §5 test.
        @before_mcs begin
            ε̄ ~ eccentricity; ā ~ orientation; x̄ ~ centroid()                        # [R7] (cell scope)
        end
        @energy contacts => -(kind != medium) * (kind′ != medium) *
                            lever_lagged(owner, (r + r′) / 2) * lever_lagged(owner′, (r + r′) / 2)
    end

    eigmax2(xx, yy, xy) = (xx + yy) / 2 + sqrt((xx - yy)^2 / 4 + xy^2)
    eigmin2(xx, yy, xy) = (xx + yy) / 2 - sqrt((xx - yy)^2 / 4 + xy^2)
    @observed begin
        ε(cell) ~ eccentricity                                            # A.4, elongation (V-Z1)   [R7]
        Axx ~ mean(orientation[1]^2 for c in cells(cell))                 # A.5 alignment tensor     [R7]
        Axy ~ mean(orientation[1] * orientation[2] for c in cells(cell))
        Ayy ~ mean(orientation[2]^2 for c in cells(cell))
        alignment ~ eigmax2(Axx, Ayy, Axy)                                # ∈ [½, 1] (12 §5)
        n  ~ count(true for s in sites if owner[s] != 0)                  # whole-array second moments (A.1)
        mx ~ sum(r[s][1] for s in sites if owner[s] != 0) / n
        my ~ sum(r[s][2] for s in sites if owner[s] != 0) / n
        Cxx ~ sum((r[s][1] - mx)^2 for s in sites if owner[s] != 0)
        Cyy ~ sum((r[s][2] - my)^2 for s in sites if owner[s] != 0)
        Cxy ~ sum((r[s][1] - mx) * (r[s][2] - my) for s in sites if owner[s] != 0)
        extension ~ eigmax2(Cxx, Cyy, Cxy) / eigmin2(Cxx, Cyy, Cxy)       # λ_b/λ_a (12 §5; A-Z5)
        J_min(cell) ~ minimum(J[cell, cell] - lever(c, contact_point(c, m)) * lever(m, contact_point(c, m))
                              for m in neighbors(c) if kind[m] == cell)   # V-Z6 flag if < 0   [R11a] [NEW contact_point]
    end
    @sweep Metropolis(; temperature = T,
                      proposal = BoundarySite(Moore(1)))   # boundary sites only, copy from a "nearby" site (12b p.252)   # [R10]
end

# --- Setup: a roughly square block of weakly elongated, randomly oriented cells (12b p.253) -------
block = Tiling((7, 7); region = (72:128, 72:128), kinds = [:cell])   # ≈ 64 cells; size and count UNSPECIFIED (Fig 5a: 50–70 by eye)
@named zajac = ZajacConvergentExtension()
sys  = mtkcompile(zajac)
op   = [layout(block, sys); :r => [[x, y] for x in 1:200, y in 1:200]]
prob = PottsProblem(sys, op, (0, 800_000); seed = 1)                 # ≈ 800 kilosweeps (Fig 5 axis)

# weak random elongation: relax with α = 0 (isotropic adhesion, random axes), then switch α on
relax = solve(remake(prob; p = [:α => 0.0], tspan = (0, 1_000)), SequentialCPM())   # relax length UNSPECIFIED
prob  = remake(prob; u0 = relax[end])                                                # [NEW] u0 from a saved state

# T to ≈ 46 % acceptance (12b p.255): bracketing on a measured rate (tutorial-level, review §3)
using NonlinearSolve
acceptance(T) = solve(remake(prob; p = [:T => T], tspan = (0, 2_000)), SequentialCPM()).stats.acceptance   # [NEW]
T₄₆ = solve(IntervalNonlinearProblem((T, _) -> acceptance(T) - 0.46, (0.1, 100.0)), Bisection()).u  # bracket is a placeholder

sol = solve(remake(prob; p = [:T => T₄₆]), SequentialCPM(); saveat = 0:1_000:800_000)   # R11b: sequential (D-051 item 5 exception)
sol[:alignment], sol[:extension], sol[:ε]                                                # V-Z1 time courses
```

Proposed syntax used above, in brief:
- `interfaces(k₁, k₂)`: every touching cell pair once. It binds `a`, `b`, `contact` (the
  number of contact-relation site pairs between them) and `interface_centroid` (the mean
  contact point, i.e. the midpoint of each unlike site pair, averaged). R11b's
  "`interfaces => E(a, b)` … interface aggregates", made concrete.
- `eccentricity`, `orientation` (a unit long-axis vector), `polar_moment` (Σ|x − x̄|² =
  I_xx + I_yy), and `centroid[c]` in energies and at a cell index: R7.
- `contact_point(c, m)`: R11a's `contact(c, m)` companion, giving the mean contact point
  at MCS cadence.
- `BoundarySite(relation)`: the R10 law, wrapping the relation it copies from.

## 2. Line → source

| Sketch line | Spec | Paper |
|---|---|---|
| `cells(cell) => λ(volume − A₀)²` | 12 §2.2 | 12b Eq 1, p.250; medium λ = 0, p.251 |
| `A₀ = πab`, `I₀ = (A₀/4)(a² + b²)` | 12 §2.2 | 12b Eq 3, p.252 |
| `κ(polar_moment − I₀)²` | 12 §2.2; §7 A-Z7; Z3 | 12b pp.251–252 (I "about an axis … perpendicular to the plane"); A.1, p.257 |
| `contacts => J[kind, kind′]` | 12 §2.2 | 12b Eq 1, p.250 |
| `lever(c, p)` = α ε r sin θ | 12 §2.2 | 12b Eq 2, p.251; Fig 4 (θ ∈ [0, π]) |
| `eccentricity` | 12 §2.2 | 12b Eq A.4, p.257 |
| `orientation` (long axis) | 12 §2.2 | 12b Eqs A.2–A.3, p.257; p.251 "least moment of inertia" |
| `interfaces(cell, cell) => −contact · lever · lever` | 12 §2.2 "Axis / coupling update" items 1–3; §6 G14; Z1 | 12b pp.252–253 (segment averages, "a visit to each boundary segment") |
| lagged branch | 12 §2.2 verdict; §5 acceptance test; Z1 | not in the paper (a deviation) |
| `BoundarySite(Moore(1))`, attempts = N sites | 12 §2.2 "Proposal", "Sweep"; §7 A-Z9 | 12b p.252; p.254 |
| `Metropolis` | 12 §2.2 | 12b Eq 4, p.252 |
| `ε`, `alignment`, `extension` | 12 §5 metric definitions; A-Z5 | 12b pp.254, 257–258 (A.4, A.5) |
| `J_min` flag | 12 §5 V-Z6 | 12b Fig 6, p.254 |
| Tiling + α = 0 relaxation | 12 §2.2 "Initial condition" | 12b p.253, Fig 5a |
| `T₄₆` calibration | 12 §3 (T row); §5 V-Z4 | 12b p.255, Fig 8 |
| `(0, 800_000)` | 12 §3 (run length) | 12b Fig 5, p.253 |

The analytic 12a model (Eqs 1–7, J(n̂·â), aspect ratio D⊥/D∥ = J(0)/J(1)) is not a CPM
and is not in the sketch. It is the V-Z8 unit test of a boundary-relaxation solver
(12 §5).

## 3. Status of primitives used

| Primitive | Status |
|---|---|
| `cells(k) => λ(volume − A₀)²`, `contacts => J[kind, kind′]`, local symbolic helpers (`A₀ = π*a*b`, `cross2`) | exists |
| Vector site/cell variables `r(site)[1:2]`, `r′` in contacts, `x̄[c]` cell reads in contacts | exists (QuantityVector; D-061; AUTHORING §4) |
| Conditional `@energy` / `@before_mcs` on a structural parameter | exists (AUTHORING §2) |
| `@observed` population folds over `cells(k)` and `sites` with `if` filters | exists |
| `Tiling`, `layout`, `remake(prob; p, tspan)`, `SequentialCPM` | exists |
| `eccentricity`, `orientation`, `polar_moment`, `centroid[c]` with exact after-values in ΔH | planned: R7, P6.7 (`major_length_after` is the precedent) |
| `interfaces(k, k) => E(a, b)` with `contact`, `interface_centroid`, and per-copy pair trackers | planned: R11b, P6.7. The domain syntax and the `interface_centroid` aggregate are this sketch's proposal |
| `neighbors(c)` in `@observed` | planned: R11a, P6.7 |
| `BoundarySite(…)` proposal law; all-site attempt counting | planned: R10, P6.4b |
| `contact_point(c, m)` (mean contact point at MCS cadence) | **NEW** (the R11a analogue of `interface_centroid`) |
| `sol.stats.acceptance` (accepted fraction per run or per MCS) | **NEW** |
| `remake(prob; u0 = sol[end])` | **NEW** (unverified whether a saved state is accepted as `u0`) |
| An `UNSPECIFIED` parameter sentinel | **NEW** (the sketch uses `NaN`) |

## 4. Friction found

1. **The exact energy lives on a new domain.** The reference form (D-051 item 3) is not a
   sum over lattice contacts or over cells. It is a sum over **touching cell pairs**,
   each term a function of both cells' moment-derived state and of the pair's interface
   aggregates. A copy changes `old`'s and `new`'s centroid, axis and ε, so the ΔH must
   re-evaluate **every** interface of both cells.
   - R11b therefore needs a per-cell adjacency list maintained on every copy. Each entry
     holds the partner id, the contact count and Σ contact-point coordinates.
   - Its degree is unbounded. A `maxdeg` like the link store needs an overflow path: a
     status word and a capacity grow.
   - The claim set is `old`, `new`, and all their neighbours as shared reads (D-058), or a
     recorded checkerboard exception (D-051 item 5). The sketch assumes sequential only.
2. **Segment averaging is ambiguous (A-Z4), and the choice is visible in the syntax.**
   - The sketch makes one "segment" per cell pair (all its links) and uses the mean
     contact point. Then r sin θ = |(p̄ − x̄) × â| is the lever of the averaged point.
   - That is not the average lever: a contact that straddles a cell's long axis averages
     to about 0, while the per-site sum is positive.
   - Maximal-run segments (several segments per pair) would need connected components
     per pair inside the tracker. That is not a general primitive anyone else needs.
   - If the paper averaged r and θ separately, the formula differs again.
   - **Proposal:** the tracker keeps Σp and Σppᵀ per pair (still O(1) per copy). Both the
     "mean point" and a "mean squared lever" reading are then expressible, and the choice
     stays in the model expression.
3. **Contact point geometry.** The "common boundary point" (12b Fig 4) is taken as the
   midpoint of each unlike site pair.
   - With `Moore(1)`, the diagonal pairs put points off the shared edge.
   - With weighted relations, should each point be weighted? The domain must state it.
   - `contact` must use the *same* relation and the same unordered-once convention as
     `contacts => J`. Otherwise the isotropic and anisotropic parts of Eq 2 do not
     decompose exactly.
   - An alternative is one term, `interfaces(medium, cell, cell) => contact * (J[kind[a],
     kind[b]] − …)`, which drops the separate `contacts` line but needs the medium as an
     interface partner, with no centroid.
4. **R7 naming conflicts with the paper's tensors.** A.1 is the *physics* inertia tensor:
   I_xx = Σ(y − ȳ)², and the long axis is its **smallest** eigenvector. The CompuCell3D
   names in AUTHORING §12.4 (`inertia`, `orientation`, `elongation`) are covariance-style.
   R7 should define these names explicitly:
   - `eccentricity` = √(1 − λ_min/λ_max), which is invariant under the swap;
   - `orientation`: a unit vector or an angle? §12.4 does not say. The sketch uses a vector;
   - `polar_moment`, or `tr(inertia)`.

   `elongation` (major/minor) is a different quantity and must not be reused. The axis is
   ill-conditioned for round cells, but the lever carries a factor ε, so the energy stays
   continuous. That is worth a test.
5. **Name clashes.**
   - The paper's Δ(r) cannot be used: `Δ` is the lattice Laplacian in the DSL, so the
     helper is called `lever`.
   - The paper's semi-axes `a`, `b` collide with the pair built-ins `a`, `b` of
     `edges`/`interfaces`. They are renamed `a₀`, `b₀`.
   - `_BOUND_BUILTINS` in `src/macro.jl` does not reserve `a`/`b`, so declaring
     `@parameters b` would probably shadow the built-in silently rather than error. The
     reserved-name check should cover every built-in in `BUILTIN_NAMES`.
6. **Declarations cannot be conditional** (AUTHORING §2). The lagged variant's `ε̄`, `ā`
   and `x̄` are declared, stored and checkpointed even in the exact model.
   **Proposal:** allow conditional `@variables`, or prune unused variables at `mtkcompile`
   **[NEW, small]**.
7. **The lagged variant is nearly writable today.** Per-cell second moments can be built
   from `integral(r[1]^2)`, `integral(r[1]*r[2])`, … together with `centroid()`, with a
   closed-form 2×2 eigen decomposition in `@before_mcs`, and contact terms already read
   cell state of both owners plus `r′` (D-061).
   - R7 at cell scope is only sugar for the variant. The exact form is the only one that
     needs engine work (R7 after-values + R11b).
   - This makes the 12 §5 exact-vs-lagged acceptance test cheap to set up early.
8. **Calibration needs an acceptance statistic.** T is specified only as "≈ 46 %
   acceptance" and α as "57 % anisotropy". No acceptance counter is exposed, so the
   sketch proposes `sol.stats.acceptance` **[NEW]**.
   - The rate drifts as the tissue elongates and aligns, and the paper does not say when
     it was measured.
   - Bisection on a noisy estimate needs an ensemble mean or a stochastic root finder.
   - α cannot be calibrated until A-Z3 defines "57 %". The sketch leaves α UNSPECIFIED
     rather than invent a definition.
9. **The initial condition composes, but only through `remake(u0 = saved state)`.**
   "Weakly elongated, randomly oriented" cells come from a Tiling relaxed with α = 0 and
   then continued. That needs a saved state accepted as `u0` **[NEW or unverified]**. The
   alternative is an R2 `Ellipses(n; semiaxes, orientation = RandomDirection())` layout;
   `Chains` in 13 already needs rotated composite shapes (13 sketch, friction 7).
10. **Parameters are missing.** Everything is UNSPECIFIED, so the sketch uses a `NaN`
    sentinel. A first-class `UNSPECIFIED` default that `mtkcompile` rejects until it is
    given (`remake(prob; p = …)`) would make reconstruction tutorials safer than `NaN`,
    which silently poisons ΔH **[NEW]**.
11. **Tissue-level observables compose from existing site folds.** Extension and the
    alignment tensor need no R16 package. They are about 8 lines of `@observed`, with a
    2×2 eigen helper. A `sym_eigvals2` library helper would shorten 12, 13 (κ) and 01.

## 5. Open choices

| Choice | Paper vs alternative | Spec default |
|---|---|---|
| Axis/ε update | exact per copy, both cells re-evaluated (paper) / lagged per MCS | **exact** (Z1, D-051 item 3); lagged only after the 12 §5 test (`lagged = true`) |
| Segment averaging (A-Z4) | per pair / per maximal run; average point / average r and θ / average lever | UNSPECIFIED. The sketch uses per pair and the averaged point |
| Trial-energy axes (A-Z8) | post-copy axes of both cells / pre-copy | post-copy (implied by "updated coupling … for a modified cell pair", 12 §2.2) |
| Shape constraint I (A-Z7) | polar moment I_xx + I_yy / other | **polar moment**, flagged (Z3) |
| Proposal law | boundary sites, copy from a "nearby" site (non-reversible) / standard | **boundary-site law** (README §4.12); range UNSPECIFIED (A-Z9); plain Metropolis without a Hastings correction (D-052) |
| Neighbour ranges (energy, proposal) | – | UNSPECIFIED (12 §3, A-Z9); `Moore(1)` is a placeholder |
| Extension measure (A-Z5) | λ_b/λ_a (second-moment ratio) / its square root (length aspect ratio) | λ_b/λ_a as defined (12 §5); plot both |
| Anisotropy "57 %" (A-Z3) | α²ε²rr′/J_cc at a side contact / (J_max − J_min)/J_max / other | UNSPECIFIED; calibrate α only once defined (Z2) |
| Every numeric parameter (J, α, λ, κ, a, b, T, lattice, cell count) | thesis unavailable | UNSPECIFIED (A-Z2); tutorial labelled a reconstruction (Z2) |
| 12a Eq 7 sign typo (A-Z1) | printed J(1) < J(0) < 0 / corrected J(0) < J(1) < 0 | corrected (12 §7 A-Z1), analytic unit test only |
