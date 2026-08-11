# Inspection and evidence for the generic buffered mechanism, split from the
# lowering implementation to keep each review unit bounded.

function _combined_determinism(backend, lowering)
    port_modes = NamedTuple{keys(lowering.outputs)}(map(
        values(lowering.outputs)
    ) do output
        output isa _IndependentOutput ? :independent :
        output isa _GenericResolvedOutput ? :resolved :
        typeof(output.combine).parameters[1]
    end)
    qualifier = (
        backend = nameof(typeof(backend)),
        lowering_identity = lowering.lowering_identity,
        port_modes,
    )
    any_fast = lowering.has_fast
    guarantees = any_fast ? (
        :not_claimed_for_fast_ports,
        :not_claimed_for_fast_ports,
        :canonical_for_deterministic_ports,
        :not_claimed_for_fast_ports,
        :not_claimed_for_fast_ports,
        :not_claimed,
        :qualified_atomic_or_canonical_fold,
        :domain_owned,
    ) : (
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :qualified_same_backend_operation,
        :not_claimed,
        :canonical_declared_operation,
        :domain_owned,
    )
    return NamedTuple{_DETERMINISM_DIMENSIONS}(
        map(guarantee -> merge(qualifier, (; guarantee)), guarantees)
    )
end

function _combined_port_determinism(backend, lowering, name, output)
    mode = output isa _IndependentOutput ? :independent :
        output isa _GenericResolvedOutput ? :resolved :
        typeof(output.combine).parameters[1]
    qualifier = (
        backend = nameof(typeof(backend)),
        lowering_identity = lowering.lowering_identity,
        port = name,
        mode,
    )
    guarantees = mode === :fast ? (
        :not_claimed,
        :not_claimed,
        :not_claimed,
        :not_claimed,
        :not_claimed,
        :not_claimed,
        :qualified_atomic_operation,
        :domain_owned,
    ) : mode === :independent ? (
        :qualified_disjoint_publication,
        :qualified_disjoint_publication,
        :not_applicable,
        :qualified_disjoint_publication,
        :qualified_same_backend_operation,
        :not_claimed,
        :caller_operation_responsibility,
        :domain_owned,
    ) : (
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :canonical_item_local_slot,
        :qualified_same_backend_operation,
        :not_claimed,
        mode === :resolved ? :exact_total_rank_and_identity :
        :canonical_declared_operation,
        :domain_owned,
    )
    return NamedTuple{_DETERMINISM_DIMENSIONS}(
        map(guarantee -> merge(qualifier, (; guarantee)), guarantees)
    )
end

function _combined_port_law(output)
    output isa _IndependentOutput && return (
        kind = :independent,
        coverage = typeof(output).parameters[4],
    )
    output isa _GenericResolvedOutput && return (
        kind = :resolved,
        rank = output.rank,
        tie_break = output.tie_break,
        empty = output.empty,
    )
    return (
        kind = :combined,
        mode = typeof(output.combine).parameters[1],
        operation = output.combine.operation,
        identity = output.combine.identity,
    )
end

function _combined_workspace_evidence(lowering)
    ports = NamedTuple{keys(lowering.segments)}(map(
        keys(lowering.segments)
    ) do name
        output = getproperty(lowering.outputs, name)
        capacity = invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            lowering.item_count,
            typeof(output).parameters[2],
            Symbol(name, :_record_capacity),
        )
        (
            capacity,
            value_type = output.value_type,
            value_bytes = invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                capacity,
                sizeof(output.value_type),
                Symbol(name, :_record_value_bytes),
            ),
            rank_bytes = output isa _GenericResolvedOutput ?
                invoke(
                    _checked_int_product,
                    Tuple{Integer, Integer, Any},
                    capacity,
                    sizeof(output.rank.type),
                    Symbol(name, :_record_rank_bytes),
                ) : 0,
            validity_bytes = invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                capacity,
                sizeof(Bool),
                Symbol(name, :_record_validity_bytes),
            ),
        )
    end)
    total_bytes = 0
    for port in values(ports)
        for bytes in (port.value_bytes, port.rank_bytes, port.validity_bytes)
            total_bytes = invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                total_bytes,
                bytes,
                :combined_workspace_bytes,
            )
        end
    end
    return (; ports, total_bytes)
end

