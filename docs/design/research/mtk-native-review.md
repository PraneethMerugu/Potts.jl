> **Review of `mtk-native-investigation.md`** (coordinator, 2026-09-30). Probes were in `/tmp/mtkrev/` (r1–r11, not kept). Outcome ratified by the maintainer: P6.0o adopted; P6.0k2 F7 added.

# Adversarial review: `docs/design/research/mtk-native-investigation.md`

Reviewer, 2026-09-30. Main checkout at `monorepo` 1092ada. Pins: MTKBase 1.77.0 (`IwLYy`),
Symbolics 7.41.1 (`74GkI`), MTK 11.45.1 in `test/`. Nothing in the repo was edited and
nothing ran on Metal. The reviewer's probes are in `/tmp/mtkrev/` (`r1`–`r11`). The original
probes p0, p1, p3, p4, p5 and p2 §1–4 were rerun. p2 §6 was rerun in split form as `r4`.

## 0. Bottom line

The headline verdict stands: full MTK-native is out of reach, Level B is rejected, and
Level C is rejected. Three of the report's supporting facts are wrong or mis-attributed:
- **The 225 s build time is not RHS codegen.** About 99 % of it (217 s against 1.4 s) is MTK building the
  `InitializationProblem`. With `build_initializeprob = false` the 64² `ODEProblem` builds
  in 1.4 s and its first RHS call compiles in 12.7 s (`r4`).
- **`compose` does not drop metadata.** It keeps the payload on the subsystem. Flattening
  is what discards it (`r10`).
- **`resize!` does not leave `sol[V]` stale.** `sol[V]` stays correct; the new entry is
  simply unnamed (`r5`).

The report also missed a cost of item 1. Subtyping `AbstractSystem` puts MTK's
`getproperty` in charge of `sys.field`. That breaks every `sys.kinds`, `sys.lattice` and
similar access in Potts, about 281 sites (`r1`).

Of the five level-A items:
- **Adopt one**, item 1, which D-075 has already decided. It gets its own row and a
  corrected cost.
- **Defer two:** item 4 (initialization) and item 5 (`PDESystem`).
- **Reject two:** item 2 (model ODEs through `mtkcompile`) and item 3 (`@discrete_events`
  as `SymbolicDiscreteCallback`s).

The review also found a real defect the report did not name. Potts **silently ignores** a
component `System`'s `initialization_eqs` and `discrete_events` (`r8`). It needs a small
fix whatever is decided about item 4.

