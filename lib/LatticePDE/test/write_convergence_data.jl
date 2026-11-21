# Write the committed data file of the convergence docs page,
# docs/src/fields/convergence.toml, from the cases of convergence_orders_tests.jl:
#
#   julia --project=lib/LatticePDE/test lib/LatticePDE/test/write_convergence_data.jl
#
# The convergence tests fail when the file and the computed cases differ, so rerun this
# after a change that moves an error or an order, and commit the file.
module WriteConvergenceData
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "convergence_helpers.jl"))
include(joinpath(@__DIR__, "shared", "convergence_cases.jl"))
const CASES = convergence_cases()
write_convergence_data(CONVERGENCE_DATA_FILE, CASES)
println("wrote $(length(CASES)) cases to $CONVERGENCE_DATA_FILE")
end
