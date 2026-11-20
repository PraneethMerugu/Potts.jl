# Checkerboard dynamics (KernelAbstractions; CPU or GPU): the lockless block scheme
# (after Sultan et al., arXiv 2312.09317).
#
# Layout. Each axis of length L is cut into nb = max(1, L ÷ kb) blocks of k sub-regions each
# (`parts`), the k·nb sub-regions of side `base` = L ÷ k·nb or base + 1 (the first L mod k·nb),
# so a block is about kb wide and its k^d sub-regions are about b wide (`region`). A phase
# activates the same sub-region (offset o ∈ {0, …, k - 1}^d) in every block, and one work item
# per block makes its attempts there one after another: a uniform site of the sub-region, a
# uniform direction, ΔH against the live state, the acceptance draw, and on acceptance the
# write and `f.commit!` at once. Active sub-regions of two blocks are at least (k - 1)·b + 1
# apart (with two or more blocks on an axis, base ≥ b; across a periodic seam too), so with
# (k - 1)·b ≥ read + write no two work items read or write each other's sites. The read
# distance includes the window of a windowed `Global` search, so a search sees no concurrent
# write inside its box.
#
# Per MCS: P = k^d · switches phases, each drawn uniformly from the k^d offsets (with
# replacement). In a phase a work item makes n / switches attempts (n the active sub-region's
# sites; a fractional part is rounded by a draw), each at a uniform site of the sub-region, so
# every site is attempted once per MCS on average. Attempts are never skipped: drawing over a
# common box and skipping sites past a smaller sub-region's end bunches attempts on one site
# (a one-site sub-region in a 2 × 2 box got Binomial(4, 1/4) attempts in a row), which slowed
# Akeeb invasion and the OpenVT chain relaxation (docs/design/research/checkerboard-kinetics.md).
#
# Lockless cells. Nothing is claimed: per-cell totals change by atomic adds. The context carries
# `lockless = true`, so the commit hooks that would otherwise overwrite a cell value use
# atomic deltas: moments accumulate atomically and re-center once per MCS (`recenter_kernel!`),
# pieces trackers add their changes, and an `@on_copy` write that reads its own cell value adds
# the difference. On a device the outcome depends on the timing of the work items (no
# determinism, user ruling 2026-11-04).
#
# Cells wider than the spacing. The spacing separates sites, not cells: two active sites of one
# phase lie in one cell when the cell is wider than (k - 1)·region + 1, and then one work item's
# commit changes a total another item's decision is reading, so the accepted ΔH stops summing to
# the trajectory's energy change. Every phase is therefore checked before it runs
# (`_phase_conflict!`): a phase whose items share a cell runs inline, one work item after another
# in block order, on the live state, which is exact; a phase whose items share no cell is a
# colouring and runs threaded. Nothing is snapshotted: a colouring phase's items share no cell and
# write only their own sites, so the live columns they read cannot be changed under them.
#
# The CPU. A phase with few work items (at most `inline_max_blocks`), or a process with one thread,
# runs them inline, one after another, so each attempt sees every earlier one, as in
# `SequentialCPM`, and the run is reproducible. A larger phase is one KA launch with one
# workgroup per thread (KA's CPU backend spawns one task per thread and launch, so more
# workgroups only add loop overhead). A colouring phase reaches the same decisions and leaves the
# same state whether its work items run inline or threaded, and a shared-cell phase runs inline
# either way, so a CPU run is reproducible from its seed at any thread count.
#
# Whole-cell searches. A copy whose decision needs the exact floods (cell-scope `pieces` off
# their fast path, a `Global` without window whose local test fails) is not decided in the
# phase: its work item appends it to the serial list, and one work item runs the list after
# the phase (`serial_kernel!`), against the state the phase left, with nothing in flight. The
# CPU decides such copies in place when it runs a phase inline, else on the host after the
# phase.

