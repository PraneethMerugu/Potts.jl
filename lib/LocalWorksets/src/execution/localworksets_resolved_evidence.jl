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
    return invoke(
        _determinism_report,
        Tuple{NamedTuple, NTuple{8, Symbol}},
        qualifier,
        guarantees,
    )
end

function _lowering_evidence(
        lowering::_ResolvedWinnerLowering, work, topology, backend
    )
    workspace_spec = invoke(
        _centrally_owned_workspace_spec,
        Tuple{Any, Any},
        lowering,
        work,
    )
    rank_type = lowering.output.rank.type
    identity_type = lowering.output.tie_break.type
    workspace = invoke(
        _winner_workspace_evidence,
        Tuple{Tuple, Int, Symbol, Symbol},
        workspace_spec,
        lowering.destination_count,
        :winner_ranks,
        :winner_identities,
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
    port = invoke(
        _port_evidence,
        Tuple{
            Symbol, Any, Int, Int, Symbol, NamedTuple, Symbol,
            Symbol, Any, NamedTuple, NamedTuple,
        },
        :resolved,
        lowering.output.destinations,
        lowering.destination_count,
        1,
        :not_applicable,
        (
            kind = :resolved,
            rank = lowering.output.rank,
            tie_break = lowering.output.tie_break,
            empty = lowering.output.empty,
            emission_mask = lowering.operation.emission.mask,
            mask_binding = lowering.output.mask,
        ),
        :publication,
        :publication_phase_is_not_transactional,
        lowering.output.empty,
        determinism,
        (;),
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
            _centrally_count_topology_payload_bytes,
            Tuple{Any},
            invoke(
                _centrally_owned_static_topology_payload,
                Tuple{Any},
                lowering,
            ),
        ),
        capability,
        determinism,
        ports = NamedTuple{(lowering.output_name,)}((port,)),
    )
end
