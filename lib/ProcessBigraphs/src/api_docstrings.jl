# Curated Phase 17 owning-page docstrings. These are kept together so the
# admitted internal-beta boundary can be reviewed against its API inventory.

@doc """
    SimulationProblem(model; initial, parameters, observations, interventions, tspan, seed)

Bind a reusable [`CompositeModel`](@ref) to typed initial values, parameter
overrides, selected observables, exact-time interventions, a horizon, and a
master seed. Construction validates handle ownership and value types without
mutating `model`; use [`remake`](@ref) for an explicit variant.
""" SimulationProblem

@doc """
    store!(builder, name, schema; initial)

Declare a named typed store in an open `compose` transaction and return its
scoped handle. A supplied initial value is validated immediately. Store names
are semantic identities; this operation does not mount or connect components.
""" store!

@doc """
    mount!(builder, name, component; domain=:cpu, continuation=nothing)
    mount!(builder, name, composite)

Mount a process, step, or reusable open composite under an explicit semantic
name. Mounting never connects, schedules, exposes, or otherwise autowires the
component. Returned handles are valid only in the owning builder transaction.
""" mount!

@doc """
    attach!(builder, component, bindings)

Bind every named port in `bindings` to an explicit store and require the
attachment to cover the component exactly. Missing, duplicate, foreign, or
incompatible bindings fail closed. `attach!` is concise syntax for explicit
connections, not name-based inference.
""" attach!

@doc """
    expose!(builder, name, store; role)

Expose a store as a typed `:import`, `:export`, or `:bidirectional` endpoint of
an open composite. Exposure changes the reusable component interface but does
not connect it to any parent.
""" expose!

@doc """
    schedule!(builder, component, schedule)

Assign one explicit temporal or reactive schedule to a mounted component.
Temporal processes require `Every`, `At`, or `On`; zero-time steps may use
`After` dependencies. Duplicate or kind-incompatible schedules are rejected.
""" schedule!

@doc """
    iteration!(builder, name, steps; mode, maximum_iterations)

Declare a named bounded or convergent zero-time iteration region over mounted
steps. The region’s membership, mode, and bound participate in semantic
identity and are validated before compilation.
""" iteration!

@doc """
    parameter!(builder, name, default; units, description)

Declare a typed problem parameter with an explicit default and optional units
and description. The returned handle can be supplied to `SimulationProblem`;
parameter overrides do not mutate the reusable model.
""" parameter!

@doc """
    observable!(builder, name, store)

Declare a named model-level observable that projects one typed store. A
`SimulationProblem` selects declared observables explicitly; declaration alone
does not schedule an external observer or record data.
""" observable!

@doc """
    allow_instances!(builder, name, definition; capacity)

Declare a reusable structural template and finite instance capacity. This
authorizes future typed structural requests but creates no child instance,
connection, numeric inheritance policy, or division side effect.
""" allow_instances!

@doc """
    lower(model) -> LoweredModel

Normalize a high-level authoring model into the canonical lowering boundary.
Lowering is deterministic and construction-order invariant for semantically
unordered declarations; it does not create mutable runtime state.
""" lower

@doc """
    compile(model_or_lowered; backend=:cpu) -> CompiledComposite

Validate and compile semantic structure into an immutable indexed execution
plan and initial committed snapshot. Compilation fails on incomplete wiring,
unsupported capabilities, invalid schedules, or unresolved semantic errors.
""" compile

@doc """
    validate(model) -> ValidationReport

Return all currently detectable authoring diagnostics without compiling or
executing the model. Diagnostics include stable codes, semantic locations, and
actionable suggestions; an empty report means authoring validation passed.
""" validate

@doc """
    describe(value)

Return a task-oriented immutable summary of an authoring value, model, or
compiled artifact. `describe` exposes admitted semantic meaning and identities,
not private representation fields.
""" describe

@doc """
    diagram(model)

Return a deterministic expanded description of stores, actors, explicit
bindings, schedules, mounts, and endpoints suitable for inspection and
documentation. The result is an inspection view, not compilation authority.
""" diagram

