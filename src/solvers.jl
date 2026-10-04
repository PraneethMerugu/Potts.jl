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
and `canonical` is the canonical string of that map that the problem fingerprint hashes.
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
- `ode_solver` (default `ExplicitEuler()`, one step per MCS) integrates every cell
  and model ODE that `solvers` does not name;
- `solvers = [x => solver, …]` keys integrated variables (the Potts variable, the MTK
  component variable `comp.x`, or the name `:x`/`Symbol("comp₊x")`), or a component
  system (all its integrated unknowns): an ODE unknown takes any `ode_solver`, a field an
  `ExplicitEuler`.

An ODE's `ExplicitEuler(substeps = nothing)` is one step, the same as `substeps = 1`
(`_ode_solver`): both resolve, group and fingerprint alike.
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
            "(no default; a published model's docstring gives its value)"))
        field_solver isa ExplicitEuler || throw(ArgumentError(
            "`field_solver` takes an `ExplicitEuler(; substeps, lower)`; got $(repr(field_solver))"))
    end
    ode_solver isa _ODESolver || throw(ArgumentError(
        "`ode_solver` takes `ExplicitEuler(; substeps)`, `RK4(; substeps)` or `Adaptive(alg; …)`; got $(repr(ode_solver))"))
    resolved = Dict{Symbol, Any}()
    foreach(n -> resolved[n] = field_solver, fields)
    foreach(n -> resolved[n] = _ode_solver(ode_solver), odes)
    given = Pair{Any, Any}[k => v for (k, v) in (solvers isa AbstractDict ? pairs(solvers) : solvers)]
    named = Set{Symbol}()
    for (k, s) in given, n in _solver_keys(k, [fields; odes])
        n in named && throw(ArgumentError("`solvers`: `$n` is given twice" *
                                          (k isa ModelingToolkitBase.AbstractSystem ? " (once through component `$(nameof(k))`)" : "")))
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
        resolved[n] = n in odes ? _ode_solver(s) : s
    end
    _check_adaptive_draws(c, resolved)
    canonical = join(("$n=$(_canonical(resolved[n]))" for n in sort!(collect(keys(resolved)))), ";")
    return SolverSpec(field_solver, ode_solver, given, resolved, canonical)
end

# As an ODE solver, explicit Euler with `substeps = nothing` is one step per MCS.
_ode_solver(s) = s isa ExplicitEuler && s.substeps === nothing ? ExplicitEuler(1, s.lower) : s

# The variable names a `solvers` key stands for: a name, a Potts variable, an MTK component
# variable (`comp.x`, the cell variable `comp₊x`), or a component system (its integrated
# unknowns `comp₊…`).
function _solver_keys(k, integrated)
    k isa Symbol && return (k,)
    if k isa ModelingToolkitBase.AbstractSystem
        prefix = string(nameof(k), "₊")
        ns = sort!([n for n in integrated if startswith(string(n), prefix)])
        isempty(ns) && throw(ArgumentError("`solvers`: the component `$(nameof(k))` has no integrated variable in this " *
                                           "model (no component of that name, or no `D(x) ~ …` equation)"))
        return ns
    end
    i = info(k)
    if i === nothing
        n = _mtkname(k)
        n isa Symbol && return (n,)
        throw(ArgumentError("`solvers`: the key `$(_key_string(k))` is not a model quantity; key by the variable " *
                            "(`x => solver`) or a component"))
    end
    i.role in (:param, :kindtable) && throw(ArgumentError(
        "`solvers`: `$(i.name)` is a parameter; the keys are integrated variables"))
    return (i.name,)
end
_key_string(k) = (s = sprint(show, k; context = :limit => true); length(s) > 60 ? first(s, 60) * "…" : s)

