# Immutable conservative-energy evaluation over compiler-proven affected anchors.

"""Immutable read-only view of runtime state before one proposed ownership copy."""
struct BeforeProposalView{R, I}
    runtime::R
    target::I
    old_owner::Int32
    new_owner::Int32
end

"""Immutable overlay view of runtime state after one proposed ownership copy."""
struct AfterProposalView{R, I}
    runtime::R
    target::I
    old_owner::Int32
    new_owner::Int32
end

struct CanonicalContactAnchor{I}
    first::I
    second::I
end

struct HamiltonianEvaluationContext{V, A, P}
    view::V
    anchor::A
    proposal::P
end

@inline evaluator_parameters(context::HamiltonianEvaluationContext) =
    context.view.runtime.parameters

for (identity, kind) in (
        :energy_anchor_site => :site,
        :energy_anchor_cell => :cell,
        :energy_anchor_contact => :contact,
        :energy_anchor_relationship => :relationship,
    )
    @eval @inline context_value(
        ::ContextOperation{$(QuoteNode(identity))},
        context::HamiltonianEvaluationContext,
    ) = context.anchor
end

@inline _view_owner(view::BeforeProposalView, site) =
    @inbounds view.runtime.ownership[site]
@inline _view_owner(view::AfterProposalView, site) =
    site == view.target ? view.new_owner : @inbounds(view.runtime.ownership[site])

@inline _view_volume(view::BeforeProposalView, cell::Int32) =
    cell <= 0 ? 0 : @inbounds(view.runtime.volumes[cell])
@inline function _view_volume(view::AfterProposalView, cell::Int32)
    cell <= 0 && return 0
    value = @inbounds view.runtime.volumes[cell]
    cell == view.old_owner && (value -= 1)
    cell == view.new_owner && (value += 1)
    return value
end

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return _view_volume(context.view, Int32(only(arguments)))
end

@inline function apply_resource_operation(
        ::ResourceOperation{:occupancy},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    kind = Int16(first(arguments))
    owner = _view_owner(context.view, last(arguments))
    return _owner_kind(context.view.runtime, owner) == kind
end

@inline function apply_resource_operation(
        ::ResourceOperation{:contact_owner_a},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    contact = only(arguments)
    return _view_owner(context.view, contact.first)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:contact_owner_b},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    contact = only(arguments)
    return _view_owner(context.view, contact.second)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:contact_kind_a},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    contact = only(arguments)
    return _owner_kind(
        context.view.runtime,
        _view_owner(context.view, contact.first),
    )
end

