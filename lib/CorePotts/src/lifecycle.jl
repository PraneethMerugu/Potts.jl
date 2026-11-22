# Cell lifecycle: division, removal, kind transition, creation and id reuse
# (INTERNALS §1.7 as amended by D-089 and D-332).
#
# One planner (`lifecycle_planner.jl`) on every backend and for every algorithm: per checked
# MCS a trigger kernel writes an event code per cell, then kernels plan (daughter ids
# lowest-first among free ids, deferral on exhausted capacity), partition sites by plane,
# remove cells, set kinds, apply the daughter state rules and update the trackers, with no
# host decision. On the CPU a quiet MCS ends after the trigger kernel; the statistics are
# folded into `integ.stats` at host read points (on the CPU at once, on event rounds).
#
# Cell ids are `1:capacity`; an id is free when its volume is zero. Reusing an id increments
# its generation, so cell-addressed randomness never replays.

"""
    EVENT_NONE

The lifecycle trigger code `Int32(0)`: no lifecycle event for the cell.

See also [`Lifecycle`](@ref).
"""
const EVENT_NONE = Int32(0)
"""
    EVENT_DIVIDE

The lifecycle trigger code `Int32(1)`: the cell divides alone along `Lifecycle.normal`.

See also [`Lifecycle`](@ref), [`transitioning`](@ref).
"""
const EVENT_DIVIDE = Int32(1)
"""
    EVENT_REMOVE

The lifecycle trigger code `Int32(2)`: the cell is removed and its sites become medium.

See also [`Lifecycle`](@ref).
"""
const EVENT_REMOVE = Int32(2)
"""
    EVENT_TRANSITION

The lifecycle trigger code `Int32(3)`: the cell changes to the kind that
`Lifecycle.kind` returns.

See also [`Lifecycle`](@ref), [`transitioning`](@ref).
"""
const EVENT_TRANSITION = Int32(3)
"""
    EVENT_DIVIDE_CLUSTER

The lifecycle trigger code `Int32(4)`: the cell's compartment cluster divides as a unit.
Only the root's event counts.

See also [`Lifecycle`](@ref).
"""
const EVENT_DIVIDE_CLUSTER = Int32(4)
# A division that also transitions the dividing cell (A-17): the transition bit on
# `EVENT_DIVIDE` or `EVENT_DIVIDE_CLUSTER` (`transitioning`). The transition is applied
# before the division: the `kind` hook reads the cell before it divides, the daughter state
# rules read the new kind, and both halves carry it (R8's priority "transition > divide").
const _TRANSITIONING = Int32(0x10)
# a cluster member that transitions and divides with its cluster in the same MCS
const _EVENT_DIVIDE_CLUSTER_TRANSITION = EVENT_DIVIDE_CLUSTER | _TRANSITIONING

"""
    transitioning(event) -> Int32

Return the trigger value for a cell that both transitions and has `event`.

`event` is [`EVENT_DIVIDE`](@ref) (the cell divides alone) or
[`EVENT_DIVIDE_CLUSTER`](@ref) (its cluster divides; the cell is the root). The cell
transitions to `kind(st, p, ctx, key, mcs, c)`, as for [`EVENT_TRANSITION`](@ref). The
transition is applied first: the `kind` hook sees the cell before the division, the
daughter state rules see the new kind, and both halves carry it. A division that is
deferred (no free slot) still transitions the cell. `stats.lifecycle.transitions` counts
the cell once.

It composes with [`ruled_event`](@ref): `ruled_event(transitioning(e), i)`. It runs
inside the trigger kernel, so it does not check `event`. The planner flags any other event
and throws an `ArgumentError` at the MCS's read point.

# Arguments
- `event`: `EVENT_DIVIDE` or `EVENT_DIVIDE_CLUSTER`.

# Returns
- `Int32`: the event with its transition bit set.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.transitioning(EVENT_DIVIDE)
17
```
"""
@inline transitioning(event) = Int32(event) | _TRANSITIONING
public transitioning

# a trigger value whose transition bit is on an event other than a division
@inline function _bad_transition(e)
    return (e & _TRANSITIONING) != Int32(0) &&
        !(_base_event(e) == EVENT_DIVIDE || _base_event(e) == EVENT_DIVIDE_CLUSTER)
