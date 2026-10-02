# Exact host-transfer counts of the CURRENT device code paths (P6.0v; not frozen). An
# ordinary regression test proving `stats.syncs`, `stats.transfers` and
# `stats.transfer_bytes` count exactly: each expected value is hand-counted from the call
# sites. Later rows that remove transfers update the formulas here (P6.0v1 did: the
# lifecycle on the device; P6.0v2: column-only HostPhase / _AdaptiveODE copies). Metal only
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

"""Hand count of the event MCS of the division fixture on a device backend. Since P6.0v1
(D-089) the lifecycle is planned and applied on the device (`run_lifecycle_device!`
enqueues kernels only): (0, 0, 0). Before it, the D-035 host plan made (2, 18, 1098)."""
p60vx_division_counts(u0) = (0, 0, 0)

"""Hand count of `integ.u` (a host read point) for a model with a device lifecycle: one
sync (`current_state`), the fold of the device lifecycle statistics (`_fold_lifecycle!`:
one transfer of the `Int32` accumulators), and the snapshot (one transfer per array leaf
of the state, `sizeof` bytes each). `u0` is the problem's host state."""
function p60vx_read_counts(u0)
    leaves = Any[u0.σ, values(u0.cell)..., values(u0.site)..., values(u0.model)..., values(u0.history)...]
    return (1, 1 + length(leaves), CorePotts._NACC * sizeof(Int32) + sum(sizeof, leaves))
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
        @test p60vx_counts(integ.stats) .- c0 == p60vx_division_counts(prob.u0)
        c1 = p60vx_counts(integ.stats)
        u = integ.u                                                      # a host read point
        @test p60vx_counts(integ.stats) .- c1 == p60vx_read_counts(prob.u0)
        @test integ.stats.lifecycle.divisions == 2                       # folded at the read
        @test count(>(0), u.cell.volume) == 4
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

# A HostPhase body gets the live `p` (P6.0v2 review): an in-place change of a parameter array
# between MCS is seen (no stale host copy), and a body's writes to a parameter array persist.
function p60vx_param_problem(body!; T = Float32, declared = true)
    σ = zeros(Int32, 12, 12)
    σ[3:6, 3:6] .= 1
    u0 = CorePotts.initial_state(σ, Int32[1, 1]; cell = (; y = zeros(T, 2)))
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    ph = declared ? CorePotts.HostPhase(body!; reads = (), writes = (:y,)) : CorePotts.HostPhase(body!)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (ph,)))
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(size(σ)), (0, 4),
        (; λ = T(1), V0 = T(16), T = T(2), Q = T[1, 1], acc = T[0]))
end
p60vx_read_q!(cell, st, p, ctx, mcs) = (cell.y[1] += Array(p.Q)[1]; nothing)
p60vx_write_acc!(cell, st, p, ctx, mcs) = (p.acc .+= 1; nothing)

@testset "P6.0v2: HostPhase bodies see and write the live p (Metal)" begin
    if get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
        alg = CheckerboardCPM()
        out = map((CorePotts.CPU(), Main.Metal.MetalBackend())) do backend
            integ = init(p60vx_param_problem(p60vx_read_q!), alg; backend, save_start = false, save_end = false)
            step!(integ); step!(integ)
            integ.p.Q .= 10                                  # in place, between MCS
            step!(integ); step!(integ)
            y = Array(integ.state.cell.y)[1]
            integ = init(p60vx_param_problem(p60vx_write_acc!; declared = false), alg; backend,
                save_start = false, save_end = false)
            foreach(_ -> step!(integ), 1:3)
            (y, Array(integ.p.acc)[1])
        end
        @test out[1] == (22.0f0, 3.0f0)                      # 1 + 1 + 10 + 10; the body ran 3 times
        @test out[2] == out[1]
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
        # the event MCS of the division fixture: planned on the device (P6.0v1, D-089), no
        # wait at all (2 syncs + 2 × 18 transfers = 38 waits on the D-035 host plan)
        prob = p60vx_divide_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        P60VX_STATS[] = integ.stats
        Main.Metal.synchronize()
        waits, d = p60vx_waits(() -> step!(integ))
        @test waits == d[1] + 2 * d[2]
        @test waits == 0
        @test checkpoint(integ).stats.lifecycle.divisions == 2           # control: the event fired
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
