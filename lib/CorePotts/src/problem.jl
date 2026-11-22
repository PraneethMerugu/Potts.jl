# SciML interface: problem → init → step!/solve!, with CommonSolve dispatch so that
# `solve(prob, alg)`, `EnsembleProblem`, callbacks-by-integrator and `remake` behave as in
# the rest of SciML. Time is the integer MCS.

const STATUS_NONFINITE = UInt32(1)

"""
    PottsProblem(f::CPMFunction, u0::CPMState, lattice::Lattice, tspan, p;
                 contact = Moore(1), proposal = VonNeumann(1), relations = (;),
                 spacing = nothing, frozen = nothing, seed = 0, replica = 0, repeat = 0,
                 tangent = nothing, kwargs...)

Construct a cellular Potts problem: the model `f`, the initial state `u0` on `lattice`, the
time span and the parameters.

An MCS is one copy attempt per mobile site. `p` is any isbits parameter object (a
`NamedTuple`, or the `PottsParameters` that the symbolic layer generates); changing it with
`remake` or `setp(prob, x)(prob, v)` never recompiles. Any other keyword (`saveat`,
`callback`, …) is a `solve` keyword kept in `prob.kwargs`: `solve` and `init` merge them
with their own keywords, which take precedence (a `callback` given to both runs both).

The problem checks its parts at construction and throws an `ArgumentError` when the state
size differs from the lattice, `tspan` is out of range, a relation uses a reserved name,
`spacing` or `frozen` has the wrong shape, or a site outside the lattice domain belongs to
a cell. A model with frozen kinds ([`frozen_kinds`](@ref)) derives the frozen mask from
the state, and a different `frozen` mask is an `ArgumentError`.

# Arguments
- `f::CPMFunction`: the model functions.
- `u0::CPMState`: the initial state, the same size as the lattice.
- `lattice::Lattice`: the lattice.
- `tspan`: `(t0, t1)` in MCS, with `0 ≤ t0 ≤ t1 ≤ 2^32 - 1`.
- `p`: the parameter object.

# Keywords
- `contact = Moore(1)`: the contact relation, exposed to the model as `ctx.contact`.
- `proposal = VonNeumann(1)`: the proposal relation, used by algorithms constructed
  without one (`SequentialCPM()`).
- `relations = (;)`: named relations (for example `(; surface = Moore(1))`), resolved on
  `lattice` and exposed as `ctx.surface`, …. The names `contact`, `proposal`, `lattice`,
  `mobility`, `mcs` and `spacing` are reserved.
- `spacing = nothing`: the lattice spacing per axis, exposed as `ctx.spacing` to field
  primitives; `ndims(lattice)` positive numbers in the model's float type (`Float32` for
  Metal). `nothing`: spacing 1 on every axis (`ctx.spacing` is not set).
- `frozen = nothing`: a `Bool` mask of sites that never change owner and never donate
  (obstacles). Sites outside the lattice domain are always frozen.
- `seed = 0`, `replica = 0`, `repeat = 0`: the random-stream address, stored as `UInt64`,
  `UInt32` and `UInt32`.
- `tangent = nothing`: a `CorePotts.ParameterTangent` that holds the parameters with
  derivative parts, for a run that differentiates its fields. `p` stays the primal object
  that the CPM reads, and the field groups also step the derivative parts along the run.
- `kwargs...`: `solve` keywords stored in `prob.kwargs`.

# Examples
```julia
using CorePotts
l = Lattice((40, 40))
σ = zeros(Int32, 40, 40); σ[11:20, 11:20] .= 1; σ[21:30, 21:30] .= 2
J(a, b) = (a == 0) | (b == 0) ? 16.0 : 2.0
dH(st, p, prop, ctx) = contact_delta(st.ownership, ctx, prop, J) +
    volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - 100)^2)
f = CPMFunction(dH; temperature = (st, p, prop, ctx) -> 10.0)
prob = PottsProblem(f, initial_state(σ, [1, 1]), l, (0, 100), (; λ = 1.0); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 10)
```

See also [`CPMFunction`](@ref), [`PottsIntegrator`](@ref), [`PottsSolution`](@ref).
"""
mutable struct PottsProblem{
        F <: CPMFunction, S <: CPMState, L <: Lattice, R, Q, RS, H, FZ, P, TG, K,
    } <:
    SciMLBase.AbstractSciMLProblem
    const f::F
    const u0::S
    const lattice::L
    const contact::R
    const proposal::Q                   # a neighbourhood spec, resolved at `init`
    const relations::RS
    const spacing::H
    const frozen::FZ
    const tspan::Tuple{Int, Int}
    # the only mutable field: `setp(prob, x)(prob, v)` (same type)
    p::P
    const seed::UInt64
    const replica::UInt32
    const repeat::UInt32
    const tangent::TG
    const kwargs::K                     # the problem's `solve` keywords (a NamedTuple)
end

function PottsProblem(
        f::CPMFunction, u0::CPMState, lattice::Lattice, tspan, p;
        contact = Moore(1), proposal = VonNeumann(1),
        relations = (;), spacing = nothing, frozen = nothing, seed = 0,
        replica = 0, repeat = 0, tangent = nothing, kwargs...
    )
    return _problem(
        f, u0, lattice, tspan, p, contact, proposal, relations,
        spacing, frozen, seed, replica, repeat, tangent,
        NamedTuple(kwargs)
    )
end

# The checks and the resolved relations of a new problem, compiled once for every model:
# nothing here is specialized on the model's types (the problem type itself is built at the
# end)
Base.@nospecializeinfer function _problem(
        @nospecialize(f::CPMFunction), @nospecialize(u0::CPMState),
        @nospecialize(lattice::Lattice), @nospecialize(tspan), @nospecialize(p),
        @nospecialize(contact),
        @nospecialize(proposal), @nospecialize(relations), @nospecialize(spacing),
        @nospecialize(frozen), seed, replica,
        repeat, @nospecialize(tangent), @nospecialize(kwargs::NamedTuple)
    )
    size(u0.ownership) == lattice.dims ||
        throw(ArgumentError("state size $(size(u0.ownership)) ≠ lattice $(lattice.dims)"))
    t0, t1 = Int.(tspan)
    0 <= t0 <= t1 <= typemax(UInt32) ||
        throw(ArgumentError("tspan must satisfy 0 ≤ t0 ≤ t1 ≤ 2^32 - 1"))
    any(in((:contact, :proposal, :lattice, :mobility, :mcs, :spacing)), keys(relations)) &&
        throw(ArgumentError("relation names `contact`, `proposal`, `lattice`, `mobility`, \
            `mcs`, `spacing` are reserved"))
    rs = map(r -> relation(r, lattice), NamedTuple(relations))
    h = spacing === nothing ? nothing : Tuple(spacing)
    h === nothing || (length(h) == ndims(lattice) && all(x -> x > 0, h)) ||
        throw(ArgumentError("spacing must be $(ndims(lattice)) positive numbers"))
    frozen === nothing || size(frozen) == lattice.dims ||
        throw(ArgumentError("frozen mask has size $(size(frozen)), \
            lattice $(lattice.dims)"))
    kinds = frozen_kinds(f.sys)
    if kinds !== nothing                            # the standard rule decides the mask
        rule = _standard_frozen(kinds, u0)
        dom(m) = lattice.mask === nothing ? m : m .| .!lattice.mask
        frozen === nothing || dom(frozen) == dom(rule) || throw(
            ArgumentError(
                "a model with frozen kinds $kinds derives its frozen mask from the " *
                    "state; a `frozen` mask that differs from it cannot be combined with " *
                    "them (give the obstacle sites to a cell of a frozen kind instead)"
            )
        )
        frozen = rule
    end
    # outside the domain: medium, never mobile
    if lattice.mask !== nothing
        all(i -> lattice.mask[i] || u0.ownership[i] == 0, eachindex(u0.ownership)) ||
            throw(ArgumentError("sites outside the lattice domain must belong to the \
                medium (0)"))
        frozen = frozen === nothing ? .!lattice.mask : (frozen .| .!lattice.mask)
    end
    relation(proposal, lattice)                     # validate now; resolved again at `init`
    return PottsProblem(
        f, u0, lattice, relation(contact, lattice), proposal, rs, h, frozen, (t0, t1), p,
        UInt64(seed), UInt32(replica), UInt32(repeat), tangent, kwargs
    )
end

"""
    remake_parameters(sys, prob, p)

Return the parameter object of a problem remade with the parameters `p` given to `remake`.

It is a hook for the symbolic layer, which turns a parameter map or operating point into
its parameter object. The default returns `p` itself.

# Arguments
- `sys`: the model description (`prob.f.sys`).
- `prob::PottsProblem`: the problem being remade.
- `p`: the parameters as the user gave them.

# Returns
- The parameter object.

See also [`remake_state`](@ref), [`remake_tangent`](@ref).
"""
remake_parameters(sys, prob, p) = p
"""
    remake_state(sys, prob, u0, kwargs = prob.kwargs)

Return the state of a problem remade with the `u0` given to `remake`.

It is a hook for the symbolic layer. The default returns `u0` itself.

# Arguments
- `sys`: the model description (`prob.f.sys`).
- `prob::PottsProblem`: the problem being remade.
- `u0`: the state as the user gave it.
- `kwargs`: the `solve` keywords of the remade problem.

# Returns
- The state.

See also [`remake_parameters`](@ref).
"""
remake_state(sys, prob, u0, kwargs = prob.kwargs) = u0
"""
    check_initializealg(sys, alg) -> nothing

Check that the model described by `sys` can apply the initialization algorithm `alg`.

It is a hook for the symbolic layer, which throws for an `initializealg` that it cannot
apply. The default accepts every `alg`.

# Arguments
- `sys`: the model description.
- `alg`: the `initializealg`.

# Returns
- `nothing`.
"""
check_initializealg(sys, alg) = nothing
"""
    remake_tangent(sys, prob, pgiven, pnew)

Return the `tangent` of a problem remade with the parameters `pgiven`.

It is a hook for the symbolic layer. `pgiven` is the parameters as the user gave them, and
`pnew` the primal object that [`remake_parameters`](@ref) made. The default returns
`nothing` (no derivative parts).

# Arguments
- `sys`: the model description.
- `prob::PottsProblem`: the problem being remade.
- `pgiven`: the parameters as given.
- `pnew`: the new parameter object.

# Returns
- A `CorePotts.ParameterTangent`, or `nothing`.
"""
remake_tangent(sys, prob, pgiven, pnew) = nothing
"""
    report_run(sys, integ) -> nothing

Report the opt-in diagnostics of a run, once per solve, at the end of `solve!`.

It is a hook for the symbolic layer. The default does nothing.

# Arguments
- `sys`: the model description.
- `integ::PottsIntegrator`: the integrator at the end of the run.

# Returns
- `nothing`.
"""
report_run(sys, integ) = nothing
"""
    frozen_kinds(sys)

Return the kinds whose cells' sites are frozen, as a tuple of `Int32`, or `nothing`.

A system that returns kinds uses the standard rule: a site is frozen when its owner's kind
is listed or it lies outside the lattice domain. The rule builds the problem's mask
(`PottsProblem`, `remake`, checkpoint resume) and is recomputed on the integrator's
backend after lifecycle events. A problem with frozen kinds takes no other `frozen` mask.
The default is `nothing`.

# Arguments
- `sys`: the model description.

# Returns
- `Tuple` of `Int32`, or `nothing`.

# Examples
```julia
CorePotts.frozen_kinds(::MySystem) = (Int32(3),)    # kind 3 is a frozen kind
```

See also [`frozen_varies`](@ref), [`remake_frozen`](@ref), [`frozen_sites`](@ref).
"""
frozen_kinds(sys) = nothing

"""
    frozen_varies(sys) -> Bool

Return whether the frozen mask follows the state during a run.

`false` means a static mask (none, a domain, a user `frozen`), never recomputed. The
default is `frozen_kinds(sys) !== nothing`. A system with a custom
[`remake_frozen`](@ref) defines it: `true` to follow the state, `false` for a deliberately
static mask.

# Arguments
- `sys`: the model description.

# Returns
- `Bool`.

See also [`frozen_kinds`](@ref), [`refresh_frozen!`](@ref).
"""
frozen_varies(sys) = frozen_kinds(sys) !== nothing

"""
    remake_frozen(sys, prob, u0)

Return the frozen mask of a remade or reinitialized state `u0`.

The default is the standard rule when `frozen_kinds(sys)` names kinds, else `prob.frozen`
(a static mask).

A custom rule overrides this method and must also define `frozen_varies(sys) = true`.
Without it the integrator treats the mask as static and never recomputes it, and `init`
warns. Defining `frozen_varies(sys) = false` (a deliberately static mask) silences the
warning. A custom rule runs on a host copy of the state at every refresh;
[`frozen_reads`](@ref) limits that copy to the leaves the rule reads.

# Arguments
- `sys`: the model description.
- `prob::PottsProblem`: the problem.
- `u0`: the state, on the host.

# Returns
- A `Bool` array of the lattice size, or `nothing`.

# Examples
```julia
CorePotts.remake_frozen(::MySystem, prob, u) = map(s -> s == 1, u.ownership)
CorePotts.frozen_varies(::MySystem) = true
CorePotts.frozen_reads(::MySystem) = (:ownership,)
```

See also [`frozen_varies`](@ref), [`frozen_sites`](@ref).
"""
function remake_frozen(sys, prob, u0)
    return (k = frozen_kinds(sys)) === nothing ? prob.frozen : _standard_frozen(k, u0)
end

"""
    frozen_reads(sys)

Return the state leaves that a custom [`remake_frozen`](@ref) rule reads at a refresh, or
`nothing`.

The leaves are `:ownership` (the cell numbers) or cell column names, each at most once. On a
device, a refresh then copies only these leaves to the host before it runs the rule. Every
other leaf is the live device array: do not read it on the host (scalar indexing errors;
`Array(...)` works but is an uncounted transfer). `nothing` (the default) copies the whole
state. A rule that reads model, site or history quantities keeps the default. The standard
rule ([`frozen_kinds`](@ref)) runs on the integrator's backend and ignores this hook.

A name that is neither `:ownership` nor a cell column of the state, or that is repeated,
is an `ArgumentError` at `init` (and at every refresh), on every backend.

# Arguments
- `sys`: the model description.

# Returns
- `Tuple` of `Symbol`s, or `nothing`.
"""
frozen_reads(sys) = nothing

# A custom `remake_frozen` without `frozen_varies(sys) = true` gives a static mask: say so.
function _check_frozen_hooks(@nospecialize(sys))         # (host, once per `init`)
    frozen_varies(sys) && return nothing
    which(remake_frozen, Tuple{typeof(sys), Any, Any}).module === CorePotts &&
        return nothing
    # a `frozen_varies` defined outside CorePotts (even `false`, also on a supertype) is a
    # choice (D-133)
    which(frozen_varies, Tuple{typeof(sys)}).module === CorePotts || return nothing
    @warn "`remake_frozen` is overridden for $(typeof(sys)) but `frozen_varies(sys)` is " *
        "false: the frozen mask stays static during a run. Define \
            `CorePotts.frozen_varies(::$(typeof(sys))) = true`." maxlog = 1
    return nothing
end

# The declared reads of a custom rule (D-128): `nothing`, or a tuple of distinct
# `:ownership` and cell column names of `st`; checked at `init` and at every custom-rule
# refresh.
function _frozen_reads(@nospecialize(sys), @nospecialize(st))
    reads = frozen_reads(sys)
    reads === nothing && return nothing
    (reads isa Tuple && all(n -> n isa Symbol, reads)) || throw(
        ArgumentError(
            "`frozen_reads` must be `nothing` or a tuple of Symbols (`:ownership` or cell \
                column names); got $(repr(reads))"
        )
    )
    for n in reads
        n === :ownership || haskey(st.cell, n) || throw(
            ArgumentError(
                "`frozen_reads` declares `$n`, which is neither `:ownership` nor a cell " *
                    "column of the state (cell columns: $(join(keys(st.cell), ", ")))"
            )
        )
    end
    allunique(reads) || throw(
        ArgumentError(
            "`frozen_reads` declares \
                `$(reads[findfirst(n -> count(==(n), reads) > 1, reads)])` more than \
                    once; got $(repr(reads))"
        )
    )
    return reads
end
_custom_frozen(@nospecialize(sys)) = frozen_varies(sys) && frozen_kinds(sys) === nothing

# the standard rule on a host state (without the domain, which `PottsProblem` adds)
function _standard_frozen(kinds, u)
    k = Array(u.cell.kind)
    return map(s -> s != 0 && _in_kinds(k[s], kinds), Array(u.ownership))
