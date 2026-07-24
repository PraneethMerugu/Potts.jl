# SciML Problem, Integrator, Solution, and Ensemble Semantics

Status: Accepted

## Purpose

This document defines genuine SciML integration for Potts.jl. It governs the relationship among
`PottsModel`, `PottsProblem`, algorithms, integrators, solutions, callbacks, saving, remaking, and
ensembles.

Using SciML names without their expected behavior is not conformance. Potts.jl participates in the
applicable SciMLBase interfaces while rejecting options whose meaning does not apply to Cellular
Potts dynamics.

The accepted rationale and implementation boundary are recorded in
[Decision 0025](decisions/0025-phase-9-sciml-and-gpu-interface.md).

## Model and Problem Ownership

### PottsModel

A `PottsModel` is an immutable reusable scientific description containing:

- Cell types and medium domains
- Properties and parameters
- Energy components
- Rules and biological events
- Scientific relations and boundary semantics
- Field coupling
- Capability requirements

It contains no realized initial lattice, live state, device arrays, run seed, or time span.

### PottsProblem

`PottsProblem` is an immutable subtype of the appropriate `SciMLBase.AbstractSciMLProblem`. It binds
one model to a concrete experiment:

- Initial state or typed initializer
- Concrete geometry, lattice dimensions, and spacing
- Integer-MCS time span
- Maximum cell capacity
- Master seed and RNG contract
- Problem-specific typed parameter values

Solving creates mutable execution state but does not alter the problem. Immutable internal data MAY
be shared; mutable initial data follows explicit copy and ownership rules.

The problem remains portable across qualified backends. Backend selection is not part of model
meaning.

The canonical direct constructor is:

```julia
PottsProblem(model, u0, geometry, tspan;
    p = default_parameters(model), capacity = nothing, seed = 0, kwargs...)
```

The four positional values define the essential experiment. Algorithm, backend, reproducibility,
saving, callbacks, progress, and execution tuning are solve-time choices. `tspan = (t0, t1)` uses
nonnegative integers with `t1 >= t0`; `u0` is the finalized state at `t0`, and the first step
completes MCS `t0 + 1`. RNG addresses and every schedule use absolute MCS rather than a counter
reset to zero.

Capacity is fixed before compilation. When the model cannot create cells, an omitted capacity MAY
resolve to the number of initially active cells. A model capable of division or another
cell-creating effect requires explicit capacity. CorePotts never guesses headroom or resizes a live
GPU state.

### Parameters and initial state

`prob.p` is a typed parameter container with accepted parameter handles. It is not an untyped
dictionary and is not mutated directly; numerical changes use `remake`.

The model owns parameter declarations, defaults, and stable handles; the problem owns the concrete
typed values for one experiment. Every parameter declares whether it is runtime numerical data,
shape/capacity data, structural data, or measured-and-justified compile-time static data. Ordinary
numeric values are not lifted into type parameters merely for convenience.

`prob.u0` MAY be a complete validated initial state or a typed initializer/layout description.
`init` realizes it deterministically. Initialization randomness uses a named semantic stream and
does not shift later dynamics draws.

Direct Level 3 construction MAY supply backend-resident initial state. Its backend must be
unambiguous and compatible with explicit solve selection. Mixed or contradictory storage is an
error.

Ordinary mutable host inputs are copied into a problem-owned immutable logical snapshot. Every
`init` realizes independent mutable execution state. Expert device input uses an explicit typed
ownership wrapper such as `DeviceInitialState(state, CopyInitialState())` or
`DeviceInitialState(state, AliasInitialState())`; copying is the default. Aliasing binds execution
to that backend, prohibits concurrent solves over the same storage, records the mutation promise in
provenance, and is never inferred merely because an input contains GPU arrays.

### Permanent name ownership and legacy evacuation

The final `PottsProblem`, `PottsIntegrator`, and `PottsSolution` names belong exclusively to this
replacement interface. Historical concrete types are renamed to explicitly internal legacy names
before the final bindings are introduced. Existing PottsToolkit constructors MAY temporarily return
the renamed legacy problem only through the frozen containment boundary until Phase 10 replaces
their compiler. The bridge gains no features, is never a replacement fallback, and is deleted at
typed-compiler parity. No provisional `ScientificPottsProblem` family is introduced.

