# 14 — Fortuna et al. 2020 compartmentalised crawling cell (3D): target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** one 3D cell made of three compartments (cytoplasm, nucleus, lamellipodium),
  crawling on a flat substrate. It is driven by an F-actin field that the lamellipodium
  makes where it touches the substrate. The last part of the sketch is the Dal-Castel
  chemotaxis variant (14c), written as an `@extend`.
- **Papers:** 14a Fortuna et al., *Biophys. J.* **118** (2020) 2801–2815 (base); 14b
  Thomas et al., *Physica A* **587** (2022) 126511 (observables); 14c Dal-Castel et al.,
  *Physica A* (2025), arXiv v1 (chemotaxis). The released code is used for 14a
  (`SF1_Code.zip`) and for 14c (`Single_Cell_Chemotaxis_2.3` @ c1353d3).
- **Spec:** [`../14_nucleus_migration.md`](../14_nucleus_migration.md), including §2.9
  (the Fortuna code). Decisions C1–C7 are in README §4.11, and C7 was changed by D-067.
  Liveness follows D-066 items 1 and 7. Build step: ROADMAP step 5 (P6.5a–d); 14c is P6.7b.
- **Date:** 2026-09-30.

Tags: `# [R#]` marks a planned roadmap feature and `# [NEW]` marks a feature that is not on
the roadmap. An untagged line uses syntax that exists today (`src/vocabulary.jl`,
`src/macro.jl`, AUTHORING "implemented"). `[verify]` marks existing syntax that I believe
works in that position but have not run.

Defaults follow the heuristic in README §4: use the code that produced the figures. So
J_CL = 10 (C1), the target-based conversion (C2), the PDE (C3 for 14a), the code's initial
state (C5) and protrusion in both directions (C7). Kind indices: medium 0, substrate 1,
lid 2, cytoplasm 3, lamellipodium 4, nucleus 5.

## 1. Sketch

