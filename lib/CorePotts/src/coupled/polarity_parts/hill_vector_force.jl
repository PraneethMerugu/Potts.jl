struct HillVectorForceWorkspace{
        T <: AbstractFloat,
        V <: AbstractVector{T},
        C <: AbstractVector{UInt32}}
    candidate_x::V
    candidate_y::V
    candidate_magnitude::V
    candidate_coefficient::V
    failure_key::C
end

function HillVectorForceWorkspace(values::AbstractVector{T}) where {
        T <: AbstractFloat}
    length(values) <= Int(_COUPLED_PROCESS_MAX_CELL) ||
        throw(ArgumentError(
            "Hill-vector-force capacity exceeds packed failure-key capacity"))
    arrays = ntuple(
        _ -> similar(values, T, length(values)), Val(4))
    failure_key = similar(values, UInt32, 1)
    for array in (arrays..., failure_key)
        fill!(array, zero(eltype(array)))
    end
    fill!(failure_key, _COUPLED_PROCESS_FAILURE_SENTINEL)
    return HillVectorForceWorkspace(
        arrays..., failure_key)
end

function Adapt.adapt_structure(to, workspace::HillVectorForceWorkspace)
    return HillVectorForceWorkspace(
        Adapt.adapt(to, workspace.candidate_x),
        Adapt.adapt(to, workspace.candidate_y),
        Adapt.adapt(to, workspace.candidate_magnitude),
        Adapt.adapt(to, workspace.candidate_coefficient),
        Adapt.adapt(to, workspace.failure_key))
end

hill_vector_force_workspace_bytes(
    workspace::HillVectorForceWorkspace) =
    sum(_array_bytes, (
        workspace.candidate_x, workspace.candidate_y,
        workspace.candidate_magnitude,
        workspace.candidate_coefficient,
        workspace.failure_key); init = 0)

"""
Backend-independent declaration of a Hill-response vector-force update.
Realization allocates only its bounded candidate/status workspace.
"""
struct HillVectorForce{
        PX, PY, Signal, FX, FY, Magnitude, Coefficient,
        Exponent, T <: AbstractFloat}
    name::Symbol
    half_activation::T
    maximum_force::T
    direction::T
    version::VersionNumber
end

