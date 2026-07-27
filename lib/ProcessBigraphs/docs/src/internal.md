# ProcessBigraphs internal contracts

Status: Phase 15.C qualified immutable-topology serial internal alpha

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
Dynamic structural transactions, executable transfers, Threads/Dagger equivalence, device
kernels, scientific adapters, and public release remain outside this internal alpha.

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

`ProcessBigraphACSet` is the sole authoring structure. It carries stable identities and relations
for the root composite, hierarchical store, actors, processes, steps, ports, bindings,
containment, and step dependencies. ACSet row numbers are storage-local and nonsemantic.

`canonical_model(::StaticComposite)` lowers the ordinary typed façade into that ACSet.
`canonical_model(::ProcessBigraphACSet; initial_values, laws, continuations)` admits direct
AlgebraicJulia authoring through the same validation path. Both paths reconstruct and validate one
normalized semantic declaration, and equivalent authoring order produces equal structural and
runtime fingerprints.

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
producer = open_composite(
    "counter-definition",
    StaticComposite(schema, Dict(), scale;
        processes=(declaration,),
        bindings);
    endpoints=(
        BoundaryEndpoint(:state, path("state"); role=:bidirectional),
    ),
)

system = compose_open(
    "counter-system";
    mounts=(
        CompositeMount(:left, producer),
        CompositeMount(:right, producer),
    ),
    junctions=(
        JunctionSpec(
            "shared-count",
            path("shared"),
            (EndpointRef(:left, :state), EndpointRef(:right, :state)),
        ),
    ),
    exports=(
        CompositeExport(:shared, "shared-count"; role=:bidirectional),
    ),
    initial_values=Dict(path("shared") => 0),
)

compiled = compile_composite(system)
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

Dynamic add/remove/divide/move/rewire operations remain Phase 16 structural transactions.

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

PB0 records transfer declarations and their bounds. It does not execute or
measure a device transfer, so `declared-measured-transfers` is not implemented.
A missing transfer at a residency boundary fails preflight as
`:hidden_transfer`.

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
schema = BranchSchema(
    state=LeafSchema(Int; default=0, update_law=:add),
)
declaration = ProcessDeclaration(
    "increment",
    Increment(2),
    FixedSchedule(Duration(1, scale)),
)
bindings = (
    PortBinding("increment", :state, path("state")),
    PortBinding("increment", :change, path("state")),
)
compiled = compile_composite(StaticComposite(
    schema,
    Dict(),
    scale;
    processes=(declaration,),
    bindings,
))

runtime = initialize_runtime(compiled)
run_until!(runtime, LogicalTime(3, scale))
@assert current_snapshot(runtime)[path("state")] == 6
```

## Checkpoint boundary

`checkpoint(runtime)` creates a versioned, integrity-hashed
`SettledCheckpoint`, and `restore(compiled, checkpoint)` verifies the model,
process/step identities, and payload hash. This proves same-package,
same-engine in-memory replay at settled boundaries.

There is intentionally no file writer/reader in PB0. A portable persisted
codec requires canonical decode, schema migrations, invalidation rules, RNG
continuations, topology, and observer positions. Julia object serialization is
not used as a substitute for that contract.

## Extension rule

User process and step laws subtype `AbstractProcess` or `AbstractStep` and
extend `ports`, `invoke`, `semantic_version`, `semantic_parameters`, and
`capabilities`. Semantic parameters must use canonically encodable values.
Closures, pointers, tasks, device allocations, and arbitrary mutable objects
are rejected by model/checkpoint fingerprinting unless a future registered
codec explicitly admits them.
