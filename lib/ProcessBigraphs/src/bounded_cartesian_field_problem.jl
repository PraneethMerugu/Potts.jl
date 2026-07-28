const BOUNDED_CARTESIAN_FIELD_VERSION =
    "process-bigraph-bounded-cartesian-field-v2"

"""
    BoundedCartesianFieldProblem(id, values; ...)

A solver-neutral, bounded periodic Cartesian reaction-diffusion problem used to
qualify external field adapters. Numerical algorithms, step sizes, tolerances,
and solver continuations belong to adapter declarations rather than this
logical problem.
"""
struct BoundedCartesianFieldProblem{N,T<:AbstractFloat}
    id::String
    initial_values::Array{T,N}
    spacing::NTuple{N,T}
    diffusion::T
    decay::T
    tick_duration::T
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
        reject_negative,
        Int64(initial_tick),
        time_scale,
        canonical_fingerprint(payload),
    )
end

function sciml_field_adapter end
function sciml_field_declaration end
function field_engine_snapshot end
