# The lattice solvers as LinearSolve.jl algorithms: `LatticePCG`, `LatticeGMRES` and the stationary
# `Multigrid` take a `LinearProblem` through `init`/`solve!`, with their preconditioners given by
# LinearSolve's `precs` contract (`LatticeMultigrid`, `LatticeBlockSolve`). On a lattice field's
# operator (`BoundOperator`) the cache is the field's `FieldSolver`, and the PCG iteration and its
# V-cycle stay fused into one program (dispatch on the cache). Any other operator (OrdinaryDiffEq's
# `W`, the operator `discretize` returns for a system with no time) takes the generic Krylov.jl path.

"""
    LatticeMultigrid(; cycle = VCycle(2, 2), cycles = 1)

The lattice multigrid as a LinearSolve `precs` function: `precs(A, p) -> (Pl, Pr)`.

  - Given a lattice field's operator (the owned steppers' rows, a [`BoundOperator`](@ref)), it
    returns the V-cycle that [`LatticePCG`](@ref) applies on the field solver's own hierarchy,
    fused into its iteration (`cycle` symmetric, `cycles = 1`).
  - Given the `W = J − M/γ` of an implicit SciML solver on a problem `discretize` returned (or the
    operator of a linear system with no time), it binds the owned implicit runtime of the problem
    at the solver's state and applies `cycles` V-cycles per field as `ldiv!`, as in

        solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMultigrid(), gmres_restart = 10)))

For `W` it extracts each field's Helmholtz part `J̃` (its diffusion, its linear local terms, its
faces and masks) with the shift `1/γ` (a steady row `0 ~ rhs`, `M = 0`, takes none), and applies
`cycles` V-cycles (`cycle` its smoothing steps) of the lattice multigrid per field from zero: a
fixed linear operator, so GMRES and CG keep their convergence theory. The other terms (advection,
cross terms, nonlinear local terms) are left to the Krylov method. A masked site (and a site
outside the domain) is inverted exactly. The operator is rebuilt at each new `W` (state, time,
`γ`); on a device it runs there, with no host wait.

Give GMRES a small memory, `gmres_restart = 10`. With this preconditioner GMRES takes a few
iterations per linear solve (3 to 4 for a diffusion–reaction system), and LinearSolve currently
allocates a new workspace of about `gmres_restart` state vectors at each new `W`
(`gmres_restart = 0`, the default, takes 20; SciML/LinearSolve.jl#1378 keeps the workspace). For
FBDF at 512², 10 instead of the default allocates 17% less, with the same steps and iterations.
When the terms left to the Krylov method are strong (advection, cross terms), increase it.
"""
struct LatticeMultigrid
    cycle::VCycle
    cycles::Int
    engines::Dict{Any, Any}
    lock::ReentrantLock
end
function LatticeMultigrid(; cycle = VCycle(2, 2), cycles = 1)
    _count(cycles) || throw(
        ArgumentError(
            string(
                "`LatticeMultigrid(; cycles = ", repr(cycles),
                ")`: `cycles` is the number of V-cycles per field, an integer ≥ 1"
            )
        )
    )
    return LatticeMultigrid(_cycle(cycle), Int(cycles), Dict{Any, Any}(), ReentrantLock())
end
Base.:(==)(a::LatticeMultigrid, b::LatticeMultigrid) = a.cycle == b.cycle && a.cycles == b.cycles
Base.hash(a::LatticeMultigrid, h::UInt) = hash((a.cycle.nu1, a.cycle.nu2, a.cycles), hash(:LatticeMultigrid, h))
function Base.show(io::IO, mg::LatticeMultigrid)
    kws = Pair{Symbol, Any}[]
    mg.cycle.nu1 == 2 && mg.cycle.nu2 == 2 || push!(kws, :cycle => (mg.cycle.nu1, mg.cycle.nu2))
    mg.cycles == 1 || push!(kws, :cycles => mg.cycles)
    return _show_kw(io, "LatticeMultigrid", kws)
end

