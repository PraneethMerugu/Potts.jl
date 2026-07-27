module ProcessBigraphs

import ACSets
import AlgebraicRewriting
import Catlab
using SHA
using ACSets: BasicSchema, @acset_type

include("errors.jl")
include("paths.jl")
include("time.jl")
include("canonical.jl")
include("scheduling.jl")
include("schemas.jl")
include("store.jl")
include("effects.jl")
include("capabilities.jl")
include("logical_codec.jl")
include("engine_protocol.jl")
include("managed_engine.jl")
include("fields.jl")
include("custom_field_adapter.jl")
include("semantic_rng.jl")
include("declarations.jl")
include("continuations.jl")
include("observation.jl")
include("transactions.jl")
include("algebraic_structure.jl")
include("structural_transactions.jl")
include("composites.jl")
include("lowering.jl")
include("composition.jl")
include("executor.jl")
include("runtime.jl")
include("checkpoint.jl")
include("checkpoint_codec.jl")
include("checkpoint_v3.jl")

export ProcessBigraphError
export AbstractPathSegment, NameSegment, IndexSegment, Path,
       path, parentpath, child, isprefixpath, segments
export TimeScale, LogicalTime, Duration, common_timescale,
       logical_time, duration, ticks, physical_value, convert_scale
export canonical_bytes, canonical_fingerprint
export encode_logical_value, decode_logical_value
export AbstractSchema, BranchSchema, LeafSchema, DynamicDimension,
       schema_at, schema_leaves, validate_value
export CommittedSnapshot, Projection, initial_snapshot, project,
       paths, commit_id, logical_time, snapshot_fingerprint, materialize
export AbstractUpdateLaw, AdditiveUpdate, MultiplicativeUpdate, ReplaceUpdate,
       KeyedUpdate, IndexedUpdate, SetUpdate, StableAppend,
       SetPatch, Delta, delta, law_identity, UpdateLawContract,
       update_law_contract, reconcile
export CapabilitySet, TransferDeclaration, PreflightReport
export PortSpec, InputPort, OutputPort, PortBinding
export AbstractProcess, AbstractStep, ProcessDeclaration, StepDeclaration,
       AbstractSchedule, FixedSchedule, AdaptiveSchedule, IterationRegion,
       AbstractHorizonPolicy, ExactHorizon, StopPrior, EventIdentity,
       InvocationContext, InvocationResult, PortView,
       AbstractIntervalInput, FrozenInput, InterpolatedInput, EventUpdatedInput,
       ContinuouslyCallableInput, interval_input, value_at,
       ports, capabilities, semantic_version, semantic_parameters, invoke, emit
export NormalizedRootSeed, RNGAddress, SemanticRNGContext,
       AbstractSemanticRNGContext, ModelRNGContext, ObserverRNGContext,
       semantic_words, semantic_bits, semantic_integer, semantic_uniform,
       philox4x32_10
export AbstractContinuationCodec, NoContinuationCodec,
       CanonicalContinuationCodec, LegacyUntrackedContinuation,
       ContinuationSchema, BoundContinuationSpec,
       AbstractContinuationMigration, IdentityContinuationMigration,
       continuation_schema, stateless_continuation_schema, bind_continuation,
       validate_continuation, alpha_eligible, continuation_fingerprint,
       encode_continuation, decode_continuation, restore_compatible,
       migrate_continuation
export AbstractObserver, AbstractObservationSchedule,
       EventObservationSchedule, PeriodicObservationSchedule,
       AtTimesObservationSchedule, ObservationSchedule,
       RecordSchema, validate_record, ObserverSpec, ObservationPlan,
       ObserverContext, ObservationResult, ObservationRecord, observe,
       observer_semantic_version, observer_semantic_parameters,
       observer_continuation_schema, observation_fingerprint
export ActivationRecord, IterationOutcome, EventRecord,
       RuntimeDiagnostic, FailureInjection
export AbstractExecutor, SerialExecutor, runtime_fingerprint
export ProcessBigraphACSet, CanonicalModel, canonical_model, canonical_structure,
       structural_fingerprint, StructuralEpoch, StructuralProvenance,
       ExecutionPlan, structural_epoch, structural_provenance,
       iteration_regions, execution_plan_fingerprint
export StaticComposite, CompiledComposite, compile_composite, preflight,
       model_fingerprint, step_layers
export BoundaryEndpoint, OpenComposite, CompositeMount, EndpointRef,
       JunctionSpec, CompositeExport, MountGroup, mount_group, CompositionSpec,
       open_composite, compose_open, structured_cospan,
       AnnotatedWiringDiagram, annotated_wiring_diagram, wiring_diagram,
       wiring_profile_version, diagram_fingerprint
export SerialRuntime, initialize_runtime, run_until!, current_snapshot,
       settled, event_count, event_trace, observation_records, last_diagnostic
export SettledCheckpoint, checkpoint, restore, checkpoint_fingerprint
export LogicalCheckpointV2, logical_checkpoint, encode_checkpoint,
       decode_checkpoint
export AbstractEngineAdapter, AbstractEngineInstance, AbstractEngineOperation,
       AbstractCompletionHandle, EngineCapabilities, EngineDeclaration,
       IntervalAdvance, BoundarySolve, DiscreteBatch, EngineInputProjection,
       EngineInvocation, EngineCandidate, EngineEarlyReturn,
       EngineEventRequest, EngineFailure, EngineContinuation,
       EngineTransactionResult, operation_family, operation_start,
       operation_target, projection_value, prepare_engine, stage_operation!,
       complete_operation!, validate_candidate, publish_candidate!,
       discard_candidate!, execute_engine!, engine_continuation_action,
       encode_engine_continuation, decode_engine_continuation,
       aggregate_replay_class
export ManagedEngineRuntime, managed_engine_runtime, managed_engine_time,
       managed_engine_settled, managed_engine_instance,
       advance_managed_engine!, reconstruct_managed_engine!,
       DomainStructuralIdentity, DomainStructuralRequest,
       DomainStructuralDisposition, DomainStructuralSelection,
       select_domain_structural_requests
export FieldGeometry, FieldBoundary, FieldDescriptor, FieldState,
       FieldSampler, FieldDeposition, FieldExchange, FieldExchangeResult,
       FieldAccounting, FieldIterationRegion, NamedFieldOperation,
       FieldSplitPlan, periodic_field_boundaries, field_values,
       sample_field, deposit_field, execute_exchange
export StructuralIdentity, StructuralIdentityRecord, StructuralLineage,
       StructuralCapacity, CompositeDivisionPolicy, DynamicStructuralEpoch,
       AddCompositeRequest, RemoveCompositeRequest, DivideCompositeRequest,
       MoveCompositeRequest, RewireBindingRequest,
       StructuralRequestDisposition, StagedStructuralTransaction,
       dynamic_structural_epoch, structural_identity,
       stage_structural_transaction, publish_structural_transaction,
       structural_structure, structural_lineage,
       StructuralEpochCheckpoint, structural_checkpoint,
       restore_structural_checkpoint
export CheckpointComponent, LogicalCheckpointV3,
       RestoredPhase16Checkpoint, AbstractLegacyCheckpointConverter,
       phase16_checkpoint, decode_phase16_checkpoint,
       restore_phase16_checkpoint, convert_legacy_checkpoint
export BoundedCartesianFieldProblem, IndependentCustomFieldAdapter,
       IndependentCustomFieldInstance, independent_custom_field_declaration,
       custom_field_snapshot, field_engine_snapshot,
       sciml_field_adapter, sciml_field_declaration

end
