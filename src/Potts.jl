"""
Potts provides a ModelingToolkit-compatible authoring layer for cellular
Potts models and compiles completed systems to CorePotts execution programs.
"""
module Potts

import CorePotts
import DynamicQuantities
import LocalMath
import ModelingToolkitBase
import ModelingToolkitBase: @named, @mtkcompile, mtkcompile
import PrecompileTools
import SciMLBase
import SHA
import SymbolicIndexingInterface
import Symbolics
import SciMLBase: init, solve, solve!, step!, remake, terminate!

# Public symbolic vocabulary and source-level model construction.
include("statements/statements.jl")
include("statements/statement_set.jl")
include("statements/registry.jl")
include("symbolics/bindings.jl")
include("symbolics/operations.jl")
include("symbolics/distributions.jl")
include("statements/semantics.jl")
include("statements/lifecycle.jl")

# Completion turns authored hierarchy into qualified, validated scientific
# meaning. Nothing below this boundary mutates the authored system.
include("completion/qualified_ir.jl")
include("native/policies.jl")
include("native/ports.jl")
include("native/components.jl")
include("native/scheduled_components.jl")
include("completion/diagnostics.jl")
include("systems.jl")
include("completion/source_inventory.jl")
include("completion/inference.jl")
include("completion/fingerprints.jl")
include("completion/lifecycle.jl")
include("completion/completion_data.jl")
include("completion/statement_contracts.jl")
include("completion/registered_contracts.jl")
include("completion/expansion.jl")
include("completion/qualification.jl")
include("completion/semantic_ordering.jl")
include("completion/native_completion.jl")
include("completion/completion.jl")

# Host compiler analysis freezes symbolic meaning and proves bounded resource
# requirements. The compiler README documents the required pass order.
include("compiler/host/source_graph.jl")
include("compiler/host/footprint_types.jl")
include("compiler/host/operations.jl")
include("operation_library/scientific.jl")
include("operation_library/numerics.jl")
include("compiler/host/normalized_payloads.jl")
include("compiler/host/operation_validation.jl")
include("compiler/host/operation_closure.jl")
include("compiler/host/normalization.jl")
include("compiler/host/energy_domains.jl")
include("compiler/host/footprints.jl")
include("compiler/host/lifecycle_analysis.jl")
include("compiler/host/operation_analysis.jl")
include("compiler/host/unit_analysis.jl")
include("compiler/host/term_analysis.jl")
include("completion/scheduling.jl")

# Execution-boundary values and late lowering to CorePotts.
include("compiler/execution/executable.jl")
include("compiler/execution/observations.jl")
include("compiler/execution/relationship_effects.jl")
include("operation_library/inventory.jl")
include("compiler/host/coverage.jl")
include("compiler/lowering/parameters.jl")
include("compiler/execution/manifests.jl")
include("compiler/lowering/evaluator_protocols.jl")
include("compiler/lowering/evaluator_resources.jl")
include("compiler/lowering/evaluator_nodes.jl")
include("compiler/lowering/descriptor_footprints.jl")
include("compiler/lowering/relationship_policies.jl")
include("compiler/lowering/storage_layouts.jl")
include("compiler/lowering/domain_resources.jl")
include("compiler/lowering/proposal_descriptors.jl")
include("compiler/lowering/stage_evaluators.jl")
include("compiler/lowering/accepted_copy_descriptors.jl")
include("compiler/lowering/relationship_stage_descriptors.jl")
include("compiler/lowering/stage_grouping.jl")
include("compiler/lowering/after_mcs_descriptors.jl")
include("compiler/lowering/stage_plan.jl")
include("compiler/lowering/constraints.jl")
include("compiler/lowering/trackers.jl")
include("compiler/lowering/lifecycle_plan.jl")
include("compiler/execution/boundary.jl")
include("compiler/lowering/core_program.jl")
include("compiler/compile.jl")