function HillVectorForce(
        name::Symbol;
        polarity_x::Symbol, polarity_y::Symbol,
        signal::Symbol, force_x::Symbol, force_y::Symbol,
        magnitude::Symbol, coefficient::Symbol,
        half_activation::T, maximum_force::T,
        exponent::Integer = 4,
        direction::T = -one(T),
        version::VersionNumber =
            COUPLED_EXECUTION_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isempty(String(name)) && throw(ArgumentError(
        "Hill-vector-force identity must not be empty"))
    isfinite(half_activation) && half_activation > zero(T) ||
        throw(ArgumentError(
            "Hill half activation must be finite and positive"))
    isfinite(maximum_force) && maximum_force >= zero(T) ||
        throw(ArgumentError(
            "maximum force must be finite and nonnegative"))
    0 < exponent <= 16 || throw(ArgumentError(
        "Hill exponent must lie in 1:16"))
    isfinite(direction) || throw(ArgumentError(
        "force direction must be finite"))
    properties = (
        polarity_x, polarity_y, signal, force_x, force_y,
        magnitude, coefficient)
    length(unique(properties)) == length(properties) ||
        throw(ArgumentError(
            "Hill-vector-force properties must be unique"))
    return HillVectorForce{
        polarity_x, polarity_y, signal, force_x, force_y,
        magnitude, coefficient, exponent, T}(
        name, half_activation, maximum_force,
        direction, version)
end

component_identity(process::HillVectorForce) =
    ComponentIdentity(
        process.name, process.version, :hill_vector_force)
component_semantic_data(process::HillVectorForce{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent} = (
    polarity_x = PX,
    polarity_y = PY,
    signal = Signal,
    force_x = FX,
    force_y = FY,
    magnitude = Magnitude,
    coefficient = Coefficient,
    exponent = Exponent,
    half_activation = process.half_activation,
    maximum_force = process.maximum_force,
    direction = process.direction,
)
process_reads(::HillVectorForce{
        PX, PY, Signal}) where {PX, PY, Signal} = (
    (:cell, PX), (:cell, PY), (:cell, Signal),
)
process_writes(::HillVectorForce{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient} = (
    (:cell, FX), (:cell, FY),
    (:cell, Magnitude), (:cell, Coefficient),
)

struct HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude, Coefficient,
        Exponent, T <: AbstractFloat,
        W <: HillVectorForceWorkspace}
    name::Symbol
    half_activation::T
    maximum_force::T
    direction::T
    workspace::W
    version::VersionNumber
end

function HillVectorForceExecution(
        name::Symbol, state;
        polarity_x::Symbol, polarity_y::Symbol,
        signal::Symbol, force_x::Symbol, force_y::Symbol,
        magnitude::Symbol, coefficient::Symbol,
        half_activation::T, maximum_force::T,
        exponent::Integer = 4,
        direction::T = -one(T),
        version::VersionNumber =
            COUPLED_EXECUTION_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isempty(String(name)) && throw(ArgumentError(
        "Hill-vector-force identity must not be empty"))
    isfinite(half_activation) && half_activation > zero(T) ||
        throw(ArgumentError(
            "Hill half activation must be finite and positive"))
    isfinite(maximum_force) && maximum_force >= zero(T) ||
        throw(ArgumentError(
            "maximum force must be finite and nonnegative"))
    0 < exponent <= 16 || throw(ArgumentError(
        "Hill exponent must lie in 1:16"))
    isfinite(direction) || throw(ArgumentError(
        "force direction must be finite"))
    properties = (
        polarity_x, polarity_y, signal, force_x, force_y,
        magnitude, coefficient)
    columns = map(
        property -> _coupled_property_column(state, property),
        properties)
    all(column -> column isa AbstractVector{T}, columns) ||
        throw(ArgumentError(
            "Hill-vector-force properties must share the parameter floating type"))
    all(==(length(first(columns))), map(length, columns)) ||
        throw(DimensionMismatch(
            "Hill-vector-force property capacities differ"))
    workspace = HillVectorForceWorkspace(first(columns))
    return HillVectorForceExecution{
        polarity_x, polarity_y, signal, force_x, force_y,
        magnitude, coefficient, exponent, T,
        typeof(workspace)}(
        name, half_activation, maximum_force,
        direction, workspace, version)
end

HillVectorForce(
    name::Symbol, state; kwargs...) =
    HillVectorForceExecution(
        name, state; kwargs...)

function realize_coupled_process(
        process::HillVectorForce{
            PX, PY, Signal, FX, FY, Magnitude,
            Coefficient, Exponent},
        state::CoupledState,
        scientific::CompiledScientificState) where {
            PX, PY, Signal, FX, FY, Magnitude,
            Coefficient, Exponent}
    return HillVectorForceExecution(
        process.name, scientific;
        polarity_x = PX, polarity_y = PY,
        signal = Signal, force_x = FX, force_y = FY,
        magnitude = Magnitude,
        coefficient = Coefficient,
        half_activation = process.half_activation,
        maximum_force = process.maximum_force,
        exponent = Exponent,
        direction = process.direction,
        version = process.version)
end

function Adapt.adapt_structure(
        to, process::HillVectorForceExecution{
            PX, PY, Signal, FX, FY, Magnitude,
            Coefficient, Exponent}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent}
    workspace = Adapt.adapt(to, process.workspace)
    return HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent,
        typeof(process.half_activation),
        typeof(workspace)}(
        process.name, process.half_activation,
        process.maximum_force, process.direction,
        workspace, process.version)
end

component_identity(process::HillVectorForceExecution) =
    ComponentIdentity(
        process.name, process.version, :hill_vector_force)
component_semantic_data(process::HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient, Exponent} = (
    polarity_x = PX,
    polarity_y = PY,
    signal = Signal,
    force_x = FX,
    force_y = FY,
    magnitude = Magnitude,
    coefficient = Coefficient,
    exponent = Exponent,
    half_activation = process.half_activation,
    maximum_force = process.maximum_force,
    direction = process.direction,
)
process_reads(::HillVectorForceExecution{
        PX, PY, Signal}) where {PX, PY, Signal} = (
    (:cell, PX), (:cell, PY), (:cell, Signal),
)
process_writes(::HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient} = (
    (:cell, FX), (:cell, FY),
    (:cell, Magnitude), (:cell, Coefficient),
)
canonical_process_law(
        process::HillVectorForceExecution{
            PX, PY, Signal, FX, FY, Magnitude,
            Coefficient, Exponent}) where {
            PX, PY, Signal, FX, FY, Magnitude,
            Coefficient, Exponent} =
    HillVectorForce(
        process.name;
        polarity_x = PX, polarity_y = PY,
        signal = Signal, force_x = FX, force_y = FY,
        magnitude = Magnitude,
        coefficient = Coefficient,
        half_activation = process.half_activation,
        maximum_force = process.maximum_force,
        exponent = Exponent,
        direction = process.direction,
        version = process.version)

@inline function _hill_force_columns(
        properties,
        ::HillVectorForceExecution{
            PX, PY, Signal, FX, FY,
            Magnitude, Coefficient}) where {
        PX, PY, Signal, FX, FY,
        Magnitude, Coefficient}
    return (
        _coupled_column(properties, PX),
        _coupled_column(properties, PY),
        _coupled_column(properties, Signal),
        _coupled_column(properties, FX),
        _coupled_column(properties, FY),
        _coupled_column(properties, Magnitude),
        _coupled_column(properties, Coefficient),
    )
end

@inline _hill_power(value, ::Val{Exponent}) where {Exponent} =
    value^Exponent

@inline function _hill_force_candidate(
        polarity_x, polarity_y, signal,
        half_activation, maximum_force,
        direction, ::Val{Exponent}) where {Exponent}
    signal_power = _hill_power(signal, Val(Exponent))
    half_power = _hill_power(
        half_activation, Val(Exponent))
    coefficient =
        signal_power / (half_power + signal_power)
    magnitude = maximum_force * coefficient
    return (
        direction * magnitude * polarity_x,
        direction * magnitude * polarity_y,
        magnitude,
        coefficient,
    )
end

@inline _hill_exponent(
    ::HillVectorForceExecution{
        PX, PY, Signal, FX, FY,
        Magnitude, Coefficient, Exponent}) where {
        PX, PY, Signal, FX, FY,
        Magnitude, Coefficient, Exponent} = Val(Exponent)

function apply_hill_vector_force!(
        candidate::LogicalPottsState,
        snapshot::LogicalPottsState,
        process::HillVectorForceExecution)
    source_px, source_py, source_signal, _, _, _, _ =
        _hill_force_columns(snapshot.properties, process)
    _, _, _, target_fx, target_fy,
        target_magnitude, target_coefficient =
        _hill_force_columns(candidate.properties, process)
    workspace = process.workspace
    workspace.failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
    for slot in eachindex(source_px)
        cell = CellID(slot)
        is_active(snapshot, cell) || continue
        px = @inbounds source_px[slot]
        py = @inbounds source_py[slot]
        signal = @inbounds source_signal[slot]
        if !(isfinite(px) && isfinite(py) &&
                isfinite(signal))
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    HILL_FORCE_NONFINITE_INPUT, slot)
            throw(ArgumentError(
                "Hill-vector-force input is nonfinite at slot $slot"))
        elseif signal < zero(signal)
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    HILL_FORCE_INVALID_SIGNAL, slot)
            throw(ArgumentError(
                "Hill-vector-force signal is negative at slot $slot"))
        end
        force_x, force_y, magnitude, coefficient =
            _hill_force_candidate(
                px, py, signal,
                process.half_activation,
                process.maximum_force,
                process.direction,
                _hill_exponent(process))
        if !(isfinite(force_x) && isfinite(force_y) &&
                isfinite(magnitude) && isfinite(coefficient))
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    HILL_FORCE_NONFINITE_OUTPUT, slot)
            throw(ArgumentError(
                "Hill-vector-force output is nonfinite at slot $slot"))
        end
        @inbounds begin
            workspace.candidate_x[slot] = force_x
            workspace.candidate_y[slot] = force_y
            workspace.candidate_magnitude[slot] = magnitude
            workspace.candidate_coefficient[slot] = coefficient
        end
    end
    for slot in eachindex(source_px)
        is_active(snapshot, CellID(slot)) || continue
        @inbounds begin
            target_fx[slot] = workspace.candidate_x[slot]
            target_fy[slot] = workspace.candidate_y[slot]
            target_magnitude[slot] =
                workspace.candidate_magnitude[slot]
            target_coefficient[slot] =
                workspace.candidate_coefficient[slot]
        end
    end
    return candidate
