# `PottsSystem`: the authored model, an MTK `AbstractSystem` wrapping a complete inner `System`
# (W-lite LA, v3 §7.1). `mtkcompile` turns it into a `CompiledPottsSystem` (compile.jl).

"""
    DiscreteBlock

A discrete-time (clocked, `Shift`) MTK component lowered into Potts terms:
one tick replaces every slot (`slots[j]`, a cell or model variable holding the node's latest
value) by `next[j]`, an expression of the pre-tick state (Jacobi reads: every `next` sees the
values before the tick). A tick follows MCS `m` when `(m + 1 - offset) % every == 0` (MTK
clock time `t = offset + k·every` MCS; `t = 0` is the initial state). `scope` is `:cell`
(for the live cells of `kinds`; empty: every kind) or `:model`.
"""
struct DiscreteBlock
    name::Symbol
    scope::Symbol
    kinds::Vector{Int}
    slots::Vector{Any}
    next::Vector{Any}
    every::Int
    offset::Int
end

"""
    Potts.FieldBinding(path, name, source)

A coupling of a model input to the field side (S-2): the input `name` of the component at
`path` (a vector of component names, empty for the model itself) is driven by `source`.
Bindings are stored per component as `(path, name)`; [`Potts.compose`](@ref) prefixes the
path by the component name, and the input resolves after the wrap as
`getproperty(foldl(getproperty, path; init = sys), name)` ([`Potts.resolve`](@ref)), a term of
`unknowns(sys)`. They are stored and printed; the field compiler consumes them.
"""
struct FieldBinding
    path::Vector{Symbol}
    name::Symbol
    source::Any
end

"""
    Potts.PottsPart(; kinds, lattice, sweep, …)

The Potts payload of a [`PottsSystem`](@ref): everything that is not an MTK system. Kinds
(the first is the medium), the lattice, the declared parameters and scoped variables (as
written: the inner `System` holds them too), Hamiltonian terms, drives, constraints,
synchronous/on-copy updates, the `@equations` and `@initialization_equations` as written,
lifecycle rules, site conversion passes, relationships and link rules, `@observed`
equations, `@components`, `@boundary` entries, `@bcs` (stored and printed; C6 classifies
them), the `@schedule`, the sweep and the field bindings ([`Potts.FieldBinding`](@ref)).
"""
Base.@kwdef struct PottsPart
    kinds::Vector{Symbol}
    frozen_kinds::Vector{Int} = Int[]          # obstacle kinds: their sites never change owner
    kind_classes::Vector{KindClass} = KindClass[]   # named sets of kinds (D-135); not hashed: lowered into the statements
    lattice::LatticeSpec
    parameters::Vector{Any} = Any[]
    variables::Vector{Any} = Any[]
    relations::Dict{Symbol, Any} = Dict{Symbol, Any}()
    energies::Vector{EnergyTerm} = EnergyTerm[]
    drives::Vector{Drive} = Drive[]
    constraints::Vector{Constraint} = Constraint[]
    updates::Vector{Update} = Update[]
    equations::Vector{Equation} = Equation[]
    # `@initialization_equations` as written (D-170); compiled into per-scope initialization
    # systems (initialization.jl)
    initialization_eqs::Vector{Equation} = Equation[]
    divisions::Vector{DivideRule} = DivideRule[]
    converts::Vector{ConvertSpec} = ConvertSpec[]   # `@convert` passes (R8, D-233), in declaration order
    relationships::Vector{RelationshipSpec} = RelationshipSpec[]
    link_rules::Vector{LinkRule} = LinkRule[]
    observed::Vector{Equation} = Equation[]    # `@observed name ~ expr`: the inner System's observed equations
    components::Vector{Any} = Any[]            # `ComponentSpec`s: MTK systems instantiated per cell
    discrete::Vector{DiscreteBlock} = DiscreteBlock[]   # bound discrete components (`_bind_components`)
    sweep::SweepSpec
    boundaries::Vector{BoundaryEntry} = BoundaryEntry[]   # `@boundary` faces and site masks (D-145)
    bcs::Vector{Equation} = Equation[]         # `@bcs`: raw MTK boundary conditions, stored and printed
    schedule::Vector{Any} = Any[]              # `@schedule` as listed (names, a `ScheduleRepeat`); empty: the default order
    structural::NamedTuple = (;)
    sources::IdDict{Any, LineNumberNode} = IdDict{Any, LineNumberNode}()   # term → where it was written
    # Potts' own build record (`_BuiltFeatures`, draws.jl); never MTK metadata, never in code
    # or fingerprint. MTK's metadata (`PottsSweepSpec`) is the inner System's.
    metadata::Base.ImmutableDict{DataType, Any} = Base.ImmutableDict{DataType, Any}()
    bindings::Vector{FieldBinding} = FieldBinding[]
end

struct _Wrap end

"""
    PottsSystem

A cellular Potts model: an MTK `AbstractSystem` that holds a complete ModelingToolkitBase
`System` for its quantities, equations and observed quantities (`Potts.inner(sys)`), a
`PDESystem` for its fields or `nothing` (`Potts.fields(sys)`), and the Potts payload
([`Potts.PottsPart`](@ref): kinds, lattice, energies, drives, constraints, sweep, lifecycle,
…). Built by `@potts_model`, by the keyword constructor
`PottsSystem(; name, kinds, lattice, sweep, parameters, variables, energies, …)` (the
[`Potts.PottsPart`](@ref) fields; `checks = false` skips the construction checks), or by
[`Potts.wrap`](@ref).

MTK's accessors read the inner System: `equations(sys)` (the `@equations` as written, plus
each component's equations, namespaced `dc₊y`), `unknowns(sys)` (the declared variables of
every scope plus each component's unknowns; never the lattice ownership, kinds or built-in
cell properties), `parameters(sys)`, `observed(sys)` (one `name ~ expr` per `@observed`
quantity), `initial_conditions(sys)`, `bindings(sys)`, `independent_variables(sys)` (`[t]`)
and `nameof(sys)`. SymbolicIndexingInterface queries are answered by the inner System.

`sys.x` is MTK's own `getproperty` on the complete inner System: the declared symbol itself
(`sys.λ` is `λ`), and `sys.dc.y` is the component quantity `dc₊y`. A name that is not a
quantity or component of the system is an `ArgumentError`. Either form, and the namespaced
`name₊x` of the model's own name, works as a key wherever a model quantity is named
(operating point, `remake`, `getu`/`setu`/`getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`)
for a model built by `@potts_model` or the keyword constructor. A model from
[`Potts.compose`](@ref) compiles, solves and extends with each component as a model-scope
component (`@components model c = system`); a `Potts.wrap` of a hand-built System does when
its top-level content is its payload's and the rest is subsystems (otherwise an
`ArgumentError` naming the content).

Other MTKBase functions are not answered by a `PottsSystem`: ask `Potts.inner(sys)`
(`iscomplete`, `get_iv`, `full_equations`, `guesses`, the metadata, …; `iscomplete(sys)` itself
is `false`). `complete`, `extend`, MTK's `compose` and `toggle_namespacing` are errors; Potts
models merge with [`Potts.extend`](@ref) (`@extend`) and compose with
[`Potts.compose`](@ref); MTK's `extend` is an `ArgumentError` saying so. Every SciMLBase problem constructor (`ODEProblem`, `JumpProblem`, …)
is an `ArgumentError` naming `PottsProblem`; `mtkcompile(sys)` compiles the CPM
([`CompiledPottsSystem`](@ref)). `Potts.lattice(sys)` is the model's lattice and
`Potts.parameters(sys)`/`Potts.variables(sys)` its own declarations.
"""
struct PottsSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol                                          # equals nameof(inner)
    inner::ModelingToolkitBase.System                     # complete: flattened; parent = the unflattened hierarchy
    fields::Union{Nothing, ModelingToolkitBase.PDESystem} # every field equation and bc (filled by the field compiler)
    part::PottsPart
    PottsSystem(::_Wrap, name::Symbol, inner::ModelingToolkitBase.System, fields, part::PottsPart) = new(name, inner, fields, part)
end

"""`getfield(getfield(sys, :part), f)`: a Potts payload field of `sys`."""
_p(sys::PottsSystem, f::Symbol) = getfield(getfield(sys, :part), f)

