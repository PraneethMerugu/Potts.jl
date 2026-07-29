const ROOT = normpath(joinpath(@__DIR__, ".."))

const CHECKERS = (
    "check_consolidation_naming.jl",
    "check_consolidation_duplication.jl",
)

failures = String[]
for checker in CHECKERS
    command = `$(Base.julia_cmd()) --startup-file=no $(joinpath(ROOT, "scripts", checker)) --check-baseline`
    println("Checking generated baseline freshness with ", checker)
    try
        run(command)
    catch exception
        exception isa ProcessFailedException || rethrow()
        push!(failures, checker)
    end
end

isempty(failures) || error(
    "Generated project baselines are stale in $(length(failures)) checker(s): " *
    join(failures, ", ") *
    ". Run scripts/update_project_integrity_baselines.jl and review the diff.")
println("Generated project baselines are fresh.")
