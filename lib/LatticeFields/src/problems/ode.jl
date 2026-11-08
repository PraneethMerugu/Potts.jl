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
    du, u, p, t, k = args
    S = map(lane -> map(a -> _resolve(a, u, du), lane), r.S0)
    P = r.derive(ntuple(i -> p[i], r.np), r.c, t, k)      # (`k`: the clock's step index, or nothing)
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
    steady::Vector{String}                     # the steady rows' fields (`0 ~ rhs`, F4-02)
    moving::Bool                               # the init kernels read the time or the clock: run at every call
end
const MAX_VARIANTS = 8

"""
    LatticeMetadata

The discretization metadata of a problem `discretize` returns (F4 design §3.2): the owned
problem built at `discretize` (its group, plans and checks, at the values given there), the
family (`:ode` or `:map`), and the right side of SciML's solvers, built at its first call
(`builds` counts the builds: an owned solve builds none). It is the `problem_type` of an
`ODEProblem` and is held by the problem's function ([`LatticeFunction`](@ref)) in every
family. A `remake` keeps it, so the plans stay warm.
"""
struct LatticeMetadata{P <: FieldProblem} <: SciMLBase.AbstractDiscretizationMetadata{Val(false)}
    problem::P
    family::Symbol
    rhs::Base.RefValue{Any}
    builds::Base.RefValue{Int}
    lock::ReentrantLock
    sem::Base.RefValue{Any}                    # the semantic program of the right side (built once)
    plans::Any                                 # its init and step plans per value type (shared by the masks of `u0`)
end
LatticeMetadata(fp::FieldProblem{N}) where {N} = LatticeMetadata(fp, fp.kind == :map ? :map : :ode, Ref{Any}(nothing),
    Ref(0), ReentrantLock(), Ref{Any}(nothing), Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}())
_sem(m::LatticeMetadata) = (m.sem[] === nothing && (m.sem[] = semantic(m.problem.group.spec.rate)); m.sem[]::Program)
# the compile options of the right side: the launches write the step index into the clock's slot
function _rhs_options(fp::FieldProblem)
    o = fp.options
    return CompileOptions(o.T, o.I, o.float64_ok, o.debug, o.index, o.lanes, clock_slot(fp.group.spec), o.S, o.declared)
end
# a solution of SciML's solvers is returned as it is (no eager `PDENoTimeSolution`)
SciMLBase.wrap_sol(sol, ::LatticeMetadata) = sol

"""
    steady_start!(u, prob, p, t) -> u

The default start of a problem with steady rows `0 ~ rhs` on an OrdinaryDiffEq solver (its
`DefaultInit`; review R2): the steady fields of `u` are solved at `t` from the other fields of
`u`, by the owned `QuasiSteady` solve of those rows on the lattice (sparse: the operator of the
rows, `DevicePCG` to `rtol = 1e-10`), so the solver starts on the algebraic constraint. The
other fields are kept. `initializealg = BrownFullBasicInit()` or `CheckInit()` given to `solve`
takes the place of this.
"""
function steady_start!(u, prob, p, t)
    m = lattice_metadata(prob)
    fp = m.problem
    st = fp.group.spec.steady
    isempty(st) && return u
    _check_backend(fp.backend, u, "u0")
    span = prob.tspan
    δ = 1e-6 * max(abs(span[2] - span[1]), eps())
    τ = fp.group.spec.clock                       # (a window divides the clock's period)
    τ === nothing || (δ = τ / ceil(τ / δ))
    g = _field_problem(fp.program, fp.state, u isa Vector ? copy(u) : Array(u), (Float64(primal(t)), Float64(primal(t)) + δ),
        collect(p.values), p.tables, p.inputs, fp.backend, fp.index, fp.faces, fp.stability, fp.kind, fp.initkeys,
        fp.options, fp.group)
    inner = Solvers.DevicePCG(; rtol = 1e-10, budget = 400)
    alg = FieldGroups((k => QuasiSteady(; dt = δ, inner) for k in st)...; default = ExplicitEuler(; dt = δ))
    ig = CommonSolve.init(g, alg; save_start = false)
    CommonSolve.step!(ig)          # (the steady rows are solved first, from the fields at `t`)
    s = fp.program
    slots = state_layout(s, Int[fieldid(s, k) for k in fp.state])
    for k in st
        copyto!(view(u, slots[fieldid(s, k)]), vec(ig[Symbol(k)]))
    end
    return u
end

"""
    LatticeFunction(meta)

The function of a problem `discretize` returns: `f(du, u, p, t)` is the right side of the
rates (an `ODEFunction`) or the next state of a map (a `DiscreteFunction`), built from
`meta` ([`LatticeMetadata`](@ref)) at its first call, so a problem that only field algorithms
step never builds it. A call with a `Float64` time allocates nothing once built.
"""
struct LatticeFunction{M}
    meta::M
end
function (f::LatticeFunction)(du, u, p, t)
    g = _built(f.meta, u, p, t)
    t isa Float64 || return _call_any(g, du, u, p, t)
    # the build this task runs, its time cell set, then a call with no unboxed argument (a
    # call of the `Any`-typed build boxes a Float64 time, 16 bytes, and a function that
    # returns the build boxes the build, about 600 bytes): every step here reads `Any` values
    o = getfield(g, :owner)::Vector{Any}
    h = o[1] === current_task() ? g : _task_copy_any(g, o)
    (getfield(h, :tcell)::Base.RefValue{Float64})[] = t
    _call_cell(h, du, u, p)
    return nothing
end
# the copy of the build `g` (owner vector `o`) for this task, found in the task-local storage
# as an `Any` (no boxing), else built
function _task_copy_any(g, o::Vector{Any})
    tls = current_task().storage
    w = tls === nothing ? nothing : get(tls::IdDict{Any, Any}, o, nothing)
    h = w === nothing ? nothing : (w::WeakRef).value
    return h === nothing ? Base.inferencebarrier(_for_task)(g) : h
end
_call_any(g, du, u, p, t) = g(du, u, p, t)
_call_cell(h, du, u, p) = h(du, u, p, h.tcell[])
_task_rhs(g) = g.owner[1] === current_task() ? g : _task_copy(g)
function _task_copy(f)
    tls = current_task().storage
    w = tls === nothing ? nothing : get(tls::IdDict{Any, Any}, f.owner, nothing)
    g = w === nothing ? nothing : (w::WeakRef).value
    return g === nothing ? _for_task(f) : g
end

"""
    lattice_metadata(prob) -> LatticeMetadata or nothing

The metadata of a problem `discretize` returned (in any family), else `nothing`.
"""
lattice_metadata(prob) = prob isa SciMLBase.LinearProblem ? _lmeta(prob.A) : hasproperty(prob, :f) ? _lmeta(prob.f) : nothing
_lmeta(f::LatticeFunction) = f.meta
_lmeta(f::SciMLBase.AbstractSciMLFunction) = _lmeta(f.f)
_lmeta(f) = nothing

