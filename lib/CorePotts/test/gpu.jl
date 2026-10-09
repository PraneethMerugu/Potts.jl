# GPU group (opt-in: COREPOTTS_GPU or POTTS_GPU = metal | rocm; the backend comes from
# test/shared/devices.jl, D-157). Trackers stay exact on the device; statistics
# agree with the CPU (D-029: statistical, not bitwise, CPU/GPU agreement).

@testset "device ($(PottsDevices.device_name()))" begin
    backend = PottsDevices.device_backend()
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
    prob = PottsProblem(f, initial_state(σ, kinds; cell), lat, (0, 50), p;
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

    # statistical parity of an observable, CPU vs device checkerboard
    function energy_proxy(u)          # mean |volume − V0|, a fast-relaxing observable
        sum(abs.(u.cell.volume .- 36)) / length(u.cell.volume)
    end
    xs = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:12]
    ys = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 101:112]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 12 + var(ys) / 12)
    @info "CPU vs device" cpu = mean(xs) device = mean(ys) t
    @test abs(t) < 4

    @testset "phases on the device" begin
        σp, kp = blocks((32, 32), 4)
        latp = Lattice((32, 32))
        u0 = Float32[sin(2π * i / 32) + cos(2π * j / 16) for i in 1:32, j in 1:32]
        st = initial_state(σp, kp; site = (; u = copy(u0), u_next = zero(u0)),
            history = (; u = history_buffer(u0, 2)))
        ph = Phases(after_mcs = (SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next)),
            HistoryPush(:u => (:site, :u))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pp = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 16.0f0, T = 10.0f0, D = 0.05f0)
        prob = PottsProblem(f, st, latp, (0, 5), pp)
        g = solve(prob, CheckerboardCPM(); backend).u[end]
        c = solve(prob, CheckerboardCPM()).u[end]
        @test g.site.u ≈ c.site.u rtol = 1e-5
        @test g.history.u ≈ c.history.u rtol = 1e-5
    end

    @testset "fields on the device" begin
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

    @testset "frozen sites and cell reductions on the device" begin
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
        u = solve(PottsProblem(f, st, latz, (0, 10), pz; frozen), CheckerboardCPM(); backend).u[end]
        @test u.σ[frozen] == σz[frozen]
        for c in 1:n
            owned = findall(==(c), u.σ)
            isempty(owned) && continue
            @test u.cell.vsum[c] ≈ sum(v[owned]) rtol = 1e-5
            @test u.cell.vmax[c] == maximum(v[owned])
        end
    end

    @testset "division on the device" begin
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
        sol = solve(PottsProblem(f, st, latd, (0, 120), pd), CheckerboardCPM(); backend)
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions >= 3
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:64]
        ref = init_moments(u.σ, latd, 64)
        for c in findall(>(0), u.cell.volume)
            @test all(isapprox.(centroid(u.cell, latd, c), centroid(merge(ref, (; volume = u.cell.volume)), latd, c); atol = 1e-9))
        end
    end

    @testset "Act, chemotaxis, connectivity and bias on the device" begin
        latA = Lattice((64, 64))
        σA, kA = blocks((64, 64), 6; gap = 2)
        nA = length(kA)
        grad = Float32[i / 64 for i in 1:64, j in 1:64]
        function dHA(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            m(site, owner) = neighborhood_mean(st.site.act, st.σ, ctx, site, owner; relation = ctx.act)
            act = -(p.λact / p.maxact) * (m(prop.source, prop.new) - m(prop.target, prop.old))
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
        probA = PottsProblem(fA, stA, latA, (0, 60), pA; contact = Moore(1), relations = (; act = Moore(1)))
        uA = solve(probA, CheckerboardCPM(); backend).u[end]
        @test uA.cell.volume == [count(==(c), uA.σ) for c in 1:nA]
        @test all(c -> components(uA.σ, latA, c) == 1, 1:nA)
        @test all(>(0), uA.cell.volume)
        @test any(>(0), uA.site.act)
        # chemotaxis moves mass up the gradient; CPU and the device agree on how far
        drift(u) = sum(i -> u.σ[i] != 0 ? grad[i] : 0.0f0, eachindex(u.σ)) / count(!=(0), u.σ)
        d0 = drift(stA)
        xs = [drift(solve(remake(probA; seed), CheckerboardCPM(); save_start = false).u[end]) - d0 for seed in 1:8]
        ys = [drift(solve(remake(probA; seed), CheckerboardCPM(); backend, save_start = false).u[end]) - d0 for seed in 101:108]
        @test mean(xs) > 0 && mean(ys) > 0
        t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8)
        @info "Act/chemotaxis drift CPU vs device" cpu = mean(xs) device = mean(ys) t
        @test abs(t) < 4
    end

    @testset "ring connectivity rule and Barker on the device" begin
        σM, kM = blocks((48, 48), 5; gap = 1)
        latM = Lattice((48, 48))
        okM(st, p, prop, ctx) = ring_arcs(st.σ, ctx, prop) <= 1 ||
            (ring_cells(st.σ, ctx, prop) == 2 && ring_medium(st.σ, ctx, prop) == 0)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = okM)
        pM = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 12.0f0)
        prob = PottsProblem(f, initial_state(σM, kM), latM, (0, 40), pM; contact = Moore(1))
        u = solve(prob, CheckerboardCPM(acceptance = Barker()); backend).u[end]
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kM)]
        @test u.σ != σM
        xs = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); save_start = false).u[end].cell.volume) for seed in 1:8]
        ys = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); backend, save_start = false).u[end].cell.volume) for seed in 101:108]
        t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8 + eps())
        @test abs(t) < 4
    end

    @testset "3D second-order neighbourhood with surface on the device" begin
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
        prob = PottsProblem(f, initial_state(σ3, k3; cell), lat3, (0, 15), p3;
            contact = NeighborOrder(2), relations = (; surface = sspec))
        u = solve(prob, CheckerboardCPM(); backend).u[end]
        @test u.σ != σ3
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:n3]
        @test u.cell.surface ≈ recompute_surface(u.σ, lat3, relation(sspec, lat3), n3; T = Float64) rtol = 1e-4
        ref = merge(init_moments(u.σ, lat3, n3), (; volume = u.cell.volume))
        @test all(c -> all(isapprox.(centroid(u.cell, lat3, c), centroid(ref, lat3, c); atol = 1e-9)), 1:n3)
    end

    @testset "links, host rules and the contact table on the device" begin
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
            u = solve(PottsProblem(f, initial_state(σL, [1, 1]; cell = cellL), latL, (0, 1000), pL; seed),
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
        u = solve(PottsProblem(fH, st, lat, (0, 3), pH; contact = VonNeumann(1)), CheckerboardCPM(); backend).u[end]
        g0 = contact_graph(σ, lat, vn, n)
        @test all(a -> all(b -> linked(u.cell, a, b), neighbors(g0, a)), 1:n)
        g = contact_graph(u.σ, lat, vn, n)
        @test all(iszero, u.cell.contact_overflow)
        for a in 1:n
            @test sort(filter(!=(0), u.cell.contact_nbr[:, a])) == collect(neighbors(g, a))
            @test all(b -> contact_measure(u.cell, a, b) == contact(g, a, b), neighbors(g, a))
        end
    end

    @testset "link_delta skips a dead partner on the device (P6.0l)" begin
        # the spring of the previous testset, plus cell 3: linked to cell 1 but owning no
        # site (copy-killed, volume 0, centroid 0/0). The kernel skips it: ΔH stays finite.
        latD = Lattice((60, 30))
        σD = zeros(Int32, 60, 30); σD[5:10, 12:17] .= 1; σD[40:45, 12:17] .= 2
        cellD = merge(init_moments(σD, latD, 3), empty_links(2, 3; rest = Float32))
        add_link!(cellD, 1, 2; rest = 12.0f0); add_link!(cellD, 1, 3; rest = 3.0f0)
        function dHD(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitD!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        f = CPMFunction(dHD; commit! = commitD!, temperature = gg_temperature,
            claims = (st, p, prop, ctx) -> link_claims(st.cell, prop, Val(2)))
        pD = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = 2.0f0)
        st0 = initial_state(σD, [1, 1, 1]; cell = cellD)
        @test st0.cell.volume[3] == 0
        ds = map(1:4) do seed
            sol = solve(PottsProblem(f, st0, latD, (0, 1000), pD; seed), CheckerboardCPM(); backend)
            @test sol.retcode == ReturnCode.Success                 # a NaN ΔH would fail the run
            u = sol.u[end]
            @test u.σ != σD && u.cell.volume[3] == 0
            @test linked(u.cell, 1, 3)                              # no boundary here: the skip suffices
            centroid_distance(Float64, u.cell, latD, 1, 2)
        end
        @test abs(mean(ds) - 12.0) < 2.5                            # the live spring still acts
    end

    @testset "a killing copy removes the dying cell's links on the device (P6.0r)" begin
        # cell 2 owns one site, 22.5 from blob 1's centroid, on a spring of rest 3 and
        # stiffness 1 (≈ 380 stretched). Dying costs it +λd = 50 (E = λd·v(v − 2)), growing
        # +50, and medium contacts with it are free: at T = 1 only the killing copy, whose
        # ΔH drops the spring (≈ 50 − 380), is ever accepted (D-083).
        latK = Lattice((60, 30))
        σK = zeros(Int32, 60, 30); σK[4:9, 12:17] .= 1; σK[29, 15] = 2
        function dHK(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = @inbounds(st.cell.kind[c]) == 2 ? p.λd * v * (v - 2) : p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitK!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        f = CPMFunction(dHK; commit! = commitK!, temperature = gg_temperature,
            claims = (st, p, prop, ctx) -> link_claims(st.cell, prop, Val(1)))
        pK = (; J = SMatrix{3, 3, Float32}(0, 16, 0, 16, 2, 16, 0, 16, 2), λ = 1.0f0, V0 = 36.0f0, λd = 50.0f0,
            T = 1.0f0, k = 1.0f0)
        st(linkit) = (cell = merge(init_moments(σK, latK, 2), empty_links(1, 2; rest = Float32));
            linkit && add_link!(cell, 1, 2; rest = 3.0f0); initial_state(σK, [1, 2]; cell))
        p0 = PottsProblem(f, st(true), latK, (0, 20), pK)
        li = LinearIndices(σK)
        props = [Proposal(li[29, 15 + j], li[29, 15], (29, 15 + j), 1, Int32(0), Int32(2)) for j in (-1, 1)]
        kill = Proposal(li[29, 15], li[30, 15], (29, 15), 1, Int32(2), Int32(0))
        ctxK = (; lattice = latK, contact = p0.contact)
        @test dHK(p0.u0, pK, kill, ctxK) < -40                       # the spring leaves with the cell
        @test all(q -> dHK(p0.u0, pK, q, ctxK) > 30, props)          # growth never pays
        for seed in 1:3
            sol = solve(remake(p0; seed), CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1)
            @test sol.retcode == ReturnCode.Success
            @test sol.u[1].cell.volume[2] == 1 && sol.u[end].cell.volume[2] == 0
            @test all(u -> u.cell.volume[1] > 0, sol.u)
        end
        # negative control: unlinked, the cell is never killed
        free = PottsProblem(f, st(false), latK, (0, 20), pK; seed = 1)
        @test all(u -> u.cell.volume[2] == 1, solve(free, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1).u)
    end

    @testset "checkpoint continuation on the device" begin
        σc, kc = blocks((48, 48), 6)
        latc = Lattice((48, 48))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, fingerprint = 0x7)
        pc = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0)
        prob = PottsProblem(f, initial_state(σc, kc), latc, (0, 20), pc; seed = 3)
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

    @testset "transfer counters (D-085): exact counts of the helpers on the device" begin
        stats = CorePotts.PottsStats()
        counts() = (stats.syncs, stats.transfers, stats.transfer_bytes)
        d = PottsDevices.device_array(Float32[1, 2, 3, 4]); d2 = PottsDevices.device_array(zeros(Float32, 4))
        CorePotts._sync!(stats, backend)
        @test counts() == (1, 0, 0)
        @test CorePotts._to_host(stats, d) == Float32[1, 2, 3, 4]
        @test counts() == (1, 1, 16)
        CorePotts._copy!(stats, d2, Float32[5, 6, 7, 8])                     # host → device
        @test counts() == (1, 2, 32)
        h = zeros(Float32, 4)
        CorePotts._copy!(stats, h, d2)                                       # device → host
        @test h == Float32[5, 6, 7, 8] && counts() == (1, 3, 48)
        CorePotts._copy!(stats, d, d2)                                       # device → device: not a transfer
        @test counts() == (1, 3, 48)
        @test CorePotts._readback(stats, PottsDevices.device_array(Int32[7])) == 7
        @test counts() == (1, 4, 52)
        # a snapshot: one transfer per device leaf
        st = CorePotts._to_backend(backend, initial_state(Int32[1 0; 0 2], Int32[1, 1]))
        before = counts()
        snap = CorePotts._snapshot(stats, backend, st)
        leaves = (st.σ, values(st.cell)...)
        @test snap.σ isa Array && snap.σ == Array(st.σ)
        @test counts() .- before == (0, length(leaves), sum(sizeof, leaves))
        # a lattice domain mask on the device: one transfer
        ml = CorePotts._to_backend(backend, Lattice((4, 4); domain = trues(4, 4)))
        before = counts()
        @test CorePotts._host_lattice(stats, ml).mask isa Array
        @test counts() .- before == (0, 1, 16)
        CorePotts._to_host(nothing, d)                                       # nothing counts into `nothing`
        @test counts() .- before == (0, 1, 16)
    end

    @testset "compartments on the device" begin
        σ, kinds, cluster = compartment_cells((48, 48), 8, 4)
        lat = Lattice((48, 48))
        n = length(kinds)
        f, p64 = compartment_model(; λs = 0.05)
        p = (; J = SMatrix{3, 3, Float32}(p64.J), Jint = 2.0f0, λ = 1.0f0, V0 = (48.0f0, 16.0f0),
            λc = 1.0f0, Vc = 64.0f0, λs = 0.05f0, Sc = 32.0f0, T = 10.0f0)
        st = initial_state(σ, kinds; cell = init_clusters(σ, cluster, lat; relation = Moore(1), T = Float32))
        u = solve(PottsProblem(f, st, lat, (0, 60), p; relations = (; surface = Moore(1))), CheckerboardCPM(); backend).u[end]
        @test u.σ != σ
        @test u.cell.cluster_volume == recompute_cluster_volume(u.σ, u.cell.cluster)
        @test u.cell.cluster_surface ≈ recompute_cluster_surface(u.σ, u.cell.cluster, lat, Moore(1)) rtol = 1e-5

        # a cluster divides as a unit on the device
        σd = zeros(Int32, 40, 40); σd[11:30, 15:22] .= 1; σd[18:23, 17:20] .= 2
        latd = Lattice((40, 40))
        cell = merge(init_moments(σd, latd, 2), init_clusters(σd, [1, 1], latd))
        std = with_capacity(initial_state(σd, Int32[1, 2]; cell), 6)
        tr(st, p, ctx, key, mcs, c) = mcs == 0 ? EVENT_DIVIDE_CLUSTER : EVENT_NONE
        fd = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
            lifecycle = Lifecycle(tr; cluster_normal = AlongMinorAxis{Float32}()))
        pd = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 40.0f0, T = 10.0f0)
        ud = solve(PottsProblem(fd, std, latd, (0, 1), pd), CheckerboardCPM(); backend).u[end]
        @test ud.cell.volume[1:4] == Int32[68, 12, 68, 12]
        @test ud.cell.cluster[1:4] == Int32[1, 1, 3, 3]

        # cells and clusters divide in one pass on the device (P6.0a): root 1 divides its
        # cluster (member 2's own EVENT_DIVIDE yields to it); lone cell 3 divides alone
        σm = copy(σd); σm[3:8, 30:37] .= 3
        cm = merge(init_moments(σm, latd, 3), init_clusters(σm, [1, 1, 3], latd), (; tag = zeros(Float32, 3)))
        stm = with_capacity(initial_state(σm, Int32[1, 2, 2]; cell = cm), 8)
        trm(st, p, ctx, key, mcs, c) = mcs != 0 ? EVENT_NONE : c == 1 ? EVENT_DIVIDE_CLUSTER :
                                       c in (2, 3) ? EVENT_DIVIDE : EVENT_NONE
        alone!(st, p, ctx, key, mcs, parent, daughter) = (st.cell.tag[parent] = st.cell.tag[daughter] = 1.0f0; nothing)
        together!(st, p, ctx, key, mcs, parent, daughter) = (st.cell.tag[parent] = st.cell.tag[daughter] = 2.0f0; nothing)
        fm = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
            lifecycle = Lifecycle(trm; normal = (st, p, ctx, key, mcs, c) -> (0.0f0, 1.0f0), divide! = alone!,
                cluster_normal = AlongMinorAxis{Float32}(), cluster_divide! = together!))
        um = solve(PottsProblem(fm, stm, latd, (0, 1), pd), CheckerboardCPM(); backend).u[end]
        @test Array(um.cell.volume)[1:6] == Int32[68, 12, 24, 68, 12, 24]
        @test Array(um.cell.cluster)[1:6] == Int32[1, 1, 3, 4, 4, 6]
        @test Array(um.cell.tag)[1:6] == Float32[2, 2, 1, 2, 2, 1]
        @test Array(um.cell.volume) == Int32[count(==(c), Array(um.σ)) for c in 1:8]
        @test Array(um.cell.cluster_volume) == recompute_cluster_volume(Array(um.σ), Array(um.cell.cluster))
    end

    @testset "lattice domains on the device" begin
        disk(x) = (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
        lat = Lattice((40, 40); boundary = Closed(), domain = disk)
        σ = zeros(Int32, 40, 40); σ[16:25, 16:25] .= 1; σ[5:10, 18:23] .= 2
        rate(st, p, ctx, key, mcs, i, c) = 0.2f0 * laplacian(c, ctx, i)
        c0 = zeros(Float32, 40, 40); c0[18:23, 18:23] .= 1
        # a division at MCS 5 rebuilds trackers on the host from the device context
        tr(st, p, ctx, key, mcs, c) = mcs == 5 && c == 1 ? EVENT_DIVIDE : EVENT_NONE
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, lifecycle = Lifecycle(tr; normal = AlongMinorAxis{Float32}()),
            phases = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), rate),)))
        st = with_capacity(initial_state(σ, Int32[1, 2]; cell = init_moments(σ, lat, 2),
            site = (; c = c0, c_next = copy(c0))), 4)
        p = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 60.0f0, T = 10.0f0)
        u = solve(PottsProblem(f, st, lat, (0, 40), p), CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test all(u.σ[.!lat.mask] .== 0)
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:4] && u.cell.volume[3] > 0
        @test sum(u.site.c[lat.mask]) ≈ 36 rtol = 1e-4
    end
    @testset "relationship reads (shared read claims) on the device" begin
        # P6.0b4: a chain of two relationships whose link partners are reads (D-058): 1–2 a
        # bond (rest 12), 2–3 a tether (len 18); every centroid distance starts at 25
        latR = Lattice((64, 30))
        σR = zeros(Int32, 64, 30); σR[5:10, 12:17] .= 1; σR[30:35, 12:17] .= 2; σR[55:60, 12:17] .= 3
        cellR = merge(init_moments(σR, latR, 3), empty_links(1, 3, :bond; rest = Float32),
            empty_links(1, 3, :tether; len = Float32))
        add_link!((; links = cellR.links__bond, link_rest = cellR.link_rest), 1, 2; rest = 12.0f0)
        add_link!((; links = cellR.links__tether, link_len = cellR.link_len), 2, 3; len = 18.0f0)
        function dHR(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S1(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            S2(a, b, k, d) = p.k * (d - st.cell.link_len[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float32, st.cell, (; links = st.cell.links__bond), ctx, prop, S1) +
                   link_delta(Float32, st.cell, (; links = st.cell.links__tether), ctx, prop, S2)
        end
        commitR!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        readsR(st, p, prop, ctx) = (link_claims((; links = st.cell.links__bond), prop, Val(1))...,
            link_claims((; links = st.cell.links__tether), prop, Val(1))...)
        f = CPMFunction(dHR; commit! = commitR!, temperature = gg_temperature, reads = readsR)
        pR(k) = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = Float32(k))
        prob(g, k, seed) = PottsProblem(g, initial_state(σR, [1, 1, 1]; cell = deepcopy(cellR)), latR, (0, 1500), pR(k); seed)
        # write claims are device buffers with reads, ghost `nothing` without (P6.0b3)
        wc = init(prob(f, 2, 1), CheckerboardCPM(); backend, save_start = false).cache.wclaims
        @test all(w -> w isa PottsDevices.device_arraytype() && eltype(w) == UInt32 && length(w) == 3, wc)
        @test init(prob(GG, 2, 1), CheckerboardCPM(); backend, save_start = false).cache.wclaims === (nothing, nothing)
        dist(u) = (centroid_distance(Float64, u.cell, latR, 1, 2), centroid_distance(Float64, u.cell, latR, 2, 3))
        runs(k, dev, seeds) = map(seeds) do seed
            integ = init(prob(f, k, seed), CheckerboardCPM(); save_start = false, (dev ? (; backend) : (;))...)
            dev && @test integ.state.σ isa PottsDevices.device_arraytype() && integ.state.cell.links__bond isa PottsDevices.device_arraytype()
            sol = solve!(integ)
            @test sol.retcode == ReturnCode.Success
            sol.u[end]
        end
        us = runs(2, true, 1:4)
        for u in us
            σu = Array(u.σ)
            @test u.cell.volume == [count(==(c), σu) for c in 1:3]
            ref = merge(init_moments(σu, latR, 3), (; volume = u.cell.volume))
            @test all(c -> all(isapprox.(centroid(u.cell, latR, c), centroid(ref, latR, c); atol = 1e-3)), 1:3)
            # the links are intact and each store keeps only its own pair
            B, Tt = (; links = Array(u.cell.links__bond)), (; links = Array(u.cell.links__tether))
            @test linked(B, 1, 2) && linked(B, 2, 1) && !linked(B, 2, 3)
            @test linked(Tt, 2, 3) && !linked(Tt, 1, 2)
            @test Array(u.cell.link_rest)[1, 1] == 12.0f0 && Array(u.cell.link_len)[1, 2] == 18.0f0
        end
        gpu = dist.(us)
        cpu = dist.(runs(2, false, 101:104))            # independent seeds (D-029)
        m(x, i) = mean(getindex.(x, i))
        @info "reads on the device: bond, tether distance" device = (m(gpu, 1), m(gpu, 2)) cpu = (m(cpu, 1), m(cpu, 2))
        @test abs(m(gpu, 1) - 12) < 2.5 && abs(m(gpu, 2) - 18) < 2.5             # relaxed toward rest
        # a consistency smoke check only: claim races are covered by the CPU kernel-mutation
        # tests in relationships.jl ("claim protocol in the real propose/commit kernels")
        @test abs(m(gpu, 1) - m(cpu, 1)) < 2.5 && abs(m(gpu, 2) - m(cpu, 2)) < 2.5  # comparable to CPU
        # negative control: without the spring the chain stays far from its rest lengths
        free = dist.(runs(0, true, 1:4))
        @info "reads on the device, k = 0" free = (m(free, 1), m(free, 2))
        @test m(free, 1) > 18 && m(free, 2) > 21
    end

    @testset "the frozen mask follows a lifecycle transition on the device (P6.0d)" begin
        # fixture in lifecycle.jl: cell 1 → frozen kind 2, cell 2 → free kind 1 at MCS 10
        S = 10
        for sys in (FrozenKind(2), HostFrozen(2))       # device rule, host fallback
            sol = solve(fk_problem(fk_flip(S); kind = fk_swap, sys, T = Float32), CheckerboardCPM(); backend, saveat = 1)
            @test sol.retcode == ReturnCode.Success && sol.stats.lifecycle.transitions == 2
            @test sol.stats.refreshes == 1
            @test fk_moved(sol, 1, 2:(S + 2)) >= (S + 1) ÷ 2
            @test fk_moved(sol, 2, 2:(S + 2)) == 0
            @test fk_moved(sol, 1, (S + 3):31) == 0              # frozen from the next sweep on
            @test fk_moved(sol, 2, (S + 3):31) >= 9              # released
        end
        # on the device the context holds the mask only; the count lives on the host
        integ = init(fk_problem(fk_flip(S); kind = fk_swap, T = Float32), CheckerboardCPM(); backend)
        @test integ.ctx.mobility.sites === nothing && integ.nmobile == 900 - 36
        # D-089: the counts of a refresh after an event MCS stay on the device until a host
        # read point (here `integ.u`), which corrects the MCS that ran with the old count
        rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
        integ = init(fk_problem(rm2; T = Float32), CheckerboardCPM(); backend, save_start = false)
        for _ in 0:S
            step!(integ)
        end
        @test integ.nmobile == 900 - 36                               # mask current, count on the device
        @test count(!, Array(integ.ctx.mobility.frozen)) == 900
        step!(integ)                                                  # MCS S+1: no read-back …
        @test integ.nmobile == 900 - 36 && integ.stats.lifecycle.removals == 0
        integ.u                                                       # … until a host read point
        @test integ.nmobile == 900 && integ.stats.lifecycle.removals == 1
        @test integ.stats.attempts == (S + 1) * (900 - 36) + 900      # MCS S+1 corrected
        # removal of the frozen cell: the mobile-site count grows by the device count
        sol = solve(fk_problem(rm2; T = Float32), CheckerboardCPM(); backend)
        @test sol.stats.attempts == (S + 1) * (900 - 36) + (30 - S - 1) * 900
        @test sol.u[end].cell.volume[1:2] == [count(==(c), sol.u[end].σ) for c in 1:2]
        # negative control: a static mask does not follow the transition
        ctl = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = nothing, T = Float32), CheckerboardCPM(); backend, saveat = 1)
        @test fk_moved(ctl, 1, (S + 3):31) >= 9 && ctl.stats.refreshes == 0
        # a domain without frozen kinds: a division, and no refresh
        dp = fk_domain_problem(; T = Float32)
        sol = solve(dp, CheckerboardCPM(); backend)
        @test sol.stats.lifecycle.divisions == 1 && sol.stats.refreshes == 0
        @test sol.stats.attempts == 8 * count(dp.lattice.mask)
        @test all(sol.u[end].σ[.!dp.lattice.mask] .== 0)
    end

    @testset "3D shell rule and the ΔH track on the device (P6.3a)" begin
        # the arc-or-pair rule on the 26-site shell compiles for the device
        lat3 = Lattice((18, 18, 18))
        σ3, k3 = blocks((18, 18, 18), 4; gap = 1)
        ok3(st, p, prop, ctx) = ring_arcs(st.σ, ctx, prop) <= 1 ||
            (ring_cells(st.σ, ctx, prop) == 2 && ring_medium(st.σ, ctx, prop) == 0)
        f3 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = ok3)
        p3 = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 64.0f0, T = 12.0f0)
        u3 = solve(PottsProblem(f3, initial_state(σ3, k3), lat3, (0, 10), p3; contact = Moore(1)),
            CheckerboardCPM(); backend).u[end]
        @test u3.σ != σ3
        @test u3.cell.volume == [count(==(c), u3.σ) for c in eachindex(k3)]
        @test all(c -> components(u3.σ, lat3, c) == 1, eachindex(k3))
        # the track: Float32 per-site sums reduced at the read points, 0 syncs per quiet MCS
        σt, kt = blocks((48, 48), 5)
        latt = Lattice((48, 48))
        pt = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 10.0f0)
        on = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float32}())
        off = CPMFunction(gg_delta_H; temperature = gg_temperature)
        mk(f) = PottsProblem(f, initial_state(σt, kt), latt, (0, 20), pt)
        a, b = solve(mk(off), CheckerboardCPM(); backend), solve(mk(on), CheckerboardCPM(); backend)
        H(u) = total_H(u, latt, mk(on).contact, pt)
        @test a.stats.accepted_ΔH === nothing
        @test b.stats.accepted_ΔH isa Float64
        @test isapprox(b.stats.accepted_ΔH, H(b.u[end]) - H(b.u[1]); atol = 0.5)
        @test abs(H(b.u[end]) - H(b.u[1])) > 100
        @test Array(a.u[end].σ) == Array(b.u[end].σ)
        for f in (off, on)
            integ = init(mk(f), CheckerboardCPM(); backend, save_start = false, save_end = false)
            step!(integ)
            c0 = (integ.stats.syncs, integ.stats.transfers)
            step!(integ); step!(integ)
            @test (integ.stats.syncs, integ.stats.transfers) == c0
        end
    end
