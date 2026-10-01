# Exact host-transfer counts of the CURRENT device code paths (P6.0v; not frozen). An
# ordinary regression test proving `stats.syncs`, `stats.transfers` and
# `stats.transfer_bytes` count exactly: each expected value is hand-counted from the call
# sites. Later rows that remove transfers (P6.0v1: lifecycle on the device; P6.0v2:
# column-only HostPhase / _AdaptiveODE copies, done) update the formulas here. Metal only
# (POTTS_GPU=metal with Metal loaded); on the CPU nothing is counted (the frozen
# acceptance file `lib/PottsModels/test/acceptance/p6_0v_transfer_counters.jl` checks that).
#
# Counting rules (frozen file header): one contiguous host↔device array copy is one
# transfer, including each array leaf of an `Adapt.adapt(Array, …)` snapshot; bytes are
# `sizeof` of the device array; device→device copies and device `fill!` are not counted.
#
# Included from `test/gpu.jl` (POTTS_GPU=metal). Names carry a `p60vx_` / `P60vx` prefix so
# this file can share a session with the acceptance file.
using Test, Potts
using Potts: CorePotts

p60vx_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)

# Division fixture: both 4×2 cells divide at MCS 0 (T = 0, weight-100 volume constraint:
# every copy of MCS 0 is rejected), plane normal (1, 0), split 4 | 4.
@potts_model P60vxDivide begin
    @kinds medium A
    @variables m(cell) = 1.0
    @lattice Lattice((16, 8))
    @energy cells => 100 * (volume - 8)^2
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 0.0)
end
function p60vx_divide_problem(; T = Float64, tspan = (0, 4))
    σ = zeros(Int32, 16, 8)
    σ[3:6, 2:3] .= 1
    σ[10:13, 5:6] .= 2
    return PottsProblem(P60vxDivide(; name = :p60vx), [ownership => σ, kind => [:A, :A]], tspan;
        T, capacity = 6)
end

"""Hand count of the event MCS of the division fixture on a device backend, from
`run_lifecycle!` and `rebuild_trackers!` (lifecycle.jl, as of 1554d56 + P6.0d ee2331b). `u0` is the
problem's host state, whose arrays have the device arrays' sizes. Returns
`(syncs, transfers, bytes)`: (2, 18, 1098) at capacity 6 on 16×8 with Float32."""
function p60vx_division_counts(u0)
    cell = u0.cell
    C = length(cell.kind)
    @assert keys(cell) == (:kind, :volume, :generation, :m, :anchor, :m1, :m2)   # no surface, links, clusters
    i32 = sizeof(Int32)
    down = [i32,                         # event count (`_readback(cache.count)`)
        i32 * C,                         # `Array(cache.events)`
        sizeof(cell.volume)]             # `Array(st.cell.volume)` (free slots)
    up = [i32 * C,                       # `copyto!(cache.daughter, …)`
        sizeof(Bool) * C,                # `copyto!(cache.removed, …)`
        i32 * C]                         # `copyto!(cache.events, …)`
    for name in (:kind, :m)              # `_copy_columns!`: every non-tracker column, down and up
        push!(down, sizeof(cell[name])); push!(up, sizeof(cell[name]))
    end
    push!(down, sizeof(cell.generation)); push!(up, sizeof(cell.generation))   # generation round trip
    push!(down, sizeof(u0.σ))                                                    # `rebuild_trackers!`: σ down
    append!(up, sizeof.((cell.volume, cell.anchor, cell.m1, cell.m2)))          # trackers up
    push!(down, sizeof(cell.volume))                                             # empty-daughter count
    return (2, length(down) + length(up), sum(down) + sum(up))  # syncs: trigger, rebuild_trackers!
end

