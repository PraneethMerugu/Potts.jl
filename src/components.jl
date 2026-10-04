# Components (ROADMAP M4.1, D-017/D-038): MTK systems instantiated per cell. A component's
# unknowns become cell variables (`clock.m` is the cell variable `clock₊m`), its parameters
# become model parameters (`clock₊τ`) unless coupled to a cell-scope expression with
# `@equations clock.τ ~ …`, and its equations become cell ODEs, advanced for every cell of
# the component's kinds by the problem's `ode_solver` (or its `solvers` entry) in one batched
# kernel (CPU or GPU).
#
# A discrete-time component (clocked, `Shift`; D-065 Q9, P6.0k) is `mtkcompile`d the same
# way; each of its discrete variables `x` becomes the cell variable `name₊x` holding the value
# of the latest tick (a `Bool` node as exact 0/1 in the model's scalar type), and its rules
# become a `DiscreteBlock`: one tick per period of its clock, after the ODEs (codegen.jl).

"""
`@components cells(kinds…) name = system`: an MTK system instantiated per cell;
`@components model name = system`: one instance for the whole model (model variables and
parameters, couplings to model-scope expressions such as `sum(volume for c in cells)`).
The system is continuous (`D(x) ~ f`, cell or model ODEs) or discrete-time (clocked, `Shift`:
Boolean and discrete networks, ticking after the ODEs of each period of its clock).
Values are plain numbers: a system with `initialization_eqs`, `discrete_events`,
`continuous_events`, `jumps`, `brownians`, `tstops` or `assertions` (also in a subsystem), or
whose quantities Potts reads (unknowns, parameters, discrete nodes, names the model reads
as `comp.x`) are bound to expressions (`y(t) = 2k`, `k2 = 2k`, `initial_conditions =
[y => 2k]`, a discrete `X(t) = !Y`), is rejected by name. Bindings of observed variables and
of parameters nothing reads are ignored, as by MTK; `guesses` are ignored too (MTK
initialisation is not run).
"""
struct ComponentSpec
    name::Symbol
    system::Any
    domain::Union{CellDomain, Symbol}           # a cell domain, or `:model`
end

_mtkname(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic && info(u) === nothing ?
                                 (try
                                     _slot_name(u)
                                 catch
                                     nothing
                                 end) : nothing)

"""
Name of an MTK variable as a Potts quantity: its name, or `z_i` for element `i` of an array
variable `z` (`z_i_j` for a matrix), the convention of vector quantities.
"""
function _slot_name(u)
    u = _unwrap(u)
    if iscall(u) && operation(u) === getindex
        idx = arguments(u)[2:end]
        all(i -> SymbolicUtils.unwrap_const(_unwrap(i)) isa Integer, idx) &&
            return Symbol(SymbolicIndexingInterface.getname(arguments(u)[1]), "_",
                join((SymbolicUtils.unwrap_const(_unwrap(i)) for i in idx), "_"))
    end
    return SymbolicIndexingInterface.getname(u)
end

# Replace every expression of a model with `f(expr)`, keeping source locations.
function _map_statements(f, sys::PottsSystem)
    src = IdDict{Any, LineNumberNode}()
    keep(old, new) = (haskey(sys.sources, old) && (src[new] = sys.sources[old]); new)
    fe(e::EnergyTerm) = keep(e, EnergyTerm(e.domain, f(e.expr)))
    fd(d::Drive) = keep(d, Drive(f(d.expr)))
    fc(c::Constraint) = keep(c, c.kind === :expr ? Constraint(c.kind, c.kinds, f(c.expr)) : c)
    fu(u::Update) = keep(u, Update(u.phase, f(u.eq.lhs) ~ f(u.eq.rhs), u.every))
    fq(eq::Equation) = keep(eq, f(eq.lhs) ~ f(eq.rhs))
    fv(d::DivideRule) = keep(d, DivideRule(d.domain, f(d.when), d.along,
        Pair{Any, Any}[f(k) => (r isa Split ? r : f(r)) for (k, r) in d.rules], d.every))
    fl(r::LinkRule) = keep(r, LinkRule(r.relationship, r.action, f(r.when), r.every))
    fo(o::ObservedEq) = keep(o, ObservedEq(o.var, f(o.expr)))
    fb(b::DiscreteBlock) = DiscreteBlock(b.name, b.scope, b.kinds, b.slots, Any[f(x) for x in b.next], b.every, b.offset)
    fs = sys.sweep
    sweep = SweepSpec(fs.law, f(fs.temperature), fs.combine, fs.offset, fs.mcs_duration)
    return (; energies = map(fe, sys.energies), drives = map(fd, sys.drives),
        constraints = map(fc, sys.constraints), updates = map(fu, sys.updates),
        equations = map(fq, sys.equations), divisions = map(fv, sys.divisions),
        link_rules = map(fl, sys.link_rules), observed = map(fo, sys.observed),
        discrete = map(fb, sys.discrete), sweep, sources = src)
