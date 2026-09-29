import LocalMath

const LMSO = LocalMath

struct SemanticOracleUniqueEvaluator end
@inline function (::SemanticOracleUniqueEvaluator)(item::Int32, reads, parameters)
    return (value = LMSO.UniqueValue(
        Int32(2) * something(getfield(reads, 1)[1].value)),)
end

struct SemanticOracleReduceEvaluator end
@inline (::SemanticOracleReduceEvaluator)(item::Int32, reads, parameters) =
    (value = LMSO.Contribution(item),)

struct SemanticOracleResolveEvaluator end
@inline function (::SemanticOracleResolveEvaluator)(item::Int32, reads, parameters)
    score = abs(Int32(3) - item)
    return (value = LMSO.ResolutionValue(score, item),)
end

struct SemanticOracleCollectEvaluator end
@inline function (::SemanticOracleCollectEvaluator)(item::Int32, reads, parameters)
    return (records = (
        LMSO.CollectedValue(item),
        LMSO.CollectedValue(item + Int32(10), isodd(item)),
    ),)
end

struct SemanticOracleFoldEvaluator end
@inline (::SemanticOracleFoldEvaluator)(item::Int32, reads, parameters) =
    (event = LMSO.FoldValue(item),)

struct SemanticOracleFoldTransition end
@inline function (::SemanticOracleFoldTransition)(state, value, item, reads)
    return LMSO.FoldStep((accumulator = LMSO.BoundedWrites(
        (Int32(1),), (value,), Int32(1)),))
end

struct SemanticOracleConflictEvaluator end
@inline (::SemanticOracleConflictEvaluator)(item::Int32, reads, parameters) =
    (value = LMSO.UniqueValue(item),)

struct SemanticOracleSuccessorEvaluator end
@inline (::SemanticOracleSuccessorEvaluator)(item::Int32, reads, parameters) =
    (value = LMSO.UniqueValue(item + Int32(100)),)

struct SemanticOracleOverflowCollectEvaluator end
@inline (::SemanticOracleOverflowCollectEvaluator)(
    item::Int32, reads, parameters) = (record = LMSO.CollectedValue(item),)

struct SemanticOracleInvalidFoldTransition end
@inline function (::SemanticOracleInvalidFoldTransition)(
        state, value, item, reads)
    return LMSO.FoldStep((accumulator = LMSO.BoundedWrites(
        (Int32(2),), (value,), Int32(1)),))
end

_semantic_host(value) = Array(value)

function _semantic_expected_reduce(endpoints, values, destination_count)
    result = zeros(Int32, destination_count)
    for item in eachindex(values)
        result[endpoints[item]] += values[item]
    end
    return result
end

function _semantic_expected_resolve(endpoints, scores, ties, payloads,
        destination_count)
    result = fill(Int32(-1), destination_count)
    winners = fill((typemax(Int32), typemax(Int32)), destination_count)
    for item in eachindex(payloads)
        destination = endpoints[item]
        key = (scores[item], ties[item])
        if key < winners[destination]
            winners[destination] = key
            result[destination] = payloads[item]
        end
    end
    return result
end

function _semantic_law_facts(prepared)
    facts = LMSO.inspect(prepared)
    return (
        lowering = facts.planning.compiler,
        executors = map(stage -> stage.planning.executor, facts.stages),
        laws = map(facts.stages) do stage
            map(publication -> publication.details.law.kind,
                stage.publications)
        end,
    )
end

