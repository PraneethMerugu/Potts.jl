module Authoring

import CorePotts
import SciMLBase
import SHA
import StaticArrays
import Base: isvalid

include("identities.jl")
include("bindings.jl")
include("properties.jl")
include("components.jl")
include("fields.jl")
include("lifecycle.jl")
include("reports.jl")
include("models.jl")
include("normalization.jl")
include("procedural_layouts.jl")
include("lowering.jl")
include("level1.jl")
include("level1_rules.jl")
include("level1_queries.jl")
include("level1_runtime.jl")
include("level1_fields.jl")
include("level1_core_api.jl")
include("level1_activity.jl")
include("level1_observables.jl")
include("level1_units.jl")

export Namespace, SemanticName, AbstractBiologicalType, CellType, Medium
export AbstractFragmentRole, CellRole, FieldRole
export FragmentPortContract, FragmentRequirement, FragmentExport
export fragment_port_contract, required_backends
export Binding, BindingTable, PairIdentity, PairwiseLaw
export AbstractPropertyInvariant, UnboundedProperty, ClosedPropertyInterval
export PropertyVisibility, PublicProperty, PrivateProperty
export PropertyPersistence, CheckpointedProperty, EphemeralProperty
export PropertyOptionality, RequiredProperty, OptionalProperty
export CellProperty
export CellParameter, ModelParameter
export VolumeParameters, VolumeConstraint, FluctuatingVolumeConstraint
export ElongationParameters, Elongation
export BoundaryParameters, BoundaryConstraint, FluctuatingBoundaryConstraint, Adhesion
export PreserveConnectivity
export PrescribedField, Chemotaxis
export PropertyUpdate, StochasticPropertyUpdate
export Growth, Transition, Division, ShrinkDeath, ImmediateDeath
export NamedCoreComponent
export ModelFragment, bind, PottsModel, NormalizedModel
export add, remove, replace, compose, normalize, validate, explain, provenance
export dependencies, capabilities
export CellLayout, CellLabelLayout, MediumLayout, LoweredModel, lower, problem, validate_problem
export backend_report
export semantic_identity, semantic_fingerprint, isvalid
export execution_fingerprint, semantic_manifest
export SourceLocation, Diagnostic, ValidationReport, ModelValidationError
export ProblemValidationError, ModelReport
export DeclarationReport, DependencyEdge, DependencyReport, ModelCapabilityReport
export ProvenanceEntry
export SemanticFingerprint, ExecutionFingerprint
export SemanticManifest
export AbstractLevel1Declaration, Volume, Surface
export Act
export FluctuatingVolumePressure, FluctuatingSurfaceTension
export AcceptanceTemperature, IndependentNoise
export RandomOrientationSplit, MinorAxisSplit, MajorAxisSplit, VectorSplit
export AbstractMissingPairPolicy, RejectMissingPairs, DefaultPairValue
export Layout, Place, LabelledCells
export AbstractProceduralLayout, UniformSiteSeedLayout, SequentialRejectionLayout
export UniformSiteSeeds, SequentialRejectionPlacement
export CartesianDomain, PeriodicBoundary, ClosedBoundary, FixedExterior, AxisBoundary
export LatticeBall, LatticeBox
export PottsProblem
export Phase, AbstractRuleExpression, RuleLiteral, OwnerReference, PropertyRead
export CellParameterRead, ModelParameterRead
export ScalarCall, ConditionalExpression, NoChange, Rule, RuleGroup, TriggerRule
export AbstractDrawDistribution, Bernoulli, Uniform, Normal, UnitVector
export RandomDraw, draw
export Contacting, AbstractQueryOwnerFilter, AnyFiniteCell, CellTypeFilter
export SpatialQueryExpression, contact_edge_count, contact_measure, boundary_site_count
export neighbor_cell_count, neighbor_property_sum, neighbor_property_mean
export EveryMCS, AtMCS, BetweenMCS, evaluate
export @rule, @rules, @trigger
export AbstractFieldPlacement, CellCentered
export AbstractFieldBoundary, NoFlux, PeriodicField, FixedValue
export AbstractFieldInterpolation, Multilinear, Nearest, Field
export LinearResponse, MichaelisMentenResponse, SaturationLinearResponse
export ExtensionChemotaxis, RetractionChemotaxis, ReciprocalChemotaxis
export PositiveYield, PropertyAtLeast
export ReadOnlyProperty, MutableProperty
export CloneOnDivision, SplitOnDivision, ResetChildOnDivision, ResetBothOnDivision
export AsymmetricResetOnDivision, UnsupportedDivision
export ConstitutiveResetAfterDivision, PreserveMechanicalOnDivision
export StationaryRedrawAfterDivision
export PreserveOnTransition, ResetOnTransition, RecomputeOnTransition
export UnsupportedTransition, ResetOnRetirement
export ConstitutiveMeanInitialization, StationaryMechanicalInitialization
export PreserveMechanicalInitialization
export SequentialCPM, AttemptsPerSite, BudgetedSequentialCPM,
       SequentialEquilibrium, CheckerboardSweepCPM,
       TiledCheckerboardCPM, LotteryCPM
