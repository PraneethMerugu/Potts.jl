# Loading AMDGPU invalidates much of the precompiled code of the models (see Potts'
# PottsAMDGPUExt; PG-11). This extension reruns PottsModels' compile workload with AMDGPU
# loaded, on the host, so the first problem and MCS of a session reuse cached code again.
module PottsModelsAMDGPUExt

using AMDGPU: AMDGPU
using PottsModels: PottsModels
using PrecompileTools: PrecompileTools

PrecompileTools.@compile_workload begin
    PottsModels._precompile_workload()
end

end
