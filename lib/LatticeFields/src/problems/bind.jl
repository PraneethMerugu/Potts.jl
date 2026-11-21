# Binding: a `LaunchSpec` of a step plan becomes an `Exec.Launch` (schedule/contract.jl).
# Linear bodies `body(s, S, P, G)` run through the guarded linear wrapper with `n = G.n`;
# Cartesian bodies `body(x, S, P, G)` through the Cartesian wrapper (the body guards each
# axis). The host executor runs the same bodies.

"""
    Geom(n, dims, rt)

The geometry argument `G` of a body (contract item 4): `n` sites of the launch space,
`dims` per level of the kernel, `rt` the launch-varying values `(t, dt)`, in the kernel's
value type (or a Dual of it when the time carries derivative parts). Isbits for isbits `T`.

# Fields
- `n`: the number of sites of the launch space, in the kernel's index type.
- `dims::NTuple{L, NTuple{N, Int32}}`: the site counts per axis of each level the kernel
  reads.
- `rt::NTuple{R, T}`: the launch-varying values, `rt[RT_T]` the time and `rt[RT_DT]` the
  step.

See also [`launch_geometry`](@ref).
"""
struct Geom{N, L, R, I, T}
    n::I
    dims::NTuple{L, NTuple{N, Int32}}
    rt::NTuple{R, T}
end

"""
    RT_T::Int

The slot of `G.rt` that holds the time `t` (the value is 1).
"""
const RT_T = 1

"""
    RT_DT::Int

The slot of `G.rt` that holds the step `dt` (the value is 2).
"""
const RT_DT = 2

"""
    launch_geometry(p, ck, rt; R = ck.T) -> Geom

The geometry of compiled kernel `ck` of program `p`, with `rt = (t, dt)` in `R` (the
kernel's value type; a Dual time gives a Dual `R` on the ODE path).

# Arguments
- `p`: the program (`LatticeFields.IR.Program`).
- `ck`: a compiled kernel of `p`.
- `rt`: the tuple `(t, dt)`.

# Keywords
- `R = ck.T`: the type of `G.rt`.

# Returns
- A [`Geom`](@ref).
"""
function launch_geometry(
        p::Program{N}, ck::CompiledKernel{N}, rt::NTuple{2, Real};
        R::Type = ck.T
    ) where {N}
    dims = Tuple(map(Int32, leveldims(p, lv)) for lv in ck.levels)
    n = ck.I(nsites(p, ck.space.level))
    return Geom{N, length(dims), 2, ck.I, R}(
        n, dims, (
            lanecast(R, rt[1]), lanecast(R, rt[2]),
        )
    )
end

"""
    launch_parameters(ck, Praw, c = zero(ck.T), t = 0.0) -> NTuple

The device parameter tuple of `ck` (contract item 3): the raw parameters (any `Real` eltype,
on the host) followed by the hoisted ones, all in the type of `c` (the compute element type:
the value type, or a Dual of it). Hoisted values that read the time use `t`.

# Arguments
- `ck`: a compiled kernel.
- `Praw`: the raw parameters, any iterable of `Real`s.
- `c = zero(ck.T)`: a value of the compute element type.
- `t = 0.0`: the time of hoisted values that read it.

# Returns
- The parameter tuple.
"""
function launch_parameters(ck::CompiledKernel, Praw, c = zero(ck.T), t = 0.0)
    return derive_function(ck)(Tuple(Praw), c, t, nothing)
end

"""
    bind_program(backend, p, spec, S, P, rt; R = spec.kernel.T, wrap = identity)
        -> Exec.Launch

The prebuilt launch of `spec` with arrays `S`, parameters `P` and `rt = (t, dt)` in `R`: a
static ndrange when `spec.static`, the workgroup of the spec, the Cartesian wrapper for
Cartesian bodies. `n` is `G.n`.

# Arguments
- `backend`: a KernelAbstractions backend.
- `p`: the program.
- `spec`: a launch description of a step plan (`LaunchSpec`).
- `S`: the tuple of arrays of the launch ([`launch_arrays`](@ref)).
- `P`: the parameter tuple ([`launch_parameters`](@ref)).
- `rt`: the tuple `(t, dt)`.

# Keywords
- `R = spec.kernel.T`: the type of `G.rt`.
- `wrap = identity`: a function of the kernel body that returns the body to launch.

# Returns
- An `Exec.Launch`.
"""
function bind_program(
        backend, p::Program{N}, spec::LaunchSpec{N}, S::Tuple, P::Tuple, rt;
        R::Type = spec.kernel.T, wrap::W = identity
    ) where {N, W}
    ck = spec.kernel
    G = launch_geometry(p, ck, rt; R)
    # `wrap`: a body around the kernel's (a fused clamp, group.jl)
    body = wrap(body_function(ck))
    if ck.strategy == :cartesian
        return Exec.Launch(
            backend, body, (S, P, G), spec.ndrange; cartesian = true,
            workgroupsize = spec.workgroup, static = spec.static
        )
    end
    return Exec.Launch(
        backend, body, (S, P, G), Int(G.n);
        workgroupsize = only(spec.workgroup), static = spec.static
    )
end

"""
    rebind(l::Exec.Launch, args) -> Exec.Launch

`l` with new body arguments `args = (S, P, G)` and the same kernel object (no compile, no
allocation): the launch-varying values change, the kernel does not.

# Arguments
- `l`: an `Exec.Launch`.
- `args`: the new body arguments.

# Returns
- A new `Exec.Launch`.
"""
function rebind(l::Exec.Launch{K, WG}, args::A) where {K, WG, A <: Tuple}
    body, _, n = l.params
    params = (body, args, n)
    return Exec.Launch{K, WG, typeof(params)}(l.kernel, params, l.ndrange)
end

"""
    retime(l::Exec.Launch, rt) -> Exec.Launch

`l` with `G.rt = rt` (converted to the type of `G.rt`).

# Arguments
- `l`: an `Exec.Launch` whose arguments are `(S, P, G)`.
- `rt`: the tuple `(t, dt)`.

# Returns
- A new `Exec.Launch` ([`rebind`](@ref)).
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

# Arguments
- `n`: the number of calls.

# Returns
- The cached RuntimeGeneratedFunction for `n`.
"""
function each(n::Integer)
    return lock(_EACH_LOCK) do
        get!(_EACH, Int(n)) do
            calls = [:(getfield(t, $i)(a)) for i in 1:n]
            rgf(
                :(
                    function (t, a)
                        $(calls...)
                        return nothing
                    end
                )
            )
        end
    end
end
