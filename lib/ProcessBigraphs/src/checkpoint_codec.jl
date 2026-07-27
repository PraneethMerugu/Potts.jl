const LOGICAL_CHECKPOINT_VERSION = "2.0.0"
const LOGICAL_CHECKPOINT_SCHEMA = "process-bigraph-logical-checkpoint-v2"

struct LogicalCheckpointV2{P}
    format_version::String
    payload::P
    payload_bytes::Vector{UInt8}
    integrity::String
end

function _snapshot_payload(snapshot::CommittedSnapshot)
    (
        version=snapshot.version,
        time=snapshot.time,
        entries=snapshot.entries,
        parent_fingerprint=snapshot.parent_fingerprint,
        topology_fingerprint=snapshot.topology_fingerprint,
    )
end

_process_clock_payload(clock::ProcessClock) = (
    id=clock.id,
    last_committed=clock.last_committed,
    next_due=clock.next_due,
    continuation=clock.continuation,
)

_step_clock_payload(clock::StepClock) = (
    id=clock.id,
    continuation=clock.continuation,
)

_input_cursor_payload(cursor::ProcessInputCursor) = (
    id=cursor.id,
    since=cursor.since,
    start_values=cursor.start_values,
    samples=cursor.samples,
)

_observer_clock_payload(clock::ObserverClock) = (
    id=clock.id,
    next_due=clock.next_due,
    continuation=clock.continuation,
    position=clock.position,
)

_activation_payload(record::ActivationRecord) = (
    owner=record.owner,
    kind=record.kind,
    layer=record.layer,
    iteration=record.iteration,
    input_fingerprint=record.input_fingerprint,
    output_fingerprint=record.output_fingerprint,
)

_iteration_payload(outcome::IterationOutcome) = (
    region=outcome.region,
    iterations=outcome.iterations,
    converged=outcome.converged,
    fingerprint=outcome.fingerprint,
)

_event_payload(record::EventRecord) = (
    schema_version=record.schema_version,
    event_id=record.event_id,
    ordinal=record.ordinal,
    time=record.time,
    due_processes=record.due_processes,
    activations=tuple((_activation_payload(value)
        for value in record.activations)...),
    iterations=tuple((_iteration_payload(value)
        for value in record.iterations)...),
    before_fingerprint=record.before_fingerprint,
    after_fingerprint=record.after_fingerprint,
    runtime_fingerprint=record.runtime_fingerprint,
)

_observation_payload(record::ObservationRecord) = (
    observer=record.observer,
    event_id=record.event_id,
    time=record.time,
    status=record.status,
    payload=record.payload,
    payload_fingerprint=record.payload_fingerprint,
)

function _continuation_specs(
    runtime::SerialRuntime,
)
    process_specs = tuple(((
        entry.declaration.id,
        _continuation_spec(runtime.executor, entry.declaration),
    ) for entry in runtime.composite.plan.processes)...)
    step_specs = tuple(((
        entry.declaration.id,
        _continuation_spec(runtime.executor, entry.declaration),
    ) for entry in runtime.composite.plan.steps)...)
    observer_specs = tuple(((
        observer.id,
        observer.continuation_spec,
    ) for observer in runtime.executor.observation_plan.observers)...)
    (process=process_specs, step=step_specs, observer=observer_specs)
end

function _validate_checkpoint_continuations(runtime::SerialRuntime)
    for (entry, clock) in zip(
        runtime.composite.plan.processes, runtime.process_clocks)
        spec = _continuation_spec(runtime.executor, entry.declaration)
        encode_continuation(spec, clock.continuation)
    end
    for (entry, clock) in zip(
        runtime.composite.plan.steps, runtime.step_clocks)
        spec = _continuation_spec(runtime.executor, entry.declaration)
        encode_continuation(spec, clock.continuation)
    end
    for (observer, clock) in zip(
        runtime.executor.observation_plan.observers,
        runtime.observer_clocks,
    )
        encode_continuation(observer.continuation_spec, clock.continuation)
    end
    true
