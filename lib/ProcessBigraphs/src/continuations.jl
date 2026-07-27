abstract type AbstractContinuationCodec end

struct NoContinuationCodec <: AbstractContinuationCodec end
struct CanonicalContinuationCodec{T} <: AbstractContinuationCodec end
struct LegacyUntrackedContinuation{T} <: AbstractContinuationCodec end

"""
Owner-free reusable continuation schema. It becomes an alpha-qualified contract
only after compilation binds it to a stable owner, owner semantic version, and
schedule identity.
"""
struct ContinuationSchema{C<:AbstractContinuationCodec}
    identity::String
    version::String
    codec_version::String
    codec::C
    invalidated_by::Tuple{Vararg{Symbol}}
end

function ContinuationSchema(
    identity::AbstractString,
    codec::C;
    version::AbstractString="1.0.0",
    codec_version::AbstractString="1.0.0",
    invalidated_by=(:owner_version, :schedule, :schema, :codec),
) where {C<:AbstractContinuationCodec}
    isempty(identity) && _fail(:empty_continuation_schema,
        "continuation schema identity cannot be empty")
    invalidations = tuple(Symbol.(invalidated_by)...)
    allowed = Set((:owner_version, :schedule, :schema, :codec,
        :model, :manual))
    Set(invalidations) <= allowed ||
        _fail(:invalid_continuation_invalidation,
            "continuation schema contains an unknown invalidation rule")
    ContinuationSchema{C}(
        String(identity),
        String(version),
        String(codec_version),
        codec,
        invalidations,
    )
end

stateless_continuation_schema() = ContinuationSchema(
    "process-bigraph-stateless-continuation",
    NoContinuationCodec();
    invalidated_by=(),
)

continuation_schema(::Union{AbstractProcess,AbstractStep}) =
    stateless_continuation_schema()

struct BoundContinuationSpec{S<:ContinuationSchema}
    owner::String
    owner_semantic_version::String
    schedule_identity::String
    schema::S
end

function bind_continuation(
    owner::AbstractString,
    owner_semantic_version::AbstractString,
    schedule_identity::AbstractString,
    schema::ContinuationSchema,
)
    isempty(owner) && _fail(:empty_continuation_owner,
        "continuation owner cannot be empty")
    BoundContinuationSpec(
        String(owner),
        String(owner_semantic_version),
        String(schedule_identity),
        schema,
    )
end

validate_continuation(::NoContinuationCodec, value) =
    isnothing(value) || _fail(:unexpected_continuation,
        "stateless continuation owner proposed state";
        actual=string(typeof(value)))

function validate_continuation(::CanonicalContinuationCodec{T}, value) where {T}
    value isa T || _fail(:continuation_type_mismatch,
        "continuation does not match its registered concrete type";
        expected=string(T), actual=string(typeof(value)))
    encode_logical_value(value)
    true
end

function validate_continuation(::LegacyUntrackedContinuation{T}, value) where {T}
    value isa T || _fail(:continuation_type_mismatch,
        "legacy continuation changed concrete type";
        expected=string(T), actual=string(typeof(value)))
    true
end

function validate_continuation(
    spec::BoundContinuationSpec,
    owner::AbstractString,
    value,
)
    spec.owner == owner || _fail(:continuation_owner_mismatch,
        "continuation specification belongs to another owner";
        expected=spec.owner, actual=owner)
    validate_continuation(spec.schema.codec, value)
end

alpha_eligible(::NoContinuationCodec) = true
alpha_eligible(::CanonicalContinuationCodec) = true
alpha_eligible(::LegacyUntrackedContinuation) = false
alpha_eligible(spec::BoundContinuationSpec) =
    alpha_eligible(spec.schema.codec)

function continuation_fingerprint(spec::BoundContinuationSpec, value)
    validate_continuation(spec, spec.owner, value)
    canonical_fingerprint((
        :typed_continuation_v1,
        spec.owner,
        spec.owner_semantic_version,
        spec.schedule_identity,
        spec.schema,
        value,
    ))
end

function encode_continuation(spec::BoundContinuationSpec, value)
    validate_continuation(spec, spec.owner, value)
    alpha_eligible(spec) || _fail(:untracked_continuation_codec,
        "legacy untracked continuations have no alpha checkpoint codec";
        owner=spec.owner)
    encode_logical_value(value)
end

function decode_continuation(spec::BoundContinuationSpec, bytes)
    alpha_eligible(spec) || _fail(:untracked_continuation_codec,
        "legacy untracked continuations have no alpha checkpoint codec";
        owner=spec.owner)
    value = decode_logical_value(bytes)
    validate_continuation(spec, spec.owner, value)
    value
end

function restore_compatible(
    expected::BoundContinuationSpec,
    actual::BoundContinuationSpec,
)
    expected.owner == actual.owner &&
        expected.owner_semantic_version == actual.owner_semantic_version &&
        expected.schedule_identity == actual.schedule_identity &&
        canonical_fingerprint(expected.schema) ==
            canonical_fingerprint(actual.schema)
end

abstract type AbstractContinuationMigration end

struct IdentityContinuationMigration <: AbstractContinuationMigration
    owner::String
    from_schema::String
    to_schema::String
end

migration_identity(migration::IdentityContinuationMigration) = (
    :identity_continuation_migration_v1,
    migration.owner,
    migration.from_schema,
    migration.to_schema,
)

migrate_value(::IdentityContinuationMigration, value) = deepcopy(value)

function migrate_continuation(
    migration::AbstractContinuationMigration,
    from::BoundContinuationSpec,
    to::BoundContinuationSpec,
    value,
)
    identity = migration_identity(migration)
    identity[2] == from.owner == to.owner ||
        _fail(:continuation_migration_owner_mismatch,
            "continuation migration owner is incompatible")
    identity[3] == from.schema.version &&
        identity[4] == to.schema.version ||
        _fail(:unregistered_continuation_migration,
            "continuation migration does not cover the requested versions";
            owner=from.owner, from=from.schema.version,
            to=to.schema.version)
    migrated = migrate_value(migration, deepcopy(value))
    validate_continuation(to, to.owner, migrated)
    migrated
end

function _canonical(io::IO, schema::ContinuationSchema)
    write(io, "CT")
    _canonical(io, "1.0.0")
    _canonical(io, schema.identity)
    _canonical(io, schema.version)
    _canonical(io, schema.codec_version)
    _canonical(io, string(typeof(schema.codec)))
    _canonical(io, schema.invalidated_by)
end

function _canonical(io::IO, spec::BoundContinuationSpec)
    write(io, "CB")
    _canonical(io, spec.owner)
    _canonical(io, spec.owner_semantic_version)
    _canonical(io, spec.schedule_identity)
    _canonical(io, spec.schema)
end