end
function _bad_transition_error(n)
    return ArgumentError(
        "lifecycle: $n trigger value(s) with `transitioning(event)` on an event " *
            "other than EVENT_DIVIDE or EVENT_DIVIDE_CLUSTER"
    )
end

# the event without its transition bit, and whether the cell transitions
@inline _base_event(e) = e & ~_TRANSITIONING
@inline _transitions(e) = e == EVENT_TRANSITION || (e & _TRANSITIONING) != Int32(0)
@inline _divides_with_cluster(e) = _base_event(e) == EVENT_DIVIDE_CLUSTER
# a planned cell whose division did not happen (deferred, or its cluster's): a transition
# stays
@inline _undivided(e) = (e & _TRANSITIONING) != Int32(0) ? EVENT_TRANSITION : EVENT_NONE

# Rule-carrying events (`Lifecycle(…; rules = true)`): the trigger returns
# `ruled_event(event, i)`, the event in the low byte and the index `i ≥ 1` of the rule that
# fired above it, so the daughter state rule of that rule alone runs.
const _RULE_SHIFT = 8
const _EVENT_MASK = Int32(0xff)
"""
    ruled_event(event, i) -> Int32

Return `event` as fired by rule `i`, for the trigger of a `Lifecycle(…; rules = true)`.

The event is in the low byte and the rule index `i ≥ 1` above it, so only that rule's
daughter state rule runs. When no rule fires, return [`EVENT_NONE`](@ref) itself, not
`ruled_event(EVENT_NONE, i)`: a nonzero value counts as an event and runs the planner.

# Arguments
- `event`: the trigger code.
- `i`: the rule index, `≥ 1`.

# Returns
- `Int32`.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.ruled_event(EVENT_DIVIDE, 2)
513
```

See also [`transitioning`](@ref), [`Lifecycle`](@ref).
"""
@inline ruled_event(event, i) = Int32(event) | (Int32(i) << _RULE_SHIFT)
public ruled_event
@inline _event(::Val{false}, raw) = raw
@inline _event(::Val{true}, raw) = raw & _EVENT_MASK
@inline _rule(raw) = raw >> _RULE_SHIFT
# the daughter state rule: with rule-carrying events it also gets the index of the rule
@inline function _divide_rule!(
        ::Val{false}, f::F, st, p, ctx, key, mcs, parent, daughter, raw
    ) where {F}
    return f(st, p, ctx, key, mcs, parent, daughter)
end
@inline function _divide_rule!(
        ::Val{true}, f::F, st, p, ctx, key, mcs, parent, daughter, raw
    ) where {F}
    return f(st, p, ctx, key, mcs, parent, daughter, _rule(raw))
end