"""
    Potts.inner(sys::PottsSystem)

The complete (flattened) ModelingToolkitBase `System` of a model: its parameters, variables,
`@equations`, `@observed` and components. Generic MTK code takes it where it needs a `System`
(`mtkcompile(Potts.inner(sys); inputs = …)` compiles the cell/model ODE alone).
"""
inner(sys::PottsSystem) = getfield(sys, :inner)

"""
    Potts.part(sys::PottsSystem) -> PottsPart

The Potts payload of a model (kinds, lattice, energies, sweep, …). A component for
`Potts.compose` is built with [`Potts.component`](@ref), which takes the model's kinds and
lattice and none of its statements.
"""
part(sys::PottsSystem) = getfield(sys, :part)

"""
    Potts.component(name, sys::System, model::PottsSystem) -> PottsSystem

The MTK `System` `sys` as a component of `model`, for [`Potts.compose`](@ref): it is
`Potts.wrap(name, sys, nothing, part)` with a payload that has the kinds, the lattice and the
sweep of `model` and no statements (no energies, drives, constraints, …), which is what a
composed component may carry. `sys` is named `name` (`@named`); a Catalyst reaction network
`rn` is `Potts.component(name, Catalyst.ode_model(complete(rn)), model)`.

```julia
@named decay = System([D(y) ~ -k * y], t)
sys = Potts.compose(model, Potts.component(:decay, decay, model))
```
"""
component(name::Symbol, sys::ModelingToolkitBase.System, model::PottsSystem) =
    wrap(name, sys, nothing, _component_part(model))

"""
    Potts.component(name, pdesys::PDESystem, model::PottsSystem) -> PottsSystem

The `PDESystem` `pdesys` (named `name`) as fields of `model`, for [`Potts.compose`](@ref).
`Potts.compose(model, Potts.component(:drug, pdesys, model))` adds each dependent variable
`c` as the field `drug₊c`, each parameter `k` as the parameter `drug₊k` (with its value),
each equation as an `@equations` entry and each condition as a `@bcs` entry, so the fields
run as if declared in the model: with the default field solver, or by name in
`FieldGroups(:drug₊c => …)`. A condition at the start time, `c(0, x, y) ~ v`, is the field's
initial value. Its time interval is not read (the problem's `tspan` is).

The spatial domain is the lattice's, in the model's length unit: axis `d` spans
`[0, dims[d] · spacing[d]]` (`[0, dims[d]]` without `@lattice spacing`), the domain
`Potts.fields(model)` gives; another interval is an `ArgumentError` naming both. An input
variable (`[input = true]`) is filled by the CPM by its `lattice_input_name` (or else its
own name): `"kind"` is the kind of each site (0 for the medium), and the name of a field
or site variable of the model reads that variable.
"""
component(name::Symbol, pdesys::ModelingToolkitBase.PDESystem, model::PottsSystem) =
    wrap(name, ModelingToolkitBase.System(Equation[], _unwrap(t); name), pdesys, _component_part(model))

"""
    Potts.couple(model::PottsSystem, pdesys::PDESystem; inputs = []) -> PottsSystem

`model` with the fields of the plain `PDESystem` `pdesys`, under their own names: each
dependent variable `c` becomes the field `c` of the model, each parameter `k` the parameter
`k` (with its value), and each equation and condition joins the model's fields, as in
[`Potts.component`](@ref) but without a namespace. The fields then run in the model's MCS loop
with its `field_solver`, are read as `sol[:c]`, take `FieldGroups(:c => …)` pairs and the
operating point `:c => values`, and a model that extends the result reads them by name
(`@extend c = base = …`, then `@drive … c[target]`).

`inputs` binds each input of `pdesys` (a dependent variable declared `[input = true]`) to a
CPM expression at a site: `inputs = [endo => Potts.kind == Potts.lookup(model, :A), vol =>
Potts.at(Potts.B.volume, Potts.B.owner)]`. A kind is compared by its number
(`Potts.lookup(model, :A)` gives it): `Potts.kind == :A` is Julia's constant `false`, and a
binding to a constant truth value is an `ArgumentError` saying so. The field compiler fills each one per site every MCS, as it fills the CPM
reads of a field equation, so `pdesys` itself holds only plain input fields (0/1 or numbers),
never a Potts quantity. A key is the input variable (`endo` or `endo(t, x, y)`) or its name. A
`Bool` input (`endo(..)::Bool`) takes a truth value. An input left unbound is filled by its
`lattice_input_name` (or its name), as in [`Potts.component`](@ref): `kind`, `owner`,
`position`, `site`, `mcs`, `time`, or a field or site variable of the model.

The spatial domain of `pdesys` is the lattice's, in the model's length unit (axis `d` spans
`[0, dims[d] · spacing[d]]`). Its time interval is not read (the problem's `tspan` is). A name
`model` already has is an `ArgumentError`; compose it as a component to namespace it.
`pdesys` stays a plain MTK system: [`Potts.field_inputs`](@ref) gives the current values of
its inputs, so `discretize(pdesys, disc; inputs = Potts.field_inputs(integ))` solves the fields
with any SciML solver at the CPM state of an integrator. Inside `@potts_model`, write
`@fields c = pdesys (endo => kind == A, …)`: the fields join the model at that line, and the
names before `=` (`c`, or a list `c, u`) are bound to them for the statements after it
(`@drive Chemotaxis(c; …)`). Without names (`@fields pdesys (…)`) the fields join the model
and are reached by name (`sol[:c]`) only.
"""
function couple(model::PottsSystem, pdesys::ModelingToolkitBase.PDESystem; inputs = ())
    what = "Potts.couple"
    base = _lower_inner(model, what)
    part = _with_pde(base, getfield(base, :part), pdesys, nothing, what; inputs = collect(Any, inputs))
    return _wrap_payload(nameof(model), nothing, part)
end

# the payload of a component of `model`: its kinds, lattice and sweep, and nothing else
_component_part(model::PottsSystem) =
    PottsPart(; kinds = copy(_p(model, :kinds)), lattice = _p(model, :lattice), sweep = _p(model, :sweep))

"""
    Potts.fields(sys::PottsSystem)
    Potts.fields(c::CompiledPottsSystem)

The `PDESystem` of a model's fields, or `nothing` for a model without fields. A model built
by `@potts_model` (or `PottsSystem(; …)`) has its PDESystem built from its field variables,
`@equations` and `@boundary` entries; a compiled model returns the one `mtkcompile` built.
Either carries the model's defaults as `initial_conditions` (each field's initial value and
each parameter's value), so LatticePDE's `discretize` takes it as a plain PDE system. Its CPM
couplings are `input = true` dependent variables, each named by the word the model uses
(`lattice_input_name`): `kind` for the kind of each site, `domain` for an irregular domain,
the CPM term as written (`volume`) for the others; give their values by that name,
`discretize(…; inputs = [:kind => K, :volume => V])` (`K` the kind number of each site, 0 for
the medium). Its conditions are the model's `@boundary` entries (`Flux(q)` and `Robin(α, β, g)`
faces as LatticePDE's face equations) and its `@bcs` conditions, as `discretize` takes them.
A hand-wrapped PDESystem (`Potts.wrap`) is returned as given.
"""
function fields(sys::PottsSystem)
    f = _stored_fields(sys)
    eqs = _field_equations(sys)
    # a model whose only fields are aux fields `K ~ rhs` has a PDESystem of aux equations (F3-00)
    none = isempty(eqs) && isempty(_field_aux(sys))
    f === nothing && none && return nothing
    f === nothing && (f = first(_field_system(sys)))
    none && return f                                # a hand-wrapped PDESystem, as given
    return _with_defaults(f, eqs)
end

