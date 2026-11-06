# The SciML path (v3 §8): `ODEProblem(ODEFunction(LatticeRHS; sys = LatticeIndex), u0, …)`.
# The right side runs the rate kernels of a program in its ODE form (each rate field `c`
# stores its rate in a scratch field `∂c`) through Exec. The solver passes a different `u`
# and `du` at each stage, so the state and rate arrays of every launch are views of `u` and
# `du` resolved at the call; the other arrays (aux, inputs, tables) live in a store.

"""
A launch argument that is a slice of the solver's `u` (`du = false`) or `du`.
"""
struct StateView
    range::UnitRange{Int}
    du::Bool
end
_resolve(a, u, du) = a
_resolve(m::StateView, u, du) = view(m.du ? du : u, m.range)

"""
One rate launch of the right side: the prebuilt launch (template arrays), its argument
template with [`StateView`](@ref) markers, the parameter derivation, the parameter count and
the compute element `c` (its type is the right side's element type).
"""
struct RHSLaunch{L, S, D, NP, C}
    launch::L
    S0::S
    derive::D
    np::Val{NP}
    c::C
end
function (r::RHSLaunch)(args)
    du, u, p, t = args
    S = map(lane -> map(a -> _resolve(a, u, du), lane), r.S0)
    P = r.derive(ntuple(i -> p[i], r.np), r.c, t, nothing)
    G = r.launch.params[2][3]
    rebind(r.launch, (S, P, typeof(G)(G.n, G.dims, (t, zero(t)))))()
    return nothing
end

# what the right side needs to build its launches for another element type
struct RHSContext{N, B}
    program::Program{N}
    backend::B
    state::Vector{String}
    rates::Dict{String, String}
    initkeys::Vector{String}
    options::CompileOptions
    tables::Vector                             # `key => values`, as given (`_table_list`)
    faces::Vector{FaceCheck}
    t0::Float64
    plans::Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}
    index::Any                                 # for the parameter checks (names)
    stability::Any                             # … and the front end's `check_parameters`
    binputs::Vector{Pair{String, Any}}         # … with the inputs it reads in an index (host, by site)
end
const MAX_VARIANTS = 8

"""
    LatticeRHS

The in-place right side `f(du, u, p, t)` of a field program's ODE form. Each call checks the
parameter-dependent Robin faces (no allocation), then enqueues the rate launches; it does not
synchronize (device work is stream-ordered with the solver's own array operations).

The launches are built for one element type `E` (the eltype of `u0`, promoted with Dual
parameters). A call whose `u`, `du`, `p` or `t` gives another compute element type (a
ForwardDiff Jacobian or time gradient, Dual parameters, a Float64 `u0` on a Float32 build)
runs a variant built once for that type (at most `MAX_VARIANTS` kept, least recently used
dropped): new bodies only for a new value type, its own arrays for the float fields that are
not state (aux, scratch) and its tables in its value type, the integer inputs shared.

Init kernels (masks, aux values from parameters) run on each build's own store with that
build's parameters. With plain Float32/Float64 parameters they re-run whenever the vector
changes (a new `p` object, as `remake` gives, or new values in place) and are skipped for the
same unchanged `p`, so the native type stays the allocation-free path. Any other parameter
type (Duals, BigFloat) re-runs them on every call: ForwardDiff's chunk mode re-seeds the
partials of one vector in place.

**Threads.** The aux, scratch and table arrays live in the build's store, which every call
writes. A build belongs to the first task that calls it (until that task ends); a call from
another task (a threaded `EnsembleProblem` whose trajectories share the function, as with
`safetycopy = false`) runs a copy of its own, built once per task (under a lock) with its own
store and variants, held by this build (a finished task's copy is dropped when the next copy
is built) and found through a weak reference in the task's local storage, so concurrent
trajectories never write one store and a dropped build frees its copies. A finished task's
copy is dropped only when the next copy is built, so a build keeps the stores of up to one
copy per task that called it (about `nthreads()` under `EnsembleThreads`) until then. The owner's calls take no lock; a task's later calls of its copy take no lock
either, and neither allocates.
"""
struct LatticeRHS{L <: Tuple, W, E, X, I}
    launches::L
    walk::W
    faces::Vector{FaceCheck}
    store::FieldStore
    ctx::X
    init::I                                    # the init plan
    lastp::Vector{Any}                         # [the parameter vector init last ran with]
    lastv::Vector{Float64}                     # … and its primal values
    checkp::Vector{Any}                        # [the parameter vector last checked]
    checkv::Vector{Float64}                    # … and its primal values
    variants::Dict{Type, Any}                  # element type → LatticeRHS (bounded, LRU)
    order::Vector{Type}
    owner::Vector{Any}                         # [the task that runs this build, or nothing]
    copies::Dict{Task, Any}                    # the builds of other tasks (finished ones dropped)
    lock::ReentrantLock                        # guards `owner` changes and `copies`
    synced::Vector{Any}                        # [the `LatticeParameters` whose tables and inputs the store holds]
    stamp::Vector{Int}                         # … at its write count
