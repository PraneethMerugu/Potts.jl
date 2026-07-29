struct ByCellVolume end
struct ConstantConcentration{S, T}
    scope::S
    value::T
end

@inline _field_constraint_matches(::Nothing, owner, ownership) = false
@inline _field_constraint_matches(scope::Symbol, owner, ownership) =
    scope === :all ||
    (scope === :cells && is_cell_owner(owner)) ||
    (scope === :medium && is_medium_owner(owner))
@inline _field_constraint_matches(scope::CellTypeID, owner, ownership) =
    is_cell_owner(owner) &&
    cell_type(ownership, CellID(owner.value)) == scope
@inline function _field_constraint_matches(scope, owner, ownership)
    applicable(scope, owner, ownership) ||
        throw(ArgumentError(
            "unsupported field constraint scope $(typeof(scope))"))
    return Bool(scope(owner, ownership))
end

@inline _field_owner(ownership::Nothing, index) = nothing
@inline _field_owner(ownership::LogicalPottsState, index) =
    @inbounds lattice_storage(ownership)[index]

@inline _apply_field_constraints(::Tuple{}, value, index, ownership) = value
@inline function _apply_field_constraints(
        constraints::Tuple, value, index, ownership)
    constraint = first(constraints)
    constraint isa ConstantConcentration || throw(ArgumentError(
        "unsupported field post-substep constraint $(typeof(constraint))"))
    owner = _field_owner(ownership, index)
    constrained = _field_constraint_matches(
        constraint.scope, owner, ownership) ?
        convert(typeof(value), constraint.value) : value
    return _apply_field_constraints(
        Base.tail(constraints), constrained, index, ownership)
end
struct Uptake{S, T, N}
    scope::S
    maximum::T
    relative_rate::T
    normalize::N
    output::Union{Nothing, Symbol}
end
function Uptake(scope; maximum::T, relative_rate::T,
        normalize = ByCellVolume(), output = nothing) where {T}
    maximum >= zero(T) && relative_rate >= zero(T) || throw(ArgumentError(
        "uptake parameters must be non-negative"))
    return Uptake(scope, maximum, relative_rate, normalize, output)
end

struct MaximumCalibration{T}
    numerator::T
    state::Symbol
    function MaximumCalibration(numerator::T, state::Symbol) where {T <: AbstractFloat}
        isfinite(numerator) && numerator > zero(T) || throw(ArgumentError(
            "maximum calibration numerator must be finite and positive"))
        return new{T}(numerator, state)
    end
end

@enum FieldExchangeMode::UInt8 begin
    InactiveExchange = 0
    ResetExchange = 1
    CalibrateExchange = 2
    PublishExchange = 3
end

struct PlanModeSchedule{E <: Tuple}
    entries::E
end
function PlanModeSchedule(entries::Pair...)
    isempty(entries) && throw(ArgumentError(
        "plan mode schedule requires at least one range"))
    all(entry -> first(entry) isa MCSRange &&
                 last(entry) isa FieldExchangeMode, entries) ||
        throw(ArgumentError(
            "plan mode entries must map MCSRange to FieldExchangeMode"))
    ordered = Tuple(entries)
    for index in 2:length(ordered)
        previous = first(ordered[index - 1])
        current = first(ordered[index])
        previous.last < current.first || throw(ArgumentError(
            "plan mode ranges must be ordered and nonoverlapping"))
        previous.last + UInt64(1) == current.first || throw(ArgumentError(
            "plan mode schedule may not contain implicit gaps"))
    end
    return PlanModeSchedule(ordered)
end
function mode_at(schedule::PlanModeSchedule, target_mcs::Integer)
    for entry in schedule.entries
        target_mcs in first(entry) && return last(entry)
    end
    throw(ArgumentError(
        "target MCS $target_mcs is outside the plan mode schedule"))
end

@enum FieldExchangeFailureCode::UInt32 begin
    ExchangeSucceeded = 0
    ExchangeShapeMismatch = 1
    ExchangeInvalidVolume = 2
    ExchangeInvalidConcentration = 3
    ExchangeInvalidRemoval = 4
    ExchangeInvalidCalibration = 5
    ExchangeUninitializedCalibration = 6
    ExchangeInvalidGeneration = 7
end

struct FieldExchangeFailure <: Exception
    code::FieldExchangeFailureCode
    index::UInt32
