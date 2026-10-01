# 05 — Bauer, Jackson & Jiang 2009, ECM topography and sprouting: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** one capillary sprout grows from a parent vessel (left wall) up a VEGF gradient
  through a stroma that is explicitly matrix fibre and interstitial fluid. ECs are tip,
  stalk or proliferating, carry a soft exact-BFS continuity penalty, and are recruited
  from the wall. Tip-cell matrix degradation is optional.
- **Paper:** Bauer AL, Jackson TL, Jiang Y, PLoS Comput Biol 5(7): e1000445 (2009). The
  mechanics missing from 2009 come from the parent paper Bauer et al. 2007 (spec 07). The
  2007 and 2009 parameter sets must not be mixed (05 §7.3, B1).
- **Spec:** `../05_bauer2009_ecm.md` (§2, §3, §6, §7). Decisions: README §4.3 (B1–B6).
  Roadmap: ROADMAP P6.9 (R4 `Global()`, R8 `@create`, R16), which builds on P6.8 (R3, R14,
  R15, R10, R2 `Fibres`). **Gate:** B2 (pixel size).
- **Date:** 2026-09-30.

Tags: `# [R#]` is a planned roadmap feature. `# [P6.0g]` is a planned step-0 composition
fix (kind classes). `# [NEW]` is not on the roadmap. `# [?]` means the primitives exist but
this combination is untested. A line with no tag uses only what exists at `monorepo` HEAD.
`UNSPECIFIED` is a placeholder that must be set before a run. It is never a guess.

