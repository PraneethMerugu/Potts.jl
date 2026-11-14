# Definitions of solvers/coefficients_tests.jl that other test files use (moved here by TS1b).
using LatticeFields.Solvers: set_coefficients!, tangent!, coef_values

"""
`op` with keyword fields replaced (the test's own rebuild of a `CellOperator`).
"""
function with(op; kw...)
    f(k) = get(kw, k, getfield(op, k))
    CellOperator(op.dims; periodic = op.periodic, face = f(:face), shift = f(:shift),
        mask = op.mask, value = f(:value), dirichlet = f(:dirichlet))
end

tight(inner_rtol) = DevicePCG(; budget = 64, rtol = inner_rtol)

function primal_solve(case, T = Float64; kw...)
    sv = case_solver(case, T; inner = tight(1e-12), kw...)
    steady!(sv)
    return sv, Solvers.solver_solution(sv)
end

"""
Central finite difference of the primal solution in coefficient `coef` (step `δ`).
"""
function fd(case, coef, δ)
    op, inputs = case
    function up(h)
        coef === :shift && return with(op; shift = op.shift + h)
        coef === :value && return with(op; value = op.value + h)
        if coef[1] === :face
            return with(op; face = ntuple(a -> a == coef[2] ? op.face[a] + h : op.face[a],
                length(op.face)))
        end
        return with(op; dirichlet = ((op.dirichlet[1][1], op.dirichlet[1][2] + h),
            op.dirichlet[2]))
    end
    (primal_solve((up(δ), inputs))[2] .- primal_solve((up(-δ), inputs))[2]) ./ (2δ)
end

relmax(a, b) = maximum(abs, a .- b) / maximum(abs, b)