"""
    BoundOperator(exec, op::CellOperator; T = Float32, solver_type = :auto, inputs = ())

A lattice field's operator `op` bound to an executor and to its coefficient arrays (the inputs
of [`FieldSolver`](@ref) other than the right-hand side `"in.f"`): the `A` of a
`LinearProblem(A, b)` that [`LatticePCG`](@ref) and [`Multigrid`](@ref) solve with a
`FieldSolver` as their cache, `b` its right-hand side `"in.f"`. It has a size and an element
type (`T`, the state type); the solvers apply it inside their own kernels (it has no `mul!`).
"""
struct BoundOperator{T, N, E, I} <: SciMLOperators.AbstractSciMLOperator{T}
    exec::E
    op::CellOperator{N}
    solver_type::Any
    inputs::I
end
BoundOperator(exec, op::CellOperator{N}, ::Type{T}, solver_type, inputs) where {T, N} =
    BoundOperator{T, N, typeof(exec), typeof(inputs)}(exec, op, solver_type, inputs)
BoundOperator(exec, op::CellOperator; T = Float32, solver_type = :auto, inputs = ()) =
    BoundOperator(exec, op, T, solver_type, Tuple(inputs))
Base.size(A::BoundOperator) = (n = prod(A.op.dims); (n, n))
Base.size(A::BoundOperator, i::Integer) = size(A)[i]

"""
    FusedVCycle(cycle, cycles)

What [`LatticeMultigrid`](@ref) returns as the left preconditioner of a [`BoundOperator`](@ref):
the V-cycle `cycle` on the hierarchy of the field solver that [`LatticePCG`](@ref) builds,
applied inside its fused iteration (it has no `ldiv!` of its own).
"""
struct FusedVCycle
    cycle::VCycle
    cycles::Int
end
(mg::LatticeMultigrid)(::BoundOperator, p) = (FusedVCycle(mg.cycle, mg.cycles), LinearAlgebra.I)

"""
    LatticePCG(; precs = LatticeMultigrid(), maxiters = nothing, reltol = nothing)

Preconditioned conjugate gradients, a LinearSolve algorithm for a symmetric operator: a lattice
field's operator (the owned implicit steppers' `linsolve`, a [`BoundOperator`](@ref)), the
`W = J − M/γ` of an implicit SciML solver on a diffusion–reaction system, or the operator of a
linear system with no time.

On a lattice field's operator the cache is the field's [`FieldSolver`](@ref): CG on device
scalars with `precs`'s V-cycle from zero (a fixed linear SPD operator) fused into each
iteration, with no host wait. It needs `precs = LatticeMultigrid(; cycle = (ν, ν))` (one cycle
per iteration). The stop test is `‖r‖∞ ≤ reltol·max(‖b‖∞, floor)` (no `abstol`); the true
residual is computed every iteration. On a device the solve returns `ReturnCode.Default` with
`iters = 0` (the status stays in the device's status word); a host executor returns `Success`,
`MaxIters` or `ConvergenceFailure` with the iteration count. The iteration starts from the
solver's last solution (zero at the first solve). The solve enqueues `maxiters` iterations (gated
on device): give a small `maxiters`.

On another operator it is CG on `−A` (positive definite for a diffusion–reaction system),
preconditioned by `precs` (`LatticeMultigrid()`: the lattice multigrid's V-cycles, matrix-free).

`maxiters` and `reltol` left out take the solve's `maxiters` and `reltol` (LinearSolve's
keywords); the owned steppers give 8 and 1e-6. A solve that stops at `maxiters` returns
`ReturnCode.MaxIters`, one that stops otherwise without converging `ReturnCode.ConvergenceFailure`.
`maxiters` is an integer ≥ 1 and `reltol` finite and > 0; any other value is an `ArgumentError`
naming the keyword.
"""
struct LatticePCG{P} <: LinearSolve.AbstractKrylovSubspaceMethod
    precs::P
    maxiters::Union{Nothing, Int}
    reltol::Union{Nothing, Float64}
    function LatticePCG(precs::P, maxiters, reltol) where {P}
        maxiters === nothing || _count(maxiters) || throw(
            ArgumentError(
                string(
                    "`LatticePCG(; maxiters = ", repr(maxiters),
                    ")`: `maxiters` is the most CG iterations per solve, an integer ≥ 1"
                )
            )
        )
        reltol === nothing || _positive(reltol) || throw(
            ArgumentError(
                string(
                    "`LatticePCG(; reltol = ", repr(reltol),
                    ")`: `reltol` is the relative residual a solve stops at, finite and > 0"
                )
            )
        )
        return new{P}(precs, maxiters === nothing ? nothing : Int(maxiters), reltol === nothing ? nothing : Float64(reltol))
    end
