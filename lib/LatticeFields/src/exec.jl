"""
    LatticeFields.Exec

The execution layer: one host executor for every CPU kernel and one generic
device wrapper for every device kernel. A kernel is a body `body(i, args...)` run for
`i in 1:n`.

- **Host executor** ([`host_launch!`](@ref)): a plain loop, or a threaded chunked loop for
  large `n`. The KernelAbstractions CPU backend never runs production work.
- **Device wrapper** (`_kernel!`): `unsafe_indices = true` with an `if i <= n` guard.
- **Launches**: [`launch!`](@ref) for a dynamic launch from a runtime `n`;
  [`Launch`](@ref) for a prebuilt, type-stable launch (static ndrange for bodies that run at
  one size); [`Plan`](@ref) for a zero-allocation walk over a tuple of launches.
- **Compile before enqueue**: [`compile!`](@ref) compiles a kernel by a launch with `n = 0`
  (no work item passes the guard); [`compile_all!`](@ref) compiles a set on host tasks.
- **Capabilities and policy**: [`supports`](@ref) (what the hardware runs),
  [`default_float`](@ref) (the float type CorePotts emits by default), [`ishost`](@ref),
  [`kernel_argument_bytes`](@ref) and [`array_argument_bytes`](@ref) (the kernel-argument
  budget and the size of one array argument, which bound fusion).
"""
module Exec

using KernelAbstractions: KernelAbstractions, @kernel, @index
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, @RuntimeGeneratedFunction
using Polyester: @batch

RuntimeGeneratedFunctions.init(@__MODULE__)

public HOST_GRAIN, COMPILE_ONLY, VERBOSE, compiling, ishost, supports, default_float,
    kernel_argument_bytes, array_argument_bytes,
    register_float64!, float64_registered, FLOAT64_KERNELS, FLOAT64_ARRAY, host_launch!,
    launch!, compile!, compile_all!, Launch, Plan, walker

# ---------------------------------------------------------------------------------------
# Capabilities

"""
    ishost(backend) -> Bool

Whether kernels on `backend` run on the host executor (host memory, native Julia): true for
the KernelAbstractions CPU backend, false for every device backend.

# Arguments
- `backend`: a KernelAbstractions backend, for example `CPU()` or `ROCBackend()`.

# Returns
- `true` for `KernelAbstractions.CPU`, `false` for any other argument.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Exec.KernelAbstractions: CPU

julia> LatticeFields.Exec.ishost(CPU())
true
```

See also [`supports`](@ref), [`default_float`](@ref).
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

# Arguments
- `backend`: a KernelAbstractions backend.
- `T`: the number type to ask about.

# Returns
- `true` if `backend` is the host, or `T <: Float32`, or `T <: Float64` and the backend
  supports Float64; `false` otherwise.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Exec.KernelAbstractions: CPU

julia> LatticeFields.Exec.supports(CPU(), Float64)
true
```

See also [`ishost`](@ref), [`default_float`](@ref).
"""
function supports(backend, ::Type{T}) where {T}
    return ishost(backend) || T <: Float32 ||
        (T <: Float64 && KernelAbstractions.supports_float64(backend))
end

"""
    default_float(backend) -> Type

Policy: the float type of code emitted for `backend` when the caller names none. `Float64`
on the host executor, `Float32` on every device: default device code stays `Float32`, so it
runs unchanged on backends without doubles (Metal) and gives the same results on every
device (the device scan checks production Float32 paths for doubles). This is not a query of
the hardware; ask [`supports`](@ref) for that.

# Arguments
- `backend`: a KernelAbstractions backend.

# Returns
- `Float64` if [`ishost`](@ref)`(backend)`, else `Float32`.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Exec.KernelAbstractions: CPU

julia> LatticeFields.Exec.default_float(CPU())
Float64
```
"""
default_float(backend) = ishost(backend) ? Float64 : Float32