"""
    Lifecycle(trigger; normal = AlongMinorAxis(), kind, divide! = no_divide_rule,
              rebuild!, every = 1,
              cluster_normal = normal, cluster_divide! = divide!, rules = false,
              before = nothing, release = nothing, owner_changed = nothing)

Construct the lifecycle of a model: cell division, removal and kind transition.

Potts generates one from `@divide`, `@remove` and `@transition` rules; it can also be
written by hand. Division requires the moment trackers (`init_moments`) and a `commit!`
that keeps them current ([`commit_moments!`](@ref)). The lifecycle updates every built-in
tracker incrementally and does not recount it from `σ`. A hand-written model whose
`commit!` does not maintain a tracker that the state holds (the moments above all) uses
stale values for the whole run: its division planes pass through stale centroids. Potts
adds `commit_moments!` whenever it adds the moment columns. On a periodic axis a centroid
is defined only while the cell spans less than half the period.

Both kinds of division can happen in one MCS:

- [`EVENT_DIVIDE_CLUSTER`](@ref) divides a compartment cluster (`st.cell.cluster`) as a
  unit. Only the root's event counts; members' `EVENT_DIVIDE_CLUSTER` events are ignored.
  `cluster_normal` is evaluated with the cluster's moments (`st.cell` then holds the
  cluster's volume and moments at the root's index), and every live member splits along
  that plane through the cluster centroid; `cluster_divide!` runs for each member. A
  portable `cluster_normal` reads `st.cell.volume`, `anchor`, `m1` and `m2` only at the
  root's index, any other cell column only as `generation`, `kind` or `cluster`, and not
  `st.ownership`. The planner passes a `σ` that holds cell numbers, the full cell columns,
  and the cluster's volume and moments at every index. The daughters form a
  new cluster. A dividing cluster takes precedence over its members' own `EVENT_DIVIDE`.
- [`EVENT_DIVIDE`](@ref) divides the cell alone along `normal`; `divide!` runs. A
  compartment's daughter (the parent shares its cluster with another live cell) stays in
  the parent's cluster; a lone cell's daughter is a lone cell.

Cell serials: when `st.cell` has a `birth` column (`Int32`, never copied to a daughter)
and `st.model` has the counter [`NEXT_BIRTH`](@ref), every daughter takes the next serial,
in increasing daughter-slot order (the allocation order), and the counter advances. A
serial is never reused, and a checkpoint keeps the counter.

Cell ids are `1:capacity`; an id is free when its volume is zero. Reusing an id increments
its generation, so cell-addressed random draws never repeat.

# Arguments
- `trigger`: `trigger(st, p, ctx, key, mcs, c) -> Int32`, the event for live cell `c`:
  `EVENT_NONE`, `EVENT_DIVIDE`, `EVENT_DIVIDE_CLUSTER`, `EVENT_REMOVE` or
  `EVENT_TRANSITION` (the trigger resolves priorities itself).

# Keywords
- `normal = AlongMinorAxis()`: `normal(st, p, ctx, key, mcs, c) -> NTuple{N}`, the normal
  of the division plane through the centroid: [`AlongMinorAxis()`](@ref AlongMinorAxis),
  [`AlongMajorAxis()`](@ref AlongMajorAxis), [`RandomPlane()`](@ref RandomPlane), or any
  function that returns a vector.
- `kind`: `kind(st, p, ctx, key, mcs, c) -> Int32`, the destination kind of a transition.
  The default keeps the cell's kind.
- `divide! = no_divide_rule`: `divide!(st, p, ctx, key, mcs, parent, daughter)`, the
  daughter state rule, run after the default copy of every non-tracker cell quantity (for
  example, to halve extensive quantities). [`no_divide_rule`](@ref) does nothing.
- `rebuild!`: `rebuild!(st, p, ctx, backend)`, a host hook run after the planner on
  every MCS with an event, once the built-in trackers are updated. Model trackers that the
  lifecycle cannot know, such as the arrays of `commit_site_sum!` and `commit_site_min!`,
  must be recomputed here (`recompute_site_sum`, `recompute_site_min!(…; all = true)`), or
  they go stale. On a device, a lifecycle with `rebuild!` (or a model with a custom
  `remake_frozen` rule or cell-scope `pieces`) reads the event flag once per checked MCS:
  one synchronization and a 4-byte transfer. Every other lifecycle runs entirely on the
  device. The default does nothing.
- `every::Integer = 1`: check the triggers every `every` MCS.
- `cluster_normal = normal`, `cluster_divide! = divide!`: `normal` and `divide!` for
  cluster divisions.
- `rules::Bool = false`: rule-carrying events. With `true`, the trigger returns
  [`ruled_event(event, i)`](@ref ruled_event), naming the rule `i ≥ 1` that fired, and
  `divide!` and `cluster_divide!` take that index as an eighth argument (a cluster member
  gets its root's), so only the firing rule's daughter state rule runs. It is needed only
  when two rules can fire for one cell.
- `before = nothing`: `before(st, p, ctx, key, mcs, c)`, a cell update run for every cell
  `c` in `1:ncells(st)` at the start of the lifecycle of every MCS (also the MCS that the
  lifecycle does not check), as a `CellPhase` that runs right before the lifecycle. It
  must write only cell `c`'s own columns. The trigger of cell `c` may read a column that
  `before` writes only at index `c`. The device lifecycle then runs `before` and the
  trigger of each cell in one work item; on an MCS that the lifecycle does not check,
  `before` runs as its own launch.
- `release = nothing`: `release(st, c)`, the reset of a model's cell references. It runs
  for every cell `c` of an event round in the copy stage: after the plan (ids, planes and
  normals) and before the daughter column copies, while every volume is still the
  pre-event one. It resets each reference of a live cell `c` whose referent is dead
  (volume 0) to 0, so no reference points at the cell that reuses the slot, and
  daughters copy the reset value. It writes only cell `c`'s own columns and reads
  `volume`. A `normal` or `cluster_normal` that reads cell references sees them before
  this reset.
- `owner_changed = nothing`: `owner_changed(st, i)`, the ownership hook, run at every site
  `i` whose owner the lifecycle changes (a removed cell's sites, a daughter's sites), for
  example to reset site variables declared `clear_on_ownership_change`. It writes only
  site `i`'s own site values. Copy hooks (`@on_copy`) never run from the lifecycle.

# Examples
```julia
divide_big(st, p, ctx, key, mcs, c) =
    st.cell.volume[c] > 2 * p.target_volume ? EVENT_DIVIDE : EVENT_NONE
lc = Lifecycle(divide_big; normal = RandomPlane(), every = 10)
```

See also [`with_capacity`](@ref), [`rebuild_trackers!`](@ref).
"""
struct Lifecycle{TR, NO, CN, KI, DV, CD, RB, RU <: Val, BE, RL, OC}
    trigger::TR
    normal::NO
    cluster_normal::CN
    kind::KI
    divide!::DV
    cluster_divide!::CD
    rebuild!::RB
    every::Int
    rules::RU                   # Val(true): rule-carrying events
    before::BE                  # a cell update fused with the trigger, or `nothing`
    release::RL                 # the reference reset of an event round, or `nothing`
    # the site hook at every site whose owner changes, or `nothing`
    owner_changed::OC
