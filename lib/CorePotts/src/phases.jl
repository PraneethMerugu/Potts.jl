# Synchronous phases around the copy sweep (INTERNALS §1.6, D-033).
#
# A phase is any callable `phase(st, p, ctx, key, mcs, backend)` that enqueues work without
# synchronizing. The built-in kinds are kernel bodies run by `Exec.launch!`:
#
#   SitePhase(f!)   f!(st, p, ctx, key, mcs, i)   for every site i
#   CellPhase(f!)   f!(st, p, ctx, key, mcs, c)   for every cell c
#   CopyPhase(dst => src)                           publish a double-buffered result
#   HistoryPush(:name => source)                    ring-buffer snapshot
#
# Bulk-synchronous semantics: a phase that reads neighbours of a quantity it also updates
# writes to a scratch array and is followed by a `CopyPhase`; this is what generated code
# emits. Randomness inside a phase is addressed by (mcs, entity, stream) as everywhere else.

"""
    SitePhase(f!)

A phase that runs `f!(st, p, ctx, key, mcs, i)` for every site `i` in the domain, in
parallel.

`i` is the linear site index. Sites outside the lattice domain are skipped. The phase
enqueues one kernel and does not synchronize. A phase that reads neighbors of a quantity
that it also updates writes to a scratch array, followed by a [`CopyPhase`](@ref).

# Arguments
- `f!`: the site function. `key` and `mcs` address its random draws ([`draw`](@ref)).

# Examples
```julia
decay = SitePhase((st, p, ctx, key, mcs, i) -> (st.site.u[i] *= 0.99; nothing))
phases = Phases(; after_mcs = (decay,))
```

See also [`CellPhase`](@ref), [`ModelPhase`](@ref), [`Phases`](@ref).
"""
struct SitePhase{F}
    f!::F
end

"""
    CellPhase(f!)

A phase that runs `f!(st, p, ctx, key, mcs, c)` for every cell slot `c` in
`1:ncells(st)`, in parallel.

`c` is passed as an `Int32`. Free slots (volume 0) are visited too. With no cell slots the
phase launches nothing.

# Arguments
- `f!`: the cell function.

# Examples
```julia
grow = CellPhase((st, p, ctx, key, mcs, c) -> (st.cell.target[c] += 0.1; nothing))
```

See also [`SitePhase`](@ref), [`CellReduce`](@ref), [`Phases`](@ref).
"""
struct CellPhase{F}
    f!::F
end

# Every kernel is a body `body(i, args...)` run for `i in 1:n` by `Exec.launch!`
# (LatticeFields): the host executor on the CPU (plain loops; threaded chunks for large
# `n`), the one generic `if`-guarded device kernel elsewhere. A warm MCS on the CPU
# allocates nothing (no KernelAbstractions CPU launch).

# Device→device copies and fills in the step path (D-101). Metal.jl's `copyto!`
# between device arrays synchronizes before its blit and waits for it (two GPU waits per
# copy), and its `fill!` of 1-byte elements is a waiting blit; a kernel enqueues and
# returns. On the CPU both stay the Base calls they were.
# i ≤ length(src) ≤ length(dst)
@inline _copy_body!(i, dst, src) = (@inbounds dst[i] = src[i]; nothing)
# i ≤ length(dst)
@inline _fill_body!(i, dst, v) = (@inbounds dst[i] = v; nothing)

"""`copyto!(dst, src)` of two arrays on `backend` without a GPU wait: one kernel on a device
(returns nothing; enqueued, not synchronized)."""
function _device_copy!(backend, dst::AbstractArray, src::AbstractArray)
    length(dst) >= length(src) ||
        throw(DimensionMismatch("destination has $(length(dst)) elements, the \
            source $(length(src))"))
    isempty(src) && return nothing                       # no zero-size kernel launch
    Exec.launch!(backend, _copy_body!, length(src), (dst, src))
    return nothing
