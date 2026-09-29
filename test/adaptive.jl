# Adaptive host integration of cell and model ODEs (`ode_solver = Adaptive(alg)`, M4.1).
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P

function adaptive_model(solver)
    @potts_model AdaptiveODEs begin
        @kinds medium A B
        @parameters k = 0.3
        @variables begin
            y(cell) = 1.0
            s(cell) = 0.0
            a(model) = 1.0
        end
        @lattice Lattice((20, 20))
        @energy cells => (volume - 16.0)^2
        @equations begin
            D(y) ~ -k * y                                    # cell ODE
            D(s) ~ -1000 * (s - cos(time))                   # stiff cell ODE
            D(a) ~ -0.5 * a + count(true for c in cells(B))  # model ODE with a population input
        end
        @sweep Metropolis(; temperature = 1.0, ode_solver = solver)
    end
    return AdaptiveODEs(; name = :ad)
end

@testset "adaptive ODE integration (SciML solvers)" begin
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    t = 5.0
    sa(t) = (1000 * (1000 * cos(t) + sin(t)) - 1000^2 * exp(-1000t)) / (1000^2 + 1)   # s(0) = 0
    for solver in (Adaptive(Tsit5(); reltol = 1e-10, abstol = 1e-12), Adaptive(Rodas5P(); reltol = 1e-8, abstol = 1e-10))
        p = PottsProblem(adaptive_model(solver), op, (0, 5))
        for alg in (SequentialCPM(), CheckerboardCPM())
            u = solve(p, alg).u[end]
            @test u.cell.y[1:2] ≈ fill(exp(-0.3t), 2) rtol = 1e-6
            @test u.model.a[1] ≈ 2 + (1 - 2) * exp(-0.5t) rtol = 1e-6            # one B cell: a → 2
            @test u.cell.s[1:2] ≈ fill(sa(t), 2) rtol = 1e-4
        end
    end
    # the integrator is created once and reused (init-once), and remake keeps working
    p = PottsProblem(adaptive_model(Adaptive(Tsit5(); reltol = 1e-8)), op, (0, 3))
    q = remake(p; p = [:k => 0.0])
    @test solve(q, SequentialCPM()).u[end].cell.y[1] ≈ 1.0
end
