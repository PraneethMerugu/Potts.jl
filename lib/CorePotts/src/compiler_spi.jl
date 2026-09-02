"""
Compiler-facing construction protocol for Potts and third-party
scientific extensions.

Bindings in this module are the only supported route from another package into
CorePotts lowering schemas, evaluator construction, descriptors, and inspection.
They are intentionally absent from the stable package-level runtime API.

This is an explicit, flat facade over CorePotts-owned bindings, not a second
implementation or a general plugin registry. Ordinary model authors should not
use it. Compiler extensions should import only the bindings needed to construct
or inspect validated compiler IR; runtime and device integration belongs to
`BackendSPI` instead.
"""
module CompilerSPI

import ..CorePotts:
    AbstractCompiledStage,
    AbstractContextualOperation,
    AbstractEvaluatorExecutionContext,
    AbstractFootprint,
    AbstractHamiltonianEvaluationContext,
    AbstractLifecycleExecutionPlan,
    AbstractLifecyclePartitionEvaluationContext,
    AbstractLifecyclePlacementEvaluationContext,
    AbstractLifecycleSiteSelection,
    AbstractLifecycleStateTransformEvaluationContext,
    AbstractLifecycleTriggerEvaluationContext,
    AbstractProbeEvaluationContext,
    AbstractProposalEvaluationContext,
    AbstractProposalRole,
    AbstractRelationshipStageEvaluationContext,
    AbstractSiteStageEvaluationContext,
    AbstractStageSiteSelector,
    AbstractStaticExpression,
    AbstractTrackerCheckpointPolicy,
    AbstractTrackerConcurrency,
    AbstractTrackerCost,
    AbstractTrackerDelta,
    AbstractTrackerDescriptor,
    AbstractTrackerSource,
    AbstractTrackerStorage,
    AbstractTrackerUpdateBound,
    AbstractTrackerVisibility,
    AcceptedCopyStage,
    AcceptedCommitTrackerVisibility,
    AfterMCSStage,
    AtMCSLifecycleCadence,
    BoundSiteFootprintAnchor,
    BoundedNeighborhoodTrackerCost,
    CanonicalLifecycleSide,
    CeilLifecycleRounding,
    CellEnergyDomainPlan,
    CellKindLifecycleDomain,
    CellMomentsTracker,
    CellSurfaceTracker,
    ClaimedOwnerExclusiveTrackerConcurrency,
    ClearLifecycleOwnershipState,
    CommutativeIntegerWriteAccess,
    CompiledPottsProgram,
    CompiledScalar,
    CompiledStageDescriptor,
    ConstraintGroup,
    ContactEnergyDomainPlan,
    ContactFootprint,
    ConstantTrackerCost,
    ContextExpression,
    ContextOperation,
    CopyDaughtersLifecycleState,
    CreateCellLifecycleEffect,
    DeferredRequestWriteAccess,
    DenseOwnerScalarStorage,
    DenseOwnerMomentsStorage,
    DenseScalarTrackerGroup,
    DestinationLifecycleStateRole,
    DescriptorExecutionPlan,
    DescriptorGroup,
    DescriptorKernelStrategy,
    DescriptorLaunch,
    DescriptorSupport,
    DimensionSquaredTrackerCost,
    DivideCellLifecycleEffect,
    DaughterLifecycleStateRole,
    EmptyDescriptorPayload,
    EmptyFootprint,
    ErrorLifecycleInadmissible,
    EveryMCSLifecycleCadence,
    ExactLifecycleRounding,
    ExclusiveWriteAccess,
    ExternalLifecyclePartition,
    ExternalLifecyclePlacement,
    FilterLifecycleInadmissible,
    FiniteSpatialFootprint,
    FloorLifecycleRounding,
    FootprintUnion,
    HamiltonianDomainResources,
    HamiltonianRole,
    IncidentContactsAffectedPlan,
    IncidentRelationshipFootprint,
    IncidentRelationshipsAffectedPlan,
    InitializeLifecycleState,
    IteratedSiteAssignmentEffect,
    IterationSiteFootprintAnchor,
    IterationStageSite,
    LifecycleCadenceCode,
    LifecycleConflictCode,
    LifecycleDescriptor,
    LifecycleDomainCode,
    LifecycleEffectCode,
    LifecycleEvaluatorStorage,
    LifecycleExecutionPlan,
    LifecycleInadmissibilityDisposition,
    LifecycleOwnershipAction,
    LifecycleOwnershipRule,
    LifecyclePartitionCode,
    LifecyclePlacementCode,
    LifecycleRelationStorage,
    LifecycleRelationshipAction,
    LifecycleRelationshipRule,
    LifecycleRoundingCode,
    LifecycleSideCode,
    LifecycleSiteSelection,
    LifecycleStateAction,
    LifecycleStateRoleCode,
    LifecycleStateRule,
    LifecycleStateRuleStorage,
    LifecycleWorkspaceOperation,
    LiteralExpression,
    ModelLifecycleDomain,
    ModelAssignmentEffect,
    ModelFootprint,
    ModelStageSite,
    NearestLifecycleRounding,
    NoLifecycleExecutionPlan,
    NoLifecyclePartition,
    NoLifecyclePlacement,
    NoWriteAccess,
    OperationExpression,
    OrderedFold,
    OwnerFootprint,
    OwnershipCountTracker,
    OwnershipTrackerSource,
    OwnershipRelationTrackerSource,
    ParameterDomainConstraint,
    ParameterExpression,
    ParentLifecycleStateRole,
    PeriodicLifecycleCadence,
    PreserveCompatibleLifecycleRelationship,
    PreserveLifecycleOwnershipState,
    PreserveLifecycleState,
    PreserveParentResetDaughterLifecycleState,
    PersistTrackerCheckpoint,
    PrincipalMajorLifecyclePartition,
    PrincipalMinorLifecyclePartition,
    ProposalConstraintRole,
    ProposalDescriptor,
    ProposalDriveRole,
    ProposalEnergyDriveRole,
    ProposalModifierRole,
    ProposalSourceFootprintAnchor,
    ProposalTargetFootprintAnchor,
    ProposalTargetStageSite,
    QualifiedResourceIdentity,
    QualifiedTrackerKey,
    QualifiedTrackerOperation,
    RandomPlaneLifecyclePartition,
    RedrawDaughtersLifecycleState,
    RejectIncompatibleLifecycleRelationship,
    RejectLifecycleConflicts,
    RejectWhileLinkedLifecycleRelationship,
    RelationshipCreateEffect,
    RelationshipEnergyDomainPlan,
    RelationshipRemoveEffect,
    RelationshipRetuneEffect,
    ReconstructTrackerCheckpoint,
    RelationshipStoreSchema,
    RemoveCellLifecycleEffect,
    RemoveIncidentLifecycleRelationship,
    RemoveIncompatibleLifecycleRelationship,
    ResetBothLifecycleState,
    ResetLifecycleState,
    ResourceAccess,
    RetireCellLifecycleEffect,
    RetireToLifecycleState,
    SeedAtLifecyclePlacement,
    SeedStencilLifecyclePlacement,
    ShiftAppendEffect,
    SiteAssignmentEffect,
    SiteEnergyDomainPlan,
    SourceLifecycleStateRole,
    SourceTargetOwnerUpdateBound,
    SourceTargetScalarDelta,
    SourceTargetCellsAffectedPlan,
    SpecifiedNormalLifecyclePartition,
    SplitConservativelyLifecycleState,
    StablePriorityLifecycleConflicts,
    StableRandomLifecycleSide,
    StageDescriptorGroup,
    StageExecutionPlan,
    StateBlockSchema,
    StateExpression,
    StateHandle,
    StateLayout,
    StaticEvaluator,
    TargetSiteAffectedPlan,
    NeighborhoodSitesAffectedPlan,
    TrackerContract,
    TrackerExecutionPlan,
    TrackerSourceView,
    TrackerSupport,
    TransformDaughtersLifecycleState,
    TransformLifecycleState,
    TransitionCellLifecycleEffect,
    UnsupportedLifecycleState,
    WorkspaceHandle,
    WorkspaceLayout,
    WorkspaceSchema,
    LatticeLinearTrackerCost,
    OwnerMomentsDelta,
    OwnerScalarDelta,
    allocate_auxiliary_state,
    copy_auxiliary_state,
    descriptor_adapt,
    descriptor_checkpoint_reconstruct,
    descriptor_inspection,
    descriptor_payload_adapt,
    descriptor_payload_checkpoint_encode,
    descriptor_payload_checkpoint_reconstruct,
    descriptor_payload_inspection,
    descriptor_plan_report,
    descriptor_resource_access,
    evaluator_node_count,
    handle_bank,
    handle_slot,
    initialization_bounded,
    lifecycle_action_identity,
    lifecycle_anchor,
    lifecycle_before_state_value,
    lifecycle_destination_cell,
    lifecycle_destination_generation,
    lifecycle_occurrence,
    lifecycle_plan_report,
    lifecycle_planned_state_value,
    lifecycle_site,
    lifecycle_source_cell,
    lifecycle_source_generation,
    lifecycle_source_identity,
    lifecycle_state_identity,
    lifecycle_state_role,
    lifecycle_workspace_capacity,
    lifecycle_workspace_layout,
    lifecycle_workspace_value,
    operation_callable,
    operation_context_supported,
    owner_kind,
    ownership_state,
    program_tracker_values,
    proposal_relation_count,
    proposal_relation_neighbor_owner,
    proposal_relation_neighbor_site,
    proposal_site_owner,
    proposal_source_kind,
    proposal_source_owner,
    proposal_source_site,
    proposal_target_kind,
    proposal_target_owner,
    proposal_target_site,
    qualified_tracker_operation_call,
    relation_count,
    relation_neighbor_site,
    relation_offsets,
    relationship_degree,
    rng_operation_limit,
    site_owner,
    stage_site,
    state_block,
    state_schema_metadata,
    state_value,
    set_lifecycle_workspace_value!,
    tracker_contract,
    tracker_adapt,
    tracker_checkpoint_policy,
    tracker_concurrency,
    tracker_inspection,
    tracker_instances,
    tracker_operation_value,
    tracker_proposal_delta,
    tracker_quantity,
    tracker_quantities,
    tracker_rebuild,
    tracker_recompute,
    tracker_source_view,
    tracker_storage,
    tracker_support,
    update_program_descriptor_state!,
    validate_parameters

