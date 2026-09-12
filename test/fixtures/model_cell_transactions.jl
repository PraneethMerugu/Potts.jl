using StaticArrays
using Symbolics

function _model_cell_transaction_contract(algorithm, backend)
    @variables increment direction[1:2]
    selected = CellKind(:selected; extinction = RetireAtZero())
    other = CellKind(:other; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :coupled_model_cells,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 4),
                selected, other, medium,
                ModelState(increment; initial = 2.0),
                CellState(direction; initial = SVector(8.0, 7.0), retirement = RetireTo(SVector(0.0, 0.0))),
                ProposalConstraint(:fixed_ownership, false),
                Synchronous(:model_update, Assign(increment, increment + 1)),
                Synchronous(
                    :cell_update, Assign(direction, SVector(direction[1] + increment, -direction[2]));
                    domain = cells(selected), expression = increment <= 4,
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (increment, direction),
    )
    # Selected cells have unequal areas (one and three sites), but each updates
    # once. The other kind and the unoccupied capacity slot must remain unchanged.
    labels = [1 0 0; 2 2 0; 2 0 0; 3 0 0]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [selected, selected, other], medium),
        values = (direction => [SVector(1.0, 2.0), SVector(3.0, 4.0), SVector(5.0, 6.0)],),
    )
    problem = PottsProblem(source, initial, (0, 3); seed = 17)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    step!(integrator)
    first_values = [SVector(3.0f0, -2.0f0), SVector(5.0f0, -4.0f0), SVector(5.0f0, 6.0f0), SVector(8.0f0, 7.0f0)]
    @test Array(integrator.u[:direction]) == first_values
    @test integrator.u[:increment] === 3.0f0
    @test integrator.t == 1
    @test Array(integrator.u.ownership) == labels
    restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
    @test Array(restored.u[:direction]) == first_values
    @test restored.u[:increment] === 3.0f0
    @test restored.t == 1
    @test Array(restored.u.ownership) == labels
    for boundary in 2:3
        step!(integrator)
        step!(restored)
        # Both RHS and condition consume entry increments 2,3,4, not 3,4,5.
        shift = Float32(sum(2:(boundary + 1)))
        sign = isodd(boundary) ? -1.0f0 : 1.0f0
        expected = [SVector(1.0f0 + shift, sign * 2.0f0), SVector(3.0f0 + shift, sign * 4.0f0), SVector(5.0f0, 6.0f0), SVector(8.0f0, 7.0f0)]
        @test Array(restored.u[:direction]) == Array(integrator.u[:direction]) == expected
        @test restored.u[:increment] == integrator.u[:increment] == Float32(boundary + 2)
        @test restored.t == integrator.t == boundary
    end
    @test failure_report(integrator) === nothing
    @test failure_report(restored) === nothing
    @test Array(restored.u.ownership) == Array(integrator.u.ownership) == labels
    return nothing
end
