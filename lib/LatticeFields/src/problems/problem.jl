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
    return CompileOptions(nothing, o.I, o.float64_ok, o.debug, o.index, o.lanes, o.clock)
end

# the compile options of value type `V` on `backend`
function _options(o::CompileOptions, ::Type{V}, backend; clock::Int = o.clock) where {V}
    return CompileOptions(; T = V, I = o.I,
        float64_ok = o.float64_ok && _float64_ok(V, backend), debug = o.debug,
        index = o.index, lanes = :state, clock)
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
    tables, p = _tables(prob, p)
    pv = _parameter_vector(prob, p)
    check_faces(prob.faces, pv)
    derive!(pv, tables, prob.index)                 # (the computed slots, before their bounds: F2-15)
    check_bounds(pv, prob.index)                    # a declared bound, at the write (F2-14)
    length(u0) == length(prob.u0) ||
        throw(ArgumentError("u0 has $(length(u0)) values; the state has $(length(prob.u0))"))
    ins = isempty(inputs) ? prob.inputs : resolve_inputs(prob.program, prob.index, inputs, prob.inputs)
    return _field_problem(prob.program, prob.state, collect(u0), tspan, pv, tables,
        ins, prob.backend, prob.index, prob.faces, prob.stability, prob.kind, prob.initkeys,
        prob.options, prob.group)
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
them. An aux field `K ~ rhs` (F3 design §3.12) is not in `u`: `aux` holds its values at each
save, evaluated from the saved state at the save time, and `sol[K]` reads them.
"""
struct FieldSolution{P, U}
    prob::P
    t::Vector{Float64}
    u::Vector{U}
    retcode::SciMLBase.ReturnCode.T
    substeps::Int
    counts::Vector{Int}
    aux::Vector{U}                      # the aux fields at each save (flat, `_aux_layout`), or empty
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

"""
    FieldIntegrator

