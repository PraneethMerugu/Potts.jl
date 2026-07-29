struct NativeFieldGeometry{N,T<:AbstractFloat}
    dimensions::NTuple{N,Int}
    origin::NTuple{N,T}
    spacing::NTuple{N,T}
end

function NativeFieldGeometry(
    dimensions::NTuple{N,<:Integer};
    origin=ntuple(_ -> 0.0, N),
    spacing=ntuple(_ -> 1.0, N),
    number_type::Type{T}=Float32,
) where {N,T<:AbstractFloat}
    N in (2, 3) ||
        throw(ArgumentError("native fields support two or three dimensions"))
    all(>(0), dimensions) ||
        throw(ArgumentError("native field dimensions must be positive"))
    normalized_origin = ntuple(i -> T(origin[i]), N)
    normalized_spacing = ntuple(i -> T(spacing[i]), N)
    all(isfinite, normalized_origin) ||
        throw(ArgumentError("native field origin must be finite"))
    all(value -> isfinite(value) && value > zero(T), normalized_spacing) ||
        throw(ArgumentError("native field spacing must be finite and positive"))
    NativeFieldGeometry(
        ntuple(i -> Int(dimensions[i]), N),
        normalized_origin,
        normalized_spacing,
    )
end

function _native_periodic_boundaries(::Type{T}, rank::Integer) where {
        T<:AbstractFloat}
    ntuple(_ -> AxisFieldBoundary(PeriodicFieldBoundary()), rank)
end

mutable struct NativeFieldEngine{N,T<:AbstractFloat,A<:AbstractArray{T,N},
        B<:Tuple,P<:ExecutionPlan,S<:AbstractVector{UInt32}}
    name::Symbol
    geometry::NativeFieldGeometry{N,T}
    boundaries::B
    diffusion::T
    decay::T
    tick_duration::T
    substeps_per_tick::Int
    reject_negative::Bool
    plan::P
    published::A
    first::A
    second::A
    forcing::A
    decay_weights::A
    status::S
    failing_index::S
    candidate::A
    time_tick::Int64
    target_tick::Int64
    publication_epoch::UInt64
    staged::Bool
    completed::Bool
end

function _validate_native_boundaries(boundaries::Tuple, rank::Int, ::Type{T}) where {
        T<:AbstractFloat}
    length(boundaries) == rank ||
        throw(ArgumentError(
            "native fields require one low/high boundary pair per axis"))
    for boundary in boundaries
        boundary isa AxisFieldBoundary ||
            throw(ArgumentError(
                "native field boundaries must be AxisFieldBoundary values"))
        for face in (boundary.negative, boundary.positive)
            face isa Union{PeriodicFieldBoundary,ZeroNeumannFieldBoundary,
                DirichletFieldBoundary,MixedFieldBoundary} ||
                throw(ArgumentError("unsupported native field boundary face"))
            if face isa DirichletFieldBoundary
                convert(T, face.value)
            elseif face isa MixedFieldBoundary
                convert(T, face.alpha)
                convert(T, face.beta)
                convert(T, face.value)
            end
        end
    end
    boundaries
end

