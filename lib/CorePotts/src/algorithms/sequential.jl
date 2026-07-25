"""Open family for ordered one-proposal-at-a-time scientific algorithms."""
abstract type AbstractSequentialCPMAlgorithm <: AbstractPottsAlgorithm end

"""Positive integer source-defined copy-attempt multiplier."""
struct AttemptsPerSite
    multiplier::UInt32

    function AttemptsPerSite(multiplier::Integer)
        0 < multiplier <= typemax(UInt32) || throw(ArgumentError(
            "attempts-per-site multiplier must be positive and fit UInt32"))
        return new(UInt32(multiplier))
    end
end

Base.Int(budget::AttemptsPerSite) = Int(budget.multiplier)

"""
CPU-reference sequential CPM whose public MCS contains exactly `budget.multiplier * N`
ordered attempts for `N` mutable recipient sites.
"""
struct BudgetedSequentialCPM{T <: AbstractFloat} <: AbstractSequentialCPMAlgorithm
    temperature::T
    budget::AttemptsPerSite

    function BudgetedSequentialCPM(temperature::T,
            budget::AttemptsPerSite) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "budgeted sequential CPM temperature must be finite and non-negative"))
        return new{T}(temperature, budget)
    end
end

function BudgetedSequentialCPM(budget::AttemptsPerSite;
        temperature::AbstractFloat = 20.0f0, proposal = nothing)
    if proposal !== nothing
        proposal isa SequentialReference || throw(ArgumentError(
            "the initial BudgetedSequentialCPM contract accepts only SequentialReference proposal semantics"))
        temperature = proposal.temperature
    end
    return BudgetedSequentialCPM(temperature, budget)
end

BudgetedSequentialCPM(; budget::AttemptsPerSite = AttemptsPerSite(1),
    temperature::AbstractFloat = 20.0f0, proposal = nothing) =
    BudgetedSequentialCPM(budget; temperature, proposal)

"""Conventional modified-Metropolis CPM with exactly `N` selections per MCS."""
struct SequentialCPM{T <: AbstractFloat} <: AbstractSequentialCPMAlgorithm
    temperature::T

    function SequentialCPM(temperature::T) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "sequential CPM temperature must be finite and non-negative"))
        return new{T}(temperature)
    end
end

SequentialCPM(; temperature::AbstractFloat = 20.0f0) = SequentialCPM(temperature)

"""Metropolis-Hastings sequential sampler for capability-qualified equilibrium models."""
struct SequentialEquilibrium{T <: AbstractFloat} <: AbstractSequentialCPMAlgorithm
    temperature::T

    function SequentialEquilibrium(temperature::T) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "sequential equilibrium temperature must be finite and non-negative"))
        return new{T}(temperature)
    end
end

SequentialEquilibrium(; temperature::AbstractFloat = 20.0f0) =
    SequentialEquilibrium(temperature)

"""Parallel color-sweep CPM with snapshot evaluation and deterministic conflicts."""
struct CheckerboardSweepCPM{T <: AbstractFloat} <: AbstractPottsAlgorithm
    temperature::T

    function CheckerboardSweepCPM(temperature::T) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "checkerboard CPM temperature must be finite and non-negative"))
        return new{T}(temperature)
    end
end

CheckerboardSweepCPM(; temperature::AbstractFloat = 20.0f0) =
    CheckerboardSweepCPM(temperature)

"""Topology-calibrated parallel lottery CPM with equal per-site expected activation."""
struct LotteryCPM{T <: AbstractFloat} <: AbstractPottsAlgorithm
    temperature::T

    function LotteryCPM(temperature::T) where {T <: AbstractFloat}
        isfinite(temperature) && temperature >= zero(T) || throw(ArgumentError(
            "lottery CPM temperature must be finite and non-negative"))
        return new{T}(temperature)
    end
end

LotteryCPM(; temperature::AbstractFloat = 20.0f0) = LotteryCPM(temperature)

component_identity(::SequentialCPM) =
    ComponentIdentity(:sequential_cpm, SEQUENTIAL_ALGORITHM_CONTRACT_VERSION, :algorithm)
component_identity(::BudgetedSequentialCPM) = ComponentIdentity(
    :budgeted_sequential_cpm, BUDGETED_SEQUENTIAL_ALGORITHM_CONTRACT_VERSION, :algorithm)