"""
    rhs_build(prob) -> LatticeRHS

The right side SciML's solvers call for `prob` (a problem `discretize` returned), built now if
it was not yet; `nothing` for a problem with no field groups.
"""
function rhs_build(prob)
    m = lattice_metadata(prob)
    m === nothing && return prob.f.f isa LatticeRHS ? prob.f.f : nothing
    return _built(m, prob.u0, prob.p, prob.tspan[1])
end

# the right side of `m`, built once (under its lock) for the element type of the first call
function _built(m::LatticeMetadata, u, p, t)
    g = m.rhs[]
    g === nothing || return g
    return lock(m.lock) do
        m.rhs[] === nothing || return m.rhs[]
        m.rhs[] = _build_rhs(m, u, p, t)
        m.builds[] += 1
        return m.rhs[]
    end
end
function _build_rhs(m::LatticeMetadata, u, p, t)
    fp = m.problem
    _check_backend(fp.backend, u, "the solver's state")
    s = _sem(m)
    rates = m.family == :map ? Dict{String, String}() : Dict{String, String}(k => "∂$k" for k in fp.state)
    N = _ndims(s)
    # the launches write the step index `p.tick` into the clock's slot (F4-02); the init
    # kernels run at every call when they read the time or the clock (`moving`)
    ctx = RHSContext{N, typeof(fp.backend)}(s, fp.backend, copy(fp.state), rates, copy(fp.initkeys), _rhs_options(fp),
        fp.tables, fp.faces, fp.tspan[1], m.plans, fp.index, fp.stability,
        Pair{String, Any}[], copy(fp.group.spec.steady), _masks_moving(fp.program, fp.group.spec))
    E = _rhs_eltype(u, u, p, t)
    _check_eltype(E, fp.backend)
    for k in fp.state                            # the solver's state is one vector of the state type
        f = s.fields[fieldid(s, k)]
        f.fixed && juliatype(f.storage) !== valtype(E) && throw(ArgumentError(string("field `", k,
            "`: `lattice_storage = ", juliatype(f.storage), "` differs from the state's number type ", valtype(E),
            "; an OrdinaryDiffEq solver's state is one vector of that type, so its fields are stored in it. Discretize ",
            "with T = ", juliatype(f.storage), ", or solve with a field algorithm (each field stored in its own type)")))
    end
    return _lattice_rhs(ctx, E, nothing)
end
# an array on another backend than the problem's is refused, naming both (SX-12)
function _check_backend(backend, u, what)
    u isa AbstractArray || return nothing
    b = KA.get_backend(u)
    typeof(b) == typeof(backend) || throw(ArgumentError(string(what, " is on the backend ", nameof(typeof(b)),
        "; the problem's backend is ", nameof(typeof(backend)), ": give the values on ", nameof(typeof(backend)),
        " (`copyto!` into an array of that backend)")))
    return nothing
end

"""
    lattice_problem(fp::FieldProblem) -> SciML problem

The SciML problem of the owned problem `fp` (F4 design §3.2): an `ODEProblem` for rates (with
a `mass_matrix` when it has steady rows), a `DiscreteProblem` for maps, and for a system with no
time a `LinearProblem` (every row linear: `A` a [`LatticeOperator`](@ref), `b` the constant
part) or a `NonlinearProblem` of the right side. `p` is a [`LatticeParameters`](@ref), the
state is on `fp`'s backend and the function a [`LatticeFunction`](@ref) whose metadata holds
`fp`. The built-in callbacks (the clock's step index, [`ClockTick`](@ref); the masks,
[`MaskSync`](@ref)) are in the problem's keywords, so every OrdinaryDiffEq solve runs them.

The Jacobian keywords (F4-07; F4 design §3.7) set the `ODEFunction`'s (and a nonlinear
system's `NonlinearFunction`'s) Jacobian fields:

- `jvp = true` (the default): `jvp` is a [`LatticeJVP`](@ref), one Dual evaluation of the right
  side, which Krylov linear solvers use; on a device it is also the `jac_prototype`, a
  matrix-free [`JacobianOperator`](@ref) (ruling Q7);
- `sparse = true`: `jac_prototype` is the sparse pattern of [`jacobian_sparsity`](@ref) with
  its diagonal, and `colorvec` a distance-2 coloring of it ([`column_colors`](@ref)), so
  OrdinaryDiffEq forms the Jacobian with one colored evaluation per color (host only);
- `jac = true`: `jac` is a [`LatticeJacobian`](@ref), the colored Dual Jacobian (host only).

A map's problem has no Jacobian; a linear system with no time keeps its operator (its
matrix is `lattice_matrix(prob.A)`).
"""
function lattice_problem(fp::FieldProblem; jac::Bool = false, sparse::Bool = false, jvp::Bool = true)
    meta = LatticeMetadata(fp)
    f = LatticeFunction(meta)
    ix = fp.index
    ix isa LatticeIndex && !isempty(ix.aux) && (ix.auxeval[] = ODEAux(f, fp.program))
    lp = LatticeParameters(copy(fp.p), fp.tables, fp.inputs)
    E = problem_eltype(fp.u0, fp.p, lp.tables)          # (a Dual `u0` or parameter promotes the state)
    U = copyto!(KA.allocate(fp.backend, E, length(fp.u0)), convert(Vector{E}, fp.u0))
    _clamp_masks!(U, meta, lp)                           # `prob.u0` holds the masked values (review 2)
    meta.family == :map && (jac || sparse) && throw(ArgumentError(string("`", jac ? "jac" : "sparse",
        " = true`: a map `Shift(t, 1)(m) ~ rhs` gives a `DiscreteProblem`, which has no Jacobian")))
    fp.group.spec.timefree && return _timefree_problem(meta, f, U, lp; jac, sparse, jvp)
    cbs = _builtin_callbacks(fp)
    kw = isempty(cbs) ? (;) : (; callback = SciMLBase.CallbackSet(cbs...))
    if meta.family == :map
        return SciMLBase.DiscreteProblem(SciMLBase.DiscreteFunction{true}(f; sys = ix), U, fp.tspan, lp; kw...)
    end
    M = _mass_matrix(fp, E)
    jkw = _jacobian_kw(meta, U, lp; jac, sparse, jvp)
    fun = M === LinearAlgebra.I ? SciMLBase.ODEFunction{true, SciMLBase.FullSpecialize}(f; sys = ix, jkw...) :
          SciMLBase.ODEFunction{true, SciMLBase.FullSpecialize}(f; sys = ix, mass_matrix = M, jkw...)
    return SciMLBase.ODEProblem(fun, U, fp.tspan, lp, meta; kw...)
end

# The mass matrix of the steady rows `0 ~ rhs` (F4-02; F4 design §3.6): `Diagonal(m)` with
# `m = 0` on the steady fields' slots (a masked site of one is the row `0 = v - u`, so it
# stays regular), or `I` when there is none
function _mass_matrix(fp::FieldProblem, ::Type{E}) where {E}
    st = fp.group.spec.steady
    isempty(st) && return LinearAlgebra.I
    s = fp.program
    slots = state_layout(s, Int[fieldid(s, k) for k in fp.state])
    m = ones(valtype(E), length(fp.u0))
    for k in fp.state
        k in st && (m[slots[fieldid(s, k)]] .= 0)
    end
    return LinearAlgebra.Diagonal(copyto!(KA.allocate(fp.backend, valtype(E), length(m)), m))
