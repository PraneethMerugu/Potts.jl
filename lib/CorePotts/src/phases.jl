# Synchronous phases around the copy sweep (INTERNALS §1.6, D-033).
#
# A phase is any callable `phase(st, p, ctx, key, mcs, backend)` that enqueues work without
# synchronizing. The built-in kinds are plain KernelAbstractions kernels:
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

# Every kernel is a thin `@kernel` around an `@inline` body `body(i, args...)`. `_launch` runs
# the body as a plain loop when the CPU backend would run the launch as one workgroup: a KA
# CPU launch allocates (argument tuple, boxed indices) even inline, and a warm MCS must not.
@kernel function _each_kernel!(body, args)
    i = @index(Global, Linear)          # KA's CPU backend needs `@index` as its own statement
    body(i, args...)
end

"""Run `body(i, args...)` for `i in 1:n` on `backend` (returns nothing, does not synchronize)."""
@inline function _launch(body::B, backend, n, args::A) where {B, A}
    if _inline(backend, n)
        for i in 1:n
            body(i, args...)
        end
    else
        _each_kernel!(backend)(body, args; ndrange = n, workgroupsize = _phase_groupsize(backend, n))
    end
    return nothing
end
_inline(backend, n) = false
_inline(backend::KernelAbstractions.CPU, n) = _groupsize(backend, n) >= n

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
    _launch(_copy_body!, backend, length(src), (dst, src))
    return nothing
end
_device_copy!(::KernelAbstractions.CPU, dst::AbstractArray, src::AbstractArray) = (copyto!(dst, src); nothing)

"""`fill!(dst, v)` on `backend` without a GPU wait: one kernel on a device."""
function _device_fill!(backend, dst::AbstractArray, v)
    _launch(_fill_body!, backend, length(dst), (dst, convert(eltype(dst), v)))
    return nothing
end
_device_fill!(::KernelAbstractions.CPU, dst::AbstractArray, v) = (fill!(dst, v); nothing)

@inline _site_phase_body!(i, f!::F, st, p, ctx, key, mcs) where {F} =
    (in_domain(ctx.lattice, i) && f!(st, p, ctx, key, mcs, i); nothing)
@inline _cell_phase_body!(c, f!::F, st, p, ctx, key, mcs) where {F} =
    (f!(st, p, ctx, key, mcs, c % Int32); nothing)         # c ≤ ncells < 2^31

function (ph::SitePhase{F})(st, p, ctx, key, mcs, backend) where {F}
    _launch(_site_phase_body!, backend, nsites(ctx.lattice), (ph.f!, st, p, ctx, key, mcs))
    return 1
end

function (ph::CellPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    n = ncells(st)
    n == 0 && return 0
    _launch(_cell_phase_body!, backend, n, (ph.f!, st, p, ctx, key, mcs))
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
    _launch(_model_phase_body!, backend, 1, (ph.f!, st, p, ctx, key, mcs))
    return 1
end

_phase_groupsize(backend, n) = nothing
_phase_groupsize(backend::KernelAbstractions.CPU, n) = _groupsize(backend, n)

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
    _launch(_history_body!, backend, n, (ring, s, mod1(mcs + 1, depth), n))
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
    Phases(; before_mcs, after_mcs, end_mcs, at_init)

Phases of every MCS: `before_mcs` before the copy sweep, `after_mcs` after it, `end_mcs`
after the lifecycle (the state at the MCS boundary: history pushes, derived quantities);
`at_init` once when an integrator is created (derived quantities of the initial state).
"""
struct Phases{B, A, E, I}
    before_mcs::B
    after_mcs::A
    end_mcs::E
    at_init::I
end
Phases(; before_mcs = (), after_mcs = (), end_mcs = (), at_init = ()) =
    Phases(Tuple(before_mcs), Tuple(after_mcs), Tuple(end_mcs), Tuple(at_init))
Phases(before_mcs, after_mcs) = Phases(before_mcs, after_mcs, (), ())
const NO_PHASES = Phases((), (), (), ())

"""
Enqueue every phase; returns the number of launches. `stats` (the integrator's
`PottsStats`, or `nothing`) counts the host transfers of phases that make them.
"""
_run_phases(phases::Tuple, st, p, ctx, key, mcs, backend, stats = nothing) =
    sum(ph -> _run_phase(ph, st, p, ctx, key, mcs, backend, stats), phases; init = 0)

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

"""Accepted-copy affect: reset `array[target]` to `value` when ownership changes."""
@inline clear_on_copy!(array, prop, value) = (@inbounds array[prop.target] = value; nothing)
