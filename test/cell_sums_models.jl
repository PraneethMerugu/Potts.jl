# The models of test/cell_sums.jl, also loaded by its `-t 4` / `-t 8` processes and by
# the device tests (test/gpu.jl).
isdefined(@__MODULE__, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
module CsPDE
    using ..FieldPDE
    @variables c(..) src(..)::Bool [input = true]
    const C = c(t, x, y)
    threshold() = pdesys([Dt(C) ~ 0.2 * laplacian(C) + 0.05 * src(t, x, y) - 0.02 * C], [c(0, x, y) ~ 0.0], (200, 200), [C, src(t, x, y)])
end

# Merks-like: cells secrete `c`, chemotaxis up its gradient, and the target volume moves when
# the cell's average of `c` passes θ
@potts_model CsThreshold begin
    @kinds medium A
    @parameters begin
        θ = 1.2
        χ = 2.0
    end
    @variables cavg(cell) = 0.0
    @lattice Lattice((200, 200); boundary = Periodic())
    @energy cells => (volume - 25.0 - 15.0 * (cavg > θ))^2
    @fields c = CsPDE.threshold() (CsPDE.src => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @after_mcs cavg ~ integral(c) / volume
    @sweep Metropolis(; temperature = 4.0)
end
# 20 × 20 cells of 5 × 5 sites, 5 sites apart; a rough initial field
function cs_threshold_op(dims = (200, 200))
    σ = zeros(Int32, dims)
    k = 0
    for j in 1:10:(dims[2] - 4), i in 1:10:(dims[1] - 4)
        k += 1
        σ[i:(i + 4), j:(j + 4)] .= k
    end
    c0 = [1.0 + sin(0.37i) * cos(0.23j) + 0.5 * sin(1.7i + 2.3j) for i in 1:dims[1], j in 1:dims[2]]
    return [ownership => σ, kind => fill(:A, k), :c => c0]
end
cs_digest(x) = string(hash(Array(x)); base = 16)

# [ocell, σ, cavg] of the Jiang-like model (2 MCS, CPU, Float64) and the Merks-like model
# (8 MCS); `ctl = true` restores the float atomics (negative control). `run = 1` makes the host
# site passes one site per item, so at these lattice sizes they are threaded (the default run
# of 256 sites leaves fewer items than `HOST_GRAIN`, a plain loop)
function cs_digests1(ctl::Bool; run = CorePotts._CR_RUN_HOST[])
    CorePotts._FLOAT_ATOMICS[] = ctl
    r0 = CorePotts._CR_RUN_HOST[]
    CorePotts._CR_RUN_HOST[] = run
    try
        σ, kinds = jiang_state(JG_DIMS)
        j = init(
            PottsProblem(
                JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 2); seed = 7,
                field_solver = BackwardEuler()
            ), SequentialCPM()
        )
        foreach(_ -> step!(j), 1:2)
        m = solve(
            PottsProblem(CsThreshold(; name = :m), cs_threshold_op(), (0, 8); seed = 7), SequentialCPM();
            save_start = false
        ).u[end]
        return [cs_digest(current_state(j).cell.ocell), cs_digest(m.ownership), cs_digest(m.cell.cavg)]
    finally
        CorePotts._FLOAT_ATOMICS[] = false
        CorePotts._CR_RUN_HOST[] = r0
    end
end
# fixed point (default runs), fixed point (runs of 1: threaded), float atomics
cs_digests() = vcat(cs_digests1(false), cs_digests1(false; run = 1), cs_digests1(true))

# A site average over frozen cells (no copy, no field solve): the host and a device read the
# same site values, so their cell averages must agree bitwise
@potts_model CsSiteAvg begin
    @kinds medium A[frozen]
    @variables begin
        h(site) = 0.0
        havg(cell) = 0.0
    end
    @lattice Lattice((200, 200); boundary = Periodic())
    @energy cells => (volume - 25.0)^2
    @after_mcs havg ~ integral(h) / volume
    @sweep Metropolis(; temperature = 4.0)
end
# values whose float sums depend on the order: magnitudes over 8 decades, both signs
function cs_site_values(dims = (200, 200))
    return Float32[(0.5 + sin(1.3i + 0.7j)) * 10.0f0^((3i + 5j) % 9 - 4) for i in 1:dims[1], j in 1:dims[2]]
end
cs_site_op() = (op = cs_threshold_op(); [op[1], op[2], :h => cs_site_values()])

# The other sums over sites. Weighted surfaces after divisions (the device
# lifecycle's recomputes), cluster surfaces of a weighted relation, and the compound
# writes of a `@convert` pass.
const CS_W = Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
@potts_model CsWSurf begin
    @kinds medium A
    @lattice Lattice((120, 120); boundary = Periodic(), neighborhood = CS_W)
    @relations contact = CS_W
    @energy begin
        cells => (volume - 40.0)^2 + 0.2 * (surface - 70.0)^2
        contacts => 3.0 * weight * (kind != neighbor_kind)
    end
    @divide cells(A) when = volume >= 34
    @sweep Metropolis(; temperature = 6.0)
end
function cs_wsurf_op(dims = (120, 120))
    σ = zeros(Int32, dims)
    k = 0
    for j in 1:12:(dims[2] - 5), i in 1:12:(dims[1] - 5)
        k += 1
        σ[i:(i + 4), j:(j + 4)] .= k
    end
    return [ownership => σ, kind => fill(:A, k)]
end

# compartments over a weighted neighborhood: a cluster surface energy, clusters that grow and divide
@potts_model CsWComp begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        V₀[kind] = [0.0, 60.0, 20.0]
    end
    @lattice Lattice((60, 60); boundary = Periodic(), neighborhood = CS_W)
    @energy begin
        cells => (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 2.0, J[kind, neighbor_kind])
        clusters(cytoplasm) => 0.1 * (cluster_surface - 30.0)^2
    end
    @divide clusters(cytoplasm) when = cluster_volume >= 60, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 10.0)