end
LatticePCG(; precs = LatticeMultigrid(), maxiters = nothing, reltol = nothing) = LatticePCG(precs, maxiters, reltol)
function Base.show(io::IO, d::LatticePCG)
    kws = Pair{Symbol, Any}[]
    d.precs isa LatticeMultigrid && d.precs == LatticeMultigrid() || push!(kws, :precs => d.precs)
    d.maxiters === nothing || push!(kws, :maxiters => d.maxiters)
    d.reltol === nothing || push!(kws, :reltol => d.reltol)
    return _show_kw(io, "LatticePCG", kws)
end

"""
    LatticeBlockSolve(linsolve = LatticePCG(; maxiters = 2))

The block-diagonal preconditioner of a [`LatticeGMRES`](@ref) coupled solve, a LinearSolve `precs`
function: each field's own operator solved from zero by `linsolve` (a `LatticePCG(…)` or a
`Multigrid(…)`) on the field's multigrid hierarchy.
"""
struct LatticeBlockSolve{L}
    linsolve::L
    function LatticeBlockSolve(linsolve::L) where {L}
        linsolve isa Union{LatticePCG, Multigrid} || throw(
            ArgumentError(
                string(
                    "`LatticeBlockSolve(", repr(linsolve), ")`: the block preconditioner solves each field with a ",
                    "`LatticePCG(…)` or a `Multigrid(…)` (for example `LatticeBlockSolve(LatticePCG(; maxiters = 4))`)"
                )
            )
        )
        return new{L}(linsolve)
    end
end
LatticeBlockSolve() = LatticeBlockSolve(LatticePCG(; maxiters = 2))
Base.:(==)(a::LatticeBlockSolve, b::LatticeBlockSolve) = a.linsolve == b.linsolve
Base.show(io::IO, b::LatticeBlockSolve) = b == LatticeBlockSolve() ? print(io, "LatticeBlockSolve()") :
    print(io, "LatticeBlockSolve(", b.linsolve, ")")
Base.:(==)(a::LatticePCG, b::LatticePCG) = a.precs == b.precs && a.maxiters == b.maxiters && a.reltol == b.reltol

"""
    LatticeGMRES(; gmres_restart = 20, maxiters = nothing, reltol = nothing, precs = LatticeBlockSolve())

Restarted flexible GMRES (Krylov.jl's `fgmres!`), a LinearSolve algorithm. It is the coupled
solve of a `QuasiSteady` group whose fields read one another (the time steppers refuse it, their
fields take `LatticePCG` or `Multigrid`): its operator is the whole Jacobian of the group's
residual (every term of every row, cross terms included: a directional difference of the residual
kernels), its preconditioner `precs`, by default [`LatticeBlockSolve`](@ref)`()` (block-diagonal:
each field's own operator solved by `LatticePCG(; maxiters = 2)` on the field's multigrid
hierarchy). `gmres_restart` is the Krylov basis size (an integer from 2 to 64), `maxiters` the
most iterations per solve (an integer ≥ 1; a restart computes the true residual), `reltol` the
stop `‖r‖₂ ≤ reltol ‖b‖₂` (finite and > 0). Left out, `maxiters` and `reltol` take the solve's
values; the owned steppers give 60 and 1e-6. The coupled solve's dot products are block partials
summed in a fixed order (no atomics, no BLAS), so a run is bitwise repeatable, and the CPU and a
GPU give the same bits. Krylov.jl keeps its small least-squares problem on the host, so on a GPU
each dot product waits for its value (about `j + 1` waits at iteration `j` of a cycle; the one
exception to the field solvers' rule of no GPU wait in a step, user ruling 2026-11-01). Any other
value is an `ArgumentError` naming the keyword.
"""
struct LatticeGMRES{P} <: LinearSolve.AbstractKrylovSubspaceMethod
    gmres_restart::Int
    maxiters::Union{Nothing, Int}
    reltol::Union{Nothing, Float64}
    precs::P
    function LatticeGMRES(gmres_restart, maxiters, reltol, precs::P) where {P}
        (gmres_restart isa Integer && !(gmres_restart isa Bool) && 2 <= gmres_restart <= 64) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; gmres_restart = ", repr(gmres_restart), ")`: `gmres_restart` is the Krylov basis size, an integer from 2 to 64"
                )
            )
        )
        maxiters === nothing || _count(maxiters) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; maxiters = ", repr(maxiters),
                    ")`: `maxiters` is the most GMRES iterations per solve, an integer ≥ 1"
                )
            )
        )
        reltol === nothing || _positive(reltol) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; reltol = ", repr(reltol),
                    ")`: `reltol` is the relative residual a solve stops at, finite and > 0"
                )
            )
        )
        return new{P}(
            Int(gmres_restart), maxiters === nothing ? nothing : Int(maxiters),
            reltol === nothing ? nothing : Float64(reltol), precs
        )
    end
