# Test entry point for the whole monorepo.
#   GROUP=All (default) | Potts | CorePotts | MakiePotts | PottsModels | GPU
# Each group runs in the shared workspace environment of its own test project.
const GROUP = get(ENV, "GROUP", "All")
const ROOT = dirname(@__DIR__)

function run_group(project, file; env = ())
    cmd = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$project $file`, env...)
    @info "Running $(relpath(file, ROOT))"
    run(cmd)
end

GROUP in ("All", "CorePotts") &&
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl"))
GROUP in ("All", "MakiePotts") &&
    run_group(joinpath(ROOT, "lib/MakiePotts/test"), joinpath(ROOT, "lib/MakiePotts/test/runtests.jl"))
GROUP in ("All", "Potts") &&
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl"))
GROUP in ("All", "PottsModels") &&
    run_group(joinpath(ROOT, "lib/PottsModels/test"), joinpath(ROOT, "lib/PottsModels/test/runtests.jl"))
# Device group (not part of All): the CorePotts and Potts suites plus their device tests, on
# the backend that POTTS_GPU / COREPOTTS_GPU request (test/shared/device_select.jl, D-157).
# Neither set: the platform's own, Metal on macOS and ROCm elsewhere. On ROCm both suites end
# with the full no-`double` scan of their compiled kernels, and a last step checks that every
# CorePotts kernel and launch body was scanned (test/device_coverage.jl).
if GROUP == "GPU"
    include(joinpath(@__DIR__, "shared", "device_select.jl"))
    gpu = PottsDeviceSelect.requested()
    isempty(gpu) && (gpu = Sys.isapple() ? "metal" : "rocm")
    @info "GROUP=GPU on $gpu"
    irdir = mktempdir()
    env = ("POTTS_GPU" => gpu, "COREPOTTS_GPU" => gpu, "POTTS_DEVICE_IR_DIR" => irdir)
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = (env..., "COREPOTTS_QA" => "false"))
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl"); env = (env..., "POTTS_QA" => "false"))
    gpu == "rocm" && run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/device_coverage.jl"); env)
end
