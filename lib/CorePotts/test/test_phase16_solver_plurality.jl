import ProcessBigraphs as PB
using CommonSolve

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
            (:backend, :precision) : (:backend, :algorithm),
    )
end

function p16f_cross_snapshot(runtime, native::Bool)
    native ?
        CorePotts.process_bigraph_native_field_snapshot(runtime) :
        PB.field_engine_snapshot(runtime.instance)
end

@testset "Phase 16.F native SciML custom cross-adapter evidence" begin
    for initial in (
        reshape(Float64.(1:20), 4, 5),
        reshape(Float32.(1:60), 3, 4, 5),
    )
        T = eltype(initial)
        scale = PB.TimeScale(1, 100, :second)
        diffusion = T(0.1)
        decay = T(0.03)
        problem = PB.BoundedCartesianFieldProblem(
            "phase16f-cross",
            initial;
            diffusion,
            decay,
            tick_duration=T(0.01),
            time_scale=scale,
        )
        native_adapter = CorePotts.CorePottsNativeFieldAdapter(
            :phase16f_cross,
            initial;
            diffusion,
            decay,
            tick_duration=T(0.01),
            time_scale=scale,
            block_size=64,
        )
        native = CorePotts.process_bigraph_native_field_runtime(
            "phase16f-native",
            native_adapter;
            structural_epoch="field-epoch-0",
        )
        sciml_declaration = PB.sciml_field_declaration(problem)
        custom_declaration =
            PB.independent_custom_field_declaration(problem)
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
        for tick in 1:4
            forcing = fill(T(0.01 * tick), size(initial))
            p16f_cross_advance!(native, tick, forcing, true)
            p16f_cross_advance!(sciml, tick, forcing, false)
            p16f_cross_advance!(custom, tick, forcing, false)
        end
        native_values = p16f_cross_snapshot(native, true)
        sciml_values = p16f_cross_snapshot(sciml, false)
        custom_values = p16f_cross_snapshot(custom, false)
        @test sciml_values == custom_values
        tolerance = T === Float32 ? 16eps(Float32) : 16eps(Float64)
        @test isapprox(
            native_values, sciml_values;
            rtol=tolerance, atol=tolerance)
        @test native.logical_time == sciml.logical_time ==
            custom.logical_time == PB.LogicalTime(4, scale)
        @test native.publication_version == sciml.publication_version ==
            custom.publication_version == UInt64(4)
    end
end
