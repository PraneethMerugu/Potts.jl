module IndependentCustomFieldAdapterFixture

import ProcessBigraphs as PB

export IndependentCustomFieldAdapter, independent_custom_field_declaration,
       custom_field_snapshot

const CONTRACT_VERSION = "independent-external-field-adapter-v2"
const CHECKPOINT_VERSION = "independent-external-field-checkpoint-v2"

struct IndependentCustomFieldAdapter{
        P<:PB.BoundedCartesianFieldProblem} <: PB.AbstractEngineAdapter
    problem::P
    substeps_per_tick::Int
end

function IndependentCustomFieldAdapter(
    problem::PB.BoundedCartesianFieldProblem;
    substeps_per_tick::Integer=4,
)
    0 < substeps_per_tick <= typemax(Int) ||
        throw(ArgumentError("custom RK4 substeps must fit positive Int"))
    IndependentCustomFieldAdapter(problem, Int(substeps_per_tick))
end

PB.engine_semantic_version(::IndependentCustomFieldAdapter) = "2.0.0"
PB.engine_semantic_parameters(adapter::IndependentCustomFieldAdapter) = (
    contract_version=CONTRACT_VERSION,
    problem_fingerprint=adapter.problem.fingerprint,
    algorithm_id="independent-classical-rk4",
    substeps_per_tick=adapter.substeps_per_tick,
    continuation_policy="reconstruct_each_invocation",
    replay_class=:numerical,
)

function independent_custom_field_declaration(
    problem::PB.BoundedCartesianFieldProblem;
    substeps_per_tick::Integer=4,
)
    adapter = IndependentCustomFieldAdapter(
        problem; substeps_per_tick)
    precision = eltype(problem.initial_values) === Float32 ?
        :float32 : :float64
    PB.EngineDeclaration(
        problem.id,
        adapter;
        capabilities=PB.EngineCapabilities(
            operation_families=(:interval_advance,),
            problem_envelopes=(
                "independent-periodic-cartesian-diffusion-decay",),
            backends=(:cpu,),
            precisions=(precision,),
            residencies=(:host,),
            input_modes=(:frozen,),
            boundary_kinds=(:periodic,),
            continuation_actions=(:reconstruct, :reject),
            replay_class=:numerical,
            cancellation=false,
            diagnostics=true,
            resize=false,
            bridges=(),
        ),
    )
end

mutable struct IndependentCustomFieldInstance{
        D<:PB.EngineDeclaration,A<:Array} <: PB.AbstractEngineInstance
    declaration::D
    published::A
    forcing::A
    decay_weights::A
    prior_forcing::Union{Nothing,A}
    prior_decay_weights::Union{Nothing,A}
    candidate::A
    time_tick::Int64
    target_tick::Int64
    publication_epoch::UInt64
    active_invocation::Union{Nothing,String}
end

function _instance(
    declaration::PB.EngineDeclaration{<:IndependentCustomFieldAdapter},
    values,
    forcing,
    decay_weights,
    time_tick::Integer,
    publication_epoch::Integer,
)
    problem = declaration.adapter.problem
    published = Array(values)
    normalized_forcing = Array(forcing)
    normalized_decay_weights = Array(decay_weights)
    size(published) == size(problem.initial_values) &&
        eltype(published) == eltype(problem.initial_values) ||
        throw(ArgumentError("custom checkpoint state is incompatible"))
    size(normalized_forcing) == size(published) &&
        eltype(normalized_forcing) == eltype(published) ||
        throw(ArgumentError("custom checkpoint forcing is incompatible"))
    size(normalized_decay_weights) == size(published) &&
        eltype(normalized_decay_weights) == eltype(published) &&
        all(value -> isfinite(value) && value >= zero(value),
            normalized_decay_weights) ||
        throw(ArgumentError(
            "custom checkpoint decay weights are incompatible"))
    IndependentCustomFieldInstance(
        declaration,
        published,
        normalized_forcing,
        normalized_decay_weights,
        nothing,
        nothing,
        published,
        Int64(time_tick),
        Int64(time_tick),
        UInt64(publication_epoch),
        nothing,
    )
end

function PB.prepare_engine(
    adapter::IndependentCustomFieldAdapter,
    declaration::PB.EngineDeclaration,
)
    declaration.adapter === adapter ||
        throw(ArgumentError("custom declaration and adapter disagree"))
    _instance(
        declaration,
        adapter.problem.initial_values,
        zeros(eltype(adapter.problem.initial_values),
            size(adapter.problem.initial_values)),
        adapter.problem.decay_weights,
        adapter.problem.initial_tick,
        0,
    )
end

PB.field_engine_array_type(
    adapter::IndependentCustomFieldAdapter,
) = typeof(adapter.problem.initial_values)

PB.field_engine_expected_diagnostics(
    ::IndependentCustomFieldAdapter,
) = (:backend, :algorithm, :retcode)

