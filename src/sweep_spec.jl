# The sweep's definition as an MTK-visible object (D-160): `hamiltonian(sys)`,
# `drives(sys)` and the `PottsSweepSpec` metadata payload, read with MTK's own
# `getmetadata`/`hasmetadata`; and the update rules as written, `updates(sys)` (D-164).
# Descriptions only: they are derived from the system on every read, so they always
# describe the system they are read from, and they never enter the generated code or the
# fingerprint (D-137 rule 2).

"""
    Potts.hamiltonian(sys) -> Vector{Pair{Any, Any}}

Return the energy ``H`` of a model as written: one `domain => expr` pair per `@energy`
term, in declaration order.

`@extend` and `extend` terms are merged. For a `CompiledPottsSystem` these are the terms
of the model it was compiled from, as written, before `@components` are lowered.

`domain` is the DSL domain value (`cells(k…)`, `clusters(k…)`, `contacts`, `contacts(r)`,
`sites`, `edges(r)`). `expr` is the term's energy density: a number for a constant term,
or a Symbolics expression over the declared parameters and variables (the declared
symbols, as `sys.x`) and the DSL built-ins (`volume`, `neighbor_kind`, …). The energy of a
state is the sum of each density over its domain (cells of the term's kinds, unordered
pairs of the relation with different owners, …), with the conventions of
[`total_energy`](@ref). Drives ([`Potts.drives`](@ref)), constraints (the
`PottsSweepSpec` payload's `constraints`) and the temperature are not terms. An algebraic
variable (`y ~ expr` in `@equations`) appears by name. Its definition is among the
observed equations of [`Potts.inner`](@ref)`(mtkcompile(sys))` and of
[`Potts.ode_system`](@ref).

# Arguments
- `sys`: a `PottsSystem` (completed or not) or a `CompiledPottsSystem`.

# Returns
- `Vector{Pair{Any, Any}}`: the `domain => expr` terms.

# Examples
```julia
H = Potts.hamiltonian(sys)
first(H[1]), last(H[1])        # cells(…) => λ * (volume - V₀)^2
```

See also [`Potts.drives`](@ref), [`Potts.updates`](@ref), [`Potts.PottsSweepSpec`](@ref).
"""
function hamiltonian(sys::PottsSystem)
    return Pair{
        Any,
        Any,
    }[e.domain => _wrapped(_described(e.expr)) for e in _p(sys, :energies)]
end
hamiltonian(c::CompiledPottsSystem) = hamiltonian(getfield(c, :authored))

# an expression as the user wrote it: wrapped (`Num`) when symbolic, a number as it is
_wrapped(x) = Symbolics.wrap(_unwrap(x))

# `x` with every contact fold's tracker symbol replaced by the fold it stands for
# (`count_contacts(…)`): descriptions show the folds, never internal names (D-164)
function _described(x)
    y = _unwrap(x)
    y isa SymbolicUtils.BasicSymbolic || return y
    sub = Dict{Any, Any}()
    _walk_all(y) do z
        i = info(z)
        i !== nothing && i.role === :contact_count && (sub[z] = _fold_description(i))
    end
    return isempty(sub) ? y : _unwrap(Symbolics.substitute(y, sub; fold = Val(false)))
end

"""
    Potts.drives(sys) -> Vector{Any}

Return the `@drive copy => expr` expressions of a model, in declaration order.

Each is a Symbolics expression in the proposal scope (`source`, `target`, `old`, `new`,
…), or a number for a constant. Drives bias the acceptance of a copy but are not terms of
[`Potts.hamiltonian`](@ref).

# Arguments
- `sys`: a `PottsSystem` or a `CompiledPottsSystem`.

# Returns
- `Vector{Any}`: the drive expressions; empty for a model without drives.

See also [`Potts.hamiltonian`](@ref).
"""
drives(sys::PottsSystem) = Any[_wrapped(_described(d.expr)) for d in _p(sys, :drives)]
drives(c::CompiledPottsSystem) = drives(getfield(c, :authored))

# one element of `updates(sys)`
const _UpdateRule = @NamedTuple{phase::Symbol, scope::Symbol, every::Every, eq::Equation}

