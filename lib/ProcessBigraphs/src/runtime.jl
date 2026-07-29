struct ProcessClock
    id::String
    last_committed::LogicalTime
    next_due::Union{Nothing,LogicalTime}
    continuation::Any
end

struct StepClock
    id::String
    continuation::Any
end

mutable struct SerialRuntime
    composite::CompiledComposite
    snapshot::CommittedSnapshot
    process_clocks::Tuple{Vararg{ProcessClock}}
    step_clocks::Tuple{Vararg{StepClock}}
    events::UInt64
    is_settled::Bool
    executor::SerialExecutor
    input_cursors::Tuple{Vararg{ProcessInputCursor}}
    observer_clocks::Tuple{Vararg{ObserverClock}}
    trace::Vector{EventRecord}
    records::Vector{ObservationRecord}
    diagnostic::Union{Nothing,RuntimeDiagnostic}
end

initialize_runtime(composite::CompiledComposite) =
    initialize_runtime(composite,
        SerialExecutor(qualification=:legacy_compatibility))

function initialize_runtime(
    composite::CompiledComposite,
    executor::SerialExecutor,
)
    _validate_executor(executor, composite)
    origin = logical_time(composite.initial)
    process_clocks = tuple((ProcessClock(
        entry.declaration.id,
        origin,
        origin + entry.declaration.schedule.first_due,
        deepcopy(entry.declaration.continuation),
    ) for entry in composite.plan.processes)...)
    step_clocks = tuple((StepClock(
        entry.declaration.id,
        deepcopy(entry.declaration.continuation),
    ) for entry in composite.plan.steps)...)
    input_cursors = tuple((ProcessInputCursor(
        entry.declaration.id,
        origin,
        tuple((name => composite.initial[target]
            for (name, target) in entry.inputs)...),
        (origin => tuple((name => composite.initial[target]
            for (name, target) in entry.inputs)...),),
    ) for entry in composite.plan.processes)...)
    observer_clocks = tuple((ObserverClock(
        observer.id,
        _initial_observer_deadline(observer.schedule, origin),
        deepcopy(observer.continuation),
        0x0000000000000000,
    ) for observer in executor.observation_plan.observers)...)
    SerialRuntime(
        composite,
        deepcopy(composite.initial),
        process_clocks,
        step_clocks,
        0x0000000000000000,
        true,
        executor,
        input_cursors,
        observer_clocks,
        EventRecord[],
        ObservationRecord[],
        nothing,
    )
end

current_snapshot(runtime::SerialRuntime) = runtime.snapshot
settled(runtime::SerialRuntime) = runtime.is_settled
event_count(runtime::SerialRuntime) = runtime.events
event_trace(runtime::SerialRuntime) = tuple(deepcopy(runtime.trace)...)
observation_records(runtime::SerialRuntime) = tuple(deepcopy(runtime.records)...)
last_diagnostic(runtime::SerialRuntime) = deepcopy(runtime.diagnostic)

