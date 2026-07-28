# ProcessBigraphs internal contracts

Status: Phase 16.A–16.HC qualified; Phase 16.I exact-head candidate awaiting attestation

## Authority and maturity

This package is an independent Julia implementation. Its initial comparison
baseline is Process-Bigraph commit
`305ea826191e9f897f0c6e207bc303bbc44a9eef` and Bigraph-Schema commit
`4b208e13620e09e877af52ea07273bc9429a3a17`. Those projects do not own or
endorse this implementation.

PB0 proves domain-neutral values and bounded serial microfixtures. Phase 15.A proves the canonical
ACSet-to-compiled-plan boundary, and Phase 15.B proves immutable open composition and derived
wiring views. Phase 15.C adds the complete immutable-topology serial executor, semantic RNG,
typed observation and continuation, transactional failure, and portable logical checkpoints.
Phase 16 adds atomic dynamic structural transactions, solver-neutral engine adapters, native and
SciML field paths, bounded Merks and CNV assemblies, and semantic high-level authoring. Distributed
execution, Dagger equivalence, universal solver support, full publication analyses, and public
release remain outside the internal beta boundary.

Decision 0038 and the completed 64-choice owner interview define the Phase 15.C boundary. The
[entry contract](../../../../spec/process-bigraph-phase15c-entry-v1.toml) names exactly 15 target
features, seven supporting oracle-requalification features, four retained direct structural
features, and the explicit later-work exclusions. The
[C0--C7 plan](../../../../design/audits/process-bigraph-phase15c-serial-alpha-plan.md) is strictly
ordered and requires a separately implemented, test-only Julia specification oracle. C0--C7 pass;
C7 records implementation PR #24, its successful Required CI run, the candidate artifact
digests, and the identical qualified and squash-merge trees. Package version is `0.4.0` with
`internal_alpha = true` and `public_release = false`. The complete closure provenance is in the
[evidence manifest](../../../../design/evidence/process-bigraph-phase15c-evidence-v1.toml).

Decision 0036 makes one ProcessBigraph ACSet the Phase 15 canonical structural
model. Phase 15.A directly depends on `ACSets.jl` 0.2.29 and `Catlab.jl` 0.17.6.
`AlgebraicRewriting.jl` follows in Phase 16 and `AlgebraicDynamics.jl` enters
through a Phase 17 weak-dependency extension.

The checked specification oracle is independent from production execution. Production, oracle,
and comparator run as separate Julia processes; the oracle uses only `Base`, `Core`, `Test`,
`TOML`, and `SHA`. CI and release tooling do not install or execute Vivarium, Process-Bigraph
Python, or Bigraph-Schema Python.

## Canonical structure and compilation

`ProcessBigraphACSet` is the sole canonical lowered structure. It carries stable identities and relations
for the root composite, hierarchical store, actors, processes, steps, ports, bindings,
containment, and step dependencies. ACSet row numbers are storage-local and nonsemantic.

`compose` creates an immutable `CompositeModel` through ordinary Julia calls to `store!`,
`mount!`, `connect!`, `attach!`, `schedule!`, and `expose!`. `lower` deterministically produces a
`LoweredModel` containing the canonical ACSet and author-origin map. `StaticComposite`,
`ProcessDeclaration`, `StepDeclaration`, and `PortBinding` are private lowering and conformance
records.
`canonical_model(::ProcessBigraphACSet; initial_values, laws, continuations)` admits direct
AlgebraicJulia conformance fixtures through the same validation path. Ordinary scientific models
do not construct it directly. Equivalent authoring order produces equal semantic, structural, and
runtime fingerprints.

### Authoring lifecycle

The author-facing lifecycle is deliberately staged:

```text
temporary builder
    → immutable CompositeModel
    → deterministic LoweredModel plus author-origin map
    → immutable ExecutionPlan
    → mutable run-specific runtime and private solver sessions
```