## SciML Initialization and Solving

CorePotts implements the applicable `SciMLBase.__init` and `SciMLBase.__solve` extension points so
SciML's common checking and error handling remain available.

The governing relationship is:

```julia
solve(prob, alg; kwargs...) = solve!(init(prob, alg; kwargs...))
```

One-shot and interactive execution therefore share validation, compilation, initialization,
callbacks, saving, and result construction.

`init` may validate, compile, realize state, adapt storage, allocate workspaces, initialize
mechanics and callbacks, and perform a requested MCS-start save. It never advances an MCS. Device
initialization remains asynchronous unless a declared host observation, initial host save,
validation result, or failure record requires synchronization; that boundary is recorded.

The Monte Carlo algorithm is an ordinary immutable value passed separately:

```julia
solve(prob, LotteryCPM(...))
```

The Phase 7 stable algorithm vocabulary is:

- `SequentialCPM`: conventional modified-Metropolis reference dynamics;
- `SequentialEquilibrium`: sequential Metropolis-Hastings equilibrium sampling when the complete
  model satisfies its capability requirements;
- `CheckerboardSweepCPM`: randomized-color, once-per-site parallel sweep dynamics; and
- `LotteryCPM`: topology-calibrated, conflict-resolved parallel dynamics.

Intrinsic or subgroup kernels are implementations of one of these algorithms when they preserve
the complete contract. If they change transactions, RNG identities, state freshness, or observable
results, they require another algorithm name and guarantee profile.

`solve(prob)` and `init(prob)` without an explicit algorithm select `SequentialCPM`. Backend choice
MUST NOT silently select different scientific dynamics. Selecting a GPU with this default emits one
informational message during integrator construction, before the first MCS, explaining that the
sequential process is intentional and naming compatible explicit parallel alternatives. The message
uses Julia's logging system, occurs once per integrator construction, and never changes the selected
algorithm.

Algorithm compatibility is checked during `init`, before device adaptation or expensive compilation
where possible. Diagnostics report all known incompatible components, topology, dimension,
reproducibility, numerical, and backend requirements together.

Validation is staged. Model construction validates scientific declarations; problem construction
validates geometry, initial state, parameters, capacity, time, and seed; `init` validates the full
model--algorithm--backend--numerical--RNG--observation combination. Each stage reports all
independently discoverable incompatibilities together.

Algorithms conform through open dispatch rather than a central concrete-type union. The algorithm
owns scheduling, proposal budget, ordering, and conflicts. An `AbstractProposalLaw` owns candidate
sampling and forward/reverse probabilities, and produces an immutable attempted-transition value
for scientific evaluation. Neighboring ownership copy is the first built-in law, not the universal
representation of every future transition.

## Backend and Reproducibility Selection

Backend selection is an `init`/`solve` execution choice:

```julia
solve(prob, alg; backend = MetalBackend())
```

Host initial data is adapted during `init` only after model, problem, algorithm, numerical, RNG, and
backend validation.

Portable problems default to `KernelAbstractions.CPU()`. CorePotts never selects a GPU because one
is installed. An expert device initial state may infer its backend only when selection is omitted
and the complete storage tree has one unambiguous backend. A contradictory explicit backend is an
error.

The seed belongs to the problem:

```julia
prob = PottsProblem(model, initializer, geometry, (0, 1_000); capacity = 4_096, seed = 42)
```

The requested reproducibility profile belongs to `init`/`solve`, allowing one problem to be examined
under different qualified profiles:

```julia
solve(prob, alg; reproducibility = StrictReproducibility())
```

Typed profile values are foundational. Symbols MAY be accepted as convenient aliases. Execution
never silently downgrades the requested profile.

Ordinary single-trajectory `solve` does not override the problem seed. A different trajectory uses
`remake(prob; seed = ...)`. Ensemble `seed` is separately the ensemble master seed.

Workgroup sizes, queues or streams, kernel variants, AcceleratedKernels tuning, subgroup
implementations, and launch decomposition belong to a typed execution policy. They are provenance,
not scientific identity, only when the requested profile proves invariance. Automatic tuning may
choose only among already qualified equivalent implementations.

