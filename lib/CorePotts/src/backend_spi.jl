"""
Backend and transactional execution protocol for Potts backend extensions.

This namespace is not an end-user modeling API. It owns capability admission,
queue/settlement operations, device adaptation, and unpublished bank swaps.

This is an explicit, flat facade over CorePotts-owned bindings, not a backend
framework or a second implementation. Backend extensions should import only
the smallest required protocol. They must not construct compiler IR through
this namespace. CorePotts remains the authority for execution support and exact
checkpoint replay.
"""
module BackendSPI

import ..CorePotts:
    AbstractBulkComponentStatePolicy,
    AbstractCheckerboardPlan,
    AbstractComponentStateApplicationError,
    AbstractProgramEngine,
    AdaptedBackend,
    AdaptedProgramBackend,
    BulkComponentStatePool,
    BulkComponentStateTransaction,
    CPUBackend,
    CPUProgramBackend,
    CapabilityBackend,
    CapabilityBoundaryTopology,
    CapabilityComponentStateProfile,
    CapabilityEngine,
    CapabilityLifecycleProfile,
    CapabilityMechanismProfile,
    CapabilityMathPolicy,
    CapabilityReplayClass,
    CapabilitySupportStatus,
    CheckerboardEngine,
    CheckerboardPlan,
    CheckerboardProgramEngine,
    CheckerboardWorkspace,
    CheckpointSettlement,
    ClosedBoundary,
    ComponentExchangeSettlement,
    ComponentStateCapacityError,
    DuplicateLifecycleReceiptError,
    ExactConfigurationReplay,
    FinalizationSettlement,
    HostCallbackSettlement,
    IndexMutationSettlement,
    IndexReadSettlement,
    LifecycleReceiptOrderError,
    NoCheckerboardPlan,
    ObservationSettlement,
    OccupiedComponentSlotError,
    PeriodicBoundary,
    ProgramCapabilityError,
    ProgramCapabilityKey,
    ProgramCapabilityReport,
    ProgramExecutionPosition,
    ProgramExecutionStage,
    RelationshipTransactionBuffer,
    CreateRelationshipRequest,
    RemoveRelationshipRequest,
    RetuneRelationshipRequest,
    ProgramRelationshipRequest,
    ProgramRelationshipState,
    ProgramSettlementReason,
    ProgramSettlementRequest,
    ProgramStepTransaction,
    ProgramStatus,
    ProgramStatusCode,
    ProgramStatusDetailCode,
    ProgressSettlement,
    PublicStepSettlement,
    RelationshipFailureDisposition,
    RelationshipFailureError,
    RelationshipFailureFilter,
    SaveSettlement,
    SequentialEngine,
    SequentialProgramEngine,
    StaleCellIdentityError,
    StatisticsSettlement,
    Supported,
    Unsupported,
    abort_component_state_transaction!,
    adapted_device_capability_disposition,
    adapted_device_environment,
    abort_program_step!,
    adapt_checkerboard_workspace,
    adapt_program_runtime,
    apply_lifecycle_receipt!,
    apply_relationship_requests!,
    host_relationship_transaction,
    bulk_component_completed_mcs,
    bulk_component_last_transaction_identity,
    capability_authorizes_execution,
    capability_authorizes_replay,
    capability_key_fingerprint,
    checkerboard_plan_report,
    clone_component_state,
    commit_component_state_transaction!,
    commit_component_state_transactions!,
    commit_program_step!,
    component_identity,
    component_metadata_snapshot,
    component_state_snapshot,
    component_transaction_state,
    copy_component_state!,
    divide_component_state!,
    enqueue_checkerboard_mcs!,
    enqueue_program_mcs!,
    enqueue_program_through!,
    emit_relationship_request!,
    execute_checkerboard_mcs!,
    initialize_component_state!,
    program_backend_name,
    program_initial_descriptor_state,
    program_snapshot_descriptor_state,
    program_step_lifecycle_receipt,
    program_step_parameter_view,
    program_step_snapshot,
    prevalidate_component_state_transaction,
    prevalidate_component_state_transactions,
    prevalidate_program_step_transaction,
    prepare_relationship_transaction!,
    relationship_edge_index,
    publish_component_state_transaction!,
    publish_component_state_transactions!,
    publish_program_step_transaction!,
    remove_component_state!,
    reset_relationship_transaction!,
    retire_component_state!,
    rng_contract_identity,
    settle_program!,
    stage_lifecycle_receipt!,
    stage_program_descriptor_state!,
    stage_program_mcs!,
    stage_program_parameters!,
    supports_queued_program_execution,
    transition_component_state!,
    validate_program_checkpoint,
    validate_component_state,
    with_program_initial_descriptor_state

