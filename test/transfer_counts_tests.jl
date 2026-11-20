# Exact host-transfer counts of the current device code paths. A regression test proving
# `stats.syncs`, `stats.transfers` and `stats.transfer_bytes` count exactly: each expected
# value is hand-counted from the call sites. Changes that remove transfers update the formulas
# here (the lifecycle on the device did; so did column-only HostPhase / _AdaptiveODE copies).
# Device only (POTTS_GPU = metal | rocm, test/shared/devices.jl); on the CPU nothing is counted
# (the acceptance file `lib/PottsModels/test/acceptance/transfer_counters_tests.jl` checks that).
#
# Counting rules: one contiguous host↔device array copy is one
# transfer, including each array leaf of an `Adapt.adapt(Array, …)` snapshot; bytes are
# `sizeof` of the device array; device→device copies and device `fill!` are not counted.
#
# Included from `test/gpu.jl` (POTTS_GPU = metal | rocm). Names carry a `tc_` / `TC_` / `Tc` prefix so
# this file can share a session with the acceptance file.

@testsetup module TransferCountsSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Test, Potts

using Potts: CorePotts


tc_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)


# Division fixture: both 4×2 cells divide at MCS 0 (T = 0, weight-100 volume constraint:
# every copy of MCS 0 is rejected), plane normal (1, 0), split 4 | 4.
@potts_model TcDivide begin
    @kinds medium A
    @variables m(cell) = 1.0
    @lattice Lattice((16, 8))
    @energy cells => 100 * (volume - 8)^2
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 0.0)
end

function tc_divide_problem(; T = Float64, tspan = (0, 4))
    σ = zeros(Int32, 16, 8)
    σ[3:6, 2:3] .= 1
    σ[10:13, 5:6] .= 2
    return PottsProblem(
        TcDivide(; name = :tc), [ownership => σ, kind => [:A, :A]], tspan;
        T, capacity = 6)
end


"""Hand count of the event MCS of the division fixture on a device backend. Since
the lifecycle is planned and applied on the device (`run_lifecycle_device!`
enqueues kernels only): (0, 0, 0). Before it, the host plan made (2, 18, 1098)."""
tc_division_counts(u0) = (0, 0, 0)


"""Hand count of `current_state(integ)` (a host read point) for a model with a device lifecycle: one
sync (`current_state`), the fold of the device lifecycle statistics (`_fold_lifecycle!`:
one transfer of the `Int32` accumulators), the fold of the checkerboard's copy counts (one
transfer of its per-block `Int32` counters, `nblocks`), and the snapshot (one transfer per
array leaf of the state, `sizeof` bytes each). `u0` is the problem's host state."""
function tc_read_counts(u0, nblocks)
    leaves = Any[u0.ownership, values(u0.cell)..., values(u0.site)..., values(u0.model)..., values(u0.history)...]
    return (1, 2 + length(leaves), (CorePotts._NACC + nblocks) * sizeof(Int32) + sum(sizeof, leaves))
end


# HostPhase fixture (CorePotts level): a no-op host phase after every sweep.
function tc_hostphase_problem(; T = Float64)
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
tc_hostphase_counts(u0) =
    (1, 1 + 2 * length(u0.cell), sizeof(u0.ownership) + 2 * sum(sizeof, values(u0.cell)))


# Declared HostPhase on a domain-masked lattice (D-092): y += x, reads (:x,),
# writes (:y,).
function tc_declared_problem(; T = Float64)
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
tc_declared_counts(u0) = (1, 3, sizeof(u0.cell.x) + 2 * sizeof(u0.cell.y))


# A HostPhase body gets the live `p`: an in-place change of a parameter array
# between MCS is seen (no stale host copy), and a body's writes to a parameter array persist.
function tc_param_problem(body!; T = Float32, declared = true)
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

tc_read_q!(cell, st, p, ctx, mcs) = (cell.y[1] += Array(p.Q)[1]; nothing)

tc_write_acc!(cell, st, p, ctx, mcs) = (p.acc .+= 1; nothing)


