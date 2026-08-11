# Buffered canonical combination and explicitly relaxed atomic combination.
# Both paths are centrally selected from semantic port laws; callers cannot
# supply launches, workspace allocation, synchronization, or host callbacks.

struct _BufferedCombinedLowering{O, P, R, T, D, S, I}
    outputs::O
    operation::P
    reads::R
    topology::T
    destination_counts::D
    segments::S
    semantic_ids::I
    item_count::Int
    has_deterministic::Bool
    has_fast::Bool
    lowering_identity::Symbol
end

mutable struct _PreparedBufferedCombined{K1, K2, K3, R, S, I}
    clear_kernel::K1
    apply_kernel::K2
    publish_kernel::K3
    device_routes::R
    device_segments::S
    device_semantic_ids::I
end

@inline function _atomic_add!(output, destination, value)
    Atomix.@atomic output[destination] += value
    return nothing
end

@inline @generated function _apply_combined_item!(
        declarations::D,
        outputs::O,
        routes::R,
        record_values::RV,
        record_ranks::RR,
        record_valid::RM,
        result::V,
        item::Int32,
    ) where {
        D <: NamedTuple,
        O <: NamedTuple,
        R <: NamedTuple,
        RV <: NamedTuple,
        RR <: NamedTuple,
        RM <: NamedTuple,
        V <: NamedTuple,
    }
    names = D.parameters[1]
    names == O.parameters[1] == R.parameters[1] == V.parameters[1] ||
        return :(error("validated combined output names changed during execution"))
    declaration_types = D.parameters[2].parameters
    expressions = Expr[]
    for (port_index, name) in pairs(names)
        declaration = declaration_types[port_index]
        maximum = declaration.parameters[2]
        if declaration <: _IndependentOutput
            for lane in 1:maximum
                push!(expressions, quote
                    local emission = _emission_lane(
                        getproperty(result, $(QuoteNode(name))),
                        Val($maximum),
                        Val($lane),
                    )
                    local destination = Int(@inbounds getproperty(
                        routes, $(QuoteNode(name))
                    )[$lane, item])
                    if destination != 0 && _emission_enabled(emission)
                        @inbounds getproperty(
                            outputs, $(QuoteNode(name))
                        )[destination] = _emission_value(emission)
                    end
                end)
            end
        elseif declaration <: _CombinedOutput
            law_type = declaration.parameters[4]
            mode = law_type.parameters[1]
            for lane in 1:maximum
                record_index = :($lane + $maximum * (Int(item) - 1))
                if mode === :deterministic
                    push!(expressions, quote
                        local emission = _emission_lane(
                            getproperty(result, $(QuoteNode(name))),
                            Val($maximum),
                            Val($lane),
                        )
                        local enabled = _emission_enabled(emission)
                        @inbounds getproperty(
                            record_valid, $(QuoteNode(name))
                        )[$record_index] = enabled
                        if enabled
                            @inbounds getproperty(
                                record_values, $(QuoteNode(name))
                            )[$record_index] = _emission_value(emission)
                        end
                    end)
                elseif mode === :fast
                    push!(expressions, quote
                        local emission = _emission_lane(
                            getproperty(result, $(QuoteNode(name))),
                            Val($maximum),
                            Val($lane),
                        )
                        local destination = Int(@inbounds getproperty(
                            routes, $(QuoteNode(name))
                        )[$lane, item])
                        if destination != 0 && _emission_enabled(emission)
                            _atomic_add!(
                                getproperty(outputs, $(QuoteNode(name))),
                                destination,
                                _emission_value(emission),
                            )
                        end
                    end)
                else
                    return :(error("unrecognized centrally validated combination mode"))
                end
            end
        elseif declaration <: _GenericResolvedOutput
            for lane in 1:maximum
                record_index = :($lane + $maximum * (Int(item) - 1))
                push!(expressions, quote
                    local emission = _emission_lane(
                        getproperty(result, $(QuoteNode(name))),
                        Val($maximum),
                        Val($lane),
                    )
                    local enabled = _candidate_enabled(emission)
                    @inbounds getproperty(
                        record_valid, $(QuoteNode(name))
                    )[$record_index] = enabled
                    if enabled
                        local rank = _candidate_rank(emission)
                        local declaration = getproperty(
                            declarations, $(QuoteNode(name))
                        )
                        declaration.rank.lower <= rank <=
                            declaration.rank.upper || error(
                                "resolved rank is outside its declared total domain"
                            )
                        @inbounds begin
                            getproperty(
                                record_ranks, $(QuoteNode(name))
                            )[$record_index] = rank
                            getproperty(
                                record_values, $(QuoteNode(name))
                            )[$record_index] = _candidate_value(emission)
                        end
                    end
                end)
            end
        else
            return :(error("unrecognized port reached buffered combination"))
        end
    end
    return Expr(:block, expressions..., :(nothing))