function NativeFieldEngine(
    name::Symbol,
    values::AbstractArray{T,N},
    plan::ExecutionPlan;
    geometry=NativeFieldGeometry(size(values); number_type=T),
    boundaries=_native_periodic_boundaries(T, N),
    diffusion::Real,
    decay::Real=0,
    decay_weights=ones(T, size(values)),
    tick_duration::Real=1,
    substeps_per_tick::Integer=1,
    reject_negative::Bool=true,
    time_tick::Integer=0,
) where {T<:AbstractFloat,N}
    geometry.dimensions == size(values) ||
        throw(ArgumentError(
            "native field geometry and array dimensions differ"))
    normalized_boundaries = _validate_native_boundaries(boundaries, N, T)
    normalized_diffusion = T(diffusion)
    normalized_decay = T(decay)
    normalized_decay_weights = Array{T,N}(decay_weights)
    normalized_tick = T(tick_duration)
    isfinite(normalized_diffusion) && normalized_diffusion >= zero(T) ||
        throw(ArgumentError(
            "native field diffusion must be finite and nonnegative"))
    isfinite(normalized_decay) && normalized_decay >= zero(T) ||
        throw(ArgumentError("native field decay must be finite and nonnegative"))
    size(normalized_decay_weights) == size(values) ||
        throw(ArgumentError(
            "native field decay weights must match the field dimensions"))
    all(value -> isfinite(value) && value >= zero(T),
        normalized_decay_weights) ||
        throw(ArgumentError(
            "native field decay weights must be finite and nonnegative"))
    isfinite(normalized_tick) && normalized_tick > zero(T) ||
        throw(ArgumentError(
            "native field tick duration must be finite and positive"))
    substeps_per_tick > 0 ||
        throw(ArgumentError("native field substeps per tick must be positive"))
    typemin(Int64) <= time_tick <= typemax(Int64) ||
        throw(ArgumentError("native field time tick must fit Int64"))
    published = copy(values)
    first = similar(values)
    second = similar(values)
    forcing = similar(values)
    owned_decay_weights = similar(values)
    arrays = (published, first, second, forcing, owned_decay_weights)
    all(array -> isequal(
            KernelAbstractions.get_backend(array), plan.backend), arrays) ||
        throw(ArgumentError(
            "native field arrays and execution plan backend differ"))
    fill!(first, zero(T))
    fill!(second, zero(T))
    fill!(forcing, zero(T))
    copyto!(owned_decay_weights, normalized_decay_weights)
    status = similar(values, UInt32, 1)
    failing_index = similar(values, UInt32, 1)
    fill!(status, UInt32(0))
    fill!(failing_index, UInt32(0))
    NativeFieldEngine(
        name,
        geometry,
        normalized_boundaries,
        normalized_diffusion,
        normalized_decay,
        normalized_tick,
        Int(substeps_per_tick),
        reject_negative,
        plan,
        published,
        first,
        second,
        forcing,
        owned_decay_weights,
        status,
        failing_index,
        published,
        Int64(time_tick),
        Int64(time_tick),
        UInt64(0),
        false,
        false,
    )
end

@inline function _native_axis_stride(
        dimensions::NTuple{N,Int},
        ::Val{D},
) where {N,D}
    stride = 1
    for axis in 1:(D - 1)
        stride *= dimensions[axis]
    end
    stride
end

@inline function _native_boundary_value(
    ::PeriodicFieldBoundary,
    input,
    cell,
    stride,
    coordinate,
    extent,
    delta,
    center,
    spacing,
)
    @inbounds input[
        cell + (delta < 0 ? extent - 1 : -(extent - 1)) * stride]
end

@inline _native_boundary_value(
    ::ZeroNeumannFieldBoundary,
    input,
    cell,
    stride,
    coordinate,
    extent,
    delta,
    center,
    spacing,
) = center

@inline _native_boundary_value(
    boundary::DirichletFieldBoundary,
    input,
    cell,
    stride,
    coordinate,
    extent,
    delta,
    center,
    spacing,
) = convert(typeof(center), boundary.value)

@inline function _native_boundary_value(
    boundary::MixedFieldBoundary,
    input,
    cell,
    stride,
    coordinate,
    extent,
    delta,
    center,
    spacing,
)
    T = typeof(center)
    alpha = T(boundary.alpha)
    beta = T(boundary.beta)
    value = T(boundary.value)
    iszero(beta) && return value / alpha
    center + spacing * (value - alpha * center) / beta
end

@inline function _native_axis_neighbor(
    input,
    cell::Int,
    geometry::NativeFieldGeometry{N,T},
    boundary::AxisFieldBoundary,
    ::Val{D},
    delta::Int,
    center,
) where {N,T,D}
    stride = _native_axis_stride(geometry.dimensions, Val(D))
    extent = geometry.dimensions[D]
    coordinate = mod(div(cell - 1, stride), extent) + 1
    shifted = coordinate + delta
    if 1 <= shifted <= extent
        return @inbounds input[cell + delta * stride]
    end
    face = delta < 0 ? boundary.negative : boundary.positive
    _native_boundary_value(
        face,
        input,
        cell,
        stride,
        coordinate,
        extent,
        delta,
        center,
        geometry.spacing[D],
    )
end

@generated function _native_laplacian(
    input,
    cell::Int,
    geometry::NativeFieldGeometry{N,T},
    boundaries::B,
    center,
) where {N,T,B<:Tuple}
    terms = [
        :((_native_axis_neighbor(
            input, cell, geometry, getfield(boundaries, $axis),
            Val($axis), -1, center) +
           _native_axis_neighbor(
            input, cell, geometry, getfield(boundaries, $axis),
            Val($axis), 1, center) -
           2center) / (geometry.spacing[$axis] * geometry.spacing[$axis]))
        for axis in 1:N
    ]
    foldl((left, right) -> :($left + $right), terms)
