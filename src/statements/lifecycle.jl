# Closed V1 cell-lifecycle authoring vocabulary. Runtime transaction machinery
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

struct SeedAt{S} <: AbstractLifecyclePlacementPolicy
    site::S
end

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

struct CellCentroid <: AbstractLifecyclePolicy end

struct RandomPlane{P, D} <: AbstractLifecyclePartitionPolicy
    point::P
    draw::D
end
RandomPlane(; point = CellCentroid(), draw = :division_normal) =
    RandomPlane(point, draw)

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

struct SpecifiedNormalPlane{N, P} <: AbstractLifecyclePartitionPolicy
    normal::N
    point::P
end
SpecifiedNormalPlane(normal; point = CellCentroid()) =
    SpecifiedNormalPlane(normal, point)

struct CanonicalSide <: AbstractLifecycleSidePolicy end
struct StableRandomSide{D} <: AbstractLifecycleSidePolicy
    draw_identity::D
end

struct PreserveKind <: AbstractLifecycleKindPolicy end
struct SetKind{K} <: AbstractLifecycleKindPolicy
    kind::K
end

struct InitializeFrom{E} <: AbstractLifecycleStatePolicy
    expression::E
end
struct Unsupported <: AbstractLifecycleStatePolicy end
struct RetireTo{E} <: AbstractLifecycleStatePolicy
    expression::E
end
struct Preserve <: AbstractLifecycleStatePolicy end
struct ResetTo{E} <: AbstractLifecycleStatePolicy
    expression::E
end
struct Transform{E} <: AbstractLifecycleStatePolicy
    expression::E
end
struct CopyToDaughters <: AbstractLifecycleStatePolicy end
struct PreserveParentResetDaughter{E} <: AbstractLifecycleStatePolicy
    expression::E
end
struct ResetBoth{P, D} <: AbstractLifecycleStatePolicy
    parent_expression::P
    daughter_expression::D
end
struct SplitConservatively{F, R} <: AbstractLifecycleStatePolicy
    fraction::F
    rounding::R
end
SplitConservatively(fraction; rounding) =
    SplitConservatively(fraction, rounding)
struct TransformDaughters{P, D} <: AbstractLifecycleStatePolicy
    parent_expression::P
    daughter_expression::D
end
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

struct RejectWhileLinked <: AbstractLifecycleRelationshipPolicy end
struct RemoveIncident <: AbstractLifecycleRelationshipPolicy end
struct PreserveCompatible <: AbstractLifecycleRelationshipPolicy end
struct RemoveIncompatible <: AbstractLifecycleRelationshipPolicy end
struct RejectIncompatible <: AbstractLifecycleRelationshipPolicy end

struct FilterInadmissible <: AbstractLifecycleInadmissibilityPolicy end
struct ErrorOnInadmissible <: AbstractLifecycleInadmissibilityPolicy end

struct RejectLifecycleAmbiguity <: AbstractLifecycleConflictPolicy end
struct StableLifecyclePriority <: AbstractLifecycleConflictPolicy end

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
