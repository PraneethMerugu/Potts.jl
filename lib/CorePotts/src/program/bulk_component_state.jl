# Generic two-bank component-state lifecycle seam.

"""
Policy boundary for component values owned by a package above CorePotts.

CorePotts owns slot/generation/kind validation and atomic bank publication. The
policy owns the representation and scientific value assigned for each event.
"""
abstract type AbstractBulkComponentStatePolicy end

"""Produce an independently owned component-state bank."""
clone_component_state(::AbstractBulkComponentStatePolicy, state) = deepcopy(state)

"""Copy one settled component-state bank into an already allocated candidate bank."""
function copy_component_state!(
        ::AbstractBulkComponentStatePolicy, destination, source
    )
    copyto!(destination, source)
    return destination
end

"""Optional representation-specific capacity and invariant check."""
validate_component_state(
    ::AbstractBulkComponentStatePolicy, state, capacity::Integer
) = nothing

# Downstream packages implement only the event operations admitted by their
# component-state policy. Keeping Remove and Retire distinct is intentional.
"""Initialize downstream component state for one newly created cell identity."""
function initialize_component_state! end
"""Remove downstream component state for one deleted cell identity."""
function remove_component_state! end
"""Apply downstream retirement semantics to one cell identity."""
function retire_component_state! end
"""Transform downstream component state across a kind transition."""
function transition_component_state! end
"""Split downstream component state between parent and daughter identities."""
function divide_component_state! end

"""Supertype for atomic component-state receipt application failures."""
abstract type AbstractComponentStateApplicationError <: Exception end

"""Error raised when a published lifecycle transaction is applied twice."""
struct DuplicateLifecycleReceiptError <: AbstractComponentStateApplicationError
    completed_mcs::Int
    transaction_identity::UInt64
end

function Base.showerror(io::IO, error::DuplicateLifecycleReceiptError)
    print(
        io,
        "lifecycle receipt ",
        error.transaction_identity,
        " at completed MCS ",
        error.completed_mcs,
        " was already applied",
    )
end

"""Error raised when lifecycle receipts do not follow published MCS order."""
struct LifecycleReceiptOrderError <: AbstractComponentStateApplicationError
    receipt_mcs::Int
    transaction_identity::UInt64
    published_mcs::Int
    published_transaction_identity::UInt64
end

function Base.showerror(io::IO, error::LifecycleReceiptOrderError)
    print(
        io,
        "lifecycle receipt ",
        error.transaction_identity,
        " at completed MCS ",
        error.receipt_mcs,
        " does not follow published component boundary ",
        error.published_mcs,
        " (transaction ",
        error.published_transaction_identity,
        ')',
    )
end

"""Error raised when a receipt names a stale generation or kind."""
struct StaleCellIdentityError <: AbstractComponentStateApplicationError
    event_index::Int
    identity::CellIdentity
    active::Bool
    observed_generation::UInt32
    observed_kind::Int16
end

function Base.showerror(io::IO, error::StaleCellIdentityError)
    identity = error.identity
    print(
        io,
        "stale cell identity at lifecycle event ",
        error.event_index,
        ": requested (slot=", identity.slot,
        ", generation=", identity.generation,
        ", kind=", identity.kind,
        "), observed (active=", error.active,
        ", generation=", error.observed_generation,
        ", kind=", error.observed_kind,
        ')',
    )
end

"""Error raised when creation targets an already occupied component slot."""
struct OccupiedComponentSlotError <: AbstractComponentStateApplicationError
    event_index::Int
    identity::CellIdentity
    observed_generation::UInt32
    observed_kind::Int16
end

function Base.showerror(io::IO, error::OccupiedComponentSlotError)
    print(
        io,
        "cannot create component state at occupied slot ",
        error.identity.slot,
        " during lifecycle event ",
        error.event_index,
        "; observed generation ",
        error.observed_generation,
        " and kind ",
        error.observed_kind,
    )
end

"""Error raised when a receipt targets a slot beyond component-state capacity."""
struct ComponentStateCapacityError <: AbstractComponentStateApplicationError
    event_index::Int
    slot::Int32
    capacity::Int
