using Chairmarks
using CorePotts
using Potts
using Test

include(joinpath(
    pkgdir(Potts), "test", "fixtures", "site_aggregates.jl",
))

function benchmark_problem(model)
    problem = model.problem
    return PottsProblem(
        problem.system,
        problem.u0,
        (0, typemax(Int));
        p = problem.p,
        seed = problem.seed,
        replica = problem.replica,
        repeat = problem.repeat,
        policies = problem.policies,
    )
end

function timed_record(result)
    return (
        seconds = result.time,
        allocation_bytes = result.bytes,
        compile_seconds = result.compile_time,
        recompile_seconds = result.recompile_time,
    )
end

function advance_core!(integrator)
    CorePotts.advance_mcs!(integrator.runtime)
    return integrator
end

authoring = @timed _site_aggregate_problem(; gain_default = 2.0)
problem_construction = @timed benchmark_problem(authoring.value)
preparation = @timed init(
    problem_construction.value,
    CheckerboardSweepCPM();
    scalar_type = Float32,
    save_everystep = false,
)
integrator = preparation.value
first_step = @timed step!(integrator)
Array(integrator.u[:amount]) == Float32[6, 6, 0] || error(
    "resolved aggregate benchmark failed its numerical oracle",
)
warm_public_step = @be step!($integrator) evals=1 seconds=1

core_integrator = init(
    benchmark_problem(_site_aggregate_problem(; gain_default = 2.0)),
    CheckerboardSweepCPM();
    scalar_type = Float32,
    save_everystep = false,
)
advance_core!(core_integrator)
warm_core_step = @be advance_core!($core_integrator) evals=1 seconds=1

source_model = _site_aggregate_problem(; gain_default = 2.0)
source_integrator = init(
    benchmark_problem(source_model),
    CheckerboardSweepCPM();
    scalar_type = Float32,
    save_everystep = false,
)
source_setter = setu(source_integrator, source_model.signal)
source_values = fill(5.0f0, 2, 2)
first_source_update = @timed source_setter(source_integrator, source_values)
warm_source_update = @be $source_setter($source_integrator, $source_values) evals=1 seconds=1

parameter_setter = setp(source_integrator, source_model.gain)
first_parameter_update = @timed parameter_setter(source_integrator, 3.0f0)
warm_parameter_update = @be $parameter_setter($source_integrator, 3.0f0) evals=1 seconds=1

println("resolved_aggregate_contract")
println((;
    julia = VERSION,
    chairmarks = pkgversion(Chairmarks),
    potts = pkgversion(Potts),
    corepotts = pkgversion(CorePotts),
    dynamicquantities = pkgversion(DynamicQuantities),
    localmath = pkgversion(LocalMath),
    modelingtoolkitbase = pkgversion(ModelingToolkitBase),
    symbolics = pkgversion(Symbolics),
    authoring = timed_record(authoring),
    problem_construction = timed_record(problem_construction),
    preparation = timed_record(preparation),
    first_step = timed_record(first_step),
    first_source_update = timed_record(first_source_update),
    first_parameter_update = timed_record(first_parameter_update),
))
println("warm_public_step=")
display(warm_public_step)
println("warm_core_step=")
display(warm_core_step)
println("warm_source_update=")
display(warm_source_update)
println("warm_parameter_update=")
display(warm_parameter_update)
