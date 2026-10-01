# 10 — Akeeb, Marcus & Jiang 2026 leader/follower invasion: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** leader/follower tumour invasion. It has leader chemotaxis on a static cue,
  follower growth and clocked division, CC3D connectivity, and the published slab seeding
  with "ghost" leaders (D-068).
- **Paper:** Akeeb, Marcus & Jiang, *PLoS Comput Biol* 22(9): e1014747 (2026). The code is
  `Jiang-Lab/Leader_Follower_Invasion_Model` @ `0b9673f` (`S:` = `CCIecmSteppables.py`,
  `X:` = `CCIecm.xml`, `P:` = `CCIecm.py`).
- **Spec:** `../10_akeeb_invasion.md` (§2 mechanics, §3 parameters, §5.3 observables
  O1–O9, §7 D-list). Decisions: README §4.7 (A1–A6), D-050 (μ = 24), D-068 (ghost-leader
  seeding), D-069 (`find_peaks` port).
- **Existing port:** `lib/PottsModels/src/akeeb.jl` (`AkeebInvasion`, `akeeb_state`). This
  sketch is the faithful target it should converge to.
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature. `# [NEW]` means the feature is not on the
roadmap. `# [?]` means the primitives exist but this combination has not been tested. A line
with no tag uses only what exists at `monorepo` HEAD. Coordinates are 1-based (the code's
0-based y = our y − 1).