end
function Base.showerror(io::IO, error::FieldExchangeFailure)
    print(io, "field exchange failed with ", Symbol(error.code))
    iszero(error.index) || print(io, " at canonical index ", error.index)
end

struct FieldExchangeWorkspace{R <: AbstractVector, S <: AbstractVector,
        C <: AbstractVector, I <: AbstractVector}
    raw_totals::R
    candidate_signal::S
    status::C
    failing_index::I
end

mutable struct FieldExchangeState{V <: AbstractVector, I <: AbstractVector,
        E <: AbstractVector, W}
    name::Symbol
    value::V
    initialized::I
    publication_epoch::E
    workspace::W
end

function FieldExchangeState(name::Symbol, field::EvolvingFieldState,
        ownership::LogicalPottsState; accumulator_type::Type{A} = Float64) where {
        A <: AbstractFloat}
    slots = nslots(capacity(ownership))
    value = similar(field.values, eltype(field.values), 1)
    initialized = similar(field.values, UInt8, 1)
    publication_epoch = similar(field.values, UInt64, 1)
    raw_totals = similar(field.values, A, slots)
    candidate_signal = similar(field.values, eltype(field.values), slots)
    status = similar(field.values, UInt32, 1)
    failing_index = similar(field.values, UInt32, 1)
    fill!(value, zero(eltype(value)))
    fill!(initialized, UInt8(0))
    fill!(publication_epoch, UInt64(0))
    fill!(raw_totals, zero(A))
    fill!(candidate_signal, zero(eltype(candidate_signal)))
    fill!(status, UInt32(ExchangeSucceeded))
    fill!(failing_index, UInt32(0))
    workspace = FieldExchangeWorkspace(
        raw_totals, candidate_signal, status, failing_index)
    return FieldExchangeState(
        name, value, initialized, publication_epoch, workspace)
end

function Adapt.adapt_structure(to, workspace::FieldExchangeWorkspace)
    return FieldExchangeWorkspace(
        Adapt.adapt(to, workspace.raw_totals),
        Adapt.adapt(to, workspace.candidate_signal),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index))
end

function Adapt.adapt_structure(to, state::FieldExchangeState)
    return FieldExchangeState(
        state.name,
        Adapt.adapt(to, state.value),
        Adapt.adapt(to, state.initialized),
        Adapt.adapt(to, state.publication_epoch),
        Adapt.adapt(to, state.workspace))
end

function _publish_state!(
        destination::FieldExchangeState, source::FieldExchangeState)
    copyto!(destination.value, source.value)
    copyto!(destination.initialized, source.initialized)
    copyto!(destination.publication_epoch, source.publication_epoch)
    return destination
end

struct FieldExchange{S <: Tuple, K <: Tuple, C}
    name::Symbol
    field::Symbol
    sources::S
    sinks::K
    calibration::C
    version::VersionNumber