end

@inline function _record_hill_force_failure!(
        failure_key, code, cell)
    key = _coupled_process_failure_key(UInt32(code), cell)
    Atomix.@atomic min(failure_key[1], key)
    return nothing
end

@kernel function _hill_force_initialize!(
        candidate_x, candidate_y,
        candidate_magnitude, candidate_coefficient,
        force_x, force_y, magnitude, coefficient,
        failure_key)
    cell = @index(Global, Linear)
    @inbounds begin
        candidate_x[cell] = force_x[cell]
        candidate_y[cell] = force_y[cell]
        candidate_magnitude[cell] = magnitude[cell]
        candidate_coefficient[cell] = coefficient[cell]
        if cell == 1
            failure_key[1] =
                _COUPLED_PROCESS_FAILURE_SENTINEL
        end
    end
end

@kernel function _hill_force_compute!(
        candidate_x, candidate_y,
        candidate_magnitude, candidate_coefficient,
        polarity_x, polarity_y, signal, active,
        half_activation, maximum_force, direction,
        exponent, failure_key)
    cell = @index(Global, Linear)
    @inbounds if active[cell] != UInt8(0)
        px = polarity_x[cell]
        py = polarity_y[cell]
        input = signal[cell]
        if !(isfinite(px) && isfinite(py) &&
                isfinite(input))
            _record_hill_force_failure!(
                failure_key,
                HILL_FORCE_NONFINITE_INPUT, cell)
        elseif input < zero(input)
            _record_hill_force_failure!(
                failure_key,
                HILL_FORCE_INVALID_SIGNAL, cell)
        else
            force_x, force_y, magnitude, coefficient =
                _hill_force_candidate(
                    px, py, input, half_activation,
                    maximum_force, direction, exponent)
            if isfinite(force_x) && isfinite(force_y) &&
                    isfinite(magnitude) && isfinite(coefficient)
                candidate_x[cell] = force_x
                candidate_y[cell] = force_y
                candidate_magnitude[cell] = magnitude
                candidate_coefficient[cell] = coefficient
            else
                _record_hill_force_failure!(
                    failure_key,
                    HILL_FORCE_NONFINITE_OUTPUT, cell)
            end
        end
    end
