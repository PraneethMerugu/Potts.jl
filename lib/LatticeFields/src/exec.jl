"""
    LatticeFields.Exec

The execution layer (v3 §4.4, §9.1): one host executor for every CPU kernel and one generic
device wrapper for every device kernel. A kernel is a body `body(i, args...)` run for
`i in 1:n`.

- **Host executor** ([`host_launch!`](@ref)): a plain loop, or a threaded chunked loop for
  large `n`. The KernelAbstractions CPU backend never runs production work: on KA 0.10 it is
  PoCL (5 µs per launch, SPIR-V semantics, invisible to JET and AllocCheck).
- **Device wrapper** (`_kernel!`): `unsafe_indices = true` with an `if i <= n` guard. KA 0.9
  refuses `return` inside a kernel; KA 0.10 accepts both.
- **Launches**: [`launch!`](@ref) for a dynamic launch from a runtime `n`;
  [`Launch`](@ref) for a prebuilt, type-stable launch (static ndrange for bodies that run at
  one size); [`Plan`](@ref) for a zero-allocation walk over a tuple of launches.
- **Compile before enqueue**: [`compile!`](@ref) compiles a kernel by a launch with `n = 0`
  (no work item passes the guard); [`compile_all!`](@ref) compiles a set on host tasks.
- **Capabilities and policy**: [`supports`](@ref) (what the hardware runs),
  [`default_float`](@ref) (the float type CorePotts emits by default), [`ishost`](@ref).
"""
module Exec

using KernelAbstractions: KernelAbstractions, @kernel, @index
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, @RuntimeGeneratedFunction
using Polyester: @batch

RuntimeGeneratedFunctions.init(@__MODULE__)

public HOST_GRAIN, ishost, supports, default_float, register_float64!, float64_registered, FLOAT64_KERNELS, host_launch!, launch!, compile!, compile_all!, Launch, Plan, walker

# ---------------------------------------------------------------------------------------
# Capabilities

"""
    ishost(backend) -> Bool

Whether kernels on `backend` run on the host executor (host memory, native Julia): true for
the KernelAbstractions CPU backend, false for every device backend.
"""
ishost(::KernelAbstractions.CPU) = true
ishost(backend) = false

"""
    supports(backend, ::Type{T}) -> Bool

Capability: can kernels on `backend` compute in and store number type `T`? The host
executor runs every type. A device runs `Float32`, and `Float64` where the hardware has it
(`KernelAbstractions.supports_float64`: true on ROCm and CUDA, false on Metal). Callers ask
only when a choice depends on the hardware (a Float64 solver group, an explicit Float64
problem); the type device code gets by default is [`default_float`](@ref).
"""
supports(backend, ::Type{T}) where {T} =
    ishost(backend) || T === Float32 || (T === Float64 && KernelAbstractions.supports_float64(backend))

"""
    default_float(backend) -> Type

Policy: the float type of code emitted for `backend` when the caller names none. `Float64`
on the host executor, `Float32` on every device: default device code stays `Float32`, so it
runs unchanged on backends without doubles (Metal) and gives the same results on every
device (D-157 scans production Float32 paths for doubles). This is not a query of the
hardware; ask [`supports`](@ref) for that.
"""
default_float(backend) = ishost(backend) ? Float64 : Float32

"""
    register_float64!(parts::String...)

The D-157 carve-out (F3 design §3.8, R-F3c): a kernel whose Float64 its user declared (a
group's `compute_T` or `solver_T` of Float64, or a field's `lattice_storage = Float64`, on a
device whose default float is Float32) is registered by the parts of its signature text: a
kernel signature that holds every part is skipped by the no-`double` scan of the device test
suites, which still flags every other kernel. [`float64_registered`](@ref) asks.
"""
function register_float64!(parts::String...)
    lock(_FLOAT64_LOCK) do
        push!(FLOAT64_KERNELS, collect(String, parts))
    end
    return nothing
end
"""The registry of [`register_float64!`](@ref): one vector of signature parts per entry."""
const FLOAT64_KERNELS = Set{Vector{String}}()
const _FLOAT64_LOCK = ReentrantLock()
"""
    float64_registered(signature::AbstractString) -> Bool

Whether a kernel signature text holds every part of a [`register_float64!`](@ref) entry.
"""
float64_registered(sig::AbstractString) =
    lock(() -> any(e -> all(q -> occursin(q, sig), e), FLOAT64_KERNELS), _FLOAT64_LOCK)

# ---------------------------------------------------------------------------------------
# Host executor

