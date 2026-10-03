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

        # A form whose first launch fails (on a device: its workgroup exceeds what the
        # kernel's pipeline allows; simulated here) hands over to the next one, fused →
        # one kernel per stage → host planner, with the results of that form
        @testset "a form that cannot launch hands over" begin
            ref = solve(pg, CheckerboardCPM(); saveat = 5)                  # fused
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
            host = solve(pg, CheckerboardCPM(); saveat = 5)
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
            fuse = CorePotts.FUSE_SITES[]
            try
                for (fault, sites, form, want) in ((CorePotts._FORM_FUSED, fuse, CorePotts._FORM_STAGED, ref),
                    (CorePotts._FORM_STAGED, 0, CorePotts._FORM_HOST, host))
                    CorePotts._LAUNCH_FAULT[] = fault
                    CorePotts.FUSE_SITES[] = sites
                    integ = init(pg, CheckerboardCPM(); save_start = false, save_end = false)
                    @test_logs (:warn, r"cannot launch") step!(integ)
                    @test integ.lcache.device.form[] == form
                    @test_logs step!(integ)                                   # once
                    sol = @test_logs (:warn, r"cannot launch") solve(pg, CheckerboardCPM(); saveat = 5)
                    @test sol.stats.lifecycle.divisions == want.stats.lifecycle.divisions >= 2
                    @test all(i -> sol.u[i].σ == want.u[i].σ && sol.u[i].cell == want.u[i].cell, eachindex(want.u))
                end
            finally
                CorePotts._LAUNCH_FAULT[] = 0
                CorePotts.FUSE_SITES[] = fuse
            end
        end

        # The staged form failing midway (D-108, `_STAGED_FAULT_AFTER`): after the trigger or
        # the planner it hands over, counting the kernels that ran; after the partition
        # (which writes σ) the state is not consistent, and the failure is rethrown
        @testset "the staged form failing midway" begin
            fuse = CorePotts.FUSE_SITES[]
            CorePotts.FUSE_SITES[] = 0
            try
                launches = Dict{Int, Int}()
                for k in (1, 2)
                    CorePotts._STAGED_FAULT_AFTER[] = k
                    integ = init(pg, CheckerboardCPM(); save_start = false, save_end = false)
                    @test_logs (:warn, r"cannot launch") step!(integ)
                    D = integ.lcache.device
                    @test D.form[] == CorePotts._FORM_HOST && D.enqueued[] == k
                    launches[k] = integ.stats.launches
                end
                @test launches[2] == launches[1] + 1             # the planner kernel is counted
                CorePotts._STAGED_FAULT_AFTER[] = CorePotts._STAGED_PARTITION
                integ = init(pg, CheckerboardCPM(); save_start = false, save_end = false)
                err = try
                    step!(integ)
                    nothing
                catch e
                    e
                end
                @test err isa CorePotts._StagedFailedMidway && err.enqueued == CorePotts._STAGED_PARTITION
                @test occursin("no longer consistent", sprint(showerror, err))
                @test integ.lcache.device.form[] == CorePotts._FORM_STAGED       # not handed over
            finally
                CorePotts._STAGED_FAULT_AFTER[] = 0
                CorePotts.FUSE_SITES[] = fuse
            end
        end

        # A daughter rule that links mother and daughter: the newborn's links are cleaned
        # (and its columns copied) for every cell before any rule runs, so the rule's link
        # survives exactly as on the host planner (a race before: the link was dropped)
        @testset "a divide! rule's links ($form)" for (form, sites) in
                                                       (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
            fuse = CorePotts.FUSE_SITES[]
            CorePotts.FUSE_SITES[] = sites
            try
                link_md!(st, p, ctx, key, mcs, parent, daughter) = (add_link!(st.cell, parent, daughter); nothing)
                cl = merge(init_moments(σ, lat, 1), empty_links(2, 1))
                stl = with_capacity(initial_state(σ, Int32[1]; cell = cl), 3)
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

        # `Lifecycle.before` (F1, D-101): a cell update run with the trigger of each cell, in
        # one work item on the device (one launch for both), on its own on the host planner
        # and on MCS the lifecycle does not check. Oracle: the same update as an after-MCS
        # `CellPhase` and no `before`, in every form (and through a failing form's handover)
        @testset "Lifecycle.before with the trigger" begin
            σb = zeros(Int32, 30, 30); σb[4:11, 4:11] .= 1; σb[18:25, 18:25] .= 2
            latb = Lattice((30, 30))
            stb = with_capacity(initial_state(σb, Int32[1, 1]; cell = merge(init_moments(σb, latb, 2), (; g = [0.0, 2.0]))), 8)
            tick!(st, p, ctx, key, mcs, c) = (st.cell.volume[c] > 0 && (st.cell.g[c] += 1.0); nothing)
            ripe(st, p, ctx, key, mcs, c) = st.cell.g[c] >= 4.0 ? EVENT_DIVIDE : EVENT_NONE    # its own `g`
            restart!(st, p, ctx, key, mcs, parent, daughter) = (st.cell.g[parent] = 0.0; st.cell.g[daughter] = 0.0; nothing)
            make(fused, every) = PottsProblem(CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
                    phases = Phases(after_mcs = fused ? () : (CellPhase(tick!),)),
                    lifecycle = Lifecycle(ripe; divide! = restart!, every, before = fused ? tick! : nothing)),
                stb, latb, (0, 9), gg_params())
            fuse = CorePotts.FUSE_SITES[]
            try
                for every in (1, 2), (form, device, sites, fault) in (("host", false, fuse, 0), ("fused", true, fuse, 0),
                    ("staged", true, 0, 0), ("fused → staged", true, fuse, CorePotts._FORM_FUSED),
                    ("staged → host", true, 0, CorePotts._FORM_STAGED))
                    CorePotts.FUSE_SITES[] = sites
                    # the reference runs the planner that ends up running (the host planner's
                    # trackers may differ from the device planner's in representation)
                    CorePotts._FORCE_DEVICE_LIFECYCLE[] = device && fault != CorePotts._FORM_STAGED
                    ref = solve(make(false, every), CheckerboardCPM(); saveat = 1)
                    CorePotts._FORCE_DEVICE_LIFECYCLE[] = device
                    CorePotts._LAUNCH_FAULT[] = fault
                    sol = fault == 0 ? solve(make(true, every), CheckerboardCPM(); saveat = 1) :
                          @test_logs (:warn, r"cannot launch") solve(make(true, every), CheckerboardCPM(); saveat = 1)
                    CorePotts._LAUNCH_FAULT[] = 0
                    @test sol.stats.lifecycle.divisions == ref.stats.lifecycle.divisions >= 3
                    @test all(i -> sol.u[i].σ == ref.u[i].σ && sol.u[i].cell == ref.u[i].cell, eachindex(ref.u))
                    # one launch fewer per checked MCS where the device lifecycle runs it
                    fault == 0 && @test sol.stats.launches == ref.stats.launches - (device ? cld(9, every) : 0)
                end
            finally
                CorePotts.FUSE_SITES[] = fuse
                CorePotts._LAUNCH_FAULT[] = 0
                CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
            end
        end
    finally
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
    end
end
