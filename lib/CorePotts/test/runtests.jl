using Aqua
using Test
import CorePotts
import LocalWorksets

include("test_api_boundary.jl")
include("test_rng_contract.jl")
include("test_scientific_reference.jl")
include("test_program_v1.jl")
include("test_surface_tracker_contract.jl")
include("test_scientific_geometry_contract.jl")
include("test_relationship_access_contract.jl")
include("test_descriptor_state_spi.jl")
include("test_acceptance.jl")
include("test_capabilities.jl")
include("test_lifecycle_receipts.jl")

@testset "CorePotts package quality" begin
    Aqua.test_all(CorePotts; ambiguities = false)
end

# Exact broad-method replacements are irreversible in a Julia process. Run
# each post-submission adapter attack in a fresh process after all other tests.
include("test_localworksets_adapter_worlds.jl")
