"""Timeseries solution containing saved Potts states, statistics, and replay provenance."""
struct PottsSolution{S, P, A, R, H} <:
       SciMLBase.AbstractTimeseriesSolution{S, 1, Vector{S}}
    u::Vector{S}
    t::Vector{Int}
    prob::P
    alg::A
    interp::Nothing
    dense::Bool
    retcode::SciMLBase.ReturnCode.T
    stats::PottsStats
    provenance::R
    parameter_history::H
    failure_report::Any
end

function PottsSolution(integrator::PottsIntegrator)
    problem = integrator.prob
    plan = integrator.plan
    frozen_parameter_history = Tuple(
        time => parameters.values
        for (time, parameters) in integrator.parameter_history
    )
    scheduled_fingerprint = scheduled_system_fingerprint(problem.system)
    profile_fingerprint = _execution_plan_fingerprint(plan)
    provenance = (
        scheduled = scheduled_fingerprint,
        runtime_profile = profile_fingerprint,
        problem = _sha256_hex(
            "potts-problem-v2",
            scheduled_fingerprint,
            _problem_initial_state(problem),
            problem.tspan,
            problem.p.values,
            problem.seed,
            problem.replica,
            problem.repeat,
            problem.policies,
        ),
        algorithm = nameof(typeof(integrator.alg)),
        backend = nameof(typeof(integrator.backend)),
        scalar_type = integrator.scalar_type,
        replay = isempty(integrator.native_profiles) ? plan.reports.replay : (
            class = :exact_pinned_native_profiles,
            cross_engine = false,
            addressed_rng = true,
        ),
        native_profiles = Tuple((
            path = profile.path,
            fingerprint = _native_profile_fingerprint(profile),
            profile_id = profile.profile_id,
            deterministic = profile.deterministic,
            exact_replay = profile.exact_replay,
        ) for profile in integrator.native_profiles),
        capability = integrator.capability_report,
        seed = problem.seed,
        replica = problem.replica,
        repeat = problem.repeat,
        parameter_history = frozen_parameter_history,
    )
    return PottsSolution{
        eltype(integrator.saved_states),
        typeof(problem),
        typeof(integrator.alg),
        typeof(provenance),
        typeof(frozen_parameter_history),
    }(
        copy(integrator.saved_states),
        copy(integrator.saved_times),
        problem,
        integrator.alg,
        nothing,
        false,
        integrator.retcode,
        _integrator_stats(integrator),
        provenance,
        frozen_parameter_history,
        integrator.failure_report,
    )
end

function native_state(
        solution::PottsSolution,
        path;
        index::Integer = lastindex(solution),
    )
    checkbounds(solution.u, index)
    component = _native_component_by_path(solution.prob.system, path)
    logical = _native_state_by_path(solution.u[index].native, path)
    logical isa NativeCellStateSnapshot && throw(ArgumentError(
        "PerCell native state requires a generation-stamped CellIdentity"
    ))
    return native_state_view(component, logical)
end

function native_state(
        solution::PottsSolution,
        path,
        identity::CorePotts.CellIdentity;
        index::Integer = lastindex(solution),
    )
    checkbounds(solution.u, index)
    component = _native_component_by_path(solution.prob.system, path)
    logical = native_state(solution.u[index], path, identity)
    return native_state_view(component, logical)
end

function native_value(
        solution::PottsSolution,
        path,
        symbolic;
        index::Integer = lastindex(solution),
    )
    checkbounds(solution.u, index)
    component = _native_component_by_path(solution.prob.system, path)
    logical = _native_state_by_path(solution.u[index].native, path)
    logical isa NativeCellStateSnapshot && throw(ArgumentError(
        "PerCell native value requires a generation-stamped CellIdentity"
    ))
    return native_component_value(component, logical, symbolic)
end

function native_value(
        solution::PottsSolution,
        path,
        identity::CorePotts.CellIdentity,
        symbolic;
        index::Integer = lastindex(solution),
    )
    checkbounds(solution.u, index)
    component = _native_component_by_path(solution.prob.system, path)
    logical = native_state(solution.u[index], path, identity)
    return native_component_value(component, logical, symbolic)
end

