# Algorithmic workspace is described once per lowering. The specification is
# private, immutable, and descriptive: it validates and reports caller-owned
# arrays but cannot allocate, launch, synchronize, or authorize a backend.

struct _WorkspaceLeaf{T, N, P, S, R}
    name::Symbol
    path::P
    size::S
    strides::R
    role::Symbol
end

function _workspace_leaf(
        name::Symbol,
        path::Tuple,
        ::Type{T},
        size::NTuple{N, Int};
        strides = nothing,
        role::Symbol,
    ) where {T, N}
    return _WorkspaceLeaf{T, N, typeof(path), typeof(size), typeof(strides)}(
        name,
        path,
        size,
        strides,
        role,
    )
end

function _workspace_spec end

function _centrally_owned_workspace_spec(lowering, work)
    signature = Tuple{typeof(lowering), typeof(work)}
    method = which(_workspace_spec, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the algorithmic workspace specification is not centrally admitted"
    ))
    return invoke(_workspace_spec, signature, lowering, work)
end

function _workspace_leaf_value(workspace, leaf::_WorkspaceLeaf)
    value = workspace
    for name in leaf.path
        hasproperty(value, name) || throw(LocalWorkValidationError(
            "workspace path $(join(string.(leaf.path), '.')) is missing $name";
            stage = :prepare, contract = :workspace_leaf_presence,
            workspace_leaf = leaf.name,
            expected = leaf.path, actual = propertynames(value),
        ))
        value = getproperty(value, name)
    end
    return value
end

function _validate_workspace_leaf(workspace, leaf::_WorkspaceLeaf{T, N}, backend) where {T, N}
    array = invoke(
        _workspace_leaf_value,
        Tuple{Any, _WorkspaceLeaf},
        workspace,
        leaf,
    )
    array isa AbstractArray || throw(LocalWorkValidationError(
        "workspace $(leaf.name) must be an array";
        stage = :prepare, contract = :workspace_leaf_kind,
        workspace_leaf = leaf.name,
        expected = AbstractArray, actual = typeof(array),
    ))
    eltype(array) === T || throw(LocalWorkValidationError(
        "workspace $(leaf.name) must have element type $T";
        stage = :prepare, contract = :workspace_leaf_element_type,
        workspace_leaf = leaf.name, expected = T, actual = eltype(array),
    ))
    ndims(array) == N && size(array) == leaf.size || throw(
        LocalWorkValidationError(
            "workspace $(leaf.name) must have exact size $(leaf.size)";
            stage = :prepare, contract = :workspace_leaf_shape,
            workspace_leaf = leaf.name,
            expected = leaf.size, actual = size(array),
        )
    )
    leaf.strides === nothing || strides(array) == leaf.strides || throw(
        LocalWorkValidationError(
            "workspace $(leaf.name) must have exact strides $(leaf.strides)";
            stage = :prepare, contract = :workspace_leaf_strides,
            workspace_leaf = leaf.name,
            expected = leaf.strides, actual = strides(array),
        )
    )
    invoke(
        _validate_array_backend,
        Tuple{Any, Any, Any},
        array,
        backend,
        leaf.name,
    )
    return array
end

function _validate_workspace_spec(workspace, spec::Tuple, backend)
    arrays = map(spec) do leaf
        invoke(
            _validate_workspace_leaf,
            Tuple{Any, _WorkspaceLeaf, Any},
            workspace,
            leaf,
            backend,
        )
    end
    for first_index in eachindex(arrays), second_index in eachindex(arrays)
        first_index < second_index || continue
        Base.mightalias(arrays[first_index], arrays[second_index]) && throw(
            LocalWorkValidationError(
                "workspace $(spec[first_index].name) aliases $(spec[second_index].name)";
                stage = :prepare, contract = :workspace_alias,
                workspace_leaf = spec[first_index].name,
                expected = :nonaliasing,
                actual = (spec[first_index].name, spec[second_index].name),
            )
        )
    end
    return nothing
end

function _workspace_arrays_from_spec(workspace, spec::Tuple)
    return map(spec) do leaf
        leaf.name => invoke(
            _workspace_leaf_value,
            Tuple{Any, _WorkspaceLeaf},
            workspace,
            leaf,
        )
    end
