struct FieldAdvanceWorkspace{A <: AbstractArray,
        S <: AbstractVector, I <: AbstractVector}
    first::A
    second::A
    status::S
    failing_index::I
end

struct FieldAdvanceDiagnostics{T}
    steps::Int
    dt::T
    endpoint::T
    residual::T
    threshold::T
    iterations::Int
    converged::Bool
    mode::Symbol
end

function Adapt.adapt_structure(to, workspace::FieldAdvanceWorkspace)
    return FieldAdvanceWorkspace(
        Adapt.adapt(to, workspace.first),
        Adapt.adapt(to, workspace.second),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index))
end

mutable struct EvolvingFieldState{A <: AbstractArray, T, B,
        E <: AbstractVector, W}
    name::Symbol
    values::A
    forcing::A
    spacing::T
    boundary::B
    time::T
    diagnostics::FieldAdvanceDiagnostics{T}
    publication_epoch::E
    workspace::W
end
function EvolvingFieldState(name::Symbol, values::AbstractArray{T};
        spacing = nothing, boundary = PeriodicFieldBoundary(),
        time = nothing) where {T <: AbstractFloat}
    resolved_spacing = spacing === nothing ? one(T) : convert(T, spacing)
    resolved_time = time === nothing ? zero(T) : convert(T, time)
    authoritative = copy(values)
    forcing = similar(authoritative)
    first = similar(authoritative)
    second = similar(authoritative)
    status = similar(authoritative, UInt32, 1)
    failing_index = similar(authoritative, UInt32, 1)
    publication_epoch = similar(authoritative, UInt64, 1)
    fill!(forcing, zero(T))
    fill!(first, zero(T))
    fill!(second, zero(T))
    fill!(status, UInt32(0))
    fill!(failing_index, UInt32(0))
    fill!(publication_epoch, UInt64(0))
    workspace = FieldAdvanceWorkspace(
        first, second, status, failing_index)
    diagnostics = FieldAdvanceDiagnostics(
        0, zero(T), resolved_time, zero(T), zero(T), 0, true, :uninitialized)
    return EvolvingFieldState(name, authoritative, forcing,
        resolved_spacing, boundary, resolved_time, diagnostics,
        publication_epoch, workspace)
end

function Adapt.adapt_structure(to, state::EvolvingFieldState)
    return EvolvingFieldState(
        state.name,
        Adapt.adapt(to, state.values),
        Adapt.adapt(to, state.forcing),
        state.spacing,
        state.boundary,
        state.time,
        state.diagnostics,
        Adapt.adapt(to, state.publication_epoch),
        Adapt.adapt(to, state.workspace))
end

struct ReactionDiffusion{T, R}
    diffusion::T
    decay::T
    reaction::R
end
function ReactionDiffusion(; diffusion::T, decay = nothing,
        reaction = nothing) where {T <: AbstractFloat}
    resolved_decay = decay === nothing ? zero(T) : convert(T, decay)
    return ReactionDiffusion(diffusion, resolved_decay, reaction)
end

struct FieldDynamics{L, M, C, P <: Tuple}
    name::Symbol
    field::Symbol
    law::L
    method::M
    clock::C
    post_substep::P
    version::VersionNumber