end
"""
    remake_function(sys, prob; kwargs...) -> (f, u0)

Return the model and state of a problem remade with extra `remake` keywords.

It is a hook for the symbolic layer, for its problem-construction keywords (such as the
solvers of the Potts package). It returns a new `f` built from them, and `prob.u0` laid out
again for it if its state layout depends on them (values kept); everything else is kept.
The default throws an `ArgumentError` for every such keyword.

# Arguments
- `sys`: the model description.
- `prob::PottsProblem`: the problem being remade.

# Keywords
- `kwargs...`: the `remake` keywords beyond the fixed ones.

# Returns
- `Tuple{CPMFunction, CPMState}`.
"""
function remake_function(sys, prob; kwargs...)
    throw(
        ArgumentError(
            "remake: unknown keyword$(length(kwargs) == 1 ? "" : "s") " *
                "$(join(("`$k`" for k in keys(kwargs)), ", "))"
        )
    )
end

"""
    remake(prob::PottsProblem; f, u0, tspan, p, seed, replica, repeat, kwargs, …)

A new problem with the given parts changed and every other part kept. `p` is a parameter
object or a map (`[T => 5.0]`, also `[:T => 5.0]` for the fields of a `NamedTuple` parameter
object). A `solve` keyword (`saveat = 10`) joins the problem's `kwargs`; `kwargs = (; …)`
replaces them, but keeps the problem's `initializealg` unless they set one. `initializealg`
is kept with the problem: a new `u0` is initialized with the given one, or else with the
problem's. A new `initializealg` needs a new `u0` (nothing else is initialized again);
without one it is an `ArgumentError`. Other keywords are the symbolic layer's problem
keywords (Potts: `field_solver`, `solvers`, …).
"""
function SciMLBase.remake(
        prob::PottsProblem; f = prob.f, u0 = prob.u0, tspan = prob.tspan, p = prob.p,
        seed = prob.seed,
        replica = prob.replica, repeat = prob.repeat, kwargs = missing, rest...
    )
    kept(k) = k in SOLVE_KEYWORDS || k in (:abstol, :reltol, :initializealg)
    solvekw = NamedTuple(k => v for (k, v) in rest if kept(k))
    other = NamedTuple(k => v for (k, v) in rest if !kept(k))
    base = kwargs === missing ? prob.kwargs : NamedTuple(kwargs)
    given = merge(kwargs === missing ? (;) : base, solvekw)
    haskey(given, :initializealg) && _remake_initializealg(prob, f, u0, given.initializealg)
    (haskey(prob.kwargs, :initializealg) && !haskey(base, :initializealg)) &&
        (base = merge(base, (; initializealg = prob.kwargs.initializealg)))
    kw = merge(base, solvekw)
    # no algorithm is stored as the constructor stores it: not at all
    (haskey(kw, :initializealg) && kw.initializealg === nothing) && (kw = _without_init(kw))
    return _remake(prob, f, u0, tspan, p, seed, replica, repeat, other, kw)
end

# a new `initializealg` at `remake`: a value the model can apply, and a new `u0` for it to
# initialize (the problem's own is accepted as it is)
function _remake_initializealg(prob, f, u0, a)
    check_initializealg(f.sys, a)
    (u0 === prob.u0 && !isequal(a, get(prob.kwargs, :initializealg, nothing))) && throw(
        ArgumentError(
            "remake: `initializealg` initializes a new state; give it with `u0` " *
                "(`remake(prob; u0 = op, initializealg)`): without one, nothing would be \
                    initialized again"
        )
    )
    return nothing
end

# `remake`, compiled once for every model: specialized on the problem's type it was
# 0.7–1.3 s of compile for every model, although the remade problem has the same type
Base.@nospecializeinfer function _remake(
        @nospecialize(prob::PottsProblem), @nospecialize(f), @nospecialize(u0),
        @nospecialize(tspan), @nospecialize(p), seed, replica, repeat,
        @nospecialize(kwargs::NamedTuple),
        @nospecialize(solvekw::NamedTuple)
    )
    relaid = prob.u0
    if !isempty(kwargs)
        f === prob.f || throw(
            ArgumentError(
                "remake: give `f` or the keywords it is rebuilt from " *
                    "($(join(("`$k`" for k in keys(kwargs)), ", "))), not both"
            )
        )
        f, relaid = remake_function(f.sys, prob; kwargs...)
    end
    tangent = prob.tangent
    if p !== prob.p
        pgiven = p
        p = remake_parameters(f.sys, prob, pgiven)
        check_field_parameters(f, p)
        tangent = remake_tangent(f.sys, prob, pgiven, p)
    end
    frozen = prob.frozen
    if u0 !== prob.u0
        u0 = remake_state(f.sys, prob, u0, solvekw)
        frozen = remake_frozen(f.sys, prob, u0)
        # (the initial fields' derivative parts were the old state's)
        tangent = without_initial(tangent)
    else
        u0 = relaid
    end
    return _problem(
        f, u0, prob.lattice, tspan, p, prob.contact,
        prob.proposal, prob.relations, prob.spacing, frozen,
        seed, replica, repeat, tangent, solvekw
    )
end

# A map given as the parameters of a problem without a model (`remake(prob; p = [:T =>
# 5.0])`): the fields of its `NamedTuple` parameter object by name; any other map is an
# `ArgumentError`
function remake_parameters(
        ::Nothing, prob, p::Union{
            AbstractDict, AbstractVector{<:Pair}, Tuple{Vararg{Pair}},
        }
    )
    prob.p isa NamedTuple || throw(
        ArgumentError(
            "remake: a parameter map needs a model or a NamedTuple parameter object; " *
                "this problem's is a $(nameof(typeof(prob.p))): give the new parameter \
                    object itself"
        )
    )
    kvs = collect(p)
    ks = [
        _index_name(SymbolicIndexingInterface.parameter_index(prob, first(kv)))
            for kv in kvs
    ]
    return SymbolicIndexingInterface.remake_buffer(
        prob, prob.p, ks, [
            last(kv)
                for kv in kvs
        ]
    )
end

Base.@kwdef mutable struct PottsStats
    mcs::Int = 0
    attempts::Int = 0
    accepted::Int = -1          # -1: not counted by this algorithm
    committed::Int = -1         # CheckerboardCPM only, else -1: copies committed
    launches::Int = 0
    refreshes::Int = 0          # frozen-mask recomputations (`refresh_frozen!`)
    # host↔device traffic (D-085; never counted on the CPU): explicit synchronizations,
    # host↔device array copies, and the bytes they moved
    syncs::Int = 0
    transfers::Int = 0
    transfer_bytes::Int = 0
    lifecycle::LifecycleStats = LifecycleStats()
    fields::FieldStats = FieldStats()       # the field solvers' counters (status words)
    ode_code::SciMLBase.ReturnCode.T = SciMLBase.ReturnCode.Default
    # Σ `f.track` over the committed copies (`CPMFunction(…; track)`, Potts `track =
    # (:energy_change,)`): `nothing` without a track. Exact after every step under
    # `SequentialCPM`; under `CheckerboardCPM` brought up to date at the host read points
    # (D-140)
    accepted_energy_change::Union{Nothing, Float64} = nothing
    # copies the `Global` veto refused only for want of window (D-197): `nothing` for
    # a model without `Global`, else an `Int` (always 0 on SequentialCPM, with or without
    # `skip_interior`, and without a window); under `CheckerboardCPM` brought up to date at
    # the host read points
    connectivity_deferred::Union{Nothing, Int} = nothing
end

"""
    SavedLeaves

The state leaves a run saves (`save_idxs`): the labels `ownership` when `ownership` is true,
and the named cell, site and model arrays.
"""
struct SavedLeaves
    ownership::Bool
    cell::Vector{Symbol}
    site::Vector{Symbol}
    model::Vector{Symbol}
end

"""
    PottsOptions

The options of a Potts run, `integ.opts`: the save times `saveat`, `save_start`, `save_end`,
`save_everystep`, the saved leaves `save_idxs` (a [`SavedLeaves`](@ref) or `nothing`: the
whole state), `maxiters` (the most MCS one `solve!` takes, counted from `init` or
`reinit!`), `verbose` (the run's warnings), `progress` (a progress log every
`progress_steps` MCS under `progress_name` and `progress_id`), the pending stops `tstops`
(sorted MCS, [`add_tstop!`](@ref SciMLBase.add_tstop!)), and the save times and stops given
to `init`, `saveat0` and `tstops0` (`reinit!` restores them, those in its time span).
"""
struct PottsOptions{A <: Real, R <: Real}
    saveat::Vector{Int}
    save_start::Bool
    save_end::Bool
    save_everystep::Bool
    save_idxs::Union{Nothing, SavedLeaves}
    maxiters::Int
    verbose::Bool
    progress::Bool
    progress_steps::Int
    progress_name::String
    progress_id::Symbol
    tstops::Vector{Int}
    saveat0::Vector{Int}
    tstops0::Vector{Int}
    abstol::A
    reltol::R
end

"""
    PottsIntegrator

The integrator of a [`PottsProblem`](@ref), a `SciMLBase.DEIntegrator`, made by `init`.

`step!` enqueues one MCS without synchronizing; `step!(integrator, n, true)` lands on MCS
`t + n`. A write into `integrator.u` takes effect from the next MCS; after one, call
`derivative_discontinuity!(integrator, true)` so that the frozen mask and the field groups
follow it.

`check_error(integrator)` is the cheap read of the run's health inside a callback:
`Success` while the run goes on, else the code that ended it. It reads a host field and
does not synchronize; a device failure is found at the next synchronization (a save, a
host read, the end of the run).

# Fields
- `t`: the current MCS.
- `u`: the live state. On a device it holds device arrays: read them with broadcasts or
  `Array`, or take a host copy with [`current_state`](@ref).
- `p`: the parameter object.
- `sol`: the solution so far.
- `opts`: the run's options (`PottsOptions`).
- `iter`: the number of MCS that this run took.
- `stats`: the run's statistics.

# Examples
```julia
integ = init(prob, SequentialCPM())
step!(integ, 10, true)
st = current_state(integ)
```

See also [`PottsSolution`](@ref), [`current_state`](@ref), [`refresh_frozen!`](@ref).
"""
mutable struct PottsIntegrator{
        Alg, Law, P, S, C, LCC, F, KF, Pa, Ctx, B, CB, MS, O <: PottsOptions,
    } <:
    SciMLBase.DEIntegrator{Alg, true, S, Int}
    const prob::P
    const alg::Alg
    const law::Law
    const state::S
    const cache::C
    const lcache::LCC
    const f::F
    const kf::KF
    p::Pa
    const ctx::Ctx
    const backend::B
    const key::RNGKey
    t::Int
    # the end of the time span (`reinit!(integ; tf)` moves it)
    tstop::Int
    const opts::O
    const saved_t::Vector{Int}
    const saved_u::Vector{Any}
    retcode::SciMLBase.ReturnCode.T
    const stats::PottsStats
    const callbacks::CB             # tuple of DiscreteCallbacks, checked after every MCS
    nmobile::Int                    # mobile sites: the attempts of one MCS
    # `MobileCounters` of the standard-rule refresh, or nothing
    const mscratch::MS
    iter::Int                       # the MCS this run took (`maxiters` counts them)
    # the end of the run was taken (`solve!`, or `done` of an iteration)
    finished::Bool
end

# Counts of the standard-rule refresh (D-081) run by `refresh_frozen!` and on the host
# lifecycle path: `device` = [unused, mobile-count change, changed sites], read into `host`
# at once. The device lifecycle (D-089) keeps its own counts on the device
# (`_fold_lifecycle!`).
struct MobileCounters{D, I}
    device::D
    host::Vector{I}             # I: `site_index_type` of the lattice (D-253)
end

# a total that is `nothing` when either part is not counted
_sum_or_nothing(a, b) = a + b
_sum_or_nothing(::Nothing, b) = nothing
_sum_or_nothing(a, ::Nothing) = nothing
_sum_or_nothing(::Nothing, ::Nothing) = nothing

# Ensemble statistics: totals over trajectories.
function Base.merge(a::PottsStats, b::PottsStats)
    l = LifecycleStats(;
        (
            f => getfield(a.lifecycle, f) + getfield(b.lifecycle, f)
                for f in fieldnames(LifecycleStats)
        )...
    )
    fs = FieldStats(;
        solves = a.fields.solves + b.fields.solves, budget = a.fields.budget +
            b.fields.budget,
        floor = a.fields.floor + b.fields.floor, newton_budget = a.fields.newton_budget +
            b.fields.newton_budget,
        code = _rank(b.fields.code) > _rank(a.fields.code) ? b.fields.code : a.fields.code
    )
    return PottsStats(;
        mcs = a.mcs + b.mcs, attempts = a.attempts + b.attempts,
        accepted = (a.accepted < 0 || b.accepted < 0) ? -1 : a.accepted + b.accepted,
        committed = (a.committed < 0 || b.committed < 0) ? -1 : a.committed + b.committed,
        launches = a.launches + b.launches, refreshes = a.refreshes + b.refreshes,
        syncs = a.syncs + b.syncs, transfers = a.transfers + b.transfers,
        transfer_bytes = a.transfer_bytes + b.transfer_bytes, lifecycle = l, fields = fs,
        ode_code = b.ode_code != SciMLBase.ReturnCode.Default ? b.ode_code : a.ode_code,
        accepted_energy_change = _sum_or_nothing(
            a.accepted_energy_change,
            b.accepted_energy_change
        ),
        connectivity_deferred = _sum_or_nothing(
            a.connectivity_deferred,
            b.connectivity_deferred
        )
    )
end

function _to_backend(backend, x)
    return Adapt.adapt(
        KernelAbstractions.allocate(backend, Int32, 0) |>
            typeof |> _array_adaptor, x
    )
end
_array_adaptor(::Type{<:Array}) = Array
_array_adaptor(A::Type) = Base.typename(A).wrapper

"""The copy neighborhood: the algorithm's if given, else the model's."""
_proposal(alg, prob) = something(alg.proposal, prob.proposal)

"""
    SOLVE_KEYWORDS

The keywords `solve` and `init` of a `PottsProblem` take (SciML's common keywords that have
a meaning on the MCS clock, and `backend` and `checkpoint`). Any other keyword is an
`ArgumentError` that lists these: a Monte Carlo sweep has no step size or truncation error,
so `dt` is refused. `abstol` and `reltol` are refused too, except for a problem whose field
phases use `LatticeNewton`, where they are accepted and stored in the run's options.
"""
const SOLVE_KEYWORDS = (
    :backend, :saveat, :save_start, :save_end, :save_everystep, :save_idxs, :tstops,
    :maxiters,
    :callback, :checkpoint, :seed, :rng, :verbose, :progress, :progress_steps,
    :progress_name,
    :progress_id, :alias, :dense,
)

# The problem's keywords and the call's, the call's taking precedence; a `callback` of both
# runs both (the problem's first), as DiffEqBase merges them
function _merge_kwargs(pk::NamedTuple, kw::NamedTuple)
    m = merge(pk, kw)
    (
        haskey(pk, :callback) && haskey(kw, :callback) && pk.callback !== nothing &&
            kw.callback !== nothing
    ) &&
        (m = merge(m, (; callback = SciMLBase.CallbackSet(pk.callback, kw.callback))))
    return m
end

function _without_init(kw::NamedTuple)
    return NamedTuple(k => v for (k, v) in pairs(kw) if k !== :initializealg)
end

# `initializealg` at `init`/`solve`: the problem's own (no algorithm and `OverrideInit()`
# are the same default) or `NoInit()`, both no-ops; any other is refused, since the state
# was initialized when the problem was built
function _check_initializealg(prob, a)
    _default_init(x) = x === nothing || x == SciMLBase.OverrideInit()
    own = get(prob.kwargs, :initializealg, nothing)
    (
        a isa SciMLBase.NoInit || isequal(a, own) ||
            (_default_init(a) && _default_init(own))
    ) && return nothing
    throw(
        ArgumentError(
            "`solve`/`init` of a PottsProblem: `initializealg = $a` differs from the " *
                "problem's ($(something(own, "the default"))); the state is initialized " *
                "when the problem is built: give it to `PottsProblem(sys, op, tspan; \
                    initializealg)` or `remake(prob; u0, initializealg)`"
        )
    )
end

function _check_keywords(kw::NamedTuple, prob)
    ln = _uses_lattice_newton(prob.f.phases)
    bad = [
        k
            for k in keys(kw)
            if !(k in SOLVE_KEYWORDS) && !(ln && k in (:abstol, :reltol)) &&
            k !== :_rng_seeds
    ]
    isempty(bad) && return nothing
    if !ln && any(in((:abstol, :reltol)), bad) && _has_implicit_field_phase(prob.f.phases)
        tolbad = filter(in((:abstol, :reltol)), bad)
        throw(
            ArgumentError(
                string(
                    "`solve`/`init` of a PottsProblem: the keyword", if length(tolbad) == 1
                        " "
                    else
                        "s "
                    end,
                    join(("`$k`" for k in tolbad), ", "),
                    length(tolbad) == 1 ? " is" : " are ",
                    "ignored under automatic `nlsolve = nothing` (which uses a fixed 1e-3 \
                        ∞-norm test); ",
                    "pass `nlsolve = LatticeNewton()` on `field_solver` to use \
                        `abstol`/`reltol`"
                )
            )
        )
    end
    throw(
        ArgumentError(
            string(
                "`solve`/`init` of a PottsProblem: the keyword",
                length(bad) == 1 ? " " : "s ",
                join(("`$k`" for k in bad), ", "), length(bad) == 1 ? " is" : " are",
                " not one of its keywords ",
                "(time is the integer MCS: a sweep has no step size or tolerance); its \
                    keywords are ",
                join(("`$k`" for k in SOLVE_KEYWORDS), ", ")
            )
        )
    )
