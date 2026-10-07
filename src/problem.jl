# `PottsProblem(sys, op, tspan)`: operating point + compiled model → `CorePotts.PottsProblem`
# with generated functions (the analogue of MTK's `ODEProblem(sys, op, tspan)`).

# `ownership => labels` in an operating point uses CorePotts' `ownership` accessor as the key.
const ownership = CorePotts.ownership

"""
    PottsModelInfo

What a generated problem keeps about its model (`prob.f.sys`): the compiled system, the
scalar type, the generated `total_energy(st, p, ctx)` and the solver specification the
phases were generated for (what `remake(prob; field_solver | ode_solver | solvers)`
rebuilds `f` from).
"""
struct PottsModelInfo{C, E, DE, X}
    csys::C
    T::Type
    total_energy::E
    delta_E::DE          # ΔH without drives: the energy change the self-check compares
    ctx::X               # host context (lattice, relations) for observed quantities
    cache::Dict{Any, Any}    # compiled observed functions, by expression
    solvers::SolverSpec
end

"""
    generated_code(sys; T = Float64, field_solver, ode_solver, solvers)

The code Potts generates for model `sys` (a `PottsSystem` or `CompiledPottsSystem`) in scalar
type `T` with the solver keywords of `PottsProblem`, as expressions: `delta_H`, `commit!`,
`constraint`, `temperature`, `total_energy`, `delta_E` (ΔH without drives), `phases`, every
other function (MCS phases, lifecycle), in build order, and `lifecycle`: `nothing` for a
model without divisions, else `(; trigger, before)`, the trigger (the event of a cell) and the
cell update that runs in the trigger's work item (`Lifecycle.before`), or `nothing`. That
update is the model's last after-MCS cell update when the trigger reads the columns it
writes only at its own cell; it then runs with the lifecycle and is not among `phases`.
Each is `(args…) -> body` and can be `eval`'d into a plain function (e.g. for JET).
"""
function generated_code(sys; T::Type = Float64, field_solver = nothing, ode_solver = ExplicitEuler(), solvers = ())
    c = sys isa CompiledPottsSystem ? sys : ModelingToolkitBase.mtkcompile(sys)
    return _with_faces(() -> _generated_code(c, T, field_solver, ode_solver, solvers), c)
end
function _generated_code(c, T, field_solver, ode_solver, solvers)
    spec = _resolve_solvers(c; field_solver, ode_solver, solvers)
    values = Dict{Any, Any}(_unwrap(x) => info(x).default for x in getfield(c.sys, :parameters))
    (phases0, cand), phases = _recording(() -> _phases_parts(c, T, values, spec))
    lc, lex = _recording(() -> _lifecycle(c, T))
    lifecycle = nothing
    if lc !== nothing
        # the problem's own fusion decision (`_problem_function`)
        before = _fuse_before(c, T, phases0, lc, cand)[2].before === nothing ? nothing : cand.expr
        before === nothing || filter!(ex -> ex !== before, phases)
        lifecycle = (; trigger = first(lex), before)            # `_lifecycle` compiles the trigger first
    end
    append!(phases, lex)
    return (; delta_H = _delta_H_expr(c, T), commit! = _commit_expr(c, T), constraint = _constraint_expr(c, T),
        temperature = _temperature_expr(c, T), total_energy = _total_energy_expr(c, T),
        delta_E = _delta_H_expr(c, T; drives = false), phases, lifecycle)
end
"""
    PottsProblem(sys, op, tspan; field_solver, ode_solver = ExplicitEuler(), solvers = [],
                 T = Float64, capacity, seed = 0, replica = 0, repeat = 0, track = (),
                 expression = Val(false))

Build the numerical problem from a `PottsSystem` (compiled with `mtkcompile` if
needed). `op` maps `ownership` to the initial labels (an integer array over the lattice),
`kind` to the kinds of the labelled cells (names or numbers), `cluster` to their
compartment groups (any ids; equal ids form one cluster; default: every cell alone), variables to initial values
(scalars or arrays), parameters to values overriding their defaults, and a relationship's
name to its initial links (`:bond => [(1, 2)]`). An edge variable takes one number (or
a parameter expression, evaluated at construction: a later `remake` of parameters does not
re-seed it), its initial value on every initial link of its relationship (both ends;
default: its declared default); links made later by `@link` start at the declared default. `T` is the scalar
type of the generated code and state (use `Float32` on Metal). The generated code is
`Potts.generated_code(sys; T)`.

How fields and ODEs are integrated is part of the problem, compiled into its code:
- `field_solver = ExplicitEuler(; substeps, lower)` is required when the model has a field
  and an error otherwise; there is no default (a published model's docstring gives its
  value, e.g. `ExplicitEuler(substeps = 2, lower = 0.0)` for `MerksVasculogenesis`);
- `ode_solver` integrates the cell and model ODEs (`D(x) ~ …`, components): `ExplicitEuler(;
  substeps)` (the default, one step per MCS), `RK4(; substeps)` or `Adaptive(alg; reltol, …)`;
- `solvers = [x => solver, …]`, keyed by integrated variables (or a component: all its
  unknowns), overrides them for those variables only (a stiff ODE under
  `Adaptive(Rodas5P())` beside explicit ones). Every ODE step reads the state at the start
  of the step (Jacobi), across solvers too.

`remake(prob; field_solver | ode_solver | solvers = …)` rebuilds the code with the keywords
it names and keeps the others, `u0`, `p` and the seed; the problem fingerprint hashes a
canonical form of the resolved solvers, so a checkpoint loads only into an equally
discretised problem.
`track = (:ΔH,)` accumulates the ΔH of every committed copy (energy plus every drive, as
`prob.f.delta_H` returns it; not the acceptance law's offset) into `sol.stats.accepted_ΔH`
(a `Float64`; `nothing` with the default `track = ()`). Under `SequentialCPM` it is exact
after every step; under `CheckerboardCPM` it is brought up to date at the host read points
(a save, `integrator.u`, `checkpoint`, the end of `solve!`). Tracking changes nothing else
in the run; it is hashed into the fingerprint (only when on), and `remake(prob; track)`
switches it.
"""
function CorePotts.PottsProblem(sys::PottsSystem, op, tspan; kwargs...)
    return CorePotts.PottsProblem(ModelingToolkitBase.mtkcompile(sys), op, tspan; kwargs...)
end

