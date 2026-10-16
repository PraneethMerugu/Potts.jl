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
    schedule::Vector{Symbol} = Symbol[]        # `@schedule` as listed; empty: the default phase order
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
[`Potts.compose`](@ref) or a `Potts.wrap` of a hand-built System answers `sys.c.x` and MTK's
accessors, but it cannot yet be compiled, solved or extended (an `ArgumentError`; cutover C9).

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
    Potts.fields(sys::PottsSystem)

The `PDESystem` of a model's fields, or `nothing`.
"""
fields(sys::PottsSystem) = getfield(sys, :fields)

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
    part = PottsPart(; kw...)
    pre = _staged(name, part)
    checks && _check_primed_names(_check_name_categories(_check_reserved_names(pre)))
    return _wrap_payload(name, nothing, part)
end

# `part` under `name` with a placeholder inner System: what the construction checks, the
# compile pipeline's rewrites (`_replace`) and `_inner_system` read (they never read the inner)
_staged(name::Symbol, part::PottsPart) = PottsSystem(_Wrap(), name, _empty_inner(name), nothing, part)
_empty_inner(name) = ModelingToolkitBase.System(Equation[], _unwrap(t); name)

# The inner System of a model: its quantities, equations, observed equations and components.
# MTK's component checks run; its unit check does not (`mtkcompile` runs Potts' own, which
# names the statement: a built-in such as `volume` carries the lattice's units there).
function _inner_system(sys::PottsSystem)
    return ModelingToolkitBase.System(_p(sys, :equations), _unwrap(t), _p(sys, :variables), _p(sys, :parameters);
        name = nameof(sys), observed = _p(sys, :observed), initialization_eqs = _p(sys, :initialization_eqs),
        systems = _component_systems(_p(sys, :components)), checks = ModelingToolkitBase.CheckComponents)
end

# The compile pipeline and `Potts.extend` read the payload only (C4); the inner System of a
# model built from its payload is exactly `_inner_system` of it. A model whose inner System
# holds more (a `Potts.compose` result, a `Potts.wrap` of a hand-built System) would drop
# that content silently, so it is refused until C9 lowers composed Systems.
# metadata key on an inner System built from a payload: `(part, token)`, where the token holds
# the exact final inner System. The check below is then a comparison of identities for every
# model `@potts_model` or the keyword constructor builds (no second build). MTK's `compose`,
# `extend` and `complete` copy metadata, so a System derived from a marked one carries the
# same pair; it is a different object from `token[]` and gets the full comparison.
struct _BuiltFrom end

"""`wrap(name, …)` of the inner System that `part` builds (marked as built from it)."""
function _wrap_payload(name::Symbol, fields, part::PottsPart)
    token = Ref{Any}(nothing)
    inner = SymbolicUtils.setmetadata(_inner_system(_staged(name, part)), _BuiltFrom, (part, token))
    w = wrap(name, inner, fields, part)
    token[] = getfield(w, :inner)       # after `wrap`, which adds metadata of its own
    return w
end

function _check_inner_matches_part(sys::PottsSystem, what::AbstractString)
    I, part = getfield(sys, :inner), getfield(sys, :part)
    m = SymbolicUtils.getmetadata(I, _BuiltFrom, nothing)
    m isa Tuple && m[1] === part && m[2][] === I && return sys
    ref = complete(_inner_system(_staged(nameof(sys), part)); allow_parameter_eqs = true)
    M = ModelingToolkitBase
    names(xs) = Set(string.(collect(xs)))
    checks = ("unknowns" => M.unknowns, "equations" => M.equations, "parameters" => M.parameters,
        "observed equations" => M.observed, "initialization equations" => M.initialization_equations,
        "initial conditions" => s -> (string(k) * " => " * string(v) for (k, v) in M.initial_conditions(s)))
    diff = String[]
    for (label, f) in checks
        a, b = names(f(I)), names(f(ref))
        a == b && continue
        extra = sort!(collect(setdiff(a, b)))
        push!(diff, "$label not in the payload: " * (isempty(extra) ? "(the payload's differ)" : join(first(extra, 5), ", ")))
    end
    isempty(diff) && return sys
    throw(ArgumentError("$what: the inner System of `$(nameof(sys))` is not the one its Potts payload builds (" *
                        join(diff, "; ") * "). A model composed with `Potts.compose` or wrapped from a hand-built " *
                        "System is compiled from cutover C9 on (components rebuilt by `Potts.compose`); until then " *
                        "declare its quantities, equations and values in `@potts_model` or `PottsSystem(; …)`"))
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
`ArgumentError`: components carry quantities, equations and bindings.
"""
function compose(p::PottsSystem, cs::PottsSystem...; name::Symbol = nameof(p))
    isempty(cs) && throw(ArgumentError("Potts.compose: give at least one component"))
    un(s) = ModelingToolkitBase.toggle_namespacing(something(ModelingToolkitBase.get_parent(inner(s)), inner(s)), true)
    sys = ModelingToolkitBase.compose(un(p), [un(c) for c in cs]; name)
    return wrap(name, complete(sys; allow_parameter_eqs = true), _merge_fields(name, p, cs), _merge_part(p, cs))
end

function _merge_fields(name, p, cs)
    fs = [f for f in (fields(p), map(fields, cs)...) if f !== nothing]
    isempty(fs) && return nothing
    merged(get) = unique(reduce(vcat, [collect(get(f)) for f in fs]))
    # read with `getfield`: MTKBase has no public accessor for a PDESystem's `bcs` or
    # `domain`, and the merge keeps the six stored fields exactly (friction register, HANDOFF §2)
    return ModelingToolkitBase.PDESystem(merged(f -> getfield(f, :eqs)), merged(f -> getfield(f, :bcs)), merged(f -> getfield(f, :domain)), merged(f -> getfield(f, :ivs)),
        merged(f -> getfield(f, :dvs)), merged(f -> getfield(f, :ps)); name)
end

const _STATEMENT_FIELDS = (:energies, :drives, :constraints, :updates, :divisions, :converts, :relationships, :link_rules,
    :discrete, :boundaries)
function _merge_part(p, cs)
    bindings = copy(_p(p, :bindings))
    for c in cs
        for f in _STATEMENT_FIELDS
            isempty(_p(c, f)) || throw(ArgumentError("Potts.compose: component `$(nameof(c))` has $f; a component carries " *
                                                     "quantities, equations and field bindings, not CPM statements"))
        end
        append!(bindings, (FieldBinding([nameof(c); b.path], b.name, b.source) for b in _p(c, :bindings)))
    end
    return getfield(_replace(p; bindings), :part)
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
const _INTERNAL_SUFFIXES = ("__ode", "__tick", "__next")
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
    isempty(_p(sys, :parameters)) || println(io, "  parameters: ", join(map(p -> info(p).name, _p(sys, :parameters)), ", "))
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
    f = fields(sys)    # counts read with `getfield`, as in `_merge_fields`
    f === nothing || print(io, "\n  fields: PDESystem with ", _count_string(length(getfield(f, :eqs)), "equation"), ", ",
        _count_string(length(getfield(f, :bcs)), "bc"), ", ", _count_string(length(getfield(f, :dvs)), "dependent variable"))
end

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
