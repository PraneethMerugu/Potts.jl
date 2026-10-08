# A model's own cell and model ODEs through ModelingToolkit (P6.0bn, route A2 of the
# MTK-native plan). The `@equations` of each scope (cell, model) become one MTK `System`, the
# per-cell template: the scope's variables are its unknowns, the declared parameters its
# parameters, and everything else the equations read (built-ins, other scopes' variables,
# gathers, population folds, cross-cell reads) an input parameter standing for that
# expression. `mtkcompile` simplifies the template, eliminating explicit algebraic equations
# `y ~ expr` as observed. Potts then restores the inputs and lowers the simplified rates into
# its own batched `CellPhase`/`ModelPhase`, as before; an algebraic variable is not stored,
# and everywhere the model reads it, it reads its definition (MTK's observed semantics).
#
# ModelingToolkitBase alone moves `y ~ x` to `observed` and solves no implicit equation;
# full ModelingToolkit also tears. Potts accepts only explicit, acyclic definitions and
# checks that itself, so what is accepted does not depend on which of the two is loaded.

"""
    Potts.ode_system(csys::CompiledPottsSystem, scope::Symbol)

The ModelingToolkit system of the cell (`scope = :cell`) or model (`scope = :model`) ODEs of
a compiled model: the `System` that `mtkcompile` produced from that scope's `@equations`, or
`nothing` when the scope has none.

- It is complete and scheduled, as every `mtkcompile` result.
- Its unknowns are the scope's differential variables under their declared names, and each
  algebraic variable (`y ~ expr` in `@equations`) is an `observed` equation.
- Each declared parameter the equations read is a parameter under its declared name.
- Everything else the equations read (built-ins such as `volume`, other scopes' variables,
  neighbour gathers, folds over cells, reads of other cells `y[j]`) is an input: a further
  parameter standing for that quantity.

A cell system is the template of one cell: Potts advances it for every cell in one batched
kernel. A system without inputs is an ordinary MTK system, which `ODEProblem` accepts.

The equations of `@components` systems are not listed here; each component is compiled as
its own system. Any other scope, or a `PottsSystem` that has not been through
`mtkcompile`, is an `ArgumentError`.
"""
function ode_system(c::CompiledPottsSystem, scope::Symbol)
    scope in (:cell, :model) || throw(ArgumentError(
        "ode_system: the scope is `:cell` or `:model`; got `:$scope` (field equations are " *
        "stepped by Potts on the lattice and are not an ODE system)"))
    return get(c.ode_systems, scope, nothing)
end
ode_system(sys::PottsSystem, ::Symbol) = throw(ArgumentError(
    "ode_system: `$(nameof(sys))` has not been compiled; call `ode_system(mtkcompile(sys), scope)`"))

const _ODE_SCOPES = (:cell, :model)

_is_derivative(l) = iscall(l) && operation(l) isa Differential

# `comp.p ~ expr`: a coupling of a component parameter (`_bind_components`), not an
# algebraic equation: its left side is an MTK variable without Potts metadata
_is_coupling(l) = l isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(l) && info(l) === nothing &&
                  (!iscall(l) || !(operation(l) isa Function) || operation(l) === getindex)

# Operations MTK sees inside a template: plain functions (arithmetic, `exp`, comparisons,
# `ifelse`, registered user functions). Potts' own operations (`at`, `gather`,
# `population`, `cell_integral`, …), operators (`Pre`) and `getindex` stand for a quantity MTK
# cannot express: the whole call is an input.
_template_op(op) = op isa Function && op !== getindex && parentmodule(op) !== (@__MODULE__) &&
                   !(op isa Union{Differential, Pre, ModelingToolkitBase.Shift, ModelingToolkitBase.Sample, ModelingToolkitBase.Hold})

