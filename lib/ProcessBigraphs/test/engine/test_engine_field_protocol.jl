import ProcessBigraphs: AbstractEngineAdapter, AbstractEngineInstance,
    EngineDeclaration, EngineCapabilities, AbstractEngineOperation,
    IntervalAdvance, BoundarySolve, DiscreteBatch, EngineInputProjection,
    EngineInvocation, AbstractCompletionHandle, ImmediateCompletionHandle,
    EngineCandidate, EngineEarlyReturn, EngineEventRequest, EngineFailure,
    EngineContinuation, EngineTransactionResult, operation_family,
    operation_start, operation_target, projection_value, prepare_engine,
    stage_operation!, complete_operation!, validate_candidate,
    publish_candidate!, discard_candidate!, execute_engine!,
    engine_semantic_parameters, engine_continuation_action,
    encode_engine_continuation, decode_engine_continuation,
    aggregate_replay_class, FieldDescriptor, FieldGeometry, FieldBoundary,
    FieldState, FieldSampler, FieldDeposition, FieldExchange,
    FieldExchangeResult, FieldAccounting, FieldIterationRegion,
    NamedFieldOperation, FieldSplitPlan, periodic_field_boundaries,
    field_values, sample_field, deposit_field, execute_exchange

struct EngineProtocolMockAdapter <: AbstractEngineAdapter
    mode::Symbol
end

engine_semantic_parameters(adapter::EngineProtocolMockAdapter) = (mode=adapter.mode,)
ProcessBigraphs.field_engine_array_type(
    ::EngineProtocolMockAdapter,
) = Vector{Float64}

mutable struct EngineProtocolMockInstance <: AbstractEngineInstance
    mode::Symbol
    published::Vector{Float64}
    staged::Union{Nothing,Vector{Float64}}
    discard_count::Int
end

prepare_engine(adapter::EngineProtocolMockAdapter, declaration::EngineDeclaration) =
    EngineProtocolMockInstance(adapter.mode, [0.0], nothing, 0)

struct EngineProtocolThrowCompletionHandle <: AbstractCompletionHandle end

complete_operation!(
    instance::EngineProtocolMockInstance,
    ::EngineProtocolThrowCompletionHandle,
) = throw(ProcessBigraphError(:mock_completion_failure,
    "requested completion failure"))

function stage_operation!(
    instance::EngineProtocolMockInstance,
    invocation::EngineInvocation,
)
    start = operation_start(invocation.operation)
    target = operation_target(invocation.operation)
    if instance.mode === :stage_throw
        throw(ProcessBigraphError(:mock_stage_failure,
            "requested staging failure"))
    elseif instance.mode === :complete_throw
        return EngineProtocolThrowCompletionHandle()
    elseif instance.mode === :failure
        return ImmediateCompletionHandle(EngineFailure(
            :mock_solver_failure,
            :solve;
            retry_class=:reconstruct,
            diagnostics=(raw_code=17,),
        ))
    elseif instance.mode === :early
        return ImmediateCompletionHandle(EngineEarlyReturn(
            start + Duration(1, start.scale),
            :root_found;
            diagnostics=(root=:threshold,),
        ))
    elseif instance.mode === :event
        return ImmediateCompletionHandle(EngineEventRequest(
            start + Duration(1, start.scale),
            :divide,
            (cell="cell-1",),
        ))
    end
    input = projection_value(only(invocation.inputs))
    candidate = Float64.(input) .* 2
    instance.staged = candidate
    actual = instance.mode === :bad_time ? start : target
    continuation = EngineContinuation(
        "mock-engine",
        "doubling-state",
        (calls=1,);
        replay_class=:exact,
        invalidated_by=(:algorithm, :precision),
    )
    ImmediateCompletionHandle(EngineCandidate(
        actual,
        candidate;
        effects=(:state_sum => sum(candidate),),
        continuation,
        diagnostics=(iterations=2,),
        fingerprint=canonical_fingerprint((:mock_candidate, candidate, actual)),
    ))
end

