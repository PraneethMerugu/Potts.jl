# Bit-exactness of generated FV kernels:
# K coupled species, `u_k ← u_k + h (a_k Δu_k − b_k u_k + Σ_T p u_i u_j)` on a periodic
# grid. On identical inputs, outputs are compared as bit patterns (`-0.0 ≠ 0.0`) across
#   layout       K separate fields  vs  one K-component field (planes);
#   store order  interleaved stores vs  every value first, stores last;
#   fusion       the cost-model plan (fused) vs one launch per species (split);
#   wrapper      Exec's host executor vs the padded oracle loop (every `run_step!`), and
#                the device vs the host executor (problems_device.jl).
# Negative control: one input element one ulp up changes the output.

@testsetup module LF_problems_bit_exact
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/problems_bit_exact.jl")
include("../shared/export_all.jl")
end

@testitem "generated FV kernels are bit-exact (length(dims)D K=K T=T)" setup = [LF_problems_bit_exact] tags = [:latticefields, :problems] begin
    @testset "generated FV kernels are bit-exact ($(length(dims))D K=$K T=$T)" for (dims, K, T) in (
            ((24, 20), 4, 0), ((24, 20), 4, 3), ((24, 20), 8, 3), ((10, 9, 8), 4, 3), (
                (10, 9, 8), 8, 0,
            ),
        )
        X, P = inputs(dims, K), speciesP(K, T)
        one(layout; stages = LOWERING) = (
            b = build(species(dims, K, T; layout); stages); run_species(b..., X, P, layout)
        )
        ref = one(:sep)
        @test one(:slab) == ref                                           # layout
        @test one(:sep; stages = stores_last) == ref                      # store order
        @test one(:slab; stages = stores_last) == ref
        # fusion: the planner's fused launches vs one launch per species (same order semantics)
        s, fused = build(species(dims, K, T; kernels = :each))
        _, split = build(species(dims, K, T; kernels = :each); fuse = false)
        @test length(split.launches) == K && length(fused.launches) < K
        @test run_species(s, fused, X, P, :sep) == run_species(s, split, X, P, :sep)
        # negative control: one input element one ulp up
        Xp = deepcopy(X)
        j = length(X[1]) ÷ 2 + 7
        Xp[1][j] = nextfloat(Xp[1][j])
        b = build(species(dims, K, T))
        d = count(run_species(b..., Xp, P, :sep) .!= ref)
        @test d > 0
    end
end