Backend capabilities and identities use typed open dispatch rather than symbols or a closed family
enum. CPU, Metal, and ROCm remain the qualified production set until explicitly revised. Exact
checkpoints record stable package, backend, device, and runtime identity.

The `backend` keyword is reserved for computation. Output destination and retention use the
separate `storage` keyword and typed policies such as `MemoryStorage`, `ZarrStorage`, and
`HDF5Storage`:

```julia
solve(
    prob,
    alg;
    backend = MetalBackend(),
    storage = MemoryStorage(),
)
```

Historical output types named `MemoryBackend`, `ZarrBackend`, or `HDF5Backend` are not part of the
final API. Storage selection never selects execution hardware or scientific dynamics.

## PottsIntegrator

`init` returns a mutable `PottsIntegrator` owning:

- Current compiled state
- Current integer MCS
- Algorithm and scientific guarantee profile
- Source problem or sufficient immutable provenance
- Compiled model and execution plan
- Backend, workspaces, and execution policy
- RNG contract and current semantic position
- Callback and saving state
- Diagnostics and current return code

Mutable execution cannot alter the source model or problem.

`PottsIntegrator` is not an ODE-specific `DEIntegrator`. It exposes the applicable common surface:
a read-only scientific `u` view, read-only live `p`, integer `t`, `prob`, `alg`, output accumulator,
status, and retcode. Authoritative mutation uses documented operations. Destructive iteration, when
used, advances the same complete one-MCS operation until terminal status.

### Stepping

```julia
step!(integrator)
```

advances exactly one MCS and returns the integrator.

```julia
step!(integrator, n)
```

accepts a nonnegative integer and advances exactly `n` MCS. Floating durations are rejected.

Internal checkerboard colors, lottery rounds, proposal batches, field substeps, and kernel launches
are not public steps. They never change the meaning of `step!`.

The public step includes proposal/mechanics execution, lifecycle commit, MCS advancement, due
observations and saves, discrete callbacks and accepted controls, and final invariant/status
bookkeeping. `solve!` is a loop over this same step. A private `perform_mcs!`-like algorithm hook may
implement the inner transition but is not a second public stepping path.

Stepping after `Success`, `Terminated`, or `MaxIters` throws `IntegratorTerminatedError`. Calling
`solve!` on a terminal integrator returns its existing finalized solution without duplicate saves,
callbacks, or launches. Calling it after manual steps continues normally because those steps already
performed their due boundary work.

`reinit!` MAY later support efficient repeated execution, but it requires explicit behavior for new
initial state, seed, parameters, caches, callbacks, and output. It does not block the first stable
refactor.

## Time and Solver Options

Public time is integer MCS. `integrator.t`, problem `tspan`, schedules, callback boundaries, and
`saveat` use integer MCS values.

A floating endpoint MAY be accepted only when exactly integral and converted without ambiguity.
Otherwise construction fails with an informative error.

Public `dt` is one MCS. Auxiliary physics MAY have accepted internal substeps but those do not
redefine CPM time.

Options such as adaptive stepping, `abstol`, and `reltol` are rejected rather than accepted and
ignored. Potts.jl does not pretend to have continuous adaptive local-error control.

The solver keyword set is explicit. Applicable common keywords receive documented Potts meanings;
continuous or adaptive options and unknown keywords throw targeted errors. Algorithm-specific
controls belong to algorithm constructors and backend-specific controls to typed execution values.

`maxiters` is a safety limit distinct from `tspan`. Reaching it before the requested final MCS
returns a solution with `SciMLBase.ReturnCode.MaxIters`.

It counts completed public MCS steps only. When omitted, it does not stop execution before the
number of MCS required by `tspan`; an explicitly smaller value yields a finalized partial solution.

## Remaking Problems

`SciMLBase.remake(prob; ...)` returns a new immutable problem and MAY replace:

- Model
- Initial state or initializer
- Typed parameters
- Geometry
- Time span
- Capacity
- Seed

It does not mutate shared arrays implicitly.

Numerical changes, including compatible parameter or seed changes, reuse compilation when safe.
Structural changes to schemas, topology, dimension, rule/effect graph, components, query set, or
algorithm structure invalidate the affected plan.

