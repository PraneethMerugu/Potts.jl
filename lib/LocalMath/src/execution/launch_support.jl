# KernelAbstractions specializes a constructor-provided ndrange on its value.
# The owning operation supplies its semantic workgroup; extent stays runtime data.
@inline function _launch_1d!(
        kernel, backend, extent::Int, ::Val{Workgroup}, arguments...
    ) where {Workgroup}
    return kernel(backend, Workgroup)(arguments...; ndrange = max(extent, 1))
end
