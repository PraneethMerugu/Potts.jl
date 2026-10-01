# 07 — Bauer, Jackson & Jiang 2007 sprouting angiogenesis: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** `Bauer2007`. A 2D CPM of one endothelial bud invading a stroma of matrix
  fibres, interstitial fluid and immobile tissue cells, coupled to a VEGF
  reaction–diffusion field with a line source at the tumour side.
  - The leading EC (tip) is the only chemotactic cell, and it degrades matrix.
  - ECs at a fixed distance behind the tip grow and divide on an 18 h cycle.
- **Paper:** Bauer AL, Jackson TL, Jiang Y, Biophys. J. 92, 3105–3121 (2007),
  doi 10.1529/biophysj.106.101501. No code is released.
- **Spec:** `../07_bauer2007_sprouting.md` (§2, §3, §7). Decisions: README §4.3 B1, B2, B6–B9
  (D-050). **Gate B2:** the pixel size is unknown, and 0.55 µm/site is used below only as the
  labelled development hypothesis.
- **Date:** 2026-09-30.

Tags: `# [R#]` = planned roadmap feature; `# [P6.x]` = a planned ROADMAP step-0 item;
`# [NEW]` = not on the roadmap; `# [?]` = the primitives exist but this combination is
untested. An untagged line uses only what exists at `monorepo` HEAD.

