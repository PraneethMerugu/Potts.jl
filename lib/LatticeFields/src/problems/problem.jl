# The owned fast path (v3 §8, §2.3): `FieldProblem`, solved by its own steppers through
# prebuilt Exec launches. A step's launches are bound once per slot parity; a warm step only
# changes `(t, dt)` in `G.rt`, enqueues, and flips the parity (no sync, no allocation on the
# host executor). `solve`, `init`, `step!` and `solve!` follow CommonSolve.

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
struct FieldProblem{N, B, X, R, U, PV, E, TB} <: SciMLBase.AbstractSciMLProblem
    program::Program{N}
    init::StepPlan{N}
    step::StepPlan{N}
    state::Vector{String}
    u0::U
    tspan::Tuple{Float64, Float64}
    p::PV
    tables::TB                         # `key => values`, each in the tables' element type (`_table_list`)
    inputs::Vector{Pair{String, Any}}
    backend::B
    index::X
    faces::Vector{FaceCheck}
    stability::R
    kind::Symbol
    initkeys::Vector{String}
    options::CompileOptions
    group::FieldGroup{N}               # the group: its spec and plans, shared by remakes
end
function FieldProblem(prog::Program, u0, tspan, p; state, kind::Symbol,
        init = String[], index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[],
        inputs = Pair[], backend = KA.CPU(), options::CompileOptions = CompileOptions(),
        stability = p -> NaN, route = "ExplicitEuler(; dt, substeps = n)", terms = String[], linearity = nothing)
    kind in (:rate, :map) ||
        throw(ArgumentError("kind must be :rate or :map; got $(repr(kind))"))
    # the group's description (F2 design §2.2): B's problem is one group of every state field
    pv = collect(p)
    spec = GroupSpec(prog; state, kind, init, stability, route, terms, linearity,
        tables = String[first(t) for t in tables],
        params = String[index isa LatticeIndex ? parameter_name(index, i) : "#$i" for i in eachindex(pv)],
        inputs = String[f.key for f in prog.fields if f.role == :input])
    return FieldProblem(spec, u0, tspan, pv; index, tables, inputs, backend, options)
end
"""
    FieldProblem(spec::GroupSpec, u0, tspan, p; index, tables, inputs, backend, options)

The owned problem of the group `spec` (its rate program, state, kind, masks and stability
bound): the default algorithm's update (`ExplicitEuler()` for rates, `ExplicitMap()` for
maps) is fused into the rate program by the update pass; another algorithm's is fused when
it first steps the problem (once per family, [`group_program`](@ref)).
"""
function FieldProblem(spec::GroupSpec, u0, tspan, p; index = LatticeIndex(), tables = Pair{String, Vector{Float64}}[],
        inputs = Pair[], backend = KA.CPU(), options::CompileOptions = CompileOptions())
    prog, state, kind, init, stability = spec.rate, spec.state, spec.kind, spec.init, spec.stability
    faces = face_checks(prog)
    check_faces(faces, p)
    alg = kind == :map ? ExplicitMap() : ExplicitEuler()
    s = semantic(fuse_update(prog, update_rule(alg)))
    pv = collect(p)
    ins = resolve_inputs(s, index, inputs)
    tabs = _table_list(tables)
    index isa LatticeIndex && (index.program[] = s)          # (the checks of an input write)
    prob = _field_problem(s, collect(String, state), u0, tspan, pv, tabs, ins, backend, index, faces, stability, kind,
        collect(String, init), _state_options(options, problem_eltype(u0, pv, tabs)), FieldGroup(spec; alg, program = s))
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
    problem_eltype(u0, p[, tables]) -> Type

The element type of a problem with initial state `u0`, parameters `p` and tables `tables`
(`key => values`): `eltype(u0)` promoted with the element type of `p` and of the tables only
when they carry derivative parts (a Dual table promotes the state as a Dual `p` does; a
BigFloat table on a Float64 state is rounded once to the compute type).
"""
problem_eltype(u0, p) = promote_dual(eltype(u0), eltype(p))
problem_eltype(u0, p, tables) = promote_dual(problem_eltype(u0, p), _tabeltype(tables))

# The tables of a problem (number types per role, F2 design §2.9): each `key => values` keeps
# its element type (a BigFloat table stays BigFloat, a Dual table stays Dual), in one vector
# type for all, the promotion of Float64 with every table's element type (an integer table is
# a Float64 one)
function _table_list(tables)
    TT = foldl((T, x) -> promote_type(T, _tabelt(last(x))), tables; init = Float64)
    return Pair{String, Vector{TT}}[String(first(x)) => Vector{TT}(vec(collect(last(x)))) for x in tables]
end
_tabelt(v) = isconcretetype(eltype(v)) ? eltype(v) : mapreduce(typeof, promote_type, v; init = Float64)
_tabeltype(::AbstractVector{Pair{String, Vector{T}}}) where {T} = T
_tabeltype(tables) = isempty(tables) ? Float64 : _tabeltype(_table_list(tables))

# the options a problem keeps: an explicit `T` must be the state's value type (`eltype(u0)`
# decides); it is then dropped, so a `remake` to another value type plans for that type
function _state_options(o::CompileOptions, ::Type{E}) where {E}
    o.T === nothing || o.T == valtype(E) || throw(ArgumentError(string("options.T = ", o.T,
        " differs from the state's value type ", valtype(E), " (from ", E, "): the eltype of ",
        "u0 decides; pass u0 in ", o.T, " or leave T out of the options")))
    return CompileOptions(nothing, o.I, o.float64_ok, o.debug, o.index, o.lanes, o.clock, o.S, o.declared)
end

# the compile options of value type `V` on `backend`; `C`: the compute type (`compute_T`,
# FE-17; the state lanes hold `V`); `s`: the program, whose fields with a declared Float64
# storage (`fixed`) need Float64 on the device too. A declared Float64 on a device whose
# default float is Float32 registers its kernels (D-157 carve-out, `declared`; a front end that
# plans on the host for every backend, A, sets `o.declared` itself)
function _options(o::CompileOptions, ::Type{V}, backend; clock::Int = o.clock, C::Type = V, s = nothing) where {V}
    f64 = s !== nothing && any(f -> f.fixed && f.storage == F64, s.fields)
    wide = C === Float64 || f64
    ok = _float64_ok(C, backend) || (f64 && Exec.supports(backend, Float64))
    return CompileOptions(; T = C, I = o.I, float64_ok = o.float64_ok && ok, debug = o.debug,
        index = o.index, lanes = :state, clock, S = C === V ? nothing : V,
        declared = o.declared || (wide && Exec.default_float(backend) !== Float64 && !(V === Float64 && C === Float64 && !f64)))
end

# Float64 in device code: allowed on the host, and for a Float64 problem on hardware that has
# it (`Exec.supports`); a Float32 problem on a device keeps the D-157 double scan (P5 C2-1)
_float64_ok(::Type{V}, backend) where {V} =
    Exec.default_float(backend) === Float64 || (V === Float64 && Exec.supports(backend, Float64))

# the init and step plans of value type `V` (planned and emitted once per family; the ODE
# path's, `ode.jl`: the owned path's are the group's, `group_plans`)
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
        stability, kind, initkeys, options, group)
    derive!(p, tables, index)                       # the computed slots from the base values (F2-15)
    E = problem_eltype(u0, p, tables)
    _check_eltype(E, backend)
    # the plans cache is shared by a problem's remakes, which threads may build at once
    ip, sp = group_plans(group, kind == :map ? ExplicitMap() : ExplicitEuler(), valtype(E), backend, options)
    return FieldProblem{_ndims(s), typeof(backend), typeof(index),
        typeof(stability), typeof(u0), typeof(p), E, typeof(tables)}(s, ip, sp, state, u0,
        (Float64(tspan[1]), Float64(tspan[2])), p, tables, inputs, backend, index, faces, stability,
        kind, initkeys, options, group)
end

_ndims(::Program{N}) where {N} = N
# the period of the discretization's clock (`nothing`: none)
_clock(prob::FieldProblem) = prob.group.spec.clock

Base.eltype(::FieldProblem{N, B, X, R, U, PV, E}) where {N, B, X, R, U, PV, E} = E

SII.symbolic_container(p::FieldProblem) = p.index
SII.state_values(p::FieldProblem) = p.u0
SII.parameter_values(p::FieldProblem) = p.p
SII.current_time(p::FieldProblem) = p.tspan[1]

"""
    remake(prob::FieldProblem; u0, tspan, p, inputs)

