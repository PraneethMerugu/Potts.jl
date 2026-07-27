abstract type AbstractUpdateLaw end

struct AdditiveUpdate <: AbstractUpdateLaw end
struct MultiplicativeUpdate <: AbstractUpdateLaw end
struct ReplaceUpdate <: AbstractUpdateLaw end
struct KeyedUpdate <: AbstractUpdateLaw end
struct IndexedUpdate <: AbstractUpdateLaw end
struct SetUpdate <: AbstractUpdateLaw end
struct StableAppend <: AbstractUpdateLaw end

struct UpdateLawContract
    identity::Symbol
    version::String
    ordering::Symbol
    conflict_policy::Symbol
end

law_identity(::AdditiveUpdate) = :add
law_identity(::MultiplicativeUpdate) = :multiply
law_identity(::ReplaceUpdate) = :replace
law_identity(::KeyedUpdate) = :keyed
law_identity(::IndexedUpdate) = :indexed
law_identity(::SetUpdate) = :set
law_identity(::StableAppend) = :append_stable

update_law_contract(law::AbstractUpdateLaw) =
    UpdateLawContract(
        law_identity(law),
        "1.0.0",
        :canonical_producer_event_payload,
        law_identity(law) === :replace ? :single_writer :
        law_identity(law) in (:keyed, :indexed) ? :disjoint_targets :
        law_identity(law) === :set ? :disjoint_add_remove :
        :deterministic_fold,
    )

struct SetPatch{A,R}
    additions::A
    removals::R
end

SetPatch(; additions=(), removals=()) = SetPatch(tuple(additions...), tuple(removals...))

"""
Typed, unpublished state effect. A delta carries the target schema fingerprint,
law version, stable producer, and event identity needed for deterministic
reconciliation.
"""
struct Delta{L<:AbstractUpdateLaw,T}
    target::Path
    schema_identity::String
    law::L
    payload::T
    producer::String
    event_id::String
end

function Delta(
    target::Path,
    schema::LeafSchema,
    law::L,
    payload::T;
    producer::AbstractString,
    event_id::AbstractString,
) where {L<:AbstractUpdateLaw,T}
    isempty(producer) && _fail(:missing_producer_identity,
        "delta producer identity cannot be empty"; target)
    isempty(event_id) && _fail(:missing_event_identity,
        "delta event identity cannot be empty"; target)
    schema.update_law == law_identity(law) ||
        _fail(:update_law_mismatch, "delta law is not admitted by the target schema";
            target, expected=schema.update_law, actual=law_identity(law))
    Delta{L,T}(target, canonical_fingerprint(schema), law, payload,
        String(producer), String(event_id))
end

function delta(
    snapshot::CommittedSnapshot,
    target::Path,
    law::AbstractUpdateLaw,
    payload;
    producer,
    event_id,
)
    schema = schema_at(snapshot.schema, target)
    schema isa LeafSchema ||
        _fail(:delta_targets_branch, "deltas must target leaf schemas"; target)
    Delta(target, schema, law, payload; producer, event_id)
end

_delta_order(effect::Delta) =
    (effect.producer, effect.event_id, canonical_fingerprint(effect.payload))

function _verify_delta(snapshot::CommittedSnapshot, effect::Delta)
    leaf = schema_at(snapshot.schema, effect.target)
    leaf isa LeafSchema ||
        _fail(:delta_targets_branch, "deltas must target leaf schemas"; target=effect.target)
    canonical_fingerprint(leaf) == effect.schema_identity ||
        _fail(:stale_delta_schema, "delta schema identity does not match committed state";
            target=effect.target)
    leaf.update_law == law_identity(effect.law) ||
        _fail(:update_law_mismatch, "delta law is not admitted by target schema";
            target=effect.target, expected=leaf.update_law, actual=law_identity(effect.law))
    leaf
end

function _apply_law(::AdditiveUpdate, current, effects)
    result = deepcopy(current)
    for effect in effects
        result = result + effect.payload
    end
    result
end

function _apply_law(::MultiplicativeUpdate, current, effects)
    result = deepcopy(current)
    for effect in effects
        result = result * effect.payload
    end
    result
end

function _apply_law(::ReplaceUpdate, current, effects)
    length(effects) == 1 ||
        _fail(:replace_conflict, "single-writer replacement received multiple writers";
            producers=Tuple(effect.producer for effect in effects))
    deepcopy(only(effects).payload)
end

function _keyed_pairs(payload)
    payload isa NamedTuple && return collect(Base.pairs(payload))
    payload isa AbstractDict && return collect(Base.pairs(payload))
    payload isa AbstractVector{<:Pair} && return collect(payload)
    payload isa Tuple && all(item -> item isa Pair, payload) && return collect(payload)
    _fail(:invalid_keyed_payload, "keyed updates require a dictionary or collection of pairs";
        type=string(typeof(payload)))
end

