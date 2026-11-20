# `PottsSystem`: the authored model, an MTK `AbstractSystem` wrapping a complete inner `System`
# (a light container: Potts keeps its own payload next to it). `mtkcompile` turns it into a `CompiledPottsSystem` (compile.jl).

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

A coupling of a model input to the field side: the input `name` of the component at
`path` (a vector of component names, empty for the model itself) is driven by `source`.
Bindings are stored per component as `(path, name)`; `compose` prefixes the
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
equations, `@components`, the conditions of the coupled fields (`bcs`, stored and printed;
the field compiler classifies them), the `@schedule`, the sweep and the field bindings
([`Potts.FieldBinding`](@ref)).
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
    bcs::Vector{Equation} = Equation[]         # the coupled PDESystems' conditions (MTK equations), stored and printed
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
[`Potts.wrap_system`](@ref).

MTK's accessors read the inner System: `equations(sys)` (the `@equations` as written, plus
each component's equations, namespaced `dc₊y`), `unknowns(sys)` (the declared variables of
every scope plus each component's unknowns; never the lattice ownership, kinds or built-in
cell properties, and never a field: the fields and their equations are in
[`Potts.fields`](@ref)`(sys)`, a `PDESystem`; `sys.c` still names the field `c`), `parameters(sys)`, `observed(sys)` (one `name ~ expr` per `@observed`
quantity), `initial_conditions(sys)` (each parameter's value: its default, or the keyword that
overrides it), `bindings(sys)`, `guesses(sys)`, `inputs(sys)`, `outputs(sys)`,
`independent_variable(sys)` and `get_iv(sys)` (`t`), the metadata (`getmetadata`, `hasmetadata`; `setmetadata`
returns the model with its inner System's metadata set) and `nameof(sys)`. A model is complete:
`iscomplete(sys)` is `true`, `does_namespacing(sys)` is `false` and `complete(sys)` returns it
(MTK's `complete` keywords are an `ArgumentError` that names them).
SymbolicIndexingInterface getters and setters built from the model (`getp(sys, λ)`,
`getu(sys, volume)`) look their symbol up in the problem, integrator or solution they are
applied to; other SymbolicIndexingInterface queries are answered by the inner System.

`sys.x` is MTK's own `getproperty` on the complete inner System: the declared symbol itself
(`sys.λ` is `λ`), and `sys.dc.y` is the component quantity `dc₊y`. A name that is not a
quantity or component of the system is an `ArgumentError`. Either form, and the namespaced
`name₊x` of the model's own name, works as a key wherever a model quantity is named
(operating point, `remake`, `getu`/`setu`/`getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`)
for a model built by `@potts_model` or the keyword constructor. A model from
`compose` compiles, solves
and extends with each component as a model-scope component (`@components model c = system`);
a `Potts.wrap_system` of a hand-built System does when its top-level content is its payload's and the
rest is subsystems (otherwise an `ArgumentError` naming the content).

MTK's operations: `compose(sys, [components])` adds components,
`extend``(sys, base)` merges two
Potts models (`@extend`), and `rename(sys, name)` (and `@named models[1:n] = Model(…)`)
renames. MTK's `extend` between a Potts model and another system, and MTK's `compose` with a
Potts model inside a plain `System` (alone or among other systems), are `ArgumentError`s naming the route;
`toggle_namespacing` is an `ArgumentError`. Every SciMLBase problem constructor (`ODEProblem`,
`JumpProblem`, …) is an `ArgumentError` naming `PottsProblem`; `mtkcompile(sys)` compiles the
CPM ([`CompiledPottsSystem`](@ref)). Other MTKBase functions (`get_eqs`, …) are asked of
`Potts.inner(sys)`. `Potts.lattice(sys)` is the model's lattice and
`Potts.declared_parameters(sys)`/`Potts.declared_variables(sys)` its own declarations.
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
    Potts.inner(csys::CompiledPottsSystem)

The complete (flattened) ModelingToolkitBase `System` of a model: its parameters, its cell,
model and site variables, their `@equations`, `@observed` and components. The fields and their
equations are not in it (an MTK `System` has one independent variable, the time): they are in
[`Potts.fields`](@ref)`(sys)`, a `PDESystem`. Generic MTK code takes it where it needs a
`System` (`mtkcompile(Potts.inner(sys); inputs = …)` compiles the cell/model ODE alone).
Of a compiled system it is the System of the model as `mtkcompile` lowered it: an algebraic
variable it eliminated is among its observed equations.
"""
inner(sys::PottsSystem) = getfield(sys, :inner)

"""
    Potts.part(sys::PottsSystem) -> PottsPart

The Potts payload of a model (kinds, lattice, energies, sweep, …). A component for
`compose` is built with [`Potts.component`](@ref), which takes the model's kinds and
lattice and none of its statements.
"""
part(sys::PottsSystem) = getfield(sys, :part)

"""
    Potts.component(name, sys::System, model::PottsSystem) -> PottsSystem

The MTK `System` `sys` as a component of `model`, for `compose`: it is
`Potts.wrap_system(name, sys, nothing, part)` with a payload that has the kinds, the lattice and the
sweep of `model` and no statements (no energies, drives, constraints, …), which is what a
composed component may carry. `sys` is named `name` (`@named`); a Catalyst reaction network
`rn` is `Potts.component(name, Catalyst.ode_model(complete(rn)), model)`.

```julia
@named decay = System([D(y) ~ -k * y], t)
sys = compose(model, [Potts.component(:decay, decay, model)])
```
"""
function component(name::Symbol, sys::ModelingToolkitBase.System, model::PottsSystem)
    return wrap_system(name, sys, nothing, _component_part(model))
end

"""
    Potts.component(name, pdesys::PDESystem, model::PottsSystem) -> PottsSystem

The `PDESystem` `pdesys` (named `name`) as fields of `model`, for `compose`.
`compose(model, [Potts.component(:drug, pdesys, model)])` adds each dependent variable
`c` as the field `drug₊c`, each parameter `k` as the parameter `drug₊k` (with its value),
each equation as a field equation and each condition as a condition of the model, so the
fields run as the fields of `@fields` do: with the default field solver, or by name in
`FieldGroups(:drug₊c => …)`. A condition at the start time, `c(0, x, y) ~ v`, is the field's
initial value. Its time interval is not read (the problem's `tspan` is).

The spatial domain is the lattice's, in the model's length unit: axis `d` spans
`[0, dims[d] · spacing[d]]` (`[0, dims[d]]` without `@lattice spacing`), the domain
`Potts.fields(model)` gives; another interval is an `ArgumentError` naming both. An input
variable (`[input = true]`) is filled by the CPM by its `lattice_input_name` (or else its
own name): `"kind"` is the kind of each site (0 for the medium), and the name of a field
or site variable of the model reads that variable.
"""
function component(name::Symbol, pdesys::ModelingToolkitBase.PDESystem, model::PottsSystem)
    return wrap_system(name, ModelingToolkitBase.System(Equation[], _unwrap(t); name), pdesys, _component_part(model))
end

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
CPM expression at a site: `inputs = [endo => Potts.is_kind(model, :A), vol =>
Potts.at(Potts.B.volume, Potts.B.owner)]`. A kind is compared by its number
([`Potts.is_kind`](@ref), or `Potts.kind == Potts.lookup(model, :A)`): `Potts.kind == :A` is
Julia's constant `false`, and a binding to a constant truth value is an `ArgumentError` saying so. The field compiler fills each one per site every MCS, as it fills the CPM
reads of a field equation, so `pdesys` itself holds only plain input fields (0/1 or numbers),
never a Potts quantity. A key is the input variable (`endo` or `endo(t, x, y)`) or its name. A
`Bool` input (`endo(..)::Bool`) takes a truth value. An input left unbound is filled by its
`lattice_input_name` (or its name), as in [`Potts.component`](@ref): `kind`, `owner`,
`position`, `site`, `mcs`, `time`, or a field or site variable of the model.

The spatial domain of `pdesys` is the lattice's, in the model's length unit (axis `d` spans
`[0, dims[d] · spacing[d]]`). An axis `pdesys` gives no interval for takes that one; a given
interval must equal it. Its time interval is not read (the problem's `tspan` is). A name
`model` already has is an `ArgumentError`; compose it as a component to namespace it.
`pdesys` stays a plain MTK system. [`Potts.fields`](@ref)`(model)` is the PDESystem of the
coupled model's fields (each binding written in as its CPM input), and
[`Potts.field_inputs`](@ref) gives the current values of its inputs, so `discretize(Potts.fields(model),
disc; inputs = collect(Potts.field_inputs(integ)))` solves the fields with any SciML solver at
the CPM state of an integrator (`Potts.field_inputs(integ, pdesys)` gives those of `pdesys`
itself). Inside `@potts_model`, write
`@fields c = pdesys (endo => kind == A, …)`: the fields join the model at that line, and the
names before `=` (`c`, or a list `c, u`) are bound to them for the statements after it
(`@drive Chemotaxis(c; …)`). A name may also be a parameter of `pdesys` (`@fields c, s = pdesys
(…)`): a later statement then reads the model's copy of it (`@drive copy => -s * …`). Without names (`@fields pdesys (…)`) the fields join the model
and are reached by name (`sol[:c]`) only.
"""
function couple(model::PottsSystem, pdesys::ModelingToolkitBase.PDESystem; inputs = ())
    what = "Potts.couple"
    base = _lower_inner(model, what)
    part = _with_pde(base, getfield(base, :part), pdesys, nothing, what; inputs = collect(Any, inputs))
    return _wrap_payload(nameof(model), nothing, part)
end

"""
    Potts.is_kind(model::PottsSystem, name::Symbol, names::Symbol...)

The test that a site's kind is `name` (or one of `name, names…`), for a binding of
[`Potts.couple`](@ref): `inputs = [endo => Potts.is_kind(model, :A)]`. One name gives
`Potts.kind == Potts.lookup(model, name)`, several a membership test
(`ismember(Potts.kind, (a, b))`). The medium is a kind (`:medium`, number 0). A name that is
not a kind of `model` is an `ArgumentError` that lists its kinds. (`Potts.kind == :A` is Julia's
constant `false`; this is the route.)
"""
function is_kind(model::PottsSystem, names::Symbol...)
    ks = _p(model, :kinds)
    isempty(names) && throw(ArgumentError("Potts.is_kind: give at least one kind name, `Potts.is_kind(model, :A)`"))
    codes = map(names) do n
        k = findfirst(==(n), ks)
        k === nothing && throw(ArgumentError(string("Potts.is_kind: `", n, "` is not a kind of `", nameof(model), "`; its ",
            "kinds are ", join(("`$k`" for k in ks), ", "))))
        return k - 1
    end
    return length(codes) == 1 ? B.kind == only(codes) : LatticePDE.ismember(B.kind, Tuple(codes))
end

# the payload of a component of `model`: its kinds, lattice and sweep, and nothing else
function _component_part(model::PottsSystem)
    return PottsPart(; kinds = copy(_p(model, :kinds)), lattice = _p(model, :lattice), sweep = _p(model, :sweep))
end

"""
    Potts.fields(sys::PottsSystem)
    Potts.fields(c::CompiledPottsSystem)

The `PDESystem` of a model's fields, or `nothing` for a model without fields. A model built
by `@potts_model`, `Potts.couple` or `compose` has its PDESystem built from the field
variables, equations and conditions of its coupled PDESystems; a compiled model returns the
one `mtkcompile` built.
Either carries the model's defaults as `initial_conditions` (each field's initial value and
each parameter's value), so LatticePDE's `discretize` takes it as a plain PDE system. Its CPM
couplings are `input = true` dependent variables, each with a name (`lattice_input_name`):
`kind` for the kind of each site (a binding to a kind expression, `endo => kind == A`, is
written into the equations as that expression of `kind`), `domain` for an irregular domain,
the name of the coupled PDESystem's input for a binding to a CPM read (`vol` for `vol =>
volume[owner]`: the input variable is `vol(t, x, y)`, in the equations too), and the CPM read
as the model writes it (`volume[owner]`) for any other.
[`Potts.field_inputs`](@ref) gives their values by these names, so

```julia
F = Potts.fields(model)
prob = discretize(F, LatticeDiscretization(Grid(dims)); inputs = collect(Potts.field_inputs(integ)))
```

solves the fields with any SciML solver at the CPM state of `integ` (by hand, `inputs =
[:kind => K, :vol => V]`, with `K` the kind number of each site, 0 for the medium). For a
coupled PDESystem of your own, `Potts.field_inputs(integ, pdesys)` gives its inputs. Its
conditions are those of the coupled PDESystems, as `discretize` takes them. A hand-wrapped
PDESystem (`Potts.wrap_system`) is returned as given.
"""
function fields(sys::PottsSystem)
    f = _stored_fields(sys)
    eqs = _field_equations(sys)
    # a model whose only fields are aux fields `K ~ rhs` has a PDESystem of aux equations
    none = isempty(eqs) && isempty(_field_aux(sys))
    f === nothing && none && return nothing
    f === nothing && (f = first(_field_system(sys)))
    none && return f                                # a hand-wrapped PDESystem, as given
    return _named_inputs(_with_defaults(f, eqs), sys)
end

# The CPM inputs of `Potts.fields(sys)` by the names a user gives their values
# (`lattice_input_name`), which `Potts.field_inputs` uses as its keys: `kind` and
# `domain` stay; a filled CPM read (`field1__in`) is named by the PDESystem input bound to
# exactly that read (`vol => volume[owner]` names it `vol`), else by the read as the model
# writes it (`volume[owner]`). A name another input, a field, a site variable or a parameter has
# falls back to the read's text. The field compiler's own PDESystem is not renamed (its program,
# input routing and fingerprint keep the generated names).
# A name that is an identifier (`vol`, a binding's name) is the input variable's own name too, in
# the equations, the conditions and every report (before, the variable kept
# its generated name `field1__in` and only its `lattice_input_name` was `vol`).
function _named_inputs(f::ModelingToolkitBase.PDESystem, sys::PottsSystem)
    names = _input_names(sys)
    isempty(names) && return f
    # the generated input `field1__in` as the variable `vol(t, x, y)`, with its metadata
    renamed = Dict{Any, Any}()
    for dv in _MTKB.get_dvs(f)
        u = _unwrap(dv)
        (ModelingToolkitBase.isinput(u) && iscall(u)) || continue
        g = nameof(operation(u))
        w = get(names, g, nothing)
        (w === nothing || !Base.isidentifier(w) || w == string(g)) && continue
        renamed[operation(u)] = _renamed_input(u, Symbol(w))
    end
    function rename(u)
        u = _unwrap(u)
        return if iscall(u) && haskey(names, nameof(operation(u)))
                SymbolicUtils.setmetadata(u, LatticePDE.LatticeInputName, names[nameof(operation(u))])
            else
                u
            end
    end
    function sub(x)
        reps = Dict{Any, Any}()
        _walk_all(x) do y
            iscall(y) && haskey(renamed, operation(y)) && (reps[y] = renamed[operation(y)](arguments(y)...))
        end
        return isempty(reps) ? x : _unwrap(Symbolics.substitute(_unwrap(x), reps; fold = Val(false)))
    end
    subeq(eqs) = isempty(renamed) ? eqs : Equation[Equation(sub(eq.lhs), sub(eq.rhs)) for eq in eqs]
    eqs, bcs = subeq(_MTKB.get_eqs(f)), subeq(_MTKB.get_bcs(f))
    dvs = Any[ModelingToolkitBase.isinput(_unwrap(dv)) ? Symbolics.wrap(rename(sub(dv))) : dv for dv in _MTKB.get_dvs(f)]
    return ModelingToolkitBase.PDESystem(
        eqs, bcs, _MTKB.get_domain(f), _MTKB.get_ivs(f), dvs,
        _MTKB.get_ps(f); name = nameof(f), initial_conditions = _MTKB.get_initial_conditions(f)
    )
end
# the callable of an input `u = g(t, x, y)` under the name `w`: each call carries `u`'s metadata
# (input, bounds, storage, level, its CPM read) with `w` as its `lattice_input_name`, not its
# source name
function _renamed_input(u, w::Symbol)
    f = Symbolics.unwrap(Symbolics.variable(w; T = SymbolicUtils.FnType{Tuple, SymbolicUtils.symtype(u), Nothing}))
    keep = Pair{Any, Any}[k => x for k in (ModelingToolkitBase.VariableInput, ModelingToolkitBase.VariableBounds,
        LatticePDE.LatticeStorage, LatticePDE.LatticeLevel, PottsEntity) for x in (SymbolicUtils.getmetadata(u, k, nothing),)
                          if x !== nothing]
    push!(keep, LatticePDE.LatticeInputName => string(w))
    return (args...) -> foldl((v, kx) -> SymbolicUtils.setmetadata(v, kx[1], kx[2]), keep; init = f(args...))
end
# generated input name => the name `Potts.fields` gives it (the filled inputs of `sys`)
function _input_names(sys::PottsSystem)
    filled = _field_inputs(sys)
    out = Dict{Symbol, String}()
    isempty(filled) && return out
    user = get(_p(sys, :metadata), _FieldInputs, ())
    taken = Set{String}(string(info(x).name) for x in Iterators.flatten((_p(sys, :variables), _p(sys, :parameters)))
                        if info(x) !== nothing && info(x).role in (:field, :site, :param, :kindtable))
    push!(taken, "kind", "domain")
    for (name, ex, _) in filled
        name in (:kind__in, :domain__in) && continue
        ks = unique!(Symbol[k for (k, e, _) in user if isequal(_unwrap(e), _unwrap(ex))])
        w = length(ks) == 1 ? string(only(ks)) : nothing
        (w === nothing || w in taken) && (w = _cpm_read_text(ex))
        w in taken && (w = string(name))           # (a model text another quantity has: the generated name)
        push!(taken, w)
        out[name] = w
    end
    return out
end
# a CPM read as the model writes it: `volume[owner]`, not `LatticePDE.value_at(volume, owner)`
function _cpm_read_text(ex)
    s = LatticePDE.as_written(replace(_builtin_text(string(ex)), "LatticePDE." => ""))
    return replace(replace(s, r"(\w+)\(t\)" => s"\1"), r"value_at\((\w+), (\w+)\)" => s"\1[\2]")
end

# the PDESystem `f` of a model's fields with the model's defaults added to its
# `initial_conditions` (a value already there is kept): the initial value of each field
# (`@variables c(field) = v`) and the value of each parameter (`@parameters k = v`, an
# expression of parameters for a computed one). Its parameters are the model's own symbols,
# whose defaults the payload holds (V13)
function _with_defaults(f::ModelingToolkitBase.PDESystem, eqs)
    ic = Dict{Any, Any}(_MTKB.get_initial_conditions(f))
    put!(k, v) = (v === nothing || any(x -> isequal(x, k), keys(ic)) || (ic[k] = v); nothing)
    byname = Dict{Symbol, Any}(info(x).name => info(x).default for (x, _) in eqs)
    for dv in _MTKB.get_dvs(f)
        u = _unwrap(dv)
        n = iscall(u) ? nameof(operation(u)) : nothing
        n isa Symbol && haskey(byname, n) && put!(u, byname[n])
    end
    ps0 = _MTKB.get_ps(f)
    ps = Any[(ps0 isa SciMLBase.NullParameters ? () : ps0)...]
    # a computed default (`k2 = 2k`) reads parameters the equations may not: they join the
    # system's parameters with their own defaults, so `discretize` can fold it
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
    return ModelingToolkitBase.PDESystem(
        _MTKB.get_eqs(f), _MTKB.get_bcs(f), _MTKB.get_domain(f), _MTKB.get_ivs(f),
        _MTKB.get_dvs(f), ps; name = nameof(f), initial_conditions = ic
    )
end
# the PDESystem slot of a wrap (a hand-wrapped or compiled one), without building it
_stored_fields(sys::PottsSystem) = getfield(sys, :fields)

"""
    Potts.wrap_system(name, sys::System, fields, part::PottsPart) -> PottsSystem

The `PottsSystem` holding `sys`, `fields` (a `PDESystem` or `nothing`) and the payload
`part`. Compose first, then wrap: an uncompleted `sys` is completed here (`complete`
flattens it and keeps the hierarchy as its parent). A complete system that still has
subsystems (`compose(complete(a), …)`) is an `ArgumentError`, and so is a name of `sys` or
`fields` other than `name`. The inner System carries the `Potts.PottsSweepSpec` metadata.
"""
function wrap_system(
        name::Symbol, sys::ModelingToolkitBase.System, fields::Union{Nothing, ModelingToolkitBase.PDESystem},
        part::PottsPart)
    nameof(sys) === name || throw(ArgumentError("wrap_system: the System is named `$(nameof(sys))`, the model `$name`; they must agree"))
    fields === nothing || nameof(fields) === name ||
        throw(ArgumentError("wrap_system: the PDESystem is named `$(nameof(fields))`, the model `$name`; they must agree"))
    ModelingToolkitBase.iscomplete(sys) || (sys = complete(sys; allow_parameter_eqs = true))
    isempty(_MTKB.get_systems(sys)) || throw(
        ArgumentError(
        "wrap: `$name` is complete but not flattened (it still has subsystems: a completed system was composed); " *
                "compose the uncompleted systems, then wrap them"
        )
    )
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
    part = _robin_slots(_check_field_lines(PottsPart(; kw...)))
    pre = _staged(name, part)
    checks && _check_primed_names(_check_name_categories(_check_reserved_names(pre)))
    return _wrap_payload(name, nothing, part)
end

# A Robin coefficient α or β that is an expression of parameters (`(g1 + g2) * c(t, 0, y) -
# Differential(x)(c(t, 0, y)) ~ g` in a coupled PDESystem's conditions) is one value at every
# site; the field compiler binds a coefficient that is a number, a parameter or a number times
# one, so the expression becomes a computed parameter of its face, `c_x_low_α = g1 + g2`, read
# only and derived again after every write
function _robin_slots(part::PottsPart)
    taken = Set{Symbol}(info(x).name for x in [part.parameters; part.variables] if info(x) !== nothing)
    extra = Any[]
    function slot(c, base)
        (_isnumber(c) || _robin_simple(_unwrap(c))) && return c
        # (a coefficient that reads the coordinates or the time varies by site: LatticePDE
        # lowers it into a value field)
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
            # the slot holds β, the coefficient of the outward ∂c/∂n: on a low face
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
        bcs = Equation[bcs...])
end
# the terms of a condition's left side: the coefficient of each face read (`c(t, 0, y)`,
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
# A Robin coefficient of a condition reads the parameters, the coordinates and the time
# (one that varies by site or in time is a value field); one that reads a field is
# refused in the model's words (the condition would be another equation)
function _check_robin_coefs(eq, N = 2)
    _, cores, coefs = _face_terms(eq)
    # a field or site variable as the PDESystem writes it, `u(t, x, y)` (the model's `u(t)`)
    args = join(("t", ("x", "y", "z")[1:N]...), ", ")
    pde(s) = replace(_builtin_text(s), r"\b(\w+)\(t\)" => SubstitutionString("\\1($args)"))
    function refuse(c, what)
        throw(
            PottsCompileError(
                string(
                    "the Robin coefficient `", pde(string(c)), "` reads `", what,
            "`; a Robin coefficient α or β is an expression of numbers, parameters, the coordinates `x`, `y`, `z` ",
            "and the time `t`")))
    end
    for c in coefs
        # a field read at a point (`u(t, 0, y)`), named as written (its arguments are no leaves)
        at = Ref{Any}(nothing)
        function walk(y)
            y = _unwrap(y)
            y isa SymbolicUtils.BasicSymbolic && iscall(y) || return nothing
            _is_field_at(operation(y)) ? (at[] === nothing && (at[] = y)) : foreach(walk, arguments(y))
            return nothing
        end
        walk(c)
        at[] === nothing || refuse(c, _builtin_text(string(at[])))
        for y in _param_leaves(c)
            j = info(y)
            j !== nothing && (j.role === :param || (j.role === :builtin && j.name in (:time, :mcs))) && continue
            j === nothing && _coordinate(y) && continue
            read_name = if j === nothing
                string(y)
            elseif j.role in (:field, :site)
                "$(j.name)($args)"
            else
                string(j.name)
            end
            refuse(c, read_name)
        end
    end
    return nothing
end
# a coefficient the field compiler binds as it is: a parameter, or a number times one
function _robin_simple(u)
    return (j = info(u); j !== nothing && j.role === :param) ||
        (iscall(u) && operation(u) === (*) && count(y -> (j = info(y); j !== nothing && j.role === :param), arguments(u)) == 1 &&
         all(y -> (j = info(y); j !== nothing && j.role === :param) || _isnumber(y) ||
                      (SymbolicUtils.isconst(_unwrap(y)) && SymbolicUtils.unwrap_const(_unwrap(y)) isa Real), arguments(u)))
end
# the face read of a condition's term, `c(t, 0, y)` or `Differential(x)(c(t, 0, y))`
function _robin_core(f)
    u = _unwrap(f)
    return iscall(u) && (_is_field_at(operation(u)) ||
        (operation(u) isa Differential && (a = _unwrap(arguments(u)[1]); iscall(a) && _is_field_at(operation(a)))))
end
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
# The fields stay out of it: an MTK `System` has one independent variable, the time, so
# a field equation there would be a scalar ODE with free spatial symbols. The field variables
# and every field equation (a rate, a map, a steady row, an aux field `K ~ rhs`, and any
# equation with a raw spatial derivative) are in the model's PDESystem
# (`Potts.fields`) only.
_is_field_variable(x) = (i = info(x); i !== nothing && i.role === :field)
function _inner_system(sys::PottsSystem)
    function spatial(eq)
        u = _unwrap(eq.rhs)
        found = Ref(false)
        _walk_all(y -> iscall(y) && operation(y) isa Differential && !isequal(operation(y).x, _unwrap(t)) &&
            (found[] = true), u)
        return found[]
    end
    of_field(eq) = (f = _field_lhs(eq, sys); f !== nothing && (f[1] === nothing || _is_field_variable(f[1])))
    eqs = [eq for eq in _p(sys, :equations) if !spatial(eq) && !of_field(eq)]
    # a field the remaining equations read (`integral(c)` in a cell equation) is an input of
    # the System, MTK's form of a value set from outside: it compiles with `inputs` given
    read = Set{Symbol}()
    note(y) = (_is_field_variable(y) && push!(read, info(y).name); nothing)
    for eq in Iterators.flatten((eqs, _p(sys, :observed)))
        _walk_all(note, _unwrap(eq.lhs))
        _walk_all(note, _unwrap(eq.rhs))
    end
    vars = Any[x for x in _p(sys, :variables) if !_is_field_variable(x)]
    for x in _p(sys, :variables)
        _is_field_variable(x) && info(x).name in read || continue
        push!(vars, SymbolicUtils.setmetadata(_unwrap(x), ModelingToolkitBase.VariableInput, true))
    end
    # each parameter's value (its declared default, or the keyword that overrides it) is an
    # initial condition, as `@mtkmodel` writes a parameter's default, so MTK and
    # SymbolicIndexingInterface see it. A computed parameter (a default that is an expression
    # of others, read-only) is left out: as an initial condition MTK would solve for it, and as
    # an MTK binding it would leave `parameters(sys)`
    values = Dict{Any, Any}()
    for p in _p(sys, :parameters)
        i = info(p)
        i === nothing || i.default === nothing || _is_symbolic(i.default) || (values[_unwrap(p)] = i.default)
    end
    return ModelingToolkitBase.System(
        eqs, _unwrap(t), vars, _p(sys, :parameters);
        name = nameof(sys), observed = _p(sys, :observed), initialization_eqs = _p(sys, :initialization_eqs),
        initial_conditions = values, systems = _component_systems(_p(sys, :components)),
        checks = ModelingToolkitBase.CheckComponents
    )
end

# The compile pipeline and `extend` read the payload only. A model whose inner System
# holds more than its payload builds (a `compose` result, a `Potts.wrap_system` of a hand-built
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

"""`wrap_system(name, …)` of the inner System that `part` builds (marked as built from it)."""
function _wrap_payload(name::Symbol, fields, part::PottsPart)
    token = Ref{Any}(nothing)
    inner = SymbolicUtils.setmetadata(_inner_system(_staged(name, part)), _BuiltFrom, (part, token))
    w = wrap_system(name, inner, fields, part)
    token[] = getfield(w, :inner)       # after `wrap_system`, which adds metadata of its own
    return w
end

# whether `sys` carries a PDESystem that its payload does not build (a hand-wrapped one)
function _foreign_fields(sys::PottsSystem)
    f = _stored_fields(sys)
    return f !== nothing && get(_p(sys, :metadata), _FieldsFrom, nothing) != _pde_digest(f)
end

function _built_from_part(sys::PottsSystem)
    I = getfield(sys, :inner)
    m = SymbolicUtils.getmetadata(I, _BuiltFrom, nothing)
    return m isa Tuple && m[1] === getfield(sys, :part) && m[2][] === I
end

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
        # the payload writes each parameter's value as an initial condition: a hand-built
        # System that leaves them out holds nothing the payload cannot build (one that gives
        # another value does: that entry is extra)
        label == "initial conditions" && isempty(extra) && continue
        push!(diff, "$label not in the payload: " * (isempty(extra) ? "(the payload's differ)" : join(first(extra, 5), ", ")))
    end
    return diff
end

"""
    _lower_inner(sys, what) -> PottsSystem

`sys` itself when its inner System is the one its payload builds; otherwise the model rebuilt
from its payload with every undeclared subsystem of the inner System's hierarchy as a
model-scope component (components rebuilt from `compose`). An
`ArgumentError` when the inner System holds anything else, or a component has inputs (field
bindings are not compiled into components).
"""
function _lower_inner(sys::PottsSystem, what::AbstractString)
    _built_from_part(sys) && return sys
    E = what == "mtkcompile" ? PottsCompileError : ArgumentError
    I, part = getfield(sys, :inner), getfield(sys, :part)
    M = ModelingToolkitBase
    P = something(M.get_parent(I), I)
    declared = Set(c.name for c in part.components if c isa ComponentSpec)
    extra = ComponentSpec[]
    subs = M.get_systems(P)
    for n in unique(nameof.(subs))
        count(s -> nameof(s) === n, subs) > 1 && throw(
            E(
                "$what: `$(nameof(sys))` has two components named " *
                    "`$n`; give each component its own name"
            )
        )
    end
    for s in subs
        nameof(s) in declared && continue          # an `@components` system of the payload
        # a subsystem built from a Potts payload (`get_parent(Potts.inner(m))` wrapped by hand)
        # carries what a `compose` component may not; check it the same way
        m = SymbolicUtils.getmetadata(s, _BuiltFrom, nothing)
        m isa Tuple && m[1] isa PottsPart && _check_component_part(nameof(s), m[1], what, E)
        for q in M.parameters(s)
            i = info(q)
            i !== nothing && i.role === :kindtable && throw(
                E(
                "$what: component `$(nameof(s))` of `$(nameof(sys))` has the kind table `$q`; a composed component " *
                "is compiled once for the model, whose parameters are scalars: declare the table in the model"))
        end
        for u in M.unknowns(s)
            M.isinput(u) && throw(
                E(
                    "$what: component `$(nameof(s))` of `$(nameof(sys))` has the input " *
                        "`$u`; a component's inputs (field bindings) are not compiled (bind the " *
                        "value with `@equations $(nameof(s)).p ~ …` on a parameter instead)"
                )
            )
            # a composed component is one instance for the model: a quantity declared per site,
            # cell, edge or field would silently become one model-wide value
            i = info(u)
            i !== nothing && i.role in SCOPES && i.role !== :model &&
                throw(
                E(
                    "$what: component `$(nameof(s))` of `$(nameof(sys))` declares `$u` per $(i.role); " *
                        "a composed component is compiled once for the model (model scope), so " *
                        "per-$(i.role) quantities are not supported in it: declare them in the model, " *
                        "or use `@components cells(…) $(nameof(s)) = system` for a per-cell MTK system"
                )
            )
        end
        # what a composed component's equations read: its own and model quantities only. A
        # population or site fold, a built-in or another scope's quantity is refused (a fold in a
        # composed component is not lowered by the CPM compiler)
        for eq in [M.equations(s); M.observed(s)], side in (eq.lhs, eq.rhs)
            _walk_all(side) do y
                i = info(y)
                (i === nothing || i.role in (:model, :param)) && return
                read_kind = i.role === :bound_cell || i.role === :bound_site ? "population fold" : i.role
                throw(
                    E(
                        "$what: component `$(nameof(s))` of `$(nameof(sys))` reads `$(i.name)` (a $(read_kind)); a composed component reads its own and model " *
                            "quantities only: write the expression in the model (`@equations $(nameof(s)).p ~ …` on a parameter)"
                    )
                )
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
        # fields, moved into the payload under their own names
        _foreign_fields(sys) || return w
        pde_part = try
            _with_pde(w, getfield(w, :part), getfield(sys, :fields), nothing, what)
        catch e
            e isa ArgumentError && E !== ArgumentError && throw(E(e.msg))
            rethrow()
        end
        return _wrap_payload(nameof(sys), nothing, pde_part)
    end
    throw(
        E(
            "$what: the inner System of `$(nameof(sys))` holds content its Potts payload cannot build (" *
                join(diff, "; ") * "). Subsystems are compiled as model-scope components; top-level " *
                "quantities, equations and values of a hand-built System are not: declare them in " *
                "`@potts_model` or `PottsSystem(; …)`, or compose the hand-built System as a component"
        )
    )
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
    compose(p::PottsSystem, cs::AbstractArray; name = nameof(p))
    compose(p::PottsSystem, cs...; name = nameof(p))

MTK's `compose` for a Potts model: `p` with the systems `cs` as components. A component is a
[`Potts.component`](@ref), or an MTK `System` or `PDESystem` itself (taken as
`Potts.component(nameof(c), c, p)`). The inner Systems are composed (MTK's `compose` on
the unflattened hierarchies, `get_parent`), completed and wrapped, so `sys.c.x` is the
quantity `c₊x` of component `c` and nested compositions match composing the raw Systems.
The `PDESystem`s are merged; the payload is `p`'s, with each component's field bindings
under its name. A component's own CPM statements (energies, drives, …) are an
`ArgumentError`: components carry quantities, equations and bindings. `mtkcompile`,
`PottsProblem` and `extend` compile each component as a model-scope component
(`@components model c = system`: its unknowns are model variables `c₊x`, its parameters model
parameters `c₊k`). An `ArgumentError` names what a component cannot carry: inputs (field
bindings are not compiled into components), quantities per site, cell, edge or field, kind
tables, relations, kind classes, obstacle kinds, a schedule, field conditions, its own `@components`,
kinds or a lattice other than the model's, or a name the model already uses (a component or a
quantity). A component's PDESystem ([`Potts.component`](@ref) of a `PDESystem`) joins the
model's fields: its fields, parameters, equations and conditions become the model's, named
`c₊x`, and the result is rebuilt from its payload. A component's sweep and structural keywords are its constructor's
and are not read. Units and guesses of a component's quantities are kept; their types are not
(a component's unknowns and parameters become Real model quantities). Build a component with
[`Potts.component`](@ref): `compose(p, [Potts.component(:rn, Catalyst.ode_model(complete(rn)), p)])`
composes a Catalyst reaction network. With no components, `compose` returns `p`, as MTK's does.
MTK's `compose` of a plain `System` with a Potts model as its component is an `ArgumentError`:
compose the MTK system into the Potts model instead.
"""
function ModelingToolkitBase.compose(p::PottsSystem, systems::AbstractArray; name = nameof(p))
    isempty(systems) && return p
    name isa Symbol || throw(ArgumentError("compose: `name` is a Symbol; got $(repr(name))"))
    cs = Tuple(_as_component(c, p) for c in systems)
    taken = Set{Symbol}(nameof.(_MTKB.get_systems(something(ModelingToolkitBase.get_parent(inner(p)), inner(p)))))
    quantities = Set{Symbol}(Symbol(SymbolicIndexingInterface.getname(x)) for x in
                             [ModelingToolkitBase.unknowns(inner(p)); ModelingToolkitBase.parameters(inner(p))])
    for c in cs
        nameof(c) in taken && throw(
            ArgumentError(
                "compose: `$(nameof(p))` already has a component named " *
                                                  "`$(nameof(c))`; give each component its own name"))
        nameof(c) in quantities && throw(
            ArgumentError(
                "compose: `$(nameof(p))` has a quantity named " *
                                                       "`$(nameof(c))`; give the component another name"))
        push!(taken, nameof(c))
    end
    # a component's PDESystem joins the payload as fields; its System, when it has
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
    return wrap_system(name, complete(sys; allow_parameter_eqs = true), _merge_fields(name, p, cs), _merge_part(p, cs))
end

# a component of `p` for `compose`: a Potts model as it is, an MTK system as `Potts.component`
_as_component(c::PottsSystem, ::PottsSystem) = c
_as_component(c::Union{ModelingToolkitBase.System, ModelingToolkitBase.PDESystem}, p::PottsSystem) = component(nameof(c), c, p)
function _as_component(c, p::PottsSystem)
    throw(
            ArgumentError(
                "compose: a component of the Potts model `$(nameof(p))` is a Potts model, an MTK `System` or `PDESystem`, " *
                    "or a `Potts.component`; got a $(typeof(c))"
            )
        )
end

# MTK's `compose` with a plain System around a Potts model: a Potts model is not a subsystem
# of an MTK System (its lattice and sweep have no place there)
function ModelingToolkitBase.compose(s::ModelingToolkitBase.System, ::AbstractArray{<:PottsSystem}; kw...)
    throw(
            ArgumentError(
                "compose($(nameof(s)), …): a Potts model is not a component of an MTK System; compose the other way round, " *
                    "`compose(model, [$(nameof(s))])`, or declare `$(nameof(s))` in the model with `@components`"
            )
        )
end
# the same with the Potts model among other systems (`compose(s, [other, model])`,
# `System(…; systems = [model])`): MTK converts each subsystem to a `System`
function Base.convert(::Type{ModelingToolkitBase.System}, p::PottsSystem)
    throw(
            ArgumentError(
                "the Potts model `$(nameof(p))` is not a component of an MTK System; compose the other way round, " *
                    "`compose($(nameof(p)), [system])`, or declare the system in the model with `@components`"
            )
        )
end

# whether the inner System `I` holds nothing (a `Potts.component` of a PDESystem)
function _empty_system(I)
    M = ModelingToolkitBase
    P = something(M.get_parent(I), I)
    return isempty(M.unknowns(I)) && isempty(M.parameters(I)) && isempty(M.equations(I)) &&
        isempty(M.observed(I)) && isempty(M.get_systems(P))
end

# `p` with the PDESystem of each component of `pdes` as fields, named `component₊n`, rebuilt
# from its payload (its own composed components lowered first, as `mtkcompile` does)
function _with_pde_components(p::PottsSystem, pdes, name::Symbol)
    base = _lower_inner(p, "compose")
    part = getfield(base, :part)
    for c in pdes
        _check_component_like(p, c)
        part = _with_pde(base, part, _stored_fields(c), nameof(c), "compose: component `$(nameof(c))`")
    end
    return _wrap_payload(name, nothing, part)
end

function _merge_fields(name, p, cs)
    fs = [f for f in (_stored_fields(p), map(_stored_fields, cs)...) if f !== nothing]
    isempty(fs) && return nothing
    merged(get) = unique(reduce(vcat, [collect(get(f)) for f in fs]))
    # the merge keeps the six stored fields exactly; `initial_conditions` are merged (one value
    # per key), and the parts a merge cannot keep (subsystems, analytic solutions) are refused,
    # never dropped. `analytic` and `analytic_func` are read as properties (`PDESystem`'s
    # `getproperty`); switch to `get_analytic` once a ModelingToolkitBase release has it
    # (SciML/ModelingToolkit.jl#5420)
    for f in fs
        isempty(_MTKB.get_systems(f)) && f.analytic === nothing && f.analytic_func === nothing ||
            throw(
            ArgumentError(
                "compose: the PDESystem `$(nameof(f))` has subsystems or analytic solutions, " *
                                "which a composed model's PDESystem does not carry; leave them out"))
    end
    ic = Dict{Any, Any}()
    for f in fs, (k, v) in _MTKB.get_initial_conditions(f)
        haskey(ic, k) && !isequal(ic[k], v) && throw(ArgumentError(
                "compose: two PDESystems give `$k` different initial conditions ($(ic[k]) and $v)"
            )
        )
        ic[k] = v
    end
    ps(f) = (x = _MTKB.get_ps(f); x isa SciMLBase.NullParameters ? Any[] : x)
    return ModelingToolkitBase.PDESystem(
        merged(f -> _MTKB.get_eqs(f)), merged(f -> _MTKB.get_bcs(f)), merged(f -> _MTKB.get_domain(f)), merged(f -> _MTKB.get_ivs(f)),
        merged(f -> _MTKB.get_dvs(f)), merged(ps); name, initial_conditions = ic
    )
end

const _STATEMENT_FIELDS = (:energies, :drives, :constraints, :updates, :divisions, :converts, :relationships, :link_rules,
    :discrete)

# What a composed component (a `compose` component, or a subsystem built from a Potts
# payload) cannot carry into the model, refused by name and never dropped: CPM statements; its
# relations, kind classes, obstacle kinds, schedule and boundary conditions; its own
# `@components` (a per-cell one would become model-wide; compose components directly).
function _check_component_part(name::Symbol, part::PottsPart, what, E::Type{<:Exception} = ArgumentError)
    for f in _STATEMENT_FIELDS
        isempty(getfield(part, f)) || throw(
            E(
                "$what: component `$name` has $f; a component carries " *
                    "quantities, equations and field bindings, not CPM statements " *
                    "(build a component of a model with " *
                    "`Potts.component($(repr(name)), system, model)`)"
            )
        )
    end
    for (f, label) in ((:relations, "relations"), (:kind_classes, "kind classes"), (:frozen_kinds, "obstacle kinds"),
            (:schedule, "a @schedule"), (:bcs, "field conditions"), (:components, "@components"))
        isempty(getfield(part, f)) && continue
        note = if f === :components
            " (compose its components into the model directly, " *
                "or declare them in the model with `@components`)"
        else
            ""
        end
        throw(
            E(
                "$what: component `$name` has $label; a composed " *
                    "component carries quantities, equations and field bindings only" * note
            )
        )
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
    _check_component_part(nameof(c), getfield(c, :part), "compose")
    # a component's folds read kinds by number and the lattice's sites: they must be the model's
    _p(c, :kinds) == _p(p, :kinds) || throw(ArgumentError(
            "compose: component `$(nameof(c))` has the kinds $(_p(c, :kinds)), the model `$(nameof(p))` " *
        "$(_p(p, :kinds)); a component is built with the model's kinds (`Potts.component(name, system, model)`)"))
    _same_lattice(_p(c, :lattice), _p(p, :lattice)) || throw(ArgumentError(
            "compose: component `$(nameof(c))` has another lattice than the model `$(nameof(p))`; a component is " *
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
function _endpoint_message(what, k)
    return "$what `$k`: `$k` is reserved (`a` and `b` are the link endpoints in edge terms and " *
        "link rules); choose another name, e.g. `$(k)₀`"
end

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

"""
    Potts.declared_parameters(sys::PottsSystem)

The parameter symbols of a model (scalars and kind tables), as declared. MTK's
`parameters(sys)` lists the parameters of the compiled system.
"""
declared_parameters(sys::PottsSystem) = _p(sys, :parameters)
"""
    Potts.declared_variables(sys::PottsSystem)

The scoped state variables of a model, as declared.
"""
declared_variables(sys::PottsSystem) = _p(sys, :variables)

"""
    Potts.lattice(sys::PottsSystem)

The lattice of a model (its `LatticeSpec`: `dims`, neighborhood, boundary). `sys.lattice`
is not a field read: `sys.<name>` is a declared symbol.
"""
lattice(sys::PottsSystem) = _p(sys, :lattice)

# --- The container's owned methods; a test lists them. Each accessor
# forwards to the complete inner System. `nameof` is MTK's generic method on the `name`
# field. MTKBase's own SymbolicIndexingInterface methods on `::AbstractSystem` would read the
# container's (absent) index cache, so the five SII methods below route them to the inner
# System; `symbolic_container` covers the rest of the interface.
const _MTKB = ModelingToolkitBase
const _SII = SymbolicIndexingInterface

# the model's field variable named `n` (wrapped, as `getproperty` of a System gives), or nothing
function _field_named(s::PottsSystem, n::Symbol)
    for x in _p(s, :variables)
        _is_field_variable(x) && info(x).name === n && return Symbolics.wrap(x)
    end
    return nothing
end

# a field variable is the model's (`Potts.fields`), not the inner System's
function Base.getproperty(s::PottsSystem, n::Symbol)
    f = _field_named(s, n)
    return f === nothing ? getproperty(getfield(s, :inner), n) : f
end
function Base.propertynames(s::PottsSystem)
    return (propertynames(getfield(s, :inner))..., (info(x).name for x in _p(s, :variables) if _is_field_variable(x))...)
end
_MTKB.equations(s::PottsSystem) = _MTKB.equations(getfield(s, :inner))
_MTKB.unknowns(s::PottsSystem) = _MTKB.unknowns(getfield(s, :inner))
_MTKB.parameters(s::PottsSystem; kw...) = _MTKB.parameters(getfield(s, :inner); kw...)
_MTKB.observed(s::PottsSystem) = _MTKB.observed(getfield(s, :inner))
_MTKB.initial_conditions(s::PottsSystem) = _MTKB.initial_conditions(getfield(s, :inner))
_MTKB.bindings(s::PottsSystem) = _MTKB.bindings(getfield(s, :inner))
# the scalar extension point (MTK's `independent_variables` wraps it)
_MTKB.independent_variable(s::PottsSystem) = _MTKB.get_iv(getfield(s, :inner))
_MTKB.guesses(s::PottsSystem) = _MTKB.guesses(getfield(s, :inner))
_MTKB.inputs(s::PottsSystem) = _MTKB.inputs(getfield(s, :inner))
_MTKB.outputs(s::PottsSystem) = _MTKB.outputs(getfield(s, :inner))
# A model is complete when it is built: its inner System is complete, and `sys.x` is the
# declared symbol, never namespaced (MTK's `does_namespacing` is `!iscomplete` for a system
# without a `namespacing` field). `complete` returns it unchanged.
_MTKB.iscomplete(::PottsSystem) = true
_MTKB.complete(s::PottsSystem; kw...) = (_refuse_complete_keywords(s, kw); s)
_MTKB.get_iv(s::PottsSystem) = _MTKB.get_iv(getfield(s, :inner))

# MTK's `complete` keywords (`split`, `flatten`, …) shape a System being completed; a Potts
# model is complete when it is built, so they are refused by name
function _refuse_complete_keywords(sys, kw)
    isempty(kw) && return nothing
    throw(
        ArgumentError(
            string(
                "complete(", nameof(sys), "; ", join(keys(kw), ", "), "): a Potts model is complete when it is built ",
                "and takes no `complete` keywords; MTK's keywords apply to an MTK System: `complete(Potts.inner(sys); …)`"
            )
        )
    )
end
# MTK's metadata of a model is its inner System's (`Potts.PottsSweepSpec` among it)
SymbolicUtils.getmetadata(s::PottsSystem, k::DataType, default) = SymbolicUtils.getmetadata(getfield(s, :inner), k, default)
SymbolicUtils.hasmetadata(s::PottsSystem, k::DataType) = SymbolicUtils.hasmetadata(getfield(s, :inner), k)
function SymbolicUtils.setmetadata(s::PottsSystem, k::DataType, v)
    return _with_inner(s, getfield(s, :name), SymbolicUtils.setmetadata(getfield(s, :inner), k, v), getfield(s, :fields))
end
# MTK's description of a model is its inner System's
_MTKB.description(s::PottsSystem) = _MTKB.description(getfield(s, :inner))

# `@description` and `@metadata` of `@potts_model` (MTK's `@mtkmodel` sections): the model
# with its inner System's description and metadata set (`metadata`: `Key => value` pairs, each
# `Key` a type, as in MTK)
function _describe(s::PottsSystem, description, metadata)
    for (k, v) in metadata
        k isa DataType || throw(
            ArgumentError("@metadata of $(nameof(s)): the key `$k` is not a type; MTK's metadata keys are types (`struct MyKey end`)")
        )
        s = SymbolicUtils.setmetadata(s, k, v)
    end
    description === nothing && return s
    description isa AbstractString || throw(
        ArgumentError("@description of $(nameof(s)): give a string; got $(repr(description))")
    )
    I = ConstructionBase.setproperties(getfield(s, :inner), (; description = String(description)))
    return _with_inner(s, getfield(s, :name), I, getfield(s, :fields))
end

# `s` with another name, inner System or PDESystem and the same payload. A model built from its
# payload stays marked as such (`_built_from_part`), so `mtkcompile` keeps the new inner System
# (and its metadata) as it is.
function _with_inner(s::PottsSystem, name::Symbol, I::ModelingToolkitBase.System, fields)
    if _built_from_part(s)
        token = Ref{Any}(nothing)
        I = SymbolicUtils.setmetadata(I, _BuiltFrom, (getfield(s, :part), token))
        token[] = I
    end
    return PottsSystem(_Wrap(), name, I, fields, getfield(s, :part))
end

"""
    rename(sys::PottsSystem, name::Symbol)

MTK's `rename`: the model under another name (its inner System and its PDESystem renamed with
it). `@named models[1:n] = Model(…)` renames this way.
"""
function Symbolics.rename(s::PottsSystem, name::Symbol)
    f = getfield(s, :fields)
    return _with_inner(s, name, Symbolics.rename(getfield(s, :inner), name), f === nothing ? nothing : _renamed_pde(f, name))
end

# the PDESystem `f` under `name`, every stored field kept (MTKBase's `rename` of a PDESystem,
# `@set`, fails on its `nothing` metadata). `analytic` and `analytic_func` are read as
# properties (`PDESystem`'s `getproperty`); switch to `get_analytic` once a ModelingToolkitBase
# release has it (SciML/ModelingToolkit.jl#5420).
function _renamed_pde(f::ModelingToolkitBase.PDESystem, name::Symbol)
    return ModelingToolkitBase.PDESystem(
            _MTKB.get_eqs(f), _MTKB.get_bcs(f), _MTKB.get_domain(f), _MTKB.get_ivs(f), _MTKB.get_dvs(f), _MTKB.get_ps(f);
            name, initial_conditions = _MTKB.get_initial_conditions(f), systems = _MTKB.get_systems(f),
            connector_type = _MTKB.get_connector_type(f), metadata = _MTKB.get_metadata(f), analytic = f.analytic,
            analytic_func = f.analytic_func, gui_metadata = _MTKB.get_gui_metadata(f),
            description = _MTKB.get_description(f), checks = false
        )
end

"""
    PottsSystem(name, inner, fields, part; checks = false)

The model `Potts.wrap_system(nameof(inner), inner, fields, part)` renamed `name`: MTK's rebuild of a
system from its fields (`@set sys.name = name`, which `rename` and `@named models[1:n]` use).
Only the name may change; build a model with `@potts_model`, the keyword constructor or
[`Potts.wrap_system`](@ref).
"""
function PottsSystem(
        name::Symbol, I::ModelingToolkitBase.System, fields::Union{Nothing, ModelingToolkitBase.PDESystem},
        part::PottsPart; checks = false
    )
    s = PottsSystem(_Wrap(), nameof(I), I, fields, part)
    return name === nameof(I) ? s : Symbolics.rename(s, name)
end
# no subsystems: the inner System is flattened (a Potts model has no subsystem hierarchy),
# so MTK's hierarchy walkers (`full_equations`, `hierarchy`, the event accessors,
# `propertynames`) see a leaf
_MTKB.get_systems(::PottsSystem) = _MTKB.AbstractSystem[]
_MTKB.full_equations(s::PottsSystem; kw...) = _MTKB.full_equations(getfield(s, :inner); kw...)
_SII.symbolic_container(s::PottsSystem) = getfield(s, :inner)
_SII.parameter_index(s::PottsSystem, sym) = _SII.parameter_index(getfield(s, :inner), sym)
_SII.parameter_index(s::PottsSystem, sym::Symbol) = _SII.parameter_index(getfield(s, :inner), sym)
_SII.is_parameter(s::PottsSystem, i::_MTKB.ParameterIndex) = _SII.is_parameter(getfield(s, :inner), i)
_SII.observed(s::PottsSystem, sym; kw...) = _SII.observed(getfield(s, :inner), sym; kw...)
_SII.parameter_observed(s::PottsSystem, sym) = _SII.parameter_observed(getfield(s, :inner), sym)
# (+ `Base.show(io, ::MIME"text/plain", ::PottsSystem)` below)

# --- Refusals: SciMLBase's `{iip}` constructors accept any object as `f`, so
# without these `ODEProblem{true}(sys, …)` and nine other routes return a problem that fails
# only at `solve`. Every problem constructor MTKBase extends, plus `JumpProblem`, in the plain,
# `{iip}` and `{iip, spec}` forms, on the system argument alone (and the disambiguations below).
const _REFUSED_PROBLEMS = (:ODEProblem, :NonlinearProblem, :SteadyStateProblem, :SDEProblem, :DAEProblem, :DDEProblem,
    :SDDEProblem, :BVProblem, :DiscreteProblem, :ImplicitDiscreteProblem, :NonlinearLeastSquaresProblem, :LinearProblem,
    :IntervalNonlinearProblem, :HomotopyProblem, :OptimizationProblem)
function _problem_msg(f)
    return "$f: a Potts model is not an ODE or jump system; build its problem with `PottsProblem(sys, op, tspan)` " *
        "and solve it with a CPM algorithm (for the cell/model ODE alone, use `Potts.inner(sys)`)"
end
for (M, n) in ((:JumpProcesses, :JumpProblem), ((:SciMLBase, n) for n in _REFUSED_PROBLEMS)...)
    P = Expr(:., M, QuoteNode(n))
    msg = String(n)
    n === :JumpProblem || @eval $P(::PottsSystem, args...; kw...) = throw(ArgumentError(_problem_msg($msg)))
    @eval begin
        $P{iip}(::PottsSystem, args...; kw...) where {iip} = throw(ArgumentError(_problem_msg($msg)))
        $P{iip, spec}(::PottsSystem, args...; kw...) where {iip, spec} = throw(ArgumentError(_problem_msg($msg)))
    end
end
# Two disambiguations. SciMLBase's own `ODEProblem{iip, FunctionWrapperSpecialize}(f, u0,
# tspan[, p])` meets the `{iip, spec}` refusal. JumpProcesses' `JumpProblem(prob, jumps…)` and
# `JumpProblem(prob, aggregator, jumps…)` take any `prob`, so the plain `JumpProblem` refusals
# are typed where a jump set, a jump or an aggregator never is: MTK's `JumpProblem(sys, op,
# tspan)` with `tspan` a tuple, `nothing` or a vector, and `JumpProblem(sys, op)` with `op` an
# operating point (a collection, a pair, a number or `nothing`). One method per type, for both
# system types (compose.jl).
function SciMLBase.ODEProblem{iip, SciMLBase.FunctionWrapperSpecialize}(::PottsSystem, args...; kw...) where {iip}
    throw(ArgumentError(_problem_msg("ODEProblem")))
end
const _JUMP_TSPANS = (:Tuple, :Nothing, :AbstractVector)
const _JUMP_OPS = (:AbstractArray, :AbstractDict, :NamedTuple, :Tuple, :Pair, :Number, :Nothing)
for T in _JUMP_TSPANS
    @eval JumpProcesses.JumpProblem(::PottsSystem, op, tspan::$T, args...; kw...) = throw(ArgumentError(_problem_msg("JumpProblem")))
end
for T in _JUMP_OPS
    @eval JumpProcesses.JumpProblem(::PottsSystem, op::$T; kw...) = throw(ArgumentError(_problem_msg("JumpProblem")))
end
# MTK's `extend` with a Potts model on one side and another system on the other (D-039): a
# clear refusal naming the ways that work, not MTK's rebuild of the container.
function _extend_msg(a, b)
    return "extend($(nameof(a)), $(nameof(b))): a Potts model extends only a Potts model " *
        "(`extend(sys, base)` with both Potts models); add an MTK System to a Potts model as " *
        "`@components`, or with `compose(model, [system])`"
end
function ModelingToolkitBase.extend(a::PottsSystem, b::ModelingToolkitBase.AbstractSystem; kw...)
    throw(ArgumentError(_extend_msg(a, b)))
end
function ModelingToolkitBase.extend(a::ModelingToolkitBase.AbstractSystem, b::PottsSystem; kw...)
    throw(ArgumentError(_extend_msg(a, b)))
end

# --- Keys namespaced by the model itself (D-137). `sys.x` of an uncompleted `sys`
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
function _declared_quantities(sys::PottsSystem)
    return Dict{Symbol, Any}(i.name => _unwrap(x) for x in Iterators.flatten((
        _p(sys, :parameters), _p(sys, :variables), (o.lhs for o in _p(sys, :observed))))
                                                               for i in (info(x),) if i !== nothing)
end
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

# A coupled PDESystem's own variable, `c` or `c(t, x, y)` as its author wrote it (one of the
# PDESystem's dependent variables, or its function), names the model's field `c`: the field
# variable, or `nothing` for any other key (a foreign variable that only shares the name too)
function _pde_variable_field(sys::PottsSystem, u, n)
    n isa Symbol || return nothing
    f = _field_named(sys, n)
    f === nothing && return nothing
    v = _unwrap(f)
    isequal(u, v) && return nothing
    pde = _stored_fields(sys)
    pde === nothing && return nothing
    any(d -> _is_variable_of(u, _unwrap(d)), _MTKB.get_dvs(pde)) || return nothing
    return v
end
_is_variable_of(u, d) = isequal(u, d) || (iscall(d) && isequal(u, operation(d)))

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
        f = _pde_variable_field(sys, u, n)
        f === nothing || return f
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

function Base.show(io::IO, sys::PottsSystem)
    return print(
            io, "PottsSystem(", getfield(sys, :name), ", ", join(_p(sys, :lattice).dims, "×"), ", ",
            _count_string(length(_p(sys, :kinds)) - 1, "cell kind"), ")"
        )
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
    f = _stored_fields(sys)    # the stored slot (not built here)
    f === nothing || print(
        io, "\n  fields: PDESystem with ", _count_string(length(_MTKB.get_eqs(f)), "equation"), ", ",
        _count_string(length(_MTKB.get_bcs(f)), "bc"), ", ", _count_string(length(_MTKB.get_dvs(f)), "dependent variable")
    )
    return nothing
end

# a parameter with its MTK description: `Dc ("diffusion of c")`
function _param_show(p)
    d = SymbolicUtils.getmetadata(_unwrap(p), ModelingToolkitBase.VariableDescription, nothing)
    return d === nothing ? string(info(p).name) : string(info(p).name, " (", repr(d), ")")
end

# with the model's kind names (`kinds`, the medium first), kinds print as authored
_domain_string(d::CellDomain, kinds = nothing) = isempty(d.kinds) ? "cells" : "cells(" * _kind_list(d.kinds, kinds) * ")"
_domain_string(d::ClusterDomain, kinds = nothing) = isempty(d.kinds) ? "clusters" : "clusters(" * _kind_list(d.kinds, kinds) * ")"
_domain_string(d, ::Any) = _domain_string(d)
_kind_list(ks, names) = join((names !== nothing && 0 <= k < length(names) ? names[k + 1] : k for k in ks), ", ")
_domain_string(d::ContactDomain) = d.relation === :contact ? "contacts" : "contacts($(d.relation))"
_domain_string(::SiteDomain) = "sites"
_domain_string(d::EdgeDomain) = "edges($(d.relationship))"
_domain_string(d) = string(d)
