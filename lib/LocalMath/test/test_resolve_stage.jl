using Test
import LocalMath
const LMV = LocalMath

struct ResolveStageNode end
struct FormulaResolveEvaluator end
@inline function (::FormulaResolveEvaluator)(item::Int32, reads, parameters)
    local_item = item <= 3 ? item : item - Int32(3)
    rank = local_item == 3 ? Int32(0) : local_item
    return (value = LMV.ResolutionValue(rank, item),)
end
struct ConstantRankResolveEvaluator end
@inline (::ConstantRankResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LMV.ResolutionValue(Int32(1), item),)
struct ExplicitResolveEvaluator end
@inline (::ExplicitResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LMV.ResolutionValue(
        Int32(1), Int32(10) - item, item),)
struct ReusedTieResolveEvaluator end
@inline (::ReusedTieResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LMV.ResolutionValue(item, Int32(7), item),)
struct DuplicateResolveEvaluator end
@inline (::DuplicateResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LMV.ResolutionValue(Int32(1), Int32(2), item),)
struct InvalidUnroutedResolveEvaluator{Conditional} end
@inline function (::InvalidUnroutedResolveEvaluator{Conditional})(
        item::Int32, reads, parameters) where {Conditional}
    rank = item == 2 ? Int32(99) : Int32(1)
    participates = Conditional ? item != 2 : true
    return (value = LMV.ResolutionValue(
        rank, Int32(item), item, participates),)
end
struct TwoLaneResolveEvaluator end
@inline (::TwoLaneResolveEvaluator)(item::Int32, reads, parameters) = (
    value = (
        LMV.ResolutionValue(
            item == 1 ? Int32(2) : Int32(0),
            item * Int32(10) + Int32(1)),
        LMV.ResolutionValue(
            item == 1 ? Int32(1) : Int32(3),
            item * Int32(10) + Int32(2)),
    ),)

function _resolve_test_stage(source, output, relation, law, evaluator;
        control = LMV.Control())
    publication = LMV.Publication((LMV.FieldPublication(
        output, relation, LMV.PublicationValue(:value)),), law)
    return LMV.Stage(source, NamedTuple(), (publication,),
        LMV.Evaluator(evaluator), control,
        LMV.SourceOrigin(:resolve_stage_test, 1))
end

function _prepare_test_resolve(bound; parameters = ())
    backend = LMV.KernelAbstractions.get_backend(
        first(bound.binding.fields).storage)
    return LMV.prepare(LMV.plan(bound; backend))
end

function _run_test_resolve!(prepared)
    event = LMV.execute!(prepared)
    try
        wait(event)
    catch error
        error isa LMV.LocalMathValidationError || rethrow()
    end
    return only(prepared.runtime.launches).stage
end

function _resolve_fixed_binding(output, storage, relation, endpoints, counts)
    return LMV._StructuralBinding(
        (LMV._field_storage_binding(output, storage),),
        (LMV._relation_storage_binding(relation, (
            endpoints = reshape(Int32.(endpoints),
                LMV.degree_bound(relation), :),
            counts = Int32.(counts))),))
end

