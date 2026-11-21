"""
    LatticeFields.Problems

Running compiled programs: the arrays of a program on a backend (`FieldStore`), the
binding of a step plan's launch descriptions to `Exec` launches (`bind_program`,
`BoundStep`), the owned `FieldProblem` with its steppers (`ExplicitEuler`, `ExplicitMap`,
the implicit ones), the SciML `ODEProblem` of a program's ODE form (`ode_problem`,
`LatticeRHS`), and symbolic indexing of problems, solutions and integrators (`LatticeIndex`,
`FieldSlot`).
"""
module Problems

using CommonSolve: CommonSolve
using LinearSolve: LinearSolve
using Serialization: Serialization
using Krylov: Krylov
using LinearAlgebra: LinearAlgebra
using SparseArrays: SparseArrays
using KernelAbstractions: KernelAbstractions as KA
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, RuntimeGeneratedFunction,
    drop_expr
using SciMLBase: SciMLBase
using SciMLOperators: SciMLOperators
using SciMLStructures: SciMLStructures as SS
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using ..LatticeFields: isfatal
using ..Exec: Exec
using ..IR: IR, CLAMP, INSIDE, Coef, DomainEdgeRule, HEX, Ex, FaceRule, sitecoefs,
    fieldperiodic,
    NodeValueRule, Program, RUNTIME, PARAM, LOAD, fieldid, print_program, isfloat,
    juliatype, leveldims, ncomp, nsites,
    runtime!, degenerate, FACE_RTOL, F64, F16, U8, I32, U32
using ..Compile: CompiledKernel, CompileOptions, body_function, derive_function, lanecast,
    lanetype,
    primal, promote_dual, semantic, value_type, withvaltype, writes,
    fuse_update, fuse_residual,
    npartials, dvalue, dpartial, dsetpartial, dreplace
using ..Schedule: LaunchSpec, StepPlan, plan, fusion_report
using ..Solvers: Solvers, LatticeMultigrid, LatticePCG, LatticeGMRES, LatticeBlockSolve

RuntimeGeneratedFunctions.init(@__MODULE__)
"""
    rgf(ex::Expr) -> function

Compile the function expression `ex` into a `RuntimeGeneratedFunction` of this module,
with its expression dropped (`drop_expr`), so it does not hold the expression.

# Arguments
- `ex::Expr`: a function expression.

# Returns
- The compiled function.
"""
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))

public Geom, RT_T, RT_DT, launch_geometry, launch_parameters, bind_program, rebind, retime,
    each, FieldStore, array, current, settable!, launch_arrays, state_layout, BoundStep,
    compile!, swap!, run_step!, FaceCheck, face_checks, degenerate_face, check_faces,
    face_ratio, FieldSlot, LatticeIndex, AbstractFieldAlgorithm, LinearSolver,
    linear_solver_refusal, ExplicitEuler, ExplicitMap, nbuffers, FieldProblem, FieldGroups,
    update_key, update_rule, alg_family, alg_cache, reset_cache!, step_retcode!, GroupSpec,
    FieldGroup, ParamSlot, TableSpec, InputSpec, canonical, check_status!, check_declared!,
    check_declared_state, check_backend_float64, status_word, status_route, STATUS_CODE,
    STATUS_WINDOW, STATUS_CAUSE, STATUS_SOLVES, STATUS_BUDGET, STATUS_FLOOR,
    STATUS_NEWTON_BUDGET, STATUS_CAUSES, field_stats, group_program, group_plans,
    restrict_bound, GroupRuntime, bind_group, advance!, advance_shared!, reset!,
    clear_status!, window_text, rebind!, FieldSolution, FieldIntegrator, substeps,
    LatticeRHS, ode_problem, input_key, aux_key, input_name, table_key, table_entry,
    parameter_name, resolve_inputs, check_parameters, check_declared, declared_intervals,
    used_intervals, seen_bound, unbounded_reason, unbounded_key, bound_inputs, ParamsTables,
    with_tables, typewith, check_setp, LatticeODEFunction, check_bounds, check_aux_write

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
include("callbacks.jl")
include("implicit.jl")
include("coupled.jl")
include("tangent.jl")
include("ode.jl")
include("series.jl")
include("sparsity.jl")
include("precond.jl")
include("report.jl")

# the parameter object of standalone SciML problems
public LatticeParameters, TableSlot, InputSlot, is_input_function, input_functions
# one problem, many algorithms
public ClockTick, MaskSync, InputRefresh, refresh_inputs!, mask_sync!, sync_masks!,
    UpdateLatticeAb, steady_start!, lattice_matrix, LatticeODEProblem, LatticeOperator,
    LatticeLinearProblem, LatticeTimeFreeProblem
public LatticeMetadata, LatticeFunction, LatticeProblem, LatticeDiscreteProblem,
    lattice_metadata, lattice_problem, field_problem, rhs_build
# the Jacobian of the ODE right side
public field_jacobian_sparsity, column_colors, LatticeJacobian, LatticeJVP,
    JacobianOperator, colored_jacobian!, lattice_jvp!
# the lattice multigrid as a LinearSolve preconditioner and algorithm
public LatticeMultigrid, MGPreconditioner, LatticePCG
# solutions
public FieldSeries, field_series, site_centers, LatticeStats, LatticeSolution, finish!
# the saved size above which a run that saves every step warns (field runs and Potts runs)
public LARGE_SAVE_BYTES
# the coupling between field groups and the per-group counts
public compute_type, substep_counts, lagged_coupling, group_loops, steady_loop_rates,
    steady_start, starts_steady, StartText, StartSubsteps
# the shared substep policy and its words
public AbstractPolicyTexts, ProblemTexts, GroupSubsteps, check_coupling, bound_report,
    unbounded_text, uncovered_text, refuse_parameters, coupling_unknown_text,
    coupling_unbounded_text, loop_text, steady_loop_text, steady_gain_text, steady_why_text,
    rows0_route, reads_time, bound_window!, bound_window, bound_params!, bound_params
# the field report
public field_report, group_report, coupling_report, substep_cause, implicit_facts,
    ImplicitFacts, unseen_reads, unseen_loop
# the implicit algorithms
public AbstractImplicitFieldAlgorithm, LatticeNewton, BackwardEuler, CrankNicolson, BDF2,
    QuasiSteady, OperatorSpec, RowOperator, operator_spec, build_operator, growth,
    inexact_bounds, ImplicitCache, bind_cache, residual_program, residual_rule, resolve_tols
# steady rows `0 ~ rhs`
public steady_alg, steady_fields
# the clock
public CLOCK_KEY, clock_slot
# the two parts of `rebind!` (an atomic update of several groups)
public rebind_launches, install_launches!
# computed parameters
public Derivation, derive_at, derive_fail, derive!, rgf, rhs_tables

end # module Problems
