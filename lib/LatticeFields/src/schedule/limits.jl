# Hard resource limits of a fused kernel: kernel arguments and a register prefilter. They
# block a fusion like a legality rule; they are not costs.

"""
Array arguments per kernel.
"""
const MAX_ARRAYS = 32
"""
Bytes of one device array descriptor (pointer, dims, length) in the kernel arguments.
"""
const ARG_BYTES_PER_ARRAY = 48
"""
Kernel-argument budget in bytes (4 KiB on ROCm and Metal).
"""
const MAX_ARG_BYTES = 4096
"""
Live-value estimate above which a kernel is assumed to spill registers.
"""
const MAX_LIVE = 96

"""
Peak number of simultaneously live values in canonical node order (a register prefilter).
"""
function live_estimate(k::Kernel)
    last = collect(1:length(k.nodes))
    for (i, n) in enumerate(k.nodes), a in args(k, n)
        last[a] = max(last[a], i)
    end
    foreach(s -> last[s.value] = length(k.nodes) + 1, k.stores)
    ends = zeros(Int, length(k.nodes) + 2)
    foreach(j -> ends[last[j] + 1] += 1, eachindex(last))
    live, peak = 0, 0
    for i in eachindex(k.nodes)
        live += 1 - ends[i + 1]
        peak = max(peak, live)
    end
    return peak
end

"""
The distinct arrays kernel `k` binds, as `(field, component, absolute level, role)` with
role `:r`, `:w` or `:rw` (a one-buffer field read and written in place is one array).
"""
function kernel_arrays(p::Program, k::Kernel)
    arr = Set{Tuple{Int32, Int16, Int8, Symbol}}()
    add!(f, comp, rel, rw) = push!(arr, (f, comp, Int8(k.space.level + rel), rw))
    foreach(
        a -> add!(a.field, a.comp.a, a.level, :r),
        (k.accesses[x.imm] for x in k.nodes if x.op == LOAD)
    )
    k.space.kind == MASKED && add!(p.masks[k.space.mask].field, Int16(1), 0, :r)
    for s in k.stores
        f = p.fields[s.access.field]
        key = (s.access.field, s.access.comp.a, Int8(k.space.level), :r)
        if f.buffers == 1 && key in arr
            delete!(arr, key)
            push!(arr, (key[1], key[2], key[3], :rw))
        else
            add!(s.access.field, s.access.comp.a, 0, :w)
        end
        f.buffers == 2 && k.space.kind != FULL &&
            add!(s.access.field, s.access.comp.a, 0, :r)
    end
    return arr
end

"""
Why a merged kernel breaks a hard limit (`nothing` if it does not).
"""
function limit_blocker(p::Program, k::Kernel)
    na = length(kernel_arrays(p, k)) + length(k.tables)
    na > MAX_ARRAYS && return "$na array arguments > $MAX_ARRAYS"
    na * ARG_BYTES_PER_ARRAY > MAX_ARG_BYTES &&
        return "kernel arguments exceed $MAX_ARG_BYTES B"
    l = live_estimate(k)
    l > MAX_LIVE && return "estimated $l live values > $MAX_LIVE"
    return nothing
end
