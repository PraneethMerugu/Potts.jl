# Static gates on generated code: type stability (JET) of the solve loop, a warm MCS
# without allocation (AllocCheck), and package hygiene (Aqua).
using JET, AllocCheck, Aqua

@testset "QA: generated models are type stable and allocation free ($name)" for (name, make) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 5)),
        ("wortel", symbolic_wortel_problem), ("merks", symbolic_merks_problem),
        ("openvt", symbolic_openvt_problem))
    prob = make()
    integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
    step!(integ)
    @test_opt target_modules = (CorePotts, Potts) step!(integ)
    args = (integ.state, integ.kf, integ.p, integ.ctx, integ.law, integ.key, 1)
    @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))
    cinteg = init(prob, CheckerboardCPM(; proposal = Moore(1)); save_start = false)
    step!(cinteg)
    @test_opt target_modules = (CorePotts, Potts) step!(cinteg)
end

@testset "QA: Aqua" begin
    Aqua.test_all(Potts; ambiguities = false, deps_compat = (; check_extras = false))
end
