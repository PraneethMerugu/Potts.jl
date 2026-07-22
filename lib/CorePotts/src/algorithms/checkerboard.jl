"""Device-resident schedule and candidate storage for one realized-domain coloring."""
struct CheckerboardWorkspace{S, O, F, A, P, C, X, D, M, T}
    sites::S
    color_order::O
    color_offsets::F
    attempts::A
    priorities::P
    selected::C
    transactions::X
    dispositions::D
    cell_max_priority::M
    cell_min_identity::T
    color_count::UInt32
    maximum_color_size::UInt32
end

const _CHECKERBOARD_PENDING = UInt8(0)
const _CHECKERBOARD_CONFLICT = UInt8(1)
const _CHECKERBOARD_CONSTRAINT_REJECTION = UInt8(2)
const _CHECKERBOARD_ACCEPTANCE_REJECTION = UInt8(3)
const _CHECKERBOARD_ACCEPTED = UInt8(4)

function _host_domain(domain::CompiledCartesianDomain)
    storage = domain.storage
    return CompiledCartesianDomain(domain.descriptor, CompiledCartesianDomainStorage(
        Array(storage.mutable_mask), Array(storage.mutable_sites),
        Array(storage.immutable_tags), Array(storage.immutable_ids)))
end

"""Canonical CSR form of the union of realized mutable-site conflict relations."""
function _realized_conflict_graph(domain::CompiledCartesianDomain, relations)
    host_domain = _host_domain(domain)
    sites = sort!(Int.(host_domain.storage.mutable_sites))
    mutable_site_set = Set(sites)
    site_position = Dict(site => index for (index, site) in pairs(sites))
    neighbors = UInt32[]
    neighbor_offsets = UInt32[1]
    maximum_degree = 0
    for site in sites
        site_neighbors = UInt32[]
        for relation in relations, direction in 1:direction_count(relation)
            neighbor = _realize_neighbor_unchecked(host_domain, relation, site, direction)
            neighbor.kind === MutableNeighbor || continue
            neighbor_site = Int(neighbor.site)
            neighbor_site != site && neighbor_site in mutable_site_set &&
                push!(site_neighbors, UInt32(site_position[neighbor_site]))
        end
        sort!(unique!(site_neighbors))
        append!(neighbors, site_neighbors)
        push!(neighbor_offsets, UInt32(length(neighbors) + 1))
        maximum_degree = max(maximum_degree, length(site_neighbors))
    end
    return UInt32.(sites), neighbors, neighbor_offsets, maximum_degree
end

"""Deterministic greedy coloring of one canonical realized conflict graph."""
function _realized_coloring(domain::CompiledCartesianDomain, relations)
    graph_sites, neighbors, neighbor_offsets, maximum_degree =
        _realized_conflict_graph(domain, relations)
    sites = Int.(graph_sites)
    colors = zeros(Int, length(sites))
    forbidden = falses(maximum_degree + 1)
    maximum_color = 0
    for (index, site) in pairs(sites)
        fill!(forbidden, false)
        first_neighbor = Int(neighbor_offsets[index])
        stop_neighbor = Int(neighbor_offsets[index + 1]) - 1
        for neighbor_index in first_neighbor:stop_neighbor
            neighbor_position = Int(neighbors[neighbor_index])
            neighbor_color = colors[neighbor_position]
            neighbor_color > 0 && (forbidden[neighbor_color] = true)
        end
        color = findfirst(!, forbidden)
        colors[index] = color
        maximum_color = max(maximum_color, color)
    end
    maximum_color <= typemax(UInt8) || throw(ArgumentError(
        "checkerboard realized-domain coloring exceeds the v1 subround domain"))
    ordered_sites = UInt32[]
    offsets = UInt32[1]
    maximum_size = 0
    for color in 1:maximum_color
        color_sites = UInt32[UInt32(sites[index]) for index in eachindex(sites)
            if colors[index] == color]
        append!(ordered_sites, color_sites)
        push!(offsets, UInt32(length(ordered_sites) + 1))
        maximum_size = max(maximum_size, length(color_sites))
    end
    return ordered_sites, offsets, maximum_color, maximum_size