end

function Base.showerror(io::IO, error::ComponentStateCapacityError)
    print(
        io,
        "cell slot ",
        error.slot,
        " at lifecycle event ",
        error.event_index,
        " exceeds component-state capacity ",
        error.capacity,
    )
end

struct BulkComponentStateBank{S}
    active::BitVector
    generations::Vector{UInt32}
    kinds::Vector{Int16}
    state::S
end

"""Two-bank transactional owner of downstream per-cell component state."""
mutable struct BulkComponentStatePool{S, P <: AbstractBulkComponentStatePolicy}
    banks::NTuple{2, BulkComponentStateBank{S}}
    active_bank::UInt8
    completed_mcs::Int
    last_transaction_identity::UInt64
    policy::P
    pending::Bool
end


@enum ComponentStateTransactionState::UInt8 begin
    ComponentStateStaged = 0x01
    ComponentStateCommitted = 0x02
    ComponentStateAborted = 0x03
end


"""Opaque unpublished component-state candidate for a lifecycle receipt."""
mutable struct BulkComponentStateTransaction{P, R}
    pool::P
    receipt::R
    source_bank::UInt8
    candidate_bank::UInt8
    source_completed_mcs::Int
    source_transaction_identity::UInt64
    state::ComponentStateTransactionState
end

@inline _active_component_bank(pool::BulkComponentStatePool) =
    pool.banks[Int(pool.active_bank)]

@inline _inactive_component_bank_index(pool::BulkComponentStatePool) =
    pool.active_bank == 0x01 ? 2 : 1

function _validate_component_metadata(
        active::AbstractVector{Bool},
        generations::AbstractVector{UInt32},
        kinds::AbstractVector{Int16},
    )
    length(active) == length(generations) == length(kinds) || throw(ArgumentError(
        "component-state metadata buffers must have equal lengths"
    ))
    for slot in eachindex(active, generations, kinds)
        if active[slot]
            iszero(generations[slot]) && throw(ArgumentError(
                "active component slot $slot must have a positive generation"
            ))
            kinds[slot] > 0 || throw(ArgumentError(
                "active component slot $slot must have a positive kind"
            ))
        else
            iszero(kinds[slot]) || throw(ArgumentError(
                "inactive component slot $slot must have kind zero"
            ))
        end
    end
    return nothing
end

function _owned_component_metadata(active, generations, kinds)
    capacity = length(active)
    capacity > 0 || throw(ArgumentError(
        "component-state capacity must be positive"
    ))
    capacity <= typemax(Int32) || throw(ArgumentError(
        "component-state capacity exceeds the Int32 slot bound"
    ))
    length(generations) == capacity || throw(ArgumentError(
        "component generation table does not match capacity"
    ))
    length(kinds) == capacity || throw(ArgumentError(
        "component kind table does not match capacity"
    ))
    owned_active = BitVector(active)
    owned_generations = Vector{UInt32}(undef, capacity)
    owned_kinds = Vector{Int16}(undef, capacity)
    for slot in 1:capacity
        generation = generations[slot]
        kind = kinds[slot]
        0 <= generation <= typemax(UInt32) || throw(ArgumentError(
            "component generation at slot $slot does not fit UInt32"
        ))
        0 <= kind <= typemax(Int16) || throw(ArgumentError(
            "component kind at slot $slot does not fit Int16"
        ))
        owned_generations[slot] = UInt32(generation)
        owned_kinds[slot] = Int16(kind)
    end
    _validate_component_metadata(
        owned_active, owned_generations, owned_kinds
    )
    return owned_active, owned_generations, owned_kinds
end

