# Split from gpu_tests.jl; uses CP_gpu setup.
@testitem "device: compartments on the device" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    backend = PottsDevices.device_backend()
    @testset "compartments on the device" begin
        σ, kinds, cluster = compartment_cells((48, 48), 8, 4)
        lat = Lattice((48, 48))
        n = length(kinds)
        f, p64 = compartment_model(; λs = 0.05)
        p = (;
            J = SMatrix{3, 3, Float32}(p64.J), Jint = 2.0f0, λ = 1.0f0, V0 = (
                48.0f0, 16.0f0,
            ),
            λc = 1.0f0, Vc = 64.0f0, λs = 0.05f0, Sc = 32.0f0, T = 10.0f0,
        )
        st = initial_state(
            σ, kinds; cell = init_clusters(
                σ, cluster, lat; relation = Moore(1), T = Float32
            )
        )
        u = solve(
            PottsProblem(f, st, lat, (0, 60), p; relations = (; surface = Moore(1))),
            CheckerboardCPM(); backend
        ).u[end]
        @test u.ownership != σ
        @test u.cell.cluster_volume == recompute_cluster_volume(u.ownership, u.cell.cluster)
        @test u.cell.cluster_surface ≈
            recompute_cluster_surface(
            u.ownership, u.cell.cluster, lat,
            Moore(1)
        ) rtol = 1.0e-5

        # a cluster divides as a unit on the device
        σd = zeros(Int32, 40, 40)
        σd[11:30, 15:22] .= 1
        σd[18:23, 17:20] .= 2
        latd = Lattice((40, 40))
        cell = merge(init_moments(σd, latd, 2), init_clusters(σd, [1, 1], latd))
        std = with_capacity(initial_state(σd, Int32[1, 2]; cell), 6)
        tr(st, p, ctx, key, mcs, c) = mcs == 0 ? EVENT_DIVIDE_CLUSTER : EVENT_NONE
        fd = CPMFunction(
            gg_delta_H; temperature = gg_temperature, constraint = (
                st, p, prop, ctx
            ) -> false,
            lifecycle = Lifecycle(tr; cluster_normal = AlongMinorAxis{Float32}())
        )
        pd = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 40.0f0, T = 10.0f0,
        )
        ud = solve(
            PottsProblem(fd, std, latd, (0, 1), pd), CheckerboardCPM();
            backend
        ).u[end]
        @test ud.cell.volume[1:4] == Int32[68, 12, 68, 12]
        @test ud.cell.cluster[1:4] == Int32[1, 1, 3, 3]

        # cells and clusters divide in one pass on the device: root 1 divides its
        # cluster (member 2's own EVENT_DIVIDE yields to it); lone cell 3 divides alone
        σm = copy(σd)
        σm[3:8, 30:37] .= 3
        cm = merge(
            init_moments(σm, latd, 3), init_clusters(σm, [1, 1, 3], latd), (;
                tag = zeros(Float32, 3),
            )
        )
        stm = with_capacity(initial_state(σm, Int32[1, 2, 2]; cell = cm), 8)
        function trm(st, p, ctx, key, mcs, c)
            if mcs != 0
                return EVENT_NONE
            elseif c == 1
                return EVENT_DIVIDE_CLUSTER
            elseif c in (2, 3)
                return EVENT_DIVIDE
            else
                return EVENT_NONE
            end
        end
        function alone!(st, p, ctx, key, mcs, parent, daughter)
            st.cell.tag[parent] = st.cell.tag[daughter] = 1.0f0
            return nothing
        end
        function together!(st, p, ctx, key, mcs, parent, daughter)
            st.cell.tag[parent] = st.cell.tag[daughter] = 2.0f0
            return nothing
        end
        fm = CPMFunction(
            gg_delta_H; temperature = gg_temperature, constraint = (
                st, p, prop, ctx
            ) -> false,
            lifecycle = Lifecycle(
                trm; normal = (st, p, ctx, key, mcs, c) -> (0.0f0, 1.0f0), divide! = alone!,
                cluster_normal = AlongMinorAxis{Float32}(), cluster_divide! = together!
            )
        )
        um = solve(
            PottsProblem(fm, stm, latd, (0, 1), pd), CheckerboardCPM();
            backend
        ).u[end]
        @test Array(um.cell.volume)[1:6] == Int32[68, 12, 24, 68, 12, 24]
        @test Array(um.cell.cluster)[1:6] == Int32[1, 1, 3, 4, 4, 6]
        @test Array(um.cell.tag)[1:6] == Float32[2, 2, 1, 2, 2, 1]
        @test Array(um.cell.volume) == Int32[count(==(c), Array(um.ownership)) for c in 1:8]
        @test Array(um.cell.cluster_volume) ==
            recompute_cluster_volume(Array(um.ownership), Array(um.cell.cluster))
    end
