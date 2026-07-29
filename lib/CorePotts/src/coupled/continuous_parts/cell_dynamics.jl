# Focused convenience declarations lower to the same numerical machinery.
struct CellDynamics{S <: ContinuousSystem}
    system::S
end
CellDynamics(name::Symbol; kwargs...) =
    begin
        system = ContinuousSystem(name; kwargs...)
        system.domain isa CellDomain || throw(ArgumentError(
            "CellDynamics requires a CellDomain"))
        CellDynamics(system)
    end
component_identity(dynamics::CellDynamics) = ComponentIdentity(
    dynamics.system.name, dynamics.system.version, :cell_dynamics)
component_semantic_data(dynamics::CellDynamics) =
    component_semantic_data(dynamics.system)
process_reads(dynamics::CellDynamics) = Tuple(
    (:cell_property, variable.property)
    for variable in dynamics.system.state)
process_writes(dynamics::CellDynamics) = process_reads(dynamics)

_cell_scope_matches(::Nothing, snapshot, cell) = true
_cell_scope_matches(scope::Symbol, snapshot, cell) = scope === :all
_cell_scope_matches(scope::Tuple, snapshot, cell) =
    cell_type(snapshot, cell) in scope
_cell_scope_matches(scope, snapshot, cell) =
    applicable(scope, snapshot, cell) ? Bool(scope(snapshot, cell)) :
    throw(ArgumentError("unsupported CellDomain scope $(typeof(scope))"))

function _cell_inputs(system, snapshot, cell, target_mcs)
    names = propertynames(system.inputs)
    values = map(names) do name
        source = getproperty(system.inputs, name)
        if source isa DirectLaw
            function_value = source.function_value
            applicable(function_value, snapshot, cell, target_mcs) ?
                function_value(snapshot, cell, target_mcs) :
                applicable(function_value, snapshot, cell) ?
                function_value(snapshot, cell) :
                throw(ArgumentError(
                    "cell input law `$(source.name)` has no supported snapshot signature"))
        elseif applicable(source, snapshot, cell, target_mcs)
            source(snapshot, cell, target_mcs)
        elseif applicable(source, snapshot, cell)
            source(snapshot, cell)
        else
            source
        end
    end
    return NamedTuple{names}(values)
end

function _continuous_interval_amount(clock, interval)
    return clock isa ContinuousClock ?
        interval_value(clock, interval) :
        interval isa ContinuousInterval ? interval.value :
        interval isa OneMCS ? clock.scale :
        interval isa HalfMCS ? clock.scale / 2 :
        clock.scale * convert(typeof(clock.scale), interval)
end

function execute_cell_dynamics!(candidate::LogicalPottsState,
        snapshot::LogicalPottsState, dynamics::CellDynamics,
        target_mcs, interval)
    system = dynamics.system
    system.domain isa CellDomain || throw(ArgumentError(
        "CellDynamics execution requires CellDomain"))
    amount = _continuous_interval_amount(system.clock, interval)
    property_keys = Tuple(variable.property for variable in system.state)
    names = Tuple(variable.name for variable in system.state)
    for cell in active_cell_ids(snapshot)
        _cell_scope_matches(
            system.domain.scope, snapshot, cell) || continue
        values = NamedTuple{names}(Tuple(
            property_value(snapshot, key, cell)
            for key in property_keys))
        local_state = ContinuousSystemState(system, values;
            time = (target_mcs - 1) * amount)
        inputs = _cell_inputs(system, snapshot, cell, target_mcs)
        advance_continuous_system!(local_state, amount; inputs)
        for (key, name) in zip(property_keys, names)
            set_cell_property!(
                candidate, key, cell, getproperty(local_state.values, name))
        end
    end
    return candidate
end

struct AffineCellAdvance{STATE, CONSTANT, INPUT, TIME, S, T}
    name::Symbol
    scope::S
    state::Symbol
    constant::Symbol
    input::Symbol
    time::Symbol
    decay::T
    duration::T
    version::VersionNumber