component_identity(::SequentialEquilibrium) =
    ComponentIdentity(
        :sequential_equilibrium, SEQUENTIAL_ALGORITHM_CONTRACT_VERSION, :algorithm)
component_identity(::CheckerboardSweepCPM) =
    ComponentIdentity(
        :checkerboard_sweep_cpm, CHECKERBOARD_SCHEDULER_CONTRACT_VERSION, :algorithm)
component_identity(::LotteryCPM) =
    ComponentIdentity(:lottery_cpm, LOTTERY_ALGORITHM_CONTRACT_VERSION, :algorithm)

algorithm_guarantees(::SequentialCPM) = AlgorithmGuaranteeProfile(
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
    reproducibility_scope = :strict_same_backend_run,
    compatible_component_scopes = (
        supported = (:energy, :drive, :hard_constraint, :kinetic_modifier,
            :mechanical, :moment_focal),
        rejected = (),
    ),
    validation_evidence = (:exact_accounting, :strict_replay,
        :tracker_reconstruction, :backend_conformance_matrix),
    backend_contract = (:cpu, :metal, :amdgpu),
    dimensions = (2, 3),
    guarantee_label = :unqualified,
    qualified_domain = (
        transition = (
            registration = :phase13_transition_evidence_v2,
            model = :adhesion_volume,
            real_type = :float32,
            backends = (:cpu, :metal, :amdgpu),
        ),
        realistic = (
            registration = :phase13_realistic_qualification_v4,
            role = :cpu_reference,
            workloads = (:adhesion_volume_relaxation,
                :differential_adhesion_sorting, :single_cell_migration),
            backends = (:cpu,),
        ),
    ),
    maximum_observed_discrepancy = 0.0,
    tested_backends = (:cpu, :metal, :amdgpu),
    evidence_version = PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION,
    api_status = :stable,
    paper_scope = :phase13_core,
)

algorithm_guarantees(algorithm::BudgetedSequentialCPM) = AlgorithmGuaranteeProfile(
    proposal_process = (
        recipient = :uniform_with_replacement,
        donor = :uniform_direction_with_boundary_no_ops,
    ),
    equilibrium_status = :not_claimed,
    kinetic_interpretation = :source_budgeted_sequential_cpm,
    transaction_semantics = (
        snapshot = :ordered_current_state,
        conflicts = :not_applicable,
        commit = :immediate_serial,
    ),
    mcs_normalization = (
        kind = :exact_integer_attempts_per_site,
        multiplier = algorithm.budget.multiplier,
    ),
    reproducibility_scope = :strict_same_backend_exact_continuation,
    compatible_component_scopes = (
        supported = (:energy, :drive, :hard_constraint, :kinetic_modifier,
            :mechanical, :moment_focal),
        rejected = (),
    ),
    validation_evidence = (:exact_budget_accounting, :strict_replay,
        :checkpoint_continuation, :wortel_gpu_native_qualification),
    backend_contract = (:cpu, :metal, :amdgpu),
    dimensions = (2, 3),
    guarantee_label = :unqualified,
    qualified_domain = (
        implementation = :ordered_backend_resident_device_chain,
        multiplier = algorithm.budget.multiplier,
        real_type = :float32,
        backends = (:cpu, :metal, :amdgpu),
    ),
    maximum_observed_discrepancy = 0.0,
    tested_backends = (:cpu, :metal, :amdgpu),
    evidence_version = PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION,
    api_status = :stable,
    paper_scope = :later_protocol_consumer,
)

algorithm_guarantees(::SequentialEquilibrium) = AlgorithmGuaranteeProfile(
    proposal_process = (
        recipient = :uniform_with_replacement,
        donor = :uniform_direction_with_boundary_no_ops,
        acceptance = :metropolis_hastings,
    ),
    equilibrium_status = :qualified_reversible_models,
    kinetic_interpretation = :sequential_metropolis_hastings,
    transaction_semantics = (
        snapshot = :ordered_current_state,
        conflicts = :not_applicable,
        commit = :immediate_serial,
    ),
    mcs_normalization = :exact_n_independent_attempts,
    reproducibility_scope = :strict_same_backend_run,
    compatible_component_scopes = (
        supported = (:conservative_energy, :hard_constraint, :moment_focal),
        rejected = (:drive, :kinetic_modifier, :mechanical),
    ),
    validation_evidence = (:proposal_probability_fixtures, :hastings_fixtures,
        :exact_accounting, :strict_replay),
    backend_contract = (:cpu, :metal, :amdgpu),
    dimensions = (2, 3),
    api_status = :experimental,
    paper_scope = :not_admitted,
)