end

@inline @generated function _clear_fast_destination!(
        declarations::D, outputs::O, destination::Int32,
    ) where {D <: NamedTuple, O <: NamedTuple}
    names = D.parameters[1]
    names == O.parameters[1] || return :(
        error("validated fast output names changed during execution")
    )
    declaration_types = D.parameters[2].parameters
    expressions = Expr[]
    for (index, name) in pairs(names)
        declaration = declaration_types[index]
        if declaration <: _CombinedOutput &&
                declaration.parameters[4].parameters[1] === :fast
            push!(expressions, quote
                local output = getproperty(outputs, $(QuoteNode(name)))
                if destination <= length(output)
                    @inbounds output[destination] = getproperty(
                        declarations, $(QuoteNode(name))
                    ).combine.identity
                end
            end)
        end
    end
    return Expr(:block, expressions..., :(nothing))
end

@inline @generated function _publish_deterministic_destination!(
        declarations::D,
        outputs::O,
        segments::S,
        semantic_ids::I,
        record_values::RV,
        record_ranks::RR,
        record_valid::RM,
        destination::Int32,
        active_count::Int32,
        full_active::F,
        full_destinations::G,
    ) where {
        D <: NamedTuple,
        O <: NamedTuple,
        S <: NamedTuple,
        I <: NamedTuple,
        RV <: NamedTuple,
        RR <: NamedTuple,
        RM <: NamedTuple,
        F,
        G,
    }
    names = D.parameters[1]
    names == O.parameters[1] || return :(
        error("validated deterministic output names changed during execution")
    )
    declaration_types = D.parameters[2].parameters
    expressions = Expr[]
    for (index, name) in pairs(names)
        declaration = declaration_types[index]
        if declaration <: _CombinedOutput &&
                declaration.parameters[4].parameters[1] === :deterministic
            maximum = declaration.parameters[2]
            destination_present = G <: Val{true} ? :(true) : :(
                destination <= length(output)
            )
            record_active = F <: Val{true} ? :(true) : :(
                (record_index - 1) ÷ $maximum + 1 <= active_count
            )
            push!(expressions, quote
                local output = getproperty(outputs, $(QuoteNode(name)))
                if $destination_present
                    local law = getproperty(
                        declarations, $(QuoteNode(name))
                    ).combine
                    local accumulator = law.identity
                    local segment = getproperty(
                        segments, $(QuoteNode(name))
                    )
                    local first_index = Int(@inbounds segment.offsets[destination])
                    local last_index = Int(
                        @inbounds(segment.offsets[destination + 1])
                    ) - 1
                    for segment_index in first_index:last_index
                        local record_index = Int(
                            @inbounds segment.records[segment_index]
                        )
                        if $record_active && @inbounds(
                                getproperty(
                                    record_valid, $(QuoteNode(name))
                                )[record_index]
                            )
                            accumulator = law.operation(
                                accumulator,
                                @inbounds(getproperty(
                                    record_values, $(QuoteNode(name))
                                )[record_index]),
                            )
                        end
                    end
                    @inbounds output[destination] = accumulator
                end
            end)
        elseif declaration <: _GenericResolvedOutput
            maximum = declaration.parameters[2]
            rank_order = declaration.parameters[5]
            identity_type = declaration.parameters[6]
            destination_present = G <: Val{true} ? :(true) : :(
                destination <= length(output)
            )
            record_active = F <: Val{true} ? :(true) : :(
                (record_index - 1) ÷ $maximum + 1 <= active_count
            )
            push!(expressions, quote
                local output = getproperty(outputs, $(QuoteNode(name)))
                if $destination_present
                    local declaration = getproperty(
                        declarations, $(QuoteNode(name))
                    )
                    local segment = getproperty(
                        segments, $(QuoteNode(name))
                    )
                    local first_index = Int(@inbounds segment.offsets[destination])
                    local last_index = Int(
                        @inbounds(segment.offsets[destination + 1])
                    ) - 1
                    local found = false
                    local winner_rank = $(QuoteNode(rank_order)) === :min ?
                        declaration.rank.upper : declaration.rank.lower
                    local winner_identity = typemax($identity_type)
                    local winner_value = declaration.empty
                    for segment_index in first_index:last_index
                        local record_index = Int(
                            @inbounds segment.records[segment_index]
                        )
                        if $record_active && @inbounds(
                                getproperty(
                                    record_valid, $(QuoteNode(name))
                                )[record_index]
                            )
                            local rank = @inbounds getproperty(
                                record_ranks, $(QuoteNode(name))
                            )[record_index]
                            local identity = @inbounds getproperty(
                                semantic_ids, $(QuoteNode(name))
                            )[record_index]
                            local better_rank = $(QuoteNode(rank_order)) === :min ?
                                rank < winner_rank : rank > winner_rank
                            local wins = !found || better_rank ||
                                (rank == winner_rank &&
                                 identity < winner_identity)
                            if wins
                                found = true
                                winner_rank = rank
                                winner_identity = identity
                                winner_value = @inbounds getproperty(
                                    record_values, $(QuoteNode(name))
                                )[record_index]
                            end
                        end
                    end
                    @inbounds output[destination] = winner_value
                end
            end)
        end
    end
    return Expr(:block, expressions..., :(nothing))