"""
    kernel_argument_bytes(backend) -> Union{Int, Nothing}

The kernel-argument budget of `backend` in bytes: the most argument data one kernel launch
may pass. The planner splits a fusion whose array arguments would exceed it.

The host executor passes arguments as ordinary Julia calls, so the CPU has no budget. The
ROCm and Metal methods are in the package extensions (4096 bytes on both). Any other backend
needs a method; without one this throws.

# Arguments
- `backend`: a KernelAbstractions backend.

# Returns
- The budget in bytes, or `nothing` when there is no budget.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Exec.KernelAbstractions: CPU

julia> LatticeFields.Exec.kernel_argument_bytes(CPU()) === nothing
true
```

See also [`array_argument_bytes`](@ref).
"""
kernel_argument_bytes(::KernelAbstractions.CPU) = nothing
function kernel_argument_bytes(backend)
    throw(
        ArgumentError(
            string(
                "no kernel-argument budget is known for backend ", typeof(backend),
                "; define `LatticeFields.Exec.kernel_argument_bytes(::",
                typeof(backend), ")` (bytes, or `nothing` for no budget)"
            )
        )
    )
end

@kernel function _argument_probe!(a)
    nothing
end

"""
    array_argument_bytes(backend) -> Int

The size in bytes of one array argument as `backend` passes it to a kernel: the device-side
form that KernelAbstractions converts an array to (`KernelAbstractions.argconvert`), measured
on an empty `Float32` vector (every LatticeFields array is a vector). The element type does
not change it.

# Arguments
- `backend`: a KernelAbstractions device backend.

# Returns
- The size of the converted array in bytes.

See also [`kernel_argument_bytes`](@ref).
"""
function array_argument_bytes(backend)
    a = KernelAbstractions.allocate(backend, Float32, 0)
    # (the size of the type: `sizeof` of an array value is its data)
    return sizeof(typeof(KernelAbstractions.argconvert(_argument_probe!(backend), a)))
end

"""
    register_float64!(parts::String...)

The carve-out: a kernel whose Float64 its user declared (a
group's `compute_type` or `solver_type` of Float64, or a field's
`lattice_storage = Float64`, on a device whose default float is Float32) is registered by
the parts of its signature text: a kernel signature that holds every part is skipped by the
no-`double` scan of the device test suites, which still flags every other kernel.
[`float64_registered`](@ref) asks.

# Arguments
- `parts`: substrings of the kernel signature text. The special part
  [`FLOAT64_ARRAY`](@ref) matches a Float64 device array of any dimension.

# Returns
- `nothing`. The entry is added to [`FLOAT64_KERNELS`](@ref) under a lock.
"""
function register_float64!(parts::String...)
    lock(_FLOAT64_LOCK) do
        push!(FLOAT64_KERNELS, collect(String, parts))
    end
    return nothing
end
"""
    FLOAT64_KERNELS::Set{Vector{String}}

The registry of [`register_float64!`](@ref): one vector of signature parts per entry.
"""
const FLOAT64_KERNELS = Set{Vector{String}}()
const _FLOAT64_LOCK = ReentrantLock()
"""
    float64_registered(signature::AbstractString) -> Bool

Whether a kernel signature text holds every part of a [`register_float64!`](@ref) entry.

# Arguments
- `signature`: the printed signature of a compiled kernel.

# Returns
- `true` if some entry of [`FLOAT64_KERNELS`](@ref) has all its parts in `signature`.
"""
function float64_registered(sig::AbstractString)
    return lock(() -> any(e -> all(q -> _holds(sig, q), e), FLOAT64_KERNELS), _FLOAT64_LOCK)
end
"""
    FLOAT64_ARRAY::String

The part of a [`register_float64!`](@ref) entry that stands for a Float64 device array in
the signature, whatever its dimension: Julia prints a 1D or 2D device array by its alias
(`ROCDeviceVector{Float64, 1}`, `ROCDeviceMatrix{Float64, 1}`), a 3D one as
`ROCDeviceArray{Float64, 3, 1}`.
"""
const FLOAT64_ARRAY = "a Float64 device array"
function _holds(sig, q)
    return if q == FLOAT64_ARRAY
        occursin(r"Device(Array|Vector|Matrix)\{Float64[,}]", sig)
    else
        occursin(q, sig)
    end
end

# ---------------------------------------------------------------------------------------
# Host executor

"""
    HOST_GRAIN::Int

Minimum number of work items per host thread. A launch of at most `HOST_GRAIN` items, or
any launch with one thread, is a plain loop (a threaded launch of few items is slower than
the loop).
"""
const HOST_GRAIN = 8192