end
function Lifecycle(
        trigger; normal = AlongMinorAxis(), kind = keep_kind, divide! = no_divide_rule,
        rebuild! = no_rebuild, every::Integer = 1, cluster_normal = normal,
        cluster_divide! = divide!,
        rules::Bool = false, before = nothing, release = nothing, owner_changed = nothing
    )
    return Lifecycle(
        trigger, normal, cluster_normal, kind, divide!, cluster_divide!,
        rebuild!, Int(every), Val(rules), before,
        release, owner_changed
    )
end

# the ownership hook at site `i` (`Lifecycle.owner_changed`)
@inline _owner_changed!(::Nothing, st, i) = nothing
@inline _owner_changed!(f::F, st, i) where {F} = (f(st, i); nothing)

"""
    NEXT_BIRTH

The `st.model` key of the cell-serial counter, a 1-element `Int32` array that holds the
serial the next daughter takes.

A model state that has it and a `birth` cell column gets serials at every division (see
[`Lifecycle`](@ref)).
"""
const NEXT_BIRTH = Symbol("#next_birth")

@inline _release!(::Nothing, st, c) = nothing
@inline _release!(f::F, st, c) where {F} = (f(st, c % Int32); nothing)

# `before` as its own launch (MCS the lifecycle does not check)
_run_before(::Nothing, st, p, ctx, key, mcs, backend) = 0
function _run_before(f::F, st, p, ctx, key, mcs, backend) where {F}
    return CellPhase(f)(st, p, ctx, key, mcs, backend)
end

no_rebuild(st, p, ctx, backend) = nothing

# bounds: c is a live cell id ≤ capacity (the lifecycle calls it per cell)
@inline keep_kind(st, p, ctx, key, mcs, c) = @inbounds st.cell.kind[c]
"""
    no_divide_rule(st, p, ctx, key, mcs, parent, daughter) -> nothing
    no_divide_rule(st, p, ctx, key, mcs, parent, daughter, rule) -> nothing

The default daughter state rule of a [`Lifecycle`](@ref): it does nothing, so a daughter
keeps the default copy of its parent's values.

# Arguments
- `st`, `p`, `ctx`, `key`, `mcs`: the state, parameters, context, RNG key and MCS.
- `parent`, `daughter`: the cell numbers.
- `rule`: the index of the firing rule, with rule-carrying events.

# Returns
- `nothing`.
"""
@inline no_divide_rule(st, p, ctx, key, mcs, parent, daughter) = nothing
@inline no_divide_rule(st, p, ctx, key, mcs, parent, daughter, rule) = nothing

