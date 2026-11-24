# The kernels that a GPU package (AMDGPU or Metal) compiled and loaded on the current
# device in this process. The device IR scan (device_ir_scan.jl), the kernel counts of the
# device suites (PottsDevices, LatticeFields' device_backend.jl) and LatticePDE's
# bench_fv.jl all list kernels through `compiled_kernels`; this file is the one place that
# chooses how.
#
# The method: every kernel lookup goes through `AMDGPU.hipfunction(f, tt; kw...)` or
# `Metal.mtlfunction(f, tt; kw...)`, and both specialize on the kernel's function type `F`
# and argument types `tt`. The specializations of these functions and of their keyword
# bodies give the candidate signatures. The keywords (KernelAbstractions 0.10 passes
# `maxthreads`, for one) select a compiler configuration, and the package keeps every
# configuration it made in `_compiler_configs`. A candidate counts when the package's
# compile results for it under one of these configurations (GPUCompiler's
# `cached_results`) hold a function or a pipeline loaded on the current device. A
# specialization that was only inferred has none, so it does not count. Checked on AMDGPU
# 2.8 (gates) and 2.13 (trial); Metal untested. The per-package kernel dicts
# (`AMDGPU.Compiler._kernel_instances`, `Metal.kernel_instances`) are gone in the newer
# versions.

"""
    compiled_kernels(pkg::Module) -> Vector{Tuple{DataType, DataType}}

The `(F, tt)` pairs (kernel function type, argument tuple type) of every kernel that `pkg`
(`AMDGPU` or `Metal`) compiled and loaded on its current device in this process.
"""
function compiled_kernels(pkg::Module)
    G = pkg.GPUCompiler
    if nameof(pkg) === :AMDGPU
        lookup, R, dev = pkg.Compiler.hipfunction, pkg.Compiler.HIPResults, pkg.device()
        configs = collect(values(pkg.Compiler._compiler_configs))
        loaded = r -> any(f -> first(f) == dev, r.functions)
    elseif nameof(pkg) === :Metal
        lookup, R, dev = pkg.mtlfunction, pkg.MetalResults, pkg.device()
        configs = collect(values(pkg._compiler_configs))
        loaded = r -> any(p -> first(p) == dev, r.pipelines)
    else
        throw(ArgumentError("no kernel listing for $pkg"))
    end
    mod, name = parentmodule(lookup), string(nameof(lookup))
    pairs = Set{Tuple{DataType, DataType}}()
    for n in names(mod; all = true)
        s = string(n)
        (s == name || startswith(s, "#$(name)#")) || continue
        for m in methods(getfield(mod, n)), mi in Base.specializations(m)
            sig = mi.specTypes
            sig isa DataType && length(sig.parameters) >= 2 || continue
            F, T = sig.parameters[end - 1], sig.parameters[end]
            T isa DataType && T <: Type{<:Tuple} || continue
            TT = T.parameters[1]
            F isa DataType && isconcretetype(F) && TT isa DataType &&
                isconcretetype(TT) || continue
            job_mi = G.methodinstance(F, TT)
            for config in configs
                r = G.cached_results(R, G.CompilerJob(job_mi, config))
                r !== nothing && loaded(r) && push!(pairs, (F, TT))
            end
        end
    end
    return collect(pairs)
end
