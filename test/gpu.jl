# Symbolic models on Metal (POTTS_GPU=metal): generated code with T = Float32 runs on the
# device with exact trackers and CPU-equivalent statistics (D-029).
using Metal
using Statistics: mean, var

@testset "symbolic models on Metal" begin
    backend = MetalBackend()
    σ, kinds = graner_state()
    prob = symbolic_graner_problem(; nmcs = 40, T = Float32)
    u = solve(prob, CheckerboardCPM(); backend).u[end]
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
    xs = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:8]
    ys = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 11:18]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8)
    @info "symbolic Graner H, CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
    @test abs(t) < 4
    for (label, p) in (
            ("wortel", PottsProblem(WORTEL, [ownership => (s = zeros(Int32, 8, 8); s[2:3, 2:3] .= 1; s[6:7, 6:7] .= 2; s),
                kind => [1, 1]], (0, 20); T = Float32)),
            ("merks", PottsProblem(MERKS, [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [1]], (0, 20); T = Float32)),
            ("openvt", PottsProblem(MONOLAYER, [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [1]], (0, 10);
                T = Float32, capacity = 8)))
        v = solve(p, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test v.cell.volume == [count(==(c), v.σ) for c in eachindex(v.cell.volume)]
    end
    σs = zeros(Int32, 60, 30); σs[5:10, 12:17] .= 1; σs[40:45, 12:17] .= 2
    sp = PottsProblem(Spring(; name = :spring), [ownership => σs, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000); T = Float32)
    ds = [CorePotts.centroid_distance(Float64, solve(remake(sp; seed), CheckerboardCPM(); backend).u[end].cell, sp.lattice, 1, 2) for seed in 1:4]
    @test abs(sum(ds) / 4 - 12.0) < 2.5
    # model-scope updates run as a single-item kernel on the device
    σc, kc = two_kind_blocks()
    cp = PottsProblem(Census(; name = :census), [ownership => σc, kind => kc], (0, 5); T = Float32)
    uc = solve(cp, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
    @test uc.model.total[1] == sum(uc.site.act)
    @test uc.model.ndark[1] == count(c -> kc[c] == 1 && uc.cell.volume[c] > 0, eachindex(kc))
    # compartments: cluster energies, trackers and cluster division on the device
    σk, kk, gk = compartment_state()
    kp = PottsProblem(Compartments(; name = :comp), [ownership => σk, kind => kk, cluster => gk], (0, 4); T = Float32)
    uk = solve(kp, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
    cl = Array(uk.cell.cluster)
    @test Array(uk.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(uk.σ), cl)
    @test Array(uk.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(uk.σ), cl, kp.lattice, Moore(1); T = Float32)
    @test count(>(0), Array(uk.cell.volume)) == 36
    # components: the batched RK4 cell-ODE kernel in Float32 on the device
    σo = zeros(Int32, 20, 20); σo[3:7, 3:7] .= 1; σo[12:16, 12:16] .= 2
    po = remake(PottsProblem(component_model(Potts.RK4(substeps = 2)), [ownership => σo, kind => [:A, :B]], (0, 10); T = Float32);
        p = [:T => 1.0f-9])
    yo = solve(po, CheckerboardCPM(); backend).u[end].cell.decay₊y_c
    @test Array(yo)[1:2] ≈ fill(Float32((1 - 0.15 + 0.15^2 / 2 - 0.15^3 / 6 + 0.15^4 / 24)^20), 2) rtol = 1e-5
    # centroid/displacement: moment trackers read in the proposal and cell kernels
    σm = zeros(Int32, 48, 48); σm[22:26, 22:26] .= 1
    pm = remake(PottsProblem(Persistent(; name = :pm), [ownership => σm, kind => [1]], (0, 20); T = Float32);
        p = [:μ => 1000.0f0])
    um = solve(pm, CheckerboardCPM(); backend).u[end]
    cm = CorePotts.centroid(Float64, map(Array, um.cell), pm.lattice, 1)
    @test Array(um.cell.cx)[1] ≈ cm[1] && Array(um.cell.cy)[1] ≈ cm[2]
    @test Array(um.cell.volume)[1] == count(==(1), Array(um.σ))
    # setters write through to device memory
    im = init(pm, CheckerboardCPM(); backend)
    im[:px] = [0.25]; im.ps[:μ] = 0.0
    @test Array(im.state.cell.px) == Float32[0.25] && im.p.μ === 0.0f0 && im[:px] == Float32[0.25]
    # history rings: pushed and read on the device
    σl = zeros(Int32, 8, 8); σl[3:5, 3:5] .= 1
    ul = solve(PottsProblem(Lags(; name = :l), [ownership => σl, kind => [1]], (0, 7); T = Float32),
        CheckerboardCPM(); backend).u[end]
    @test Array(ul.model.lag3) == Float32[4] && all(==(-1), Array(ul.site.wlag))
    # integral(x): atomic per-cell reductions on the device
    σi = zeros(Int32, 20, 20); σi[3:6, 3:6] .= 1; σi[12:15, 12:15] .= 2
    wi = [Float32(i + j) / 40 for i in 1:20, j in 1:20]
    ui = solve(PottsProblem(Integrals(; name = :i), [ownership => σi, kind => [1, 1], :w => wi], (0, 5); T = Float32),
        CheckerboardCPM(); backend).u[end]
    σh = Array(ui.σ)
    @test Array(ui.cell.mass) ≈ [sum(wi[σh .== k]) for k in 1:2]
end
