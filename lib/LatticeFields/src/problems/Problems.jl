"""
    LatticeFields.Problems

Running compiled programs (v3 §8): the arrays of a program on a backend (`FieldStore`), the
binding of a step plan's launch descriptions to `Exec` launches (`bind`, `BoundStep`), the
owned `FieldProblem` with its steppers (`ExplicitEuler`, `ExplicitMap`, the implicit ones), the SciML
`ODEProblem` of a program's ODE form (`ode_problem`, `LatticeRHS`), and symbolic indexing of
problems, solutions and integrators (`LatticeIndex`, `FieldSlot`).
"""
module Problems

using CommonSolve: CommonSolve
using Serialization: Serialization
using Krylov: Krylov
using LinearAlgebra: LinearAlgebra
using KernelAbstractions: KernelAbstractions as KA
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, RuntimeGeneratedFunction,
                                 drop_expr
using SciMLBase: SciMLBase
using SciMLOperators: SciMLOperators
using SciMLStructures: SciMLStructures as SS
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using ..Exec: Exec
using ..IR: Coef, DomainEdgeRule, HEX, Ex, FaceRule, NodeValueRule, Program, RUNTIME, PARAM, LOAD, fieldid, print_program, isfloat, juliatype, leveldims, ncomp, nsites,
            runtime!, degenerate, FACE_RTOL, F64, F16
using ..Compile: CompiledKernel, CompileOptions, body_function, derive_function, lanecast, lanetype,
                 primal, promote_dual, semantic, valtype, withvaltype, writes, fuse_update, fuse_residual,
                 npartials, dvalue, dpartial, dsetpartial, dreplace
using ..Schedule: LaunchSpec, StepPlan, plan
using ..Solvers: Solvers

RuntimeGeneratedFunctions.init(@__MODULE__)
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))

public Geom, RT_T, RT_DT, launch_geometry, launch_parameters, bind, rebind, retime, each,
       FieldStore,
       array, current, settable!, launch_arrays, state_layout, BoundStep, compile!, swap!,
       run_step!, FaceCheck, face_checks, degenerate_face, check_faces, face_ratio, FieldSlot,
       LatticeIndex, FieldAlgorithm, LinearSolver, linear_solver_refusal, ExplicitEuler, ExplicitMap, nbuffers, FieldProblem,
       FieldGroups, update_key, update_rule, EulerRule, alg_family, alg_cache, reset_cache!, step_retcode!, GroupSpec, FieldGroup,
       ParamSlot, TableSpec, InputSpec, canonical, check_status!, check_declared!, check_declared_state, check_backend_float64, status_word, status_route, StatusTotals, STATUS_CODE,
       STATUS_WINDOW, STATUS_CAUSE, STATUS_SOLVES, STATUS_BUDGET, STATUS_FLOOR, STATUS_NEWTON_BUDGET, STATUS_CAUSES, field_stats,
       group_program, group_plans, restrict_bound, GroupRuntime, bind_group, advance!, advance_shared!, reset!, clear_status!, window_text, rebind!, clamp_now!,
       FieldSolution,
       FieldIntegrator, substeps, StateView, RHSLaunch, LatticeRHS, ode_problem,
       input_key, aux_key, input_name, table_key, table_entry, parameter_name, resolve_inputs, check_inputs_set, upload_inputs!, check_parameters, check_declared, declared_intervals, used_intervals,
       seen_bound, unbounded_reason, unbounded_key, bound_inputs, check_values, ParamsTables, with_tables,
       typewith, check_setp, LatticeODEFunction, check_bounds, check_aux_write

include("bind.jl")
include("store.jl")
include("steps.jl")
include("faces.jl")
include("index.jl")
include("params.jl")
include("derivation.jl")
include("inputs.jl")
include("algorithms.jl")
include("group.jl")
include("operator.jl")
include("problem.jl")
include("implicit.jl")
include("coupled.jl")
include("tangent.jl")
include("ode.jl")

# the parameter object of B's SciML problems (F4-00)
public LatticeParameters, TableSlot, InputSlot, with_values, remake_params, remake_u0
# one problem, many algorithms (F4-01)
public ClockTick, MaskSync, mask_sync!, sync_masks!, UpdateLatticeAb, steady_start!, lattice_matrix, LatticeODEProblem, LatticeOperator, LatticeLinearProblem, LatticeTimeFreeProblem
public LatticeMetadata, LatticeFunction, LatticeProblem, LatticeDiscreteProblem, lattice_metadata, lattice_problem,
       field_problem, rhs_build
# the coupling between field groups and the per-group counts (review of F2-06)
public compute_type, substep_counts, lagged_coupling, group_loops, steady_loop_rates, steady_start, starts_steady, StartText, StartSubsteps
# the one substep policy of both front ends and its words (F3-01)
public PolicyTexts, ProblemTexts, GroupSubsteps, check_coupling, bound_report, unbounded_text, uncovered_text,
       refuse_parameters, coupling_unknown_text, coupling_unbounded_text, loop_text, steady_loop_text, steady_gain_text,
       steady_why_text, steady_gain_words, rows0_route
# the implicit algorithms (F3-07)
public ImplicitAlgorithm, BackwardEuler, CrankNicolson, BDF2, QuasiSteady, OperatorSpec, RowOperator, operator_spec, build_operator, growth, inexact_bounds, ImplicitCache,
       ImplicitRow, bind_cache, residual_program, residual_rule
# steady rows `0 ~ rhs` (F3-12b)
public steady_alg, steady_fields
# the clock (F2-08c)
public CLOCK_KEY, clock_slot
public rebind_launches, install_launches!   # the two parts of `rebind!` (an atomic update of several groups)
# computed parameters (F2-15, D-F2-1)
public Derivation, derive_at, derive_fail, derive!, rgf, computed_slot, rhs_tables

end # module Problems