end

@testitem "device: lattice domains on the device" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    backend = PottsDevices.device_backend()
    @testset "lattice domains on the device" begin
        disk(x) = (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
        lat = Lattice((40, 40); boundary = Closed(), domain = disk)
        σ = zeros(Int32, 40, 40)
        σ[16:25, 16:25] .= 1
        σ[5:10, 18:23] .= 2
        # a division at MCS 5 rebuilds trackers on the host from the device context
        tr(st, p, ctx, key, mcs, c) = mcs == 5 && c == 1 ? EVENT_DIVIDE : EVENT_NONE
        f = CPMFunction(
            gg_delta_H; temperature = gg_temperature,
            lifecycle = Lifecycle(tr; normal = AlongMinorAxis{Float32}())
        )
        st = with_capacity(initial_state(σ, Int32[1, 2]; cell = init_moments(σ, lat, 2)), 4)
        p = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 60.0f0, T = 10.0f0,
        )
        u = solve(
            PottsProblem(f, st, lat, (0, 40), p), CheckerboardCPM(;
                proposal = Moore(1)
            ); backend
        ).u[end]
        @test all(u.ownership[.!lat.mask] .== 0)
        @test u.cell.volume == [count(==(c), u.ownership) for c in 1:4] &&
            u.cell.volume[3] > 0
    end
end