struct BlockLayout{N}
    k::Int                            # sub-regions per block along each axis
    nblocks::NTuple{N, Int}
    base::NTuple{N, Int}
    rem::NTuple{N, Int}               # sub-regions of side base + 1 on the axis
    box::NTuple{N, Int}
end

function BlockLayout(dims::NTuple{N, Int}, b::Int, k::Int = 2) where {N}
    nb = ntuple(d -> max(1, dims[d] ÷ (k * b)), N)
    base = ntuple(d -> dims[d] ÷ (k * nb[d]), N)
    r = ntuple(d -> dims[d] - k * nb[d] * base[d], N)
    return BlockLayout{N}(k, nb, base, r, ntuple(d -> base[d] + (r[d] > 0), N))
end
boxsize(l::BlockLayout) = prod(l.box)
nblocks(l::BlockLayout) = prod(l.nblocks)

# the offset of phase `ph` (1:k^N) per axis: the base-k digits of `ph - 1` (host)
phase_offset(l::BlockLayout{N}, ph::Int) where {N} = ntuple(d -> rem(div(ph - 1, l.k^(d - 1)), l.k), Val(N))

# block number `blk` (1-based, first axis fastest) and its coordinates `bc` (0-based)
@inline block_index(l::BlockLayout{N}, bc::NTuple{N, Int}) where {N} =
    1 + foldl((a, d) -> a * l.nblocks[d] + bc[d], ntuple(d -> N + 1 - d, Val(N)); init = 0)
block_coords(l::BlockLayout{N}, blk::Int) where {N} =
    ntuple(d -> rem(div(blk - 1, prod(ntuple(e -> e < d ? l.nblocks[e] : 1, Val(N)))), l.nblocks[d]), Val(N))

# the active sub-region of the block at `bc` in a phase with offset `off`: its start (0-based)
# and side per axis
@inline function block_region(l::BlockLayout{N}, bc::NTuple{N, Int}, off::NTuple{N, Int}) where {N}
    rs = ntuple(Val(N)) do d
        j = l.k * bc[d] + off[d]                         # sub-region, 0-based
        (j * l.base[d] + min(j, l.rem[d]), l.base[d] + (j < l.rem[d]))
    end
    return map(first, rs), map(last, rs)
end
block_region(l::BlockLayout, blk::Int, ph::Int) = block_region(l, block_coords(l, blk), phase_offset(l, ph))

# the site of draw `r`, uniform over the sub-region with start `lo` and side `side` (a one-site
# sub-region, region 1's usual case, needs no division)
@inline function block_site(lo::NTuple{N, Int}, side::NTuple{N, Int}, r::UInt32) where {N}
    n = prod(side)
    n == 1 && return map(a -> a + 1, lo)
    u = bounded(r, n)                                    # 0:n - 1
    return ntuple(Val(N)) do d
        s = prod(ntuple(e -> e < d ? side[e] : 1, Val(N)))
        lo[d] + rem(div(u, s), side[d]) + 1
    end
end

# attempts in one stay: n / s, the fractional part rounded up with probability rem(n, s) / s
@inline _stay_attempts(n, s, r::UInt32) = div(n, s) + (bounded(r, s) < rem(n, s))

# draw local index of attempt k (1:n; 0 draws the stay's length) in the MCS's phase number q
# (1:P): both < 2^16 (checked)
@inline _block_lid(q, k) = UInt32(q) << 16 | UInt32(k)

# blk ≤ nblocks: one work item per block in a phase, and the serial pass runs alone
@inline _count!(cnt, blk) = (@inbounds cnt[blk] += Int32(1); nothing)

# The serial list (`nothing` without whole-cell connectivity): the deferred copies of a phase
# as (block, draw index) pairs, their count, the refusals for want of window (read into
# `stats.connectivity_deferred`), and whether a veto without window defers its undecided copies
# (`exact`). A copy is listed at most once per phase, so count ≤ length(blk).
@inline function _push_serial!(sl, blk, lid)
    i = Atomix.@atomic sl.count[1] += UInt32(1)          # count has one entry
    @inbounds sl.blk[i] = Int32(blk)
    @inbounds sl.lid[i] = lid
    return nothing