end

function _device_copy(prototype, source::Vector{T}) where {T}
    destination = similar(prototype, T, length(source))
    copyto!(destination, source)
    return destination
end

function _record_checkerboard_array!(plan, array)
    domain = plan.backend isa KernelAbstractions.CPU ? :host : :device
    record_allocation!(plan, domain, _array_bytes(array))
    return array
end

function _qualified_snapshot_access(component, algorithm_name)
    access = scientific_access(component)
    access isa SnapshotScientificAccess || throw(ArgumentError(
        "$algorithm_name component $(typeof(component)) has no qualified scientific_access trait"))
    access.private_workspace && throw(ArgumentError(
        "$algorithm_name component $(typeof(component)) requires proposal-private workspace"))
    return access
end

function _parallel_component_compatibility(algorithm_name::String,
        components::ScientificComponentSet, moment_tracker)
    messages = _scientific_interface_messages(components)
    isempty(components.constraints) || (messages = (messages...,
        "$algorithm_name does not qualify hard constraints",))
    moment_tracker === nothing || (messages = (messages...,
        "$algorithm_name does not qualify moment-dependent components",))
    for component in (components.energies..., components.drives...,
            components.kinetic_modifiers..., components.mechanics...)
        try
            _qualified_snapshot_access(component, algorithm_name)
        catch error
            messages = (messages..., sprint(showerror, error))
        end
    end
    return messages
end

algorithm_component_compatibility(::CheckerboardSweepCPM,
    components::ScientificComponentSet, moment_tracker = nothing) =
    _parallel_component_compatibility(
        "CheckerboardSweepCPM", components, moment_tracker)

function _validate_checkerboard_components(components, state, moment_tracker)
    isempty(components.constraints) || throw(ArgumentError(
        "CheckerboardSweepCPM does not yet qualify hard constraints; use SequentialCPM"))
    moment_tracker === nothing || throw(ArgumentError(
        "CheckerboardSweepCPM does not yet qualify moment-dependent components"))
    state.trackers.moments isa NoMomentStorage || throw(ArgumentError(
        "CheckerboardSweepCPM requires state compiled without moment storage"))
    accesses = map(component -> _qualified_snapshot_access(
            component, "CheckerboardSweepCPM"),
        (components.energies..., components.drives..., components.kinetic_modifiers...,
            components.mechanics...))
    return accesses
end

function _compiled_conflict_relations(state, proposal_relation, accesses)
    relations = Any[proposal_relation, state.boundary_tracker.relation]
    for access in accesses
        append!(relations, access.relations)
    end
    unique!(relations)
    return relations
end

function _allocate_checkerboard_workspace(state, proposal_relation, accesses, plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        synchronize_observation!(plan)
        record_transfer!(plan, :device_to_host)
    end
    conflict_relations = _compiled_conflict_relations(
        state, proposal_relation, accesses)
    host_sites, host_offsets, color_count, maximum_size =
        _realized_coloring(state.domain, conflict_relations)
    prototype = state.potts.storage.active
    sites = _record_checkerboard_array!(plan, _device_copy(prototype, host_sites))
    offsets = _record_checkerboard_array!(plan, _device_copy(prototype, host_offsets))
    order = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, color_count))
    attempts = _record_checkerboard_array!(plan,
        similar(prototype, CopyAttempt, length(host_sites)))
    priorities = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, length(host_sites)))
    selected = _record_checkerboard_array!(plan,
        similar(prototype, UInt8, length(host_sites)))
    boundary_type = eltype(state.trackers.boundary_measures)
    transaction_type = StagedCopyTransaction{boundary_type, NoMomentDelta}
    transactions = _record_checkerboard_array!(plan,
        similar(prototype, transaction_type, length(host_sites)))
    dispositions = _record_checkerboard_array!(plan,
        similar(prototype, UInt8, length(host_sites)))
    cell_max_priority = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, length(state.potts.storage.active)))
    cell_min_identity = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, length(state.potts.storage.active)))
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :host_to_device)
    end
    return CheckerboardWorkspace(sites, order, offsets, attempts, priorities,
        selected, transactions, dispositions, cell_max_priority, cell_min_identity,
        UInt32(color_count), UInt32(maximum_size))
