# P6.0v2 (ROADMAP Phase 6, step 0): `_AdaptiveODE` and `HostPhase` move only the columns they
# read and write. Frozen (AUTONOMY §7.3). Decisions: D-085 (counters), D-089; audit
# `docs/design/research/gpu-host-transfer-audit.md` §4 (A1–A4) and §5 (H1–H4).
#
# Accept (ROADMAP): per-MCS bytes of an adaptive-ODE fixture and a `HostPhase` fixture scale
# with the columns used, not with all cell quantities; results unchanged up to floating-point
# tolerance.
#
# What is pinned. Each fixture comes as a pair that differs ONLY by quantities the phase
# does not touch: extra cell columns (Float, Int32 and a matrix column), an extra model
# quantity, an extra site field and extra parameter tables (the extra cell column `z1` is
# live: a device `@after_mcs` rule updates it, so it is not dead state a compiler could
# drop). On Metal (POTTS_GPU=metal with Metal loaded; Float32, CheckerboardCPM):
#  1. Pair invariance. The per-MCS counter triple (syncs, transfers, transfer_bytes) of
#     `step!` is identical between the two members, MCS by MCS. The fixtures have no
#     lifecycle, and every other phase is a device phase (frozen P6.0v target (a): 0 / 0 / 0),
#     so the whole triple is the ODE's / HostPhase's.
#  2. Lattice-size invariance. A phase that does not read σ moves the same bytes on a
#     16² (12²) and a 32² (24²) lattice with the same cells. The lattices carry a domain
#     mask (all sites in the domain), so this also pins A4/H3: the static mask is not copied
#     every MCS.
#  3. Bound. Per-MCS bytes ≤ (bytes of the columns read, once down) + (bytes of the columns
#     written, once up) + P60V2_SLACK. Columns a phase writes may also be read (in-place
#     updates such as `add_link!`), so they are allowed down as well. The adaptive phase
#     may read `volume` (it skips dead cells) and `kind` (the capacity); a `@link` phase may
#     read σ, `kind`, `volume`, the centroid trackers (`anchor`, `m1`, `m2`) and its
#     relationship's adjacency and payload columns. P60V2_SLACK = 16 B covers up to four
#     4-byte scalar read-backs (a status word or a live-cell count) that an implementation
#     may need; capacities are chosen so that every column is ≥ 64 B, i.e. the slack is
#     smaller than any column, so no extra column fits in it. A device implementation
#     (0 B) satisfies every bound ("or run on the device", ROADMAP).
#  4. Negative controls: each phase actually ran on Metal (ODE values follow their
#     analytic solutions; HostPhase effects are present; the extra `z1` rule ran), and its
#     results equal the CPU / current-path results up to Float32 tolerance.
# On the CPU (always): results equal the current path. ODE solutions match the analytic
# solutions and are identical between the pair members; a HostPhase with declared
# reads/writes has exactly the effect of the same body without declarations.
#
# HostPhase API (proposed surface; ruling for the coordinator). `HostPhase` today declares
# nothing (it gets `f!` and `every`), so it cannot know its columns. This file uses
#     HostPhase(f!; every = 1, reads = nothing, writes = nothing)
# `reads` / `writes`: tuples of Symbols naming the state leaves the body touches: `:σ` (the
# labels) or a cell column name. `nothing` (the default) keeps today's behaviour: the whole
# state down, every cell column up. Columns in `writes` are copied down too (bodies update
# them in place) and are the only columns copied back. A name that is not `:σ` or a cell
# column of the state is an `ArgumentError` by the first MCS the phase runs (on every
# backend, so a typo never silently reads a stale host copy). What `f!` sees in undeclared
# leaves is unspecified. Potts fills the declarations in for its generated `@link`/`@unlink`
# phases (pinned through the `@link` pair below).
#
# Today: the CPU ODE and `@link` testsets pass (the current path is the reference); the
# HostPhase testsets fail with `MethodError: no method matching HostPhase(…; reads, writes)`;
# on Metal the pair and lattice invariances fail (the snapshot copies σ, every cell column,
# every model/site leaf, the mask and every parameter table each MCS).
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P

