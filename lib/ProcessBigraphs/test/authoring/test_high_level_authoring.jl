import ProcessBigraphs: StaticComposite, ProcessDeclaration,
    StepDeclaration, PortBinding, compile_composite, AbstractProcess,
    AbstractStep, ports, invoke,
    semantic_parameters, parameter_names, with_parameters

struct PB0ParameterizedIncrement <: AbstractProcess
    amount::Int
end
ports(::PB0ParameterizedIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)
semantic_parameters(law::PB0ParameterizedIncrement) = (amount=law.amount,)
parameter_names(::PB0ParameterizedIncrement) = (:amount,)
with_parameters(
    ::PB0ParameterizedIncrement,
    values::NamedTuple{(:amount,)},
) = PB0ParameterizedIncrement(values.amount)
function invoke(law::PB0ParameterizedIncrement, inputs, context)
    InvocationResult((
        emit(context, :increment, AdditiveUpdate(), law.amount),
    ))
end

struct PB0TriggeredIncrement <: AbstractStep end
ports(::PB0TriggeredIncrement) = (
    InputPort(Int, :trigger),
    OutputPort(Int, :out; update_law=:add),
)
function invoke(::PB0TriggeredIncrement, inputs, context)
    InvocationResult((
        emit(context, :out, AdditiveUpdate(), 10),
    ))
end

struct PB0OneShotIncrement <: AbstractProcess end
ports(::PB0OneShotIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)
function invoke(::PB0OneShotIncrement, inputs, context)
    InvocationResult((
        emit(context, :increment, AdditiveUpdate(), 1),
    ))
end

function pb0_component_encoder(law)
    law isa PB0Increment && return (
        id="pb0.increment",
        version="1.0.0",
        payload=(amount=law.amount,))
    law isa PB0ForkStep && return (
        id="pb0.fork-step",
        version="1.0.0",
        payload=(port=law.port, amount=law.amount))
    error("unsupported test component $(typeof(law))")
end

function pb0_component_decoder(id, version, payload)
    version == "1.0.0" || error("unsupported fixture codec version")
    id == "pb0.increment" && return PB0Increment(payload.amount)
    id == "pb0.fork-step" &&
        return PB0ForkStep(payload.port, payload.amount)
    error("unknown fixture component codec $id")
end

