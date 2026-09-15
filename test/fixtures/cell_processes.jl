using DynamicQuantities
using ModelingToolkitBase: complete, mtkcompile
using StaticArrays
using Symbolics

function _cell_process_contract(algorithm, backend)
    @variables amount direction[1:2]
    selected = CellKind(:selected; extinction = RetireAtZero())
    other = CellKind(:other; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :cell_exchange,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 4), selected, other, medium,
                CellState(amount; initial = 9.0, retirement = RetireTo(0.0)),
                CellState(direction; initial = SVector(8.0, 7.0), retirement = RetireTo(SVector(0.0, 0.0))),
                ProposalConstraint(:fixed_ownership, false),
                Synchronous(
                    :exchange, Assign(amount, direction[1]),
                    Assign(direction, SVector(amount, 0.0)); domain = cells(selected)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (amount, direction),
    )
    labels = [1 0 0; 2 2 0; 2 0 0; 3 0 0]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [selected, selected, other], medium),
        values = (
            amount => [2.0, 3.0, 4.0],
            direction => [SVector(5.0, 1.0), SVector(6.0, 1.0), SVector(7.0, 1.0)],
        ),
    )
    problem = PottsProblem(source, initial, (0, 2); seed = 17)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    step!(integrator)
    @test Array(integrator.u[:amount]) == Float32[5, 6, 4, 9]
    @test Array(integrator.u[:direction]) == [
        SVector(2.0f0, 0.0f0), SVector(3.0f0, 0.0f0),
        SVector(7.0f0, 1.0f0), SVector(8.0f0, 7.0f0),
    ]
    step!(integrator)
    @test Array(integrator.u[:amount]) == Float32[2, 3, 4, 9]
    @test Array(integrator.u[:direction]) == [
        SVector(5.0f0, 0.0f0), SVector(6.0f0, 0.0f0),
        SVector(7.0f0, 1.0f0), SVector(8.0f0, 7.0f0),
    ]
    return @test failure_report(integrator) === nothing
end

function _structured_retirement_contract(algorithm, backend)
    @variables position[1:2]
    @variables status::NamedTuple{(:enabled, :count, :level), Tuple{Bool, Int32, Float64}}
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = CellBinding(:retiring)
    source = PottsSystem(
        name = :structured_retirement, statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                CellState(
                    position; initial = SVector(2.0u"m", 4.0u"m"),
                    retirement = RetireTo(SVector(600.0u"cm", 800.0u"cm"))
                ),
                CellState(
                    status; initial = (enabled = true, count = Int32(2), level = 1.0),
                    retirement = RetireTo((enabled = false, count = Int32(7), level = 2.5))
                ),
                ProposalConstraint(:fixed_ownership, false),
                LifecycleProcess(
                    :remove; domain = cells(cell), anchor, expression = true,
                    effects = (
                        RemoveCell(
                            anchor; replacement = medium,
                            on_inadmissible = ErrorOnInadmissible()
                        ),
                    ), cadence = AtMCS(1)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (position, status)
    )
    system = mtkcompile(complete(source; reference_units = ReferenceUnits(length = 2.0u"m")))
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    problem = PottsProblem(system, initial, (0, 1); seed = 17)
    result = solve(problem, algorithm; backend, scalar_type = Float32)
    @test result.retcode == SciMLBase.ReturnCode.Success
    @test only(Array(result.u[end][:position])) === SVector(3.0f0, 4.0f0)
    @test only(Array(result.u[end][:status])) === (enabled = false, count = Int32(7), level = 2.5f0)
    return @test all(owner -> owner <= 0, Array(result.u[end].ownership))
end