end
_rhs_eltype(du, u, p, t) = promote_dual(promote_dual(promote_type(eltype(u), eltype(du)), eltype(_pvals(p))), typeof(t))
function (f::LatticeRHS{L, W, E})(du, u, p, t) where {L, W, E}
    f.owner[1] === current_task() || return _other_task(f, du, u, p, t)
    pv = _pvals(p)
    degenerate_face(f.faces, pv) == 0 || check_faces(f.faces, pv)
    C = _rhs_eltype(du, u, p, t)
    C === E || return _variant(f, C)(du, u, p, t)
    # the tables and inputs of `p` (F4-00): uploaded again when `p` or its write count changes
    _synced(f, p) || _sync!(f, p)
    # the computed slots (F2-15): derived again when the values change, and on every call for
    # parameters with derivative parts (a reseeded Dual vector keeps its primal values)
    _derives(f) && (_plainp(pv) && _checked(f, pv) || derive!(pv, _ptables(p, f.ctx.tables), f.ctx.index))
    _checked(f, pv) || _check!(f, p)
    isempty(f.init.launches) || _same_params(f, pv) || _init!(f, pv)
    f.walk(f.launches, (du, u, pv, t))
    return nothing
end

# the store holds the tables and inputs of `p` (a raw parameter vector: the build's own)
# a plain vector holds no input values: the store's inputs are those given at the build (an
# eager `ode_problem`), or of a `LatticeParameters` an earlier call synced; else the inputs
# would read as zero, which is refused (review finding 5)
_synced(f::LatticeRHS, p) = f.synced[1] !== nothing || _no_inputs(f.ctx.program) || _raw_inputs(f)
_no_inputs(s::Program) = !any(fd -> fd.role == :input, s.fields)
function _raw_inputs(f::LatticeRHS)
    ks = [input_name(f.ctx.index, fd.key) for fd in f.ctx.program.fields if fd.role == :input]
    throw(ArgumentError(string("the parameters are a plain vector, which holds no input values: the input field",
        length(ks) == 1 ? " " : "s ", join(("`$k`" for k in ks), ", "), " would read as zero. Give the problem's ",
        "parameters, `prob.p` (a `LatticeParameters`, with the inputs), or `remake(prob; p = values)`")))
end
_synced(f::LatticeRHS, p::LatticeParameters) = f.synced[1] === p && f.stamp[1] == p.stamp[]
# upload the tables and inputs of `p` into the store, in place (the bound launches hold the
# arrays); the init kernels and the checks run again at this call
function _sync!(f::LatticeRHS, p::LatticeParameters)
    prog, st = f.ctx.program, f.store
    for (k, v) in p.tables
        a = st.tables[findfirst(t -> t.key == k, prog.tables)]
        copyto!(a, convert(Vector{eltype(a)}, collect(v)))
    end
    check_inputs_set(p.inputs; index = f.ctx.index)
    for (k, v) in p.inputs
        _set_input!(st, prog, k, v)
    end
    f.lastp[1] = nothing
    f.checkp[1] = nothing
    f.synced[1] = p
    f.stamp[1] = p.stamp[]
    return nothing
end

# the tables of the right side under a SciML function (an ODEFunction, or one wrapping it), or
# `nothing` (then the computed slots are not derived for a bound check)
rhs_tables(f::LatticeRHS) = f.ctx.tables
rhs_tables(f) = hasproperty(f, :f) ? rhs_tables(getproperty(f, :f)) : nothing
_derives(f::LatticeRHS) = _hasderive(f.ctx.index)
_hasderive(ix) = false
_hasderive(ix::LatticeIndex) = ix.derive !== nothing
_plainp(p) = p isa AbstractVector{<:Union{Float32, Float64}}

