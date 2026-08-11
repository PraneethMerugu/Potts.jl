# One narrow, centrally admitted resolved-selection lowering. This file owns
# its routing witness, physical binding derivation, capability qualification,
# workspace layout, kernels, and lowering identity. The lifecycle substrate in
# the generic lifecycle source files contain none of these mechanism choices.

struct _ResolvedOutput{D, E, R, T, K, V, M} <:
       _AbstractOutputDeclaration
    destinations::D
    empty::E
    rank::R
    tie_break::T
    capacity::Int
    key_type::K
    value_type::V
    mask::M
end

struct _ResolvedSelection{E}
    emission::E
end

struct _ResolvedWinnerLowering{O, P, R, T, S, I}
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

mutable struct _PreparedResolvedWinner{K1, K2, K3, K4, K, I}
    clear_kernel::K1
    rank_kernel::K2
    identity_kernel::K3
    publish_kernel::K4
    device_keys::K
    device_identities::I
end

function _central_admission(work::LocalWork, topology, backend)
    if work.operation isa _SequenceOperation
        admission_signature = Tuple{LocalWork, Any, Any}
        admission_method = which(_central_admission, admission_signature)
        admission_method.module === (@__MODULE__) ||
            throw(LocalWorkValidationError(
                "the central admission implementation is not package-owned"
            ))
        stages = map(work.operation.works) do stage
            invoke(
                _central_admission,
                admission_signature,
                stage,
                topology,
                backend,
            )
        end
        invoke(
            _validate_sequence,
            Tuple{Any, Any, Any, Any},
            stages,
            work.operation.works,
            topology,
            backend,
        )
        return _SequenceLowering(stages)
    elseif all(
            output -> output isa Union{
                _IndependentOutput,
                _CombinedOutput,
                _GenericResolvedOutput,
            },
            values(work.outputs),
        )
        return invoke(
            _lower_generic,
            Tuple{LocalWork, Any, Any},
            work,
            topology,
            backend,
        )
    elseif work.operation isa NamedTuple &&
            hasproperty(work.operation, :family) &&
            work.operation.family === :resolved_selection
        return invoke(
            _lower_resolved,
            Tuple{LocalWork, Any, Any},
            work,
            topology,
            backend,
        )
    elseif work.operation isa NamedTuple &&
            hasproperty(work.operation, :family) &&
            work.operation.family === :resolved_conjunctive_selection
        return invoke(
            _lower_conjunctive_resolved,
            Tuple{LocalWork, Any, Any},
            work,
            topology,
            backend,
        )
    end
    throw(LocalWorkValidationError(
        "the LocalWork declaration has no centrally admitted lowering"
    ))
end

