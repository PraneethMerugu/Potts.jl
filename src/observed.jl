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
    isempty(_p(csys.sys, :observed)) && return x
    sub = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in _p(csys.sys, :observed))
    for _ in 1:(length(sub) + 1)
        y = Symbolics.substitute(x, sub; fold = Val(false))
        isequal(y, x) && return y
        x = y
    end
    throw(ArgumentError("@observed definitions are cyclic"))
end

function _observed_scope(x)
    # a fold over `members(cluster)` reads the enclosing cell's `cluster` (`outer_value`)
    outer = Any[]
    _walk(y -> (iscall(y) && operation(y) === outer_value && push!(outer, arguments(y)[1])), _unwrap(x))
    x, _ = _strip_populations(_unwrap(x))
    # an integral is a cell quantity, whatever site expression it sums
    calls = Dict{Any, Any}()
    _walk(y -> (iscall(y) && operation(y) === cell_integral && (calls[y] = _unwrap(B.volume))), x)
    isempty(calls) || (x = _unwrap(Symbolics.substitute(x, calls; fold = Val(false))))
    scope = _has_op(x, cell_centroid) ? :cell : :model
    (:contact_count in (r for (r, _) in _uses(x))) && (scope = :cell)        # a contact fold (D-150)
    for v in _bare_vars(x)
        r = info(v).role
        r === :cell && (scope = :cell)
        r in (:site, :field) && return :site
    end
    for n in _bare_builtins(x)
        n in (:owner, :position, :site) && return :site
        n in (:volume, :surface, :kind, :id, :generation, :cluster, :cluster_volume, :cluster_surface, :major_length,
            :euler, :euler_full, :pieces, :pieces_full, :largest_piece, :largest_piece_full, :birth) &&
            (scope = :cell)
    end
    any(y -> _observed_scope(y) === :cell, outer) && (scope = :cell)
    return scope
end

# A dividing model that reads no `birth` keeps no serials (P6.5a3): a query that reads them
# afterwards (`sol[birth]`, `sibling`'s lowest-birth rule) is refused, not answered with slots
function _check_untracked_birth(c::CompiledPottsSystem, e)
    (_numbers_cells(c) && !c.uses_birth) || return nothing
    (_uses_builtin(e, :birth) || _has_op(e, cluster_sibling)) || return nothing
    throw(ArgumentError("model `$(nameof(c))` never reads `birth`, so the birth column was not kept " *
                        "(P6.5a3, D-245): `$e` cannot be evaluated after the run; declare " *
                        "`@observed bth(cell) ~ birth` in the model to record it"))
end

_algebraic_cell(x) = (i = info(x); i !== nothing && i.role === :observed && get(i.options, :scope, nothing) === :cell)

# One lock for every model's observed-function cache: ensemble threads (`EnsembleThreads`)
# read observed quantities concurrently (A-55).
const _OBSERVED_LOCK = ReentrantLock()

"""A host function `(u, p, t) -> value` for the quantity or expression `x`."""
_observed_function(info::PottsModelInfo, x) = lock(() -> _observed_function_unlocked(info, x), _OBSERVED_LOCK)

function _observed_function_unlocked(info::PottsModelInfo, x)
    get!(info.cache, _unwrap(x)) do
        c = info.csys
        T = info.T
        _with_model_scope(() -> _observed_build(info, c, T, x), c)
    end
end

# (in the scope of the model's `@boundary` faces: a `Δ` here sees them)
function _observed_build(info::PottsModelInfo, c, T, x)
    e = _expand_observed(c, _unwrap(x))
    _check_integral_pre_outside(e)
    _check_untracked_birth(c, e)
    rn = c.gather_names
    scope = _observed_scope(e)
    # an algebraic cell variable (`y ~ expr` in `@equations`) has one value per cell, whatever
    # its definition reads
    scope === :model && _algebraic_cell(x) && (scope = :cell)
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
    # the cell sums' scratch (F3-23) is made fresh, so the saved state's own is left unchanged
    sc = CorePotts.reduce_scratch(length(u.cell.kind))
    cell = merge(u.cell, NamedTuple(n => fresh(n) for n in names), sc.cell)
    # the integrals' hoisted folds write their model slots: copies, so `u` is left unchanged
    model = merge(u.model, NamedTuple(n => copy(getfield(u.model, n)) for n in propertynames(u.model)
                                      if startswith(String(n), "__ifold_")), sc.model)
    st = CorePotts.CPMState(u.σ, cell, u.site, model, u.history)
    foreach(ph -> ph(st, p, ctx, CorePotts.RNGKey(0), Int(t), CorePotts.CPU()), phases)
    return st
end

_potts_quantity(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic)

# a base parameter (a computed one is not a parameter for SII: it is observed, D-F2-1)
function _param_info(sys::PottsModelInfo, x)
    x = _localize(sys.csys.sys, x; strict = true)       # another model's `other₊λ` is an error (D-137)
    ps = _p(sys.csys.sys, :parameters)
    if x isa Symbol
        k = findfirst(p -> info(p).name === x, ps)
        return k === nothing || _is_symbolic(info(ps[k]).default) ? nothing : k
    end
    _potts_quantity(x) || return nothing
    i = info(x)
    i !== nothing && i.role in (:param, :kindtable) || return nothing
    return _computed_entity(ps, i.name) === nothing ? i.name : nothing
end
# the computed parameter `x` names (D-F2-1), or `nothing`
function _computed_info(sys::PottsModelInfo, x)
    x isa Union{AbstractArray, Tuple} && return nothing
    x = _localize(sys.csys.sys, x; strict = true)
    x isa Symbol || _potts_quantity(x) || return nothing
    return _computed_entity(_p(sys.csys.sys, :parameters), x isa Symbol ? x : (i = info(x); i === nothing ? x : i.name))