algorithm_guarantees(::CheckerboardSweepCPM) = AlgorithmGuaranteeProfile(
    proposal_process = (
        recipient = :realized_graph_coloring_without_replacement,
        color_order = :semantic_random_permutation_once_per_mcs,
        donor = :uniform_direction_with_boundary_no_ops,
    ),
    equilibrium_status = :not_claimed,
    kinetic_interpretation = :parallel_color_sweep_cpm,
    transaction_semantics = (
        snapshot = :common_per_color,
        conflicts = :deterministic_semantic_priority,
        commit = :conflict_free_parallel_subset,
    ),
    mcs_normalization = :exact_once_per_mutable_site,
    reproducibility_scope = :strict_same_backend_run,
    compatible_component_scopes = (
        supported = (:snapshot_energy, :snapshot_drive, :snapshot_kinetic_modifier,
            :mechanical),
        rejected = (:hard_constraint, :private_workspace, :moment_focal),
    ),
    validation_evidence = (:realized_coloring_validation, :exact_sweep_accounting,
        :deterministic_conflict_fixtures, :strict_replay,
        :tracker_reconstruction, :backend_conformance_matrix),
    backend_contract = (:cpu, :metal, :amdgpu),
    dimensions = (2, 3),
    guarantee_label = :unqualified,
    qualified_domain = (
        transition = (
            registration = :phase13_transition_evidence_v2,
            model = :adhesion_volume,
            real_type = :float32,
            backends = (:cpu, :metal, :amdgpu),
        ),
        realistic = (
            registration = :phase13_realistic_qualification_v4,
            workloads = (:adhesion_volume_relaxation,
                :differential_adhesion_sorting, :single_cell_migration),
            backends = (:cpu, :metal, :amdgpu),
        ),
    ),
    maximum_observed_discrepancy = 0.5625,
    tested_backends = (:cpu, :metal, :amdgpu),
    evidence_version = PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION,
    api_status = :stable,
    paper_scope = :phase13_core,
)

algorithm_guarantees(::LotteryCPM) = AlgorithmGuaranteeProfile(
    proposal_process = (
        recipient = :topology_calibrated_local_priority_lottery,
        rounds = :realized_maximum_degree_plus_one,
        order = :semantic_random_permutation_once_per_mcs,
        donor = :uniform_direction_with_boundary_no_ops,
    ),
    equilibrium_status = :not_claimed,
    kinetic_interpretation = :parallel_lottery_cpm,
    transaction_semantics = (
        snapshot = :common_per_round,
        conflicts = :deterministic_semantic_priority,
        commit = :conflict_free_parallel_subset,
    ),
    mcs_normalization = :one_activation_per_mutable_site_in_expectation,
    reproducibility_scope = :strict_same_backend_run,
    compatible_component_scopes = (
        supported = (:snapshot_energy, :snapshot_drive, :snapshot_kinetic_modifier,
            :mechanical),
        rejected = (:hard_constraint, :private_workspace, :moment_focal),
    ),
    validation_evidence = (:topology_calibration_proof, :boundary_class_statistics,
        :waiting_time_statistics, :neighbor_covariance_statistics,
        :deterministic_conflict_fixtures, :strict_replay,
        :tracker_reconstruction, :backend_conformance_matrix),
    backend_contract = (:cpu, :metal, :amdgpu),
    dimensions = (2, 3),
    api_status = :limited,
    paper_scope = :later_protocol_consumer,
)

