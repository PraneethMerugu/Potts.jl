const COREPOTTS_PROCESS_BIGRAPH_ADAPTER_VERSION =
    "corepotts-process-bigraph-native-field-v1"
const COREPOTTS_PROCESS_BIGRAPH_CHECKPOINT_VERSION =
    "corepotts-native-field-checkpoint-v1"

"""
An immutable CorePotts native-field configuration. ProcessBigraphs owns invocation
time, placement authorization, validation, and publication; the resulting
`NativeFieldEngine` continues to own its numerical buffers and kernels.
"""
struct CorePottsNativeFieldAdapter{
        N,T<:AbstractFloat,B<:Tuple} <: ProcessBigraphs.AbstractEngineAdapter
    name::Symbol
    initial_values::Array{T,N}
    geometry::NativeFieldGeometry{N,T}
    boundaries::B
    diffusion::T
    decay::T
    tick_duration::T
    substeps_per_tick::Int
    reject_negative::Bool
    initial_tick::Int64
    block_size::Int
    time_scale::ProcessBigraphs.TimeScale
end

function CorePottsNativeFieldAdapter(
    name::Symbol,
    values::AbstractArray{T,N};
    geometry=NativeFieldGeometry(size(values); number_type=T),
    boundaries=_native_periodic_boundaries(T, N),
    diffusion::Real,
    decay::Real=0,
    tick_duration::Real=1,
    substeps_per_tick::Integer=1,
    reject_negative::Bool=true,
    initial_tick::Integer=0,
    block_size::Integer=DEFAULT_BLOCK_SIZE,
    time_scale::ProcessBigraphs.TimeScale,
) where {T<:AbstractFloat,N}
    block_size > 0 ||
        throw(ArgumentError("native-field adapter block size must be positive"))
    block_size <= typemax(Int) ||
        throw(ArgumentError("native-field adapter block size exceeds Int"))
    typemin(Int64) <= initial_tick <= typemax(Int64) ||
        throw(ArgumentError("native-field adapter initial tick must fit Int64"))
    # Construct once to apply the native engine's complete semantic validation.
    prototype = NativeFieldEngine(
        name,
        Array(values),
        ExecutionPlan(KernelAbstractions.CPU(); block_size=Int(block_size));
        geometry,
        boundaries,
        diffusion,
        decay,
        tick_duration,
        substeps_per_tick,
        reject_negative,
        time_tick=initial_tick,
    )
    physical_tick = T(time_scale.numerator) / T(time_scale.denominator)
    physical_tick == prototype.tick_duration ||
        throw(ArgumentError(
            "ProcessBigraphs time scale must equal the native-field tick duration"))
    CorePottsNativeFieldAdapter(
        name,
        copy(prototype.published),
        prototype.geometry,
        prototype.boundaries,
        prototype.diffusion,
        prototype.decay,
        prototype.tick_duration,
        prototype.substeps_per_tick,
        prototype.reject_negative,
        prototype.time_tick,
        Int(block_size),
        time_scale,
    )
end

function _process_bigraph_boundary_payload(face::AbstractFieldBoundary)
    face isa PeriodicFieldBoundary && return (kind=:periodic,)
    face isa ZeroNeumannFieldBoundary && return (kind=:neumann, flux=0)
    face isa DirichletFieldBoundary &&
        return (kind=:dirichlet, value=face.value)
    face isa MixedFieldBoundary &&
        return (
            kind=:mixed,
            alpha=face.alpha,
            beta=face.beta,
            value=face.value,
        )
    throw(ArgumentError("unsupported native-field boundary"))
end

_process_bigraph_boundary_payload(boundary::AxisFieldBoundary) = (
    negative=_process_bigraph_boundary_payload(boundary.negative),
    positive=_process_bigraph_boundary_payload(boundary.positive),
)

