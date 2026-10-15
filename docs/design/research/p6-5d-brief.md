# P6.5d test-author brief: the Fortuna nucleus-migration reproduction (14a, then 14b and 14c)

2026-10-14. A spec for the P6.5d test author, written before any implementation. It is not
code. Written against `origin/monorepo` at a82c556f (P6.5c merge, D-244), with the P6.5a2
API of `feat/p6-5a2` at 69fc9462 (D-243, about to merge) treated as available.

Conventions:
- `spec l.N` cites `model-specs/14_nucleus_migration.md` at a82c556f; `sketch l.N` cites
  `model-specs/sketches/14_nucleus_migration.md`. Other `file:line` cites are at a82c556f
  unless they name `feat/p6-5a2`.
- 14a pages are journal pages (PDF page = journal page − 2800). 14a-S1, 14b and 14c pages
  are PDF pages (spec l.18–21).
- **[inference]** marks a conclusion of this brief that no source states. **[probe]** marks
  something checked by a small script on `feat/p6-5a2` (16 × 16 × 9 lattice, 5 MCS; script
  in the session scratchpad, not committed). **[estimate]** marks a number that depends on
  stated assumptions.
- Indices are Julia's, 1-based. The 14a code is 0-based: its substrate plane z = 0 is our
  z = 1, its lid z = L_z − 1 is our z = L_z, and its ball "tangent at z = 1" bottoms at our
  z = 2 (as in `research/p6-5c-brief.md`).
- Rulings that win over everything older: spec §9 "Ruling under paper-over-code (2026-10-13)"
  (spec l.619–633), D-233 (`@convert`), D-244 (initial state, fits; "Carried to P6.5d"),
  D-155 (ship provisional), D-156 (FULL runs on the PC, calibrated unstated parameters,
  no outlines).

---

## 0. Summary

| Sub-item | Scope | Runs | Gate for the next |
|---|---|---|---|
| **P6.5d1** (14a) | Model `FortunaMigration`, initial state, SMOKE and short tiers, FULL Figs 5–7, 9, 11 and Table 2, page and videos | ≈ 700 FULL runs on the PC | Yes: d2 and d3 start after d1's SMOKE and short tiers pass |
| **P6.5d2** (14b) | Π_CN−N polarization, Δτ_opt, P1–P6 | No new runs: reads d1's records | No |
| **P6.5d3** (14c) | Chemotaxis variant by `@extend`, C1–C9 | ≈ 240 small runs | Blocked on R12 for its per-cell gate (§6 Q5) |

Recommendation: split P6.5d into these three rows. d1 is the gate. d2 is analysis only and
can be frozen with d1's test file or right after it. d3 has a different mechanism (binary
field, tanh bias, 100-MCS gate) and an open dependency, so it gets its own brief when R12
lands.

---

## 1. Scope and staging

### 1.1 Why split

- 14a is the base model, the primary definition (spec l.7). 14b restates it with no new
  mechanics (spec l.289–305) and adds observables only. 14c changes the mechanism
  (spec l.311–330).
- 14b's run set (λ ∈ {150, 175, 200}, φ ∈ {0.05, 0.10, 0.20, 0.30}, R ∈ {10, 15, 20}, 10
  runs × 10⁵ MCS, 14b p.8; spec l.295) is a subset of d1's run set (§4.4). So d2 costs no
  new runs if d1 records the three compartment centers of mass (§5.1).
- 14c's Switch (Eq 6, 14c p.8) needs a 100-MCS window mean of a cell quantity. `Pre(x, k)`
  on a cell variable is refused today ("lags of cell variables are not tracked",
  `src/lower.jl:163`). ROADMAP schedules it as P6.7b ("R12 `Pre(x, k)` on cell variables",
  `docs/design/ROADMAP.md:753`). See §6 Q5.

### 1.2 Engine features used (all merged or about to merge)

| Feature | Decision | Used for |
|---|---|---|
| `sibling(k)`, `x[ref]`, `alive`, `members` | D-231 | `to = sibling(lamellipodium)`, `volume[to]` |
| `@convert name clusters(k) begin to; at; p end`, `created` | D-233 | conversion (14a p.2806) |
| E1 kind-conditional cell-variable defaults | D-233 (section G of `p6_5b_convert.jl:123–134`) | fixed targets from t = 0 |
| Birth serials kept when `sibling` is read | D-245 | nothing to do: `@convert` keeps them |
| `Interior(Sphere)`, `Objects`, `Fill`, `Group` | D-244 | the initial state |
| Predicate-sourced field rate | D-244 B | Eq 6 source on lamellipodium sites that touch the substrate |
| `unwrap_track`, `msd`, `furth_fit(:paper \| :lsq)`, `natural_units` | D-244 C | Eq 1, Eq 2, Table 2 |
| `Pairs`, `centroid(ref, k)`, `minimum_image`, `separation`, `integral(x; over = cluster)` | D-243 (`feat/p6-5a2`) | J table, Π_CN−N, contact observable |

Every line of the §2 model compiled and ran **[probe]**, with one fix: `field_solver` is a
`PottsProblem` keyword, not a `@sweep` keyword ("`@sweep` no longer takes `field_solver`",
`src/vocabulary.jl:1374` on `feat/p6-5a2`). The probe also ran
`integral((kind == lamellipodium) * (count(true for n in VonNeumann(1)(site) if kind[n] == cytoplasm) > 0); over = cluster)`,
so a neighbor fold inside the integrand works **[probe]**.

### 1.3 Not available (do not use)

- `@terminate` (R3, P6.4c): not in `src/`. The code's detachment stop (spec l.161) becomes
  a post-run classification (§4.4, §6 Q1).