```julia
using Potts
using OrdinaryDiffEq, LinearSolve, NonlinearSolve       # R14 field solvers, loaded by the user

@potts_model Bauer2007 begin
    @structural_parameters begin
        Δx = 0.55                     # µm/site: UNSPECIFIED (07 §3.3); B2 hypothesis, gated
        lattice = (302, 193)          # 166 × 106 µm (07 Figs 3, 4, 6); Fig 7: (302, 578)
        order = 2                     # "second nearest neighbors" = shells 1–2: UNSPECIFIED (07 §3.3, Q1)
        d_prolif = 8.9                # µm behind the tip: B9 inference; Fig 5: 0, 8.9, 26.6, :base
        gradient = :shallow           # :steep = no source (07 §2.6, H1)
        vegf_gated = false            # H1: proliferation also needs v_p (07 §2.4)
        exclusive = true              # proliferating cells are not chemotactic (07 p.8); false = W5
    end
    @kinds medium fluid matrix tissue endothelial inert[frozen]   # medium owns no sites (Friction 1)
    @parameters begin
        kT = 0.01                                               # Table 1
        J[kind, kind] = [0  0  0  0  0  0;                      # Table 1 (medium row unused)
                         0 35 35 32 32 32;                      # fluid:  J_ff J_fm J_ft J_ef
                         0 35  5 30 16 16;                      # matrix: J_mm J_mt J_em
                         0 32 30  2 31 31;                      # tissue: J_tt J_et
                         0 32 16 31  1  1;                      # EC:     J_ee
                         0 32 16 31  1  1]                      # inert = EC: UNSPECIFIED
        γ[kind] = [0.0, 0.1, 0.4, 1.2, 1.0, 1.0]               # γ_f γ_m γ_t γ_e (Table 1; Figs 3, 5: γ_e 0.7, γ_t 0.8)
        μ = -1.5e5                                              # tip chemotaxis (Table 1)
        Dv = 3.6e-4 * 1e8 / Δx^2                                # cm²/h → site²/MCS (1 MCS = 1 h, 07 p.8)
        λv = 0.6498                                             # h⁻¹ = MCS⁻¹
        β = 0.06                                                # pg/EC/h (07 p.5)
        S = 0.035                                               # pg/site at x = L₁ (07 p.6)
        v_a = 1.0e-4                                            # pg, activation (07 p.8)
        v_p = 5.0e-3                                            # pg, H1 proliferation (07 p.9)
        τ_cycle = 18                                            # h = MCS (07 p.8)
        V₀ = π * 5.0^2 / Δx^2                                   # EC ≈ 10 µm diameter: UNSPECIFIED size (07 p.6, §3.3)
        ℓ = 8.9                                                 # µm per cell length (07 §3.2, 26.6/3)
        p_deg                                                   # UNSPECIFIED (07 §2.4 degradation rate)
    end
    @variables begin
        V(field) = 0.0
        V_target(cell) = volume       # [NEW] default from the initial state; collectives: UNSPECIFIED (07 §3.3)
        active(cell) = 0.0
        tip(cell) = 0.0
        prolif(cell) = 0.0
        clock(cell) = 0.0
        cx(cell) = 0.0
        x_tip(model) = 0.0
    end
    @lattice Lattice(lattice; boundary = (Closed(), Periodic()), neighborhood = NeighborOrder(order))  # CPM BCs UNSPECIFIED
    @relations proposal = NeighborOrder(order)
    @energy begin
        cells => γ[kind] * (volume - V_target)^2               # Eq 2, volume term (07 p.7)
        contacts => J[kind, kind′]                              # Eq 2, adhesion
    end
    chemotactic = exclusive ? (tip[new] > 0) && (prolif[new] == 0) : tip[new] > 0
    @drive Chemotaxis(V; strength = -μ, when = chemotactic)    # Eq 3: μ(V(x) − V(x′)), x = target
    @constraint kind[new] == endothelial                        # only ECs invade (07 p.7; B8)

    # 07 §2.5 step 2: activation, then tip vs proliferating, before the MCS
    @before_mcs begin
        cx ~ centroid(1)
        active ~ (kind == endothelial) * ifelse(integral(V) >= v_a, 1.0,
                                                gradient === :steep ? 0.0 : Pre(active))   # [?] v_a is pg: reads ∫V over the cell
        x_tip ~ maximum(cx[c] for c in cells(endothelial) if active[c] > 0)                 # [?] "leading EC" (07 p.8)
        tip ~ (active > 0) * (cx == x_tip)                                                  # ties: Friction 4
        clock ~ Pre(clock) + 1                                  # cycle clock; ticking rule UNSPECIFIED
        V_target ~ ifelse(kind == endothelial, ifelse(prolif > 0, 2V₀, V₀), Pre(V_target))  # A^T = 2 × initial (07 p.7)
    end
    gate = vegf_gated ? integral(V) >= v_p : true               # H1 only (07 p.9)
    if d_prolif === :base
        @before_mcs prolif ~ (active > 0) * gate * (cx == minimum(cx[c] for c in cells(endothelial)))
    else
        @before_mcs prolif ~ (active > 0) * gate * (abs((x_tip - cx) * Δx - d_prolif) <= ℓ / 2)  # region at fixed distance (07 p.14)
    end
    @divide cells(endothelial) when = (prolif > 0) && (volume >= 2V₀) && (clock >= τ_cycle),
        along = RandomPlane(), clock => 0.0, V_target => V₀    # plane UNSPECIFIED; daughter gets a new id (07 p.8)
    @convert sites(matrix) => the(fluid),                                                   # [R8][R6] product UNSPECIFIED
        when = any(tip[owner[n]] > 0 for n in VonNeumann(1)(site)), p = p_deg               # tip degrades matrix (07 p.8)
    if gradient === :steep
        @transition cells(endothelial) => inert when = active == 0                          # [R3][P6.0d] "deactivate and become inert" (07 p.9)
    end

    @equations D(V) ~ Dv * Δ(V) - λv * V - uptake(V; max = β, by = kind == endothelial, per = :cell)  # [R15] Eq 1, B6 per cell
    @boundary V begin                                                                        # [R5] 07 p.6
        x => (Dirichlet(0.0), gradient === :shallow ? Dirichlet(S) : NoFlux())               # steep BC UNSPECIFIED (07 §2.6)
    end                                                                                      # y periodic from the lattice
    @initialization_equations 0 ~ Dv * Δ(V) - λv * V - uptake(V; max = β, by = kind == endothelial, per = :cell)  # [R14][NEW syntax] B7
    @schedule before_mcs, copies, fields, lifecycle            # [R5][NEW syntax] 07 §2.5 steps 2–6
    @sweep Metropolis(; temperature = kT, law = UnlikeNeighbor(),                           # [R10] 07 p.7
                      field_solver = Adaptive(KenCarp4(linsolve = KrylovJL_GMRES())))       # [R14] Friction 6
end

@named sys = Bauer2007(; p_deg = 0.0)       # UNSPECIFIED: 0.0 = degradation off until Q4 is answered
stroma = overlay(Fill(:fluid),                                                    # [R2][NEW] one collective cell
    Fibres(; fraction = 0.37, width = 1.1 / 0.55, angles = nothing, length = nothing, # [R2] 07 p.6; angle set, length UNSPECIFIED (07 §2.7)
           kind = :matrix, as = OneCell(), seed = 1),                             # [NEW] collective option
    Scattered(30, (14, 14); kinds = [:tissue], seed = 2),                         # ≈30 cells ≈7.5 µm, read from Fig 2: count/placement UNSPECIFIED
    Spheres([(10, 97)], 9; kinds = [:endothelial]))                               # [R2] one bud at the parent vessel (Fig 2)
prob = PottsProblem(sys, layout(stroma, sys), (0, 398); seed = 1)                # 16.6 d = 398 MCS (07 §3.2)
ens  = solve(EnsembleProblem(prob; trajectories = 12), SequentialCPM(); saveat = 0:24:398)   # n = 12 (Fig 5, Table 2)
speed(sol) = sprout_length(sol) / (sol.t[end] / 24)                               # [R16] µm/day (Table 2, W2)
```

