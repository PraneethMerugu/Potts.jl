# Entity-local initialization through ModelingToolkit (P6.0bo, D-170; route A1 of the
# MTK-native plan). The `@initialization_equations` of each scope (cell, model) are the
# `initialization_eqs` of one MTK `System`, the template of one cell (or the model), built at
# `mtkcompile` (`initialization_system`). When a problem is built, Potts builds MTK's
# `InitializationProblem` of that scope once, with what is fixed for this problem (written
# values, operating-point values, built-ins, model values) as its parameters, and solves it
# for every cell on the host, before the first MCS: the model first, then the cells. The
# batched kernels are unchanged.
#
# Semantics are MTK's, made strict (`fully_determined`): a written value (`= 0.0` included) or
# an operating-point value fixes a variable, a variable declared without one is solved for
# when its scope's conditions name it. An operating-point value of an algebraic variable
# (`y ~ expr` in `@equations`) is the condition `expr ~ value`. Potts checks the counts itself
# (a matching of conditions to free variables), so the messages name the variables, and so
# what is accepted does not depend on whether full ModelingToolkit (with its least-squares
# fallbacks) is loaded. Every result is checked against the conditions themselves
# (`_InitCheck`: a residual small against the size of the terms, and a Jacobian that is not
# singular), so a condition without a solution, or without a unique one, is an error rather
# than a least-squares answer or the guess. Cross-entity reads (another cell, gathers, folds,
# site, field and edge variables) are refused until P6.4a (R17).

"""
    Potts.initialization_system(csys::CompiledPottsSystem, scope::Symbol)

The ModelingToolkit system of the cell (`scope = :cell`) or model (`scope = :model`)
initialization of a compiled model: a complete `System` whose `initialization_equations` are
that scope's `@initialization_equations`, one per equation as written, or `nothing` when the
scope has none.

- Its unknowns are the scope's variables the equations name, under their declared names. A
  variable declared without a value (`r(cell)`) has none here, so initialization solves for
  it; its guess (`r(cell), [guess = -1.0]`) is the system's guess. A variable with a written
  value has that value as its initial condition.
- Each declared parameter the equations read is a parameter under its declared name, with
  its declared value.
- Everything else the equations read (built-ins such as `volume` and `id`, a kind table at
  the cell's kind, `g[kind]`, as `g_kind`, model variables in the cell system) is an input:
  a further parameter standing for that quantity.
- `D(x)` of a cell or model ODE variable is its rate at the start (`D(x) ~ 0` is a steady
  start): the system carries the ODE `D(x) ~ rate`, and every other unknown `D(v) ~ 0`.

An equation that reads no cell quantity is in the model system. A system without inputs is
an ordinary MTK system, which `ModelingToolkitBase.InitializationProblem` accepts.

When a problem is built (and on `remake(prob; u0 = map)`, not on `remake(prob; p = …)`),
Potts solves the model system once and then the cell system for every cell, with that cell's
built-ins, fixed values and the model's values as inputs, and checks each result against the
equations: one without a solution, or without a unique one (a singular Jacobian), is an
`ArgumentError` naming the cell and the variables. An operating-point value for an algebraic variable is a condition
of that problem alone and builds no system here. Any other scope, or a `PottsSystem` that has
not been through `mtkcompile`, is an `ArgumentError`.
"""
function initialization_system(c::CompiledPottsSystem, scope::Symbol)
    scope in _ODE_SCOPES || throw(ArgumentError(
        "initialization_system: the scope is `:cell` or `:model`; got `:$scope` (site, field and edge " *
        "initialization reads across entities, planned in P6.4a)"))
    s = get(c.initialization, scope, nothing)
    return s === nothing ? nothing : s.template
end
initialization_system(sys::PottsSystem, ::Symbol) = throw(ArgumentError(
    "initialization_system: `$(nameof(sys))` has not been compiled; call `initialization_system(mtkcompile(sys), scope)`"))

"""One scope's `@initialization_equations`, compiled (`_compile_initialization`)."""
struct _InitScope
    authored::Vector{Equation}       # as written
    conditions::Vector{Equation}     # algebraic variables and `D(x)` replaced by their definitions and rates
    template::ModelingToolkitBase.System
end

# what initialization equations read of a cell besides its variables
const _INIT_BUILTINS = (:volume, :id, :kind)

const _INIT_LOCAL = "initialization equations are entity-local: they read a cell's own variables, its built-ins " *
                    "`volume`, `id` and `kind`, parameters, model variables and `D(x)` of ODE variables"

# `f()`, an error naming initialization equation `eq` and where it was written
function _init_located(f, sys::PottsSystem, eq)
    try
        return f()
    catch e
        e isa Union{ArgumentError, ErrorException} || rethrow()
        occursin("\n  in ", e.msg) && rethrow()
        ln = get(getfield(sys, :sources), eq, nothing)
        loc = ln === nothing ? "" : " at $(ln.file):$(ln.line)"
        throw(ArgumentError("$(e.msg)\n  in @initialization_equations $eq$loc"))
    end
end

