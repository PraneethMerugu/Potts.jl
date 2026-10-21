# Continuous fields on the lattice (v3 §7, cutover C8). A field is a site array of floats in
# `st.site`; its equations are lowered by the field compiler (LatticePDE → LatticeFields) into
# a step plan, and `FieldPhase` runs that plan inside the MCS: the CPM keeps reading the field
# from `st.site` as before. The arrays of the plan (the field and its scratch, the inputs the
# CPM fills, the masks) are site arrays of the state; the bound launches of one trajectory live
# in its run context (`ctx`), built when an integrator is created (`phase_context`).

"""Kind of the cell owning site `i` (`0` for the medium)."""
@inline owner_kind(st, i) = (c = @inbounds st.σ[i]; c == 0 ? Int32(0) : @inbounds st.cell.kind[c])

"""
    FieldPhase{K}(group, alg, arrays; tables, params, substeps, dt, options, T, init = false)

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

`K` names the entry of the run context that holds the trajectory's runtime
([`phase_context`](@ref)). The field ends every MCS in its `st.site` array: after an odd
number of substeps one copy brings the scratch buffer back (`ends_in = :slot1`). With
`init = true` the phase is the masked-condition clamp of a fresh initial state (one substep
of length zero: each masked site takes its value, every other site keeps its own); `init`
from a checkpoint skips it.
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
    init::Bool
    options::Any                         # the compile options of the plans (host)
    T::Type                              # the value type of the plans
end
function FieldPhase{K}(group, alg, arrays::Tuple; tables = Pair{Int, Symbol}[], params = Symbol[], substeps,
        dt::Real, options, T::Type, init::Bool = false) where {K}
    program = Problems.group_program(group, alg)
    # the plans of value type `T`, made once per group (shared by every trajectory; the host
    # backend only decides the Float64 check here, which `options` already holds)
    masks, step = Problems.group_plans(group, alg, T, KernelAbstractions.CPU(), options)
    return FieldPhase{K, typeof(group), typeof(alg), typeof(arrays), typeof(substeps), typeof(program), typeof(step)}(
        group, alg, program, masks, step, arrays, tables, params, substeps, Float64(dt), init, options, T)
end
"""The masked-condition clamp of field phase `ph` (its at-init form)."""
field_clamp(ph::FieldPhase{K}) where {K} =
    FieldPhase{K}(ph.group, ph.alg, ph.arrays; ph.tables, ph.params, ph.substeps, ph.dt, ph.options, ph.T, init = true)

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

function _table_array(backend, ::Type{E}, v) where {E}
    a = KernelAbstractions.allocate(backend, E, length(v))
    copyto!(a, E[E(x) for x in v])
    return a
end

# the parameter values and table contents a binding depends on (copies: a table written in
# place is a change)
_bound_values(ph::FieldPhase, p) = (Any[getproperty(p, n) for n in ph.params],
                                    Any[copy(vec(collect(getproperty(p, name)))) for (_, name) in ph.tables])

# whether the phase's parameters and tables at `p` equal those of the binding `b` (no copies)
function _same_params(ph::FieldPhase, b::FieldBinding, p)
    for (k, n) in enumerate(ph.params)
        isequal(getproperty(p, n), b.pvals[k]) || return false
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
_praw(ph::FieldPhase, p) = Tuple(getproperty(p, n) for n in ph.params)

"""
    field_substeps(ph, p) -> Int

The substep count of field phase `ph` at parameters `p`: its `substeps` rule at the phase's
parameter and table values. The rule throws (an `ArgumentError`) for parameters it refuses
(negative diffusion, a coupling past the limit, a coefficient with no finite bound), so a
caller that checks before it changes anything keeps the run atomic.
"""
function field_substeps(ph::FieldPhase, p)
    n = ph.substeps(Problems.with_tables(Float64[_praw(ph, p)...], _table_values(ph, p)))
    n >= 1 || throw(ArgumentError("a field group needs at least one substep; got $n"))
    return n
end

# The runtime of a field phase bound to the state's arrays at parameters `p` (front end A on
# the shared group runtime: `ends_in = :slot1`, the field back in its `st.site` array after an
# odd count), with the step's substep count (also when `ph` is the at-init clamp, which runs
# one substep of length zero from the same launches: the binding is the step's, D-C8 item 8).
# `tables` reuses the device tables of an earlier binding when their contents are unchanged.
function _field_bind(ph::FieldPhase, st, p, backend; tables = nothing)
    s = ph.program
    arrs = _arrays(ph.arrays, st)
    bufs = [a[2] === nothing ? Any[vec(a[1])] : Any[vec(a[1]), vec(a[2])] for a in arrs]
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
        backend, options = ph.options, V = ph.T, host, fixed_time = true)
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
    # on a device the kernels of a step (its launches, the masks, the clamp at the step's start
    # and the slot-1 copies) compile on host tasks, awaited before the first enqueue
    Exec.ishost(backend) || (rt.pending = Threads.@spawn _field_compile!(backend, rt))
    return NamedTuple{(K,)}((FieldHandle(rt),))
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
    new = _field_bind(ph, st, p, backend; tables = same_tables ? rt.store.tables : nothing)
    for f in fieldnames(typeof(rt))
        setfield!(rt, f, getfield(new, f))
    end
    return rt
end

function (ph::FieldPhase{K})(st, p, ctx, key, mcs, backend) where {K}
    rt = _runtime(getfield(ctx, K))
    rt.pending === nothing || Base.invokelatest(_await!, rt)
    # the rebinding is cold host work (the substep bound, new launches): called past an
    # inference barrier, so the warm path compiles without it
    (rt.host.p === p && rt.host.arrays === _arrays(ph.arrays, st)) || Base.invokelatest(_rebind!, rt, ph, st, p, backend)
    # the at-init clamp: one substep of length zero from the step's launches
    n = ph.init ? 1 : rt.n
    Problems.advance!(rt, (Float64(mcs), mcs), n, ph.init ? 0.0 : rt.dt)
    launches = n * length(rt.steps[1].launches)
    # the masks (on a device they clamp the sites they mark; a clamp they cannot take is one
    # more kernel)
    rt.masks === nothing || (launches += length(rt.masks[1].launches) + (Exec.ishost(backend) ? 0 : length(rt.stepclamps)))
    isodd(n) && (launches += length(rt.copies))
    return launches
end

# The at-init phases of a state that is not fresh (a checkpoint restore, `Potts.anneal`'s
# per-MCS refresh): the derived refreshes without the field clamps, which hold on a fresh
# initial state only (D-145)
_derived(t::Tuple) = filter(ph -> !(ph isa FieldPhase && ph.init), t)
