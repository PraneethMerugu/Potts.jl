# The device lifecycle planner (D-089, `src/lifecycle_device.jl`) runs on every GPU backend.
# Here it runs on the CPU backend (`_FORCE_DEVICE_LIFECYCLE`), so the lifecycle, compartment
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
        include("lifecycle.jl")
        include("compartments.jl")
        include("relationships.jl")
    finally
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
    end
end
