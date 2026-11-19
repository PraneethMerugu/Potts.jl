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
    isempty(_p(getfield(csys, :sys), :observed)) && return x
    sub = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in _p(getfield(csys, :sys), :observed))
    for _ in 1:(length(sub) + 1)
        y = Symbolics.substitute(x, sub; fold = Val(false))
        isequal(y, x) && return y
        x = y
    end
    throw(
        ArgumentError(
            "@observed definitions are cyclic; break the cycle so each definition depends only on state, parameters or earlier definitions"
        )
    )
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
        n in (
            :volume, :surface, :kind, :id, :generation, :cluster, :cluster_volume, :cluster_surface, :major_length,
            :euler, :euler_full, :pieces, :pieces_full, :largest_piece, :largest_piece_full, :birth,
        ) &&
            (scope = :cell)
    end
    any(y -> _observed_scope(y) === :cell, outer) && (scope = :cell)
    return scope
end

# A dividing model that reads no `birth` keeps no serials (P6.5a3): a query that reads them
# afterwards (`sol[birth]`, `sibling`'s lowest-birth rule) is refused, not answered with slots
function _check_untracked_birth(c::CompiledPottsSystem, e)
    (_numbers_cells(c) && !getfield(c, :uses_birth)) || return nothing
    (_uses_builtin(e, :birth) || _has_op(e, cluster_sibling)) || return nothing
    throw(
        ArgumentError(
            "model `$(nameof(c))` never reads `birth`, so the birth column was not kept " *
                "(P6.5a3, D-245): `$e` cannot be evaluated after the run; declare " *
                "`@observed bth(cell) ~ birth` in the model to record it"
        )
    )
end

_algebraic_cell(x) = (i = info(x); i !== nothing && i.role === :observed && get(i.options, :scope, nothing) === :cell)

# One lock for every model's observed-function cache: ensemble threads (`EnsembleThreads`)
# read observed quantities concurrently (A-55).
const _OBSERVED_LOCK = ReentrantLock()

"""A host function `(u, p, t) -> value` for the quantity or expression `x`."""
_observed_function(info::PottsModelInfo, x) = lock(() -> _observed_function_unlocked(info, x), _OBSERVED_LOCK)

function _observed_function_unlocked(info::PottsModelInfo, x)
    return get!(info.cache, _unwrap(x)) do
        c = info.csys
        T = info.T
        _with_model_scope(() -> _observed_build(info, c, T, x), c)
    end
end

# Observed values per cell or per site: the generated function of one element, mapped here. A
# comprehension inside the generated body would be an opaque closure, which a downstream
# package cannot precompile (TS1c).
struct _CellValues{T, F}
    f::F
end
_CellValues{T}(f::F) where {T, F} = _CellValues{T, F}(f)
(o::_CellValues{T})(st, p, ctx, t) where {T} = [(c == 0 ? T(0) : o.f(st, p, ctx, t, c)) for c in 1:length(st.cell.kind)]
struct _SiteValues{F}
    f::F
end
(o::_SiteValues)(st, p, ctx, t) = reshape([o.f(st, p, ctx, t, i) for i in 1:length(st.ownership)], size(st.ownership))

function _observed_build(info::PottsModelInfo, c, T, x)
    e = _expand_observed(c, _unwrap(x))
    _check_integral_pre_outside(e, ArgumentError)
    _check_untracked_birth(c, e)
    rn = getfield(c, :gather_names)
    scope = _observed_scope(e)
    # an algebraic cell variable (`y ~ expr` in `@equations`) has one value per cell, whatever
    # its definition reads
    scope === :model && _algebraic_cell(x) && (scope = :cell)
    f = if scope === :cell
        code = lower(e, _cell_env(T, :c, rn; mcs = :t))
        _CellValues{T}(_rgf(:((st, p, ctx, t, c) -> $code)))
    elseif scope === :site
        code = lower(e, _site_env(T, :i, rn; mcs = :t))
        _SiteValues(_rgf(:((st, p, ctx, t, i) -> $code)))
    else
        code = lower(e, _model_env(T, rn; mcs = :t))
        _rgf(:((st, p, ctx, t) -> $code))
    end
    hctx = info.ctx
    return if _has_op(e, cell_integral)       # integrals of the state itself (not the stored refresh)
        # observed-only integrals (D-120) have no stored column: computed here, with the rest
        ph = _integral_phases(c, T; observed = true)
        names = [_integral_name(x) for x in _integrals(getfield(c, :sys); observed = true)]
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
    model = merge(
        u.model, NamedTuple(
            n => copy(getfield(u.model, n)) for n in propertynames(u.model)
                if startswith(String(n), "__ifold_")
        ), sc.model
    )
    st = CorePotts.CPMState(u.ownership, cell, u.site, model, u.history)
    foreach(ph -> ph(st, p, ctx, CorePotts.RNGKey(0), Int(t), CorePotts.CPU()), phases)
    return st
