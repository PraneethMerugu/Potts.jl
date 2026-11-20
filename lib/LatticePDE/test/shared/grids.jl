# Definitions of grids_tests.jl that other test files use.
using OrdinaryDiffEqTsit5: Tsit5

@parameters qD = 0.1 qk = 1.0
@variables qc(..)
qce = qc(t, x, y)
function qsys()
    return PDESystem(
        [D(qce) ~ qD * laplacian(qce) - qk * qce], [qc(0, x, y) ~ 1.0 + x * y],
        [t ∈ Interval(0.0, 0.3), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y],
        [qce], [
            qD, qk,
        ]; name = :q18
    )
end
