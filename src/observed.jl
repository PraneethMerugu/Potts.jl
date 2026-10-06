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
    isempty(getfield(csys.sys, :observed)) && return x
    sub = Dict{Any, Any}(_unwrap(o.var) => _unwrap(o.expr) for o in getfield(csys.sys, :observed))
    for _ in 1:(length(sub) + 1)
        y = Symbolics.substitute(x, sub; fold = Val(false))
        isequal(y, x) && return y
        x = y
    end
    throw(ArgumentError("@observed definitions are cyclic"))
end

function _observed_scope(x)
    x, _ = _strip_populations(_unwrap(x))
    # an integral is a cell quantity, whatever site expression it sums
    calls = Dict{Any, Any}()
    _walk(y -> (iscall(y) && operation(y) === cell_integral && (calls[y] = _unwrap(B.volume))), x)
    isempty(calls) || (x = _unwrap(Symbolics.substitute(x, calls; fold = Val(false))))
    scope = _has_op(x, cell_centroid) ? :cell : :model
    for v in _bare_vars(x)
        r = info(v).role
        r === :cell && (scope = :cell)
        r in (:site, :field) && return :site
    end
    for n in _bare_builtins(x)
        n in (:owner, :position, :site) && return :site
        n in (:volume, :surface, :kind, :id, :generation, :cluster, :cluster_volume, :cluster_surface, :major_length) &&
            (scope = :cell)
    end
    return scope
end

# One lock for every model's observed-function cache: ensemble threads (`EnsembleThreads`)
# read observed quantities concurrently (A-55).
const _OBSERVED_LOCK = ReentrantLock()

"""A host function `(u, p, t) -> value` for the quantity or expression `x`."""
_observed_function(info::PottsModelInfo, x) = lock(() -> _observed_function_unlocked(info, x), _OBSERVED_LOCK)

function _observed_function_unlocked(info::PottsModelInfo, x)
    get!(info.cache, _unwrap(x)) do
        c = info.csys
        T = info.T
        _with_faces(() -> _observed_build(info, c, T, x), c)
    end
end

# (in the scope of the model's `@boundary` faces: a `Δ` here sees them)
function _observed_build(info::PottsModelInfo, c, T, x)
    e = _expand_observed(c, _unwrap(x))
    _check_integral_pre_outside(e)
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
    if _has_op(e, cell_integral)       # integrals of the state itself (not the stored refresh)
        # observed-only integrals (D-120) have no stored column: computed here, with the rest
        ph = _integral_phases(c, T; observed = true)
        names = [_integral_name(x) for x in _integrals(c.sys; observed = true)]
        (u, p, t) -> f(_fresh_integrals(T, u, p, hctx, t, ph, names), p, hctx, t)
    else
        (u, p, t) -> f(u, p, hctx, t)
    end
end

"""A copy of state `u` whose integral arrays are recomputed from its sites (host); the
columns of integrals read only by `@observed` (not stored) are created in `T`."""
# (observed-only integrals have no cell column, D-120)
function _fresh_integrals(::Type{T}, u, p, ctx, t, phases, names) where {T}
    fresh(n) = hasproperty(u.cell, n) ? zero(getfield(u.cell, n)) : fill!(similar(u.cell.kind, T), zero(T))
    cell = merge(u.cell, NamedTuple(n => fresh(n) for n in names))
    # the integrals' hoisted folds write their model slots: copies, so `u` is left unchanged
    model = merge(u.model, NamedTuple(n => copy(getfield(u.model, n)) for n in propertynames(u.model)
                                      if startswith(String(n), "__ifold_")))
    st = CorePotts.CPMState(u.σ, cell, u.site, model, u.history)
    foreach(ph -> ph(st, p, ctx, CorePotts.RNGKey(0), Int(t), CorePotts.CPU()), phases)
    return st
end

_potts_quantity(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic)

function _param_info(sys::PottsModelInfo, x)
    x = _localize(sys.csys.sys, x; strict = true)       # another model's `other₊λ` is an error (D-137)
    x isa Symbol && return findfirst(p -> info(p).name === x, getfield(sys.csys.sys, :parameters))
    _potts_quantity(x) || return nothing
    i = info(x)
    return i !== nothing && i.role in (:param, :kindtable) ? i.name : nothing
end

# Declared state variables are SII variables (settable with `setu`/`integ[x] = v`); built-ins
# and expressions are observed (read-only).
const _STATE_SCOPE = (cell = :cell, site = :site, field = :site, model = :model)
_state_var(v) = (i = info(v); i !== nothing && haskey(_STATE_SCOPE, i.role))
function _state_index(sys::PottsModelInfo, x)
    x = _localize(sys.csys.sys, x)
    _foreign(sys.csys.sys, x) && return nothing
    x isa Symbol || _potts_quantity(x) || return nothing
    for v in getfield(sys.csys.sys, :variables)
        _state_var(v) || continue
        (x isa Symbol ? info(v).name === x : isequal(_unwrap(v), _unwrap(x))) &&
            return CorePotts.StateIndex(_STATE_SCOPE[info(v).role], info(v).name)
    end
    return nothing