function _views(
    entry::Union{ProcessPlanEntry,StepPlanEntry},
    snapshot::CommittedSnapshot,
    cursor::ProcessInputCursor,
    start_time::LogicalTime,
    end_time::LogicalTime,
)
    input_values = Pair{Symbol,Any}[]
    output_values = Pair{Symbol,Any}[]
    interval_values = Pair{Symbol,AbstractIntervalInput}[]
    portmap = Dict(port.name => port for port in ports(entry.declaration.law))
    for (name, target) in entry.inputs
        push!(input_values, name => snapshot[target])
        start_position = findfirst(pair -> first(pair) == name,
            cursor.start_values)
        isnothing(start_position) &&
            _fail(:missing_input_cursor,
                "process input cursor omits a declared port";
                owner=entry.declaration.id, port=name)
        start_value = last(cursor.start_values[start_position])
        end_value = snapshot[target]
        timeline = Pair{LogicalTime,Any}[]
        for sample in cursor.samples
            values = last(sample)
            position = findfirst(pair -> first(pair) == name, values)
            isnothing(position) || push!(timeline,
                first(sample) => last(values[position]))
        end
        if isempty(timeline) ||
                canonical_fingerprint(last(last(timeline))) !=
                    canonical_fingerprint(end_value)
            push!(timeline, end_time => end_value)
        elseif first(last(timeline)) == end_time
            timeline[end] = end_time => end_value
        end
        behavior = portmap[name].interval_behavior
        interval = if behavior === :frozen
            FrozenInput(start_time, end_time, deepcopy(start_value))
        elseif behavior === :interpolated
            InterpolatedInput(start_time, end_time,
                deepcopy(start_value), deepcopy(end_value))
        elseif behavior === :event_updated
            EventUpdatedInput(start_time, end_time,
                tuple((sample for sample in timeline
                    if first(sample) > start_time)...))
        elseif behavior === :continuously_callable
            ContinuouslyCallableInput(start_time, end_time,
                tuple(timeline...))
        else
            _fail(:invalid_interval_behavior,
                "compiled port has an unknown interval-input behavior";
                owner=entry.declaration.id, port=name, behavior)
        end
        push!(interval_values, name => interval)
    end
    for (name, target) in entry.outputs
        leaf = schema_at(snapshot.schema, target)
        push!(output_values, name => (target, leaf))
    end
    sort!(input_values; by=first)
    sort!(output_values; by=first)
    PortView(snapshot.version, snapshot_fingerprint(snapshot),
        tuple(input_values...), tuple(interval_values...)),
        tuple(output_values...)
end

function _instantaneous_cursor(
    entry::Union{ProcessPlanEntry,StepPlanEntry},
    snapshot::CommittedSnapshot,
    time::LogicalTime,
)
    values = tuple((name => snapshot[target] for (name, target) in entry.inputs)...)
    ProcessInputCursor(entry.declaration.id, time, values, (time => values,))
end

function _validate_result(result, context::InvocationContext)
    result isa InvocationResult ||
        _fail(:invalid_invocation_result, "invoke must return InvocationResult";
            owner=context.owner, actual=string(typeof(result)))
    for effect in result.deltas
        effect.producer == context.owner ||
            _fail(:forged_producer_identity,
                "invocation result uses another producer identity";
                owner=context.owner, producer=effect.producer)
        effect.event_id == context.event_id ||
            _fail(:wrong_event_identity,
                "invocation result uses another event identity";
                owner=context.owner, expected=context.event_id,
                actual=effect.event_id)
    end
    canonical_bytes(result.diagnostics)
    result
end

function _invoke_declaration(
    runtime::SerialRuntime,
    entry::Union{ProcessPlanEntry,StepPlanEntry},
    snapshot::CommittedSnapshot,
    start_time::LogicalTime,
    end_time::LogicalTime,
    continuation,
    event_id::String,
    namespace::Symbol,
    injection_stage::Symbol,
    cursor::ProcessInputCursor,
)
    declaration = entry.declaration
    _inject_failure(runtime.executor.failure_injection, injection_stage,
        declaration.id)
    view, outputs = _views(entry, snapshot, cursor, start_time, end_time)
    namespace === :model ||
        _fail(:invalid_process_rng_namespace,
            "process and step invocations require model RNG context")
    rng = ModelRNGContext(
        model_fingerprint(runtime.composite),
        runtime.executor.root_seed,
        declaration.id,
        end_time,
        event_id,
    )
    context = InvocationContext(
        declaration.id,
        event_id,
        start_time,
        end_time,
        end_time - start_time,
        deepcopy(continuation),
        outputs,
        rng,
    )
    result = invoke(declaration.law, view, context)
    _inject_failure(runtime.executor.failure_injection,
        :invocation_result_validation, declaration.id)
    _validate_result(result, context)
end

function _diagnostic_stage(stage::Symbol)
    stage === :process_invoke && return :process_invocation
    stage === :step_invoke && return :reactive_step_execution
    stage === :process_reconcile && return :reconciliation
    stage === :step_reconcile && return :reconciliation
    stage