Scientific and compilation fingerprints are distinct. The scientific fingerprint covers every
trajectory-relevant value. The structural compilation key covers only types, shapes, schemas,
dimensions, topology, relations, component/effect structure, numerical policy, algorithm
requirements, observation plan, and backend capabilities which affect generated execution.

An optional explicit `PottsCompilationCache` owns thread-safe reusable artifacts. It contains no
trajectory state, RNG position, callbacks, output, or live workspaces; has ordinary `empty!`,
`length`, `show`, and memory-reporting behavior; has no hidden global singleton or implicit disk
storage; and initially performs no automatic eviction. Correctness is identical without it.

Invalidation is dependency directed:

- seed, time span, progress, and schedule-only saving/callback changes reuse scientific
  compilation when their declared observation requirements are unchanged;
- compatible numerical parameter changes reuse kernels/workspace shapes and refresh affected
  backend parameter storage;
- compatible `u0` changes reuse model compilation and shapes but rebuild state, trackers, and
  initialization-dependent mechanics;
- geometry, dimension, topology, relations, schema, capacity, numerical types, component/lifecycle
  graph, or observation requirements invalidate dependent products; and
- backend changes reuse portable host normalization but not backend-specific compiled artifacts.

Algorithms remain solve-time values rather than `remake` fields. Algorithm-independent products
MAY be shared, while plans and workspaces are keyed separately. Ambiguous or undeclared
dependencies disable reuse rather than guessing.

Explicit integrator-time parameter changes use documented operations at accepted MCS phase
boundaries; direct mutation of `prob.p` is not their implementation.

## Saving

The default schedule is `save_start = true`, `save_end = true`,
`save_everystep = false`, and `saveat = ()`. Large 2D/3D lattices are not copied after every MCS
unless requested.

SciML `saveat` is supported at integer MCS values. A positive scalar integer denotes a regular MCS
interval. Nonintegral save times are rejected until a corresponding state meaning exists.

Collection values are normalized to sorted unique boundaries and values outside `tspan` throw.
`save_start` and `save_end` are unioned with `saveat`. Coincident requests produce one record unless
an explicitly named before/after-control policy requires semantically distinct entries.

`save_start` and `save_end` follow normal SciML expectations. `save_everystep = true` saves every
MCS, not every internal algorithm round.

Dense interpolation is not advertised. Cellular ownership has no accepted state between integer MCS
snapshots, so Potts solutions do not fabricate linear interpolation between cell labels.

`sol(t)` returns the exact available saved state at integer MCS `t`; an unavailable MCS throws
`UnsavedTimeError`. It never silently interpolates or implicitly observes ownership.

Saving does not require every full state to be copied to host memory. A policy MAY:

- Keep qualified device snapshots
- Transfer full or selected state
- Save only scientific observables
- Stream frames to an output storage policy
- Use out-of-core storage

The solution reports what was retained and where. Saved entries are immutable snapshots or stable
snapshot handles, not aliases to live integrator storage.

The default snapshot policy makes an independent copy in the execution backend's memory: CPU
snapshots remain on CPU and GPU snapshots remain device resident. Host materialization is explicit
and recorded. Typed host, observable-only, streaming, and out-of-core policies MAY replace the
default.

## PottsSolution

A Potts solution subtypes the appropriate `SciMLBase.AbstractSciMLSolution` and exposes as
applicable:

- `t`
- `u`
- `prob`
- `alg`
- `retcode`
- Diagnostics and statistics
- Reproducibility and model provenance
- Storage metadata

Saved scientific quantities are requested with typed observable handles, not strings:

```julia
sol = solve(
    prob,
    alg;
    saveat = 10,
    observables = (volume, cell_type, boundary_measure),
)
```

An observable requested before execution may be maintained or evaluated efficiently at declared
observation boundaries. Applicable SciML symbolic indexing such as `sol[volume]` retrieves the
saved series. An unknown or unsaved observable is a structured error and does not initiate hidden
computation, transfer, or synchronization.

When it subtypes `AbstractTimeseriesSolution`, it implements that collection contract rather than
using the name only for branding. `sol[j]` is the `j`th saved entry and `sol.t[j]` its MCS.
`sol(t)` performs exact saved-MCS lookup; an unavailable MCS throws `UnsavedTimeError`. `sol[t]`
retains ordinary collection indexing. Dense, nearest, and between-MCS interpolation are unsupported.

