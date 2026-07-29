const STRUCTURAL_TRANSACTION_VERSION = "process-bigraph-structural-transaction-v1"

const _STRUCTURAL_LAYOUT = (
    Composite=(
        attrs=(:composite_id, :composite_definition_id, :scale_numerator,
            :scale_denominator, :scale_unit),
        homs=(),
        id=:composite_id,
    ),
    StoreNode=(
        attrs=(:store_id, :store_path, :store_local_path, :schema_kind,
            :schema_payload),
        homs=(:store_composite,),
        id=:store_id,
    ),
    StoreContainment=(
        attrs=(:containment_id,),
        homs=(:containment_child, :containment_parent),
        id=:containment_id,
    ),
    CompositeContainment=(
        attrs=(:composite_containment_id, :mount_key),
        homs=(:composite_child, :composite_parent),
        id=:composite_containment_id,
    ),
    Actor=(
        attrs=(:actor_id, :actor_local_id, :law_type, :law_version,
            :law_parameters, :capability_payload, :actor_domain,
            :continuation_version),
        homs=(:actor_composite,),
        id=:actor_id,
    ),
    Process=(
        attrs=(:cadence_tick, :first_due_tick, :supports_partial),
        homs=(:process_actor,),
        id=nothing,
    ),
    Step=(
        attrs=(),
        homs=(:step_actor,),
        id=nothing,
    ),
    Port=(
        attrs=(:port_id, :port_name, :port_value_type, :port_direction,
            :port_effect, :port_interval_behavior, :port_optional,
            :port_cardinality, :port_residency, :port_update_law),
        homs=(:port_actor,),
        id=:port_id,
    ),
    Binding=(
        attrs=(:binding_id, :transfer_payload),
        homs=(:binding_port, :binding_store),
        id=:binding_id,
    ),
    StepDependency=(
        attrs=(:dependency_id,),
        homs=(:dependency_before, :dependency_after),
        id=:dependency_id,
    ),
    Endpoint=(
        attrs=(:endpoint_id, :endpoint_name, :endpoint_role,
            :endpoint_origin_store_id, :endpoint_local_path,
            :endpoint_schema_payload),
        homs=(),
        id=:endpoint_id,
    ),
    BoundaryMap=(
        attrs=(:boundary_map_id,),
        homs=(:boundary_map_endpoint, :boundary_map_store,
            :boundary_map_composite),
        id=:boundary_map_id,
    ),
    Junction=(
        attrs=(:junction_id,),
        homs=(:junction_store, :junction_composite),
        id=:junction_id,
    ),
    JunctionEndpoint=(
        attrs=(:junction_endpoint_id,),
        homs=(:junction_endpoint_junction, :junction_endpoint_endpoint),
        id=:junction_endpoint_id,
    ),
)

const _STRUCTURAL_HOM_TARGET = Dict{Symbol,Symbol}(
    :store_composite => :Composite,
    :containment_child => :StoreNode,
    :containment_parent => :StoreNode,
    :composite_child => :Composite,
    :composite_parent => :Composite,
    :actor_composite => :Composite,
    :process_actor => :Actor,
    :step_actor => :Actor,
    :port_actor => :Actor,
    :binding_port => :Port,
    :binding_store => :StoreNode,
    :dependency_before => :Step,
    :dependency_after => :Step,
    :boundary_map_endpoint => :Endpoint,
    :boundary_map_store => :StoreNode,
    :boundary_map_composite => :Composite,
    :junction_store => :StoreNode,
    :junction_composite => :Composite,
    :junction_endpoint_junction => :Junction,
    :junction_endpoint_endpoint => :Endpoint,
)

struct StructuralIdentity
    kind::Symbol
    id::String
    generation::UInt64
    function StructuralIdentity(
        kind::Symbol,
        id::AbstractString,
        generation::Integer=0,
    )
        kind in keys(_STRUCTURAL_LAYOUT) ||
            _fail(:invalid_structural_identity_kind,
                "structural identity kind is not in the canonical ACSet";
                kind)
        isempty(id) &&
            _fail(:empty_structural_identity,
                "structural identity cannot be empty"; kind)
        generation >= 0 ||
            _fail(:invalid_structural_generation,
                "structural identity generation cannot be negative";
                kind, generation)
        generation <= typemax(UInt64) ||
            _fail(:structural_generation_overflow,
                "structural identity generation exceeds UInt64";
                kind, generation)
        new(kind, String(id), UInt64(generation))
    end
end