(≈ 105 lines of code.)

## Line → source

| Line | Spec | Paper |
|---|---|---|
| `kT = 0.01`, Metropolis | 07 §2.2 | p.7 [3111]; Table 1 p.6 |
| `J[kind, kind]` values | 07 §3.1 | Table 1 p.6 [3110] |
| `γ[kind]`; Figs 3, 5 values | 07 §3.1 | Table 1; Fig 3, 5 captions |
| `cells => γ(volume − V_target)²` | 07 §2.3 | Eq 2 p.7 [3111] |
| `contacts => J` | 07 §2.3 | Eq 2 |
| `Chemotaxis(V; strength = −μ, when = tip)` | 07 §2.3 (x/x′ reading), §2.4 | Eq 3 p.7; tip-only p.8 [3112] |
| `exclusive` gate | 07 §2.4 | p.8 "if the cell is proliferating, it cannot move chemotactically"; W5 p.11 |
| `@constraint kind[new] == endothelial` | 07 §2.1, §6 G8; B8 | p.7 "Only endothelial cells are allowed to … invade" |
| `NeighborOrder(2)` proposal, `UnlikeNeighbor()` | 07 §2.1, §3.3 | p.7 "unlike second nearest neighbors" |
| `active` from `v_a` | 07 §2.4 | p.8; Table 1 |
| `x_tip`, `tip` (leading EC) | 07 §2.4, §6 G10 | p.8 "defined as the leading endothelial cell" |
| `prolif` at `d_prolif` | 07 §2.4, §3.2, §7.1 item 3; B9 | p.8; Fig 5 p.11; p.14 "fixed distance from the tip" |
| `V_target = 2V₀` when proliferating | 07 §2.3 | p.7 "twice its initial volume" |
| `@divide … clock >= 18`, daughter id | 07 §2.4 | p.8 "doubled in size and … 18 h"; new ID |
| `vegf_gated`, `v_p` | 07 §2.4 | p.9 [3113] (H1) |
| `@transition … => inert` (steep) | 07 §2.4 | p.9 "deactivate and become inert" |
| `@convert sites(matrix)` | 07 §2.4, §6 G7 | p.8 degradation (+5 % speed, W6) |
| `D(V) ~ DΔV − λV − B` | 07 §2.6 | Eq 1 p.5 [3109]; B p.6 [3110] |
| `uptake(…; max = β, per = :cell)` | 07 §2.6, §7.1 item 4; B6 | p.5 β derivation; p.6 B = min(β, V) |
| `@boundary V`: 0 / S, periodic y | 07 §2.6 | p.6 BCs |
| steep: no source | 07 §2.6 | p.9 "do not provide a source" |
| `@initialization_equations` steady state | 07 §2.5 step 1, §7.1 item 1; B7 | p.8 "steady-state solution … initial" |
| `@schedule before_mcs, copies, fields, lifecycle` | 07 §2.5 | p.8 Hybridization |
| lattice 166 × 106 µm; Fig 7 166 × 318 µm | 07 §2.1 | Figs 3–7 axes |
| fibres 37 %, 1.1 µm, 0–180° | 07 §2.7 | p.6 [3110] |
| tissue cells ≈ 30 | 07 §2.4 | Fig 2 p.5 (read from figure) |
| 398 MCS, n = 12 | 07 §3.2, §2.1 | captions p.9–13; Fig 5; Table 2 |