const P60V2_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
const P60V2_SLACK = 16
const P60V2_CAPACITY = 64
p60v2_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
p60v2_bytes(arrays) = isempty(arrays) ? 0 : sum(sizeof, arrays)

"""Per-MCS counter triples of `step!` (no saves), after `nwarm` warm-up MCS."""
function p60v2_deltas(prob, alg; backend, nwarm = 1, nstep = 3)
    integ = init(prob, alg; backend, save_start = false, save_end = false)
    for _ in 1:nwarm
        step!(integ)
    end
    out = NTuple{3, Int}[]
    for _ in 1:nstep
        c0 = p60v2_counts(integ.stats)
        step!(integ)
        push!(out, p60v2_counts(integ.stats) .- c0)
    end
    return out, integ
end

# ---------------------------------------------------------------------------------------
# Adaptive-ODE fixture pair: a cell ODE reading another cell column (`r`) and a model ODE.
# y_c(t) = exp(−k r_c t), g(t) = exp(−k t). The wide member adds unused (by the ODEs) cell
# columns z1–z3, a model quantity q, a site field h and parameter tables Q, R.

@potts_model P60v2Ode begin
    @structural_parameters lattice = (16, 16)
    @kinds medium A
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        r(cell) = 1.0
        g(model) = 1.0
    end
    @lattice Lattice(lattice; boundary = Closed(), domain = x -> true)
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * r * y
        D(g) ~ -k * g
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60v2OdeWide begin
    @structural_parameters lattice = (16, 16)
    @kinds medium A
    @parameters begin
        k = 0.3
        Q[kind, kind] = [0.0 1.0; 1.0 2.0]
        R[kind] = [0.0, 3.0]
    end
    @variables begin
        y(cell) = 1.0
        r(cell) = 1.0
        g(model) = 1.0
        z1(cell) = 2.0
        z2(cell) = 3.0
        z3(cell) = 4.0
        q(model) = 5.0
        h(site) = 0.5
    end
    @lattice Lattice(lattice; boundary = Closed(), domain = x -> true)
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * r * y
        D(g) ~ -k * g
    end
    @after_mcs z1 ~ z1 + 1
    @sweep Metropolis(; temperature = 1.0)
end
const P60V2_K = 0.3
const P60V2_R = [1.0, 2.0]
function p60v2_ode_problem(; wide = false, lattice = (16, 16), T = Float64, nmcs = 5)
    σ = zeros(Int32, lattice)
    σ[3:6, 3:6] .= 1
    σ[10:13, 10:13] .= 2
    M = wide ? P60v2OdeWide : P60v2Ode
    return PottsProblem(M(; name = :p60v2ode, lattice), [ownership => σ, kind => [:A, :A], :r => P60V2_R], (0, nmcs);
        T, capacity = P60V2_CAPACITY, seed = 3, ode_solver = Adaptive(Rodas5P(); reltol = 1e-8, abstol = 1e-10))
end
"""Bytes the ODE phases may move per MCS: down y, r, volume, kind and g (plus any scratch
outputs, which are written); up the outputs."""
function p60v2_ode_bound(u0)
    cell, model = u0.cell, u0.model
    outs_cell = [getfield(cell, n) for n in keys(cell) if n === :y || n === :y__ode]
    outs_model = [getfield(model, n) for n in keys(model) if n === :g || n === :g__ode]
    down = p60v2_bytes([cell.r, cell.volume, cell.kind, outs_cell..., outs_model...])
    up = p60v2_bytes([outs_cell..., outs_model...])
    return down + up + P60V2_SLACK
end
p60v2_y_exact(t) = exp.(-P60V2_K .* P60V2_R .* t)
p60v2_g_exact(t) = exp(-P60V2_K * t)

# ---------------------------------------------------------------------------------------
# HostPhase fixtures (CorePotts level). 32 cell slots (2 live cells, so every Float32 or
# Int32 column is 128 B), a domain-masked lattice. Bodies:
#   :xy    y[c] += x[c] for every slot           reads (:x,), writes (:y,)
#   :sigma y[c] = count(==(c), σ) for c = 1, 2   reads (:σ,), writes (:y,)
#   :none  the :xy body with no declarations (today's whole-state path)
# The wide member adds cell columns z1 (Float), z2 (Int32), z3 (3 × capacity), a model
# quantity q, a site field h and a parameter table Q.

