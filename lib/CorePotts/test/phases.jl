# Synchronous phases, state validation, history and accepted-copy affects (ROADMAP M2.3).

# Jacobi step of u on the periodic lattice into u_next (bulk-synchronous: reads only u).
function jacobi!(st, p, ctx, key, mcs, i)
    lat = ctx.lattice
    x = coordinates(lat, i)
    acc = zero(eltype(st.site.u))
    for off in ctx.contact.offsets
        _, y = shift(lat, x, off)
        acc += @inbounds st.site.u[linear_index(lat, y)]
    end
    @inbounds st.site.u_next[i] = st.site.u[i] + p.D * (acc - length(ctx.contact) * st.site.u[i])
    return nothing
end
function host_jacobi(u, lat, rel, D)
    v = similar(u)
    for i in 1:nsites(lat)
        x = coordinates(lat, i)
        acc = 0.0
        for off in rel.offsets
            acc += u[linear_index(lat, shift(lat, x, off)[2])]
        end
        v[i] = u[i] + D * (acc - length(rel) * u[i])
    end
    return v
end

@testset "phases" begin
    σ, kinds = blocks((24, 24), 4)
    lat = Lattice((24, 24))

    @testset "state validation" begin
        @test_throws ArgumentError initial_state(σ, kinds; site = (; u = zeros(3, 3)))
        @test_throws ArgumentError initial_state(σ, kinds; cell = (; a = zeros(2)))
        @test_throws ArgumentError initial_state(σ, kinds; model = (; m = 1.0))
        @test initial_state(σ, kinds; cell = (; M = zeros(2, length(kinds)))) isa CPMState
    end

    @testset "bulk-synchronous site update matches host ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        u0 = [sin(2π * i / 24) + cos(2π * j / 12) for i in 1:24, j in 1:24]
        st = initial_state(σ, kinds; site = (; u = copy(u0), u_next = zero(u0)))
        ph = Phases(after_mcs = (SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        p = merge(gg_params(), (; D = 0.05))
        sol = solve(PottsProblem(f, st, lat, (0, 6), p), alg)
        ref = u0
        for _ in 1:6
            ref = host_jacobi(ref, lat, relation(Moore(1), lat), 0.05)
        end
        @test sol.u[end].site.u == ref                     # same arithmetic order: exact
        @test sol.stats.launches >= 12
    end

    @testset "randomness in phases is address-keyed" begin
        const_stream = CorePotts.stream_id("test.noise")
        noise!(st, p, ctx, key, mcs, i) =
            (@inbounds st.site.u[i] = CorePotts.uniform(Float64, CorePotts.draw(key, mcs, i, const_stream)[1]); nothing)
        st = initial_state(σ, kinds; site = (; u = zeros(24, 24)))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature,
            phases = Phases(after_mcs = (SitePhase(noise!),)))
        prob = PottsProblem(f, st, lat, (0, 3), gg_params(); seed = 11)
        u = solve(prob, CheckerboardCPM()).u[end].site.u
        key = CorePotts.RNGKey(11)
        @test vec(u) == [CorePotts.uniform(Float64, CorePotts.draw(key, 2, i, const_stream)[1]) for i in 1:nsites(lat)]
    end

    @testset "cell phase drives growth" begin
        grow!(st, p, ctx, key, mcs, c) = (@inbounds st.cell.target[c] += p.rate; nothing)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - @inbounds(st.cell.target[c]))^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
        end
        st = initial_state(σ, kinds; cell = (; target = fill(16.0, length(kinds))))
        f = CPMFunction(dH; temperature = gg_temperature,
            phases = Phases(before_mcs = (CellPhase(grow!),)))
        u = solve(PottsProblem(f, st, lat, (0, 20), merge(gg_params(), (; rate = 0.5))),
            CheckerboardCPM()).u[end]
        @test all(u.cell.target .== 26.0)
        @test sum(u.cell.volume) / length(kinds) > 20
    end

    @testset "history ring buffer" begin
        stamp!(st, p, ctx, key, mcs, i) = (@inbounds st.site.u[i] = mcs; nothing)
        u0 = zeros(24, 24)
        st = initial_state(σ, kinds; site = (; u = u0), history = (; u = history_buffer(u0, 3)))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = Phases(
            after_mcs = (SitePhase(stamp!), HistoryPush(:u => (:site, :u)))))
        h = solve(PottsProblem(f, st, lat, (0, 7), gg_params()), SequentialCPM()).u[end].history.u
        last_mcs = 6                                        # MCS 0…6 ran
        for lag in 0:2
            @test all(h[:, :, history_slot(3, last_mcs, lag)] .== last_mcs - lag)
        end
    end

    @testset "accepted-copy affect: clear on ownership change" begin
        age!(st, p, ctx, key, mcs, i) = (@inbounds st.site.age[i] += 1; nothing)
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            clear_on_copy!(st.site.age, prop, 0);
            @inbounds(st.site.copies[prop.target] += 1); nothing)
        st = initial_state(σ, kinds; site = (; age = zeros(Int32, 24, 24), copies = zeros(Int32, 24, 24)))
        f = CPMFunction(gg_delta_H; commit!, temperature = gg_temperature,
            phases = Phases(after_mcs = (SitePhase(age!),)))
        sol = solve(PottsProblem(f, st, lat, (0, 8), gg_params()), SequentialCPM();
            saveat = 0:8)
        u = sol.u[end]
        a, n = u.site.age, u.site.copies
        @test any(n .> 0) && any(n .== 0)
        @test all(a[n .== 0] .== 8)                        # never copied: aged every MCS
        @test all(1 .<= a[n .> 0] .<= 8)                   # cleared in a sweep, aged after it
        changed_last = sol.u[end - 1].σ .!= u.σ
        @test any(changed_last) && all(a[changed_last] .== 1)
    end