@doc """
    explain(value)

Explain an authoring relationship or validation result in semantic terms.
Explanations expose exact coverage and expanded connections so convenience
syntax remains auditable.
""" explain

@doc """
    remake(problem; kwargs...) -> SimulationProblem

Construct a validated problem variant while preserving every unspecified field
of `problem`. The original problem is immutable; changed inputs produce a new
problem fingerprint.
""" remake

@doc """
    with_parameters(component, values)

Return a reconstructable component value with the explicitly supplied semantic
parameters. Extension authors implement this together with
[`parameter_names`](@ref); silent partial or type-changing rebinding is
unsupported.
""" with_parameters

@doc """
    Every(cadence; first_due=cadence, supports_partial=true)

Declare an exact periodic process schedule. Cadence and first-due values use
one `TimeScale`; nonpositive cadences and incompatible partial-horizon policies
are rejected.
""" Every

@doc """
    At(times...)

Declare a finite set of exact one-shot process boundaries. Times are
normalized deterministically and a process is exhausted after its last
boundary.
""" At

@doc """
    On(store)

Declare activation after a named store changes through committed publication.
Reactive scheduling observes published state and never an uncommitted
candidate.
""" On

@doc """
    After(steps...)

Declare a zero-time step dependency on one or more explicitly named steps.
Compilation rejects unknown dependencies and cycles, then produces
deterministic reactive layers.
""" After

@doc """
    semantic_fingerprint(model)

Return the stable identity of the high-level semantic authoring model.
Scientific-family, canonical-IR, execution-plan, problem, run, and checkpoint
identities remain separate contracts.
""" semantic_fingerprint

@doc """
    problem_fingerprint(problem)

Return the identity of a `SimulationProblem`, including its model, typed
initial state, parameters, observations, interventions, horizon, and root
seed. It is not a run or checkpoint identity.
""" problem_fingerprint

@doc """
    origin_map(lowered_or_compiled)

Return deterministic provenance linking normalized or compiled elements to
their high-level authoring declarations. Use this for diagnostics and audit
traces rather than inspecting private lowering records.
""" origin_map

@doc """
    schema_at(schema, path)

Return the schema node addressed by a typed `Path`, failing when the path is
absent or traverses through a leaf. This is the supported schema-inspection
route; concrete `BranchSchema` fields are representation details.
""" schema_at

@doc """
    schema_leaves(schema)

Return a deterministic tuple of `Path => LeafSchema` pairs for every leaf in a
schema tree. Ordering is canonical and does not expose concrete branch storage.
""" schema_leaves

@doc """
    observation_records(runtime)

Return an immutable copy of the runtime’s published `ObservationRecord`
sequence in event order. Records are outside logical model state and contain
only the projections authorized by each observer specification.
""" observation_records

@doc """
    checkpoint(runtime) -> SettledCheckpoint

Capture an integrity-checked logical checkpoint at a settled serial boundary.
The checkpoint records model and plan identity, committed state, logical time,
clocks, continuations, observations, and replay policy; unsettled capture fails.
""" checkpoint

@doc """
    restore(compiled, checkpoint) -> SerialRuntime
    restore(compiled, executor, checkpoint) -> SerialRuntime

Validate and restore a compatible settled logical checkpoint. Restore rejects
corrupt payloads and mismatched model, execution, continuation, observation,
or runtime-policy identities rather than silently migrating them.
""" restore

@doc """
    spawn(template, request_id, source_epoch, parent, mount_key; ...)

Author a typed add-composite request from an admitted template. The request is
pure data addressed to one source structural epoch; it does not mutate
structure, create numeric state, or infer connections.
""" spawn

@doc """
    divide(template, request_id, source_epoch, target, daughter_mount_key; policies, ...)

Author a typed divide request with an explicit daughter definition and division
policies. Selection and publication remain transactional; numeric inheritance,
geometry, lineage, and connection behavior are never inferred.
""" divide

@doc """
    remove(request_id, source_epoch, target, owned_closure=(); ...)

Author a typed remove request naming its source epoch and complete owned
closure. Structural validation rejects incomplete closure claims and stale or
unknown identities.
""" remove