end
function AffineCellAdvance(name::Symbol, scope;
        state::Symbol, constant::Symbol, input::Symbol, time::Symbol,
        decay::T, duration::T,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isfinite(decay) && decay >= zero(T) || throw(ArgumentError(
        "affine cell decay must be finite and non-negative"))
    isfinite(duration) && duration > zero(T) || throw(ArgumentError(
        "affine cell duration must be finite and positive"))
    length(unique((state, constant, input, time))) == 4 || throw(ArgumentError(
        "affine cell property roles must be distinct"))
    return AffineCellAdvance{
        state, constant, input, time, typeof(scope), T}(
        name, scope, state, constant, input, time,
        decay, duration, version)
end
component_identity(process::AffineCellAdvance) =
    ComponentIdentity(process.name, process.version, :cell_dynamics)
component_semantic_data(process::AffineCellAdvance) = (
    scope = process.scope, state = process.state,
    constant = process.constant, input = process.input,
    time = process.time, decay = process.decay,
    duration = process.duration)
process_reads(process::AffineCellAdvance) = (
    (:cell_property, process.state),
    (:cell_property, process.constant),
    (:cell_property, process.input),
    (:cell_property, process.time))
process_writes(process::AffineCellAdvance) = (
    (:cell_property, process.state),
    (:cell_property, process.time))

@inline function _affine_columns(columns,
        ::AffineCellAdvance{STATE, CONSTANT, INPUT, TIME}) where {
        STATE, CONSTANT, INPUT, TIME}
    return (
        getproperty(columns, STATE),
        getproperty(columns, CONSTANT),
        getproperty(columns, INPUT),
        getproperty(columns, TIME))
end

struct AffineCellWorkspace{S <: AbstractVector, T <: AbstractVector,
        C <: AbstractVector, I <: AbstractVector, E <: AbstractVector}
    candidate_state::S
    candidate_time::T
    status::C
    failing_index::I
    publication_epoch::E
end

mutable struct AffineCellRuntime{W}
    name::Symbol
    workspace::W
end

function AffineCellWorkspace(state_values::AbstractVector,
        time_values::AbstractVector)
    length(state_values) == length(time_values) || throw(DimensionMismatch(
        "affine cell state and time capacities differ"))
    candidate_state = similar(state_values)
    candidate_time = similar(time_values)
    status = similar(state_values, UInt32, 1)
    failing_index = similar(state_values, UInt32, 1)
    publication_epoch = similar(state_values, UInt64, 1)
    fill!(candidate_state, zero(eltype(candidate_state)))
    fill!(candidate_time, zero(eltype(candidate_time)))
    fill!(status, UInt32(0))
    fill!(failing_index, UInt32(0))
    fill!(publication_epoch, UInt64(0))
    return AffineCellWorkspace(
        candidate_state, candidate_time,
        status, failing_index, publication_epoch)
end

AffineCellRuntime(
    process::AffineCellAdvance, state::LogicalPottsState) =
    AffineCellRuntime(
        process.name, AffineCellWorkspace(state, process))

function AffineCellWorkspace(
        state::LogicalPottsState, process::AffineCellAdvance)
    state_values, _, _, times =
        _affine_columns(state.properties.columns, process)
    return AffineCellWorkspace(state_values, times)
end

function Adapt.adapt_structure(to, workspace::AffineCellWorkspace)
    return AffineCellWorkspace(
        Adapt.adapt(to, workspace.candidate_state),
        Adapt.adapt(to, workspace.candidate_time),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index),
        Adapt.adapt(to, workspace.publication_epoch))
end

Adapt.adapt_structure(to, runtime::AffineCellRuntime) =
    AffineCellRuntime(
        runtime.name, Adapt.adapt(to, runtime.workspace))

