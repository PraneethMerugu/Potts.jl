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
    variants::Dict{Type, Any}                  # element type → LatticeRHS (bounded, LRU)
    order::Vector{Type}
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
end
_rhs_eltype(du, u, p, t) = promote_dual(promote_dual(promote_type(eltype(u), eltype(du)), eltype(p)), typeof(t))
function (f::LatticeRHS{L, W, E})(du, u, p, t) where {L, W, E}
    degenerate_face(f.faces, p) == 0 || check_faces(f.faces, p)
    C = _rhs_eltype(du, u, p, t)
    C === E || return _variant(f, C)(du, u, p, t)
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

function _variant(f::LatticeRHS, ::Type{C}) where {C}
    ctx = f.ctx
    v = get(ctx.variants, C, nothing)
    if v === nothing
        V = valtype(C)
        V <: Union{Float16, Float32} || Exec.supports_float64(ctx.backend) || throw(ArgumentError(
            string("the solver passed values of type ", C, " (SciMLBase promotes u0 to the ",
                "parameters' value type for ForwardDiff); this backend has no Float64: ",
                "differentiate with respect to Float32 parameters (θ::Vector{Float32}) here")))
        _check_eltype(C, ctx.backend)
        v = _lattice_rhs(ctx, C, f.store)
        ctx.variants[C] = v
        push!(ctx.order, C)
        if length(ctx.order) > MAX_VARIANTS
            delete!(ctx.variants, popfirst!(ctx.order))
        end
    else
        filter!(!=(C), ctx.order)
        push!(ctx.order, C)
    end
    return v
end

# the rate launches of element type `E` on a store of their own; `base` is the native
# build's store (its integer inputs are shared), or `nothing` for the native build. Init
# kernels run at the first call (with that call's `p`), or here for the native build
# (`Pinit`).
function _lattice_rhs(ctx::RHSContext, ::Type{E}, base, Pinit = nothing) where {E}
    s, backend = ctx.program, ctx.backend
    ip, sp = _plans!(ctx.plans, s, ctx.initkeys, ctx.options, valtype(E), backend)
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
    if base !== nothing                        # share what the element type does not change
        for (i, f) in enumerate(s.fields)
            isfloat(f.storage) || (st.bufs[i] = base.bufs[i])
        end
    end
    U = KA.allocate(backend, E, n)
    fill!(U, zero(E))
    dU = similar(U)
    c = zero(E)
    ls = map(Tuple(sp.launches)) do l
        S0 = Tuple(Tuple(get(marks, id, nothing) === nothing ?
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
        each(length(ls)), ctx.faces, st, ctx, ip, Any[nothing], Float64[])
    Pinit === nothing || isempty(ip.launches) || _init!(f, Pinit)
    return f
end

"""
    ode_problem(program, u0, tspan, p; state, rates, init = String[], index, tables = [],
                backend = CPU(), options = CompileOptions())

The `ODEProblem` of a field program in ODE form. `state` are the state field keys (flat
order), `rates[k]` the scratch field holding the rate of state field `k`; `init` kernels run
once (on the problem's store) before the problem is returned. `u0` is the flat host initial
state, `p` the raw parameter vector, both kept in their element types (P5 role model: the
eltype of `u0`, promoted with Dual `p`, decides the bodies' value type; an explicit
`options.T` that differs is refused). The `ODEFunction` carries `sys = index`, so solutions
and integrators index fields by symbol.
"""
function ode_problem(prog::Program, u0, tspan, p; state, rates, init = String[],
        index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[], backend = KA.CPU(),
        options::CompileOptions = CompileOptions())
    faces = face_checks(prog)
    check_faces(faces, p)
    s = semantic(prog)
    N = _ndims(s)
    E = problem_eltype(u0, p)
    _check_eltype(E, backend)
    options = _state_options(options, E)
    ctx = RHSContext{N, typeof(backend)}(s, backend, collect(String, state),
        Dict{String, String}(rates), collect(String, init), options,
        Pair{String, Vector{Float64}}[tables...], faces, Float64(tspan[1]),
        Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}(), Dict{Type, Any}(), Type[])
    ids = Int[fieldid(s, k) for k in state]
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    length(u0) == n || throw(ArgumentError("u0 has $(length(u0)) values; the state has $n"))
    pv = collect(p)
    f = _lattice_rhs(ctx, E, nothing, pv)
    U = copyto!(KA.allocate(backend, E, n), convert(Vector{E}, collect(u0)))
    fun = SciMLBase.ODEFunction{true, SciMLBase.FullSpecialize}(f; sys = index)
    return SciMLBase.ODEProblem(fun, U, (Float64(tspan[1]), Float64(tspan[2])), pv)
end
