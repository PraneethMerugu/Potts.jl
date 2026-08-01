# Compiler-owned grouping of concrete stage descriptor types.

function _stage_descriptor_groups(descriptors)
    types = DataType[]
    grouped = Vector{Vector{Any}}()
    for descriptor in descriptors
        descriptor_type = typeof(descriptor)
        index = findfirst(==(descriptor_type), types)
        if index === nothing
            push!(types, descriptor_type)
            push!(grouped, Any[descriptor])
        else
            push!(grouped[index], descriptor)
        end
    end
    groups = ()
    for (descriptor_type, instances) in zip(types, grouped)
        typed = descriptor_type[instance for instance in instances]
        groups = (groups..., CorePotts.StageDescriptorGroup(typed))
    end
    return groups
end
