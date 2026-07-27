const BOUNDED_CARTESIAN_FIELD_VERSION =
    "process-bigraph-bounded-cartesian-field-v1"
const INDEPENDENT_CUSTOM_FIELD_VERSION =
    "process-bigraph-independent-custom-field-v1"

struct BoundedCartesianFieldProblem{N,T<:AbstractFloat}
    id::String
    initial_values::Array{T,N}
    spacing::NTuple{N,T}
    diffusion::T
    decay::T
    tick_duration::T
    substeps_per_tick::Int
    reject_negative::Bool
    initial_tick::Int64
    time_scale::TimeScale
    fingerprint::String
end

function BoundedCartesianFieldProblem(
    id::AbstractString,
    values::AbstractArray{T,N};
    spacing=ntuple(_ -> one(T), N),
    diffusion::Real,
    decay::Real=0,
    tick_duration::Real,
    substeps_per_tick::Integer=1,
    reject_negative::Bool=true,
    initial_tick::Integer=0,
    time_scale::TimeScale,
) where {T<:AbstractFloat,N}
    isempty(id) &&
        _fail(:empty_bounded_field_identity,
            "bounded Cartesian field identity cannot be empty")
    N in (2, 3) ||
        _fail(:unsupported_field_rank,
            "bounded Cartesian fields support only 2D or 3D"; rank=N)
    all(>(0), size(values)) ||
        _fail(:invalid_field_dimensions,
            "bounded Cartesian field dimensions must be positive")
    normalized_spacing = ntuple(axis -> T(spacing[axis]), N)
    all(value -> isfinite(value) && value > zero(T),
        normalized_spacing) ||
        _fail(:invalid_field_spacing,
            "bounded Cartesian field spacing must be finite and positive")
    normalized_diffusion = T(diffusion)
    normalized_decay = T(decay)
    normalized_tick = T(tick_duration)
    isfinite(normalized_diffusion) && normalized_diffusion >= zero(T) ||
        _fail(:invalid_field_diffusion,
            "bounded Cartesian diffusion must be finite and nonnegative")
    isfinite(normalized_decay) && normalized_decay >= zero(T) ||
        _fail(:invalid_field_decay,
            "bounded Cartesian decay must be finite and nonnegative")
    isfinite(normalized_tick) && normalized_tick > zero(T) ||
        _fail(:invalid_field_tick,
            "bounded Cartesian tick duration must be finite and positive")
    substeps_per_tick > 0 && substeps_per_tick <= typemax(Int) ||
        _fail(:invalid_field_substeps,
            "bounded Cartesian substeps must fit positive Int")
    typemin(Int64) <= initial_tick <= typemax(Int64) ||
        _fail(:field_time_overflow,
            "bounded Cartesian initial tick must fit Int64")
    T(time_scale.numerator) / T(time_scale.denominator) ==
        normalized_tick ||
        _fail(:field_time_scale_mismatch,
            "exact logical time scale must equal field tick duration")
    owned = Array(values)
    all(isfinite, owned) ||
        _fail(:nonfinite_field_initial_state,
            "bounded Cartesian initial state must be finite")
    reject_negative && any(<(zero(T)), owned) &&
        _fail(:negative_field_initial_state,
            "bounded Cartesian initial state violates positivity")
    payload = (
        BOUNDED_CARTESIAN_FIELD_VERSION,
        String(id),
        owned,
        normalized_spacing,
        normalized_diffusion,
        normalized_decay,
        normalized_tick,
        Int(substeps_per_tick),
        reject_negative,
        Int64(initial_tick),
        time_scale,
    )
    BoundedCartesianFieldProblem(
        String(id),
        owned,
        normalized_spacing,
        normalized_diffusion,
        normalized_decay,
        normalized_tick,
        Int(substeps_per_tick),
        reject_negative,
        Int64(initial_tick),
        time_scale,
        canonical_fingerprint(payload),
    )
end

function _bounded_field_stability(problem::BoundedCartesianFieldProblem)
    dt = problem.tick_duration / problem.substeps_per_tick
    coefficient = zero(dt)
    for spacing in problem.spacing
        coefficient += problem.diffusion * dt / (spacing * spacing)
    end
    coefficient <= convert(typeof(coefficient), 0.5) ||
        _fail(:unstable_explicit_field_step,
            "bounded Cartesian explicit step exceeds the stability limit";
            coefficient)
    dt
end

@inline function _periodic_laplacian(
    input,
    index::CartesianIndex{N},
    spacing::NTuple{N},
) where {N}
    coordinates = Tuple(index)
    center = @inbounds input[index]
    laplacian = zero(center)
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
        @inbounds laplacian += (
            input[low...] + input[high...] - 2center
        ) / (spacing[axis] * spacing[axis])
    end
    laplacian
end

struct IndependentCustomFieldAdapter{
        P<:BoundedCartesianFieldProblem} <: AbstractEngineAdapter
    problem::P
end

