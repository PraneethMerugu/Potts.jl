using CommonSolve
using SciMLBase

import ProcessBigraphs: BoundedCartesianFieldProblem,
    IndependentCustomFieldAdapter, independent_custom_field_declaration,
    sciml_field_adapter, sciml_field_declaration, field_engine_snapshot,
    managed_engine_runtime, advance_managed_engine!, phase16_checkpoint,
    restore_phase16_checkpoint, decode_phase16_checkpoint

function p16f_problem(
    values;
    diffusion=0.1,
    decay=0.03,
    tick=0.01,
    substeps=1,
    id="phase16f-field",
)
    scale = TimeScale(1, 100, :second)
    BoundedCartesianFieldProblem(
        id,
        values;
        diffusion,
        decay,
        tick_duration=tick,
        substeps_per_tick=substeps,
        time_scale=scale,
    )
end

function p16f_managed(declaration, problem)
    managed_engine_runtime(
        declaration,
        LogicalTime(problem.initial_tick, problem.time_scale);
        structural_epoch="field-epoch-0",
    )
end

function p16f_advance!(runtime, target, forcing)
    precision = eltype(forcing) === Float32 ? :float32 : :float64
    advance_managed_engine!(
        runtime,
        LogicalTime(target, runtime.logical_time.scale);
        reason=:scheduled_field_advance,
        inputs=(:forcing => forcing,),
        resource_authorization=(
            backend=:cpu,
            precision,
            residency=:host,
        ),
        expected_outputs=(:field_state,),
        expected_diagnostics=(:backend, :algorithm),
    )
end

function p16f_reference_step(problem, values, forcing)
    result = similar(values)
    dt = problem.tick_duration / problem.substeps_per_tick
    input = copy(values)
    for _ in 1:problem.substeps_per_tick
        for index in CartesianIndices(input)
            center = input[index]
            laplacian = zero(center)
            coordinates = Tuple(index)
            for axis in 1:ndims(input)
                low = Base.setindex(
                    coordinates,
                    mod1(coordinates[axis] - 1, size(input, axis)),
                    axis,
                )
                high = Base.setindex(
                    coordinates,
                    mod1(coordinates[axis] + 1, size(input, axis)),
                    axis,
                )
                laplacian += (
                    input[low...] + input[high...] - 2center
                ) / (problem.spacing[axis] * problem.spacing[axis])
            end
            result[index] = center + dt * (
                problem.diffusion * laplacian +
                forcing[index] - problem.decay * center)
        end
        input, result = result, input
    end
    input
end

function p16f_empty_serial_runtime()
    scale = TimeScale(1)
    composite = compile_composite(StaticComposite(
        BranchSchema(
            marker=LeafSchema(Int; default=0, update_law=:replace),
        ),
        Dict(),
        scale,
    ))
    executor = SerialExecutor(root_seed=1606)
    composite, executor, initialize_runtime(composite, executor)
end

@testset "Phase 16.F CPU SciML and independent custom adapters" begin
    initial = reshape(Float64.(1:20), 4, 5)
    forcing = reshape(range(0.0, 0.19; length=20), 4, 5)
    problem = p16f_problem(initial)
    sciml_declaration = sciml_field_declaration(problem)
    custom_declaration = independent_custom_field_declaration(problem)
    @test sciml_field_adapter(problem) isa
        Base.get_extension(
            ProcessBigraphs, :ProcessBigraphsSciMLExt).SciMLFieldAdapter
    @test sciml_declaration.capabilities.problem_envelopes ==
        ("sciml-odeproblem-periodic-cartesian-diffusion-decay",)
    @test custom_declaration.capabilities.problem_envelopes ==
        ("periodic-cartesian-diffusion-decay",)
    @test sciml_declaration.capabilities.replay_class === :exact
    @test custom_declaration.capabilities.replay_class === :exact
    @test sciml_declaration.capabilities.backends == (:cpu,)
    @test custom_declaration.capabilities.backends == (:cpu,)
    @test sciml_declaration.capabilities.boundary_kinds == (:periodic,)
    @test custom_declaration.capabilities.boundary_kinds == (:periodic,)

    sciml = p16f_managed(sciml_declaration, problem)
    custom = p16f_managed(custom_declaration, problem)
    expected = p16f_reference_step(problem, initial, forcing)
    sciml_result = p16f_advance!(sciml, 1, forcing)
    custom_result = p16f_advance!(custom, 1, forcing)
    @test field_engine_snapshot(sciml.instance) == expected
    @test field_engine_snapshot(custom.instance) == expected
    @test field_engine_snapshot(sciml.instance) ==
        field_engine_snapshot(custom.instance)
    @test sciml_result.outcome.diagnostics.algorithm ===
        :sciml_fixed_euler
    @test custom_result.outcome.diagnostics.algorithm ===
        :independent_custom_euler
    @test sciml.logical_time == custom.logical_time ==
        LogicalTime(1, problem.time_scale)

    initial3 = reshape(Float32.(1:60), 3, 4, 5)
    forcing3 = fill(0.02f0, size(initial3))
    problem3 = p16f_problem(
        initial3; diffusion=0.05f0, decay=0.01f0, id="phase16f-3d")
    sciml3 = p16f_managed(sciml_field_declaration(problem3), problem3)
    custom3 = p16f_managed(
        independent_custom_field_declaration(problem3), problem3)
    p16f_advance!(sciml3, 1, forcing3)
    p16f_advance!(custom3, 1, forcing3)
    expected3 = p16f_reference_step(problem3, initial3, forcing3)
    @test field_engine_snapshot(sciml3.instance) == expected3
    @test field_engine_snapshot(custom3.instance) == expected3

    constant = fill(2.0, 4, 4)
    constant_problem = p16f_problem(
        constant; diffusion=0.2, decay=0.1, substeps=2,
        id="phase16f-decay")
    decay = p16f_managed(
        sciml_field_declaration(constant_problem), constant_problem)
    p16f_advance!(decay, 1, zeros(size(constant)))
    dt = 0.01 / 2
    analytic_discrete = 2.0 * (1 - 0.1dt)^2
    @test all(value -> isapprox(
            value, analytic_discrete; rtol=2eps(Float64), atol=0),
        field_engine_snapshot(decay.instance))
