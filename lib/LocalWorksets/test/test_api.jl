@testset "LocalWorksets exact internal-first API" begin
    expected = Set((
        :LocalWorksets,
        :LocalWork,
        :WorkPlan,
        :PreparedWork,
        :WorkEvent,
        :LocalWorkValidationError,
        :localwork,
        :topology,
        :plan,
        :prepare,
        :run!,
        :sequence,
        :inspect,
        :value_slot,
        :storage_slot,
        :resolved,
        :masked,
        :independent,
        :combined,
        :deterministic,
        :fast,
        :emit,
        :candidate,
    ))
    expected_exports = setdiff(expected, Set((:inspect,)))
    expected_types = Set((
        :LocalWork,
        :WorkPlan,
        :PreparedWork,
        :WorkEvent,
        :LocalWorkValidationError,
    ))
    expected_functions = setdiff(
        expected, union(Set((:LocalWorksets,)), expected_types)
    )
    @test Set(names(LW)) == expected
    @test all(name -> Base.ispublic(LW, name), expected)
    @test Set(filter(
        name -> Base.isexported(LW, name),
        names(LW; all = true, imported = true),
    )) == expected_exports
    @test Set(filter(
        name -> getfield(LW, name) isa Type,
        expected,
    )) == expected_types
    @test Set(filter(
        name -> getfield(LW, name) isa Function,
        expected,
    )) == expected_functions
    docs = Base.Docs.meta(LW)
    @test all(
        name -> haskey(docs, Base.Docs.Binding(LW, name)),
        expected,
    )
    private_inventory = (
        :_ConstructionToken,
        :_ValueSlot,
        :_StorageSlot,
        :_MaskedEmission,
        :_AbstractOutputDeclaration,
        :_AbstractCombinationLaw,
        :_IndependentOutput,
        :_CombinationLaw,
        :_CombinedOutput,
        :_Emission,
        :_ConditionalEmission,
        :_Candidate,
        :_ConditionalCandidate,
        :_SequenceOperation,
        :_SequenceLowering,
        :_SingleOutputOperation,
        :_ResolvedOutput,
        :_ResolvedSelection,
        :_ResolvedWinnerLowering,
        :_PreparedResolvedWinner,
        :_ConjunctiveResolvedOutput,
        :_ConjunctiveResolvedOperation,
        :_ConjunctiveResolvedLowering,
        :_PreparedConjunctiveResolved,
        :_KernelAbstractionsLane,
    )
    @test all(name -> isdefined(LW, name), private_inventory)
    @test all(name -> !Base.ispublic(LW, name), private_inventory)
    @test all(name -> !Base.isexported(LW, name), private_inventory)
    diagnostic = LW.LocalWorkValidationError(
        "bad route";
        stage = :plan,
        contract = :route_shape,
        port = :force,
        expected = (2, 4),
        actual = (1, 4),
        hint = "declare two lanes",
    )
    @test diagnostic.stage == :plan
    @test diagnostic.contract == :route_shape
    @test diagnostic.port == :force
    @test diagnostic.binding === nothing
    @test diagnostic.workspace_leaf === nothing
    @test diagnostic.expected == (2, 4)
    @test diagnostic.actual == (1, 4)
    @test sprint(showerror, diagnostic) ==
          "bad route. Hint: declare two lanes"
    @test !isdefined(LW, :CorePotts)
    operation = (family = :declaration_only,)
    declaration_output =
        _zbuffer_declaration().work.outputs.framebuffer_color
    ordered_a = LW.localwork(
        operation,
        1:2;
        read = (z = :z_binding, a = :a_binding),
        outputs = (
            right = declaration_output,
            left = declaration_output,
        ),
    )
    ordered_b = LW.localwork(
        operation,
        1:2;
        read = (a = :a_binding, z = :z_binding),
        outputs = (
            left = declaration_output,
            right = declaration_output,
        ),
    )
    @test typeof(ordered_a) === typeof(ordered_b)
    @test ordered_a.reads == ordered_b.reads
    @test ordered_a.outputs == ordered_b.outputs
    @test keys(ordered_a.reads) == (:a, :z)
    @test keys(ordered_a.outputs) == (:left, :right)
    ordered_sequence = LW.sequence(ordered_a, ordered_b)
    @test sprint(show, ordered_sequence) ==
          "LocalWork(family=ordered_sequence, stages=2)"
    @test LW.inspect(ordered_sequence).family == :ordered_sequence
    @test length(LW.inspect(ordered_sequence).stages) == 2
    raw_constructor_calls = (
        (LW.LocalWork, (1:1, (;), (;), nothing, operation)),
        (LW.WorkPlan, (nothing, nothing, nothing, nothing, nothing)),
        (LW.PreparedWork, (
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            UInt(0),
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            ReentrantLock(),
            current_task(),
            UInt64(0),
            UInt64(0),
            Any[],
            false,
            nothing,
        )),
        (LW.WorkEvent, (nothing, UInt64(0))),
    )
    @test all(call -> !applicable(first(call), last(call)...),
        raw_constructor_calls)
    for (constructor, args) in raw_constructor_calls
        @test_throws MethodError constructor(args...)
    end