end

function _runtime_failure(
    error,
    stage::Symbol,
    time::LogicalTime,
    owner,
    event_id::AbstractString,
    snapshot::CommittedSnapshot,
)
    error isa ProcessBigraphError && error.code === :runtime_event_failed &&
        return error
    cause_code = error isa ProcessBigraphError ? error.code : :unhandled_exception
    semantic_stage = _diagnostic_stage(stage)
    diagnostic = RuntimeDiagnostic(
        FAILURE_SCHEMA_VERSION,
        :runtime_event_failed,
        semantic_stage,
        String(owner),
        time,
        String(event_id),
        snapshot_fingerprint(snapshot),
        cause_code,
        :explicit_retry_from_stable_boundary,
    )
    ProcessBigraphError(
        :runtime_event_failed,
        "serial event failed without publishing partial state";
        stage,
        semantic_stage,
        time_tick=time.tick,
        owner=String(owner),
        event_id=String(event_id),
        last_settled_snapshot=snapshot_fingerprint(snapshot),
        cause_code,
        retry_classification=:explicit_retry_from_stable_boundary,
        diagnostic,
        cause=error isa ProcessBigraphError ? error.message : sprint(showerror, error),
    )
end

function _record_failure!(runtime::SerialRuntime, error)
    if error isa ProcessBigraphError && error.code === :runtime_event_failed &&
            hasproperty(error.context, :diagnostic)
        runtime.diagnostic = error.context.diagnostic
    end
    error
end

function _changed_paths(
    before::CommittedSnapshot,
    after::CommittedSnapshot,
)
    Set(target for target in paths(before)
        if canonical_fingerprint(before[target]) !=
            canonical_fingerprint(after[target]))
end

function _step_maps(runtime::SerialRuntime, clocks)
    entries = Dict(entry.declaration.id => entry
        for entry in runtime.composite.plan.steps)
    positions = Dict(clock.id => index for (index, clock) in enumerate(clocks))
    entries, positions
end

function _validate_continuation_result(
    runtime::SerialRuntime,
    declaration,
    value,
)
    _inject_failure(runtime.executor.failure_injection,
        :continuation_validation, declaration.id)
    spec = _continuation_spec(runtime.executor, declaration)
    validate_continuation(spec, declaration.id, value)
    value
end

function _invoke_step(
    runtime::SerialRuntime,
    entry::StepPlanEntry,
    snapshot::CommittedSnapshot,
    clock::StepClock,
    time::LogicalTime,
    event_id::String,
)
    result = _invoke_declaration(
        runtime,
        entry,
        snapshot,
        time,
        time,
        clock.continuation,
        event_id,
        :model,
        :reactive_step_execution,
        _instantaneous_cursor(entry, snapshot, time),
    )
    _validate_continuation_result(runtime, entry.declaration,
        result.continuation)
    isnothing(result.next_deadline) ||
        _fail(:step_proposed_deadline,
            "reactive steps cannot propose temporal deadlines";
            step=entry.declaration.id)
    result
end

function _reconcile_candidate(
    runtime::SerialRuntime,
    snapshot::CommittedSnapshot,
    effects,
    time::LogicalTime,
    owner::AbstractString,
)
    _inject_failure(runtime.executor.failure_injection, :reconciliation, owner)
    runtime.executor.qualification === :strict ?
        _reconcile_unpublished(snapshot, effects, time) :
        reconcile(snapshot, effects, time)
end

