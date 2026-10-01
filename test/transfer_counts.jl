# Exact host-transfer counts of the CURRENT device code paths (P6.0v; not frozen). An
# ordinary regression test proving `stats.syncs`, `stats.transfers` and
# `stats.transfer_bytes` count exactly: each expected value is hand-counted from the call
# sites. Later rows that remove transfers (P6.0v1: lifecycle on the device; P6.0v2:
# column-only HostPhase / _AdaptiveODE copies) update the formulas here. Metal only
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
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end