# A-68: an adaptive step re-evaluates the rate at trial steps, so it cannot replay draws.
function _check_adaptive_draws(c::CompiledPottsSystem, resolved)
    for eq in getfield(c.sys, :equations)
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
The ODE unknowns `odes` (`(x, rate)` pairs, in model order) grouped by solver (by canonical
string, the fingerprint's: equal specifications built afresh share a phase, and solvers
that differ, a closure's captures included, do not), in order of first appearance: each
group is one phase. Every rate
sees the state at the start of the step (Jacobi): with one group the phase writes
the variables directly; with several, each writes scratch `x__ode` and one publish per
scope copies them back after all groups ran (`_ode_scratch`).
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

"""Whether the ODEs of `scope` (`:cell`, `:model`) step through scratch slots `x__ode`:
when they run in several solver groups (Jacobi across groups), or when a cell ODE
reads another cell's ODE unknowns (Jacobi across cells)."""
_ode_scratch(c::CompiledPottsSystem, spec::SolverSpec, scope) =
    length(_ode_groups(scope === :cell ? c.cell_odes : c.model_odes, spec)) > 1 ||
    (scope === :cell && _ode_reads_other_cells(c))

# A cell ODE whose rate reads a cell-ODE unknown of another cell (`y[j]`, also in a gather's
# body or an index, or a population fold left in the kernel because it reads `time`) must not
# see cells that already stepped: it needs scratch slots even with one solver group, as
# discrete ticks do (`_reads_other_cells_slots`). Reads of the cell's own unknowns (`y`,
# `y[id]`, `w[f(y)]`) do not; nor do folds hoisted to model slots (`cell_ode_pops`,
# computed before the ODEs).
function _ode_reads_other_cells(c::CompiledPottsSystem)
    names = Set{Symbol}(info(x).name for (x, _) in c.cell_odes)
    isempty(names) && return false
    hit = Ref(false)
    reads(y) = (found = Ref(false);
        _walk_all(z -> (i = info(z); i !== nothing && i.role === :cell && i.name in names && (found[] = true)), y); found[])
    for (_, r) in c.cell_odes
        _walk_all(r) do y
            hit[] && return
            iscall(y) || return
            op = operation(y)
            # an indexed read crosses cells through its variable, not its index (this cell's
            # expression; a read nested in it is visited on its own); a gather's body reads
            # this cell's unknowns unless indexed; a fold's body reads every cell's
            hit[] = op in (at, at2) ? !_is_own_read(y) && reads(arguments(y)[1]) :
                    op === population && reads(y)
        end
    end
    return hit[]
end

"""`x[id]`: the current cell's own `x`."""
_own_read(x) = _unwrap(at(Symbolics.wrap(x), Symbolics.wrap(B.id)))
_is_own_read(y) = operation(y) === at && isequal(arguments(y)[2], B.id)
_ode_scratch_name(n::Symbol) = Symbol(n, :__ode)

# ---------------------------------------------------------------------------------------
# Canonical strings (D-016 as amended by D-075): the fingerprint hashes what a solver is,
# not the host object, so equal specifications built afresh hash equally. Types print fully
# qualified (independent of what the session has imported); keyword bundles are sorted.

_canonical(s::ExplicitEuler) = "ExplicitEuler(substeps=$(repr(s.substeps)),lower=$(repr(s.lower)))"
_canonical(s::RK4) = "RK4(substeps=$(s.substeps))"
function _canonical(s::Adaptive)
    alg = _canonical_solver_part(s.alg, "the algorithm")
    kw = sort!([string(k, "=", _canonical_solver_part(v, "the keyword `$k`")) for (k, v) in pairs(s.kwargs)])
    return "Adaptive($alg;$(join(kw, ",")))"
end

# A solver part's canonical string (D-130). A value beyond the printer's depth cap, or a
# cyclic one, is an `ArgumentError` naming `Adaptive` and the part: cut to its type, two
# different solvers would fingerprint alike and share one ODE group. A compiler-generated
# name (`var"#…"`: an anonymous function, a closure, a local function) is accepted; the
# problem fingerprint then also hashes the session token (`_session_bound`).
_canonical_solver_part(v, what) = _canonical_checked(() -> "`Adaptive`: $what", v)

# `_canonical_value(v)`, with a value too deep or cyclic turned into an `ArgumentError` that
# starts with `describe()` (built only then): every caller that can meet a user value (solver
# parts, gather relations, symbolic constants and bound options) goes through here, so the
# private `_CanonicalDepthError` never reaches the user (D-130).
function _canonical_checked(describe, v)
    try
        return _canonical_value(v)
    catch e
        e isa _CanonicalDepthError || rethrow()
        throw(ArgumentError(string(describe(), " holds a value nested deeper than ", _CANONICAL_DEPTH,
            " levels, or a cyclic value (at a `", e.type, "`): too deep to print in the canonical form that ",
            "orders, names and fingerprints the model's parts; pass a flatter value, e.g. a callable struct ",
            "holding only the values that matter")))
    end
end

_canonical_type(T) = sprint(show, T; context = :module => Core)

# How deep `_canonical_value` descends. A value with parts below this depth, or a cyclic one,
# is an error (`_CanonicalDepthError`), never cut to its type (D-130). The depth is the only
# cycle check: build-time, no visited set.
const _CANONICAL_DEPTH = 8
struct _CanonicalDepthError <: Exception
    type::String
end
Base.showerror(io::IO, e::_CanonicalDepthError) =
    print(io, "a value nested deeper than $(_CANONICAL_DEPTH) levels, or a cyclic value (at a `", e.type,
        "`), too deep to print in canonical form; pass a flatter value")

# Values print with their full type. Scalars, enums and other primitives, strings and
# ranges by `repr`; containers element by element (dictionaries and sets sorted by the
# printed key, never their hash slots); types and singleton functions by type; any other
# struct, closures included (their captures are fields), by type and fields. Leaves print at
# any depth; a value with parts below `_CANONICAL_DEPTH` throws.
function _canonical_value(x, depth = 0)
    T = typeof(x)
    (x isa Union{Number, Symbol, AbstractString, Nothing, Missing, Enum, AbstractRange} || isprimitivetype(T)) &&
        return string(_canonical_type(T), ":", repr(x))
    x isa Type && return _canonical_type(x)
    container = x isa Union{AbstractDict, AbstractSet, Tuple, NamedTuple, AbstractArray}
    !container && (!isstructtype(T) || fieldcount(T) == 0) && return _canonical_type(T)
    depth > _CANONICAL_DEPTH && throw(_CanonicalDepthError(_canonical_type(T)))
    item(v) = _canonical_value(v, depth + 1)
    x isa AbstractDict && return string(_canonical_type(T), "{",
        join(sort!([string(item(k), "=>", item(v)) for (k, v) in pairs(x)]), ","), "}")
    x isa AbstractSet && return string(_canonical_type(T), "{", join(sort!([item(v) for v in x]), ","), "}")
    container &&
        return string(_canonical_type(T), "[", join((string(k, "=", item(v)) for (k, v) in pairs(x)), ","), "]")
    return string(_canonical_type(T), "(",
        join((string(n, "=", item(getfield(x, n))) for n in fieldnames(T) if isdefined(x, n)), ","), ")")
end

# The per-session token (D-130), drawn in `__init__` (Potts.jl) at every load, never baked
# into the precompile image. A solver whose canonical string holds a compiler-generated name
# is identified only within this session: `_problem_function` hashes the token into such a
# problem's fingerprint (only there: the canonical string and solver grouping never see it),
# so its checkpoints never load into another session, nor collide with another session's
# closure that happens to get the same name. Construction and `remake` both build through
# `_problem_function`, and `spec.canonical` covers every solver (`field_solver`,
# `ode_solver`, `solvers`).
const _SESSION_TOKEN = Ref{UInt64}(0)
_session_bound(spec::SolverSpec) = occursin("var\"#", spec.canonical)