end
function _device_copy!(::KernelAbstractions.CPU, dst::AbstractArray, src::AbstractArray)
    (copyto!(dst, src); nothing)
end

"""`fill!(dst, v)` on `backend` without a GPU wait: one kernel on a device."""
function _device_fill!(backend, dst::AbstractArray, v)
    isempty(dst) && return nothing
    Exec.launch!(backend, _fill_body!, length(dst), (dst, convert(eltype(dst), v)))
    return nothing
end
_device_fill!(::KernelAbstractions.CPU, dst::AbstractArray, v) = (fill!(dst, v); nothing)

@inline function _site_phase_body!(i, f!::F, st, p, ctx, key, mcs) where {F}
    in_domain(ctx.lattice, i) && f!(st, p, ctx, key, mcs, i)
    return nothing
end
@inline function _cell_phase_body!(c, f!::F, st, p, ctx, key, mcs) where {F}
    f!(st, p, ctx, key, mcs, c % Int32)
    return nothing
end         # c ≤ ncells < 2^31

function (ph::SitePhase{F})(st, p, ctx, key, mcs, backend) where {F}
    Exec.launch!(
        backend, _site_phase_body!, nsites(ctx.lattice), (
            ph.f!, st, p, ctx, key, mcs,
        )
    )
    return 1
end