end

function init_scientific(state::CompiledScientificState,
        proposal_relation::StaticCartesianRelation{<:ProposalRole},
        components::ScientificComponentSet, algorithm::CheckerboardSweepCPM;
        seed::Integer = 0, rng::AbstractRNGContract = Philox4x32x10V1(),
        plan::ExecutionPlan = _default_execution_plan(state), moment_tracker = nothing,
        connectivity_workspace = nothing, lifecycle = NoCompiledLifecycle(),
        initialize_mechanics::Bool = true)
    connectivity_workspace === nothing || throw(ArgumentError(
        "CheckerboardSweepCPM owns its conflict workspace; connectivity workspace is unsupported"))
    _validate_scientific_initialization(
        state, proposal_relation, components, algorithm, seed, rng, plan)
    accesses = _validate_checkerboard_components(components, state, moment_tracker)
    _validate_zero_temperature(algorithm, components)
    workspace = _allocate_checkerboard_workspace(
        state, proposal_relation, accesses, plan)
    report_storage = similar(state.potts.storage.active, UInt64,
        _SEQUENTIAL_REPORT_FIELDS)
    _record_checkerboard_array!(plan, report_storage)
    integrator = ScientificPottsIntegrator(state, components, proposal_relation, algorithm, rng,
        plan, NoConnectivityWorkspace(), nothing, workspace, lifecycle, report_storage,
        UInt64(seed), UInt64(0))
    return initialize_mechanics ? _initialize_mechanics!(integrator) : integrator
end

@inline function _checkerboard_address(stream, mcs, site; draw = UInt16(0))
    return _rng_address_unchecked(stream, mcs, UInt8(0), UInt16(0), SiteEntity,
        site, UInt64(0), UInt8(0), draw)
end

@kernel function _checkerboard_order_kernel!(order, rng, seed, mcs, color_count)
    index = @index(Global, Linear)
    @inbounds if index == 1
        count = Int(color_count)
        for color in 1:count
            order[color] = Base.unsafe_trunc(UInt32, color)
        end
        for color in count:-1:2
            draw = Base.unsafe_trunc(UInt16, count - color)
            address = _rng_address_unchecked(CheckerboardOrderStream, mcs, UInt8(0),
                UInt16(0), GlobalEntity, UInt32(0), UInt64(0), UInt8(0), draw)
            selected = Int(bounded_uint(
                rng, seed, address, Base.unsafe_trunc(UInt32, color))) + 1
            order[color], order[selected] = order[selected], order[color]
        end
    end
end