Builder operations end in `!` because they mutate only the temporary transaction. Closing the
`compose` block normalizes declaration order, accumulates structured diagnostics, and either
returns an immutable model or throws one `ModelValidationError`. Captured builder handles cannot
mutate the completed model.

`connect!(m, store, ports...)` joins one named store junction to explicit typed endpoints.
`attach!` is exact-name bulk spelling and returns an inspectable expansion report. It never
performs approximate matching, positional wiring, or hidden conversion. A repeated mounted
definition exposes only its declared endpoints; mounted internals remain private.

Scheduling separates orchestration from numerical integration:

- `Every(duration)` publishes periodic communication boundaries;
- `At(times...)` publishes exact one-shot boundaries and becomes inactive afterward;
- `On(store)` reacts to a committed store change through an explicitly bound input;
- `After(components...)` declares a reactive stage dependency; and
- `iteration!` declares bounded or convergence-checked repeated coupling.

None of these constructs chooses a solver timestep. A SciML integrator, CPM implementation, or
external adapter retains its own adaptive steps, sweeps, device kernels, caches, and workspaces
inside the interval authorized by ProcessBigraphs.

### Models and simulation problems

`parameter!` declares a typed run parameter. A component opts in with `parameter_names` and
`with_parameters`; problem compilation rebinds the law before lowering and requires its concrete
component type to remain stable. Unknown, duplicate, foreign-model, or type-changing bindings fail
before runtime initialization.

`SimulationProblem` binds run-specific initial values, parameter overrides, selected observables,
typed boundary interventions, time span, and master seed. Bindings may use handles from the
completed model; handles from another model are rejected even when names happen to match.

`StateIntervention(id, time, store, law, payload)` is lowered to an ordinary exact one-shot
component. Its update law must match the store contract, so intervention effects use the same
validation, reconciliation, failure atomicity, checkpoint, and replay path as every other process.
It does not introduce a second runtime or mutate committed state out of band.

### Inspection, identity, and semantic archives

`describe`, `diagram`, and `explain` inspect the semantic model without compiling or running it.
Every compiled structural provenance identity maps to an author location, including repeated
mount chains, ports, bindings, endpoints, junctions, and generated one-shot occurrences.

Identity is layered: `semantic_fingerprint`, `ir_fingerprint`, `plan_fingerprint`,
`problem_fingerprint`, and checkpoint fingerprints answer different questions. Backend or resource
selection can change a plan fingerprint without changing semantic model identity.

`ProcessBigraphs.encode_semantic_model` and `decode_semantic_model` are qualified-name expert
operations. The caller supplies explicit domain-owned component encoder and decoder functions.
Archives contain a versioned logical payload plus the complete component contract fingerprint;
decoding rejects changed science and unsupported versions. Closures, tasks, pointers, live solver
sessions, device buffers, and caches are never serialized, and there is no global string-based
runtime registry.

The complete
[high-level authoring example](../../test/examples/high_level_authoring.jl) is executable as a
standalone documentation check:

```sh
julia --project=lib/ProcessBigraphs \
    lib/ProcessBigraphs/test/examples/high_level_authoring.jl
```

It defines a component through the open functional protocol, builds and validates a semantic
model, inspects lowering and plan identity, binds a `SimulationProblem`, and executes the result.
Unlike conceptual snippets that use a placeholder domain solver, this example is kept executable
in CI.

`compile_composite` freezes a private structural copy in a `StructuralEpoch` and creates an
`ExecutionPlan` containing canonical process and step order, layer indices, pre-resolved routes,
and an exact `StructuralProvenance` map. Public structure accessors return detached copies. Runtime
and checkpoint code use only the compiled plan; they do not traverse the ACSet or retain
`StaticComposite` as a parallel authority.

Phase 15.B extends the same ACSet with composite containment, typed endpoints, boundary maps,
junctions, and junction-endpoint provenance. Static hierarchy is canonical authoring information;
compilation resolves it into flat stores, routes, actors, and lookup tables before runtime.

## Immutable open composition

The ordinary API is declarative. An endpoint exposes one leaf store and its complete schema and
optional transfer contract:

