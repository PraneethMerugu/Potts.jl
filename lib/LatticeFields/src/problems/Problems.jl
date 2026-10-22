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
using Serialization: Serialization
using KernelAbstractions: KernelAbstractions as KA
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, RuntimeGeneratedFunction,
                                 drop_expr
using SciMLBase: SciMLBase
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using ..Exec: Exec
using ..IR: Coef, Ex, FaceRule, NodeValueRule, Program, fieldid, print_program, isfloat, juliatype, leveldims, ncomp, nsites,
            runtime!
using ..Compile: CompiledKernel, CompileOptions, body_function, derive_function, lanecast, lanetype,
                 primal, promote_dual, semantic, valtype, withvaltype, writes, fuse_update
using ..Schedule: LaunchSpec, StepPlan, plan

RuntimeGeneratedFunctions.init(@__MODULE__)
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))

public Geom, RT_T, RT_DT, launch_geometry, launch_parameters, bind, rebind, retime, each,
       FieldStore,
       array, current, settable!, launch_arrays, state_layout, BoundStep, compile!, swap!,
       run_step!, FaceCheck, face_checks, degenerate_face, check_faces, degenerate, face_ratio, FACE_RTOL, FieldSlot,
       LatticeIndex, FieldAlgorithm, ExplicitEuler, ExplicitMap, nbuffers, FieldProblem,
       FieldGroups, update_key, update_rule, EulerRule, alg_family, alg_cache, reset_cache!, step_retcode!, GroupSpec, FieldGroup,
       group_program, group_plans, restrict_bound, GroupRuntime, bind_group, advance!, reset!, rebind!, clamp_now!,
       FieldSolution,
       FieldIntegrator, substeps, StateView, RHSLaunch, LatticeRHS, ode_problem,
       input_key, input_name, table_key, table_entry, parameter_name, resolve_inputs, check_inputs_set, upload_inputs!, check_parameters,
       seen_bound, unbounded_reason, unbounded_key, bound_inputs, check_values, ParamsTables, with_tables,
       typewith, check_setp, LatticeODEFunction, check_bounds

include("bind.jl")
include("store.jl")
include("steps.jl")
include("faces.jl")
include("index.jl")
include("inputs.jl")
include("algorithms.jl")
include("group.jl")
include("problem.jl")
include("ode.jl")

# the coupling between field groups and the per-group counts (review of F2-06)
public substep_counts, lagged_coupling, group_loops
# the clock (F2-08c)
public CLOCK_KEY, clock_slot

end # module Problems