end

# The device lifecycle's staged form (one kernel per stage; what problems above FUSE_SITES
# use) with the optional stages: the surface tracker, contact counts, cluster volume and
# surface, and the frozen-mask refresh. The fixtures above are small, so they run fused;
# here they run staged, against the same oracles (and the full no-`double` scan below then
# sees every stage kernel, D-157).
@testset "the staged device lifecycle on the device (surface, contact counts, clusters, frozen mask)" begin
    backend = PottsDevices.device_backend()
    fuse = CorePotts.FUSE_SITES[]
    CorePotts.FUSE_SITES[] = 0
    try
        # a cluster divides as a unit; cell surface and cluster surface tracked (Moore(1))
        σd = zeros(Int32, 40, 40); σd[11:30, 15:22] .= 1; σd[18:23, 17:20] .= 2
        latd = Lattice((40, 40))
        rel = relation(Moore(1), latd)
        cell = merge(init_moments(σd, latd, 2), init_clusters(σd, [1, 1], latd; relation = Moore(1), T = Float32),
            (; surface = recompute_surface(σd, latd, rel, 2; T = Float32)))
        std = with_capacity(initial_state(σd, Int32[1, 2]; cell), 6)
        tr(st, p, ctx, key, mcs, c) = mcs == 0 ? EVENT_DIVIDE_CLUSTER : EVENT_NONE
        fd = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
            lifecycle = Lifecycle(tr; cluster_normal = AlongMinorAxis{Float32}()))
        pd = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 40.0f0, T = 10.0f0)
        prob = PottsProblem(fd, std, latd, (0, 1), pd; relations = (; surface = Moore(1)))
        integ = init(prob, CheckerboardCPM(); backend)
        @test integ.lcache.device.fused! === nothing                     # control: staged
        u = solve!(integ).u[end]
        σu, cl = Array(u.σ), Array(u.cell.cluster)
        @test Array(u.cell.volume)[1:4] == Int32[68, 12, 68, 12]
        @test cl[1:4] == Int32[1, 1, 3, 3]
        @test Array(u.cell.volume) == Int32[count(==(c), σu) for c in eachindex(cl)]
        @test Array(u.cell.cluster_volume) == recompute_cluster_volume(σu, cl)
        @test Array(u.cell.cluster_surface) ≈ recompute_cluster_surface(σu, cl, latd, Moore(1); T = Float32)
        @test Array(u.cell.surface) ≈ brute_surface(σu, latd, rel, length(cl))
        # contact counts through divisions and a kind change (contact_counts.jl's fixture)
        cp = remake(cc_problem(); p = merge(gg_params(Float32), (; V0 = 36.0f0, T = 8.0f0)))
        integ = init(cp, CheckerboardCPM(); backend, saveat = 1)
        @test integ.lcache.device.fused! === nothing
        sol = solve!(integ)
        @test sol.stats.lifecycle.divisions >= 3 && sol.stats.lifecycle.transitions >= 1
        @test cc_bad(sol, cp.lattice) == 0
        # the frozen mask follows a removal (lifecycle.jl's fixture); counts as fused
        S = 10
        rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
        fp = fk_problem(rm2; T = Float32)
        integ = init(fp, CheckerboardCPM(); backend)
        @test integ.lcache.device.fused! === nothing
        sol = solve!(integ)
        @test sol.stats.attempts == (S + 1) * (900 - 36) + (30 - S - 1) * 900
        @test sol.u[end].cell.volume[1:2] == [count(==(c), sol.u[end].σ) for c in 1:2]
        # the Euler columns through divisions (euler.jl's fixture): zeroed and summed from σ
        ep = remake(eu_problem(); p = merge(gg_params(Float32), (; V0 = 30.0f0, T = 8.0f0)))
        integ = init(ep, CheckerboardCPM(); backend, saveat = 1)
        @test integ.lcache.device.fused! === nothing
        sol = solve!(integ)
        @test sol.stats.lifecycle.divisions >= 2
        @test sum(u -> eu_bad(map(Array, u.cell), Array(u.σ), ep.lattice), sol.u) == 0
    finally
        CorePotts.FUSE_SITES[] = fuse
    end
end

# ROCm, last: no `double` in any kernel this suite compiled (full scan of the kernel cache,
# D-157); the scan lives with the monorepo's shared test helpers
const DEVICE_IR_SCAN = joinpath(@__DIR__, "..", "..", "..", "test", "shared", "device_ir_scan.jl")
if PottsDevices.device_name() == "rocm" && isfile(DEVICE_IR_SCAN)
    include(DEVICE_IR_SCAN)
    DeviceIRScan.check("CorePotts")
end
