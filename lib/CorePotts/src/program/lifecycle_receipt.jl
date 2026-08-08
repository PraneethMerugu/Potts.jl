# Immutable, generation-safe lifecycle publication records.

"""A generation-stamped identity for one occupied cell slot."""
struct CellIdentity
    slot::Int32
    generation::UInt32
    kind::Int16

    function CellIdentity(slot::Integer, generation::Integer, kind::Integer)
        0 < slot <= typemax(Int32) || throw(ArgumentError(
            "cell slot must be in 1:typemax(Int32)"
        ))
        0 < generation <= typemax(UInt32) || throw(ArgumentError(
            "cell generation must be in 1:typemax(UInt32)"
        ))
        0 < kind <= typemax(Int16) || throw(ArgumentError(
            "cell kind must be in 1:typemax(Int16)"
        ))
        return new(Int32(slot), UInt32(generation), Int16(kind))
    end
end

"""
The complete ordering identity of one surviving lifecycle request.

Priority is deliberately absent: it selects conflict winners but never controls
publication order.
"""
struct QualifiedLifecycleRequestIdentity
    source_identity::UInt64
    action_identity::UInt64
    anchor_identity::Int32
    generation::UInt32

    function QualifiedLifecycleRequestIdentity(
            source_identity::Integer,
            action_identity::Integer,
            anchor_identity::Integer,
            generation::Integer,
        )
        0 < source_identity <= typemax(UInt64) || throw(ArgumentError(
            "lifecycle source identity must be positive and fit UInt64"
        ))
        0 < action_identity <= typemax(UInt64) || throw(ArgumentError(
            "lifecycle action identity must be positive and fit UInt64"
        ))
        0 <= anchor_identity <= typemax(Int32) || throw(ArgumentError(
            "lifecycle anchor identity must be in 0:typemax(Int32)"
        ))
        0 <= generation <= typemax(UInt32) || throw(ArgumentError(
            "lifecycle request generation must fit UInt32"
        ))
        return new(
            UInt64(source_identity),
            UInt64(action_identity),
            Int32(anchor_identity),
            UInt32(generation),
        )
    end
end

@inline function _lifecycle_request_order_key(
        identity::QualifiedLifecycleRequestIdentity
    )
    return (
        identity.source_identity,
        identity.action_identity,
        identity.anchor_identity,
        identity.generation,
    )
end

Base.isless(
    left::QualifiedLifecycleRequestIdentity,
    right::QualifiedLifecycleRequestIdentity,
) = isless(_lifecycle_request_order_key(left), _lifecycle_request_order_key(right))

abstract type AbstractLifecycleEvent end

@inline lifecycle_request_identity(event::AbstractLifecycleEvent) = event.request

@inline function _require_request_generation(
        request::QualifiedLifecycleRequestIdentity, identity::CellIdentity
    )
    request.generation == identity.generation || throw(ArgumentError(
        "lifecycle request generation does not match its affected cell identity"
    ))
    return nothing
end

"""Create has no before identity and exactly one generation-stamped after identity."""
struct CreateLifecycleEvent <: AbstractLifecycleEvent
    request::QualifiedLifecycleRequestIdentity
    after::CellIdentity

    function CreateLifecycleEvent(
            request::QualifiedLifecycleRequestIdentity, after::CellIdentity
        )
        return new(request, after)
    end
end

"""RemoveCell deletes exactly one before identity without retirement semantics."""
struct RemoveCellLifecycleEvent <: AbstractLifecycleEvent
    request::QualifiedLifecycleRequestIdentity
    before::CellIdentity

    function RemoveCellLifecycleEvent(
            request::QualifiedLifecycleRequestIdentity, before::CellIdentity
        )
        _require_request_generation(request, before)
        return new(request, before)
    end
end

