module PottsToolkit

import CorePotts
import DynamicQuantities
import ModelingToolkitBase
import SciMLBase
import SHA
import SymbolicIndexingInterface
import Symbolics

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
include("inspection.jl")

export PottsSystem, StatementSet, StatementID, SourceLocation, UnknownSource
export AbstractPottsStatement, AbstractPottsEffect, AbstractPottsPhase
export CellKind, MediumKind, LatticeDomain, SpatialRelation
export SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
export RelationshipState
export ProposalEnergy, ProposalDrive, ProposalConstraint, ProposalModifier
export SynchronousProcess, AcceptedCopyProcess, RelationshipProcess, LifecycleProcess
export EquationProcess, Observation, Protocol, RegisteredStatement
export StatementRegistry, default_statement_registry, register_statement
export statements, statement_id, statement_source, @statements
export compose, extend, flatten, complete, iscomplete
export DeclaredReferenceUnits, ReferenceUnits
export ProposalContext, RelationshipBinding
export source_site, target_site, source_cell, target_cell, source_kind, target_kind
export is_extension, is_retraction, new_contact, lost_contact
export cell_volume, cell_surface, cell_center, unwrapped_center, distance
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
export EquationComponent

public map_symbolics, statement_kind, with_source
public QualifiedStatementID, QualifiedStatement, EffectBound, RandomOperation
public EngineAdmission, SemanticFingerprint, CompletedSystemFingerprint
public ExecutableFingerprint, PottsDiagnostic, PottsValidationError
public to_dynamic_quantity, to_unitful_quantity

function EquationComponent end
function to_unitful_quantity end
to_dynamic_quantity(value::DynamicQuantities.UnionAbstractQuantity) = value

const compose = ModelingToolkitBase.compose
const extend = ModelingToolkitBase.extend
const flatten = ModelingToolkitBase.flatten
const complete = ModelingToolkitBase.complete
const iscomplete = ModelingToolkitBase.iscomplete

end