function _apply_law(::KeyedUpdate, current, effects)
    current isa AbstractDict ||
        _fail(:invalid_keyed_target, "keyed updates require a dictionary target")
    result = deepcopy(current)
    seen = Set{Any}()
    for effect in effects
        for (key, value) in _keyed_pairs(effect.payload)
            key in seen &&
                _fail(:keyed_update_conflict, "same-time keyed updates overlap"; key)
            push!(seen, key)
            result[key] = deepcopy(value)
        end
    end
    result
end

function _indexed_pairs(payload)
    payload isa Pair && return (payload,)
    payload isa AbstractVector{<:Pair} && return tuple(payload...)
    payload isa Tuple && all(item -> item isa Pair, payload) && return payload
    _fail(:invalid_indexed_payload, "indexed updates require index => value pairs";
        type=string(typeof(payload)))
end

function _apply_law(::IndexedUpdate, current, effects)
    current isa AbstractArray ||
        _fail(:invalid_indexed_target, "indexed updates require an array target")
    result = copy(current)
    seen = Set{Any}()
    for effect in effects
        for (index, value) in _indexed_pairs(effect.payload)
            index in seen &&
                _fail(:indexed_update_conflict, "same-time indexed updates overlap"; index)
            checkbounds(Bool, result, index) ||
                _fail(:indexed_update_bounds, "indexed update is out of bounds"; index)
            push!(seen, index)
            result[index] = value
        end
    end
    result
end

function _apply_law(::SetUpdate, current, effects)
    current isa AbstractSet ||
        _fail(:invalid_set_target, "set updates require a set target")
    result = deepcopy(current)
    additions = Set{Any}()
    removals = Set{Any}()
    for effect in effects
        effect.payload isa SetPatch ||
            _fail(:invalid_set_payload, "set updates require SetPatch payloads")
        union!(additions, effect.payload.additions)
        union!(removals, effect.payload.removals)
    end
    conflict = intersect(additions, removals)
    isempty(conflict) ||
        _fail(:set_update_conflict, "same event adds and removes the same members";
            members=collect(conflict))
    union!(result, additions)
    setdiff!(result, removals)
    result
end

function _apply_law(::StableAppend, current, effects)
    current isa AbstractVector ||
        _fail(:invalid_append_target, "stable append requires a vector target")
    result = copy(current)
    for effect in effects
        payload = effect.payload
        if payload isa AbstractVector || payload isa Tuple
            append!(result, payload)
        else
            push!(result, payload)
        end
    end
    result
end

function reconcile(
    snapshot::CommittedSnapshot,
    effects::AbstractVector{<:Delta},
    time::LogicalTime,
)
    time.scale == snapshot.time.scale ||
        _fail(:time_scale_mismatch, "reconciliation uses the compiled time scale")
    time.tick >= snapshot.time.tick ||
        _fail(:time_regression, "reconciliation cannot commit into the past")
    isempty(effects) &&
        return _committed_snapshot(snapshot, snapshot.entries, time)

    groups = Dict{Path,Vector{Delta}}()
    for effect in effects
        _verify_delta(snapshot, effect)
        push!(get!(groups, effect.target, Delta[]), effect)
    end

    updated = materialize(snapshot)
    for target in sort!(collect(keys(groups)))
        target_effects = groups[target]
        sort!(target_effects; by=_delta_order)
        identities = unique(law_identity(effect.law) for effect in target_effects)
        length(identities) == 1 ||
            _fail(:mixed_update_laws, "one target received incompatible update laws";
                target, laws=Tuple(identities))
        law = first(target_effects).law
        candidate = _apply_law(law, updated[target], target_effects)
        validate_value(schema_at(snapshot.schema, target), candidate)
        updated[target] = candidate
    end

    entries = Pair{Path,Any}[target => updated[target] for target in paths(snapshot)]
    _committed_snapshot(snapshot, tuple(entries...), time)
end

"""
Internal unpublished reconciliation used by the strict serial executor.
It validates and applies the same update algebra as `reconcile` without
manufacturing a committed version or parent link for an intermediate layer.
"""
function _reconcile_unpublished(
    snapshot::CommittedSnapshot,
    effects::AbstractVector{<:Delta},
    time::LogicalTime,
)
    published = reconcile(snapshot, effects, time)
    CommittedSnapshot(
        snapshot.schema,
        published.entries,
        snapshot.version,
        time,
        snapshot.parent_fingerprint,
        snapshot.topology_fingerprint,
    )
end

function _canonical(io::IO, law::AbstractUpdateLaw)
    write(io, "UL")
    _canonical(io, law_identity(law))
    _canonical(io, 1)
end

function _canonical(io::IO, contract::UpdateLawContract)
    write(io, "UC")
    _canonical(io, contract.identity)
    _canonical(io, contract.version)
    _canonical(io, contract.ordering)
    _canonical(io, contract.conflict_policy)
end

function _canonical(io::IO, patch::SetPatch)
    write(io, "SP")
    _canonical(io, patch.additions)
    _canonical(io, patch.removals)
end

function _canonical(io::IO, effect::Delta)
    write(io, "DE")
    _canonical(io, effect.target)
    _canonical(io, effect.schema_identity)
    _canonical(io, effect.law)
    _canonical(io, effect.payload)
    _canonical(io, effect.producer)
    _canonical(io, effect.event_id)
end
