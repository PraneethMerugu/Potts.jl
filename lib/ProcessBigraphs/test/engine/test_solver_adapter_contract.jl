using CommonSolve
using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase

import ProcessBigraphs: managed_engine_runtime, advance_managed_engine!,
    capture_logical_checkpoint, restore_logical_checkpoint,
    decode_logical_checkpoint

include(joinpath(
    @__DIR__, "..", "fixtures", "independent_custom_field_adapter.jl"))
using .IndependentCustomFieldAdapterFixture

function solver_adapter_problem(
    values;
    diffusion=0.1,
    decay=0.03,
    tick=0.01,
    scale=TimeScale(1, 100, :second),
    id="solver_adapter-field",
)
    BoundedCartesianFieldProblem(
        id,
        values;
        diffusion,
        decay,
        tick_duration=tick,
        time_scale=scale,
    )
end

function solver_adapter_sciml_declaration(
    problem;
    abstol=1.0e-10,
    reltol=1.0e-10,
    options=(;),
)
    sciml_field_declaration(
        problem,
        Tsit5();
        algorithm_id="ordinarydiffeq-tsit5",
        solver_options=merge((; abstol, reltol), options),
    )
end

function solver_adapter_managed(declaration, problem)
    managed_engine_runtime(
        declaration,
        LogicalTime(problem.initial_tick, problem.time_scale);
        structural_epoch="field-epoch-0",
    )
end

function solver_adapter_advance!(runtime, target, forcing)
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
        expected_diagnostics=(:backend, :algorithm, :retcode),
    )
end

function solver_adapter_empty_serial_runtime()
    scale = TimeScale(1)
    schema = BranchSchema(
        marker=LeafSchema(Int; default=0, update_law=:replace),
    )
    model = compose(:SolverAdapterEmptyRuntime, schema; scale) do _, _
    end
    composite = compile(model)
    executor = SerialExecutor(root_seed=1606)
    composite, executor, initialize_runtime(composite, executor)
end

function solver_adapter_fourier_fixture(
    ::Type{T}=Float64;
    dimensions=(12, 10),
    mode=2,
    offset=T(2),
    amplitude=T(0.2),
) where {T<:AbstractFloat}
    values = Array{T}(undef, dimensions)
    for index in CartesianIndices(values)
        values[index] = offset + amplitude *
            cos(T(2pi * mode * (index[1] - 1) / dimensions[1]))
    end
    values
end

function solver_adapter_fourier_exact(
    initial,
    diffusion,
    spacing,
    duration;
    mode=2,
    offset=2.0,
)
    n = size(initial, 1)
    eigenvalue = -4sin(pi * mode / n)^2 / spacing[1]^2
    amplitude = maximum(initial) - offset
    result = similar(initial)
    for index in CartesianIndices(result)
        result[index] = offset + amplitude *
            exp(diffusion * eigenvalue * duration) *
            cos(2pi * mode * (index[1] - 1) / n)
    end
    result
end