"""
    host_launch!(body, n, args)

Run `body(i, args...)` for `i in 1:n` on the host: a plain loop when `n ≤ HOST_GRAIN` or
with one thread, else `ceil(n / chunk)` chunks of
`chunk = max(cld(n, nthreads), HOST_GRAIN)` items on Polyester's persistent workers
(`@batch`: no task is created, so a warm launch allocates nothing; nested under busy
workers, e.g. inside `EnsembleThreads`, the chunks run serially). Under `@batch`, Polyester
passes top-level `Array`s in `args` as `PtrArray`s, so a body compiles for both array types.

# Arguments
- `body`: a callable `body(i, args...)`.
- `n`: the number of work items.
- `args`: the tuple of extra arguments passed to every call.

# Returns
- `nothing`.

# Examples
```jldoctest
julia> using LatticeFields

julia> v = zeros(4);

julia> LatticeFields.Exec.host_launch!((i, v) -> (v[i] = i; nothing), 4, (v,))

julia> v
4-element Vector{Float64}:
 1.0
 2.0
 3.0
 4.0
```

See also [`launch!`](@ref), [`HOST_GRAIN`](@ref).
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

@noinline function _host_threaded!(body::B, n::Integer, chunk::Integer, args::A) where {
        B, A,
    }
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
`n ≤ 0`. In compile mode ([`compiling`](@ref)) a device launch compiles the kernel instead.

# Arguments
- `backend`: a KernelAbstractions backend.
- `body`: a callable `body(i, args...)`.
- `n`: the number of work items.
- `args`: the tuple of extra arguments passed to every call.

# Returns
- `nothing`.

See also [`host_launch!`](@ref), [`Launch`](@ref), [`compile!`](@ref).
"""
function launch!(backend, body::B, n::Integer, args::A) where {B, A}
    if ishost(backend)
        host_launch!(body, n, args)
    elseif compiling()
        compile!(backend, body, args)
    elseif n > 0
        _kernel!(backend)(body, args, Int(n); ndrange = Int(n))
    end
    return nothing
end

"""
    compiling() -> Bool

Whether the current task runs in compile mode ([`COMPILE_ONLY`](@ref)): every device launch
of [`launch!`](@ref), of a prebuilt [`Launch`](@ref) and of a solver's workgroup launch
compiles its kernel instead (a launch that runs no work item), so a host task can walk a
runtime's launch sequence to compile it ahead of the first step (the implicit
launches in the pending compile task). The host executor ignores it.

# Returns
- The value of [`COMPILE_ONLY`](@ref) in the current task.
"""
compiling() = COMPILE_ONLY[]
"""
    COMPILE_ONLY::Base.ScopedValues.ScopedValue{Bool}

Compile mode, task-scoped (`Base.ScopedValues.with(Exec.COMPILE_ONLY => true) do … end`).
The default is `false`. [`compiling`](@ref) reads it.
"""
const COMPILE_ONLY = Base.ScopedValues.ScopedValue(false)
"""
    VERBOSE::Base.ScopedValues.ScopedValue{Bool}

Whether a run's warnings print, task-scoped: `false` inside an owned run given
`verbose = false` (SciML's `verbose` keyword); every warning of a run checks it. The
default is `true`.
"""
const VERBOSE = Base.ScopedValues.ScopedValue(true)

