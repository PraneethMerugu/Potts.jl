# CorePotts V1 program ownership map. Each included file owns one runtime layer;
# this file deliberately contains no executable implementation.

include("relationships.jl")
include("runtime.jl")
include("../execution/program_rng.jl")
include("../execution/proposal_context.jl")
include("../execution/lifecycle_context.jl")
include("../execution/lifecycle_workspace.jl")
include("../execution/lifecycle_request_emission.jl")
include("../execution/lifecycle_planning.jl")
include("../execution/lifecycle_conflicts.jl")
include("../execution/lifecycle_commit.jl")
include("../execution/lifecycle_validation.jl")
include("../execution/lifecycle_execution.jl")
include("../execution/stage_runtime.jl")
include("../execution/checkerboard_program.jl")
include("../execution/sequential_program.jl")
