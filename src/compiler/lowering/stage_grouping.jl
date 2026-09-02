# Compiler-owned grouping of concrete stage descriptor types.

function _stage_descriptor_groups(descriptors)
    types = DataType[]
    grouped = Vector{Vector{Any}}()
    for descriptor in descriptors
        descriptor_type = typeof(descriptor)
        if isempty(types) || last(types) !== descriptor_type
            push!(types, descriptor_type)
            push!(grouped, Any[descriptor])
        else
            push!(last(grouped), descriptor)
        end
    end
    groups = ()
    for (descriptor_type, instances) in zip(types, grouped)
        typed = descriptor_type[instance for instance in instances]
        groups = (groups..., CorePotts.CompilerSPI.StageDescriptorGroup(typed))
    end
    return groups
end