A copy with new initial state, time span, parameters (`p` a vector, or `symbol => value`
pairs looked up in the index; a table as `Dk => values`) or input values (`symbol => values`
pairs; the others keep theirs). Element types are kept as given: a parameter vector keeps its
element type (Dual parameters promote the state, BigFloat parameters stay BigFloat); a pair's
plain value is written into the problem's parameter type, and a Dual value promotes it (so
under `T = BigFloat` with Float64 defaults, `p = [k => big"0.1"]` rounds to Float64: declare
BigFloat defaults or give a BigFloat vector); a
table keeps its values' element type (a BigFloat table stays BigFloat, a Dual table promotes
the state). The result's type follows from the argument types (a `Vector` of pairs with one
value type infers). A new value type plans once (cached on the problem family); a value-only
change reuses the plans. New parameters are checked again (degenerate Robin faces); the
stability bound is a function of the parameters, evaluated again when solved.
"""
function SciMLBase.remake(prob::FieldProblem; u0 = prob.u0, tspan = prob.tspan, p = prob.p,
        inputs = ())
    p, inputs = _input_pairs(prob.index, p, inputs)
    tables, p = _tables(prob, p)
    pv = _parameter_vector(prob, p)
    check_faces(prob.faces, pv)
    derive!(pv, tables, prob.index)                 # (the computed slots, before their bounds: F2-15)
    check_bounds(pv, prob.index)                    # a declared bound, at the write (F2-14)
    length(u0) == length(prob.u0) ||
        throw(ArgumentError("u0 has $(length(u0)) values; the state has $(length(prob.u0))"))
    # the declared intervals (batch 5 review M2): the face values at the new parameters, the
    # new initial values as at the build
    check_declared(prob.stability, with_tables(map(primal, pv), tables))
    u0 === prob.u0 || check_declared_state(prob, u0, eachindex(u0), "starts at")
    ins = isempty(inputs) ? prob.inputs : resolve_inputs(prob.program, prob.index, inputs, prob.inputs)
    return _field_problem(prob.program, prob.state, collect(u0), tspan, pv, tables,
        ins, prob.backend, prob.index, prob.faces, prob.stability, prob.kind, prob.initkeys,
        prob.options, prob.group)
end
# the input pairs of a parameter map `p` (`kind => K`: an input is a parameter, F4 design
# §3.3) moved to the input pairs; the other pairs in `p`'s container type
_input_pairs(ix, p, inputs) = p, inputs
function _input_pairs(ix::LatticeIndex, p::Union{AbstractVector{<:Pair}, Tuple, AbstractDict}, inputs)
    isin(x) = !(first(x) isa Union{AbstractArray, Tuple, Integer}) && input_key(ix, first(x)) !== nothing
    any(isin, p) || return p, inputs
    return filter(!isin, p), Any[collect(Any, inputs); [x for x in p if isin(x)]]
end
# the table pairs of `p` (`Dk => values`, array parameters) as the problem's new tables, and
# the other pairs (in the caller's container type, so a `Vector` of pairs infers). The tables'
# element type is the promotion of the problem's with the given values' (`_newtab`: from the
# pair type when it is concrete, else from the values)
_tables(prob::FieldProblem, p) = prob.tables, p
function _tables(prob::FieldProblem, p::Union{AbstractVector{<:Pair}, Tuple, AbstractDict})
    ix = prob.index
    ix isa LatticeIndex || return prob.tables, p
    TT = _tabeltype(prob.tables)
    TN = _newtab(TT, eltype(typeof(p)), ix, p)
    istab(x) = table_key(ix, first(x)) !== nothing
    TN === TT && !any(istab, p) && return prob.tables, p
    tables = Pair{String, Vector{TN}}[k => Vector{TN}(v) for (k, v) in prob.tables]
    for x in p
        k, v = first(x), last(x)
        t = table_key(ix, k)
        t === nothing && continue
        e = table_entry(ix, k)
        e == 0 || throw(ArgumentError("`$k` is entry $e of the table `$t`: give the whole table, `$t => values`"))
        j = findfirst(x -> first(x) == t, tables)
        n = length(last(tables[j]))
        v isa AbstractArray && length(v) == n || throw(ArgumentError(
            "the table `$k` has $n entries; give $n values (got $(v isa AbstractArray ? length(v) : v))"))
        w = Vector{TN}(vec(collect(v)))
        all(isfinite, w) || throw(ArgumentError("the table `$t` must hold finite values (got $w)"))
        tables[j] = t => w
    end
    return tables, filter(!istab, p)
end
_newtab(::Type{TT}, ::Type{Pair{K, V}}, ix, p) where {TT, K, V <: AbstractArray} =
    isconcretetype(eltype(V)) ? promote_type(TT, eltype(V)) : _newtab(TT, Any, ix, p)
_newtab(::Type{TT}, ::Type{Pair{K, V}}, ix, p) where {TT, K, V <: Real} =
    isconcretetype(V) ? TT : _newtab(TT, Any, ix, p)
_newtab(::Type{TT}, _, ix, p) where {TT} =
    foldl((T, x) -> table_key(ix, first(x)) !== nothing && last(x) isa AbstractArray ? promote_type(T, _tabelt(last(x))) : T,
        p; init = TT)
_parameter_vector(::FieldProblem, p::AbstractVector{<:Real}) = collect(p)
_parameter_vector(prob::FieldProblem, p) = _pairs_vector(prob, p)
# the parameter type after pairs `p`: the problem's, promoted only by a Dual value (a plain
# value is written into the problem's type: plain parameters never promote, P5); from the
# pair type when its value type is concrete, else from the values
_pairtype(::Type{E}, ::Type{Pair{K, V}}, p) where {E, K, V} =
    isconcretetype(V) ? (V <: Real ? promote_dual(E, V) : E) : _pairtype(E, Any, p)
_pairtype(::Type{E}, _, p) where {E} = foldl((T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) : T, p; init = E)
function _pairs_vector(prob::FieldProblem, p)
    pv = Vector{_pairtype(eltype(prob.p), eltype(typeof(p)), p)}(prob.p)
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
counts used: `substeps` the first group's (the only one's for one group), `counts` every
group's, in group order ([`substep_counts`](@ref)). Indexed by symbol through
SymbolicIndexingInterface: `sol[c]` is a vector of grid-shaped arrays, `sol[c, i]` one of
them, `sol(t; idxs = c)` the grid at time `t` (linear between the saves) and
[`field_series`](@ref)`(sol, c)` the time-first view, as on the owned `ODESolution` (ruling Q18). An aux field `K ~ rhs` (F3 design §3.12) is not in `u`: `aux` holds its values at each
save, evaluated from the saved state at the save time, and `sol[K]` reads them. `stats` holds
the solver counters of the groups' status words ([`field_stats`](@ref)).
"""
struct FieldSolution{P, U}
    prob::P
    t::Vector{Float64}
    u::Vector{U}
    retcode::SciMLBase.ReturnCode.T
    substeps::Int
    counts::Vector{Int}
    aux::Vector{U}                      # the aux fields at each save (flat, `_aux_layout`), or empty
    stats::@NamedTuple{solves::Int64, budget::Int64, floor::Int64, newton_budget::Int64}   # (`field_stats`)
end
SciMLBase.successful_retcode(s::FieldSolution) = SciMLBase.successful_retcode(s.retcode)

SII.is_timeseries(::Type{<:FieldSolution}) = SII.Timeseries()
SII.symbolic_container(s::FieldSolution) = s.prob.index
SII.state_values(s::FieldSolution) = s.u
SII.current_time(s::FieldSolution) = s.t
SII.parameter_values(s::FieldSolution) = s.prob.p
function Base.getindex(s::FieldSolution, sym)
    k = aux_key(s.prob.index, sym)
    k === nothing || return [_aux_read(s.prob.program, a, k) for a in s.aux]
    return SII.getsym(s, sym)(s)
end
function Base.getindex(s::FieldSolution, sym, i)
    k = aux_key(s.prob.index, sym)
    k === nothing || return _aux_read(s.prob.program, s.aux[i], k)
    return SII.getsym(s, sym)(s, i)
end

# The aux fields of a program (`K ~ rhs`: the fields its `aux:` kernels write, F3 design
# §3.12): their keys, and their ranges in a flat vector of saved aux values
_aux_keys(prog::Program) = String[k.key[(ncodeunits("aux:") + 1):end] for k in prog.kernels if startswith(k.key, "aux:")]
_aux_layout(prog::Program) = state_layout(prog, [fieldid(prog, k) for k in _aux_keys(prog)])
# aux field `k` in the flat saved values `flat`, grid-shaped
function _aux_read(prog::Program, flat, k)
    id = fieldid(prog, k)
    f = prog.fields[id]
    d = leveldims(prog, f.levels[1])
    return reshape(flat[_aux_layout(prog)[id]], ncomp(f) == 1 ? d : (d..., ncomp(f)))
end
Base.length(s::FieldSolution) = length(s.t)
# (`sol[c, end]`: the last save)
Base.lastindex(s::FieldSolution, d::Integer) = d == 2 ? length(s.t) :
    throw(ArgumentError("a FieldSolution is indexed `sol[c, i]` by a symbol and a save"))

"""
    FieldIntegrator

The integrator of an owned solve, a `SciMLBase.DEIntegrator` (F4-03; F4 design §3.4): the
store, the runtime of each field group ([`GroupRuntime`](@ref): its bound launches, clamps and
algorithm cache), the substep count (the first group's) and the saves. `integ.t` is the
current time and `integ.u` the current state (the store's current flat buffer, on the
problem's device, or a `MixedState`); `integ.sol` is the solution so far. `step!(integ)`
advances one window of `dt` ([`advance!`](@ref) of each group, in group order);
`step!(integ, dt, true)` lands on `integ.t + dt`; indexing by symbol reads (and sets) fields
of the current state.

**Windows off the grid.** The window `dt` is fixed: the windows end at `t₀ + k dt` (the grid).
A time off the grid that the run must land on (a `tstop`: [`add_tstop!`](@ref
SciMLBase.add_tstop!), `step!(integ, dt, true)`; the end of the time span) is reached by one
shortened window, and the next window is shortened to land back on the grid. In a shortened
window of length `w` each group takes `⌈n w / dt⌉` substeps of its count `n` (so no substep is
longer than in a full window); an implicit group rebuilds its operator for that step and back
(BDF2 starts again, Crank–Nicolson damps again: a new step is a start).

**State writes.** `integ[c] = values` and `setu` drop every group's algorithm history
([`reset!`](@ref)). A write into `integ.u` itself is not seen by the groups until
`derivative_discontinuity!(integ, true)` (or `u_modified!`), which drops it too.

Parameters and tables change only through `integ.ps[sym] = v` or `setp(integ, sym)(integ, v)`
(SymbolicIndexingInterface), which checks the faces, recomputes the substeps and rebinds the
steps, or else leaves the integrator unchanged. Writing `integ.p[i] = v` directly has no effect on the run: the steps
keep the values they were bound to.
"""
mutable struct FieldIntegrator{P <: FieldProblem, A, S <: FieldStore, RT <: Tuple, T, PV, TB, U} <:
               SciMLBase.DEIntegrator{A, true, U, Float64}
    prob::P
    alg::A
    store::S
    runtimes::RT                        # one `GroupRuntime` per field group, in group order
    p::PV
    pgood::PV                           # the parameters the steps are bound to
    tables::TB                          # its own copy (`integ.ps[Dk] = values`), as the problem's
    t0::Float64
    iter::Int                           # the grid windows done: the time is on the grid at `t0 + iter dt`, or past it
    dt::Float64
    substeps::Int
    nsteps::Int                         # the whole windows in the time span
    per::Int                            # windows per period of the clock (0: no clock)
    save::Vector{Float64}               # the save times, sorted
    ts::Vector{Float64}                 # the saved times …
    us::Vector{Vector{T}}               # … and states (flat, host)
    retcode::SciMLBase.ReturnCode.T
    aux::Any                            # the aux kernels bound at both parities, or nothing (F3-00)
    auxu::Vector{Vector{T}}             # the aux fields at each save (flat, `_aux_layout`)
    starts::Vector{Any}                 # the steady starts of the groups with `init = :steady` (F3-12c)
    tnow::Float64                       # the current time
    tend::Float64                       # the end of the time span
    tstops::Vector{Float64}             # the times to land on, sorted (`add_tstop!`)
    nsave::Int                          # the next save time's index in `save`
    windows::Int                        # every window stepped (shortened ones too)
    sciml::Any                          # the SciML problem solved (its solution's `prob`), or nothing
    cbs::Any                            # the callbacks (a `CallbackSet`), or nothing (F4-05)
    saveidxs::Any                       # the flat indices saved (`save_idxs`), or nothing
    everystep::Bool                     # save after every window
    maxiters::Int                       # the most windows
    modflag::Bool                       # a callback's affect changed the state (`derivative_discontinuity!`)
    prevu::Any                          # the state at the window's start (interpolated saves, events), or nothing
    prevaux::Any                        # … and its aux values
    tprev::Float64                      # … and its time
    syncs::Int                          # the host copies of a device state for callbacks and interpolated saves
    cprev::Any                          # the continuous callbacks' conditions at the window's start (F4-06)
    dense::Bool                         # the solution's `dense` (the `dense` keyword)
    prevbuf::Any                        # the host buffer `prevu` reuses (no copy allocated per window)
end


"""
    substeps(prob, alg, p = prob.p) -> Int

The substep count of `alg` on `prob` at parameters `p`: `⌈dt ρ(p) / 1.8⌉`; with a user
count `n`, the larger of `n` and the count of the bound over the terms the bound sees
([`seen_bound`](@ref)), or `n` when that is not finite; when the full bound is unknown the
count is the user's for the terms it does not cover, and a warning names them, once per
program, term and cause in a session ([`unbounded_key`](@ref): never once per value). An unknown bound with no user count is an `ArgumentError` that names the
terms the bound cannot see. A problem with no state (aux fields `K ~ rhs` only, F3 design
§3.12) takes 0 substeps: its window evaluates the aux fields once, and a count `substeps = n`
(a minimum) has nothing to step, so it changes nothing. This is the one policy of
both front ends, [`substeps`](@ref)`(spec, alg, dt, pp)` of the problem's group, in front end
B's words ([`ProblemTexts`](@ref)).
"""
substeps(::FieldProblem, ::ExplicitMap, p = nothing; tables = nothing, inputs = nothing, stability = nothing, fields = nothing) = 1

# the host values of the inputs the stability bound reads in an index (`bound_inputs`), each
# shaped by site (a number stays a number): from the problem, or from an integrator's store
_site_shaped(prog, k, v) = v isa Number ? v : reshape(collect(v), _input_dims(prog, prog.fields[fieldid(prog, k)]))
function _bound_inputs(prob::FieldProblem)
    ks = bound_inputs(prob.stability)
    out = Pair{String, Any}[]
    isempty(ks) && return out
    for (k, v) in prob.inputs
        k in ks && v !== nothing && push!(out, k => _site_shaped(prob.program, k, v))
    end
    return out
end
function _bound_inputs(i::FieldIntegrator; set = nothing)
    ks = bound_inputs(i.prob.stability)
    prog = i.prob.program
    return Pair{String, Any}[k => _site_shaped(prog, k, set !== nothing && first(set) == k ? last(set) :
                                                         Array(array(i.store, fieldid(prog, k), :cur))) for k in ks]
