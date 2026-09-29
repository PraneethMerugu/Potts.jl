# Potts ecosystem: monorepo migration and SciML-aligned architecture

Status: draft for review · 2026-09-29

## 1. Goals

1. **One repository, one environment.** Every package, model, test, doc and benchmark
   resolves from one `[workspace]` Manifest, and every cross-layer change is one PR.
2. **Compile time comparable to SciML packages.** Symbolic models compile by code
   generation into flat functions, following ModelingToolkit. Models are not encoded
   in the type system.
3. **Warm performance limited by the kernel, not the orchestration.** That means fused
   solver kernels, no per-step host sync, and zero steady-state allocation.
4. **Every novel, useful feature survives.** A feature is cut only when there is a
   SciML argument against it. §4 lists each argument explicitly.

Evidence behind this plan: the four architecture reviews, the stored LM-0/1/2a
compiler evidence, and the FusedCPM prototype (`FusedCPM/README.md`).

| Graner–Glazier 72², same machine | Current stack | FusedCPM prototype |
|---|---|---|
| Build + first MCS | 6.75 s + 16.3 s | 1.6 s + 0.4 s |
| Re-solve the same problem | 2.0 s | 0.03 s |
| Warm, sequential | 6.2 MCS/s | 610 MCS/s, 0 alloc |
| Checkerboard at 16 attempts/site | errors (queue capacity) | 500 MCS/s CPU, 2.3 ns/attempt Metal |
| CPU/Metal replay | claimed | bitwise, tested |

## 2. Target architecture

The layering follows the SciML split between a symbolic front end and numerical
solvers:

| SciML | Potts ecosystem | Role |
|---|---|---|
| ModelingToolkit / Catalyst | **Potts** (repo root) | symbolic `PottsSystem`, statement DSL, `mtkcompile`, codegen |
| SciMLBase + OrdinaryDiffEq / JumpProcesses | **lib/CorePotts** | numerical `CPMProblem`/`CPMFunction`, algorithms, integrator, trackers, lifecycle, RNG, checkpoints. **No Symbolics dependency.** |
| KernelAbstractions / DiffEqGPU | **lib/LocalMath** | generic bounded local computation with conflict-contracted publication |
| Makie recipes | **lib/MakiePotts** | plotting of `PottsSolution`, render frames, explorer |
| ModelingToolkitStandardLibrary | **lib/PottsModels** | published model library, tested in CI |

Two design consequences:

- **CorePotts is usable without the symbolic layer**, in the same way `ODEProblem(f, u0,
  tspan, p)` works without MTK. A user or test can hand-write `ΔH` as a Julia function.
  FusedCPM's `CPMProblem` is this layer in miniature.
- **`PottsProblem(sys, op, tspan)` returns a `CPMProblem` whose `CPMFunction` stores
  `sys`**, the way `ODEProblem(sys, …)` returns an `ODEProblem` whose `ODEFunction`
  carries `sys`. Symbolic indexing works through that stored `sys`.

### 2.1 Symbolic compiler, mirroring MTK

**Current:** a model passes through 10 representations. These are statements,
qualified IR, frozen source graph, normalized graph, analyzed IR, CompilerSPI plans,
compiled program, runtime, LocalMath plan, and kernels. Expressions are lowered twice
into type-level trees (`OperationExpression{T,Tuple}`, then `_Executable*`).

**Target:** three representations, each an MTK analogue.

| Stage | MTK analogue | Output |
|---|---|---|
| **Author** | `System(eqs, t, vars, ps)`, `@mtkmodel`, Catalyst `@reaction_network` | `PottsSystem <: AbstractSystem` holding symbolic energies, update equations, events, observed |
| **`mtkcompile(sys)`** | structural simplification | a *symbolic* compiled system (see below) |
| **`PottsProblem(sys, op, tspan)`** | `ODEProblem(sys, op, tspan)` → `build_function` → RuntimeGeneratedFunction | `CPMProblem` with a `CPMFunction` of generated functions and a `PottsParameters` object |

`mtkcompile` performs these steps and keeps the result symbolic:

1. Flatten and namespace the system.
2. Expand library statements (`Volume`, `ContactEnergy`, `Chemotaxis`, `ActEnergy`, …)
   into primitive energies and updates, as Catalyst expands reactions into
   equations.
