# Continuous fields on the lattice (v3 §7, cutover C8). A field is a site array of floats in
# `st.site`; its equations are lowered by the field compiler (LatticePDE → LatticeFields) into
# a step plan, and `FieldPhase` runs that plan inside the MCS: the CPM keeps reading the field
# from `st.site` as before. The arrays of the plan (the field and its scratch, the inputs the
# CPM fills, the masks) are site arrays of the state; the bound launches of one trajectory live
# in its run context (`ctx`), built when an integrator is created (`phase_context`).

"""Kind of the cell owning site `i` (`0` for the medium)."""
@inline owner_kind(st, i) = (c = @inbounds st.σ[i]; c == 0 ? Int32(0) : @inbounds st.cell.kind[c])

"""
    FieldPhase{K}(group, alg, arrays; tables, params, substeps, dt, period = dt, options, T, init = false, aux_only = false)

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
    options::Any                         # the compile options of the plans (host)
    T::Type                              # the value type of the plans
end
function FieldPhase{K}(group, alg, arrays::Tuple; tables = Pair{Int, Symbol}[], params = Symbol[], substeps,
        dt::Real, period::Real = dt, options, T::Type, init::Bool = false, aux_only::Bool = false) where {K}
    program = Problems.group_program(group, alg)
    # the plans of value type `T`, made once per group (shared by every trajectory; the host
    # backend only decides the Float64 check here, which `options` already holds)
    masks, step = aux_only ?
        Problems.group_plans(group, alg, T, KernelAbstractions.CPU(), options; kernels = (Int[], _aux_ids(program))) :
        Problems.group_plans(group, alg, T, KernelAbstractions.CPU(), options)
    return FieldPhase{K, typeof(group), typeof(alg), typeof(arrays), typeof(substeps), typeof(program), typeof(step)}(
        group, alg, program, masks, step, arrays, tables, params, substeps, Float64(dt), Float64(period), init, aux_only,
        options, T)
end
# the ids of a program's `aux:` kernels (an `aux_only` phase binds them alone)
_aux_ids(prog) = [i for (i, k) in enumerate(prog.kernels) if startswith(k.key, "aux:")]
_aux_ids(ph::FieldPhase) = _aux_ids(ph.program)
"""The masked-condition clamp of field phase `ph` (its at-init form)."""
field_clamp(ph::FieldPhase{K}) where {K} =
    FieldPhase{K}(ph.group, ph.alg, ph.arrays; ph.tables, ph.params, ph.substeps, ph.dt, ph.period, ph.options, ph.T,
        init = true, ph.aux_only)

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
                                    Any[copy(vec(collect(getproperty(p, name)))) for (_, name) in ph.tables])

# whether the phase's parameters and tables at `p` equal those of the binding `b` (no copies)
function _same_params(ph::FieldPhase, b::FieldBinding, p)
    for (k, n) in enumerate(ph.params)
        isequal(_param(p, n), b.pvals[k]) || return false
    end
    return true
end
function _same_tables(ph::FieldPhase, b::FieldBinding, p)
    for (k, (_, name)) in enumerate(ph.tables)
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
_table_values(ph::FieldPhase, p) = Pair{String, Vector{Float64}}[ph.program.tables[i].key => Float64.(vec(collect(getproperty(p, name))))
                                                                 for (i, name) in ph.tables]
# the raw parameter values of the phase's slots at `p`
_praw(ph::FieldPhase, p) = Tuple(_param(p, n) for n in ph.params)

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
    n = ph.substeps(Problems.with_tables(Float64[_praw(ph, p)...], _table_values(ph, p)))
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
function _field_bind(ph::FieldPhase, st, p, backend; tables = nothing)
    s = ph.program
    arrs = _arrays(ph.arrays, st)
    n0 = LatticeFields.IR.nsites(s, 0)
    bufs = [a[1] === nothing ? Any[_scratch(backend, LatticeFields.IR.juliatype(s.fields[i].storage), n0)] :
            a[2] === nothing ? Any[vec(a[1])] : Any[vec(a[1]), vec(a[2])] for (i, a) in enumerate(arrs)]
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
        backend, options = ph.options, V = ph.T, host, kernels = ph.aux_only ? (Int[], _aux_ids(ph)) : nothing)
end

"""
    phase_context(phase, st, p, backend) -> NamedTuple

The run-context entries a phase needs for one trajectory, built once when an integrator is
created (after the state and parameters are on `backend`): a [`FieldPhase`](@ref) binds its
group's runtime to the state's arrays and compiles its launches. Other phases need none
(`(;)`).
"""
phase_context(ph, st, p, backend) = (;)
function phase_context(ph::FieldPhase{K}, st, p, backend) where {K}
    ph.init && return (;)
    rt = _field_bind(ph, st, p, backend)
    # the status word's window in the front end's words: "MCS n" (a rate group takes `R` windows
    # per MCS in a sub-MCS `repeat(R, …)`; a map group and a group with no state take one)
    per = ph.alg isa Problems.ExplicitMap || _stateless(ph) ? 1 : max(round(Int, ph.period / ph.dt), 1)
    rt.totals.where = _MCSWindow(ph.period, per)
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
function phase_contexts(phases::Phases, st, p, backend)
    ctx = (;)
    for e in (phases.mcs..., phases.at_init)
        for t in (e isa Repeat ? e.entries : (e,))
            t isa Tuple || continue
            for ph in t
                ctx = merge(ctx, phase_context(ph, st, p, backend))
            end
        end
    end
    return ctx
end

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
function check_field_parameters(f, p)
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
    new = _field_bind(ph, st, p, backend; tables = same_tables ? rt.store.tables : nothing)
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
    Problems.advance!(rt, (t0, mcs), n, ph.init ? 0.0 : rt.dt)
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
    stats === nothing || ph.init || !Exec.ishost(backend) || _read_status!(stats, _runtime(getfield(ctx, K)))
    return n
end

"""
    FieldStats

The field solvers' counters of a run (`integ.stats.fields`, F3 design §3.3), summed over the
status words of its field groups: `solves`, `budget` (linear budget hits), `floor` (rounding
floors), `newton_budget` (Newton budget hits), and `code`, the worst code read so far
(`Success`, `StalledSuccess` or `ConvergenceFailure`). All zero for the explicit algorithms.
"""
Base.@kwdef mutable struct FieldStats
    solves::Int64 = 0
    budget::Int64 = 0
    floor::Int64 = 0
    newton_budget::Int64 = 0
    code::SciMLBase.ReturnCode.T = SciMLBase.ReturnCode.Success
end
Base.show(io::IO, s::FieldStats) = print(io, "FieldStats(solves = ", s.solves, ", budget = ", s.budget, ", floor = ",
    s.floor, ", newton_budget = ", s.newton_budget, ", code = ", s.code, ")")
_rank(c::SciMLBase.ReturnCode.T) = c == SciMLBase.ReturnCode.Success ? 0 : c == SciMLBase.ReturnCode.StalledSuccess ? 1 : 2
# one group's status word into the run's counters and code (`Problems.check_status!`)
function _read_status!(stats, rt::Problems.GroupRuntime)
    c = Problems.check_status!(rt, stats.fields)
    _rank(c) > _rank(stats.fields.code) && (stats.fields.code = c)
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
# per-MCS refresh): the derived refreshes without the field clamps, which hold on a fresh
# initial state only (D-145)
_derived(t::Tuple) = filter(ph -> !(ph isa FieldPhase && ph.init), t)