public AbstractProgramEngine, SequentialProgramEngine, CheckerboardProgramEngine
public CPUProgramBackend, AdaptedProgramBackend
public AbstractCheckerboardPlan, NoCheckerboardPlan, CheckerboardPlan
public CheckerboardWorkspace, adapt_checkerboard_workspace
public execute_checkerboard_mcs!, enqueue_checkerboard_mcs!
public CapabilitySupportStatus, Unsupported, Supported
public CapabilityEngine, SequentialEngine, CheckerboardEngine
public CapabilityBackend, CPUBackend, AdaptedBackend
public CapabilityBoundaryTopology, ClosedBoundary, PeriodicBoundary
public CapabilityReplayClass, ExactConfigurationReplay
public CapabilityMathPolicy, CapabilityLifecycleProfile
public CapabilityComponentStateProfile, CapabilityMechanismProfile
public ProgramCapabilityKey
public ProgramCapabilityReport, ProgramCapabilityError
public capability_authorizes_execution, capability_authorizes_replay
public adapted_device_capability_disposition, capability_key_fingerprint
public adapted_device_environment
public ProgramExecutionPosition, ProgramSettlementReason, ProgramSettlementRequest
public FinalizationSettlement, PublicStepSettlement, SaveSettlement
public HostCallbackSettlement, CheckpointSettlement
public IndexReadSettlement, IndexMutationSettlement
public ComponentExchangeSettlement, ProgressSettlement
public StatisticsSettlement, ObservationSettlement
public supports_queued_program_execution
public enqueue_program_mcs!, enqueue_program_through!, settle_program!
public program_backend_name, adapt_program_runtime, checkerboard_plan_report
public program_initial_descriptor_state, program_snapshot_descriptor_state
public with_program_initial_descriptor_state
public ProgramStatus, ProgramStatusCode, ProgramStatusDetailCode
public ProgramExecutionStage
public ProgramStepTransaction, stage_program_mcs!
public program_step_snapshot, program_step_lifecycle_receipt
public stage_program_parameters!, stage_program_descriptor_state!
public program_step_parameter_view
public prevalidate_program_step_transaction, publish_program_step_transaction!
public commit_program_step!, abort_program_step!
public ProgramRelationshipState, ProgramRelationshipRequest
public RelationshipTransactionBuffer, CreateRelationshipRequest
public RemoveRelationshipRequest, RetuneRelationshipRequest
public emit_relationship_request!, reset_relationship_transaction!
public prepare_relationship_transaction!
public RelationshipFailureDisposition, RelationshipFailureError
public RelationshipFailureFilter, apply_relationship_requests!
public relationship_edge_index, host_relationship_transaction
public AbstractBulkComponentStatePolicy, BulkComponentStatePool
public BulkComponentStateTransaction, AbstractComponentStateApplicationError
public DuplicateLifecycleReceiptError, LifecycleReceiptOrderError
public StaleCellIdentityError, OccupiedComponentSlotError
public ComponentStateCapacityError
public clone_component_state, copy_component_state!, validate_component_state
public initialize_component_state!, remove_component_state!
public retire_component_state!, transition_component_state!
public divide_component_state!, stage_lifecycle_receipt!
public component_transaction_state, prevalidate_component_state_transaction
public prevalidate_component_state_transactions
public publish_component_state_transaction!, publish_component_state_transactions!
public commit_component_state_transaction!, commit_component_state_transactions!
public abort_component_state_transaction!, apply_lifecycle_receipt!
public component_identity, component_state_snapshot
public component_metadata_snapshot
public bulk_component_completed_mcs, bulk_component_last_transaction_identity
public validate_program_checkpoint, rng_contract_identity

end