Solution provenance records model/problem identity, algorithm guarantee, backend qualification,
seed and RNG contract, return code, storage policy, execution statistics, observation/sync/transfer
counts, model/schema/topology/initial-state fingerprints, and checkpoint ancestry where applicable.

Every completed solution has a meaningful return code. It does not remain at `ReturnCode.Default`.

- Normal completion: `ReturnCode.Success`
- Deliberate user termination: `ReturnCode.Terminated`
- Safety limit reached: `ReturnCode.MaxIters`

### Identity-aware cell series

Per-cell saved values use a ragged identity-aware `CellSeries`. Each entry is a `CellValues`
collection keyed by stable cell identity including generation, never by a reusable dense storage
slot. Cells may appear and disappear between frames. An absent lifetime is not filled with zero, and
slot reuse cannot splice unrelated biological cells into one trajectory. Lineage metadata supports
explicit parent, daughter, ancestor, and descendant analysis where it was requested or retained.

### Typed reduction observables

Population summaries are immutable observable expressions, for example:

```julia
mean(volume; over = Tumor)
count(cells(Tumor))
sum(contact_measure; between = (Tumor, Stroma))
```

Construction does not compute the reduction. Its population selection, uniqueness, weighting,
empty behavior, metric, and accumulator policy are semantic data. When requested during a GPU
solve, a qualified reduction remains device resident and transfers only its declared small result
at the observation boundary.

### Tables and materialization

`observation_table(sol, observables...)` returns a Tables.jl-compatible long-form view. Per-cell
rows include applicable MCS, stable cell identity, generation, cell type, and requested values.
Potts.jl does not require DataFrames, CSV, Arrow, or a plotting package; their normal Tables.jl
interfaces consume the view. A unit-bearing solution view adds calibrated columns and metadata
without dropping original MCS or lattice quantities.

Analysis never hides transfer of GPU-resident scientific data. Full cell tables, ownership arrays,
or device-resident series require an explicit materialization operation such as
`materialize(values, CPU())`. Post-hoc derivation from retained snapshots uses an explicit
`observe(sol, observable; backend)` operation that reports whether values were already available,
recomputed, transferred, or synchronized. Display, symbolic indexing, and metadata queries do not
materialize a GPU trajectory.

### Optional physical-unit view

Model authoring, normalized IR, execution state, and kernels use plain numerical values under the
accepted numerical policy. Unitful integration is a solution-side Julia package extension and is
not a CorePotts execution dependency.

```julia
scale = PhysicalScale(
    lattice_spacing = (0.5u"μm", 0.5u"μm"),
    mcs_duration = 2u"s",
)

physical_sol = with_units(sol, scale)
```

`PhysicalScale` is immutable. Spacing may be anisotropic and must match the solution dimension. No
length, time, energy, concentration, or other scale is inferred. `mcs_duration` is explicitly an
empirical user-supplied calibration rather than an intrinsic interpretation of MCS. Calibration
method, citation, and notes MAY be attached as analysis provenance.

`with_units` returns a lazy immutable `UnitfulSolutionView` sharing its parent solution. It does not
copy snapshots, alter stored values, synchronize a device, rerun execution, or change the parent
solution fingerprint. `parent(view)` returns the original solution, `mcs(view)` returns its integer
MCS axis, and `view.t` returns the calibrated physical axis when a time calibration exists.

An exact lookup by unitful physical time MAY convert through the declared calibration and then use
the existing exact saved-MCS lookup. It never introduces dense, nearest, or between-MCS
interpolation.

Units attach only to observables with enough semantic information for a valid conversion.
Coordinates use declared lattice spacing; 2D area and 3D volume use the applicable spacing product;
concentration and other dimensions require their own declared scale. Owner labels, raw site counts,
and raw contact-edge counts remain dimensionless. A boundary value converts to physical length or
area only through its declared normalized or physical metric estimator. Missing conversion meaning
is a structured error rather than a guessed unit.

Post-hoc calibration produces a separate analysis-provenance layer containing the parent solution
fingerprint, physical scale, calibration method or citation, relevant extension versions, and
derived-observable definitions. Several calibrated views may coexist for one solution. Paper-facing
exports retain both original MCS/lattice quantities and calibrated quantities so they cannot be
confused with execution inputs.

