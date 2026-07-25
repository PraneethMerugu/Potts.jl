"""Typed scientific component bundle lowered once and passed unchanged to hot kernels."""
struct ScientificComponentSet{E <: Tuple, D <: Tuple, C <: Tuple, K <: Tuple, M <: Tuple}
    energies::E
    drives::D
    constraints::C
    kinetic_modifiers::K
    mechanics::M
end

function ScientificComponentSet(; energies::Tuple = (), drives::Tuple = (),
        constraints::Tuple = (), kinetic_modifiers::Tuple = (), mechanics::Tuple = ())
    all(component -> component isa AbstractEnergy, energies) || throw(ArgumentError(
        "every energy component must subtype AbstractEnergy"))
    all(component -> component isa AbstractDrive, drives) || throw(ArgumentError(
        "every drive component must subtype AbstractDrive"))
    all(component -> component isa AbstractHardConstraint, constraints) ||
        throw(ArgumentError(
            "every constraint component must subtype AbstractHardConstraint"))
    all(component -> component isa AbstractKineticModifier, kinetic_modifiers) ||
        throw(ArgumentError(
            "every kinetic modifier must subtype AbstractKineticModifier"))
    all(component -> component isa AbstractMechanicalComponent, mechanics) ||
        throw(ArgumentError(
            "every mechanical component must subtype AbstractMechanicalComponent"))
    return ScientificComponentSet(energies, drives, constraints, kinetic_modifiers, mechanics)
end

function _interface_compatibility_message(validator, component)
    try
        validator(component)
        validate_proposal_component(component)
        return nothing
    catch error
        return sprint(showerror, error)
    end
end

function _scientific_interface_messages(components::ScientificComponentSet)
    checks = (
        (validate_energy_component, components.energies),
        (validate_drive_component, components.drives),
        (validate_constraint_component, components.constraints),
        (validate_kinetic_modifier_component, components.kinetic_modifiers),
        (validate_mechanical_component, components.mechanics),
    )
    return Tuple(message for (validator, values) in checks for component in values
        for message in (_interface_compatibility_message(validator, component),)
        if message !== nothing)
end

algorithm_component_compatibility(::AbstractPottsAlgorithm,
    components::ScientificComponentSet, moment_tracker = nothing) =
    _scientific_interface_messages(components)

_all_scientific_components(components::ScientificComponentSet) = (
    components.energies..., components.drives..., components.constraints...,
    components.kinetic_modifiers..., components.mechanics...)

function Adapt.adapt_structure(to, components::ScientificComponentSet)
    adapt_tuple(values) = map(value -> Adapt.adapt(to, value), values)
    return ScientificComponentSet(
        adapt_tuple(components.energies),
        adapt_tuple(components.drives),
        adapt_tuple(components.constraints),
        adapt_tuple(components.kinetic_modifiers),
        adapt_tuple(components.mechanics)
    )
end

"""Zero-storage marker for models without an exact connectivity constraint."""
struct NoConnectivityWorkspace end

"""One immutable pre-copy view shared by every component in a proposal evaluation."""
struct ScientificProposalContext{S <: ScientificExecutionState,
    T <: StagedCopyTransaction, W, A}
    state::S
    transaction::T
    connectivity_workspace::W
    workspace_epoch::UInt32
    algorithm_workspace::A
end

function ScientificProposalContext(state::CompiledScientificState,
        transaction::StagedCopyTransaction;
        connectivity_workspace = NoConnectivityWorkspace(), workspace_epoch::Integer = 1,
        algorithm_workspace = nothing)
    return ScientificProposalContext(
        scientific_execution(state), transaction; connectivity_workspace, workspace_epoch,
        algorithm_workspace)
end

function ScientificProposalContext(state::ScientificExecutionState,
        transaction::StagedCopyTransaction;
        connectivity_workspace = NoConnectivityWorkspace(), workspace_epoch::Integer = 1,
        algorithm_workspace = nothing)
    0 < workspace_epoch <= typemax(UInt32) || throw(ArgumentError(
        "proposal workspace epoch must be positive and fit UInt32"))
    connectivity_workspace isa ConnectivityWorkspace &&
        validate_workspace(connectivity_workspace, state)
    return ScientificProposalContext(
        state, transaction, connectivity_workspace, UInt32(workspace_epoch),
        algorithm_workspace)
