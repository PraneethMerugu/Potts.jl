using StaticArrays

function _component_dependency_fixture(; shared_initial = SVector(2.0u"m", 4.0u"m"), unrelated_default = 17.0)
    @parameters coefficients[1:2] = [2.0, 3.0]
    @parameters unrelated_parameter = unrelated_default
    @variables shared[1:2] unused[1:2] incoming[1:2] remote[1:2] response[1:2]
    child = PottsSystem(
        name = :reader,
        statements = StatementSet(
            (
                ModelState(response; initial = SVector(0.0u"m", 0.0u"m")),
                Synchronous(:read, Assign(response, SVector(remote[2] * incoming[1], remote[1] * incoming[2]))),
            )
        ),
        unknowns = (response,), inputs = (incoming, remote),
        imports = (
            incoming => ComponentReference((), coefficients),
            remote => ComponentReference((), shared),
        ),
    )
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :enclosing,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(shared), ModelState(unused; initial = SVector(0.0, 0.0)),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (coefficients, unrelated_parameter), unknowns = (shared, unused),
        initial_conditions = Dict(shared => shared_initial), systems = (child,),
    )
    completed = complete(source; reference_units = ReferenceUnits(length = 2.0u"m"))
    initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
    return (; completed, initial, coefficients)
end

@testset "stored field imports exclude producer coefficients and retain history sources" begin
    for read_history in (false, true), producer_default in (0.05, 0.1)
        @parameters producer_diffusion = producer_default
        @variables concentration memory incoming response
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        field = FieldState(
            concentration; initial = 1.0, evolution = DiscreteFieldEuler(),
            diffusion = producer_diffusion, secretion = 0.0, decay = 0.0,
            substeps = 1, duration_per_mcs = 1.0, source_kind = cell,
            stencil = :field_stencil,
        )
        child_source = PottsSystem(
            name = :reader,
            statements = StatementSet(
                (
                    SiteState(response; initial = 0.0),
                    Synchronous(:read, Assign(response, read_history ? lag(incoming, 0) : incoming)),
                )
            ),
            unknowns = (response,), inputs = (incoming,),
            imports = (incoming => ComponentReference((), read_history ? memory : concentration),),
        )
        source = PottsSystem(
            name = :field_owner,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed(), relations = (proposal = Moore(), field_stencil = VonNeumann())),
                    cell, medium, field, HistoryState(memory; of = concentration, depth = 2),
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (concentration, memory), parameters = (producer_diffusion,),
            systems = (child_source,),
        )
        completed = complete(source)
        child = only(ModelingToolkitBase.get_systems(completed))
        @test isempty(parameters(child))
        @test count(record -> record.kind === :SiteState, inspect(child, Statements())) == 1
        @test all(record -> record.kind ∉ (:FieldState, :HistoryState), inspect(child, Statements()))
        initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
        @test PottsProblem(completed, initial, (0, 1); seed = 23) isa PottsProblem
        # The completed child has no lattice. Ownership must be diagnosed before
        # structural scheduling can fail for that missing spatial context.
        error = try
            PottsProblem(child, initial, (0, 1); seed = 23)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        if error isa ArgumentError
            message = sprint(showerror, error)
            @test occursin("field_owner₊concentration", message)
            @test !occursin("producer_diffusion", message)
            @test occursin("materialize the enclosing system", message)
            @test occursin("field_owner₊memory", message) == read_history
        end
    end
end

@testset "component analysis borrows dependencies without cloning their owners" begin
    fixture = _component_dependency_fixture()
    child = only(ModelingToolkitBase.get_systems(fixture.completed))
    @test length(parameters(fixture.completed)) == 2
    @test isempty(parameters(child))
    @test count(record -> record.kind === :ModelState, inspect(fixture.completed, Statements())) == 3
    @test count(record -> record.kind === :ModelState, inspect(child, Statements())) == 1
    @test all(record -> record.identity.path == (:enclosing, :reader), inspect(child, Statements()))
    @test isempty(initial_conditions(child))
    @test length(initial_conditions(fixture.completed)) == 1
    unrelated = _component_dependency_fixture(; unrelated_default = 29.0)
    unrelated_child = only(ModelingToolkitBase.get_systems(unrelated.completed))
    @test isequal(unknowns(unrelated_child), unknowns(child))
    @test parameters(unrelated_child) == parameters(child)
    @test [record.identity for record in inspect(unrelated_child, Statements())] ==
        [record.identity for record in inspect(child, Statements())]
    @test Potts._completion_data(unrelated_child).source_graph.structural_key ==
        Potts._completion_data(child).source_graph.structural_key
    changed = _component_dependency_fixture(; shared_initial = SVector(4.0u"m", 6.0u"m"))
    changed_child = only(ModelingToolkitBase.get_systems(changed.completed))
    @test Potts._completion_data(changed_child).source_graph.structural_key !=
        Potts._completion_data(child).source_graph.structural_key
    problem = PottsProblem(fixture.completed, fixture.initial, (0, 1); seed = 23)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        before = integrator.u
        error = try
            child_problem = PottsProblem(child, fixture.initial, (0, 1); seed = 23)
            init(child_problem, algorithm; scalar_type = Float32)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        if error isa ArgumentError
            @test occursin("enclosing₊shared", sprint(showerror, error))
            @test occursin("enclosing₊coefficients", sprint(showerror, error))
            @test occursin("materialize the enclosing system", sprint(showerror, error))
        end
        @test integrator.u === before
        step!(integrator)
        @test integrator.u[:reader₊response] == SVector(4.0f0, 3.0f0)
        @test integrator.u[:shared] == SVector(1.0f0, 2.0f0)
        @test integrator.u.ownership == ones(Int32, 2, 2)
    end
end
