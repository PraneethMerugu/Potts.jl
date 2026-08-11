"""
    LocalWorksets

Backend-portable execution of bounded local operations under centrally
validated topology, storage, conflict, visibility, and determinism contracts.
Domain packages retain physics, clocks, RNG, solver, and commit semantics.
"""
module LocalWorksets

using Adapt
using Atomix
using KernelAbstractions
using SHA

include("model.jl")
include("planning.jl")
include("preparation.jl")
include("execution.jl")
include("inspection.jl")

include("execution/mechanism_support.jl")
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