end
# the warning's once-key: the program (its printed text, hashed) and the value-free reason
_warn_key(prob::FieldProblem, why) = string(hash(sprint(print_program, prob.program)); base = 16) * "|" * string(why)
function substeps(prob::FieldProblem, alg::Union{ExplicitEuler, ImplicitAlgorithm}, p = prob.p; tables = prob.tables,
        inputs = _bound_inputs(prob), stability = prob.stability, fields = prob.group.spec.state)
    dt = _window(alg, _clock(prob))
    isempty(prob.state) && return 0                 # aux fields only: one evaluation per window
    pp = with_tables(map(primal, p), tables; inputs)        # a policy: on the primal values
    # the one policy of both front ends (F3-01), in front end B's words
    return substeps(prob.group.spec, alg, dt, pp; fields, stability, key = why -> _warn_key(prob, why),
        texts = ProblemTexts(prob.group.spec.texts.route), (alg isa ExplicitEuler ? (; span = prob.tspan) : (;))...)
end

# whole number of `dt` in `span` (to a relative 1e-5, so `dt = 1f-2` counts 0.01), else an
# error that names the window as it was set (`window`: the text of `_wtext`) and a route
_whole(span, dt) = (n = round(Int, span / dt); abs(n * dt - span) <= 1e-5 * max(dt, abs(span)))
function _count(span, dt, what; window = string("dt = ", dt), route = "")
    _whole(span, dt) || throw(ArgumentError(string(what, " = ", span, " is not a whole number of windows (",
        window, ")", route)))
    return round(Int, span / dt)
end
# the window of `alg` in messages: its `dt` as given, or the clock's period when `dt` is left out
_wtext(::ExplicitMap, clock, dt) = "one map step, 1"
_wtext(a::FieldAlgorithm, clock, dt) = a.dt === nothing ? string("the window ", dt, ": the clock's period, no `dt` given") :
                                       string("dt = ", dt)
# the largest `clock / n` (n ≤ 10⁴) that divides `span`, else `nothing`: a `dt` that lands on
# both (a route in the messages)
function _divider(span, clock)
    for n in 1:10_000
        d = clock / n
        _whole(span, d) && return d
    end
    return nothing
end
# the route of a span or save interval `span` that the window `dt` of `alg` does not divide
function _count_route(alg, clock, dt, span, what)
    alg isa ExplicitMap && return string("; give ", what, " a whole number of map steps")
    d = clock === nothing ? nothing : _divider(span, clock)
    give = d === nothing ? string(what, " a multiple of ", dt) :
           string(what, " a multiple of ", dt, ", or `", nameof(typeof(alg)), "(; dt = ", d, ")` (it divides both ", what,
                  " and the clock's period ", clock, ")")
    return string("; give ", give)
end

# the field groups of `alg` on `prob`: `(algorithm, state keys)`, the QuasiSteady groups first
# and each kind in state order (F3 design §3.5: a steady field is solved before the transient
# fields that read it, from their window-start values). A single algorithm steps every state
# field, except the steady rows `0 ~ rhs` (F3-12b), which take `QuasiSteady` at its window
function _groups(prob::FieldProblem, alg::FieldAlgorithm)
    st = prob.group.spec.steady
    (isempty(st) || alg isa QuasiSteady) && return Tuple{FieldAlgorithm, Vector{String}}[(alg, prob.state)]
    rest = String[k for k in prob.state if !(k in st)]
    isempty(rest) && throw(ArgumentError(string(_algtext(alg), ": every field of the problem has a steady equation ",
        "`0 ~ rhs` (", join(("`$k`" for k in st), ", "), "), which `QuasiSteady` solves (a steady row's one algorithm); ",
        "solve it with `QuasiSteady(; dt)`, or write the rows as rates `D(c) ~ rhs` to step them")))
    return Tuple{FieldAlgorithm, Vector{String}}[(steady_alg(alg), String[k for k in prob.state if k in st]), (alg, rest)]
end
_alg_dt(a::FieldAlgorithm) = hasproperty(a, :dt) ? getproperty(a, :dt) : nothing
"""
    steady_alg(alg) -> QuasiSteady

The algorithm of a steady row `0 ~ rhs` that no pair names, beside `alg` (F3-12b, both front
ends): `QuasiSteady` at `alg`'s window, with its `inner` and `solver_T` when it has them.
"""
steady_alg(a) = a isa QuasiSteady ? a :
                QuasiSteady(; dt = _alg_dt(a), inner = a isa ImplicitAlgorithm ? a.inner : :auto,
                    solver_T = a isa ImplicitAlgorithm ? a.solver_T : :auto, init = starts_steady(a) ? :steady : nothing)
"""
    starts_steady(alg) -> Bool

Whether `alg` has `init = :steady`: its group starts at its steady state ([`steady_start`](@ref)).
"""
starts_steady(a) = hasproperty(a, :init) && getproperty(a, :init) === :steady
# a steady row's algorithm: `QuasiSteady` only (F3-12b)
function _check_steady(prob::FieldProblem, key, a)
    a isa QuasiSteady && return nothing
    throw(ArgumentError(string("FieldGroups: the field `", key, "` has a steady equation `0 ~ rhs`, which `QuasiSteady` ",
        "solves (a steady row's one algorithm); got `", key, " => ", _algtext(a), "`: give `", key, " => QuasiSteady()` ",
        "or leave it out (a steady field takes `QuasiSteady` by default), or write its row as a rate `D(", key,
        ") ~ rhs` to step it")))
end
_qs_first(out) = [filter(x -> x[1] isa QuasiSteady, out); filter(x -> !(x[1] isa QuasiSteady), out)]
function _groups(prob::FieldProblem, g::FieldGroups)
    # aux fields only (no state, F3 design §3.12): one group with no field, which evaluates them
    # once per window; `default` (or any pair's algorithm) sets the window
    if isempty(prob.state)
        why = "the problem has no state field (its fields are aux fields `K ~ rhs`, evaluated once per window)"
        for (k, _) in g.pairs
            throw(ArgumentError(string("FieldGroups: `", _symtext(k), "` is not a state field: ", why,
                "; give only `default`, an algorithm whose `dt` sets the window")))
        end
        g.default === nothing && throw(ArgumentError(string("FieldGroups: ", why,
            "; give `default`, an algorithm whose `dt` sets the window")))
        return Tuple{FieldAlgorithm, Vector{String}}[(g.default, String[])]
    end
    assigned = Dict{String, FieldAlgorithm}()
    for (k, a) in g.pairs
        key = _state_key(prob, k)
        haskey(assigned, key) && throw(ArgumentError("FieldGroups: the field `$key` has two algorithms"))
        assigned[key] = a
    end
    out = Tuple{FieldAlgorithm, Vector{String}}[]
    st = prob.group.spec.steady
    for (k, a) in assigned
        k in st && _check_steady(prob, k, a)
    end
    # a steady field with no pair takes `QuasiSteady` beside the default (or, with none, at the
    # window of the pairs)
    wdt = something((_alg_dt(a) for (_, a) in g.pairs)..., Some(nothing))
    sa = g.default === nothing ? QuasiSteady(; dt = wdt) : steady_alg(g.default)
    for k in prob.state
        a = haskey(assigned, k) ? assigned[k] : k in st ? sa : g.default
        a === nothing && throw(ArgumentError(string("FieldGroups: the field `", k, "` has no algorithm; ",
            "pair it with one (`", k, " => alg`) or give `default`")))
        j = findfirst(x -> isequal(x[1], a), out)
        j === nothing ? push!(out, (a, [k])) : push!(out[j][2], k)
    end
    length(unique(alg_family(a) for (a, _) in out)) == 1 || throw(ArgumentError(string(
        "FieldGroups: a rate algorithm and a map algorithm are never mixed in one problem ",
        "(split stepping is planned); got ", join((_algtext(a) for (a, _) in out), ", "))))
    ws = [(a, _window(a, _clock(prob))) for (a, _) in out]
    dts = unique(last.(ws))
    length(dts) == 1 || throw(ArgumentError(string("FieldGroups: every group steps the same window; ",
        "the algorithms give ", join(unique(_wtext(a, _clock(prob), d) for (a, d) in ws), ", "),
        ": give every algorithm one `dt`, such as `dt = ", minimum(dts), "`")))
    return _qs_first(out)
end
# the state key of field `k` (a symbol of the index, or the key itself)
function _state_key(prob::FieldProblem, k)
    k isa Union{AbstractString, Symbol} && String(k) in prob.state && return String(k)
    ix = prob.index
    slot = ix isa LatticeIndex ? _slot(ix, k) : nothing
    if slot !== nothing
        prog = prob.program
        ranges = state_layout(prog, [fieldid(prog, s) for s in prob.state])
        for s in prob.state
            ranges[fieldid(prog, s)] == slot.range && return s
        end
    end
    throw(ArgumentError(string("FieldGroups: `", _symtext(k), "` is not a state field of the problem; its fields: ",
        join(("`$s`" for s in prob.state), ", "))))
end

CommonSolve.init(::FieldProblem, alg::LinearSolver; kw...) =
    throw(linear_solver_refusal("`solve`/`init`", alg, "`solve(prob, ExplicitEuler(; dt))`"))

# the save times (F4-05), sorted, one per time within `1e-9 dt` (concrete arguments: cached by
# the precompile workload, whatever the problem)
_saveat_grid(t0::Float64, tf::Float64, h::Float64) =
    h > 0 ? Float64[t0 + m * h for m in 1:floor(Int, (tf - t0) / h + 1e-9)] : Float64[]
function _save_times(t0::Float64, tf::Float64, dt::Float64, save_start::Bool, save_end::Bool, sat::Vector{Float64})
    save = Float64[]
    save_start && push!(save, t0)
    append!(save, sat)
    save_end && push!(save, tf)
    filter!(x -> t0 - 1e-9dt <= x <= tf + 1e-9dt, save)
    # sorted, then a time within `1e-9 dt` of the one kept before it is dropped (no conversion to
    # an integer count: a long span over a short `dt` overflows `Int`, batch-end review (g))
    sort!(save)
    out = Float64[]
    for x in save
        isempty(out) || x - last(out) > 1e-9dt || continue
        push!(out, x)
    end
    return out
end
# a map saves whole steps only
_map_saveat(sat, t0, dt, a1, clock) = foreach(s -> _whole(s - t0, dt) || _count(s - t0, dt, "a saveat time";
    window = _wtext(a1, clock, dt), route = _count_route(a1, clock, dt, s - t0, "the saveat times")), sat)

