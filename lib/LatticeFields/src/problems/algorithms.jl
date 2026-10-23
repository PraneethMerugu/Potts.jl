# The field algorithms (F2 design §2.3, §2.6): `ExplicitEuler`, `ExplicitMap`, the group
# assignment `FieldGroups`, and the hooks an algorithm defines for the group layer
# (`group.jl`): its update (`update_key`), its family (`alg_family`), its buffer count
# (`nbuffers`) and its cache (`alg_cache`, `reset_cache!`, `step_retcode!`).

"""
Field stepping algorithms of the owned path.
"""
abstract type FieldAlgorithm end

"""
    ExplicitEuler(; dt = nothing, substeps = nothing, lower = nothing)

Forward Euler: each window `dt` runs `n` substeps of `dt / n`. One type for both front ends
(`Potts` and `LatticePDE` export this binding). `substeps = nothing` takes the automatic
count `n = ⌈dt ρ(p) / 1.8⌉` from the problem's stability bound `ρ` at the current parameters
(§6.2); an unknown bound (a rate term it cannot see, a parameter without a value, or coupled
rows that are not diagonally dominant) is refused. A count `substeps = n ≥ 1` is a minimum:
the count is the larger of `n` and the bound over the terms the bound sees; when no term is
seen, `n` is used. `lower` clips each substep's result at `max(v, lower)`.

- On a `FieldProblem` (`LatticePDE.discretize(…; problem = :owned)`), `dt` is the step and
  is required (nothing else sets the window: `saveat` does not); `lower`
  clips as above, fused into the step by the update pass ([`update_rule`](@ref)).
- As a `PottsProblem` `field_solver`, the window is the MCS (`mcs_duration`): `dt` must be
  left out. As an `ode_solver`, `substeps = nothing` is one step per MCS.

`dt` must be finite and > 0, and `substeps` ≥ 1: `substeps = 0` is an `ArgumentError` (leave
`substeps` out for the automatic count).
"""
struct ExplicitEuler <: FieldAlgorithm
    dt::Union{Nothing, Float64}
    substeps::Union{Nothing, Int}
    lower::Union{Nothing, Float64}
    function ExplicitEuler(dt, substeps, lower)
        dt === nothing || (dt isa Real && isfinite(dt) && dt > 0) ||
            throw(ArgumentError("ExplicitEuler: dt = $(repr(dt)) must be finite and > 0"))
        substeps isa Integer && substeps == 0 && throw(ArgumentError(
            "ExplicitEuler: `substeps = 0` is not a count; leave `substeps` out for the automatic count"))
        substeps === nothing || (substeps isa Integer && substeps >= 1) ||
            throw(ArgumentError("ExplicitEuler: substeps = $(repr(substeps)) must be an integer ≥ 1 (or left out: automatic)"))
        lower === nothing || lower isa Real && isfinite(lower) ||
            throw(ArgumentError("ExplicitEuler: lower = $(repr(lower)) must be a finite number (a clip at ±Inf or NaN " *
                                "clips nothing or every value; leave `lower` out for no clip)"))
        return new(dt === nothing ? nothing : Float64(dt), substeps === nothing ? nothing : Int(substeps),
            lower === nothing ? nothing : Float64(lower))
    end
end
ExplicitEuler(; dt = nothing, substeps = nothing, lower = nothing) = ExplicitEuler(dt, substeps, lower)
# the state buffers a step of the algorithm needs per field (`c`, `c__next`)
nbuffers(::ExplicitEuler) = 2

"""
    ExplicitMap()

Discrete maps `Shift(t, 1)(c) ~ rhs` (§5.5): one application per unit of time.
"""
struct ExplicitMap <: FieldAlgorithm end
nbuffers(::ExplicitMap) = 2

# The window of a step of `alg` on a problem whose discretization declares the clock of period
# `clock` (`nothing`: none; F2 design §2.4, §2.6): the algorithm's `dt`, or the clock's period
# when `dt` is left out; without a clock `dt` is required (nothing else sets the window:
# `saveat` never does). A given `dt` must divide the period to a relative 1e-12: the stepper
# lands on every clock boundary, so a period holds a whole number of windows (`_per`).
function _window(alg::FieldAlgorithm, clock)
    dt = alg.dt
    if dt === nothing
        clock === nothing && throw(ArgumentError(string(
            "`", nameof(typeof(alg)), "` on a `FieldProblem` needs `dt` (the window) when the discretization declares no ",
            "`clock`: nothing else sets the window, and `saveat` never does; give `", nameof(typeof(alg)), "(; dt)` or ",
            "`LatticeDiscretization(…; clock = τ)`")))
        return Float64(clock)
    end
    clock === nothing || _per(dt, clock)
    return Float64(dt)
