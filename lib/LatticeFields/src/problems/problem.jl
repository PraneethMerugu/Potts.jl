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
is a minimum: the count is the larger of `n` and the bound over the terms the bound sees
(as in `@potts_model`); when no term is seen, `n` is used.
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
                 inputs = [], backend = CPU(), options = CompileOptions(), stability = p -> NaN)

The owned problem of a lowered field program (before the semantic passes). `state` are the
keys of the packed state fields (two buffers each), `u0` the flat initial state on the host,
`p` the raw parameters. `kind` is `:rate` (stepped by [`ExplicitEuler`](@ref); the program
stores `c + dt · rate` with `dt = G.rt[2]`) or `:map` ([`ExplicitMap`](@ref)). Kernels named
in `init` (the masks of masked conditions) run at `init`, after a parameter or input change,
and at the start of every step, before its substeps, so a mask that reads the time, a field
or an input follows it; the others run each substep.
`index` is the [`LatticeIndex`](@ref); `tables` are `key => values`; `inputs` are
`symbol => values` for the input fields (an array with one value per site, or a number):
every input field must have a value at `init`, an unset one is an error naming it (see
[`resolve_inputs`](@ref)). `stability(p)` is a
bound `ρ` on the spectral radius of the rate Jacobian at raw parameters `p` (NaN when
unknown); it is evaluated again whenever the parameters change, on their primal values. A
parameter that is NaN (no value) is an error at `init`.

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
    inputs::Vector{Pair{String, Any}}
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
        inputs = Pair[], backend = KA.CPU(), options::CompileOptions = CompileOptions(),
        stability::R = p -> NaN) where {R}
    kind in (:rate, :map) ||
        throw(ArgumentError("kind must be :rate or :map; got $(repr(kind))"))
    faces = face_checks(prog)
    check_faces(faces, p)
    s = semantic(prog)
    plans = Dict{Type, Tuple{StepPlan{_ndims(s)}, StepPlan{_ndims(s)}}}()
    pv = collect(p)
    prob = _field_problem(s, collect(String, state), u0, tspan, pv,
        Pair{String, Vector{Float64}}[tables...], resolve_inputs(s, index, inputs), backend, index, faces, stability, kind,
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

function _field_problem(s::Program, state, u0, tspan, p, tables, inputs, backend, index, faces,
        stability, kind, initkeys, options, plans)
    E = problem_eltype(u0, p)
    _check_eltype(E, backend)
    # the plans cache is shared by a problem's remakes, which threads may build at once
    ip, sp = lock(() -> _plans!(plans, s, initkeys, options, valtype(E), backend), _PLANS_LOCK)
    return FieldProblem{_ndims(s), typeof(backend), typeof(index),
        typeof(stability), typeof(u0), typeof(p), E}(s, ip, sp, state, u0,
        (Float64(tspan[1]), Float64(tspan[2])), p, tables, inputs, backend, index, faces, stability,
        kind, initkeys, options, plans)
end

_ndims(::Program{N}) where {N} = N

Base.eltype(::FieldProblem{N, B, X, R, U, PV, E}) where {N, B, X, R, U, PV, E} = E

SII.symbolic_container(p::FieldProblem) = p.index
SII.state_values(p::FieldProblem) = p.u0
SII.parameter_values(p::FieldProblem) = p.p
SII.current_time(p::FieldProblem) = p.tspan[1]

"""
    remake(prob::FieldProblem; u0, tspan, p, inputs)

A copy with new initial state, time span, parameters (`p` a vector, or `symbol => value`
pairs looked up in the index) or input values (`symbol => values` pairs; the others keep
theirs). Element types are kept as given: Dual parameters promote the
state, BigFloat parameters stay BigFloat. A new value type plans once (cached on the
problem family); a value-only change reuses the plans. New parameters are checked again
(degenerate Robin faces); the stability bound is a function of the parameters, evaluated
again when solved.
"""
function SciMLBase.remake(prob::FieldProblem; u0 = prob.u0, tspan = prob.tspan, p = prob.p,
        inputs = ())
    tables, p = _tables(prob, p)
    pv = _parameter_vector(prob, p)
    check_faces(prob.faces, pv)
    length(u0) == length(prob.u0) ||
        throw(ArgumentError("u0 has $(length(u0)) values; the state has $(length(prob.u0))"))
    ins = isempty(inputs) ? prob.inputs : resolve_inputs(prob.program, prob.index, inputs, prob.inputs)
    return _field_problem(prob.program, prob.state, collect(u0), tspan, pv, tables,
        ins, prob.backend, prob.index, prob.faces, prob.stability, prob.kind, prob.initkeys,
        prob.options, prob.plans)
end
# the table pairs of `p` (`Dk => values`, array parameters) as the problem's new tables, and
# the other pairs
_tables(prob::FieldProblem, p) = prob.tables, p
function _tables(prob::FieldProblem, p::Union{AbstractVector{<:Pair}, Tuple, AbstractDict})
    ix = prob.index
    ix isa LatticeIndex || return prob.tables, p
    tables = copy(prob.tables)
    rest = Pair[]
    for (k, v) in p
        t = table_key(ix, k)
        t === nothing && (push!(rest, k => v); continue)
        e = table_entry(ix, k)
        e == 0 || throw(ArgumentError("`$k` is entry $e of the table `$t`: give the whole table, `$t => values`"))
        j = findfirst(x -> first(x) == t, tables)
        n = length(last(tables[j]))
        v isa AbstractArray && length(v) == n || throw(ArgumentError(
            "the table `$k` has $n entries; give $n values (got $(v isa AbstractArray ? length(v) : v))"))
        w = Float64.(vec(collect(v)))
        all(isfinite, w) || throw(ArgumentError("the table `$t` must hold finite values (got $w)"))
        tables[j] = t => w
    end
    return tables, rest
end
_parameter_vector(::FieldProblem, p::AbstractVector{<:Real}) = collect(p)
_parameter_vector(prob::FieldProblem, p::AbstractVector{Pair}) = isempty(p) ? copy(prob.p) :
                                                               _pairs_vector(prob, p)
_parameter_vector(prob::FieldProblem, p) = _pairs_vector(prob, p)
function _pairs_vector(prob::FieldProblem, p)
    pv = Vector{promote_type(eltype(prob.p), map(x -> typeof(last(x)), collect(p))...)}(prob.p)
    prob.index isa LatticeIndex && check_parameter_keys(prob.index, (first(x) for x in p))
    for (k, v) in p
        i = SII.parameter_index(prob.index, k)      # (a computed parameter is an error naming it)
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
mutable struct FieldIntegrator{P <: FieldProblem, A, S <: FieldStore, B, M, T, PV, CL}
    prob::P
    alg::A
    store::S
    steps::NTuple{2, B}
    masks::M                            # the mask launches at both slot parities, or nothing
    clamps::CL                          # the masked fields' arrays and values (`_clamps`)
    p::PV
    pgood::PV                           # the parameters the steps are bound to
    tables::Vector{Pair{String, Vector{Float64}}}   # its own copy (`integ[Dk] = values`)
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

function _bound(prob::FieldProblem, st::FieldStore, p, parity, sp = prob.step)
    BoundStep(prob.backend,
        prob.program, sp, st, p; cur = fill(parity, length(st.cur)), c = zero(eltype(prob)))
end
_masks(prob::FieldProblem, st, p) = isempty(prob.init.launches) ? nothing :
                                    (_bound(prob, st, p, 1, prob.init), _bound(prob, st, p, 2, prob.init))

"""
    substeps(prob, alg, p = prob.p) -> Int

The substep count of `alg` on `prob` at parameters `p`: `⌈dt ρ(p) / 1.8⌉`; with a user
count `n`, the larger of `n` and the count of the bound over the terms the bound sees
([`seen_bound`](@ref)), or `n` when that is not finite; when the full bound is unknown the
count is the user's for the terms it does not cover, and a warning names them, once per
program, term and cause in a session ([`unbounded_key`](@ref): never once per value). An unknown bound with no user count is an `ArgumentError` that names the
terms the bound cannot see.
"""
substeps(::FieldProblem, ::ExplicitMap, p = nothing; tables = nothing) = 1
const _SEEN_WARNED = Set{String}()
const _SEEN_WARNED_LOCK = ReentrantLock()
# the warning's once-key: the program (its printed text, hashed) and the value-free reason
_warn_key(prob::FieldProblem, why) = string(hash(sprint(print_program, prob.program)); base = 16) * "|" * string(why)
function substeps(prob::FieldProblem, alg::ExplicitEuler, p = prob.p; tables = prob.tables)
    pp = with_tables(map(primal, p), tables)        # a policy: on the primal values
    if alg.substeps >= 1
        ρ = seen_bound(prob.stability, pp)
        n = isfinite(ρ) && ρ >= 0 ? max(alg.substeps, ceil(Int, alg.dt * ρ / 1.8)) : alg.substeps
        full = Float64(prob.stability(pp))
        if !(isfinite(full) && full >= 0) && ccall(:jl_generating_output, Cint, ()) == 0
            why = unbounded_reason(prob.stability, pp)
            # once per (program, term, cause) and session: the key holds no value, so a sweep
            # over entries or parameters warns once and the set stays bounded
            key = why === nothing ? nothing : _warn_key(prob, unbounded_key(prob.stability, pp))
            why === nothing || !lock(() -> key in _SEEN_WARNED ? false : (push!(_SEEN_WARNED, key); true),
                                     _SEEN_WARNED_LOCK) ||
                @warn string("ExplicitEuler(substeps = ", alg.substeps, "): ", n, " substeps (the request, or more for ",
                             "the terms the bound sees); the stability bound does not cover ", why, ": the count is the user's")
        end
        return n
    end
    ρ = Float64(prob.stability(pp))
    isfinite(ρ) && ρ >= 0 && return max(1, ceil(Int, alg.dt * ρ / 1.8))
    why = unbounded_reason(prob.stability, pp)
    throw(ArgumentError(string("no automatic substeps: no stability bound for these parameters (",
        why === nothing ? string("a rate term the bound cannot see, such as advection, a nonlinear rate, ",
            "or a coefficient with more than 6 kind sets and ",
            "comparisons; a parameter without a value; or coupled rows that ",
            "are not diagonally dominant, whose spectrum may be complex") : why,
        "). Give an explicit count: ExplicitEuler(; dt, substeps = n) (a minimum; the bound over ",
        "the terms it sees can raise it)")))
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
    check_values(prob.p, prob.index)
    check_parameters(prob.stability, with_tables(map(primal, prob.p), prob.tables))
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
    upload_inputs!(st, prob.program, prob.inputs; index = prob.index)
    if !isempty(st.flat)
        copyto!(st.flat[1], convert(Vector{eltype(st.flat[1])}, prob.u0))
        copyto!(st.flat[2], st.flat[1])
    end
    m = substeps(prob, alg)
    run_step!(prob.backend, prob.program, prob.init, st, prob.p; rt = (t0, dt), c = zero(E))
    clamps = _clamps(prob, st)
    _clamp!(clamps, st, prob.p)                     # the saved t0 state holds the mask values
    steps = (_bound(prob, st, prob.p, 1), _bound(prob, st, prob.p, 2))
    compile!(prob.backend, steps[1])
    integ = FieldIntegrator(prob, alg, st, steps, _masks(prob, st, prob.p), clamps, copy(prob.p), copy(prob.p),
        Pair{String, Vector{Float64}}[k => copy(v) for (k, v) in prob.tables], t0, 0, dt,
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

One step of `dt`: the masks at the step's start and the masked values at the sites they mark
(when the problem has masked conditions), then `substeps` launches of the step plan,
alternating the slot parity.
"""
function CommonSolve.step!(integ::FieldIntegrator)
    m, dt = integ.substeps, integ.dt
    h = dt / m
    t = _time(integ)
    st, sp = integ.store, integ.prob.step
    if integ.masks !== nothing
        integ.masks[_parity(integ)]((t, h))
        _clamp!(integ.clamps, st, integ.pgood) # the values the masks set now (the bound parameters)
    end
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
"""
    integ[sym]

The values of the field, input, parameter or table `sym` at the integrator's current step; a
list of symbols gives a list. A field or input comes back as a new array (on the problem's
device), a copy: writing into it, `integ[c][1, 1] = v`, changes nothing (SciML's convention);
assign the field, `integ[c] = values`. On a device the copy is a device array: compare it with
a device array, or take `Array(integ[c])` and compare host arrays.
"""
function Base.getindex(i::FieldIntegrator, sym)
    # a table first (a symbolic array is an AbstractVector too); then a list reads each of its
    # names (fields, inputs, parameters, tables alike)
    t = _read_table(i, sym)
    t === nothing || return t
    sym isa Union{AbstractVector, Tuple} && i.prob.index isa LatticeIndex && return map(s -> i[s], sym isa Tuple ? sym : collect(sym))
    k = i.prob.index isa LatticeIndex ? input_key(i.prob.index, sym) : nothing
    k === nothing && (_check_symbol(i, sym); return SII.getsym(i, sym)(i))
    f = i.prob.program.fields[fieldid(i.prob.program, k)]
    return reshape(copy(array(i.store, fieldid(i.prob.program, k), :cur)),
        ncomp(f) == 1 ? leveldims(i.prob.program, f.levels[1]) : (leveldims(i.prob.program, f.levels[1])..., ncomp(f)))
end

# the values of the table (or the entry of one) that `sym` names, else `nothing`; a list of
# names reads each
function _read_table(x::Union{FieldProblem, FieldIntegrator, FieldSolution}, sym)
    ix = (x isa FieldProblem ? x : x.prob).index
    ix isa LatticeIndex || return nothing
    t = table_key(ix, sym)
    t === nothing && return nothing
    tables = x isa FieldIntegrator ? x.tables : (x isa FieldProblem ? x : x.prob).tables
    vals = last(tables[findfirst(x -> first(x) == t, tables)])
    e = table_entry(ix, sym)
    return e == 0 ? copy(vals) : vals[e]
end
_has_table(ix, sym) = sym isa Union{AbstractVector, Tuple} && table_key(ix, sym) === nothing ?
                      any(s -> _has_table(ix, s), sym) : table_key(ix, sym) !== nothing
# `getp` of a table reads it from the problem (a table is not in the parameter vector); a list
# with a table in it reads each entry with its own `getp`
function SII.getp(sys::Union{FieldProblem, FieldIntegrator, FieldSolution}, sym)
    prob = sys isa FieldProblem ? sys : sys.prob
    ix = prob.index
    if ix isa LatticeIndex && _has_table(ix, sym)
        table_key(ix, sym) === nothing || return x -> _read_table(x, sym)
        gs = map(s -> SII.getp(sys, s), sym isa Tuple ? sym : collect(sym))
        return sym isa Tuple ? (x -> map(g -> g(x), gs)) : (x -> [g(x) for g in gs])
    end
    return invoke(SII.getp, Tuple{Any, Any}, sys, sym)
end
# a symbol as the user wrote it: `:kind`, `"kind"`, or a variable without `⋆` and `(t, x, y)`
_symtext(sym::Union{Symbol, AbstractString}) = repr(sym)
_symtext(sym) = replace(string(sym), "⋆" => "", r"\(t(, \w+)*\)" => "")

# a symbol the integrator does not know is an error listing the names it does (rather than
# SII's "Invalid symbol"); a computed parameter says it is computed
function _check_symbol(i::FieldIntegrator, sym; write::Bool = false)
    ix = i.prob.index
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && (foreach(s -> _check_symbol(i, s; write), sym); return nothing)
    k = ix.key(sym)
    (haskey(ix.vars, k) || haskey(ix.params, k) || SII.is_independent_variable(ix, sym)) && return nothing
    if haskey(ix.observed, k) || haskey(ix.derived, k)
        write && SII.parameter_index(ix, sym)          # throws: it is computed
        return nothing
    end
    names = String[_symtext(s) for s in Iterators.flatten((ix.varsyms, ix.paramsyms))]
    append!(names, values(ix.inputnames))
    append!(names, [k for k in values(ix.inputs) if !haskey(ix.inputnames, k)])
    append!(names, [first(v) for v in values(ix.tables) if last(v) == 0])
    throw(ArgumentError(string("`", _symtext(sym), "` names nothing of this problem; its names: ",
        join(("`$n`" for n in unique!(names)), ", "))))
end
# `integ[sym] .= v` would broadcast into the copy `getindex` returns and change nothing: it is
# an error that gives the assignment (F1)
function Base.dotview(i::FieldIntegrator, sym)
    ix = i.prob.index
    t = ix isa LatticeIndex ? table_key(ix, sym) : nothing
    t === nothing || table_entry(ix, sym) != 0 ||
        throw(ArgumentError(string("`integ[", t, "] .= …` would write a copy (indexing an integrator returns the ",
            "table's values): assign the table, `integ[", t, "] = values`")))
    sym = _symtext(sym)                            # as written (no `⋆`, no `(t, x, y)`)
    throw(ArgumentError(string("`integ[", sym, "] .= …` would write a copy (indexing an integrator ",
        "returns the field's values): assign the field, `integ[", sym, "] = values`")))
end
# an input symbol writes the input's array (the masks run again); any other goes to SII
function Base.setindex!(i::FieldIntegrator, v, sym)
    _write_table!(i, v, sym) && return i
    k = i.prob.index isa LatticeIndex ? input_key(i.prob.index, sym) : nothing
    k === nothing && (_check_symbol(i, sym; write = true); SII.setsym(i, sym)(i, v); return i)
    _set_input!(i.store, i.prob.program, k, _input_value(i.prob.program, k, v, input_name(i.prob.index, k);
        bool = is_bool_input(i.prob.index, k), bounds = input_bounds(i.prob.index, k)))
    _rerun_init!(i, i.pgood)                       # the parameters the steps are bound to
    return i
end

# `integ[Dk] = values` (or `integ[Dk[i]] = value`) sets the integrator's table: the store's
# array in place (the bound steps read it), then the masks and clamps run again; false if
# `sym` is no table
function _write_table!(i::FieldIntegrator, v, sym)
    ix = i.prob.index
    ix isa LatticeIndex || return false
    t = table_key(ix, sym)
    t === nothing && return false
    e = table_entry(ix, sym)
    j = findfirst(x -> first(x) == t, i.tables)
    vals = copy(last(i.tables[j]))
    n = length(vals)
    num(x) = x isa Real && !(x isa Bool)
    if e == 0
        v isa Union{AbstractArray, Tuple} && length(v) == n && all(num, v) || throw(ArgumentError(string(
            "the table `", t, "` has ", n, " entries; give a vector of ", n, " numbers (got ",
            v isa Union{AbstractArray, Tuple} ? (length(v) == n ? "a non-number" : "$(length(v))") : repr(v), ")")))
        vals .= Float64.(collect(v))
    else
        num(v) || throw(ArgumentError("`$(_symtext(sym))` is entry $e of the table `$t`: give one number (got $(repr(v)))"))
        vals[e] = Float64(v)
    end
    all(isfinite, vals) || throw(ArgumentError("the table `$t` must hold finite values (got $vals)"))
    # the checks and the substep count at the new values, before anything changes
    tables = copy(i.tables)
    tables[j] = t => vals
    check_parameters(i.prob.stability, with_tables(map(primal, i.pgood), tables))
    m = substeps(i.prob, i.alg, i.pgood; tables)
    a = i.store.tables[findfirst(x -> x.key == t, i.prob.program.tables)]
    copyto!(a, convert(Vector{eltype(a)}, vals))
    i.tables[j] = t => vals
    i.substeps = m
    _rerun_init!(i, i.pgood)
    return true
end

# a parameter set through `setp` checks the faces, recomputes the substep count from the
# stability bound at the new values, and rebinds the steps (the derived parameters are
# launch arguments); nothing recompiles. The update is atomic: on any error the parameters
# go back to the last values the steps were bound to.
function _rerun_init!(integ::FieldIntegrator, p)
    prob = integ.prob
    isempty(prob.init.launches) && return nothing
    run_step!(prob.backend, prob.program, prob.init, integ.store, p;
        rt = (_time(integ), integ.dt), c = zero(eltype(prob)))
    _clamp!(integ.clamps, integ.store, p)
    return nothing
end

# The node-value clamp, now: each masked field (`NodeValueRule`) takes its value at the sites
# its mask marks, `u = ifelse(mask, v, u)` on the current slot, and nothing else changes (no
# launch of the step plan, no slot swap). It runs after init (before the t0 save), after every
# input write and parameter change, and after the masks at the start of every step, so a
# step's first fluxes read the clamped values, for rate and map programs alike (F1). The step
# kernels still store the value at masked sites (the store-side rule).
# The masked fields of `prob` on store `st`, as a tuple (one entry per `NodeValueRule`: the
# field's buffers, its id, its mask array and the value), so the clamp is type-stable and
# allocation-free on the host (the store's own arrays are untyped)
function _clamps(prob::FieldProblem, st::FieldStore)
    prog = prob.program
    return Tuple((Tuple(st.bufs[r.field]), Int(r.field), array(st, prog.masks[r.mask].field, :cur), r.value)
                 for r in prog.rules if r isa NodeValueRule)
end
_clamp!(clamps::Tuple, st::FieldStore, p) = (foreach(c -> _clamp_one!(c, st, p), clamps); nothing)
function _clamp_one!((bufs, id, m, c), st::FieldStore, p)
    u = length(bufs) == 1 ? bufs[1] : bufs[st.cur[id]]
    v = convert(eltype(u), c.param == 0 ? c.value : c.value * p[c.param])
    KA.get_backend(u) isa KA.CPU ? _clamp_host!(u, m, v) : _clamp_device!(u, m, v)
    return nothing
end
function _clamp_host!(u, m, v)                        # host: a loop, no allocation
    n = length(m)
    length(u) % n == 0 || throw(DimensionMismatch("a masked field has $(length(u)) values for $n mask sites"))
    for j in 0:(div(length(u), n) - 1), i in 1:n
        m[i] != 0 && (u[j * n + i] = v)
    end
    return nothing
end
function _clamp_device!(u, m, v)                      # a device: one broadcast per field
    if length(u) == length(m)
        u .= ifelse.(m .!= 0, v, u)
    else                                        # components: the mask holds for each one
        U = reshape(u, length(m), :)
        U .= ifelse.(m .!= 0, v, U)
    end
    return nothing
end

function SII.finalize_parameters_hook!(integ::FieldIntegrator, _)
    try
        check_faces(integ.prob.faces, integ.p)
        check_values(integ.p, integ.prob.index)
        check_parameters(integ.prob.stability, with_tables(map(primal, integ.p), integ.tables))
        m = substeps(integ.prob, integ.alg, integ.p; tables = integ.tables)
        steps = (_bound(integ.prob, integ.store, integ.p, 1),
            _bound(integ.prob, integ.store, integ.p, 2))
        masks = _masks(integ.prob, integ.store, integ.p)
        _rerun_init!(integ, integ.p)                  # init kernels read the parameters too
        integ.substeps, integ.steps, integ.masks = m, steps, masks
        copyto!(integ.pgood, integ.p)
    catch
        copyto!(integ.p, integ.pgood)
        _rerun_init!(integ, integ.pgood)
        rethrow()
    end
    return nothing
end