function publish_candidate!(
    instance::EngineProtocolMockInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate,
)
    instance.mode === :publish_throw &&
        throw(ProcessBigraphError(:mock_publication_failure,
            "requested publication failure"))
    instance.staged === candidate.payload ||
        error("published candidate was not the staged candidate")
    instance.published = candidate.payload
    instance.staged = nothing
    (version=UInt64(1), fingerprint=candidate.fingerprint)
end

function discard_candidate!(
    instance::EngineProtocolMockInstance,
    invocation::EngineInvocation,
    candidate,
)
    instance.mode === :discard_throw &&
        throw(ProcessBigraphError(:mock_discard_failure,
            "requested discard failure"))
    instance.staged = nothing
    instance.discard_count += 1
    nothing
end

function engine_protocol_publication_allocations(
    instance::EngineProtocolMockInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate,
)
    @allocated publish_candidate!(instance, invocation, candidate)
end

function engine_protocol_declaration(mode::Symbol=:success)
    capabilities = EngineCapabilities(
        operation_families=(:interval_advance, :boundary_solve, :discrete_batch),
        problem_envelopes=("engine_protocol-mock",),
        backends=(:cpu,),
        precisions=(:float64,),
        residencies=(:host,),
        input_modes=(:frozen, :event_updated),
        boundary_kinds=(:periodic, :dirichlet, :neumann, :mixed),
        continuation_actions=(:preserve, :reconstruct, :reject),
        replay_class=:exact,
        cancellation=true,
        diagnostics=true,
    )
    EngineDeclaration("engine_protocol-mock", EngineProtocolMockAdapter(mode); capabilities)
end

@testset "managed field process supported constructor" begin
    declaration = engine_protocol_declaration()
    authorization = (
        backend=:cpu,
        precision=:float64,
        residency=:host,
    )
    process = managed_field_process(
        declaration;
        resource_authorization=authorization,
        subcycles_per_mcs=2,
    )
    @test process isa AbstractProcess
    @test nameof(typeof(process)) === :ManagedFieldAdvanceProcess
    @test :ManagedFieldAdvanceProcess ∉ names(ProcessBigraphs)
    @test semantic_parameters(process).resource_authorization ==
          authorization
    @test semantic_parameters(process).subcycles_per_mcs == 2
    @test_throws UndefKeywordError managed_field_process(declaration)
    @test_throws ProcessBigraphError managed_field_process(
        declaration; resource_authorization=NamedTuple())
    @test_throws ProcessBigraphError managed_field_process(
        declaration;
        resource_authorization=(backend=:cpu,))
    @test_throws ProcessBigraphError managed_field_process(
        declaration;
        resource_authorization=(
            backend=:metal,
            precision=:float64,
            residency=:host,
        ))
    @test_throws ProcessBigraphError managed_field_process(
        declaration;
        resource_authorization=authorization,
        subcycles_per_mcs=0,
    )
end

function engine_protocol_invocation(
    declaration::EngineDeclaration,
    values;
    id="invocation-1",
    start_tick=0,
    target_tick=3,
)
    scale = TimeScale(1)
    start = LogicalTime(start_tick, scale)
    target = LogicalTime(target_tick, scale)
    input = EngineInputProjection(:state, 0, start, values; mode=:frozen)
    EngineInvocation(
        id,
        :scheduled_field_advance,
        declaration,
        IntervalAdvance(start, target);
        structural_epoch="epoch-1",
        inputs=(input,),
        resource_authorization=(backend=:cpu, bytes=1024),
        expected_outputs=(:state_sum,),
        expected_diagnostics=(:iterations,),
    )
end