function ProcessBigraphs.engine_semantic_parameters(
    adapter::CorePottsNativeFieldAdapter,
)
    (
        contract_version=COREPOTTS_PROCESS_BIGRAPH_ADAPTER_VERSION,
        name=adapter.name,
        initial_values=copy(adapter.initial_values),
        dimensions=adapter.geometry.dimensions,
        origin=adapter.geometry.origin,
        spacing=adapter.geometry.spacing,
        boundaries=tuple((_process_bigraph_boundary_payload(boundary)
            for boundary in adapter.boundaries)...),
        diffusion=adapter.diffusion,
        decay=adapter.decay,
        tick_duration=adapter.tick_duration,
        substeps_per_tick=adapter.substeps_per_tick,
        reject_negative=adapter.reject_negative,
        initial_tick=adapter.initial_tick,
        block_size=adapter.block_size,
        time_scale=(
            numerator=adapter.time_scale.numerator,
            denominator=adapter.time_scale.denominator,
            unit=adapter.time_scale.unit,
        ),
    )
end

ProcessBigraphs.engine_semantic_version(
    ::CorePottsNativeFieldAdapter,
) = "1.0.0"

function corepotts_native_field_declaration(
    id::AbstractString,
    adapter::CorePottsNativeFieldAdapter,
)
    T = eltype(adapter.initial_values)
    precision = T === Float32 ? :float32 :
        T === Float64 ? :float64 :
        throw(ArgumentError(
            "the Phase 16 native-field adapter supports Float32 or Float64"))
    kinds = unique!(Symbol[
        _process_bigraph_boundary_payload(face).kind
        for axis in adapter.boundaries
        for face in (axis.negative, axis.positive)
    ])
    sort!(kinds; by=String)
    capabilities = ProcessBigraphs.EngineCapabilities(
        operation_families=(:interval_advance,),
        problem_envelopes=("corepotts-native-cartesian-field",),
        backends=(:cpu,),
        precisions=(precision,),
        residencies=(:host,),
        input_modes=(:frozen,),
        boundary_kinds=tuple(kinds...),
        continuation_actions=(:preserve, :reconstruct, :reject),
        replay_class=:exact,
        cancellation=false,
        diagnostics=true,
        resize=false,
        bridges=(),
    )
    ProcessBigraphs.EngineDeclaration(
        id, adapter; capabilities)
end

function process_bigraph_native_field_runtime(
    id::AbstractString,
    adapter::CorePottsNativeFieldAdapter;
    structural_epoch::AbstractString,
)
    declaration = corepotts_native_field_declaration(id, adapter)
    ProcessBigraphs.managed_engine_runtime(
        declaration,
        ProcessBigraphs.LogicalTime(
            adapter.initial_tick, adapter.time_scale);
        structural_epoch,
    )
end

function corepotts_cell_structural_request(
    request_id::AbstractString,
    source_epoch::Integer,
    operation::Symbol,
    cell::CellID,
    generation::CellGeneration;
    payload::NamedTuple=NamedTuple(),
    dependencies=(),
    priority::Integer=0,
)
    target = ProcessBigraphs.DomainStructuralIdentity(
        "corepotts",
        :cell,
        string(value(cell)),
        value(generation),
    )
    ProcessBigraphs.DomainStructuralRequest(
        request_id,
        "corepotts",
        source_epoch,
        operation,
        (target,);
        payload,
        dependencies,
        priority,
    )
end

mutable struct CorePottsNativeFieldInstance{
        E<:NativeFieldEngine} <: ProcessBigraphs.AbstractEngineInstance
    engine::E
    time_scale::ProcessBigraphs.TimeScale
    prior_forcing::Union{Nothing,Array}
    active_invocation::Union{Nothing,String}
end

function _new_native_field_instance(
    adapter::CorePottsNativeFieldAdapter,
    values,
    forcing,
    time_tick::Integer,
    publication_epoch::Integer,
)
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size=adapter.block_size)
    engine = NativeFieldEngine(
        adapter.name,
        values,
        plan;
        geometry=adapter.geometry,
        boundaries=adapter.boundaries,
        diffusion=adapter.diffusion,
        decay=adapter.decay,
        tick_duration=adapter.tick_duration,
        substeps_per_tick=adapter.substeps_per_tick,
        reject_negative=adapter.reject_negative,
        time_tick,
    )
    size(forcing) == size(engine.forcing) ||
        throw(ArgumentError(
            "restored native-field forcing has incompatible dimensions"))
    copyto!(engine.forcing, forcing)
    publication_epoch >= 0 &&
        publication_epoch <= typemax(UInt64) ||
        throw(ArgumentError(
            "native-field publication epoch must fit UInt64"))
    engine.publication_epoch = UInt64(publication_epoch)
    CorePottsNativeFieldInstance(
        engine, adapter.time_scale, nothing, nothing)