const STREAM_DIVISION_PLANE = stream_id("CorePotts.division_plane")

"""
    AlongMinorAxis()
    AlongMinorAxis{T}()

A division plane functor that divides across the cell's long axis: the plane contains the
minor axis, so the normal is the major principal axis.

A [`Lifecycle`](@ref) evaluates it in the state's float type, whatever `T` it was given.

# Arguments
- `T`: the float type (`Float64` when not given).

See also [`AlongMajorAxis`](@ref), [`RandomPlane`](@ref), [`principal_axis`](@ref).
"""
struct AlongMinorAxis{T} end
AlongMinorAxis() = AlongMinorAxis{Float64}()

"""
    AlongMajorAxis()
    AlongMajorAxis{T}()

A division plane functor that divides along the cell's long axis: the normal is the
minor principal axis.

A [`Lifecycle`](@ref) evaluates it in the state's float type, whatever `T` it was given.

# Arguments
- `T`: the float type (`Float64` when not given).

See also [`AlongMinorAxis`](@ref), [`RandomPlane`](@ref), [`principal_axis`](@ref).
"""
struct AlongMajorAxis{T} end
AlongMajorAxis() = AlongMajorAxis{Float64}()

"""
    RandomPlane()
    RandomPlane{T}()

A division plane functor that draws a uniformly random unit normal, addressed by the cell
number and generation.

A [`Lifecycle`](@ref) evaluates it in the state's float type, whatever `T` it was given.

# Arguments
- `T`: the float type (`Float64` when not given).

See also [`AlongMinorAxis`](@ref), [`AlongMajorAxis`](@ref).
"""
struct RandomPlane{T} end
RandomPlane() = RandomPlane{Float64}()

@inline function (::AlongMinorAxis{T})(st, p, ctx, key, mcs, c) where {T}
    return principal_axis(T, st.cell, ctx.lattice, c, 1)
end
@inline function (::AlongMajorAxis{T})(st, p, ctx, key, mcs, c) where {T}
    return principal_axis(T, st.cell, ctx.lattice, c, ndims(ctx.lattice))
end
@inline function (::RandomPlane{T})(st, p, ctx, key, mcs, c) where {T}
    # bounds: c is a live cell id ≤ capacity (the lifecycle calls it per cell)
    r = draw(
        key, mcs, cell_entity(c, @inbounds st.cell.generation[c]),
        STREAM_DIVISION_PLANE
    )
    return _random_unit(T, r, Val(ndims(ctx.lattice)))
end
@inline function _random_unit(::Type{T}, r, ::Val{2}) where {T}
    θ = 2T(π) * uniform(T, r[1])
    return (cos(θ), sin(θ))
end
@inline function _random_unit(::Type{T}, r, ::Val{3}) where {T}
    z = 2uniform(T, r[1]) - one(T)
    φ = 2T(π) * uniform(T, r[2])
    s = sqrt(max(one(T) - z^2, zero(T)))
    return (s * cos(φ), s * sin(φ), z)
end

"""
    principal_axis(T, cell, lattice, c, k) -> NTuple{N, T}

Return the unit eigenvector of cell `c`'s site-coordinate covariance for its `k`-th
largest eigenvalue, in float type `T`.

On a 1D lattice the result is the axis itself. On a 2D lattice the covariance is taken in
Cartesian (embedded) coordinates. If the eigenvector is not determined (an isotropic
cell), a coordinate axis is returned.

# Arguments
- `T::Type`: the float type of the result.
- `cell`: the cell state, with `volume` and the moment trackers.
- `lattice::Lattice`: the lattice.
- `c`: the cell number.
- `k`: `1` for the largest eigenvalue, up to `N` for the smallest.

# Returns
- `NTuple{N, T}`: the unit vector.

# Examples
A bar of three sites along axis 1:
```jldoctest
julia> using CorePotts

julia> l = Lattice((5, 5)); σ = zeros(Int32, 5, 5); σ[2:4, 3] .= 1;

julia> cell = merge((; volume = Int32[3]), init_moments(σ, l, 1));

julia> principal_axis(Float64, cell, l, 1, 1)
(1.0, 0.0)
```
"""
function principal_axis end
# 1D: the axis itself (a division cuts the cell across its length, A-16)
@inline principal_axis(::Type{T}, cell, l::Lattice{1}, c, k) where {T} = (one(T),)
@inline function principal_axis(::Type{T}, cell, l::Lattice{2}, c, k) where {T}
    C = embed_covariance(l, covariance(T, cell, c, Val(2)))     # Cartesian axes
    λ = principal_moments(C)[k]
    a, b, d = C
    v = if abs(b) > eps(T) * (abs(a) + abs(d))
        (λ - d, b)
    elseif (a >= d) == (k == 1)
        (one(T), zero(T))
    else
        (zero(T), one(T))
    end
    n = sqrt(v[1]^2 + v[2]^2)
    return (v[1] / n, v[2] / n)
