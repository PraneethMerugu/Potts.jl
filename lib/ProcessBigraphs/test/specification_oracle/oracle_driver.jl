using TOML
using SHA

length(ARGS) == 2 || error("usage: oracle_driver.jl FIXTURE OUTPUT")
include(joinpath(@__DIR__, "Oracle.jl"))
SpecificationOracle.write_results(ARGS[1], ARGS[2])
