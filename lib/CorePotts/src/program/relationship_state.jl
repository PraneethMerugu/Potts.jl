function initialize_program_relationships(
        schema::RelationshipStoreSchema,
        endpoint_status,
        endpoint_generations,
        parameters::AbstractVector{T},
        entries,
    ) where {T}
    state = ProgramRelationshipState(
        T,
        schema.capacity,
        length(endpoint_status),
        schema.maximum_degree,
        length(schema.payload_defaults),
    )
    entries === nothing && return validate_relationship_integrity(
        state, schema, endpoint_status, endpoint_generations
    )
    defaults = map(
        value -> compiled_scalar_value(value, parameters),
        schema.payload_defaults,
    )
    requests = ProgramRelationshipRequest[]
    for (identity, entry) in enumerate(entries)
        entry isa Tuple && length(entry) in (2, 3, 5) || throw(ArgumentError(
            "relationship entries are `(a, b)`, `(a, b, payload)`, or " *
            "`(a, b, payload, generation_a, generation_b)`"
        ))
        a, b = entry[1], entry[2]
        a isa Integer && 1 <= a <= length(endpoint_generations) ||
            throw(ArgumentError("relationship endpoint $a is not an active cell"))
        b isa Integer && 1 <= b <= length(endpoint_generations) ||
            throw(ArgumentError("relationship endpoint $b is not an active cell"))
        supplied = length(entry) >= 3 ? entry[3] : ntuple(_ -> nothing, length(defaults))
        supplied isa Tuple && length(supplied) == length(defaults) ||
            throw(ArgumentError(
                "initial relationship payload does not match its schema"
            ))
        payload = ntuple(length(defaults)) do slot
            value = supplied[slot]
            value === nothing ? defaults[slot] : T(value)
        end
        generation_a = length(entry) == 5 && entry[4] !== nothing ?
                       UInt32(entry[4]) : endpoint_generations[Int(a)]
        generation_b = length(entry) == 5 && entry[5] !== nothing ?
                       UInt32(entry[5]) : endpoint_generations[Int(b)]
        push!(requests, CreateRelationshipRequest(
            a,
            b,
            payload;
            generation_a,
            generation_b,
            identity,
        ))
    end
    apply_relationship_requests!(
        state, endpoint_status, endpoint_generations, schema, requests
    )
    return validate_relationship_integrity(
        state, schema, endpoint_status, endpoint_generations
    )
end

