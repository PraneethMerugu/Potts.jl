using Test
import KernelAbstractions
import LocalMath

include("semantic_oracle_support.jl")

@testset "independent tiny-domain semantic oracles" begin
    result = run_semantic_oracle_suite(identity, KernelAbstractions.CPU())
    for law in (:unique, :reduce, :resolve, :collect, :fold)
        witness = getproperty(result, law)
        @test all(==(witness.oracle), witness.results)
        @test witness.facts[1].lowering == witness.facts[2].lowering
        @test witness.facts[1].executors == witness.facts[2].executors
        @test witness.facts[1].laws == witness.facts[2].laws
    end
end

@testset "fallible laws preserve destinations and suppress successors" begin
    candidate = run_semantic_failure_barrier(
        identity, KernelAbstractions.CPU())
    collect = run_collect_failure_barrier(identity, KernelAbstractions.CPU())
    fold = run_fold_failure_barrier(identity, KernelAbstractions.CPU())
    @test all(result -> result.failure isa LocalMath.LocalMathValidationError,
        (candidate, collect, fold))
    @test candidate.conflicted == Int32[-7]
    @test candidate.successor == fill(Int32(-9), 2)
    @test collect.count == Int32[0]
    @test collect.successor == fill(Int32(-9), 2)
    @test fold.accumulator == Int32[-7]
    @test fold.successor == fill(Int32(-9), 2)
end