"""
Minimum number of work items per host thread. A launch of at most `HOST_GRAIN` items, or
any launch with one thread, is a plain loop (threaded launches of about 1000 items were 6×
slower than the loop).
"""
const HOST_GRAIN = 8192

"""
    host_launch!(body, n, args)

Run `body(i, args...)` for `i in 1:n` on the host: a plain loop when `n ≤ HOST_GRAIN` or
with one thread, else `ceil(n / chunk)` chunks of `chunk = max(cld(n, nthreads), HOST_GRAIN)`
items on Polyester's persistent workers (`@batch`: no task is created, so a warm launch
allocates nothing; nested under busy workers, e.g. inside `EnsembleThreads`, the chunks run
serially). Under `@batch`, Polyester passes top-level `Array`s in `args` as `PtrArray`s, so a
body compiles for both array types. Returns `nothing`.
"""
function host_launch!(body::B, n::Integer, args::A) where {B, A}
    nt = Threads.nthreads()
    chunk = max(cld(n, nt), min(n, HOST_GRAIN))
    if chunk >= n
        _host_loop!(body, n, args)
    else
        _host_threaded!(body, n, chunk, args)
    end
    return nothing
end

# the plain loop (AllocCheck gates it: it allocates nothing)
function _host_loop!(body::B, n::Integer, args::A) where {B, A}
    for i in 1:n
        body(i, args...)
    end
    return nothing
end

@noinline function _host_threaded!(body::B, n::Integer, chunk::Integer, args::A) where {B, A}
    nc = cld(n, chunk)
    @batch per = thread for c in 1:nc
        _host_chunk!(body, n, chunk, c, args)
    end
    return nothing
end
function _host_chunk!(body::B, n::Integer, chunk::Integer, c::Integer, args::A) where {B, A}
    for i in ((c - 1) * chunk + 1):min(c * chunk, n)
        body(i, args...)
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Device wrapper

# The one generic device kernel. `unsafe_indices = true`: no implicit bounds mask; the guard
# is the `if` (KA 0.9 refuses `return` in a kernel). Work items past `n` (the last
# workgroup's padding, or every item of a compile launch with `n = 0`) do nothing.
@kernel unsafe_indices = true function _kernel!(body, args, n)
    i = @index(Global, Linear)
    if i <= n
        body(i, args...)
    end
end

"""
    launch!(backend, body, n, args)

Run `body(i, args...)` for `i in 1:n` on `backend`, without synchronizing: the host
executor on the CPU, else the device wrapper with a dynamic ndrange and the backend's
workgroup size (one compile per body and argument types, whatever `n`). Nothing runs for
`n ≤ 0`. Returns `nothing`.
"""
function launch!(backend, body::B, n::Integer, args::A) where {B, A}
    if ishost(backend)
        host_launch!(body, n, args)
    elseif n > 0
        _kernel!(backend)(body, args, Int(n); ndrange = Int(n))
    end
    return nothing
end

"""
    compile!(backend, body, args)

Compile the kernel that [`launch!`](@ref)`(backend, body, n, args)` runs, by a launch of one
work item with `n = 0` (it passes no guard, so nothing is written). The kernel type does not
depend on the ndrange of a dynamic launch, so the later launch reuses this compile. A
launch over an empty ndrange is not used: KA 0.10 returns before compiling it. Nothing on
the host executor. Returns `nothing`; does not synchronize.
"""
function compile!(backend, body::B, args::A) where {B, A}
    ishost(backend) && return nothing
    _kernel!(backend)(body, args, 0; ndrange = 1, workgroupsize = 1)
    return nothing
end

# ---------------------------------------------------------------------------------------
# Prebuilt launches

"""The host executor as a `Launch` kernel."""
struct HostExec end

"""
    Launch(backend, body, args, n; static::Bool, workgroupsize = 256)

A prebuilt launch of `body(i, args...)` for `i in 1:n`, built once at plan time and called
with no arguments: `l()` enqueues it (does not synchronize). On a device it holds the kernel
object of the generic wrapper with a static workgroup size `WG` and, with `static = true`,
a static ndrange (`n` rounded up to a multiple of `WG`). On KA 0.9 a static ndrange saves
1.6–1.8 µs and about 900 B per launch (pass 3), but each distinct ndrange is its own kernel
type, so its own compile (`static` has no default: the caller decides): use it for bodies that run at one size, and `static = false` for
bodies launched at several sizes. On the host the launch is [`host_launch!`](@ref).

Type parameters: `K` the kernel object (or the host executor), `WG` the workgroup size (0 on
the host), `NP` the launch tuple `(body, args, n)`.
"""
struct Launch{K, WG, NP <: Tuple{Any, Tuple, Union{Int, Tuple}}}
    kernel::K
    params::NP
    ndrange::Int        # the dynamic linear ndrange; 0 for a static one (in the kernel type)
