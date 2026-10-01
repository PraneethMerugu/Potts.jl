# 01 — Merks vasculogenesis and contact-inhibited chemotaxis: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Models:** two published parameterisations that share one mechanism core (autocrine
  chemotaxis of endothelial cells on a frozen frame, TST 0.1.3 semantics):
  - **`Merks2006`**, Variant E: area + length constraint, chemotaxis at every copy, soft
    connectivity penalty E₀, 8-neighbourhood;
  - **`Merks2008`**, Variant CI: area constraint, chemotaxis with χ(c,c) ≠ χ(c,M) (contact
    inhibition), extension/retraction mode, 20-neighbourhood, 100 MCS relaxation.
  Both `@extend` a base `MerksCore` that has **no defaults** for paper-specific values, so
  the two sets cannot mix (01 §8 A-17; D-050 M1). The existing `MerksVasculogenesis` is the
  early mixed version; this sketch is the faithful target (ROADMAP P6.3d).
- **Papers:** 01a Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006);
  01b Merks, Perryn, Shirinifard & Glazier, PLoS Comput. Biol. 4, e1000163 (2008), with
  Dataset S1 (parameter files) and Protocol S1 (TST 0.1.3 source).
- **Spec:** `../01_merks.md` (§2, §3, §7, §8). Decisions: README §4.1 M1–M11 (D-050).
- **Date:** 2026-09-30.

Tags: `# [R#]` = planned roadmap feature; `# [P6.x]` = a planned ROADMAP step-0 item;
`# [NEW]` = not on the roadmap; `# [?]` = the primitives exist but this combination is
untested. An untagged line uses only what exists at `monorepo` HEAD.

