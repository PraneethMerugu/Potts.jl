# Settled host relationship mutation and atomic runtime reconstruction.

function _host_relationship_transaction_groups(transactions)
    groups = collect(transactions)
    seen = Set{Int}()
    normalized = Pair{Int, Any}[]
    for transaction in groups
        transaction isa Pair || throw(ArgumentError(
            "host relationship transactions must be `slot => requests` pairs"
        ))
        slot = first(transaction)
        slot isa Integer || throw(ArgumentError(
            "host relationship transaction slots must be integers"
        ))
        resolved = Int(slot)
        resolved in seen && throw(ArgumentError(
            "host relationship transaction contains duplicate slot $resolved"
        ))
        push!(seen, resolved)
        push!(normalized, resolved => last(transaction))
    end
    sort!(normalized; by = first)
    return normalized
end

"""
    host_relationship_transaction(runtime, transactions)

Build a new host runtime in which all supplied bounded relationship requests
have been validated and committed atomically. `transactions` is an iterable of
`relationship_slot => requests` pairs. The input runtime is never mutated.

The operation is deliberately cold and host-only: it snapshots one settled
logical boundary, applies every store transaction to independent storage, then
reconstructs all execution banks in one candidate runtime. Backend adapters may
adapt that candidate only after this function succeeds.
"""
function host_relationship_transaction(
        runtime::ProgramRuntime, transactions
    )
    runtime.settled || throw(ArgumentError(
        "host relationship mutations require a settled complete-MCS boundary"
    ))
    program_failed(runtime) && throw(ArgumentError(
        "a terminal failed runtime cannot accept relationship mutations"
    ))
    groups = _host_relationship_transaction_groups(transactions)
    isempty(groups) && throw(ArgumentError(
        "a host relationship transaction requires at least one request group"
    ))

    snapshot = program_snapshot(runtime)
    relationships = copy(snapshot.relationships)
    for (slot, requests) in groups
        1 <= slot <= length(relationships) || throw(ArgumentError(
            "relationship slot $slot is outside the compiled program"
        ))
        apply_relationship_requests!(
            relationships[slot],
            snapshot.cell_kinds,
            snapshot.cell_generations,
            runtime.program.relationships[slot],
            requests,
        )
    end
    for slot in eachindex(relationships)
        validate_relationship_integrity(
            relationships[slot],
            runtime.program.relationships[slot],
            snapshot.cell_kinds,
            snapshot.cell_generations,
        )
    end

    initial = ProgramInitialState(
        snapshot.ownership,
        snapshot.cell_kinds;
        scalar_type = eltype(runtime.parameters),
        cell_generations = snapshot.cell_generations,
        relationships = collect(relationships),
        descriptor_state = snapshot.descriptor_state,
    )
    tracker_checkpoint = encode_tracker_checkpoint(
        runtime.program.tracker_plan, runtime.trackers
    )
    candidate = _materialize_program(
        runtime.program,
        initial,
        runtime.parameters,
        runtime.seed,
        runtime.replica;
        repeat = runtime.repeat,
        initial_mcs = runtime.mcs,
        tracker_checkpoint,
        counters = (
            accepted = runtime.accepted,
            rejected = runtime.rejected,
            null_attempts = runtime.null_attempts,
            constraint_rejections = runtime.constraint_rejections,
            energy_rejections = runtime.energy_rejections,
            retired_cells = runtime.retired_cells,
        ),
    )
    candidate.last_lifecycle_receipt = deepcopy(runtime.last_lifecycle_receipt)
    return candidate
end