end

# the built-in callbacks of `fp`'s SciML problem: the clock's step index when the group reads
# it, and the masks when a state field has one
function _builtin_callbacks(fp::FieldProblem)
    cbs = Any[]
    clock_slot(fp.group.spec) == 0 || fp.group.spec.clock === nothing ||
        push!(cbs, ClockTick(fp.group.spec.clock))
    ix = fp.index
    if _has_masks(fp) && fp.kind != :map
        moving = _masks_moving(fp.program, fp.group.spec)
        push!(cbs, MaskSync(moving, moving && ix isa LatticeIndex && ix.maskunlocated))
        # each located switch of a moving mask set: a continuous callback at its root
        moving && ix isa LatticeIndex && foreach(f -> push!(cbs, MaskEvent(f)), ix.maskevents)
    end
    return Any[_callback(c) for c in cbs]
end
_has_masks(fp::FieldProblem) = (s = fp.program; ids = Int[fieldid(s, k) for k in fp.state];
                                any(r -> r isa NodeValueRule && r.field in ids, s.rules))

# the affect of a built-in callback (the clock, the masks: the ODE path's), marked so that an
# owned solve, which steps them itself, leaves them out of the problem's callbacks (F4-05)
struct _Builtin{F} <: Function
    f::F
end
(b::_Builtin)(integ) = b.f(integ)
_builtin(cb) = cb isa Union{SciMLBase.DiscreteCallback, SciMLBase.ContinuousCallback} && cb.affect! isa _Builtin

"""
    ClockTick(τ)

The built-in callback of the clock's step index on an OrdinaryDiffEq solve (F4-02; F4 design
§3.6): at `init` it sets `p.tick` to 0 and adds a `tstop` at every boundary `t₀ + kτ` of the
time span, and at each boundary it sets `p.tick = k`, so the solver lands on every boundary and
reads `step_index(t)` as the owned steppers do (the right side has one value per period). A
new step index is a discrete event: every masked site takes its value again (a value that reads
`step_index(t)` jumps; its rate `∂v/∂t` cannot carry the jump).
"""
struct ClockTick
    τ::Float64
end
_ticks(c::ClockTick, integ, t) = floor(Int, (t - integ.sol.prob.tspan[1]) / c.τ + 1e-9)
function _callback(c::ClockTick)
    cond(u, t, integ) = _ticks(c, integ, t) != integ.p.tick[]
    affect!(integ) = (integ.p.tick[] = _ticks(c, integ, integ.t); sync_masks!(integ); nothing)
    function start(cb, u, t, integ)
        integ.p.tick[] = 0
        t1 = integ.sol.prob.tspan[2]
        k = 1
        while t + k * c.τ < t1 - 1e-12 * c.τ
            SciMLBase.add_tstop!(integ, t + k * c.τ)
            k += 1
        end
        SciMLBase.derivative_discontinuity!(integ, false)
        return nothing
    end
    return SciMLBase.DiscreteCallback(cond, _Builtin(affect!); initialize = start, save_positions = (false, false))
end

"""
    MaskSync(moving)

The built-in callback of the masks on an OrdinaryDiffEq solve (F4-02; F4 design §3.6). A
masked site's rate is its value's time derivative (`∂v/∂t`, 0 for a value that does not read
the time), so the solver carries the value at its own order; the callback writes values only
where the mask *set* changes, which no rate can carry:
- at `init`, every masked site (the first save is rewritten), for a state that was not built
  by `discretize` or `remake` (they hold the masked values already);
- when the mask kernels read the time or the clock (`moving`), after each accepted step, the
  sites that became masked since the last write (released sites keep their values); and at
  each located switch, every masked site ([`MaskEvent`](@ref));
- at every discrete event, at every masked site (a value that reads a parameter, a table, an
  input or `step_index(t)` jumps there, which its rate cannot carry): a new step index
  ([`ClockTick`](@ref)), and any write of a parameter, a table or an input through `setp` or
  `integ.ps[k] = v` on the integrator (the OrdinaryDiffEqCore extension).
A step that writes nothing is no discontinuity (the solver keeps its FSAL derivative).

**Moving sets.** A predicate that reads the time switches where one of its comparisons changes
sign. A comparison whose sides read only `t`, scalar parameters and constants (`t > t0`,
`sin(ω t) < 0.5`) is located exactly: a continuous callback ([`MaskEvent`](@ref)) finds its
root and every masked site takes its value there, so a set that switches on over a quiet state
(where an adaptive solver takes long steps) switches at the right time. A read of
`step_index(t)` switches at the clock's boundaries, which [`ClockTick`](@ref) lands on. Any
other read of the time in a predicate (a comparison with a field, an input or a coordinate,
`t == t0`, a bare `t`) has no located switch: the set moves at the end of the step it moved in,
and over a quiet state the solver can step over the switch. An OrdinaryDiffEq solve of such a
predicate is refused at `init` (`unlocated`) unless it bounds the step (`dtmax`) or gives
`tstops`; with them the switch is first order in time. (A `tstops` at a located switch alone
does not apply a mask such as `t > 0.3`: the predicate is false at exactly 0.3.)
A user callback that writes `integ.p` directly (not through `setp` or `integ.ps`) and changes a
value that a mask reads must call [`sync_masks!`](@ref)`(integ)` itself: such a write is not
seen by the masks until then.
"""
struct MaskSync
    moving::Bool
    unlocated::Bool                     # a moving predicate with a switch that has no event
end
MaskSync(moving::Bool) = MaskSync(moving, false)
function _callback(c::MaskSync)
    affect!(integ) = (mask_sync!(integ) || SciMLBase.derivative_discontinuity!(integ, false); nothing)
    # at `init`: the first save (taken before the callbacks start) holds the masked values too
    function start(cb, u, t, integ)
        c.unlocated && !_step_bounded(integ) && throw(ArgumentError(string("a masked condition's predicate reads ",
            "the time in a switch an OrdinaryDiffEq solver cannot locate (a comparison of `t` with a field, an input ",
            "or a coordinate, an equality, or a bare `t`): over a quiet state an adaptive step can pass the switch, ",
            "and the mask is never applied. Bound the step (`dtmax`) or give `tstops` at the switch, write the ",
            "switch as a comparison of `t` with parameters and constants (`t > t0`: located exactly), or solve ",
            "with a field algorithm (`ExplicitEuler(; dt)`)")))
        mask_sync!(integ; all = true) || return SciMLBase.derivative_discontinuity!(integ, false)
        sol = integ.sol
        !isempty(sol.t) && sol.t[end] == t && length(sol.u[end]) == length(integ.u) && copyto!(sol.u[end], integ.u)
        return nothing
    end
    cond = c.moving ? (u, t, integ) -> true : (u, t, integ) -> false
    return SciMLBase.DiscreteCallback(cond, _Builtin(affect!); initialize = start, save_positions = (false, false))