end

struct _Level1IndependentOperation end
(::_Level1IndependentOperation)(item, reads, values) =
    LW.emit(@inbounds(reads.source[item]) + Int32(2))

struct _Level1CombinedOperation end
(::_Level1CombinedOperation)(item, reads, values) =
    LW.emit(@inbounds(reads.source[item]))

struct _Level1ResolvedOperation end
(::_Level1ResolvedOperation)(item, reads, values) = LW.candidate(
    @inbounds(reads.rank[item]),
    @inbounds(reads.value[item]),
    @inbounds(reads.enabled[item]),
)

struct _LateLevel1PublicOperation end
(::_LateLevel1PublicOperation)(item::Int32, reads, values) =
    LW.emit(@inbounds(reads.source[item]))

module _ExternalWorkAuthor
import LocalWorksets

struct Scale
    factor::Int32
end

function (operation::Scale)(item::Int32, reads, values)
    return LocalWorksets.emit(
        @inbounds(reads.source[item]) * operation.factor
    )
end
end

@testset "LW-4C3 concise single-output authoring desugars exactly" begin
    backend = LW.KernelAbstractions.CPU()

    direct = LW.localwork(
        _Level1IndependentOperation(),
        1:3,
        :result => LW.independent(:route; value_type = Int32);
        read = (source = :source,),
    )
    @test isbitstype(typeof(direct.operation))
    @test LW.inspect(direct).authoring == :single_output
    @test LW.inspect(direct).family == :independent
    @test LW.inspect(direct).operation isa _Level1IndependentOperation
    direct_topology = LW.topology(
        direct;
        epoch = UInt64(1),
        routes = (route = reshape(Int32[3, 1, 2], 1, 3),),
        destination_counts = (result = 3,),
    )
    direct_storage = (
        source = Int32[1, 2, 3],
        result = fill(Int32(-1), 3),
    )
    @test @inferred(direct.operation(
        Int32(1), (source = direct_storage.source,), (;)
    )) == (result = LW.emit(Int32(3)),)
    direct_plan = LW.plan(direct, direct_topology; backend)
    @test LW.inspect(direct_plan).qualification == (
        operation_structure = :validated,
        provider_environment = :reviewed,
        selected_device_compilation = :host_runtime_compiler,
        provider_compile_validation = :not_available,
        host_fallback = :forbidden,
    )
    plan_facts = LW.inspect(direct_plan)
    @test plan_facts.summary == (
        lifecycle = :WorkPlan,
        family = plan_facts.family,
        backend = plan_facts.backend,
    )
    @test plan_facts.outputs === plan_facts.ports
    @test plan_facts.execution.launches == plan_facts.launches
    @test plan_facts.execution.phases == plan_facts.phases
    @test plan_facts.memory.workspace === plan_facts.workspace
    @test plan_facts.memory.topology_transfer_bytes ==
          plan_facts.topology_transfer_bytes
    direct_prepared = LW.prepare(direct_plan, direct_storage)
    direct_event = LW.run!(direct_prepared)
    wait(direct_event)
    prepared_facts = LW.inspect(direct_prepared)
    event_facts = LW.inspect(direct_event)
    @test prepared_facts.summary.poisoned == prepared_facts.poisoned
    @test prepared_facts.execution.provider == prepared_facts.provider
    @test prepared_facts.memory.workspace_facts ===
          prepared_facts.workspace_facts
    @test event_facts.execution.event_serial == event_facts.event_serial
    @test event_facts.execution.receipt_scope == :lane_tail
    @test direct_storage.result == Int32[4, 5, 3]

    combined = LW.localwork(
        _Level1CombinedOperation(),
        1:3,
        :total => LW.combined(
            :route;
            value_type = Int32,
            combine = LW.deterministic(+, Int32(0)),
        );
        read = (source = :source,),
    )
    combined_topology = LW.topology(
        combined;
        epoch = UInt64(2),
        routes = (route = reshape(Int32[1, 1, 2], 1, 3),),
        destination_counts = (total = 3,),
    )
    combined_storage = (
        source = Int32[2, 3, 7],
        total = fill(Int32(-1), 3),
    )
    combined_prepared = LW.prepare(
        LW.plan(combined, combined_topology; backend), combined_storage
    )
    wait(LW.run!(combined_prepared))
    @test combined_storage.total == Int32[5, 7, 0]

    resolved = LW.localwork(
        _Level1ResolvedOperation(),
        1:3,
        :winner => LW.resolved(
            :route;
            value_type = UInt32,
            maximum = 1,
            empty = UInt32(0),
            rank = (
                type = Int32,
                order = :min,
                lower = Int32(-10),
                upper = Int32(10),
            ),
            tie_break = (type = UInt32, order = :min),
        );
        read = (
            enabled = :enabled,
            rank = :rank,
            value = :value,
        ),
    )
    resolved_topology = LW.topology(
        resolved;
        epoch = UInt64(3),
        routes = (route = reshape(Int32[1, 1, 2], 1, 3),),
        destination_counts = (winner = 3,),
        semantic_ids = (
            winner = reshape(UInt32[20, 10, 30], 1, 3),
        ),
    )
    resolved_storage = (
        enabled = Bool[true, true, false],
        rank = Int32[-2, -2, -4],
        value = UInt32[11, 22, 33],
        winner = fill(UInt32(99), 3),
    )
    resolved_prepared = LW.prepare(
        LW.plan(resolved, resolved_topology; backend), resolved_storage
    )
    wait(LW.run!(resolved_prepared))
    @test resolved_storage.winner == UInt32[22, 0, 0]

    @test propertynames(direct_plan) == (:work, :topology, :backend)
    @test !(:lowering in propertynames(direct_plan))
    @test propertynames(direct_prepared) ==
        (:workplan, :storage, :workspace, :submission_schema)
    property_event = LW.run!(direct_prepared)
    @test propertynames(property_event) == (:serial,)
    wait(property_event)
    @test occursin("outputs=(:result,)", sprint(show, direct))
    @test occursin("workspace=package", sprint(show, direct_prepared))
