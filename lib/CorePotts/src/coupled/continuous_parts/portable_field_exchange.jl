function _portable_reduction_width(plan::ExecutionPlan)
    width = plan.block_size
    ispow2(width) && 2 <= width <= 256 || throw(ArgumentError(
        "portable fixed-tree reduction requires a power-of-two block size in 2:256"))
    return width
end

@inline function _record_exchange_device_failure!(
        status, failing_index, code::FieldExchangeFailureCode, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@inline _portable_scope_type(::Nothing) = UInt32(0)
@inline _portable_scope_type(scope::Symbol) =
    scope in (:all, :cells) ? UInt32(0) :
    throw(ArgumentError(
        "portable uptake scope symbol must be :all or :cells"))
@inline _portable_scope_type(scope::CellTypeID) = value(scope)
@inline _portable_cell_eligible(scope_type, cell_type) =
    iszero(scope_type) | (scope_type == cell_type)

@kernel function _exchange_device_initialize_sites!(
        candidate_field, removals, field)
    site = @index(Global, Linear)
    @inbounds begin
        candidate_field[site] = field[site]
        removals[site] = zero(eltype(removals))
    end
end

@kernel function _exchange_device_initialize_cells!(
        raw_totals, candidate_signal, signal)
    cell = @index(Global, Linear)
    @inbounds begin
        raw_totals[cell] = zero(eltype(raw_totals))
        candidate_signal[cell] = signal[cell]
    end
end

@kernel function _exchange_device_clear_status!(status, failing_index)
    index = @index(Global, Linear)
    @inbounds if index == 1
        status[1] = UInt32(ExchangeSucceeded)
        failing_index[1] = typemax(UInt32)
    end
end

@kernel function _exchange_device_reduce_cells!(
        candidate_field, removals, raw_totals,
        field, owner_tags, owner_ids, active, cell_types, volumes,
        scope_type, maximum, relative_rate, status, failing_index,
        ::Val{Width}) where {Width}
    cell = @index(Group, Linear)
    lane = @index(Local, Linear)
    scratch = @localmem eltype(raw_totals) (Width,)
    total = zero(eltype(raw_totals))
    eligible = cell <= length(active) &&
        @inbounds(active[cell] != UInt8(0)) &&
        _portable_cell_eligible(
            scope_type, @inbounds(cell_types[cell]))
    if eligible
        site = lane
        while site <= length(field)
            if @inbounds(owner_tags[site] == _CELL_OWNER_TAG &&
                    owner_ids[site] == UInt32(cell))
                concentration = @inbounds field[site]
                if !(isfinite(concentration) &&
                        concentration >= zero(concentration))
                    _record_exchange_device_failure!(
                        status, failing_index,
                        ExchangeInvalidConcentration, site)
                else
                    removal = min(maximum, relative_rate * concentration)
                    if !(isfinite(removal) &&
                            zero(removal) <= removal <= concentration)
                        _record_exchange_device_failure!(
                            status, failing_index,
                            ExchangeInvalidRemoval, site)
                    else
                        @inbounds begin
                            removals[site] = removal
                            candidate_field[site] = concentration - removal
                        end
                        total += eltype(raw_totals)(removal)
                    end
                end
            end
            site += Width
        end
    end
    @inbounds scratch[lane] = total
    @synchronize
    if Width >= 256
        lane <= 128 && (@inbounds scratch[lane] += scratch[lane + 128])
        @synchronize
    end
    if Width >= 128
        lane <= 64 && (@inbounds scratch[lane] += scratch[lane + 64])
        @synchronize
    end
    if Width >= 64
        lane <= 32 && (@inbounds scratch[lane] += scratch[lane + 32])
        @synchronize
    end
    if Width >= 32
        lane <= 16 && (@inbounds scratch[lane] += scratch[lane + 16])
        @synchronize
    end
    if Width >= 16
        lane <= 8 && (@inbounds scratch[lane] += scratch[lane + 8])
        @synchronize
    end
    if Width >= 8
        lane <= 4 && (@inbounds scratch[lane] += scratch[lane + 4])
        @synchronize
    end
    if Width >= 4
        lane <= 2 && (@inbounds scratch[lane] += scratch[lane + 2])
        @synchronize
    end
    lane <= 1 && (@inbounds scratch[lane] += scratch[lane + 1])
    @synchronize
    if lane == 1
        if cell <= length(active) &&
                @inbounds(active[cell] != UInt8(0)) &&
                _portable_cell_eligible(
                    scope_type, @inbounds(cell_types[cell]))
            volume = @inbounds volumes[cell]
            if volume <= 0
                _record_exchange_device_failure!(
                    status, failing_index, ExchangeInvalidVolume, cell)
            else
                raw = @inbounds scratch[1] /
                    eltype(raw_totals)(volume)
                if !(isfinite(raw) && raw >= zero(raw))
                    _record_exchange_device_failure!(
                        status, failing_index,
                        ExchangeInvalidRemoval, cell)
                else
                    @inbounds raw_totals[cell] = raw
                end
            end
        end
    end
end

@kernel function _exchange_device_calibrate_maximum!(
        value, initialized, raw_totals, active, cell_types,
        scope_type, numerator, status, failing_index,
        ::Val{Width}) where {Width}
    lane = @index(Local, Linear)
    scratch = @localmem eltype(raw_totals) (Width,)
    local_maximum = zero(eltype(raw_totals))
    cell = lane
    while cell <= length(raw_totals)
        eligible = @inbounds(active[cell] != UInt8(0)) &&
            _portable_cell_eligible(
                scope_type, @inbounds(cell_types[cell]))
        eligible &&
            (local_maximum = max(
                local_maximum, @inbounds(raw_totals[cell])))
        cell += Width
    end
    @inbounds scratch[lane] = local_maximum
    @synchronize
    if Width >= 256
        lane <= 128 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 128]))
        @synchronize
    end
    if Width >= 128
        lane <= 64 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 64]))
        @synchronize
    end
    if Width >= 64
        lane <= 32 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 32]))
        @synchronize
    end
    if Width >= 32
        lane <= 16 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 16]))
        @synchronize
    end
    if Width >= 16
        lane <= 8 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 8]))
        @synchronize
    end
    if Width >= 8
        lane <= 4 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 4]))
        @synchronize
    end
    if Width >= 4
        lane <= 2 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 2]))
        @synchronize
    end
    lane <= 1 && (@inbounds scratch[lane] =
        max(scratch[lane], scratch[lane + 1]))
    @synchronize
    if lane == 1
        maximum_raw = @inbounds scratch[1]
        if !(isfinite(maximum_raw) && maximum_raw > zero(maximum_raw))
            _record_exchange_device_failure!(
                status, failing_index, ExchangeInvalidCalibration, 0)
        elseif @inbounds(status[1] == UInt32(ExchangeSucceeded))
            calibrated = numerator / maximum_raw
            if isfinite(calibrated) && calibrated > zero(calibrated)
                @inbounds begin
                    value[1] = calibrated
                    initialized[1] = UInt8(1)
                end
            else
                _record_exchange_device_failure!(
                    status, failing_index, ExchangeInvalidCalibration, 0)
            end
        end
    end
