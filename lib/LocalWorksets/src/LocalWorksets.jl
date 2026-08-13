"""
    LocalWorksets

Backend-portable execution of bounded local operations under centrally
validated topology, storage, conflict, visibility, and determinism contracts.
Domain packages retain physics, clocks, RNG, solver, and commit semantics.
"""
module LocalWorksets

export LocalWork, WorkPlan, PreparedWork, WorkEvent, LocalWorkValidationError
export localwork, topology, plan, prepare, run!, sequence
export value_slot, storage_slot
export independent, combined, resolved, deterministic, fast
export emit, candidate, masked

# `inspect` is public but intentionally not exported: domain packages commonly
# own an `inspect` binding of their own.
public inspect

import Adapt
import Atomix
import KernelAbstractions
import SHA
using KernelAbstractions: @index, @kernel

include("model.jl")
include("planning.jl")
include("preparation.jl")
include("execution.jl")
include("inspection.jl")

include("execution/mechanism_support.jl")
include("execution/validation_support.jl")
include("execution/topology_support.jl")
include("execution/workspace_support.jl")
include("execution/evidence_support.jl")
include("execution/arbitration_support.jl")
include("execution/localworksets_generic.jl")
include("execution/localworksets_combined.jl")
include("execution/localworksets_combined_workspace.jl")
include("execution/localworksets_combined_kernels.jl")
include("execution/localworksets_single_resolved.jl")
include("execution/localworksets_combined_evidence.jl")
include("execution/localworksets_resolved.jl")
include("execution/localworksets_resolved_evidence.jl")
include("execution/localworksets_conjunctive.jl")
include("execution/localworksets_evidence.jl")
include("execution/localworksets_kernelabstractions.jl")

end