"""
The model's cell and model ODEs through `mtkcompile`: one template per scope that has
`@equations`, the algebraic variables eliminated (not stored, read as their definitions
everywhere), and the simplified rates in place of the authored ones. Returns the rewritten
model and the compiled templates by scope (empty when the model has no cell or model
equations).
"""
function _compile_odes(sys::PottsSystem)
    deqs = Dict{Symbol, Vector{Equation}}()
    aeqs = Dict{Symbol, Vector{Equation}}()
    for eq in getfield(sys, :equations)
        l = _unwrap(eq.lhs)
        if _is_derivative(l)
            i = info(arguments(l)[1])
            i !== nothing && i.role in _ODE_SCOPES && push!(get!(deqs, i.role, Equation[]), eq)
            continue
        end
        _is_coupling(l) && continue
        _located(sys, eq) do
            i = info(l)
            i === nothing && throw(ArgumentError(
                "`$eq` is an implicit algebraic equation; an algebraic equation defines a declared cell or " *
                "model variable explicitly, `y ~ expr` (Potts accepts explicit, acyclic definitions only)"))
            i.role in _ODE_SCOPES || throw(ArgumentError(
                "`$eq`: an algebraic equation defines a cell or model variable; `$(i.name)` is " *
                (i.role in (:site, :field, :edge) ? "a $(i.role) variable" :
                 i.role === :param ? "a parameter" : "not a declared variable ($(i.role))")))
            push!(get!(aeqs, i.role, Equation[]), eq)
        end
    end
    odes = Dict{Symbol, Any}()
    isempty(deqs) && isempty(aeqs) && return sys, odes, IdDict{Any, Any}()
    alg = _check_algebraic(sys, deqs, aeqs)
    rates = Dict{Symbol, Any}()                       # differential variable → simplified rate
    defs = Dict{Any, Any}()                           # algebraic variable → its definition
    for scope in _ODE_SCOPES
        d = get(deqs, scope, Equation[])
        a = get(aeqs, scope, Equation[])
        isempty(d) && isempty(a) && continue
        odes[scope] = _ode_template(sys, scope, d, a, rates, defs)
    end
    # definitions may read other scopes' algebraic variables (acyclic: checked above)
    expand(x) = isempty(defs) ? _unwrap(x) :
                _fixpoint(y -> _unwrap(Symbolics.substitute(y, defs; fold = Val(false))), _unwrap(x))
    for (x, r) in defs
        defs[x] = expand(r)
    end
    src = IdDict{Any, LineNumberNode}()
    srcs = getfield(sys, :sources)
    origin = IdDict{Any, Any}()                       # rewritten statement → the authored one
    keep(old, new) = (haskey(srcs, old) && (src[new] = srcs[old]); origin[new] = old; new)
    m = isempty(alg) ? nothing : _map_statements(expand, sys; seen = origin)
    equations = Equation[]
    for (j, eq) in enumerate(getfield(sys, :equations))
        l = _unwrap(eq.lhs)
        x = _is_derivative(l) ? info(arguments(l)[1]) : nothing
        if x !== nothing && haskey(rates, x.name)
            push!(equations, keep(eq, eq.lhs ~ Symbolics.wrap(expand(rates[x.name]))))
        elseif !_is_derivative(l) && !_is_coupling(l)
            continue                                   # an algebraic equation: eliminated
        else
            push!(equations, m === nothing ? eq : keep(eq, getfield(m, :equations)[j]))
        end
    end
    m === nothing && return _replace(sys; equations, sources = merge(srcs, src)), odes, origin
    names = Set{Symbol}(info(x).name for x in keys(alg))
    variables = Any[x for x in getfield(sys, :variables) if !(info(x).name in names)]
    observed = [getfield(m, :observed);
                [ObservedEq(_tag(_sym(info(x).name), Info(:observed, info(x).name, nothing, (; scope = info(x).role))),
                     Symbolics.wrap(defs[x])) for x in _algebraic_order(alg)]]
    return _replace(sys; variables, equations, observed, energies = getfield(m, :energies), drives = getfield(m, :drives),
               constraints = getfield(m, :constraints), updates = getfield(m, :updates), divisions = getfield(m, :divisions),
               link_rules = getfield(m, :link_rules), discrete = getfield(m, :discrete), sweep = getfield(m, :sweep),
               boundaries = getfield(m, :boundaries), sources = merge(srcs, getfield(m, :sources), src)), odes, origin