function _run_reactive(
    runtime::SerialRuntime,
    base::CommittedSnapshot,
    step_clocks::Tuple,
    time::LogicalTime,
    event_id::String,
    initial_changed::Set{Path},
)
    candidate = base
    clocks = collect(step_clocks)
    entries, positions = _step_maps(runtime, clocks)
    iterative_steps = Set(step for region in runtime.composite.plan.iterations
        for step in region.steps)
    changed = copy(initial_changed)
    activations = ActivationRecord[]
    activation_count = 0

    for (layer_index, layer) in enumerate(runtime.composite.plan.layers)
        active = String[]
        for id in layer
            id in iterative_steps && continue
            entry = entries[id]
            input_paths = Set(last.(entry.inputs))
            if !isempty(initial_changed) &&
                    (isempty(input_paths) || !isempty(intersect(input_paths, changed)))
                push!(active, id)
            end
        end
        isempty(active) && continue
        common = candidate
        effects = Delta[]
        updates = Pair{Int,Any}[]
        for id in sort!(active)
            activation_count += 1
            activation_count <= runtime.executor.activation_bound ||
                _fail(:reactive_activation_bound,
                    "reactive activation bound was exhausted";
                    bound=runtime.executor.activation_bound)
            entry = entries[id]
            position = positions[id]
            step_event = string(event_id, "/step/", layer_index, "/", id)
            result = _invoke_step(runtime, entry, common, clocks[position],
                time, step_event)
            append!(effects, result.deltas)
            push!(updates, position => result.continuation)
        end
        next_candidate = _reconcile_candidate(runtime, common, effects, time,
            join(active, ","))
        new_changed = _changed_paths(common, next_candidate)
        for id in sort!(active)
            entry = entries[id]
            input_fp = canonical_fingerprint(tuple(
                (target => common[target] for (_, target) in entry.inputs)...))
            output_fp = canonical_fingerprint(tuple(
                (target => next_candidate[target] for (_, target) in entry.outputs)...))
            push!(activations, ActivationRecord(
                id, :reactive, layer_index, 0, input_fp, output_fp))
        end
        for (position, continuation) in updates
            old = clocks[position]
            clocks[position] = StepClock(old.id, deepcopy(continuation))
        end
        candidate = next_candidate
        union!(changed, new_changed)
    end

    outcomes = IterationOutcome[]
    for region in runtime.composite.plan.iterations
        iterations = 0
        converged = false
        region_fp = ""
        for iteration in 1:region.max_iterations
            iterations = iteration
        before_watch = canonical_fingerprint(tuple(
            (target => candidate[target] for target in region.watch_paths)...))
            for id in region.steps
                activation_count += 1
                activation_count <= runtime.executor.activation_bound ||
                    _fail(:reactive_activation_bound,
                        "reactive activation bound was exhausted";
                        bound=runtime.executor.activation_bound)
                entry = entries[id]
                position = positions[id]
                common = candidate
                step_event = string(event_id, "/iteration/", region.id, "/",
                    iteration, "/", id)
                result = _invoke_step(runtime, entry, common, clocks[position],
                    time, step_event)
                candidate = _reconcile_candidate(runtime, common,
                    collect(result.deltas), time, id)
                clocks[position] = StepClock(id, deepcopy(result.continuation))
                push!(activations, ActivationRecord(
                    id,
                    :iteration,
                    0,
                    iteration,
                    snapshot_fingerprint(common),
                    snapshot_fingerprint(candidate),
                ))
            end
        after_watch = canonical_fingerprint(tuple(
            (target => candidate[target] for target in region.watch_paths)...))
            region_fp = after_watch
            if region.mode === :convergent && before_watch == after_watch
                converged = true
                break
            end
        end
        if region.mode === :convergent && !converged
            _fail(:iteration_nonconvergence,
                "iterative region exhausted its deterministic convergence bound";
                region=region.id, bound=region.max_iterations,
                fingerprint=region_fp)
        end
        push!(outcomes, IterationOutcome(
            region.id,
            iterations,
            region.mode === :bounded ? false : converged,
            region_fp,
        ))
    end
    candidate, tuple(clocks...), tuple(activations...), tuple(outcomes...)
end

