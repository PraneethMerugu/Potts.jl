struct StableRelationshipPriority end

abstract type AbstractRelationshipRequest end
struct CreateRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
CreateRelationship(left, right, payload; priority::Integer = 0) =
    CreateRelationship(left, right, payload, Int32(priority))
struct RemoveRelationship <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    priority::Int32
end
RemoveRelationship(left, right; priority::Integer = 0) =
    RemoveRelationship(left, right, Int32(priority))
struct RetuneRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
RetuneRelationship(left, right, payload; priority::Integer = 0) =
    RetuneRelationship(left, right, payload, Int32(priority))

const RELATIONSHIP_REMOVE_REQUEST = UInt8(1)
const RELATIONSHIP_RETUNE_REQUEST = UInt8(2)
const RELATIONSHIP_CREATE_REQUEST = UInt8(3)

struct RelationshipTransactionWorkspace{
        E <: AbstractVector{UInt32}, G <: AbstractVector{UInt64},
        P <: AbstractVector, A <: AbstractVector{UInt8},
        C <: AbstractVector{UInt32}, K <: AbstractVector{UInt8},
        R <: AbstractVector{Int32}}
    candidate_endpoint_a::E
    candidate_generation_a::G
    candidate_endpoint_b::E
    candidate_generation_b::G
    candidate_payload::P
    candidate_active::A
    candidate_count::C
    request_kind::K
    request_endpoint_a::E
    request_generation_a::G
    request_endpoint_b::E
    request_generation_b::G
    request_payload::P
    request_priority::R
    request_count::C
    status::C
    failing_request::C
end

function RelationshipTransactionWorkspace(
        state::RelationshipState; request_capacity::Integer =
            Int(state.declaration.capacity.value))
    request_capacity > 0 || throw(ArgumentError(
        "relationship request capacity must be positive"))
    candidate_endpoint_a = similar(state.endpoint_a)
    candidate_generation_a = similar(state.generation_a)
    candidate_endpoint_b = similar(state.endpoint_b)
    candidate_generation_b = similar(state.generation_b)
    candidate_payload = similar(state.payload)
    candidate_active = similar(state.active)
    request_endpoint_a = similar(state.endpoint_a, UInt32, request_capacity)
    request_generation_a = similar(
        state.generation_a, UInt64, request_capacity)
    request_endpoint_b = similar(state.endpoint_b, UInt32, request_capacity)
    request_generation_b = similar(
        state.generation_b, UInt64, request_capacity)
    request_payload = similar(state.payload, eltype(state.payload), request_capacity)
    request_kind = similar(state.active, UInt8, request_capacity)
    request_priority = similar(state.endpoint_a, Int32, request_capacity)
    candidate_count = similar(state.count)
    request_count = similar(state.count)
    status = similar(state.count)
    failing_request = similar(state.count)
    for array in (
            candidate_endpoint_a, candidate_generation_a,
            candidate_endpoint_b, candidate_generation_b,
            candidate_active, request_endpoint_a, request_generation_a,
            request_endpoint_b, request_generation_b, request_kind,
            request_priority, candidate_count, request_count,
            status, failing_request)
        fill!(array, zero(eltype(array)))
    end
    return RelationshipTransactionWorkspace(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_priority, request_count, status, failing_request)
end

function Adapt.adapt_structure(to,
        workspace::RelationshipTransactionWorkspace)
    return RelationshipTransactionWorkspace(
        Adapt.adapt(to, workspace.candidate_endpoint_a),
        Adapt.adapt(to, workspace.candidate_generation_a),
        Adapt.adapt(to, workspace.candidate_endpoint_b),
        Adapt.adapt(to, workspace.candidate_generation_b),
        Adapt.adapt(to, workspace.candidate_payload),
        Adapt.adapt(to, workspace.candidate_active),
        Adapt.adapt(to, workspace.candidate_count),
        Adapt.adapt(to, workspace.request_kind),
        Adapt.adapt(to, workspace.request_endpoint_a),
        Adapt.adapt(to, workspace.request_generation_a),
        Adapt.adapt(to, workspace.request_endpoint_b),
        Adapt.adapt(to, workspace.request_generation_b),
        Adapt.adapt(to, workspace.request_payload),
        Adapt.adapt(to, workspace.request_priority),
        Adapt.adapt(to, workspace.request_count),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_request))
end

@inline _relationship_request_kind(::RemoveRelationship) =
    RELATIONSHIP_REMOVE_REQUEST
@inline _relationship_request_kind(::RetuneRelationship) =
    RELATIONSHIP_RETUNE_REQUEST
@inline _relationship_request_kind(::CreateRelationship) =
    RELATIONSHIP_CREATE_REQUEST

function stage_relationship_requests!(
        workspace::RelationshipTransactionWorkspace,
        declaration::RelationshipSet, requests)
    ordered = collect(requests)
    all(request -> request isa AbstractRelationshipRequest, ordered) ||
        throw(ArgumentError(
            "relationship transaction contains an untyped request"))
    sort!(ordered; by = _request_key)
    length(ordered) <= length(workspace.request_kind) || throw(
        RelationshipCapacityError(
            declaration.name, length(ordered),
            UInt32(length(workspace.request_kind))))
    previous = nothing
    for (index, request) in enumerate(ordered)
        left, right = _canonical_endpoints(
            declaration, request.left, request.right)
        key = (left, right)
        key == previous && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        previous = key
        payload = request isa RemoveRelationship ?
            workspace.request_payload[index] :
            convert(eltype(workspace.request_payload), request.payload)
        @inbounds begin
            workspace.request_kind[index] =
                _relationship_request_kind(request)
            workspace.request_endpoint_a[index] = value(left.cell)
            workspace.request_generation_a[index] =
                value(left.generation)
            workspace.request_endpoint_b[index] = value(right.cell)
            workspace.request_generation_b[index] =
                value(right.generation)
            request isa RemoveRelationship ||
                (workspace.request_payload[index] = payload)
            workspace.request_priority[index] = request.priority
        end
    end
    workspace.request_count[1] = UInt32(length(ordered))
    return workspace
end

function clear_relationship_requests!(
        workspace::RelationshipTransactionWorkspace)
    workspace.request_count[1] = UInt32(0)
    return workspace
end

@inline function _relationship_endpoint_is_current(
        active, generations, endpoint::UInt32, generation::UInt64)
    return UInt32(1) <= endpoint <= UInt32(length(active)) &&
        @inbounds(active[Int(endpoint)] != zero(eltype(active)) &&
            generations[Int(endpoint)] == generation)
end

@inline function _relationship_raw_edge_index(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, left, left_generation, right, right_generation)
    for index in 1:count
        @inbounds if active[index] != UInt8(0) &&
                endpoint_a[index] == left &&
                generation_a[index] == left_generation &&
                endpoint_b[index] == right &&
                generation_b[index] == right_generation
            return index
        end
    end
    return 0
end

@inline function _relationship_raw_degree(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, endpoint, generation)
    degree = 0
    for index in 1:count
        @inbounds active[index] == UInt8(0) && continue
        @inbounds degree += (
            (endpoint_a[index] == endpoint &&
             generation_a[index] == generation) ||
            (endpoint_b[index] == endpoint &&
             generation_b[index] == generation))
    end
    return degree
end

@inline function _relationship_raw_copy!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, destination, source)
    @inbounds begin
        endpoint_a[destination] = endpoint_a[source]
        generation_a[destination] = generation_a[source]
        endpoint_b[destination] = endpoint_b[source]
        generation_b[destination] = generation_b[source]
        payload[destination] = payload[source]
        active[destination] = active[source]
    end
    return nothing
end

@inline function _relationship_raw_less(
        left_a, left_ga, left_b, left_gb,
        right_a, right_ga, right_b, right_gb)
    left_a != right_a && return left_a < right_a
    left_ga != right_ga && return left_ga < right_ga
    left_b != right_b && return left_b < right_b
    return left_gb < right_gb
