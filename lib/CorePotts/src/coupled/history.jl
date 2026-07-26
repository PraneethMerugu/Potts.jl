const CENTROID_HISTORY_UNTRACKED = UInt32(1)
const CENTROID_HISTORY_INVALID_VOLUME = UInt32(2)
const CENTROID_HISTORY_STALE_GENERATION = UInt32(3)
const CENTROID_HISTORY_NONFINITE = UInt32(4)

struct CentroidHistorySampleWorkspace{
        S <: AbstractVector,
        A <: AbstractVector{Bool},
        G <: AbstractVector{CellGeneration},
        C <: AbstractVector{UInt32}}
    samples::S
    active::A
    generations::G
    failure_key::C
end

function CentroidHistorySampleWorkspace(
        state::CellHistoryState)
    capacity = length(state.generations)
    capacity <= Int(_COUPLED_PROCESS_MAX_CELL) ||
        throw(ArgumentError(
            "centroid-history capacity exceeds packed failure-key capacity"))
    samples = similar(
        state.generations, eltype(state.values), capacity)
    active = similar(state.generations, Bool, capacity)
    generations = similar(state.generations)
    failure_key = similar(state.heads, UInt32, 1)
    fill!(samples, zero(eltype(samples)))
    fill!(active, false)
    copyto!(generations, state.generations)
    failure_key[1] = _COUPLED_PROCESS_FAILURE_SENTINEL
    return CentroidHistorySampleWorkspace(
        samples, active, generations, failure_key)
end

function Adapt.adapt_structure(
        to, workspace::CentroidHistorySampleWorkspace)
    return CentroidHistorySampleWorkspace(
        Adapt.adapt(to, workspace.samples),
        Adapt.adapt(to, workspace.active),
        Adapt.adapt(to, workspace.generations),
        Adapt.adapt(to, workspace.failure_key))
end

centroid_history_workspace_bytes(
        workspace::CentroidHistorySampleWorkspace) =
    sum(_array_bytes, (
        workspace.samples, workspace.active,
        workspace.generations, workspace.failure_key); init = 0)

"""
Backend-independent declaration of one centroid-to-history sampling process.

The bounded workspace is realized only after the authoritative history and
compiled scientific state exist.
"""
struct CentroidHistorySample
    name::Symbol
    history::Symbol
    version::VersionNumber
    function CentroidHistorySample(
            name::Symbol, history::Symbol;
            version::VersionNumber =
                DYNAMIC_STATE_CONTRACT_VERSION)
        isempty(String(name)) && throw(ArgumentError(
            "centroid-history sample identity must not be empty"))
        isempty(String(history)) && throw(ArgumentError(
            "centroid-history target must not be empty"))
        return new(name, history, version)
    end
end

component_identity(process::CentroidHistorySample) =
    ComponentIdentity(
        process.name, process.version,
        :centroid_history_sample)
component_semantic_data(
        process::CentroidHistorySample) = (
    history = process.history,
    source = :compiled_unwrapped_centroid,
    ordering = :ascending_persistent_cell_slot,
)
process_reads(::CentroidHistorySample) = (
    (:ownership, :lattice),
    (:tracker, :unwrapped_coordinate_moments),
)
process_writes(process::CentroidHistorySample) =
    ((:history, process.history),)

struct CentroidHistorySampleExecution{
        W <: CentroidHistorySampleWorkspace}
    name::Symbol
    history::Symbol
    workspace::W
    version::VersionNumber
end

function CentroidHistorySampleExecution(
        name::Symbol, history::CellHistoryState,
        scientific::CompiledScientificState;
        version::VersionNumber =
            DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "centroid-history sample identity must not be empty"))
    moments = scientific_execution(
        scientific).trackers.moments
    moments isa UnwrappedMomentStorage || throw(ArgumentError(
        "centroid-history sampling requires unwrapped moments"))
    sample_type = eltype(history.values)
    sample_type <: StaticVector || throw(ArgumentError(
        "centroid-history samples must be fixed-size vectors"))
    length(sample_type) == length(moments.coordinate_sums) ||
        throw(DimensionMismatch(
            "centroid-history sample dimension differs from tracked moments"))
    length(history.generations) ==
        length(scientific_execution(scientific).core.active) ||
        throw(DimensionMismatch(
            "centroid-history and scientific cell capacities differ"))
    workspace = CentroidHistorySampleWorkspace(history)
    return CentroidHistorySampleExecution(
        name, history.declaration.name,
        workspace, version)