@testitem "device: a chain of two relationships on the device" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    backend = PottsDevices.device_backend()
    @testset "a chain of two relationships on the device" begin
        # A chain of two relationships: 1–2 a
        # bond (rest 12), 2–3 a tether (len 18); every centroid distance starts at 25
        latR = Lattice((64, 30))
        σR = zeros(Int32, 64, 30)
        σR[5:10, 12:17] .= 1
        σR[30:35, 12:17] .= 2
        σR[55:60, 12:17] .= 3
        cellR = merge(
            init_moments(σR, latR, 3), empty_links(1, 3, :bond; rest = Float32),
            empty_links(1, 3, :tether; len = Float32)
        )
        add_link!(
            (; links = cellR.links__bond, link_rest = cellR.link_rest), 1, 2;
            rest = 12.0f0
        )
        add_link!(
            (; links = cellR.links__tether, link_len = cellR.link_len), 2, 3;
            len = 18.0f0
        )
        function dHR(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S1(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            S2(a, b, k, d) = p.k * (d - st.cell.link_len[k, a])^2
            return contact_delta(st.ownership, ctx, prop, J) +
                volume_delta(st.cell.volume, prop, E) +
                link_delta(
                Float32, st.cell, (; links = st.cell.links__bond), ctx, prop, S1
            ) +
                link_delta(
                Float32, st.cell, (; links = st.cell.links__tether), ctx, prop, S2
            )
        end
        function commitR!(st, p, prop, ctx)
            commit_volume!(st, p, prop, ctx)
            return commit_moments!(st.cell, ctx, prop)
        end
        f = CPMFunction(dHR; commit! = commitR!, temperature = gg_temperature)
        function pR(k)
            return (;
                J = SMatrix{3, 3, Float32}(gg_params().J),
                λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = Float32(k),
            )
        end
        function prob(g, k, seed)
            return PottsProblem(
                g, initial_state(σR, [1, 1, 1]; cell = deepcopy(cellR)),
                latR, (0, 1500), pR(k); seed
            )
        end
        function dist(u)
            return (
                centroid_distance(Float64, u.cell, latR, 1, 2),
                centroid_distance(Float64, u.cell, latR, 2, 3),
            )
        end
        function runs(k, dev, seeds)
            return map(seeds) do seed
                integ = init(
                    prob(f, k, seed), CheckerboardCPM();
                    save_start = false, (dev ? (; backend) : (;))...
                )
                dev && @test integ.state.ownership isa PottsDevices.device_arraytype() &&
                    integ.state.cell.links__bond isa PottsDevices.device_arraytype()
                sol = solve!(integ)
                @test sol.retcode == ReturnCode.Success
                sol.u[end]
            end
        end
        us = runs(2, true, 1:4)
        for u in us
            σu = Array(u.ownership)
            @test u.cell.volume == [count(==(c), σu) for c in 1:3]
            ref = merge(init_moments(σu, latR, 3), (; volume = u.cell.volume))
            @test all(
                c -> all(
                    isapprox.(
                        centroid(u.cell, latR, c), centroid(ref, latR, c);
                        atol = 1.0e-3
                    )
                ),
                1:3
            )
            # the links are intact and each store keeps only its own pair
            B, Tt = (; links = Array(u.cell.links__bond)),
                (; links = Array(u.cell.links__tether))
            @test linked(B, 1, 2) && linked(B, 2, 1) && !linked(B, 2, 3)
            @test linked(Tt, 2, 3) && !linked(Tt, 1, 2)
            @test Array(u.cell.link_rest)[1, 1] == 12.0f0 &&
                Array(u.cell.link_len)[1, 2] == 18.0f0
        end
        gpu = dist.(us)
        cpu = dist.(runs(2, false, 101:104))            # independent seeds (D-029)
        m(x, i) = mean(getindex.(x, i))
        @info "reads on the device: bond, tether distance" device = (
            m(gpu, 1),
            m(gpu, 2),
        ) cpu = (
            m(cpu, 1), m(cpu, 2),
        )
        # relaxed toward rest
        @test abs(m(gpu, 1) - 12) < 2.5 && abs(m(gpu, 2) - 18) < 2.5
        # a consistency smoke check: the lockless checkerboard reads partners' centroids
        # live
        # comparable to CPU
        @test abs(m(gpu, 1) - m(cpu, 1)) < 2.5 && abs(m(gpu, 2) - m(cpu, 2)) < 2.5
        # negative control: without the spring the chain stays far from its rest lengths
        free = dist.(runs(0, true, 1:4))
        @info "reads on the device, k = 0" free = (m(free, 1), m(free, 2))
        @test m(free, 1) > 18 && m(free, 2) > 21
    end
end

@testitem "device: the frozen mask follows a lifecycle transition on the device" setup = [
    CP_gpu,
] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    backend = PottsDevices.device_backend()
    @testset "the frozen mask follows a lifecycle transition on the device" begin
        # fixture in lifecycle.jl: cell 1 → frozen kind 2, cell 2 → free kind 1 at MCS 10
        S = 10
        for sys in (FrozenKind(2), HostFrozen(2))       # device rule, host fallback
            sol = solve(
                fk_problem(fk_flip(S); kind = fk_swap, sys, T = Float32),
                CheckerboardCPM(); backend, saveat = 1
            )
            @test sol.retcode == ReturnCode.Success && sol.stats.lifecycle.transitions == 2
            @test sol.stats.refreshes == 1
            @test fk_moved(sol, 1, 2:(S + 2)) >= (S + 1) ÷ 2
            @test fk_moved(sol, 2, 2:(S + 2)) == 0
            # frozen from the next sweep on
            @test fk_moved(sol, 1, (S + 3):31) == 0
            @test fk_moved(sol, 2, (S + 3):31) >= 9              # released
        end
        # on the device the context holds the mask only; the count lives on the host
        integ = init(
            fk_problem(fk_flip(S); kind = fk_swap, T = Float32), CheckerboardCPM();
            backend
        )
        @test integ.ctx.mobility.sites === nothing && integ.nmobile == 900 - 36
        # D-089: the counts of a refresh after an event MCS stay on the device until a host
        # read point (here `current_state(integ)`), which corrects the MCS that ran with the
        # old count
        rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
        integ = init(
            fk_problem(rm2; T = Float32), CheckerboardCPM();
            backend, save_start = false, save_everystep = false
        )
        for _ in 0:S
            step!(integ)
        end
        # mask current, count on the device
        @test integ.nmobile == 900 - 36
        @test count(!, Array(integ.ctx.mobility.frozen)) == 900
        # MCS S+1: no read-back …
        step!(integ)
        @test integ.nmobile == 900 - 36 && integ.stats.lifecycle.removals == 0
        # … until a host read point
        current_state(integ)
        @test integ.nmobile == 900 && integ.stats.lifecycle.removals == 1
        # D-253: the Int64 width (forced; it is the width above 2³¹ − 1 sites) on the
        # device. With 64-bit atomic adds the counted run equals its Int32 run; without them
        # (Metal) a mask that follows the state is refused at `init`, and a run without one
        # still runs
        function wide(f)
            CorePotts._FORCE_WIDE_SITES[] = true
            return try
                f()
            finally
                CorePotts._FORCE_WIDE_SITES[] = false
            end
        end
        fk32 = fk_problem(rm2; T = Float32)
        if CorePotts._atomic64(backend)
            # the device run is not reproducible (lockless): both widths run the event
            a = solve(fk32, CheckerboardCPM(); backend, saveat = 1)
            b = wide(() -> solve(fk32, CheckerboardCPM(); backend, saveat = 1))
            @test a.stats.attempts == b.stats.attempts &&
                a.stats.lifecycle.removals == b.stats.lifecycle.removals == 1
        else
            @test_throws ArgumentError wide(() -> init(fk32, CheckerboardCPM(); backend))
            static = fk_problem(rm2; T = Float32, sys = nothing)
            @test wide(() -> solve(static, CheckerboardCPM(); backend)).retcode ==
                ReturnCode.Success
        end
        @test integ.stats.attempts == (S + 1) * (900 - 36) + 900      # MCS S+1 corrected
        # removal of the frozen cell: the mobile-site count grows by the device count
        sol = solve(fk_problem(rm2; T = Float32), CheckerboardCPM(); backend)
        @test sol.stats.attempts == (S + 1) * (900 - 36) + (30 - S - 1) * 900
        @test sol.u[end].cell.volume[1:2] ==
            [count(==(c), sol.u[end].ownership) for c in 1:2]
        # negative control: a static mask does not follow the transition
        ctl = solve(
            fk_problem(fk_flip(S); kind = fk_swap, sys = nothing, T = Float32),
            CheckerboardCPM(); backend, saveat = 1
        )
        @test fk_moved(ctl, 1, (S + 3):31) >= 9 && ctl.stats.refreshes == 0
        # a domain without frozen kinds: a division, and no refresh
        dp = fk_domain_problem(; T = Float32)
        sol = solve(dp, CheckerboardCPM(); backend)
        @test sol.stats.lifecycle.divisions == 1 && sol.stats.refreshes == 0
        @test sol.stats.attempts == 8 * count(dp.lattice.mask)
        @test all(sol.u[end].ownership[.!dp.lattice.mask] .== 0)
    end
end

@testitem "device: 3D shell rule and the ΔH track on the device" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    backend = PottsDevices.device_backend()
    @testset "3D shell rule and the ΔH track on the device" begin
        # the arc-or-pair rule on the 26-site shell compiles for the device
        lat3 = Lattice((18, 18, 18))
        σ3, k3 = blocks((18, 18, 18), 4; gap = 1)
        function ok3(st, p, prop, ctx)
            return ring_arcs(st.ownership, ctx, prop) <= 1 ||
                (
                ring_cells(st.ownership, ctx, prop) == 2 &&
                    ring_medium(st.ownership, ctx, prop) == 0
            )
        end
        f3 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = ok3)
        p3 = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 64.0f0, T = 12.0f0,
        )
        u3 = solve(
            PottsProblem(f3, initial_state(σ3, k3), lat3, (0, 10), p3; contact = Moore(1)),
            CheckerboardCPM(); backend
        ).u[end]
        @test u3.ownership != σ3
        @test u3.cell.volume == [count(==(c), u3.ownership) for c in eachindex(k3)]
        @test all(c -> components(u3.ownership, lat3, c) == 1, eachindex(k3))
        # the track: Float32 per-site sums reduced at the read points, 0 syncs per quiet MCS
        σt, kt = blocks((48, 48), 5)
        latt = Lattice((48, 48))
        pt = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 10.0f0,
        )
        on = CPMFunction(
            gg_delta_H; temperature = gg_temperature,
            track = CorePotts.TrackEnergyChange{Float32}()
        )
        off = CPMFunction(gg_delta_H; temperature = gg_temperature)
        mk(f) = PottsProblem(f, initial_state(σt, kt), latt, (0, 20), pt)
        a, b = solve(mk(off), CheckerboardCPM(); backend),
            solve(mk(on), CheckerboardCPM(); backend)
        H(u) = total_H(u, latt, mk(on).contact, pt)
        @test a.stats.accepted_energy_change === nothing
        @test b.stats.accepted_energy_change isa Float64
        # concurrent copies of one cell each take ΔH against its totals before the other's
        # commit (lockless), so on a device the track is the energy change to within that
        @test isapprox(b.stats.accepted_energy_change, H(b.u[end]) - H(b.u[1]); rtol = 0.01)
        @test abs(H(b.u[end]) - H(b.u[1])) > 100
        for f in (off, on)
            integ = init(
                mk(f), CheckerboardCPM(); backend, save_start = false,
                save_everystep = false, save_end = false
            )
            step!(integ)
            c0 = (integ.stats.syncs, integ.stats.transfers)
            step!(integ)
            step!(integ)
            @test (integ.stats.syncs, integ.stats.transfers) == c0
        end
    end