"""
The `@initialization_equations` of a model by scope: each checked (entity-local reads only),
algebraic variables replaced by their definitions, and its MTK template. Empty when the model
has none (every published model), which costs nothing.
"""
function _compile_initialization(sys::PottsSystem)
    out = Dict{Symbol, _InitScope}()
    eqs = getfield(sys, :initialization_eqs)
    isempty(eqs) && return out
    defs = Dict{Symbol, Any}(info(o.var).name => _unwrap(o.expr) for o in _algebraic_observed(sys))
    rates = _init_rates(sys)
    byscope = Dict{Symbol, Vector{Tuple{Equation, Equation, Equation}}}()
    for eq in eqs
        _init_located(sys, eq) do
            # `y` defined by `y ~ expr` in @equations reads as its definition (MTK observed)
            e = _init_defs(eq, defs)
            what = "the initialization equation `$eq`"
            _check_init_reads(e, what)
            r = _init_with_rates(e, rates, what)
            scope = _reads_cell(r) ? :cell : :model
            push!(get!(byscope, scope, Tuple{Equation, Equation, Equation}[]), (eq, e, r))
        end
    end
    for scope in _ODE_SCOPES
        list = get(byscope, scope, nothing)
        list === nothing && continue
        out[scope] = _InitScope([x[1] for x in list], [x[3] for x in list],
            _init_template(sys, scope, [x[2] for x in list], rates))
    end
    return out
end

# the cell and model ODEs: variable name → (variable, rate), the rates as simplified by
# `mtkcompile` (odes.jl)
function _init_rates(sys::PottsSystem)
    rates = Dict{Symbol, Tuple{Any, Any}}()
    for eq in getfield(sys, :equations)
        l = _unwrap(eq.lhs)
        _is_derivative(l) || continue
        x = arguments(l)[1]
        i = info(x)
        i !== nothing && i.role in _ODE_SCOPES && (rates[i.name] = (x, _unwrap(eq.rhs)))
    end
    return rates
end

function _init_defs(eq::Equation, defs)
    isempty(defs) && return eq
    sub = Dict{Any, Any}()
    for side in (eq.lhs, eq.rhs)
        _walk(side) do y
            i = info(y)
            i !== nothing && i.role in _ODE_SCOPES && haskey(defs, i.name) && (sub[y] = defs[i.name])
        end
    end
    isempty(sub) && return eq
    return _init_substitute(eq.lhs, sub) ~ _init_substitute(eq.rhs, sub)
end
_init_substitute(x, sub) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic ? Symbolics.substitute(u, sub; fold = Val(false)) : u)

# a read of a kind table at the cell's own kind (`g[kind]`, lowered to `at(g, kind)`)
function _kind_read(y)
    (iscall(y) && (operation(y) === at || operation(y) === at2)) || return false
    i = info(_unwrap(arguments(y)[1]))
    return i !== nothing && i.role === :kindtable
end
_own_kind(k) = (i = info(_unwrap(k)); i !== nothing && i.role === :builtin && i.name === :kind)

# `_walk`, but a kind-table read is one quantity (its table and index are not visited)
function _init_walk(f, x)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return
    f(x)
    _kind_read(x) && return
    if iscall(x) && !(info(x) !== nothing && info(x).role in SCOPES)
        foreach(a -> _init_walk(f, a), arguments(x))
    end
    return
end

# Every read of `x` is entity-local: the scope's variables, built-ins of the cell, parameters,
# kind tables at the cell's own kind, model variables, `D(x)` of an ODE variable, and plain
# functions of them.
function _check_init_reads(x, what)
    for side in (x isa Equation ? (x.lhs, x.rhs) : (x,))
        _init_walk(side) do y
            if _kind_read(y)
                args = arguments(y)
                all(_own_kind, args[2:end]) && return
                n = info(_unwrap(args[1])).name
                throw(ArgumentError("$what reads the kind table `$n` at `$(join(args[2:end], ", "))`; in initialization " *
                                    "equations a kind table is read at the cell's own kind (`$n[kind]`, or " *
                                    "`$n[kind, kind]` for a matrix); $(_INIT_LOCAL)"))
            end
            i = info(y)
            if i !== nothing
                (i.role in _ODE_SCOPES || i.role === :param) && return
                i.role === :builtin && i.name in _INIT_BUILTINS && return
                i.role === :kindtable && throw(ArgumentError(
                    "$what reads the kind table `$(i.name)` as a whole; read it at the cell's own kind (`$(i.name)[kind]`)"))
                i.role in (:site, :field, :edge) && throw(ArgumentError(
                    "$what reads the $(i.role) variable `$(i.name)`; $(_INIT_LOCAL). Initialization of site, field " *
                    "and edge variables reads across entities and is planned (P6.4a)"))
                i.role === :builtin && throw(ArgumentError(
                    "$what reads the built-in `$(i.name)`, which has no value at initialization; $(_INIT_LOCAL)"))
                throw(ArgumentError("$what reads `$(i.name)` (a $(i.role) quantity); $(_INIT_LOCAL)"))
            end
            if !iscall(y)
                SymbolicUtils.isconst(y) && return
                throw(ArgumentError("$what reads `$y`, which is not a quantity of the model; $(_INIT_LOCAL)"))
            end
            op = operation(y)
            op isa Differential && return                    # checked with its rate (`_init_with_rates`)
            _template_op(op) && return
            op isa Function || throw(ArgumentError(
                "$what reads `$y`, which is not a cell or model variable of the model (a component's variables are " *
                "initialized by the component); $(_INIT_LOCAL)"))
            if op === at || op === at2
                v = info(_unwrap(arguments(y)[1]))
                n = v === nothing ? string(arguments(y)[1]) : string(v.name)
                throw(ArgumentError("$what reads `$n` of another cell (`$y`); $(_INIT_LOCAL). Cross-entity " *
                                    "initialization is planned (P6.4a)"))
            end
            throw(ArgumentError("$what reads `$y`, which reads across entities (a neighbour gather, a fold over " *
                                "cells, an integral, a draw or a previous value); $(_INIT_LOCAL). Cross-entity " *
                                "initialization is planned (P6.4a)"))
        end
    end
    return nothing