`SciMLBase.successful_retcode(sol)` works through the standard trait. `Success` and deliberate
`Terminated` are successful outcomes.

### Throwing versus returning

The following throw before or during execution rather than returning a misleading solution:

- Invalid model, problem, algorithm, backend, or solver option
- Structured cell-capacity exhaustion
- Broken state or transaction invariants
- Unsupported required capability
- Device execution or compilation failure
- Output or persistence failure

Expected deliberate termination returns a valid solution with `Terminated`. Reaching `maxiters`
returns a partial solution with `MaxIters`.

## Biological Events and SciML Callbacks

Division, death, transition, growth, property updates, and field coupling are model components with
accepted snapshot, effect, and transaction semantics. They are not implemented as generic SciML
callbacks.

SciML callbacks provide external observation and control, including:

- Custom observation and saving
- Termination
- Declared parameter changes at MCS boundaries
- Coupling to another accepted solver
- User-requested monitoring

`DiscreteCallback` and `CallbackSet` are supported. Continuous callbacks, root finding,
interpolation-based conditions, and continuous event localization are rejected because no accepted
ownership state exists between integer MCS boundaries.

Callback conditions observe a consistent documented integer-MCS boundary after the MCS and accepted
event phases.

A host callback that requires device data creates a declared synchronization boundary. A qualified
device-compatible callback MAY remain resident. Callback synchronization and residency appear in
the execution report.

An ordinary SciML `DiscreteCallback` is a host callback. All standard host callbacks due at a
boundary share one immutable host analysis snapshot and one recorded synchronization/materialization
boundary; its condition receives that snapshot, integer MCS, and the live integrator. GPU
initialization emits one informational cost notice and names the typed device alternative.

A device callback declares required observables, condition, permitted control effect, schedule,
priority/dependencies, and capabilities. It lowers during `init` into concrete bounded descriptors
and workspaces. Its kernels contain no host closures, dynamic dispatch, allocation, exceptions,
dictionaries, or arbitrary host objects.

Callbacks do not mutate lattice or cell state arbitrarily. Scientific changes use typed effects or
documented integrator operations so trackers, RNG, provenance, and invariants remain consistent.

Stable callback controls are termination; requested save, observation, snapshot, or checkpoint;
and typed parameter changes through stable handles effective at the documented next-MCS boundary.
Evolving-field changes require the separately specified coupling protocol.

`terminate!(integrator)` is supported and yields `ReturnCode.Terminated` with final saving governed
by the selected options.

Scientifically interacting callback effects use explicit priority or dependency semantics, or are
rejected when conflicting. Accidental vector order is not a conflict law. Pure observations use a
documented deterministic order.

Conditions observe the completed post-lifecycle state. The ordinary scheduled save occurs before
callback control effects. Pure observations execute in deterministic declaration order; controls
are collected and validated together. Callback before/after saves are distinct only when their
metadata or controlled parameter state differs. Termination finalizes the same MCS, applies
`save_end`, and yields `Terminated`.

## Snapshots and Checkpoints

An analysis snapshot and continuation checkpoint are distinct APIs.

A snapshot represents observable state at a named MCS. A checkpoint promises continuation and
therefore includes all required model, scientific state, algorithm, RNG, identity, and semantic
counter state under its checkpoint contract. Stable capture occurs only at finalized MCS `0` or a
completed positive integer MCS; replaceable caches and execution workspaces are rebuilt.

They MAY share storage infrastructure but neither silently claims the other's guarantees.

Canonical storage, exact resume, logical import, and compatibility follow
[Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md).

Exact restore uses the final path:

```julia
restore_checkpoint(checkpoint, prob, alg; backend, cache, kwargs...)
```

and returns a `PottsIntegrator`; a convenience `init(...; checkpoint)` MAY delegate to the same
implementation. Exact compatibility includes scientific parameters, model, geometry, topology,
schema, capacity, numerical policy, algorithm/guarantee, RNG/namespaces, backend/runtime profile,
and initial ancestry. The checkpoint MCS must lie within the resumed interval. A later endpoint,
saving, callbacks, and progress MAY change and are recorded.

