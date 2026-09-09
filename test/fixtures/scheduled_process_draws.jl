using StaticArrays
using Symbolics

function _scheduled_draw_problem(; reordered = false, unrelated = false)
    @variables model_noise cell_noise[1:2] site_noise extra_noise
    selected = CellKind(:selected; extinction = RetireAtZero())
    other = CellKind(:other; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    processes = (
        Synchronous(:model_sample, Assign(model_noise, draw(Uniform(2.0, 3.0), DrawKey(:model_sample)))),
        Synchronous(
            :cell_sample,
            Assign(cell_noise, SVector(draw(Uniform(), DrawKey(:cell_uniform)), draw(Normal(0.0, 1.0), DrawKey(:cell_normal))));
            domain = cells(selected), expression = draw(Bernoulli(1.0), DrawKey(:cell_enabled)),
        ),
        Synchronous(:site_sample, Assign(site_noise, draw(Uniform(), DrawKey(:site_sample)))),
    )
    extras = unrelated ? (
            ModelState(extra_noise; initial = 0.0),
            Synchronous(:unrelated_sample, Assign(extra_noise, draw(Uniform(), DrawKey(:unrelated_sample)))),
        ) : ()
    source = PottsSystem(
        name = :scheduled_random_model,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 4),
                selected, other, medium,
                ModelState(model_noise; initial = -1.0),
                CellState(cell_noise; initial = SVector(-1.0, -1.0), retirement = RetireTo(SVector(0.0, 0.0))),
                SiteState(site_noise; initial = -1.0),
                ProposalConstraint(:fixed_ownership, false),
                extras...,
                (reordered ? reverse(processes) : processes)...,
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = unrelated ? (model_noise, cell_noise, site_noise, extra_noise) : (model_noise, cell_noise, site_noise),
    )
    labels = [1 0 0; 2 2 0; 2 0 0; 3 0 0]
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [selected, selected, other], medium))
    return PottsProblem(source, initial, (0, 3); seed = 0x00172390)
end

_scheduled_draw_values(integrator) = (
    model = integrator.u[:model_noise],
    cells = Array(integrator.u[:cell_noise]),
    sites = Array(integrator.u[:site_noise]),
)

function _scheduled_draw_contract(algorithm, backend; reordered = false, unrelated = false)
    problem = _scheduled_draw_problem(; reordered, unrelated)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    ownership = Array(integrator.u.ownership)
    outputs = []
    restored = nothing
    for boundary in 1:3
        step!(integrator)
        values = _scheduled_draw_values(integrator)
        push!(outputs, values)
        @test integrator.t == boundary
        @test failure_report(integrator) === nothing
        @test Array(integrator.u.ownership) == ownership
        @test 2.0f0 <= values.model <= 3.0f0
        @test all(value -> 0.0f0 < value < 1.0f0, values.sites)
        @test all(value -> 0.0f0 < value[1] < 1.0f0 && isfinite(value[2]), values.cells[1:2])
        @test values.cells[3:4] == fill(SVector(-1.0f0, -1.0f0), 2)
        if restored === nothing
            restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
        else
            step!(restored)
        end
        @test restored.t == boundary
        @test _scheduled_draw_values(restored) == values
        @test Array(restored.u.ownership) == ownership
    end
    @test outputs[1].model != outputs[2].model
    @test outputs[1].cells[1] != outputs[1].cells[2]
    return outputs
end