end

CentroidHistorySample(
    name::Symbol, history::CellHistoryState,
    scientific::CompiledScientificState; kwargs...) =
    CentroidHistorySampleExecution(
        name, history, scientific; kwargs...)

function realize_coupled_process(
        process::CentroidHistorySample,
        state::CoupledState,
        scientific::CompiledScientificState)
    history = _state_by_name(
        state.histories, process.history)
    return CentroidHistorySampleExecution(
        process.name, history, scientific;
        version = process.version)
end

function Adapt.adapt_structure(
        to, process::CentroidHistorySampleExecution)
    workspace = Adapt.adapt(to, process.workspace)
    return CentroidHistorySampleExecution(
        process.name, process.history,
        workspace, process.version)
end

component_identity(process::CentroidHistorySampleExecution) =
    ComponentIdentity(
        process.name, process.version,
        :centroid_history_sample)
component_semantic_data(
        process::CentroidHistorySampleExecution) = (
    history = process.history,
    source = :compiled_unwrapped_centroid,
    ordering = :ascending_persistent_cell_slot,
)
process_reads(process::CentroidHistorySampleExecution) = (
    (:ownership, :lattice),
    (:tracker, :unwrapped_coordinate_moments),
)
process_writes(process::CentroidHistorySampleExecution) =
    ((:history, process.history),)
canonical_process_law(
        process::CentroidHistorySampleExecution) =
    CentroidHistorySample(
        process.name, process.history;
        version = process.version)

@inline function _history_sample_value(
        coordinate_sums::Tuple, volume,
        slot, ::Type{S}) where {N, T, S <: SVector{N, T}}
    inverse_volume = inv(T(volume))
    return S(ntuple(axis ->
        @inbounds(coordinate_sums[axis][slot]) *
            inverse_volume, Val(N)))
end

function apply_centroid_history_sample!(
        history::CellHistoryState,
        scientific::CompiledScientificState,
        process::CentroidHistorySampleExecution,
        target_mcs::Integer)
    history.declaration.name === process.history ||
        throw(ArgumentError(
            "centroid-history sampler targets a different history"))
    execution = scientific_execution(scientific)
    core = execution.core
    moments = execution.trackers.moments
    moments isa UnwrappedMomentStorage || throw(ArgumentError(
        "centroid-history sampling requires unwrapped moments"))
    workspace = process.workspace
    capacity = length(core.active)
    all(==(capacity), (
        length(history.generations),
        length(workspace.samples),
        length(workspace.active),
        length(workspace.generations))) ||
        throw(DimensionMismatch(
            "centroid-history sampling capacities differ"))
    workspace.failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
    for slot in 1:capacity
        is_active = @inbounds core.active[slot] != UInt8(0)
        @inbounds workspace.active[slot] = is_active
        generation_value =
            CellGeneration(@inbounds core.generations[slot])
        @inbounds workspace.generations[slot] =
            generation_value
        is_active || continue
        code = if @inbounds(moments.tracked[slot]) == UInt8(0)
            CENTROID_HISTORY_UNTRACKED
        elseif @inbounds(execution.trackers.finite_volumes[slot]) <= 0
            CENTROID_HISTORY_INVALID_VOLUME
        elseif @inbounds(history.generations[slot]) !=
                generation_value
            CENTROID_HISTORY_STALE_GENERATION
        else
            UInt32(0)
        end
        if !iszero(code)
            workspace.failure_key[1] = min(
                workspace.failure_key[1],
                _coupled_process_failure_key(code, slot))
            continue
        end
        sample = _history_sample_value(
            moments.coordinate_sums,
            @inbounds(execution.trackers.finite_volumes[slot]),
            slot, eltype(workspace.samples))
        if !all(isfinite, sample)
            workspace.failure_key[1] = min(
                workspace.failure_key[1],
                _coupled_process_failure_key(
                    CENTROID_HISTORY_NONFINITE, slot))
            continue
        end
        @inbounds workspace.samples[slot] = sample
    end
    key = workspace.failure_key[1]
    key == _COUPLED_PROCESS_FAILURE_SENTINEL ||
        throw(ArgumentError(
            "centroid-history sampling failed with status $(_coupled_process_failure_code(key)) at cell $(_coupled_process_failing_cell(key))"))
    sample_history!(
        history, workspace.samples, workspace.active,
        workspace.generations, target_mcs)
    return history
