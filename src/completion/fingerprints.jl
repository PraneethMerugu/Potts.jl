const _CANONICAL_VALUE_SCHEMA = "potts-canonical-value-v2"

@noinline function _canonical_frame(tag::AbstractString, parts)
    Base.@nospecialize parts
    io = IOBuffer()
    print(io, 'F', ncodeunits(tag), ':')
    write(io, tag)
    print(io, length(parts), ':')
    for part in parts
        part isa AbstractString || throw(ArgumentError(
            "canonical frame payloads must already be encoded strings"
        ))
        print(io, ncodeunits(part), ':')
        write(io, part)
    end
    return String(take!(io))
end

_canonical_frame(tag::AbstractString, parts::AbstractString...) =
    _canonical_frame(tag, parts)

@noinline function _canonical_type_identity(type)
    Base.@nospecialize type
    module_path = try
        join(string.(Base.fullname(parentmodule(type))), ".")
    catch
        ""
    end
    return _canonical_frame("type", module_path, repr(type))
end

@noinline function _canonical_struct(value)
    Base.@nospecialize value
    type = typeof(value)
    isstructtype(type) && !ismutabletype(type) || throw(ArgumentError(
        "unsupported mutable canonical fingerprint value of type $type"
    ))
    fields = String[_canonical_type_identity(type)]
    for name in fieldnames(type)
        push!(fields, _canonical_frame(
            "field", _canonical_value(name),
            _canonical_value(getfield(value, name)),
        ))
    end
    return _canonical_frame("struct", fields)
end

@noinline function _canonical_axis(axis)
    Base.@nospecialize axis
    return _canonical_frame(
        "axis",
        _canonical_type_identity(typeof(axis)),
        _canonical_value(length(axis)),
        _canonical_value(first(axis)),
        _canonical_value(step(axis)),
        _canonical_value(last(axis)),
    )
end

@noinline function _canonical_axes(value)
    Base.@nospecialize value
    encoded = String[]
    for axis in axes(value)
        push!(encoded, _canonical_axis(axis))
    end
    return _canonical_frame("axes", encoded)
end

@noinline function _canonical_named_tuple(value)
    Base.@nospecialize value
    encoded = String[_canonical_type_identity(typeof(value))]
    for key in keys(value)
        push!(encoded, _canonical_frame(
            "entry",
            _canonical_value(key),
            _canonical_value(getfield(value, key)),
        ))
    end
    return _canonical_frame("named-tuple", encoded)
end

@noinline function _canonical_tuple(value)
    Base.@nospecialize value
    encoded = String[_canonical_type_identity(typeof(value))]
    for item in value
        push!(encoded, _canonical_value(item))
    end
    return _canonical_frame("tuple", encoded)
end

@noinline function _canonical_dictionary(value)
    Base.@nospecialize value
    entries = String[]
    for (key, item) in value
        push!(entries, _canonical_frame(
            "entry", _canonical_value(key), _canonical_value(item)
        ))
    end
    sort!(entries)
    encoded = String[
        _canonical_type_identity(typeof(value)),
        _canonical_value(length(value)),
    ]
    append!(encoded, entries)
    return _canonical_frame("dictionary", encoded)
end

@noinline function _canonical_set(value)
    Base.@nospecialize value
    entries = String[]
    for item in value
        push!(entries, _canonical_value(item))
    end
    sort!(entries)
    encoded = String[
        _canonical_type_identity(typeof(value)),
        _canonical_value(length(value)),
    ]
    append!(encoded, entries)
    return _canonical_frame("set", encoded)
end

@noinline function _canonical_array(value)
    Base.@nospecialize value
    encoded = String[
        _canonical_type_identity(typeof(value)),
        _canonical_axes(value),
        _canonical_value(length(value)),
    ]
    for item in value
        push!(encoded, _canonical_value(item))
    end
    return _canonical_frame("array", encoded)
end

