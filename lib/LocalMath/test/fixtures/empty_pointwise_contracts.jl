using Test
import LocalMath
import KernelAbstractions

struct EmptyPointwiseDomain end
struct EmptyPointwiseCopy end
@inline (::EmptyPointwiseCopy)(item::Int32, reads, parameters) =
    (value = LocalMath.UniqueValue(something(reads[1][1].value) + Int32(1)),)

function empty_pointwise_contracts(array_type)
    return @testset "empty pointwise domains retain storage and control diagnostics" begin
        for count in (0, 3), controlled_prefix in (false, true), sequence_length in (1, 2)
            space = LocalMath.Space(EmptyPointwiseDomain, count)
            input, middle, output = ntuple(_ -> LocalMath.Field(space, Int32), 3)
            relation = LocalMath.IdentityRelation(space)
            enabled = LocalMath.Parameter(:enabled, Bool)
            prefix = LocalMath.Parameter(:prefix, Int32; bounds = (Int32(0), Int32(max(count, 1))))
            parameters = controlled_prefix ? (enabled, prefix) : (enabled,)
            control = controlled_prefix ? LocalMath.Control(; gate = enabled, prefix) : LocalMath.Control(; gate = enabled)
            function stage(source, destination)
                LocalMath.Stage(
                    space, (value = LocalMath.Access(source, relation; required = true),),
                    (
                        LocalMath.Publication(
                            (LocalMath.FieldPublication(destination, relation, LocalMath.PublicationValue(:value)),),
                            LocalMath.Unique(Int32; coverage = LocalMath.PartialCoverage(), onempty = LocalMath.PreserveEmpty())
                        ),
                    ),
                    LocalMath.Evaluator(EmptyPointwiseCopy(), parameters), control,
                    LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :empty_pointwise_copy),
                )
            end
            # Empty views retain observable guard elements in their backing
            # buffers. An out-of-domain write must not corrupt those guards.
            input_storage = array_type(Int32[10, 20, 30, 41, 42])
            middle_storage = array_type(fill(Int32(71), 5))
            output_storage = array_type(fill(Int32(91), 5))
            law = sequence_length == 1 ? LocalMath.LocalLaw(stage(input, output)) :
                LocalMath.sequence(LocalMath.LocalLaw(stage(input, middle)), LocalMath.LocalLaw(stage(middle, output)))
            bindings = (input => view(input_storage, 1:count), output => view(output_storage, 1:count))
            sequence_length == 2 && (bindings = (bindings..., middle => view(middle_storage, 1:count)))
            prepared = LocalMath.prepare(
                law, bindings...;
                backend = KernelAbstractions.get_backend(input_storage)
            )
            @test all(segment -> segment.family === :direct_pointwise, LocalMath.inspect(prepared; level = :kernels).physical_segments)
            @test Array(middle_storage) == fill(Int32(71), 5)
            @test Array(output_storage) == fill(Int32(91), 5)
            arguments(value, prefix_value) = controlled_prefix ? (; enabled = value, prefix = Int32(prefix_value)) : (; enabled = value)
            wait(LocalMath.execute!(prepared; parameters = arguments(false, max(count, 1))))
            @test Array(output_storage) == fill(Int32(91), 5)
            wait(LocalMath.execute!(prepared; parameters = arguments(true, count)))
            @test Array(middle_storage)[1:count] == (sequence_length == 1 ? fill(Int32(71), count) : Int32[11, 21, 31][1:count])
            @test Array(output_storage)[1:count] == (Int32[10, 20, 30][1:count] .+ Int32(sequence_length))
            @test Array(middle_storage)[(count + 1):5] == fill(Int32(71), 5 - count)
            @test Array(output_storage)[(count + 1):5] == fill(Int32(91), 5 - count)
            if iszero(count) && controlled_prefix
                failure = try
                    wait(LocalMath.execute!(prepared; parameters = arguments(true, 1)))
                    nothing
                catch error
                    error
                end
                @test failure isa LocalMath.LocalMathValidationError
                @test failure.actual.failure_class === :invalid_control
                @test Array(middle_storage) == fill(Int32(71), 5)
                @test Array(output_storage) == fill(Int32(91), 5)
            end
        end
    end
end
