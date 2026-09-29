# Test entry point for the whole monorepo.
#   GROUP=All (default) | Potts | CorePotts | LocalMath | MakiePotts | GPU | Reference
# Each group runs in the shared workspace environment of its own test project.
const GROUP = get(ENV, "GROUP", "All")
const ROOT = dirname(@__DIR__)

function run_group(project, file; env = ())
    cmd = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$project $file`, env...)
    @info "Running $(relpath(file, ROOT))"
    run(cmd)
end

GROUP in ("All", "LocalMath") &&
    run_group(joinpath(ROOT, "lib/LocalMath/test"), joinpath(ROOT, "lib/LocalMath/test/runtests.jl"))
GROUP in ("All", "CorePotts") &&
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl"))
GROUP in ("All", "MakiePotts") &&
    run_group(joinpath(ROOT, "lib/MakiePotts/test"), joinpath(ROOT, "lib/MakiePotts/test/runtests.jl"))
GROUP in ("All", "Potts") &&
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl"))
# Device group (not part of All): the CorePotts suite plus its Metal tests.
GROUP == "GPU" &&
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = ("COREPOTTS_GPU" => "metal", "COREPOTTS_QA" => "false"))
GROUP == "GPU" &&
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl");
        env = ("POTTS_GPU" => "metal", "POTTS_QA" => "false"))
# Legacy reference stack (D-021): not part of All; needs its own pinned environment.
GROUP == "Reference" &&
    run_group(joinpath(ROOT, "reference"), joinpath(ROOT, "reference/graner.jl"))
