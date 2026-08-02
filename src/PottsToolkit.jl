module PottsToolkit

import CorePotts
import DynamicQuantities
import ModelingToolkitBase
import SciMLBase
import SHA
import SymbolicIndexingInterface
import Symbolics
import SciMLBase: init, solve, solve!, step!, remake, terminate!

include("statements/statements.jl")
include("symbolics/bindings.jl")
include("symbolics/operations.jl")
include("symbolics/distributions.jl")
include("statements/semantics.jl")
include("completion/qualified_ir.jl")
include("completion/diagnostics.jl")
include("systems.jl")
include("completion/inference.jl")
include("completion/fingerprints.jl")
include("completion/completion.jl")
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
include("compiler/host/analysis.jl")
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
include("compiler/execution/boundary.jl")
include("compiler/lowering/core_program.jl")
include("compiler/compile.jl")
include("runtime/initial_state.jl")
include("runtime/problem.jl")
include("runtime/saved_state.jl")
include("runtime/integrator.jl")
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
export EquationProcess, Observation, Protocol, RegisteredStatement
export StatementRegistry, default_statement_registry, register_statement
export statements, statement_id, statement_source, @statements
export compose, extend, flatten, complete, iscomplete
export compile, PottsExecutable, SequentialEngine, CheckerboardEngine, CPUBackend
export PottsParameters
export LabelledCells, OwnershipLayout, CellPlacement, MediumPlacement
export SiteBinding, CellBinding, ContactBinding, RelationshipBinding
export anchor_value
export AbstractProceduralPlacement, RandomSitePlacement
export PottsInitialState, PottsProblem, PottsIntegrator, PottsSavedState, PottsSolution
export PottsStats, init, solve, solve!, step!, remake, terminate!
export PottsCheckpoint, checkpoint
export DeclaredReferenceUnits, ReferenceUnits
export ProposalContext, RelationshipBinding
export source_site, target_site, source_cell, target_cell, source_kind, target_kind
export is_extension, is_retraction, new_contact, lost_contact
export cell_volume, cell_surface, cell_elongation, cell_center, unwrapped_center, distance
export contact_owner_a, contact_owner_b, contact_kind_a, contact_kind_b
export contact_measure, boundary_measure, neighbor_count, neighbor_sum, neighbor_mean
export neighbor_geomean, field_value, field_gradient, laplacian, occupancy
export linked, degree, endpoint_a, endpoint_b, edge_payload, lag, history_value
export AbstractPottsDistribution, Bernoulli, Uniform, Normal, UnitVector, DrawKey, draw
export PureRead, SynchronousAssign, AcceptedCopyEffect, OrderedBatchEffect
export Proposal, AcceptedCopy, AfterMCS, RelationshipCommit, Lifecycle, EquationStep, Observe
export Before, After, EveryMCS, AtMCS, Every
export sites, cells, contacts, edges, incident_edges
export Assign, Create, Remove, Retune, Transition, Divide, Retire
export Periodic, Closed, FrozenBorder, VonNeumann, Moore
export ClearOnOwnershipChange, PreserveOnOwnershipChange
export Undirected, Directed, RemoveWithEndpoint, RejectEndpointRetirement
export ExplicitDiffusion, ExplicitEuler, Heun, RK4
export ExtensionsOnly, RetractionsOnly, ExtensionsAndRetractions
export Nearest, Multilinear, CellCentered, AttemptsPerSite
export Lattice, Volume, ContactEnergy, Elongation, Chemotaxis, LocalConnectivity
export ActEnergy, Synchronous, Sweep, SweepStage, ObserveStage
export RelationshipEnergy, RelationshipConstraint, ↔
export inspect, Statements, Variables, Effects, RandomOperations, Schedule
export Capabilities, Fingerprints, StoragePlan, Kernels
export semantic_fingerprint, completed_system_fingerprint
export EquationComponent, process_component

public map_symbolics, statement_kind, with_source
public registered_statement_lowering
public OperationTransfer, operation_transfer
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
public QualifiedStatementID, QualifiedStatement, EffectBound, RandomOperation
public EngineAdmission, SemanticFingerprint, CompletedSystemFingerprint
public ExecutableFingerprint, PottsDiagnostic, PottsValidationError
public PottsLookupError, PottsUnknownIdentityError, PottsKnownUnsavedError
public PottsUnsavedTimeError
public RuntimeParameter, ParameterManifest, executable_fingerprint
public ReferenceUnitDescriptor
public ParameterSchema, StateSchema, Observations, ExternalIO, ReplayContract
public stage_external_inputs!, runtime_statistics
public to_dynamic_quantity, to_unitful_quantity

function EquationComponent end
function process_component end
function compile end
function to_unitful_quantity end
to_dynamic_quantity(value::DynamicQuantities.UnionAbstractQuantity) = value

const compose = ModelingToolkitBase.compose
const extend = ModelingToolkitBase.extend
const flatten = ModelingToolkitBase.flatten
const complete = ModelingToolkitBase.complete
const iscomplete = ModelingToolkitBase.iscomplete

include("precompile.jl")

end