end

_potts_quantity(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic)

# a base parameter (a computed one is not a parameter for SII: it is observed, D-F2-1)
function _param_info(sys::PottsModelInfo, x)
    x = _localize(getfield(sys.csys, :sys), x; strict = true)       # another model's `other₊λ` is an error (D-137)
    ps = _p(getfield(sys.csys, :sys), :parameters)
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
    x = _localize(getfield(sys.csys, :sys), x; strict = true)
    x isa Symbol || _potts_quantity(x) || return nothing
    return _computed_entity(_p(getfield(sys.csys, :sys), :parameters), x isa Symbol ? x : (i = info(x); i === nothing ? x : i.name))
end

# SymbolicIndexingInterface getters and setters built from a model or a compiled model
# (`getp(sys, T)`, `getu(sys, volume)`, `setp(mtkcompile(sys), T)`): the model holds names, the
# problem holds the generated code and the context that values are computed with. So the
# accessor looks its symbol up in the problem, integrator or solution it is applied to (whose
# index provider is the compiled model's `PottsModelInfo`) and reads or writes there. Other
# queries on the model are answered by its inner System (`symbolic_container`).
struct _DeferredAccessor{F, S}
    build::F        # `SII.getsym`, `SII.getp`, `SII.setsym` or `SII.setp` (with its keywords)
    sym::S
end
(a::_DeferredAccessor)(target) = a.build(target, a.sym)(target)
# a getter with a time index (`getu(sys, x)(sol, i)`), or a setter with its value (`(prob, v)`)
(a::_DeferredAccessor)(target, x) = a.build(target, a.sym)(target, x)

const _ModelOrCompiled = Union{PottsSystem, CompiledPottsSystem}
SII.getsym(sys::_ModelOrCompiled, sym) = _DeferredAccessor(SII.getsym, sym)
SII.getp(sys::_ModelOrCompiled, p) = _DeferredAccessor(SII.getp, p)
SII.setsym(sys::_ModelOrCompiled, sym) = _DeferredAccessor(SII.setsym, sym)
SII.setp(sys::_ModelOrCompiled, p; run_hook = true) = _DeferredAccessor((target, q) -> SII.setp(target, q; run_hook), p)
# MTKBase's `all_symbols` of a complete system reads its bound parameters, which only the
# inner System holds
SII.all_symbols(sys::_ModelOrCompiled) = SII.all_symbols(SII.symbolic_container(sys))
# the compiled model's other queries: the model's inner System, as for the model (MTKBase's
# own methods on an `AbstractSystem` would read an index cache it does not have)
SII.symbolic_container(c::CompiledPottsSystem) = inner(getfield(c, :authored))
SII.parameter_index(c::CompiledPottsSystem, sym) = SII.parameter_index(SII.symbolic_container(c), sym)
SII.parameter_index(c::CompiledPottsSystem, sym::Symbol) = SII.parameter_index(SII.symbolic_container(c), sym)
SII.is_parameter(c::CompiledPottsSystem, i::ModelingToolkitBase.ParameterIndex) = SII.is_parameter(SII.symbolic_container(c), i)
SII.observed(c::CompiledPottsSystem, sym; kw...) = SII.observed(SII.symbolic_container(c), sym; kw...)
SII.parameter_observed(c::CompiledPottsSystem, sym) = SII.parameter_observed(SII.symbolic_container(c), sym)