# SciML-facing runtime orchestration and optional native component coupling.
include("runtime/initial_state.jl")
include("runtime/problem.jl")
include("native/runtime_errors.jl")
include("native/logical_state.jl")
include("native/component_pools.jl")
include("native/preflight.jl")
include("native/coupling_io.jl")
include("native/initialization.jl")
include("native/advancement.jl")
include("runtime/capabilities.jl")
include("runtime/saved_state.jl")
include("runtime/integrator.jl")
include("runtime/relationships.jl")
include("runtime/solution.jl")
include("runtime/checkpoint.jl")
include("runtime/symbolic_indexing.jl")
include("inspection.jl")

export PottsSystem, StatementSet, StatementID, SourceLocation, UnknownSource
export AbstractPottsStatement, AbstractPottsEffect, AbstractPottsPhase
export CellKind, MediumKind, LatticeDomain, SpatialRelation
export SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
export RelationshipState
export HamiltonianTerm, ProposalDrive, ProposalConstraint, ProposalModifier
export SynchronousProcess, AcceptedCopyProcess, RelationshipProcess, LifecycleProcess
export Observation, Protocol, RegisteredStatement
export StatementRegistry, default_statement_registry, register_statement
export statements, statement_id, statement_source, @statements
export compose, extend, flatten, complete, iscomplete, is_scheduled
export @named, @mtkcompile, mtkcompile
export AbstractPottsAlgorithm, SequentialCPM, CheckerboardSweepCPM
export AbstractPottsBackend, CPUBackend, MetalBackend
export PottsParameters
export LabelledCells, OwnershipLayout, CellPlacement, MediumPlacement
export SiteBinding, CellBinding, ContactBinding, RelationshipBinding
export anchor_value
export gather
export AbstractProceduralPlacement, RandomSitePlacement
export PottsInitialState, PottsProblem, PottsIntegrator, PottsSavedState, PottsSolution
export PottsStats, init, solve, solve!, step!, remake, terminate!
export CellIdentity, relationship_transaction!
export PottsCheckpoint, checkpoint
export DeclaredReferenceUnits, ReferenceUnits
export ProposalContext
export source_site, target_site, source_cell, target_cell, source_kind, target_kind
export is_extension, is_retraction, new_contact, lost_contact
export cell_volume, cell_surface, cell_elongation, cell_center, unwrapped_center, distance
export contact_owner_a, contact_owner_b, contact_kind_a, contact_kind_b
export contact_edge_count, contact_measure, boundary_site_count, neighbor_cells
export neighbor_cell_count, neighbor_property_sum, neighbor_property_mean
export global_interface_measure, field_value, field_gradient, laplacian, occupancy
export linked, degree, endpoint_a, endpoint_b, edge_payload, lag, history_value
export AbstractPottsDistribution, Bernoulli, Uniform, Normal, UnitVector, DrawKey, draw
export PureRead, SynchronousAssign, AcceptedCopyEffect, OrderedBatchEffect
export Proposal, AcceptedCopy, AfterMCS, RelationshipCommit, Lifecycle
export Before, After, EveryMCS, AtMCS, Every
export sites, cells, model, contacts, edges, incident_edges
export Assign, Create, Remove, Retune
export CreateCell, RemoveCell, Transition, Divide, Retire
export SeedAt, SeedStencil, CellCentroid
export RandomPlane, PrincipalAxisPlane, SpecifiedNormalPlane
export CanonicalSide, StableRandomSide, PreserveKind, SetKind
export InitializeFrom, Unsupported, RetireTo, Preserve, ResetTo, Transform
export CopyToDaughters, PreserveParentResetDaughter, ResetBoth
export SplitConservatively, TransformDaughters, RedrawDaughters
export RejectWhileLinked, RemoveIncident, PreserveCompatible
export RemoveIncompatible, RejectIncompatible
export FilterInadmissible, ErrorOnInadmissible
export RejectLifecycleAmbiguity, StableLifecyclePriority
export RetireAtZero, ForbidExtinction
export Periodic, Closed, FrozenBorder, VonNeumann, Moore
export ClearOnOwnershipChange, PreserveOnOwnershipChange
export Undirected, RemoveWithEndpoint, RejectEndpointRetirement
export DiscreteFieldEuler
export ExtensionsOnly, RetractionsOnly, ExtensionsAndRetractions
export Nearest, Multilinear, CellCentered, AttemptsPerSite
export Lattice, Volume, ContactEnergy, Elongation, Chemotaxis, LocalConnectivity
export ActEnergy, Synchronous, Sweep, SweepStage
export RelationshipEnergy, RelationshipConstraint, ↔
export inspect, Statements, Variables, Effects, RandomOperations, Schedule
export Capabilities, Fingerprints
export ParameterSchema, StateSchema, Observations, ExternalIO, ReplayContract
export LifecyclePlans
export semantic_fingerprint, completed_system_fingerprint, scheduled_system_fingerprint
export NativeComponent, ODEComponent, DAEComponent, Global, PerCell
export FixedPhysicalTime, CPMThenComponents, NativeInput, NativeOutput
export NativeFieldOutput, MethodOfLinesComponent
export NativeOperatingPoint, NativeSolveProfile
export SerialNativeExecution, BatchedNativeExecution, MetalNativeExecution
export CouplingEndpointSchema, native_components, scheduled_native_components
export native_component_path
export native_time_at, native_cadence_stride, native_due, native_time_interval
export native_state, native_value
export PreserveNativeInitialization, PreserveNativeEvents
export GlobalNativeLifecycle, PerCellNativeLifecycle, LateBoundNativeAlgorithm
export StandardNativeCapability

