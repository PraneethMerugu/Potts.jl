# Components (ROADMAP M4.1, D-017/D-038): MTK systems instantiated per cell. A component's
# unknowns become cell variables (`clock.m` is the cell variable `clock₊m`), its parameters
# become model parameters (`clock₊τ`) unless coupled to a cell-scope expression with
# `@equations clock.τ ~ …`, and its equations become cell ODEs, advanced for every cell of
# the component's kinds by the sweep's `ode_solver` in one batched kernel (CPU or GPU).

"""
`@components cells(kinds…) name = system`: an MTK system instantiated per cell;
`@components model name = system`: one instance for the whole model (model variables and
parameters, couplings to model-scope expressions such as `sum(volume for c in cells)`).
"""
struct ComponentSpec
    name::Symbol
    system::Any
    domain::Union{CellDomain, Symbol}           # a cell domain, or `:model`
end

_mtkname(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic && info(u) === nothing ?
                                 (try
                                     ModelingToolkitBase.getname(u)
                                 catch
                                     nothing
                                 end) : nothing)

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
        Pair{Any, Any}[f(k) => (r isa Split ? r : f(r)) for (k, r) in d.rules]))
    fl(r::LinkRule) = keep(r, LinkRule(r.relationship, r.action, f(r.when), r.every))
    fo(o::ObservedEq) = keep(o, ObservedEq(o.var, f(o.expr)))
    fs = sys.sweep
    sweep = SweepSpec(fs.law, f(fs.temperature), fs.combine, fs.offset, fs.mcs_duration, fs.field_solver, fs.ode_solver)
    return (; energies = map(fe, sys.energies), drives = map(fd, sys.drives),
        constraints = map(fc, sys.constraints), updates = map(fu, sys.updates),
        equations = map(fq, sys.equations), divisions = map(fv, sys.divisions),
        link_rules = map(fl, sys.link_rules), observed = map(fo, sys.observed), sweep, sources = src)
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
    for comp in sys.components
        cs = ModelingToolkitBase.mtkcompile(comp.system)
        ics = ModelingToolkitBase.initial_conditions(cs)
        # a missing value stays `nothing`: the operating point must give it (checked there)
        value(x) = (v = get(ics, _unwrap(x), nothing); v === nothing ? nothing :
                                                        (w = _unwrap(v); SymbolicUtils.isconst(w) ? Float64(SymbolicUtils.unwrap_const(w)) : w))
        local_sub = Dict{Any, Any}(_unwrap(t) => time)
        for u in ModelingToolkitBase.unknowns(cs)
            nm = Symbol(comp.name, :₊, ModelingToolkitBase.getname(u))
            v = variable(only(Symbolics.@variables $nm(t)), comp.domain === :model ? :model : :cell; default = value(u))
            push!(vars, v)
            names[nm] = _unwrap(v)
            local_sub[_unwrap(u)] = _unwrap(v)
        end
        for p in ModelingToolkitBase.parameters(cs)
            nm = Symbol(comp.name, :₊, ModelingToolkitBase.getname(p))
            push!(coupleable, nm)
            if haskey(couplings, nm)
                names[nm] = _unwrap(couplings[nm])
            else
                q = parameter(nm, value(p))
                push!(params, q)
                names[nm] = _unwrap(q)
            end
            local_sub[_unwrap(p)] = names[nm]
        end
        obs = Dict{Any, Any}(_unwrap(o.lhs) => _unwrap(o.rhs) for o in ModelingToolkitBase.observed(cs))
        expand(x) = _fixpoint(y -> Symbolics.substitute(y, obs; fold = Val(false)), _unwrap(x))
        for o in ModelingToolkitBase.observed(cs)          # `comp.y` for an observed y
            names[Symbol(comp.name, :₊, ModelingToolkitBase.getname(o.lhs))] =
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
        relationships = sys.relationships, m.link_rules, m.observed, m.sweep, structural = sys.structural,
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