end
# an OrdinaryDiffEq solve that bounds its step (`dtmax` below the span) or gives `tstops` (more
# than the span's end and the clock's boundaries, which the built-in callbacks add)
function _step_bounded(integ)
    hasproperty(integ, :opts) || return true
    o = integ.opts
    tf, t0 = integ.sol.prob.tspan[2], integ.sol.prob.tspan[1]
    hasproperty(o, :dtmax) && abs(o.dtmax) < abs(tf - t0) && return true
    hasproperty(o, :tstops) || return true
    fp = lattice_metadata(integ.sol.prob).problem
    τ = clock_slot(fp.group.spec) == 0 ? nothing : fp.group.spec.clock
    h = o.tstops
    v = hasproperty(h, :valtree) ? h.valtree : collect(h)
    tol = 1e-9 * abs(tf - t0)
    isclock(s) = τ !== nothing && abs((s - t0) / τ - round((s - t0) / τ)) * τ <= tol
    return any(s -> abs(s - tf) > tol && !isclock(s), v)
end

"""
    MaskEvent(f)

The built-in callback of one located switch of a moving mask set on an OrdinaryDiffEq solve
(review F4 b2 #3; [`MaskSync`](@ref)): a continuous callback on `f(p, t)` (a comparison's
`lhs - rhs` of the time and the parameters) whose root the solver finds; at the root every
masked site takes its value, with the masks evaluated just past it (at `nextfloat(t)`: a root
of `t - t0` is `t0` itself, where `t > t0` is still false).
"""
struct MaskEvent
    f::Any
end
function _callback(c::MaskEvent)
    f = c.f
    cond(u, t, integ) = f(_pvals(integ.p), t)
    # the masks just past the root (a root of `t - 0.3` is 0.3 itself, where `t > 0.3` is false)
    function affect!(integ)
        t = integ.t
        changed = mask_sync!(integ; all = true, t = t isa AbstractFloat ? nextfloat(t) : t)
        SciMLBase.derivative_discontinuity!(integ, changed)
        return nothing
    end
    return SciMLBase.ContinuousCallback(cond, _Builtin(affect!); rootfind = SciMLBase.RightRootFind,
        save_positions = (false, false))
end

"""
    mask_sync!(integ; all = false, t = integ.t) -> Bool

Run the masks of an OrdinaryDiffEq integrator's right side at time `t` (its own by default),
its step index and inputs, and write the masked values into `integ.u` at the sites that became
masked since the last write (`all = true`: at every masked site; the work of
[`MaskSync`](@ref)): whether a value changed.
"""
function mask_sync!(integ; all::Bool = false, t = integ.t)
    m = lattice_metadata(integ.sol.prob)
    p, u = integ.p, integ.u
    g = _task_rhs(_built(m, u, p, t))
    pv = _pvals(p)
    _synced(g, p) || _sync!(g, p)
    _derives(g) && derive!(pv, _ptables(p, g.ctx.tables), g.ctx.index)
    isempty(g.init.launches) || _init!(g, pv, t, _ptick(p))
    changed = false
    for (range, mk, c, vf, mode, _, prev) in g.masked
        v = convert(eltype(u), _coefdual(c, pv))
        changed |= _write_masked!(view(u, range), mk, prev, v, vf, all)
        copyto!(prev, mk)
    end
    return changed
end
"""
    sync_masks!(integ)

A discrete event on an OrdinaryDiffEq integrator of a lattice problem with masks: every masked
site takes its value again at the integrator's time, step index, parameters, tables and inputs
(`mask_sync!(integ; all = true)`), and the solver restarts its derivative when a value changed.
A no-op on a problem with no masks.
"""
function sync_masks!(integ)
    m = lattice_metadata(integ.sol.prob)
    (m === nothing || !_has_masks(m.problem)) && return false
    changed = mask_sync!(integ; all = true)
    changed && SciMLBase.derivative_discontinuity!(integ, true)
    return changed
end
# write `v` (or `v vf`) at the masked sites that were not masked at the last write (`all`: at
# every masked site): whether a value changed
function _write_masked!(u, m, prev, v, vf, all)
    n = length(m)
    if !(KA.get_backend(u) isa KA.CPU)          # a device: one reduction (one host sync), then the writes
        U = reshape(u, n, :)
        new = all ? (m .!= 0) : (m .!= 0) .& (prev .== 0)
        any(new) || return false
        vf === nothing ? (U .= ifelse.(new, v, U)) : (U .= ifelse.(new, v .* vf, U))
        return true
    end
    changed = false
    for j in 0:(div(length(u), n) - 1), i in 1:n
        (m[i] == 0 || (!all && prev[i] != 0)) && continue
        w = vf === nothing ? v : v * vf[i]
        u[j * n + i] == w || (u[j * n + i] = w; changed = true)
    end
    return changed
end

# The masked values in a state `U` (review 2): the mask kernels of `m`'s right side run at `t`
# with the parameters, tables and inputs of `lp`, on a store of their own (the init plan is the
# right side's, kept in the metadata), and `U` takes the value at each masked site. A state with
# an unset input is left as it is (its solve names the input).
function _clamp_masks!(U, m::LatticeMetadata, lp::LatticeParameters, t = m.problem.tspan[1])
    fp = m.problem
    _has_masks(fp) || return U
    any(x -> last(x) === nothing, lp.inputs) && return U
    E = eltype(U)
    (isbitstype(E) || Exec.ishost(fp.backend)) || return U
    s = _sem(m)
    ip, _ = lock(() -> _plans!(m.plans, s, fp.initkeys, _rhs_options(fp), valtype(E), fp.backend), _PLANS_LOCK)
    st = FieldStore(fp.backend, s; E, TE = _tabeltype(lp.tables))
    foreach(((k, v),) -> settable!(st, s, k, v), lp.tables)
    foreach(((k, v),) -> _set_input!(st, s, k, v), lp.inputs)
    pv = lp.values
    isempty(ip.launches) || run_step!(fp.backend, s, ip, st, pv; rt = (Float64(primal(t)), 0.0, lp.tick[]), c = zero(E))
    slots = state_layout(s, Int[fieldid(s, k) for k in fp.state])
    for r in s.rules
        r isa NodeValueRule && isassigned(slots, r.field) && !isempty(slots[r.field]) || continue
        mk = array(st, s.masks[r.mask].field, :cur)
        v = convert(E, _coefdual(r.value, pv))
        u = view(U, slots[r.field])
        r.vfield == 0 ? _clamp_masked!(u, mk, v) : _clamp_masked!(u, mk, v, array(st, r.vfield, :cur))
    end
    return U
end
# the state of a remake with new parameters, inputs or `u0`: a copy with the masked values. A
# mask value reads the parameters and tables, so a Dual parameter or table promotes the state
# (as SciML promotes `u0` to the parameters' element type at `solve`) instead of a conversion of
# the Dual value to the state's type
function _masked_u0(prob, u0, q)
    m = lattice_metadata(prob)
    (m === nothing || (u0 === missing && q === missing) || !_has_masks(m.problem)) && return u0
    u = u0 === missing ? prob.u0 : u0
    lp = q === missing ? prob.p : q
    E = lp isa LatticeParameters ? problem_eltype(u, lp.values, lp.tables) : eltype(u)
    U = E === eltype(u) ? copy(u) : copyto!(similar(u, E), u)
    return _clamp_masks!(U, m, lp)