end
# a map steps one unit of time: a clock is a whole number of map steps
function _window(::ExplicitMap, clock)
    clock === nothing || (clock >= 1 && abs(round(clock) - clock) <= 1e-12 * clock) || throw(ArgumentError(string(
        "the clock's period ", clock, " is not a whole number of map steps (a map steps one unit of time, and ",
        "`step_index(t)` counts whole periods): give `clock = n` with an integer n ≥ 1, or no clock")))
    return 1.0
end
# the number of windows `dt` in one period of the clock
function _per(dt, clock)
    m = round(Int, clock / dt)
    m >= 1 && abs(m * dt - clock) <= 1e-12 * clock || throw(ArgumentError(string(
        "dt = ", dt, " does not divide the clock's period ", clock, " (to a relative 1e-12): the stepper lands on every ",
        "boundary of the clock, so a period holds a whole number of windows; give dt = ", clock, "/n, or leave `dt` out ",
        "to step windows of ", clock)))
    return m
end

"""
    update_key(alg)

The update that algorithm `alg` fuses into a group's rate program, as a key: a group's fused
program and plans are cached by it (and the value type), so two algorithms with one update
share them (`ExplicitEuler(; dt = 0.1)` and `ExplicitEuler(; dt = 0.2, substeps = 4)`:
`:euler`). It names every part of the algorithm that changes the fused program: a clip
`lower` is part of it (`(:euler, 0.0)`).
"""
update_key(a::ExplicitEuler) = a.lower === nothing ? :euler : (:euler, a.lower)
update_key(::ExplicitMap) = :map

"""
    update_rule(alg) -> rule or nothing

The update of algorithm `alg` for the update pass ([`fuse_update`](@ref
LatticeFields.Compile.fuse_update)): `rule(kb, c, r)` gives the new value of a field from its
current value `c` and its rate `r` (IR handles). `ExplicitEuler`: `c + dt · r` with
`dt = G.rt[2]`, then `max(·, lower)` with a clip; `ExplicitMap`: `nothing` (a map program
stores its values itself).
"""
update_rule(a::ExplicitEuler) = EulerRule(a.lower)
update_rule(::ExplicitMap) = nothing
struct EulerRule
    lower::Union{Nothing, Float64}
end
function (u::EulerRule)(kb, c, r)
    v = c + Ex(kb, runtime!(kb, RT_DT)) * r
    return u.lower === nothing ? v : max(v, u.lower)
end

"""
    alg_family(alg) -> Symbol

`:rate` for an algorithm that steps rates `D(c) ~ rhs`, `:map` for one that applies maps
`Shift(t, 1)(c) ~ rhs`. A problem steps one family (split stepping is planned).
"""
alg_family(::FieldAlgorithm) = :rate
alg_family(::ExplicitMap) = :map

"""
    alg_cache(alg, group, store) -> cache

The algorithm's own state for one group on `store` (`nothing` for `ExplicitEuler` and
`ExplicitMap`): the workspaces and history of an implicit or multistep method. It lives in the
group's [`GroupRuntime`](@ref); [`reset!`](@ref) drops its history (`reset_cache!`), and
after each step [`advance!`](@ref) returns its `step_retcode!`.
"""
alg_cache(::FieldAlgorithm, group, store) = nothing

"""
    reset_cache!(cache)

Drop the history of an algorithm's cache: the state was written (`integ[c] = values`,
`reinit!`), or the parameters or inputs changed. Nothing for `nothing`.
"""
reset_cache!(::Nothing) = nothing

"""
    step_retcode!(cache, rt) -> ReturnCode.T

The return code of the step that runtime `rt` just took: `ReturnCode.Success` for an
explicit algorithm (`nothing` cache); an implicit solver returns its failure code
(`ConvergenceFailure`, …), and the driver stops with it.
"""
step_retcode!(::Nothing, rt) = SciMLBase.ReturnCode.Success