function validate_relationship_integrity(
        state,
        schema::RelationshipStoreSchema,
        endpoint_status,
        endpoint_generations,
    )
    capacity = Int(schema.capacity)
    length(state.active) == capacity || throw(ArgumentError(
        "relationship active-slot storage has the wrong capacity"
    ))
    all(length(values) == capacity for values in state.payload) || throw(
        ArgumentError("relationship payload storage has the wrong capacity")
    )
    length(state.payload) == length(schema.payload_defaults) || throw(
        ArgumentError("relationship payload storage does not match its schema")
    )
    length(endpoint_status) == length(endpoint_generations) ==
        length(state.degree) == size(state.incident_edges, 2) || throw(
        ArgumentError("relationship endpoint tables are misaligned")
    )
    size(state.incident_edges, 1) == Int(schema.maximum_degree) || throw(
        ArgumentError("relationship incident storage has the wrong degree bound")
    )

    for edge in eachindex(state.active)
        if @inbounds state.active[edge]
            a = @inbounds state.endpoint_a[edge]
            b = @inbounds state.endpoint_b[edge]
            1 <= a < b <= length(endpoint_status) || throw(ArgumentError(
                "active relationship $edge has invalid canonical endpoints"
            ))
            @inbounds(!iszero(endpoint_status[a]) &&
                      !iszero(endpoint_status[b])) || throw(ArgumentError(
                "active relationship $edge references an inactive endpoint"
            ))
            @inbounds(state.generation_a[edge] == endpoint_generations[a] &&
                      state.generation_b[edge] == endpoint_generations[b]) ||
                throw(ArgumentError(
                    "active relationship $edge has a stale endpoint generation"
                ))
            all(values -> isfinite(@inbounds(values[edge])), state.payload) ||
                throw(DomainError(
                    edge, "active relationship payload values must be finite"
                ))
        else
            @inbounds(
                iszero(state.endpoint_a[edge]) &&
                iszero(state.endpoint_b[edge]) &&
                iszero(state.generation_a[edge]) &&
                iszero(state.generation_b[edge])
            ) || throw(ArgumentError(
                "inactive relationship $edge retains structural state"
            ))
            all(values -> iszero(@inbounds(values[edge])), state.payload) ||
                throw(ArgumentError(
                    "inactive relationship $edge retains payload state"
                ))
        end
    end

    for endpoint in eachindex(state.degree)
        degree = Int(@inbounds state.degree[endpoint])
        0 <= degree <= Int(schema.maximum_degree) || throw(ArgumentError(
            "relationship degree is outside its compiled bound"
        ))
        previous = Int32(0)
        for position in 1:size(state.incident_edges, 1)
            edge = @inbounds state.incident_edges[position, endpoint]
            if position <= degree
                edge > previous || throw(ArgumentError(
                    "relationship incident indices are not strictly ordered"
                ))
                1 <= edge <= capacity && @inbounds(state.active[edge]) ||
                    throw(ArgumentError(
                        "relationship incident index references an inactive edge"
                    ))
                @inbounds(
                    state.endpoint_a[edge] == endpoint ||
                    state.endpoint_b[edge] == endpoint
                ) || throw(ArgumentError(
                    "relationship incident index references the wrong endpoint"
                ))
                previous = edge
            else
                iszero(edge) || throw(ArgumentError(
                    "relationship incident storage is not zero-filled"
                ))
            end
        end
    end

    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        a = Int(@inbounds state.endpoint_a[edge])
        b = Int(@inbounds state.endpoint_b[edge])
        count(==(Int32(edge)), @view state.incident_edges[:, a]) == 1 &&
            count(==(Int32(edge)), @view state.incident_edges[:, b]) == 1 ||
            throw(ArgumentError(
                "active relationship $edge is not indexed exactly once by both endpoints"
            ))
        for position in 1:Int(@inbounds state.degree[a])
            prior = Int(@inbounds state.incident_edges[position, a])
            prior < edge || break
            @inbounds state.active[prior] || continue
            @inbounds(
                state.endpoint_a[prior] == a &&
                state.endpoint_b[prior] == b
            ) && throw(ArgumentError(
                "active relationship endpoints ($a, $b) are duplicated"
            ))
        end
    end
    return state
end

_is_relationship_state(::ProgramRelationshipState) = true
_is_relationship_state(::PackedRelationshipState) = true
_is_relationship_state(::Any) = false

function _materialize_relationship_storage(
        initial::RelationshipStorage,
        schemas,
        endpoint_status,
        endpoint_generations,
        parameters,
    )
    all(bank -> bank isa PackedRelationshipBank, initial.banks) ||
        return _materialize_relationship_storage(
            collect(initial), schemas, endpoint_status,
            endpoint_generations, parameters,
        )
    result = copy(initial)
    for slot in eachindex(result)
        validate_relationship_integrity(
            result[slot], schemas[slot], endpoint_status, endpoint_generations
        )
    end
    return result
end

function _materialize_relationship_storage(
        initial,
        schemas,
        endpoint_status,
        endpoint_generations,
        parameters,
    )
    values = Any[]
    for slot in eachindex(schemas)
        entries = initial[slot]
        state = if _is_relationship_state(entries)
            copy(entries)
        else
            initialize_program_relationships(
                schemas[slot], endpoint_status, endpoint_generations,
                parameters, entries,
            )
        end
        validate_relationship_integrity(
            state, schemas[slot], endpoint_status, endpoint_generations
        )
        push!(values, state)
    end
    return _pack_relationship_storage(RelationshipStorage(values))
end

@inline function relationship_payload(
        state,
        edge::Integer,
        slot::Integer,
    )
    1 <= slot <= length(state.payload) || throw(ArgumentError(
        "relationship payload slot is outside the compiled schema"
    ))
    1 <= edge <= length(state.active) || throw(ArgumentError(
        "relationship edge is outside the compiled store"
    ))
    return @inbounds state.payload[slot][edge]
end
