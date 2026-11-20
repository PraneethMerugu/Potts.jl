# Cell sums are exact Int64 fixed-point sums, so a model that reads a cell average runs bitwise the
# same at every thread count (D-029). Two models, each run in this process (one thread) and in
# fresh processes at `-t 4` and `-t 8` (32³ and 200² lattices: above `HOST_GRAIN` sites):
#
# - the Jiang-like model: the digest of `ocell = integral(o) / volume` after 2 MCS;
# - a Merks-like model whose energy thresholds a cell average (`cavg > θ` moves the target
#   volume): the digests of σ and `cavg` after 8 MCS.
#
# Each run also takes the host site passes one site per item (`CorePotts._CR_RUN_HOST`), so they
# are threaded at these sizes. Negative control in the same runs: `CorePotts._FLOAT_ATOMICS`
# restores the float atomics of the code before the fixed-point sums, and the averages then differ between one
# thread and several.
#
# The same for the other sums over sites, in Float32 with CheckerboardCPM and
# the device lifecycle on the CPU (as a device runs it): `surface` over a weighted lattice
# neighborhood after divisions, `cluster_surface` of weighted compartments that divide, and
# the compound writes of a `@convert` pass (`cs_site_sum_digests`). Their negative control is on
# ROCm (gpu_fields_tests.jl), where the float atomics differ run to run; here it only shows that the
# fixed-point path is the one taken.

@testsetup module CellSumsSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test

using Potts: CorePotts

isdefined(@__MODULE__, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))

include(joinpath(@__DIR__, "cell_sums_models.jl"))


const CS_SITE_SUMS = cs_site_sum_digests()
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "cell averages are bitwise the same across run lengths (1 thread)" setup = [CellSumsSetup] tags = [:potts, :cell_sums] begin
    @testset "cell averages are bitwise the same across run lengths (1 thread)" begin
        @test 32^3 > CorePotts.Exec.HOST_GRAIN && 200^2 > CorePotts.Exec.HOST_GRAIN
        one = cs_digests()
        # the run length changes no bit; negative control (float atomics) differs
        @test one[4:6] == one[1:3]
        @test one[7:9] != one[1:3]
    end
end

@testitem "fixed-point cell averages are bitwise the same at 1 and 4 threads (in-process)" setup = [CellSumsSetup] tags = [:multithreaded] begin
    Threads.nthreads() >= 4 ||
        error("This testitem requires at least 4 Julia threads (got $(Threads.nthreads())); run GROUP=Multithreaded with `julia -t 4`")
    @testset "fixed-point cell averages are bitwise the same at 1 and 4 threads (in-process)" begin
        @test 32^3 > CorePotts.Exec.HOST_GRAIN && 200^2 > CorePotts.Exec.HOST_GRAIN
        one_run = cs_digests1(false)
        four_run = cs_digests1(false; run = 1)
        @test four_run == one_run
        # negative control: float atomics differ from fixed-point
        ctl_run = cs_digests1(true; run = 1)
        @test ctl_run != one_run
    end
end

@testitem "threaded CheckerboardCPM Repeat invariants, Global veto, and negative control" setup = [CellSumsSetup] tags = [:multithreaded] begin
    Threads.nthreads() >= 4 ||
        error("This testitem requires at least 4 Julia threads (got $(Threads.nthreads())); run GROUP=Multithreaded with `julia -t 4`")
    @testset "threaded CheckerboardCPM Repeat invariants, Global veto, and negative control" begin
        @test cs_threaded_cb_invariants() == (true, true, true, true, true)
        gv = cs_threaded_cb_global_veto_check(CsThreadedCBGlobalVeto; threads = true)
        @test gv.nonzero_cells && gv.committed > 0
        @test gv.over_grain
        @test gv.vol_ok
        @test gv.deferred > 0
        @test gv.one_piece_ok
        # negative control: removing the Global veto allows cells to fragment
        nv = cs_threaded_cb_global_veto_check(CsThreadedCBNoVeto; threads = true)
        @test nv.nonzero_cells && nv.committed > 0
        @test nv.over_grain
        @test !nv.one_piece_ok && nv.max_pieces > 1
    end
end