- `contact(c, n)` (R11a): not merged. Replaced by the `integral` contact observable above.
- `Pre(x, k)` on cell variables (R12): see §1.1.
- `Plane`, `Spheres`, `Tiling` + a hand-written `cluster`: replaced by `Fill`, `Objects`,
  `Group` (D-244 A; `p6_5c_initial_state.jl:777–786`).

---

## 2. The model as it should be written (d1)

Source file: `lib/PottsModels/src/fortuna.jl`, exported `FortunaMigration`, plus host
helpers `fortuna_lattice(R, φ_l)` and `fortuna_layout(R, φ_l, sys)` (§3). Model-named
functions live in PottsModels only. Core gets nothing Fortuna-named.

Tags: `[R]` = spec §9 ruling (spec l.619–633); `[Dnnn]` = decision; `[T1]` = 14a Table 1,
p.2807; `[C]` = 14a-code used as evidence where the paper is silent (paper over code).

```julia
@potts_model FortunaMigration begin
    @structural_parameters begin
        lattice = (120, 120, 31)        # R = 15: int(8R)² × int(2.1R) [C] spec l.148; 14a p.2806 (L_z = 2.1R, L ∈ [8R, 14R])
    end
    @kinds medium substrate[frozen] lid[frozen] cytoplasm lamellipodium nucleus   # 14a p.2805; lid [C] spec l.155
    @parameters begin
        R = 15.0                        # R_cell, (lattice sites)^(1/3); 14a p.2806
        φ_n = 0.15                      # [T1]
        φ_l = 0.05                      # 14a p.2806; Figs 5–6
        T = 100.0                       # T_B [T1]
        λ = 10.0                        # λ_c = λ_l = λ_n [T1]
        λ_F = 150.0                     # λ_F-actin, Eq 7 sign (spec l.578, §9 item 2)
        D_F = 1.0e-4                    # [T1]
        k_decay = 0.9                   # [T1]
        k_source = 0.9                  # [T1]
        c = 0.1                         # unstated; calibrated (D-156) from the code's 0.1 [R] spec l.625; §4.3 S-cal
        J[kind, kind] = Pairs(default = 0.0,                                  # D-243 E2
            (medium, substrate) => 20, (medium, cytoplasm) => 20,             # [T1]
            (medium, lamellipodium) => 40 / 3, (medium, nucleus) => 100,      # [T1]
            (substrate, cytoplasm) => 20, (substrate, lamellipodium) => 20 / 3,
            (substrate, nucleus) => 100,                                      # [T1]
            (cytoplasm, lamellipodium) => 20,                                 # [T1] and [R]: 20, not the code's 10
            (cytoplasm, nucleus) => 20, (lamellipodium, nucleus) => 40,       # [T1] ("front" = lamellipodium)
            (medium, lid) => -20, (lid, cytoplasm) => 20,                     # [C] spec l.186, l.194
            (lid, lamellipodium) => 40 / 3, (lid, nucleus) => 100)            # [C]
    end
    @variables begin
        F(field) = 0.0                  # F-actin on the whole lattice, unconfined (spec l.77, l.167)
        V_target(cell) = ifelse(kind == nucleus, φ_n, ifelse(kind == lamellipodium, φ_l,
                         ifelse(kind == cytoplasm, 1 - φ_n - φ_l, 0.0))) *
                         (4 / 3 * 3.141592653589793 * R^3)    # fixed from t = 0, V = (4π/3)R³ [R] spec l.627–628; E1 (D-233)
        lam_births(model) = 0.0         # D-066 diagnostic: lamellipodium creations (spec l.234)
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Periodic(), Closed()),   # 14a p.2806; z closed [C] spec l.149
                     neighborhood = NeighborOrder(4))                          # 32-neighbor contacts, 14a p.2805
    @relations proposal = VonNeumann(1)                                        # copy distance 1, 14a p.2805; spec l.107

    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0   # spec l.166 (6 faces)

    @energy begin
        cells(cytoplasm, lamellipodium, nucleus) => λ * (volume - V_target)^2  # Eq 5, 14a p.2805
        contacts => J[kind, kind′]                                             # Eq 4; zero only for same cell (spec l.580)
    end
    # Eq 7, both directions (C7, D-067; spec l.211): ΔE = λ_F (F(target) − F(source))
    @drive copy => ifelse(((kind[new] == lamellipodium) & (old == 0)) |
                          ((kind[old] == lamellipodium) & (new == 0)),
                          λ_F * (F[target] - F[source]), 0.0)
    # Eq 6; one explicit step per MCS = CC3D's diffuse + decay, then secrete (spec l.170, l.173)
    @equations D(F) ~ D_F * Δ(F) - k_decay * F +
                      k_source * (kind == lamellipodium) * touches_substrate(site)   # D-244 B
    # 14a p.2806 paper form [R]: independent per site, p once per MCS on start-of-pass V₃,
    # clamped to [0, 1] by the runtime, NaN converts nothing (D-233). φ_l is the parameter,
    # not V_target[to] (spec l.626).
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)     # allocated on the first conversion (D-066, D-233)
        at = touches_substrate(site)    # every cytoplasm site at z = 2 (spec l.221)
        p = c * (1 - volume[to] / (φ_l * (4 / 3 * 3.141592653589793 * R^3)))
        lam_births += created
    end
    @observed begin                     # read on the cytoplasm row (the cluster root)
        nx(cell) ~ centroid(sibling(nucleus), 1)          # MSD point: nucleus COM, xy (14a-S1 p.10; spec l.121)
        ny(cell) ~ centroid(sibling(nucleus), 2)
        lx(cell) ~ centroid(sibling(lamellipodium), 1)    # 14b Eq 10, 14a Fig 12
        ly(cell) ~ centroid(sibling(lamellipodium), 2)
        Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) /
                   (volume + volume[sibling(nucleus)])    # Π_CN−N, 14b Eq 10–11 (D-243 test l.641)
        Πy(cell) ~ volume * minimum_image(centroid(2) - centroid(sibling(nucleus), 2), 2) /
                   (volume + volume[sibling(nucleus)])
        lam_cyto(cell) ~ integral((kind == lamellipodium) *
                   (count(true for n in VonNeumann(1)(site) if kind[n] == cytoplasm) > 0); over = cluster)  # detachment (§4.4)
    end
    @sweep Metropolis(; temperature = T)                  # 14a p.2805
end
```

