"""Quadratic finite-cell volume Hamiltonian for the scalar reference engine."""
struct ReferenceVolumeEnergy <: AbstractEnergy
    target_key::Symbol
    strength_key::Symbol
end

ReferenceVolumeEnergy(; target::Symbol = :target_volume, strength::Symbol = :volume_strength) =
    ReferenceVolumeEnergy(target, strength)

component_identity(::ReferenceVolumeEnergy) =
    ComponentIdentity(:quadratic_volume, v"1.0.0", :energy)

function required_properties(component::ReferenceVolumeEnergy)
    requester = component_identity(component)
    return PropertySchema(
        PropertyDescriptor(component.target_key, Float64, ConstantInitializer(0.0);
            requester, division = SplitOnDivision(), transition = PreserveOnTransition(),
            kind = BiologicalProperty),
        PropertyDescriptor(component.strength_key, Float64, ConstantInitializer(0.0);
            requester, division = CloneOnDivision(), transition = PreserveOnTransition(),
            kind = BiologicalProperty),
    )
end

"""Symmetric unordered contact Hamiltonian for the scalar reference engine."""
struct ReferenceContactEnergy{T, N} <: AbstractEnergy
    interactions::NTuple{N, NTuple{N, T}}
    medium_type::CellTypeID
end

function ReferenceContactEnergy(interactions::AbstractMatrix{T}; medium_type::CellTypeID) where {T <: Real}
    size(interactions, 1) == size(interactions, 2) || throw(ArgumentError(
        "contact interactions must form a square matrix"))
    all(isfinite, interactions) || throw(ArgumentError("contact interactions must be finite"))
    issymmetric(interactions) || throw(ArgumentError("contact interactions must be symmetric"))
    size(interactions, 1) > 0 || throw(ArgumentError("contact interactions must not be empty"))
    Int(value(medium_type)) <= size(interactions, 1) || throw(ArgumentError(
        "medium type lies outside the contact matrix"))
    count = size(interactions, 1)
    immutable_interactions = ntuple(i -> ntuple(j -> interactions[i, j], count), count)
    return ReferenceContactEnergy{T, count}(immutable_interactions, medium_type)
end

component_identity(::ReferenceContactEnergy) =
    ComponentIdentity(:unordered_contact, v"1.0.0", :energy)
required_relations(::ReferenceContactEnergy) = (:contact,)

@inline function _reference_owner_type(state::LogicalPottsState, owner::OwnerRef,
        medium_type::CellTypeID)
    return is_cell_owner(owner) ? cell_type(state, cell_id(owner)) : medium_type
end

@inline function _contact_value(component::ReferenceContactEnergy, left::CellTypeID,
        right::CellTypeID)
    i = Int(value(left))
    j = Int(value(right))
    1 <= i <= length(component.interactions) && 1 <= j <= length(component.interactions) ||
        throw(ArgumentError(
        "cell type ($i, $j) lies outside the contact matrix"))
    return component.interactions[i][j]
end

function energy_change(component::ReferenceVolumeEnergy, proposal::CopyProposal,
        state::LogicalPottsState)
    targets = property_values(state, component.target_key)
    strengths = property_values(state, component.strength_key)
    delta = 0.0
    if is_cell_owner(proposal.losing)
        id = cell_id(proposal.losing)
        index = Int(value(id))
        volume = finite_volume(state, id)
        old_energy = strengths[index] * (volume - targets[index])^2
        # Extinction retires the finite cell, so it contributes no post-copy volume energy.
        delta += volume == 1 ? -old_energy :
                 strengths[index] * (volume - 1 - targets[index])^2 - old_energy
    end
    if is_cell_owner(proposal.gaining)
        id = cell_id(proposal.gaining)
        index = Int(value(id))
        volume = finite_volume(state, id)
        delta += strengths[index] * ((volume + 1 - targets[index])^2 -
                                     (volume - targets[index])^2)
    end
    return delta
end