end

@kernel function _stage_centroid_history_sample!(
        samples, sample_active, sample_generations,
        active, generations, history_generations,
        finite_volumes, tracked, coordinate_sums,
        failure_key)
    slot = @index(Global, Linear)
    @inbounds begin
        is_active = active[slot] != UInt8(0)
        sample_active[slot] = is_active
        generation_value = CellGeneration(generations[slot])
        sample_generations[slot] = generation_value
        if is_active
            code = tracked[slot] == UInt8(0) ?
                CENTROID_HISTORY_UNTRACKED :
                finite_volumes[slot] <= 0 ?
                CENTROID_HISTORY_INVALID_VOLUME :
                history_generations[slot] != generation_value ?
                CENTROID_HISTORY_STALE_GENERATION : UInt32(0)
            if !iszero(code)
                Atomix.@atomic min(
                    failure_key[1],
                    _coupled_process_failure_key(code, slot))
            else
                sample = _history_sample_value(
                    coordinate_sums, finite_volumes[slot],
                    slot, eltype(samples))
                if all(isfinite, sample)
                    samples[slot] = sample
                else
                    Atomix.@atomic min(
                        failure_key[1],
                        _coupled_process_failure_key(
                            CENTROID_HISTORY_NONFINITE, slot))
                end
            end
        end
    end
end

@kernel function _commit_centroid_history_sample!(
        values, heads, fills, generations,
        samples, sample_active, sample_generations,
        ::Val{Width}) where {Width}
    slot = @index(Global, Linear)
    @inbounds if sample_active[slot]
        head = mod(Int(heads[slot]), Width) + 1
        values[slot, head] = samples[slot]
        heads[slot] = UInt32(head)
        fills[slot] = min(
            UInt32(Width), fills[slot] + UInt32(1))
        generations[slot] = sample_generations[slot]
    end
end

@kernel function _reset_centroid_history_failure!(failure_key)
    @inbounds failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
end