# Declared state variables are SII variables (settable with `setu`/`integ[x] = v`); built-ins
# and expressions are observed (read-only).
const _STATE_SCOPE = (cell = :cell, site = :site, field = :site, model = :model)
_state_var(v) = (i = info(v); i !== nothing && haskey(_STATE_SCOPE, i.role))
function _state_index(sys::PottsModelInfo, x)
    x = _localize(getfield(sys.csys, :sys), x)
    _foreign(getfield(sys.csys, :sys), x) && return nothing
    x isa Symbol || _potts_quantity(x) || return nothing
    for v in _p(getfield(sys.csys, :sys), :variables)
        _state_var(v) || continue
        (x isa Symbol ? info(v).name === x : isequal(_unwrap(v), _unwrap(x))) &&
            return CorePotts.StateIndex(_STATE_SCOPE[info(v).role], info(v).name)
    end
    return nothing
end
SII.is_variable(sys::PottsModelInfo, x) = _state_index(sys, x) !== nothing
SII.variable_index(sys::PottsModelInfo, x) = _state_index(sys, x)
SII.variable_symbols(sys::PottsModelInfo) = filter(_state_var, _p(getfield(sys.csys, :sys), :variables))
SII.all_variable_symbols(sys::PottsModelInfo) = [SII.variable_symbols(sys); [o.lhs for o in _p(getfield(sys.csys, :sys), :observed)]]
SII.is_parameter(sys::PottsModelInfo, x) = _param_info(sys, x) !== nothing
function SII.parameter_index(sys::PottsModelInfo, x)
    # a computed parameter is read-only (D-F2-1): its index (asked by `setp`, `integ.ps[x] = v`,
    # `remake`) is an error naming its inputs
    ci = _computed_info(sys, x)
    ci === nothing || throw(ArgumentError(_computed_message(_p(getfield(sys.csys, :sys), :parameters), ci)))
    i = _param_info(sys, x)
    return i isa Integer ? info(_p(getfield(sys.csys, :sys), :parameters)[i]).name : i
end
# a list setter (`setp(integ, [:k2, …])`, `setsym`) names a computed parameter with its route
function CorePotts.readonly_message(sys::PottsModelInfo, x)
    x isa Symbol && !isempty(_vector_components(getfield(sys.csys, :sys), _localize(getfield(sys.csys, :sys), x))) &&
        return _vector_message(getfield(sys.csys, :sys), _localize(getfield(sys.csys, :sys), x))
    ci = _computed_info(sys, x)
    return ci === nothing ? nothing : _computed_message(_p(getfield(sys.csys, :sys), :parameters), ci)
end
SII.parameter_symbols(sys::PottsModelInfo) = filter(x -> !_is_symbolic(info(x).default), _p(getfield(sys.csys, :sys), :parameters))
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
        n = i isa Integer ? info(_p(getfield(sys.csys, :sys), :parameters)[i]).name : i
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
SII.all_symbols(sys::PottsModelInfo) = vcat(SII.all_variable_symbols(sys), _p(getfield(sys.csys, :sys), :parameters), [t])
SII.default_values(::PottsModelInfo) = Dict()
SII.is_observed(sys::PottsModelInfo, x) = _potts_quantity(x) && !SII.is_parameter(sys, x) &&
    !SII.is_variable(sys, x) && !SII.is_independent_variable(sys, x)
function SII.observed(sys::PottsModelInfo, x)
    # a list of quantities (`sol[[a, b]]`, `getsym(sol, (a, b))`): one function per entry, read
    # together, a vector for a vector and a tuple for a tuple (SymbolicIndexingInterface's contract)
    if x isa Union{AbstractArray, Tuple}
        fs = map(y -> _entry_observed(sys, y), x isa Tuple ? x : collect(x))
        return x isa Tuple ? ((u, p, t) -> map(f -> f(u, p, t), fs)) : ((u, p, t) -> [f(u, p, t) for f in fs])
    end
    ci = _computed_info(sys, x)
    ci === nothing || (n = ci.name; return (u, p, t) -> getproperty(p, n))
    return _observed_function(sys, _localize(getfield(sys.csys, :sys), x; strict = true))
