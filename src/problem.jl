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
    copy_relations::Vector{Symbol}   # the relations the copy step reads (D-208) ...
    copy_fns::Any                    # ... of these generated copy-step functions
end

# CheckerboardCPM's spacing reach (D-208): only the relations the generated copy-step
# functions read, and only while `f` runs exactly those (with no bias). A `CPMFunction` that
# keeps this `sys` but swaps one of them (`remake(prob; f = …)`) may read any relation:
# `nothing`, every relation counts. `anneal`'s zero temperature wraps the generated one.
function CorePotts.copy_step_relations(mi::PottsModelInfo, f)
    g = mi.copy_fns
    f.delta_H === g.delta_H && f.commit! === g.commit! && f.constraint === g.constraint &&
        f.connectivity === g.connectivity &&
        _same_temperature(f.temperature, g.temperature) && f.bias === CorePotts.no_bias &&
        (f.track === nothing || f.track isa CorePotts.TrackEnergyChange) || return nothing
    return mi.copy_relations
end
_same_temperature(t, g) = t === g      # (and `anneal`'s `_ZeroTemperature`, analysis.jl)

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
function generated_code(
        sys; T::Type = Float64, field_solver = nothing, ode_solver = ExplicitEuler(), solvers = (),
        discretization = nothing
    )
    c = sys isa CompiledPottsSystem ? sys : ModelingToolkitBase.mtkcompile(sys)
    return _with_model_scope(() -> _generated_code(c, T, field_solver, ode_solver, solvers, discretization), c)
end
function _generated_code(c, T, field_solver, ode_solver, solvers, discretization)
    spec = _resolve_solvers(c; field_solver, ode_solver, solvers, discretization, T)
    values = Dict{Any, Any}(_unwrap(x) => info(x).default for x in _p(getfield(c, :sys), :parameters))
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
    return (;
        delta_H = _delta_H_expr(c, T), commit! = _commit_expr(c, T), constraint = _constraint_expr(c, T),
        temperature = _temperature_expr(c, T), total_energy = _total_energy_expr(c, T),
        delta_E = _delta_H_expr(c, T; drives = false), phases, lifecycle,
    )
end
"""
    PottsProblem(sys, op, tspan; field_solver = ExplicitEuler(), ode_solver = ExplicitEuler(), solvers = [],
                 discretization = nothing, backend = nothing, T, capacity, seed = 0, replica = 0, repeat = 0, track = (),
                 initializealg = nothing, expression = Val(false))

Build the numerical problem from a `PottsSystem` (compiled with `mtkcompile` if
needed). `op` maps `ownership` to the initial labels (an integer array over the lattice),
`kind` to the kinds of the labeled cells (names or numbers), `cluster` to their
compartment groups (any ids; equal ids form one cluster; default: every cell alone), variables to initial values
(scalars or arrays), parameters to values overriding their defaults, and a relationship's
name to its initial links (`:bond => [(1, 2)]`). An edge variable takes one number (or
a parameter expression, evaluated at construction: a later `remake` of parameters does not
re-seed it), its initial value on every initial link of its relationship (both ends;
default: its declared default); links made later by `@link` start at the declared default. `T` is the scalar
type of the generated code and state: by default `Float64`, or the default float type of
`backend` when one is given (`Float32` on a device, `LatticeFields.Exec.default_float`; pass
the same backend to `init`/`solve`). A field declared `@variables c(..) = 0.5 [lattice_storage = S]` in its PDESystem
(`Float16`, `Float32` or `Float64`) is stored in `S` and computed in its field solver's
`compute_type` (default `T`). The generated code is `Potts.generated_code(sys; T)`.

`initializealg` is SciML's initialization algorithm, used here when the problem is built (the
state is initialized then; `init` and `solve` accept only the problem's own or `NoInit()`,
which change nothing). The default solves the
model's initialization equations (`@initialization_equations`, operating-point values of
algebraic variables) per entity, as `OverrideInit()` does. `OverrideInit(; abstol, reltol,
nlsolve)` sets the nonlinear solver (`nlsolve`, run once from the guesses) and its
tolerances: a condition passes when its residual is at most `abstol`, or at most `reltol`
(default `1e-9`) times the size of its terms. `CheckInit()` checks the values the state is
built with against the conditions (a `SciMLBase.CheckInitFailureError` when one fails), and
`NoInit()` keeps them unchecked. `remake(prob; u0)` initializes the new state the same way,
and `remake(prob; u0, initializealg)` with the given one (which the new problem keeps).

How fields and ODEs are integrated is part of the problem, compiled into its code:
- `field_solver = ExplicitEuler(; substeps, lower_bound)` integrates the fields, and is an error
  when the model has none. The default is `ExplicitEuler()`: the automatic substep count
  from the stability bound, no clip. A published model's docstring gives the paper's value
  (e.g. `ExplicitEuler(substeps = 2, lower_bound = 0.0)` for `MerksVasculogenesis`).
  It steps each field over one MCS in `substeps` explicit Euler steps, clipping each result
  at `lower_bound` if given (legacy Potts clips concentrations at 0); the window
  is the MCS. `substeps = nothing` takes the smallest count `n` with
  `mcs_duration / n · ρ ≤ 1.8`, where `ρ` is the field compiler's Gershgorin bound on the
  spectral radius of the discrete right-hand side at the current parameters (diffusion
  `D · Σ_d 4/h_d²`, a kind-table or kind-set multiplier at its largest, plus the size of each
  reaction coefficient). A group whose rate gives no bound from the parameters (a reaction
  nonlinear in the field, a multiplier reading a CPM value or `mcs`, `÷`, a rate reading
  another field whose Jacobian row is not diagonally dominant) needs an explicit `substeps`;
  without one, `PottsProblem` throws an `ArgumentError`. An explicit `n` is a minimum: the
  count is at least the bound of the terms the bound sees, and a warning (once per group,
  term and cause) names the others. A negative diffusion coefficient, or a coefficient that
  is not finite at a kind table entry, is an `ArgumentError`;
- `ode_solver` integrates the cell and model ODEs (`D(x) ~ …`, components): `ExplicitEuler(;
  substeps)` (the default, one step per MCS), `Potts.RK4(; substeps)` or `Adaptive(alg; reltol, …)`;
- `solvers = [x => solver, …]`, keyed by integrated variables (or a component: all its
  unknowns), overrides them for those variables only (a stiff ODE under
  `Adaptive(Rodas5P())` beside explicit ones). Every ODE step reads the state at the start
  of the step (Jacobi), across solvers too;
- `discretization` (any `SciMLBase.AbstractDiscretization`) discretizes the fields. Left out,
  or a `LatticeDiscretization(Grid(dims))` of the model's lattice, the fields are the fused
  lattice fields described above. Any other discretization steps the problem
  `discretize(Potts.fields(model), discretization; inputs)` over each MCS window, solved with
  `field_solver` (required: a SciML algorithm such as `Tsit5()`), on the CPU. Each window
  starts from the fields' current values and the CPM inputs at that MCS
  ([`Potts.field_inputs`](@ref) names them). The discretization must take
  `inputs = [name => array, …]` and give an integrator that reads and writes each field by
  name (`getu`, `setu`) and sets each input and parameter by name (`setp`).

`remake(prob; field_solver | ode_solver | solvers | discretization = …)` rebuilds the code with the keywords
it names and keeps the others, `u0`, `p` and the seed; the problem fingerprint hashes a
canonical form of the resolved solvers, so a checkpoint loads only into an equally
discretized problem.
`track = (:energy_change,)` accumulates the ΔH of every committed copy (energy plus every drive, as
`prob.f.delta_H` returns it; not the acceptance law's offset) into `sol.stats.accepted_energy_change`
(a `Float64`; `nothing` with the default `track = ()`). Under `SequentialCPM` it is exact
after every step; under `CheckerboardCPM` it is brought up to date at the host read points
(a save, `current_state`, `checkpoint`, the end of `solve!`). Tracking changes nothing else
in the run; it is hashed into the fingerprint (only when on), and `remake(prob; track)`
switches it. `track = (:references,)` is the debug mode of cell references (R6): every
dereference of a dead referent (a nonzero reference to a cell that is not alive, which reads
as the medium) is counted per term (cell energy group, drive, constraint, temperature,
update, division), as is every `sibling(k)` scan that found several alive members of kind `k`
(the lowest `birth` is returned); `solve` reports the counts once, in one warning. Nothing of
it is compiled into an untracked problem.

A ForwardDiff `Dual` for a parameter, or as a field's initial value, runs: the fields carry
derivative parts along the run's CPM path, which is held fixed (see
[Derivatives with ForwardDiff](@ref manual-derivatives)).
"""
function CorePotts.PottsProblem(sys::PottsSystem, op, tspan; kwargs...)
    return CorePotts.PottsProblem(ModelingToolkitBase.mtkcompile(sys), op, tspan; kwargs...)
end

