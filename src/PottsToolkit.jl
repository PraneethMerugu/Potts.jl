module PottsToolkit

import CorePotts

const ScientificContractVersions = CorePotts.ScientificContractVersions
const scientific_contract_versions = CorePotts.scientific_contract_versions
const AUTHORING_DSL_CONTRACT_VERSION = CorePotts.AUTHORING_DSL_CONTRACT_VERSION
const NORMALIZED_IR_CONTRACT_VERSION = CorePotts.NORMALIZED_IR_CONTRACT_VERSION
const SEMANTIC_FINGERPRINT_VERSION = CorePotts.SEMANTIC_FINGERPRINT_VERSION
const EXECUTION_FINGERPRINT_VERSION = CorePotts.EXECUTION_FINGERPRINT_VERSION
const PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION =
    CorePotts.PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION

include("authoring/Authoring.jl")
include("reference_models.jl")

using .Authoring: Namespace, SemanticName, AbstractBiologicalType, CellType, Medium,
                  AbstractFragmentRole, CellRole, FieldRole,
                  Binding, BindingTable, PairIdentity, PairwiseLaw,
                  AbstractPropertyInvariant, UnboundedProperty, ClosedPropertyInterval,
                  PropertyVisibility, PublicProperty, PrivateProperty,
                  PropertyPersistence, CheckpointedProperty, EphemeralProperty,
                  PropertyOptionality, RequiredProperty, OptionalProperty, CellProperty,
                  CellParameter, ModelParameter,
                  VolumeParameters, VolumeConstraint, FluctuatingVolumeConstraint,
                  ElongationParameters, Elongation,
                  BoundaryParameters, BoundaryConstraint, FluctuatingBoundaryConstraint,
                  Adhesion, PreserveConnectivity, PrescribedField, Chemotaxis,
                  PropertyUpdate, StochasticPropertyUpdate, Growth, Transition,
                  Division, ShrinkDeath, ImmediateDeath, NamedCoreComponent,
                  ModelFragment, bind, PottsModel, NormalizedModel, add, remove, replace,
                  compose, normalize, validate, explain, provenance, dependencies,
                  capabilities,
                  CellLayout, CellLabelLayout, MediumLayout, LoweredModel, lower, problem,
                  validate_problem, backend_report, semantic_identity,
                  semantic_fingerprint, execution_fingerprint, semantic_manifest,
                  SourceLocation, Diagnostic, ValidationReport, ModelValidationError,
                  ProblemValidationError, ModelReport, DeclarationReport, DependencyEdge,
                  DependencyReport, ModelCapabilityReport, ProvenanceEntry,
                  SemanticFingerprint,
                  ExecutionFingerprint, SemanticManifest,
                  AbstractLevel1Declaration, Volume, Surface,
                  Act,
                  FluctuatingVolumePressure, FluctuatingSurfaceTension,
                  AcceptanceTemperature, IndependentNoise,
                  RandomOrientationSplit, MinorAxisSplit, MajorAxisSplit, VectorSplit,
                  AbstractMissingPairPolicy, RejectMissingPairs, DefaultPairValue,
                  Layout, Place, LabelledCells, AbstractProceduralLayout,
                  UniformSiteSeedLayout, SequentialRejectionLayout,
                  UniformSiteSeeds, SequentialRejectionPlacement,
                  CartesianDomain, PeriodicBoundary,
                  ClosedBoundary, FixedExterior, AxisBoundary, LatticeBall, LatticeBox,
                  PottsProblem,
                  Phase, AbstractRuleExpression, RuleLiteral, OwnerReference,
                  PropertyRead, CellParameterRead, ModelParameterRead,
                  ScalarCall, ConditionalExpression, NoChange,
                  AbstractDrawDistribution, Bernoulli, Uniform, Normal, UnitVector,
                  RandomDraw, draw,
                  Contacting, AbstractQueryOwnerFilter, AnyFiniteCell, CellTypeFilter,
                  SpatialQueryExpression, contact_edge_count, contact_measure,
                  boundary_site_count, neighbor_cell_count, neighbor_property_sum,
                  neighbor_property_mean,
                  Rule, RuleGroup, TriggerRule, EveryMCS, AtMCS, BetweenMCS,
                  evaluate, @rule, @rules, @trigger,
                  AbstractFieldPlacement, CellCentered, AbstractFieldBoundary,
                  NoFlux, PeriodicField, FixedValue, AbstractFieldInterpolation,
                  Multilinear, Nearest, Field,
                  LinearResponse, MichaelisMentenResponse, SaturationLinearResponse,
                  ExtensionChemotaxis, RetractionChemotaxis, ReciprocalChemotaxis,
                  PositiveYield, PropertyAtLeast,
                  ReadOnlyProperty, MutableProperty,
                  CloneOnDivision, SplitOnDivision, ResetChildOnDivision,
                  ResetBothOnDivision, AsymmetricResetOnDivision, UnsupportedDivision,
                  ConstitutiveResetAfterDivision, PreserveMechanicalOnDivision,
                  StationaryRedrawAfterDivision, PreserveOnTransition, ResetOnTransition,
                  RecomputeOnTransition, UnsupportedTransition, ResetOnRetirement,
                  ConstitutiveMeanInitialization, StationaryMechanicalInitialization,
                  PreserveMechanicalInitialization,
                  SequentialCPM, AttemptsPerSite, BudgetedSequentialCPM,
                  SequentialEquilibrium, CheckerboardSweepCPM,
                  TiledCheckerboardCPM, LotteryCPM,
                  SpatialRoles, OmittedSpatialRole, spatial_roles, relation_for,
                  FillSites, SiteValues, InitializeFromOwnership,
                  PreserveAtSite, ResetChangedSites, AcceptedCopyManaged, SiteProperty,
                  SetTo, PreserveSiteValue, AcceptedCopyUpdate,
                  SaturatingSubtract, SetSiteValue, SiteDynamics,
                  Lag, RepeatInitialSample, MissingUntilFull, ExplicitInitialHistory,
                  ResetChildHistory, CopyParentHistory, PreserveHistory, ResetHistory,
                  CellHistory, HistorySample, RelationshipCapacity,
                  RemoveIncidentEdges, RejectEndpointRetirement, RelationshipSet,
                  MCSPlan, PottsAttempts, LifecyclePhase, ObservationPhase,
                  Advance, Exchange, Sample, Update,
                  MCSRange, During, ProtocolStage, StagedProtocol,
                  ScheduledParameter, ContinuousClock, ContinuousInterval,
                  OneMCS, HalfMCS, GlobalClock, MCSDuration,
                  AtMCSStart, AtMCSEnd, AtMCSOffset,
                  ScheduledSystem, ScheduledEvent, ScheduledProcess,
                  ScheduledPotts, TimedLifecyclePhase, ScheduledLifecycle,
                  MultirateSchedule,
                  GlobalDomain, CellDomain, FieldDomain, MembraneDomain,
                  GlobalProperty, MembraneProperty,
                  AngularMembrane, FillMembrane,
                  ConservativeMembraneRemap, PartitionMembraneByGeometry,
                  PreserveMembrane, ResetMembrane,
                  StateVariable, InputVariable, Constant, IntermediateVariable,
                  ObservableVariable, TimeVariable, DirectLaw,
                  DifferentialEquation, SynchronousRule, AlgebraicAssignment,
                  FunctionDefinition, AlgebraicConstraint,
                  StochasticDifferentialEquation, ReactionStatement,
                  DeterministicReaction, DiscreteJumpProcess, HybridReaction,
                  ExplicitEuler, Heun, RK4, SystemStep, FixedStep, AdaptiveStep,
                  SystemClock, ContinuousSystem, CellDynamics,
                  ReactionDiffusion, FieldDynamics, ByCellVolume,
                  ConstantConcentration, Uptake, FieldExchange,
                  SteadyStateAdvance,
                  StableRelationshipPriority, CreateRelationship,
                  RemoveRelationship, RetuneRelationship,
                  RelationshipDynamics,
                  ExactSample, PiecewiseConstantDelay,
                  LinearDelayInterpolation, RepeatInitialDelay, EveryGlobal,
                  DelayState, WhileTrue, OnRising, OnceWhenTrue,
                  PersistentTrigger, SampledTrigger, RootTrigger,
                  EventAssignment, FromTriggerSnapshot,
                  FromExecutionSnapshot, NoImmediateCascade,
                  CascadeUntilStable, LifecycleRequest, ContinuousEvent,
                  SymbolIdentity, SymbolRef, InputRef, IdentityMap, SymbolMap,
                  ExactSemanticMapping, QualifiedNumericalMapping,
                  ExplicitApproximation, PartialMapping, RejectedMapping,
                  CompatibilityItem, MorpheusSemanticProfile,
                  SBMLSemanticProfile, ContinuousModelAdapter,
                  CompletedMCS, NamedPhaseSnapshot, RequiredObservation,
                  BestEffortTelemetry, RecordSchema, PhaseObservation,
                  ObservationTransform,
                  AbstractScientificObservable, CellVolume, CellTypeObservable,
                  CellBoundaryMeasure, CellPropertyValues, ObservationSet,
                  CellValue, CellValues, CellFrame, CellSeries,
                  observe, observation_policy, observation_table,
                  PhysicalScale, UnitfulSolutionView, with_units, mcs