end

"""
    init(prob::PottsProblem, alg::AbstractCPMAlgorithm; backend = CPU(), saveat = [],
         save_start = true, save_end = true, save_everystep = nothing, save_idxs = nothing,
         tstops = [], maxiters = typemax(Int), callback = nothing, checkpoint = nothing,
         seed = nothing, rng = nothing, verbose = true, progress = false,
         progress_steps = 1000, progress_name = "CPM", progress_id = :CorePotts,
         alias = nothing, dense = false, abstol = nothing, reltol = nothing)
    solve(prob::PottsProblem, alg::AbstractCPMAlgorithm; kwargs...)

The integrator (or the solution) of a Potts run, with SciML's common keywords on the MCS
clock:

- Saving: `saveat` (MCS, or a number: every that many MCS from `t0`), `save_start`,
  `save_end`, `save_everystep` (every MCS; `nothing` means `isempty(saveat)`, as SciML).
  A saved state is a host copy of the whole state, so a run whose saves would hold more than
  2 GiB warns: give `saveat`, `save_everystep = false` or `save_idxs`. `save_idxs` names the
  state leaves to save (`:ownership`, cell, site or model array names, or the model's state
  variables); the saved states hold only those.
- `tstops`: MCS the run must stop at (each MCS is a stop already; `step!(integ, n, true)`
  and DiffEqCallbacks' timed callbacks add them). Only the stops `t0 < t ≤ tf` are kept, as
  in OrdinaryDiffEq; a stop added during the run with `add_tstop!` may lie past `tf`, and
  `solve!` then runs on to it.
- `maxiters`: the most MCS one `solve!` takes before it ends with `ReturnCode.MaxIters`,
  counted from `init` (or `reinit!`).
- `seed` replaces `prob.seed` for this run; `rng` draws the run's seed from it
  (`SciMLBase.supports_solve_rng` is true).
- `verbose = false` silences the warnings of `init` and `solve!`; `progress = true` logs the
  progress (SciML's progress logging).
- `alias`: accepted; the state is always copied.
- `dense`: only `false` (no interpolation between MCS).
- `backend`: the KernelAbstractions backend the run executes on; `checkpoint`: a
  [`PottsCheckpoint`](@ref) to continue.
- `abstol`, `reltol`: only for a problem whose field phases use `LatticeNewton` (defaults
  `1//10^6` and `1//10^3`; both zero is an `ArgumentError`).

Any other keyword is an `ArgumentError` listing these (`SOLVE_KEYWORDS`). The
problem's `kwargs` are merged in first (except the problem's `initializealg`, which its
symbolic layer used when it built the state). `initializealg` is accepted when it is the
problem's own or `NoInit()`, and changes nothing: the state was initialized when the problem
was built. Any other is an `ArgumentError`: give it to the problem
(`PottsProblem(sys, op, tspan; initializealg)` or `remake(prob; u0, initializealg)`).
"""
function CommonSolve.init(prob::PottsProblem, alg::AbstractCPMAlgorithm; kwargs...)
    call = NamedTuple(kwargs)
    haskey(call, :initializealg) && _check_initializealg(prob, call.initializealg)
    kw = _merge_kwargs(_without_init(prob.kwargs), _without_init(call))
    _check_keywords(kw, prob)
    return _init_kw(prob, alg; kw...)
end

function _init_kw(
        prob::PottsProblem, alg::AbstractCPMAlgorithm; backend = CPU(),
        saveat = Int[], save_start::Bool = true,
        save_end::Bool = true, save_everystep::Union{Nothing, Bool} = nothing,
        save_idxs = nothing, tstops = Int[],
        maxiters::Integer = typemax(Int), callback = nothing, checkpoint = nothing,
        seed = nothing, rng = nothing,
        verbose::Bool = true, progress::Bool = false, progress_steps::Integer = 1000,
        progress_name = "CPM",
        progress_id = :CorePotts, alias = nothing, dense::Bool = false, abstol = nothing,
        reltol = nothing, _rng_seeds::Bool = true
    )
    atol, rtol = Problems.resolve_tols(abstol, reltol)
    dense && throw(
        ArgumentError(
            "`dense = true`: a Potts solution has no interpolation between MCS (a label " *
                "field has no meaningful interpolant); `sol(t)` looks up the saved MCS. \
                    Save the MCS you need with `saveat`"
        )
    )
    alias === nothing || alias isa Bool || alias isa SciMLBase.AbstractAliasSpecifier ||
        throw(
        ArgumentError(
            "`alias` is a Bool or a SciMLBase alias specifier; got a $(typeof(alias))"
        )
    )
    seed === nothing || rng === nothing || throw(
        ArgumentError("give `seed` or `rng` (which draws the run's seed), not both")
    )
    maxiters > 0 || throw(ArgumentError("`maxiters` must be positive; got $maxiters"))
    progress_steps > 0 ||
        throw(ArgumentError("`progress_steps` must be positive; got $progress_steps"))
    rng !== nothing && _rng_seeds && (seed = rand(rng, UInt64))
    if save_everystep === nothing
        save_everystep = isempty(saveat)            # SciML's default
        save_everystep && verbose && !(backend isa CPU) && _hint_device_saves()
    end
    if seed !== nothing
        checkpoint === nothing || throw(
            ArgumentError("a checkpoint continues its own random stream: give `seed` or \
                `rng`, or `checkpoint`, not both")
        )
        prob = remake(prob; seed)
    end
    o = (;
        saveat, save_start, save_end, save_everystep, save_idxs,
        tstops, maxiters = Int(maxiters), verbose, progress,
        progress_steps = Int(progress_steps), progress_name = string(progress_name),
        progress_id = Symbol(progress_id),
        abstol = atol, reltol = rtol,
    )
    verbose || return Base.ScopedValues.with(Exec.VERBOSE => false) do
        _init_run(prob, alg, backend, checkpoint, callback, o)
    end
    return _init_run(prob, alg, backend, checkpoint, callback, o)
end

function _init_run(prob, alg, backend, checkpoint, callback, o)
    if checkpoint !== nothing
        prob = _from_checkpoint(prob, checkpoint)
        # the accumulator continues only into an equally tracked run (a hand-written model
        # may keep fingerprint 0 whatever its track, so this is checked here too)
        (checkpoint.stats.accepted_energy_change === nothing) ==
            (prob.f.track === nothing) || throw(
            ArgumentError(
                "checkpoint was taken with tracking " *
                    "$(
                    checkpoint.stats.accepted_energy_change === nothing ? "off" : "on"
                ) " *
                    "but the problem has tracking " *
                    "$(prob.f.track === nothing ? "off" : "on"); continue it in a " *
                    "problem with the same `track`"
            )
        )
        # a restored state is no fresh one: its at-init phases skip the field clamps (D-145)
        integ = _init(prob, alg, false, backend, _options(prob, o), callback)
        _restore_stats!(_stats(integ), checkpoint.stats)
        return integ
    end
    return _init(prob, alg, true, backend, _options(prob, o), callback)
end

# The run's options at the problem's time span (a checkpoint's span starts at its MCS)
function _options(@nospecialize(prob::PottsProblem), o::NamedTuple)
    t0, t1 = prob.tspan
    # SciML convention: a number means "every Δ MCS" from t0 (t0 itself is `save_start`)
    saveat = _saveat_list(o.saveat, t0, t1)
    outside = filter(t -> !(t0 <= t <= t1), saveat)
    isempty(outside) || !o.verbose ||
        @warn "saveat times outside tspan $(prob.tspan) are never reached: $outside"
    tstops = _tstops_list(o.tstops)
    leaves = _saved_leaves(prob, o.save_idxs)
    o.verbose &&
        _warn_large_saves(prob, saveat, o.save_start, o.save_end, o.save_everystep, leaves)
    return PottsOptions(
        saveat, o.save_start, o.save_end, o.save_everystep,
        leaves, o.maxiters, o.verbose, o.progress,
        o.progress_steps, o.progress_name, o.progress_id, _in_span(tstops, t0, t1),
        copy(saveat), tstops,
        o.abstol, o.reltol
    )
end

# the save times of `saveat` over `t0..t1`: a number means "every Δ MCS" from t0, as in
# SciML (t0 itself is `save_start`)
function _saveat_list(saveat, t0, t1)
    saveat isa Number || return sort!(Int[_mcs(s, "saveat") for s in saveat])
    Δ = _mcs(saveat, "saveat")
    Δ > 0 ||
        throw(ArgumentError("`saveat`: a step of $Δ MCS; give a positive number of MCS"))
    return collect((t0 + Δ):Δ:t1)
end
# the stops given, sorted and once each
function _tstops_list(tstops)
    return sort!(
        unique!(Int[_mcs(s, "tstops") for s in (tstops isa Number ? (tstops,) : tstops)])
    )
end
# the stops of a run over `t0..t1`: those with `t0 < t ≤ t1` (OrdinaryDiffEq's rule)
_in_span(tstops, t0, t1) = filter(t -> t0 < t <= t1, tstops)

# a time on the MCS clock: an integer (or an integer-valued number)
function _mcs(t, what)
    (t isa Real && isinteger(t)) || throw(
        ArgumentError("`$what`: time is the integer MCS; got $(repr(t))")
    )
    return Int(t)
end

# `save_idxs`: the leaves to save, or `nothing` (the whole state)
_saved_leaves(prob, ::Nothing) = nothing
function _saved_leaves(prob, idxs)
    u = prob.u0
    ownership, cell, site, model = false, Symbol[], Symbol[], Symbol[]
    for x in (idxs isa Union{AbstractVector, Tuple} ? idxs : (idxs,))
        i = _leaf(prob, x)
        if i === :ownership
            ownership = true
        else
            if i.scope === :cell
                push!(cell, i.name)
            elseif i.scope === :site
                push!(site, i.name)
            else
                push!(model, i.name)
            end
        end
    end
    return SavedLeaves(ownership, unique!(cell), unique!(site), unique!(model))
end
# one entry of `save_idxs`: `:ownership`, a `StateIndex`, an array name of the state, or a
# state variable of the model
function _leaf(prob, x)
    x === :ownership && return :ownership
    x isa StateIndex && return x
    u = prob.u0
    if x isa Symbol
        hits = [
            StateIndex(s, x)
                for s in (:cell, :site, :model) if haskey(getfield(u, s), x)
        ]
        length(hits) == 1 && return only(hits)
    elseif SymbolicIndexingInterface.is_variable(prob, x)
        i = SymbolicIndexingInterface.variable_index(prob, x)
        i isa StateIndex && return i
    end
    throw(
        ArgumentError(
            "save_idxs: `$x` is not a state leaf of the problem; " *
                "give `:ownership`, a cell, site or model array name (" *
                "$(
                join(Iterators.flatten((keys(u.cell), keys(u.site), keys(u.model))), ", ")
            )) " *
                "or a state variable"
        )
    )
end

# a host copy of the leaves `l` of the host state `u` (all of it for `nothing`)
_select(u, ::Nothing) = u
function _select(u, l::SavedLeaves)
    return CPMState(
        l.ownership ? u.ownership : nothing, _pick(u.cell, l.cell), _pick(u.site, l.site),
        _pick(
            u.model, l.model
        ), (;)
    )
end
function _pick(nt::NamedTuple, names::Vector{Symbol})
    return NamedTuple{Tuple(names)}(map(n -> getfield(nt, n), Tuple(names)))
end

# a device run that saves every MCS by default copies the whole state to the host after each
# MCS: a hint, once per session
@noinline function _hint_device_saves()
    return @info string(
        "this device run saves every MCS (`save_everystep` defaults to `isempty(saveat)`, \
            as in SciML), ",
        "a host copy of the state each time; pass `saveat` or `save_everystep = false` to \
            save less"
    ) maxlog = 1
end
function _warn_large_saves(prob, saveat, save_start, save_end, everystep, leaves)
    t0, t1 = prob.tspan
    n = if everystep
        t1 - t0 + save_start
    else
        count(t -> t0 <= t <= t1, saveat) + save_start + save_end
    end
    n <= 2 && return false
    bytes = n * Base.summarysize(_select(prob.u0, leaves))
    bytes > Problems.LARGE_SAVE_BYTES || return false
    @warn string(
        "this run saves ", n, " states, about ", round(bytes / 2^30; digits = 1),
        " GiB on the host",
        everystep ?
            " (every MCS: `save_everystep` is true when `saveat` is empty, as in \
                SciML)" : "",
        ". Give `saveat` (the MCS to keep), `save_everystep = false` or `save_idxs` (the \
            leaves to keep)"
    ) maxlog = 1
    return true
end

"""
    init(prob::PottsProblem; backend = CPU(), kwargs...)
    solve(prob::PottsProblem; backend = CPU(), kwargs...)

Without an algorithm: `SequentialCPM()` on the CPU. A device backend has no default,
since `SequentialCPM` is CPU-only. Pass `CheckerboardCPM()` there; anything else throws an
`ArgumentError` that says so.
"""
function CommonSolve.init(prob::PottsProblem; backend = CPU(), kwargs...)
    backend isa CPU || throw(
        ArgumentError(
            "no default algorithm on the $(nameof(typeof(backend))) " *
                "backend: pass one explicitly, e.g. `solve(prob, CheckerboardCPM(); " *
                "backend)` (SequentialCPM, the CPU default, runs only on the CPU)"
        )
    )
    return CommonSolve.init(prob, SequentialCPM(); backend, kwargs...)
end
function CommonSolve.solve(prob::PottsProblem; kwargs...)
    return CommonSolve.solve!(CommonSolve.init(prob; kwargs...))
end

# A problem built in Float64 that runs on a device backend (V11): the backend given only to
# `solve`/`init`, not to the symbolic layer's problem constructor (which would build in the
# backend's default float, Float32 on a device). A notice, not an error: Float64 on a device
# that has it (ROCm, CUDA) is a valid, slower run, and a backend without Float64 refuses at
# compile with its own message. Once per session.
_holds_float64(x::AbstractArray) = eltype(x) <: Float64
_holds_float64(x::Float64) = true
_holds_float64(x::NamedTuple) = any(_holds_float64, values(x))
_holds_float64(x) = false
_parameter_tuple(p::NamedTuple) = p
_parameter_tuple(p) = applicable(NamedTuple, p) ? NamedTuple(p) : (;)
function _float64_problem(prob::PottsProblem)
    u = prob.u0
    return _holds_float64(u.cell) || _holds_float64(u.site) || _holds_float64(u.model) ||
        _holds_float64(_parameter_tuple(prob.p))
end
function _device_float_notice(prob::PottsProblem, backend)
    (Exec.ishost(backend) || !_float64_problem(prob)) && return false
    @warn string(
        "this problem was built in Float64 and runs on the ", nameof(typeof(backend)),
        " backend: Float64 device code is several times slower than Float32 on most GPUs. \
            Give the ",
        "backend to the problem as well (`PottsProblem(sys, op, tspan; backend)` builds \
            in the ",
        "backend's float type, Float32 on a device). The run itself is unchanged; this \
            notice shows once"
    ) maxlog = 1
    return true
end

