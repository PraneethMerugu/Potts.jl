# [Compose and inspect a system](@id compose-and-inspect)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Validate, lower, compile, and inspect one model while keeping its
semantic, structural, and execution identities distinct.

**Prerequisites.** [Stores, ports, schemas, and updates](@ref stores-ports-updates).

## Complete executed source

```@example compose-and-inspect
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct InspectableIncrement <: AbstractProcess
    amount::Int
end

ports(::InspectableIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)
semantic_version(::InspectableIncrement) = "1.0.0"
semantic_parameters(law::InspectableIncrement) = (amount=law.amount,)
invoke(law::InspectableIncrement, inputs, context) = InvocationResult((
    emit(context, :increment, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
model = compose(:Inspectable; scale, profile=:reproducible) do system
    state = store!(
        system, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    gain = parameter!(
        system, :gain, 3;
        units="dimensionless",
        description="Documented experiment parameter",
    )
    actor = mount!(system, :increment, InspectableIncrement(gain.default))
    attach!(system, actor, (state=state, increment=state))
    schedule!(system, actor, Every(Duration(1, scale)))
    observable!(system, :state, state)
end

validation = validate(model)
lowered = lower(model)
plan = compile(lowered)

result = (
    summary=describe(model),
    expanded=diagram(model),
    valid=isempty(validation.diagnostics),
    semantic=semantic_fingerprint(model),
    canonical=ir_fingerprint(lowered),
    execution=plan_fingerprint(plan),
)
@assert result.valid
```

`describe` answers task-level questions. `diagram` exposes the expanded stores,
actors, bindings, and schedules. `origin_map` links compiled elements back to
authoring declarations when a validation diagnostic needs explanation.

**Material defaults.** Reproducible profile, gain 3, cadence 1, additive state.

**Expected result.** Empty diagnostics and three independently named
fingerprints.

**Establishes.** Deterministic authoring-to-plan inspection.

**Does not establish.** Matching fingerprints across different package
versions require the corresponding semantic contracts and migration policy.

**Backend / runtime / seed.** Compile-only CPU host; no seed.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/compose_and_inspect.jl`

**Next step.** [Logical time, scheduling, and publication](@ref time-scheduling-publication).
