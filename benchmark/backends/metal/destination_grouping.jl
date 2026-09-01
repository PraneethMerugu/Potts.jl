using Test
using Metal
using LocalMath
using KernelAbstractions

const LWMG = LocalMath
Metal.functional() || error("Metal is not functional")
Metal.allowscalar(false)
const _DestinationGrouping_DESTINATION_CASE = get(ENV, "DestinationGrouping_DESTINATION_CASE", "all")

function metal_destination_grouping(candidates, destinations)
    spec = LWMG._destination_grouping_workspace_spec(
        candidates, destinations;
        path = (:destination_grouping,),
        name_prefix = :destination_grouping,
    )
    authority = LWMG._WorkspaceAuthority(spec.leaves, spec.template)
    workspace = LWMG._materialize_workspace(
        authority.template, authority,
        LWMG._WorkspaceAllocator(Metal.MetalBackend()),
    )
    return LWMG._destination_grouping_from_workspace(workspace, spec.shape)
end

@kernel function reset_metal_destination_grouping!(grouping)
    index = @index(Global, Linear)
    LWMG._reset_destination_grouping_index!(grouping, index)
end

function reset_metal_destination_grouping!(backend, grouping)
    extent = max(Int(grouping.sort_capacity), Int(grouping.candidate_count),
        Int(grouping.destination_count) + 1)
    reset_metal_destination_grouping!(backend)(grouping; ndrange=extent)
    return grouping
end

struct DestinationGroupingMetalUniqueNode end
struct DestinationGroupingMetalItemEvaluator end
@inline (::DestinationGroupingMetalItemEvaluator)(item::Int32, reads, parameters) =
    (value = LWMG.UniqueValue(item),)
struct DestinationGroupingMetalConstantEvaluator
    value::Int32
end
@inline (evaluator::DestinationGroupingMetalConstantEvaluator)(item::Int32, reads, parameters) =
    (value = LWMG.UniqueValue(evaluator.value),)
struct DestinationGroupingMetalContributionEvaluator end
@inline (::DestinationGroupingMetalContributionEvaluator)(item::Int32, reads, parameters) =
    (value = LWMG.Contribution(item),)
struct DestinationGroupingMetalRoutedContributionEvaluator{D} end
@inline function (::DestinationGroupingMetalRoutedContributionEvaluator{D})(
        item::Int32, reads, parameters) where {D}
    return (value = LWMG.RoutedContribution(
        Int32(mod1(item * Int32(29), Int32(D))), item),)
end
struct DestinationGroupingMetalInvalidRoutedContributionEvaluator{D} end
@inline function (::DestinationGroupingMetalInvalidRoutedContributionEvaluator{D})(
        item::Int32, reads, parameters) where {D}
    key = item == Int32(19) ? Int32(D + 1) :
        Int32(mod1(item * Int32(29), Int32(D)))
    return (value = LWMG.RoutedContribution(key, item),)
end
struct DestinationGroupingMetalAffineFold end
@inline (::DestinationGroupingMetalAffineFold)(left::Int32, right::Int32) =
    left * Int32(3) + right
struct DestinationGroupingMetalCanonicalResolveEvaluator end
@inline (::DestinationGroupingMetalCanonicalResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LWMG.ResolutionValue(item & Int32(7), item),)
struct DestinationGroupingMetalExplicitResolveEvaluator end
@inline (::DestinationGroupingMetalExplicitResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LWMG.ResolutionValue(
        (item & Int32(3), item & Int32(7)),
        Int32(1000) - item, item),)
struct DestinationGroupingMetalDuplicateResolveEvaluator end
@inline function (::DestinationGroupingMetalDuplicateResolveEvaluator)(
        item::Int32, reads, parameters)
    duplicate = item == Int32(19) || item == Int32(401)
    rank = duplicate ? (Int32(1), Int32(1)) : (item, Int32(0))
    tie = duplicate ? Int32(7) : item
    return (value = LWMG.ResolutionValue(rank, tie, item),)
end

struct DestinationGroupingMetalInvalidResolveEvaluator end
@inline function (::DestinationGroupingMetalInvalidResolveEvaluator)(
        item::Int32, reads, parameters)
    rank = item == Int32(19) ? Int32(99) : Int32(1)
    return (value = LWMG.ResolutionValue(rank, item, item),)