## Status of primitives used

| Primitive | Status |
|---|---|
| Kind-indexed tables `J[kind, kind]`, `γ[kind]` | exist (`test/symbolic.jl:709`) |
| `Chemotaxis(V; strength, when)` with a cell variable of `new` in `when` | exists (R0); `tip[new]` in `when` [?] |
| `@constraint kind[new] == endothelial` | exists (README §2.2 footnote) |
| `centroid(1)` in cell updates; `integral(V)` in cell updates | exist (AUTHORING §12.2, §12.3) |
| Population `maximum`/`minimum` fold in a model or cell update, with a filter | exists (hoisted, `schedule.jl`); filtered over a cell variable [?] |
| Mixed cell/model updates in one `@before_mcs`, ordered by dependencies | exists (D-042) |
| `@divide … along = RandomPlane()`, state rules | exists |
| Conditional sections on structural symbols | exists |
| `inert[frozen]` + `@transition` to it | planned: R3 `@transition` (P6.4c) + P6.0d frozen-mask refresh |
| `@convert sites(k) => ref, when, p` | planned, R8 (P6.5b); destination as a cell reference needs R6 (`the(fluid)` is NEW syntax) |
| `uptake(V; max, by, per = :cell)` | planned, R15 (P6.8); keyword shape proposed here |
| `@boundary V begin x => (…) end` | planned, R5 (AUTHORING §12.5 syntax) |
| `@initialization_equations 0 ~ …` (steady initial field) | planned, R14 (P6.8); **MTK-style syntax NEW** |
| `Adaptive(KenCarp4(…))` as a *field* solver | planned, R14 (today `Adaptive` is for cell and model ODEs only) |
| `law = UnlikeNeighbor()` | planned, R10 (P6.4b) |
| `@schedule …` | planned, R5 (phase order); **syntax NEW** |
| `Fill`, `OneCell()` collective layers | **NEW** (R2 has `Frame` as one cell, but no general "paint as one cell") |
| `Fibres`, `Spheres` | planned, R2 |
| `V_target(cell) = volume` (default from an expression of built-ins at t₀) | **NEW** (MTK has `initialization_eqs`/defaults of expressions) |
| `sprout_length`, branch/loop detection | planned, R16 (docs) |

## Friction found

1. **The model has no medium, but the DSL requires one.** Kind 0 is always the medium, and
   the medium has no volume. In Bauer 2007, "fluid" (σ = 0 in the paper) is a collective
   with a volume term γ_f(a − A)². The sketch therefore declares a dummy `medium` that owns
   no sites. That costs a dead J row, and any `old == 0` or `new == 0` test silently means
   "never".
   - P6.0g kind classes help in gates, but not with this. The real gap is that "medium"
     conflates two meanings: background sites, and a kind with no cell energy.
   - Options: allow `@kinds` with no medium (`@kinds nomedium fluid …`), or allow
     `cells(medium)` energies on a collective medium.