end

"""Admit every pair of distinct active finite cells for contact-triggered relationship formation."""
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
    return ContactRelationshipTransaction(
        Adapt.adapt(to, transaction.component),
        Adapt.adapt(to, transaction.relationships),
        Adapt.adapt(to, transaction.permutation),
        Adapt.adapt(to, transaction.candidate_endpoint),
        Adapt.adapt(to, transaction.candidate_generation),
        Adapt.adapt(to, transaction.candidate_present),
        Adapt.adapt(to, transaction.removal_endpoint_a),
        Adapt.adapt(to, transaction.removal_generation_a),
        Adapt.adapt(to, transaction.removal_endpoint_b),
        Adapt.adapt(to, transaction.removal_generation_b),
        Adapt.adapt(to, transaction.removal_count),
        Adapt.adapt(to, transaction.status),
        Adapt.adapt(to, transaction.failing_attempt),
        Adapt.adapt(to, transaction.attempt_id),
        Adapt.adapt(to, transaction.mcs_id))
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

function begin_accepted_copy_mcs!(
        transaction::ContactRelationshipTransaction,
        scientific_state, mcs)
    @inbounds begin
        transaction.status[1] = CONTACT_RELATIONSHIP_SUCCEEDED
        transaction.failing_attempt[1] = UInt32(0)
        transaction.candidate_present[1] = UInt8(0)
        transaction.removal_count[1] = UInt32(0)
        transaction.mcs_id[1] = UInt64(mcs)
    end
    return nothing
end

@inline function _contact_permutation!(
        destination, rng::Philox4x32x10V1, seed::UInt64,
        namespace::RNGNamespaceIdentity, mcs::UInt64,
        zero_based_attempt::UInt32)
    for index in eachindex(destination)
        @inbounds destination[index] =
            Base.unsafe_trunc(UInt16, index)
    end
    address = _rng_address_unchecked(
        AuxiliaryEvolutionStream, mcs, UInt8(0),
        extension_rng_operation(namespace), GlobalEntity,
        zero_based_attempt, UInt64(0), UInt8(0), UInt16(0))
    length_value = length(destination)
    for index in length_value:-1:2
        draw = Base.unsafe_trunc(
            UInt16, length_value - index)
        selected = Int(bounded_uint(
            rng, seed, _with_draw(address, draw),
            Base.unsafe_trunc(UInt32, index))) + 1
        @inbounds destination[index], destination[selected] =
            destination[selected], destination[index]
    end
    return destination
end

function prepare_accepted_copy_effect!(
        transaction::ContactRelationshipTransaction,
        proposal, staged, scientific, rng, seed, mcs, attempt_id)
    @inbounds begin
        transaction.candidate_present[1] = UInt8(0)
        transaction.removal_count[1] = UInt32(0)
        transaction.attempt_id[1] = attempt_id - UInt32(1)
    end
    is_cell_owner(proposal.gaining) || return nothing
    relationships = transaction.relationships
    gaining = proposal.gaining.value
    gaining_generation =
        @inbounds scientific.core.generations[Int(gaining)]
    gaining_degree = _relationship_raw_degree(
        relationships.endpoint_a, relationships.generation_a,
        relationships.endpoint_b, relationships.generation_b,
        relationships.active, Int(@inbounds relationships.count[1]),
        gaining, gaining_generation)
    gaining_degree < _relationship_maximum_degree(relationships) ||
        return nothing
    component = transaction.component
    _contact_permutation!(
        transaction.permutation, rng, seed,
        component.namespace, mcs,
        @inbounds(transaction.attempt_id[1]))
    gaining_type =
        @inbounds scientific.core.cell_types[Int(gaining)]
    count = Int(@inbounds relationships.count[1])
    for permutation_index in eachindex(transaction.permutation)
        direction = Int(@inbounds transaction.permutation[permutation_index])
        neighbor = _realize_neighbor_unchecked(
            scientific.domain, component.relation,
            proposal.recipient, direction)
        neighbor.kind === MutableNeighbor || continue
        owner = _proposal_owner_at(scientific, neighbor.site)
        is_cell_owner(owner) || continue
        owner.value == gaining && continue
        neighbor_type =
            @inbounds scientific.core.cell_types[Int(owner.value)]
        component.pair_filter(gaining_type, neighbor_type) || continue
        neighbor_generation =
            @inbounds scientific.core.generations[Int(owner.value)]
        _relationship_raw_degree(
            relationships.endpoint_a, relationships.generation_a,
            relationships.endpoint_b, relationships.generation_b,
            relationships.active, count,
            owner.value, neighbor_generation) <
            _relationship_maximum_degree(relationships) || continue
        left, left_generation, right, right_generation =
            _canonical_raw_relationship(
                relationships, gaining, gaining_generation,
                owner.value, neighbor_generation)
        _relationship_raw_edge_index(
            relationships.endpoint_a, relationships.generation_a,
            relationships.endpoint_b, relationships.generation_b,
            relationships.active, count,
            left, left_generation, right, right_generation) == 0 ||
            continue
        @inbounds begin
            transaction.candidate_endpoint[1] = owner.value
            transaction.candidate_generation[1] =
                neighbor_generation
            transaction.candidate_present[1] = UInt8(1)
        end
        break
    end
    return nothing
end

@inline function _contact_postcopy_center(
        scientific, proposal, moments, endpoint::UInt32)
    owner = CellOwner(endpoint)
    if owner == proposal.losing
        volume =
            @inbounds scientific.trackers.finite_volumes[Int(endpoint)]
        volume == 1 && return nothing
    end
    return owner == proposal.losing || owner == proposal.gaining ?
        _proposed_center(
            scientific, owner, proposal, moments) :
        unwrapped_center(scientific, owner)
end

@inline function _contact_link_energy(
        scientific, left::UInt32, right::UInt32,
        strength, target_length, left_center, right_center)
    displacement = _minimum_image_displacement(
        scientific, left, right, left_center, right_center)
    distance = sqrt(sum(abs2, displacement))
    return strength * (distance - target_length)^2
end

@inline function energy_change(
        component::ContactRelationshipHamiltonian,
        proposal::CopyProposal,
        context::ScientificProposalContext)
    transaction = _contact_relationship_transaction(
        context.algorithm_workspace,
        _contact_relationship_identity(component))
    @inbounds transaction.status[1] ==
        CONTACT_RELATIONSHIP_SUCCEEDED ||
        return zero(component.activation_energy)
    @inbounds transaction.candidate_present[1] != UInt8(0) &&
        return component.activation_energy
    relationships = transaction.relationships
    payload = relationships.payload
    moments = context.transaction.trackers.moments
    if !(moments isa UnwrappedMomentDelta)
        _contact_relationship_failure!(
            transaction, CONTACT_RELATIONSHIP_STALE_ENDPOINT)
        return zero(component.activation_energy)
    end
    result = zero(component.activation_energy)
    count = Int(@inbounds relationships.count[1])
    for index in 1:count
        @inbounds relationships.active[index] == UInt8(0) && continue
        left = @inbounds relationships.endpoint_a[index]
        left_generation =
            @inbounds relationships.generation_a[index]
        right = @inbounds relationships.endpoint_b[index]
        right_generation =
            @inbounds relationships.generation_b[index]
        affected = left == proposal.losing.value ||
            right == proposal.losing.value ||
            left == proposal.gaining.value ||
            right == proposal.gaining.value
        affected || continue
        if !_contact_endpoint_current(
                context.state, left, left_generation) ||
                !_contact_endpoint_current(
                    context.state, right, right_generation)
            _contact_relationship_failure!(
                transaction, CONTACT_RELATIONSHIP_STALE_ENDPOINT)
            return zero(component.activation_energy)
        end
        old_left = unwrapped_center(
            context.state, CellOwner(left))
        old_right = unwrapped_center(
            context.state, CellOwner(right))
        strength = @inbounds payload.strength[index]
        target_length =
            @inbounds payload.target_length[index]
        old_energy = _contact_link_energy(
            context.state, left, right,
            strength, target_length, old_left, old_right)
        new_left = _contact_postcopy_center(
            context.state, proposal, moments, left)
        new_right = _contact_postcopy_center(
            context.state, proposal, moments, right)
        if new_left === nothing || new_right === nothing
            result -= old_energy
        else
            result += _contact_link_energy(
                context.state, left, right,
                strength, target_length,
                new_left, new_right) - old_energy
        end
    end
    return result
