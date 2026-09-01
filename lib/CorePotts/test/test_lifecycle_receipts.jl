struct TestBulkComponentPolicy <: CorePotts.AbstractBulkComponentStatePolicy
    fail_kind::Base.RefValue{Int16}
end

struct _OffsetAxesVector{T, A <: Vector{T}} <: AbstractVector{T}
    values::A
    first::Int
end
Base.IndexStyle(::Type{<:_OffsetAxesVector}) = IndexLinear()
Base.size(values::_OffsetAxesVector) = (length(values.values),)
Base.axes(values::_OffsetAxesVector) = (
    values.first:(values.first + length(values.values) - 1),
)
Base.getindex(values::_OffsetAxesVector, index::Int) =
    values.values[index - values.first + 1]
Base.setindex!(values::_OffsetAxesVector, value, index::Int) =
    (values.values[index - values.first + 1] = value)
Base.strides(::_OffsetAxesVector) = (1,)
CorePotts.KernelAbstractions.get_backend(values::_OffsetAxesVector) =
    CorePotts.KernelAbstractions.get_backend(values.values)

function _relationship_schema_state(
        ownership;
        trackers = (),
        relationships = CorePotts.RelationshipStorage(
            (), CorePotts.RelationshipSlot[]
        ),
    )
    return (
        ownership,
        cell_kinds = zeros(Int16, length(ownership)),
        cell_generations = zeros(UInt32, length(ownership)),
        trackers = (values = trackers,),
        relationships,
        descriptor_state = (banks = (),),
        lifecycle_workspace = CorePotts.NoLifecycleWorkspace(),
        program = (topology_epoch = UInt64(1),),
    )
end

@testset "lifecycle copy schema rejects structurally ambiguous banks" begin
    different_axes_a = _relationship_schema_state(_OffsetAxesVector(zeros(Int32, 4), 0))
    different_axes_b = _relationship_schema_state(_OffsetAxesVector(zeros(Int32, 4), 1))
    @test_throws ArgumentError CorePotts._validated_program_state_copy_schema(
        different_axes_a, different_axes_b
    )

    states = [
        CorePotts.ProgramRelationshipState(Float32, 2, 2, 1, 1),
        CorePotts.ProgramRelationshipState(Float32, 2, 2, 1, 1),
    ]
    bank = CorePotts._pack_relationship_bank(identity, states)
    canonical = CorePotts.RelationshipStorage(
        (bank,), CorePotts.RelationshipSlot[
            CorePotts.RelationshipSlot(1, 1),
            CorePotts.RelationshipSlot(1, 2),
        ]
    )
    permuted = CorePotts.RelationshipStorage(
        (copy(bank),), reverse(copy(canonical.slots))
    )
    @test_throws ArgumentError CorePotts._validated_program_state_copy_schema(
        _relationship_schema_state(zeros(Int32, 4); relationships = canonical),
        _relationship_schema_state(zeros(Int32, 4); relationships = permuted),
    )

    mismatched = copy(canonical)
    mismatched.banks[1].edge_offsets[1] += Int32(1)
    @test_throws ArgumentError CorePotts._validated_program_state_copy_schema(
        _relationship_schema_state(zeros(Int32, 4); relationships = canonical),
        _relationship_schema_state(zeros(Int32, 4); relationships = mismatched),
    )

    shared = zeros(Float32, 4)
    cross_chunk_alias = _relationship_schema_state(
        zeros(Int32, 4);
        trackers = (shared, zeros(Float32, 4), zeros(Float32, 4),
            zeros(Float32, 4), shared),
    )
    independent = _relationship_schema_state(
        zeros(Int32, 4);
        trackers = ntuple(_ -> zeros(Float32, 4), 5),
    )
    @test_throws ArgumentError CorePotts._validated_program_state_copy_schema(
        cross_chunk_alias, independent
    )

    zero_a = _relationship_schema_state(
        zeros(Int32, 4); trackers = (Float32[],)
    )
    zero_b = _relationship_schema_state(
        zeros(Int32, 4); trackers = (Float32[],)
    )
    schema = CorePotts._validated_program_state_copy_schema(zero_a, zero_b)
    @test any(isempty(leaf.original) for leaves in schema for leaf in leaves)
    declaration = CorePotts._program_state_copy_sequence(
        first(schema), last(schema), nothing)
    nonempty_extents = map(leaf -> length(leaf.original),
        filter(leaf -> !isempty(leaf.original), first(schema)))
    @test length(declaration.laws) == sum(
        cld(count(==(extent), nonempty_extents), 4)
        for extent in unique(nonempty_extents))
end