end

ScientificProposalContext(state::ScientificExecutionState,
        transaction::StagedCopyTransaction, connectivity_workspace,
        workspace_epoch::Integer) =
    ScientificProposalContext(state, transaction; connectivity_workspace,
        workspace_epoch)

ScientificProposalContext(state::ScientificExecutionState,
        transaction::StagedCopyTransaction, connectivity_workspace,
        workspace_epoch::Integer, algorithm_workspace) =
    ScientificProposalContext(state, transaction; connectivity_workspace,
        workspace_epoch, algorithm_workspace)

function Adapt.adapt_structure(to, context::ScientificProposalContext)
    return ScientificProposalContext(
        Adapt.adapt(to, context.state), context.transaction,
        Adapt.adapt(to, context.connectivity_workspace), context.workspace_epoch,
        Adapt.adapt(to, context.algorithm_workspace))
end

@inline proposal_energy_change(component::QuadraticVolumeHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state)
@inline proposal_energy_change(component::UnorderedContactHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state, context.state.domain)
@inline proposal_energy_change(component::QuadraticBoundaryHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state)
@inline proposal_energy_change(component::ExternalFieldOccupancyHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state, context.state.domain)
@inline proposal_energy_change(component::FocalPointSpringHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state, context.transaction)
@inline proposal_energy_change(component::QuadraticElongationHamiltonian,
    proposal::CopyProposal, context::ScientificProposalContext) =
    energy_change(component, proposal, context.state, context.transaction)

@inline proposal_drive_log_bias(component::ChemotaxisDrive,
    proposal::CopyProposal, context::ScientificProposalContext) =
    drive_log_bias(component, proposal, context.state, context.state.domain)

@inline proposal_constraint_allowed(component::PreserveConnectedCells,
    proposal::CopyProposal, context::ScientificProposalContext) =
    _proposal_constraint_allowed(component, proposal, context,
        context.connectivity_workspace)
@inline _proposal_constraint_allowed(component::PreserveConnectedCells,
    proposal::CopyProposal, context::ScientificProposalContext,
    workspace::ConnectivityWorkspace) = is_allowed(
    component, proposal, context.state, workspace,
    context.workspace_epoch)
function _proposal_constraint_allowed(component::PreserveConnectedCells,
        proposal::CopyProposal, context::ScientificProposalContext, workspace)
    throw(ArgumentError("PreserveConnectedCells requires a ConnectivityWorkspace"))
end
@inline proposal_constraint_allowed(component::FixedFocalEndpointConstraint,
    proposal::CopyProposal, context::ScientificProposalContext) =
    is_allowed(component, proposal, context.state)

@inline proposal_modifier_contribution(component::PositiveYield,
    proposal::CopyProposal, context::ScientificProposalContext) = (
    kinetic = zero(component.barrier),
    yield = kinetic_barrier(
        component, proposal, context.state))

@inline proposal_mechanical_work(component::AbstractMechanicalComponent,
    proposal::CopyProposal, context::ScientificProposalContext) = mechanical_work(
    component, proposal, context.state, context.transaction)

proposal_energy_change(component::AbstractEnergy, proposal::CopyProposal,
    context::ScientificProposalContext) = throw(ScientificInterfaceError(
        :compiled_energy, typeof(component), [:proposal_energy_change]))
proposal_drive_log_bias(component::AbstractDrive, proposal::CopyProposal,
    context::ScientificProposalContext) = throw(ScientificInterfaceError(
        :compiled_drive, typeof(component), [:proposal_drive_log_bias]))
proposal_constraint_allowed(component::AbstractHardConstraint, proposal::CopyProposal,
    context::ScientificProposalContext) = throw(ScientificInterfaceError(
        :compiled_constraint, typeof(component), [:proposal_constraint_allowed]))
