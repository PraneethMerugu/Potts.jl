using Test
import LocalMath
import KernelAbstractions

struct TrigonometricStageDomain end
struct TrigonometricStageEvaluator{F}
    operation::F
end
@inline function (evaluator::TrigonometricStageEvaluator)(item::Int32, reads, parameters)
    angle = something(reads[1][1].value)
    return (value = LocalMath.UniqueValue(evaluator.operation(angle)),)
end

function trigonometric_stage_contracts(array_type, ::Type{T} = Float32) where {T}
    return @testset "real trigonometric stage publication ($T)" begin
        angles = T[-100, -3, -0.25, -0.0, 0, 0.25, 1, 3, 100]
        space = LocalMath.Space(TrigonometricStageDomain, length(angles))
        input = LocalMath.Field(space, T)
        output = LocalMath.Field(space, T)
        relation = LocalMath.IdentityRelation(space)
        for operation in (sin, cos)
            stage = LocalMath.Stage(
                space, (angle = LocalMath.Access(input, relation),),
                (
                    LocalMath.Publication(
                        (LocalMath.FieldPublication(output, relation, LocalMath.PublicationValue(:value)),),
                        LocalMath.Unique(T),
                    ),
                ),
                LocalMath.Evaluator(TrigonometricStageEvaluator(operation), ()),
                LocalMath.Control(),
                LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :trigonometric_publication),
            )
            values = array_type(angles)
            destination = array_type(fill(T(17), length(angles)))
            prepared = LocalMath.prepare(
                LocalMath.LocalLaw(stage), input => values, output => destination;
                backend = KernelAbstractions.get_backend(values),
            )
            @test Array(destination) == fill(T(17), length(angles))
            wait(LocalMath.execute!(prepared))
            # Higher-precision host arithmetic is a numerical oracle, not a
            # second stage evaluator or a device bitwise-transcendental claim.
            reference = setprecision(BigFloat, 128) do
                T.(operation.(BigFloat.(angles)))
            end
            @test Array(destination) ≈ reference rtol = 4eps(T) atol = 4eps(T)
            @test isequal(Array(values), angles)
        end
    end
end