end

@testset "external concrete operations use the central lifecycle" begin
    backend = LW.KernelAbstractions.CPU()
    work = LW.localwork(
        _ExternalWorkAuthor.Scale(Int32(3)),
        1:3,
        :scaled => LW.independent(:route; value_type = Int32);
        read = (source = :source,),
    )
    topo = LW.topology(
        work;
        epoch = UInt64(4),
        routes = (route = reshape(Int32[2, 3, 1], 1, 3),),
        destination_counts = (scaled = 3,),
    )
    storage = (
        source = Int32[4, 5, 6],
        scaled = fill(Int32(-1), 3),
    )
    workplan = LW.plan(work, topo; backend)
    prepared = LW.prepare(workplan, storage)
    event = LW.run!(prepared)
    wait(event)

    @test storage.scaled == Int32[18, 12, 15]
    @test LW.inspect(work).operation isa _ExternalWorkAuthor.Scale
    @test LW.inspect(workplan).capability.compiler.qualification ==
          :centrally_reviewed_environment
    @test LW.inspect(prepared).provider === :KernelAbstractions
end

struct _B1ScaleOperation
    factor::Int32
end

(operation::_B1ScaleOperation)(item, reads, values) =
    (; result = LW.emit(reads.values[item] * operation.factor))

@testset "LW-4B bounded declaration vocabulary" begin
    independent = LW.independent(
        :destinations;
        value_type = Float32,
        maximum = 2,
        coverage = :partial,
    )
    deterministic = LW.deterministic(+, 0.0f0)
    relaxed = LW.fast(+, Int32(0))
    combined = LW.combined(
        :vertices;
        value_type = Float32,
        maximum = 2,
        combine = deterministic,
    )
    independent_facts = LW.inspect(LW.localwork(
        _B1ScaleOperation(Int32(2)),
        1:2;
        read = (values = :values,),
        outputs = (; result = independent),
    )).outputs.result
    combined_facts = LW.inspect(LW.localwork(
        _B1ScaleOperation(Int32(2)),
        1:2;
        read = (values = :values,),
        outputs = (; result = combined),
    )).outputs.result

    @test independent_facts == (
        family = :independent,
        route = :destinations,
        value_type = Float32,
        maximum_emissions = 2,
        coverage = :partial,
        false_lane = :no_emission,
    )
    @test combined_facts.family == :combined
    @test combined_facts.route == :vertices
    @test combined_facts.maximum_emissions == 2
    @test combined_facts.combine.mode == :deterministic
    @test combined_facts.combine.semantic_order ==
          :canonical_item_local_slot
    @test combined_facts.empty_destination === 0.0f0
    @test relaxed isa LW._AbstractCombinationLaw
    @test LW.emit(UInt32(3)) isa LW._Emission{UInt32}
    @test LW.emit(UInt32(3), false) isa
          LW._ConditionalEmission{UInt32}
    @test LW.candidate(Int32(4), UInt8(2)) isa
          LW._Candidate{Int32, UInt8}
    @test LW.candidate(Int32(4), UInt8(2), false) isa
          LW._ConditionalCandidate{Int32, UInt8}
    @test isbitstype(_B1ScaleOperation)
    @test isbitstype(typeof(deterministic))

    @test_throws ArgumentError LW.independent(
        :route; value_type = Any
    )
    @test_throws ArgumentError LW.independent(
        :route; value_type = UInt32, maximum = 0
    )
    @test_throws ArgumentError LW.independent(
        :route; value_type = UInt32, coverage = :unknown
    )
    @test_throws ArgumentError LW.combined(
        :route; value_type = Float32, combine = +
    )
    @test_throws ArgumentError LW.combined(
        :route;
        value_type = Float32,
        combine = LW.deterministic(+, Int32(0)),
    )
    @test_throws ArgumentError LW.deterministic(+, Any[0])
    @test_throws ArgumentError LW.localwork(
        1, 1:1;
        outputs = (; result = independent),
    )