end

# `D(x)` replaced by the rate of `x` (its value at the start), checked like the equation
function _init_with_rates(eq::Equation, rates, what)
    sub = Dict{Any, Any}()
    for side in (eq.lhs, eq.rhs)
        _walk(side) do y
            (iscall(y) && operation(y) isa Differential) || return
            a = _unwrap(arguments(y)[1])
            i = info(a)
            dx = "D($(i === nothing ? a : i.name))"
            (i !== nothing && i.role in _ODE_SCOPES && haskey(rates, i.name)) || throw(ArgumentError(
                "$what reads `$dx`, but `$(i === nothing ? a : i.name)` has no ODE; `D(x)` is read for a cell or model " *
                "variable `x` with an ODE `D(x) ~ rate` in @equations"))
            r = rates[i.name][2]
            _check_init_reads(r, "`$dx` (the rate `$r` of `$(i.name)`) in $what")
            sub[y] = r
        end
    end
    isempty(sub) && return eq
    return _init_substitute(eq.lhs, sub) ~ _init_substitute(eq.rhs, sub)
end

# whether `x` reads a cell quantity (a cell variable or a built-in of the cell)
function _reads_cell(x)
    found = Ref(false)
    for side in (x isa Equation ? (x.lhs, x.rhs) : (x,))
        _walk(side) do y
            i = info(y)
            i !== nothing && (i.role === :cell || (i.role === :builtin && i.name in _INIT_BUILTINS)) && (found[] = true)
        end
    end
    return found[]
end

# the variables of `scope` that `xs` read, in order of first appearance
function _scope_vars(xs, scope)
    out = Any[]
    seen = Set{Symbol}()
    for x in xs, side in (x isa Equation ? (x.lhs, x.rhs) : (x,))
        _walk(side) do y
            i = info(y)
            i !== nothing && i.role === scope && !(i.name in seen) && (push!(seen, i.name); push!(out, y))
        end
    end
    return out
end

_init_guess(x) = (g = ModelingToolkitBase.getguess(x); g === nothing ? 0.0 : g)

"""
The public template of one scope (`initialization_system`): the scope's variables the
equations `eqs` name are its unknowns (`D(x) ~ rate` for an ODE variable whose `D(x)` they
read, else `D(v) ~ 0`), declared parameters its parameters, other quantities inputs, and
`eqs` its `initialization_eqs`.
"""
function _init_template(sys::PottsSystem, scope::Symbol, eqs, rates)
    dread = Set{Symbol}()
    for eq in eqs, side in (eq.lhs, eq.rhs)
        _walk(y -> (iscall(y) && operation(y) isa Differential && push!(dread, info(_unwrap(arguments(y)[1])).name)), side)
    end
    # `D(m)` of a model variable read by a cell equation is the model's rate, an input here
    other = Dict{Any, Any}(D(rates[n][1]) => rates[n][2] for n in dread if info(rates[n][1]).role !== scope)
    isempty(other) || (eqs = Equation[_init_substitute(eq.lhs, other) ~ _init_substitute(eq.rhs, other) for eq in eqs])
    odes = Any[rates[n][2] for n in dread if info(rates[n][1]).role === scope]
    vars = _scope_vars(Any[eqs; odes], scope)
    params = Any[]
    inputs = Dict{Any, Any}()
    ics = Dict{Any, Any}()
    taken = Set{Symbol}(info(x).name for x in Iterators.flatten((getfield(sys, :parameters), getfield(sys, :variables))))
    function input(y)
        haskey(inputs, y) && return
        i = _kind_read(y) ? nothing : info(y)
        if i === nothing                                # `g[kind]`: the cell's entry, an input
            n0 = Symbol(info(_unwrap(arguments(y)[1])).name, :_kind)
            n = n0
            k = 1
            while n in taken
                n = Symbol(n0, :_, k += 1)
            end
            push!(taken, n)
            p = _unwrap(ModelingToolkitBase.toparam(Symbolics.variable(n)))
        elseif i.role === :param
            p = _unwrap(ModelingToolkitBase.toparam(y))
            i.default isa Real && (ics[p] = i.default)
        else                                            # a built-in or a model variable in a cell system
            n = i.name
            k = 1
            while i.role === :builtin && n in taken
                n = Symbol(i.name, :_, k += 1)
            end
            p = _unwrap(ModelingToolkitBase.toparam(Symbolics.variable(n; T = SymbolicUtils.symtype(y))))
        end
        push!(params, p)
        inputs[y] = p
        return
    end
    # the written values of the fixed variables are initial conditions: their parameters too
    written = Any[info(x).default for x in vars if _written(x) && _is_symbolic(info(x).default)]
    for x in Any[eqs; odes; written], side in (x isa Equation ? (x.lhs, x.rhs) : (x,))
        _init_walk(side) do y
            _kind_read(y) && return input(y)
            i = info(y)
            i === nothing || i.role === scope || input(y)
        end
    end
    sub(x) = isempty(inputs) ? _unwrap(x) : _init_substitute(x, inputs)
    deqs = Equation[n in dread && info(rates[n][1]).role === scope ? (D(rates[n][1]) ~ sub(rates[n][2])) : (D(x) ~ 0)
                    for x in vars for n in (info(x).name,)]
    guesses = Dict{Any, Any}()
    for x in vars
        if _written(x)
            d = info(x).default
            d isa Real ? (ics[x] = d) : (_is_symbolic(d) && (ics[x] = sub(d)))
        else
            guesses[x] = _init_guess(x)
        end
    end
    template = ModelingToolkitBase.System(deqs, t, vars, params; name = Symbol(nameof(sys), :₊, scope, :_init),
        initialization_eqs = Equation[sub(eq.lhs) ~ sub(eq.rhs) for eq in eqs], guesses, initial_conditions = ics,
        checks = ModelingToolkitBase.CheckComponents)
    return ModelingToolkitBase.complete(template)