function _publish_state!(
        destination::AffineCellRuntime, source::AffineCellRuntime)
    copyto!(
        destination.workspace.publication_epoch,
        source.workspace.publication_epoch)
    return destination
end

@inline function _affine_cell_solution(
        state, constant, input, decay, duration)
    if iszero(decay)
        return muladd(duration, constant + input, state)
    end
    equilibrium = (constant + input) / decay
    return muladd(
        state - equilibrium, exp(-decay * duration), equilibrium)
end

function apply_affine_cell_advance!(
        state::LogicalPottsState, process::AffineCellAdvance,
        workspace::AffineCellWorkspace)
    state_values, constants, inputs, times =
        _affine_columns(state.properties.columns, process)
    slots = nslots(capacity(state))
    length(state_values) == slots &&
        length(constants) == slots &&
        length(inputs) == slots &&
        length(times) == slots &&
        length(workspace.candidate_state) == slots &&
        length(workspace.candidate_time) == slots ||
        throw(DimensionMismatch(
            "affine cell property/workspace capacities differ"))
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_index, UInt32(0))
    copyto!(workspace.candidate_state, state_values)
    copyto!(workspace.candidate_time, times)
    for slot in 1:slots
        cell = CellID(slot)
        is_active(state, cell) || continue
        _cell_scope_matches_exchange(
            process.scope, state, cell) || continue
        state_value = @inbounds state_values[slot]
        constant = @inbounds constants[slot]
        input = @inbounds inputs[slot]
        time = @inbounds times[slot]
        if !(isfinite(state_value) && isfinite(constant) &&
                isfinite(input) && isfinite(time))
            workspace.status[1] = UInt32(1)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "affine cell input is nonfinite at slot $slot"))
        end
        advanced = _affine_cell_solution(
            state_value, constant, input,
            process.decay, process.duration)
        advanced_time = time + process.duration
        if !(isfinite(advanced) && isfinite(advanced_time))
            workspace.status[1] = UInt32(2)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "affine cell advance is nonfinite at slot $slot"))
        end
        @inbounds begin
            workspace.candidate_state[slot] =
                convert(eltype(state_values), advanced)
            workspace.candidate_time[slot] =
                convert(eltype(times), advanced_time)
        end
    end
    copyto!(state_values, workspace.candidate_state)
    copyto!(times, workspace.candidate_time)
    workspace.publication_epoch[1] += UInt64(1)
    return state
end

function execute_affine_cell_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        process::AffineCellAdvance)
    source_runtime = _state_by_name(
        snapshot.globals, process.name)
    target_runtime = _state_by_name(
        candidate.globals, process.name)
    source_runtime isa AffineCellRuntime &&
        target_runtime isa AffineCellRuntime || throw(ArgumentError(
            "affine cell runtime is not realized"))
    _publish_state!(target_runtime, source_runtime)
    apply_affine_cell_advance!(
        potts_candidate, process, target_runtime.workspace)
    return (process.state, process.time)
end

