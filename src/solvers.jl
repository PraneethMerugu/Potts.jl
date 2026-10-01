# Solver placement (D-075, P6.0c): how each field and ODE is integrated is fixed when the
# problem is built, from the `PottsProblem` keywords `field_solver`, `ode_solver` and
# `solvers`, and compiled into the phase code at the one codegen point (`_phases`). The model
# carries no solver; the algorithms carry none either (D-046). A different scheme is a
# different problem: `remake(prob; field_solver = …)` rebuilds `f` (problem.jl).

const _ODESolver = Union{ExplicitEuler, RK4, Adaptive}

"""
    SolverSpec

The solver keywords of a problem as given (`field_solver`, `ode_solver`, `solvers`: kept for
`remake`, which replaces only the keywords it names) and resolved: `resolved` maps every
integrated variable (each field and each cell or model ODE unknown) by name to its solver,
and `canonical` is the canonical string of that map that the D-016 fingerprint hashes.
"""
struct SolverSpec
    field_solver::Union{Nothing, ExplicitEuler}
    ode_solver::_ODESolver
    solvers::Vector{Pair{Any, Any}}
    resolved::Dict{Symbol, Any}
    canonical::String
end

_solver_name(x) = info(x).name

"""
    _resolve_solvers(c; field_solver = nothing, ode_solver = ExplicitEuler(), solvers = ())

Resolve the solver keywords against compiled model `c`:
- `field_solver` is required when the model has a field (no default: a silent default
  would replace a paper's scheme), and an error without one;
- `ode_solver` (default `ExplicitEuler()`, one step per MCS; D-038) integrates every cell
  and model ODE that `solvers` does not name;
- `solvers = [x => solver, …]` keys integrated variables (symbolic, or by name): an ODE
  unknown takes any `ode_solver`, a field an `ExplicitEuler`.
"""
function _resolve_solvers(c::CompiledPottsSystem; field_solver = nothing, ode_solver = ExplicitEuler(), solvers = ())
    sys = c.sys
    fields = [_solver_name(x) for (x, _) in c.fields]
    odes = [_solver_name(x) for (x, _) in Iterators.flatten((c.cell_odes, c.model_odes))]
    if isempty(fields)
        field_solver === nothing || throw(ArgumentError(
            "`field_solver`: model `$(nameof(sys))` has no field to integrate; remove the keyword"))
    else
        field_solver === nothing && throw(ArgumentError(
            "model `$(nameof(sys))` has the field$(length(fields) == 1 ? "" : "s") " *
            "$(join(("`$n`" for n in fields), ", ")), so `PottsProblem` needs `field_solver = ExplicitEuler(; substeps, lower)` " *
            "(no default, D-075; a published model's docstring gives its value)"))
        field_solver isa ExplicitEuler || throw(ArgumentError(
            "`field_solver` takes an `ExplicitEuler(; substeps, lower)`; got $(repr(field_solver))"))
    end
    ode_solver isa _ODESolver || throw(ArgumentError(
        "`ode_solver` takes `ExplicitEuler(; substeps)`, `RK4(; substeps)` or `Adaptive(alg; …)`; got $(repr(ode_solver))"))
    resolved = Dict{Symbol, Any}()
    foreach(n -> resolved[n] = field_solver, fields)
    foreach(n -> resolved[n] = ode_solver, odes)
    given = Pair{Any, Any}[k => v for (k, v) in (solvers isa AbstractDict ? pairs(solvers) : solvers)]
    named = Set{Symbol}()
    for (k, s) in given
        n = _solver_key(sys, k)
        n in named && throw(ArgumentError("`solvers`: `$n` is given twice"))
        push!(named, n)
        if n in fields
            s isa ExplicitEuler || throw(ArgumentError(
                "`solvers`: the field `$n` takes an `ExplicitEuler(; substeps, lower)`; got $(repr(s))"))
        elseif n in odes
            s isa _ODESolver || throw(ArgumentError(
                "`solvers`: `$n` takes `ExplicitEuler(; substeps)`, `RK4(; substeps)` or `Adaptive(alg; …)`; got $(repr(s))"))
        else
            throw(ArgumentError("`solvers`: `$n` is not integrated (no `D($n) ~ …` equation); the keys are the " *
                                "integrated variables $(join(("`$m`" for m in sort!([fields; odes])), ", "))"))
        end
        resolved[n] = s
    end
    _check_adaptive_draws(c, resolved)
    canonical = join(("$n=$(_canonical(resolved[n]))" for n in sort!(collect(keys(resolved)))), ";")
    return SolverSpec(field_solver, ode_solver, given, resolved, canonical)