function CommonSolve.init(prob::FieldProblem, alg::FieldAlgorithm; saveat = (), save_start::Bool = true,
        save_end::Bool = true, save_everystep::Bool = false, save_on::Bool = true, save_idxs = nothing,
        callback = nothing, tstops = (), maxiters::Integer = typemax(Int), verbose = true, alias_u0::Bool = false,
        dense::Bool = true, _sciml = nothing, kw...)
    isempty(kw) || throw(ArgumentError(string("`solve`/`init` with ", _algtext(alg), ": the keyword",
        length(kw) == 1 ? " " : "s ", join(("`$k`" for k in keys(kw)), ", "), length(kw) == 1 ? " is" : " are",
        " not one of a field algorithm's (it steps fixed windows of `dt`): `saveat`, `save_start`, `save_end`, ",
        "`save_everystep`, `save_on`, `save_idxs`, `callback`, `tstops`, `maxiters`, `verbose`, `alias_u0`, `dense`")))
    prob.group.spec.timefree && prob.tspan == (0.0, 0.0) && throw(ArgumentError(string("`init`: the system has no time ",
        "(a steady system), so there is nothing to step; `solve(prob)` solves it once")))
    groups = _groups(prob, alg)
    for (a, _) in groups
        alg_family(a) == prob.kind || throw(ArgumentError(string(
            "a ", prob.kind == :map ? "map program is stepped by ExplicitMap()" :
                  "rate program is stepped by ExplicitEuler(; dt)",
            "; got ",
            _algtext(a))))
        _window(a, _clock(prob))
    end
    check_faces(prob.faces, prob.p)
    check_values(prob.p, prob.index)
    check_parameters(prob.stability, with_tables(map(primal, prob.p), prob.tables; inputs = _bound_inputs(prob)))
    t0, tf = prob.tspan
    a1, clock = first(groups[1]), _clock(prob)
    w = _window(a1, clock)
    # a time span that is not a whole number of windows ends with one shortened window (F4-03)
    whole = _whole(tf - t0, w)
    # (a map steps whole steps only: no shortened step)
    whole || prob.kind != :map || _count(tf - t0, w, "the time span"; window = _wtext(a1, clock, w),
        route = _count_route(a1, clock, w, tf - t0, "the time span"))
    nsteps = whole ? round(Int, (tf - t0) / w) : floor(Int, (tf - t0) / w)
    dt = whole && nsteps > 0 ? (tf - t0) / nsteps : Float64(w)     # (whole: the step that lands on tf exactly)
    # the save times (F4-05): a time off the grid is the linear interpolation of the states at the
    # ends of its window (Q2 (a): no extra window); a map saves whole steps only
    sat = !save_on ? Float64[] : saveat isa Real ? _saveat_grid(t0, tf, Float64(saveat)) : Float64[s for s in saveat]
    prob.kind == :map && !isempty(sat) && Base.inferencebarrier(_map_saveat)(sat, t0, dt, a1, clock)
    save = _save_times(t0, tf, dt, save_start, save_end, sat)
    E = eltype(prob)
    # the state buffers the algorithms declare (`nbuffers`: two for the explicit ones)
    st = FieldStore(prob.backend, prob.program; flat = prob.state, E,
        nbuf = maximum(nbuffers(a) for (a, _) in groups), TE = _tabeltype(prob.tables))
    for (k, v) in prob.tables
        settable!(st, prob.program, k, v)
    end
    upload_inputs!(st, prob.program, prob.inputs; index = prob.index)
    _load_state!(st, prob.u0)
    # each group's count from the bound of its own rows (`restrict_bound`; one group: the
    # problem's bound)
    ms = [length(groups) == 1 ? substeps(prob, a) :
          substeps(prob, a, prob.p; tables = prob.tables, inputs = _bound_inputs(prob),
              stability = restrict_bound(prob.stability, ks), fields = ks) for (a, ks) in groups]
    _check_coupling(prob, groups, prob.p; dt)
    run_step!(prob.backend, prob.program, prob.init, st, prob.p; rt = (t0, dt, 0), c = zero(E))
    pgood = copy(prob.p)
    # one group steps in alternating slots; several end each step in slot 1, so the next
    # group reads current values
    ends_in = length(groups) == 1 ? :parity : :slot1
    # (`groups` holds abstract `FieldAlgorithm`s: through the barrier each group binds at its
    # own algorithm's type, and inference of an explicit `init` does not walk `bind_cache`'s
    # implicit method, the operator build and the solver; F3 review round 2)
    rts = Tuple(Base.inferencebarrier(bind_group)(prob.group, a, st, pgood; fields = ks, n = m, dt,
                    c = zero(E), ends_in, backend = prob.backend, options = prob.options, V = valtype(E))
                for ((a, ks), m) in zip(groups, ms))
    foreach(clamp_now!, rts)                        # the saved t0 state holds the mask values
    foreach(rt -> compile!(prob.backend, rt), rts)
    aux = _bind_aux(prob, st, pgood)
    aux === nothing || compile!(prob.backend, aux[1])
    T = _ueltype(st, E)
    tabs = eltype(prob.tables)[k => copy(v) for (k, v) in prob.tables]
    pv = copy(prob.p)
    integ = FieldIntegrator{typeof(prob), typeof(alg), typeof(st), typeof(rts), T, typeof(pv), typeof(tabs),
                            _utype(st, E)}(prob, alg, st, rts, pv, pgood, tabs, t0, 0, dt, ms[1], nsteps,
        _clock(prob) === nothing ? 0 : _per(dt, _clock(prob)), save, Float64[], Vector{T}[], SciMLBase.ReturnCode.Success,
        aux, Vector{T}[], Any[], t0, tf, Float64[], 1, 0, _sciml, nothing, _save_indices(prob, save_idxs),
        save_everystep, Int(maxiters), false, nothing, nothing, t0, 0, nothing, dense, nothing)
    for ts in tstops
        t0 < ts <= tf + 1e-9dt && SciMLBase.add_tstop!(integ, ts)
    end
    # (behind a barrier: an `init` with no steady start does not compile the steady policy)
    any(g -> starts_steady(g[1]), groups) && Base.inferencebarrier(_steady_starts!)(integ, groups)
    _saves!(integ)
    # the callbacks (behind a barrier: an `init` with none compiles none of their code)
    callback === nothing || Base.inferencebarrier(_init_callbacks!)(integ, callback)
    return integ
end
# `save_idxs`: the flat indices of the fields (symbols) or the indices given
function _save_indices(prob::FieldProblem, idxs)
    idxs === nothing && return nothing
    out = Int[]
    for i in (idxs isa Union{AbstractVector, Tuple} ? idxs : (idxs,))
        if i isa Integer
            push!(out, i)
            continue
        end
        ix = prob.index
        slot = ix isa LatticeIndex ? get(ix.vars, ix.key(i), nothing) : nothing
        slot isa FieldSlot || throw(ArgumentError(string("save_idxs: `", _symtext(i), "` is not a state field of the ",
            "problem; give state fields or flat indices")))
        append!(out, slot.range)
    end
    return out
end
# the type of `integ.u`: the store's flat buffer (a `MixedState` for a mixed store)
_utype(st::FieldStore, ::Type{E}) where {E} = mixed_state(st) ? MixedState : isempty(st.flat) ? Vector{E} : typeof(st.flat[1])

# The steady starts (`init = :steady` on a group's algorithm, F3-12c): before the first window
# each such group's steady state `0 = r(u)` is solved once by `QuasiSteady` (`steady_start`),
# in group order (the QuasiSteady groups first), at the start time from the state as it is, on
# a runtime of its own bound to the same arrays (`ends_in = :slot1`: the fields in slot 1,
# where the steps start). Its status is read at once: a failure becomes `integ.retcode` and
# the run does not step. Bound again at each `reinit!` (the parameters may have changed).
function _steady_starts!(integ::FieldIntegrator, groups)
    prob, st, E = integ.prob, integ.store, eltype(integ.prob)
    empty!(integ.starts)
    for (a, ks) in groups
        starts_steady(a) || continue
        qa = steady_start(a, integ.dt)
        rt = _start_bind(ks) do
            # (the steady refusals first: a growth, no unique steady state)
            substeps(prob, qa, integ.pgood; tables = integ.tables, inputs = _bound_inputs(integ),
                stability = restrict_bound(prob.stability, ks), fields = ks)
            Base.inferencebarrier(bind_group)(prob.group, qa, st, integ.pgood; fields = ks, n = 1,
                dt = integ.dt, c = zero(E), ends_in = :slot1, backend = prob.backend, options = prob.options, V = valtype(E))
        end
        rt.totals.where = StartText()
        compile!(prob.backend, rt)
        push!(integ.starts, rt)
        code = _worse(advance!(rt, (_time(integ), _tick(integ))), check_status!(rt))
        code == SciMLBase.ReturnCode.Success || !_running(integ.retcode) || (integ.retcode = code)
        _running(code) || break
    end
    return nothing
end
"""
    steady_start(alg, dt) -> QuasiSteady

The steady solve of `alg`'s `init = :steady` (F3-12c, both front ends): `QuasiSteady` at the
window `dt` with `alg`'s `inner` and `solver_T` (and `newton` for a `QuasiSteady` group);
`inner = :auto` takes `DevicePCG` to `rtol = 1e-6` within 64 iterations (`STEADY_INNER`), the
host-checked steady solve of a system with no time.
"""
steady_start(a, dt) = QuasiSteady(; dt, newton = a isa QuasiSteady ? a.newton : nothing,
    inner = a isa ImplicitAlgorithm && a.inner !== :auto ? a.inner : STEADY_INNER,
    solver_T = a isa ImplicitAlgorithm ? a.solver_T : :auto)
"""
    StartSubsteps(rule, keys)

The substep rule of a steady start in front end A (`init = :steady`, F3-12c): `rule(pp)` (the
`QuasiSteady` policy: its steady refusals), whose refusal names `init` and its route.
"""
struct StartSubsteps{R}
    rule::R
    keys::Vector{String}
end
(s::StartSubsteps)(pp) = _start_bind(() -> s.rule(pp), s.keys)
# a steady start's refusal (a growth, no unique steady state) names `init` and its route
function _start_bind(f, ks)
    try
        return f()
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError(string("`init = :steady` of ", _fieldlist(ks), ": ", err.msg, "; or leave `init` out (the ",
            "run starts from the initial state)")))
    end
end
"""
    StartText()

The steady start in a runtime's messages (`totals.where`): "the steady start (`init = :steady`, t = …)".
"""
struct StartText end
(::StartText)(w, t1) = string("the steady start (`init = :steady`, t = ", round(t1; sigdigits = 6), ")")

# The aux kernels of a problem alone (`K ~ rhs`, F3 design §3.12), bound at both slot parities
# to the parameters `p`, or `nothing` when it has none. They run before each save and each
# read of an aux field, so a saved or read `K` is `rhs` of the state at that time (inside a
# step each substep computes them from the state before it, one substep behind a save)
function _bind_aux(prob::FieldProblem, st::FieldStore, p)
    s = prob.program
    ids = [i for (i, k) in enumerate(s.kernels) if startswith(k.key, "aux:")]
    isempty(ids) && return nothing
    E = eltype(prob)
    _, sp = group_plans(prob.group, _default_alg(prob), valtype(E), prob.backend, prob.options; kernels = (Int[], ids))
    return _bind_steps(prob.backend, s, sp, st, p, prob.step.swaps, true, zero(E))
end
# evaluate the aux fields now, from the current state at the current time and step index
_eval_aux!(integ::FieldIntegrator) =
    (integ.aux === nothing || integ.aux[_parity(integ)]((_time(integ), integ.dt, _tick(integ))); nothing)
# the aux fields' current values, flat (`_aux_layout`), on the host
function _aux_values(integ::FieldIntegrator)
    prog = integ.prob.program
    out = eltype(integ.auxu)()
    for k in _aux_keys(prog)
        append!(out, Array(array(integ.store, fieldid(prog, k), :cur)))
    end
    return out
end

function _parity(integ::FieldIntegrator)
    isempty(integ.prob.step.swaps) ? 1 :
    integ.store.cur[integ.prob.step.swaps[1]]
end
_time(integ::FieldIntegrator) = getfield(integ, :tnow)
# The clock's step index of the current window: the clock boundaries reached since the start
# of the time span, by integer bookkeeping (each period holds `per` windows, and no window
# crosses a boundary), never from a float time; the window count without a clock
_tick(integ::FieldIntegrator) = integ.per == 0 ? integ.iter : div(integ.iter, integ.per)

# `u0` (flat, host) into every state buffer, the state in slot 1
function _load_state!(st::FieldStore, u0)
    if mixed_state(st)                              # (each state field its own arrays, S2)
        for i in _state_ids(st)
            v = view(u0, st.slots[i])
            foreach(b -> copyto!(b, convert(Vector{eltype(b)}, collect(v))), st.bufs[i])
        end
        return st
    end
    isempty(st.flat) && return st
    copyto!(st.flat[1], convert(Vector{eltype(st.flat[1])}, u0))
    foreach(b -> copyto!(b, st.flat[1]), st.flat[2:end])
    return st
end

