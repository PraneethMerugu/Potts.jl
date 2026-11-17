# Definitions of solvers/hierarchy_tests.jl that other test files use (moved here by TS1b).
using LatticeFields.Solvers: depth, RULE_M
const SV = LatticeFields.Solvers

function built(op, inputs; rule = RULE_M)
    sv = case_solver((op, inputs), Float64; linsolve = Multigrid(), rule)
    rebuild!(sv)
    return sv
end
