"""Compiled realized-graph schedule and reusable storage for `LotteryCPM`."""
struct LotteryWorkspace{S, N, O, R, A, J, P, C, X, D, M, T, K}
    sites::S
    neighbor_indices::N
    neighbor_offsets::O
    round_order::R
    attempts::A
    tickets::J
    priorities::P
    selected::C
    transactions::X
    dispositions::D
    cell_max_priority::M
    cell_min_identity::T
    accounting::K
    round_count::UInt32
end

const _LOTTERY_ACCOUNTING_FIELDS = 9
const _LOTTERY_ACTIVATED = 1
const _LOTTERY_REALIZED = 2
const _LOTTERY_SAME_OWNER = 3
const _LOTTERY_BOUNDARY = 4
const _LOTTERY_IMMUTABLE = 5
const _LOTTERY_CONFLICT = 6
const _LOTTERY_CONSTRAINT_REJECTION = 7
const _LOTTERY_ACCEPTANCE_REJECTION = 8
const _LOTTERY_ACCEPTED = 9

function _validate_lottery_components(components, state, moment_tracker)
    isempty(components.constraints) || throw(ArgumentError(
        "LotteryCPM does not yet qualify hard constraints; use SequentialCPM"))
    moment_tracker === nothing || throw(ArgumentError(
        "LotteryCPM does not yet qualify moment-dependent components"))
    state.trackers.moments isa NoMomentStorage || throw(ArgumentError(
        "LotteryCPM requires state compiled without moment storage"))
    return map(component -> _qualified_snapshot_access(component, "LotteryCPM"),
        (components.energies..., components.drives..., components.kinetic_modifiers...,
            components.mechanics...))
end

algorithm_component_compatibility(::LotteryCPM,
    components::ScientificComponentSet, moment_tracker = nothing) =
    _parallel_component_compatibility("LotteryCPM", components, moment_tracker)

function _allocate_lottery_workspace(state, proposal_relation, accesses, plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        synchronize_observation!(plan)
        record_transfer!(plan, :device_to_host)
    end
    relations = _compiled_conflict_relations(state, proposal_relation, accesses)
    host_sites, host_neighbors, host_neighbor_offsets, maximum_degree =
        _realized_conflict_graph(state.domain, relations)
    round_count = maximum_degree + 1
    round_count <= typemax(UInt8) || throw(ArgumentError(
        "LotteryCPM realized conflict degree exceeds the v1 subround domain"))
    prototype = state.potts.storage.active
    site_count = length(host_sites)
    sites = _record_checkerboard_array!(plan, _device_copy(prototype, host_sites))
    neighbors = _record_checkerboard_array!(plan,
        _device_copy(prototype, host_neighbors))
    neighbor_offsets = _record_checkerboard_array!(plan,
        _device_copy(prototype, host_neighbor_offsets))
    order = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, round_count))
    attempts = _record_checkerboard_array!(plan,
        similar(prototype, CopyAttempt, site_count))
    tickets = _record_checkerboard_array!(plan,
        similar(prototype, NTuple{4, UInt32}, site_count))
    priorities = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, site_count))
    selected = _record_checkerboard_array!(plan,
        similar(prototype, UInt8, site_count))
    boundary_type = eltype(state.trackers.boundary_measures)
    transaction_type = StagedCopyTransaction{boundary_type, NoMomentDelta}
    transactions = _record_checkerboard_array!(plan,
        similar(prototype, transaction_type, site_count))
    dispositions = _record_checkerboard_array!(plan,
        similar(prototype, UInt8, site_count))
    cell_max_priority = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, length(state.potts.storage.active)))
    cell_min_identity = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, length(state.potts.storage.active)))
    accounting = _record_checkerboard_array!(plan,
        similar(prototype, UInt32, _LOTTERY_ACCOUNTING_FIELDS * site_count))
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :host_to_device)
    end
    return LotteryWorkspace(sites, neighbors, neighbor_offsets, order, attempts,
        tickets, priorities, selected, transactions, dispositions, cell_max_priority,
        cell_min_identity, accounting, UInt32(round_count))
end