end

function _logical_checkpoint_payload(runtime::SerialRuntime)
    specs = _continuation_specs(runtime)
    (
        schema=LOGICAL_CHECKPOINT_SCHEMA,
        format_version=LOGICAL_CHECKPOINT_VERSION,
        logical_value_codec=LOGICAL_VALUE_CODEC_VERSION,
        model_fingerprint=model_fingerprint(runtime.composite),
        structural_epoch_version=runtime.composite.epoch.version,
        structural_fingerprint=structural_fingerprint(runtime.composite),
        execution_plan_fingerprint=execution_plan_fingerprint(runtime.composite),
        runtime_fingerprint=runtime_fingerprint(
            runtime.executor, runtime.composite),
        observation_fingerprint=observation_fingerprint(
            runtime.executor.observation_plan),
        continuation_fingerprint=canonical_fingerprint(specs),
        rng_algorithm=SEMANTIC_RNG_ALGORITHM,
        rng_address_schema=SEMANTIC_RNG_ADDRESS_SCHEMA,
        root_seed=runtime.executor.root_seed.words,
        snapshot=_snapshot_payload(runtime.snapshot),
        process_clocks=tuple((_process_clock_payload(clock)
            for clock in runtime.process_clocks)...),
        step_clocks=tuple((_step_clock_payload(clock)
            for clock in runtime.step_clocks)...),
        input_cursors=tuple((_input_cursor_payload(cursor)
            for cursor in runtime.input_cursors)...),
        observer_clocks=tuple((_observer_clock_payload(clock)
            for clock in runtime.observer_clocks)...),
        event_count=runtime.events,
        trace=tuple((_event_payload(record) for record in runtime.trace)...),
        records=tuple((_observation_payload(record)
            for record in runtime.records)...),
    )
end

function logical_checkpoint(runtime::SerialRuntime)
    runtime.is_settled ||
        _fail(:unsettled_checkpoint,
            "logical checkpoints require a settled commit boundary")
    runtime.executor.qualification === :strict ||
        _fail(:logical_checkpoint_requires_strict_executor,
            "v2 logical checkpoints require the strict serial executor")
    _validate_checkpoint_continuations(runtime)
    payload = _logical_checkpoint_payload(runtime)
    payload_bytes = encode_logical_value(payload)
    LogicalCheckpointV2(
        LOGICAL_CHECKPOINT_VERSION,
        payload,
        payload_bytes,
        bytes2hex(sha256(payload_bytes)),
    )
end

function _validate_logical_checkpoint(checkpoint::LogicalCheckpointV2)
    checkpoint.format_version == LOGICAL_CHECKPOINT_VERSION ||
        _fail(:unsupported_checkpoint_version,
            "logical checkpoint format is unsupported";
            version=checkpoint.format_version)
    payload_bytes = encode_logical_value(checkpoint.payload)
    payload_bytes == checkpoint.payload_bytes ||
        _fail(:checkpoint_payload_mismatch,
            "logical checkpoint cached payload bytes do not match its payload")
    integrity = bytes2hex(sha256(payload_bytes))
    integrity == checkpoint.integrity ||
        _fail(:checkpoint_integrity_failure,
            "logical checkpoint integrity hash does not match";
            expected=checkpoint.integrity, actual=integrity)
    true
end

function encode_checkpoint(checkpoint::LogicalCheckpointV2)
    _validate_logical_checkpoint(checkpoint)
    encode_logical_value((
        schema=LOGICAL_CHECKPOINT_SCHEMA,
        format_version=checkpoint.format_version,
        payload=checkpoint.payload,
        integrity=checkpoint.integrity,
    ))
end

