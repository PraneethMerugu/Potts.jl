# Definitions of callbacks_tests.jl that other test files use.
using DiffEqCallbacks: PresetTimeCallback, PeriodicCallback

function cbsys(T = 1.0)
    return bsys(
        [D(bce) ~ bD * laplacian(bce) - bk * bce + x],
        [bc(0, x, y) ~ x * y], [bD, bk]; T, dvs = [bce]
    )
end
cbprob(T = 1.0) = discretize(cbsys(T), LatticeDiscretization(Grid((8, 8)); T = Float64))