# The host setup of a run, inferred and compiled once for every model: the problem,
# the algorithm, `saveat` and the callbacks are not specialized on, so each call below is a
# dynamic dispatch that compiles only that callee for the model's types (the setup runs once
# per run; `step!` and the kernels stay fully specialized). Specialized on the model, this
# body was 0.3–0.9 s of inference for every model (measured).
Base.@nospecializeinfer function _init(
        @nospecialize(prob::PottsProblem), @nospecialize(alg::AbstractCPMAlgorithm),
        fresh::Bool,
        backend, opts::PottsOptions, @nospecialize(callback)
    )
    check_algorithm(prob.f.sys, alg)
    alg isa SequentialCPM && !(backend isa CPU) &&
        throw(ArgumentError("SequentialCPM runs on the host; use CheckerboardCPM \
            on $(typeof(backend))"))
    lat = prob.lattice
    _device_float_notice(prob, backend)
    _check_convert_atomics(backend, prob.u0)
    ctx = (;
        lattice = _to_backend(backend, lat), proposal = relation(_proposal(alg, prob), lat),
        contact = prob.contact,
        mobility = _backend_mobility(backend, mobility(prob.frozen, lat)),
        prob.relations...,
    )
    prob.spacing === nothing || (ctx = merge(ctx, (; spacing = prob.spacing)))
    # whole-cell connectivity: the flood scratch and the evaluation mode; nothing otherwise
    ctx = merge(
        ctx,
        connectivity_ctx(
            backend, prob.f, lat, alg isa CheckerboardCPM ? GlobalBoard() :
                GlobalExact()
        )
    )
    # the lockless checkerboard: commit hooks add their changes atomically (`_lockless`)
    alg isa CheckerboardCPM && (ctx = merge(ctx, (; lockless = true)))
    _preflight(prob, alg, ctx)
    _check_frozen_hooks(prob.f.sys)
    _custom_frozen(prob.f.sys) && _frozen_reads(prob.f.sys, prob.u0)
    state = _to_backend(backend, deepcopy(prob.u0))
    p = _to_backend(backend, prob.p)
    # the trajectory's launch state of its phases (field steps bind to the state's arrays)
    ctx = merge(
        ctx,
        phase_contexts(
            prob.f.phases, state, p, backend; abstol = opts.abstol, reltol = opts.reltol
        )
    )
    # a problem with derivative parts: the shadow tangent store of the field phases
    ctx = with_tangent(ctx, prob.tangent, prob.f.phases, state, p, backend, fresh)
    cache = alg isa CheckerboardCPM ?
        CheckerboardCache(
            backend, lat, prob.f, relation(_proposal(alg, prob), lat);
            alg.region, alg.parts, alg.switches,
            alg.threads, alg.inline_max_blocks, min_read = _copy_step_reach(prob, ctx),
            cell = state.cell
        ) :
        _skips_interior(alg) ?
        BoundaryCache(state.ownership, ctx.mobility, ctx.lattice, ctx.proposal) :
        nothing
    _check_repeat(prob.f.phases, alg, cache)
    key = RNGKey(prob.seed, prob.replica, prob.repeat)
    fused_limits = _fused_lifecycle_limits(alg)
    lcache = prob.f.lifecycle === nothing ? nothing :
        LifecycleCache(backend, ndims(lat), ncells(prob.u0), state; fused_limits)
    integ = PottsIntegrator(
        prob, alg, _device_law(_law(alg, prob.f), backend), state, cache,
        lcache, prob.f, device_functions(prob.f), p, ctx, backend, key,
        prob.tspan[1], prob.tspan[2], opts, Int[], Any[],
        SciMLBase.ReturnCode.Default, _initial_stats(prob.f),
        _callbacks(callback), prob.frozen === nothing ? nsites(lat) : count(!, prob.frozen),
        _mobility_scratch(backend, prob, ctx.mobility), 0, false
    )
    # compile the handler of each MCS entry before `step!` is compiled: if `step!` is
    # inferred while a field-step entry's handler is still in an inference cycle, the call
    # stays dynamic and boxes the entry (16 B per MCS, Merks Float32 under CheckerboardCPM)
    _each(e -> precompile(_run_entry!, (typeof(integ), typeof(e))), prob.f.phases.mcs)
    _stats(integ).launches += run_phases(
        fresh ? prob.f.phases.at_init : derived(prob.f.phases.at_init), integ.state,
        integ.p, integ.ctx,
        integ.key, integ.t, integ.backend, _stats(integ)
    )
    _start_failed!(integ)
    _each(cb -> cb.initialize(cb, integ.state, integ.t, integ), integ.callbacks)
    opts.save_start && _save!(integ)
    return integ
end

# SciML callbacks: `DiscreteCallback`s (alone or in a `CallbackSet`) are checked at every
# MCS boundary, after the lifecycle and before saving. `condition(u, t, integrator)` and
# `affect!(integrator)` see the live state (`integrator.u`, on the device for GPU backends).
# Continuous callbacks have no meaning for an MCS clock (D-287 X2).
_callbacks(::Nothing) = ()
_callbacks(cb::SciMLBase.DiscreteCallback) = (cb,)
function _callbacks(cb::SciMLBase.CallbackSet)
    isempty(cb.continuous_callbacks) ||
        throw(ArgumentError("continuous callbacks are not supported by Potts integrators \
            (time is the integer MCS); use DiscreteCallback"))
    return cb.discrete_callbacks
end
function _callbacks(cb)
    throw(
        ArgumentError(
            "unsupported callback $(typeof(cb)); use DiscreteCallback or CallbackSet"
        )
    )
end

# `f(x)` for each element `x` of the tuple `t`, in order, each call specialized on its own
# element type, at any length: `ntuple` with `Val(N)` unrolls (Base generates the calls; no
# recursion here). The closure is `@inline` so that each unrolled call sees its constant
# index and `t[i]` its concrete type; not inlined, `t[i]` dispatches dynamically and
# allocates. A `for` loop over a heterogeneous tuple carries a `Union` of the element types,
# and `Base.afoldl` beyond 31 elements calls itself dynamically. For a CallbackSet of
# differently typed callbacks (closures and a BitVector next to bits fields), Julia 1.12's
# optimized code for that loop corrupted the GC heap (segfaults in a later `_save!` with
# `saveat`).
function _each(f::F, t::Tuple{Vararg{Any, N}}) where {F, N}
    (ntuple(@inline(i -> (f(t[i]); nothing)), Val(N)); nothing)
end

function _apply_callbacks!(integ::PottsIntegrator)
    _each(
        cb -> (cb.condition(integ.state, integ.t, integ) && _fire!(integ, cb); nothing),
        integ.callbacks
    )
    return nothing
end
# The saving of a callback that fires, as SciML's (DiffEqBase `apply_discrete_callback!`): a
# `saveat` MCS is saved before the first affect at it, then the state before the affect
# (`save_positions[1]`, unless that save was just made) and after it (`save_positions[2]`).
function _fire!(integ::PottsIntegrator, cb)
    at = _saveat_due(integ)
    at && (_check_status!(integ); _save!(integ))
    cb.save_positions[1] && !at && _save!(integ)
    cb.affect!(integ)
    cb.save_positions[2] && _save!(integ)
    return nothing
end
# the MCS is a `saveat` time not saved yet (nothing is saved at an MCS before its callbacks
# run)
function _saveat_due(integ::PottsIntegrator)
    return insorted(integ.t, integ.opts.saveat) &&
        (isempty(integ.saved_t) || last(integ.saved_t) != integ.t)
end
# a save is due after the MCS: a `saveat` time, or every MCS (`save_everystep`)
function _save_due(integ::PottsIntegrator)
    return (integ.opts.save_everystep || insorted(integ.t, integ.opts.saveat)) &&
        (isempty(integ.saved_t) || last(integ.saved_t) != integ.t)
end

# `derivative_discontinuity!(integ, true)` after writing the state (what a callback's affect
# does): the frozen mask follows (D-081) and the field groups' algorithms take the state as
# a start (`reset!`: Crank–Nicolson damps its next substep, BDF2 restarts with a Backward
# Euler substep). SciMLBase forwards its deprecated `u_modified!` here.
function SciMLBase.derivative_discontinuity!(integ::PottsIntegrator, modified::Bool)
    modified && (refresh_frozen!(integ); reset_fields!(integ.ctx))
    return nothing
end

"""
    copy_step_relations(sys, f::CPMFunction)

Return the names of the problem's relations that the copy-step functions of `f` read, or
`nothing` for every relation.

The copy-step functions are `delta_H`, `commit!`, `constraint`, `temperature`, `bias`,
`track` and the connectivity hooks. The default is `nothing`, for a hand-built
`CPMFunction`. A symbolic layer that knows the reads of the functions it generated extends
it (Potts does). It must return `nothing` when `f` carries a function it did not generate
(one swapped in by `remake(prob; f = …)`), since that one may read any relation.
`CheckerboardCPM`'s spacing covers the reach of these relations only.

# Arguments
- `sys`: the model description (`f.sys`).
- `f::CPMFunction`: the model functions.

# Returns
- A collection of `Symbol`s, or `nothing`.

See also [`CPMFunction`](@ref).
"""
copy_step_relations(sys, f) = nothing

"""
    check_algorithm(sys, alg) -> nothing

Throw an `ArgumentError` when the model `sys` cannot run under the algorithm `alg`.

`init` and `solve` call it before anything else. The default accepts every algorithm. A
symbolic layer extends it for the models whose generated code only one algorithm executes
correctly (Potts does, for energies over three consecutive chain members, which only
`SequentialCPM` evaluates exactly).

# Arguments
- `sys`: the model description (`f.sys`).
- `alg::AbstractCPMAlgorithm`: the algorithm.

# Returns
- `nothing`.

See also [`copy_step_relations`](@ref copy_step_relations).
"""
check_algorithm(sys, alg) = nothing

"""
Reject combinations no algorithm can execute correctly. (The checkerboard spacing covers the
declared footprint and everything the copy step reads, `_copy_step_reach`: the contact
neighborhood and the relations the copy-step functions read, `copy_step_relations`, every
relation by default. A relation read only at the MCS boundary does not count.)
"""
function _preflight(prob::PottsProblem, alg::AbstractCPMAlgorithm, ctx)
    prob.f.lifecycle === nothing || haskey(prob.u0.cell, :m1) ||
        throw(ArgumentError("a lifecycle needs the moment trackers: add `init_moments(σ, \
            lattice, capacity)` to the cell state"))
    haskey(ctx, :surface) && has_origin(ctx.surface) &&
        throw(ArgumentError("the surface relation must not include the origin: pass a \
            neighbor relation without offset zero (such as `VonNeumann(1)` or `Moore(1)`)"))
    # the pair-energy deltas assume unordered bonds: every offset needs its negation
    for name in (:contact, :surface)
        haskey(ctx, name) && !is_symmetric(getfield(ctx, name)) && throw(
            ArgumentError(
                "the $name relation is not symmetric (each offset needs its negation " *
                    "with the same weight); an asymmetric relation gives a ΔH that is not \
                        an energy difference"
            )
        )
    end
    return nothing
end

# the read distance the checkerboard spacing must cover beyond the declared footprint: the
# contact relation and the relations the copy step reads (all of them when unknown)
function _copy_step_reach(prob::PottsProblem, ctx)
    return max(
        radius(ctx.contact),
        _copy_reach(prob.relations, copy_step_relations(prob.f.sys, prob.f))
    )
end

# the largest radius of the relations the copy step reads (all of them for `nothing`)
_copy_reach(relations, ::Nothing) = maximum(radius, values(relations); init = 0)
function _copy_reach(relations, names)
    return maximum(
        k -> k in names ? radius(getfield(relations, k)) : 0, keys(relations);
        init = 0
    )
end

"""
    current_state(integ::PottsIntegrator) -> CPMState

Return a host snapshot of the integrator's current state.

The snapshot is independent of the live state on every backend (`Adapt.adapt(Array, …)`
alone would alias host arrays). It synchronizes the device and is counted in
`integ.stats`. It is a host read point: the device lifecycle's statistics and frozen-mask
counts are folded into `integ.stats`. For a run with derivative parts, the fields of the
snapshot carry them as `Dual`s. The live state is `integ.u`.

# Arguments
- `integ::PottsIntegrator`: the integrator.

# Returns
- `CPMState`: a host copy.

# Examples
```julia
integ = init(prob, SequentialCPM())
step!(integ, 10, true)
volumes(current_state(integ))
```

See also [`PottsIntegrator`](@ref).
"""
function current_state(integ::PottsIntegrator)
    sync!(_stats(integ), integ.backend)
    _fold_lifecycle!(integ)
    _fold_track!(integ)
    _fold_deferred!(integ)
    _fold_counts!(integ)
    snap = snapshot(_stats(integ), integ.backend, integ.state)
    # (a run with derivative parts: its fields as Duals)
    return tangent_snapshot(_stats(integ), integ.ctx, snap)
end

# SciML's integrator properties: `u` the live state (D-287 R5), `sol` the solution so far,
# `tdir` the direction of time, `ps` the parameters
function Base.getproperty(integ::PottsIntegrator, name::Symbol)
    name === :u && return getfield(integ, :state)
    name === :ps && return SymbolicIndexingInterface.ParameterIndexingProxy(integ)
    name === :tdir && return 1
    name === :sol && return invokelatest(PottsSolution, integ)
    # a read of `integ.stats`: on a device the field groups' status words are read first
    # (one synchronization), so `integ.stats.fields` counts every window so far, as
    # `field_stats` does; the solver itself reads `_stats(integ)`
    name === :stats && !Exec.ishost(getfield(integ, :backend)) &&
        _read_statuses!(_stats(integ), getfield(integ, :ctx))
    return getfield(integ, name)
end
function Base.propertynames(integ::PottsIntegrator)
    return (fieldnames(typeof(integ))..., :u, :ps, :tdir, :sol)
end
# the run's statistics without a status read (every internal use)
_stats(integ) = getfield(integ, :stats)

# Symbolic reads of an integrator (`integ[x]`, `getu(integ, x)`) read a host copy of the
# state, on every backend: the values at the integrator's MCS, which a later step does not
# change
SymbolicIndexingInterface.state_values(integ::PottsIntegrator) = current_state(integ)

# `integ[p]` and `integ[p] = v` of a parameter (a kind table too; a list naming one): an
# error with SciML's route, `integ.ps[p]` (before: SciMLBase's "Indexing with parameters is
# deprecated" error). States, fields, inputs and observed quantities index as before.
function _parameter_route(integ::PottsIntegrator, sym, write::Bool)
    SII = SymbolicIndexingInterface
    if sym isa Union{AbstractArray, Tuple} && SII.symbolic_type(sym) === SII.NotSymbolic()
        foreach(s -> _parameter_route(integ, s, write), sym)
        return nothing
    end
    # a computed parameter reads as observed; a write names it with its routes
    write && (m = _readonly(integ, sym); m === nothing || throw(ArgumentError(m)))
    SII.is_parameter(integ, sym) || return nothing
    t = sym isa Symbol ? repr(sym) : string(sym)
    route = write ? "write `integ.ps[$t] = v`" : "read `integ.ps[$t]`"
    throw(
        ArgumentError(
            string(
                "`", lstrip(t, ':'), "` is a parameter: ", route,
                " (SciML's convention: an integrator indexes states, `integ.ps` its \
                    parameters)"
            )
        )
    )
end
function Base.getindex(integ::PottsIntegrator, sym)
    _parameter_route(integ, sym, false)
    return invoke(Base.getindex, Tuple{SciMLBase.DEIntegrator, Any}, integ, sym)
end
function Base.getindex(integ::PottsIntegrator, sym::Union{AbstractArray, Tuple})
    _parameter_route(integ, sym, false)
    return invoke(
        Base.getindex, Tuple{SciMLBase.DEIntegrator, Union{AbstractArray, Tuple}},
        integ, sym
    )
end
function Base.setindex!(integ::PottsIntegrator, v, sym)
    _parameter_route(integ, sym, true)
    return invoke(Base.setindex!, Tuple{SciMLBase.DEIntegrator, Any, Any}, integ, v, sym)
end
function Base.setindex!(integ::PottsIntegrator, v, sym::Union{AbstractArray, Tuple})
    _parameter_route(integ, sym, true)
    return invoke(
        Base.setindex!,
        Tuple{SciMLBase.DEIntegrator, Any, Union{AbstractArray, Tuple}}, integ, v, sym
    )
end

function _save!(integ::PottsIntegrator)
    push!(integ.saved_t, integ.t)
    l = integ.opts.save_idxs
    u = current_state(integ)
    # (a part of the state: its type follows the names given at run time, so the selection
    # is a dynamic call, kept out of the compiled MCS loop)
    push!(integ.saved_u, l === nothing ? u : invokelatest(_select, u, l))
    return nothing
end

# a steady start (`init = :steady`) that failed ends the run before its first MCS
function _start_failed!(integ)
    (
        (c = _phase_failed_code(_stats(integ))) != SciMLBase.ReturnCode.Default &&
            (integ.retcode = c);
        nothing
    )
end
# a field or adaptive-ODE code that ends the run
function _fields_failed(c::SciMLBase.ReturnCode.T)
    return c == SciMLBase.ReturnCode.ConvergenceFailure || c ==
        SciMLBase.ReturnCode.Unstable
end
function _phase_failed_code(stats::PottsStats)
    stats.ode_code != SciMLBase.ReturnCode.Default && return stats.ode_code
    _fields_failed(stats.fields.code) && return stats.fields.code
    return SciMLBase.ReturnCode.Default
end
function _check_status!(integ::PottsIntegrator)
    _status_failure!(integ, _model_status(_stats(integ), integ.state.model))
    _check_reduce_status!(_stats(integ), integ.state, integ.t, integ.backend)
    # the field groups' status words (on the host they are read after every window already)
    Exec.ishost(integ.backend) || _read_statuses!(_stats(integ), integ.ctx)
    (c = _phase_failed_code(_stats(integ))) != SciMLBase.ReturnCode.Default &&
        integ.retcode == SciMLBase.ReturnCode.Default && (integ.retcode = c)
    integ.alg isa CheckerboardCPM || return integ.retcode
    st = _readback(_stats(integ), integ.cache.status)
    _status_failure!(integ, st)
    return integ.retcode