end

function _solver_key(sys::PottsSystem, k)
    k isa Symbol && return k
    i = info(k)
    i === nothing && throw(ArgumentError("`solvers`: the key `$k` is not a model quantity; key by the variable (`x => solver`)"))
    i.role in (:param, :kindtable) && throw(ArgumentError(
        "`solvers`: `$(i.name)` is a parameter; the keys are integrated variables"))
    return i.name
end

# A-68: an adaptive step re-evaluates the rate at trial steps, so it cannot replay draws.
function _check_adaptive_draws(c::CompiledPottsSystem, resolved)
    for eq in c.sys.equations
        lhs = _unwrap(eq.lhs)
        (iscall(lhs) && operation(lhs) isa Differential) || continue
        get(resolved, _solver_name(arguments(lhs)[1]), nothing) isa Adaptive || continue
        _has_op(eq.rhs, random_uniform) && _located(c.sys, eq) do
            throw(ArgumentError("`rand()` in an equation integrated by `Adaptive(…)`: the solver re-evaluates " *
                                "the rate at trial steps; use `RK4`/`ExplicitEuler`, or draw in an update"))
        end
    end
    return nothing
end

"""
The ODE unknowns `odes` (`(x, rate)` pairs, in model order) grouped by solver, in order of
first appearance: each group is one phase. Within a group every rate sees the state at the
start of the step (Jacobi, D-038); a later group sees the earlier groups' results.
"""
function _ode_groups(odes, spec::SolverSpec)
    groups = Tuple{String, Any, Vector{Tuple{Any, Any}}}[]
    for (x, r) in odes
        s = spec.resolved[_solver_name(x)]
        k = _canonical(s)
        j = findfirst(g -> g[1] == k, groups)
        j === nothing ? push!(groups, (k, s, Tuple{Any, Any}[(x, r)])) : push!(groups[j][3], (x, r))
    end
    return [(s, o) for (_, s, o) in groups]
end

# ---------------------------------------------------------------------------------------
# Canonical strings (D-016 as amended by D-075): the fingerprint hashes what a solver is,
# not the host object, so equal specifications built afresh hash equally. Types print fully
# qualified (independent of what the session has imported); keyword bundles are sorted.

_canonical(s::ExplicitEuler) = "ExplicitEuler(substeps=$(repr(s.substeps)),lower=$(repr(s.lower)))"
_canonical(s::RK4) = "RK4(substeps=$(s.substeps))"
function _canonical(s::Adaptive)
    kw = sort!([string(k, "=", _canonical_value(v)) for (k, v) in pairs(s.kwargs)])
    return "Adaptive($(_canonical_value(s.alg));$(join(kw, ",")))"
end

_canonical_type(T) = sprint(show, T; context = :module => Core)

function _canonical_value(x, depth = 0)
    x isa Union{Number, Symbol, AbstractString, Nothing, Missing} && return string(_canonical_type(typeof(x)), ":", repr(x))
    x isa Union{Function, Type} && return _canonical_type(x isa Type ? x : typeof(x))
    x isa Union{Tuple, NamedTuple, AbstractArray} &&
        return string(parentmodule(typeof(x)), ".", nameof(typeof(x)), "[",
            join((string(k, "=", _canonical_value(v, depth + 1)) for (k, v) in pairs(x)), ","), "]")
    T = typeof(x)
    (depth > 8 || !isstructtype(T) || fieldcount(T) == 0) && return _canonical_type(T)
    return string(_canonical_type(T), "(",
        join((string(n, "=", _canonical_value(getfield(x, n), depth + 1)) for n in fieldnames(T) if isdefined(x, n)), ","), ")")
end
