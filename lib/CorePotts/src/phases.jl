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

Run `f!(st, p, ctx, key, mcs, i)` for every site `i` (linear index), in parallel.
"""
struct SitePhase{F}
    f!::F
end

"""
    CellPhase(f!)

Run `f!(st, p, ctx, key, mcs, c)` for every cell id `c` in `1:ncells(st)`, in parallel.
"""
struct CellPhase{F}
    f!::F
end

# Every kernel is a body `body(i, args...)` run for `i in 1:n` by `Exec.launch!`
# (LatticeFields): the host executor on the CPU (plain loops; threaded chunks for large `n`),
# the one generic `if`-guarded device kernel elsewhere (v3 §4.4). A warm MCS on the CPU
# allocates nothing (no KernelAbstractions CPU launch).

# Device→device copies and fills in the step path (P6.0v8, D-101). Metal.jl's `copyto!`
# between device arrays synchronizes before its blit and waits for it (two GPU waits per
# copy), and its `fill!` of 1-byte elements is a waiting blit; a kernel enqueues and returns.
# On the CPU both stay the Base calls they were.
@inline _copy_body!(i, dst, src) = (@inbounds dst[i] = src[i]; nothing)     # i ≤ length(src) ≤ length(dst)
@inline _fill_body!(i, dst, v) = (@inbounds dst[i] = v; nothing)            # i ≤ length(dst)

"""`copyto!(dst, src)` of two arrays on `backend` without a GPU wait: one kernel on a device
(returns nothing; enqueued, not synchronized)."""
function _device_copy!(backend, dst::AbstractArray, src::AbstractArray)
    length(dst) >= length(src) || throw(DimensionMismatch("destination has $(length(dst)) elements, the source $(length(src))"))
    isempty(src) && return nothing                       # no zero-size kernel launch
    Exec.launch!(backend, _copy_body!, length(src), (dst, src))
    return nothing
end
_device_copy!(::KernelAbstractions.CPU, dst::AbstractArray, src::AbstractArray) = (copyto!(dst, src); nothing)

"""`fill!(dst, v)` on `backend` without a GPU wait: one kernel on a device."""
function _device_fill!(backend, dst::AbstractArray, v)
    isempty(dst) && return nothing
    Exec.launch!(backend, _fill_body!, length(dst), (dst, convert(eltype(dst), v)))
    return nothing
end
_device_fill!(::KernelAbstractions.CPU, dst::AbstractArray, v) = (fill!(dst, v); nothing)

@inline _site_phase_body!(i, f!::F, st, p, ctx, key, mcs) where {F} =
    (in_domain(ctx.lattice, i) && f!(st, p, ctx, key, mcs, i); nothing)
@inline _cell_phase_body!(c, f!::F, st, p, ctx, key, mcs) where {F} =
    (f!(st, p, ctx, key, mcs, c % Int32); nothing)         # c ≤ ncells < 2^31

function (ph::SitePhase{F})(st, p, ctx, key, mcs, backend) where {F}
    Exec.launch!(backend, _site_phase_body!, nsites(ctx.lattice), (ph.f!, st, p, ctx, key, mcs))
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

Run `f!(st, p, ctx, key, mcs)` once (a single work item): model-scope updates, e.g. a
reduction over the population written to `st.model`. Sequential on the device by design;
use `CellReduce` for large parallel reductions.
"""
struct ModelPhase{F}
    f!::F
end

@inline _model_phase_body!(_, f!::F, st, p, ctx, key, mcs) where {F} = (f!(st, p, ctx, key, mcs); nothing)