function CorePotts.PottsProblem(c::CompiledPottsSystem, op, tspan; T::Type = Float64, capacity = nothing,
        seed = 0, replica = 0, repeat = 0, expression = Val(false), field_solver = nothing,
        ode_solver = ExplicitEuler(), solvers = (), track = ())
    sys = c.sys
    spec = _resolve_solvers(c; field_solver, ode_solver, solvers)
    track = _track(track)
    opd = _operating_point(sys, op)
    values = _parameter_values(c, opd)
    p = PottsParameters(NamedTuple(info(x).name => _param_value(T, values[_unwrap(x)], info(x)) for x in getfield(sys, :parameters)))
    for name in _contact_tables(c)
        J = getproperty(p, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    _check_kind_tables(sys, p)
    expression isa Val{true} && throw(ArgumentError(
        "`expression = Val(true)` is not supported; use `Potts.generated_code(sys; T)` to inspect the code"))
    st = _ode_layout(_initial_state(c, opd, T, capacity, values), c, spec)
    lat = core_lattice(getfield(sys, :lattice))
    relations = _with_contact_counts(c, NamedTuple(k => v for (k, v) in _sorted(c.relations)))
    spacing = getfield(sys, :lattice).spacing === nothing ? nothing : map(T, getfield(sys, :lattice).spacing)
    hctx = (; lattice = lat, contact = CorePotts.relation(c.contact_spec, lat),
        map(r -> CorePotts.relation(r, lat), relations)...,
        (spacing === nothing ? (;) : (; spacing))...)
    f = _problem_function(c, T, spec, values, hctx, Dict{Any, Any}(); track)
    frozen = _frozen_mask(sys, st)
    _host_init!(f, st, p, hctx, seed, replica, repeat)
    return CorePotts.PottsProblem(f, st, lat, tspan, p; contact = c.contact_spec, proposal = c.proposal_spec, relations,
        spacing, frozen, seed, replica, repeat)
end

# The non-default cadences of phases `x` (a phase, or a tuple or vector of them), appended to
# `acc` as strings (stable across sessions) for the fingerprint.
_cadences!(acc, x) = acc
_cadences!(acc, g::_Gated) = (g.every == 1 && g.offset == 0) ? acc : push!(acc, "gated($(g.every),$(g.offset))")
_cadences!(acc, h::CorePotts.HostPhase) = h.every == 1 ? acc : push!(acc, "host($(h.every))")
_cadences!(acc, v::Union{Tuple, AbstractVector}) = (foreach(y -> _cadences!(acc, y), v); acc)

# The one codegen point: every generated function of a problem for compiled model `c`, scalar
# type `T` and solvers `spec`, as a `CPMFunction` (construction, and `remake` with solvers).
function _problem_function(c::CompiledPottsSystem, T, spec::SolverSpec, values, hctx, cache; track::Tuple = ())
    sys = c.sys
    fns, generated = _recording() do
        _with_faces(c) do
        ce = _constraint_expr(c, T)
        (; delta_H = _rgf(_delta_H_expr(c, T)), commit! = _rgf(_commit_expr(c, T)),
            constraint = ce === nothing ? CorePotts.always : _rgf(ce), temperature = _rgf(_temperature_expr(c, T)),
            phases = _phases_parts(c, T, values, spec), lifecycle = _lifecycle(c, T),
            total = _rgf(_total_energy_expr(c, T)), delta_E = _rgf(_delta_H_expr(c, T; drives = false)))
        end
    end
    phases, lifecycle = _fuse_before(c, T, fns.phases[1], fns.lifecycle, fns.phases[2])
    # every generated function, without line numbers: independent of the install path, and
    # the canonical solver spec (D-016 as amended by D-075; a model with no field or ODE has
    # none and keeps its fingerprint)
    h = hash(_fingerprint_seed(sys, T))
    isempty(spec.canonical) || (h = hash(spec.canonical, h))
    # a solver holding a compiler-generated name (a closure) is bound to this session (D-130):
    # only the fingerprint sees the token, never the canonical string or the solver groups
    _session_bound(spec) && (h = hash(_SESSION_TOKEN[], h))
    # the schedule kept outside the generated code (D-118): the resolved cadence (in MCS,
    # after `mcs_duration`) of every gated phase, host phase and the lifecycle pass, and a
    # non-default `mcs_duration`; only non-default values, so a model on the default schedule
    # (every = 1, offset = 0, `mcs_duration` = 1) keeps its fingerprint
    cad = String[]
    for f in (:before_mcs, :after_mcs, :end_mcs, :at_init)      # the phases by role (`mcs` lists them again)
        _cadences!(cad, getfield(phases, f))
    end
    # the phase order (`@schedule`, D-145), canonicalized to the full placed order; only a
    # non-default one, so a model without `@schedule` (or one listing the default relative
    # order) keeps its fingerprint
    order = _phase_order(sys)
    order == collect(SCHEDULE_PHASES) || push!(cad, "schedule=$(join(order, ","))")
    lifecycle === nothing || lifecycle.every == 1 || push!(cad, "lifecycle($(lifecycle.every))")
    # the MCS length, which solvers keep as data (`Adaptive`'s dt, an explicit-substeps `FieldStep.dt`)
    getfield(sys, :sweep).mcs_duration == 1 || push!(cad, "mcs_duration=$(repr(getfield(sys, :sweep).mcs_duration))")
    # the acceptance law and its offset, solver data in `CPMFunction.acceptance` (D-121); only
    # non-default values (Metropolis, offset 0), so the default keeps its fingerprint. The
    # offset is a Float64 in `SweepSpec`, so `offset = 2` and `offset = 2.0` hash alike.
    getfield(sys, :sweep).law === :metropolis || push!(cad, "law=$(getfield(sys, :sweep).law)")
    getfield(sys, :sweep).offset == 0 || push!(cad, "offset=$(repr(getfield(sys, :sweep).offset))")
    # the proposal and contact neighbourhoods, run data outside the generated code (D-122):
    # each resolved on the lattice and hashed with its role when it differs from its default
    # (proposal `VonNeumann(1)`, contact the lattice's `neighborhood`). A default that does
    # not resolve on this lattice (it aliases on a thin periodic axis) is unused here, so it
    # is resolved leniently and any resolvable relation differs from it.
    lat = hctx.lattice
    for (role, nb, default) in (("proposal", c.proposal_spec, CorePotts.VonNeumann(1)),
            ("contact", c.contact_spec, getfield(sys, :lattice).neighborhood))
        r = CorePotts.relation(nb, lat)
        d = try
            CorePotts.relation(default, lat)
        catch e
            e isa ArgumentError || rethrow()
            nothing
        end
        r == d || push!(cad, "$role=$(r.offsets);$(r.weights)")
    end
    # named and inline gather relations, also run data outside the generated code (D-124):
    # every one a recorded function reads as `ctx.<name>` (`generated` holds each compiled
    # expression: energies, drives, ODEs, site and cell updates, ticks, lifecycle and
    # temperature), already resolved on the lattice in `hctx`, keyed by its name in sorted
    # order. No default is skipped. `surface` is always the lattice neighbourhood; a relation
    # read only by observed quantities (built at query time) is not here.
    used = Set{Symbol}()
    names = keys(c.relations)
    foreach(ex -> _ctx_reads!(used, ex, names), generated)
    delete!(used, :surface)
    for k in sort!(collect(used))
        r = getfield(hctx, k)
        push!(cad, "relation:$k=$(r.offsets);$(r.weights)")
    end
    # what the run accumulates (D-140, D-075's amendment of D-016): hashed only when on, so an
    # untracked problem keeps its fingerprint and a checkpoint loads only into an equally
    # tracked one
    isempty(track) || push!(cad, "track=$(repr(track))")
    isempty(cad) || (h = hash(join(cad, ";"), h))
    return CorePotts.CPMFunction(fns.delta_H; fns.commit!, fns.constraint, fns.temperature,
        claims = _claims(c), reads = _reads(c), phases, lifecycle, acceptance = _acceptance(getfield(sys, :sweep), T),
        footprint = c.footprint, fingerprint = _code_hash(generated, h),
        sys = PottsModelInfo(c, T, fns.total, fns.delta_E, hctx, cache, spec),
        track = isempty(track) ? nothing : CorePotts.TrackDeltaH{T}())
end

# The relation fields `names` that expression `x` reads from the run context (`ctx.<name>`),
# added to `acc` (D-124).
_ctx_reads!(acc, x, names) = acc
function _ctx_reads!(acc, ex::Expr, names)
    if ex.head === :. && length(ex.args) == 2 && ex.args[1] === :ctx && ex.args[2] isa QuoteNode &&
       ex.args[2].value in names
        push!(acc, ex.args[2].value)
    end
    foreach(a -> _ctx_reads!(acc, a, names), ex.args)
    return acc
end

# The fingerprint's structural part as a canonical string: the lattice (dims, boundaries,
# domain, geometry), spacing, neighbourhood and scalar type by content. Hashing the objects
# would fall back to `objectid` for package structs and tie the fingerprint to the build.
_fingerprint_seed(sys::PottsSystem, T) = string("lattice=", _canonical_value(core_lattice(getfield(sys, :lattice))),
    ";spacing=", _canonical_value(getfield(sys, :lattice).spacing), ";neighborhood=", _canonical_value(getfield(sys, :lattice).neighborhood),
    ";T=", string(T))

# `remake(prob; field_solver | ode_solver | solvers = …)`: the problem's code rebuilt through
# the codegen point with the named keywords replaced and the others kept, and `u0` re-laid
# out for its ODE scratch (values kept; CorePotts keeps p, the seed and the frozen mask).
# Never reached by `remake(prob; p | u0 | seed)`.
function CorePotts.remake_function(mi::PottsModelInfo, prob; field_solver = mi.solvers.field_solver,
        ode_solver = mi.solvers.ode_solver, solvers = mi.solvers.solvers, track = _track_names(prob.f), kwargs...)
    isempty(kwargs) || throw(ArgumentError("remake: unknown keyword$(length(kwargs) == 1 ? "" : "s") " *
                                           "$(join(("`$k`" for k in keys(kwargs)), ", "))"))
    c = mi.csys
    spec = _resolve_solvers(c; field_solver, ode_solver, solvers)
    values = _derived_parameters(c, prob.p, Set(info(x).name for x in getfield(c.sys, :parameters)))
    return _problem_function(c, mi.T, spec, values, mi.ctx, mi.cache; track = _track(track)), _ode_layout(prob.u0, c, spec)
end

# `track` (D-140): the quantities a run accumulates into its statistics. Only `:ΔH` (each
# committed copy's ΔH → `stats.accepted_ΔH`) for now; per-term names wait for R18.
const _TRACKABLE = (:ΔH,)
function _track(track)
    (track isa Union{Tuple, AbstractVector} && all(x -> x isa Symbol, track)) || throw(ArgumentError(
        "`track` must be a tuple of names, e.g. `track = (:ΔH,)`; got $(repr(track))"))
    for x in track
        x in _TRACKABLE || throw(ArgumentError("`track`: `:$x` cannot be tracked (trackable: $(join(repr.(_TRACKABLE), ", ")))"))
    end
    allunique(track) || throw(ArgumentError("`track`: a name is given twice in $(repr(track))"))
    return Tuple(track)
end
_track_names(f::CorePotts.CPMFunction) = f.track === nothing ? () : (:ΔH,)

# The ODE scratch slots `x__ode` a state needs for solvers `spec` (several solver groups in a
# scope, or cell ODEs reading other cells' unknowns: `_ode_scratch`), each starting as a
# copy of its variable; any others removed. The same state if its layout already fits.
function _ode_layout(st, c::CompiledPottsSystem, spec::SolverSpec)
    slots = Set(_ode_scratch_name(info(x).name) for (x, _) in Iterators.flatten((c.cell_odes, c.model_odes)))
    scratchless(nt) = NamedTuple(k => v for (k, v) in pairs(nt) if !(k in slots))
    function add(nt, scope, odes)
        _ode_scratch(c, spec, scope) || return nt
        return merge(nt, NamedTuple(_ode_scratch_name(info(x).name) => copy(getproperty(nt, info(x).name)) for (x, _) in odes))
    end
    cell = add(scratchless(st.cell), :cell, c.cell_odes)
    model = add(scratchless(st.model), :model, c.model_odes)
    keys(cell) == keys(st.cell) && keys(model) == keys(st.model) && return st
    return CorePotts.CPMState(st.σ, cell, st.site, model, st.history)
end

# Checkerboard claims beyond old/new: the clusters of old/new (cluster energies read cluster
# trackers, which the copy writes) ...
function _claims(c::CompiledPottsSystem)
    isempty(c.cluster_terms) && return CorePotts.no_claims
    return _rgf(:((st, p, prop, ctx) -> (CorePotts.cluster_claims(st.cell, prop)...,)))
end
# ... and, shared, the link partners of old/new in every relationship with an edge energy
# (link energies read their centroids; a copy writes only its old/new). Leaving one out
# would let a concurrent copy move a partner whose centroid this copy's ΔH read (P6.0b).
# Relationships used only by link rules are read on the host between sweeps: no claims.
function _reads(c::CompiledPottsSystem)
    rels = [r for r in c.relationships if any(t -> first(t) === r.name, c.edge_terms)]
    isempty(rels) && return CorePotts.no_claims
    parts = [:(CorePotts.link_claims($(_link_store(c, r.name)), prop, Val($(r.capacity)))...) for r in rels]
    return _rgf(:((st, p, prop, ctx) -> $(Expr(:tuple, parts...))))
end

# Kind tables are indexed by kind (medium first) along every axis.
function _check_kind_tables(sys::PottsSystem, p)
    nk = length(getfield(sys, :kinds))
    for x in getfield(sys, :parameters)
        i = info(x)
        i.role === :kindtable || continue
        v = getproperty(p, i.name)
        all(==(nk), size(v)) || throw(ArgumentError("kind table `$(i.name)` has size $(size(v)); the model has $nk kinds " *
                                                    "($(join(getfield(sys, :kinds), ", "))), so it needs $nk entries per axis"))
    end
    return nothing
end

function _acceptance(s::SweepSpec, T)
    if s.law === :barker
        return s.offset == 0 ? CorePotts.Barker() : CorePotts.Barker(T(s.offset))
    end
    return s.offset == 0 ? CorePotts.Metropolis() : CorePotts.Metropolis(T(s.offset))
end

# Keys may be symbolic quantities or their names (`:λ`, `Symbol("clock₊τ")`); relationship
# names (`:bond => [(1, 2)]`) stay symbols.
function _operating_point(sys::PottsSystem, op)
    op = _expand_vectors(sys, Pair{Any, Any}[_localize(sys, k; strict = true) => v for (k, v) in op])
    byname = Dict{Symbol, Any}(info(x).name => _unwrap(x) for x in Iterators.flatten((getfield(sys, :parameters), getfield(sys, :variables))))
    byname[:kind] = _unwrap(B.kind)
    byname[:cluster] = _unwrap(B.cluster)
    byname[:ownership] = CorePotts.ownership
    rels = Set(r.name for r in getfield(sys, :relationships))
    known = Set{Any}(values(byname))
    opd = Dict{Any, Any}()
    for (k, v) in op
        key = k isa Symbol ? get(byname, k, k) : _opkey(k)
        if !(key in known || (key isa Symbol && key in rels))
            _algebraic_key(sys, k)
            throw(ArgumentError(
                "operating-point key `$k` names nothing in model `$(nameof(sys))`; it has parameters " *
                "$(join((info(x).name for x in getfield(sys, :parameters)), ", ")), variables " *
                "$(join((info(x).name for x in getfield(sys, :variables)), ", ")), and `ownership`, `kind`, `cluster`" *
                (isempty(rels) ? "" : ", $(join(rels, ", "))")))
        end
        opd[key] = v
    end
    return opd
end

"""
Operating-point entries for vector quantities (`p => …`, `:p => …`) split into their
components: a number applies to every component; a parameter takes a length-`n` vector; a
variable takes per-cell/site vectors (`[(x, y), …]`) or an array whose last dimension is `n`.
"""
function _expand_vectors(sys::PottsSystem, op)
    vecs = Dict{Symbol, Vector{Any}}()
    for x in Iterators.flatten((getfield(sys, :parameters), getfield(sys, :variables)))
        o = info(x).options
        haskey(o, :vector) || continue
        v = get!(vecs, o.vector, Any[])
        length(v) < o.index && resize!(v, o.index)
        v[o.index] = x
    end
    isempty(vecs) && return op
    out = Pair{Any, Any}[]
    for (k, v) in (op isa AbstractDict ? pairs(op) : op)
        name = k isa QuantityVector ? k.name : k isa Symbol ? k : nothing
        if name !== nothing && haskey(vecs, name)
            comps = vecs[name]
            append!(out, [c => _vector_entry(name, v, i, length(comps), info(c).role) for (i, c) in enumerate(comps)])
        else
            push!(out, k => v)
        end
    end
    return out
end
function _vector_entry(name, v, i, n, role)
    v isa Number && return v
    # a flat numeric vector is the vector itself (for every cell/site); per-entry data are
    # vectors of tuples/vectors or arrays whose last dimension is `n`
    if v isa AbstractVector && eltype(v) <: Number
        length(v) == n || throw(ArgumentError("`$name` has $n components; got $(length(v)) numbers " *
                                              "(per-cell/site values: a vector of $n-tuples or an array whose last dimension is $n)"))
        return v[i]
    end
    role === :param && throw(ArgumentError("`$name` takes $n numbers"))
    v isa AbstractVector && all(e -> e isa Union{AbstractVector, Tuple}, v) && return [e[i] for e in v]
    v isa AbstractArray && size(v, ndims(v)) == n && return copy(selectdim(v, ndims(v), i))
    throw(ArgumentError("values for the $n-component `$name`: a number, per-entry vectors, or an array whose last dimension is $n"))
end

# A variable defined by an algebraic equation (`y ~ expr`, eliminated by `mtkcompile` as an
# observed quantity) has no initial value of its own.
function _algebraic_key(sys::PottsSystem, k)
    name = k isa Symbol ? k : (i = info(_opkey(k)); i === nothing ? nothing : i.name)
    for o in getfield(sys, :observed)
        i = info(o.var)
        (i.name === name && haskey(i.options, :scope)) || continue
        throw(ArgumentError("operating-point key `$k`: `$name` is defined by an algebraic equation in @equations " *
                            "(`mtkcompile` eliminates it as an observed quantity, `$name ~ $(o.expr)`), so it has no " *
                            "initial value; remove it from the operating point"))
    end
    return nothing
end

_opkey(k::typeof(CorePotts.ownership)) = k
_opkey(k) = (u = _unwrap(k); u)

function _parameter_values(c::CompiledPottsSystem, opd)
    values = Dict{Any, Any}()
    for x in getfield(c.sys, :parameters)
        u = _unwrap(x)
        v = haskey(opd, u) ? opd[u] : info(x).default
        v === nothing && throw(ArgumentError("parameter `$(info(x).name)` has no default; give it in the operating point"))
        values[u] = v
    end
    return _resolve_defaults!(values)
end

# a scalar expression, or a kind table (vector/matrix) with an expression among its entries
_is_symbolic(v) = v isa Num || v isa SymbolicUtils.BasicSymbolic
_is_symbolic(v::AbstractArray) = any(_is_symbolic, v)

"""A value given by an expression of parameters, evaluated with the parameter `values`."""
function _evaluate(v, values, who = "`$v`")
    _is_symbolic(v) || return v
    w = _substitute_entry(v, values, who)
    _is_symbolic(w) && throw(ArgumentError("`$v` does not reduce to a number with the parameter values" *
                                           _non_parameters(w)))
    return w
end

"""
The parameters as a `Dict` (symbol → value) after a change naming the parameters `changed`
(names), with values `p`. A computed parameter (its default an expression of parameters, or
a kind table with expression entries) is re-derived from its expression iff it is not named
in the change and one of its inputs is named in the change or is itself re-derived by it
(transitively): `b = 3a` follows a new `a`. Every other parameter keeps its value in `p`, so
an explicit value survives every change that touches none of its inputs.
"""
function _derived_parameters(c::CompiledPottsSystem, p, changed)
    ps = getfield(c.sys, :parameters)
    values = Dict{Any, Any}()
    redo = _rederived(ps, changed)
    for x in ps
        i = info(x)
        values[_unwrap(x)] = i.name in redo ? i.default : getproperty(p, i.name)
    end
    isempty(redo) && return values
    return _resolve_defaults!(values)
end

# The names of the computed parameters a change naming `changed` re-derives (D-112): a fixed
# point over the inputs of the computed defaults. Empty when every parameter is named.
function _rederived(ps, changed)
    redo = Set{Symbol}()
    computed = [x for x in ps if _is_symbolic(info(x).default) && !(info(x).name in changed)]
    isempty(computed) && return redo
    byvar = Dict{Any, Symbol}(_unwrap(x) => info(x).name for x in ps)
    inputs = [Set{Symbol}(byvar[u] for u in _default_inputs(info(x).default) if haskey(byvar, u)) for x in computed]
    grew = true
    while grew
        grew = false
        for (x, ins) in zip(computed, inputs)
            n = info(x).name
            n in redo && continue
            if any(d -> d in changed || d in redo, ins)
                push!(redo, n)
                grew = true
            end
        end
    end
    return redo
end

# the parameters an expression default (scalar, or kind-table entries) reads, unwrapped
_default_inputs(v::AbstractArray) = reduce(vcat, (_default_inputs(e) for e in v); init = Any[])
_default_inputs(v) = _is_symbolic(v) ? Any[_unwrap(u) for u in Symbolics.get_variables(v)] : Any[]

function _resolve_defaults!(values)
    # parameters may default to expressions of other parameters; a kind table's entries may
    # be such expressions (`J[kind, kind] = [0 Jx; Jx 2]`), substituted entry by entry
    for _ in 1:length(values)
        done = true
        for (k, v) in values
            _is_symbolic(v) || continue
            if v isa AbstractArray
                w = map(e -> _substitute_entry(e, values, k), v)
                values[k] = w
                done &= !any(_is_symbolic, w)
            else
                w = _substitute_entry(v, values, k)
                values[k] = w
                done &= !_is_symbolic(w)
            end
        end
        done && break
    end
    return values
end

# One value with the parameter `values` substituted: a number once it reduces to one (D-117).
# What substitution leaves (calls of functions, kind-table reads) is evaluated numerically;
# the expression stays symbolic while it reads a parameter not yet a number, or a quantity
# that is not a parameter (reported by `_param_value`). `who` (a parameter, or a label)
# names the default in errors.
function _substitute_entry(v, values, who)
    _is_symbolic(v) || return v
    w = try
        _unwrap(Symbolics.substitute(v, values))
    catch e     # substitution folds calls on numbers: `sqrt(-1.0)` fails here
        throw(ArgumentError("$(_who(who)) = `$v` fails on the parameter values: $(sprint(showerror, e))"))
    end
    SymbolicUtils.isconst(w) && return SymbolicUtils.unwrap_const(w)
    r = _numeric(w, _who(who))
    return r === _PENDING ? w : r
end
_who(s::AbstractString) = s
_who(k) = (i = info(k); i === nothing ? "`$k`" : "parameter `$(i.name)`")

struct _Pending end
const _PENDING = _Pending()

# The number of a substituted expression: Julia's functions on the evaluated arguments
# (`ifelse` lazily), kind-table reads by kind number (medium = 0). `_PENDING` if a symbol
# (a quantity not yet a number, or not a parameter) or a table with symbolic entries remains.
function _numeric(x, who)
    x = _unwrap(x)
    SymbolicUtils.isconst(x) && (x = SymbolicUtils.unwrap_const(x))
    x isa SymbolicUtils.BasicSymbolic || return _is_symbolic(x) ? _PENDING : x
    SymbolicUtils.iscall(x) || return _PENDING
    op = SymbolicUtils.operation(x)
    args = SymbolicUtils.arguments(x)
    op === random_uniform &&
        throw(ArgumentError("$who draws a random number (`rand()`); a default is evaluated once per build " *
                            "and must be deterministic"))
    if op === ifelse
        c = _numeric(args[1], who)
        c === _PENDING && return c
        return _numeric(c ? args[2] : args[3], who)
    end
    vals = map(a -> _numeric(a, who), args)
    any(a -> a === _PENDING, vals) && return _PENDING
    (op === at || op === at2) && return _table_entry(who, vals...)
    try
        return op(vals...)
    catch e
        throw(ArgumentError("$who: `$x` fails on the parameter values: $(sprint(showerror, e))"))
    end
end

# `t[k…]` of a kind table `t` by kind numbers (medium = 0, then the `@kinds` order)
function _table_entry(who, t, ks...)
    t isa AbstractArray && ndims(t) == length(ks) ||
        throw(ArgumentError("$who reads a kind table with $(length(ks)) kind$(length(ks) == 1 ? "" : "s"); " *
                            "the table takes $(t isa AbstractArray ? ndims(t) : 0)"))
    for k in ks
        k isa Real && isinteger(k) || throw(ArgumentError("$who reads a kind table at `$k`, not a kind number"))
    end
    i = map(k -> Int(k) + 1, ks)
    checkbounds(Bool, t, i...) ||
        throw(ArgumentError("$who reads kind $(join(ks, ", ")) of a kind table with kinds 0:$(size(t, 1) - 1)"))
    return t[i...]
end

# the quantities a symbolic default reads that are not parameters (variables, built-ins)
function _non_parameters(v)
    us = _default_inputs(v)
    out = unique(string(u) for u in us if (i = info(u); i === nothing || !(i.role in (:param, :kindtable))))
    isempty(out) && return ""
    return "; it reads $(join(("`$o`" for o in out), ", ")), which $(length(out) == 1 ? "is not a parameter" : "are not parameters"): " *
           "a default is an expression of parameters, numbers and functions"
end

function _param_value(T, v, i::Info)
    _is_symbolic(v) && throw(ArgumentError("parameter `$(i.name)` = `$(_is_symbolic(i.default) ? i.default : v)` does not " *
                                           "reduce to numbers with the parameter values" * _non_parameters(v)))
    if i.role === :kindtable
        v isa Number && throw(ArgumentError("kind table `$(i.name)` takes a vector (one value per kind) or a matrix; got $v"))
        A = Matrix(v isa AbstractVector ? reshape(v, :, 1) : v)
        v isa AbstractVector && return SVector{length(v), T}(T.(v))
        return SMatrix{size(A, 1), size(A, 2), T}(T.(A))
    end
    return T(v)
end

function _initial_state(c::CompiledPottsSystem, opd, T, capacity, pvals = Dict{Any, Any}())
    sys = c.sys
    haskey(opd, ownership) || throw(ArgumentError("the operating point needs `ownership => labels`"))
    σ = Int32.(opd[ownership])
    size(σ) == getfield(sys, :lattice).dims || throw(ArgumentError("labels have size $(size(σ)); the lattice is $(getfield(sys, :lattice).dims)"))
    all(>=(0), σ) || throw(ArgumentError("labels must be ≥ 0 (0 is medium); got $(minimum(σ))"))
    ncell = maximum(σ; init = Int32(0))
    kkey = _unwrap(B.kind)
    kinds = haskey(opd, kkey) ? opd[kkey] : fill(1, ncell)
    kinds = Int32[k isa Symbol ? _kind_index(sys, k) : _kind_number(k) for k in (kinds isa AbstractVector ? kinds : fill(kinds, ncell))]
    length(kinds) == ncell || throw(ArgumentError("$(length(kinds)) kinds for $ncell labelled cells"))
    nk = length(getfield(sys, :kinds)) - 1
    for k in kinds
        1 <= k <= nk || throw(ArgumentError("kind number $k is out of range: cell kinds are 1:$nk " *
                                            "($(join(getfield(sys, :kinds)[2:end], ", ")))"))
    end
    lat = core_lattice(getfield(sys, :lattice))
    site = Pair{Symbol, Any}[]
    cell = Pair{Symbol, Any}[]
    model = Pair{Symbol, Any}[]
    for x in getfield(sys, :variables)
        i = info(x)
        v = _evaluate(get(opd, _unwrap(x), i.default), pvals, "the default of `$(i.name)`")
        if i.role === :site || i.role === :field
            a = v isa AbstractArray ? T.(v) : fill(T(v), getfield(sys, :lattice).dims)
            push!(site, i.name => a)
            i.name in c.scratch && push!(site, Symbol(i.name, :__next) => copy(a))
        elseif i.role === :cell
            v === nothing && throw(ArgumentError("cell variable `$(i.name)` has no initial value; give it in the operating point"))
            push!(cell, i.name => (v isa AbstractArray ? T.(v) : fill(T(v), ncell)))
        elseif i.role === :edge
            continue                                   # link payloads, below
        elseif i.role === :model
            v === nothing && throw(ArgumentError("model variable `$(i.name)` has no initial value; give it in the operating point"))
            push!(model, i.name => fill(T(v), 1))
        end
    end
    for x in _integrals(sys)
        push!(cell, _integral_name(x) => zeros(T, ncell))
    end
    if c.uses_surface
        push!(cell, :surface => CorePotts.recompute_surface(σ, lat, CorePotts.relation(c.relations[:surface], lat), ncell; T))
    end
    append!(cell, _contact_count_columns(c, σ, kinds, lat, ncell))          # contact folds (D-150)
    _has_bounded_draw(sys) && push!(model, CorePotts.MODEL_STATUS => zeros(UInt32, 1))
    c.needs_moments && append!(cell, pairs(CorePotts.init_moments(σ, lat, ncell)))
    ckey = _unwrap(B.cluster)
    if c.uses_clusters
        ids = haskey(opd, ckey) ? opd[ckey] : 1:ncell
        length(ids) == ncell || throw(ArgumentError("$(length(ids)) cluster ids for $ncell labelled cells"))
        rel = c.uses_cluster_surface ? c.relations[:surface] : nothing
        append!(cell, pairs(CorePotts.init_clusters(σ, ids, lat; relation = rel, T, kind = kinds,
            prefer = _cluster_kinds(c))))
    elseif haskey(opd, ckey)
        throw(ArgumentError("`cluster` in the operating point, but the model uses no compartments"))
    end
    for r in c.relationships                       # one link store per relationship (P6.0b)
        vars = c.edge_vars[r.name]
        links = CorePotts.empty_links(r.capacity, ncell, r.name; (info(x).name => T for x in vars)...)
        store = (; links = links[CorePotts.adjacency_name(r.name)], Base.tail(links)...)
        defaults = (; (info(x).name => T(_edge_initial(x, opd, pvals, r.name)) for x in vars)...)
        for (x, y) in get(opd, r.name, ())
            CorePotts.add_link!(store, x, y; defaults...) ||
                throw(ArgumentError("$(r.name): cannot link cells $x and $y (full row or duplicate)"))
        end
        append!(cell, pairs(links))
    end
    # previous-value snapshots and population slots (D-041, D-042)
    for (scope, n) in unique(Iterators.flatten(values(c.pre_snapshots)))
        dst = scope === :site ? site : scope === :cell ? cell : model
        push!(dst, Symbol(n, :__pre) => copy(last(dst[findfirst(q -> q.first === n, dst)])))
    end
    # scratch slots of discrete components ticking in several phases (P6.0k)
    if _tick_scratch(c)
        for b in c.discrete, x in b.slots
            dst = b.scope === :cell ? cell : model
            n = info(x).name
            push!(dst, _tick_scratch_name(n) => copy(last(dst[findfirst(q -> q.first === n, dst)])))
        end
    end
    for (n, _) in Iterators.flatten((c.update_pops, c.energy_snapshots, c.cell_ode_pops, c.discrete_pops))
        push!(model, n => zeros(T, 1))
    end
    sitent, modelnt = NamedTuple(site), NamedTuple(model)
    history = (; (n => CorePotts.history_buffer(haskey(sitent, n) ? sitent[n] : modelnt[n], d)
                  for (n, d) in sort!(collect(_history_depths(sys)); by = first))...)
    st = CorePotts.initial_state(σ, kinds; cell = NamedTuple(cell), site = sitent, model = modelnt, history)
    cap = capacity === nothing ? (isempty(c.divisions) ? ncell : 2ncell + 64) : capacity
    return cap > ncell ? CorePotts.with_capacity(st, cap) : st
end

# The initial value of edge variable `x` on the initial links of relationship `r`: its
# operating-point value (one number for every initial link, both ends; D-127) or its
# default. Per-link values are not guessed from arrays.
function _edge_initial(x, opd, pvals, r)
    i = info(x)
    haskey(opd, _unwrap(x)) || return i.default
    v = _evaluate(opd[_unwrap(x)], pvals, "the operating-point value of `$(i.name)`")
    v isa Real || throw(ArgumentError("edge variable `$(i.name)`: the operating point takes one number, " *
        "the initial value on every initial link of `$r`; got $(repr(v; context = :limit => true))"))
    return v
end

# The at-init phases (integrals, energy snapshots) on a host state, so a problem's `u0` is
# consistent before `init` (e.g. `total_energy(prob)`).
function _host_init!(f, st, p, ctx, seed, replica, repeat)
    key = CorePotts.RNGKey(seed, replica, repeat)
    CorePotts._run_phases(f.phases.at_init, st, p, ctx, key, 0, CorePotts.CPU())
    return st
end

# Kinds that name clusters (`clusters(k)` terms and divisions): a cluster's root is chosen
# among its members of these kinds, so the filters select it.
_cluster_kinds(c::CompiledPottsSystem) = Tuple(unique(Iterators.flatten((first.(c.cluster_terms)...,
    (d.domain.kinds for d in c.divisions if d.domain isa ClusterDomain)...))))

# Sites of cells of frozen kinds never change owner (walls, obstacles).
function _frozen_mask(sys::PottsSystem, st)
    isempty(getfield(sys, :frozen_kinds)) && return nothing
    kinds = st.cell.kind
    return map(s -> s != 0 && Int(kinds[s]) in getfield(sys, :frozen_kinds), st.σ)
end

_kind_number(k) = Int(k)
_kind_number(g::KindClass) = throw(ArgumentError("`$(g.name)` is a kind class, not a kind: a cell has one kind"))
function _kind_index(sys::PottsSystem, k::Symbol)
    j = findfirst(==(k), getfield(sys, :kinds))
    j === nothing && any(g -> g.name === k, getfield(sys, :kind_classes)) &&
        throw(ArgumentError("`$k` is a kind class, not a kind: a cell has one kind; kinds are $(getfield(sys, :kinds))"))
    j === nothing && throw(ArgumentError("unknown kind `$k`; kinds are $(getfield(sys, :kinds))"))
    j == 1 && throw(ArgumentError("cells cannot have the medium kind `$k`"))
    return j - 1
end

_host_ctx(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...)

"""
    energy_change(prob, u, prop)

The authored energy change of proposal `prop` in state `u` (the model's ΔH without drives).
"""
energy_change(prob::CorePotts.PottsProblem, u, prop) = prob.f.sys.delta_E(u, prob.p, prop, _host_ctx(prob))

"""
    total_energy(prob, u = prob.u0)

The authored Hamiltonian `H` of state `u` (brute force, host), generated from the same
terms as the model's ΔH. A dead cell (`volume == 0`) contributes nothing:
cell terms sum over alive cells, cluster terms over the roots of clusters with at
least one alive member, edge terms over links whose two ends are both alive; free slots
add nothing.

So `ΔH == H(after) − H(before)` for every copy except a killing one (the copy takes the
old owner `o`'s last site), whose ΔH pays o's cell terms down to the empty state (and its
cluster's, if no alive member is left): there `ΔH == H(after) − H(before) + E_cell(o,
empty) [+ E_cluster(empty)]`. Links carry no such credit: the killing copy's ΔH removes
o's edges at their pre-copy energy. With `E_cell(empty) = 0` (e.g. `λ·volume²`) and no
cluster term with `E_cluster(empty) ≠ 0`, ΔH equals the H difference for every copy.
"""
function total_energy(prob::CorePotts.PottsProblem, u = prob.u0)
    info = prob.f.sys
    info isa PottsModelInfo || throw(ArgumentError("not a PottsProblem"))
    return info.total_energy(u, prob.p, _host_ctx(prob))
end

# `remake(prob; p = [λ => 2.0])` and `remake(prob; u0 = [ownership => σ, kind => kinds])`:
# symbolic maps are translated with the problem's scalar type, so the parameter object keeps
# its type and nothing recompiles.
const _SymbolicMap = Union{AbstractVector{<:Pair}, AbstractDict}

CorePotts.remake_parameters(info::PottsModelInfo, prob, p::_SymbolicMap) = _set_parameter_map(info, prob.p, p)

# parameter object `old` with the parameter map `p` applied as one change (D-112)
function _set_parameter_map(info::PottsModelInfo, old::PottsParameters, p)
    p = _expand_vectors(info.csys.sys, Pair{Any, Any}[_localize(info.csys.sys, k; strict = true) => v for (k, v) in p])
    names = Dict{Any, Info}()
    for x in getfield(info.csys.sys, :parameters)
        i = Potts.info(x)
        names[_unwrap(x)] = i
        names[i.name] = i
    end
    new = Dict{Symbol, Any}()
    for (k, v) in p
        key = k isa Symbol ? k : _unwrap(k)
        haskey(names, key) || throw(ArgumentError("`$k` is not a parameter of $(nameof(info.csys))"))
        i = names[key]
        new[i.name] = _param_value(info.T, v, i)
    end
    out = PottsParameters(NamedTuple(k => get(new, k, v) for (k, v) in pairs(NamedTuple(old))))
    return _finish_parameters(info, old, out, Set(keys(new)))
end

# `SII.remake_buffer(prob, prob.p, keys, vals)`: a new parameter object, `remake(prob; p =
# Dict(keys .=> vals)).p` (the original untouched); `sys` is the model's problem, integrator,
# function or description
function SymbolicIndexingInterface.remake_buffer(sys, p::PottsParameters, idxs, vals)
    length(idxs) == length(vals) ||
        throw(DimensionMismatch("remake_buffer: $(length(idxs)) keys, $(length(vals)) values"))
    return _set_parameter_map(_model_info(sys), p, Pair[k => v for (k, v) in zip(idxs, vals)])
end
_model_info(sys::PottsModelInfo) = sys
_model_info(f::CorePotts.CPMFunction) = _model_info(f.sys)
_model_info(x::Union{CorePotts.PottsProblem, CorePotts.PottsIntegrator}) = _model_info(x.f)
_model_info(x) = throw(ArgumentError("remake_buffer: `$(nameof(typeof(x)))` does not describe a Potts model"))

# `remake(prob; p = (λ = 3.0,))`: a NamedTuple is the map of its fields (D-115)
CorePotts.remake_parameters(info::PottsModelInfo, prob, p::NamedTuple) =
    CorePotts.remake_parameters(info, prob, _field_pairs(p))

# a whole parameter object of this problem's type is taken as given (`remake(prob; p = ck.p)`);
# one of another type must have the same names and sets every value, converted to the
# problem's scalar type (a Float32 problem's `p` does not make a Float64 problem Float32)
function CorePotts.remake_parameters(info::PottsModelInfo, prob, p::PottsParameters)
    typeof(p) === typeof(prob.p) && return p
    new, old = keys(NamedTuple(p)), keys(NamedTuple(prob.p))
    if Set(new) != Set(old)
        extra, absent = setdiff(new, old), setdiff(old, new)
        throw(ArgumentError("the parameter object is not one of $(nameof(info.csys))" *
                            (isempty(extra) ? "" : "; not its parameters: $(join(extra, ", "))") *
                            (isempty(absent) ? "" : "; missing: $(join(absent, ", "))")))
    end
    return CorePotts.remake_parameters(info, prob, NamedTuple(p))
end

# SciML's keep sentinels: `p = missing` (SciMLBase's generic `remake`) or `nothing` keeps `prob.p`
CorePotts.remake_parameters(::PottsModelInfo, prob, ::Union{Nothing, Missing}) = prob.p

# a vector or tuple of `Pair`s (of any eltype) is a map; anything else is an error, never a
# silent replacement of `prob.p` (D-115)
function CorePotts.remake_parameters(info::PottsModelInfo, prob, p)
    _is_pairs(p) && return CorePotts.remake_parameters(info, prob, Pair[x for x in p])
    throw(ArgumentError("`p = $(repr(p; context = :limit => true))` is not a parameter map of $(nameof(info.csys)); " *
                        "give a NamedTuple, a vector of `name => value` pairs or a Dict"))
end

_field_pairs(nt::NamedTuple) = Pair{Symbol, Any}[k => v for (k, v) in pairs(nt)]
_is_pairs(p) = (p isa AbstractVector || p isa Tuple) && all(x -> x isa Pair, p)

# Re-derive the expression-defined parameters not set in this change, and check the tables.
function _finish_parameters(mi::PottsModelInfo, old, out, explicit)
    c = mi.csys
    derived = _derived_parameters(c, out, explicit)
    out = PottsParameters(NamedTuple(info(x).name => _param_value(mi.T, derived[_unwrap(x)], info(x))
                                     for x in getfield(c.sys, :parameters)))
    typeof(out) === typeof(old) || throw(ArgumentError("parameter types changed; kind tables keep their size"))
    _check_kind_tables(c.sys, out)
    for name in _contact_tables(c)
        J = getproperty(out, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    return out
end

# `setp`/`integ.ps[x] = v` on an integrator: the same conversion, derivation and checks (A-53)
function CorePotts.set_parameter(info::PottsModelInfo, p::PottsParameters, v, i::Symbol)
    x = findfirst(x -> Potts.info(x).name === i, getfield(info.csys.sys, :parameters))
    x === nothing && throw(ArgumentError("`$i` is not a parameter of $(nameof(info.csys))"))
    q = PottsParameters(merge(NamedTuple(p), NamedTuple{(i,)}((_param_value(info.T, v, Potts.info(getfield(info.csys.sys, :parameters)[x])),))))
    return _finish_parameters(info, p, q, Set([i]))
end

SymbolicIndexingInterface.setp(sys::PottsModelInfo, ps::Union{Tuple, AbstractVector}; run_hook = true) =
    CorePotts.parameter_setter(sys, ps, run_hook)
SymbolicIndexingInterface.setsym(sys::PottsModelInfo, syms::Union{Tuple, AbstractVector}) =
    CorePotts.symbol_setter(sys, syms)

# `setp(integ, [x, y])`: every value set first, then one derivation for the whole change
function CorePotts.set_parameters(info::PottsModelInfo, p::PottsParameters, vals, names)
    params = getfield(info.csys.sys, :parameters)
    new = Dict{Symbol, Any}()
    for (v, i) in zip(vals, names)
        x = findfirst(x -> Potts.info(x).name === i, params)
        x === nothing && throw(ArgumentError("`$i` is not a parameter of $(nameof(info.csys))"))
        new[i] = _param_value(info.T, v, Potts.info(params[x]))
    end
    q = PottsParameters(NamedTuple(k => get(new, k, v) for (k, v) in pairs(NamedTuple(p))))
    return _finish_parameters(info, p, q, Set(keys(new)))
end

# `[frozen]` kinds: the mask follows the kinds, by CorePotts' standard rule (built on the
# device after lifecycle events, D-081; `frozen_varies` follows from it)
CorePotts.frozen_kinds(info::PottsModelInfo) =
    isempty(getfield(info.csys.sys, :frozen_kinds)) ? nothing : Tuple(Int32.(getfield(info.csys.sys, :frozen_kinds)))

# a state given as such (`remake(prob; u0 = st)`, `reinit!(integ, st)`, a saved state of another
# problem of the model): its values, laid out for this problem's ODE scratch
CorePotts.remake_state(info::PottsModelInfo, prob, u0::CorePotts.CPMState) = _ode_layout(u0, info.csys, info.solvers)

# a NamedTuple operating point is the map of its fields (D-115)
CorePotts.remake_state(info::PottsModelInfo, prob, u0::NamedTuple) =
    CorePotts.remake_state(info, prob, _field_pairs(u0))

# `u0 = nothing`/`missing` keeps the problem's state (laid out for this model's functions)
CorePotts.remake_state(info::PottsModelInfo, prob, ::Union{Nothing, Missing}) =
    CorePotts.remake_state(info, prob, prob.u0)

function CorePotts.remake_state(info::PottsModelInfo, prob, u0)
    _is_pairs(u0) && return CorePotts.remake_state(info, prob, Pair[x for x in u0])
    throw(ArgumentError("`u0 = $(repr(u0; context = :limit => true))` is not a state or an operating point of $(nameof(info.csys)); " *
                        "give a state, a NamedTuple, a vector of `variable => value` pairs or a Dict"))
end

function CorePotts.remake_state(info::PottsModelInfo, prob, u0::_SymbolicMap)
    opd = _operating_point(info.csys.sys, u0)
    # keep the old capacity and the old number of free slots (room for divisions)
    old = length(prob.u0.cell.kind)
    free = count(iszero, prob.u0.cell.volume)
    ncell = maximum(Int32.(get(opd, ownership, Int32[])); init = Int32(0))
    values = _derived_parameters(info.csys, prob.p, Set(Potts.info(x).name for x in getfield(info.csys.sys, :parameters)))
    st = _ode_layout(_initial_state(info.csys, opd, info.T, max(old, ncell + free), values), info.csys, info.solvers)
    return _host_init!(prob.f, st, prob.p, info.ctx, prob.seed, prob.replica, prob.repeat)
end