function receipt_descriptor(
        index::Integer,
        effect::CorePotts.LifecycleEffectCode;
        domain_kind::Integer = 0,
        destination_kind::Integer = 0,
        parent_kind::Integer = 0,
        daughter_kind::Integer = 0,
        placement::CorePotts.LifecyclePlacementCode =
            CorePotts.NoLifecyclePlacement,
        placement_evaluator::Integer = 0,
        partition::CorePotts.LifecyclePartitionCode =
            CorePotts.NoLifecyclePartition,
        point_from_centroid::Bool = false,
        normal = (0.0, 0.0),
        relation_slot::Integer = 0,
        on_inadmissible::CorePotts.LifecycleInadmissibilityDisposition =
            CorePotts.ErrorLifecycleInadmissible,
        compiler_synthesized::Bool = false,
        cadence::CorePotts.LifecycleCadenceCode =
            CorePotts.EveryMCSLifecycleCadence,
        cadence_value::Integer = 1,
    )
    return CorePotts.LifecycleDescriptor{2, Float64}(
        Int32(index),
        UInt64(100 + index),
        UInt64(200 + index),
        effect === CorePotts.CreateCellLifecycleEffect ?
            CorePotts.ModelLifecycleDomain :
            CorePotts.CellKindLifecycleDomain,
        Int16(effect === CorePotts.CreateCellLifecycleEffect ? 0 : domain_kind),
        Int32(1),
        cadence,
        Int32(cadence_value),
        effect,
        Int32(0),
        on_inadmissible,
        Int16(destination_kind),
        Int16(1),
        placement,
        Int32(placement_evaluator),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(relation_slot),
        partition,
        Int32(0),
        point_from_centroid,
        (0.0, 0.0),
        Tuple(Float64.(normal)),
        CorePotts.CanonicalLifecycleSide,
        UInt16(0),
        UInt16(0),
        Int16(parent_kind),
        Int16(daughter_kind),
        Int32(1),
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        compiler_synthesized,
    )
end

function receipt_lifecycle_plan()
    descriptors = CorePotts.LifecycleDescriptor{2, Float64}[
        receipt_descriptor(
            1,
            CorePotts.CreateCellLifecycleEffect;
            destination_kind = 8,
            placement = CorePotts.SeedAtLifecyclePlacement,
            placement_evaluator = 2,
        ),
        receipt_descriptor(
            2, CorePotts.RemoveCellLifecycleEffect; domain_kind = 2
        ),
        receipt_descriptor(
            3,
            CorePotts.TransitionCellLifecycleEffect;
            domain_kind = 4,
            destination_kind = 5,
        ),
        receipt_descriptor(
            4,
            CorePotts.DivideCellLifecycleEffect;
            domain_kind = 6,
            parent_kind = 6,
            daughter_kind = 7,
            partition = CorePotts.SpecifiedNormalLifecyclePartition,
            point_from_centroid = true,
            normal = (0.0, 1.0),
            relation_slot = 1,
        ),
    ]
    evaluators = CorePotts.LifecycleEvaluatorStorage(
        Any[
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(36)),
        ],
        Symbol[:lifecycle_trigger, :lifecycle_placement],
    )
    relation = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    return CorePotts.LifecycleExecutionPlan(
        descriptors,
        evaluators,
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage((relation,), Val(2)),
        CorePotts.StablePriorityLifecycleConflicts,
        8,
        25,
        1,
        0,
        falses(8),
    )
end

function retirement_lifecycle_plan()
    descriptor = receipt_descriptor(
        1,
        CorePotts.RetireCellLifecycleEffect;
        domain_kind = 2,
        on_inadmissible = CorePotts.FilterLifecycleInadmissible,
        compiler_synthesized = true,
    )
    evaluators = CorePotts.LifecycleEvaluatorStorage(
        Any[CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true))],
        Symbol[:lifecycle_trigger],
    )
    return CorePotts.LifecycleExecutionPlan(
        CorePotts.LifecycleDescriptor{2, Float64}[descriptor],
        evaluators,
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        CorePotts.StablePriorityLifecycleConflicts,
        1,
        1,
        1,
        0,
        falses(2),
    )
end

function periodic_transition_lifecycle_plan()
    descriptor = receipt_descriptor(
        1,
        CorePotts.TransitionCellLifecycleEffect;
        domain_kind = 2,
        destination_kind = 3,
        cadence = CorePotts.PeriodicLifecycleCadence,
        cadence_value = 2,
    )
    evaluators = CorePotts.LifecycleEvaluatorStorage(
        Any[CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true))],
        Symbol[:lifecycle_trigger],
    )
    return CorePotts.LifecycleExecutionPlan(
        CorePotts.LifecycleDescriptor{2, Float64}[descriptor],
        evaluators,
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        CorePotts.StablePriorityLifecycleConflicts,
        2,
        2,
        1,
        0,
        falses(3),
    )
end

function _lifecycle_checkerboard_initial(capacity::Integer)
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    kinds = zeros(Int16, capacity)
    kinds[1] = Int16(2)
    generations = zeros(UInt32, capacity)
    generations[1] = UInt32(1)
    return CorePotts.ProgramInitialState(
        ownership,
        kinds;
        scalar_type = Float64,
        cell_generations = generations,
    )
end