end


# One attempt. `SERIAL = false` in a phase (copies that need the floods are listed); `true` in
# the serial pass and on the CPU (the floods run, a veto decides at once).
@inline function block_attempt!(blk, st, f, p, ctx, law, key, mcs, lo, side, lid, tk, cnt, status, sl,
        ::Val{SERIAL}) where {SERIAL}
    lat = ctx.lattice
    rd, ra, rs, _ = draw(key, mcs, blk, STREAM_BLOCK, lid)
    x = block_site(lo, side, rs)
    t = linear_index(lat, x)
    dir = bounded(rd, length(ctx.proposal)) + 1
    inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
    (inside && is_mobile(ctx.mobility, t)) || return nothing
    s = linear_index(lat, y)
    is_mobile(ctx.mobility, s) || return nothing
    a = @inbounds st.ownership[t]
    b = @inbounds st.ownership[s]
    a == b && return nothing
    prop = Proposal(t, s, x, dir, a, b)
    if !SERIAL && has_defer(f) && _defer(f)(st, p, prop, ctx)
        _push_serial!(sl, blk, lid)
        return nothing
    end
    f.constraint(st, p, prop, ctx) || return nothing
    dH0 = f.delta_H(st, p, prop, ctx)
    temperature = f.temperature(st, p, prop, ctx)
    T = typeof(temperature)
    dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
    if !isfinite(dH)
        @inbounds Atomix.@atomic status[1] |= STATUS_NONFINITE     # status has 1 entry
        return nothing
    end
    accept(law, T(dH), temperature, uniform(T, ra)) || return nothing
    if has_post(f)                                   # the whole-cell veto after the draw, as `SequentialCPM`
        code = _post(f)(st, p, prop, ctx, SERIAL ? GlobalSearch() : GlobalLocal())
        if !SERIAL && code == GLOBAL_WINDOW
            if sl.exact                              # a veto without window: the serial pass decides
                _push_serial!(sl, blk, lid)
                return nothing
            end
            code = _post(f)(st, p, prop, ctx, GlobalSearch())
        end
        if code != GLOBAL_PASS
            code == GLOBAL_WINDOW && Atomix.@atomic sl.deferred[1] += UInt32(1)
            return nothing
        end
    end
    # t ≤ nsites: the track has one writer per site at a time
    tk === nothing || (@inbounds tk.acc[t] += tk.track(st, p, prop, ctx, dH0))
    @inbounds st.ownership[t] = b
    f.commit!(st, p, prop, ctx)
    _count!(cnt, blk)
    return nothing
end

# one work item's stay (the block at `bc`) in phase number q (offset `off`): its attempts one
# after another; with one switch a stay makes exactly n attempts (no draw)
@inline function block_stay!(bc, st, f, p, ctx, law, key, mcs, layout, off, s, q, tk, cnt, status, sl, serial::Val)
    blk = block_index(layout, bc)
    lo, side = block_region(layout, bc, off)
    n = prod(side)
    m = s == 1 ? n : _stay_attempts(n, s, first(draw(key, mcs, blk, STREAM_BLOCK, _block_lid(q, 0))))
    for k in 1:m
        block_attempt!(blk, st, f, p, ctx, law, key, mcs, lo, side, _block_lid(q, k), tk, cnt, status, sl, serial)
    end
    return nothing
end

# one work item per block over the N-d grid of blocks (no index division per work item)
@kernel function block_kernel!(st, f, p, ctx, law, key, mcs, layout, off, s, q, tk, cnt, status, sl)
    I = @index(Global, NTuple)
    block_stay!(map(i -> i - 1, I), st, f, p, ctx, law, key, mcs, layout, off, s, q, tk, cnt, status, sl, Val(false))
