# Continuous fields on the lattice (v3 §7, cutover C8). A field is a site array of floats in
# `st.site`; its equations are lowered by the field compiler (LatticePDE → LatticeFields) into
# a step plan, and `FieldPhase` runs that plan inside the MCS: the CPM keeps reading the field
# from `st.site` as before. The arrays of the plan (the field and its scratch, the inputs the
# CPM fills, the masks) are site arrays of the state; the bound launches of one trajectory live
# in its run context (`ctx`), built when an integrator is created (`phase_context`).

"""Kind of the cell owning site `i` (`0` for the medium)."""
@inline owner_kind(st, i) = (c = @inbounds st.ownership[i]; c == 0 ? Int32(0) : @inbounds st.cell.kind[c])

"""
    FieldPhase{K}(group, alg, arrays; tables, params, substeps, dt, period = dt, options, T, init = false, aux_only = false,
                  start = false)

A group of fields stepped by algorithm `alg` (`ExplicitEuler`) over one MCS of length `dt`,
in `n` substeps of `dt / n`: `group` is the group's `LatticeFields.Problems.FieldGroup` (its
`GroupSpec`, its fused program and its plans), stepped through the shared runtime
(`Problems.GroupRuntime`, [`phase_context`](@ref)), as front end B steps its groups.
`program`, `masks` and `step` are the group's semantic program of `alg` and its plans (the
masks of masked conditions, run once per MCS before the substeps: the masks follow σ; and
one substep), planned once for value type `T` with `options`. `arrays[f]` binds program field
`f` to state arrays: `(Part, nothing)` for a one-buffer field (an input or a mask),
`(Part, Part)` for a state field and its scratch. `tables` binds table ids to kind tables of
the parameters and `params` the parameter slots to parameter names. `substeps(praw)` is the
substep count at raw parameter values `praw`, with the phase's tables
(`LatticeFields.Problems.with_tables`) when it has any (a host function, evaluated when the
parameters change, never per MCS).

`period` is the MCS (`mcs_duration`), the clock's period: a window starts at
`mcs · period`, plus `(r − 1) dt` in pass `r` of a sub-MCS `repeat`.

`K` names the entry of the run context that holds the trajectory's runtime
([`phase_context`](@ref)). The field ends every MCS in its `st.site` array: after an odd
number of substeps one copy brings the scratch buffer back (`ends_in = :slot1`). With
`init = true` the phase is the masked-condition clamp of a fresh initial state (one substep
of length zero: each masked site takes its value, every other site keeps its own); `init`
from a checkpoint skips it.

With `aux_only = true` the phase is bound to the group's `aux:` kernels alone (aux fields
`K ~ rhs`, F3 design §3.12) and takes no substep: one launch evaluates them from the state as
it is, which it never writes. Front end A runs one at init for a group with state and aux
fields (F3 review S1, r2 N1: no update rule, so no `lower` clip, touches the state).

With `start = true` the phase is a group's steady start (`init = :steady` on its algorithm,
F3-12c): `alg` is the `QuasiSteady` of `LatticeFields.Problems.steady_start`, bound to the same
arrays as the step and run once, at init on a fresh state (after the masked-condition clamp),
never per MCS and not from a checkpoint.
"""
struct FieldPhase{K, G, AL, A, F, PR, SP}
    group::G
    alg::AL
    program::PR
    masks::SP
    step::SP
    arrays::A
    tables::Vector{Pair{Int, Symbol}}
    params::Vector{Symbol}
    substeps::F
    dt::Float64
    period::Float64                      # the MCS (`mcs_duration`): the clock's period
    init::Bool
    aux_only::Bool                       # the `aux:` kernels alone, no substep (an at-init evaluation)
    start::Bool                          # a steady start (`init = :steady`, at init on a fresh state)
    rule_tables::Vector{Pair{String, Symbol}}   # tables only the substep rule reads (key => name)
    options::Any                         # the compile options of the plans (host)
    T::Type                              # the value type of the plans
end
function FieldPhase{K}(group, alg, arrays::Tuple; tables = Pair{Int, Symbol}[], params = Symbol[], substeps,
        dt::Real, period::Real = dt, options, T::Type, init::Bool = false, aux_only::Bool = false,
        start::Bool = false, rule_tables = Pair{String, Symbol}[]) where {K}
    program = Problems.group_program(group, alg)
    # the plans of value type `T`, made once per group (shared by every trajectory; the host
    # backend only decides the Float64 check here, which `options` already holds)
    masks, step = aux_only ?
        Problems.group_plans(group, alg, T, KernelAbstractions.CPU(), options; kernels = (Int[], _aux_ids(program))) :
        Problems.group_plans(group, alg, T, KernelAbstractions.CPU(), options)
    return FieldPhase{K, typeof(group), typeof(alg), typeof(arrays), typeof(substeps), typeof(program), typeof(step)}(
        group, alg, program, masks, step, arrays, tables, params, substeps, Float64(dt), Float64(period), init, aux_only,
        start, collect(Pair{String, Symbol}, rule_tables), options, T)
end
# the ids of a program's `aux:` kernels (an `aux_only` phase binds them alone)
_aux_ids(prog) = [i for (i, k) in enumerate(prog.kernels) if startswith(k.key, "aux:")]
_aux_ids(ph::FieldPhase) = _aux_ids(ph.program)
"""The masked-condition clamp of field phase `ph` (its at-init form)."""
field_clamp(ph::FieldPhase{K}) where {K} =
    FieldPhase{K}(ph.group, ph.alg, ph.arrays; ph.tables, ph.params, ph.substeps, ph.dt, ph.period, ph.options, ph.T,
        init = true, ph.aux_only, ph.rule_tables)