end

# A system with no time (F4-02; F4 design §3.6): every row linear gives a `LinearProblem` of the
# right side's operator, any other a `NonlinearProblem` of the right side at `t₀`
function _timefree_problem(meta, f, U, lp; jac::Bool = false, sparse::Bool = false, jvp::Bool = true)
    fp = meta.problem
    ix = fp.index
    if all(r -> r.linear, operator_spec(fp.group.spec).rows)
        A = LatticeOperator(f, lp, U)
        b = -A.r0
        return SciMLBase.LinearProblem{true}(A, b, lp; u0 = U, f = SciMLBase.SymbolicLinearInterface(;
            update_Ab = UpdateLatticeAb(), sys = ix, observed = nothing, metadata = meta))
    end
    # (the residual's Jacobian keywords take the time span's start, as the residual does)
    jkw = map(v -> v isa Union{LatticeJacobian, LatticeJVP} ? _AtStart(v, fp.tspan[1]) : v,
        _jacobian_kw(meta, U, lp; jac, sparse, jvp))
    return SciMLBase.NonlinearProblem(SciMLBase.NonlinearFunction{true}(f; sys = ix, jkw...), U, lp)
end
# a Jacobian function of the right side as one of a residual `r(u, p)`: at time `t`
struct _AtStart{F}
    f::F
    t::Float64
end
(a::_AtStart)(J, u, p) = a.f(J, u, p, a.t)
(a::_AtStart)(Jv, v, u, p) = a.f(Jv, v, u, p, a.t)
# the residual of a steady system: the right side at the time span's start
(f::LatticeFunction)(du, u, p) = f(du, u, p, f.meta.problem.tspan[1])

"""
    LatticeOperator(f, p, u)

The operator `A x = r(x) - r(0)` of the right side `r` (a [`LatticeFunction`](@ref)) at the
parameters `p`, a `SciMLOperators.AbstractSciMLOperator`: for a system whose rows are linear
it is the system's matrix, and `A u = -r(0)` is its steady state (the `LinearProblem` of a
system with no time). `A.r0` holds `r(0)`. It applies the compiled right side (no matrix is
stored).
"""
struct LatticeOperator{T, F, P, V} <: SciMLOperators.AbstractSciMLOperator{T}
    f::F
    p::P
    r0::V
    zero::V
end
function LatticeOperator(f::LatticeFunction, p, u::AbstractVector{T}) where {T}
    z = fill!(similar(u), zero(T))
    r0 = similar(u)
    f(r0, z, p)
    return LatticeOperator{T, typeof(f), typeof(p), typeof(u)}(f, p, r0, z)
end
Base.size(A::LatticeOperator) = (length(A.r0), length(A.r0))
Base.size(A::LatticeOperator, i::Integer) = size(A)[i]
function LinearAlgebra.mul!(w::AbstractVector, A::LatticeOperator, v::AbstractVector)
    A.f(w, v, A.p)
    w .-= A.r0
    return w
end
function LinearAlgebra.mul!(w::AbstractVector, A::LatticeOperator, v::AbstractVector, α, β)
    t = similar(w)
    LinearAlgebra.mul!(t, A, v)
    w .= α .* t .+ β .* w
    return w
end
Base.:*(A::LatticeOperator, v::AbstractVector) = LinearAlgebra.mul!(similar(v, promote_type(eltype(A), eltype(v))), A, v)
(A::LatticeOperator)(v::AbstractVector, u, p, t; kw...) = A * v
(A::LatticeOperator)(w::AbstractVector, v::AbstractVector, u, p, t; kw...) = LinearAlgebra.mul!(w, A, v)
SciMLOperators.islinear(::LatticeOperator) = true
SciMLOperators.isconstant(::LatticeOperator) = true
SciMLOperators.has_mul(::LatticeOperator) = true
SciMLOperators.has_mul!(::LatticeOperator) = true
SciMLOperators.iscached(::LatticeOperator) = true
SciMLOperators.update_coefficients!(A::LatticeOperator, u, p, t; kw...) = A
SciMLOperators.update_coefficients(A::LatticeOperator, u, p, t; kw...) = A
_lmeta(A::LatticeOperator) = A.f.meta
# a copy shares the right side and the parameters (the operator is the same), not its vectors
Base.copy(A::LatticeOperator{T, F, P, V}) where {T, F, P, V} = LatticeOperator{T, F, P, V}(A.f, A.p, copy(A.r0), copy(A.zero))
"""
    lattice_matrix(A::LatticeOperator) -> AbstractMatrix

The matrix of `A`, column by column (`n` applications of the right side, an `n × n` array on
its backend): the route to a factorization, `solve(LinearProblem(lattice_matrix(lp.A), lp.b),
LUFactorization())`, for a small system. A Krylov method applies `A` itself.
"""
function lattice_matrix(A::LatticeOperator)
    n = size(A, 1)
    M = fill!(similar(A.r0, n, n), zero(eltype(A)))
    e = similar(A.r0)
    for j in 1:n
        fill!(e, zero(eltype(A)))
        view(e, j:j) .= one(eltype(A))
        LinearAlgebra.mul!(view(M, :, j), A, e)
    end
    return M
end
# a factorization asks for a matrix the operator does not store (review 4): the routes
Base.convert(::Type{AbstractMatrix}, ::LatticeOperator) = throw(ArgumentError(string("a `LatticeOperator` stores no ",
    "matrix (it applies the compiled right side), so a factorization (`LUFactorization`, `QRFactorization`) has none ",
    "to factor: solve with a Krylov method (`KrylovJL_GMRES()`, `KrylovJL_CG()`) or `QuasiSteady()`, or factor the ",
    "assembled matrix, `LinearProblem(Problems.lattice_matrix(lp.A), lp.b)` (n² values)")))
SciMLOperators.isconvertible(::LatticeOperator) = false

"""
    UpdateLatticeAb()

The `update_Ab` of a time-free `LinearProblem` (review 4): a parameter write on the problem
(`lp.ps[k] = v`, `setp`) takes effect in place, so `r(0)` (in `A`) and `b = -r(0)` are computed
again from the written parameters (the operator applies the right side at them already).
"""
struct UpdateLatticeAb end
function (::UpdateLatticeAb)(A::LatticeOperator, b, p)
    A.p === p || throw(ArgumentError(string("the parameters written are not the operator's (a problem built with ",
        "another `p`): `remake(prob; p = …)` builds the problem at new values")))
    A.f(A.r0, A.zero, p)
    b .= .-A.r0
    return nothing
