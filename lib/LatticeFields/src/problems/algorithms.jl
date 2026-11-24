# The field algorithms: `ExplicitEuler`, `ExplicitMap`, the group
# assignment `FieldGroups`, and the hooks an algorithm defines for the group layer
# (`group.jl`): its update (`update_key`), its family (`alg_family`), its buffer count
# (`nbuffers`) and its cache (`alg_cache`, `reset_cache!`, `step_retcode!`).

"""
    AbstractFieldAlgorithm <: SciMLBase.AbstractODEAlgorithm

The supertype of the field stepping algorithms.

They step the problem `LatticePDE.discretize` returns (an `ODEProblem` of rates, a
`DiscreteProblem` of maps) with the owned steppers, as `solve(prob, BackwardEuler(); dt)`.
The same problem takes an OrdinaryDiffEq solver, `solve(prob, Rodas5P())`.

See also [`AbstractImplicitFieldAlgorithm`](@ref), [`ExplicitEuler`](@ref),
[`ExplicitMap`](@ref), [`FieldGroups`](@ref).
"""
abstract type AbstractFieldAlgorithm <: SciMLBase.AbstractODEAlgorithm end

"""
    ExplicitEuler(; substeps = nothing, lower_bound = nothing, init = nothing,
        compute_type = :auto)

Forward Euler: each window `dt` (the `dt` keyword of `solve`) runs `n` substeps of `dt / n`.

The method is explicit and first order. It is stable only for substeps small against the
problem's stability bound `ρ`, so the automatic count follows `ρ`. One type for both
coupled and standalone routes (`Potts` and `LatticePDE` export this binding).

- On the problem `LatticePDE.discretize` returns, `solve(prob, ExplicitEuler(); dt)` sets
  the window, and `dt` is required unless the discretization declares a clock (nothing else
  sets the window: `saveat` does not); `lower_bound` clips as below, fused into the step by
  the update pass ([`update_rule`](@ref)).
- As a `PottsProblem` `field_solver`, the window is the MCS (`mcs_duration`). As an
  `ode_solver`, `substeps = nothing` is one step per MCS.

# Keywords
- `substeps = nothing`: `nothing` takes the automatic count `n = ⌈dt ρ(p) / 1.8⌉` from the
  problem's stability bound `ρ` at the current parameters. An unknown bound (a rate term it
  cannot see, a parameter without a value, or rows that read each other in a loop and are
  not diagonally dominant) is refused. A count `substeps = n ≥ 1` is a minimum: the count
  is the larger of `n` and the bound over the terms the bound sees; when no term is seen,
  `n` is used. `substeps = 0` is an `ArgumentError`.
- `lower_bound = nothing`: a finite number clips each substep's result at
  `max(v, lower_bound)`; `nothing` clips nothing.
- `init = nothing`: `:steady` starts at the group's steady state (see
  [`BackwardEuler`](@ref)); `nothing` starts from the initial state.
- `compute_type = :auto`: the number type the group's kernels compute in, `:auto` (the
  problem's value type), `Float32` or `Float64` (see [`BackwardEuler`](@ref)).

Any other keyword is an `ArgumentError` that names it.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: ExplicitEuler

julia> ExplicitEuler(; substeps = 4, lower_bound = 0).lower_bound
0.0
```

See also [`BackwardEuler`](@ref), [`FieldGroups`](@ref).
"""
struct ExplicitEuler <: AbstractFieldAlgorithm
    substeps::Union{Nothing, Int}
    lower_bound::Union{Nothing, Float64}
    init::Union{Nothing, Symbol}
    compute_type::Any
    function ExplicitEuler(substeps, lower_bound, init = nothing, compute_type = :auto)
        substeps isa Integer && substeps == 0 && throw(
            ArgumentError(
                "ExplicitEuler: `substeps = 0` is not a count; leave `substeps` out for \
                    the automatic count"
            )
        )
        substeps === nothing ||
            (substeps isa Integer && !(substeps isa Bool) && substeps >= 1) ||
            throw(ArgumentError("ExplicitEuler: substeps = $(repr(substeps)) must be an \
                integer ≥ 1 (or left out: automatic)"))
        lower_bound === nothing || lower_bound isa Real && isfinite(lower_bound) || throw(
            ArgumentError(
                "ExplicitEuler: lower_bound = $(repr(lower_bound)) must be a finite " *
                    "number (a clip at ±Inf or NaN clips nothing or every value; leave \
                        `lower_bound` out for no clip)"
            )
        )
        return new(
            substeps === nothing ? nothing : Int(substeps),
            lower_bound === nothing ? nothing : Float64(lower_bound),
            _init_keyword("ExplicitEuler", init),
            _compute_keyword("ExplicitEuler", compute_type)
        )
    end
end
# `init`: `nothing` (start from the initial state) or `:steady`
function _init_keyword(w, init)
    init === nothing || init === :steady || throw(
        ArgumentError(
            string(
                w, ": init = ", repr(init), " is not a start; ",
                "give `init = :steady` (solve the group's steady state before the first \
                    window) or leave `init` out (start from ",
                "the initial state)"
            )
        )
    )
    return init
end
# `compute_type`: `:auto` (the problem's value type), `Float32` or `Float64`
function _compute_keyword(w, c)
    c === :auto || c === Float32 || c === Float64 || throw(
        ArgumentError(
            string(
                w, ": `compute_type` takes `:auto` (the ",
                "problem's value type), `Float32` or `Float64` (the number type the \
                    group's kernels compute in; its fields keep ",
                "their storage, converted at each load and store); got ", repr(c)
            )
        )
    )
    return c
end
"""
    compute_type(alg, V) -> Type

The value type the kernels of a group stepped by `alg` compute in, for problem value type
`V`.

# Arguments
- `alg`: the field algorithm. One with no `compute_type` field counts as `:auto`.
- `V::Type`: the problem's value type.

# Returns
- `V` under `compute_type = :auto`, else the algorithm's `compute_type`.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: BackwardEuler

julia> LatticeFields.Problems.compute_type(BackwardEuler(; compute_type = Float64), Float32)
Float64
```
"""
function compute_type(a, ::Type{V}) where {V}
    c = hasfield(typeof(a), :compute_type) ? getfield(a, :compute_type) : :auto
    return c === :auto ? V : c
end
function ExplicitEuler(;
        substeps = nothing, lower_bound = nothing,
        init = nothing, compute_type = :auto, kw...
    )
    isempty(kw) ||
        throw(ArgumentError(string("ExplicitEuler: ", _explicit_euler_keywords(kw))))
    return ExplicitEuler(substeps, lower_bound, init, compute_type)
end
# the refusal of keywords `ExplicitEuler` does not take
function _explicit_euler_keywords(kw)
    if haskey(kw, :linsolve)
        return string(
            "`linsolve = ", repr(kw[:linsolve]),
            "`: `linsolve` is a keyword of the implicit field ",
            "solvers (the linear solver of each implicit step), and `ExplicitEuler` \
                solves no ",
            "linear system; give it to an implicit field solver, `BackwardEuler(; \
                linsolve = ",
            repr(kw[:linsolve]), ")`, or leave `linsolve` out"
        )
    else
        return string(
            "no keyword ", join(("`$k`" for k in keys(kw)), ", "),
            "; its keywords are `substeps`, `lower_bound`, `init` ",
            "and `compute_type`", _dt_text(kw)
        )
    end
