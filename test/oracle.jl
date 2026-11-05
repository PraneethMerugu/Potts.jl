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
    # periodic axes need length ≥ 3 (shorter ones alias ±1 offsets and are rejected); on 3 × 3
    # the checkerboard is one block of one-site sub-regions (64 phases per MCS)
    for (dims, σ0, nmcs, alg, step) in (
            ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, SequentialCPM(; proposal = Moore(1)), Oracle.sequential_mcs),
            ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, CheckerboardCPM(; proposal = Moore(1)), (m, d) -> Oracle.block_mcs(m, d, 64)))
        tiny = Oracle.Tiny(dims, moore, moore, [1, 2], Jk, 1.0, 2.0, 4.0, true)
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = dims),
            [ownership => reshape(Int32.(σ0), dims), kind => [:dark, :light], :J => Jk, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
            (0, nmcs))
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
