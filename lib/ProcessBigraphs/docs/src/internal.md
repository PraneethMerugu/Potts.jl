# ProcessBigraphs PB0 internal contracts

Status: implemented PB0 foundation; no internal-alpha or public-parity claim

## Authority and maturity

This package is an independent Julia implementation. Its initial comparison
baseline is Process-Bigraph commit
`305ea826191e9f897f0c6e207bc303bbc44a9eef` and Bigraph-Schema commit
`4b208e13620e09e877af52ea07273bc9429a3a17`. Those projects do not own or
endorse this implementation.

PB0 is deliberately narrower than the Phase 15 internal alpha. It proves
domain-neutral values and bounded serial microfixtures. It does not claim
dynamic structural transactions, nested composites, bridges that execute
transfers, persisted checkpoint files, a general observer protocol, semantic
RNG, Threads/Dagger equivalence, device kernels, scientific adapters, or
pinned-Python oracle parity.

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

## Bounded serial microfixture runner

`SerialRuntime` is the PB0 semantic microfixture runner, not a Phase 15
executor qualification. It supports fixed-cadence static processes and an
acyclic static Step DAG.

At each imminent event, all due processes read one common snapshot. Their
deltas reconcile into a local candidate. Each Step layer then reads one common
layer snapshot. Only after every process invocation, reconciliation, and Step
layer succeeds does the runtime publish the candidate and timing continuation.

`horizon_policy=:exact` supplies the actual final elapsed interval. A process
that rejects partial intervals causes preflight failure before the call
publishes any event. `:stop_prior` stops at the last ordinary due event.

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