end

function ProcessBigraphs.prepare_engine(
    adapter::CorePottsNativeFieldAdapter,
    declaration::ProcessBigraphs.EngineDeclaration,
)
    declaration.adapter === adapter ||
        throw(ArgumentError("native-field declaration adapter changed"))
    _new_native_field_instance(
        adapter,
        adapter.initial_values,
        zeros(eltype(adapter.initial_values), size(adapter.initial_values)),
        adapter.initial_tick,
        0,
    )
end

struct CorePottsNativeCompletionHandle <: ProcessBigraphs.AbstractCompletionHandle
    invocation_id::String
    target::ProcessBigraphs.LogicalTime
end

struct CorePottsNativeCandidateToken
    invocation_id::String
    field::Symbol
    target_tick::Int64
    publication_epoch::UInt64
end

struct CorePottsNativePublication
    field::Symbol
    time_tick::Int64
    publication_epoch::UInt64
end

function _required_native_resource_authorization(
    invocation::ProcessBigraphs.EngineInvocation,
    ::Type{T},
) where {T}
    expected_precision = T === Float32 ? :float32 : :float64
    required = (
        backend=:cpu,
        precision=expected_precision,
        residency=:host,
    )
    all(key -> haskey(invocation.resource_authorization, key), keys(required)) ||
        throw(ArgumentError(
            "native-field invocation requires explicit backend, precision, and residency authorization"))
    all(key -> getproperty(invocation.resource_authorization, key) ==
            getproperty(required, key), keys(required)) ||
        throw(ArgumentError(
            "native-field invocation resource authorization is incompatible"))
    required
end

function _forcing_projection(
    invocation::ProcessBigraphs.EngineInvocation,
    engine::NativeFieldEngine,
)
    length(invocation.inputs) == 1 &&
        only(invocation.inputs).name === :forcing ||
        throw(ArgumentError(
            "native-field invocation requires exactly one `forcing` projection"))
    projection = only(invocation.inputs)
    projection.mode === :frozen ||
        throw(ArgumentError("native-field forcing must be frozen"))
    forcing = ProcessBigraphs.projection_value(projection)
    forcing isa AbstractArray ||
        throw(ArgumentError("native-field forcing must be an array"))
    size(forcing) == size(engine.forcing) ||
        throw(ArgumentError(
            "native-field forcing dimensions do not match the field"))
    eltype(forcing) == eltype(engine.forcing) ||
        throw(ArgumentError(
            "native-field forcing precision does not match the field"))
    forcing
end

function ProcessBigraphs.stage_operation!(
    instance::CorePottsNativeFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
)
    invocation.operation isa ProcessBigraphs.IntervalAdvance ||
        throw(ArgumentError(
            "native-field adapter supports only interval advances"))
    isnothing(instance.active_invocation) ||
        throw(ArgumentError(
            "native-field adapter already has an active invocation"))
    operation = invocation.operation
    operation.start_time.tick == instance.engine.time_tick ||
        throw(ArgumentError(
            "ProcessBigraphs and native-field start clocks disagree"))
    operation.start_time.scale == instance.time_scale &&
        operation.target_time.scale == instance.time_scale ||
        throw(ArgumentError(
            "ProcessBigraphs and native-field time scales disagree"))
    _required_native_resource_authorization(
        invocation, eltype(instance.engine.published))
    forcing = _forcing_projection(invocation, instance.engine)
    instance.prior_forcing = copy(instance.engine.forcing)
    copyto!(instance.engine.forcing, forcing)
    instance.active_invocation = invocation.id
    try
        stage_native_field!(instance.engine, operation.target_time.tick)
    catch
        copyto!(instance.engine.forcing, instance.prior_forcing)
        instance.prior_forcing = nothing
        instance.active_invocation = nothing
        rethrow()
    end
    CorePottsNativeCompletionHandle(invocation.id, operation.target_time)