end

@inline proposal_energy_change(
    component::ContactRelationshipHamiltonian,
    proposal::CopyProposal,
    context::ScientificProposalContext) =
    energy_change(component, proposal, context)

@inline function _contact_removal_already_staged(
        transaction, left, left_generation,
        right, right_generation)
    for index in 1:Int(@inbounds transaction.removal_count[1])
        @inbounds if transaction.removal_endpoint_a[index] == left &&
                transaction.removal_generation_a[index] ==
                    left_generation &&
                transaction.removal_endpoint_b[index] == right &&
                transaction.removal_generation_b[index] ==
                    right_generation
            return true
        end
    end
    return false
end

@inline function _stage_contact_removal!(
        transaction, left, left_generation,
        right, right_generation)
    _contact_removal_already_staged(
        transaction, left, left_generation,
        right, right_generation) && return true
    count = Int(@inbounds transaction.removal_count[1])
    count < length(transaction.removal_endpoint_a) ||
        return _contact_relationship_failure!(
            transaction, CONTACT_RELATIONSHIP_REMOVAL_CAPACITY)
    index = count + 1
    @inbounds begin
        transaction.removal_endpoint_a[index] = left
        transaction.removal_generation_a[index] =
            left_generation
        transaction.removal_endpoint_b[index] = right
        transaction.removal_generation_b[index] =
            right_generation
        transaction.removal_count[1] = UInt32(index)
    end
    return true
end

@inline function _contact_edge_overlength(
        transaction, scientific, proposal, moments,
        left, left_generation, right, right_generation,
        maximum_length)
    _contact_endpoint_current(
        scientific, left, left_generation) &&
        _contact_endpoint_current(
            scientific, right, right_generation) || return false
    left_center = _contact_postcopy_center(
        scientific, proposal, moments, left)
    right_center = _contact_postcopy_center(
        scientific, proposal, moments, right)
    (left_center === nothing || right_center === nothing) &&
        return true
    displacement = _minimum_image_displacement(
        scientific, left, right, left_center, right_center)
    return sqrt(sum(abs2, displacement)) > maximum_length
end

function _stage_first_overlength_for_endpoint!(
        transaction, scientific, proposal, moments,
        endpoint::UInt32)
    relationships = transaction.relationships
    payload = relationships.payload
    found = false
    best_left = UInt32(0)
    best_left_generation = UInt64(0)
    best_right = UInt32(0)
    best_right_generation = UInt64(0)
    count = Int(@inbounds relationships.count[1])
    for index in 1:count
        @inbounds relationships.active[index] == UInt8(0) && continue
        left = @inbounds relationships.endpoint_a[index]
        left_generation =
            @inbounds relationships.generation_a[index]
        right = @inbounds relationships.endpoint_b[index]
        right_generation =
            @inbounds relationships.generation_b[index]
        left == endpoint || right == endpoint || continue
        _contact_edge_overlength(
            transaction, scientific, proposal, moments,
            left, left_generation, right, right_generation,
            @inbounds(payload.maximum_length[index])) || continue
        if !found || _relationship_raw_less(
                left, left_generation, right, right_generation,
                best_left, best_left_generation,
                best_right, best_right_generation)
            found = true
            best_left, best_left_generation =
                left, left_generation
            best_right, best_right_generation =
                right, right_generation
        end
    end
    if @inbounds transaction.candidate_present[1] != UInt8(0)
        gaining = proposal.gaining.value
        gaining_generation =
            @inbounds scientific.core.generations[Int(gaining)]
        neighbor = @inbounds transaction.candidate_endpoint[1]
        neighbor_generation =
            @inbounds transaction.candidate_generation[1]
        left, left_generation, right, right_generation =
            _canonical_raw_relationship(
                relationships, gaining, gaining_generation,
                neighbor, neighbor_generation)
        if (left == endpoint || right == endpoint) &&
                _contact_edge_overlength(
                    transaction, scientific, proposal, moments,
                    left, left_generation, right, right_generation,
                    transaction.component.initial_payload.maximum_length) &&
                (!found || _relationship_raw_less(
                    left, left_generation, right, right_generation,
                    best_left, best_left_generation,
                    best_right, best_right_generation))
            found = true
            best_left, best_left_generation =
                left, left_generation
            best_right, best_right_generation =
                right, right_generation
        end
    end
    found || return true
    return _stage_contact_removal!(
        transaction, best_left, best_left_generation,
        best_right, best_right_generation)
end

function preflight_accepted_copy_effect!(
        transaction::ContactRelationshipTransaction,
        proposal, staged, scientific)
    @inbounds transaction.status[1] ==
        CONTACT_RELATIONSHIP_SUCCEEDED || return false
    relationships = transaction.relationships
    count = Int(@inbounds relationships.count[1])
    if @inbounds transaction.candidate_present[1] != UInt8(0)
        gaining = proposal.gaining.value
        gaining_generation =
            @inbounds scientific.core.generations[Int(gaining)]
        neighbor = @inbounds transaction.candidate_endpoint[1]
        neighbor_generation =
            @inbounds transaction.candidate_generation[1]
        _contact_endpoint_current(
            scientific, gaining, gaining_generation) &&
            _contact_endpoint_current(
                scientific, neighbor, neighbor_generation) ||
            return _contact_relationship_failure!(
                transaction, CONTACT_RELATIONSHIP_STALE_ENDPOINT)
        left, left_generation, right, right_generation =
            _canonical_raw_relationship(
                relationships, gaining, gaining_generation,
                neighbor, neighbor_generation)
        _relationship_raw_edge_index(
            relationships.endpoint_a, relationships.generation_a,
            relationships.endpoint_b, relationships.generation_b,
            relationships.active, count,
            left, left_generation, right, right_generation) == 0 ||
            return _contact_relationship_failure!(
                transaction, CONTACT_RELATIONSHIP_DUPLICATE)
        count < length(relationships.active) ||
            return _contact_relationship_failure!(
                transaction, CONTACT_RELATIONSHIP_CAPACITY)
        _relationship_raw_degree(
            relationships.endpoint_a, relationships.generation_a,
            relationships.endpoint_b, relationships.generation_b,
            relationships.active, count,
            left, left_generation) <
            _relationship_maximum_degree(relationships) &&
            _relationship_raw_degree(
                relationships.endpoint_a, relationships.generation_a,
                relationships.endpoint_b, relationships.generation_b,
                relationships.active, count,
                right, right_generation) <
            _relationship_maximum_degree(relationships) ||
            return _contact_relationship_failure!(
                transaction, CONTACT_RELATIONSHIP_DEGREE)
    end
    moments = staged.trackers.moments
    moments isa UnwrappedMomentDelta ||
        return _contact_relationship_failure!(
            transaction, CONTACT_RELATIONSHIP_STALE_ENDPOINT)
    @inbounds transaction.removal_count[1] = UInt32(0)
    if is_cell_owner(proposal.losing) &&
            @inbounds(scientific.trackers.finite_volumes[
                Int(proposal.losing.value)]) == 1
        losing = proposal.losing.value
        for index in 1:count
            @inbounds relationships.active[index] == UInt8(0) && continue
            left = @inbounds relationships.endpoint_a[index]
            right = @inbounds relationships.endpoint_b[index]
            left == losing || right == losing || continue
            _stage_contact_removal!(
                transaction, left,
                @inbounds(relationships.generation_a[index]),
                right,
                @inbounds(relationships.generation_b[index])) ||
                return false
        end
        if @inbounds transaction.candidate_present[1] != UInt8(0) &&
                transaction.candidate_endpoint[1] == losing
            gaining = proposal.gaining.value
            gaining_generation =
                @inbounds scientific.core.generations[Int(gaining)]
            left, left_generation, right, right_generation =
                _canonical_raw_relationship(
                    relationships, gaining, gaining_generation,
                    losing,
                    @inbounds(transaction.candidate_generation[1]))
            _stage_contact_removal!(
                transaction, left, left_generation,
                right, right_generation) || return false
        end
    else
        is_cell_owner(proposal.gaining) &&
            !_stage_first_overlength_for_endpoint!(
                transaction, scientific, proposal, moments,
                proposal.gaining.value) && return false
        is_cell_owner(proposal.losing) &&
            !_stage_first_overlength_for_endpoint!(
                transaction, scientific, proposal, moments,
                proposal.losing.value) && return false
    end
    return true