end
"""
    field_problem(prob) -> FieldProblem

The owned problem that field algorithms step for `prob` (a problem `discretize` returned): the
metadata's group at `prob`'s state (on the host), time span and parameters. A `FieldProblem`
is its own.
"""
field_problem(fp::FieldProblem) = fp
function field_problem(prob)
    m = lattice_metadata(prob)
    m === nothing && throw(ArgumentError(string("this problem was not built by `LatticePDE.discretize` (it has no ",
        "field groups to step): give `solve` an OrdinaryDiffEq solver")))
    fp, lp = m.problem, prob.p
    U = prob.u0 === nothing ? fp.u0 : prob.u0
    _check_backend(fp.backend, U, "u0")
    u0 = U isa Vector ? copy(U) : Array(U)
    span = hasproperty(prob, :tspan) ? prob.tspan : fp.tspan        # (a system with no time: none)
    return _field_problem(fp.program, fp.state, u0, span, collect(lp.values), lp.tables, lp.inputs, fp.backend,
        fp.index, fp.faces, fp.stability, fp.kind, fp.initkeys, fp.options, fp.group)
end

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
    tcell::Base.RefValue{Float64}              # the time of a call through a `LatticeFunction` (no boxing)
    masked::Vector{Tuple{UnitRange{Int}, Any, Coef, Any, Symbol, Any, Any}} # the masked state fields (F4-02, `_masked`)
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
    k = _ptick(p)
    isempty(f.init.launches) || (!f.ctx.moving && _same_params(f, pv)) || _init!(f, pv, t, k)
    f.walk(f.launches, (du, u, pv, t, k))
    isempty(f.masked) || _masked_rates!(du, u, pv, f.masked)
    return nothing
end
# the clock's step index of `p` (F4-02), or nothing (the launch keeps the slot's value)
_ptick(p::LatticeParameters) = p.tick[]
_ptick(p) = nothing
# The masked sites of the state (F4-02; F4 design §3.6): a site of a rate's field holds its
# value (rate 0), a site of a steady row's field is the row `0 = v - u` (so the mass matrix
# stays regular there), and a map's next value is the mask value. A value or a mask set that
# moves in time follows the mask callback ([`MaskSync`](@ref)) at each accepted step.
function _masked_rates!(du, u, p, masked)
    for (range, m, c, vf, mode, rf, _) in masked
        d = view(du, range)
        if mode === :hold
            # a value that reads the time moves at its rate `∂v/∂t` (review R1), else it holds
            rf === nothing ? _clamp_masked!(d, m, zero(eltype(du))) :
            _clamp_masked!(d, m, convert(eltype(du), _coefdual(c, p)), rf)
        else
            v = convert(eltype(du), _coefdual(c, p))
            mode === :next ? (vf === nothing ? _clamp_masked!(d, m, v) : _clamp_masked!(d, m, v, vf)) :
            _mask_residual!(d, view(u, range), m, v, vf)
        end
    end
    return nothing
end
# `d = v - u` (or `v vf - u`) at the masked sites (a broadcast over the components of a site)
function _mask_residual!(d, u, m, v, vf)
    n = length(m)
    D, U = reshape(d, n, :), reshape(u, n, :)
    vf === nothing ? (D .= ifelse.(m .!= 0, v .- U, D)) : (D .= ifelse.(m .!= 0, v .* vf .- U, D))
    return nothing
end
_clamp_masked!(u, m, v) = KA.get_backend(u) isa KA.CPU ? _clamp_host!(u, m, v) : _clamp_device!(u, m, v)
_clamp_masked!(u, m, v, vf) = KA.get_backend(u) isa KA.CPU ? _clamp_host!(u, m, v, vf) : _clamp_device!(u, m, v, vf)

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
function _init!(f::LatticeRHS{L, W, E}, p, t = f.ctx.t0, k = nothing) where {L, W, E}
    run_step!(f.ctx.backend, f.ctx.program, f.init, f.store, p; rt = k === nothing ? (Float64(primal(t)), 0.0) :
                                                                        (Float64(primal(t)), 0.0, k), c = zero(E))
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
    k === :synced ? Any[getfield(f, :synced)[1] === nothing ? nothing : :given] : k === :tcell ? Ref(0.0) : k === :masked ? val(getfield(f, :masked)) :
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
# the masked state fields of program `s` on store `st` (a `NodeValueRule` on a state field):
# each field's slot in the state, its mask array, the rule's value, its value field (or
# `nothing`), the row's mode (`:hold` a rate, `:steady` a steady row, `:next` a map), the value's
# time rate field (`maskrate:…`, a value that reads the time; or `nothing`) and the mask the last
# sync wrote (zeros: none yet)
function _masked(s::Program, st::FieldStore, slots, ctx)
    out = Tuple{UnitRange{Int}, Any, Coef, Any, Symbol, Any, Any}[]
    for r in s.rules
        r isa NodeValueRule && isassigned(slots, r.field) && !isempty(slots[r.field]) || continue
        mode = isempty(ctx.rates) ? :next : s.fields[r.field].key in ctx.steady ? :steady : :hold
        vf = r.vfield == 0 ? nothing : array(st, r.vfield, :cur)
        rk = r.vfield == 0 ? "" : replace(s.fields[r.vfield].key, r"^maskvalue:" => "maskrate:")
        ri = rk == "" ? nothing : findfirst(fd -> fd.key == rk, s.fields)
        rf = ri === nothing ? nothing : array(st, ri, :cur)
        mk = array(st, s.masks[r.mask].field, :cur)
        push!(out, (slots[r.field], mk, r.value, vf, mode, rf, fill!(similar(mk), 0)))
    end
    return out
end
function _lattice_rhs(ctx::RHSContext, ::Type{E}, base, Pinit = nothing, inputs = ();
        shared::Symbol = :all) where {E}
    s, backend = ctx.program, ctx.backend
    ip, sp = lock(() -> _plans!(ctx.plans, s, ctx.initkeys, ctx.options, valtype(E), backend), _PLANS_LOCK)
    ids = Int[fieldid(s, k) for k in ctx.state]
    # a rate program writes each rate into a scratch field (one buffer per field); a map program
    # writes the next value of each state field (its `:next` role: the solver's `du`)
    sort(sp.swaps) == (isempty(ctx.rates) ? sort(ids) : Int[]) ||
        throw(ArgumentError("the ODE form has one buffer per field"))
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    marks = Dict{Int32, StateView}()
    for (k, i) in zip(ctx.state, ids)
        marks[Int32(i)] = StateView(slots[i], false)
        isempty(ctx.rates) || (marks[fieldid(s, ctx.rates[k])] = StateView(slots[i], true))
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
            elseif f.role == :input                # a float input, in this build's type (a
                b = base.bufs[i][1]                #  Float64 build after a Dual one: the primal)
                st.bufs[i][1] .= promote_type(eltype(st.bufs[i][1]), eltype(b)) == eltype(st.bufs[i][1]) ? b : primal.(b)
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
                         array(st, id, role, role == :table ? 0 : 1) :
                         role === :next ? StateView(marks[id].range, true) : marks[id]
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
        Any[nothing], Dict{Task, Any}(), ReentrantLock(), Any[nothing], Int[0], Ref(0.0), _masked(s, st, slots, ctx))
    isempty(inputs) || (f.synced[1] = :given)                # (the inputs given at the build)
    Pinit === nothing || isempty(ip.launches) || _init!(f, Pinit)
    return f