function algorithm_component_compatibility(::SequentialEquilibrium,
        components::ScientificComponentSet, moment_tracker = nothing)
    messages = _scientific_interface_messages(components)
    any(_non_equilibrium_energy, components.energies) &&
        (messages = (messages...,
            "SequentialEquilibrium rejects non-equilibrium energy components",))
    isempty(components.drives) || (messages = (messages...,
        "SequentialEquilibrium rejects nonconservative drive components",))
    isempty(components.kinetic_modifiers) || (messages = (messages...,
        "SequentialEquilibrium rejects kinetic modifier components",))
    isempty(components.mechanics) || (messages = (messages...,
        "SequentialEquilibrium rejects mechanical components",))
    return messages
end

_non_equilibrium_energy(::Any) = false

@inline acceptance_law(::SequentialCPM) = ConventionalMetropolis()
@inline acceptance_law(::BudgetedSequentialCPM) = ConventionalMetropolis()
@inline acceptance_law(::SequentialEquilibrium) = MetropolisHastings()

"""Accounting for one completed normalized MCS."""
struct ScientificMCSReport
    mcs::UInt64
    internal_rounds::UInt64
    scheduler_candidates::UInt64
    activated_attempts::UInt64
    realized_proposals::UInt64
    same_owner_no_ops::UInt64
    boundary_no_ops::UInt64
    immutable_recipient_no_ops::UInt64
    dynamic_conflicts::UInt64
    constraint_rejections::UInt64
    acceptance_rejections::UInt64
    accepted_copies::UInt64
end

const _SEQUENTIAL_REPORT_FIELDS = fieldcount(ScientificMCSReport)

struct NoAlgorithmWorkspace end

mutable struct ScientificPottsIntegrator{S <: CompiledScientificState,
        C <: ScientificComponentSet, R <: StaticCartesianRelation{<:ProposalRole},
        A <: AbstractPottsAlgorithm,
        G <: AbstractRNGContract, P <: ExecutionPlan, W, M, Q, L,
        B <: AbstractVector{UInt64}}
    state::S
    components::C
    proposal_relation::R
    algorithm::A
    rng::G
    plan::P
    connectivity_workspace::W
    moment_tracker::M
    algorithm_workspace::Q
    lifecycle::L
    report_storage::B
    seed::UInt64
    mcs::UInt64
end

"""Open initialization hook for downstream scientific algorithms."""
function initialize_scientific_algorithm(state, proposal_relation, components,
        algorithm::AbstractPottsAlgorithm; kwargs...)
    throw(MethodError(initialize_scientific_algorithm,
        (state, proposal_relation, components, algorithm)))
end

function init_scientific(state::CompiledScientificState,
        proposal_relation::StaticCartesianRelation{<:ProposalRole},
        components::ScientificComponentSet, algorithm::AbstractPottsAlgorithm; kwargs...)
    return initialize_scientific_algorithm(
        state, proposal_relation, components, algorithm; kwargs...)
end

"""Return the immutable scientific guarantee profile owned by this integrator's algorithm."""
algorithm_guarantees(integrator::ScientificPottsIntegrator) =
    algorithm_guarantees(integrator.algorithm)

function _requires_connectivity_workspace(::Tuple{})
    return false
end

function _requires_connectivity_workspace(constraints::Tuple)
    return first(constraints) isa PreserveConnectedCells ||
           _requires_connectivity_workspace(Base.tail(constraints))
end

function _allocate_connectivity_workspace(state::CompiledScientificState)
    prototype = state.potts.storage.active
    site_count = prod(state.domain.descriptor.dims)
    visited = similar(prototype, UInt32, site_count)
    queue = similar(prototype, UInt32, site_count)
    fill!(visited, UInt32(0))
    fill!(queue, UInt32(0))
    return ConnectivityWorkspace(visited, queue)
end

function _validate_sequential_components(::SequentialCPM, components)
    return components
end

function _validate_sequential_components(::BudgetedSequentialCPM, components)
    return components
end

function _validate_sequential_components(::AbstractSequentialCPMAlgorithm, components)
    return components
end

function _validate_sequential_components(::SequentialEquilibrium, components)
    any(_non_equilibrium_energy, components.energies) && throw(ArgumentError(
        "SequentialEquilibrium does not admit non-equilibrium energy components"))
    isempty(components.drives) || throw(ArgumentError(
        "SequentialEquilibrium does not admit nonconservative drive components"))
    isempty(components.kinetic_modifiers) || throw(ArgumentError(
        "SequentialEquilibrium does not admit kinetic-modifier components"))
    isempty(components.mechanics) || throw(ArgumentError(
        "SequentialEquilibrium does not admit non-equilibrium mechanical components; use exact quadratic Hamiltonians"))
    return components
