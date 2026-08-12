# One static topology payload per lowering drives preparation-time copies and
# checked transfer accounting. Family code still owns validation, semantic
# fingerprint headers, and the interpretation of every payload leaf.

function _static_topology_payload end

function _centrally_owned_static_topology_payload(lowering)
    signature = Tuple{typeof(lowering)}
    method = which(_static_topology_payload, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the static topology payload is not centrally admitted"
    ))
    return invoke(_static_topology_payload, signature, lowering)
end

function _copy_topology_payload(backend, payload)
    if payload isa NamedTuple
        return NamedTuple{keys(payload)}(map(values(payload)) do value
            invoke(
                _copy_topology_payload,
                Tuple{Any, Any},
                backend,
                value,
            )
        end)
    elseif payload isa Tuple
        return map(payload) do value
            invoke(
                _copy_topology_payload,
                Tuple{Any, Any},
                backend,
                value,
            )
        end
    elseif payload isa AbstractArray
        return invoke(
            _centrally_owned_device_copy,
            Tuple{Any, Any},
            backend,
            payload,
        )
    end
    throw(LocalWorkValidationError(
        "static topology payloads may contain only tuples, named tuples, and arrays"
    ))
end

function _centrally_copy_topology_payload(backend, payload)
    signature = Tuple{Any, Any}
    method = which(_copy_topology_payload, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the static topology copier is not package-owned"
    ))
    return invoke(_copy_topology_payload, signature, backend, payload)
end

function _topology_payload_bytes(payload, path::Tuple = ())
    if payload isa NamedTuple
        total = 0
        for (name, value) in pairs(payload)
            total = invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                total,
                invoke(
                    _topology_payload_bytes,
                    Tuple{Any, Tuple},
                    value,
                    (path..., name),
                ),
                :topology_transfer_bytes,
            )
        end
        return total
    elseif payload isa Tuple
        total = 0
        for (index, value) in pairs(payload)
            total = invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                total,
                invoke(
                    _topology_payload_bytes,
                    Tuple{Any, Tuple},
                    value,
                    (path..., index),
                ),
                :topology_transfer_bytes,
            )
        end
        return total
    elseif payload isa AbstractArray
        purpose = isempty(path) ? :topology_payload_bytes :
            Symbol(join(string.(path), "_"), "_bytes")
        return invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            length(payload),
            sizeof(eltype(payload)),
            purpose,
        )
    end
    throw(LocalWorkValidationError(
        "static topology byte accounting found an unsupported payload leaf"
    ))
end

function _centrally_count_topology_payload_bytes(payload)
    signature = Tuple{Any, Tuple}
    method = which(_topology_payload_bytes, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the static topology byte counter is not package-owned"
    ))
    return invoke(_topology_payload_bytes, signature, payload, ())
end