# Init is skipped only for plain Float32/Float64 parameters that are the same object with the
# same values (exact in Float64). Any other type re-runs init on every call: ForwardDiff's
# chunk mode re-seeds the partials of one Dual vector in place (same object, same primal
# values), and a BigFloat changed below Float64 resolution would compare equal.
_same_params(::LatticeRHS, p) = false
_same_params(f::LatticeRHS, p::AbstractVector{<:Union{Float32, Float64}}) =
    f.lastp[1] === p && length(f.lastv) == length(p) &&
    all(i -> f.lastv[i] == Float64(p[i]), eachindex(f.lastv))
function _init!(f::LatticeRHS{L, W, E}, p) where {L, W, E}
    run_step!(f.ctx.backend, f.ctx.program, f.init, f.store, p; rt = (f.ctx.t0, 0.0), c = zero(E))
    f.lastp[1] = p
    resize!(f.lastv, length(p))
    f.lastv .= [Float64(primal(x)) for x in p]
    return nothing
end

# The parameter checks (a NaN value, the front end's `check_parameters`, as negative diffusion)
# run whenever the parameters change: a new `p` object (`remake`, a solver's own copy) or new
# primal values in place (`setp` on an integrator, which takes effect at the next call). The
# same unchanged `p` skips them without allocating. On any change of primal values the checks
# run (Dual parameters reseeded in place keep their primal values, so they are checked once).
_checked(f::LatticeRHS, p) = f.checkp[1] === p && length(f.checkv) == length(p) &&
                             all(i -> f.checkv[i] == Float64(primal(p[i])), eachindex(f.checkv))
function _check!(f::LatticeRHS, p)
    pv = _pvals(p)
    check_values(pv, f.ctx.index)
    check_parameters(f.ctx.stability, with_tables(map(primal, pv), _ptables(p, f.ctx.tables); inputs = _binputs(f.ctx, p)))
    f.checkp[1] = pv
    resize!(f.checkv, length(pv))
    f.checkv .= [Float64(primal(x)) for x in pv]
    return nothing
end
# the inputs the stability bound reads in an index, shaped by site: those of `p`, or the ones
# the problem was built with
_binputs(ctx, p) = ctx.binputs
function _binputs(ctx, p::LatticeParameters)
    bks = bound_inputs(ctx.stability)
    isempty(bks) && return ctx.binputs
    return Pair{String, Any}[k => _site_shaped(ctx.program, k, v) for (k, v) in p.inputs if k in bks && v !== nothing]
end

# A deep copy (SciML's `safetycopy` of an ensemble's problem) is a new build: it has no owner
# and its own lock. Serializing writes the same: a build with no owner (a running task does
# not serialize), which the task that first calls the deserialized function claims.
_unowned(f::LatticeRHS, val) = typeof(f)(map(fieldnames(typeof(f))) do k
    k === :owner ? Any[nothing] : k === :copies ? Dict{Task, Any}() : k === :lock ? ReentrantLock() :
    k === :synced ? Any[getfield(f, :synced)[1] === nothing ? nothing : :given] :
    val(getfield(f, k))
end...)
function Base.deepcopy_internal(f::LatticeRHS, d::IdDict)
    haskey(d, f) && return d[f]
    g = _unowned(f, x -> Base.deepcopy_internal(x, d))
    d[f] = g
    return g
end
Serialization.serialize(s::Serialization.AbstractSerializer, f::LatticeRHS) =
    invoke(Serialization.serialize, Tuple{Serialization.AbstractSerializer, Any}, s, _unowned(f, identity))

# A call from a task that does not own the build: the build itself once the task claims it
# (it has no owner, or its owner has ended), else the task's own copy, built once and kept in
# `copies`, found through a `WeakRef` in its task-local storage keyed by this build's `owner`
# vector (SX-37): a mutable key, whose identity is its address (the build itself is an
# immutable struct, whose `objectid` hashes its contents and allocates). The build holds the
# copy; the task holds only the weak reference, so a dropped build frees its copies. The
# lookup takes no lock and does not allocate; the copy has this build's type, so the call is
# not a dynamic one.
function _other_task(f::F, du, u, p, t) where {F <: LatticeRHS}
    tls = current_task().storage
    w = tls === nothing ? nothing : get(tls::IdDict{Any, Any}, f.owner, nothing)
    g = w === nothing ? nothing : (w::WeakRef).value
    g === nothing && (g = _for_task(f))
    g isa F && return (g::F)(du, u, p, t)
    return g(du, u, p, t)
