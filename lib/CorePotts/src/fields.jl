# Continuous fields on the lattice (v3 §7, cutover C8). A field is a site array of floats in
# `st.site`; its equations are lowered by the field compiler (LatticePDE → LatticeFields) into
# a step plan, and `FieldPhase` runs that plan inside the MCS: the CPM keeps reading the field
# from `st.site` as before. The arrays of the plan (the field and its scratch, the inputs the
# CPM fills, the masks) are site arrays of the state; the bound launches of one trajectory live
# in its run context (`ctx`), built when an integrator is created (`phase_context`).

"""Kind of the cell owning site `i` (`0` for the medium)."""
@inline owner_kind(st, i) = (c = @inbounds st.σ[i]; c == 0 ? Int32(0) : @inbounds st.cell.kind[c])

"""
    FieldPhase{K}(program, masks, step, arrays; tables, params, substeps, dt, init = false)

A group of fields stepped by explicit Euler over one MCS of length `dt`, in `n` substeps of
`dt / n`: `program` is the semantic LatticeFields `Program` of the group, `step` the step plan
of one substep (each state field written into its scratch buffer, the buffers swapped) and
`masks` the plan of the mask kernels (run once per MCS, before the substeps: the masks follow
σ). `arrays[f]` binds program field `f` to state arrays: `(Part, nothing)` for a one-buffer
field (an input or a mask), `(Part, Part)` for a state field and its scratch. `tables` binds
table ids to kind tables of the parameters and `params` the parameter slots to parameter
names. `substeps(praw)` is the substep count at raw parameter values `praw` (a host
function, evaluated when the parameters change, never per MCS).

`K` names the entry of the run context that holds the trajectory's bound launches
([`phase_context`](@ref)). The field ends every MCS in its `st.site` array: after an odd
number of substeps one copy brings the scratch buffer back. With `init = true` the phase is
the masked-condition clamp of a fresh initial state (one substep of length zero: each masked
site takes its value, every other site keeps its own); `init` from a checkpoint skips it.
"""
struct FieldPhase{K, A, F, PR, SP}
    program::PR
    masks::SP
    step::SP
    arrays::A
    tables::Vector{Pair{Int, Symbol}}
    params::Vector{Symbol}
    substeps::F
    dt::Float64
    init::Bool
end
function FieldPhase{K}(program, masks, step, arrays::Tuple; tables = Pair{Int, Symbol}[],
        params = Symbol[], substeps, dt::Real, init::Bool = false) where {K}
    return FieldPhase{K, typeof(arrays), typeof(substeps), typeof(program), typeof(step)}(program, masks, step,
        arrays, tables, params, substeps, Float64(dt), init)
end
"""The masked-condition clamp of field phase `ph` (its at-init form)."""
field_clamp(ph::FieldPhase{K}) where {K} =
    FieldPhase{K}(ph.program, ph.masks, ph.step, ph.arrays; ph.tables, ph.params, ph.substeps, ph.dt, init = true)

"""
The bound launches of one field phase for one trajectory: the store over the state arrays,
the mask plan, the substep plan at both slot parities, the parameters they were bound with,
the substep count `n` and length `h`, and the `(field, scratch)` pairs copied back after an
odd count. Rebound when the parameters or the state arrays change. On a device, `pending` is
the host task compiling the launches (started when the integrator is created, awaited at the
phase's first run), so the field kernels compile while the rest of `init` and the first MCS
compile theirs (v3 §4.4: host-parallel compile).
"""
mutable struct FieldRuntime{S, M, B, P, A, C}
    store::S
    masks::M
    even::B
    odd::B
    p::P
    arrays::A
    n::Int
    h::Float64
    copies::C
    pending::Union{Nothing, Task}
    pvals::Vector{Any}                  # the parameter and table values the launches were bound with
    tvals::Vector{Any}
end
# device kernels never see the runtime (it is host-side launch state in the run context)
Adapt.adapt_structure(to, ::FieldRuntime) = nothing

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

# whether the phase's parameters and tables at `p` equal those of the binding (no copies)
function _same_params(ph::FieldPhase, rt, p)
    for (k, n) in enumerate(ph.params)
        isequal(getproperty(p, n), rt.pvals[k]) || return false
    end
    return true
end
function _same_tables(ph::FieldPhase, rt, p)
    for (k, (_, name)) in enumerate(ph.tables)
        t, v = getproperty(p, name), rt.tvals[k]
        t isa Array || (t = collect(t))             # a device table: read on the host
        length(t) == length(v) || return false
        for (x, y) in zip(t, v)
            isequal(x, y) || return false
        end
    end
    return true
end