function PB.field_engine_reconstruct(
    declaration::PB.EngineDeclaration{<:IndependentCustomFieldAdapter},
    values,
    time_tick::Integer,
)
    problem = declaration.adapter.problem
    _instance(
        declaration,
        values,
        zeros(eltype(problem.initial_values), size(problem.initial_values)),
        problem.decay_weights,
        time_tick,
        0,
    )
end

struct IndependentCustomCompletion <: PB.AbstractCompletionHandle
    invocation_id::String
    target::PB.LogicalTime
end

struct IndependentCustomCandidate
    invocation_id::String
    target_tick::Int64
    publication_epoch::UInt64
end

@inline function _fixture_laplacian(
    input,
    index::CartesianIndex{N},
    spacing::NTuple{N},
) where {N}
    coordinates = Tuple(index)
    center = @inbounds input[index]
    result = zero(center)
    for axis in 1:N
        low = Base.setindex(
            coordinates,
            mod1(coordinates[axis] - 1, size(input, axis)),
            axis,
        )
        high = Base.setindex(
            coordinates,
            mod1(coordinates[axis] + 1, size(input, axis)),
            axis,
        )
        @inbounds result += (
            input[low...] + input[high...] - 2center
        ) / (spacing[axis] * spacing[axis])
    end
    result
end

function _fixture_rhs!(
    output,
    values,
    forcing,
    decay_weights,
    problem,
)
    for index in CartesianIndices(values)
        @inbounds center = values[index]
        @inbounds output[index] =
            problem.diffusion *
                _fixture_laplacian(values, index, problem.spacing) +
            forcing[index] -
            problem.decay * decay_weights[index] * center
    end
    output
end

function _field_inputs(
    instance::IndependentCustomFieldInstance,
    invocation,
)
    projections = Dict(projection.name => projection
        for projection in invocation.inputs)
    Set(keys(projections)) in
        (Set((:forcing,)), Set((:forcing, :decay_weights))) ||
        throw(ArgumentError(
            "custom field advance requires `forcing` and optionally `decay_weights` projections"))
    forcing = PB.projection_value(projections[:forcing])
    forcing isa AbstractArray &&
        size(forcing) == size(instance.forcing) &&
        eltype(forcing) == eltype(instance.forcing) ||
        throw(ArgumentError(
            "custom field forcing has incompatible shape or precision"))
    decay_weights = haskey(projections, :decay_weights) ?
        PB.projection_value(projections[:decay_weights]) :
        instance.decay_weights
    decay_weights isa AbstractArray &&
        size(decay_weights) == size(instance.decay_weights) &&
        eltype(decay_weights) == eltype(instance.decay_weights) &&
        all(value -> isfinite(value) && value >= zero(value), decay_weights) ||
        throw(ArgumentError(
            "custom field decay weights have incompatible values, shape, or precision"))
    forcing, decay_weights
end

function _authorize_resources(
    instance::IndependentCustomFieldInstance,
    invocation,
)
    precision = eltype(instance.published) === Float32 ?
        :float32 : :float64
    expected = (backend=:cpu, precision, residency=:host)
    all(key -> haskey(invocation.resource_authorization, key) &&
        getproperty(invocation.resource_authorization, key) ==
            getproperty(expected, key), keys(expected)) ||
        throw(ArgumentError(
            "custom field requires explicit CPU/precision/host authorization"))
    nothing
end

function _rk4_advance(
    values,
    forcing,
    decay_weights,
    problem,
    steps::Int,
    duration,
)
    current = copy(values)
    next = similar(current)
    temporary = similar(current)
    k1 = similar(current)
    k2 = similar(current)
    k3 = similar(current)
    k4 = similar(current)
    dt = duration / steps
    half = dt / 2
    sixth = dt / 6
    for _ in 1:steps
        _fixture_rhs!(k1, current, forcing, decay_weights, problem)
        @. temporary = current + half * k1
        _fixture_rhs!(k2, temporary, forcing, decay_weights, problem)
        @. temporary = current + half * k2
        _fixture_rhs!(k3, temporary, forcing, decay_weights, problem)
        @. temporary = current + dt * k3
        _fixture_rhs!(k4, temporary, forcing, decay_weights, problem)
        @. next = current + sixth * (k1 + 2k2 + 2k3 + k4)
        current, next = next, current
    end
    current
end

