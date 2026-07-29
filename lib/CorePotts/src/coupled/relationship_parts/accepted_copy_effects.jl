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

@inline function energy_change(
        component::ContactRelationshipHamiltonianExecution,
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
        @inbounds relationships.active[index] == UInt8(0) &&
            continue
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
                transaction,
                CONTACT_RELATIONSHIP_STALE_ENDPOINT)
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
            strength, target_length,
            old_left, old_right)
        new_left = _contact_postcopy_center(
            context.state, proposal, moments, left)
        new_right = _contact_postcopy_center(
            context.state, proposal, moments, right)
        if new_left === nothing ||
                new_right === nothing
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
@inline proposal_energy_change(
    component::ContactRelationshipHamiltonianExecution,
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