end

@testset "Phase 16.F continuation, failure, restart, and capability matrix" begin
    initial = reshape(Float64.(1:12), 3, 4)
    forcings = [fill(0.01 * tick, size(initial)) for tick in 1:4]
    problem = p16f_problem(initial; id="phase16f-restart")
    declarations = (
        sciml_field_declaration(problem),
        independent_custom_field_declaration(problem),
    )
    composite, executor, serial = p16f_empty_serial_runtime()
    for declaration in declarations
        baseline = p16f_managed(declaration, problem)
        for tick in 1:4
            p16f_advance!(baseline, tick, forcings[tick])
        end
        expected = field_engine_snapshot(baseline.instance)
        for cut in 0:3
            prefix = p16f_managed(declaration, problem)
            for tick in 1:cut
                p16f_advance!(prefix, tick, forcings[tick])
            end
            checkpoint_value = phase16_checkpoint(
                serial; managed_engines=(prefix,))
            restored = restore_phase16_checkpoint(
                composite,
                executor,
                decode_phase16_checkpoint(
                    encode_checkpoint(checkpoint_value));
                engine_declarations=(declaration,),
            )
            resumed = only(restored.engines).second
            for tick in (cut + 1):4
                p16f_advance!(resumed, tick, forcings[tick])
            end
            @test field_engine_snapshot(resumed.instance) == expected
            @test resumed.logical_time ==
                LogicalTime(4, problem.time_scale)
            @test resumed.publication_version == UInt64(4)
        end

        rejected = p16f_managed(declaration, problem)
        before = field_engine_snapshot(rejected.instance)
        @test_throws ProcessBigraphError advance_managed_engine!(
            rejected,
            LogicalTime(1, problem.time_scale);
            inputs=(:forcing => forcings[1],),
            resource_authorization=(
                backend=:cpu,
                precision=:float64,
                residency=:host,
            ),
            expected_outputs=(:field_state,),
            expected_diagnostics=(:backend, :algorithm),
            authorize=(candidate, invocation) -> false,
        )
        @test field_engine_snapshot(rejected.instance) == before
        @test rejected.logical_time ==
            LogicalTime(0, problem.time_scale)
    end

    failing_problem = p16f_problem(
        zeros(Float64, 3, 4); id="phase16f-failure")
    for declaration in (
        sciml_field_declaration(failing_problem),
        independent_custom_field_declaration(failing_problem),
    )
        runtime = p16f_managed(declaration, failing_problem)
        @test_throws ProcessBigraphError p16f_advance!(
            runtime, 1, fill(-1000.0, 3, 4))
        @test field_engine_snapshot(runtime.instance) ==
            zeros(Float64, 3, 4)
        @test runtime.logical_time ==
            LogicalTime(0, failing_problem.time_scale)
        @test !isnothing(runtime.last_failure)
    end

    @test_throws ProcessBigraphError BoundedCartesianFieldProblem(
        "unstable",
        zeros(Float64, 3, 4);
        diffusion=100.0,
        tick_duration=1.0,
        time_scale=TimeScale(1),
    ) |> ProcessBigraphs._bounded_field_stability
    declaration = sciml_field_declaration(problem)
    runtime = p16f_managed(declaration, problem)
    @test_throws ProcessBigraphError advance_managed_engine!(
        runtime,
        LogicalTime(1, problem.time_scale);
        inputs=(:forcing => forcings[1],),
        resource_authorization=(
            backend=:metal,
            precision=:float64,
            residency=:device,
        ),
        expected_outputs=(:field_state,),
        expected_diagnostics=(:backend, :algorithm),
    )
end