"""
The front end's record of a field runtime's binding (`Problems.GroupRuntime`'s `host`): the
parameter object and the state arrays the launches were bound from, and the parameter and
table values they depend on. The runtime is bound again when the parameters or the state
arrays change.
"""
mutable struct FieldBinding{P, A}
    p::P
    arrays::A
    pvals::Vector{Any}                  # the parameter and table values the launches were bound with
    tvals::Vector{Any}
end

# The run-context entry of a field phase: the runtime behind an untyped reference, so the
# context's type (what kernels receive, adapted to `nothing` here) carries none of the
# host launch state (its Float64 step lengths, D-C8 item 9); `R` recovers the runtime's type
struct FieldHandle{R}
    ref::Base.RefValue{Any}
end
FieldHandle(rt) = FieldHandle{typeof(rt)}(Ref{Any}(rt))
_runtime(h::FieldHandle{R}) where {R} = h.ref[]::R
Adapt.adapt_structure(to, ::FieldHandle) = nothing

_arrays(arrays::Tuple, st) = map(a -> (a[1](st), a[2] === nothing ? nothing : a[2](st)), arrays)

"""
    BindingScratch()

The `arrays` entry of a program field that no state array holds: a face value or a masked
value that varies by site (`face:c:…`, `maskvalue:c`), which its own kernel computes every
window. The binding allocates it ([`FieldPhase`](@ref)); it is not part of the state (not
saved, not in a checkpoint).
"""
struct BindingScratch end
(::BindingScratch)(st) = nothing

_scratch(backend, ::Type{E}, n) where {E} = fill!(KernelAbstractions.allocate(backend, E, n), zero(E))
function _table_array(backend, ::Type{E}, v) where {E}
    a = KernelAbstractions.allocate(backend, E, length(v))
    _bind_copy!(a, E[E(x) for x in v])
    return a
end
# the one raw copy of a field binding (D-085 allowlist): a phase's tables to the backend when it
# binds, and at a rebind the new table values and the status word (setup and rebinding, never
# per MCS)
_bind_copy!(dst, src) = copyto!(dst, src)

# The value of parameter slot `n` at `p`: the clock's slot (`clock__tick`, F2 design §2.6) is
# not a parameter of the model; its launches write the step index (the MCS number) into it
const _CLOCK = Symbol(Problems.CLOCK_KEY)
_param(p, n::Symbol) = n === _CLOCK ? 0.0 : getproperty(p, n)

# the parameter values and table contents a binding depends on (copies: a table written in
# place is a change)
_bound_values(ph::FieldPhase, p) = (Any[_param(p, n) for n in ph.params],
                                    Any[copy(vec(collect(getproperty(p, name)))) for name in _table_names(ph)])
# the tables a phase depends on: its program's, then those only its substep rule reads
_table_names(ph::FieldPhase) = Iterators.flatten((last.(ph.tables), last.(ph.rule_tables)))

# whether the phase's parameters and tables at `p` equal those of the binding `b` (no copies)
function _same_params(ph::FieldPhase, b::FieldBinding, p)
    for (k, n) in enumerate(ph.params)
        isequal(_param(p, n), b.pvals[k]) || return false
    end
    return true
end
function _same_tables(ph::FieldPhase, b::FieldBinding, p)
    for (k, name) in enumerate(_table_names(ph))
        t, v = getproperty(p, name), b.tvals[k]
        t isa Array || (t = collect(t))             # a device table: read on the host
        length(t) == length(v) || return false
        for (x, y) in zip(t, v)
            isequal(x, y) || return false
        end
    end
    return true
end

# the phase's tables at `p` by their program keys (the substep bound reads them: a table
# coefficient, F1)
# (and the tables only the rule reads: the steady gain of another group, F3-12c)
_table_values(ph::FieldPhase, p) = Pair{String, Vector{Float64}}[
    [ph.program.tables[i].key => Float64.(vec(collect(getproperty(p, name)))) for (i, name) in ph.tables];
    [k => Float64.(vec(collect(getproperty(p, name)))) for (k, name) in ph.rule_tables]]
# the raw parameter values of the phase's slots at `p`
_praw(ph::FieldPhase, p) = Tuple(_param(p, n) for n in ph.params)
# … as the substep rule reads them, with the phase's tables (`field_substeps`, `field_report`)
_policy_params(ph::FieldPhase, p) = Problems.with_tables(Float64[_praw(ph, p)...], _table_values(ph, p))

"""
    field_substeps(ph, p) -> Int

The substep count of field phase `ph` at parameters `p`: its `substeps` rule at the phase's
parameter and table values. The rule throws (an `ArgumentError`) for parameters it refuses
(negative diffusion, a coupling past the limit, a coefficient with no finite bound), so a
caller that checks before it changes anything keeps the run atomic. A group with state needs
at least one substep; a group with no state (aux fields only, F3 design §3.12) takes 0: its
window evaluates them once.
"""
function field_substeps(ph::FieldPhase, p)
    n = ph.substeps(_policy_params(ph, p))
    _stateless(ph) && return n
    n >= 1 || throw(ArgumentError("a field group needs at least one substep; got $n"))
    return n
end
# a group with no state field (aux fields `K ~ rhs` only), or a phase of its aux kernels alone
_stateless(ph::FieldPhase) = ph.aux_only || isempty(ph.group.spec.state)

