# Observed quantities and SymbolicIndexingInterface: `sol[x]` / `getu(prob, x)` evaluate any
# model quantity or expression on saved states, `getp(prob, λ)` reads parameters.
#
# The scope of an expression decides the shape of its value: a bare cell quantity
# (`volume`, a cell variable) gives one value per cell, a bare site quantity one per site
# (an array over the lattice), and anything else (parameters, model variables, population
# folds) a scalar.

const SII = SymbolicIndexingInterface

"""Definitions of `@observed` names, substituted (recursively) into observed expressions."""
function _expand_observed(csys::CompiledPottsSystem, x)
    isempty(csys.sys.observed) && return x
    sub = Dict{Any, Any}(_unwrap(o.var) => _unwrap(o.expr) for o in csys.sys.observed)
    for _ in 1:(length(sub) + 1)
        y = Symbolics.substitute(x, sub; fold = Val(false))
        isequal(y, x) && return y
        x = y
    end
    throw(ArgumentError("@observed definitions are cyclic"))
end

function _observed_scope(x)
    x, _ = _strip_populations(_unwrap(x))
    scope = _has_op(x, cell_centroid) ? :cell : :model
    for v in _bare_vars(x)
        r = info(v).role
        r === :cell && (scope = :cell)
        r in (:site, :field) && return :site
    end
    for n in _bare_builtins(x)
        n in (:owner, :position) && return :site
        n in (:volume, :surface, :kind, :id, :generation, :cluster, :cluster_volume, :cluster_surface) && (scope = :cell)
    end
    return scope
end

"""A host function `(u, p, t) -> value` for the quantity or expression `x`."""
function _observed_function(info::PottsModelInfo, x)
    get!(info.cache, _unwrap(x)) do
        c = info.csys
        T = info.T
        e = _expand_observed(c, _unwrap(x))
        rn = c.gather_names
        scope = _observed_scope(e)
        f = if scope === :cell
            code = lower(e, _cell_env(T, :c, rn; mcs = :t))
            _rgf(:((st, p, ctx, t) -> [(c == 0 ? $T(0) : $code) for c in 1:length(st.cell.kind)]))
        elseif scope === :site
            code = lower(e, _site_env(T, :i, rn; mcs = :t))
            _rgf(:((st, p, ctx, t) -> reshape([$code for i in 1:length(st.σ)], size(st.σ))))
        else
            code = lower(e, _model_env(T, rn; mcs = :t))
            _rgf(:((st, p, ctx, t) -> $code))
        end
        hctx = info.ctx
        (u, p, t) -> f(u, p, hctx, t)
    end
end

_potts_quantity(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic)

function _param_info(sys::PottsModelInfo, x)
    x isa Symbol && return findfirst(p -> info(p).name === x, sys.csys.sys.parameters)
    _potts_quantity(x) || return nothing
    i = info(x)
    return i !== nothing && i.role in (:param, :kindtable) ? i.name : nothing
end

SII.is_variable(::PottsModelInfo, x) = false
SII.variable_index(::PottsModelInfo, x) = nothing
SII.variable_symbols(::PottsModelInfo) = []
SII.all_variable_symbols(sys::PottsModelInfo) = [o.var for o in sys.csys.sys.observed]
SII.is_parameter(sys::PottsModelInfo, x) = _param_info(sys, x) !== nothing
function SII.parameter_index(sys::PottsModelInfo, x)
    i = _param_info(sys, x)
    return i isa Integer ? info(sys.csys.sys.parameters[i]).name : i
end
SII.parameter_symbols(sys::PottsModelInfo) = sys.csys.sys.parameters
SII.is_timeseries_parameter(::PottsModelInfo, x) = false
SII.is_independent_variable(::PottsModelInfo, x) = _potts_quantity(x) && isequal(_unwrap(x), _unwrap(t))
SII.independent_variable_symbols(::PottsModelInfo) = [t]
SII.is_time_dependent(::PottsModelInfo) = true
SII.constant_structure(::PottsModelInfo) = true
SII.all_symbols(sys::PottsModelInfo) = vcat(SII.all_variable_symbols(sys), sys.csys.sys.parameters, [t])
SII.default_values(::PottsModelInfo) = Dict()
SII.is_observed(sys::PottsModelInfo, x) = _potts_quantity(x) && !SII.is_parameter(sys, x) &&
                                          !SII.is_independent_variable(sys, x)
SII.observed(sys::PottsModelInfo, x) = _observed_function(sys, x)
# by name: `sol[:volume]`, `sol[:act]`, `sol[:mean_excess]`
function _named_quantity(sys::PottsModelInfo, x::Symbol)
    m = sys.csys.sys
    for v in Iterators.flatten((m.variables, (o.var for o in m.observed)))
        info(v).name === x && return v
    end
    return x in BUILTIN_NAMES ? getfield(B, x) : nothing
end
SII.is_observed(sys::PottsModelInfo, x::Symbol) = !SII.is_parameter(sys, x) && _named_quantity(sys, x) !== nothing
SII.observed(sys::PottsModelInfo, x::Symbol) = _observed_function(sys, _named_quantity(sys, x))

"""
    observe(prob_or_sol, x[, u])

Evaluate the model quantity or expression `x` (e.g. `volume`, an `@observed` name,
`count(true for c in cells(tumor))` written with the model's symbols) on state `u`
(default: the problem's initial state, or every saved state of a solution).
"""
observe(prob::CorePotts.CPMProblem, x, u = prob.u0) = _observed_function(prob.f.sys, x)(u, prob.p, prob.tspan[1])
observe(sol::CorePotts.PottsSolution, x) = map((u, s) -> _observed_function(sol.prob.f.sys, x)(u, sol.prob.p, s), sol.u, sol.t)

SII.parameter_values(p::PottsParameters) = p
SII.parameter_values(p::PottsParameters, i::Symbol) = p[i]