engine_semantic_version(::IndependentCustomFieldAdapter) = "1.0.0"
engine_semantic_parameters(adapter::IndependentCustomFieldAdapter) = (
    contract_version=INDEPENDENT_CUSTOM_FIELD_VERSION,
    problem_fingerprint=adapter.problem.fingerprint,
)

function independent_custom_field_declaration(
    problem::BoundedCartesianFieldProblem,
)
    precision = eltype(problem.initial_values) === Float32 ?
        :float32 : :float64
    EngineDeclaration(
        problem.id,
        IndependentCustomFieldAdapter(problem);
        capabilities=EngineCapabilities(
            operation_families=(:interval_advance,),
            problem_envelopes=("periodic-cartesian-diffusion-decay",),
            backends=(:cpu,),
            precisions=(precision,),
            residencies=(:host,),
            input_modes=(:frozen,),
            boundary_kinds=(:periodic,),
            continuation_actions=(:preserve, :reconstruct, :reject),
            replay_class=:exact,
            cancellation=false,
            diagnostics=true,
            resize=false,
            bridges=(),
        ),
    )
end

mutable struct IndependentCustomFieldInstance{
        P<:BoundedCartesianFieldProblem,A<:Array} <: AbstractEngineInstance
    problem::P
    published::A
    first::A
    second::A
    forcing::A
    prior_forcing::Union{Nothing,A}
    candidate::A
    time_tick::Int64
    target_tick::Int64
    publication_epoch::UInt64
    active_invocation::Union{Nothing,String}
end

function _independent_custom_instance(
    problem::BoundedCartesianFieldProblem,
    values,
    forcing,
    time_tick::Integer,
    publication_epoch::Integer,
)
    published = Array(values)
    size(published) == size(problem.initial_values) &&
        eltype(published) == eltype(problem.initial_values) ||
        _fail(:field_checkpoint_shape_mismatch,
            "custom field checkpoint state is incompatible")
    normalized_forcing = Array(forcing)
    size(normalized_forcing) == size(published) &&
        eltype(normalized_forcing) == eltype(published) ||
        _fail(:field_checkpoint_forcing_mismatch,
            "custom field checkpoint forcing is incompatible")
    first = similar(published)
    second = similar(published)
    fill!(first, zero(eltype(first)))
    fill!(second, zero(eltype(second)))
    IndependentCustomFieldInstance(
        problem,
        published,
        first,
        second,
        normalized_forcing,
        nothing,
        published,
        Int64(time_tick),
        Int64(time_tick),
        UInt64(publication_epoch),
        nothing,
    )
end

prepare_engine(
    adapter::IndependentCustomFieldAdapter,
    declaration::EngineDeclaration,
) = _independent_custom_instance(
    adapter.problem,
    adapter.problem.initial_values,
    zeros(eltype(adapter.problem.initial_values),
        size(adapter.problem.initial_values)),
    adapter.problem.initial_tick,
    0,
)

struct IndependentCustomCompletion <: AbstractCompletionHandle
    invocation_id::String
    target::LogicalTime
end

struct IndependentCustomCandidate
    invocation_id::String
    target_tick::Int64
    publication_epoch::UInt64
end

function _bounded_forcing(instance, invocation)
    length(invocation.inputs) == 1 &&
        only(invocation.inputs).name === :forcing ||
        _fail(:invalid_field_forcing_projection,
            "bounded field advance requires one forcing projection")
    forcing = projection_value(only(invocation.inputs))
    forcing isa AbstractArray &&
        size(forcing) == size(instance.forcing) &&
        eltype(forcing) == eltype(instance.forcing) ||
        _fail(:invalid_field_forcing,
            "bounded field forcing has incompatible shape or precision")
    forcing
end

function _bounded_resource_authorization(instance, invocation)
    precision = eltype(instance.published) === Float32 ?
        :float32 : :float64
    expected = (backend=:cpu, precision=precision, residency=:host)
    all(key -> haskey(invocation.resource_authorization, key) &&
        getproperty(invocation.resource_authorization, key) ==
            getproperty(expected, key), keys(expected)) ||
        _fail(:field_resource_unauthorized,
            "bounded field requires explicit CPU/precision/host authorization")
    true
end