2. **Collectives make J_ff = 35 and J_mm = 5 dead parameters.** If the fluid and the matrix
   are each one σ, as p.7 says, same-cell pairs never count, so Table 1's J_ff and J_mm
   never enter H. Either the paper lists them for completeness, or each fibre bundle (or
   site) had its own σ. This matters for the fibre layout: one cell, or one cell per bundle
   (`as = OneCell()` against the per-box default). **New ambiguity, not in 07 §7:** add it
   to the author questions.
3. **"Initial volume" needs a default computed from the state.** The collectives' target
   volumes are unspecified. The natural reading is their initial volumes, and the EC
   A^T = 2 × initial volume. The DSL has no way to say `V_target(cell) = volume` at t₀; the
   workaround is to compute it host-side in the operating point. The same issue hits the
   daughters: division state rules are evaluated in the parent's environment
   (`compile.jl:612`), so a daughter cannot record its own birth volume. AUTHORING §12.7's
   planned `daughter` index would help. The sketch sidesteps this with a single `V₀`
   (UNSPECIFIED).
4. **"Leading cell" is an argmax, and ties are fragile.** `tip ~ cx == x_tip` compares
   floats: two ECs with equal `cx` are both tips, and a tip whose `cx` changes between the
   two stages is none. The review asks for "a population argmax of any cell expression"
   (§4). This needs a reference-valued fold such as
   `tip_ref ~ argmax(cx[c] for c in cells(endothelial))` (R6, NEW syntax) and then
   `tip ~ id == tip_ref`.
   The Fig 5 variant "three cell lengths behind" is naturally a **rank** from the tip,
   `count(c for c in cells(endothelial) if cx[c] > cx)`. That is a fold correlated with the
   current cell, which the fold hoisting in `schedule.jl` cannot express (it hoists
   uncorrelated folds into one model slot). The sketch uses a distance band (ℓ = 8.9 µm)
   instead, which is an approximation of "cell lengths".
5. **Bootstrap gap (new; not in 07 §7).** The start state is one EC. It is the tip, and
   with `exclusive = true` and `d_prolif = 8.9` no cell is "behind" it, so nothing ever
   divides and the sprout cannot grow. The paper must have had a rule for the first
   divisions (the tip proliferates while alone? the region is measured from the tip's
   rear?). The sketch reproduces the stall faithfully. Ask Jiang (extends Q3).
6. **The field is far outside explicit stability.** At 0.55 µm/site,
   D = 3.6 × 10⁴ µm²/h ≈ 1.2 × 10⁵ site²/MCS. Explicit Euler would need about 5 × 10⁵
   substeps per MCS.
   - The diffusion time across the domain (≈ 0.8 MCS) is shorter than one MCS, so each MCS
     is effectively quasi-steady. An implicit single step (R14) and a per-MCS steady solve
     (`0 ~ …`, the R14 quasi-steady form) are both defensible readings of "Eq 1 is solved
     for the next time step" (07 §2.5).
   - This makes R14 **mandatory** for 07, not just for the initial condition.
   - The B2 pixel-size gate changes the stiffness by (Δx)⁻², so the solver choice cannot be
     frozen before Jiang answers.
7. **`min(β, V)` uptake is non-smooth, and its shape is ambiguous.** Per cell (B6), the EC
   removes min(β, amount in the cell) per MCS, but how that is taken from the cell's sites
   is unstated (uniformly? proportional to V?). In an implicit solve the `min` is a kink;
   D-065 Q8 ("once per MCS, operator split") avoids that by applying uptake outside the
   PDE solve. The sketch nevertheless writes it inside `D(V) ~ …` as R15 sugar, and the
   lowering must pull it out into the split, or the user writes it as a
   `CellOperator`. The `uptake` keyword surface (`max`, `per = :cell`, the distribution
   rule) needs deciding in R15. It also appears in the steady initialization equation,
   where operator splitting has no meaning: the steady state must include a smooth or
   exact per-cell sink.
