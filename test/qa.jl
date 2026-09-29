# Static gates on generated code: type stability (JET) of the solve loop, a warm MCS
# without allocation (AllocCheck), and package hygiene (Aqua).
using JET, AllocCheck, Aqua

@testset "QA: generated models are type stable and allocation free ($name)" for (name, make) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 5)),
        ("wortel", symbolic_wortel_problem), ("merks", symbolic_merks_problem),
        ("openvt", symbolic_openvt_problem),
        ("compartments", () -> (c = compartment_state(); PottsProblem(Compartments(; name = :comp),
            [ownership => c[1], kind => c[2], cluster => c[3]], (0, 5)))),
        ("components", () -> (σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2;
            PottsProblem(component_model(Potts.RK4(substeps = 2)), [ownership => σ, kind => [:A, :B]], (0, 5)))))
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
