# One bounded, domain-neutral two-key conjunctive resolved lowering. Dynamic
# routing and identities are submission/storage data; the central lowering
# fixes their exact proof law, result layout, workspace, and four launches.

struct _ConjunctiveResolvedOutput{D, E, R, T, K, V, S, U} <:
       _AbstractOutputDeclaration
    destinations::D
    empty::E
    rank::R
    tie_break::T
    capacity::Int
    key_type::K
    value_type::V
    skipped_keys::S
    result::U
end

struct _ConjunctiveResolvedOperation{E}
    eligible::E
end

struct _ConjunctiveResolvedLowering{O, P, R, T, S, I}
    output_name::Symbol
    output::O
    operation::P
    reads::R
    topology::T
    item_count::Int
    destination_count::Int
    sentinel_rank::S
    sentinel_identity::I
    lowering_identity::Symbol
end

mutable struct _PreparedConjunctiveResolved{K1, K2, K3, K4}
    clear_kernel::K1
    rank_kernel::K2
    identity_kernel::K3
    select_kernel::K4
end

_static_topology_payload(::_ConjunctiveResolvedLowering) = (;)

function _workspace_spec(lowering::_ConjunctiveResolvedLowering, work)
    return (
        _workspace_leaf(
            :winner_ranks,
            (:winner_ranks,),
            UInt32,
            (lowering.destination_count,);
            strides = (1,),
            role = :winner_rank,
        ),
        _workspace_leaf(
            :winner_identities,
            (:winner_identities,),
            UInt32,
            (lowering.destination_count,);
            strides = (1,),
            role = :winner_identity,
        ),
    )
end

function resolved(
        destinations::NTuple{2, Symbol};
        empty,
        rank,
        tie_break,
        capacity::Integer,
        key_type::Type,
        value_type::Type,
        skipped_keys,
        result,
        mask = nothing,
    )
    0 <= capacity <= typemax(Int32) || throw(ArgumentError(
        "resolved-output capacity must fit the bounded Int32 kernel ABI"
    ))
    mask === nothing || throw(ArgumentError(
        "the bounded conjunctive profile uses literal eligibility, not masked output"
    ))
    rank isa NamedTuple &&
        keys(rank) == (:type, :order, :lower, :upper) ||
        throw(ArgumentError(
            "conjunctive rank requires exactly type, order, lower, and upper"
        ))
    rank.type === UInt32 && rank.order === :max || throw(ArgumentError(
        "the bounded conjunctive profile requires UInt32 maximum rank"
    ))
    typeof(rank.lower) === UInt32 && typeof(rank.upper) === UInt32 &&
        rank.lower == UInt32(0) && rank.upper == typemax(UInt32) ||
        throw(ArgumentError(
            "the bounded conjunctive rank domain must be the complete UInt32 order"
        ))
    tie_break isa NamedTuple && keys(tie_break) == (
        :input_type, :type, :order, :transform, :proof,
    ) || throw(ArgumentError(
        "conjunctive tie break requires input_type, type, order, transform, and proof"
    ))
    tie_break == (
        input_type = Int32,
        type = UInt32,
        order = :min,
        transform = :checked_unsigned,
        proof = :strictly_increasing_active_prefix,
    ) || throw(ArgumentError(
        "the bounded conjunctive profile requires checked increasing Int32 identities"
    ))
    key_type === Int32 || throw(ArgumentError(
        "the bounded conjunctive profile requires Int32 destination keys"
    ))
    value_type === UInt8 || throw(ArgumentError(
        "the bounded conjunctive profile requires UInt8 item values"
    ))
    skipped_keys === :nonpositive || throw(ArgumentError(
        "the bounded conjunctive profile skips exactly nonpositive keys"
    ))
    result isa NamedTuple && keys(result) == (
        :layout, :selection, :zero_claim, :selected, :ineligible,
    ) || throw(ArgumentError(
        "conjunctive result requires layout, selection, zero_claim, selected, and ineligible"
    ))
    result == (
        layout = :items,
        selection = :all,
        zero_claim = :selected,
        selected = :preserve,
        ineligible = :preserve,
    ) || throw(ArgumentError(
        "the bounded conjunctive item-result semantics are fixed"
    ))
    typeof(empty) === UInt8 || throw(ArgumentError(
        "the conjunctive empty result must have the declared UInt8 value type"
    ))
    return _ConjunctiveResolvedOutput(
        destinations,
        empty,
        rank,
        tie_break,
        Int(capacity),
        key_type,
        value_type,
        skipped_keys,
        result,
    )