Run call: `PottsProblem(sys, op, (0, 100_000); seed, field_solver = ExplicitEuler(substeps = 1))`,
solved with `SequentialCPM()`. One explicit substep is CC3D's single solver call
(spec l.169; the stable-substep rule cannot raise it at D_F = 10⁻⁴, D-244 B contract
`p6_5c_predicate_source.jl:29–31`).

Phase order per MCS is the default schedule: sweep, `after_mcs`, fields, `protrusion`,
`lifecycle` (`p6_5b_convert.jl:99–104`). That is the code's Potts sweep, then the PDE,
then conversion (spec l.239–243; pinned by `p6_5c_predicate_source.jl` §7).

Notes for the implementer:
- One cell per run, so one contact table suffices. The code's `ContactInternal` split
  (spec l.158) changes nothing for a single cell. Pairs between two cells of one kind
  never occur; `default = 0.0` covers them.
- The diagonal J of the frozen planes (code: 1) never acts: each plane is one cell.
- `V_target` reads 0 for the medium and the planes, so `volume[to] / V_target[to]` of an
  absent lamellipodium would be 0/0 = NaN and convert nothing. This is why `p` uses the
  parameter φ_l (spec l.626; D-233 ruling 6).
- The `lam_births` write is the D-233 compound write (`p6_5b_convert.jl:83–87`).

### 2.1 Parameters

| Symbol | Value(s) | Source | Status |
|---|---|---|---|
| R_cell | 10, 15, 20 | 14a p.2806; 14a-S1 p.3 | stated |
| φ_n | 0.15 | Table 1, p.2807 | stated |
| φ_l | 0.05, 0.10, 0.20, 0.30 | p.2806; Figs 5–6, p.2808 | stated |
| φ_c | 1 − φ_n − φ_l | spec l.68 | derived |
| V_cell | (4π/3) R³ | p.2806; [R] spec l.628 | stated |
| T_B | 100 | Table 1 | stated |
| λ_c, λ_l, λ_n | 10 | Table 1 | stated |
| D_F, k_decay, k_source | 10⁻⁴, 0.9, 0.9 | Table 1 | stated |
| λ_F-actin | 75, 100, 125, 150, 160, 165, 170, 175, 200, 250 | Fig 5 (100–200), Fig 6 (125–250), p.2808; Table 2 (75–200), p.2810 | stated |
| J (10 pairs) | 20, 20, 40/3, 100, 20, 20/3, 100, 20, 20, 40 | Table 1 | stated; J_cyto–lam = 20 by [R] |
| J with the lid | −20, 20, 40/3, 100 | code (spec l.186, l.194) | code evidence; paper silent |
| c | 0.1, then calibrated | [R] spec l.625 | unstated, calibrated (§4.3) |
| Lattice | int(8R)² × int(2.1R); int(10R) when R ≥ 20 and φ_l ≥ 0.2 | p.2806 range; code rule spec l.148 | code rule inside the paper's range |
| Proposals | `VonNeumann(1)` | p.2805; spec l.107 | inferred, explicit in 14b p.3 |
| Run length | 10⁵ MCS | Figs 5–6 | stated |
| Sampling | every 50 MCS for MSD | 14a-S1 p.10 ((T − Δt)/Δt = 1999) | stated |

---

## 3. Initial state

Rule (spec l.627–630; D-244): no lamellipodium; a 6³ nucleus seed; a cytoplasm ball with
strict membership, tangent to the substrate, holding ≈ (1 − φ_n − φ_l)V cytoplasm sites
plus the 216 nucleus sites.

- r₀ = ∛(((1 − φ_n − φ_l)V + 216) / (4π/3)), V = (4π/3)R³.
- Ball center (L ÷ 2 + 1, L ÷ 2 + 1, r₀ + 1). The site (L ÷ 2 + 1, L ÷ 2 + 1, 1) lies at
  distance exactly r₀ and is excluded by `Interior`, so the ball bottoms at z = 2.
- Nucleus: `Fill(:nucleus; region = map(a -> (a - 3):(a + 2), cn))`, with
  cn = (L ÷ 2 + 1, L ÷ 2 + 1, round(Int, r₀ + 1)) **[inference]** (the code puts the cube at
  the integer cytoplasm center of mass, spec l.159; P6.5c pinned the integer-R form,
  `p6_5c_initial_state.jl:777–786`).
- Layout: `overlay(Group(Objects(Interior(Sphere(Point(c...), r₀)); kinds = [:cytoplasm]), Fill(:nucleus; region)), Fill(:substrate; region = (1:L, 1:L, 1:1)), Fill(:lid; region = (1:L, 1:L, Lz:Lz)))`.
  This is the P6.5c recipe (`p6_5c_initial_state.jl:777–786`) at non-integer r₀
  (`p6_5c_initial_state.jl:827–850`).

Exact counts (brute-force oracle, strict rule with r·(1 − 1e-12), center as above). The two
R = 15 rows at φ_l = 0.05 and 0.30 equal D-244's pinned values (11512 and 7980; ztop 29 and
25; 89 and 69 sites at z = 2).