end
function cs_wcomp_op()
    σ = zeros(Int32, 60, 60)
    n = 0
    for i in 2:15:47, j in 2:15:47
        n += 1
        σ[i:(i + 7), j:(j + 7)] .= n
    end
    for c in 1:n
        lo = minimum(findall(==(c), σ))
        σ[(lo[1] + 2):(lo[1] + 5), (lo[2] + 2):(lo[2] + 5)] .= n + c
    end
    return [ownership => σ, kind => vcat(fill(:cytoplasm, n), fill(:nucleus, n)), cluster => vcat(1:n, 1:n)]
end

# `@convert` compound writes with non-dyadic values over 6 decades, into a model and a cell
# variable that the energy reads
@potts_model CsConv begin
    @kinds medium cytoplasm lamellipodium
    @parameters J[kind, kind] = [0 16 16; 16 2 0; 16 0 2]
    @variables begin
        sub(site) = 0.0
        V_target(cell) = ifelse(kind == cytoplasm, 400.0, 0.0)
        tot(model) = 0.0
    end
    @lattice Lattice((64, 64); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cytoplasm, lamellipodium) => (volume - V_target)^2
        contacts => J[kind, neighbor_kind]
    end
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.0
        p = ifelse(mcs == 3, 1.0, 0.0)
        V_target[to] += 0.37 * sub
        tot += sub
    end
    @sweep Metropolis(; temperature = 2.0)
end
function cs_conv_op()
    σ = zeros(Int32, 64, 64)
    σ[13:52, 13:52] .= 1
    sub = zeros(64, 64)
    for j in 20:45, i in 20:45                      # 676 sites
        sub[i, j] = (1.0 + sin(1.3i + 0.7j)) * 10.0^(((3i + 5j) % 7) - 3)
    end
    return [ownership => σ, kind => [:cytoplasm], cluster => [1], :sub => sub]
end

cs_bits(x) = string(hash(reinterpret(UInt32, Float32.(vec(Array(x))))); base = 16)
# [w σ, w surface, comp σ, comp cluster surface, conv σ, conv tot, conv V_target]
# in Float32 with CheckerboardCPM on `backend` (on the CPU with the device lifecycle, as a
# device runs it; the weighted surface model staged, the compartments fused); `ctl = true` restores the float atomics (negative control). Also returns
# the division counts (checked > 0).
# `host = true`: on the CPU, the host lifecycle planner instead (the same unit
# arithmetic, so the same bits)
function cs_site_sum_digests(backend = CorePotts.CPU(); ctl::Bool = false, mcs = 80, host::Bool = false)
    CorePotts._FLOAT_ATOMICS[] = ctl
    f0 = CorePotts._FORCE_DEVICE_LIFECYCLE[]
    CorePotts._FORCE_DEVICE_LIFECYCLE[] = !host
    try
        # Pin `threads = false` so the 1-thread vs 4-thread comparison stays deterministic
        # regardless of `inline_max_blocks`.
        function run(m, op, t; kw...)
            return solve(
                PottsProblem(m, op, (0, t); T = Float32, seed = 7, capacity = 2000),
                CheckerboardCPM(; threads = false, kw...); backend, save_start = false
            )
        end
        # the weighted surface in the staged device lifecycle (one kernel per stage), the
        # compartments in the fused one (one workgroup: `fused_lifecycle_max_sites`)
        sw = run(CsWSurf(; name = :w), cs_wsurf_op(), mcs; fused_lifecycle_max_sites = 0)
        sc = run(CsWComp(; name = :c), cs_wcomp_op(), 40)
        sv = run(CsConv(; name = :v), cs_conv_op(), 30)
        w, c, v = sw.u[end], sc.u[end], sv.u[end]
        d = [cs_digest(w.ownership), cs_bits(w.cell.surface), cs_digest(c.ownership), cs_bits(c.cell.cluster_surface), cs_digest(v.ownership), cs_bits(v.model.tot), cs_bits(v.cell.V_target)]
        return d, (sw.stats.lifecycle.divisions, sc.stats.lifecycle.divisions)
    finally
        CorePotts._FLOAT_ATOMICS[] = false
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = f0
    end