function BulkComponentStatePool(
        active,
        generations,
        kinds,
        state,
        policy::AbstractBulkComponentStatePolicy;
        completed_mcs::Integer = 0,
        last_transaction_identity::Integer = 0,
    )
    0 <= completed_mcs <= typemax(Int) || throw(ArgumentError(
        "component-state completed MCS must be nonnegative and fit Int"
    ))
    0 <= last_transaction_identity <= typemax(UInt64) || throw(ArgumentError(
        "last lifecycle transaction identity must fit UInt64"
    ))
    owned_active, owned_generations, owned_kinds =
        _owned_component_metadata(active, generations, kinds)
    first_state = clone_component_state(policy, state)
    second_state = clone_component_state(policy, first_state)
    first_state === second_state && throw(ArgumentError(
        "component-state policy must clone independent candidate banks"
    ))
    capacity = length(owned_active)
    validate_component_state(policy, first_state, capacity)
    validate_component_state(policy, second_state, capacity)
    first_bank = BulkComponentStateBank(
        owned_active, owned_generations, owned_kinds, first_state
    )
    second_bank = BulkComponentStateBank(
        copy(owned_active),
        copy(owned_generations),
        copy(owned_kinds),
        second_state,
    )
    return BulkComponentStatePool(
        (first_bank, second_bank),
        UInt8(1),
        Int(completed_mcs),
        UInt64(last_transaction_identity),
        policy,
        false,
    )
end

Base.length(pool::BulkComponentStatePool) = length(_active_component_bank(pool).active)

"""Return the last MCS published by a component-state pool."""
bulk_component_completed_mcs(pool::BulkComponentStatePool) = pool.completed_mcs
"""Return the last lifecycle transaction identity published by a pool."""
bulk_component_last_transaction_identity(pool::BulkComponentStatePool) =
    pool.last_transaction_identity

"""Return the current identity at `slot`, or `nothing` when the slot is inactive."""
function component_identity(pool::BulkComponentStatePool, slot::Integer)
    bank = _active_component_bank(pool)
    checkbounds(bank.active, slot)
    bank.active[slot] || return nothing
    return CellIdentity(slot, bank.generations[slot], bank.kinds[slot])
end

"""Return an independently owned snapshot of the active native component values."""
function component_state_snapshot(pool::BulkComponentStatePool)
    return clone_component_state(pool.policy, _active_component_bank(pool).state)
end

"""Return independently owned active, generation, and kind slot metadata."""
function component_metadata_snapshot(pool::BulkComponentStatePool)
    bank = _active_component_bank(pool)
    return (
        active = copy(bank.active),
        generations = copy(bank.generations),
        kinds = copy(bank.kinds),
    )
end

function _component_slot_index(
        bank::BulkComponentStateBank,
        identity::CellIdentity,
        event_index::Int,
    )
    slot = Int(identity.slot)
    slot <= length(bank.active) || throw(ComponentStateCapacityError(
        event_index, identity.slot, length(bank.active)
    ))
    return slot
end

function _require_component_identity(
        bank::BulkComponentStateBank,
        identity::CellIdentity,
        event_index::Int,
    )
    slot = _component_slot_index(bank, identity, event_index)
    active = bank.active[slot]
    generation = bank.generations[slot]
    kind = bank.kinds[slot]
    active && generation == identity.generation && kind == identity.kind ||
        throw(StaleCellIdentityError(
            event_index, identity, active, generation, kind
        ))
    return slot
end

function _require_fresh_component_identity(
        bank::BulkComponentStateBank,
        identity::CellIdentity,
        event_index::Int,
    )
    slot = _component_slot_index(bank, identity, event_index)
    if bank.active[slot]
        throw(OccupiedComponentSlotError(
            event_index,
            identity,
            bank.generations[slot],
            bank.kinds[slot],
        ))
    end
    identity.generation > bank.generations[slot] || throw(StaleCellIdentityError(
        event_index,
        identity,
        false,
        bank.generations[slot],
        bank.kinds[slot],
    ))
    return slot
end

function _apply_component_event!(
        pool::BulkComponentStatePool,
        bank::BulkComponentStateBank,
        event::CreateLifecycleEvent,
        event_index::Int,
    )
    slot = _require_fresh_component_identity(bank, event.after, event_index)
    initialize_component_state!(pool.policy, bank.state, event)
    bank.active[slot] = true
    bank.generations[slot] = event.after.generation
    bank.kinds[slot] = event.after.kind
    return nothing
end

