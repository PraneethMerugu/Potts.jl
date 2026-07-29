struct AnyFiniteCellPair end
@inline (::AnyFiniteCellPair)(left_type::UInt32, right_type::UInt32) = true

"""Admit a contact-triggered relationship only when both endpoints have one registered type."""
struct SameCellTypePair
    cell_type::UInt32
end
SameCellTypePair(cell_type::CellTypeID) =
    SameCellTypePair(value(cell_type))
@inline (pair::SameCellTypePair)(
    left_type::UInt32, right_type::UInt32) =
    left_type == pair.cell_type && right_type == pair.cell_type

"""
Generic contact-triggered dynamic elastic-relationship Hamiltonian.

The component owns scientific meaning only. Its mutable, backend-adaptable attempt state is
compiled separately as a `ContactRelationshipTransaction`, so the same declaration works for CPU,
Metal, and ROCm execution.
"""
struct ContactRelationshipHamiltonian{
        Relationships, R, F, T <: AbstractFloat,
        P <: ElasticLinkParameters, N} <: AbstractEnergy
    name::Symbol
    relation::R
    pair_filter::F
    activation_energy::T
    initial_payload::P
    namespace::N
    version::VersionNumber
end

"""
Descriptor-free device view of a contact-relationship Hamiltonian.

The public declaration retains its `VersionNumber` for fingerprints and
checkpoints. Kernel argument conversion removes that host descriptor while
preserving every scientific value and the relationship identity as a type
parameter.
"""
struct ContactRelationshipHamiltonianExecution{
        Relationships, R, F, T <: AbstractFloat,
        P <: ElasticLinkParameters, N} <: AbstractEnergy
    relation::R
    pair_filter::F
    activation_energy::T
    initial_payload::P
    namespace::N
end