function CorePotts.PottsProblem(
        c::CompiledPottsSystem, op, tspan; backend = nothing,
        T::Type = backend === nothing ? Float64 : LatticeFields.Exec.default_float(backend), capacity = nothing,
        seed = 0, replica = 0, repeat = 0, expression = Val(false), field_solver = nothing,
        ode_solver = ExplicitEuler(), solvers = (), discretization = nothing, track = (), initializealg = nothing, kwargs...
    )
    sys = getfield(c, :sys)
    init = _init_options(initializealg)
    spec = _resolve_solvers(c; field_solver, ode_solver, solvers, discretization, T)
    spec.discretization === nothing || backend === nothing || backend isa KernelAbstractions.CPU || throw(
        ArgumentError(
            string(
                "`discretization = ", repr(spec.discretization), "`: its fields step on the host; give a CPU backend, ",
                "or leave `discretization` out"
            )
        )
    )
    track = _track(track)
    opd = _operating_point(sys, op)
    seeds, u0seeds = _split_tangents!(sys, opd)     # Dual values: their primal values in `opd` (F3-21b)
    values = _parameter_values(c, opd)
    p = PottsParameters(
        NamedTuple(
            info(x).name => _param_value(T, values[_unwrap(x)], info(x); ps = _p(sys, :parameters))
                for x in _p(sys, :parameters)
        ),
        _computed_tag(_p(sys, :parameters))
    )
    _register_derivation!(_p(sys, :parameters), T, p)
    for name in _contact_tables(c)
        J = getproperty(p, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    _check_kind_tables(sys, p)
    expression isa Val{true} && throw(
        ArgumentError(
            "`expression = Val(true)` is not supported; use `Potts.generated_code(sys; T)` to inspect the code"
        )
    )
    st = _track_layout(_ode_layout(_initial_state(c, opd, T, capacity, values, init), c, spec), c, track)
    lat = core_lattice(_p(sys, :lattice))
    relations = _with_contact_counts(c, NamedTuple(k => v for (k, v) in _sorted(getfield(c, :relations))))
    spacing = _p(sys, :lattice).spacing === nothing ? nothing : map(T, _p(sys, :lattice).spacing)
    hctx = (;
        lattice = lat, contact = CorePotts.relation(getfield(c, :contact_spec), lat),
        map(r -> CorePotts.relation(r, lat), relations)...,
        (spacing === nothing ? (;) : (; spacing))...,
    )
    f = _problem_function(c, T, spec, values, hctx, Dict{Any, Any}(); track)
    _check_field_substeps(f, p; tspan)
    frozen = _frozen_mask(sys, st)
    _host_init!(f, st, p, hctx, seed, replica, repeat, NamedTuple(kwargs))
    tangent = isempty(seeds) && isempty(u0seeds) ? nothing : _tangent(c, T, p, seeds, opd; u0 = u0seeds)
    return CorePotts.PottsProblem(
        f, st, lat, tspan, p; contact = getfield(c, :contact_spec), proposal = getfield(c, :proposal_spec), relations,
        spacing, frozen, seed, replica, repeat, tangent, kwargs...,
        (initializealg === nothing ? (;) : (; initializealg))...
    )
end

# ---------------------------------------------------------------------------------------
# Parameters with derivative parts (F3-21b). A ForwardDiff `Dual` given for a parameter (in the
# operating point or `remake(prob; p = …)`) runs: the problem's parameter object holds its primal
# value (the CPM, the ODEs and every kernel read it: the run is the primal run, bit for bit), and
# `prob.tangent` holds the parameter object with the Duals (the computed parameters that read a
# seeded one derived again in Duals). The field groups step the derivative parts along the run's
# CPM path (CorePotts' shadow tangent store): the derivative is pathwise, the CPM path held fixed.

# a value with derivative parts (one level of a ForwardDiff Dual)
_is_dual(v) = v isa Real && LatticeFields.Compile.npartials(typeof(v)) > 0
_has_dual(v) = _is_dual(v) || (v isa AbstractArray && (LatticeFields.Compile.npartials(eltype(v)) > 0 || any(_is_dual, v)))
_tprimal(v) = _is_dual(v) ? LatticeFields.Compile.primal(v) : v

# the Dual parameter values of operating point `opd` (`name => Dual`) and the Dual initial values
# of its fields (`name => Dual array or number`), each replaced in `opd` by its primal value; a
# Dual in a kind table or in another variable's initial value is refused in words
function _split_tangents!(sys::PottsSystem, opd)
    seeds, u0 = Pair{Symbol, Any}[], Pair{Symbol, Any}[]
    for (k, v) in collect(opd)
        _has_dual(v) || continue
        i = info(k)
        if i !== nothing && i.role === :param && _is_dual(v)
            push!(seeds, i.name => v)
            opd[k] = _tprimal(v)
        elseif i !== nothing && i.role === :field
            push!(u0, i.name => v)
            opd[k] = v isa AbstractArray ? map(_tprimal, v) : _tprimal(v)
        else
            _refuse_dual_value(i === nothing ? string(k) : string(i.name), i === nothing ? nothing : i.role, v)
        end
    end
    return seeds, u0
end
function _refuse_dual_value(name, role, v)
    w = v isa AbstractArray ? first(x for x in v if _is_dual(x)) : v
    what = role === :kindtable ? "kind table `$name` holds" : role === :param ? "parameter `$name` holds" :
        "the initial value of `$name` holds"
    throw(
        ArgumentError(
            string(
                what, " ", _valtext(w), ": derivatives run through scalar parameters and the ",
                "initial values of fields (F3-21b); not through ", role === :kindtable ? "kind tables (a later feature)" :
                    "the initial values of cell, model or site variables (the CPM's state, held fixed)",
                ". Take finite differences, or give the derivative's direction a scalar parameter"
            )
        )
    )
end

# the problem's `ParameterTangent`: the parameter object `p` with the seeds as Duals of the
# problem's scalar type `T`, the computed parameters that read a seeded one derived again in Duals,
# and the initial fields' derivative parts: the Dual initial values `u0` given, and the defaults
# that read a seeded parameter evaluated in Duals (with `opd`, the operating point: a construction)
function _tangent(c::CompiledPottsSystem, T, p::PottsParameters, seeds, opd = nothing; u0 = Pair{Symbol, Any}[])
    sys = getfield(c, :sys)
    ps = _p(sys, :parameters)
    first_seed = isempty(seeds) ? first(u0) : first(seeds)
    _has_fields(c) || throw(
        ArgumentError(
            string(
                isempty(seeds) ? "the initial value of `" : "parameter `", first_seed.first,
                "` holds ", _valtext(first(_dualvals(first_seed.second))), "; model `", nameof(c), "` has no fields, and derivative ",
                "parts run through the fields only (F3-21b): the CPM and the ODEs take plain numbers. Take finite differences of the run"
            )
        )
    )
    Es = unique(
        Any[
            LatticeFields.Compile.withvaltype(v isa AbstractArray ? eltype(v) : typeof(v), T)
                for (_, v) in Iterators.flatten((seeds, u0))
        ]
    )
    length(Es) == 1 || throw(
        ArgumentError(
            string(
                "the values with derivative parts hold ", length(Es),
                " different Dual types (different tags or derivative part counts): give every seed of one problem the same ",
                "Dual type (one `ForwardDiff.derivative`, `gradient` or `jacobian` call)"
            )
        )
    )
    nt = NamedTuple(p)
    vals = Dict{Symbol, Any}(pairs(nt))
    for (n, v) in seeds
        nt[n] isa AbstractFloat || throw(
            ArgumentError(
                string(
                    "parameter `", n, "` holds ", _valtext(v), "; it is ",
                    "a ", typeof(nt[n]), " parameter, and derivative parts run through floating-point parameters only"
                )
            )
        )
        vals[n] = LatticeFields.Compile.lanecast(T, v)
    end
    dp = _dual_object(c, T, p, vals)
    dual = Set{Symbol}(k for (k, v) in pairs(NamedTuple(dp)) if _is_dual(v))
    _check_tangent_reads(c, T, dual)
    init = collect(Pair{Symbol, Any}, u0)
    if opd !== nothing && !isempty(dual)
        # a field's default that reads a parameter with derivative parts: evaluated in Duals
        dvals = Dict{Any, Any}(_unwrap(x) => getproperty(dp, info(x).name) for x in ps)
        for x in _p(sys, :variables)
            i = info(x)
            (i !== nothing && i.role === :field && !haskey(opd, _unwrap(x))) || continue
            any(u -> (j = info(u); j !== nothing && j.name in dual), _default_inputs(i.default)) || continue
            v = _evaluate(i.default, dvals, "the default of `$(i.name)`")
            _is_dual(v) && push!(init, i.name => LatticeFields.Compile.lanecast(T, v))
        end
    end
    return CorePotts.ParameterTangent(dp, collect(Pair{Symbol, Any}, seeds), init)
end
_dualvals(v) = v isa AbstractArray ? [x for x in v if _is_dual(x)] : [v]

# parameter object `p` with the values `vals` (some Duals), the computed parameters that read one
# derived again in Duals (the others keep `p`'s values)
function _dual_object(c::CompiledPottsSystem, T, p::PottsParameters, vals::Dict{Symbol, Any})
    if !isempty(_computed(p))
        d = _derivation(_p(getfield(c, :sys), :parameters))
        for (n, v) in zip(d.computed, d(Tuple(vals[b] for b in d.base)))
            vals[n] = _is_dual(v) ? LatticeFields.Compile.lanecast(T, v) : getproperty(p, n)
        end
    end
    return _with_values(p, NamedTuple(k => vals[k] for k in keys(NamedTuple(p))))
end

# a write on a run with derivative parts (F3-21b r1 S1): the base entries the write left unchanged
# keep their derivative parts, the written ones are plain, the computed ones are derived again
function CorePotts.tangent_parameters(info::PottsModelInfo, dp::PottsParameters, p::PottsParameters)
    ps = _p(getfield(info.csys, :sys), :parameters)
    nt = NamedTuple(p)
    vals = Dict{Symbol, Any}(pairs(nt))
    for (k, v) in pairs(NamedTuple(dp))
        _computed_entity(ps, k) === nothing && _is_dual(v) && isequal(LatticeFields.Compile.primal(v), nt[k]) && (vals[k] = v)
    end
    return _dual_object(info.csys, info.T, p, vals)
end

# a parameter with derivative parts read where the derivative would be dropped: a field input the
# CPM fills (computed each MCS in primal values; e.g. an `ifelse` of CPM reads only, filled whole)
function _check_tangent_reads(c::CompiledPottsSystem, T, dual::Set{Symbol})
    _has_fields(c) || return nothing
    reads(e) = [info(u).name for u in _default_inputs(e) if (j = info(u); j !== nothing && j.role === :param && j.name in dual)]
    for (name, ex, _) in _field_inputs(c, T)
        r = reads(ex)
        isempty(r) && continue
        throw(
            ArgumentError(
                string(
                    "the field equations read `", _input_word(name, ex), "`, which the CPM computes ",
                    "each MCS from `", first(r), "`, a parameter with derivative parts; the CPM computes in primal values, so ",
                    "that derivative would be lost (F3-21b): write `", first(r), "` outside the CPM read in the field equation ",
                    "(an `ifelse` of CPM reads is filled whole: move the parameter out of its branches), or take finite differences"
                )
            )
        )
    end
    return nothing
end

# `remake(prob; p = …)`: the seeds of the old problem that the new map does not set, and the Duals
# of the new map; `nothing` when none is left
Base.@nospecializeinfer function CorePotts.remake_tangent(
        @nospecialize(info::PottsModelInfo), @nospecialize(prob),
        @nospecialize(pgiven), @nospecialize(pnew)
    )
    (pgiven === nothing || pgiven === missing) && return prob.tangent
    given = _given_names(info, pgiven)
    old = prob.tangent === nothing ? Pair{Symbol, Any}[] : prob.tangent.seeds
    seeds = Pair{Symbol, Any}[s for s in old if !haskey(given, s.first)]
    append!(seeds, [n => v for (n, v) in given if _is_dual(v)])
    # (the initial fields' derivative parts stay: the state is kept; `remake` drops them with a new one)
    u0 = prob.tangent === nothing ? Pair{Symbol, Any}[] : prob.tangent.u0
    isempty(seeds) && isempty(u0) && return nothing
    return _tangent(info.csys, info.T, pnew, seeds; u0)
end
# the names a parameter map sets, with the values as given
Base.@nospecializeinfer function _given_names(@nospecialize(info::PottsModelInfo), @nospecialize(p))
    p isa PottsParameters && return Dict{Symbol, Any}(k => v for (k, v) in pairs(NamedTuple(p)))
    p isa NamedTuple && return Dict{Symbol, Any}(pairs(p))
    _is_pairs(p) && (p = Pair[x for x in p])
    p isa _SymbolicMap || return Dict{Symbol, Any}()
    sys = getfield(info.csys, :sys)
    out = Dict{Symbol, Any}()
    for (k, v) in _expand_vectors(sys, Pair{Any, Any}[_localize(sys, k; strict = true) => v for (k, v) in p])
        key = k isa Symbol ? k : _unwrap(k)
        i = key isa Symbol ? nothing : Potts.info(key)
        out[i === nothing ? key : i.name] = v
    end
    return out
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
    sys = getfield(c, :sys)
    # `track = (:references,)` (E4/E5): the dereference counters are compiled in; else nothing is
    slots = :references in track ? _ref_count_slots(c) : nothing
    fns, generated = Base.ScopedValues.with(_REF_SLOTS => slots) do
        _recording() do
            _with_model_scope(c) do
                # the build order is the fingerprint's (D-016); the log ranges mark the copy-step code
                glog = _GENERATED[]
                i0 = length(glog)
                ce = _with_ref_term(() -> _constraint_expr(c, T), "@constraint")
                delta_H = _rgf(_delta_H_expr(c, T))
                commit! = _rgf(_commit_expr(c, T))
                constraint = ce === nothing ? CorePotts.always : _rgf(ce)
                temperature = _rgf(_with_ref_term(() -> _temperature_expr(c, T), "@sweep temperature"))
                i1 = length(glog)
                phases = _phases_parts(c, T, values, spec)
                lifecycle = _with_ref_term(() -> _lifecycle(c, T), "@divide")
                total = _rgf(_total_energy_expr(c, T))
                # `energy_change` (host, on the caller's state) is never tracked: it must not bump the
                # state's `#ref_counts` (built in place, so the fingerprint's build order is kept)
                delta_E = Base.ScopedValues.with(() -> _rgf(_delta_H_expr(c, T; drives = false)), _REF_SLOTS => nothing)
                i2 = length(glog)
                connectivity = _connectivity_hooks(c, T)
                copy_step = [glog[(i0 + 1):i1]; glog[(i2 + 1):end]]
                (; delta_H, commit!, constraint, temperature, phases, lifecycle, total, delta_E, connectivity, copy_step)
            end
        end
    end
    phases, lifecycle = _fuse_before(c, T, fns.phases[1], fns.lifecycle, fns.phases[2])
    # a shell-based quantity on a periodic axis of length 1 reads the target as its own
    # neighbour: refused on the host, at build, by the one CorePotts check
    foreach(q -> CorePotts.check_shell_lattice(hctx.lattice, q), _shell_quantities(generated))
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
    # the MCS length, which solvers keep as data (`Adaptive`'s dt, a field phase's `dt`)
    _p(sys, :sweep).mcs_duration == 1 || push!(cad, "mcs_duration=$(repr(_p(sys, :sweep).mcs_duration))")
    # the acceptance law and its offset, solver data in `CPMFunction.acceptance` (D-121); only
    # non-default values (Metropolis, offset 0), so the default keeps its fingerprint. The
    # offset is a Float64 in `SweepSpec`, so `offset = 2` and `offset = 2.0` hash alike.
    _p(sys, :sweep).law === :metropolis || push!(cad, "law=$(_p(sys, :sweep).law)")
    _p(sys, :sweep).offset == 0 || push!(cad, "offset=$(repr(_p(sys, :sweep).offset))")
    # the proposal and contact neighbourhoods, run data outside the generated code (D-122):
    # each resolved on the lattice and hashed with its role when it differs from its default
    # (proposal `VonNeumann(1)`, contact the lattice's `neighborhood`). A default that does
    # not resolve on this lattice (it aliases on a thin periodic axis) is unused here, so it
    # is resolved leniently and any resolvable relation differs from it.
    lat = hctx.lattice
    for (role, nb, default) in (
            ("proposal", getfield(c, :proposal_spec), CorePotts.VonNeumann(1)),
            ("contact", getfield(c, :contact_spec), _p(sys, :lattice).neighborhood),
        )
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
    names = keys(getfield(c, :relations))
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
    # the relations the copy step reads (D-208): those the copy-step functions (ΔH with its
    # edge energies and drives, commit!, constraint, temperature, connectivity hooks) read as
    # `ctx.<name>`, and every run-context entry that is not a gather relation (the contact
    # relation, `contact_counts`), and `surface` (read by `surface_change` through a keyword
    # default, not a literal `ctx.surface`; the footprint covers it). A relation read only at the MCS boundary (lifecycle, link
    # rules, boundary updates, ODEs, observed) is not among them. The declared footprint is
    # unchanged; CheckerboardCPM's spacing covers the reach of these only.
    copy_used = Set{Symbol}()
    foreach(ex -> _ctx_reads!(copy_used, ex, keys(hctx)), fns.copy_step)
    copy_relations = Symbol[
        k for k in keys(hctx)
            if k ∉ (:lattice, :spacing) && (k in copy_used || k === :surface || !haskey(getfield(c, :relations), k))
    ]
    copy_fns = (; fns.delta_H, fns.commit!, fns.constraint, fns.temperature, fns.connectivity)
    return CorePotts.CPMFunction(
        fns.delta_H; fns.commit!, fns.constraint, fns.temperature,
        phases, lifecycle, acceptance = _acceptance(_p(sys, :sweep), T),
        footprint = getfield(c, :footprint), fingerprint = _code_hash(generated, h),
        sys = PottsModelInfo(c, T, fns.total, fns.delta_E, hctx, cache, spec, copy_relations, copy_fns),
        track = :energy_change in track ? CorePotts.TrackEnergyChange{T}() : nothing, fns.connectivity
    )
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
_fingerprint_seed(sys::PottsSystem, T) = string(
    "lattice=", _canonical_value(core_lattice(_p(sys, :lattice))),
    ";spacing=", _canonical_value(_p(sys, :lattice).spacing), ";neighborhood=", _canonical_neighborhood(sys),
    ";T=", string(T)
)
# The neighbourhood by content. A neighbourhood that holds a compiler-generated name (an
# anonymous weight, `Weighted(Moore(1), o -> 1 / norm(o))`) printed as `var"#24#25"`, a number
# that depends on what was defined before it in the session (F4-E15), so it is written by its
# offsets and weights on the lattice instead. Every other neighbourhood keeps its printed form,
# and so its fingerprint.
function _canonical_neighborhood(sys::PottsSystem)
    nb = _p(sys, :lattice).neighborhood
    s = _canonical_value(nb)
    occursin("var\"#", s) || return s
    r = CorePotts.relation(nb, core_lattice(_p(sys, :lattice)))
    return string("resolved(", r.offsets, ";", r.weights, ")")
end

# `remake(prob; field_solver | ode_solver | solvers = …)`: the problem's code rebuilt through
# the codegen point with the named keywords replaced and the others kept, and `u0` re-laid
# out for its ODE scratch (values kept; CorePotts keeps p, the seed and the frozen mask).
# Never reached by `remake(prob; p | u0 | seed)`.
function CorePotts.remake_function(
        mi::PottsModelInfo, prob; field_solver = mi.solvers.field_solver,
        ode_solver = mi.solvers.ode_solver, solvers = nothing, discretization = mi.solvers.discretization,
        track = _track_names(prob), kwargs...
    )
    isempty(kwargs) || throw(
        ArgumentError(
            "remake: unknown keyword$(length(kwargs) == 1 ? "" : "s") $(join(("`$k`" for k in keys(kwargs)), ", ")); " *
                "supported keywords are `u0`, `p`, `tspan`, `seed`, `replica`, `repeat`, `field_solver`, `ode_solver`, " *
                "`solvers`, `discretization`, `track`, `initializealg`, `f`"
        )
    )
    c = mi.csys
    kept = solvers === nothing                      # the problem's `solvers` (named in a clash)
    spec = _resolve_solvers(
        c; field_solver, ode_solver, solvers = kept ? mi.solvers.solvers : solvers, kept, discretization,
        mi.T
    )
    values = _parameter_dict(c, prob.p)
    track = _track(track)
    f = _problem_function(c, mi.T, spec, values, mi.ctx, mi.cache; track)
    _check_field_substeps(f, prob.p; prob.tspan)   # the policy's refusals at `remake`, as at the build
    return f, _track_layout(_ode_layout(prob.u0, c, spec), c, track)
end

# `track` (D-140): the quantities a run accumulates into its statistics. Only `:energy_change` (each
# committed copy's ΔH → `stats.accepted_energy_change`) for now; per-term names wait for R18.
const _TRACKABLE = (:energy_change, :references)
function _track(track)
    (track isa Union{Tuple, AbstractVector} && all(x -> x isa Symbol, track)) || throw(
        ArgumentError(
            "`track` must be a tuple of names, e.g. `track = (:energy_change,)`; got $(repr(track))"
        )
    )
    for x in track
        x in _TRACKABLE || throw(ArgumentError("`track`: `:$x` cannot be tracked (trackable: $(join(repr.(_TRACKABLE), ", ")))"))
    end
    allunique(track) || throw(ArgumentError("`track`: a name is given twice in $(repr(track))"))
    return Tuple(track)
end
_track_names(f::CorePotts.CPMFunction) = f.track === nothing ? () : (:energy_change,)
_track_names(prob::CorePotts.PottsProblem) =
    (_track_names(prob.f)..., (haskey(prob.u0.model, REF_COUNTS) ? (:references,) : ())...)

# The reference counters of a tracked problem (`track = (:references,)`, E4/E5): one `UInt32`
# per term of `_ref_count_labels`, in `st.model`; removed from a state of an untracked one
function _track_layout(st::CorePotts.CPMState, c::CompiledPottsSystem, track)
    on = :references in track
    on == haskey(st.model, REF_COUNTS) && return st
    model = on ? merge(st.model, NamedTuple{(REF_COUNTS,)}((fill!(similar(st.cell.kind, UInt32, length(_ref_count_labels(c))), 0),))) :
        NamedTuple(k => v for (k, v) in pairs(st.model) if k !== REF_COUNTS)
    return CorePotts.CPMState(st.ownership, st.cell, st.site, model, st.history)
end

# After a solve (E4/E5): one warning with the counts of a tracked problem, which are then reset
function CorePotts.report_run(info::PottsModelInfo, integ)
    model = integ.state.model
    haskey(model, CorePotts.CONVERT_FLAGS) && _report_converts(info, integ)
    haskey(model, REF_COUNTS) || return nothing
    counts = CorePotts._to_host(getfield(integ, :stats), getfield(model, REF_COUNTS))
    any(>(0), counts) || return nothing
    labels = _ref_count_labels(info.csys)
    lines = String[]
    for (j, n) in enumerate(counts)
        n > 0 || continue
        push!(
            lines, labels[j] == _SIBLING_LABEL || endswith(labels[j], "(it converts nothing)") ? "$(labels[j]): $n time(s)" :
                "$(labels[j]) read a dead referent $n time(s) (it reads as the medium; guard with `alive(ref)`)"
        )
    end
    @warn "references in $(nameof(info.csys)) (track = (:references,)):\n  " * join(lines, "\n  ")
    fill!(getfield(model, REF_COUNTS), 0)
    return nothing
end

# The ODE scratch slots `x__ode` a state needs for solvers `spec` (several solver groups in a
# scope, or cell ODEs reading other cells' unknowns: `_ode_scratch`), each starting as a
# copy of its variable; any others removed. The same state if its layout already fits.
function _ode_layout(@nospecialize(st), c::CompiledPottsSystem, spec::SolverSpec)
    slots = Set(_ode_scratch_name(info(x).name) for (x, _) in Iterators.flatten((getfield(c, :cell_odes), getfield(c, :model_odes))))
    scratchless(nt) = NamedTuple(k => v for (k, v) in pairs(nt) if !(k in slots))
    function add(nt, scope, odes)
        _ode_scratch(c, spec, scope) || return nt
        return merge(nt, NamedTuple(_ode_scratch_name(info(x).name) => copy(getproperty(nt, info(x).name)) for (x, _) in odes))
    end
    cell = add(scratchless(st.cell), :cell, getfield(c, :cell_odes))
    model = add(scratchless(st.model), :model, getfield(c, :model_odes))
    keys(cell) == keys(st.cell) && keys(model) == keys(st.model) && return st
    return CorePotts.CPMState(st.ownership, cell, st.site, model, st.history)
end

# Kind tables are indexed by kind (medium first) along every axis.
function _check_kind_tables(sys::PottsSystem, p)
    nk = length(_p(sys, :kinds))
    for x in _p(sys, :parameters)
        i = info(x)
        i.role === :kindtable || continue
        v = getproperty(p, i.name)
        all(==(nk), size(v)) || throw(
            ArgumentError(
                "kind table `$(i.name)` has size $(size(v)); the model has $nk kinds " *
                    "($(join(_p(sys, :kinds), ", "))), so it needs $nk entries per axis"
            )
        )
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
    byname = Dict{Symbol, Any}(info(x).name => _unwrap(x) for x in Iterators.flatten((_p(sys, :parameters), _p(sys, :variables))))
    byname[:kind] = _unwrap(B.kind)
    byname[:cluster] = _unwrap(B.cluster)
    byname[:ownership] = CorePotts.ownership
    # an algebraic variable's value is an initial condition `y ~ value` (D-170, initialization.jl),
    # keyed by its name or by its symbol as declared in `@variables`
    algebraic = Dict{Symbol, Any}(info(o.lhs).name => _unwrap(o.lhs) for o in _algebraic_observed(sys))
    merge!(byname, algebraic)
    rels = Set(r.name for r in _p(sys, :relationships))
    known = Set{Any}(values(byname))
    opd = Dict{Any, Any}()
    for (k, v) in op
        key = k isa Symbol ? get(byname, k, k) : _opkey(k)
        if !(key in known) && !isempty(algebraic)
            i = info(key)
            i !== nothing && i.role in _ODE_SCOPES && (key = get(algebraic, i.name, key))
        end
        if !(key in known || (key isa Symbol && key in rels))
            throw(
                ArgumentError(
                    "operating-point key `$k` names nothing in model `$(nameof(sys))`; it has parameters " *
                        "$(join((info(x).name for x in _p(sys, :parameters)), ", ")), variables " *
                        "$(join((info(x).name for x in _p(sys, :variables)), ", ")), and `ownership`, `kind`, `cluster`" *
                        (isempty(rels) ? "" : ", $(join(rels, ", "))")
                )
            )
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
    for x in Iterators.flatten((_p(sys, :parameters), _p(sys, :variables)))
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
        length(v) == n || throw(
            ArgumentError(
                "`$name` has $n components; got $(length(v)) numbers " *
                    "(per-cell/site values: a vector of $n-tuples or an array whose last dimension is $n)"
            )
        )
        return v[i]
    end
    role === :param && throw(
        ArgumentError(
            "parameter `$name` has $n components and takes a number or a length-$n vector of numbers; got $(repr(v; context = :limit => true))"
        )
    )
    v isa AbstractVector && all(e -> e isa Union{AbstractVector, Tuple}, v) && return [e[i] for e in v]
    v isa AbstractArray && size(v, ndims(v)) == n && return copy(selectdim(v, ndims(v), i))
    throw(ArgumentError("values for the $n-component `$name`: a number, per-entry vectors, or an array whose last dimension is $n"))
end

_opkey(k::typeof(CorePotts.ownership)) = k
_opkey(k) = (u = _unwrap(k); u)

# The parameter values of a problem being built (raw, before the conversion to the scalar type):
# a base parameter's operating-point value or default, and every computed parameter derived from
# them (D-F2-1; F2 design §2.7). An operating-point entry for a computed parameter is a write,
# refused naming its inputs; an operating-point value written as an expression of parameters is
# evaluated once (D-117).
function _parameter_values(c::CompiledPottsSystem, opd)
    ps = _p(getfield(c, :sys), :parameters)
    values = Dict{Any, Any}()
    for x in ps
        u, i = _unwrap(x), info(x)
        if _is_symbolic(i.default)
            haskey(opd, u) && throw(ArgumentError(_computed_message(ps, i)))
            continue
        end
        v = haskey(opd, u) ? opd[u] : i.default
        v === nothing && throw(ArgumentError("parameter `$(i.name)` has no default; give it in the operating point"))
        values[u] = v
    end
    any(_is_symbolic, values) && _resolve_defaults!(values)
    return _derive_values!(values, ps)
end
# `values` (keyed by the parameters' variables) with the computed parameters derived from the base ones
function _derive_values!(values, ps)
    isempty(_computed_params(ps)) && return values
    d = _derivation(ps)
    byname = Dict{Symbol, Any}(info(x).name => _unwrap(x) for x in ps)
    out = d(Tuple(values[byname[b]] for b in d.base))
    for (n, v) in zip(d.computed, out)
        values[byname[n]] = v
    end
    return values
end

# a scalar expression, or a kind table (vector/matrix) with an expression among its entries
_is_symbolic(v) = v isa Num || v isa SymbolicUtils.BasicSymbolic
_is_symbolic(v::AbstractArray) = any(_is_symbolic, v)

"""A value given by an expression of parameters, evaluated with the parameter `values`."""
function _evaluate(v, values, who = "`$v`")
    _is_symbolic(v) || return v
    w = _substitute_entry(v, values, who)
    _is_symbolic(w) && throw(
        ArgumentError(
            "`$v` does not reduce to a number with the parameter values" *
                _non_parameters(w)
        )
    )
    return w
end

# the parameters of `p` as a `Dict` (variable → value), for evaluating defaults of state
_parameter_dict(c::CompiledPottsSystem, p) = Dict{Any, Any}(_unwrap(x) => getproperty(p, info(x).name) for x in _p(getfield(c, :sys), :parameters))

# The computed parameters (D-F2-1, F2 design §2.7): read-only and derived from the base
# parameters through one compiled derivation (`LatticePDE.derivation`, D-117's rules), built
# once per model's parameter list. Its structural checks name the parameter: a default that
# reads a variable or built-in, or draws `rand()`.
# (keyed by the list's identity: symbolic parameters compare equal by name, so two models with
# the same names and other defaults must not share an entry; a dead list's entry is replaced)
const _DERIVATION_CACHE = Dict{UInt, Tuple{WeakRef, Any}}()
const _DERIVATION_CACHE_LOCK = ReentrantLock()
function _derivation(ps)
    return lock(_DERIVATION_CACHE_LOCK) do
        k = objectid(ps)
        e = get(_DERIVATION_CACHE, k, nothing)
        e !== nothing && e[1].value === ps && return e[2]
        d = _build_derivation(ps)
        _DERIVATION_CACHE[k] = (WeakRef(ps), d)
        return d
    end
end
function _build_derivation(ps)
    cs = _computed_params(ps)
    for x in cs
        i = info(x)
        for e in (i.default isa AbstractArray ? i.default : (i.default,))
            _is_symbolic(e) || continue
            _has_op(e, random_uniform) && throw(
                ArgumentError(
                    "parameter `$(i.name)` draws a random number " *
                        "(`rand()`); a default is evaluated once per build and must be deterministic"
                )
            )
            m = _non_parameters(e)
            isempty(m) || throw(
                ArgumentError(
                    "parameter `$(i.name)` = `$(i.default)` does not reduce to " *
                        "numbers with the parameter values" * m
                )
            )
        end
    end
    return LatticePDE.derivation(
        Symbol[info(x).name for x in ps if !_is_symbolic(info(x).default)],
        Pair{Symbol, Any}[info(x).name => info(x).default for x in cs]
    )
end
# `p` with every computed parameter derived again from its base values, in scalar type `T`
function _derive(ps, T, p::PottsParameters)
    isempty(_computed(p)) && return p
    d = _derivation(ps)
    nt = NamedTuple(p)
    out = Dict{Symbol, Any}(zip(d.computed, d(Tuple(nt[b] for b in d.base))))
    return _with_values(
        p, NamedTuple(
            info(x).name => (
                haskey(out, info(x).name) ? _param_value(T, out[info(x).name], info(x); ps) :
                    nt[info(x).name]
            ) for x in ps
        )
    )
end
# the refusal of a write of computed parameter `i` (D-F2-1): its expression, its base inputs
# (through chains) and the routes
function _computed_message(ps, i::Entity)
    byvar = Dict{Any, Entity}(_unwrap(x) => info(x) for x in ps)
    base, seen, todo = Symbol[], Set{Symbol}(), Any[i]
    while !isempty(todo)
        j = pop!(todo)
        j.name in seen && continue
        push!(seen, j.name)
        for u in _default_inputs(j.default)
            k = get(byvar, _unwrap(u), nothing)
            k === nothing && continue
            _is_symbolic(k.default) ? push!(todo, k) : (k.name in base || push!(base, k.name))
        end
    end
    sort!(base; by = string)
    ins = join(("`$b`" for b in base), ", ")
    # a component's binding (`k2 = 2k` in `comp`): the number goes into the component (review M1)
    o = get(i.options, :origin, nothing)
    route = o === nothing ? string("(the model constructor's keyword `", i.name, " = v` does)") :
        string("in the component: give `", o[2], "` a number in `", o[1], "`'s parameters, in place of its binding")
    return string(
        "`", i.name, "` is computed from ", ins, " (`", i.name, " = ", _builtin_text(_default_text(i.default)),
        "`): set ", length(base) == 1 ? ins : "its inputs", "; for a fixed `", i.name, "`, declare it with a number ", route
    )
end
_default_text(d::AbstractArray) = "[" * join((join(map(_default_text, d[r, :]), " ") for r in axes(d, 1)), "; ") * "]"
# (as written: no package prefixes, a discrete Bool read `!comp₊s`, not `!Potts._nonzero(comp₊s)`)
_default_text(d) = replace(string(d), "LatticePDE." => "", r"Potts\._nonzero\(([^()]*)\)" => s"\1")
# the computed parameter that `x` names in model `c`, or `nothing`
function _computed_entity(ps, x)
    for q in ps
        i = info(q)
        (x isa Symbol ? i.name === x : isequal(_unwrap(q), _unwrap(x))) && return _is_symbolic(i.default) ? i : nothing
    end
    return nothing
end

# `()` or `(names, fp)` for a parameter object's type (`PottsParameters{NT, D}`): the computed
# parameters (D-F2-1) and a fingerprint of their `(name, default)` pairs (C9). Only computed
# parameters are fingerprinted: a constructor keyword that overrides another default (a sweep
# `Model(; T = t)`) keeps one type, so nothing recompiles.
_computed_params(ps) = [x for x in ps if _is_symbolic(info(x).default)]
# the fingerprint's text of a default: numbers as Float64 (`0` and `0.0` are one derivation: the
# Pairs and matrix forms of a kind table give one type), arrays element by element with their size
_canon_default(d::AbstractArray) = string(size(d)) * "[" * join(map(_canon_default, d), ", ") * "]"
function _canon_default(d)
    u = _const_value(d)
    return u isa Real ? repr(Float64(u)) : string(u)
end
_const_value(d) = (u = _unwrap(d); u isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(u) ? SymbolicUtils.unwrap_const(u) : u)
function _computed_tag(ps)
    cs = _computed_params(ps)
    # MTK metadata (F2-14): `tunable = false` names and declared bounds, in the type only when present
    nt = Tuple(info(x).name for x in ps if get(info(x).options, :tunable, true) === false)
    bs = Tuple((info(x).name, info(x).options.bounds...) for x in ps if haskey(info(x).options, :bounds))
    tag = isempty(cs) ? ((), UInt64(0)) :
        (Tuple(info(x).name for x in cs), hash([(info(x).name, _canon_default(info(x).default)) for x in cs]))
    isempty(nt) && isempty(bs) && return isempty(cs) ? () : tag
    return (tag..., (nt, bs))
end

# the raw computed defaults, compared exactly (`isequal`, arrays element by element with their
# size): `0` and `0.0` agree, `1//3` and `0.333…`, `big"0.1"` and `0.1`, or `A.f(λ)` and
# `B.f(λ)` do not, although the fingerprint's text cannot tell them apart
_raw_defaults(ps) = [(info(x).name, info(x).default) for x in _computed_params(ps)]
_same_default(a::AbstractArray, b::AbstractArray) = size(a) == size(b) && all(_same_default(x, y) for (x, y) in zip(a, b))
_same_default(a::AbstractArray, b) = false
_same_default(a, b::AbstractArray) = false
_same_default(a, b) = isequal(_const_value(a), _const_value(b))
_same_defaults(a, b) = length(a) == length(b) && all(x[1] === y[1] && _same_default(x[2], y[2]) for (x, y) in zip(a, b))

# register the derivation of `p`'s computed parameters (D-F2-1) for `SciMLStructures.replace`:
# one per exact type; a second model with the same type but other computed defaults (a
# fingerprint collision) is an error, never a silent replacement
function _register_derivation!(ps, T, p::PottsParameters)
    isempty(_computed(p)) && return nothing
    defaults = _raw_defaults(ps)
    lock(_DERIVATIONS_LOCK) do
        old = get(_DERIVATIONS, typeof(p), nothing)
        if old === nothing
            _DERIVATIONS[typeof(p)] = (; derive = (o, n) -> _derive(ps, T, n), defaults)
        elseif !_same_defaults(old.defaults, defaults)
            throw(
                ArgumentError(
                    "two models share a parameter type but derive $(_computed(p)) from other defaults " *
                        "(a fingerprint collision: equal as text, e.g. `1//3` and `0.333…`, or two functions " *
                        "named alike); rename a parameter of one of them"
                )
            )
        end
    end
    return nothing
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
        isfatal(e) && rethrow()
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
        throw(
        ArgumentError(
            "$who draws a random number (`rand()`); a default is evaluated once per build " *
                "and must be deterministic"
        )
    )
    if op === ifelse
        c = _numeric(args[1], who)
        c === _PENDING && return c
        return _numeric(c ? args[2] : args[3], who)
    end
    vals = map(a -> _numeric(a, who), args)
    any(a -> a === _PENDING, vals) && return _PENDING
    op === value_at && return _table_entry(who, vals...)
    try
        return op(vals...)
    catch e
        isfatal(e) && rethrow()
        throw(ArgumentError("$who: `$x` fails on the parameter values: $(sprint(showerror, e))"))
    end
end

# `t[k…]` of a kind table `t` by kind numbers (medium = 0, then the `@kinds` order)
function _table_entry(who, t, ks...)
    t isa AbstractArray && ndims(t) == length(ks) ||
        throw(
        ArgumentError(
            "$who reads a kind table with $(length(ks)) kind$(length(ks) == 1 ? "" : "s"); " *
                "the table takes $(t isa AbstractArray ? ndims(t) : 0)"
        )
    )
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

_param_value(T, v, i::Entity; ps = nothing) = _check_bounds(i, _param_value_unchecked(T, v, i), ps)
function _param_value_unchecked(T, v, i::Entity)
    _is_symbolic(v) && throw(
        ArgumentError(
            "parameter `$(i.name)` = `$(_is_symbolic(i.default) ? i.default : v)` does not " *
                "reduce to numbers with the parameter values" * _non_parameters(v)
        )
    )
    if i.role === :kindtable
        v isa Number && throw(ArgumentError("kind table `$(i.name)` takes a vector (one value per kind) or a matrix; got $v"))
        A = Matrix(v isa AbstractVector ? reshape(v, :, 1) : v)
        v isa AbstractVector && return SVector{length(v), T}(_cpm_scalar.(T, v, Ref(i)))
        return SMatrix{size(A, 1), size(A, 2), T}(_cpm_scalar.(T, A, Ref(i)))
    end
    return _cpm_scalar(T, v, i)
end

# A CPM parameter converted to the problem's scalar type `T`, with a named error for a value
# that does not convert (a Dual, P5 C3/4-1): the CPM takes plain numbers. Metropolis
# acceptance is piecewise constant in `p`, so a derivative of a CPM run in `p` is zero
# almost everywhere; CPM parameters belong to likelihood-free inference on the counter RNG
_cpm_scalar(::Type{T}, v, i::Entity) where {T} = _plain_number(v) ? T(v) :
    try
        T(v)
catch e
        e isa Union{MethodError, InexactError, ArgumentError} || rethrow()
        throw(
            ArgumentError(
                "parameter `$(i.name)` = $(_valtext(v)) does not convert to the problem's scalar type $T: " *
                "a parameter object holds plain numbers (no Duals). A Dual goes to the problem: " *
                "`PottsProblem(sys, op, tspan)` or `remake(prob; p = [k => Dual])`, whose fields then carry derivative " *
                "parts along the run's CPM path (F3-21b); an integrator write takes a plain number. A parameter the " *
                "CPM reads has a derivative that is zero almost everywhere (the acceptance of a copy is piecewise " *
                "constant in it), so it belongs to likelihood-free inference"
            )
        )
end

# a value in a message: a ForwardDiff Dual by its value and value type, not its type (whose tag
# can embed the whole problem's type: several KB; batch 5 review S4)
function _valtext(v)
    T = typeof(v)
    V = LatticeFields.Compile.value_type(T)
    T <: Real && V !== T && return string("a ForwardDiff `Dual` of ", V, " (value ", LatticeFields.Compile.primal(v), ")")
    return string(v, " (a ", T, ")")
end

function _initial_state(c::CompiledPottsSystem, opd, T, capacity, pvals = Dict{Any, Any}(), init = _init_options(nothing))
    sys = getfield(c, :sys)
    haskey(opd, ownership) || throw(ArgumentError("the operating point needs `ownership => labels`"))
    σ = Int32.(opd[ownership])
    size(σ) == _p(sys, :lattice).dims || throw(ArgumentError("labels have size $(size(σ)); the lattice is $(_p(sys, :lattice).dims)"))
    all(>=(0), σ) || throw(ArgumentError("labels must be ≥ 0 (0 is medium); got $(minimum(σ))"))
    ncell = maximum(σ; init = Int32(0))
    kkey = _unwrap(B.kind)
    kinds = haskey(opd, kkey) ? opd[kkey] : fill(1, ncell)
    kinds = Int32[k isa Symbol ? _kind_index(sys, k) : _kind_number(k) for k in (kinds isa AbstractVector ? kinds : fill(kinds, ncell))]
    length(kinds) == ncell || throw(ArgumentError("$(length(kinds)) kinds for $ncell labeled cells"))
    nk = length(_p(sys, :kinds)) - 1
    for k in kinds
        1 <= k <= nk || throw(
            ArgumentError(
                "kind number $k is out of range: cell kinds are 1:$nk " *
                    "($(join(_p(sys, :kinds)[2:end], ", ")))"
            )
        )
    end
    lat = core_lattice(_p(sys, :lattice))
    site = Pair{Symbol, Any}[]
    shapes = Pair{Symbol, Any}[]          # the site arrays on a coarse grid (F3-17): their shapes
    cell = Pair{Symbol, Any}[]
    model = Pair{Symbol, Any}[]
    for x in _p(sys, :variables)
        i = info(x)
        # a kind-conditional default (E1) is evaluated per cell from its kind, below
        v = i.role === :cell && !haskey(opd, _unwrap(x)) && _kind_default(i.default) ?
            [_evaluate(_substitute_kind(i.default, k), pvals, "the default of `$(i.name)` for kind $k") for k in kinds] :
            _evaluate(get(opd, _unwrap(x), i.default), pvals, "the default of `$(i.name)`")
        if i.role === :site || i.role === :field
            S = get(i.options, :lattice_storage, T)                  # a field's own storage (Float16)
            _check_field_bounds(i, v)
            # (a `Coarse(k)` field's array is its grid's, F3-17)
            sd = _site_dims(i, _p(sys, :lattice).dims)
            v isa AbstractArray && sd != _p(sys, :lattice).dims && size(v) != sd &&
                throw(
                ArgumentError(
                    string(
                        "the operating point gives `", i.name, "` an array of size ", size(v), "; `", i.name,
                        "` has `lattice_level = ", i.options.lattice_level, "`, so its array is its grid's, of size ", sd
                    )
                )
            )
            a = v isa AbstractArray ? S.(v) : fill(S(v), sd)
            push!(site, i.name => a)
            i.name in getfield(c, :scratch) && push!(site, Symbol(i.name, :__next) => copy(a))
            sd == _p(sys, :lattice).dims || append!(shapes, [i.name => sd, Symbol(i.name, :__next) => sd, Symbol(i.name, :__mask) => sd])
        elseif i.role === :cell
            v === nothing && throw(ArgumentError("cell variable `$(i.name)` has no initial value; give it in the operating point"))
            if get(i.options, :reference, false) === true
                push!(cell, i.name => _ref_column(i.name, v, ncell))
            else
                push!(cell, i.name => (v isa AbstractArray ? T.(v) : fill(T(v), ncell)))
            end
        elseif i.role === :edge
            continue                                   # link payloads, below
        elseif i.role === :model
            v === nothing && throw(ArgumentError("model variable `$(i.name)` has no initial value; give it in the operating point"))
            push!(model, i.name => fill(T(v), 1))
        end
    end
    # the fields' CPM inputs and masks (written every MCS by the field phases, fields.jl)
    if _has_fields(c)
        dims = _p(sys, :lattice).dims
        for (name, _, E) in _field_inputs(c, T)
            push!(site, name => zeros(E === Bool ? UInt8 : E, dims))
        end
        foreach(n -> push!(site, Symbol(n, :__mask) => zeros(UInt8, _site_dims(_field_info(sys, n), dims))), _masked_fields(sys))
    end
    # `@initialization_equations` and operating-point values of algebraic variables (D-170)
    _initialize!(c, opd, σ, kinds, ncell, cell, model, pvals, init)
    for x in _integrals(sys)
        push!(cell, _integral_name(x) => zeros(T, ncell))
    end
    if getfield(c, :uses_surface)
        push!(cell, :surface => CorePotts.recompute_surface(σ, lat, CorePotts.relation(getfield(c, :relations)[:surface], lat), ncell; T))
    end
    # Euler characteristics (P6.3j, D-192): Int32 columns, one per adjacency the model reads
    getfield(c, :uses_euler) && push!(cell, :euler => CorePotts.recompute_euler(σ, lat, Val(:face), ncell))
    getfield(c, :uses_euler_full) && push!(cell, :euler_full => CorePotts.recompute_euler(σ, lat, Val(:full), ncell))
    # cell-scope pieces (P6.9a): Int32 columns, a (pieces, largest piece) pair per adjacency read
    for (full, P, L) in ((false, :pieces, :largest_piece), (true, :pieces_full, :largest_piece_full))
        (full ? getfield(c, :uses_pieces_full) : getfield(c, :uses_pieces)) || continue
        pc, lc = CorePotts.recompute_pieces(σ, lat, Val(full), ncell)
        push!(cell, P => pc, L => lc)
    end
    append!(cell, _contact_count_columns(c, σ, kinds, lat, ncell))          # contact folds (D-150)
    _has_bounded_draw(sys) && push!(model, CorePotts.MODEL_STATUS => zeros(UInt32, 1))
    getfield(c, :needs_moments) && append!(cell, pairs(CorePotts.init_moments(σ, lat, ncell)))
    ckey = _unwrap(B.cluster)
    if getfield(c, :uses_clusters)
        ids = haskey(opd, ckey) ? opd[ckey] : 1:ncell
        length(ids) == ncell || throw(ArgumentError("$(length(ids)) cluster ids for $ncell labeled cells"))
        rel = getfield(c, :uses_cluster_surface) ? getfield(c, :relations)[:surface] : nothing
        append!(
            cell, pairs(
                CorePotts.init_clusters(
                    σ, ids, lat; relation = rel, T, kind = kinds,
                    prefer = _cluster_kinds(c)
                )
            )
        )
    elseif haskey(opd, ckey)
        throw(ArgumentError("`cluster` in the operating point, but the model uses no compartments"))
    end
    for r in getfield(c, :relationships)                       # one link store per relationship (P6.0b)
        vars = getfield(c, :edge_vars)[r.name]
        links = CorePotts.empty_links(r.capacity, ncell, r.name; (info(x).name => T for x in vars)...)
        store = (; links = links[CorePotts.adjacency_name(r.name)], Base.tail(links)...)
        defaults = (; (info(x).name => T(_edge_initial(x, opd, pvals, r.name)) for x in vars)...)
        for (x, y) in get(opd, r.name, ())
            CorePotts.add_link!(store, x, y; defaults...) ||
                throw(
                ArgumentError(
                    "$(r.name): cannot link cells $x and $y (out-of-range id, full row of capacity $(r.capacity), " *
                        "self-link or duplicate); increase `capacity` in `@relationship $(r.name)(cell, cell) capacity = …` " *
                        "or pass distinct ids in 1:$ncell"
                )
            )
        end
        append!(cell, pairs(links))
    end
    # previous-value snapshots and population slots (D-041, D-042)
    for (scope, n) in unique(Iterators.flatten(values(getfield(c, :pre_snapshots))))
        dst = scope === :site ? site : scope === :cell ? cell : model
        push!(dst, Symbol(n, :__pre) => copy(last(dst[findfirst(q -> q.first === n, dst)])))
    end
    # scratch slots of discrete components ticking in several phases (P6.0k)
    if _tick_scratch(c)
        for b in getfield(c, :discrete), x in b.slots
            dst = b.scope === :cell ? cell : model
            n = info(x).name
            push!(dst, _tick_scratch_name(n) => copy(last(dst[findfirst(q -> q.first === n, dst)])))
        end
    end
    for (n, _) in Iterators.flatten((getfield(c, :update_pops), getfield(c, :energy_snapshots), getfield(c, :cell_ode_pops), getfield(c, :discrete_pops)))
        push!(model, n => zeros(T, 1))
    end
    # cell serials (R6, D-066 item 3): a model that divides numbers its cells 1, 2, … and
    # its daughters from the counter on; without divisions a cell's serial is its slot. A
    # dividing model that never reads `birth` has no column, so no serial pass (P6.5a3)
    if _tracks_births(c)
        push!(cell, :birth => Int32.(1:ncell))
        push!(model, CorePotts.NEXT_BIRTH => Int32[ncell + 1])
    end
    sitent, modelnt = NamedTuple(site), NamedTuple(model)
    history = (;
        (
            n => CorePotts.history_buffer(haskey(sitent, n) ? sitent[n] : modelnt[n], d)
                for (n, d) in sort!(collect(_history_depths(sys)); by = first)
        )...,
    )
    st = CorePotts.initial_state(
        σ, kinds; cell = NamedTuple(cell), site = sitent, model = modelnt, history,
        shapes = NamedTuple(shapes)
    )
    cap = capacity === nothing ? (_numbers_cells(c) ? 2ncell + 64 : ncell) : capacity
    st = cap > ncell ? CorePotts.with_capacity(st, cap) : st
    return _reduce_layout(_convert_layout(st, c), c)
end

# Cell serials and spare slots: a model that divides or allocates by `@convert`
_numbers_cells(c::CompiledPottsSystem) = !isempty(getfield(c, :divisions)) || !isempty(_p(getfield(c, :sys), :converts))
# Cell serials kept (P6.5a3): a model that allocates cells and reads `birth` (`uses_birth`:
# `birth`, `sibling`, `@convert`). Decided when the model is compiled; the state's `birth`
# column and `NEXT_BIRTH` counter carry it to both lifecycle planners (`births = nothing`
# without them, the serial pass skipped).
_tracks_births(c::CompiledPottsSystem) = _numbers_cells(c) && getfield(c, :uses_birth)

# a cell-variable default that reads the built-in `kind` (E1)
function _kind_default(v)
    _is_symbolic(v) || return false
    k = _unwrap(B.kind)
    return any(u -> isequal(_unwrap(u), k), Symbolics.get_variables(v))
end
_substitute_kind(v, k) = Symbolics.substitute(v, Dict(_unwrap(B.kind) => k))

# The scratch of `@convert` passes (`CorePotts.convert_scratch`), made where the state lives;
# a model without `@convert`, or a state that has all of it, is returned as is. A state saved
# by an earlier version (with the pass flags but without the compound writes' sum columns, or
# with fewer rows than the model's writes) gets the missing cell columns (F3-23 r2): they are
# scratch, zero between passes, so nothing of the run is lost; the flags' counts are kept.
function _convert_layout(st::CorePotts.CPMState, c::CompiledPottsSystem)
    isempty(_p(getfield(c, :sys), :converts)) && return st
    J = maximum(v -> length(v.writes), _p(getfield(c, :sys), :converts))
    sc = CorePotts.convert_scratch(size(st.ownership), length(st.cell.kind), ndims(st.ownership); writes = J)
    # every scratch array is constant (zeros, or `typemax` for the minima): filled where the
    # state lives, so a device state gets device scratch with no host transfer
    dev(a) = isempty(a) ? similar(st.ownership, eltype(a), size(a)) : fill!(similar(st.ownership, eltype(a), size(a)), first(a))
    if haskey(st.model, CorePotts.CONVERT_FLAGS)
        fits(n, a) = haskey(st.cell, n) && size(getfield(st.cell, n))[1:(end - 1)] == size(a)[1:(end - 1)]
        add = [(n, a) for (n, a) in sc.cell if !fits(n, a)]
        isempty(add) && return st
        return CorePotts.CPMState(
            st.ownership, merge(st.cell, NamedTuple(n => dev(a) for (n, a) in add)), st.site, st.model,
            st.history
        )
    end
    return CorePotts.CPMState(
        st.ownership, merge(st.cell, NamedTuple(n => dev(a) for (n, a) in sc.cell)),
        merge(st.site, NamedTuple(n => dev(a) for (n, a) in sc.site)),
        merge(st.model, NamedTuple(n => dev(a) for (n, a) in sc.model)), st.history
    )
end

# The scratch of the cell sums of stored integrals (`CorePotts.reduce_scratch`, F3-23: exact
# Int64 fixed-point sums), made where the state lives; a state that has it, or a model without
# a stored integral, is returned as is
function _reduce_layout(st::CorePotts.CPMState, c::CompiledPottsSystem)
    (isempty(_integrals(getfield(c, :sys))) || haskey(st.model, CorePotts.REDUCE_STATUS)) && return st
    sc = CorePotts.reduce_scratch(length(st.cell.kind))
    dev(a) = fill!(similar(st.ownership, eltype(a), size(a)), zero(eltype(a)))     # zeros, where the state lives
    return CorePotts.CPMState(
        st.ownership, merge(st.cell, map(dev, sc.cell)), st.site, merge(st.model, map(dev, sc.model)),
        st.history
    )
end

# A `CellRef` column (R6): Int32 cell ids, 0 (none) or a labelled cell
# A field's initial values against its declared `bounds = (lo, hi)` (F3-13): the stability bound
# takes that interval for the coefficients that read the field, so a field that starts outside
# it is refused, naming the first site
function _check_field_bounds(i, v)
    b = get(i.options, :bounds, nothing)
    b === nothing && return nothing
    vals = v isa AbstractArray ? v : (v,)
    k = findfirst(x -> !(b[1] <= x <= b[2]), vals)
    k === nothing && return nothing
    at = v isa AbstractArray ? string(" at site ", Tuple(CartesianIndices(v)[k])) : ""
    throw(
        ArgumentError(
            string(
                "field `", i.name, "` starts at ", vals[k], at, ", outside its declared bounds (",
                _bnum(b[1]), ", ", _bnum(b[2]), "): the stability bound takes that interval for the coefficients that read `",
                i.name, "`; give it initial values in its bounds, or change `bounds` in its declaration"
            )
        )
    )
end
function _ref_column(name, v, ncell)
    vals = v isa AbstractArray ? vec(v) : fill(v, ncell)
    length(vals) == ncell || throw(ArgumentError("$(length(vals)) values of reference `$name` for $ncell labeled cells"))
    for r in vals
        (r isa Integer || (r isa Real && isinteger(r))) && 0 <= r <= ncell ||
            throw(ArgumentError("reference `$name` = $r: a reference is 0 (none) or a cell id in 1:$ncell"))
    end
    return Int32.(vals)
end

# The initial value of edge variable `x` on the initial links of relationship `r`: its
# operating-point value (one number for every initial link, both ends; D-127) or its
# default. Per-link values are not guessed from arrays.
function _edge_initial(x, opd, pvals, r)
    i = info(x)
    haskey(opd, _unwrap(x)) || return i.default
    v = _evaluate(opd[_unwrap(x)], pvals, "the operating-point value of `$(i.name)`")
    v isa Real || throw(
        ArgumentError(
            "edge variable `$(i.name)`: the operating point takes one number, " *
                "the initial value on every initial link of `$r`; got $(repr(v; context = :limit => true))"
        )
    )
    return v
end

# The at-init phases (integrals, energy snapshots) on a host state, so a problem's `u0` is
# consistent before `init` (e.g. `total_energy(prob)`).
function _host_init!(@nospecialize(f), @nospecialize(st), @nospecialize(p), @nospecialize(ctx), seed, replica, repeat, kw)
    key = CorePotts.RNGKey(seed, replica, repeat)
    # (only `LatticeNewton` groups read them; `init` refuses them for the others)
    atol, rtol = LatticeFields.Problems.resolve_tols(get(kw, :abstol, nothing), get(kw, :reltol, nothing))
    ctx = merge(ctx, CorePotts.phase_contexts(f.phases, st, p, CorePotts.CPU(); abstol = atol, reltol = rtol))
    CorePotts._run_phases(f.phases.at_init, st, p, ctx, key, 0, CorePotts.CPU())
    return st
end

# Kinds that name clusters (`clusters(k)` terms and divisions): a cluster's root is chosen
# among its members of these kinds, so the filters select it.
_cluster_kinds(c::CompiledPottsSystem) = Tuple(
    unique(
        Iterators.flatten(
            (
                first.(getfield(c, :cluster_terms))...,
                (d.domain.kinds for d in getfield(c, :divisions) if d.domain isa ClusterDomain)...,
            )
        )
    )
)

# Sites of cells of frozen kinds never change owner (walls, obstacles).
function _frozen_mask(sys::PottsSystem, st)
    isempty(_p(sys, :frozen_kinds)) && return nothing
    kinds = st.cell.kind
    return map(s -> s != 0 && Int(kinds[s]) in _p(sys, :frozen_kinds), st.ownership)
end

_kind_number(k) = Int(k)
_kind_number(g::KindClass) = throw(ArgumentError("`$(g.name)` is a kind class, not a kind: a cell has one kind"))
function _kind_index(sys::PottsSystem, k::Symbol)
    j = findfirst(==(k), _p(sys, :kinds))
    j === nothing && any(g -> g.name === k, _p(sys, :kind_classes)) &&
        throw(ArgumentError("`$k` is a kind class, not a kind: a cell has one kind; kinds are $(_p(sys, :kinds))"))
    j === nothing && throw(ArgumentError("unknown kind `$k`; kinds are $(_p(sys, :kinds))"))
    j == 1 && throw(ArgumentError("cells cannot have the medium kind `$k`"))
    return j - 1
end

# with the flood scratch of a model with whole-cell connectivity (P6.9a), exact (`GlobalExact`)
_host_ctx(prob) = (;
    lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...,
    CorePotts.connectivity_ctx(CorePotts.CPU(), prob.f, prob.lattice, CorePotts.GlobalExact())...,
)

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
    info isa PottsModelInfo || throw(
        ArgumentError(
            "total_energy: `prob` was not built from a symbolic Potts model (`PottsSystem`), so it has no generated energy"
        )
    )
    return info.total_energy(u, prob.p, _host_ctx(prob))
end

# `remake(prob; p = [λ => 2.0])` and `remake(prob; u0 = [ownership => σ, kind => kinds])`:
# symbolic maps are translated with the problem's scalar type, so the parameter object keeps
# its type and nothing recompiles.
const _SymbolicMap = Union{AbstractVector{<:Pair}, AbstractDict}

# (a Dual value: its primal value here, the Dual in the problem's tangent: `remake_tangent`, F3-21b)
CorePotts.remake_parameters(@nospecialize(info::PottsModelInfo), @nospecialize(prob), p::_SymbolicMap) =
    _set_parameter_map(
    info, prob.p, Pair{Any, Any}[
        k => (
            _is_dual(v) ? _tprimal(v) : _has_dual(v) ?
                _refuse_dual_value(string(k), :kindtable, v) : v
        ) for (k, v) in p
    ]
)

# parameter object `old` with the parameter map `p` applied as one change, then every computed
# parameter derived again (D-F2-1)
Base.@nospecializeinfer function _set_parameter_map(@nospecialize(info::PottsModelInfo), @nospecialize(old::PottsParameters), p)
    p = _expand_vectors(getfield(info.csys, :sys), Pair{Any, Any}[_localize(getfield(info.csys, :sys), k; strict = true) => v for (k, v) in p])
    names = Dict{Any, Entity}()
    for x in _p(getfield(info.csys, :sys), :parameters)
        i = Potts.info(x)
        names[_unwrap(x)] = i
        names[i.name] = i
    end
    new = Dict{Symbol, Any}()
    for (k, v) in p
        key = k isa Symbol ? k : _unwrap(k)
        haskey(names, key) || throw(ArgumentError("`$k` is not a parameter of $(nameof(info.csys))"))
        i = names[key]
        # a computed parameter is read-only (D-F2-1): the whole change is refused, nothing is set
        _is_symbolic(i.default) && throw(ArgumentError(_computed_message(_p(getfield(info.csys, :sys), :parameters), i)))
        new[i.name] = _param_value(info.T, v, i)
    end
    out = _with_values(old, NamedTuple(k => get(new, k, v) for (k, v) in pairs(NamedTuple(old))))
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
CorePotts.remake_parameters(@nospecialize(info::PottsModelInfo), @nospecialize(prob), p::NamedTuple) =
    CorePotts.remake_parameters(info, prob, _field_pairs(p))

# a whole parameter object gives its base values, and the computed parameters are derived again
# from them (D-F2-1 amends D-115: a checkpoint's object restores bitwise, as the derivation is
# deterministic; a hand-edited object gets consistent computed values, never a silent mix); the
# kind tables are checked either way. One of this problem's type is used as is; one of another
# type must have the same names and sets every base value, converted to the problem's scalar type
# (a Float32 problem's `p` does not make a Float64 problem Float32)
Base.@nospecializeinfer function CorePotts.remake_parameters(
        @nospecialize(info::PottsModelInfo), @nospecialize(prob),
        @nospecialize(p::PottsParameters)
    )
    typeof(p) === typeof(prob.p) && return _finish_parameters(info, p, p, nothing)
    new, old = keys(NamedTuple(p)), keys(NamedTuple(prob.p))
    if Set(new) != Set(old)
        extra, absent = setdiff(new, old), setdiff(old, new)
        throw(
            ArgumentError(
                "the parameter object is not one of $(nameof(info.csys))" *
                    (isempty(extra) ? "" : "; not its parameters: $(join(extra, ", "))") *
                    (isempty(absent) ? "" : "; missing: $(join(absent, ", "))")
            )
        )
    end
    ps = _p(getfield(info.csys, :sys), :parameters)
    base = Pair{Symbol, Any}[k => v for (k, v) in pairs(NamedTuple(p)) if _computed_entity(ps, k) === nothing]
    return CorePotts.remake_parameters(info, prob, base)
end

# SciML's keep sentinels: `p = missing` (SciMLBase's generic `remake`) or `nothing` keeps `prob.p`
CorePotts.remake_parameters(@nospecialize(::PottsModelInfo), @nospecialize(prob), ::Union{Nothing, Missing}) = prob.p

# a vector or tuple of `Pair`s (of any eltype) is a map; anything else is an error, never a
# silent replacement of `prob.p` (D-115)
function CorePotts.remake_parameters(@nospecialize(info::PottsModelInfo), @nospecialize(prob), p)
    _is_pairs(p) && return CorePotts.remake_parameters(info, prob, Pair[x for x in p])
    throw(
        ArgumentError(
            "`p = $(repr(p; context = :limit => true))` is not a parameter map of $(nameof(info.csys)); " *
                "give a NamedTuple, a vector of `name => value` pairs or a Dict"
        )
    )
end

_field_pairs(nt::NamedTuple) = Pair{Symbol, Any}[k => v for (k, v) in pairs(nt)]
_is_pairs(p) = (p isa AbstractVector || p isa Tuple) && all(x -> x isa Pair, p)

# Derive every computed parameter again from the base values (D-F2-1), and check the tables.
Base.@nospecializeinfer function _finish_parameters(@nospecialize(mi::PottsModelInfo), @nospecialize(old), @nospecialize(out), _)
    c = mi.csys
    out = _derive(_p(getfield(c, :sys), :parameters), mi.T, out)
    typeof(out) === typeof(old) || throw(
        ArgumentError(
            "parameter types changed (kind tables keep their size and scalars keep type $(mi.T)); pass values compatible with $(nameof(typeof(old)))"
        )
    )
    return _check_parameter_tables(c, out)
end

# the kind tables of a parameter object: their checks, and contact tables symmetric
function _check_parameter_tables(c::CompiledPottsSystem, @nospecialize(out))
    _check_kind_tables(getfield(c, :sys), out)
    for name in _contact_tables(c)
        J = getproperty(out, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    return out
end

# `setp`/`integ.ps[x] = v` on an integrator: the same conversion, derivation and checks (A-53)
function CorePotts.set_parameter(info::PottsModelInfo, p::PottsParameters, v, i::Symbol)
    x = findfirst(x -> Potts.info(x).name === i, _p(getfield(info.csys, :sys), :parameters))
    x === nothing && throw(ArgumentError("`$i` is not a parameter of $(nameof(info.csys))"))
    e = Potts.info(_p(getfield(info.csys, :sys), :parameters)[x])
    _is_symbolic(e.default) && throw(ArgumentError(_computed_message(_p(getfield(info.csys, :sys), :parameters), e)))
    q = _with_values(p, merge(NamedTuple(p), NamedTuple{(i,)}((_param_value(info.T, v, Potts.info(_p(getfield(info.csys, :sys), :parameters)[x])),))))
    return _finish_parameters(info, p, q, Set([i]))
end

SymbolicIndexingInterface.setp(sys::PottsModelInfo, ps::Union{Tuple, AbstractVector}; run_hook = true) =
    CorePotts.parameter_setter(sys, ps, run_hook)
SymbolicIndexingInterface.setp(sys::PottsModelInfo, p; run_hook = true) = CorePotts.name_setter(sys, p, run_hook)
SymbolicIndexingInterface.setsym(sys::PottsModelInfo, syms::Union{Tuple, AbstractVector}) =
    CorePotts.symbol_setter(sys, syms)

# `setp(integ, [x, y])`: every value set first, then one derivation for the whole change
function CorePotts.set_parameters(info::PottsModelInfo, p::PottsParameters, vals, names)
    params = _p(getfield(info.csys, :sys), :parameters)
    new = Dict{Symbol, Any}()
    for (v, i) in zip(vals, names)
        x = findfirst(x -> Potts.info(x).name === i, params)
        x === nothing && throw(ArgumentError("`$i` is not a parameter of $(nameof(info.csys))"))
        e = Potts.info(params[x])
        _is_symbolic(e.default) && throw(ArgumentError(_computed_message(params, e)))
        new[i] = _param_value(info.T, v, e)
    end
    q = _with_values(p, NamedTuple(k => get(new, k, v) for (k, v) in pairs(NamedTuple(p))))
    return _finish_parameters(info, p, q, Set(keys(new)))
end

# `[frozen]` kinds: the mask follows the kinds, by CorePotts' standard rule (built on the
# device after lifecycle events, D-081; `frozen_varies` follows from it)
CorePotts.frozen_kinds(info::PottsModelInfo) =
    isempty(_p(getfield(info.csys, :sys), :frozen_kinds)) ? nothing : Tuple(Int32.(_p(getfield(info.csys, :sys), :frozen_kinds)))

# a state given as such (`remake(prob; u0 = st)`, `reinit!(integ, st)`, a saved state of another
# problem of the model): its values, laid out for this problem's ODE scratch
CorePotts.remake_state(info::PottsModelInfo, prob, u0::CorePotts.CPMState, kw = prob.kwargs) =
    _track_layout(
    _ode_layout(
        _reduce_layout(_convert_layout(_check_births(u0, info.csys), info.csys), info.csys), info.csys,
        info.solvers
    ), info.csys, _track_names(prob)
)

# `@convert` (D-233): the allocations deferred for want of a free slot and the entities
# skipped for the Int32 moment scratch, read once per solve (as the lifecycle's deferrals)
function _report_converts(info::PottsModelInfo, integ)
    dev = getfield(integ.state.model, CorePotts.CONVERT_FLAGS)
    flags = CorePotts._to_host(getfield(integ, :stats), dev)
    deferred, large = Int(flags[3]), Int(flags[4])
    deferred > 0 && @warn "@convert in $(nameof(info.csys)): $deferred allocation(s) deferred: all " *
        "$(length(integ.state.cell.kind)) cell slots are in use (the lowest-slot entities " *
        "allocate first; the others convert nothing that MCS). Pass a larger `capacity`."
    large > 0 && @warn "@convert in $(nameof(info.csys)): $large entity pass(es) skipped: the cells' second " *
        "moments exceed the pass's Int32 scratch (a cell far larger than any in use)"
    (deferred > 0 || large > 0) && fill!(dev, 0)        # flags 1–2 are per pass; 3–4 counted again
    return nothing
end

# A given state has this model's serial layout (D-066 item 3, P6.5a3): the `birth` column and
# the `NEXT_BIRTH` counter exactly when the model reads `birth`. Any other layout is a state of
# another model, an `ArgumentError`.
function _check_births(st::CorePotts.CPMState, c::CompiledPottsSystem)
    want = _tracks_births(c)
    col, ctr = haskey(st.cell, :birth), haskey(st.model, CorePotts.NEXT_BIRTH)
    col == ctr == want && return st
    throw(
        ArgumentError(
            "the given state does not fit model `$(nameof(c))`: " *
                (
                want ? "the model reads `birth`, so a state needs the `birth` cell column and its counter" :
                    "the model keeps no cell serials, so a state has no `birth` cell column or counter"
            ) *
                " (the state has $(col ? "a" : "no") `birth` column and $(ctr ? "a" : "no") counter)"
        )
    )
end

# a NamedTuple operating point is the map of its fields (D-115)
CorePotts.remake_state(info::PottsModelInfo, prob, u0::NamedTuple, kw = prob.kwargs) =
    CorePotts.remake_state(info, prob, _field_pairs(u0), kw)

# `u0 = nothing`/`missing` keeps the problem's state (laid out for this model's functions)
CorePotts.remake_state(info::PottsModelInfo, prob, ::Union{Nothing, Missing}, kw = prob.kwargs) =
    CorePotts.remake_state(info, prob, prob.u0, kw)

function CorePotts.remake_state(info::PottsModelInfo, prob, u0, kw = prob.kwargs)
    _is_pairs(u0) && return CorePotts.remake_state(info, prob, Pair[x for x in u0], kw)
    throw(
        ArgumentError(
            "`u0 = $(repr(u0; context = :limit => true))` is not a state or an operating point of $(nameof(info.csys)); " *
                "give a state, a NamedTuple, a vector of `variable => value` pairs or a Dict"
        )
    )
end

# an `initializealg` given to `remake` is one the model can apply
CorePotts.check_initializealg(::PottsModelInfo, a) = (_init_options(a); nothing)

# `kw`: the remade problem's keywords (its `initializealg`)
function CorePotts.remake_state(info::PottsModelInfo, prob, u0::_SymbolicMap, kw = prob.kwargs)
    any(x -> _has_dual(last(x)), u0) && throw(
        ArgumentError(
            "`remake(prob; u0 = …)` takes plain values: give initial " *
                "values with derivative parts to the problem (`PottsProblem(sys, op, tspan)`, F3-21b)"
        )
    )
    opd = _operating_point(getfield(info.csys, :sys), u0)
    # keep the old capacity and the old number of free slots (room for divisions)
    old = length(prob.u0.cell.kind)
    free = count(iszero, prob.u0.cell.volume)
    ncell = maximum(Int32.(get(opd, ownership, Int32[])); init = Int32(0))
    values = _parameter_dict(info.csys, prob.p)
    init = _init_options(get(kw, :initializealg, nothing))
    st = _ode_layout(_initial_state(info.csys, opd, info.T, max(old, ncell + free), values, init), info.csys, info.solvers)
    return _host_init!(prob.f, st, prob.p, info.ctx, prob.seed, prob.replica, prob.repeat, prob.kwargs)
end
