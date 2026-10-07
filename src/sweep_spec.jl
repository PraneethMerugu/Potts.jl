# The sweep's definition as an MTK-visible object (D-160, P6.0bm): `hamiltonian(sys)`,
# `drives(sys)` and the `PottsSweepSpec` metadata payload, read with MTK's own
# `getmetadata`/`hasmetadata`; and the update rules as written, `updates(sys)` (D-164).
# Descriptions only: they are derived from the system on every read, so they always
# describe the system they are read from, and they never enter the generated code or the
# fingerprint (D-137 rule 2).

"""
    Potts.hamiltonian(sys) -> AbstractVector{Pair}

The Hamiltonian of a model as written: one `domain => expr` pair per `@energy` term, in
declaration order (`@extend`/`extend` terms merged), for a `PottsSystem` (completed or not)
or a `CompiledPottsSystem` (the same terms as the model it was compiled from: as written,
before `@components` are lowered).

`domain` is the DSL domain value (`cells(k…)`, `clusters(k…)`, `contacts`, `contacts(r)`,
`sites`, `edges(r)`); `expr` is the term's energy density (a number for a constant term), a Symbolics expression over the
declared parameters and variables (the declared symbols, as `complete(sys).x`) and the DSL
built-ins (`volume`, `kind′`, …). The energy of a state is the sum of each density over its
domain (cells of the term's kinds, unordered pairs of the relation with different owners,
…), with the conventions of `total_energy`. Drives ([`Potts.drives`](@ref)), constraints
(`ModelingToolkitBase.constraints(sys)`) and the temperature are not terms.

```julia
H = Potts.hamiltonian(GranerGlazier(; name = :gg))
first(H[1]), last(H[1])        # cells(…) => λ * (volume - V₀)^2
```
"""
hamiltonian(sys::PottsSystem) = Pair{Any, Any}[e.domain => _wrapped(e.expr) for e in getfield(sys, :energies)]
hamiltonian(c::CompiledPottsSystem) = hamiltonian(c.authored)

# an expression as the user wrote it: wrapped (`Num`) when symbolic, a number as it is
_wrapped(x) = Symbolics.wrap(_unwrap(x))

"""
    Potts.drives(sys) -> AbstractVector

The `@drive copy => expr` expressions of a model (Symbolics expressions, or a number for a constant, in the proposal
scope: `source`, `target`, `old`, `new`, …), in declaration order; empty for a model
without drives. Drives bias the acceptance of a copy but are not terms of
[`Potts.hamiltonian`](@ref).
"""
drives(sys::PottsSystem) = Any[_wrapped(d.expr) for d in getfield(sys, :drives)]
drives(c::CompiledPottsSystem) = drives(c.authored)

"""
    Potts.updates(sys) -> AbstractVector

The update rules of a model as written: one element per `@before_mcs`, `@after_mcs` and
`@on_copy` statement, in declaration order across the three phases (`@extend`/`extend`
statements merged), for a `PottsSystem` (completed or not) or a `CompiledPottsSystem` (the
statements of the model it was compiled from: as written, before `@components` are
lowered). Empty for a model without updates. Each element `u` has the properties

- `u.phase`: `:before_mcs`, `:after_mcs` or `:on_copy`;
- `u.scope`: `:cell`, `:site`, `:model` or `:edge`, the declared scope of the variable the
  statement writes (for `@on_copy x[target] ~ …`, the scope of `x`; a field variable is
  `:site`);
- `u.every`: the cadence, a [`Potts.Every`](@ref) (`Every(1)` when none is written, and
  always for `@on_copy`);
- `u.eq`: the statement as a Symbolics `Equation` in ModelingToolkit's `Pre` form: the new
  value on the left (at `target`/`new` for `@on_copy`), `Pre(x)` where it was written, and a
  compound write `x += e` as `x ~ Pre(x) + e`. Its symbols are the declared ones (as
  `complete(sys).x`) and the DSL built-ins (`volume`, `new`, …).

The rules are a description: Potts compiles and runs them in its sweep, and they are not
ModelingToolkit events (`ModelingToolkitBase.discrete_events(sys)` is empty).

```julia
u = first(Potts.updates(OpenVTGrowingMonolayer(; name = :openvt)))
u.phase, u.scope, u.every      # (:after_mcs, :cell, Every(1))
u.eq                           # V_target ~ ifelse(…, Pre(V_target) + …, Pre(V_target))
```
"""
# one element of `updates(sys)`
const _UpdateRule = @NamedTuple{phase::Symbol, scope::Symbol, every::Every, eq::Equation}
updates(sys::PottsSystem) = _UpdateRule[_update_rule(u) for u in getfield(sys, :updates)]
updates(c::CompiledPottsSystem) = updates(c.authored)

_update_rule(u::Update) = _UpdateRule((u.phase, _written_scope(u), Every(u.every), u.eq))

