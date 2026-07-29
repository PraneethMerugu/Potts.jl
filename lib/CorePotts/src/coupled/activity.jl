"""Eligibility law matching Artistoo's accepted copy into a finite cell."""
struct GainingCellCopy end
(::GainingCellCopy)(proposal, context) = is_cell_owner(proposal.gaining)

"""Geometric mean over the site itself and same-cell neighbors."""
struct GeometricActivity end

struct ActivityBounds{T}
    lower::T
    upper::T
end
(bounds::ActivityBounds)(value) = bounds.lower <= value <= bounds.upper

function canonical_state_spec(property::SiteProperty{
        <:FillSites, <:ActivityBounds})
    T = typeof(property.initial.value)
    return StateSpec(property.name;
        owner = :site,
        schema = (value_type = T, lower = property.invariant.lower,
            upper = property.invariant.upper),
        initialization = (kind = :fill, value = property.initial.value),
        lifecycle = (accepted_copy = :gaining_cell_sets_maximum,
            other_changes = :preserve_site_value),
        persistence = :checkpointed,
        adaptation = (:cpu, :metal, :rocm),
        version = property.version)
end

"""
Activity-dependent Act-CPM Hamiltonian.

The contribution is `strength * (activity(recipient) - activity(donor)) / maximum`,
with activity reduced over each site's same-cell query neighborhood.
"""
struct ActivityHamiltonian{Property, T <: AbstractFloat,
        R <: StaticCartesianRelation{<:SpatialQueryRole}} <: AbstractEnergy
    maximum::T
    strength::T
    relation::R
    reduction::GeometricActivity
end
@inline _activity_property(
    ::ActivityHamiltonian{Property}) where {Property} = Property

function ActivityHamiltonian(property::Union{Symbol, SiteProperty};
        maximum::Real, strength::Real,
        relation::StaticCartesianRelation{<:SpatialQueryRole},
        reduction::GeometricActivity = GeometricActivity(),
        version::VersionNumber = COUPLED_SEMANTIC_KERNEL_VERSION)
    version == COUPLED_SEMANTIC_KERNEL_VERSION || throw(ArgumentError(
        "ActivityHamiltonian supports only semantic-kernel version $(COUPLED_SEMANTIC_KERNEL_VERSION)"))
    maximum_value, strength_value = promote(float(maximum), float(strength))
    T = typeof(maximum_value)
    isfinite(maximum_value) && maximum_value > zero(T) ||
        throw(ArgumentError("maximum activity must be positive and finite"))
    isfinite(strength_value) && strength_value >= zero(T) ||
        throw(ArgumentError("activity strength must be finite and non-negative"))
    property_name = property isa Symbol ? property : property.name
    return ActivityHamiltonian{property_name, T, typeof(relation)}(
        maximum_value, strength_value, relation, reduction)
end

component_identity(component::ActivityHamiltonian) =
    ComponentIdentity(:activity_bias, COUPLED_SEMANTIC_KERNEL_VERSION, :energy)
component_semantic_data(component::ActivityHamiltonian) = (
    property = _activity_property(component),
    maximum = component.maximum,
    strength = component.strength,
    relation = component.relation,
    reduction = :geometric_same_cell,
)
required_relations(component::ActivityHamiltonian) = (component.relation,)
capabilities(::ActivityHamiltonian) =
    ScientificCapabilities(dimensions = (2,), portable = true)
component_supports_backend(::ActivityHamiltonian, backend::BackendCapabilities) =
    backend.family in (CPUFamily, MetalFamily, AMDGPUFamily) &&
    supports(backend, QualifiedBackendCapability()) &&
    supports(backend, FunctionalBackendCapability()) &&
    supports(backend, OrderedLaunchCapability())
scientific_access(component::ActivityHamiltonian) =
    SnapshotScientificAccess((component.relation,);
        cell_wide = true, private_workspace = true)
tiled_scientific_access(::ActivityHamiltonian) = UnsupportedTiledScientificAccess()
_non_equilibrium_energy(::ActivityHamiltonian) = true
canonical_process_law(component::ActivityHamiltonian) = component

function canonical_process_law(update::AcceptedCopyUpdate{
        <:GainingCellCopy, <:SetTo})
    return (kind = :accepted_copy_activity,
        eligibility = :gaining_cell, value = update.gained.value)
end

function canonical_process_law(process::SiteDynamics{
        <:SaturatingSubtract})
    return (kind = :saturating_subtract,
        amount = process.update.amount, lower = process.update.lower)
end