end
LatticeGMRES(; gmres_restart = 20, maxiters = nothing, reltol = nothing, precs = LatticeBlockSolve()) =
    LatticeGMRES(gmres_restart, maxiters, reltol, precs)
function Base.show(io::IO, g::LatticeGMRES)
    kws = Pair{Symbol, Any}[]
    g.gmres_restart == 20 || push!(kws, :gmres_restart => g.gmres_restart)
    g.maxiters === nothing || push!(kws, :maxiters => g.maxiters)
    g.reltol === nothing || push!(kws, :reltol => g.reltol)
    g.precs isa LatticeBlockSolve && g.precs == LatticeBlockSolve() || push!(kws, :precs => g.precs)
    return _show_kw(io, "LatticeGMRES", kws)
end
Base.:(==)(a::LatticeGMRES, b::LatticeGMRES) =
    a.gmres_restart == b.gmres_restart && a.maxiters == b.maxiters && a.reltol == b.reltol && a.precs == b.precs

"""
The per-field solver of a `LatticeGMRES`'s block preconditioner (the default `LatticeBlockSolve()`:
two PCG iterations with one V(2, 2) cycle each).
"""
gmres_precond(g::LatticeGMRES) = g.precs isa LatticeBlockSolve ? g.precs.linsolve : LatticePCG(; maxiters = 2)

"""
    owned(alg)

`alg` with the owned steppers' values of an unset `maxiters` and `reltol` (`LatticePCG`: 8 and
1e-6; `LatticeGMRES`: 60 and 1e-6). Other algorithms are returned as given.
"""
owned(a::LatticePCG) = LatticePCG(a.precs, something(a.maxiters, 8), something(a.reltol, 1.0e-6))
owned(a::LatticeGMRES) = LatticeGMRES(a.gmres_restart, something(a.maxiters, 60), something(a.reltol, 1.0e-6), a.precs)
owned(a) = a

# ---- traits (in the module that owns the types, as LinearSolve requires) -----------------------
LinearSolve.needs_concrete_A(::LatticePCG) = false
LinearSolve.needs_concrete_A(::LatticeGMRES) = false
LinearSolve.needs_concrete_A(::Multigrid) = false
LinearSolve.default_alias_A(::Multigrid, ::Any, ::Any) = true
LinearSolve.default_alias_b(::Multigrid, ::Any, ::Any) = true
# (each reads `cache.reltol` at its solve, when its own `reltol` is unset)
LinearSolve.update_tolerances_internal!(cache, ::LatticePCG, abstol, reltol) = nothing
LinearSolve.update_tolerances_internal!(cache, ::LatticeGMRES, abstol, reltol) = nothing
LinearSolve.update_tolerances_internal!(cache, ::Multigrid, abstol, reltol) = nothing

"""
    field_cache(exec, op::CellOperator, linsolve; T = Float32, solver_type = :auto, inputs) -> LinearCache

The linear solve of one field of the owned implicit steppers: `init(LinearProblem(A, b), alg)`
with `A` the [`BoundOperator`](@ref) of `op` and its coefficient `inputs`, `b` the input `"in.f"`
of `inputs`, and `alg` `linsolve` (`:auto`: `LatticePCG()`) with the owned values of an unset
`maxiters` and `reltol` ([`owned`](@ref)). Its cache (`cacheval`) is the field's
[`FieldSolver`](@ref); the owner rebuilds its hierarchy (`rebuild!`), so the cache is not fresh.
"""
function field_cache(exec, op::CellOperator, linsolve; T = Float32, solver_type = :auto, inputs = ())
    resolve_inner(op, linsolve)                       # (the checks, each refusal naming the field)
    alg = owned(linsolve === :auto ? LatticePCG() : linsolve)
    i = findfirst(p -> first(p) == "in.f", inputs)
    i === nothing && irerror("a field's linear solve needs its right-hand side `in.f` among the inputs")
    b = last(inputs[i])
    A = BoundOperator(exec, op, T, solver_type, Tuple(inputs[j] for j in eachindex(inputs) if j != i))
    c = CommonSolve.init(SciMLBase.LinearProblem(A, b), alg)
    c.isfresh = false
    return c