end

"""The model with its components expanded into cell variables, parameters and cell ODEs."""
function _bind_components(sys::PottsSystem)
    isempty(sys.components) && return sys
    params = copy(sys.parameters)
    vars = copy(sys.variables)
    odes = Equation[]
    # namespaced name (`clock₊m`) → the Potts quantity or expression it stands for
    names = Dict{Symbol, Any}()
    # couplings `clock.τ ~ expr` (component parameter ← cell-scope expression)
    couplings = Dict{Symbol, Any}()
    rest = Equation[]
    for eq in sys.equations
        lhs = _unwrap(eq.lhs)
        n = iscall(lhs) && operation(lhs) isa Differential ? nothing : _mtkname(lhs)
        n === nothing ? push!(rest, eq) : (couplings[n] = eq.rhs)
    end
    time = _unwrap(B.time)
    coupleable = Set{Symbol}()                  # component parameters (the only coupling targets)
    blocks = copy(sys.discrete)
    slotnames_all = Set{Symbol}()               # every discrete slot (`Pre` of one is the slot)
    unread = Dict{Symbol, String}()             # bound names no component equation reads → their error
    for comp in sys.components
        _reject_ignored_features(comp)
        discrete = _is_discrete(comp.system)
        cs = discrete ? _compile_discrete(comp) : ModelingToolkitBase.mtkcompile(comp.system)
        _reject_coupled_bindings(comp, cs, couplings)
        _reject_bindings(comp, cs, discrete, unread)
        ics = ModelingToolkitBase.initial_conditions(cs)
        # a missing value stays `nothing`: the operating point must give it (checked there)
        value(x) = (v = get(ics, _unwrap(x), nothing); v === nothing ? nothing :
                                                        (w = _unwrap(v); SymbolicUtils.isconst(w) ? Float64(SymbolicUtils.unwrap_const(w)) : w))
        local_sub = Dict{Any, Any}(_unwrap(t) => time)
        scope = comp.domain === :model ? :model : :cell
        plan = discrete ? _discrete_plan(comp, cs, sys.sweep.mcs_duration) : nothing
        if discrete
            # one slot per discrete variable (and per older lag): the value of its latest tick
            for (x, standin) in zip(plan.slots, plan.standins)
                nm = Symbol(comp.name, :₊, _slot_name(x))
                haskey(names, nm) && throw(ArgumentError("component `$(comp.name)`: two discrete variables are both stored as `$nm`"))
                v = variable(only(Symbolics.@variables $nm(t)), scope; default = _element_default(ics, x))
                push!(vars, v)
                names[nm] = standin(_unwrap(v))
                push!(slotnames_all, nm)
            end
        else
            for u in ModelingToolkitBase.unknowns(cs)
                nm = Symbol(comp.name, :₊, SymbolicIndexingInterface.getname(u))
                v = variable(only(Symbolics.@variables $nm(t)), scope; default = value(u))
                push!(vars, v)
                names[nm] = _unwrap(v)
                local_sub[_unwrap(u)] = _unwrap(v)
            end
        end
        for p in ModelingToolkitBase.parameters(cs)
            nm = Symbol(comp.name, :₊, SymbolicIndexingInterface.getname(p))
            push!(coupleable, nm)
            if haskey(couplings, nm)
                names[nm] = _unwrap(couplings[nm])
            else
                q = parameter(nm, value(p))
                push!(params, q)
                names[nm] = _unwrap(q)
            end
            # a `Bool` parameter of a discrete component reads its stored 0/1 (or a Real
            # coupling) as a Bool; a Real one reads a Bool coupling as 0/1
            discrete && (names[nm] = _as_symtype(names[nm], SymbolicUtils.symtype(_unwrap(p))))
            local_sub[_unwrap(p)] = names[nm]
        end
        if discrete
            # lags read the pre-tick slot of their source; rules become the tick's new values
            slotnames = [Symbol(comp.name, :₊, _slot_name(x)) for x in plan.slots]
            for (ℓ, j) in plan.lags
                local_sub[ℓ] = names[slotnames[j]]
            end
            next = Any[_unwrap(Symbolics.substitute(r, local_sub; fold = Val(false))) for r in plan.rules]
            slots = Any[_standin_var(names[n]) for n in slotnames]
            kinds = comp.domain isa CellDomain ? _all_kinds(sys, comp.domain.kinds) : Int[]
            push!(blocks, DiscreteBlock(comp.name, scope, kinds, slots, next, plan.every, plan.offset))
            continue
        end
        obs = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in ModelingToolkitBase.observed(cs))
        expand(x) = _fixpoint(y -> Symbolics.substitute(y, obs; fold = Val(false)), _unwrap(x))
        for o in ModelingToolkitBase.observed(cs)          # `comp.y` for an observed y
            oname = Symbol(comp.name, :₊, SymbolicIndexingInterface.getname(o.lhs))
            _check_internal_suffix("component observed quantity", oname)    # D-130
            names[oname] =
                _unwrap(Symbolics.substitute(expand(o.rhs), local_sub; fold = Val(false)))
        end
        for eq in ModelingToolkitBase.equations(cs)
            lhs = _unwrap(eq.lhs)
            (iscall(lhs) && operation(lhs) isa Differential) ||
                throw(ArgumentError("component `$(comp.name)`: only explicit ODEs `D(x) ~ f` are supported; got $eq"))
            x = local_sub[arguments(lhs)[1]]
            rhs = _unwrap(Symbolics.substitute(expand(eq.rhs), local_sub; fold = Val(false)))
            comp.domain isa CellDomain && !isempty(comp.domain.kinds) && (rhs = _unwrap(ifelse(_kind_in(comp.domain.kinds), Symbolics.wrap(rhs), 0.0)))
            push!(odes, D(Symbolics.wrap(x)) ~ Symbolics.wrap(rhs))
        end
    end
    for k in keys(couplings)
        k in coupleable || throw(ArgumentError("@equations $k ~ …: `$k` is not a parameter of a component " *
                                               "(component unknowns evolve by their own equations)"))
    end
    # couplings may read other components' state (`dec.k ~ clock.m`)
    # a bound name no component equation reads is ignored, unless the model reads it (`comp.k2`)
    function subst(x)
        isempty(unread) || _walk_all(x) do y
            n = _mtkname(y)
            n !== nothing && haskey(unread, n) && throw(ArgumentError(unread[n]))
        end
        return _substitute_names(x, names, slotnames_all)
    end
    odes = [eq.lhs ~ Symbolics.wrap(subst(eq.rhs)) for eq in odes]
    blocks = [DiscreteBlock(b.name, b.scope, b.kinds, b.slots, Any[subst(x) for x in b.next],
                  b.every, b.offset)
              for b in blocks]
    # the model's own statements: `clock.m` (an MTK variable) → the cell variable `clock₊m`
    sub(x) = subst(x)
    m = _map_statements(sub, PottsSystem(; name = sys.name, kinds = sys.kinds, frozen_kinds = sys.frozen_kinds,
        lattice = sys.lattice, parameters = params, variables = vars, relations = sys.relations,
        energies = sys.energies, drives = sys.drives, constraints = sys.constraints, updates = sys.updates,
        equations = rest, divisions = sys.divisions, relationships = sys.relationships,
        link_rules = sys.link_rules, observed = sys.observed, sweep = sys.sweep, structural = sys.structural,
        sources = sys.sources))
    return PottsSystem(; name = sys.name, kinds = sys.kinds, frozen_kinds = sys.frozen_kinds,
        lattice = sys.lattice, parameters = params, variables = vars, relations = sys.relations,
        m.energies, m.drives, m.constraints, m.updates, equations = [m.equations; odes], m.divisions,
        relationships = sys.relationships, m.link_rules, m.observed, discrete = blocks, m.sweep, structural = sys.structural,
        sources = merge(sys.sources, m.sources),
        kind_classes = sys.kind_classes)