end
function FieldDynamics(name::Symbol; field::Symbol, law,
        method, clock, post_substep::Tuple = (),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    method isa Union{FixedStep, SteadyStateAdvance} || throw(ArgumentError(
        "FieldDynamics method must be FixedStep or SteadyStateAdvance"))
    return FieldDynamics(
        name, field, law, method, clock, post_substep, version)
end
component_identity(dynamics::FieldDynamics) =
    ComponentIdentity(dynamics.name, dynamics.version, :field_dynamics)
component_semantic_data(dynamics::FieldDynamics) = (
    field = dynamics.field, law = dynamics.law,
    method = dynamics.method, clock = dynamics.clock,
    post_substep = dynamics.post_substep)
process_reads(dynamics::FieldDynamics) = ((:field, dynamics.field),)
process_writes(dynamics::FieldDynamics) = ((:field, dynamics.field),)

function _field_neighbor(values, index::CartesianIndex, axis, delta,
        ::PeriodicFieldBoundary)
    coordinates = Tuple(index)
    size_axis = size(values, axis)
    shifted = Base.setindex(coordinates,
        mod1(coordinates[axis] + delta, size_axis), axis)
    return @inbounds values[shifted...]
end
function _field_neighbor(values, index::CartesianIndex, axis, delta,
        ::ZeroNeumannFieldBoundary)
    coordinates = Tuple(index)
    shifted = Base.setindex(coordinates,
        clamp(coordinates[axis] + delta, 1, size(values, axis)), axis)
    return @inbounds values[shifted...]
end
function _field_laplacian(values, boundary, spacing)
    result = similar(values)
    inverse_spacing2 = inv(spacing * spacing)
    for index in CartesianIndices(values)
        center = @inbounds values[index]
        value = zero(center)
        for axis in 1:ndims(values)
            value += _field_neighbor(values, index, axis, -1, boundary) +
                _field_neighbor(values, index, axis, 1, boundary) - 2center
        end
        @inbounds result[index] = value * inverse_spacing2
    end
    return result
end

@inline _field_reaction_value(::Nothing, value) = zero(value)
@inline _field_reaction_value(reaction, value) = reaction(value)

@inline function _periodic_reaction_diffusion_value(
        input, forcing, law, spacing, dt, row, column)
    rows, columns = size(input)
    left_column = column == 1 ? columns : column - 1
    right_column = column == columns ? 1 : column + 1
    down_row = row == 1 ? rows : row - 1
    up_row = row == rows ? 1 : row + 1
    @inbounds begin
        center = input[row, column]
        pair_x = input[row, left_column] + input[row, right_column]
        pair_y = input[down_row, column] + input[up_row, column]
        laplacian = ((pair_x + pair_y) - 4 * center) / (spacing * spacing)
        derivative = muladd(law.diffusion, laplacian,
            _field_reaction_value(law.reaction, center) +
            forcing[row, column] - law.decay * center)
        return muladd(dt, derivative, center)
    end
end

function _field_substep!(output::AbstractMatrix, input::AbstractMatrix,
        forcing, law, spacing, dt, ::PeriodicFieldBoundary,
        constraints::Tuple, ownership)
    for column in axes(input, 2), row in axes(input, 1)
        value = _periodic_reaction_diffusion_value(
            input, forcing, law, spacing, dt, row, column)
        @inbounds output[row, column] = _apply_field_constraints(
            constraints, value, CartesianIndex(row, column), ownership)
    end
    return output
end

function _field_substep!(output, input, forcing, law, spacing, dt,
        boundary, constraints::Tuple, ownership)
    inverse_spacing2 = inv(spacing * spacing)
    for index in CartesianIndices(input)
        center = @inbounds input[index]
        laplacian = zero(center)
        for axis in 1:ndims(input)
            laplacian += _field_neighbor(input, index, axis, -1, boundary) +
                _field_neighbor(input, index, axis, 1, boundary) - 2center
        end
        derivative = law.diffusion * laplacian * inverse_spacing2 -
            law.decay * center +
            _field_reaction_value(law.reaction, center) + forcing[index]
        candidate = muladd(dt, derivative, center)
        @inbounds output[index] = _apply_field_constraints(
            constraints, candidate, index, ownership)
    end
    return output
end

function _first_invalid_field_value(values)
    for index in eachindex(values)
        isfinite(@inbounds values[index]) || return Int(index)
    end
    return 0
end

function _validate_transient_field_profile(state, law, count, dt)
    count > 0 || throw(ArgumentError(
        "field advance requires at least one substep"))
    isfinite(dt) && dt > zero(dt) || throw(ArgumentError(
        "field substep must be finite and positive"))
    law.diffusion >= zero(law.diffusion) || throw(ArgumentError(
        "field diffusion must be non-negative"))
    law.decay >= zero(law.decay) || throw(ArgumentError(
        "field decay must be non-negative"))
    state.spacing > zero(state.spacing) && isfinite(state.spacing) ||
        throw(ArgumentError("field spacing must be finite and positive"))
    if law.diffusion > zero(law.diffusion)
        courant = law.diffusion * dt / (state.spacing * state.spacing)
        limit = inv(convert(typeof(courant), 2 * ndims(state.values)))
        courant <= limit || throw(ArgumentError(
            "explicit field step exceeds the declared diffusion stability limit"))
    end
    return nothing
end

function _advance_transient_field!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, method::FixedStep, ownership)
    law = dynamics.law
    law isa ReactionDiffusion || throw(ArgumentError(
        "the stable field reference currently requires ReactionDiffusion"))
    count, dt = _materialize_substeps(method, interval)
    state.workspace.status[1] = UInt32(0)
    state.workspace.failing_index[1] = UInt32(0)
    try
        _validate_transient_field_profile(state, law, count, dt)
    catch
        state.workspace.status[1] = UInt32(2)
        rethrow()
    end
    input = state.values
    output = state.workspace.first
    for step in 1:count
        _field_substep!(output, input, state.forcing, law,
            state.spacing, dt, state.boundary,
            dynamics.post_substep, ownership)
        invalid = _first_invalid_field_value(output)
        if !iszero(invalid)
            state.workspace.status[1] = UInt32(1)
            state.workspace.failing_index[1] = UInt32(invalid)
            throw(ArgumentError(
                "field advance produced nonfinite values at canonical index $invalid"))
        end
        input = output
        output = isodd(step) ? state.workspace.second : state.workspace.first
    end
    copyto!(state.values, input)
    state.time += interval
    state.publication_epoch[1] += UInt64(1)
    state.diagnostics = FieldAdvanceDiagnostics(
        count, dt, state.time, zero(dt), zero(dt), 0, true, :transient)
    return state
end

function advance_field!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, ownership = nothing)
    return _advance_field_method!(
        state, dynamics, interval, dynamics.method, ownership)
end

_advance_field_method!(state, dynamics, interval, method::FixedStep, ownership) =
    _advance_transient_field!(state, dynamics, interval, method, ownership)

function _publish_state!(destination::EvolvingFieldState,
        source::EvolvingFieldState)
    copyto!(destination.values, source.values)
    copyto!(destination.forcing, source.forcing)
    destination.time = source.time
    destination.diagnostics = source.diagnostics
    copyto!(destination.publication_epoch, source.publication_epoch)
    return destination
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, dynamics::FieldDynamics, target_mcs, stage, interval)
    source = _state_by_name(snapshot.fields, dynamics.field)
    target = _state_by_name(candidate.fields, dynamics.field)
    _publish_state!(target, source)
    amount = _field_interval_amount(dynamics, interval)
    advance_field!(target, dynamics, amount, potts_snapshot)
    return nothing
end

function _field_interval_amount(dynamics::FieldDynamics, interval)
    return dynamics.clock isa ContinuousClock ?
        interval_value(dynamics.clock, interval) :
        interval isa OneMCS ? dynamics.clock.scale :
        interval isa HalfMCS ? dynamics.clock.scale / 2 :
        interval isa ContinuousInterval ? interval.value :
        dynamics.clock.scale * interval
end