end

# ---------------------------------------------------------------------------------------
# Running: once per problem, before the first MCS

"""
Initialize the cell and model variables of a state being built (`_initial_state`): the
model's conditions first, then each cell's. `cell` and `model` are the state's columns
(name => array) and are written in place.
"""
function _initialize!(c::CompiledPottsSystem, opd, σ, kinds, ncell, cell, model, pvals)
    sys = c.sys
    alg = _algebraic_observed(sys)
    conds = isempty(alg) ? Any[] : Any[o for o in alg if haskey(opd, _unwrap(o.var))]
    isempty(c.initialization) && isempty(conds) && return nothing
    volume = zeros(Float64, ncell)
    for l in σ
        l > 0 && (volume[l] += 1)
    end
    builtins = (; volume, id = Float64.(1:ncell), kind = Float64.(kinds))
    for scope in (:model, :cell)
        s = get(c.initialization, scope, nothing)
        cs = Any[o for o in conds if info(o.var).options.scope === scope]
        s === nothing && isempty(cs) && continue
        scope === :cell && ncell == 0 && continue
        _initialize_scope!(c, scope, s, cs, opd, builtins, scope === :cell ? ncell : 1, cell, model, pvals)
    end
    return nothing
end

_column(cols, n) = last(cols[findfirst(q -> q.first === n, cols)])