"""
Encode one admitted logical value for hashing.

Every composite uses byte-length-delimited frames. Arrays additionally encode
their concrete type, axes, and logical iteration length, so shape, indexing,
and element-type changes cannot alias a flat element sequence. Statement
source locations are intentionally represented by one omitted-source token
because provenance is not part of scientific identity.
"""
@noinline function _canonical_value(value)
    # Fingerprints are a runtime data codec.  Inferring this method from the
    # full concrete shape of large statement, provenance, and analysis tuples
    # creates model-size-dependent compiler work without changing the bytes.
    Base.@nospecialize value
    value isa AbstractStatementSource &&
        return _canonical_frame("omitted-statement-source")
    value isa StatementID && return _canonical_frame(
        "statement-id", _canonical_value(Symbol(value))
    )
    value isa AbstractPottsStatement && return _canonical_frame(
        "potts-statement",
        _canonical_type_identity(typeof(value)),
        _canonical_value(statement_kind(value)),
        _canonical_value(Symbol(statement_id(value))),
        _canonical_value(_statement_arguments(value)),
        _canonical_value(_statement_options(value)),
    )
    value isa NamedTuple && return _canonical_named_tuple(value)
    value isa Tuple && return _canonical_tuple(value)
    value isa Pair && return _canonical_frame(
        "pair",
        _canonical_type_identity(typeof(value)),
        _canonical_value(first(value)),
        _canonical_value(last(value)),
    )
    value isa AbstractRange && return _canonical_frame(
        "range",
        _canonical_type_identity(typeof(value)),
        _canonical_value(length(value)),
        _canonical_value(first(value)),
        _canonical_value(step(value)),
        _canonical_value(last(value)),
    )
    value isa AbstractDict && return _canonical_dictionary(value)
    value isa AbstractSet && return _canonical_set(value)
    value isa AbstractArray && return _canonical_array(value)
    value isa Type && return _canonical_frame(
        "type-value", _canonical_type_identity(value)
    )
    value isa AbstractString && return _canonical_frame(
        "string", _canonical_type_identity(typeof(value)), String(value)
    )
    value isa Symbol && return _canonical_frame("symbol", String(value))
    value isa Char && return _canonical_frame(
        "character", _canonical_type_identity(typeof(value)), string(UInt32(value))
    )
    value === nothing && return _canonical_frame("nothing")
    value === missing && return _canonical_frame("missing")
    value isa VersionNumber && return _canonical_frame(
        "version", _canonical_type_identity(typeof(value)), repr(value)
    )
    value isa Enum && return _canonical_frame(
        "enum", _canonical_type_identity(typeof(value)), bitstring(value)
    )
    if value isa Number
        type = typeof(value)
        isprimitivetype(type) && return _canonical_frame(
            "primitive-number",
            _canonical_type_identity(type),
            bitstring(value),
        )
        isstructtype(type) && !ismutabletype(type) && return _canonical_frame(
            "number-struct",
            _canonical_struct(value),
        )
        return _canonical_frame(
            "number", _canonical_type_identity(type), repr(value)
        )
    end
    value isa Expr && return _canonical_frame(
        "expression", _canonical_value(value.head), _canonical_value(value.args)
    )
    value isa QuoteNode && return _canonical_frame(
        "quote-node", _canonical_value(value.value)
    )
    if !(SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic)
        return _canonical_frame(
            "symbolic",
            _canonical_type_identity(typeof(value)),
            _canonical_type_identity(
                typeof(SymbolicIndexingInterface.symbolic_type(value))
            ),
            string(value),
        )
    end
    return _canonical_struct(value)
end

@noinline function _sha256_hex(parts...)
    Base.@nospecialize parts
    encoded = String[_CANONICAL_VALUE_SCHEMA]
    for part in parts
        push!(encoded, _canonical_value(part))
    end
    payload = _canonical_frame("digest", encoded)
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function _native_declaration_fingerprint_payload(
        path,
        declaration::NativeComponent,
        endpoints,
        source_fingerprint::NativeSourceFingerprint,
    )
    endpoint_payloads = Tuple((
        direction = endpoint.port isa NativeInput ? :input : :output,
        native_variable = _canonical_value(native_variable(endpoint)),
        value_type = native_value_type(endpoint),
        potts_identity = potts_endpoint(endpoint),
        potts_kind = endpoint.potts_kind,
    ) for endpoint in endpoints)
    return (
        path,
        source = source_fingerprint.hex,
        family = nameof(typeof(getfield(declaration, :family))),
        scope = nameof(typeof(getfield(declaration, :scope))),
        time = getfield(declaration, :time),
        cadence = getfield(declaration, :cadence),
        split = nameof(typeof(getfield(declaration, :split))),
        initialization = nameof(typeof(getfield(declaration, :initialization))),
        events = nameof(typeof(getfield(declaration, :events))),
        lifecycle = nameof(typeof(getfield(declaration, :lifecycle))),
        algorithm = nameof(typeof(getfield(declaration, :algorithm))),
        capabilities = nameof(typeof(getfield(declaration, :capabilities))),
        endpoints = endpoint_payloads,
    )
end

function _native_fingerprint_payload(component::CompletedNativeComponent)
    return _native_declaration_fingerprint_payload(
        component.path,
        component.declaration,
        component.endpoints,
        component.source_fingerprint,
    )
end

function _scheduled_native_fingerprint_payload(
        component::ScheduledNativeComponent
    )
    declaration = _native_declaration_fingerprint_payload(
        component.path,
        component.declaration,
        component.endpoints,
        component.original_fingerprint,
    )
    return merge(declaration, (
        scheduled_source = component.scheduled_fingerprint.hex,
    ))
end

function _semantic_fingerprint(
        system::PottsSystem, records, native_components = ()
    )
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
    natives = sort!([
        _canonical_value(_native_fingerprint_payload(component))
        for component in native_components
    ])
    return SemanticFingerprint(_sha256_hex(
        "potts-semantic-v1", normalized, equations, natives
    ))
end

function _completed_fingerprint(
        semantic::SemanticFingerprint,
        records,
        reference_units,
        registry,
        native_components = (),
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
            sort!([
                _canonical_value(_native_fingerprint_payload(component))
                for component in native_components
            ]),
        )
    )
end

"""Identity of one deterministic, structurally scheduled `PottsSystem`."""
struct ScheduledSystemFingerprint
    hex::String
end

Base.string(value::ScheduledSystemFingerprint) = value.hex
Base.:(==)(
    left::ScheduledSystemFingerprint, right::ScheduledSystemFingerprint
) = left.hex == right.hex
Base.hash(value::ScheduledSystemFingerprint, seed::UInt) = hash(value.hex, seed)
Base.show(io::IO, value::ScheduledSystemFingerprint) =
    print(io, "ScheduledSystemFingerprint(\"", value.hex, "\")")

function _scheduled_fingerprint(
        completed::CompletedSystemFingerprint,
        schedule,
        provenance,
        parameters,
        states,
        relationships,
        observations,
        capability_requirements,
        native_components = (),
    )
    return ScheduledSystemFingerprint(_sha256_hex(
        "potts-scheduled-system-v1",
        completed.hex,
        schedule,
        provenance,
        parameters,
        states,
        relationships,
        observations,
        capability_requirements,
        native_components,
    ))
end