The state of an owned solve: the store, the runtime of each field group
([`GroupRuntime`](@ref): its bound launches, clamps and algorithm cache), time, step,
substep count (the first group's) and the saved states. `step!` advances one step of `dt`
([`advance!`](@ref) of each group, in group order); indexing by symbol reads (and sets)
fields of the current state.

Parameters and tables change only through `integ.ps[sym] = v` or `setp(integ, sym)(integ, v)`
(SymbolicIndexingInterface), which checks the faces, recomputes the substeps and rebinds the
steps, or else leaves the integrator unchanged. Writing `integ.p[i] = v` directly has no effect on the run: the steps
keep the values they were bound to.
"""
mutable struct FieldIntegrator{P <: FieldProblem, A, S <: FieldStore, RT <: Tuple, T, PV, TB}
    prob::P
    alg::A
    store::S
    runtimes::RT                        # one `GroupRuntime` per field group, in group order
    p::PV
    pgood::PV                           # the parameters the steps are bound to
    tables::TB                          # its own copy (`integ.ps[Dk] = values`), as the problem's
    t0::Float64
    iter::Int
    dt::Float64
    substeps::Int
    nsteps::Int
    per::Int                            # windows per period of the clock (0: no clock)
    save::Vector{Int}
    t::Vector{Float64}
    u::Vector{Vector{T}}
    retcode::SciMLBase.ReturnCode.T
    aux::Any                            # the aux kernels bound at both parities, or nothing (F3-00)
    auxu::Vector{Vector{T}}             # the aux fields at each save (flat, `_aux_layout`)
end


"""
    substeps(prob, alg, p = prob.p) -> Int

The substep count of `alg` on `prob` at parameters `p`: `⌈dt ρ(p) / 1.8⌉`; with a user
count `n`, the larger of `n` and the count of the bound over the terms the bound sees
([`seen_bound`](@ref)), or `n` when that is not finite; when the full bound is unknown the
count is the user's for the terms it does not cover, and a warning names them, once per
program, term and cause in a session ([`unbounded_key`](@ref): never once per value). An unknown bound with no user count is an `ArgumentError` that names the
terms the bound cannot see. A problem with no state (aux fields `K ~ rhs` only, F3 design
§3.12) takes 0 substeps: its window evaluates the aux fields once.
"""
substeps(::FieldProblem, ::ExplicitMap, p = nothing; tables = nothing, inputs = nothing) = 1

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
const _SEEN_WARNED = Set{String}()
const _SEEN_WARNED_LOCK = ReentrantLock()
# the warning's once-key: the program (its printed text, hashed) and the value-free reason
_warn_key(prob::FieldProblem, why) = string(hash(sprint(print_program, prob.program)); base = 16) * "|" * string(why)
function substeps(prob::FieldProblem, alg::ExplicitEuler, p = prob.p; tables = prob.tables,
        inputs = _bound_inputs(prob), stability = prob.stability)
    dt = _window(alg, _clock(prob))
    isempty(prob.state) && return 0                 # aux fields only: one evaluation per window
    pp = with_tables(map(primal, p), tables; inputs)        # a policy: on the primal values
    if alg.substeps !== nothing
        ρ = seen_bound(stability, pp)
        n = isfinite(ρ) && ρ >= 0 ? max(alg.substeps, ceil(Int, dt * ρ / 1.8)) : alg.substeps
        full = Float64(stability(pp))
        if !(isfinite(full) && full >= 0) && ccall(:jl_generating_output, Cint, ()) == 0
            why = unbounded_reason(stability, pp)
            # once per (program, term, cause) and session: the key holds no value, so a sweep
            # over entries or parameters warns once and the set stays bounded
            key = why === nothing ? nothing : _warn_key(prob, unbounded_key(stability, pp))
            why === nothing || !lock(() -> key in _SEEN_WARNED ? false : (push!(_SEEN_WARNED, key); true),
                                     _SEEN_WARNED_LOCK) ||
                @warn string("ExplicitEuler(substeps = ", alg.substeps, "): ", n, " substeps (the request, or more for ",
                             "the terms the bound sees); the stability bound does not cover ", why, ": the count is the user's")
        end
        return n
    end
    ρ = Float64(stability(pp))
    isfinite(ρ) && ρ >= 0 && return max(1, ceil(Int, dt * ρ / 1.8))
    why = unbounded_reason(stability, pp)
    throw(ArgumentError(string("no automatic substeps: no stability bound for these parameters (",
        why === nothing ? string("a rate term the bound cannot see, such as advection, a nonlinear rate, ",
            "or a coefficient with more than 6 kind sets and ",
            "comparisons; a parameter without a value; or coupled rows that ",
            "are not diagonally dominant, whose spectrum may be complex") : why,
        "). Give an explicit count: ExplicitEuler(; dt, substeps = n) (a minimum; the bound over ",
        "the terms it sees can raise it)")))
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

# the field groups of `alg` on `prob`: `(algorithm, state keys)` in state order (one group
# of every state field for a single algorithm)
_groups(prob::FieldProblem, alg::FieldAlgorithm) = Tuple{FieldAlgorithm, Vector{String}}[(alg, prob.state)]
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
    for k in prob.state
        a = get(assigned, k, g.default)
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
    return out
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

function CommonSolve.init(prob::FieldProblem, alg::FieldAlgorithm; saveat = (),
        save_start::Bool = true, save_end::Bool = true)
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
    nsteps = _count(tf - t0, w, "the time span"; window = _wtext(a1, clock, w),
        route = _count_route(a1, clock, w, tf - t0, "the time span"))
    dt = (tf - t0) / max(nsteps, 1)                 # the step that lands on tf exactly
    save = Int[]
    save_start && push!(save, 0)
    if saveat isa Real
        k = _count(saveat, dt, "saveat"; window = _wtext(a1, clock, dt), route = _count_route(a1, clock, dt, saveat, "saveat"))
        k >= 1 && append!(save, k:k:nsteps)
    else
        append!(save, (_count(s - t0, dt, "a saveat time"; window = _wtext(a1, clock, dt),
                           route = _count_route(a1, clock, dt, s - t0, "the saveat times")) for s in saveat))
    end
    save_end && push!(save, nsteps)
    save = sort!(unique!(filter!(i -> 0 <= i <= nsteps, save)))
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
              stability = restrict_bound(prob.stability, ks)) for (a, ks) in groups]
    _check_coupling(prob, groups, prob.p; dt)
    run_step!(prob.backend, prob.program, prob.init, st, prob.p; rt = (t0, dt, 0), c = zero(E))
    pgood = copy(prob.p)
    # one group steps in alternating slots; several end each step in slot 1, so the next
    # group reads current values
    ends_in = length(groups) == 1 ? :parity : :slot1
    rts = Tuple(bind_group(prob.group, a, st, pgood; fields = ks, n = m, dt, c = zero(E), ends_in,
                    backend = prob.backend, options = prob.options, V = valtype(E))
                for ((a, ks), m) in zip(groups, ms))
    foreach(clamp_now!, rts)                        # the saved t0 state holds the mask values
    foreach(rt -> compile!(prob.backend, rt), rts)
    aux = _bind_aux(prob, st, pgood)
    aux === nothing || compile!(prob.backend, aux[1])
    integ = FieldIntegrator(prob, alg, st, rts, copy(prob.p), pgood,
        eltype(prob.tables)[k => copy(v) for (k, v) in prob.tables], t0, 0, dt,
        ms[1], nsteps, _clock(prob) === nothing ? 0 : _per(dt, _clock(prob)), save, Float64[], Vector{_ueltype(st, E)}[],
        SciMLBase.ReturnCode.Success, aux, Vector{_ueltype(st, E)}[])
    0 in save && _save!(integ)
    return integ
end

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
_time(integ::FieldIntegrator) = integ.t0 + integ.iter * integ.dt
# The clock's step index of the current window: the clock boundaries reached since the start
# of the time span, by integer bookkeeping (each period holds `per` windows, and no window
# crosses a boundary), never from a float time; the window count without a clock
_tick(integ::FieldIntegrator) = integ.per == 0 ? integ.iter : div(integ.iter, integ.per)

# `u0` (flat, host) into every state buffer, the state in slot 1
function _load_state!(st::FieldStore, u0)
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
code other than `ReturnCode.Success` becomes `integ.retcode`, and the later groups do not
run; `solve!` stops on it.
"""
function CommonSolve.step!(integ::FieldIntegrator)
    code = _advance_all(integ.runtimes, (_time(integ), _tick(integ)))
    integ.iter += 1
    code == SciMLBase.ReturnCode.Success || (integ.retcode = code)
    return integ
end
_advance_all(::Tuple{}, clock) = SciMLBase.ReturnCode.Success
function _advance_all(rts::Tuple, clock)
    code = advance!(first(rts), clock)
    code == SciMLBase.ReturnCode.Success || return code
    return _advance_all(Base.tail(rts), clock)
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
    st = integ.store
    foreach(f -> st.cur[f] = 1, integ.prob.step.swaps)
    _load_state!(st, u0)
    integ.iter = 0
    empty!(integ.t)
    empty!(integ.u)
    empty!(integ.auxu)
    integ.retcode = SciMLBase.ReturnCode.Success
    _rerun_init!(integ, integ.pgood)
    foreach(reset!, integ.runtimes)
    0 in integ.save && _save!(integ)
    return integ
end

_ueltype(st::FieldStore, ::Type{E}) where {E} = isempty(st.flat) ? E : eltype(st.flat[1])
_current(integ::FieldIntegrator) = isempty(integ.store.flat) ? eltype(integ.prob)[] :
                                   Array(integ.store.flat[_parity(integ)])

# a saved state that is not finite ends the solve with `ReturnCode.Unstable`; the aux fields
# are evaluated at the save (one aux launch) and saved with it
function _save!(integ::FieldIntegrator)
    u = _current(integ)
    push!(integ.t, _time(integ))
    push!(integ.u, u)
    if integ.aux !== nothing
        _eval_aux!(integ)
        push!(integ.auxu, _aux_values(integ))
    end
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
    return FieldSolution(integ.prob, integ.t, integ.u, integ.retcode, integ.substeps, substep_counts(integ), integ.auxu)
end

# the default algorithm: `ExplicitEuler()` for rates (which needs `dt`: nothing else sets the
# window, and `saveat` never does), `ExplicitMap()` for maps
_default_alg(prob::FieldProblem) = prob.kind == :map ? ExplicitMap() : ExplicitEuler()
CommonSolve.init(prob::FieldProblem; kw...) = CommonSolve.init(prob, _default_alg(prob); kw...)
CommonSolve.solve(prob::FieldProblem; kw...) = CommonSolve.solve(prob, _default_alg(prob); kw...)
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
function Base.getindex(i::FieldIntegrator, sym)
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
function SII.getp(sys::Union{FieldProblem, FieldIntegrator, FieldSolution}, sym)
    prob = sys isa FieldProblem ? sys : sys.prob
    ix = prob.index
    # the clock's slot is the stepper's, not a parameter (review N6 of F2 batch 3)
    sym isa Union{Symbol, AbstractString} && String(sym) == CLOCK_KEY && throw(ArgumentError(string(
        "`", CLOCK_KEY, "` is the clock's slot, which the stepper writes at every launch, not a parameter of the ",
        "problem: an equation reads the step index as `step_index(t)`")))
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
# a state written through `setu(integ, c)(integ, v)` drops every group's algorithm history, as
# `integ[c] = v` does
function SII.set_state!(i::FieldIntegrator, val, idx)
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
function Base.getproperty(i::FieldIntegrator, f::Symbol)
    f === :ps && return SII.ParameterIndexingProxy(i)
    return getfield(i, f)
end
Base.propertynames(i::FieldIntegrator) = (fieldnames(typeof(i))..., :ps)

# an input symbol writes the input's array (the masks run again); a parameter or table is an
# error naming `integ.ps`; any other goes to SII
function Base.setindex!(i::FieldIntegrator, v, sym)
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
                   substeps(i.prob, rt.alg, p; tables, inputs, stability = rt.stability), i.runtimes)
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
    foreach((rt, m) -> rt.n = m, i.runtimes, ms)
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
_explicit_count(a) = hasproperty(a, :substeps) && getproperty(a, :substeps) !== nothing
_num(x) = round(x; sigdigits = 6)                  # a value in a message (`dt = 0.003334`)
const _COUPLING_RTOL = 1e-12
function _check_coupling(prob::FieldProblem, groups, p; tables = prob.tables, inputs = _bound_inputs(prob), dt::Real)
    length(groups) > 1 && prob.kind != :map || return nothing
    pp = with_tables(map(primal, p), tables; inputs)
    keys = [collect(String, ks) for (_, ks) in groups]
    parts = lagged_coupling(prob.stability, keys, pp)
    warn(key, msg) = ccall(:jl_generating_output, Cint, ()) == 0 &&
        lock(() -> key in _SEEN_WARNED ? false : (push!(_SEEN_WARNED, key); true), _SEEN_WARNED_LOCK) && @warn msg
    if parts === nothing
        all(g -> _explicit_count(first(g)), groups) || throw(ArgumentError(string(
            "FieldGroups: the problem's stability bound does not see the terms that couple its groups (each group ",
            "reads the fields of the others from their arrays, held over the window); step the fields in one group, ",
            "or give every group an explicit count (`ExplicitEuler(; dt, substeps = n)`)")))
        warn(_warn_key(prob, "coupling#unknown"), string("FieldGroups: the stability bound does not see the coupling ",
            "between the groups ", join((_fieldlist(k) for k in keys), " and "), ": the counts are the user's"))
        return nothing
    end
    loops = group_loops(parts)
    all(isempty, loops) && return nothing
    # the rates over the reads inside each group's loop: a read of a group outside it is a
    # one-way source of the loop, which cannot feed growth back (round 3)
    parts = lagged_coupling(prob.stability, keys, pp; within = loops)
    for (g, ((a, _), ks, q)) in enumerate(zip(groups, keys, parts))
        isempty(loops[g]) && continue
        κ = dt * q.rate
        lf = reduce(vcat, keys[loops[g]])           # the fields of the loop
        if !isfinite(κ)
            _explicit_count(a) || throw(ArgumentError(string("FieldGroups: the group of ", _fieldlist(ks),
                " is in a loop of groups that read one another (", _fieldlist(lf), "), and its coupling to the ",
                "other groups has no bound at these parameters (the coefficient `", q.text, "` of `", q.other,
                "` in the rate of `", q.row, "` reads more table entries than the bound evaluates); step ",
                _fieldlist(lf), " in one group, or give the group an explicit count (`ExplicitEuler(; dt, substeps = n)`)")))
            warn(_warn_key(prob, string("coupling#", join(ks, ","), "#", q.row, "#", q.raw)), string(
                "FieldGroups: the coupling of the group of ", _fieldlist(ks), " in the loop of ", _fieldlist(lf),
                " has no bound (the coefficient `", q.text, "` of `", q.other, "` in the rate of `", q.row,
                "`): the count is the user's"))
        elseif κ > 1 + _COUPLING_RTOL
            throw(ArgumentError(_loop_message(prob, parts, keys, loops[g], q, dt, pp)))
        end
    end
    return nothing