end

@kernel function _exchange_device_publish_signal!(
        candidate_signal, raw_totals, value, initialized,
        active, cell_types, scope_type, status, failing_index)
    cell = @index(Global, Linear)
    @inbounds if cell <= length(active) && active[cell] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[cell])
        if initialized[1] != UInt8(1)
            _record_exchange_device_failure!(
                status, failing_index,
                ExchangeUninitializedCalibration, 0)
        else
            output = raw_totals[cell] * value[1]
            if isfinite(output) && output >= zero(output)
                candidate_signal[cell] = output
            else
                _record_exchange_device_failure!(
                    status, failing_index,
                    ExchangeInvalidRemoval, cell)
            end
        end
    end
end

@kernel function _exchange_device_reset_signal!(
        candidate_signal, active, cell_types, scope_type)
    cell = @index(Global, Linear)
    @inbounds if cell <= length(active) && active[cell] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[cell])
        candidate_signal[cell] = zero(eltype(candidate_signal))
    end
end

@kernel function _exchange_device_commit_field!(
        field, candidate_field, status)
    site = @index(Global, Linear)
    @inbounds status[1] == UInt32(ExchangeSucceeded) &&
        (field[site] = candidate_field[site])
end

@kernel function _exchange_device_commit_signal!(
        signal, candidate_signal, status)
    cell = @index(Global, Linear)
    @inbounds status[1] == UInt32(ExchangeSucceeded) &&
        (signal[cell] = candidate_signal[cell])