@inline function _activity_site_state(context::ScientificProposalContext,
        property::Symbol)
    workspace = context.algorithm_workspace
    workspace isa CoupledAttemptWorkspace || throw(ArgumentError(
        "ActivityHamiltonian requires the coupled accepted-copy workspace"))
    return _find_site_state(workspace.site_states, property)
end

@inline function _activity_geometric_mean(component::ActivityHamiltonian,
        site::Integer, owner::OwnerRef, context::ScientificProposalContext)
    state = _activity_site_state(context, _activity_property(component))
    scientific = context.state
    _proposal_owner_at(scientific, site) == owner || return zero(component.maximum)
    value = @inbounds state.values[site]
    iszero(value) && return zero(component.maximum)
    product = value
    count = 1
    for direction in 1:direction_count(component.relation)
        neighbor = realize_neighbor(
            scientific.domain, component.relation, site, direction)
        neighbor.kind === MutableNeighbor || continue
        _proposal_owner_at(scientific, neighbor.site) == owner || continue
        neighbor_value = @inbounds state.values[Int(neighbor.site)]
        iszero(neighbor_value) && return zero(component.maximum)
        product *= neighbor_value
        count += 1
    end
    exponent = one(component.maximum) / convert(typeof(component.maximum), count)
    return convert(typeof(component.maximum), product^exponent)
end

@inline function energy_change(component::ActivityHamiltonian,
        proposal::CopyProposal, context::ScientificProposalContext)
    source = _activity_geometric_mean(
        component, proposal.donor, proposal.gaining, context)
    target = _activity_geometric_mean(
        component, proposal.recipient, proposal.losing, context)
    return component.strength * (target - source) / component.maximum
end

@inline proposal_energy_change(component::ActivityHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context)

"""
Complete reusable Act mechanism. `semantic_model` is authoritative; the remaining fields are
compiled CPU-reference realizations of its state and process laws.
"""
struct ActivityProgram{T, U, D, H, M <: SemanticModel}
    property::T
    accepted_copy::U
    decay::D
    hamiltonian::H
    semantic_model::M
end

function ActivityProgram(; maximum::Real, strength::Real,
        relation::StaticCartesianRelation{<:SpatialQueryRole},
        algorithm::AbstractSequentialCPMAlgorithm,
        observation_cadence::Integer = 1)
    algorithm isa SequentialEquilibrium && throw(ArgumentError(
        "Act is non-equilibrium and cannot use SequentialEquilibrium"))
    observation_cadence > 0 ||
        throw(ArgumentError("activity observation cadence must be positive"))
    maximum_value, strength_value = promote(float(maximum), float(strength))
    T = typeof(maximum_value)
    property = SiteProperty(:activity; initial = zero(T),
        invariant = ActivityBounds(zero(T), maximum_value),
        ownership = AcceptedCopyManaged(),
        version = COUPLED_SEMANTIC_KERNEL_VERSION)
    accepted_copy = AcceptedCopyUpdate(
        :activity_on_accept, property;
        when = GainingCellCopy(), gained = SetTo(maximum_value),
        version = COUPLED_SEMANTIC_KERNEL_VERSION)
    decay = SiteDynamics(:activity_decay, property;
        update = SaturatingSubtract(one(T); lower = zero(T)),
        schedule = EveryMCS(),
        version = COUPLED_SEMANTIC_KERNEL_VERSION)
    hamiltonian = ActivityHamiltonian(property;
        maximum = maximum_value, strength = strength_value,
        relation = relation)

    state_spec = StateSpec(:activity;
        owner = :site,
        schema = (value_type = T, lower = zero(T), upper = maximum_value),
        initialization = (kind = :fill, value = zero(T)),
        lifecycle = (accepted_copy = :gaining_cell_sets_maximum,
            other_changes = :preserve_site_value),
        persistence = :checkpointed,
        adaptation = (:cpu, :metal, :rocm))
    accepted_spec = ProcessSpec(:activity_on_accept;
        reads = (:activity,), writes = (:activity,),
        law = (kind = :accepted_copy_activity,
            eligibility = :gaining_cell, value = maximum_value),
        snapshot = :accepted_copy, commit = :accepted_copy_transaction)
    bias_spec = ProcessSpec(:activity_bias;
        reads = (:activity,), writes = (),
        law = hamiltonian, snapshot = :accepted_copy, commit = :read_only)
    decay_spec = ProcessSpec(:activity_decay;
        reads = (:activity,), writes = (:activity,),
        law = (kind = :saturating_subtract,
            amount = one(T), lower = zero(T)),
        snapshot = :process_entry, commit = :atomic_synchronous)
    plan_spec = PlanSpec((
        PlanEntrySpec(:potts, :potts; target = :potts,
            snapshot = :accepted_copy, commit = :ordered_sequential),
        PlanEntrySpec(:activity_decay, :process; target = :activity_decay,
            snapshot = :process_entry, commit = :atomic_synchronous),
        PlanEntrySpec(:lifecycle, :lifecycle;
            snapshot = :completed_process, commit = :atomic_synchronous),
        PlanEntrySpec(:activity_observation, :observation;
            cadence = observation_cadence, snapshot = :completed_mcs,
            commit = :read_only),
        PlanEntrySpec(:completed_mcs, :stable_boundary;
            snapshot = :completed_mcs, commit = :read_only),
    ))
    observation = ObservationSpec(:activity_summary;
        inputs = (:activity,),
        transform = (kind = :activity_summary,
            values = (:active_site_count, :mean_activity)),
        cadence = observation_cadence)
    roles = SpatialRoles(query = relation)
    model = SemanticModel((state_spec,),
        (accepted_spec, bias_spec, decay_spec), plan_spec;
        lifecycle = LifecycleSpec(),
        observations = (observation,),
        spatial_roles = roles,
        algorithm)
    return ActivityProgram(property, accepted_copy, decay, hamiltonian, model)