end

"""
    ODEAux(f, program)

The aux fields of an ODE problem as observed quantities (F3 design §3.12): `a(u, p, t, key)` is
aux field `key` at state `u`, parameters `p` and time `t`, `rhs(u, t)`, grid-shaped on the
problem's backend (a host state, such as an owned solve's save on a device, is copied there
first). One call of the right side `f` at `(u, p, t)` runs the aux kernels on the
store of the build this task runs (the rates it writes into a scratch `du` are dropped).
"""
struct ODEAux{F, P}
    f::F
    program::P
end
_build_eltype(::LatticeRHS{L, W, E}) where {L, W, E} = E
function (a::ODEAux)(u, p, t, key)
    # a saved state of an owned solve on a device is a host vector: the aux kernels read it on
    # the problem's backend (review F4 b2 #4)
    if a.f isa LatticeFunction
        be = a.f.meta.problem.backend
        typeof(KA.get_backend(u)) == typeof(be) || (u = copyto!(KA.allocate(be, eltype(u), length(u)), u))
    end
    f = a.f isa LatticeFunction ? _built(a.f.meta, u, p, t) : a.f
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
        Dict{Type, Tuple{StepPlan{N}, StepPlan{N}}}(), index, stability, binputs, String[], false)
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
const LatticeODEFunction = SciMLBase.ODEFunction{<:Any, <:Any, <:Union{LatticeRHS, LatticeFunction}}
# (the problem type bounded: SciMLBase's `remake` of a dynamical or second-order problem stays its own)
const LatticeODEProblem = SciMLBase.ODEProblem{<:Any, <:Any, <:Any, <:Any, <:LatticeODEFunction, <:Any,
                                               <:Union{SciMLBase.StandardODEProblem, LatticeMetadata}}
const LatticeDiscreteFunction = SciMLBase.DiscreteFunction{<:Any, <:Any, <:LatticeFunction}
const LatticeDiscreteProblem = typewith(SciMLBase.DiscreteProblem, :f, LatticeDiscreteFunction)
const LatticeSteadyStateProblem = typewith(SciMLBase.SteadyStateProblem, :f, LatticeODEFunction)
const LatticeNonlinearProblem = typewith(SciMLBase.NonlinearProblem, :f,
                                          typewith(SciMLBase.NonlinearFunction, :sys, LatticeIndex))
const LatticeSciMLProblem = Union{LatticeODEProblem, LatticeSteadyStateProblem, LatticeNonlinearProblem,
                                  LatticeDiscreteProblem}

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
    # a state on another backend than the problem's is refused, naming both (SX-12)
    u0 isa AbstractArray && !(u0 isa AbstractArray{<:Pair}) && _check_backend(KA.get_backend(prob.u0), u0, "u0")
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
    q = remake_params(prob, p, inputs)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.ODEProblem}, prob; p = q, u0 = _masked_u0(prob, remake_u0(prob, u0), q),
        _remake_kw(prob, kw)...)
end
function SciMLBase.remake(prob::LatticeDiscreteProblem; p = missing, u0 = missing, inputs = (), kw...)
    q = remake_params(prob, p, inputs)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.DiscreteProblem}, prob; p = q, u0 = _masked_u0(prob, remake_u0(prob, u0), q),
        _remake_kw(prob, kw)...)
end
function SciMLBase.remake(prob::LatticeSteadyStateProblem; p = missing, u0 = missing, inputs = (), kw...)
    q = remake_params(prob, p, inputs)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.SteadyStateProblem}, prob; p = q, u0 = _masked_u0(prob, remake_u0(prob, u0), q),
        kw...)
end
# `NonlinearProblem(SteadyStateProblem(prob))`: the residual `f(du, u, p, Inf)` with the
# Jacobian keywords in residual form. (SciMLBase 3.58's own conversion wraps a `jvp` as
# `(Jv, u, p)`, dropping the vector, so its `NonlinearFunction` refuses an in-place `jvp` as
# nonconforming; F4-07 sets one on every problem.)
# Upstream: https://github.com/SciML/SciMLBase.jl/issues/1663; drop this method once a fixed SciMLBase is required.
function SciMLBase.NonlinearProblem(prob::LatticeSteadyStateProblem)
    f = prob.f
    kw = (; sys = f.sys)
    f.jac === nothing || (kw = (; kw..., jac = _AtStart(f.jac, Inf)))
    f.jvp === nothing || (kw = (; kw..., jvp = _AtStart(f.jvp, Inf)))
    f.jac_prototype isa SparseArrays.SparseMatrixCSC && (kw = (; kw..., jac_prototype = f.jac_prototype, colorvec = f.colorvec))
    r = _SteadyResidual(f.f)
    return SciMLBase.NonlinearProblem(SciMLBase.NonlinearFunction{true, SciMLBase.FullSpecialize}(r; kw...), prob.u0, prob.p;
        prob.kwargs...)
end
struct _SteadyResidual{F}
    f::F
end
(r::_SteadyResidual)(du, u, p) = (r.f(du, u, p, Inf); nothing)
function SciMLBase.remake(prob::LatticeNonlinearProblem; p = missing, u0 = missing, inputs = (), kw...)
    q = remake_params(prob, p, inputs)
    return invoke(SciMLBase.remake, Tuple{SciMLBase.NonlinearProblem}, prob; p = q, u0 = _masked_u0(prob, remake_u0(prob, u0), q),
        kw...)
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
# (the clock's slot of a SciML problem `discretize` returned is no parameter either)
SII.getp(sys::LatticeSciMLProblem, sym) = (_not_clock(sym); invoke(SII.getp, Tuple{Any, Any}, sys, sym))
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

# A field solver or a linear solver given to an `ODEProblem` that `discretize` did not build
# (its right side has no group to step): the route to an OrdinaryDiffEq solver
function _ode_refusal(alg)
    name = alg isa LinearSolver ? string("`", repr(alg), "` is a linear solver, the `inner` of an implicit field solver") :
           string("`", _algtext(alg), "` is a field solver: it steps the problem of a discretized system")
    return ArgumentError(string("`solve`/`init` of an `ODEProblem`: ", name, ". This `ODEProblem` was not built by ",
        "`LatticePDE.discretize` (it has no field groups to step): give it an OrdinaryDiffEq solver (`ImplicitEuler()` ",
        "is Backward Euler), or solve the problem `discretize` returns"))
end
CommonSolve.solve(::SciMLBase.AbstractODEProblem, alg::Union{FieldAlgorithm, LinearSolver}; kw...) = throw(_ode_refusal(alg))
CommonSolve.init(::SciMLBase.AbstractODEProblem, alg::Union{FieldAlgorithm, LinearSolver}; kw...) = throw(_ode_refusal(alg))

# The problems `discretize` returns (F4-01): one problem, many algorithms. A field algorithm
# (or no algorithm: the default of the group's kind, Q1) steps the owned problem built from the
# metadata and the problem's state, time span and parameters; any other algorithm is SciML's.
const LatticeProblem = Union{LatticeODEProblem, LatticeDiscreteProblem}
function _owned_or_refuse(prob, alg)
    lattice_metadata(prob) === nothing && throw(_ode_refusal(alg))
    return field_problem(prob)