# the PDESystem `f` of a model's fields with the model's defaults added to its
# `initial_conditions` (a value already there is kept): the initial value of each field
# (`@variables c(field) = v`) and the value of each parameter (`@parameters k = v`, an
# expression of parameters for a computed one). Its parameters are the model's own symbols,
# whose defaults the payload holds (F1, V13)
function _with_defaults(f::ModelingToolkitBase.PDESystem, eqs)
    ic = Dict{Any, Any}(getfield(f, :initial_conditions))
    put!(k, v) = (v === nothing || any(x -> isequal(x, k), keys(ic)) || (ic[k] = v); nothing)
    byname = Dict{Symbol, Any}(info(x).name => info(x).default for (x, _) in eqs)
    for dv in getfield(f, :dvs)
        u = _unwrap(dv)
        n = iscall(u) ? nameof(operation(u)) : nothing
        n isa Symbol && haskey(byname, n) && put!(u, byname[n])
    end
    ps0 = getfield(f, :ps)
    ps = Any[(ps0 isa SciMLBase.NullParameters ? () : ps0)...]
    # a computed default (`k2 = 2k`) reads parameters the equations may not: they join the
    # system's parameters with their own defaults, so `discretize` can fold it (F1)
    k = 1
    while k <= length(ps)
        q = ps[k]
        i = info(q)
        if i !== nothing
            put!(_unwrap(q), i.default)
            if _is_symbolic(i.default)
                for v in Symbolics.get_variables(_unwrap(i.default))
                    j = info(v)
                    j !== nothing && j.role in (:param, :kindtable) && !any(x -> isequal(_unwrap(x), v), ps) &&
                        push!(ps, v)
                end
            end
        end
        k += 1
    end
    return ModelingToolkitBase.PDESystem(getfield(f, :eqs), getfield(f, :bcs), getfield(f, :domain), getfield(f, :ivs),
        getfield(f, :dvs), ps; name = nameof(f), initial_conditions = ic)
end
# the PDESystem slot of a wrap (a hand-wrapped or compiled one), without building it
_stored_fields(sys::PottsSystem) = getfield(sys, :fields)

"""
    Potts.wrap(name, sys::System, fields, part::PottsPart) -> PottsSystem

The `PottsSystem` holding `sys`, `fields` (a `PDESystem` or `nothing`) and the payload
`part`. Compose first, then wrap: an uncompleted `sys` is completed here (`complete`
flattens it and keeps the hierarchy as its parent). A complete system that still has
subsystems (`compose(complete(a), …)`) is an `ArgumentError`, and so is a name of `sys` or
`fields` other than `name`. The inner System carries the `Potts.PottsSweepSpec` metadata.
"""
function wrap(name::Symbol, sys::ModelingToolkitBase.System, fields::Union{Nothing, ModelingToolkitBase.PDESystem},
        part::PottsPart)
    nameof(sys) === name || throw(ArgumentError("wrap: the System is named `$(nameof(sys))`, the model `$name`; they must agree"))
    fields === nothing || nameof(fields) === name ||
        throw(ArgumentError("wrap: the PDESystem is named `$(nameof(fields))`, the model `$name`; they must agree"))
    ModelingToolkitBase.iscomplete(sys) || (sys = complete(sys; allow_parameter_eqs = true))
    isempty(ModelingToolkitBase.get_systems(sys)) || throw(ArgumentError(
        "wrap: `$name` is complete but not flattened (it still has subsystems: a completed system was composed); " *
        "compose the uncompleted systems, then wrap"))
    w = PottsSystem(_Wrap(), name, sys, fields, part)
    return PottsSystem(_Wrap(), name, SymbolicUtils.setmetadata(sys, PottsSweepSpec, _sweep_spec(w)), fields, part)
end

"""
    PottsSystem(; name, kinds, lattice, sweep, parameters, variables, energies, …, checks = true)

The model with payload `Potts.PottsPart(; kinds, lattice, sweep, …)`, its inner System built
from the declared parameters, variables, `@equations`, `@initialization_equations`,
`@observed` and `@components`. `checks = false` skips the construction checks (reserved and
clashing names).
"""
function PottsSystem(; name::Symbol, checks::Bool = true, kw...)
    part = _robin_slots(PottsPart(; kw...))
    pre = _staged(name, part)
    checks && _check_primed_names(_check_name_categories(_check_reserved_names(pre)))
    return _wrap_payload(name, nothing, part)
end

# A Robin coefficient α or β that is an expression of parameters (`Robin(g1 + g2, 1, g)`, or
# `(g1 + g2) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ g` in `@bcs`) is one value at every
# site; the field compiler binds a coefficient that is a number, a parameter or a number times
# one, so the expression becomes a computed parameter of its face, `c_x_low_α = g1 + g2`, read
# only and derived again after every write (F4-12a)
function _robin_slots(part::PottsPart)
    taken = Set{Symbol}(info(x).name for x in [part.parameters; part.variables] if info(x) !== nothing)
    extra = Any[]
    function slot(c, base)
        (_isnumber(c) || _robin_simple(_unwrap(c))) && return c
        # (a coefficient that reads the coordinates or the time varies by site: LatticePDE
        # lowers it into a value field, F4-12b)
        _params_only(c) || return c
        n = Symbol(base)
        k = 1
        while n in taken
            k += 1
            n = Symbol(base, "_", k)
        end
        push!(taken, n)
        q = parameter(n, c)
        push!(extra, q)
        return q
    end
    boundaries = map(part.boundaries) do b
        b.axis == 0 && return b
        f = info(b.field).name
        sides = ntuple(2) do k
            s = b.sides[k]
            s isa Robin || return s
            base = string(f, "_", _AXIS_NAMES[b.axis], "_", k == 1 ? "low" : "high", "_")
            return Robin(slot(s.α, base * "α"), slot(s.β, base * "β"), s.g)
        end
        return BoundaryEntry(b.field, b.axis, sides, b.mask, b.value)
    end
    bcs = map(part.bcs) do eq
        other, cores, coefs = _face_terms(eq)
        changed = false
        for (i, (core, c)) in enumerate(zip(cores, coefs))
            _params_only(c) || continue
            isder = operation(core) isa Differential
            read = isder ? _unwrap(arguments(core)[1]) : core
            a = findfirst(y -> _unwrap_number(y) isa Real, arguments(read)[2:end])
            a === nothing && continue
            low = iszero(_unwrap_number(arguments(read)[a + 1]))
            base = string(_field_at_name(read), "_", _AXIS_NAMES[a], "_", low ? "low" : "high", "_", isder ? "β" : "α")
            # the slot holds `@boundary`'s β, the coefficient of the outward ∂c/∂n: on a low face
            # `∂c/∂n = −∂c/∂x`, so the written coefficient of `∂c/∂x` is −β
            flip = isder && low
            cc = flip ? -c : c
            q = slot(cc, base)
            q === cc && continue
            coefs[i] = flip ? -q : q
            changed = true
        end
        changed || return eq
        return sum(Symbolics.wrap, other; init = Symbolics.wrap(0)) +
               sum(Symbolics.wrap(c) * Symbolics.wrap(core) for (core, c) in zip(cores, coefs)) ~ eq.rhs
    end
    isempty(extra) && return part
    return PottsPart(; (f => getfield(part, f) for f in fieldnames(PottsPart))..., parameters = Any[part.parameters; extra],
        boundaries, bcs = Equation[bcs...])
end
# the terms of a `@bcs` condition's left side: the coefficient of each face read (`c(t, 0, y)`,
# `Differential(x)(c(t, 0, y))`), summed over its terms (`g1 * c + g2 * c` is `(g1 + g2) * c`),
# and the other terms
function _face_terms(eq)
    l = _unwrap(eq.lhs)
    terms = iscall(l) && operation(l) === (+) ? collect(Any, arguments(l)) : Any[l]
    other, cores, coefs = Any[], Any[], Any[]
    for tm in terms
        fac = iscall(tm) && operation(tm) === (*) ? arguments(tm) : Any[tm]
        k = findfirst(_robin_core, fac)
        k === nothing && (push!(other, tm); continue)
        core = _unwrap(fac[k])
        c = prod(Symbolics.wrap.(fac[setdiff(eachindex(fac), k)]); init = Symbolics.wrap(1))
        h = findfirst(o -> isequal(o, core), cores)
        h === nothing ? (push!(cores, core); push!(coefs, c)) : (coefs[h] += c)
    end
    return other, cores, coefs
