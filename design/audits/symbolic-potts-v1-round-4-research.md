# Symbolic Potts V1 Consolidation Round 4 Research

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete research basis for the next owner interview; no implementation authorization

## Purpose

Rounds 1 through 3 and the ModelingToolkit/ProcessBigraphs amendment froze the symbolic model,
statement language, units, completion, qualified IR, compiler ownership, extension boundaries, and
two-level composition architecture.

The remaining implementation-grade decisions are concentrated in the runtime and repository
cutover:

1. the exact `PottsExecutable` and compile contract;
2. structural versus runtime parameters;
3. initial state, `PottsProblem`, RNG replica, solve, solution, and checkpoint behavior;
4. the final public surface and clean-break deletion/extraction map; and
5. the ordinary test, CI, and scoped-supersession gate.

This research prepares one five-decision interview round covering those topics. Accepting that
round should leave specification consolidation and ambiguity audit, rather than another product
interview, as the only work before implementation send-off.

## Research method

### Repository audit

The audit covered:

- the root and CorePotts package entry modules and complete export blocks;
- current root authoring, lowering, initialization, reference-model, and precompile paths;
- current CorePotts state, topology, relationship, field, lifecycle, algorithm, execution, SciML,
  ensemble, persistence, and ProcessBigraphs adapter paths;
- current `PottsModel`, `PottsProblem`, integrator, solution, parameter-remake, callback,
  checkpoint, and ensemble implementations;
- root, CorePotts, ProcessBigraphs, MakiePotts, integration, GPU, benchmark, and platform tests;
- all living GitHub Actions workflows;
- current archived qualification and evidence scripts;
- specifications whose API, dependency, compatibility, or qualification clauses conflict with
  Symbolic Potts V1; and
- the completed Round 3 and MTK/ProcessBigraphs research.

Measured current impact:

| Surface | Current size or occurrence |
|:--|--:|
| root `src/authoring` | 29 files, 7,701 lines |
| root paper-specific `src/reference_models` | 4 files, 1,631 lines |
| CorePotts `src/coupled` | 35 files, 16,458 lines |
| CorePotts algorithm files | 5 files, 3,114 lines |
| root test suite | 14 files, 2,279 lines |
| CorePotts test suite | 47 files, 10,063 lines |
| active integration conformance files | 29 files, 3,343 lines |
| active integration transition tooling | 18 files, 4,519 lines |
| files mentioning `PottsModel` in active audited paths | 80 |
| files mentioning `ModelFragment` | 15 |
| files mentioning `LotteryCPM` | 20 |
| files mentioning `TiledCheckerboardCPM` | 14 |
| files mentioning `ProcessBigraphs` in Potts/Core active paths | 26 |

Runtime module inspection in the prior consolidation audit found approximately 248 public/exported
PottsToolkit bindings and 777 public/exported CorePotts bindings. This is not a viable clean V1
surface.

### Primary and official external sources