@testset "engine and field protocol solver-neutral engine transaction" begin
    declaration = engine_protocol_declaration()
    instance = prepare_engine(declaration)
    source = [1.0, 2.0]
    invocation = engine_protocol_invocation(declaration, source)
    source[1] = 99.0
    @test projection_value(only(invocation.inputs)) == [1.0, 2.0]
    @test declaration.fingerprint ==
          engine_protocol_declaration().fingerprint

    result = execute_engine!(instance, invocation)
    @test result.status === :published
    @test instance.published == [2.0, 4.0]
    @test isnothing(instance.staged)
    @test result.outcome.actual_time == LogicalTime(3, TimeScale(1))
    @test result.outcome.effects == (:state_sum => 6.0,)
    @test result.outcome.continuation.replay_class === :exact

    allocation_instance = prepare_engine(declaration)
    allocation_handle = stage_operation!(allocation_instance, invocation)
    allocation_candidate = complete_operation!(allocation_instance, allocation_handle)
    validate_candidate(allocation_instance, invocation, allocation_candidate)
    engine_protocol_publication_allocations(
        allocation_instance, invocation, allocation_candidate)
    allocation_instance.staged = allocation_candidate.payload
    @test engine_protocol_publication_allocations(
        allocation_instance, invocation, allocation_candidate) == 0

    unauthorized = prepare_engine(declaration)
    error = try
        execute_engine!(unauthorized, invocation; authorize=(candidate, invocation) -> false)
        nothing
    catch caught
        caught
    end
    @test error isa ProcessBigraphError
    @test error.code === :engine_candidate_unauthorized
    @test unauthorized.published == [0.0]
    @test isnothing(unauthorized.staged)
    @test unauthorized.discard_count == 1

    bad_declaration = engine_protocol_declaration(:bad_time)
    bad_instance = prepare_engine(bad_declaration)
    @test_throws ProcessBigraphError execute_engine!(
        bad_instance, engine_protocol_invocation(bad_declaration, [1.0]))
    @test bad_instance.published == [0.0]
    @test bad_instance.discard_count == 1

    failure_declaration = engine_protocol_declaration(:failure)
    failure_instance = prepare_engine(failure_declaration)
    failure = try
        execute_engine!(
            failure_instance,
            engine_protocol_invocation(failure_declaration, [1.0]),
        )
        nothing
    catch caught
        caught
    end
    @test failure isa ProcessBigraphError
    @test failure.code === :mock_solver_failure
    @test failure.context.retry_class === :reconstruct
    @test failure_instance.discard_count == 1

    for (mode, code) in (
        :stage_throw => :mock_stage_failure,
        :complete_throw => :mock_completion_failure,
        :publish_throw => :mock_publication_failure,
    )
        staged_declaration = engine_protocol_declaration(mode)
        staged_instance = prepare_engine(staged_declaration)
        staged_error = try
            execute_engine!(
                staged_instance,
                engine_protocol_invocation(staged_declaration, [1.0]),
            )
            nothing
        catch caught
            caught
        end
        @test staged_error isa ProcessBigraphError
        @test staged_error.code === code
        @test staged_instance.published == [0.0]
        @test isnothing(staged_instance.staged)
        @test staged_instance.discard_count == 1
    end

    discard_declaration = engine_protocol_declaration(:discard_throw)
    discard_instance = prepare_engine(discard_declaration)
    discard_error = try
        execute_engine!(
            discard_instance,
            engine_protocol_invocation(discard_declaration, [1.0]);
            authorize=(candidate, invocation) -> false,
        )
        nothing
    catch caught
        caught
    end
    @test discard_error isa ProcessBigraphError
    @test discard_error.code === :engine_candidate_unauthorized
    @test discard_instance.published == [0.0]

    early_declaration = engine_protocol_declaration(:early)
    early_instance = prepare_engine(early_declaration)
    early = execute_engine!(
        early_instance,
        engine_protocol_invocation(early_declaration, [1.0]),
    )
    @test early.status === :returned
    @test early.outcome isa EngineEarlyReturn
    @test early.outcome.actual_time == LogicalTime(1, TimeScale(1))
    @test early_instance.published == [0.0]

    event_declaration = engine_protocol_declaration(:event)
    event = execute_engine!(
        prepare_engine(event_declaration),
        engine_protocol_invocation(event_declaration, [1.0]),
    )
    @test event.outcome isa EngineEventRequest
    @test event.outcome.event === :divide

    @test_throws ProcessBigraphError EngineCapabilities(backends=(:quantum,))
    @test_throws ProcessBigraphError EngineCapabilities(
        operation_families=(:interval_advance, :interval_advance))
    @test_throws ProcessBigraphError EngineInvocation(
        "unsupported",
        :scheduled,
        EngineDeclaration(
            "boundary-only",
            EngineProtocolMockAdapter(:success);
            capabilities=EngineCapabilities(
                operation_families=(:boundary_solve,),
            ),
        ),
        IntervalAdvance(LogicalTime(0, TimeScale(1)), LogicalTime(1, TimeScale(1)));
        structural_epoch="epoch-1",
    )
    @test_throws ProcessBigraphError EngineInvocation(
        "unsupported-backend",
        :scheduled,
        declaration,
        IntervalAdvance(LogicalTime(0, TimeScale(1)), LogicalTime(1, TimeScale(1)));
        structural_epoch="epoch-1",
        resource_authorization=(backend=:metal,),
    )