# the declared scope of the variable an update writes (`x` of an on-copy `x[target]`)
function _written_scope(u::Update)
    x = _unwrap(u.eq.lhs)
    w = u.phase === :on_copy && iscall(x) && operation(x) === at ? arguments(x)[1] : x
    r = role(w)
    return r === :field ? :site : r
end

"""
    Potts.PottsSweepSpec

The lattice sweep of a Potts model as typed system metadata (D-160): both the metadata key
and the value type. Generic code detects a Potts model with MTK's metadata API, with no
Potts internals:

```julia
using ModelingToolkitBase: getmetadata, hasmetadata
hasmetadata(sys, Potts.PottsSweepSpec)                 # true for every Potts model
spec = getmetadata(sys, Potts.PottsSweepSpec, nothing) # `nothing` for a plain `System`
```

The payload is present on every system built by `@potts_model` or the `PottsSystem`
constructor, on `complete(sys)`, on `mtkcompile(sys)` (and its `.sys`) and after `extend`,
and always describes the system it is read from: it is derived on every read, so the key
never appears in the system's raw `metadata` field, and `setmetadata(sys, PottsSweepSpec, x)`
is an `ArgumentError`. On a `CompiledPottsSystem` it describes the model as written (before
`@components` are lowered). It is a description only: MTK never executes the sweep (build
it with `PottsProblem`). The payload shares its domain values and constraint entries with
the model: read it, do not mutate it.

Properties:
- `hamiltonian`: [`Potts.hamiltonian`](@ref)`(sys)`, the `domain => expr` terms;
- `drives`: [`Potts.drives`](@ref)`(sys)`;
- `constraints`: one entry per `@constraint` (as `ModelingToolkitBase.constraints(sys)`;
  the entry type is not public);
- `temperature`: the `@sweep` temperature as written (a declared symbol or an expression,
  wrapped; or a number);
- `proposal`: the `@relations proposal` relation (default `VonNeumann(1)`).
"""
struct PottsSweepSpec
    hamiltonian::Vector{Pair{Any, Any}}
    drives::Vector{Any}
    constraints::Vector{Constraint}
    temperature::Any
    proposal::Any
end

function _sweep_spec(sys::PottsSystem)
    return PottsSweepSpec(hamiltonian(sys), drives(sys), copy(getfield(sys, :constraints)),
        _wrapped(getfield(sys, :sweep).temperature), _proposal_spec(sys))
end

_count_string(n, what) = string(n, " ", what, n == 1 ? "" : "s")
function Base.show(io::IO, s::PottsSweepSpec)
    print(io, "PottsSweepSpec(", _count_string(length(s.hamiltonian), "term"), ", ",
        _count_string(length(s.drives), "drive"), ", ", _count_string(length(s.constraints), "constraint"),
        "; temperature = ", s.temperature, ", proposal = ", s.proposal, ")")
end
function Base.show(io::IO, ::MIME"text/plain", s::PottsSweepSpec)
    println(io, "PottsSweepSpec")
    for (d, e) in s.hamiltonian
        println(io, "  energy  ", _domain_string(d), " => ", e)
    end
    for d in s.drives
        println(io, "  drive   copy => ", d)
    end
    for c in s.constraints
        println(io, "  constraint ", c.kind === :expr ? c.expr : string(c.kind, c.kinds))
    end
    println(io, "  temperature ", s.temperature)
    print(io, "  proposal ", s.proposal)
end

# MTK's typed metadata (D-137): the payload key is answered here, every other key by MTK's
# `AbstractSystem` methods on the `metadata` field. A `CompiledPottsSystem` reads the payload
# of the authored system and every other key from its `.sys`; it is read-only.
SymbolicUtils.getmetadata(sys::PottsSystem, ::Type{PottsSweepSpec}, default) = _sweep_spec(sys)
SymbolicUtils.hasmetadata(::PottsSystem, ::Type{PottsSweepSpec}) = true
SymbolicUtils.setmetadata(::PottsSystem, ::Type{PottsSweepSpec}, v) = throw(ArgumentError(
    "setmetadata(sys, PottsSweepSpec, …): the PottsSweepSpec payload is derived from the model " *
    "(its @energy, @drive, @constraint, @sweep and @relations) and cannot be set; change the model instead"))
SymbolicUtils.getmetadata(c::CompiledPottsSystem, k::DataType, default) = SymbolicUtils.getmetadata(c.sys, k, default)
SymbolicUtils.getmetadata(c::CompiledPottsSystem, ::Type{PottsSweepSpec}, default) = _sweep_spec(c.authored)
SymbolicUtils.hasmetadata(c::CompiledPottsSystem, k::DataType) = SymbolicUtils.hasmetadata(c.sys, k)
SymbolicUtils.setmetadata(::CompiledPottsSystem, k::DataType, v) = throw(ArgumentError(
    "setmetadata(…, $k, …) on a CompiledPottsSystem: a compiled system is read-only; set metadata before mtkcompile"))