end

function _inspect_output(output::_ConjunctiveResolvedOutput)
    return (
        family = :resolved,
        destinations = output.destinations,
        empty = output.empty,
        rank = output.rank,
        tie_break = output.tie_break,
        capacity = output.capacity,
        key_type = output.key_type,
        value_type = output.value_type,
        skipped_keys = output.skipped_keys,
        result = output.result,
    )
end

function _conjunctive_operation(operation, output)
    operation isa NamedTuple && keys(operation) == (
        :family, :eligible,
    ) || throw(LocalWorkValidationError(
        "conjunctive resolution requires exactly family and eligible"
    ))
    operation.family === :resolved_conjunctive_selection ||
        throw(LocalWorkValidationError(
            "the operation family has no bounded conjunctive lowering"
        ))
    typeof(operation.eligible) === output.value_type ||
        throw(LocalWorkValidationError(
            "the conjunctive eligible literal has the wrong value type"
        ))
    operation.eligible != output.empty || throw(LocalWorkValidationError(
        "eligible and losing values must be distinct"
    ))
    return _ConjunctiveResolvedOperation(operation.eligible)
end

function _conjunctive_reads(work::LocalWork)
    required = (:gate, :identity, :key_a, :key_b, :rank, :value)
    Tuple(keys(work.reads)) == required || throw(LocalWorkValidationError(
        "conjunctive reads require exactly gate, identity, key_a, key_b, rank, and value"
    ))
    all(value -> value isa Symbol, values(work.reads)) ||
        throw(LocalWorkValidationError(
            "conjunctive logical reads must map roles to binding names"
        ))
    length(unique(values(work.reads))) == length(work.reads) ||
        throw(LocalWorkValidationError(
            "conjunctive logical read bindings must be distinct"
        ))
    return work.reads
end

function _conjunctive_topology(work, topology, output)
    required = (:item_count, :destination_count, :epoch)
    invoke(
        _require_properties,
        Tuple{Any, Tuple, Any},
        topology,
        required,
        :conjunctive_topology,
    )
    invoke(
        _validate_topology_epoch,
        Tuple{Any, Any},
        topology,
        :conjunctive,
    )
    item_count = invoke(
        _bounded_count,
        Tuple{Any, Any},
        topology.item_count,
        :conjunctive_item_count,
        positive = true,
    )
    destination_count = invoke(
        _bounded_count,
        Tuple{Any, Any},
        topology.destination_count,
        :conjunctive_destination_count,
        positive = true,
    )
    invoke(
        _validate_item_domain,
        Tuple{LocalWork, Int, Any},
        work,
        item_count,
        :conjunctive_topology,
    )
    output.capacity == item_count || throw(LocalWorkValidationError(
        "conjunctive output capacity must exactly equal item capacity"
    ))
    work.active isa Symbol || throw(LocalWorkValidationError(
        "conjunctive work requires a bounded active-count submission value"
    ))
    return item_count, destination_count
end

function _validate_conjunctive_capability(backend, output)
    for (type, operation) in (
            (Int32, :load),
            (UInt32, :load),
            (UInt8, :load),
            (Bool, :load),
            (UInt8, :store),
        )
        invoke(
            _centrally_qualified_value_capability,
            Tuple{Any, Type, Symbol, Symbol},
            backend,
            type,
            operation,
            :global,
        ) || throw(LocalWorkValidationError(
            "backend × value type × operation × address-space is not qualified"
        ))
    end
    for operation in (:max, :min)
        invoke(
            _centrally_qualified_atomic_capability,
            Tuple{Any, Type, Symbol, Symbol},
            backend,
            UInt32,
            operation,
            :global,
        ) || throw(LocalWorkValidationError(
            "backend × UInt32 atomic operation × global address-space is not qualified"
        ))
    end
    return nothing
end

