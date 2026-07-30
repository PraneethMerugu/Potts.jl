function _canonical_value(value)
    value isa AbstractStatementSource && return ""
    value isa StatementID && return String(Symbol(value))
    value isa QualifiedStatementID && return string(value)
    value isa AbstractPottsStatement && return string(
        statement_kind(value), ":", Symbol(statement_id(value)), ":",
        _canonical_value(_statement_arguments(value)), ":",
        _canonical_value(_statement_options(value)),
    )
    value isa NamedTuple && return string(
        "(",
        join(
            (
                string(key, "=", _canonical_value(getfield(value, key)))
                for key in keys(value)
            ),
            ",",
        ),
        ")",
    )
    value isa Tuple && return string(
        "(", join((_canonical_value(item) for item in value), ","), ")"
    )
    value isa Pair && return string(
        _canonical_value(first(value)), "=>", _canonical_value(last(value))
    )
    value isa AbstractDict && return string(
        "{",
        join(
            sort!(
                [
                    string(_canonical_value(key), "=>", _canonical_value(item))
                    for (key, item) in value
                ]
            ),
            ",",
        ),
        "}",
    )
    value isa AbstractArray && return string(
        "[", join((_canonical_value(item) for item in value), ","), "]"
    )
    value isa DataType && return string(parentmodule(value), ".", nameof(value))
    if !(Symbolics.symbolic_type(value) isa SymbolicIndexingInterface.NotSymbolic)
        return string(value)
    end
    return repr(value)
end

_sha256_hex(parts...) =
    bytes2hex(SHA.sha256(codeunits(join(_canonical_value.(parts), "\n"))))

function _semantic_fingerprint(system::PottsSystem, records)
    normalized = sort!(
        [_canonical_value(record.normalized_payload) for record in records]
    )
    equations = sort!(_canonical_value.(ModelingToolkitBase.equations(system)))
    return SemanticFingerprint(_sha256_hex("potts-semantic-v1", normalized, equations))
end

function _completed_fingerprint(
        semantic::SemanticFingerprint, records, reference_units, registry
    )
    summaries = sort!([
        _canonical_value((
            record.identity,
            record.reads,
            record.writes,
            record.effect,
            record.bound,
            record.random_operations,
            record.phase,
            record.engine_admission,
            record.lowering_identity,
        ))
        for record in records
    ])
    return CompletedSystemFingerprint(
        _sha256_hex(
            "potts-completion-v1",
            semantic.hex,
            summaries,
            reference_units,
            registry.definitions,
        )
    )
end