# Every GPU wait of a quiet MCS is a counted one. On Metal a
# counted sync waits once and a counted transfer twice (Metal.jl synchronizes before the copy
# and waits for its blit), so the waits of an MCS must equal `syncs + 2 transfers`. Waits the
# counters cannot see (Metal.jl's device→device `copyto!`, `UInt8`/`Int8` `fill!`) break the
# identity (D-101 removed them from the step path: kernel copies and fills).
# Test-only instrumentation: `Metal.wait_cmdbuf!` gains a counter; the queue-depth
# back-pressure of `wait_oldest_cleanup!` (the host running ahead of the GPU) is not a sync
# and is excluded. The redefinitions copy Metal.jl 1.10.0's bodies, hence the version guard.
const TC_WAITS = Ref(0)

const TC_INFLIGHT = Ref(false)

function tc_instrument_waits!()
    M = PottsDevices.device_package()
    @eval M function wait_oldest_cleanup!(bq::BatchedCommandQueue)
        isempty(bq.cleanups) && return
        cmdbuf = first(bq.cleanups).cmdbuf
        $(TC_INFLIGHT)[] = true
        try
            wait_cmdbuf!(cmdbuf)
        finally
            $(TC_INFLIGHT)[] = false
        end
        drain_cleanups!(bq)
        return
    end
    @eval M function wait_cmdbuf!(cmdbuf::MTL.MTLCommandBufferLike)
        $(TC_INFLIGHT)[] || ($(TC_WAITS)[] += 1)
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
# The wait counter wraps Metal.jl internals, so it is Metal-only; ROCm skips it (D-157).
# The gate models are the acceptance file's (`transfer_counters_tests.jl`); on Metal this
# setup includes the file itself, which runs its testsets once more.
if PottsDevices.device_name() == "metal"
    let counters_path = joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "transfer_counters_tests.jl"),
            runner = joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl")
        Core.eval(
            @__MODULE__, :(
                module TransferCountersOnDevice
                    include($runner)
                    PottsModelsTestFile.run_file(@__MODULE__, $counters_path)
        end))
    end
end
const TC_ON_METAL = PottsDevices.device_name() == "metal" && isdefined(@__MODULE__, :TransferCountersOnDevice)

const TC_METAL_VERSION = TC_ON_METAL ? pkgversion(PottsDevices.device_package()) : nothing

const TC_WAITS_ON = TC_ON_METAL && TC_METAL_VERSION == v"1.10.0"

TC_WAITS_ON && tc_instrument_waits!()
      # at top level: the testsets must see the new methods

"""GPU waits and counter deltas of `f()`."""
function tc_waits(f)
    c0, w0 = tc_counts(TC_STATS[]), TC_WAITS[]
    f()
    d = tc_counts(TC_STATS[]) .- c0
    return TC_WAITS[] - w0, d
end