# HostPhase fixture (CorePotts level): a no-op host phase after every sweep.
function p60vx_hostphase_problem(; T = Float64)
    σ = zeros(Int32, 12, 12)
    σ[3:6, 3:6] .= 1
    σ[8:11, 7:10] .= 2
    u0 = CorePotts.initial_state(σ, Int32[1, 1]; cell = (; x = zeros(T, 2), y = zeros(T, 2)))
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (CorePotts.HostPhase((cell, st, p, ctx, mcs) -> nothing),)))
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(size(σ)), (0, 4), (; λ = T(1), V0 = T(16), T = T(2)))
end
"""`HostPhase` (relationships.jl): 1 sync; the snapshot (σ and every cell column) down;
every cell column up. (1, 11, 656) for this fixture with Float32."""
p60vx_hostphase_counts(u0) =
    (1, 1 + 2 * length(u0.cell), sizeof(u0.σ) + 2 * sum(sizeof, values(u0.cell)))

# Declared HostPhase on a domain-masked lattice (P6.0v2, D-092): y += x, reads (:x,),
# writes (:y,).
function p60vx_declared_problem(; T = Float64)
    σ = zeros(Int32, 12, 12)
    σ[3:6, 3:6] .= 1
    σ[8:11, 7:10] .= 2
    u0 = CorePotts.initial_state(σ, Int32[1, 1]; cell = (; x = ones(T, 2), y = zeros(T, 2), z = zeros(T, 2)))
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    body!(cell, st, p, ctx, mcs) = (cell.y .+= cell.x; nothing)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (CorePotts.HostPhase(body!; reads = (:x,), writes = (:y,)),)))
    lat = CorePotts.Lattice(size(σ); domain = trues(size(σ)))
    return CorePotts.PottsProblem(f, u0, lat, (0, 4), (; λ = T(1), V0 = T(16), T = T(2)))
end
"""Declared `HostPhase`: 1 sync; `x` and `y` down, `y` up. The domain mask (for
`ctx.lattice`) comes down on the first run only (then cached)."""
p60vx_declared_counts(u0) = (1, 3, sizeof(u0.cell.x) + 2 * sizeof(u0.cell.y))

@testset "P6.0v: exact transfer counts of the current paths (Metal)" begin
    if get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        prob = p60vx_divide_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        c0 = p60vx_counts(integ.stats)
        step!(integ)                                                     # MCS 0: both cells divide
        @test integ.stats.lifecycle.divisions == 2
        @test p60vx_counts(integ.stats) .- c0 == p60vx_division_counts(prob.u0)
        prob = p60vx_hostphase_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        for _ in 1:3
            c0 = p60vx_counts(integ.stats)
            step!(integ)
            @test p60vx_counts(integ.stats) .- c0 == p60vx_hostphase_counts(prob.u0)
        end
        prob = p60vx_declared_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        c0 = p60vx_counts(integ.stats)
        step!(integ)                                                     # the mask comes down once
        @test p60vx_counts(integ.stats) .- c0 == p60vx_declared_counts(prob.u0) .+ (0, 1, sizeof(prob.lattice.mask))
        for _ in 1:2
            c0 = p60vx_counts(integ.stats)
            step!(integ)
            @test p60vx_counts(integ.stats) .- c0 == p60vx_declared_counts(prob.u0)
        end
        @test Array(integ.state.cell.y) == 3 .* Array(integ.state.cell.x)    # the body ran
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

# Every GPU wait of a quiet MCS is a counted one (P6.0v3 / proposed P6.0v8). On Metal a
# counted sync waits once and a counted transfer twice (Metal.jl synchronizes before the copy
# and waits for its blit), so the waits of an MCS must equal `syncs + 2 transfers`. Waits the
# counters cannot see (Metal.jl's device→device `copyto!`, `UInt8`/`Int8` `fill!`) break the
# identity. Test-only instrumentation: `Metal.wait_cmdbuf!` gains a counter; the queue-depth
# back-pressure of `wait_oldest_cleanup!` (the host running ahead of the GPU) is not a sync
# and is excluded. The redefinitions copy Metal.jl 1.10.0's bodies, hence the version guard.
const P60VX_WAITS = Ref(0)
const P60VX_INFLIGHT = Ref(false)
function p60vx_instrument_waits!()
    M = Main.Metal
    @eval M function wait_oldest_cleanup!(bq::BatchedCommandQueue)
        isempty(bq.cleanups) && return
        cmdbuf = first(bq.cleanups).cmdbuf
        $(P60VX_INFLIGHT)[] = true
        try
            wait_cmdbuf!(cmdbuf)
        finally
            $(P60VX_INFLIGHT)[] = false
        end
        drain_cleanups!(bq)
        return
    end
    @eval M function wait_cmdbuf!(cmdbuf::MTL.MTLCommandBufferLike)
        $(P60VX_INFLIGHT)[] || ($(P60VX_WAITS)[] += 1)
        is_completed(cmdbuf) && return
        precompiling = ccall(:jl_generating_output, Cint, ()) != 0
        if use_nonblocking_synchronization && !precompiling
            spinning_synchronization(cmdbuf) || yielding_synchronization(cmdbuf)
        else
            wait_completed(cmdbuf)
        end
        return
    end
    return nothing
