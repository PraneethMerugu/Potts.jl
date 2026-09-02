# Closed cell-lifecycle authoring vocabulary. Runtime transaction machinery
# is intentionally absent from this compiler-stage module.

abstract type AbstractLifecyclePolicy end
abstract type AbstractLifecyclePlacementPolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecyclePartitionPolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleSidePolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleKindPolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleStatePolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleRelationshipPolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleInadmissibilityPolicy <: AbstractLifecyclePolicy end
abstract type AbstractLifecycleConflictPolicy <: AbstractLifecyclePolicy end
abstract type AbstractExtinctionPolicy <: AbstractLifecyclePolicy end

"""Place a newly created cell at one explicit site."""
struct SeedAt{S} <: AbstractLifecyclePlacementPolicy
    site::S
end

"""Place a cell using finite unique offsets around an anchor site."""
struct SeedStencil{S, O <: Tuple, R} <: AbstractLifecyclePlacementPolicy
    site::S
    offsets::O
    relation::R
end
function SeedStencil(site, offsets; relation)
    frozen = offsets isa Tuple ? offsets : Tuple(offsets)
    isempty(frozen) && throw(ArgumentError("SeedStencil offsets must be nonempty"))
    length(unique(frozen)) == length(frozen) || throw(ArgumentError(
        "SeedStencil offsets must be unique"
    ))
    return SeedStencil(site, frozen, relation)
end

"""Use the parent cell centroid as a lifecycle geometric center."""
struct CellCentroid <: AbstractLifecyclePolicy end

"""Choose a division plane from a named semantic random draw."""
struct RandomPlane{P, D} <: AbstractLifecyclePartitionPolicy
    point::P
    draw::D
end
RandomPlane(; point = CellCentroid(), draw = :division_normal) =
    RandomPlane(point, draw)

"""Choose a major or minor principal-axis division plane."""
struct PrincipalAxisPlane{P} <: AbstractLifecyclePartitionPolicy
    axis::Symbol
    point::P
    function PrincipalAxisPlane(axis::Symbol; point = CellCentroid())
        axis in (:major, :minor) || throw(ArgumentError(
            "PrincipalAxisPlane axis must be :major or :minor"
        ))
        return new{typeof(point)}(axis, point)
    end
end
PrincipalAxisPlane(; axis, point = CellCentroid()) =
    PrincipalAxisPlane(axis; point)
PrincipalAxisPlane(axis::Symbol, point) = PrincipalAxisPlane(axis; point)

"""Use an explicit normal and point for a division plane."""
struct SpecifiedNormalPlane{N, P} <: AbstractLifecyclePartitionPolicy
    normal::N
    point::P
end
SpecifiedNormalPlane(normal; point = CellCentroid()) =
    SpecifiedNormalPlane(normal, point)

"""Choose the geometrically canonical side of a division plane."""
struct CanonicalSide <: AbstractLifecycleSidePolicy end
"""Choose a division side using a stable semantic draw identity."""
struct StableRandomSide{D} <: AbstractLifecycleSidePolicy
    draw_identity::D
end

"""Preserve a cell's kind through a lifecycle transition."""
struct PreserveKind <: AbstractLifecycleKindPolicy end
"""Assign an explicit cell kind after a lifecycle transition."""
struct SetKind{K} <: AbstractLifecycleKindPolicy
    kind::K
end

"""Initialize lifecycle state from a symbolic expression."""
struct InitializeFrom{E} <: AbstractLifecycleStatePolicy
    expression::E
end
"""Declare that a lifecycle state transition is intentionally unsupported."""
struct Unsupported <: AbstractLifecycleStatePolicy end
"""Transfer retiring state according to a symbolic expression."""
struct RetireTo{E} <: AbstractLifecycleStatePolicy
    expression::E
end
"""Preserve a state value through a lifecycle transition."""
struct Preserve <: AbstractLifecycleStatePolicy end
"""Reset a state value from a symbolic expression."""
struct ResetTo{E} <: AbstractLifecycleStatePolicy
    expression::E
end
"""Transform lifecycle state with a symbolic expression."""
struct Transform{E} <: AbstractLifecycleStatePolicy
    expression::E
