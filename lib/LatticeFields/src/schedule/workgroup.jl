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
    _workgroups!(backend, wg)(body, S, P, G, Int32(phases), T, Val(max(Int(ldslen), 1));
        ndrange = ngroups * wg)
    return nothing
end