end
SII.is_variable(sys::PottsModelInfo, x) = _state_index(sys, x) !== nothing
SII.variable_index(sys::PottsModelInfo, x) = _state_index(sys, x)
SII.variable_symbols(sys::PottsModelInfo) = filter(_state_var, getfield(sys.csys.sys, :variables))
SII.all_variable_symbols(sys::PottsModelInfo) = [SII.variable_symbols(sys); [o.var for o in getfield(sys.csys.sys, :observed)]]
SII.is_parameter(sys::PottsModelInfo, x) = _param_info(sys, x) !== nothing
function SII.parameter_index(sys::PottsModelInfo, x)
    i = _param_info(sys, x)
    return i isa Integer ? info(getfield(sys.csys.sys, :parameters)[i]).name : i
end
SII.parameter_symbols(sys::PottsModelInfo) = getfield(sys.csys.sys, :parameters)
SII.is_timeseries_parameter(::PottsModelInfo, x) = false
SII.is_independent_variable(::PottsModelInfo, x) = _potts_quantity(x) && isequal(_unwrap(x), _unwrap(t))
SII.independent_variable_symbols(::PottsModelInfo) = [t]
SII.is_time_dependent(::PottsModelInfo) = true
SII.constant_structure(::PottsModelInfo) = true
SII.all_symbols(sys::PottsModelInfo) = vcat(SII.all_variable_symbols(sys), getfield(sys.csys.sys, :parameters), [t])
SII.default_values(::PottsModelInfo) = Dict()
SII.is_observed(sys::PottsModelInfo, x) = _potts_quantity(x) && !SII.is_parameter(sys, x) &&
                                          !SII.is_variable(sys, x) && !SII.is_independent_variable(sys, x)
SII.observed(sys::PottsModelInfo, x) = _observed_function(sys, _localize(sys.csys.sys, x; strict = true))
# by name: `sol[:volume]`, `sol[:act]`, `sol[:mean_excess]`
function _named_quantity(sys::PottsModelInfo, x::Symbol)
    m = sys.csys.sys
    for v in Iterators.flatten((getfield(m, :variables), (o.var for o in getfield(m, :observed))))
        info(v).name === x && return v
    end
    return x in BUILTIN_NAMES ? getfield(B, x) : nothing
end
SII.is_observed(sys::PottsModelInfo, x::Symbol) = !SII.is_parameter(sys, x) && !SII.is_variable(sys, x) &&
                                                  _named_quantity(sys, _localize(sys.csys.sys, x)) !== nothing
SII.observed(sys::PottsModelInfo, x::Symbol) = _observed_function(sys, _named_quantity(sys, _localize(sys.csys.sys, x)))

"""
    observe(prob_or_sol, x[, u])

Evaluate the model quantity or expression `x` (e.g. `volume`, an `@observed` name,
`count(true for c in cells(tumor))` written with the model's symbols) on state `u`
(default: the problem's initial state, or every saved state of a solution).

`x` may also be a name, as a `Symbol`: `observe(sol, :nA)` is `observe` on the model's
quantity of that name, looked up in this order: a declared variable or `@observed`
quantity, then a built-in such as `:volume`, then a parameter. An unknown name is an
`ArgumentError`.
"""
observe(prob::CorePotts.PottsProblem, x, u = prob.u0) =
    _observed_function(prob.f.sys, _observe_quantity(prob.f.sys, x))(u, prob.p, prob.tspan[1])
function observe(sol::CorePotts.PottsSolution, x)
    f = _observed_function(sol.prob.f.sys, _observe_quantity(sol.prob.f.sys, x))
    return map((u, s) -> f(u, sol.prob.p, s), sol.u, sol.t)
end

# `observe` by name: the model's quantity called `x` (variable, `@observed`, built-in, parameter)
_observe_quantity(::Any, x) = x
_observe_quantity(sys::PottsModelInfo, x) = _localize(sys.csys.sys, x; strict = true)
function _observe_quantity(sys::PottsModelInfo, x::Symbol)
    x = _localize(sys.csys.sys, x; strict = true)
    q = _named_quantity(sys, x)
    q === nothing || return q
    m = sys.csys.sys
    for p in getfield(m, :parameters)
        info(p).name === x && return p
    end
    msg = "`$x` is not a variable, observed quantity, built-in or parameter of $(nameof(sys.csys))"
    comps = [info(v).name for v in Iterators.flatten((getfield(m, :parameters), getfield(m, :variables)))
             if get(info(v).options, :vector, nothing) === x]
    if !isempty(comps)
        msg *= "; `$x` is a vector quantity: observe its components ($(join((":" * string(n) for n in comps), ", ")))"
    elseif x === :t
        msg *= "; the times of a solution are `sol.t`"
    end
    throw(ArgumentError(msg))
end

SII.parameter_values(p::PottsParameters) = p
SII.parameter_values(p::PottsParameters, i::Symbol) = p[i]