const P60V2_NCELL = 32
p60v2_xy!(cell, st, p, ctx, mcs) = (for c in eachindex(cell.y)
    cell.y[c] += cell.x[c]
end; nothing)
p60v2_sigma!(cell, st, p, ctx, mcs) = (for c in 1:2
    cell.y[c] = count(==(Int32(c)), st.σ)
end; nothing)
function p60v2_hostphase(body; bad = false)
    body === :none && return CorePotts.HostPhase(p60v2_xy!)
    body === :xy && return CorePotts.HostPhase(p60v2_xy!; reads = bad ? (:x, :nonexistent) : (:x,), writes = (:y,))
    body === :sigma && return CorePotts.HostPhase(p60v2_sigma!; reads = (:σ,), writes = (:y,))
    error("unknown body $body")
end
function p60v2_host_problem(; body = :xy, wide = false, dims = (12, 12), T = Float64, bad = false, nmcs = 4)
    σ = zeros(Int32, dims)
    σ[3:6, 3:6] .= 1
    σ[8:11, 7:10] .= 2
    n = P60V2_NCELL
    cell = (; x = T.(1:n) ./ 8, y = zeros(T, n))
    model = (;)
    site = (;)
    if wide
        cell = merge(cell, (; z1 = fill(T(2), n), z2 = fill(Int32(7), n), z3 = ones(T, 3, n)))
        model = (; q = T[5])
        site = (; h = fill(T(0.5), dims))
    end
    u0 = CorePotts.initial_state(σ, ones(Int32, n); cell, model, site)
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (p60v2_hostphase(body; bad),)))
    p = (; λ = T(1), V0 = T(16), T = T(2))
    wide && (p = merge(p, (; Q = T[1 2; 3 4])))
    lat = CorePotts.Lattice(dims; domain = trues(dims))
    return CorePotts.PottsProblem(f, u0, lat, (0, nmcs), p)
end
"""Bytes a HostPhase body may move per MCS: its read columns down, its written columns down
and up."""
function p60v2_host_bound(u0, body)
    y = sizeof(u0.cell.y)
    body === :xy && return sizeof(u0.cell.x) + 2y + P60V2_SLACK
    body === :sigma && return sizeof(u0.σ) + 2y + P60V2_SLACK
    error("no bound for $body")
end

# ---------------------------------------------------------------------------------------
# `@link` fixture pair (Potts generates the HostPhase and must fill in its declarations).
# Cells 1 and 2 touch, cell 3 is far; T = 0 and a weight-100 volume constraint at the cells'
# volumes reject every copy, so the link 1–2 (rest 3) is made at MCS 0 deterministically.

@potts_model P60v2Link begin
    @kinds medium A
    @variables rest(bond) = 3.0
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy cells => 100 * (volume - 16)^2
    @link bond when = new_contact(a, b)
    @sweep Metropolis(; temperature = 0.0)
end
@potts_model P60v2LinkWide begin
    @kinds medium A
    @parameters Q[kind, kind] = [0.0 1.0; 1.0 2.0]
    @variables begin
        rest(bond) = 3.0
        z1(cell) = 2.0
        z2(cell) = 3.0
        q(model) = 5.0
        h(site) = 0.5
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy cells => 100 * (volume - 16)^2
    @link bond when = new_contact(a, b)
    @after_mcs z1 ~ z1 + 1
    @sweep Metropolis(; temperature = 0.0)
end
function p60v2_link_problem(; wide = false, T = Float64, nmcs = 4)
    σ = zeros(Int32, 16, 16)
    σ[3:6, 3:6] .= 1
    σ[7:10, 3:6] .= 2
    σ[11:14, 11:14] .= 3
    M = wide ? P60v2LinkWide : P60v2Link
    return PottsProblem(M(; name = :p60v2link), [ownership => σ, kind => [:A, :A, :A]], (0, nmcs);
        T, capacity = P60V2_CAPACITY, seed = 5)
end
_p60v2_linkcol(n) = startswith(String(n), "links") || startswith(String(n), "link_")
function p60v2_link_bound(u0)
    cell = u0.cell
    rel = [getfield(cell, n) for n in keys(cell) if _p60v2_linkcol(n)]
    reads = [getfield(cell, n) for n in (:kind, :volume, :anchor, :m1, :m2) if haskey(cell, n)]
    return sizeof(u0.σ) + p60v2_bytes(reads) + 2 * p60v2_bytes(rel) + P60V2_SLACK