8. **`@convert` needs a cell destination, not a kind.** Degraded matrix becomes fluid, which
   is one existing collective cell. If `@convert` only takes a destination kind, R8 would
   create a new fluid cell per converted site. The destination must be a cell reference
   (R6), here `the(fluid)`, the unique cell of a kind: NEW syntax. Also:
   - rate, product and site choice are UNSPECIFIED (Q4);
   - the matrix collective's `V_target` must shrink with it, or the γ_m term pushes back.
     That is another UNSPECIFIED rule (07 §3.3 target volumes).
9. **Restricted sources.** `@constraint kind[new] == endothelial` together with an
   unlike-neighbour law wastes attempts: the law picks an unlike neighbour that is fluid,
   and the constraint then rejects it. A source predicate in the law,
   `UnlikeNeighbor(; source = kind == endothelial)`, would draw only admissible pairs.
   That changes the kinetics, so it needs its own D-052-style note. A scientific
   consequence of B8 to record in the tutorial: an EC can never lose a site to the stroma.
   ECs cannot retract, and sprout thinning happens only through EC–EC copies.
10. **Phase order is essential, not cosmetic.** The paper's order is rules → CPM → B → PDE
    (07 §2.5). The Merks sketch needs fields → CPM. The same `@schedule` vocabulary
    (R5) has to express both. The `inert` transition must fire at the lifecycle phase so
    that the frozen mask (P6.0d) is refreshed before the next sweep.
11. **Layout collectives.** `overlay` warns when a partly covered cell is left
    disconnected (AUTHORING §12.8). The fluid and matrix collectives are disconnected by
    design, so every run warns. A `Fill(kind)` or `as = OneCell()` layer should mark the
    cell as an expected multi-piece collective. Tissue-cell placement ("jittered grid",
    Fig 2) is closest to `Tiling` with a jitter option: small R2 addition.
12. **`v_a` is in pg, V in pg/site.** Activation compares the amount integrated over the
    cell (`integral(V)`) with v_a. That is our reading, and it makes activation
    cell-size-dependent. A per-site maximum or mean are the alternatives, both expressible
    today.
13. **Good composition to record.** Tip-only chemotaxis is exactly the library
    `Chemotaxis(V; strength, when)`, since here only a gaining EC is chemotactic (contrast
    01 Friction 1). The division rule, the 18-MCS clock and the population-fold tip reuse
    the Akeeb and OpenVT idioms unchanged.

## Open choices

| Choice | Default in this sketch (spec/decision) | Variant |
|---|---|---|
| Pixel size | 0.55 µm/site, labelled hypothesis (B2, gate) | author answer |
| "Second nearest neighbours" | shells 1–2, `NeighborOrder(2)` (UNSPECIFIED) | 2nd shell only (diagonals); an adhesion neighbourhood different from the proposal one |
| Proposal law | unlike-neighbour + EC-only sources (B8) | free sources; plain uniform-neighbour law |
| Proliferating region | one cell ≈ 8.9 µm behind the tip (B9, inference) | 0 (tip), 26.6 µm, base (Fig 5); non-exclusive (W5) |
| Tip identification | max x-centroid among active ECs | frozen tip identity; rank-based (Friction 4) |
| Uptake | per cell, conservative, once per MCS (B6, D-065 Q8) | per site, min(β, V) at each EC site |
| Initial field | steady state of Eq 1 (B7) | V = 0 (p.6 literal) |
| Transient field | implicit (KenCarp4 + GMRES), one MCS = 1 h | quasi-steady per MCS (`0 ~ …`) |
| Steep-gradient right BC | no-flux (UNSPECIFIED, 07 §2.6) | V = 0 |
| Deactivation | steep variant only; frozen `inert` kind | stays mobile but non-chemotactic |
| Degradation | off (`p_deg = 0`) until Q4 | matrix → fluid at tip-adjacent sites with p_deg |
| Collectives | fluid and matrix each one cell (07 §2.3, D-066) | one cell per fibre bundle (Friction 2) |
| Division plane | random (UNSPECIFIED) | major-axis split |
| Fig 7 | 5 buds on (302, 578) | — |
