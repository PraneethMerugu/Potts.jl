# The owned fast path (v3 §8, §2.3): `FieldProblem`, solved by its own steppers through
# prebuilt Exec launches. A step's launches are bound once per slot parity; a warm step only
# changes `(t, dt)` in `G.rt`, enqueues, and flips the parity (no sync, no allocation on the
# host executor). `solve`, `init`, `step!` and `solve!` follow CommonSolve.

"""
Field stepping algorithms of the owned path.
"""
abstract type FieldAlgorithm end

"""
    ExplicitEuler(; dt, substeps = 0)

Forward Euler on the fused rate + update kernels (FV, §5.6). `dt` is the step; each step
runs `n` substeps of `dt / n`. With `substeps = 0` (the default, "automatic"),
`n = ⌈dt ρ(p) / 1.8⌉` from the problem's stability bound `ρ` at the current parameters
(§6.2), and an unknown bound (a rate term it cannot see, a parameter without a value, or
coupled rows that are not diagonally dominant) is refused. A user count `substeps = n ≥ 1`
is used as given: the bound is not evaluated, and stability is the user's choice.
"""
struct ExplicitEuler <: FieldAlgorithm
    dt::Float64
    substeps::Int
    function ExplicitEuler(dt::Real, substeps::Integer)
        dt > 0 && isfinite(dt) ||
            throw(ArgumentError("ExplicitEuler: dt = $dt must be finite and > 0"))
        substeps >= 0 || throw(ArgumentError("ExplicitEuler: substeps = $substeps < 0"))
        return new(Float64(dt), Int(substeps))
    end
end
ExplicitEuler(; dt::Real, substeps::Integer = 0) = ExplicitEuler(dt, substeps)

"""
    ExplicitMap()

Discrete maps `Shift(t, 1)(c) ~ rhs` (§5.5): one application per unit of time.
"""
struct ExplicitMap <: FieldAlgorithm end

"""
    FieldProblem(program, u0, tspan, p; state, kind, init = String[], index, tables = [],
                 backend = CPU(), options = CompileOptions(), stability = p -> NaN)

The owned problem of a lowered field program (before the semantic passes). `state` are the
keys of the packed state fields (two buffers each), `u0` the flat initial state on the host,
`p` the raw parameters. `kind` is `:rate` (stepped by [`ExplicitEuler`](@ref); the program
stores `c + dt · rate` with `dt = G.rt[2]`) or `:map` ([`ExplicitMap`](@ref)). Kernels named
in `init` run once per state upload (e.g. masks from inputs), the others each step.
`index` is the [`LatticeIndex`](@ref); `tables` are `key => values`. `stability(p)` is a
bound `ρ` on the spectral radius of the rate Jacobian at raw parameters `p` (NaN when
unknown); it is evaluated again whenever the parameters change, on their primal values.

**Number types** (P5 role model). The element type `E` of the problem is `eltype(u0)`,
promoted with the parameters only when they carry derivative parts (Dual `p` gives a Dual
state; a plain Float64 `p` leaves a Float32 state Float32; a BigFloat `p` is kept as given and
rounded once to the compute type). The bodies are emitted for the value type `valtype(E)`
(`eltype(u0)` decides; an explicit `options.T` that differs is refused); a new value type plans and emits once per
problem family, and a value-only change never recompiles. `tspan` stays Float64 on the host.
A non-isbits `E` (BigFloat) runs on the host only; Float64 values on a backend without
Float64 are refused. `p` is a plain vector, so it is a SciMLStructures structure whose
`Tunable` portion is every scalar parameter (`replace` promotes its eltype); kind tables are
constants outside `p` (not tunable in this version).
"""
struct FieldProblem{N, B, X, R, U, PV, E} <: SciMLBase.AbstractSciMLProblem
    program::Program{N}
    init::StepPlan{N}
    step::StepPlan{N}
    state::Vector{String}
    u0::U
    tspan::Tuple{Float64, Float64}
    p::PV
    tables::Vector{Pair{String, Vector{Float64}}}
    backend::B
    index::X
    faces::Vector{FaceCheck}
    stability::R
    kind::Symbol
    initkeys::Vector{String}
    options::CompileOptions
    plans::Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}    # by value type, shared by remakes