end
function _for_task(f::LatticeRHS{L, W, E}) where {L, W, E}
    ct = current_task()
    return lock(f.lock) do
        o = f.owner[1]
        if o === nothing || (o isa Task && istaskdone(o))
            f.owner[1] = ct
            return f
        end
        g = get(f.copies, ct, nothing)
        g === nothing || return g
        filter!(kv -> !istaskdone(first(kv)), f.copies)
        g = _lattice_rhs(f.ctx, E, f.store; shared = :inputs)
        f.synced[1] === nothing || (g.synced[1] = :given)      # (the inputs are shared)
        g.owner[1] = ct
        f.copies[ct] = g
        task_local_storage(f.owner, WeakRef(g))
        return g
    end
end

function _variant(f::LatticeRHS, ::Type{C}) where {C}
    ctx = f.ctx
    v = get(f.variants, C, nothing)
    if v === nothing
        V = valtype(C)
        V <: Union{Float16, Float32} || Exec.supports(ctx.backend, Float64) || throw(ArgumentError(
            string("the solver passed values of type ", C, " (SciMLBase promotes u0 to the ",
                "parameters' value type for ForwardDiff); this backend has no Float64: ",
                "differentiate with respect to Float32 parameters (θ::Vector{Float32}) here")))
        _check_eltype(C, ctx.backend)
        v = _lattice_rhs(ctx, C, f.store)
        f.synced[1] === nothing || (v.synced[1] = :given)      # (the integer inputs are shared)
        v.owner[1] = f.owner[1]                  # the variant runs on its build's task
        f.variants[C] = v
        push!(f.order, C)
        if length(f.order) > MAX_VARIANTS
            delete!(f.variants, popfirst!(f.order))
        end
    else
        filter!(!=(C), f.order)
        push!(f.order, C)
    end
    return v
end

# the rate launches of element type `E` on a store of their own; `base` is another build's
# store, or `nothing` for the native build. From `base`, the integer inputs are shared and the
# float inputs copied; with `shared = :all` (a variant of the same task, called in turn with
# its build) the other integer arrays are shared too, with `shared = :inputs` (another
# task's copy) they are its own. Init kernels run at the first call (with that call's `p`),
# or here for the native build (`Pinit`).
const _PLANS_LOCK = ReentrantLock()
function _lattice_rhs(ctx::RHSContext, ::Type{E}, base, Pinit = nothing, inputs = ();
        shared::Symbol = :all) where {E}
    s, backend = ctx.program, ctx.backend
    ip, sp = lock(() -> _plans!(ctx.plans, s, ctx.initkeys, ctx.options, valtype(E), backend), _PLANS_LOCK)
    isempty(sp.swaps) || throw(ArgumentError("the ODE form has one buffer per field"))
    ids = Int[fieldid(s, k) for k in ctx.state]
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    marks = Dict{Int32, StateView}()
    for (k, i) in zip(ctx.state, ids)
        marks[Int32(i)] = StateView(slots[i], false)
        marks[fieldid(s, ctx.rates[k])] = StateView(slots[i], true)
    end
    st = FieldStore(backend, s; E, TE = _tabeltype(ctx.tables))
    for (k, v) in ctx.tables                   # in this build's value type, from the source
        settable!(st, s, k, v)
    end
    foreach(((k, v),) -> _set_input!(st, s, k, v), inputs)   # the native build's inputs
    if base !== nothing                        # share what the element type does not change
        for (i, f) in enumerate(s.fields)
            if !isfloat(f.storage)
                (shared === :all || f.role == :input) && (st.bufs[i] = base.bufs[i])
            elseif f.role == :input                # a float input, in this build's type
                st.bufs[i][1] .= base.bufs[i][1]
            end
        end
    end
    U = KA.allocate(backend, E, n)
    fill!(U, zero(E))
    dU = similar(U)
    c = zero(E)
    ls = map(Tuple(sp.launches)) do l
        # a table's id numbers the tables, not the fields: it is never a state slot (F1: a
        # table whose index equalled a state field's id was bound to the state)
        S0 = Tuple(Tuple(role === :table || !haskey(marks, id) ?
                         array(st, id, role, role == :table ? 0 : 1) : marks[id]
                   for (id, role) in lane) for lane in l.bind)
        S = map(lane -> map(a -> _resolve(a, U, dU), lane), S0)
        np = s.nparams
        P = launch_parameters(l.kernel, ntuple(_ -> zero(E), np), c)
        RHSLaunch(bind(backend, s, l, S, P, (0.0, 0.0); R = E), S0, derive_function(l.kernel),
            Val(np), c)
    end
    Exec.compile_all!(backend, [r.launch for r in ls])
    f = LatticeRHS{typeof(ls), typeof(each(length(ls))), E, typeof(ctx), typeof(ip)}(ls,
        each(length(ls)), ctx.faces, st, ctx, ip, Any[nothing], Float64[], Any[nothing], Float64[],
        Dict{Type, Any}(), Type[],
        Any[nothing], Dict{Task, Any}(), ReentrantLock(), Any[nothing], Int[0])
    isempty(inputs) || (f.synced[1] = :given)                # (the inputs given at the build)
    Pinit === nothing || isempty(ip.launches) || _init!(f, Pinit)
    return f