function apply_centroid_history_sample!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        history::CellHistoryState,
        process::CentroidHistorySampleExecution,
        target_mcs::Integer)
    0 <= target_mcs <= typemax(UInt64) || throw(ArgumentError(
        "history sample MCS must be non-negative and fit UInt64"))
    history.declaration.name === process.history ||
        throw(ArgumentError(
            "centroid-history sampler targets a different history"))
    execution = scientific_execution(scientific)
    moments = execution.trackers.moments
    moments isa UnwrappedMomentStorage || throw(ArgumentError(
        "centroid-history sampling requires unwrapped moments"))
    workspace = process.workspace
    capacity = length(execution.core.active)
    arrays = (
        execution.core.active, execution.core.generations,
        execution.trackers.finite_volumes,
        moments.tracked, moments.coordinate_sums...,
        history.values, history.heads, history.fills,
        history.generations, workspace.samples,
        workspace.active, workspace.generations,
        workspace.failure_key)
    all(array -> array isa AbstractArray &&
            isbitstype(eltype(array)) &&
            isequal(
                KernelAbstractions.get_backend(array),
                plan.backend),
        arrays) || throw(ArgumentError(
        "centroid-history storage has a backend mismatch"))
    all(==(capacity), (
        length(history.generations),
        length(workspace.samples),
        length(workspace.active),
        length(workspace.generations))) ||
        throw(DimensionMismatch(
            "centroid-history sampling capacities differ"))
    reset = _execution_kernel(
        plan, _reset_centroid_history_failure!, 1)
    launch!(plan, reset, workspace.failure_key;
        ndrange = 1)
    stage = _execution_kernel(
        plan, _stage_centroid_history_sample!, capacity)
    launch!(plan, stage,
        workspace.samples, workspace.active,
        workspace.generations,
        execution.core.active, execution.core.generations,
        history.generations,
        execution.trackers.finite_volumes,
        moments.tracked, moments.coordinate_sums,
        workspace.failure_key; ndrange = capacity)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    key = only(Adapt.adapt(
        Array, workspace.failure_key))
    key == _COUPLED_PROCESS_FAILURE_SENTINEL ||
        throw(ArgumentError(
            "centroid-history sampling failed with status $(_coupled_process_failure_code(key)) at cell $(_coupled_process_failing_cell(key))"))
    commit = _execution_kernel(
        plan, _commit_centroid_history_sample!, capacity)
    launch!(plan, commit,
        history.values, history.heads, history.fills,
        history.generations, workspace.samples,
        workspace.active, workspace.generations,
        Val(Int(history.declaration.length));
        ndrange = capacity)
    history.latest_sample_mcs = UInt64(target_mcs)
    return history
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::CentroidHistorySampleExecution,
        target_mcs, stage, interval)
    target = _state_by_name(
        candidate.histories, process.history)
    apply_centroid_history_sample!(
        target, scientific, process, target_mcs)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::CentroidHistorySampleExecution,
        target_mcs, stage, interval)
    history = _state_by_name(
        integrator.state.histories, process.history)
    apply_centroid_history_sample!(
        integrator.potts.plan, integrator.potts.state,
        history, process, target_mcs)
    return ()
end

const HISTORY_POLARITY_UNAVAILABLE = UInt32(1)
const HISTORY_POLARITY_NONFINITE_INPUT = UInt32(2)
const HISTORY_POLARITY_NONFINITE_OUTPUT = UInt32(3)

struct HistoryDisplacementWorkspace{
        C <: Tuple,
        V <: AbstractVector,
        K <: AbstractVector{UInt32}}
    candidate_coordinates::C
    candidate_magnitude::V
    failure_key::K
end

function HistoryDisplacementWorkspace(
        columns::Tuple,
        magnitude::AbstractVector)
    isempty(columns) && throw(ArgumentError(
        "history-displacement direction requires coordinate outputs"))
    capacity = length(magnitude)
    all(column -> length(column) == capacity, columns) ||
        throw(DimensionMismatch(
            "history-displacement output capacities differ"))
    capacity <= Int(_COUPLED_PROCESS_MAX_CELL) ||
        throw(ArgumentError(
            "history-displacement capacity exceeds packed failure-key capacity"))
    candidates = map(column ->
        similar(column, eltype(column), capacity), columns)
    candidate_magnitude = similar(
        magnitude, eltype(magnitude), capacity)
    failure_key = similar(magnitude, UInt32, 1)
    for array in (candidates..., candidate_magnitude)
        fill!(array, zero(eltype(array)))
    end
    failure_key[1] = _COUPLED_PROCESS_FAILURE_SENTINEL
    return HistoryDisplacementWorkspace(
        candidates, candidate_magnitude, failure_key)
end

function Adapt.adapt_structure(
        to, workspace::HistoryDisplacementWorkspace)
    return HistoryDisplacementWorkspace(
        map(column -> Adapt.adapt(to, column),
            workspace.candidate_coordinates),
        Adapt.adapt(to, workspace.candidate_magnitude),
        Adapt.adapt(to, workspace.failure_key))
end

history_displacement_workspace_bytes(
        workspace::HistoryDisplacementWorkspace) =
    sum(_array_bytes, (
        workspace.candidate_coordinates...,
        workspace.candidate_magnitude,
        workspace.failure_key); init = 0)