function _next_deadline(
    schedule::FixedSchedule,
    clock::ProcessClock,
    result::InvocationResult,
    time::LogicalTime,
    partial::Bool,
)
    isnothing(result.next_deadline) ||
        _fail(:fixed_schedule_deadline_proposal,
            "fixed schedules cannot accept a proposed deadline";
            process=clock.id)
    partial ? clock.next_due : clock.next_due + schedule.cadence
end

function _next_deadline(
    schedule::AdaptiveSchedule,
    clock::ProcessClock,
    result::InvocationResult,
    time::LogicalTime,
    partial::Bool,
)
    deadline = result.next_deadline
    isnothing(deadline) &&
        _fail(:missing_adaptive_deadline,
            "adaptive process must propose its next deadline";
            process=clock.id)
    deadline.scale == time.scale ||
        _fail(:time_scale_mismatch,
            "adaptive deadline uses another time scale";
            process=clock.id)
    deadline.tick > time.tick ||
        _fail(:nonfuture_adaptive_deadline,
            "adaptive deadline must be strictly future";
            process=clock.id, current=time.tick, proposed=deadline.tick)
    deadline
end

function _next_deadline(
    ::OneShotSchedule,
    clock::ProcessClock,
    result::InvocationResult,
    time::LogicalTime,
    partial::Bool,
)
    partial &&
        _fail(:one_shot_partial_invocation,
            "one-shot processes run only at their authored exact boundary";
            process=clock.id)
    isnothing(result.next_deadline) ||
        _fail(:one_shot_deadline_proposal,
            "one-shot processes cannot propose another deadline";
            process=clock.id)
    nothing
end

function _observer_due(
    spec::ObserverSpec,
    clock::ObserverClock,
    time::LogicalTime,
    process_event::Bool,
)
    spec.schedule isa EventObservationSchedule &&
        return process_event
    !isnothing(clock.next_due) && clock.next_due == time
end

function _run_observers(
    runtime::SerialRuntime,
    snapshot::CommittedSnapshot,
    clocks::Tuple,
    time::LogicalTime,
    event_id::String,
    process_event::Bool,
)
    mutable_clocks = collect(clocks)
    records = ObservationRecord[]
    specs = runtime.executor.observation_plan.observers
    for (position, (spec, clock)) in enumerate(zip(specs, mutable_clocks))
        _observer_due(spec, clock, time, process_event) || continue
        projection = project(snapshot, spec.paths...)
        rng = ObserverRNGContext(
            model_fingerprint(runtime.composite),
            runtime.executor.root_seed,
            spec.id,
            time,
            event_id,
        )
        context = ObserverContext(
            spec.id,
            event_id,
            time,
            deepcopy(clock.continuation),
            rng,
        )
        result = try
            _inject_failure(runtime.executor.failure_injection,
                :required_observation, spec.id)
            observe(spec.observer, projection, context)
        catch error
            if spec.required
                rethrow(error)
            end
            error
        end
        next_continuation = clock.continuation
        if result isa Exception
            if spec.optional_failure_policy === :publish_failure_record
                payload = (
                    code=:optional_observer_failure,
                    classification=result isa ProcessBigraphError ?
                        result.code : :unhandled_exception,
                )
                push!(records, ObservationRecord(
                    spec.id,
                    event_id,
                    time,
                    :optional_failure,
                    payload,
                    canonical_fingerprint((
                        :optional_observer_failure_v1, payload)),
                ))
            end
        else
            result isa ObservationResult ||
                _fail(:invalid_observation_result,
                    "observe must return ObservationResult";
                    observer=spec.id, actual=string(typeof(result)))
            validate_record(spec.record_schema, result.record)
            validate_continuation(spec.continuation_spec, spec.id,
                result.continuation)
            next_continuation = result.continuation
            push!(records, ObservationRecord(
                spec.id,
                event_id,
                time,
                :success,
                deepcopy(result.record),
                canonical_fingerprint((
                    spec.record_schema,
                    result.record,
                )),
            ))
        end
        next_due = _next_observer_deadline(spec.schedule, clock)
        mutable_clocks[position] = ObserverClock(
            clock.id,
            next_due,
            deepcopy(next_continuation),
            Base.Checked.checked_add(clock.position, UInt64(1)),
        )
    end
    tuple(mutable_clocks...), tuple(records...)
