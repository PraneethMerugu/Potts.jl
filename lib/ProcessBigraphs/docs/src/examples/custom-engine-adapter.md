# [Independent custom engine adapter](@id custom-engine-adapter)

> **Support level:** qualified public extension protocol; the example adapter
> itself is documentation code, not package API.

**Outcome.** Implement the complete candidate lifecycle for an independent
analytic decay engine without using ProcessBigraphs representation internals.

**Prerequisites.** [Engines, adapters, and heavy computation](@ref engines-and-compute).

## Complete executed source

```@example custom-engine-adapter
using ProcessBigraphs
import ProcessBigraphs: AbstractEngineAdapter, AbstractEngineInstance,
    AbstractCompletionHandle, EngineCapabilities, EngineDeclaration,
    EngineInvocation, EngineCandidate, IntervalAdvance,
    prepare_engine, stage_operation!, complete_operation!,
    validate_candidate, publish_candidate!, discard_candidate!

struct ExponentialDecayAdapter <: AbstractEngineAdapter
    initial::Matrix{Float64}
    decay::Float64
end

mutable struct ExponentialDecayInstance <: AbstractEngineInstance
    declaration::EngineDeclaration
    published::Matrix{Float64}
    candidate::Matrix{Float64}
    active_invocation::Union{Nothing,String}
end

struct DecayCompletion <: AbstractCompletionHandle
    invocation_id::String
    target::LogicalTime
end

function prepare_engine(
    adapter::ExponentialDecayAdapter,
    declaration::EngineDeclaration,
)
    declaration.adapter === adapter ||
        throw(ArgumentError("declaration and adapter disagree"))
    ExponentialDecayInstance(
        declaration,
        copy(adapter.initial),
        copy(adapter.initial),
        nothing,
    )
end

function stage_operation!(
    instance::ExponentialDecayInstance,
    invocation::EngineInvocation,
)
    invocation.operation isa IntervalAdvance ||
        throw(ArgumentError("this adapter supports interval advance only"))
    invocation.resource_authorization == (
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ) || throw(ArgumentError("explicit CPU/Float64/host authorization required"))
    isnothing(instance.active_invocation) ||
        throw(ArgumentError("a candidate is already staged"))

    operation = invocation.operation
    elapsed = physical_value(operation.target_time) -
        physical_value(operation.start_time)
    instance.candidate =
        instance.published .* exp(-instance.declaration.adapter.decay * elapsed)
    instance.active_invocation = invocation.id
    DecayCompletion(invocation.id, operation.target_time)
end

function complete_operation!(
    instance::ExponentialDecayInstance,
    handle::DecayCompletion,
)
    instance.active_invocation == handle.invocation_id ||
        throw(ArgumentError("completion handle does not own the candidate"))
    EngineCandidate(
        handle.target,
        copy(instance.candidate);
        effects=(:field_state => copy(instance.candidate),),
        diagnostics=(
            backend=:cpu,
            algorithm=:analytic_exponential_decay,
            retcode=:success,
        ),
    )
end

function publish_candidate!(
    instance::ExponentialDecayInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate,
)
    instance.active_invocation == invocation.id ||
        throw(ArgumentError("candidate belongs to another invocation"))
    instance.published = copy(candidate.payload)
    instance.active_invocation = nothing
    (published=true, mass=sum(instance.published))
end

function discard_candidate!(
    instance::ExponentialDecayInstance,
    invocation::EngineInvocation,
    candidate,
)
    if instance.active_invocation == invocation.id
        instance.candidate = copy(instance.published)
        instance.active_invocation = nothing
    end
    nothing
end

scale = TimeScale(1, 10, :second)
adapter = ExponentialDecayAdapter(fill(2.0, 4, 4), 0.25)
declaration = EngineDeclaration(
    "independent-decay",
    adapter;
    semantic_version="1.0.0",
    parameters=(decay=adapter.decay, algorithm=:analytic_exponential_decay),
    capabilities=EngineCapabilities(
        operation_families=(:interval_advance,),
        problem_envelopes=("bounded-positive-decay",),
        backends=(:cpu,),
        precisions=(:float64,),
        residencies=(:host,),
        input_modes=(:frozen,),
        continuation_actions=(:reconstruct,),
        replay_class=:numerical,
    ),
)
invocation = EngineInvocation(
    "decay/1",
    :scheduled_field_advance,
    declaration,
    IntervalAdvance(LogicalTime(0, scale), LogicalTime(5, scale));
    structural_epoch="docs-epoch-1",
    resource_authorization=(
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ),
    expected_outputs=(:field_state,),
    expected_diagnostics=(:backend, :algorithm, :retcode),
)

instance = prepare_engine(declaration)
handle = stage_operation!(instance, invocation)
candidate = complete_operation!(instance, handle)
@assert validate_candidate(instance, invocation, candidate)
publication = publish_candidate!(instance, invocation, candidate)

result = (
    observed=instance.published[1, 1],
    expected=2exp(-0.25 * 0.5),
    publication,
    declaration=declaration.fingerprint,
)
@assert isapprox(result.observed, result.expected; atol=1.0e-12)
```

![Three boxes labeled stage, validate, and publish emphasize that numerical completion is not yet visible state.](../assets/example-results.svg)

The adapter owns its mutable instance and candidate. It cannot publish before
the runtime validates reached time, effect names, diagnostics, authorization,
and policy. A production executor calls these hooks inside a fail-stop
transaction and invokes `discard_candidate!` after pre-publication failure.

**Material defaults.** 4×4 field at 2.0, analytic decay 0.25, 0.5-second
interval, CPU/Float64/host.

**Expected result.** Each site equals `2exp(-0.125)` within `1e-12`.

**Establishes.** Required public dispatch points, call order, candidate
validation, explicit resource authorization, and publication ownership.

**Does not establish.** The example adapter does not support cancellation,
resize, device residency, or continuation preservation.

**Backend / runtime / seed.** Independent CPU analytic engine; no RNG draw.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/examples/custom_engine_adapter.jl`

**Next step.** Read the [extension protocol reference](@ref extension-experimental-api).