end

# On Metal (from test/gpu.jl) the instrumentation must apply: a Metal upgrade fails here
# loudly instead of silently disabling the Merks reminder (update the copied bodies above).
const P60VX_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal) &&
                       isdefined(Main, :P60vOnMetal)
const P60VX_METAL_VERSION = P60VX_ON_METAL ? pkgversion(Main.Metal) : nothing
const P60VX_WAITS_ON = P60VX_ON_METAL && P60VX_METAL_VERSION == v"1.10.0"
P60VX_WAITS_ON && p60vx_instrument_waits!()      # at top level: the testsets must see the new methods

"""GPU waits and counter deltas of `f()`."""
function p60vx_waits(f)
    c0, w0 = p60vx_counts(P60VX_STATS[]), P60VX_WAITS[]
    f()
    d = p60vx_counts(P60VX_STATS[]) .- c0
    return P60VX_WAITS[] - w0, d
end
const P60VX_STATS = Ref{Any}(nothing)

@testset "P6.0v: every GPU wait is counted (Metal; quiet, event and HostPhase MCS)" begin
    if P60VX_ON_METAL
        @test P60VX_METAL_VERSION == v"1.10.0"
        P60VX_METAL_VERSION == v"1.10.0" || @error "test/transfer_counts.jl copies Metal.jl 1.10.0's " *
            "`wait_cmdbuf!`/`wait_oldest_cleanup!`; Metal is $P60VX_METAL_VERSION: update the copies and the version"
    else
        @test_skip "POTTS_GPU=metal with Metal loaded, from test/gpu.jl"
    end
    if P60VX_WAITS_ON
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        # quiet MCS of every gate model
        for (label, _, make) in Main.P60vOnMetal.p60v_gate_models(Float32)
            integ = init(make(), alg; backend, save_start = false, save_end = false)
            P60VX_STATS[] = integ.stats
            step!(integ); step!(integ)
            Main.Metal.synchronize()
            for _ in 1:3
                waits, d = p60vx_waits(() -> step!(integ))
                if label == "Merks"          # FieldStep's device→device copies wait (P6.0v3)
                    @test_broken waits == d[1] + 2 * d[2]
                else
                    @test waits == d[1] + 2 * d[2]
                end
            end
        end
        # the event MCS of the division fixture (the runtime backstop for raw copies on the
        # event path until P6.0v1): 2 syncs + 2 × 18 transfers = 38 waits today
        prob = p60vx_divide_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        P60VX_STATS[] = integ.stats
        Main.Metal.synchronize()
        waits, d = p60vx_waits(() -> step!(integ))
        @test integ.stats.lifecycle.divisions == 2
        @test waits == d[1] + 2 * d[2]
        @test waits == 38
        # HostPhase MCS
        integ = init(p60vx_hostphase_problem(; T = Float32), alg; backend, save_start = false, save_end = false)
        P60VX_STATS[] = integ.stats
        Main.Metal.synchronize()
        for _ in 1:2
            waits, d = p60vx_waits(() -> step!(integ))
            @test d[2] > 0 && waits == d[1] + 2 * d[2]
        end
    end
end
