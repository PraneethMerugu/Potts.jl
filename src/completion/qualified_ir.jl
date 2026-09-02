"""Path-qualified identity of a statement in a composed Potts system."""
struct QualifiedStatementID
    path::Tuple{Vararg{Symbol}}
    local_id::StatementID
end

function Base.show(io::IO, id::QualifiedStatementID)
    parts = (id.path..., Symbol(id.local_id))
    print(io, join(String.(parts), "₊"))
end
Base.string(id::QualifiedStatementID) = sprint(show, id)
Base.:(==)(left::QualifiedStatementID, right::QualifiedStatementID) =
    left.path == right.path && left.local_id == right.local_id
Base.hash(id::QualifiedStatementID, seed::UInt) =
    hash(id.local_id, hash(id.path, seed))

"""Finite maximum number of effects and the basis on which it is counted."""
struct EffectBound
    maximum::Int
    basis::Symbol
    function EffectBound(maximum::Integer, basis::Symbol)
        maximum >= 0 || throw(ArgumentError("an effect bound must be nonnegative"))
        new(Int(maximum), basis)
    end
end

"""Completed semantic-random operation identity and distribution family."""
struct RandomOperation
    identity::Symbol
    family::Symbol
    reserved::Bool
end

"""Admission result and reason for one execution-engine family."""
struct EngineAdmission
    engine::Symbol
    admitted::Bool
    reason::String
end

"""Completed, source-aware semantic record for one Potts statement."""
struct QualifiedStatement{
        S, M, N, T, Y, H, U, C, R, W, Q, D, Z, E, B, X, L, G, P, O, A,
    }
    identity::QualifiedStatementID
    kind::Symbol
    schema_version::VersionNumber
    source::S
    normalized_statement::M
    provenance::N
    normalized_payload::T
    result_type::Y
    shape::H
    units::U
    reference_conversion::C
    reads::R
    writes::W
    ownership::Q
    persistence::D
    resources::Z
    effect::E
    bound::B
    transaction_identity::X
    lifecycle::L
    random_operations::G
    phase::P
    ordering_dependencies::O
    engine_admission::A
    lowering_identity::Symbol
end

"""Fingerprint of authored scientific meaning before completion."""
struct SemanticFingerprint
    hex::String
end
"""Fingerprint of the completed system and its inferred contracts."""
struct CompletedSystemFingerprint
    hex::String
end
struct ExecutableFingerprint
    hex::String
end

for fingerprint_type in (
        SemanticFingerprint, CompletedSystemFingerprint, ExecutableFingerprint
    )
    @eval begin
        Base.string(value::$fingerprint_type) = value.hex
        Base.:(==)(left::$fingerprint_type, right::$fingerprint_type) =
            left.hex == right.hex
        Base.hash(value::$fingerprint_type, seed::UInt) = hash(value.hex, seed)
        Base.show(io::IO, value::$fingerprint_type) =
            print(io, $(string(fingerprint_type)), "(\"", value.hex, "\")")
    end
end

abstract type AbstractInspectionSelector end
"""Inspection selector for completed or scheduled statement records."""
struct Statements <: AbstractInspectionSelector end
"""Inspection selector for the qualified variable inventory."""
struct Variables <: AbstractInspectionSelector end
"""Inspection selector for effect and publication semantics."""
struct Effects <: AbstractInspectionSelector end
"""Inspection selector for semantic random-operation identities."""
struct RandomOperations <: AbstractInspectionSelector end
"""Inspection selector for the ordered execution schedule."""
struct Schedule <: AbstractInspectionSelector end
"""Inspection selector for backend and algorithm capability results."""
struct Capabilities <: AbstractInspectionSelector end
"""Inspection selector for semantic, completed, and scheduled fingerprints."""
struct Fingerprints <: AbstractInspectionSelector end
struct StoragePlan <: AbstractInspectionSelector end
struct Kernels <: AbstractInspectionSelector end
"""Inspection selector for the ordered runtime parameter schema."""
struct ParameterSchema <: AbstractInspectionSelector end
"""Inspection selector for state storage and initialization schemas."""
struct StateSchema <: AbstractInspectionSelector end
"""Inspection selector for declared observations and schedules."""
struct Observations <: AbstractInspectionSelector end
"""Inspection selector for external input and output contracts."""
struct ExternalIO <: AbstractInspectionSelector end
"""Inspection selector for deterministic replay and checkpoint guarantees."""
struct ReplayContract <: AbstractInspectionSelector end
"""Inspection selector for completed cell-lifecycle plans."""
struct LifecyclePlans <: AbstractInspectionSelector end