```julia
using Potts

@potts_model FortunaCrawling begin
    @structural_parameters begin
        lattice = (120, 120, 31)       # R = 15: int(8R)² × int(2.1R) (14 §2.9.1; 10R if R ≥ 20 and φ_F ≥ 0.2)
        retraction = true              # C7 (D-067): Medium → lamellipodium copies also pay the term; false = Eq 7
        stop_on_detachment = true      # code: stop when CYTO–FRONT contact is 0 at a 50-MCS sample (14 §2.9.1)
    end
    @kinds medium substrate[frozen] lid[frozen] cytoplasm lamellipodium nucleus   # 14 §2.9.1 types
    @parameters begin
        T = 100.0                      # T_B (14 §5.1, Table 1; code CellMig3D.py:80)
        λ = 10.0                       # λ_c = λ_l = λ_n (14 §5.1; code Steppables.py:110, 115, 156)
        φ_F = 0.05                     # lamellipodium fraction (14 §5.1; code CellMig3D.py:45)
        λ_F = 150.0                    # protrusion, 14a sign = −λ_CC3D (14 §2.9.4; code CellMig3D.py:48)
        D_F = 1.0e-4                   # F-actin diffusion (14 §5.1, Table 1)
        k_decay = 0.9                  # (14 §5.1, Table 1)
        k_source = 0.9                 # on lamellipodium in contact with the substrate (14 §2.9.2)
        # Contact table: pairs of different clusters (CC3D Contact, 14 §2.9.3). Order M S lid C L N
        J[kind, kind] = [1 20 -20 20 40/3 100; 20 1 1 20 20/3 100; -20 1 1 20 40/3 100;
                         20 20 20 40 40 100; 40/3 20/3 40/3 40 40 100; 100 100 100 100 100 100]
        # Pairs within one cluster (CC3D ContactInternal, 14 §2.9.3). J_CL = 10 (C1; Table 1 gives 20)
        Jint[kind, kind] = [0 0 0 0 0 0; 0 0 0 0 0 0; 0 0 0 0 0 0;
                            0 0 0 0 10 20; 0 0 0 10 0 40; 0 0 0 20 40 0]
    end
    @variables begin
        F(field) = 0.0                 # F-actin, on the whole lattice, unconfined (14 §2.9.2)
        V_target(cell) = 0.0           # moves between compartments on conversion (14 §2.9.5)
        front_births(model) = 0.0      # D-066 diagnostic: FRONT deaths = births − alive
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Periodic(), Closed()),   # 14 §2.7; z = CC3D default
                     neighborhood = NeighborOrder(4))                           # 32-neighbour contacts (14 §2.2)
    @relations proposal = VonNeumann(1)                                         # NeighborOrder 1 (14 §2.6)

    touches_substrate(s) = any(kind[n] == substrate for n in VonNeumann(1)(s))  # SecretionOnContact test (14 §2.9.2)

    @energy begin
        cells(cytoplasm, lamellipodium, nucleus) => λ * (volume - V_target)^2               # Eq 5
        contacts => ifelse(cluster[owner] == cluster[owner′], Jint[kind, kind′], J[kind, kind′])  # Eq 4 (§9 item 4)
    end
    # Eq 7 work term, CC3D "merks" chemotaxis: ΔE = λ_F (F(target) − F(source)) (14 §2.9.4)
    extension  = (kind[new] == lamellipodium) & (old == 0)
    retracting = (kind[old] == lamellipodium) & (new == 0)
    @drive copy => ifelse(retraction ? extension | retracting : extension,
                          λ_F * (F[target] - F[source]), 0.0)
    # Eq 6: one explicit step per MCS equals CC3D's diffuse + decay, then secrete (14 §2.9.2)
    @equations D(F) ~ D_F * Δ(F) - k_decay * F +
                      k_source * (kind == lamellipodium) * touches_substrate(site)          # [R5] [verify]

    # Conversion: cytoplasm at the substrate → lamellipodium, after the PDE (14 §2.9.5, §2.9.6; C2)
    @convert protrusion clusters(cytoplasm) begin                                          # [R8] [NEW name]
        from  = sibling(cytoplasm); to = sibling(lamellipodium)   # `to` is made on demand (D-066)  # [R6]
        at    = touches_substrate(site)                           # every CYTO site at z = 1
        order = Shuffled()                                        # sequential, shuffled   # [NEW]
        p     = 0.1 * (1 - V_target[to] / (φ_F * sum(V_target[m] for m in members(cluster))))  # [R6]
        V_target[to]   += ifelse(created, 1.5, 1.0)               # FRONT starts at 1.5     # [NEW created]
        V_target[from] -= ifelse(created, 1.5, 1.0)               # total target conserved
        front_births   += created
    end
    if stop_on_detachment
        @terminate Every(50) when = (mcs > 10) &&                                          # [R3]
            any(contact(c, sibling(c, lamellipodium)) == 0 for c in cells(cytoplasm))       # [R11a] [R6]
    end

    @observed begin
        front_deaths ~ front_births - count(true for c in cells(lamellipodium))
        # 14b Eq 10, selected Π_CN−N = r_CN − r_N = V_C (r_C − r_N)/(V_C + V_N), xy only
        Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) /  # [NEW] [R6]
                   (volume + volume[sibling(nucleus)])
        Πy(cell) ~ volume * minimum_image(centroid(2) - centroid(sibling(nucleus), 2), 2) /
                   (volume + volume[sibling(nucleus)])
    end
    @sweep Metropolis(; temperature = T, field_solver = ExplicitEuler(substeps = 1))
    # order per MCS: sweep → F → @convert (14 §2.9.6), to be pinned by the R5 phase order  # [R5]
end

# --- 14a-code initial state: ball tangent to the substrate, 6³ nucleus, no FRONT (C5, 14 §2.9.1) ---
@named cell = FortunaCrawling()
R = 15; L, Lz = 120, 31; V = 4.19R^3                                  # code volume (14 §2.9.7 item 3)
c = (L ÷ 2 + 1, L ÷ 2 + 1, R + 1)                                    # CC3D (L/2, L/2, int R), 1-based
op = layout(overlay(Spheres([c]; radius = R, kinds = [:cytoplasm]),  # |r − c| < R          # [R2]
                    Tiling((6, 6, 6); region = map(a -> (a - 3):(a + 2), c), kinds = [:nucleus]),
                    Plane(:substrate; axis = 3, at = 1),             # overwrites the ball's z = 0 point  # [R2]
                    Plane(:lid; axis = 3, at = Lz)), cell)                                    # [R2]
op = [op; cluster => [1, 1, 3, 4],                                   # ids follow layer order  # [NEW helper wanted]
      :V_target => [floor(0.85V) + 0.5, floor(0.15V) + 0.5, 0, 0]]   # 12020.5, 2121.5 at R = 15
prob = PottsProblem(mtkcompile(cell), op, (0, 100_001); seed = 1)    # tSim = 100001 (14 §2.9.1)
sol  = solve(prob, SequentialCPM(); saveat = 0:50:100_001)           # deltaT = 50 (code output cadence)
ens  = EnsembleProblem(prob; trajectories = 5)                       # Fig 5 replicas; MSD/Fürth fits: R16 docs

# --- 14c Dal-Castel chemotaxis (14 §4.2, 14c-code): binary F, tanh bias, 100-MCS gate --------------
@potts_model DalCastelChemotaxis begin
    @extend T, λ, λ_F, φ_F, V_target, touches_substrate =                              # [NEW fn binding]
        base = FortunaCrawling(; lattice = (59, 59, 21), λ_F = 175.0)                  # SC:22, 32–33
    @parameters begin ρ = 0.5; μ = 0.0; χ = 1.0; δ = 0.0 end                            # SC:45–51 (C6)
    @variables begin
        F(site) = 0.0                  # replaces the base's field + PDE (C3)            # [NEW replace equation]
        φ_frac(cell) = 0.0; φ_sum(cell) = 0.0; φ_EST(cell) = 0.0
        Q̄(cell) = 0.0; σQ(cell) = 1.0  # base statistics (14 §4.2 "Base statistics")
    end
    base_site = touches_substrate(site) & (kind != nucleus)             # base = cell sites at z = 1 (14c-SM p.4)
    Q = minimum_image(position[1] - centroid(sibling(owner, cytoplasm), 1), 1)   # x rel. Cyto COM  # [NEW] [R6]
    @after_mcs begin                   # code order: F, then φ_EST, then conversions (SS:82–172)
        F ~ (kind == lamellipodium) * touches_substrate(site)                           # SS:88–95
        φ_frac ~ volume[sibling(lamellipodium)] /
                 (V_target + volume[sibling(lamellipodium)] + volume[sibling(nucleus)])  # SS:107 (CELLvol)
        φ_sum ~ Pre(φ_sum) + φ_frac - Pre(φ_frac, 100)                                   # [R12]
        φ_EST ~ ifelse(mcs < 100, φ_F, φ_sum / 100)                                      # SS:41, 110–114
        Q̄  ~ cluster_integral(Q * base_site) / cluster_integral(base_site)               # [NEW]
        σQ ~ sqrt(cluster_integral(Q^2 * base_site) / cluster_integral(base_site) - Q̄^2)
    end
    @convert protrusion clusters(cytoplasm) begin     # replaces the base rule by name     # [R8] [NEW]
        from  = sibling(cytoplasm); to = sibling(lamellipodium); order = Shuffled()
        at    = touches_substrate(site)
        p     = ρ * (χ * tanh(μ * (Q - Q̄[from]) / σQ[from]) + 1)                         # Eq 7; SS:156–159
        gate  = volume[to] / (V_target[from] + volume[to] + volume[sibling(nucleus)]) - δ <= φ_EST[from]  # SS:162–172
    end
    @terminate when = count(true for c in cells(lamellipodium)) == 0                     # D-066 item 7 # [R3]
end
```

