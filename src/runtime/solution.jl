struct PottsSolution{S, P, R, A} <:
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
end

function PottsSolution(
        states::Vector{S},
        times::Vector{Int},
        problem,
        retcode,
        stats,
    ) where {S}
    provenance = (
        executable = executable_fingerprint(problem.executable),
        engine = problem.executable.reports.execution.engine,
        backend = problem.executable.reports.execution.backend,
        scalar_type = problem.executable.reports.execution.scalar_type,
        replay = problem.executable.reports.replay,
        seed = problem.seed,
        replica = problem.replica,
    )
    return PottsSolution{S, typeof(problem), typeof(provenance), Vector{S}}(
        states,
        times,
        problem,
        nothing,
        nothing,
        false,
        retcode,
        stats,
        provenance,
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
    index === nothing && throw(ArgumentError(
        "MCS $(Int(mcs)) is known to the trajectory but was not saved"
    ))
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
    )
end

solve(problem::PottsProblem; kwargs...) = solve!(init(problem; kwargs...))

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