end
# one entry of a list read: a state variable by its index, anything else as observed
function _entry_observed(sys::PottsModelInfo, y)
    i = SII.is_variable(sys, y) ? SII.variable_index(sys, y) : nothing
    i === nothing || return (u, p, t) -> u[i]
    return SII.observed(sys, y)
end
# by name: `sol[:volume]`, `sol[:act]`, `sol[:mean_excess]`
function _named_quantity(sys::PottsModelInfo, x::Symbol)
    m = getfield(sys.csys, :sys)
    for v in Iterators.flatten((_p(m, :variables), (o.lhs for o in _p(m, :observed))))
        info(v).name === x && return v
    end
    return x in BUILTIN_NAMES ? getfield(B, x) : nothing
end
# a vector name (`u` of `@variables u(field)[1:2]`, an array field of a PDESystem) is observed
# only so that `sol[:u]` reaches `SII.observed`, which names its components
SII.is_observed(sys::PottsModelInfo, x::Symbol) = !SII.is_parameter(sys, x) && !SII.is_variable(sys, x) &&
    (
    _named_quantity(sys, _localize(getfield(sys.csys, :sys), x)) !== nothing ||
        _computed_info(sys, x) !== nothing ||
        !isempty(_vector_components(getfield(sys.csys, :sys), _localize(getfield(sys.csys, :sys), x)))
)
function SII.observed(sys::PottsModelInfo, x::Symbol)
    ci = _computed_info(sys, x)
    ci === nothing || (n = ci.name; return (u, p, t) -> getproperty(p, n))
    q = _named_quantity(sys, _localize(getfield(sys.csys, :sys), x))
    q === nothing && throw(ArgumentError(_vector_message(getfield(sys.csys, :sys), _localize(getfield(sys.csys, :sys), x))))
    return _observed_function(sys, q)
end
# the component names of the vector quantity `x` of model `m` (`[:u_1, :u_2]`), or none
_vector_components(m, x) = Symbol[
    info(v).name for v in Iterators.flatten((_p(m, :parameters), _p(m, :variables)))
        if get(info(v).options, :vector, nothing) === x
]
_vector_message(m, x) = "`$x` is a vector quantity of $(nameof(m)): read its components " *
    "($(join((":" * string(n) for n in _vector_components(m, x)), ", ")))"

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
_observe_quantity(sys::PottsModelInfo, x) = _localize(getfield(sys.csys, :sys), x; strict = true)
function _observe_quantity(sys::PottsModelInfo, x::Symbol)
    x = _localize(getfield(sys.csys, :sys), x; strict = true)
    q = _named_quantity(sys, x)
    q === nothing || return q
    m = getfield(sys.csys, :sys)
    for p in _p(m, :parameters)
        info(p).name === x && return p
    end
    msg = "`$x` is not a variable, observed quantity, built-in or parameter of $(nameof(sys.csys))"
    comps = [
        info(v).name for v in Iterators.flatten((_p(m, :parameters), _p(m, :variables)))
            if get(info(v).options, :vector, nothing) === x
    ]
    if !isempty(comps)
        msg *= "; `$x` is a vector quantity: observe its components ($(join((":" * string(n) for n in comps), ", ")))"
    elseif x === :t
        msg *= "; the times of a solution are `sol.t`"
    end
    throw(ArgumentError(msg))
end

SII.parameter_values(p::PottsParameters) = p
SII.parameter_values(p::PottsParameters, i::Symbol) = p[i]

