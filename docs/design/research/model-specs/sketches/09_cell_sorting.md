# 09 — Differential-adhesion cell sorting: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** differential-adhesion cell sorting, two variants that share one mechanism
  (adhesion + area constraint + Metropolis copies):
  - **GG**, Graner & Glazier (the faithful target for the existing `GranerGlazier`);
  - **OS**, the Chaste cellular Potts benchmark of Osborne et al. (no port yet).
- **Papers:** 09a Graner & Glazier, PRL 69, 2013 (1992); 09c Glazier & Graner, PRE 47, 2128
  (1993); 09b Osborne et al., PLoS Comput Biol 13, e1005387 (2017), with the Chaste code
  `CellBasedComparison2017` (CBC).
- **Spec:** `../09_cell_sorting.md` (§2, §3, §8, §9). Decisions: README §4.6 (S1–S6), D-059,
  D-063.
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature. `# [NEW]` means the feature is not on the
roadmap. `# [?]` means the primitives exist but this combination has not been tested. A line
with no tag uses only what exists at `monorepo` HEAD.

```julia
using Potts
const PAPER_MCS = 16      # 1 paper MCS = 16 × (all lattice sites) attempts = 16 of our MCS (09c p.2130; 09 §8.5)

# ── Variant GG (09a/09c) ──────────────────────────────────────────────────────────────
@potts_model DifferentialAdhesion begin
    @structural_parameters begin
        lattice  = (247, 247)     # FULL start: 1000 cells + 10-site margin (09 §9.0); paper size UNSPECIFIED (09 §8.4 A-GG5)
        boundary = Periodic()     # UNSPECIFIED (09 §8.4); dispersal runs need margin ≥ 60 (V-PRE14/15)
    end
    @kinds medium dark light
    @parameters begin
        λ = 1.0                                         # 09c p.2129–2130; 09a p.2014
        V₀[kind] = [-1.0, 40.0, 40.0]                   # A_τ per type; A_M < 0 is off via θ (09c p.2130); Fig 28: A_l = 20
        T = 10.0                                        # 09c p.2139; 09a p.2014
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]    # (M, d, l) 09c p.2139, 09a p.2015; J(M,M) unused
    end
    @lattice Lattice(lattice; boundary, neighborhood = Moore(1))   # "second-nearest-neighbor", n = 8 (09c p.2129, 2132)
    @relations proposal = Moore(1)                      # "one of the eight neighboring sites" (09c p.2130)
    @energy begin
        contacts => J[kind, kind′]                      # Eq 2, bond sum; like-spin bonds 0 (09c p.2129)
        cells(dark, light) => λ * (volume - V₀[kind])^2 # Eq 2, area term × θ(A_τ)
    end
    pair(a, b) = ((kind == a) & (kind′ == b)) | ((kind == b) & (kind′ == a))
    @observed begin                                     # 09c §II D1: unweighted mismatched Moore bonds
        N_mm ~ count(true for _ in contacts)            # [NEW] population fold over contact pairs
        N_dl ~ count(pair(dark, light) for _ in contacts)     # [NEW]
        N_dd ~ count(pair(dark, dark) for _ in contacts)      # [NEW]
        N_ll ~ count(pair(light, light) for _ in contacts)    # [NEW]
        N_dM ~ count(pair(dark, medium) for _ in contacts)    # [NEW]
        N_lM ~ count(pair(light, medium) for _ in contacts)   # [NEW]
        Δa   ~ mean(volume for c in cells(light)) - mean(volume for c in cells(dark))   # V-GG6
    end
    @sweep Metropolis(; temperature = T)                # Eq 3; T ≤ 0 ties accepted with ½ (09c p.2130)
end

@named gg = DifferentialAdhesion()
ball = Circle(Point(124.0, 124.0), sqrt(40_000 / π))    # 247² lattice centre; = graner_glazier_aggregate(1000; margin = 10)
start(seed) = layout(Voronoi(RandomPoints(1000; region = ball, seed); region = ball, lloyd = 30,
                             kinds = [:dark, :light]), gg)   # D-063, D-138 (core Voronoi)
prob = PottsProblem(gg, start(1), (0, PAPER_MCS * 20_000); seed = 1)   # FULL: 2×10⁴ paper MCS (09 §9.0)
alg  = SequentialCPM()
ts   = PAPER_MCS .* [1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 32, 40, 50, 64, 80, 100, 1000, 10_000, 20_000]
ens  = solve(EnsembleProblem(prob; prob_func = (q, ctx) -> remake(q; u0 = start(ctx.sim_id))), alg,
             EnsembleThreads(); trajectories = 10, saveat = ts)       # n = 10 (09 §9.0)

# Statistics on a copy annealed 2 paper MCS at T = 0 with the run's own J, λ, V₀ (09c p.2134; D-059; S2)
annealed(q, u) = solve(remake(q; u0 = u, p = [T => 0.0], tspan = (0, 2PAPER_MCS)), alg).u[end]   # [?] u0 = saved state
F(q, u, N) = (a = annealed(q, u); a[N] / a[N_mm])      # [R16] fraction of all mismatched bonds (09 §9.0)
# R16 sugar: sol[N_dl / N_mm; on = Annealed(2PAPER_MCS)]                            # [R16][NEW syntax]

# Regimes are parameter remakes (09c §8.3); every row anneals under its own J and T (D-059)
regimes = (checkerboard = [J => [0 12 12; 12 8 6; 12 6 10]],                     # V-PRE9
           reversal     = [J => [0 16 30; 16 2 11; 30 11 14]],                   # V-PRE12 (J_lM = 30; order M, d, l)
           partial      = [J => [0 16 16; 16 2 14; 16 14 11], T => 5.0],         # V-PRE13
           cavity       = [V₀ => [-1.0, 40.0, 20.0], T => 5.0])                  # Fig 28; also needs nucleation (Open choices)
# Engulfment start: the upper half light, the lower half dark (V-PRE11)
halves(seed) = layout(Relabel(Voronoi(RandomPoints(1000; region = ball, seed); region = ball, lloyd = 30, kinds = [:dark]),
                              c -> centroid(c)[2] > 124 ? :light : :dark), gg)   # [NEW] layout relabel by cell predicate

# PRE §II D3 recipe (variant of the D-063 start): square aggregate of staggered bricks of various widths
bricks = layout(BrickWall((8, 5); widths = :varied, region = (24:223, 24:223), kinds = [:light]), gg)   # [R2] ≈1000 × 40 sites; height 5 / mean 40 from data/graner/generate.jl; width law UNSPECIFIED
relax  = solve(PottsProblem(gg, bricks, (0, 400PAPER_MCS); p = [J => [0 8 8; 8 2 2; 8 2 2], T => 5.0]), alg)  # 09c p.2135
typed  = [relax.u[end]..., kind => rand(StableRNG(1), [:dark, :light], ncells(relax.u[end]))]         # [?] Bernoulli(½), fraction UNSPECIFIED

# ── Variant OS: Chaste cellular Potts (09b + CBC) ───────────────────────────────────────
@potts_model ChasteSorting begin
    @structural_parameters begin
        lattice = (242, 242)      # 240² domain (CBC:200–202) + a 1-site frozen rim (Chaste counts edge edges in C)
    end
    @kinds void unlabelled labelled rim[frozen]         # A = unlabelled, B = labelled; A engulfs B (S3)
    @parameters begin
        α = 0.1;  A⁰ = 16.0                             # Table 1 p.10; CBC:232–233
        β = 0.01; C⁰ = 16.0                             # Table 1 p.10; CBC:237–238
        T = 0.2                                         # Table 2 p.11; CBC:219
        k_pert = 1.0                                    # Table 2 p.11; Fig 3: 10^-2 … 10^2
        t_label = 1000                                  # 10 h × 100 MCS/h (CBC:81, 226–228; S6)
        p_label = 0.5                                   # Bernoulli per cell (CBC:100, 254; S5)
        γ[kind, kind] = [0 0.2 1.0 0; 0.2 0.1 0.5 0; 1.0 0.5 0.1 0; 0 0 0 0]   # (void, A, B, rim) Tables 1–2; CBC:242–246
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = VonNeumann(1))   # VN contacts, VN perimeter (Chaste, 09 §2.2)
    @relations proposal = Moore(1)                      # 09b p.5; Chaste PottsBasedCellPopulation.cpp:285
    @energy begin
        cells(unlabelled, labelled) => α * (volume - A⁰)^2 + β * (surface - C⁰)^2   # 09b Eq 4
        contacts => γ[kind, kind′]                      # 09b Eq 4; rim pairs carry 0 (Chaste lattice edge)
    end
    @transition cells(unlabelled) => labelled  when = (mcs == t_label) & (rand() < p_label)   # [R3] CBC:94–104, 252–257
    @observed L ~ count(((kind == unlabelled) & (kind′ == labelled)) |
                        ((kind == labelled) & (kind′ == unlabelled)) for _ in contacts)   # [NEW] V-OS1 heterotypic VN edges
    @sweep Metropolis(; temperature = T * ifelse(mcs < t_label, 1.0, k_pert))    # [R1] `mcs` in copy scope; 09b Eq 3
end

@named os = ChasteSorting()
op_os = layout(overlay(Frame(:rim), Tiling((4, 4); region = (82:161, 82:161), kinds = [:unlabelled])), os)  # 20×20 cells, centred (PottsMeshGenerator.cpp:67–76)
prob_os = PottsProblem(os, op_os, (0, 11_000); seed = 1)       # 10 h + 100 h; t[h] = (MCS − 1000)/100 (09 §5.2)
kgrid = 10.0 .^ (-2:0.5:2)                                      # Fig 3 legend
ens_os = solve(EnsembleProblem(prob_os; prob_func = (q, ctx) -> remake(q; p = [k_pert => kgrid[cld(ctx.sim_id, 10)]])),
               alg, EnsembleThreads(); trajectories = 10length(kgrid), saveat = 1000:100:11_000)   # 10 runs per k (09b p.10)
Lnorm(sol) = sol[L] ./ sol[L][1]                                # L(t)/L(0), L(0) at the labelling instant (A-OS3)
```