@testset "canonical Resolve preserves rank direction, ordinal tie, and empties" begin
    source = LMV.Space(ResolveStageNode, 6)
    destination = LMV.Space(ResolveStageNode, 3)
    output = LMV.Field(destination, Int32)
    relation = LMV.FixedRelation(source => destination; degree = 1)
    endpoints = Int32[1, 1, 1, 2, 2, 2]
    counts = fill(Int32(1), 6)

    min_law = LMV.Resolve(Int32, Int32;
        direction = LMV.ArgMin(), lower = Int32(0), upper = Int32(2),
        onempty = LMV.FillEmpty(Int32(-9)))
    min_stage = _resolve_test_stage(
        source, output, relation, min_law, FormulaResolveEvaluator())
    min_storage = fill(Int32(70), 3)
    min_bound = LMV._bind_law(LMV.LocalLaw(min_stage),
        _resolve_fixed_binding(
            output, min_storage, relation, endpoints, counts))
    backend = LMV.KernelAbstractions.get_backend(min_storage)
    min_plan = LMV.plan(min_bound; backend)
    min_phases = only(LMV.inspect(min_plan).planning.stage_phases)
    @test map(phase -> phase.kind, min_phases) == (
        :candidate_reset,
        :candidate_evaluate,
        :resolve_atomic_winner,
        :candidate_validate,
        :candidate_finalize_publish,
    )
    min_prepared = _run_test_resolve!(LMV.prepare(min_plan))
    @test min_storage == Int32[3, 6, -9]
    @test only(Array(min_prepared.execution.status)) ==
        LMV._CANDIDATE_STATUS_SUCCESS

    max_law = LMV.Resolve(Int32, Int32;
        direction = LMV.ArgMax(), lower = Int32(0), upper = Int32(2),
        onempty = LMV.PreserveEmpty())
    max_stage = _resolve_test_stage(
        source, output, relation, max_law, FormulaResolveEvaluator())
    max_storage = Int32[70, 71, 72]
    max_bound = LMV._bind_law(LMV.LocalLaw(max_stage),
        _resolve_fixed_binding(
            output, max_storage, relation, endpoints, counts))
    _run_test_resolve!(_prepare_test_resolve(max_bound))
    @test max_storage == Int32[2, 5, 72]

    one = LMV.Space(ResolveStageNode, 1)
    one_output = LMV.Field(one, Int32)
    collision = LMV.FixedRelation(source => one; degree = 1)
    ordinal_stage = _resolve_test_stage(source, one_output, collision,
        LMV.Resolve(Int32, Int32;
            direction = LMV.ArgMin(), lower = Int32(1), upper = Int32(1)),
        ConstantRankResolveEvaluator())
    ordinal_storage = Int32[-1]
    ordinal_bound = LMV._bind_law(LMV.LocalLaw(ordinal_stage),
        _resolve_fixed_binding(one_output, ordinal_storage, collision,
            fill(Int32(1), 6), counts))
    _run_test_resolve!(_prepare_test_resolve(ordinal_bound))
    @test ordinal_storage == Int32[1]
end

@testset "explicit Resolve ties are secondary complete keys" begin
    source = LMV.Space(ResolveStageNode, 6)
    destination = LMV.Space(ResolveStageNode, 2)
    output = LMV.Field(destination, Int32)
    relation = LMV.FixedRelation(source => destination; degree = 1)
    endpoints = Int32[1, 1, 1, 2, 2, 2]
    counts = fill(Int32(1), 6)
    for (tie_law, expected) in (
            (LMV.TieMin{Int32}(), Int32[3, 6]),
            (LMV.TieMax{Int32}(), Int32[1, 4]))
        law = LMV.Resolve(Int32, Int32;
            direction = LMV.ArgMin(), tie = tie_law,
            lower = Int32(1), upper = Int32(1))
        stage = _resolve_test_stage(
            source, output, relation, law, ExplicitResolveEvaluator())
        storage = fill(Int32(-1), 2)
        bound = LMV._bind_law(LMV.LocalLaw(stage),
            _resolve_fixed_binding(output, storage, relation,
                endpoints, counts))
        prepared = _run_test_resolve!(_prepare_test_resolve(bound))
        @test storage == expected
        phases = only(LMV.inspect(LMV.plan(bound;
            backend = LMV.KernelAbstractions.get_backend(storage))).planning.stage_phases)
        @test any(phase -> startswith(String(phase.kind),
            "destination_grouping_"), phases)
        @test only(Array(prepared.execution.status)) ==
            LMV._CANDIDATE_STATUS_SUCCESS
    end

    # Reusing a tie at distinct primary ranks is fully ordered and legal.
    unique_rank_law = LMV.Resolve(Int32, Int32;
        direction = LMV.ArgMin(), tie = LMV.TieMin{Int32}(),
        lower = Int32(1), upper = Int32(6))
    reused_stage = _resolve_test_stage(source, output, relation,
        unique_rank_law, ReusedTieResolveEvaluator())
    reused_storage = fill(Int32(-1), 2)
    reused_bound = LMV._bind_law(LMV.LocalLaw(reused_stage),
        _resolve_fixed_binding(output, reused_storage, relation,
            endpoints, counts))
    reused_prepared = _run_test_resolve!(_prepare_test_resolve(reused_bound))
    @test reused_storage == Int32[1, 4]
    @test only(Array(reused_prepared.execution.status)) ==
        LMV._CANDIDATE_STATUS_SUCCESS