end
"""Copy parent state to both daughters."""
struct CopyToDaughters <: AbstractLifecycleStatePolicy end
"""Preserve parent state and reset daughter state."""
struct PreserveParentResetDaughter{E} <: AbstractLifecycleStatePolicy
    expression::E
end
"""Reset parent and daughter from separate expressions."""
struct ResetBoth{P, D} <: AbstractLifecycleStatePolicy
    parent_expression::P
    daughter_expression::D
end
"""Split an extensive value conservatively under an explicit rounding policy."""
struct SplitConservatively{F, R} <: AbstractLifecycleStatePolicy
    fraction::F
    rounding::R
end
SplitConservatively(fraction; rounding) =
    SplitConservatively(fraction, rounding)
"""Transform parent and daughter states independently."""
struct TransformDaughters{P, D} <: AbstractLifecycleStatePolicy
    parent_expression::P
    daughter_expression::D
end
"""Redraw parent and daughter states with distinct semantic draw identities."""
struct RedrawDaughters{P, D, R, S} <: AbstractLifecycleStatePolicy
    parent_distribution::P
    daughter_distribution::D
    parent_draw::R
    daughter_draw::S
end
RedrawDaughters(parent_distribution, daughter_distribution;
        parent_draw, daughter_draw) = RedrawDaughters(
    parent_distribution, daughter_distribution, parent_draw, daughter_draw
)

"""Reject a lifecycle operation while relationships remain linked."""
struct RejectWhileLinked <: AbstractLifecycleRelationshipPolicy end
"""Remove incident relationships during a lifecycle operation."""
struct RemoveIncident <: AbstractLifecycleRelationshipPolicy end
"""Preserve relationship edges compatible with new endpoint kinds."""
struct PreserveCompatible <: AbstractLifecycleRelationshipPolicy end
"""Remove relationship edges incompatible with new endpoint kinds."""
struct RemoveIncompatible <: AbstractLifecycleRelationshipPolicy end
"""Reject lifecycle changes that would make an edge inadmissible."""
struct RejectIncompatible <: AbstractLifecycleRelationshipPolicy end

"""Filter inadmissible lifecycle candidates before selection."""
struct FilterInadmissible <: AbstractLifecycleInadmissibilityPolicy end
"""Fail when a lifecycle request is inadmissible."""
struct ErrorOnInadmissible <: AbstractLifecycleInadmissibilityPolicy end

"""Reject lifecycle requests with ambiguous deterministic precedence."""
struct RejectLifecycleAmbiguity <: AbstractLifecycleConflictPolicy end
"""Resolve lifecycle conflicts by priority and stable semantic identity."""
struct StableLifecyclePriority <: AbstractLifecycleConflictPolicy end

"""Retire cells automatically when their owned-site count reaches zero."""
struct RetireAtZero <: AbstractExtinctionPolicy
    priority::Int32
    function RetireAtZero(; priority::Integer = 0)
        typemin(Int32) <= priority <= typemax(Int32) || throw(ArgumentError(
            "RetireAtZero priority must be representable as Int32"
        ))
        new(Int32(priority))
    end
end
RetireAtZero(priority::Integer) = RetireAtZero(; priority)
"""Reject copy proposals that would make a cell extinct."""
struct ForbidExtinction <: AbstractExtinctionPolicy end

_lifecycle_tuple(values) = values === nothing ? () :
    values isa Tuple ? values :
    values isa AbstractArray ? Tuple(values) : (values,)

function _lifecycle_priority(priority::Integer)
    typemin(Int32) <= priority <= typemax(Int32) || throw(ArgumentError(
        "lifecycle priority must be representable as Int32"
    ))
    return Int32(priority)
end

function _lifecycle_inadmissibility(value)
    value isa AbstractLifecycleInadmissibilityPolicy || throw(ArgumentError(
        "on_inadmissible must be FilterInadmissible() or ErrorOnInadmissible()"
    ))
    return value
end

"""Request creation of a cell under explicit placement and state policies."""
struct CreateCell{K, P, S <: Tuple, I} <: AbstractPottsEffect
    kind::K
    placement::P
    state::S
    priority::Int32
    on_inadmissible::I