public AbstractCompiledStage, AbstractContextualOperation
public AbstractEvaluatorExecutionContext, AbstractProbeEvaluationContext
public AbstractHamiltonianEvaluationContext, AbstractProposalEvaluationContext
public AbstractSiteStageEvaluationContext, AbstractRelationshipStageEvaluationContext
public AbstractLifecycleTriggerEvaluationContext
public AbstractLifecyclePlacementEvaluationContext
public AbstractLifecyclePartitionEvaluationContext
public AbstractLifecycleStateTransformEvaluationContext
public AbstractStaticExpression, AbstractFootprint, AbstractStageSiteSelector
public AbstractProposalRole, AbstractTrackerDescriptor
public AbstractTrackerCheckpointPolicy, AbstractTrackerConcurrency
public AbstractTrackerCost, AbstractTrackerDelta, AbstractTrackerSource
public AbstractTrackerStorage, AbstractTrackerUpdateBound
public AbstractTrackerVisibility
public CompiledPottsProgram, CompiledScalar, CompiledStageDescriptor
public StaticEvaluator, LiteralExpression, ParameterExpression, ContextExpression
public StateExpression, OperationExpression, OrderedFold, ContextOperation
public StateHandle, WorkspaceHandle, StateBlockSchema, WorkspaceSchema
public StateLayout, WorkspaceLayout, QualifiedResourceIdentity
public ResourceAccess, EmptyFootprint, ModelFootprint, ContactFootprint
public FiniteSpatialFootprint
public FootprintUnion, IncidentRelationshipFootprint, OwnerFootprint
public ProposalSourceFootprintAnchor, ProposalTargetFootprintAnchor
public IterationSiteFootprintAnchor, BoundSiteFootprintAnchor
public DescriptorSupport, DescriptorLaunch, DescriptorGroup
public DescriptorKernelStrategy, DescriptorExecutionPlan
public ProposalDescriptor, ConstraintGroup, ParameterDomainConstraint
public HamiltonianDomainResources, HamiltonianRole
public ProposalDriveRole, ProposalEnergyDriveRole, ProposalConstraintRole
public ProposalModifierRole, SiteEnergyDomainPlan, CellEnergyDomainPlan
public ContactEnergyDomainPlan, RelationshipEnergyDomainPlan
public TargetSiteAffectedPlan, SourceTargetCellsAffectedPlan
public NeighborhoodSitesAffectedPlan
public IncidentContactsAffectedPlan, IncidentRelationshipsAffectedPlan
public AcceptedCopyStage, AfterMCSStage, ProposalTargetStageSite
public IterationStageSite, ModelStageSite, SiteAssignmentEffect
public ModelAssignmentEffect, IteratedSiteAssignmentEffect
public ShiftAppendEffect, RelationshipCreateEffect, RelationshipRemoveEffect
public RelationshipRetuneEffect, StageDescriptorGroup, StageExecutionPlan
public NoWriteAccess, ExclusiveWriteAccess, CommutativeIntegerWriteAccess
public DeferredRequestWriteAccess, RelationshipStoreSchema
public OwnershipCountTracker, CellSurfaceTracker, CellMomentsTracker
public DenseOwnerScalarStorage, DenseOwnerMomentsStorage, DenseScalarTrackerGroup
public OwnershipTrackerSource, OwnershipRelationTrackerSource
public AcceptedCommitTrackerVisibility
public ClaimedOwnerExclusiveTrackerConcurrency, SourceTargetOwnerUpdateBound
public PersistTrackerCheckpoint, ReconstructTrackerCheckpoint
public ConstantTrackerCost, DimensionSquaredTrackerCost
public BoundedNeighborhoodTrackerCost, LatticeLinearTrackerCost
public OwnerScalarDelta, SourceTargetScalarDelta, OwnerMomentsDelta
public TrackerSourceView, TrackerSupport, QualifiedTrackerKey
public QualifiedTrackerOperation, TrackerContract, TrackerExecutionPlan
public LifecycleDomainCode, ModelLifecycleDomain, CellKindLifecycleDomain
public LifecycleCadenceCode, EveryMCSLifecycleCadence, AtMCSLifecycleCadence
public PeriodicLifecycleCadence, LifecycleEffectCode
public CreateCellLifecycleEffect, RemoveCellLifecycleEffect
public RetireCellLifecycleEffect, TransitionCellLifecycleEffect
public DivideCellLifecycleEffect, LifecycleInadmissibilityDisposition
public FilterLifecycleInadmissible, ErrorLifecycleInadmissible
public LifecycleConflictCode, RejectLifecycleConflicts
public StablePriorityLifecycleConflicts, LifecyclePlacementCode
public NoLifecyclePlacement, SeedAtLifecyclePlacement
public SeedStencilLifecyclePlacement, ExternalLifecyclePlacement
public LifecyclePartitionCode, NoLifecyclePartition
public RandomPlaneLifecyclePartition, PrincipalMajorLifecyclePartition
public PrincipalMinorLifecyclePartition, SpecifiedNormalLifecyclePartition
public ExternalLifecyclePartition, LifecycleSideCode
public CanonicalLifecycleSide, StableRandomLifecycleSide
public LifecycleStateAction, InitializeLifecycleState
public LifecycleStateRoleCode, SourceLifecycleStateRole
public DestinationLifecycleStateRole, ParentLifecycleStateRole
public DaughterLifecycleStateRole
public UnsupportedLifecycleState, RetireToLifecycleState, PreserveLifecycleState
public ResetLifecycleState, TransformLifecycleState, CopyDaughtersLifecycleState
public PreserveParentResetDaughterLifecycleState, ResetBothLifecycleState
public SplitConservativelyLifecycleState, TransformDaughtersLifecycleState
public RedrawDaughtersLifecycleState, LifecycleRoundingCode
public ExactLifecycleRounding, FloorLifecycleRounding
public CeilLifecycleRounding, NearestLifecycleRounding
public LifecycleRelationshipAction, RejectWhileLinkedLifecycleRelationship
public RemoveIncidentLifecycleRelationship, PreserveCompatibleLifecycleRelationship
public RemoveIncompatibleLifecycleRelationship, RejectIncompatibleLifecycleRelationship
public LifecycleOwnershipAction, PreserveLifecycleOwnershipState
public ClearLifecycleOwnershipState, AbstractLifecycleSiteSelection
public LifecycleSiteSelection
public AbstractLifecycleExecutionPlan, NoLifecycleExecutionPlan
public LifecycleDescriptor, LifecycleExecutionPlan, LifecycleEvaluatorStorage
public LifecycleStateRule, LifecycleStateRuleStorage
public LifecycleRelationshipRule, LifecycleOwnershipRule
public LifecycleRelationStorage, LifecycleWorkspaceOperation
public EmptyDescriptorPayload
public allocate_auxiliary_state, copy_auxiliary_state
public descriptor_adapt, descriptor_checkpoint_reconstruct
public descriptor_inspection, descriptor_payload_adapt
public descriptor_payload_checkpoint_encode
public descriptor_payload_checkpoint_reconstruct, descriptor_payload_inspection
public descriptor_plan_report, descriptor_resource_access
public evaluator_node_count, handle_bank, handle_slot, initialization_bounded
public lifecycle_action_identity, lifecycle_anchor
public lifecycle_before_state_value, lifecycle_destination_cell
public lifecycle_destination_generation, lifecycle_occurrence
public lifecycle_plan_report, lifecycle_planned_state_value, lifecycle_site
public lifecycle_source_cell, lifecycle_source_generation
public lifecycle_source_identity, lifecycle_state_identity, lifecycle_state_role
public lifecycle_workspace_capacity, lifecycle_workspace_layout
public lifecycle_workspace_value, set_lifecycle_workspace_value!
public operation_callable, operation_context_supported
public owner_kind, ownership_state, program_tracker_values
public proposal_relation_count, proposal_relation_neighbor_owner
public proposal_relation_neighbor_site, proposal_site_owner
public proposal_source_kind, proposal_source_owner, proposal_source_site
public proposal_target_kind, proposal_target_owner, proposal_target_site
public qualified_tracker_operation_call
public relation_count, relation_neighbor_site, relation_offsets
public relationship_degree, rng_operation_limit, site_owner, stage_site
public state_block, state_schema_metadata, state_value
public tracker_contract, tracker_adapt, tracker_checkpoint_policy
public tracker_concurrency, tracker_inspection, tracker_instances
public tracker_operation_value, tracker_proposal_delta, tracker_quantity
public tracker_quantities, tracker_rebuild, tracker_recompute
public tracker_source_view, tracker_storage, tracker_support
public update_program_descriptor_state!, validate_parameters

end