end

# The device lifecycle's staged form (one kernel per stage; what problems above
# `fused_lifecycle_max_sites` use) with the optional stages: the surface tracker, contact
# counts, cluster volume and surface, and the frozen-mask refresh. The fixtures above are
# small, so they run fused; here they run staged, against the same oracles (and the full
# no-`double` scan below then sees every stage kernel, D-157).
@testitem "the staged device lifecycle on the device (surface, contact counts, clusters, \
    frozen mask)" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "the staged device lifecycle on the device (surface, contact counts, \
        clusters, frozen mask)" begin
        backend = PottsDevices.device_backend()
        staged = CheckerboardCPM(; fused_lifecycle_max_sites = 0)
        begin
            # a cluster divides as a unit; cell surface and cluster surface tracked
            # (Moore(1))
            σd = zeros(Int32, 40, 40)
            σd[11:30, 15:22] .= 1
            σd[18:23, 17:20] .= 2
            latd = Lattice((40, 40))
            rel = relation(Moore(1), latd)
            cell = merge(
                init_moments(σd, latd, 2), init_clusters(
                    σd, [1, 1], latd; relation = Moore(1), T = Float32
                ),
                (; surface = recompute_surface(σd, latd, rel, 2; T = Float32))
            )
            std = with_capacity(initial_state(σd, Int32[1, 2]; cell), 6)
            tr(st, p, ctx, key, mcs, c) = mcs == 0 ? EVENT_DIVIDE_CLUSTER : EVENT_NONE
            fd = CPMFunction(
                gg_delta_H; temperature = gg_temperature, constraint = (
                    st, p, prop, ctx
                ) -> false,
                lifecycle = Lifecycle(tr; cluster_normal = AlongMinorAxis{Float32}())
            )
            pd = (;
                J = SMatrix{3, 3, Float32}(gg_params().J),
                λ = 1.0f0, V0 = 40.0f0, T = 10.0f0,
            )
            prob = PottsProblem(
                fd, std, latd, (0, 1), pd; relations = (; surface = Moore(1))
            )
            integ = init(prob, staged; backend)
            # control: staged
            @test integ.lcache.device.fused! === nothing
            u = solve!(integ).u[end]
            σu, cl = Array(u.ownership), Array(u.cell.cluster)
            @test Array(u.cell.volume)[1:4] == Int32[68, 12, 68, 12]
            @test cl[1:4] == Int32[1, 1, 3, 3]
            @test Array(u.cell.volume) == Int32[count(==(c), σu) for c in eachindex(cl)]
            @test Array(u.cell.cluster_volume) == recompute_cluster_volume(σu, cl)
            @test Array(u.cell.cluster_surface) ≈
                recompute_cluster_surface(σu, cl, latd, Moore(1); T = Float32)
            @test Array(u.cell.surface) ≈ brute_surface(σu, latd, rel, length(cl))
            # contact counts through divisions and a kind change (contact_counts.jl's
            # fixture)
            cp = remake(
                cc_problem(); p = merge(
                    gg_params(Float32), (;
                        V0 = 36.0f0, T = 8.0f0,
                    )
                )
            )
            integ = init(cp, staged; backend, saveat = 1)
            @test integ.lcache.device.fused! === nothing
            sol = solve!(integ)
            @test sol.stats.lifecycle.divisions >= 3 && sol.stats.lifecycle.transitions >= 1
            @test cc_bad(sol, cp.lattice) == 0
            # the frozen mask follows a removal (lifecycle.jl's fixture); counts as fused
            S = 10
            rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
            fp = fk_problem(rm2; T = Float32)
            integ = init(fp, staged; backend)
            @test integ.lcache.device.fused! === nothing
            sol = solve!(integ)
            @test sol.stats.attempts == (S + 1) * (900 - 36) + (30 - S - 1) * 900
            @test sol.u[end].cell.volume[1:2] ==
                [count(==(c), sol.u[end].ownership) for c in 1:2]
            # the Euler columns through divisions (euler.jl's fixture): zeroed and summed
            # from σ
            ep = remake(
                eu_problem(); p = merge(
                    gg_params(Float32), (;
                        V0 = 30.0f0, T = 8.0f0,
                    )
                )
            )
            integ = init(ep, staged; backend, saveat = 1)
            @test integ.lcache.device.fused! === nothing
            sol = solve!(integ)
            @test sol.stats.lifecycle.divisions >= 2
            @test sum(
                u -> eu_bad(map(Array, u.cell), Array(u.ownership), ep.lattice),
                sol.u
            ) ==
                0
        end
    end