end
# whether `c` is an expression of parameters alone (at least one): a computed parameter holds it
_params_only(c) = (ls = _param_leaves(c); !isempty(ls) && all(y -> (j = info(y); j !== nothing && j.role === :param), ls))
# A Robin coefficient of a `@bcs` condition reads the parameters, the coordinates and the time
# (F4-12b: one that varies by site or in time is a value field); one that reads a field is
# refused in the model's words (the condition would be another equation)
function _check_robin_coefs(eq)
    _, cores, coefs = _face_terms(eq)
    for c in coefs
        for y in _param_leaves(c)
            j = info(y)
            j !== nothing && (j.role === :param || (j.role === :builtin && j.name in (:time, :mcs))) && continue
            j === nothing && _coordinate(y) && continue
            throw(ArgumentError(string("@bcs: the Robin coefficient `", _builtin_text(string(c)), "` reads `",
                j === nothing ? string(y) : string(j.name), "`; a Robin coefficient α or β is an expression of numbers, ",
                "parameters, the coordinates `x`, `y`, `z`, `time` and `mcs`")))
        end
    end
    return nothing
end
# a coefficient the field compiler binds as it is: a parameter, or a number times one
_robin_simple(u) = (j = info(u); j !== nothing && j.role === :param) ||
                   (iscall(u) && operation(u) === (*) && count(y -> (j = info(y); j !== nothing && j.role === :param), arguments(u)) == 1 &&
                    all(y -> (j = info(y); j !== nothing && j.role === :param) || _isnumber(y) ||
                                 (SymbolicUtils.isconst(_unwrap(y)) && SymbolicUtils.unwrap_const(_unwrap(y)) isa Real), arguments(u)))
# the face read of a `@bcs` term, `c(t, 0, y)` or `Differential(x)(c(t, 0, y))`
_robin_core(f) = (u = _unwrap(f); iscall(u) && (_is_field_at(operation(u)) ||
                                                 (operation(u) isa Differential && (a = _unwrap(arguments(u)[1]); iscall(a) && _is_field_at(operation(a))))))
# the model quantities and other symbols an expression reads (not inside a built-in's call)
function _param_leaves(x)
    out = Any[]
    function walk2(y)
        y isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(y) || return nothing
        info(y) !== nothing && return push!(out, y)
        iscall(y) ? foreach(walk2, arguments(y)) : push!(out, y)
        return nothing
    end
    walk2(_unwrap(x))
    return out
end

# `part` under `name` with a placeholder inner System: what the construction checks, the
# compile pipeline's rewrites (`_replace`) and `_inner_system` read (they never read the inner)
_staged(name::Symbol, part::PottsPart) = PottsSystem(_Wrap(), name, _empty_inner(name), nothing, part)
_empty_inner(name) = ModelingToolkitBase.System(Equation[], _unwrap(t); name)

# The inner System of a model: its quantities, equations, observed equations and components.
# MTK's component checks run; its unit check does not (`mtkcompile` runs Potts' own, which
# names the statement: a built-in such as `volume` carries the lattice's units there).
# A field equation with a raw spatial derivative (`Differential(x)(K * Differential(x)(c))`, F2
# design §2.11) stays out of it: an MTK `System` has one independent variable, the time; the
# model's PDESystem (`Potts.fields`) holds it.
function _inner_system(sys::PottsSystem)
    spatial(eq) = (u = _unwrap(eq.rhs); found = Ref(false);
                   _walk_all(y -> iscall(y) && operation(y) isa Differential && !isequal(operation(y).x, _unwrap(t)) &&
                                  (found[] = true), u); found[])
    eqs = [eq for eq in _p(sys, :equations) if !spatial(eq)]
    return ModelingToolkitBase.System(eqs, _unwrap(t), _p(sys, :variables), _p(sys, :parameters);
        name = nameof(sys), observed = _p(sys, :observed), initialization_eqs = _p(sys, :initialization_eqs),
        systems = _component_systems(_p(sys, :components)), checks = ModelingToolkitBase.CheckComponents)
end

# The compile pipeline and `Potts.extend` read the payload only. A model whose inner System
# holds more than its payload builds (a `Potts.compose` result, a `Potts.wrap` of a hand-built
# System with subsystems) is first lowered (`_lower_inner`): each subsystem the payload does
# not declare becomes a model-scope component (`ComponentSpec(name, system, :model)`, as
# `@components model name = system`), and the model is rebuilt from that payload. Content the
# payload cannot hold (top-level equations, quantities or values of a hand-built System) is an
# `ArgumentError` naming it, never dropped.
# metadata key on an inner System built from a payload: `(part, token)`, where the token holds
# the exact final inner System. The check below is then a comparison of identities for every
# model `@potts_model` or the keyword constructor builds (no second build). MTK's `compose`,
# `extend` and `complete` copy metadata, so a System derived from a marked one carries the
# same pair; it is a different object from `token[]` and gets the full comparison.
struct _BuiltFrom end

# payload metadata key: the digest of the PDESystem `mtkcompile` built from the payload
struct _FieldsFrom end
# read with `getfield`: MTKBase has no public accessor for a PDESystem's `bcs` or `domain`
# (as in `_merge_fields`)
_pde_digest(f) = hash(Tuple(sort!(string.(collect(getfield(f, k)))) for k in (:eqs, :bcs, :domain, :ivs, :dvs, :ps)))

"""`wrap(name, …)` of the inner System that `part` builds (marked as built from it)."""
function _wrap_payload(name::Symbol, fields, part::PottsPart)
    token = Ref{Any}(nothing)
    inner = SymbolicUtils.setmetadata(_inner_system(_staged(name, part)), _BuiltFrom, (part, token))
    w = wrap(name, inner, fields, part)
    token[] = getfield(w, :inner)       # after `wrap`, which adds metadata of its own
    return w
end

# whether `sys` carries a PDESystem that its payload does not build (a hand-wrapped one)
_foreign_fields(sys::PottsSystem) = (f = _stored_fields(sys);
                                     f !== nothing && get(_p(sys, :metadata), _FieldsFrom, nothing) != _pde_digest(f))

_built_from_part(sys::PottsSystem) = (I = getfield(sys, :inner); m = SymbolicUtils.getmetadata(I, _BuiltFrom, nothing);
                                      m isa Tuple && m[1] === getfield(sys, :part) && m[2][] === I)

# the unflattened hierarchy of a complete System (`complete` does not carry every field, e.g.
# noise equations, into the flattened system)
_hierarchy(s) = something(ModelingToolkitBase.get_parent(s), s)

# The names by which the inner Systems `I` and `ref` differ (empty: the same content).
function _inner_diff(I, ref)
    M = ModelingToolkitBase
    names(xs) = Set(string.(collect(xs)))
    # MTK's accessors are recursive: a subsystem's content is in both; a top-level extra differs
    checks = ("unknowns" => M.unknowns, "equations" => M.equations, "parameters" => M.parameters,
        "observed equations" => M.observed, "initialization equations" => M.initialization_equations,
        "initial conditions" => s -> (string(k) * " => " * string(v) for (k, v) in M.initial_conditions(s)),
        "bindings" => s -> (string(k) * " = " * string(v) for (k, v) in M.bindings(s)),
        "continuous events" => M.continuous_events, "discrete events" => M.discrete_events, "jumps" => M.jumps,
        "brownians" => M.brownians, "tstops" => _all_tstops, "poissonians" => s -> _all_poissonians(_hierarchy(s)),
        "noise equations" => s -> _all_noise_eqs(_hierarchy(s)), "constraints" => M.constraints, "costs" => _nonzero_costs,
        "assertions" => s -> (string(k) * " => " * string(v) for (k, v) in M.assertions(s)))
    diff = String[]
    for (label, f) in checks
        a, b = names(f(I)), names(f(ref))
        a == b && continue
        extra = sort!(collect(setdiff(a, b)))
        push!(diff, "$label not in the payload: " * (isempty(extra) ? "(the payload's differ)" : join(first(extra, 5), ", ")))
    end
    return diff
end