end

@inline function _insert_contact_relationship!(
        relationships, left, left_generation,
        right, right_generation, payload)
    count = Int(@inbounds relationships.count[1])
    insertion = count + 1
    for index in 1:count
        @inbounds if _relationship_raw_less(
                left, left_generation, right, right_generation,
                relationships.endpoint_a[index],
                relationships.generation_a[index],
                relationships.endpoint_b[index],
                relationships.generation_b[index])
            insertion = index
            break
        end
    end
    for destination in (count + 1):-1:(insertion + 1)
        _relationship_raw_copy!(
            relationships.endpoint_a,
            relationships.generation_a,
            relationships.endpoint_b,
            relationships.generation_b,
            relationships.payload, relationships.active,
            destination, destination - 1)
    end
    @inbounds begin
        relationships.endpoint_a[insertion] = left
        relationships.generation_a[insertion] =
            left_generation
        relationships.endpoint_b[insertion] = right
        relationships.generation_b[insertion] =
            right_generation
        relationships.payload[insertion] = payload
        relationships.active[insertion] = UInt8(1)
        relationships.count[1] = UInt32(count + 1)
    end
    return nothing
end

@inline function _remove_contact_relationship!(
        relationships, left, left_generation,
        right, right_generation)
    count = Int(@inbounds relationships.count[1])
    index = _relationship_raw_edge_index(
        relationships.endpoint_a, relationships.generation_a,
        relationships.endpoint_b, relationships.generation_b,
        relationships.active, count,
        left, left_generation, right, right_generation)
    index == 0 && return false
    for source in (index + 1):count
        _relationship_raw_copy!(
            relationships.endpoint_a,
            relationships.generation_a,
            relationships.endpoint_b,
            relationships.generation_b,
            relationships.payload, relationships.active,
            source - 1, source)
    end
    @inbounds begin
        relationships.active[count] = UInt8(0)
        relationships.count[1] = UInt32(count - 1)
    end
    return true
end

function commit_accepted_copy_effect!(
        transaction::ContactRelationshipTransaction,
        proposal, staged, scientific)
    relationships = transaction.relationships
    changed = false
    if @inbounds transaction.candidate_present[1] != UInt8(0)
        gaining = proposal.gaining.value
        gaining_generation =
            @inbounds scientific.core.generations[Int(gaining)]
        neighbor = @inbounds transaction.candidate_endpoint[1]
        neighbor_generation =
            @inbounds transaction.candidate_generation[1]
        left, left_generation, right, right_generation =
            _canonical_raw_relationship(
                relationships, gaining, gaining_generation,
                neighbor, neighbor_generation)
        _insert_contact_relationship!(
            relationships, left, left_generation,
            right, right_generation,
            transaction.component.initial_payload)
        changed = true
    end
    for index in 1:Int(@inbounds transaction.removal_count[1])
        changed |= _remove_contact_relationship!(
            relationships,
            @inbounds(transaction.removal_endpoint_a[index]),
            @inbounds(transaction.removal_generation_a[index]),
            @inbounds(transaction.removal_endpoint_b[index]),
            @inbounds(transaction.removal_generation_b[index]))
    end
    changed &&
        (@inbounds relationships.publication_epoch[1] += UInt64(1))
    return nothing
end

function accepted_copy_effect_backend_valid(
        transaction::ContactRelationshipTransaction,
        scientific, plan)
    relationships = transaction.relationships
    arrays = (
        relationships.endpoint_a, relationships.generation_a,
        relationships.endpoint_b, relationships.generation_b,
        relationships.payload.strength,
        relationships.payload.target_length,
        relationships.payload.maximum_length,
        relationships.active, relationships.count,
        relationships.publication_epoch,
        transaction.permutation,
        transaction.candidate_endpoint,
        transaction.candidate_generation,
        transaction.candidate_present,
        transaction.removal_endpoint_a,
        transaction.removal_generation_a,
        transaction.removal_endpoint_b,
        transaction.removal_generation_b,
        transaction.removal_count, transaction.status,
        transaction.failing_attempt, transaction.attempt_id,
        transaction.mcs_id)
    return all(array -> isbitstype(eltype(array)) &&
        isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays)
end

accepted_copy_effect_allocation_bytes(
    transaction::ContactRelationshipTransaction) = sum(
    _array_bytes, (
        transaction.permutation,
        transaction.candidate_endpoint,
        transaction.candidate_generation,
        transaction.candidate_present,
        transaction.removal_endpoint_a,
        transaction.removal_generation_a,
        transaction.removal_endpoint_b,
        transaction.removal_generation_b,
        transaction.removal_count, transaction.status,
        transaction.failing_attempt, transaction.attempt_id,
        transaction.mcs_id);
    init = 0)

function synchronize_accepted_copy_effect_status!(
        plan, transaction::ContactRelationshipTransaction)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, transaction.status))
    iszero(status) && return transaction
    attempt = only(Adapt.adapt(
        Array, transaction.failing_attempt))
    throw(ArgumentError(
        "contact-relationship transaction failed with status $status at zero-based attempt $attempt"))
end

function rebuild_accepted_copy_effect(
        transaction::ContactRelationshipTransaction{Name},
        coupled_state::CoupledState) where {Name}
    state = _state_by_name(
        coupled_state.relationships, Name)
    return ContactRelationshipTransaction(
        transaction.component, state)
end

@kernel function _relationship_initialize_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, status, failing_request)
    index = @index(Global, Linear)
    @inbounds begin
        candidate_endpoint_a[index] = endpoint_a[index]
        candidate_generation_a[index] = generation_a[index]
        candidate_endpoint_b[index] = endpoint_b[index]
        candidate_generation_b[index] = generation_b[index]
        candidate_payload[index] = payload[index]
        candidate_active[index] = active[index]
        if index == 1
            candidate_count[1] = count[1]
            status[1] = UInt32(0)
            failing_request[1] = UInt32(0)
        end
    end
end