```julia
using Potts

@potts_model LeaderFollowerInvasion begin
    @structural_parameters begin
        lattice = (500, 300)                            # 10 p.4, Table 1; X:14
    end
    @kinds medium leader follower                       # X:37–38 (LC = 1, FC = 2)
    @parameters begin
        T      = 10.0                                   # Table 1; X:16
        λᵥ     = 2.0                                    # p.6, Table 1; S:88
        V₀     = 10.0                                   # initial target, all cells (S:87)
        μ      = 24.0                                   # leader chemotaxis λ; D-050 A5 (sample point, S:25)
        J_LF   = 2.0                                    # scanned −5:5 (p.6; S:37)
        J[kind, kind] = [0 2 10; 2 16 J_LF; 10 J_LF 5]  # (M, L, F) Table 1; X:53–57   [NEW] entry from a scalar parameter
        E_conn = 1e5                                    # Connectivity penalty (X:29–31); not in the paper (D7)
        f_grow = 0.015                                  # Table 1; S:20
        V_max  = 20.0                                   # growth cap and division size (S:113, S:143)
        PP     = 0.5                                    # P(follower competent), Bernoulli (S:131; D4)
        clock_min    = 75.0                             # S:143–146
        clock_spread = 50.0                             # randint(0, 50) → U{0…49}, redrawn each MCS (S:145; D3)
    end
    @variables begin
        cue(site)      = 0.0                            # c = y/g, g = 1, static (p.6; S:78–83)
        V_target(cell) = V₀
        clock(cell)    = -1.0                           # −1 = not competent (Python `None`)
    end
    @initialize begin                                   # [NEW] per-site/per-cell initial values, evaluated once at init
        cue   ~ position[2] - 1                         # 0-based y (S:83)
        clock ~ ifelse((kind == follower) & (rand() <= PP), floor(75rand()), -1.0)   # S:131–132: randint(0, 75)
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = Moore(1))  # X:18–19; contact order 2 = 8 nbrs (X:59)
    @relations proposal = VonNeumann(1)                 # Potts NeighborOrder 1 (X:17)
    @energy begin
        cells(leader, follower) => λᵥ * (volume - V_target)^2       # Eq 1 term 2
        contacts                => J[kind, kind′]                   # Eq 1 term 1
    end
    # CC3D Merks chemotaxis (default algorithm, X:66–73): once per copy if the gaining OR losing cell is a leader (D6)
    @drive copy => ifelse((kind[new] == leader) | (kind[old] == leader), -μ * (cue[target] - cue[source]), 0.0)
    # CC3D Connectivity: penalty unless the loser's 8-ring sites form exactly one arc; 0 arcs = last site (extinction guard)
    @drive copy => E_conn * ((old != 0) & (local_components != 1))
    @after_mcs begin                                    # S:111–147, same MCS, in this order
        V_target ~ ifelse((kind == follower) & (Pre(V_target) < V_max), Pre(V_target) + f_grow, Pre(V_target))
        clock    ~ ifelse(Pre(clock) >= 0, Pre(clock) + 1, Pre(clock))
    end
    @divide cells(follower) when = (clock >= 0) & (volume > V_max) & (clock > clock_min + floor(clock_spread * rand())),
        along = RandomPlane(), V_target => Split(), clock => 0.0          # S:151–163 (clone_parent_2_child)
    @observed begin                                     # cheap per-save counters; full metrics are docs analysis below
        n_leader   ~ count(true for c in cells(leader))
        n_follower ~ count(true for c in cells(follower))
        lonely(cell) ~ count(true for n in neighbors(c; relation = VonNeumann(1)) if n != 0) == 0   # O1/O6 [R11a][NEW relation kw]
    end
    @sweep Metropolis(; temperature = T)                # Eq 2
end

@named inv = LeaderFollowerInvasion()

# Initial layout (10 §2.3, §5.3.2; D-068). The slab has 1169 followers of 3×3 sites; the last column is clipped to 2×3.
slab    = Tiling((3, 3); region = (1:500, 1:21), kinds = [:follower], partial = :clip)   # X:121–131 [R2][NEW partial]
leaders = InsertUntil(:leader; into = :follower, size = 1, region = (2:500, 2:20),     # S:64–75: x ∈ 1…499, y ∈ 1…19
    fraction = 0.25, on_miss = :count, check = :after_hit, seed = 1)              # D-068 ghosts; `on_miss = :retry` variant [R2]
op, report = layout(overlay(slab, leaders), inv; report = true)                  # report.misses ≈ 7.9 ghosts (V-A1a) [NEW]

# The authors' "MCS t" is our state after t + 1 MCS (10 §5.3.2): 701 MCS for "700".
prob = PottsProblem(inv, op, (0, 701); seed = 1)
sol  = solve(prob, SequentialCPM(); saveat = [1, 101, 301, 501, 701])        # V-A0, V-A11, V-A2

# Scan: 11 J_LF × 11 μ × 11 PP × 10 replicates = 13,310 runs (p.6); the CI tier is P1–P9 (10 §5.3.4)
grid = vec(collect(Iterators.product(-5.0:5.0, 0.0:3.0:30.0, 0.0:0.1:1.0)))
scan(p, ctx) = ((j, m, pp) = grid[cld(ctx.sim_id, 10)];
    remake(p; u0 = first(layout(overlay(slab, remake(leaders; seed = ctx.sim_id)), inv; report = true)),  # [R2]
        p = [:J_LF => j, :μ => m, :PP => pp]))
ens = solve(EnsembleProblem(prob; prob_func = scan), SequentialCPM(), EnsembleThreads();
    trajectories = 10length(grid), saveat = [701])

# ── R16 observables O1–O8, docs analysis on saved states (D-051 item 6) ──────────────────
using Graphs
function invasion_metrics(u; kind_leader = 1)                  # u = sol.u[end]; code-exact definitions (10 §5.3.3)
    σ, K = u.σ, u.cell.kind
    g = contact_graph(σ; relation = VonNeumann(1), periodic = (true, false))  # O1 [R16] (or R11a neighbors at the boundary)
    seeds = unique(filter(!=(0), σ[1:(end - 1), 2]))                          # O2: row y = 1 (0-based), x ∈ 0…498
    M = Set(reduce(vcat, (c for c in connected_components(g) if any(in(c), seeds)); init = Int[]))
    top(pred) = [something(findlast(pred, σ[x, :]), 0) for x in axes(σ, 1)]  # O3 per-column profiles
    tm, to = top(in(M)), top(!=(0)); keep = (tm .> 0) .& (to .> 0)
    base = minimum(tm[keep]) - 1                                               # 0-based heights
    area(h) = trapz(findall(keep) .- 1, h[keep] .- 1 .- base)                  # O4 numpy.trapz, not periodic
    fingers = merge_peaks(find_peaks(tm[keep]; prominence = 10, distance = 10, width = 5), 15)  # O5, D-069 port [R16]
    ycom = cell_mean_y(σ); ymin = minimum(ycom[c] for c in M)
    singles = count(c -> K[c] == kind_leader && degree(g, c) == 0 && ycom[c] > ymin, vertices(g))   # O6 leaders only (D16)
    detached = count(c -> c ∉ M && !any(in(M), neighbors(g, c)) && ycom[c] > ymin, vertices(g))  # O7
    clusters = count(c -> length(c) >= 2 && !any(in(M), c) && any(v -> K[v] != kind_leader, c),
        connected_components(g))                                               # O8 FC-seeded (D17)
    return (; invasive = area(tm), infiltrative = area(to), fingers = length(fingers), singles, detached, clusters)
end
```