"""
    _lower_inner(sys, what) -> PottsSystem

`sys` itself when its inner System is the one its payload builds; otherwise the model rebuilt
from its payload with every undeclared subsystem of the inner System's hierarchy as a
model-scope component (cutover C9: components rebuilt from `Potts.compose`). An
`ArgumentError` when the inner System holds anything else, or a component has inputs (field
bindings are not compiled into components).
"""
function _lower_inner(sys::PottsSystem, what::AbstractString)
    _built_from_part(sys) && return sys
    I, part = getfield(sys, :inner), getfield(sys, :part)
    M = ModelingToolkitBase
    P = something(M.get_parent(I), I)
    declared = Set(c.name for c in part.components if c isa ComponentSpec)
    extra = ComponentSpec[]
    subs = M.get_systems(P)
    for n in unique(nameof.(subs))
        count(s -> nameof(s) === n, subs) > 1 && throw(ArgumentError("$what: `$(nameof(sys))` has two components named " *
                                                                     "`$n`; give each component its own name"))
    end
    for s in subs
        nameof(s) in declared && continue          # an `@components` system of the payload
        # a subsystem built from a Potts payload (`get_parent(Potts.inner(m))` wrapped by hand)
        # carries what a `Potts.compose` component may not; check it the same way
        m = SymbolicUtils.getmetadata(s, _BuiltFrom, nothing)
        m isa Tuple && m[1] isa PottsPart && _check_component_part(nameof(s), m[1], what)
        for q in M.parameters(s)
            i = info(q)
            i !== nothing && i.role === :kindtable && throw(ArgumentError(
                "$what: component `$(nameof(s))` of `$(nameof(sys))` has the kind table `$q`; a composed component " *
                "is compiled once for the model, whose parameters are scalars: declare the table in the model"))
        end
        for u in M.unknowns(s)
            M.isinput(u) && throw(ArgumentError("$what: component `$(nameof(s))` of `$(nameof(sys))` has the input " *
                                                "`$u`; a component's inputs (field bindings) are not compiled (bind the " *
                                                "value with `@equations $(nameof(s)).p ~ …` on a parameter instead)"))
            # a composed component is one instance for the model: a quantity declared per site,
            # cell, edge or field would silently become one model-wide value
            i = info(u)
            i !== nothing && i.role in SCOPES && i.role !== :model &&
                throw(ArgumentError("$what: component `$(nameof(s))` of `$(nameof(sys))` declares `$u` per $(i.role); " *
                                    "a composed component is compiled once for the model (model scope), so " *
                                    "per-$(i.role) quantities are not supported in it: declare them in the model, " *
                                    "or use `@components cells(…) $(nameof(s)) = system` for a per-cell MTK system"))
        end
        # what a composed component's equations read: its own and model quantities only. A
        # population or site fold, a built-in or another scope's quantity is refused (a fold in a
        # composed component is not lowered by the CPM compiler; review round 2)
        for eq in [M.equations(s); M.observed(s)], side in (eq.lhs, eq.rhs)
            _walk_all(side) do y
                i = info(y)
                i === nothing || i.role in (:model, :param) || throw(ArgumentError(
                    "$what: component `$(nameof(s))` of `$(nameof(sys))` reads `$(i.name)` (a $(i.role === :bound_cell ||
                    i.role === :bound_site ? "population fold" : i.role)); a composed component reads its own and model " *
                    "quantities only: write the expression in the model (`@equations $(nameof(s)).p ~ …` on a parameter)"))
            end
        end
        push!(extra, ComponentSpec(nameof(s), s, :model))
    end
    lowered = isempty(extra) ? part : getfield(_replace(_staged(nameof(sys), part); components = Any[part.components; extra]), :part)
    w = _wrap_payload(nameof(sys), nothing, lowered)
    diff = _inner_diff(I, getfield(w, :inner))
    if isempty(diff)
        # a PDESystem that `mtkcompile` built from this payload (a compiled model's `sys` composed
        # again) is the payload's own (`_FieldsFrom` proves Potts' `mtkcompile` built it; fields
        # always compile from the payload, so w has none); any other PDESystem is the model's
        # fields, moved into the payload under their own names (F4-11)
        _foreign_fields(sys) || return w
        return _wrap_payload(nameof(sys), nothing, _with_pde(w, getfield(w, :part), getfield(sys, :fields), nothing, what))
    end
    throw(ArgumentError("$what: the inner System of `$(nameof(sys))` holds content its Potts payload cannot build (" *
                        join(diff, "; ") * "). Subsystems are compiled as model-scope components; top-level " *
                        "quantities, equations and values of a hand-built System are not: declare them in " *
                        "`@potts_model` or `PottsSystem(; …)`, or compose the hand-built System as a component"))
end

"""`sys` with some payload fields replaced (the compile pipeline's rewrites: the inner System
is kept as authored until `mtkcompile` rebuilds it from the lowered payload)."""
function _replace(sys::PottsSystem; kw...)
    part = getfield(sys, :part)
    return PottsSystem(_Wrap(), nameof(sys), getfield(sys, :inner), getfield(sys, :fields),
        PottsPart(; (f => getfield(part, f) for f in fieldnames(PottsPart))..., kw...))
end

"""
    Potts.resolve(sys::PottsSystem, b::Potts.FieldBinding)

The input that the binding `b` drives: `getproperty(foldl(getproperty, b.path; init = sys), b.name)`,
a term of `unknowns(sys)`.
"""
resolve(sys::PottsSystem, b::FieldBinding) = getproperty(foldl(getproperty, b.path; init = sys), b.name)

"""
    Potts.compose(p::PottsSystem, cs::PottsSystem...; name = nameof(p))

`p` with the systems `cs` as components: the inner Systems are composed (MTK's `compose` on
the unflattened hierarchies, `get_parent`), completed and wrapped, so `sys.c.x` is the
quantity `c₊x` of component `c` and nested compositions match composing the raw Systems.
The `PDESystem`s are merged; the payload is `p`'s, with each component's field bindings
under its name. A component's own CPM statements (energies, drives, …) are an
`ArgumentError`: components carry quantities, equations and bindings. `mtkcompile`,
`PottsProblem` and [`Potts.extend`](@ref) compile each component as a model-scope component
(`@components model c = system`: its unknowns are model variables `c₊x`, its parameters model
parameters `c₊k`). An `ArgumentError` names what a component cannot carry: inputs (field
bindings are not compiled into components), quantities per site, cell, edge or field, kind
tables, relations, kind classes, obstacle kinds, a schedule, `@bcs`, its own `@components`,
kinds or a lattice other than the model's, or a name the model already uses (a component or a
quantity). A component's PDESystem ([`Potts.component`](@ref) of a `PDESystem`) joins the
model's fields: its fields, parameters, equations and conditions become the model's, named
`c₊x`, and the result is rebuilt from its payload. A component's sweep and structural keywords are its constructor's
and are not read. Units and guesses of a component's quantities are kept; their types are not
(a component's unknowns and parameters become Real model quantities). Build a component with
[`Potts.component`](@ref): `Potts.compose(p, Potts.component(:rn, Catalyst.ode_model(complete(rn)), p))`
composes a Catalyst reaction network.
"""
function compose(p::PottsSystem, cs::PottsSystem...; name::Symbol = nameof(p))
    isempty(cs) && throw(ArgumentError("Potts.compose: give at least one component"))
    taken = Set{Symbol}(nameof.(ModelingToolkitBase.get_systems(something(ModelingToolkitBase.get_parent(inner(p)), inner(p)))))
    quantities = Set{Symbol}(Symbol(SymbolicIndexingInterface.getname(x)) for x in
                             [ModelingToolkitBase.unknowns(inner(p)); ModelingToolkitBase.parameters(inner(p))])
    for c in cs
        nameof(c) in taken && throw(ArgumentError("Potts.compose: `$(nameof(p))` already has a component named " *
                                                  "`$(nameof(c))`; give each component its own name"))
        nameof(c) in quantities && throw(ArgumentError("Potts.compose: `$(nameof(p))` has a quantity named " *
                                                       "`$(nameof(c))`; give the component another name"))
        push!(taken, nameof(c))
    end
    # a component's PDESystem joins the payload as fields (F4-11); its System, when it has
    # content, is composed as any other
    if any(c -> _stored_fields(c) !== nothing, cs)
        pdes = [c for c in cs if _stored_fields(c) !== nothing]
        plain = PottsSystem[c for c in cs if _stored_fields(c) === nothing || !_empty_system(inner(c))]
        p = _with_pde_components(p, pdes, isempty(plain) ? name : nameof(p))
        isempty(plain) && return p
        cs = Tuple(PottsSystem(_Wrap(), nameof(c), inner(c), nothing, getfield(c, :part)) for c in plain)
    end
    un(s) = ModelingToolkitBase.toggle_namespacing(something(ModelingToolkitBase.get_parent(inner(s)), inner(s)), true)
    sys = ModelingToolkitBase.compose(un(p), [un(c) for c in cs]; name)
    return wrap(name, complete(sys; allow_parameter_eqs = true), _merge_fields(name, p, cs), _merge_part(p, cs))
