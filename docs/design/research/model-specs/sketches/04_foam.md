# 04 — Sheared 2D foam: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** a dry 2D foam with area constraints, sheared at the boundary (Eq 6) or in the
  bulk (Eq 7), steadily or periodically. The observables are φ, T1 events, topology
  moments and spectra.
- **Paper:** 04b Y. Jiang, P.J. Swart, A. Saxena, M. Asipauskas, J.A. Glazier, "Hysteresis
  and avalanches in two-dimensional foam rheology simulations", *Phys. Rev. E* 59, 5819
  (1999). The arXiv version 04a has identical physics. No code was released.
- **Spec:** `../04_foam.md`. Decisions: README §4.2 (F1–F6), D-052 (plain Metropolis on a
  non-symmetric law).
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature. `# [NEW]` means the feature is not on the
roadmap. `# [?]` means the primitives exist but this combination has not been tested. A line
with no tag uses only what exists at `monorepo` HEAD. `UNSPECIFIED` values are placeholders
and are not invented.

```julia
using Potts
const T_ANNEAL, N_ANNEAL, N_RELAX, T_COARSEN = nothing, nothing, nothing, nothing   # UNSPECIFIED (04 §2.6, §7 A-8)

@potts_model ShearedFoam begin
    @structural_parameters begin
        lattice  = (256, 256)     # all shown figures: 256², 16² bubbles (04 §2.5, F3)
        shear    = :bulk          # :boundary (Eq 6) | :bulk (Eq 7)
        periodic = false          # G(t) = sin(ωt) if true, else 1 (04b p.5822)
        walls    = :free          # y walls: :free (closed edge) | :frozen (frozen rows); type UNSPECIFIED (04 §7 A-2, F4)
    end
    @kinds medium bubble wall[frozen]    # dry foam: no site is medium (04b p.5822); `wall` only for walls = :frozen
    @parameters begin
        J   = 3.0             # 04b p.5823; Fig 3(b): 1, 3, 5, 10
        J_w = NaN             # bubble–wall coupling: UNSPECIFIED (04 §7 A-2); read only when walls = :frozen
        Γ   = 1.0             # 04b p.5823
        T   = 0.0             # 04b p.5823; Fig 3(d): 0, 5, 10, 15
        γ₀  = 7.0             # Fig 3(b); scale calibrated on γ₀/J ≈ 1.9 (F1); Figs 2, 6 value UNSPECIFIED (04 §7 A-12)
        β   = 0.01            # Fig 4; Fig 5 0.05; sweeps in Figs 8–11 (04 §3.1)
        ω   = 2π / 4000       # "about 4000 MCS" per cycle (04b p.5822)
    end
    @variables begin
        A(cell)  = 256.0      # A_n, area "under zero applied stress" (04b p.5821); set from the start state below
        G(model) = 1.0        # G(t) (04b p.5822)
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()),       # periodic x, walls in y (04b p.5822)
                     neighborhood = NeighborOrder(4))                  # fourth-nearest neighbours (04b p.5822)
    @relations proposal = UnlikeNeighbor(NeighborOrder(4))  # [R10] F5: wall sites only, to an unlike neighbour; set UNSPECIFIED (A-4)
    @energy begin
        contacts => ifelse((kind == wall) | (kind′ == wall), J_w, J)   # Eq 1, J Σ(1 − δ)
        cells(bubble) => Γ * (volume - A)^2                            # Eq 1, Γ Σ(a_n − A_n)²
    end
    if periodic
        @before_mcs G ~ sin(ω * mcs)                                   # 04b p.5822, 5824
    end
    # F1: copying σ_j (source) into site i (target) adds γ(y_i, t)·(x_i − x_j), minimum image
    y    = position[2]                                                 # [R1] target coordinate in copy scope
    rows = walls === :frozen ? (2, lattice[2] - 1) : (1, lattice[2])   # the y_min / y_max rows of Eq 6
    γy   = shear === :bulk ? -β * (y - (lattice[2] + 1) / 2) :         # Eq 7, y from the mid-plane (A-3); sign: top → +x
                             γ₀ * ((y == rows[1]) - (y == rows[2]))    # Eq 6 on the boundary rows only
    @drive copy => γy * G * direction[1]                                # [R1] direction = target − source (A-1, A-10)
    @observed begin
        φ      ~ sum(surface for c in cells(bubble)) / 2               # Eq 8, θ = 1: unlike pairs once (exact with free walls)
        E_area ~ sum(Γ * (volume - A)^2 for c in cells(bubble))        # V19: ≈ 10⁻³ of J·φ (04b p.5823)
        strain ~ γ₀ * G                                                # Fig 3 "Strain" axis = γ(t) (04 §2.2)
        sides(cell) ~ count(true for n in neighbors(c; relation = Moore(1)))   # [R11a] n = distinct neighbours (04b p.5823); relation UNSPECIFIED
        μ₂n    ~ mean(sides^2 for c in cells(bubble)) - mean(sides for c in cells(bubble))^2   # [R11a][?] 04b p.5823
        μ₂a    ~ mean(volume^2 for c in cells(bubble)) - mean(volume for c in cells(bubble))^2   # 04b p.5823
    end
    @sweep Metropolis(; temperature = T, tie = 1.0)                    # [R1] Eq 3; ΔH′ = 0 accepted at T = 0 (F2)
end

# ── Initial conditions (04b p.5823; 04 §2.6) ──────────────────────────────────────────
@named foam = ShearedFoam()
alg  = SequentialCPM()
op   = layout(BrickWall((16, 16); offset = 8, kinds = [:bubble]), foam)          # [R2] "brick wall … common bond"
prob = PottsProblem(foam, [op..., A => volume], (0, 1); seed = 1)                # [NEW] A_n := start area (truncated rows smaller)
stage(u, n, p; kw...) = solve(remake(prob; u0 = u, tspan = (0, n), p), alg; kw...).u[end]   # [?] u0 = a saved state
u = stage(op, N_ANNEAL, [β => 0, γ₀ => 0, T => T_ANNEAL])      # 1. area constraint, no strain, finite T, "a few MCS"
u = stage(u, N_RELAX, [β => 0, γ₀ => 0, T => 0])                # 2. T = 0 relaxation → hexagonal foam (V1, V1b)
ordered = u
# Disordered foams: coarsen without area constraint until μ₂(n) hits the target, then reset A_n and relax at T = 0
stop_at(μ) = DiscreteCallback((u, t, integ) -> integ[μ₂n] >= μ, terminate!)      # [?][R11a] SciMLBase callback on an observed
u = stage(ordered, 10^6, [Γ => 0, β => 0, γ₀ => 0, T => T_COARSEN]; callback = stop_at(0.81))  # μ₂(n) = 0.81 foam (Fig 8b)
disordered = stage([u..., A => volume], N_RELAX, [β => 0, γ₀ => 0, T => 0])   # [NEW] reset A_n; rule UNSPECIFIED (A-8)

# ── Runs ───────────────────────────────────────────────────────────────────────────────
# Fig 4 / 8(a) / 10(a) / 11(c): ordered, steady bulk shear, β = 0.01, 10⁵ MCS; per-MCS series for spectra
t1 = T1Counter(; relation = Moore(1), unit = :pair)            # [R16][NEW] streaming neighbour-list diff; unit configurable (A-15, F6)
sv = SavedValues(Int, Tuple{Float64, Int, Float64})
sol = solve(remake(prob; u0 = ordered, tspan = (0, 100_000), p = [β => 0.01]), alg; saveat = 1000,
            callback = SavingCallback((u, t, integ) -> (integ[φ], t1(integ), integ[μ₂n]), sv))   # [?] DiffEqCallbacks on Potts
# Fig 3(a–c): periodic boundary shear; loops φ vs γ(t) averaged over 10 periods; (J, γ₀) phase diagram
@named cyc = ShearedFoam(; shear = :boundary, periodic = true)
pcyc  = PottsProblem(cyc, [ordered..., A => volume], (0, 10 * 4000); seed = 1)   # [NEW] A => volume, as above
grid  = [(J, g) for J in (1.0, 3.0, 5.0, 10.0) for g in 0.0:0.5:16.0]           # Fig 3(c) axes (J 0–10, γ₀ 0–16)
loops = solve(EnsembleProblem(pcyc; prob_func = (q, ctx) -> remake(q; p = [J => grid[ctx.sim_id][1], γ₀ => grid[ctx.sim_id][2]])),
              alg, EnsembleThreads(); trajectories = length(grid), saveat = 10)
# Fig 3(d): T ∈ (0, 5, 10, 15) at J = 3, γ₀ = 4; Fig 6/7/9: disordered start, remake(u0 = disordered, p = [β => …])
```