function init_scientific(state::CompiledScientificState,
        proposal_relation::StaticCartesianRelation{<:ProposalRole},
        components::ScientificComponentSet, algorithm::LotteryCPM;
        seed::Integer = 0, rng::AbstractRNGContract = Philox4x32x10V1(),
        plan::ExecutionPlan = _default_execution_plan(state), moment_tracker = nothing,
        connectivity_workspace = nothing, lifecycle = NoCompiledLifecycle(),
        initialize_mechanics::Bool = true)
    connectivity_workspace === nothing || throw(ArgumentError(
        "LotteryCPM owns its conflict workspace; connectivity workspace is unsupported"))
    _validate_scientific_initialization(
        state, proposal_relation, components, algorithm, seed, rng, plan)
    accesses = _validate_lottery_components(components, state, moment_tracker)
    _validate_zero_temperature(algorithm, components)
    workspace = _allocate_lottery_workspace(state, proposal_relation, accesses, plan)
    report_storage = similar(state.potts.storage.active, UInt64,
        _SEQUENTIAL_REPORT_FIELDS)
    _record_checkerboard_array!(plan, report_storage)
    integrator = ScientificPottsIntegrator(state, components, proposal_relation, algorithm, rng,
        plan, NoConnectivityWorkspace(), nothing, workspace, lifecycle, report_storage,
        UInt64(seed), UInt64(0))
    return initialize_mechanics ? _initialize_mechanics!(integrator) : integrator
end

@inline function _lottery_address(stream, mcs, round, site;
        operation = UInt16(0), draw = UInt16(0))
    return _rng_address_unchecked(stream, mcs,
        Base.unsafe_trunc(UInt8, round - UInt32(1)), operation, SiteEntity,
        site, UInt64(0), UInt8(0), draw)
end

@kernel function _lottery_round_order!(order, rng, seed, mcs, round_count)
    index = @index(Global, Linear)
    @inbounds if index == 1
        count = Int(round_count)
        for round in 1:count
            order[round] = Base.unsafe_trunc(UInt32, round)
        end
        for round in count:-1:2
            draw = Base.unsafe_trunc(UInt16, count - round)
            address = _rng_address_unchecked(LotteryActivationStream, mcs, UInt8(0),
                UInt16(1), GlobalEntity, UInt32(0), UInt64(0), UInt8(0), draw)
            selected = Int(bounded_uint(
                rng, seed, address, Base.unsafe_trunc(UInt32, round))) + 1
            order[round], order[selected] = order[selected], order[round]
        end
    end
end

@kernel function _lottery_clear_accounting!(accounting)
    index = @index(Global, Linear)
    @inbounds accounting[index] = UInt32(0)
end

@inline function _lottery_count!(accounting, site_count, category, site_index)
    index = (category - 1) * site_count + site_index
    @inbounds accounting[index] += UInt32(1)
    return nothing
end

@kernel function _lottery_priorities!(sites, round_order, tickets, priorities, rng, seed,
        mcs, ordinal)
    site_index = @index(Global, Linear)
    if site_index <= length(sites)
        site = @inbounds sites[site_index]
        round = @inbounds round_order[Int(ordinal)]
        address = _lottery_address(LotteryPriorityStream, mcs, round, site)
        ticket = rng_words(rng, seed, address)
        @inbounds begin
            tickets[site_index] = ticket
            priorities[site_index] = ticket[1]
        end
    end
end

@inline function _lottery_ticket_is_better(left, right, left_site, right_site)
    left[1] != right[1] && return left[1] > right[1]
    left[2] != right[2] && return left[2] > right[2]
    left[3] != right[3] && return left[3] > right[3]
    left[4] != right[4] && return left[4] > right[4]
    # Philox is bijective over the complete counter block, so distinct semantic site
    # addresses cannot reach this fallback. It remains canonical defensive behavior.
    return left_site < right_site
end