end

@kernel function _exchange_device_commit_epoch!(
        exchange_epoch, field_epoch, status)
    index = @index(Global, Linear)
    @inbounds if index == 1 &&
            status[1] == UInt32(ExchangeSucceeded)
        exchange_epoch[1] += UInt64(1)
        field_epoch[1] += UInt64(1)
    end
end

function _portable_exchange_arrays_match(
        plan::ExecutionPlan, field::EvolvingFieldState,
        runtime::FieldExchangeState, execution::ScientificExecutionState,
        signal)
    arrays = (
        field.values, field.workspace.first, field.workspace.second,
        field.publication_epoch,
        runtime.value, runtime.initialized, runtime.publication_epoch,
        runtime.workspace.raw_totals, runtime.workspace.candidate_signal,
        runtime.workspace.status, runtime.workspace.failing_index,
        execution.core.ownership.tags, execution.core.ownership.ids,
        execution.core.active, execution.core.cell_types,
        execution.trackers.finite_volumes, signal)
    all(array -> isbitstype(eltype(array)), arrays) || return false
    all(array -> isequal(
            KernelAbstractions.get_backend(array), plan.backend), arrays) ||
        return false
    return true
end

"""
Launch the portable fixed-tree immediate exchange without host scalar access or floating atomics.

Failure remains backend-resident. The stable observation/checkpoint boundary is responsible for
synchronizing once and translating a nonzero status into `FieldExchangeFailure`.
"""
function apply_field_exchange!(plan::ExecutionPlan,
        field::EvolvingFieldState, exchange::FieldExchange,
        scientific::CompiledScientificState,
        runtime::FieldExchangeState, mode::FieldExchangeMode,
        target_mcs::Integer)
    sink = only(exchange.sinks)
    sink isa Uptake && sink.output !== nothing || throw(ArgumentError(
        "portable exchange requires one named Uptake output"))
    sink.normalize isa ByCellVolume || throw(ArgumentError(
        "portable exchange requires ByCellVolume normalization"))
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "portable exchange requires MaximumCalibration"))
    T = eltype(field.values)
    T <: AbstractFloat &&
        eltype(runtime.workspace.raw_totals) === T ||
        throw(ArgumentError(
            "portable exchange requires matching floating field and reduction storage"))
    execution = scientific_execution(scientific)
    signal = getproperty(execution.core.properties, sink.output)
    _portable_exchange_arrays_match(
        plan, field, runtime, execution, signal) || throw(ArgumentError(
        "portable exchange storage has a backend or element-type mismatch"))
    size(field.values) == size(execution.core.ownership.tags) ||
        throw(ArgumentError(
            "portable exchange field and ownership shapes differ"))
    length(runtime.workspace.raw_totals) ==
        length(execution.core.active) || throw(ArgumentError(
            "portable exchange cell workspace capacity differs"))
    scope_type = _portable_scope_type(sink.scope)
    site_count = length(field.values)
    cell_count = length(execution.core.active)

    clear = _execution_kernel(plan, _exchange_device_clear_status!, 1)
    launch!(plan, clear,
        runtime.workspace.status, runtime.workspace.failing_index;
        ndrange = 1)
    mode === InactiveExchange && return false

    init_cells = _execution_kernel(
        plan, _exchange_device_initialize_cells!, cell_count)
    launch!(plan, init_cells,
        runtime.workspace.raw_totals,
        runtime.workspace.candidate_signal, signal;
        ndrange = cell_count)
    if mode === ResetExchange
        reset = _execution_kernel(
            plan, _exchange_device_reset_signal!, cell_count)
        launch!(plan, reset,
            runtime.workspace.candidate_signal,
            execution.core.active, execution.core.cell_types, scope_type;
            ndrange = cell_count)
        commit_signal = _execution_kernel(
            plan, _exchange_device_commit_signal!, cell_count)
        launch!(plan, commit_signal,
            signal, runtime.workspace.candidate_signal,
            runtime.workspace.status; ndrange = cell_count)
        commit_epoch = _execution_kernel(
            plan, _exchange_device_commit_epoch!, 1)
        launch!(plan, commit_epoch,
            runtime.publication_epoch, field.publication_epoch,
            runtime.workspace.status; ndrange = 1)
        return true
    end

    mode in (CalibrateExchange, PublishExchange) || throw(ArgumentError(
        "unsupported portable field-exchange mode"))
    init_sites = _execution_kernel(
        plan, _exchange_device_initialize_sites!, site_count)
    launch!(plan, init_sites,
        field.workspace.first, field.workspace.second, field.values;
        ndrange = site_count)
    reduction_width = _portable_reduction_width(plan)
    reduction_width_value = Val(reduction_width)
    reduce_cells = _fixed_execution_kernel(
        plan, _exchange_device_reduce_cells!)
    launch!(plan, reduce_cells,
        field.workspace.first, field.workspace.second,
        runtime.workspace.raw_totals,
        field.values, execution.core.ownership.tags,
        execution.core.ownership.ids, execution.core.active,
        execution.core.cell_types, execution.trackers.finite_volumes,
        scope_type, T(sink.maximum), T(sink.relative_rate),
        runtime.workspace.status, runtime.workspace.failing_index,
        reduction_width_value;
        ndrange = cell_count * reduction_width,
        workgroupsize = reduction_width)
    if mode === CalibrateExchange
        calibrate = _fixed_execution_kernel(
            plan, _exchange_device_calibrate_maximum!)
        launch!(plan, calibrate,
            runtime.value, runtime.initialized,
            runtime.workspace.raw_totals, execution.core.active,
            execution.core.cell_types, scope_type,
            T(exchange.calibration.numerator),
            runtime.workspace.status, runtime.workspace.failing_index,
            reduction_width_value;
            ndrange = reduction_width,
            workgroupsize = reduction_width)
    else
        publish = _execution_kernel(
            plan, _exchange_device_publish_signal!, cell_count)
        launch!(plan, publish,
            runtime.workspace.candidate_signal,
            runtime.workspace.raw_totals,
            runtime.value, runtime.initialized,
            execution.core.active, execution.core.cell_types,
            scope_type, runtime.workspace.status,
            runtime.workspace.failing_index;
            ndrange = cell_count)
    end
    commit_field = _execution_kernel(
        plan, _exchange_device_commit_field!, site_count)
    launch!(plan, commit_field,
        field.values, field.workspace.first,
        runtime.workspace.status; ndrange = site_count)
    if mode === PublishExchange
        commit_signal = _execution_kernel(
            plan, _exchange_device_commit_signal!, cell_count)
        launch!(plan, commit_signal,
            signal, runtime.workspace.candidate_signal,
            runtime.workspace.status; ndrange = cell_count)
    end
    commit_epoch = _execution_kernel(
        plan, _exchange_device_commit_epoch!, 1)
    launch!(plan, commit_epoch,
        runtime.publication_epoch, field.publication_epoch,
        runtime.workspace.status; ndrange = 1)
    return true