end

@inline function _native_record_failure!(
    status,
    failing_index,
    site,
)
    Atomix.@atomic max(status[1], UInt32(1))
    Atomix.@atomic min(failing_index[1], UInt32(site))
    nothing
end

@kernel function _native_field_clear_status!(status, failing_index)
    site = @index(Global, Linear)
    @inbounds if site == 1
        status[1] = UInt32(0)
        failing_index[1] = typemax(UInt32)
    end
end

@kernel function _native_field_substep!(
    output,
    input,
    forcing,
    decay_weights,
    geometry,
    boundaries,
    diffusion,
    decay,
    dt,
    reject_negative,
    status,
    failing_index,
)
    site = @index(Global, Linear)
    @inbounds center = input[site]
    laplacian = _native_laplacian(
        input, Int(site), geometry, boundaries, center)
    candidate = muladd(
        dt,
        muladd(
            diffusion,
            laplacian,
            forcing[site] - decay * decay_weights[site] * center,
        ),
        center,
    )
    if isfinite(candidate) &&
       (!reject_negative || candidate >= zero(candidate))
        @inbounds output[site] = candidate
    else
        _native_record_failure!(status, failing_index, site)
    end
end

function _native_stability_check(
    engine::NativeFieldEngine,
    step_count::Int,
)
    step_count > 0 ||
        throw(ArgumentError(
            "native field advance requires at least one substep"))
    dt = engine.tick_duration / engine.substeps_per_tick
    coefficient = zero(dt)
    for spacing in engine.geometry.spacing
        coefficient += engine.diffusion * dt / (spacing * spacing)
    end
    coefficient <= convert(typeof(coefficient), 0.5) ||
        throw(ArgumentError(
            "native explicit field step exceeds the multidimensional stability limit"))
    dt
end

function _stage_native_field!(
    ::KernelAbstractions.Backend,
    engine::NativeFieldEngine,
    target_tick::Integer,
)
    engine.staged &&
        throw(ArgumentError(
            "native field engine already has a staged candidate"))
    engine.time_tick < target_tick <= typemax(Int64) ||
        throw(ArgumentError(
            "native field target tick must advance exact logical time"))
    delta_ticks = Int64(target_tick) - engine.time_tick
    step_count = Base.Checked.checked_mul(
        Int(delta_ticks), engine.substeps_per_tick)
    dt = _native_stability_check(engine, step_count)
    clear = _execution_kernel(
        engine.plan, _native_field_clear_status!, 1)
    launch!(
        engine.plan,
        clear,
        engine.status,
        engine.failing_index;
        ndrange=1,
    )
    input = engine.published
    output = engine.first
    for step in 1:step_count
        kernel = _execution_kernel(
            engine.plan, _native_field_substep!, length(input))
        launch!(
            engine.plan,
            kernel,
            output,
            input,
            engine.forcing,
            engine.decay_weights,
            engine.geometry,
            engine.boundaries,
            engine.diffusion,
            engine.decay,
            dt,
            engine.reject_negative,
            engine.status,
            engine.failing_index;
            ndrange=length(input),
        )
        input = output
        output = isodd(step) ? engine.second : engine.first
    end
    engine.candidate = input
    engine.target_tick = Int64(target_tick)
    engine.staged = true
    engine.completed = false
    engine
end

function _stage_native_field!(
    ::KernelAbstractions.CPU,
    engine::NativeFieldEngine,
    target_tick::Integer,
)
    engine.staged &&
        throw(ArgumentError(
            "native field engine already has a staged candidate"))
    engine.time_tick < target_tick <= typemax(Int64) ||
        throw(ArgumentError(
            "native field target tick must advance exact logical time"))
    delta_ticks = Int64(target_tick) - engine.time_tick
    step_count = Base.Checked.checked_mul(
        Int(delta_ticks), engine.substeps_per_tick)
    dt = _native_stability_check(engine, step_count)
    engine.status[1] = UInt32(0)
    engine.failing_index[1] = typemax(UInt32)
    engine.plan.metrics.launches += 1
    input = engine.published
    output = engine.first
    for step in 1:step_count
        engine.plan.metrics.launches += 1
        for site in eachindex(input)
            @inbounds center = input[site]
            laplacian = _native_laplacian(
                input, Int(site), engine.geometry,
                engine.boundaries, center)
            candidate = muladd(
                dt,
                muladd(
                    engine.diffusion,
                    laplacian,
                    @inbounds(engine.forcing[site]) -
                    engine.decay *
                    @inbounds(engine.decay_weights[site]) * center,
                ),
                center,
            )
            if isfinite(candidate) &&
               (!engine.reject_negative || candidate >= zero(candidate))
                @inbounds output[site] = candidate
            else
                engine.status[1] = UInt32(1)
                engine.failing_index[1] =
                    min(engine.failing_index[1], UInt32(site))
            end
        end
        input = output
        output = isodd(step) ? engine.second : engine.first
    end
    engine.candidate = input
    engine.target_tick = Int64(target_tick)
    engine.staged = true
    engine.completed = false
    engine