end

function _validate_scientific_interfaces(components::ScientificComponentSet,
        algorithm)
    foreach(validate_energy_component, components.energies)
    foreach(validate_drive_component, components.drives)
    foreach(validate_constraint_component, components.constraints)
    foreach(validate_mechanical_component, components.mechanics)
    foreach(validate_proposal_component, components.energies)
    foreach(validate_proposal_component, components.drives)
    foreach(validate_proposal_component, components.constraints)
    foreach(validate_proposal_component, components.kinetic_modifiers)
    foreach(validate_proposal_component, components.mechanics)
    validate_algorithm_component(algorithm)
    return components
end

function _validate_mechanical_components(state::CompiledScientificState,
        mechanics::Tuple)
    isempty(mechanics) && return mechanics
    instance_ids = map(component -> component.instance_id, mechanics)
    length(unique(instance_ids)) == length(instance_ids) || throw(ArgumentError(
        "mechanical component instance IDs must be unique within one model"))
    state_keys = map(component -> property_key(_mechanical_state(component)), mechanics)
    length(unique(state_keys)) == length(state_keys) || throw(ArgumentError(
        "mechanical components must own distinct state properties"))
    schema = state.potts.descriptor.property_schema
    available = property_keys(schema)
    for component in mechanics
        component isa FluctuatingSurfaceTension &&
            component.tracker_identity != state.boundary_tracker.identity &&
            throw(ArgumentError(
                "fluctuating surface tension must use the compiled boundary metric and relation"))
        for descriptor in required_properties(component).descriptors
            descriptor.key in available || throw(ArgumentError(
                "mechanical component $(typeof(component)) requires missing property `$(descriptor.key)`"))
            existing = property_descriptor(schema, descriptor.key)
            _same_property_contract(existing, descriptor) || throw(ArgumentError(
                "mechanical property `$(descriptor.key)` does not match its declared schema"))
        end
    end
    return mechanics
end

function _default_execution_plan(state::CompiledScientificState)
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    return ExecutionPlan(backend)
end

function _validate_algorithm_workspace(workspace::CoupledAttemptWorkspace,
        state::CompiledScientificState, plan::ExecutionPlan)
    storage_backend = KernelAbstractions.get_backend(state.potts.storage.active)
    for site_state in workspace.site_states
        isequal(KernelAbstractions.get_backend(site_state.values), storage_backend) ||
            throw(ArgumentError(
                "coupled attempt state must share the scientific execution backend"))
    end
    if !(plan.backend isa KernelAbstractions.CPU)
        isbitstype(typeof(workspace)) || throw(ArgumentError(
            "GPU coupled attempt workspace must lower to an isbits array tree"))
    end
    return workspace
end
_validate_algorithm_workspace(
    workspace, state::CompiledScientificState, plan::ExecutionPlan) = workspace

_contains_float64_type(::Type{Float64}) = true
function _contains_float64_type(type::Type)
    type isa DataType || return false
    return any(parameter -> parameter isa Type && _contains_float64_type(parameter),
        type.parameters)
end

function _requires_device_float64(state, proposal_relation, components, algorithm)
    return any(_contains_float64_type,
        (typeof(state), typeof(proposal_relation), typeof(components), typeof(algorithm)))
end

