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
    value isa AbstractRange && return string(
        "Range(",
        nameof(typeof(value)),
        ",first=", _canonical_value(first(value)),
        ",step=", _canonical_value(step(value)),
        ",last=", _canonical_value(last(value)),
        ")",
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
    value isa DataType && return string(
        "DataType(",
        parentmodule(value),
        ".",
        nameof(value),
        "{",
        join((_canonical_value(parameter) for parameter in value.parameters), ","),
        "})",
    )
    if !(SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic)
        return string(value)
    end
    return repr(value)
end

_sha256_hex(parts...) =
    bytes2hex(SHA.sha256(codeunits(join(_canonical_value.(parts), "\n"))))

function _semantic_fingerprint(system::PottsSystem, records)
    function semantic_payload(record)
        arguments, options = record.normalized_payload
        if record.kind in (
                :SiteState,
                :CellState,
                :MediumState,
                :ModelState,
                :FieldState,
                :HistoryState,
                :RelationshipState,
            ) && arguments isa NamedTuple && haskey(arguments, :initial)
            retained = Tuple(
                name for name in keys(arguments) if name !== :initial
            )
            arguments = NamedTuple{retained}(Tuple(
                getproperty(arguments, name) for name in retained
            ))
        end
        return (arguments, options)
    end
    normalized = sort!(
        [_canonical_value(semantic_payload(record)) for record in records]
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
            record.result_type,
            record.shape,
            record.units,
            record.reference_conversion,
            record.reads,
            record.writes,
            record.ownership,
            record.persistence,
            record.resources,
            record.effect,
            record.bound,
            record.transaction_identity,
            record.lifecycle,
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