end

stage_native_field!(engine::NativeFieldEngine, target_tick::Integer) =
    _stage_native_field!(engine.plan.backend, engine, target_tick)

function complete_native_field!(engine::NativeFieldEngine)
    engine.staged ||
        throw(ArgumentError(
            "native field engine has no staged candidate"))
    synchronize_observation!(engine.plan)
    if !(engine.plan.backend isa KernelAbstractions.CPU)
        record_transfer!(engine.plan, :device_to_host)
        record_transfer!(engine.plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, engine.status))
    if !iszero(status)
        failing = only(Adapt.adapt(Array, engine.failing_index))
        engine.completed = false
        throw(ArgumentError(
            "native field candidate failed at canonical index $(failing)"))
    end
    engine.completed = true
    engine
end

function publish_native_field!(engine::NativeFieldEngine)
    engine.staged && engine.completed ||
        throw(ArgumentError(
            "native field candidate is not complete and valid"))
    prior = engine.published
    if engine.candidate === engine.first
        engine.published = engine.first
        engine.first = prior
    elseif engine.candidate === engine.second
        engine.published = engine.second
        engine.second = prior
    else
        throw(ArgumentError(
            "native field candidate is not an owned staging buffer"))
    end
    engine.candidate = engine.published
    engine.time_tick = engine.target_tick
    engine.publication_epoch += UInt64(1)
    engine.staged = false
    engine.completed = false
    engine
end

function discard_native_field!(engine::NativeFieldEngine)
    engine.candidate = engine.published
    engine.target_tick = engine.time_tick
    engine.staged = false
    engine.completed = false
    engine
end

function advance_native_field!(
    engine::NativeFieldEngine,
    target_tick::Integer,
)
    stage_native_field!(engine, target_tick)
    try
        complete_native_field!(engine)
        publish_native_field!(engine)
    catch
        discard_native_field!(engine)
        rethrow()
    end
end

function adapt_native_field_engine(
    plan::ExecutionPlan,
    to,
    engine::NativeFieldEngine,
)
    engine.plan.backend isa KernelAbstractions.CPU ||
        throw(ArgumentError(
            "native field adaptation source must be CPU resident"))
    arrays = map(
        array -> Adapt.adapt(to, array),
        (
            engine.published,
            engine.first,
            engine.second,
            engine.forcing,
            engine.decay_weights,
            engine.status,
            engine.failing_index,
        ),
    )
    all(array -> isequal(
            KernelAbstractions.get_backend(array), plan.backend), arrays) ||
        throw(ArgumentError(
            "adapted native field arrays do not match the destination plan"))
    if !(plan.backend isa KernelAbstractions.CPU)
        for array in arrays
            record_transfer!(plan, :host_to_device)
            record_allocation!(plan, :device, _array_bytes(array))
        end
    end
    NativeFieldEngine(
        engine.name,
        engine.geometry,
        engine.boundaries,
        engine.diffusion,
        engine.decay,
        engine.tick_duration,
        engine.substeps_per_tick,
        engine.reject_negative,
        plan,
        arrays[1],
        arrays[2],
        arrays[3],
        arrays[4],
        arrays[5],
        arrays[6],
        arrays[7],
        arrays[1],
        engine.time_tick,
        engine.time_tick,
        engine.publication_epoch,
        false,
        false,
    )
end

function native_field_snapshot(engine::NativeFieldEngine)
    synchronize_observation!(engine.plan)
    if !(engine.plan.backend isa KernelAbstractions.CPU)
        record_transfer!(engine.plan, :device_to_host)
    end
    Array(engine.published)
end
