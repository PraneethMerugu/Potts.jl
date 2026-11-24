# Backend-neutral device selection for the test suites (D-157).
#
#   POTTS_GPU ∈ {"", "metal", "rocm"}   (the rule is `PottsDeviceSelect.requested`,
#                                         device_select.jl)
#
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
#   device_kernels()   the `(F, tt)` pairs of the kernels compiled and loaded on the device
#                      in this process (kernel_listing.jl)
#
# Off the device a test records the uniform skip
#   @test_skip "device (POTTS_GPU=metal|rocm)"
# written out literally (`@test_skip` records its expression unevaluated). Frozen acceptance
# files guard every use with `isdefined(Main, :PottsDevices) &&
# Main.PottsDevices.on_device()`; the module below is that `Main.PottsDevices`.
#
# One `PottsDevices` per process. Every `@testsetup` of the Potts suite includes this file,
# and a module defined once per setup gave each setup its own binding: an item that declares
# two setups then has two exported `PottsDevices` and resolves neither (`export_visible.jl`
# exports both). So the module is defined once, in `Main`, and every setup imports that one
# binding.
if !isdefined(Main, :PottsDevices)
    Core.eval(Main, :(module PottsDevices end))
    Base.include(Main.PottsDevices, joinpath(@__DIR__, "devices_module_body.jl"))
end
import Main.PottsDevices