end
# `save_idxs` of state fields on an OrdinaryDiffEq solve: a field is a grid of indices, which
# SciML's saved subsystem cannot take, so the fields become their flat indices (and `sol[c]`
# finds the field in the saves: F4-05)
function SciMLBase.get_save_idxs_and_saved_subsystem(prob::LatticeProblem, save_idxs)
    idx = _field_save_idxs(prob, save_idxs)
    idx === save_idxs && return invoke(SciMLBase.get_save_idxs_and_saved_subsystem, Tuple{Any, Any}, prob, save_idxs)
    return invoke(SciMLBase.get_save_idxs_and_saved_subsystem, Tuple{Any, Vector{Int}}, prob, idx)
end
SciMLBase.get_save_idxs_and_saved_subsystem(prob::LatticeProblem, i::Nothing) =
    invoke(SciMLBase.get_save_idxs_and_saved_subsystem, Tuple{Any, Nothing}, prob, i)
SciMLBase.get_save_idxs_and_saved_subsystem(prob::LatticeProblem, i::Int) =
    invoke(SciMLBase.get_save_idxs_and_saved_subsystem, Tuple{Any, Int}, prob, i)
SciMLBase.get_save_idxs_and_saved_subsystem(prob::LatticeProblem, i::Vector{Int}) =
    invoke(SciMLBase.get_save_idxs_and_saved_subsystem, Tuple{Any, Vector{Int}}, prob, i)
function _field_save_idxs(prob, save_idxs)
    m = lattice_metadata(prob)
    m === nothing && return save_idxs
    ix = m.problem.index
    ix isa LatticeIndex || return save_idxs
    isfield(i) = !(i isa Integer) && get(ix.vars, ix.key(i), nothing) isa FieldSlot
    any(isfield, save_idxs isa Union{AbstractVector, Tuple} ? save_idxs : (save_idxs,)) || return save_idxs
    return _save_indices(m.problem, save_idxs)
end
# (the integrator keeps `prob`: its solution is SciML's, of `prob`, F4-04; the problem's own
# keywords join the call's as DiffEqBase merges them, its callbacks before the call's, without
# the built-in ones of the ODE path, which an owned run steps itself: F4-05)
function _owned_init(fp::FieldProblem, alg, prob; callback = nothing, kw...)
    pk = Dict{Symbol, Any}(pairs(prob.kwargs))
    pcb = _user_callbacks(pop!(pk, :callback, nothing))
    cb = pcb === nothing ? callback : callback === nothing ? pcb : SciMLBase.CallbackSet(pcb, callback)
    return CommonSolve.init(fp, alg; pk..., kw..., callback = cb, _sciml = prob)
end
function _user_callbacks(cb)
    cb === nothing && return nothing
    cs = cb isa SciMLBase.CallbackSet ? cb : SciMLBase.CallbackSet(cb)
    d = filter(!_builtin, collect(Any, cs.discrete_callbacks))
    c = filter(!_builtin, collect(Any, cs.continuous_callbacks))
    isempty(d) && isempty(c) && return nothing
    return SciMLBase.CallbackSet(c..., d...)
end
# the built-in callbacks of a problem's keywords (the clock, the masks), or nothing
function _builtin_set(prob)
    cb = get(prob.kwargs, :callback, nothing)
    cb === nothing && return nothing
    cs = cb isa SciMLBase.CallbackSet ? cb : SciMLBase.CallbackSet(cb)
    b = Any[c for c in (cs.continuous_callbacks..., cs.discrete_callbacks...) if _builtin(c)]
    return isempty(b) ? nothing : b
end
# `remake(prob; callback = cb)`: the built-in callbacks stay, the given ones join them (a
# replaced keyword would drop the clock and the masks of the ODE path: review F4 b2 #2)
function _remake_kw(prob, kw)
    haskey(kw, :callback) || return kw
    b = _builtin_set(prob)
    b === nothing && return kw
    u = _user_callbacks(kw[:callback])
    cb = u === nothing ? SciMLBase.CallbackSet(b...) : SciMLBase.CallbackSet(b..., u)
    return merge(NamedTuple(kw), (; callback = cb))
end
CommonSolve.init(prob::LatticeProblem, alg::FieldAlgorithm; kw...) = _owned_init(_owned_or_refuse(prob, alg), alg, prob; kw...)
CommonSolve.init(prob::LatticeProblem, alg::LinearSolver; kw...) = CommonSolve.init(_owned_or_refuse(prob, alg), alg; kw...)
CommonSolve.solve(prob::LatticeProblem, alg::FieldAlgorithm; kw...) = CommonSolve.solve!(CommonSolve.init(prob, alg; kw...))
CommonSolve.solve(prob::LatticeProblem, alg::LinearSolver; kw...) = CommonSolve.solve(_owned_or_refuse(prob, alg), alg; kw...)
CommonSolve.init(prob::LatticeProblem; kw...) = (fp = field_problem(prob); _owned_init(fp, _default_alg(fp), prob; kw...))
CommonSolve.solve(prob::LatticeProblem; kw...) = CommonSolve.solve!(CommonSolve.init(prob; kw...))

# A system with no time (F4-02): its `LinearProblem` or `NonlinearProblem`; a field algorithm
# (or none: `QuasiSteady()`) solves the owned problem once
const LatticeLinearProblem = typewith(SciMLBase.LinearProblem, :A, LatticeOperator)
const LatticeResidualProblem = typewith(SciMLBase.NonlinearProblem, :f,
                                         typewith(SciMLBase.NonlinearFunction, :f, LatticeFunction))
const LatticeTimeFreeProblem = Union{LatticeLinearProblem, LatticeResidualProblem}
CommonSolve.solve(prob::LatticeTimeFreeProblem, alg::Union{FieldAlgorithm, LinearSolver}; kw...) =
    CommonSolve.solve(field_problem(prob), alg; kw...)
CommonSolve.solve(prob::LatticeTimeFreeProblem; kw...) = CommonSolve.solve(field_problem(prob); kw...)
# a remake builds the problem again at the new values (`A` and `b` are the parameters')
function SciMLBase.remake(prob::LatticeLinearProblem; p = missing, u0 = missing, inputs = (), kw...)
    isempty(kw) || throw(ArgumentError(string("`remake` of a system with no time takes `p`, `u0` and `inputs`; got ",
        join(("`$k`" for k in keys(kw)), ", "))))
    q = remake_params(prob, p, inputs)
    m = lattice_metadata(prob)
    fp = m.problem
    lp = q === missing ? prob.p : q
    U = u0 === missing ? (prob.u0 === nothing ? fp.u0 : prob.u0) : remake_u0(prob, u0)
    g = _field_problem(fp.program, fp.state, U isa Vector ? copy(U) : Array(U), fp.tspan, collect(lp.values), lp.tables,
        lp.inputs, fp.backend, fp.index, fp.faces, fp.stability, fp.kind, fp.initkeys, fp.options, fp.group)
    return lattice_problem(g)
end