end

# What an MTK System can carry that Potts would otherwise drop silently (P6.0k2 F7). MTK
# `guesses` only seed MTK's initialisation, which Potts does not run (G8): they are ignored.
function _reject_ignored_features(comp)
    sys = comp.system
    what(x) = first(join(string.(x), ", "), 200)
    for (field, items, why) in (
            ("initialization_eqs", ModelingToolkitBase.initialization_equations(sys),
                "Potts does not run MTK initialisation; give the values as variable defaults or in the operating point"),
            ("discrete_events", ModelingToolkitBase.discrete_events(sys),
                "write the event as a Potts update (`@after_mcs`) or a discrete component"),
            ("continuous_events", ModelingToolkitBase.continuous_events(sys),
                "Potts does not root-find inside a cell ODE step; write the event as a Potts update (`@after_mcs`)"),
            ("jumps", ModelingToolkitBase.jumps(sys),
                "write the jump as a Potts update with `rand()`"),
            ("brownians", ModelingToolkitBase.brownians(sys),
                "Potts integrates cell ODEs deterministically; write the noise as a Potts update with `rand()`"),
            ("tstops", _all_tstops(sys),
                "Potts advances cell ODEs once per MCS and never stops inside a step; write the stop as a Potts update (`@after_mcs`)"),
            ("assertions", collect(keys(ModelingToolkitBase.assertions(sys))),
                "Potts does not check MTK assertions; write the check as a Potts update or a callback"))
        isempty(items) || throw(ArgumentError("component `$(comp.name)`: MTK $field are not supported " *
                                              "(they would be ignored): $(what(items)); $why"))
    end
    return nothing