end
function FieldProblem(prog::Program, u0, tspan, p; state, kind::Symbol,
        init = String[], index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[],
        backend = KA.CPU(), options::CompileOptions = CompileOptions(),
        stability::R = p -> NaN) where {R}
    kind in (:rate, :map) ||
        throw(ArgumentError("kind must be :rate or :map; got $(repr(kind))"))
    faces = face_checks(prog)
    check_faces(faces, p)
    s = semantic(prog)
    plans = Dict{Type, Tuple{StepPlan{_ndims(s)}, StepPlan{_ndims(s)}}}()
    pv = collect(p)
    prob = _field_problem(s, collect(String, state), u0, tspan, pv,
        Pair{String, Vector{Float64}}[tables...], backend, index, faces, stability, kind,
        collect(String, init), _state_options(options, problem_eltype(u0, pv)), plans)
    ids = sort!([fieldid(s, k) for k in state])
    sort(prob.step.swaps) == ids ||
        throw(ArgumentError(string("every state field must be written ",
            "(and swapped) by every step: state ", state, ", swapped ",
            [s.fields[f].key for f in prob.step.swaps])))
    isempty(prob.init.swaps) || throw(ArgumentError("init kernels must not write the state"))
    n = sum(
        f -> nsites(s, s.fields[fieldid(s, f)].levels[1]) * ncomp(s.fields[fieldid(s, f)]),
        state; init = 0)
    length(u0) == n || throw(ArgumentError("u0 has $(length(u0)) values; the state has $n"))
    return prob
end

"""
    problem_eltype(u0, p) -> Type

The element type of a problem with initial state `u0` and parameters `p`: `eltype(u0)`
promoted with `eltype(p)` only when the parameters carry derivative parts.
"""
problem_eltype(u0, p) = promote_dual(eltype(u0), eltype(p))

# the options a problem keeps: an explicit `T` must be the state's value type (`eltype(u0)`
# decides); it is then dropped, so a `remake` to another value type plans for that type
function _state_options(o::CompileOptions, ::Type{E}) where {E}
    o.T === nothing || o.T == valtype(E) || throw(ArgumentError(string("options.T = ", o.T,
        " differs from the state's value type ", valtype(E), " (from ", E, "): the eltype of ",
        "u0 decides; pass u0 in ", o.T, " or leave T out of the options")))
    return CompileOptions(nothing, o.I, o.float64_ok, o.debug, o.index, o.lanes)
end

# the compile options of value type `V` on `backend`
function _options(o::CompileOptions, ::Type{V}, backend) where {V}
    return CompileOptions(; T = V, I = o.I,
        float64_ok = o.float64_ok && _float64_ok(V, backend), debug = o.debug,
        index = o.index, lanes = :state)
end

# Float64 in device code: allowed on the host, and for a Float64 problem on hardware that has
# it (`Exec.supports`); a Float32 problem on a device keeps the D-157 double scan (P5 C2-1)
_float64_ok(::Type{V}, backend) where {V} =
    Exec.default_float(backend) === Float64 || (V === Float64 && Exec.supports(backend, Float64))

# the init and step plans of value type `V` (planned and emitted once per family)
function _plans!(plans, s::Program, initkeys, o::CompileOptions, ::Type{V}, backend) where {V}
    return get!(plans, V) do
        keys = [k.key for k in s.kernels]
        initids = [i for (i, k) in enumerate(keys) if k in initkeys]
        opts = _options(o, V, backend)
        (plan(s, initids; options = opts), plan(s, setdiff(eachindex(keys), initids); options = opts))
    end
end

function _check_eltype(::Type{E}, backend) where {E}
    V = valtype(E)
    V <: AbstractFloat ||
        throw(ArgumentError("the state value type must be a float type; got $V (from $E)"))
    isbitstype(E) || Exec.ishost(backend) || throw(ArgumentError(string("element type ", E,
        " is not isbits: it runs on the host backend only (use T = Float32 or Float64 on a device)")))
    V <: Union{Float16, Float32} || Exec.supports(backend, Float64) || throw(ArgumentError(
        string("the backend has no Float64 compute (value type ", V, " from ", E,
            "); use T = Float32")))
    return nothing
end

