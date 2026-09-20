using Test
using Potts
using Symbolics
import Metal
import SciMLBase

function _authored_randomness_problem(draw_identity = :published_noise)
    @variables sample
    cell = CellKind(:random_cell; extinction = RetireAtZero())
    medium = MediumKind(:random_medium)
    copy_context = ProposalContext(:copy)
    system = PottsSystem(
        name = :authored_randomness,
        statements = StatementSet(
            (
                Lattice((8, 8); boundary = Periodic()), cell, medium,
                SiteState(sample; initial = 0.0f0),
                ProposalDrive(:bias, draw(Uniform(-2.0f0, -1.0f0), DrawKey(:proposal_bias))),
                ProposalConstraint(:stochastic_guard, draw(Bernoulli(0.75f0), DrawKey(:guard))),
                AcceptedCopy(
                    :publish, Assign(sample, draw(Uniform(0.25f0, 0.75f0), DrawKey(draw_identity)));
                    when = copy_context.is_extension,
                ),
                Protocol(Sweep(; temperature = 1.0f0); name = :main),
            )
        ),
        unknowns = [sample],
    )
    labels = zeros(Int32, 8, 8)
    labels[3:6, 3:6] .= 1
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
    return PottsProblem(system, initial, (0, 2); seed = 0xa881)
end

@testset "authored proposal and accepted-copy randomness executes on Metal" begin
    Metal.functional() || error("authored RNG witness requires functional Metal")
    Metal.allowscalar(false)
    problem = _authored_randomness_problem()
    run(problem, backend) = solve(
        problem, CheckerboardSweepCPM(); backend, scalar_type = Float32,
        save_everystep = true,
    )
    cpu = run(problem, CPUBackend())
    device = run(problem, Potts.MetalBackend())
    @test cpu.retcode == device.retcode == SciMLBase.ReturnCode.Success
    @test device.stats.accepted > 0
    @test map(state -> Array(state.ownership), device.u) == getfield.(cpu.u, :ownership)
    @test map(state -> Array(state[:sample]), device.u) == map(state -> state[:sample], cpu.u)
    samples = Array(last(device)[:sample])
    @test any(!iszero, samples)
    @test all(value -> iszero(value) || 0.25f0 <= value <= 0.75f0, samples)

    renamed = run(_authored_randomness_problem(:renamed_noise), Potts.MetalBackend())
    @test renamed.retcode == SciMLBase.ReturnCode.Success
    @test Array(last(renamed).ownership) == Array(last(device).ownership)
    @test Array(last(renamed)[:sample]) != samples

    integrator = init(problem, CheckerboardSweepCPM(); backend = Potts.MetalBackend(), scalar_type = Float32)
    step!(integrator)
    resumed = init(
        problem, CheckerboardSweepCPM(); backend = Potts.MetalBackend(), scalar_type = Float32,
        checkpoint = checkpoint(integrator),
    )
    step!(integrator)
    step!(resumed)
    @test Array(integrator.u.ownership) == Array(resumed.u.ownership)
    @test Array(integrator.u[:sample]) == Array(resumed.u[:sample])
end
