import ProcessBigraphs as PB
using OrdinaryDiffEqTsit5: Tsit5

include(joinpath(
    @__DIR__, "..", "..", "ProcessBigraphs", "test", "fixtures",
    "independent_custom_field_adapter.jl"))
using .IndependentCustomFieldAdapterFixture

function p16f_cross_advance!(runtime, target, forcing, native::Bool)
    PB.advance_managed_engine!(
        runtime,
        PB.LogicalTime(target, runtime.logical_time.scale);
        reason=:scheduled_field_advance,
        inputs=(:forcing => forcing,),
        resource_authorization=(
            backend=:cpu,
            precision=eltype(forcing) === Float32 ? :float32 : :float64,
            residency=:host,
        ),
        expected_outputs=(:field_state,),
        expected_diagnostics=native ?
            (:backend, :precision) : (:backend, :algorithm, :retcode),
    )
end

function p16f_cross_snapshot(runtime, native::Bool)
    native ?
        CorePotts.process_bigraph_native_field_snapshot(runtime) :
        PB.field_engine_snapshot(runtime.instance)
end

function p16f_cross_exact(initial, diffusion, decay, tick_duration, ticks)
    offset = eltype(initial)(2)
    amplitude = maximum(initial) - offset
    mode = 2
    n = size(initial, 1)
    eigenvalue = -4sin(pi * mode / n)^2
    rate = diffusion * eigenvalue - decay
    duration = tick_duration * ticks
    result = similar(initial)
    for index in CartesianIndices(result)
        result[index] =
            offset * exp(-decay * duration) +
            amplitude * exp(rate * duration) *
            cos(2pi * mode * (index[1] - 1) / n)
    end
    result
end

@testset "Phase 16.F native real-solver custom cross-adapter evidence" begin
    for T in (Float64, Float32)
        dimensions = T === Float64 ? (12, 10) : (12, 10, 4)
        initial = Array{T}(undef, dimensions)
        for index in CartesianIndices(initial)
            initial[index] = T(2) +
                T(0.2) * cos(T(4pi * (index[1] - 1) / dimensions[1]))
        end
        scale = PB.TimeScale(1, 100, :second)
        diffusion = T(0.1)
        decay = T(0.03)
        tick_duration = T(0.01)
        problem = PB.BoundedCartesianFieldProblem(
            "phase16f-cross",
            initial;
            diffusion,
            decay,
            tick_duration,
            time_scale=scale,
        )
        native_adapter = CorePotts.CorePottsNativeFieldAdapter(
            :phase16f_cross,
            initial;
            diffusion,
            decay,
            tick_duration,
            time_scale=scale,
            block_size=64,
        )
        native = CorePotts.process_bigraph_native_field_runtime(
            "phase16f-native",
            native_adapter;
            structural_epoch="field-epoch-0",
        )
        sciml_declaration = PB.sciml_field_declaration(
            problem,
            Tsit5();
            algorithm_id="ordinarydiffeq-tsit5",
            solver_options=(
                abstol=T === Float32 ? 1.0f-6 : 1.0e-11,
                reltol=T === Float32 ? 1.0f-6 : 1.0e-11,
            ),
        )
        custom_declaration =
            independent_custom_field_declaration(
                problem; substeps_per_tick=4)
        sciml = PB.managed_engine_runtime(
            sciml_declaration,
            PB.LogicalTime(0, scale);
            structural_epoch="field-epoch-0",
        )
        custom = PB.managed_engine_runtime(
            custom_declaration,
            PB.LogicalTime(0, scale);
            structural_epoch="field-epoch-0",
        )
        ticks = 8
        forcing = zeros(T, size(initial))
        for tick in 1:ticks
            p16f_cross_advance!(native, tick, forcing, true)
            p16f_cross_advance!(sciml, tick, forcing, false)
            p16f_cross_advance!(custom, tick, forcing, false)
        end
        native_values = p16f_cross_snapshot(native, true)
        sciml_values = p16f_cross_snapshot(sciml, false)
        custom_values = p16f_cross_snapshot(custom, false)
        exact = p16f_cross_exact(
            initial, diffusion, decay, tick_duration, ticks)
        native_error = maximum(abs.(native_values .- exact))
        sciml_error = maximum(abs.(sciml_values .- exact))
        custom_error = maximum(abs.(custom_values .- exact))
        tolerance = T === Float32 ? T(2.0e-5) : T(2.0e-10)
        @test sciml_error <= tolerance
        @test custom_error <= tolerance
        @test native_error >= sciml_error
        @test native_error >= custom_error
        @test isapprox(
            sciml_values, custom_values;
            rtol=tolerance, atol=tolerance)
        @test native.logical_time == sciml.logical_time ==
            custom.logical_time == PB.LogicalTime(ticks, scale)
        @test native.publication_version == sciml.publication_version ==
            custom.publication_version == UInt64(ticks)
    end
end
