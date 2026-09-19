using StaticArrays
isdefined(@__MODULE__, :CellPolarityDynamicsExample) ||
    include(joinpath(@__DIR__, "../../examples/cell_polarity_dynamics.jl"))

_polarity_values(integrator) = (
    polarity = Array(integrator.u[:polarity]),
    turn = Array(integrator.u[:turn]),
)

function _polarity_dynamics_contract(algorithm, backend; reordered = false, unrelated = false, scalar_type = Float32)
    problem = CellPolarityDynamicsExample.polarity_problem(; reordered, unrelated)
    integrator = init(problem, algorithm; backend, scalar_type)
    ownership = Array(integrator.u.ownership)
    initial = _polarity_values(integrator)
    @test count(==(1), ownership) == 1
    @test count(==(2), ownership) == 3
    outputs = []
    restored = nothing
    tolerance = scalar_type === Float32 ? 3.0e-6 : 3.0e-13
    for boundary in 1:4
        entry = _polarity_values(integrator)
        step!(integrator)
        values = _polarity_values(integrator)
        push!(outputs, values)
        @test integrator.t == boundary
        @test failure_report(integrator) === nothing
        @test Array(integrator.u.ownership) == ownership
        @test all(angle -> -0.25 <= angle <= 0.25, values.turn[1:2])
        for cell in 1:2
            # Independent complex-plane rotation of the captured entry state.
            prior = entry.polarity[cell]
            expected = complex(Float64(prior[1]), Float64(prior[2])) * cis(Float64(entry.turn[cell]))
            @test values.polarity[cell] ≈ SVector(real(expected), imag(expected)) rtol = tolerance atol = tolerance
            @test sum(abs2, values.polarity[cell]) ≈ 1.0 rtol = tolerance atol = tolerance
        end
        @test values.polarity[3:4] == initial.polarity[3:4]
        @test values.turn[3:4] == initial.turn[3:4]
        boundary == 1 && @test values.polarity == initial.polarity
        if restored === nothing
            restored = init(problem, algorithm; backend, scalar_type, checkpoint = checkpoint(integrator))
        else
            step!(restored)
        end
        @test restored.t == boundary
        @test _polarity_values(restored) == values
        @test Array(restored.u.ownership) == ownership
    end
    # These inequalities witness this fixed seeded trajectory, not collision freedom.
    @test outputs[2].polarity[1] != initial.polarity[1]
    @test outputs[2].polarity[1] != outputs[2].polarity[2]
    return outputs
end