@kernel function _relationship_apply_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_count, cell_active, cell_generations,
        directed, maximum_degree, status, failing_request)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        prior_a = UInt32(0)
        prior_ga = UInt64(0)
        prior_b = UInt32(0)
        prior_gb = UInt64(0)
        for request_index in 1:Int(@inbounds request_count[1])
            kind = @inbounds request_kind[request_index]
            left = @inbounds request_endpoint_a[request_index]
            left_generation =
                @inbounds request_generation_a[request_index]
            right = @inbounds request_endpoint_b[request_index]
            right_generation =
                @inbounds request_generation_b[request_index]
            if !directed && _relationship_raw_less(
                    right, right_generation, left, left_generation,
                    left, left_generation, right, right_generation)
                left, right = right, left
                left_generation, right_generation =
                    right_generation, left_generation
            end
            code = UInt32(0)
            if left == right && left_generation == right_generation
                code = UInt32(1)
            elseif !_relationship_endpoint_is_current(
                    cell_active, cell_generations, left, left_generation) ||
                    !_relationship_endpoint_is_current(
                        cell_active, cell_generations, right, right_generation)
                code = UInt32(2)
            elseif request_index > 1 &&
                    left == prior_a && left_generation == prior_ga &&
                    right == prior_b && right_generation == prior_gb
                code = UInt32(3)
            else
                edge_index = _relationship_raw_edge_index(
                    candidate_endpoint_a, candidate_generation_a,
                    candidate_endpoint_b, candidate_generation_b,
                    candidate_active, count,
                    left, left_generation, right, right_generation)
                if kind == RELATIONSHIP_REMOVE_REQUEST
                    if edge_index != 0
                        for source in (edge_index + 1):count
                            _relationship_raw_copy!(
                                candidate_endpoint_a,
                                candidate_generation_a,
                                candidate_endpoint_b,
                                candidate_generation_b,
                                candidate_payload, candidate_active,
                                source - 1, source)
                        end
                        @inbounds candidate_active[count] = UInt8(0)
                        count -= 1
                    end
                elseif kind == RELATIONSHIP_RETUNE_REQUEST
                    if edge_index == 0
                        code = UInt32(4)
                    else
                        @inbounds candidate_payload[edge_index] =
                            request_payload[request_index]
                    end
                elseif kind == RELATIONSHIP_CREATE_REQUEST
                    if edge_index != 0
                        code = UInt32(5)
                    elseif count >= length(candidate_active)
                        code = UInt32(6)
                    elseif _relationship_raw_degree(
                            candidate_endpoint_a, candidate_generation_a,
                            candidate_endpoint_b, candidate_generation_b,
                            candidate_active, count,
                            left, left_generation) >= maximum_degree ||
                            _relationship_raw_degree(
                                candidate_endpoint_a, candidate_generation_a,
                                candidate_endpoint_b, candidate_generation_b,
                                candidate_active, count,
                                right, right_generation) >= maximum_degree
                        code = UInt32(7)
                    else
                        insertion = count + 1
                        for index in 1:count
                            @inbounds if _relationship_raw_less(
                                    left, left_generation,
                                    right, right_generation,
                                    candidate_endpoint_a[index],
                                    candidate_generation_a[index],
                                    candidate_endpoint_b[index],
                                    candidate_generation_b[index])
                                insertion = index
                                break
                            end
                        end
                        for destination in (count + 1):-1:(insertion + 1)
                            _relationship_raw_copy!(
                                candidate_endpoint_a,
                                candidate_generation_a,
                                candidate_endpoint_b,
                                candidate_generation_b,
                                candidate_payload, candidate_active,
                                destination, destination - 1)
                        end
                        @inbounds begin
                            candidate_endpoint_a[insertion] = left
                            candidate_generation_a[insertion] =
                                left_generation
                            candidate_endpoint_b[insertion] = right
                            candidate_generation_b[insertion] =
                                right_generation
                            candidate_payload[insertion] =
                                request_payload[request_index]
                            candidate_active[insertion] = UInt8(1)
                        end
                        count += 1
                    end
                else
                    code = UInt32(8)
                end
            end
            if code != UInt32(0)
                @inbounds begin
                    status[1] = code
                    failing_request[1] = UInt32(request_index)
                end
                break
            end
            prior_a, prior_ga, prior_b, prior_gb =
                left, left_generation, right, right_generation
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

@kernel function _relationship_commit_transaction!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, publication_epoch,
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count, status)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        endpoint_a[index] = candidate_endpoint_a[index]
        generation_a[index] = candidate_generation_a[index]
        endpoint_b[index] = candidate_endpoint_b[index]
        generation_b[index] = candidate_generation_b[index]
        payload[index] = candidate_payload[index]
        active[index] = candidate_active[index]
        if index == 1
            count[1] = candidate_count[1]
            publication_epoch[1] += UInt64(1)
        end
    end
end

function apply_relationship_requests!(
        plan::ExecutionPlan, scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    execution = scientific_execution(scientific)
    core = execution.core
    arrays = (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, workspace.status,
        workspace.failing_request,
        core.active, core.generations)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable relationship storage has a backend mismatch"))
    capacity = length(state.active)
    all(==(capacity), map(length, (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active))) ||
        throw(DimensionMismatch(
            "portable relationship capacities differ"))
    initialize = _execution_kernel(
        plan, _relationship_initialize_transaction!, capacity)
    launch!(plan, initialize,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        workspace.status, workspace.failing_request;
        ndrange = capacity)
    apply = _execution_kernel(
        plan, _relationship_apply_transaction!, 1)
    launch!(plan, apply,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, core.active, core.generations,
        state.declaration.directed,
        Int(state.declaration.maximum_degree),
        workspace.status, workspace.failing_request;
        ndrange = 1)
    commit = _execution_kernel(
        plan, _relationship_commit_transaction!, capacity)
    launch!(plan, commit,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count, workspace.status;
        ndrange = capacity)
    return state
end

function synchronize_relationship_status!(
        plan::ExecutionPlan,
        workspace::RelationshipTransactionWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_request))
    throw(ArgumentError(
        "relationship transaction failed with status $status at request $failing"))
end

struct ElasticLinkRetune{PROPERTY, S, T <: AbstractFloat}
    name::Symbol
    relationships::Symbol
    scope::S
    property::Symbol
    parameters::ElasticLinkParameters{T}
    version::VersionNumber
end
function ElasticLinkRetune(name::Symbol,
        relationships::Union{Symbol, RelationshipSet}, scope;
        property::Symbol, strength::T, target_length::T,
        maximum_length::T,
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    parameters = ElasticLinkParameters(
        strength, target_length, maximum_length)
    return ElasticLinkRetune{
        property, typeof(scope), T}(
        name,
        relationships isa Symbol ? relationships : relationships.name,
        scope, property, parameters, version)
end
component_identity(process::ElasticLinkRetune) =
    ComponentIdentity(
        process.name, process.version, :relationship_retune)
component_semantic_data(process::ElasticLinkRetune) = (
    relationships = process.relationships,
    scope = process.scope, property = process.property,
    parameters = process.parameters)
process_reads(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:ownership, :cells))
process_writes(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:cell_property, process.property))

struct ElasticLinkRetuneWorkspace{
        P <: AbstractVector, T <: AbstractVector,
        C <: AbstractVector{UInt32}}
    candidate_property::P
    candidate_strength::T
    candidate_target_length::T
    candidate_maximum_length::T
    status::C
    failing_edge::C
end

function ElasticLinkRetuneWorkspace(
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        property_values::AbstractVector{T}) where {D, T}
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    status = similar(state.count)
    failing_edge = similar(state.count)
    fill!(status, UInt32(0))
    fill!(failing_edge, UInt32(0))
    return ElasticLinkRetuneWorkspace(
        similar(property_values),
        similar(payload.strength),
        similar(payload.target_length),
        similar(payload.maximum_length),
        status, failing_edge)
end

function Adapt.adapt_structure(to,
        workspace::ElasticLinkRetuneWorkspace)
    return ElasticLinkRetuneWorkspace(
        Adapt.adapt(to, workspace.candidate_property),
        Adapt.adapt(to, workspace.candidate_strength),
        Adapt.adapt(to, workspace.candidate_target_length),
        Adapt.adapt(to, workspace.candidate_maximum_length),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_edge))
end

"""
Compiled execution view for an immutable `ElasticLinkRetune` declaration.

The wrapper owns only bounded scratch storage. Relationship payload and cell properties remain
authoritative in `CoupledState` and `CompiledScientificState`, respectively.
"""
struct ElasticLinkRetuneExecution{
        P <: ElasticLinkRetune,
        W <: ElasticLinkRetuneWorkspace}
    process::P
    workspace::W