function _lower_conjunctive_resolved(work::LocalWork, topology, backend)
    length(work.outputs) == 1 || throw(LocalWorkValidationError(
        "bounded conjunctive resolution implements one named output port"
    ))
    output_name = only(keys(work.outputs))
    output = only(values(work.outputs))
    output isa _ConjunctiveResolvedOutput ||
        throw(LocalWorkValidationError(
            "the conjunctive family requires its exact resolved output"
        ))
    reads = invoke(_conjunctive_reads, Tuple{LocalWork}, work)
    output.destinations == (reads.key_a, reads.key_b) ||
        throw(LocalWorkValidationError(
            "conjunctive destinations must match the two declared key bindings"
        ))
    output_name === reads.value || throw(LocalWorkValidationError(
        "the conjunctive item result must pointwise update its value binding"
    ))
    operation = invoke(
        _conjunctive_operation, Tuple{Any, Any}, work.operation, output
    )
    item_count, destination_count = invoke(
        _conjunctive_topology,
        Tuple{Any, Any, Any},
        work,
        topology,
        output,
    )
    invoke(
        _validate_conjunctive_capability,
        Tuple{Any, Any},
        backend,
        output,
    )
    return _ConjunctiveResolvedLowering(
        output_name,
        output,
        operation,
        reads,
        topology,
        item_count,
        destination_count,
        UInt32(0),
        typemax(UInt32),
        :resolved_conjunctive_two_key_UInt32_UInt8_v1,
    )
end

function _topology_fingerprint(topology, lowering::_ConjunctiveResolvedLowering)
    payload = (
        profile = lowering.lowering_identity,
        item_count = lowering.item_count,
        destination_count = lowering.destination_count,
        epoch = UInt64(invoke(_topology_epoch, Tuple{Any}, topology)),
        maximum_emissions = 2,
        skipped_keys = lowering.output.skipped_keys,
        result = lowering.output.result,
    )
    return bytes2hex(SHA.sha256(repr(payload)))
end

function _validate_binding_schema(
        lowering::_ConjunctiveResolvedLowering,
        work,
        storage,
        schema,
        backend,
    )
    reads = lowering.reads
    requirements = (
        _binding_requirement(
            reads.key_a, Int32, (lowering.item_count,), :read;
            role = :first_key,
        ),
        _binding_requirement(
            reads.key_b, Int32, (lowering.item_count,), :read;
            role = :second_key,
        ),
        _binding_requirement(
            reads.rank, UInt32, (lowering.item_count,), :read;
            role = :rank,
        ),
        _binding_requirement(
            reads.identity, Int32, (lowering.item_count,), :read;
            role = :identity,
        ),
        _binding_requirement(
            reads.value, UInt8, (lowering.item_count,), :readwrite;
            role = :item_result,
        ),
        _binding_requirement(
            reads.gate, Bool, (1,), :read;
            role = :gate,
        ),
    )
    return invoke(
        _validate_binding_requirements,
        Tuple{Any, Any, Tuple},
        storage,
        schema,
        requirements,
    )
end

function _required_bindings(lowering::_ConjunctiveResolvedLowering, work)
    reads = lowering.reads
    return invoke(
        _unique_symbols,
        Tuple{Any},
        (
            reads.key_a,
            reads.key_b,
            reads.rank,
            reads.identity,
            reads.value,
            reads.gate,
        ),
    )
end

function _binding_access(lowering::_ConjunctiveResolvedLowering, work)
    names = invoke(
        _required_bindings,
        Tuple{_ConjunctiveResolvedLowering, Any},
        lowering,
        work,
    )
    return NamedTuple{names}(map(names) do name
        name === lowering.reads.value ? :readwrite : :read
    end)
end

function _validate_workspace(
        lowering::_ConjunctiveResolvedLowering, work, workspace, backend
    )
    required = (:winner_ranks, :winner_identities)
    all(name -> hasproperty(workspace, name), required) ||
        throw(LocalWorkValidationError(
            "conjunctive workspace requires winner_ranks and winner_identities"
        ))
    return invoke(
        _validate_workspace_spec,
        Tuple{Any, Tuple, Any},
        workspace,
        invoke(
            _centrally_owned_workspace_spec,
            Tuple{Any, Any},
            lowering,
            work,
        ),
        backend,
    )
end

function _prepare_lowering(
        lowering::_ConjunctiveResolvedLowering,
        work,
        storage,
        workspace,
        backend,
    )
    return _PreparedConjunctiveResolved(
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _conjunctive_clear_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _conjunctive_rank_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _conjunctive_identity_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _conjunctive_select_kernel!,
            backend,
        ),
    )
end

@inline function _conjunctive_destination(key::Int32, destination_count::Int32)
    key <= Int32(0) && return 0
    key <= destination_count || error(
        "conjunctive destination is outside the prepared positive key domain"
    )
    return Int(key)
end

@inline function _conjunctive_rank_claim!(winners, destination, rank)
    destination == 0 && return nothing
    return _rank_claim!(winners, destination, rank, Val(:max))
end

@inline function _conjunctive_identity_claim!(
        ranks, identities, destination, rank, identity
    )
    destination == 0 && return nothing
    return _identity_claim!(ranks, identities, destination, rank, identity)