end


@testset "LocalWork construction spellings and declaration validation" begin
    output = _zbuffer_declaration().work.outputs.framebuffer_color
    reads = (value = :logical_value,)
    outputs = (; result = output)
    direct = LW.localwork(identity, 1:2; read = reads, outputs)
    blocked = LW.localwork(1:2; read = reads, outputs) do value
        value
    end
    direct_facts = LW.inspect(direct)
    blocked_facts = LW.inspect(blocked)
    @test direct isa LW.LocalWork
    @test blocked isa LW.LocalWork
    @test isimmutable(direct)
    @test isimmutable(blocked)
    @test direct_facts.items == blocked_facts.items == 1:2
    @test direct_facts.reads == blocked_facts.reads == reads
    @test direct_facts.outputs == blocked_facts.outputs
    @test direct_facts.outputs.result.destinations ==
          output.destinations
    @test direct_facts.active === blocked_facts.active === nothing
    @test direct.operation(7) == blocked.operation(7) == 7

    @test_throws ArgumentError LW.localwork(
        identity, nothing; read = reads, outputs
    )
    @test_throws ArgumentError LW.localwork(
        identity, 0:2; read = reads, outputs
    )
    @test_throws ArgumentError LW.localwork(
        identity, 1:2; read = (value = 1,), outputs
    )
    @test_throws ArgumentError LW.localwork(
        identity, 1:2; read = reads, outputs = (;)
    )
    @test_throws ArgumentError LW.localwork(
        identity, 1:2; read = reads, outputs = (result = nothing,)
    )
    empty_name_outputs = NamedTuple{(Symbol(""),)}((output,))
    @test_throws ArgumentError LW.localwork(
        identity, 1:2; read = reads, outputs = empty_name_outputs
    )
    @test_throws ArgumentError LW.localwork(
        nothing, 1:2; read = reads, outputs
    )
    @test_throws ArgumentError LW.localwork(
        (not_family = :x,), 1:2; read = reads, outputs
    )
    @test_throws ArgumentError LW.localwork(
        identity, 1:2; read = reads, outputs, active = Any[]
    )