proposal_modifier_contribution(component::AbstractKineticModifier, proposal::CopyProposal,
    context::ScientificProposalContext) = throw(ScientificInterfaceError(
        :compiled_modifier, typeof(component), [:proposal_modifier_contribution]))

function _has_specialized_proposal_method(function_value, component, category)
    signature = Tuple{typeof(component), CopyProposal, ScientificProposalContext}
    fallback_signature = Tuple{category, CopyProposal, ScientificProposalContext}
    return which(function_value, signature) !== which(function_value, fallback_signature)
end

function validate_proposal_component(component::AbstractEnergy)
    _has_specialized_proposal_method(proposal_energy_change, component, AbstractEnergy) ||
        throw(ScientificInterfaceError(:compiled_energy, typeof(component),
            [:proposal_energy_change]))
    return component
end


function validate_proposal_component(component::AbstractDrive)
    _has_specialized_proposal_method(proposal_drive_log_bias, component, AbstractDrive) ||
        throw(ScientificInterfaceError(:compiled_drive, typeof(component),
            [:proposal_drive_log_bias]))
    return component
end


function validate_proposal_component(component::AbstractHardConstraint)
    _has_specialized_proposal_method(
        proposal_constraint_allowed, component, AbstractHardConstraint) ||
        throw(ScientificInterfaceError(:compiled_constraint, typeof(component),
            [:proposal_constraint_allowed]))
    return component
end


function validate_proposal_component(component::AbstractKineticModifier)
    _has_specialized_proposal_method(
        proposal_modifier_contribution, component, AbstractKineticModifier) ||
        throw(ScientificInterfaceError(:compiled_modifier, typeof(component),
            [:proposal_modifier_contribution]))
    return component
end


function validate_proposal_component(component::AbstractMechanicalComponent)
    return component
end

@inline _fold_energies(::Tuple{}, proposal, context, result) = result
@inline function _fold_energies(components::Tuple, proposal, context, result)
    updated = result + proposal_energy_change(first(components), proposal, context)
    return _fold_energies(Base.tail(components), proposal, context, updated)
end

@inline _fold_drives(::Tuple{}, proposal, context, result) = result
@inline function _fold_drives(components::Tuple, proposal, context, result)
    updated = result + proposal_drive_log_bias(first(components), proposal, context)
    return _fold_drives(Base.tail(components), proposal, context, updated)
end

@inline _fold_constraints(::Tuple{}, proposal, context, result) = result
@inline function _fold_constraints(components::Tuple, proposal, context, result)
    updated = result && proposal_constraint_allowed(first(components), proposal, context)
    return _fold_constraints(Base.tail(components), proposal, context, updated)
end

@inline _fold_modifiers(::Tuple{}, proposal, context, kinetic, yield) = (kinetic, yield)
@inline function _fold_modifiers(components::Tuple, proposal, context, kinetic, yield)
    contribution = proposal_modifier_contribution(first(components), proposal, context)
    return _fold_modifiers(Base.tail(components), proposal, context,
        kinetic + contribution.kinetic, yield + contribution.yield)
end

@inline _fold_mechanics(::Tuple{}, proposal, context, result) = result
@inline function _fold_mechanics(components::Tuple, proposal, context, result)
    updated = result + proposal_mechanical_work(first(components), proposal, context)
    return _fold_mechanics(Base.tail(components), proposal, context, updated)
end

"""Category-preserving scalar result consumed by a separately selected acceptance law."""
struct ScientificCopyEvaluation{T <: AbstractFloat}
    delta_h::T
    mechanical_work::T
    drive_log_bias::T
    kinetic_modifier::T
    yield_barrier::T
    forward_multiplicity::UInt32
    reverse_multiplicity::UInt32
    constraints_allowed::Bool
end