end

# A nonzero status word fails the run, with a warning naming each reason (once per run)
const _STATUS_REASONS = (
    STATUS_NONFINITE => "an energy change was not finite (NaN or Inf)",
    STATUS_DRAW_EXHAUSTED => "a bounded randn(μ, σ; lower_bound) draw exhausted \
        its $MAX_DRAW_ATTEMPTS attempts",
    STATUS_DRAW_NEGATIVE_SD => "a bounded randn(μ, σ; lower_bound) draw was given σ < 0",
)
function _status_failure!(integ, st::UInt32)
    st == 0 && return nothing
    code = _status_code(st)
    if integ.retcode != code
        why = [r for (bit, r) in _STATUS_REASONS if st & bit != 0]
        isempty(why) && push!(why, "status word $(repr(st))")
        @warn "the run failed at MCS $(integ.t): $(join(why, "; "))"
    end
    integ.retcode = code
    return nothing
end
# the return code of a nonzero status word: a non-finite energy change is SciML's `Unstable`
# (the state left the finite numbers); a failed draw is a `Failure`
function _status_code(st::UInt32)
    return if st & STATUS_NONFINITE != 0
        SciMLBase.ReturnCode.Unstable
    else
        SciMLBase.ReturnCode.Failure
    end
end

function CommonSolve.step!(integ::PottsIntegrator)
    integ.retcode == SciMLBase.ReturnCode.Default ||
        throw(ArgumentError("integrator finished with retcode $(integ.retcode); call \
            `reinit!(integ)` to reset it before stepping again"))
    # this sweep's count (a refresh may change it)
    attempts = integ.nmobile
    # one fold over the static MCS order (api-synthesis §2.12): phase tuples, the sweep and
    # the lifecycle in the model's order: `Base.afoldl` over the tuple (unrolled by Base, no
    # recursion here; zero allocations, where `sum` and `foldl` with a closure allocated on
    # SequentialCPM)
    _run_mcs!(integ, integ.f.phases.mcs)
    # a field or adaptive ODE solve that failed ends the run
    (c = _phase_failed_code(_stats(integ))) != SciMLBase.ReturnCode.Default &&
        (integ.retcode = c)
    integ.t += 1
    integ.iter += 1
    _stats(integ).mcs += 1
    _stats(integ).attempts += attempts
    _drop_reached!(integ.opts.tstops, integ.t)
    isempty(integ.callbacks) || _apply_callbacks!(integ)
    _save_due(integ) && (_check_status!(integ); _save!(integ))
    _past_maxiters(integ) && _maxiters!(integ)
    integ.opts.progress && integ.iter % integ.opts.progress_steps == 0 && _progress!(integ)
    return integ
end

# the stops at or before MCS `t` are reached: dropped (a plain vector; compiled once)
function _drop_reached!(tstops::Vector{Int}, t::Int)
    while !isempty(tstops) && first(tstops) <= t
        popfirst!(tstops)
    end
    return nothing
end
# the last MCS `solve!` runs to: the end of the time span, or a later stop
function _final_stop(integ::PottsIntegrator)
    (ts = integ.opts.tstops; isempty(ts) ? integ.tstop : max(integ.tstop, last(ts)))
end
# `maxiters` MCS taken before the end: the run stops
function _past_maxiters(integ::PottsIntegrator)
    return integ.iter >= integ.opts.maxiters &&
        integ.retcode == SciMLBase.ReturnCode.Default && integ.t < _final_stop(integ)
end
@noinline function _maxiters!(integ::PottsIntegrator)
    integ.opts.verbose && @warn string(
        "the run stopped after maxiters = ", integ.opts.maxiters, " MCS at MCS ", integ.t,
        ": `ReturnCode.MaxIters`; give a larger `maxiters`"
    )
    integ.retcode = SciMLBase.ReturnCode.MaxIters
    return nothing
end
# SciML's progress log (ProgressLogging's form, as OrdinaryDiffEq writes it)
@noinline function _progress!(integ::PottsIntegrator, done::Bool = false)
    o = integ.opts
    t0 = integ.prob.tspan[1]
    frac = done ? "done" : clamp((integ.t - t0) / max(_final_stop(integ) - t0, 1), 0.0, 1.0)
    @logmsg LogLevel(
        -1
    ) o.progress_name _id = o.progress_id message = "MCS $(integ.t)" progress = frac
    return nothing
end

# `Base.afoldl`, not `_each`: the MCS order is compiler-built and short (`Phases` caps it at
# 31, afoldl's unrolled limit)
function _run_mcs!(integ, t::Tuple)
    (Base.afoldl((_, e) -> (_run_entry!(integ, e); nothing), nothing, t...); nothing)
end

function _sequential_sweep!(integ::PottsIntegrator, ctx, part::NTuple{2, Int})
    if _skips_interior(integ.alg)
        acc, status, tracked = boundary_site_mcs!(
            integ.state, integ.kf, integ.p, ctx,
            integ.law, integ.key, integ.t, integ.cache, integ.f.track
        )
    else
        acc, status, tracked = sequential_mcs!(
            integ.state, integ.kf, integ.p, ctx,
            integ.law, integ.key, integ.t, integ.f.track, part
        )
    end
    _stats(integ).accepted = max(_stats(integ).accepted, 0) + acc
    tracked === nothing || (_stats(integ).accepted_energy_change += tracked)
    status != 0 && (integ.retcode = _status_code(status))
    return nothing
end

# One entry of the MCS order: a tuple of phases, the sweep, the lifecycle or a `Repeat`.
function _run_entry!(integ::PottsIntegrator, phases::Tuple, part::NTuple{2, Int} = (1, 1))
    _stats(integ).launches += run_phases(
        phases, integ.state, integ.p, integ.ctx,
        integ.key, integ.t, integ.backend, _stats(integ), part
    )
    return nothing
end
# `part = (j, n)`: pass `j` of the `n` passes of a `Repeat` (the whole MCS is `(1, 1)`)
function _run_entry!(integ::PottsIntegrator, ::SweepPhase, part::NTuple{2, Int} = (1, 1))
    # the copy functions see the number of completed MCS as `ctx.mcs` (the copy-scope `mcs`,
    # D-188): n − 1 during the n-th MCS, as the phases' `mcs`
    ctx = sweep_ctx(integ.ctx, integ.t)
    if integ.alg isa SequentialCPM
        # the site-pick regime is fixed per sweep in the context's type (D-247): two static
        # calls, so the one-word sweep compiles exactly as before
        if _two_word_pick(integ.nmobile)
            _sequential_sweep!(integ, _with_two_word_pick(ctx), part)
        else
            _sequential_sweep!(integ, ctx, part)
        end
    else
        _stats(integ).launches += checkerboard_mcs!(
            integ.state, integ.cache, integ.kf,
            integ.p, ctx, integ.law, integ.key, integ.t, part
        )
    end
    return nothing
end
function _run_entry!(integ::PottsIntegrator, r::Repeat)
    n = r.n
    for j in 1:n
        Base.afoldl(
            (_, e) -> (_run_entry!(integ, e, (j, n)); nothing), nothing,
            r.entries...
        )
    end
    return nothing
end

# A `Repeat` of `n > 1` passes needs a sweep that splits: refused at `init` otherwise
function _check_repeat(phases::Phases, alg, cache)
    for r in phases.mcs
        (r isa Repeat && r.n > 1 && any(x -> x isa SweepPhase, r.entries)) || continue
        _skips_interior(alg) && throw(
            ArgumentError(
                "the MCS order repeats a 1/$(r.n) sweep, which `SequentialCPM(; " *
                    "skip_interior = true)` cannot split (its attempts are geometric \
                        skips); use `SequentialCPM()` or `CheckerboardCPM()`"
            )
        )
        if cache isa CheckerboardCache
            C = length(cache.order)
            C % r.n == 0 || throw(
                ArgumentError(
                    "the MCS order repeats a 1/$(r.n) sweep; `CheckerboardCPM` splits an " *
                        "MCS into its $C phases, so the count must divide $C"
                )
            )
        end
    end
    return nothing
end

"""
    sweep_ctx(ctx, mcs)

The run context of the copy sweep of MCS `mcs + 1`: `ctx` with `mcs`, the number of
completed MCS, which the copy functions (`delta_H`, `constraint`, `temperature`, `bias`,
`commit!`) may read as `ctx.mcs`.
"""
sweep_ctx(ctx::NamedTuple, mcs::Integer) = merge(ctx, (; mcs = Int(mcs)))

function _run_entry!(integ::PottsIntegrator, ::LifecyclePhase)
    integ.f.lifecycle === nothing || _step_lifecycle!(integ)
    return nothing
end

# The lifecycle planner (D-089, D-332): enqueued, with the standard-rule mask refresh; then
# the host stage (`_host_stage!`) where the backend is the CPU or the model has host hooks
function _step_lifecycle!(integ)
    sc = integ.mscratch
    refresh = if sc === nothing
        nothing
    else
        (; integ.ctx.mobility.frozen, kinds = frozen_kinds(integ.f.sys))
    end
    lc = integ.f.lifecycle
    _stats(integ).launches += run_lifecycle!(
        lc, integ.lcache, integ.state, integ.p, integ.ctx, integ.key, integ.t,
        integ.backend, refresh
    )
    integ.t % lc.every == 0 && _host_stage!(integ, integ.lcache.device, integ.backend)
    return nothing
end

"""
The host stage after the lifecycle planner, on event rounds only. On the CPU the event flag
is host memory: an event round folds the planner's counts at once (statistics, the mobile
count and the `SequentialCPM` mobile-site list, so every CPU read of `stats.lifecycle` is
current), then runs the host hooks. On a device only a model with host hooks reads the flag
(one synchronization and a 4-byte transfer per checked MCS). The host hooks, in this order:
the cell-scope `pieces` columns rebuilt from σ, `Lifecycle.rebuild!`, and a custom
`remake_frozen` rule.
"""
function _host_stage!(integ, D, backend::CPU)
    _events_on(_stats(integ), backend, D) || return nothing
    _fold_lifecycle!(integ; now = integ.t + 1)
    _host_hooks!(integ)
    return nothing
end
function _host_stage!(integ, D, backend)
    _has_host_hooks(integ.f, integ.state) || return nothing
    _events_on(_stats(integ), backend, D) || return nothing
    _host_hooks!(integ)
    return nothing
end

_has_pieces(st) = haskey(st.cell, :pieces) || haskey(st.cell, :pieces_full)
function _has_host_hooks(f::CPMFunction, st)
    return _has_pieces(st) || f.lifecycle.rebuild! !== no_rebuild || _custom_frozen(f.sys)
end

function _host_hooks!(integ)
    st, stats = integ.state, _stats(integ)
    if _has_pieces(st)
        sync!(stats, integ.backend)
        σ = to_host(stats, st.ownership)
        lat = host_lattice(stats, integ.ctx.lattice)
        _rebuild_pieces!(stats, st, σ, lat, length(st.cell.kind))
    end
    integ.f.lifecycle.rebuild!(st, integ.p, integ.ctx, integ.backend)
    _custom_frozen(integ.f.sys) && _refresh_frozen!(integ)
    return nothing
end

# tests: the lifecycle runs staged whatever the `CheckerboardCPM` limits (for test files
# that build their own algorithms); the fused form runs on the CPU too, within those limits
const _FORCE_STAGED_LIFECYCLE = Ref(false)
const _FORCE_FUSED_LIFECYCLE = Ref(false)
# the sizes up to which the device lifecycle runs fused (`CheckerboardCPM` keywords;
# validated here)
_fused_lifecycle_limits(alg) = (;)
# (both at least 0: the constructor checks them)
function _fused_lifecycle_limits(alg::CheckerboardCPM)
    return (;
        max_sites = alg.fused_lifecycle_max_sites,
        max_cells = alg.fused_lifecycle_max_cells,
    )
end

# counters for the standard-rule refresh: only when the mask can change by the standard rule
_mobility_scratch(backend, prob, ::AllMobile) = nothing
function _mobility_scratch(backend, prob, ::MaskMobility)
    (frozen_varies(prob.f.sys) && frozen_kinds(prob.f.sys) !== nothing) || return nothing
    I = site_index_type(nsites(prob.lattice))
    I <: Int64 && !_atomic64(backend) && throw(
        ArgumentError(
            "this lattice has $(nsites(prob.lattice)) sites and a frozen mask that " *
                "follows the state: its refresh counts sites in Int64 atomics, " *
                "which $(nameof(typeof(backend))) does not have; run it on the CPU or on \
                    ROCm or CUDA"
        )
    )
    return MobileCounters(KernelAbstractions.zeros(backend, I, 3), zeros(I, 3))
end

# A conversion pass above 2³¹ − 1 sites keeps its lowest site and its counts in Int64
# atomics (`convert_scratch`, D-253), which a backend without them cannot compile: refused
function _check_convert_atomics(backend, u0)
    haskey(u0.model, CONVERT_FLAGS) || return nothing
    (eltype(getfield(u0.model, CONVERT_FLAGS)) <: Int64 && !_atomic64(backend)) && throw(
        ArgumentError(
            "this lattice has $(length(u0.ownership)) sites and an @convert pass: it " *
                "keeps site indices in Int64 atomics, which $(nameof(typeof(backend))) \
                    does not have; run it on the CPU or on ROCm or CUDA"
        )
    )
    return nothing
end

# Statistics of a new run: `accepted_energy_change` is 0.0 when `f` tracks, else `nothing`;
# `connectivity_deferred` is 0 when the model uses `Global`, else `nothing`.
function _initial_stats(f)
    return PottsStats(;
        accepted_energy_change = f.track === nothing ? nothing : 0.0,
        connectivity_deferred = if f.connectivity === nothing ||
                !f.connectivity.uses_global
            nothing
        else
            0
        end
    )
end

# Read point of the checkerboard track (D-140, the D-089 pattern): the per-site accumulator
# is reduced into `stats.accepted_energy_change` (Float64; one counted copy on a device) and
# zeroed. Nothing without a track or under `SequentialCPM` (with or without
# `skip_interior`), which adds into the stats every step.
_fold_track!(integ) = _fold_track!(_stats(integ), integ.cache)
_fold_track!(stats, ::Nothing) = nothing
_fold_track!(stats, ::BoundaryCache) = nothing
function _fold_track!(stats, tk::NamedTuple)
    acc = tk.acc
    h = _ondevice(acc) ? to_host(stats, acc) : acc
    stats.accepted_energy_change += sum(Float64, h)
    fill!(acc, zero(eltype(acc)))
    return nothing
end

_fold_counts!(integ) = _fold_counts!(_stats(integ), integ.cache)
_fold_counts!(stats, cache) = nothing

# bring the device lifecycle's counts into `integ.stats` (synchronizes; only off the MCS
# loop)
_flush_counts!(integ) = _fold_lifecycle!(integ)

"""
    refresh_frozen!(integrator) -> integrator

Recompute the frozen-site mask from the integrator's current state.

The integrator does this itself after every MCS with a lifecycle event (transition,
division, removal), and `reinit!` does it for the new state. A `DiscreteCallback` that
writes `kind` (or `σ` around frozen cells) directly in `integrator.u` must call it, or
`derivative_discontinuity!(integrator, true)`. `set_state!` (`setu`) on `kind` calls it.

Only models whose mask follows the state ([`frozen_varies`](@ref); Potts: a `[frozen]`
kind) do any work; for a static mask (none, the domain, a user `frozen`) it returns at
once. The standard rule ([`frozen_kinds`](@ref)) runs as one kernel on the integrator's
backend; called directly, it then reads back its counts (one small transfer). A custom
rule ([`remake_frozen`](@ref)) runs on a host copy of the state (of the leaves that
[`frozen_reads`](@ref) names, if it names them).

On a device, the integrator's own refreshes after lifecycle events run on the device.
`integrator.nmobile`, `integrator.stats.attempts` and `stats.refreshes` are brought up to
date at the host read points (a save, `current_state`, `checkpoint`, the end of `solve!`)
and by any direct `refresh_frozen!`. Code that calls `step!` directly and reads them in
between sees lagging values; the mask itself is always current.

# Arguments
- `integrator::PottsIntegrator`: the integrator.

# Returns
- The integrator.

See also [`frozen_sites`](@ref).
"""
refresh_frozen!(integ::PottsIntegrator) = (_refresh_frozen!(integ); integ)

function _refresh_frozen!(integ::PottsIntegrator)
    m = integ.ctx.mobility
    (m isa AllMobile || !frozen_varies(integ.f.sys)) && return nothing
    _stats(integ).refreshes += 1
    _refresh_frozen!(integ, m, frozen_kinds(integ.f.sys))
    return nothing
end