end
# the note after a refused `solver_type`: why a non-bits float type is refused
function _solver_type_note(solver_type)
    solver_type isa Type || return ""
    solver_type <: AbstractFloat && isbitstype(solver_type) && return ""
    return " (kernels take isbits numbers only, so BigFloat is not supported; a Dual " *
        "state's derivative parts take tangent solves in its value type)"
end
# the route of a `dt` given to a field algorithm: the window is a keyword of `solve`
function _dt_text(kw)
    return if haskey(kw, :dt)
        " (the window `dt` is a keyword of `solve`: `solve(prob, alg; dt)`)"
    else
        ""
    end
end
"""
    nbuffers(alg) -> Int

The state buffers a step of algorithm `alg` needs per field (`c`, `c__next`).

# Arguments
- `alg`: the field algorithm.

# Returns
- The buffer count. Every algorithm here needs 2.
"""
nbuffers(::ExplicitEuler) = 2

"""
    AbstractImplicitFieldAlgorithm <: AbstractFieldAlgorithm

The supertype of the implicit field algorithms.

Each substep solves the Newton form `(I/(γh) − J̃) δ = G(u_k)` with a linear solver
(`linsolve`), `G` the group's rate program as a residual and `J̃` the symmetric operator its
front end extracts ([`OperatorSpec`](@ref)).

See also [`BackwardEuler`](@ref), [`CrankNicolson`](@ref), [`BDF2`](@ref),
[`QuasiSteady`](@ref).
"""
abstract type AbstractImplicitFieldAlgorithm <: AbstractFieldAlgorithm end
# (equal keywords: equal algorithms; a `linsolve` that holds a preconditioner's cache
# compares by value)
function Base.:(==)(a::A, b::A) where {A <: AbstractImplicitFieldAlgorithm}
    return all(f -> getfield(a, f) == getfield(b, f), fieldnames(A))
end
function Base.hash(a::AbstractImplicitFieldAlgorithm, h::UInt)
    return foldl(
        (h, f) -> hash(getfield(a, f), h), fieldnames(typeof(a));
        init = hash(typeof(a), h)
    )
end

"""
    LatticeNewton(; κ = 1 // 100, max_iter = 10, check_div = true)

Nonlinear solver specification for the owned implicit field algorithms
([`BackwardEuler`](@ref), [`CrankNicolson`](@ref), [`BDF2`](@ref), [`QuasiSteady`](@ref)).

It matches OrdinaryDiffEq's `NLNewton` convergence and divergence rules on fixed-step,
no-wait CPU and device execution.

# Keywords
- `κ = 1 // 100`: rate-scaled convergence threshold (a finite positive real).
- `max_iter = 10`: maximum Newton iterations per step (an integer ≥ 1). Unlike
  automatic mode (`nlsolve = nothing`), even `max_iter = 1` is checked (`ndz < 1e-5`). The
  solver runs at most `max_iter` iterations and stops early once the group meets the
  stopping test.
- `check_div = true`: when `true`, abort with `ReturnCode.ConvergenceFailure` if the
  contraction rate diverges (`θ > 2`), stalls above the tolerance floor (`θ ≈ 1` with
  `ndz > 1`), or exhausts `max_iter` without converging; when `false`, disable divergence
  growth checks and accept a `max_iter` budget hit as converged (`ReturnCode.Success`, still
  counted in `stats.newton_budget` once per group per substep, unlike automatic mode's
  per-row count, and warned; non-finite corrections still stop). Pass
  `LatticeNewton(; max_iter = 1, check_div = false)` for an unchecked single sweep.

At each iteration `iter`, the scaled update norm `ndz` is the single RMS norm over all
active (unmasked, in-domain) unknowns in the group of
`δ ./ (abstol .+ max.(abs.(uⁿ), abs.(u_k)) .* reltol)` in the working float type `T`, using
the pre-update iterate `u_k` and `abstol`/`reltol` from the `solve` keywords (SciML defaults
`1 // 10^6` and `1 // 10^3` if unset; refused when no group uses `LatticeNewton`, and
ignored by automatic groups in mixed problems). Note that `NLNewton`'s defaults
(`κ = 1 // 100`, `abstol = 1e-6`, `reltol = 1e-3`) are looser than automatic mode's `1e-3`
step-increment test when steps are small; tighten `κ` or `reltol` for tighter Newton
accuracy. On `iter == 1`, convergence requires `ndz < 1e-5`. For `iter > 1`,
`θ = prev_θ = max(0.3 * prev_θ, ndz / ndzprev)` (carried across steps and reset on `reinit!`
or parameter, table, or state writes) and `η = θ / (1 - θ)`; convergence holds when
`η >= 0 && η * ndz < κ` or at the floating-point precision limit
`|θ - 1| ≤ 100 * sqrt(eps(T))` when `ndz ≤ 1` (using type-faithful `eps(T)` rather than
`Float64` promotion, leaving `prev_θ` unchanged, and keeping the already-applied `ndz ≤ 1`
update).

Unsupported `NLNewton` keywords (`fast_convergence_cutoff`, `new_W_dt_cutoff`,
`always_new`, `relax`, `predictor`) throw `ArgumentError` explaining why they are not
honored.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: LatticeNewton

julia> LatticeNewton(; max_iter = 4).max_iter
4
```
"""
struct LatticeNewton{K}
    κ::K
    max_iter::Int
    check_div::Bool
    function LatticeNewton(κ, max_iter, check_div)
        κ isa Real && !(κ isa Bool) && isfinite(κ) && κ > 0 ||
            throw(ArgumentError("LatticeNewton: κ = $(repr(κ)) must be a finite positive \
                number"))
        max_iter isa Integer && !(max_iter isa Bool) && max_iter >= 1 ||
            throw(ArgumentError("LatticeNewton: max_iter = $(repr(max_iter)) is the most \
                Newton iterations per step, an integer ≥ 1 (leave `nlsolve = nothing` on \
                    the solver algorithm for the automatic count)"))
        check_div isa Bool ||
            throw(ArgumentError("LatticeNewton: check_div = $(repr(check_div)) must be a \
                Bool (`true` or `false`)"))
        return new{typeof(κ)}(κ, Int(max_iter), check_div)
    end