end
@inline function principal_axis(::Type{T}, cell, l::Lattice{3}, c, k) where {T}
    C = covariance(T, cell, c, Val(3))
    λ = principal_moments(C)[k]
    a, b, e, d, f, g = C[1], C[2], C[3], C[4], C[5], C[6]      # [a b e; b d f; e f g]
    r1 = (a - λ, b, e)
    r2 = (b, d - λ, f)
    r3 = (e, f, g - λ)
    function cross(u, v)
        return (
            u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1],
        )
    end
    cands = (cross(r1, r2), cross(r1, r3), cross(r2, r3))
    best = cands[1]
    nb = sum(abs2, best)
    for v in cands
        n = sum(abs2, v)
        n > nb && (best = v; nb = n)
    end
    o, z = one(T), zero(T)
    if nb < eps(T)^2
        if k == 1
            return (o, z, z)
        elseif k == 2
            return (z, o, z)
        else
            return (z, z, o)
        end
    end
    s = sqrt(nb)
    return (best[1] / s, best[2] / s, best[3] / s)
end

# ---------------------------------------------------------------------------------------
# Kernels

# A transition is applied before the division of the same cell (A-17, R8's "transition >
# divide"): the `kind` hook reads the cell before the state rules run (its columns are the
# parent's, the daughter holds their copy), both halves take the new kind, and the daughter
# state rule reads it.
@inline function _cell_rule_body!(
        c, events, daughter, kindf, divide!, cluster_divide!, st, p, ctx, key, mcs, ruled
    )
    # bounds: launched over c ∈ 1:capacity; daughters are cell ids ≤ capacity
    raw = @inbounds events[c]
    e = _event(ruled, raw)
    b = _base_event(e)
    d = @inbounds daughter[c]
    divides = d > 0 && (b == EVENT_DIVIDE || b == EVENT_DIVIDE_CLUSTER)
    if _transitions(e)
        k = kindf(st, p, ctx, key, mcs, Int32(c))
        @inbounds st.cell.kind[c] = k
        divides && (@inbounds st.cell.kind[d] = k)
    end
    return if divides
        if b == EVENT_DIVIDE
            _divide_rule!(ruled, divide!, st, p, ctx, key, mcs, Int32(c), d, raw)
        else
            _divide_rule!(ruled, cluster_divide!, st, p, ctx, key, mcs, Int32(c), d, raw)
        end
    end
end

# ---------------------------------------------------------------------------------------
# Scratch

"""Lifecycle scratch: buffers sized by capacity on the state's backend, and the planner's
state (`LifecyclePlanner`)."""
struct LifecycleCache{E, D, R, NM, B, DL}
    events::E
    daughter::D
    removed::R
    normals::NM
    bias::B
    device::DL
end

function LifecycleCache(
        backend, N::Int, capacity::Int, st = nothing; fused_limits = (;)
    )
    T = Exec.default_float(backend)
    return LifecycleCache(
        KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Bool, capacity),
        KernelAbstractions.zeros(backend, T, N, capacity),
        KernelAbstractions.zeros(backend, T, capacity),
        LifecyclePlanner(backend, N, capacity, st; fused_limits...)
    )
end

Base.@kwdef mutable struct LifecycleStats
    divisions::Int = 0
    removals::Int = 0
    transitions::Int = 0
    deferred::Int = 0
    empty_daughters::Int = 0
end