# the standard rule: one kernel rewrites the mask and counts the changes on the device
function _refresh_frozen!(integ, m::MaskMobility, kinds::Tuple)
    sc = integ.mscratch
    _flush_counts!(integ)                           # earlier device refreshes first
    Exec.launch!(
        integ.backend, _frozen_body!, length(integ.state.ownership),
        (
            m.frozen, sc.device, integ.state.ownership,
            integ.state.cell.kind, kinds, integ.ctx.lattice,
        )
    )
    _stats(integ).launches += 1
    # synchronizes (a no-op copy on the CPU)
    counted_copy!(_stats(integ), sc.host, sc.device)
    fill!(sc.device, zero(eltype(sc.host)))
    integ.nmobile += sc.host[2]
    sc.host[3] > 0 && m.sites !== nothing && _mobile_sites!(m.sites, m.frozen)
    return nothing
end
# a custom rule: `remake_frozen` on a host copy of the state; with `frozen_reads`, a copy
# of the declared leaves only (D-128; the other leaves stay device arrays)
function _refresh_frozen!(integ, m::MaskMobility, ::Nothing)
    reads = _frozen_reads(integ.f.sys, integ.state)
    sync!(_stats(integ), integ.backend)
    u = if integ.backend isa CPU
        integ.state
    elseif reads === nothing
        snapshot(_stats(integ), integ.backend, integ.state)
    else
        host_leaves(
            _stats(integ), integ.state; ownership = :ownership in reads,
            cell = filter(n -> n !== :ownership, reads)
        )
    end
    fz = frozen_sites(integ.prob, u)
    _set_mobility!(_stats(integ), m, fz)
    integ.nmobile = count(!, fz)
    return nothing
end

"""
    frozen_sites(prob::PottsProblem, u)

Return the frozen-site mask of state `u` for problem `prob`.

It applies the rule that the integrator applies at a refresh ([`refresh_frozen!`](@ref)),
with the sites outside the lattice domain. For a model whose mask does not vary it is
`prob.frozen`. Use it to draw a saved state's obstacles.

# Arguments
- `prob::PottsProblem`: the problem.
- `u`: a host state, for example `sol[end]`.

# Returns
- A host `Bool` array of the lattice size, or `nothing` when the problem has no mask.

# Examples
```julia
mask = frozen_sites(prob, sol[end])
```
"""
function frozen_sites(prob::PottsProblem, u)
    sys = prob.f.sys
    frozen_varies(sys) || return prob.frozen
    kinds = frozen_kinds(sys)
    fz = kinds === nothing ? remake_frozen(sys, prob, u) : _standard_frozen(kinds, u)
    m = prob.lattice.mask
    m === nothing && return fz
    return fz === nothing ? .!m : fz .| .!m
end

function CommonSolve.solve!(integ::PottsIntegrator)
    integ.opts.verbose ||
        return Base.ScopedValues.with(() -> _solve!(integ), Exec.VERBOSE => false)
    return _solve!(integ)
end
function _solve!(integ::PottsIntegrator)
    try
        while integ.t < _final_stop(integ) && integ.retcode == SciMLBase.ReturnCode.Default
            step!(integ)
        end
        _finish!(integ)
    catch err
        # a failed or interrupted run: callbacks that hold a file close it (frames.jl;
        # `_abort_frames!` logs its own errors, so this run's error is the one raised)
        _each(_abort_callback!, integ.callbacks)
        rethrow()
    end
    return PottsSolution(integ)
end

# The end of a run (once: `solve!`, or `done` at the end of an iteration): the exact
# statistics, the final status and return code, the final save and the callbacks' `finalize`
function _finish!(integ::PottsIntegrator)
    integ.finished && return nothing
    integ.finished = true
    _flush_counts!(integ)                           # exact `stats` at the end (D-089)
    _fold_track!(integ)
    _fold_deferred!(integ)
    _fold_counts!(integ)
    _check_status!(integ)
    report_run(integ.f.sys, integ)
    if integ.retcode == SciMLBase.ReturnCode.Default
        # a rounding floor of a field solve is kept as the final code (the run went on)
        integ.retcode = if _stats(integ).fields.code == SciMLBase.ReturnCode.StalledSuccess
            SciMLBase.ReturnCode.StalledSuccess
        else
            SciMLBase.ReturnCode.Success
        end
    end
    integ.opts.save_end && (isempty(integ.saved_t) || last(integ.saved_t) != integ.t) &&
        _save!(integ)
    _each(cb -> cb.finalize(cb, integ.state, integ.t, integ), integ.callbacks)
    integ.opts.progress && _progress!(integ, true)
    return nothing
end

"""
    step!(integ::PottsIntegrator, n, stop_at_tdt = false)

Step `integ` until MCS `integ.t + n` (`n` a whole number of MCS; with `stop_at_tdt`, a stop
there is added too, as SciML's integrators do). It stops earlier when the run ends (a
callback's `terminate!`, a failure).
"""
function CommonSolve.step!(integ::PottsIntegrator, dt, stop_at_tdt::Bool = false)
    n = _mcs(dt, "step!(integ, dt)")
    n >= 0 ||
        throw(ArgumentError("step!(integ, dt): dt = $dt; an integrator does not step back"))
    next = integ.t + n
    stop_at_tdt && n > 0 && SciMLBase.add_tstop!(integ, next)
    while integ.t < next && integ.retcode == SciMLBase.ReturnCode.Default
        step!(integ)
    end
    return integ
end

"""
    add_tstop!(integ::PottsIntegrator, t)

Make `integ` stop at MCS `t` (a whole number, not before `integ.t`; a stop at `integ.t` is
reached already, as in OrdinaryDiffEq). Each MCS is a step, so a stop inside the time span
changes no state; a stop past its end makes `solve!` run on to it.
"""
function SciMLBase.add_tstop!(integ::PottsIntegrator, t)
    m = _mcs(t, "add_tstop!")
    m >= integ.t ||
        throw(ArgumentError("add_tstop!: MCS $t is before the integrator's MCS $(integ.t)"))
    ts = integ.opts.tstops
    k = searchsortedfirst(ts, m)
    (k <= length(ts) && ts[k] == m) || insert!(ts, k, m)
    return nothing
end
SciMLBase.has_tstop(integ::PottsIntegrator) = !isempty(integ.opts.tstops)
SciMLBase.first_tstop(integ::PottsIntegrator) = first(integ.opts.tstops)
SciMLBase.pop_tstop!(integ::PottsIntegrator) = popfirst!(integ.opts.tstops)

"""
    savevalues!(integ::PottsIntegrator, force_save = false) -> (saved, savedexactly)

Save the state at the current MCS (once per MCS) when the run saves it: with `force_save`,
`save_everystep`, or when the MCS is one of the `saveat` times, as in OrdinaryDiffEq.
"""
function SciMLBase.savevalues!(integ::PottsIntegrator, force_save = false)
    unsaved = isempty(integ.saved_t) || last(integ.saved_t) != integ.t
    (force_save ? unsaved : _save_due(integ)) || return (false, false)
    _check_status!(integ)
    _save!(integ)
    return (true, true)
end

# The end of an iteration (`for i in integ`): at the last stop, or when the run ended; the
# end of the run is taken then (`solve!`'s, once)
function SciMLBase.done(integ::PottsIntegrator)
    integ.retcode == SciMLBase.ReturnCode.Default && integ.t < _final_stop(integ) &&
        return false
    _finish!(integ)
    return true
end
SciMLBase.has_stats(::PottsIntegrator) = true
function SciMLBase.get_du(::PottsIntegrator)
    throw(
        ArgumentError(
            "get_du: a Potts state is a label field and has no derivative; compare two \
                states instead"
        )
    )
end

# SciML's contract: `Success` while the run is healthy, else the code that ended it
function SciMLBase.check_error(integ::PottsIntegrator)
    return if integ.retcode == SciMLBase.ReturnCode.Default
        SciMLBase.ReturnCode.Success
    else
        integ.retcode
    end
end
function SciMLBase.terminate!(
        integ::PottsIntegrator,
        retcode = SciMLBase.ReturnCode.Terminated
    )
    integ.retcode = retcode
    return integ
end

# ---------------------------------------------------------------------------------------

"""
    PottsSolution

The saved states of a run at integer MCS, a `SciMLBase.AbstractTimeseriesSolution`.

`sol[i]` is the `i`-th saved state and `sol(t)` the state saved at MCS `t`; `sol(t; idxs)`
reads `idxs` there. There is no interpolation between MCS (`dense` is `false`): a time
that was not saved, or is not a whole MCS, is an `ArgumentError`. A state is a lattice
of cell numbers and cell tables, not one array, so `Array(sol)` and `sol[j, i]` are
refused. Read a quantity by name, `sol[x]` or `sol[x, i]`.

# Fields
- `u`: the saved host states.
- `t`: the saved MCS.
- `prob`: the problem.
- `alg`: the algorithm.
- `retcode`: the `SciMLBase.ReturnCode`.
- `stats`: the run's statistics.
- `dense`: always `false`.

# Examples
```julia
sol = solve(prob, SequentialCPM(); saveat = 10)
sol(50)         # the state at MCS 50
sol[end]        # the final saved state
```

See also [`PottsProblem`](@ref), [`PottsIntegrator`](@ref).
"""
struct PottsSolution{S, P, A} <: SciMLBase.AbstractTimeseriesSolution{S, 1, Vector{S}}
    u::Vector{S}
    t::Vector{Int}
    prob::P
    alg::A
    retcode::SciMLBase.ReturnCode.T
    stats::PottsStats
    dense::Bool
end

function PottsSolution(integ::PottsIntegrator)
    S = isempty(integ.saved_u) ? Any : typeof(first(integ.saved_u))
    _record_fields!(integ)
    return PottsSolution(
        convert(Vector{S}, integ.saved_u), copy(integ.saved_t),
        integ.prob, integ.alg, integ.retcode, _stats(integ), false
    )
end
# what the field report of the solution reads, at the end of the run (`FieldStats`): the
# counts the groups used, their resolved implicit facts and the backend
function _record_fields!(integ::PottsIntegrator)
    f = _stats(integ).fields
    rts = [
        _runtime(getfield(integ.ctx, _ctxkey(ph)))
            for ph in _field_phases(integ.f.phases)
    ]
    f.counts = Int[rt.n for rt in rts]
    f.implicit = Union{Nothing, Problems.ImplicitFacts}[
        Problems.implicit_facts(rt)
            for rt in rts
    ]
    f.backend = _backend_name(integ.backend)
    return nothing
end
_backend_name(b) = string(nameof(typeof(b)))

# Integer indexing is by saved state (`sol[end]` is the final state), not
# RecursiveArrayTools' element indexing: a state is a named collection of arrays, not an
# array.
Base.getindex(sol::PottsSolution, i::Int) = sol.u[i]
Base.getindex(sol::PottsSolution, i::AbstractVector{<:Integer}) = sol.u[i]
Base.firstindex(sol::PottsSolution) = firstindex(sol.u)
Base.lastindex(sol::PottsSolution) = lastindex(sol.u)

function Base.show(io::IO, ::MIME"text/plain", sol::PottsSolution)
    n = length(sol.t)
    println(
        io, "PottsSolution: retcode ", sol.retcode, ", ", n, " saved state", if n == 1
            ""
        else
            "s"
        end,
        ", ", sol.stats.mcs, " MCS"
    )
    return print(
        io,
        "t: ",
        if n <= 12
            sol.t
        else
            "[$(join(sol.t[1:5], ", ")), …, $(join(sol.t[(end - 4):end], ", "))]"
        end
    )
end
function Base.show(io::IO, sol::PottsSolution)
    return print(io, "PottsSolution(", sol.retcode, ", ", length(sol.t), " states)")
end

# a lattice in a few words: `24×20 periodic lattice`, `16×16 closed hexagonal lattice`
function _lattice_words(l::Lattice)
    b = if all(l.periodic)
        " periodic"
    elseif any(l.periodic)
        " partly periodic"
    else
        " closed"
    end
    g = if l.geometry isa Square
        ""
    else
        string(" ", lowercase(string(nameof(typeof(l.geometry)))))
    end
    return string(join(l.dims, "×"), b, g, " lattice")
end
_count_words(n, what) = string(n, " ", what, n == 1 ? "" : "s")
# The shows print only host-side facts held in the structs (sizes, slot counts, names): a
# count of live cells would read the volumes, a device-to-host copy on a GPU state
_slots(st::CPMState) = length(st.cell.kind)
# up to `n` names, then `…`
function _names_words(ks, n = 8)
    return length(ks) <= n ? join(ks, ", ") : string(join(ks[1:n], ", "), ", …")
end

function Base.show(io::IO, st::CPMState)
    return print(
        io, "CPMState(", join(size(st.ownership), "×"),
        ", ", _count_words(_slots(st), "cell slot"), ")"
    )
end
function Base.show(io::IO, ::MIME"text/plain", st::CPMState)
    print(
        io, "CPMState on a ", join(size(st.ownership), "×"),
        " lattice: ", _count_words(_slots(st), "cell slot"),
        " (", nameof(typeof(st.ownership)), ")"
    )
    for (part, nt) in (("cell", st.cell), ("site", st.site), ("model", st.model))
        isempty(nt) || print(io, "\n  ", part, ": ", _names_words(collect(keys(nt))))
    end
    return
end

function Base.show(io::IO, prob::PottsProblem)
    return print(
        io, "PottsProblem(", join(prob.lattice.dims, "×"), ", ",
        _count_words(_slots(prob.u0), "cell slot"), ", tspan ", prob.tspan, ")"
    )
end
function Base.show(io::IO, ::MIME"text/plain", prob::PottsProblem)
    print(
        io, "PottsProblem on a ", _lattice_words(prob.lattice),
        ": ", _count_words(_slots(prob.u0), "cell slot"),
        ", tspan ", prob.tspan, ", seed ", prob.seed
    )
    print(io, "\n  u0: ")
    show(io, prob.u0)
    kw = _without_init(prob.kwargs)
    isempty(kw) || print(io, "\n  solve keywords: ", join(keys(kw), ", "))
    haskey(prob.kwargs, :initializealg) &&
        print(io, "\n  initializealg (used when the problem was \
            built): ", prob.kwargs.initializealg)
    return nothing
end

function Base.show(io::IO, integ::PottsIntegrator)
    dims = join(integ.prob.lattice.dims, "×")
    return print(
        io, "PottsIntegrator(", nameof(typeof(integ.alg)), ", ", dims,
        ", t = ", integ.t, " of ", integ.tstop, ", ", integ.retcode, ")"
    )
end
function Base.show(io::IO, ::MIME"text/plain", integ::PottsIntegrator)
    print(
        io, "PottsIntegrator on a ", _lattice_words(integ.prob.lattice),
        ": ", nameof(typeof(integ.alg)),
        ", t = ", integ.t, " of ", integ.tstop, ", retcode ", integ.retcode
    )
    print(io, "\n  state: ")
    return show(io, integ.state)
end

function (sol::PottsSolution)(t::Real; idxs = nothing)
    (isinteger(t) && !isempty(sol.t) && first(sol.t) <= t <= last(sol.t)) || throw(
        ArgumentError(
            string(
                "sol(t): t = ", t, " is not a saved MCS (there is no interpolation \
                    between MCS); saved ",
                if length(sol.t) <= 12
                    "times are $(sol.t)"
                else
                    "MCS run from $(first(sol.t)) to $(last(sol.t))"
                end
            )
        )
    )
    i = searchsortedfirst(sol.t, Int(t))
    (i <= length(sol.t) && sol.t[i] == t) || throw(
        ArgumentError(
            string(
                "sol(t): MCS ", Int(t),
                " was not saved (there is no interpolation between MCS); save it with ",
                "`saveat`"
            )
        )
    )
    return idxs === nothing ? sol.u[i] : sol[idxs, i]
end
function (sol::PottsSolution)(ts::AbstractVector{<:Real}; idxs = nothing)
    return [sol(t; idxs) for t in ts]
end

function Base.Array(::PottsSolution)
    throw(
        ArgumentError(
            "`Array(sol)`: a Potts state is a label lattice and cell tables, not one " *
                "array; read a quantity by name (`sol[x]`) or a saved state's arrays \
                    (`sol.u[i].ownership`)"
        )
    )
end
function Base.getindex(::PottsSolution, j::Int, i::Int)
    throw(
        ArgumentError(
            "sol[j, i]: a Potts state is not one array, so it has no component `j`; read " *
                "a quantity by name, `sol[x, i]`"
        )
    )
end

function _restore_stats!(dst::PottsStats, src::PottsStats)
    dst.mcs, dst.attempts, dst.accepted, dst.launches = src.mcs, src.attempts, src.accepted,
        src.launches
    dst.committed = src.committed
    dst.refreshes = src.refreshes
    dst.syncs, dst.transfers, dst.transfer_bytes = src.syncs, src.transfers,
        src.transfer_bytes
    dst.accepted_energy_change = src.accepted_energy_change
    dst.connectivity_deferred = src.connectivity_deferred
    dst.ode_code = src.ode_code
    for f in fieldnames(LifecycleStats)
        setfield!(dst.lifecycle, f, getfield(src.lifecycle, f))
    end
    for f in fieldnames(FieldStats)
        v = getfield(src.fields, f)
        setfield!(dst.fields, f, v isa Vector ? copy(v) : v)
    end
    return dst