"""
    Potts.updates(sys) -> Vector

Return the update rules of a model as written: one element per `@before_mcs`,
`@after_mcs` and `@on_copy` statement, in declaration order across the three phases.

`@extend` and `extend` statements are merged. For a `CompiledPottsSystem` these are the
statements of the model it was compiled from, as written, before `@components` are
lowered. Each element `u` has the properties:

- `u.phase`: `:before_mcs`, `:after_mcs` or `:on_copy`.
- `u.scope`: `:cell`, `:site`, `:model` or `:edge`, the declared scope of the variable
  that the statement writes. For `@on_copy x[target] ~ …` it is the scope of `x`, and a
  field variable is `:site`.
- `u.every`: the cadence, a [`Potts.Every`](@ref). It is `Every(1)` when none is written,
  and always for `@on_copy`.
- `u.eq`: the statement as a Symbolics `Equation` in ModelingToolkit's `Pre` form. The new
  value is on the left (at `target`/`new` for `@on_copy`), `Pre(x)` stands where `x` was
  written, and a compound write `x += e` is `x ~ Pre(x) + e`. Its symbols are the declared
  ones (as `sys.x`) and the DSL built-ins (`volume`, `new`, …).

Folds appear as Potts fold terms over their bound variable: a contact fold as
[`Potts.count_contacts`](@ref)`(contact_partner, pred, relation)`, a population fold as
`population(c_k, body, cond)`, and a gather with its bound `n_k`. Random draws appear as
`random_*` terms numbered in declaration order. Scope and cadence are those of a valid
model: the statements are checked when the model is compiled (`mtkcompile`,
`PottsProblem`), not here. An algebraic variable (`y ~ expr` in `@equations`) appears by
name. Its definition is among the observed equations of
[`Potts.inner`](@ref)`(mtkcompile(sys))` and of [`Potts.ode_system`](@ref).

The rules are a description: Potts compiles and runs them in its sweep, and they are not
ModelingToolkit events (`ModelingToolkitBase.discrete_events(sys)` is empty).

# Arguments
- `sys`: a `PottsSystem` (completed or not) or a `CompiledPottsSystem`.

# Returns
- A `Vector` of `NamedTuple`s with the fields `phase`, `scope`, `every` and `eq`; empty
  for a model without updates.

# Examples
```julia
u = first(Potts.updates(sys))
u.phase, u.scope, u.every   # (:after_mcs, :cell, Potts.Every(1))
u.eq
```

See also [`Potts.hamiltonian`](@ref), [`Potts.Every`](@ref).
"""
updates(sys::PottsSystem) = _UpdateRule[_update_rule(u) for u in _p(sys, :updates)]
updates(c::CompiledPottsSystem) = updates(getfield(c, :authored))

function _update_rule(u::Update)
    return _UpdateRule((u.phase, _update_scope(u), Every(u.every), _described(u.eq)))
end

function _described(eq::Equation)
    lhs, rhs = _described(eq.lhs), _described(eq.rhs)
    return lhs === _unwrap(eq.lhs) && rhs === _unwrap(eq.rhs) ? eq : lhs ~ rhs
end

"""
    Potts.PottsSweepSpec

The lattice sweep of a Potts model as typed system metadata: both the metadata key and the
value type.

It is metadata of the model's inner System (`Potts.inner(sys)`), set when the model is
built (`Potts.wrap_system`). So generic code that holds the System detects a Potts model
with MTK's metadata API. A `CompiledPottsSystem` answers the same keys
(`getmetadata(mtkcompile(sys), PottsSweepSpec, nothing)`), and describes the model as
written (before `@components` are lowered). It is a description only: MTK never runs the
sweep (build it with `PottsProblem`). The payload shares its domain values and constraint
entries with the model: read it, do not mutate it.

# Fields
- `hamiltonian`: [`Potts.hamiltonian`](@ref)`(sys)`, the `domain => expr` terms.
- `drives`: [`Potts.drives`](@ref)`(sys)`.
- `constraints`: one entry per `@constraint` (the entry type is not public).
- `temperature`: the `@sweep` temperature as written (a declared symbol or an expression,
  wrapped; or a number).
- `proposal`: the `@relations proposal` relation (default `VonNeumann(1)`).

# Examples
```julia
using ModelingToolkitBase: getmetadata, hasmetadata
hasmetadata(Potts.inner(sys), Potts.PottsSweepSpec)  # true for every Potts model
spec = getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing)
spec.temperature
```

See also [`Potts.hamiltonian`](@ref), [`Potts.inner`](@ref).
"""
struct PottsSweepSpec
    hamiltonian::Vector{Pair{Any, Any}}
    drives::Vector{Any}
    constraints::Vector{Constraint}
    temperature::Any
    proposal::Any
end

function _sweep_spec(sys::PottsSystem)
    return PottsSweepSpec(
        hamiltonian(sys), drives(sys), copy(_p(sys, :constraints)),
        _wrapped(_p(sys, :sweep).temperature), _proposal_spec(sys)
    )
end

_count_string(n, what) = string(n, " ", what, n == 1 ? "" : "s")
function Base.show(io::IO, s::PottsSweepSpec)
    return print(
        io, "PottsSweepSpec(", _count_string(length(s.hamiltonian), "term"), ", ",
        _count_string(length(s.drives), "drive"), ", ",
        _count_string(length(s.constraints), "constraint"),
        "; temperature = ", s.temperature, ", proposal = ", s.proposal, ")"
    )
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
    return print(io, "  proposal ", s.proposal)
end

# MTK's typed metadata (D-137): the payload is the inner System's (`Potts.wrap_system` sets
# it). A `CompiledPottsSystem` reads every key from the authored model's inner System; it is
# read-only.
function SymbolicUtils.getmetadata(c::CompiledPottsSystem, k::DataType, default)
    return SymbolicUtils.getmetadata(inner(getfield(c, :authored)), k, default)
end
function SymbolicUtils.hasmetadata(c::CompiledPottsSystem, k::DataType)
    return SymbolicUtils.hasmetadata(inner(getfield(c, :authored)), k)
end
function SymbolicUtils.setmetadata(::CompiledPottsSystem, k::DataType, v)
    throw(
        ArgumentError(
            "setmetadata(…, $k, …) on a CompiledPottsSystem: a compiled system is \
                read-only; set metadata before mtkcompile"
        )
    )
end