# The launches of a field phase bound to the state's arrays at parameters `p`, with the step's
# substep count and length (also when `ph` is the at-init clamp, which runs one substep of
# length zero from the same launches: the binding is the step's, D-C8 item 8). `tables`
# reuses the device tables of an earlier binding when their contents are unchanged.
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
    praw = Tuple(getproperty(p, n) for n in ph.params)
    n = ph.substeps(Float64[praw...])
    n >= 1 || throw(ArgumentError("a field group needs at least one substep; got $n"))
    odd = [length(b) == 2 ? 2 : 1 for b in bufs]
    even = Problems.BoundStep(backend, s, ph.step, store, praw; cur = ones(Int, length(bufs)))
    oddb = Problems.BoundStep(backend, s, ph.step, store, praw; cur = odd)
    masks = isempty(ph.masks.launches) ? nothing : Problems.BoundStep(backend, s, ph.masks, store, praw)
    copies = Tuple((a[1], a[2]) for a in arrs if a[2] !== nothing)
    return store, masks, even, oddb, arrs, n, ph.dt / n, copies
end

"""
    phase_context(phase, st, p, backend) -> NamedTuple

The run-context entries a phase needs for one trajectory, built once when an integrator is
created (after the state and parameters are on `backend`): a [`FieldPhase`](@ref) binds its
launches to the state's arrays and compiles them. Other phases need none (`(;)`).
"""
phase_context(ph, st, p, backend) = (;)
function phase_context(ph::FieldPhase{K}, st, p, backend) where {K}
    ph.init && return (;)
    store, masks, even, odd, arrs, n, h, copies = _field_bind(ph, st, p, backend)
    # on a device the launches compile on host tasks, awaited before the first enqueue
    pending = Exec.ishost(backend) ? nothing : Threads.@spawn _field_compile!(backend, even, masks)
    rt = FieldRuntime(store, masks, even, odd, p, arrs, n, h, copies, pending, _bound_values(ph, p)...)
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

# A test hook: an event the field compile tasks wait on before compiling (`nothing`: none),
# so a test can act while a compile is certainly pending
const _COMPILE_HOLD = Ref{Union{Nothing, Base.Event}}(nothing)
function _field_compile!(backend, even, masks)
    hold = _COMPILE_HOLD[]
    hold === nothing || wait(hold)
    return Problems.compile!(backend, masks === nothing ? even : _Both(even, masks))
end
# one compile set of the substep and the mask launches (`Problems.compile!` takes one step)
struct _Both{A, B}
    a::A
    b::B
end
Problems.compile!(backend, s::_Both) = Exec.compile_all!(backend,
    Any[[x.launch for x in s.a.launches]; [x.launch for x in s.b.launches]])

# wait for the compile task of `rt` (cold: the first run after `init`); a failed compile
# rethrows here, before anything is enqueued
function _await!(rt::FieldRuntime)
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
# length zero), so the clamp of `reinit!` never leaves the step with the clamp's count.
function _rebind!(rt::FieldRuntime, ph::FieldPhase, st, p, backend)
    _await!(rt)
    same_arrays = rt.arrays === _arrays(ph.arrays, st)
    same_tables = _same_tables(ph, rt, p)
    if same_arrays && same_tables && _same_params(ph, rt, p)
        rt.p = p
        return rt
    end
    pv, tv = _bound_values(ph, p)
    store, masks, even, odd, arrs, n, h, copies =
        _field_bind(ph, st, p, backend; tables = same_tables ? rt.store.tables : nothing)
    rt.store, rt.masks, rt.even, rt.odd, rt.p, rt.arrays, rt.n, rt.h, rt.copies, rt.pvals, rt.tvals =
        store, masks, even, odd, p, arrs, n, h, copies, pv, tv
    return rt
end

function (ph::FieldPhase{K})(st, p, ctx, key, mcs, backend) where {K}
    rt = _runtime(getfield(ctx, K))
    rt.pending === nothing || Base.invokelatest(_await!, rt)
    # the rebinding is cold host work (the substep bound, new launches): called past an
    # inference barrier, so the warm path compiles without it
    (rt.p === p && rt.arrays === _arrays(ph.arrays, st)) || Base.invokelatest(_rebind!, rt, ph, st, p, backend)
    rtime = (Float64(mcs), ph.init ? 0.0 : rt.h)
    launches = 0
    if rt.masks !== nothing
        rt.masks(rtime)
        launches += length(rt.masks.launches)
    end
    n = ph.init ? 1 : rt.n
    for k in 1:n
        isodd(k) ? rt.even(rtime) : rt.odd(rtime)
    end
    launches += n * length(rt.even.launches)
    if isodd(n)
        for (c, cn) in rt.copies
            _device_copy!(backend, c, cn)            # a kernel: no GPU wait (P6.0v8)
        end
        launches += length(rt.copies)
    end
    return launches
end

# The at-init phases of a state that is not fresh (a checkpoint restore, `Potts.anneal`'s
# per-MCS refresh): the derived refreshes without the field clamps, which hold on a fresh
# initial state only (D-145)
_derived(t::Tuple) = filter(ph -> !(ph isa FieldPhase && ph.init), t)
