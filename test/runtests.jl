# Test entry point for the whole monorepo.
#   GROUP=All (default) | Potts | CorePotts | LocalMath | QA
# Each group runs in the shared workspace environment of its own test project.
const GROUP = get(ENV, "GROUP", "All")
const ROOT = dirname(@__DIR__)

function run_group(project, file)
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project $file`
    @info "Running $(relpath(file, ROOT))"
    run(cmd)
end

GROUP in ("All", "LocalMath") &&
    run_group(joinpath(ROOT, "lib/LocalMath/test"), joinpath(ROOT, "lib/LocalMath/test/runtests.jl"))
GROUP in ("All", "CorePotts") &&
    run_group(joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl"))
GROUP in ("All", "Potts") &&
    run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/potts.jl"))
