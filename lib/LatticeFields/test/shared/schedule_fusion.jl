# Definitions of schedule/fusion_tests.jl that other test files use.
using LatticeFields.Schedule: traffic, modeled_time, working_set, merge_kernels, step_order,
                              fusion_report, CostModel

"""
K masked-Helmholtz smoother components sharing one byte mask (6 streams each: u stencil,
u_prev, b, uⁿ, mask, out), the launch-bound and DRAM test family of the field-kernel benchmarks.
"""
function smoother(dims, K)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 3)
    m = mask!(pb, "kind")
    offs = [ntuple(e -> e == d ? s : 0, N) for d in 1:N for s in (-1, 1)]
    for k in 1:K
        u, up, b, un = (field!(pb, "$(x)$k"; role = :input) for x in ("u", "uprev", "b", "un"))
        out = field!(pb, "out$k"; role = :output)
        kb = kernel(pb)
        c = load(kb, u)
        Au = 2N * c - sum(load(kb, u; offset = o) for o in offs)
        r = load(kb, b) - param(kb, 1) * Au - param(kb, 2) * load(kb, up)
        live = select(eq(load(kb, m), IR.constant(kb, 0, U8)), c, load(kb, un) +
                                                                  param(kb, 3) * r)
        store(kb, out, live)
        add!(pb, kb, "smooth$k")
    end
    return semantic(program(pb))
end

"""
K residuals `r = b − A u` on the mask (4 streams each, mask shared).
"""
function residual(dims, K)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1)
    m = mask!(pb, "kind")
    offs = [ntuple(e -> e == d ? s : 0, N) for d in 1:N for s in (-1, 1)]
    for k in 1:K
        u, b = field!(pb, "u$k"; role = :input), field!(pb, "b$k"; role = :input)
        r = field!(pb, "r$k"; role = :output)
        kb = kernel(pb)
        c = load(kb, u)
        res = load(kb, b) -
              param(kb, 1) * (2N * c - sum(load(kb, u; offset = o) for o in offs))
        store(kb, r, select(eq(load(kb, m), IR.constant(kb, 0, U8)), IR.constant(kb, 0), res))
        add!(pb, kb, "residual$k")
    end
    return semantic(program(pb))
end

"""
K independent 2:1 restrictions (coarse space reads 2^N fine children; nothing shared).
"""
function restrict(dims, K)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), levels = 2)
    for k in 1:K
        r = field!(pb, "r$k"; role = :input)
        rc = field!(pb, "rc$k"; role = :output, levels = [1])
        kb = kernel(pb, Space{N}(; level = 1))
        kids = [load(kb, r; level = -1, offset = Tuple(o) .- 1)
                for o in CartesianIndices(ntuple(_ -> 2, N))]
        store(kb, rc, sum(kids) * (1 / 2^N))
        add!(pb, kb, "restrict$k")
    end
    return semantic(program(pb))
end

"""
K prolong-and-correct kernels: fine `u + e(coarse)` on the mask (mask shared).
"""
function prolong(dims, K)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), levels = 2)
    m = mask!(pb, "kind")
    for k in 1:K
        u = field!(pb, "u$k"; role = :input)
        e = field!(pb, "e$k"; role = :input, levels = [1])
        out = field!(pb, "out$k"; role = :output)
        kb = kernel(pb)
        c = load(kb, u)
        store(kb, out, select(eq(load(kb, m), IR.constant(kb, 0, U8)), c, c +
                                                                          load(kb, e; level = 1)))
        add!(pb, kb, "prolong$k")
    end
    return semantic(program(pb))
end

"""
K independent fields, `v = a·u + p` (2 streams each, generator-like, T = 0).
"""
function independent(dims, K)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, length(dims)), nparams = 2)
    for k in 1:K
        u, v = field!(pb, "u$k"; role = :input), field!(pb, "v$k"; role = :output)
        kb = kernel(pb)
        store(kb, v, param(kb, 1) * load(kb, u) + param(kb, 2))
        add!(pb, kb, "axpy$k")
    end
    return semantic(program(pb))
end

nlaunch(s) = length(plan(s).launches)

"""
Direct comparison of fusing all kernels against running them all split.
"""
function all_vs_split(s, cost = CostModel())
    ids = collect(eachindex(s.kernels))
    N = length(s.periodic)
    scc = Dict(i => i for i in ids)
    ws = working_set(s, [traffic(s, k) for k in s.kernels])
    tf = modeled_time(cost, N, traffic(s, merge_kernels(s, ids, scc)), ws)
    ts = sum(modeled_time(cost, N, traffic(s, k), ws) for k in s.kernels)
    return tf, ts
end

# Negative-control rules the cost model replaces.
function shares_read(s)
    (rs = [Set((a.field, a.level) for a in k.accesses) for k in s.kernels];
        !isempty(intersect(rs...)))
end
function stream_cap_ok(s, cap)
    length(traffic(s,
        merge_kernels(s, collect(eachindex(s.kernels)),
            Dict(i => i for i in eachindex(s.kernels)))).arrays) <= cap
end

"""
Producer `w ← 2u + p` and consumer `v ← w(off) · u`.
"""
function producer_consumer(off; dims = (42, 42, 42))
    pb = ProgramBuilder(Grid(dims); periodic = (true, true, true), nparams = 1)
    u = field!(pb, "u"; role = :input)
    w = field!(pb, "w"; role = :aux)
    v = field!(pb, "v"; role = :output)
    kb = kernel(pb)
    store(kb, v, load(kb, w; offset = off) * load(kb, u))
    add!(pb, kb, "a_consume")                          # declared first, key sorts first
    kb = kernel(pb)
    store(kb, w, 2 * load(kb, u) + param(kb, 1))
    add!(pb, kb, "z_produce")
    return semantic(program(pb))
end
