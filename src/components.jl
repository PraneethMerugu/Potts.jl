# Components (ROADMAP M4.1, D-017/D-038): MTK systems instantiated per cell. A component's
# unknowns become cell variables (`clock.m` is the cell variable `clock₊m`), its parameters
# become model parameters (`clock₊τ`) unless coupled to a cell-scope expression with
# `@equations clock.τ ~ …`, and its equations become cell ODEs, advanced for every cell of
# the component's kinds by the sweep's `ode_solver` in one batched kernel (CPU or GPU).
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
    sweep = SweepSpec(fs.law, f(fs.temperature), fs.combine, fs.offset, fs.mcs_duration, fs.field_solver, fs.ode_solver)
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
    for comp in sys.components
        discrete = _is_discrete(comp.system)
        cs = discrete ? _compile_discrete(comp) : ModelingToolkitBase.mtkcompile(comp.system)
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
            names[Symbol(comp.name, :₊, SymbolicIndexingInterface.getname(o.lhs))] =
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
    odes = [eq.lhs ~ Symbolics.wrap(_substitute_names(eq.rhs, names)) for eq in odes]
    blocks = [DiscreteBlock(b.name, b.scope, b.kinds, b.slots, Any[_substitute_names(x, names) for x in b.next], b.every, b.offset)
              for b in blocks]
    # the model's own statements: `clock.m` (an MTK variable) → the cell variable `clock₊m`
    sub(x) = _substitute_names(x, names)
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
        sources = merge(sys.sources, m.sources))
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
function _substitute_names(x, names)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return x
    sub = Dict{Any, Any}()
    _walk_all(u) do y
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
    try
        return ext === nothing ? ModelingToolkitBase.mtkcompile(comp.system) : ext.compile_discrete(comp.system)
    catch e
        e isa Union{ArgumentError, InterruptException, StackOverflowError, OutOfMemoryError} && rethrow()
        hint = nameof(typeof(e)) === :ExtraVariablesSystemException ?
               "every discrete variable needs an update `x(k) ~ …`; " : ""
        throw(ArgumentError("component `$(comp.name)`: $(hint)ModelingToolkit cannot compile this discrete system: " *
                            first(sprint(showerror, e), 600)))
    end
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