end

# the tstops of a system and its subsystems (`get_tstops` is the system's own)
_all_tstops(sys) = Any[ModelingToolkitBase.get_tstops(sys); (x for s in ModelingToolkitBase.get_systems(sys) for x in _all_tstops(s))...]

# An MTK binding (a variable's or parameter's value given as an expression, `y(t) = 2k`,
# `k2 = 2k`) is evaluated by MTK against the parameter's own value; a coupled parameter has no
# value of its own (it is a per-cell or model expression), so such a binding would be wrong or
# dropped (P6.0k2 F7). Other bindings are not supported either (`_reject_bindings`).
function _reject_coupled_bindings(comp, cs, couplings)
    namespaced(y) = Symbol(comp.name, :₊, SymbolicIndexingInterface.getname(y))
    leafname(y) = (SymbolicUtils.issym(y) || (iscall(y) && SymbolicUtils.issym(operation(y)))) ? namespaced(y) : nothing
    for (lhs, rhs) in ModelingToolkitBase.bindings(cs)
        touched = Symbol[]
        n = leafname(_unwrap(lhs))
        n !== nothing && haskey(couplings, n) && push!(touched, n)
        _walk_all(rhs) do y
            m = leafname(y)
            m !== nothing && haskey(couplings, m) && !(m in touched) && push!(touched, m)
        end
        isempty(touched) && continue
        throw(ArgumentError("component `$(comp.name)`: the MTK binding `$lhs = $rhs` touches the coupled " *
                            "parameter$(length(touched) > 1 ? "s" : "") $(join(("`$c`" for c in touched), ", ")) " *
                            "(`@equations $(first(touched)) ~ …`); a coupled parameter has no value of its own for MTK " *
                            "to bind with. Write the expression inline in the component's equations instead, or give " *
                            "a plain value"))
    end
    return nothing
