@testset "LocalWorksets exact internal-first API" begin
    expected = Set((
        :LocalWorksets,
        :LocalWork,
        :WorkPlan,
        :PreparedWork,
        :WorkEvent,
        :localwork,
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
    expected_exports = Set((:LocalWorksets,))
    expected_types = Set((:LocalWork, :WorkPlan, :PreparedWork, :WorkEvent))
    expected_functions = setdiff(expected, union(
        expected_exports, expected_types
    ))
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
        :LocalWorkValidationError,
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
    @test_throws MethodError LW.resolved((:a, :b, :c); keywords...)
    @test_throws MethodError LW.resolved([:a, :b]; keywords...)
    @test_throws MethodError LW.resolved(17; keywords...)
end