@kernel function _lottery_candidates!(sites, neighbor_indices, neighbor_offsets,
        round_order, attempts, tickets, selected, dispositions, accounting,
        state, relation, proposal_process, rng, seed, mcs, ordinal, round_count)
    site_index = @index(Global, Linear)
    if site_index <= length(sites)
        site = @inbounds sites[site_index]
        round = @inbounds round_order[Int(ordinal)]
        first_neighbor = @inbounds neighbor_offsets[site_index]
        stop_neighbor = @inbounds neighbor_offsets[site_index + 1]
        degree = stop_neighbor - first_neighbor
        activation_address = _lottery_address(
            LotteryActivationStream, mcs, round, site)
        eligible = bounded_uint(rng, seed, activation_address, round_count) <
                   degree + UInt32(1)
        ticket = @inbounds tickets[site_index]
        wins = true
        neighbor_index = first_neighbor
        while neighbor_index < stop_neighbor
            neighbor_position = @inbounds neighbor_indices[Int(neighbor_index)]
            neighbor_site = @inbounds sites[Int(neighbor_position)]
            neighbor_ticket = @inbounds tickets[Int(neighbor_position)]
            if _lottery_ticket_is_better(
                    neighbor_ticket, ticket, neighbor_site, site)
                wins = false
            end
            neighbor_index += UInt32(1)
        end
        @inbounds begin
            selected[site_index] = UInt8(0)
            dispositions[site_index] = _CHECKERBOARD_PENDING
        end
        if eligible && wins
            _lottery_count!(accounting, length(sites), _LOTTERY_ACTIVATED, site_index)
            direction_address = _lottery_address(
                ProposalDirectionStream, mcs, round, site)
            direction = bounded_uint(rng, seed, direction_address,
                UInt32(direction_count(relation))) + UInt32(1)
            attempt = construct_proposal_attempt(proposal_process,
                state, state.domain, relation, Int(site), direction, mcs,
                (UInt64(round) << 32) | UInt64(site))
            @inbounds attempts[site_index] = attempt
            if attempt.outcome === ActionableCopy
                _lottery_count!(accounting, length(sites), _LOTTERY_REALIZED, site_index)
                @inbounds selected[site_index] = UInt8(1)
            elseif attempt.outcome === SameOwnerAttempt
                _lottery_count!(accounting, length(sites), _LOTTERY_SAME_OWNER, site_index)
            elseif attempt.outcome === BoundaryNullAttempt
                _lottery_count!(accounting, length(sites), _LOTTERY_BOUNDARY, site_index)
            else
                _lottery_count!(accounting, length(sites), _LOTTERY_IMMUTABLE, site_index)
            end
        end
    end
end

@kernel function _lottery_claim_priorities!(attempts, priorities, selected,
        cell_max_priority)
    site_index = @index(Global, Linear)
    if @inbounds(selected[site_index] != 0)
        attempt = @inbounds attempts[site_index]
        priority = @inbounds priorities[site_index]
        _claim_cell_priority!(cell_max_priority, attempt.losing, priority)
        _claim_cell_priority!(cell_max_priority, attempt.gaining, priority)
    end
end

@kernel function _lottery_claim_ties!(attempts, priorities, selected,
        cell_max_priority, cell_min_identity)
    site_index = @index(Global, Linear)
    if @inbounds(selected[site_index] != 0)
        attempt = @inbounds attempts[site_index]
        priority = @inbounds priorities[site_index]
        identity = attempt.recipient
        _claim_cell_identity!(cell_max_priority, cell_min_identity,
            attempt.losing, priority, identity)
        _claim_cell_identity!(cell_max_priority, cell_min_identity,
            attempt.gaining, priority, identity)
    end
end

@kernel function _lottery_select_conflicts!(attempts, priorities, selected,
        dispositions, cell_max_priority, cell_min_identity, accounting)
    site_index = @index(Global, Linear)
    if @inbounds(selected[site_index] != 0)
        attempt = @inbounds attempts[site_index]
        priority = @inbounds priorities[site_index]
        identity = attempt.recipient
        wins = _wins_cell_claim(cell_max_priority, cell_min_identity,
                   attempt.losing, priority, identity) &&
               _wins_cell_claim(cell_max_priority, cell_min_identity,
                   attempt.gaining, priority, identity)
        if !wins
            @inbounds begin
                selected[site_index] = UInt8(0)
                dispositions[site_index] = _CHECKERBOARD_CONFLICT
            end
            _lottery_count!(accounting, length(attempts), _LOTTERY_CONFLICT, site_index)
        end
    end