end
# [σ, tot, V_target] of the `@convert` model alone (the five-runs test on a device)
function cs_conv_digests(backend = CorePotts.CPU(); ctl::Bool = false)
    CorePotts._FLOAT_ATOMICS[] = ctl
    try
        # Pin `threads = false` so `:auto` does not switch to threaded execution under `-t 4`.
        v = solve(
            PottsProblem(CsConv(; name = :v), cs_conv_op(), (0, 30); T = Float32, seed = 7, capacity = 8),
            CheckerboardCPM(; threads = false); backend, save_start = false
        ).u[end]
        return [cs_digest(v.ownership), cs_bits(v.model.tot), cs_bits(v.cell.V_target)]
    finally
        CorePotts._FLOAT_ATOMICS[] = false
    end
end

@potts_model CsThreadedCBRepeat begin
    @kinds medium A
    @lattice Lattice((1536, 1536))
    @energy cells => (volume - 64.0)^2 + 0.01 * (surface - 32.0)^2
    @energy contacts => 4.0
    @schedule repeat(2, sweep(fraction = 1 // 2))
    @sweep Metropolis(; temperature = 2.0)
end

function cs_threaded_cb_invariants()
    σ = zeros(Int32, 1536, 1536)
    id = 0
    for bj in 0:4:1524, bi in 0:4:1524
        (bi + bj) % 64 == 0 || continue
        id += 1
        σ[(bi + 1):(bi + 4), (bj + 1):(bj + 4)] .= id
    end
    prob = PottsProblem(CsThreadedCBRepeat(; name = :tcb), [ownership => σ, kind => fill(:A, id)], (0, 2); seed = 7)
    alg = CheckerboardCPM(; threads = true)
    integ = init(prob, alg; save_start = false)
    lay = integ.cache.layout
    nblocks_pass = prod(cld.(lay.nblocks, lay.k))
    sol = solve!(integ)
    u = sol.u[end]
    σ_arr = Array(u.ownership)
    vol_recount = [count(==(c), σ_arr) for c in 1:length(u.cell.volume)]
    vol_ok = all(u.cell.volume .== vol_recount)
    surf_recount = CorePotts.recompute_surface(σ_arr, prob.lattice, prob.relations.surface, length(u.cell.volume))
    surf_ok = Array(u.cell.surface) == surf_recount
    attempts_ok = sol.stats.attempts == 2 * length(σ_arr)
    committed_ok = sol.stats.accepted >= sol.stats.committed > 0
    return (id > 0 && nblocks_pass > alg.inline_max_blocks, vol_ok, surf_ok, attempts_ok, committed_ok)
end

@potts_model CsThreadedCBGlobalVeto begin
    @kinds medium A
    @lattice Lattice((1536, 1536))
    @energy cells => (volume - 24.0)^2
    @constraint connectivity(A; rule = Global(; window = 1))
    @schedule repeat(2, sweep(fraction = 1 // 2))
    @sweep Metropolis(; temperature = 12.0)
end

@potts_model CsThreadedCBNoVeto begin
    @kinds medium A
    @lattice Lattice((1536, 1536))
    @energy cells => (volume - 24.0)^2
    @schedule repeat(2, sweep(fraction = 1 // 2))
    @sweep Metropolis(; temperature = 12.0)
end

function cs_threaded_cb_global_veto_check(M; threads::Bool = true)
    σ = zeros(Int32, 1536, 1536)
    id = 0
    for bj in 0:6:1524, bi in 0:6:1524
        (bi + bj) % 64 == 0 || continue
        id += 1
        σ[(bi + 1):(bi + 6), (bj + 1):(bj + 6)] .= id
    end
    prob = PottsProblem(M(; name = :gv), [ownership => σ, kind => fill(:A, id)], (0, 6); seed = 7)
    alg = CheckerboardCPM(; threads)
    integ = init(prob, alg; save_start = false)
    lay = integ.cache.layout
    nblocks_pass = prod(cld.(lay.nblocks, lay.k))
    sol = solve!(integ)
    u = sol.u[end]
    σ_arr = Array(u.ownership)
    vol_recount = [count(==(c), σ_arr) for c in 1:length(u.cell.volume)]
    vol_ok = all(u.cell.volume .== vol_recount)
    pieces, _ = CorePotts.recompute_pieces(σ_arr, prob.lattice, Val(false), length(u.cell.volume))
    live = findall(>(0), Array(u.cell.volume))
    one_piece_ok = !isempty(live) && all(==(1), pieces[live])
    return (;
        nonzero_cells = id > 0, committed = sol.stats.committed, nblocks_pass,
        over_grain = nblocks_pass > alg.inline_max_blocks,
        vol_ok, one_piece_ok, deferred = sol.stats.connectivity_deferred,
        max_pieces = isempty(live) ? 0 : maximum(pieces[live]),
    )
end
