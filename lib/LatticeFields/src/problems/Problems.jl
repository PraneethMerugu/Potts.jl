"""
    LatticeFields.Problems

Running compiled programs (v3 §8): the arrays of a program on a backend (`FieldStore`), the
binding of a step plan's launch descriptions to `Exec` launches (`bind`, `BoundStep`), the
owned `FieldProblem` with its steppers (`ExplicitEuler`, `ExplicitMap`), the SciML
`ODEProblem` of a program's ODE form (`ode_problem`, `LatticeRHS`), and symbolic indexing of
problems, solutions and integrators (`LatticeIndex`, `FieldSlot`).
"""
module Problems

using CommonSolve: CommonSolve
using KernelAbstractions: KernelAbstractions as KA
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, RuntimeGeneratedFunction,
                                 drop_expr
using SciMLBase: SciMLBase
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using ..Exec: Exec
using ..IR: Coef, FaceRule, Program, fieldid, isfloat, juliatype, leveldims, ncomp, nsites
using ..Compile: CompiledKernel, CompileOptions, body_function, derive_function, lanecast, lanetype,
                 primal, promote_dual, semantic, valtype, withvaltype
using ..Schedule: LaunchSpec, StepPlan, plan

RuntimeGeneratedFunctions.init(@__MODULE__)
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))

public Geom, RT_T, RT_DT, launch_geometry, launch_parameters, bind, rebind, retime, each,
       FieldStore,
       array, current, settable!, launch_arrays, state_layout, BoundStep, compile!, swap!,
       run_step!, FaceCheck, face_checks, degenerate_face, check_faces, degenerate, face_ratio, FACE_RTOL, FieldSlot,
       LatticeIndex, FieldAlgorithm, ExplicitEuler, ExplicitMap, FieldProblem,
       FieldSolution,
       FieldIntegrator, substeps, StateView, RHSLaunch, LatticeRHS, ode_problem

include("bind.jl")
include("store.jl")
include("steps.jl")
include("faces.jl")
include("index.jl")
include("problem.jl")
include("ode.jl")

end # module Problems