end

@kernel function _lottery_evaluate!(attempts, selected, transactions, dispositions,
        accounting, round_order, state, components, algorithm, rng, seed, mcs, ordinal)
    site_index = @index(Global, Linear)
    if @inbounds(selected[site_index] != 0)
        round = @inbounds round_order[Int(ordinal)]
        attempt = @inbounds attempts[site_index]
        proposal = _copy_proposal_unchecked(attempt.recipient, attempt.donor,
            attempt.losing, attempt.gaining, attempt.direction, attempt.mcs,
            attempt.semantic_id, attempt.forward_multiplicity,
            attempt.reverse_multiplicity)
        transaction = _stage_copy_transaction_unchecked(
            state, state.boundary_tracker, proposal; moment_tracker = nothing)
        @inbounds transactions[site_index] = transaction
        context = ScientificProposalContext(
            state, transaction, NoConnectivityWorkspace(), UInt32(1))
        evaluation = evaluate_copy(
            components, proposal, context, typeof(algorithm.temperature))
        if !evaluation.constraints_allowed
            @inbounds dispositions[site_index] = _CHECKERBOARD_CONSTRAINT_REJECTION
            _lottery_count!(accounting, length(attempts),
                _LOTTERY_CONSTRAINT_REJECTION, site_index)
        else
            probability = _acceptance_probability(ConventionalMetropolis(),
                _unchecked_acceptance_inputs(evaluation), algorithm.temperature)
            address = _lottery_address(
                AcceptanceStream, mcs, round, attempt.recipient)
            draw = uniform_open01(typeof(algorithm.temperature), rng, seed, address)
            if draw < probability
                @inbounds dispositions[site_index] = _CHECKERBOARD_ACCEPTED
                _lottery_count!(accounting, length(attempts),
                    _LOTTERY_ACCEPTED, site_index)
            else
                @inbounds dispositions[site_index] =
                    _CHECKERBOARD_ACCEPTANCE_REJECTION
                _lottery_count!(accounting, length(attempts),
                    _LOTTERY_ACCEPTANCE_REJECTION, site_index)
            end
        end
    end
end

@kernel function _lottery_commit!(transactions, dispositions, state)
    site_index = @index(Global, Linear)
    if @inbounds(dispositions[site_index] == _CHECKERBOARD_ACCEPTED)
        transaction = @inbounds transactions[site_index]
        _commit_checkerboard!(state, transaction)
    end
end

function _lottery_execution_kernels(plan, site_count)
    return (
        fill = _fixed_execution_kernel(plan, _checkerboard_clear_claims!),
        accounting_clear = _fixed_execution_kernel(plan, _lottery_clear_accounting!),
        candidates = _execution_kernel(plan, _lottery_candidates!, site_count),
        priorities = _execution_kernel(plan, _lottery_priorities!, site_count),
        claim_priorities = _execution_kernel(
            plan, _lottery_claim_priorities!, site_count),
        claim_ties = _execution_kernel(plan, _lottery_claim_ties!, site_count),
        select_conflicts = _execution_kernel(
            plan, _lottery_select_conflicts!, site_count),
        evaluate = _execution_kernel(plan, _lottery_evaluate!, site_count),
        commit = _execution_kernel(plan, _lottery_commit!, site_count),
    )
end