function _apply_component_event!(
        pool::BulkComponentStatePool,
        bank::BulkComponentStateBank,
        event::RemoveCellLifecycleEvent,
        event_index::Int,
    )
    slot = _require_component_identity(bank, event.before, event_index)
    remove_component_state!(pool.policy, bank.state, event)
    bank.active[slot] = false
    bank.kinds[slot] = 0
    return nothing
end

function _apply_component_event!(
        pool::BulkComponentStatePool,
        bank::BulkComponentStateBank,
        event::RetireLifecycleEvent,
        event_index::Int,
    )
    slot = _require_component_identity(bank, event.before, event_index)
    retire_component_state!(pool.policy, bank.state, event)
    bank.active[slot] = false
    bank.kinds[slot] = 0
    return nothing
end

function _apply_component_event!(
        pool::BulkComponentStatePool,
        bank::BulkComponentStateBank,
        event::TransitionLifecycleEvent,
        event_index::Int,
    )
    slot = _require_component_identity(bank, event.before, event_index)
    transition_component_state!(pool.policy, bank.state, event)
    bank.kinds[slot] = event.after.kind
    return nothing
end

function _apply_component_event!(
        pool::BulkComponentStatePool,
        bank::BulkComponentStateBank,
        event::DivideLifecycleEvent,
        event_index::Int,
    )
    parent = event.parent_before.cell
    parent_after = event.parent_after.cell
    daughter = event.daughter_after.cell
    parent_slot = _require_component_identity(bank, parent, event_index)
    daughter_slot = _require_fresh_component_identity(bank, daughter, event_index)
    divide_component_state!(pool.policy, bank.state, event)
    bank.kinds[parent_slot] = parent_after.kind
    bank.active[daughter_slot] = true
    bank.generations[daughter_slot] = daughter.generation
    bank.kinds[daughter_slot] = daughter.kind
    return nothing
end

function _prepare_component_candidate!(pool::BulkComponentStatePool)
    source = _active_component_bank(pool)
    destination = pool.banks[_inactive_component_bank_index(pool)]
    copyto!(destination.active, source.active)
    copyto!(destination.generations, source.generations)
    copyto!(destination.kinds, source.kinds)
    copy_component_state!(pool.policy, destination.state, source.state)
    return destination
end

"""
    apply_lifecycle_receipt!(pool, receipt)

Validate and apply one receipt to the inactive component bank. The bank index,
completed MCS, and transaction identity are published only after every event and
policy validation succeeds. A thrown validation or policy error leaves the active
bank and last-applied identity unchanged.
"""
function stage_lifecycle_receipt!(
        pool::BulkComponentStatePool, receipt::LifecycleReceipt
    )
    pool.pending && throw(ArgumentError(
        "a component-state lifecycle transaction is already staged"
    ))
    validate_lifecycle_receipt(receipt)
    if receipt.completed_mcs == pool.completed_mcs &&
            receipt.transaction_identity == pool.last_transaction_identity
        throw(DuplicateLifecycleReceiptError(
            receipt.completed_mcs, receipt.transaction_identity
        ))
    end
    if receipt.completed_mcs < pool.completed_mcs ||
            receipt.completed_mcs == pool.completed_mcs
        throw(LifecycleReceiptOrderError(
            receipt.completed_mcs,
            receipt.transaction_identity,
            pool.completed_mcs,
            pool.last_transaction_identity,
        ))
    end

    source_bank = pool.active_bank
    candidate_bank = UInt8(_inactive_component_bank_index(pool))
    pool.pending = true
    try
        candidate = _prepare_component_candidate!(pool)
        for (event_index, event) in enumerate(receipt)
            _apply_component_event!(pool, candidate, event, event_index)
        end
        _validate_component_metadata(
            candidate.active, candidate.generations, candidate.kinds
        )
        validate_component_state(pool.policy, candidate.state, length(pool))
    catch
        pool.pending = false
        rethrow()
    end
    return BulkComponentStateTransaction(
        pool,
        receipt,
        source_bank,
        candidate_bank,
        pool.completed_mcs,
        pool.last_transaction_identity,
        ComponentStateStaged,
    )
end


