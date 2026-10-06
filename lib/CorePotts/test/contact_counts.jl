# Contact counts with a kind predicate (D-150 G1, `src/contact_counts.jl`) and the normal
# draws (`normal`, `bounded_normal`, the model status word): ordinary tests (D-048) against
# a brute-force count from σ, on both algorithms and every lifecycle planner.

# brute force: per cell, the pairs (s, s′) over `offs` with σ(s′) ≠ σ(s) and the partner's
# kind (0 for the medium) in `kinds`
function cc_brute(σ, kind, lat, rel, kinds, n)
    out = zeros(Int32, n)
    for i in 1:nsites(lat)
        c = σ[i]
        c == 0 && continue
        x = coordinates(lat, i)
        for o in rel.offsets
            inside, y = shift(lat, x, o)
            inside || continue
            q = σ[linear_index(lat, y)]
            q == c && continue
            (q == 0 ? 0 : kind[q]) in kinds && (out[c] += 1)
        end
    end
    return out
end

const CC_MED = UInt64(0b001)          # partner is the medium
const CC_TWO = UInt64(0b100)          # partner is of kind 2
function cc_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx.lattice, prop)
    commit_contact_count!(st.cell.n_med, st.σ, st.cell.kind, ctx.contact, CC_MED, ctx.lattice, prop)
    commit_contact_count!(st.cell.n_two, st.σ, st.cell.kind, ctx.vn, CC_TWO, ctx.lattice, prop)
    return nothing
end
# divisions of large cells every other MCS, and cell 1 changes kind at MCS 4
cc_trigger(st, p, ctx, key, mcs, c) = mcs == 4 && c == 1 ? EVENT_TRANSITION :
                                      (iseven(mcs) && st.cell.volume[c] >= 28) ? EVENT_DIVIDE : EVENT_NONE
cc_kind(st, p, ctx, key, mcs, c) = Int32(3 - st.cell.kind[c])

function cc_problem(; lifecycle = true)
    lat = Lattice((30, 24); boundary = (Periodic(), Closed()))
    σ = zeros(Int32, 30, 24)
    blocks = ((vcat(29:30, 1:3), 1:5), (8:12, 1:5), (13:17, 2:6), (5:9, 12:16), (20:24, 18:22))
    for (c, (xs, ys)) in enumerate(blocks)
        σ[xs, ys] .= c
    end
    kinds = Int32[1, 2, 1, 2, 1]
    cell = merge(init_moments(σ, lat, 5),
        (; n_med = recompute_contact_count(σ, kinds, lat, Moore(1), CC_MED, 5),
            n_two = recompute_contact_count(σ, kinds, lat, VonNeumann(1), CC_TWO, 5)))
    st = with_capacity(initial_state(σ, kinds; cell), 32)
    cc = ContactCounts((ContactCount(:n_med, Moore(1), CC_MED), ContactCount(:n_two, VonNeumann(1), CC_TWO)))
    f = CPMFunction(gg_delta_H; commit! = cc_commit!, temperature = gg_temperature,
        lifecycle = lifecycle ? Lifecycle(cc_trigger; kind = cc_kind, normal = random_plane) : nothing)
    p = merge(gg_params(), (; V0 = 36.0, T = 8.0))
    return PottsProblem(f, st, lat, (0, 30), p; contact = Moore(1), proposal = Moore(1),
        relations = (; vn = VonNeumann(1), contact_counts = cc), seed = 7)
end

function cc_bad(sol, lat)
    bad = 0
    for u in sol.u
        m = cc_brute(u.σ, u.cell.kind, lat, relation(Moore(1), lat), (0,), length(u.cell.kind))
        t = cc_brute(u.σ, u.cell.kind, lat, relation(VonNeumann(1), lat), (2,), length(u.cell.kind))
        bad += (u.cell.n_med != m) + (u.cell.n_two != t)
    end
    return bad
end

@testset "contact counts" begin
    lat = Lattice((30, 24); boundary = (Periodic(), Closed()))
    @testset "recompute equals the unweighted surface for every kind" begin
        prob = cc_problem()
        st = prob.u0
        all3 = recompute_contact_count(st.σ, st.cell.kind, lat, Moore(1), 0b111, length(st.cell.kind))
        @test all3 == recompute_surface(st.σ, lat, relation(Moore(1), lat), length(st.cell.kind); T = Int32)
        @test st.cell.n_med != all3[1:end] && any(>(0), st.cell.n_two)          # the masks select
        @test CorePotts.radius(CorePotts.relation(prob.relations.contact_counts, lat)) == 1
        # masks hold kinds 0–63: more kinds, or a mask beyond the model's kinds, are errors (review F5)
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
    @testset "device planner on the CPU backend ($form)" for (form, sites) in (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
        fuse = CorePotts.FUSE_SITES[]
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        CorePotts.FUSE_SITES[] = sites
        try
            integ = init(cc_problem(), CheckerboardCPM(); saveat = 1)
            @test integ.lcache.device isa CorePotts.DeviceLifecycle
            @test (integ.lcache.device.fused! === nothing) == (form == "staged")
            sol = solve!(integ)
            @test sol.stats.lifecycle.divisions >= 3 && sol.stats.lifecycle.transitions >= 1
            @test cc_bad(sol, lat) == 0
        finally
            CorePotts.FUSE_SITES[] = fuse
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        end
    end
    @testset "rebuild_trackers! after a host edit" begin
        prob = cc_problem(; lifecycle = false)
        st = deepcopy(prob.u0)
        st.σ[5:9, 12:16] .= 0                                  # cell 4 removed by hand
        ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
        rebuild_trackers!(st, ctx, CPU())
        @test st.cell.n_med == cc_brute(st.σ, st.cell.kind, lat, relation(Moore(1), lat), (0,), length(st.cell.kind))
        @test st.cell.n_two == cc_brute(st.σ, st.cell.kind, lat, relation(VonNeumann(1), lat), (2,), length(st.cell.kind))
    end
end

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
