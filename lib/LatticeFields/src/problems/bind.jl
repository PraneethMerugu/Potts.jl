# Binding: a `LaunchSpec` of a step plan becomes an `Exec.Launch` (schedule/contract.jl).
# Linear bodies `body(s, S, P, G)` run through the guarded linear wrapper with `n = G.n`;
# Cartesian bodies `body(x, S, P, G)` through the Cartesian wrapper (the body guards each
# axis). The host executor runs the same bodies.

"""
    Geom(n, dims, rt)

The geometry argument `G` of a body (contract item 4): `n` sites of the launch space,
`dims` per level of the kernel, `rt` the launch-varying values `(t, dt)`, in the kernel's
value type (or a Dual of it when the time carries derivative parts). Isbits for isbits `T`.
"""
struct Geom{N, L, R, I, T}
    n::I
    dims::NTuple{L, NTuple{N, Int32}}
    rt::NTuple{R, T}
end

"""
    RT_T

The slot of `G.rt` that holds the time `t`.
"""
const RT_T = 1

"""
    RT_DT

The slot of `G.rt` that holds the step `dt`.
"""
const RT_DT = 2

"""
    launch_geometry(p, ck, rt; R = ck.T) -> Geom

The geometry of compiled kernel `ck` of program `p`, with `rt = (t, dt)` in `R` (the
kernel's value type; a Dual time gives a Dual `R` on the ODE path).
"""
function launch_geometry(p::Program{N}, ck::CompiledKernel{N}, rt::NTuple{2, Real};
        R::Type = ck.T) where {N}
    dims = Tuple(map(Int32, leveldims(p, lv)) for lv in ck.levels)
    n = ck.I(nsites(p, ck.space.level))
    return Geom{N, length(dims), 2, ck.I, R}(n, dims, (lanecast(R, rt[1]), lanecast(R, rt[2])))
end

"""
    launch_parameters(ck, Praw, c = zero(ck.T), t = 0.0) -> NTuple

The device parameter tuple of `ck` (contract item 3): the raw parameters (any `Real` eltype,
on the host) followed by the hoisted ones, all in the type of `c` (the compute element type:
the value type, or a Dual of it). Hoisted values that read the time use `t`.
"""
function launch_parameters(ck::CompiledKernel, Praw, c = zero(ck.T), t = 0.0)
    return derive_function(ck)(Tuple(Praw), c, t, nothing)
end

"""
    bind_program(backend, p, spec, S, P, rt; R = spec.kernel.T) -> Exec.Launch

The prebuilt launch of `spec` with arrays `S`, parameters `P` and `rt = (t, dt)` in `R`: a static
ndrange when `spec.static`, the workgroup of the spec, the Cartesian wrapper for Cartesian
bodies. `n` is `G.n`.
"""
function bind_program(
        backend, p::Program{N}, spec::LaunchSpec{N}, S::Tuple, P::Tuple, rt;
        R::Type = spec.kernel.T, wrap::W = identity) where {N, W}
    ck = spec.kernel
    G = launch_geometry(p, ck, rt; R)
    body = wrap(body_function(ck))          # `wrap`: a body around the kernel's (a fused clamp, group.jl)
    if ck.strategy == :cartesian
        return Exec.Launch(backend, body, (S, P, G), spec.ndrange; cartesian = true,
            workgroupsize = spec.workgroup, static = spec.static)
    end
    return Exec.Launch(backend, body, (S, P, G), Int(G.n);
        workgroupsize = only(spec.workgroup), static = spec.static)
end

"""
    rebind(l::Exec.Launch, args) -> Exec.Launch

`l` with new body arguments `args = (S, P, G)` and the same kernel object (no compile, no
allocation): the launch-varying values change, the kernel does not.
"""
function rebind(l::Exec.Launch{K, WG}, args::A) where {K, WG, A <: Tuple}
    body, _, n = l.params
    params = (body, args, n)
    return Exec.Launch{K, WG, typeof(params)}(l.kernel, params, l.ndrange)
end

"""
    retime(l::Exec.Launch, rt) -> Exec.Launch

`l` with `G.rt = rt` (converted to the type of `G.rt`).
"""
function retime(l::Exec.Launch, rt::NTuple{2, Real})
    S, P, G = l.params[2]
    return rebind(l, (S, P, typeof(G)(G.n, G.dims, rt)))
end

const _EACH = Dict{Int, Any}()
const _EACH_LOCK = ReentrantLock()

"""
    each(n)

The RuntimeGeneratedFunction `(t, a) -> (t[1](a); …; t[n](a); nothing)` (cached by
`n`): one call per element of a heterogeneous tuple, unrolled, so a walk over more than 32
callables neither recurses nor allocates (as `Exec.walker`, with arguments).
"""
function each(n::Integer)
    return lock(_EACH_LOCK) do
        get!(_EACH, Int(n)) do
            calls = [:(getfield(t, $i)(a)) for i in 1:n]
            rgf(:(function (t, a)
                $(calls...)
                return nothing
            end))
        end
    end
end