| R | φ_l | Lattice | r₀ | Ball | Cytoplasm | Cyto target | Δ | z range | Sites at z = 2 | Nucleus z |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 0.05 | 80² × 21 | 9.478497 | 3546 | 3330 | 3351.0 | −21.0 | 2–19 | 57 | 7–12 |
| 10 | 0.10 | 80² × 21 | 9.289232 | 3374 | 3158 | 3141.6 | +16.4 | 2–19 | 57 | 7–12 |
| 10 | 0.20 | 80² × 21 | 8.885657 | 2933 | 2717 | 2722.7 | −5.7 | 2–18 | 49 | 7–12 |
| 10 | 0.30 | 80² × 21 | 8.441659 | 2528 | 2312 | 2303.8 | +8.2 | 2–17 | 45 | 6–11 |
| 15 | 0.05 | 120² × 31 | 14.012856 | 11512 | 11296 | 11309.7 | −13.7 | 2–29 | 89 | 12–17 |
| 15 | 0.10 | 120² × 31 | 13.720328 | 10835 | 10619 | 10602.9 | +16.1 | 2–28 | 89 | 12–17 |
| 15 | 0.20 | 120² × 31 | 13.094608 | 9398 | 9182 | 9189.2 | −7.2 | 2–27 | 81 | 11–16 |
| 15 | 0.30 | 120² × 31 | 12.402584 | 7980 | 7764 | 7775.4 | −11.4 | 2–25 | 69 | 10–15 |
| 20 | 0.05 | 160² × 42 | 18.616086 | 27029 | 26813 | 26808.3 | +4.7 | 2–38 | 113 | 17–22 |
| 20 | 0.10 | 160² × 42 | 18.223114 | 25320 | 25104 | 25132.7 | −28.7 | 2–37 | 109 | 16–21 |
| 20 | 0.20 | 200² × 42 | 17.381861 | 21998 | 21782 | 21781.7 | +0.3 | 2–35 | 101 | 15–20 |
| 20 | 0.30 | 200² × 42 | 16.450191 | 18616 | 18400 | 18430.7 | −30.7 | 2–33 | 97 | 14–19 |

The nucleus box lies wholly inside the ball in every row **[probe]** (scratchpad script, pure
Python, independent of Potts). Nucleus target φ_n·V: 628.3 (R = 10), 2120.6 (R = 15),
5026.5 (R = 20). The nucleus grows from 216 to its target at the cytoplasm's expense, and
the cytoplasm refills from the medium (spec l.630).

---

## 4. Acceptance criteria

All tiers run on the PC (D-157: no intensive compute on this Mac). SMOKE runs in the
PottsModels suite. The file is `lib/PottsModels/test/reproductions/14_fortuna.jl`, frozen
under AUTONOMY §7.3, with the 10_akeeb.jl layout: a header table of rows, tiers by
`POTTS_FULL_REPRODUCTION=true` / `REPRO=full` (`test/reproductions/10_akeeb.jl:1–90`).
Every band, seed list, replicate count and lag window is fixed before its run.

### 4.1 SMOKE (minutes; CI)