"""
    FieldGroups(field => alg, …; default = nothing)

An algorithm that steps the fields of a problem in groups (F2 design §2.6): each field takes
the algorithm of its pair (a field symbol, or a state key), the others `default`. Fields with
`isequal` algorithms form one group (the comparison covers the whole value, `dt` included).
Groups run in state order (the order of their first field), each step of `dt`: a group reads
the fields of the other groups from their arrays, as they are when it runs (A's field phases
do the same, v3 §6.1), and ends each step in slot 1, so the next group reads the current
values.

Groups that read one another in a loop (`c` reads `o` and `o` reads `c`, directly or through
other groups) can grow without bound at any substep count, because each holds the others'
values over the window. For each group in such a loop, `dt` times the largest sum, over the
group's rows, of the largest coefficient magnitudes of the terms that read other groups of
the same loop must be at most 1 (a conservative limit). Reads of groups outside the loop do
not count. Past it the problem is refused, naming the fields of the
loop. The routes: step those fields in one group (with an explicit `substeps = n` when their
rows are not diagonally dominant), or use a smaller `dt` that divides the time span. A
one-way chain (`u` reads `c`, `c` does not read `u`) has no loop and is not limited: each group
is stable under its own count. A group with a term that the stability bound cannot see and
that reads another field counts as reading every other group. A term that reads only its own
field (`-a^3`) does not. [`substep_counts`](@ref) gives each group's count.

Every group has the same window: two algorithms with different `dt` are an `ArgumentError`.
A rate algorithm and a map algorithm are never mixed (split stepping is planned). A field
without a pair and with no `default` is an error naming it.

```julia
solve(prob, FieldGroups(o => ExplicitEuler(; dt = 0.1, substeps = 4); default = ExplicitEuler(; dt = 0.1)))
```
"""
struct FieldGroups <: FieldAlgorithm
    pairs::Vector{Pair{Any, FieldAlgorithm}}
    default::Union{Nothing, FieldAlgorithm}
    function FieldGroups(pairs::Vector{Pair{Any, FieldAlgorithm}}, default)
        for (k, a) in pairs
            a isa FieldGroups && throw(ArgumentError("FieldGroups: the algorithm of `$k` is a `FieldGroups`; give one algorithm per field"))
        end
        default isa FieldGroups && throw(ArgumentError("FieldGroups: `default` is a `FieldGroups`; give one algorithm"))
        return new(pairs, default)
    end
end
function FieldGroups(pairs::Pair...; default = nothing)
    for (k, a) in pairs
        a isa FieldAlgorithm || throw(ArgumentError("FieldGroups: `$k => $(repr(a))` is not a field algorithm"))
    end
    default === nothing || default isa FieldAlgorithm ||
        throw(ArgumentError("FieldGroups: default = $(repr(default)) is not a field algorithm"))
    return FieldGroups(Pair{Any, FieldAlgorithm}[k => a for (k, a) in pairs], default)
end
nbuffers(g::FieldGroups) = maximum(nbuffers, [last.(g.pairs); g.default === nothing ? FieldAlgorithm[] : [g.default]])

"""
    canonical(alg) -> String

The one canonical text of a field algorithm (or of a solver part: `DevicePCG`, `Multigrid`,
`V`, `:auto`, a number), the text both front ends' fingerprints hash (F3 design §3.7): what
the algorithm is, not the host object, so equal specifications built afresh print alike.
`ExplicitEuler` prints `ExplicitEuler(substeps=…,lower=…)` (its window `dt` is the
problem's, not part of the scheme); another algorithm prints every field but `dt`, sorted by
name, each by `canonical`; `:auto` prints as given (`:auto`, unresolved, so a CPU and a
device problem print alike). A `FieldGroups` prints its pairs as given (a front end that
resolves it per field, front end A, prints the per-field map instead).
"""
canonical(s::ExplicitEuler) = "ExplicitEuler(substeps=$(repr(s.substeps)),lower=$(repr(s.lower)))"
canonical(::ExplicitMap) = "ExplicitMap()"
canonical(g::FieldGroups) = string("FieldGroups(", join((string(k, "=", canonical(a)) for (k, a) in g.pairs), ","),
    ";default=", g.default === nothing ? "nothing" : canonical(g.default), ")")
canonical(a::FieldAlgorithm) = _canonical_fields(a)
canonical(s::Union{Solvers.DevicePCG, Solvers.Multigrid}) = _canonical_fields(s)
canonical(v::Solvers.V) = "V($(v.nu1),$(v.nu2))"
canonical(s::Symbol) = repr(s)
canonical(::Nothing) = "nothing"
canonical(x::Union{Number, AbstractString}) = repr(x)
canonical(::Type{T}) where {T} = string(T)
canonical(x) = throw(ArgumentError("no canonical text for $(repr(x)) (a `$(typeof(x))`): a field algorithm's " *
                                   "keywords are numbers, symbols, types or solver parts"))
_canonical_fields(s) = string(nameof(typeof(s)), "(",
    join((string(f, "=", canonical(getfield(s, f))) for f in sort!(collect(fieldnames(typeof(s)))) if f !== :dt), ","), ")")

# an algorithm in messages, in its keyword form (`ExplicitEuler(; dt = 0.01, substeps = 2)`)
function _algtext(a::ExplicitEuler)
    kw = [string(k, " = ", getfield(a, k)) for k in (:dt, :substeps, :lower) if getfield(a, k) !== nothing]
    return isempty(kw) ? "ExplicitEuler()" : string("ExplicitEuler(; ", join(kw, ", "), ")")
end
_algtext(a) = repr(a)
