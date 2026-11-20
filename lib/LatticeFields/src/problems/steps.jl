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
A prebuilt launch whose parameters are derived again at each launch (a hoisted value reads the
time, or the kernel reads the clock slot): `l(rt)` derives `P` on the host at `t = rt[1]` and,
with `rt = (t, dt, k)`, with the step index `k` in the clock slot (no allocation), sets `G.rt`
and enqueues it.
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
    rebind(x.launch, (S, x.derive(x.Praw, x.c, rt[1], k), typeof(G)(G.n, G.dims, (rt[1], rt[2]))))()
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
"""
struct BoundStep{L <: Tuple, W}
    launches::L
    walk::W
end
function BoundStep(backend, p::Program, sp::StepPlan, st::FieldStore, Praw; cur = st.cur,
        c = nothing, fuse = nothing)
    P0 = Tuple(Praw)
    ls = Tuple(begin
                   ck = l.kernel
            # the parameters in the kernel's compute type (its `compute_type`), wrapped
                   # like `c` (a Dual of it under Dual parameters)
            cc = c === nothing ? zero(ck.T) : zero(withvaltype(typeof(c), value_type(ck.T)))
                   S = launch_arrays(st, l, cur)
                   f = fuse === nothing ? nothing : fuse(l, cur)
            b = f === nothing ? bind_program(backend, p, l, S, launch_parameters(ck, P0, cc), (0, 0)) :
                bind_program(backend, p, l, (S..., f[1]), launch_parameters(ck, P0, cc), (0, 0); wrap = f[2])
                   ck.timed ? TimedDerived(b, derive_function(ck), P0, cc) : Timed(b)
               end
    for l in sp.launches)
    return BoundStep(ls, each(length(ls)))
end
(bs::BoundStep)(rt) = bs.walk(bs.launches, rt)

"""
    compile!(backend, bs::BoundStep)

Compile every launch of `bs` before the first enqueue (host tasks, `Exec.compile_all!`).
"""
function compile!(backend, bs::BoundStep)
    Exec.compile_all!(backend, [x.launch for x in bs.launches])
end

"""
    swap!(st, sp)

The host slot swaps after a step of `sp` (no copy, no wait).
"""
function swap!(st::FieldStore, sp::StepPlan)
    (foreach(f -> st.cur[f] = 3 - st.cur[f], sp.swaps); st)
end

"""
    run_step!(backend, p, sp, st, Praw; rt = (0, 0), c = nothing)

Bind, run and swap one step (cold: binds on every call; tests and one-off steps). The
warm path prebuilds [`BoundStep`](@ref)s.
"""
function run_step!(backend, p::Program, sp::StepPlan, st::FieldStore, Praw; rt = (0, 0),
        c = nothing)
    bs = BoundStep(backend, p, sp, st, Praw; c)
    bs(map(Float64, rt))
    return swap!(st, sp)
end