end

# The algebraic variables of a model with its ODEs simplified (`_compile_odes`), as the
# `@observed` entries that carry their declared scope.
_algebraic_observed(sys::PottsSystem) = [o for o in getfield(sys, :observed) if haskey(info(o.var).options, :scope)]

# The statement being compiled reads its algebraic variables as their definitions, so an
# error about a definition's quantities would not name the variable. While `_via_algebraic`
# runs, `_located` adds a note naming the algebraic variables the failing statement itself
# read (as authored: `origin` maps each rewritten statement to the authored one). Statements
# rewritten again later (component binding) have no entry and get no note.
const _ALGEBRAIC_READS = Base.ScopedValues.ScopedValue{Any}(nothing)

function _via_algebraic(f::F, sys::PottsSystem, origin) where {F}
    alg = _algebraic_observed(sys)
    isempty(alg) && return f()
    defs = Dict{Symbol, Any}(info(o.var).name => o.expr for o in alg)
    return Base.ScopedValues.with(f, _ALGEBRAIC_READS => (; origin, defs))
end

# the note for an error in statement `x` (empty when `x` read no algebraic variable, or the
# message already names every one it read)
function _algebraic_note(x, msg)
    ctx = _ALGEBRAIC_READS[]
    ctx === nothing && return ""
    old = get(ctx.origin, x, nothing)
    old === nothing && return ""
    read = Symbol[]
    _walk_statement(old) do y
        i = info(y)
        i !== nothing && haskey(ctx.defs, i.name) && !(i.name in read) && push!(read, i.name)
    end
    filter!(n -> !occursin("`$n`", msg), read)
    isempty(read) && return ""
    return "\n  (this statement reads the algebraic variable$(length(read) == 1 ? "" : "s") " *
           join(("`$n ~ $(ctx.defs[n])`" for n in read), ", ") * ", which stand$(length(read) == 1 ? "s" : "") " *
           "for $(length(read) == 1 ? "its definition" : "their definitions"))"
end

# every symbolic value of a statement (its expressions, equations, rules and conditions)
_walk_statement(f, x::Union{Num, SymbolicUtils.BasicSymbolic}) = _walk_all(f, x)
_walk_statement(f, x::Equation) = (_walk_all(f, x.lhs); _walk_all(f, x.rhs))
_walk_statement(f, x::Pair) = (_walk_statement(f, x.first); _walk_statement(f, x.second))
_walk_statement(f, x::Union{AbstractArray, Tuple, NamedTuple}) = foreach(y -> _walk_statement(f, y), x)
_walk_statement(f, ::Union{Number, Symbol, AbstractString, Nothing, Function, Module, DataType}) = nothing
function _walk_statement(f, x)
    isstructtype(typeof(x)) || return nothing
    foreach(n -> isdefined(x, n) && _walk_statement(f, getfield(x, n)), fieldnames(typeof(x)))
    return nothing
end

"""
Each algebraic definition lowered once where `sol[:y]` evaluates it (its cell, or the
model), so that one that cannot be evaluated there fails at `mtkcompile`, naming `y`, and
not when it is first observed.
"""
function _check_algebraic_lowering(sys::PottsSystem, rn)
    for o in _algebraic_observed(sys)
        i = info(o.var)
        cell = i.options.scope === :cell
        try
            lower(o.expr, cell ? _cell_env(Float64, :c, rn; mcs = :t) : _model_env(Float64, rn; mcs = :t))
            # an integral is evaluated by summing its operand over the cell's sites
            _walk(o.expr) do y
                iscall(y) && operation(y) === cell_integral && lower(arguments(y)[1], _site_env(Float64, :i, rn; mcs = :t))
            end
        catch e
            e isa Union{ArgumentError, ErrorException} || rethrow()
            throw(ArgumentError("the algebraic equation `$(i.name) ~ $(o.expr)` cannot be evaluated at " *
                                "$(cell ? "its cell" : "the model"): $(sprint(showerror, e))"))
        end
    end
    return nothing