function stage_operation!(
    instance::IndependentCustomFieldInstance,
    invocation::EngineInvocation,
)
    operation = invocation.operation
    operation isa IntervalAdvance ||
        _fail(:unsupported_engine_operation,
            "custom field supports only interval advance")
    isnothing(instance.active_invocation) ||
        _fail(:field_candidate_in_flight,
            "custom field already has an active candidate")
    operation.start_time ==
        LogicalTime(instance.time_tick, instance.problem.time_scale) ||
        _fail(:field_clock_mismatch,
            "custom field and ProcessBigraphs clocks disagree")
    _bounded_resource_authorization(instance, invocation)
    forcing = _bounded_forcing(instance, invocation)
    instance.prior_forcing = copy(instance.forcing)
    copyto!(instance.forcing, forcing)
    dt = _bounded_field_stability(instance.problem)
    steps = Base.Checked.checked_mul(
        operation.target_time.tick - operation.start_time.tick,
        instance.problem.substeps_per_tick,
    )
    input = instance.published
    output = instance.first
    try
        for step in 1:steps
            for index in CartesianIndices(input)
                @inbounds center = input[index]
                candidate = center + dt * (
                    instance.problem.diffusion *
                        _periodic_laplacian(
                            input, index, instance.problem.spacing) +
                    instance.forcing[index] -
                    instance.problem.decay * center
                )
                isfinite(candidate) &&
                    (!instance.problem.reject_negative ||
                     candidate >= zero(candidate)) ||
                    _fail(:invalid_field_candidate,
                        "custom field produced an invalid candidate";
                        index=Tuple(index))
                @inbounds output[index] = candidate
            end
            input = output
            output = isodd(step) ? instance.second : instance.first
        end
    catch
        copyto!(instance.forcing, instance.prior_forcing)
        instance.prior_forcing = nothing
        rethrow()
    end
    instance.candidate = input
    instance.target_tick = operation.target_time.tick
    instance.active_invocation = invocation.id
    IndependentCustomCompletion(invocation.id, operation.target_time)
end

function complete_operation!(
    instance::IndependentCustomFieldInstance,
    handle::IndependentCustomCompletion,
)
    instance.active_invocation == handle.invocation_id ||
        _fail(:field_completion_owner_mismatch,
            "custom field completion does not own the candidate")
    token = IndependentCustomCandidate(
        handle.invocation_id,
        instance.target_tick,
        Base.Checked.checked_add(
            instance.publication_epoch, UInt64(1)),
    )
    EngineCandidate(
        handle.target,
        token;
        effects=(:field_state => (
            target_tick=token.target_tick,
            publication_epoch=token.publication_epoch,
        ),),
        diagnostics=(backend=:cpu, algorithm=:independent_custom_euler),
        fingerprint=canonical_fingerprint((
            INDEPENDENT_CUSTOM_FIELD_VERSION,
            token.invocation_id,
            token.target_tick,
            token.publication_epoch,
        )),
    )
end

function publish_candidate!(
    instance::IndependentCustomFieldInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate{<:IndependentCustomCandidate},
)
    instance.active_invocation == invocation.id &&
        candidate.payload.invocation_id == invocation.id ||
        _fail(:field_candidate_owner_mismatch,
            "custom field candidate belongs to another invocation")
    prior = instance.published
    if instance.candidate === instance.first
        instance.published = instance.first
        instance.first = prior
    elseif instance.candidate === instance.second
        instance.published = instance.second
        instance.second = prior
    else
        _fail(:field_candidate_buffer_mismatch,
            "custom field candidate is not an owned staging buffer")
    end
    instance.candidate = instance.published
    instance.time_tick = instance.target_tick
    instance.publication_epoch =
        candidate.payload.publication_epoch
    instance.prior_forcing = nothing
    instance.active_invocation = nothing
    (
        time_tick=instance.time_tick,
        publication_epoch=instance.publication_epoch,
    )
end

function discard_candidate!(
    instance::IndependentCustomFieldInstance,
    invocation::EngineInvocation,
    candidate,
)
    if instance.active_invocation == invocation.id
        instance.candidate = instance.published
        instance.target_tick = instance.time_tick
        if !isnothing(instance.prior_forcing)
            copyto!(instance.forcing, instance.prior_forcing)
        end
        instance.prior_forcing = nothing
        instance.active_invocation = nothing
    end
    nothing
end

custom_field_snapshot(instance::IndependentCustomFieldInstance) =
    copy(instance.published)
field_engine_snapshot(instance::IndependentCustomFieldInstance) =
    custom_field_snapshot(instance)

function engine_checkpoint_payload(
    instance::IndependentCustomFieldInstance,
    declaration::EngineDeclaration,
)
    isnothing(instance.active_invocation) ||
        _fail(:unsettled_checkpoint,
            "custom field checkpoint requires a settled candidate boundary")
    CheckpointComponent(
        declaration.id,
        "independent-custom-field-checkpoint-v1",
        :exact,
        (
            declaration_fingerprint=declaration.fingerprint,
            values=copy(instance.published),
            forcing=copy(instance.forcing),
            time_tick=instance.time_tick,
            publication_epoch=instance.publication_epoch,
        ),
    )
end

function restore_engine_checkpoint(
    adapter::IndependentCustomFieldAdapter,
    declaration::EngineDeclaration,
    payload::NamedTuple,
)
    payload.declaration_fingerprint == declaration.fingerprint ||
        _fail(:checkpoint_engine_declaration_mismatch,
            "custom field declaration changed")
    _independent_custom_instance(
        adapter.problem,
        payload.values,
        payload.forcing,
        payload.time_tick,
        payload.publication_epoch,
    )
end

function sciml_field_adapter end
function sciml_field_declaration end
function field_engine_snapshot end