end

# ---------------------------------------------------------------------------------------
# SymbolicIndexingInterface: the symbolic system (if any) is `f.sys`; symbolic layers
# implement the SII queries on it (`sol[x]`, `getp(prob, x)`).

# ---------------------------------------------------------------------------------------
# Ensembles: trajectory `i` is the template with `replica = template.replica + i` and
# `repeat = ctx.repeat - 1` (independent Philox streams, D-005; one compiled model), unless
# the user's `prob_func` already changed the seed or replica.

"""
    EnsembleProblem(prob::PottsProblem; prob_func, output_func, reduction, u_init,
        safetycopy = false)

A SciML ensemble of Potts runs. Trajectory `i` solves
`remake(prob′; replica = prob.replica + i)`, where `prob′ = prob_func(prob, ctx)` (default:
`prob`), so trajectories are independent and reproducible: trajectory `i` equals
`solve(remake(prob; replica = prob.replica + i), alg)`.
"""
function SciMLBase.EnsembleProblem(
        prob::PottsProblem; prob_func = SciMLBase.DEFAULT_PROB_FUNC,
        safetycopy = false, kwargs...
    )
    pf = _ReplicaProbFunc(prob_func)
    return invoke(
        SciMLBase.EnsembleProblem, Tuple{Any}, prob; prob_func = pf, safetycopy, kwargs...
    )
end

"""
    solve(ens::EnsembleProblem, alg::AbstractCPMAlgorithm; backend = CPU(), trajectories, …)

An ensemble solved without an ensemble algorithm runs `EnsembleThreads()`, with `backend`
forwarded to every trajectory's `solve`: as many trajectories run at once as Julia has
threads. On a device each trajectory's task has its own queue, so their kernels overlap
(OpenVT monolayer, 1400², ROCm: about 720 MCS/s one at a time, 1,900 in total with 4 or 8 at
once). A waiting trajectory spins on its CPU thread, so start Julia with no more threads
than free CPUs. `EnsembleSerial()` runs them one after another. Each trajectory has its own
random stream, whichever ensemble runs it.
"""
function SciMLBase.__solve(
        prob::SciMLBase.AbstractEnsembleProblem,
        alg::AbstractCPMAlgorithm; backend = CPU(), kwargs...
    )
    return SciMLBase.__solve(prob, alg, EnsembleThreads(); backend, kwargs...)
end

# a parallel ensemble's trajectories run with `IN_THREADED_ENSEMBLE` set (the tasks inherit
# it). SciMLBase hands every trajectory an `rng`; it seeds the trajectories only when the
# ensemble itself got a `seed` or an `rng`, else trajectory `i` keeps replica `i` of the
# problem's seed.
function SciMLBase.__solve(
        prob::SciMLBase.AbstractEnsembleProblem, alg::AbstractCPMAlgorithm,
        ensemble::SciMLBase.BasicEnsembleAlgorithm; kwargs...
    )
    seeded = haskey(kwargs, :seed) || haskey(kwargs, :rng)
    function generic()
        return invoke(
            SciMLBase.__solve, Tuple{
                SciMLBase.AbstractEnsembleProblem, Any, SciMLBase.BasicEnsembleAlgorithm,
            },
            prob, alg, ensemble; kwargs..., _rng_seeds = seeded
        )
    end
    ensemble isa EnsembleSerial && return generic()
    return @with IN_THREADED_ENSEMBLE => true generic()
end

struct _ReplicaProbFunc{F}
    f::F
end
function (r::_ReplicaProbFunc)(prob, ctx)
    q = r.f(prob, ctx)
    (q.seed == prob.seed && q.replica == prob.replica) || return q
    return remake(
        q; replica = prob.replica + UInt32(ctx.sim_id), repeat = UInt32(
            ctx.repeat -
                1
        )
    )
end

"""
    StateIndex(scope::Symbol, name::Symbol)

A SymbolicIndexingInterface index of the named state array `getfield(st.scope, name)`.

Reading gives the array (a model variable: its value). Writing copies a same-sized array
into the live storage, or fills it with a number converted to the array's element type.

# Fields
- `scope::Symbol`: `:cell`, `:site` or `:model`.
- `name::Symbol`: the quantity's name in that scope.

# Examples
```jldoctest
julia> using CorePotts

julia> st = initial_state(Int32[1 0; 2 2], [1, 2]);

julia> st[StateIndex(:cell, :volume)]
2-element Vector{Int32}:
 1
 2
```
"""
struct StateIndex
    scope::Symbol
    name::Symbol
end
_state_array(st::CPMState, i::StateIndex) = getfield(getfield(st, i.scope), i.name)
function Base.getindex(st::CPMState, i::StateIndex)
    a = _state_array(st, i)
    return i.scope === :model ? only(to_host(nothing, a)) : a      # user read: not counted
end
Base.setindex!(st::CPMState, v, i::StateIndex) = _set_state_array!(nothing, st, v, i)
# `stats`: the integrator's `PottsStats` counting the host→device copy (D-085), or `nothing`
function _set_state_array!(stats, st::CPMState, v, i::StateIndex)
    a = _state_array(st, i)
    if v isa Number
        # a Float64 must not reach a Float32 device array
        fill!(a, convert(eltype(a), v))
    else
        size(v) == size(a) ||
            throw(DimensionMismatch("$(i.scope) variable $(i.name) has size $(size(a)); \
                got $(size(v))"))
        counted_copy!(stats, a, convert(Array{eltype(a)}, v))
    end
    return v
end

"""
    set_parameter(p::NamedTuple, v, i::Symbol) -> NamedTuple

Return the parameter object `p` with parameter `i` set to `v`.

`v` is converted to the stored type, so the parameter type, and the compiled code, never
change. Symbolic layers add methods for their parameter objects.

# Arguments
- `p::NamedTuple`: the parameter object.
- `v`: the new value.
- `i::Symbol`: the parameter's name.

# Returns
- `NamedTuple`: a new parameter object of the same type.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.set_parameter((; T = 10.0, n = 2), 5, :T)
(T = 5.0, n = 2)
```

See also [`set_parameters`](@ref).
"""
function set_parameter(p::NamedTuple, v, i::Symbol)
    return merge(p, NamedTuple{(i,)}((convert(typeof(getfield(p, i)), v),)))
end

# Setters act on the live state and parameters of an integrator and take effect from the
# next MCS. A problem's parameter object is replaced on a write (`set_parameter!` below).
function SymbolicIndexingInterface.set_state!(integ::PottsIntegrator, v, i::StateIndex)
    sync!(_stats(integ), integ.backend)
    if tangent_on(integ.ctx) isa Val{true} && i.scope === :site
        # a run with derivative parts: the values into the state, their derivative parts
        # into the twin
        _set_state_array!(_stats(integ), integ.state, tangent_primal(v), i)
        tangent_write!(_stats(integ), integ.ctx, i.name, v)
    else
        _set_state_array!(_stats(integ), integ.state, v, i)
    end
    # the owner or kind decides which sites are frozen
    (i.scope === :cell && i.name === :kind) && refresh_frozen!(integ)
    # a field written: its group's algorithm takes the new values as a start (`reset!`)
    i.scope === :site && reset_fields!(integ.ctx)
    return v
end
function SymbolicIndexingInterface.set_parameter!(integ::PottsIntegrator, v, i)
    p = set_parameter(integ.f.sys, integ.p, v, i)
    check_field_parameters(integ, p)               # a refused value changes nothing
    integ.p = p
    # (a run with derivative parts: its Dual parameters follow)
    tangent_parameters!(integ, p)
    return nothing
end

"""
    set_parameter(sys, p, v, i)

Return `set_parameter(p, v, i)` for the model described by `sys` (`CPMFunction.sys`).

A symbolic layer adds a method to validate the value and to update the parameters derived
from `i`.

# Arguments
- `sys`: the model description.
- `p`: the parameter object.
- `v`: the new value.
- `i`: the parameter's index.

# Returns
- The new parameter object.
"""
set_parameter(sys, p, v, i) = set_parameter(p, v, i)

"""
    set_parameters(sys, p, vals, idxs)

Return the parameter object `p` with parameters `idxs` set to `vals` as one change.

It serves `setp(integ, [x, y])`. The default makes one `set_parameter` call per index; a
symbolic layer adds a method so that the parameters derived from several of them are
updated once, from all the new values.

# Arguments
- `sys`: the model description.
- `p`: the parameter object.
- `vals`: the new values.
- `idxs`: the parameter indices, in the order of `vals`.

# Returns
- The new parameter object.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.set_parameters(nothing, (; a = 1.0, b = 2.0), (3, 4), (:a, :b))
(a = 3.0, b = 4.0)
```

See also [`set_parameter`](@ref).
"""
function set_parameters(sys, p, vals, idxs)
    for (v, i) in zip(vals, idxs)
        p = set_parameter(sys, p, v, i)
    end
    return p
end

# `setp(integ, [x, y])` (and `integ.ps[[x, y]] = v`) on an integrator: the parameters are
# set together, as one change (`set_parameters`), not one name at a time
struct ParameterSetter{I, O}
    idxs::I
    original::O
    run_hook::Bool
end
function (s::ParameterSetter)(integ::PottsIntegrator, vals)
    length(vals) == length(s.idxs) ||
        throw(DimensionMismatch("setp: $(length(s.idxs)) parameters, $(length(vals)) \
            values"))
    p = set_parameters(integ.f.sys, integ.p, vals, s.idxs)
    check_field_parameters(integ, p)               # a refused value changes nothing
    integ.p = p
    # (a run with derivative parts: its Dual parameters follow)
    tangent_parameters!(integ, p)
    s.run_hook && SymbolicIndexingInterface.finalize_parameters_hook!(integ, s.original)
    return nothing
end
function (s::ParameterSetter)(valp, vals)
    for (v, i) in zip(vals, s.idxs)
        SymbolicIndexingInterface.set_parameter!(valp, v, i)
    end
    s.run_hook && SymbolicIndexingInterface.finalize_parameters_hook!(valp, s.original)
    return nothing
end
function SymbolicIndexingInterface.setp(
        sys::Union{PottsIntegrator, PottsProblem, CPMFunction}, ps::Union{
            Tuple, AbstractVector,
        };
        run_hook = true
    )
    return parameter_setter(sys, ps, run_hook)
end
function SymbolicIndexingInterface.setp(
        sys::Union{PottsIntegrator, PottsProblem, CPMFunction}, p; run_hook = true
    )
    return name_setter(sys, p, run_hook)
end

"""
    name_setter(sys, p, run_hook)

Return the setter of `setp(sys, p)` for one name `p`.

It is SymbolicIndexingInterface's setter, after the same name check as for a list: a state
variable or an unknown name is an `ArgumentError`.

# Arguments
- `sys`: an integrator, problem, function or model description.
- `p`: the name.
- `run_hook::Bool`: run `finalize_parameters_hook!` after a set.

# Returns
- A setter, called as `setter(integ, v)`.

See also [`parameter_setter`](@ref), [`symbol_setter`](@ref).
"""
function name_setter(sys, p, run_hook)
    SymbolicIndexingInterface.symbolic_type(p) isa
        SymbolicIndexingInterface.ScalarSymbolic && _check_settable(sys, p)
    return invoke(SymbolicIndexingInterface.setp, Tuple{Any, Any}, sys, p; run_hook)
end

"""
    parameter_setter(sys, ps, run_hook)

Return the setter of `setp(sys, ps)` for several parameters `ps` of `sys`.

The setter applies them to an integrator as one change. A state in the list (set those
with `setu`, or both with `setsym`) or an unknown name is an `ArgumentError` here, before
anything is set.

# Arguments
- `sys`: an integrator, problem, function or model description.
- `ps`: the parameter names, a tuple or vector.
- `run_hook::Bool`: run `finalize_parameters_hook!` after a set.

# Returns
- A setter, called as `setter(integ, vals)`.

See also [`name_setter`](@ref), [`set_parameters`](@ref).
"""
function parameter_setter(sys, ps, run_hook)
    isempty(ps) &&
        return invoke(SymbolicIndexingInterface.setp, Tuple{Any, Any}, sys, ps; run_hook)
    foreach(x -> _check_settable(sys, x), ps)
    return ParameterSetter(
        map(x -> SymbolicIndexingInterface.parameter_index(sys, x), ps),
        ps, run_hook
    )
end

function _check_settable(sys, x)
    SymbolicIndexingInterface.is_parameter(sys, x) && return nothing
    SymbolicIndexingInterface.is_variable(sys, x) && throw(
        ArgumentError(
            "setp: `$x` is a state variable, not a parameter; set states with " *
                "`setu`, or parameters and states together with `setsym`"
        )
    )
    throw(_unknown_name(sys, x, "setp"))
end

function _unknown_name(sys, x, fn)
    m = _readonly(sys, x)
    m === nothing || return ArgumentError(m)
    SymbolicIndexingInterface.is_observed(sys, x) &&
        return ArgumentError("$fn: `$x` is read-only (a built-in or observed quantity) \
            and cannot be set")
    return ArgumentError(
        "$fn: `$x` is neither a parameter nor a state variable" *
            _names_hint(sys)
    )
end
_names_hint(sys) = ""
"""
    readonly_message(container, x) -> Union{String, Nothing}

Return why `x` cannot be set, when a symbolic layer knows, or `nothing`.

A symbolic layer adds methods, for example for a computed parameter: the message gives its
expression, its inputs and the routes to change it. The default returns `nothing`.

# Arguments
- `container`: an integrator, problem, function or model description.
- `x`: the name.

# Returns
- `String`, or `nothing`.
"""
readonly_message(container, x) = nothing
# through the containers (an integrator's function, the function's model description)
function _readonly(sys, x)
    m = readonly_message(sys, x)
    m === nothing || return m
    applicable(SymbolicIndexingInterface.symbolic_container, sys) || return nothing
    c = SymbolicIndexingInterface.symbolic_container(sys)
    return c === sys ? nothing : _readonly(c, x)
end
function _names_hint(x::Union{PottsIntegrator, PottsProblem, CPMFunction})
    return _names_hint(SymbolicIndexingInterface.symbolic_container(x))
end

# `setsym(integ, [x, y, w])`: the parameters of the list are set as one change (as `setp`),
# then its states (as `setu`)
struct SymbolSetter{PS, SS}
    pset::PS
    sset::SS
    pk::Vector{Int}
    sk::Vector{Int}
end
function (s::SymbolSetter)(valp, vals)
    length(vals) == length(s.pk) + length(s.sk) ||
        throw(DimensionMismatch("setsym: $(length(s.pk) + length(s.sk)) \
            names, $(length(vals)) values"))
    s.pset(valp, map(k -> vals[k], s.pk))
    s.sset(valp, map(k -> vals[k], s.sk))
    return nothing
end
function SymbolicIndexingInterface.setsym(
        sys::Union{PottsIntegrator, PottsProblem, CPMFunction},
        syms::Union{Tuple, AbstractVector}
    )
    return symbol_setter(sys, syms)
end

"""
    symbol_setter(sys, syms)

Return the setter of `setsym(sys, syms)` (and `setu`) for a list of names of `sys`.

Its parameters are set as one change, as by `setp(sys, parameters)` (a rejected value sets
none of them); its states as by `setu`. A list of states only gets
SymbolicIndexingInterface's setter. An unknown or read-only name is an `ArgumentError`
when the setter is built. A mixed list is all-or-nothing for its parameters only: they are
set first, so a rejected parameter value sets nothing, but a rejected state value (set
after them) leaves the new parameter values in place.

# Arguments
- `sys`: an integrator, problem, function or model description.
- `syms`: the names, a tuple or vector.

# Returns
- A setter, called as `setter(integ, vals)`.

See also [`parameter_setter`](@ref).
"""
function symbol_setter(sys, syms)
    generic() = invoke(SymbolicIndexingInterface.setsym, Tuple{Any, Any}, sys, syms)
    SymbolicIndexingInterface.symbolic_type(syms) isa
        SymbolicIndexingInterface.NotSymbolic || return generic()
    pk, sk = Int[], Int[]
    for (k, x) in enumerate(syms)
        if SymbolicIndexingInterface.symbolic_type(x) isa
                SymbolicIndexingInterface.NotSymbolic ||
                SymbolicIndexingInterface.is_variable(sys, x)
            push!(sk, k)                                  # a state (or a raw state index)
        elseif SymbolicIndexingInterface.is_parameter(sys, x)
            push!(pk, k)
        else
            throw(_unknown_name(sys, x, "setsym"))
        end
    end
    isempty(pk) && return generic()
    pset = parameter_setter(sys, [syms[k] for k in pk], true)
    isempty(sk) && return pset
    sset = invoke(
        SymbolicIndexingInterface.setsym, Tuple{Any, Any}, sys, [
            syms[k]
                for k in sk
        ]
    )
    return SymbolSetter(pset, sset, pk, sk)
