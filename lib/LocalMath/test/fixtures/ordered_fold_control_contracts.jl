using Test
import LocalMath
import KernelAbstractions

struct OrderedFoldControlDomain end
struct OrderedFoldControlEvent end
@inline (::OrderedFoldControlEvent)(item::Int32, reads, parameters) =
    (event = LocalMath.FoldValue(item),)
struct OrderedFoldControlWrite end
@inline (::OrderedFoldControlWrite)(state, value, item, reads) = LocalMath.FoldStep(
    (result = LocalMath.BoundedWrites((Int32(1),), (value,), Int32(1)),),
)
struct OrderedFoldDuplicateIdentity end
@inline (::OrderedFoldDuplicateIdentity)(value) = Int32(0)
struct OrderedFoldControlGate end
@inline (::OrderedFoldControlGate)(item::Int32, reads, parameters) =
    (gate = LocalMath.UniqueValue(something(reads[1][1].value)),)

function ordered_fold_control_contracts(array_type)
    return @testset "closed ordered-fold gates preserve publication" begin
        for gate_kind in (:field, :parameter), duplicate in (false, true)
            @testset "$gate_kind duplicate=$duplicate" begin
                source = LocalMath.Space(OrderedFoldControlDomain, 5)
                state_space = LocalMath.Space(OrderedFoldControlDomain, 2)
                initial, result = LocalMath.Field(state_space, Int32), LocalMath.Field(state_space, Int32)
                gate_space = LocalMath.Space(1)
                external_gate = LocalMath.Field(gate_space, Bool)
                gate = gate_kind === :field ? LocalMath.Field(gate_space, Bool) :
                    LocalMath.Parameter(:enabled, Bool)
                parameters = gate_kind === :parameter ? (gate,) : ()
                state = LocalMath.InitializedState(;
                    result = LocalMath.FoldComponent(result; from = initial),
                )
                key = duplicate ? OrderedFoldDuplicateIdentity() : identity
                fold = LocalMath.OrderedFold(
                    Int32, state, OrderedFoldControlWrite();
                    order = LocalMath.canonical_by(key, key),
                )
                stage = LocalMath.Stage(
                    source, NamedTuple(),
                    (LocalMath.Publication((LocalMath.FoldPublication(LocalMath.PublicationValue(:event)),), fold),),
                    LocalMath.Evaluator(OrderedFoldControlEvent(), parameters),
                    LocalMath.Control(; gate),
                    LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :ordered_fold_control),
                )
                destination = array_type(Int32[66, 77])
                initial_values = array_type(Int32[7, 8])
                enabled_values = array_type(Bool[false])
                bindings = (initial => initial_values, result => destination)
                work = LocalMath.LocalLaw(stage)
                if gate_kind === :field
                    relation = LocalMath.IdentityRelation(gate_space)
                    copy_gate = LocalMath.Stage(
                        gate_space, (gate = LocalMath.Access(external_gate, relation; required = true),),
                        (
                            LocalMath.Publication(
                                (LocalMath.FieldPublication(gate, relation, LocalMath.PublicationValue(:gate)),),
                                LocalMath.Unique(Bool),
                            ),
                        ),
                        LocalMath.Evaluator(OrderedFoldControlGate()), LocalMath.Control(),
                        LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :ordered_fold_gate_publication),
                    )
                    work = LocalMath.sequence(LocalMath.LocalLaw(copy_gate), work)
                    bindings = (bindings..., external_gate => enabled_values, gate => LocalMath.Allocate(false))
                end
                prepared = LocalMath.prepare(
                    work, bindings...;
                    backend = KernelAbstractions.get_backend(destination),
                )
                function run(enabled)
                    gate_kind === :field && copyto!(enabled_values, array_type(Bool[enabled]))
                    arguments = gate_kind === :parameter ? (; parameters = (; enabled)) : NamedTuple()
                    return try
                        wait(LocalMath.execute!(prepared; arguments...))
                        nothing
                    catch error
                        error
                    end
                end
                @test run(false) === nothing
                @test Array(destination) == Int32[66, 77]
                failure = run(true)
                if duplicate
                    @test failure isa LocalMath.LocalMathValidationError
                    @test failure.actual.failure_class === :duplicate_order_identity
                    @test Array(destination) == Int32[66, 77]
                else
                    @test failure === nothing
                    @test Array(destination) == Int32[5, 8]
                    copyto!(destination, array_type(Int32[91, 92]))
                    copyto!(initial_values, array_type(Int32[13, 14]))
                    @test run(false) === nothing
                    @test Array(destination) == Int32[91, 92]
                    @test run(true) === nothing
                    @test Array(destination) == Int32[5, 14]
                end
            end
        end
    end
end