end

# the phase's listed copies in list order, then the list is emptied (one work item, or the host)
function serial_pass!(st, f, p, ctx, law, key, mcs, layout, off, tk, cnt, status, sl)
    for i in 1:Int(@inbounds sl.count[1])
        blk = Int(@inbounds sl.blk[i])
        lo, side = block_region(layout, block_coords(layout, blk), off)
        block_attempt!(blk, st, f, p, ctx, law, key, mcs, lo, side, @inbounds(sl.lid[i]), tk, cnt, status, sl, Val(true))
    end
    @inbounds sl.count[1] = UInt32(0)
    return nothing
end

@kernel function serial_kernel!(st, f, p, ctx, law, key, mcs, layout, off, tk, cnt, status, sl)
    _ = @index(Global, Linear)
    serial_pass!(st, f, p, ctx, law, key, mcs, layout, off, tk, cnt, status, sl)
end

# moments re-center once per MCS (the commits only accumulate, `lockless`); c ≤ capacity
@kernel function recenter_kernel!(cell, lat)
    c = @index(Global, Linear)
    _recenter!(cell, lat, c, @inbounds cell.volume[c])
end

struct CheckerboardCache{N, B, TK, CN, SL, CK, K1, K2, K3, GS}
    layout::BlockLayout{N}
    switches::Int                     # a stay makes n / switches attempts (n sites)
    order::Vector{Int}                # the MCS's phase offsets (1:k^N), P of them
    status::B
    track::TK                         # `nothing`, or `(; track, acc)` (acc per site)
    cnt::CN                           # committed copies per block (Int32), folded at the read points
    serial::SL                        # `nothing`, or the serial list (see `_push_serial!`)
    reach::Int                        # the lattice distance a copy reads and writes around its target
    claim::CK                         # `nothing`, or the per-cell claim stamps of `_phase_conflict!` (CPU)
    kernel::K1
    serial!::K2
    recenter!::K3
    groupsize::GS                     # the phase launch's workgroup size (`nothing`: the backend's choice)
    inline::Bool                      # CPU: the work items of a phase run one after another
    host::Bool                        # the CPU backend
end

# Whether a phase is a proper colouring: whether two of its work items touch one cell. The block
# spacing keeps two active sites (k - 1)·region + 1 apart, which does not keep them out of one cell
# when the cell is wider than that, and a cell is not a lattice distance the spacing could cover.
# In such a phase one work item's decision can be invalidated by another's commit, so the sum of the
# accepted ΔH stops being the energy change of the trajectory (`stats.accepted_energy_change`); the phase runs
# inline instead, one work item after another in block order, which is exact and independent of any
# scheduling. Every other phase is a colouring: its items share no cell and only their own sites,
# so whether they run inline or threaded they reach the same decisions. A cell column is read for
# the cells a copy's target and source belong to (`kind` of a neighbour is read at the neighbour's
# cell, and no kind changes inside a sweep), so sharing a cell is the only way two items of one
# phase can invalidate each other.
#
# The claim covers every cell a work item can touch, not only its target's: a proposal's source
# lies within `radius(proposal)` of the target, and the commit hooks write the target's neighbours'
# cells (`commit_surface!` maintains their surface, `commit_contact_count!` every third cell next
# to the target). The claim radius is the layout's own `need`, the lattice distance the spacing
# guarantees: it is `reach(footprint, proposal)` widened by the contact relation and by every
# relation a copy-step function reads, so it holds whatever a commit hook writes. One 8-byte stamp
# per cell holds the phase's token and the block that first claimed it, so a scan costs one read
# and one write per (site, offset) and allocates nothing.
_claim_columns(::KernelAbstractions.CPU, cell) = (; stamp = zeros(UInt64, length(cell.volume)), token = Ref(UInt32(0)))
_claim_columns(backend, cell) = nothing