export Authoring, ReferenceModels
export ScientificContractVersions, scientific_contract_versions,
       AUTHORING_DSL_CONTRACT_VERSION, NORMALIZED_IR_CONTRACT_VERSION,
       SEMANTIC_FINGERPRINT_VERSION, EXECUTION_FINGERPRINT_VERSION,
       PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION
export Namespace, SemanticName, AbstractBiologicalType, CellType, Medium
export AbstractFragmentRole, CellRole, FieldRole
export Binding, BindingTable, PairIdentity, PairwiseLaw
export AbstractPropertyInvariant, UnboundedProperty, ClosedPropertyInterval
export PropertyVisibility, PublicProperty, PrivateProperty
export PropertyPersistence, CheckpointedProperty, EphemeralProperty
export PropertyOptionality, RequiredProperty, OptionalProperty, CellProperty
export CellParameter, ModelParameter
export VolumeParameters, VolumeConstraint, FluctuatingVolumeConstraint
export ElongationParameters, Elongation
export BoundaryParameters, BoundaryConstraint, FluctuatingBoundaryConstraint
export Adhesion, PreserveConnectivity, PrescribedField, Chemotaxis
export PropertyUpdate, StochasticPropertyUpdate, Growth, Transition
export Division, ShrinkDeath, ImmediateDeath, NamedCoreComponent
export ModelFragment, bind, PottsModel, NormalizedModel
export add, remove, replace, compose, normalize, validate, explain, provenance, dependencies
export capabilities
export CellLayout, CellLabelLayout, MediumLayout, LoweredModel
export lower, problem, validate_problem, backend_report
export semantic_identity, semantic_fingerprint, execution_fingerprint, semantic_manifest
export SourceLocation, Diagnostic, ValidationReport, ModelValidationError, ProblemValidationError
export ModelReport, DeclarationReport, DependencyEdge, DependencyReport
export ModelCapabilityReport, ProvenanceEntry
export SemanticFingerprint, ExecutionFingerprint, SemanticManifest
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
export SequentialCPM, SequentialEquilibrium, CheckerboardSweepCPM,
       TiledCheckerboardCPM, LotteryCPM
export AttemptsPerSite, BudgetedSequentialCPM
export SpatialRoles
# Registry-v1 Phase 14 façades remain implementation details during kernel migration.
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
export AbstractScientificObservable, CellVolume, CellTypeObservable
export CellBoundaryMeasure, CellPropertyValues, ObservationSet
export CellValue, CellValues, CellFrame, CellSeries
export observe, observation_policy, observation_table
export PhysicalScale, UnitfulSolutionView, with_units, mcs

include("public_api_docs.jl")
include("precompile.jl")

end
