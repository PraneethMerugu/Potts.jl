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
    P = r.derive(ntuple(i -> p[i], r.np), r.c, t)
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
    tables::Vector{Pair{String, Vector{Float64}}}
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
end
_rhs_eltype(du, u, p, t) = promote_dual(promote_dual(promote_type(eltype(u), eltype(du)), eltype(p)), typeof(t))
function (f::LatticeRHS{L, W, E})(du, u, p, t) where {L, W, E}
    f.owner[1] === current_task() || return _other_task(f, du, u, p, t)
    degenerate_face(f.faces, p) == 0 || check_faces(f.faces, p)
    C = _rhs_eltype(du, u, p, t)
    C === E || return _variant(f, C)(du, u, p, t)
    _checked(f, p) || _check!(f, p)
    isempty(f.init.launches) || _same_params(f, p) || _init!(f, p)
    f.walk(f.launches, (du, u, p, t))
    return nothing
end

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
    check_values(p, f.ctx.index)
    check_parameters(f.ctx.stability, with_tables(map(primal, p), f.ctx.tables; inputs = f.ctx.binputs))
    f.checkp[1] = p
    resize!(f.checkv, length(p))
    f.checkv .= [Float64(primal(x)) for x in p]
    return nothing
end

# A deep copy (SciML's `safetycopy` of an ensemble's problem) is a new build: it has no owner
# and its own lock. Serializing writes the same: a build with no owner (a running task does
# not serialize), which the task that first calls the deserialized function claims.
_unowned(f::LatticeRHS, val) = typeof(f)(map(fieldnames(typeof(f))) do k
    k === :owner ? Any[nothing] : k === :copies ? Dict{Task, Any}() : k === :lock ? ReentrantLock() :
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
    st = FieldStore(backend, s; E)
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
        Any[nothing], Dict{Task, Any}(), ReentrantLock())
    Pinit === nothing || isempty(ip.launches) || _init!(f, Pinit)
    return f
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
is an error from `solve` or `step!`, never a run.
"""
function ode_problem(prog::Program, u0, tspan, p; state, rates, init = String[],
        index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[], inputs = Pair[], stability = p -> NaN,
        backend = KA.CPU(),
        options::CompileOptions = CompileOptions())
    faces = face_checks(prog)
    check_faces(faces, p)
    check_values(p, index; built = false)
    s = semantic(prog)
    ins = resolve_inputs(s, index, inputs)
    check_inputs_set(ins; built = false, index)
    # the inputs are fixed here (the ODE path takes them at `discretize` only): the checks see
    # their values, so a rate that is not finite where they reach is refused now
    bks = bound_inputs(stability)
    binputs = Pair{String, Any}[k => _site_shaped(s, k, v) for (k, v) in ins if k in bks && v !== nothing]
    check_parameters(stability, with_tables(map(primal, collect(p)), Pair{String, Vector{Float64}}[tables...]; inputs = binputs))
    N = _ndims(s)
    E = problem_eltype(u0, p)
    _check_eltype(E, backend)
    options = _state_options(options, E)
    ctx = RHSContext{N, typeof(backend)}(s, backend, collect(String, state),
        Dict{String, String}(rates), collect(String, init), options,
        Pair{String, Vector{Float64}}[tables...], faces, Float64(tspan[1]),
        Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}(), index, stability, binputs)
    ids = Int[fieldid(s, k) for k in state]
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    length(u0) == n || throw(ArgumentError("u0 has $(length(u0)) values; the state has $n"))
    pv = collect(p)
    f = _lattice_rhs(ctx, E, nothing, pv, ins)
    U = copyto!(KA.allocate(backend, E, n), convert(Vector{E}, collect(u0)))
    fun = SciMLBase.ODEFunction{true, SciMLBase.FullSpecialize}(f; sys = index)
    return SciMLBase.ODEProblem(fun, U, (Float64(tspan[1]), Float64(tspan[2])), pv)
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

# a parameter map's keys (a vector or tuple of pairs, `Any[...]` too, or a dict); an untyped
# vector of pairs is passed on as a vector of pairs (SciMLBase reads a map by its eltype)
function _check_map_keys(prob, p)
    ix = SII.symbolic_container(prob.f)
    ix isa LatticeIndex || return p
    ismap = p isa AbstractDict || (p isa Union{AbstractVector, Tuple} && !isempty(p) && all(x -> x isa Pair, p))
    ismap || return p
    check_parameter_keys(ix, (first(x) for x in p))
    return p isa AbstractVector && !(eltype(p) <: Pair) ? Pair[x for x in p] : p
end
function SciMLBase.remake(prob::LatticeODEProblem; p = missing, kw...)
    p = _check_map_keys(prob, p)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.ODEProblem}, prob; p, kw...)
end
function SciMLBase.remake(prob::LatticeSteadyStateProblem; p = missing, kw...)
    p = _check_map_keys(prob, p)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.SteadyStateProblem}, prob; p, kw...)
end
function SciMLBase.remake(prob::LatticeNonlinearProblem; p = missing, kw...)
    p = _check_map_keys(prob, p)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.NonlinearProblem}, prob; p, kw...)
end

# `setp` of a symbol that is no parameter names it (SII: "invalid index: nothing")
function check_setp(sys, sym)
    ix = SII.symbolic_container(sys isa Union{FieldProblem, FieldIntegrator} ? sys : sys.f)
    ix isa LatticeIndex && !(sym isa Union{AbstractArray, Tuple}) && check_parameter_keys(ix, (sym,))
    return nothing
end
function SII.setp(sys::Union{FieldProblem, FieldIntegrator, LatticeSciMLProblem}, sym; kw...)
    check_setp(sys, sym)
    return invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
end
