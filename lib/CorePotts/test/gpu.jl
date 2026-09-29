# GPU group (opt-in: COREPOTTS_GPU=metal). Trackers stay exact on the device; statistics
# agree with the CPU (D-029: statistical, not bitwise, CPU/GPU agreement).
using Metal

@testset "Metal" begin
    backend = MetalBackend()
    σ, kinds = blocks((64, 64), 6)
    σ = circshift(σ, (3, 3))
    lat = Lattice((64, 64))
    sspec = Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
    cell = merge(init_moments(σ, lat, length(kinds)),
        (; surface = recompute_surface(σ, lat, relation(sspec, lat), length(kinds); T = Float32)))
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
        commit_surface!(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32));
        commit_moments!(st.cell, ctx.lattice, prop))
    function delta_H(st, p, prop, ctx)
        J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - p.V0)^2
        S(s, c) = p.λs * (s - p.S0)^2
        return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               surface_delta(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32), S)
    end
    f = CPMFunction(delta_H; commit!, temperature = gg_temperature)
    p = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
        λs = 0.2f0, S0 = 22.0f0)
    prob = CPMProblem(f, initial_state(σ, kinds; cell), lat, (0, 50), p;
        relations = (; surface = sspec))
    sol = solve(prob, CheckerboardCPM(); backend)
    @test sol.retcode == ReturnCode.Success
    u = sol.u[end]
    @test u.σ != σ
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
    @test u.cell.surface ≈ recompute_surface(u.σ, lat, relation(sspec, lat), length(kinds); T = Float64) rtol = 1e-4
    ref = init_moments(u.σ, lat, length(kinds))
    for c in eachindex(kinds)
        @test all(isapprox.(centroid(u.cell, lat, c), centroid(merge(ref, (; volume = u.cell.volume)), lat, c); atol = 1e-9))
    end

    # statistical parity of an observable, CPU vs Metal checkerboard
    function energy_proxy(u)          # mean |volume − V0|, a fast-relaxing observable
        sum(abs.(u.cell.volume .- 36)) / length(u.cell.volume)
    end
    xs = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:12]
    ys = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 101:112]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 12 + var(ys) / 12)
    @info "CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
    @test abs(t) < 4

    @testset "phases on Metal" begin
        σp, kp = blocks((32, 32), 4)
        latp = Lattice((32, 32))
        u0 = Float32[sin(2π * i / 32) + cos(2π * j / 16) for i in 1:32, j in 1:32]
        st = initial_state(σp, kp; site = (; u = copy(u0), u_next = zero(u0)),
            history = (; u = history_buffer(u0, 2)))
        ph = Phases(after_mcs = (SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next)),
            HistoryPush(:u => (:site, :u))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pp = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 16.0f0, T = 10.0f0, D = 0.05f0)
        prob = CPMProblem(f, st, latp, (0, 5), pp)
        g = solve(prob, CheckerboardCPM(); backend).u[end]
        c = solve(prob, CheckerboardCPM()).u[end]
        @test g.site.u ≈ c.site.u rtol = 1e-5
        @test g.history.u ≈ c.history.u rtol = 1e-5
    end

    @testset "fields on Metal" begin
        σf, kf = blocks((64, 32), 6)
        latf = Lattice((64, 32))
        c0 = Float32[exp(-((i - 20)^2 + (j - 10)^2) / 30) for i in 1:64, j in 1:32]
        pf = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
            D = 0.1f0)
        prob = field_problem(σf, kf, latf, c0, diffuse, pf; dt = 1.0f0, spacing = (1.0f0, 0.8f0),
            tspan = (0, 20))
        g = solve(prob, CheckerboardCPM(); backend).u[end].site.c
        c = solve(prob, CheckerboardCPM()).u[end].site.c
        @test g ≈ c rtol = 1e-4
        @test sum(g) ≈ sum(c0) rtol = 1e-4
    end

    @testset "frozen sites and cell reductions on Metal" begin
        σz, kz = blocks((32, 32), 5; gap = 0)
        latz = Lattice((32, 32))
        frozen = falses(32, 32); frozen[:, 1:2] .= true
        v = Float32[i + j for i in 1:32, j in 1:32]
        n = length(kz)
        st = initial_state(σz, kz; site = (; v), cell = (; vsum = zeros(Float32, n), vmax = zeros(Float32, n)))
        ph = Phases(after_mcs = (
            CellReduce((:cell, :vsum), (st, p, ctx, key, mcs, i) -> st.site.v[i]),
            CellReduce((:cell, :vmax), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max)))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pz = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 20.0f0)
        u = solve(CPMProblem(f, st, latz, (0, 10), pz; frozen), CheckerboardCPM(); backend).u[end]
        @test u.σ[frozen] == σz[frozen]
        for c in 1:n
            owned = findall(==(c), u.σ)
            isempty(owned) && continue
            @test u.cell.vsum[c] ≈ sum(v[owned]) rtol = 1e-5
            @test u.cell.vmax[c] == maximum(v[owned])
        end
    end

    @testset "division on Metal" begin
        latd = Lattice((48, 48))
        σd = zeros(Int32, 48, 48); σd[20:27, 20:27] .= 1
        grow!(st, p, ctx, key, mcs, c) = (@inbounds st.cell.target[c] += 1.0f0; nothing)
        big(st, p, ctx, key, mcs, c) = st.cell.volume[c] >= 80 ? EVENT_DIVIDE : EVENT_NONE
        reset!(st, p, ctx, key, mcs, parent, daughter) =
            (st.cell.target[parent] = 40.0f0; st.cell.target[daughter] = 40.0f0; nothing)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - @inbounds(st.cell.target[c]))^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
        end
        commitD!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        st = with_capacity(initial_state(σd, [1]; cell = merge(init_moments(σd, latd, 1), (; target = Float32[64]))), 64)
        f = CPMFunction(dH; commit! = commitD!, temperature = gg_temperature,
            phases = Phases(before_mcs = (CellPhase(grow!),)),
            lifecycle = Lifecycle(big; divide! = reset!, normal = AlongMinorAxis{Float32}()))
        pd = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, T = 10.0f0)
        sol = solve(CPMProblem(f, st, latd, (0, 120), pd), CheckerboardCPM(); backend)
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions >= 3
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:64]
        ref = init_moments(u.σ, latd, 64)
        for c in findall(>(0), u.cell.volume)
            @test all(isapprox.(centroid(u.cell, latd, c), centroid(merge(ref, (; volume = u.cell.volume)), latd, c); atol = 1e-9))
        end
    end

    @testset "Act, chemotaxis, connectivity and bias on Metal" begin
        latA = Lattice((64, 64))
        σA, kA = blocks((64, 64), 6; gap = 2)
        nA = length(kA)
        grad = Float32[i / 64 for i in 1:64, j in 1:64]
        function dHA(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            act = act_delta(st.site.act, st.σ, ctx, prop, p.λact, p.maxact)
            chem = is_extension(prop) ? chemotaxis_delta(st.site.c, prop, p.χ) : 0.0f0
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) + act + chem
        end
        commitA!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            @inbounds st.site.act[prop.target] = prop.new == 0 ? 0.0f0 : p.maxact; nothing)
        decay!(st, p, ctx, key, mcs, i) = (@inbounds st.site.act[i] = max(st.site.act[i] - 1.0f0, 0.0f0); nothing)
        okA(st, p, prop, ctx) = locally_connected(st.σ, ctx, prop) && forbid_extinction(st.cell.volume, prop)
        biasA(st, p, prop, ctx) = is_extension(prop) ? 0.05f0 : 0.0f0
        fA = CPMFunction(dHA; commit! = commitA!, temperature = gg_temperature, constraint = okA,
            bias = biasA, phases = Phases(after_mcs = (SitePhase(decay!),)))
        pA = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
            λact = 30.0f0, maxact = 20.0f0, χ = 200.0f0)
        stA = initial_state(σA, kA; site = (; act = zeros(Float32, 64, 64), c = grad))
        probA = CPMProblem(fA, stA, latA, (0, 60), pA; contact = Moore(1), relations = (; act = Moore(1)))
        uA = solve(probA, CheckerboardCPM(); backend).u[end]
        @test uA.cell.volume == [count(==(c), uA.σ) for c in 1:nA]
        @test all(c -> components(uA.σ, latA, c) == 1, 1:nA)
        @test all(>(0), uA.cell.volume)
        @test any(>(0), uA.site.act)
        # chemotaxis moves mass up the gradient; CPU and Metal agree on how far
        drift(u) = sum(i -> u.σ[i] != 0 ? grad[i] : 0.0f0, eachindex(u.σ)) / count(!=(0), u.σ)
        d0 = drift(stA)
        xs = [drift(solve(remake(probA; seed), CheckerboardCPM(); save_start = false).u[end]) - d0 for seed in 1:8]
        ys = [drift(solve(remake(probA; seed), CheckerboardCPM(); backend, save_start = false).u[end]) - d0 for seed in 101:108]
        @test mean(xs) > 0 && mean(ys) > 0
        t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8)
        @info "Act/chemotaxis drift CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
        @test abs(t) < 4
    end

    @testset "Merks connectivity and Barker on Metal" begin
        σM, kM = blocks((48, 48), 5; gap = 1)
        latM = Lattice((48, 48))
        okM(st, p, prop, ctx) = merks_connectivity(st.σ, ctx, prop)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = okM)
        pM = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 12.0f0)
        prob = CPMProblem(f, initial_state(σM, kM), latM, (0, 40), pM; contact = Moore(1))
        u = solve(prob, CheckerboardCPM(acceptance = Barker()); backend).u[end]
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kM)]
        @test u.σ != σM
        xs = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); save_start = false).u[end].cell.volume) for seed in 1:8]
        ys = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); backend, save_start = false).u[end].cell.volume) for seed in 101:108]
        t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8 + eps())
        @test abs(t) < 4
    end

    @testset "3D second-order neighbourhood with surface on Metal" begin
        lat3 = Lattice((24, 24, 24))
        σ3, k3 = blocks((24, 24, 24), 5; gap = 1)
        n3 = length(k3)
        sspec = NeighborOrder(2)
        cell = merge(init_moments(σ3, lat3, n3),
            (; surface = recompute_surface(σ3, lat3, relation(sspec, lat3), n3; T = Float32)))
        commit3!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            commit_surface!(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32));
            commit_moments!(st.cell, ctx.lattice, prop))
        function dH3(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(s, c) = p.λs * (s - p.S0)^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   surface_delta(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32), S)
        end
        f = CPMFunction(dH3; commit! = commit3!, temperature = gg_temperature)
        p3 = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 125.0f0, T = 10.0f0,
            λs = 0.01f0, S0 = 200.0f0)
        prob = CPMProblem(f, initial_state(σ3, k3; cell), lat3, (0, 15), p3;
            contact = NeighborOrder(2), relations = (; surface = sspec))
        u = solve(prob, CheckerboardCPM(); backend).u[end]
        @test u.σ != σ3
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:n3]
        @test u.cell.surface ≈ recompute_surface(u.σ, lat3, relation(sspec, lat3), n3; T = Float64) rtol = 1e-4
        ref = merge(init_moments(u.σ, lat3, n3), (; volume = u.cell.volume))
        @test all(c -> all(isapprox.(centroid(u.cell, lat3, c), centroid(ref, lat3, c); atol = 1e-9)), 1:n3)
    end

    @testset "links, host rules and the contact table on Metal" begin
        latL = Lattice((60, 30))
        σL = zeros(Int32, 60, 30); σL[5:10, 12:17] .= 1; σL[40:45, 12:17] .= 2
        cellL = merge(init_moments(σL, latL, 2), empty_links(1, 2; rest = Float32))
        add_link!(cellL, 1, 2; rest = 12.0f0)
        function dHL(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitL!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        f = CPMFunction(dHL; commit! = commitL!, temperature = gg_temperature,
            claims = (st, p, prop, ctx) -> link_claims(st.cell, prop, Val(1)))
        pL = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = 2.0f0)
        ds = map(1:4) do seed
            u = solve(CPMProblem(f, initial_state(σL, [1, 1]; cell = cellL), latL, (0, 1000), pL; seed),
                CheckerboardCPM(); backend).u[end]
            centroid_distance(Float64, u.cell, latL, 1, 2)
        end
        @test abs(mean(ds) - 12.0) < 2.5

        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        n = length(kinds)
        vn = relation(VonNeumann(1), lat)
        function link_touching!(cell, st, p, ctx, mcs)
            g = contact_graph(st.σ, ctx.lattice, vn, length(cell.kind))
            for a in eachindex(cell.kind), b in neighbors(g, a)
                a < b && add_link!(cell, a, b; age = Int32(mcs))
            end
        end
        st = initial_state(σ, kinds; cell = merge(empty_links(8, n; age = Int32), empty_contacts(8, n)))
        fH = CPMFunction(gg_delta_H; temperature = gg_temperature,
            phases = Phases(after_mcs = (HostPhase(link_touching!; every = 100), ContactPhase())))
        pH = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 10.0f0)
        u = solve(CPMProblem(fH, st, lat, (0, 3), pH; contact = VonNeumann(1)), CheckerboardCPM(); backend).u[end]
        g0 = contact_graph(σ, lat, vn, n)
        @test all(a -> all(b -> linked(u.cell, a, b), neighbors(g0, a)), 1:n)
        g = contact_graph(u.σ, lat, vn, n)
        @test all(iszero, u.cell.contact_overflow)
        for a in 1:n
            @test sort(filter(!=(0), u.cell.contact_nbr[:, a])) == collect(neighbors(g, a))
            @test all(b -> contact_measure(u.cell, a, b) == contact(g, a, b), neighbors(g, a))
        end
    end

    @testset "checkpoint continuation on Metal" begin
        σc, kc = blocks((48, 48), 6)
        latc = Lattice((48, 48))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, fingerprint = 0x7)
        pc = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0)
        prob = CPMProblem(f, initial_state(σc, kc), latc, (0, 20), pc; seed = 3)
        whole = solve(prob, CheckerboardCPM(); backend).u[end]
        again = solve(prob, CheckerboardCPM(); backend).u[end]
        @test whole.σ == again.σ                        # the device run is reproducible
        integ = init(prob, CheckerboardCPM(); backend)
        for _ in 1:8
            step!(integ)
        end
        ck = checkpoint(integ)
        rest = solve!(init(prob, CheckerboardCPM(); backend, checkpoint = ck)).u[end]
        @test rest.σ == whole.σ
        @test rest.cell.volume == whole.cell.volume
    end
end