end

# P6.3b (D-145): the MCS order is one static tuple with the sweep and the lifecycle as
# entries; a field step may carry a masked clamp.
@testset "MCS order and field clamps" begin
    σ, kinds = blocks((24, 24), 4)
    lat = Lattice((24, 24))
    @test Phases().mcs == ((), SweepPhase(), (), LifecyclePhase(), ())
    ph = Phases(after_mcs = (CopyPhase((:site, :u) => (:site, :v)),))
    @test ph.mcs == ((), SweepPhase(), ph.after_mcs, LifecyclePhase(), ())
    @test Phases((), ph.after_mcs, (), ()).mcs == ph.mcs
    @test_throws ArgumentError Phases(; mcs = ((), LifecyclePhase()))                     # no sweep
    @test_throws ArgumentError Phases(; mcs = (SweepPhase(), SweepPhase(), LifecyclePhase()))
    @test_throws ArgumentError Phases(; mcs = (SweepPhase(), LifecyclePhase(), CopyPhase((:site, :u) => (:site, :v))))

    # the same phase after the sweep (default) or before it (an explicit order)
    age!(st, p, ctx, key, mcs, i) = (@inbounds st.site.age[i] += 1; nothing)
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); clear_on_copy!(st.site.age, prop, 0); nothing)
    aged = (SitePhase(age!),)
    for (phases, fresh) in ((Phases(after_mcs = aged), 1),
            (Phases(; before_mcs = aged, mcs = (aged, SweepPhase(), (), LifecyclePhase(), ())), 0))
        st = initial_state(σ, kinds; site = (; age = zeros(Int32, 24, 24)))
        f = CPMFunction(gg_delta_H; commit!, temperature = gg_temperature, phases)
        sol = solve(PottsProblem(f, st, lat, (0, 8), gg_params()), SequentialCPM(); saveat = 0:8)
        changed = sol.u[end - 1].σ .!= sol.u[end].σ
        @test any(changed) && all(sol.u[end].site.age[changed] .== fresh)
    end

    # a clamp after every substep's write, and on the initial state (`FieldClamp`)
    one_rate(st, p, ctx, key, mcs, i, c) = 1.0
    zero_low(st, p, ctx, key, mcs, i, v) = i <= 24 ? zero(v) : v          # the first column
    for alg in (SequentialCPM(), CheckerboardCPM())
        st = initial_state(σ, kinds; site = (; c = fill(5.0, 24, 24), c_next = zeros(24, 24)))
        step = FieldStep((:site, :c) => (:site, :c_next), one_rate; substeps = 4, clamp = zero_low)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature,
            phases = Phases(; after_mcs = (step,), at_init = (FieldClamp((:site, :c), zero_low),)))
        sol = solve(PottsProblem(f, st, lat, (0, 3), gg_params()), alg; saveat = 1)
        @test all(u -> all(==(0.0), u.site.c[:, 1]), sol.u)                       # the initial state too
        @test all(==(8.0), sol.u[end].site.c[:, 2:end])
        @test sol.stats.launches >= 3 * 2 * 4
    end
end

# P6.0v (D-085): the counted transfer helpers. On host arrays they copy as before and count
# nothing; the counters add under `merge` and survive `_restore_stats!` (checkpoints).
@testset "transfer counters: host arrays count nothing; merge and restore" begin
    s = CorePotts.PottsStats()
    h = Int32[1, 2, 3]
    g = CorePotts._to_host(s, h)
    @test g == h && g !== h                                   # a copy, as `Array(a)`
    @test CorePotts._copy!(s, zeros(Int32, 3), h) == h
    @test CorePotts._readback(s, h) == 1
    st = initial_state(Int32[1 0; 0 2], Int32[1, 1])
    snap = CorePotts._snapshot(s, CorePotts.CPU(), st)
    @test snap.σ == st.σ && snap.σ !== st.σ                   # independent (deepcopy)
    @test CorePotts._adapt_host(s, (; a = h)).a === h         # host leaves kept, as `adapt(Array, …)`
    CorePotts._sync!(s, CorePotts.CPU())
    @test (s.syncs, s.transfers, s.transfer_bytes) == (0, 0, 0)
    # the one counter (what a device copy calls)
    CorePotts._count_transfer!(s, 1, 2, 12)
    @test (s.syncs, s.transfers, s.transfer_bytes) == (1, 2, 12)
    CorePotts._count_transfer!(nothing, 1, 1, 4)              # outside an integrator: no-op
    m = merge(s, CorePotts.PottsStats(; syncs = 2, transfers = 3, transfer_bytes = 5))
    @test (m.syncs, m.transfers, m.transfer_bytes) == (3, 5, 17)
    r = CorePotts._restore_stats!(CorePotts.PottsStats(), m)
    @test (r.syncs, r.transfers, r.transfer_bytes) == (3, 5, 17)
end