end

@testset "Resolve rejects duplicate keys and pre-routing rank violations" begin
    source = LMV.Space(ResolveStageNode, 2)
    destination = LMV.Space(ResolveStageNode, 1)
    output = LMV.Field(destination, Int32)
    relation = LMV.FixedRelation(source => destination; degree = 1)
    endpoints = Int32[1, 1]

    duplicate_law = LMV.Resolve(Int32, Int32;
        tie = LMV.TieMin{Int32}(),
        lower = Int32(0), upper = Int32(2))
    duplicate_stage = _resolve_test_stage(source, output, relation,
        duplicate_law, DuplicateResolveEvaluator())
    duplicate_storage = Int32[91]
    duplicate_bound = LMV._bind_law(LMV.LocalLaw(duplicate_stage),
        _resolve_fixed_binding(output, duplicate_storage, relation,
            endpoints, Int32[1, 1]))
    duplicate_prepared = _run_test_resolve!(
        _prepare_test_resolve(duplicate_bound))
    @test duplicate_storage == Int32[91]
    @test only(Array(duplicate_prepared.execution.status)) ==
        LMV._CANDIDATE_STATUS_DUPLICATE_TIE
    @test Array(duplicate_prepared.validation)[:, 1] == UInt32[
        LMV._CANDIDATE_STATUS_DUPLICATE_TIE, 1, 1, 2, 1, 0]

    invalid_law = LMV.Resolve(Int32, Int32;
        tie = LMV.TieMin{Int32}(),
        lower = Int32(0), upper = Int32(10))
    invalid_stage = _resolve_test_stage(source, output, relation,
        invalid_law, InvalidUnroutedResolveEvaluator{false}())
    invalid_storage = Int32[81]
    invalid_bound = LMV._bind_law(LMV.LocalLaw(invalid_stage),
        _resolve_fixed_binding(output, invalid_storage, relation,
            endpoints, Int32[1, 0]))
    invalid_prepared = _run_test_resolve!(_prepare_test_resolve(invalid_bound))
    @test invalid_storage == Int32[81]
    @test only(Array(invalid_prepared.execution.status)) ==
        LMV._CANDIDATE_STATUS_RANK_BOUNDS
    @test Array(first(invalid_prepared.execution.workspaces).
        invalid_rank_ordinal) == Int32[2]
    @test Array(invalid_prepared.validation)[:, 1] == UInt32[
        LMV._CANDIDATE_STATUS_RANK_BOUNDS, 1, 2, 2, 0, 0]

    conditional_stage = _resolve_test_stage(source, output, relation,
        invalid_law, InvalidUnroutedResolveEvaluator{true}())
    conditional_storage = Int32[71]
    conditional_bound = LMV._bind_law(LMV.LocalLaw(conditional_stage),
        _resolve_fixed_binding(output, conditional_storage, relation,
            endpoints, Int32[1, 0]))
    conditional_prepared = _run_test_resolve!(
        _prepare_test_resolve(conditional_bound))
    @test conditional_storage == Int32[1]
    @test only(Array(conditional_prepared.execution.status)) ==
        LMV._CANDIDATE_STATUS_SUCCESS
end

@testset "Resolve preserves exact static lane routing" begin
    source = LMV.Space(ResolveStageNode, 2)
    destination = LMV.Space(ResolveStageNode, 2)
    output = LMV.Field(destination, Int32)
    relation = LMV.FixedRelation(source => destination; degree = 2)
    law = LMV.Resolve(Int32, Int32; maximum = 2,
        lower = Int32(0), upper = Int32(3))
    stage = _resolve_test_stage(
        source, output, relation, law, TwoLaneResolveEvaluator())
    storage = fill(Int32(-1), 2)
    bound = LMV._bind_law(LMV.LocalLaw(stage),
        _resolve_fixed_binding(output, storage, relation,
            Int32[1, 2, 1, 2], Int32[2, 2]))
    _run_test_resolve!(_prepare_test_resolve(bound))
    @test storage == Int32[21, 12]
end