@inline function _record_affine_device_failure!(
        status, failing_index, code, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@kernel function _affine_cell_initialize!(
        candidate_state, candidate_time, state_values, times,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds begin
        candidate_state[slot] = state_values[slot]
        candidate_time[slot] = times[slot]
        if slot == 1
            status[1] = UInt32(0)
            failing_index[1] = typemax(UInt32)
        end
    end
end

@kernel function _affine_cell_advance_kernel!(
        candidate_state, candidate_time,
        state_values, constants, inputs, times,
        active, cell_types, scope_type, decay, duration,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds if active[slot] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[slot])
        state_value = state_values[slot]
        constant = constants[slot]
        input = inputs[slot]
        time = times[slot]
        if !(isfinite(state_value) && isfinite(constant) &&
                isfinite(input) && isfinite(time))
            _record_affine_device_failure!(
                status, failing_index, 1, slot)
        else
            advanced = _affine_cell_solution(
                state_value, constant, input, decay, duration)
            advanced_time = time + duration
            if isfinite(advanced) && isfinite(advanced_time)
                candidate_state[slot] = advanced
                candidate_time[slot] = advanced_time
            else
                _record_affine_device_failure!(
                    status, failing_index, 2, slot)
            end
        end
    end
end

@kernel function _affine_cell_commit!(
        state_values, times, candidate_state, candidate_time,
        publication_epoch, status)
    slot = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        state_values[slot] = candidate_state[slot]
        times[slot] = candidate_time[slot]
        slot == 1 && (publication_epoch[1] += UInt64(1))
    end
end

function apply_affine_cell_advance!(plan::ExecutionPlan,
        scientific::CompiledScientificState,
        process::AffineCellAdvance,
        workspace::AffineCellWorkspace)
    execution = scientific_execution(scientific)
    core = execution.core
    state_values, constants, inputs, times =
        _affine_columns(core.properties, process)
    arrays = (
        state_values, constants, inputs, times,
        core.active, core.cell_types,
        workspace.candidate_state, workspace.candidate_time,
        workspace.status, workspace.failing_index,
        workspace.publication_epoch)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable affine cell storage has a backend mismatch"))
    slots = length(core.active)
    all(==(slots), map(length, (
        state_values, constants, inputs, times,
        workspace.candidate_state, workspace.candidate_time))) ||
        throw(DimensionMismatch(
            "portable affine cell capacities differ"))
    scope_type = _portable_scope_type(process.scope)
    initialize = _execution_kernel(
        plan, _affine_cell_initialize!, slots)
    launch!(plan, initialize,
        workspace.candidate_state, workspace.candidate_time,
        state_values, times, workspace.status,
        workspace.failing_index; ndrange = slots)
    advance = _execution_kernel(
        plan, _affine_cell_advance_kernel!, slots)
    launch!(plan, advance,
        workspace.candidate_state, workspace.candidate_time,
        state_values, constants, inputs, times,
        core.active, core.cell_types, scope_type,
        process.decay, process.duration,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    commit = _execution_kernel(
        plan, _affine_cell_commit!, slots)
    launch!(plan, commit,
        state_values, times,
        workspace.candidate_state, workspace.candidate_time,
        workspace.publication_epoch, workspace.status;
        ndrange = slots)
    return scientific
end
function synchronize_affine_cell_status!(
        plan::ExecutionPlan, workspace::AffineCellWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_index))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(ArgumentError(
        "affine cell advance failed with status $status at slot $failing"))
end

struct UniformCellInitialization{PROPERTY, S, T}
    name::Symbol
    scope::S
    property::Symbol
    lower::T
    upper::T
    namespace::RNGNamespaceIdentity
    version::VersionNumber
end
function UniformCellInitialization(name::Symbol, scope;
        property::Symbol, lower::T, upper::T,
        namespace::RNGNamespaceIdentity,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isfinite(lower) && isfinite(upper) && lower < upper ||
        throw(ArgumentError(
            "uniform cell initialization requires finite ordered bounds"))
    return UniformCellInitialization{
        property, typeof(scope), T}(
        name, scope, property, lower, upper, namespace, version)
end
component_identity(initializer::UniformCellInitialization) =
    ComponentIdentity(
        initializer.name, initializer.version, :cell_initialization)
component_semantic_data(initializer::UniformCellInitialization) = (
    scope = initializer.scope, property = initializer.property,
    lower = initializer.lower, upper = initializer.upper,
    namespace = initializer.namespace)
process_reads(::UniformCellInitialization) = ()
process_writes(initializer::UniformCellInitialization) =
    ((:cell_property, initializer.property),)

@inline _uniform_initialization_values(
    columns, ::UniformCellInitialization{PROPERTY}) where {PROPERTY} =
    getproperty(columns, PROPERTY)

function apply_uniform_cell_initialization!(
        state::LogicalPottsState,
        initializer::UniformCellInitialization,
        workspace::AffineCellWorkspace,
        master_seed::UInt64)
    values = _uniform_initialization_values(
        state.properties.columns, initializer)
    length(values) == length(workspace.candidate_state) ||
        throw(DimensionMismatch(
            "uniform initialization workspace capacity differs"))
    copyto!(workspace.candidate_state, values)
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_index, UInt32(0))
    contract = Philox4x32x10V1()
    operation = extension_rng_operation(initializer.namespace)
    span = initializer.upper - initializer.lower
    for slot in eachindex(values)
        cell = CellID(slot)
        is_active(state, cell) || continue
        _cell_scope_matches_exchange(
            initializer.scope, state, cell) || continue
        address = RNGAddress(
            AuxiliaryInitializationStream, UInt64(0), UInt8(0),
            operation, CellEntity, UInt32(slot),
            value(generation(state, cell)), UInt8(0), UInt16(0))
        uniform = uniform_open01(
            eltype(values), contract, master_seed, address)
        candidate = muladd(span, uniform, initializer.lower)
        if !isfinite(candidate)
            workspace.status[1] = UInt32(1)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "uniform cell initialization is nonfinite at slot $slot"))
        end
        @inbounds workspace.candidate_state[slot] = candidate
    end
    copyto!(values, workspace.candidate_state)
    workspace.publication_epoch[1] += UInt64(1)
    return state