end

function _validate_combined_route(topology, name, output, item_count)
    hasproperty(topology.routes, output.route) || throw(
        LocalWorkValidationError(
            "combined port $name has no topology route $(output.route)"
        )
    )
    hasproperty(topology.destination_counts, name) || throw(
        LocalWorkValidationError(
            "combined port $name has no destination count"
        )
    )
    route = getproperty(topology.routes, output.route)
    maximum = typeof(output).parameters[2]
    route isa AbstractMatrix && size(route) == (maximum, item_count) ||
        throw(LocalWorkValidationError(
            "combined route $(output.route) has the wrong matrix shape"
        ))
    isconcretetype(eltype(route)) && eltype(route) <: Integer || throw(
        LocalWorkValidationError(
            "combined route $(output.route) requires a concrete integer type"
        )
    )
    destination_count = try
        Int(getproperty(topology.destination_counts, name))
    catch
        throw(LocalWorkValidationError(
            "combined destination count is not representable as Int"
        ))
    end
    destination_count >= 0 || throw(LocalWorkValidationError(
        "combined destination count must be nonnegative"
    ))
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        destination_count,
        Symbol(name, :_destination_count),
    )
    capacity = invoke(
        _checked_int_product,
        Tuple{Integer, Integer, Any},
        item_count,
        maximum,
        Symbol(name, :_record_capacity),
    )
    capacity == length(route) || throw(LocalWorkValidationError(
        "combined route $(output.route) has inconsistent capacity"
    ))
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        capacity,
        Symbol(name, :_record_capacity);
        terminal = true,
    )
    for value in route
        destination = try
            Int(value)
        catch
            throw(LocalWorkValidationError(
                "combined route contains an unrepresentable destination"
            ))
        end
        0 <= destination <= destination_count || throw(
            LocalWorkValidationError(
                "combined route contains a negative or out-of-domain destination"
            )
        )
    end
    return route, destination_count
end

