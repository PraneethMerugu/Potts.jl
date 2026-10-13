# Test entry point for the whole monorepo.
#   GROUP=All (default) | Potts | CorePotts | MakiePotts | PottsModels | GPU
# Each group runs in the shared workspace environment of its own test project.
const GROUP = get(ENV, "GROUP", "All")
const ROOT = dirname(@__DIR__)

function run_group(project, file, args...; env = ())
    cmd = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$project $file $args`, env...)
    @info "Running $(relpath(file, ROOT)) $(join(map(a -> relpath(a, ROOT), args), ' '))"
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
# Device group (not part of All): the device tests of the CorePotts and Potts suites, on the
# backend that POTTS_GPU / COREPOTTS_GPU request (test/shared/device_select.jl, D-157). The
# suites run through test/shared/device_only.jl, which drops the top-level testsets that name
# no device (the CPU groups run them) and keeps every definition and every device testset;
# POTTS_DEVICE_ONLY=false runs the suites in full, as before.
# Neither set: the platform's own, Metal on macOS and ROCm elsewhere. On ROCm both suites end
# with the full no-`double` scan of their compiled kernels, and a last step checks that every
# CorePotts kernel and launch body was scanned (test/device_coverage.jl).
if GROUP == "GPU"
    include(joinpath(@__DIR__, "shared", "device_select.jl"))
    gpu = PottsDeviceSelect.requested()
    isempty(gpu) && (gpu = Sys.isapple() ? "metal" : "rocm")
    @info "GROUP=GPU on $gpu"
    irdir = get(ENV, "POTTS_DEVICE_IR_DIR", "")       # set: keep the scanned IR there (for comparing runs)
    isempty(irdir) ? (irdir = mktempdir()) : mkpath(irdir)
    env = ("POTTS_GPU" => gpu, "COREPOTTS_GPU" => gpu, "POTTS_DEVICE_IR_DIR" => irdir)
    only = get(ENV, "POTTS_DEVICE_ONLY", "true") == "true"
    suite(project, runner; env) = only ?
        run_group(project, joinpath(ROOT, "test/shared/device_only.jl"), runner; env) : run_group(project, runner; env)
    suite(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = (env..., "COREPOTTS_QA" => "false"))
    suite(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl"); env = (env..., "POTTS_QA" => "false"))
    gpu == "rocm" && run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/device_coverage.jl"); env)
end