```julia
producer = compose(:CounterDefinition; scale) do model
    state = store!(
        model, :state,
        LeafSchema(Int; default=0, update_law=:add))
    counter = mount!(model, :counter, Counter())
    schedule!(model, counter, Every(Duration(1, scale)))
    attach!(model, counter, (state=state, change=state))
    expose!(model, :state, state; role=:bidirectional)
end

system = compose(:CounterSystem; scale) do model
    shared = store!(
        model, :shared,
        LeafSchema(Int; default=0, update_law=:add))
    left = mount!(model, :left, producer)
    right = mount!(model, :right, producer)
    connect!(model, left.state, shared)
    connect!(model, right.state, shared)
    expose!(model, :shared, shared; role=:bidirectional)
end

compiled = compile(system)
```

The definition may be mounted repeatedly. Each instance identity derives from the parent identity
and mount key; private state remains below that key. A junction may connect any finite number of
endpoints. Conflicting initializers require one parent override. Duplicate mounts, paths,
junctions, or exports fail without changing the inputs.

Endpoint roles are capabilities at the composition boundary: `import` is consumer-capable,
`export` is provider-capable, and `bidirectional` is both. A private junction needs at least one
provider and consumer. A parent import supplies an external provider, a parent export supplies an
external consumer, and a parent bidirectional endpoint supplies both.

Compatibility is exact across Julia type and shape, units, ontology, update law, persistence,
residency, and optional `TransferDeclaration`. Conversion belongs in an explicit process or step.

`mount_group` is a pairwise/nested authoring convenience that flattens into the n-ary
`CompositionSpec`; grouping and declaration order do not enter semantic identity.

## Advanced AlgebraicJulia access

`canonical_structure(system)` returns a detached `ProcessBigraphACSet`.
`structured_cospan(system)` returns the corresponding real Catlab structured multicospan with
import and export feet. Advanced callers can author or transform an ACSet directly, then enter the
same validator:

```julia
compiled = compile_composite(
    structure;
    initial_values,
    laws,
    continuations,
)
```

`annotated_wiring_diagram(system)` derives the supported ProcessBigraph directed-wiring profile.
`wiring_diagram(view)` returns its Catlab diagram for inspection. Compiling the intact annotated
view is lossless; mutation, missing annotations, unsupported profile versions, or a generic
`Catlab.WiringDiagram` fail closed. The diagram is never a runtime authority.

Dynamic add/remove/divide/move/rewire operations are qualified Phase 16 structural transactions.
Ordinary authors declare them through structural templates; direct raw rewrite-rule execution
remains experimental and internal.

## Semantic values

`Path` identity is a tuple of typed `NameSegment` and `IndexSegment` values.
Display strings are not identity. `path("1")` and `path(1)` are different.

`TimeScale` is a normalized positive rational duration per integer tick.
`LogicalTime` and `Duration` retain the scale. Runtime compilation requires one
common scale, and inexact conversion fails rather than rounding.

`BranchSchema` declares a deterministic sorted hierarchy. `LeafSchema{T,N}`
separates value/element type and shape from units, ontology, ownership, update,
division, persistence, continuation, residency, and codec metadata.

`CommittedSnapshot` is logically immutable. Public lookup and projections
return copies; reconciliation constructs a new version with its parent
fingerprint. Engine internals may eventually specialize physical leaves, but
no PB0 invocation receives mutable committed storage.

## Effects and publication

An invocation emits `Delta` values through `emit(context, port, law, payload)`.
The engine supplies the bound path and target schema identity, preventing a
process from forging another port's target. Every result is checked against
the stable producer and event identity.

PB0 implements version-1 forms of additive, multiplicative, unique replace,
keyed, indexed, set, and stable-append updates. Deltas are sorted by semantic
producer/event/payload identity before application. Overlapping keyed/indexed
updates, multiple unique replacements, and add/remove set conflicts fail the
whole reconciliation. Arbitrary merge functions are not admitted.