"""
Backend-independent declaration of a direction and magnitude derived from a
bounded cell-history displacement.
"""
struct HistoryDisplacementDirection{
        OUTPUTS, MAGNITUDE}
    name::Symbol
    history::Symbol
    lag::UInt32
    version::VersionNumber
end

function HistoryDisplacementDirection(
        name::Symbol, history::Symbol;
        outputs::Tuple, magnitude::Symbol,
        lag::Lag,
        version::VersionNumber =
            DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "history-displacement identity must not be empty"))
    isempty(String(history)) && throw(ArgumentError(
        "history-displacement source must not be empty"))
    isempty(outputs) && throw(ArgumentError(
        "history-displacement outputs must not be empty"))
    all(output -> output isa Symbol, outputs) ||
        throw(ArgumentError(
            "history-displacement outputs must be property symbols"))
    length(unique((outputs..., magnitude))) ==
        length(outputs) + 1 || throw(ArgumentError(
        "history-displacement output properties must be unique"))
    return HistoryDisplacementDirection{
        outputs, magnitude}(
        name, history, lag.value, version)
end

component_identity(
        process::HistoryDisplacementDirection) =
    ComponentIdentity(
        process.name, process.version,
        :history_displacement_direction)
component_semantic_data(
        process::HistoryDisplacementDirection{
            OUTPUTS, MAGNITUDE}) where {
            OUTPUTS, MAGNITUDE} = (
    history = process.history,
    lag = process.lag,
    outputs = OUTPUTS,
    magnitude = MAGNITUDE,
    zero_displacement = :zero_vector,
)
process_reads(
        process::HistoryDisplacementDirection) =
    ((:history, process.history),)
function process_writes(
        ::HistoryDisplacementDirection{
            OUTPUTS, MAGNITUDE}) where {
            OUTPUTS, MAGNITUDE}
    outputs = map(property ->
        (:cell_property, property), OUTPUTS)
    return (outputs..., (:cell_property, MAGNITUDE))
end

struct HistoryDisplacementDirectionExecution{
        OUTPUTS, MAGNITUDE, T <: AbstractFloat,
        W <: HistoryDisplacementWorkspace}
    name::Symbol
    history::Symbol
    lag::UInt32
    workspace::W
    version::VersionNumber
end

function HistoryDisplacementDirectionExecution(
        name::Symbol, history::CellHistoryState,
        state::Union{
            LogicalPottsState, CompiledScientificState};
        outputs::Tuple, magnitude::Symbol,
        lag::Lag,
        version::VersionNumber =
            DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "history-displacement identity must not be empty"))
    isempty(outputs) && throw(ArgumentError(
        "history-displacement outputs must not be empty"))
    all(output -> output isa Symbol, outputs) ||
        throw(ArgumentError(
            "history-displacement outputs must be property symbols"))
    length(unique((outputs..., magnitude))) ==
        length(outputs) + 1 || throw(ArgumentError(
        "history-displacement output properties must be unique"))
    columns = map(
        property -> _coupled_property_column(state, property),
        outputs)
    magnitude_column =
        _coupled_property_column(state, magnitude)
    T = eltype(magnitude_column)
    T <: AbstractFloat || throw(ArgumentError(
        "history-displacement magnitude must be floating point"))
    all(column ->
            column isa AbstractVector{T} &&
            length(column) == length(magnitude_column),
        columns) || throw(ArgumentError(
        "history-displacement output columns must share one floating type and capacity"))
    sample_type = eltype(history.values)
    sample_type <: SVector{length(outputs), T} ||
        throw(ArgumentError(
            "history samples must match the output dimension and floating type"))
    lag.value < history.declaration.length ||
        throw(ArgumentError(
            "history-displacement lag exceeds the bounded history"))
    workspace = HistoryDisplacementWorkspace(
        columns, magnitude_column)
    return HistoryDisplacementDirectionExecution{
        outputs, magnitude, T, typeof(workspace)}(
        name, history.declaration.name,
        lag.value, workspace, version)
end