"""
    Potts.field_inputs(integ) -> Dict{Symbol, Array}
    Potts.field_inputs(prob)

The current values of the CPM inputs of a model's fields, at the CPM state of an integrator
(the state at `integ.t`) or the initial state of a problem: one array over the lattice per
input of [`Potts.fields`](@ref)`(model)`, by the name it gives that input
(`lattice_input_name`): `kind` (the kind number of each site, 0 for the medium), `vol` for a
binding `vol => volume[owner]`, `volume[owner]` for a CPM read with no binding of its own, a
site variable by its name. Each array holds the values the field compiler reads for that
input: a `Bool` input gives a `Bool` array, an integer input an array of its type, any other
input an array of the model's scalar type. They are what `discretize(Potts.fields(model),
disc; inputs = collect(Potts.field_inputs(integ)))` takes: the fields solved by any SciML
solver with the CPM frozen at that state, a `Coarse(k)` field included. That solve matches the model's own run
only while the lattice does not change (σ frozen): in a run the CPM moves the cells every MCS
and the inputs follow them, while the frozen inputs do not. A model without such inputs gives
an empty `Dict`.

The values are computed from the CPM state at `integ.t` (the lattice and cells at the end of
the last completed MCS). They are not the arrays the field phase filled during that
MCS: a phase after it in the schedule (divisions and the other lifecycle rules, by default)
may have changed the lattice since.
"""
field_inputs(integ::CorePotts.PottsIntegrator) = _field_inputs_at(integ.f.sys, CorePotts.current_state(integ), integ.p, integ.t, _exported(integ.f.sys))
field_inputs(prob::CorePotts.PottsProblem) = _field_inputs_at(prob.f.sys, prob.u0, prob.p, prob.tspan[1], _exported(prob.f.sys))

"""
    Potts.field_inputs(integ, pdesys::PDESystem) -> Dict{Symbol, Array}
    Potts.field_inputs(prob, pdesys)

The current values of exactly the inputs of the PDESystem `pdesys`, by the names
`discretize(pdesys, disc; inputs)` takes (each input's `lattice_input_name`, else its own name).
For a PDESystem coupled into the model (`@fields c = pdesys (sec => kind == A, vol =>
volume[owner])`, `Potts.couple`), its inputs: a bound input holds its binding evaluated at
each site (`sec` the truth value of `kind == A`, `vol` the owner's volume), an unbound one the
model quantity that fills it (`kind`, a site variable). For [`Potts.fields`](@ref)`(model)`,
its own inputs, as `Potts.field_inputs(integ)` gives them. So

```julia
prob = discretize(pdesys, disc; inputs = collect(Potts.field_inputs(integ, pdesys)))
```

solves the user's own PDESystem with any SciML solver at the CPM state of `integ` (σ frozen, as
for [`Potts.field_inputs`](@ref)`(integ)`). A `Coarse(k)` field included: the coupled model
and `pdesys` fold a fine read over each block by the same rule (the block mean of a bound input
and of its binding written out alike), so the two agree on any cell layout, blocks that a cell
covers in part included. A PDESystem whose inputs are neither those of a
coupled PDESystem of the same name nor those of `Potts.fields(model)` is an `ArgumentError`
that names both lists.
"""
field_inputs(integ::CorePotts.PottsIntegrator, pdesys::ModelingToolkitBase.PDESystem) =
    _field_inputs_at(integ.f.sys, CorePotts.current_state(integ), integ.p, integ.t, _pde_inputs(integ.f.sys, pdesys))
field_inputs(prob::CorePotts.PottsProblem, pdesys::ModelingToolkitBase.PDESystem) =
    _field_inputs_at(prob.f.sys, prob.u0, prob.p, prob.tspan[1], _pde_inputs(prob.f.sys, pdesys))