About 105 lines of code. The GG model body is 30 lines. The rest is set-up, the paper's
protocol and the OS variant.

## Line → source

| Line | Spec | Paper / code |
|---|---|---|
| `contacts => J[kind, kind′]` (GG) | 09 §2.1, §8.2 | 09a Eq 2 p.2014; 09c Eq 2 p.2129; like bonds 0 (09c p.2129) |
| `J = [0 16 16; 16 2 11; 16 11 14]` | 09 §3.1, §8.3 | 09a p.2015; 09c p.2139 |
| `cells(dark, light) => λ(volume − V₀[kind])²` | 09 §2.1, §8.2 (A-GG1 resolved) | 09c Eq 2, θ(A_τ) with A_M < 0 (p.2130); A = 40 (p.2129–2130); Fig 28 A_l = 20 (p.2151) |
| `λ = 1`, `T = 10` | 09 §3.1, §8.2 | 09a p.2014; 09c p.2139 |
| `neighborhood = Moore(1)`, `proposal = Moore(1)` | 09 §8.2, §8.4 A-GG2 | 09c p.2129, 2130, 2132 |
| `Metropolis`, tie ½ at T = 0 | 09 §8.2 | 09c Eq 3 p.2130; `lib/CorePotts/src/algorithms.jl` (spec §8.6 M6) |
| `PAPER_MCS = 16` | 09 §8.5 | 09c p.2130; 09a p.2014 |
| `N_xy`, `N_mm` observables | 09 §9.0 "Fractions" | 09c §II D1 p.2133 |
| `annealed` (2 paper MCS, T = 0, own J) | 09 §8.4 A-GG4, §9.0; D-059 | 09c §II D2 p.2134 |
| `Δa` | 09 §9.1 V-GG6 | 09a p.2014 |
| `Voronoi(RandomPoints(1000; region = ball, …); lloyd = 30)`, 247² | 09 §9.0 FULL; D-063, D-138 | 09c p.2129 ("≈ 1000 cells") |
| `regimes` | 09 §8.3 | 09c §III A, D, E, F3 (p.2135–2151) |
| `halves` | 09 §9.1 V-PRE11 | 09c §III C, Fig 18 p.2145 |
| `bricks` / `relax` / `typed` | 09 §8.2 IC, §8.4 A-GG5 | 09c §II D3 p.2134–2135, Fig 4(a) |
| `cells(unlabelled, labelled) => α(A − A⁰)² + β(C − C⁰)²` | 09 §2.2, §3.2 | 09b Eq 4 p.6; Table 1 p.10 |
| `neighborhood = VonNeumann(1)` | 09 §2.2 (A-OS4 resolved) | Chaste AdhesionPottsUpdateRule.cpp:80; PottsMesh.cpp:198–230 |
| `rim[frozen]` + zero rim row/column in `γ` | 09 §2.2 table (perimeter counts lattice-edge edges; the edge carries no contact energy) | PottsMesh.cpp:211 (`local_edges = 2*DIM`); AdhesionPottsUpdateRule.cpp:80–84 |
| `γ` values | 09 §3.2 | Table 1 p.10, Table 2 p.11; CBC:242–246 |
| `proposal = Moore(1)` (OS) | 09 §2.2 | 09b p.5; PottsBasedCellPopulation.cpp:241–336 |
| `@transition … mcs == t_label & rand() < p_label` | 09 §2.2 protocol 1–3; S5, S6 | CBC:94–104, 219, 252–254 |
| `temperature = T · (k_pert after labelling)` | 09 §2.2 protocol 4 | CBC:257; 09b Table 2 |
| `Tiling((4, 4); region = 82:161)` | 09 §3.2 | CBC:200–203; PottsMeshGenerator.cpp:67–76 |
| `L`, `Lnorm` | 09 §9.1 V-OS1 | 09b p.11; HeterotypicBoundaryLengthWriter.cpp:276–330 |
| `tspan = 11_000`, `saveat = 1000:100:11_000` | 09 §5.2 time mapping | 09b Table 1 (Δt = 0.01 h), Table 2 (100 h); CBC:77, 227 |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds`, `x[frozen]`, `@parameters` scalar and `J[kind, kind]`, `V₀[kind]` in a cell energy | exists (`test/symbolic.jl:709`) |
| `Lattice(…; boundary, neighborhood)`, `Moore`, `VonNeumann`, `@relations proposal` | exists (D-049 F-1) |
| `contacts => J[kind, kind′]`, `cells(k…) => f(volume, surface)` | exists |
| `Metropolis(; temperature)`, tie ½ at T ≤ 0 | exists |
| `@observed x ~ mean(volume for c in cells(k))` | exists (`test/symbolic.jl:616`) |
| `count(… for _ in contacts)`: a population fold over contact pairs, in `@observed` | **NEW**, not on the roadmap (R16 is "analysis in docs"; R11a is cell-level) |
| `layout`, `overlay`, `Tiling`, `Frame` | exists (P6.1a, D-057) |
| `Voronoi`, `RandomPoints`, `Circle`/`Point` | exist in core (P6.1a5, D-138; `VoronoiBall` removed, no alias) |
| `BrickWall` | planned (R2, ROADMAP P6.4d) |
| `Relabel(layer, cell -> kind)` layout combinator | **NEW** |
| `EnsembleProblem` with `prob_func`, `remake(q; p, tspan)` | exists (tutorial `reproductions/09_cell_sorting.jl`) |
| `remake(q; u0 = <saved state>)` | untested `[?]`. The tutorial rebuilds `[ownership => …, kind => …]` by hand |
| Annealed-copy measurement as a named helper | planned (R16, P6.1b) |
| `@transition cells(a) => b when = …` with `rand()` and `mcs` | planned (R3, P6.4c) |
| `mcs` in the temperature (copy scope) | planned (R1, P6.4a). A model variable set `@before_mcs` works today |
| Cluster counts and components for V-PRE5/14/15 and V-OS5 | planned (R11a `neighbors(c)` + R16 graph components) |

## Friction found

1. **No way to count bonds by kind pair inside the model.** Every GG and OS target is a
   bond count by kind pair (N_dl/N_mm, F_dM, L). `contacts` exists only as an *energy*
   domain. Today the counting is hand-written host code (`bond_counts` in the tutorial,
   `bonds` in `papers.jl`). Two indirect encodings are possible:
   - a site population fold over a Moore gather,
     `sum(count(kind[n] == light for n in Moore(1)(site)) for s in sites if kind == dark)`;
   - a cell fold of `integral(gather)`.

   Neither nesting is tested. Both double-count homotypic pairs and see medium only from
   the cell side. The natural primitive is a **contact-pair population fold**,
   `count(expr for _ in contacts(rel))`, with `kind`, `kind′`, `x`, `x′` in scope (the
   contact-term env, D-061). This fold is on no roadmap row. It is small (one host pass),
   covers foam φ, Zajac interface lengths and every "fraction of boundary" metric, and
   should be added to R16 or R11a.
2. **The annealed-copy measurement does not compose with SII.** The pattern is: take the
   state saved at t, run 32 MCS at T = 0 under the run's own parameters, then evaluate an
   observed quantity. That needs `remake(q; u0 = sol.u[i])` accepting a saved state
   (untested), and a way to evaluate `@observed` on the result.
   - A declarative form such as `sol[expr; on = Annealed(32)]` or
     `measure(sol, obs; transform = anneal)` is R16 territory. Its syntax is not
     proposed anywhere.
   - D-059's "own Hamiltonian" rule falls out for free if the transform `remake`s the
     run's own problem.
3. **A timed kind change needs R3, and the workaround does not scale.** Without
   `@transition`, OS labelling can be done in two ways:
   - (a) two solves, with host code that rebuilds `u0` with new kinds;
   - (b) a cell variable `label(cell)` read in contacts as `label[owner]`/`label[owner′]`.
     Reading cell state in contacts makes the term non-local, so the cells join the claim
     set. Also, `γ` is indexed by kind only, so the variable-indexed table needs `ifelse`
     chains (or R13 integer-indexed tables).

   (a) works today but is imperative. R3 is the right fix. Also, a `when = mcs == t` rule
   is really a *one-shot discrete event*. `@discrete_events` (R3) reads better than a
   per-MCS rule that is false 10,999 times.
4. **Chaste perimeter semantics need a trick.** Chaste's perimeter counts lattice-edge edges
   (`local_edges = 2*DIM`), but the edge carries no contact energy. Our `surface` under
   `Closed()` skips out-of-lattice pairs. The sketch uses a frozen `rim` kind with a zero
   `γ` row, which grows the kind table and the lattice (242²). It only matters once cells
   reach the edge (k_pert ≥ 10^1.5). A boundary option such as
   `Closed(; counts_in_surface = true)` would be cleaner, but it is **NEW** and probably not
   worth it. At the edge, the Moore draw of a rim neighbour wastes the attempt, whereas
   Chaste renormalises. The spec accepts this (09 §5.2).
5. **Layout gaps.** The Voronoi start is core since P6.1a5 (D-138). There is no layout
   combinator for "relabel cells by a predicate on the cell" (the engulfment start needs
   it). The PRE brick recipe needs `BrickWall` with *varied widths*, a parameter R2's
   proposed `BrickWall` does not mention. The random typing after relaxation is host code
   (`rand` over `ncells`), because no layout layer re-kinds an existing operating point.
6. **The cavity run (Fig 28) is not expressible.** It needs a proposal that nucleates medium
   at non-neighbour sites (09c p.2130, "nucleation constraint removed"). R10's laws
   (`UniformNeighbor`, `UnlikeNeighbor`, `BoundarySite`) do not cover it, and its rate is
   unstated. It is **NEW**, and it may be better left undone (one figure, 200 MCS).
7. **Topology targets stay parked for a primitive reason.** `neighbors(c)` (R11a) is
   defined as "face-sharing under the contact relation". Bulk ⟨n⟩ needs a neighbour rule
   that is independent of the contact relation, which is the V-PRE6 parking reason. R11a
   should take `neighbors(c; relation = …)` explicitly (the same issue appears in foam).
8. **Temperature staging.** `temperature = T * ifelse(mcs < t_label, 1, k_pert)` needs
   `mcs` in copy scope (R1). The workaround, a model variable set `@before_mcs`, is fine.
   Nothing else in OS needs R1.

## Open choices

| Choice | Default (spec) | Variants |
|---|---|---|
| Start (GG) | `Voronoi` disk of 1000 cells, unrelaxed (`graner_glazier_aggregate`; D-063, D-138; 09 §9.0 FULL) | PRE §II D3 brick recipe, relaxed 400 paper MCS (`bricks`/`relax`); SMOKE `graner_glazier_state()` 64 cells on 72² |
| Light:dark fraction | exactly 500/500 (±1), reported (09 §9.3 item 5) | Bernoulli(½); UNSPECIFIED in the paper (09 §8.4 A-GG5) |
| Lattice and BC (GG) | 247² periodic, 10-site margin | Closed with margin ≥ 60 for dispersal (V-PRE14/15); both UNSPECIFIED (09 §8.4) |
| Annealing | on a copy, 2 paper MCS, T = 0, own J (S2, D-059) | on the trajectory (S2 variant); 10 MCS for the §II D3 statistics (09c p.2135) |
| Per-type target area | A_d = A_l = 40 | Fig 28 A_l = 20, which also needs a nucleation proposal (NEW, rate UNSPECIFIED) |
| OS engulfment direction | A engulfs B, B = labelled (S3) | — (p.11 wording treated as an error) |
| OS labels | Bernoulli(0.5) per cell (S5) | exactly 200/200 |
| OS equilibration | 10 h unlabelled; t = 0 at labelling (S6) | none |
| OS contacts/perimeter | VN, following the code (S4, verified identical in the paper tag) | — |
| OS edge perimeter | frozen rim counts edge edges (Chaste) | plain `Closed()` (edge edges uncounted; differs only after dissociation) |
| OS temperature | T = 0.2 (Table 2) | T = 0.1 (Table 1 cross-study default) |
| OS fluctuation metric (V-OS3) | PARKED; smoother UNSPECIFIED (09 §7 A-OS6) | — |