end


@testset "slot bounds and resolved destination profiles are closed" begin
    unbounded = LW.value_slot(Int32)
    bounded = LW.value_slot(Int32; bounds = Int32(0):Int32(2))
    @test unbounded.bounds === nothing
    @test bounded.bounds == Int32(0):Int32(2)
    @test_throws ArgumentError LW.value_slot(
        Int32; bounds = "not bounds"
    )
    @test_throws ArgumentError LW.value_slot(
        Int32; bounds = Int32(3):Int32(1)
    )
    @test_throws ArgumentError LW.value_slot(
        Int32; bounds = Int64(0):Int64(2)
    )
    @test_throws ArgumentError LW.value_slot(
        Int32; bounds = (lower = Int32(0), upper = Int32(2))
    )
    @test_throws ArgumentError LW.storage_slot(Any[1]; access = :read)

    keywords = (
        empty = UInt32(0),
        rank = (
            type = Int32,
            order = :min,
            lower = typemin(Int32),
            upper = typemax(Int32),
        ),
        tie_break = (type = UInt32, order = :min),
        capacity = 4,
        key_type = Int32,
        value_type = UInt32,
    )
    @test LW.resolved(:destinations; keywords...) isa
          LW._AbstractOutputDeclaration
    missing_maximum = try
        LW.resolved(
            :destinations;
            empty = UInt32(0),
            rank = (
                type = Int32,
                order = :min,
                lower = typemin(Int32),
                upper = typemax(Int32),
            ),
            tie_break = (type = UInt32, order = :min),
            value_type = UInt32,
        )
        nothing
    catch error
        error
    end
    @test missing_maximum isa ArgumentError
    @test sprint(showerror, missing_maximum) ==
        "ArgumentError: generic resolved output requires maximum"
    @test_throws ArgumentError LW.resolved(
        :destinations;
        empty = UInt32(0),
        rank = keywords.rank,
        tie_break = keywords.tie_break,
        capacity = 4,
        value_type = UInt32,
    )
    @test_throws ArgumentError LW.resolved(
        :destinations;
        empty = UInt32(0),
        rank = keywords.rank,
        tie_break = keywords.tie_break,
        key_type = Int32,
        value_type = UInt32,
    )
    @test_throws MethodError LW.resolved((:a, :b, :c); keywords...)
    @test_throws MethodError LW.resolved([:a, :b]; keywords...)
    @test_throws MethodError LW.resolved(17; keywords...)
end
