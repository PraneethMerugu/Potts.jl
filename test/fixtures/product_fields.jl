using StaticArrays
using Symbolics

function _product_field_system()
    @variables memory::NamedTuple{(:amount, :polarity, :nested), Tuple{Float64, SVector{2, Float64}, NamedTuple{(:enabled,), Tuple{Bool}}}}
    @variables amount polarity[1:2]
    initial = (amount = 3.0, polarity = SVector(4.0, 5.0), nested = (enabled = true,))
    state = ModelState(memory; initial)
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    system = PottsSystem(
        name = :product_fields,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium, state,
                ModelState(amount; initial = 0.0),
                ModelState(polarity; initial = SVector(0.0, 0.0)),
                ProposalConstraint(:held_ownership, false),
                Synchronous(
                    :project,
                    Assign(amount, ifelse(state.nested.enabled, state.amount + 1, state.amount - 1)),
                    Assign(polarity, SVector(-state.polarity[2], state.polarity[1])),
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (memory, amount, polarity),
    )
    initial_state = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    return system, initial_state
end

function _test_product_field_values(integrator)
    @test integrator.u[:amount] === 4.0f0
    @test integrator.u[:polarity] === SVector(-5.0f0, 4.0f0)
    @test integrator.u[:memory] === (amount = 3.0f0, polarity = SVector(4.0f0, 5.0f0), nested = (enabled = true,))
    return nothing
end

function _product_field_execution_contract(algorithm, backend)
    system, initial = _product_field_system()
    problem = PottsProblem(system, initial, (0, 2); seed = 17)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    for _ in 1:2
        step!(integrator)
        _test_product_field_values(integrator)
    end
    @test integrator.t == 2
    return nothing
end