## Static composition and residency

`compile_composite` validates:

- unique process and step identities;
- required bindings and port directions;
- leaf value types and output update laws;
- multiple-writer compatibility;
- fixed schedules on the common time scale;
- acyclic step dependencies; and
- declared execution domains and explicit cross-residency transfers.

PB0 records transfer declarations and their bounds but does not execute or measure a device
transfer. Phase 16.C separately qualifies the native Cartesian field envelope on real Metal and
ROCm hardware with explicit construction/observation transfers and zero warm staging transfer.
A missing transfer at any residency boundary still fails preflight as `:hidden_transfer`.

## Immutable-topology serial executor

`SerialExecutor()` is the fail-closed Phase 15.C policy and `SerialRuntime` owns its mutable
execution state. The one-argument `initialize_runtime(compiled)` remains a legacy-compatibility
facade solely to preserve PB0/15.A/15.B fingerprints; new qualified work constructs the executor
explicitly.

At each imminent event, all due processes read one common snapshot. Their
deltas reconcile into one unpublished candidate. Changed-input Step layers run to quiescence,
named iteration regions run to their convergence or hard bounds, and required observation records
validate inside the same transaction. Only then does the runtime publish state, clocks,
continuations, input cursors, observer positions, records, and one canonical event identity.

`horizon_policy=:exact` supplies the actual final elapsed interval. A process
that rejects partial intervals causes preflight failure before the call
publishes any event. `:stop_prior` stops at the last ordinary due event.

Semantic RNG uses immutable Philox4x32-10 addresses containing model, seed, owner, exact time,
event, lineage, site, and explicit draw index. Observer draws use a disjoint namespace. The v2
logical checkpoint codec captures every settled execution field without Julia object
serialization and validates its integrity and compatibility before returning a live runtime.

## Minimal example

```julia
using ProcessBigraphs
import ProcessBigraphs: ports, invoke, semantic_parameters

struct Increment <: AbstractProcess
    amount::Int
end

ports(::Increment) = (
    InputPort(Int, :state),
    OutputPort(Int, :change; update_law=:add),
)
semantic_parameters(process::Increment) = (amount=process.amount,)

function invoke(process::Increment, inputs, context)
    InvocationResult((
        emit(context, :change, AdditiveUpdate(), process.amount),
    ); diagnostics=(observed=inputs[:state], elapsed=context.elapsed.tick))
end

scale = TimeScale(1, 1, :second)
model = compose(:IncrementModel; scale) do builder
    state = store!(
        builder, :state,
        LeafSchema(Int; default=0, update_law=:add))
    increment = mount!(builder, :increment, Increment(2))
    schedule!(builder, increment, Every(Duration(1, scale)))
    attach!(builder, increment, (state=state, change=state))
end
compiled = compile(model)

runtime = initialize_runtime(compiled)
run_until!(runtime, LogicalTime(3, scale))
@assert current_snapshot(runtime)[path("state")] == 6
```

## Checkpoint boundary

`checkpoint(runtime)` creates a versioned, integrity-hashed logical checkpoint, and
`restore(compiled, checkpoint)` verifies the model, plan, engine declarations, process and step
identities, topology, continuation codecs, observer positions, and payload integrity. Phase 16
extends this boundary to dynamic structure and typed engine continuation while retaining every
previously attested reader.

Filesystem and database I/O remain extension concerns. The logical codec is portable and
canonical; Julia object serialization is not used. Legacy conversion is explicit,
non-destructive, and fail-closed. See the
[failure and persistence guide](failure-and-persistence.md) for the full Phase 16 contract.

## Extension rule

User process and step laws subtype `AbstractProcess` or `AbstractStep` and
extend `ports`, `invoke`, `semantic_version`, `semantic_parameters`, and
`capabilities`. Semantic parameters must use canonically encodable values.
Closures, pointers, tasks, device allocations, and arbitrary mutable objects
are rejected by model/checkpoint fingerprinting unless a future registered
codec explicitly admits them.
