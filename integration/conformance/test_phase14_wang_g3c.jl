include("phase14_wang_fixture.jl")

@testset "Phase 14 Wang G3-C fail-closed backend contract" begin
    fixture = _wang_runtime_fixture(32)
    coupled = fixture.coupled
    @test CorePotts._wang_g3c_state_matches(
        coupled.state)
    @test CorePotts._wang_g3c_plan_matches(
        coupled.plan)
    @test CorePotts._coupled_tree_backend_valid(
        coupled.plan, coupled.state,
        coupled.potts.plan.capabilities)

    cpu_report = CorePotts.coupled_backend_report(
        coupled.plan, coupled.state,
        coupled.potts.plan.capabilities;
        potts = coupled.potts)
    @test cpu_report.executable
    @test all(row ->
        row.status === :qualified_reference,
        cpu_report.rows)

    # A family label cannot qualify CPU storage as a GPU runtime. This
    # proves the Wang recognizer fails closed before any mutation even when
    # every advertised capability bit is otherwise present.
    alleged_metal = CorePotts.BackendCapabilities(
        CorePotts.MetalFamily,
        CorePotts.QualifiedBackend,
        true, true, false, true, (v"1.0.0",))
    alleged_report = CorePotts.coupled_backend_report(
        coupled.plan, coupled.state, alleged_metal;
        potts = coupled.potts)
    @test !alleged_report.executable
    @test all(row -> row.status === :unsupported,
        alleged_report.rows)
    @test_throws CorePotts.UnsupportedCoupledCapabilities CorePotts.preflight_coupled(
            coupled.plan, coupled.state,
            alleged_metal; potts = coupled.potts)

    @test CorePotts.SciMLBase.step!(coupled) ===
        coupled
    @test coupled.mcs == 1
    @test fixture.field.time == 1.0f0
    @test CorePotts.capture_checkpoint(coupled).mcs == 1
    coupled.checkpoint_stable = false
    @test_throws ArgumentError CorePotts.capture_checkpoint(coupled)
end
