using Metal
using Potts

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

# Keep the benchmark fixture identical to the executable qualification row.
include("native_component_execution.jl")

problem, path, _ = _metal_per_cell_fixture()
problem = remake(problem; tspan = (0, 7))
profile = _metal_profile(path, 4)
integrator = init(
    problem,
    CheckerboardSweepCPM();
    backend = Potts.MetalBackend(),
    scalar_type = Float32,
    native_profiles = (profile,),
    save_start = false,
)

# Compile and execute one complete public coupled transaction before measuring.
step!(integrator)
GC.gc()
timed = @timed for _ in 1:6
    step!(integrator)
end
execution = _test_checkerboard_execution(integrator.runtime)
println((;
    julia = VERSION,
    metal = Base.pkgversion(Metal),
    device = Metal.device().name,
    fixture = :per_cell_metal_native_ode_exact_replay,
    live_lanes = 2,
    capacity = 4,
    measured_mcs = 6,
    seconds = timed.time,
    seconds_per_mcs = timed.time / 6,
    allocations = timed.bytes,
    gc_seconds = timed.gctime,
    settlements = execution.settlement_count,
    synchronizations = execution.synchronization_count,
    control_transfers = execution.control_transfer_count,
    snapshot_transfers = execution.snapshot_transfer_count,
    lifecycle_transfers = execution.lifecycle_transfer_count,
))
