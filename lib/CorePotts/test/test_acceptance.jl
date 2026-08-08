function acceptance_descriptor_plan(value; role = CorePotts.ProposalDriveRole())
    descriptor = CorePotts.ProposalDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(value)),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        (),
        (),
        role,
        1,
    )
    launch = CorePotts.DescriptorLaunch(nothing, [descriptor], (), ())
    group = CorePotts.DescriptorGroup(launch, :unsplit)
    return CorePotts.DescriptorExecutionPlan(
        (group,),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[:acceptance_test],
        1,
        "acceptance-test-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

@testset "shared proposal acceptance law" begin
    neutral = CorePotts.ProposalEvaluation(0.0, 0.0, 0.0, 0.0, true)
    favorable = CorePotts.ProposalEvaluation(-1.0, 0.0, 0.0, 0.0, true)
    unfavorable = CorePotts.ProposalEvaluation(log(2.0), 0.0, 0.0, 0.0, true)
    constrained = CorePotts.ProposalEvaluation(-1.0, 0.0, 0.0, 0.0, false)
    biased = CorePotts.ProposalEvaluation(0.0, 0.0, 1.0, 0.0, true)
    modified = CorePotts.ProposalEvaluation(0.0, 0.0, 0.0, 1.0, true)

    @test CorePotts.proposal_acceptance_probability(neutral, 1.0) == 1.0
    @test CorePotts.proposal_acceptance_probability(favorable, 0.0) == 1.0
    @test CorePotts.proposal_acceptance_probability(unfavorable, 0.0) == 0.0
    @test CorePotts.proposal_acceptance_probability(unfavorable, 1.0) == 0.5
    @test CorePotts.proposal_acceptance_probability(constrained, 1.0) == 0.0
    @test CorePotts.proposal_acceptance_decision(
        unfavorable, 1.0, prevfloat(0.5)
    )
    @test !CorePotts.proposal_acceptance_decision(unfavorable, 1.0, 0.5)
    @test !CorePotts.proposal_acceptance_decision(
        unfavorable, 1.0, nextfloat(0.5)
    )

    for temperature in (-1.0, Inf, NaN)
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            neutral, temperature
        )
    end
    for evaluation in (
            CorePotts.ProposalEvaluation(NaN, 0.0, 0.0, 0.0, true),
            CorePotts.ProposalEvaluation(0.0, Inf, 0.0, 0.0, true),
            CorePotts.ProposalEvaluation(0.0, 0.0, NaN, 0.0, true),
            CorePotts.ProposalEvaluation(0.0, 0.0, 0.0, Inf, true),
        )
        result = CorePotts._proposal_acceptance_result(evaluation, 1.0)
        @test result.code === CorePotts.ProposalAcceptanceNonfinite
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            evaluation, 1.0
        )
    end
    for evaluation in (biased, modified)
        result = CorePotts._proposal_acceptance_result(evaluation, 0.0)
        @test result.code === CorePotts.ProposalAcceptanceZeroTemperatureDrive
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            evaluation, 0.0
        )
    end
end

@testset "acceptance preflight and engine failure atomicity" begin
    initial = test_initial()
    for temperature in (-1.0, Inf, NaN)
        program = test_program(
            CorePotts.SequentialProgramEngine(); temperature
        )
        @test_throws ArgumentError CorePotts.initialize_program(
            program, initial, Float64[], UInt64(1), UInt32(1)
        )
    end

    zero_bias_program = test_program(
        CorePotts.SequentialProgramEngine();
        temperature = 0.0,
        descriptor_plan = acceptance_descriptor_plan(0.0),
    )
    @test_throws ArgumentError CorePotts.initialize_program(
        zero_bias_program, initial, Float64[], UInt64(1), UInt32(1)
    )

    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(
            engine;
            temperature = 1.0,
            descriptor_plan = acceptance_descriptor_plan(NaN),
        )
        runtime = CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0xa77e), UInt32(1)
        )
        before = CorePotts.program_snapshot(runtime)
        CorePotts.advance_mcs!(runtime)
        after = CorePotts.program_snapshot(runtime)
        report = CorePotts.program_failure_report(runtime)
        @test CorePotts.program_failed(runtime)
        @test report.code === CorePotts.ProgramStatusAcceptance
        @test report.detail === CorePotts.LifecycleDetailAcceptanceNonfinite
        @test runtime.mcs == before.mcs == after.mcs == 0
        @test after.ownership == before.ownership
        @test after.cell_kinds == before.cell_kinds
        @test after.cell_generations == before.cell_generations
        @test after.trackers.values == before.trackers.values
        @test CorePotts.program_lifecycle_receipt(runtime) === nothing
        @test_throws ArgumentError CorePotts.program_checkpoint(runtime)
    end
end