Proposed syntax used above:
- **`@convert name clusters(k) begin … end`** (R8). A host pass once per MCS over every
  cluster whose root is of kind `k`. It takes `from`/`to` references, the `at` candidate
  sites (site scope), an `order`, a probability `p`, an optional `gate`, and state updates
  that run once per conversion. `p` and `gate` are evaluated **again before each candidate**,
  on the running trackers. `created` is true when this conversion made `to`.
- **`sibling(k)`, `sibling(c, k)`, `members(cluster)`** (R6). A missing sibling reads as
  ref 0, whose variables read as their defaults (D-066 item 5).
- **`centroid(c, k)`** [NEW]. Coordinate `k` of cell `c`'s centroid, as the cell-first
  counterpart of `displacement(c, k)`.
- **`minimum_image(d, axis)`** [NEW]. A wrapped coordinate difference on periodic axes.
- **`cluster_integral(x)`** [NEW]. `integral` summed over the members of a cluster.
- **`Shuffled()`** [NEW]. A visiting order for sequential host passes, drawn from the
  addressed RNG.

## 2. Line → source

| Sketch line | Spec | Paper / code |
|---|---|---|
| `lattice = (120, 120, 31)`, periodic x, y, closed z | 14 §2.7, §2.9.1 | 14a p.2806; CellMig3D.py:66–75, 99, 104–105 |
| kinds, `substrate[frozen]`, `lid[frozen]` | 14 §2.9.1 | CellMig3D.py:111–117; Steppables.py:80–83 |
| `T = 100` | 14 §5.1 | Table 1; CellMig3D.py:80 |
| `λ = 10` | 14 §5.1 | Table 1; Steppables.py:110, 115, 156 |
| `φ_F = 0.05` | 14 §5.1 | p.2806; CellMig3D.py:45 |
| `λ_F = 150` (sign) | 14 §2.9.4, §9 item 2 | Eq 7, p.2806; CellMig3D.py:48, 263; CC379 ChemotaxisPlugin.cpp:272–273 |
| `D_F`, `k_decay`, `k_source` | 14 §5.1, §2.9.2 | Table 1; CellMig3D.py:249–253 |
| `J` table | 14 §2.9.3, §5.1 | Table 1; CellMig3D.py:174–209 |
| `Jint` table, J_CL = 10 | 14 §2.9.3; C1 | Table 1 gives 20; CellMig3D.py:229–240 |
| `NeighborOrder(4)` | 14 §2.2, F7 | Eq 4, p.2805; CellMig3D.py:163, 219 |
| `proposal = VonNeumann(1)` | 14 §2.6, F8 | p.2805; CellMig3D.py:103 |
| `cells(…) => λ(volume − V_target)²` | 14 §2.2, §2.9.1 | Eq 5, p.2805 |
| `contacts => ifelse(cluster …, Jint, J)` | 14 §2.2, §9 item 4 | Eq 4; CellMig3D.py:162, 218 |
| `@drive … λ_F (F[target] − F[source])`, both directions | 14 §2.4, §2.9.4; C7 | Eq 7; CC379 ChemotaxisPlugin.cpp:434–455, 487–502 |
| `D(F) ~ …`, `ExplicitEuler(substeps = 1)` | 14 §2.3, §2.9.2 | Eq 6, p.2805; CC379 DiffusionSolverFE_CPU.cpp:835–841, 1204, 316–335 |
| `touches_substrate` (6 face neighbours) | 14 §2.9.2 | CC379 DiffusableVectorCommon.h:78 |
| `@convert protrusion` (p, targets, sequential) | 14 §2.9.5; C2 | p.2806; Steppables.py:121–165 |
| FRONT created on demand, dies when it empties | 14 §2.9.5; D-066 item 7 | Steppables.py:149–159 |
| `@terminate` on detachment | 14 §2.9.1 row "Detachment stop", §2.9.7 item 17 | Steppables.py:404–411 |
| `Πx`, `Πy` | 14 §3 (Eq 10), §2.8 | 14b Eq 10–11, p.6, p.11 |
| initial ball, 6³ nucleus, planes | 14 §2.9.1; C5 | Steppables.py:65–105 |
| `V_target` initial 12020.5 / 2121.5 | 14 §2.9.1 row "Volume constraint" | CellMig3D.py:45–47, 60; Steppables.py:109–115 |
| `(0, 100_001)`, `saveat = 50` | 14 §2.9.1 | CellMig3D.py:41, 84 |
| 14c: lattice 59×59×21, `λ_F = 175` | 14 §4.2, §5.2 | SC:22, 32–33 |
| 14c: `ρ, μ, χ, δ` | 14 §4.2, §5.2; C6 | Eq 7, 14c p.9; SC:45–51 |
| 14c: binary `F` | 14 §4.2; C3 | 14c p.6; SS:88–95 |
| 14c: `φ_EST` window | 14 §4.2; C6 | Eq 6, 14c p.8; SS:41, 110–114 |
| 14c: `gate` | 14 §4.2 | SS:107, 162–172 |
| 14c: `@terminate` on LAMEL death | 14 §4.2; D-066 item 7 | SS:104–105, 122 |