struct StructuralIdentityRecord
    identity::StructuralIdentity
    status::Symbol
    birth_epoch::UInt64
    retired_epoch::Union{Nothing,UInt64}
    function StructuralIdentityRecord(
        identity::StructuralIdentity,
        status::Symbol,
        birth_epoch::Integer,
        retired_epoch,
    )
        status in (:active, :retired) ||
            _fail(:invalid_structural_identity_status,
                "structural identity status must be active or retired";
                status)
        birth_epoch >= 0 ||
            _fail(:invalid_structural_birth_epoch,
                "structural birth epoch cannot be negative"; birth_epoch)
        if status === :active
            isnothing(retired_epoch) ||
                _fail(:active_identity_has_retirement,
                    "an active identity cannot have a retirement epoch";
                    identity=identity.id)
        else
            retired_epoch isa Integer && retired_epoch >= birth_epoch ||
                _fail(:invalid_structural_retirement_epoch,
                    "a retired identity requires a valid retirement epoch";
                    identity=identity.id)
        end
        new(identity, status, UInt64(birth_epoch),
            isnothing(retired_epoch) ? nothing : UInt64(retired_epoch))
    end
end

struct StructuralLineage
    child::StructuralIdentity
    parent::Union{Nothing,StructuralIdentity}
    birth_event::String
    birth_epoch::UInt64
end

struct StructuralCapacity
    composites::Int
    total_parts::Int
    function StructuralCapacity(;
        composites::Integer=typemax(Int),
        total_parts::Integer=typemax(Int),
    )
        composites > 0 ||
            _fail(:invalid_structural_capacity,
                "composite capacity must be positive"; composites)
        total_parts > 0 ||
            _fail(:invalid_structural_capacity,
                "total structural-part capacity must be positive";
                total_parts)
        composites <= typemax(Int) && total_parts <= typemax(Int) ||
            _fail(:structural_capacity_overflow,
                "structural capacity exceeds Int")
        new(Int(composites), Int(total_parts))
    end
end

struct CompositeDivisionPolicy
    state::Symbol
    relationships::Symbol
    schedule::Symbol
    bindings::Symbol
    continuation::Symbol
    function CompositeDivisionPolicy(;
        state::Symbol=:initialize,
        relationships::Symbol=:none,
        schedule::Symbol=:next_selection,
        bindings::Symbol=:none,
        continuation::Symbol=:reconstruct,
    )
        state in (:initialize,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division requires initialized state";
                policy=:state, value=state)
        relationships in (:none,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division cannot implicitly copy relationships";
                policy=:relationships, value=relationships)
        schedule in (:next_selection,) ||
            _fail(:unsupported_division_policy,
                "a daughter composite first runs at the next scheduler selection";
                policy=:schedule, value=schedule)
        bindings in (:none,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division cannot implicitly copy bindings";
                policy=:bindings, value=bindings)
        continuation in (:reconstruct,) ||
            _fail(:unsupported_division_policy,
                "a daughter composite requires reconstructed continuation";
                policy=:continuation, value=continuation)
        new(state, relationships, schedule, bindings, continuation)
    end
end

struct DynamicStructuralEpoch
    contract_version::String
    ordinal::UInt64
    structure::ConcreteProcessBigraphACSet
    fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    capacity::StructuralCapacity
end

abstract type AbstractStructuralRequest end

struct AddCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    parent::StructuralIdentity
    definition_id::String
    mount_key::Symbol
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct RemoveCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    owned_closure::Tuple{Vararg{StructuralIdentity}}
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct DivideCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    daughter_definition_id::String
    daughter_mount_key::Symbol
    policies::CompositeDivisionPolicy
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct MoveCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    new_parent::StructuralIdentity
    mount_key::Symbol
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct RewireBindingRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    binding::StructuralIdentity
    new_store::StructuralIdentity
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

function _request_fields(
    request_id::AbstractString,
    source_epoch::Integer,
    dependencies,
    priority::Integer,
)
    isempty(request_id) &&
        _fail(:empty_structural_request_identity,
            "structural request identity cannot be empty")
    source_epoch >= 0 ||
        _fail(:invalid_structural_source_epoch,
            "structural source epoch cannot be negative"; source_epoch)
    source_epoch <= typemax(UInt64) ||
        _fail(:structural_source_epoch_overflow,
            "structural source epoch exceeds UInt64"; source_epoch)
    priority >= typemin(Int) && priority <= typemax(Int) ||
        _fail(:structural_priority_overflow,
            "structural request priority exceeds Int"; priority)
    deps = tuple(sort!(unique!(String[String(value) for value in dependencies]))...)
    any(isempty, deps) &&
        _fail(:empty_structural_dependency,
            "structural dependency identity cannot be empty";
            request_id=String(request_id))
    String(request_id), UInt64(source_epoch), deps, Int(priority)
end

function AddCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    parent::StructuralIdentity,
    definition_id::AbstractString,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
)
    parent.kind === :Composite ||
        _fail(:invalid_add_parent,
            "add parent must be a Composite identity";
            kind=parent.kind)
    isempty(definition_id) &&
        _fail(:empty_composite_definition,
            "added composite definition identity cannot be empty")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    AddCompositeRequest(rid, epoch, parent, String(definition_id), mount_key,
        deps, rank)
end

function RemoveCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity;
    owned_closure=(target,),
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite ||
        _fail(:invalid_remove_target,
            "remove target must be a Composite identity";
            kind=target.kind)
    closure = tuple(sort!(unique!(StructuralIdentity[owned_closure...]);
        by=value -> (String(value.kind), value.id, value.generation))...)
    all(value -> value.kind === :Composite, closure) ||
        _fail(:invalid_owned_closure,
            "remove owned closure may contain only Composite identities")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    RemoveCompositeRequest(rid, epoch, target, closure, deps, rank)
end

function DivideCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    daughter_definition_id::AbstractString,
    daughter_mount_key::Symbol;
    policies::CompositeDivisionPolicy=CompositeDivisionPolicy(),
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite ||
        _fail(:invalid_divide_target,
            "divide target must be a Composite identity";
            kind=target.kind)
    isempty(daughter_definition_id) &&
        _fail(:empty_composite_definition,
            "daughter definition identity cannot be empty")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    DivideCompositeRequest(rid, epoch, target,
        String(daughter_definition_id), daughter_mount_key, policies,
        deps, rank)
end

function MoveCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    new_parent::StructuralIdentity,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite && new_parent.kind === :Composite ||
        _fail(:invalid_move_identity,
            "move target and parent must be Composite identities";
            target_kind=target.kind, parent_kind=new_parent.kind)
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    MoveCompositeRequest(rid, epoch, target, new_parent, mount_key,
        deps, rank)
end

function RewireBindingRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    binding::StructuralIdentity,
    new_store::StructuralIdentity;
    dependencies=(),
    priority::Integer=0,
)
    binding.kind === :Binding && new_store.kind === :StoreNode ||
        _fail(:invalid_rewire_identity,
            "rewire requires Binding and StoreNode identities";
            binding_kind=binding.kind, store_kind=new_store.kind)
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    RewireBindingRequest(rid, epoch, binding, new_store, deps, rank)
end

struct StructuralRequestDisposition
    request_id::String
    status::Symbol
    conflicting_with::Union{Nothing,String}
end

struct StagedStructuralTransaction
    contract_version::String
    source_ordinal::UInt64
    source_fingerprint::String
    candidate_structure::ConcreteProcessBigraphACSet
    candidate_fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    dispositions::Tuple{Vararg{StructuralRequestDisposition}}
    numeric_candidate::Any
end

struct StructuralEpochCheckpoint
    contract_version::String
    ordinal::UInt64
    structure::ConcreteProcessBigraphACSet
    epoch_fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    capacity::StructuralCapacity
    checksum::String
end

function _canonical(io::IO, identity::StructuralIdentity)
    write(io, "SI")
    _canonical(io, identity.kind)
    _canonical(io, identity.id)
    _canonical(io, identity.generation)
end

function _canonical(io::IO, record::StructuralIdentityRecord)
    write(io, "IR")
    _canonical(io, record.identity)
    _canonical(io, record.status)
    _canonical(io, record.birth_epoch)
    _canonical(io, record.retired_epoch)
end

function _canonical(io::IO, lineage::StructuralLineage)
    write(io, "LN")
    _canonical(io, lineage.child)
    _canonical(io, lineage.parent)
    _canonical(io, lineage.birth_event)
    _canonical(io, lineage.birth_epoch)
end

function _structural_identity_records(
    structure::ConcreteProcessBigraphACSet,
    ordinal::UInt64,
)
    records = StructuralIdentityRecord[]
    for (object, layout) in pairs(_STRUCTURAL_LAYOUT)
        isnothing(layout.id) && continue
        for row in _rows(structure, object)
            identity = StructuralIdentity(
                object, String(_attr(structure, row, layout.id)), 0)
            push!(records,
                StructuralIdentityRecord(identity, :active, ordinal, nothing))
        end
    end
    tuple(sort!(records; by=record ->
        (String(record.identity.kind), record.identity.id,
            record.identity.generation))...)
end

function _structural_epoch_fingerprint(
    ordinal::UInt64,
    structure::ConcreteProcessBigraphACSet,
    identities,
    lineage,
    capacity::StructuralCapacity,
)
    canonical_fingerprint((
        STRUCTURAL_TRANSACTION_VERSION,
        ordinal,
        structural_fingerprint(structure),
        identities,
        lineage,
        (capacity.composites, capacity.total_parts),
    ))
end