end

function _workspace_leaf_bytes(leaf::_WorkspaceLeaf{T}) where {T}
    count = foldl(leaf.size; init = 1) do total, extent
        invoke(
            _checked_int_product,
            Tuple{Integer, Integer, Any},
            total,
            extent,
            Symbol(leaf.name, :_element_count),
        )
    end
    return invoke(
        _checked_int_product,
        Tuple{Integer, Integer, Any},
        count,
        sizeof(T),
        Symbol(leaf.name, :_bytes),
    )
end

function _workspace_spec_bytes(spec::Tuple)
    return foldl(spec; init = 0) do total, leaf
        invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            total,
            invoke(
                _workspace_leaf_bytes,
                Tuple{_WorkspaceLeaf},
                leaf,
            ),
            :algorithmic_workspace_bytes,
        )
    end
end

function _workspace_leaf_by_name(spec::Tuple, name::Symbol)
    index = findfirst(leaf -> leaf.name === name, spec)
    index === nothing && throw(LocalWorkValidationError(
        "algorithmic workspace specification has no leaf $name"
    ))
    return spec[index]
end

function _allocate_workspace_leaf(backend, leaf::_WorkspaceLeaf{T}) where {T}
    return KernelAbstractions.allocate(backend, T, leaf.size)
end

function _centrally_allocate_workspace_leaf(backend, leaf::_WorkspaceLeaf)
    signature = Tuple{typeof(backend), typeof(leaf)}
    method = which(_allocate_workspace_leaf, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "automatic workspace allocation is not package-owned"
    ))
    return invoke(_allocate_workspace_leaf, signature, backend, leaf)
end

function _workspace_path_children(spec::Tuple, prefix::Tuple)
    depth = length(prefix) + 1
    names = Symbol[]
    for leaf in spec
        length(leaf.path) >= depth || continue
        leaf.path[1:length(prefix)] == prefix || continue
        name = leaf.path[depth]
        name in names || push!(names, name)
    end
    return Tuple(names)
end

function _allocate_workspace_tree(backend, spec::Tuple, prefix::Tuple = ())
    names = invoke(
        _workspace_path_children,
        Tuple{Tuple, Tuple},
        spec,
        prefix,
    )
    values = map(names) do name
        path = (prefix..., name)
        exact = findall(leaf -> leaf.path == path, spec)
        descendants = any(leaf -> begin
            length(leaf.path) > length(path) &&
                leaf.path[1:length(path)] == path
        end, spec)
        if length(exact) == 1 && !descendants
            return invoke(
                _centrally_allocate_workspace_leaf,
                Tuple{Any, _WorkspaceLeaf},
                backend,
                spec[only(exact)],
            )
        elseif isempty(exact) && descendants
            return invoke(
                _allocate_workspace_tree,
                Tuple{Any, Tuple, Tuple},
                backend,
                spec,
                path,
            )
        end
        error("invalid package-owned workspace path tree")
    end
    return NamedTuple{names}(values)
end

function _allocate_algorithmic_workspace(lowering, work, backend)
    spec = invoke(
        _centrally_owned_workspace_spec,
        Tuple{Any, Any},
        lowering,
        work,
    )
    return invoke(
        _allocate_workspace_tree,
        Tuple{Any, Tuple, Tuple},
        backend,
        spec,
        (),
    )
end

function _allocate_algorithmic_workspace(
        lowering::_SequenceLowering, work, backend
    )
    stages = map(
        lowering.stages,
        work.operation.works,
    ) do stage, stage_work
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _allocate_algorithmic_workspace,
            (stage, stage_work, backend),
            :workspace_allocation,
        )
    end
    return (; stages)
end

function _automatic_workspace(
        lowering, work, backend, lease_capacity::Int
    )
    algorithmic = invoke(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _allocate_algorithmic_workspace,
        (lowering, work, backend),
        :workspace_allocation,
    )
    leases = Any[nothing for _ in 1:lease_capacity]
    return merge(algorithmic, (; leases))
end