- [SciML problem and remake interfaces](https://docs.sciml.ai/SciMLBase/dev/interfaces/Problems/)
- [SciML solution interfaces](https://docs.sciml.ai/SciMLBase/dev/interfaces/Solutions/)
- [SciML ensemble interface](https://docs.sciml.ai/SciMLBase/dev/interfaces/Ensembles/)
- [SymbolicIndexingInterface API](https://docs.sciml.ai/SymbolicIndexingInterface/dev/api/)
- [SymbolicIndexingInterface usage](https://docs.sciml.ai/SymbolicIndexingInterface/stable/usage/)
- [ModelingToolkit variable and tunable-parameter metadata](https://docs.sciml.ai/ModelingToolkit/stable/API/variables/)
- [SciML common solver options](https://docs.sciml.ai/DiffEqDocs/dev/basics/common_solver_opts/)
- [Julia module, export, and `public` semantics](https://docs.julialang.org/en/v1/manual/modules/)
- [Aqua package QA](https://juliatesting.github.io/Aqua.jl/stable/)
- [ExplicitImports API](https://juliatesting.github.io/ExplicitImports.jl/stable/api/)
- [JET package analysis](https://aviatesk.github.io/JET.jl/stable/)
- [PrecompileTools](https://julialang.github.io/PrecompileTools.jl/stable/)

## Executive recommendation

The final V1 lifecycle should be:

```julia
completed = complete(sys)

executable = compile(
    completed;
    engine = SequentialEngine(),
    backend = CPUBackend(),
    scalar_type = Float32,
)

initial = PottsInitialState(
    ownership = LabelledCells(
        labels;
        cells = [1 => endothelial, 2 => endothelial],
        medium = extracellular,
    ),
    values = [
        activity => activity0,
        chemoattractant => concentration0,
    ],
)

prob = PottsProblem(
    executable,
    initial,
    (0, 1_000);
    p = [
        temperature => 20.0,
        diffusion => 1.0us"μm^2/s",
    ],
    seed = 0x1234,
    replica = 1,
)

sol = solve(
    prob;
    saveat = 10,
    observables = [cell_area, concentration],
)
```

The compiler fixes engine semantics, backend target, scalar type, storage, and kernels.
`PottsProblem` supplies only experiment-specific numerical data and initial conditions. `solve`
does not select another engine or backend.

This is the crucial simplification over the current interface.

## Finding 1 — `PottsExecutable` must be the sole compiled authority

The current CorePotts interface stores a reusable `PottsModel` in the problem, then chooses the
algorithm and backend during `init` or `solve`. It realizes components from a host callable,
constructs an execution plan, compiles lifecycle behavior, adapts state, and optionally uses a
public `PottsCompilationCache`.

That design conflicts with the accepted V1 lifecycle:

```text
complete -> compile -> PottsProblem -> solve
```

V1 should make compilation final with respect to:

- sequential versus deterministic-checkerboard engine;
- backend family and concrete device target;
- runtime scalar and accumulator types;
- storage layout and fixed capacities;
- lowered statement and equation programs;
- RNG site allocation;
- effect and relationship transactions;
- equation-solver policies and workspace shapes;
- observation kernels;
- capability envelope; and
- checkpoint schema.

### Recommended compile surface

```julia
compile(
    completed::PottsSystem;
    engine::AbstractPottsEngine,
    backend::AbstractPottsBackend,
    scalar_type::Type{<:AbstractFloat},
) -> PottsExecutable
```

The three selections should be explicit. An accidental default must not silently choose different
scientific dynamics, device behavior, or numerical precision.

Recommended public selectors:

- `SequentialEngine()`
- `CheckerboardEngine()`
- `CPUBackend()`
- optional backend-extension values such as `MetalBackend()`, `ROCmBackend()`, and `CUDABackend()`

The exact backend values should be Potts-owned immutable descriptors. Users should not need to
import KernelAbstractions merely to request the CPU. A backend extension may carry the concrete
device object privately.

### Executable contents

`PottsExecutable` should be immutable and privately laid out. Through accessors and `inspect`, it
exposes:

- completed-system and executable fingerprints;
- selected engine, backend, scalar, accumulator, and replay classes;
- qualified statement and equation manifest;
- public symbolic index map;
- runtime parameter schema and defaults;
- initial-state schema;
- external IO manifest;
- storage, workspace, kernel, and schedule reports;
- capability admissions and rejections; and
- the private `CorePotts.CompiledPottsProgram`.

The compiled program and executable contain no unresolved registry lookup, external ModelingToolkit
system, DynamicQuantities object, Unitful quantity, Symbolics expression, source AST, or executable
closure.

### No public compilation cache

The current cache keys compilation with Julia `hash` over types, shapes, algorithm, backend, and
snapshot policy. Julia `hash` is not a semantic or persistent identity, and the cache exists mainly
because compilation currently happens at `init`.

V1 should not expose a `PottsCompilationCache` initially:

- compile once and reuse the immutable executable;
- create multiple problems from one executable;
- keep any backend compiler cache internal to Julia, KernelAbstractions, or the backend; and
- add a public cache only after a measured real workload demonstrates a need and its invalidation
  contract can be specified.

There must be no hidden global compilation cache or disk cache.

## Finding 2 — Parameter role must be compiler-proven

The current runtime accepts a typed parameter container and calls a host parameterization function
to rebuild `ScientificComponentSet`. Runtime mutation is admitted if the rebuilt component tuple
has the same concrete type. This tests an implementation accident rather than the semantic
dependency of a parameter.

V1 should classify every symbolic parameter by use.

### Structural parameters

A parameter is structural if it can affect:

- lattice dimensions, topology, neighborhood, or boundary kind;
- state element type, rank, shape, ownership, or storage policy;
- cell, relationship, history, or request capacity;
- relationship maximum degree;
- statement, equation, event, process, or RNG-site existence;
- phase, cadence, substep count, ordering, or iteration domain;
- access, effect, write, bound, or conflict analysis;
- equation algorithm identity or workspace shape;
- admitted engine, backend, or capability; or
- generated kernel or transaction structure.

Structural values must resolve from explicit symbolic defaults or substitution before completion.
Changing one requires returning to the incomplete source, applying `substitute`, completing, and
compiling again. Structural values enter the completed-system and executable fingerprints.

Completion must reject an unresolved structural value. It must not defer the value to
`PottsProblem`.

### Runtime parameters

A parameter is runtime-replaceable when replacement changes only a validated numerical leaf in:

- an energy, drive, constraint, or modifier expression;
- an equation coefficient, rate, threshold, or source;
- a supported event condition or assignment;
- a protocol-controlled numerical value; or
- an explicitly external numerical input.

Replacement must not change units, shape, storage, access, effects, bounds, RNG sites, phase,
solver family, or capability.

The compiler owns this classification. `tunable=true` metadata may express author intent and
improve diagnostics, but it cannot override dependency analysis. A value marked tunable that is
structural is rejected as tunable and diagnosed with every structural use.

Runtime parameter values:

- are converted to the executable reference-unit system and selected scalar type;
- live in a typed executable-owned parameter buffer schema;
- enter problem/trajectory identity and solution provenance;
- do not change the executable fingerprint; and
- can vary between problems made from one executable.

### Problem parameter input

The user-facing `p` input should accept a complete or partial symbolic map, including `Vector{Pair}`
or `Dict`. The constructed problem stores a typed `PottsParameters` value, not the user dictionary.
Missing values resolve from executable defaults and then from the existing problem during
`remake`, following the SciML symbolic-map convention.

Unknown, duplicate, unit-incompatible, shape-incompatible, structural, or unresolved parameters
are contextual construction errors.

## Finding 3 — `PottsProblem` should contain experiment data only

### Recommended initial-state vocabulary

V1 needs one public host-side value:

```julia
PottsInitialState(
    ;
    ownership,
    values = [],
)
```

`ownership` is exactly one of:

- `LabelledCells(labels; cells, medium)` for a dense paper or image-derived raster; or
- `OwnershipLayout(entries...)` containing explicit `CellPlacement`,
  `MediumPlacement`, or accepted procedural placement declarations.

`values` is a symbolic map from declared state identities to initial scalar, array, field, history,
or relationship values.

Rules:

- the label raster contains provisional finite-cell identities;
- `cells` maps every nonzero label identity to one declared `CellKind`;
- `medium` supplies the declared medium for zero labels when exactly one applies;
- multiple media require explicit `MediumPlacement` entries;
- every mutable input is defensively copied;
- map keys are symbolic identities, not strings;
- missing values resolve from `PottsSystem.initial_conditions` and declared state defaults;
- conflicting sources are errors;
- shape, kind, capacity, endpoint, unit, and generation constraints validate against the
  executable manifest;
- procedural placement randomness uses a dedicated semantic initialization stream; and
- initialization draws do not shift simulation draw sites.

The PottsToolkit V1 surface should not expose backend-resident initial-state aliasing. Expert device
restart belongs to CorePotts or the checkpoint path, not the canonical authoring API.

### Recommended problem constructor

```julia
PottsProblem(
    executable::PottsExecutable,
    initial::PottsInitialState,
    tspan::Tuple{<:Integer,<:Integer};
    p = [],
    seed::Integer,
    replica::Integer = 1,
) -> PottsProblem
```

The problem:

- owns the executable, normalized typed initial state, typed parameter values, absolute integer MCS
  span, `UInt64` master seed, and positive bounded replica identity;
- does not contain an algorithm, backend, numerical policy, capacity guess, callback, save policy,
  compilation cache, or host component-realization function;
- is deeply immutable from the user's perspective;
- creates independent mutable runtime state for every `init`;
- validates `0 <= t0 <= t1`;
- interprets the first step as completing MCS `t0 + 1`; and
- uses absolute MCS in RNG addresses and schedules.

All capacities are structural declarations resolved by completion and compilation. The problem does
not guess headroom or resize compiled storage.

### Seed and replica

The accepted `replica` keyword should replace the current ensemble-specific seed derivation as the
stable trajectory identity:

```text
random key = (seed, replica, semantic stream, MCS, operation, entity, invocation, draw)
```

`replica` defaults to `1`, must be positive, and must fit the accepted RNG address domain.
Worker, thread, device, scheduling order, and ensemble completion order never enter the key.

An `EnsembleProblem` wrapper should keep the template master seed and assign the SciML
`EnsembleContext.sim_id` as replica identity unless a user `prob_func` explicitly supplies a
different valid replica. Reruns include the ensemble repeat identity in the RNG address rather than
silently deriving an unrelated master seed.

This is easier to inspect and reproduce than replacing `prob.seed` with a hidden derived value.

## Finding 4 — Solve must not recompile or change scientific dynamics

### Recommended solve relationship

```julia
solve(prob; kwargs...) = solve!(init(prob; kwargs...))
```

There is no algorithm positional argument. Engine, backend, and scalar type already belong to the
executable.

`init`:

- validates problem/executable identity;
- realizes and converts the normalized initial state;
- allocates private runtime storage and workspaces;
- initializes RNG from seed and replica;
- initializes supported equation solvers and observation storage;
- may restore a compatible V1 checkpoint; and
- does not advance an MCS.

`step!` advances exactly one complete MCS. `solve!` is a loop over that same operation.

### Admitted solve options

Recommended V1 keywords:

- `saveat`
- `save_start`
- `save_end`
- `save_everystep`
- `observables`
- `maxiters`
- `progress`
- `progress_steps`
- `verbose`

`saveat` accepts integer MCS boundaries or one positive integer cadence. Potts solutions have no
dense or fractional-MCS interpolation.

Generic `adaptive`, `dt`, `abstol`, `reltol`, `sensealg`, continuous callback, and arbitrary host
`callback` options are rejected. Equation-process solvers own their typed numerical policy.
Scientific mutation and scheduling use accepted symbolic events and `Protocol`, not an
uninspected callback closure.

`terminate!` remains available for interactive control and produces a successful terminated
return code.

### Symbolic remake and runtime updates

```julia
remake(
    prob;
    u0 = prob.u0,
    p = [],
    tspan = prob.tspan,
    seed = prob.seed,
    replica = prob.replica,
)
```

`remake` returns a new problem and accepts partial symbolic maps. It cannot replace the executable,
capacity, engine, backend, scalar type, or structural parameter. A new executable requires an
explicit new `PottsProblem`.

Problem parameter replacement is out-of-place. A running integrator may support SII `setp` only:

- at a settled complete-MCS boundary;
- for compiler-proven runtime parameters;
- after type, shape, unit, range, and scalar-conversion validation;
- as one atomic parameter transaction effective at the next MCS; and
- with the update stored in checkpoint and parameter-timeseries provenance.

Direct mutation of `prob.p`, compiled constants, component tuples, or device storage is not public
behavior. Protocol-controlled changes and ProcessBigraph external inputs use the same internal
parameter transaction rather than separate mutation paths.

### Solution contract

`PottsSolution <: SciMLBase.AbstractTimeseriesSolution` should implement the actual collection and
SII contracts:

- `u`, `t`, `prob`, `retcode`, statistics, diagnostics, provenance, and storage metadata;
- exact symbolic state and observation indexing;
- `getp` for fixed parameters and recorded parameter timeseries;
- exact integer saved-MCS lookup;
- `SciMLBase.successful_retcode`;
- no dense interpolation;
- no hidden recomputation or device transfer when indexing an unsaved observable; and
- one structured error for unknown versus known-but-unsaved symbols.

The solution should report the selected executable engine/backend/scalar configuration rather than
an algorithm passed to `solve`.

### V1 checkpoint contract

The current `CanonicalCheckpoint` implementation contains valuable logical-state, RNG,
fingerprint, integrity, and completed-MCS mechanisms. V1 should extract those mechanisms into a new
`PottsCheckpoint` contract:

```julia
cp = checkpoint(integrator)
integrator = init(prob; checkpoint = cp)
```

The V1 checkpoint:

- is captured only at a settled complete-MCS boundary;
- contains executable identity, logical state, runtime parameters and parameter history, RNG seed,
  replica and continuation, MCS, schema, replay class, and checksum;
- excludes scratch workspaces, live kernels, Symbolics values, external systems, registries, and
  arbitrary Julia serialization;
- supports portable logical reconstruction on a qualified backend where the declared replay class
  admits it; and
- requires the exact continuation envelope for exact replay.

The branch has no migration obligation. It should not retain a reader, converter, alias, or wrapper
for the current checkpoint schema. Existing checkpoint semantic assertions should be ported to the
new schema.

## Finding 5 — The public surface needs an ownership policy, not another registry

Julia 1.12 distinguishes exported names from qualified `public` names. V1 should use that directly.
It should not create a generated API registry, migration list, or compatibility alias file.

### PottsToolkit exports

Export values needed in ordinary model source:

- `PottsSystem`, `PottsExecutable`, `PottsInitialState`, `PottsProblem`, `PottsIntegrator`,
  `PottsSolution`, and `PottsCheckpoint`;
- `complete`, `iscomplete`, `compile`, `init`, `solve`, `solve!`, `step!`, `terminate!`, and
  `remake`;
- `compose`, `extend`, `flatten`, and `substitute`;
- the accepted statement, symbolic-operation, domain, effect, schedule, solver-policy, and
  high-level component constructors;
- `StatementRegistry`, `default_statement_registry`, and the one registered-statement entry;
- the canonical initial ownership/layout constructors;
- `SequentialEngine`, `CheckerboardEngine`, and admitted backend descriptors;
- `inspect` and common inspection selectors;
- `EquationComponent` and `process_component`; and
- thin authoring macros such as `@statements`.

### Qualified public PottsToolkit names

Mark as `public`, but do not export:

- source/provenance and structured diagnostic records;
- qualified statement, access, effect, RNG, schedule, capability, storage, kernel, and interface
  manifest records;
- fingerprint value types and canonical serialization helpers intended for extensions;
- SII index-map and parameter-buffer support types;
- statement traversal/reconstruction extension functions;
- registered-statement schema hooks; and
- backend and ProcessBigraph adapter hooks.

### Private names

Keep private:

- compiler pass types;
- mutable lowering builders;
- storage arrays and workspaces;
- kernel functions and launch geometry;
- concrete extension adapter types;
- cache keys;
- namespace rewrite helpers;
- generated-function helpers; and
- CorePotts internal transaction implementations.

### CorePotts

CorePotts should expose a narrow qualified public compiler/runtime interface centered on:

- `CompiledPottsProgram`;
- runtime initialization and whole-MCS advance;
- logical state and checkpoint import/export;
- backend capability and execution reports; and
- explicit extension hooks required by backend packages.

PottsToolkit must not re-export CorePotts storage, workspace, kernel, tracker, request, transaction,
or coupled-schedule types. CorePotts's current hundreds of exports are not a V1 compatibility
constraint.

The source `export` and `public` blocks are the authority. Ordinary tests may assert the curated
inventory and forbidden stale names directly; no versioned API ledger is needed.

## Finding 6 — File impact should distinguish extraction from preservation

The clean break does not authorize throwing away scientifically qualified mechanisms. It does
authorize deleting their old authoring and scheduling authorities.

### Root PottsToolkit

| Current path | V1 disposition |
|:--|:--|
| `src/authoring/**` | Replace with V1 system, statements, completion, compiler, runtime-facing initial-state, and inspection modules |
| `src/reference_models/**` | Delete; replace with visible test fixtures, not package model builders |
| `src/compatibility.jl` | Delete |
| `src/PottsToolkit.jl` | Replace imports, includes, exports, and public inventory |
| `src/precompile.jl` | Replace with one tiny sequential and one tiny checkerboard compile workload after measurement |
| `src/public_api_docs.jl` | Replace only as needed for V1 docstrings; do not write user-facing tutorials |
| `ext/PottsToolkitUnitfulExt.jl` | Retain concept, rewrite against V1 units/solution boundary |
| new MTK/PB extensions | Add exactly as accepted in SPV1-034 through SPV1-042 |

### CorePotts retain and adapt

Retain mechanisms, with names/files changed as needed:

- topology, Cartesian relations, and boundary realization;
- logical state, IDs, capacities, and lifecycle generation safety;
- semantic RNG and addressed draws;
- proposal/acceptance inner-loop mechanisms;
- sequential and checkerboard kernels;
- relationship request collection, conflict resolution, and atomic commit;
- field, history, lifecycle, mechanics, query, observation, and tracker kernels required by V1;
- logical initialization and overlap validation;
- the sequential reference implementation;
- backend execution plans and capability reporting;
- logical checkpoint integrity and restore mechanisms; and
- scientific assertions covering those mechanisms.

### CorePotts extract, then delete the old authority

Extract reusable runtime mechanisms from:

- `coupled/dynamic_state*`;
- `coupled/continuous*`;
- `coupled/native_fields.jl`;
- `coupled/relationships*`;
- `coupled/history.jl`;
- `coupled/polarity*`;
- `coupled/events.jl`;
- `coupled/observations.jl`;
- `coupled/persistence.jl`; and
- the reusable parts of `coupled/execution.jl` and `coupled/preflight.jl`.

After extraction, delete the coupled declaration, plan, schedule, semantic-kernel, and public
dispatch authority. The qualified V1 compiler becomes the only producer of runtime descriptors.

### CorePotts delete without replacement

- `algorithms/lottery.jl`
- `algorithms/tiled_checkerboard.jl`
- `algorithms/tiled_checkerboard_device.jl`
- `coupled/process_bigraph_adapter.jl`
- `persistence/process_bigraph_conversion.jl`
- `coupled/merks2006.jl`
- `coupled/shirinifard2012.jl`
- `coupled/activity_problem.jl`
- compatibility-only contracts, aliases, exports, and legacy checkpoint readers

Replace `sciml/interface.jl` around `PottsExecutable` and the accepted V1 problem contract rather
than wrapping the current `PottsModel` interface.

### MakiePotts and integration

MakiePotts may be adapted to the V1 solution, state, and observation interfaces where required to
keep the package family coherent. This is runtime integration, not user-facing documentation.

Active root and integration tests tied solely to `PottsModel`, `ModelFragment`,
`AbstractRuleExpression`, Lottery, tiled execution, paper builders, compatibility, evidence
archives, or transition oracles should be deleted or archived out of the required runner.
Scientific assertions that remain relevant should be rewritten against V1 behavior.

The ProcessBigraphs package and its independent tests are not generally in this clean-break
rewrite. Only a minimal public-protocol change proven necessary for the optional Potts extension is
in scope.

## Finding 7 — The QA gate should be strict but ordinary

The user has explicitly rejected evidence freshness, one-time release qualification, compatibility
oracles, and expensive finicky CI. Normal high-quality Julia package practice supports that
decision.

### Required pull-request jobs

1. PottsToolkit package tests on the supported Julia version and Linux.
2. CorePotts package tests on the supported Julia version and Linux.
3. ProcessBigraphs and MakiePotts package tests when the shared repository CI normally covers
   them.
4. One integration job loading ModelingToolkit, ModelingToolkitStandardLibrary,
   ProcessBigraphs, and Unitful extensions.
5. macOS and Windows fresh-environment smoke tests that load the package and run one tiny
   sequential CPU trajectory.
6. One package-quality job or test group containing stable static QA.

### Required stable QA

- `Aqua.test_all` with no new ambiguity, undefined export, stale dependency, unbound type
  parameter, piracy, or persistent-task allowlist;
- ExplicitImports ownership, explicit-import, public-access, and stale-import checks;
- no stale legacy exports, imports, includes, precompile workloads, or test references;
- targeted `@inferred` checks at completion-to-IR, IR-to-runtime, proposal, RNG, relationship
  transaction, and whole-MCS boundaries;
- zero or explicitly bounded warmed CPU allocations for selected hot paths;
- deterministic same-seed/same-replica replay and different-replica divergence;
- a plain public API black-box test from authoring through solution access; and
- optional-extension absence and activation tests in fresh Julia processes.

Package-wide JET should not initially be a required PR gate. It is valuable as a manual analysis,
but dependency-origin reports and version sensitivity can make it noisy. Targeted `JET.@test_opt`
may become required only for a stable owned function barrier with no external false-positive
allowlist.

### Performance, GPU, coverage, and docs

- Wall-clock benchmarks and baseline comparisons remain manual or scheduled, not PR gates.
- Allocation caps may be PR gates because they are substantially less noisy than elapsed time.
- GPU validation remains manual or hardware-dispatched. A backend claim is made only after its
  actual hardware tests pass; missing hardware does not fail CPU work or docs.
- Coverage may be uploaded from one Linux job. If a hard project threshold is retained, use one
  simple threshold no higher than 90%, with no per-file freshness or patch ratchet.
- User-facing documentation and browser QA remain outside this V1 branch. The docs workflow is not
  a V1 acceptance gate. A merge that intentionally breaks living public docs must wait for or be
  paired with the later documentation phase; this branch must not add migration documentation.

### Main-branch reference

During implementation, the agent may clone the exact main branch into a temporary directory for
read-only inspection and spot comparisons. It must not:

- run a parity harness against it;
- copy old APIs or tests as compatibility authority;
- create expected-output archives from it;
- add it to CI; or
- retain the clone or its generated artifacts in the repository.

The V1 spec and ported scientific assertions remain the test authority.

## Finding 8 — Scoped supersession must be explicit

The consolidation specification should include this disposition:

| Existing authority | V1 disposition |
|:--|:--|
| `pottstoolkit-authoring-composition-and-api-semantics.md` | Superseded for model types, levels, fragments, ports, algorithms, problem construction, compatibility, migration, API, serialization, and qualification |
| `pottstoolkit-rule-and-model-semantics.md` | Superseded for the handwritten rule IR, host/expert escape paths, authoring API, migration, and old compiler; scientific snapshot/effect meaning survives only where incorporated by V1 or another scientific spec |
| `sciml-interface-semantics.md` | Superseded for `PottsModel`, solve-time algorithm/backend selection, compilation cache, generic callbacks, old parameter handles, legacy evacuation, and checkpoint migration; absolute integer MCS, saving, solution, ensemble, and return-code semantics survive where not in conflict |
| `corepotts-public-interface-semantics.md` | Superseded for export and extension inventory; scientific runtime behavior survives through the applicable domain specifications |
| `phase-14-semantic-kernel.md` and registry contracts | Superseded as authoring, coupled-plan, and compiler architecture; scientifically accepted mechanism semantics remain input to V1 |
| `published-model-reproduction-semantics.md` | Paper mechanisms, parameters, stochasticity, and observables remain; hidden model builders and legacy authoring fixtures are superseded |
| `semantic-preserving-consolidation-contract.md` | Superseded for compatibility aliases, old dependency direction, evidence preservation, requalification, and migration; it remains historical consolidation evidence |
| ProcessBigraph specifications | Remain authoritative for ProcessBigraphs itself; statements placing the Potts adapter in CorePotts are superseded by the accepted PottsToolkit extension direction |
| checkpoint migration and historical authoring serialization clauses | Superseded; V1 starts a new schema with no reader or migration obligation |

Historical specifications and evidence should remain in the repository and index. They do not
remain living implementation instructions for V1.

## Alternatives and tradeoffs for the interview

### Compile at `init`

Rejected recommendation. It preserves familiar SciML algorithm selection but erases the accepted
`PottsExecutable` boundary and makes engine/backend capability a runtime surprise.

### Give `compile` defaults

Possible but not recommended. Requiring engine, backend, and scalar type makes scientific and
performance choices visible in canonical code.

### Let users mark structural parameters

Useful as intent metadata but unsafe as authority. Compiler dependency analysis must decide.

### Keep capacity in `PottsProblem`

Rejected recommendation. Capacity changes storage, relationship bounds, workspace sizes, and
device allocation; it is structural.

### Derive a new seed per ensemble trajectory

Possible but less transparent than keeping one master seed and making replica identity explicit in
the RNG address.

### Continue allowing host callbacks

Rejected recommendation. Arbitrary callback mutation bypasses the accepted effect, phase, unit,
checkpoint, and deterministic replay contracts. Symbolic events and protocols cover V1 control.

### Preserve current checkpoint readers

Rejected recommendation under the owner's clean-break instruction. Port scientific checkpoint
tests, not format compatibility.

### Keep all CorePotts exports for advanced users

Rejected recommendation. Qualified `public` names provide an advanced interface without injecting
hundreds of internal names into every `using CorePotts` namespace.

### Require package-wide JET and hard timing budgets

Rejected recommendation for the first V1 gate. Both can produce expensive, dependency-sensitive
maintenance. Targeted inference/allocation tests plus manual analysis provide better signal.

### Delete every coupled file immediately

Rejected recommendation. Relationship, field, lifecycle, history, checkpoint, and transaction
mechanisms are scientifically valuable. Extract them behind `CompiledPottsProgram`, then remove the
old declarations and scheduler.

## Proposed Round 4 decisions

The next interview can present five decisions:

1. **Executable and compilation contract**  
   Accept explicit engine/backend/scalar compilation, immutable `PottsExecutable`, no public
   compilation cache, and no solve-time algorithm selection.

2. **Parameter, initial-state, problem, and RNG contract**  
   Accept compiler-proven structural/runtime roles, the proposed `PottsInitialState`,
   experiment-only `PottsProblem`, structural capacity, and explicit seed-plus-replica addressing.

3. **SciML runtime, solution, ensemble, and checkpoint contract**  
   Accept `solve(prob)`, the narrow solve keyword set, symbolic `remake`, settled-boundary runtime
   parameter transactions, true SII solution behavior, and a new V1-only checkpoint schema.

4. **Public API and clean-break source disposition**  
   Accept export/public/private ownership, the narrow CorePotts interface, the deletion/extraction
   map, paper fixtures instead of builders, and MakiePotts runtime adaptation.

5. **Tests, CI, reference use, and supersession**  
   Accept ordinary package/integration/platform QA, stable Aqua/ExplicitImports/inference/allocation
   gates, manual GPU/performance analysis, simple coverage, no docs gate, read-only temporary main
   reference, and the scoped supersession table.

## Readiness judgment

The next owner interview is ready.

The recommendations intentionally reduce runtime degrees of freedom:

- compilation fixes scientific engine and backend;
- problem construction supplies experiment data;
- solve executes rather than recompiles;
- runtime replacement is compiler-proven;
- state mutation remains inside typed transactions;
- one curated public surface replaces hundreds of exports;
- qualified mechanisms survive without their legacy DSL;
- ordinary tests replace oracles and evidence bureaucracy; and
- old specifications remain historical without directing V1 implementation.

No implementation work was performed by this research.