function _require_staged_component_transaction(
        transaction::BulkComponentStateTransaction
    )
    transaction.state === ComponentStateStaged || throw(ArgumentError(
        "component-state transaction is no longer staged"
    ))
    pool = transaction.pool
    pool.pending || throw(ArgumentError(
        "component-state transaction lost its pending pool ownership"
    ))
    pool.active_bank == transaction.source_bank &&
        pool.completed_mcs == transaction.source_completed_mcs &&
        pool.last_transaction_identity == transaction.source_transaction_identity ||
        throw(ArgumentError(
            "component-state pool changed while a transaction was staged"
        ))
    return transaction
end


"""Return the unpublished downstream state owned by a staged transaction."""
function component_transaction_state(
        transaction::BulkComponentStateTransaction
    )
    _require_staged_component_transaction(transaction)
    return transaction.pool.banks[Int(transaction.candidate_bank)].state
end


"""Validate one component token completely before coordinated publication."""
function prevalidate_component_state_transaction(
        transaction::BulkComponentStateTransaction
    )
    _require_staged_component_transaction(transaction)
    transaction.candidate_bank != transaction.source_bank || throw(ArgumentError(
        "component-state transaction candidate bank aliases its source bank"
    ))
    transaction.candidate_bank ==
        UInt8(_inactive_component_bank_index(transaction.pool)) || throw(
        ArgumentError(
            "component-state transaction no longer owns the inactive candidate bank"
        )
    )
    pool = transaction.pool
    candidate = pool.banks[Int(transaction.candidate_bank)]
    _validate_component_metadata(
        candidate.active, candidate.generations, candidate.kinds
    )
    validate_component_state(pool.policy, candidate.state, length(pool))
    return transaction
end


"""
Validate every component token and reject repeated pool ownership.

No token is published by this operation, so any validation failure leaves the
entire group staged and abortable.
"""
function prevalidate_component_state_transactions(transactions)
    pools = IdDict{Any, Nothing}()
    for transaction in transactions
        transaction isa BulkComponentStateTransaction || throw(ArgumentError(
            "component transaction groups may contain only bulk component tokens"
        ))
        prevalidate_component_state_transaction(transaction)
        pool = transaction.pool
        haskey(pools, pool) && throw(ArgumentError(
            "a component transaction group contains duplicate pool ownership"
        ))
        pools[pool] = nothing
    end
    return transactions
end


"""
Publish one prevalidated component token using assignment-only operations.

This is the no-throw half of coordinated commit and must only be called after
`prevalidate_component_state_transaction` succeeds for every participant.
"""
function publish_component_state_transaction!(
        transaction::BulkComponentStateTransaction
    )
    pool = transaction.pool
    receipt = transaction.receipt

    pool.completed_mcs = receipt.completed_mcs
    pool.last_transaction_identity = receipt.transaction_identity
    pool.active_bank = transaction.candidate_bank
    pool.pending = false
    transaction.state = ComponentStateCommitted
    return pool
end


"""Publish an already prevalidated, duplicate-free component token group."""
function publish_component_state_transactions!(transactions)
    for transaction in transactions
        publish_component_state_transaction!(transaction)
    end
    return transactions
end


"""Prevalidate and atomically publish one component-state transaction."""
function commit_component_state_transaction!(
        transaction::BulkComponentStateTransaction
    )
    prevalidate_component_state_transaction(transaction)
    return publish_component_state_transaction!(transaction)
end


"""Prevalidate all component tokens, then publish the complete group."""
function commit_component_state_transactions!(transactions)
    prevalidate_component_state_transactions(transactions)
    return publish_component_state_transactions!(transactions)
end


"""Discard one unpublished component-state transaction."""
function abort_component_state_transaction!(
        transaction::BulkComponentStateTransaction
    )
    _require_staged_component_transaction(transaction)
    transaction.pool.pending = false
    transaction.state = ComponentStateAborted
    return transaction.pool
end


"""Stage, validate, and atomically publish one lifecycle receipt to a pool."""
function apply_lifecycle_receipt!(
        pool::BulkComponentStatePool, receipt::LifecycleReceipt
    )
    transaction = stage_lifecycle_receipt!(pool, receipt)
    return commit_component_state_transaction!(transaction)
end
