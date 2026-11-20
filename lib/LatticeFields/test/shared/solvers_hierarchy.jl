# Definitions of solvers/hierarchy_tests.jl that other test files use.
using LatticeFields.Solvers: depth, RULE_M
const SV = LatticeFields.Solvers

function built(op, inputs; rule = RULE_M)
    sv = case_solver((op, inputs), Float64; linsolve = LatticeMultigrid(), rule)
    rebuild!(sv)
    return sv
end
