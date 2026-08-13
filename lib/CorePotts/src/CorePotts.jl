module CorePotts

import LinearAlgebra
import SHA
import AcceleratedKernels
import Adapt
import Atomix
import KernelAbstractions
using KernelAbstractions: @index, @kernel
import LocalWorksets

const RNG_CONTRACT_VERSION = v"1.2.0"
const RNG_LOWERING_IDENTITY =
    :philox4x32x10_semantic_address_fisher_yates_v1

"""Return the exact RNG contract and lowering identity admitted by this Core build."""
rng_contract_identity() = (
    contract_version = RNG_CONTRACT_VERSION,
    lowering_identity = RNG_LOWERING_IDENTITY,
)

public LocalWorksets

# Declared before program/types.jl so the compiled program can own the generic
# lifecycle boundary while its concrete plan is defined with the execution IR.
abstract type AbstractLifecycleExecutionPlan end
struct NoLifecycleExecutionPlan <: AbstractLifecycleExecutionPlan end

include("rng/semantic.jl")
include("execution/static_evaluator.jl")
include("execution/storage_schema.jl")
include("execution/storage_runtime.jl")
include("execution/descriptor_protocol.jl")
include("execution/domain_resources.jl")
include("execution/descriptor_plan.jl")
include("execution/tracker_plan.jl")
include("program/checkerboard_plan.jl")
include("program/types.jl")
include("execution/stage_plan.jl")
include("execution/lifecycle_plan.jl")
include("program/capabilities.jl")
include("execution/lifecycle_status.jl")
include("execution/acceptance.jl")
include("program/v1.jl")
include("execution/hamiltonian_runtime.jl")

include("compiler_spi.jl")
include("backend_spi.jl")

public CompilerSPI, BackendSPI

# Stable package-level runtime boundary. Compiler and backend implementation
# details are public only through their explicit SPI modules above.
public ProgramInitialState, ProgramSnapshot, ProgramRuntime
public ProgramFailureReport, program_failed, program_failure_report
public ProgramSettlementReceipt
public initialize_program, program_snapshot, advance_mcs!
public update_program_parameters!, program_execution_report
public program_capability_report
public ProgramCheckpoint, program_checkpoint
public restore_program_checkpoint

# Generation-safe lifecycle identity and immutable receipt boundary.
public CellIdentity, QualifiedLifecycleRequestIdentity
public AbstractLifecycleEvent, LifecycleEvent, LifecycleReceipt
public MaybeLifecycleReceipt
public CreateLifecycleEvent, RemoveCellLifecycleEvent, RetireLifecycleEvent
public TransitionLifecycleEvent, DivideLifecycleEvent
public ParentBeforeIdentity, ParentAfterIdentity, DaughterAfterIdentity
public lifecycle_request_identity, lifecycle_events, validate_lifecycle_receipt
public program_lifecycle_receipt

end
