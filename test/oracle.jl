# The generated Graner–Glazier model against the exact transition-matrix oracle (D-048): the
# oracle (lib/CorePotts/test/oracle_core.jl) re-derives each algorithm's Markov chain from its
# specification; the empirical end-state distribution of the generated code over many seeds
# must match it (χ² z-score and TV distance against sampling noise), and a mutant must not.
include(joinpath(@__DIR__, "..", "lib", "CorePotts", "test", "oracle_core.jl"))

@testset "generated Graner–Glazier against the exact oracle" begin
    Jk = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, dark, light
    moore = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
    R = 40_000
    function sample(prob, alg)
        counts = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
            counts[σ] = get(counts, σ, 0) + 1
        end
        return counts
    end
    # periodic axes need length ≥ 3 (shorter ones alias ±1 offsets and are rejected); the
    # periodic checkerboard needs even axes ≥ 4, too large to enumerate, so the checkerboard
    # is covered by the closed-lattice oracle in CorePotts, the port equality and the T → 0
    # monotonicity test in PottsModels
    for (dims, σ0, nmcs, alg, step) in (
            ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, SequentialCPM(; proposal = Moore(1)), Oracle.sequential_mcs),)
        tiny = Oracle.Tiny(dims, moore, moore, [1, 2], Jk, 1.0, 2.0, 4.0, true)
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = dims),
            [ownership => reshape(Int32.(σ0), dims), kind => [:dark, :light], :J => Jk, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
            (0, nmcs))
        if alg isa CheckerboardCPM                  # the oracle's coloring is the production one
            lat = prob.lattice
            @test sort(sort.(Oracle.color_classes(tiny, 2))) ==
                  sort([sort([CorePotts.linear_index(lat, CorePotts.color_site(c, j))
                              for j in 1:CorePotts.ncolorsites(c)]) for c in CorePotts.colors(lat, 2)])
        end
        ex = Oracle.exact(tiny, σ0, nmcs, step)
        counts = sample(prob, alg)
        d, noise = Oracle.tv(ex, counts, R)
        z = Oracle.chi2_z(ex, counts, R)
        @info "generated oracle" alg = nameof(typeof(alg)) dims states = length(ex) tv = d expected_tv = noise z
        @test z < 4.5
        @test d < 2noise
        # power: the same comparison rejects a model with T = 5
        zm = Oracle.chi2_z(ex, sample(remake(prob; p = [:T => 5.0]), alg), R)
        @info "generated oracle mutant (T = 5 against exact T = 4)" zm
        @test zm > 4.5
    end
end