function resolved(
        destinations::Symbol;
        empty,
        rank,
        tie_break,
        capacity::Union{Nothing, Integer} = nothing,
        key_type::Union{Nothing, Type} = nothing,
        value_type::Type,
        mask = nothing,
        maximum::Union{Nothing, Integer} = nothing,
    )
    isempty(String(destinations)) && throw(ArgumentError(
        "a resolved route name must be nonempty"
    ))
    if maximum !== nothing
        capacity === nothing && key_type === nothing || throw(ArgumentError(
            "generic resolved output does not accept legacy capacity/key_type"
        ))
        mask === nothing || throw(ArgumentError(
            "generic resolved masking is expressed by candidate(..., when)"
        ))
        1 <= maximum <= typemax(Int32) || throw(ArgumentError(
            "generic resolved maximum must be a positive Int32 bound"
        ))
        isconcretetype(value_type) && isbitstype(value_type) || throw(
            ArgumentError(
                "generic resolved value type must be concrete and isbits"
            )
        )
        typeof(empty) === value_type || throw(ArgumentError(
            "generic resolved empty result must have its declared value type"
        ))
        rank isa NamedTuple && keys(rank) ==
            (:type, :order, :lower, :upper) || throw(ArgumentError(
                "generic resolved rank requires type, order, lower, and upper"
            ))
        rank.type isa Type && isconcretetype(rank.type) &&
            isbitstype(rank.type) || throw(ArgumentError(
                "generic resolved rank type must be concrete and isbits"
            ))
        rank.order in (:min, :max) || throw(ArgumentError(
            "generic resolved rank order must be :min or :max"
        ))
        typeof(rank.lower) === rank.type &&
            typeof(rank.upper) === rank.type &&
            rank.lower <= rank.upper || throw(ArgumentError(
                "generic resolved rank bounds must be ordered exact values"
            ))
        tie_break isa NamedTuple && keys(tie_break) == (:type, :order) ||
            throw(ArgumentError(
                "generic resolved tie_break requires type and order"
            ))
        tie_break.type isa Type && isconcretetype(tie_break.type) &&
            isbitstype(tie_break.type) || throw(ArgumentError(
                "generic resolved identity type must be concrete and isbits"
            ))
        tie_break.order === :min || throw(ArgumentError(
            "generic resolved selection admits canonical minimum identity"
        ))
        return _GenericResolvedOutput{
            value_type,
            Int(maximum),
            destinations,
            rank.type,
            rank.order,
            tie_break.type,
        }(empty, rank.lower, rank.upper)
    end
    capacity === nothing && throw(ArgumentError(
        "legacy resolved output requires capacity"
    ))
    key_type === nothing && throw(ArgumentError(
        "legacy resolved output requires key_type"
    ))
    0 <= capacity <= typemax(Int32) || throw(ArgumentError(
        "resolved-output capacity must fit the bounded Int32 kernel ABI"
    ))
    rank isa NamedTuple || throw(ArgumentError(
        "resolved rank must declare type, order, lower, and upper"
    ))
    keys(rank) == (:type, :order, :lower, :upper) ||
        throw(ArgumentError(
            "resolved rank requires exactly type, order, lower, and upper"
        ))
    rank.order in (:min, :max) || throw(ArgumentError(
        "resolved rank order must be :min or :max"
    ))
    rank.type isa DataType && isconcretetype(rank.type) ||
        throw(ArgumentError("resolved rank type must be concrete"))
    typeof(rank.lower) === rank.type && typeof(rank.upper) === rank.type ||
        throw(ArgumentError("resolved rank bounds must have the rank type"))
    rank.lower <= rank.upper || throw(ArgumentError(
        "resolved rank lower bound exceeds its upper bound"
    ))
    tie_break isa NamedTuple || throw(ArgumentError(
        "resolved tie break must declare type and order"
    ))
    keys(tie_break) == (:type, :order) || throw(ArgumentError(
        "resolved tie break requires exactly type and order"
    ))
    tie_break.order === :min || throw(ArgumentError(
        "LW-1 admits canonical minimum identity tie breaking only"
    ))
    tie_break.type isa DataType && isconcretetype(tie_break.type) ||
        throw(ArgumentError("resolved identity type must be concrete"))
    isconcretetype(key_type) && isconcretetype(value_type) ||
        throw(ArgumentError("resolved key and value types must be concrete"))
    mask === nothing || mask isa Symbol || throw(ArgumentError(
        "resolved mask must name one declared read"
    ))
    return _ResolvedOutput(
        destinations,
        empty,
        rank,
        tie_break,
        Int(capacity),
        key_type,
        value_type,
        mask,
    )
end

function _inspect_output(output::_ResolvedOutput)
    return (
        family = :resolved,
        destinations = output.destinations,
        empty = output.empty,
        rank = output.rank,
        tie_break = output.tie_break,
        capacity = output.capacity,
        key_type = output.key_type,
        value_type = output.value_type,
        mask = output.mask,
    )
end