Base.size(solution::PottsSolution) = (length(solution.u),)
Base.length(solution::PottsSolution) = length(solution.u)
# RecursiveArrayTools provides a vararg-Int indexing fallback for SciML
# timeseries solutions.  Keep the ordinary vector index unambiguous for the
# native Int used by `first`, `last`, iteration consumers, and array code.
Base.getindex(solution::PottsSolution, index::Int) = solution.u[index]
Base.getindex(solution::PottsSolution, index::Integer) = solution.u[index]
Base.iterate(solution::PottsSolution, state...) = iterate(solution.u, state...)
Base.firstindex(solution::PottsSolution) = firstindex(solution.u)
Base.lastindex(solution::PottsSolution) = lastindex(solution.u)
Base.eltype(::Type{<:PottsSolution{S}}) where {S} = S

function (solution::PottsSolution)(mcs::Integer; idxs = nothing)
    index = findlast(==(Int(mcs)), solution.t)
    index === nothing && throw(PottsUnsavedTimeError(Int(mcs)))
    state = solution.u[index]
    idxs === nothing && return state
    return state[_state_name(idxs)]
end

function _next_queued_boundary(integrator::PottsIntegrator)
    policy = integrator.policy
    remaining_iterations = policy.maxiters - integrator.iterations
    limit = min(integrator.prob.tspan[2], integrator.t + remaining_iterations)
    !_callbacks_empty(integrator) && return min(limit, integrator.t + 1)
    policy.save_everystep && return min(limit, integrator.t + 1)
    boundary = limit
    for saved_time in policy.saveat
        saved_time > integrator.t || continue
        boundary = min(boundary, saved_time)
        break
    end
    policy.progress &&
        (boundary = min(boundary, integrator.t + policy.progress_steps))
    return boundary
end

function _queued_boundary_reason(integrator::PottsIntegrator, boundary::Int)
    !_callbacks_empty(integrator) &&
        return CorePotts.BackendSPI.HostCallbackSettlement
    policy = integrator.policy
    boundary in policy.saveat && return CorePotts.BackendSPI.SaveSettlement
    policy.save_everystep && return CorePotts.BackendSPI.SaveSettlement
    policy.progress && boundary < integrator.prob.tspan[2] &&
        return CorePotts.BackendSPI.ProgressSettlement
    return CorePotts.BackendSPI.FinalizationSettlement
end

function _advance_queued_boundary!(
        integrator::PottsIntegrator, boundary::Int
    )
    CorePotts.BackendSPI.enqueue_program_through!(integrator.runtime, boundary)
    _request_integrator_settlement!(
        integrator, _queued_boundary_reason(integrator, boundary)
    )
    failure_report = CorePotts.program_failure_report(integrator.runtime)
    if failure_report === nothing
        _run_callbacks!(integrator)
        _save_due(integrator) && _save_current!(integrator)
    end
    return integrator
end

function _solve_queued!(integrator::PottsIntegrator)
    while !integrator.terminated &&
            integrator.retcode == SciMLBase.ReturnCode.Default &&
            integrator.t < integrator.prob.tspan[2] &&
            integrator.iterations < integrator.policy.maxiters
        boundary = _next_queued_boundary(integrator)
        boundary > integrator.t || break
        _advance_queued_boundary!(integrator, boundary)
    end
    return integrator
end

function solve!(integrator::PottsIntegrator)
    try
        # Native components advance from a settled, staged Core snapshot and
        # publish with that Core step.  The Core-only queued fast path cannot
        # represent that coupled boundary.
        if isempty(integrator.native_states) &&
                CorePotts.BackendSPI.supports_queued_program_execution(
                    integrator.runtime
                )
            _solve_queued!(integrator)
        else
            while !integrator.terminated &&
                    integrator.retcode == SciMLBase.ReturnCode.Default &&
                    integrator.t < integrator.prob.tspan[2] &&
                    integrator.iterations < integrator.policy.maxiters
                step!(integrator)
            end
        end
    catch solve_error
        try
            _finalize_callbacks!(integrator)
        catch finalize_error
            throw(CompositeException(solve_error, finalize_error))
        end
        rethrow()
    end
    if integrator.retcode == SciMLBase.ReturnCode.Default
        integrator.retcode = integrator.t == integrator.prob.tspan[2] ?
                             SciMLBase.ReturnCode.Success :
                             SciMLBase.ReturnCode.MaxIters
    end
    integrator.policy.save_end && _save_current!(integrator)
    _finalize_callbacks!(integrator)
    return PottsSolution(integrator)
end

solve(problem::PottsProblem, algorithm::AbstractPottsAlgorithm; kwargs...) =
    solve!(init(problem, algorithm; kwargs...))
solve(problem::PottsProblem; alg = SequentialCPM(), kwargs...) =
    solve(problem, alg; kwargs...)

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
        return _with_ensemble_context(candidate, replica, context.repeat)
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