function _canonical_segments(route, destination_count)
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        length(route),
        :buffered_record_count;
        terminal = true,
    )
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        destination_count,
        :buffered_destination_count,
    )
    buckets = [Int32[] for _ in 1:destination_count]
    for record_index in eachindex(route)
        destination = Int(route[record_index])
        destination == 0 || push!(buckets[destination], Int32(record_index))
    end
    offsets = Vector{Int32}(undef, destination_count + 1)
    records = Int32[]
    offsets[1] = Int32(1)
    for destination in 1:destination_count
        append!(records, buckets[destination])
        length(records) < typemax(Int32) || throw(
            LocalWorkValidationError(
                "combined record capacity leaves no Int32 terminal offset"
            )
        )
        offsets[destination + 1] = Int32(length(records) + 1)
    end
    return (; offsets, records)
end

function _validate_combination_capability(backend, output::_CombinedOutput)
    law = output.combine
    mode = typeof(law).parameters[1]
    law isa _CombinationLaw && mode in (:deterministic, :fast) || throw(
        LocalWorkValidationError(
            "combined output requires a centrally declared deterministic or fast law"
        )
    )
    output.value_type in (Int32, UInt32, Float32) || throw(
        LocalWorkValidationError(
            "combined value type is outside the centrally qualified profile"
        )
    )
    law.operation === (+) || throw(LocalWorkValidationError(
        "the initial combined profile centrally qualifies addition only"
    ))
    iszero(law.identity) || throw(LocalWorkValidationError(
        "qualified addition requires its exact zero identity"
    ))
    if mode === :fast
        invoke(
            _centrally_qualified_atomic_capability,
            Tuple{Any, Type, Symbol, Symbol},
            backend, output.value_type, :add, :global,
        ) || throw(LocalWorkValidationError(
            "backend x value type x atomic add x address space is not qualified"
        ))
    elseif mode === :deterministic
        invoke(
            _centrally_qualified_value_capability,
            Tuple{Any, Type, Symbol, Symbol},
            backend, output.value_type, :store, :global,
        ) || throw(LocalWorkValidationError(
            "backend x combined type x store x address space is not qualified"
        ))
    else
        throw(LocalWorkValidationError(
            "combined output has an unrecognized combination mode"
        ))
    end
    return nothing
end