# The runtime of a field phase bound to the state's arrays at parameters `p` (front end A on
# the shared group runtime: `ends_in = :slot1`, the field back in its `st.site` array after an
# odd count), with the step's substep count (also when `ph` is the at-init clamp, which runs
# one substep of length zero from the same launches: the binding is the step's, D-C8 item 8).
# `tables` reuses the device tables of an earlier binding when their contents are unchanged.
function _field_bind(ph::FieldPhase, st, p, backend; tables = nothing, abstol = 1 // 10^6, reltol = 1 // 10^3)
    s = ph.program
    arrs = _arrays(ph.arrays, st)
    # (a scratch field on its own level: a coarse field's face or masked value, F3-17)
    nf(i) = LatticeFields.IR.nsites(s, s.fields[i].levels[1])
    bufs = [a[1] === nothing ? Any[_scratch(backend, LatticeFields.IR.juliatype(s.fields[i].storage), nf(i))] :
            a[2] === nothing ? Any[vec(a[1])] : Any[vec(a[1]), vec(a[2])] for (i, a) in enumerate(arrs)]
    # every bound array holds its field's sites (the kernels index it unchecked)
    for (i, b) in enumerate(bufs), x in b
        length(x) == nf(i) || throw(ArgumentError(string("field array `", s.fields[i].key, "` has ", length(x),
            " values; its grid has ", nf(i), " sites")))
    end
    if tables === nothing
        tables = Any[nothing for _ in s.tables]
        for (i, name) in ph.tables
            lane = s.tables[i].storage
            tables[i] = _table_array(backend, LatticeFields.IR.juliatype(lane), vec(collect(getproperty(p, name))))
        end
    end
    store = Problems.FieldStore(backend, bufs, ones(Int, length(bufs)), tables)
    n = field_substeps(ph, p)
    host = FieldBinding(p, arrs, _bound_values(ph, p)...)
    return Problems.bind_group(ph.group, ph.alg, store, _praw(ph, p); n, dt = ph.dt, c = nothing, ends_in = :slot1,
        backend, options = ph.options, V = ph.T, host, abstol, reltol, kernels = ph.aux_only ? (Int[], _aux_ids(ph)) : nothing)
end

"""
    phase_context(phase, st, p, backend) -> NamedTuple

The run-context entries a phase needs for one trajectory, built once when an integrator is
created (after the state and parameters are on `backend`): a [`FieldPhase`](@ref) binds its
group's runtime to the state's arrays and compiles its launches. Other phases need none
(`(;)`).
"""
phase_context(ph, st, p, backend) = (;)
function phase_context(ph::FieldPhase{K}, st, p, backend; abstol = 1 // 10^6, reltol = 1 // 10^3) where {K}
    ph.init && return (;)
    rt = _field_bind(ph, st, p, backend; abstol, reltol)
    # the status word's window in the front end's words: "MCS n" (a rate group takes `R` windows
    # per MCS in a sub-MCS `repeat(R, …)`; a map group and a group with no state take one)
    per = ph.alg isa Problems.ExplicitMap || _stateless(ph) ? 1 : max(round(Int, ph.period / ph.dt), 1)
    rt.totals.where = ph.start ? Problems.StartText() : _MCSWindow(ph.period, per)
    # on a device the kernels of a step (its launches, the masks, the clamp at the step's start
    # and the slot-1 copies) compile on host tasks, awaited before the first enqueue
    Exec.ishost(backend) || (rt.pending = Threads.@spawn _field_compile!(backend, rt))
    return NamedTuple{(K,)}((FieldHandle(rt),))
end

# window `w` of a field runtime as the MCS it ran in (window 1 starts at MCS time `t1`; the
# `n`-th MCS starts at time `(n − 1) · period`)
struct _MCSWindow
    period::Float64
    per::Int                            # the windows of one MCS
end
function (m::_MCSWindow)(w::Integer, t1::Real)
    n = round(Int, t1 / m.period) + cld(w, m.per)
    r = mod1(w, m.per)
    t = round((n - 1) * m.period + (r - 1) * m.period / m.per; sigdigits = 6)
    return m.per == 1 ? string("the field step of MCS ", n, " (t = ", t, ")") :
           string("the field step of MCS ", n, " (pass ", r, " of ", m.per, ", t = ", t, ")")
end

"""The merged [`phase_context`](@ref) of every phase of `phases` (each once)."""
function phase_contexts(phases::Phases, st, p, backend; abstol = 1 // 10^6, reltol = 1 // 10^3)
    ctx = (;)
    for e in (phases.mcs..., phases.at_init)
        for t in (e isa Repeat ? e.entries : (e,))
            t isa Tuple || continue
            for ph in t
                c = ph isa FieldPhase ? phase_context(ph, st, p, backend; abstol, reltol) : phase_context(ph, st, p, backend)
                ctx = merge(ctx, c)
            end
        end
    end
    return ctx
end

_has_implicit_field_phase(phases::Phases) =
    any(ph -> !ph.aux_only && ph.alg isa Problems.AbstractImplicitFieldAlgorithm, _field_phases(phases))
_uses_lattice_newton(phases::Phases) =
    any(ph -> !ph.aux_only && ph.alg isa Problems.AbstractImplicitFieldAlgorithm && ph.alg.nlsolve isa Problems.LatticeNewton, _field_phases(phases))

# every field phase of the MCS order of `phases` (the steps, not the at-init clamps), each once
function _field_phases(phases::Phases)
    out = FieldPhase[]
    for e in phases.mcs, t in (e isa Repeat ? e.entries : (e,))
        t isa Tuple || continue
        for ph in t
            ph isa FieldPhase && !ph.init && !any(q -> q === ph, out) && push!(out, ph)
        end
    end
    return out
end

"""
    check_field_parameters(f, p)
    check_field_parameters(integ, p)

Check the field phases of problem function `f` (or of integrator `integ`) at new parameters
`p` before anything changes: each phase's substep rule ([`field_substeps`](@ref)) refuses
parameters that make its step unsafe (negative diffusion, a coupling between field groups past
its limit, a coefficient with no finite bound) with an `ArgumentError`. A parameter write on an
integrator (`setp`, `integ.ps[x] = v`) and `remake` run it first, so a refused value changes
nothing: the parameters, the state and the time stay as they were. On an integrator only the
phases whose own parameters or tables change are checked.
"""
function check_field_parameters(@nospecialize(f), @nospecialize(p))     # host, once per change (TS1c)
    for ph in _field_phases(f.phases)
        field_substeps(ph, p)
    end
    return nothing
end

# A test hook: an event the field compile tasks wait on before compiling (`nothing`: none),
# so a test can act while a compile is certainly pending
const _COMPILE_HOLD = Ref{Union{Nothing, Base.Event}}(nothing)
function _field_compile!(backend, rt)
    hold = _COMPILE_HOLD[]
    hold === nothing || wait(hold)
    return Problems.compile!(backend, rt)
end

# wait for the compile task of `rt` (cold: the first run after `init`); a failed compile
# rethrows here, before anything is enqueued
function _await!(rt::Problems.GroupRuntime)
    t = rt.pending
    rt.pending = nothing
    t === nothing || fetch(t)
    return nothing
end

# Rebinding (host, cold): another parameter object (a `setp`, a callback) or new state arrays
# (a state written into the integrator) since the launches were bound. The launches depend on
# the phase's own parameters and tables only: when those values are unchanged the binding is
# kept (a temperature change each MCS rebinds nothing); unchanged tables are reused. The
# binding is always the step's (the at-init clamp reads its launches with one substep of
# length zero), so the clamp of `reinit!` never leaves the step with the clamp's count. The
# runtime is updated in place (its handle and every reference to it stay valid).
function _rebind!(rt::Problems.GroupRuntime, ph::FieldPhase, st, p, backend)
    _await!(rt)
    b = rt.host
    same_arrays = b.arrays === _arrays(ph.arrays, st)
    same_tables = _same_tables(ph, b, p)
    if same_arrays && same_tables && _same_params(ph, b, p)
        b.p = p
        return rt
    end
    # an implicit group on the same arrays: in place (its solvers take the new coefficients;
    # building them again would compile their kernels), the tables written into their arrays,
    # and `reset!` (the hierarchy is rebuilt before the next window)
    if same_arrays && rt.cache isa Problems.ImplicitCache && _tables_fit(ph, rt, p) && _praw(ph, p) isa typeof(rt.p)
        n = field_substeps(ph, p)                   # (the policy's refusals first: nothing changed yet)
        praw = _praw(ph, p)
        launches = Problems.rebind_launches(rt, praw)
        same_tables || _write_tables!(ph, rt, p)
        rt.p = praw
        Problems.install_launches!(rt, launches)
        rt.n = n
        b.p = p
        b.pvals, b.tvals = _bound_values(ph, p)
        return rt
    end
    new = if rt.cache isa Problems.ImplicitCache
        _field_bind(ph, st, p, backend; tables = same_tables ? rt.store.tables : nothing, abstol = rt.cache.abstol, reltol = rt.cache.reltol)
    else
        _field_bind(ph, st, p, backend; tables = same_tables ? rt.store.tables : nothing)
    end
    # the status word's counts not read yet stay the run's (the new runtime's word starts there)
    wo, wn = Problems.status_word(rt.cache), Problems.status_word(new.cache)
    wo === nothing || wn === nothing || _bind_copy!(wn, wo)
    for f in fieldnames(typeof(rt))
        # the status word's totals and the worst code stay the run's (cleared by `reinit!`)
        (f === :totals || f === :status) && continue
        setfield!(rt, f, getfield(new, f))
    end
    return rt
end

# whether the phase's tables at `p` fit the runtime's table arrays (the same lengths), and
# their values written into them (host or device: a copy)
_tables_fit(ph::FieldPhase, rt, p) = all(((i, name),) -> length(rt.store.tables[i]) == length(getproperty(p, name)), ph.tables)
function _write_tables!(ph::FieldPhase, rt, p)
    for (i, name) in ph.tables
        a = rt.store.tables[i]
        _bind_copy!(a, eltype(a)[eltype(a)(x) for x in vec(collect(getproperty(p, name)))])
    end
    return nothing
end

# The phase runs one window of the fields: pass `part = (r, R)` of the `R` passes of a sub-MCS
# `repeat(R, …)` (`(1, 1)` for the whole MCS); a map group (`ExplicitMap`) steps in pass 1 only,
# and so does a group with no state (aux fields only, F3 design §3.12: once per MCS).
# The clock (F2 design §2.6): the step index is
# the MCS number `mcs` (the same in every pass), and the window starts at the time
# `t0 = (mcs + (r − 1)/R) · mcs_duration`; substep `j` runs at `t0 + j h`.
function (ph::FieldPhase{K})(st, p, ctx, key, mcs, backend, part::NTuple{2, Int} = (1, 1)) where {K}
    # a map steps once per MCS (the clock's period), in the first pass of a sub-MCS `repeat`
    (ph.alg isa Problems.ExplicitMap || _stateless(ph)) && !ph.init && part[1] != 1 && return 0
    rt = _runtime(getfield(ctx, K))
    rt.pending === nothing || Base.invokelatest(_await!, rt)
    # the rebinding is cold host work (the substep bound, new launches): called past an
    # inference barrier, so the warm path compiles without it
    (rt.host.p === p && rt.host.arrays === _arrays(ph.arrays, st)) || Base.invokelatest(_rebind!, rt, ph, st, p, backend)
    # the at-init clamp: one substep of length zero from the step's launches
    n = ph.init ? 1 : rt.n
    # (the at-init clamp runs outside the passes: `part = (1, 1)`, its window starts at `mcs · period`)
    t0 = mcs * ph.period + (part[1] - 1) * ph.dt          # ph.dt = mcs_duration / R
    # (a run with derivative parts, F3-21b: its shadow runtime too, from the same start)
    _field_advance!(ctx, ph, st, rt, (t0, mcs), n, ph.init ? 0.0 : rt.dt)
    # (a group with no state: `n = 0`, its kernels once)
    launches = max(n, 1) * length(rt.steps[1].launches)
    # the masks (on a device they clamp the sites they mark; a clamp they cannot take is one
    # more kernel)
    rt.masks === nothing || (launches += length(rt.masks[1].launches) + (Exec.ishost(backend) ? 0 : length(rt.stepclamps)))
    isodd(n) && (launches += length(rt.copies))
    return launches
end

# a field phase takes the pass of a sub-MCS `repeat` (`_run_phases`); other phases do not.
# On the host its group's status word is read after its window (F3 design §3.4: a plain read;
# nothing for the explicit algorithms, whose caches have no word)
function _run_phase(ph::FieldPhase{K}, st, p, ctx, key, mcs, backend, stats, part) where {K}
    n = ph(st, p, ctx, key, mcs, backend, part)
    # (a steady start's word is read at once on a device too: one read at init, cold)
    stats === nothing || ph.init || !(ph.start || Exec.ishost(backend)) || _read_status!(stats, _runtime(getfield(ctx, K)))
    return n
end

"""
    FieldStats

The field solvers' counters of a run (`integ.stats.fields`, F3 design §3.3), summed over the
status words of its field groups: `solves`, `budget` (linear budget hits), `floor` (rounding
floors), `newton_budget` (Newton budget hits), and `code`, the worst code read so far
(`Success`, `StalledSuccess`, `ConvergenceFailure`, or `Unstable` when a field left the declared
`bounds` its stability bound used). All zero for the explicit algorithms. On a device, each read
of `integ.stats` reads the status words first (one synchronization), so the counters include
every window so far. When a solution is built at the end of a run, it also keeps what the
field report of the solution reads (batch-end review (e), as LatticePDE's `sol.stats`
does): `counts`, the substep count each field group used last ([`substep_counts`](@ref));
`implicit`, the resolved implicit facts of each group (`nothing` for an explicit one;
`Problems.implicit_facts`); and `backend`, the backend's name (`"CPU"`). All empty before.
"""
Base.@kwdef mutable struct FieldStats
    solves::Int64 = 0
    budget::Int64 = 0
    floor::Int64 = 0
    newton_budget::Int64 = 0
    code::SciMLBase.ReturnCode.T = SciMLBase.ReturnCode.Success
    counts::Vector{Int} = Int[]
    implicit::Vector{Union{Nothing, Problems.ImplicitFacts}} = Union{Nothing, Problems.ImplicitFacts}[]
    backend::String = ""
end
Base.show(io::IO, s::FieldStats) = print(io, "FieldStats(solves = ", s.solves, ", budget = ", s.budget, ", floor = ",
    s.floor, ", newton_budget = ", s.newton_budget, ", code = ", s.code, ")")
_rank(c::SciMLBase.ReturnCode.T) = c == SciMLBase.ReturnCode.Success ? 0 : c == SciMLBase.ReturnCode.StalledSuccess ? 1 : 2
# one group's status word into the run's counters and code (`Problems.check_status!`)
function _read_status!(stats, rt::Problems.GroupRuntime)
    c = Problems.check_status!(rt, stats.fields)
    # the fields whose declared bounds the stability bound used, still inside them (batch 5
    # review M2): `Unstable` past them, with one warning
    c = Problems.check_declared!(rt)
    _rank(c) > _rank(stats.fields.code) && (stats.fields.code = c)
    return nothing
end
"""
    reset_fields!(ctx)

Drop the algorithm history of every field group of run context `ctx`
(`LatticeFields.Problems.reset!`): the state was written (`integ[c] = values`, `setu`, a
callback with `derivative_discontinuity!(integ, true)`, `reinit!`), so Crank–Nicolson damps its next substep
and BDF2 restarts with a Backward Euler substep; the hierarchy of an implicit group is rebuilt.
Nothing for the explicit algorithms. A move of σ by the CPM is no write: the fields' history
survives it.
"""
function reset_fields!(ctx)
    for h in values(ctx)
        h isa FieldHandle && Problems.reset!(_runtime(h))
        h isa TangentHandle && foreach(Problems.reset!, values(_tangent_run(h).rts))
    end
    return nothing
end
# every field group's word (the read points on a device: `saveat` and the end; cold)
function _read_statuses!(stats, ctx)
    for h in values(ctx)
        h isa FieldHandle && _read_status!(stats, _runtime(h))
    end
    return nothing
end

# The at-init phases of a state that is not fresh (a checkpoint restore, `Potts.anneal`'s
# per-MCS refresh): the derived refreshes without the field clamps and the steady starts,
# which hold on a fresh initial state only (D-145)
_derived(t::Tuple) = filter(ph -> !(ph isa FieldPhase && (ph.init || ph.start)), t)

# ---------------------------------------------------------------------------------------
# Derivative parts of the fields (F3-21b): a shadow tangent store. A problem with a
# `ParameterTangent` runs the primal model unchanged (the CPM, its kernels and the primal field
# runtimes read and write only primal arrays at the primal parameters), and each field phase has
# a second runtime, bound to a shadow store at the Dual element type: a Dual twin of every array
# a field group writes (its state, aux and output fields; one twin per array, shared by every
# group that reads it), Dual scratch, and the state's own primal arrays for what the group only
# reads (the CPM inputs, masks, site variables, tables). Before each window the twins take the
# primal state's values (their derivative parts kept); an explicit group's shadow runtime steps
# forward mode, then the primal one; an implicit group's primal runtime solves each stage once and
# F3-21a's tangent step (`TangentCache`, on the primal cache) follows it (`advance_shared!`). The derivative is pathwise at the run's CPM path: σ, the cells
# and every CPM value are held fixed, and the fields' response to the parameters is
# differentiated along it.

"""
    ParameterTangent(p, seeds, u0 = [])

The parameters of a run with derivative parts (F3-21b): `p` is the parameter object with
ForwardDiff Duals in the entries that carry them (the seeded parameters and the computed ones
that read them), `seeds` the front end's record of the Dual values given (`name => value`), and
`u0` the derivative parts of the initial fields (`name => Dual array or Dual number`: a Dual
initial value, or a default that reads a seeded parameter). The CPM reads the primal object
(`prob.p`); the field groups step the derivative parts along the CPM path ([`tangent_run`](@ref)).
"""
struct ParameterTangent{P}
    p::P
    seeds::Vector{Pair{Symbol, Any}}
    u0::Vector{Pair{Symbol, Any}}
end
ParameterTangent(p, seeds) = ParameterTangent(p, seeds, Pair{Symbol, Any}[])
# the tangent of a problem whose initial state was replaced: the initial parts go (`nothing` when
# no seed is left)
without_initial(::Nothing) = nothing
without_initial(tg::ParameterTangent) = isempty(tg.seeds) ? nothing : ParameterTangent(tg.p, tg.seeds)

"""
    tangent_parameters(sys, dp, p)

The parameter object with derivative parts after a parameter write on a run with them: `dp` the
one before, `p` the new primal object. A symbolic layer keeps each entry whose value the write did
not change (its derivative parts with it), takes the written values as plain numbers, and derives
the computed entries again. Here: `p` (no derivative parts).
"""
tangent_parameters(sys, dp, p) = p

"""
The run context's entry of a run with derivative parts (`ctx.__tangent`): the host
[`TangentRun`](@ref) behind an untyped reference; kernels see `nothing`.
"""
struct TangentHandle
    ref::Base.RefValue{Any}
end
Adapt.adapt_structure(to, ::TangentHandle) = nothing

"""
The shadow tangent store of one trajectory: the Dual parameter object and its version (one more
per parameter write), the twins (primal array ⇒ Dual twin; `names`: a field's name ⇒ the twin of
its state array, for the reads), each field phase's shadow runtime by its context key, whether it
shares its primal runtime's solve (an implicit group, F3-21b r1 S3), the primal runtime's store
and cache and the version it was bound at, and the (twin, primal) pairs whose values are set
before each window.
"""
mutable struct TangentRun
    p::Any
    version::Int
    E::Type
    twins::IdDict{Any, Any}
    written::IdDict{Any, Nothing}
    names::Dict{Symbol, Any}
    rts::Dict{Symbol, Any}
    shared::Dict{Symbol, Bool}
    bound::Dict{Symbol, Tuple{Any, Any, Int}}
    syncs::Dict{Symbol, Vector{Tuple{Any, Any}}}
    backend::Any
end
_tangent_run(h::TangentHandle) = h.ref[]::TangentRun

# whether run context `ctx` has a shadow tangent store, as a type (`Val(true)` or `Val(false)`):
# a primal run dispatches to the no-op methods, so it infers none of the tangent code. A plain
# method (the repo rules forbid staged functions): `K` is a constant of the type, so `in` folds
# and the `Val` is inferred
tangent_on(::NamedTuple{K}) where {K} = Val(:__tangent in K)

# the run context with the shadow store of `tg` (none for a primal problem: no entry, so the
# phases compile no tangent path); `fresh`: the initial state's derivative parts are seeded
with_tangent(ctx, ::Nothing, phases, st, p, backend, fresh = true) = ctx
with_tangent(ctx, tg::ParameterTangent, phases, st, p, backend, fresh = true) =
    merge(ctx, (; __tangent = TangentHandle(Ref{Any}(Base.invokelatest(tangent_run, phases, st, p, tg, backend, ctx, fresh)))))

# One window of field phase `ph` on its primal runtime `rt` (a primal run: `advance!` alone)
@inline _field_advance!(ctx::NamedTuple, ph, st, rt, tm, n, h) = _field_advance!(tangent_on(ctx), ctx, ph, st, rt, tm, n, h)
_field_advance!(::Val{false}, ctx, ph, st, rt, tm, n, h) = (Problems.advance!(rt, tm, n, h); nothing)
_field_advance!(::Val{true}, ctx, ph, st, rt, tm, n, h) =
    (Base.invokelatest(_tangent_advance!, getfield(ctx, :__tangent), ph, st, rt, tm, n, h); nothing)

_tvalue_body!(i, tw, a) = (@inbounds tw[i] = LatticeFields.Compile.dreplace(tw[i], a[i]); nothing)   # i ≤ length(tw)
# the window with derivative parts: the twins take the primal values, then an implicit group's
# primal solve and tangent steps together (one solve per stage), or an explicit group's shadow
# step and then its primal step
function _tangent_advance!(h::TangentHandle, ph::FieldPhase{K}, st, rt, tm, n, dt) where {K}
    run = _tangent_run(h)
    trt = _shadow!(run, ph, st, rt)
    for (tw, a) in run.syncs[K]
        Exec.launch!(run.backend, _tvalue_body!, length(tw), (tw, a))
    end
    if run.shared[K]
        Problems.advance_shared!(rt, trt, tm, n, dt)
    else
        Problems.advance!(trt, tm, n, dt)
        Problems.advance!(rt, tm, n, dt)
    end
    return nothing
end

# the Dual element type of a tangent (one type for every seed: one tag, one count)
_dualtype(v) = v isa AbstractArray ? eltype(v) : typeof(v)
function _tangent_eltype(tg::ParameterTangent, T)
    Es = unique(Any[LatticeFields.Compile.withvaltype(_dualtype(v), T) for (_, v) in Iterators.flatten((tg.seeds, tg.u0))])
    length(Es) == 1 || throw(ArgumentError(string("the values with derivative parts hold ", length(Es),
        " different Dual types (", join((LatticeFields.Compile.npartials(E) for E in Es), ", "), " derivative parts, or ",
        "different tags); give every seed of one run the same Dual type (one `ForwardDiff.derivative`, `gradient` ",
        "or `jacobian` call)")))
    return only(Es)
end

# the field phases of `phases` that bind a runtime (the steps, the steady starts and the aux-only
# evaluations; the at-init clamps read their step's), each once
function _bound_phases(phases::Phases)
    out = FieldPhase[]
    for e in (phases.mcs..., phases.at_init), t in (e isa Repeat ? e.entries : (e,))
        t isa Tuple || continue
        for ph in t
            ph isa FieldPhase && !ph.init && !any(q -> q === ph, out) && push!(out, ph)
        end
    end
    return out
end

"""
    tangent_run(phases, st, p, tg, backend, ctx, fresh = true) -> TangentRun

The shadow tangent store of a trajectory (built at `init`, after the primal runtimes): every
field phase bound again to Dual twins of the arrays the field groups write, at the Dual
parameters `tg.p`, with the primal runtimes' substep counts and tables. An implicit group's
tangent shares its primal runtime's cache (one primal solve per stage). With `fresh`, the twins
take the initial fields' derivative parts `tg.u0`.
"""
function tangent_run(phases::Phases, st, p, tg::ParameterTangent, backend, ctx, fresh::Bool = true)
    phs = _bound_phases(phases)
    T = isempty(phs) ? Float64 : phs[1].T
    E = _tangent_eltype(tg, T)
    # the arrays the field groups write: their state, aux and output fields
    written = IdDict{Any, Nothing}()
    for ph in phs, (i, a) in enumerate(_arrays(ph.arrays, st))
        ph.program.fields[i].role in (:state, :aux, :output) || continue
        for x in a
            x === nothing || (written[x] = nothing)
        end
    end
    run = TangentRun(tg.p, 0, E, IdDict{Any, Any}(), written, Dict{Symbol, Any}(), Dict{Symbol, Any}(), Dict{Symbol, Bool}(),
        Dict{Symbol, Tuple{Any, Any, Int}}(), Dict{Symbol, Vector{Tuple{Any, Any}}}(), backend)
    any_seeded = false
    for ph in phs
        _shadow!(run, ph, st, _runtime(getfield(ctx, _ctxkey(ph))))
        any_seeded |= any(x -> LatticeFields.Compile.npartials(typeof(x)) > 0 && !iszero(x - LatticeFields.Compile.primal(x)),
            _praw(ph, tg.p))
    end
    any_seeded || !isempty(tg.u0) || isempty(phs) || @warn string("no field group reads a parameter with derivative parts, ",
        "so every derivative of the fields is zero: the CPM and the ODEs read the primal values, and the derivative holds ",
        "the CPM path fixed (F3-21b)") maxlog = 1
    fresh && _seed_initial!(nothing, run, tg)
    return run
end

# The shadow runtime of phase `ph` (its context key `K`), bound again when the primal runtime's
# store or cache changed (a rebind that made new arrays) or the Dual parameters did (a write)
function _shadow!(run::TangentRun, ph::FieldPhase{K}, st, prt) where {K}
    b = get(run.bound, K, nothing)
    b !== nothing && b[1] === prt.store && b[2] === prt.cache && b[3] == run.version && return run.rts[K]
    backend = run.backend
    E = run.E
    s = ph.program
    arrs = _arrays(ph.arrays, st)
    twin(x) = get!(() -> fill!(KernelAbstractions.allocate(backend, LatticeFields.Compile.withvaltype(E, eltype(x)), size(x)),
                               zero(LatticeFields.Compile.withvaltype(E, eltype(x)))), run.twins, x)
    nf(i) = LatticeFields.IR.nsites(s, s.fields[i].levels[1])
    bufs = map(enumerate(arrs)) do (i, a)
        if a[1] === nothing                 # a face or masked value: Dual scratch for a float
            S = LatticeFields.IR.juliatype(s.fields[i].storage)
            return Any[S <: AbstractFloat ? _scratch(backend, LatticeFields.Compile.withvaltype(E, S), nf(i)) :
                       _scratch(backend, S, nf(i))]
        end
        return Any[x isa AbstractArray && eltype(x) <: AbstractFloat && haskey(run.written, x) ? vec(twin(x)) : vec(x)
                   for x in a if x !== nothing]
    end
    # the values of every twin the phase binds (its own fields, and another group's it reads)
    # from the primal state; a state field's twin is also read back by its name
    sync = Tuple{Any, Any}[]
    for a in arrs
        (a[1] !== nothing && haskey(run.twins, a[1])) || continue
        push!(sync, (vec(run.twins[a[1]]), vec(a[1])))
        a[2] === nothing || (run.names[_part_name(ph, a[1], st)] = run.twins[a[1]])
    end
    # an implicit group's tangent on its primal runtime's cache: the stores share the slot parity
    shared = ph.alg isa Problems.AbstractImplicitFieldAlgorithm && !ph.aux_only && prt.cache isa Problems.ImplicitCache
    store = Problems.FieldStore(backend, bufs, shared ? prt.store.cur : ones(Int, length(bufs)), prt.store.tables)
    tols = shared ? (abstol = prt.cache.abstol, reltol = prt.cache.reltol) : (;)
    trt = Problems.bind_group(ph.group, ph.alg, store, _praw(ph, run.p); n = prt.n, dt = ph.dt, c = zero(E),
        ends_in = :slot1, backend, options = ph.options, V = ph.T, host = nothing,
        kernels = ph.aux_only ? (Int[], _aux_ids(ph)) : nothing,
        tols...,
        (shared ? (; shared = (prt.cache, prt.store)) : (;))...)
    trt.totals.where = prt.totals.where
    Exec.ishost(backend) || Problems.compile!(backend, trt)
    run.rts[K], run.syncs[K], run.shared[K] = trt, sync, shared
    run.bound[K] = (prt.store, prt.cache, run.version)
    return trt
end
# the state name of array `x` bound by phase `ph` (its `Part`)
function _part_name(ph::FieldPhase, x, st)
    for a in ph.arrays, q in a
        q === nothing || q isa BindingScratch || q(st) !== x || return _partname(q)
    end
    error("no state array of the phase is the twin's")
end
_partname(::Part{A, B}) where {A, B} = B

# A host snapshot with the fields' derivative parts (`current_state` of a run with them): each
# twinned field's array as Duals, the value the primal state's (bitwise) and the derivative parts
# the twin's; every other array as it is
tangent_snapshot(stats, ctx, snap) = _tangent_snapshot(tangent_on(ctx), stats, ctx, snap)
_tangent_snapshot(::Val{false}, stats, ctx, snap) = snap
function _tangent_snapshot(::Val{true}, stats, ctx, snap::CPMState)
    run = _tangent_run(getfield(ctx, :__tangent))
    isempty(run.names) && return snap
    ks = Tuple(k for k in keys(snap.site) if haskey(run.names, k))
    vs = map(ks) do k
        tw = _to_host(stats, run.names[k])
        v = getfield(snap.site, k)
        reshape(map((d, x) -> LatticeFields.Compile.dreplace(d, x), vec(tw), vec(v)), size(v))
    end
    return CPMState(snap.ownership, snap.cell, merge(snap.site, NamedTuple{ks}(vs)), snap.model, snap.history)
end

_tpart_body!(i, tw, src, j) = (@inbounds tw[i] = LatticeFields.Compile.dsetpartial(tw[i], j, LatticeFields.Compile.dpartial(src[i], j)); nothing)
_tzero_body!(i, tw) = (@inbounds tw[i] = zero(tw[i]); nothing)
# the derivative parts of `v` (an array or a number of Duals; 0 for plain values) into twin `tw`
function _set_parts!(stats, run::TangentRun, tw, v, name)
    E = eltype(tw)
    w = v isa AbstractArray ? v : fill(v, size(tw))
    if LatticeFields.Compile.npartials(eltype(w)) > 0
        LatticeFields.Compile.npartials(eltype(w)) == LatticeFields.Compile.npartials(E) ||
            throw(ArgumentError("`$name` holds $(LatticeFields.Compile.npartials(E)) derivative parts in this run; the " *
                                "written values hold $(LatticeFields.Compile.npartials(eltype(w)))"))
        size(w) == size(tw) || throw(DimensionMismatch("`$name` has size $(size(tw)); got $(size(w))"))
        src = similar(tw, E, size(tw))
        _copy!(stats, src, E[convert(E, x) for x in w])
        for j in 1:LatticeFields.Compile.npartials(E)
            Exec.launch!(run.backend, _tpart_body!, length(tw), (vec(tw), vec(src), j))
        end
    else
        Exec.launch!(run.backend, _tzero_body!, length(tw), (vec(tw),))
    end
    return nothing
end
# a write of field `name` (`integ[c] = v`): the twin's derivative parts from `v` (0 for a plain
# value or a number); nothing for an array with no twin
function tangent_write!(stats, ctx, name::Symbol, v)
    run = _tangent_run(getfield(ctx, :__tangent))
    tw = get(run.names, name, nothing)
    tw === nothing || _set_parts!(stats, run, tw, v, name)
    return nothing
end
# the initial fields' derivative parts (a fresh state)
function _seed_initial!(stats, run::TangentRun, tg::ParameterTangent)
    for (name, v) in tg.u0
        tw = get(run.names, name, nothing)
        tw === nothing && throw(ArgumentError("the initial value of `$name` holds derivative parts, and `$name` is not " *
                                              "a field a field group steps"))
        _set_parts!(stats, run, tw, v, name)
    end
    return nothing
end
# the primal part of written values (an array of Duals: their values)
tangent_primal(v::AbstractArray) = LatticeFields.Compile.npartials(eltype(v)) > 0 ? map(LatticeFields.Compile.primal, v) : v
tangent_primal(v) = LatticeFields.Compile.npartials(typeof(v)) > 0 ? LatticeFields.Compile.primal(v) : v

# a new run (`reinit!`): every twin's derivative parts zero, then the initial ones of `tg` (the
# problem's own initial state; `nothing` for another state), and the shadow runtimes' history and
# status cleared
tangent_reinit!(ctx, tg = nothing) = _tangent_reinit!(tangent_on(ctx), ctx, tg)
_tangent_reinit!(::Val{false}, ctx, tg) = nothing
function _tangent_reinit!(::Val{true}, ctx, tg)
    run = _tangent_run(getfield(ctx, :__tangent))
    for tw in values(run.twins)
        Exec.launch!(run.backend, _tzero_body!, length(tw), (vec(tw),))
    end
    tg === nothing || _seed_initial!(nothing, run, tg)
    foreach(rt -> (Problems.clear_status!(rt); Problems.reset!(rt)), values(run.rts))
    return nothing
end

# A parameter write on a run with derivative parts (F3-21b r1 S1): the Dual parameters follow
# (`tangent_parameters`: the written values plain, the others keep their derivative parts), and
# each shadow runtime is bound again at its next window
tangent_parameters!(integ, p) = _tangent_parameters!(tangent_on(integ.ctx), integ, p)
_tangent_parameters!(::Val{false}, integ, p) = nothing
function _tangent_parameters!(::Val{true}, integ, p)
    run = _tangent_run(getfield(integ.ctx, :__tangent))
    run.p = tangent_parameters(integ.f.sys, run.p, p)
    run.version += 1
    return nothing
end