end

function _candidate_boundary_fingerprint(
    runtime::SerialRuntime,
    snapshot,
    process_clocks,
    step_clocks,
    input_cursors,
    observer_clocks,
    events,
    records,
)
    canonical_fingerprint((
        :serial_event_candidate_v1,
        runtime_fingerprint(runtime.executor, runtime.composite),
        snapshot,
        process_clocks,
        step_clocks,
        input_cursors,
        observer_clocks,
        events,
        records,
    ))
end

function _publish_event!(
    runtime::SerialRuntime,
    candidate::CommittedSnapshot,
    process_clocks,
    step_clocks,
    input_cursors,
    observer_clocks,
    new_records,
    event_record::EventRecord,
)
    runtime.snapshot = candidate
    runtime.process_clocks = process_clocks
    runtime.step_clocks = step_clocks
    runtime.input_cursors = input_cursors
    runtime.observer_clocks = observer_clocks
    runtime.events = event_record.ordinal
    append!(runtime.records, new_records)
    push!(runtime.trace, event_record)
    runtime.diagnostic = nothing
    runtime
end

function _input_values(
    entry::ProcessPlanEntry,
    snapshot::CommittedSnapshot,
)
    tuple((name => snapshot[target] for (name, target) in entry.inputs)...)
end

function _advance_input_cursors(
    runtime::SerialRuntime,
    before::CommittedSnapshot,
    after::CommittedSnapshot,
    due_positions::Vector{Int},
    time::LogicalTime,
)
    cursors = collect(runtime.input_cursors)
    due = Set(due_positions)
    changed = _changed_paths(before, after)
    for (position, entry) in enumerate(runtime.composite.plan.processes)
        values = _input_values(entry, after)
        if position in due
            cursors[position] = ProcessInputCursor(
                entry.declaration.id,
                time,
                values,
                (time => values,),
            )
        elseif !isempty(intersect(Set(last.(entry.inputs)), changed))
            old = cursors[position]
            cursors[position] = ProcessInputCursor(
                old.id,
                old.since,
                old.start_values,
                tuple(old.samples..., time => values),
            )
        end
    end
    tuple(cursors...)
end