function _lower_combined(work::LocalWork, topology, backend)
    isbitstype(typeof(work.operation)) || throw(LocalWorkValidationError(
        "generic local-work operations must be concrete isbits callables"
    ))
    item_count = invoke(
        _generic_topology_header, Tuple{Any, Any}, work, topology
    )
    validated = map(keys(work.outputs)) do name
        output = getproperty(work.outputs, name)
        if output isa _IndependentOutput
            invoke(
                _validate_independent_route,
                Tuple{Any, Any, Any, _IndependentOutput, Any},
                work, topology, name, output, item_count,
            )
        else
            invoke(
                _validate_combined_route,
                Tuple{Any, Any, Any, Any},
                topology, name, output, item_count,
            )
        end
    end
    routes = NamedTuple{keys(work.outputs)}(first.(validated))
    destination_counts = NamedTuple{keys(work.outputs)}(last.(validated))
    buffered_names = Tuple(
        name for (name, output) in pairs(work.outputs)
        if output isa _GenericResolvedOutput ||
            output isa _CombinedOutput &&
                typeof(output.combine).parameters[1] === :deterministic
    )
    segments = NamedTuple{buffered_names}(map(
        buffered_names
    ) do name
        invoke(
            _canonical_segments,
            Tuple{Any, Any},
            getproperty(routes, name),
            getproperty(destination_counts, name),
        )
    end)
    resolved_names = Tuple(
        name for (name, output) in pairs(work.outputs)
        if output isa _GenericResolvedOutput
    )
    hasproperty(topology, :semantic_ids) || isempty(resolved_names) || throw(
        LocalWorkValidationError(
            "generic resolved topology requires named semantic_ids"
        )
    )
    isempty(resolved_names) || topology.semantic_ids isa NamedTuple || throw(
        LocalWorkValidationError(
            "generic resolved semantic_ids must be a named tuple"
        )
    )
    semantic_ids = NamedTuple{resolved_names}(map(resolved_names) do name
        output = getproperty(work.outputs, name)
        hasproperty(topology.semantic_ids, name) || throw(
            LocalWorkValidationError(
                "resolved port $name has no semantic identity matrix"
            )
        )
        identities = getproperty(topology.semantic_ids, name)
        route = getproperty(routes, name)
        identities isa AbstractMatrix && size(identities) == size(route) ||
            throw(LocalWorkValidationError(
                "resolved semantic identities must match route shape"
            ))
        eltype(identities) === output.tie_break.type || throw(
            LocalWorkValidationError(
                "resolved semantic identities have the wrong type"
            )
        )
        seen = Dict{Int, Set{eltype(identities)}}()
        for record_index in eachindex(route)
            destination = Int(route[record_index])
            destination == 0 && continue
            bucket = get!(seen, destination) do
                Set{eltype(identities)}()
            end
            identity = identities[record_index]
            identity in bucket && throw(LocalWorkValidationError(
                "resolved semantic identities must be unique per destination"
            ))
            push!(bucket, identity)
        end
        identities
    end)
    for output in values(work.outputs)
        if output isa _CombinedOutput
            invoke(
                _validate_combination_capability,
                Tuple{Any, _CombinedOutput}, backend, output,
            )
        elseif output isa _IndependentOutput
            invoke(
                _centrally_qualified_value_capability,
                Tuple{Any, Type, Symbol, Symbol},
                backend, output.value_type, :store, :global,
            ) || throw(LocalWorkValidationError(
                "independent port store profile is not centrally qualified"
            ))
        else
            output.rank.type in (Int32, UInt32) || throw(
                LocalWorkValidationError(
                    "generic resolved rank type is outside the qualified profile"
                )
            )
            output.tie_break.type === UInt32 || throw(
                LocalWorkValidationError(
                    "generic resolved semantic identity must use UInt32"
                )
            )
            output.value_type in (Int32, UInt32, Float32) || throw(
                LocalWorkValidationError(
                    "generic resolved value type is outside the qualified profile"
                )
            )
            invoke(
                _centrally_qualified_value_capability,
                Tuple{Any, Type, Symbol, Symbol},
                backend, output.value_type, :store, :global,
            ) || throw(LocalWorkValidationError(
                "generic resolved value store profile is not qualified"
            ))
        end
    end
    has_deterministic = !isempty(buffered_names)
    has_fast = any(values(work.outputs)) do output
        output isa _CombinedOutput &&
            typeof(output.combine).parameters[1] === :fast
    end
    return _BufferedCombinedLowering(
        work.outputs,
        work.operation,
        work.reads,
        merge(topology, (; routes)),
        destination_counts,
        segments,
        semantic_ids,
        item_count,
        has_deterministic,
        has_fast,
        Symbol(
            "buffered_combined_",
            has_deterministic ? "canonical" : "",
            has_fast ? "fast" : "",
            "_v1",
        ),
    )
end

function _topology_fingerprint(topology, lowering::_BufferedCombinedLowering)
    io = IOBuffer()
    write(io, Int64(lowering.item_count))
    write(io, UInt64(invoke(_topology_epoch, Tuple{Any}, topology)))
    for name in keys(lowering.outputs)
        write(io, String(name))
        write(io, Int64(getproperty(lowering.destination_counts, name)))
        route = getproperty(lowering.topology.routes, name)
        write(io, Int64(size(route, 1)))
        write(io, Int64(size(route, 2)))
        for value in route
            write(io, value)
        end
        if hasproperty(lowering.segments, name)
            segment = getproperty(lowering.segments, name)
            foreach(value -> write(io, value), segment.offsets)
            foreach(value -> write(io, value), segment.records)
        end
        if hasproperty(lowering.semantic_ids, name)
            foreach(
                value -> write(io, value),
                getproperty(lowering.semantic_ids, name),
            )
        end
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

function _required_bindings(lowering::_BufferedCombinedLowering, work)
    return invoke(
        _unique_symbols,
        Tuple{Any},
        (collect(values(work.reads))..., collect(keys(work.outputs))...),
    )
end

function _binding_access(lowering::_BufferedCombinedLowering, work)
    names = invoke(
        _required_bindings,
        Tuple{_BufferedCombinedLowering, Any}, lowering, work,
    )
    output_names = keys(work.outputs)
    return NamedTuple{names}(map(
        name -> name in output_names ? :write : :read, names
    ))
