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

struct EffectBound
    maximum::Int
    basis::Symbol
    function EffectBound(maximum::Integer, basis::Symbol)
        maximum >= 0 || throw(ArgumentError("an effect bound must be nonnegative"))
        new(Int(maximum), basis)
    end
end

struct RandomOperation
    identity::Symbol
    family::Symbol
    reserved::Bool
end

struct EngineAdmission
    engine::Symbol
    admitted::Bool
    reason::String
end

struct QualifiedStatement{S, N, T, U, C, R, W, E, B, G, P, O, A}
    identity::QualifiedStatementID
    kind::Symbol
    schema_version::VersionNumber
    source::S
    provenance::N
    normalized_payload::T
    units::U
    reference_conversion::C
    reads::R
    writes::W
    effect::E
    bound::B
    random_operations::G
    phase::P
    ordering_dependencies::O
    engine_admission::A
    lowering_identity::Symbol
end

struct SemanticFingerprint
    hex::String
end
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
struct Statements <: AbstractInspectionSelector end
struct Variables <: AbstractInspectionSelector end
struct Effects <: AbstractInspectionSelector end
struct RandomOperations <: AbstractInspectionSelector end
struct Schedule <: AbstractInspectionSelector end
struct Capabilities <: AbstractInspectionSelector end
struct Fingerprints <: AbstractInspectionSelector end
struct StoragePlan <: AbstractInspectionSelector end
struct Kernels <: AbstractInspectionSelector end
