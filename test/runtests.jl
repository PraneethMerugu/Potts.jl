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
# Device group (not part of All): the CorePotts suite plus its Metal tests.
GROUP == "GPU" &&
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = ("COREPOTTS_GPU" => "metal", "COREPOTTS_QA" => "false"))
GROUP == "GPU" &&
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl");
        env = ("POTTS_GPU" => "metal", "POTTS_QA" => "false"))