end

"""
    ODEAux(f, program)

The aux fields of an ODE problem as observed quantities (F3 design §3.12): `a(u, p, t, key)` is
aux field `key` at state `u`, parameters `p` and time `t`, `rhs(u, t)`, grid-shaped on the
problem's backend. One call of the right side `f` at `(u, p, t)` runs the aux kernels on the
store of the build this task runs (the rates it writes into a scratch `du` are dropped).
"""
struct ODEAux{F, P}
    f::F
    program::P
end
_build_eltype(::LatticeRHS{L, W, E}) where {L, W, E} = E
function (a::ODEAux)(u, p, t, key)
    f = a.f
    g = f.owner[1] === current_task() ? f : _for_task(f)
    C = _rhs_eltype(u, u, p, t)
    C === _build_eltype(g) || (g = _variant(g, C))
    du = similar(u)
    g(du, u, p, t)
    prog = a.program
    id = fieldid(prog, key)
    fd = prog.fields[id]
    d = leveldims(prog, fd.levels[1])
    return reshape(copy(array(g.store, id, :cur)), ncomp(fd) == 1 ? d : (d..., ncomp(fd)))
end

"""
    ode_problem(program, u0, tspan, p; state, rates, init = String[], index, tables = [],
                inputs = [], stability = p -> NaN, backend = CPU(), options = CompileOptions())

The `ODEProblem` of a field program in ODE form. `state` are the state field keys (flat
order), `rates[k]` the scratch field holding the rate of state field `k`; `init` kernels run
once (on the problem's store) before the problem is returned. `u0` is the flat host initial
state, `p` the raw parameter vector, both kept in their element types (P5 role model: the
eltype of `u0`, promoted with Dual `p`, decides the bodies' value type; an explicit
`options.T` that differs is refused). The `ODEFunction` carries `sys = index`, so solutions
and integrators index fields by symbol. `inputs` are `symbol => values` for every input field
(an unset one, or a parameter that is NaN, is an error here: an ODE problem has no `init`).
`stability` is the front end's stability bound, whose [`check_parameters`](@ref) runs here and
at every call of the right side with new parameter values (`remake`, `setp`): a refused value
is an error from `solve` or `step!`, never a run. With `steady = true` (a system with no time)
it is the `SteadyStateProblem` of the right side.
"""
function ode_problem(prog::Program, u0, tspan, p; state, rates, init = String[],
        index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[], inputs = Pair[], stability = p -> NaN,
        backend = KA.CPU(),
        options::CompileOptions = CompileOptions(), steady::Bool = false)
    faces = face_checks(prog)
    derive!(p, tables, index)                       # the computed slots (F2-15)
    check_faces(faces, p)
    check_values(p, index; built = false)
    s = semantic(prog)
    ins = resolve_inputs(s, index, inputs)
    check_inputs_set(ins; built = false, index)
    # the inputs are fixed here (the ODE path takes them at `discretize` only): the checks see
    # their values, so a rate that is not finite where they reach is refused now
    bks = bound_inputs(stability)
    binputs = Pair{String, Any}[k => _site_shaped(s, k, v) for (k, v) in ins if k in bks && v !== nothing]
    tabs = _table_list(tables)
    check_parameters(stability, with_tables(map(primal, collect(p)), tabs; inputs = binputs))
    N = _ndims(s)
    E = problem_eltype(u0, p, tabs)
    _check_eltype(E, backend)
    options = _state_options(options, E)
    ctx = RHSContext{N, typeof(backend)}(s, backend, collect(String, state),
        Dict{String, String}(rates), collect(String, init), options,
        tabs, faces, Float64(tspan[1]),
        Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}(), index, stability, binputs)
    ids = Int[fieldid(s, k) for k in state]
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    length(u0) == n || throw(ArgumentError("u0 has $(length(u0)) values; the state has $n"))
    pv = collect(p)
    f = _lattice_rhs(ctx, E, nothing, pv, ins)
    U = copyto!(KA.allocate(backend, E, n), convert(Vector{E}, collect(u0)))
    # aux fields `K ~ rhs` read as observed quantities (`sol[K]`, `integ[K]`: F3-00 review M1)
    index isa LatticeIndex && !isempty(index.aux) && (index.auxeval[] = ODEAux(f, s))
    index isa LatticeIndex && (index.program[] = s)          # (the checks of an input write)
    fun = SciMLBase.ODEFunction{true, SciMLBase.FullSpecialize}(f; sys = index)
    lp = LatticeParameters(pv, tabs, ins)
    # a system with no time (F3-12b): the steady state of the right side, for SciML's steady
    # solvers (`DynamicSS`, a nonlinear solver)
    steady && return SciMLBase.SteadyStateProblem(fun, U, lp)
    return SciMLBase.ODEProblem(fun, U, (Float64(tspan[1]), Float64(tspan[2])), lp)