function _validate_scientific_initialization(state, proposal_relation, components,
        algorithm, seed, rng, plan)
    0 <= seed <= typemax(UInt64) || throw(ArgumentError(
        "scientific integrator seed must fit UInt64"))
    rng_contract_version(rng) in plan.capabilities.qualified_rng_contracts ||
        throw(UnsupportedBackendCapability(plan.capabilities.family, :semantic_rng_v1))
    _require_plan_backend(plan, state.potts.storage)
    scientific_storage_valid(state) || throw(ArgumentError(
        "compiled scientific state is not a valid single-backend array tree"))
    validate_relation_domain(state.domain, proposal_relation)
    mutable_count = length(state.domain.storage.mutable_sites)
    0 < mutable_count <= typemax(UInt32) || throw(ArgumentError(
        "scientific semantic addressing requires 1:typemax(UInt32) mutable sites"))
    if algorithm isa BudgetedSequentialCPM
        attempt_total = try
            _attempt_total(algorithm, mutable_count)
        catch error
            error isa OverflowError || rethrow()
            throw(ArgumentError("budgeted sequential attempt count overflows Int"))
        end
        attempt_total <= typemax(UInt32) || throw(ArgumentError(
            "budgeted sequential semantic addressing requires k*N <= typemax(UInt32)"))
    end
    _validate_scientific_interfaces(components, algorithm)
    for component in _all_scientific_components(components)
        component_supports_backend(component, plan.capabilities) ||
            throw(UnsupportedBackendCapability(
                plan.capabilities.family, component_identity(component).key))
    end
    _validate_mechanical_components(state, components.mechanics)
    _requires_device_float64(state, proposal_relation, components, algorithm) &&
        require_capability(plan.capabilities, DeviceFloat64Capability())
    return mutable_count
end

function _validate_zero_temperature(algorithm, components)
    if iszero(algorithm.temperature) &&
       (!isempty(components.drives) || !isempty(components.kinetic_modifiers))
        throw(ArgumentError(
            "zero-temperature execution requires no drives or kinetic modifiers"))
    end
    return algorithm
end

"""
    init_scientific(state, proposal_relation, components, algorithm; seed, plan, ...)

Construct the Phase 7 scientific integrator over already compiled, backend-resident state. The seed
is execution state rather than algorithm configuration. No simulation work or observation sync is
performed during construction.
"""
function init_scientific(state::CompiledScientificState,
        proposal_relation::StaticCartesianRelation{<:ProposalRole},
        components::ScientificComponentSet,
        algorithm::AbstractSequentialCPMAlgorithm; seed::Integer = 0,
        rng::AbstractRNGContract = Philox4x32x10V1(), plan::ExecutionPlan =
            _default_execution_plan(state), connectivity_workspace = nothing,
        moment_tracker = nothing, lifecycle = NoCompiledLifecycle(),
        initialize_mechanics::Bool = true,
        algorithm_workspace = NoAlgorithmWorkspace())
    _validate_scientific_initialization(
        state, proposal_relation, components, algorithm, seed, rng, plan)
    _validate_algorithm_workspace(algorithm_workspace, state, plan)
    _validate_sequential_components(algorithm, components)
    _validate_zero_temperature(algorithm, components)

    needs_connectivity = _requires_connectivity_workspace(components.constraints)
    workspace = if connectivity_workspace === nothing
        needs_connectivity ? _allocate_connectivity_workspace(state) :
        NoConnectivityWorkspace()
    else
        connectivity_workspace
    end
    needs_connectivity && !(workspace isa ConnectivityWorkspace) && throw(ArgumentError(
        "PreserveConnectedCells requires a ConnectivityWorkspace"))
    workspace isa ConnectivityWorkspace && validate_workspace(workspace, state)

    report_storage = similar(
        state.potts.storage.active, UInt64, _SEQUENTIAL_REPORT_FIELDS)
    domain = plan.backend isa KernelAbstractions.CPU ? :host : :device
    record_allocation!(plan, domain, _array_bytes(report_storage))
    if workspace isa ConnectivityWorkspace
        record_allocation!(plan, domain, workspace_bytes(workspace))
    end
    if algorithm_workspace isa CoupledAttemptWorkspace
        for site_state in algorithm_workspace.site_states
            record_allocation!(
                plan, domain, _array_bytes(site_state.values))
        end
    end
    integrator = ScientificPottsIntegrator(state, components, proposal_relation, algorithm, rng,
        plan, workspace, moment_tracker, algorithm_workspace, lifecycle, report_storage,
        UInt64(seed), UInt64(0))
    return initialize_mechanics ? _initialize_mechanics!(integrator) : integrator
end

function init_scientific(state::CompiledScientificState,
        proposal_relation::StaticCartesianRelation{<:ProposalRole},
        components::ScientificComponentSet; kwargs...)
    plan = get(kwargs, :plan, _default_execution_plan(state))
    if !(plan.backend isa KernelAbstractions.CPU)
        @info "SequentialCPM is the backend-independent default and will intentionally execute one ordered proposal chain. Select CheckerboardSweepCPM or LotteryCPM explicitly when their distinct dynamics are desired."
    end
    forwarded = Base.structdiff((; kwargs...), (; plan))
    return init_scientific(state, proposal_relation, components, SequentialCPM();
        plan, forwarded...)