"""Evaluate every declared component against exactly one shared pre-copy snapshot."""
@inline function evaluate_copy(components::ScientificComponentSet, proposal::CopyProposal,
        context::ScientificProposalContext, ::Type{T}) where {T <: AbstractFloat}
    delta_h = T(_fold_energies(components.energies, proposal, context, zero(T)))
    mechanical = T(_fold_mechanics(components.mechanics, proposal, context, zero(T)))
    drive_bias = T(_fold_drives(components.drives, proposal, context, zero(T)))
    constraints_allowed = _fold_constraints(
        components.constraints, proposal, context, true)
    kinetic, yield = _fold_modifiers(
        components.kinetic_modifiers, proposal, context, zero(T), zero(T))
    return ScientificCopyEvaluation(delta_h, mechanical, T(drive_bias), T(kinetic), T(yield),
        proposal.forward_multiplicity, proposal.reverse_multiplicity,
        constraints_allowed)
end

function evaluate_copy(components::ScientificComponentSet, proposal::CopyProposal,
        context::ScientificProposalContext; number_type::Type{T} = Float64) where {
        T <: AbstractFloat}
    return evaluate_copy(components, proposal, context, T)
end

function acceptance_inputs(evaluation::ScientificCopyEvaluation)
    return AcceptanceInputs(evaluation.delta_h + evaluation.mechanical_work;
        drive_log_bias = evaluation.drive_log_bias,
        kinetic_modifier = evaluation.kinetic_modifier,
        yield_barrier = evaluation.yield_barrier,
        forward_multiplicity = evaluation.forward_multiplicity,
        reverse_multiplicity = evaluation.reverse_multiplicity,
        constraints_allowed = evaluation.constraints_allowed)
end

function scientific_components_report(components::ScientificComponentSet)
    identities(values) = map(component_identity, values)
    return (
        energies = identities(components.energies),
        drives = identities(components.drives),
        constraints = identities(components.constraints),
        kinetic_modifiers = identities(components.kinetic_modifiers),
        mechanics = identities(components.mechanics)
    )
end

# These traits are host-side compiler evidence. Unknown extensions remain conservatively
# unsupported until they declare their own auditable access behavior.
scientific_access(::QuadraticVolumeHamiltonian) =
    SnapshotScientificAccess(; cell_wide = true)
scientific_access(component::UnorderedContactHamiltonian) =
    SnapshotScientificAccess((component.relation,); cell_wide = true)
scientific_access(component::QuadraticBoundaryHamiltonian) =
    SnapshotScientificAccess((component.relation,); cell_wide = true)
scientific_access(::ExternalFieldOccupancyHamiltonian) =
    SnapshotScientificAccess(; cell_wide = true)
scientific_access(::ChemotaxisDrive) =
    SnapshotScientificAccess(; cell_wide = true)
scientific_access(::PositiveYield) = SnapshotScientificAccess()
scientific_access(component::PreserveConnectedCells) =
    SnapshotScientificAccess((component.relation,);
        cell_wide = true, private_workspace = true)
scientific_access(::FluctuatingVolumePressure) =
    SnapshotScientificAccess(; cell_wide = true)
component_rng_streams(::FluctuatingVolumePressure) =
    (AuxiliaryInitializationStream, AuxiliaryEvolutionStream)
scientific_access(component::FluctuatingSurfaceTension) =
    SnapshotScientificAccess((component.relation,); cell_wide = true)

# Tile-local qualification is intentionally explicit. Unknown downstream components stay rejected
# until they declare bounded halo, scratch, and reconciliation behavior through the open protocol.
tiled_scientific_access(::QuadraticVolumeHamiltonian) =
    TiledSnapshotAccess(; cell_wide = true, scratch_words = 2)
tiled_scientific_access(component::UnorderedContactHamiltonian) =
    TiledSnapshotAccess((component.relation,); dependency_radius = 1,
        cell_wide = true, scratch_words = 2)
function tiled_scientific_access(component::QuadraticBoundaryHamiltonian)
    component.metric isa BoundaryEdgeCount || return UnsupportedTiledScientificAccess()
    return TiledSnapshotAccess((component.relation,); dependency_radius = 1,
        cell_wide = true, scratch_words = 3)
end
tiled_scientific_access(::ExternalFieldOccupancyHamiltonian) =
    TiledSnapshotAccess(; cell_wide = true)
tiled_scientific_access(::ChemotaxisDrive) =
    TiledSnapshotAccess(; cell_wide = true)
tiled_scientific_access(::PositiveYield) = TiledSnapshotAccess()