export SpatialRoles
# Registry-v1 Phase 14 façades are internalized; `Act` is the first retained v2 façade.
#=
export FillSites, SiteValues, InitializeFromOwnership,
       PreserveAtSite, ResetChangedSites, AcceptedCopyManaged, SiteProperty,
       SetTo, PreserveSiteValue, AcceptedCopyUpdate,
       SaturatingSubtract, SetSiteValue, SiteDynamics,
       Lag, RepeatInitialSample, MissingUntilFull, ExplicitInitialHistory,
       ResetChildHistory, CopyParentHistory, PreserveHistory, ResetHistory,
       CellHistory, HistorySample, RelationshipCapacity,
       RemoveIncidentEdges, RejectEndpointRetirement, RelationshipSet
export MCSPlan, PottsAttempts, LifecyclePhase, ObservationPhase,
       Advance, Exchange, Sample, Update,
       MCSRange, During, ProtocolStage, StagedProtocol,
       ScheduledParameter, ContinuousClock, ContinuousInterval, OneMCS, HalfMCS,
       GlobalClock, MCSDuration, AtMCSStart, AtMCSEnd, AtMCSOffset,
       ScheduledSystem, ScheduledEvent, ScheduledProcess, ScheduledPotts,
       TimedLifecyclePhase, ScheduledLifecycle, MultirateSchedule
export GlobalDomain, CellDomain, FieldDomain, MembraneDomain,
       GlobalProperty, MembraneProperty,
       AngularMembrane, FillMembrane, ConservativeMembraneRemap,
       PartitionMembraneByGeometry, PreserveMembrane, ResetMembrane,
       StateVariable, InputVariable, Constant, IntermediateVariable,
       ObservableVariable, TimeVariable, DirectLaw,
       DifferentialEquation, SynchronousRule, AlgebraicAssignment,
       FunctionDefinition, AlgebraicConstraint, StochasticDifferentialEquation,
       ReactionStatement, DeterministicReaction, DiscreteJumpProcess,
       HybridReaction, ExplicitEuler, Heun, RK4, SystemStep, FixedStep,
       AdaptiveStep, SystemClock, ContinuousSystem, CellDynamics,
       ReactionDiffusion, FieldDynamics, ByCellVolume, ConstantConcentration,
       Uptake, FieldExchange, SteadyStateAdvance
export StableRelationshipPriority, CreateRelationship, RemoveRelationship,
       RetuneRelationship, RelationshipDynamics
export ExactSample, PiecewiseConstantDelay, LinearDelayInterpolation,
       RepeatInitialDelay, EveryGlobal, DelayState,
       WhileTrue, OnRising, OnceWhenTrue, PersistentTrigger,
       SampledTrigger, RootTrigger, EventAssignment,
       FromTriggerSnapshot, FromExecutionSnapshot,
       NoImmediateCascade, CascadeUntilStable, LifecycleRequest,
       ContinuousEvent, SymbolIdentity, SymbolRef, InputRef, IdentityMap,
       SymbolMap, ExactSemanticMapping, QualifiedNumericalMapping,
       ExplicitApproximation, PartialMapping, RejectedMapping,
       CompatibilityItem, MorpheusSemanticProfile, SBMLSemanticProfile,
       ContinuousModelAdapter
export CompletedMCS, NamedPhaseSnapshot, RequiredObservation,
       BestEffortTelemetry, RecordSchema, PhaseObservation,
       ObservationTransform
=#
export AbstractScientificObservable, CellVolume, CellTypeObservable, LatticeOwnership
export CellBoundaryMeasure, CellPropertyValues, ObservationSet
export CellValue, CellValues, CellFrame, CellSeries
export ObservedCell, OwnershipValues, SpatialFrame, SpatialSeries
export observed_cell_id, observed_cell_generation, observed_cell_type
export ownership_size, ownership_owner_at, ownership_cells
export spatial_mcs, spatial_values
export observe, observation_policy, observation_table
export PhysicalScale, UnitfulSolutionView, with_units, mcs

end
