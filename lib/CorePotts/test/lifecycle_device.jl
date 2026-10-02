# The device lifecycle planner (D-089, `src/lifecycle_device.jl`) runs on every GPU backend.
# Here it runs on the CPU backend, in both of its forms, (`_FORCE_DEVICE_LIFECYCLE`), so the lifecycle, compartment
# and relationship tests below check its kernels (scan-based id allocation, deferral,
# cluster units and planes, links, trackers, the P6.0d mask counts) without a GPU, against
# the same oracles as the host planner. By design (D-089), the device planner's statistics
# are exact only at host read points (saves, `integ.u`, `checkpoint`, the end of `solve!`).

@testset "device lifecycle planner on the CPU backend" begin
    CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
    try
        # the planner is really the device one (negative control: off by default)
        lat = Lattice((20, 20))
        σ = zeros(Int32, 20, 20); σ[5:12, 5:10] .= 1
        st = with_capacity(initial_state(σ, Int32[1]; cell = init_moments(σ, lat, 1)), 3)
        once(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? EVENT_DIVIDE : EVENT_NONE
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
            lifecycle = Lifecycle(once))
        prob = PottsProblem(f, st, lat, (0, 4), gg_params())
        integ = init(prob, CheckerboardCPM(); save_start = false, save_end = false)
        @test integ.lcache.device isa CorePotts.DeviceLifecycle
        @test integ.lcache.device.fused! !== nothing                 # small: one fused launch
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        @test init(prob, CheckerboardCPM()).lcache.device === nothing
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        # statistics live on the device and are folded at a host read point
        step!(integ); step!(integ)                             # MCS 1: the division
        @test count(>(0), Array(integ.state.cell.volume)) == 2  # applied at once …
        @test integ.stats.lifecycle.divisions == 0             # … counted at the next read
        u = integ.u
        @test integ.stats.lifecycle.divisions == 1 && count(>(0), u.cell.volume) == 2
        integ.u                                                # folding twice adds nothing
        @test integ.stats.lifecycle.divisions == 1
        # deterministic: two runs of a growing population agree exactly (random planes)
        σg = zeros(Int32, 40, 40); σg[15:24, 15:24] .= 1
        lg = Lattice((40, 40))
        stg = with_capacity(initial_state(σg, Int32[1]; cell = init_moments(σg, lg, 1)), 16)
        fg = CPMFunction(gg_delta_H; temperature = gg_temperature,
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> st.cell.volume[c] >= 60 ? EVENT_DIVIDE : EVENT_NONE;
                normal = random_plane))
        pg = PottsProblem(fg, stg, lg, (0, 30), merge(gg_params(), (; V0 = 70.0)))
        g, h = (solve(pg, CheckerboardCPM(); saveat = 5) for _ in 1:2)
        @test g.stats.lifecycle.divisions == h.stats.lifecycle.divisions >= 2
        @test all(i -> g.u[i].σ == h.u[i].σ && g.u[i].cell == h.u[i].cell, eachindex(g.u))
        # both forms: the fused one-workgroup kernel (these problems are small) and one
        # kernel per stage (what larger problems use)
        @testset "$form" for (form, sites) in (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
            fuse = CorePotts.FUSE_SITES[]
            CorePotts.FUSE_SITES[] = sites
            try
                integ = init(prob, CheckerboardCPM())
                @test (integ.lcache.device.fused! === nothing) == (form == "staged")
                include("lifecycle.jl")
                include("compartments.jl")
                include("relationships.jl")
            finally
                CorePotts.FUSE_SITES[] = fuse
            end
        end

        # A daughter rule that links mother and daughter: the newborn's links are cleaned
        # (and its columns copied) for every cell before any rule runs, so the rule's link
        # survives exactly as on the host planner (a race before: the link was dropped)
        @testset "a divide! rule's links ($form)" for (form, sites) in (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
            fuse = CorePotts.FUSE_SITES[]
            CorePotts.FUSE_SITES[] = sites
            try
                link_md!(st, p, ctx, key, mcs, parent, daughter) = (add_link!(st.cell, parent, daughter); nothing)
                stl = with_capacity(initial_state(σ, Int32[1]; cell = merge(init_moments(σ, lat, 1), empty_links(2, 1))), 3)
                fl = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
                    lifecycle = Lifecycle(once; divide! = link_md!))
                probl = PottsProblem(fl, stl, lat, (0, 3), gg_params())
                CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
                host = solve(probl, CheckerboardCPM())
                CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
                dev = solve(probl, CheckerboardCPM())
                @test host.stats.lifecycle.divisions == dev.stats.lifecycle.divisions == 1
                @test linked(host.u[end].cell, 1, 2) && linked(host.u[end].cell, 2, 1)
                @test dev.u[end].cell.links == host.u[end].cell.links
                @test dev.u[end].σ == host.u[end].σ
            finally
                CorePotts.FUSE_SITES[] = fuse
                CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
            end
        end

        # A cell too large for the Int32 moment scratch (here: a lowered bound) does not
        # divide: the division is deferred and counted, the state stays exact, the host warns
        # once per report, later reads and `reinit!` do not throw (the count is not sticky)
        @testset "moment-scratch bound ($form)" for (form, sites) in (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
            fuse = CorePotts.FUSE_SITES[]
            lim = CorePotts._SCRATCH_LIMIT[]
            CorePotts.FUSE_SITES[] = sites
            try
                # cell 1 (8 × 6 sites: m2 about its anchor 264 in x, 152 in y) alone; cluster
                # {2, 3} with root 2 (a small and a large member) as a unit
                σs = zeros(Int32, 30, 30); σs[3:10, 3:8] .= 1
                σs[15:16, 15:16] .= 2; σs[20:27, 15:20] .= 3
                trs(st, p, ctx, key, mcs, c) = mcs != 1 ? EVENT_NONE : c == 1 ? EVENT_DIVIDE :
                                               c == 2 ? EVENT_DIVIDE_CLUSTER : EVENT_NONE
                latS = Lattice((30, 30))
                cells = merge(init_moments(σs, latS, 3), init_clusters(σs, Int32[1, 2, 2], latS))
                sts = with_capacity(initial_state(σs, Int32[1, 1, 1]; cell = cells), 8)
                fs = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
                    lifecycle = Lifecycle(trs))
                probs = PottsProblem(fs, sts, latS, (0, 3), gg_params())
                CorePotts._SCRATCH_LIMIT[] = 20                  # the two large cells exceed it
                integ = init(probs, CheckerboardCPM(); save_start = false, save_end = false)
                step!(integ); step!(integ); step!(integ)
                u = @test_logs (:warn, r"Int32 scratch") integ.u
                @test integ.stats.lifecycle.divisions == 0
                @test integ.stats.lifecycle.deferred == 2         # cell 1 and cluster 2
                @test u.σ == σs && u.cell.volume[1:3] == Int32[48, 4, 48]
                @test u.cell.m1[:, 1:3] == cells.m1 && u.cell.m2[:, 1:3] == cells.m2
                @test_logs integ.u                                # reported once
                reinit!(integ)
                @test integ.stats.lifecycle.deferred == 0
                # control: within the bound, both divide (cell 1 alone, the cluster as a unit)
                CorePotts._SCRATCH_LIMIT[] = typemax(Int32)
                integ = init(probs, CheckerboardCPM(); save_start = false, save_end = false)
                step!(integ); step!(integ); step!(integ)
                u = integ.u
                @test integ.stats.lifecycle.divisions == 3 && integ.stats.lifecycle.deferred == 0
                @test u.cell.volume == Int32[count(==(c), u.σ) for c in 1:8]
                @test same_moments(u, latS, 8, CheckerboardCPM())
            finally
                CorePotts.FUSE_SITES[] = fuse
                CorePotts._SCRATCH_LIMIT[] = lim
            end
        end
    finally
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
    end
end