end

# a linear launch carries `n::Int`, a Cartesian one its ndrange `NTuple{N, Int}`
const LinearLaunch{K, WG} = Launch{K, WG, <:Tuple{Any, Tuple, Int}}
const CartesianLaunch{K, WG} = Launch{K, WG, <:Tuple{Any, Tuple, Tuple}}

# The Cartesian device kernel (v3 §4.4, the C5 contract): `body(x, args...)` with
# `x::NTuple{N, Int}` 1-based; the body guards every axis itself (padded items are no-ops).
# `live = false` is the compile launch: no item calls the body.
@kernel unsafe_indices = true function _kernel_cart!(body, args, live)
    x = @index(Global, NTuple)
    if live
        body(x, args...)
    end
end

function Launch(backend, body::B, args::A, n::Integer; static::Bool, workgroupsize::Integer = 256) where {B, A <: Tuple}
    n >= 0 || throw(ArgumentError("Launch: n = $n < 0"))
    params = (body, args, Int(n))
    ishost(backend) && return Launch{HostExec, 0, typeof(params)}(HostExec(), params, 0)
    wg = Int(workgroupsize)
    wg >= 1 || throw(ArgumentError("Launch: workgroupsize = $wg < 1"))
    nd = max(cld(Int(n), wg), 1) * wg
    k = static ? _kernel!(backend, wg, nd) : _kernel!(backend, wg)
    return Launch{typeof(k), wg, typeof(params)}(k, params, static ? 0 : nd)
end

"""
    Launch(backend, body, args, ndrange::Tuple; static::Bool, workgroupsize, cartesian)

The tuple form of the Schedule contract (`spec.ndrange`, `spec.workgroup`, `spec.static`).
A 1-tuple without `cartesian = true` is the linear launch of `n = ndrange[1]`
(`body(s, S, P, G)` with `args = (S, P, G)` and `n = G.n`, guarded by `s <= n`). Otherwise
the launch is Cartesian: `body(x, args...)` for `x` over the ndrange (padded up to a
multiple of the workgroup per axis on a device; the body guards every axis), a plain
column-major loop over `CartesianIndices(ndrange)` on the host.
"""
function Launch(backend, body::B, args::A, ndrange::NTuple{N, Integer};
        workgroupsize::Union{Integer, NTuple{N, Integer}} = N == 1 ? 256 : (64, ntuple(_ -> 1, N - 1)...),
        static::Bool, cartesian::Bool = N > 1) where {B, A <: Tuple, N}
    cartesian || return Launch(backend, body, args, only(ndrange); workgroupsize = only(workgroupsize), static)
    all(>=(0), ndrange) || throw(ArgumentError("Launch: ndrange $ndrange has a negative axis"))
    nd = map(Int, ndrange)
    params = (body, args, nd)
    ishost(backend) && return Launch{HostExec, 0, typeof(params)}(HostExec(), params, 0)
    wg = map(Int, workgroupsize isa Integer ? (workgroupsize, ntuple(_ -> 1, N - 1)...) : workgroupsize)
    all(>=(1), wg) || throw(ArgumentError("Launch: workgroupsize = $wg has an axis < 1"))
    pad = map((n, w) -> max(cld(n, w), 1) * w, nd, wg)
    static || throw(ArgumentError("Launch: a Cartesian launch takes a static ndrange in this version"))
    k = _kernel_cart!(backend, wg, pad)
    return Launch{typeof(k), wg, typeof(params)}(k, params, 0)
end

function (l::LinearLaunch{HostExec})()
    body, args, n = l.params
    host_launch!(body, n, args)
    return nothing
end
function (l::CartesianLaunch{HostExec})()
    body, args, nd = l.params
    nt = Threads.nthreads()
    if nt == 1 || prod(nd) <= HOST_GRAIN || last(nd) < 2
        _host_cartesian!(body, CartesianIndices(nd), args)
    else
        _host_cartesian_threaded!(body, nd, cld(last(nd), min(nt, last(nd))), args)
    end
    return nothing
end

# the plain Cartesian loop (allocates nothing)
function _host_cartesian!(body::B, R::CartesianIndices, args::A) where {B, A}
    for I in R
        body(Tuple(I), args...)
    end
    return nothing
end