end
function FieldExchange(name::Symbol; field::Symbol,
        sources::Tuple = (), sinks::Tuple = (), calibration = nothing,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    calibration isa Union{Nothing, MaximumCalibration} || throw(ArgumentError(
        "unsupported field-exchange calibration declaration"))
    return FieldExchange(
        name, field, sources, sinks, calibration, version)
end
component_identity(exchange::FieldExchange) =
    ComponentIdentity(exchange.name, exchange.version, :field_exchange)
component_semantic_data(exchange::FieldExchange) = (
    field = exchange.field, sources = exchange.sources, sinks = exchange.sinks,
    calibration = exchange.calibration)
function process_reads(exchange::FieldExchange)
    calibration = exchange.calibration === nothing ? () :
        ((:global, exchange.calibration.state),)
    return ((:ownership, :lattice), (:field, exchange.field), calibration...)
end
function process_writes(exchange::FieldExchange)
    outputs = Tuple((:cell_property, sink.output)
        for sink in exchange.sinks if sink isa Uptake && sink.output !== nothing)
    calibration = exchange.calibration === nothing ? () :
        ((:global, exchange.calibration.state),)
    field_write = isempty(exchange.sinks) ? () : ((:field, exchange.field),)
    forcing_write = isempty(exchange.sources) ? () :
        ((:field_forcing, exchange.field),)
    return (field_write..., forcing_write..., outputs..., calibration...)
end

_scope_matches(::Nothing, owner, state) = true
_scope_matches(scope::Symbol, owner, state) =
    scope === :all || (scope === :cells && is_cell_owner(owner)) ||
    (scope === :medium && is_medium_owner(owner))
_scope_matches(scope::CellTypeID, owner, state) =
    is_cell_owner(owner) &&
    cell_type(state, CellID(owner.value)) == scope
function _scope_matches(scope, owner, state)
    applicable(scope, owner, state) || throw(ArgumentError(
        "unsupported field-exchange scope $(typeof(scope))"))
    return Bool(scope(owner, state))
end

_cell_scope_matches_exchange(::Nothing, state, cell) = true
_cell_scope_matches_exchange(scope::Symbol, state, cell) =
    scope === :all || scope === :cells
_cell_scope_matches_exchange(scope::CellTypeID, state, cell) =
    cell_type(state, cell) == scope
_cell_scope_matches_exchange(scope::Tuple, state, cell) =
    cell_type(state, cell) in scope
function _cell_scope_matches_exchange(scope, state, cell)
    applicable(scope, state, cell) || throw(ArgumentError(
        "unsupported cell-exchange scope $(typeof(scope))"))
    return Bool(scope(state, cell))
end

function _exchange_fail!(runtime::FieldExchangeState,
        code::FieldExchangeFailureCode, index::Integer)
    runtime.workspace.status[1] = UInt32(code)
    runtime.workspace.failing_index[1] = UInt32(index)
    throw(FieldExchangeFailure(code, UInt32(index)))
end

function _validate_direct_exchange(
        field, exchange, ownership, signal, runtime)
    size(field.values) == lattice_size(ownership) ||
        _exchange_fail!(runtime, ExchangeShapeMismatch, 0)
    slots = nslots(capacity(ownership))
    length(signal) == slots &&
        length(runtime.workspace.raw_totals) == slots &&
        length(runtime.workspace.candidate_signal) == slots ||
        _exchange_fail!(runtime, ExchangeShapeMismatch, 0)
    length(exchange.sources) == 0 || throw(ArgumentError(
        "direct uptake transaction does not admit forcing sources"))
    length(exchange.sinks) == 1 || throw(ArgumentError(
        "direct uptake transaction requires exactly one sink"))
    sink = only(exchange.sinks)
    sink isa Uptake || throw(ArgumentError(
        "direct uptake transaction requires Uptake"))
    sink.normalize isa ByCellVolume || throw(ArgumentError(
        "direct uptake transaction requires ByCellVolume normalization"))
    sink.output === nothing && throw(ArgumentError(
        "direct uptake transaction requires a named cell output"))
    return sink
end

function _prepare_exchange_workspace!(runtime, signal)
    fill!(runtime.workspace.status, UInt32(ExchangeSucceeded))
    fill!(runtime.workspace.failing_index, UInt32(0))
    fill!(runtime.workspace.raw_totals,
        zero(eltype(runtime.workspace.raw_totals)))
    copyto!(runtime.workspace.candidate_signal, signal)
    return runtime
end

function _publish_exchange_epoch!(runtime::FieldExchangeState)
    runtime.publication_epoch[1] += UInt64(1)
    return runtime
end

"""
Apply an immediate field/cell/global exchange as one failure-atomic CPU transaction.

The root plan supplies `mode`; the process contains no MCS-dependent scheduling branch.
The field's two existing staging grids serve as candidate concentration and per-site removal
workspace and are never checkpointed.
"""
function apply_field_exchange!(field::EvolvingFieldState,
        exchange::FieldExchange, ownership::LogicalPottsState,
        signal::AbstractVector, runtime::FieldExchangeState,
        mode::FieldExchangeMode, target_mcs::Integer)
    sink = _validate_direct_exchange(
        field, exchange, ownership, signal, runtime)
    _prepare_exchange_workspace!(runtime, signal)
    mode === InactiveExchange && return false

    slots = nslots(capacity(ownership))
    if mode === ResetExchange
        for slot in 1:slots
            cell = CellID(slot)
            is_active(ownership, cell) || continue
            _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
            runtime.workspace.candidate_signal[slot] =
                zero(eltype(runtime.workspace.candidate_signal))
        end
        copyto!(signal, runtime.workspace.candidate_signal)
        _publish_exchange_epoch!(runtime)
        return true
    end

    mode in (CalibrateExchange, PublishExchange) || throw(ArgumentError(
        "unsupported direct field-exchange mode"))
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "calibrate/publish exchange requires MaximumCalibration"))
    candidate_field = field.workspace.first
    removals = field.workspace.second
    copyto!(candidate_field, field.values)
    fill!(removals, zero(eltype(removals)))
    owners = lattice_storage(ownership)
    maximum_raw = zero(eltype(runtime.workspace.raw_totals))
    eligible_count = 0

    for slot in 1:slots
        cell = CellID(slot)
        is_active(ownership, cell) || continue
        _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
        eligible_count += 1
        volume = finite_volume(ownership, cell)
        volume > 0 || _exchange_fail!(
            runtime, ExchangeInvalidVolume, slot)
        total = zero(eltype(runtime.workspace.raw_totals))
        for site in eachindex(owners)
            owner = @inbounds owners[site]
            is_cell_owner(owner) && Int(owner.value) == slot || continue
            concentration = @inbounds field.values[site]
            isfinite(concentration) && concentration >= zero(concentration) ||
                _exchange_fail!(
                    runtime, ExchangeInvalidConcentration, site)
            removal = min(convert(typeof(concentration), sink.maximum),
                convert(typeof(concentration), sink.relative_rate) * concentration)
            isfinite(removal) &&
                zero(removal) <= removal <= concentration ||
                _exchange_fail!(runtime, ExchangeInvalidRemoval, site)
            @inbounds begin
                removals[site] = removal
                candidate_field[site] = concentration - removal
            end
            total += removal
        end
        raw = total / volume
        isfinite(raw) && raw >= zero(raw) ||
            _exchange_fail!(runtime, ExchangeInvalidRemoval, slot)
        runtime.workspace.raw_totals[slot] = raw
        maximum_raw = max(maximum_raw, raw)
    end

    eligible_count > 0 || _exchange_fail!(
        runtime, ExchangeInvalidCalibration, 0)
    calibration_value = runtime.value[1]
    if mode === CalibrateExchange
        maximum_raw > zero(maximum_raw) && isfinite(maximum_raw) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
        calibration_value = convert(eltype(runtime.value),
            exchange.calibration.numerator / maximum_raw)
        isfinite(calibration_value) && calibration_value > zero(calibration_value) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
    else
        runtime.initialized[1] == UInt8(1) ||
            _exchange_fail!(runtime, ExchangeUninitializedCalibration, 0)
        isfinite(calibration_value) && calibration_value > zero(calibration_value) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
        for slot in 1:slots
            cell = CellID(slot)
            is_active(ownership, cell) || continue
            _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
            output = runtime.workspace.raw_totals[slot] * calibration_value
            isfinite(output) && output >= zero(output) ||
                _exchange_fail!(runtime, ExchangeInvalidRemoval, slot)
            runtime.workspace.candidate_signal[slot] =
                convert(eltype(signal), output)
        end
    end

    copyto!(field.values, candidate_field)
    mode === PublishExchange &&
        copyto!(signal, runtime.workspace.candidate_signal)
    if mode === CalibrateExchange
        runtime.value[1] = calibration_value
        runtime.initialized[1] = UInt8(1)
    end
    _publish_exchange_epoch!(runtime)
    return true