function energy_change(component::ReferenceContactEnergy, proposal::CopyProposal,
        state::LogicalPottsState)
    topology = VonNeumannTopology{2}()
    dims = lattice_size(state)
    coordinates = idx_to_coord(UInt32(proposal.recipient), dims)
    losing_type = _reference_owner_type(state, proposal.losing, component.medium_type)
    gaining_type = _reference_owner_type(state, proposal.gaining, component.medium_type)
    delta = zero(typeof(component.interactions[1][1]))
    for direction in UInt32(1):get_val(num_dirs(topology))
        neighbor_index = Int(get_neighbor_by_coord(topology, coordinates, direction, dims))
        neighbor = owner_at(state, neighbor_index)
        neighbor_type = _reference_owner_type(state, neighbor, component.medium_type)
        proposal.losing != neighbor &&
            (delta -= _contact_value(component, losing_type, neighbor_type))
        proposal.gaining != neighbor &&
            (delta += _contact_value(component, gaining_type, neighbor_type))
    end
    return delta
end

"""Complete scalar Hamiltonian evaluation used to validate local deltas."""
function reference_energy(component::ReferenceVolumeEnergy, state::LogicalPottsState)
    targets = property_values(state, component.target_key)
    strengths = property_values(state, component.strength_key)
    energy = 0.0
    for id in active_cell_ids(state)
        index = Int(value(id))
        energy += strengths[index] * (finite_volume(state, id) - targets[index])^2
    end
    return energy
end

function reference_energy(component::ReferenceContactEnergy, state::LogicalPottsState)
    topology = VonNeumannTopology{2}()
    dims = lattice_size(state)
    energy = zero(typeof(component.interactions[1][1]))
    for site in eachindex(lattice_storage(state))
        owner = owner_at(state, site)
        owner_type = _reference_owner_type(state, owner, component.medium_type)
        coordinates = idx_to_coord(UInt32(site), dims)
        for direction in UInt32(1):get_val(num_dirs(topology))
            neighbor_index = Int(get_neighbor_by_coord(topology, coordinates, direction, dims))
            neighbor = owner_at(state, neighbor_index)
            if owner != neighbor
                neighbor_type = _reference_owner_type(state, neighbor, component.medium_type)
                energy += _contact_value(component, owner_type, neighbor_type)
            end
        end
    end
    return energy / 2
end

"""Scientific inputs consumed by the first sequential reference vertical slice."""
struct ReferenceModel{E <: Tuple, C <: Tuple}
    energies::E
    constraints::C
end

function ReferenceModel(; energies = (), constraints = ())
    energy_tuple = Tuple(energies)
    constraint_tuple = Tuple(constraints)
    all(component -> component isa AbstractEnergy, energy_tuple) || throw(ArgumentError(
        "every reference energy must subtype AbstractEnergy"))
    all(component -> component isa AbstractHardConstraint, constraint_tuple) || throw(ArgumentError(
        "every reference constraint must subtype AbstractHardConstraint"))
    foreach(validate_energy_component, energy_tuple)
    foreach(validate_constraint_component, constraint_tuple)
    return ReferenceModel(energy_tuple, constraint_tuple)
end

reference_energy(model::ReferenceModel, state::LogicalPottsState) =
    sum(component -> reference_energy(component, state), model.energies; init = 0.0)

"""Conventional modified-Metropolis sequential reference algorithm."""
struct SequentialReference{T <: AbstractFloat} <: AbstractPottsAlgorithm
    temperature::T
    seed::UInt64
    checked::Bool

    function SequentialReference(temperature::T, seed::UInt64, checked::Bool) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "reference temperature must be finite and non-negative"))
        return new{T}(temperature, seed, checked)
    end
end

function SequentialReference(; temperature::T = 20.0, seed::Integer = 0,
        checked::Bool = true) where {T <: AbstractFloat}
    0 <= seed <= typemax(UInt64) || throw(ArgumentError("seed must fit in UInt64"))
    return SequentialReference(temperature, UInt64(seed), checked)