const TC_STATS = Ref{Any}(nothing)
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "exact transfer counts of the current paths (device)" setup = [TransferCountsSetup] tags = [:potts, :transfer_counts, :gpu, :device] begin
    @testset "exact transfer counts of the current paths (device)" begin
        if PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            prob = tc_divide_problem(; T = Float32)
            integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
            c0 = tc_counts(integ.stats)
            step!(integ)                                                     # MCS 0: both cells divide
            @test tc_counts(integ.stats) .- c0 == tc_division_counts(prob.u0)
            c1 = tc_counts(integ.stats)
            u = current_state(integ)                                                      # a host read point
            @test tc_counts(integ.stats) .- c1 == tc_read_counts(prob.u0, CorePotts.nblocks(integ.cache.layout))
            @test integ.stats.lifecycle.divisions == 2                       # folded at the read
            @test count(>(0), u.cell.volume) == 4
            prob = tc_hostphase_problem(; T = Float32)
            integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
            for _ in 1:3
                c0 = tc_counts(integ.stats)
                step!(integ)
                @test tc_counts(integ.stats) .- c0 == tc_hostphase_counts(prob.u0)
            end
            prob = tc_declared_problem(; T = Float32)
            integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
            c0 = tc_counts(integ.stats)
            step!(integ)                                                     # the mask comes down once
            @test tc_counts(integ.stats) .- c0 == tc_declared_counts(prob.u0) .+ (0, 1, sizeof(prob.lattice.mask))
            for _ in 1:2
                c0 = tc_counts(integ.stats)
                step!(integ)
                @test tc_counts(integ.stats) .- c0 == tc_declared_counts(prob.u0)
            end
            @test Array(integ.state.cell.y) == 3 .* Array(integ.state.cell.x)    # the body ran
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "HostPhase bodies see and write the live p (device)" setup = [TransferCountsSetup] tags = [:potts, :transfer_counts, :gpu, :device] begin
    @testset "HostPhase bodies see and write the live p (device)" begin
        if PottsDevices.on_device()
            alg = CheckerboardCPM()
            out = map((CorePotts.CPU(), PottsDevices.device_backend())) do backend
                integ = init(tc_param_problem(tc_read_q!), alg; backend, save_start = false, save_everystep = false, save_end = false)
                step!(integ); step!(integ)
                integ.p.Q .= 10                                  # in place, between MCS
                step!(integ); step!(integ)
                y = Array(integ.state.cell.y)[1]
                integ = init(
                    tc_param_problem(tc_write_acc!; declared = false), alg; backend,
                    save_start = false, save_everystep = false, save_end = false
                )
                foreach(_ -> step!(integ), 1:3)
                (y, Array(integ.p.acc)[1])
            end
            @test out[1] == (22.0f0, 3.0f0)                      # 1 + 1 + 10 + 10; the body ran 3 times
            @test out[2] == out[1]
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "every GPU wait is counted (Metal; quiet, event and HostPhase MCS)" setup = [TransferCountsSetup] tags = [:potts, :transfer_counts, :gpu, :device] begin
    @testset "every GPU wait is counted (Metal; quiet, event and HostPhase MCS)" begin
        if TC_ON_METAL
            @test TC_METAL_VERSION == v"1.10.0"
            TC_METAL_VERSION == v"1.10.0" || @error "test/transfer_counts.jl copies Metal.jl 1.10.0's " *
                "`wait_cmdbuf!`/`wait_oldest_cleanup!`; Metal is $TC_METAL_VERSION: update the copies and the version"
        else
            @test_skip "device (POTTS_GPU=metal, from test/gpu.jl; Metal.jl wait counter)"
        end
        if TC_WAITS_ON
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            # quiet MCS of every gate model
            for (label, _, make) in TransferCountersOnDevice.TransferCountersSetup.gate_models(Float32)
                integ = init(make(), alg; backend, save_start = false, save_everystep = false, save_end = false)
                TC_STATS[] = integ.stats
                step!(integ); step!(integ)
                PottsDevices.device_sync()
                for _ in 1:3
                    waits, d = tc_waits(() -> step!(integ))
                    @test waits == d[1] + 2 * d[2]    # Merks too: the field phase copies by kernel (D-101)
                end
            end
            # the event MCS of the division fixture: planned on the device (D-089), no
            # wait at all (2 syncs + 2 × 18 transfers = 38 waits on the D-035 host plan)
            prob = tc_divide_problem(; T = Float32)
            integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
            TC_STATS[] = integ.stats
            PottsDevices.device_sync()
            waits, d = tc_waits(() -> step!(integ))
            @test waits == d[1] + 2 * d[2]
            @test waits == 0
            @test checkpoint(integ).stats.lifecycle.divisions == 2           # control: the event fired
            # HostPhase MCS
            integ = init(tc_hostphase_problem(; T = Float32), alg; backend, save_start = false, save_everystep = false, save_end = false)
            TC_STATS[] = integ.stats
            PottsDevices.device_sync()
            for _ in 1:2
                waits, d = tc_waits(() -> step!(integ))
                @test d[2] > 0 && waits == d[1] + 2 * d[2]
            end
        end
    end
end