_phase_conflict!(st, cache::CheckerboardCache, lat, layout, off) =
    _phase_conflict!(st, cache.claim, cache.reach, lat, layout, off)
_phase_conflict!(st, ::Nothing, reach, lat, layout, off) = false    # a device: no colouring guarantee
function _phase_conflict!(st, claim::NamedTuple, reach::Int, lat::Lattice{N}, layout::BlockLayout{N}, off) where {N}
    tok = UInt64(claim.token[])
    if tok == UInt64(typemax(UInt32))                # 4 billion phases: the stamps restart with the token
        fill!(claim.stamp, UInt64(0))
        tok = UInt64(0)
    end
    tok += 1
    claim.token[] = UInt32(tok)
    hi = tok << 32
    stamp, σ = claim.stamp, st.ownership
    box = CartesianIndices(ntuple(_ -> -reach:reach, Val(N)))
    for I in CartesianIndices(layout.nblocks)
        bc = map(i -> i - 1, Tuple(I))
        blk = UInt64(block_index(layout, bc))
        lo, side = block_region(layout, bc, off)
        for idx in CartesianIndices(side)
            x = ntuple(d -> lo[d] + idx[d], Val(N))                 # `lo` is 0-based, `idx` 1-based
            for δ in box
                inside, z = shift(lat, x, ntuple(d -> Int32(δ[d]), Val(N)))   # wraps, or the medium
                inside || continue
                c = @inbounds σ[linear_index(lat, z)]
                c == 0 && continue                                 # the medium holds no cell columns
                v = @inbounds stamp[c]
                if v >>> 32 == tok
                    (v & 0xffffffff) == blk || return true          # a second work item, one cell
                else
                    @inbounds stamp[c] = hi | blk
                end
            end
        end
    end
    return false
end

# The default `inline_max_blocks` of `CheckerboardCPM`: a CPU phase of at most this many work
# items runs inline. Measured on the PC
# (`benchmark/kinetics/cpu_threads.jl`, 2026-11-05): threads gain under 1.3× at 324 blocks and
# 1.5–2× from 1000 blocks; 4 threads reach 3.3–3.7× at 5000 blocks and above. That 3.3–3.7× is a
# 5000-block measurement: at 2500 blocks over 1600 cells of 10 × 10 the four-thread gain is about
# 1.4× (2.76 ms to 1.96 ms per MCS, best of two runs), and that is the gain a wide-cell geometry
# loses to `_phase_conflict!` (see the docstring's threading note). Each phase ends at a barrier,
# so a thread per busy core stalls on any other process: leave the OS a spare CPU.
const _INLINE_MAX_BLOCKS = 512
# true while the trajectories of a parallel ensemble run (set by the ensemble `solve`; the
# trajectory tasks inherit it): threaded phases would wait at each barrier on threads that
# other trajectories hold
const IN_THREADED_ENSEMBLE = ScopedValue(false)
# fewer work items per phase than this leave a GPU mostly idle (a warning, not a refusal)
const DEVICE_MIN_BLOCKS = 256
# `threads`: `:auto` (inline with one thread, at most `max_blocks` work items, or inside a threaded
# ensemble, whose trajectories already hold the threads), `false` (always inline:
# reproducible), `true` (always the threaded launch)
_block_inline(backend, n, threads, max_blocks) = false
_block_inline(::KernelAbstractions.CPU, n, threads, max_blocks) =
    threads === :auto ? (Threads.nthreads() == 1 || n <= max_blocks || IN_THREADED_ENSEMBLE[]) : !threads
# CPU: one workgroup per thread, the grid of blocks split along its last axis
_block_groupsize(backend, nb) = nothing
_block_groupsize(::KernelAbstractions.CPU, nb::NTuple{N, Int}) where {N} =
    ntuple(d -> d < N ? nb[d] : cld(nb[N], Threads.nthreads()), Val(N))

