# Shared aliases only. Final Stage witnesses own their fixtures locally.
const LM = LocalMath
const KA = LocalMath.KernelAbstractions

"""Return a Stage admission through the sole production planning entrance."""
function _test_stage_admission(bound; backend, index::Integer = 1)
    plan = LocalMath.plan(bound; backend)
    entries = LocalMath._logical_lowering_entries(plan.lowering)
    1 <= index <= length(entries) || throw(BoundsError(entries, index))
    return entries[index].admission
end

struct ReceiptTestNode end
struct ReceiptTestEvaluator{T}
    value::T
end

@inline (evaluator::ReceiptTestEvaluator)(item::Int32, reads, parameters) =
    (value = LM.UniqueValue(evaluator.value + item),)

function _receipt_test_preparation(value::Int32;
        dependency_arity::Int = 0, lease_capacity::Int = 1,
        evaluator = ReceiptTestEvaluator(value))
    space = LM.Space(ReceiptTestNode, 2)
    output = LM.Field(space, Int32)
    relation = LM.IdentityRelation(space)
    publication = LM.Publication((LM.FieldPublication(
        output, relation, LM.PublicationValue(:value)),),
        LM.Unique(Int32))
    stage = LM.Stage(space, NamedTuple(), (publication,),
        LM.Evaluator(evaluator), LM.Control(),
        LM.SourceOrigin(:execution_receipt_test, 1))
    storage = fill(Int32(-1), 2)
    bound = LM._bind_law(LM.LocalLaw(stage),
        LM._StructuralBinding(
            (LM._field_storage_binding(output, storage),),
            (LM._relation_storage_binding(relation),)))
    backend = LM.KernelAbstractions.get_backend(storage)
    prepared = LM.prepare(LM.plan(bound; backend);
        dependency_arity, lease_capacity)
    return prepared, storage
end