end
function LatticeNewton(; κ = 1 // 100, max_iter = 10, check_div = true, kw...)
    if !isempty(kw)
        reasons = String[]
        for k in keys(kw)
            if k in
                    (
                    :fast_convergence_cutoff, :new_W_dt_cutoff, :always_new, :relax,
                    :predictor,
                )
                push!(
                    reasons,
                    "`$k` drives OrdinaryDiffEq's adaptive host loop with host waits and \
                        step-size control, which no-wait fixed-step owned steppers do not \
                            use"
                )
            else
                push!(reasons, "unknown keyword `$k`")
            end
        end
        throw(
            ArgumentError(
                string(
                    "LatticeNewton: unsupported keyword", length(kw) == 1 ? "" : "s", " ",
                    join(("`$k`" for k in keys(kw)), ", "), ": ", join(reasons, "; "),
                    "; honored keywords are `κ`, `max_iter`, and `check_div`"
                )
            )
        )
    end
    return LatticeNewton(κ, max_iter, check_div)
end
function Base.:(==)(a::LatticeNewton, b::LatticeNewton)
    return a.κ == b.κ && a.max_iter == b.max_iter && a.check_div == b.check_div
end
function Base.hash(a::LatticeNewton, h::UInt)
    return hash((a.κ, a.max_iter, a.check_div), hash(:LatticeNewton, h))
end
function Base.show(io::IO, n::LatticeNewton)
    kw = String[]
    n.κ == 1 // 100 || push!(kw, string("κ = ", repr(n.κ)))
    n.max_iter == 10 || push!(kw, string("max_iter = ", repr(n.max_iter)))
    n.check_div || push!(kw, "check_div = false")
    return if isempty(kw)
        print(io, "LatticeNewton()")
    else
        print(io, "LatticeNewton(; ", join(kw, ", "), ")")
    end
end

"""
    BackwardEuler(; substeps = nothing, nlsolve = nothing, lower_bound = nothing,
                    linsolve = :auto, solver_type = :auto, init = nothing,
                        compute_type = :auto)

Backward Euler: each window `dt` runs `n` substeps of `h = dt / n`, each solving
`(u − uⁿ)/h = r(u)` at the substep's end time `tⁿ⁺¹` (the rate, the face values and the
inputs are read there) by Newton iterations on the form `(I/h − J̃) δ = G(u_k)`,
`G(u_k) = (uⁿ − u_k)/h + r(u_k)`, `J̃` the group's operator (diffusion faces, linear local
terms, face and mask conditions; a front end extracts it: `OperatorSpec`), each a linear
solve with `linsolve`, and `u_{k+1} = u_k + δ`.

The method is implicit, first order and L-stable (of the converged step). An operator that
reads the time is built at each substep's end time. One type for both coupled and standalone
routes (Potts and LatticePDE export this binding). On a hexagonal lattice the operator has
the lattice's six faces. The window `dt` is the `dt` keyword of `solve`, as for
[`ExplicitEuler`](@ref) (required on a `FieldProblem` without a clock; in a `PottsProblem`
the window is the MCS).

# Keywords
- `substeps = nothing`: `nothing` is automatic: 1, raised only where the operator needs it
  (a positive local derivative `g` the operator sees takes `n ≥ ⌈2 dt g⌉`, so the operator's
  shift stays ≥ half its `1/h` part; the terms out of the operator, with their bound `ρ_in`,
  take `n ≥ ⌈2 dt ρ_in⌉`, so their correction contracts by `≤ 1/2` per iteration); `n ≥ 1`
  is a minimum.
- `nlsolve = nothing`: [`LatticeNewton`](@ref) or `nothing`. `nothing` keeps the automatic
  count: 1 when the operator is exact (one solve is the Backward Euler step of a linear
  rate), 2 with a switch `max(c − c_T, 0)` (a flip pass: the second iteration takes the
  switch state at the first's result; it is no convergence test, so it counts no budget
  hit), more when a term stays out of the operator (a defect correction, `OperatorSpec`:
  advection, a cycle among the group's fields, a Robin face whose diagonal is negative, a
  second face coefficient of a scaled row), enough for the bound of those terms, 4 when no
  bound sees one. `LatticeNewton(; κ, max_iter, check_div)` runs at most `max_iter`
  iterations per substep, stops early once the group meets the `NLNewton` rate-scaled
  criterion (weighted by `abstol` and `reltol` from `solve`), and ends with
  `ReturnCode.ConvergenceFailure` at the window end on a budget hit when `check_div = true`
  (or accepts as `ReturnCode.Success` when `check_div = false`).
- `lower_bound = nothing`: the clip `max(v, lower_bound)` after each substep (a positivity
  route; Backward Euler keeps nonnegative data nonnegative on M-matrix rows, so it is rarely
  needed).
- `linsolve = :auto`: the linear solver: `:auto` (`LatticePCG()` with one V(2,2) cycle,
  `maxiters = 8`), `LatticePCG(…)`, `LatticeMultigrid(…)`, or any LinearSolve algorithm
  (such as `KLUFactorization()` on the host). `LatticeGMRES(…)` is `QuasiSteady`'s only (the
  coupled steady solve); a time stepper refuses it.
- `solver_type = :auto`: the solver's number type, `:auto` (the state's), `Float32` or
  `Float64`.
- `compute_type = :auto`: the number type the group's kernels (rate, residual, operator,
  update) compute in, `:auto` (the problem's value type), `Float32` or `Float64`. A wider
  type than the storage (`Float64` on a Float32 problem) loads each field value into it and
  rounds once at each store; on a device with Float64 (ROCm, CUDA) its kernels are
  registered as declared Float64, and a device without Float64 (Metal) refuses it when the
  group is bound (`init`, in both routes; so do `solver_type = Float64` and a field declared
  `lattice_storage = Float64`), naming the field and the routes.
- `init = nothing`: with `:steady`, before the first window (at `init`, and again at
  `reinit!`), solve the group's steady state `0 = r(u)` once with [`QuasiSteady`](@ref),
  from the initial state at the start time and with this algorithm's `linsolve` and
  `solver_type` (`:auto` takes `LatticePCG` to `reltol = 1e-6` within 64 iterations), then
  step from it. The steady state must exist and be unique, as for `QuasiSteady` (a growth or
  a field with no decay and no fixed value is refused); a steady solve that fails ends the
  run with `ReturnCode.ConvergenceFailure`. Every field algorithm takes it (`ExplicitEuler`
  too). `nothing` starts from the initial state.

Every value is checked here; a wrong one is an `ArgumentError` naming the keyword.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: BackwardEuler

julia> BackwardEuler(; substeps = 2).substeps
2
```

See also [`CrankNicolson`](@ref), [`BDF2`](@ref), [`QuasiSteady`](@ref),
[`LatticeNewton`](@ref).
"""
struct BackwardEuler <: AbstractImplicitFieldAlgorithm
    substeps::Union{Nothing, Int}
    nlsolve::Union{Nothing, LatticeNewton}
    lower_bound::Union{Nothing, Float64}
    linsolve::Any
    solver_type::Any
    init::Union{Nothing, Symbol}
    compute_type::Any
    function BackwardEuler(
            substeps, nlsolve, lower_bound, linsolve,
            solver_type, init = nothing, compute_type = :auto
        )
        return new(
            _implicit_keywords(
                "BackwardEuler", substeps, nlsolve, lower_bound, linsolve, solver_type
            )..., _init_keyword(
                "BackwardEuler", init
            ),
            _compute_keyword("BackwardEuler", compute_type)
        )
    end
end
# The keywords of a time-stepping implicit algorithm, each checked (an `ArgumentError`
# naming the keyword) and converted (`w` names the algorithm in the messages)
function _implicit_keywords(w, substeps, nlsolve, lower_bound, linsolve, solver_type)
    substeps isa Integer && !(substeps isa Bool) && substeps == 0 && throw(
        ArgumentError(
            "$w: `substeps = 0` is not a count; leave `substeps` out for the automatic \
                count"
        )
    )
    substeps === nothing ||
        (substeps isa Integer && !(substeps isa Bool) && substeps >= 1) ||
        throw(ArgumentError("$w: substeps = $(repr(substeps)) must be an integer ≥ 1 (or \
            left out: automatic)"))
    nlsolve === nothing || nlsolve isa LatticeNewton || throw(
        ArgumentError(
            string(
                "$w: nlsolve = $(repr(nlsolve)) must be `nothing` (automatic) or a \
                    `LatticeNewton(; κ, max_iter, check_div)`",
                if nlsolve isa Integer && !(nlsolve isa Bool)
                    "; give `nlsolve = LatticeNewton(; max_iter = $(Int(nlsolve)))`"
                else
                    ""
                end
            )
        )
    )
    lower_bound === nothing ||
        lower_bound isa Real && !(lower_bound isa Bool) && isfinite(lower_bound) || throw(
        ArgumentError(
            "$w: lower_bound = $(repr(lower_bound)) must be a finite number (a clip at " *
                "±Inf or NaN clips nothing or every value; leave `lower_bound` out for no \
                    clip)"
        )
    )
    # (`LatticeGMRES` is the coupled steady solve's: on a time stepper it was slower in
    # every case measured, user ruling 2026-11-03)
    linsolve isa Solvers.LatticeGMRES && w != "QuasiSteady" && throw(
        ArgumentError(
            string(
                w, ": `linsolve = ", repr(linsolve),
                "` is the solver of a coupled steady group (`QuasiSteady`, whose fields \
                    read one another); a time stepper ",
                "solves each field with `LatticePCG(…)` (the default) or \
                    `LatticeMultigrid(…)`: leave `linsolve` out, or give ",
                "`linsolve = LatticePCG(; maxiters = n)`"
            )
        )
    )
    linsolve === :auto || linsolve isa LinearSolve.SciMLLinearSolveAlgorithm || throw(
        ArgumentError(
            "$w: `linsolve` takes `:auto`, a `LatticePCG(…)`" *
                (
                if w == "QuasiSteady"
                    ", a `LatticeMultigrid(…)` or a `LatticeGMRES(…)`"
                else
                    " or a `LatticeMultigrid(…)`"
                end
            ) * " (the " *
                "linear solver of each implicit step); got $(repr(linsolve))"
        )
    )
    solver_type === :auto || solver_type === Float32 || solver_type === Float64 || throw(
        ArgumentError(
            string(
                w,
                ": `solver_type` takes `:auto` (the state's number type), `Float32` or \
                    `Float64`; got ", repr(solver_type),
                _solver_type_note(solver_type)
            )
        )
    )
    return (
        substeps === nothing ? nothing : Int(substeps),
        nlsolve, lower_bound === nothing ? nothing : Float64(lower_bound), linsolve,
        solver_type,
    )
end
function _implicit_kwerror(w, kw)
    return ArgumentError(
        string(
            w, ": no keyword ", join(("`$k`" for k in keys(kw)), ", "),
            "; its keywords are `substeps`, `nlsolve`, `lower_bound`, `linsolve`, \
                `solver_type`, `init` and `compute_type`",
            _dt_text(kw)
        )
    )
end
function BackwardEuler(;
        substeps = nothing, nlsolve = nothing, lower_bound = nothing, linsolve = :auto,
        solver_type = :auto, init = nothing, compute_type = :auto, kw...
    )
    isempty(kw) || throw(_implicit_kwerror("BackwardEuler", kw))
    return BackwardEuler(
        substeps, nlsolve, lower_bound, linsolve, solver_type, init, compute_type
    )
end
nbuffers(::BackwardEuler) = 2

"""
    CrankNicolson(; substeps = nothing, nlsolve = nothing, lower_bound = nothing,
                    linsolve = :auto, solver_type = :auto, init = nothing,
                        compute_type = :auto)

Crank–Nicolson (the trapezoidal rule, second order, A-stable but not L-stable).

Each substep of `h = dt / n` solves
`(u − uⁿ)/h = (r(uⁿ) + r(u))/2`, `r(uⁿ)` at the substep's start time `tⁿ` and `r(u)` at its
end time `tⁿ⁺¹`, by the Newton iterations of [`BackwardEuler`](@ref) with the shift `2/h`
(the operator of a Backward Euler step of `h/2`). It is not L-stable: data that jump (a
step, a mask that moves, an input that changes) ring with the factor `−1` per substep in the
stiff modes. So the first substep after a start (at `init`, and after every
[`reset!`](@ref): a state, input, table or parameter write) is damped (Rannacher): two
Backward Euler steps of `h/2`, at `tⁿ + h/2` and `tⁿ + h`, which use the same operator (no
extra rebuild). A group whose data can jump every window (it reads an input the CPM fills, a
field of another group or the clock's step index, or has a mask that moves) damps the first
substep of every window, so its automatic count is at least 2: one damped substep, then
Crank–Nicolson substeps (the window's error falls as `1/n²` with the count `n`). With
`substeps = 1` such a window is Backward Euler in two halves (first order, at twice Backward
Euler's cost). Crank–Nicolson does not keep nonnegative data nonnegative (a stiff decay
overshoots below 0): `lower_bound` clips each substep (for a consumption field,
[`BackwardEuler`](@ref) needs no clip). One type for both routes.

# Keywords
The keywords are those of [`BackwardEuler`](@ref), with the same defaults, meanings and
checks; the automatic counts use the shift `2/h`.

See also [`BackwardEuler`](@ref), [`BDF2`](@ref).
"""
struct CrankNicolson <: AbstractImplicitFieldAlgorithm
    substeps::Union{Nothing, Int}
    nlsolve::Union{Nothing, LatticeNewton}
    lower_bound::Union{Nothing, Float64}
    linsolve::Any
    solver_type::Any
    init::Union{Nothing, Symbol}
    compute_type::Any
    function CrankNicolson(
            substeps, nlsolve, lower_bound, linsolve,
            solver_type, init = nothing, compute_type = :auto
        )
        return new(
            _implicit_keywords(
                "CrankNicolson", substeps, nlsolve, lower_bound, linsolve, solver_type
            )..., _init_keyword(
                "CrankNicolson", init
            ),
            _compute_keyword("CrankNicolson", compute_type)
        )
    end
end
function CrankNicolson(;
        substeps = nothing, nlsolve = nothing, lower_bound = nothing, linsolve = :auto,
        solver_type = :auto, init = nothing, compute_type = :auto, kw...
    )
    isempty(kw) || throw(_implicit_kwerror("CrankNicolson", kw))
    return CrankNicolson(
        substeps, nlsolve, lower_bound, linsolve, solver_type, init, compute_type
    )
end
nbuffers(::CrankNicolson) = 2

"""
    BDF2(; substeps = nothing, nlsolve = nothing, lower_bound = nothing,
           linsolve = :auto, solver_type = :auto, init = nothing, compute_type = :auto)

The two-step backward differentiation formula (second order, L-stable).

Each substep of `h = dt / n` solves `(u − (4uⁿ − uⁿ⁻¹)/3)/(2h/3) = r(u)` at its end time
`tⁿ⁺¹`, by the Newton iterations of [`BackwardEuler`](@ref) with the shift `3/(2h)`. It
needs the state one substep back, `uⁿ⁻¹`, which the runtime keeps (not in the problem's
state: never saved, never in a checkpoint). The first substep after a start (at `init`,
after every [`reset!`](@ref): a state, input, table or parameter write, a restored
checkpoint) has none: it is one Backward Euler substep (with the Backward Euler operator,
then the BDF2 operator again: two extra rebuilds). The formula holds for a constant `h`
only, so every change of `h` (a new automatic count after a parameter, input or table write;
a new `substeps`) restarts it the same way. Moving data (a mask, the CPM's inputs) do not
restart it. BDF2 does not keep nonnegative data nonnegative (its right side `(4uⁿ − uⁿ⁻¹)/3`
is negative where `uⁿ⁻¹ > 4uⁿ`): `lower_bound` clips each substep; for a consumption field,
[`BackwardEuler`](@ref) needs no clip. One type for both routes.

# Keywords
The keywords are those of [`BackwardEuler`](@ref), with the same defaults, meanings and
checks; the automatic counts are those of the Backward Euler start (shift `1/h`), so they
hold for every substep.

See also [`BackwardEuler`](@ref), [`CrankNicolson`](@ref).
"""
struct BDF2 <: AbstractImplicitFieldAlgorithm
    substeps::Union{Nothing, Int}
    nlsolve::Union{Nothing, LatticeNewton}
    lower_bound::Union{Nothing, Float64}
    linsolve::Any
    solver_type::Any
    init::Union{Nothing, Symbol}
    compute_type::Any
    function BDF2(
            substeps, nlsolve, lower_bound, linsolve,
            solver_type, init = nothing, compute_type = :auto
        )
        return new(
            _implicit_keywords(
                "BDF2", substeps, nlsolve, lower_bound, linsolve, solver_type
            )..., _init_keyword("BDF2", init),
            _compute_keyword("BDF2", compute_type)
        )
    end
end
function BDF2(;
        substeps = nothing, nlsolve = nothing, lower_bound = nothing, linsolve = :auto,
        solver_type = :auto, init = nothing, compute_type = :auto, kw...
    )
    isempty(kw) || throw(_implicit_kwerror("BDF2", kw))
    return BDF2(substeps, nlsolve, lower_bound, linsolve, solver_type, init, compute_type)
end
nbuffers(::BDF2) = 2

"""
    QuasiSteady(; nlsolve = nothing, linsolve = :auto, solver_type = :auto, init = nothing,
        compute_type = :auto)

The steady state of a group in each window: `0 = r(u)`, solved once per window.

The solve is at the window's start time (in a `PottsProblem`: at the σ of that MCS; on a
field problem: at the integrator's inputs) by the Newton iterations of
[`BackwardEuler`](@ref) with no time-step term, `−J̃ δ = r(u_k)`, from the field's current
values (the previous window's solution: a warm start). A field stepped this way follows
the inputs at once, as a steady field does. The window `dt`: as for
[`BackwardEuler`](@ref).

# Keywords
- `nlsolve = nothing`: [`LatticeNewton`](@ref) or `nothing`. `nothing` keeps the automatic
  count: 1 for a linear group whose operator is exact (one linear solve is the steady
  state), else 8 (a nonlinear or switched row, a term out of the operator), each checked on
  the device. `LatticeNewton(; κ, max_iter, check_div)` runs at most `max_iter` iterations
  per window, stops early on the `NLNewton` rate-scaled tolerance, and ends with
  `ReturnCode.ConvergenceFailure` on a budget hit when `check_div = true` (or accepts when
  `check_div = false`).
- `linsolve = :auto`, `solver_type = :auto`, `compute_type = :auto`: as for
  [`BackwardEuler`](@ref).
- `init = nothing`: `:steady` makes the initial state the steady state too (one more solve
  before the first window, as for [`BackwardEuler`](@ref)); with `nothing` the state at the
  start time is the initial state, and the first window solves.

Steady rows that read one another (a cycle in the group, a cross diffusion `Δ(b)` in a's
row, or a term the operator does not see, such as `c²` in `0 ~ q − c²`) are solved together:
one Newton iteration solves all of them with every cross term in the operator, by a
restarted flexible GMRES
(`linsolve = LatticeGMRES(; gmres_restart = 20, maxiters = 60, reltol = 1e-6)` under
`:auto`; a `LatticePCG` or `LatticeMultigrid` given here is its preconditioner), with each
row's own solve as the preconditioner. There is no gain limit: two steady fields in one
`QuasiSteady` may read each other as strongly as their steady state allows. Give the fields
of such a loop one `QuasiSteady`: two steady groups that read each other are lagged by a
window, and a loop whose gain does not contract is refused with that route. A coupled steady
system whose Jacobian has an eigenvalue with nonnegative real part has no stable steady
state and is refused, naming the sign and the route `BackwardEuler`: checked mode by mode
for linear rows with constant coefficients on one grid, else (a linear group whose
coefficients vary by site) estimated by Arnoldi through the coupled operator at the bind and
at each parameter write (a nonlinear group right after its first solve after either, or
after the steady start). The coupled solve is deterministic (fixed reduction order, no
atomics): the same backend gives the same bits, and the CPU host form and a device agree
bitwise. On a GPU it waits for each dot product of its GMRES (Krylov.jl solves the small
least-squares problem on the host), so a coupled steady group adds about 100–250 GPU waits
per window, where every other field solve waits for none.

There is no `substeps` (one solve per window; `nlsolve` sets the Newton iterations) and no
`lower_bound` (a steady solve has no substep to clip). The steady state must exist and be
unique: a positive local derivative the operator sees (a growth `+ g c`) is refused at build
and at every parameter write (a growing row's steady state is unstable or not unique: step
it with [`BackwardEuler`](@ref)), and so is a field with no decay and no fixed value (no
Dirichlet or Robin face, no mask: `0 = rhs` then has no solution or many). A region that the
CPM's inputs or a mask cut off with neither (an island) is found on the device: its solve
cannot reduce the residual there, and a budget hit with no real reduction ends the run with
`ReturnCode.ConvergenceFailure`, naming the field, the window and the route (a decay or a
fixed value in that region). One type for both routes.

See also [`BackwardEuler`](@ref), [`LatticeGMRES`](@ref LatticeFields.Solvers.LatticeGMRES).
"""
struct QuasiSteady <: AbstractImplicitFieldAlgorithm
    substeps::Nothing                   # (none: one solve per window)
    nlsolve::Union{Nothing, LatticeNewton}
    lower_bound::Nothing                      # (none: no substep to clip)
    linsolve::Any
    solver_type::Any
    init::Union{Nothing, Symbol}
    compute_type::Any
    function QuasiSteady(
            nlsolve, linsolve, solver_type, init = nothing, compute_type = :auto
        )
        _, k, _, i, T = _implicit_keywords(
            "QuasiSteady", nothing, nlsolve, nothing, linsolve, solver_type
        )
        return new(
            nothing, k, nothing, i, T, _init_keyword("QuasiSteady", init),
            _compute_keyword("QuasiSteady", compute_type)
        )
    end
end
function QuasiSteady(;
        nlsolve = nothing, linsolve = :auto, solver_type = :auto,
        init = nothing, compute_type = :auto, kw...
    )
    haskey(kw, :substeps) && throw(
        ArgumentError(
            string(
                "QuasiSteady: no keyword `substeps`: a steady field is solved ",
                "once per window; give `nlsolve = LatticeNewton(; max_iter = k)` for more \
                    Newton iterations per window"
            )
        )
    )
    haskey(kw, :lower_bound) && throw(
        ArgumentError(
            string(
                "QuasiSteady: no keyword `lower_bound`: a steady solve has no substep to ",
                "clip (a steady state below a bound means the equation allows it; \
                    `BackwardEuler` keeps nonnegative data ",
                "nonnegative)"
            )
        )
    )
    isempty(kw) || throw(
        ArgumentError(
            string(
                "QuasiSteady: no keyword ", join(("`$k`" for k in keys(kw)), ", "),
                "; its keywords are `nlsolve`, `linsolve`, `solver_type`, `init` and \
                    `compute_type`", _dt_text(kw)
            )
        )
    )
    return QuasiSteady(nlsolve, linsolve, solver_type, init, compute_type)
end
nbuffers(::QuasiSteady) = 2

"""
    ExplicitMap(; compute_type = :auto)

Discrete maps `Shift(t, 1)(c) ~ rhs`: one application per unit of time.

# Keywords
- `compute_type = :auto`: as for [`BackwardEuler`](@ref).

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: ExplicitMap

julia> LatticeFields.Problems.alg_family(ExplicitMap())
:map
```
"""
struct ExplicitMap <: AbstractFieldAlgorithm
    compute_type::Any
    ExplicitMap(compute_type) = new(_compute_keyword("ExplicitMap", compute_type))
end
ExplicitMap(; compute_type = :auto) = ExplicitMap(compute_type)
nbuffers(::ExplicitMap) = 2

# The window of a step of `alg` on a problem whose discretization declares the clock of
# period `clock` (`nothing`: none): `dt`, the `solve` keyword, or the clock's period when
# `dt` is left out; without a clock `dt` is required (nothing else sets the window: `saveat`
# never does). A given `dt` must divide the period to a relative 1e-12: the stepper lands on
# every clock boundary, so a period holds a whole number of windows (`_per`).
function _window(alg::AbstractFieldAlgorithm, dt, clock)
    dt === nothing || (dt isa Real && !(dt isa Bool) && isfinite(dt) && dt > 0) ||
        throw(ArgumentError(string("`solve`/`init`: dt = ", repr(dt), " must be finite \
            and > 0")))
    if dt === nothing
        clock === nothing && throw(
            ArgumentError(
                string(
                    "`", nameof(typeof(alg)),
                    "` on a `FieldProblem` needs `dt` (the window) when the \
                        discretization declares no ",
                    "`clock`: nothing else sets the window, and `saveat` never does; give \
                        `solve(prob, alg; dt)` or ",
                    "`LatticeDiscretization(…; clock = τ)`"
                )
            )
        )
        return float(clock)
    end
    clock === nothing || _per(dt, clock)
    return float(dt)
end
# a map steps one unit of time: a clock is a whole number of map steps
function _window(::ExplicitMap, dt, clock)
    dt === nothing || dt == 1 || throw(
        ArgumentError(
            string(
                "`solve`/`init`: dt = ", repr(dt), " on a map: a map ",
                "steps one unit of time; leave `dt` out"
            )
        )
    )
    clock === nothing || (clock >= 1 && abs(round(clock) - clock) <= 1.0e-12 * clock) ||
        throw(
        ArgumentError(
            string(
                "the clock's period ", clock,
                " is not a whole number of map steps (a map steps one unit of time, and ",
                "`step_index(t)` counts whole periods): give `clock = n` with an integer \
                    n ≥ 1, or no clock"
            )
        )
    )
    return 1.0
end
# the number of windows `dt` in one period of the clock
function _per(dt, clock)
    m = round(Int, clock / dt)
    # (to a relative 1e-12, or a few roundings of `dt`'s type when that is coarser: Float32)
    m >= 1 && abs(m * dt - clock) <= max(1.0e-12, 4 * eps(typeof(float(dt)))) * clock ||
        throw(
        ArgumentError(
            string(
                "dt = ", dt, " does not divide the clock's period ", clock,
                " (to the rounding of dt's type): the stepper lands on every ",
                "boundary of the clock, so a period holds a whole number of windows; give \
                    dt = ", clock, "/n, or leave `dt` out ",
                "to step windows of ", clock
            )
        )
    )
    return m
end

"""
    update_key(alg)

The update that algorithm `alg` fuses into a group's rate program, as a key.

A group's fused program and plans are cached by it (and the value type), so two algorithms
with one update share them (`ExplicitEuler()` and `ExplicitEuler(; substeps = 4)`:
`:euler`). It names every part of the algorithm that changes the fused program: a clip
`lower_bound` is part of it (`(:euler, 0.0)`).

# Arguments
- `alg`: the field algorithm.

# Returns
- The key: a `Symbol`, or a `Tuple` that adds the clip.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: ExplicitEuler

julia> LatticeFields.Problems.update_key(ExplicitEuler(; lower_bound = 0.0))
(:euler, 0.0)
```
"""
update_key(a::ExplicitEuler) = a.lower_bound === nothing ? :euler : (:euler, a.lower_bound)
update_key(::ExplicitMap) = :map
# an implicit group's store holds the arrays of the explicit program (the same fields, rules
# and kernels), and its own residual and operator programs alias them (`implicit.jl`)
update_key(::AbstractImplicitFieldAlgorithm) = :euler

"""
    update_rule(alg) -> Union{EulerRule, Nothing}

The update of algorithm `alg` for the update pass ([`fuse_update`](@ref
LatticeFields.Compile.fuse_update)).

`rule(kb, c, r)` gives the new value of a field from its current value `c` and its rate `r`
(IR handles).

# Arguments
- `alg`: the field algorithm.

# Returns
- `ExplicitEuler`: an `EulerRule`, `c + dt · r` with `dt = G.rt[2]`, then
  `max(·, lower_bound)` with a clip. An implicit algorithm: an `EulerRule` with no clip.
- `ExplicitMap`: `nothing` (a map program stores its values itself).
"""
update_rule(a::ExplicitEuler) = EulerRule(a.lower_bound)
update_rule(::ExplicitMap) = nothing
update_rule(::AbstractImplicitFieldAlgorithm) = EulerRule(nothing)
"""
    EulerRule(lower_bound)

The Euler update of the update pass: `rule(kb, c, r)` gives `c + dt · r`, with `dt` the
runtime slot `RT_DT`, then `max(·, lower_bound)` when `lower_bound` is a number.

# Fields
- `lower_bound::Union{Nothing, Float64}`: the clip, or `nothing` for none.

See also [`update_rule`](@ref).
"""
struct EulerRule
    lower_bound::Union{Nothing, Float64}
end
function (u::EulerRule)(kb, c, r)
    v = c + Ex(kb, runtime!(kb, RT_DT)) * r
    return u.lower_bound === nothing ? v : max(v, u.lower_bound)
end

"""
    alg_family(alg) -> Symbol

The family of algorithm `alg`. A problem steps one family: rates and maps are never mixed in
one problem.

# Arguments
- `alg`: the field algorithm.

# Returns
- `:rate` for an algorithm that steps rates `D(c) ~ rhs`, `:map` for one that applies maps
  `Shift(t, 1)(c) ~ rhs`.
"""
alg_family(::AbstractFieldAlgorithm) = :rate
alg_family(::ExplicitMap) = :map

"""
    alg_cache(alg, group, store) -> cache

The algorithm's own state for one group on `store`: the workspaces and history of an
implicit or multistep method.

It lives in the group's [`GroupRuntime`](@ref); [`reset!`](@ref) drops its history
(`reset_cache!`), and after each step [`advance!`](@ref) returns its `step_retcode!`.

# Arguments
- `alg`: the field algorithm.
- `group`: the group the cache is for.
- `store`: the [`FieldStore`](@ref) of the group.

# Returns
- The cache, or `nothing` for `ExplicitEuler` and `ExplicitMap`.
"""
alg_cache(::AbstractFieldAlgorithm, group, store) = nothing

"""
    reset_cache!(cache)

Drop the history of an algorithm's cache.

It runs when the state was written (`integ[c] = values`, `reinit!`), or the parameters or
inputs changed. The default does nothing: a cache with no history (`nothing`, or an
algorithm's own workspace) needs no method.

# Arguments
- `cache`: the algorithm's cache ([`alg_cache`](@ref)).

# Returns
- `nothing`.
"""
reset_cache!(cache) = nothing

"""
    step_retcode!(cache, rt) -> ReturnCode.T

The return code of the step that runtime `rt` just took.

# Arguments
- `cache`: the algorithm's cache ([`alg_cache`](@ref)).
- `rt`: the group's [`GroupRuntime`](@ref).

# Returns
- `ReturnCode.Success` for an explicit algorithm (`nothing` cache). An implicit solver
  returns its failure code (`ConvergenceFailure`, …), and the driver stops with it.
"""
step_retcode!(::Nothing, rt) = SciMLBase.ReturnCode.Success

"""
    LinearSolver

The linear solvers (`Solvers.LatticePCG`, `Solvers.LatticeMultigrid`,
`Solvers.LatticeGMRES`), as a `Union`.

Each is the `linsolve` of an implicit field solver, never a field algorithm itself.
"""
const LinearSolver = Union{
    Solvers.LatticePCG, Solvers.LatticeMultigrid, Solvers.LatticeGMRES,
}

"""
    linear_solver_refusal(what, s, route) -> ArgumentError

The refusal of a linear solver `s` given where a field algorithm goes.

Both coupled and standalone routes and `init` use it.

# Arguments
- `what`: the place, for the message.
- `s`: the linear solver given.
- `route`: the working spelling, for the message.

# Returns
- The `ArgumentError` (not thrown).
"""
function linear_solver_refusal(
        what, s, route;
        implicit = "`BackwardEuler(; linsolve = $(repr(s)))`"
    )
    return ArgumentError(
        string(
            what,
            ": `", repr(s),
            "` is a linear solver: it is the `linsolve` of an implicit field solver, not \
                a field solver; give it to ",
            "one, ", implicit,
            ", or step the field with an explicit field algorithm: give ", route
        )
    )
end

"""
    FieldGroups(field => alg, …; default = nothing)

An algorithm that steps the fields of a problem in groups: each field takes the algorithm of
its pair (a field symbol, or a state key), the others `default`. Fields with `isequal`
algorithms form one group (the comparison covers the whole value). Groups run in state order
(the order of their first field), each window `dt` (the `solve` keyword): a group reads the
fields of the other groups from their arrays, as they are when it runs (coupled
`PottsProblem` field phases do the same), and ends each step in slot 1, so the next group
reads the current values.

Groups that read one another in a loop (`c` reads `o` and `o` reads `c`, directly or through
other groups) can grow without bound at any substep count, because each holds the others'
values over the window. For each group in such a loop, `dt` times the largest sum, over the
group's rows, of the largest coefficient magnitudes of the terms that read other groups of
the same loop must be at most 1 (a conservative limit). Reads of groups outside the loop do
not count. Past it the problem is refused, naming the fields of the loop. The routes: step
those fields in one group (with an explicit `substeps = n` when their rows are not
diagonally dominant), or use a smaller `dt` that divides the time span. A one-way chain (`u`
reads `c`, `c` does not read `u`) has no loop and is not limited: each group is stable under
its own count. A group with a term that the stability bound cannot see and that reads
another field counts as reading every other group. A term that reads only its own field
(`-a^3`) does not. [`substep_counts`](@ref) gives each group's count.

Every group steps the same window, the `dt` of `solve`. A rate algorithm and a map algorithm
are never mixed in one problem. A field without a pair and with no `default` is
an error naming it.

# Arguments
- `field => alg`: a field symbol or state key, and the algorithm of that field. A
  `FieldGroups` or a linear solver as `alg` is an `ArgumentError`.

# Keywords
- `default = nothing`: the algorithm of the fields without a pair.

# Examples
```julia
solve(prob, FieldGroups(o => ExplicitEuler(; substeps = 4); default = ExplicitEuler()); \
dt = 0.1)
```
"""
struct FieldGroups <: AbstractFieldAlgorithm
    pairs::Vector{Pair{Any, AbstractFieldAlgorithm}}
    default::Union{Nothing, AbstractFieldAlgorithm}
    function FieldGroups(pairs::Vector{Pair{Any, AbstractFieldAlgorithm}}, default)
        for (k, a) in pairs
            a isa FieldGroups &&
                throw(ArgumentError("FieldGroups: the algorithm of `$k` is a \
                    `FieldGroups`; give one algorithm per field"))
        end
        default isa FieldGroups &&
            throw(ArgumentError("FieldGroups: `default` is a `FieldGroups`; give one \
                algorithm"))
        return new(pairs, default)
    end
end
function FieldGroups(pairs::Pair...; default = nothing)
    for (k, a) in pairs
        a isa LinearSolver &&
            throw(linear_solver_refusal("FieldGroups: the field `$k`", a, "`$k => \
                ExplicitEuler(…)`"))
        a isa AbstractFieldAlgorithm ||
            throw(ArgumentError("FieldGroups: `$k => $(repr(a))` is not a field algorithm"))
    end
    default isa LinearSolver &&
        throw(linear_solver_refusal("FieldGroups: `default`", default, "`default = \
            ExplicitEuler(…)`"))
    default === nothing || default isa AbstractFieldAlgorithm ||
        throw(ArgumentError("FieldGroups: default = $(repr(default)) is not a field \
            algorithm"))
    return FieldGroups(
        Pair{Any, AbstractFieldAlgorithm}[k => a for (k, a) in pairs],
        default
    )
end
function nbuffers(g::FieldGroups)
    return maximum(
        nbuffers, [
            last.(g.pairs);
            g.default === nothing ? AbstractFieldAlgorithm[] : [g.default]
        ]
    )
end

# SciML's algorithm traits: a field algorithm steps fixed windows (not adaptive), has `init`
# and `step!`, and its order in time is the stepper's (a map is exact per step: order 0, as
# OrdinaryDiffEq's `FunctionMap`; a group of algorithms: the lowest of its members)
SciMLBase.isadaptive(::AbstractFieldAlgorithm) = false
SciMLBase.has_init(::AbstractFieldAlgorithm) = true
SciMLBase.has_step(::AbstractFieldAlgorithm) = true
SciMLBase.alg_order(::Union{ExplicitEuler, BackwardEuler, QuasiSteady}) = 1
SciMLBase.alg_order(::Union{CrankNicolson, BDF2}) = 2
SciMLBase.alg_order(::ExplicitMap) = 0
function SciMLBase.alg_order(g::FieldGroups)
    return minimum(
        SciMLBase.alg_order,
        [last.(g.pairs); g.default === nothing ? AbstractFieldAlgorithm[] : [g.default]]
    )
end

"""
    canonical(alg) -> String

The one canonical text of a field algorithm (or of a solver part: `LatticePCG`,
`LatticeMultigrid`, `VCycle`, `:auto`, a number), the text both coupled and standalone
fingerprints hash.

It is what the algorithm is, not the host object, so equal specifications built afresh
print alike. `ExplicitEuler` prints `ExplicitEuler(substeps=…,lower_bound=…)`;
another algorithm prints every field, sorted by name, each by `canonical`; `:auto` prints as
given (`:auto`, unresolved, so a CPU and a device problem print alike). `init = nothing` and
`compute_type = :auto` (the defaults) are left out, so the texts recorded before them stay.
A `FieldGroups` prints its pairs as given (a caller that resolves it per field, such as
`PottsProblem`, prints the per-field map instead).

# Arguments
- `alg`: the field algorithm or solver part.

# Returns
- The canonical text as a `String`.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Problems: ExplicitEuler

julia> LatticeFields.Problems.canonical(ExplicitEuler(; substeps = 2))
"ExplicitEuler(substeps=2,lower_bound=nothing)"
```
"""
function canonical(s::ExplicitEuler)
    return string(
        "ExplicitEuler(substeps=", repr(s.substeps), ",lower_bound=", repr(s.lower_bound),
        s.init === nothing ? "" : string(",init=", repr(s.init)),
        if s.compute_type === :auto
            ""
        else
            string(",compute_type=", s.compute_type)
        end, ")"
    )
end
function canonical(m::ExplicitMap)
    return if m.compute_type === :auto
        "ExplicitMap()"
    else
        string("ExplicitMap(compute_type=", m.compute_type, ")")
    end
end
function canonical(g::FieldGroups)
    return string(
        "FieldGroups(", join((string(k, "=", canonical(a)) for (k, a) in g.pairs), ","),
        ";default=", g.default === nothing ? "nothing" : canonical(g.default), ")"
    )
end
canonical(a::AbstractFieldAlgorithm) = _canonical_fields(a)
function canonical(s::Union{Solvers.LatticePCG, Solvers.LatticeGMRES})
    return _canonical_fields(Solvers.owned(s))
end
canonical(v::Solvers.VCycle) = "VCycle($(v.nu1),$(v.nu2))"
function canonical(m::LatticeMultigrid)
    o = Solvers.owned(m)
    return string(
        "LatticeMultigrid(cycle=", canonical(o.cycle), ",cycles=", canonical(o.cycles),
        ",maxiters=", canonical(o.maxiters), ",reltol=", canonical(o.reltol),
        ",warn_tol=", canonical(o.warn_tol), ")"
    )
end
function canonical(b::LatticeBlockSolve)
    return string("LatticeBlockSolve(linsolve=", canonical(b.linsolve), ")")
end
function canonical(n::LatticeNewton)
    return string(
        "LatticeNewton(κ=", canonical(n.κ), ",max_iter=",
        canonical(n.max_iter), ",check_div=", n.check_div, ")"
    )
end
canonical(s::Symbol) = repr(s)
canonical(::Nothing) = "nothing"
canonical(x::Union{Number, AbstractString}) = repr(x)
canonical(::Type{T}) where {T} = string(T)
canonical(x) = _canonical_value(x, 0)

const _CANONICAL_DEPTH = 8
_canonical_type(T) = sprint(show, T; context = :module => Core)
const _CanonicalKnown = Union{
    AbstractFieldAlgorithm,
    Solvers.LatticePCG,
    Solvers.LatticeGMRES,
    Solvers.VCycle,
    LatticeMultigrid,
    LatticeBlockSolve,
    LatticeNewton,
    Symbol,
    Nothing,
    Number,
    AbstractString,
    Type,
}
function _canonical_value(x, depth::Int)
    x isa _CanonicalKnown && return canonical(x)
    T = typeof(x)
    (x isa Union{Enum, Missing, AbstractRange} || isprimitivetype(T)) &&
        return string(_canonical_type(T), ":", repr(x))
    container = x isa Union{AbstractDict, AbstractSet, Tuple, NamedTuple, AbstractArray}
    !container && (!isstructtype(T) || fieldcount(T) == 0) && return _canonical_type(T)
    depth > _CANONICAL_DEPTH && throw(
        ArgumentError(
            "no canonical text for $(repr(x)) (a `$T`): value nested deeper \
                than $_CANONICAL_DEPTH levels or cyclic"
        )
    )
    item(v) = _canonical_value(v, depth + 1)
    x isa AbstractDict && return string(
        _canonical_type(T), "{",
        join(sort!([string(item(k), "=>", item(v)) for (k, v) in pairs(x)]), ","), "}"
    )
    x isa AbstractSet &&
        return string(_canonical_type(T), "{", join(sort!([item(v) for v in x]), ","), "}")
    container && return string(
        _canonical_type(T), "[",
        join((string(k, "=", item(v)) for (k, v) in pairs(x)), ","), "]"
    )
    return string(
        _canonical_type(T), "(",
        join(
            (
                string(f, "=", item(getfield(x, f)))
                    for f in sort!(collect(fieldnames(T))) if isdefined(x, f)
            ),
            ","
        ), ")"
    )
end
function _canonical_fields(s)
    return string(
        nameof(typeof(s)), "(",
        join(
            (
                string(f, "=", canonical(getfield(s, f)))
                    for f in sort!(collect(fieldnames(typeof(s))))
                    if !(f === :init && getfield(s, f) === nothing) &&
                    !(f === :compute_type && getfield(s, f) === :auto)
            ), ","
        ), ")"
    )
end

# an algorithm in messages, in its keyword form (`ExplicitEuler(; substeps = 2)`)
function _algtext(a::ExplicitEuler)
    kw = [
        string(k, " = ", repr(getfield(a, k)))
            for k in (:substeps, :lower_bound, :init) if getfield(a, k) !== nothing
    ]
    a.compute_type === :auto || push!(kw, string("compute_type = ", a.compute_type))
    return isempty(kw) ? "ExplicitEuler()" : string("ExplicitEuler(; ", join(kw, ", "), ")")
end
function _algtext(a::Union{BackwardEuler, CrankNicolson, BDF2, QuasiSteady})
    kw = [
        string(k, " = ", repr(getfield(a, k)))
            for k in (:substeps, :nlsolve, :lower_bound) if getfield(a, k) !== nothing
    ]
    a.linsolve === :auto || push!(kw, string("linsolve = ", repr(a.linsolve)))
    a.solver_type === :auto || push!(kw, string("solver_type = ", a.solver_type))
    a.init === nothing || push!(kw, string("init = ", repr(a.init)))
    a.compute_type === :auto || push!(kw, string("compute_type = ", a.compute_type))
    w = nameof(typeof(a))
    return isempty(kw) ? string(w, "()") : string(w, "(; ", join(kw, ", "), ")")
end
function Base.show(
        io::IO, a::Union{
            ExplicitEuler, BackwardEuler, CrankNicolson, BDF2, QuasiSteady,
        }
    )
    return print(io, _algtext(a))
end
_algtext(a) = repr(a)