end

function metal_unique_stage(source, output, relation, law, evaluator;
        control = LWMG.Control())
    publication = LWMG.Publication((LWMG.FieldPublication(
        output, relation, LWMG.PublicationValue(:value)),), law)
    return LWMG.Stage(source, NamedTuple(), (publication,),
        LWMG.Evaluator(evaluator), control,
        LWMG.SourceOrigin(:destination_grouping_metal_unique, 1))
end

function metal_reduce_stage(source, output, relation, law, evaluator)
    publication = LWMG.Publication((LWMG.FieldPublication(
        output, relation, LWMG.PublicationValue(:value)),), law)
    return LWMG.Stage(source, NamedTuple(), (publication,),
        LWMG.Evaluator(evaluator), LWMG.Control(),
        LWMG.SourceOrigin(:destination_grouping_metal_reduce, 1))
end

function metal_resolve_stage(source, output, relation, law, evaluator)
    publication = LWMG.Publication((LWMG.FieldPublication(
        output, relation, LWMG.PublicationValue(:value)),), law)
    return LWMG.Stage(source, NamedTuple(), (publication,),
        LWMG.Evaluator(evaluator), LWMG.Control(),
        LWMG.SourceOrigin(:destination_grouping_metal_resolve, 1))
end

function prepare_metal_candidate(bound, index, parameters, backend, label)
    index == 1 || error("the public Stage lifecycle prepares the full program")
    isempty(parameters) || error("this Metal witness declares no parameters")
    relations = map(bound.binding.relations) do binding
        binding.storage === nothing && return binding
        (binding.generation !== nothing || binding.status !== nothing) &&
            return binding
        generation = LWMG._RelationContentGenerationRef(
            Metal.MtlArray(UInt64[1]), 1)
        status = LWMG._RelationStatusRef(Metal.MtlArray(Int32[0]),
            Metal.MtlArray(UInt64[0]), 1)
        return LWMG._relation_storage_binding(binding.relation,
            binding.storage; generation, status)
    end
    device_bound = LWMG._bind_law(bound.law, LWMG._StructuralBinding(
        bound.binding.fields, relations, bound.binding.collections))
    return LWMG.prepare(LWMG.plan(device_bound; backend))
end

_metal_candidate_stage(prepared) = only(prepared.runtime.launches).stage
_metal_candidate_status(prepared) = _metal_candidate_stage(prepared).execution.status
function _run_metal_candidate!(prepared)
    try
        wait(LWMG.execute!(prepared))
    catch error
        error isa LWMG.LocalMathValidationError || rethrow()
    end
    return prepared
end