function _run_process_batch!(
    runtime::SerialRuntime,
    due_positions::Vector{Int},
    time::LogicalTime;
    partial::Bool,
)
    common = runtime.snapshot
    clocks = collect(runtime.process_clocks)
    entries = runtime.composite.plan.processes
    effects = Delta[]
    results = Pair{Int,InvocationResult}[]
    event_ordinal = try
        Base.Checked.checked_add(runtime.events, UInt64(1))
    catch error
        _fail(:event_ordinal_overflow,
            "event ordinal exceeds UInt64"; current=runtime.events)
    end
    event_id = if runtime.executor.qualification === :strict
        identity = EventIdentity(
            model_fingerprint(runtime.composite),
            execution_plan_fingerprint(runtime.composite),
            time,
            event_ordinal,
        )
        string("event/", identity.fingerprint)
    else
        string("event/", time.tick, "/", event_ordinal)
    end
    sort!(due_positions; by=position -> entries[position].declaration.id)

    try
        for position in due_positions
            entry = entries[position]
            declaration = entry.declaration
            clock = clocks[position]
            result = _invoke_declaration(
                runtime,
                entry,
                common,
                clock.last_committed,
                time,
                clock.continuation,
                event_id,
                :model,
                :process_invocation,
                runtime.input_cursors[position],
            )
            _validate_continuation_result(runtime, declaration,
                result.continuation)
            _next_deadline(declaration.schedule, clock, result, time, partial)
            append!(effects, result.deltas)
            push!(results, position => result)
        end

        candidate = _reconcile_candidate(
            runtime,
            common,
            effects,
            time,
            join((entries[position].declaration.id
                for position in due_positions), ","),
        )

        for (position, result) in results
            declaration = entries[position].declaration
            old = clocks[position]
            clocks[position] = ProcessClock(
                old.id,
                time,
                _next_deadline(declaration.schedule, old, result, time, partial),
                deepcopy(result.continuation),
            )
        end

        process_changed = _changed_paths(common, candidate)
        candidate, next_steps, activations, iterations = _run_reactive(
            runtime,
            candidate,
            runtime.step_clocks,
            time,
            event_id,
            process_changed,
        )
        if runtime.executor.qualification === :strict
            candidate = _committed_snapshot(common, candidate.entries, time)
        end
        next_observers, new_records = _run_observers(
            runtime,
            candidate,
            runtime.observer_clocks,
            time,
            event_id,
            true,
        )
        next_cursors = _advance_input_cursors(
            runtime, common, candidate, due_positions, time)
        _inject_failure(runtime.executor.failure_injection,
            :checkpoint_capture, event_id)
        _candidate_boundary_fingerprint(
            runtime,
            candidate,
            tuple(clocks...),
            next_steps,
            next_cursors,
            next_observers,
            event_ordinal,
            new_records,
        )
        record = EventRecord(
            "process-bigraph-event-v1",
            event_id,
            event_ordinal,
            time,
            tuple((entries[position].declaration.id
                for position in due_positions)...),
            activations,
            iterations,
            snapshot_fingerprint(common),
            snapshot_fingerprint(candidate),
            runtime_fingerprint(runtime.executor, runtime.composite),
        )
        _inject_failure(runtime.executor.failure_injection,
            :record_publication, event_id)
        _publish_event!(
            runtime,
            candidate,
            tuple(clocks...),
            next_steps,
            next_cursors,
            next_observers,
            new_records,
            record,
        )
    catch error
        failed = _runtime_failure(
            error,
            error isa ProcessBigraphError &&
                hasproperty(error.context, :stage) ?
                error.context.stage : :process_invoke,
            time,
            join((entries[position].declaration.id
                for position in due_positions), ","),
            event_id,
            common,
        )
        _record_failure!(runtime, failed)
        throw(failed)
    end
    nothing
end

function _publish_empty_boundary!(
    runtime::SerialRuntime,
    time::LogicalTime,
)
    common = runtime.snapshot
    event_id = string("boundary/", time.tick, "/", runtime.events)
    try
        candidate = time == logical_time(common) ? common :
            reconcile(common, Delta[], time)
        next_observers, new_records = _run_observers(
            runtime,
            candidate,
            runtime.observer_clocks,
            time,
            event_id,
            false,
        )
        _inject_failure(runtime.executor.failure_injection,
            :checkpoint_capture, event_id)
        _candidate_boundary_fingerprint(
            runtime,
            candidate,
            runtime.process_clocks,
            runtime.step_clocks,
            runtime.input_cursors,
            next_observers,
            runtime.events,
            new_records,
        )
        _inject_failure(runtime.executor.failure_injection,
            :record_publication, event_id)
        runtime.snapshot = candidate
        runtime.observer_clocks = next_observers
        append!(runtime.records, new_records)
        runtime.diagnostic = nothing
    catch error
        failed = _runtime_failure(
            error,
            :required_observation,
            time,
            "observation-boundary",
            event_id,
            common,
        )
        _record_failure!(runtime, failed)
        throw(failed)
    end
    runtime
end

function _requires_partial(
    clock::ProcessClock,
    schedule::FixedSchedule,
    target::LogicalTime,
)
    target.tick <= clock.last_committed.tick && return false
    target.tick < clock.next_due.tick && return true
    mod(target.tick - clock.next_due.tick, schedule.cadence.tick) != 0
end

function _requires_partial(
    clock::ProcessClock,
    schedule::AdaptiveSchedule,
    target::LogicalTime,
)
    clock.last_committed.tick < target.tick < clock.next_due.tick
end