end

function ElasticLinkRetuneExecution(
        process::ElasticLinkRetune,
        relationships::RelationshipState,
        state::Union{
            LogicalPottsState,
            CompiledScientificState})
    property = _coupled_property_column(
        state, process.property)
    workspace = ElasticLinkRetuneWorkspace(
        relationships, property)
    return ElasticLinkRetuneExecution(
        process, workspace)
end

function realize_coupled_process(
        process::ElasticLinkRetune,
        state::CoupledState,
        scientific::CompiledScientificState)
    relationships = _state_by_name(
        state.relationships,
        process.relationships)
    return ElasticLinkRetuneExecution(
        process, relationships, scientific)
end

function Adapt.adapt_structure(
        to, execution::ElasticLinkRetuneExecution)
    return ElasticLinkRetuneExecution(
        Adapt.adapt(to, execution.process),
        Adapt.adapt(to, execution.workspace))
end

component_identity(
    execution::ElasticLinkRetuneExecution) =
    component_identity(execution.process)
component_semantic_data(
    execution::ElasticLinkRetuneExecution) =
    component_semantic_data(execution.process)
process_reads(execution::ElasticLinkRetuneExecution) =
    process_reads(execution.process)
process_writes(execution::ElasticLinkRetuneExecution) =
    process_writes(execution.process)
canonical_process_law(
    execution::ElasticLinkRetuneExecution) =
    execution.process

function apply_elastic_link_retune!(
        logical::LogicalPottsState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    return apply_elastic_link_retune!(
        logical, state, process,
        process.parameters, workspace)
end

function apply_elastic_link_retune!(
        logical::LogicalPottsState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        parameters::ElasticLinkParameters{T},
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    property = property_values(logical, process.property)
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "elastic retune cell-property capacities differ"))
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    copyto!(workspace.candidate_property, property)
    copyto!(workspace.candidate_strength, payload.strength)
    copyto!(
        workspace.candidate_target_length, payload.target_length)
    copyto!(
        workspace.candidate_maximum_length, payload.maximum_length)
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_edge, UInt32(0))
    for index in 1:_relationship_count(state)
        edge = _relationship_edge(state, index)
        for endpoint in (edge.left, edge.right)
            if !is_active(logical, endpoint.cell) ||
                    generation(logical, endpoint.cell) !=
                        endpoint.generation
                workspace.status[1] = UInt32(1)
                workspace.failing_edge[1] = UInt32(index)
                throw(ArgumentError(
                    "elastic retune encountered a stale endpoint at edge $index"))
            end
        end
        @inbounds begin
            workspace.candidate_strength[index] =
                parameters.strength
            workspace.candidate_target_length[index] =
                parameters.target_length
            workspace.candidate_maximum_length[index] =
                parameters.maximum_length
        end
    end
    for slot in eachindex(property)
        cell = CellID(slot)
        is_active(logical, cell) || continue
        _cell_scope_matches_exchange(
            process.scope, logical, cell) || continue
        @inbounds workspace.candidate_property[slot] =
            parameters.strength
    end
    copyto!(property, workspace.candidate_property)
    copyto!(payload.strength, workspace.candidate_strength)
    copyto!(
        payload.target_length, workspace.candidate_target_length)
    copyto!(
        payload.maximum_length, workspace.candidate_maximum_length)
    state.publication_epoch[1] += UInt64(1)
    return state
end

@inline function _record_relationship_failure!(
        status, failing_edge, code, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_edge[1], UInt32(index))
    return nothing
end

@kernel function _elastic_retune_initialize!(
        candidate_property, property,
        candidate_strength, strength,
        candidate_target_length, target_length,
        candidate_maximum_length, maximum_length,
        status, failing_edge, edge_capacity)
    index = @index(Global, Linear)
    if index <= length(property)
        @inbounds candidate_property[index] = property[index]
    end
    if index <= edge_capacity
        @inbounds begin
            candidate_strength[index] = strength[index]
            candidate_target_length[index] = target_length[index]
            candidate_maximum_length[index] = maximum_length[index]
        end
    end
    if index == 1
        @inbounds begin
            status[1] = UInt32(0)
            failing_edge[1] = typemax(UInt32)
        end
    end
end

@kernel function _elastic_retune_apply!(
        candidate_property,
        candidate_strength, candidate_target_length,
        candidate_maximum_length,
        relationship_endpoint_a, relationship_generation_a,
        relationship_endpoint_b, relationship_generation_b,
        relationship_active, relationship_count,
        cell_active, cell_generations, cell_types, scope_type,
        strength, target_length, maximum_length,
        status, failing_edge)
    index = @index(Global, Linear)
    if index <= length(candidate_property)
        @inbounds if cell_active[index] != zero(eltype(cell_active)) &&
                _portable_cell_eligible(scope_type, cell_types[index])
            candidate_property[index] = strength
        end
    end
    if index <= Int(@inbounds relationship_count[1]) &&
            @inbounds(relationship_active[index] != UInt8(0))
        left = @inbounds relationship_endpoint_a[index]
        left_generation =
            @inbounds relationship_generation_a[index]
        right = @inbounds relationship_endpoint_b[index]
        right_generation =
            @inbounds relationship_generation_b[index]
        if _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            @inbounds begin
                candidate_strength[index] = strength
                candidate_target_length[index] = target_length
                candidate_maximum_length[index] = maximum_length
            end
        else
            _record_relationship_failure!(
                status, failing_edge, 1, index)
        end
    end
end

@kernel function _elastic_retune_commit!(
        property, candidate_property,
        strength, candidate_strength,
        target_length, candidate_target_length,
        maximum_length, candidate_maximum_length,
        publication_epoch, status, edge_capacity)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        index <= length(property) &&
            (property[index] = candidate_property[index])
        if index <= edge_capacity
            strength[index] = candidate_strength[index]
            target_length[index] = candidate_target_length[index]
            maximum_length[index] =
                candidate_maximum_length[index]
        end
        index == 1 &&
            (publication_epoch[1] += UInt64(1))
    end
end

function apply_elastic_link_retune!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    return apply_elastic_link_retune!(
        plan, scientific, state, process,
        process.parameters, workspace)
end

function apply_elastic_link_retune!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        parameters::ElasticLinkParameters{T},
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    execution = scientific_execution(scientific)
    core = execution.core
    property = getproperty(core.properties, process.property)
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    arrays = (
        property, payload.strength, payload.target_length,
        payload.maximum_length, state.endpoint_a,
        state.generation_a, state.endpoint_b,
        state.generation_b, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        workspace.status, workspace.failing_edge,
        core.active, core.generations, core.cell_types)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable elastic-retune storage has a backend mismatch"))
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "portable elastic-retune cell capacities differ"))
    edge_capacity = length(state.active)
    all(==(edge_capacity), map(length, (
        payload.strength, payload.target_length,
        payload.maximum_length,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length))) ||
        throw(DimensionMismatch(
            "portable elastic-retune edge capacities differ"))
    ndrange = max(length(property), edge_capacity)
    initialize = _execution_kernel(
        plan, _elastic_retune_initialize!, ndrange)
    launch!(plan, initialize,
        workspace.candidate_property, property,
        workspace.candidate_strength, payload.strength,
        workspace.candidate_target_length, payload.target_length,
        workspace.candidate_maximum_length, payload.maximum_length,
        workspace.status, workspace.failing_edge, edge_capacity;
        ndrange)
    scope_type = _portable_scope_type(process.scope)
    apply = _execution_kernel(
        plan, _elastic_retune_apply!, ndrange)
    launch!(plan, apply,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.active, state.count,
        core.active, core.generations, core.cell_types,
        scope_type, parameters.strength,
        parameters.target_length,
        parameters.maximum_length,
        workspace.status, workspace.failing_edge;
        ndrange)
    commit = _execution_kernel(
        plan, _elastic_retune_commit!, ndrange)
    launch!(plan, commit,
        property, workspace.candidate_property,
        payload.strength, workspace.candidate_strength,
        payload.target_length,
        workspace.candidate_target_length,
        payload.maximum_length,
        workspace.candidate_maximum_length,
        state.publication_epoch, workspace.status,
        edge_capacity; ndrange)
    return state