@testitem "weighted surfaces, cluster surfaces and @convert writes" setup = [CellSumsSetup] tags = [:potts, :cell_sums] begin
    @testset "weighted surfaces, cluster surfaces and @convert writes" begin
        r1, (nw, nc) = CS_SITE_SUMS                                                 # (at 4 and 8 threads: above)
        @test nw > 100 && nc > 10                                            # both models divide
        @test first(cs_site_sum_digests()) == r1
        # The host lifecycle planner adds the same integer units as the device
        # lifecycle, so the CPU's default path gives the same bits (weighted surface after 441
        # divisions, compartments after 34 cluster divisions). Control: with float atomics the
        # host's float recompute and the device lifecycle's float deltas differ.
        @test first(cs_site_sum_digests(; host = true)) == r1
        ch, cd = first(cs_site_sum_digests(; ctl = true, host = true)), first(cs_site_sum_digests(; ctl = true))
        @test ch[1] == cd[1] && ch[2] != cd[2] && ch[4] != cd[4]
        # the trackers against a recount from σ, with a tolerance: copies add the float weights and
        # divisions their integer units, so a weighted tracker and a recount differ in the last
        # bits (`_weight_units`); rtol 1e-5 is a few Float32 ulps of the sum
        f0 = CorePotts._FORCE_DEVICE_LIFECYCLE[]
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        try
            pw = PottsProblem(CsWSurf(; name = :w), cs_wsurf_op(), (0, 80); T = Float32, seed = 7, capacity = 2000)
            u = solve(pw, CheckerboardCPM(); save_start = false).u[end]
            S = CorePotts.recompute_surface(Array(u.ownership), pw.lattice, CorePotts.relation(CS_W, pw.lattice), length(u.cell.volume))
            @test Array(u.cell.surface) ≈ S rtol = 1.0e-5
            pc = PottsProblem(CsWComp(; name = :c), cs_wcomp_op(), (0, 40); T = Float32, seed = 7, capacity = 2000)
            c = solve(pc, CheckerboardCPM(); save_start = false).u[end]
            @test Array(c.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(c.ownership), Array(c.cell.cluster), pc.lattice, CS_W) rtol = 1.0e-5
        finally
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = f0
        end
        # a state saved before the compound writes' scratch (no `#cv_w*` columns)
        # runs after `remake`, which adds them; its result equals the fresh problem's
        pv = PottsProblem(CsConv(; name = :v), cs_conv_op(), (0, 30); T = Float32, seed = 7, capacity = 8)
        u0 = pv.u0
        old = CorePotts.CPMState(
            u0.ownership, NamedTuple(k => v for (k, v) in pairs(u0.cell) if !startswith(String(k), "#cv_w")),
            u0.site, u0.model, u0.history
        )
        @test !haskey(old.cell, Symbol("#cv_wsum"))
        qv = remake(pv; u0 = old)
        @test haskey(qv.u0.cell, Symbol("#cv_wsum")) && size(qv.u0.cell[Symbol("#cv_wsum")], 1) == 2
        sv = solve(qv, CheckerboardCPM(); save_start = false).u[end]
        @test cs_bits(sv.model.tot) == r1[6]
        # `reinit!` with the cell columns in another order at the same capacity says
        # so (it said "cell capacity 8, got 8"); a capacity that differs keeps its words
        integ = init(pv, CheckerboardCPM())
        ks = collect(keys(u0.cell))
        swapped = CorePotts.CPMState(
            u0.ownership, NamedTuple(k => u0.cell[k] for k in [ks[2]; ks[1]; ks[3:end]]), u0.site, u0.model,
            u0.history
        )
        err = try
            reinit!(integ, swapped); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        big = PottsProblem(CsConv(; name = :v), cs_conv_op(), (0, 30); T = Float32, seed = 7, capacity = 9).u0
        @test_throws ArgumentError reinit!(integ, big)
        # the float atomics give other sums (the path is taken): surface, cluster surface, tot, V_target
        ctl = first(cs_site_sum_digests(; ctl = true))
        @test ctl[2] != r1[2] && ctl[4] != r1[4] && ctl[6] != r1[6] && ctl[7] != r1[7]
    end
end