@testset "solver adapter real solver handoff and declaration provenance" begin
    initial = solver_adapter_fourier_fixture()
    problem = solver_adapter_problem(initial)
    declaration = solver_adapter_sciml_declaration(problem)
    adapter = declaration.adapter
    @test adapter.algorithm isa Tsit5
    @test adapter.algorithm_id == "ordinarydiffeq-tsit5"
    @test adapter.algorithm_package == "OrdinaryDiffEqTsit5"
    @test adapter.algorithm_package_uuid ==
        "b1df2697-797e-41e3-8120-5422d3b24e4a"
    @test v"2.0.0" <=
        VersionNumber(adapter.algorithm_package_version) < v"3.0.0"
    @test adapter.solver_options.abstol == 1.0e-10
    @test adapter.solver_options.reltol == 1.0e-10
    @test adapter.solver_options.save_everystep == false
    @test declaration.parameters.exact_target_policy ==
        "CommonSolve.step!(integrator, duration, true)"
    @test declaration.parameters.continuation_policy ==
        "reconstruct_each_invocation"
    @test declaration.capabilities.replay_class === :numerical
    @test declaration.capabilities.continuation_actions ==
        (:reconstruct, :reject)

    reordered = sciml_field_declaration(
        problem,
        Tsit5();
        algorithm_id="ordinarydiffeq-tsit5",
        solver_options=(reltol=1.0e-10, abstol=1.0e-10),
    )
    changed = solver_adapter_sciml_declaration(problem; reltol=1.0e-8)
    @test reordered.fingerprint == declaration.fingerprint
    @test changed.fingerprint != declaration.fingerprint
    @test_throws MethodError sciml_field_declaration(problem)
    @test_throws ArgumentError sciml_field_declaration(
        problem,
        Tsit5();
        algorithm_id="ordinarydiffeq-tsit5",
        solver_options=(
            abstol=1.0e-8,
            reltol=1.0e-8,
            callback=:undeclared_global_callback,
        ),
    )

    extension_source = read(joinpath(
        dirname(pathof(ProcessBigraphs)),
        "..", "ext", "ProcessBigraphsSciMLExt.jl"), String)
    fixture_source = read(joinpath(
        @__DIR__, "..", "fixtures",
        "independent_custom_field_adapter.jl"), String)
    @test !occursin("FixedEuler", extension_source)
    @test !occursin("P16SciMLSolution", extension_source)
    @test !occursin("function CommonSolve.solve", extension_source)
    @test !occursin("SciML", fixture_source)
    @test !occursin("_fixture_laplacian", extension_source)
end

@testset "solver adapter analytic and convergence evidence" begin
    constant = fill(2.0, 4, 4)
    scale = TimeScale(1, 10, :second)
    decay_problem = solver_adapter_problem(
        constant;
        diffusion=0.0,
        decay=10.0,
        tick=0.1,
        scale,
        id="solver_adapter-decay",
    )
    exact = 2exp(-1)

    loose = solver_adapter_managed(
        solver_adapter_sciml_declaration(
            decay_problem; abstol=1.0e-3, reltol=1.0e-3),
        decay_problem,
    )
    tight = solver_adapter_managed(
        solver_adapter_sciml_declaration(
            decay_problem; abstol=1.0e-11, reltol=1.0e-11),
        decay_problem,
    )
    solver_adapter_advance!(loose, 1, zeros(size(constant)))
    tight_result = solver_adapter_advance!(tight, 1, zeros(size(constant)))
    loose_error = maximum(abs.(
        field_engine_snapshot(loose.instance) .- exact))
    tight_error = maximum(abs.(
        field_engine_snapshot(tight.instance) .- exact))
    @test tight_error < loose_error
    @test tight_error < 1.0e-9
    @test tight_result.outcome.diagnostics.algorithm ===
        :ordinarydiffeq_tsit5
    @test occursin(
        "Success", tight_result.outcome.diagnostics.retcode)

    custom_errors = Float64[]
    for substeps in (1, 2, 4)
        declaration = independent_custom_field_declaration(
            decay_problem; substeps_per_tick=substeps)
        runtime = solver_adapter_managed(declaration, decay_problem)
        result = solver_adapter_advance!(runtime, 1, zeros(size(constant)))
        push!(custom_errors, maximum(abs.(
            field_engine_snapshot(runtime.instance) .- exact)))
        @test result.outcome.diagnostics.algorithm ===
            :independent_classical_rk4
        @test declaration.capabilities.replay_class === :numerical
    end
    @test custom_errors[2] < custom_errors[1] / 8
    @test custom_errors[3] < custom_errors[2] / 8

    initial = solver_adapter_fourier_fixture()
    spatial_problem = solver_adapter_problem(
        initial;
        diffusion=0.2,
        decay=0.0,
        id="solver_adapter-manufactured-fourier",
    )
    forcing = zeros(size(initial))
    target_tick = 20
    exact_spatial = solver_adapter_fourier_exact(
        initial,
        spatial_problem.diffusion,
        spatial_problem.spacing,
        target_tick * spatial_problem.tick_duration,
    )
    sciml = solver_adapter_managed(
        solver_adapter_sciml_declaration(spatial_problem), spatial_problem)
    custom = solver_adapter_managed(
        independent_custom_field_declaration(
            spatial_problem; substeps_per_tick=4),
        spatial_problem,
    )
    solver_adapter_advance!(sciml, target_tick, forcing)
    solver_adapter_advance!(custom, target_tick, forcing)
    @test isapprox(
        field_engine_snapshot(sciml.instance),
        exact_spatial;
        rtol=2.0e-9,
        atol=2.0e-9,
    )
    @test isapprox(
        field_engine_snapshot(custom.instance),
        exact_spatial;
        rtol=2.0e-8,
        atol=2.0e-8,
    )
