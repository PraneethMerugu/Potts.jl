VERSION == v"1.12.6" ||
    error("Wortel model qualification requires Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    return isnothing(argument) ?
        default : ARGS[argument][(length(prefix) + 1):end]
end

backend = option("backend", "")
profile = option("profile", "paper")
backend == "metal" && (@eval using Metal)
backend == "amdgpu" && (@eval using AMDGPU)

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

qualification = PottsBenchmarks.qualify_wortel_model_backend(
    backend; profile)
println("WORTEL_MODEL_QUALIFICATION=", qualification)
result = PottsBenchmarks.wortel_model_result(
    backend, qualification)
path = PottsBenchmarks.write_wortel_model_result(result)
println("WORTEL_MODEL_RESULT=", path)