function _resolved_operation(operation)
    operation isa NamedTuple || throw(LocalWorkValidationError(
        "resolved selection requires an inspectable named operation declaration"
    ))
    keys(operation) == (:family, :emission) ||
        throw(LocalWorkValidationError(
            "resolved selection operation requires exactly family and emission"
        ))
    operation.family === :resolved_selection ||
        throw(LocalWorkValidationError(
            "the operation family has no centrally admitted LW-1 lowering"
        ))
    operation.emission isa _MaskedEmission ||
        throw(LocalWorkValidationError(
            "resolved selection emission must use masked(value, mask)"
        ))
    operation.emission.values === :value ||
        throw(LocalWorkValidationError(
            "resolved selection emits the declared :value read"
        ))
    operation.emission.mask isa Union{Bool, Symbol} ||
        throw(LocalWorkValidationError(
            "resolved selection mask must be Bool or a logical read role"
        ))
    return _ResolvedSelection(operation.emission)
end

function _resolved_reads(work::LocalWork)
    required = (:key, :rank, :identity, :value)
    all(name -> hasproperty(work.reads, name), required) ||
        throw(LocalWorkValidationError(
            "resolved selection requires key, rank, identity, and value reads"
        ))
    all(value -> value isa Symbol, values(work.reads)) ||
        throw(LocalWorkValidationError(
            "resolved logical reads must map roles to binding names"
        ))
    return work.reads
end

function _resolved_topology(work, topology, output, operation)
    required = (:item_count, :destination_count, :epoch)
    all(name -> hasproperty(topology, name), required) ||
        throw(LocalWorkValidationError(
            "resolved topology requires item_count, destination_count, and epoch"
        ))
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    expected_read_roles = operation.emission.mask === :mask ?
        (:key, :rank, :identity, :value, :mask) :
        (:key, :rank, :identity, :value)
    Set(keys(reads)) == Set(expected_read_roles) ||
        throw(LocalWorkValidationError(
            "resolved selection reads must exactly match its operational roles"
        ))
    hasproperty(topology, reads.key) &&
        hasproperty(topology, reads.identity) ||
        throw(LocalWorkValidationError(
            "key and identity reads must name topology-owned routing arrays"
        ))
    output.destinations === reads.key || throw(LocalWorkValidationError(
        "resolved destinations must name the declared key read"
    ))
    operation.emission.mask === true ||
        operation.emission.mask === false ||
        operation.emission.mask === :mask ||
        throw(LocalWorkValidationError(
            "resolved emission mask must be true, false, or the :mask read role"
        ))
    if operation.emission.mask === :mask
        output.mask isa Symbol && hasproperty(reads, :mask) &&
            output.mask === reads.mask || throw(LocalWorkValidationError(
                "resolved mask must agree with the declared mask read"
            ))
    else
        output.mask === nothing || throw(LocalWorkValidationError(
            "an unmasked operation cannot declare a mask binding"
        ))
    end

    typeof(topology.epoch) === UInt64 || throw(LocalWorkValidationError(
        "resolved topology epoch must be exactly UInt64"
    ))
    item_count = try
        Int(topology.item_count)
    catch
        throw(LocalWorkValidationError(
            "resolved item_count must be exactly representable as Int"
        ))
    end
    destination_count = try
        Int(topology.destination_count)
    catch
        throw(LocalWorkValidationError(
            "resolved destination_count must be exactly representable as Int"
        ))
    end
    item_count >= 0 && destination_count >= 0 ||
        throw(LocalWorkValidationError(
            "resolved topology counts must be nonnegative"
        ))
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        item_count,
        :resolved_item_count,
    )
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        destination_count,
        :resolved_destination_count,
    )
    invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        output.capacity,
        :resolved_output_capacity,
    )
    work.items == (1:item_count) || throw(LocalWorkValidationError(
        "LocalWork items must exactly cover the planned topology items"
    ))
    output.capacity >= item_count || throw(LocalWorkValidationError(
        "resolved capacity is smaller than the topology item count"
    ))
    keys_array = getproperty(topology, reads.key)
    identities = getproperty(topology, reads.identity)
    length(keys_array) == item_count && length(identities) == item_count ||
        throw(LocalWorkValidationError(
            "topology routing arrays do not match item_count"
        ))
    eltype(keys_array) === output.key_type || throw(LocalWorkValidationError(
        "topology key type disagrees with the resolved declaration"
    ))
    eltype(identities) === output.tie_break.type ||
        throw(LocalWorkValidationError(
            "topology identity type disagrees with the resolved declaration"
        ))
    all(key -> 1 <= Int(key) <= destination_count, keys_array) ||
        throw(LocalWorkValidationError(
            "resolved topology contains an out-of-domain destination"
        ))
    length(unique(identities)) == item_count ||
        throw(LocalWorkValidationError(
            "canonical semantic identities must be unique"
        ))
    return item_count, destination_count