end

# whether the inner System `I` holds nothing (a `Potts.component` of a PDESystem)
_empty_system(I) = (M = ModelingToolkitBase; P = something(M.get_parent(I), I);
                    isempty(M.unknowns(I)) && isempty(M.parameters(I)) && isempty(M.equations(I)) &&
                    isempty(M.observed(I)) && isempty(M.get_systems(P)))

# `p` with the PDESystem of each component of `pdes` as fields, named `component₊n`, rebuilt
# from its payload (its own composed components lowered first, as `mtkcompile` does)
function _with_pde_components(p::PottsSystem, pdes, name::Symbol)
    base = _lower_inner(p, "Potts.compose")
    part = getfield(base, :part)
    for c in pdes
        _check_component_like(p, c)
        part = _with_pde(base, part, _stored_fields(c), nameof(c), "Potts.compose: component `$(nameof(c))`")
    end
    return _wrap_payload(name, nothing, part)
end

function _merge_fields(name, p, cs)
    fs = [f for f in (_stored_fields(p), map(_stored_fields, cs)...) if f !== nothing]
    isempty(fs) && return nothing
    merged(get) = unique(reduce(vcat, [collect(get(f)) for f in fs]))
    # read with `getfield`: MTKBase has no public accessor for a PDESystem's `bcs` or
    # `domain`, and the merge keeps the six stored fields exactly (friction register, HANDOFF §2);
    # `initial_conditions` are merged (one value per key), and the parts a merge cannot keep
    # (subsystems, analytic solutions) are refused, never dropped (SX-21)
    for f in fs
        isempty(getfield(f, :systems)) && getfield(f, :analytic) === nothing && getfield(f, :analytic_func) === nothing ||
            throw(ArgumentError("Potts.compose: the PDESystem `$(nameof(f))` has subsystems or analytic solutions, " *
                                "which a composed model's PDESystem does not carry; leave them out"))
    end
    ic = Dict{Any, Any}()
    for f in fs, (k, v) in getfield(f, :initial_conditions)
        haskey(ic, k) && !isequal(ic[k], v) && throw(ArgumentError(
            "Potts.compose: two PDESystems give `$k` different initial conditions ($(ic[k]) and $v)"))
        ic[k] = v
    end
    ps(f) = (x = getfield(f, :ps); x isa SciMLBase.NullParameters ? Any[] : x)
    return ModelingToolkitBase.PDESystem(merged(f -> getfield(f, :eqs)), merged(f -> getfield(f, :bcs)), merged(f -> getfield(f, :domain)), merged(f -> getfield(f, :ivs)),
        merged(f -> getfield(f, :dvs)), merged(ps); name, initial_conditions = ic)
end

const _STATEMENT_FIELDS = (:energies, :drives, :constraints, :updates, :divisions, :converts, :relationships, :link_rules,
    :discrete, :boundaries)

# What a composed component (a `Potts.compose` component, or a subsystem built from a Potts
# payload) cannot carry into the model, refused by name and never dropped: CPM statements; its
# relations, kind classes, obstacle kinds, schedule and boundary conditions; its own
# `@components` (a per-cell one would become model-wide; compose components directly).
function _check_component_part(name::Symbol, part::PottsPart, what)
    for f in _STATEMENT_FIELDS
        isempty(getfield(part, f)) || throw(ArgumentError("$what: component `$name` has $f; a component carries " *
                                                          "quantities, equations and field bindings, not CPM statements " *
                                                          "(build a component of a model with " *
                                                          "`Potts.component($(repr(name)), system, model)`)"))
    end
    for (f, label) in ((:relations, "relations"), (:kind_classes, "kind classes"), (:frozen_kinds, "obstacle kinds"),
            (:schedule, "a @schedule"), (:bcs, "@bcs"), (:components, "@components"))
        isempty(getfield(part, f)) || throw(ArgumentError("$what: component `$name` has $label; a composed " *
                                                          "component carries quantities, equations and field bindings only" *
                                                          (f === :components ? " (compose its components into the model directly, " *
                                                           "or declare them in the model with `@components`)" : "")))
    end
    return nothing
end

_same_lattice(a, b) = typeof(a) === typeof(b) && all(f -> isequal(getfield(a, f), getfield(b, f)), fieldnames(typeof(a)))

function _merge_part(p, cs)
    bindings = copy(_p(p, :bindings))
    for c in cs
        _check_component_like(p, c)
        append!(bindings, (FieldBinding([nameof(c); b.path], b.name, b.source) for b in _p(c, :bindings)))
    end
    return getfield(_replace(p; bindings), :part)
end

# what a component of `p` must be: no CPM statements, and the kinds and lattice of `p`
function _check_component_like(p, c)
    _check_component_part(nameof(c), getfield(c, :part), "Potts.compose")
    # a component's folds read kinds by number and the lattice's sites: they must be the model's
    _p(c, :kinds) == _p(p, :kinds) || throw(ArgumentError(
        "Potts.compose: component `$(nameof(c))` has the kinds $(_p(c, :kinds)), the model `$(nameof(p))` " *
        "$(_p(p, :kinds)); a component is built with the model's kinds (`Potts.component(name, system, model)`)"))
    _same_lattice(_p(c, :lattice), _p(p, :lattice)) || throw(ArgumentError(
        "Potts.compose: component `$(nameof(c))` has another lattice than the model `$(nameof(p))`; a component is " *
        "built with the model's lattice (`Potts.component(name, system, model)`)"))
    return nothing
end

# The `@components` systems, each under its component name (MTK's `sys.dc` finds it by name).
function _component_systems(components)
    out = ModelingToolkitBase.AbstractSystem[]
    for c in components
        c isa ComponentSpec && c.system isa ModelingToolkitBase.AbstractSystem || continue
        push!(out, nameof(c.system) === c.name ? c.system : Symbolics.rename(c.system, c.name))
    end
    return out
end

# The link endpoints `a`, `b` (bound in edge terms and link rules) are reserved globally
# (D-075 Q8); `@potts_model` rejects them at expansion (`_declare!`), this at construction.
const _ENDPOINT_NAMES = (:a, :b)
_endpoint_message(what, k) = "$what `$k`: `$k` is reserved (`a` and `b` are the link endpoints in edge terms and " *
                             "link rules); choose another name, e.g. `$(k)₀`"

function _check_reserved_names(sys)
    check(what, n) = n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message(what, n)))
    foreach(k -> check("kind", k), _p(sys, :kinds))
    for (what, xs) in (("parameter", _p(sys, :parameters)), ("variable", _p(sys, :variables)))
        for x in xs
            i = info(x)
            i === nothing && continue
            check(what, i.name)
            _check_internal_suffix(what, i.name)
            v = get(i.options, :vector, nothing)
            v === nothing || (check(what, v); _check_internal_suffix(what, v))
        end
    end
    foreach(o -> (i = info(o.lhs); i === nothing || (check("observed quantity", i.name);
                                                     _check_internal_suffix("observed quantity", i.name))), _p(sys, :observed))
    foreach(k -> check("relation", k), keys(_p(sys, :relations)))
    foreach(r -> check("relationship", r.name), _p(sys, :relationships))
    foreach(c -> check("component", c.name), _p(sys, :components))
    foreach(k -> check("structural parameter", k), keys(_p(sys, :structural)))
    _check_kind_classes(sys)
    return sys
end

# A class is a non-empty set of cell kinds of this system (D-135); `@kinds` checks the same
# at expansion, this catches programmatic builds.
function _check_kind_classes(sys)
    ncell = length(_p(sys, :kinds)) - 1
    for (i, g) in enumerate(_p(sys, :kind_classes))
        n = g.name
        n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message("kind class", n)))
        n in _reserved_names() && throw(ArgumentError(
            "kind class `$n` has the name of a built-in (`$n` means something else in @potts_model); choose another name"))
        any(h -> h.name === n, view(_p(sys, :kind_classes), 1:(i - 1))) &&
            throw(ArgumentError("kind class `$n` is declared twice in $(getfield(sys, :name))"))
        isempty(g.kinds) && throw(ArgumentError("kind class `$n` is empty; list at least one kind"))
        allunique(g.kinds) || throw(ArgumentError("kind class `$n` lists a kind twice: $(Tuple(g.kinds))"))
        for k in g.kinds
            1 <= k <= ncell || throw(ArgumentError("kind class `$n` lists kind number $k, which is not a cell kind of " *
                                                   "$(getfield(sys, :name)) (cell kinds are 1:$ncell; 0 is the medium)"))
        end
    end
    return nothing
