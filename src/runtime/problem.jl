struct PottsProblem{E, I, P} <: SciMLBase.AbstractSciMLProblem
    executable::E
    initial::I
    tspan::Tuple{Int, Int}
    parameters::P
    seed::UInt64
    replica::UInt32
    ensemble_repeat::UInt32
end

function _normalize_seed(seed::Integer)
    seed >= 0 || throw(ArgumentError("seed must be nonnegative"))
    seed <= typemax(UInt64) || throw(ArgumentError("seed exceeds UInt64"))
    return UInt64(seed)
end

function _normalize_replica(replica::Integer)
    1 <= replica <= typemax(UInt32) ||
        throw(ArgumentError("replica must be in 1:$(typemax(UInt32))"))
    return UInt32(replica)
end

function _normalize_ensemble_repeat(repeat::Integer)
    1 <= repeat <= typemax(UInt32) ||
        throw(ArgumentError("ensemble repeat must be in 1:$(typemax(UInt32))"))
    return UInt32(repeat)
end

function _normalize_tspan(tspan)
    tspan isa Tuple && length(tspan) == 2 &&
        all(value -> value isa Integer, tspan) ||
        throw(ArgumentError("Potts time span must be two integer MCS boundaries"))
    first_time, last_time = Int.(tspan)
    0 <= first_time <= last_time ||
        throw(ArgumentError("Potts time span must satisfy 0 ≤ t0 ≤ t1"))
    return (first_time, last_time)
end

"""
    PottsProblem(executable, initial, tspan; p=[], seed, replica=1)

Bind concrete initial data and stochastic identity to a reusable executable.
The seed is mandatory; execution choices cannot be changed here.
"""
function PottsProblem(
        executable::PottsExecutable,
        initial::PottsInitialState,
        tspan;
        p = (),
        seed,
        replica::Integer = 1,
    )
    normalized_span = _normalize_tspan(tspan)
    normalized_parameters = _normalize_parameters(executable, p)
    normalized_seed = _normalize_seed(seed)
    normalized_replica = _normalize_replica(replica)
    # Validate and defensively realize now, before any mutable run exists.
    core_initial = _core_initial_state(
        executable, initial, normalized_seed, normalized_replica
    )
    CorePotts.initialize_program(
        executable.core_program,
        core_initial,
        collect(normalized_parameters.values),
        normalized_seed,
        normalized_replica;
        initial_mcs = normalized_span[1],
    )
    return PottsProblem(
        executable,
        _defensive_copy(initial),
        normalized_span,
        normalized_parameters,
        normalized_seed,
        normalized_replica,
        UInt32(1),
    )
end

function _with_ensemble_context(
        problem::PottsProblem,
        replica::Integer,
        repeat::Integer,
    )
    return PottsProblem(
        problem.executable,
        _defensive_copy(problem.initial),
        problem.tspan,
        problem.parameters,
        problem.seed,
        _normalize_replica(replica),
        _normalize_ensemble_repeat(repeat),
    )
end

function _overlay_initial_values(existing, replacements)
    result = Pair{Any, Any}[
        _defensive_copy(first(pair)) => _defensive_copy(last(pair))
        for pair in existing
    ]
    for replacement in replacements
        key = first(replacement)
        index = findfirst(pair -> isequal(first(pair), key), result)
        copied = _defensive_copy(key) =>
                 _defensive_copy(last(replacement))
        if index === nothing
            push!(result, copied)
        else
            result[index] = copied
        end
    end
    return Tuple(result)
end

function remake(
        problem::PottsProblem;
        u0 = missing,
        p = missing,
        tspan = missing,
        seed = missing,
        replica = missing,
        kwargs...,
    )
    isempty(kwargs) || throw(ArgumentError(
        "PottsProblem remake accepts only u0, p, tspan, seed, and replica"
    ))
    initial = if ismissing(u0)
        problem.initial
    elseif u0 isa PottsInitialState
        u0
    else
        pairs = _initial_value_pairs(u0)
        PottsInitialState(
            ownership = problem.initial.ownership,
            values = _overlay_initial_values(problem.initial.values, pairs),
        )
    end
    parameter_values = if ismissing(p)
        Tuple(
            entry.name => problem.parameters.values[entry.index]
            for entry in problem.executable.parameter_manifest
        )
    else
        p
    end
    return PottsProblem(
        problem.executable,
        initial,
        ismissing(tspan) ? problem.tspan : tspan;
        p = parameter_values,
        seed = ismissing(seed) ? problem.seed : seed,
        replica = ismissing(replica) ? problem.replica : replica,
    )
end

function Base.show(io::IO, problem::PottsProblem)
    print(
        io,
        "PottsProblem(",
        problem.tspan[1],
        ":",
        problem.tspan[2],
        " MCS; replica=",
        problem.replica,
        ")",
    )
end
