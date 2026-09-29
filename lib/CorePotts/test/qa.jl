# Static gates: type stability (JET) and allocation freedom (AllocCheck) of the hot paths.
using JET, AllocCheck

@testset "QA" begin
    σ0, kinds0 = blocks((36, 36), 5)
    prob = CPMProblem(GG, initial_state(σ0, kinds0), Lattice((36, 36)), (0, 20), gg_params())
    integ = init(prob, SequentialCPM(); save_start = false)
    args = (integ.state, integ.f, integ.p, integ.ctx, integ.law, integ.key, 0)
    @test_opt target_modules = (CorePotts,) CorePotts.sequential_mcs!(args...)
    @test_opt target_modules = (CorePotts,) step!(integ)
    @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))

    cinteg = init(prob, CheckerboardCPM(); save_start = false)
    cargs = (cinteg.state, cinteg.cache, cinteg.f, cinteg.p, cinteg.ctx, cinteg.law,
        cinteg.key, 0)
    @test_opt target_modules = (CorePotts,) CorePotts.checkerboard_mcs!(cargs...)
    @test_opt target_modules = (CorePotts,) step!(cinteg)
    # `init` is not gated: resolving a relation fixes its length K at run time, which is a
    # deliberate one-time function barrier before the (gated) hot loop.

    # the energy primitives are allocation free on their own
    prop = Proposal(1, 2, (1, 1), 1, Int32(1), Int32(0))
    @test isempty(check_allocs(gg_delta_H, typeof.((integ.state, integ.p, prop, integ.ctx))))
end