end

function ProcessBigraphs.complete_operation!(
    instance::CorePottsNativeFieldInstance,
    handle::CorePottsNativeCompletionHandle,
)
    instance.active_invocation == handle.invocation_id ||
        throw(ArgumentError(
            "native-field completion handle does not own the staged candidate"))
    complete_native_field!(instance.engine)
    token = CorePottsNativeCandidateToken(
        handle.invocation_id,
        instance.engine.name,
        instance.engine.target_tick,
        Base.Checked.checked_add(
            instance.engine.publication_epoch, UInt64(1)),
    )
    ProcessBigraphs.EngineCandidate(
        handle.target,
        token;
        effects=(
            :field_state => (
                field=instance.engine.name,
                target_tick=instance.engine.target_tick,
                publication_epoch=token.publication_epoch,
            ),
        ),
        diagnostics=(
            backend=:cpu,
            precision=eltype(instance.engine.published) === Float32 ?
                :float32 : :float64,
        ),
        fingerprint=ProcessBigraphs.canonical_fingerprint((
            COREPOTTS_PROCESS_BIGRAPH_ADAPTER_VERSION,
            token.invocation_id,
            token.field,
            token.target_tick,
            token.publication_epoch,
        )),
    )
end

function ProcessBigraphs.publish_candidate!(
    instance::CorePottsNativeFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
    candidate::ProcessBigraphs.EngineCandidate{
        <:CorePottsNativeCandidateToken},
)
    candidate.payload.invocation_id == invocation.id &&
        instance.active_invocation == invocation.id ||
        throw(ArgumentError(
            "native-field candidate does not belong to this invocation"))
    publish_native_field!(instance.engine)
    instance.prior_forcing = nothing
    instance.active_invocation = nothing
    CorePottsNativePublication(
        instance.engine.name,
        instance.engine.time_tick,
        instance.engine.publication_epoch,
    )
end

function ProcessBigraphs.discard_candidate!(
    instance::CorePottsNativeFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
    candidate,
)
    if instance.active_invocation == invocation.id
        discard_native_field!(instance.engine)
        if !isnothing(instance.prior_forcing)
            copyto!(instance.engine.forcing, instance.prior_forcing)
        end
        instance.prior_forcing = nothing
        instance.active_invocation = nothing
    end
    nothing
end

function ProcessBigraphs.engine_checkpoint_payload(
    instance::CorePottsNativeFieldInstance,
    declaration::ProcessBigraphs.EngineDeclaration,
)
    isnothing(instance.active_invocation) ||
        throw(ArgumentError(
            "cannot checkpoint an in-flight native-field invocation"))
    engine = instance.engine
    ProcessBigraphs.CheckpointComponent(
        declaration.id,
        COREPOTTS_PROCESS_BIGRAPH_CHECKPOINT_VERSION,
        :exact,
        (
            declaration_fingerprint=declaration.fingerprint,
            values=native_field_snapshot(engine),
            forcing=Array(engine.forcing),
            time_tick=engine.time_tick,
            publication_epoch=engine.publication_epoch,
        ),
    )
end

function ProcessBigraphs.restore_engine_checkpoint(
    adapter::CorePottsNativeFieldAdapter,
    declaration::ProcessBigraphs.EngineDeclaration,
    payload::NamedTuple,
)
    payload.declaration_fingerprint == declaration.fingerprint ||
        throw(ArgumentError(
            "native-field checkpoint declaration fingerprint changed"))
    _new_native_field_instance(
        adapter,
        payload.values,
        payload.forcing,
        payload.time_tick,
        payload.publication_epoch,
    )
end

function process_bigraph_native_field_snapshot(
    runtime::ProcessBigraphs.ManagedEngineRuntime,
)
    runtime.instance isa CorePottsNativeFieldInstance ||
        throw(ArgumentError(
            "managed runtime does not contain a CorePotts native field"))
    native_field_snapshot(runtime.instance.engine)
end