end

# Suffixes of the state slots Potts adds (ODE and tick scratch, double-buffered fields): a
# declared name ending in one would collide with them. Every declared name is checked
# (D-130): scalar and vector variables and parameters and `@observed` names here, component
# names when components are bound (`_bind_components`, and the rebuilt system's names).
const _INTERNAL_SUFFIXES = ("__ode", "__tick", "__next", "__in", "__mask")
function _check_internal_suffix(what, n::Symbol)
    for suf in _INTERNAL_SUFFIXES
        endswith(String(n), suf) && throw(ArgumentError(
            "$what `$n`: names ending in `$suf` are reserved for Potts' internal state slots; choose another name"))
    end
    return nothing
end

# `nameof` and `get_name` are MTK's (`getfield(sys, :name)`); defining them here only invalidated MTK code

"""Parameter symbols of a model (scalars and kind tables), as declared."""
parameters(sys::PottsSystem) = _p(sys, :parameters)
"""Scoped state variables of a model, as declared."""
variables(sys::PottsSystem) = _p(sys, :variables)

"""
    Potts.lattice(sys::PottsSystem)

The lattice of a model (its `LatticeSpec`: `dims`, neighborhood, boundary). `sys.lattice`
is not a field read: `sys.<name>` is a declared symbol.
"""
lattice(sys::PottsSystem) = _p(sys, :lattice)

# --- The container's owned methods (W-lite LA, v3 §7.1). Exactly these 15; a test lists them.
# Each forwards to the complete inner System. `nameof` is MTK's generic method on the `name`
# field. MTKBase's own SymbolicIndexingInterface methods on `::AbstractSystem` would read the
# container's (absent) index cache, so the five SII methods below route them to the inner
# System; `symbolic_container` covers the rest of the interface.
const _MTKB = ModelingToolkitBase
const _SII = SymbolicIndexingInterface

Base.getproperty(s::PottsSystem, n::Symbol) = getproperty(getfield(s, :inner), n)
_MTKB.equations(s::PottsSystem) = _MTKB.equations(getfield(s, :inner))
_MTKB.unknowns(s::PottsSystem) = _MTKB.unknowns(getfield(s, :inner))
_MTKB.parameters(s::PottsSystem; kw...) = _MTKB.parameters(getfield(s, :inner); kw...)
_MTKB.observed(s::PottsSystem) = _MTKB.observed(getfield(s, :inner))
_MTKB.initial_conditions(s::PottsSystem) = _MTKB.initial_conditions(getfield(s, :inner))
_MTKB.bindings(s::PottsSystem) = _MTKB.bindings(getfield(s, :inner))
_MTKB.independent_variables(s::PottsSystem) = _MTKB.independent_variables(getfield(s, :inner))
_SII.symbolic_container(s::PottsSystem) = getfield(s, :inner)
_SII.parameter_index(s::PottsSystem, sym) = _SII.parameter_index(getfield(s, :inner), sym)
_SII.parameter_index(s::PottsSystem, sym::Symbol) = _SII.parameter_index(getfield(s, :inner), sym)
_SII.is_parameter(s::PottsSystem, i::_MTKB.ParameterIndex) = _SII.is_parameter(getfield(s, :inner), i)
_SII.observed(s::PottsSystem, sym; kw...) = _SII.observed(getfield(s, :inner), sym; kw...)
_SII.parameter_observed(s::PottsSystem, sym) = _SII.parameter_observed(getfield(s, :inner), sym)
# (+ `Base.show(io, ::MIME"text/plain", ::PottsSystem)` below)

# --- Refusals (v3 §7.1, FR-32): SciMLBase's `{iip}` constructors accept any object as `f`, so
# without these `ODEProblem{true}(sys, …)` and nine other routes return a problem that fails
# only at `solve`. Every problem constructor MTKBase extends, plus `JumpProblem`, in the plain,
# `{iip}` and `{iip, spec}` forms: 48 methods (and one disambiguation, below).
const _REFUSED_PROBLEMS = (:ODEProblem, :NonlinearProblem, :SteadyStateProblem, :SDEProblem, :DAEProblem, :DDEProblem,
    :SDDEProblem, :BVProblem, :DiscreteProblem, :ImplicitDiscreteProblem, :NonlinearLeastSquaresProblem, :LinearProblem,
    :IntervalNonlinearProblem, :HomotopyProblem, :OptimizationProblem)
_problem_msg(f) = "$f: a Potts model is not an ODE or jump system; build its problem with `PottsProblem(sys, op, tspan)` " *
                  "and solve it with a CPM algorithm (for the cell/model ODE alone, use `Potts.inner(sys)`)"
# The second argument is what a problem constructor takes after the system (an operating
# point, `u0`, a `tspan`, …): typed so that the refusals stay unambiguous with SciMLBase's and
# JumpProcesses' own methods on a jump set, an aggregator or a jump (Aqua's ambiguity check).
# Names and symbols are included: `ODEProblem{true}(sys, :x, tspan)` must not build either.
const _ProblemArg = Union{AbstractArray, AbstractDict, Tuple, NamedTuple, Pair, Number, Nothing, Symbol, AbstractString,
    AbstractChar, Function, SymbolicUtils.BasicSymbolic}
for (M, n) in ((:JumpProcesses, :JumpProblem), ((:SciMLBase, n) for n in _REFUSED_PROBLEMS)...)
    P = Expr(:., M, QuoteNode(n))
    msg = String(n)
    @eval begin
        $P(::PottsSystem, ::_ProblemArg, args...; kw...) = throw(ArgumentError(_problem_msg($msg)))
        $P{iip}(::PottsSystem, ::_ProblemArg, args...; kw...) where {iip} = throw(ArgumentError(_problem_msg($msg)))
        $P{iip, spec}(::PottsSystem, ::_ProblemArg, args...; kw...) where {iip, spec} =
            throw(ArgumentError(_problem_msg($msg)))
    end
end
# SciMLBase's own `ODEProblem{iip, FunctionWrapperSpecialize}(f, u0, tspan[, p])` meets the
# `{iip, spec}` refusal there: this one method settles that ambiguity (49 methods in all)
SciMLBase.ODEProblem{iip, SciMLBase.FunctionWrapperSpecialize}(::PottsSystem, ::_ProblemArg, args...; kw...) where {iip} =
    throw(ArgumentError(_problem_msg("ODEProblem")))

# MTK's `extend` with a Potts model on either side (D-039): a clear refusal naming the two
# ways that work, not MTK's rebuild of the container (which has no MTK constructor).
_extend_msg(a, b) = "extend($(nameof(a)), $(nameof(b))): MTK's `extend` does not merge a Potts model; merge two Potts " *
                    "models with `Potts.extend(sys, base)`, and add an MTK System to a Potts model as `@components`"
ModelingToolkitBase.extend(a::PottsSystem, b::ModelingToolkitBase.AbstractSystem; kw...) =
    throw(ArgumentError(_extend_msg(a, b)))
ModelingToolkitBase.extend(a::ModelingToolkitBase.AbstractSystem, b::PottsSystem; kw...) =
    throw(ArgumentError(_extend_msg(a, b)))
ModelingToolkitBase.extend(a::PottsSystem, b::PottsSystem; kw...) = throw(ArgumentError(_extend_msg(a, b)))

# --- Keys namespaced by the model itself (D-137 review SF1). `sys.x` of an uncompleted `sys`
# is `pr₊x`; wherever a key names a model quantity (operating point, `remake`, `getu`/`setu`/
# `getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`) it means the declared `x`. A key
# namespaced by another name names nothing here: with `strict`, an `ArgumentError`.