function _field_problem(s::Program, state, u0, tspan, p, tables, backend, index, faces,
        stability, kind, initkeys, options, plans)
    E = problem_eltype(u0, p)
    _check_eltype(E, backend)
    ip, sp = _plans!(plans, s, initkeys, options, valtype(E), backend)
    return FieldProblem{_ndims(s), typeof(backend), typeof(index),
        typeof(stability), typeof(u0), typeof(p), E}(s, ip, sp, state, u0,
        (Float64(tspan[1]), Float64(tspan[2])), p, tables, backend, index, faces, stability,
        kind, initkeys, options, plans)
end

_ndims(::Program{N}) where {N} = N

Base.eltype(::FieldProblem{N, B, X, R, U, PV, E}) where {N, B, X, R, U, PV, E} = E

SII.symbolic_container(p::FieldProblem) = p.index
SII.state_values(p::FieldProblem) = p.u0
SII.parameter_values(p::FieldProblem) = p.p
SII.current_time(p::FieldProblem) = p.tspan[1]

"""
    remake(prob::FieldProblem; u0, tspan, p)

A copy with new initial state, time span or parameters (`p` a vector, or `symbol => value`
pairs looked up in the index). Element types are kept as given: Dual parameters promote the
state, BigFloat parameters stay BigFloat. A new value type plans once (cached on the
problem family); a value-only change reuses the plans. New parameters are checked again
(degenerate Robin faces); the stability bound is a function of the parameters, evaluated
again when solved.
"""
function SciMLBase.remake(prob::FieldProblem; u0 = prob.u0, tspan = prob.tspan, p = prob.p)
    pv = _parameter_vector(prob, p)
    check_faces(prob.faces, pv)
    length(u0) == length(prob.u0) ||
        throw(ArgumentError("u0 has $(length(u0)) values; the state has $(length(prob.u0))"))
    return _field_problem(prob.program, prob.state, collect(u0), tspan, pv, prob.tables,
        prob.backend, prob.index, prob.faces, prob.stability, prob.kind, prob.initkeys,
        prob.options, prob.plans)
end
_parameter_vector(::FieldProblem, p::AbstractVector{<:Real}) = collect(p)
function _parameter_vector(prob::FieldProblem, p)
    pv = Vector{promote_type(eltype(prob.p), map(x -> typeof(last(x)), collect(p))...)}(prob.p)
    for (k, v) in p
        i = SII.parameter_index(prob.index, k)
        i === nothing && throw(ArgumentError("`$k` is not a parameter of the problem"))
        pv[i] = v
    end
    return pv
end

"""
    FieldSolution

Saved states of an owned solve: `t`, `u` (flat host vectors), `retcode`, and the substep
count used. Indexed by symbol through SymbolicIndexingInterface: `sol[c]` is a vector of
grid-shaped arrays, `sol[c, i]` one of them.
"""
struct FieldSolution{P, U}
    prob::P
    t::Vector{Float64}
    u::Vector{U}
    retcode::SciMLBase.ReturnCode.T
    substeps::Int
end
SciMLBase.successful_retcode(s::FieldSolution) = SciMLBase.successful_retcode(s.retcode)

SII.is_timeseries(::Type{<:FieldSolution}) = SII.Timeseries()
SII.symbolic_container(s::FieldSolution) = s.prob.index
SII.state_values(s::FieldSolution) = s.u
SII.current_time(s::FieldSolution) = s.t
SII.parameter_values(s::FieldSolution) = s.prob.p
Base.getindex(s::FieldSolution, sym) = SII.getsym(s, sym)(s)
Base.getindex(s::FieldSolution, sym, i) = SII.getsym(s, sym)(s, i)
Base.length(s::FieldSolution) = length(s.t)

"""
    FieldIntegrator

The state of an owned solve: the store, the two bound steps (one per slot parity), time,
step, substep count and the saved states. `step!` advances one step of `dt`; indexing by
symbol reads (and sets) fields of the current state.

Parameters change only through `setp(integ, sym)(integ, v)` (SymbolicIndexingInterface),
which checks the faces, recomputes the substeps and rebinds the steps, or else leaves the
integrator unchanged. Writing `integ.p[i] = v` directly has no effect on the run: the steps
keep the values they were bound to.
"""
mutable struct FieldIntegrator{P <: FieldProblem, A, S <: FieldStore, B, T, PV}
    prob::P
    alg::A
    store::S
    steps::NTuple{2, B}
    p::PV
    pgood::PV                           # the parameters the steps are bound to
    t0::Float64
    iter::Int
    dt::Float64
    substeps::Int
    nsteps::Int
    save::Vector{Int}
    t::Vector{Float64}
    u::Vector{Vector{T}}
    retcode::SciMLBase.ReturnCode.T