end

# Any other binding Potts reads (D-133): Potts takes a component's values as plain numbers
# (it does not run MTK initialisation), so a value given as an expression (`y(t) = 2k`,
# `k2 = 2k`, `initial_conditions = [y => 2k]`, a discrete `X(t) = !Y`) is rejected here, naming
# the component, instead of failing later as a missing value or an unknown symbol. Only
# bindings of what Potts reads count: unknowns, parameters, symbols the equations or observed
# expressions read, and (discrete) the nodes, which are observed. A binding of a continuous
# observed variable (its equation gives its value) or of an unused parameter stays ignored,
# unless the model reads it (`comp.k2`): `unread` collects namespaced name → error for that.
function _reject_bindings(comp, cs, discrete::Bool, unread = Dict{Symbol, String}())
    used = Set{Any}()
    function use(y)
        y = _unwrap(y)
        push!(used, y)
        iscall(y) && operation(y) === getindex && push!(used, _unwrap(arguments(y)[1]))   # `z[1]` reads `z`
        return nothing
    end
    foreach(use, ModelingToolkitBase.unknowns(cs))
    foreach(use, ModelingToolkitBase.parameters(cs))
    for eq in ModelingToolkitBase.equations(cs)
        _walk_all(use, eq.lhs)
        _walk_all(use, eq.rhs)
    end
    observed = Set{Any}()
    for o in ModelingToolkitBase.observed(cs)
        discrete ? _walk_all(use, o.lhs) : push!(observed, _unwrap(o.lhs))
        _walk_all(use, o.rhs)
    end
    reads(x) = (u = _unwrap(x); u in used && !(u in observed))
    for (x, v) in ModelingToolkitBase.bindings(cs)
        msg = "component `$(comp.name)`: `$x` is bound to the expression `$v` (an MTK binding); " *
              "Potts takes a component's values as plain numbers: give `$x` a value, or write " *
              "the expression inline in the component's equations"
        reads(x) && throw(ArgumentError(msg))
        u = _unwrap(x)
        u in observed || (unread[Symbol(comp.name, :₊, _slot_name(u))] = msg)
    end
    for (x, v) in ModelingToolkitBase.initial_conditions(cs)
        w = _unwrap(v)
        w isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(w) && reads(x) &&
            throw(ArgumentError("component `$(comp.name)`: the initial value `$x => $v` is an expression; " *
                                "Potts takes a component's values as plain numbers (it does not run MTK initialisation)"))
    end
    return nothing
end

_kind_in(kinds) = foldl(|, [B.kind == k for k in kinds])

function _fixpoint(f, x; n = 32)
    for _ in 1:n
        y = f(x)
        isequal(y, x) && return y
        x = y
    end
    throw(ArgumentError("component observed equations are cyclic"))
end

# Substitute leaves that are MTK variables of components (no Potts metadata) by name.
# `Pre(x)` of such a leaf is substituted whole (`substitute` does not enter operators):
# `Pre(names[x])`, or, for a discrete slot (`slots`), `names[x]` itself — a slot changes only
# at its tick, and a tick reads every slot's pre-tick value (Jacobi, D-077), so `Pre(x)` is
# `x` wherever it is read, and lowers to the same code.
function _substitute_names(x, names, slots = ())
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return x
    sub = Dict{Any, Any}()
    _walk_all(u) do y
        if iscall(y) && operation(y) isa ModelingToolkitBase.Pre
            a = arguments(y)[1]
            n = _mtkname(a)
            if n !== nothing && haskey(names, n)
                sub[y] = n in slots ? names[n] : _unwrap(ModelingToolkitBase.Pre(Symbolics.wrap(names[n])))
            else                                        # `Pre` of an expression: inside it
                b = _substitute_names(a, names, slots)
                b === a || (sub[y] = _unwrap(ModelingToolkitBase.Pre(Symbolics.wrap(b))))
            end
            return
        end
        n = _mtkname(y)
        n !== nothing && haskey(names, n) && (sub[y] = names[n])
    end
    isempty(sub) && return x
    return _unwrap(Symbolics.substitute(u, sub; fold = Val(false)))
