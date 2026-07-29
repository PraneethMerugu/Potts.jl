struct CorePottsCanonicalCheckpointConverter <:
        ProcessBigraphs.AbstractLegacyCheckpointConverter end

struct CorePottsCoupledCheckpointConverter <:
        ProcessBigraphs.AbstractLegacyCheckpointConverter end

function _process_bigraph_logical_value(value)
    value isa Union{
        Nothing,Missing,Bool,Integer,AbstractFloat,AbstractString,
        Symbol,Char,Rational,
    } && return value
    value isa VersionNumber &&
        return (logical_type=:version_number, value=string(value))
    value isa Enum &&
        return (
            logical_type=:enum,
            source_type=string(typeof(value)),
            value=Integer(value),
        )
    value isa Type &&
        return (logical_type=:type, value=string(value))
    value isa Pair &&
        return _process_bigraph_logical_value(first(value)) =>
            _process_bigraph_logical_value(last(value))
    value isa NamedTuple &&
        return NamedTuple{keys(value)}(Tuple(
            _process_bigraph_logical_value(item) for item in values(value)))
    value isa Tuple &&
        return tuple((_process_bigraph_logical_value(item)
            for item in value)...)
    value isa AbstractArray &&
        return map(_process_bigraph_logical_value, Array(value))
    isstructtype(typeof(value)) && !ismutabletype(typeof(value)) ||
        throw(ArgumentError(
            "legacy checkpoint value $(typeof(value)) has no logical conversion"))
    names = fieldnames(typeof(value))
    (
        logical_type=:immutable_struct,
        source_type=string(typeof(value)),
        fields=NamedTuple{names}(Tuple(
            _process_bigraph_logical_value(getfield(value, name))
            for name in names)),
    )
end

function ProcessBigraphs.legacy_source_fingerprint(
    ::CorePottsCanonicalCheckpointConverter,
    checkpoint::CanonicalCheckpoint,
)
    validate_checkpoint(checkpoint)
    bytes2hex(collect(checkpoint.checksum))
end

function ProcessBigraphs.legacy_checkpoint_component(
    ::CorePottsCanonicalCheckpointConverter,
    checkpoint::CanonicalCheckpoint,
)
    validate_checkpoint(checkpoint)
    ProcessBigraphs.CheckpointComponent(
        "corepotts-canonical-checkpoint",
        string(checkpoint.schema_version),
        :exact,
        (
            source_kind=:canonical,
            source_checksum=bytes2hex(collect(checkpoint.checksum)),
            storage_payload=checkpoint_storage_payload(checkpoint),
        ),
    )
end

function _coupled_checkpoint_payload(checkpoint::CoupledCheckpoint)
    (
        source_kind=:coupled,
        source_checksum=bytes2hex(collect(checkpoint.checksum)),
        schema_version=string(checkpoint.schema_version),
        complete=checkpoint.complete,
        mcs=checkpoint.mcs,
        phase=checkpoint.phase,
        base=checkpoint_storage_payload(checkpoint.base),
        extension=(
            version=string(checkpoint.extension.version),
            blocks=tuple((
                (
                    family=block.family,
                    name=block.name,
                    contract=block.contract,
                    version=string(block.version),
                    metadata=_process_bigraph_logical_value(block.metadata),
                    payload=_process_bigraph_logical_value(block.payload),
                    required=block.required,
                    checksum=collect(block.checksum),
                )
                for block in checkpoint.extension.blocks
            )...),
            protocol_position=_process_bigraph_logical_value(
                checkpoint.extension.protocol_position),
            observation_schedule=_process_bigraph_logical_value(
                checkpoint.extension.observation_schedule),
        ),
        coupled_model_fingerprint=collect(
            checkpoint.coupled_model_fingerprint),
        state_schema_fingerprint=collect(
            checkpoint.state_schema_fingerprint),
        initial_state_fingerprint=collect(
            checkpoint.initial_state_fingerprint),
        ancestry_fingerprint=collect(checkpoint.ancestry_fingerprint),
        state_fingerprint=collect(checkpoint.state_fingerprint),
        warnings=_process_bigraph_logical_value(checkpoint.warnings),
    )
end

function ProcessBigraphs.legacy_source_fingerprint(
    ::CorePottsCoupledCheckpointConverter,
    checkpoint::CoupledCheckpoint,
)
    validate_checkpoint(checkpoint)
    bytes2hex(collect(checkpoint.checksum))
end

function ProcessBigraphs.legacy_checkpoint_component(
    ::CorePottsCoupledCheckpointConverter,
    checkpoint::CoupledCheckpoint,
)
    validate_checkpoint(checkpoint)
    ProcessBigraphs.CheckpointComponent(
        "corepotts-coupled-checkpoint",
        string(checkpoint.schema_version),
        :exact,
        _coupled_checkpoint_payload(checkpoint),
    )
end
