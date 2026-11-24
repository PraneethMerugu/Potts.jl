# The body of `PottsDevices` (test/shared/devices.jl): included into the one module per
# process, so this file is not a test file and ReTestItems does not scan it.

isdefined(@__MODULE__, :PottsDeviceSelect) ||
    include(joinpath(@__DIR__, "device_select.jl"))

const NAME = PottsDeviceSelect.requested()

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

include(joinpath(@__DIR__, "kernel_listing.jl"))
"""The `(F, tt)` pairs of the kernels compiled and loaded on the device in this process."""
device_kernels() = on_device() ? compiled_kernels(PKG) : _off()

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