end

# `x` with folds over cells, sites and neighbours and cell integrals replaced by 0: what is
# left is read at the variable's own cell (or the model)
function _outside_folds(x)
    x = first(_strip_populations(x))
    sub = Dict{Any, Any}()
    _walk(y -> (iscall(y) && (operation(y) === cell_integral || operation(y) === gather) && (sub[y] = 0)), x)
    return isempty(sub) ? x : _unwrap(Symbolics.substitute(x, sub; fold = Val(false)))
end

# algebraic variables in the order of their equations
_algebraic_order(alg) = sort!(collect(keys(alg)); by = x -> alg[x].order)

"""
Check the algebraic equations (explicit, acyclic definitions of cell or model variables that
nothing else writes, read bare); returns each defined variable → (equation, order).
"""
function _check_algebraic(sys::PottsSystem, deqs, aeqs)
    alg = Dict{Any, NamedTuple{(:eq, :order), Tuple{Equation, Int}}}()
    isempty(aeqs) && return alg
    differential = Set{Symbol}(info(arguments(_unwrap(eq.lhs))[1]).name for eqs in values(deqs) for eq in eqs)
    byname = Dict{Symbol, Any}()
    n = 0
    for scope in _ODE_SCOPES, eq in get(aeqs, scope, Equation[])
        x = _unwrap(eq.lhs)
        name = info(x).name
        _located(sys, eq) do
            name in differential && throw(ArgumentError(
                "`$name` has both `D($name) ~ …` and the algebraic equation `$eq`; an algebraic variable has no derivative"))
            haskey(byname, name) && throw(ArgumentError(
                "`$name` has two algebraic equations, `$(alg[byname[name]].eq)` and `$eq`; one definition per variable"))
            what = "an algebraic equation of a $scope variable"
            _check_names(eq.rhs, scope === :cell ? (_CELL_BUILTINS..., :time) : (:mcs, :time), what; between_copies = true)
            # the variable's own scope: a model value folds cell quantities, a cell value reads
            # site quantities through `integral(c)` or at a site (`c[…]`)
            for v in _bare_vars(_outside_folds(eq.rhs))
                r = info(v).role
                scope === :model && r in (:cell, :site, :field) && throw(ArgumentError(
                    "the algebraic equation `$eq` of the model variable `$name` reads the $r variable " *
                    "`$(info(v).name)` bare; fold it, e.g. `sum($(info(v).name) for c in cells)`"))
                scope === :cell && r in (:site, :field) && throw(ArgumentError(
                    "the algebraic equation `$eq` of the cell variable `$name` reads the $r variable `$(info(v).name)` " *
                    "bare, which has one value per site; read it over the cell (`integral($(info(v).name))`) or at a " *
                    "site (`$(info(v).name)[…]`)"))
            end
            d = getfield(info(x), :default)
            (d === nothing || (d isa Real && iszero(d))) || throw(ArgumentError(
                "`$name` is defined by the algebraic equation `$eq` and has the declared initial value `$d`; an " *
                "algebraic variable's value follows from its definition. Declare `$name($scope)` without a value; to " *
                "start it at a value, give `$name => value` in the operating point (the initial condition " *
                "`$name ~ value`, D-170) or write the condition in @initialization_equations"))
            _has_op(eq.rhs, random_uniform) && throw(ArgumentError(
                "the algebraic equation `$eq` draws `rand()`; an algebraic variable is a function of the current state " *
                "(MTK observed): keep the draw in an update or an ODE"))
            (_has_op(eq.rhs, history_lag) || _has_operator(eq.rhs, ModelingToolkitBase.Pre)) && throw(ArgumentError(
                "the algebraic equation `$eq` reads a previous value (`Pre`); an algebraic variable is a function of " *
                "the current state (MTK observed)"))
        end
        byname[name] = x
        alg[x] = (; eq, order = (n += 1))
    end
    # self-references and cycles, by depth-first search over the definitions
    reads(x) = unique!(Symbol[i.name for i in (info(y) for y in _leaves(alg[x].eq.rhs))
                              if i !== nothing && i.role in _ODE_SCOPES && haskey(byname, i.name)])
    state = Dict{Symbol, Int}()                        # 1: on the path, 2: done
    function visit(name, path)
        get(state, name, 0) == 2 && return
        if get(state, name, 0) == 1
            loop = path[findfirst(==(name), path):end]
            eq = alg[byname[name]].eq
            _located(sys, eq) do
                throw(ArgumentError(length(loop) == 1 ?
                    "the algebraic equation `$eq` reads `$name` itself (an algebraic loop); Potts accepts explicit, acyclic definitions only" :
                    "the algebraic equations of $(join(("`$v`" for v in loop), ", ")) read each other in a cycle " *
                    "(an algebraic loop); Potts accepts explicit, acyclic definitions only"))
            end
        end
        state[name] = 1
        foreach(r -> visit(r, [path; r]), reads(byname[name]))
        state[name] = 2
        return
    end
    foreach(x -> visit(info(x).name, [info(x).name]), _algebraic_order(alg))
    # nothing writes an algebraic variable
    message(name, by) = "`$name` is defined by an algebraic equation (`$(alg[byname[name]].eq)`); it is not a stored " *
                        "variable, so $by cannot write it"
    target(l) = (l = _unwrap(l); iscall(l) && (operation(l) === at || operation(l) === at2) ? _unwrap(arguments(l)[1]) : l)
    for u in getfield(sys, :updates)
        i = info(target(u.eq.lhs))
        i !== nothing && haskey(byname, i.name) && _located(() -> throw(ArgumentError(message(i.name, "@$(u.phase)"))), sys, u)
    end
    for d in getfield(sys, :divisions), (k, _) in d.rules
        i = info(target(k))
        i !== nothing && haskey(byname, i.name) && _located(() -> throw(ArgumentError(message(i.name, "a division rule"))), sys, d)
    end
    # every read is bare: an indexed read `y[j]` or a lag `Pre(y)` has no stored value to read
    function bare(x)
        _walk_all(x) do y
            iscall(y) || return
            op = operation(y)
            (op === at || op === at2 || op === history_lag || op isa ModelingToolkitBase.Pre) || return
            i = info(_unwrap(arguments(y)[1]))
            (i !== nothing && i.role in _ODE_SCOPES && haskey(byname, i.name)) || return
            throw(ArgumentError("`$(i.name)` is defined by an algebraic equation (`$(alg[byname[i.name]].eq)`) and is read " *
                                "as `$y`; an algebraic variable is read bare (its definition at the current cell or model), " *
                                "not at another index or as a previous value"))
        end
        return x
    end
    _map_statements(bare, sys)
    return alg