end

# The problems built from a field program's ODE form (an ODEProblem whose right side is a
# `LatticeRHS`, a SteadyStateProblem of it, a NonlinearProblem of that, whose function wraps
# the right side and keeps its `sys`): a parameter map given to `remake` names parameters
# only. SciMLBase skips a key whose `parameter_index` is `nothing` (SII's answer for an
# expression such as `2k`), so `remake(o; p = [2k => 1.0])` would run with the old values; it
# is refused here (F1).

# `T` with the type parameter of its field `field` bounded by `S` (a parameter found by name,
# not by position)
function typewith(T::UnionAll, field::Symbol, S)
    U = T
    while U isa UnionAll
        U = U.body
    end
    j = findfirst(x -> x === fieldtype(U, field), U.parameters)
    vars = Any[TypeVar(Symbol(:P, i)) for i in 1:(j - 1)]
    push!(vars, TypeVar(:F, S))
    body = T{vars...}
    for v in reverse(vars)
        body = UnionAll(v, body)
    end
    return body
end
const LatticeODEFunction = SciMLBase.ODEFunction{<:Any, <:Any, <:LatticeRHS}
const LatticeODEProblem = SciMLBase.ODEProblem{<:Any, <:Any, <:Any, <:Any, <:LatticeODEFunction, <:Any,
                                               SciMLBase.StandardODEProblem}
const LatticeSteadyStateProblem = typewith(SciMLBase.SteadyStateProblem, :f, LatticeODEFunction)
const LatticeNonlinearProblem = typewith(SciMLBase.NonlinearProblem, :f,
                                          typewith(SciMLBase.NonlinearFunction, :sys, LatticeIndex))
const LatticeSciMLProblem = Union{LatticeODEProblem, LatticeSteadyStateProblem, LatticeNonlinearProblem}

