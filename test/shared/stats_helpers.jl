# Process-wide statistical acceptance and convergence-order helpers (`Main.PottsStats`).
# Defined once in `Main` (following `devices.jl`) so multiple ReTestItems `@testsetup`
# modules import the exact same bindings without export collisions on a `@testitem`.
if !isdefined(Main, :PottsStats)
    Core.eval(Main, :(module PottsStats end))
    Base.include(Main.PottsStats, joinpath(@__DIR__, "stats_body.jl"))
end
using Main.PottsStats: required_n, stat_accept, observed_orders, observed_order
