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

struct HamiltonianEvaluationContext{V, A, P, D} <:
       AbstractHamiltonianEvaluationContext
    view::V
    anchor::A
    proposal::P
    domain_resource::D
end

HamiltonianEvaluationContext(view, anchor, proposal) =
    HamiltonianEvaluationContext(view, anchor, proposal, nothing)

@inline evaluator_parameters(context::HamiltonianEvaluationContext) =
    context.view.runtime.parameters
@inline _compiled_evaluator_parameters(
    context::HamiltonianEvaluationContext
) = context.view.runtime.parameters

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

@inline function _compiled_context_value(
        operation::ContextOperation{Identity},
        context::HamiltonianEvaluationContext,
    ) where {Identity}
    return invoke(
        context_value,
        Tuple{ContextOperation{Identity}, HamiltonianEvaluationContext},
        operation,
        context,
    )
end

@inline _view_owner(view::BeforeProposalView, site) =
    @inbounds view.runtime.ownership[site]
@inline _view_owner(view::AfterProposalView, site) =
    site == view.target ? view.new_owner : @inbounds(view.runtime.ownership[site])

@inline _view_volume(view::BeforeProposalView, cell::Int32) =
    cell <= 0 ? 0 : program_tracker_value(
        view.runtime, Val(:cell_volume), cell
    )
@inline function _view_volume(view::AfterProposalView, cell::Int32)
    cell <= 0 && return 0
    value = program_tracker_value(
        view.runtime, Val(:cell_volume), cell
    )
    cell == view.old_owner && (value -= 1)
    cell == view.new_owner && (value += 1)
    return value
end

@inline _view_surface(view::BeforeProposalView, cell::Int32) =
    cell <= 0 ? 0 : program_tracker_value(
        view.runtime, Val(:cell_surface), cell
    )

@inline function _view_surface(view::AfterProposalView, cell::Int32)
    cell <= 0 && return 0
    runtime = view.runtime
    source = tracker_source_view(runtime.program, runtime.ownership)
    return tracker_value_after(
        runtime.program.tracker_plan,
        runtime.trackers,
        source,
        Val(:cell_surface),
        cell,
        view.target,
        view.old_owner,
        view.new_owner,
    )
end

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return _view_volume(context.view, Int32(only(arguments)))
end


@inline function apply_resource_operation(
        ::ResourceOperation{:cell_surface},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return _view_surface(context.view, Int32(only(arguments)))
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
    return @inbounds context.domain_resource.endpoint_a[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:endpoint_b},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    return @inbounds context.domain_resource.endpoint_b[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:edge_payload},
        arguments,
        context::HamiltonianEvaluationContext,
    )
    edge = Int(first(arguments))
    payload_slot = Int(last(arguments))
    state = context.domain_resource
    return relationship_payload(state, edge, payload_slot)
end

@inline function state_value(
        context::HamiltonianEvaluationContext,
        handle::StateHandle,
        site,
    )
    return @inbounds state_block(
        context.view.runtime.descriptor_state, handle
    ).values[site]
end

@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::HamiltonianEvaluationContext,
    ) where {Identity}
    return invoke(
        apply_resource_operation,
        Tuple{ResourceOperation{Identity}, Any, HamiltonianEvaluationContext},
        operation,
        arguments,
        context,
    )
end

operation_context_supported(
    operation::ContextOperation,
    ::Type{AbstractHamiltonianEvaluationContext},
) = hasmethod(
    context_value,
    Tuple{typeof(operation), HamiltonianEvaluationContext},
)

operation_context_supported(
    operation::ResourceOperation,
    ::Type{AbstractHamiltonianEvaluationContext},
) = hasmethod(
    apply_resource_operation,
    Tuple{typeof(operation), Tuple, HamiltonianEvaluationContext},
)

@inline function _canonical_contact(runtime, first, second)
    linear = LinearIndices(runtime.ownership)
    return linear[first] <= linear[second] ?
           CanonicalContactAnchor(first, second) :
           CanonicalContactAnchor(second, first)
end

@inline function _compiled_anchor_energy(
        evaluator::StaticEvaluator,
        view,
        anchor,
        proposal,
        domain_resource,
        present::Bool,
    )
    present || return zero(eltype(view.runtime.parameters))
    context = HamiltonianEvaluationContext(
        view, anchor, proposal, domain_resource
    )
    return _compiled_evaluate_static(evaluator, context)
end

@inline function _anchor_energy_delta(
        evaluator::StaticEvaluator,
        before,
        after,
        anchor,
        proposal,
        domain_resource = nothing,
        before_present::Bool = true,
        after_present::Bool = true,
    )
    return _compiled_anchor_energy(
        evaluator,
        after,
        anchor,
        proposal,
        domain_resource,
        after_present,
    ) - _compiled_anchor_energy(
        evaluator,
        before,
        anchor,
        proposal,
        domain_resource,
        before_present,
    )
end

