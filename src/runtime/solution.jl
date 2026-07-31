struct PottsSolution{S, P, R, A, H} <:
       SciMLBase.AbstractTimeseriesSolution{S, 1, A}
    u::A
    t::Vector{Int}
    prob::P
    alg::Nothing
    interp::Nothing
    dense::Bool
    retcode::SciMLBase.ReturnCode.T
    stats::PottsStats
    provenance::R
    parameter_history::H
end

function PottsSolution(
        states::Vector{S},
        times::Vector{Int},
        problem,
        retcode,
        stats,
        parameter_history,
    ) where {S}
    frozen_parameter_history = Tuple(
        time => parameters.values
        for (time, parameters) in parameter_history
    )
    provenance = (
        executable = executable_fingerprint(problem.executable),
        problem = _sha256_hex(
            "potts-problem-v1",
            executable_fingerprint(problem.executable),
            problem.initial,
            problem.tspan,
            problem.parameters.values,
            problem.seed,
            problem.replica,
            problem.ensemble_repeat,
        ),
        engine = problem.executable.reports.execution.engine,
        backend = problem.executable.reports.execution.backend,
        scalar_type = problem.executable.reports.execution.scalar_type,
        replay = problem.executable.reports.replay,
        seed = problem.seed,
        replica = problem.replica,
        ensemble_repeat = problem.ensemble_repeat,
        parameter_history = frozen_parameter_history,
    )
    return PottsSolution{
        S,
        typeof(problem),
        typeof(provenance),
        Vector{S},
        typeof(frozen_parameter_history),
    }(
        states,
        times,
        problem,
        nothing,
        nothing,
        false,
        retcode,
        stats,
        provenance,
        frozen_parameter_history,
    )
end

Base.size(solution::PottsSolution) = (length(solution.u),)
Base.length(solution::PottsSolution) = length(solution.u)
Base.getindex(solution::PottsSolution, index::Integer) = solution.u[index]
Base.iterate(solution::PottsSolution, state...) = iterate(solution.u, state...)
Base.firstindex(solution::PottsSolution) = firstindex(solution.u)
Base.lastindex(solution::PottsSolution) = lastindex(solution.u)
Base.eltype(::Type{<:PottsSolution{S}}) where {S} = S

function (solution::PottsSolution)(mcs::Integer; idxs = nothing)
    index = findfirst(==(Int(mcs)), solution.t)
    index === nothing && throw(PottsUnsavedTimeError(Int(mcs)))
    state = solution.u[index]
    idxs === nothing && return state
    name = _state_name(idxs)
    return state[name]
end

function solve!(integrator::PottsIntegrator)
    while !integrator.terminated &&
            integrator.t < integrator.prob.tspan[2] &&
            integrator.iterations < integrator.policy.maxiters
        step!(integrator)
    end
    if integrator.retcode == SciMLBase.ReturnCode.Default
        integrator.retcode = integrator.t == integrator.prob.tspan[2] ?
                             SciMLBase.ReturnCode.Success :
                             SciMLBase.ReturnCode.MaxIters
    end
    integrator.policy.save_end && _save_current!(integrator)
    return PottsSolution(
        copy(integrator.saved_states),
        copy(integrator.saved_times),
        integrator.prob,
        integrator.retcode,
        _integrator_stats(integrator),
        integrator.parameter_history,
    )
end

solve(problem::PottsProblem; kwargs...) = solve!(init(problem; kwargs...))
solve(problem::PottsProblem, ::Nothing; kwargs...) = solve(problem; kwargs...)

function SciMLBase.EnsembleProblem(
        problem::PottsProblem;
        prob_func = nothing,
        output_func = nothing,
        reduction = nothing,
        u_init = nothing,
        safetycopy::Bool = prob_func !== nothing,
    )
    wrapped_prob_func = function (template, context)
        candidate = prob_func === nothing ?
                    template : prob_func(template, context)
        candidate isa PottsProblem || throw(ArgumentError(
            "a Potts ensemble prob_func must return PottsProblem"
        ))
        replica = candidate.replica == template.replica ?
                  context.sim_id : candidate.replica
        return _with_ensemble_context(
            candidate, replica, context.repeat
        )
    end
    wrapped_output = output_func === nothing ?
                     ((solution, _) -> (solution, false)) : output_func
    wrapped_reduction = reduction === nothing ?
                        ((accumulator, data, _) -> (
                            append!(accumulator, data), false
                        )) : reduction
    return SciMLBase.EnsembleProblem(
        problem,
        wrapped_prob_func,
        wrapped_output,
        wrapped_reduction,
        u_init,
        safetycopy,
    )
end

function Base.show(io::IO, solution::PottsSolution)
    print(
        io,
        "PottsSolution(",
        first(solution.prob.tspan),
        ":",
        last(solution.prob.tspan),
        " MCS; ",
        length(solution.t),
        " saved, retcode=",
        solution.retcode,
        ")",
    )
end