function _assert_checkerboard_bank_invariants(workspace)
    primary = workspace.state
    alternate = workspace.alternate_state
    for state in (primary, alternate)
        CorePotts._require_checkerboard_lifecycle_staging_aliases(state)
        lifecycle = state.lifecycle_workspace
        if lifecycle isa CorePotts.LifecycleWorkspace
            @test lifecycle.staged_ownership === state.ownership
            @test lifecycle.staged_cell_kinds === state.cell_kinds
            @test lifecycle.staged_cell_generations === state.cell_generations
            @test lifecycle.staged_trackers === state.trackers
            @test lifecycle.staged_relationships === state.relationships
            @test lifecycle.staged_descriptor_state === state.descriptor_state
        end
    end
    primary_leaves = last.(CorePotts._program_state_copy_leaves(primary))
    alternate_leaves = last.(CorePotts._program_state_copy_leaves(alternate))
    @test length(primary_leaves) == length(alternate_leaves)
    @test all(
        primary_leaf !== alternate_leaf &&
            !Base.mightalias(primary_leaf, alternate_leaf)
        for primary_leaf in primary_leaves for alternate_leaf in alternate_leaves
    )
    return length(primary_leaves)
end

@testset "checkerboard banks own disjoint science and aliased lifecycle staging" begin
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            CorePotts.CellMomentsTracker{2, Float64}(),
        ),
        "lifecycle-alias-ownership-and-moments-v1",
    )
    inert_plan = CorePotts.LifecycleExecutionPlan(
        CorePotts.LifecycleDescriptor{2, Float64}[],
        CorePotts.LifecycleEvaluatorStorage(Any[], Symbol[]),
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        CorePotts.RejectLifecycleConflicts,
        2,
        0,
        1,
        0,
        falses(1),
    )
    profiles = (
        CorePotts.NoLifecycleExecutionPlan(),
        inert_plan,
        retirement_lifecycle_plan(),
    )
    leaf_counts = map(profiles) do lifecycle_plan
        program = test_program(
            CorePotts.CheckerboardProgramEngine();
            lifecycle_plan,
            tracker_plan,
        )
        runtime = CorePotts.initialize_program(
            program,
            _lifecycle_checkerboard_initial(1),
            Float64[],
            UInt64(0x909),
            UInt32(1),
        )
        reductions = runtime.engine_workspace.lifecycle_reductions
        if lifecycle_plan isa CorePotts.NoLifecycleExecutionPlan
            @test reductions === nothing
        else
            @test reductions !== nothing
            for bank in reductions
                for prepared in (
                        bank.site_index, bank.request_index, bank.selection,
                    )
                    facts = LocalMath.inspect(prepared.plan)
                    @test facts.planning.base_provider_launch_count ==
                        facts.planning.stage_local_launch_count + 1
                    @test facts.planning.program_reset_count == 1
                    @test facts.planning.workspace_bytes == sum(
                        leaf.bytes for leaf in
                            LocalMath.workspace_requirements(
                                prepared.plan).algorithmic)
                end
            end
        end
        workspace = CorePotts._checkerboard_core(runtime.engine_workspace)
        _assert_checkerboard_bank_invariants(workspace)
    end
    @test allequal(leaf_counts)
    @test first(leaf_counts) == 6

    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        lifecycle_plan = retirement_lifecycle_plan(),
        tracker_plan,
    )
    runtime = CorePotts.initialize_program(
        program,
        _lifecycle_checkerboard_initial(1),
        Float64[],
        UInt64(0x909),
        UInt32(1),
    )
    workspace = CorePotts._checkerboard_core(runtime.engine_workspace)
    alternate = workspace.alternate_state
    aliased_science = (
        ownership = workspace.state.ownership,
        cell_kinds = alternate.cell_kinds,
        cell_generations = alternate.cell_generations,
        trackers = alternate.trackers,
        relationships = alternate.relationships,
        descriptor_state = alternate.descriptor_state,
    )
    aliased_lifecycle = CorePotts._lifecycle_workspace_with_staged_state(
        alternate.lifecycle_workspace, aliased_science
    )
    aliased_alternate = CorePotts._checkerboard_state_with_science(
        alternate,
        aliased_science.ownership,
        aliased_science.cell_kinds,
        aliased_science.cell_generations,
        aliased_science.trackers,
        aliased_science.relationships,
        aliased_science.descriptor_state,
        aliased_lifecycle,
    )
    @test_throws ArgumentError CorePotts._allocate_checkerboard_workspace(
        workspace.state;
        capability_report = workspace.capability_report,
        alternate_state = aliased_alternate,
    )

    source = workspace.alternate_state
    destination = workspace.state
    source.ownership[1] = Int32(7)
    destination.ownership[1] = Int32(0)
    lifecycle = destination.lifecycle_workspace
    lifecycle.status[1] = CorePotts.ProgramStatus(
        CorePotts.ProgramStatusEvaluator,
        Int32(0),
        Int32(0),
        Int32(0),
        CorePotts.LifecycleDetailNone,
        Int32(0),
        Int32(0),
        Int32(0),
    )
    receipt = CorePotts._clear_checkerboard_bulk!(
        runtime.engine_workspace, destination)
    wait(receipt)
    @test destination.ownership[1] == 0
    lifecycle.status[1] = CorePotts.ProgramStatus()
    receipt = CorePotts._clear_checkerboard_bulk!(
        runtime.engine_workspace, destination)
    wait(receipt)
    @test destination.ownership[1] == 7
end