function Adapt.adapt_structure(
        to, process::HistoryDisplacementDirectionExecution{
            OUTPUTS, MAGNITUDE, T}) where {
            OUTPUTS, MAGNITUDE, T}
    workspace = Adapt.adapt(to, process.workspace)
    return HistoryDisplacementDirectionExecution{
        OUTPUTS, MAGNITUDE, T, typeof(workspace)}(
        process.name, process.history, process.lag,
        workspace, process.version)
end

HistoryDisplacementDirection(
    name::Symbol, history::CellHistoryState,
    state::Union{
        LogicalPottsState, CompiledScientificState};
    kwargs...) =
    HistoryDisplacementDirectionExecution(
        name, history, state; kwargs...)

function realize_coupled_process(
        process::HistoryDisplacementDirection{
            OUTPUTS, MAGNITUDE},
        state::CoupledState,
        scientific::CompiledScientificState) where {
            OUTPUTS, MAGNITUDE}
    history = _state_by_name(
        state.histories, process.history)
    return HistoryDisplacementDirectionExecution(
        process.name, history, scientific;
        outputs = OUTPUTS,
        magnitude = MAGNITUDE,
        lag = Lag(process.lag),
        version = process.version)
end

component_identity(
        process::HistoryDisplacementDirectionExecution) =
    ComponentIdentity(
        process.name, process.version,
        :history_displacement_direction)
component_semantic_data(
        process::HistoryDisplacementDirectionExecution{
            OUTPUTS, MAGNITUDE}) where {
            OUTPUTS, MAGNITUDE} = (
    history = process.history,
    lag = process.lag,
    outputs = OUTPUTS,
    magnitude = MAGNITUDE,
    zero_displacement = :zero_vector,
)
process_reads(
        process::HistoryDisplacementDirectionExecution) =
    ((:history, process.history),)
function process_writes(
        ::HistoryDisplacementDirectionExecution{
            OUTPUTS, MAGNITUDE}) where {
            OUTPUTS, MAGNITUDE}
    outputs = map(property ->
        (:cell_property, property), OUTPUTS)
    return (outputs..., (:cell_property, MAGNITUDE))
end
canonical_process_law(
        process::HistoryDisplacementDirectionExecution{
            OUTPUTS, MAGNITUDE}) where {
            OUTPUTS, MAGNITUDE} =
    HistoryDisplacementDirection(
        process.name, process.history;
        outputs = OUTPUTS,
        magnitude = MAGNITUDE,
        lag = Lag(process.lag),
        version = process.version)

@generated function _history_displacement_columns(
        properties,
        ::HistoryDisplacementDirectionExecution{
            OUTPUTS}) where {OUTPUTS}
    expressions = map(OUTPUTS) do property
        :(getproperty(properties, $(QuoteNode(property))))
    end
    return Expr(:tuple, expressions...)
end

@inline function _write_history_direction!(
        columns::Tuple, slot, value)
    @inbounds first(columns)[slot] = first(value)
    return _write_history_direction!(
        Base.tail(columns), slot, Base.tail(value))
end
@inline _write_history_direction!(
    ::Tuple{}, slot, ::Tuple{}) = nothing
@inline function _write_history_direction!(
        columns::Tuple, slot,
        value::StaticVector)
    _write_history_direction!(
        columns, slot, Tuple(value))
end

@inline function _history_direction_candidate(
        current::StaticVector,
        previous::StaticVector)
    displacement = current - previous
    magnitude = sqrt(sum(abs2, displacement))
    direction = iszero(magnitude) ?
        zero(displacement) :
        displacement / magnitude
    return direction, magnitude
end