"""
The default `parts` of a `d`-dimensional lattice: about 64 phases per MCS (8 in 2D, 4 in 3D),
the density that matched `SequentialCPM` kinetics in 2D and 3D.
"""
default_parts(N::Int) = max(2, round(Int, 64^(1 / N)))

function CheckerboardCache(backend, lat::Lattice{N}, f::CPMFunction, proposal; region = nothing, parts = nothing,
        switches = 1, threads = :auto, inline_max_blocks = _INLINE_MAX_BLOCKS, min_read = 0, cell
    ) where {N}
    r, w = reach(f.footprint, proposal)
    r = max(r, min_read, _window(f.connectivity))
    need = max(r + w, 1)
    k = parts === nothing ? default_parts(N) : parts
    k >= 2 || throw(ArgumentError("CheckerboardCPM(; parts = $k): use at least 2"))
    b = region === nothing ? cld(need, k - 1) : region
    b >= 1 && (k - 1) * b >= need || throw(ArgumentError(
        "CheckerboardCPM(; region = $b, parts = $k): the model's copy footprint needs (parts - 1) × region ≥ $need"))
    layout = BlockLayout(lat.dims, b, k)
    nbox = boxsize(layout)
    switches >= 1 || throw(ArgumentError("CheckerboardCPM(; switches = $switches): use at least 1"))
    threads in (:auto, true, false) || throw(ArgumentError("CheckerboardCPM(; threads = $(repr(threads))): use :auto, true or false"))
    inline_max_blocks >= 0 || throw(ArgumentError("CheckerboardCPM(; inline_max_blocks = $inline_max_blocks): use at least 0"))
    P = k^N * switches
    (nbox < 2^16 && P < 2^16) || throw(ArgumentError(
        "CheckerboardCPM(; region = $b, parts = $k, switches = $switches): at most 2^16 - 1 sites per sub-region and phases per MCS"))
    z(T, n) = KernelAbstractions.zeros(backend, T, n)
    tk = f.track === nothing ? nothing : (; f.track, acc = z(track_eltype(f.track), nsites(lat)))
    cnt = z(Int32, nblocks(layout))
    sl = f.connectivity === nothing ? nothing :
         (; blk = z(Int32, nblocks(layout) * cld(nbox, switches)), lid = z(UInt32, nblocks(layout) * cld(nbox, switches)),
        count = z(UInt32, 1), deferred = z(UInt32, 1), exact = f.connectivity.exact_veto)
    n = nblocks(layout)
    backend isa KernelAbstractions.CPU || n >= DEVICE_MIN_BLOCKS ||
        @warn "CheckerboardCPM on a device: $n work items per phase (blocks $(layout.nblocks)) leave the GPU mostly idle; a lattice this small runs as fast or faster on the CPU" maxlog = 1
    claims = _claim_columns(backend, cell)
    c = CheckerboardCache(layout, switches, zeros(Int, P), z(UInt32, 1), tk, cnt, sl, need, claims, block_kernel!(backend),
        serial_kernel!(backend), recenter_kernel!(backend), _block_groupsize(backend, layout.nblocks), _block_inline(backend, n, threads, inline_max_blocks),
        backend isa KernelAbstractions.CPU)
    # fifteen positional fields are easy to permute (two defects of that shape on this branch): read
    # back the ones a swap would corrupt, once per `init`
    @assert c.layout === layout && c.switches == switches && c.reach == need && c.serial === sl &&
        c.inline == _block_inline(backend, n, threads, inline_max_blocks)
    return c
end

# the window of the model's windowed `Global` searches (0: none)
_window(::Nothing) = 0
_window(h::ConnectivityHooks) = h.window

# whether the serial pass runs after each phase (a type-level choice: a model with copies to defer)
_serial_pass(::Nothing, f) = false
_serial_pass(sl, f) = has_defer(f) || (has_post(f) && sl.exact)