@testset "lifecycle emission has one Core KA authority and positional banks" begin
    plan = retirement_lifecycle_plan()
    initial = _lifecycle_checkerboard_initial(1)
    checkerboard = CorePotts.initialize_program(
        test_program(CorePotts.CheckerboardProgramEngine(); lifecycle_plan = plan),
        initial,
        Float64[],
        UInt64(0x8c4),
        UInt32(1),
    )
    sequential = CorePotts.initialize_program(
        test_program(CorePotts.SequentialProgramEngine(); lifecycle_plan = plan),
        initial,
        Float64[],
        UInt64(0x8c4),
        UInt32(1),
    )
    checkerboard_emission =
        checkerboard.engine_workspace.lifecycle_reductions[1].emission
    sequential_emission =
        sequential.engine_workspace.lifecycle_compaction.emission[1]
    @test checkerboard_emission isa CorePotts._PreparedLifecycleEmission
    @test sequential_emission isa CorePotts._PreparedLifecycleEmission
    @test checkerboard_emission.runtime.ownership ===
        checkerboard.engine_workspace.core.state.ownership
    @test length(sequential.engine_workspace.lifecycle_compaction.emission) == 2
    @test all(
        emission -> emission isa CorePotts._PreparedLifecycleEmission,
        sequential.engine_workspace.lifecycle_compaction.emission,
    )
    @test !isdefined(CorePotts, :_emit_lifecycle_requests!)
    @test isdefined(CorePotts, :_lifecycle_request_emission_kernel!)
    @test isdefined(CorePotts, :_lifecycle_emission_status_kernel!)

    inspection = CorePotts._inspect_checkerboard_execution(
        checkerboard.engine_workspace
    )
    initialization_extents = map(leaf -> length(last(leaf)), filter(
        leaf -> !isempty(last(leaf)), CorePotts._program_state_copy_leaves(
            checkerboard.engine_workspace.core.state)))
    initialization_stages = sum(
        cld(count(==(extent), initialization_extents), 4)
        for extent in unique(initialization_extents))
    @test all(fact -> length(fact.stages) == initialization_stages + 2,
        inspection.clear_report)
    @test all(fact -> fact.planning.program_reset_count == 1,
        inspection.clear_report)
    @test first(inspection.order) ===
        :state_initialization_and_report_reset
    @test hasproperty(inspection.lifecycle_reductions[1], :emission)
    @test hasproperty(inspection.completion_receipts, :mechanics)
    @test length(inspection.completion_receipts.mechanics) == 2
    @test all(
        bank -> bank isa Vector{LocalMath.ExecutionReceipt},
        inspection.completion_receipts.mechanics,
    )
    @test hasproperty(
        inspection.completion_receipts.lifecycle, :emission
    )

    # Emission follows the candidate science bank selected by the same physical
    # ownership identity as site indexing; it never retains the initial bank.
    transaction_workspace = sequential.engine_workspace
    CorePotts._prepare_sequential_transaction!(
        sequential, transaction_workspace
    )
    sequential.cell_kinds[1] = Int16(0)
    CorePotts._reset_lifecycle_workspace!(sequential.lifecycle_workspace)
    @test CorePotts._run_host_lifecycle_emission!(
        sequential, sequential.lifecycle_workspace
    )
    @test !sequential.lifecycle_workspace.active[1]
    CorePotts._restore_sequential_transaction!(
        sequential, transaction_workspace
    )
end

@testset "checkerboard reuses prepared destination lifecycle operations" begin
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        lifecycle_plan = retirement_lifecycle_plan(),
    )
    runtime = CorePotts.initialize_program(
        program,
        _lifecycle_checkerboard_initial(1),
        Float64[],
        UInt64(0x8c42),
        UInt32(1),
    )
    execution = runtime.engine_workspace
    core = CorePotts._checkerboard_core(execution)
    _, destination, _ = CorePotts._checkerboard_transaction_banks(core, 0)
    bank = CorePotts._checkerboard_authorized_bank(execution, destination)
    prepared = execution.lifecycle_reductions[bank]

    CorePotts.advance_mcs!(runtime)

    @test runtime.settled
    @test runtime.mcs == 1
    @test CorePotts.program_snapshot(runtime).mcs == 1
    @test execution.lifecycle_reductions[bank] === prepared
    @test core.execution.submitted_mcs == core.execution.drained_mcs == 1
    receipt = CorePotts.program_lifecycle_receipt(runtime)
    @test CorePotts.validate_lifecycle_receipt(receipt) === receipt
end

