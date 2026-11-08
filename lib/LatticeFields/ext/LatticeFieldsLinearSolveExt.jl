# LatticePCG (F4-08; F4 design §3.7): a LinearSolve algorithm for a symmetric `W`, conjugate
# gradients on `−W` (positive definite for a diffusion–reaction system) preconditioned by the
# lattice multigrid's V-cycles (`LatticeMG`, positive definite on `−W` too), matrix-free.
module LatticeFieldsLinearSolveExt

using LatticeFields: Problems
using LinearSolve: LinearSolve
using SciMLBase: SciMLBase
using Krylov: Krylov
using LinearAlgebra: LinearAlgebra

struct LatticePCGAlgorithm{P} <: LinearSolve.AbstractKrylovSubspaceMethod
    precs::P
end
Problems.LatticePCG(; precs = Problems.LatticeMG()) = LatticePCGAlgorithm(precs)
Base.show(io::IO, a::LatticePCGAlgorithm) = print(io, "LatticePCG(; precs = ", a.precs, ")")

LinearSolve.needs_concrete_A(::LatticePCGAlgorithm) = false
LinearSolve.init_cacheval(::LatticePCGAlgorithm, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
    assumptions::LinearSolve.OperatorAssumptions) = nothing

# `−A` and `−P` (CG takes a positive definite operator and preconditioner)
struct NegatedOperator{A}
    a::A
end
Base.size(n::NegatedOperator) = size(n.a)
Base.size(n::NegatedOperator, i) = size(n.a, i)
Base.eltype(n::NegatedOperator) = eltype(n.a)
LinearAlgebra.mul!(y::AbstractVector, n::NegatedOperator, x::AbstractVector) = (LinearAlgebra.mul!(y, n.a, x); y .= .-y; y)
struct NegatedPreconditioner{P}
    p::P
end
LinearAlgebra.ldiv!(y::AbstractVector, n::NegatedPreconditioner, x::AbstractVector) =
    (LinearAlgebra.ldiv!(y, n.p, x); y .= .-y; y)

function SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticePCGAlgorithm; kwargs...)
    if cache.precsisfresh
        Pl, _ = alg.precs(cache.A, cache.p)
        cache.Pl = Pl
        cache.precsisfresh = false
    end
    M = cache.Pl isa LinearAlgebra.UniformScaling ? LinearAlgebra.I : NegatedPreconditioner(cache.Pl)
    x, stats = Krylov.cg(NegatedOperator(cache.A), .-cache.b; M, ldiv = true, atol = float(cache.abstol),
        rtol = float(cache.reltol), itmax = cache.maxiters)
    copyto!(cache.u, x)
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache;
        retcode = stats.solved ? SciMLBase.ReturnCode.Success : SciMLBase.ReturnCode.Failure, iters = stats.niter, stats)
end

end # module LatticeFieldsLinearSolveExt