"""
    step!(integ)

One step of `dt`: [`advance!`](@ref) of each field group in group order (its masks at the
step's start and the masked values at the sites they mark, when the problem has masked
conditions, then its substeps, alternating the slot parity). With a clock (`clock = τ` on the
discretization), the step index `k` that `step_index(t)` reads is the number of clock
boundaries reached since the start of the time span, kept as an integer. A group's return
code other than `ReturnCode.Success` becomes `integ.retcode`; a failure (a code other than
`StalledSuccess`) also stops the step, so the later groups do not run, and `solve!` stops on
it. On the host the groups' status words are read after the step
([`check_status!`](@ref)): a `ConvergenceFailure` stops the run, a `StalledSuccess` is kept as
the code and the run goes on. On a device they are read at the saves and at the end.
"""
function CommonSolve.step!(integ::FieldIntegrator)
    t, dt = _time(integ), integ.dt
    target, full = _window_end!(integ)
    # the state at the window's start, when a save falls inside the window or an event may
    # (a continuous callback): one host copy. The rare paths sit behind barriers, and the time
    # logic is in small functions: a run on the grid compiles little (design §6)
    _needs_prev(integ, target) && _keep_prev!(integ, t)
    code = full ? _advance_all(integ.runtimes, (t, _tick(integ))) :
           Base.inferencebarrier(_advance_short)(integ.runtimes, (t, _tick(integ)), target - t, dt)::SciMLBase.ReturnCode.T
    _window_done!(integ, target)
    code == SciMLBase.ReturnCode.Success || (integ.retcode = code)
    # the status words: on the host after every step (a plain read; nothing for explicit groups)
    Exec.ishost(integ.prob.backend) && _check_statuses!(integ)
    # the callbacks (behind a barrier; none: no host read), then the saves due
    getfield(integ, :cbs) === nothing || Base.inferencebarrier(_apply_callbacks!)(integ)
    _saves!(integ)
    integ.everystep && (isempty(integ.ts) || integ.ts[end] != integ.tnow) && _save!(integ)
    integ.prevu = nothing
    _past_maxiters(integ) && Base.inferencebarrier(_maxiters!)(integ)
    return integ
end
# the window's end: the next grid time, or an earlier time to land on (a tstop, the end of the
# span); a time within `tol` of the grid lands with a full window, at that time
function _window_end!(integ::FieldIntegrator)
    t, dt = integ.tnow, integ.dt
    g = integ.t0 + (integ.iter + 1) * dt            # the next grid time
    tol = 1e-9 * dt
    target, full = g, abs(t - (integ.t0 + integ.iter * dt)) <= tol
    if t < integ.tend - tol && integ.tend < g + tol
        target, full = integ.tend, full && integ.tend > g - tol
    end
    tstops = integ.tstops
    while !isempty(tstops) && first(tstops) <= t + tol
        popfirst!(tstops)                           # (reached or passed)
    end
    if !isempty(tstops) && first(tstops) < target + tol
        ts = first(tstops)
        target, full = ts, full && ts > g - tol
    end
    return (target, full)::Tuple{Float64, Bool}
end
function _window_done!(integ::FieldIntegrator, target::Float64)
    dt = integ.dt
    tol = 1e-9 * dt
    target > integ.t0 + (integ.iter + 1) * dt - tol && (integ.iter += 1)   # (a window that ends on the grid)
    integ.tnow = target
    integ.windows += 1
    tstops = integ.tstops
    while !isempty(tstops) && first(tstops) <= target + tol
        popfirst!(tstops)
    end
    return nothing
end
_past_maxiters(integ::FieldIntegrator) = integ.windows >= integ.maxiters && _running(integ.retcode) &&
    integ.tnow < integ.tend - 1e-9 * integ.dt
@noinline function _maxiters!(integ::FieldIntegrator)
    @warn string("the run stopped after maxiters = ", integ.maxiters, " windows at t = ", _num(_time(integ)),
        ": `ReturnCode.MaxIters`; give a larger `maxiters`")
    integ.retcode = SciMLBase.ReturnCode.MaxIters
    return nothing
end
function _needs_prev(integ::FieldIntegrator, target::Float64)
    integ.cprev === nothing || return true
    k = integ.nsave
    return k <= length(integ.save) && integ.save[k] < target - 1e-9 * integ.dt
end
_prev_aux(integ::FieldIntegrator) = (_eval_aux!(integ); _aux_values(integ))
function _keep_prev!(integ::FieldIntegrator, t)
    Exec.ishost(integ.prob.backend) || (integ.syncs += 1)
    integ.prevu = integ.prevbuf = _current!(integ.prevbuf, integ)
    integ.prevaux = integ.aux === nothing ? nothing : Base.inferencebarrier(_prev_aux)(integ)
    integ.tprev = t
    return nothing
end
# a shortened window of length `w` (a time off the grid, F4-03): each group takes
# `⌈n w / dt⌉` of its `n` substeps (none longer than in a full window)
_advance_short(::Tuple{}, clock, w::Float64, dt::Float64) = SciMLBase.ReturnCode.Success
function _advance_short(rts::Tuple, clock, w::Float64, dt::Float64)
    rt = first(rts)
    code = advance!(rt, clock, _short_count(rt.n, w, dt), w)
    _running(code) || return code
    return _worse(code, _advance_short(Base.tail(rts), clock, w, dt))
end
_short_count(n::Integer, w, dt) = n == 0 ? 0 : max(1, ceil(Int, n * w / dt - 1e-9))
# the saves due at the current time (the save times are on the grid or at the end of the span)
function _saves!(integ::FieldIntegrator)
    # none due; one, at the window's end (the usual case); anything else (an off-grid save
    # inside the window, Q2 (a)) behind a barrier, so a run without one compiles none of the
    # interpolation (first-init compile, design §6)
    case = _save_case(integ)
    case == 0 && return nothing
    if case == 1
        _save!(integ, integ.save[integ.nsave - 1], _current(integ), nothing)   # (the save time itself)
    elseif case == 2
        Base.inferencebarrier(_saves_window!)(integ)
    end
    return nothing
end
# 0: no save due; 1: one save, at the window's end (taken); 2: the general case; 3: the one
# save due was taken already (the index moves on)
function _save_case(integ::FieldIntegrator)
    tol = 1e-9 * integ.dt
    save, k, tnow = integ.save, integ.nsave, integ.tnow
    (k > length(save) || save[k] > tnow + tol) && return 0
    abs(save[k] - tnow) <= tol && (k == length(save) || save[k + 1] > tnow + tol) || return 2
    integ.nsave = k + 1
    return isempty(integ.ts) || integ.ts[end] != save[k] ? 1 : 3
end
@noinline function _saves_window!(integ::FieldIntegrator)
    tol = 1e-9 * integ.dt
    save, k = integ.save, integ.nsave
    cur = nothing
    while k <= length(save) && save[k] <= integ.tnow + tol
        s = save[k]
        if abs(s - integ.tnow) <= tol
            (isempty(integ.ts) || integ.ts[end] != s) && _save!(integ, s, _current(integ), nothing)
        elseif integ.prevu !== nothing && s > integ.tprev
            # (Q2 (a)) linear in time between the window's ends
            cur === nothing && (cur = _current(integ); Exec.ishost(integ.prob.backend) || (integ.syncs += 1))
            θ = (s - integ.tprev) / (integ.tnow - integ.tprev)
            u = integ.prevu .+ θ .* (cur .- integ.prevu)
            a = integ.prevaux === nothing ? nothing : (integ.prevaux .+ θ .* (_aux_now(integ) .- integ.prevaux))
            _save!(integ, s, u, a)
        end
        k += 1
    end
    integ.nsave = k
    return nothing
end
_aux_now(integ::FieldIntegrator) = (_eval_aux!(integ); _aux_values(integ))

"""
    step!(integ, dt, stop_at_tdt = false)

Step `integ` by windows until its time reaches `integ.t + dt` (SciML's convention): with
`stop_at_tdt = true` the run lands on `integ.t + dt` exactly (a `tstop`: a shortened window
when it is off the grid), else it stops at the first window end at or past it. A failure
stops it ([`step!`](@ref CommonSolve.step!(::FieldIntegrator))).
"""
function CommonSolve.step!(integ::FieldIntegrator, dt::Real, stop_at_tdt::Bool = false)
    dt < 0 && throw(ArgumentError("step!(integ, dt): dt = $dt; an integrator does not step back"))
    next = _time(integ) + dt
    stop_at_tdt && SciMLBase.add_tstop!(integ, next)
    while _time(integ) < next - 1e-9 * integ.dt && _running(integ.retcode)
        CommonSolve.step!(integ)
    end
    return integ
end
# the status words of every group (F3 design §3.3): a failure becomes `integ.retcode` (the run
# stops), `StalledSuccess` too unless something worse happened (the run goes on)
function _check_statuses!(integ::FieldIntegrator)
    code = _check_all(integ.runtimes, SciMLBase.ReturnCode.Success)
    code == SciMLBase.ReturnCode.Success || !_running(integ.retcode) || (integ.retcode = code)
    return nothing
end
_check_all(::Tuple{}, code) = code
_check_all(rts::Tuple, code) = _check_all(Base.tail(rts), _worse(code, check_status!(first(rts))))
# a run goes on while its code is `Success` or `StalledSuccess` (a rounding floor, accepted)
_running(c::SciMLBase.ReturnCode.T) = c == SciMLBase.ReturnCode.Success || c == SciMLBase.ReturnCode.StalledSuccess
_advance_all(::Tuple{}, clock) = SciMLBase.ReturnCode.Success
# the groups in order; a failing group stops the step (the later groups do not run), a
# `StalledSuccess` (a rounding floor, accepted) does not: the step returns the worst code
function _advance_all(rts::Tuple, clock)
    code = advance!(first(rts), clock)
    _running(code) || return code
    return _worse(code, _advance_all(Base.tail(rts), clock))
end

"""
    reinit!(integ, u0 = integ.prob.u0)

Start `integ` again from the flat state `u0` at the problem's start time, with its current
parameters, tables and inputs: the saved states are dropped, the masks and the clamp run
again, every group's algorithm history is dropped ([`reset!`](@ref)) and the start state is
saved when the save times include it.
"""
function SciMLBase.reinit!(integ::FieldIntegrator, u0 = integ.prob.u0)
    length(u0) == length(integ.prob.u0) ||
        throw(ArgumentError("u0 has $(length(u0)) values; the state has $(length(integ.prob.u0))"))
    u0 === integ.prob.u0 || check_declared_state(integ.prob, u0, eachindex(u0), "starts at")
    st = integ.store
    foreach(f -> st.cur[f] = 1, integ.prob.step.swaps)
    _load_state!(st, u0)
    integ.iter = 0
    integ.tnow = integ.t0
    integ.nsave = 1
    integ.windows = 0
    integ.prevu = nothing
    empty!(integ.tstops)
    empty!(integ.ts)
    empty!(integ.us)
    empty!(integ.auxu)
    integ.retcode = SciMLBase.ReturnCode.Success
    _rerun_init!(integ, integ.pgood)
    foreach(reset!, integ.runtimes)
    foreach(clear_status!, integ.runtimes)          # a new run: no failure, no counters
    # the steady starts again, at the current parameters
    isempty(integ.starts) || Base.inferencebarrier(_steady_starts!)(integ, [(rt.alg, rt.keys) for rt in integ.runtimes])
    _saves!(integ)
    getfield(integ, :cbs) === nothing || Base.inferencebarrier(_initialize_callbacks!)(integ)
    return integ
end

# the saved state's element type: the state's storage (a mixed store: their promotion, so no
# field loses precision in a save; batch 5 review S2)
_ueltype(st::FieldStore, ::Type{E}) where {E} =
    mixed_state(st) ? mapreduce(i -> eltype(st.bufs[i][1]), promote_type, _state_ids(st)) :
    isempty(st.flat) ? E : eltype(st.flat[1])
function _current(integ::FieldIntegrator)
    st = integ.store
    if mixed_state(st)
        E = _ueltype(st, eltype(integ.prob))
        return reduce(vcat, (convert(Vector{E}, Array(array(st, i, :cur))) for i in _state_ids(st)))
    end
    return isempty(st.flat) ? eltype(integ.prob)[] : Array(st.flat[_parity(integ)])