end

@testitem "whole-cell connectivity on the device" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "whole-cell connectivity on the device" begin
        backend = PottsDevices.device_backend()
        σ, kinds = blocks((32, 32), 5)
        lat = Lattice((32, 32))
        p = merge(gg_params(Float32), (; V0 = 25.0f0, T = 12.0f0))
        H = CorePotts.ConnectivityHooks
        for (f, splits) in (
                (
                    CPMFunction(
                        gg_delta_H; temperature = gg_temperature,
                        connectivity = H(; post = global_post_window, uses_global = true)
                    ),
                    false,
                ),
                (
                    CPMFunction(
                        gg_delta_H; temperature = gg_temperature,
                        connectivity = H(;
                            post = global_post_exact, uses_global = true,
                            exact_veto = true
                        )
                    ), false,
                ),
                (
                    CPMFunction(
                        global_penalty_dH; temperature = gg_temperature,
                        connectivity = H(; defer = global_defer_check, uses_global = true)
                    ),
                    true,
                ),
            )
            prob = PottsProblem(f, initial_state(σ, kinds), lat, (0, 8), p)
            integ = init(
                prob, CheckerboardCPM(; proposal = Moore(1));
                backend, save_start = false, save_end = false
            )
            prev = first(recompute_pieces(σ, lat, Val(false), length(kinds)))
            up = 0
            for _ in 1:8
                step!(integ)
                now = first(
                    recompute_pieces(
                        Array(integ.state.ownership), lat, Val(false),
                        length(kinds)
                    )
                )
                up += count(now .> prev)
                prev = now
            end
            @test integ.retcode == ReturnCode.Default
            # the veto: no cell's pieces increase
            splits || @test up == 0
            @test current_state(integ).cell.volume ==
                [count(==(c), Array(integ.state.ownership)) for c in eachindex(kinds)]
            @test integ.stats.connectivity_deferred isa Int
        end
    end