```julia
using Potts, OrdinaryDiffEq, LinearSolve        # R14: implicit field + steady init (extension)
const UNSPECIFIED = NaN                          # must be set before solve (05 §3.3)

@potts_model Bauer2009ECM begin
    @structural_parameters begin
        Δx = UNSPECIFIED          # µm/px (05 §2.1, §3.3). 0.55 fits 1.1 µm bundles but is a hypothesis only (B2)
        domain = (166.0, 106.0)   # µm, x × y (05 §2.1, Fig 1; B3 over "100 × 160", 05 §7.1 item 1)
        degradation = false       # tip-cell matrix degradation, §Degradation runs only (05 §2.4, p.11)
        continuity = :global      # B5: exact BFS (default) | :local ring variant
    end
    @kinds begin
        medium                                # kind 0 is mandatory but owns no site: the stroma is fluid + matrix (05 §2.3)
        fluid; matrix                         # one collective cell each (05 p.14; D-066: ordinary cells)
        tip; stalk; prolif                    # EC phenotypes (05 §2.4)
        ecm = [fluid, matrix]                 # [P6.0g] kind classes
        endothelial = [tip, stalk, prolif]    # [P6.0g]
    end
    @parameters begin
        kT = 2.5                                          # 05 §2.2, Table 1
        #                 M   f   m  tip stalk prolif     (Table 1: J_ee 30, J_ef 76, J_em 66, J_ff 71, J_fm 85, J_mm 85)
        J[kind, kind] = [0   0   0   0   0   0;
                         0  71  85  76  76  76;
                         0  85  85  66  66  66;
                         0  76  66  30  30  30;
                         0  76  66  30  30  30;
                         0  76  66  30  30  30]
        γ[kind] = [0.0, 0.5, 0.5, 0.8, 0.8, 0.8]          # γ_f, γ_m, γ_e (Table 1)
        χ = 1.11e6                                        # E/conc (Table 1)
        χ_rel[kind] = [0.0, 0.0, 0.0, -1.45, -1.42, -1.40]  # tip, stalk, prolif potentials (Table 1)
        α = 300.0                                         # continuity penalty (Table 1, fixed)
        A₀ = π * (5.0 / Δx)^2                             # "∼10 µm diameter" EC (05 p.4) as a disk, in px
        τ_cycle = 1080.0                                  # 18 h × 60 MCS/h (05 §3.2)
        v_a = 1e-4                                        # pg, activation threshold (Table 1)
        D_V = 600.0                                       # µm²/min, from 3.6e-4 cm²/h (05 §3.2)
        λ_V = 0.6498 / 60                                 # min⁻¹ (05 §3.2)
        β = 0.06 / 60                                     # pg per EC per min (Table 1)
        S = 0.035                                         # pg/pixel at the right boundary (Table 1)
        r_new = UNSPECIFIED                               # recruited-cell radius, px (05 §2.4)
        deg_budget = 0.55^2 / Δx^2                        # sites per tip per MCS, (0.55 µm)²/min (05 p.11)
    end
    @variables begin
        V(field) = 0.0                                    # VEGF, pg/pixel; replaced by the steady init below
        rim(site) = 0.0                                   # 1 on a cell's boundary sites
        V_target(cell) = A₀                               # ECM targets set from the layout (see op below)
        clock(cell) = 0.0                                 # "zero for newly recruited cells" (05 p.6)
        activated(cell) = 0.0                             # latched once VEGF ≥ v_a (05 p.5)
        cx(cell) = 0.0
        cy(cell) = 0.0
        at_wall(cell) = 0.0                               # sites in the parent-vessel column
        y_base(model) = 0.0                               # where the base cell last touched the wall
    end
    @lattice Lattice(round.(Int, domain ./ Δx); spacing = Δx,
        boundary = (Closed(), Periodic()),                # CPM BCs UNSPECIFIED (05 §7.2); field periodic in y (05 p.3)
        neighborhood = Moore(1))                          # UNSPECIFIED in 2009; 2007 "second nearest" (07 p.7)

    @energy begin
        contacts => J[kind, kind′]                        # Eq 1 term 1 (pair counting: see Friction 9)
        cells => γ[kind] * (volume - V_target)^2          # Eq 1 term 2 (ECM collectives included)
    end
    if continuity == :global                              # Eq 1 term 4: α(1 − δ_{a,a′}), a′ = BFS count
        @energy cells(endothelial) => α * (components(; scope = Global()) > 1)   # [R4][NEW] cell-scope value, exact after-value
    else
        @drive copy => α * (kind[old] ∈ endothelial) * (local_components > 1)    # [P6.0g] B5 local variant
    end
    @drive copy => ifelse((kind[new] ∈ endothelial) & (activated[new] > 0),     # [P6.0g] Eq 1 term 3 = 07 Eq 3,
        χ * χ_rel[kind[new]] * (V[target] - V[source]), 0.0)                    # gainer only (05 §2.3, UNSPECIFIED)
    @constraint no_extinction(fluid, matrix)             # [R6] optional D-066 item 6 guard (05 §6 G10)

    @equations D(V) ~ D_V * Δ(V) - λ_V * V -                                    # Eq 2 (05 p.3)
        uptake(V; amount = β, per = cells(endothelial), cap = V)                # [R15][NEW cap] B = min(β, V), per cell (B6)
    @initialization_equations 0 ~ D_V * Δ(V) - λ_V * V -                        # [R14][NEW syntax] steady state at t = 0 (05 p.3)
        uptake(V; amount = β, per = cells(endothelial), cap = V)                # [R15]
    @boundary V begin                                                           # [R5]
        x => (Dirichlet(0.0), Dirichlet(S))                                     # V = 0 left, V = S right (05 p.3)
        y => Periodic()
    end

    @after_mcs begin
        rim ~ any(owner[n] != owner for n in Moore(1)(site))                    # membrane sites
        cx ~ centroid(1)
        cy ~ centroid(2)
        at_wall ~ integral(position[1] <= 1)                                    # [?] position units with spacing
        activated ~ max(Pre(activated), integral(V * rim) >= v_a * integral(rim))   # "processed at the membrane" (05 p.4); Friction 5
        clock ~ ifelse(kind == prolif, Pre(clock) + 1, Pre(clock))              # 18 h clock (05 p.5)
        y_base ~ ifelse(any(at_wall[c] > 0 for c in cells(endothelial)),       # [P6.0g]
            mean(cy[c] for c in cells(endothelial) if at_wall[c] > 0), Pre(y_base))
    end

    lead = cx == maximum(cx[c] for c in cells(endothelial))                     # [P6.0g] "leading EC" (07 p.8); 2009 UNSPECIFIED
    @transition cells(stalk, prolif) => tip when = lead                         # [R3]
    @transition cells(tip) => stalk when = !lead                                # [R3] former phenotype is lost (Friction 4)
    @transition cells(stalk) => prolif when = UNSPECIFIED, V_target => 2A₀      # [R3] rule UNSPECIFIED; target 2 × initial (05 p.2–3)
    @divide cells(prolif) when = (clock >= τ_cycle) & (volume >= 2A₀),          # 2007 mechanics (07 p.8); never fires in 14 h (05 p.6)
        along = RandomPlane(), clock => 0.0, V_target => A₀
    @create stalk when = !any(at_wall[c] > 0 for c in cells(endothelial)),     # [R8][P6.0g] recruit "when and where the previous
        at = Sphere((1.0, y_base), r_new),                                      # [NEW] cell detaches" (05 p.4–5); geometry UNSPECIFIED
        V_target => A₀, clock => 0.0, activated => 0.0                          # phenotype of new cell UNSPECIFIED (05 §7.4 q5)
    if degradation
        @convert matrix => fluid, sites => the(fluid),                          # [R8][NEW the] product UNSPECIFIED (05 §4 #21)
            where = any(kind[n] == tip for n in Moore(1)(site)),                # site choice UNSPECIFIED (05 §7.2)
            budget = deg_budget, per = cells(tip)                                # (0.55 µm)²/min per tip (05 p.11)
    end

    @observed begin
        tip_x(model) ~ maximum(cx[c] for c in cells(endothelial))              # [P6.0g] V1 speed = d(tip_x − base)/dt (R16)
        n_ec(model) ~ count(true for c in cells(endothelial))                   # [P6.0g] V3
    end
    @sweep Metropolis(; temperature = kT, mcs_duration = 1.0,                   # 1 MCS = 1 min (05 p.5)
        field_solver = Adaptive(KenCarp4(linsolve = KrylovJL_GMRES())))         # [R14] Friction 8
end

Δx = UNSPECIFIED                                   # B2
@named sys = Bauer2009ECM(; Δx)
stroma = Fibres(; kind = :matrix, background = :fluid, fraction = 0.40,       # [R2] ρ ≈ 0.40 baseline (05 p.5)
    thickness = 1.1 / Δx, angles = (0, 30, -30, 45, -45, 60, -60, 90),        # 1.1 µm bundles, discrete angles (05 p.5, p.9)
    length = UNSPECIFIED, collective = true, seed = 1)                         # [NEW collective] one id per constituent (05 p.14)
bud = Spheres(1, 5.0 / Δx; centers = [(5.0 / Δx + 1, 53.0 / Δx)], kinds = [:tip])   # [R2] one ∼10 µm EC at the wall (05 p.4)
op = layout(overlay(stroma, bud), sys)
op = [op; :activated => [0.0, 0.0, 1.0],           # fluid, matrix, bud: the bud starts activated (05 p.4)
      :V_target => initial(volume)]                # [NEW] ECM targets = initial totals (UNSPECIFIED, 05 §2.3 notes)
prob = PottsProblem(sys, op, (0, 840))             # ≈ 14 h (05 §3.2)
sol = solve(EnsembleProblem(prob; trajectories = 10), SequentialCPM(); saveat = 0:60:840)   # ≥ 10 replicates (05 p.6)
```