@doc """
    move(request_id, source_epoch, target, new_parent, mount_key; ...)

Author a typed move request between explicit structural identities. Cycles,
stale generations, incompatible containment, and request conflicts fail before
publication.
""" move

@doc """
    AbstractProcess

Supertype for scheduled temporal components. Implementors provide typed
[`ports`](@ref), stable semantic identity, and [`invoke`](@ref); every mounted
process requires an explicit temporal schedule.
""" AbstractProcess

@doc """
    AbstractStep

Supertype for zero-time reactive components. Steps participate in compiled
acyclic or explicitly bounded iteration layers and emit typed effects against
one committed event boundary.
""" AbstractStep

@doc """
    AbstractObserver

Supertype for typed external observers. Implementors receive only declared
state projections and an isolated semantic RNG context, and return validated
records that cannot mutate logical model state.
""" AbstractObserver

@doc """
    ports(component)

Return a reconstructable tuple of typed input and output port declarations for
a process or step. Port name, direction, value type, interval behavior, update
law, cardinality, and residency participate in validation and identity.
""" ports

@doc """
    capabilities(component)

Return the component’s declared capability requirements. The declaration is a
preflight envelope, not evidence that every backend or method supported by a
dependency is qualified.
""" capabilities

@doc """
    semantic_version(component)

Return the stable semantic version string for a process or step implementation.
Changing behavior without changing the version invalidates canonical identity
and persistence assumptions.
""" semantic_version

@doc """
    semantic_parameters(component)

Return a canonical-encodable named tuple containing every behavior-affecting
semantic parameter of a process or step. Runtime caches, buffers, and display
settings must not appear here.
""" semantic_parameters

@doc """
    invoke(component, inputs, context) -> InvocationResult

Execute one authorized process or step activation against immutable typed
inputs. Return deltas, diagnostics, an optional continuation, and allowed
requests; do not mutate committed stores or forge producer/event identities.
""" invoke

@doc """
    observe(observer, projection, context) -> ObservationResult

Produce one typed record from the observer’s authorized projection. Observation
uses an isolated RNG namespace and may advance only its declared continuation;
it cannot emit model-state effects.
""" observe

@doc """
    observer_semantic_version(observer)

Return the stable semantic version string for an observer implementation.
Record meaning or continuation behavior changes require an explicit version
and migration decision.
""" observer_semantic_version

@doc """
    observer_semantic_parameters(observer)

Return every behavior-affecting observer parameter as a canonical-encodable
named tuple. Presentation-only configuration and mutable caches are excluded.
""" observer_semantic_parameters

@doc """
    observer_continuation_schema(observer)

Return the observer’s typed continuation schema and codec contract. Stateless
observers use `stateless_continuation_schema`; incompatible persisted
continuations fail restore.
""" observer_continuation_schema

@doc """
    AbstractEngineAdapter

Supertype for reconstructable, immutable engine declarations. An adapter names
the problem and algorithm semantics it supports; mutable solver state belongs
to an [`AbstractEngineInstance`](@ref).
""" AbstractEngineAdapter

@doc """
    AbstractEngineInstance

Supertype for implementor-owned mutable engine sessions, workspaces, buffers,
integrators, or device state. Instances stage candidates but cannot make them
logical state without runtime validation and publication.
""" AbstractEngineInstance

@doc """
    AbstractEngineOperation

Supertype for typed authorized engine operations such as
[`IntervalAdvance`](@ref), [`BoundarySolve`](@ref), and
[`DiscreteBatch`](@ref).
""" AbstractEngineOperation

@doc """
    AbstractCompletionHandle

Supertype for implementor-owned handles returned by [`stage_operation!`](@ref).
A handle may represent immediate, asynchronous, device, or solver completion;
it is consumed by [`complete_operation!`](@ref).
""" AbstractCompletionHandle

@doc """
    EngineDeclaration(id, adapter; semantic_version, capabilities, parameters)

Bind a reconstructable adapter to an explicit semantic version, canonical
parameters, and a narrow capability envelope. The declaration fingerprint
authorizes later invocations; mutable instance state is not retained.
""" EngineDeclaration

