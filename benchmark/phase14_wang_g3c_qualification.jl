VERSION == v"1.12.6" ||
    error("Phase 14 Wang G3-C qualification requires Julia 1.12.6; found $VERSION")

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

qualification =
    PottsBenchmarks.qualify_phase14_wang_g3c_backend(
        backend; profile)
println("PHASE14_WANG_G3C_QUALIFICATION=", qualification)
result = PottsBenchmarks.phase14_wang_g3c_result(
    backend, qualification)
path = PottsBenchmarks.write_phase14_wang_g3c_result(result)
println("PHASE14_WANG_G3C_RESULT=", path)
