@testset "model-wide energy coefficients determine extension acceptance" begin
    @variables coefficient
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = SiteBinding(:energy_site)
    proposal = ProposalContext(:copy)
    labels = zeros(Int32, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
    function energy_system(weight)
        PottsSystem(
            name = :model_energy,
            statements = StatementSet(
                (
                    Lattice((3, 3); boundary = Closed()), cell, medium,
                    ModelState(coefficient; initial = weight),
                    HamiltonianTerm(
                        :occupied_energy; domain = sites(:lattice), anchor,
                        expression = coefficient * occupancy(cell, anchor)
                    ),
                    ProposalConstraint(:extensions_only, proposal.is_extension),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (coefficient,),
        )
    end
    # H = coefficient * occupied-site count: every permitted extension
    # changes H by exactly coefficient, independent of the selected neighbor.
    @testset "$(typeof(algorithm))" for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        favorable = solve(
            PottsProblem(energy_system(-2.0), initial, (0, 5); seed = 17),
            algorithm; scalar_type = Float32
        )
        unfavorable = solve(
            PottsProblem(energy_system(2.0), initial, (0, 5); seed = 17),
            algorithm; scalar_type = Float32
        )
        @test favorable.retcode == SciMLBase.ReturnCode.Success
        @test unfavorable.retcode == SciMLBase.ReturnCode.Success
        @test favorable.stats.accepted > 0
        @test count(>(0), last(favorable).ownership) > 1
        @test unfavorable.stats.energy_rejections > 0
        @test unfavorable.stats.accepted == 0
        @test last(unfavorable).ownership == labels
        @test last(favorable)[:coefficient] == -2.0f0
        @test last(unfavorable)[:coefficient] == 2.0f0
    end
end