# chunks of the last axis on Polyester's persistent workers (`@batch`: no task is created, so
# a warm launch allocates nothing; nested under busy workers it runs the chunks serially)
@noinline function _host_cartesian_threaded!(body::B, nd::NTuple{N}, chunk::Integer, args::A) where {B, N, A}
    nc = cld(last(nd), chunk)
    @batch per = thread for c in 1:nc
        _host_cartesian_chunk!(body, nd, chunk, c, args)
    end
    return nothing
end
function _host_cartesian_chunk!(body::B, nd::NTuple{N}, chunk::Integer, c::Integer, args::A) where {B, N, A}
    lo, hi = (c - 1) * chunk + 1, min(c * chunk, last(nd))
    _host_cartesian!(body, CartesianIndices(ntuple(d -> d == N ? (lo:hi) : (1:nd[d]), Val(N))), args)
    return nothing
end
function (l::CartesianLaunch)()
    body, args, _ = l.params
    l.kernel(body, args, true)
    return nothing
end
function (l::LinearLaunch)()
    body, args, n = l.params
    if l.ndrange == 0
        l.kernel(body, args, n)
    else
        l.kernel(body, args, n; ndrange = l.ndrange)
    end
    return nothing
end

"""
    compile!(l::Launch)

Compile `l`'s kernel by a launch with `n = 0`: over one workgroup for a dynamic ndrange,
over the full static ndrange otherwise (it is part of the kernel type). Nothing on the host.
"""
compile!(l::Launch{HostExec}) = nothing
compile!(l::CartesianLaunch{HostExec}) = nothing
compile!(l::CartesianLaunch) = (l.kernel(l.params[1], l.params[2], false); nothing)
function compile!(l::LinearLaunch{K, WG}) where {K, WG}
    body, args, _ = l.params
    if l.ndrange == 0
        l.kernel(body, args, 0)
    else
        l.kernel(body, args, 0; ndrange = WG)
    end
    return nothing
end

"""
    compile_all!(backend, jobs)

Compile a kernel set in parallel on the host: one task per job (`Threads.@spawn`), each a
[`Launch`](@ref) or a zero-argument function that compiles (e.g. `() -> compile!(backend,
body, args)`), and each task synchronizes `backend` before it ends (device streams are
task-local). Waits for every task; rethrows the first failure. Compilation is the cost
(about 0.2 s per kernel on ROCm); with 4 threads a 17-kernel set compiles about 1.5 s
faster than in series (pass 3). Returns `nothing`.
"""
function compile_all!(backend, jobs)
    ishost(backend) && return nothing
    tasks = [Threads.@spawn _compile_job!(backend, j) for j in jobs]
    err = nothing
    for t in tasks
        try
            wait(t)
        catch e
            err === nothing && (err = e)
        end
    end
    err === nothing || throw(err isa TaskFailedException ? err.task.exception : err)
    return nothing
end

_compile_job!(backend, l::Launch) = (compile!(l); KernelAbstractions.synchronize(backend); nothing)
_compile_job!(backend, f::F) where {F} = (f(); KernelAbstractions.synchronize(backend); nothing)

# ---------------------------------------------------------------------------------------
# Plans

"""
    Plan(launches::Tuple)

A fixed sequence of [`Launch`](@ref)es (or any zero-argument callables), run in order by
`plan()`. The walk is a RuntimeGeneratedFunction emitted once per plan length,
`t -> (t[1](); t[2](); …; nothing)`: one call per launch, unrolled and type-stable at any
length. A recursive or `foreach` walk over a tuple of more than 32 launches is not: it
allocates 10–13 KB per launch (pass 3), and `return_types` does not show it.
"""
struct Plan{L <: Tuple, W}
    launches::L
    walk::W
end
Plan(launches::Tuple) = Plan(launches, walker(length(launches)))

(p::Plan)() = p.walk(p.launches)

Base.length(p::Plan) = length(p.launches)

const _WALKERS = Dict{Int, Any}()
const _WALKERS_LOCK = ReentrantLock()

"""
    walker(n)

The RuntimeGeneratedFunction `t -> (t[1](); …; t[n](); nothing)` (cached by `n`).
"""
function walker(n::Integer)
    n >= 0 || throw(ArgumentError("walker: n = $n < 0"))
    return lock(_WALKERS_LOCK) do
        get!(_WALKERS, Int(n)) do
            calls = [:(getfield(t, $i)()) for i in 1:n]
            ex = :(function (t)
                $(calls...)
                return nothing
            end)
            RuntimeGeneratedFunctions.drop_expr(@RuntimeGeneratedFunction(ex))
        end
    end
end

end # module Exec