# The parameters of a remake of a lattice problem (F4-00): `p` a `LatticeParameters`, a vector
# of every scalar parameter, or a map whose keys name scalar parameters, whole tables (`Dk =>
# values`) and inputs (`kind => K`); `inputs` more input pairs. Every key names a parameter (a
# typo, an expression or a computed parameter is refused, F1), each write is checked (a
# declared bound, finite table values, one input value per site) and the computed slots
# follow (F2-15). A plain value is written into the parameter type, a Dual promotes it.
# `missing`: the problem's own object.
function remake_params(prob, p, inputs = ())
    lp = prob.p
    lp isa LatticeParameters || return p
    ix = SII.symbolic_container(prob.f)
    p === missing && isempty(inputs) && return missing
    q = if p === missing
        copy(lp)
    elseif p isa LatticeParameters
        p
    elseif p isa AbstractVector{<:Real}
        length(p) == length(lp.values) ||
            throw(ArgumentError("`p` has $(length(p)) values; the problem has $(length(lp.values)) parameters"))
        with_values(lp, collect(p))
    elseif p isa AbstractDict || (p isa Union{AbstractVector, Tuple} && all(x -> x isa Pair, p))
        _params_from_map(lp, ix, p)
    else
        throw(ArgumentError(string("`p` is a `LatticeParameters`, a vector of every parameter or `parameter => value` ",
            "pairs; got a ", typeof(p))))
    end
    for (s, v) in inputs
        SII.set_parameter!(q, v, InputSlot(_input_of(ix, s, q), ix))
    end
    ix isa LatticeIndex || return q
    derive!(q.values, q.tables, ix)                    # the computed slots follow (F2-15)
    check_bounds(q.values, ix)                         # a declared bound, at the write (F2-14)
    return q
end
# the input key of `s` among the inputs of `q`, else an error listing them
function _input_of(ix, s, q::LatticeParameters)
    k = ix isa LatticeIndex && !(s isa Union{AbstractArray, Tuple, Integer}) ? input_key(ix, s) : nothing
    k === nothing && s isa AbstractString && any(x -> first(x) == s, q.inputs) && (k = String(s))
    k === nothing && _not_input(s, [input_name(ix, first(x)) for x in q.inputs])
    return k
end
function _params_from_map(lp::LatticeParameters, ix, p)
    ix isa LatticeIndex && check_parameter_keys(ix, (first(x) for x in p))
    T = foldl((T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) : T, p; init = eltype(lp.values))
    q = with_values(lp, Vector{T}(lp.values))
    # a whole table of a wider type (BigFloat values for Float64 defaults) widens the tables
    TT0 = _tabeltype(lp.tables)
    TT = foldl((S, x) -> SII.parameter_index(ix, first(x)) isa TableSlot && last(x) isa Union{AbstractArray, Tuple} ?
                         promote_type(S, _tabelt(collect(last(x)))) : S, p; init = TT0)
    TT === TT0 || (q = LatticeParameters(q.values, Pair{String, Vector{TT}}[k => Vector{TT}(v) for (k, v) in q.tables],
        q.inputs; tick = q.tick[]))
    for (k, v) in p
        i = SII.parameter_index(ix, k)
        if i isa TableSlot
            i.entry == 0 || throw(ArgumentError(string("`", _symtext(k), "` is entry ", i.entry, " of the table `", i.key,
                "`: give the whole table, `", i.key, " => values`")))
            SII.set_parameter!(q, v, i)
        elseif i isa InputSlot
            SII.set_parameter!(q, v, i)
        else
            q.values[i] = v
        end
    end
    return q
end
# `u0` of a remake: a flat state, or `field => values` pairs (a number or one value per site)
# over the problem's state, on its backend; a Dual value promotes the state
function remake_u0(prob, u0)
    u0 isa Union{AbstractVector{<:Pair}, Tuple, AbstractDict} && !isempty(u0) || return u0
    ix = SII.symbolic_container(prob.f)
    all(x -> x isa Pair, u0) || throw(ArgumentError("`u0` is a flat vector of the state or `field => values` pairs"))
    E = foldl((T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) :
                        last(x) isa AbstractArray ? promote_dual(T, eltype(last(x))) : T, u0; init = eltype(prob.u0))
    out = Vector{E}(Array(prob.u0))
    for (k, v) in u0
        slot = ix isa LatticeIndex ? _slot(ix, k) : nothing
        slot === nothing && throw(ArgumentError(string("`u0`: `", _symtext(k), "` is not a field of the state",
            ix isa LatticeIndex ? string("; its fields: ", join(("`$(_symtext(f))`" for f in ix.varsyms), ", ")) : "")))
        if v isa Real
            out[slot.range] .= v
        elseif v isa AbstractArray && length(v) == length(slot.range)
            out[slot.range] .= vec(collect(v))
        else
            throw(ArgumentError(string("`u0`: give `", _symtext(k), "` one value per site (", length(slot.range),
                ") or a number; got ", v isa AbstractArray ? "$(length(v)) values" : repr(v))))
        end
    end
    return copyto!(similar(prob.u0, E), out)