end

# ---- the fused path: a lattice field's operator, the `FieldSolver` as the cache -----------------
function _field_solver(alg, A::BoundOperator, b, linsolve, bound)
    return FieldSolver(
        A.exec, A.op; linsolve, T = eltype(A), solver_type = A.solver_type,
        inputs = ("in.f" => b, A.inputs...), bound
    )
end
function LinearSolve.init_cacheval(
        alg::LatticePCG, A::BoundOperator, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    Pl isa FusedVCycle || _refuse(
        A.op, "a lattice field's `LatticePCG` applies the V-cycles of `precs = LatticeMultigrid(…)` inside its fused ",
        "iteration; its `precs` gave the preconditioner ", repr(Pl), ": leave `precs` out, or give ",
        "`precs = LatticeMultigrid(; cycle = (ν, ν))`"
    )
    pcg = LatticePCG(
        LatticeMultigrid(; cycle = Pl.cycle, cycles = Pl.cycles), something(alg.maxiters, maxiters),
        something(alg.reltol, Float64(reltol))
    )
    return _field_solver(alg, A, b, pcg, A)
end
function LinearSolve.init_cacheval(
        alg::Multigrid, A::BoundOperator, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    return _field_solver(alg, A, b, alg, A)
end
LinearSolve.init_cacheval(
    ::LatticePCG, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
    assumptions::LinearSolve.OperatorAssumptions
) = nothing
LinearSolve.init_cacheval(
    ::Multigrid, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
    assumptions::LinearSolve.OperatorAssumptions
) = throw(
    ArgumentError(
        string(
            "`Multigrid` solves a lattice field's operator (a `BoundOperator`); got a ", nameof(typeof(A)),
            ": use `LatticePCG()`, or a Krylov method with `precs = LatticeMultigrid()`"
        )
    )
)

SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticePCG; kwargs...) = _solve!(cache, alg, cache.cacheval)
SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::Multigrid; kwargs...) = _solve!(cache, alg, cache.cacheval)

# the fused solve: rebind a new right-hand side, the hierarchy after a new `A`, the tolerance;
# then `lift!` and the budgeted solve, as the owned steppers ran them
function _solve!(cache, alg, sv::FieldSolver)
    cache.precsisfresh && (cache.precsisfresh = false)   # (the V-cycle is the solver's own hierarchy)
    if cache.isfresh
        if cache.A !== sv.bound                          # a new operator: a new solver
            sv = LinearSolve.init_cacheval(
                alg, cache.A, cache.b, cache.u, cache.Pl, cache.Pr, cache.maxiters,
                cache.abstol, cache.reltol, nothing, LinearSolve.OperatorAssumptions(true)
            )
            cache.cacheval = sv
        end
        rebuild!(sv)
        cache.isfresh = false
    end
    _bind_rhs!(sv, cache.b)
    budget = _budget!(sv, alg, cache)
    lift!(sv)
    solve!(sv; maxiters = budget)
    b = sv.bufs[sv.xid]
    _set_u!(cache, length(b) == 1 ? b[1] : b[sv.slot[sv.xid]])
    retcode, iters = _retcode(sv)
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters)
end
# the budget of this solve; a PCG `reltol` that differs from the held plans' drops them
function _budget!(sv::FieldSolver, alg::LatticePCG, cache)
    a = sv.alg::FusedPCG
    r = something(alg.reltol, Float64(cache.reltol))
    if r != a.reltol
        sv.alg = FusedPCG(a.precond, a.maxiters, r)
        empty!(sv.plans)
    end
    return something(alg.maxiters, cache.maxiters)
