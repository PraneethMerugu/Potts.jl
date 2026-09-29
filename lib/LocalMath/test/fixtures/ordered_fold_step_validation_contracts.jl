using Test
import KernelAbstractions
import LocalMath

struct OrderedFoldStepValidityDomain end
struct OrderedFoldStepValidityEvaluator end

@inline function (::OrderedFoldStepValidityEvaluator)(
        item::Int32, reads, parameters)
    imbalance = item == Int32(3) ? getfield(parameters, 1) : Int32(0)
    return (event = LocalMath.FoldValue((item, imbalance)),)
end

struct OrderedFoldStepValidityTransition end

@inline function (::OrderedFoldStepValidityTransition)(
        state, value, item, reads,
    )
    event = value[1]
    requested = event == Int32(1) ? Int32(3) :
        event == Int32(2) ? Int32(8) : Int32(5)
    available = state.available[Int32(1)]
    realized = requested <= available ? requested : Int32(0)
    update_count = realized == Int32(0) ? Int32(0) : Int32(1)
    disposition = realized == Int32(0) ? UInt8(0) : UInt8(1)
    imbalance = value[2]
    available_next = available - realized
    received_next = state.received[Int32(1)] + realized + imbalance
    balance = available_next + received_next
    valid = balance == Int32(10)
    witness = balance - Int32(10)
    # The invalid result deliberately also proposes an out-of-range write. The
    # semantic invalidity must win before structural write validation or apply.
    destination = valid ? Int32(1) : Int32(2)
    disposition_destination = valid ? event : Int32(4)
    return LocalMath.FoldStep((
        available = LocalMath.BoundedWrites(
            (destination,), (available_next,), update_count),
        received = LocalMath.BoundedWrites(
            (Int32(1),), (received_next,), update_count),
        disposition = LocalMath.BoundedWrites(
            (disposition_destination,), (disposition,), Int32(1)),
    ); valid, witness)
end

function _ordered_fold_step_validity_prepared(array_type)
    events = LocalMath.Space(OrderedFoldStepValidityDomain, 3)
    resource = LocalMath.Space(OrderedFoldStepValidityDomain, 1)
    available_initial = LocalMath.Field(resource, Int32)
    available = LocalMath.Field(resource, Int32)
    received_initial = LocalMath.Field(resource, Int32)
    received = LocalMath.Field(resource, Int32)
    disposition_initial = LocalMath.Field(events, UInt8)
    disposition = LocalMath.Field(events, UInt8)
    imbalance = LocalMath.Parameter(:imbalance, Int32)
    state = LocalMath.initialized_state(;
        available = LocalMath.FoldComponent(
            available; from = available_initial),
        received = LocalMath.FoldComponent(
            received; from = received_initial),
        disposition = LocalMath.FoldComponent(
            disposition; from = disposition_initial),
    )
    publication = LocalMath.Publication((LocalMath.FoldPublication(
        LocalMath.PublicationValue(:event)),), LocalMath.OrderedFold(
            NTuple{2,Int32}, state, OrderedFoldStepValidityTransition(),
        ))
    stage = LocalMath.Stage(
        events, NamedTuple(), (publication,),
        LocalMath.Evaluator(OrderedFoldStepValidityEvaluator(), (imbalance,)),
        LocalMath.Control(),
        LocalMath.SourceOrigin(
            @__FILE__, @__LINE__; label = :ordered_fold_step_validity),
    )
    available_output = array_type(Int32[-41])
    received_output = array_type(Int32[-42])
    disposition_output = array_type(fill(UInt8(0xff), 3))
    work = LocalMath.LocalLaw(stage;
        parameters = LocalMath.ParameterSchema(imbalance))
    prepared = LocalMath.prepare(
        work,
        available_initial => array_type(Int32[10]),
        available => available_output,
        received_initial => array_type(Int32[0]),
        received => received_output,
        disposition_initial => array_type(zeros(UInt8, 3)),
        disposition => disposition_output;
        backend = KernelAbstractions.get_backend(available_output),
    )
    return (;
        prepared, available_output, received_output, disposition_output,
    )
end

function _ordered_fold_step_validity_execute(prepared, imbalance::Int32)
    return try
        wait(LocalMath.execute!(prepared; parameters = (; imbalance)))
        nothing
    catch error
        error
    end
end

function ordered_fold_step_validation_contracts(array_type)
    return @testset "computed ordered-fold step validity is transactional" begin
        transition = OrderedFoldStepValidityTransition()
        state = (available = Int32[7], received = Int32[3],
            disposition = zeros(UInt8, 3))
        valid_step = transition(
            state, (Int32(3), Int32(0)), Int32(3), ())
        invalid_step = transition(
            state, (Int32(3), Int32(1)), Int32(3), ())
        @test typeof(valid_step) === typeof(invalid_step)

        witness = _ordered_fold_step_validity_prepared(array_type)
        accepted = _ordered_fold_step_validity_execute(
            witness.prepared, Int32(0))
        @test accepted === nothing
        @test (
            available = Array(witness.available_output),
            received = Array(witness.received_output),
            disposition = Array(witness.disposition_output),
        ) == (
            available = Int32[2],
            received = Int32[8],
            disposition = UInt8[1, 0, 1],
        )

        copyto!(witness.available_output, array_type(Int32[-41]))
        copyto!(witness.received_output, array_type(Int32[-42]))
        copyto!(witness.disposition_output, array_type(fill(UInt8(0xff), 3)))
        rejected = _ordered_fold_step_validity_execute(
            witness.prepared, Int32(1))
        @test rejected isa LocalMath.LocalMathValidationError
        @test rejected.contract === :runtime_ordered_fold_validation
        @test rejected.actual.failure_class === :invalid_step
        @test rejected.actual.component === nothing
        @test rejected.actual.source_item == Int32(3)
        @test rejected.actual.canonical_position == Int32(3)
        @test rejected.actual.witness == Int32(1)
        @test (
            available = Array(witness.available_output),
            received = Array(witness.received_output),
            disposition = Array(witness.disposition_output),
        ) == (
            available = Int32[-41],
            received = Int32[-42],
            disposition = fill(UInt8(0xff), 3),
        )
    end
end
