struct ProcessClock
    id::String
    last_committed::LogicalTime
    next_due::LogicalTime
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
end

function initialize_runtime(composite::CompiledComposite)
    origin = logical_time(composite.initial)
    process_clocks = tuple((ProcessClock(
        declaration.id,
        origin,
        origin + declaration.schedule.first_due,
        deepcopy(declaration.continuation),
    ) for declaration in composite.declaration.processes)...)
    step_clocks = tuple((StepClock(
        declaration.id,
        deepcopy(declaration.continuation),
    ) for declaration in composite.declaration.steps)...)
    SerialRuntime(composite, deepcopy(composite.initial), process_clocks, step_clocks,
        0x0000000000000000, true)
end

current_snapshot(runtime::SerialRuntime) = runtime.snapshot
settled(runtime::SerialRuntime) = runtime.is_settled
event_count(runtime::SerialRuntime) = runtime.events

_binding(composite::StaticComposite, owner::String, port::Symbol) =
    only(binding for binding in composite.bindings
        if binding.owner == owner && binding.port == port)

function _views(
    compiled::CompiledComposite,
    declaration,
    snapshot::CommittedSnapshot,
)
    input_values = Pair{Symbol,Any}[]
    output_values = Pair{Symbol,Any}[]
    for port in ports(declaration.law)
        binding = _binding(compiled.declaration, declaration.id, port.name)
        if port.direction === :input
            push!(input_values, port.name => snapshot[binding.target])
        else
            leaf = schema_at(snapshot.schema, binding.target)
            push!(output_values, port.name => (binding.target, leaf))
        end
    end
    sort!(input_values; by=first)
    sort!(output_values; by=first)
    PortView(snapshot.version, snapshot_fingerprint(snapshot), tuple(input_values...)),
        tuple(output_values...)
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
            _fail(:wrong_event_identity, "invocation result uses another event identity";
                owner=context.owner, expected=context.event_id, actual=effect.event_id)
    end
    result
end

function _invoke_declaration(
    compiled::CompiledComposite,
    declaration,
    snapshot::CommittedSnapshot,
    start_time::LogicalTime,
    end_time::LogicalTime,
    continuation,
    event_id::String,
)
    view, outputs = _views(compiled, declaration, snapshot)
    context = InvocationContext(
        declaration.id,
        event_id,
        start_time,
        end_time,
        end_time - start_time,
        deepcopy(continuation),
        outputs,
    )
    result = invoke(declaration.law, view, context)
    _validate_result(result, context)
end

function _runtime_failure(error, stage::Symbol, time::LogicalTime, owner, snapshot)
    error isa ProcessBigraphError && error.code === :runtime_event_failed && return error
    cause_code = error isa ProcessBigraphError ? error.code : :unhandled_exception
    ProcessBigraphError(:runtime_event_failed,
        "serial event failed without publishing partial state";
        stage,
        time_tick=time.tick,
        owner,
        last_settled_snapshot=snapshot_fingerprint(snapshot),
        cause_code,
        cause=error isa ProcessBigraphError ? error.message : sprint(showerror, error))
end

function _run_steps(
    runtime::SerialRuntime,
    base::CommittedSnapshot,
    step_clocks::Tuple,
    time::LogicalTime,
    event_id::String,
)
    candidate = base
    clocks = collect(step_clocks)
    declarations = Dict(step.id => step for step in runtime.composite.declaration.steps)
    clock_positions = Dict(clock.id => index for (index, clock) in enumerate(clocks))
    for (layer_index, layer) in enumerate(runtime.composite.layers)
        common = candidate
        layer_effects = Delta[]
        updates = Pair{Int,Any}[]
        for id in layer
            declaration = declarations[id]
            position = clock_positions[id]
            clock = clocks[position]
            step_event = string(event_id, "/step/", layer_index, "/", id)
            result = try
                _invoke_declaration(runtime.composite, declaration, common, time, time,
                    clock.continuation, step_event)
            catch error
                throw(_runtime_failure(error, :step_invoke, time, id, runtime.snapshot))
            end
            append!(layer_effects, result.deltas)
            push!(updates, position => result.continuation)
        end
        candidate = try
            reconcile(common, layer_effects, time)
        catch error
            throw(_runtime_failure(error, :step_reconcile, time, join(layer, ","),
                runtime.snapshot))
        end
        for (position, continuation) in updates
            old = clocks[position]
            clocks[position] = StepClock(old.id, deepcopy(continuation))
        end
    end
    candidate, tuple(clocks...)