function decode_checkpoint(bytes::AbstractVector{UInt8})
    envelope = decode_logical_value(bytes)
    envelope isa NamedTuple &&
        hasproperty(envelope, :schema) &&
        hasproperty(envelope, :format_version) &&
        hasproperty(envelope, :payload) &&
        hasproperty(envelope, :integrity) ||
        _fail(:invalid_checkpoint_envelope,
            "decoded logical checkpoint has an invalid envelope")
    envelope.schema == LOGICAL_CHECKPOINT_SCHEMA ||
        _fail(:unsupported_checkpoint_schema,
            "logical checkpoint schema is unsupported";
            schema=envelope.schema)
    envelope.format_version == LOGICAL_CHECKPOINT_VERSION ||
        _fail(:unsupported_checkpoint_version,
            "logical checkpoint format is unsupported";
            version=envelope.format_version)
    payload_bytes = encode_logical_value(envelope.payload)
    integrity = bytes2hex(sha256(payload_bytes))
    integrity == envelope.integrity ||
        _fail(:checkpoint_integrity_failure,
            "logical checkpoint integrity hash does not match";
            expected=envelope.integrity, actual=integrity)
    LogicalCheckpointV2(
        envelope.format_version,
        envelope.payload,
        payload_bytes,
        envelope.integrity,
    )
end

checkpoint_fingerprint(value::LogicalCheckpointV2) = value.integrity

function _restore_snapshot(
    composite::CompiledComposite,
    payload::NamedTuple,
)
    entries = _realize_entries(
        composite.plan.schema,
        Dict(payload.entries),
    )
    tuple((first(pair) for pair in entries)...) ==
        tuple((first(pair) for pair in payload.entries)...) ||
        _fail(:checkpoint_state_paths,
            "checkpoint state paths do not match the compiled schema")
    CommittedSnapshot(
        composite.plan.schema,
        entries,
        payload.version,
        payload.time,
        payload.parent_fingerprint,
        payload.topology_fingerprint,
    )
end

function _restore_event(payload)
    EventRecord(
        payload.schema_version,
        payload.event_id,
        payload.ordinal,
        payload.time,
        payload.due_processes,
        tuple((ActivationRecord(
            record.owner,
            record.kind,
            record.layer,
            record.iteration,
            record.input_fingerprint,
            record.output_fingerprint,
        ) for record in payload.activations)...),
        tuple((IterationOutcome(
            record.region,
            record.iterations,
            record.converged,
            record.fingerprint,
        ) for record in payload.iterations)...),
        payload.before_fingerprint,
        payload.after_fingerprint,
        payload.runtime_fingerprint,
    )
end

function _restore_observation(payload)
    ObservationRecord(
        payload.observer,
        payload.event_id,
        payload.time,
        payload.status,
        payload.payload,
        payload.payload_fingerprint,
    )
end