```julia
using Potts

# ── Shared core (01 §2, §7.2–§7.5): TST CPM + autocrine field. No paper defaults here. ─────
@potts_model MerksCore begin
    @structural_parameters begin
        lattice = (202, 202)            # TST 200² + the off-lattice ring TST counts as border (Friction 2)
        order = 4                       # NeighborOrder(order): 2 → 8 sites, 4 → 20 sites (01 §7.3)
        mode = :extension_retraction    # D-050 M7; :extension_only = 01b Eq 4
        Δx = 2.0e-6                     # m per site (01a p.49; 01b p.11)
        τ = 30.0                        # s per MCS (01a p.50; 01b p.11); 15 × Δt = 2 s
    end
    @kinds medium endothelial border[frozen]           # frozen frame B (01 §2.1, §7.5; D-050 M4)
    @parameters begin
        T                               # Metropolis temperature
        λ                               # area strength
        A                               # target area (sites)
        J[kind, kind]                   # medium, endothelial, border
        χcM                             # chemotaxis strength at cell–medium copies
        χcc                             # … at cell–cell copies (contact inhibition ⇔ χcc = 0)
        s = 0.0                         # saturation, c/(1 + s c) per site (01b Eq 3, p.12)
        Dc                              # m² s⁻¹
        α                               # s⁻¹, secretion at EC sites
        ε                               # s⁻¹, decay at medium sites
        t_relax = 0                     # MCS without the field (01 §7.4, D-5)
    end
    @variables c(field) = 0.0                          # c₀ = 0 (pde.cpp:104-106)
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = NeighborOrder(order))
    @relations proposal = NeighborOrder(order)         # energy relation = proposal relation (ca.cpp:206, :389)
    @energy begin
        cells(endothelial) => λ * (volume - A)^2       # 01a Eq 1; 01b Eq 2
        contacts => J[kind, kind′]                     # unordered pairs; TST sums the target's pairs (same ΔH)
    end
    sat = saturating_linear(s)                         # c/(s c + 1) (ca.cpp:188-193)
    χ = ifelse((old == 0) || (new == 0), χcM, χcc)     # interface = the copy's (source, target) (01 §8 A-13)
    chemo = -χ * (sat(c[target]) - sat(c[source]))     # 01b Eq 3; = 01a Eq 2 with s = 0
    if mode === :extension_retraction
        @drive copy => chemo
    else
        @drive copy => ifelse(new == 0, 0.0, chemo)    # 01b Eq 4: medium-source copies are neutral
    end
    @equations D(c) ~ (mcs >= t_relax) * τ *
                      (Dc / Δx^2 * Δ(c) + α * (kind == endothelial) - ε * c * (kind == medium))   # 01b Eq 1 (01a Eq 6 as prose, A-4)
    @boundary c (kind == border) => Dirichlet(0.0)    # [R5] absorbing ring, clamped every substep (pde.cpp:189-194)
    @schedule fields, copies                          # [R5][NEW syntax] PDE before the sweep (vessel.cpp:86-94)
    @sweep Metropolis(; temperature = T, field_solver = ExplicitEuler(substeps = 15))   # 15 × 2 s (01a p.49)
end

# ── Merks 2006, Variant E (01 §3.1, §7.8; 2008-code values "assumed for 2006") ─────────────
@potts_model Merks2006 begin
    @structural_parameters begin
        lattice = (502, 502)            # 500² (01a Fig 4) + ring
        rule = :soft                    # D-050 M3: soft E₀; :hard = veto variant
    end
    @extend endothelial, border, c = core = MerksCore(; lattice, order = 2,          # 8 sites (01a p.47; longcells.par:18)
        T = 50.0, λ = 50.0, A = 100.0,                                              # 01a p.48; longcells.par:7,9
        J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0],                          # 01a p.48; J(M,B) = 0 (ca.cpp:236)
        χcM = 1000.0, χcc = 1000.0,                                                 # γ at every copy (01a Eq 2; A-7)
        Dc = 1.0e-13, α = 1.8e-4, ε = 1.8e-4)                                       # 01a p.49
    @parameters begin
        λ_L = 5.0                       # longcells.par:10 (01 §7.8)
        L = 50.0                        # D-050 M2: "about 100 µm" = 50 px; 60 = code variant (D-12)
        E₀ = 5000.0                     # D-050 M3; longcells.par:12 (2000 = default.par variant, D-13)
    end
    @energy cells(endothelial) => λ_L * (major_length - L)^2      # 01a Eq 4; l = 4√(λ₁/a) (Eq 5)
    # TST ConnectivityPreservedP: target's fixed 8-ring, losing cell only (ca.cpp:1166-1226; 01 §7.3)
    breaks = (ring_arcs > 1) && ((ring_cells > 2) || any(owner[n] == 0 for n in Moore(1)(target)))   # [?]
    if rule === :soft
        @drive copy => E₀ * breaks      # threshold shift ≡ additive term under Metropolis (01a Eq 3)
    else
        @constraint !breaks             # [?] hard variant with the same test
    end
end

# ── Merks 2008, Variant CI (Dataset S1, 01 §7.1) ─────────────────────────────────────────
@potts_model Merks2008 begin
    @structural_parameters begin
        lattice = (202, 202)            # sprout_*.par:34-35 (Figs 5–11); Fig 12: (502, 502)
        mode = :extension_retraction    # D-050 M7; *_extensiononly_*.par:13
    end
    @extend χcM, χcc, s, T, c = core = MerksCore(; lattice, order = 4, mode,      # 20 sites (neighbours = 3)
        T = 50.0, λ = 25.0, A = 50.0,                                           # :5, :8, :6
        J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0],                      # J.dat; border_energy (:15)
        χcM = 500.0, χcc = 0.0, s = 0.0,                                        # :14, 01b p.12, :26
        Dc = 1.0e-13, α = 1.0e-3, ε = 1.0e-3,                                   # :23-25
        t_relax = 100)                                                          # :40 (D-050 M6; not in paper)
    @observed accepted_ΔH ~ cumulative_accepted_ΔH                             # [NEW] 01b Fig 13 (V-C11, D-17)
end

# ── Problems (01 §2.9; D-050 M10, M11) ───────────────────────────────────────────────────
@named m06 = Merks2006()
seed06 = overlay(Frame(:border; width = 2),
                 Scattered(282, (10, 10); region = (85:417, 85:417), kinds = [:endothelial], seed = 1))  # 01a Fig 4; shape UNSPECIFIED (01 §2.9)
sol06 = solve(PottsProblem(m06, layout(seed06, m06), (0, 6000); seed = 1),       # 50 h at 30 s/MCS
              SequentialCPM(); saveat = 0:120:6000)

@named m08 = Merks2008()
sprout = overlay(Frame(:border; width = 2),
                 Splits(Eden(1; rounds = 50, at = :center, kinds = [:endothelial], seed = 1), 7))   # [R2] 128 cells (01 §7.6)
prob08 = PottsProblem(m08, layout(sprout, m08), (0, 10_100); seed = 1)          # 100 relax + 10,000 MCS
fig5 = EnsembleProblem(prob08; trajectories = 10 * 11,                          # χcc/χcM ∈ 0:0.1:1, n = 10 (01b Fig 5)
    prob_func = (p, i, _) -> remake(p; p = [:χcc => 500.0 * ((i - 1) ÷ 10) / 10]))
denovo = overlay(Frame(:border; width = 2),
                 Eden(1000; rounds = 10, region = (85:417, 85:417), kinds = [:endothelial], seed = 1))  # [R2] 01b Fig 2 (M10), on (502, 502)

compactness(u) = cell_area(u, :endothelial) / convex_hull_area(u, :endothelial)  # [R16] C = A/A_hull (01b p.5; ca.cpp:1376)
```