@testset "semantic builder lifecycle and lowering" begin
    scale = TimeScale(1)
    captured_builder = Ref{Any}()
    captured_state = Ref{Any}()
    captured_attachment = Ref{Any}()
    model = compose(:Counter; scale, profile=:reproducible) do m
        captured_builder[] = m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        copied = store!(
            m, :copied,
            LeafSchema(Int; default=0, update_law=:add))
        captured_state[] = state
        increment = mount!(m, :increment, PB0Increment(2))
        copy = mount!(m, :copy, PB0ForkStep(:left, 1))
        schedule!(m, increment, Every(Duration(1, scale)))
        captured_attachment[] = attach!(m, increment, (
            state=state,
            increment=state,
        ))
        connect!(m, copy.left, copied)
        parameter!(m, :gain, 2.0;
            units="dimensionless",
            description="Example typed problem parameter")
        observable!(m, :state_value, state)
    end

    @test model isa CompositeModel
    @test describe(model).name === :Counter
    @test propertynames(model.parameters) == (:gain,)
    @test model.parameters.gain.default == 2.0
    @test model.state.state.target == path("state")
    @test semantic_fingerprint(model) == model.fingerprint
    @test explain(captured_attachment[]).exact
    @test explain(captured_attachment[]).connected ==
        (:increment, :state)
    @test_throws ProcessBigraphError store!(
        captured_builder[], :late,
        LeafSchema(Int; default=0))

    lowered = lower(model)
    compiled = compile(lowered)
    @test lowered isa LoweredModel
    @test ir_fingerprint(lowered) == structural_fingerprint(compiled)
    @test plan_fingerprint(compiled) ==
        execution_plan_fingerprint(compiled)
    @test !isempty(origin_map(lowered))
    @test origin_map(compiled) == origin_map(lowered)
    @test describe(model).semantic_fingerprint ==
        semantic_fingerprint(model)

    direct = compile_composite(StaticComposite(
        BranchSchema(
            state=LeafSchema(Int; default=0, update_law=:add),
            copied=LeafSchema(Int; default=0, update_law=:add),
        ),
        Dict(),
        scale;
        processes=(
            ProcessDeclaration(
                "increment",
                PB0Increment(2),
                FixedSchedule(Duration(1, scale)),
            ),
        ),
        steps=(StepDeclaration("copy", PB0ForkStep(:left, 1)),),
        bindings=(
            PortBinding("increment", :state, path("state")),
            PortBinding("increment", :increment, path("state")),
            PortBinding("copy", :left, path("copied")),
        ),
    ))
    @test model_fingerprint(compiled) == model_fingerprint(direct)
    @test structural_fingerprint(compiled) ==
        structural_fingerprint(direct)

    archive = ProcessBigraphs.encode_semantic_model(
        model; encode_component=pb0_component_encoder)
    decoded = ProcessBigraphs.decode_semantic_model(
        archive; decode_component=pb0_component_decoder)
    @test semantic_fingerprint(decoded) == semantic_fingerprint(model)
    @test ir_fingerprint(lower(decoded)) == ir_fingerprint(lower(model))
    @test_throws ProcessBigraphError ProcessBigraphs.decode_semantic_model(
        archive;
        decode_component=(id, version, payload) -> PB0Increment(999))
    payload = decode_logical_value(archive)
    future_archive = encode_logical_value(merge(
        payload, (format_version="999.0.0",)))
    @test_throws ProcessBigraphError ProcessBigraphs.decode_semantic_model(
        future_archive; decode_component=pb0_component_decoder)

    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(2, scale))
    @test current_snapshot(runtime)[path("state")] == 4
    @test current_snapshot(runtime)[path("copied")] == 2

    problem = SimulationProblem(model;
        initial=(model.state.state => 5,),
        parameters=(model.parameters.gain => 3.0,),
        observations=(model.observables.state_value,))
    variant = remake(problem;
        parameters=(model.parameters.gain => 4.0,))
    @test problem_fingerprint(problem) != problem_fingerprint(variant)
    @test problem_fingerprint(problem) ==
        problem_fingerprint(remake(problem))
    @test problem.observations == (:state_value => true,)
    problem_runtime = initialize_runtime(problem)
    @test current_snapshot(problem_runtime)[path("state")] == 5
end