function restore(
    composite::CompiledComposite,
    executor::SerialExecutor,
    checkpoint::LogicalCheckpointV2,
)
    executor.qualification === :strict ||
        _fail(:logical_checkpoint_requires_strict_executor,
            "v2 logical restore requires the strict serial executor")
    _validate_logical_checkpoint(checkpoint)
    payload = checkpoint.payload
    payload.schema == LOGICAL_CHECKPOINT_SCHEMA &&
        payload.format_version == LOGICAL_CHECKPOINT_VERSION ||
        _fail(:unsupported_checkpoint_version,
            "logical checkpoint payload version is unsupported")
    model_fingerprint(composite) == payload.model_fingerprint ||
        _fail(:checkpoint_model_mismatch,
            "logical checkpoint belongs to another model")
    structural_fingerprint(composite) == payload.structural_fingerprint &&
        composite.epoch.version == payload.structural_epoch_version ||
        _fail(:checkpoint_structure_mismatch,
            "logical checkpoint structural epoch is incompatible")
    execution_plan_fingerprint(composite) ==
        payload.execution_plan_fingerprint ||
        _fail(:checkpoint_plan_mismatch,
            "logical checkpoint execution plan is incompatible")
    runtime_fingerprint(executor, composite) == payload.runtime_fingerprint ||
        _fail(:checkpoint_runtime_mismatch,
            "logical checkpoint runtime policy is incompatible")
    observation_fingerprint(executor.observation_plan) ==
        payload.observation_fingerprint ||
        _fail(:checkpoint_observation_mismatch,
            "logical checkpoint observation plan is incompatible")
    SEMANTIC_RNG_ALGORITHM == payload.rng_algorithm &&
        SEMANTIC_RNG_ADDRESS_SCHEMA == payload.rng_address_schema &&
        executor.root_seed.words == payload.root_seed ||
        _fail(:checkpoint_rng_mismatch,
            "logical checkpoint RNG contract is incompatible")

    runtime = initialize_runtime(composite, executor)
    specs = _continuation_specs(runtime)
    canonical_fingerprint(specs) == payload.continuation_fingerprint ||
        _fail(:checkpoint_continuation_mismatch,
            "logical checkpoint continuation contracts are incompatible")
    length(payload.process_clocks) == length(runtime.process_clocks) ||
        _fail(:checkpoint_process_mismatch,
            "logical checkpoint process count changed")
    length(payload.step_clocks) == length(runtime.step_clocks) ||
        _fail(:checkpoint_step_mismatch,
            "logical checkpoint step count changed")
    length(payload.observer_clocks) == length(runtime.observer_clocks) ||
        _fail(:checkpoint_observer_mismatch,
            "logical checkpoint observer count changed")

    process_clocks = tuple((ProcessClock(
        row.id,
        row.last_committed,
        row.next_due,
        row.continuation,
    ) for row in payload.process_clocks)...)
    step_clocks = tuple((StepClock(
        row.id,
        row.continuation,
    ) for row in payload.step_clocks)...)
    input_cursors = tuple((ProcessInputCursor(
        row.id,
        row.since,
        row.start_values,
        row.samples,
    ) for row in payload.input_cursors)...)
    observer_clocks = tuple((ObserverClock(
        row.id,
        row.next_due,
        row.continuation,
        row.position,
    ) for row in payload.observer_clocks)...)

    for (entry, clock) in zip(composite.plan.processes, process_clocks)
        entry.declaration.id == clock.id ||
            _fail(:checkpoint_process_mismatch,
                "logical checkpoint process identity changed")
        validate_continuation(
            _continuation_spec(executor, entry.declaration),
            clock.id,
            clock.continuation,
        )
    end
    for (entry, clock) in zip(composite.plan.steps, step_clocks)
        entry.declaration.id == clock.id ||
            _fail(:checkpoint_step_mismatch,
                "logical checkpoint step identity changed")
        validate_continuation(
            _continuation_spec(executor, entry.declaration),
            clock.id,
            clock.continuation,
        )
    end
    for (observer, clock) in zip(
        executor.observation_plan.observers, observer_clocks)
        observer.id == clock.id ||
            _fail(:checkpoint_observer_mismatch,
                "logical checkpoint observer identity changed")
        validate_continuation(
            observer.continuation_spec,
            clock.id,
            clock.continuation,
        )
    end

    runtime.snapshot = _restore_snapshot(composite, payload.snapshot)
    runtime.process_clocks = process_clocks
    runtime.step_clocks = step_clocks
    runtime.input_cursors = input_cursors
    runtime.observer_clocks = observer_clocks
    runtime.events = payload.event_count
    runtime.trace = EventRecord[_restore_event(row) for row in payload.trace]
    runtime.records = ObservationRecord[
        _restore_observation(row) for row in payload.records]
    runtime.diagnostic = nothing
    runtime
end

restore(
    composite::CompiledComposite,
    executor::SerialExecutor,
    bytes::AbstractVector{UInt8},
) = restore(composite, executor, decode_checkpoint(bytes))