end

function synchronize_field_exchange_status!(
        plan::ExecutionPlan, runtime::FieldExchangeState)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, runtime.workspace.status))
    status == UInt32(ExchangeSucceeded) && return runtime
    failing = only(Adapt.adapt(Array, runtime.workspace.failing_index))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(FieldExchangeFailure(
        FieldExchangeFailureCode(status), failing))
end

@inline function _record_field_device_failure!(
        status, failing_index, index)
    Atomix.@atomic max(status[1], UInt32(1))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@kernel function _field_device_clear_status!(status, failing_index)
    index = @index(Global, Linear)
    @inbounds if index == 1
        status[1] = UInt32(0)
        failing_index[1] = typemax(UInt32)
    end
end

@kernel function _periodic_field_device_substep!(
        output, input, forcing, owner_tags,
        law, spacing, dt, reset_medium, reset_value,
        status, failing_index)
    site = @index(Global, Linear)
    rows = size(input, 1)
    row = mod(site - 1, rows) + 1
    column = div(site - 1, rows) + 1
    candidate = _periodic_reaction_diffusion_value(
        input, forcing, law, spacing, dt, row, column)
    if reset_medium && @inbounds(owner_tags[site] == _MEDIUM_OWNER_TAG)
        candidate = reset_value
    end
    if isfinite(candidate)
        @inbounds output[site] = candidate
    else
        _record_field_device_failure!(
            status, failing_index, site)
    end