The helpers `contact_graph`, `cell_mean_y`, `trapz`, `find_peaks` and `merge_peaks` are
docs-level Julia (R16). `find_peaks` is the D-069 SciPy 1.7 port. `vertices(g)` must be
read as the alive cells only (Graphs.jl vertices also include medium and dead slots).

## Line → source

| Line / rule | Spec | Paper / code |
|---|---|---|
| `lattice = (500, 300)` | 10 §2.2, §3 | p.4, Table 1 p.7; X:14 |
| `boundary = (Periodic(), Closed())` | §2.2 | p.4, p.7 (x only); X:18, X:19 (y commented, so a CC3D wall) |
| `neighborhood = Moore(1)` (contacts) | §2.1 | X:59 `NeighborOrder 2` = 8 neighbours; not in the paper (D8) |
| `proposal = VonNeumann(1)` | §2.2 | X:17; not in the paper (D8) |
| `T = 10` | §2.2, §3 | Eq 2 p.4; Table 1; X:16 |
| `J[kind, kind]`, `J_LF` | §3 | Table 1 p.7; X:53–57; scan p.6, S:37 |
| `cells(…) => λᵥ(volume − V_target)²`, `λᵥ = 2`, `V₀ = 10` | §2.1, §2.3, §3 | Eq 1 term 2 p.4; S:86–88 |
| `contacts => J[kind, kind′]` | §2.1 | Eq 1 term 1 p.4 |
| Chemotaxis drive (either cell a leader, once) | §2.1 (D6), §3 | CC3D 4.6.0 `ChemotaxisPlugin.cpp` `merksChemotaxis`, `simpleChemotaxisFormula` (external); X:66–73; S:90–91. Paper Eq 1 term 3 differs (D6) |
| `μ = 24` | §3, §7.1 P1 | S:25 sample; README §4.7 A5; D-050 |
| `cue ~ position[2] − 1` | §2.3 "Field" | p.6 `c = y/g`, g = 1; S:78–83; D = 0 (X:75–119) |
| Connectivity drive `E_conn·(local_components ≠ 1)` | §2.1 "Connectivity" (D7), §7.1 P2 | X:29–31; CC3D 4.6.0 `ConnectivityPlugin.cpp` `changeEnergy` (external) |
| `V_target` growth | §2.4 (D5) | Table 1 `fgrow`; S:111–115 (all FC, cap 20) |
| `clock` initial value | §2.4 (D4), §3 | S:124–134 (`rand() <= PP`, `randint(0, 75)`) |
| `clock` tick | §2.4 | S:136–141 |
| `@divide … when` | §2.4 (D3), §7.1 P5 | S:143–147; paper p.6 "U(25,125)" differs (D3) |
| `along = RandomPlane()`, `V_target => Split()`, `clock => 0` | §2.4 | S:151–163; p.6 "random axes", "reset timers" |
| `@after_mcs` before `@divide`, same MCS | §2.2 "Per-MCS order", §7.1 P6 | P:5–26 registration order |
| `Tiling((3,3); … partial = :clip)` | §2.3, §5.3.2 | X:121–131 `UniformInitializer`, Width 3; 1169 followers (sample CSV row 0) |
| `InsertUntil(…; on_miss = :count, check = :after_hit)` | §2.3, §5.3.6 (MD-1) | S:64–75 (`new_cell` at :68, paint at :73–74, ratio at :75); D-068 |
| `(0, 701)`, `saveat = [1, 101, …, 701]` | §2.2, §5.3.2 (A6) | X:15 `Steps 701`; `invasion_metrics_0_mcs.csv` (MCS 0 is after one sweep) |
| Scan grid, 10 replicates | §3 | p.6; S:32–46 (`ITERATION % 1331`) |
| O1 adjacency (VN, x periodic) | §5.3.3 O1 | S:475–487; paper p.7 (von Neumann) |
| O2 main tumour | O2 (D19) | S:493–500; p.7 |
| O3, O4 profiles and areas | O3, O4 (D12, D13, D14) | S:617–657; paper p.7–8 differ |
| O5 fingers | O5 (D15); D-069 | S:659–671; p.8–9 |
| O6 singles, O7 detached | O6 (D16), O7 | S:521–531, S:541–554; p.9 |
| O8 clusters | O8 (D17) | S:559–612; p.9 |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds`, `@parameters`, cell/site `@variables`, `Lattice(…; boundary = (Periodic(), Closed()))`, `@relations proposal` | exists |
| `@energy` cells and contacts; `@drive copy => ifelse(…)` with `kind[new]`, `kind[old]`, `cue[target]` | exists (the current port uses it) |
| `local_components` in a drive (soft connectivity) | exists (R0, `db7eea2`; AUTHORING §5). The soft form is R4's acceptance sibling |
| `@after_mcs` with `Pre`, `rand()` in `@divide when`, `RandomPlane()`, `Split()`, reset `clock => 0.0` | exists |
| `count(… for c in cells(k))` in `@observed` | exists (population folds, `test/symbolic.jl` Census) |
| `position[2]` in a site expression | exists (D-043) in updates. Inside `@initialize` it is NEW |
| `@initialize` block (per-site and per-cell initial values from expressions, with `rand()`) | **NEW**, not on the roadmap. Workaround today: `@before_mcs … ifelse(mcs == 0, …, Pre(x))`, or the host-side `akeeb_state` |
| Kind-table entry from a scalar parameter (`J_LF` inside `J[kind, kind]`) | **NEW** (MTK parameter dependencies). Workaround: host-built matrix (`akeeb_contacts`) |
| `Tiling(…; partial = :clip)` | `Tiling` exists (P6.1a). `partial` is **NEW** |
| `InsertUntil(…; on_miss, check)` | planned **R2** (ROADMAP P6.2a). The `on_miss`/`check` keywords and the `report` are proposed here (**NEW**) |
| `layout(…; report = true)` returning layout metadata | **NEW** |
| `neighbors(c; relation)` | `neighbors(c)` is planned **R11a** (AUTHORING §12.3). The `relation` keyword is **NEW** |
| Metrics O1–O8 (`contact_graph`, BFS, per-column profile, `trapz`, `find_peaks`) | planned **R16** (docs, D-051 item 6; P6.2a); `find_peaks` port per D-069 |
| `EnsembleProblem` + `remake(p; u0, p)` | exists |

## Friction found

1. **The `Chemotaxis` helper cannot express CC3D's default (Merks) gate.**
   - `Chemotaxis(c; kinds, when)` ANDs its gate with `new != 0` (`src/vocabulary.jl:636`).
     So `when = (kind[new] == leader) | (kind[old] == leader)`, the form its own docstring
     suggests for "copies involving kind a", silently drops copies where the **medium**
     gains a leader site.
   - CC3D applies the leader's λ to those copies (the old cell is a leader).
   - The sketch therefore keeps the raw `@drive`.
   - Fix: a `Chemotaxis(…; parties = :either | :gaining | :losing)` keyword (the Merks
     either-cell gate is also 14a/14c's C7 and 11a's default), or document that `kinds`
     must be empty *and* `new != 0` must not be implied. This is an R0 follow-up, not
     R-new.
2. **The CC3D connectivity rule is `local_components != 1`, not `connectivity(k)`.**
   - `connectivity(k)` is `local_components <= 1`, so it *accepts* 0, the loser's last
     site in the ring.
   - CC3D penalises zero collisions. That is what keeps one-site leaders alive, which is
     why the port adds `@constraint no_extinction`.
   - The faithful form is one soft drive, `E_conn * ((old != 0) & (local_components != 1))`.
     It covers the arc rule and the extinction guard together, at 1e5 (effectively hard at
     T = 10).
   - This is equivalent to CC3D's "exactly two collisions" on the 8-ring only if
     `local_components` (face-connected pieces in the 3×3) equals the ring-arc count on
     every pattern. Consecutive 8-ring sites are face-adjacent and no others are, so it
     should. **A pattern-enumeration unit test (2⁸ rings) against `ring_arcs` should prove
     it**, and should become a sibling.
3. **There is no per-cell or per-site initialisation primitive.**
   - The static cue (`c = y`), the Bernoulli(PP) clocks and "every cell's target = 10" are
     all *initial conditions from expressions*. Today they are host code in `akeeb_state`,
     where they cannot see `PP` as a model parameter, so a `remake(p = [:PP => …])` does
     not re-draw them.
   - Workaround: `@before_mcs x ~ ifelse(mcs == 0, init, Pre(x))`. It costs an O(sites)
     pass every MCS for the cue, and it hides the intent.
   - Proposal: `@initialize` (NEW, the MTK analogue is initialization equations), with
     assignment semantics. Addressed `rand()` streams make it reproducible and
     `remake`-aware.
4. **Kind tables cannot contain parameters.** Scanning `J_LF` needs a host-built 3×3 matrix
   (`akeeb_contacts`) and `remake(p = [:J => …])`. MTK-style parameter dependencies
   (`J[L, F] = J_LF`) would make the scan a scalar `remake` and make `J_LF` an SII
   parameter visible in `sol.ps`. The same need appears in 09 (J_dl scans) and 11a
   (sensitivity scans of J entries).
5. **The InsertUntil semantics are subtle, and the general primitive needs three knobs.**
   - `on_miss = :count | :retry | :skip`: what happens when a draw lands on a non-`into`
     site (here, an existing leader).
   - `check = :after_hit | :every_draw`: when the quota is re-tested. The authors test
     only after a hit (S:75), which is why the inventory can overshoot to 391 or 392.
   - What the `fraction` counts: the inventory, *including* counted misses.
   - Under D-066 X2 a ghost is never allocated, so V-A1(a) ("inventory = 390") cannot be
     checked from the operating point. The layout must **report** its misses, and an
     operating point has no slot for layout metadata.
   - This is a composition gap between R2 and D-066. It is harmless for dynamics (ghosts
     are inert).
6. **`Tiling` paints whole boxes only.** On x = 1:500 it gives 166 × 7 = 1162 followers,
   not 1169. CC3D `UniformInitializer` clips the last column to 2×3. A `partial = :clip |
   :skip` keyword is needed; `:skip` stays the default to keep P6.1a's behaviour.
7. **The metrics do not fit `@observed`.** O2–O8 need:
   - graph components seeded by a site predicate (row y = 1);
   - per-column max-y profiles, which are group-by-axis site reductions;
   - `trapz`;
   - SciPy `find_peaks`;
   - component membership tests.

   None of these is a fold over cells or relations. Only the per-cell "isolated" flag
   (O6) and simple counts are expressible, and only once `neighbors(c)` (R11a) takes a
   **relation**: O1 adjacency is von Neumann while the contact relation is Moore(1).
   R11a as specified iterates the *contact* relation, so without a `relation` keyword it
   gives the wrong singles. The analysis therefore lives in docs (D-051 item 6).

   D-069's tested `find_peaks` port (BSD notice, hand-built fixtures) is library-grade code
   whether or not it sits in a docs page. It is the first R16 piece that arguably "has
   merit" as a reusable module. Decide where it lives before P6.2a (docs `src/` helper,
   PottsModels test utility, or a thin `lib/PottsAnalysis`).
8. **The phase order is implicit.** The faithful per-MCS order is sweep → (metrics) →
   growth → clock → division (S:111–163). The sketch relies on `@after_mcs` running before
   `@divide` within an MCS. That holds today but is undocumented (spec §7.1 P6: "verify"),
   and it is exactly the R5 "explicit phase order" gap. The authors' metrics run *before*
   growth, which we reproduce only via the t + 1 sampling rule.
9. **The t + 1 sampling rule is a footgun.** Every target needs `saveat = t .+ 1`. It is
   correct (the authors' MCS 0 is after one sweep), but a tutorial must say it loudly; the
   frozen test should encode it once as a helper.
10. **Scan ergonomics.** Re-drawing the layout per replicate inside `prob_func` means
    building a fresh layout (host, O(sites)) per trajectory. That is fine, but
    `EnsembleProblem` has no notion of "u0 depends on seed", so the layout seed and the
    solver seed are managed separately. A small `seeded(layout)` or `u0 = seed -> …`
    convention would help all 12 models.

## Open choices

| Choice | Default (spec / decision) | Variant |
|---|---|---|
| Leader creation (D1) | Insert one-site leaders; misses counted as ghosts (D-068, MD-1 "emulate authors") | `on_miss = :retry` (exactly 390 painted, today's port); `leaders = :reassign` (paper "reassigned", README §4.7 A1): re-kind 25 % of the followers |
| Chemotaxis form (D6) | CC3D Merks ΔH = −μ Δcue, once, when either cell is a leader (A3) | Paper Eq 1 absolute potential: `@energy sites => -μ * cue * (kind == leader)`, which is expressible today; magnitudes differ by orders |
| Division timer (D3) | Per-MCS hazard: `clock > 75 + U{0…49}`, redrawn each MCS (A2) | Paper: one `U(25, 125)` draw per cycle: `when = clock > t_div` with `t_div => Redraw(Uniform(25, 125))` [R3 `rand(dist)`] |
| Competence (D4) | Bernoulli(PP) per follower (S:131) | Paper "subset of size PP·N_FC": an exact-count labelling, a population-level draw (NEW; a layout-time `Label(k of n)` would do) |
| Growth (D5) | All followers grow while target < 20 (S:113) | Competent followers only |
| Connectivity (D7) | Soft 1e5 on `local_components ≠ 1` (X:29–31) | Hard `@constraint connectivity(leader, follower)` + `no_extinction` (today's port; ≈ equal at T = 10) |
| Neighbourhoods (D8) | Proposals VN(1), contacts Moore(1) (X:17, X:59) | — (paper silent) |
| μ default | 24 (D-050 A5) | 30 (old port) |
| Duration | 701 MCS for the authors' 700 (A6, §5.3.2) | 700 |
| Metrics (D12–D18) | Code definitions O1–O8 (A4) | Paper definitions as extra observables: volume-sum invasive area, convex-hull infiltrative area, spline-smoothed front, ≥ 20 px finger separation, singles incl. followers, leader-only clusters |
| Phenotype classifier (D18) | PARKED (V-A6); the area-equality classifier matches Fig 5B | fingers/singles/clusters classifier (Fig 5A) |
