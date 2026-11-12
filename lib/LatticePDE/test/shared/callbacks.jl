# Definitions of callbacks_tests.jl that other test files use (moved here by TS1b).
using DiffEqCallbacks: PresetTimeCallback, PeriodicCallback

cbsys(T = 1.0) = bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y], [bD, bk]; T, dvs = [bce])
cbprob(T = 1.0) = discretize(cbsys(T), LatticeDiscretization(Grid((8, 8)); T = Float64))