Analysis entries remain in `sol.u`; checkpoint handles, when requested, remain in a separate
checkpoint collection. Persistence failure throws, prevents a `Success` result, preserves prior
atomic publications, and leaves an already completed live MCS inspectable where possible.

Logical import constructs a new portable problem at the checkpoint's absolute MCS, retaining the
seed by default and marking the new ancestry as an import. It may change backend after
model/schema/topology validation, but does not claim exact continuation.

## Ensembles

Potts problems participate in `SciMLBase.EnsembleProblem`. Potts.jl does not invent a separate
parameter-sweep framework for cases covered by the SciML ensemble interface.

`prob_func` uses `remake` to vary seeds, parameters, initial conditions, geometry, or models across
trajectories.

Every trajectory receives independent mutable execution state and workspaces. Immutable model and
problem data MAY be shared safely across threads or processes.

### Ensemble RNG

Trajectory seeds are derived from:

- Ensemble master seed
- Stable trajectory identity
- Rerun identity
- Versioned derivation contract

They do not depend on worker, thread, device, batch size, completion order, or ensemble scheduling.

Serial, threaded, distributed, and GPU ensemble execution preserve each trajectory's selected
scientific algorithm and semantic seed identity. Ensemble scheduling does not alter within-trajectory
semantics.

CorePotts uses a thin Potts adapter around SciMLBase scheduling rather than reimplementing
threading, distribution, batching, progress, output, or reduction. An explicit ensemble `seed` is
the master seed; when omitted, the template problem seed is the master. Supplying `rng` consumes one
`UInt64` master value before scheduling and records it.

`EnsembleSeedDerivationV1` derives each trajectory seed from the master seed, trajectory identity,
rerun identity, and derivation version through the semantic Philox machinery. The user `prob_func`
runs first and must return a `PottsProblem`; automatic seed `remake` runs afterward. An explicit
`UserManagedEnsembleSeeds()` policy transfers this responsibility and records the override.

Potts ensembles default to `safetycopy = false` because problems are deeply immutable and each
`init` creates private mutable execution. User problem functions use `remake`, not mutation. Thrown
trajectory errors abort by default with trajectory/rerun context; valid partial retcodes reach
`output_func`; `CollectTrajectoryFailures()` may retain structured failures. Reruns require an
explicit finite bound.

CPU serial, threaded, and distributed schedulers are qualified. Metal and ROCm initially qualify
serial ensembles of independent GPU-resident trajectories. Same-device threaded GPU execution
throws until backend task/stream/workspace ownership is independently qualified; it is not silently
serialized. Multi-GPU and whole-ensemble batched kernels are separately named future execution
algorithms.

## Observation Interface

Ordinary observation functions receive scientific state or snapshot interfaces rather than raw
backend arrays. Explicit expert operations MAY request backend storage.

Observation requests and their results use typed scientific handles. Strings may label output
columns or plots but are not model-state identifiers. Per-cell results preserve semantic identity
and generation across lifecycle changes rather than exposing dense slot indices as biological
identity.

Observation requests declare whether they require device reduction, host materialization, full
state, or only cached metadata. The compiler can then report transfers and synchronization before
execution.

All requests due at one MCS are compiled and batched by residency. Cached metadata requires no
boundary; device outputs and reductions remain resident until host consumption; selected host data,
full snapshots, and checkpoints each use one explicit appropriate boundary. An unobserved warm MCS
adds no launch, synchronization, transfer, allocation, copy, or RNG draw beyond the direct
scientific engine.

After initialization and warmup, ordinary MCS execution performs no host or device allocation
except storage explicitly required by a requested output policy. Temporary execution and reduction
storage is bounded and preallocated in the integrator workspace.

Preflight compatibility/reproducibility reports, compilation/reuse reports, and executed
`PottsStats` are distinct inspectable structs. Statistics contain only maintained or explicitly
requested quantities; unavailable values remain unavailable rather than triggering observation or
appearing as zero.

## Display

`show(prob)` concisely reports model identity, geometry, time span, seed, capacity, and unresolved
requirements without printing the lattice.

`show(integrator)` does not synchronize the device. It uses cached host metadata such as current
completed MCS, backend, algorithm, status, and available diagnostics. State inspection is explicit.