end

@inline _algorithm_rng_operation(::AbstractSequentialCPMAlgorithm) = UInt16(0)
@inline _algorithm_rng_operation(::BudgetedSequentialCPM) = UInt16(0x1401)

@inline function _attempt_address(stream::RNGStream, mcs::UInt64,
        attempt::UInt32, algorithm::AbstractSequentialCPMAlgorithm)
    return _rng_address_unchecked(stream, mcs, UInt8(0),
        _algorithm_rng_operation(algorithm), GlobalEntity,
        attempt, UInt64(0), UInt8(0), UInt16(0))
end

@inline _attempt_total(::AbstractSequentialCPMAlgorithm, candidate_count::Int) =
    candidate_count

@inline function _attempt_total(algorithm::BudgetedSequentialCPM,
        candidate_count::Int)
    return Base.checked_mul(candidate_count, Int(algorithm.budget.multiplier))
end

@inline function _unchecked_acceptance_inputs(evaluation::ScientificCopyEvaluation{T}) where {T}
    return AcceptanceInputs{T}(evaluation.delta_h + evaluation.mechanical_work,
        evaluation.drive_log_bias,
        evaluation.kinetic_modifier, evaluation.yield_barrier,
        evaluation.forward_multiplicity, evaluation.reverse_multiplicity,
        evaluation.constraints_allowed)
end

@kernel function _sequential_mcs_kernel!(report, state, components, proposal_relation,
        algorithm, rng, seed, mcs, connectivity_workspace, moment_tracker,
        algorithm_workspace)
    kernel_index = @index(Global, Linear)
    @inbounds if kernel_index == 1
        mutable_sites = state.domain.storage.mutable_sites
        candidate_count = length(mutable_sites)
        attempt_total = _attempt_total(algorithm, candidate_count)
        direction_total = UInt32(direction_count(proposal_relation))
        realized = UInt64(0)
        same_owner = UInt64(0)
        boundary = UInt64(0)
        immutable = UInt64(0)
        constraint_rejections = UInt64(0)
        acceptance_rejections = UInt64(0)
        accepted = UInt64(0)
        proposal_process = proposal_law(algorithm)
        accepted_law = acceptance_law(algorithm)
        # init_scientific proves candidate_count fits UInt32; the loop proves each attempt ID.
        for raw_attempt in 1:attempt_total
            attempt_id = Base.unsafe_trunc(UInt32, raw_attempt)
            recipient_address = _attempt_address(
                ProposalRecipientStream, mcs, attempt_id, algorithm)
            mutable_index = bounded_uint(
                rng, seed, recipient_address,
                Base.unsafe_trunc(UInt32, candidate_count)) + UInt32(1)
            recipient = Int(@inbounds mutable_sites[Int(mutable_index)])
            direction_address = _attempt_address(
                ProposalDirectionStream, mcs, attempt_id, algorithm)
            direction = bounded_uint(rng, seed, direction_address, direction_total) + UInt32(1)
            attempt = construct_proposal_attempt(proposal_process, state, state.domain,
                proposal_relation, recipient, direction, mcs, attempt_id)
            if attempt.outcome === SameOwnerAttempt
                same_owner += UInt64(1)
                continue
            elseif attempt.outcome === BoundaryNullAttempt
                boundary += UInt64(1)
                continue
            elseif attempt.outcome === ImmutableRecipientAttempt
                immutable += UInt64(1)
                continue
            end

            realized += UInt64(1)
            proposal = actionable_proposal(attempt)
            transaction = _stage_copy_transaction_unchecked(
                state, state.boundary_tracker, proposal; moment_tracker)
            context = ScientificProposalContext(
                state, transaction, connectivity_workspace, attempt_id,
                algorithm_workspace)
            evaluation = evaluate_copy(
                components, proposal, context, typeof(algorithm.temperature))
            if !evaluation.constraints_allowed
                constraint_rejections += UInt64(1)
                continue
            end
            inputs = _unchecked_acceptance_inputs(evaluation)
            probability = _acceptance_probability(
                accepted_law, inputs, algorithm.temperature)
            acceptance_address = _attempt_address(
                AcceptanceStream, mcs, attempt_id, algorithm)
            draw = uniform_open01(
                typeof(algorithm.temperature), rng, seed, acceptance_address)
            if draw < probability
                commit_accepted_copy_updates!(
                    algorithm_workspace, proposal, transaction, state)
                _commit_staged!(state, transaction)
                accepted += UInt64(1)
            else
                acceptance_rejections += UInt64(1)
            end
        end
        @inbounds begin
            report[1] = mcs
            report[2] = UInt64(1)
            report[3] = Base.unsafe_trunc(UInt64, attempt_total)
            report[4] = Base.unsafe_trunc(UInt64, attempt_total)
            report[5] = realized
            report[6] = same_owner
            report[7] = boundary
            report[8] = immutable
            report[9] = UInt64(0)
            report[10] = constraint_rejections
            report[11] = acceptance_rejections
            report[12] = accepted
        end
    end
