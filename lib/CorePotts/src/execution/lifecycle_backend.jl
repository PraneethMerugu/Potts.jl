# Backend lifecycle execution is split by ownership while retaining one include boundary.
include("lifecycle_backend_control.jl")
include("lifecycle_backend_kernels.jl")
include("lifecycle_backend_enqueue.jl")