@inline function _hamiltonian_delta(
        evaluator::StaticEvaluator,
        role::HamiltonianRole{<:SiteEnergyDomainPlan, <:TargetSiteAffectedPlan},
        before,
        after,
        proposal,
        resources,
    )
    return _anchor_energy_delta(
        evaluator, before, after, proposal.target, proposal
    )
end

@inline function _hamiltonian_delta(
        evaluator::StaticEvaluator,
        role::HamiltonianRole{<:CellEnergyDomainPlan, <:SourceTargetCellsAffectedPlan},
        before,
        after,
        proposal,
        resources,
    )
    T = eltype(proposal.runtime.parameters)
    delta = zero(T)
    old_owner = proposal.old_owner
    new_owner = proposal.new_owner
    if old_owner > 0 &&
            @inbounds(proposal.runtime.cell_kinds[old_owner]) == role.domain.kind
        delta += _anchor_energy_delta(
            evaluator,
            before,
            after,
            old_owner,
            proposal,
            nothing,
            true,
            _view_volume(after, old_owner) > 0,
        )
    end
    if new_owner > 0 && new_owner != old_owner &&
            @inbounds(proposal.runtime.cell_kinds[new_owner]) == role.domain.kind
        delta += _anchor_energy_delta(
            evaluator,
            before,
            after,
            new_owner,
            proposal,
            nothing,
            _view_volume(before, new_owner) > 0,
            true,
        )
    end
    return delta
end

@inline function _hamiltonian_delta(
        evaluator::StaticEvaluator,
        role::HamiltonianRole{<:ContactEnergyDomainPlan, <:IncidentContactsAffectedPlan},
        before,
        after,
        proposal,
        resources,
    )
    runtime = proposal.runtime
    T = eltype(runtime.parameters)
    delta = zero(T)
    count = 0
    start, direction_count = _contact_domain_columns(
        resources, role.domain.relation_handle
    )
    stop = start + direction_count - 1
    for direction in start:stop
        neighbor = _neighbor_index(
            runtime.program,
            proposal.target,
            resources.contact_offsets,
            direction,
        )
        neighbor === nothing && continue
        contact = _canonical_contact(runtime, proposal.target, neighbor)
        duplicate = false
        for prior in start:(direction - 1)
            prior_neighbor = _neighbor_index(
                runtime.program,
                proposal.target,
                resources.contact_offsets,
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
            evaluator, before, after, contact, proposal
        )
    end
    return delta
end

@inline function _relationship_hamiltonian_delta(
        state,
        evaluator::StaticEvaluator,
        role::HamiltonianRole{<:RelationshipEnergyDomainPlan, <:IncidentRelationshipsAffectedPlan},
        before,
        after,
        proposal,
        resources,
    )
    runtime = proposal.runtime
    T = eltype(runtime.parameters)
    delta = zero(T)
    count = 0

    old_owner = proposal.old_owner
    new_owner = proposal.new_owner
    old_degree = old_owner > 0 ? Int(@inbounds state.degree[old_owner]) : 0
    new_degree = new_owner > 0 ? Int(@inbounds state.degree[new_owner]) : 0
    old_index = 1
    new_index = 1
    while old_index <= old_degree || new_index <= new_degree
        old_edge = old_index <= old_degree ?
                   @inbounds(state.incident_edges[old_index, old_owner]) :
                   typemax(Int32)
        new_edge = new_index <= new_degree ?
                   @inbounds(state.incident_edges[new_index, new_owner]) :
                   typemax(Int32)
        edge = min(old_edge, new_edge)
        old_edge == edge && (old_index += 1)
        new_edge == edge && (new_index += 1)
        count += 1
        count <= role.affected.maximum || throw(ArgumentError(
            "relationship affected-anchor proof was exceeded at runtime"
        ))
        a = @inbounds state.endpoint_a[edge]
        b = @inbounds state.endpoint_b[edge]
        before_present = @inbounds(state.active[edge]) &&
                         _view_volume(before, a) > 0 &&
                         _view_volume(before, b) > 0
        after_present = @inbounds(state.active[edge]) &&
                        _view_volume(after, a) > 0 &&
                        _view_volume(after, b) > 0
        delta += _anchor_energy_delta(
            evaluator,
            before,
            after,
            Int32(edge),
            proposal,
            state,
            before_present,
            after_present,
        )
    end
    return delta
end

@inline function _hamiltonian_delta(
        evaluator::StaticEvaluator,
        role::HamiltonianRole{<:RelationshipEnergyDomainPlan, <:IncidentRelationshipsAffectedPlan},
        before,
        after,
        proposal,
        resources,
    )
    slot = _relationship_domain_slot(
        resources, role.domain.relationship_handle
    )
    return _call_relationship_slot(
        _relationship_hamiltonian_delta,
        proposal.runtime.relationships,
        slot,
        (evaluator, role, before, after, proposal, resources),
    )
end

@inline function _compiled_hamiltonian_delta(
        evaluator::StaticEvaluator,
        role::HamiltonianRole,
        proposal::_ProposalEvaluationContext,
        resources::HamiltonianDomainResources =
            proposal.runtime.program.descriptor_plan.domain_resources,
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
        evaluator, role, before, after, proposal, resources
    )
end