function ContactRelationshipHamiltonian(
        name::Symbol, relationships::Symbol;
        relation::StaticCartesianRelation,
        pair_filter = AnyFiniteCellPair(),
        activation_energy::T,
        initial_payload::ElasticLinkParameters,
        namespace::RNGNamespaceIdentity,
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isempty(String(name)) && throw(ArgumentError(
        "contact-relationship Hamiltonian identity must not be empty"))
    isfinite(activation_energy) || throw(ArgumentError(
        "contact-relationship activation energy must be finite"))
    direction_count(relation) <= Int(_RNG_MAX_DRAW) + 2 || throw(
        ArgumentError(
            "contact-relationship permutation exceeds the semantic RNG draw domain"))
    return ContactRelationshipHamiltonian{
        relationships, typeof(relation), typeof(pair_filter), T,
        typeof(initial_payload), typeof(namespace)}(
        name, relation, pair_filter, activation_energy,
        initial_payload, namespace, version)
end

function Adapt.adapt_structure(
        to,
        component::ContactRelationshipHamiltonian{
            Relationships}) where {Relationships}
    relation = Adapt.adapt(to, component.relation)
    pair_filter = Adapt.adapt(to, component.pair_filter)
    payload = Adapt.adapt(to, component.initial_payload)
    namespace = Adapt.adapt(to, component.namespace)
    if to isa Union{Type, UnionAll}
        return ContactRelationshipHamiltonian{
            Relationships, typeof(relation),
            typeof(pair_filter),
            typeof(component.activation_energy),
            typeof(payload), typeof(namespace)}(
            component.name, relation, pair_filter,
            component.activation_energy, payload,
            namespace, component.version)
    end
    return ContactRelationshipHamiltonianExecution{
        Relationships, typeof(relation),
        typeof(pair_filter),
        typeof(component.activation_energy),
        typeof(payload), typeof(namespace)}(
        relation, pair_filter,
        component.activation_energy, payload, namespace)
end

component_identity(component::ContactRelationshipHamiltonian) =
    ComponentIdentity(component.name, component.version,
        :energy)
component_semantic_data(component::ContactRelationshipHamiltonian{
        Relationships}) where {Relationships} = (
    relationships = Relationships,
    relation = component.relation,
    pair_filter = component.pair_filter,
    activation_energy = component.activation_energy,
    initial_payload = component.initial_payload,
    namespace = component.namespace)
required_relations(component::ContactRelationshipHamiltonian) =
    (component.relation, :center_unwrapping)
component_rng_streams(::ContactRelationshipHamiltonian) =
    (AuxiliaryEvolutionStream,)
capabilities(::ContactRelationshipHamiltonian) =
    ScientificCapabilities(dimensions = (2, 3), portable = true)
component_supports_backend(
        ::ContactRelationshipHamiltonian,
        backend::BackendCapabilities) =
    backend.family in (CPUFamily, MetalFamily, AMDGPUFamily) &&
    supports(backend, QualifiedBackendCapability()) &&
    supports(backend, FunctionalBackendCapability()) &&
    supports(backend, OrderedLaunchCapability())
scientific_access(component::ContactRelationshipHamiltonian) =
    SnapshotScientificAccess(
        (component.relation,); cell_wide = true,
        private_workspace = true)
tiled_scientific_access(::ContactRelationshipHamiltonian) =
    UnsupportedTiledScientificAccess()
_non_equilibrium_energy(::ContactRelationshipHamiltonian) = true
accepted_copy_effect_requirement(
        component::ContactRelationshipHamiltonian{
            Relationships}) where {Relationships} = (
    identity = Relationships,
    component,
)

const CONTACT_RELATIONSHIP_SUCCEEDED = UInt32(0)
const CONTACT_RELATIONSHIP_STALE_ENDPOINT = UInt32(1)
const CONTACT_RELATIONSHIP_CAPACITY = UInt32(2)
const CONTACT_RELATIONSHIP_DEGREE = UInt32(3)
const CONTACT_RELATIONSHIP_DUPLICATE = UInt32(4)
const CONTACT_RELATIONSHIP_REMOVAL_CAPACITY = UInt32(5)

struct ContactRelationshipTransaction{
        Name, H, R <: RelationshipExecutionState,
        D <: AbstractVector{UInt16},
        E <: AbstractVector{UInt32},
        G <: AbstractVector{UInt64},
        P <: AbstractVector{UInt8}}
    component::H
    relationships::R
    permutation::D
    candidate_endpoint::E
    candidate_generation::G
    candidate_present::P
    removal_endpoint_a::E
    removal_generation_a::G
    removal_endpoint_b::E
    removal_generation_b::G
    removal_count::E
    status::E
    failing_attempt::E
    attempt_id::E
    mcs_id::G
end

function ContactRelationshipTransaction(
        component::H, relationships::R, permutation::D,
        candidate_endpoint::E, candidate_generation::G,
        candidate_present::P, removal_endpoint_a::E,
        removal_generation_a::G, removal_endpoint_b::E,
        removal_generation_b::G, removal_count::E,
        status::E, failing_attempt::E, attempt_id::E,
        mcs_id::G) where {
        Name, H <: ContactRelationshipHamiltonian{Name},
        R <: RelationshipExecutionState,
        D <: AbstractVector{UInt16},
        E <: AbstractVector{UInt32},
        G <: AbstractVector{UInt64},
        P <: AbstractVector{UInt8}}
    return ContactRelationshipTransaction{Name, H, R, D, E, G, P}(
        component, relationships, permutation,
        candidate_endpoint, candidate_generation, candidate_present,
        removal_endpoint_a, removal_generation_a,
        removal_endpoint_b, removal_generation_b,
        removal_count, status, failing_attempt, attempt_id, mcs_id)
end

function ContactRelationshipTransaction(
        component::ContactRelationshipHamiltonian{Name},
        state::RelationshipState) where {Name}
    state.declaration.name === Name || throw(ArgumentError(
        "contact-relationship component and state identities differ"))
    state.payload isa ElasticLinkColumns || throw(ArgumentError(
        "contact-relationship Hamiltonian requires ElasticLinkParameters payload storage"))
    directions = direction_count(component.relation)
    removal_capacity = max(
        2, Int(state.declaration.maximum_degree))
    permutation = similar(state.endpoint_a, UInt16, directions)
    candidate_endpoint = similar(state.endpoint_a, UInt32, 1)
    candidate_generation = similar(state.generation_a, UInt64, 1)
    candidate_present = similar(state.active, UInt8, 1)
    removal_endpoint_a =
        similar(state.endpoint_a, UInt32, removal_capacity)
    removal_generation_a =
        similar(state.generation_a, UInt64, removal_capacity)
    removal_endpoint_b =
        similar(state.endpoint_b, UInt32, removal_capacity)
    removal_generation_b =
        similar(state.generation_b, UInt64, removal_capacity)
    removal_count = similar(state.count, UInt32, 1)
    status = similar(state.count, UInt32, 1)
    failing_attempt = similar(state.count, UInt32, 1)
    attempt_id = similar(state.count, UInt32, 1)
    mcs_id = similar(state.generation_a, UInt64, 1)
    for array in (
            permutation, candidate_endpoint, candidate_generation,
            candidate_present, removal_endpoint_a, removal_generation_a,
            removal_endpoint_b, removal_generation_b, removal_count,
            status, failing_attempt, attempt_id, mcs_id)
        fill!(array, zero(eltype(array)))
    end
    return ContactRelationshipTransaction(
        component, RelationshipExecutionState(state),
        permutation, candidate_endpoint, candidate_generation,
        candidate_present, removal_endpoint_a, removal_generation_a,
        removal_endpoint_b, removal_generation_b, removal_count,
        status, failing_attempt, attempt_id, mcs_id)
end

function Adapt.adapt_structure(to,
        transaction::ContactRelationshipTransaction{Name}) where {Name}
    component = Adapt.adapt(to, transaction.component)
    relationships = Adapt.adapt(
        to, transaction.relationships)
    permutation = Adapt.adapt(
        to, transaction.permutation)
    candidate_endpoint = Adapt.adapt(
        to, transaction.candidate_endpoint)
    candidate_generation = Adapt.adapt(
        to, transaction.candidate_generation)
    candidate_present = Adapt.adapt(
        to, transaction.candidate_present)
    removal_endpoint_a = Adapt.adapt(
        to, transaction.removal_endpoint_a)
    removal_generation_a = Adapt.adapt(
        to, transaction.removal_generation_a)
    removal_endpoint_b = Adapt.adapt(
        to, transaction.removal_endpoint_b)
    removal_generation_b = Adapt.adapt(
        to, transaction.removal_generation_b)
    removal_count = Adapt.adapt(
        to, transaction.removal_count)
    status = Adapt.adapt(to, transaction.status)
    failing_attempt = Adapt.adapt(
        to, transaction.failing_attempt)
    attempt_id = Adapt.adapt(
        to, transaction.attempt_id)
    mcs_id = Adapt.adapt(to, transaction.mcs_id)
    return ContactRelationshipTransaction{
        Name, typeof(component), typeof(relationships),
        typeof(permutation), typeof(candidate_endpoint),
        typeof(candidate_generation),
        typeof(candidate_present)}(
        component, relationships, permutation,
        candidate_endpoint, candidate_generation,
        candidate_present, removal_endpoint_a,
        removal_generation_a, removal_endpoint_b,
        removal_generation_b, removal_count, status,
        failing_attempt, attempt_id, mcs_id)
end

accepted_copy_effect_binding(
        transaction::ContactRelationshipTransaction{Name}) where {Name} = (
    identity = Name,
    component = transaction.component,
    required = true,
)

function accepted_copy_effect_state_valid(
        transaction::ContactRelationshipTransaction{Name},
        coupled_state::CoupledState) where {Name}
    state = try
        _state_by_name(coupled_state.relationships, Name)
    catch
        return false
    end
    state.payload isa ElasticLinkColumns || return false
    relationships = transaction.relationships
    return relationships.endpoint_a === state.endpoint_a &&
        relationships.generation_a === state.generation_a &&
        relationships.endpoint_b === state.endpoint_b &&
        relationships.generation_b === state.generation_b &&
        relationships.payload.strength === state.payload.strength &&
        relationships.payload.target_length === state.payload.target_length &&
        relationships.payload.maximum_length === state.payload.maximum_length &&
        relationships.active === state.active &&
        relationships.count === state.count &&
        relationships.publication_epoch === state.publication_epoch
end

@inline _relationship_directed(
    ::RelationshipExecutionState{Name, Directed}) where {
    Name, Directed} = Directed
@inline _relationship_maximum_degree(
    ::RelationshipExecutionState{Name, Directed, MaximumDegree}) where {
    Name, Directed, MaximumDegree} = MaximumDegree

@inline function _canonical_raw_relationship(
        relationships::RelationshipExecutionState,
        left::UInt32, left_generation::UInt64,
        right::UInt32, right_generation::UInt64)
    if !_relationship_directed(relationships) &&
            _relationship_raw_less(
                right, right_generation, left, left_generation,
                left, left_generation, right, right_generation)
        return right, right_generation, left, left_generation
    end
    return left, left_generation, right, right_generation
end

@inline function _find_contact_relationship_transaction(
        effects::Tuple, ::Val{Name}) where {Name}
    effect = first(effects)
    effect isa ContactRelationshipTransaction{Name} && return effect
    return _find_contact_relationship_transaction(
        Base.tail(effects), Val(Name))
end
@noinline _find_contact_relationship_transaction(
    ::Tuple{}, ::Val{Name}) where {Name} = throw(ArgumentError(
    "contact-relationship Hamiltonian `$Name` has no compiled attempt transaction"))

@inline function _contact_relationship_transaction(
        workspace::CoupledAttemptWorkspace, ::Val{Name}) where {Name}
    return _find_contact_relationship_transaction(
        workspace.transaction_effects, Val(Name))
end
@inline _contact_relationship_identity(
    ::ContactRelationshipHamiltonian{Name}) where {Name} = Val(Name)
@inline _contact_relationship_identity(
    ::ContactRelationshipHamiltonianExecution{Name}) where {Name} =
    Val(Name)

@inline function _contact_endpoint_current(
        scientific, endpoint::UInt32, generation::UInt64)
    core = scientific.core
    return UInt32(1) <= endpoint <= UInt32(length(core.active)) &&
        @inbounds(core.active[Int(endpoint)] != UInt8(0) &&
            core.generations[Int(endpoint)] == generation)
end

@inline function _contact_relationship_failure!(
        transaction::ContactRelationshipTransaction,
        code::UInt32)
    @inbounds begin
        transaction.status[1] = code
        transaction.failing_attempt[1] =
            transaction.attempt_id[1]
    end
    return false
end