function (ph::ModelPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    Exec.launch!(backend, _model_phase_body!, 1, (ph.f!, st, p, ctx, key, mcs))
    return 1
end

"""State accessor `st.<A>.<B>`, resolved at compile time like a `NamedTuple` field."""
struct Part{A, B} end
Part(path::Tuple{Symbol, Symbol}) = Part{path[1], path[2]}()
@inline (::Part{A, B})(st) where {A, B} = getfield(getfield(st, A), B)

"""
    CopyPhase(dst => src)

Copy one state array into another (`(:site, :u) => (:site, :u_next)`), publishing a
double-buffered result. One pair per phase keeps every access static.
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
    HistoryPush(:name => (:site, :u))

Push the current value of the source into the ring buffer `st.history.name`, an array with
one extra trailing dimension of length `depth`. Slot `mod1(mcs + 1, depth)` receives the
value at the end of MCS `mcs`; `history_slot(depth, mcs, lag)` addresses a lag.
"""
struct HistoryPush{D <: Part, S <: Part}
    ring::D
    src::S
end
HistoryPush(pair::Pair) = HistoryPush(Part((:history, pair.first)), Part(pair.second))

@inline _history_body!(i, ring, src, slot, n) = (@inbounds ring[i + (slot - 1) * n] = src[i]; nothing)

function (ph::HistoryPush)(st, p, ctx, key, mcs, backend)
    ring = ph.ring(st)
    s = ph.src(st)
    # host-side shape check: the kernel indexes the ring by the source's length
    size(ring)[1:(end - 1)] == size(s) || throw(DimensionMismatch(
        "history ring $(size(ring)) does not match its source $(size(s)) plus a depth axis " *
        "(grow rings with the state, e.g. `with_capacity`)"))
    depth = size(ring, ndims(ring))
    n = length(s)
    Exec.launch!(backend, _history_body!, n, (ring, s, mod1(mcs + 1, depth), n))
    return 1
end

"""Ring-buffer slot holding the value `lag` MCS before the end of MCS `mcs` (lag 0 = latest)."""
@inline history_slot(depth, mcs, lag) = mod1(mcs + 1 - lag, depth)

"""
    history_buffer(x, depth)

A ring buffer for snapshots of array `x` (all slots start as copies of `x`).
"""
history_buffer(x::AbstractArray, depth::Integer) =
    repeat(x, ntuple(_ -> 1, ndims(x))..., depth)

"""
    SweepPhase()

The copy sweep as an entry of an MCS order (`Phases(; mcs)`): `step!` runs the algorithm's
sweep (`SequentialCPM` or `CheckerboardCPM`) where the order lists it.
"""
struct SweepPhase end

"""
    Repeat(n, entries)

An entry of an MCS order (`Phases(; mcs)`) that runs `entries` (a tuple of phase tuples and
at most one [`SweepPhase`](@ref)`()`) `n` times in one MCS: the sub-MCS interleave. The sweep
inside runs `1/n` of the MCS per pass. Pass `j` of `n` makes these copy attempts:

- `SequentialCPM`: attempts `(j-1)·N÷n+1 : j·N÷n` of the MCS's `N`, with their own draws.
- `CheckerboardCPM`: the phases `(j-1)·P÷n+1 : j·P÷n` of the MCS's `P` block phases. `n` must
  divide the phase count `P`.

With nothing else in `entries`, the `n` passes make exactly the copies of one plain sweep.
`SequentialCPM(; skip_interior = true)` takes no `Repeat` with `n > 1`.
"""
struct Repeat{E}
    n::Int
    entries::E
    function Repeat(n::Integer, entries::Tuple)
        n >= 1 || throw(ArgumentError("Repeat: the count must be ≥ 1; got $n"))
        all(x -> x isa Union{Tuple, SweepPhase}, entries) || throw(ArgumentError(
            "Repeat: the entries are tuples of phases and at most one SweepPhase() (no lifecycle, no nested Repeat)"))
        count(x -> x isa SweepPhase, entries) <= 1 || throw(ArgumentError("Repeat: at most one SweepPhase()"))
        return new{typeof(entries)}(Int(n), entries)
    end
end

"""
    LifecyclePhase()

The lifecycle (divisions, removals, transitions; `CPMFunction(…; lifecycle)`) as an entry of
an MCS order (`Phases(; mcs)`). Nothing runs at it when the model has no lifecycle.
"""
struct LifecyclePhase end

"""
    Phases(; before_mcs, after_mcs, end_mcs, at_init, mcs)

Phases of every MCS: `before_mcs` before the copy sweep, `after_mcs` after it, `end_mcs`
after the lifecycle (the state at the MCS boundary: history pushes, derived quantities);
`at_init` once when an integrator is created (derived quantities of the initial state; a
[`FieldPhase`](@ref) clamp in it runs only on a fresh state, not on `init` from a checkpoint).

`mcs` is the order `step!` runs, one static tuple whose entries are tuples of phases and the
sentinels [`SweepPhase`](@ref)`()` and [`LifecyclePhase`](@ref)`()` (each exactly once; the
sweep may sit in a [`Repeat`](@ref)).
Without it the order is today's, `(before_mcs, SweepPhase(), after_mcs, LifecyclePhase(),
end_mcs)`; the positional form `Phases(before_mcs, after_mcs, end_mcs, at_init)` means the
same. With an explicit `mcs`, `before_mcs`, `after_mcs` and `end_mcs` name the phases by role
(for inspection) and are not run themselves: `mcs` is (Potts' `@schedule` builds one).
`step!` is one fold over `mcs`, unrolled at compile time (recursion over the tuple, inlined).
"""
struct Phases{B, A, E, I, M}
    before_mcs::B
    after_mcs::A
    end_mcs::E
    at_init::I
    mcs::M
    function Phases(before_mcs::B, after_mcs::A, end_mcs::E, at_init::I, mcs::M) where {B, A, E, I, M}
        _check_order(mcs)
        return new{B, A, E, I, M}(before_mcs, after_mcs, end_mcs, at_init, mcs)
    end
end
Phases(before_mcs, after_mcs, end_mcs, at_init) =
    Phases(before_mcs, after_mcs, end_mcs, at_init, default_order(before_mcs, after_mcs, end_mcs))
function Phases(; before_mcs = (), after_mcs = (), end_mcs = (), at_init = (), mcs = nothing)
    b, a, e = Tuple(before_mcs), Tuple(after_mcs), Tuple(end_mcs)
    return Phases(b, a, e, Tuple(at_init), mcs === nothing ? default_order(b, a, e) : Tuple(mcs))
end
Phases(before_mcs, after_mcs) = Phases(before_mcs, after_mcs, (), ())

"""The MCS order without a schedule: `(before_mcs, SweepPhase(), after_mcs, LifecyclePhase(), end_mcs)`."""
default_order(before_mcs, after_mcs, end_mcs) = (before_mcs, SweepPhase(), after_mcs, LifecyclePhase(), end_mcs)

function _check_order(mcs)
    mcs isa Tuple || throw(ArgumentError("Phases: `mcs` is a tuple of phase tuples and the sentinels SweepPhase(), LifecyclePhase()"))
    nsweep = count(x -> x isa SweepPhase, mcs) + sum(r -> r isa Repeat ? count(x -> x isa SweepPhase, r.entries) : 0, mcs; init = 0)
    nsweep == 1 || throw(ArgumentError("Phases: the MCS order `mcs` must list SweepPhase() exactly once"))
    count(x -> x isa LifecyclePhase, mcs) == 1 ||
        throw(ArgumentError("Phases: the MCS order `mcs` must list LifecyclePhase() exactly once"))
    all(x -> x isa Union{Tuple, SweepPhase, LifecyclePhase, Repeat}, mcs) || throw(ArgumentError(
        "Phases: each entry of the MCS order `mcs` is a tuple of phases, SweepPhase(), LifecyclePhase() or a Repeat"))
    # `_run_mcs!` folds the order with `Base.afoldl`, which unrolls (one call specialized per
    # entry) only up to 31 entries
    length(mcs) <= 31 || throw(ArgumentError("Phases: the MCS order `mcs` has $(length(mcs)) entries; " *
                                             "at most 31 (group consecutive phases into one tuple)"))
    return nothing
end
const NO_PHASES = Phases((), (), (), ())

"""
Enqueue every phase; returns the number of launches. `stats` (the integrator's
`PottsStats`, or `nothing`) counts the host transfers of phases that make them.
"""
_run_phases(phases::Tuple, st, p, ctx, key, mcs, backend, stats = nothing, part::NTuple{2, Int} = (1, 1)) =
    sum(ph -> _run_phase(ph, st, p, ctx, key, mcs, backend, stats, part), phases; init = 0)

"""
    _run_phase(phase, st, p, ctx, key, mcs, backend, stats)

Internal: run one phase, `phase(st, p, ctx, key, mcs, backend)`, with the integrator's
transfer counters. Not an extension point for users: host work in a phase goes through the
public `HostPhase`, which counts its copies. CorePotts' and Potts' own phases that copy
between the host and a device add a method that routes the copies through the counted
helpers (`_sync!`, `_to_host`, `_copy!`, `_snapshot`); a wrapper phase forwards `stats` to
the phase it wraps.
"""
_run_phase(ph::P, st, p, ctx, key, mcs, backend, stats) where {P} = ph(st, p, ctx, key, mcs, backend)
# with the pass `part = (j, n)` of a sub-MCS `Repeat` (only a field phase reads it, fields.jl)
_run_phase(ph::P, st, p, ctx, key, mcs, backend, stats, part) where {P} = _run_phase(ph, st, p, ctx, key, mcs, backend, stats)

"""Accepted-copy affect: reset `array[target]` to `value` when ownership changes."""
@inline clear_on_copy!(array, prop, value) = (@inbounds array[prop.target] = value; nothing)