# Scientific statement and compiler-transfer SPI.
public map_symbolics, statement_kind, with_source
public registered_statement_lowering
public OperationTransfer, LifecycleOperationABI, operation_transfer
public AbstractOperationSourceRequirement, LatticeRankRequirement
public SpatialRelationRequirement
public NamedSpatialRelationRequirement
public AbstractFootprintTransferRule, InheritFootprintRule
public ProposalSourceFootprintRule, ProposalTargetFootprintRule
public ProposalSourceTargetFootprintRule, IterationSiteFootprintRule
public OwnerFootprintRule
public ContactFootprintRule, IncidentRelationshipFootprintRule
public AbstractNeighborhoodAnchorRule, OperandNeighborhoodAnchors
public ProposalTargetNeighborhoodAnchor
public ProposalSourceTargetNeighborhoodAnchor, IterationNeighborhoodAnchor
public NeighborhoodFootprintRule
public DescriptorSource, DescriptorConstructionContext
public registered_descriptor_payload, registered_workspace_schemas
public registered_tracker_requirements
public ResolvedOperationSourceBinding, OperationTrackerContext
public registered_operation_tracker_requirements
public is_direct_scalar_tracker_projection
public QualifiedStatementID, QualifiedStatement, EffectBound, RandomOperation
public EngineAdmission, SemanticFingerprint, CompletedSystemFingerprint
public ScheduledSystemFingerprint

# Native MTK/SciML component-extension SPI.
public NativeSourceFingerprint, CompletedNativeComponent, ScheduledNativeComponent
public native_source, native_family, native_inputs, native_outputs
public native_variable, potts_endpoint, native_value_type
public native_original_system, native_scheduled_system, native_coupling_endpoints
public native_original_fingerprint, native_scheduled_fingerprint
public native_index_provider, native_problem_constructor
public NativeLogicalState
public AbstractNativeRuntimeError, NativeProfileError, NativeCapabilityError
public NativeExecutionError, NativeSolveFailure
public PottsCapabilityKey, PottsCapabilityReport

# Stable diagnostics, inspection, and unit-conversion helpers.
public PottsDiagnostic, PottsValidationError
public PottsLookupError, PottsUnknownIdentityError, PottsKnownUnsavedError
public PottsUnsavedTimeError
public runtime_statistics
public to_dynamic_quantity, to_unitful_quantity

"""Convert a DynamicQuantities value to Unitful when that extension is loaded."""
function to_unitful_quantity end
"""Convert a Unitful quantity to Potts's DynamicQuantities representation."""
to_dynamic_quantity(value::DynamicQuantities.UnionAbstractQuantity) = value

const compose = ModelingToolkitBase.compose
const extend = ModelingToolkitBase.extend
const flatten = ModelingToolkitBase.flatten
const complete = ModelingToolkitBase.complete
const iscomplete = ModelingToolkitBase.iscomplete

include("precompile.jl")

end
