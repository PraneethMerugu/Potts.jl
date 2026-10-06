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
# the backend named by POTTS_GPU ("metal" or "rocm"; D-157). Unset, it is the platform's own:
# Metal on macOS, ROCm elsewhere.
if GROUP == "GPU"
    gpu = lowercase(get(ENV, "POTTS_GPU", ""))
    isempty(gpu) && (gpu = Sys.isapple() ? "metal" : "rocm")
    gpu in ("metal", "rocm") || error("GROUP=GPU: POTTS_GPU must be \"metal\" or \"rocm\", got \"$gpu\"")
    @info "GROUP=GPU on $gpu"
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = ("POTTS_GPU" => gpu, "COREPOTTS_GPU" => gpu, "COREPOTTS_QA" => "false"))
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl");
        env = ("POTTS_GPU" => gpu, "COREPOTTS_GPU" => gpu, "POTTS_QA" => "false"))
end