end

@inline function _conjunctive_wins(
        ranks, identities, destination, rank, identity
    )
    destination == 0 && return true
    return _is_winner(ranks, identities, destination, rank, identity)
end

@inline function _checked_conjunctive_identity(identities, item::Int)
    value = @inbounds identities[item]
    value > Int32(0) || error(
        "conjunctive identity must be positive"
    )
    if item > 1
        previous = @inbounds identities[item - 1]
        previous < value || error(
            "conjunctive active identities must be strictly increasing"
        )
    end
    return UInt32(value)
end

@kernel function _conjunctive_clear_kernel!(
        gate,
        winner_ranks,
        winner_identities,
        destination_count::Int32,
    )
    destination = @index(Global, Linear)
    if @inbounds(gate[1]) && destination <= destination_count
        @inbounds begin
            winner_ranks[destination] = UInt32(0)
            winner_identities[destination] = typemax(UInt32)
        end
    end
end

@kernel function _conjunctive_rank_kernel!(
        key_a,
        key_b,
        ranks,
        values,
        gate,
        winner_ranks,
        active_count::Int32,
        destination_count::Int32,
        eligible::UInt8,
    )
    item = @index(Global, Linear)
    if @inbounds(gate[1]) && item <= active_count &&
            @inbounds(values[item] == eligible)
        rank = @inbounds ranks[item]
        destination_a = _conjunctive_destination(
            @inbounds(key_a[item]), destination_count
        )
        destination_b = _conjunctive_destination(
            @inbounds(key_b[item]), destination_count
        )
        _conjunctive_rank_claim!(winner_ranks, destination_a, rank)
        _conjunctive_rank_claim!(winner_ranks, destination_b, rank)
    end
end

@kernel function _conjunctive_identity_kernel!(
        key_a,
        key_b,
        ranks,
        identities,
        values,
        gate,
        winner_ranks,
        winner_identities,
        active_count::Int32,
        destination_count::Int32,
        eligible::UInt8,
    )
    item = @index(Global, Linear)
    if @inbounds(gate[1]) && item <= active_count
        identity = _checked_conjunctive_identity(identities, item)
        if @inbounds values[item] == eligible
            rank = @inbounds ranks[item]
            destination_a = _conjunctive_destination(
                @inbounds(key_a[item]), destination_count
            )
            destination_b = _conjunctive_destination(
                @inbounds(key_b[item]), destination_count
            )
            _conjunctive_identity_claim!(
                winner_ranks,
                winner_identities,
                destination_a,
                rank,
                identity,
            )
            _conjunctive_identity_claim!(
                winner_ranks,
                winner_identities,
                destination_b,
                rank,
                identity,
            )
        end
    end
end

@kernel function _conjunctive_select_kernel!(
        key_a,
        key_b,
        ranks,
        identities,
        values,
        gate,
        winner_ranks,
        winner_identities,
        active_count::Int32,
        destination_count::Int32,
        eligible::UInt8,
        empty::UInt8,
    )
    item = @index(Global, Linear)
    if @inbounds(gate[1]) && item <= active_count &&
            @inbounds(values[item] == eligible)
        rank = @inbounds ranks[item]
        identity = UInt32(@inbounds identities[item])
        destination_a = _conjunctive_destination(
            @inbounds(key_a[item]), destination_count
        )
        destination_b = _conjunctive_destination(
            @inbounds(key_b[item]), destination_count
        )
        wins = _conjunctive_wins(
                   winner_ranks,
                   winner_identities,
                   destination_a,
                   rank,
                   identity,
               ) && _conjunctive_wins(
                   winner_ranks,
                   winner_identities,
                   destination_b,
                   rank,
                   identity,
               )
        wins || (@inbounds values[item] = empty)
    end
end