end

function _bound(prob::FieldProblem, st::FieldStore, p, parity)
    BoundStep(prob.backend,
        prob.program, prob.step, st, p; cur = fill(parity, length(st.cur)), c = zero(eltype(prob)))
end

"""
    substeps(prob, alg, p = prob.p) -> Int

The substep count of `alg` on `prob` at parameters `p`: the user count when given (the
bound is not evaluated), else `⌈dt ρ(p) / 1.8⌉`. An unknown bound with no user count is an
`ArgumentError`.
"""
substeps(::FieldProblem, ::ExplicitMap, p = nothing) = 1
function substeps(prob::FieldProblem, alg::ExplicitEuler, p = prob.p)
    alg.substeps >= 1 && return alg.substeps
    ρ = Float64(prob.stability(map(primal, p)))     # a policy: on the primal values
    isfinite(ρ) && ρ >= 0 && return max(1, ceil(Int, alg.dt * ρ / 1.8))
    throw(ArgumentError(string("no automatic substeps: no stability bound for these ",
        "parameters (a rate term the bound cannot see, such as advection, a nonlinear rate ",
        "an array-element coefficient, or a coefficient with more than 6 kind sets and ",
        "comparisons; a parameter without a value; or coupled rows that ",
        "are not diagonally dominant, whose spectrum may be complex). Give an explicit count: ",
        "ExplicitEuler(; dt, substeps = n)")))
end

_dt(::ExplicitMap) = 1.0
_dt(a::ExplicitEuler) = a.dt

# whole number of `dt` in `span` (to a relative 1e-5, so `dt = 1f-2` counts 0.01), else an
# error
function _count(span, dt, what)
    n = round(Int, span / dt)
    abs(n * dt - span) <= 1e-5 * max(dt, abs(span)) ||
        throw(ArgumentError("$what = $span is not a whole number of steps dt = $dt"))
    return n
end

function CommonSolve.init(prob::FieldProblem, alg::FieldAlgorithm; saveat = (),
        save_start::Bool = true, save_end::Bool = true)
    (alg isa ExplicitMap) == (prob.kind == :map) || throw(ArgumentError(string(
        "a ", prob.kind == :map ? "map program is stepped by ExplicitMap()" :
              "rate program is stepped by ExplicitEuler(; dt)",
        "; got ",
        alg)))
    check_faces(prob.faces, prob.p)
    t0, tf = prob.tspan
    nsteps = _count(tf - t0, _dt(alg), "the time span")
    dt = (tf - t0) / max(nsteps, 1)                 # the step that lands on tf exactly
    save = Int[]
    save_start && push!(save, 0)
    if saveat isa Real
        k = _count(saveat, dt, "saveat")
        k >= 1 && append!(save, k:k:nsteps)
    else
        append!(save, (_count(s - t0, dt, "a saveat time") for s in saveat))
    end
    save_end && push!(save, nsteps)
    save = sort!(unique!(filter!(i -> 0 <= i <= nsteps, save)))
    E = eltype(prob)
    st = FieldStore(prob.backend, prob.program; flat = prob.state, E)
    for (k, v) in prob.tables
        settable!(st, prob.program, k, v)
    end
    if !isempty(st.flat)
        copyto!(st.flat[1], convert(Vector{eltype(st.flat[1])}, prob.u0))
        copyto!(st.flat[2], st.flat[1])
    end
    m = substeps(prob, alg)
    run_step!(prob.backend, prob.program, prob.init, st, prob.p; rt = (t0, dt), c = zero(E))
    steps = (_bound(prob, st, prob.p, 1), _bound(prob, st, prob.p, 2))
    compile!(prob.backend, steps[1])
    integ = FieldIntegrator(prob, alg, st, steps, copy(prob.p), copy(prob.p), t0, 0, dt,
        m, nsteps, save, Float64[], Vector{_ueltype(st, E)}[],
        SciMLBase.ReturnCode.Success)
    0 in save && _save!(integ)
    return integ
