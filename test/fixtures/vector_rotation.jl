using StaticArrays
using Symbolics

function _vector_rotation_contract(algorithm, backend)
    @variables polarity[1:2]
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    for state_constructor in (ModelState, SiteState)
        @testset "$(nameof(state_constructor))" begin
            system = PottsSystem(
                name = :rotating_polarity,
                statements = StatementSet(
                    (
                        Lattice((2, 2); boundary = Closed()), cell, medium,
                        state_constructor(polarity; initial = SVector(1.0, 0.0)),
                        ProposalConstraint(:fixed_ownership, false),
                        Synchronous(:rotate, Assign(polarity, SVector(-polarity[2], polarity[1]))),
                        Protocol(Sweep(; temperature = 0.0); name = :main),
                    )
                ),
                unknowns = (polarity,),
            )
            initial = PottsInitialState(
                ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
            )
            problem = PottsProblem(system, initial, (0, 4); seed = 17)
            integrator = init(problem, algorithm; backend, scalar_type = Float32)
            # Independent quarter-turn values, not the compiled rotation law.
            expected_values = (
                SVector(0.0f0, 1.0f0), SVector(-1.0f0, 0.0f0),
                SVector(0.0f0, -1.0f0), SVector(1.0f0, 0.0f0),
            )
            for expected in expected_values
                step!(integrator)
                actual = integrator.u[:polarity]
                if state_constructor === ModelState
                    @test actual == expected
                else
                    @test Array(actual) == fill(expected, 2, 2)
                end
            end
        end
    end
    return nothing
end