end

# Like `_walk`, but also inside scoped variables' calls (`clock₊m(t)` is a call of `t`).
function _walk_all(f, x)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return
    f(x)
    iscall(x) && foreach(a -> _walk_all(f, a), arguments(x))
    return
end

# ---------------------------------------------------------------------------------------
# Discrete-time components (P6.0k, D-065 Q9)

"""Whether an MTK system is discrete-time: it uses `Shift`, `Sample` or `Hold`, or a clocked variable."""
function _is_discrete(sys)
    found = Ref(false)
    for eq in ModelingToolkitBase.equations(sys), side in (eq.lhs, eq.rhs)
        _walk_all(side) do y
            iscall(y) && operation(y) isa Union{ModelingToolkitBase.Shift, ModelingToolkitBase.Sample, ModelingToolkitBase.Hold} &&
                (found[] = true)
            SymbolicUtils.getmetadata(y, ModelingToolkitBase.VariableTimeDomain, nothing) === nothing || (found[] = true)
        end
    end
    return found[]
end

_has_operator(x, ::Type{O}) where {O} = (found = Ref(false); _walk_all(y -> (iscall(y) && operation(y) isa O && (found[] = true)), x); found[])

"""
`mtkcompile` of a discrete component, rejecting what the lowering cannot honour first. MTK
failures become `ArgumentError`s naming the component. With full ModelingToolkit loaded (which
replaces MTKBase's compiler and rejects clocked systems), the `PottsModelingToolkitExt`
extension compiles through MTK's discrete-pass hook (gap G1).
"""
function _compile_discrete(comp)
    eqs = ModelingToolkitBase.equations(comp.system)
    for eq in eqs, side in (eq.lhs, eq.rhs)            # Sample/Hold first: they come with D(x)
        _has_operator(side, Union{ModelingToolkitBase.Sample, ModelingToolkitBase.Hold}) && throw(ArgumentError(
            "component `$(comp.name)`: `Sample`/`Hold` are not supported (ModelingToolkitBase has no clock " *
            "partitioning); couple a continuous and a discrete component with `@equations` instead (the discrete " *
            "one samples at its tick, the continuous one holds the latest tick); got $eq"))
    end
    for eq in eqs, side in (eq.lhs, eq.rhs)
        _has_operator(side, Differential) && throw(ArgumentError(
            "component `$(comp.name)`: a discrete (clocked, `Shift`) component cannot also have `D(x)` equations " *
            "(hybrid systems are not supported); make two components, one continuous and one discrete, " *
            "coupled with `@equations`; got $eq"))
    end
    ext = Base.get_extension(@__MODULE__, :PottsModelingToolkitExt)
    ext === nothing || ext.check_compatible()           # G1: the MTK hook, checked once per session
    compile = ext === nothing ? ModelingToolkitBase.mtkcompile : ext.compile_discrete
    return _mtk_compile_call(compile, comp)
end

# ModelingToolkit's compile of a discrete component. Only errors ModelingToolkit raises become
# `ArgumentError`s naming the component: an error raised in Potts' own code (the extension's
# pass runs inside MTK's compile) is a Potts bug and propagates unchanged (P6.0k2 F4).
function _mtk_compile_call(compile::F, comp) where {F}
    try
        return compile(comp.system)
    catch e
        e isa Union{ArgumentError, InterruptException, StackOverflowError, OutOfMemoryError} && rethrow()
        _raised_in_potts(catch_backtrace()) && rethrow()
        hint = nameof(typeof(e)) === :ExtraVariablesSystemException ?
               "every discrete variable needs an update `x(k) ~ …`; " : ""
        throw(ArgumentError("component `$(comp.name)`: $(hint)ModelingToolkit cannot compile this discrete system: " *
                            first(sprint(showerror, e), 600)))
    end