@testset "relationship connections, exact At, and On scheduling" begin
    scale = TimeScale(1)
    model = compose(:ExactEvents; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        pulse = mount!(m, :pulse, PB0OneShotIncrement())
        reaction = mount!(m, :reaction, PB0TriggeredIncrement())
        schedule!(m, pulse, At(
            LogicalTime(5, scale),
            LogicalTime(2, scale)))
        connect!(
            m, state,
            pulse.state, pulse.increment,
            reaction.trigger, reaction.out)
        schedule!(m, reaction, On(state))
    end
    compiled = compile(model)
    executor = SerialExecutor()
    runtime = initialize_runtime(compiled, executor)
    run_until!(runtime, LogicalTime(6, scale))
    @test current_snapshot(runtime)[path("state")] == 22
    @test all(isnothing(clock.next_due) for clock in runtime.process_clocks)
    resumed = restore(
        compiled,
        executor,
        encode_checkpoint(logical_checkpoint(runtime)))
    run_until!(resumed, LogicalTime(8, scale))
    @test current_snapshot(resumed)[path("state")] == 22
    pulse_origins = filter(
        origin -> origin.kind === :component && origin.name === :pulse,
        origin_map(compiled))
    @test length(pulse_origins) == 2
    # The explicit relationship already connected `reaction.out`, so exact
    # attachment detects the duplicate rather than silently rewiring it.
    @test_throws ProcessBigraphError compose(:DuplicateRelation; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        actor = mount!(m, :actor, PB0ForkStep(:out, 1))
        connect!(m, state, actor.out)
        attach!(m, actor, (out=state,))
    end
end

@testset "problem parameters are validated and rebound before compilation" begin
    scale = TimeScale(1)
    model = compose(:ParameterizedCounter; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        amount = parameter!(m, :amount, 2)
        increment = mount!(m, :increment, PB0ParameterizedIncrement(0))
        schedule!(m, increment, Every(Duration(1, scale)))
        attach!(m, increment, (state=state, increment=state))
        observable!(m, :state, state)
        @test amount.default == 2
    end

    default_runtime = initialize_runtime(SimulationProblem(model))
    override_runtime = initialize_runtime(SimulationProblem(
        model; parameters=(amount=4,), seed=11))
    run_until!(default_runtime, LogicalTime(1, scale))
    run_until!(override_runtime, LogicalTime(1, scale))
    @test current_snapshot(default_runtime)[path("state")] == 2
    @test current_snapshot(override_runtime)[path("state")] == 4
    @test_throws ProcessBigraphError SimulationProblem(
        model; parameters=(amount=4.0,))
    other = compose(:OtherParameterizedCounter; scale) do m
        store!(m, :state, LeafSchema(Int; default=0))
        parameter!(m, :amount, 2)
    end
    @test_throws ProcessBigraphError SimulationProblem(
        model; parameters=(other.parameters.amount => 4,))
    @test_throws ProcessBigraphError initialize_runtime(
        SimulationProblem(model; seed=11),
        SerialExecutor(
            qualification=:legacy_compatibility,
            root_seed=12))
end

@testset "typed problem interventions use ordinary atomic publication" begin
    scale = TimeScale(1)
    model = compose(:IntervenedState; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        observable!(m, :state, state)
    end
    kick = StateIntervention(
        :kick,
        LogicalTime(2, scale),
        model.state.state,
        AdditiveUpdate(),
        7)
    problem = SimulationProblem(
        model;
        interventions=(kick,),
        observations=(model.observables.state,),
        tspan=(LogicalTime(0, scale), LogicalTime(3, scale)),
        seed=13)
    runtime = initialize_runtime(problem)
    run_until!(runtime, last(problem.tspan))
    @test current_snapshot(runtime)[path("state")] == 7
    @test all(isnothing(clock.next_due)
        for clock in runtime.process_clocks)

    changed = remake(problem; interventions=(StateIntervention(
        :kick,
        LogicalTime(2, scale),
        model.state.state,
        AdditiveUpdate(),
        9),))
    @test problem_fingerprint(changed) != problem_fingerprint(problem)
    other = compose(:OtherIntervenedState; scale) do m
        store!(m, :state, LeafSchema(Int; default=0, update_law=:add))
    end
    foreign = StateIntervention(
        :foreign,
        LogicalTime(1, scale),
        other.state.state,
        AdditiveUpdate(),
        1)
    @test_throws ProcessBigraphError SimulationProblem(
        model; interventions=(foreign,))
    @test_throws ProcessBigraphError SimulationProblem(
        model;
        interventions=(kick,),
        tspan=(LogicalTime(0, scale), LogicalTime(1, scale)))
end

@testset "ordinary Julia expressibility and deterministic identity" begin
    scale = TimeScale(1)
    function counter(order)
        compose(:Generated; scale) do m
            stores = Dict(
                :a => store!(m, :a,
                    LeafSchema(Int; default=0, update_law=:add)),
                :b => store!(m, :b,
                    LeafSchema(Int; default=0, update_law=:add)),
            )
            for name in order
                actor = mount!(
                    m, Symbol(:actor_, name), PB0Increment(1))
                schedule!(m, actor, Every(Duration(1, scale)))
                attach!(m, actor, (
                    state=stores[name],
                    increment=stores[name],
                ))
            end
        end
    end

    left = counter((:a, :b))
    right = counter((:b, :a))
    @test semantic_fingerprint(left) == semantic_fingerprint(right)
    @test ir_fingerprint(lower(left)) == ir_fingerprint(lower(right))
    @test plan_fingerprint(compile(left)) == plan_fingerprint(compile(right))

    function observed(target)
        compose(:Observed; scale) do m
            a = store!(m, :a, LeafSchema(Int; default=0))
            b = store!(m, :b, LeafSchema(Int; default=0))
            observable!(m, :value, target === :a ? a : b)
        end
    end
    @test semantic_fingerprint(observed(:a)) !=
        semantic_fingerprint(observed(:b))
end

@testset "hierarchy, shared junctions, and explicit exports" begin
    scale = TimeScale(1)
    child = compose(:CounterDefinition; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        increment = mount!(m, :increment, PB0Increment(1))
        schedule!(m, increment, Every(Duration(1, scale)))
        attach!(m, increment, (
            state=state,
            increment=state,
        ))
        expose!(m, :state, state; role=:bidirectional)
    end

    system = compose(:CounterSystem; scale) do m
        shared = store!(
            m, :shared,
            LeafSchema(Int; default=0, update_law=:add))
        left = mount!(m, :left, child)
        right = mount!(m, :right, child)
        connect!(m, left.state, shared)
        connect!(m, right.state, shared)
        expose!(m, :state, shared; role=:bidirectional)
    end
    lowered = lower(system)
    @test length(ProcessBigraphs.ACSets.parts(
        canonical_structure(lowered), :Composite)) == 3
    @test length(ProcessBigraphs.ACSets.parts(
        canonical_structure(lowered), :Junction)) == 1
    compiled = compile(system)
    provenance_ids = Set(first.(structural_provenance(compiled).entries))
    origins = origin_map(compiled)
    # Every compiled structural entity retains an author-facing location.
    @test provenance_ids <= Set(
        origin.canonical_identity for origin in origins)
    @test Set(origin.location for origin in origins
        if origin.kind === :component &&
            origin.name === :increment) ==
        Set(((:left, :increment), (:right, :increment)))
    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(1, scale))
    @test current_snapshot(runtime)[path("shared")] == 2
end

@testset "structured diagnostics and exact attachment" begin
    scale = TimeScale(1)
    caught = try
        compose(:Invalid; scale) do m
            state = store!(
                m, :state,
                LeafSchema(Int; default=0, update_law=:add))
            actor = mount!(m, :actor, PB0Increment(1))
            connect!(m, actor.state, state)
        end
        nothing
    catch error
        error
    end
    @test caught isa ModelValidationError
    codes = Set(diagnostic.code for diagnostic in caught.report.diagnostics)
    @test :missing_process_schedule in codes
    @test :unbound_required_port in codes
    @test all(!isempty(diagnostic.location)
        for diagnostic in caught.report.diagnostics)
    @test all(!isempty(diagnostic.suggestion)
        for diagnostic in caught.report.diagnostics)

    @test_throws ProcessBigraphError compose(:Inexact; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        actor = mount!(m, :actor, PB0Increment(1))
        schedule!(m, actor, Every(Duration(1, scale)))
        attach!(m, actor, (state=state,))
    end
end

@testset "structural templates author typed requests" begin
    scale = TimeScale(1)
    cell = compose(:Cell; scale) do m
        state = store!(
            m, :state,
            LeafSchema(Int; default=0, update_law=:add))
        expose!(m, :state, state; role=:bidirectional)
    end
    template = Ref{Any}()
    host = compose(:Host; scale) do m
        shared = store!(
            m, :shared,
            LeafSchema(Int; default=0, update_law=:add))
        template[] = allow_instances!(m, :cells, cell; capacity=8)
        # A template declaration does not instantiate or connect a runtime child.
        observable!(m, :shared, shared)
    end
    @test host isa CompositeModel
    parent = ProcessBigraphs.StructuralIdentity(:Composite, "root", 0)
    request = spawn(template[], "spawn-1", 0, parent, :cell_1)
    @test request isa ProcessBigraphs.AddCompositeRequest
    @test request.definition_id == "Cell"
end