## 3. Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds … x[frozen]`, kind tables `J[kind, kind]`, scalar parameters, structural parameters, `if` sections | exists |
| 3D `Lattice` with per-axis boundaries, `NeighborOrder(4)`, `@relations proposal = VonNeumann(1)` | exists |
| `contacts => ifelse(cluster[owner] == cluster[owner′], …)` | exists (D-036, AUTHORING §12.7a) |
| `cells(…) =>` with a cell variable target | exists |
| `@drive` with `kind[new]`, `old`, `new`, `F[target]` | exists |
| field `D(F) ~ Δ … + kind predicate`, `ExplicitEuler(substeps = 1)` | exists (as in Merks) |
| relation gather `any(… for n in VonNeumann(1)(site))` in a field rate | exists as syntax [verify]: the field rate is lowered in a site environment with gather names (`codegen.jl:382`), but ROADMAP P6.5c still lists a "predicate-sourced PDE" |
| `@after_mcs` updates of site and cell variables, `Pre(x)`, `mcs` | exists |
| `@observed`, `count(true for c in cells(k))` | exists |
| `Tiling`, `overlay`, `layout`, `cluster =>` in the operating point, `PottsProblem`, `SequentialCPM`, `EnsembleProblem` | exists |
| `@convert` (R8, P6.5b); FRONT created on demand; ownership hooks | planned (R8, step 5) |
| `sibling`, `members`, reading `x[ref]` (R6, P6.5a) | planned (R6, step 5) |
| `Spheres`, `Plane` (R2, P6.5c) | planned (R2, step 5) |
| explicit phase order (R5, P6.3b) | planned (R5, step 3) |
| `@terminate` (R3, P6.4c) | planned (R3, step 4) |
| `contact(c, n)` (R11a) | planned (R11a; AUTHORING §12.3) |
| `Pre(x, 100)` on a cell variable (R12, P6.7b) | planned (R12) |
| MSD, modified-Fürth fits, ψ_δ (R16, P6.5c) | planned (R16, docs) |
| named rules that an `@extend` can replace (`@convert protrusion`) | **NEW** |
| `created` flag and `order = Shuffled()` in a host pass | **NEW** |
| `centroid(c, k)` (cell-first) | **NEW** |
| `minimum_image(d, axis)` | **NEW** (AUTHORING §12.2 mentions "a wrapped difference" but gives no primitive) |
| `cluster_integral(x)` | **NEW** (R15 lists "rim reductions", not cluster reductions) |
| replacing a base equation by an update in an `@extend` (`F(field)` → `F(site)`) | **NEW** |
| `@extend` binding a model-body helper function (`touches_substrate`) | **NEW** |
| layout helper to set `cluster` | **NEW** |

