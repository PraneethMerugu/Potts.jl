# Contact counts with a kind predicate (D-150 G1, `src/contact_counts.jl`) and the normal
# draws (`normal`, `bounded_normal`, the model status word): ordinary tests (D-048) against
# a brute-force count from σ, on both algorithms and every lifecycle planner.

# brute force: per cell, the pairs (s, s′) over `offs` with σ(s′) ≠ σ(s) and the partner's
# kind (0 for the medium) in `kinds`

@testsetup module CP_contact_counts
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("shared/contact_counts.jl")
include("shared/export_all.jl")
end

@testitem "contact counts" setup = [CP_contact_counts] tags = [:corepotts, :contact_counts] begin
@testset "contact counts" begin
    lat = Lattice((30, 24); boundary = (Periodic(), Closed()))
    @testset "recompute equals the unweighted surface for every kind" begin
        prob = cc_problem()
        st = prob.u0
            all3 = recompute_contact_count(st.ownership, st.cell.kind, lat, Moore(1), 0b111, length(st.cell.kind))
            @test all3 == recompute_surface(st.ownership, lat, relation(Moore(1), lat), length(st.cell.kind); T = Int32)
        @test st.cell.n_med != all3[1:end] && any(>(0), st.cell.n_two)          # the masks select
        @test CorePotts.radius(CorePotts.relation(prob.relations.contact_counts, lat)) == 1
        # masks hold kinds 0–63: more kinds, or a mask beyond the model's kinds, are errors
        @test_throws ArgumentError ContactCount(:n, Moore(1), 0b1; kinds = 65)
        @test_throws ArgumentError ContactCount(:n, Moore(1), 0b1000; kinds = 3)
        @test ContactCount(:n, Moore(1), 0b100; kinds = 3).mask == 0b100
        @test CorePotts._kind_bit(typemax(UInt64), 64) == 0 && CorePotts._kind_bit(typemax(UInt64), 63) == 1
    end
    @testset "exact after every MCS: $(nameof(typeof(alg)))" for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(cc_problem(), alg; saveat = 1)
        @test sol.stats.lifecycle.divisions >= 3 && sol.stats.lifecycle.transitions >= 1
        @test cc_bad(sol, lat) == 0
        # control: without the lifecycle rebuild the counts go stale at the first event
        noreb = cc_problem()
        bare = PottsProblem(noreb.f, noreb.u0, lat, (0, 30), noreb.p; contact = Moore(1), proposal = Moore(1),
            relations = (; vn = VonNeumann(1)), seed = 7)
        @test cc_bad(solve(bare, alg; saveat = 1), lat) > 0
    end
        @testset "device planner on the CPU backend ($form)" for (form, sites) in (("fused", CheckerboardCPM().fused_lifecycle_max_sites), ("staged", 0))
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        try
                integ = init(cc_problem(), CheckerboardCPM(; fused_lifecycle_max_sites = sites); saveat = 1)
            @test integ.lcache.device isa CorePotts.DeviceLifecycle
            @test (integ.lcache.device.fused! === nothing) == (form == "staged")
            sol = solve!(integ)
            @test sol.stats.lifecycle.divisions >= 3 && sol.stats.lifecycle.transitions >= 1
            @test cc_bad(sol, lat) == 0
            finally
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        end
    end
    @testset "rebuild_trackers! after a host edit" begin
        prob = cc_problem(; lifecycle = false)
        st = deepcopy(prob.u0)
            st.ownership[5:9, 12:16] .= 0                                  # cell 4 removed by hand
        ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
        rebuild_trackers!(st, ctx, CPU())
            @test st.cell.n_med == cc_brute(st.ownership, st.cell.kind, lat, relation(Moore(1), lat), (0,), length(st.cell.kind))
            @test st.cell.n_two == cc_brute(st.ownership, st.cell.kind, lat, relation(VonNeumann(1), lat), (2,), length(st.cell.kind))
    end
end
end

@testitem "normal draws" setup = [CP_contact_counts] tags = [:corepotts, :contact_counts] begin
@testset "normal draws" begin
    key = RNGKey(11)
    z = [CorePotts.normal(Float64, draw(key, 3, e, stream_id("t.normal"))) for e in 1:20_000]
    n = length(z)
    @test abs(sum(z) / n) < 4 / sqrt(n) && abs(var(z) - 1) < 4 * sqrt(2 / n)
    @test abs(count(x -> abs(x) > 1.959964, z) / n - 0.05) < 4 * sqrt(0.05 * 0.95 / n)
    z32 = [CorePotts.normal(Float32, draw(key, 3, e, stream_id("t.normal"))) for e in 1:2000]
    @test eltype(z32) === Float32 && all(isfinite, z32) && abs(sum(z32) / 2000) < 4 / sqrt(2000)
    # bounded: the redraws stay on the address (local index = attempt), the bound holds
    status = zeros(UInt32, 1)
    b = [CorePotts.bounded_normal(Float64, key, 3, e, stream_id("t.b"), 2.0, 1.25, 0.0, status) for e in 1:20_000]
    @test all(>(0), b) && status[1] == 0
    @test abs(sum(b) / length(b) - 2.1467) < 4 * 1.25 / sqrt(length(b))     # N(2, 1.25²) truncated at 0
    @test b[1] == CorePotts.bounded_normal(Float64, key, 3, 1, stream_id("t.b"), 2.0, 1.25, 0.0, nothing)
    # the first attempt is the unbounded draw's value when it is above the bound
    first_ok = findfirst(e -> 2.0 + 1.25 * CorePotts.normal(Float64, draw(key, 3, e, stream_id("t.b"))) > 0, 1:10)
    @test b[first_ok] == 2.0 + 1.25 * CorePotts.normal(Float64, draw(key, 3, first_ok, stream_id("t.b")))
    # exhaustion: NaN and the status bit, no throw
    x = CorePotts.bounded_normal(Float64, key, 3, 1, stream_id("t.b"), 0.0, 1.0, 50.0, status)
    @test isnan(x) && status[1] == CorePotts.STATUS_DRAW_EXHAUSTED
    neg = zeros(UInt32, 1)
    @test isnan(CorePotts.bounded_normal(Float64, key, 3, 1, stream_id("t.b"), 0.0, -1.0, -5.0, neg)) &&
          neg[1] == CorePotts.STATUS_DRAW_NEGATIVE_SD
    @test CorePotts._model_status(nothing, nothing) == 0                       # a model state that is not a NamedTuple
end
end

@testitem "a model status word fails the run" setup = [CP_contact_counts] tags = [:corepotts, :contact_counts] begin
@testset "a model status word fails the run" begin
    lat = Lattice((12, 12))
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    raise(st, p, ctx, key, mcs, c) = (mcs == 2 && (st.model[CorePotts.MODEL_STATUS][1] |= CorePotts.STATUS_DRAW_EXHAUSTED); nothing)
    st = initial_state(σ, Int32[1]; model = NamedTuple{(CorePotts.MODEL_STATUS,)}((zeros(UInt32, 1),)))
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = Phases(; after_mcs = (CellPhase(raise),)))
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = @test_logs (:warn, r"exhausted its 64 attempts") solve(PottsProblem(f, st, lat, (0, 6), gg_params()), alg; saveat = 1)
        @test sol.retcode == ReturnCode.Failure && sol.t[end] == 3
    end
    ok = PottsProblem(CPMFunction(gg_delta_H; temperature = gg_temperature), st, lat, (0, 6), gg_params())
    @test solve(ok, SequentialCPM()).retcode == ReturnCode.Success                    # control
end
end