# `part = (j, n)`: pass `j` of `n` of a sub-MCS `Repeat`, the phases `(j-1)·P÷n+1 : j·P÷n` of the
# MCS's `P` (the whole MCS is `(1, 1)`); each pass ends with the moments re-centered
function checkerboard_mcs!(st, cache::CheckerboardCache{N}, f::F, p, ctx, law::L, key::RNGKey,
        mcs::Integer, part::NTuple{2, Int} = (1, 1)) where {N, F, L}
    order = cache.order
    for q in eachindex(order)
        r, _, _, _ = draw(key, mcs, q, STREAM_COLOR_ORDER, 2)
        order[q] = bounded(r, cache.layout.k^N) + 1
    end
    l, s, sl = cache.layout, cache.switches, cache.serial
    serial = _serial_pass(sl, f)
    launches = 0
    j, np = part
    P = length(order)
    for q in ((j - 1) * P ÷ np + 1):(j * P ÷ np)
        ph = @inbounds order[q]                      # q ∈ 1:P (the range above)
        off = phase_offset(l, ph)
        launches += 1                                # an inline phase counts as one, like a one-workgroup launch
        if cache.inline || _phase_conflict!(st, cache, ctx.lattice, l, off)
            # one work item after another, so each decision sees what the item before it left: exact
            # (the ΔH sum reconciles with the trajectory) and independent of the thread count
            for I in CartesianIndices(l.nblocks)
                block_stay!(Tuple(I) .- 1, st, f, p, ctx, law, key, mcs, l, off, s, q, cache.track, cache.cnt, cache.status,
                    sl, Val(true))
            end
            continue
        end
        cache.kernel(st, f, p, ctx, law, key, mcs, l, off, s, q, cache.track, cache.cnt, cache.status, sl;
            ndrange = l.nblocks, workgroupsize = cache.groupsize)
        serial || continue
        if cache.host
            serial_pass!(st, f, p, ctx, law, key, mcs, l, off, cache.track, cache.cnt, cache.status, sl)
        else
            cache.serial!(st, f, p, ctx, law, key, mcs, l, off, cache.track, cache.cnt, cache.status, sl; ndrange = 1,
                workgroupsize = 1)
            launches += 1
        end
    end
    if hasproperty(st.cell, :anchor)                 # the moments re-center
        ncell = length(st.cell.volume)
        if cache.host
            for c in 1:ncell
                _recenter!(st.cell, ctx.lattice, c, st.cell.volume[c])
            end
        else
            cache.recenter!(st.cell, ctx.lattice; ndrange = ncell)
            launches += 1
        end
    end
    return launches
end

_fold_track!(stats, cache::CheckerboardCache) = _fold_track!(stats, cache.track)
# Read point of the copy counts: the per-block counters are summed into `stats.accepted` and
# `committed` (equal: a lockless copy commits when it is accepted) and zeroed.
function _fold_counts!(stats, cache::CheckerboardCache)
    a = cache.cnt
    h = _ondevice(a) ? to_host(stats, a) : a
    n = sum(Int, h)
    fill!(a, Int32(0))
    stats.accepted = max(stats.accepted, 0) + n
    stats.committed = max(stats.committed, 0) + n
    return nothing
end

# Read point of the deferred-refusal counter: added into `stats.connectivity_deferred` and
# zeroed (one counted copy on a device).
_fold_deferred!(integ) = _fold_deferred!(_stats(integ), integ.cache)
_fold_deferred!(stats, cache) = nothing
_fold_deferred!(stats, cache::CheckerboardCache) = _fold_deferred!(stats, cache.serial)
_fold_deferred!(stats, ::Nothing) = nothing
function _fold_deferred!(stats, sl::NamedTuple)
    d = sl.deferred
    h = _ondevice(d) ? to_host(stats, d) : d
    stats.connectivity_deferred === nothing || (stats.connectivity_deferred += Int(h[1]))
    fill!(d, UInt32(0))
    return nothing
end