end

# The lockless checkerboard on the device: concurrent copies keep every tracker exact,
# the serial pass and the windowed search keep vetoed cells whole, and the device commits at
# the CPU's rate (statistically: D-029; runs are not reproducible on a device)
@testitem "lockless checkerboard on the device (PottsDevices.device_name())" setup = [
    CP_gpu,
] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "lockless checkerboard on the device ($(PottsDevices.device_name()))" begin
        backend = PottsDevices.device_backend()
        lat = Lattice((96, 96))
        σ, kinds = blocks((96, 96), 6)
        n = length(kinds)
        pf = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
        )
        recount(u) = [count(==(c), u.ownership) for c in 1:n]
        prob = PottsProblem(
            CPMFunction(gg_delta_H; temperature = gg_temperature),
            initial_state(σ, kinds), lat, (0, 30), pf
        )
        for kw in (
                (;), (; region = 3), (; region = 4, switches = 4), (;
                    region = 1, parts = 4,
                ),
            )
            alg = CheckerboardCPM(; proposal = Moore(1), kw...)
            g = solve(remake(prob; seed = 3), alg; backend)
            @test g.u[end].cell.volume == recount(g.u[end])
            @test g.stats.committed == g.stats.accepted > 0
            n_cb = max(10, required_n(sqrt(2) * 250.0, 1000.0; alpha = 1.0e-3, power = 0.9))
            cg = Float64[
                solve(remake(prob; seed), alg; backend).stats.committed
                    for seed in 1:n_cb
            ]
            cc = Float64[
                solve(remake(prob; seed), alg).stats.committed
                    for seed in 11:(10 + n_cb)
            ]
            margin = 0.05 * mean(cc)
            @test stat_accept(cg, cc; margin, alpha = 1.0e-3).pass
            @test !stat_accept(0.5 .* cg, cc; margin, alpha = 1.0e-3).pass
        end
        # moments (atomic sums, re-centered once per MCS) and on-copy counters that read
        # their own value (atomic changes): gains minus losses equal each cell's volume
        # change, so no update was lost
        function commitM!(st, p, prop, ctx)
            commit_volume!(st, p, prop, ctx)
            commit_moments!(st.cell, ctx, prop)
            g = prop.new == 0 ? Int32(0) : st.cell.gain[prop.new]
            CorePotts.oncopy_cell!(st.cell.gain, prop.new, g + Int32(1), g, ctx)
            l = prop.old == 0 ? Int32(0) : st.cell.loss[prop.old]
            CorePotts.oncopy_cell!(st.cell.loss, prop.old, l + Int32(1), l, ctx)
            return nothing
        end
        cell = merge(
            init_moments(σ, lat, n), (;
                gain = zeros(Int32, n), loss = zeros(Int32, n),
            )
        )
        mprob = PottsProblem(
            CPMFunction(gg_delta_H; temperature = gg_temperature, commit! = commitM!),
            initial_state(σ, kinds; cell), lat, (0, 30), pf; seed = 5
        )
        u0 = initial_state(σ, kinds)
        u = solve(mprob, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test u.cell.volume == recount(u)
        @test u.cell.gain .- u.cell.loss == u.cell.volume .- u0.cell.volume
        @test sum(u.cell.gain) > 1000
        ref = merge(init_moments(u.ownership, lat, n), (; volume = u.cell.volume))
        @test all(
            c -> all(
                isapprox.(centroid(u.cell, lat, c), centroid(ref, lat, c); atol = 1.0e-6)
            ),
            1:n
        )
        # a `Global` veto: exact (the serial pass) and in a window of 2 (searched in the
        # phase)
        function post_w(st, p, prop, ctx, stage)
            if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
                return CorePotts.global_keeps(
                    st.ownership, ctx, prop, Val(false), Val(2), Val(25), stage
                )
            else
                return Int32(2)
            end
        end
        function post_x(st, p, prop, ctx, stage)
            if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
                return CorePotts.global_keeps(
                    st.ownership, ctx, prop, Val(false), Val(nothing), Val(0), stage
                )
            else
                return Int32(2)
            end
        end
        pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), n))
        for hooks in (
                CorePotts.ConnectivityHooks(;
                    post = post_x, uses_global = true,
                    exact_veto = true
                ),
                CorePotts.ConnectivityHooks(;
                    post = post_w, uses_global = true,
                    window = 2
                ),
            )
            cprob = PottsProblem(
                CPMFunction(gg_delta_H; temperature = gg_temperature, connectivity = hooks),
                initial_state(σ, kinds), lat, (0, 20), pf; seed = 7
            )
            sol = solve(cprob, CheckerboardCPM(; proposal = Moore(1)); backend)
            uc = sol.u[end]
            @test uc.cell.volume == recount(uc)
            @test all(
                first(CorePotts.recompute_pieces(uc.ownership, lat, Val(false), n)) .<=
                    pieces0
            )   # no cell splits
            @test sol.stats.committed > 1000
            @test sol.stats.connectivity_deferred isa Int
        end
        # ensembles: concurrent trajectories (tasks, each with its own device queue; on one
        # thread they interleave at the waits) each stay consistent and draw their own
        # stream
        alg = CheckerboardCPM(; proposal = Moore(1))
        runs = fetch.(
            [
                Threads.@spawn(solve(remake(prob; seed = 20 + k), alg; backend))
                    for k in 1:4
            ]
        )
        @test all(
            s -> s.u[end].cell.volume == recount(s.u[end]) &&
                s.stats.committed == s.stats.accepted > 0,
            runs
        )
        @test allunique([s.u[end].ownership for s in runs])
        # EnsembleThreads by default
        ens = solve(EnsembleProblem(prob), alg; backend, trajectories = 3)
        @test all(s -> s.u[end].cell.volume == recount(s.u[end]), ens.u) &&
            allunique([s.u[end].ownership for s in ens.u])
    end