function _initialize_scope!(c::CompiledPottsSystem, scope, s, conds, opd, builtins, n, cell, model, pvals)
    sys = c.sys
    where_ = scope === :cell ? "the cells" : "the model"
    authored = s === nothing ? Equation[] : s.authored
    eqs = s === nothing ? Equation[] : s.conditions
    # an operating-point value of an algebraic variable `y`: the condition `definition ~ value`
    values = Any[]
    for o in conds
        name = info(o.var).name
        what = "the operating-point value of the algebraic variable `$name` (the condition `$name ~ value`, `$name ~ $(o.expr)`)"
        _check_init_reads(o.expr, what)
        v = _evaluate(opd[_unwrap(o.var)], pvals, "the operating-point value of `$name`")
        v isa AbstractArray ? (length(v) == n || throw(ArgumentError("$(length(v)) values of `$name` for $n entities"))) :
        v isa Real || throw(ArgumentError("the operating-point value of `$name`: a number or one number per cell; got $(repr(v))"))
        push!(values, v)
    end
    exprs = Any[eqs; [o.expr for o in conds]]
    vars = _scope_vars(exprs, scope)
    # fixed: a written value or an operating-point value, read from the declaration
    declared = Dict{Symbol, Any}(info(x).name => _unwrap(x) for x in getfield(sys, :variables))
    fixed(x) = (d = get(declared, info(x).name, _unwrap(x)); haskey(opd, d) || _written(d))
    free = Any[x for x in vars if !fixed(x)]
    # the count, by a matching of conditions to free variables: names what is over- or
    # underdetermined (MTK would refuse it too, `fully_determined`, without naming it)
    rows = [(; text = i <= length(eqs) ? "`$(authored[i])`" : "the operating-point value of the algebraic variable `$(info(conds[i - length(eqs)].var).name)`",
                label = i <= length(eqs) ? nothing : info(conds[i - length(eqs)].var).name,
                free = Set{Symbol}(info(x).name for x in _scope_vars((exprs[i],), scope) if !fixed(x)),
                fixed = Symbol[info(x).name for x in _scope_vars((exprs[i],), scope) if fixed(x)],
                model = scope === :cell ? Symbol[info(x).name for x in _scope_vars((exprs[i],), :model)] : Symbol[])
            for i in eachindex(exprs)]
    _check_determined(where_, rows, Symbol[info(x).name for x in free])
    # what is fixed for this problem is a parameter of the problem: built-ins, fixed values,
    # the model's values (in a cell), parameters and the conditions' values
    params = Any[]
    sources = Any[]
    pmap = Dict{Any, Any}()
    taken = Set{Symbol}(info(x).name for x in free)
    function fresh(base)
        k = 1
        nm = base
        while nm in taken
            nm = Symbol(base, :_, k += 1)
        end
        push!(taken, nm)
        return _unwrap(ModelingToolkitBase.toparam(Symbolics.variable(nm)))
    end
    for x in exprs, side in (x isa Equation ? (x.lhs, x.rhs) : (x,))
        _init_walk(side) do y
            haskey(pmap, y) && return
            if _kind_read(y)                            # `g[kind]`: the cell's entry of the table
                g = _unwrap(arguments(y)[1])
                src = (:table, pvals[g], length(arguments(y)) - 1, "the kind table `$(info(g).name)`")
                p = fresh(Symbol(info(g).name, :_kind))
            else
                i = info(y)
                (i === nothing || (i.role === scope && !fixed(y))) && return
                src = i.role === :builtin ? (:builtin, i.name) :
                      i.role === :param ? (:param, Float64(_numeric(pvals[_unwrap(y)], "parameter `$(i.name)`"))) :
                      (i.role, i.name)
                p = fresh(i.name)
            end
            pmap[y] = p
            push!(params, p)
            push!(sources, src)
        end
    end
    targets = Any[]
    for (j, o) in enumerate(conds)
        p = fresh(Symbol(info(o.var).name, :_value))
        push!(params, p)
        push!(sources, (:condition, j))
        push!(targets, p)
    end
    sub(x) = isempty(pmap) ? _unwrap(x) : _init_substitute(x, pmap)
    ieqs = Equation[[sub(eq.lhs) ~ sub(eq.rhs) for eq in eqs]; [sub(o.expr) ~ p for (o, p) in zip(conds, targets)]]
    value(src, k) = src[1] === :builtin ? getproperty(builtins, src[2])[k] :
                    src[1] === :param ? src[2] :
                    src[1] === :table ? Float64(_table_entry(src[4], src[2], ntuple(_ -> Int(builtins.kind[k]), src[3])...)) :
                    src[1] === :condition ? (v = values[src[2]]; Float64(v isa AbstractArray ? v[k] : v)) :
                    src[1] === :cell ? Float64(_column(cell, src[2])[k]) : Float64(_column(model, src[2])[1])
    vals(k) = Float64[value(src, k) for src in sources]
    names = join(("`$(info(x).name)`" for x in free), ", ")
    ip = try
        isys = ModelingToolkitBase.System(Equation[D(x) ~ 0 for x in free], t, free, params;
            name = Symbol(nameof(sys), :₊, scope, :_initialization), initialization_eqs = ieqs,
            checks = ModelingToolkitBase.CheckComponents)
        ModelingToolkitBase.InitializationProblem(ModelingToolkitBase.complete(isys), 0.0, Dict{Any, Any}(zip(params, vals(1)));
            guesses = Dict{Any, Any}(x => _init_guess(x) for x in free), fully_determined = true, use_scc = false)
    catch e
        e isa ArgumentError && rethrow()
        throw(ArgumentError("initialization of $where_: ModelingToolkit could not build the initialization problem for " *
                            "$names: $(first(sprint(showerror, e), 2000))"))
    end
    # the parameters are written by index into MTK's parameter object (its type is the same
    # for these templates, so the workload's compiled `setindex!` serves every model)
    pv = SymbolicIndexingInterface.parameter_values(ip)
    pindex = Any[SymbolicIndexingInterface.parameter_index(ip, p) for p in params]
    setter!(vs) = (foreach((i, v) -> setindex!(pv, v, i), pindex, vs); nothing)
    # MTK builds a `NonlinearProblem` (state: the implicit unknowns), one without a state when
    # every condition is explicit (its values are MTK's observed values), or, for a linear
    # system, an `SCCNonlinearProblem` around a `LinearProblem`
    plain = ip isa SciMLBase.NonlinearProblem
    u0 = plain ? ip.u0 : nothing
    explicit = plain && (u0 === nothing || isempty(u0))
    # the solved unknowns are read from the state by index, the eliminated ones as MTK's observed
    # values (one observed getter, compiled per model, only for these)
    index = Any[plain && !explicit ? SymbolicIndexingInterface.variable_index(ip, x) : nothing for x in free]
    observed = Any[x for (x, i) in zip(free, index) if i === nothing]
    getter = isempty(observed) ? nothing : SymbolicIndexingInterface.getu(ip, observed)
    opos = cumsum(Int[i === nothing for i in index])           # position among the observed
    guess = plain && !explicit ? Float64.(u0) : nothing
    # MTK's residual behind one fixed function type, so the nonlinear solve compiled by the
    # precompile workload serves every model (the residual's own type changes per model)
    nlp = guess === nothing ? nothing : SciMLBase.NonlinearProblem(SciMLBase.NonlinearFunction{true, SciMLBase.FullSpecialize}(
        _InitResidual(ip.f, SymbolicIndexingInterface.parameter_values(ip))), copy(guess), nothing)
    # the free values at the state `x` of the nonlinear problem (the observed ones by MTK)
    function at_state(x)
        u0 .= x
        obs = getter === nothing ? () : getter(ip)
        return Float64[i === nothing ? obs[opos[q]] : x[i] for (q, i) in enumerate(index)]
    end
    # every result is checked against the conditions themselves (`_InitCheck`): a solve may stop
    # on a small absolute residual, and a linear solve may return a least-squares answer
    check = _InitCheck(ieqs, params, free)
    dst = Any[_column(scope === :cell ? cell : model, info(x).name) for x in free]
    entity(k) = scope === :cell ? "cell $k" : "the model"
    conditions = join((r.text for r in rows), ", ")
    zero_guess = nlp !== nothing && any(x -> ModelingToolkitBase.getguess(x) === nothing, free)
    hint = zero_guess ? " (a variable without a guess starts from 0.0, where the Jacobian of an equation symmetric " *
                        "in it, such as `r^2 ~ volume`, is singular: give it one, `r(cell), [guess = 1.0]`)" : ""
    failed(k, why) = throw(ArgumentError(
        "initialization of $(entity(k)) found no solution for $names ($why); check $conditions and the guesses$hint"))
    solving(f, k) = try
        f()
    catch e
        (e isa InterruptException || e isa ArgumentError) && rethrow()
        failed(k, "the solve failed: $(first(sprint(showerror, e), 300))")
    end
    for k in 1:n
        pk = vals(k)
        setter!(pk)
        retcode = nothing
        out = if explicit                              # MTK's observed values
            getter(ip)
        elseif nlp !== nothing
            # Newton from the guess, stopped on a residual small against the terms of the
            # conditions (`_INIT_NEWTON_RTOL`), restarted with a tighter tolerance and a
            # finite-difference step at the scale of the iterate while the result fails the check
            nlp.u0 .= guess
            abstol = _INIT_NEWTON_RTOL * max(maximum(_init_scales(check, pk, at_state(guess)); init = 0.0), floatmin(Float64))
            step = _init_step(guess)
            local x
            for _ in 1:_INIT_ROUNDS
                sol = solving(() -> SciMLBase.solve(nlp, _init_solver(step); abstol, maxiters = 100), k)
                retcode = sol.retcode
                x = at_state(sol.u)
                all(isfinite, x) || break
                _init_residual(check, pk, x) === nothing && break
                tighter = _INIT_NEWTON_RTOL * minimum((v for v in _init_scales(check, pk, x) if v > 0); init = floatmin(Float64))
                step2 = _init_step(sol.u)
                (tighter < abstol / 2 || !(step / 2 < step2 < 2step)) || break
                abstol = min(abstol, tighter)
                step = step2
                nlp.u0 .= sol.u
            end
            x
        else
            sol = solving(() -> SciMLBase.solve(ip, _INIT_SOLVER), k)
            retcode = sol.retcode
            getter(sol)
        end
        for (j, v) in enumerate(out)
            isfinite(v) || failed(k, "it gives `$(info(free[j]).name)` = $v" *
                                     (retcode === nothing ? "" : "; the solve stopped with $retcode"))
        end
        bad = _init_residual(check, pk, out)
        if bad !== nothing
            r, res, sc = bad
            failed(k, "$(rows[r].text) is not satisfied: residual $res against terms of size $sc" *
                      (retcode === nothing ? "" : "; the solve stopped with $retcode"))
        end
        _init_singular(check, pk, out) && throw(ArgumentError(
            "initialization of $(entity(k)) does not determine $names uniquely: the conditions are dependent there " *
            "(their Jacobian at the solution is singular, as for `a + b ~ volume` with `2a + 2b ~ 2volume`, a " *
            "coefficient that is zero for this $(scope === :cell ? "cell" : "model"), or a repeated root); check $conditions"))
        for (j, v) in enumerate(out)
            dst[j][k] = v
        end
    end
    return nothing