end
# the refusal of a loop past the limit, with its routes
function _loop_message(prob, parts, keys, loop, q, dt, pp)
    κ = dt * q.rate
    lf = reduce(vcat, keys[loop])
    unseen = [k for h in loop if parts[h].unseen for k in keys[h]]
    # route 1: the loop's fields in one group; an automatic count needs dominant rows
    ρ = Float64(restrict_bound(prob.stability, lf)(pp))
    one = isfinite(ρ) && ρ >= 0 ? string("Step ", _fieldlist(lf), " in one group (one algorithm; its count can be automatic)") :
          string("Step ", _fieldlist(lf), " in one group with an explicit count (`ExplicitEuler(; dt, substeps = n)`: ",
                 "their rows are not diagonally dominant, so no automatic count bounds them)")
    # route 2: a dt that divides the time span (`init` refuses any other)
    span = prob.tspan[2] - prob.tspan[1]
    lim = floor(1 / q.rate; sigdigits = 4)
    n = max(1, ceil(Int, span * q.rate * (1 - _COUPLING_RTOL)))
    return string("FieldGroups: the groups of ", _fieldlist(lf), " read one another in a loop, each from the ",
        "others' arrays, held over each window dt = ", _num(dt),
        ": the terms in the rate of `", q.row, "` that read other groups of the loop (the largest: the coefficient `", q.text,
        "` of `", q.other, "`) give dt · Σ max|coefficient| = ", round(κ; sigdigits = 4), " > 1, and the loop can then ",
        "grow without bound at any substep count",
        isempty(unseen) ? "" : string(" (the terms of ", _fieldlist(unseen), " that the bound cannot see and that read ",
                                      "another field count as reading every other group)"),
        ". ", one, ", or use a smaller dt that divides the time span ", _num(span), ": dt ≤ ", lim,
        ", such as dt = ", _num(span), "/", n)
end
_fieldlist(ks) = join(("`$k`" for k in ks), ", ")

function SII.finalize_parameters_hook!(integ::FieldIntegrator, _)
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
        integ.aux === nothing || (integ.aux = _bind_aux(integ.prob, integ.store, integ.p))
        _set_counts!(integ, ms)
        copyto!(integ.pgood, integ.p)
    catch
        copyto!(integ.p, integ.pgood)
        _rerun_init!(integ, integ.pgood)
        rethrow()
    end
    return nothing
end
