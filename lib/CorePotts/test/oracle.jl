# Exact transition-matrix oracle (ROADMAP M1.4b): the `Oracle` module is in oracle_core.jl
# (the Potts group reuses it against generated models).
include("oracle_core.jl")

@testset "exact transition oracle (M1.4b)" begin
    Jk = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, kind 1, kind 2
    dims = (3, 2)
    vn = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    moore = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
    tiny = Oracle.Tiny(dims, vn, moore, [1, 2], Jk, 1.0, 2.0, 4.0)
    σ0 = Int8[1, 1, 0, 2, 2, 0]                    # column-major 3×2

    lat = Lattice(dims; boundary = Closed())
    p = (; J = SMatrix{3, 3}(Jk), λ = 1.0, V0 = 2.0, T = 4.0)
    prob = CPMProblem(GG, initial_state(reshape(Int32.(σ0), dims), [1, 2]), lat, (0, 2), p)

    @test sort(sort.(Oracle.color_classes(tiny, 2))) ==
          sort([sort([CorePotts.linear_index(lat, CorePotts.color_site(c, j))
                      for j in 1:CorePotts.ncolorsites(c)]) for c in colors(lat, 2)])

    R = 40_000
    for (alg, step) in ((SequentialCPM(), Oracle.sequential_mcs),
            (CheckerboardCPM(), (m, d) -> Oracle.checkerboard_mcs(m, d, 2)))
        ex = Oracle.exact(tiny, σ0, 2, step)
        @test sum(values(ex)) ≈ 1
        counts = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
            counts[σ] = get(counts, σ, 0) + 1
        end
        d, noise = Oracle.tv(ex, counts, R)
        z = Oracle.chi2_z(ex, counts, R)
        @info "oracle" alg = nameof(typeof(alg)) states = length(ex) tv = d expected_tv = noise z
        @test z < 4.5                   # a correct sampler fails this about once in 3·10⁵ runs
        @test d < 2noise
    end

    # power: the test rejects a mutant (T = 4 → 5) at this sample size
    ex = Oracle.exact(tiny, σ0, 2, (m, d) -> Oracle.checkerboard_mcs(m, d, 2))
    mutant = remake(prob; p = merge(p, (; T = 5.0)))
    counts = Dict{Vector{Int8}, Int}()
    for seed in 1:R
        σ = vec(Int8.(solve(remake(mutant; seed), CheckerboardCPM()).u[end].σ))
        counts[σ] = get(counts, σ, 0) + 1
    end
    z = Oracle.chi2_z(ex, counts, R)
    @info "oracle mutant (T = 5 against exact T = 4)" z
    @test z > 4.5
end

@testset "preflight rejects an undeclared read radius" begin
    lat = Lattice((20, 20))
    σ, k = blocks((20, 20), 3)
    wide = CPMProblem(GG, initial_state(σ, k), lat, (0, 1), gg_params();
        contact = NeighborOrder(3))
    @test_throws ArgumentError init(wide, CheckerboardCPM())
    @test init(wide, SequentialCPM()) isa PottsIntegrator
    ok = CPMFunction(gg_delta_H; temperature = gg_temperature, footprint = Footprint(read = 2))
    @test solve(remake(wide; f = ok), CheckerboardCPM()).retcode == ReturnCode.Success
end
