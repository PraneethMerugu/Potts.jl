module ProcessBigraphs

import ACSets
import Catlab
using SHA
using ACSets: BasicSchema, @acset_type

include("errors.jl")
include("paths.jl")
include("time.jl")
include("canonical.jl")
include("schemas.jl")
include("store.jl")
include("effects.jl")
include("capabilities.jl")
include("declarations.jl")
include("algebraic_structure.jl")
include("composites.jl")
include("lowering.jl")
include("runtime.jl")
include("checkpoint.jl")

export ProcessBigraphError
export AbstractPathSegment, NameSegment, IndexSegment, Path,
       path, parentpath, child, isprefixpath, segments
export TimeScale, LogicalTime, Duration, common_timescale,
       logical_time, duration, ticks, physical_value, convert_scale
export canonical_bytes, canonical_fingerprint
export AbstractSchema, BranchSchema, LeafSchema, DynamicDimension,
       schema_at, schema_leaves, validate_value
export CommittedSnapshot, Projection, initial_snapshot, project,
       paths, commit_id, logical_time, snapshot_fingerprint, materialize
export AbstractUpdateLaw, AdditiveUpdate, MultiplicativeUpdate, ReplaceUpdate,
       KeyedUpdate, IndexedUpdate, SetUpdate, StableAppend,
       SetPatch, Delta, delta, law_identity, reconcile
export CapabilitySet, TransferDeclaration, PreflightReport
export PortSpec, InputPort, OutputPort, PortBinding
export AbstractProcess, AbstractStep, ProcessDeclaration, StepDeclaration,
       FixedSchedule, InvocationContext, InvocationResult, PortView,
       ports, capabilities, semantic_version, semantic_parameters, invoke, emit
export ProcessBigraphACSet, CanonicalModel, canonical_model, canonical_structure,
       structural_fingerprint, StructuralEpoch, StructuralProvenance,
       ExecutionPlan, structural_epoch, structural_provenance
export StaticComposite, CompiledComposite, compile_composite, preflight,
       model_fingerprint, step_layers
export SerialRuntime, initialize_runtime, run_until!, current_snapshot,
       settled, event_count
export SettledCheckpoint, checkpoint, restore, checkpoint_fingerprint

end