end

@testset "engine and field protocol typed continuation and restart cuts" begin
    continuation = EngineContinuation(
        "engine-1",
        "state-v1",
        (step=7, residual=0.125);
        schema_version="2.0.0",
        codec_version="1.1.0",
        replay_class=:numerical,
        invalidated_by=(:precision, :geometry),
    )
    encoded = encode_engine_continuation(continuation)
    decoded = decode_engine_continuation(
        encoded;
        owner="engine-1",
        identity="state-v1",
        schema_version="2.0.0",
        codec_version="1.1.0",
    )
    @test decoded.value == continuation.value
    @test decoded.fingerprint == continuation.fingerprint
    @test engine_continuation_action(decoded, (:backend,)) === :preserve
    @test engine_continuation_action(decoded, (:precision,);
        invalidated_action=:reconstruct) === :reconstruct
    @test aggregate_replay_class((:exact, :numerical, :statistical)) === :statistical
    @test_throws ProcessBigraphError decode_engine_continuation(
        encoded;
        owner="other-engine",
        identity="state-v1",
        schema_version="2.0.0",
        codec_version="1.1.0",
    )

    declaration = engine_protocol_declaration()
    operations = ([1.0], [2.0], [4.0])
    expected = [8.0]
    for cut in 0:length(operations)
        instance = prepare_engine(declaration)
        saved_values = [0.0]
        saved_continuation = nothing
        for (index, values) in enumerate(operations)
            result = execute_engine!(
                instance,
                engine_protocol_invocation(
                    declaration,
                    values;
                    id="restart-$(cut)-$(index)",
                    start_tick=index - 1,
                    target_tick=index,
                ),
            )
            saved_values = copy(instance.published)
            saved_continuation =
                encode_engine_continuation(result.outcome.continuation)
            if index == cut
                restored = prepare_engine(declaration)
                restored.published = copy(saved_values)
                restored_continuation = decode_engine_continuation(
                    saved_continuation;
                    owner="mock-engine",
                    identity="doubling-state",
                    schema_version="1.0.0",
                    codec_version="1.0.0",
                )
                @test restored_continuation.value == (calls=1,)
                instance = restored
            end
        end
        @test instance.published == expected
    end
end

