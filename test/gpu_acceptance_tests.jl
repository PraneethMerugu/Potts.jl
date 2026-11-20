# PottsModels acceptance files on device backends (each file's items, through
# shared/pottsmodels_test_file.jl) and standalone ROCm device IR scan (D-157).

# The Boolean-network acceptance file (its device testset runs only where a
# device backend is loaded: here), then discrete components with couplings and model scope
# on the device.
@testitem "boolean network: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module BooleanNetworkOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "boolean_network_tests.jl"))
    end
end

# The transfer-counter acceptance file, whose device testset runs only where
# a device backend is loaded (here)
@testitem "transfer counters: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module TransferCountersOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "transfer_counters_tests.jl"))
    end
end

# The column-copy acceptance file (device testsets run only here)
@testitem "column copies: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module ColumnCopiesOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "column_copies_tests.jl"))
    end
end

# The custom-rule refresh acceptance file (device testsets run only here)
@testitem "frozen kind refresh bytes: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module FrozenKindRefreshBytesOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "frozen_kind_refresh_bytes_tests.jl"))
    end
end

# The device-lifecycle acceptance file, whose device testsets run only where
# a device backend is loaded (here). On Metal it wraps `Metal.wait_cmdbuf!` for its own wait
# count; `transfer_counts.jl` below re-wraps it for its own.
@testitem "device lifecycle: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module DeviceLifecycleOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "device_lifecycle_tests.jl"))
    end
end

# Launch fusion and no hidden GPU wait. The acceptance file's device
# testsets run only where a device backend is loaded (here); on Metal it wraps
# `Metal.wait_cmdbuf!` for its own wait count, and `transfer_counts.jl` below re-wraps it.
@testitem "launch fusion: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module LaunchFusionOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "launch_fusion_tests.jl"))
    end
end

# The library's device wait (D-179). The acceptance file's device testsets (the
# helper on the device, its allocations, results on every gate case; on ROCm hostcalls and
# the read-point timing) run only where a device backend is loaded (here)
@testitem "device wait: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module DeviceWaitOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "device_wait_tests.jl"))
    end
end

# The ODE-expansion acceptance file; its device testsets run only where a device backend is
# loaded (here).
@testitem "ODE expansion: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module ODEExpansionOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "ode_expansion_tests.jl"))
    end
end

# The staged-form handover after the fused `before` ran (D-108); device testsets here
@testitem "lifecycle launch fusion: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module LifecycleLaunchFusionOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "lifecycle_launch_fusion_tests.jl"))
    end
end

# A population fold reading `time` inside a cell ODE (unhoisted) on the device (D-119);
# the acceptance file's device testsets run only where a device backend is loaded (here)
@testitem "time fold metal: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module TimeFoldMetalOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "time_fold_metal_tests.jl"))
    end
end

# Kind classes lower to constant kind comparisons, so the class gates compile for
# the device and match the CPU run in Float32 (D-135)
@testitem "kind classes: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module KindClassesOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "kind_classes_tests.jl"))
    end
end

# The topology/track acceptance file; its device testset (the ΔH track in
# Float32, no per-MCS sync) runs only where a device backend is loaded (here)
@testitem "topology tracking: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module TopologyTrackingOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "topology_tracking_tests.jl"))
    end
end

# The OpenVT Table S1 file; its device testset (contact counts exact, draws per
# daughter and the model's free-surface fraction, CheckerboardCPM in Float32) runs only where
# a device backend is loaded (here)
@testitem "OpenVT Table S1: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module OpenVTTableS1OnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "openvt_table_s1_tests.jl"))
    end
end

# Acceptance files whose device testsets (a cell ODE across cells,
# a partner killed during a device run, boundaries and the schedule) were not wired into the
# GPU group before D-157; they run only where a device backend is loaded (here)
@testitem "cell ODE Jacobi: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module CellODEJacobiOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "cell_ode_jacobi_tests.jl"))
    end
end

@testitem "killing copy energy: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module KillingCopyEnergyOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "killing_copy_energy_tests.jl"))
    end
end

@testitem "boundary schedule: the acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module BoundaryScheduleOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "boundary_schedule_tests.jl"))
    end
end

# D-157, ROCm: no `double` in any kernel this suite compiled (a full scan of the process's kernel
# cache). It is an item of its own, tagged `:device_scan`: it runs after every other device item and
# in the process that compiled those kernels (PottsRTI.device_suite), not when a setup is evaluated.
@testitem "device IR: no double in any kernel this suite compiled (ROCm)" setup = [GpuSetup] tags = [:potts, :gpu, :device, :gpu_only, :device_scan] begin
    if PottsDevices.device_name() == "rocm"
        include(joinpath(@__DIR__, "shared", "device_ir_scan.jl"))
        DeviceIRScan.check("Potts")
    end
end