3. Validate units and domains.
4. Run dependency analysis to choose trackers. For example, `cell_surface` appears,
   so a surface tracker is added. This is the analogue of MTK's choice between
   observed variables and unknowns.
5. Schedule phases.
6. Apply CSE.

The problem constructor then generates flat code:

- **Rules for codegen:**
  - **Energies are summed symbolically before codegen.** Each anchor domain (site,
    cell, contact, relationship) becomes one straight-line generated function. This
    removes the heterogeneous tuple of terms, and with it the `Base.tail` recursion,
    the `@generated` unrolls and the 26 kB type signatures.
  - **Site and state updates use MTK's discrete-affect conventions.** `Assign(a,
    max(a-1, 0))` becomes `a ~ max(Pre(a) - 1, 0)`, compiled like a
    `SymbolicDiscreteCallback` affect.
  - **Parameters use an `MTKParameters`-style object:** tunable values, discrete
    values, constants and non-numeric values. `remake(prob; p)` and `setp` never
    recompile. **Structural parameters** (lattice rank, neighborhoods, kind count)
    become literals in the generated code, as with MTK `@structural_parameters`.
    Changing them rebuilds the problem, not the type universe.
  - **The codegen API matches MTK:**
    - generation goes through `build_function(...; expression = Val(false), cse = true)`
    - generated functions pass through `drop_expr` so they are GPU-safe
    - `eval_expression` and `eval_module` keyword arguments let packages precompile
      models
    - `expression = Val(true)` returns the generated code for inspection
  - **Observed quantities are generated lazily** through SymbolicIndexingInterface
    `getu`/`observed`, as in MTK.
- **Solver kernels are hand-written generic kernels in CorePotts, specialized only on
  the generated function types.** FusedCPM is the pattern: the kernel takes
  `energy::F`, and every host pass-through uses `::F where {F}`.

### 2.2 Solvers (CorePotts)

- The algorithms are `SequentialCPM` and `CheckerboardCPM`. Both keep exact replay.
  The checkerboard uses 3×3 coloring plus mutual-maxima cell claims, with 2 launches
  per color. The checkerboard dynamic differs from sequential; this is documented,
  and the two are checked against each other statistically.
- The integrator is a `SciMLBase.DEIntegrator`, following JumpProcesses'
  `SSAIntegrator`. It supports `init`/`step!`/`solve!`/`reinit!`, callbacks,
  `ReturnCode`, and `stats`.
- `integrator.u` is materialized lazily. **Nothing synchronizes with the host unless it
  saves or is queried.** The existing queued multi-MCS path becomes the default.
- Failure atomicity is at MCS granularity: a double buffer at the MCS boundary plus a
  device status word, with `retcode` reporting. This replaces the per-color
  full-lattice shadow copies and the `throw` calls in device code.
- Trackers update incrementally per accepted copy. Full-lattice reconstruction happens
  only on init, restore and lifecycle.
- Lifecycle is event-driven. A generated trigger condition gates it, like a
  `DiscreteCallback` condition, so the division pipeline does not run on every MCS.
  Compaction still uses LocalMath.

### 2.3 Hybrid coupling, the SciML way

- Native ODE, DAE and PDE components are created **once**, at `init`, as SciML
  integrators. They are advanced with `step!`/`reinit!`, and coupled through SII
  `setp`/`getu`. This removes the current rebuild of `ODEProblem` on every advance
  (`PottsModelingToolkitExt.jl:875`).
- Per-cell ODEs become one batched system over the cell dimension on CPU. On GPU they
  run through `EnsembleGPUKernel`, as today.
- MethodOfLines fields continue to be supported. Simple reaction–diffusion fields also
  get a direct generated LocalMath stencil stage.

### 2.4 Repository layout

```
Potts.jl/                      # monorepo; root package = Potts (symbolic front end)
├─ Project.toml                # [workspace] projects = [lib/*, test, docs, benchmark]
├─ src/  ext/  test/
├─ lib/
│  ├─ LocalMath/   {Project.toml, src, test, ext}
│  ├─ CorePotts/   {Project.toml, src, test, ext}
│  ├─ MakiePotts/  {Project.toml, src, test}
│  └─ PottsModels/ {Project.toml, src, test}
├─ docs/                       # one Documenter site, per-package sections
├─ benchmark/                  # AirspeedVelocity suites: TTFX + warm, per model
└─ .github/workflows/          # CI matrix over GROUP = lib × {Core, QA, GPU}
```

- Sibling dependencies use `[sources] LocalMath = {path = "lib/LocalMath"}`. There is
  one Manifest at the root, and it is git-ignored.
- `Pkg.develop` scripts, `dev/environments.jl`, and the 32 separate `Project.toml`
  files all go away.
- Each `lib/*` package is still registered independently. Registrator's `subdir`
  option and CompatHelper handle this, as in OrdinaryDiffEq.jl.
- CI follows SciML practice:
  - `GROUP`-selected tests, run with ParallelTestRunner or SafeTestsets
  - a quality group: Aqua, ExplicitImports, JET `@test_opt` on the solver entry
    points, and AllocCheck on the warm step
  - a Downgrade CI job
  - GPU testing on a Metal runner, or Buildkite for CUDA/ROCm
  - benchmark comparison on PRs; tracked, never a pass/fail gate
- Formatting uses the SciML style.
- These stay outside the monorepo, but under git: SCDPotts and LocalMathSCD go to a
  `PottsTalks` repo. KaimonCompilerTools remains a standalone dev tool.

## 3. Feature survival matrix

✅ = survives, with the same meaning. 🔁 = survives, reimplemented. The acceptance test
is ported *before* the cut-over.

| Feature | Current owner | New owner | Status | Acceptance |
|---|---|---|---|---|
| `PottsSystem <: AbstractSystem`, `compose`/`extend`/`flatten`, namespacing, `@named` | Potts | Potts | ✅ | existing system tests |
| Statement DSL (`@statements`, `Lattice`, kinds, `Volume`, `ContactEnergy`, `Chemotaxis`, `ActEnergy`, `HamiltonianTerm`, `ProposalDrive/Constraint/Modifier`, `Observation`, `Protocol/Sweep`) | Potts | Potts | 🔁 codegen | model library trajectories (statistical); per-term ΔH vs brute-force H |
| Statement registry and user-defined statements (`register_statement`) | Potts | Potts | ✅ simplified: a registered statement expands into primitive symbolic terms | custom-statement test |
| `SourceLocation` in diagnostics | Potts | Potts | ✅ | error-message tests |
| Symbolic operations: `cell_volume`, `cell_surface`, `cell_center`, `cell_elongation`, `field_value`, `field_gradient`, `laplacian`, `history_value`, `lag`, `linked`, `distance`, `gather`/`fold` | Potts | Potts → generated code | 🔁 | per-operation oracle tests |
| Randomness in models (`draw`, `Bernoulli`, `Normal`, `Uniform`, `UnitVector`) | Potts/CorePotts | same | 🔁 as generated Philox calls | distribution tests + replay |
| Units (DynamicQuantities/Unitful, `ReferenceUnits`) | Potts | Potts | ✅ | unit tests |
| `PottsProblem`, `solve`/`init`/`step!`/`remake`, `EnsembleProblem`, `PottsSolution`, SII (`getu`/`setp`/`observed`) | Potts | Potts + CorePotts | ✅ integrator subtypes `DEIntegrator`; ensembles reuse one compiled problem | SciMLBase interface tests |
| Site, cell, medium, model, field and history state; `Synchronous`, `AcceptedCopy`, `ClearOnOwnershipChange` | Potts/CorePotts | same | 🔁 as `Pre()`-style affects | state-update tests |
| **Address-keyed semantic RNG** (Philox, qualified addresses) | CorePotts | CorePotts | ✅ **core novelty** | replay across threads and backends |
| Sequential and checkerboard engines, mutual-maxima conflict rule | CorePotts | CorePotts | 🔁 fused kernels | brute-force ΔH, replay, seq-vs-cb statistics, CPU/GPU bitwise |
| Hamiltonian anchor domains (site, cell, contact, relationship) | CorePotts | codegen targets | 🔁 | per-domain ΔH oracle |
| Trackers: volume, surface, moments/centroid/elongation, site-sum, site-minimum | CorePotts | CorePotts | 🔁 incremental | tracker == recomputation after N steps |
| Local connectivity constraint | Potts/CorePotts | CorePotts | 🔁 | connectivity tests |
| Lifecycle: divide (principal axis, random plane, specified normal, external), remove, retire, create, transition; state rules; placement; conflict priorities; inadmissibility policies | CorePotts | CorePotts | 🔁 event-driven | existing lifecycle scientific tests |
| Cell–cell relationships (edges, relationship state/energy, create/remove/retune) | CorePotts | CorePotts | 🔁 | relationship tests |
| Checkpoint and exact continuation | CorePotts | CorePotts | ✅ one model fingerprint + state + RNG position | split-run == straight-run bitwise |
| Native components: ODE/DAE/MethodOfLines, per-cell batched, Metal via DiffEqGPU, scheduling phases | Potts ext | Potts ext | 🔁 init-once integrators | Akeeb MTK-bridge validation (bytewise target match) |
| LocalMath relation algebra (affine, boundary periodic/ghost/masked, indexed, packed, inverse, composed, product) | LocalMath | LocalMath | ✅ | existing tests |
| **LocalMath publication laws** (`Unique` with conflict detection; `Reduce` canonical/relaxed; `Resolve` ArgMin/ArgMax with ties; `Collect`; `KeyedReduce`; `OrderedFold`) | LocalMath | LocalMath | ✅ **core novelty** | existing tests + D2Q9/DEM witnesses |
| `@localmath`, `@prepare`, bind → plan → prepare → `execute!` | LocalMath | LocalMath | ✅ plan made cheap | TTFX benchmark |
| Pointwise launch fusion with inspectable plan | LocalMath | LocalMath | ✅ | fusion tests |
| Makie recipes, encodings, 3D slices, explorer, recording | MakiePotts | lib/MakiePotts | ✅ + `plot(sol)`; reads through accessors only | existing tests |
| Published models (Wortel, Merks, OpenVT) | PottsModels | lib/PottsModels | ✅ **tested in CI**, so they cannot drift again | model tests |
| Metal backend | ext | ext | ✅ takes KA backends directly | GPU group |

### 3.1 Features that exist only on unmerged branches

These requirements were recovered by the Phase 0 triage from 30 unmerged branches and
the `native-act-leader-follower` integration tips. Some are already squash-merged on
`main`; each one must be matched or covered by the rewrite. All source is preserved in
`archive/*` tags.

| Area | Features |
|---|---|
| Spatial queries | neighbor counts; runtime-weighted contact measures; boundary-site queries; neighbor property sums and means; predicate filters; global interface queries; fixed-domain owners |
| Cartesian ownership domains | fixed owners and immutable sites; per-face boundary kinds |
| Maintained quantities | scalar site sums with atomic input; source-aware site quantities; structured owner sums; bounded scalar site minima; scalar site aggregates |
| Geometry | stable periodic cell geometry (centroid and moments across periodic boundaries); held-turn cell polarity with scalar trigonometry |
| Act / migration | owner-filtered Act with raw geometric mean; owner-filtered bounded site gathers; leader interface drives; compositional activity drives |
| Randomness | addressed draws in scheduled state assignments and explicit Euler field rates; namespaced operation keys for authored and initialization draws |
| Fields | explicit authored rates for discrete fields; named-product fields with shared initial units |
| Composition | scalar and native component imports; structural replacement; scoped quantities and anchors; logical vector parameters; logical state through symbolic setters; one-block model declaration; compound assignments from shared boundary reads |
| Lifecycle | explicit policies for retained cell state; typed lifecycle literals; finite-cell processes; pausable sequential lifecycle boundary; native-component lifecycle phases |
| History | source-owned histories with typed lag and initial capture |
| Diagnostics | compound-model compilation diagnostic; operation failures shown with expression and remedy |
| LocalMath | runtime-indexed Field reads; runtime-selected reads of published collections; live compacted records in portable stages; grouped inverse reads by runtime occupancy |

## 4. What changes, and the SciML argument for each

| Current design | Change | SciML argument |
|---|---|---|
| Type-level expression trees (`StaticEvaluator`, `OperationExpression{T,Tuple}`, `_Executable*`), 81 `@generated`, 1 700 `@inline` | **Replace** with `build_function` + RuntimeGeneratedFunction | MTK compiles symbolic models by generating code, never by encoding them in types. Type-level ASTs make inference and LLVM cost scale with model complexity: measured at 62 s and 3 GB for the flagship. |
| 10 representations, with coverage checks and fingerprints repeated | **Collapse** to System → compiled System → Problem | Each representation is another owner of the same facts, which is also forbidden by your own AGENTS.md. MTK has exactly these three. |
| Lowering on every `init`; ensembles recompile their plans | Codegen at problem construction; `remake` reuses it | SciML problems carry compiled functions, and `init` only allocates the cache. |
| Plan-time `code_typed` admission of evaluators | Move to **test-time** JET/AllocCheck, plus clear errors at kernel compilation | Runtime IR inspection costs seconds, depends on compiler internals, and is not done by any SciML package. |
| Receipts, leases, poisoning, settlement objects, status/detail codes, capability report objects | `ReturnCode`, `stats`, algorithm traits, exceptions | SciML reports outcomes through `retcode`/`stats`, and capabilities through traits such as `SciMLBase.allowscomplex` and `isadaptive`. **Kept:** on-device conflict *detection* (e.g. `Unique`), because it is semantic, not reporting. |
| 5 fingerprint levels, SHA identities pinned to `v1`/`v2` strings | **One** model fingerprint, used by checkpoints | One fingerprint gives the only guarantee users need: checkpoint compatibility. |
| Public cross-repo SPIs (`CompilerSPI`, `BackendSPI`, capability SPI) | Internal to the monorepo; the public surface is the SciMLBase interface plus documented extension points | In SciML, sub-packages talk through SciMLBase interfaces, and internals change together in one PR. |
| Per-color full-lattice shadow copies; per-stage transaction banks; `throw` in device code | MCS-boundary double buffer + device status word | SciML integrators do not roll back mid-step. A failed step reports through `retcode` and keeps the last good state. |
| Host sync + full snapshot on every `step!` | Lazy `integrator.u`; sync on save or query | Matches the DiffEqGPU and JumpProcesses integrators. |
| Full LocalMath prepare + execute per accepted flip (sequential trackers) | Incremental tracker updates | This is a bug. |
| Lifecycle pipeline, with serial single-thread kernels, on every MCS | Gated by generated trigger conditions | Callback semantics: evaluate the condition, then run the affect only when it fires. |
| `ODEProblem` rebuilt on every native-component advance | `init` once, then `step!`/`reinit!` | The integrator interface exists for exactly this. |
| `CPUBackend`/`MetalBackend` wrappers | KA backends passed directly | DiffEqGPU and KernelAbstractions convention. |
| `design/evidence`, qualification bundles, frozen timing ceilings, committed Manifests | Archive tag in the old repo; AirspeedVelocity trend tracking; no committed Manifests | SciML tracks performance as benchmarks, not gates, and reproducibility comes from compat bounds plus Downgrade CI. |

### What is explicitly *not* cut

These have no SciML counterpart, and the SciML argument is to keep them:

- Address-keyed deterministic RNG, and bitwise CPU/GPU replay.
- LocalMath's conflict-contracted publication laws.
- Checkpoint continuation.
- Cell–cell relationships.
- The declarative lifecycle vocabulary.
- Statement source locations.

## 5. Strategy: greenfield rewrite against a frozen reference

A rewrite is simpler than a migration:

- The compiler and execution core, about 60k of the 90k lines, would be deleted in
  any case.
- The branches have diverged in exactly those files.
- FusedCPM already demonstrates the new core design.

What is carried over:

- **LocalMath**, imported with its history and then slimmed.
- **MakiePotts**, imported and adapted to accessors.
- **Scientific vocabulary, tests and models**, ported rather than copied.

**The reference implementation.** The `origin/main` set is LocalMath `041b930`,
CorePotts `6ec7316`, Potts `427dc2e2`, PottsModels `de97149` and MakiePotts `a8a025f`.
Verified 2026-09-29: it loads together, and all PottsModels tests pass (36/36 model
assertions). It is frozen as the `legacy` reference:

- Its Manifest lives in `reference/`. This is the one committed Manifest, because the
  claim that the old results replay exactly requires exact dependency replay.
- It is used for statistical and scientific parity checks.
- It never runs in the main CI matrix.

### Phase 0 — Freeze (done 2026-09-29, local only)

- 237 local `archive/<branch>` tags across the five repos.
- 12 second-clone-only branches imported into `Potts.jl` as `archive/second-clone/*`.
- `archive/localmath-integrated-detached` created for the detached integration head.
- Uncommitted work (native-act worktree, second clone, AGENTS.md edits) saved as
  patches, with the triage report and scripts, in
  `.reconciliation-preservation/phase0-2026-09-29/`.
- **Pending approval:** push the tags to GitHub, then prune 42 stale worktrees and
  delete archived branches.

### Phase 1 — Skeleton monorepo

Layout as in §2.4:

- Root `[workspace]` with `[sources]` and one git-ignored Manifest.
- CI groups (Core, QA, GPU) and an AirspeedVelocity benchmark suite.
- `lib/CorePotts` seeded from FusedCPM.
- `lib/LocalMath` and `lib/MakiePotts` imported with history (`git subtree`).
- `lib/PottsModels` created empty.
- `reference/` environment pinned to the legacy set.

**Exit criterion:** CI green, and FusedCPM's tests pass inside `lib/CorePotts`.

### Phase 2 — CorePotts numerical engine

1. Build out `CPMFunction`/`CPMProblem`, the `DEIntegrator` integrator and the fused
   kernels. Every feature takes plain Julia functions.
2. Port features in dependency order. Each step lands with its oracle tests:
   brute-force ΔH, trackers equal to recomputation, replay, and CPU/Metal bitwise
   agreement.
   1. contact, volume, surface, generic cell/site energies
   2. trackers: surface, moments, periodic geometry, site sums and minima
   3. site, cell and history state; synchronous and accepted-copy updates
   4. fields and explicit rates, using LocalMath stages
   5. drives, chemotaxis, Act, owner-filtered gathers
   6. connectivity
   7. spatial queries and Cartesian ownership domains
   8. lifecycle (event-driven)
   9. relationships
   10. checkpoint and continuation
   11. Metal
3. **Science parity for each feature:** matching statistics against `reference/` on a
   fixed model.

### Phase 3 — Potts symbolic front end (MTK-style, §2.1)

1. Build `PottsSystem`, statements that expand into primitive symbolic terms, and
   `mtkcompile`.
2. Generate code into `CPMFunction`.
3. Wire up `PottsProblem(sys, op, tspan)`, `PottsParameters`, SII, callbacks,
   `EnsembleProblem`, units, diagnostics with source locations, and the statement
   registry.

### Phase 4 — Hybrid coupling and models

1. Implement native ODE/DAE/MethodOfLines components as init-once integrators, plus
   batched per-cell ODEs.
2. Port Wortel, Merks and OpenVT, and the SCD studies (Graner–Glazier, Wortel Act,
   Akeeb), into `lib/PottsModels`.
3. **Exit criterion:** each ported model matches its `reference/` statistics, and the
   Akeeb MTK-bridge targets match bytewise as they do today.

### Phase 5 — LocalMath slimming, docs, cut-over

1. Slim LocalMath (§4).
2. Write one docs site.
3. **Cut-over, which requires approval.** The monorepo becomes `Potts.jl` `main`, and
   the legacy history stays reachable through `legacy/*` tags. The other four repos
   are archived read-only, with a pointer.
4. Register each `lib/*` package from its `subdir`.

## 6. Targets

These are tracked in `benchmark/`; they are goals, not CI gates.

| Metric | Now | Target |
|---|---|---|
| Graner–Glazier build + first MCS, CPU, warm package cache | 23 s | < 3 s |
| Largest published model, first MCS | 60–120 s | < 15 s |
| `remake(prob; p)` + first MCS | recompiles and relowers | 0 compilation |
| Warm allocations per MCS | 49 kB | 0 |
| Package load (`using Potts`) | 7.4 s | < 4 s |
| Environments to set up for development | ≥ 5 (+ worktrees) | 1 |

## 7. Decisions (accepted 2026-09-29)

0. **Strategy:** greenfield rewrite against a frozen reference (§5); chosen over an
   in-place migration.

1. **Monorepo home:** convert `Potts.jl` in place, like OrdinaryDiffEq.jl, and strip
   the heavy paths from history. The other repos are archived, read-only, with a
   pointer.
2. **Compatibility:** pre-migration trajectories and checkpoints need only match
   statistically. The minor version is bumped.
3. **Branch triage:** evidence-based classification (§8). Every branch is preserved
   as an `archive/<branch>` tag before any branch is removed, so nothing is lost.
4. **MakiePotts:** stays a `lib/` package and gains a `plot(sol)` recipe.