end

component_identity(::SequentialReference) =
    ComponentIdentity(:sequential_reference, v"1.0.0", :algorithm)
algorithm_guarantees(::SequentialReference) = AlgorithmGuaranteeProfile(
    proposal_process = (
        recipient = :uniform_with_replacement,
        donor = :uniform_direction_with_boundary_no_ops,
    ),
    equilibrium_status = :not_claimed,
    kinetic_interpretation = :conventional_sequential_cpm,
    transaction_semantics = (
        snapshot = :ordered_current_state,
        conflicts = :not_applicable,
        commit = :immediate_serial,
    ),
    mcs_normalization = :exact_n_independent_attempts,
    reproducibility_scope = :same_reference_contract,
    compatible_component_scopes = (
        supported = (:reference_volume, :reference_contact),
        rejected = (:unimplemented_reference_component,),
    ),
    validation_evidence = (:checked_scalar_execution, :exact_attempt_accounting),
    backend_contract = (:cpu_reference,),
    dimensions = (2,),
)

"""The temporary, explicitly versioned random-bit contract of the reference engine."""
reference_rng_version(::SequentialReference) = v"0.1.0-reference-splitmix64"

@enum _ReferenceDrawRole::UInt64 begin
    _RecipientSelection = 1
    _DirectionSelection = 2
    _AcceptanceSelection = 3
    _ProposalIdentity = 4
end

const _REFERENCE_ALGORITHM_DOMAIN = UInt64(0x9e3779b97f4a7c15)

@inline function _reference_mix(value::UInt64)
    value = xor(value, value >> 30) * UInt64(0xbf58476d1ce4e5b9)
    value = xor(value, value >> 27) * UInt64(0x94d049bb133111eb)
    return xor(value, value >> 31)
end

@inline function _reference_word(seed::UInt64, mcs::UInt64, attempt::UInt64,
        role::_ReferenceDrawRole, retry::UInt64 = UInt64(0))
    value = _reference_mix(xor(seed, _REFERENCE_ALGORITHM_DOMAIN))
    value = _reference_mix(xor(value, mcs))
    value = _reference_mix(xor(value, attempt))
    value = _reference_mix(xor(value, UInt64(role)))
    return _reference_mix(xor(value, retry))
end

function _reference_bounded(seed::UInt64, mcs::UInt64, attempt::UInt64,
        role::_ReferenceDrawRole, bound::Int)
    bound > 0 || throw(ArgumentError("bounded reference draws require a positive bound"))
    modulus = UInt64(bound)
    threshold = mod(-modulus, modulus)
    retry = UInt64(0)
    while true
        word = _reference_word(seed, mcs, attempt, role, retry)
        word >= threshold && return Int(mod(word, modulus)) + 1
        retry += 1
    end
end

@inline function _reference_uniform_open(seed::UInt64, mcs::UInt64, attempt::UInt64,
        role::_ReferenceDrawRole)
    mantissa = _reference_word(seed, mcs, attempt, role) >> 11
    return (Float64(mantissa) + 0.5) * 0x1.0p-53
end

struct ReferenceMCSReport
    mcs::UInt64
    candidate_attempts::Int
    realized_proposals::Int
    no_op_attempts::Int
    constraint_rejections::Int
    energy_rejections::Int
    accepted_copies::Int
    retired_cells::Vector{CellID}
end

function Base.:(==)(left::ReferenceMCSReport, right::ReferenceMCSReport)
    return left.mcs == right.mcs &&
           left.candidate_attempts == right.candidate_attempts &&
           left.realized_proposals == right.realized_proposals &&
           left.no_op_attempts == right.no_op_attempts &&
           left.constraint_rejections == right.constraint_rejections &&
           left.energy_rejections == right.energy_rejections &&
           left.accepted_copies == right.accepted_copies &&
           left.retired_cells == right.retired_cells