end

# The nonlinear solver of initialization (MTKB has no default): Newton from the guess, with a
# finite-difference Jacobian, so the residual is never compiled for dual numbers (≈ 0.2 s per
# model cold), and a step that follows the scale of the values. It stops when MTK's residual is below `_INIT_NEWTON_RTOL` times the size of the
# conditions' terms (`_init_scales`), tightened over up to `_INIT_ROUNDS` restarts while the
# result fails the check; the result is accepted when every condition holds to `_INIT_RTOL`
# relative to its terms (D-158: 1e-9 is the tolerance of nonlinear values).
const _INIT_FD = cbrt(eps(Float64))
# central differences, the step `_INIT_FD` relative to each value and at least `_INIT_FD * scale`
# (one concrete solver type for every scale, compiled once)
_init_solver(scale::Float64) = SimpleNewtonRaphson(;
    autodiff = AutoFiniteDiff(; fdtype = Val(:central), relstep = _INIT_FD, absstep = _INIT_FD * scale))
const _INIT_SOLVER = _init_solver(1.0)
# the scale of the step: the smallest nonzero magnitude among the values (1 when all are zero)
_init_step(x) = (s = minimum((abs(v) for v in x if v != 0); init = Inf); isfinite(s) ? Float64(s) : 1.0)
const _INIT_NEWTON_RTOL = 1.0e-13
const _INIT_RTOL = 1.0e-9
const _INIT_ROUNDS = 6
# the Jacobian of the conditions, equilibrated, is singular below this ratio of singular values
const _INIT_SINGULAR = 1.0e-8