end
p60v2_bond(cell) = CorePotts.link_store(cell, :bond)

# ---------------------------------------------------------------------------------------

@testset "P6.0v2: fixtures differ only by untouched quantities" begin
    a, b = p60v2_ode_problem(), p60v2_ode_problem(; wide = true)
    @test issubset(keys(a.u0.cell), keys(b.u0.cell)) && length(keys(b.u0.cell)) >= length(keys(a.u0.cell)) + 3
    @test haskey(b.u0.model, :q) && haskey(b.u0.site, :h) && !haskey(a.u0.site, :h)
    @test a.lattice.mask !== nothing                          # the mask exists (pins A4)
    @test all(c -> sizeof(getfield(a.u0.cell, c)) >= 64, keys(a.u0.cell))   # slack < any column
    a, b = p60v2_link_problem(), p60v2_link_problem(; wide = true)
    @test issubset(keys(a.u0.cell), keys(b.u0.cell)) && length(keys(b.u0.cell)) >= length(keys(a.u0.cell)) + 2
end

@testset "P6.0v2: adaptive ODE results on the CPU (current path)" begin
    for alg in (SequentialCPM(), CheckerboardCPM())
        n = 5
        ua = solve(p60v2_ode_problem(; nmcs = n), alg).u[end]
        ub = solve(p60v2_ode_problem(; nmcs = n, wide = true), alg).u[end]
        @test ua.cell.y[1:2] ≈ p60v2_y_exact(n) rtol = 1e-6
        @test ua.model.g[1] ≈ p60v2_g_exact(n) rtol = 1e-6
        @test ub.cell.y[1:2] == ua.cell.y[1:2] && ub.model.g == ua.model.g
        @test ub.σ == ua.σ                                          # the extras change nothing else
        @test ub.cell.z1[1:2] == fill(2.0 + n, 2)                   # the extra rule ran
    end
end

@testset "P6.0v2: HostPhase declarations on the CPU" begin
    n = 4
    for alg in (SequentialCPM(), CheckerboardCPM())
        ref = solve(p60v2_host_problem(; body = :none, nmcs = n), alg).u[end]
        for wide in (false, true)
            u = solve(p60v2_host_problem(; body = :xy, wide, nmcs = n), alg).u[end]
            @test u.cell.y == ref.cell.y                            # same effect as undeclared
            @test u.σ == ref.σ
            @test u.cell.y ≈ n .* u.cell.x                          # the body ran every MCS
            u = solve(p60v2_host_problem(; body = :sigma, wide, nmcs = n), alg).u[end]
            @test u.cell.y[1:2] == Float64.(u.cell.volume[1:2])     # σ was read
            @test all(iszero, u.cell.y[3:end])
        end
        @test_throws ArgumentError begin
            integ = init(p60v2_host_problem(; bad = true), alg)
            step!(integ)
        end
    end
end

@testset "P6.0v2: @link results on the CPU (current path)" begin
    for alg in (SequentialCPM(), CheckerboardCPM())
        ua = solve(p60v2_link_problem(), alg).u[end]
        ub = solve(p60v2_link_problem(; wide = true), alg).u[end]
        A, B = p60v2_bond(ua.cell), p60v2_bond(ub.cell)
        @test CorePotts.linked(A, 1, 2) && !CorePotts.linked(A, 1, 3) && !CorePotts.linked(A, 2, 3)
        @test A.links == B.links && ua.cell.link_rest == ub.cell.link_rest
        @test ua.σ == ub.σ
    end
end