end

mutable struct ReferenceIntegrator{S <: LogicalPottsState, M <: ReferenceModel,
        A <: SequentialReference}
    state::S
    model::M
    algorithm::A
    mcs::UInt64
    pending_retired::Vector{CellID}
    last_report::Union{Nothing, ReferenceMCSReport}
end

"""Current authoritative logical state of a sequential reference integration."""
logical_state(integrator::ReferenceIntegrator) = integrator.state

function init_reference(state::LogicalPottsState, model::ReferenceModel,
        algorithm::SequentialReference = SequentialReference())
    ndims(lattice_storage(state)) == 2 || throw(ArgumentError(
        "the sequential reference slice currently supports only 2D state"))
    assert_valid_state(state)
    return ReferenceIntegrator(state, model, algorithm, UInt64(0), CellID[], nothing)
end

function _reference_accepts(delta_energy, temperature, draw)
    delta_energy <= zero(delta_energy) && return true
    temperature == zero(temperature) && return false
    return log(draw) < -delta_energy / temperature
end

"""Advance one and only one normalized MCS through the scalar reference engine."""
function step_reference!(integrator::ReferenceIntegrator)
    state = integrator.state
    if !isempty(integrator.pending_retired)
        state = release_retired_slots(LogicalRetirementResult(state,
            copy(integrator.pending_retired)))
        empty!(integrator.pending_retired)
    end
    integrator.algorithm.checked && assert_valid_state(state)
    next_mcs = integrator.mcs + UInt64(1)
    site_count = length(lattice_storage(state))
    directions = Int(get_val(num_dirs(VonNeumannTopology{2}())))
    no_ops = 0
    constraint_rejections = 0
    energy_rejections = 0
    accepted = 0
    retired = CellID[]
    dims = lattice_size(state)
    for attempt_index in 1:site_count
        attempt = UInt64(attempt_index)
        recipient = _reference_bounded(integrator.algorithm.seed, next_mcs, attempt,
            _RecipientSelection, site_count)
        direction = _reference_bounded(integrator.algorithm.seed, next_mcs, attempt,
            _DirectionSelection, directions)
        draw = _reference_uniform_open(integrator.algorithm.seed, next_mcs, attempt,
            _AcceptanceSelection)
        donor = Int(get_neighbor_by_dir(VonNeumannTopology{2}(), UInt32(recipient),
            UInt32(direction), dims))
        losing = owner_at(state, recipient)
        gaining = owner_at(state, donor)
        if losing == gaining
            no_ops += 1
            continue
        end
        proposal = CopyProposal(recipient, donor, losing, gaining; direction, mcs = next_mcs,
            semantic_id = _reference_word(integrator.algorithm.seed, next_mcs, attempt,
                _ProposalIdentity))
        if !all(constraint -> is_allowed(constraint, proposal, state), integrator.model.constraints)
            constraint_rejections += 1
            continue
        end
        delta = sum(component -> energy_change(component, proposal, state),
            integrator.model.energies; init = 0.0)
        if !_reference_accepts(delta, integrator.algorithm.temperature, draw)
            energy_rejections += 1
            continue
        end
        result = commit_copy_proposal(state, proposal)
        state = result.state
        append!(retired, result.retired)
        accepted += 1
    end
    unique!(retired)
    sort!(retired; by = value)
    append!(integrator.pending_retired, retired)
    integrator.algorithm.checked && assert_valid_state(state)
    realized = constraint_rejections + energy_rejections + accepted
    report = ReferenceMCSReport(next_mcs, site_count, realized, no_ops,
        constraint_rejections, energy_rejections, accepted, retired)
    report.candidate_attempts == report.no_op_attempts + report.constraint_rejections +
        report.energy_rejections + report.accepted_copies || error(
        "reference attempt accounting failed to partition the MCS budget")
    integrator.state = state
    integrator.mcs = next_mcs
    integrator.last_report = report
    return report
end