end

@kernel function _field_device_commit!(
        values, candidate, status)
    site = @index(Global, Linear)
    @inbounds status[1] == UInt32(0) &&
        (values[site] = candidate[site])
end

@kernel function _field_device_commit_epoch!(epoch, status)
    index = @index(Global, Linear)
    @inbounds if index == 1 && status[1] == UInt32(0)
        epoch[1] += UInt64(1)
    end
end

function _portable_field_constraint(
        constraints::Tuple, ::Type{T}) where {T}
    isempty(constraints) && return (false, zero(T))
    length(constraints) == 1 || throw(ArgumentError(
        "portable field advance currently admits one post-substep constraint"))
    constraint = only(constraints)
    constraint isa ConstantConcentration &&
        constraint.scope === :medium || throw(ArgumentError(
        "portable field advance requires a :medium ConstantConcentration"))
    return (true, convert(T, constraint.value))
end

function _portable_field_arrays_match(plan, state, ownership)
    arrays = (
        state.values, state.forcing,
        state.workspace.first, state.workspace.second,
        state.workspace.status, state.workspace.failing_index,
        state.publication_epoch, ownership.tags, ownership.ids)
    all(array -> isbitstype(eltype(array)), arrays) || return false
    return all(array -> isequal(
        KernelAbstractions.get_backend(array), plan.backend), arrays)
end

"""
Launch a descriptor-free periodic fixed-step field advance with conditional publication.

The host semantic time and diagnostics are finalized only by
`synchronize_field_advance_status!` at the stable boundary.
"""
function advance_field!(plan::ExecutionPlan,
        state::EvolvingFieldState, dynamics::FieldDynamics,
        interval, ownership::CompiledOwnership)
    dynamics.field === state.name || throw(ArgumentError(
        "portable field dynamics targets a different field"))
    state.values isa AbstractMatrix || throw(ArgumentError(
        "portable field advance currently requires a logical matrix"))
    state.boundary isa PeriodicFieldBoundary || throw(ArgumentError(
        "portable field advance currently requires periodic boundaries"))
    law = dynamics.law
    law isa ReactionDiffusion && law.reaction === nothing ||
        throw(ArgumentError(
            "portable field advance requires reaction-free ReactionDiffusion"))
    eltype(state.values) <: AbstractFloat || throw(ArgumentError(
        "portable field advance requires floating field storage"))
    count, dt = _materialize_substeps(dynamics.method, interval)
    _validate_transient_field_profile(state, law, count, dt)
    size(state.values) == size(ownership.tags) ||
        throw(ArgumentError(
            "portable field and ownership shapes differ"))
    _portable_field_arrays_match(plan, state, ownership) ||
        throw(ArgumentError(
            "portable field storage has a backend mismatch"))
    reset_medium, reset_value = _portable_field_constraint(
        dynamics.post_substep, eltype(state.values))
    site_count = length(state.values)
    clear = _execution_kernel(
        plan, _field_device_clear_status!, 1)
    launch!(plan, clear,
        state.workspace.status, state.workspace.failing_index;
        ndrange = 1)
    input = state.values
    output = state.workspace.first
    for step in 1:count
        substep = _execution_kernel(
            plan, _periodic_field_device_substep!, site_count)
        launch!(plan, substep,
            output, input, state.forcing, ownership.tags,
            law, state.spacing, dt, reset_medium, reset_value,
            state.workspace.status, state.workspace.failing_index;
            ndrange = site_count)
        input = output
        output = isodd(step) ?
            state.workspace.second : state.workspace.first
    end
    commit = _execution_kernel(
        plan, _field_device_commit!, site_count)
    launch!(plan, commit,
        state.values, input, state.workspace.status;
        ndrange = site_count)
    epoch = _execution_kernel(
        plan, _field_device_commit_epoch!, 1)
    launch!(plan, epoch,
        state.publication_epoch, state.workspace.status;
        ndrange = 1)
    return state
end