@testset "P6.0v2: adaptive-ODE column-only copies on Metal" begin
    if P60V2_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        host(a) = Array(a)
        nar = p60v2_ode_problem(; T = Float32)
        da, ia = p60v2_deltas(nar, alg; backend)
        db, ib = p60v2_deltas(p60v2_ode_problem(; T = Float32, wide = true), alg; backend)
        dl, il = p60v2_deltas(p60v2_ode_problem(; T = Float32, lattice = (32, 32)), alg; backend)
        @info "P6.0v2 adaptive-ODE MCS (syncs, transfers, bytes)" narrow = da wide = db lattice32 = dl bound = p60v2_ode_bound(nar.u0)
        @test all(==(first(da)), da)                                # the same every MCS
        @test db == da                                              # extra quantities: not moved
        @test dl == da                                              # no σ, no mask per MCS
        @test all(d -> d[3] <= p60v2_ode_bound(nar.u0), da)
        # negative controls: the ODEs ran (4 MCS: t = 4) and match the CPU
        for integ in (ia, ib, il)
            @test host(integ.state.cell.y)[1:2] ≈ p60v2_y_exact(4) rtol = 1e-4
            @test host(integ.state.model.g)[1] ≈ p60v2_g_exact(4) rtol = 1e-4
        end
        @test host(ib.state.cell.z1)[1:2] == fill(6.0f0, 2)
        cpu = solve(p60v2_ode_problem(; T = Float32, nmcs = 4), alg).u[end]
        @test host(ia.state.cell.y)[1:2] ≈ cpu.cell.y[1:2] rtol = 1e-5
        @test host(ia.state.model.g) ≈ cpu.model.g rtol = 1e-5
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

@testset "P6.0v2: HostPhase column-only copies on Metal" begin
    if P60V2_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        host(a) = Array(a)
        for body in (:xy, :sigma)
            nar = p60v2_host_problem(; body, T = Float32)
            da, ia = p60v2_deltas(nar, alg; backend)
            db, ib = p60v2_deltas(p60v2_host_problem(; body, T = Float32, wide = true), alg; backend)
            @info "P6.0v2 HostPhase MCS (syncs, transfers, bytes)" body narrow = da wide = db bound = p60v2_host_bound(nar.u0, body)
            @test all(==(first(da)), da)
            @test db == da
            @test all(d -> d[3] <= p60v2_host_bound(nar.u0, body), da)
            if body === :xy
                dl, il = p60v2_deltas(p60v2_host_problem(; body, T = Float32, dims = (24, 24)), alg; backend)
                @test dl == da                                      # σ not read: lattice-free
                @test all(d -> d[3] > 0, da)                        # x and y do cross (host body)
                # negative control: 4 MCS ran the body; same effect as the undeclared phase
                for integ in (ia, ib, il)
                    @test host(integ.state.cell.y) ≈ 4 .* host(integ.state.cell.x)
                end
                _, iref = p60v2_deltas(p60v2_host_problem(; body = :none, T = Float32), alg; backend)
                @test host(ia.state.cell.y) == host(iref.state.cell.y)
                @test host(ia.state.σ) == host(iref.state.σ)
            else
                @test all(d -> d[3] >= sizeof(nar.u0.σ), da)       # σ declared: it comes down
                for integ in (ia, ib)
                    @test host(integ.state.cell.y)[1:2] == Float32.(host(integ.state.cell.volume)[1:2])
                    @test all(iszero, host(integ.state.cell.y)[3:end])
                end
            end
        end
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

@testset "P6.0v2: @link column-only copies on Metal" begin
    if P60V2_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        host(a) = Array(a)
        nar = p60v2_link_problem(; T = Float32)
        da, ia = p60v2_deltas(nar, alg; backend)
        db, ib = p60v2_deltas(p60v2_link_problem(; T = Float32, wide = true), alg; backend)
        @info "P6.0v2 @link MCS (syncs, transfers, bytes)" narrow = da wide = db bound = p60v2_link_bound(nar.u0)
        @test all(==(first(da)), da)
        @test db == da
        @test all(d -> d[3] <= p60v2_link_bound(nar.u0), da)
        cpu = solve(p60v2_link_problem(; T = Float32, nmcs = 4), alg).u[end]
        for integ in (ia, ib)
            cell = map(host, integ.state.cell)
            S = p60v2_bond(cell)
            @test CorePotts.linked(S, 1, 2) && !CorePotts.linked(S, 1, 3) && !CorePotts.linked(S, 2, 3)
            @test S.links == p60v2_bond(cpu.cell).links
            @test cell.link_rest == cpu.cell.link_rest
        end
        @test host(ib.state.cell.z1)[1:3] == fill(6.0f0, 3)
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end