function run_semantic_oracle_suite(array_type, backend)
    source = LMSO.Space(4)
    destination = LMSO.Space(2)
    identity = LMSO.IdentityRelation(source)
    route = LMSO.FixedRelation(source => destination; degree = 1)
    endpoints_host = reshape(Int32[1, 2, 1, 2], 1, 4)
    endpoints = array_type(endpoints_host)

    input = LMSO.Field(source, Int32)
    unique_output = LMSO.Field(source, Int32)
    input_data = array_type(Int32[3, 1, 4, 2])
    authored_unique = LMSO.@localmath item ∈ source begin
        unique_output[item] = Int32(2) * input[item]
    end
    explicit_unique = LMSO.LocalLaw(LMSO.Stage(source,
        (input = LMSO.Access(input, identity),),
        (LMSO.Publication((LMSO.FieldPublication(unique_output, identity,
            LMSO.PublicationValue(:value)),), LMSO.Unique(Int32)),),
        LMSO.Evaluator(SemanticOracleUniqueEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_oracle, 1)))
    unique_results = []
    unique_facts = []
    for law in (authored_unique, explicit_unique)
        output = array_type(fill(Int32(-1), 4))
        prepared = LMSO.prepare(law, input => input_data,
            unique_output => output; backend)
        wait(LMSO.execute!(prepared))
        push!(unique_results, _semantic_host(output))
        push!(unique_facts, _semantic_law_facts(prepared))
    end

    reduce_output = LMSO.Field(destination, Int32)
    authored_reduce = LMSO.@localmath item ∈ source begin
        reduce_output[route(item)] += Int32(item)
    end
    explicit_reduce = LMSO.LocalLaw(LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(reduce_output, route,
            LMSO.PublicationValue(:value)),), LMSO.Reduce(Int32, +;
                seed = LMSO.IdentitySeed(Int32(0)),
                order = LMSO.CanonicalLeftFold())),),
        LMSO.Evaluator(SemanticOracleReduceEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_oracle, 2)))
    reduce_results = []
    reduce_facts = []
    for law in (authored_reduce, explicit_reduce)
        output = array_type(zeros(Int32, 2))
        prepared = LMSO.prepare(law, reduce_output => output,
            route => endpoints; backend)
        wait(LMSO.execute!(prepared))
        push!(reduce_results, _semantic_host(output))
        push!(reduce_facts, _semantic_law_facts(prepared))
    end

    resolve_output = LMSO.Field(destination, Int32)
    authored_resolve = LMSO.@localmath item ∈ source begin
        resolve_output[route(item)] = resolve_to(;
            score = abs(Int32(3) - item), payload = item,
            lower = Int32(0), upper = Int32(3), onempty = Int32(-1))
    end
    explicit_resolve = LMSO.LocalLaw(LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(resolve_output, route,
            LMSO.PublicationValue(:value)),), LMSO.Resolve(Int32, Int32;
                direction = LMSO.ArgMin(),
                lower = Int32(0), upper = Int32(3),
                onempty = LMSO.FillEmpty(Int32(-1)))),),
        LMSO.Evaluator(SemanticOracleResolveEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_oracle, 3)))
    resolve_results = []
    resolve_facts = []
    for law in (authored_resolve, explicit_resolve)
        output = array_type(fill(Int32(-9), 2))
        prepared = LMSO.prepare(law, resolve_output => output,
            route => endpoints; backend)
        wait(LMSO.execute!(prepared))
        push!(resolve_results, _semantic_host(output))
        push!(resolve_facts, _semantic_law_facts(prepared))
    end

    records = LMSO.Collection(Int32, 6)
    authored_collect = LMSO.@localmath item ∈ source begin
        records[item] = bounded_collect((item, item + Int32(10));
            maximum = 2, when = (true, isodd(item)))
    end
    explicit_collect = LMSO.LocalLaw(LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.CollectionPublication(records,
            LMSO.PublicationValue(:records)),), LMSO.Collect(Int32;
                maximum = 2)),),
        LMSO.Evaluator(SemanticOracleCollectEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_oracle, 4)))
    collect_results = []
    collect_facts = []
    for law in (authored_collect, explicit_collect)
        prepared = LMSO.prepare(law, records => LMSO.Allocate(); backend)
        wait(LMSO.execute!(prepared))
        storage = LMSO.storage(prepared, records)
        count = Int(only(_semantic_host(storage.count)))
        push!(collect_results, _semantic_host(storage.records)[1:count])
        push!(collect_facts, _semantic_law_facts(prepared))
    end

    state_space = LMSO.Space(1)
    initial = LMSO.Field(state_space, Int32)
    accumulator = LMSO.Field(state_space, Int32)
    authored_fold = LMSO.@localmath item ∈ source begin
        @ordered (by = :source, state = (accumulator => initial,)) begin
            accumulator[Int32(1)] = Int32(item)
        end
    end
    fold_state = LMSO.InitializedState(;
        accumulator = LMSO.FoldComponent(accumulator; from = initial))
    explicit_fold = LMSO.LocalLaw(LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FoldPublication(
            LMSO.PublicationValue(:event)),), LMSO.OrderedFold(
                Int32, fold_state, SemanticOracleFoldTransition();
                order = LMSO.source_order())),),
        LMSO.Evaluator(SemanticOracleFoldEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_oracle, 5)))
    fold_results = []
    fold_facts = []
    for law in (authored_fold, explicit_fold)
        output = array_type(Int32[-1])
        prepared = LMSO.prepare(law,
            initial => array_type(Int32[0]), accumulator => output; backend)
        wait(LMSO.execute!(prepared))
        push!(fold_results, _semantic_host(output))
        push!(fold_facts, _semantic_law_facts(prepared))
    end

    return (
        unique = (results = unique_results, facts = unique_facts,
            oracle = Int32[2value for value in Int32[3, 1, 4, 2]]),
        reduce = (results = reduce_results, facts = reduce_facts,
            oracle = _semantic_expected_reduce(vec(endpoints_host),
                Int32[1, 2, 3, 4], 2)),
        resolve = (results = resolve_results, facts = resolve_facts,
            oracle = _semantic_expected_resolve(vec(endpoints_host),
                Int32[2, 1, 0, 1], Int32[1, 2, 3, 4],
                Int32[1, 2, 3, 4], 2)),
        collect = (results = collect_results, facts = collect_facts,
            oracle = Int32[1, 11, 2, 3, 13, 4]),
        fold = (results = fold_results, facts = fold_facts,
            oracle = Int32[4]),
    )