end

function _validate_resolved_capability(backend, output)
    output.key_type === Int32 || throw(LocalWorkValidationError(
        "LW-1 resolved selection admits Int32 destination keys only"
    ))
    output.rank.type === Int32 || throw(LocalWorkValidationError(
        "LW-1 resolved rank type must be the qualified Int32 profile"
    ))
    output.tie_break.type === UInt32 || throw(LocalWorkValidationError(
        "LW-1 resolved identity type must be UInt32"
    ))
    output.value_type === UInt32 || throw(LocalWorkValidationError(
        "LW-1 resolved value type must be the qualified UInt32 profile"
    ))
    invoke(
        _centrally_qualified_value_capability,
        Tuple{Any, Type, Symbol, Symbol},
        backend,
        output.value_type,
        :store,
        :global,
    ) || throw(LocalWorkValidationError(
        "backend × value type × store operation × address-space is not qualified"
    ))
    typeof(output.empty) === output.value_type ||
        throw(LocalWorkValidationError(
            "resolved empty result must have the declared value type"
        ))
    invoke(
        _centrally_qualified_atomic_capability,
        Tuple{Any, Type, Symbol, Symbol},
        backend,
        output.rank.type,
        output.rank.order,
        :global,
    ) || throw(LocalWorkValidationError(
        "backend × rank type × atomic operation × address-space is not qualified"
    ))
    invoke(
        _centrally_qualified_atomic_capability,
        Tuple{Any, Type, Symbol, Symbol},
        backend,
        UInt32,
        :min,
        :global,
    ) ||
        throw(LocalWorkValidationError(
            "backend identity arbitration is not qualified"
        ))
    return nothing
end

function _lower_resolved(work::LocalWork, topology, backend)
    length(work.outputs) == 1 || throw(LocalWorkValidationError(
        "LW-1 resolved selection implements one named output port"
    ))
    output_name = only(keys(work.outputs))
    output = only(values(work.outputs))
    output isa _ResolvedOutput || throw(LocalWorkValidationError(
        "LW-1 implements resolved outputs only"
    ))
    operation = invoke(
        _resolved_operation, Tuple{Any}, work.operation
    )
    item_count, destination_count = invoke(
        _resolved_topology,
        Tuple{Any, Any, Any, Any},
        work,
        topology,
        output,
        operation,
    )
    invoke(
        _validate_resolved_capability,
        Tuple{Any, Any},
        backend,
        output,
    )
    sentinel_rank = output.rank.order === :min ?
                    output.rank.upper : output.rank.lower
    sentinel_identity = typemax(output.tie_break.type)
    return _ResolvedWinnerLowering(
        output_name,
        output,
        operation,
        invoke(_resolved_reads, Tuple{LocalWork}, work),
        topology,
        item_count,
        destination_count,
        sentinel_rank,
        sentinel_identity,
        Symbol(
            "resolved_selection_",
            output.rank.order,
            "_",
            nameof(output.rank.type),
            "_",
            nameof(output.value_type),
            "_v1",
        ),
    )
end

