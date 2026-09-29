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
end