end

@kernel function _uniform_cell_initialization_kernel!(
        candidate, active, generations, cell_types,
        scope_type, lower, upper, namespace, master_seed,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds if active[slot] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[slot])
        operation = extension_rng_operation(namespace)
        address = _rng_address_unchecked(
            AuxiliaryInitializationStream, UInt64(0), UInt8(0),
            operation, CellEntity, UInt32(slot), generations[slot],
            UInt8(0), UInt16(0))
        uniform = uniform_open01(
            eltype(candidate), Philox4x32x10V1(),
            master_seed, address)
        value = muladd(upper - lower, uniform, lower)
        if isfinite(value)
            candidate[slot] = value
        else
            _record_affine_device_failure!(
                status, failing_index, 1, slot)
        end
    end
end

@kernel function _uniform_cell_commit!(
        values, candidate, publication_epoch, status)
    slot = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        values[slot] = candidate[slot]
        slot == 1 && (publication_epoch[1] += UInt64(1))
    end
end

function apply_uniform_cell_initialization!(
        plan::ExecutionPlan, scientific::CompiledScientificState,
        initializer::UniformCellInitialization,
        workspace::AffineCellWorkspace, master_seed::UInt64)
    execution = scientific_execution(scientific)
    core = execution.core
    values = _uniform_initialization_values(
        core.properties, initializer)
    length(values) == length(workspace.candidate_state) ||
        throw(DimensionMismatch(
            "portable uniform initialization capacity differs"))
    arrays = (
        values, core.active, core.generations, core.cell_types,
        workspace.candidate_state, workspace.status,
        workspace.failing_index, workspace.publication_epoch)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable uniform initialization has a backend mismatch"))
    slots = length(values)
    initialize = _execution_kernel(
        plan, _affine_cell_initialize!, slots)
    launch!(plan, initialize,
        workspace.candidate_state, workspace.candidate_time,
        values, workspace.candidate_time,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    kernel = _execution_kernel(
        plan, _uniform_cell_initialization_kernel!, slots)
    launch!(plan, kernel,
        workspace.candidate_state, core.active,
        core.generations, core.cell_types,
        _portable_scope_type(initializer.scope),
        initializer.lower, initializer.upper,
        initializer.namespace, master_seed,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    commit = _execution_kernel(
        plan, _uniform_cell_commit!, slots)
    launch!(plan, commit,
        values, workspace.candidate_state,
        workspace.publication_epoch, workspace.status;
        ndrange = slots)
    return scientific
end