# the name of a symbolic key (`x` of `x` or `x(t)`), or `nothing` for other expressions
function _key_name(u)
    u isa SymbolicUtils.BasicSymbolic || return nothing
    (issym(u) || (iscall(u) && issym(operation(u)))) || return nothing
    return SymbolicIndexingInterface.getname(u)
end
_namespaced(n::Symbol) = occursin('₊', String(n))
_declared_quantities(sys::PottsSystem) = Dict{Symbol, Any}(i.name => _unwrap(x) for x in Iterators.flatten((
    _p(sys, :parameters), _p(sys, :variables), (o.lhs for o in _p(sys, :observed))))
                                                           for i in (info(x),) if i !== nothing)
# `pr₊x` → `:x` when `x` is declared and `pr₊x` is not; otherwise `nothing`
function _own_name(sys::PottsSystem, n::Symbol, declared)
    haskey(declared, n) && return nothing
    pre = string(nameof(sys), '₊')
    s = String(n)
    startswith(s, pre) || return nothing
    m = Symbol(SubString(s, ncodeunits(pre) + 1))
    return haskey(declared, m) ? m : nothing
end
function _foreign_key(sys::PottsSystem, n::Symbol, declared)
    haskey(declared, n) && return nothing
    throw(ArgumentError("`$n` is namespaced by another system: model `$(nameof(sys))` declares no such quantity; " *
                        "key by this model's own symbols (`sys.x`, or `$(nameof(sys))₊x`)"))
end

# `k` (after `_localize`) is a single symbol namespaced by another system: its name has a
# `₊` and names no declared quantity
function _foreign(sys::PottsSystem, k)
    n = k isa Symbol ? k : _key_name(_unwrap(k))
    n isa Symbol && _namespaced(n) || return false
    return !haskey(_declared_quantities(sys), n)
end

"""The key `k` with this model's namespace (`pr₊x`) removed: the declared quantity (or its
name, for a `Symbol` key); in an expression, every such symbol. Other keys are returned as
they are, or with `strict` a key namespaced by another name is an `ArgumentError`."""
function _localize(sys::PottsSystem, k; strict::Bool = false)
    if k isa Symbol
        _namespaced(k) || return k
        declared = _declared_quantities(sys)
        m = _own_name(sys, k, declared)
        m === nothing || return m
        strict && _foreign_key(sys, k, declared)
        return k
    end
    u = _unwrap(k)
    u isa SymbolicUtils.BasicSymbolic || return k
    n = _key_name(u)
    if n !== nothing
        n isa Symbol && _namespaced(n) || return k
        declared = _declared_quantities(sys)
        m = _own_name(sys, n, declared)
        m === nothing || return declared[m]
        strict && _foreign_key(sys, n, declared)
        return k
    end
    iscall(u) || return k
    found = Any[]
    _walk_all(y -> ((ny = _key_name(y)) isa Symbol && _namespaced(ny) && push!(found, y)), u)
    isempty(found) && return k
    declared = _declared_quantities(sys)
    subs = Dict{Any, Any}()
    for y in found
        n = _key_name(y)
        m = _own_name(sys, n, declared)
        if m !== nothing
            subs[y] = declared[m]
        elseif strict
            _foreign_key(sys, n, declared)
        end
    end
    isempty(subs) && return k
    return Symbolics.substitute(u, subs; fold = Val(false))
end

function Base.show(io::IO, ::MIME"text/plain", sys::PottsSystem)
    println(io, "PottsSystem ", getfield(sys, :name), " on ", join(_p(sys, :lattice).dims, "×"), " (", length(_p(sys, :lattice).dims), "D)")
    println(io, "  kinds: ", join(_p(sys, :kinds), ", "))
    isempty(_p(sys, :parameters)) || println(io, "  parameters: ", join(map(_param_show, _p(sys, :parameters)), ", "))
    isempty(_p(sys, :variables)) || println(io, "  variables: ",
        join(map(v -> string(info(v).name, "(", info(v).role, ")"), _p(sys, :variables)), ", "))
    for e in _p(sys, :energies)
        println(io, "  energy  ", _domain_string(e.domain), " => ", e.expr)
    end
    for d in _p(sys, :drives)
        println(io, "  drive   copy => ", d.expr)
    end
    for c in _p(sys, :constraints)
        println(io, "  constraint ", c.kind === :expr ? c.expr : string(c.kind, c.kinds))
    end
    for u in _p(sys, :updates)
        println(io, "  @", u.phase, " ", u.eq)
    end
    for e in _p(sys, :equations)
        println(io, "  equation ", e)
    end
    for e in _p(sys, :initialization_eqs)
        println(io, "  initialization ", e)
    end
    for b in _p(sys, :discrete)
        println(io, "  tick    ", b.name, b.scope === :model ? " (model)" : "", b.every == 1 ? "" : " every $(b.every) MCS",
            ": ", join((string(info(x).name, " ← ", y) for (x, y) in zip(b.slots, b.next)), ", "))
    end
    for d in _p(sys, :divisions)
        println(io, "  divide  ", _domain_string(d.domain), _cadence_string(d.every), " when ", d.when)
    end
    for v in _p(sys, :converts)
        println(io, "  convert ", v.name, " ", _domain_string(v.domain), ": ", v.from, " → ", v.to,
            v.fresh == 0 ? "" : " (fresh kind $(v.fresh))", ", at ", v.at, ", p = ", v.p)
    end
    for b in _p(sys, :boundaries)
        println(io, "  boundary ", info(b.field).name, " ", b.axis == 0 ? "sites($(b.mask)) => Dirichlet($(b.value))" :
                                                          "$(_AXIS_NAMES[b.axis]) => ($(_side_string(b.sides[1])), $(_side_string(b.sides[2])))")
    end
    for b in _p(sys, :bcs)
        println(io, "  bc      ", b)
    end
    for b in _p(sys, :bindings)
        println(io, "  binding ", join([b.path; b.name], '.'), " ← ", b.source)
    end
    isempty(_p(sys, :schedule)) || println(io, "  schedule ", join(_p(sys, :schedule), ", "))
    println(io, "  sweep: ", _p(sys, :sweep).law, "(temperature = ", _p(sys, :sweep).temperature, ")")
    s = inner(sys)
    print(io, "  inner: System ", nameof(s), " with ", _count_string(length(_MTKB.equations(s)), "equation"), ", ",
        _count_string(length(_MTKB.unknowns(s)), "unknown"), ", ", _count_string(length(_MTKB.parameters(s)), "parameter"))
    isempty(_MTKB.unknowns(s)) || print(io, "\n    unknowns: ", join(_MTKB.unknowns(s), ", "))
    f = _stored_fields(sys)    # the stored slot (not built here); counts read with `getfield`, as in `_merge_fields`
    f === nothing || print(io, "\n  fields: PDESystem with ", _count_string(length(getfield(f, :eqs)), "equation"), ", ",
        _count_string(length(getfield(f, :bcs)), "bc"), ", ", _count_string(length(getfield(f, :dvs)), "dependent variable"))
end

# a parameter with its MTK description (F2-14): `Dc ("diffusion of c")`
_param_show(p) = (d = SymbolicUtils.getmetadata(_unwrap(p), ModelingToolkitBase.VariableDescription, nothing);
                  d === nothing ? string(info(p).name) : string(info(p).name, " (", repr(d), ")"))
_side_string(s::Dirichlet) = "Dirichlet($(s.value))"
_side_string(::NoFlux) = "NoFlux()"

# with the model's kind names (`kinds`, the medium first), kinds print as authored
_domain_string(d::CellDomain, kinds = nothing) = isempty(d.kinds) ? "cells" : "cells(" * _kind_list(d.kinds, kinds) * ")"
_domain_string(d::ClusterDomain, kinds = nothing) = isempty(d.kinds) ? "clusters" : "clusters(" * _kind_list(d.kinds, kinds) * ")"
_domain_string(d, ::Any) = _domain_string(d)
_kind_list(ks, names) = join((names !== nothing && 0 <= k < length(names) ? names[k + 1] : k for k in ks), ", ")
_domain_string(d::ContactDomain) = d.relation === :contact ? "contacts" : "contacts($(d.relation))"
_domain_string(::SiteDomain) = "sites"
_domain_string(d::EdgeDomain) = "edges($(d.relationship))"
_domain_string(d) = string(d)