About 95 lines of code, of which the model body is 50.

## Line → source

| Line | Spec | Paper |
|---|---|---|
| `contacts => … J` | 04 §2.2, §3.1 | Eq 1, 04b p.5821; J = 3 (p.5823) |
| `cells(bubble) => Γ(volume − A)²`, `Γ = 1` | 04 §2.2, §3.1 (claim #2 corrected) | Eq 1 p.5821; Γ = 1 (p.5823) |
| `A(cell)`, `A => volume` | 04 §2.2, §2.6 | "area under zero applied stress" (p.5821); reset rule UNSPECIFIED (A-8) |
| `neighborhood = NeighborOrder(4)` | 04 §2.4 | "fourth-nearest-neighbor … anisotropy 1.03" (p.5822) |
| `boundary = (Periodic(), Closed())`, `walls` | 04 §2.5, A-2, F4 | p.5822; wall type unstated |
| `proposal = UnlikeNeighbor(…)` | 04 §2.3, A-4, A-5, F5 | "only reassign it if it is at a bubble wall and then only to one of its unlike neighbors" (p.5822) |
| `Metropolis(; tie = 1.0)`, `T = 0` | 04 §2.3, A-6, F2 | Eq 3 p.5822; T = 0 default (p.5823) |
| `@drive copy => γy * G * direction[1]` | 04 §2.2, A-1, A-10, F1 | Eq 2 p.5821 (shear term on walls), sign rule p.5822 |
| `γy` boundary branch | 04 §2.2 | Eq 6 p.5822 |
| `γy` bulk branch, y from the mid-plane | 04 §2.2, A-3 resolved | Eq 7 p.5822; p.5824, p.5830; arrows in Figs 4a, 5a, 7a |
| `G ~ sin(ω mcs)`, ω = 2π/4000 | 04 §2.2, §3.2 | p.5822, p.5824 |
| `γ₀ = 7`, `β = 0.01` | 04 §3.1 | Fig 3(b) caption; Fig 4 |
| `φ` | 04 §2.8 | Eq 8 p.5823 |
| `sides`, `μ₂n`, `μ₂a` | 04 §2.8 | p.5823 |
| `E_area` | 04 §5.2 V19 | p.5823 |
| `strain ~ γ₀ G` | 04 §2.2 "Figure evidence" | Fig 3 loop extents ≈ ±γ₀ |
| `BrickWall((16,16); offset = 8)` | 04 §2.6 step 1 | p.5823 |
| stages 1–2 (anneal, T = 0 relax) | 04 §2.6 steps 2–3 | p.5823; T, lengths UNSPECIFIED (A-8) |
| coarsen until μ₂(n), reset A_n, relax | 04 §2.6 steps 4–5 | p.5823; μ₂(n) = 0.81 foam (Fig 8b caption) |
| `T1Counter` | 04 §2.8, A-15, F6 | T1 = neighbour-list change (p.5823) |
| 10⁵-MCS per-MCS series | 04 §2.8, §5.1 Fig 8 | Eq 9 p.5827; f to 0.5 = Nyquist |
| (J, γ₀) grid | 04 §5.1 Fig 3(c), V5 | Fig 3(c), 44 simulations (p.5824) |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds … wall[frozen]`, scalar `@parameters`, `A(cell)` default from a parameter or value, `G(model)` | exists |
| Per-axis `boundary = (Periodic(), Closed())`, `NeighborOrder(4)` | exists |
| `contacts => ifelse(kind == …, …)`, `cells(k) => Γ(volume − A)²` with a cell variable `A` | exists |
| Conditional sections (`if periodic … end`), `@before_mcs G ~ sin(ω * mcs)` | exists |
| `@drive copy => …` reading a model variable | exists (model variables lower to `st.model`) |
| `position` in copy scope | planned (R1, P6.4a). Today `position` is bound only in site scope and on-copy updates |
| `direction` (target − source, minimum image) | planned (R1, P6.4a; AUTHORING §12.2) |
| `Metropolis(; tie)` | planned (R1, P6.4a). Today the T ≤ 0 tie is fixed at ½ |
| `UnlikeNeighbor` proposal law, all-site attempt counting | planned (R10, P6.4b) |
| `@observed x ~ sum(surface for c in cells(k))`, `mean(volume^2 …)` | exists (population folds in `@observed`) |
| `neighbors(c; relation)` and a cell-scope observed read inside a model-scope fold | planned (R11a); the `relation` keyword is **NEW** (R11a says "under the contact relation") |
| `BrickWall` layout | planned (R2, P6.4d) |
| `A => volume` in the operating point (a cell initial value from an expression of the state) | **NEW** |
| `remake(prob; u0 = <saved state>)` for staged protocols | untested `[?]` |
| `DiscreteCallback`/`SavingCallback` on a Potts integrator, `integ[obs]` | untested `[?]` (AUTHORING §8 says SciMLBase callback semantics hold) |
| T1 counting (neighbour-list diffs per MCS), spectra, N̄, yield strain | planned (R16, P6.4d); a streaming counter is **NEW** |

## Friction found

1. **R1 is sugar here. The shear drive can be written today.** Copy-scope `position` and
   `direction` are missing, but site variables are readable at `source` and `target` in
   drives (the chemotaxis idiom).
   - With `@variables px(site); py(site)` filled with the coordinates in the operating
     point, F1 is
     `@drive copy => γ(py[target]) * G * wrap(px[target] - px[source])`,
     with a hand-written minimum-image `wrap` for periodic x. It costs two site arrays.
   - So R1 buys readability and removes the `wrap` hazard; it is not a capability.
   - Only the `tie = 1` policy (F2) is a real gap. Without it, T = 0 runs use ½, and
     V3–V5 timings would shift.
2. **The placement of the proposal law is undecided.** R10 says "`ProposalLaw` dispatch", and
   D-049 F-1 put the proposal *relation* in `@relations proposal = …`. A law is more than a
   relation: `BoundarySite` changes what an attempt is (A-5).
   - The sketch writes `@relations proposal = UnlikeNeighbor(NeighborOrder(4))`, but
     `@sweep Metropolis(; proposal = UnlikeNeighbor(…))` is equally plausible.
   - One place must be picked before P6.4b.
   - The spec's A-5 choice maps to the two laws as follows:
     - `UnlikeNeighbor` counts every site pick, and non-wall picks are null (the F5
       default);
     - `BoundarySite` draws only among wall sites.
3. **An initial value derived from the state (`A => volume`) is missing.** A_n is "the area
   under zero applied stress". The truncated boundary bubbles are smaller than 256, and
   A_n must be reset after coarsening.
   - Today this is host code: count sites per id in σ and pass `A => vec`.
   - The MTK-idiomatic form is an initialization equation `A ~ volume` evaluated at
     `init`, as MTK does for unknowns with expression defaults. It is on no roadmap row.
     Every "set target to current size" protocol needs it (Merks relaxation, OpenVT
     re-targeting).
4. **`neighbors(c)` must take its own relation.** R11a defines neighbours as "face-sharing
   under the contact relation".
   - The foam's contact relation is `NeighborOrder(4)` (radius ≈ 2.2), so bubbles two
     sites apart would count as sides. That inflates n, μ₂(n) and the T1 counts.
   - `neighbors(c; relation = Moore(1) | VonNeumann(1))` is needed. The paper does not say
     which relation it used. This is a **new ambiguity the spec does not list**: add it to
     04 §7 next to A-4. It is the same neighbour-rule gap that parks 09 V-PRE6.
5. **T1 detection cannot be an `@observed`.** A T1 is a change of a bubble's neighbour
   *set* between consecutive MCS.
   - `@observed` is a pure function of one state.
   - `Pre` lags only scalars, and R12 covers only scalar cell variables.
   - Saving every MCS for 1.3×10⁵ MCS at 256² would take ≈ 34 GB (Int32).
   - A **streaming** per-MCS hook is required. It could be a SciML `SavingCallback` (if a
     Potts integrator supports it, which is untested) or a Potts-native "contact-graph
     event" count at the MCS boundary: `@after_mcs n_T1 ~ count(changed_contacts(…))`.
     Neither is on the roadmap.
   - R16 lists "T1 counts" but assumes post-hoc analysis of saved states. That does not
     scale to the spectra (Figs 8, 10).
6. **The staged protocol is the bulk of the reproduction, and R3 `@terminate` is the wrong
   tool for it.** Anneal → relax → coarsen-until-μ₂(n) → reset A_n → relax are stages with
   *different parameters*. Putting `@terminate when = μ₂n ≥ μ` into the model would bake
   one stage's stopping rule into every stage.
   - Host-level staging fits better: `remake` + `solve` + a `DiscreteCallback` with
     `terminate!`. It needs `remake(u0 = saved state)` and `integ[observed]` inside
     callbacks (both untested).
   - Recommendation: have R3's `@terminate` lower to exactly that callback and document
     the host form as primary.
   - Every stage's T and length is UNSPECIFIED (A-8), so this stage machinery is exercised
     with placeholder values.
7. **The rows of Eq 6 depend on the wall variant.** `rows` is computed from the `walls`
   structural parameter, which is fine. But `@kinds` cannot be conditional, so the frozen
   `wall` kind and the `J_w` placeholder exist even in the free-wall variant. The dry foam
   also must declare a `medium` that owns no site. Both are cosmetic.
8. **φ from `surface` is only exact with free walls.** Bubble–wall pairs are counted once,
   and the /2 halves them. With a contact-pair fold (**NEW**, the same primitive as in
   sketch 09), `φ ~ count((kind == bubble) & (kind′ == bubble) for _ in contacts)` is exact
   in both variants.
9. **μ₂ needs a population fold of a cell-scope observed**, in a model-scope observed that
   must also be readable by a callback at MCS cadence. The sketch avoids nested folds with
   the identity μ₂ = ⟨n²⟩ − ⟨n⟩². A general `var(x for c in cells)` fold would be cleaner
   and is on no list.
10. **Spectra, N̄ and yield strain are pure analysis.** They use FFT or periodograms (FFTW or
    DSP.jl in docs, D-051 item 6). N̄ and the yield strain need the unresolved A-9
    calibration, so they compare ratios only.

## Open choices

| Choice | Default (spec) | Variants |
|---|---|---|
| Shear-term form | displacement γ(y_i,t)(x_i − x_j), minimum image (F1) | literal Σ γ(y)·x_i(1 − δ) as a contact term over coordinate site variables `px`, `py` (`contacts => γ(py) * G * px`, exists via D-061), documented as ill-posed on periodic x (A-10) |
| γ₀ scale | calibrated on the γ₀/J transition ≈ 1.9 (V3/V5) (F1) | the literal equation scale |
| ΔH′ = 0 at T = 0 | accept, P = 1 (F2) | ½ (engine default today), 0 |
| Lattice / bubble | 256², 16² (F3) | 400 × 100, 20² (text only; no figure) |
| y walls | pick by V1b μ₂(n) ≈ 0.44; report both (F4) | free closed edge / frozen rows with J_w UNSPECIFIED |
| Proposal law | boundary-only, unlike neighbour, all-site attempt counting (F5) | plain Metropolis; `BoundarySite` counting |
| Proposal neighbour set | NeighborOrder(4), assumed equal to the interaction set | UNSPECIFIED (A-4) |
| T1 counting unit | configurable, ratios only (F6) | per bubble pair / per event (A-15) |
| Sides relation for n, μ₂(n) | Moore(1) (sketch choice) | VonNeumann(1); UNSPECIFIED in the paper (new ambiguity, friction 4) |
| Protocol numbers | UNSPECIFIED: anneal T and length, relax length, coarsening T, A_n reset rule (A-8) | reset A_n := current area (sketch) or mean area |
| Fig 9 foams (377/380 bubbles) | not reproducible on 256² with 16² bricks (A-14) | smaller bricks or a larger lattice |
| y sign (Eq 6 vs Eq 7) | fixed so the top moves +x (A-3) | — |