function PB.stage_operation!(
    instance::IndependentCustomFieldInstance,
    invocation::PB.EngineInvocation,
)
    operation = invocation.operation
    operation isa PB.IntervalAdvance ||
        throw(ArgumentError("custom field supports only interval advance"))
    isnothing(instance.active_invocation) ||
        throw(ArgumentError("custom field already has an active candidate"))
    adapter = instance.declaration.adapter
    problem = adapter.problem
    operation.start_time ==
        PB.LogicalTime(instance.time_tick, problem.time_scale) ||
        throw(ArgumentError(
            "custom field and ProcessBigraphs clocks disagree"))
    _authorize_resources(instance, invocation)
    forcing, decay_weights = _field_inputs(instance, invocation)
    instance.prior_forcing = copy(instance.forcing)
    instance.prior_decay_weights = copy(instance.decay_weights)
    copyto!(instance.forcing, forcing)
    copyto!(instance.decay_weights, decay_weights)
    ticks = operation.target_time.tick - operation.start_time.tick
    steps = Base.Checked.checked_mul(
        ticks, adapter.substeps_per_tick)
    duration = convert(eltype(instance.published), ticks) *
        problem.tick_duration
    try
        candidate = _rk4_advance(
            instance.published,
            instance.forcing,
            instance.decay_weights,
            problem,
            steps,
            duration,
        )
        all(isfinite, candidate) &&
            (!problem.reject_negative ||
             all(>=(zero(eltype(candidate))), candidate)) ||
            throw(ArgumentError(
                "custom field produced an invalid candidate"))
        instance.candidate = candidate
    catch
        copyto!(instance.forcing, instance.prior_forcing)
        copyto!(
            instance.decay_weights, instance.prior_decay_weights)
        instance.prior_forcing = nothing
        instance.prior_decay_weights = nothing
        rethrow()
    end
    instance.target_tick = operation.target_time.tick
    instance.active_invocation = invocation.id
    IndependentCustomCompletion(invocation.id, operation.target_time)
end

function PB.complete_operation!(
    instance::IndependentCustomFieldInstance,
    handle::IndependentCustomCompletion,
)
    instance.active_invocation == handle.invocation_id ||
        throw(ArgumentError(
            "custom completion does not own the staged candidate"))
    token = IndependentCustomCandidate(
        handle.invocation_id,
        instance.target_tick,
        Base.Checked.checked_add(
            instance.publication_epoch, UInt64(1)),
    )
    PB.EngineCandidate(
        handle.target,
        token;
        effects=(:field_state => (
            target_tick=token.target_tick,
            publication_epoch=token.publication_epoch,
        ),),
        diagnostics=(
            backend=:cpu,
            algorithm=:independent_classical_rk4,
            retcode="completed",
        ),
        fingerprint=PB.canonical_fingerprint((
            CONTRACT_VERSION,
            instance.declaration.fingerprint,
            token.invocation_id,
            token.target_tick,
            token.publication_epoch,
        )),
    )
end

function PB.publish_candidate!(
    instance::IndependentCustomFieldInstance,
    invocation::PB.EngineInvocation,
    candidate::PB.EngineCandidate{<:IndependentCustomCandidate},
)
    instance.active_invocation == invocation.id &&
        candidate.payload.invocation_id == invocation.id ||
        throw(ArgumentError(
            "custom candidate belongs to another invocation"))
    instance.published = instance.candidate
    instance.time_tick = instance.target_tick
    instance.publication_epoch =
        candidate.payload.publication_epoch
    instance.prior_forcing = nothing
    instance.prior_decay_weights = nothing
    instance.active_invocation = nothing
    (
        time_tick=instance.time_tick,
        publication_epoch=instance.publication_epoch,
    )
end

function PB.discard_candidate!(
    instance::IndependentCustomFieldInstance,
    invocation::PB.EngineInvocation,
    candidate,
)
    if instance.active_invocation == invocation.id
        instance.candidate = instance.published
        instance.target_tick = instance.time_tick
        if !isnothing(instance.prior_forcing)
            copyto!(instance.forcing, instance.prior_forcing)
        end
        if !isnothing(instance.prior_decay_weights)
            copyto!(
                instance.decay_weights, instance.prior_decay_weights)
        end
        instance.prior_forcing = nothing
        instance.prior_decay_weights = nothing
        instance.active_invocation = nothing
    end
    nothing
end

custom_field_snapshot(instance::IndependentCustomFieldInstance) =
    copy(instance.published)
PB.field_engine_snapshot(instance::IndependentCustomFieldInstance) =
    custom_field_snapshot(instance)

function PB.engine_checkpoint_payload(
    instance::IndependentCustomFieldInstance,
    declaration::PB.EngineDeclaration,
)
    isnothing(instance.active_invocation) ||
        throw(ArgumentError(
            "custom field checkpoint requires a settled boundary"))
    PB.CheckpointComponent(
        declaration.id,
        CHECKPOINT_VERSION,
        :numerical,
        (
            declaration_fingerprint=declaration.fingerprint,
            values=copy(instance.published),
            forcing=copy(instance.forcing),
            decay_weights=copy(instance.decay_weights),
            time_tick=instance.time_tick,
            publication_epoch=instance.publication_epoch,
            continuation_policy=:reconstruct_each_invocation,
        ),
    )
end

function PB.restore_engine_checkpoint(
    adapter::IndependentCustomFieldAdapter,
    declaration::PB.EngineDeclaration,
    payload::NamedTuple,
)
    payload.declaration_fingerprint == declaration.fingerprint ||
        throw(ArgumentError(
            "custom field declaration changed during restore"))
    payload.continuation_policy === :reconstruct_each_invocation ||
        throw(ArgumentError(
            "unsupported custom continuation policy"))
    _instance(
        declaration,
        payload.values,
        payload.forcing,
        payload.decay_weights,
        payload.time_tick,
        payload.publication_epoch,
    )
end

end