end

# Declared state variables are SII variables (settable with `setu`/`integ[x] = v`); built-ins
# and expressions are observed (read-only).
const _STATE_SCOPE = (cell = :cell, site = :site, field = :site, model = :model)
_state_var(v) = (i = info(v); i !== nothing && haskey(_STATE_SCOPE, i.role))
function _state_index(sys::PottsModelInfo, x)
    x = _localize(sys.csys.sys, x)
    _foreign(sys.csys.sys, x) && return nothing
    x isa Symbol || _potts_quantity(x) || return nothing
    for v in _p(sys.csys.sys, :variables)
        _state_var(v) || continue
        (x isa Symbol ? info(v).name === x : isequal(_unwrap(v), _unwrap(x))) &&
            return CorePotts.StateIndex(_STATE_SCOPE[info(v).role], info(v).name)
    end
    return nothing
end
SII.is_variable(sys::PottsModelInfo, x) = _state_index(sys, x) !== nothing
SII.variable_index(sys::PottsModelInfo, x) = _state_index(sys, x)
SII.variable_symbols(sys::PottsModelInfo) = filter(_state_var, _p(sys.csys.sys, :variables))
SII.all_variable_symbols(sys::PottsModelInfo) = [SII.variable_symbols(sys); [o.lhs for o in _p(sys.csys.sys, :observed)]]
SII.is_parameter(sys::PottsModelInfo, x) = _param_info(sys, x) !== nothing
function SII.parameter_index(sys::PottsModelInfo, x)
    # a computed parameter is read-only (D-F2-1): its index (asked by `setp`, `integ.ps[x] = v`,
    # `remake`) is an error naming its inputs
    ci = _computed_info(sys, x)
    ci === nothing || throw(ArgumentError(_computed_message(_p(sys.csys.sys, :parameters), ci)))
    i = _param_info(sys, x)
    return i isa Integer ? info(_p(sys.csys.sys, :parameters)[i]).name : i
end
# a list setter (`setp(integ, [:k2, …])`, `setsym`) names a computed parameter with its route
CorePotts.readonly_message(sys::PottsModelInfo, x) =
    (ci = _computed_info(sys, x); ci === nothing ? nothing : _computed_message(_p(sys.csys.sys, :parameters), ci))
SII.parameter_symbols(sys::PottsModelInfo) = filter(x -> !_is_symbolic(info(x).default), _p(sys.csys.sys, :parameters))
# a computed parameter reads as observed from the parameter object (`getp`, `integ.ps[k2]`, `sol.ps[k2]`)
function SII.parameter_observed(sys::PottsModelInfo, x)
    if x isa Union{AbstractArray, Tuple}
        fs = map(y -> SII.parameter_observed(sys, y), x isa Tuple ? x : collect(x))
        any(isnothing, fs) && return nothing
        return x isa Tuple ? ((p, t) -> map(f -> f(p, t), fs)) : ((p, t) -> [f(p, t) for f in fs])
    end
    ci = _computed_info(sys, x)
    if ci === nothing
        i = _param_info(sys, x)
        i === nothing && return nothing
        n = i isa Integer ? info(_p(sys.csys.sys, :parameters)[i]).name : i
        return (p, t) -> getproperty(p, n)
    end
    n = ci.name
    return (p, t) -> getproperty(p, n)
end
SII.is_timeseries_parameter(::PottsModelInfo, x) = false
SII.is_independent_variable(::PottsModelInfo, x) = _potts_quantity(x) && isequal(_unwrap(x), _unwrap(t))
SII.independent_variable_symbols(::PottsModelInfo) = [t]
SII.is_time_dependent(::PottsModelInfo) = true
SII.constant_structure(::PottsModelInfo) = true
SII.all_symbols(sys::PottsModelInfo) = vcat(SII.all_variable_symbols(sys), _p(sys.csys.sys, :parameters), [t])
SII.default_values(::PottsModelInfo) = Dict()
SII.is_observed(sys::PottsModelInfo, x) = _potts_quantity(x) && !SII.is_parameter(sys, x) &&
                                          !SII.is_variable(sys, x) && !SII.is_independent_variable(sys, x)
function SII.observed(sys::PottsModelInfo, x)
    ci = _computed_info(sys, x)
    ci === nothing || (n = ci.name; return (u, p, t) -> getproperty(p, n))
    return _observed_function(sys, _localize(sys.csys.sys, x; strict = true))
end
# by name: `sol[:volume]`, `sol[:act]`, `sol[:mean_excess]`
function _named_quantity(sys::PottsModelInfo, x::Symbol)
    m = sys.csys.sys
    for v in Iterators.flatten((_p(m, :variables), (o.lhs for o in _p(m, :observed))))
        info(v).name === x && return v
    end
    return x in BUILTIN_NAMES ? getfield(B, x) : nothing
end
SII.is_observed(sys::PottsModelInfo, x::Symbol) = !SII.is_parameter(sys, x) && !SII.is_variable(sys, x) &&
                                                  (_named_quantity(sys, _localize(sys.csys.sys, x)) !== nothing ||
                                                   _computed_info(sys, x) !== nothing)
function SII.observed(sys::PottsModelInfo, x::Symbol)
    ci = _computed_info(sys, x)
    ci === nothing || (n = ci.name; return (u, p, t) -> getproperty(p, n))
    return _observed_function(sys, _named_quantity(sys, _localize(sys.csys.sys, x)))
end

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
    for p in _p(m, :parameters)
        info(p).name === x && return p
    end
    msg = "`$x` is not a variable, observed quantity, built-in or parameter of $(nameof(sys.csys))"
    comps = [info(v).name for v in Iterators.flatten((_p(m, :parameters), _p(m, :variables)))
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