end
_budget!(sv::FieldSolver, ::Multigrid, cache) = sv.alg.maxiters::Int
# a new right-hand side array is bound as `"in.f"` (the held plans read the old one)
function _bind_rhs!(sv::FieldSolver, b)
    bs = sv.bufs[sv.rhs]
    bs[1] === b && return nothing
    old = bs[1]
    (typeof(b) == typeof(old) && length(b) == length(old)) || _refuse(
        sv.op, "the right-hand side `b` is a ", typeof(b), " of ", length(b), " values; the solver's is a ",
        typeof(old), " of ", length(old)
    )
    bs[1] = b
    empty!(sv.plans)
    return nothing
end
# the solution into `cache.u`: the solver's own array (no copy) when its type is `u`'s
_set_u!(cache, x) = x isa typeof(cache.u) ? (cache.u === x || (cache.u = x); nothing) : (copyto!(cache.u, x); nothing)
# the return code and the iteration count: read on a host executor (free), else `Default` and 0
function _retcode(sv::FieldSolver)
    host_scalars(sv.exec, sv.scal) || return SciMLBase.ReturnCode.Default, 0
    code = _scal_int(sv.scal, DONE)
    iters = _scal_int(sv.scal, ITER)
    fixed = sv.alg isa Multigrid && sv.alg.cycles !== nothing
    rc = code == 1 || (code == 0 && fixed) ? SciMLBase.ReturnCode.Success :
        code == 0 ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return rc, iters
end
_scal_int(scal::Array, i) = @inbounds Int(scal[i])       # (i ≤ SCALARS = length(scal))

# ---- the generic path: CG on `−A` for any other operator (`W`, a system with no time) -----------
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

function _solve!(cache, alg::LatticePCG, ::Nothing)
    if cache.precsisfresh
        Pl, _ = alg.precs(cache.A, cache.p)
        cache.Pl = Pl
        cache.precsisfresh = false
    end
    itmax = something(alg.maxiters, cache.maxiters)
    rtol = alg.reltol === nothing ? float(cache.reltol) : alg.reltol
    M = cache.Pl isa LinearAlgebra.UniformScaling ? LinearAlgebra.I : NegatedPreconditioner(cache.Pl)
    x, stats = Krylov.cg(NegatedOperator(cache.A), .-cache.b; M, ldiv = true, atol = float(cache.abstol), rtol, itmax)
    copyto!(cache.u, x)
    # (not converged: `MaxIters` at the iteration limit, else `ConvergenceFailure`, as LinearSolve's
    # Krylov methods report it)
    retcode = stats.solved ? SciMLBase.ReturnCode.Success :
        stats.niter >= itmax ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters = stats.niter, stats)
end

# ---- LatticeGMRES: the FGMRES workspace as the cache ---------------------------------------------
function LinearSolve.init_cacheval(
        alg::LatticeGMRES, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    budget = something(alg.maxiters, maxiters)
    m = min(alg.gmres_restart, budget)
    ws = Krylov.FgmresWorkspace(Krylov.KrylovConstructor(b); memory = m)
    sizehint!(ws.stats.residuals, budget + cld(budget, m) + 2)
    return ws
end

# stop a solve whose residual is not finite (it cannot recover)
struct NonFiniteStop end
(::NonFiniteStop)(ws) = (r = ws.stats.residuals; !isempty(r) && !isfinite(@inbounds r[end]))
_krylov_precond(P) = P isa Union{LinearAlgebra.UniformScaling, SciMLOperators.IdentityOperator} ? LinearAlgebra.I : P

function SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticeGMRES; kwargs...)
    if cache.precsisfresh
        Pl, Pr = alg.precs(cache.A, cache.p)
        cache.Pl = Pl
        cache.Pr = Pr
        cache.precsisfresh = false
    end
    ws = cache.cacheval
    K = eltype(cache.b)
    rtol = something(alg.reltol, Float64(cache.reltol))
    budget = something(alg.maxiters, cache.maxiters)
    Krylov.fgmres!(
        ws, cache.A, cache.b; M = _krylov_precond(cache.Pl), N = _krylov_precond(cache.Pr), ldiv = true,
        restart = true, rtol = K(rtol), atol = K(rtol * FLOOR), itmax = budget, history = true, callback = NonFiniteStop()
    )
    _set_u!(cache, ws.x)
    st = ws.stats
    retcode = st.solved ? SciMLBase.ReturnCode.Success :
        st.niter >= budget ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters = st.niter)
end