@kernel function _checkerboard_candidates!(sites, color_order, color_offsets, attempts,
        priorities, selected, dispositions, state, relation, proposal_process,
        rng, seed, mcs, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        site = @inbounds sites[Int(schedule_index)]
        address = _checkerboard_address(ProposalDirectionStream, mcs, site)
        direction = bounded_uint(rng, seed, address,
            UInt32(direction_count(relation))) + UInt32(1)
        attempt = construct_proposal_attempt(proposal_process,
            state, state.domain, relation, Int(site), direction, mcs, UInt64(site))
        @inbounds begin
            attempts[Int(schedule_index)] = attempt
            priority_address = _checkerboard_address(
                CheckerboardPriorityStream, mcs, site)
            priorities[Int(schedule_index)] =
                rng_word(rng, seed, priority_address)
            selected[Int(schedule_index)] =
                attempt.outcome === ActionableCopy ? UInt8(1) : UInt8(0)
            dispositions[Int(schedule_index)] = _CHECKERBOARD_PENDING
        end
    end
end

@kernel function _checkerboard_clear_claims!(cell_max_priority, cell_min_identity)
    cell = @index(Global, Linear)
    @inbounds begin
        cell_max_priority[cell] = UInt32(0)
        cell_min_identity[cell] = typemax(UInt32)
    end
end

@inline function _claim_cell_priority!(claims, owner::OwnerRef, priority)
    if is_cell_owner(owner)
        Atomix.@atomic max(claims[Int(owner.value)], priority)
    end
    return nothing
end

@kernel function _checkerboard_claim_priorities!(color_order, color_offsets, attempts,
        priorities, cell_max_priority, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        attempt = @inbounds attempts[Int(schedule_index)]
        if attempt.outcome === ActionableCopy
            priority = @inbounds priorities[Int(schedule_index)]
            _claim_cell_priority!(cell_max_priority, attempt.losing, priority)
            _claim_cell_priority!(cell_max_priority, attempt.gaining, priority)
        end
    end
end

@inline function _claim_cell_identity!(max_priorities, min_identities,
        owner::OwnerRef, priority, identity)
    if is_cell_owner(owner) &&
       @inbounds(max_priorities[Int(owner.value)] == priority)
        Atomix.@atomic min(min_identities[Int(owner.value)], identity)
    end
    return nothing
end


@kernel function _checkerboard_claim_ties!(color_order, color_offsets, attempts,
        priorities, cell_max_priority, cell_min_identity, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        attempt = @inbounds attempts[Int(schedule_index)]
        if attempt.outcome === ActionableCopy
            priority = @inbounds priorities[Int(schedule_index)]
            identity = attempt.recipient
            _claim_cell_identity!(cell_max_priority, cell_min_identity,
                attempt.losing, priority, identity)
            _claim_cell_identity!(cell_max_priority, cell_min_identity,
                attempt.gaining, priority, identity)
        end
    end
end

@inline function _wins_cell_claim(max_priorities, min_identities,
        owner::OwnerRef, priority, identity)
    is_cell_owner(owner) || return true
    index = Int(owner.value)
    return @inbounds max_priorities[index] == priority &&
                     min_identities[index] == identity
end

@kernel function _checkerboard_select_conflicts!(color_order, color_offsets, attempts,
        priorities, selected, dispositions, cell_max_priority, cell_min_identity, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        attempt = @inbounds attempts[Int(schedule_index)]
        if attempt.outcome === ActionableCopy
            priority = @inbounds priorities[Int(schedule_index)]
            identity = attempt.recipient
            wins = _wins_cell_claim(cell_max_priority, cell_min_identity,
                       attempt.losing, priority, identity) &&
                   _wins_cell_claim(cell_max_priority, cell_min_identity,
                       attempt.gaining, priority, identity)
            @inbounds begin
                selected[Int(schedule_index)] = wins ? UInt8(1) : UInt8(0)
                !wins && (dispositions[Int(schedule_index)] =
                    _CHECKERBOARD_CONFLICT)
            end
        end
    end
end

@kernel function _checkerboard_evaluate!(color_order, color_offsets, attempts, selected,
        transactions, dispositions, state, components, algorithm, rng, seed, mcs, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        if @inbounds(selected[Int(schedule_index)] != 0)
            attempt = @inbounds attempts[Int(schedule_index)]
            proposal = _copy_proposal_unchecked(attempt.recipient, attempt.donor,
                attempt.losing, attempt.gaining, attempt.direction, attempt.mcs,
                attempt.semantic_id, attempt.forward_multiplicity,
                attempt.reverse_multiplicity)
            transaction = _stage_copy_transaction_unchecked(
                state, state.boundary_tracker, proposal; moment_tracker = nothing)
            @inbounds transactions[Int(schedule_index)] = transaction
            context = ScientificProposalContext(
                state, transaction, NoConnectivityWorkspace(), UInt32(1))
            evaluation = evaluate_copy(
                components, proposal, context, typeof(algorithm.temperature))
            if !evaluation.constraints_allowed
                @inbounds dispositions[Int(schedule_index)] =
                    _CHECKERBOARD_CONSTRAINT_REJECTION
            else
                probability = _acceptance_probability(ConventionalMetropolis(),
                    _unchecked_acceptance_inputs(evaluation), algorithm.temperature)
                address = _checkerboard_address(
                    AcceptanceStream, mcs, attempt.recipient)
                draw = uniform_open01(
                    typeof(algorithm.temperature), rng, seed, address)
                @inbounds dispositions[Int(schedule_index)] = draw < probability ?
                    _CHECKERBOARD_ACCEPTED : _CHECKERBOARD_ACCEPTANCE_REJECTION
            end
        end
    end
end

@inline function _commit_checkerboard!(state, transaction)
    proposal = transaction.proposal
    delta = transaction.trackers
    core = state.core
    trackers = state.trackers
    recipient = proposal.recipient
    @inbounds begin
        core.ownership.tags[recipient] = proposal.gaining.tag
        core.ownership.ids[recipient] = proposal.gaining.value
        if delta.losing_cell != 0
            losing = Int(delta.losing_cell)
            trackers.finite_volumes[losing] -= Int32(1)
            trackers.boundary_measures[losing] += delta.losing_boundary
            if trackers.finite_volumes[losing] == 0
                core.active[losing] = UInt8(0)
                core.cell_types[losing] = UInt32(0)
                _reset_columns!(Tuple(core.properties), Tuple(state.retirement_defaults), losing)
            end
        else
            Atomix.@atomic trackers.medium_volumes[Int(delta.losing_medium)] -= Int32(1)
        end
        if delta.gaining_cell != 0
            gaining = Int(delta.gaining_cell)
            trackers.finite_volumes[gaining] += Int32(1)
            trackers.boundary_measures[gaining] += delta.gaining_boundary
        else
            Atomix.@atomic trackers.medium_volumes[Int(delta.gaining_medium)] += Int32(1)
        end
    end
    return nothing
end

@kernel function _checkerboard_commit!(color_order, color_offsets, transactions,
        dispositions, state, ordinal)
    local_index = @index(Global, Linear)
    color = @inbounds color_order[Int(ordinal)]
    first_index = @inbounds color_offsets[Int(color)]
    stop_index = @inbounds color_offsets[Int(color) + 1]
    count = stop_index - first_index
    if local_index <= count
        schedule_index = first_index + Base.unsafe_trunc(UInt32, local_index - 1)
        if @inbounds(dispositions[Int(schedule_index)] ==
                     _CHECKERBOARD_ACCEPTED)
            transaction = @inbounds transactions[Int(schedule_index)]
            _commit_checkerboard!(state, transaction)
        end
    end
end

@kernel function _checkerboard_report!(report, attempts, dispositions, color_count, mcs)
    index = @index(Global, Linear)
    if index == 1
        realized = UInt64(0)
        same_owner = UInt64(0)
        boundary = UInt64(0)
        immutable = UInt64(0)
        conflicts = UInt64(0)
        constraint_rejections = UInt64(0)
        acceptance_rejections = UInt64(0)
        accepted = UInt64(0)
        for candidate in eachindex(attempts)
            attempt = @inbounds attempts[candidate]
            disposition = @inbounds dispositions[candidate]
            if attempt.outcome === ActionableCopy
                realized += UInt64(1)
                conflicts += UInt64(disposition == _CHECKERBOARD_CONFLICT)
                constraint_rejections +=
                    UInt64(disposition == _CHECKERBOARD_CONSTRAINT_REJECTION)
                acceptance_rejections +=
                    UInt64(disposition == _CHECKERBOARD_ACCEPTANCE_REJECTION)
                accepted += UInt64(disposition == _CHECKERBOARD_ACCEPTED)
            elseif attempt.outcome === SameOwnerAttempt
                same_owner += UInt64(1)
            elseif attempt.outcome === BoundaryNullAttempt
                boundary += UInt64(1)
            else
                immutable += UInt64(1)
            end
        end
        candidates = UInt64(length(attempts))
        @inbounds begin
            report[1] = mcs
            report[2] = UInt64(color_count)
            report[3] = candidates
            report[4] = candidates
            report[5] = realized
            report[6] = same_owner
            report[7] = boundary
            report[8] = immutable
            report[9] = conflicts
            report[10] = constraint_rejections
            report[11] = acceptance_rejections
            report[12] = accepted
        end
    end
end

function _checkerboard_execution_kernels(plan, color_size)
    return (
        candidates = _execution_kernel(plan, _checkerboard_candidates!, color_size),
        clear_claims = _fixed_execution_kernel(plan, _checkerboard_clear_claims!),
        claim_priorities = _execution_kernel(
            plan, _checkerboard_claim_priorities!, color_size),
        claim_ties = _execution_kernel(plan, _checkerboard_claim_ties!, color_size),
        select_conflicts = _execution_kernel(
            plan, _checkerboard_select_conflicts!, color_size),
        evaluation = _execution_kernel(plan, _checkerboard_evaluate!, color_size),
        commit = _execution_kernel(plan, _checkerboard_commit!, color_size),
    )
end

function _perform_checkerboard_mcs!(integrator, next_mcs, workspace, kernels, color_size)
    for ordinal in UInt32(1):workspace.color_count
        _advance_checkerboard_mechanics!(integrator, next_mcs, ordinal, UInt8(0))
        launch!(integrator.plan, kernels.clear_claims, workspace.cell_max_priority,
            workspace.cell_min_identity;
            ndrange = length(workspace.cell_max_priority))
        launch!(integrator.plan, kernels.candidates, workspace.sites,
            workspace.color_order, workspace.color_offsets, workspace.attempts,
            workspace.priorities, workspace.selected, workspace.dispositions,
            scientific_execution(integrator.state), integrator.proposal_relation,
            proposal_law(integrator.algorithm), integrator.rng, integrator.seed,
            next_mcs, ordinal;
            ndrange = color_size)
        launch!(integrator.plan, kernels.claim_priorities, workspace.color_order,
            workspace.color_offsets, workspace.attempts, workspace.priorities,
            workspace.cell_max_priority, ordinal;
            ndrange = color_size)
        launch!(integrator.plan, kernels.claim_ties, workspace.color_order,
            workspace.color_offsets, workspace.attempts, workspace.priorities,
            workspace.cell_max_priority, workspace.cell_min_identity, ordinal;
            ndrange = color_size)
        launch!(integrator.plan, kernels.select_conflicts, workspace.color_order,
            workspace.color_offsets, workspace.attempts, workspace.priorities,
            workspace.selected, workspace.dispositions,
            workspace.cell_max_priority, workspace.cell_min_identity, ordinal;
            ndrange = color_size)
        launch!(integrator.plan, kernels.evaluation, workspace.color_order,
            workspace.color_offsets, workspace.attempts, workspace.selected,
            workspace.transactions, workspace.dispositions,
            scientific_execution(integrator.state), integrator.components,
            integrator.algorithm, integrator.rng, integrator.seed, next_mcs, ordinal;
            ndrange = color_size)
        launch!(integrator.plan, kernels.commit, workspace.color_order,
            workspace.color_offsets, workspace.transactions, workspace.dispositions,
            scientific_execution(integrator.state), ordinal;
            ndrange = color_size)
        _advance_checkerboard_mechanics!(integrator, next_mcs, ordinal, UInt8(1))
    end
    run_compiled_lifecycle!(integrator, integrator.lifecycle, next_mcs)
    integrator.mcs = next_mcs
    return integrator
end

function perform_scientific_mcs!(integrator::ScientificPottsIntegrator{S, C, R,
        <:CheckerboardSweepCPM}, ::CheckerboardSweepCPM) where {S, C, R}
    next_mcs = integrator.mcs + UInt64(1)
    workspace = integrator.algorithm_workspace
    order_kernel = _checkerboard_order_kernel!(integrator.plan.backend, 1)
    launch!(integrator.plan, order_kernel, workspace.color_order, integrator.rng,
        integrator.seed, next_mcs, workspace.color_count; ndrange = 1)
    color_size = Int(workspace.maximum_color_size)
    kernels = _checkerboard_execution_kernels(integrator.plan, color_size)
    return _perform_checkerboard_mcs!(
        integrator, next_mcs, workspace, kernels, color_size)
end

function _current_mcs_report(integrator::ScientificPottsIntegrator,
        ::CheckerboardSweepCPM)
    integrator.mcs > 0 || return nothing
    workspace = integrator.algorithm_workspace
    report_kernel = _checkerboard_report!(integrator.plan.backend, 1)
    launch!(integrator.plan, report_kernel, integrator.report_storage,
        workspace.attempts, workspace.dispositions, workspace.color_count,
        integrator.mcs; ndrange = 1)
    return _standard_current_mcs_report(integrator)
end