(≈ 110 lines of code.)

## Line → source

| Line | Spec | Paper / code |
|---|---|---|
| `@kinds … border[frozen]`, `J(c,B) = 100`, `J(M,B) = 0` | 01 §2.1, §7.2, §7.5 | 01a p.48; 01b p.11; ca.cpp:97-105, :228-238 |
| `NeighborOrder(2)` / `NeighborOrder(4)` for energy and proposal | 01 §2.1, §7.3, §8 A-8 | 01a p.47 "eight second-order"; 01b p.11 "twenty"; ca.cpp:59-62; longcells.par:18; sprout_*.par:18 |
| `cells(endothelial) => λ(volume − A)²` | 01 §2.2 | 01a Eq 1 p.47; 01b Eq 2 p.11; ca.cpp:249-260 |
| `contacts => J[kind, kind′]` | 01 §2.2, §7.2 | 01a Eq 1; 01b Eq 2; ca.cpp:206-243 |
| `λ_L(major_length − L)²` | 01 §2.2 | 01a Eq 4 p.48, estimator p.48, Eq 5 p.49; cell.h:397-421 |
| `χ = ifelse(old == 0 ‖ new == 0, χcM, χcc)` | 01 §2.3, §8 A-13, A-20 | 01b p.12 "μ = χ(c,M) at cell–ECM …"; ca.cpp:264 |
| `chemo = −χ(sat(c_t) − sat(c_s))`, `sat = c/(1 + s c)` | 01 §2.3 | 01b Eq 3 p.12; 01a Eq 2 p.47; ca.cpp:188-193, :264-274 |
| `ifelse(new == 0, 0, chemo)` (extension-only) | 01 §2.3 | 01b Eq 4 p.12; ca.cpp:269 |
| `breaks` / `E₀ * breaks` | 01 §2.6, §7.3, §8 A-3 | 01a p.49 "E0 > 2000", Fig 3 p.47; ca.cpp:442-448, :1166-1226; longcells.par:12 |
| `D(c) ~ … α·[EC] − ε c·[medium] + D∇²c` | 01 §2.7 | 01b Eq 1 p.3; 01a Eq 6 p.49 (prose reading, A-4); vessel.cpp:151-168; pde.cpp:178-219 |
| `(mcs >= t_relax)` | 01 §7.1, §7.9 D-5 | sprout_*.par:40; vessel.cpp:86 |
| `ExplicitEuler(substeps = 15)`, τ = 30 s | 01 §2.7, §2.10 | 01a p.49; 01b p.12 |
| `@boundary c (kind == border) => Dirichlet(0)` | 01 §2.7, §7.4 | pde.cpp:189-194, :269-285 |
| `@schedule fields, copies` | 01 §7.4, §8 A-16 | vessel.cpp:86-94 |
| 2006 values (λ 50, A 100, λ_L 5, L 50, E₀ 5000, α = ε 1.8e-4, γ 1000) | 01 §3.1, §7.8; D-050 M1–M3 | 01a pp.47–50; longcells.par:7-14, :24-25 |
| 2008 values (λ 25, A 50, χcM 500, χcc 0, s 0, α = ε 1e-3, relaxation 100) | 01 §3.2, §7.1 | 01b pp.3, 11–12; sprout_extensionretraction_t50.par |
| 282 cells in 333² of 500² | 01 §2.9, §3.1 | 01a Fig 4 p.48 |
| Eden 1 blob × 50 rounds, 7 splits → 128 cells | 01 §7.6; D-050 M11 | vessel.cpp:52-61; ca.cpp:901-1163 |
| De novo: 1000 cells in 333² (paper geometry) | 01 §2.9, §7.9 D-1; D-050 M10 | 01b Fig 2 p.4 |
| Compactness `A / A_hull` | 01 §5 V-C3, §7.7 | 01b p.5; ca.cpp:1376-1448 |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@extend … = Base(; kw…)` with keyword overrides; parameters without defaults | exists (AUTHORING §8; `problem.jl:201`) |
| Conditional sections on structural symbols (`mode`, `rule`) | exists (AUTHORING §2) |
| `border[frozen]`, `NeighborOrder(k)`, `@relations proposal` | exist |
| `major_length` in energies (exact ΔH) | exists (D-049 F-3) |
| `ring_arcs`, `ring_cells`, soft drive over them | exist (R0 done, D-051 item 1) |
| `any(owner[n] == 0 for n in Moore(1)(target))` in a drive | [?] gathers exist in drives (WortelAct); `any` over a Bool body at `target` untested |
| `saturating_linear(s)` as a response function | exists |
| `mcs` in a field equation | exists (`compile.jl:604`, site env with `mcs`) |
| `ExplicitEuler(substeps = 15)` | exists |
| `Δ(c)` 5-point, independent of the contact neighbourhood | exists (`CorePotts/src/fields.jl`) |
| `Frame(kind; width)`, `Scattered`, `overlay`, `layout` | exist (P6.1a) |
| `@boundary c mask => Dirichlet(v)` (kind-defined clamp every substep) | planned, R5 (ROADMAP P6.3b); **mask form of the syntax is proposed here** |
| `@schedule fields, copies` (explicit phase order) | planned, R5 (P6.3b); **syntax NEW** (nothing proposed yet) |
| `Eden(n; rounds, at/region)`, `Splits(layer, k)` | planned, R2 (P6.3c); names proposed here |
| `compactness`, `convex_hull_area` | planned, R16 (docs-level analysis, D-051 item 6) |
| `cumulative_accepted_ΔH` | **NEW**, not on the roadmap |
| `SequentialCPM`, `EnsembleProblem`, `remake` | exist |

R4 (topology values) is **not** needed for the 2D reproductions: the TST test composes from
existing values (Friction 3). R4's geometry dispatch is needed only for a hex/3D Merks sibling.

## Friction found

1. **`Chemotaxis(…)` cannot express either Merks model.** Its gate is hard-wired to
   `new != 0 & when` (`vocabulary.jl:634-637`), so a copy where the medium gains a site is
   never chemotactic. Both 01a Eq 2 (every copy) and 01b Eq 3 (extension *and* retraction)
   need exactly those copies (ca.cpp:264-274). The sketch writes a raw drive. The same gate
   is wrong for CC3D's default algorithm (AUTHORING §12.9: "source cell's parameters,
   falling back to target's") and for D-067 C7 (Fortuna retraction). Fix: move the gain
   test into the default of `when` (`when = new != 0`), so `when = true` means every copy,
   and let `strength` be any copy-scope expression (it already can be, e.g. the `χ` switch
   here). Then Merks 2008 would read `Chemotaxis(c; strength = χ, response =
   saturating_linear(s), when = mode === :extension_only ? new != 0 : true)`.
2. **The TST border reaches off the lattice.** TST counts every off-lattice position that
   the 20-site stencil reaches as border, at J(c,B) = 100 (ca.cpp:228-230). Under
   `Closed()` those pairs do not exist. The sketch emulates TST with a width-2 `Frame` on a
   lattice 2 sites larger (202² for a TST 200²). That has two costs:
   - **Attempt count.** Frozen sites consume attempts (AUTHORING §12.9). One MCS here is
     202² attempts against TST's 198², about 4 % more at 202² and 1.6 % at 502². R10's
     "attempts counted over all sites" goes the opposite way. A sweep option to count
     attempts over the mobile sites, or R10's fractional attempts set to 198²/202², would
     remove it.
   - **The planned `Wall(kind)` boundary** (AUTHORING §3, not implemented) is the natural
     home: an off-lattice neighbour that reads as a kind, with no sites and no attempts.
3. **The published connectivity rule matches none of the shorthands, but composes today.**
   TST flags a copy as breaking when `ring_arcs > 1` **and** (`ring_cells > 2` **or** the
   ring touches the medium) (ca.cpp:1166-1226). Neither shorthand is this rule:
   - `connectivity(; rule = :arc_or_pair)` accepts a ring of {own, one other cell, medium},
     because `ring_cells` excludes the medium. TST rejects it.
   - `local_components` is a different test altogether.
   The rule is written above from `ring_arcs`, `ring_cells` and an `any` gather. Since that
   works, R4's "soft E₀" needs no new engine work for 01. Only the combination is untested.
   Suggestion: a `ring_touches(k)` value, or `ring_cells(; medium = true)`, so the test does
   not need a gather. The ring values are 2D only, so a 3D Merks sibling needs R4's geometry
   dispatch.
4. **Operator splitting is not declarable.** TST runs 15 × (secretion/decay, then
   diffusion), a Lie split (vessel.cpp:151-168). `ExplicitEuler` takes one unsplit step of
   the whole right-hand side. The difference is O(Δt²) and statistically invisible, but
   "match the paper's scheme" cannot be stated. R5's phase order covers the order of
   phases, not a split *within* one field step. Possible NEW:
   `field_solver = LieSplit(reaction, diffusion; substeps = 15)`.
5. **Units are converted by hand.** The parameters are written in SI and the equation
   multiplies by `τ` and divides by `Δx²` itself. Two things prevent a cleaner form:
   - DynamicQuantities units are **checked only** (AUTHORING §8); they are not converted
     to lattice units.
   - Setting `Lattice(spacing = Δx)` would scale `Δ`, but it would also rescale
     `major_length`, `position` and `L` into metres.

   NEW: a physical-units lattice. It would take `spacing = 2u"µm"` and
   `mcs_duration = 30u"s"`, convert unit-carrying parameters to lattice units, and leave
   the geometric built-ins in sites.
6. **Kind tables cannot be built from scalar parameters.** 01a Fig 7 sweeps J(c,c) and 01b
   Fig 7 sweeps J(c,c) ∈ [0, 80]. Today each point needs a whole new `J` matrix in
   `remake`. NEW: symbolic entries, `J[kind, kind] = [0 J_cM 0; J_cM J_cc J_cB; 0 J_cB 0]`,
   so that `remake(p = [J_cc => 10])` works without recompiling.
7. **The field phase and the clamp have no settled syntax.** The ROADMAP (P6.3b) names
   `@boundary` "per face with a masked clamp", and AUTHORING §12.5 shows only the per-axis
   form. The kind-mask form `@boundary c (kind == border) => Dirichlet(0.0)` and
   `@schedule` are invented here. Two semantic points need care:
   - The clamp is a **node** value on sites that the frame owns. CorePotts' per-face
     Dirichlet is a **face** value (`ghost = 2v − c`, `fields.jl:14-17`). R5 needs both.
   - `@schedule` should name the same phases for every model (fields, copies,
     before/after-MCS updates, lifecycle), so that Bauer 2007 (rules → copies → fields)
     and Merks (fields → copies) use one vocabulary.
8. **The relaxation gate is a multiplication.** Writing `(mcs >= t_relax) * (…)` in the
   field equation works, but the field kernel still runs 1,500 no-op substeps. That is
   cheap, but it hides intent. A declarative `@discrete_events` (R3) at `mcs == t_relax`
   that switches the field on would read better. It would also make the D-5 time origin
   explicit: `sol` time could be reported from the end of relaxation.
9. **V-C11 has no primitive.** Fig 13 plots the running sum of the ΔH of *accepted* copies,
   which includes the chemotaxis drive but not E₀ (ca.cpp:450). That is not `H`, so
   `total_energy` cannot give it. The sketch uses a NEW accumulator. Separating drive
   contributions (E₀ versus chemotaxis) would need per-term accumulation, which has a
   hot-path cost, so it should be opt-in.
10. **`Splits(layer, k)` repeats a lifecycle rule at layout time.** TST divides each cell
    through its centroid, perpendicular to its long axis (ca.cpp:901-1002). The engine
    already does this for `@divide … along = principal_axis()`. A host-side layout that
    reuses the same division code, rather than a second implementation, would keep R2 and
    the lifecycle consistent.
11. **The base carries every paper's parameter list.** `MerksCore` has to declare
    `t_relax`, `s` and `χcc`, although 2006 uses none of them. A base cannot leave a term
    for an extension to parameterise. This is inherent to `@extend` and acceptable, but the
    alternative is worth recording: a 2006-only drive in the extension that replaces the
    core's. That is possible because "an extension's update of a target replaces the
    base's" for updates, but drives are not named, so it is not possible for drives. NEW,
    minor: named drives and energies (`@drive chemo: copy => …`) that an extension can
    replace.

## Open choices

| Choice | Default in this sketch (spec/decision) | Variant |
|---|---|---|
| 2006 target length L | 50 px (D-050 M2; 01a p.50) | 60 px (every 2006-labelled file; D-12, author question) |
| 2006 connectivity | soft E₀ = 5000, TST ring test, losing cell only (M3) | E₀ = 2000 (default.par; D-13); hard veto `rule = :hard` |
| 2006 chemotaxis scope | every copy, χcc = χcM = 1000 (A-7) | χcc = 0, which is 01a Fig 9c contact inhibition (round cells: L = 10, λ_L = 50, D-14) |
| 2008 mode | `:extension_retraction` (M7) | `:extension_only` (Figs 11–13), T = 200 |
| 2008 χcc | 0 (01b p.12) | continuous ratio for Fig 5 (A-20). The code only had {0, χcM} (D-3) |
| 2008 relaxation | 100 MCS, included (M6) | time origin from MCS 0 or MCS 100 (A-19, open) |
| Frame emulation | width-2 frame on (N+2)² (Friction 2) | width-1 frame on N² (no off-lattice border energy) |
| Field scheme | unsplit explicit Euler, 15 substeps, before the sweep (M5) | Lie split, as in TST (Friction 4) |
| ΔH arithmetic | Float (M9) | none (the integer truncation, D-7, is not offered) |
| 2006 seeding | 10×10 blocks, `Scattered` (M11 allows it until R2) | Eden seeds (2008-code method; A-15 open) |
| 01b Fig 2 geometry | paper: 1000 cells, 333² in 502² (M10) | files: 360 seeds × 10 Eden rounds on 202² (D-1) |
| Sprout geometry | 128 cells on 202² (Figs 5–11) | 256 cells on 502² (Fig 12: `Splits(…, 8)`); 1024 cells on 402² (Fig 10) |