end

function _run_process_batch(
    runtime::SerialRuntime,
    due_positions::Vector{Int},
    time::LogicalTime;
    partial::Bool,
)
    common = runtime.snapshot
    clocks = collect(runtime.process_clocks)
    declarations = runtime.composite.declaration.processes
    effects = Delta[]
    continuations = Pair{Int,Any}[]
    event_ordinal = Base.Checked.checked_add(runtime.events, UInt64(1))
    event_id = string("event/", time.tick, "/", event_ordinal)

    sort!(due_positions; by=position -> declarations[position].id)
    for position in due_positions
        declaration = declarations[position]
        clock = clocks[position]
        result = try
            _invoke_declaration(runtime.composite, declaration, common,
                clock.last_committed, time, clock.continuation, event_id)
        catch error
            throw(_runtime_failure(error, :process_invoke, time, declaration.id,
                runtime.snapshot))
        end
        append!(effects, result.deltas)
        push!(continuations, position => result.continuation)
    end

    candidate = try
        reconcile(common, effects, time)
    catch error
        throw(_runtime_failure(error, :process_reconcile, time,
            join((declarations[position].id for position in due_positions), ","),
            runtime.snapshot))
    end

    for (position, continuation) in continuations
        declaration = declarations[position]
        old = clocks[position]
        next_due = partial ? old.next_due : old.next_due + declaration.schedule.cadence
        clocks[position] = ProcessClock(old.id, time, next_due, deepcopy(continuation))
    end

    candidate, next_steps = _run_steps(
        runtime, candidate, runtime.step_clocks, time, event_id)
    runtime.snapshot = candidate
    runtime.process_clocks = tuple(clocks...)
    runtime.step_clocks = next_steps
    runtime.events = event_ordinal
    nothing
end

function _requires_partial(clock::ProcessClock, schedule::FixedSchedule, target::LogicalTime)
    target.tick <= clock.last_committed.tick && return false
    target.tick < clock.next_due.tick && return true
    mod(target.tick - clock.next_due.tick, schedule.cadence.tick) != 0
end

function _preflight_horizon(runtime::SerialRuntime, target::LogicalTime, policy::Symbol)
    policy in (:exact, :stop_prior) ||
        _fail(:unknown_horizon_policy, "horizon policy must be exact or stop_prior"; policy)
    policy === :stop_prior && return
    for (clock, declaration) in zip(runtime.process_clocks,
        runtime.composite.declaration.processes)
        _requires_partial(clock, declaration.schedule, target) || continue
        declaration.schedule.supports_partial ||
            _fail(:partial_interval_unsupported,
                "exact horizon requires a partial interval this process rejects";
                process=declaration.id, target=target.tick,
                last=clock.last_committed.tick, next_due=clock.next_due.tick)
    end
end

"""
Advance the bounded PB0 serial foundation using imminent-event batches.

This is the semantic microfixture runner, not a Phase 15 executor qualification.
At each event all due processes read one common snapshot; publication occurs
only after deterministic reconciliation and all zero-time step layers succeed.
"""
function run_until!(
    runtime::SerialRuntime,
    target::LogicalTime;
    horizon_policy::Symbol=:exact,
)
    runtime.is_settled ||
        _fail(:runtime_not_settled, "cannot advance an unsettled runtime")
    target.scale == runtime.snapshot.time.scale ||
        _fail(:time_scale_mismatch, "target must use the compiled time scale")
    target.tick >= runtime.snapshot.time.tick ||
        _fail(:time_regression, "target cannot precede the current settled boundary")
    _preflight_horizon(runtime, target, horizon_policy)

    runtime.is_settled = false
    try
        while true
            eligible = [clock.next_due.tick for clock in runtime.process_clocks
                if clock.next_due.tick <= target.tick]
            isempty(eligible) && break
            next_tick = minimum(eligible)
            due = [position for (position, clock) in enumerate(runtime.process_clocks)
                if clock.next_due.tick == next_tick]
            _run_process_batch(runtime, due, LogicalTime(next_tick, target.scale);
                partial=false)
        end

        if horizon_policy === :exact
            partial_due = [position for (position, clock) in enumerate(runtime.process_clocks)
                if clock.last_committed.tick < target.tick]
            isempty(partial_due) || _run_process_batch(runtime, partial_due, target;
                partial=true)
            if isempty(runtime.process_clocks) && runtime.snapshot.time.tick < target.tick
                runtime.snapshot = reconcile(runtime.snapshot, Delta[], target)
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