_exported(info::PottsModelInfo) = lock(() -> get!(() -> _exported_inputs(info.csys), info.cache, :field_inputs), _OBSERVED_LOCK)
# the inputs of the PDESystem `f`, `(key, how, what, eltype)` as `_exported_inputs` gives them: a
# coupled PDESystem's (by its name; each a CPM expression filled at a site), else those of
# `Potts.fields(model)`
function _pde_inputs(info::PottsModelInfo, f::ModelingToolkitBase.PDESystem)
    want = Symbol[]
    for dv in getfield(f, :dvs)
        u = _unwrap(dv)
        (iscall(u) && ModelingToolkitBase.isinput(u)) || continue
        push!(want, Symbol(_input_key(u, operation(u))))
    end
    md = _p(getfield(info.csys, :sys), :metadata)
    coupled = [e for e in get(md, _FieldInputs, ()) if length(e) >= 4 && e[4] === nameof(f)]
    out = Tuple{Symbol, Symbol, Any, Type}[]
    if !isempty(coupled) && all(k -> any(e -> e[1] === k, coupled), want)
        for k in unique(want)
            e = coupled[findfirst(e -> e[1] === k, coupled)]
            push!(out, (k, :fill, e[2], e[3]))
        end
        return out
    end
    ex = _exported(info)
    all(k -> any(e -> e[1] === k, ex), want) && return [e for e in ex if e[1] in want]
    lst(ks) = isempty(ks) ? "none" : join(("`$k`" for k in ks), ", ")
    names = unique(Symbol[e[4] for e in get(md, _FieldInputs, ()) if length(e) >= 4])
    throw(
        ArgumentError(
            string(
                "Potts.field_inputs: the inputs of the PDESystem `", nameof(f), "` (", lst(want), ") are ",
                "neither those of a PDESystem of that name coupled into the model (",
                isempty(names) ? "it has none" : string("its coupled PDESystems: ", lst(names)), isempty(coupled) ? "" :
                    string("; `", nameof(f), "` has ", lst(unique(Symbol[e[1] for e in coupled]))), ") nor those of `Potts.fields(model)` (",
                lst([e[1] for e in ex]), "); give the PDESystem that `@fields` or `Potts.couple` took, or `Potts.fields(model)`"
            )
        )
    )
end

function _field_inputs_at(info::PottsModelInfo, u, p, t, ins)
    c = info.csys
    out = Dict{Symbol, Array}()
    for (key, how, ex, E) in ins
        v = if how === :fill
            f = lock(_OBSERVED_LOCK) do
                get!(info.cache, (:field_input, ex)) do
                    code = _with_model_scope(() -> lower(ex, _site_env(info.T, :i, getfield(c, :gather_names); mcs = :t)), c)
                    _SiteValues(_rgf(:((st, p, ctx, t, i) -> $code)))
                end
            end
            f(u, p, info.ctx, t)
        elseif how === :domain
            m = core_lattice(_p(getfield(c, :sys), :lattice)).mask
            m === nothing ? trues(size(u.ownership)) : collect(m)
        else
            collect(getproperty(u.site, ex))
        end
        # the values the field compiler uses, converted exactly (a value the element type cannot
        # hold is an InexactError, never a rounded or truncated value)
        out[key] = E === Bool ? Bool.(v) : E <: Integer ? E.(v) : info.T.(v)
    end
    return out
end
# the inputs of `Potts.fields(c)`: `(key, how, what, eltype)`, `how` one of `:fill` (a CPM
# expression `what`, `kind` or a CPM read), `:domain` (the lattice's mask) and `:site` (the site
# array named `what`: a site variable or a field the PDESystem reads)
function _exported_inputs(c::CompiledPottsSystem)
    out = Tuple{Symbol, Symbol, Any, Type}[]
    F = fields(getfield(c, :sys))
    F === nothing && return out
    isempty(_field_equations(getfield(c, :sys))) && isempty(_field_aux(getfield(c, :sys))) && return out    # a hand-wrapped PDESystem
    filled = Dict{Symbol, Any}(e[1] => e for e in _field_inputs(c, Float64))
    # (an input `Potts.fields` names by its binding, `vol`: the generated input it holds)
    back = Dict{Symbol, Symbol}(Symbol(w) => g for (g, w) in _input_names(getfield(c, :sys)))
    for dv in getfield(F, :dvs)
        x = _unwrap(dv)
        ModelingToolkitBase.isinput(x) || continue
        op = Symbol(nameof(operation(x)))
        op = get(back, op, op)
        key = Symbol(something(LatticePDE.get_lattice_input_name(x), string(op)))
        st = SymbolicUtils.symtype(x)
        E = st <: Bool ? Bool : st <: Integer ? Int32 : Real
        if op === :domain__in
            push!(out, (key, :domain, nothing, Bool))
        elseif haskey(filled, op)
            push!(out, (key, :fill, filled[op][2], filled[op][3]))
        else
            push!(out, (key, :site, op, E))
        end
    end
    return out
end