end

"""
`mtkcompile` of the template of one scope: its differential equations `d` and algebraic
equations `a`. Records the simplified rate of each differential variable in `rates` (by name)
and the definition of each algebraic variable in `defs`, with the inputs restored.
"""
function _ode_template(sys::PottsSystem, scope::Symbol, d, a, rates, defs)
    targets = Any[[arguments(_unwrap(eq.lhs))[1] for eq in d]; [_unwrap(eq.lhs) for eq in a]]
    istarget = Set{Any}(targets)
    # input names: a built-in's or another scope's variable's own name, else `input_k`; never
    # the name of a target, a parameter or another declared variable
    reserved = Set{Symbol}(info(x).name for x in Iterators.flatten((targets, getfield(sys, :parameters), getfield(sys, :variables))))
    own = Set{Symbol}(info(x).name for x in Iterators.flatten((targets, getfield(sys, :parameters))))
    used = Set{Symbol}()
    params = Any[]
    inputs = Dict{Any, Any}()                          # authored expression → its parameter
    back = Dict{Any, Any}()                            # parameter → the authored expression
    function name(y)
        i = info(y)
        if i !== nothing && !(i.name in own) && !(i.name in used)    # a built-in or another scope's variable
            push!(used, i.name)
            return i.name
        end
        base = i === nothing ? :input : i.name
        n = base
        k = 1
        while n in used || n in reserved
            n = Symbol(base, :_, k += 1)
        end
        push!(used, n)
        return n
    end
    function input(y; declared = false)
        get!(inputs, y) do
            p = _unwrap(ModelingToolkitBase.toparam(declared ? y :
                 Symbolics.variable(name(y); T = SymbolicUtils.symtype(y))))
            push!(params, p)
            back[p] = y
            p
        end
    end
    # the inputs of a right side: its outermost subexpressions MTK cannot express
    function scan(y)
        y = _unwrap(y)
        (y isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(y)) || return
        (y in istarget || isequal(y, _unwrap(t))) && return
        i = info(y)
        if i !== nothing
            input(y; declared = i.role === :param)
        elseif iscall(y) && _template_op(operation(y))
            foreach(scan, arguments(y))
        else
            input(y)
        end
        return
    end
    foreach(eq -> scan(eq.rhs), Iterators.flatten((d, a)))
    # (`substitute` replaces the outermost match, so an input's own subexpressions stay in it)
    eqs = Equation[eq.lhs ~ (isempty(inputs) ? eq.rhs : Symbolics.substitute(eq.rhs, inputs; fold = Val(false)))
                   for eq in Iterators.flatten((d, a))]
    # component checks only: Potts checks units itself (`_check_units`), and the inputs carry none
    template = ModelingToolkitBase.System(eqs, t, targets, params; name = Symbol(nameof(sys), :₊, scope), checks = ModelingToolkitBase.CheckComponents)
    compiled = ModelingToolkitBase.mtkcompile(template)
    obs = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in ModelingToolkitBase.observed(compiled))
    restore(x) = _unwrap(Symbolics.substitute(
        _fixpoint(y -> _unwrap(Symbolics.substitute(y, obs; fold = Val(false))), _unwrap(x)), back; fold = Val(false)))
    differential = Set{Symbol}(info(x).name for x in targets[1:length(d)])
    for eq in ModelingToolkitBase.equations(compiled)
        l = _unwrap(eq.lhs)
        x = _is_derivative(l) ? arguments(l)[1] : nothing
        (x !== nothing && SymbolicIndexingInterface.getname(x) in differential) || throw(ArgumentError(
            "the $scope equations of `$(nameof(sys))`: mtkcompile left `$eq`, which is not the ODE of a " *
            "differential variable; Potts accepts explicit, acyclic algebraic definitions only"))
        rates[SymbolicIndexingInterface.getname(x)] = restore(eq.rhs)
    end
    length(ModelingToolkitBase.equations(compiled)) == length(d) || throw(ArgumentError(
        "the $scope equations of `$(nameof(sys))`: mtkcompile kept $(length(ModelingToolkitBase.equations(compiled))) " *
        "of $(length(d)) ODEs"))
    for x in targets[(length(d) + 1):end]
        haskey(obs, x) || throw(ArgumentError(
            "the $scope equations of `$(nameof(sys))`: mtkcompile did not eliminate the algebraic variable `$(info(x).name)`"))
        defs[x] = restore(obs[x])
    end
    return compiled
end