function _topology_fingerprint(
        topology, lowering::_ResolvedWinnerLowering
    )
    io = IOBuffer()
    write(io, Int64(lowering.item_count))
    write(io, Int64(lowering.destination_count))
    write(io, UInt64(invoke(_topology_epoch, Tuple{Any}, topology)))
    # The lowering already owns the exact topology object and logical routing
    # names; hash the concrete, validated routing arrays rather than `show`.
    key_array = getproperty(topology, lowering.reads.key)
    identity_array = getproperty(topology, lowering.reads.identity)
    for value in key_array
        write(io, value)
    end
    for value in identity_array
        write(io, value)
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

function _validate_binding_schema(
        lowering::_ResolvedWinnerLowering,
        work,
        storage,
        schema,
        backend,
    )
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    expected = (
        reads.rank => (
            type = lowering.output.rank.type,
            length = lowering.item_count,
            access = :read,
        ),
        reads.value => (
            type = lowering.output.value_type,
            length = lowering.item_count,
            access = :read,
        ),
        lowering.output_name => (
            type = lowering.output.value_type,
            length = lowering.destination_count,
            access = :write,
        ),
    )
    mask_expected = lowering.operation.emission.mask === :mask ?
        (reads.mask => (
            type = Bool,
            length = lowering.item_count,
            access = :read,
        ),) : ()
    for (name, requirement) in (expected..., mask_expected...)
        facts = invoke(
            _binding_facts, Tuple{Any, Any, Any}, storage, schema, name
        )
        facts.element_type === requirement.type ||
            throw(LocalWorkValidationError(
                "logical binding $name has the wrong element type"
            ))
        facts.dimensions == 1 && facts.size == (requirement.length,) ||
            throw(LocalWorkValidationError(
                "logical binding $name has the wrong layout or length"
            ))
        facts.access === nothing || facts.access === requirement.access ||
            facts.access === :readwrite ||
            throw(LocalWorkValidationError(
                "submission storage $name has the wrong access role"
            ))
    end
    return nothing
end

function _validate_binding_schema(
        lowering::_SequenceLowering,
        work,
        storage,
        schema,
        backend,
    )
    for index in eachindex(lowering.stages)
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _validate_binding_schema,
            (
                lowering.stages[index],
                work.operation.works[index],
                storage,
                schema,
                backend,
            ),
            :binding_validation,
        )
    end
    return nothing
end

function _required_bindings(lowering::_ResolvedWinnerLowering, work)
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    names = Symbol[reads.rank, reads.value, lowering.output_name]
    lowering.operation.emission.mask === :mask && push!(names, reads.mask)
    return invoke(_unique_symbols, Tuple{Any}, names)
end

function _binding_access(lowering::_ResolvedWinnerLowering, work)
    names = invoke(
        _required_bindings,
        Tuple{_ResolvedWinnerLowering, Any},
        lowering,
        work,
    )
    return NamedTuple{names}(map(names) do name
        name === lowering.output_name ? :write : :read
    end)
end

function _validate_workspace(lowering::_ResolvedWinnerLowering, work, workspace, backend)
    required = (:winner_ranks, :winner_identities)
    all(name -> hasproperty(workspace, name), required) ||
        throw(LocalWorkValidationError(
            "resolved workspace requires winner_ranks and winner_identities"
        ))
    ranks = workspace.winner_ranks
    identities = workspace.winner_identities
    eltype(ranks) === lowering.output.rank.type ||
        throw(LocalWorkValidationError(
            "winner-rank workspace has the wrong element type"
        ))
    eltype(identities) === lowering.output.tie_break.type ||
        throw(LocalWorkValidationError(
            "winner-identity workspace has the wrong element type"
        ))
    length(ranks) == lowering.destination_count ||
        throw(LocalWorkValidationError(
            "winner-rank workspace has the wrong exact capacity"
        ))
    length(identities) == lowering.destination_count ||
        throw(LocalWorkValidationError(
            "winner-identity workspace has the wrong exact capacity"
        ))
    ndims(ranks) == 1 && size(ranks) == (lowering.destination_count,) &&
        strides(ranks) == (1,) || throw(LocalWorkValidationError(
            "winner-rank workspace must be a dense one-dimensional buffer"
        ))
    ndims(identities) == 1 &&
        size(identities) == (lowering.destination_count,) &&
        strides(identities) == (1,) || throw(LocalWorkValidationError(
            "winner-identity workspace must be a dense one-dimensional buffer"
        ))
    invoke(
        _validate_array_backend,
        Tuple{Any, Any, Any},
        ranks,
        backend,
        :winner_ranks,
    )
    invoke(
        _validate_array_backend,
        Tuple{Any, Any, Any},
        identities,
        backend,
        :winner_identities,
    )
    Base.mightalias(ranks, identities) && throw(LocalWorkValidationError(
        "resolved scratch buffers must be disjoint"
    ))
    return nothing