_requires_partial(
    ::ProcessClock,
    ::OneShotSchedule,
    ::LogicalTime,
) = false

function _preflight_horizon(
    runtime::SerialRuntime,
    target::LogicalTime,
    policy,
)
    policy = _horizon_symbol(policy)
    policy === :stop_prior && return
    for (clock, entry) in zip(runtime.process_clocks,
        runtime.composite.plan.processes)
        declaration = entry.declaration
        _requires_partial(clock, declaration.schedule, target) || continue
        declaration.schedule.supports_partial ||
            _fail(:partial_interval_unsupported,
                "exact horizon requires a partial interval this process rejects";
                process=declaration.id, target=target.tick,
                last=clock.last_committed.tick, next_due=clock.next_due.tick)
    end
end

function _next_process_tick(runtime::SerialRuntime, target::LogicalTime)
    eligible = Int64[clock.next_due.tick for clock in runtime.process_clocks
        if !isnothing(clock.next_due) && clock.next_due.tick <= target.tick]
    isempty(eligible) ? nothing : minimum(eligible)
end

function _next_observer_tick(runtime::SerialRuntime, target::LogicalTime)
    eligible = Int64[clock.next_due.tick for clock in runtime.observer_clocks
        if !isnothing(clock.next_due) && clock.next_due.tick <= target.tick]
    isempty(eligible) ? nothing : minimum(eligible)
end

"""
Advance the production immutable-topology serial executor to an exact logical
horizon or to the last complete event strictly before it.

All due processes at one time observe a common immutable snapshot. State,
clocks, continuations, semantic event position, required observation records,
and the canonical event record publish as one settled transaction.
"""
function run_until!(
    runtime::SerialRuntime,
    target::LogicalTime;
    horizon_policy=:exact,
)
    runtime.is_settled ||
        _fail(:runtime_not_settled, "cannot advance an unsettled runtime")
    target.scale == runtime.snapshot.time.scale ||
        _fail(:time_scale_mismatch,
            "target must use the compiled time scale")
    target.tick >= runtime.snapshot.time.tick ||
        _fail(:time_regression,
            "target cannot precede the current settled boundary")
    policy = _horizon_symbol(horizon_policy)
    _preflight_horizon(runtime, target, policy)

    runtime.is_settled = false
    try
        while true
            process_tick = _next_process_tick(runtime, target)
            observer_tick = _next_observer_tick(runtime, target)
            isnothing(process_tick) && isnothing(observer_tick) && break
            next_tick = isnothing(process_tick) ? observer_tick :
                isnothing(observer_tick) ? process_tick :
                min(process_tick, observer_tick)
            time = LogicalTime(next_tick, target.scale)
            if !isnothing(process_tick) && process_tick == next_tick
                due = [position for (position, clock) in
                    enumerate(runtime.process_clocks)
                    if !isnothing(clock.next_due) &&
                        clock.next_due.tick == next_tick]
                _run_process_batch!(runtime, due, time; partial=false)
            else
                _publish_empty_boundary!(runtime, time)
            end
        end

        if policy === :exact
            partial_due = [position for (position, (clock, entry)) in
                enumerate(zip(
                    runtime.process_clocks,
                    runtime.composite.plan.processes))
                if _requires_partial(
                    clock, entry.declaration.schedule, target)]
            if !isempty(partial_due)
                _run_process_batch!(runtime, partial_due, target; partial=true)
            elseif runtime.snapshot.time.tick < target.tick
                _publish_empty_boundary!(runtime, target)
            end
        end
        runtime
    finally
        runtime.is_settled = true
    end
end

function _canonical(io::IO, clock::ProcessClock)
    write(io, "PC")
    _canonical(io, clock.id)
    _canonical(io, clock.last_committed)
    _canonical(io, clock.next_due)
    _canonical(io, clock.continuation)
end

function _canonical(io::IO, clock::StepClock)
    write(io, "SC")
    _canonical(io, clock.id)
    _canonical(io, clock.continuation)
end