end

# the current state into `dest` when it is a host vector of the state's size (else a new copy)
function _current!(dest, integ::FieldIntegrator)
    st = integ.store
    (mixed_state(st) || isempty(st.flat)) && return _current(integ)
    src = st.flat[_parity(integ)]
    dest isa Vector{eltype(src)} && length(dest) == length(src) || return _current(integ)
    return copyto!(dest, src)
end
# a saved state that is not finite ends the solve with `ReturnCode.Unstable`; the aux fields
# are evaluated at the save (one aux launch) and saved with it
_save!(integ::FieldIntegrator) = _save!(integ, _time(integ), _current(integ), nothing)
function _save!(integ::FieldIntegrator, t, u, a)
    _check_statuses!(integ)                      # (a save synchronizes anyway)
    push!(integ.ts, t)
    idx = getfield(integ, :saveidxs)
    push!(integ.us, idx === nothing ? u : u[idx])
    if integ.aux !== nothing
        push!(integ.auxu, a === nothing ? _aux_now(integ) : a)
    end
    _check_declared!(integ)                      # (the declared intervals: batch 5 review M2)
    _running(integ.retcode) && !all(isfinite, u) && Base.inferencebarrier(_unstable!)(integ, u)   # (a failure path: not compiled until taken)
    return nothing
end
# the declared intervals of every group (`check_declared!`): a field outside its interval ends
# the run with `ReturnCode.Unstable` (one warning names it)
function _check_declared!(integ::FieldIntegrator)
    code = _declared_all(integ.runtimes, SciMLBase.ReturnCode.Success)
    code == SciMLBase.ReturnCode.Success || !_running(integ.retcode) || (integ.retcode = code)
    return nothing
end
_declared_all(::Tuple{}, code) = code
_declared_all(rts::Tuple, code) = _declared_all(Base.tail(rts), _worse(code, check_declared!(first(rts))))
# a state that is not finite (batch 5 review N7): `ReturnCode.Unstable`, with one warning that
# names the fields and the routes
@noinline function _unstable!(integ::FieldIntegrator, u)
    integ.retcode = SciMLBase.ReturnCode.Unstable
    ix = integ.prob.index
    bad = String[]
    if ix isa LatticeIndex
        for k in integ.prob.state
            slot = get(ix.vars, ix.key(Symbol(k)), nothing)
            slot isa FieldSlot && !all(isfinite, view(u, slot.range)) && push!(bad, k)
        end
    end
    isempty(bad) && (bad = copy(integ.prob.state))
    @warn string("field", length(bad) == 1 ? " " : "s ", _fieldlist(bad), ": the state is not finite at t = ",
        _num(_time(integ)), " (the step is unstable): `ReturnCode.Unstable`, the run stops. Give more substeps ",
        "(`substeps = n`), or step the field", length(bad) == 1 ? "" : "s", " with `BackwardEuler`; a term the ",
        "stability bound cannot see (named when the count was set) is the usual cause")
    return nothing
end

function CommonSolve.solve!(integ::FieldIntegrator)
    finish!(integ)
    return _solution(integ)
end
"""
    finish!(integ) -> integ

The run of `solve!` without its solution: step to the end of the time span, then the checks
at the end (statuses, declared intervals, a state that is not finite; a failure saves the state
it stopped at). Inferred; `solve!` then builds the solution behind a barrier (F4-04).
"""
function finish!(integ::FieldIntegrator)
    while _time(integ) < integ.tend - 1e-9 * integ.dt && _running(integ.retcode)
        CommonSolve.step!(integ)
    end
    KA.synchronize(integ.prob.backend)
    getfield(integ, :cbs) === nothing || Base.inferencebarrier(_finalize_callbacks!)(integ)
    _check_statuses!(integ)
    _running(integ.retcode) && _check_declared!(integ)
    _running(integ.retcode) && (isempty(integ.ts) ||
     integ.ts[end] != _time(integ)) && (u = _current(integ); !all(isfinite, u)) && Base.inferencebarrier(_unstable!)(integ, u)
    # a failure stops the run: the state it stopped at is saved (as front end A does)
    !_running(integ.retcode) && (isempty(integ.ts) || integ.ts[end] != _time(integ)) && _save!(integ)
    return integ
end
# the solution so far: SciML's `ODESolution` of the problem solved (F4-04), or a `FieldSolution`
# for an owned problem stepped directly
function _solution(integ::FieldIntegrator)
    sp = getfield(integ, :sciml)
    sp === nothing && return FieldSolution(integ.prob, integ.ts, integ.us, integ.retcode, integ.substeps,
        substep_counts(integ), integ.auxu, field_stats(integ))
    return Base.inferencebarrier(_ode_solution)(integ, sp)
end

"""
    field_stats(integ) -> NamedTuple

The solver counters of an owned run (F3 design §3.3), summed over its groups' status words:
`solves`, `budget` (linear budget hits), `floor` (rounding floors), `newton_budget` (Newton
budget hits). All zero for the explicit algorithms. On a device, where a run reads the status
words only at the saves and at the end, it reads them first (one copy per group), so the counts
are current in the middle of a run too; a failure found there becomes `integ.retcode`, as at a save.
"""
function field_stats(integ::FieldIntegrator)
    Exec.ishost(integ.prob.backend) || _check_statuses!(integ)
    tot(f) = sum((getfield(rt.totals, f) for rt in Iterators.flatten((integ.runtimes, integ.starts))); init = Int64(0))
    return (; solves = tot(:solves), budget = tot(:budget), floor = tot(:floor), newton_budget = tot(:newton_budget))
end

# the default algorithm: `ExplicitEuler()` for rates (which needs `dt`: nothing else sets the
# window, and `saveat` never does; steady rows take `QuasiSteady`, `_groups`), `QuasiSteady()`
# when every row is steady, `ExplicitMap()` for maps
function _default_alg(prob::FieldProblem)
    prob.kind == :map && return ExplicitMap()
    st = prob.group.spec.steady
    return !isempty(prob.state) && all(k -> k in st, prob.state) ? QuasiSteady() : ExplicitEuler()
end
CommonSolve.init(prob::FieldProblem; kw...) = CommonSolve.init(prob, _default_alg(prob); kw...)
CommonSolve.solve(prob::FieldProblem; kw...) = CommonSolve.solve(prob, _default_alg(prob); kw...)
function CommonSolve.solve(prob::FieldProblem, alg::FieldAlgorithm; kw...)
    prob.group.spec.timefree && return _steady_solve(prob, alg; kw...)
    CommonSolve.solve!(
        CommonSolve.init(prob, alg; kw...))
end

"""
    steady_fields(prob) -> Vector{String}

The state fields of `prob` written as steady rows `0 ~ rhs` (each row's field by the rule of
`LatticePDE.steady_choice`), which `QuasiSteady` solves (F3-12b; review r3 N2).
"""
steady_fields(prob::FieldProblem) = copy(prob.group.spec.steady)
function Base.show(io::IO, ::MIME"text/plain", prob::FieldProblem)
    st = prob.group.spec.steady
    print(io, "FieldProblem (", prob.kind, ", ", join(Int.(leveldims(prob.program, 0)), "×"), " sites) of ",
        join(("`$k`" for k in prob.state), ", "))
    prob.group.spec.timefree ? print(io, "; no time (a steady system, solved once)") : print(io, "; tspan ", prob.tspan)
    isempty(st) || print(io, "\n  steady rows `0 ~ rhs` (`QuasiSteady`), solved for ", join(("`$k`" for k in st), ", "))
end

# A system with no time (F3 design §3.5, F3-12b): one steady solve from the cold `u0`, the
# host-checked path of `init = :steady` (the inner solver to `rtol = 1e-6` within 64
# iterations unless `inner` is given), returned as a one-state solution at t = 0
const STEADY_INNER = Solvers.DevicePCG(; budget = 64)
function _steady_solve(prob::FieldProblem, alg::FieldAlgorithm; kw...)
    alg isa QuasiSteady || throw(ArgumentError(string(_algtext(alg), ": the system has no time (a steady system, ",
        "solved once by `QuasiSteady`): `solve(prob)` or `solve(prob, QuasiSteady(; inner, newton))`")))
    alg.dt === nothing || throw(ArgumentError(string("QuasiSteady(; dt = ", alg.dt, "): the system has no time, ",
        "so there is no window; leave `dt` out")))
    isempty(kw) || throw(ArgumentError(string("`solve` of a system with no time takes no ",
        join(("`$k`" for k in keys(kw)), ", "), ": it is solved once and returns that one state")))
    a = QuasiSteady(; dt = 1.0, newton = alg.newton, inner = alg.inner === :auto ? STEADY_INNER : alg.inner,
        solver_T = alg.solver_T)
    s = CommonSolve.solve!(CommonSolve.init(SciMLBase.remake(prob; tspan = (0.0, 1.0)), a; save_start = false))
    return FieldSolution(prob, [0.0], s.u[end:end], s.retcode, s.substeps, s.counts, isempty(s.aux) ? s.aux : s.aux[end:end],
        s.stats)
end

SII.symbolic_container(i::FieldIntegrator) = i.prob.index
SII.state_values(i::FieldIntegrator) =
    mixed_state(i.store) ? MixedState(i.store, _ueltype(i.store, eltype(i.prob))) : i.store.flat[_parity(i)]
SII.parameter_values(i::FieldIntegrator) = i.p
SII.current_time(i::FieldIntegrator) = _time(i)
"""
    integ[sym]

The values of the field, input, aux field or observed quantity `sym` at the integrator's
current step; a list of symbols gives a list. An aux field (`K ~ rhs`) is evaluated from the
current state at the current time when read. A field or input comes back as a new array (on the problem's
device), a copy: writing into it, `integ[c][1, 1] = v`, changes nothing (SciML's convention);
assign the field, `integ[c] = values`. On a device the copy is a device array: compare it with
a device array, or take `Array(integ[c])` and compare host arrays.

Parameters and tables are read and written through `integ.ps` (SciML's convention, F2 design
§2.13): `integ.ps[k]`, `integ.ps[k] = v`, `integ.ps[Dk] = values`, `integ.ps[Dk[2]] = v`.
`integ[k]` and `integ[k] = v` of a parameter or table are errors that give that route.
"""
# SciMLBase's `DEIntegrator` methods for a list or a tuple would be ambiguous with these
Base.getindex(i::FieldIntegrator, sym) = _integ_getindex(i, sym)
Base.getindex(i::FieldIntegrator, sym::Union{Tuple, AbstractArray}) = _integ_getindex(i, sym)
function _integ_getindex(i::FieldIntegrator, sym)
    _parameter_route(i, sym, false)
    # a list reads each of its names (fields, inputs alike)
    sym isa Union{AbstractVector, Tuple} && i.prob.index isa LatticeIndex && return map(s -> i[s], sym isa Tuple ? sym : collect(sym))
    ka = aux_key(i.prob.index, sym)
    if ka !== nothing
        _eval_aux!(i)
        f = i.prob.program.fields[fieldid(i.prob.program, ka)]
        a = copy(array(i.store, fieldid(i.prob.program, ka), :cur))
        return reshape(a, ncomp(f) == 1 ? leveldims(i.prob.program, f.levels[1]) :
                          (leveldims(i.prob.program, f.levels[1])..., ncomp(f)))
    end
    k = i.prob.index isa LatticeIndex ? input_key(i.prob.index, sym) : nothing
    k === nothing && (_check_symbol(i, sym); return SII.getsym(i, sym)(i))
    f = i.prob.program.fields[fieldid(i.prob.program, k)]
    a = copy(array(i.store, fieldid(i.prob.program, k), :cur))
    # a Bool-declared input (stored as 0/1 bytes) reads back as Bool, on the problem's device
    is_bool_input(i.prob.index, k) && (a = map(!iszero, a))
    return reshape(a, ncomp(f) == 1 ? leveldims(i.prob.program, f.levels[1]) :
                      (leveldims(i.prob.program, f.levels[1])..., ncomp(f)))
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
# the clock's slot is the stepper's, not a parameter (review N6 of F2 batch 3)
_not_clock(sym) = sym isa Union{Symbol, AbstractString} && String(sym) == CLOCK_KEY && throw(ArgumentError(string(
    "`", CLOCK_KEY, "` is the clock's slot, which the stepper writes at every launch, not a parameter of the ",
    "problem: an equation reads the step index as `step_index(t)`")))