## 1. Verdict per claim

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1a | `JumpType` is a closed union | **Verified** | `MTKB/src/utils.jl:1672`: `const JumpType = Union{VariableRateJump, ConstantRateJump, MassActionJump}`; p0 rerun |
| 1b | `Affect` is a closed union | **Verified** | `MTKB/src/systems/callbacks.jl:353`: `const Affect = Union{AffectSystem, ImperativeAffect}`; p0 rerun |
| 2a | A symbolic array length throws | **Verified** | `@variables W(t)[1:n]` gives `TypeError: non-boolean (Num)` (`r9`, p2 §4). The error comes from Julia's range construction, not from a deliberate MTK check. The conclusion holds either way |
| 2b | After `resize!`, `sol[V]` is stale or SII is "silently desynchronised" | **Refuted as framed** | `u` has 9 entries, `sol[V][end]` equals `u[end][1:8]`, and `u[end][9] = 42.0` (`r5`). `V` was declared with 8 elements, so `sol[V]` is correct. The accurate statement: "a resized entry has no symbol and cannot be addressed through SII." Blocker 2 still stands for that reason |
| 3 | `ODEProblem` takes 2 s at 16², 14 s at 32² and 225 s at 64² | **Numbers verified, attribution refuted** | Default `ODEProblem`: 1.4 s, 16.7 s and 217 s (`r4`). With `build_initializeprob = false`: 0.15 s, 0.16 s and 1.39 s, plus a first RHS call of 0.33 s, 2.3 s and 12.7 s. So the cost is mostly MTK's initialization-problem construction, not scalarized RHS codegen. §4.3's table header "ODEProblem (codegen)" and the §7.1 gate ("if 64² drops below ~1 s, revisit") measure the wrong thing. MTK #5139 (unscalarized arrays) would not necessarily fix the 217 s |
| 4a | Symbolics 7.41.1 emits a lazy `if` for `ifelse` | **Verified only for `build_function` with `cse = false` (its default)** | p4 rerun. With `cse = true` (`r2`), `NaNMath.sqrt(x)` and `(y+1)^3` are hoisted out of the branch, and the exponent is bound to a variable and called through `NaNMath.pow`. MTK's own `generate_rhs` output is CSE'd and hoists `NaNMath.sqrt` out of the `if` too (`r3`). D-014 amended already says SymbolicUtils' CSE "hoists work out of a lazy `ifelse`", and that remains true |
| 4b | Symbolics 7.41.1 keeps Float32 literals | **Verified** | `0.5f0` and `0.1f0` survive in both `build_function` and MTK codegen (p4, `r3`) |
| 4c | "No device target" as a decisive D-014 reason | **Weak** | `JuliaTarget` output is plain Julia and could run in a KernelAbstractions kernel; DiffEqGPU's `EnsembleGPUKernel` runs MTK-generated functions on the GPU. The decisive reasons are loops, gathers, claims, status words and diagnostics. `build_function.jl:4-7, 34` (Julia/Stan/C/MATLAB targets) is cited correctly |
| 5 | `compose` drops metadata | **Refuted as framed** | In `compose(other, [sys])` the outer system never had the payload. The subsystem keeps it (`getmetadata(only(get_systems(c)), PottsContent)` is `true`), and `compose(sys, [other])` keeps it too. Only `mtkcompile` of the composed system loses it (`r10`). That is undefined merge behaviour, not a bug. D-039 is not "reinforced" by this |
| 6 | AbstractSystem contract probe | **Verified, but incomplete** | p1 rerun gives the same failure sequence: `eqs`, `ps`, then `namespacing`, `gui_metadata`, and no `mtkcompile` method. **Missed:** `Base.getproperty(::AbstractSystem, ::Symbol)` (`MTKB/src/systems/abstractsystem.jl:1087-1094`) routes through `getvar`. `s.lattice` on a plain field throws "variable lattice does not exist", and so does `s.observed` (`r1`). Potts reads `sys.<field>` 281 times in `src`/`ext`/`lib` |
| 7 | The `ImperativeAffect` array-`observed` bug | **Verified** | `observed = (; V = V)` on an array unknown fails with "Observed equation (V(t))[1:8] in affect refers to missing variable(s)". It fails under full MTK 11.45.1 (`r5`) and under MTKBase 1.77.0 alone (`r11`). `modified = (; V = V)` works, and `observed = (; v1 = V[1])` works. The asymmetry is a genuine bug |
| — | `PottsSystem` is not `<: AbstractSystem` (`src/system.jl:32`); only `@components` reach `mtkcompile` (`src/components.jl:91`) | **Verified** | Note that AUTHORING.md:50 and INTERNALS §2.1 already describe `PottsSystem <: AbstractSystem` as fact. This is a docs/code divergence |
| — | The sweep-as-event probe and the callable-parameter probe | **Verified** | p3: 2 sweeps, and the undeclared write is rejected. p5: `du = [17.0]` |
| — | Web items (#5139, MOL #695, PRs #5131/#5051/#5017, Discourse 102324) | **Unverifiable here** (offline) | — |

## 2. Verdict per level-A item

### Item 4 (report §5.1 #1): MTK initialization engine per entity — **defer**

None of the 12 reference models has an entity-local *nonlinear* initialization. Every
initialization in the specs reads the lattice or draws:
- `A ~ volume` (04);
- `V_target ~ volume` (07);
- Akeeb's `cue ~ position…` and `rand()` clocks (10);
- steady fields `0 ~ D_V Δ(V) …` (05, 07).

MTK's engine cannot see `volume` or `position` unless they are passed in as parameters.
These are exactly the forms that D-075 R17 (P6.4a) and review S9 assigned to the `at_init`
phase. Spec 11's Ramis-Conde ODE does not say it starts at a steady state.

D-077 G8 already decided not to run MTK initialization for discrete components.

Measured cost if adopted (`r7`, full MTK, 3-state component, cold):
- `mtkcompile`: 0.5 s;
- `InitializationProblem` build: 1.0 s;
- first solve: 0.4 s;
- then 44–54 µs and 2.8 KB per cell, about 50 ms for 1000 cells, on the host only.

The cost is acceptable. But adopting it would need:
- a NonlinearSolve extension;
- a rule for daughters born after t0, where MTK initialization never runs;
- an amendment to ratified D-075 R17 text.

**Should R17 absorb it?** No. R17's own scope is right as it stands.

**Trigger to reopen:** the first reference model or sibling that needs a component started
at its own steady state. Acceptance conditions for that future row:
- build time grows by at most 2 s per component class, cold;
- per-entity initialization costs at most 100 µs per cell and at most 0.2 s for 1000 cells;
- zero effect on the warm MCS (the gate is unchanged);
- daughters follow a stated rule (inherit, or re-solve per birth, costed);
- models without component `initialization_eqs` generate byte-identical code.

The defect behind it is real and fixed now, by the new row in §3 (P6.0k2 F7).

### Item 2 (report §5.1 #2): model cell and model ODEs as an MTK `System` through `mtkcompile` — **reject**

`@equations` accepts only explicit `D(x) ~ rhs` (`src/compile.jl:262-265`), and the right
side is full of Potts built-ins (`volume`, `kind`, gathers, `Δ`) that MTK can only treat as
opaque. `mtkcompile` of explicit ODEs with no algebraic equations removes nothing, and
Potts already has `@observed`. DAEs are deferred by D-038.

Users who want MTK to simplify cell dynamics already have the route: `@components`
(D-038), plus clocked components (D-077, P6.0k). Adding a second route would:
- add an `mtkcompile` to every model build (≈0.5 s cold for a 3-state system, `r7`);
- churn the generated code and D-016 fingerprints;
- risk Float64 and CSE artefacts against D-014 and D-047;
- give no reference model a new capability.

D-038 wording: unchanged.

### Item 3 (report §5.1 #3): `@discrete_events`/`@terminate` stored as `SymbolicDiscreteCallback`s — **reject as a separate item**

Construction is cheap: 0.14 s cold and 0.6 ms warm (`r6`). But
`ModelingToolkitBase.conditions`, `affects` and `AffectSystem` are **not public** (`r6`).
Potts would have to read the stored objects through internals, which conflicts with D-064's
ExplicitImports check that qualified accesses are public. The gain is nominal (`show` and
inspection).

P6.4c already lands `@discrete_events` in MTK syntax mapped to SciMLBase callbacks (D-075
R3, §0.1 row). The useful piece, honouring or rejecting a *component's* own
`discrete_events`, goes into the new row in §3.

### Item 1 (report §5.1 #4): `PottsSystem <: AbstractSystem` — **adopt (new row P6.0o); the report's cost is wrong**

This is already decided: D-075 §0.1 ("Same lifecycle"), AUTHORING.md:50 and INTERNALS §2.1
all describe it, and the code does not do it. The divergence has to close, and the decided
direction is to subtype.

The report's "small, no decision change" understates the cost:
- MTK's `getproperty` shadows fields, so all 281 `sys.<field>` reads must move to
  `getfield` or accessors (`r1`).
- The field names `observed` and `name` collide with MTK's meaning, and Potts' `observed`
  is `Vector{ObservedEq}`, not `Vector{Equation}`.
- `extend(::PottsSystem, ::System)` and `compose` would fall through to MTK's generic
  methods.

There is still no benefit to any reference model. The gains are the SciML-native claim,
MTK's `sys.x` symbolic access, `getmetadata`, and MTK's `show`. That is enough to justify
doing it, as D-075 §0.1 decided, but not urgently.

Schedule it before P6.4a, so that R17's `initialization_eqs`, `initial_conditions` and
`guesses` land on the mirrored field names.

### Item 5 (report §5.1 #5): `PDESystem` as field input — **defer**

No consumer exists. MethodOfLines is already an oracle extension (D-075 §0.1). Its premise,
the scaling numbers, is mis-attributed (claim 3).

### The gate (re-run the 64² probe on each MTK release) — **reject as a standing ROADMAP row**

It measures initialization-problem build, not array codegen. If kept, it should stay as a
note in the research doc. Use the split `r4` probe and report three numbers: build without
initialization, first RHS call, and build with initialization.

## 3. Rows and acceptance

**P6.0k2 — add F7** (same write set, `src/components.jl`). "An `@components` MTK `System`
whose compiled form has a non-empty `initialization_eqs`, `discrete_events`,
`continuous_events`, `jumps`, or bindings that touch a coupled parameter is rejected at
`mtkcompile` with a message naming the component and the field. MTK `guesses` are ignored,
as documented."

- Accept: each case has a negative test. `r8` is the reproducer: today `z ~ 5y` is
  ignored and `c₊z_c = 0.0`.
- Accept: every existing model and fixture generates byte-identical code (same D-016
  fingerprint).
- Accept: build time and time to first MCS are unchanged within noise, by
  `benchmark/graner.jl` and the D-047 workload.

**P6.0o (new, step 0, before P6.4a) — `PottsSystem <: ModelingToolkitBase.AbstractSystem`
(D-075 §0.1; AUTHORING §1; INTERNALS §2.1).**
- Accept: `PottsSystem` mirrors the `System` field names that the MTK accessors it supports
  read. It has an all-fields constructor taking `checks`, sets `namespacing`, and defines
  Potts-owned `complete`, `extend` and `show`.
- Accept: every internal `sys.<field>` read uses `getfield` or an accessor. `sys.x`
  returns the namespaced symbolic, as in MTK.
- Accept: `equations`, `unknowns`, `parameters`, `observed`, `nameof`, `getmetadata` and
  `setmetadata` each return a documented value or throw a clear error. None of them returns
  a silently partial view; for example, `unknowns` either documents that it excludes the
  lattice, or throws.
- Accept: `compose` (D-039), `ODEProblem`/`JumpProblem` and `extend` with a plain `System`
  throw clear errors.
- Accept: Aqua ambiguities and piracy checks, JET, and ExplicitImports are clean.
- Accept: every PottsModels model and test fixture generates byte-identical code (same
  fingerprint).
- Latency acceptance:
  - `@potts_model` construction, `mtkcompile` and `PottsProblem` build time each within
    +5 % of the pre-change baseline on the five gate models;
  - fresh-process time to first MCS (`benchmark/graner.jl`, and the D-047 target under
    15 s) within +5 %;
  - the warm-MCS gate unchanged.

No row for items 2, 3 and 5. Item 4 gets no row until its trigger fires.

## 4. Proposed amendments

| Text | Status | Wording |
|---|---|---|
| D-075 §3.2 / R17 (initialization) | **Unchanged** | Item 4 is deferred. Optional *clarify*: "MTK component `initialization_eqs` are rejected (P6.0k2 F7) until a consumer needs per-entity MTK initialization." |
| D-075 §0.1 `PottsSystem` row | **Unchanged** | Already says `AbstractSystem`. The contract details are acceptance text on P6.0o, not decision text. Drop the report's "D-039 reinforced by `compose` dropping metadata": it is refuted |
| D-014 rationale | **Unchanged (optional clarify)** | If edited at all, replace "a lazy `ifelse`" with: "a lazy `ifelse` *under CSE*: Symbolics 7.41 `build_function(cse = false)` emits a lazy `if` and keeps `T` literals, but CSE'd output (`cse = true`, and MTK's codegen) hoists branch work and binds exponents (`/tmp/mtkrev/r2`, `r3`)." Do not drop the reason |
| D-038 | **Unchanged** | Item 2 is rejected |
| AUTHORING.md:50, INTERNALS §2.1 | **Clarify** | "planned (P6.0o); not yet" until P6.0o merges |

Nothing here amends a decision. P6.0o implements D-075 §0.1, and P6.0k2 F7 is a bug fix.
The two new rows still go to the maintainer as ROADMAP additions.

## 5. Upstream proposals (none posted)

| # | Report proposal | Verdict |
|---|---|---|
| 1 | Document the third-party `AbstractSystem` contract | **Well-founded.** Also list the `getproperty` → `getvar` takeover of plain fields (`r1`) |
| 2 | Keep metadata through `compose` | **Not well-founded.** `compose` keeps it on the subsystem (`r10`). At most, ask for the flattening merge rule to be documented |
| 3 | Public problem-compatibility hook | **Not needed.** It only matters for Level B, which is rejected |
| 4 | Array `observed` in `ImperativeAffect` | **Well-founded bug.** It reproduces on MTKBase 1.77.0 alone (`r11`). Re-check on the newest MTKBase (1.77.2 is in the depot) before filing. Potts does not depend on it |
| 5 | Comment on MTK #5139 with the 64² numbers | **Not as written.** The numbers measure `InitializationProblem` build. A separate, better-founded issue: "`ODEProblem` with a fully specified `u0` and no initialization equations takes 217 s to build at 4096 unknowns, against 1.4 s with `build_initializeprob = false`" (`r4`). Re-measure on the newest release first |
| 6 | Discourse RFC for a population dimension | **Low value now.** No consumer, and the evidence is a 2023 maintainer statement |

## 6. Reviewer probes

All are in `/tmp/mtkrev/`:
- `r1_getprop.jl`: field shadowing.
- `r2_cse.jl`: `build_function` with and without CSE.
- `r3_mtkcodegen.jl`: MTK `generate_rhs` output.
- `r4_scale.jl`: split timing, with output in `r4_out.txt` and `r4_out64.txt`.
- `r5_event.jl`: array `observed` and the `resize!` check.
- `r6_sdc.jl`: `SymbolicDiscreteCallback` cost and public API.
- `r7_init.jl`: per-entity initialization cost at 1000 cells.
- `r8_compinit.jl`: Potts silently ignoring component initialization and events.
- `r9_p2_head.jl`: p2 §1–4 rerun.
- `r10_compose.jl`: where the metadata goes under `compose`.
- `r11_obs_mtkb.jl`: the array-`observed` bug on MTKBase alone.
