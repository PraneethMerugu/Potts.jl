using StaticArrays

function _product_state_source(variable, declaration)
    return PottsSystem(
        name = :product_state,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()), MediumKind(:medium),
                declaration, ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (variable,),
    )
end

@testset "named-product declarations retain one symbolic owner" begin
    @variables memory::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    initial = (amount = 2.0, enabled = true)
    for constructor in (ModelState, SiteState)
        declaration = constructor(memory; initial)
        source = PottsSystem(
            name = :product_state,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()),
                    CellKind(:cell; extinction = RetireAtZero()), MediumKind(:medium),
                    declaration, Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (memory,),
        )
        completed = complete(source)
        @test length(ModelingToolkitBase.unknowns(completed)) == 1
        owned = only(ModelingToolkitBase.unknowns(completed))
        @test Symbolics.symtype(Symbolics.unwrap(owned)) === typeof(initial)
    end
    @test_throws r"symbolic declarations" ModelState(1.0; name = :invalid)
end

@testset "named-product initial state retains field types and shapes" begin
    @variables memory::NamedTuple{(:amount, :enabled, :count, :direction), Tuple{Float64, Bool, Int32, SVector{2, Float64}}}
    initial = (amount = 2.0, enabled = true, count = Int32(3), direction = SVector(1.0, 0.0))
    supplied = (amount = 4.0, enabled = false, count = Int32(5), direction = SVector(0.0, 1.0))
    expected = (amount = 4.0f0, enabled = false, count = Int32(5), direction = SVector(0.0f0, 1.0f0))
    ownership = LabelledCells(ones(Int, 2, 2); cells = [CellKind(:cell; extinction = RetireAtZero())], medium = MediumKind(:medium))
    for constructor in (ModelState, SiteState)
        source = _product_state_source(memory, constructor(memory; initial))
        is_model = constructor === ModelState
        values = (memory => (is_model ? supplied : fill(supplied, 2, 2)),)
        problem = PottsProblem(source, PottsInitialState(; ownership, values), (0, 1); seed = 17)
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            integrator = init(problem, algorithm; scalar_type = Float32)
            actual = integrator.u[:memory]
            @test actual == (is_model ? expected : fill(expected, 2, 2))
            @test (is_model ? typeof(actual) : eltype(actual)) === typeof(expected)
            restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
            @test restored.u[:memory] == actual
            @test solve!(integrator).u[end][:memory] == actual
        end
    end
    source = _product_state_source(memory, ModelState(memory; initial))
    for invalid in (
            (enabled = true, amount = 2.0, count = Int32(3), direction = SVector(1.0, 0.0)),
            merge(initial, (direction = SVector(1.0, 0.0, 0.0),)),
            merge(initial, (amount = SVector(1.0, 2.0),)),
            merge(initial, (amount = Inf,)),
        )
        problem = PottsProblem(source, PottsInitialState(; ownership, values = (memory => invalid,)), (0, 1); seed = 17)
        @test_throws ArgumentError init(problem; scalar_type = Float32)
    end
    default_source = _product_state_source(memory, ModelState(memory))
    default = init(PottsProblem(default_source, PottsInitialState(; ownership), (0, 1); seed = 17); scalar_type = Float32)
    @test default.u[:memory] === (amount = 0.0f0, enabled = false, count = Int32(0), direction = SVector(0.0f0, 0.0f0))
end