"""
    compile!(backend, body, args)

Compile the kernel that [`launch!`](@ref)`(backend, body, n, args)` runs, by a launch of one
work item with `n = 0` (it passes no guard, so nothing is written). The kernel type does not
depend on the ndrange of a dynamic launch, so the later launch reuses this compile. A
launch over an empty ndrange is not used, since it may return before compiling. Nothing on
the host executor. Does not synchronize.

# Arguments
- `backend`: a KernelAbstractions backend.
- `body`: the kernel body, as given to [`launch!`](@ref).
- `args`: the tuple of extra arguments, as given to [`launch!`](@ref).

# Returns
- `nothing`.

See also [`compile_all!`](@ref), [`compiling`](@ref).
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
a static ndrange (`n` rounded up to a multiple of `WG`). A static ndrange avoids a
per-launch cost, but each distinct ndrange is its own kernel type, so its own compile
(`static` has no default: the caller decides): use it for bodies that run at one size, and
`static = false` for bodies launched at several sizes. On the host
the launch is [`host_launch!`](@ref).

Type parameters: `K` the kernel object (or the host executor), `WG` the workgroup size (0 on
the host), `NP` the launch tuple `(body, args, n)`.

# Arguments
- `backend`: a KernelAbstractions backend.
- `body`: a callable `body(i, args...)`.
- `args`: the tuple of extra arguments.
- `n`: the number of work items; `n < 0` throws an `ArgumentError`.

# Keywords
- `static::Bool`: required. `true` puts the ndrange in the kernel type.
- `workgroupsize = 256`: the device workgroup size; a value below 1 throws an
  `ArgumentError`. Ignored on the host.

# Returns
- A `Launch`; call it with no arguments to enqueue it.

# Examples
```jldoctest
julia> using LatticeFields; using LatticeFields.Exec.KernelAbstractions: CPU

julia> v = zeros(3);

julia> l = LatticeFields.Exec.Launch(CPU(), (i, v) -> (v[i] = 2i; nothing), (v,), 3;
                                     static = false);

julia> l(); v
3-element Vector{Float64}:
 2.0
 4.0
 6.0
```

See also [`Plan`](@ref), [`compile!`](@ref), [`launch!`](@ref).
"""
struct Launch{K, WG, NP <: Tuple{Any, Tuple, Union{Int, Tuple}}}
    kernel::K
    params::NP
    # the dynamic linear ndrange; 0 for a static one (in the kernel type)
    ndrange::Int
end

# a linear launch carries `n::Int`, a Cartesian one its ndrange `NTuple{N, Int}`
const LinearLaunch{K, WG} = Launch{K, WG, <:Tuple{Any, Tuple, Int}}
const CartesianLaunch{K, WG} = Launch{K, WG, <:Tuple{Any, Tuple, Tuple}}

# The Cartesian device kernel (the Schedule–Exec contract, contract.jl): `body(x, args...)`
# with `x::NTuple{N, Int}` 1-based; the body guards every axis itself (padded items are
# no-ops). `live = false` is the compile launch: no item calls the body.
@kernel unsafe_indices = true function _kernel_cart!(body, args, live)
    x = @index(Global, NTuple)
    if live
        body(x, args...)
    end
end

function Launch(
        backend, body::B, args::A, n::Integer; static::Bool,
        workgroupsize::Integer = 256
    ) where {B, A <: Tuple}
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

# Arguments
- `backend`: a KernelAbstractions backend.
- `body`: the kernel body.
- `args`: the tuple of extra arguments.
- `ndrange`: the tuple of axis lengths; a negative axis throws an `ArgumentError`.

# Keywords
- `static::Bool`: required. A Cartesian launch on a device requires `static = true`; else
  it throws an `ArgumentError`.
- `workgroupsize`: an integer or a tuple with one entry per axis. The default is `256` for
  a 1-tuple and `(64, 1, …)` otherwise; an integer `w` means `(w, 1, …)`.
- `cartesian::Bool = length(ndrange) > 1`: whether the launch is Cartesian.