"""
    rebuild_trackers!(st, ctx, backend) -> st

Recompute the built-in trackers in `st.cell` exactly from `σ`, on the host.

The trackers are `volume`, `surface` (over `ctx.surface`, if both exist), `euler` and
`euler_full`, the `pieces` columns, the moments (`anchor`, `m1`, `m2`), the cluster
trackers (`cluster_volume`, `cluster_surface`) and the contact counts named in
`ctx.contact_counts`. Use it after host edits of `σ`.

# Arguments
- `st`: the state.
- `ctx`: the run context, with `lattice` and the relations.
- `backend`: the KernelAbstractions backend of `st`.

# Returns
- `st`, with the trackers updated in place.
"""
rebuild_trackers!(st, ctx, backend) = _rebuild_trackers!(nothing, st, ctx, backend)

# `stats`: the integrator's `PottsStats` counting the host transfers (D-085), or `nothing`
function _rebuild_trackers!(stats, st, ctx, backend)
    sync!(stats, backend)
    σ = to_host(stats, st.ownership)
    lat = host_lattice(stats, ctx.lattice)
    ctx = merge(ctx, (; lattice = lat))
    cap = length(st.cell.kind)
    volume = zeros(Int32, cap)
    for s in σ
        s > 0 && (volume[s] += Int32(1))
    end
    counted_copy!(stats, st.cell.volume, volume)
    if haskey(st.cell, :surface) && haskey(ctx, :surface)
        T = eltype(st.cell.surface)
        counted_copy!(
            stats, st.cell.surface, _recompute_surface(T, σ, lat, ctx.surface, cap)
        )
    end
    _rebuild_euler!(stats, st, σ, lat, cap)
    _rebuild_pieces!(stats, st, σ, lat, cap)
    if haskey(st.cell, :m1)
        m = init_moments(σ, lat, cap)
        counted_copy!(stats, st.cell.anchor, m.anchor)
        counted_copy!(stats, st.cell.m1, m.m1)
        counted_copy!(stats, st.cell.m2, m.m2)
    end
    _has_clusters(st) && _rebuild_cluster_trackers!(stats, st, σ, ctx)
    _rebuild_contact_counts!(stats, st, σ, lat, _contact_counts(ctx))
    return st
end

"""
    with_capacity(st, capacity) -> CPMState

Return a state like the host state `st` whose cell quantities have `capacity` slots.

Free slots have volume 0, kind 1 and generation 0, and with a `cluster` column each free
slot is its own cluster. The cell columns are new arrays; `ownership` and the site, model
and history parts are shared with `st`. History rings are not resized: build rings of
cell quantities after `with_capacity` (a `HistoryPush` with a mismatched ring is an
error). Lifecycle models preallocate capacity this way.

# Arguments
- `st::CPMState`: the state, on the host.
- `capacity::Integer`: the number of cell slots, at least the current number.

# Returns
- `CPMState`.

# Examples
```jldoctest
julia> using CorePotts

julia> st = with_capacity(initial_state(Int32[1 0; 2 2], [1, 2]), 4);

julia> st.cell.kind, st.cell.volume
(Int32[1, 2, 1, 1], Int32[1, 2, 0, 0])
```

See also [`Lifecycle`](@ref).
"""
function with_capacity(st::CPMState, capacity::Integer)
    n = length(st.cell.kind)
    capacity >= n || throw(ArgumentError("capacity $capacity < $n existing cells"))
    function grow(a::AbstractVector)
        b = similar(a, capacity)
        fill!(b, zero(eltype(a)))
        b[1:n] .= a
        return b
    end
    function grow(a::AbstractArray)
        b = similar(a, (size(a)[1:(end - 1)]..., capacity))
        fill!(b, zero(eltype(a)))
        b[ntuple(_ -> Colon(), ndims(a) - 1)..., 1:n] .= a
        return b
    end
    cell = map(grow, st.cell)
    cell.kind[(n + 1):end] .= Int32(1)
    haskey(cell, :cluster) && (cell.cluster[(n + 1):end] .= Int32.((n + 1):capacity))
    return CPMState(st.ownership, cell, st.site, st.model, st.history)
end

_is_link_data(name::Symbol) = _is_adjacency(name) || startswith(String(name), "link_")
