const ROOT = normpath(joinpath(@__DIR__, ".."))

const UPDATERS = (
    "check_consolidation_naming.jl",
    "check_consolidation_duplication.jl",
)

for updater in UPDATERS
    command = `$(Base.julia_cmd()) --startup-file=no $(joinpath(ROOT, "scripts", updater)) --update`
    println("Updating generated baseline with ", updater)
    run(command)
end

println()
println("Generated baseline diff summary (review before committing):")
run(`git -C $ROOT diff --stat -- design/evidence/consolidation-naming/historical-artifact-index-v1.toml design/evidence/consolidation-architecture/duplication-v1.toml`)
