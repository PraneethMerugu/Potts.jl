# F3-23 (user ruling 2026-10-28; research/field-compiler/f3/F3-23-integer-cell-sums.md): cell
# sums are exact Int64 fixed-point sums, so a model that reads a cell average runs bitwise the
# same at every thread count (D-029). Two models, each run in this process (one thread) and in
# fresh processes at `-t 4` and `-t 8` (32³ and 200² lattices: above `HOST_GRAIN` sites):
#
# - the Jiang-like model of F3-18: the digest of `ocell = integral(o) / volume` after 2 MCS;
# - a Merks-like model whose energy thresholds a cell average (`cavg > θ` moves the target
#   volume): the digests of σ and `cavg` after 8 MCS.
#
# Each run also takes the host site passes one site per item (`CorePotts._CR_RUN_HOST`), so they
# are threaded at these sizes. Negative control in the same runs: `CorePotts._FLOAT_ATOMICS`
# restores the float atomics of the code before F3-23, and the averages then differ between one
# thread and several.
#
# Review r1 (M1, M2): the same for the other sums over sites, in Float32 with CheckerboardCPM and
# the device lifecycle on the CPU (as a device runs it): `surface` over a weighted lattice
# neighborhood after divisions, `cluster_surface` of weighted compartments that divide, and
# the compound writes of a `@convert` pass (`cs_r1_digests`). Their negative control is on
# ROCm (test/gpu.jl), where the float atomics differ run to run; here it only shows that the
# fixed-point path is the one taken.
using Potts, Test
using Potts: CorePotts
isdefined(Main, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))

const CS_THREADS_RUN = raw"""
using Potts
using Potts: CorePotts
include(joinpath(ENV["CS_TEST_DIR"], "cell_sums_models.jl"))
println("CSRUN ", Threads.nthreads(), " ", join(cs_digests(), " "))
println("CSR1 ", Threads.nthreads(), " ", join(first(cs_r1_digests()), " "))
"""
include(joinpath(@__DIR__, "cell_sums_models.jl"))

const CS_R1 = cs_r1_digests()          # review r1 (one thread), checked below and at 4 and 8 threads

@testset "F3-23: cell averages are bitwise the same at 1, 4 and 8 threads" begin
    @test 32^3 > CorePotts.Exec.HOST_GRAIN && 200^2 > CorePotts.Exec.HOST_GRAIN
    one = cs_digests()
    @test Threads.nthreads() == 1
    run(t) = split(strip(readchomp(addenv(`$(Base.julia_cmd()) --startup-file=no -t $t --project=$(Base.active_project()) -e $CS_THREADS_RUN`,
        "CS_TEST_DIR" => @__DIR__))))
    for t in (4, 8)
        out = run(t)
        i = findlast(==("CSRUN"), out)
        @test parse(Int, out[i + 1]) == t
        got = out[(i + 2):end]
        # fixed point: ocell, σ and cavg equal one thread's, with the default runs and with
        # runs of one site (threaded site passes)
        @test got[1:3] == one[1:3] && got[4:6] == one[1:3]
        # negative control (float atomics): an average differs from one thread's
        @test got[7:9] != one[7:9]
        # review r1: weighted surfaces, cluster surfaces, `@convert` writes
        j = findlast(==("CSR1"), out)
        @test parse(Int, out[j + 1]) == t && out[(j + 2):(j + 8)] == first(CS_R1)
    end
    @test one[4:6] == one[1:3]                                           # the run length changes no bit
end

@testset "F3-23 r1: weighted surfaces, cluster surfaces and @convert writes" begin
    r1, (nw, nc) = CS_R1                                                 # (at 4 and 8 threads: above)
    @test nw > 100 && nc > 10                                            # both models divide
    @test first(cs_r1_digests()) == r1
    # review r2 (S1): the host lifecycle planner adds the same integer units as the device
    # lifecycle, so the CPU's default path gives the same bits (weighted surface after 441
    # divisions, compartments after 34 cluster divisions). Control: with float atomics the
    # host's float recompute and the device lifecycle's float deltas differ.
    @test first(cs_r1_digests(; host = true)) == r1
    ch, cd = first(cs_r1_digests(; ctl = true, host = true)), first(cs_r1_digests(; ctl = true))
    @test ch[1] == cd[1] && ch[2] != cd[2] && ch[4] != cd[4]
    # the trackers against a recount from σ, with a tolerance: copies add the float weights and
    # divisions their integer units, so a weighted tracker and a recount differ in the last
    # bits (`_weight_units`); rtol 1e-5 is a few Float32 ulps of the sum
    f0 = CorePotts._FORCE_DEVICE_LIFECYCLE[]
    CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
    try
        pw = PottsProblem(CsWSurf(; name = :w), cs_wsurf_op(), (0, 80); T = Float32, seed = 7, capacity = 2000)
        u = solve(pw, CheckerboardCPM(); save_start = false).u[end]
        S = CorePotts.recompute_surface(Array(u.σ), pw.lattice, CorePotts.relation(CS_W, pw.lattice), length(u.cell.volume))
        @test Array(u.cell.surface) ≈ S rtol = 1e-5
        pc = PottsProblem(CsWComp(; name = :c), cs_wcomp_op(), (0, 40); T = Float32, seed = 7, capacity = 2000)
        c = solve(pc, CheckerboardCPM(); save_start = false).u[end]
        @test Array(c.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(c.σ), Array(c.cell.cluster), pc.lattice, CS_W) rtol = 1e-5
    finally
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = f0
    end
    # review r2 (N4): a state saved before the compound writes' scratch (no `#cv_w*` columns)
    # runs after `remake`, which adds them; its result equals the fresh problem's
    pv = PottsProblem(CsConv(; name = :v), cs_conv_op(), (0, 30); T = Float32, seed = 7, capacity = 8)
    u0 = pv.u0
    old = CorePotts.CPMState(u0.σ, NamedTuple(k => v for (k, v) in pairs(u0.cell) if !startswith(String(k), "#cv_w")),
        u0.site, u0.model, u0.history)
    @test !haskey(old.cell, Symbol("#cv_wsum"))
    qv = remake(pv; u0 = old)
    @test haskey(qv.u0.cell, Symbol("#cv_wsum")) && size(qv.u0.cell[Symbol("#cv_wsum")], 1) == 2
    sv = solve(qv, CheckerboardCPM(); save_start = false).u[end]
    @test cs_bits(sv.model.tot) == r1[6]
    # review r3 (N2): `reinit!` with the cell columns in another order at the same capacity says
    # so (it said "cell capacity 8, got 8"); a capacity that differs keeps its words
    integ = init(pv, CheckerboardCPM())
    ks = collect(keys(u0.cell))
    swapped = CorePotts.CPMState(u0.σ, NamedTuple(k => u0.cell[k] for k in [ks[2]; ks[1]; ks[3:end]]), u0.site, u0.model,
        u0.history)
    err = try
        reinit!(integ, swapped); ""
    catch e
        e.msg
    end
    @test occursin("the cell arrays are in another order: $(ks[1]), $(ks[2])", err) && !occursin("cell capacity", err) ||
          (println("r3 N2: ", err); false)
    big = PottsProblem(CsConv(; name = :v), cs_conv_op(), (0, 30); T = Float32, seed = 7, capacity = 9).u0
    @test_throws "cell capacity 8, got 9" reinit!(integ, big)
    # the float atomics give other sums (the path is taken): surface, cluster surface, tot, V_target
    ctl = first(cs_r1_digests(; ctl = true))
    @test ctl[2] != r1[2] && ctl[4] != r1[4] && ctl[6] != r1[6] && ctl[7] != r1[7]
end