"""Retire retains explicit cause and policy identities and is not plain removal."""
struct RetireLifecycleEvent <: AbstractLifecycleEvent
    request::QualifiedLifecycleRequestIdentity
    before::CellIdentity
    cause_identity::UInt64
    policy_identity::UInt64

    function RetireLifecycleEvent(
            request::QualifiedLifecycleRequestIdentity,
            before::CellIdentity,
            cause_identity::Integer,
            policy_identity::Integer,
        )
        _require_request_generation(request, before)
        0 < cause_identity <= typemax(UInt64) || throw(ArgumentError(
            "retirement cause identity must be positive and fit UInt64"
        ))
        0 < policy_identity <= typemax(UInt64) || throw(ArgumentError(
            "retirement policy identity must be positive and fit UInt64"
        ))
        return new(
            request, before, UInt64(cause_identity), UInt64(policy_identity)
        )
    end
end

"""Transition changes kind while retaining the same slot and generation."""
struct TransitionLifecycleEvent <: AbstractLifecycleEvent
    request::QualifiedLifecycleRequestIdentity
    before::CellIdentity
    after::CellIdentity

    function TransitionLifecycleEvent(
            request::QualifiedLifecycleRequestIdentity,
            before::CellIdentity,
            after::CellIdentity,
        )
        _require_request_generation(request, before)
        before.slot == after.slot || throw(ArgumentError(
            "transition before and after identities must use the same slot"
        ))
        before.generation == after.generation || throw(ArgumentError(
            "transition before and after identities must use the same generation"
        ))
        before.kind != after.kind || throw(ArgumentError(
            "transition before and after kinds must be distinct"
        ))
        return new(request, before, after)
    end
end

"""Role tag for the cell identity consumed by a divide event."""
struct ParentBeforeIdentity
    cell::CellIdentity
end

"""Role tag for the retained parent identity produced by a divide event."""
struct ParentAfterIdentity
    cell::CellIdentity
end

"""Role tag for the new daughter identity produced by a divide event."""
struct DaughterAfterIdentity
    cell::CellIdentity
end

"""Divide consumes one parent and produces role-tagged parent and daughter identities."""
struct DivideLifecycleEvent <: AbstractLifecycleEvent
    request::QualifiedLifecycleRequestIdentity
    parent_before::ParentBeforeIdentity
    parent_after::ParentAfterIdentity
    daughter_after::DaughterAfterIdentity

    function DivideLifecycleEvent(
            request::QualifiedLifecycleRequestIdentity,
            parent_before::ParentBeforeIdentity,
            parent_after::ParentAfterIdentity,
            daughter_after::DaughterAfterIdentity,
        )
        before = parent_before.cell
        parent = parent_after.cell
        daughter = daughter_after.cell
        _require_request_generation(request, before)
        before.slot == parent.slot || throw(ArgumentError(
            "divide parent-before and parent-after identities must use the same slot"
        ))
        before.generation == parent.generation || throw(ArgumentError(
            "divide parent-before and parent-after identities must use the same generation"
        ))
        daughter.slot != parent.slot || throw(ArgumentError(
            "divide daughter identity must use a slot distinct from the parent"
        ))
        daughter != parent || throw(ArgumentError(
            "divide daughter identity must be distinct from the parent identity"
        ))
        return new(request, parent_before, parent_after, daughter_after)
    end
end

function DivideLifecycleEvent(
        request::QualifiedLifecycleRequestIdentity,
        parent_before::CellIdentity,
        parent_after::CellIdentity,
        daughter_after::CellIdentity,
    )
    return DivideLifecycleEvent(
        request,
        ParentBeforeIdentity(parent_before),
        ParentAfterIdentity(parent_after),
        DaughterAfterIdentity(daughter_after),
    )
end

const LifecycleEvent = Union{
    CreateLifecycleEvent,
    RemoveCellLifecycleEvent,
    RetireLifecycleEvent,
    TransitionLifecycleEvent,
    DivideLifecycleEvent,
}