_DestinationGrouping_DESTINATION_CASE in ("all", "runtime") &&
@testset "LocalMath RuntimeRelation real Metal" begin
    backend = Metal.MetalBackend()
    n, destination_count = 513, 17
    source = LWMG.Space(DestinationGroupingMetalUniqueNode, n)
    destination = LWMG.Space(DestinationGroupingMetalUniqueNode, destination_count)
    output = LWMG.Field(destination, Int32)
    relation = LWMG.RuntimeRelation(source => destination;
        degree_bound = 1, key_type = Int32)
    law = LWMG.Reduce(Int32, +;
        seed = LWMG.IdentitySeed(Int32(0)))

    storage = Metal.MtlArray(fill(Int32(-1), destination_count))
    stage = metal_reduce_stage(source, output, relation, law,
        DestinationGroupingMetalRoutedContributionEvaluator{destination_count}())
    bound = LWMG._bind_law(LWMG.LocalLaw(stage), LWMG._StructuralBinding(
        (LWMG._field_storage_binding(output, storage),),
        (LWMG._relation_storage_binding(relation),)))
    prepared = prepare_metal_candidate(
        bound, 1, (), backend, :runtime_relation_reduce)
    _run_metal_candidate!(prepared)
    KernelAbstractions.synchronize(backend)
    expected = zeros(Int32, destination_count)
    for item in 1:n
        expected[mod1(item * 29, destination_count)] += Int32(item)
    end
    @test Array(storage) == expected
    @test Array(_metal_candidate_status(prepared)) == Int32[0]

    invalid_storage = Metal.MtlArray(fill(Int32(73), destination_count))
    invalid_stage = metal_reduce_stage(source, output, relation, law,
        DestinationGroupingMetalInvalidRoutedContributionEvaluator{destination_count}())
    invalid_bound = LWMG._bind_law(
        LWMG.LocalLaw(invalid_stage), LWMG._StructuralBinding(
            (LWMG._field_storage_binding(output, invalid_storage),),
            (LWMG._relation_storage_binding(relation),)))
    invalid_prepared = prepare_metal_candidate(
        invalid_bound, 1, (), backend, :runtime_relation_invalid_key)
    _run_metal_candidate!(invalid_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(invalid_storage) == fill(Int32(73), destination_count)
    @test Array(_metal_candidate_status(invalid_prepared)) ==
        Int32[LWMG._CANDIDATE_STATUS_ROUTE_KEY]
end

_DestinationGrouping_DESTINATION_CASE in ("all", "unique") &&
@testset "LocalMath Unique real Metal" begin
    backend = Metal.MetalBackend()
    n = 513
    source = LWMG.Space(DestinationGroupingMetalUniqueNode, n)
    output = LWMG.Field(source, Int32)
    identity = LWMG.IdentityRelation(source)
    output_storage = Metal.MtlArray(fill(Int32(-1), n))
    stage = metal_unique_stage(source, output, identity,
        LWMG.Unique(Int32), DestinationGroupingMetalItemEvaluator())
    bound = LWMG._bind_law(LWMG.LocalLaw(stage), LWMG._StructuralBinding(
        (LWMG._field_storage_binding(output, output_storage),),
        (LWMG._relation_storage_binding(identity),)))
    prepared = prepare_metal_candidate(bound, 1, (), backend, :unique_identity)
    _run_metal_candidate!(prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(output_storage) == Int32.(1:n)
    @test Array(_metal_candidate_status(prepared)) == Int32[0]

    destination = LWMG.Space(DestinationGroupingMetalUniqueNode, 1)
    collision_output = LWMG.Field(destination, Int32)
    collision = LWMG.FixedRelation(source => destination; degree = 1)
    collision_storage = Metal.MtlArray(Int32[91])
    collision_stage = metal_unique_stage(source, collision_output, collision,
        LWMG.Unique(Int32), DestinationGroupingMetalConstantEvaluator(Int32(7)))
    collision_bound = LWMG._bind_law(LWMG.LocalLaw(collision_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(
                collision_output, collision_storage),),
            (LWMG._relation_storage_binding(collision, (
                endpoints = Metal.MtlArray(reshape(fill(Int32(1), n), 1, n)),
                counts = Metal.MtlArray(fill(Int32(1), n)),
            )),)))
    collision_prepared = prepare_metal_candidate(
        collision_bound, 1, (), backend, :unique_collision)
    _run_metal_candidate!(collision_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(collision_storage) == Int32[91]
    @test Array(_metal_candidate_status(collision_prepared)) ==
        Int32[LWMG._UNIQUE_STATUS_CONFLICT]

    enabled = LWMG.Parameter(:enabled, Bool)
    gated_storage = Metal.MtlArray(fill(Int32(23), n))
    gated_stage = metal_unique_stage(source, output, identity,
        LWMG.Unique(Int32;
            coverage = LWMG.PartialCoverage(),
            onempty = LWMG.FillEmpty(Int32(-8))),
        DestinationGroupingMetalConstantEvaluator(Int32(4));
        control = LWMG.Control(; gate = LWMG._ParameterGate(enabled)))
    gated_bound = LWMG._bind_law(LWMG.LocalLaw(gated_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(output, gated_storage),),
            (LWMG._relation_storage_binding(identity),)))
    gated_prepared = prepare_metal_candidate(
        gated_bound, 1, (false,), backend, :unique_closed_gate)
    _run_metal_candidate!(gated_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(gated_storage) == fill(Int32(23), n)
    @test Array(_metal_candidate_status(gated_prepared)) == Int32[0]
end

_DestinationGrouping_DESTINATION_CASE in ("all", "reduce") &&
@testset "LocalMath Reduce real Metal" begin
    backend = Metal.MetalBackend()
    n = 513
    source = LWMG.Space(DestinationGroupingMetalUniqueNode, n)

    # Exact canonical order with two deliberately empty destinations and an
    # Existing seed. The affine fold is both nonassociative and order-sensitive.
    canonical_destination_count = 19
    canonical_destination =
        LWMG.Space(DestinationGroupingMetalUniqueNode, canonical_destination_count)
    canonical_output = LWMG.Field(canonical_destination, Int32)
    canonical_relation = LWMG.FixedRelation(
        source => canonical_destination; degree = 1)
    canonical_endpoints = Int32[mod1(37 * item, 17) for item in 1:n]
    canonical_storage = Metal.MtlArray(
        Int32[1000 + destination for destination in
            1:canonical_destination_count])
    canonical_law = LWMG.Reduce(Int32, DestinationGroupingMetalAffineFold();
        seed = LWMG.ExistingSeed(),
        order = LWMG.CanonicalLeftFold())
    canonical_stage = metal_reduce_stage(source, canonical_output,
        canonical_relation, canonical_law, DestinationGroupingMetalContributionEvaluator())
    canonical_bound = LWMG._bind_law(LWMG.LocalLaw(canonical_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(
                canonical_output, canonical_storage),),
            (LWMG._relation_storage_binding(canonical_relation, (
                endpoints = Metal.MtlArray(reshape(
                    canonical_endpoints, 1, n)),
                counts = Metal.MtlArray(fill(Int32(1), n)),
            )),)))
    canonical_prepared = prepare_metal_candidate(
        canonical_bound, 1, (), backend, :reduce_canonical)
    _run_metal_candidate!(canonical_prepared)
    KernelAbstractions.synchronize(backend)
    canonical_expected = Int32[1000 + destination
        for destination in 1:canonical_destination_count]
    for item in 1:n
        destination = canonical_endpoints[item]
        canonical_expected[destination] = DestinationGroupingMetalAffineFold()(
            canonical_expected[destination], Int32(item))
    end
    @test Array(canonical_storage) == canonical_expected
    @test Array(_metal_candidate_status(canonical_prepared)) == Int32[0]

    # Relaxed atomics still accumulate privately, then cross the common
    # stage-wide visibility gate in a separate KA publication kernel.
    atomic_destination_count = 17
    atomic_destination =
        LWMG.Space(DestinationGroupingMetalUniqueNode, atomic_destination_count)
    atomic_output = LWMG.Field(atomic_destination, Int32)
    atomic_relation = LWMG.FixedRelation(
        source => atomic_destination; degree = 1)
    atomic_endpoints = Int32[mod1(29 * item, atomic_destination_count)
        for item in 1:n]
    atomic_storage = Metal.MtlArray(fill(Int32(-1), atomic_destination_count))
    atomic_law = LWMG.Reduce(Int32, +;
        seed = LWMG.IdentitySeed(Int32(0)),
        order = LWMG.RelaxedAtomic())
    atomic_stage = metal_reduce_stage(source, atomic_output,
        atomic_relation, atomic_law, DestinationGroupingMetalContributionEvaluator())
    atomic_bound = LWMG._bind_law(LWMG.LocalLaw(atomic_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(atomic_output, atomic_storage),),
            (LWMG._relation_storage_binding(atomic_relation, (
                endpoints = Metal.MtlArray(reshape(atomic_endpoints, 1, n)),
                counts = Metal.MtlArray(fill(Int32(1), n)),
            )),)))
    atomic_prepared = prepare_metal_candidate(
        atomic_bound, 1, (), backend, :reduce_atomic)
    _run_metal_candidate!(atomic_prepared)
    KernelAbstractions.synchronize(backend)
    atomic_expected = Int32[sum(Int32(item) for item in 1:n
        if atomic_endpoints[item] == destination)
        for destination in 1:atomic_destination_count]
    @test Array(atomic_storage) == atomic_expected
    @test Array(_metal_candidate_status(atomic_prepared)) == Int32[0]

    # Fixed relationship contents are validated before candidate evaluation.
    # An invalid endpoint fails the receipt and leaves publication untouched.
    invalid_endpoints = copy(atomic_endpoints)
    invalid_endpoints[19] = Int32(0)
    invalid_endpoints[401] = Int32(atomic_destination_count + 1)
    invalid_storage = Metal.MtlArray(fill(Int32(73), atomic_destination_count))
    invalid_bound = LWMG._bind_law(LWMG.LocalLaw(atomic_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(atomic_output, invalid_storage),),
            (LWMG._relation_storage_binding(atomic_relation, (
                endpoints = Metal.MtlArray(reshape(invalid_endpoints, 1, n)),
                counts = Metal.MtlArray(fill(Int32(1), n)),
            )),)))
    invalid_prepared = prepare_metal_candidate(
        invalid_bound, 1, (), backend, :reduce_atomic_invalid)
    invalid_error = try
        wait(LWMG.execute!(invalid_prepared))
        nothing
    catch error
        error
    end
    KernelAbstractions.synchronize(backend)
    @test invalid_error isa LWMG.LocalMathValidationError
    @test invalid_error.contract == :runtime_stage_validation
    @test Array(invalid_storage) == fill(Int32(73), atomic_destination_count)

    # Mutable packed content advertises readiness through its device status.
    # A failed relation transaction suppresses evaluation, settlement, atomics,
    # and publication without moving relationship state back to the host.
    packed_relation = LWMG.PackedRelation(
        source => atomic_destination; degree_bound = 1, capacity = n)
    packed_stage = metal_reduce_stage(source, atomic_output,
        packed_relation, atomic_law, DestinationGroupingMetalContributionEvaluator())
    stale_storage = Metal.MtlArray(fill(Int32(73), atomic_destination_count))
    stale_bound = LWMG._bind_law(LWMG.LocalLaw(packed_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(atomic_output, stale_storage),),
            (LWMG._relation_storage_binding(packed_relation, (
                active = Metal.MtlArray(fill(true, n)),
                endpoints = Metal.MtlArray(reshape(atomic_endpoints, 1, n)),
                offsets = Metal.MtlArray(Int32[1]),
                counts = Metal.MtlArray(Int32[n]),
            );
                generation = LWMG._RelationContentGenerationRef(
                    Metal.MtlArray(UInt64[1]), 1),
                status = LWMG._RelationStatusRef(
                    Metal.MtlArray(Int32[9]), Metal.MtlArray(UInt64[1]), 1)),)))
    stale_prepared = prepare_metal_candidate(
        stale_bound, 1, (), backend, :reduce_atomic_stale)
    _run_metal_candidate!(stale_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(stale_storage) == atomic_expected
    @test Array(_metal_candidate_status(stale_prepared)) == Int32[0]
end

_DestinationGrouping_DESTINATION_CASE in ("all", "resolve") &&
@testset "LocalMath Resolve real Metal" begin
    backend = Metal.MetalBackend()
    n = 513
    destination_count = 19
    live_destination_count = 17
    source = LWMG.Space(DestinationGroupingMetalUniqueNode, n)
    destination = LWMG.Space(DestinationGroupingMetalUniqueNode, destination_count)
    output = LWMG.Field(destination, Int32)
    relation = LWMG.FixedRelation(source => destination; degree = 1)
    endpoints = Int32[mod1(31 * item, live_destination_count)
        for item in 1:n]
    relation_storage = (
        endpoints = Metal.MtlArray(reshape(endpoints, 1, n)),
        counts = Metal.MtlArray(fill(Int32(1), n)),
    )

    for (direction, empty, sentinel, label) in (
            (LWMG.ArgMin(), LWMG.FillEmpty(Int32(-9)), Int32(70),
                :resolve_canonical_min),
            (LWMG.ArgMax(), LWMG.PreserveEmpty(), Int32(80),
                :resolve_canonical_max))
        law = LWMG.Resolve(Int32, Int32; direction,
            lower = Int32(0), upper = Int32(7), onempty = empty)
        stage = metal_resolve_stage(source, output, relation, law,
            DestinationGroupingMetalCanonicalResolveEvaluator())
        storage = Metal.MtlArray(fill(sentinel, destination_count))
        bound = LWMG._bind_law(LWMG.LocalLaw(stage),
            LWMG._StructuralBinding(
                (LWMG._field_storage_binding(output, storage),),
                (LWMG._relation_storage_binding(
                    relation, relation_storage),)))
        prepared = prepare_metal_candidate(bound, 1, (), backend, label)
        _run_metal_candidate!(prepared)
        KernelAbstractions.synchronize(backend)
        expected = fill(sentinel, destination_count)
        for destination_index in 1:live_destination_count
            candidates = [item for item in 1:n
                if endpoints[item] == destination_index]
            ranks = Int32[item & 7 for item in candidates]
            best_rank = direction isa LWMG.ArgMin ? minimum(ranks) :
                maximum(ranks)
            expected[destination_index] = Int32(first(candidates[index]
                for index in eachindex(candidates)
                if ranks[index] == best_rank))
        end
        empty isa LWMG.FillEmpty &&
            (expected[(live_destination_count + 1):end] .= Int32(-9))
        @test Array(storage) == expected
        @test Array(_metal_candidate_status(prepared)) == Int32[0]
    end

    tuple_lower = (Int32(0), Int32(0))
    tuple_upper = (Int32(3), Int32(7))
    for (tie_law, label) in (
            (LWMG.TieMin{Int32}(), :resolve_explicit_tie_min),
            (LWMG.TieMax{Int32}(), :resolve_explicit_tie_max))
        law = LWMG.Resolve(typeof(tuple_lower), Int32;
            direction = LWMG.ArgMin(), tie = tie_law,
            lower = tuple_lower, upper = tuple_upper,
            onempty = LWMG.FillEmpty(Int32(-7)))
        stage = metal_resolve_stage(source, output, relation, law,
            DestinationGroupingMetalExplicitResolveEvaluator())
        storage = Metal.MtlArray(fill(Int32(91), destination_count))
        bound = LWMG._bind_law(LWMG.LocalLaw(stage),
            LWMG._StructuralBinding(
                (LWMG._field_storage_binding(output, storage),),
                (LWMG._relation_storage_binding(
                    relation, relation_storage),)))
        prepared = prepare_metal_candidate(bound, 1, (), backend, label)
        _run_metal_candidate!(prepared)
        KernelAbstractions.synchronize(backend)
        expected = fill(Int32(-7), destination_count)
        for destination_index in 1:live_destination_count
            candidates = [item for item in 1:n
                if endpoints[item] == destination_index]
            best_rank = minimum(((Int32(item & 3), Int32(item & 7))
                for item in candidates))
            tied = [item for item in candidates
                if (Int32(item & 3), Int32(item & 7)) == best_rank]
            expected[destination_index] = Int32(tie_law isa LWMG.TieMin ?
                argmin(item -> Int32(1000 - item), tied) :
                argmax(item -> Int32(1000 - item), tied))
        end
        @test Array(storage) == expected
        @test Array(_metal_candidate_status(prepared)) == Int32[0]
    end

    duplicate_endpoints = copy(endpoints)
    duplicate_endpoints[19] = Int32(1)
    duplicate_endpoints[401] = Int32(1)
    duplicate_relation_storage = (
        endpoints = Metal.MtlArray(reshape(duplicate_endpoints, 1, n)),
        counts = Metal.MtlArray(fill(Int32(1), n)),
    )
    duplicate_law = LWMG.Resolve(
        Tuple{Int32,Int32}, Int32;
        tie = LWMG.TieMin{Int32}(),
        lower = (Int32(0), Int32(0)),
        upper = (Int32(600), Int32(1)))
    duplicate_stage = metal_resolve_stage(source, output, relation,
        duplicate_law, DestinationGroupingMetalDuplicateResolveEvaluator())
    duplicate_storage = Metal.MtlArray(fill(Int32(61), destination_count))
    duplicate_bound = LWMG._bind_law(LWMG.LocalLaw(duplicate_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(output, duplicate_storage),),
            (LWMG._relation_storage_binding(
                relation, duplicate_relation_storage),)))
    duplicate_prepared = prepare_metal_candidate(
        duplicate_bound, 1, (), backend, :resolve_duplicate)
    _run_metal_candidate!(duplicate_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(duplicate_storage) == fill(Int32(61), destination_count)
    @test Array(_metal_candidate_status(duplicate_prepared)) ==
        Int32[LWMG._CANDIDATE_STATUS_DUPLICATE_TIE]

    invalid_law = LWMG.Resolve(Int32, Int32;
        tie = LWMG.TieMin{Int32}(),
        lower = Int32(0), upper = Int32(10))
    invalid_stage = metal_resolve_stage(source, output, relation,
        invalid_law, DestinationGroupingMetalInvalidResolveEvaluator())
    invalid_storage = Metal.MtlArray(fill(Int32(51), destination_count))
    invalid_bound = LWMG._bind_law(LWMG.LocalLaw(invalid_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(output, invalid_storage),),
            (LWMG._relation_storage_binding(relation, relation_storage),)))
    invalid_prepared = prepare_metal_candidate(
        invalid_bound, 1, (), backend, :resolve_invalid_rank)
    _run_metal_candidate!(invalid_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(invalid_storage) == fill(Int32(51), destination_count)
    @test Array(_metal_candidate_status(invalid_prepared)) ==
        Int32[LWMG._CANDIDATE_STATUS_RANK_BOUNDS]
    @test Array(first(_metal_candidate_stage(
        invalid_prepared).execution.workspaces).
        invalid_rank_ordinal) == Int32[19]

    packed_relation = LWMG.PackedRelation(
        source => destination; degree_bound = 1, capacity = n)
    packed_stage = metal_resolve_stage(source, output, packed_relation,
        invalid_law, DestinationGroupingMetalInvalidResolveEvaluator())
    stale_storage = Metal.MtlArray(fill(Int32(41), destination_count))
    stale_bound = LWMG._bind_law(LWMG.LocalLaw(packed_stage),
        LWMG._StructuralBinding(
            (LWMG._field_storage_binding(output, stale_storage),),
            (LWMG._relation_storage_binding(packed_relation, (
                active = Metal.MtlArray(fill(true, n)),
                endpoints = Metal.MtlArray(reshape(endpoints, 1, n)),
                offsets = Metal.MtlArray(Int32[1]),
                counts = Metal.MtlArray(Int32[n]),
            );
                generation = LWMG._RelationContentGenerationRef(
                    Metal.MtlArray(UInt64[1]), 1),
                status = LWMG._RelationStatusRef(
                    Metal.MtlArray(Int32[9]), Metal.MtlArray(UInt64[1]), 1)),)))
    stale_prepared = prepare_metal_candidate(
        stale_bound, 1, (), backend, :resolve_stale_relation)
    _run_metal_candidate!(stale_prepared)
    KernelAbstractions.synchronize(backend)
    @test Array(stale_storage) == fill(Int32(41), destination_count)
    @test Array(_metal_candidate_status(stale_prepared)) ==
        Int32[LWMG._CANDIDATE_STATUS_RANK_BOUNDS]
end

_DestinationGrouping_DESTINATION_CASE in ("all", "grouping") &&
@testset "LocalMath destination grouping real Metal" begin
    Metal.functional() || error("Metal is not functional")
    Metal.allowscalar(false)
    backend = Metal.MetalBackend()
    n, destination_count = 513, 17
    destinations = Int32[mod1(37 * ordinal, destination_count)
        for ordinal in 1:n]
    valid = fill(UInt8(1), n)
    destinations[19] = Int32(0)
    destinations[401] = Int32(destination_count + 1)
    valid[77] = UInt8(0)

    grouping = metal_destination_grouping(n, destination_count)
    LWMG._require_destination_grouping_capabilities(backend)
    reset_metal_destination_grouping!(backend, grouping)
    KernelAbstractions.synchronize(backend)
    copyto!(grouping.destinations, destinations)
    copyto!(grouping.valid, valid)
    LWMG._group_destinations!(backend, grouping)
    KernelAbstractions.synchronize(backend)

    normalized_valid = copy(valid)
    normalized_valid[[19, 401]] .= UInt8(0)
    expected_live = sort(Int32.(1:n); by = ordinal -> (
        normalized_valid[ordinal] == 0,
        normalized_valid[ordinal] == 0 ? typemax(Int32) :
            destinations[ordinal],
        ordinal,
    ))
    live = filter(ordinal -> normalized_valid[ordinal] != 0, expected_live)
    expected = vcat(expected_live,
        zeros(Int32, Int(grouping.sort_capacity) - n))
    sorted_destinations = Int32[destinations[ordinal] for ordinal in live]
    expected_starts = Int32[searchsortedfirst(
        sorted_destinations, destination) for destination in
        1:(destination_count + 1)]

    @test Array(LWMG._destination_grouping_order(grouping)) == expected
    @test Array(grouping.starts) == expected_starts
    @test Array(grouping.invalid_ordinal) == Int32[19]
    @test Array(grouping.valid)[[19, 401, 77]] == UInt8[0, 0, 0]
end