"""
The conditions of one scope as a tape of numeric operations on (parameters…, free values…),
evaluated without compiling anything per model: each condition's residual `lhs - rhs` and the
size of its terms (`|a| + |b|` for a sum, `|a|·|b|` for a product, `|a|^n`, `|a|/|b|`,
otherwise the magnitude of the value), against which the residual is judged.
"""
struct _InitCheck
    code::Vector{UInt8}          # 0 constant, 1 input, 2 operation
    num::Vector{Float64}         # the constant, or the input's position
    op::Vector{Any}
    args::Vector{Vector{Int}}
    rows::Vector{Tuple{Int, Int}}
    v::Vector{Float64}
    m::Vector{Float64}
    inputs::Vector{Float64}
    np::Int
end

function _InitCheck(eqs, params, free)
    slot = Dict{Any, Int}()
    for (j, x) in enumerate(Iterators.flatten((params, free)))
        slot[_unwrap(x)] = j
    end
    code = UInt8[]; num = Float64[]; op = Any[]; args = Vector{Int}[]
    memo = Dict{Any, Int}()
    node!(c, x, o, a) = (push!(code, c); push!(num, x); push!(op, o); push!(args, a); length(code))
    function build(y)
        y = _unwrap(y)
        haskey(memo, y) && return memo[y]
        j = get(slot, y, 0)
        id = if j > 0
            node!(0x01, j, nothing, Int[])
        elseif y isa Number
            node!(0x00, Float64(y), nothing, Int[])
        elseif SymbolicUtils.isconst(y)
            node!(0x00, Float64(SymbolicUtils.unwrap_const(y)), nothing, Int[])
        elseif iscall(y)
            a = Int[build(z) for z in arguments(y)]
            node!(0x02, 0.0, operation(y), a)
        else
            throw(ArgumentError("initialization: `$y` is not a quantity of the conditions"))
        end
        memo[y] = id
        return id
    end
    rows = Tuple{Int, Int}[(build(eq.lhs), build(eq.rhs)) for eq in eqs]
    nn = length(code)
    return _InitCheck(code, num, op, args, rows, zeros(nn), zeros(nn), zeros(length(params) + length(free)), length(params))
end

function _init_eval!(c::_InitCheck, p, x)
    inp = c.inputs
    inp[1:c.np] .= p
    inp[(c.np + 1):end] .= x
    v = c.v
    m = c.m
    for i in eachindex(c.code)
        code = c.code[i]
        if code === 0x00
            v[i] = c.num[i]
            m[i] = abs(v[i])
        elseif code === 0x01
            v[i] = inp[Int(c.num[i])]
            m[i] = abs(v[i])
        else
            f = c.op[i]
            a = c.args[i]
            if f === ifelse
                b = v[a[1]] != 0 ? a[2] : a[3]
                v[i] = v[b]
                m[i] = m[b]
            elseif f === (+)
                s = 0.0; t = 0.0
                for j in a
                    s += v[j]; t += m[j]
                end
                v[i] = s; m[i] = t
            elseif f === (*)
                s = 1.0; t = 1.0
                for j in a
                    s *= v[j]; t *= m[j]
                end
                v[i] = s; m[i] = t
            elseif f === (^) && length(a) == 2
                v[i] = Float64(v[a[1]]^v[a[2]])
                m[i] = c.code[a[2]] === 0x00 && v[a[2]] > 0 ? m[a[1]]^v[a[2]] : abs(v[i])
            elseif f === (/) && length(a) == 2
                v[i] = v[a[1]] / v[a[2]]
                m[i] = m[a[1]] / abs(v[a[2]])
            else
                r = length(a) == 1 ? f(v[a[1]]) : length(a) == 2 ? f(v[a[1]], v[a[2]]) : f((v[j] for j in a)...)
                v[i] = Float64(r)
                m[i] = abs(v[i])
            end
        end
    end
    return nothing
end

# the size of the terms of each condition at (`p`, `x`)
function _init_scales(c::_InitCheck, p, x)
    try
        _init_eval!(c, p, x)
    catch e
        e isa InterruptException && rethrow()
        return zeros(length(c.rows))
    end
    return Float64[c.m[l] + c.m[r] for (l, r) in c.rows]