end

@testset "solver adapter transaction, numerical restart, and capability matrix" begin
    initial = solver_adapter_fourier_fixture()
    forcings = [fill(0.01 * tick, size(initial)) for tick in 1:4]
    problem = solver_adapter_problem(initial; id="solver_adapter-restart")
    declarations = (
        solver_adapter_sciml_declaration(problem),
        independent_custom_field_declaration(problem),
    )
    composite, executor, serial = solver_adapter_empty_serial_runtime()
    for declaration in declarations
        @test declaration.capabilities.backends == (:cpu,)
        @test declaration.capabilities.boundary_kinds == (:periodic,)
        @test declaration.capabilities.replay_class === :numerical
        baseline = solver_adapter_managed(declaration, problem)
        for tick in 1:4
            solver_adapter_advance!(baseline, tick, forcings[tick])
        end
        expected = field_engine_snapshot(baseline.instance)
        for cut in 0:3
            prefix = solver_adapter_managed(declaration, problem)
            for tick in 1:cut
                solver_adapter_advance!(prefix, tick, forcings[tick])
            end
            checkpoint_value = capture_logical_checkpoint(
                serial; managed_engines=(prefix,))
            @test checkpoint_value.payload.aggregate_replay === :numerical
            restored = restore_logical_checkpoint(
                composite,
                executor,
                decode_logical_checkpoint(
                    encode_checkpoint(checkpoint_value));
                engine_declarations=(declaration,),
            )
            resumed = only(restored.engines).second
            for tick in (cut + 1):4
                solver_adapter_advance!(resumed, tick, forcings[tick])
            end
            @test isapprox(
                field_engine_snapshot(resumed.instance),
                expected;
                rtol=4eps(Float64),
                atol=4eps(Float64),
            )
            @test resumed.logical_time ==
                LogicalTime(4, problem.time_scale)
            @test resumed.publication_version == UInt64(4)
        end

        rejected = solver_adapter_managed(declaration, problem)
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
            expected_diagnostics=(:backend, :algorithm, :retcode),
            authorize=(candidate, invocation) -> false,
        )
        @test field_engine_snapshot(rejected.instance) == before
        @test rejected.logical_time ==
            LogicalTime(0, problem.time_scale)
    end

    failing_problem = solver_adapter_problem(
        zeros(Float64, 3, 4);
        diffusion=0.0,
        id="solver_adapter-failure",
    )
    for declaration in (
        solver_adapter_sciml_declaration(failing_problem),
        independent_custom_field_declaration(failing_problem),
    )
        runtime = solver_adapter_managed(declaration, failing_problem)
        @test_throws ProcessBigraphError solver_adapter_advance!(
            runtime, 1, fill(-1000.0, 3, 4))
        @test field_engine_snapshot(runtime.instance) ==
            zeros(Float64, 3, 4)
        @test runtime.logical_time ==
            LogicalTime(0, failing_problem.time_scale)
        @test !isnothing(runtime.last_failure)
    end

    declaration = solver_adapter_sciml_declaration(problem)
    runtime = solver_adapter_managed(declaration, problem)
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
        expected_diagnostics=(:backend, :algorithm, :retcode),
    )
end
