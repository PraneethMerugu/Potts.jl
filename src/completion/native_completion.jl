function _native_source_fingerprint_or_error(
        occurrence::_SourceNativeOccurrence
    )
    source = native_source(occurrence.component)
    applicable(native_source_fingerprint, source) || throw(ArgumentError(
        "native component $(join(occurrence.path, '₊')) requires the full " *
        "ModelingToolkit extension for structural source identity"
    ))
    fingerprint = native_source_fingerprint(source)
    fingerprint isa NativeSourceFingerprint || error(
        "native_source_fingerprint must return NativeSourceFingerprint"
    )
    return fingerprint
end

function _native_endpoint_occurrence(
        inventory::_PottsSourceInventory,
        native::_SourceNativeOccurrence,
        port::_NativePort,
    )
    endpoint = potts_endpoint(port)
    exact = filter(
        occurrence -> occurrence.statement === endpoint,
        inventory.statements,
    )
    if length(exact) == 1
        return only(exact)
    elseif length(exact) > 1
        paths = join((join(item.path, '₊') for item in exact), ", ")
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) is ambiguous across $paths"
        ))
    end

    same_identity = occurrence ->
        statement_id(occurrence.statement) == statement_id(endpoint) &&
        statement_kind(occurrence.statement) === statement_kind(endpoint)
    local_matches = filter(
        occurrence -> occurrence.path == native.system_path &&
                      same_identity(occurrence),
        inventory.statements,
    )
    length(local_matches) == 1 && return only(local_matches)
    length(local_matches) > 1 && error(
        "completion admitted duplicate local statement identities"
    )

    global_matches = filter(same_identity, inventory.statements)
    if isempty(global_matches)
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) does not resolve to a Potts statement"
        ))
    elseif length(global_matches) > 1
        paths = join((join(item.path, '₊') for item in global_matches), ", ")
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) is ambiguous across $paths"
        ))
    end
    return only(global_matches)
end

# Native component completion resolves Potts endpoints while retaining the
# original ModelingToolkit systems as their own semantic authority.
function _resolve_native_components(
        inventory::_PottsSourceInventory, records
    )
    isempty(inventory.natives) && return CompletedNativeComponent[]
    by_identity = Dict(record.identity => record for record in records)
    completed = CompletedNativeComponent[]
    seen_paths = Set{Tuple{Vararg{Symbol}}}()
    all_endpoints = CouplingEndpointSchema[]
    for native in inventory.natives
        native.path in seen_paths && throw(ArgumentError(
            "duplicate native component path $(join(native.path, '₊'))"
        ))
        push!(seen_paths, native.path)
        endpoints = CouplingEndpointSchema[]
        for port in (
                native_inputs(native.component)...,
                native_outputs(native.component)...,
            )
            occurrence = _native_endpoint_occurrence(inventory, native, port)
            identity = QualifiedStatementID(
                occurrence.path, statement_id(occurrence.statement)
            )
            record = get(by_identity, identity, nothing)
            record isa QualifiedStatement || error(
                "native endpoint $identity is missing from completion records"
            )
            if record.kind in (
                    :SiteState, :CellState, :MediumState, :ModelState,
                    :FieldState, :HistoryState,
                )
                arguments = first(record.normalized_payload)
                haskey(arguments, :variable) || throw(ArgumentError(
                    "native coupling endpoint $identity resolves to a " *
                    "$(record.kind) without symbolic storage; author it with " *
                    "the symbolic state constructor"
                ))
            end
            push!(endpoints, CouplingEndpointSchema(
                native.path, port, identity, record.kind
            ))
        end
        endpoint_tuple = Tuple(endpoints)
        append!(all_endpoints, endpoints)
        push!(completed, CompletedNativeComponent(
            native.path,
            native.component,
            endpoint_tuple,
            _native_source_fingerprint_or_error(native),
        ))
    end
    _assert_single_native_writers(all_endpoints)
    return completed
end

