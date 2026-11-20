# Loading AMDGPU invalidates much of Potts' precompiled code (methods of Symbolics,
# GPUArrays and BFloat16s that AMDGPU's load brings in), so a session that loads it
# recompiled the whole symbolic pipeline on its first model (about 15 s on the PC; PG-11).
# This extension reruns Potts' compile workload with AMDGPU loaded, on the host, so that
# code is cached again.
module PottsAMDGPUExt

using AMDGPU: AMDGPU
using Potts: Potts
using PrecompileTools: PrecompileTools

PrecompileTools.@compile_workload begin
    Potts._precompile_workload()
end

end