@testset "engine and field protocol field descriptor, sampling, deposition, and exchange" begin
    scale = TimeScale(1)
    geometry = FieldGeometry(
        (2, 2);
        origin=(0.0, 0.0),
        spacing=(1.0, 1.0),
        axis_order=(:x, :y),
    )
    descriptor = FieldDescriptor(
        "chemoattractant",
        (:vegf,),
        geometry;
        numeric_type=Float64,
        units=(:vegf => "mol/m^3",),
        sampling_law=:linear,
        boundaries=periodic_field_boundaries(2),
        operation="diffusion-decay",
        positivity=:reject,
        conservation=:conservative,
        insufficiency=:partial_proportional,
        accounting_tolerance=1.0e-12,
        semantic_time=LogicalTime(0, scale),
    )
    values = reshape([1.0, 2.0, 3.0, 4.0], 2, 2, 1)
    state = FieldState(descriptor, values)
    values[1] = 99.0
    @test field_values(state)[1, 1, 1] == 1.0
    @test sample_field(
        state,
        FieldSampler(descriptor, :vegf, (0.5, 0.5); law=:linear),
    ) == 1.0
    @test sample_field(
        state,
        FieldSampler(descriptor, :vegf, (2.5, 0.5); law=:nearest),
    ) == 1.0

    deposition = FieldDeposition(
        descriptor,
        :vegf,
        "cell-1",
        ((0.5, 0.5), (1.5, 1.5)),
        (2.0, 3.0);
        law=:nearest,
        units="mol/m^3",
    )
    deposited, accounting = deposit_field(state, deposition)
    @test field_values(deposited)[1, 1, 1] == 3.0
    @test field_values(deposited)[2, 2, 1] == 7.0
    @test accounting.residual ≈ 0.0 atol=1.0e-12
    @test deposited.version == state.version + 1
    @test field_values(state)[1, 1, 1] == 1.0

    exchange = execute_exchange(FieldExchange(
        "competing-uptake",
        10.0,
        ("cell-b" => 8.0, "cell-a" => 8.0);
        allocation=:proportional,
        insufficiency=:partial_proportional,
        conservative=true,
        tolerance=1.0e-12,
    ))
    @test Dict(exchange.allocations) ==
          Dict("cell-a" => 5.0, "cell-b" => 5.0)
    @test exchange.remaining == 0.0
    @test exchange.accounting.residual ≈ 0.0 atol=1.0e-12
    @test_throws ProcessBigraphError execute_exchange(FieldExchange(
        "reject-shortage",
        1.0,
        ("cell-a" => 2.0,);
        insufficiency=:reject,
    ))

    dirichlet = tuple((
        FieldBoundary(axis, side, :dirichlet; parameters=(value=0.0,))
        for axis in 1:2 for side in (:low, :high)
    )...)
    nonperiodic = FieldDescriptor(
        "bounded",
        (:u,),
        geometry;
        units=(:u => "dimensionless",),
        boundaries=dirichlet,
        semantic_time=LogicalTime(0, scale),
    )
    bounded_state = FieldState(nonperiodic, zeros(2, 2, 1))
    @test_throws ProcessBigraphError sample_field(
        bounded_state,
        FieldSampler(nonperiodic, :u, (-0.1, 0.5)),
    )
    @test_throws ProcessBigraphError FieldDescriptor(
        "unpaired",
        (:u,),
        geometry;
        units=(:u => "dimensionless",),
        boundaries=(
            FieldBoundary(1, :low, :periodic),
            FieldBoundary(1, :high, :dirichlet; parameters=(value=0.0,)),
            FieldBoundary(2, :low, :periodic),
            FieldBoundary(2, :high, :periodic),
        ),
    )
end

@testset "engine and field protocol exact field clocks and named splitting" begin
    scale = TimeScale(1)
    start = LogicalTime(0, scale)
    target = LogicalTime(1, scale)
    deposit = NamedFieldOperation("deposit", :deposit, start, start)
    evolve = NamedFieldOperation(
        "evolve",
        :evolve,
        start,
        target;
        input_mode=:frozen,
        dependencies=("deposit",),
    )
    sample = NamedFieldOperation(
        "sample",
        :sample,
        target,
        target;
        dependencies=("evolve",),
    )
    plan = FieldSplitPlan((deposit, evolve, sample))
    @test !isempty(plan.fingerprint)
    @test plan.operations == (deposit, evolve, sample)

    left = NamedFieldOperation(
        "left", :exchange, start, target; dependencies=("right",))
    right = NamedFieldOperation(
        "right", :exchange, start, target; dependencies=("left",))
    @test_throws ProcessBigraphError FieldSplitPlan((left, right))
    iterative = FieldSplitPlan(
        (left, right);
        iterative_regions=(
            FieldIterationRegion(
                "feedback",
                ("left", "right");
                max_iterations=8,
            ),
        ),
    )
    @test only(iterative.iterative_regions).max_iterations == 8
    @test_throws ProcessBigraphError NamedFieldOperation(
        "backwards",
        :evolve,
        target,
        start,
    )
end