end

# Whether the innermost frame of `bt` outside Julia's Base and standard library is Potts code
# (its `src/` or `ext/`): where the error was raised, as opposed to inside ModelingToolkit.
# This is who raised it, not whose bug it is: a Potts misuse that SymbolicUtils or MTK
# rejects is relabelled. Julia records stdlib frames under the build machine's path.
function _raised_in_potts(bt)
    own = (joinpath(pkgdir(@__MODULE__), "src"), joinpath(pkgdir(@__MODULE__), "ext"))
    for fr in stacktrace(bt)
        m = parentmodule(fr)
        (m === Base || m === Core) && continue
        file = String(fr.file)
        (isabspath(file) && !startswith(file, Sys.STDLIB) &&
         !occursin(joinpath("share", "julia", "stdlib", ""), file)) || continue    # Base (inlined), stdlib
        return any(d -> startswith(file, joinpath(d, "")), own)
    end
    return false
end

"""
The tick of a compiled discrete component `cs`: its slots (every discrete variable, then
each lag that is itself the source of an older lag), the new value of each slot as an MTK
expression of lag unknowns and parameters, which slot each lag unknown reads (`lags`), and
its clock as a cadence in MCS (`every`, `offset`).
"""
function _discrete_plan(comp, cs, mcs_duration)
    name = comp.name
    unk = Set{Any}(_unwrap(u) for u in ModelingToolkitBase.unknowns(cs))
    src = Dict{Any, Any}()                               # lag unknown → what it will hold
    for eq in ModelingToolkitBase.equations(cs)
        l = _unwrap(eq.lhs)
        (iscall(l) && operation(l) isa ModelingToolkitBase.Shift && operation(l).steps == 1 && arguments(l)[1] in unk) ||
            throw(ArgumentError("component `$name`: `$eq` is not an explicit discrete update " *
                                "(`x(k) ~ f(x(k - 1), …)`): an implicit rule or an algebraic loop of same-step reads"))
        src[arguments(l)[1]] = _unwrap(eq.rhs)
    end
    for u in unk
        haskey(src, u) || throw(ArgumentError("component `$name`: unknown `$u` has no update"))
    end
    obs = [o for o in ModelingToolkitBase.observed(cs) if !SymbolicUtils.is_array_shape(SymbolicUtils.shape(_unwrap(o.lhs)))]
    obsd = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in obs)
    expand(x) = _fixpoint(y -> _unwrap(Symbolics.substitute(y, obsd; fold = Val(false))), _unwrap(x))
    slots = Any[]
    rules = Any[]
    # slots in name order: the generated code does not depend on MTK's observed order (a tick
    # computes every new value before writing any, so the order has no other effect)
    for o in sort(obs; by = o -> string(_slot_name(o.lhs)))
        x = _unwrap(o.lhs)
        r = expand(o.rhs)
        SymbolicUtils.symtype(x) === Bool && SymbolicUtils.symtype(r) !== Bool && throw(ArgumentError(
            "component `$name`: the Bool node `$x` has the non-Bool rule `$r`; write a Bool expression " *
            "(`&`, `|`, `!`, `xor`, comparisons, `ifelse` of Bools) or declare the node Real"))
        push!(slots, x)
        push!(rules, r)
    end
    slot_of = Dict{Any, Int}(x => j for (j, x) in enumerate(slots))
    for (ℓ, v) in sort!(collect(src); by = p -> string(_slot_name(p.first)))   # a lag of a lag keeps its own slot
        if v in unk && !haskey(slot_of, v)
            push!(slots, v)
            slot_of[v] = length(slots)
            push!(rules, v)                             # the older lag takes its source's pre-tick value
        end
    end
    lags = Pair{Any, Int}[]
    for (ℓ, v) in src
        haskey(slot_of, v) || throw(ArgumentError("component `$name`: the lag `$ℓ` holds `$v`, which is not a discrete variable"))
        push!(lags, ℓ => slot_of[v])
    end
    standins = [SymbolicUtils.symtype(x) === Bool ? (v -> _unwrap(_nonzero(Symbolics.wrap(v)))) : identity for x in slots]
    every, offset = _clock_cadence(comp, cs, slots, mcs_duration)
    return (; slots, rules, lags, standins, every, offset)
