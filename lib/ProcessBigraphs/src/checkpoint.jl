struct SettledCheckpoint
    format_version::String
    model_fingerprint::String
    snapshot::CommittedSnapshot
    process_clocks::Tuple{Vararg{ProcessClock}}
    step_clocks::Tuple{Vararg{StepClock}}
    event_count::UInt64
    integrity::String
end

function _checkpoint_payload(
    model::String,
    snapshot::CommittedSnapshot,
    process_clocks,
    step_clocks,
    events,
)
    (
        :process_bigraphs_settled_checkpoint_v1,
        "1.0.0",
        model,
        snapshot,
        process_clocks,
        step_clocks,
        events,
    )
end

function checkpoint(runtime::SerialRuntime)
    runtime.is_settled ||
        _fail(:unsettled_checkpoint, "checkpoints require a settled commit boundary")
    payload = _checkpoint_payload(
        model_fingerprint(runtime.composite),
        runtime.snapshot,
        runtime.process_clocks,
        runtime.step_clocks,
        runtime.events,
    )
    SettledCheckpoint(
        "1.0.0",
        model_fingerprint(runtime.composite),
        deepcopy(runtime.snapshot),
        deepcopy(runtime.process_clocks),
        deepcopy(runtime.step_clocks),
        runtime.events,
        canonical_fingerprint(payload),
    )
end

checkpoint_fingerprint(value::SettledCheckpoint) = value.integrity

function restore(composite::CompiledComposite, value::SettledCheckpoint)
    value.format_version == "1.0.0" ||
        _fail(:unsupported_checkpoint_version, "checkpoint format is unsupported";
            version=value.format_version)
    model_fingerprint(composite) == value.model_fingerprint ||
        _fail(:checkpoint_model_mismatch, "checkpoint belongs to another compiled model";
            expected=model_fingerprint(composite), actual=value.model_fingerprint)
    payload = _checkpoint_payload(
        value.model_fingerprint,
        value.snapshot,
        value.process_clocks,
        value.step_clocks,
        value.event_count,
    )
    canonical_fingerprint(payload) == value.integrity ||
        _fail(:checkpoint_integrity_failure, "checkpoint integrity hash does not match")
    ids = Tuple(entry.declaration.id for entry in composite.plan.processes)
    Tuple(clock.id for clock in value.process_clocks) == ids ||
        _fail(:checkpoint_process_mismatch, "checkpoint process identities changed")
    step_ids = Tuple(entry.declaration.id for entry in composite.plan.steps)
    Tuple(clock.id for clock in value.step_clocks) == step_ids ||
        _fail(:checkpoint_step_mismatch, "checkpoint step identities changed")
    SerialRuntime(
        composite,
        deepcopy(value.snapshot),
        deepcopy(value.process_clocks),
        deepcopy(value.step_clocks),
        value.event_count,
        true,
    )
end