end

function _validate_emission_result_type(work, result_type)
    result_type <: NamedTuple || throw(LocalWorkValidationError(
        "generic operation result must infer as a concrete NamedTuple"
    ))
    result_type.parameters[1] == keys(work.outputs) || throw(
        LocalWorkValidationError(
            "generic operation result names must exactly match output port names"
        )
    )
    result_types = result_type.parameters[2].parameters
    for (index, output) in pairs(values(work.outputs))
        maximum = typeof(output).parameters[2]
        port_type = invoke(
            _emission_result_type,
            Tuple{Any, Val{maximum}},
            result_types[index], Val(maximum),
        )
        port_type === nothing && throw(LocalWorkValidationError(
            "operation result has the wrong fixed emission arity"
        ))
        lane_types = maximum == 1 ? (port_type,) : port_type.parameters
        for lane_type in lane_types
            if output isa _GenericResolvedOutput
                lane_type <: Union{_Candidate, _ConditionalCandidate} ||
                    throw(LocalWorkValidationError(
                        "resolved operation results must use candidate(rank, value[, when])"
                    ))
                lane_type.parameters[1] === output.rank.type &&
                    lane_type.parameters[2] === output.value_type || throw(
                        LocalWorkValidationError(
                            "candidate rank/value types do not match the resolved port"
                        )
                    )
            else
                if !(lane_type <:
                        Union{_Emission, _ConditionalEmission})
                    throw(LocalWorkValidationError(
                        "combined/independent operation results must use emit(value[, when])"
                    ))
                end
                if lane_type.parameters[1] !== output.value_type
                    throw(LocalWorkValidationError(
                        "emitted value type does not match its output port"
                    ))
                end
                if output isa _IndependentOutput &&
                        typeof(output).parameters[4] === :all &&
                        lane_type <: _ConditionalEmission
                    throw(
                        LocalWorkValidationError(
                            "full-coverage independent ports require unconditional emissions"
                        )
                    )
                end
            end
        end
    end
    return nothing
end

function _validate_binding_schema(
        lowering::_BufferedCombinedLowering,
        work,
        storage,
        schema,
        backend,
    )
    for (name, output) in pairs(work.outputs)
        facts = invoke(
            _binding_facts, Tuple{Any, Any, Any}, storage, schema, name
        )
        facts.element_type === output.value_type || throw(
            LocalWorkValidationError(
                "output binding $name has the wrong element type"
            )
        )
        facts.dimensions == 1 && facts.size == (
            getproperty(lowering.destination_counts, name),
        ) || throw(LocalWorkValidationError(
            "output binding $name has the wrong shape"
        ))
    end
    result_type = invoke(
        _operation_result_type,
        Tuple{Any, Any, Any}, work, storage, schema,
    )
    invoke(
        _validate_emission_result_type,
        Tuple{Any, Any}, work, result_type,
    )
    return nothing
end

function _operation_call_facts(
        lowering::_BufferedCombinedLowering, work, storage, schema
    )
    signature = invoke(
        _operation_call_signature,
        Tuple{Any, Any, Any},
        work,
        storage,
        schema,
    )
    operation_fact = (
        callback = work.operation,
        signature,
        method = which(work.operation, signature),
        purpose = :local_operation,
    )
    law_facts = Tuple(
        (
            callback = output.combine.operation,
            signature = Tuple{output.value_type, output.value_type},
            method = which(
                output.combine.operation,
                Tuple{output.value_type, output.value_type},
            ),
            purpose = Symbol(name, :_combination_operation),
        )
        for (name, output) in pairs(work.outputs)
        if output isa _CombinedOutput &&
            typeof(output.combine).parameters[1] === :deterministic
    )
    return (operation_fact, law_facts...)
end

