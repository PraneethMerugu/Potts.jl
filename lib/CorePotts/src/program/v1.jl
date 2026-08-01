# CorePotts V1 program ownership map. Each included file owns one runtime layer;
# this file deliberately contains no executable implementation.

include("relationships.jl")
include("runtime.jl")
include("../execution/program_rng.jl")
include("../execution/proposal_context.jl")
include("../execution/stage_runtime.jl")
include("../execution/sequential_program.jl")