@doc """
    IntervalAdvance(start_time, target_time)

Authorize an engine to advance over one positive exact logical interval.
Adapters must reach `target_time` for a successful terminal candidate or return
a typed nonterminal outcome within the interval.
""" IntervalAdvance

@doc """
    BoundarySolve(time, problem)

Authorize one named zero-duration boundary problem at an exact logical time.
The problem symbol and operation family must fall within the engine’s declared
capability envelope.
""" BoundarySolve

@doc """
    DiscreteBatch(time, batch, count=1)

Authorize a positive finite count of named discrete operations at one exact
logical boundary. Batch identity and count are semantic invocation inputs.
""" DiscreteBatch

@doc """
    EngineInputProjection(name, version, time, value; mode=:frozen)

Capture an immutable, canonical-encoded, versioned engine input projection.
Projection time cannot be after invocation start, and its mode must be admitted
by the engine declaration.
""" EngineInputProjection

@doc """
    EngineInvocation(id, reason, declaration, operation; ...)

Describe one authorized engine handoff: operation, structural epoch, immutable
inputs, RNG context, selected resources, and expected effect/diagnostic
schemas. Construction rejects requests outside declared capabilities.
""" EngineInvocation

@doc """
    EngineCandidate(actual_time, payload; effects, continuation, diagnostics, fingerprint)

Represent a completed but not-yet-published engine result. A candidate remains
implementor-owned until the runtime validates reached time, output schemas,
diagnostics, authorization, and policy.
""" EngineCandidate

@doc """
    EngineEarlyReturn(actual_time, reason; diagnostics)

Report a nonterminal return strictly within an authorized interval. A result at
the exact terminal target must be an `EngineCandidate`, not an early return.
""" EngineEarlyReturn

@doc """
    EngineEventRequest(actual_time, event, payload=NamedTuple())

Request a typed runtime-visible event at a nonterminal authorized time. The
runtime validates temporal bounds and decides how the request affects
scheduling; the adapter does not publish state directly.
""" EngineEventRequest

@doc """
    EngineFailure(code, stage; retry_class=:never, diagnostics)

Return a structured engine failure with an explicit retry class. Managed
execution discards staged candidates and preserves the pre-publication logical
state before reporting the failure.
""" EngineFailure

@doc """
    projection_value(input)

Decode and return an owned value from an immutable `EngineInputProjection`.
Adapters should use this accessor rather than depend on the projection’s
canonical byte representation.
""" projection_value

@doc """
    prepare_engine(adapter, declaration) -> AbstractEngineInstance
    prepare_engine(declaration) -> AbstractEngineInstance

Construct implementor-owned mutable engine state for a declaration. Verify that
the adapter and declaration agree and allocate only resources authorized by the
declared capability and later invocation policy.
""" prepare_engine

@doc """
    stage_operation!(instance, invocation) -> AbstractCompletionHandle

Validate adapter-specific inputs and resources, perform or launch heavy work,
and stage a private candidate without publishing it. Only one active candidate
may own a given invocation identity unless the adapter documents otherwise.
""" stage_operation!

@doc """
    complete_operation!(instance, handle)

Wait for or collect a staged operation and return exactly one
`EngineCandidate`, `EngineEarlyReturn`, `EngineEventRequest`, or
`EngineFailure`. Completion alone does not publish logical state.
""" complete_operation!

@doc """
    validate_candidate(instance, invocation, candidate) -> true

Validate terminal time, exact effect names, and exact diagnostic schema for a
candidate. Adapter overloads may add domain checks but must preserve the base
runtime contract and fail before publication.
""" validate_candidate

@doc """
    publish_candidate!(instance, invocation, candidate)

Perform the adapter’s one-way publication after runtime validation and
authorization. The method must verify candidate ownership and return a
canonical-encodable publication summary.
""" publish_candidate!

@doc """
    discard_candidate!(instance, invocation, outcome)

Release or reset all private staged state associated with an invocation after
pre-publication failure or a nonterminal outcome. Cleanup must not mutate
committed logical state.
""" discard_candidate!