`show(sol)` includes return code, saved interval, backend, algorithm guarantee, seed, RNG version,
model-fingerprint prefix, and storage mode.

Progress uses cached MCS only, has positive integer intervals, and never observes scientific state
implicitly. Informational GPU notices occur once during `init`; kernels perform no logging or string
construction. `verbose = false` suppresses optional notices, not errors or execution.

## Symbolic Indexing, Differentiation, and Distribution

Stable typed parameter and observable handles participate in the applicable SciML symbolic-indexing
interface. Unique symbols MAY be aliases; missing or ambiguous names fail during construction.
Indexing never becomes a device dictionary lookup and an unsaved observable is not recomputed or
transferred implicitly.

Phase 9 rejects `sensealg`, generic trajectory differentiation, and automatic differentiation
through `solve`. Discrete ownership, addressed random decisions, and accept/reject transitions do
not have ordinary pathwise derivatives. Differentiable surrogates or estimators belong to separately
specified experimental NeuralPotts interfaces; parameter ensembles and finite-difference studies do
not imply solver differentiation.

Portable problems are serializable when their user components are serializable. Distributed
ensembles serialize problems and compile on workers. Live integrators, GPU arrays, streams,
workspaces, and compilation caches are not portable serialization formats; checkpoints move live
execution. Nonserializable components or callbacks fail distributed preflight.

Public structured error families cover invalid problems, unsupported options/capabilities,
terminal stepping, unsaved times, callback conflicts, capacity exhaustion, checkpoint
incompatibility, and persistence failure. Device compiler/runtime exceptions remain available as
context. `reinit!` remains deferred until its state, cache, seed, callback, and output reset contract
is specified completely.

## Evolving-Field Scope

Phase 9 supports accepted static/exogenous fields and permits problem, solution, observation, and
checkpoint state to carry declared fields. The model owns field meaning, discretization, boundary,
units, and coupling law; the problem binds immutable initial field data or a typed initializer.

PDE evolution, secretion, uptake, and operator splitting are deferred to a separately scoped
evolving-field semantics phase after the Phase 13 core. A selected Phase 14 published model
promotes only the subset it requires through Decision 0029's source, semantic, sequential-reference,
and conformance gates. Phase 9 reserves completed-MCS phases, immutable transaction snapshots,
timestamps, observation, and checkpoint ownership, but does not freeze speculative universal
coupled-problem or split-integrator types.

Future Lie, Strang, subcycled, asynchronous, or other splitting choices are explicitly named and
specify visibility, substeps, source/sink timing, conservation/error claims, RNG, checkpoint phase,
and residency. A GPU-qualified coupling keeps field storage, stepping, interpolation, and source/
sink accumulation resident. A host solver is an explicitly synchronized mode and callbacks are not
an undocumented coupling substitute.

## Conformance Requirements

- `PottsProblem` and `PottsSolution` participate in the appropriate SciMLBase abstractions.
- CorePotts uses the applicable `__init` and `__solve` hooks.
- One-shot solving is behaviorally `solve!(init(...))`.
- Problems are immutable and separate from mutable integrators.
- `step!` advances integer MCS, never internal rounds.
- Inapplicable adaptive-solver options are rejected rather than ignored.
- `remake` preserves ownership and distinguishes numerical from structural changes.
- Saving occurs at exact MCS states without fabricated dense interpolation.
- Saved states do not alias live mutable integrator storage.
- Every completed solution has a meaningful return code.
- Capacity and invariant failures follow their structured error contracts.
- Biological events remain model effects rather than generic callbacks.
- Host callback synchronization is declared and reported.
- Snapshots and continuation checkpoints remain distinct.
- Ensemble seeds are independent of scheduling and batching.
- Displays do not cause hidden GPU synchronization.

## Primary Interface References

- [SciMLBase initialization and solving](https://docs.sciml.ai/SciMLBase/dev/interfaces/Init_Solve/)
- [SciMLBase solutions and return codes](https://docs.sciml.ai/SciMLBase/stable/interfaces/Solutions/)
- [SciMLBase ensemble interface](https://docs.sciml.ai/SciMLBase/stable/interfaces/Ensembles/)