@inline function apply_resource_operation(
        ::ResourceOperation{:contact_kind_b},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    contact = only(arguments)
    return _owner_kind(
        context.view.runtime,
        _view_owner(context.view, contact.second),
    )
end

@inline function _view_cell_center(view::BeforeProposalView, cell::Int32)
    return _cell_center(view.runtime, cell)
end
@inline function _view_cell_center(view::AfterProposalView, cell::Int32)
    return _cell_center(
        view.runtime,
        cell;
        replaced_site = view.target,
        replacement_owner = view.new_owner,
    )
end

@inline function _view_cell_length(view::BeforeProposalView, cell::Int32)
    return _cell_length(view.runtime, cell)
end
@inline function _view_cell_length(view::AfterProposalView, cell::Int32)
    return _cell_length(
        view.runtime,
        cell;
        replaced_site = view.target,
        replacement_owner = view.new_owner,
    )
end

@inline apply_resource_operation(
    ::ResourceOperation{:cell_center}, arguments,
    context::HamiltonianEvaluationContext,
) = _view_cell_center(context.view, Int32(only(arguments)))
@inline apply_resource_operation(
    ::ResourceOperation{:unwrapped_center}, arguments,
    context::HamiltonianEvaluationContext,
) = _view_cell_center(context.view, Int32(only(arguments)))
@inline apply_resource_operation(
    ::ResourceOperation{:cell_elongation}, arguments,
    context::HamiltonianEvaluationContext,
) = _view_cell_length(context.view, Int32(only(arguments)))
@inline apply_resource_operation(
    ::ResourceOperation{:distance}, arguments,
    ::HamiltonianEvaluationContext,
) = _center_distance(first(arguments), last(arguments))

@inline function apply_resource_operation(
        ::ResourceOperation{:endpoint_a},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return @inbounds context.view.runtime.relationships.endpoint_a[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:endpoint_b},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return @inbounds context.view.runtime.relationships.endpoint_b[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:edge_payload},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    edge = Int(first(arguments))
    payload = UInt8(last(arguments))
    state = context.view.runtime.relationships
    payload == 0x01 && return @inbounds state.strength[edge]
    payload == 0x02 && return @inbounds state.target[edge]
    payload == 0x03 && return @inbounds state.maximum[edge]
    throw(ArgumentError("unknown relationship energy payload `$payload`"))
end

@inline function state_value(
        context::HamiltonianEvaluationContext,
        handle::StateHandle,
        site,
    )
    states = values(context.view.runtime.stored_states)
    return @inbounds states[Int(handle.index)][site]
end

@inline function _canonical_contact(runtime, first, second)
    linear = LinearIndices(runtime.ownership)
    return linear[first] <= linear[second] ?
           CanonicalContactAnchor(first, second) :
           CanonicalContactAnchor(second, first)
end

@inline function _anchor_energy_delta(
        descriptor::ProposalDescriptor,
        before,
        after,
        anchor,
        proposal,
    )
    before_context = HamiltonianEvaluationContext(before, anchor, proposal)
    after_context = HamiltonianEvaluationContext(after, anchor, proposal)
    return descriptor_evaluate_energy(descriptor, after_context) -
           descriptor_evaluate_energy(descriptor, before_context)
end

@inline function _hamiltonian_delta(
        descriptor::ProposalDescriptor,
        role::HamiltonianRole{<:SiteEnergyDomainPlan, <:TargetSiteAffectedPlan},
        before,
        after,
        proposal,
    )
    return _anchor_energy_delta(
        descriptor, before, after, proposal.target, proposal
    )
end

@inline function _hamiltonian_delta(
        descriptor::ProposalDescriptor,
        role::HamiltonianRole{<:CellEnergyDomainPlan, <:SourceTargetCellsAffectedPlan},
        before,
        after,
        proposal,
    )
    T = eltype(proposal.runtime.parameters)
    delta = zero(T)
    old_owner = proposal.old_owner
    new_owner = proposal.new_owner
    if old_owner > 0 &&
            @inbounds(proposal.runtime.cell_kinds[old_owner]) == role.domain.kind
        delta += _anchor_energy_delta(
            descriptor, before, after, old_owner, proposal
        )
    end
    if new_owner > 0 && new_owner != old_owner &&
            @inbounds(proposal.runtime.cell_kinds[new_owner]) == role.domain.kind
        delta += _anchor_energy_delta(
            descriptor, before, after, new_owner, proposal
        )
    end
    return delta
end

@inline function _hamiltonian_delta(
        descriptor::ProposalDescriptor,
        role::HamiltonianRole{<:ContactEnergyDomainPlan, <:IncidentContactsAffectedPlan},
        before,
        after,
        proposal,
    )
    runtime = proposal.runtime
    T = eltype(runtime.parameters)
    delta = zero(T)
    count = 0
    for direction in axes(runtime.program.contact_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program,
            proposal.target,
            runtime.program.contact_offsets,
            direction,
        )
        neighbor === nothing && continue
        contact = _canonical_contact(runtime, proposal.target, neighbor)
        duplicate = false
        for prior in 1:(direction - 1)
            prior_neighbor = _neighbor_index(
                runtime.program,
                proposal.target,
                runtime.program.contact_offsets,
                prior,
            )
            prior_neighbor === nothing && continue
            if _canonical_contact(runtime, proposal.target, prior_neighbor) == contact
                duplicate = true
                break
            end
        end
        duplicate && continue
        count += 1
        count <= role.affected.maximum || throw(ArgumentError(
            "contact affected-anchor proof was exceeded at runtime"
        ))
        delta += _anchor_energy_delta(
            descriptor, before, after, contact, proposal
        )
    end
    return delta
end

@inline function _hamiltonian_delta(
        descriptor::ProposalDescriptor,
        role::HamiltonianRole{<:RelationshipEnergyDomainPlan, <:IncidentRelationshipsAffectedPlan},
        before,
        after,
        proposal,
    )
    runtime = proposal.runtime
    state = runtime.relationships
    T = eltype(runtime.parameters)
    state === nothing && return zero(T)
    delta = zero(T)
    count = 0
    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        a = @inbounds state.endpoint_a[edge]
        b = @inbounds state.endpoint_b[edge]
        (a in (proposal.old_owner, proposal.new_owner) ||
         b in (proposal.old_owner, proposal.new_owner)) || continue
        count += 1
        count <= role.affected.maximum || throw(ArgumentError(
            "relationship affected-anchor proof was exceeded at runtime"
        ))
        delta += _anchor_energy_delta(
            descriptor, before, after, Int32(edge), proposal
        )
    end
    return delta
end

@inline function descriptor_hamiltonian_delta(
        descriptor::ProposalDescriptor,
        proposal::_ProposalEvaluationContext,
    )
    before = BeforeProposalView(
        proposal.runtime,
        proposal.target,
        proposal.old_owner,
        proposal.new_owner,
    )
    after = AfterProposalView(
        proposal.runtime,
        proposal.target,
        proposal.old_owner,
        proposal.new_owner,
    )
    return _hamiltonian_delta(
        descriptor, descriptor.role, before, after, proposal
    )
end