@testset "lifecycle selection validity does not survive a non-due MCS" begin
    plan = periodic_transition_lifecycle_plan()
    initial = _lifecycle_checkerboard_initial(1)
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        runtime = CorePotts.initialize_program(
            test_program(engine; lifecycle_plan = plan),
            initial,
            Float64[],
            UInt64(0x8c41),
            UInt32(1),
        )
        CorePotts.advance_mcs!(runtime)
        @test isempty(CorePotts.program_lifecycle_receipt(runtime))
        expected = _selection_oracle(
            [_oracle_request((
                UInt32(0), UInt32(101), UInt32(0), UInt32(201),
                Int32(1), UInt32(1),
            ), 0; effect = :transition)],
            falses(1, 1),
            copy(runtime.cell_kinds),
            copy(runtime.cell_generations),
            :stable_priority,
        )
        CorePotts.advance_mcs!(runtime)
        due = CorePotts.program_lifecycle_receipt(runtime)
        @test length(due) == length(expected.selected) == 1
        @test only(due) isa CorePotts.TransitionLifecycleEvent
        CorePotts.advance_mcs!(runtime)
        closed = CorePotts.program_lifecycle_receipt(runtime)
        @test isempty(closed)
        lifecycle_workspace = if engine isa CorePotts.CheckerboardProgramEngine
            core = CorePotts._checkerboard_core(runtime.engine_workspace)
            current, _, _ = CorePotts._checkerboard_transaction_banks(
                core, runtime.mcs
            )
            current.lifecycle_workspace
        else
            runtime.lifecycle_workspace
        end
        @test !only(lifecycle_workspace.selection.ready)
        @test CorePotts._lifecycle_selected_count(
            lifecycle_workspace
        ) == 0
    end
end

function receipt_program(plan)
    offsets = zeros(Int8, 2, 1)
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            CorePotts.CellMomentsTracker{2, Float64}(),
        ),
        "receipt-ownership-count-and-moments-v1",
    )
    return CorePotts.CompiledPottsProgram(
        (6, 6),
        (false, false),
        offsets,
        8,
        1,
        CorePotts.CompiledScalar(0.0),
        1,
        Float64[],
        (),
        tracker_plan,
        empty_descriptor_plan(),
        CorePotts.StageExecutionPlan(),
        CorePotts.SequentialProgramEngine(),
        CorePotts.CPUProgramBackend(),
        "lifecycle-receipt-real-transaction-v1";
        lifecycle_plan = plan,
    )
end

function CorePotts.validate_component_state(
        ::TestBulkComponentPolicy, state::Vector{Int}, capacity::Integer
    )
    length(state) == capacity || throw(ArgumentError("test state capacity mismatch"))
    return nothing
end

function CorePotts.initialize_component_state!(
        policy::TestBulkComponentPolicy,
        state::Vector{Int},
        event::CorePotts.CreateLifecycleEvent,
    )
    slot = Int(event.after.slot)
    state[slot] = 100 * Int(event.after.kind)
    event.after.kind == policy.fail_kind[] && error("injected component failure")
    return state
end

function CorePotts.remove_component_state!(
        ::TestBulkComponentPolicy,
        state::Vector{Int},
        event::CorePotts.RemoveCellLifecycleEvent,
    )
    state[Int(event.before.slot)] = -1
    return state
end

function CorePotts.retire_component_state!(
        ::TestBulkComponentPolicy,
        state::Vector{Int},
        event::CorePotts.RetireLifecycleEvent,
    )
    state[Int(event.before.slot)] = -Int(event.cause_identity)
    return state
end


function CorePotts.transition_component_state!(
        ::TestBulkComponentPolicy,
        state::Vector{Int},
        event::CorePotts.TransitionLifecycleEvent,
    )
    slot = Int(event.before.slot)
    state[slot] += 100 * Int(event.after.kind)
    return state
end


function CorePotts.divide_component_state!(
        ::TestBulkComponentPolicy,
        state::Vector{Int},
        event::CorePotts.DivideLifecycleEvent,
    )
    parent_slot = Int(event.parent_before.cell.slot)
    daughter_slot = Int(event.daughter_after.cell.slot)
    original = state[parent_slot]
    state[parent_slot] = original ÷ 2
    state[daughter_slot] = original - state[parent_slot]
    return state
end