## Line → source

| Line / rule | Spec | Paper |
|---|---|---|
| `contacts => J[kind, kind′]`, J table | 05 §2.3, §3.1 | Eq 1 term 1 (p.2); Table 1 (p.4) |
| `cells => γ[kind] (volume − V_target)²` | 05 §2.3, §3.1 | Eq 1 term 2 (p.2–3); Table 1 γ_e, γ_m, γ_f |
| ECM targets = initial totals | 05 §2.3 notes, §3.3 | UNSPECIFIED; "total mass … conserved" (p.14) |
| `α (components > 1)` / local variant | 05 §2.3, §6 G4; README B5 | Eq 1 term 4 (p.3); α = 300 (Table 1) |
| chemotaxis drive, χ_rel per phenotype | 05 §2.3, §3.1, §3.2 | Eq 1 term 3 (p.3); 07 Eq 3 (07 p.7); Table 1 |
| `activated` latch at v_a, membrane mean | 05 §2.4, §2.5 | p.4 ("at the cell membrane"), p.5; Table 1 v_a |
| `D(V) ~ D ΔV − λV − B` | 05 §2.5, §3.2 | Eq 2 (p.3); Table 1 D, λ |
| `uptake(… amount = β, per = cell, cap = V)` | 05 §2.5, §7.2; README B6 | B from 07 p.6; β Table 1 |
| steady-state init | 05 §2.5 | p.3 "establishing the steady state solution" |
| `@boundary V` Dirichlet 0 / S, periodic y | 05 §2.5 | p.3; S Table 1 |
| tip = leading EC (`lead`) | 05 §2.4, §7.2 | 2009 UNSPECIFIED; 07 p.8 "the leading endothelial cell" |
| stalk → prolif, `V_target => 2A₀` | 05 §2.4 | p.2–3 (target doubles); assignment UNSPECIFIED |
| `clock`, `@divide` | 05 §2.4, §3.2 | p.5 (18 h clock); division from 07 p.8; no division in 14 h (p.6) |
| `@create stalk` at `y_base` | 05 §2.4, §7.4 q5 | p.4–5, p.6 (15–20 recruited) |
| `@convert matrix => fluid` | 05 §2.4, §4 #21 | p.11 ((0.55 µm)²/min; product not stated) |
| lattice 166 × 106 µm, Δx | 05 §2.1, §3.3; README B2, B3 | Fig 1 caption (p.3) |
| `Metropolis(kT = 2.5)`, 1 MCS = 1 min | 05 §2.2, §2.1 | p.2 acceptance; Table 1; p.5 calibration |
| `Fibres(ρ = 0.4, 1.1 µm, angles)` | 05 §2.6 | p.5, p.9 |
| run 840 MCS, 10 replicates | 05 §2.1, §3.2 | p.6–7; Fig 1 caption |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds`, `J[kind, kind]`, `γ[kind]`, `χ_rel[kind]`, `contacts`, `cells =>` with per-kind vectors | exists |
| cell/site/model variables, `Pre`, `integral`, `centroid(k)`, `mean`/`maximum`/`any`/`count` population folds, site gathers, `local_components` | exists |
| `@divide … along = RandomPlane()`, `rand()`, `Adaptive` (cell ODEs only) | exists |
| `spacing` in `Lattice` | exists (per AUTHORING §3); how `position` and `Δ` scale with it is unverified `[?]` |
| kind classes `ecm = [...]`, `kind ∈ class`, `cells(class)` | planned, P6.0g (step 0) |
| `components(; scope = Global())` | planned R4 (P6.3a / P6.9), proposed as a copy-scope value of `old` |
| `components` as a **cell-scope** value with an exact after-value in `cells(k) =>` energies | NEW (extends R4) |
| `@boundary` per face | planned R5 (P6.3b) |
| `uptake(…; per = cells(k))` | planned R15 (P6.8); the `cap = V` / fixed-`amount` form is NEW (AUTHORING §12.5 has only Michaelis–Menten `vmax, K`) |
| implicit field solver, steady init | planned R14 (P6.8); `@initialization_equations` as the steady-init spelling is NEW (MTK's own name) |
| `@transition` | planned R3 (P6.4c, P6.8) |
| `@create` | planned R8 (P6.9); placement `at = Sphere(center, r)` is NEW |
| `@convert` | planned R8 (P6.5b); `sites => the(fluid)` (a collective cell as destination) is NEW |
| `no_extinction(kinds…)` | decided (D-066 item 6), not built (today it takes no kinds) |
| `Fibres`, `Spheres` layouts | planned R2 (P6.8, P6.5c); `collective = true` (one id for all shapes) is NEW |
| `initial(volume)` in the operating point | NEW |
| speed, branch and loop detection | planned R16 (P6.9) |

## Friction found

1. **Medium is mandatory but empty.** The 2009 stroma is two collective *cells* (fluid,
   matrix), so kind 0 owns no site. Every `old == 0` / `new != 0` idiom, including
   `Chemotaxis(; kinds)`'s gain gate (`new != 0`) and the default `no_extinction`, is then
   either wrong or a no-op. Kind classes (P6.0g) are **required**, not sugar.
2. **Kind tables do not know classes.** J is defined per constituent (e, m, f), but the
   phenotypes split e into three kinds, so the 6×6 table repeats 9 values. A typo in one
   copy would silently make tip–stalk adhesion differ from stalk–stalk. Proposal [NEW]:
   let a kind table be indexed by class, e.g. `J[class, class] = …` with
   `J[kind, kind′]` resolving through the class, or a `by_class(...)` constructor. The
   alternative is a phenotype cell variable instead of kinds. That needs no classes for
   J, but it needs integer-indexed χ tables (R13), and plots would lose kind colouring.
3. **The R4 soft form is not Eq 1.** R4 proposes `@drive copy => E₀ * (components(old) > 1)`.
   That charges every breaking copy. Eq 1's term is a **state energy**, α·[cell
   fragmented]:
   - a cell that is already fragmented pays nothing for further breaks;
   - a copy that *reconnects* a cell (the `new` side) earns −α;
   - `total_energy` and the ΔH self-check only see it if it is an energy.

   Proposal [NEW]: a cell-scope `components` built-in with an exact after-value (as
   `major_length` already has), usable in `cells(k) => α * (components > 1)`. Evaluating
   it needs a BFS for `old` when the local test fails, and a BFS for `new` when the gained
   site touches two or more of `new`'s local pieces. The drive stays as the B5-style
   performance variant.
4. **The tip is a population argmax.** There is no `argmax` fold, so `lead` compares a
   helper `cx` with a `maximum`. `centroid(1)` cannot be read for a bound cell inside a
   fold, which is why `cx` exists. Float ties make two tips. `tip => stalk` forgets
   whether the cell was stalk or prolif, so a proliferating cell that becomes tip and
   loses the lead comes back as stalk. Proposal: `argmax(cx[c] for c in cells(k))`
   returning a `CellRef` (R6) [NEW fold], plus a cell variable holding the phenotype to
   revert to (expressible, but clumsy).
5. **Membrane sensing reads a stale rim.** An `integral` read by after-MCS updates is
   recomputed *right after the sweep* (AUTHORING §12.3). `rim` is itself an after-MCS site
   update, so `integral(V * rim)` uses the previous MCS's rim. Either allow a gather
   inside the `integral` body (`integral(V * any(owner[n] != owner for n in Moore(1)(site)))`)
   or use R15's rim reductions. The `v_a` units also differ: it is "pg", while V is
   pg/pixel. Mean-over-rim vs max-over-rim is UNSPECIFIED.
6. **Recruitment placement.** `@create` needs an "at" geometry. The obvious name `Ball` is
   already a *relation* (`Ball(r)`), hence `Sphere` [NEW]. Anchoring it at "where the
   previous cell detached" needs a model variable (`y_base`) written by a filtered
   population mean. That works, but it is order-sensitive within `@after_mcs`. The created
   cell paints over fluid and matrix sites. R8's ownership routine debits their volumes,
   but their targets do not change (UNSPECIFIED), so recruitment adds ECM pressure.
7. **`@convert` into a collective.** R8's `@convert from => to` is kind-to-kind. Here the
   destination is *the* single fluid cell, so the shape needed is `sites => ref`. That is
   the same shape as Jiang 2005's `@retire … sites => core`: one "move sites to a cell
   reference" primitive should serve both. `the(kind)` [NEW] (the unique live cell of a
   kind, or an error) is one spelling. The budget (0.3025/Δx² sites/MCS) is fractional for
   most Δx, so the budget needs stochastic rounding or carry-over. That is unspecified in
   R8.
8. **The VEGF field is stiff.** D_V·Δt/Δx² = 600/Δx² per MCS: about 1983 at 0.55 µm, so
   explicit Euler (2D FTCS, D·Δt/Δx² ≤ ¼) would need about 7900 substeps per MCS on about 302×193 sites. R14
   (implicit, per-field solver P6.0c) is therefore required, not a variant. The paper's
   own scheme is UNSPECIFIED. Also, `@sweep`'s `field_solver` accepts only `ExplicitEuler`
   today (`SweepSpec`).
9. **Pair counting.** Eq 1 sums J over *sites*, so each unlike pair may be counted twice.
   Potts counts unordered pairs once (AUTHORING §4). If the paper double-counts, every J
   is effectively 2× relative to kT = 2.5. The spec does not raise this. Add it to the
   author questions.
10. **Units with `spacing`.** The sketch relies on `Δ` using `spacing` (so D is in µm²/min)
    and on `position` being in lattice indices (for `at_wall`). AUTHORING does not say
    which. If `position` is Cartesian with spacing, the wall test must be `<= Δx`.
11. **Operating point from the initial state.** "Target = initial total" for the
    collectives has no clean spelling. `@before_mcs V_target ~ ifelse(mcs == 0, volume, Pre(V_target))`
    works but is a hack. Proposed: `initial(volume)` in the operating point [NEW].
12. **Checkerboard.** The global BFS (Friction 3) reads a whole cell. D-051 item 5 allows
    it, but GPU divergence at O(V) per failing local test on a ~260-site cell is the
    likely cost centre. Sequential is the natural reference.

## Open choices

| Choice | Default (spec / README) | Variant |
|---|---|---|
| Continuity | exact BFS soft penalty (B5) | local-ring drive |
| Uptake B | per EC, conservative (B6) | per EC site `min(β, V)` (07 form) |
| Chemotaxis evaluation | gaining EC only, `V(target) − V(source)` (07 Eq 3 reading; 05 §2.3 UNSPECIFIED) | also the losing EC; also when ECM gains from an EC |
| Domain | 166 × 106 µm (B3) | 100 × 160 µm (p.6) |
| Pixel size | **blocked** (B2); 0.55 µm only as a labelled development hypothesis | – |
| Neighbourhood | UNSPECIFIED; `Moore(1)` per the 2007 "second nearest" | VonNeumann(1), NeighborOrder(2) |
| Tip rule | leading EC by centroid x (07 p.8) | leading EC by max x extent |
| Degradation product | fluid (NOT IN PAPER, 05 §4 #21) | removed site stays matrix-free by another rule |
| Clock init | zero for recruits (05 p.6) | uniform random (no difference reported, V18) |
| Speed target | Fig 1A curve (B4) | Table 2 16.0 µm/h recorded, unexplained |
| Fig S1 elongated-cell set | – | J_{ee,em,ef} = {42, 76, 66}, χ_tip 1.55χ, χ_{stalk,prolif} 1.45χ (signs as printed) |