function _conjunctive_determinism(backend, lowering)
    qualifier = (
        backend = nameof(typeof(backend)),
        key_type = Int32,
        rank_type = UInt32,
        identity_input_type = Int32,
        identity_type = UInt32,
        value_type = UInt8,
        atomic_operations = (:max, :min),
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
        :qualified_for_two_slot_permutation,
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
        lowering::_ConjunctiveResolvedLowering, work, topology, backend
    )
    workspace_spec = invoke(
        _centrally_owned_workspace_spec,
        Tuple{Any, Any},
        lowering,
        work,
    )
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
        key_type = Int32,
        rank_type = UInt32,
        identity_input_type = Int32,
        identity_type = UInt32,
        value_type = UInt8,
        gate_type = Bool,
        atomic_operations = (:max, :min),
        address_space = :global,
    )
    determinism = invoke(
        _conjunctive_determinism,
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
        2,
        :not_applicable,
        (
            kind = :conjunctive_resolved,
            rank = lowering.output.rank,
            tie_break = lowering.output.tie_break,
            skipped_keys = lowering.output.skipped_keys,
            result = lowering.output.result,
        ),
        :publication,
        :publication_phase_is_not_transactional,
        :not_published_for_private_claim_destinations,
        determinism,
        (;
            result_count = lowering.item_count,
            publication_target = :item_result,
            result_layout = lowering.output.result.layout,
            empty_result = lowering.output.empty,
            private_key_no_winner_state = (
                rank = lowering.sentinel_rank,
                identity = lowering.sentinel_identity,
            ),
        ),
    )
    return (
        family = :resolved_conjunctive_selection,
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

function _execute_lowering!(
        runtime::_PreparedConjunctiveResolved,
        lowering::_ConjunctiveResolvedLowering,
        work,
        bindings,
        workspace,
        submission,
    )
    reads = lowering.reads
    key_a = getproperty(bindings, reads.key_a)
    key_b = getproperty(bindings, reads.key_b)
    ranks = getproperty(bindings, reads.rank)
    identities = getproperty(bindings, reads.identity)
    values = getproperty(bindings, reads.value)
    gate = getproperty(bindings, reads.gate)
    active_count = Int(getproperty(submission, work.active))
    0 <= active_count <= lowering.item_count ||
        throw(LocalWorkValidationError(
            "active_count exceeds the conjunctive item capacity"
        ))
    active_ndrange = max(active_count, 1)
    runtime.clear_kernel(
        gate,
        workspace.winner_ranks,
        workspace.winner_identities,
        Int32(lowering.destination_count);
        ndrange = lowering.destination_count,
    )
    runtime.rank_kernel(
        key_a,
        key_b,
        ranks,
        values,
        gate,
        workspace.winner_ranks,
        Int32(active_count),
        Int32(lowering.destination_count),
        lowering.operation.eligible;
        ndrange = active_ndrange,
    )
    runtime.identity_kernel(
        key_a,
        key_b,
        ranks,
        identities,
        values,
        gate,
        workspace.winner_ranks,
        workspace.winner_identities,
        Int32(active_count),
        Int32(lowering.destination_count),
        lowering.operation.eligible;
        ndrange = active_ndrange,
    )
    runtime.select_kernel(
        key_a,
        key_b,
        ranks,
        identities,
        values,
        gate,
        workspace.winner_ranks,
        workspace.winner_identities,
        Int32(active_count),
        Int32(lowering.destination_count),
        lowering.operation.eligible,
        lowering.output.empty;
        ndrange = active_ndrange,
    )
    return 4
end

function _lowering_inspection(
        runtime::_PreparedConjunctiveResolved,
        lowering::_ConjunctiveResolvedLowering,
        work,
        workspace,
    )
    workspace_spec = invoke(
        _centrally_owned_workspace_spec,
        Tuple{Any, Any},
        lowering,
        work,
    )
    return (
        family = :resolved_conjunctive_selection,
        phases = (
            :initialize_rank,
            :rank_arbitration,
            :identity_arbitration,
            :publication,
        ),
        profile = :bounded_conjunctive_selection,
        output_port = lowering.output_name,
        logical_reads = lowering.reads,
        destinations = lowering.output.destinations,
        routing = :submission_or_storage_bound_dynamic,
        maximum_emissions = 2,
        absent_key = :nonpositive,
        empty = lowering.output.empty,
        eligible = lowering.operation.eligible,
        rank = lowering.output.rank,
        tie_break = lowering.output.tie_break,
        result_layout = :items,
        selection = :all_emitted_destinations,
        zero_claim = :selected,
        masked_behavior = :preserve,
        selected_publication = :preserve,
        unselected_publication = :empty,
        alias_proof = :proven_pointwise_readwrite,
        launches = 4,
        topology_transfer_bytes = invoke(
            _centrally_count_topology_payload_bytes,
            Tuple{Any},
            invoke(
                _centrally_owned_static_topology_payload,
                Tuple{Any},
                lowering,
            ),
        ),
        workspace = invoke(
            _winner_workspace_inspection,
            Tuple{Any, Tuple, Symbol, Symbol},
            workspace,
            workspace_spec,
            :winner_ranks,
            :winner_identities,
        ),
    )
end
