@testset "qualified effective initials govern units, scheduling, and storage" begin
    @variables distance speed
    @variables memory::NamedTuple{(:distance, :clock), Tuple{Float64, NamedTuple{(:duration,), Tuple{Float64}}}}
    state = ModelState(memory)
    child = PottsSystem(
        name = :reader,
        statements = StatementSet(
            (
                ModelState(distance), state, ModelState(speed),
                Synchronous(:measure, Assign(speed, (distance + state.distance) / state.clock.duration)),
            )
        ),
        unknowns = (distance, memory, speed),
        initial_conditions = Dict(
            distance => 2.0u"m",
            memory => (distance = 6.0u"m", clock = (duration = 2.0u"s",)),
            speed => 0.0u"m/s",
        ),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    qualified_distance = ModelingToolkitBase.renamespace(:reader, distance)
    source = PottsSystem(
        name = :effective_initials,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        systems = (child,),
        initial_conditions = Dict(qualified_distance => 4.0u"m"),
    )
    references = ReferenceUnits(length = 1.0u"m", time = 1.0u"s", speed = 1.0u"m/s")
    completed = complete(source; reference_units = references)
    @test ModelingToolkitBase.initial_conditions(completed)[qualified_distance] == 4.0u"m"
    scheduled = mtkcompile(completed)
    entry = only(filter(entry -> entry.key === :reader₊distance, inspect(scheduled, StateSchema()).states))
    @test entry.initial == 4.0u"m"
    @test entry.initial_source === :system
    analysis = Potts._analyze_completed_system(completed)
    root = only(filter(root -> root.role === :effect_1_value, analysis.graph.roots))
    @test analysis.facts.units[root.node] == Potts._canonical_dimension(DynamicQuantities.dimension(1.0u"m/s"))
    ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)
    problem = PottsProblem(scheduled, PottsInitialState(; ownership), (0, 1); seed = 23)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        @test integrator.u[:reader₊distance] === 4.0f0
        @test integrator.u[:reader₊memory] === (distance = 6.0f0, clock = (duration = 2.0f0,))
        step!(integrator)
        @test integrator.u[:reader₊speed] === 5.0f0
    end
end

@testset "declaration and system initial conflicts use qualified identity" begin
    @variables amount
    function initial_source(declared, supplied)
        child = PottsSystem(
            name = :child,
            statements = StatementSet((ModelState(amount; initial = declared),)),
            unknowns = (amount,),
            initial_conditions = Dict(amount => supplied),
        )
        return PottsSystem(name = :root, systems = (child,))
    end
    references = ReferenceUnits(length = 1.0u"m")
    equal = mtkcompile(complete(initial_source(2.0u"m", 2.0u"m"); reference_units = references))
    @test only(inspect(equal, StateSchema()).states).initial == 2.0u"m"
    @test_throws r"conflicting declaration and PottsSystem initial conditions" mtkcompile(
        complete(initial_source(2.0u"m", 3.0u"m"); reference_units = references)
    )
end