@testset "generation-safe lifecycle receipts" begin
    cell = CorePotts.CellIdentity(1, 2, 3)
    @test cell.slot == 1
    @test cell.generation == 2
    @test cell.kind == 3
    @test_throws ArgumentError CorePotts.CellIdentity(0, 1, 1)
    @test_throws ArgumentError CorePotts.CellIdentity(1, 0, 1)
    @test_throws ArgumentError CorePotts.CellIdentity(1, 1, 0)

    request = CorePotts.QualifiedLifecycleRequestIdentity(10, 20, 30, 2)
    @test CorePotts.lifecycle_request_identity(
        CorePotts.CreateLifecycleEvent(request, cell)
    ) == request
    @test_throws ArgumentError CorePotts.QualifiedLifecycleRequestIdentity(
        0, 20, 30, 2
    )
    model_request = CorePotts.QualifiedLifecycleRequestIdentity(10, 20, 0, 0)
    @test CorePotts.CreateLifecycleEvent(model_request, cell).after == cell

    remove = CorePotts.RemoveCellLifecycleEvent(request, cell)
    retire = CorePotts.RetireLifecycleEvent(request, cell, 31, 32)
    @test retire.cause_identity == 31
    @test retire.policy_identity == 32
    @test_throws ArgumentError CorePotts.RetireLifecycleEvent(
        request, cell, 0, 32
    )
    @test remove.before == retire.before

    transitioned = CorePotts.CellIdentity(1, 2, 4)
    transition = CorePotts.TransitionLifecycleEvent(request, cell, transitioned)
    @test transition.after.kind == 4
    @test_throws ArgumentError CorePotts.TransitionLifecycleEvent(
        request, cell, cell
    )
    @test_throws ArgumentError CorePotts.TransitionLifecycleEvent(
        request, cell, CorePotts.CellIdentity(2, 2, 4)
    )

    daughter = CorePotts.CellIdentity(2, 1, 3)
    divide = CorePotts.DivideLifecycleEvent(request, cell, transitioned, daughter)
    @test divide.parent_before isa CorePotts.ParentBeforeIdentity
    @test divide.parent_after isa CorePotts.ParentAfterIdentity
    @test divide.daughter_after isa CorePotts.DaughterAfterIdentity
    @test_throws ArgumentError CorePotts.DivideLifecycleEvent(
        request, cell, transitioned, CorePotts.CellIdentity(1, 3, 3)
    )

    first_request = CorePotts.QualifiedLifecycleRequestIdentity(1, 1, 1, 2)
    second_request = CorePotts.QualifiedLifecycleRequestIdentity(2, 1, 1, 2)
    first = CorePotts.TransitionLifecycleEvent(
        first_request, cell, transitioned
    )
    second = CorePotts.RemoveCellLifecycleEvent(second_request, cell)
    source_events = CorePotts.LifecycleEvent[first, second]
    receipt = CorePotts.LifecycleReceipt(7, 99, source_events)
    empty!(source_events)
    @test length(receipt) == 2
    @test CorePotts.lifecycle_events(receipt) == (first, second)
    @test CorePotts.validate_lifecycle_receipt(receipt) === receipt
    @test !Base.ismutable(receipt)
    @test nothing isa CorePotts.MaybeLifecycleReceipt
    @test receipt isa CorePotts.MaybeLifecycleReceipt
    @test_throws ArgumentError CorePotts.LifecycleReceipt(7, 99, (second, first))
    @test_throws ArgumentError CorePotts.LifecycleReceipt(7, 99, (first, first))
end


@testset "real Core transaction publishes every lifecycle receipt variant" begin
    plan = receipt_lifecycle_plan()
    program = receipt_program(plan)
    ownership = zeros(Int32, 6, 6)
    ownership[1, 1] = 1
    ownership[2, 1] = 2
    ownership[4, 3] = 3
    ownership[4, 4] = 3
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 4, 6];
        scalar_type = Float64,
        cell_generations = UInt32[1, 3, 4],
    )
    runtime = CorePotts.initialize_program(
        program,
        initial,
        Float64[],
        UInt64(0x5151),
        UInt32(2);
        repeat = UInt32(1),
    )
    before = CorePotts.program_snapshot(runtime)
    CorePotts.advance_mcs!(runtime)
    @test !CorePotts.program_failed(runtime)
    receipt = CorePotts.program_lifecycle_receipt(runtime)
    after = CorePotts.program_snapshot(runtime)

    @test receipt isa CorePotts.LifecycleReceipt
    @test receipt.completed_mcs == 1
    @test length(receipt) == 4
    events = CorePotts.lifecycle_events(receipt)
    @test count(event -> event isa CorePotts.CreateLifecycleEvent, events) == 1
    @test count(event -> event isa CorePotts.RemoveCellLifecycleEvent, events) == 1
    @test count(event -> event isa CorePotts.RetireLifecycleEvent, events) == 0
    @test count(event -> event isa CorePotts.TransitionLifecycleEvent, events) == 1
    @test count(event -> event isa CorePotts.DivideLifecycleEvent, events) == 1

    create = only(filter(event -> event isa CorePotts.CreateLifecycleEvent, events))
    remove = only(filter(event -> event isa CorePotts.RemoveCellLifecycleEvent, events))
    transition = only(filter(
        event -> event isa CorePotts.TransitionLifecycleEvent, events
    ))
    divide = only(filter(event -> event isa CorePotts.DivideLifecycleEvent, events))

    @test create.after.kind == 8
    @test remove.before == CorePotts.CellIdentity(1, 1, 2)
    @test transition.before == CorePotts.CellIdentity(2, 3, 4)
    @test transition.after == CorePotts.CellIdentity(2, 3, 5)
    @test divide.parent_before.cell == CorePotts.CellIdentity(3, 4, 6)
    @test divide.parent_after.cell == CorePotts.CellIdentity(3, 4, 6)
    @test divide.daughter_after.cell.kind == 7
    @test divide.daughter_after.cell.slot != create.after.slot

    @test before.mcs == 0
    @test after.mcs == 1
    @test after.cell_kinds[Int(remove.before.slot)] == 0
    @test after.cell_kinds[Int(transition.after.slot)] == 5
    @test after.cell_kinds[Int(create.after.slot)] == 8
    @test after.cell_kinds[Int(divide.daughter_after.cell.slot)] == 7
    @test count(==(Int32(divide.parent_after.cell.slot)), after.ownership) == 1
    @test count(==(Int32(divide.daughter_after.cell.slot)), after.ownership) == 1
    @test CorePotts.validate_lifecycle_receipt(receipt) === receipt

    # Retirement is exercised through the production extinction seam. The
    # executor admits a final-site copy only when a compiler-synthesized due
    # retirement exists; the lifecycle transaction then publishes the event.
    retirement_plan = retirement_lifecycle_plan()
    retirement_program = test_program(
        CorePotts.SequentialProgramEngine();
        lifecycle_plan = retirement_plan,
        temperature = 0.0,
    )
    retirement_ownership = zeros(Int32, 6, 6)
    retirement_ownership[3, 3] = 1
    retirement_initial = CorePotts.ProgramInitialState(
        retirement_ownership, Int16[2]; scalar_type = Float64
    )
    retirement_event = nothing
    for seed in UInt64(1):UInt64(128)
        candidate = CorePotts.initialize_program(
            retirement_program,
            retirement_initial,
            Float64[],
            seed,
            UInt32(1),
        )
        for _ in 1:8
            CorePotts.advance_mcs!(candidate)
            candidate_receipt = CorePotts.program_lifecycle_receipt(candidate)
            found = findfirst(
                event -> event isa CorePotts.RetireLifecycleEvent,
                CorePotts.lifecycle_events(candidate_receipt),
            )
            if found !== nothing
                retirement_event = candidate_receipt[found]
                break
            end
        end
        retirement_event === nothing || break
    end
    @test retirement_event isa CorePotts.RetireLifecycleEvent
    @test retirement_event.before == CorePotts.CellIdentity(1, 1, 2)
    @test retirement_event.cause_identity == UInt64(101)
    @test retirement_event.policy_identity == UInt64(201)