end

@kernel function _clear_connectivity_epochs!(workspace)
    index = @index(Global, Linear)
    @inbounds workspace.visited_epochs[index] = UInt32(0)
end

function perform_scientific_mcs!(integrator::ScientificPottsIntegrator{S, C, R, A},
        ::A) where {
        S, C, R, A <: AbstractSequentialCPMAlgorithm}
    next_mcs = integrator.mcs + UInt64(1)
    half_interval = typeof(integrator.algorithm.temperature)(0.5)
    _advance_mechanics!(integrator, next_mcs, UInt8(0), UInt8(0), half_interval)
    if integrator.connectivity_workspace isa ConnectivityWorkspace
        clear = _clear_connectivity_epochs!(
            integrator.plan.backend, integrator.plan.block_size)
        launch!(integrator.plan, clear, integrator.connectivity_workspace;
            ndrange = length(integrator.connectivity_workspace.visited_epochs))
    end
    kernel = _sequential_mcs_kernel!(integrator.plan.backend, 1)
    launch!(integrator.plan, kernel, integrator.report_storage,
        scientific_execution(integrator.state), integrator.components,
        integrator.proposal_relation, integrator.algorithm, integrator.rng,
        integrator.seed, next_mcs, integrator.connectivity_workspace,
        integrator.moment_tracker, integrator.algorithm_workspace; ndrange = 1)
    _advance_mechanics!(integrator, next_mcs, UInt8(0), UInt8(1), half_interval)
    run_compiled_lifecycle!(integrator, integrator.lifecycle, next_mcs)
    integrator.mcs = next_mcs
    return integrator
end

"""Dispatch one complete MCS through the algorithm-owned open hook."""
function SciMLBase.step!(integrator::ScientificPottsIntegrator)
    return perform_scientific_mcs!(integrator, integrator.algorithm)
end

function SciMLBase.step!(integrator::ScientificPottsIntegrator, steps::Integer)
    steps >= 0 || throw(ArgumentError("scientific step count must be non-negative"))
    for _ in 1:steps
        SciMLBase.step!(integrator)
    end
    return integrator
end

function current_mcs_report(integrator::ScientificPottsIntegrator)
    return _current_mcs_report(integrator, integrator.algorithm)
end

function _standard_current_mcs_report(integrator::ScientificPottsIntegrator)
    integrator.mcs > 0 || return nothing
    synchronize_observation!(integrator.plan)
    if !(integrator.plan.backend isa KernelAbstractions.CPU)
        record_transfer!(integrator.plan, :device_to_host)
    end
    values = Array(integrator.report_storage)
    return ScientificMCSReport(values...)
end

_current_mcs_report(integrator::ScientificPottsIntegrator, ::SequentialCPM) =
    _standard_current_mcs_report(integrator)
_current_mcs_report(integrator::ScientificPottsIntegrator, ::BudgetedSequentialCPM) =
    _standard_current_mcs_report(integrator)
_current_mcs_report(integrator::ScientificPottsIntegrator, ::SequentialEquilibrium) =
    _standard_current_mcs_report(integrator)

function logical_state(integrator::ScientificPottsIntegrator)
    return logical_snapshot(integrator.plan, integrator.state.potts)
end
