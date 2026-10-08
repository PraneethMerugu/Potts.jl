# ROCm device waits (D-179). AMDGPU.jl's default `synchronize`, which `KernelAbstractions.
# synchronize` and every `copyto!` to the host make, spins 256 times and then waits for a
# HIP host callback through Julia's event loop: a read point right after `step!` took
# ~13 ms on the OpenVT lifecycle models (2026-10-08, NucBox). Here the host spins on the
# stream's `hipStreamQuery` (`CorePotts._spin_until`: a GC safepoint every turn, a `yield`
# every few thousand, an error after the timeout) and then calls `hipStreamSynchronize`,
# which returns at once and reports a stream error; device→host copies are enqueued
# `async = true` and waited for the same way. The HIP entry points are called raw through
# their addresses: AMDGPU's wrappers (`HIP.isdone`, `synchronize(; blocking = true)`)
# allocate 16 B per call, and a warm wait here allocates nothing.
module CorePottsAMDGPUExt

using AMDGPU: AMDGPU, ROCArray, ROCBackend
using CorePotts: CorePotts

const HIP_SUCCESS = UInt32(0)
const HIP_ERROR_NOT_READY = UInt32(600)

"""Addresses of `hipStreamQuery` and `hipStreamSynchronize` (resolved on first use: the
library is found when AMDGPU initializes, and not at all without ROCm)."""
struct HIPCalls
    query::Ptr{Cvoid}
    sync::Ptr{Cvoid}
end
const HIP_CALLS = Ref(HIPCalls(C_NULL, C_NULL))

function hip_calls()
    h = HIP_CALLS[]
    h.query == C_NULL || return h
    return HIP_CALLS[] = resolve_hip_calls()
end
@noinline function resolve_hip_calls()
    Libdl = Base.Libc.Libdl
    lib = Libdl.dlopen(AMDGPU.libhip)
    return HIPCalls(Libdl.dlsym(lib, :hipStreamQuery), Libdl.dlsym(lib, :hipStreamSynchronize))
end

"""`done()` for `_spin_until`: the stream has no work left (any answer but "not ready":
an error is then reported by the synchronize that follows)."""
struct StreamDone
    query::Ptr{Cvoid}
    stream::Ptr{Cvoid}
end
(d::StreamDone)() = ccall(d.query, UInt32, (Ptr{Cvoid},), d.stream) != HIP_ERROR_NOT_READY

@noinline hip_failed(code) = throw(AMDGPU.HIP.HIPError(AMDGPU.HIP.hipError_t(code)))

function CorePotts._device_wait(::ROCBackend; timeout::Real = CorePotts.DEVICE_WAIT_TIMEOUT)
    s = AMDGPU.stream()
    h = hip_calls()
    handle = Ptr{Cvoid}(s.stream)
    CorePotts._spin_until(StreamDone(h.query, handle), timeout)
    code = ccall(h.sync, UInt32, (Ptr{Cvoid},), handle)
    code == HIP_SUCCESS || hip_failed(code)
    AMDGPU.throw_if_exception(s.device)          # a kernel exception, as `synchronize` reports it
    return nothing
end

# Device→host copies: enqueued on the task's stream without AMDGPU's wait, then waited for.
# The stream is drained first: an async copy into pageable host memory may itself block in
# HIP until earlier work finishes, with no yield (a hostcall kernel would deadlock) and no
# timeout, so the copy is only enqueued on an idle stream.
function CorePotts._copy_to_host!(dst::Array{T}, doff::Integer, src::ROCArray{T}, soff::Integer, n::Integer) where {T}
    CorePotts._device_wait(ROCBackend())
    copyto!(dst, doff, src, soff, n; async = true)
    CorePotts._device_wait(ROCBackend())
    return dst
end
CorePotts._copy_to_host!(dst::Array{T}, src::ROCArray{T}) where {T} =
    CorePotts._copy_to_host!(dst, 1, src, 1, length(src))
CorePotts._host_copy(a::ROCArray{T, N}) where {T, N} = CorePotts._copy_to_host!(Array{T, N}(undef, size(a)), a)

end # module CorePottsAMDGPUExt
