# Backend-neutral device selection for the test suites (D-157).
#
#   POTTS_GPU ∈ {"", "metal", "rocm"}   (the CorePotts suite reads COREPOTTS_GPU when
#                                         POTTS_GPU is empty; both set must agree)
#
# Including this file defines the module `PottsDevices` in the including module (the test
# runners include it into `Main`, guarded with `isdefined(Main, :PottsDevices) ||`). It
# loads Metal.jl for "metal" and AMDGPU.jl for "rocm", and no GPU package at all when the
# variable is empty: Metal.jl precompiles on Linux but cannot run there, and AMDGPU.jl
# likewise on macOS, so each is only *loaded* on request.
#
# API (all functions; nothing is exported):
#   device_name()      "" | "metal" | "rocm"
#   on_device()        a device backend was requested (and its package loaded)
#   device_backend()   Metal.MetalBackend() | AMDGPU.ROCBackend()
#   device_sync()      wait for all work queued on the device
#   device_array(x)    copy a host array to the device (MtlArray / ROCArray)
#   device_arraytype() MtlArray | ROCArray (for `isa` checks)
#   device_package()   the loaded package module (Metal | AMDGPU), for backend-specific
#                      instrumentation; `nothing` off the device
#
# Off the device a test records the uniform skip
#   @test_skip "device (POTTS_GPU=metal|rocm)"
# written out literally (`@test_skip` records its expression unevaluated). Frozen acceptance
# files guard every use with `isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()`,
# so they still load where this file was not included.
module PottsDevices

function _requested()
    a = lowercase(strip(get(ENV, "POTTS_GPU", "")))
    b = lowercase(strip(get(ENV, "COREPOTTS_GPU", "")))
    for v in (a, b)
        v in ("", "metal", "rocm") ||
            error("POTTS_GPU/COREPOTTS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$v\"")
    end
    isempty(a) || isempty(b) || a == b ||
        error("POTTS_GPU = \"$a\" and COREPOTTS_GPU = \"$b\" disagree; set one, or both alike")
    return isempty(a) ? b : a
end

const NAME = _requested()

if NAME == "metal"
    import Metal
    const PKG = Metal
elseif NAME == "rocm"
    import AMDGPU
    const PKG = AMDGPU
else
    const PKG = nothing
end

device_name() = NAME
on_device() = PKG !== nothing
device_package() = PKG

_off() = error("no device backend requested (set POTTS_GPU=metal or rocm)")

function device_backend()
    NAME == "metal" && return PKG.MetalBackend()
    NAME == "rocm" && return PKG.ROCBackend()
    return _off()
end

function device_sync()
    on_device() || return _off()
    PKG.synchronize()
    return nothing
end

function device_arraytype()
    NAME == "metal" && return PKG.MtlArray
    NAME == "rocm" && return PKG.ROCArray
    return _off()
end

device_array(x::AbstractArray) = device_arraytype()(x)

end # module PottsDevices