function synchronize_field_advance_status!(
        plan::ExecutionPlan, state::EvolvingFieldState,
        dynamics::FieldDynamics, interval)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, state.workspace.status))
    if !iszero(status)
        failing = only(Adapt.adapt(Array, state.workspace.failing_index))
        failing == typemax(UInt32) && (failing = UInt32(0))
        throw(ArgumentError(
            "portable field advance failed at canonical index $failing"))
    end
    count, dt = _materialize_substeps(dynamics.method, interval)
    state.time += interval
    state.diagnostics = FieldAdvanceDiagnostics(
        count, dt, state.time, zero(dt), zero(dt), 0, true, :transient)
    return state
end

function apply_field_exchange!(field::EvolvingFieldState,
        exchange::FieldExchange, ownership::LogicalPottsState)
    size(field.values) == lattice_size(ownership) || throw(ArgumentError(
        "initial field-exchange reference requires field and Potts lattice alignment"))
    forcing = zeros(eltype(field.values), size(field.values))
    owners = lattice_storage(ownership)
    for source in exchange.sources
        source isa ConstantConcentration || throw(ArgumentError(
            "unsupported field source in stable CPU reference"))
        for index in eachindex(owners)
            _scope_matches(source.scope, owners[index], ownership) || continue
            @inbounds forcing[index] += source.value - field.values[index]
        end
    end
    for sink in exchange.sinks
        sink isa Uptake || throw(ArgumentError(
            "unsupported field sink in stable CPU reference"))
        for index in eachindex(owners)
            _scope_matches(sink.scope, owners[index], ownership) || continue
            available = max(zero(eltype(field.values)), @inbounds field.values[index])
            removal = min(sink.maximum, sink.relative_rate * available)
            @inbounds forcing[index] -= removal
        end
    end
    copyto!(field.forcing, forcing)
    return field
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, exchange::FieldExchange, target_mcs, stage, interval)
    source = _state_by_name(snapshot.fields, exchange.field)
    target = _state_by_name(candidate.fields, exchange.field)
    _publish_state!(target, source)
    apply_field_exchange!(target, exchange, potts_snapshot)
    return nothing
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::FieldExchange, target_mcs, stage,
        schedule::PlanModeSchedule)
    output = execute_field_exchange!(
        candidate, snapshot, potts_candidate, potts_snapshot,
        process, schedule, target_mcs)
    return (output,)
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::AffineCellAdvance, target_mcs, stage, interval)
    return execute_affine_cell_process!(
        candidate, snapshot, potts_candidate, process)
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::FieldDynamics,
        target_mcs, stage, interval)
    field = _state_by_name(
        integrator.state.fields, process.field)
    amount = _field_interval_amount(process, interval)
    ownership = scientific_execution(
        integrator.potts.state).core.ownership
    advance_field!(
        integrator.potts.plan, field, process,
        amount, ownership)
    synchronize_field_advance_status!(
        integrator.potts.plan, field, process, amount)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::FieldExchange,
        target_mcs, stage,
        schedule::PlanModeSchedule)
    process.calibration isa MaximumCalibration ||
        throw(ArgumentError(
            "portable scheduled exchange requires MaximumCalibration"))
    field = _state_by_name(
        integrator.state.fields, process.field)
    runtime = _state_by_name(
        integrator.state.globals,
        process.calibration.state)
    runtime isa FieldExchangeState || throw(ArgumentError(
        "portable scheduled exchange runtime is not realized"))
    apply_field_exchange!(
        integrator.potts.plan, field, process,
        integrator.potts.state, runtime,
        mode_at(schedule, target_mcs), target_mcs)
    synchronize_field_exchange_status!(
        integrator.potts.plan, runtime)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::AffineCellAdvance,
        target_mcs, stage, interval)
    runtime = _state_by_name(
        integrator.state.globals, process.name)
    runtime isa AffineCellRuntime || throw(ArgumentError(
        "portable affine-cell runtime is not realized"))
    apply_affine_cell_advance!(
        integrator.potts.plan, integrator.potts.state,
        process, runtime.workspace)
    synchronize_affine_cell_status!(
        integrator.potts.plan, runtime.workspace)
    return ()
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::CellDynamics, target_mcs, stage, interval)
    execute_cell_dynamics!(
        potts_candidate, potts_snapshot, process,
        target_mcs, interval)
    return Tuple(variable.property for variable in process.system.state)
end