end

function _parity(integ::FieldIntegrator)
    isempty(integ.prob.step.swaps) ? 1 :
    integ.store.cur[integ.prob.step.swaps[1]]
end
_time(integ::FieldIntegrator) = integ.t0 + integ.iter * integ.dt

"""
    step!(integ)

One step of `dt`: `substeps` launches of the step plan, alternating the slot parity.
"""
function CommonSolve.step!(integ::FieldIntegrator)
    m, dt = integ.substeps, integ.dt
    h = dt / m
    t = _time(integ)
    st, sp = integ.store, integ.prob.step
    for j in 0:(m - 1)
        integ.steps[_parity(integ)]((t + j * h, h))
        swap!(st, sp)
    end
    integ.iter += 1
    return integ
end

_ueltype(st::FieldStore, ::Type{E}) where {E} = isempty(st.flat) ? E : eltype(st.flat[1])
_current(integ::FieldIntegrator) = isempty(integ.store.flat) ? eltype(integ.prob)[] :
                                   Array(integ.store.flat[_parity(integ)])

# a saved state that is not finite ends the solve with `ReturnCode.Unstable`
function _save!(integ::FieldIntegrator)
    u = _current(integ)
    push!(integ.t, _time(integ))
    push!(integ.u, u)
    all(isfinite, u) || (integ.retcode = SciMLBase.ReturnCode.Unstable)
    return nothing
end

function CommonSolve.solve!(integ::FieldIntegrator)
    k = searchsortedfirst(integ.save, integ.iter + 1)
    while integ.iter < integ.nsteps && integ.retcode == SciMLBase.ReturnCode.Success
        CommonSolve.step!(integ)
        if k <= length(integ.save) && integ.save[k] == integ.iter
            _save!(integ)
            k += 1
        end
    end
    KA.synchronize(integ.prob.backend)
    integ.retcode == SciMLBase.ReturnCode.Success && (isempty(integ.save) ||
     integ.save[end] != integ.iter) && !all(isfinite, _current(integ)) &&
        (integ.retcode = SciMLBase.ReturnCode.Unstable)
    return FieldSolution(integ.prob, integ.t, integ.u, integ.retcode, integ.substeps)
end

function CommonSolve.solve(prob::FieldProblem, alg::FieldAlgorithm; kw...)
    CommonSolve.solve!(
        CommonSolve.init(prob, alg; kw...))
end

SII.symbolic_container(i::FieldIntegrator) = i.prob.index
SII.state_values(i::FieldIntegrator) = i.store.flat[_parity(i)]
SII.parameter_values(i::FieldIntegrator) = i.p
SII.current_time(i::FieldIntegrator) = _time(i)
Base.getindex(i::FieldIntegrator, sym) = SII.getsym(i, sym)(i)
Base.setindex!(i::FieldIntegrator, v, sym) = (SII.setsym(i, sym)(i, v); i)

# a parameter set through `setp` checks the faces, recomputes the substep count from the
# stability bound at the new values, and rebinds the steps (the derived parameters are
# launch arguments); nothing recompiles. The update is atomic: on any error the parameters
# go back to the last values the steps were bound to.
function _rerun_init!(integ::FieldIntegrator, p)
    prob = integ.prob
    isempty(prob.init.launches) && return nothing
    run_step!(prob.backend, prob.program, prob.init, integ.store, p;
        rt = (_time(integ), integ.dt), c = zero(eltype(prob)))
    return nothing
end

function SII.finalize_parameters_hook!(integ::FieldIntegrator, _)
    try
        check_faces(integ.prob.faces, integ.p)
        m = substeps(integ.prob, integ.alg, integ.p)
        steps = (_bound(integ.prob, integ.store, integ.p, 1),
            _bound(integ.prob, integ.store, integ.p, 2))
        _rerun_init!(integ, integ.p)                  # init kernels read the parameters too
        integ.substeps, integ.steps = m, steps
        copyto!(integ.pgood, integ.p)
    catch
        copyto!(integ.p, integ.pgood)
        _rerun_init!(integ, integ.pgood)
        rethrow()
    end
    return nothing
end