function apply_history_displacement_direction!(
        candidate::LogicalPottsState,
        snapshot::LogicalPottsState,
        history::CellHistoryState,
        process::HistoryDisplacementDirectionExecution)
    history.declaration.name === process.history ||
        throw(ArgumentError(
            "history-displacement process targets a different history"))
    output_columns = _history_displacement_columns(
        candidate.properties.columns, process)
    magnitude_column = _coupled_column(
        candidate.properties, _history_magnitude(process))
    workspace = process.workspace
    slot_count = nslots(capacity(snapshot))
    all(==(slot_count), (
        length(history.generations),
        map(length, output_columns)...,
        length(magnitude_column),
        map(length, workspace.candidate_coordinates)...,
        length(workspace.candidate_magnitude))) ||
        throw(DimensionMismatch(
            "history-displacement capacities differ"))
    workspace.failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
    for slot in 1:slot_count
        cell = CellID(slot)
        is_active(snapshot, cell) || continue
        generation_value = generation(snapshot, cell)
        current = maybe_history_value(
            history, cell, generation_value, Lag(0))
        previous = maybe_history_value(
            history, cell, generation_value,
            Lag(process.lag))
        if !(current.available && previous.available)
            workspace.failure_key[1] = min(
                workspace.failure_key[1],
                _coupled_process_failure_key(
                    HISTORY_POLARITY_UNAVAILABLE, slot))
            continue
        end
        if !(all(isfinite, current.value) &&
                all(isfinite, previous.value))
            workspace.failure_key[1] = min(
                workspace.failure_key[1],
                _coupled_process_failure_key(
                    HISTORY_POLARITY_NONFINITE_INPUT, slot))
            continue
        end
        direction, magnitude =
            _history_direction_candidate(
                current.value, previous.value)
        if !(all(isfinite, direction) &&
                isfinite(magnitude))
            workspace.failure_key[1] = min(
                workspace.failure_key[1],
                _coupled_process_failure_key(
                    HISTORY_POLARITY_NONFINITE_OUTPUT, slot))
            continue
        end
        _write_history_direction!(
            workspace.candidate_coordinates,
            slot, direction)
        @inbounds workspace.candidate_magnitude[slot] =
            magnitude
    end
    key = workspace.failure_key[1]
    key == _COUPLED_PROCESS_FAILURE_SENTINEL ||
        throw(ArgumentError(
            "history-displacement direction failed with status $(_coupled_process_failure_code(key)) at cell $(_coupled_process_failing_cell(key))"))
    for slot in 1:slot_count
        is_active(snapshot, CellID(slot)) || continue
        values = map(column ->
            @inbounds(column[slot]),
            workspace.candidate_coordinates)
        _write_history_direction!(
            output_columns, slot, values)
        @inbounds magnitude_column[slot] =
            workspace.candidate_magnitude[slot]
    end
    return candidate
end

_history_magnitude(
    ::HistoryDisplacementDirectionExecution{
        OUTPUTS, MAGNITUDE}) where {
        OUTPUTS, MAGNITUDE} = MAGNITUDE

@kernel function _stage_history_displacement_direction!(
        candidate_coordinates, candidate_magnitude,
        history_values, history_heads, history_fills,
        history_generations, active, generations,
        failure_key, ::Val{Width}, ::Val{LagValue}) where {
        Width, LagValue}
    slot = @index(Global, Linear)
    @inbounds if active[slot] != UInt8(0)
        generation_value = CellGeneration(generations[slot])
        if history_generations[slot] !=
                generation_value ||
                history_fills[slot] <= UInt32(LagValue)
            Atomix.@atomic min(
                failure_key[1],
                _coupled_process_failure_key(
                    HISTORY_POLARITY_UNAVAILABLE, slot))
        else
            head = Int(history_heads[slot])
            current_column =
                mod(head - 1, Width) + 1
            previous_column =
                mod(head - LagValue - 1, Width) + 1
            current =
                history_values[slot, current_column]
            previous =
                history_values[slot, previous_column]
            if !(all(isfinite, current) &&
                    all(isfinite, previous))
                Atomix.@atomic min(
                    failure_key[1],
                    _coupled_process_failure_key(
                        HISTORY_POLARITY_NONFINITE_INPUT,
                        slot))
            else
                direction, magnitude =
                    _history_direction_candidate(
                        current, previous)
                if all(isfinite, direction) &&
                        isfinite(magnitude)
                    _write_history_direction!(
                        candidate_coordinates,
                        slot, direction)
                    candidate_magnitude[slot] = magnitude
                else
                    Atomix.@atomic min(
                        failure_key[1],
                        _coupled_process_failure_key(
                            HISTORY_POLARITY_NONFINITE_OUTPUT,
                            slot))
                end
            end
        end
    end