end

function synchronize_elastic_retune_status!(
        plan::ExecutionPlan,
        workspace::ElasticLinkRetuneWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_edge))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(ArgumentError(
        "elastic relationship retune failed with status $status at edge $failing"))
end

function _execute_host_process!(
        candidate::CoupledState,
        snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        execution::ElasticLinkRetuneExecution,
        target_mcs, stage, interval)
    process = execution.process
    parameters = _elastic_retune_parameters(
        process, interval)
    source = _state_by_name(
        snapshot.relationships,
        process.relationships)
    target = _state_by_name(
        candidate.relationships,
        process.relationships)
    _publish_state!(target, source)
    apply_elastic_link_retune!(
        potts_candidate, target, process, parameters,
        execution.workspace)
    return (process.property,)
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        execution::ElasticLinkRetuneExecution,
        target_mcs, stage, interval)
    process = execution.process
    parameters = _elastic_retune_parameters(
        process, interval)
    relationships = _state_by_name(
        integrator.state.relationships,
        process.relationships)
    apply_elastic_link_retune!(
        integrator.potts.plan,
        integrator.potts.state,
        relationships, process, parameters,
        execution.workspace)
    synchronize_elastic_retune_status!(
        integrator.potts.plan,
        execution.workspace)
    return ()
end

function _elastic_retune_parameters(
        process::ElasticLinkRetune,
        interval)
    interval === nothing &&
        return process.parameters
    interval isa typeof(process.parameters) ||
        throw(ArgumentError(
            "elastic retune scheduled value must match the declaration parameter type"))
    return interval
end

"""
Immutable declaration for canonical stale-endpoint relationship compaction.

The declaration carries only identity and the targeted relationship set. Bounded candidate
storage belongs to `RelationshipCleanupExecution`.
"""
struct RelationshipCleanup{Relationships}
    name::Symbol
    version::VersionNumber
end

function RelationshipCleanup(
        name::Symbol,
        relationships::Union{
            Symbol, RelationshipSet};
        version::VersionNumber =
            DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "relationship-cleanup identity must not be empty"))
    target = relationships isa Symbol ?
        relationships : relationships.name
    return RelationshipCleanup{target}(
        name, version)
end

component_identity(process::RelationshipCleanup) =
    ComponentIdentity(
        process.name, process.version,
        :relationship_cleanup)
component_semantic_data(
        ::RelationshipCleanup{Relationships}) where {
        Relationships} = (
    relationships = Relationships,
    policy = :remove_stale_endpoint_generation,
    order = :canonical_compaction,
)
process_reads(
        ::RelationshipCleanup{
            Relationships}) where {
        Relationships} = (
    (:relationships, Relationships),
    (:ownership, :cells),
)
process_writes(
        ::RelationshipCleanup{
            Relationships}) where {
        Relationships} = (
    (:relationships, Relationships),)

struct RelationshipCleanupExecution{
        P <: RelationshipCleanup,
        W <: RelationshipTransactionWorkspace}
    process::P
    workspace::W
end

function RelationshipCleanupExecution(
        process::RelationshipCleanup{
            Relationships},
        state::RelationshipState) where {
        Relationships}
    state.declaration.name === Relationships ||
        throw(ArgumentError(
            "relationship-cleanup declaration and state identities differ"))
    return RelationshipCleanupExecution(
        process,
        RelationshipTransactionWorkspace(
            state; request_capacity = 1))
end

function realize_coupled_process(
        process::RelationshipCleanup{
            Relationships},
        state::CoupledState,
        scientific::CompiledScientificState) where {
            Relationships}
    relationships = _state_by_name(
        state.relationships, Relationships)
    return RelationshipCleanupExecution(
        process, relationships)
end

function Adapt.adapt_structure(
        to,
        execution::RelationshipCleanupExecution)
    return RelationshipCleanupExecution(
        Adapt.adapt(to, execution.process),
        Adapt.adapt(to, execution.workspace))
end

component_identity(
    execution::RelationshipCleanupExecution) =
    component_identity(execution.process)
component_semantic_data(
    execution::RelationshipCleanupExecution) =
    component_semantic_data(execution.process)
process_reads(
    execution::RelationshipCleanupExecution) =
    process_reads(execution.process)
process_writes(
    execution::RelationshipCleanupExecution) =
    process_writes(execution.process)
canonical_process_law(
    execution::RelationshipCleanupExecution) =
    execution.process

function cleanup_relationships!(
        state::RelationshipState,
        logical::LogicalPottsState)
    state.declaration.endpoint_lifecycle isa
        RemoveIncidentEdges ||
        throw(ArgumentError(
            "relationship cleanup requires RemoveIncidentEdges"))
    count = _relationship_count(state)
    index = 1
    while index <= count
        left = @inbounds state.endpoint_a[index]
        left_generation =
            @inbounds state.generation_a[index]
        right = @inbounds state.endpoint_b[index]
        right_generation =
            @inbounds state.generation_b[index]
        current =
            is_active(logical, CellID(left)) &&
            generation(logical, CellID(left)) ==
                CellGeneration(left_generation) &&
            is_active(logical, CellID(right)) &&
            generation(logical, CellID(right)) ==
                CellGeneration(right_generation)
        if current
            index += 1
            continue
        end
        for source in (index + 1):count
            _relationship_raw_copy!(
                state.endpoint_a,
                state.generation_a,
                state.endpoint_b,
                state.generation_b,
                state.payload, state.active,
                source - 1, source)
        end
        @inbounds state.active[count] = UInt8(0)
        count -= 1
    end
    state.count[1] = UInt32(count)
    state.publication_epoch[1] += UInt64(1)
    return state
end

function _execute_host_process!(
        candidate::CoupledState,
        snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        execution::RelationshipCleanupExecution,
        target_mcs, stage, interval)
    process = execution.process
    relationships =
        component_semantic_data(process).relationships
    source = _state_by_name(
        snapshot.relationships, relationships)
    target = _state_by_name(
        candidate.relationships, relationships)
    _publish_state!(target, source)
    cleanup_relationships!(
        target, potts_snapshot)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        execution::RelationshipCleanupExecution,
        target_mcs, stage, interval)
    process = execution.process
    relationships =
        component_semantic_data(process).relationships
    state = _state_by_name(
        integrator.state.relationships,
        relationships)
    cleanup_relationships!(
        integrator.potts.plan,
        integrator.potts.state, state,
        execution.workspace)
    synchronize_relationship_status!(
        integrator.potts.plan,
        execution.workspace)
    return ()
end

@kernel function _relationship_cleanup_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        cell_active, cell_generations)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        index = 1
        while index <= count
            left = @inbounds candidate_endpoint_a[index]
            left_generation =
                @inbounds candidate_generation_a[index]
            right = @inbounds candidate_endpoint_b[index]
            right_generation =
                @inbounds candidate_generation_b[index]
            current = _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            if current
                index += 1
            else
                for source in (index + 1):count
                    _relationship_raw_copy!(
                        candidate_endpoint_a,
                        candidate_generation_a,
                        candidate_endpoint_b,
                        candidate_generation_b,
                        candidate_payload, candidate_active,
                        source - 1, source)
                end
                @inbounds candidate_active[count] = UInt8(0)
                count -= 1
            end
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