| ID | Check | Oracle / rule |
|---|---|---|
| S1 | `FortunaMigration` builds and `mtkcompile`s at R = 10, 15, 20 | — |
| S2 | `Pairs` lowers to Table 1: every listed entry, symmetric, J_cyto–lam = 20 | hand matrix (D-243 E2) |
| S3 | Initial state: all 12 rows of the §3 table (ball, cytoplasm, z range, sites at z = 2, nucleus box); `cluster` = one group plus the two planes; no lamellipodium; plane volumes L² | brute-force oracle, as `p6_5c_initial_state.jl` §10 |
| S4 | Targets fixed: after 200 MCS at R = 10, `V_target` of cytoplasm and nucleus equal their t = 0 values bitwise; the created lamellipodium reads φ_l·V; no transfer | E1 defaults; [R] spec l.628 |
| S5 | Conversion only at cytoplasm sites with a substrate face neighbor; the converted set of pass k equals the draw oracle `u < clamp(p, 0, 1)` with p from the start-of-pass V₃ | D-233 draw address (`p6_5b_convert.jl:70–76`), on a copy-blocked twin (note below) |
| S6 | p formula and edges: c = 2.5 gives p > 1 (every candidate converts); V₃ ≥ φ_l·V gives p ≤ 0 (nothing); φ_l = 0 gives p = c·(1 − 0/0) = NaN (nothing) | D-233 rulings 6 |
| S7 | F-actin source: on a copy-blocked twin with lamellipodium sites at z = 2 and z = 3, F at z = 2 lamellipodium sites is 0.9, 0.99, 0.999 after 1–3 MCS (±10⁻³); every other site stays ≤ 10⁻³ | spec l.174; `p6_5c_predicate_source.jl` §6 |
| S8 | Drive sign: one extension copy (lamellipodium source, F = 1, into medium, F = 0) adds −λ_F to ΔH; one retraction copy adds +λ_F; a cytoplasm → medium copy adds 0 | the ΔH oracle style of `p6_5a2_ref_helpers.jl` (feat/p6-5a2) l.167–190 |
| S9 | Bookkeeping after 500 MCS (R = 10): trackers equal a recount from σ; Σ volumes + medium = lattice size; the ΔH self-check holds | existing self-check helpers |
| S10 | Determinism: same seed gives bitwise-equal σ, F and observables at MCS 300; a different seed differs | free determinism |
| S11 | Negative controls: c = 0 → no lamellipodium is ever alive in 500 MCS; φ_l = 0 → the same (NaN path); with the drive on, the default run has an alive lamellipodium by MCS 50 | D-048 |
| S12 | Observables: `nx`, `ny` of a hand-shifted state across the periodic seam unwrap correctly through `unwrap_track`; Πx, Πy equal 14b Eq 11 by hand | D-243 test l.641–647 |
| S13 | S-resolution oracle (§4.5), host only | synthetic, StableRNG |
| S14 | 14b P1 (analytic): maximizing Eq 12 reproduces Δτ_opt = 1.932 S^0.455 and α_opt = 2.022 − 1.115 S^0.397 within 3 % over S ∈ [10⁻⁴, 0.4] | spec l.508 (d2's first row; frozen with d1 if convenient) |

Copy-blocked twin (S5, S7): `@extend` `FortunaMigration` with `@parameters mobile = 0.0` and
`@constraint mobile > 0.5`, the P6.5b trick (`p6_5b_convert.jl:755`). **[verify]** that
`@extend` accepts an added `@constraint`. If it does not, the test defines a twin body
inline, as `P65B_FORTUNA_BODY` does, and S1–S4 and S8–S12 still use the shipped model.

Expected SMOKE cost **[estimate]**: about 2 min of compilation plus under 1 min of runs
(R = 10 is 134,400 sites; 500 MCS ≈ 2 s at 30 ns per copy attempt).

### 4.2 Short qualitative tier (PC, < 1 h)

| ID | Check | Rule |
|---|---|---|
| Q1 | B1 onset (spec l.492): R = 10, φ_l = 0.05, λ_F = 150, 3 replicates × 2 × 10⁴ MCS. The lamellipodium is alive from MCS ≤ 50; |Π_CN−N| goes from < 0.5 site at t = 0 to a time mean > 1 site over MCS 5000–20000 | per replicate |
| Q2 | Motion: the same runs move the nucleus by > 2R over 2 × 10⁴ MCS in every replicate **[inference]**: Table 2 gives P = 4150, D = 2.56 × 10⁻³ R²/MCS, so Eq 1 predicts an MSD of ≈ 80 R² | per replicate |
| Q3 | Regime sanity: R = 15, φ_l = 0.30, λ_F = 125 (Fig 6 cyan) moves < 2R in 2 × 10⁴ MCS (3 replicates, mean) | mean |
| Q4 | Mechanism control: λ_F = 0 at the Q1 set moves < 1/3 of Q1's mean displacement (not a paper target; spec l.461 F23) | mean |
| Q5 | B2 volumes: in Q1, the time mean of \|V − V_target\|/V_target over MCS 5000–20000 is ≤ 2 % for each compartment | spec l.493 |
| Q6 | Timing: ns per copy attempt at R = 10, 15 and 20 over 1000 MCS, recorded; it replaces the §4.4 estimate before FULL starts | info |

**S-cal (the c calibration, pre-registered).** c is unstated (spec l.625). Use c = 0.1, the
code's constant. If Q5 fails at c = 0.1, rerun Q1/Q5 with c ∈ {0.3, 1.0} and take the
smallest c that passes Q5. c is never chosen against Figs 5–6 or Table 2. The chosen c is
labelled "calibrated" on the page (D-156).

### 4.3 FULL tier, d1 (PC)

Run set: every (R, φ_l, λ_F) of Fig 5, Fig 6 and Table 2. That is 68 sets: R = 10, 21 sets
(λ_F 100–200 × 4 φ_l, plus λ_F = 75 at φ_l = 0.05); R = 15, 27 sets (λ_F 100–250 × 4, plus
160, 165 and 170 at φ_l = 0.30); R = 20, 20 sets (λ_F 100–200 × 4). Replicates: 10 per set
(Fig 6 shows 10, Fig 5 used 5); 30 for R = 15, φ_l = 0.30, λ_F = 160 (Fig 9, p.2809). Seeds:
a fixed list, one per (set, replicate), written in the test header.

| ID | Target | Source | Band | Gating? |
|---|---|---|---|---|
| B2 | compartment volumes within 1 % of target in steady state | p.2806 | mean \|ΔV\|/V_t ≤ 2 % (spec l.493), every set | yes |
| B3 | Fig 6 regime map, R = 15: φ_l = 0.05: 125–175 migrating, 200–250 detachment; φ_l ≥ 0.10: 125 confined, 150–200 migrating, 250 detachment | Fig 6, p.2808 | ≥ 16 of 20 panels match (spec l.494) | yes |
| B4 | Fig 5 displacement after 10⁵ MCS, nucleus xy, in R units, 60 points | Fig 5, p.2808 (digitized, D-202 style) | within 2 × the published SE, or a factor 2 on a log scale (spec l.495) | yes, per point |
| B5 | Table 2 S, P, D on the nucleus xy track, 40 rows | p.2810 | S within ×2 (log), P ± 50 %, D within ×2 (log) (spec l.496) | yes, per row |
| B5′ | The three inconsistent rows (R = 15: φ 0.10 λ 150; φ 0.20 λ 150; φ 0.30 λ 160) | spec l.496 | S as B5; P and D get the spec's "×2 extra slack": P ∈ [0.25 P, 3 P], D within ×4 **[inference: our reading of "×2 extra slack"]** | S yes; P, D yes with the wider band |
| B6 | Metzner match: S = 0.02 (text p.2809; Table 2: 2.12 × 10⁻²) | p.2809 | S ∈ [0.01, 0.04] with SE(S) ≤ 0.005 (§4.5); the collapsed MSD within 20 % of Eq 2 at S = 0.02 | yes (S only; P, D not targets, spec l.497) |
| B7 | All MSDs collapse onto Eq 2 in natural units | Fig 7, p.2809 | RMS of log(MSD) residual ≤ 0.1 per set | yes |
| B8 | D_fast = 0.127 R⁻² (lattice sites)^{2/3}/MCS; with D_fast from Table 2 in R²/MCS this is D_fast·R² ≈ 0.127/R² sites²/MCS **[inference, checked on two rows: R = 10, φ 0.05, λ 150 gives 1.50 × 10⁻³ vs 1.27 × 10⁻³; R = 15, φ 0.10, λ 150 gives 6.2 × 10⁻⁴ vs 5.6 × 10⁻⁴]** | Fig 11, p.2812 | fitted prefactor within ± 30 % of 0.127 | yes |
| B9 | \|u(τ, δ)\| grows as δ → 0; ψ_δ as in Fig 8 | Fig 8 | monotone | info |
| B10 | polarization correlates with displacement for S < Δτ < 1 | Fig 12 | qualitative | info (spec §9 item 19 open) |
| B11 | cost vs CC3D's 200 min per R = 15 run | p.2810–2811 | — | info |

Rules shared by B4–B8:
- The tracked point is the nucleus center of mass in xy, periodic-unwrapped, divided by R
  (14a-S1 p.10; spec l.121; Table 2 units R²_cell).
- MSD: the whole 10⁵-MCS track at Δt = 50 MCS (2001 samples, so (T − Δt)/Δt = 1999 as in
  14a-S1 p.10); overlapping windows; replicates averaged with equal weight (`msd`, D-244 C2).
- Fits use both `:paper` and `:lsq`. A method gates B5–B8 only if it passed the §4.5
  oracle. A method that failed it is reported as info.
- A set that the paper fits but our runs classify as confined or detached fails its B5 row
  as "regime mismatch" and is not fitted (Table 2 lists only cells "not confined or broken",
  p.2810).
- No aggregate pass rule: each row has its own verdict, and the page reports the counts
  (as page 15 does). Failures ship provisional as deviations (D-155).

Regime classification (B3, used by B5) **[inference; §6 Q1]**:
- A replicate is **detached** if `lam_cyto` = 0 at any 50-MCS sample after MCS 10 while the
  lamellipodium is alive (the code's criterion, spec l.161, applied after the run because
  `@terminate` is not merged). Lamellipodium deaths (`lam_births` − 1) are reported, not
  classified.
- A set is **detachment** if ≥ 5 of its 10 replicates detach; else **confined** if its mean
  nucleus displacement after 10⁵ MCS is < 2R (p.2807: "less than a cell diameter (2R_cell)
  … nonmotile"); else **migrating**.

### 4.4 Compute estimate for d1 FULL **[estimate]**

Assumptions: `SequentialCPM` on one thread per replicate; 30 ns per copy attempt, averaged
over cheap medium–medium attempts and costly 32-neighbor boundary attempts (no 3D
`NeighborOrder(4)` benchmark exists yet; Q6 measures it); the field and conversion phases
add < 10 %; the PC runs about 18 replicates at once in the 24-thread FULL cap (D-156, D-157).

| R | Sites per run | Runs | Site-MCS | Wall per run |
|---|---|---|---|---|
| 10 | 134,400 | 210 | 2.8 × 10¹² | ≈ 7 min |
| 15 | 446,400 | 290 | 1.3 × 10¹³ | ≈ 22 min |
| 20 (φ_l < 0.2) | 1,075,200 | 100 | 1.1 × 10¹³ | ≈ 54 min |
| 20 (φ_l ≥ 0.2) | 1,680,000 | 100 | 1.7 × 10¹³ | ≈ 84 min |
| Total | | 700 | 4.3 × 10¹³ | |

That is ≈ 360 core-hours, about **20 h of wall time** on the PC. At 15–60 ns per attempt
the range is 10–40 h. For reference, CC3D took 200 min per R = 15 run on an i7-3770K
(p.2810–2811), about 270 ns per attempt. Launch order: the B6 set first, then the Fig 6
grid (R = 15), then the rest of Table 2, then the rest of Fig 5. A FULL batch runs only
outside A/B quiet windows (D-242, D-248).

d2 adds no runs. d3 **[estimate]**: R = 10 on 59² × 21 (73,101 sites), λ_F ∈ {125, 150, 175}
× φ_f ∈ {0.05, 0.10, 0.20} × μ ∈ {0, 10⁶} × 10 replicates = 180 runs, plus Fig 3's R = 15
and 20 (≈ 60 runs): about 2 × 10¹² site-MCS, under 2 h of wall time.

### 4.5 S-resolution protocol (D-244 "Carried to P6.5d")

On the D-244 S = 0 synthetic, `:paper` reached |S| = 0.058, larger than Fortuna's S = 0.02.
So, before any FULL fit:

1. **Oracle at S = 0.02, Fortuna's sampling.** Generate OU + Brownian tracks with the
   generator of `p6_5c_msd_furth.jl:104–131` (exact AR(1), StableRNG) at S = 0.0212,
   P = 8327 MCS, D = 1.13 × 10⁻⁴ R²/MCS (the B6 row as printed), sampled every 50 MCS for
   10⁵ MCS (2001 samples), 30 tracks. Repeat with P = 11987 (the value the row's own last
   column implies, spec l.459).
2. **Controls.** The same at S = 0 and at S = 0.1.
3. **Calibrate once, on 16 seeds.** The test author fixes, for each method, the lag window
   (`range`, `short`) from the oracle only. A method passes if the median |S − 0.0212| ≤
   0.005 and the seed-to-seed SD ≤ 0.005, and the S = 0 control gives median |S| ≤ 0.01.
4. **Size replicates.** If the SD at 30 tracks exceeds 0.005, raise the B6 replicate count
   to the smallest N ≤ 100 that meets it (SD ∝ 1/√N, checked on the oracle).
5. **Freeze.** The windows, N and the passing methods go into the test header. B5–B8 use
   them unchanged. SE(S) on the simulations is a bootstrap over replicates (1000
   resamples, fixed seed).

### 4.6 FULL tier, d2 (14b; analysis of d1's records)

Data: R ∈ {10, 15, 20}, φ ∈ {0.05, 0.10, 0.20, 0.30}, λ_F ∈ {150, 175, 200}, 10 replicates,
statistics after a 1000-MCS warm-up (14b p.8; spec l.295–296).

| ID | Target (spec l.508–513) | Band | Gating? |
|---|---|---|---|
| P1 | Eq 12 fits (analytic) | 3 % | yes (SMOKE S14) |
| P2 | Δτ_opt = 0.048 at R = 15, φ 0.10, λ 200; 0.672 at φ 0.30, λ 150 (S = 9.46 × 10⁻²) | ± 30 % from our fitted S | yes |
| P3 | ξ_CN−N(δ) peaks near Δτ_opt (φ 0.10, λ 200); all definitions fail at φ 0.30, λ 150 | peak within ×2 | yes |
| P4 | ⟨u(Δτ_opt)⟩ up and ε down with ⟨\|Π_CN−N\|⟩; ⟨u⟩ down with φ | same monotone trends | yes |
| P5 | σ_θ down with ⟨Π⟩ and up with φ; ⟨Π⟩ down with φ | same trends | yes |
| P6 | ⟨u_∥⟩_δ converges as δ → 0 while ⟨u⟩_δ diverges | ≤ 10 % change over the smallest decade of δ | yes |

14b records "at each MCS" (14b p.6). d1 records every 10 MCS (§5.1); the smallest δ is then
10 MCS, about 10⁻³ P at the sets above. This is a deviation row **[inference: no target
needs δ below 10 MCS]**.

### 4.7 FULL tier, d3 (14c; own brief later)

Targets C1–C9 as in spec l.519–527, with C3, C5 and C6 quantitative and gating, C9 info.
Mechanism per spec §4.1 and the §9 ruling (spec l.632): `@extend FortunaMigration`,
redeclaring `@convert protrusion` with p = ρ[tanh(μ(Q − ⟨Q⟩)/σ_Q) + 1] × Switch, per-MCS
base statistics by `integral(…; over = cluster)`, a binary F refreshed once per MCS. Open
items: §6 Q5 and Q6, and spec §9 items 10–13 (spec l.601–610).

---

## 5. Records and the docs page

### 5.1 Records

Per run, in memory during the run and written at its end:
- every 10 MCS: centers of mass (x, y, z) of cytoplasm, nucleus and lamellipodium, wrapped
  as `centroid` returns them; the three volumes; `Πx`, `Πy`; `lam_cyto`; `alive` of the
  lamellipodium; `lam_births`. Float32 is enough.
- recorded by stepping the integrator and calling `observe` on its state, not by
  `saveat` of full states (a full R = 15 state is ≈ 1.8 MB).

Record directory `lib/PottsModels/reproductions/data/14/full-YYYY-MM-DD/` (D-156), as
`data/01/full-2026-10-08/`:

| File | Content |
|---|---|
| `README.md`, `provenance.toml` | machine, CPU, threads, Julia, commit, dirty flag (D-156) |
| `run_full.jl`, `evaluate.jl`, `figures.jl` | the scripts that made and read the record |
| `sets.tsv` | one row per set: R, φ_l, λ_F, n, seeds, regime, detach count, mean and SE of the displacement |
| `fits.tsv` | per set and method: S, P, D, D_fast, v_eff, bootstrap SE(S), lag window |
| `msd.tsv` | ensemble MSD per set on 60 log-spaced lags |
| `oracle.tsv` | the §4.5 calibration: method, seed, S, D, P |
| `verdicts.tsv`, `deviations.tsv`, `job_walls.tsv` | per target row; deviations (D-154); wall times |
| `videos.toml` | video names, release URLs, sha256 |

The raw per-run tracks (≈ 700 runs × 10⁴ rows) go to the batch's immutable pre-release with
the videos, not into git (memory: full-run artifacts; immutable releases).

### 5.2 Docs

- **Reproduction page** `lib/PottsModels/reproductions/14_fortuna.jl`, in page 15's order:
  model code first; a minimal run (R = 10, 2000 MCS); then results against the paper
  (Fig 5, Fig 6 map, Fig 7 collapse, Table 2, Fig 9, Fig 11), each as one plot or table;
  the videos; a verdict summary; deviations. Protocol, every verdict, the §3 table and
  provenance go in collapsed `<details>` blocks (memory: digestible model pages).
- **Model page** `docs/models/fortuna.jl` with `docs/models/src/fortuna_model.jl`, and a
  paper run `docs/paper_runs/fortuna_migration.jl` (as `akeeb_invasion.jl`).
- **Videos.** Color by compartment kind, as 14a Fig 4 does: cytoplasm violet,
  lamellipodium green, nucleus yellow (p.2807 caption). This is the "by phenotype" form of
  per-cell categorical color, since one run has one cell. No outlines (D-156). Three views
  per frame, as Fig 4: top view (`OrthogonalSlice` at z = 2), a 3D `pottsvolume`, and a
  sagittal `OrthogonalSlice` through the nucleus.
  1. Onset (Fig 4): R = 15, φ_l = 0.10, λ_F = 175, MCS 0–5000, a frame every 25 MCS.
  2. Migration: the same run over 10⁵ MCS, a frame every 500 MCS, with the nucleus track.
  3. The Fig 6 grid: 20 panels of animated nucleus tracks (10 per panel), background
     colored by our regime, one cell morphology per panel.
  Snapshots of σ are saved every 25 or 500 MCS for these runs only.
- d2 adds a Π_CN−N section to the same page. d3 gets its own section or page.

---

## 6. Open questions (each with a recommendation)

**Status 2026-10-14:** the spec owner has ruled on all six. Q1 and Q3–Q6 are accepted as recommended; Q2 is amended (below).

| # | Question | Recommendation |
|---|---|---|
| Q1 | Detachment: the code stops a run at zero CYTO–FRONT contact at a 50-MCS sample (spec l.161); `@terminate` is not merged; the paper gives no rule (spec l.267) | Classify after the run, as §4.3: face contact 0 at any sample after MCS 10 detaches a replicate; ≥ 5 of 10 makes a detachment set. Record deaths as info |
| Q2 | 14b records every MCS (14b p.6) | **Ruled 2026-10-14 (spec owner):** record every 10 MCS in general, but every MCS for the 14b-targeted sets. 14b's lag Δτ_opt·P can be only a few MCS, and 10-MCS sampling would alias it. One deviation row, for the non-14b sets only |
| Q3 | MSD window: the whole track or after a warm-up (14a states none; 14b waits 1000 MCS) | 14a: the whole track (14a-S1 p.10 count 1999). 14b: 1000-MCS warm-up |
| Q4 | c is unstated | c = 0.1 with the S-cal check (§4.2); grid only if B2 fails |
| Q5 | 14c's Switch needs a 100-MCS window of a cell quantity; `Pre(x, k)` on cell variables waits for R12 (P6.7b) | Keep d3 behind R12, as ROADMAP orders. If the maintainer wants 14c earlier: the paper runs one cell, so a model-scope variable with `Pre(φ_frac, 100)` is exact today **[inference; model-scope lags are supported, `src/lower.jl:305`]** |
| Q6 | 14c Eq 5 as printed opposes protrusion for λ > 0 (spec l.318) | Use the protrusion-favoring sign. 14c's own text says the term "favors Lamel growth over Medium" (14c p.6), and 14a Eq 7 has that sign. Not code over paper: the paper's text decides |

Everything else follows existing rulings: J_cyto–lam = 20, fixed targets, the ball, the
6³ nucleus, the PDE source, both drive directions, the lid, V = (4π/3)R³.

---

## 7. Risks

1. **The paper rules may not give Fig 6's regimes.** Three ruled choices differ from the
   code: J_cyto–lam = 20 (code 10), conversion that re-fires whenever V₃ < φ_l·V (the code
   stops for good once its target grows to φ_l·V, spec l.226), and fixed targets (the code
   moves targets). Re-firing may hold the lamellipodium at its target and change detachment.
   **Pre-registered response:** if B3 or B4 fails, run one reverse-engineering screen (memory:
   reverse-engineering first) at R = 15 over the ruled switches only: J_cyto–lam ∈ {20, 10}
   and the conversion law (paper, or the code's variant, spec l.631, built only then). The
   screen explains the failure; it does not retune λ_F, c or J to fit. The default stays
   ruled. The finding goes to the PI sheet (D-155) and the deviations table.
2. **S resolution.** The `:paper` fit may not resolve S = 0.02 at Fortuna's sampling. §4.5
   catches this before any FULL fit, and B6 then gates on `:lsq` alone.
3. **Table 2 is noisy.** P is not monotone in λ_F (spec l.460), and three R = 15 rows are
   internally inconsistent (spec l.496). Per-row verdicts and B5′ keep one bad row from
   hiding the others.
4. **Cost.** The estimate has no 3D `NeighborOrder(4)` benchmark behind it. Q6 measures it
   first. At 60 ns per attempt FULL takes about 40 h; the launch order (§4.4) puts the
   headline sets first.
5. **Nucleus start.** The 216-site nucleus grows to 628–5027 sites. If it pinches through
   the cytoplasm or touches the medium early, the onset video and B1 suffer. Q1 and Q5
   detect it at R = 10; the response is a reported deviation, not a new start.
6. **The lid.** J(medium, lid) = −20 is code-only (spec l.186). A lamellipodium that
   reaches z = L_z − 1 would meet it. 14a-nH added a lid source there (spec l.279); we do
   not. Report the count of runs whose lamellipodium touches the lid.

---

## 8. Contradictions between spec 14 / the sketch and the merged API

| Spec or sketch | Merged API | Effect on P6.5d |
|---|---|---|
| `@sweep Metropolis(; …, field_solver = …)` (sketch l.112) | `field_solver` is a `PottsProblem` keyword (error text, `src/vocabulary.jl:1374`, feat/p6-5a2) **[probe]** | pass it to `PottsProblem` |
| `Spheres`, `Plane`, `Tiling`, hand `cluster` (sketch l.122–127) | `Objects(Interior(Sphere))`, `Fill`, `Group` (D-244) | §3 |
| `@terminate` on detachment; `contact(c, n)` (sketch l.99–101) | neither merged | post-run classification with an `integral` observable (§4.3) |
| `p = max(0, …)`; `V_target[to] = …` written on creation (sketch l.95–96) | runtime clamp to [0, 1]; E1 defaults set the new slot's target (D-233) | no clamp and no write in the block |
| `Pre(φ_frac, 100)` on a cell variable (sketch l.148) | refused (`src/lower.jl:163`) | d3 waits (§6 Q5) |
| The 0/0 = NaN rationale (spec l.626) | holds only when the medium's default target is 0. With a nonzero medium branch, `V_target[to]` of an absent lamellipodium reads that value instead (`p6_5b_convert.jl:123–134`) | keep the parameter form; S6 pins the φ_l = 0 NaN path |