end

@kernel function _commit_history_displacement_direction!(
        output_coordinates, output_magnitude,
        candidate_coordinates, candidate_magnitude,
        active, failure_key)
    slot = @index(Global, Linear)
    @inbounds if failure_key[1] ==
            _COUPLED_PROCESS_FAILURE_SENTINEL &&
            active[slot] != UInt8(0)
        values = map(column -> column[slot],
            candidate_coordinates)
        _write_history_direction!(
            output_coordinates, slot, values)
        output_magnitude[slot] =
            candidate_magnitude[slot]
    end
end

@kernel function _reset_history_direction_failure!(
        failure_key)
    @inbounds failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
end

function apply_history_displacement_direction!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        history::CellHistoryState,
        process::HistoryDisplacementDirectionExecution)
    history.declaration.name === process.history ||
        throw(ArgumentError(
            "history-displacement process targets a different history"))
    execution = scientific_execution(scientific)
    output_coordinates =
        _history_displacement_columns(
            execution.core.properties, process)
    output_magnitude = _coupled_column(
        execution.core.properties,
        _history_magnitude(process))
    workspace = process.workspace
    capacity = length(execution.core.active)
    arrays = (
        history.values, history.heads, history.fills,
        history.generations, execution.core.active,
        execution.core.generations,
        output_coordinates..., output_magnitude,
        workspace.candidate_coordinates...,
        workspace.candidate_magnitude,
        workspace.failure_key)
    all(array -> array isa AbstractArray &&
            isbitstype(eltype(array)) &&
            isequal(
                KernelAbstractions.get_backend(array),
                plan.backend),
        arrays) || throw(ArgumentError(
        "history-displacement storage has a backend mismatch"))
    all(==(capacity), (
        length(history.generations),
        map(length, output_coordinates)...,
        length(output_magnitude),
        map(length, workspace.candidate_coordinates)...,
        length(workspace.candidate_magnitude))) ||
        throw(DimensionMismatch(
            "history-displacement capacities differ"))
    reset = _execution_kernel(
        plan, _reset_history_direction_failure!, 1)
    launch!(plan, reset, workspace.failure_key;
        ndrange = 1)
    stage = _execution_kernel(
        plan, _stage_history_displacement_direction!,
        capacity)
    launch!(plan, stage,
        workspace.candidate_coordinates,
        workspace.candidate_magnitude,
        history.values, history.heads, history.fills,
        history.generations, execution.core.active,
        execution.core.generations,
        workspace.failure_key,
        Val(Int(history.declaration.length)),
        Val(Int(process.lag)); ndrange = capacity)
    commit = _execution_kernel(
        plan, _commit_history_displacement_direction!,
        capacity)
    launch!(plan, commit,
        output_coordinates, output_magnitude,
        workspace.candidate_coordinates,
        workspace.candidate_magnitude,
        execution.core.active, workspace.failure_key;
        ndrange = capacity)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    key = only(Adapt.adapt(
        Array, workspace.failure_key))
    key == _COUPLED_PROCESS_FAILURE_SENTINEL ||
        throw(ArgumentError(
            "history-displacement direction failed with status $(_coupled_process_failure_code(key)) at cell $(_coupled_process_failing_cell(key))"))
    return scientific
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::HistoryDisplacementDirectionExecution,
        target_mcs, stage, interval)
    history = _state_by_name(
        snapshot.histories, process.history)
    apply_history_displacement_direction!(
        potts_candidate, potts_snapshot,
        history, process)
    return (
        _history_outputs(process)...,
        _history_magnitude(process))
end

_history_outputs(
    ::HistoryDisplacementDirectionExecution{
        OUTPUTS}) where {OUTPUTS} = OUTPUTS

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::HistoryDisplacementDirectionExecution,
        target_mcs, stage, interval)
    history = _state_by_name(
        integrator.state.histories, process.history)
    apply_history_displacement_direction!(
        integrator.potts.plan, integrator.potts.state,
        history, process)
    return ()
end