end

_workspace_arrays(lowering::_ResolvedWinnerLowering, work, workspace) = (
    :winner_ranks => workspace.winner_ranks,
    :winner_identities => workspace.winner_identities,
)

function _prepare_lowering(lowering::_ResolvedWinnerLowering, work, storage, workspace, backend)
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    copy_signature = backend isa KernelAbstractions.CPU ?
        Tuple{KernelAbstractions.CPU, Any} :
        Tuple{KernelAbstractions.Backend, Any}
    device_keys = invoke(
        _device_copy,
        copy_signature,
        backend,
        getproperty(lowering.topology, reads.key),
    )
    device_identities = invoke(
        _device_copy,
        copy_signature,
        backend,
        getproperty(lowering.topology, reads.identity),
    )
    return _PreparedResolvedWinner(
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _resolved_clear_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _resolved_rank_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _resolved_identity_kernel!,
            backend,
        ),
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _resolved_publish_kernel!,
            backend,
        ),
        device_keys,
        device_identities,
    )
end

@inline function _rank_claim!(winners, destination, rank, ::Val{:min})
    Atomix.@atomic min(winners[destination], rank)
    return nothing
end

@inline function _rank_claim!(winners, destination, rank, ::Val{:max})
    Atomix.@atomic max(winners[destination], rank)
    return nothing
end

@inline _emits(::Nothing, item) = true
@inline _emits(mask::Bool, item) = mask
@inline _emits(mask, item) = @inbounds mask[item]

@kernel function _resolved_clear_kernel!(
        output,
        winner_ranks,
        winner_identities,
        empty,
        sentinel_rank,
        sentinel_identity,
        destination_count::Int32,
    )
    destination = @index(Global, Linear)
    if destination <= destination_count
        @inbounds begin
            output[destination] = empty
            winner_ranks[destination] = sentinel_rank
            winner_identities[destination] = sentinel_identity
        end
    end
end

@kernel function _resolved_rank_kernel!(
        keys,
        ranks,
        mask,
        winner_ranks,
        active_count::Int32,
        lower,
        upper,
        order,
    )
    item = @index(Global, Linear)
    if item <= active_count
        destination = Int(@inbounds keys[item])
        rank = @inbounds ranks[item]
        if !(1 <= destination <= length(winner_ranks))
            error("resolved destination is outside the prepared key domain")
        elseif !(lower <= rank <= upper)
            error("resolved rank is outside its declared total domain")
        elseif _emits(mask, item)
            _rank_claim!(winner_ranks, destination, rank, order)
        end
    end
end