end
function SciMLBase.remake(prob::LatticeODEProblem; p = missing, u0 = missing, inputs = (), kw...)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.ODEProblem}, prob; p = remake_params(prob, p, inputs),
        u0 = remake_u0(prob, u0), kw...)
end
function SciMLBase.remake(prob::LatticeSteadyStateProblem; p = missing, u0 = missing, inputs = (), kw...)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.SteadyStateProblem}, prob; p = remake_params(prob, p, inputs),
        u0 = remake_u0(prob, u0), kw...)
end
function SciMLBase.remake(prob::LatticeNonlinearProblem; p = missing, u0 = missing, inputs = (), kw...)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.NonlinearProblem}, prob; p = remake_params(prob, p, inputs),
        u0 = remake_u0(prob, u0), kw...)
end

# `setp` of a symbol that is no parameter names it (SII: "invalid index: nothing")
function check_setp(sys, sym)
    # (a resolved index: SII's setter of an array symbol calls `setp` again with its index)
    sym isa Union{TableSlot, InputSlot, Integer} && return nothing
    ix = SII.symbolic_container(sys isa Union{FieldProblem, FieldIntegrator} ? sys : sys.f)
    ix isa LatticeIndex && !(sym isa Union{AbstractArray, Tuple}) && check_parameter_keys(ix, (sym,))
    # an owned problem holds its tables and inputs as given: `remake` gives new ones
    if sys isa FieldProblem && ix isa LatticeIndex
        t = table_key(ix, sym)
        t === nothing || throw(ArgumentError(string("`", t, "` is a table (an array parameter) of an owned problem: ",
            "`remake(prob; p = [", t, " => values])` gives it new values, and on its integrator `integ.ps[", t, "] = values`")))
        k = sym isa Union{AbstractArray, Tuple, Integer} ? nothing : input_key(ix, sym)
        k === nothing || throw(ArgumentError(string("`", input_name(ix, k), "` is an input of an owned problem: ",
            "`remake(prob; inputs = [", _route(input_name(ix, k)), " => values])` gives it new values, and on its integrator ",
            "`integ.ps[", input_name(ix, k), "] = values`")))
    end
    return nothing
end
function SII.setp(sys::Union{FieldProblem, FieldIntegrator, LatticeSciMLProblem}, sym; kw...)
    # a table (or an entry of one) of an integrator: its write, with the checks (`integ.ps[Dk] = values`)
    if sys isa FieldIntegrator && sys.prob.index isa LatticeIndex && table_key(sys.prob.index, sym) !== nothing
        return (i, v) -> (_write_table!(i, v, sym); v)
    end
    # an input of an integrator: the input write (`integ.ps[kind] = K` is `integ[kind] = K`)
    if sys isa FieldIntegrator && sys.prob.index isa LatticeIndex && !(sym isa Union{AbstractArray, Tuple, Integer}) &&
       input_key(sys.prob.index, sym) !== nothing
        return (i, v) -> (i[sym] = v; v)
    end
    check_setp(sys, sym)
    return invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
end

# A field solver or a linear solver given to an `ODEProblem` (the `:ode` path): the route to
# an OrdinaryDiffEq solver, or to the owned problem that the field solvers step
function _ode_refusal(alg)
    name = alg isa LinearSolver ? string("`", repr(alg), "` is a linear solver, the `inner` of an implicit field solver") :
           string("`", _algtext(alg), "` is a field solver: it steps a `FieldProblem`")
    own = alg isa LinearSolver ? string("`solve(prob, BackwardEuler(; dt, inner = ", repr(alg), "))`") :
          string("`solve(prob, ", _algtext(alg), ")`")
    return ArgumentError(string("`solve`/`init` of an `ODEProblem`: ", name, ". An `ODEProblem` takes an OrdinaryDiffEq ",
        "solver (`ImplicitEuler()` is Backward Euler); or discretize with `LatticeDiscretization(…; problem = :owned)` ",
        "and give ", own))
end
CommonSolve.solve(::SciMLBase.AbstractODEProblem, alg::Union{FieldAlgorithm, LinearSolver}; kw...) = throw(_ode_refusal(alg))
CommonSolve.init(::SciMLBase.AbstractODEProblem, alg::Union{FieldAlgorithm, LinearSolver}; kw...) = throw(_ode_refusal(alg))