function cleanup_relationships!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    state.declaration.endpoint_lifecycle isa RemoveIncidentEdges ||
        throw(ArgumentError(
            "portable relationship cleanup requires RemoveIncidentEdges"))
    execution = scientific_execution(scientific)
    core = execution.core
    capacity = length(state.active)
    initialize = _execution_kernel(
        plan, _relationship_initialize_transaction!, capacity)
    launch!(plan, initialize,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        workspace.status, workspace.failing_request;
        ndrange = capacity)
    cleanup = _execution_kernel(
        plan, _relationship_cleanup_transaction!, 1)
    launch!(plan, cleanup,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        core.active, core.generations;
        ndrange = 1)
    commit = _execution_kernel(
        plan, _relationship_commit_transaction!, capacity)
    launch!(plan, commit,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count, workspace.status;
        ndrange = capacity)
    return state
end

"""Atomic relationship transaction planner over one common graph/cell snapshot."""
struct RelationshipDynamics{L, C}
    name::Symbol
    relationships::Symbol
    law::L
    conflicts::C
    version::VersionNumber
end
function RelationshipDynamics(name::Symbol,
        relationships::Union{Symbol, RelationshipSet};
        law = nothing, create = nothing, remove = nothing, update = nothing,
        conflicts = StableRelationshipPriority(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    supplied = count(value -> value !== nothing, (create, remove, update))
    if law !== nothing && supplied > 0
        throw(ArgumentError(
            "RelationshipDynamics accepts either law or create/remove/update policies"))
    end
    law isa Function && throw(ArgumentError(
        "stable relationship laws must use DirectLaw with explicit identity"))
    for policy in (create, remove, update)
        policy isa Function && throw(ArgumentError(
            "stable relationship policies must use DirectLaw with explicit identity"))
    end
    resolved_law = law === nothing ?
        RelationshipPolicyBundle(create, remove, update) : law
    return RelationshipDynamics(name,
        relationships isa Symbol ? relationships : relationships.name,
        resolved_law, conflicts, version)
end

struct RelationshipPolicyBundle{C, R, U}
    create::C
    remove::R
    update::U
end

component_identity(process::RelationshipDynamics) =
    ComponentIdentity(process.name, process.version, :relationship_dynamics)
component_semantic_data(process::RelationshipDynamics) = (
    relationships = process.relationships,
    law = process.law, conflicts = process.conflicts)
component_effects(::RelationshipDynamics) = (:relationship_phase_write,)
process_reads(process::RelationshipDynamics) =
    ((:relationships, process.relationships), (:ownership, :cells))
process_writes(process::RelationshipDynamics) =
    ((:relationships, process.relationships),)

function _relationship_requests(law, relationships, potts_snapshot,
        target_mcs, stage)
    applicable(law, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs, stage))
    applicable(law, relationships, potts_snapshot, target_mcs) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs))
    applicable(law, relationships, potts_snapshot) &&
        return Tuple(law(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law must return typed requests from a supported snapshot signature"))
end

function _relationship_requests(law::DirectLaw, relationships,
        potts_snapshot, target_mcs, stage)
    function_value = law.function_value
    applicable(function_value, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs, stage))
    applicable(function_value, relationships, potts_snapshot, target_mcs) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs))
    applicable(function_value, relationships, potts_snapshot) &&
        return Tuple(function_value(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law `$(law.name)` has no supported snapshot signature"))
end

function _relationship_requests(bundle::RelationshipPolicyBundle,
        relationships, potts_snapshot, target_mcs, stage)
    requests = ()
    for policy in (bundle.remove, bundle.update, bundle.create)
        policy === nothing && continue
        produced = _relationship_requests(
            policy, relationships, potts_snapshot, target_mcs, stage)
        requests = (requests..., produced...)
    end
    return requests
end

_request_key(request::AbstractRelationshipRequest) = (
    -Int(request.priority),
    value(request.left.cell), value(request.left.generation),
    value(request.right.cell), value(request.right.generation),
    request isa RemoveRelationship ? 1 :
    request isa RetuneRelationship ? 2 : 3)

function apply_relationship_dynamics!(state::RelationshipState,
        process::RelationshipDynamics, potts_snapshot,
        target_mcs::Integer; stage = nothing)
    process.relationships === state.declaration.name || throw(ArgumentError(
        "RelationshipDynamics targets a different RelationshipSet"))
    requests = collect(_relationship_requests(
        process.law, deepcopy(state), potts_snapshot, target_mcs, stage))
    all(request -> request isa AbstractRelationshipRequest, requests) ||
        throw(ArgumentError(
            "relationship dynamics produced an untyped transaction request"))
    sort!(requests; by = _request_key)
    candidate = deepcopy(state)
    touched = Set{Tuple{CellEndpoint, CellEndpoint}}()
    for request in requests
        endpoints = _canonical_endpoints(
            candidate.declaration, request.left, request.right)
        endpoints in touched && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        push!(touched, endpoints)
        if request isa RemoveRelationship
            remove_relationship!(candidate, endpoints...)
        elseif request isa RetuneRelationship
            retune_relationship!(
                candidate, endpoints..., request.payload)
        else
            create_relationship!(
                candidate, endpoints..., request.payload)
        end
    end
    _publish_state!(state, candidate)
    return state
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, process::RelationshipDynamics,
        target_mcs, stage, interval)
    source = _state_by_name(snapshot.relationships, process.relationships)
    target = _state_by_name(candidate.relationships, process.relationships)
    _publish_state!(target, source)
    apply_relationship_dynamics!(
        target, process, potts_snapshot, target_mcs; stage)
    return nothing
end

function _apply_site_lifecycle!(state::SitePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    policy = state.declaration.ownership
    policy isa PreserveAtSite && return state
    before_owners = lattice_storage(before)
    after_owners = lattice_storage(after)
    for site in eachindex(before_owners)
        before_owners[site] == after_owners[site] && continue
        if policy isa ResetChangedSites
            _site_write!(state, site, policy.value)
        else
            throw(ArgumentError(
                "AcceptedCopyManaged does not define lifecycle-driven ownership changes; declare a coupled lifecycle site policy"))
        end
    end
    return state
end

function _apply_history_lifecycle!(state::CellHistoryState,
        before::LogicalPottsState, after::LogicalPottsState)
    for slot in eachindex(state.generations)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        next_generation = generation(after, cell)
        if !active_after || state.generations[slot] != next_generation
            state.heads[slot] = UInt32(0)
            state.fills[slot] = UInt32(0)
            state.generations[slot] = next_generation
        end
    end
    return state
end

function _apply_relationship_lifecycle!(state::RelationshipState,
        before::LogicalPottsState, after::LogicalPottsState)
    stale = CellEndpoint[]
    for edge in state.edges, endpoint in (edge.left, edge.right)
        cell = endpoint.cell
        if !is_active(after, cell) || generation(after, cell) != endpoint.generation
            endpoint in stale || push!(stale, endpoint)
        end
    end
    for endpoint in stale
        retire_relationship_endpoint!(state, endpoint)
    end
    return state
end

function _apply_membrane_lifecycle!(state::MembranePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    initial = state.declaration.initial.value
    for slot in axes(state.values, 1)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        generation_after = generation(after, cell)
        if !active_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = false
            state.generations[slot] = generation_after
        elseif !state.active[slot] ||
                state.generations[slot] != generation_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = true
            state.generations[slot] = generation_after
        end
    end
    return state
end

"""Apply coupled-state cleanup after one accepted CorePotts lifecycle transaction."""
function apply_coupled_lifecycle!(state::CoupledState,
        before::LogicalPottsState, after::LogicalPottsState)
    candidate = deepcopy(state)
    foreach(item -> _apply_site_lifecycle!(item, before, after),
        candidate.site_states)
    foreach(item -> _apply_history_lifecycle!(item, before, after),
        candidate.histories)
    foreach(item -> _apply_relationship_lifecycle!(item, before, after),
        candidate.relationships)
    foreach(item -> _apply_membrane_lifecycle!(item, before, after),
        candidate.membranes)
    publish_coupled_state!(state, candidate)
    return state
end
