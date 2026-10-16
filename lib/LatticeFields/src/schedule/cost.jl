# The fusion cost model (v3 §4.3; P3-gates x2, x3). Not a shared-reads rule and no stream cap:
#   t = max(bytes / (η(streams, ws) · BW(ws)), flops / F) + launch_dep(arrays)
# Calibration values live in `CostModel` (DECISIONS item; the crossover between 128³ and 256³
# is not measured finely). `ws` is the working set of the whole candidate sequence, the same
# for both arms, so fused and split are compared in one regime.

"""
Measured η tables as `(streams, η)` points (fused, DRAM, P3-gates §2–§3).
"""
const ETA_GENERATOR = Dict(2 => [(2, 0.99), (8, 0.91), (16, 0.85), (32, 0.80), (64, 0.64)],
    3 => [(2, 0.97), (4, 0.87), (8, 0.87), (16, 0.84)])   # monotone envelope (8: 0.92 measured)
const ETA_REALISTIC = Dict(
    2 => [(6, 0.95), (11, 0.94), (16, 0.92), (21, 0.91), (26, 0.90)],
    3 => [(6, 0.94), (11, 0.91), (16, 0.87), (21, 0.83), (26, 0.78)])

Base.@kwdef struct CostModel
    bw_dram::Float64 = 235e9          # 232–237 GB/s
    bw_cache::Float64 = 674e9         # cache-resident ceiling 617–731 GB/s
    cache_ws::Float64 = 32 * 2.0^20   # cache-resident up to 32 MiB
    dram_ws::Float64 = 64 * 2.0^20    # DRAM from 64 MiB
    eta_lo_ws::Float64 = 256 * 2.0^20 # η = 1 below (fused wins at 128³; calibration)
    eta_hi_ws::Float64 = 2.0^30       # η = table above (fused loses at 256³; calibration)
    flops::Float64 = 14.8e12
    launch0::Float64 = 4.5e-6         # KA 0.9, dynamic ndrange: 4.5 µs + 0.23 µs per array
    launch_per_array::Float64 = 0.23e-6
    realistic_reads::Float64 = 0.75   # read fraction from which the realistic table applies
    # Hard limits (blockers, not costs): kernel arguments and the register prefilter. Below
    # 256 MiB η = 1, so without them the model would fuse any number of components.
    max_arrays::Int = 32              # array arguments per kernel (P3-gates measured up to 26)
    arg_bytes_per_array::Int = 48     # device array descriptor (pointer, dims, length)
    max_arg_bytes::Int = 4096         # kernel-argument budget (4 KiB on ROCm and Metal)
    max_live::Int = 96                # live-value estimate; x2/x3 kernels had VGPR ≤ 78
end

"""
Peak number of simultaneously live values in canonical node order (a register prefilter;
PG-17 checks the real VGPR count and scratch = 0 after compile).
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
Why a merged kernel breaks a hard limit (`nothing` if it does not).
"""
function limit_blocker(m::CostModel, k::Kernel, t)
    na = length(t.arrays) + length(k.tables)
    na > m.max_arrays && return "$na array arguments > $(m.max_arrays)"
    na * m.arg_bytes_per_array > m.max_arg_bytes &&
        return "kernel arguments exceed $(m.max_arg_bytes) B"
    l = live_estimate(k)
    l > m.max_live && return "estimated $l live values > $(m.max_live)"
    return nothing
end
ka09_static() = CostModel(; launch0 = 3.0e-6, launch_per_array = 0.22e-6)
ka010() = CostModel(; launch0 = 1.9e-6, launch_per_array = 0.08e-6)

function _interp(tab, x)
    x <= tab[1][1] && return tab[1][2]
    x >= tab[end][1] && return tab[end][2]
    j = findfirst(t -> t[1] >= x, tab)
    (x0, y0), (x1, y1) = tab[j - 1], tab[j]
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
end
_logfrac(x, lo, hi) = clamp(log(x / lo) / log(hi / lo), 0.0, 1.0)

"""
η at `streams` arrays, read fraction `rf`, dimension `N` and working set `ws` (bytes).
"""
function eta(m::CostModel, N, streams, rf, ws)
    tab = (rf >= m.realistic_reads ? ETA_REALISTIC : ETA_GENERATOR)[min(N, 3)]
    w = _logfrac(ws, m.eta_lo_ws, m.eta_hi_ws)
    return 1 - w * (1 - _interp(tab, streams))
end
function bandwidth(m::CostModel, ws)
    exp(log(m.bw_cache) +
        _logfrac(ws, m.cache_ws, m.dram_ws) * log(m.bw_dram / m.bw_cache))
end

"""
Compulsory traffic of a semantic kernel: arrays, bytes per launch, reads, writes, flops.
"""
struct Traffic
    arrays::Set{Tuple{Int32, Int16, Int8, Symbol}}  # (field, comp, abs level, :r | :w)
    bytes::Float64
    nreads::Int
    nwrites::Int
    flops::Float64
end

function traffic(p::Program{N}, k::Kernel{N}) where {N}
    n = nsites(p, k.space.level)
    arr = Set{Tuple{Int32, Int16, Int8, Symbol}}()
    bytes = Ref(0.0)
    function add!(f, comp, rel, rw)
        (f, comp, Int8(k.space.level + rel), rw) in arr && return
        push!(arr, (f, comp, Int8(k.space.level + rel), rw))
        bytes[] += n * lanebytes(p.fields[f].storage) * 2.0^(-N * rel)
    end
    foreach(a -> add!(a.field, a.comp.a, a.level, :r), (k.accesses[x.imm]
    for x in k.nodes if x.op == LOAD))
    k.space.kind == MASKED && add!(p.masks[k.space.mask].field, Int16(1), 0, :r)
    for s in k.stores
        f = p.fields[s.access.field]
        key = (s.access.field, s.access.comp.a, Int8(k.space.level), :r)
        if f.buffers == 1 && key in arr     # read and written in place: one array, both bytes
            delete!(arr, key)
            push!(arr, (key[1], key[2], key[3], :rw))
            bytes[] += n * lanebytes(f.storage)
        else
            add!(s.access.field, s.access.comp.a, 0, :w)
        end
        f.buffers == 2 && k.space.kind != FULL &&
            add!(s.access.field, s.access.comp.a, 0, :r)
    end
    nr, nw = count(x -> x[4] != :w, arr), count(x -> x[4] != :r, arr)
    flops = n *
            count(x -> !(x.op in (LOAD, CONST, PARAM, COORD, RUNTIME, INSIDE_OP)), k.nodes)
    return Traffic(arr, bytes[], nr, nw, flops)
end

"""
Working set (bytes) of the arrays touched by a set of traffics.
"""
function working_set(p::Program{N}, ts) where {N}
    u = Set{Tuple{Int32, Int16, Int8, Bool}}()
    for t in ts, (f, c, l, rw) in t.arrays

        push!(u, (f, c, l, rw == :w && p.fields[f].buffers == 2))
    end
    return sum((nsites(p, l) * lanebytes(p.fields[f].storage) for (f, c, l, _) in u); init = 0.0)
end

"""
Modeled time (seconds) of one launch with traffic `t` in a sequence of working set `ws`.
"""
function modeled_time(m::CostModel, N, t::Traffic, ws)
    s = length(t.arrays)
    rf = t.nreads / max(t.nreads + t.nwrites, 1)
    tb = t.bytes / (eta(m, N, s, rf, ws) * bandwidth(m, ws))
    return max(tb, t.flops / m.flops) + m.launch0 + m.launch_per_array * s
end