function _perform_lottery_mcs!(integrator, next_mcs, workspace, kernels, site_count)
    T = typeof(integrator.algorithm.temperature)
    half_interval = one(T) / (T(2) * T(workspace.round_count))
    for ordinal in UInt32(1):workspace.round_count
        subround = Base.unsafe_trunc(UInt8, ordinal - UInt32(1))
        _advance_mechanics!(integrator, next_mcs, subround, UInt8(0), half_interval)
        launch!(integrator.plan, kernels.fill, workspace.cell_max_priority,
            workspace.cell_min_identity;
            ndrange = length(workspace.cell_max_priority))
        launch!(integrator.plan, kernels.priorities, workspace.sites, workspace.round_order,
            workspace.tickets, workspace.priorities, integrator.rng, integrator.seed,
            next_mcs, ordinal;
            ndrange = site_count)
        launch!(integrator.plan, kernels.candidates, workspace.sites, workspace.neighbor_indices,
            workspace.neighbor_offsets, workspace.round_order, workspace.attempts,
            workspace.tickets, workspace.selected, workspace.dispositions,
            workspace.accounting, scientific_execution(integrator.state),
            integrator.proposal_relation, proposal_law(integrator.algorithm),
            integrator.rng, integrator.seed, next_mcs, ordinal,
            workspace.round_count; ndrange = site_count)
        launch!(integrator.plan, kernels.claim_priorities, workspace.attempts,
            workspace.priorities, workspace.selected, workspace.cell_max_priority;
            ndrange = site_count)
        launch!(integrator.plan, kernels.claim_ties, workspace.attempts,
            workspace.priorities, workspace.selected, workspace.cell_max_priority,
            workspace.cell_min_identity; ndrange = site_count)
        launch!(integrator.plan, kernels.select_conflicts, workspace.attempts,
            workspace.priorities, workspace.selected, workspace.dispositions,
            workspace.cell_max_priority, workspace.cell_min_identity,
            workspace.accounting; ndrange = site_count)
        launch!(integrator.plan, kernels.evaluate, workspace.attempts, workspace.selected,
            workspace.transactions, workspace.dispositions, workspace.accounting,
            workspace.round_order,
            scientific_execution(integrator.state), integrator.components,
            integrator.algorithm, integrator.rng, integrator.seed, next_mcs, ordinal;
            ndrange = site_count)
        launch!(integrator.plan, kernels.commit, workspace.transactions,
            workspace.dispositions, scientific_execution(integrator.state);
            ndrange = site_count)
        _advance_mechanics!(integrator, next_mcs, subround, UInt8(1), half_interval)
    end
    run_compiled_lifecycle!(integrator, integrator.lifecycle, next_mcs)
    integrator.mcs = next_mcs
    return integrator
end


function perform_scientific_mcs!(integrator::ScientificPottsIntegrator{S, C, R,
        <:LotteryCPM}, ::LotteryCPM) where {S, C, R}
    next_mcs = integrator.mcs + UInt64(1)
    workspace = integrator.algorithm_workspace
    site_count = length(workspace.sites)
    kernels = _lottery_execution_kernels(integrator.plan, site_count)
    launch!(integrator.plan, kernels.accounting_clear, workspace.accounting;
        ndrange = length(workspace.accounting))
    order_kernel = _lottery_round_order!(integrator.plan.backend, 1)
    launch!(integrator.plan, order_kernel, workspace.round_order, integrator.rng,
        integrator.seed, next_mcs, workspace.round_count; ndrange = 1)
    return _perform_lottery_mcs!(integrator, next_mcs, workspace, kernels, site_count)
end

function _current_mcs_report(integrator::ScientificPottsIntegrator, ::LotteryCPM)
    integrator.mcs > 0 || return nothing
    synchronize_observation!(integrator.plan)
    if !(integrator.plan.backend isa KernelAbstractions.CPU)
        record_transfer!(integrator.plan, :device_to_host)
    end
    workspace = integrator.algorithm_workspace
    accounting = Array(workspace.accounting)
    site_count = length(workspace.sites)
    total(category) = sum(UInt64,
        @view accounting[((category - 1) * site_count + 1):(category * site_count)])
    return ScientificMCSReport(integrator.mcs, UInt64(workspace.round_count),
        UInt64(site_count) * UInt64(workspace.round_count),
        total(_LOTTERY_ACTIVATED), total(_LOTTERY_REALIZED),
        total(_LOTTERY_SAME_OWNER), total(_LOTTERY_BOUNDARY),
        total(_LOTTERY_IMMUTABLE), total(_LOTTERY_CONFLICT),
        total(_LOTTERY_CONSTRAINT_REJECTION),
        total(_LOTTERY_ACCEPTANCE_REJECTION), total(_LOTTERY_ACCEPTED))
end