## 4. Friction found

1. **`Chemotaxis` cannot express C7 (the default).** The library gate is
   `gain = new != 0` (`vocabulary.jl`, `Chemotaxis`). That kills the retraction branch,
   where Medium (new = 0) overwrites the lamellipodium. So the paper's own default is a raw
   `@drive`, and the library helper covers only the extension-only variant.

   The review §2 lists the "Morpheus retraction switch" as covered by the R0 family, but
   the implemented gate prevents it. Fix options:
   - `Chemotaxis(c; kinds, towards = (0,), mode = :extension | :both)`, which covers the
     CC3D merks rule `ChemotactTowards`;
   - or drop the implicit gain gate and put it in `when`.

   Merks 2008 M7 (`:extension_retraction`) needs the same fix.
2. **`@convert` needs a precise sequential contract.** R8's "too-narrow shapes" list names
   `from`/`to`, a predicate, a probability and a budget. Fortuna also needs these:
   - **Recompute per candidate.** `p` and `gate` are evaluated again before each
     candidate, on the running trackers (volume) and the running cell variables
     (`V_target`). 14a's p depends on V_target and 14c's gate on `volume[to]`, and both
     change within the pass.
   - **Per-conversion writes to two cells and a model variable.** For example
     `V_target[to] += …`, `V_target[from] -= …`, `front_births += created`.
   - **`created`.** 14a's first conversion adds 1.5 and later ones add 1. The birth
     serial exists (D-066), but no rule scope exposes "this event allocated `to`".
   - **A visiting order.** The code shuffles the candidates. This cannot be a batched
     device phase; it is a serial host loop. That is fine: it runs off the hot path
     (README R8).

   The rule mixes scopes. It is a cluster-scope rule with site-scope `at` and `p`
   (14c's p reads `Q` at the site). The lowering environment must bind the site names
   (`site`, `position`, `kind`) together with `from`, `to` and `cluster`.
3. **Replacing rules and equations under `@extend`.** Division rules accumulate under
   `@extend`, and so, presumably, would `@convert` rules. 14c must *replace* the base's
   conversion and must replace the base's `D(F) ~ …` PDE with an `@after_mcs` update
   of a site variable. AUTHORING §6 lets an extension replace an update by an update, and
   an equation by an equation of the same name. It says nothing about replacing across
   kinds, or about rules.

   Proposal: named rules (`@convert protrusion …`), where redeclaring the name replaces
   the rule. This is consistent with "structural replacement is explicit: redeclare the
   target". Also let a redeclared variable drop its base equation. The only alternative
   today is a structural switch in the base (`actin = :pde | :indicator`), which puts
   14c's mechanics inside the 14a model.
4. **Reading another cell's centroid collides with `centroid(k)`.** `centroid(k)` is
   axis-first and has no cell argument, while `displacement(c, k)` is cell-first. Π, the
   14c `Q` and any sibling-COM observable need "centroid of `ref`". Neither
   `centroid(1)[ref]` (indexing a call) nor R6's `x[ref]` (variables only) covers it.
   Proposal: `centroid(c, k)`, which mirrors `displacement`. The one-argument form stays
   the current cell's.
5. **Periodic unwrapping has no primitive.** Π_CN−N, 14c's `Q` ("unwrapped relative to
   the Cyto COM", SS:137–145), and MSD all need a minimum-image difference, and MSD needs
   unwrapped trajectories. AUTHORING §12.2 says "use a wrapped difference" but provides
   none. R7 promises unwrapped centroids for 13, which covers MSD only.
   `minimum_image(d, axis)` is tiny and general.
6. **Cluster-level site reductions.** 14c's base statistics (⟨Q⟩ and σ_Q over the cyto
   and lamellipodium sites at z = 1) span two cells. `integral` is per cell. Two ways to
   write it:
   - `sum(integral(x)[m] for m in members(cluster))`, which needs `integral` at a
     reference (neither R6 nor §12.3 has it);
   - a `cluster_integral(x)` next to `cluster_volume` (NEW).

   The same applies to CELLvol-style sums, which I wrote here as `members` folds.
