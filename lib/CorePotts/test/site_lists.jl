# D-251: site lists (the boundary list, a frozen mask's mobile sites) and the counters of the
# mask refreshes are Int32 up to 2³¹ − 1 sites and Int64 above. Lattices that large do not
# fit a test machine, so `_FORCE_WIDE_SITES` takes the Int64 width on small ones: every run
# must then be bit-identical to its Int32 run, since the width changes storage only.

@testset "site lists widen above 2³¹ − 1 sites (D-251)" begin
    @test CorePotts.site_index_type(typemax(Int32)) === Int32
    @test CorePotts.site_index_type(Int64(typemax(Int32)) + 1) === Int64
    function forced(f, wide::Bool; device = false)
        CorePotts._FORCE_WIDE_SITES[] = wide
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = device
        try
            return f()
        finally
            CorePotts._FORCE_WIDE_SITES[] = false
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        end
    end
    S = 10
    rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
    σ, kinds = blocks((30, 30), 5)
    plain = PottsProblem(CPMFunction(gg_delta_H; temperature = gg_temperature), initial_state(σ, kinds),
        Lattice((30, 30)), (0, 15), gg_params())
    # (problem, algorithm, device lifecycle): a mask that a transition and a removal change
    # (the host refresh's counters, the mobile-site list, the device planner's counters), a
    # static mask, and a lattice without one
    cases = [(fk_problem(fk_flip(S); kind = fk_swap), SequentialCPM(), false),
        (fk_problem(fk_flip(S); kind = fk_swap), SequentialCPM(; skip_interior = true), false),
        (fk_problem(rm2), SequentialCPM(), false),
        (fk_problem(rm2), SequentialCPM(; skip_interior = true), false),
        (fk_problem(fk_flip(S); kind = fk_swap), CheckerboardCPM(), false),
        (fk_problem(fk_flip(S); kind = fk_swap), CheckerboardCPM(), true),
        (fk_problem(rm2), CheckerboardCPM(), true),
        (fk_problem(fk_flip(S); kind = fk_swap, sys = nothing), SequentialCPM(; skip_interior = true), false),
        (plain, SequentialCPM(; skip_interior = true), false)]
    for (prob, alg, device) in cases, seed in 1:2
        p = remake(prob; seed)
        narrow = forced(() -> solve(p, alg; saveat = 1), false; device)
        wide = forced(() -> solve(p, alg; saveat = 1), true; device)
        @test narrow.retcode == ReturnCode.Success && wide.retcode == ReturnCode.Success
        @test all(i -> wide.u[i].σ == narrow.u[i].σ && wide.u[i].cell.kind == narrow.u[i].cell.kind, eachindex(narrow.u))
        @test wide.stats.attempts == narrow.stats.attempts && wide.stats.accepted == narrow.stats.accepted
        @test wide.stats.refreshes == narrow.stats.refreshes
        # the widths reach every list and counter the run has; unforced, they stay Int32
        for (w, T) in ((true, Int64), (false, Int32))
            integ = forced(() -> init(p, alg), w; device)
            mob = integ.ctx.mobility
            mob isa CorePotts.MaskMobility && @test eltype(mob.sites) === T
            integ.cache isa CorePotts.BoundaryCache &&
                @test eltype(integ.cache.list) === T && eltype(integ.cache.pos) === T
            integ.mscratch === nothing || @test eltype(integ.mscratch.host) === T
            dl = integ.lcache === nothing ? nothing : integ.lcache.device
            dl === nothing || @test eltype(dl.dv.mcnt) === T
            @test device == (dl !== nothing)
        end
    end
end