function SII.getp(sys::Union{FieldProblem, FieldIntegrator, FieldSolution}, sym)
    prob = sys isa FieldProblem ? sys : sys.prob
    ix = prob.index
    _not_clock(sym)
    # an input (a parameter of the `Discrete` portion, F4 design §3.3): its current values
    ki = ix isa LatticeIndex && !(sym isa Union{AbstractArray, Tuple, Integer}) ? input_key(ix, sym) : nothing
    ki === nothing || return x -> _read_input(x, ki)
    if ix isa LatticeIndex && _has_table(ix, sym)
        table_key(ix, sym) === nothing || return x -> _read_table(x, sym)
        gs = map(s -> SII.getp(sys, s), sym isa Tuple ? sym : collect(sym))
        return sym isa Tuple ? (x -> map(g -> g(x), gs)) : (x -> [g(x) for g in gs])
    end
    return invoke(SII.getp, Tuple{Any, Any}, sys, sym)
end
# input `k` of a problem (its values as given, shaped by site), an integrator (its store) or a
# solution (its problem's)
_read_input(i::FieldIntegrator, k) = i[k]
function _read_input(x::Union{FieldProblem, FieldSolution}, k)
    prob = x isa FieldProblem ? x : x.prob
    v = last(prob.inputs[findfirst(q -> first(q) == k, prob.inputs)])
    v isa AbstractArray || return v
    a = reshape(copy(v), _input_dims(prob.program, prob.program.fields[fieldid(prob.program, k)]))
    return is_bool_input(prob.index, k) ? map(!iszero, a) : a
end
# a symbol as the user wrote it: `:kind`, `"kind"`, or a variable without `⋆` and `(t, x, y)`
_symtext(sym::Union{Symbol, AbstractString}) = repr(sym)
_symtext(sym) = replace(string(sym), "⋆" => "", r"\(t(, \w+)*\)" => "")
# a parameter or table as written: a symbolic table by its key (`Dq`, not `Dq[1:2]`), an entry `Dq[2]`
function _ptext(ix, sym)
    sym isa Union{Symbol, AbstractString} && return _symtext(sym)
    t = ix isa LatticeIndex ? table_key(ix, sym) : nothing
    t === nothing && return _symtext(sym)
    e = table_entry(ix, sym)
    return e == 0 ? t : "$t[$e]"
end

# a write of an aux field (`integ[K] = v`): refused in the user's words, on the owned path
# (`_check_symbol`) and on the ODE path (`setsym` on an OrdinaryDiffEq integrator, the
# OrdinaryDiffEqCore extension; SII would say "Invalid symbol … for `setsym`")
_aux_write_text(sym) = string("`", _symtext(sym), "` is an aux field (`", _symtext(sym), " ~ rhs`), ",
    "evaluated from the state at each read and save; it cannot be written: write the fields it reads")
"""
    check_aux_write(ix, sym)

Throw an `ArgumentError` in the user's words when `sym` (or an entry of a list) is an aux field
of index `ix` (`K ~ rhs`: computed, never written); else nothing.
"""
function check_aux_write(ix, sym)
    sym isa Union{AbstractArray, Tuple} && (foreach(s -> check_aux_write(ix, s), sym); return nothing)
    ix isa LatticeIndex && aux_key(ix, sym) !== nothing && throw(ArgumentError(_aux_write_text(sym)))
    return nothing
end

# a symbol the integrator does not know is an error listing the names it does (rather than
# SII's "Invalid symbol"); a computed parameter says it is computed
function _check_symbol(i::FieldIntegrator, sym; write::Bool = false)
    ix = i.prob.index
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && (foreach(s -> _check_symbol(i, s; write), sym); return nothing)
    k = ix.key(sym)
    if haskey(ix.aux, k)
        write && throw(ArgumentError(_aux_write_text(sym)))
        return nothing
    end
    (haskey(ix.vars, k) || haskey(ix.params, k) || SII.is_independent_variable(ix, sym)) && return nothing
    if haskey(ix.observed, k) || haskey(ix.derived, k)
        write && SII.parameter_index(ix, sym)          # throws: it is computed
        return nothing
    end
    names = String[_symtext(s) for s in Iterators.flatten((ix.varsyms, ix.auxsyms, ix.paramsyms))]
    append!(names, values(ix.inputnames))
    append!(names, [k for k in values(ix.inputs) if !haskey(ix.inputnames, k)])
    append!(names, [first(v) for v in values(ix.tables) if last(v) == 0])
    throw(ArgumentError(string("`", _symtext(sym), "` names nothing of this problem; its names: ",
        join(("`$n`" for n in unique!(names)), ", "))))
end
# `integ[sym] .= v` would broadcast into the copy `getindex` returns and change nothing: it is
# an error that gives the assignment (F1)
function Base.dotview(i::FieldIntegrator, sym)
    _parameter_route(i, sym, true)
    sym = _symtext(sym)                            # as written (no `⋆`, no `(t, x, y)`)
    throw(ArgumentError(string("`integ[", sym, "] .= …` would write a copy (indexing an integrator ",
        "returns the field's values): assign the field, `integ[", sym, "] = values`")))
end
# `integ.ps[Dk] .= …` would broadcast into the copy `getp` returns: an error giving the assignment
function Base.dotview(p::SII.ParameterIndexingProxy{<:FieldIntegrator}, sym)
    t = _ptext(p.wrapped.prob.index, sym)
    throw(ArgumentError(string("`integ.ps[", t, "] .= …` would write a copy (`integ.ps[", t, "]` returns the ",
        "values): assign it, `integ.ps[", t, "] = values`")))
end
"""
    check_declared_state(prob, vals, idx, what)

The values `vals` written at the flat state indices `idx` of `prob` against the declared
intervals of its state fields ([`declared_intervals`](@ref); batch 5 review M2): the stability
bound takes those intervals for the coefficients that read the fields, so a value outside one
is refused before anything changes, naming the field, the value and the site (`what`: "starts
at" for `remake(; u0)` and `reinit!`, "is written" for a state write).
"""
function check_declared_state(prob::FieldProblem, vals, idx, what::AbstractString)
    decl = declared_intervals(prob.stability)
    (isempty(decl) || !(prob.index isa LatticeIndex)) && return nothing
    is = idx isa Integer ? (idx,) : idx isa Colon ? eachindex(prob.u0) : idx
    vals isa AbstractArray && !(vals isa Array) && (vals = Array(vals))      # (a device array: one copy, cold)
    for (k, (lo, hi)) in decl
        slot = get(prob.index.vars, prob.index.key(Symbol(k)), nothing)
        slot isa FieldSlot || continue
        for (j, q) in enumerate(is)
            q isa Integer && q in slot.range || continue
            v = primal(vals isa AbstractArray ? vals[firstindex(vals) + j - 1] : vals)
            lo <= v <= hi && continue
            site = Tuple(CartesianIndices(Tuple(slot.dims))[q - first(slot.range) + 1])
            throw(ArgumentError(string("field `", k, "` ", what, " ", v, " at site ", site, ", outside its declared bounds (",
                lo, ", ", hi, "): the stability bound takes that interval for the coefficients that read `", k, "`; ",
                what == "is written" ? "write values in its bounds" : "give it initial values in its bounds",
                ", or change `bounds` in its declaration")))
        end
    end
    return nothing
end

# a state written through `setu(integ, c)(integ, v)` drops every group's algorithm history, as
# `integ[c] = v` does
function SII.set_state!(i::FieldIntegrator, val, idx)
    check_declared_state(i.prob, val, idx, "is written")
    SII.state_values(i)[idx] = val
    foreach(reset!, i.runtimes)
    return val
end
# `integ[k]` or `integ[k] = v` of a parameter or table (a list naming one too): an error with
# SciML's route, `integ.ps[k]` (F2 design §2.13; before: read and written in place)
function _parameter_route(i::FieldIntegrator, sym, write::Bool)
    ix = i.prob.index
    ix isa LatticeIndex || return nothing
    if sym isa Union{AbstractVector, Tuple} && table_key(ix, sym) === nothing
        foreach(s -> _parameter_route(i, s, write), sym)
        return nothing
    end
    istable = table_key(ix, sym) !== nothing
    (istable || haskey(ix.params, ix.key(sym))) || return nothing
    t = _ptext(ix, sym)
    throw(ArgumentError(string("`", lstrip(t, ':'), "` is a ", istable ? "table" : "parameter", ": ",
        write ? "write `integ.ps[$t] = $(istable && table_entry(ix, sym) == 0 ? "values" : "v")`" : "read `integ.ps[$t]`",
        " (SciML's convention: an integrator indexes states, `integ.ps` its parameters)")))
end
# `integ.ps`: SciML's parameter proxy (`getp`/`setp`; a table write goes through `setp` too)
# (SciML's integrator properties: `t` the current time, `u` the current state, `sol` the
# solution so far, `tdir` the direction, `opts` the options the callbacks of DiffEqCallbacks read)
function Base.getproperty(i::FieldIntegrator, f::Symbol)
    f === :ps && return SII.ParameterIndexingProxy(i)
    f === :t && return getfield(i, :tnow)
    f === :u && return SII.state_values(i)
    f === :sol && return _solution(i)
    f === :tdir && return 1.0
    f === :opts && return (; maxiters = typemax(Int), tstops = getfield(i, :tstops))
    return getfield(i, f)
end
Base.propertynames(i::FieldIntegrator) = (fieldnames(typeof(i))..., :ps, :t, :u, :sol, :tdir, :opts)

"""
    add_tstop!(integ, t)

Make the owned run land on the time `t` (F4-03): a time on the window grid is a window's end
already; a time off it is reached by one shortened window ([`FieldIntegrator`](@ref)). A time
at or before `integ.t` is an error, as on OrdinaryDiffEq's integrators.
"""
function SciMLBase.add_tstop!(i::FieldIntegrator, t)
    t <= _time(i) && throw(ArgumentError(string("add_tstop!: t = ", t, " is not after the integrator's time ", _time(i))))
    ts = getfield(i, :tstops)
    k = searchsortedfirst(ts, t)
    (k <= length(ts) && ts[k] == t) || insert!(ts, k, Float64(t))
    return nothing
end
SciMLBase.has_tstop(i::FieldIntegrator) = !isempty(getfield(i, :tstops))
SciMLBase.first_tstop(i::FieldIntegrator) = first(getfield(i, :tstops))
SciMLBase.pop_tstop!(i::FieldIntegrator) = popfirst!(getfield(i, :tstops))
"""
    derivative_discontinuity!(integ, true)

The state or the data changed outside the steps (a write into `integ.u`, a callback): every
group's algorithm history is dropped ([`reset!`](@ref): Crank–Nicolson damps again, BDF2
starts again). `false` changes nothing. `u_modified!` is SciML's older name.
"""
SciMLBase.derivative_discontinuity!(i::FieldIntegrator, b::Bool) = (i.modflag = b; b && foreach(reset!, i.runtimes); nothing)
"""
    terminate!(integ, retcode = ReturnCode.Terminated)

End the owned run at its current time: `solve!` and `step!(integ, dt)` stop, and the state is
saved.
"""
function SciMLBase.terminate!(i::FieldIntegrator, retcode = SciMLBase.ReturnCode.Terminated)
    i.retcode = retcode
    return nothing
end
"""
    savevalues!(integ, force_save = false) -> (saved, savedexactly)

Save the current state at the current time now (once per time).
"""
function SciMLBase.savevalues!(i::FieldIntegrator, force_save = false)
    (isempty(i.ts) || i.ts[end] != _time(i)) || return (false, false)
    _save!(i)
    return (true, true)
