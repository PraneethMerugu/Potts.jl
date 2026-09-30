# 08 — FBCA (Graudenzi, Maspero, Damiani 2019/2020): target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** a 2D CPM in which every cell runs flux balance analysis (FBA) each MCS. The
  LP's biomass flux accumulates as biomass B, which sets the target area (A_target = F·B).
  Cells divide at 50 sites along a random horizontal or vertical plane. 08a supplies
  nutrients as a constant supply per site; 08b adds nutrient fields that spread by
  neighbourhood averaging (Eq 6), and cells that take up and secrete into them.
- **Papers:** 08a Graudenzi, Maspero, Damiani, *J. Cell. Automata* **15**:75–95 (2019/2020);
  08b Maspero et al., *Fundam. Inform.* **171**:279–295 (2020). No code was released.
- **Metabolic model:** Di Filippo 2016 supplementary `mmc1.xls` (X5, D-067; flagged:
  274 × 252 against the papers' 272 × 240).
- **Spec:** [`../08_fbca.md`](../08_fbca.md). Decisions X1–X5 are in README §4.5 and §4.12.
  Build step: ROADMAP P6.12.
- **Date:** 2026-09-30.

Tags: `# [R#]` marks a planned roadmap feature and `# [NEW]` marks a feature that is not on
the roadmap. An untagged line uses syntax that exists today. `[verify]` marks existing
syntax that I believe works in that position but have not run.

The base model is **08a SC1-A** (Table 1, SC1 column). The **08b** tissue model is an
`@extend`. SC1-B, SC2 and the closed "chemostat" are variants (§5).

## 1. Sketch

```julia
using Potts, COBREXA, HiGHS              # loading COBREXA + HiGHS activates Potts' FBA extension (D-030)  [R15]

hmr = load_model("docs/references/supplementary/08_DiFilippo2016_mmc1.json")   # X5; .xls converted once  [NEW]
fba = FluxBalance(hmr; objective = "biomass_synthesis",   # max v_b s.t. S v = 0, v_L ≤ v ≤ v_U (08 §2.1 Eq 2)  [R15]
    optimizer = HiGHS.Optimizer, warm_start = true,       # README §4.12: warm-start the per-cell LPs
    tiebreak = Parsimonious(),                            # X1: pFBA, a deterministic tie-break
    exchanges = (O2 = "Ex_O2[s]", glc = "Ex_glucose[s]", gln = "Ex_glutamine[s]",
                 lac = "Ex_L-lactate[s]"))                # Arg: mmc1 has no arginine[s] (§4 item 3)

@potts_model FBCA begin
    @structural_parameters begin
        lattice = (100, 155)                # w × h = 100 × 155, SC1 (08 §3; 620 cells of 5 × 5)
        boundary = (Periodic(), Closed())   # crypt rolled out; which axis wraps is UNSPECIFIED (08 §7 item 2)
        open_bottom = true                  # cells reaching the lower edge are deleted (08 §2.1)
        density_limited = false             # SC1: γ = 1; SC2 and 08b: density factor (08 §2.1)
    end
    @kinds medium oxidative fermentative    # empty space; SC1 type 1 (takes up lactate), type 2 (secretes it)
    @parameters begin
        T = 3.0                             # k_B T (08 §3, Table 1)
        λ = 1.0                             # SC1; SC2 uses 4 (Table 1)
        F = 0.02                            # area per unit biomass, A_target = F·B (Table 1; 08b φ = 1/F)
        A_mitosis = 50.0                    # division area (Table 1, 08a p.82)
        gln_cell = 20.0                     # Gln supplied per cell in SC1 (Table 1)
        J[kind, kind] = [0.0 0.5 0.5; 0.5 4.0 4.0; 0.5 4.0 4.0]   # SC1: J(A,A) = J(A,B) = 4, J(cell, empty) = 0.5
    end
    @variables begin
        B(cell) = 1250.0                    # biomass, pg (08 §2.1 IC; ρ = 1/F)
        clone(cell) = 0.0                   # lineage: copied to daughters (V08a-3)
        born(cell) = 0.0                    # MCS of the cell's own division (V08a-4)
        cycle(cell) = 0.0                   # duplication time at the last division
        O2(site) = 6.0                      # fmol per site (Table 1, SC1); constant supply in 08a
        glc(site) = 0.5
        lac(site) = 0.5
    end
    @lattice Lattice(lattice; boundary, neighborhood = Moore(1))   # Moore N = 1 (Table 1)
    @relations proposal = Moore(1)                                  # l′ from N(l) (Eq 4)

    @components cells(oxidative, fermentative) fba = fba            # one LP per cell, on the host   [R15]
    @equations begin                                                # U_j = Σ_{l∈C(σ)} [M_j^l] (08a p.83)
        fba.uptake_O2 ~ integral(O2)
        fba.uptake_glc ~ integral(glc)
        fba.uptake_gln ~ gln_cell                                   # per cell, not per site (Table 1)
        fba.uptake_lac ~ ifelse(kind == oxidative, integral(lac), 0.0)   # type 1 may take up lactate …
        fba.secrete_lac ~ ifelse(kind == fermentative, Inf, 0.0)         # … type 2 may only secrete it
    end

    @energy begin
        cells(oxidative, fermentative) => λ * (volume - F * B)^2     # Eq 5: λ Σ (|C| − A_target(B))²
        contacts => J[kind, kind′]                                   # Eq 5: ½ Σ over ordered pairs = once per pair
    end
    ρ = B / volume                                                   # 08b p.283; 08a leaves ρ undefined (§7 item 3)
    γ = density_limited ? ifelse(F * ρ <= 1, 1.0, 1 - min(1, 2 * (F * ρ - 1))^2) : 1.0   # 08a p.87; 08b Eq 3
    @before_mcs B ~ Pre(B) + γ * fba.biomass                         # B += γ v_b, after the LP (08b p.282)  [R15] [R5]

    @divide cells(oxidative, fermentative) when = volume >= A_mitosis,
        along = rand(((1.0, 0.0), (0.0, 1.0))),                      # horizontal or vertical, 50/50 (08a p.82)  [R3] [NEW]
        B => Split(),                                                # X4: halve the biomass
        cycle => mcs - born, born => mcs                             # rule order matters [verify]
    if open_bottom
        @retire cells(oxidative, fermentative) when = integral(position[2] == 1) > 0   # touches y = 1   [R3]
    end

    @observed begin
        n_ox ~ count(true for c in cells(oxidative))                 # Fig 2E
        n_fe ~ count(true for c in cells(fermentative))
        v_lac(cell) ~ fba.flux_lac                                   # lactate phenotype (08b Figs 6–7)   [R15]
    end
    @sweep Metropolis(; temperature = T, attempts = 4)               # k = 4 attempts per site per MCS   [R10]
end

@named fbca = FBCA()
sys  = mtkcompile(fbca)
op   = layout(Tiling((5, 5); kinds = [:oxidative, :fermentative]), sys)   # 20 × 31 = 620; x-neighbours alternate
prob = PottsProblem(sys, [op; :clone => collect(1.0:620.0)], (0, 2000); seed = 1)
sol  = solve(prob, SequentialCPM(); saveat = 0:10:2000)
ens  = EnsembleProblem(prob; trajectories = 20)                      # 20 runs (08 §3)
o2B  = [x <= 25 || x > 75 ? 0.5 : 6.0 for x in 1:100, y in 1:155]    # SC1-B: 2 × 3875 sites at 0.5 (layout derived)
probB = PottsProblem(sys, [op; :clone => collect(1.0:620.0), :O2 => o2B], (0, 2000); seed = 1)

# --- 08b: nutrient fields spread by Eq 6, conservative exchange, closed tissue ---------------------
@potts_model FBCADiffusion begin
    @structural_parameters begin
        permeable = true                    # both cases are run (08b p.289)
    end
    @extend T, λ, B, O2, glc, lac, fba =
        base = FBCA(; lattice = (175, 115), boundary = Closed(), open_bottom = false,   # tissue (08 §2.2)
                    density_limited = true, J = [0.0 2.0 2.0; 2.0 8.0 8.0; 2.0 8.0 8.0]) # J(c,c) = 8, J(c,E) = 2
    # λ, T, attempts per MCS, initial fields: "as in [18]" (ACRI 2018), UNSPECIFIED (08 §3, §7 item 12)
    @parameters begin
        D_O2 = 1.0; D_glc = 1.0; D_gln = 1.0; D_lac = 1.0    # Eq 6 D: UNSPECIFIED (08 §2.2; X3 as written)
        θ_starve = NaN                                       # starvation rule UNSPECIFIED (08 §2.2, §7 item 10)
    end
    @variables begin
        gln(site) = 0.0                     # a field in 08b; its initial value is UNSPECIFIED (08 §2.2)
        vessel(site) = false                # sources: 11² top/bottom, 9² ×3 centre, or 11 × 115 (08 §2.2)
    end
    sites_used = permeable ? cell_sites : outer_rim          # own sites (Fig 2D) or adjacent empty sites (Fig 2C)  [R15]
    @exchange cells(oxidative, fermentative) fba begin       # bound = Σ field over the sites; flux back ∝ field  [R15]
        O2 => fba.O2; glc => fba.glc; gln => fba.gln; lac => fba.lac
    end over = sites_used, order = Shuffled()                # X2: one cell at a time, write-back after each LP  [NEW order]
    if !permeable                                            # a cell entering an empty site pushes its nutrients
        @on_copy when = old == 0,                            # to the empty neighbours (08b p.287)   [NEW] [R5 footprint]
            spread((O2, glc, gln, lac), n for n in Moore(1)(target) if owner[n] == 0)
    end
    @retire cells(oxidative, fermentative) when = fba.biomass <= θ_starve   # the rule's form is a guess  [R3]
    # Eq 6: [N(l)] ← (D/|I|) Σ_{j∈I} [N(l_j)]; I = N ∪ l, or only its empty sites when impermeable
    avg(x, D) = D * mean(Pre(x)[n] for n in Moore(1; include_self = true)(site)
                         if permeable || owner[n] == 0)                                     # [verify] [NEW empty set]
    open_site = permeable | (owner == 0)
    @after_mcs begin                                         # step 6, after division (08b p.282)   [R5]
        O2  ~ ifelse(vessel, 100.0, ifelse(open_site, avg(O2, D_O2), Pre(O2)))   # clamps (08b p.286)
        glc ~ ifelse(vessel, 50.0, ifelse(open_site, avg(glc, D_glc), Pre(glc)))
        gln ~ ifelse(vessel, 50.0, ifelse(open_site, avg(gln, D_gln), Pre(gln)))
        lac ~ ifelse(open_site, avg(lac, D_lac), Pre(lac))                       # secretion only
    end
    # edge efflux "through a constant flux value": value UNSPECIFIED (08 §2.2), omitted
    # MCS order (08b p.282): FBA → biomass → starvation → sweep → division → Eq 6   [R5]
end
```

Proposed syntax used above:
- **`FluxBalance(model; objective, optimizer, tiebreak, warm_start, exchanges)`** (R15,
  through the COBREXA/JuMP extension). It builds a per-cell `CellOperator`. For each named
  exchange it has an input `uptake_x` and `secrete_x`, and it outputs `flux_x` and
  `biomass`. It is instantiated with `@components cells(k) fba = fba` and coupled with
  `@equations`, like a D-038 component.
- **`@exchange cells(k) op begin field => op.x … end over = …, order = …`** (R15
  `uptake`/`secrete` sugar). The bound is the sum of the field over a site set. After each
  LP, the exchange flux is written back over the same set, shared in proportion to the
  concentration (08b p.283).
- **`cell_sites` / `outer_rim`** (R15). Site sets relative to the cell.
- **`along = rand(tuple)`** [NEW]. A division plane drawn from a finite set.
- **`spread(fields, generator)`** [NEW]. An on-copy scatter of the target's values to the
  generated sites, with the target zeroed. Its footprint is the target's Moore(1).

## 2. Line → source

| Sketch line | Spec | Paper |
|---|---|---|
| `FluxBalance(hmr; objective = "biomass_synthesis")` | 08 §2.1 (Eqs 1–2), §1 (mmc1); X5 | 08a Eqs 1–2, p.78–79; 08b Eqs 1–2, p.283; Di Filippo 2016 mmc1 |
| `tiebreak = Parsimonious()` | 08 §6 G9 "Solver"; X1 | not in paper (§7 item 5) |
| `lattice = (100, 155)`, `Periodic` x, `Closed` y | 08 §2.1, §3, §7 item 2 | 08a Table 1 p.81; p.79 (cylinder) |
| `open_bottom` → `@retire` at y = 1 | 08 §2.1 "Death" (i) | 08a p.82; Fig 1 caption p.80 |
| kinds, lactate rules per kind | 08 §2.1 "Cell-type metabolic variants" | 08a p.83 |
| `T = 3`, `λ = 1`, `F = 0.02`, `A_mitosis = 50` | 08 §3 | 08a Table 1 p.81 |
| `J` (SC1) | 08 §3 | 08a Table 1 |
| `O2 = 6`, `glc = 0.5`, `lac = 0.5`, `gln_cell = 20` | 08 §2.1, §3 | 08a Table 1 |
| `fba.uptake_x ~ integral(x)` | 08 §2.1 "Exchange bounds"; §6 G9 | 08a p.83 |
| `cells => λ(volume − F·B)²` | 08 §2.1 Eq 5 | 08a Eq 5 p.82; 08b Eq 5 p.284 |
| `contacts => J[kind, kind′]` | 08 §2.1 Eq 5 | 08a Eq 5 (½ Σ over ordered pairs) |
| `γ`, `ρ = B/volume` | 08 §2.1 "density limit"; 08 §2.2 Eq 3 | 08a p.87; 08b Eq 3 p.283 |
| `B ~ Pre(B) + γ v_b` | 08 §2.2, §6 G9 "Outputs" | 08b Eq 3 p.283 |
| `@divide … A_mitosis`, random horizontal or vertical, `B => Split()` | 08 §2.1 "Division"; X4 | 08a p.82; 08b p.284 |
| `Tiling((5, 5))`, 620 cells, alternating, B = 1250 | 08 §2.1 "Initial conditions" | 08a p.83–84 |
| SC1-B `o2B` | 08 §2.1, §3 | 08a p.83 (2 × 3875 sites at 0.5; the lateral geometry is derived: 3875 = 25 × 155) |
| `attempts = 4` | 08 §2.1 "Update rule"; §6 G8 | 08a Table 1, Eq 4 |
| `trajectories = 20`, `(0, 2000)` | 08 §3 "runs" | 08a p.84, Fig 2 |
| 08b `lattice = (175, 115)`, closed, `J` 8/2 | 08 §2.2 table, §3 | 08b p.285 |
| `D_x`, Eq 6 `avg` with the permeable/impermeable mask | 08 §2.2 "Diffusion operator"; X3 | 08b Eq 6 p.284, p.287 |
| vessel clamps 100/50/50 | 08 §2.2 "Scenarios" | 08b p.286 |
| `@exchange … order = Shuffled()` | 08 §2.2 "Impermeable-case bookkeeping"; §6 G6; X2 | 08b p.287 |
| `sites_used` (own sites / outer rim) | 08 §2.2 FBA bullet | 08b p.286–287, Fig 2C/D |
| `@on_copy … spread(…)` | 08 §2.2; §6 G7 | 08b p.287 |
| starvation `@retire` | 08 §2.2 "Death" (UNSPECIFIED) | 08b p.282, p.285 |
| MCS order comment | 08 §2.2 "Explicit per-step algorithm"; §6 G15 | 08b p.282 |

## 3. Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds`, kind table `J`, cell/site variables, structural parameters, `if` sections | exists |
| `Lattice(…; boundary = (Periodic(), Closed()), neighborhood = Moore(1))`, `@relations proposal` | exists |
| `cells(k) => λ(volume − F·B)²` (a cell variable inside the target) | exists |
| `@before_mcs`/`@after_mcs` with `Pre`, `ifelse`, `min` | exists |
| `integral(x)` (cell scope) | exists (AUTHORING §12.3); `integral(position[2] == 1)` [verify: `position` inside the reduction kernel] |
| `@divide … B => Split(), x => expr` | exists; `mcs - born` in a daughter rule [verify rule order] |
| relation gather with a filter in a site update (Eq 6) | exists (D-042); `Pre(x)[n]` at a neighbour [verify] |
| `Tiling`, `layout`, `PottsProblem`, `EnsembleProblem`, `@observed`, population `count` | exists |
| `@components cells(k) name = …` with `@equations name.p ~ …` coupling | exists for MTK systems (D-038); **not** for an LP operator [R15] |
| `FluxBalance`, `CellOperator`, COBREXA/JuMP extension, pFBA, warm start | planned (R15, P6.12) |
| `@exchange` (`uptake`/`secrete` sugar), `cell_sites`/`outer_rim` rim reductions | planned (R15) |
| sequential shuffled operator pass with field write-back (X2) | planned in substance (R15 "sequential write-back", README §3 row R15); `order = Shuffled()` syntax **NEW** |
| `attempts = 4` | planned (R10, P6.4b) |
| `@retire` | planned (R3, P6.4c) |
| explicit phase order | planned (R5, P6.3b) |
| division plane drawn from a set (`along = rand(tuple)`) | gap listed in README §2.4 → R3; syntax **NEW** |
| copy-time scatter write to neighbours (`spread`) | gap listed in README §2.4 → R5 with a declared footprint; syntax **NEW** |
| folds with a default for an empty filtered set | **NEW** |
| `.xls` → COBREXA model conversion | **NEW** (host tooling, not DSL) |

## 4. Friction found

1. **An LP is not an MTK `System`.** Reusing `@components` + `@equations` for FBA is the
   most MTK-like coupling (inputs as component parameters, outputs as `fba.x`). But the
   compiler would then need to accept a non-`System` component (a `CellOperator`) and
   schedule it as a host phase, with no ODE integrator. The alternative is a separate
   `@operators` section.

   MTK's `OptimizationSystem` does not fit: the review notes that Optimization.jl has no
   LP warm start, and 600–1000 LPs per MCS need it. Either way, the operator's `order`
   (shuffled, sequential) and `every` are properties that D-038 components do not have.
2. **The metabolic model file.** `mmc1.xls` is the legacy BIFF `.xls` format. No
   maintained pure-Julia reader exists (XLSX.jl reads `.xlsx` only), and COBREXA reads
   SBML, JSON and MAT. A one-off conversion to JSON is needed, and it must be recorded
   with a sha in `codebases/SOURCES.md`. It must also resolve the two sheet
   inconsistencies (08 §1: the `ferrocytocrome` typo; `isopentenyl-pPP` used but not
   declared), and that resolution is itself a flagged deviation.
3. **mmc1 cannot express two 08a SC1 mechanisms as bounds.** Both were found with a
   string search of `mmc1.xls` and need confirmation with a real parser:
   - **No arginine exchange.** There is no `arginine[s]` metabolite and no `Ex_` reaction
     for arginine: the `[s]` exchanges found are O2, glucose, glutamine, glutamate,
     L/D-lactate, NH3, urea, folate, riboflavin, ornithine, putrescine, H, H2O and biomass;
     the rest are `[c]` sinks. So "Arg 20 fmol/cell" (Table 1) has nothing to bound.
   - **Lactate cannot be taken up.** The lactate transport is written irreversibly as
     `L-lactate[c] -> L-lactate[s]` (export only). So SC1's oxidative type ("may take up
     lactate") cannot take it up, whatever the exchange bound is.

   Either add reactions (an authors' variant; ask under §7 item 13) or record both as
   deviations. This affects V08a-1/-2 directly: the 11 % biomass advantage comes from the
   lactate rule.
4. **Division plane by draw.** `along` today takes a constant tuple, `RandomPlane()` or an
   axis rule (`codegen.jl` `_division_normal` lowers only numeric tuples). "Horizontal or
   vertical at random" is a draw from a 2-element set. `RandomPlane()` in 2D draws a
   uniform angle, which is a different law. Proposal: `along` accepts any cell-scope
   vector expression, including `rand(set)` from R3. CorePotts `normal` already takes any
   vector (README §2.4).
5. **Write-back must be serial, and it conflicts with one writer per target.** X2
   requires LP → field write → next cell in shuffled order. That is a serial host loop,
   not a batched `CellPhase`: the same shape as Fortuna's sequential `@convert`. One
   general "sequential shuffled host pass over cells" primitive would serve 08, 14 and
   R15 uptake.

   In the extension, `@exchange` sets the `fba.uptake_x` bounds that the base's
   `@equations` also set. The "one writer per target" rule will reject this unless
   `@extend` replacement covers equations written by a sugar. So redeclaration semantics
   are needed again (see 14 friction 3).
6. **Copy-time writes to the target's neighbours.** Today `@on_copy` writes only at the
   target, and AUTHORING §4 rejects source writes because of ΔH. Here the field is not in
   any energy, so ΔH is unaffected, but on the checkerboard the writes reach
   Moore(1)(target). That is a radius-2 footprint from the source, so the claims must
   widen, or the feature is sequential-only with a D-051 item 5 exception. The
   redistribution is also a "for each empty neighbour" loop with a count in the
   denominator. `@potts_model` has no macro-time `for` over statements, so four fields
   need four statements or a tuple-taking helper (`spread`).
7. **Eq 6 as a site update: three rough edges.**
   - **Reading `Pre(x)` at a neighbour** (a stencil in a synchronous update) is not
     documented. D-042 defines `Pre(x)` at the site, and bare `x` means the new value.
   - **An empty filtered neighbourhood.** When an impermeable empty site is surrounded
     by cells except itself, the mean has |I| = 1. But a fold whose filter excludes
     everything returns `sum/0 = NaN`. Folds need an `init`/default (NEW).
   - **Update or `FieldStep`?** It is an update, not a PDE, so no `field_solver` applies.
     The README maps G18 to R5 "conformance tests", which fits. The number of sweeps per
     MCS (UNSPECIFIED) would be `Every`/repeat, and there is no "repeat k times within one
     MCS" form for updates (NEW if ever needed).
8. **Rim site sets.** `integral(x)` covers only the cell's own sites. The impermeable
   uptake set, "empty sites adjacent to the perimeter", is an outer-rim reduction (R15).
   Neighbouring cells' rims overlap, so conservation holds only because the pass is
   sequential with write-back (friction 5). A batched per-cell reduction would
   double-count.
9. **Phase order.** 08b fixes the order FBA → biomass → starvation → sweep → division →
   Eq 6. Today lifecycle and after-MCS phases have no user-visible order relative to each
   other, or to a host operator. The operator must also run before the `@before_mcs`
   update that reads `fba.biomass`. R5's explicit order must include host operators,
   lifecycle rules and updates, not only fields.
10. **Attempts per MCS.** k = 4 flips per site per MCS, with one LP per MCS. Writing it as
    4 of our MCS would run the LP and the updates 4 times, so `Every(4)` on everything
    plus a time rescale would be needed. `attempts = 4` (R10) is the clean form.
11. **Duplication-time histogram.** Snapshots sample `cycle`, but the exact per-division
    distribution (V08a-4, V08a-7) needs every division event. An event log for division
    events (R16, or an `on_divide` observable) is not specified. The `cycle => mcs − born,
    born => mcs` idiom also relies on daughter rules reading the parent's pre-division
    `born`. The order of rules within one `@divide` is not documented.
12. **"Dominant type" therapy (SC2-B).** It is expressible as a population fold in a
    `@retire` gate (R3): `(mcs >= 2000) & (count(cells(kind)) is max) & (rand() < 0.5)`.
    But "the kind with the largest count" needs an argmax over kinds. That is writable
    with three `count`s and `ifelse` for three types, but not generically. An `argmax`
    population fold would be NEW.
13. **No friction:** the open lower boundary composes from `@retire` + `integral(position
    == edge) > 0`, with no boundary type needed. The density factor, the biomass → target
    link, lineage (`Copy()` default) and the SC1 tiling are all expressible today.

## 5. Open choices

| Choice | Default (spec) | Variant(s) |
|---|---|---|
| Metabolic model | `mmc1.xls`, flagged (X5, D-067) | the authors' 272 × 240 variant (unknown; §7 item 13) |
| Degenerate optima | pFBA (X1) | plain FBA; lexicographic |
| Scenario | 08a SC1-A | SC1-B (`o2B`); SC2 (λ = 4, J 4/8/2, 3 types with flux caps, O2 bands UNSPECIFIED, `density_limited = true`); SC2-B therapy |
| Periodic axis, top edge | x periodic, top closed | UNSPECIFIED (08 §7 item 2) |
| ρ in 08a | B / area | undefined in 08a (§7 item 3) |
| Biomass at division | halve (X4) | split by area |
| Exchange bound | U = Σ over sites (08a p.83) | flux ∝ concentration with a rate constant (08b p.283; §7 item 6) |
| 08a nutrient bookkeeping | static fields (constant supply) | per-MCS reset; SC2 lactate pool (rule UNSPECIFIED, §7 item 7) |
| Update order (08a) | 08b order: FBA → biomass → CPM | UNSPECIFIED in 08a |
| Impermeable FBA order | sequential, shuffled, write-back (X2) | parallel (not conservative) |
| Eq 6 | as written, non-conservative for D ≠ 1 (X3); D a calibration parameter | conservative averaging |
| 08b closed "chemostat" | reset every site to the lattice mean each step: `glc ~ mean(Pre(glc) for s in sites)` (a population fold over `sites`, exists) | – |
| Starvation death | rule UNSPECIFIED (08 §7 item 10) | v_b ≤ θ; infeasible LP; falling B |
| Edge efflux (08b) | omitted (UNSPECIFIED) | constant outflow per edge site |
| λ, T, attempts, initial fields (08b) | 08a values as placeholders | "as in [18]", ACRI 2018, not obtained (§7 item 12) |
| Missing Arg exchange / irreversible lactate transport in mmc1 | record as deviations | add the reactions (authors' variant) |
