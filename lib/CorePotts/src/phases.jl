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

@kernel function _site_phase_kernel!(f!, st, p, ctx, key, mcs)
    i = @index(Global, Linear)
    f!(st, p, ctx, key, mcs, i)
end

@kernel function _cell_phase_kernel!(f!, st, p, ctx, key, mcs)
    c = @index(Global, Linear)
    f!(st, p, ctx, key, mcs, Int32(c))
end

function (ph::SitePhase{F})(st, p, ctx, key, mcs, backend) where {F}
    n = nsites(ctx.lattice)
    _site_phase_kernel!(backend)(ph.f!, st, p, ctx, key, mcs;
        ndrange = n, workgroupsize = _phase_groupsize(backend, n))
    return 1
end

function (ph::CellPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    n = ncells(st)
    n == 0 && return 0
    _cell_phase_kernel!(backend)(ph.f!, st, p, ctx, key, mcs;
        ndrange = n, workgroupsize = _phase_groupsize(backend, n))
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
    copyto!(ph.dst(st), ph.src(st))
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

@kernel function _history_kernel!(ring, @Const(src), slot, n)
    i = @index(Global, Linear)
    @inbounds ring[i + (slot - 1) * n] = src[i]
end

function (ph::HistoryPush)(st, p, ctx, key, mcs, backend)
    ring = ph.ring(st)
    s = ph.src(st)
    depth = size(ring, ndims(ring))
    n = length(s)
    _history_kernel!(backend)(ring, s, mod1(mcs + 1, depth), n; ndrange = n,
        workgroupsize = _phase_groupsize(backend, n))
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

"""Phases run before and after the copy sweep of every MCS."""
struct Phases{B, A}
    before_mcs::B
    after_mcs::A
end
Phases(; before_mcs = (), after_mcs = ()) = Phases(Tuple(before_mcs), Tuple(after_mcs))
const NO_PHASES = Phases((), ())

"""Enqueue every phase; returns the number of launches."""
_run_phases(phases::Tuple, st, p, ctx, key, mcs, backend) =
    sum(ph -> ph(st, p, ctx, key, mcs, backend), phases; init = 0)

"""Accepted-copy affect: reset `array[target]` to `value` when ownership changes."""
@inline clear_on_copy!(array, prop, value) = (@inbounds array[prop.target] = value; nothing)
