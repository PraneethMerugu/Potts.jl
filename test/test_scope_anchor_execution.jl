include("fixtures/scoped_quantities.jl")

@testset "scoped anchors evaluate the selected identity" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM()), domain_kind in (:cell, :site)
        @testset "$algorithm $domain_kind" begin
            _scoped_anchor_contract(algorithm, CPUBackend(), domain_kind)
        end
    end
end