end
SciMLBase.get_proposed_dt(i::FieldIntegrator) = i.dt
SciMLBase.set_proposed_dt!(i::FieldIntegrator, dt) = throw(ArgumentError(string("set_proposed_dt!: an owned run steps ",
    "a fixed window (dt = ", i.dt, "); land on a time with `add_tstop!` or `step!(integ, dt, true)`, or give the ",
    "algorithm another `dt`")))
SciMLBase.done(i::FieldIntegrator) = !_running(i.retcode) || _time(i) >= i.tend - 1e-9 * i.dt

# an input symbol writes the input's array (the masks run again); a parameter or table is an
# error naming `integ.ps`; any other goes to SII
Base.setindex!(i::FieldIntegrator, v, sym) = _integ_setindex!(i, v, sym)
Base.setindex!(i::FieldIntegrator, v, sym::Union{Tuple, AbstractArray}) = _integ_setindex!(i, v, sym)
function _integ_setindex!(i::FieldIntegrator, v, sym)
    _parameter_route(i, sym, true)
    k = i.prob.index isa LatticeIndex ? input_key(i.prob.index, sym) : nothing
    if k === nothing
        _check_symbol(i, sym; write = true)
        SII.setsym(i, sym)(i, v)                   # a state write resets (`set_state!`); a parameter's rebinds
        return i
    end
    w = _input_value(i.prob.program, k, v, input_name(i.prob.index, k);
        bool = is_bool_input(i.prob.index, k), bounds = input_bounds(i.prob.index, k))
    # an input the bound reads in an index: the checks (a rate that is not finite where the
    # new values reach, naming the site) and the substep count at the new values, before
    # anything changes
    ms = nothing
    if k in bound_inputs(i.prob.stability)
        ins = _bound_inputs(i; set = k => w)
        check_parameters(i.prob.stability, with_tables(map(primal, i.pgood), i.tables; inputs = ins))
        ms = _counts(i, i.pgood; tables = i.tables, inputs = ins)
    end
    _set_input!(i.store, i.prob.program, k, w)
    ms === nothing || _set_counts!(i, ms)
    _rerun_init!(i, i.pgood)                       # the parameters the steps are bound to
    foreach(reset!, i.runtimes)                    # the masked values may have moved
    return i
end

# `integ.ps[Dk] = values` (or `integ.ps[Dk[i]] = value`, `setp(integ, Dk)`) sets the
# integrator's table: the store's array in place (the bound steps read it), then the masks and
# clamps run again; false if `sym` is no table
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
        vals .= [_table_value(eltype(vals), t, x) for x in v]
    else
        num(v) || throw(ArgumentError("`$(_symtext(sym))` is entry $e of the table `$t`: give one number (got $(repr(v)))"))
        vals[e] = _table_value(eltype(vals), t, v)
    end
    all(isfinite, vals) || throw(ArgumentError("the table `$t` must hold finite values (got $vals)"))
    # the checks and the substep count at the new values, before anything changes (with the
    # computed parameters that read the table derived again, F2-15)
    tables = copy(i.tables)
    tables[j] = t => vals
    pc = derive!(copy(i.pgood), tables, ix)
    ins = _bound_inputs(i)
    check_faces(i.prob.faces, pc)
    check_values(pc, ix)
    check_parameters(i.prob.stability, with_tables(map(primal, pc), tables; inputs = ins))
    ms = _counts(i, pc; tables, inputs = ins)
    a = i.store.tables[findfirst(x -> x.key == t, i.prob.program.tables)]
    copyto!(a, convert(Vector{eltype(a)}, vals))
    i.tables[j] = t => vals
    if pc != i.pgood                                 # a computed parameter moved: rebind the steps
        copyto!(i.p, pc)
        SII.finalize_parameters_hook!(i, nothing)
        return true
    end
    _set_counts!(i, ms)
    _rerun_init!(i, i.pgood)
    foreach(reset!, i.runtimes)
    return true
end

# a value written into an integrator's table of element type `T` (the problem's): converted;
# derivative parts into a table without them are refused with the route (the problem's type
# is fixed for its integrator)
function _table_value(::Type{T}, t, x) where {T}
    valtype(typeof(x)) === typeof(x) || valtype(T) !== T || throw(ArgumentError(string("the table `", t,
        "` of this integrator holds ", T, " values; a value with derivative parts (", typeof(x), ") needs a problem ",
        "whose table holds them: `remake(prob; p = [", t, " => values])`, then `init`")))
    return convert(T, x)
end

# a parameter set through `setp` checks the faces, recomputes the substep count from the
# stability bound at the new values, and rebinds the steps (the derived parameters are
# launch arguments); nothing recompiles. The update is atomic: on any error the parameters
# go back to the last values the steps were bound to.
function _rerun_init!(integ::FieldIntegrator, p)
    prob = integ.prob
    isempty(prob.init.launches) && return nothing
    run_step!(prob.backend, prob.program, prob.init, integ.store, p;
        rt = (_time(integ), integ.dt, _tick(integ)), c = zero(eltype(prob)))
    foreach(rt -> _clamp!(rt.clamps, integ.store, p), integ.runtimes)
    return nothing
end

# the substep count of each group at parameters `p` (checked, nothing changes yet), and
# setting them
function _counts(i::FieldIntegrator, p; tables, inputs)
    ms = map(rt -> rt.all_state ? substeps(i.prob, rt.alg, p; tables, inputs) :
                   substeps(i.prob, rt.alg, p; tables, inputs, stability = rt.stability, fields = rt.keys), i.runtimes)
    _check_coupling(i.prob, [(rt.alg, rt.keys) for rt in i.runtimes], p; tables, inputs, dt = i.dt)
    return ms
end
# `integ.substeps = n` sets the count of every group (a test forces a count this way)
function Base.setproperty!(i::FieldIntegrator, f::Symbol, v)
    f === :substeps && foreach(rt -> rt.n = v, getfield(i, :runtimes))
    return setfield!(i, f, convert(fieldtype(typeof(i), f), v))
end
# (`setfield!`: the `substeps` property above would write the first count into every group)
function _set_counts!(i::FieldIntegrator, ms)
    foreach((rt, m) -> (rt.n = m; _count_set!(rt.cache, rt)), i.runtimes, ms)
    setfield!(i, :substeps, first(ms))
    return nothing
end

"""
    substep_counts(integ) -> Vector{Int}
    substep_counts(sol) -> Vector{Int}

The substep count of each field group of an integrator or a solution, in group order (the
order of each group's first state). A count is the algorithm's `substeps` (a minimum) or more,
as the stability bound of the group's own rows needs at the current parameters, so it follows
`setp`, input and table writes. `integ.substeps` and `sol.substeps` are the first group's.

```julia
ig = init(prob, FieldGroups(o => ExplicitEuler(; dt = 0.01); default = ExplicitEuler(; dt = 0.01, substeps = 1)))
substep_counts(ig)        # [1, 4]: c takes 1, o (diffusion) 4
```
"""
substep_counts(i::FieldIntegrator) = Int[rt.n for rt in i.runtimes]
substep_counts(s::FieldSolution) = copy(s.counts)

# The coupling between field groups (review of F2-06, ruling K-unsafe; round 2: loops only).
# A group reads the fields of the other groups from their arrays: over its window `dt` they
# are held (the groups step one after the other, in state order), so a cross term `a o` in the
# rate of `c` is a lagged source of `c`'s step that no substep count of `c`'s group reaches.
# When the group read graph (`lagged_coupling`'s `reads`; `group_loops`) has no loop, the split
# system is block triangular: each group is stable under its own count and the lag adds only
# an O(dt) source error, so such groups are not checked (a one-way chain runs as before the
# check). In a loop, only the reads of groups in the same loop count: a group outside it is
# upstream (a bounded source) or downstream (not read), so it cannot feed growth back. In a loop the lag can feed back: with `c' = −k o`, `o' = k c` in two groups stepped
# one after the other (each exactly), the window map is symplectic Euler, whose amplification
# stays 1 only while `κ_c κ_o ≤ 4` (`κ = k dt`), and grows without bound past it. The
# criterion is conservative and per group in a loop: `κ_g = dt · max over the group's rows of
# Σ max|coefficient|` over the terms that read fields of other groups (a cross diffusion with
# its `4 Σ 1/h²` and Robin parts), and `κ_g ≤ 1` (a margin to the skew pair's 2, as 1.8 to 2
# for the substep count; it is not a proof for every coupling; a relative 1e-12 absorbs the
# rounding of `dt · rate` at a limit the message prints). A group with a term the bound cannot
# see and that reads another field (of another row, or an aux field) may read any group, so it
# counts as reading every other group; one on the row's own field alone couples nothing. Above the limit the
# problem is refused with the routes (the loop's fields in one group, with an explicit count
# when their rows are not diagonally dominant; or a smaller `dt` that divides the time span);
# a cross coefficient in a loop with no finite bound (past the evaluation cap; a value that is
# not finite is refused by `check_parameters`) is refused with an automatic count and runs with
# a warning (once per program, group and term) with an explicit one. A bound that does not know
# the cross terms (`lagged_coupling` returns `nothing`) is the same as an unseen term for every
# group. Maps step as the user wrote them: not checked.
# One group (or a map) returns before any work; the check itself is behind a barrier, so a
# one-group `init` does not compile it.
function _check_coupling(prob::FieldProblem, groups, p; tables = prob.tables, inputs = nothing, dt::Real)
    length(groups) > 1 && prob.kind != :map || return nothing
    ins = inputs === nothing ? _bound_inputs(prob) : inputs
    return Base.inferencebarrier(_check_coupling_loops)(prob, groups, p, tables, ins, dt)
end

function _check_coupling_loops(prob::FieldProblem, groups, p, tables, inputs, dt::Real)
    pp = with_tables(map(primal, p), tables; inputs)
    # the one coupling rule of both front ends (F3-01), in front end B's words
    return check_coupling(prob.stability, [collect(String, ks) for (_, ks) in groups], [_explicit_count(a) for (a, _) in groups],
        pp, dt; key = why -> _warn_key(prob, why), texts = ProblemTexts(prob.group.spec.texts.route),
        span = prob.tspan[2] - prob.tspan[1], steady = [a isa QuasiSteady for (a, _) in groups],
        rows0 = collect(String, prob.group.spec.steady))
end

function SII.finalize_parameters_hook!(integ::FieldIntegrator, _)
    installed = false
    try
        derive!(integ.p, integ.tables, integ.prob.index)   # the computed slots follow (F2-15)
        check_faces(integ.prob.faces, integ.p)
        check_values(integ.p, integ.prob.index)
        ins = _bound_inputs(integ)
        check_parameters(integ.prob.stability, with_tables(map(primal, integ.p), integ.tables; inputs = ins))
        ms = _counts(integ, integ.p; tables = integ.tables, inputs = ins)
        launches = map(rt -> rebind_launches(rt, integ.p), integ.runtimes)
        _rerun_init!(integ, integ.p)                  # init kernels read the parameters too
        foreach(install_launches!, integ.runtimes, launches)    # (and `reset!`)
        installed = true
        # a coupled steady group's growing mode at the new values (F3-12d r1 M2)
        foreach(rt -> check_coupled_growth(rt, integ.p), integ.runtimes)
        integ.aux === nothing || (integ.aux = _bind_aux(integ.prob, integ.store, integ.p))
        # (the bound parameters first: a new count sets an implicit group's step from them)
        copyto!(integ.pgood, integ.p)
        _set_counts!(integ, ms)
    catch
        copyto!(integ.p, integ.pgood)
        _rerun_init!(integ, integ.pgood)
        # (a check after the new launches were installed: the old values' launches again)
        installed && foreach(install_launches!, integ.runtimes, map(rt -> rebind_launches(rt, integ.p), integ.runtimes))
        rethrow()
    end
    return nothing
end