function _prepare_lowering(
        lowering::_BufferedCombinedLowering,
        work,
        storage,
        workspace,
        backend,
    )
    copy_signature = backend isa KernelAbstractions.CPU ?
        Tuple{KernelAbstractions.CPU, Any} :
        Tuple{KernelAbstractions.Backend, Any}
    routes = NamedTuple{keys(lowering.outputs)}(map(
        keys(lowering.outputs)
    ) do name
        invoke(
            _device_copy, copy_signature, backend,
            getproperty(lowering.topology.routes, name),
        )
    end)
    segments = NamedTuple{keys(lowering.segments)}(map(
        keys(lowering.segments)
    ) do name
        segment = getproperty(lowering.segments, name)
        (
            offsets = invoke(
                _device_copy, copy_signature, backend, segment.offsets
            ),
            records = invoke(
                _device_copy, copy_signature, backend, segment.records
            ),
        )
    end)
    semantic_ids = NamedTuple{keys(lowering.semantic_ids)}(map(
        keys(lowering.semantic_ids)
    ) do name
        invoke(
            _device_copy, copy_signature, backend,
            vec(getproperty(lowering.semantic_ids, name)),
        )
    end)
    if length(lowering.outputs) == 1 &&
            first(values(lowering.outputs)) isa _GenericResolvedOutput
        return invoke(
            _prepare_single_resolved_runtime,
            Tuple{
                _BufferedCombinedLowering,
                Any,
                Any,
                Any,
                Any,
            },
            lowering,
            work,
            backend,
            segments,
            semantic_ids,
        )
    end
    return _PreparedBufferedCombined(
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any}, _combined_clear_kernel!, backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any}, _combined_apply_kernel!, backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any}, _combined_publish_kernel!, backend,
        ),
        routes,
        segments,
        semantic_ids,
    )
end

function _record_arrays(lowering, workspace)
    names = keys(lowering.segments)
    isempty(names) && return (;), (;), (;)
    records = invoke(_deterministic_workspace, Tuple{Any}, workspace)
    values_tuple = NamedTuple{names}(map(
        name -> getproperty(records, name).values, names
    ))
    valid_tuple = NamedTuple{names}(map(
        name -> getproperty(records, name).valid, names
    ))
    resolved_names = keys(lowering.semantic_ids)
    rank_tuple = NamedTuple{resolved_names}(map(
        name -> getproperty(records, name).ranks, resolved_names
    ))
    return values_tuple, rank_tuple, valid_tuple
end

function _execute_lowering!(
        runtime::_PreparedBufferedCombined,
        lowering::_BufferedCombinedLowering,
        work,
        bindings,
        workspace,
        submission,
    )
    reads = NamedTuple{keys(work.reads)}(map(
        name -> getproperty(bindings, name), values(work.reads)
    ))
    outputs = NamedTuple{keys(work.outputs)}(map(
        name -> getproperty(bindings, name), keys(work.outputs)
    ))
    record_values, record_ranks, record_valid = invoke(
        _record_arrays, Tuple{Any, Any}, lowering, workspace
    )
    scalar_values = invoke(
        _scalar_values,
        Tuple{NamedTuple},
        submission,
    )
    active_count = work.active === nothing ? lowering.item_count :
                   Int(getproperty(submission, work.active))
    0 <= active_count <= lowering.item_count || throw(
        LocalWorkValidationError(
            "active selection exceeds the planned item capacity"
        )
    )
    maximum_destination = isempty(lowering.destination_counts) ? 0 :
        maximum(values(lowering.destination_counts))
    launches = 0
    if lowering.has_fast
        runtime.clear_kernel(
            work.outputs, outputs, Int32(maximum_destination);
            ndrange = max(maximum_destination, 1),
        )
        launches += 1
    end
    runtime.apply_kernel(
        work.operation,
        reads,
        scalar_values,
        work.outputs,
        outputs,
        runtime.device_routes,
        record_values,
        record_ranks,
        record_valid,
        Int32(active_count);
        ndrange = max(active_count, 1),
    )
    launches += 1
    if lowering.has_deterministic
        runtime.publish_kernel(
            work.outputs,
            outputs,
            runtime.device_segments,
            runtime.device_semantic_ids,
            record_values,
            record_ranks,
            record_valid,
            Int32(maximum_destination),
            Int32(active_count),
            Val(work.active === nothing),
            Val(all(==(maximum_destination), values(
                lowering.destination_counts
            )));
            ndrange = max(maximum_destination, 1),
        )
        launches += 1
    end
    return launches
end