end

function run_semantic_failure_barrier(array_type, backend)
    source = LMSO.Space(2)
    destination = LMSO.Space(1)
    conflicted = LMSO.Field(destination, Int32)
    successor = LMSO.Field(source, Int32)
    collision = LMSO.FixedRelation(source => destination; degree = 1)
    identity = LMSO.IdentityRelation(source)
    failing = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(conflicted, collision,
            LMSO.PublicationValue(:value)),), LMSO.Unique(Int32)),),
        LMSO.Evaluator(SemanticOracleConflictEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_failure_barrier, 1))
    later = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(successor, identity,
            LMSO.PublicationValue(:value)),), LMSO.Unique(Int32)),),
        LMSO.Evaluator(SemanticOracleSuccessorEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_failure_barrier, 2))
    law = LMSO.sequence(LMSO.LocalLaw(failing), LMSO.LocalLaw(later))
    conflicted_storage = array_type(Int32[-7])
    successor_storage = array_type(fill(Int32(-9), 2))
    prepared = LMSO.prepare(law,
        conflicted => conflicted_storage,
        successor => successor_storage,
        collision => array_type(reshape(Int32[1, 1], 1, 2)); backend)
    failure = try
        wait(LMSO.execute!(prepared))
        nothing
    catch error
        error
    end
    return (
        failure,
        conflicted = _semantic_host(conflicted_storage),
        successor = _semantic_host(successor_storage),
    )
end

function run_collect_failure_barrier(array_type, backend)
    source = LMSO.Space(2)
    records = LMSO.Collection(Int32, 1)
    successor = LMSO.Field(source, Int32)
    identity = LMSO.IdentityRelation(source)
    collect = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.CollectionPublication(records,
            LMSO.PublicationValue(:record)),), LMSO.Collect(Int32)),),
        LMSO.Evaluator(SemanticOracleOverflowCollectEvaluator()),
        LMSO.Control(), LMSO.SourceOrigin(:semantic_failure_barrier, 3))
    later = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(successor, identity,
            LMSO.PublicationValue(:value)),), LMSO.Unique(Int32)),),
        LMSO.Evaluator(SemanticOracleSuccessorEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_failure_barrier, 4))
    successor_storage = array_type(fill(Int32(-9), 2))
    prepared = LMSO.prepare(LMSO.sequence(
            LMSO.LocalLaw(collect), LMSO.LocalLaw(later)),
        records => LMSO.Allocate(), successor => successor_storage; backend)
    failure = try
        wait(LMSO.execute!(prepared))
        nothing
    catch error
        error
    end
    return (
        failure,
        count = _semantic_host(LMSO.storage(prepared, records).count),
        successor = _semantic_host(successor_storage),
    )
end

function run_fold_failure_barrier(array_type, backend)
    source = LMSO.Space(2)
    state_space = LMSO.Space(1)
    initial = LMSO.Field(state_space, Int32)
    accumulator = LMSO.Field(state_space, Int32)
    successor = LMSO.Field(source, Int32)
    identity = LMSO.IdentityRelation(source)
    state = LMSO.InitializedState(;
        accumulator = LMSO.FoldComponent(accumulator; from = initial))
    fold = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FoldPublication(
            LMSO.PublicationValue(:event)),), LMSO.OrderedFold(Int32,
                state, SemanticOracleInvalidFoldTransition();
                order = LMSO.source_order())),),
        LMSO.Evaluator(SemanticOracleFoldEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_failure_barrier, 5))
    later = LMSO.Stage(source, NamedTuple(),
        (LMSO.Publication((LMSO.FieldPublication(successor, identity,
            LMSO.PublicationValue(:value)),), LMSO.Unique(Int32)),),
        LMSO.Evaluator(SemanticOracleSuccessorEvaluator()), LMSO.Control(),
        LMSO.SourceOrigin(:semantic_failure_barrier, 6))
    accumulator_storage = array_type(Int32[-7])
    successor_storage = array_type(fill(Int32(-9), 2))
    prepared = LMSO.prepare(LMSO.sequence(
            LMSO.LocalLaw(fold), LMSO.LocalLaw(later)),
        initial => array_type(Int32[0]), accumulator => accumulator_storage,
        successor => successor_storage; backend)
    failure = try
        wait(LMSO.execute!(prepared))
        nothing
    catch error
        error
    end
    return (
        failure,
        accumulator = _semantic_host(accumulator_storage),
        successor = _semantic_host(successor_storage),
    )
end