end


@testset "atomic bulk component-state receipt application" begin
    policy = TestBulkComponentPolicy(Ref(Int16(6)))
    pool = CorePotts.BulkComponentStatePool(
        Bool[true, true, false, false],
        UInt32[1, 1, 0, 0],
        Int16[1, 2, 0, 0],
        [10, 20, 0, 0],
        policy,
    )
    @test length(pool) == 4
    @test CorePotts.component_identity(pool, 1) == CorePotts.CellIdentity(1, 1, 1)
    @test CorePotts.component_identity(pool, 3) === nothing
    metadata = CorePotts.BackendSPI.component_metadata_snapshot(pool)
    @test metadata.active == Bool[true, true, false, false]
    @test metadata.generations == UInt32[1, 1, 0, 0]
    @test metadata.kinds == Int16[1, 2, 0, 0]
    metadata.generations[1] = 99
    @test CorePotts.BackendSPI.component_metadata_snapshot(pool).generations[1] == 1

    transition = CorePotts.TransitionLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(1, 1, 1, 1),
        CorePotts.CellIdentity(1, 1, 1),
        CorePotts.CellIdentity(1, 1, 3),
    )
    divide = CorePotts.DivideLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(2, 1, 2, 1),
        CorePotts.CellIdentity(2, 1, 2),
        CorePotts.CellIdentity(2, 1, 2),
        CorePotts.CellIdentity(3, 1, 4),
    )
    create = CorePotts.CreateLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(3, 1, 4, 1),
        CorePotts.CellIdentity(4, 1, 5),
    )
    first_receipt = CorePotts.LifecycleReceipt(
        1, 101, CorePotts.LifecycleEvent[transition, divide, create]
    )
    staged = CorePotts.stage_lifecycle_receipt!(pool, first_receipt)
    @test CorePotts.component_state_snapshot(pool) == [10, 20, 0, 0]
    @test CorePotts.bulk_component_completed_mcs(pool) == 0
    @test CorePotts.component_transaction_state(staged) == [310, 10, 10, 500]
    @test CorePotts.abort_component_state_transaction!(staged) === pool
    @test CorePotts.component_state_snapshot(pool) == [10, 20, 0, 0]
    @test CorePotts.bulk_component_completed_mcs(pool) == 0
    @test CorePotts.apply_lifecycle_receipt!(pool, first_receipt) === pool
    @test CorePotts.bulk_component_completed_mcs(pool) == 1
    @test CorePotts.bulk_component_last_transaction_identity(pool) == 101
    @test CorePotts.component_state_snapshot(pool) == [310, 10, 10, 500]
    @test CorePotts.component_identity(pool, 1) == CorePotts.CellIdentity(1, 1, 3)
    @test CorePotts.component_identity(pool, 3) == CorePotts.CellIdentity(3, 1, 4)
    @test CorePotts.component_identity(pool, 4) == CorePotts.CellIdentity(4, 1, 5)

    remove = CorePotts.RemoveCellLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(1, 2, 1, 1),
        CorePotts.CellIdentity(1, 1, 3),
    )
    retire = CorePotts.RetireLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(2, 2, 3, 1),
        CorePotts.CellIdentity(3, 1, 4),
        77,
        88,
    )
    second_receipt = CorePotts.LifecycleReceipt(
        2, 102, CorePotts.LifecycleEvent[remove, retire]
    )
    CorePotts.apply_lifecycle_receipt!(pool, second_receipt)
    @test CorePotts.component_identity(pool, 1) === nothing
    @test CorePotts.component_identity(pool, 3) === nothing
    @test CorePotts.component_state_snapshot(pool) == [-1, 10, -77, 500]

    published = CorePotts.component_state_snapshot(pool)
    @test_throws CorePotts.DuplicateLifecycleReceiptError CorePotts.apply_lifecycle_receipt!(
        pool, second_receipt
    )
    @test CorePotts.component_state_snapshot(pool) == published

    stale = CorePotts.LifecycleReceipt(
        3,
        103,
        CorePotts.LifecycleEvent[
            CorePotts.RemoveCellLifecycleEvent(
                CorePotts.QualifiedLifecycleRequestIdentity(1, 3, 1, 1),
                CorePotts.CellIdentity(1, 1, 3),
            ),
        ],
    )
    @test_throws CorePotts.StaleCellIdentityError CorePotts.apply_lifecycle_receipt!(
        pool, stale
    )
    @test CorePotts.component_state_snapshot(pool) == published
    @test CorePotts.bulk_component_completed_mcs(pool) == 2
    @test CorePotts.bulk_component_last_transaction_identity(pool) == 102

    injected_failure = CorePotts.LifecycleReceipt(
        3,
        104,
        CorePotts.LifecycleEvent[
            CorePotts.CreateLifecycleEvent(
                CorePotts.QualifiedLifecycleRequestIdentity(1, 4, 1, 2),
                CorePotts.CellIdentity(1, 2, 6),
            ),
        ],
    )
    @test_throws ErrorException CorePotts.apply_lifecycle_receipt!(
        pool, injected_failure
    )
    @test CorePotts.component_state_snapshot(pool) == published
    @test CorePotts.component_identity(pool, 1) === nothing
    @test CorePotts.bulk_component_completed_mcs(pool) == 2

    policy.fail_kind[] = 0
    CorePotts.apply_lifecycle_receipt!(pool, injected_failure)
    @test CorePotts.component_identity(pool, 1) == CorePotts.CellIdentity(1, 2, 6)
    @test CorePotts.component_state_snapshot(pool) == [600, 10, -77, 500]
    @test CorePotts.bulk_component_completed_mcs(pool) == 3
    @test CorePotts.bulk_component_last_transaction_identity(pool) == 104

    same_boundary = CorePotts.LifecycleReceipt(3, 105)
    @test_throws CorePotts.LifecycleReceiptOrderError CorePotts.apply_lifecycle_receipt!(
        pool, same_boundary
    )
