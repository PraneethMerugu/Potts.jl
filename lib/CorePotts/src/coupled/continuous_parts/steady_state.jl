struct SteadyStateAdvance{M, T, R}
    method::M
    absolute_tolerance::T
    relative_tolerance::T
    maximum_iterations::UInt32
    residual_norm::R
end

struct MaximumAbsoluteResidual end
(::MaximumAbsoluteResidual)(residual) = maximum(abs, residual)

function SteadyStateAdvance(method;
        absolute_tolerance::T,
        relative_tolerance::T,
        maximum_iterations::Integer,
        residual_norm = MaximumAbsoluteResidual()) where {T <: AbstractFloat}
    absolute_tolerance > zero(T) || throw(ArgumentError(
        "steady-state absolute tolerance must be positive"))
    relative_tolerance >= zero(T) || throw(ArgumentError(
        "steady-state relative tolerance must be non-negative"))
    maximum_iterations > 0 || throw(ArgumentError(
        "steady-state iteration bound must be positive"))
    return SteadyStateAdvance(method, absolute_tolerance,
        relative_tolerance, UInt32(maximum_iterations), residual_norm)
end

function _field_residual(candidate, state, law)
    laplacian = _field_laplacian(
        candidate, state.boundary, state.spacing)
    reaction = law.reaction === nothing ? zero.(candidate) :
        map(law.reaction, candidate)
    return law.diffusion .* laplacian .-
        law.decay .* candidate .+ reaction .+ state.forcing
end

function _steady_jacobi_step(candidate, state, law)
    dimension = ndims(candidate)
    coefficient = law.diffusion / (state.spacing * state.spacing)
    diagonal = 2dimension * coefficient + law.decay
    diagonal > zero(diagonal) || throw(ArgumentError(
        "steady-state reaction-diffusion operator is singular without decay"))
    next = similar(candidate)
    for index in CartesianIndices(candidate)
        neighbors = zero(eltype(candidate))
        for axis in 1:dimension
            neighbors += _field_neighbor(
                candidate, index, axis, -1, state.boundary)
            neighbors += _field_neighbor(
                candidate, index, axis, 1, state.boundary)
        end
        reaction = law.reaction === nothing ? zero(eltype(candidate)) :
            law.reaction(@inbounds candidate[index])
        @inbounds next[index] = (
            coefficient * neighbors + reaction + state.forcing[index]) /
            diagonal
    end
    return next
end

function _advance_field_method!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, method::SteadyStateAdvance,
        ownership)
    isempty(dynamics.post_substep) || throw(ArgumentError(
        "steady-state field advance does not support post-substep constraints"))
    law = dynamics.law
    law isa ReactionDiffusion || throw(ArgumentError(
        "stable steady-state field reference requires ReactionDiffusion"))
    method.method === :jacobi || throw(ArgumentError(
        "stable steady-state field reference supports only :jacobi"))
    candidate = copy(state.values)
    initial_norm = method.residual_norm(
        _field_residual(candidate, state, law))
    isfinite(initial_norm) || throw(ArgumentError(
        "steady-state initial residual is nonfinite"))
    threshold = method.absolute_tolerance +
        method.relative_tolerance * initial_norm
    residual = initial_norm
    iterations = 0
    while residual > threshold &&
            iterations < Int(method.maximum_iterations)
        candidate = _steady_jacobi_step(candidate, state, law)
        all(isfinite, candidate) || throw(ArgumentError(
            "steady-state field iteration produced nonfinite values"))
        residual = method.residual_norm(
            _field_residual(candidate, state, law))
        isfinite(residual) || throw(ArgumentError(
            "steady-state field residual is nonfinite"))
        iterations += 1
    end
    residual <= threshold || throw(ArgumentError(
        "steady-state field solver exceeded its iteration bound"))
    copyto!(state.values, candidate)
    state.time += interval
    state.publication_epoch[1] += UInt64(1)
    state.diagnostics = FieldAdvanceDiagnostics(
        0, zero(state.time), state.time, residual, threshold,
        iterations, true, :steady_state)
    return state
end