end

# the default of a slot: its own, or its entry in the default of its array variable (G11)
function _element_default(ics, x)
    const_of(y) = (v = get(ics, _unwrap(y), nothing); v === nothing ? nothing :
                                                      (w = _unwrap(v); SymbolicUtils.isconst(w) ? SymbolicUtils.unwrap_const(w) : nothing))
    v = const_of(x)
    v isa Real && return Float64(v)
    u = _unwrap(x)
    (iscall(u) && operation(u) === getindex) || return nothing
    a = const_of(arguments(u)[1])
    idx = [SymbolicUtils.unwrap_const(_unwrap(i)) for i in arguments(u)[2:end]]
    return a isa AbstractArray && all(i -> i isa Integer, idx) ? Float64(a[idx...]) : nothing
end

# the Potts variable behind a slot's stand-in (`_nonzero(grn₊A)` → `grn₊A`)
_standin_var(x) = (u = _unwrap(x); iscall(u) && operation(u) === _nonzero ? _unwrap(arguments(u)[1]) : u)

# `x` with the symtype of the MTK quantity it replaces (G7: a Real leaf cannot stand in for a Bool one)
function _as_symtype(x, ::Type{S}) where {S}
    s = x isa SymbolicUtils.BasicSymbolic ? SymbolicUtils.symtype(x) : typeof(x)
    S === Bool && s !== Bool && return _unwrap(_nonzero(Symbolics.wrap(x)))
    S !== Bool && s === Bool && return _unwrap(ifelse(Symbolics.wrap(x), 1.0, 0.0))
    return x
end

"""
The tick cadence of a discrete component: `ShiftIndex(t, 0)` (an `IntegerSequence`) ticks
after every MCS; `Clock(dt; phase)` at MTK clock times `t = phase + k·dt` (`t = 0` is the initial
state), i.e. after MCS `m` when `(m + 1 - offset) % every == 0`, `every = dt / mcs_duration`
and `offset = phase / mcs_duration` whole numbers of MCS.
"""
function _clock_cadence(comp, cs, slots, mcs_duration)
    clocks = Any[]
    for x in Iterators.flatten((ModelingToolkitBase.unknowns(cs), slots))
        d = SymbolicUtils.getmetadata(_unwrap(x), ModelingToolkitBase.VariableTimeDomain, nothing)
        d === nothing || any(c -> isequal(c, d), clocks) || push!(clocks, d)
    end
    length(clocks) <= 1 || throw(ArgumentError("component `$(comp.name)`: several clocks ($(join(clocks, ", "))); " *
                                               "a discrete component has one clock (put each clock in its own component)"))
    isempty(clocks) && return 1, 0
    c = only(clocks)
    c isa ModelingToolkitBase.IntegerSequence && return 1, 0
    c isa SciMLBase.Clocks.PeriodicClock || throw(ArgumentError(
        "component `$(comp.name)`: clock $c is not supported; use `ShiftIndex(t, 0)` (one tick per MCS) or " *
        "`ShiftIndex(Clock(n * mcs_duration))`"))
    whole(x) = (r = round(x); isapprox(x, r; rtol = 1.0e-9, atol = 1.0e-12) ? Int(r) : nothing)
    n = whole(Float64(c.dt) / Float64(mcs_duration))
    (n === nothing || n < 1) && throw(ArgumentError(
        "component `$(comp.name)`: the clock period $(c.dt) is not a whole number of MCS (mcs_duration = $mcs_duration)"))
    o = whole(Float64(c.phase) / Float64(mcs_duration))
    (o === nothing || !(0 <= o < n)) && throw(ArgumentError(
        "component `$(comp.name)`: the clock phase $(c.phase) must be a whole number of MCS in [0, period)"))
    return n, o
end
