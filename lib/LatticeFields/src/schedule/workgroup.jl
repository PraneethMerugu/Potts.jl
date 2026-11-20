# Workgroup launches (contract item 5): `ngroups` workgroups of `wg` items run `phases`
# barrier-separated phases, `body(ph, g, t, lds, S, P, G)` with `ph`, `g`, `t` Int32 and
# 1-based, and `lds` workgroup memory of `ldslen` elements. Every item runs every phase (the
# barrier stays uniform); a body never returns early around a barrier, only inside a phase.
# A phase may read what any item of its workgroup wrote in an earlier phase, and only that.
# The host form below is the reference; `workgroups!` is the device wrapper.

"""
Items of every workgroup launch.
"""
const WG = 256
"""
Phases of a reducing kernel: the sites (1), then the halving tree (strides 128 … 1).
"""
const REDUCE_PHASES = 9

"""
Workgroup memory (elements) of compiled kernel `ck` with reductions: 256 per reduction.
"""
reduce_lds(ck::CompiledKernel) = WG * length(ck.kernel.reductions)

"""
    host_workgroups!(body, ngroups, wg, phases, lds, S, P, G; reverse = false)

The host form: workgroups in order, phases in order, items in order (`reverse = true` runs
the items of each phase backwards: a body that is free of intra-phase races gives the
same bits either way). `lds` is a host array of at least the launch's `ldslen` elements.
"""
function host_workgroups!(body::F, ngroups, wg, phases, lds, S, P, G;
        reverse::Bool = false) where {F}
    for g in Int32(1):Int32(ngroups), ph in Int32(1):Int32(phases)

        if reverse
            for t in Int32(wg):Int32(-1):Int32(1)
                body(ph, g, t, lds, S, P, G)
            end
        else
            for t in Int32(1):Int32(wg)
                body(ph, g, t, lds, S, P, G)
            end
        end
    end
    return nothing
end

"""
    host_reduce!(body, ngroups, wg, lds, ldslen, S, P, G; chunks = 1)

The host fast path of a reducing kernel's workgroup form (`REDUCE_PHASES` phases: the site
phase, then the halving tree, contract item 5), bitwise equal to `host_workgroups!`: per
block, phase 1 for every item, then in phase `ph` only the items `t ≤ wg >> (ph − 1)` (the
others are idle in the tree: they read and write nothing), in the same order. Blocks are
independent, so `chunks > 1` runs contiguous ranges of blocks on Polyester's persistent
workers (`@batch`: no task is created, a warm launch allocates nothing), chunk `c` in region
`c` of `lds` (`chunks · ldslen` elements). Every block computes the same values in the same
order whatever the chunk, so the result does not depend on `chunks` or the thread count.
"""
function host_reduce!(body::F, ngroups, wg, lds, ldslen, S, P, G; chunks::Integer = 1) where {F}
    if chunks <= 1
        _reduce_blocks!(body, 1, Int(ngroups), wg, lds, S, P, G)
    else
        _host_reduce_threaded!(body, Int(ngroups), Int(chunks), wg, lds, Int(ldslen), S, P, G)
    end
    return nothing
end

@noinline function _host_reduce_threaded!(body::F, ngroups, nc, wg, lds, ldslen, S, P, G) where {F}
    per = cld(ngroups, nc)
    @batch per = thread for c in 1:nc
        _reduce_chunk!(body, c, per, ngroups, wg, lds, ldslen, S, P, G)
    end
    return nothing
end
function _reduce_chunk!(body::F, c, per, ngroups, wg, lds, ldslen, S, P, G) where {F}
    r = view(lds, ((c - 1) * ldslen + 1):(c * ldslen))
    _reduce_blocks!(body, (c - 1) * per + 1, min(c * per, ngroups), wg, r, S, P, G)
    return nothing
end
function _reduce_blocks!(body::F, g0, g1, wg, lds, S, P, G) where {F}
    for g in Int32(g0):Int32(g1)
        for t in Int32(1):Int32(wg)
            body(Int32(1), g, t, lds, S, P, G)
        end
        stride = Int32(wg)
        for ph in Int32(2):Int32(REDUCE_PHASES)
            stride >>= one(Int32)
            for t in Int32(1):stride
                body(ph, g, t, lds, S, P, G)
            end
        end
    end
    return nothing
end

# The device wrapper: one workgroup per `g`, `@synchronize` after every phase.
@kernel unsafe_indices = true function _workgroups!(
        body, S, P, G, phases, ::Type{T}, ::Val{M}) where {T, M}
    g = @index(Group, Linear)
    t = @index(Local, Linear)
    lds = @localmem T (M,)
    for ph in 1:phases
        body(Int32(ph), Int32(g), Int32(t), lds, S, P, G)
        @synchronize
    end
end

"""
    workgroups!(backend, body, ngroups, wg, phases, T, ldslen, S, P, G)

Enqueue a workgroup launch on a KernelAbstractions `backend` (no wait): `ngroups` groups of
`wg` items, `ldslen` elements of `T` of workgroup memory.
"""
function workgroups!(backend, body::F, ngroups, wg, phases, ::Type{T}, ldslen, S, P,
        G) where {F, T}
    # compile mode (`Exec.compiling`): one group with no phase compiles the kernel
    c = Exec.compiling()
    _workgroups!(backend, wg)(body, S, P, G, Int32(c ? 0 : phases), T, Val(max(Int(ldslen), 1));
        ndrange = (c ? 1 : ngroups) * wg)
    return nothing
end