end

canonical_coupled_model(program::ActivityProgram) = program.semantic_model

struct ActivitySummary{C <: AbstractVector{UInt64}, T <: AbstractVector}
    property::Symbol
    active_count::C
    total::T
    version::VersionNumber
end
function ActivitySummary(property::Symbol, values::AbstractArray,
        version::VersionNumber)
    active_count = similar(values, UInt64, 1)
    total = similar(values, eltype(values), 1)
    fill!(active_count, UInt64(0))
    fill!(total, zero(eltype(values)))
    return ActivitySummary(property, active_count, total, version)
end
component_identity(summary::ActivitySummary) =
    ComponentIdentity(:activity_summary, summary.version, :observation)
component_semantic_data(summary::ActivitySummary) = (property = summary.property,)
canonical_observation_transform(::ActivitySummary) = (
    kind = :activity_summary,
    values = (:active_site_count, :mean_activity))
function (summary::ActivitySummary)(coupled, potts, mcs)
    state = _state_by_name(coupled.site_states, summary.property)
    active_count = count(!iszero, state.values)
    total = sum(state.values)
    mean_activity = iszero(active_count) ?
        zero(eltype(state.values)) : total / active_count
    return (
        active_site_count = active_count,
        mean_activity,
        completed_mcs = UInt64(mcs),
    )
end

@kernel function _activity_summary_kernel!(active_count, total, values)
    index = @index(Global, Linear)
    @inbounds if index == 1
        count = UInt64(0)
        sum_value = zero(eltype(values))
        for site in eachindex(values)
            value = values[site]
            if !iszero(value)
                count += UInt64(1)
                sum_value += value
            end
        end
        active_count[1] = count
        total[1] = sum_value
    end
end

"""
Realize an `ActivityProgram` against an ownership lattice. All returned execution objects are
derived from the program's canonical semantic model.
"""
function realize_activity(program::ActivityProgram, ownership::AbstractArray)
    site_state = initialize_site_property(program.property, ownership)
    workspace = CoupledAttemptWorkspace(
        (site_state,), (program.accepted_copy,))
    cadence = only(program.semantic_model.observations).cadence
    schedule = cadence == 1 ? EveryMCS() :
        PeriodicMCS(cadence, cadence)
    summary = ActivitySummary(
        program.property.name, site_state.values,
        COUPLED_SEMANTIC_KERNEL_VERSION)
    observation = PhaseObservation(:activity_summary, summary;
        schedule,
        schema = RecordSchema(:activity_summary, v"1.0.0"),
        failure = RequiredObservation(),
        version = COUPLED_SEMANTIC_KERNEL_VERSION)
    plan = MCSPlan(
        PottsAttempts(on_accept = (program.accepted_copy,)),
        CoupledPhase(:activity_decay, Update(program.decay)),
        LifecyclePhase(),
        ObservationPhase(observation))
    return (
        state = site_state,
        workspace,
        coupled_state = CoupledState(site_states = (site_state,)),
        plan,
        observation,
    )
end

"""
Realize Act state directly beside an already compiled scientific state.

`similar` allocation against the compiled ownership tags preserves an existing CPU, Metal, or ROCm
backend and the lattice-site cardinality, and therefore performs no adaptation or host-to-device
copy.
"""
realize_activity(program::ActivityProgram, state::CompiledScientificState) =
    realize_activity(program, state.potts.storage.ownership.tags)