end

# A float cell sum on the device equals the host bitwise (exact fixed point), in the
# Int64 form and in the paired 32-bit form of backends without 64-bit atomics (Metal),
# forced here. Negative control: the float atomics of the code before integer cell sums
# differ from the host.
@testitem "float cell sums on the device equal the host bitwise" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "float cell sums on the device equal the host bitwise" begin
        backend = PottsDevices.device_backend()
        dims = (96, 80)
        σ = cs_owners(dims)
        n = Int(maximum(σ))
        v = Float32.(cs_values(dims))
        bits(x) = reinterpret(UInt32, Array(x))
        host = cs_run!(cs_state(σ, v, n; T = Float32))
        for paired in (false, true)
            CorePotts._FORCE_PAIRED[] = paired
            try
                st = CorePotts._to_backend(backend, cs_state(σ, v, n; T = Float32))
                @test bits(cs_run!(st; backend)) == bits(host)
            finally
                CorePotts._FORCE_PAIRED[] = false
            end
        end
        # non-finite values on the device
        w = copy(v)
        w[findfirst(==(1), σ)] = NaN32
        w[findfirst(==(2), σ)] = -Inf32
        d = Array(
            cs_run!(
                CorePotts._to_backend(backend, cs_state(σ, w, n; T = Float32));
                backend
            )
        )
        @test isnan(d[1]) && d[2] == -Inf32 && bits(d[3:n]) == bits(host[3:n])
        CorePotts._FLOAT_ATOMICS[] = true
        try
            host0 = cs_run!(cs_state(σ, v, n; T = Float32))
            @test bits(
                cs_run!(
                    CorePotts._to_backend(backend, cs_state(σ, v, n; T = Float32));
                    backend
                )
            ) !=
                bits(host0)
        finally
            CorePotts._FLOAT_ATOMICS[] = false
        end
    end
end

