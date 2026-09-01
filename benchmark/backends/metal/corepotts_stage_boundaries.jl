using Test
import Metal
import CorePotts
import LocalMath

function _metal_model_assignment_descriptor()
    schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :metal_model_signal),
        v"1.0.0",
        :model,
        Float32,
        (1,),
        1,
        :structure_of_arrays,
        :provided_or_zero,
        :shape_and_finite,
        :logical,
        :preserve,
        :declared,
        :bounded_write,
        :adapt_storage,
        :copy,
        :logical_copy,
        :qualified,
        true,
    )
    handle = only(CorePotts.StateLayout([schema]).entries).handle
    read_model = CorePotts.OperationExpression(
        CorePotts.operation_callable(
            Val(:model_bound_state_value), v"1.0.0"),
        CorePotts.StateExpression(handle),
    )
    value = CorePotts.OperationExpression(
        CorePotts.operation_callable(Val(:add), v"1.0.0"),
        read_model,
        CorePotts.LiteralExpression(1.0f0),
    )
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(value),
        CorePotts.ModelAssignmentEffect(handle),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (handle,),
            (handle,),
            CorePotts.EmptyFootprint(),
            CorePotts.ModelFootprint(),
            CorePotts.ExclusiveWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
        1,
    )
    return descriptor
end

@testset "CorePotts model-stage compiler executes through LocalMath on Metal" begin
    Metal.allowscalar(false)
    backend = Metal.MetalBackend()
    descriptor = _metal_model_assignment_descriptor()
    gate_space = LocalMath.Space(CorePotts._CheckerboardStageGateDomain, 1)
    external_gate = LocalMath.Field(gate_space, Bool)
    declaration = CorePotts._compile_model_assignment_law(
        descriptor,
        (:metal_model_assignment,),
        nothing,
        external_gate,
        Float32,
    )
    model_storage = Metal.MtlArray(Float32[2])
    status_storage = Metal.MtlArray(
        CorePotts.ProgramStatus[CorePotts.ProgramStatus()])
    prepared = LocalMath.prepare(
        declaration.law,
        only(declaration.fields) => model_storage,
        declaration.scratch => LocalMath.Allocate(0.0f0),
        declaration.status_field => status_storage,
        declaration.initial_gate => LocalMath.Allocate(false),
        declaration.refreshed_gate => LocalMath.Allocate(false),
        external_gate => Metal.MtlArray(Bool[true]);
        backend,
    )
    wait(LocalMath.execute!(prepared; parameters = (mcs = Int64(1),)))
    @test Array(model_storage) == Float32[3]
    @test Array(status_storage)[1].code === CorePotts.ProgramStatusSuccess
end
