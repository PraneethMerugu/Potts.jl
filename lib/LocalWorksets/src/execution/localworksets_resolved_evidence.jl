# Inspection evidence for the preserved resolved-selection parity lowering.
# Kept separate so the executable lowering remains a bounded review unit.

function _resolved_determinism(backend, lowering)
    qualifier = (
        backend = nameof(typeof(backend)),
        key_type = lowering.output.key_type,
        rank_type = lowering.output.rank.type,
        identity_type = lowering.output.tie_break.type,
        value_type = lowering.output.value_type,
        atomic_operation = lowering.output.rank.order,
        address_space = :global,
        compiler = merge(
            invoke(
                _centrally_qualified_provider_compiler_identity,
                Tuple{Any},
                backend,
            ),
            (; atomix = Base.pkgversion(Atomix)),
        ),
        lowering_identity = lowering.lowering_identity,
    )
    guarantees = (
        :qualified_exact_integer_order,
        :not_claimed,
        :not_applicable,
        :qualified_exact_integer_order,
        :qualified_exact_integer_order,
        :not_claimed,
        :exact_for_declared_integer_order,
        :domain_owned,
    )
    return NamedTuple{_DETERMINISM_DIMENSIONS}(
        map(guarantee -> merge(qualifier, (; guarantee)), guarantees)
    )
end

function _lowering_evidence(
        lowering::_ResolvedWinnerLowering, work, topology, backend
    )
    rank_type = lowering.output.rank.type
    identity_type = lowering.output.tie_break.type
    rank_bytes = invoke(
        _checked_int_product,
        Tuple{Integer, Integer, Any},
        lowering.destination_count,
        sizeof(rank_type),
        :resolved_rank_workspace_bytes,
    )
    identity_bytes = invoke(
        _checked_int_product,
        Tuple{Integer, Integer, Any},
        lowering.destination_count,
        sizeof(identity_type),
        :resolved_identity_workspace_bytes,
    )
    workspace = (
        destination_count = lowering.destination_count,
        rank = (
            element_type = rank_type,
            length = lowering.destination_count,
            alignment = Base.datatype_alignment(rank_type),
            bytes = rank_bytes,
        ),
        identity = (
            element_type = identity_type,
            length = lowering.destination_count,
            alignment = Base.datatype_alignment(identity_type),
            bytes = identity_bytes,
        ),
        total_bytes = invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            rank_bytes,
            identity_bytes,
            :resolved_total_workspace_bytes,
        ),
    )
    capability = (
        backend = typeof(backend),
        compiler = merge(
            invoke(
                _centrally_qualified_provider_compiler_identity,
                Tuple{Any},
                backend,
            ),
            (; atomix = Base.pkgversion(Atomix)),
        ),
        key_type = lowering.output.key_type,
        rank_type,
        identity_type,
        value_type = lowering.output.value_type,
        atomic_operation = lowering.output.rank.order,
        address_space = :global,
    )
    determinism = invoke(
        _resolved_determinism,
        Tuple{Any, Any},
        backend,
        lowering,
    )
    port = (
        family = :resolved,
        route = lowering.output.destinations,
        destination_count = lowering.destination_count,
        maximum_emissions = 1,
        coverage = :not_applicable,
        law = (
            kind = :resolved,
            rank = lowering.output.rank,
            tie_break = lowering.output.tie_break,
            empty = lowering.output.empty,
            emission_mask = lowering.operation.emission.mask,
            mask_binding = lowering.output.mask,
        ),
        publication_phase = :publication,
        post_launch_failure_visibility = :publication_phase_is_not_transactional,
        empty_destination = lowering.output.empty,
        determinism,
    )
    return (
        family = :resolved_selection,
        lowering_identity = lowering.lowering_identity,
        launch_count = 4,
        phases = (
            :initialize_rank,
            :rank_arbitration,
            :identity_arbitration,
            :publication,
        ),
        workspace,
        topology_transfer_bytes = invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            lowering.item_count,
            invoke(
                _checked_int_sum,
                Tuple{Integer, Integer, Any},
                sizeof(lowering.output.key_type),
                sizeof(identity_type),
                :resolved_transfer_record_bytes,
            ),
            :resolved_topology_transfer_bytes,
        ),
        capability,
        determinism,
        ports = NamedTuple{(lowering.output_name,)}((port,)),
    )
end
