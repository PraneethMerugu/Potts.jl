# Prebuilt steps: the launches of one step plan, bound once to a store's arrays at given
# current slots, run warm with only `(t, dt)` changing. A step whose two-buffer fields all
# swap alternates between two such bindings (even and odd parity).

"""
A prebuilt launch whose `G.rt` is set at each call: `l(rt)` enqueues it. `rt = (t, dt)`, or
`(t, dt, k)` with the clock's step index `k`, which this launch does not read.
"""
struct Timed{L}
    launch::L
end
(x::Timed)(rt) = (retime(x.launch, (rt[1], rt[2]))(); nothing)

"""
A prebuilt launch whose parameters are derived again at each launch (a hoisted value reads
the time, or the kernel reads the clock slot): `l(rt)` derives `P` on the host at
`t = rt[1]` and, with `rt = (t, dt, k)`, with the step index `k` in the clock slot (no
allocation), sets `G.rt` and enqueues it.
"""
struct TimedDerived{L, D, P, C}
    launch::L
    derive::D
    Praw::P
    c::C
end
function (x::TimedDerived)(rt)
    S, _, G = x.launch.params[2]
    k = length(rt) >= 3 ? rt[3] : nothing
    rebind(
        x.launch, (
            S, x.derive(x.Praw, x.c, rt[1], k), typeof(G)(G.n, G.dims, (rt[1], rt[2])),
        )
    )()
    return nothing
end

"""
    BoundStep(backend, p, sp, st, Praw; cur = st.cur, c = nothing, fuse = nothing)

The launches of step plan `sp` on store `st` with the current slots `cur`, parameters
`Praw` (raw, host, any `Real` eltype) in the compute element type of `c` (default: each
kernel's value type), and `rt = (t, dt)`. `bs(rt)` enqueues them in order (no sync, no
allocation on the host executor). `fuse(spec, cur)` may return `(lane, wrap)` for a launch:
its arrays gain the lane `lane` and its body is `wrap(body)` (the clamp fused into the mask
launch on a device, group.jl); `nothing` leaves the launch as planned.

# Arguments
- `backend`: a KernelAbstractions backend.
- `p`: the program.
- `sp`: a step plan (`StepPlan`).
- `st`: the [`FieldStore`](@ref) of `p`.
- `Praw`: the raw parameters.

# Keywords
- `cur = st.cur`: the current slot of each field.
- `c = nothing`: a value of the compute element type, or `nothing`.
- `fuse = nothing`: the launch fusion hook described above.

# Returns
- A `BoundStep`; `bs(rt)` returns `nothing`.

See also [`compile!`](@ref), [`run_step!`](@ref).
"""
struct BoundStep{L <: Tuple, W}
    launches::L
    walk::W
end
function BoundStep(
        backend, p::Program, sp::StepPlan, st::FieldStore, Praw; cur = st.cur,
        c = nothing, fuse = nothing
    )
    P0 = Tuple(Praw)
    sp = _at_budget(backend, p, sp, st, P0, cur, c, fuse)
    ls = Tuple(
        begin
            ck = l.kernel
            cc = _launch_c(ck, c)
            b = _bind_launch(backend, p, l, st, cur, fuse, launch_parameters(ck, P0, cc))
            ck.timed ? TimedDerived(b, derive_function(ck), P0, cc) : Timed(b)
        end
            for l in sp.launches
    )
    return BoundStep(ls, each(length(ls)))
end

# the parameters of a launch are in the kernel's compute type (its `compute_type`), wrapped
# like `c` (a Dual of it under Dual parameters)
function _launch_c(ck, c)
    return c === nothing ? zero(ck.T) : zero(withvaltype(typeof(c), value_type(ck.T)))
end

# the launch of `l` with parameters `P`, its arrays at the slots `cur`
function _bind_launch(backend, p, l, st, cur, fuse::F, P) where {F}
    S = launch_arrays(st, l, cur)
    f = fuse === nothing ? nothing : fuse(l, cur)
    return if f === nothing
        bind_program(backend, p, l, S, P, (0, 0))
    else
        bind_program(backend, p, l, (S..., f[1]), P, (0, 0); wrap = f[2])
    end
end

# The plan of `sp` at the backend's kernel-argument budget, its launches measured as this
# binding binds them: the parameters as the tuple the derive function returns (the raw and
# the hoisted values, all in the compute element type), so no derive function runs. The
# argument types decide the sizes, so the plan is kept per those types.
function _at_budget(backend, p, sp, st, P0, cur, c, fuse::F) where {F}
    budget = Exec.kernel_argument_bytes(backend)
    budget === nothing && return sp
    function arguments(l)
        ck = l.kernel
        cc = _launch_c(ck, c)
        P = ntuple(_ -> cc, ck.nparams + length(ck.derived))
        return Exec.launch_argument_bytes(_bind_launch(backend, p, l, st, cur, fuse, P))
    end
    signature = (
        typeof(backend), _argument_types(st), typeof(P0), typeof(c), F, fuse_key(fuse),
    )
    return bound_plan(sp, budget, signature, arguments)
end

# what besides the argument types decides the launches a fuse hook changes
fuse_key(fuse) = nothing

# the types of a store's arrays and tables
function _argument_types(st::FieldStore)
    return (
        Tuple(Tuple(map(typeof, b)) for b in st.bufs), Tuple(map(typeof, st.tables)),
    )
end
(bs::BoundStep)(rt) = bs.walk(bs.launches, rt)

"""
    compile!(backend, bs::BoundStep)

Compile every launch of `bs` before the first enqueue (host tasks, `Exec.compile_all!`).

# Arguments
- `backend`: a KernelAbstractions backend.
- `bs`: a [`BoundStep`](@ref).

# Returns
- `nothing`.
"""
function compile!(backend, bs::BoundStep)
    return Exec.compile_all!(backend, [x.launch for x in bs.launches])
end

"""
    swap!(st, sp)

The host slot swaps after a step of `sp` (no copy, no wait).

# Arguments
- `st`: a [`FieldStore`](@ref).
- `sp`: the step plan whose two-buffer fields swap.

# Returns
- `st`.
"""
function swap!(st::FieldStore, sp::StepPlan)
    for f in sp.swaps
        st.cur[f] = 3 - st.cur[f]
    end
    return st
end

"""
    run_step!(backend, p, sp, st, Praw; rt = (0, 0), c = nothing)

Bind, run and swap one step (cold: binds on every call; tests and one-off steps). The
warm path prebuilds [`BoundStep`](@ref)s.

# Arguments
- `backend`: a KernelAbstractions backend.
- `p`: the program.
- `sp`: a step plan.
- `st`: the [`FieldStore`](@ref) of `p`.
- `Praw`: the raw parameters.

# Keywords
- `rt = (0, 0)`: the tuple `(t, dt)`, converted to `Float64`.
- `c = nothing`: a value of the compute element type, or `nothing`.

# Returns
- `st`, after the swap.
"""
function run_step!(
        backend, p::Program, sp::StepPlan, st::FieldStore, Praw; rt = (0, 0),
        c = nothing
    )
    bs = BoundStep(backend, p, sp, st, Praw; c)
    bs(map(Float64, rt))
    return swap!(st, sp)
end