7. **A site-scope expression that reads the owner's sibling.** `Q` is a site expression
   that reads the cluster's cytoplasm centroid (`sibling(owner, cytoplasm)`). R6
   describes references from a cell. A reference taken from a site owner (site → cell →
   sibling) is a second hop that should be stated explicitly. It is cheap here: the
   reduction runs at the boundary, not in the sweep.
8. **`@terminate` on detachment uses a reference that can read 0.** Once FRONT is dead,
   `sibling(c, lamellipodium)` reads 0 (medium, D-066 item 5). So `contact(c, 0)` is the
   cell–medium contact, which is > 0, and the stop silently never fires. It needs an
   `alive(sibling(…))` guard. The code's behaviour with no FRONT at a sample is unknown
   (not in spec). `sibling` also needs a cell-explicit form inside population folds:
   `sibling(c, k)` versus the cell-scope `sibling(k)`.
9. **Phase order.** In the code, one MCS is sweep → PDE → conversion → analysis
   (14 §2.9.6). Today fields run in the after phase (`codegen.jl:380–390`). Where the
   R8 routine will run relative to the fields and the after-MCS updates is undefined. In
   14c, the conversion must also follow the `F`, `φ_EST` and `Q̄` updates. I left the
   order as a comment. R5 must pin it. Proposal: a named `order` in `@sweep` that refers
   to rule names.