# A weighted contact table on the device equals the host bitwise (integer
# weight units, Int64 and paired forms)
@testitem "weighted contact tables on the device equal the host bitwise" setup = [
    CP_gpu,
] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "weighted contact tables on the device equal the host bitwise" begin
        backend = PottsDevices.device_backend()
        dims = (96, 80)
        σ = cs_owners(dims)
        n = Int(maximum(σ))
        lat = Lattice(dims)
        ctx = (;
            lattice = lat,
            touch = relation(Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o))), lat),
        )
        function run(b)
            st = initial_state(σ, ones(Int32, n); cell = empty_contacts(12, n; T = Float32))
            b isa CPU || (st = CorePotts._to_backend(b, st))
            ContactPhase(:touch)(st, nothing, ctx, RNGKey(0), 0, b)
            return (
                Array(st.cell.contact_nbr), Array(st.cell.contact_measure),
                Array(st.cell.contact_medium),
            )
        end
        hn, hm, hd = run(CPU())
        function meas(nbr, m, a, b)
            k = findfirst(==(b), view(nbr, :, a))
            return k === nothing ? 0.0f0 : m[k, a]
        end
        for paired in (false, true)
            CorePotts._FORCE_PAIRED[] = paired
            try
                dn, dm, dd = run(backend)
                @test reinterpret(UInt32, dd) == reinterpret(UInt32, hd)
                @test all(
                    a -> all(b -> meas(dn, dm, a, b) === meas(hn, hm, a, b), 1:n),
                    1:n
                )
            finally
                CorePotts._FORCE_PAIRED[] = false
            end
        end
    end
end

@testitem "device IR: no double in any kernel this suite compiled" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only, :device_scan,
] begin
    if PottsDevices.device_name() == "rocm"&&isfile(DEVICE_IR_SCAN)
        include(DEVICE_IR_SCAN)
        DeviceIRScan.check("CorePotts")
    end
end

@testitem "device IR: the minimum image divides by no lattice length" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    # The device LLVM of `min_image` holds no 64-bit division or remainder by a runtime
    # value (a division by the constant 2 is a shift). Negative control: the floor-division
    # wrap it replaced is flagged. ROCm only: the module comes from GPUCompiler's job.
    if PottsDevices.device_name() == "rocm"
        AMDGPU = PottsDevices.device_package()
        GPUCompiler = AMDGPU.GPUCompiler
        function device_ir(f, TT)
            config = AMDGPU.Compiler.compiler_config(AMDGPU.device(); kernel = false)
            mi = GPUCompiler.methodinstance(typeof(f), Base.to_tuple_type(TT))
            job = GPUCompiler.CompilerJob(mi, config)
            return sprint(io -> GPUCompiler.code_llvm(io, job; dump_module = true))
        end
        runtime_div = r"\b[su](?:div|rem) i64 [^,]+, %"
        ndiv(ir) = count(l -> occursin(runtime_div, l), split(ir, '\n'))
        floor_wrap(l::Lattice{N}, x, a) where {N} = ntuple(Val(N)) do d
            δ = x[d] - a[d]
            n = l.dims[d]
            l.periodic[d] ? δ - n * fld(δ + cld(n, 2) - 1, n) : δ
        end
        @testset "$(N)-D" for N in (2, 3)
            TT = (typeof(Lattice(ntuple(_ -> 8, N))), NTuple{N, Int}, NTuple{N, Int})
            @test ndiv(device_ir(min_image, TT)) == 0
            @test ndiv(device_ir(floor_wrap, TT)) >= N
        end
    end
end

@testitem "compile-only launches compile what the launch runs, and write nothing \
    (device)" setup = [CP_gpu] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    @testset "compile-only launches compile what the launch runs, and write nothing \
        (device)" begin
        backend = PottsDevices.device_backend()
        ninst() = length(PottsDevices.device_kernels())
        a = PottsDevices.device_array(ones(Float32, 300))
        b = PottsDevices.device_array(ones(Int32, 40))
        m = CorePotts._CompileOnly()
        CorePotts._stage!(m, cp_compile_write!, backend, 300, (a, 2.0f0))
        CorePotts._stage!(m, cp_compile_write!, backend, 40, (b, Int32(5)))
        @test length(m.jobs) == 2
        PottsDevices.device_sync()
        n0 = ninst()
        CorePotts._compile!(m, backend)
        PottsDevices.device_sync()
        @test ninst() == n0 + 2
        @test Array(a) == ones(Float32, 300) && Array(b) == ones(Int32, 40)
        CorePotts._stage!(CorePotts._Enqueue(), cp_compile_write!, backend, 300, (a, 2.0f0))
        CorePotts._stage!(
            CorePotts._Enqueue(), cp_compile_write!, backend, 40, (b, Int32(5))
        )
        PottsDevices.device_sync()
        # reused: no compile at the launch
        @test ninst() == n0 + 2
        @test Array(a) == fill(2.0f0, 300) && Array(b) == fill(Int32(5), 40)
        # negative control: a launch with new argument types compiles
        c = PottsDevices.device_array(ones(Float32, 8))
        CorePotts.Exec.launch!(backend, cp_compile_write!, 8, (c, Int32(7)))
        PottsDevices.device_sync()
        @test ninst() == n0 + 3
    end
end