end

@kernel function _hill_force_commit!(
        force_x, force_y, magnitude, coefficient,
        candidate_x, candidate_y,
        candidate_magnitude, candidate_coefficient,
        active, failure_key)
    cell = @index(Global, Linear)
    @inbounds if failure_key[1] ==
            _COUPLED_PROCESS_FAILURE_SENTINEL &&
            active[cell] != UInt8(0)
        force_x[cell] = candidate_x[cell]
        force_y[cell] = candidate_y[cell]
        magnitude[cell] = candidate_magnitude[cell]
        coefficient[cell] = candidate_coefficient[cell]
    end
end

function apply_hill_vector_force!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        process::HillVectorForceExecution)
    core = scientific_execution(scientific).core
    polarity_x, polarity_y, signal,
        force_x, force_y, magnitude, coefficient =
        _hill_force_columns(core.properties, process)
    workspace = process.workspace
    capacity = length(core.active)
    arrays = (
        polarity_x, polarity_y, signal,
        force_x, force_y, magnitude, coefficient,
        core.active, workspace.candidate_x,
        workspace.candidate_y,
        workspace.candidate_magnitude,
        workspace.candidate_coefficient,
        workspace.failure_key)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable Hill-vector-force storage has a backend mismatch"))
    all(==(capacity), map(length, arrays[1:12])) ||
        throw(DimensionMismatch(
            "portable Hill-vector-force capacities differ"))
    initialize = _execution_kernel(
        plan, _hill_force_initialize!, capacity)
    launch!(plan, initialize,
        workspace.candidate_x, workspace.candidate_y,
        workspace.candidate_magnitude,
        workspace.candidate_coefficient,
        force_x, force_y, magnitude, coefficient,
        workspace.failure_key;
        ndrange = capacity)
    compute = _execution_kernel(
        plan, _hill_force_compute!, capacity)
    launch!(plan, compute,
        workspace.candidate_x, workspace.candidate_y,
        workspace.candidate_magnitude,
        workspace.candidate_coefficient,
        polarity_x, polarity_y, signal, core.active,
        process.half_activation, process.maximum_force,
        process.direction, _hill_exponent(process),
        workspace.failure_key;
        ndrange = capacity)
    commit = _execution_kernel(
        plan, _hill_force_commit!, capacity)
    launch!(plan, commit,
        force_x, force_y, magnitude, coefficient,
        workspace.candidate_x, workspace.candidate_y,
        workspace.candidate_magnitude,
        workspace.candidate_coefficient,
        core.active, workspace.failure_key;
        ndrange = capacity)
    return scientific