@kernel function _resolved_identity_kernel!(
        keys,
        ranks,
        identities,
        mask,
        winner_ranks,
        winner_identities,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count && _emits(mask, item)
        destination = Int(@inbounds keys[item])
        if 1 <= destination <= length(winner_ranks)
            @inbounds if ranks[item] == winner_ranks[destination]
                identity = identities[item]
                Atomix.@atomic min(
                    winner_identities[destination], identity
                )
            end
        else
            error("resolved destination is outside the prepared key domain")
        end
    end
end

@kernel function _resolved_publish_kernel!(
        keys,
        ranks,
        identities,
        values,
        mask,
        output,
        winner_ranks,
        winner_identities,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count && _emits(mask, item)
        destination = Int(@inbounds keys[item])
        if 1 <= destination <= length(output)
            @inbounds begin
                wins = ranks[item] == winner_ranks[destination] &&
                       identities[item] == winner_identities[destination]
                wins && (output[destination] = values[item])
            end
        else
            error("resolved destination is outside the prepared key domain")
        end
    end
end

function _execute_lowering!(
        runtime::_PreparedResolvedWinner,
        lowering::_ResolvedWinnerLowering,
        work,
        bindings,
        workspace,
        submission,
    )
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    ranks = getproperty(bindings, reads.rank)
    values = getproperty(bindings, reads.value)
    output = getproperty(bindings, lowering.output_name)
    mask = lowering.operation.emission.mask === :mask ?
           getproperty(bindings, reads.mask) :
           lowering.operation.emission.mask
    eltype(ranks) === lowering.output.rank.type || error(
        "validated rank binding changed type"
    )
    eltype(values) === lowering.output.value_type || error(
        "validated value binding changed type"
    )
    eltype(output) === lowering.output.value_type || error(
        "validated output binding changed type"
    )
    active_count = work.active === nothing ? lowering.item_count :
                   Int(getproperty(submission, work.active))
    0 <= active_count <= lowering.item_count ||
        throw(LocalWorkValidationError(
            "active_count exceeds the planned item capacity"
        ))
    active_ndrange = max(active_count, 1)
    destination_ndrange = max(lowering.destination_count, 1)
    runtime.clear_kernel(
        output,
        workspace.winner_ranks,
        workspace.winner_identities,
        lowering.output.empty,
        lowering.sentinel_rank,
        lowering.sentinel_identity,
        Int32(lowering.destination_count);
        ndrange = destination_ndrange,
    )
    runtime.rank_kernel(
        runtime.device_keys,
        ranks,
        mask,
        workspace.winner_ranks,
        Int32(active_count),
        lowering.output.rank.lower,
        lowering.output.rank.upper,
        Val(lowering.output.rank.order);
        ndrange = active_ndrange,
    )
    runtime.identity_kernel(
        runtime.device_keys,
        ranks,
        runtime.device_identities,
        mask,
        workspace.winner_ranks,
        workspace.winner_identities,
        Int32(active_count);
        ndrange = active_ndrange,
    )
    runtime.publish_kernel(
        runtime.device_keys,
        ranks,
        runtime.device_identities,
        values,
        mask,
        output,
        workspace.winner_ranks,
        workspace.winner_identities,
        Int32(active_count);
        ndrange = active_ndrange,
    )
    return 4
end

function _lowering_inspection(
        runtime::_PreparedResolvedWinner,
        lowering::_ResolvedWinnerLowering,
        work,
        workspace,
    )
    reads = invoke(_resolved_reads, Tuple{LocalWork}, work)
    return (
        family = :resolved_selection,
        phases = (
            :initialize_rank,
            :rank_arbitration,
            :identity_arbitration,
            :publication,
        ),
        output_port = lowering.output_name,
        logical_reads = reads,
        destinations = lowering.output.destinations,
        empty = lowering.output.empty,
        rank = lowering.output.rank,
        tie_break = lowering.output.tie_break,
        capacity = lowering.output.capacity,
        mask = lowering.output.mask,
        device_topology = (
            keys_identity = objectid(runtime.device_keys),
            identities_identity = objectid(runtime.device_identities),
            transfer_bytes = lowering.item_count *
                (sizeof(lowering.output.key_type) +
                 sizeof(lowering.output.tie_break.type)),
        ),
        workspace = (
            rank_identity = objectid(workspace.winner_ranks),
            identity_identity = objectid(workspace.winner_identities),
            rank_bytes = sizeof(eltype(workspace.winner_ranks)) *
                length(workspace.winner_ranks),
            identity_bytes = sizeof(eltype(workspace.winner_identities)) *
                length(workspace.winner_identities),
        ),
    )
end
