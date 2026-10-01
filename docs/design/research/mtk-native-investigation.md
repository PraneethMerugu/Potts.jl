# Could Potts.jl be fully native to ModelingToolkit?

> **RESEARCH — not a decision.** 2026-09-30. Nothing in `src/`, `lib/` or DECISIONS changes.
> Scratch probes are in `/tmp/mtknative/` (`p0_env.jl` … `p5_callable.jl`), run read-only with
> `julia --project=.` (and `--project=test` for the one probe that needs a solver). Their
> output is quoted in §6.

> **Corrected after adversarial review (2026-09-30; review at `mtk-native-review.md`, probes `/tmp/mtkrev/r1–r11`, nothing run on Metal).** The headline holds: full MTK-nativeness is not achievable, and Levels B and C are rejected. Three supporting facts were wrong and one cost was missing; they are corrected inline (marked **[Corrected]**):
> 1. **Build time.** The 64² `ODEProblem` time reproduces (1.4 / 16.7 / 217 s at 16² / 32² / 64²), but ≈ 99 % of it is building the `InitializationProblem`. With `build_initializeprob = false` it is 0.15 / 0.16 / 1.39 s. Scalarized codegen is *not* the bottleneck at this size; the #5139 argument and the "re-run the 64² probe" gate rested on the mis-attribution.
> 2. **`compose`** keeps the metadata on the subsystem; only `mtkcompile` of the composed (flattened) system loses it. "D-039 reinforced" is withdrawn.
> 3. **`resize!`**: `sol[V]` stays correct (8 declared entries); the 9th entry simply has no symbol, so SII cannot address it. It is not a silent desync of existing variables.
> 4. **D-014 nuance.** Lazy `ifelse` holds only for `build_function(cse = false)`. With `cse = true`, and in MTK's `generate_rhs`, `NaNMath.sqrt` and powers are hoisted out of the branch, so the lazy-`ifelse` reason **stands under CSE**. "No device target" is weak (DiffEqGPU's `EnsembleGPUKernel` runs MTK code on GPUs); the decisive reasons are loops/gathers, claims and status words, and diagnostics.
> 5. **Missed cost.** `Base.getproperty(::AbstractSystem)` (MTKB `abstractsystem.jl:1087-1094`) takes over `sys.field`, so becoming an `AbstractSystem` breaks ≈ 281 `sys.<field>` reads in Potts.
>
> **Outcome (maintainer, 2026-09-30).** Of Level A, only `PottsSystem <: AbstractSystem` is adopted, as ROADMAP **P6.0o** (before P6.4a; byte-identical code and fingerprints; build, `mtkcompile`, `PottsProblem` and first-MCS latency within +5 % on the gate models). Model ODEs through `mtkcompile` and events as `SymbolicDiscreteCallback`s are rejected; per-entity MTK initialization and `PDESystem` input are deferred; the 64² gate is rejected. No decision is amended (D-014's text may be clarified to "lazy `ifelse` fails under CSE"). Separately, `@components` silently ignoring a component's initialization equations, events, jumps and coupled bindings is a defect, fixed as P6.0k2 F7. Upstream: only the `AbstractSystem` contract (incl. the `getproperty` takeover), the array-`observed` affect bug, and a new "`ODEProblem` initialization build is 217 s vs 1.4 s at 4096 unknowns" issue are well-founded; nothing is posted without the maintainer.

**Sources and versions.** All code citations refer to the versions pinned in the workspace
`Manifest.toml`:
- ModelingToolkitBase 1.77.0: `~/.julia/packages/ModelingToolkitBase/IwLYy`, written `MTKB/` below.
- ModelingToolkit 11.45.1: `ModelingToolkit/brqnn`, written `MTK/`. It is a weak dependency of
  Potts and a dependency of `test/`. It also carries SciCompDSL 1.0.4 in
  `MTK/lib/SciCompDSL`, and its `NEWS.md`.
- Symbolics 7.41.1: `Symbolics/74GkI`.

The slugs were derived with `Base.version_slug(uuid, SHA1(git-tree))`. Packages that are not
pinned were read from the newest copy in the depot:
- Catalyst 16.4.3 (`Catalyst/tAUzg`, compat MTKBase ≥ 1.46);
- PDEBase 0.1.36 (`PDEBase/rfV7U`);
- MethodOfLines 1.5.1 (`MethodOfLines/0m4Gg`).

Web sources were found by a read-only search pass on 2026-09-30. The two that carry the
argument (MTK #5139 and Discourse 102324) were re-fetched and checked by hand. The others are
labelled *(search, not re-verified)*.

---

## 1. Summary verdict

**"Fully native" is not achievable, now or within a year, and no upstream plan points
there.** Two of the three blockers are real limits of MTK's data model, not missing glue.
The first is the sweep: a Markov operator over an ownership lattice, with no equation
form. The second is per-cell state whose length changes during a solve. The third blocker
(lattice quantities) is half solved, and MTK's own roadmap is attacking it: whole-array,
unscalarized compilation, tracked in MTK #5139.

Evidence:

- **The sweep (blocker 1): no mechanism exists.** MTK's stochastic content is a closed
  `Union{VariableRateJump, ConstantRateJump, MassActionJump}` (`MTKB/src/utils.jl:1672`).
  Its event affects are a closed `Union{AffectSystem, ImperativeAffect}`
  (`MTKB/src/systems/callbacks.jl:353`). Neither union can carry a lattice copy-attempt
  operator symbolically.
  - The sweep *can* be smuggled in as an opaque Julia function: an `ImperativeAffect` with
    the lattice in `ctx`, or a callable parameter. Both ran in the probes (§6.3, §6.5).
  - MTK neither sees nor compiles such a function, so this is "native" in name only.
  - D-014 was partly re-checked. Symbolics 7.41.1 now emits a lazy `if` for `ifelse` and
    keeps `Float32` literals (§6.4), so two of D-014's five reasons are obsolete.
  - The decisive reasons stand. Symbolics cannot express gathers or loops over a
    neighbourhood, claims and status words, or Potts' scope diagnostics, and it has no
    KernelAbstractions or GPU target (`Symbolics/74GkI/src/build_function.jl:4-7, 34`:
    Julia, Stan, C and MATLAB only).
- **Ragged, growing per-cell state (blocker 2): partial.**
  - Potts' own layout is already "capacity plus inactive ids": ids live in `1:capacity`,
    and an id is free when its volume is zero (`lib/CorePotts/src/lifecycle.jl:7-10`;
    capacity at `src/problem.jl:342`). That is exactly MTK's officially suggested
    workaround: preallocate, then use activation parameters (Discourse 102324, 2023-08-01).
  - So *fixed-capacity* per-cell columns are expressible as array unknowns, and the
    probes show they work (§6.2).
  - What MTK cannot do is change that capacity during a solve. The array length must be
    concrete (`@variables W(t)[1:n]` with a symbolic `n` throws, §6.2).
  - A symbolic affect cannot write an undeclared variable (§6.3).
  - An integrator `resize!` on an MTK problem leaves the new entry without a symbol: `u` has 9
    entries and `sol[V]` correctly returns the 8 declared ones (§6.3). **[Corrected]** It is not a desync of existing variables, but grown entities are unaddressable through SII.
  - The only maintainer statement found on birth/death in MTK is "Avoid MTK for these
    models for the time being" (Rackauckas, Discourse 102324, 2023-08-01).
  - No issue, PR or roadmap item proposes a population, agent or variable-size scope.
- **Lattice-scoped quantities (blocker 3): partial.**
  - Site and field variables are expressible as fixed-shape symbolic arrays, and neighbour
    reads as index arithmetic (§6.2, item 6).
  - But MTKBase scalarizes them. Building an `ODEProblem` for a 64×64 periodic diffusion
    field took **225 s** (256 → 2 s, 1024 → 14 s, 4096 → 225 s), against 10⁴–10⁷ sites in
    the reference models. **[Corrected]** ≈ 99 % of that is building the `InitializationProblem`; with `build_initializeprob = false` it is 0.15 / 0.16 / 1.39 s (review `r4`).
  - MTK #5139 (opened 2026-09-13 by Rackauckas, open) and MethodOfLines #695 (2026-09-13)
    aim to keep arrays unscalarized. **[Corrected]** Since the measured cost is initialization-problem construction, not scalarized codegen, #5139 is not the gating fix at this size.
  - Ownership-dependent terms have no symbolic counterpart and none is planned. These are
    contact pairs `J(τ(σ(x)), τ(σ(x′)))`, `volume(σ(x))`, and folds over `sites(c)`. Their
    indexing goes through a state-dependent map.

**Levels.**

| Level | What it means | Verdict |
|---|---|---|
| **A** | Deeper use of real MTK inside D-075 | **Yes.** Recommended now. Five concrete items (§5.1) |
| **B** | A Potts model *is* an MTK `System`, with lattice content in typed metadata | **Partial, not recommended.** It works mechanically (§6.2), but the `System`'s equations would no longer be the model, so MTK's own tools would give wrong answers silently. Costs scalarization, a rebuild on every capacity change, and `compose` drops the metadata |
| **C** | An upstream population/agent scope in MTK, shared with ABMs | **No** for one year (no plan, maintainer advises against). Worth a Discourse RFC, nothing more |

The realistic target is **Catalyst-level nativeness**. Catalyst's spatial system is the
exact precedent:
- `DiscreteSpaceReactionSystem <: MT.AbstractSystem` (`Catalyst/tAUzg/src/spatial_reaction_systems/discrete_space_reaction_systems.jl:60`) is a wrapper.
- It forwards `equations`, `unknowns` and `parameters` to an inner MTK system (`:489-514`).
- It builds its **own hand-written fused functor**, `LatticeTransportODEFunction` (`spatial_ODE_systems.jl:136-166`).
- That functor calls the MTK-generated per-vertex RHS in a loop.

D-075 already takes this route. What remains is to use MTK for more of the per-entity
dynamics than Potts does today.

---

## 2. Extension-point inventory (MTKBase 1.77.0 / MTK 11.45.1)

| Extension point | Location | What it allows | Relevance to Potts |
|---|---|---|---|
| `AbstractSystem` subtyping | `MTKB/src/ModelingToolkitBase.jl:228`; `System` is concrete, `struct System <: IntermediateDeprecationSystem` (`MTKB/src/systems/system.jl:82`; `isconcretetype(System) == true`, §6.0) | A third-party system type. `System` **cannot be subtyped**: it must be wrapped or mirrored | `PottsSystem` today is **not** `<: AbstractSystem` (`src/system.jl:32`); D-075 §0 plans it to be |
| Field-name duck typing of `AbstractSystem` | `SYS_PROPS` and the generated `get_*`/`has_*` (`MTKB/src/systems/abstractsystem.jl:889-958`) | Generic `equations`, `unknowns`, `parameters`, `observed`, `bindings`, SII and `getproperty` work if the struct has fields named `eqs`, `unknowns`, `ps`, `iv`, `observed`, `name`, `systems`, … | The contract is **undocumented and incremental**. The probe hit, in turn: `eqs`, then `ps`, then the `checks` constructor, then `namespacing`, then `gui_metadata` (§6.1). Catalyst mirrors the fields (`reactionsystem.jl:311-382`) and overrides `complete`, `flatten`, `compose` and `extend` (`:1146, 1569, 1615, 1658`) |
| `setproperties` contract | `MTKB/src/systems/abstractsystem.jl:1029-1048` | `@set`, `setmetadata` and `complete` rebuild a system as `constructorof(T)(all fields…; checks = false)` | A Potts `AbstractSystem` needs a positional all-fields constructor that takes `checks` (§6.1) |
| System metadata | `metadata::MetadataT` field (`system.jl:239`), `MetadataT = ImmutableDict{DataType, Any}` (`:13`); `getmetadata`/`setmetadata`/`hasmetadata` on any `AbstractSystem` (`:1310-1331`); `System(…; metadata = [Key => v])` | Typed, out-of-place payloads keyed by a user `DataType`. `MiscSystemData` (`:29`) is the generic key | Survives `complete`, `mtkcompile` and `extend` in both directions; **lost by `compose`** (§6.2) |
| `ProblemTypeCtx` | `system.jl:1341`; read at `problems/odeproblem.jl:190` and others | Tags the `problem_type` of the produced problem | MOL's hook (`PDEBase/rfV7U/src/discretization_state.jl:127-141`). Could mark a Potts-origin system |
| `mtkcompile(sys::System; additional_passes)` | `MTKB/src/systems/systems.jl:99-100, 135-171` | Post-compile `System → System` functions, run in order after the built-in passes | Dispatches on **`System` only** (`p0`: one method). A custom `AbstractSystem` owns its own `mtkcompile` method, as Potts does (`src/compile.jl:162`). PR #5051 notes that passes run after tearing and can leave structural data stale *(search, not re-verified)* |
| `discrete_compile_pass` trait | `MTK/src/systems/systems.jl:224`; consumed at `MTK/src/systems/systemstructure.jl:150-163, 184-197` | A pass declaring `discrete_compile_pass(p) = true` takes over compilation of the clocked partitions that open-source MTK rejects (`:167`) | **Already used by Potts** (`ext/PottsModelingToolkitExt.jl:16-28`). The only MTK hook that hands a whole partition to third-party code |
| Simplification limits | `MTKB/src/systems/systems.jl:310` | MTKBase refuses systems with both `Shift` and `D` (hybrid) | The MCS clock plus cell ODEs cannot be one MTKBase `System` |
| Problem constructors | `ODEProblem{iip,spec}(sys::System, …)` (`problems/odeproblem.jl:196-197`), `DiscreteProblem` (`discreteproblem.jl:59-60`), `JumpProblem` (`jumpproblem.jl:5`) | Dispatch on `System` | A third-party system must lower to a `System` (Catalyst's `ode_model`/`jump_model`, `reactionsystem_conversions.jl:820, 1218`) or define its own problem (Potts) |
| `process_SciMLProblem` | `MTKB/src/systems/problem_utils.jl:2382-2410, 2432` | Accepts `sys::AbstractSystem`: op → `u0`/`p`, initialization, function construction | **Not public** (`p0`: `public=false`). It assumes a flat `u` |
| `InitializationProblem(sys::AbstractSystem, …)` | `problems/initializationproblem.jl:2-4, 50-56`; `supports_initialization` (`abstractsystem.jl:530`) | MTK's initialization engine on any `AbstractSystem` | Works for a fixed-size `System`, e.g. a per-cell component. Not for ragged state (the D-075 §7.1 gap stands) |
| `bindings`, `initial_conditions`, `guesses`, `initialization_eqs` | `system.jl:193, 198, 202, 212` | Bound (derived) parameters, defaults, guesses, init equations | `bindings` evaluated through `getp`: `J_cm => 2J_cc` gave 6.0 (§6.2) |
| Events | `SymbolicDiscreteCallback` (`callbacks.jl:586`), `Affect` union (`:353`), `ImperativeAffect(f; modified, observed, ctx)` (`imperative_affect.jl:30-60`) | Symbolic conditions; an imperative affect with an **arbitrary `ctx`** | A stand-in "sweep" with the lattice in `ctx` ran at every `t = k` (§6.3). It can only write declared variables, and a whole-array `observed` failed under full MTK 11.45.1 (§6.3) |
| Jumps in `System` | `jumps::Vector{JumpType}` (`system.jl:111`); `JumpType` closed (`utils.jl:1672`); `JumpProblem(::System)` (`jumpproblem.jl:5-135`) | Mass-action, constant-rate and variable-rate jumps with symbolic rates and affects | No room for a lattice operator. The aggregators are O(#jumps) per event (D-075 §0) |
| Clocks | `Clock`, `Shift`, `ShiftIndex`, `Sample`, `Hold`, `SampleTime` (`MTKB/src/discretedomain.jl:184-197`), exported (§6.0) | Clocked partitions | Already the D-042/D-065 Q9 meaning of updates and Boolean networks (`research/mtk-discrete-components.md`) |
| Callable parameters | `@parameters (op::T)(..)` | An opaque functor inside equations, set like any parameter | Works (§6.5): the lattice could ride in a parameter. MTK sees only an opaque call (draft PR #5017: `tgrad` zeroed callable calls *(search, not re-verified)*) |
| Codegen | `generate_rhs`, `generate_jacobian`, …, `generate_custom_function(sys::AbstractSystem, exprs, dvs, ps, opts)` (`MTKB/src/systems/codegen.jl:184, 2471`); `CompilerOptions` holds only `optlevel`/`compile`/`infer` (`codegen_utils.jl:36-40`); Symbolics `BuildTargets` (`build_function.jl:4-7, 34`) | Julia/C/Stan/MATLAB targets; `_build_function(::Target, …)` is internal | No custom-target or kernel hook. `generate_custom_function` is the public route for *per-cell* functions from a compiled `System` |
| SymbolicIndexingInterface | `symbolic_container` and friends (SII 0.3.55) | Any container type can implement the interface | Potts does already (`src/observed.jl:108-138`). There is no ragged shape trait in SII *(search)* |
| PDESystem → discretizer | `PDESystem <: AbstractSystem` (`MTKB/src/systems/pde/pdesystem.jl:37`); PDEBase `discretize`/`symbolic_discretize` (`PDEBase/rfV7U/src/discretization_state.jl:159-195`, `symbolic_discretize.jl:9`) | A discretizer turns a PDESystem into a `System` (scalarized grid unknowns) plus `ProblemTypeCtx` | The input surface could be reused. The MOL route scales badly for lattices (§6.2, item 6) |
| SciCompDSL (`@mtkmodel`) | `MTK/lib/SciCompDSL/src/model_parsing.jl:819-860` | Hard-coded section list; any other section is `error("$mname is not handled.")` (`:859`). Arbitrary-length symbolic arrays are rejected (`:593`) | **No plug-in mechanism for other DSLs.** NEWS: deprecated, community-maintained only (`MTK/NEWS.md:322-330`). Confirms D-075 §0.1: `@potts_model` is its own DSL |

Two further points:
- **License split.** MTKBase keeps the `System`, callbacks and codegen under MIT. Tearing
  and index reduction moved to the AGPL StateSelection and ModelingToolkitTearing
  (`MTK/NEWS.md:337-345`; Discourse "ModelingToolkit v11 library split", 2025-12-06
  *(search)*). Any Level B or C dependency on full MTK would pull AGPL code into the solve
  path. D-015 deliberately depends on MTKBase only.
- **Custom AbstractSystem minimum.** Mirror the `System` field names that the accessors you
  use touch. Provide the `checks` constructor. Override `complete` and `extend` (Catalyst
  overrides `compose` too). Never expect `mtkcompile` or the problem constructors to accept
  the type: they dispatch on `System`.

---

## 3. Precedents: who is "native", and in what sense

| Package | System type | Path to a problem | Own codegen? | Sense of "native" |
|---|---|---|---|---|
| **Catalyst `ReactionSystem`** | Own `<: MT.AbstractSystem` with mirrored fields (`reactionsystem.jl:311`) | **Lowers to an MTK `System`**: `ode_model`, `sde_model`, `jump_model`, `hybrid_model` (`reactionsystem_conversions.jl:659, 820, 1067, 1218`), then MTK's `ODEProblem`/`JumpProblem` (`:1317-1352`, `:1554-1583`) | No | Fully native downstream: every equation is an MTK equation |
| **Catalyst `DiscreteSpaceReactionSystem`** (lattice) | Own `<: MT.AbstractSystem`, a wrapper that forwards `equations`/`unknowns`/`get_metadata` to the inner `ReactionSystem` and declares `get_systems = []` only "for the `show` function to work" (`discrete_space_reaction_systems.jl:489-514`) | Own `ODEProblem`/`JumpProblem` methods (`spatial_ODE_systems.jl:231-271`; `discrete_space_jump_systems.jl:40-98`) | **Yes**: `LatticeTransportODEFunction` loops over vertices, calls the MTK-generated vertex RHS, then adds transport by hand (`spatial_ODE_systems.jl:136-166`). Its SII container is a bare `SymbolCache` of parameter names (`:318-321`) | Native per vertex, own operator across space. **The closest precedent to Potts.** The docs call spatial support "a work in progress" (`discrete_space_reaction_systems.jl:52-58`) |
| **MethodOfLines / PDEBase** | `PDESystem <: AbstractSystem` (MTKB) | `discretize` → scalarized `System` with `ProblemTypeCtx` metadata → `mtkcompile` → `ODEProblem` (`PDEBase/rfV7U/src/discretization_state.jl:127-141, 159-195`) | No (MTK generates the RHS) | Fully native, paid for by one scalar unknown per grid point. MOL #695 (2026-09-13) reports NeuralPDE timing out at 4,417 unknowns and proposes array unknowns *(search, not re-verified)* |
| **JumpProcesses** | None; jumps are fields of `System` | `JumpProblem(sys::System)` builds jump structs (`MTKB/src/problems/jumpproblem.jl:5-135`); `AbstractJumpProblem <: AbstractDEProblem`, special-cased in DiffEqBase (D-075 §0.1) | Rates and affects via MTK codegen | Native because the jump kinds are a closed union MTK knows about |
| **Potts (D-075 target)** | `PottsSystem <: AbstractSystem` (planned; not yet, `src/system.jl:32`) | Own `PottsProblem <: AbstractSciMLProblem` | Yes (D-014 amended) | Catalyst-spatial pattern. MTK `System`s already enter as components (D-038, `src/components.jl:91`) and discrete components (`ext/PottsModelingToolkitExt.jl`) |

Agents.jl, and AgentBasedModeling.jl (arXiv 2409.19294, Sep 2024 *(search)*), sit
outside MTK. They use MTK or Catalyst for each agent's internal dynamics and run their own
population loop. That is again the Catalyst-spatial pattern. The SciML overview points
users with agent-based models to Agents.jl *(search)*.

---

## 4. Blocker analysis

### 4.1 Blocker 1: the stochastic sweep

**Verdict: no MTK mechanism exists, and no upstream change is planned. Confirmed.**

| Candidate MTK mechanism | Does it carry the sweep? | Evidence |
|---|---|---|
| Equations (`D`, `Shift`) | No. A sweep is a random map on an ownership field with rejection; it has no equation form | D-075 §0 |
| `jumps` | No. `JumpType` is a closed union; one jump per (site, neighbour) with ΔH-dependent rates is the n-fold-way algorithm, i.e. different kinetics | `MTKB/src/utils.jl:1672`; D-075 §0 table |
| `ImperativeAffect` with `ctx` | **Opaquely only.** A periodic event can call a Julia sweep that mutates a lattice held in `ctx`. MTK never sees ΔH; affects run on the host between integrator steps; only declared variables may be written | §6.3 (ran 2 sweeps over `t ∈ (0, 3)`; an undeclared write was rejected) |
| Callable parameter | **Opaquely only.** Same problem | §6.5 |
| `discrete_compile_pass` | Hands a *clocked equation partition* to third-party code. Still needs equations | `MTK/src/systems/systemstructure.jl:150-163` |
| `build_function` / `generate_custom_function` | For straight-line expressions only | §6.4; `Symbolics/74GkI/src/build_function.jl:4-7` |

D-014 was re-examined against the pinned Symbolics (§6.4):
- `build_function` now emits `ifelse` as a lazy `if … else … end` and keeps `0.5f0`
  literals. So "lazy `ifelse`" and "Float32 literals" are **no longer reasons** (they
  were in D-014 amended). **[Corrected]** Only with `cse = false`: under CSE (and in MTK's `generate_rhs`) branch-only subexpressions are hoisted, so the lazy-`ifelse` reason stands. Float32 literals: verified.
- It emits `(^)(x, 2)` as a call, not `literal_pow`, so that reason stands.
- The decisive reasons are untouched:
  - loops (gathers, folds, history rings, draws): `sum(x for i in 1:n)` with a symbolic
    `n` throws (§6.4);
  - claims and status words, and the copy/commit protocol;
  - Potts' scope diagnostics;
  - no device target. **[Corrected]** Weak: DiffEqGPU's `EnsembleGPUKernel` runs MTK-generated functions on GPUs.
- D-014's conclusion holds. Its rationale should be updated (§7.2).

**Upstream change that would solve it.** A "custom operator / custom partition" extension
point: a system field holding opaque operators with declared read/write sets, which
`mtkcompile` schedules but does not differentiate or scalarize. This is roughly what
`ImperativeAffect` already is for events. Nothing like it is on any roadmap that was found.
Even if it existed, the kernels would remain Potts-owned. The gain would be scheduling and
indexing, not codegen.

### 4.2 Blocker 2: per-cell ragged, growing state

**Verdict: partial. A fixed capacity is representable. Growth during a solve is not, and
none is planned.**

- **What exists.**
  - Array unknowns of concrete length, `V(t)[1:NCAP]`, plus an `alive` mask. They compile,
    survive `mtkcompile` and are SII-indexable (`is_variable(msys, V[3]) == true`, §6.2).
  - This matches Potts' own layout: capacity-padded, with volume-zero ids free
    (`lib/CorePotts/src/lifecycle.jl:7-10`, `src/problem.jl:342`). It also matches the
    workaround suggested on Discourse 102324 (2023-08-01).
- **What breaks.**
  - Capacity cannot change inside a solve. Growing means a new `System`, a new
    `mtkcompile` and new codegen. Today Potts reallocates on the host at an MCS boundary
    without regenerating code (D-013).
  - A symbolic length is impossible (§6.2).
  - MTKBase scalarizes array unknowns (`mtkcompile` turned 2 array unknowns into 16 scalar
    ones, §6.2). With capacities of 10³–10⁵ cells, construction time balloons (see 4.3).
  - An integrator `resize!` works numerically but desynchronises SII (§6.3).
  - SII has no ragged shape trait *(search)*.
- **Upstream changes that would solve it, and their status.**
  - Unscalarized array unknowns through compile and codegen: MTK #5139 (tracking, opened
    2026-09-13 by ChrisRackauckas, **open**; verified) and PR #5131 (array unknowns on a
    completed system for all problem types, ~Sep 2026 *(search)*). These remove the
    scalarization cost of a fixed capacity, but not the fixed shape.
  - A runtime-resizable unknown (a "population" dimension) together with an SII shape trait
    and an initialization engine that accepts per-entity assignments. **No issue, PR or
    roadmap item found** (search over the MTK issues, Discourse and sciml.ai; "State of
    SciML 2025", 2025-06-26, has no agent-based-model content *(search)*).

### 4.3 Blocker 3: lattice-scoped quantities

**Verdict: partial. Fields are expressible but too costly today, with a fix in progress
upstream. Ownership-indexed terms have no counterpart.**

- **Site and field variables on a fixed lattice.** `c(t)[1:N, 1:N]` with
  `c[mod1(i+1, N), j]` stencils is valid MTK (§6.2, item 6). After scalarization it costs:

  | N×N | `System` | `mtkcompile` | `ODEProblem` (codegen) |
  |---|---|---|---|
  | 16×16 | 0.12 s | 0.12 s | 1.95 s |
  | 32×32 | 0.00 s | 0.06 s | 13.7 s |
  | 64×64 | 0.01 s | 0.24 s | **225 s** |

  Roughly quadratic growth. Reference lattices are 200² to 300³. This is the MOL route's
  cost too. MTK #5139 and MOL #695 target exactly this; when they land, fixed-shape
  fields become cheap.
- **Neighbour reads `x′` relative to a copy attempt, contact pairs, `volume(σ(x))`, and
  folds over `sites(c)`.** These index through the ownership map σ, which is *state*.
  Symbolic arrays index by symbolic integers built from the indices, not by values of
  another state array. The only way in is an opaque callable parameter (§6.5).
- **No counterpart in MTK, and none is planned.**

---

## 5. Levels A, B, C

| | A: deeper MTK inside D-075 | B: model *is* an MTK `System` with metadata | C: upstream population scope |
|---|---|---|---|
| Feasibility | **Yes** | **Partial** (mechanically yes; semantically no) | **No** within a year |
| What works | Per-cell and model ODE/DAE systems compiled by MTK; discrete events; per-cell initialization; MTK clocks (already) | `equations`, `unknowns`, `parameters`, `bindings`, `complete`, `mtkcompile`, `extend`, SII and `ODEProblem` on the non-lattice part; metadata survives (§6.2) | Would make per-cell state first-class |
| What breaks | Nothing user-facing | `unknowns(sys)` omits the lattice; `ODEProblem(sys)` builds a problem *without the sweep*; `compose` drops the metadata; capacity changes mean a rebuild; array `observed` in affects (§6.3) | Nothing upstream to build on |
| Hot path (D-014, D-047, D-051) | Unchanged if MTK only *compiles* (symbolic simplification) and Potts still lowers. Using MTK-generated RGFs in kernels must pass AllocCheck and Metal checks | Unchanged only if Potts ignores MTK's codegen; otherwise scalarized per-element code and 225 s builds at 64² | Unknown |
| GPU | As today | MTK codegen has no device target | — |
| Effort | Small to medium per item (§5.1) | Large: re-plumb `PottsSystem` as metadata, keep a shadow lowering, rewrite `@potts_model` output | Multi-year, requires SciML buy-in |
| Risk | Low; each item is reversible | High: depends on undocumented field and metadata behaviour (`compose` loss, AGPL MTK for hybrids), and silently wrong answers | Very high |
| Decisions touched | D-038 (wording), D-075 §3.2 and §7.1 (init), D-014 (rationale text only) | D-075 §0 and §0.1, D-039, D-013, D-014, D-015 | D-013, D-075 |

### 5.1 Level A: concrete items, ranked

1. **Per-cell initialization through MTK's engine, per entity.**
   - D-075 §3.2 says "same surface, different engine" because the unknowns are ragged.
   - But a *per-cell* component `System` is fixed-size, and `InitializationProblem` accepts
     any `AbstractSystem` (`initializationproblem.jl:2-4`).
   - For `@initialization_equations` that involve only one cell's variables, Potts can
     build one MTK initialization system per component class and evaluate it per cell at
     `at_init`. This is Catalyst's per-vertex pattern.
   - Cross-cell and lattice initialization stays in the Potts `at_init` phase.
   - Effort: medium. Amends D-075 §3.2 (engine: "MTK per entity where the equations are
     entity-local").
2. **The model's own cell and model ODEs as an MTK `System`, simplified by MTK.**
   - Today only `@components` systems go through `mtkcompile` (`src/components.jl:91`);
     the model's own `@equations` cell ODEs are lowered directly.
   - Building one per-cell MTK `System` from them would make the cell dynamics an
     ordinary MTK system that MTK inspects and simplifies (observed elimination, units,
     `bindings`). Potts would still lower the simplified equations into its fused
     `CellPhase` (D-038).
   - Codegen stays Potts' (D-014). Effort: medium. D-038 wording only.
3. **`@discrete_events`/`@terminate` stored as real `SymbolicDiscreteCallback`s on the
   compiled system.**
   - D-075 §0.1 already maps them to `SymbolicDiscreteCallback → DiscreteCallback`.
   - Keep the MTK objects themselves on the system (inspectable, `show`), with a Potts
     compiler that accepts only conditions on model scope and `t`.
   - Effort: small.
4. **`PottsSystem <: AbstractSystem` with typed metadata.** This is what D-075 §0 already
   plans.
   - The probes give its exact contract: mirrored field names, the `checks` constructor,
     and `namespacing`/`gui_metadata`/`complete` handled (§6.1, §2).
   - Use `getmetadata`/`setmetadata` with Potts-owned `DataType` keys for
     lattice/sweep/kind content, rather than ad hoc fields, so MTK tools such as `show`,
     `getmetadata` and SII can see it.
   - Effort: small to medium. No decision change.
5. **`PDESystem` as an *input surface* for fields, lowered by Potts.** Accept a
   `PDESystem` (or its equations, domains and BCs) and lower it to `FieldStep` through
   Potts' own `SciMLBase.discretize(pdesys, ::PottsLatticeDiscretization)`. Do *not* go
   through PDEBase's scalarizing path (§4.3).
   - Value: MOL-compatible authoring and an oracle (D-075 §0.1 already lists MOL as an
     oracle extension).
   - Effort: medium. Optional.

Not recommended under A: calling MTK-generated RGFs (`generate_rhs`) inside Potts kernels
(the literal Catalyst-spatial pattern). It would throw away the fused, `T`-literal,
AllocCheck-gated kernels of D-014/D-047 for no user-visible gain. It is a fallback for
adaptive or stiff host integration only (D-038 "Deferred"), and that is unverified on
Metal.

### 5.2 Level B: detail

The PoC (§6.2) shows the mechanics are fine. A `System` holds the scalar parameters, the
`bindings`, a capacity-padded per-cell ODE and an energy expression, with a `PottsSpec`
payload in `metadata`. The payload survives `complete`, `mtkcompile` (or is re-attached
via `additional_passes`) and `extend`, and reaches `prob.f.sys`.

The objection is semantic. The `System`'s `equations`/`unknowns` would be a *strict subset*
of the model:
- `ODEProblem(msys, …)` builds successfully and simulates a model **with no sweep**;
- `unknowns` lists no lattice;
- `compose(other, [sys])` silently drops the Potts payload (`false` in §6.2); **[Corrected]** the subsystem keeps it; only `mtkcompile` of the flattened composite loses it (review `r10`);
- every MTK tool "works unchanged" only by giving answers about a different model.

A real Level B would also need two more pieces:
- a Potts `PottsProblem(sys::System)` that dispatches on the metadata key, rejecting a
  `System` without it;
- a guard against `ODEProblem` on a Potts-tagged `System`, which can only be done by type
  piracy or by an upstream "problem compatibility" hook (`check_compatible_system`,
  `odeproblem.jl:287` and `jumpproblem.jl:142`, is an internal function, not an extension
  point).

Hybrid MCS-clocked and continuous content cannot be one MTKBase `System` at all
(`systems.jl:310`). Full MTK rejects it too unless a `discrete_compile_pass` takes over
(`systemstructure.jl:184-197`), and that drags in AGPL MTK.

The benefit over A+4 (`PottsSystem <: AbstractSystem` with metadata keys) is negligible.

### 5.3 Level C: detail

There is no plan, and the only maintainer statement is negative (Discourse 102324,
2023-08-01, re-verified). The adjacent work is fixed-shape arrays (#5139, PR #5131). It
is the necessary first step, and Potts should consume it when it lands.

A shared "population scope" would need four pieces:
- a resizable unknown dimension in `System`;
- SII shape traits for ragged solutions;
- an initialization engine that accepts per-entity explicit assignments;
- problem and integrator `resize!` that keeps SII in sync.

That is the D-075 §7.1 list. It is worth proposing as a Discourse RFC co-signed with
Agents.jl or Catalyst-spatial users, not as a Potts dependency.

---

## 6. Proof-of-concept results (read-only, `/tmp/mtknative/`)

### 6.0 Environment (`p0_env.jl`, `--project=.`)
```
MTKBase 1.77.0 SciMLBase 3.56.1 Symbolics 7.41.1
isconcretetype(System) = true; supertype chain: (System, IntermediateDeprecationSystem, AbstractSystem, Any)
JumpType = Union{ConstantRateJump, MassActionJump, VariableRateJump}
Affect union = Union{AffectSystem, ImperativeAffect}
mtkcompile(sys::System; additional_passes, inputs, outputs, disturbance_inputs, split, homotopy, kwargs...) @ systems.jl:135
ProblemTypeCtx public=true exported=false · MiscSystemData public=true exported=true · ImperativeAffect public=true
generate_custom_function public=true · process_SciMLProblem public=false · flat_unknowns public=false
```

### 6.1 Third-party `AbstractSystem` contract (`p1_abstractsystem.jl`)

- A struct with only `name`: `equations` fails with ``no field `eqs` ``, `parameters`
  with ``no field `ps` ``, and `complete`/`show` with ``no field `observed`/`systems` ``.
- A struct mirroring `System`'s field names (`eqs`, `iv`, `unknowns`, `ps`,
  `var_to_name`, `observed`, `name`, `description`, `systems`, `bindings`,
  `initial_conditions`, `guesses`, `initialization_eqs`, `*_events`, `metadata`,
  `complete`) plus a `lattice` field, and an all-fields constructor accepting `checks`:

```
equations / unknowns / parameters / independent_variables / observed / bindings   OK
setmetadata/getmetadata      OK → :potts
getproperty s.V              OK → cpm₊V(t)
SII is_variable / variable_index  OK → true / 1
complete, show               ERR → The system must define the `namespacing` flag to toggle namespacing
extend(s, System)            ERR → type FieldLike has no field `gui_metadata`
mtkcompile(s)                ERR → no method matching mtkcompile(::FieldLike)
```
Without the `checks` constructor, `setmetadata` fails inside
`setproperties(::AbstractSystem)` (`abstractsystem.jl:1029-1048`).

### 6.2 Level B PoC (`p2_levelB.jl`, `--project=.`, 4 min 17 s total)
```
== 1. construction and metadata ==
System(...; metadata = [PottsContent => spec]) OK  (16 equations, 2 array unknowns, 6 parameters)
getmetadata(sys, PottsContent)                 OK → (64, 64)
== 2. what survives the MTK pipeline ==
metadata after complete                        OK → true
mtkcompile(sys)                                OK   unknowns after mtkcompile → 16 (scalarized)
metadata after mtkcompile                      OK → true
metadata after extend(sys, other)              OK → true
metadata after extend(other, sys)              OK → true
metadata after compose(other, [sys])           OK → false        ← payload lost
metadata after additional_passes reattach      OK → true
== 3. SII and problems on the System ==
is_variable(msys, V[3])                        OK → true
is_parameter(msys, J_cm) (bound)               OK → false
ODEProblem(msys, op, (0,10))                   OK → ODEProblem{Vector{Float64}, …, MTKParameters{…}}   ← a problem with no sweep
getp(prob, J_cm)(prob)  (binding evaluated)    OK → 6.0
prob.f.sys carries PottsContent                OK → true
length(prob.u0)  (fixed at construction)       OK → 16
== 4. the ragged / growing state ==
@variables W(t)[1:n] with symbolic n           ERR → TypeError: non-boolean (Num) used in boolean context
== 6. scale: a 2D lattice field as scalarized MTK unknowns (MOL-style) ==
N=16 (256 unknowns)    System 0.12 s, mtkcompile 0.12 s, ODEProblem 1.95 s
N=32 (1024 unknowns)   System 0.0 s,  mtkcompile 0.06 s, ODEProblem 13.72 s
N=64 (4096 unknowns)   System 0.01 s, mtkcompile 0.24 s, ODEProblem 225.44 s
```
(The script's section 5 error came from the probe itself: `alive` had no equation. It is
redone correctly in §6.3.)

### 6.3 The sweep as an MTK event, and growth (`p3_event.jl`, `--project=test`: full ModelingToolkit 11.45.1 + OrdinaryDiffEqTsit5)
```
array-valued ImperativeAffect (modified only): OK
  [first run: observed = (; V = V) on an array unknown → "Observed equation (V(t))[1:8] in affect
   refers to missing variable(s) … V(t)" from compile_functional_affect]
retcode = Success; sweeps run by the event = 2; V(3) = [2.3, 2.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
grow: ERR → Tried to write back to v9 from affect; only declared states ((:v1,)) may be written to.
integrator resize! on an MTK problem: retcode = Success, length(u) end = 9
  sol[V] after resize: 8                         ← SII silently ignores the new entry
```

### 6.4 `build_function` versus D-014 (`p4_buildfunction.jl`)
```
(+)(if (<)(0, x)
        NaNMath.sqrt(x)
    else
        0.5f0
    end, (*)(0.1f0, (^)((+)(-2, y), 2)))
eval in Float32: Float32
sum(x for i in 1:n) with symbolic n → TypeError: non-boolean (Num) used in boolean context
```
Lazy `if` and Float32 literals: present. `literal_pow`: absent (a `(^)` call). Loops over
a symbolic range: impossible. `NaNMath.sqrt` in device code is unverified on Metal.

### 6.5 Callable parameter (`p5_callable.jl`)
```
callable parameter in an equation: OK, du = [17.0]  (op is a parameter: true)
```
An opaque `Sweep` functor holding a lattice matrix sat inside `D(V) ~ op(V)` and was
evaluated by MTK's generated RHS.

---

## 7. Recommendation

### 7.1 How native, and when

- **Now: Catalyst-spatial nativeness**, which D-075 already chose. Implement Level A items
  4, 3, 2 and 1 (§5.1, in that order of cost), inside the existing Phase 6 steps.
  - Every model then has an `AbstractSystem` that MTK tools can introspect.
  - Every per-cell or model ODE, DAE or clocked system is an MTK `System` simplified by MTK.
  - Entity-local initialization uses MTK's engine.
  - The sweep, the lattice, ragged growth and the kernels stay Potts'.
- **In one year, conditional on MTK #5139 and PR #5131 landing.** Fixed-shape lattice
  *fields* could become MTK array unknowns at acceptable build cost. Then `PDESystem` input
  (A5) could reuse more of MTK.
  - Re-run the §6.2 item 6 probe on each MTK minor release. It is a cheap gate: if
    `ODEProblem` at 64² drops below ~1 s, revisit. **[Corrected — rejected by review]** This gate measures initialization-problem construction, not field codegen; it is not a standing row.
  - Ownership-indexed terms and the sweep remain Potts-owned regardless.
- **Never, without new upstream concepts:** Level B as semantics, and Level C.

### 7.2 Proposed D-075 amendments (for the maintainer; not decided)

1. **§3.2 (initialization).** Today: "same surface, different engine". Proposed: "the MTK
   engine per entity for entity-local `initialization_eqs` (per-component
   `InitializationProblem`); the Potts `at_init` phase for cross-entity and lattice
   equations".
2. **§0.1 row `PottsSystem`.** Record the concrete `AbstractSystem` contract found here:
   - mirrored field names;
   - the `checks` constructor;
   - Potts-owned `complete`/`extend`;
   - typed metadata keys for lattice and sweep content;
   - no `compose` (D-039). **[Corrected]** The "reinforced" argument is withdrawn: `compose` keeps subsystem metadata.
3. **D-014 rationale (text only).** Drop "lazy `ifelse`" and "literals in `T`" as reasons
   against `build_function` (obsolete in Symbolics 7.41.1, §6.4). Keep loops, gathers,
   claims, status words, diagnostics and device targets. The conclusion is unchanged.
4. **D-038.** "The model's own cell ODEs are assembled into an MTK `System` and
   `mtkcompile`d like a component before Potts lowers them" (A2), if the maintainer wants
   it.

### 7.3 Upstream proposals (to the SciML team)

Ordered by expected acceptance:

1. **Document the third-party `AbstractSystem` contract.** List the required fields, the
   `setproperties`/`checks` constructor, `namespacing`, and which generic functions
   dispatch on `System` only. A docs PR; Catalyst would benefit too.
2. **Preserve system metadata through `compose`,** or document that it is dropped (§6.2).
   A small issue.
3. **A public problem-compatibility hook,** so a metadata-tagged `System` can refuse
   `ODEProblem`. Today `check_compatible_system` is internal (`odeproblem.jl:287`). This
   only matters if Level B is ever pursued.
4. **Array `observed` in `ImperativeAffect` after scalarizing `mtkcompile`** (§6.3 first
   run). File as a bug with the probe as a reproducer.
5. **Comment on MTK #5139 with Potts' lattice-field use case and the scaling numbers.**
   Use the 64² periodic Laplacian timings as a benchmark. This is the one upstream effort
   that moves Potts closer to native.
6. **A Discourse RFC for a "population/agent dimension"** (a resizable unknown, SII
   ragged shape trait, per-entity initialization, `resize!` that keeps SII consistent).
   Co-sign with Agents.jl or Catalyst-spatial users. Frame it as long-term, not as a
   Potts dependency. It restates D-075 §7.1 rows 1, 6 and 7.

---

## 8. Open questions for the maintainer

1. Is Catalyst-spatial nativeness (Level A) the goal you want stated in the paper, or do
   you want "MTK-native" claimed only for the components and initialization parts?
2. A1 (MTK initialization per entity) and A2 (model cell ODEs through `mtkcompile`) change
   build paths. Should they enter Phase 6 now (P6.0c/P6.4a neighbourhood) or wait for 1.0?
3. Should a `PDESystem` input surface for fields (A5) be built, given that the MOL
   discretization path is only an oracle at small sizes?
4. Should we file proposals 1, 2, 4 and 5 now? (Each needs only the probes in
   `/tmp/mtknative/`, which would move into an upstream reproducer.)
5. Do you want the D-014 rationale text corrected (§7.2 item 3) even though the decision
   is unchanged?

**Unverified items.**
- Metal compatibility of MTK-generated functions (`NaNMath`) inside Potts kernels.
- The status and dates of MTK PR #5131, PR #5051, PR #5017 and MOL #695 (from the search
  pass only).
- Whether MTK 11.45.2 or MTKBase 1.77.1/1.77.2 change any finding. The depot has 1.77.2;
  no probe was run on it.
