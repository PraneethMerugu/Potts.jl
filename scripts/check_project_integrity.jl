const ROOT = normpath(joinpath(@__DIR__, ".."))

const CHECKERS = (
    "check_structure.jl",
    "check_makiepotts_contract.jl",
    "check_makiepotts_release.jl",
    "check_legacy_containment.jl",
    "check_consolidation_naming.jl",
    "check_consolidation_tests.jl",
    "check_consolidation_architecture.jl",
    "check_consolidation_duplication.jl",
    "check_consolidation_api.jl",
    "check_process_bigraphs.jl",
)

failures = String[]
for checker in CHECKERS
    command = `$(Base.julia_cmd()) --startup-file=no $(joinpath(ROOT, "scripts", checker))`
    println("Running ", checker)
    try
        run(command)
    catch exception
        exception isa ProcessFailedException || rethrow()
        push!(failures, checker)
    end
end

isempty(failures) || error(
    "Project integrity failed in $(length(failures)) checker(s): " *
    join(failures, ", "))
println("Project integrity checks passed.")