function (ph::CellPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    n = ncells(st)
    n == 0 && return 0
    Exec.launch!(backend, _cell_phase_body!, n, (ph.f!, st, p, ctx, key, mcs))
    return 1
end

"""
    ModelPhase(f!)

A phase that runs `f!(st, p, ctx, key, mcs)` once, as a single work item.

Use it for model-scope updates, for example a reduction over the cells written to
`st.model`. It runs sequentially on a device; use [`CellReduce`](@ref) for large parallel
reductions.

# Arguments
- `f!`: the model function.

See also [`CellPhase`](@ref), [`Phases`](@ref).
"""
struct ModelPhase{F}
    f!::F
end

@inline function _model_phase_body!(_, f!::F, st, p, ctx, key, mcs) where {F}
    f!(st, p, ctx, key, mcs)
    return nothing
end

function (ph::ModelPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    Exec.launch!(backend, _model_phase_body!, 1, (ph.f!, st, p, ctx, key, mcs))
    return 1
end

"""
    Part((A, B))
    Part{A, B}()

A state accessor: `Part{A, B}()(st)` returns `getfield(getfield(st, A), B)`, as
`st.A.B`.

The names are type parameters, so the access compiles like a `NamedTuple` field.
[`CopyPhase`](@ref) and [`HistoryPush`](@ref) use it.

# Arguments
- `(A, B)::Tuple{Symbol, Symbol}`: the state part and the array name, for example
  `(:site, :u)`.

# Examples
```jldoctest
julia> using CorePotts

julia> st = initial_state(Int32[0 1], [1]);

julia> CorePotts.Part((:cell, :volume))(st)
1-element Vector{Int32}:
 1
```
"""
struct Part{A, B} end
Part(path::Tuple{Symbol, Symbol}) = Part{path[1], path[2]}()
@inline (::Part{A, B})(st) where {A, B} = getfield(getfield(st, A), B)

"""
    CopyPhase(dst => src)

A phase that copies one state array into another, to publish a double-buffered result.

Each side is a pair of names, for example `(:site, :u) => (:site, :u_next)`. One pair per
phase keeps every access static. On a device the copy is one kernel that does not
synchronize. The destination must have at least as many elements as the source.

# Arguments
- `dst => src`: a `Pair` of `(part, name)` tuples.

# Examples
```julia
publish = CopyPhase((:site, :u) => (:site, :u_next))
```

See also [`SitePhase`](@ref), [`Part`](@ref).
"""
struct CopyPhase{D <: Part, S <: Part}
    dst::D
    src::S
end
CopyPhase(pair::Pair) = CopyPhase(Part(pair.first), Part(pair.second))

function (ph::CopyPhase)(st, p, ctx, key, mcs, backend)
    _device_copy!(backend, ph.dst(st), ph.src(st))
    return 1
end

"""
    HistoryPush(:name => (part, array))

A phase that pushes the current value of a state array into the ring buffer
`st.history.name`.

The ring has the source's shape plus one trailing axis of length `depth`
([`history_buffer`](@ref)). At MCS `mcs` the push writes slot `mod1(mcs + 1, depth)`, and
[`history_slot`](@ref)`(depth, mcs, lag)` addresses the value `lag` pushes earlier. A ring
whose shape does not match its source throws a `DimensionMismatch`.

# Arguments
- `:name => (part, array)`: the ring's name in `st.history`, and the source, for example
  `:u_hist => (:site, :u)`.

# Examples
```julia
st = initial_state(σ, kinds; site = (; u), history = (; u_hist = history_buffer(u, 4)))
phases = Phases(; end_mcs = (HistoryPush(:u_hist => (:site, :u)),))
```

See also [`history_buffer`](@ref), [`history_slot`](@ref).
"""
struct HistoryPush{D <: Part, S <: Part}
    ring::D
    src::S
end
HistoryPush(pair::Pair) = HistoryPush(Part((:history, pair.first)), Part(pair.second))

# bounds: i ≤ n = length(src); slot ≤ the ring's depth, so the index ≤ length(ring)
@inline function _history_body!(i, ring, src, slot, n)
    @inbounds ring[i + (slot - 1) * n] = src[i]
    return nothing
end

function (ph::HistoryPush)(st, p, ctx, key, mcs, backend)
    ring = ph.ring(st)
    s = ph.src(st)
    # host-side shape check: the kernel indexes the ring by the source's length
    size(ring)[1:(end - 1)] == size(s) || throw(
        DimensionMismatch(
            "history ring $(size(ring)) does not match its source $(size(s)) plus a " *
                "depth axis (grow rings with the state, e.g. `with_capacity`)"
        )
    )
    depth = size(ring, ndims(ring))
    n = length(s)
    Exec.launch!(backend, _history_body!, n, (ring, s, mod1(mcs + 1, depth), n))
    return 1
end

"""
    history_slot(depth, mcs, lag) -> Int

Return the ring-buffer slot that holds the value pushed `lag` MCS before MCS `mcs`, as
[`HistoryPush`](@ref) writes it.

`lag = 0` is the latest push. The slot is `mod1(mcs + 1 - lag, depth)`.

# Arguments
- `depth`: the ring's depth.
- `mcs`: the current MCS.
- `lag`: how many pushes back, in `0:depth-1`.

# Returns
- `Int`: the slot, in `1:depth`.

# Examples
```jldoctest
julia> using CorePotts

julia> history_slot(4, 10, 0), history_slot(4, 10, 1)
(3, 2)
```

See also [`HistoryPush`](@ref), [`history_buffer`](@ref).
"""
@inline history_slot(depth, mcs, lag) = mod1(mcs + 1 - lag, depth)

"""
    history_buffer(x, depth) -> AbstractArray

Return a ring buffer for snapshots of the array `x`: `x` repeated along one new trailing
axis of length `depth`.

Every slot starts as a copy of `x`.

# Arguments
- `x::AbstractArray`: the array to record.
- `depth::Integer`: the number of slots.

# Returns
- An array of size `(size(x)..., depth)`.

# Examples
```jldoctest
julia> using CorePotts

julia> size(history_buffer(zeros(3, 2), 4))
(3, 2, 4)
```

See also [`HistoryPush`](@ref), [`history_slot`](@ref).
"""
function history_buffer(x::AbstractArray, depth::Integer)
    return repeat(x, ntuple(_ -> 1, ndims(x))..., depth)
end

"""
    SweepPhase()

The copy sweep, as an entry of an MCS order (`Phases(; mcs)`).

`step!` runs the algorithm's sweep ([`SequentialCPM`](@ref) or [`CheckerboardCPM`](@ref))
where the order lists it. The order lists it exactly once, possibly inside a
[`Repeat`](@ref).

See also [`Phases`](@ref), [`LifecyclePhase`](@ref).
"""
struct SweepPhase end

"""
    Repeat(n, entries)

An entry of an MCS order (`Phases(; mcs)`) that runs `entries` `n` times in one MCS: the
sub-MCS interleave.

The sweep inside runs `1/n` of the MCS per pass. Pass `j` of `n` makes these copy
attempts:

- [`SequentialCPM`](@ref): attempts `(j-1)·N÷n+1 : j·N÷n` of the MCS's `N`, with their
  own draws.
- [`CheckerboardCPM`](@ref): the block phases `(j-1)·P÷n+1 : j·P÷n` of the MCS's `P`.
  `n` must divide `P`.

With nothing else in `entries`, the `n` passes make exactly the copies of one plain sweep.
`SequentialCPM(; skip_interior = true)` accepts no `Repeat` with `n > 1`.

# Arguments
- `n::Integer`: the number of passes, `≥ 1`.
- `entries::Tuple`: tuples of phases and at most one [`SweepPhase`](@ref)`()`. A lifecycle
  or a nested `Repeat` throws an `ArgumentError`.

# Examples
```julia
field_step = (SitePhase(diffuse!), CopyPhase((:site, :u) => (:site, :u_next)))
order = (Repeat(4, (field_step, SweepPhase())), LifecyclePhase())
phases = Phases(; mcs = order)
```

See also [`Phases`](@ref), [`SweepPhase`](@ref).
"""
struct Repeat{E}
    n::Int
    entries::E
    function Repeat(n::Integer, entries::Tuple)
        n >= 1 || throw(ArgumentError("Repeat: the count must be ≥ 1; got $n"))
        all(x -> x isa Union{Tuple, SweepPhase}, entries) || throw(
            ArgumentError(
                "Repeat: the entries are tuples of phases and at most one SweepPhase() \
                    (no lifecycle, no nested Repeat)"
            )
        )
        count(x -> x isa SweepPhase, entries) <= 1 ||
            throw(ArgumentError("Repeat: at most one SweepPhase()"))
        return new{typeof(entries)}(Int(n), entries)
    end
end

"""
    LifecyclePhase()

The lifecycle (divisions, removals and transitions; `CPMFunction(…; lifecycle)`), as an
entry of an MCS order (`Phases(; mcs)`).

Nothing runs at it when the model has no lifecycle. The order lists it exactly once, not
inside a [`Repeat`](@ref).

See also [`Phases`](@ref), [`Lifecycle`](@ref).
"""
struct LifecyclePhase end

"""
    Phases(; before_mcs = (), after_mcs = (), end_mcs = (), at_init = (), mcs = nothing)
    Phases(before_mcs, after_mcs)
    Phases(before_mcs, after_mcs, end_mcs, at_init)

The synchronous phases of every MCS, and the order that `step!` runs them in.

A phase is a callable `phase(st, p, ctx, key, mcs, backend)` that enqueues work without
synchronizing: [`SitePhase`](@ref), [`CellPhase`](@ref), [`ModelPhase`](@ref),
[`CopyPhase`](@ref), [`HistoryPush`](@ref), [`CellReduce`](@ref), [`HostPhase`](@ref),
[`FieldPhase`](@ref) or [`ContactPhase`](@ref).

Without `mcs`, the order is `(before_mcs, SweepPhase(), after_mcs, LifecyclePhase(),
end_mcs)`, and the positional forms mean the same. With an explicit `mcs`, the three role
tuples name the phases for inspection only and are not run; `mcs` is what runs. Potts'
`@schedule` builds one. `step!` unrolls the order at compile time.

# Keywords
- `before_mcs = ()`: phases before the sweep.
- `after_mcs = ()`: phases after the sweep, before the lifecycle.
- `end_mcs = ()`: phases after the lifecycle, on the state at the MCS boundary (history
  pushes, derived quantities).
- `at_init = ()`: phases run once when an integrator is created (derived quantities of the
  initial state). A [`FieldPhase`](@ref) clamp in it runs only on a fresh state, not at
  `init` from a checkpoint.
- `mcs = nothing`: the MCS order, a tuple whose entries are tuples of phases,
  [`Repeat`](@ref)s and the sentinels [`SweepPhase`](@ref)`()` and
  [`LifecyclePhase`](@ref)`()`. Each sentinel appears exactly once (the sweep may be in a
  `Repeat`), and the order has at most 31 entries. A wrong order throws an
  `ArgumentError`.

# Examples
```jldoctest
julia> using CorePotts

julia> ph = Phases(; after_mcs = (ModelPhase((st, p, ctx, key, mcs) -> nothing),));

julia> length(ph.mcs), ph.mcs[2]
(5, SweepPhase())
```

See also [`CPMFunction`](@ref), [`SweepPhase`](@ref), [`Repeat`](@ref).
"""
struct Phases{B, A, E, I, M}
    before_mcs::B
    after_mcs::A
    end_mcs::E
    at_init::I
    mcs::M
    function Phases(
            before_mcs::B, after_mcs::A, end_mcs::E,
            at_init::I, mcs::M
        ) where {B, A, E, I, M}
        _check_order(mcs)
        return new{B, A, E, I, M}(before_mcs, after_mcs, end_mcs, at_init, mcs)
    end
end
function Phases(before_mcs, after_mcs, end_mcs, at_init)
    return Phases(
        before_mcs, after_mcs, end_mcs, at_init,
        default_order(before_mcs, after_mcs, end_mcs)
    )
end
function Phases(;
        before_mcs = (), after_mcs = (), end_mcs = (), at_init = (), mcs = nothing
    )
    b, a, e = Tuple(before_mcs), Tuple(after_mcs), Tuple(end_mcs)
    return Phases(
        b, a, e, Tuple(at_init), mcs === nothing ? default_order(b, a, e) : Tuple(mcs)
    )
end
Phases(before_mcs, after_mcs) = Phases(before_mcs, after_mcs, (), ())

"""
The MCS order without a schedule:
`(before_mcs, SweepPhase(), after_mcs, LifecyclePhase(), end_mcs)`.
"""
function default_order(before_mcs, after_mcs, end_mcs)
    return (before_mcs, SweepPhase(), after_mcs, LifecyclePhase(), end_mcs)
end

function _check_order(mcs)
    mcs isa Tuple ||
        throw(ArgumentError("Phases: `mcs` is a tuple of phase tuples and the sentinels \
            SweepPhase(), LifecyclePhase()"))
    nsweep = count(x -> x isa SweepPhase, mcs) +
        sum(r -> r isa Repeat ? count(x -> x isa SweepPhase, r.entries) : 0, mcs; init = 0)
    nsweep == 1 ||
        throw(ArgumentError("Phases: the MCS order `mcs` must list SweepPhase() exactly \
            once"))
    count(x -> x isa LifecyclePhase, mcs) == 1 ||
        throw(ArgumentError("Phases: the MCS order `mcs` must list LifecyclePhase() \
            exactly once"))
    all(x -> x isa Union{Tuple, SweepPhase, LifecyclePhase, Repeat}, mcs) || throw(
        ArgumentError(
            "Phases: each entry of the MCS order `mcs` is a tuple of phases, \
                SweepPhase(), LifecyclePhase() or a Repeat"
        )
    )
    # `_run_mcs!` folds the order with `Base.afoldl`, which unrolls (one call specialized
    # per entry) only up to 31 entries
    length(mcs) <= 31 || throw(
        ArgumentError(
            "Phases: the MCS order `mcs` has $(length(mcs)) entries; " *
                "at most 31 (group consecutive phases into one tuple)"
        )
    )
    return nothing
end
const NO_PHASES = Phases((), (), (), ())

"""
    run_phases(phases, st, p, ctx, key, mcs, backend, stats = nothing, part = (1, 1)) -> Int

Enqueue every phase of the tuple `phases`, through [`run_phase`](@ref).

# Arguments
- `phases::Tuple`: the phases.
- `st`, `p`, `ctx`, `key`, `mcs`, `backend`: the state, parameters, context, random key,
  MCS number and backend.
- `stats = nothing`: the integrator's run statistics, which count the host transfers of
  the phases that make them, or `nothing`.
- `part::NTuple{2, Int} = (1, 1)`: the pass `(j, n)` of a sub-MCS [`Repeat`](@ref).

# Returns
- `Int`: the number of kernel launches.

See also [`run_phase`](@ref), [`Phases`](@ref).
"""
function run_phases(
        phases::Tuple, st, p, ctx, key, mcs, backend,
        stats = nothing, part::NTuple{2, Int} = (1, 1)
    )
    return sum(_RunPhase(st, p, ctx, key, mcs, backend, stats, part), phases; init = 0)
end
# `run_phase` summed over the phases (every MCS): a functor, not a per-call closure
struct _RunPhase{S, P, C, K, M, B, T}
    st::S
    p::P
    ctx::C
    key::K
    mcs::M
    backend::B
    stats::T
    part::NTuple{2, Int}
end
function (f::_RunPhase)(ph)
    return run_phase(
        ph, f.st, f.p, f.ctx, f.key, f.mcs, f.backend, f.stats, f.part
    )
end

"""
    run_phase(phase, st, p, ctx, key, mcs, backend, stats) -> Int
    run_phase(phase, st, p, ctx, key, mcs, backend, stats, part) -> Int

Run one phase, `phase(st, p, ctx, key, mcs, backend)`, with the integrator's transfer
counters.

This is a hook for model compilers, not for models: host work in a model's phase goes
through [`HostPhase`](@ref), which counts its copies. A phase that copies between the host
and a device adds a method that routes the copies through the counted helpers
([`sync!`](@ref), [`to_host`](@ref), [`counted_copy!`](@ref), [`snapshot`](@ref)). A
wrapper phase forwards `stats` to the phase it wraps. The form with `part` forwards to
the form without it, unless a phase (a field phase) adds a method that reads it.

# Arguments
- `phase`: the phase.
- `st`, `p`, `ctx`, `key`, `mcs`, `backend`: as for the phase call.
- `stats`: the run statistics, or `nothing`.
- `part::NTuple{2, Int}`: the pass `(j, n)` of a sub-MCS [`Repeat`](@ref).

# Returns
- `Int`: the number of kernel launches the phase made.

See also [`run_phases`](@ref).
"""
function run_phase(ph::P, st, p, ctx, key, mcs, backend, stats) where {P}
    return ph(st, p, ctx, key, mcs, backend)
end
# with the pass `part = (j, n)` of a sub-MCS `Repeat` (only a field phase reads it,
# fields.jl)
function run_phase(ph::P, st, p, ctx, key, mcs, backend, stats, part) where {P}
    return run_phase(ph, st, p, ctx, key, mcs, backend, stats)
end

# bounds: prop.target is a site index ≤ nsites = length(array)
"""
    clear_on_copy!(array, prop, value) -> nothing

Set `array[prop.target]` to `value`: a `commit!` effect that resets a site quantity when
the target changes cell.

# Arguments
- `array::AbstractArray`: the site array.
- `prop::Proposal`: the accepted copy.
- `value`: the reset value.

# Returns
- `nothing`.

# Examples
```julia
function commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    return clear_on_copy!(st.site.age, prop, 0)
end
```

See also [`commit_volume!`](@ref).
"""
@inline clear_on_copy!(array, prop, value) = (@inbounds array[prop.target] = value; nothing)