@inline _lifecycle_event_order_key(event::AbstractLifecycleEvent) =
    _lifecycle_request_order_key(lifecycle_request_identity(event))

function _validate_lifecycle_event(event::AbstractLifecycleEvent)
    # Re-run all cross-field checks so a receipt never trusts an event buffer
    # that may have been obtained through reflective field access.
    if event isa CreateLifecycleEvent
        CreateLifecycleEvent(event.request, event.after)
    elseif event isa RemoveCellLifecycleEvent
        RemoveCellLifecycleEvent(event.request, event.before)
    elseif event isa RetireLifecycleEvent
        RetireLifecycleEvent(
            event.request,
            event.before,
            event.cause_identity,
            event.policy_identity,
        )
    elseif event isa TransitionLifecycleEvent
        TransitionLifecycleEvent(event.request, event.before, event.after)
    elseif event isa DivideLifecycleEvent
        DivideLifecycleEvent(
            event.request,
            event.parent_before,
            event.parent_after,
            event.daughter_after,
        )
    else
        throw(ArgumentError("unsupported lifecycle event type $(typeof(event))"))
    end
    return event
end

"""
An owned, logically immutable lifecycle receipt for one successful transaction.

The event buffer is defensively copied and has no supported mutating accessor.
`validate_lifecycle_receipt` is repeated at the component-state boundary.
"""
struct LifecycleReceipt
    completed_mcs::Int
    transaction_identity::UInt64
    _events::Vector{LifecycleEvent}

    function LifecycleReceipt(
            completed_mcs::Integer,
            transaction_identity::Integer,
            events = LifecycleEvent[],
        )
        0 <= completed_mcs <= typemax(Int) || throw(ArgumentError(
            "receipt completed MCS must be nonnegative and fit Int"
        ))
        0 < transaction_identity <= typemax(UInt64) || throw(ArgumentError(
            "receipt transaction identity must be positive and fit UInt64"
        ))
        owned = LifecycleEvent[]
        for event in events
            event isa LifecycleEvent || throw(ArgumentError(
                "receipt contains unsupported lifecycle event $(typeof(event))"
            ))
            push!(owned, _validate_lifecycle_event(event))
        end
        for index in 2:length(owned)
            previous = _lifecycle_event_order_key(owned[index - 1])
            current = _lifecycle_event_order_key(owned[index])
            isless(previous, current) || throw(ArgumentError(
                "lifecycle receipt events must be in strict canonical request order"
            ))
        end
        return new(Int(completed_mcs), UInt64(transaction_identity), owned)
    end
end

"""Explicit absence represents a failed or not-yet-published lifecycle transaction."""
const MaybeLifecycleReceipt = Union{Nothing, LifecycleReceipt}

Base.length(receipt::LifecycleReceipt) = length(receipt._events)
Base.isempty(receipt::LifecycleReceipt) = isempty(receipt._events)
Base.eltype(::Type{LifecycleReceipt}) = LifecycleEvent
Base.getindex(receipt::LifecycleReceipt, index::Integer) = receipt._events[index]
Base.iterate(receipt::LifecycleReceipt, state...) = iterate(receipt._events, state...)

"""Return the receipt events as an immutable tuple snapshot."""
lifecycle_events(receipt::LifecycleReceipt) = Tuple(receipt._events)

function validate_lifecycle_receipt(receipt::LifecycleReceipt)
    0 <= receipt.completed_mcs || throw(ArgumentError(
        "receipt completed MCS must be nonnegative"
    ))
    iszero(receipt.transaction_identity) && throw(ArgumentError(
        "receipt transaction identity must be nonzero"
    ))
    previous = nothing
    for event in receipt._events
        _validate_lifecycle_event(event)
        key = _lifecycle_event_order_key(event)
        if previous !== nothing
            isless(previous, key) || throw(ArgumentError(
                "lifecycle receipt events must be in strict canonical request order"
            ))
        end
        previous = key
    end
    return receipt
end