end

function execute_field_exchange!(candidate::CoupledState,
        snapshot::CoupledState, potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState, exchange::FieldExchange,
        schedule::PlanModeSchedule, target_mcs::Integer)
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "plan-resolved direct exchange requires MaximumCalibration"))
    sink = only(exchange.sinks)
    sink isa Uptake && sink.output !== nothing || throw(ArgumentError(
        "plan-resolved direct exchange requires one named Uptake output"))
    source_field = _state_by_name(snapshot.fields, exchange.field)
    target_field = _state_by_name(candidate.fields, exchange.field)
    source_runtime = _state_by_name(
        snapshot.globals, exchange.calibration.state)
    target_runtime = _state_by_name(
        candidate.globals, exchange.calibration.state)
    source_runtime isa FieldExchangeState &&
        target_runtime isa FieldExchangeState || throw(ArgumentError(
            "plan-resolved exchange calibration state is not realized"))
    _publish_state!(target_field, source_field)
    _publish_state!(target_runtime, source_runtime)
    source_signal = property_values(potts_snapshot, sink.output)
    target_signal = property_values(potts_candidate, sink.output)
    copyto!(target_signal, source_signal)
    apply_field_exchange!(
        target_field, exchange, potts_snapshot, target_signal,
        target_runtime, mode_at(schedule, target_mcs), target_mcs)
    return sink.output
end
