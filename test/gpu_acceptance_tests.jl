# PottsModels acceptance files on device backends (each file's items, through
# shared/pottsmodels_test_file.jl) and standalone ROCm device IR scan (D-157).

# P6.0k: the frozen Boolean-network acceptance file (its device testset runs only where a
# device backend is loaded: here), then discrete components with couplings and model scope
# on the device.
@testitem "P6.0k: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60kOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "boolean_network_tests.jl"))
    end
end

# P6.0v: the frozen transfer-counter acceptance file, whose device testset runs only where
# a device backend is loaded (here)
@testitem "P6.0v: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60vOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "transfer_counters_tests.jl"))
    end
end

# P6.0v2: the frozen column-copy acceptance file (device testsets run only here)
@testitem "P6.0v2: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60v2OnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "column_copies_tests.jl"))
    end
end

# P6.0v2b: the frozen custom-rule refresh acceptance file (device testsets run only here)
@testitem "P6.0v2b: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60v2bOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "frozen_kind_refresh_bytes_tests.jl"))
    end
end

# P6.0v1: the frozen device-lifecycle acceptance file, whose device testsets run only where
# a device backend is loaded (here). On Metal it wraps `Metal.wait_cmdbuf!` for its own wait
# count; `transfer_counts.jl` below re-wraps it for its own.
@testitem "P6.0v1: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60v1OnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "device_lifecycle_tests.jl"))
    end
end

# P6.0v3 (with P6.0v8): launch fusion and no hidden GPU wait. The acceptance file's device
# testsets run only where a device backend is loaded (here); on Metal it wraps
# `Metal.wait_cmdbuf!` for its own wait count, and `transfer_counts.jl` below re-wraps it.
@testitem "P6.0v3: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60v3OnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "launch_fusion_tests.jl"))
    end
end

# P6.0bw: the library's device wait (D-179). The acceptance file's device testsets (the
# helper on the device, its allocations, results on every gate case; on ROCm hostcalls and
# the read-point timing) run only where a device backend is loaded (here)
@testitem "P6.0bw: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60bwOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "device_wait_tests.jl"))
    end
end

# run only where a device backend is loaded (here).
@testitem "P6.0ag: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60agOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "ode_expansion_tests.jl"))
    end
end

# P6.0af: the staged-form handover after the fused `before` ran (D-108); device testsets here
@testitem "P6.0af: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60afOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "lifecycle_launch_fusion_tests.jl"))
    end
end

# P6.0q: a population fold reading `time` inside a cell ODE (unhoisted) on the device (D-119);
# the acceptance file's device testsets run only where a device backend is loaded (here)
@testitem "P6.0q: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60qOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "time_fold_metal_tests.jl"))
    end
end

# P6.0g: kind classes lower to constant kind comparisons, so the class gates compile for
# the device and match the CPU run in Float32 (D-135)
@testitem "P6.0g: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60gOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "kind_classes_tests.jl"))
    end
end

# P6.3a: the frozen topology/track acceptance file; its device testset (the ΔH track in
# Float32, no per-MCS sync) runs only where a device backend is loaded (here)
@testitem "P6.3a: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P63aOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "topology_tracking_tests.jl"))
    end
end

# P6.15c: the frozen OpenVT Table S1 file; its device testset (contact counts exact, draws per
# daughter and the model's free-surface fraction, CheckerboardCPM in Float32) runs only where
# a device backend is loaded (here)
@testitem "P6.15c: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P615cOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "openvt_table_s1_tests.jl"))
    end
end

# P6.0n, P6.0r, P6.3b: frozen acceptance files whose device testsets (a cell ODE across cells,
# a partner killed during a device run, boundaries and the schedule) were not wired into the
# GPU group before D-157; they run only where a device backend is loaded (here)
@testitem "P6.0n: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60nOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "cell_ode_jacobi_tests.jl"))
    end
end

@testitem "P6.0r: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P60rOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "killing_copy_energy_tests.jl"))
    end
end

@testitem "P6.3b: the frozen acceptance file on the device" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    module P63bOnDevice
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