end

function synchronize_hill_vector_force_status!(
        plan::ExecutionPlan, process::HillVectorForceExecution)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    key = only(Adapt.adapt(
        Array, process.workspace.failure_key))
    key == _COUPLED_PROCESS_FAILURE_SENTINEL &&
        return process
    status = _coupled_process_failure_code(key)
    cell = _coupled_process_failing_cell(key)
    throw(ArgumentError(
        "Hill-vector-force update failed with status $status at cell $cell"))
end

@inline _hill_force_x_property(
    ::HillVectorForceExecution{
        PX, PY, Signal, FX}) where {
        PX, PY, Signal, FX} = FX
@inline _hill_force_y_property(
    ::HillVectorForceExecution{
        PX, PY, Signal, FX, FY}) where {
        PX, PY, Signal, FX, FY} = FY
@inline _hill_force_magnitude_property(
    ::HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude}) where {
        PX, PY, Signal, FX, FY, Magnitude} = Magnitude
@inline _hill_force_coefficient_property(
    ::HillVectorForceExecution{
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient}) where {
        PX, PY, Signal, FX, FY, Magnitude,
        Coefficient} = Coefficient

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::HillVectorForceExecution,
        target_mcs, stage, interval)
    apply_hill_vector_force!(
        potts_candidate, potts_snapshot, process)
    return (
        _hill_force_x_property(process),
        _hill_force_y_property(process),
        _hill_force_magnitude_property(process),
        _hill_force_coefficient_property(process),
    )
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::HillVectorForceExecution,
        target_mcs, stage, interval)
    apply_hill_vector_force!(
        integrator.potts.plan, integrator.potts.state,
        process)
    synchronize_hill_vector_force_status!(
        integrator.potts.plan, process)
    return ()
end