# Returns
- A `Launch`.
"""
function Launch(
        backend, body::B, args::A, ndrange::NTuple{N, Integer};
        workgroupsize::Union{Integer, NTuple{N, Integer}} = if N == 1
            256
        else
            (64, ntuple(_ -> 1, N - 1)...)
        end,
        static::Bool, cartesian::Bool = N > 1
    ) where {B, A <: Tuple, N}
    cartesian || return Launch(
        backend, body, args, only(ndrange); workgroupsize = only(workgroupsize), static
    )
    all(>=(0), ndrange) ||
        throw(ArgumentError("Launch: ndrange $ndrange has a negative axis"))
    nd = map(Int, ndrange)
    params = (body, args, nd)
    ishost(backend) && return Launch{HostExec, 0, typeof(params)}(HostExec(), params, 0)
    wg = map(
        Int, if workgroupsize isa Integer
            (workgroupsize, ntuple(_ -> 1, N - 1)...)
        else
            workgroupsize
        end
    )
    all(>=(1), wg) || throw(ArgumentError("Launch: workgroupsize = $wg has an axis < 1"))
    pad = map((n, w) -> max(cld(n, w), 1) * w, nd, wg)
    static ||
        throw(ArgumentError("Launch: a Cartesian launch takes a static ndrange in this \
            version"))
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

# chunks of the last axis on Polyester's persistent workers (`@batch`: no task is created,
# so a warm launch allocates nothing; nested under busy workers it runs the chunks serially)
@noinline function _host_cartesian_threaded!(
        body::B, nd::NTuple{N}, chunk::Integer,
        args::A
    ) where {
        B, N, A,
    }
    nc = cld(last(nd), chunk)
    @batch per = thread for c in 1:nc
        _host_cartesian_chunk!(body, nd, chunk, c, args)
    end
    return nothing
end
function _host_cartesian_chunk!(
        body::B, nd::NTuple{N}, chunk::Integer, c::Integer, args::A
    ) where {B, N, A}
    lo, hi = (c - 1) * chunk + 1, min(c * chunk, last(nd))
    _host_cartesian!(
        body,
        CartesianIndices(ntuple(d -> d == N ? (lo:hi) : (1:nd[d]), Val(N))), args
    )
    return nothing
end
function (l::CartesianLaunch)()
    compiling() && return compile!(l)
    body, args, _ = l.params
    l.kernel(body, args, true)
    return nothing
end
function (l::LinearLaunch)()
    compiling() && return compile!(l)
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

# Arguments
- `l`: a prebuilt [`Launch`](@ref).

# Returns
- `nothing`.
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
task-local). Waits for every task; rethrows the first failure. Compilation is the cost, so
a set compiles faster than in series. Nothing on the host executor.

# Arguments
- `backend`: a KernelAbstractions backend.
- `jobs`: an iterable of [`Launch`](@ref)es or zero-argument functions.

# Returns
- `nothing`. Throws the exception of the first failed task.

See also [`compile!`](@ref).
"""
function compile_all!(backend, jobs)
    ishost(backend) && return nothing
    tasks = [Threads.@spawn _compile_job!(backend, j) for j in jobs]
    err = nothing
    for t in tasks
        try
            wait(t)
        catch e
            e isa TaskFailedException || rethrow()
            err === nothing && (err = e)
        end
    end
    err === nothing || throw(err isa TaskFailedException ? err.task.exception : err)
    return nothing
end

function _compile_job!(backend, l::Launch)
    (compile!(l); KernelAbstractions.synchronize(backend); nothing)
end
function _compile_job!(backend, f::F) where {F}
    (f(); KernelAbstractions.synchronize(backend); nothing)
end

# ---------------------------------------------------------------------------------------
# Plans

"""
    Plan(launches::Tuple)

A fixed sequence of [`Launch`](@ref)es (or any zero-argument callables), run in order by
`plan()`. The walk is a RuntimeGeneratedFunction emitted once per plan length,
`t -> (t[1](); t[2](); …; nothing)`: one call per launch, unrolled and type-stable at any
length. A recursive or `foreach` walk over a tuple of more than 32 launches is not: it
allocates at every launch, and `return_types` does not show it.

# Arguments
- `launches`: a tuple of [`Launch`](@ref)es or zero-argument callables.

# Returns
- A `Plan`. `plan()` returns `nothing`, and `length(plan)` is the number of launches.

# Examples
```jldoctest
julia> using LatticeFields

julia> calls = Int[];

julia> p = LatticeFields.Exec.Plan((() -> push!(calls, 1), () -> push!(calls, 2)));

julia> p(); calls
2-element Vector{Int64}:
 1
 2
```

See also [`walker`](@ref).
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

# Arguments
- `n`: the number of calls; `n < 0` throws an `ArgumentError`.

# Returns
- The cached RuntimeGeneratedFunction for `n`.
"""
function walker(n::Integer)
    n >= 0 || throw(ArgumentError("walker: n = $n < 0"))
    return lock(_WALKERS_LOCK) do
        get!(_WALKERS, Int(n)) do
            calls = [:(getfield(t, $i)()) for i in 1:n]
            ex = :(
                function (t)
                    $(calls...)
                    return nothing
                end
            )
            RuntimeGeneratedFunctions.drop_expr(@RuntimeGeneratedFunction(ex))
        end
    end
end

end # module Exec