end

# A problem's parameter object is replaced, not mutated: the isbits `p` the kernels take is
# rebuilt with the new value (`set_parameter`), after the same field check as `remake`.
function SymbolicIndexingInterface.set_parameter!(prob::PottsProblem, v, i)
    p = set_parameter(prob.f.sys, prob.p, v, i)
    _set_problem_parameters!(prob, p)
    return nothing
end
function _set_problem_parameters!(prob::PottsProblem, p)
    prob.tangent === nothing ||
        throw(ArgumentError("a problem with derivative parts keeps its parameters; use \
            `remake(prob; p = ...)`"))
    check_field_parameters(prob.f, p)              # a refused value changes nothing
    prob.p = p
    return nothing
end
function (s::ParameterSetter)(prob::PottsProblem, vals)
    length(vals) == length(s.idxs) ||
        throw(DimensionMismatch("setp: $(length(s.idxs)) parameters, $(length(vals)) \
            values"))
    _set_problem_parameters!(prob, set_parameters(prob.f.sys, prob.p, vals, s.idxs))
    s.run_hook && SymbolicIndexingInterface.finalize_parameters_hook!(prob, s.original)
    return nothing
end

# A hand-written problem (`f.sys === nothing`): the fields of a NamedTuple parameter object
# are its parameters by name (`getp(integ, :T)`, `setp(integ, :T)`, `integ.ps[:T]`); any
# other parameter object has no names.
struct ParameterFields{P}
    p::P            # the parameter object; `nothing` for a function (no parameter object)
end
# index of field `name` of a NamedTuple parameter object
struct ParameterField
    name::Symbol
end
_index_name(i) = i
_index_name(i::ParameterField) = i.name
function _parameter_container(::Nothing, x)
    return ParameterFields(SymbolicIndexingInterface.parameter_values(x))
end
_parameter_container(sys, x) = x.f

SymbolicIndexingInterface.symbolic_container(f::CPMFunction) = _function_container(f.sys)
_function_container(::Nothing) = ParameterFields(nothing)
_function_container(sys) = sys
function SymbolicIndexingInterface.symbolic_container(integ::PottsIntegrator)
    return _parameter_container(integ.f.sys, integ)
end
function SymbolicIndexingInterface.symbolic_container(prob::PottsProblem)
    return _parameter_container(prob.f.sys, prob)
end

_has_field(s::ParameterFields, x) = s.p isa NamedTuple && x isa Symbol && haskey(s.p, x)
function _names_hint(s::ParameterFields)
    if s.p isa NamedTuple
        return "; the parameters of a problem without a model are the fields of its " *
            "NamedTuple parameter object: $(join(keys(s.p), ", "))"
    elseif s.p === nothing
        return "; a function without a model has no parameter names (use its problem or \
            integrator)"
    else
        return "; a problem without a model has parameter names only if its parameter " *
            "object is a NamedTuple (this one is a $(nameof(typeof(s.p))))"
    end
end
function _check_parameter_name(s::ParameterFields, x)
    SymbolicIndexingInterface.symbolic_type(x) isa SymbolicIndexingInterface.NotSymbolic &&
        return nothing
    _has_field(s, x) || throw(ArgumentError("`$x` is not a parameter" * _names_hint(s)))
    return nothing
end
_check_parameter_name(s, x) = nothing

SymbolicIndexingInterface.is_parameter(s::ParameterFields, x) = _has_field(s, x)
function SymbolicIndexingInterface.parameter_index(s::ParameterFields, x)
    _check_parameter_name(s, x)
    return ParameterField(x)
end
function SymbolicIndexingInterface.parameter_symbols(s::ParameterFields)
    return s.p isa NamedTuple ? collect(keys(s.p)) : Symbol[]
end
SymbolicIndexingInterface.is_variable(::ParameterFields, x) = false
SymbolicIndexingInterface.variable_index(::ParameterFields, x) = nothing
SymbolicIndexingInterface.variable_symbols(::ParameterFields) = Symbol[]
SymbolicIndexingInterface.all_variable_symbols(::ParameterFields) = Symbol[]
function SymbolicIndexingInterface.all_symbols(s::ParameterFields)
    return SymbolicIndexingInterface.parameter_symbols(s)
end
SymbolicIndexingInterface.is_independent_variable(::ParameterFields, x) = false
SymbolicIndexingInterface.independent_variable_symbols(::ParameterFields) = Symbol[]
SymbolicIndexingInterface.is_observed(::ParameterFields, x) = false
SymbolicIndexingInterface.is_time_dependent(::ParameterFields) = true
SymbolicIndexingInterface.constant_structure(::ParameterFields) = true
SymbolicIndexingInterface.default_values(::ParameterFields) = Dict()
function SymbolicIndexingInterface.parameter_values(p::NamedTuple, i::ParameterField)
    return getfield(p, i.name)
end
set_parameter(p::NamedTuple, v, i::ParameterField) = set_parameter(p, v, i.name)

# `SII.remake_buffer(prob, prob.p, keys, vals)` (and `setp_oop`, which calls it on the root
# container) on a problem without a model: a new NamedTuple of the same type with those
# fields set (the original untouched)
function SymbolicIndexingInterface.remake_buffer(
        sys::Union{PottsIntegrator, PottsProblem, CPMFunction, ParameterFields},
        p::NamedTuple, idxs, vals
    )
    length(idxs) == length(vals) ||
        throw(DimensionMismatch("remake_buffer: $(length(idxs)) keys, $(length(vals)) \
            values"))
    for (i, v) in zip(idxs, vals)
        name = _index_name(i)
        (name isa Symbol && haskey(p, name)) || throw(
            ArgumentError(
                "remake_buffer: `$name` is not a field of the parameter object " *
                    "($(join(keys(p), ", ")))"
            )
        )
        p = set_parameter(p, v, name)
    end
    return p
end

# a name that is not a parameter of a problem without a model is an `ArgumentError` (not
# SymbolicIndexingInterface's "invalid symbol" error); with a model, `getp` is unchanged
function SymbolicIndexingInterface.getp(
        sys::Union{
            PottsIntegrator, PottsProblem, CPMFunction,
        }, p
    )
    _check_parameter_name(SymbolicIndexingInterface.symbolic_container(sys), p)
    return invoke(SymbolicIndexingInterface.getp, Tuple{Any, Any}, sys, p)
end

SymbolicIndexingInterface.state_values(prob::PottsProblem) = prob.u0
SymbolicIndexingInterface.parameter_values(prob::PottsProblem) = prob.p
SymbolicIndexingInterface.current_time(prob::PottsProblem) = prob.tspan[1]
SymbolicIndexingInterface.is_time_dependent(::PottsProblem) = true

# a problem's state is updated in place; `solve(prob; seed)` and `solve(prob; rng)` choose
# the random stream (an ensemble hands each trajectory its own `rng`)
SciMLBase.isinplace(::PottsProblem) = true
SciMLBase.supports_solve_rng(::PottsProblem, ::Union{Nothing, AbstractCPMAlgorithm}) = true

# Field phases on an integrator (fields.jl): the parameter check before a write, and the
# per-group substep counts
function check_field_parameters(integ::PottsIntegrator, p)
    for ph in _field_phases(integ.f.phases)
        b = _runtime(getfield(integ.ctx, _ctxkey(ph))).host
        _same_tables(ph, b, p) && _same_params(ph, b, p) && continue
        field_substeps(ph, p)
    end
    return nothing
end
_ctxkey(::FieldPhase{K}) where {K} = K

"""
    substep_counts(integ::PottsIntegrator) -> Vector{Int}
    substep_counts(prob::PottsProblem) -> Vector{Int}

The substep count of each field group of a Potts integrator or problem, in group order (the
order of each group's first field; one group per `field_solver`/`solvers` algorithm). A
count is the algorithm's `substeps` (a minimum) or more, as the stability bound of the
group's own rows needs at the current parameters (`mcs_duration`, or its part in a
`repeat(n, …)` of the fields, is the window). On an integrator it is the count at the
integrator's current parameters, right after a parameter write (`setp`, `integ.ps[x] = v`),
before the next step; on a problem it is the count at the problem's parameters. Empty for a
model with no fields. The same function gives the counts of a LatticePDE `FieldProblem`'s
integrator and solution.

```julia
integ = init(PottsProblem(sys, op, tspan; field_solver = ExplicitEuler(), solvers = [o => \
ExplicitEuler(substeps = 2)]),
             SequentialCPM())
substep_counts(integ)        # [3, 2]: the group of c takes 3 substeps per MCS, o 2
```
"""
# (from the parameters, not the runtimes: a runtime rebinds at its next step)
function Problems.substep_counts(integ::PottsIntegrator)
    return Int[field_substeps(ph, integ.p) for ph in _field_phases(integ.f.phases)]
end
function Problems.substep_counts(prob::PottsProblem)
    return Int[field_substeps(ph, prob.p) for ph in _field_phases(prob.f.phases)]
end

"""
    field_report([io::IO = stdout], prob::PottsProblem)
    field_report([io::IO = stdout], integ::PottsIntegrator)
    field_report([io::IO = stdout], sol::PottsSolution)

Print the policy of every field group of a Potts problem, integrator or solution, and the
backend of a run, as
LatticeFields prints the groups of a LatticePDE problem (`field_report` of a `FieldProblem`,
one function): one block per group with its fields and algorithm, the window (the MCS, or
its part in a `repeat(n, …)` of the fields), the substep count and its cause (the bound, the
user minimum `substeps = m`, or both), the stability bound `ρ` and its parts, and the number
types; for an implicit group `linsolve` and its multigrid levels and the Newton count; then
the coupling rule's `κ` for groups that read each other in a loop. A problem gives the
policy at its parameters (an implicit group's `linsolve` and Newton count as given: they are
resolved when the group is bound). An integrator gives each bound group as it is, with its
run counters (windows, solves, budget hits, status), its launches per substep and its fusion
decisions; then its steady starts (`init = :steady`). An integrator or a solution also gives
the run's field counters (`stats.fields`). The report reads what the problem, integrator or
solution holds and changes nothing in the run. A solution gives the substep counts its
groups used and their implicit facts as resolved at the end of the run (`sol.stats.fields`),
so its blocks match the integrator's. On a device it reads the groups' status words first
(one synchronization), so call it outside a timed loop.

```julia
integ = init(PottsProblem(sys, op, tspan), SequentialCPM())
field_report(integ)
```
"""
function Problems.field_report(io::IO, prob::PottsProblem)
    phases = _field_phases(prob.f.phases)
    println(
        io, "Field report: PottsProblem, ", _report_groups(phases),
        " (the policy at the problem's parameters; nothing bound)"
    )
    isempty(phases) ||
        _report_line(io, "backend", "set at `init` (`init(prob, alg; backend)`; the CPU \
            by default)")
    for (i, ph) in enumerate(phases)
        Problems.group_report(
            io, ph.group, ph.alg, _policy_params(ph, prob.p);
            title = _report_title(i, phases), ph.dt,
            E = ph.T, t0 = prob.tspan[1] * ph.period
        )
    end
    _report_coupling(io, phases, prob.p)
    return nothing
end
function Problems.field_report(io::IO, integ::PottsIntegrator)
    phases = _field_phases(integ.f.phases)
    # (on a device the status words are read first)
    st = integ.stats
    println(
        io, "Field report: PottsIntegrator, ",
        _report_groups(phases), ", ", nameof(typeof(integ.alg))
    )
    _report_line(
        io, "time", string(
            "MCS ", integ.t, " of ", integ.prob.tspan, ", retcode ", integ.retcode
        )
    )
    isempty(phases) || _report_line(io, "backend", _backend_name(integ.backend))
    rts = [_runtime(getfield(integ.ctx, _ctxkey(ph))) for ph in phases]
    # (the counts the runtimes hold: the substep rule is not called, so nothing warns)
    _report_counters(io, phases, Int[rt.n for rt in rts], st.fields)
    p = integ.p
    for (i, (ph, rt)) in enumerate(zip(phases, rts))
        # (a device compile still pending: its launches)
        _await!(rt)
        Problems.group_report(
            io, rt, _policy_params(ph, p);
            title = _report_title(i, phases), ph.dt, spec = ph.group.spec
        )
    end
    for ph in _start_phases(integ.f.phases)
        rt = _runtime(getfield(integ.ctx, _ctxkey(ph)))
        _await!(rt)
        Problems.group_report(
            io, rt, _policy_params(ph, p);
            title = "steady start", ph.dt, spec = ph.group.spec
        )
    end
    _report_coupling(io, phases, p)
    return nothing
end
function Problems.field_report(io::IO, sol::PottsSolution)
    prob = sol.prob
    phases = _field_phases(prob.f.phases)
    println(
        io, "Field report: PottsSolution, ", _report_groups(phases),
        ", ", nameof(typeof(sol.alg)), ", retcode ", sol.retcode,
        " (the policy at the problem's parameters)"
    )
    _report_line(
        io, "saves", string(
            length(sol.t), " over ", prob.tspan, ", ", sol.stats.mcs, " MCS"
        )
    )
    # the counts the groups used and their implicit facts, kept at the end of the run (a
    # solution built before they were kept: the policy's and as given)
    f = sol.stats.fields
    kept = length(f.counts) == length(phases)
    isempty(phases) || isempty(f.backend) || _report_line(io, "backend", f.backend)
    _report_counters(io, phases, kept ? f.counts : nothing, f)
    for (i, ph) in enumerate(phases)
        Problems.group_report(
            io, ph.group, ph.alg, _policy_params(ph, prob.p);
            title = _report_title(i, phases), ph.dt,
            E = ph.T, t0 = prob.tspan[1] * ph.period, n = kept ? f.counts[i] : nothing,
            facts = kept && length(f.implicit) == length(phases) ? f.implicit[i] : nothing
        )
    end
    _report_coupling(io, phases, prob.p)
    return nothing
end

# --- the field report's own lines (the groups are LatticeFields' `group_report`) ---
_report_line(io, label, text) = println(io, "  ", rpad(label, 11), text)
function _report_groups(phases)
    return if isempty(phases)
        "no fields"
    else
        string(length(phases), " field group", length(phases) == 1 ? "" : "s")
    end
end
_report_title(i, phases) = string("group ", i, " of ", length(phases))
function _report_counters(io, phases, counts, f::FieldStats)
    parts = String[]
    counts === nothing || push!(
        parts,
        string(
            "substep counts ",
            join(
                (
                    string(join(ph.group.spec.state, ", "), " ", n)
                        for (ph, n) in zip(phases, counts)
                ),
                ", "
            )
        )
    )
    f.solves > 0 && push!(parts, string(f.solves, " solve", f.solves == 1 ? "" : "s"))
    f.budget > 0 && push!(parts, string(f.budget, " linear budget hits"))
    f.floor > 0 && push!(parts, string(f.floor, " floors"))
    f.newton_budget > 0 && push!(parts, string(f.newton_budget, " Newton budget hits"))
    push!(parts, string("code ", f.code))
    isempty(phases) || _report_line(io, "counters", join(parts, "; "))
    return nothing
end
# the steady starts (`init = :steady`) among the at-init phases, each once
function _start_phases(phases::Phases)
    out = FieldPhase[]
    for t in (phases.at_init isa Repeat ? phases.at_init.entries : (phases.at_init,))
        t isa Tuple || continue
        for ph in t
            ph isa FieldPhase && ph.start && !any(q -> q === ph, out) && push!(out, ph)
        end
    end
    return out
end
# the coupling between groups (`Problems.coupling_report`): the whole field system's bound
# at the parameters of every group's phase, merged by name (each phase holds its own
# parameters; a parameter it does not read is `NaN` in its part)
function _report_coupling(io, phases, p)
    rules = [
        ph.substeps
            for ph in phases
            if ph.substeps isa Problems.GroupSubsteps && ph.substeps.coupling !== nothing
    ]
    length(rules) == length(phases) && length(phases) > 1 || return nothing
    c = first(rules).coupling
    wp, tabs = Float64[], Pair{String, Vector{Float64}}[]
    for ph in phases
        w = ph.substeps.coupling.whole(_policy_params(ph, p))
        v = w isa Problems.ParamsTables ? w.p : w
        isempty(wp) ? append!(wp, v) : (wp .= ifelse.(isnan.(wp), v, wp))
        w isa Problems.ParamsTables &&
            append!(tabs, (t for t in w.tables if !any(u -> u[1] == t[1], tabs)))
    end
    Problems.coupling_report(
        io, c.stability, c.groups, [ph.alg for ph in phases],
        Problems.with_tables(wp, tabs),
        first(phases).dt
    )
    return nothing
end