end


@testset "component transaction groups prevalidate before publication" begin
    policy = TestBulkComponentPolicy(Ref(Int16(0)))
    first_pool = CorePotts.BulkComponentStatePool(
        Bool[true, false], UInt32[1, 0], Int16[1, 0], [10, 0], policy
    )
    second_pool = CorePotts.BulkComponentStatePool(
        Bool[true, false], UInt32[1, 0], Int16[1, 0], [20, 0], policy
    )
    first = CorePotts.stage_lifecycle_receipt!(
        first_pool, CorePotts.LifecycleReceipt(1, 201)
    )
    second = CorePotts.stage_lifecycle_receipt!(
        second_pool, CorePotts.LifecycleReceipt(1, 202)
    )
    tokens = (first, second)

    pop!(CorePotts.component_transaction_state(second))
    @test_throws ArgumentError CorePotts.commit_component_state_transactions!(tokens)
    @test first_pool.pending
    @test second_pool.pending
    @test CorePotts.bulk_component_completed_mcs(first_pool) == 0
    @test CorePotts.bulk_component_completed_mcs(second_pool) == 0
    push!(CorePotts.component_transaction_state(second), 0)

    @test_throws ArgumentError CorePotts.prevalidate_component_state_transactions(
        (first, first)
    )
    @test_throws ArgumentError CorePotts.commit_component_state_transactions!(
        (first, first)
    )
    @test first_pool.pending
    @test second_pool.pending
    @test CorePotts.bulk_component_completed_mcs(first_pool) == 0
    @test CorePotts.bulk_component_completed_mcs(second_pool) == 0

    @test CorePotts.prevalidate_component_state_transactions(tokens) === tokens
    @test CorePotts.publish_component_state_transactions!(tokens) === tokens
    @test CorePotts.bulk_component_completed_mcs(first_pool) == 1
    @test CorePotts.bulk_component_last_transaction_identity(first_pool) == 201
    @test CorePotts.bulk_component_completed_mcs(second_pool) == 1
    @test CorePotts.bulk_component_last_transaction_identity(second_pool) == 202
    @test !first_pool.pending
    @test !second_pool.pending

    next_first = CorePotts.stage_lifecycle_receipt!(
        first_pool, CorePotts.LifecycleReceipt(2, 203)
    )
    next_second = CorePotts.stage_lifecycle_receipt!(
        second_pool, CorePotts.LifecycleReceipt(2, 204)
    )
    next_tokens = (next_first, next_second)
    @test CorePotts.commit_component_state_transactions!(next_tokens) === next_tokens
    @test CorePotts.bulk_component_completed_mcs(first_pool) == 2
    @test CorePotts.bulk_component_last_transaction_identity(first_pool) == 203
    @test CorePotts.bulk_component_completed_mcs(second_pool) == 2
    @test CorePotts.bulk_component_last_transaction_identity(second_pool) == 204
end