function _lowering_evidence(
        lowering::_BufferedCombinedLowering, work, topology, backend
    )
    ports = NamedTuple{keys(lowering.outputs)}(map(
        keys(lowering.outputs)
    ) do name
        output = getproperty(lowering.outputs, name)
        route = getproperty(lowering.topology.routes, name)
        (
            family = output isa _IndependentOutput ? :independent :
                output isa _GenericResolvedOutput ? :resolved : :combined,
            route = output.route,
            mode = output isa _IndependentOutput ? :disjoint :
                output isa _GenericResolvedOutput ? :resolved :
                typeof(output.combine).parameters[1],
            coverage = output isa _IndependentOutput ?
                typeof(output).parameters[4] : :not_applicable,
            law = invoke(_combined_port_law, Tuple{Any}, output),
            maximum_emissions = typeof(output).parameters[2],
            destination_count = getproperty(lowering.destination_counts, name),
            route_bytes = invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                length(route),
                sizeof(eltype(route)),
                Symbol(name, :_route_bytes),
            ),
            publication_phase = output isa _IndependentOutput ? :apply :
                output isa _CombinedOutput &&
                    typeof(output.combine).parameters[1] === :fast ?
                    :apply : :publish_canonical,
            post_launch_failure_visibility = output isa _IndependentOutput ||
                output isa _CombinedOutput &&
                    typeof(output.combine).parameters[1] === :fast ?
                    :may_be_partially_visible :
                    :publication_phase_is_not_transactional,
            empty_destination = output isa _IndependentOutput ?
                typeof(output).parameters[4] === :all ?
                    :not_possible_by_total_coverage : :preserve_existing :
                output isa _GenericResolvedOutput ? output.empty :
                output.combine.identity,
            determinism = invoke(
                _combined_port_determinism,
                Tuple{Any, Any, Any, Any},
                backend,
                lowering,
                name,
                output,
            ),
        )
    end)
    segment_bytes = foldl(keys(lowering.segments); init = 0) do total, name
        segment = getproperty(lowering.segments, name)
        offset_bytes = invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            sizeof(eltype(segment.offsets)),
            length(segment.offsets),
            Symbol(name, :_segment_offset_bytes),
        )
        record_bytes = invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            sizeof(eltype(segment.records)),
            length(segment.records),
            Symbol(name, :_segment_record_bytes),
        )
        invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            total,
            invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                offset_bytes,
                record_bytes,
                Symbol(name, :_segment_bytes),
            ),
            :combined_segment_bytes,
        )
    end
    identity_bytes = foldl(keys(lowering.semantic_ids); init = 0) do total, name
        identities = getproperty(lowering.semantic_ids, name)
        invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            total,
            invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                sizeof(eltype(identities)),
                length(identities),
                Symbol(name, :_identity_bytes),
            ),
            :combined_identity_bytes,
        )
    end
    launch_count = 1 + Int(lowering.has_fast) +
        Int(lowering.has_deterministic)
    return (
        family = :buffered,
        lowering_identity = lowering.lowering_identity,
        launch_count,
        phases = reduce(
            (left, right) -> (left..., right...),
            (
                lowering.has_fast ? (:initialize_fast,) : (),
                (:apply,),
                lowering.has_deterministic ? (:publish_canonical,) : (),
            ),
        ),
        workspace = invoke(
            _combined_workspace_evidence, Tuple{Any}, lowering
        ),
        topology_transfer_bytes = foldl(
            (
                (port.route_bytes for port in values(ports))...,
                segment_bytes,
                identity_bytes,
            );
            init = 0,
        ) do total, bytes
            invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                total,
                bytes,
                :combined_topology_transfer_bytes,
            )
        end,
        capability = (
            backend = typeof(backend),
            compiler = merge(invoke(
                _centrally_qualified_provider_compiler_identity,
                Tuple{Any}, backend,
            ), (; atomix = Base.pkgversion(Atomix))),
            ports,
        ),
        determinism = invoke(
            _combined_determinism, Tuple{Any, Any}, backend, lowering
        ),
        ports,
    )
end

function _lowering_inspection(
        runtime::_PreparedBufferedCombined,
        lowering::_BufferedCombinedLowering,
        work,
        workspace,
    )
    phases = (
        lowering.has_fast ? (:initialize_fast,) : (),
        (:apply,),
        lowering.has_deterministic ? (:publish_canonical,) : (),
    )
    return (
        family = :buffered,
        phases = reduce((left, right) -> (left..., right...), phases),
        launches = 1 + Int(lowering.has_fast) +
            Int(lowering.has_deterministic),
        operation_invocations = :once_per_active_item,
        device_routes = keys(runtime.device_routes),
        deterministic_segments = keys(runtime.device_segments),
    )
end