end
function CreateCell(kind; placement, state = (), priority::Integer = 0,
        on_inadmissible)
    return CreateCell(
        kind,
        placement,
        _lifecycle_tuple(state),
        _lifecycle_priority(priority),
        _lifecycle_inadmissibility(on_inadmissible),
    )
end

"""Request removal of a cell under explicit replacement and relationship policies."""
struct RemoveCell{C, M, S <: Tuple, R <: Tuple, I} <: AbstractPottsEffect
    cell::C
    replacement::M
    state::S
    relationships::R
    priority::Int32
    on_inadmissible::I
end
function RemoveCell(cell; replacement, state = (), relationships = (),
        priority::Integer = 0, on_inadmissible)
    return RemoveCell(
        cell,
        replacement,
        _lifecycle_tuple(state),
        _lifecycle_tuple(relationships),
        _lifecycle_priority(priority),
        _lifecycle_inadmissibility(on_inadmissible),
    )
end

"""Request retirement of a cell under explicit state and relationship policies."""
struct Retire{C, S <: Tuple, R <: Tuple, I} <: AbstractPottsEffect
    cell::C
    state::S
    relationships::R
    priority::Int32
    on_inadmissible::I
end
function Retire(cell; state = (), relationships = (), priority::Integer = 0,
        on_inadmissible)
    return Retire(
        cell,
        _lifecycle_tuple(state),
        _lifecycle_tuple(relationships),
        _lifecycle_priority(priority),
        _lifecycle_inadmissibility(on_inadmissible),
    )
end

"""Request a cell-kind transition under explicit state policies."""
struct Transition{C, K, S <: Tuple, R <: Tuple, I} <: AbstractPottsEffect
    cell::C
    kind::K
    state::S
    relationships::R
    priority::Int32
    on_inadmissible::I
end
function Transition(cell, kind; state = (), relationships = (),
        priority::Integer = 0, on_inadmissible)
    return Transition(
        cell,
        kind,
        _lifecycle_tuple(state),
        _lifecycle_tuple(relationships),
        _lifecycle_priority(priority),
        _lifecycle_inadmissibility(on_inadmissible),
    )
end

"""Request division of a cell under explicit geometry, state, and relationship policies."""
struct Divide{C, G, R, D, P, K, S <: Tuple, L <: Tuple, I} <:
       AbstractPottsEffect
    cell::C
    geometry::G
    relation::R
    side::D
    parent_kind::P
    daughter_kind::K
    state::S
    relationships::L
    priority::Int32
    on_inadmissible::I
end
function Divide(cell; geometry, relation, side,
        parent_kind = PreserveKind(), daughter_kind = PreserveKind(),
        state = (), relationships = (), priority::Integer = 0,
        on_inadmissible)
    parent_kind isa AbstractLifecycleKindPolicy || throw(ArgumentError(
        "parent_kind must be PreserveKind() or SetKind(kind)"
    ))
    daughter_kind isa AbstractLifecycleKindPolicy || throw(ArgumentError(
        "daughter_kind must be PreserveKind() or SetKind(kind)"
    ))
    return Divide(
        cell,
        geometry,
        relation,
        side,
        parent_kind,
        daughter_kind,
        _lifecycle_tuple(state),
        _lifecycle_tuple(relationships),
        _lifecycle_priority(priority),
        _lifecycle_inadmissibility(on_inadmissible),
    )
end

const AbstractCellLifecycleEffect = Union{
    CreateCell, RemoveCell, Retire, Transition, Divide,
}

_map_symbolic_payload(f, value::AbstractLifecyclePolicy) =
    _map_symbolic_fields(f, value)

function LifecycleProcess(
        id::Union{Symbol, StatementID};
        domain,
        anchor = nothing,
        expression,
        effects,
        phase = Lifecycle(),
        cadence = EveryMCS(),
        source = UnknownSource(),
        kwargs...,
    )
    return LifecycleProcess(_statement_core(
        id,
        (; domain, anchor, expression, effects = _defensive_tuple(effects)),
        (; phase, cadence, kwargs...),
        source,
    ))
end