10. **No friction: the F-actin step.** A single explicit Euler step (dt = 1 MCS) gives
    c + DΔc − k c + k_s·src. That is exactly CC3D's "diffuse + decay, then secrete"
    (14 §2.9.2), so F → 1 at sources with no special operator. This holds only if
    `substeps = 1` is honoured. The automatic substep choice must not override it: it
    looks only at the Δ coefficient.
11. **The checkerboard is exact here, which the matrix does not reflect.** Every energy
    and drive reads only the copy's owners, `cluster[·]` (which a copy never changes) and
    site values. Cluster trackers and references appear only in boundary rules and
    observables. So 14a needs **no** R6 claim widening in the sweep, and README §4.12's
    "sequential reference for 14" is conservative. The real cost is NeighborOrder(4) in
    3D: a radius-2 footprint needs many checkerboard colours.
12. **Initial layout.** Layouts cannot assign `cluster`. Today the user writes
    `cluster => [1, 1, 3, 4]` by hand, from the rule that ids follow layer order, which is
    fragile. A combinator such as `Group(Spheres(…), Tiling(…))` that emits `cluster` is
    wanted (NEW). 14c also needs a hemisphere and an annulus ("ring") layer (R2 lists
    neither).
13. **`@extend` cannot bind a helper function.** 14c reuses `touches_substrate`.
    Body-local Julia functions (like WortelAct's `act_mean`) are not part of a system, so
    `@extend` cannot bind them. The extension must repeat the definition, or the helper
    must live outside the model.
14. **The window mean costs a lag ring of 100.** `Pre(φ_frac, 100)` (R12) keeps a
    100-deep ring per cell for one running mean. A `window_mean(x, n)` primitive, or the
    running-sum idiom above, is enough. The running-sum idiom is expressible once R12
    exists. The review merged the spec's G15 into R12; that holds, at a memory cost.

## 5. Open choices

| Choice | Default (spec) | Variant(s) |
|---|---|---|
| J_cyto–lamellipodium | 10, both codes (C1) | 20, Table 1 (`Jint[3,4] = Jint[4,3] = 20`) |
| Conversion law | code: 0.1·(1 − V₃ᵗ/(φ_F ΣVᵗ)) on targets, sequential, stops once reached (C2) | paper literal: p ∝ (1 − V₃/V₃ᵗ) with V₃ᵗ = φ_l V fixed; constant UNSPECIFIED (14 §2.5) |
| Protrusion direction | both extension and retraction (C7, D-067) | Eq 7 extension only (`retraction = false`) |
| F-actin | PDE, source on FRONT touching SUBS_A (C3; 14 §2.9.2) | 14b Eq 9: source on all lamellipodium sites; 14c binary indicator |
| Initial state | ball tangent to substrate, 6³ cube nucleus, no FRONT (C5) | 14a-S1: centred sphere with spherical nucleus; 14a Fig 4A "suspended" cell |
| Cell volume | 4.19 R³, int + 0.5 (code) | (4π/3) R³ (paper) |
| Lattice | int(8R) (10R when R ≥ 20 and φ_F ≥ 0.2) | paper range [8R, 14R] |
| Top lid | frozen SUBS_NA at z = L_z − 1, J(M, lid) = −20 (code) | none (paper is silent) |
| Extra SUBS_NA secretion | off (14a-code) | on (14a-nH port addition, 14 §2.9.8) |
| Detachment stop | on (code) | off; classify detachment after the run |
| Conversion RNG | addressed per replicate (§9 item 18; performance over exactness) | fixed `seed(1000)` shared across replicates (code) |
| Polarization observable | Π_CN−N (14b choice) | lamellipodium–nucleus COM distance (14a Fig 12), `dcm_F_CN` (code; §9 item 19) |
| R, φ_F, λ_F | 15, 0.05, 150 (code defaults) | scans R ∈ {10, 15, 20}, φ ∈ {0.05, 0.1, 0.2, 0.3}, λ ∈ 75–250 (14a-S1 p.3; Table 2 adds 160–170) |
| 14c gate | δ = 0, "≤", window includes the current MCS (C6) | δ = 0.01 (README), strict "<" |
| 14c clustering | clustered (as 14a), same effective J | unclustered as in 14c-code (only the table in use differs, 14 §4.2) |
| 14c chemotaxis | µ = 0 (code default) | µ = 10⁶ (gradient runs, 14c p.15) |