end

"""The first condition not satisfied at (`p`, `x`): (row, residual, size of its terms), or `nothing`."""
function _init_residual(c::_InitCheck, p, x)
    try
        _init_eval!(c, p, x)
    catch e
        e isa InterruptException && rethrow()
        return (1, NaN, NaN)
    end
    for (q, (l, r)) in enumerate(c.rows)
        res = c.v[l] - c.v[r]
        sc = c.m[l] + c.m[r]
        (isfinite(res) && abs(res) <= _INIT_RTOL * sc) || return (q, res, sc)
    end
    return nothing
end

function _init_jacobian!(J, c::_InitCheck, p, x)
    y = collect(Float64, x)
    for j in eachindex(y)
        h = cbrt(eps(Float64)) * (x[j] == 0 ? 1.0 : abs(x[j]))
        y[j] = x[j] + h
        _init_eval!(c, p, y)
        for (q, (l, r)) in enumerate(c.rows)
            J[q, j] = c.v[l] - c.v[r]
        end
        y[j] = x[j] - h
        _init_eval!(c, p, y)
        for (q, (l, r)) in enumerate(c.rows)
            J[q, j] = (J[q, j] - (c.v[l] - c.v[r])) / 2h
        end
        y[j] = x[j]
    end
    return J
end

"""
Whether the conditions' Jacobian in the free values at (`p`, `x`) is singular (central
differences), after scaling each row and column to unit maximum: a solution that is not
isolated (dependent conditions) is refused rather than one of many returned.
"""
function _init_singular(c::_InitCheck, p, x)
    n = length(x)
    J = zeros(n, n)
    try
        _init_jacobian!(J, c, p, x)
    catch e
        e isa InterruptException && rethrow()
        return false                                    # not evaluable beside the solution: not judged
    end
    all(isfinite, J) || return true
    for q in 1:n
        s = maximum(abs, view(J, q, :))
        s > 0 || return true
        J[q, :] ./= s
    end
    for j in 1:n
        s = maximum(abs, view(J, :, j))
        s > 0 || return true
        J[:, j] ./= s
    end
    n == 1 && return false
    σ = svdvals(J)
    return σ[end] <= _INIT_SINGULAR * σ[1]
end

"""The residual of an MTK `InitializationProblem` (`f`, its parameter object `p`), behind an
abstract field: one concrete type for every model."""
struct _InitResidual
    f::Any
    p::Any
end
(r::_InitResidual)(du, u, _) = (r.f(du, u, r.p); nothing)

"""
Match each condition (`rows`) to a free variable it names (augmenting paths): an unmatched
condition is overdetermined, an unmatched free variable underdetermined.
"""
function _check_determined(where_, rows, free::Vector{Symbol})
    match = Dict{Symbol, Int}()
    function augment(r, seen)
        for v in rows[r].free
            v in seen && continue
            push!(seen, v)
            if !haskey(match, v) || augment(match[v], seen)
                match[v] = r
                return true
            end
        end
        return false
    end
    for r in eachindex(rows)
        augment(r, Set{Symbol}()) && continue
        row = rows[r]
        if isempty(row.fixed) && isempty(row.free) && !isempty(row.model)
            vs = join(("`$v`" for v in row.model), ", ")
            throw(ArgumentError("initialization of $where_: $(row.text) names no cell variable to solve for, and a cell " *
                                "equation does not determine the model variable$(length(row.model) == 1 ? "" : "s") $vs " *
                                "(it would give one value per cell); determine $vs by a model equation (one that reads " *
                                "no cell quantity), or give $(length(row.model) == 1 ? "it" : "them") a value"))
        end
        if isempty(row.fixed)
            throw(ArgumentError("initialization of $where_ is overdetermined: $(row.text) adds a condition on " *
                                (isempty(row.free) ? "no variable" : join(("`$v`" for v in row.free), ", ")) *
                                " beyond the others; remove one condition"))
        end
        vs = join(("`$v`" for v in row.fixed), ", ")
        has = length(row.fixed) == 1 ? "has" : "have"
        throw(ArgumentError("initialization of $where_ is overdetermined: $(row.text)" *
                            (row.label === nothing ? "" : " (the condition `$(row.label) ~ value`)") * " names $vs, which already $has a value " *
                            "(written in @variables, `= 0.0` included, or given in the operating point), and no free " *
                            "variable is left for it; declare $vs without a value to have initialization solve for it, or " *
                            "remove the condition"))
    end
    left = [v for v in free if !haskey(match, v)]
    isempty(left) || throw(ArgumentError(
        "initialization of $where_ is underdetermined: $(length(rows)) condition$(length(rows) == 1 ? "" : "s") for " *
        "$(length(free)) free variables, and $(join(("`$v`" for v in left), ", ")) $(length(left) == 1 ? "is" : "are") " *
        "not determined; give $(length(left) == 1 ? "it" : "them") a value (in @variables or the operating point) or add " *
        "an equation to @initialization_equations"))
    return nothing
end
