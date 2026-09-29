# Algorithmic workspace is lowered once into immutable authority. Its stored
# leaf schema and exact container template jointly drive allocation,
# reconstruction, validation, byte accounting, and inspection.

struct _WorkspaceLeaf
    name::Symbol
    path::Tuple
    element_type::DataType
    dimensions::Int
    size::Tuple
    strides::Union{Nothing,Tuple}
    role::Symbol
end

struct _WorkspaceLeafSlot
    name::Symbol
end

struct _WorkspaceAuthority{L,T,S}
    leaves::L
    template::T
    alias_scopes::S
end

_WorkspaceAuthority(leaves, template) = _WorkspaceAuthority(
    leaves, template, ntuple(_ -> :global, length(leaves)))

function _workspace_leaf(
        name::Symbol,
        path::Tuple,
        ::Type{T},
        size::NTuple{N, Int};
        strides = nothing,
        role::Symbol,
    ) where {T, N}
    return _WorkspaceLeaf(
        name,
        path,
        T,
        N,
        size,
        strides,
        role,
    )
end

function _workspace_requirement_fact(
        leaf::_WorkspaceLeaf, alias_scope = :global)
    lease_scaled = leaf.role in (:relation_content_receipt, :validation_status)
    return (
        name = leaf.name,
        path = leaf.path,
        element_type = leaf.element_type,
        dimensions = leaf.dimensions,
        size = leaf.size,
        strides = leaf.strides,
        role = leaf.role,
        alias_scope,
        lifetime = lease_scaled ? :submission_lease : :prepared_plan,
        lease_scaled,
        bytes = _workspace_leaf_bytes(leaf),
    )
end

_workspace_requirement_facts(lowering) = map(
    _workspace_requirement_fact,
    lowering.workspace.leaves,
    lowering.workspace.alias_scopes,
)

function _prepared_workspace_leaf(
        leaf::_WorkspaceLeaf, lease_capacity::Int
    )
    T, N = leaf.element_type, leaf.dimensions
    if leaf.role === :relation_content_receipt
        N == 2 && leaf.size[2] == 1 || error(
            "invalid package-owned relation-content receipt schema")
        return _workspace_leaf(leaf.name, leaf.path, T,
            (leaf.size[1], lease_capacity); role = leaf.role)
    end
    leaf.role === :validation_status || return leaf
    N == 2 && leaf.size == (_VALIDATION_STATUS_FIELDS, 1) || error(
        "invalid package-owned validation status schema")
    return _workspace_leaf(
        leaf.name,
        leaf.path,
        T,
        (_VALIDATION_STATUS_FIELDS, lease_capacity);
        role = leaf.role,
    )
end

function _prepared_workspace_authority(
        authority::_WorkspaceAuthority, lease_capacity::Int
    )
    leaves = map(
        leaf -> _prepared_workspace_leaf(leaf, lease_capacity),
        authority.leaves,
    )
    return _WorkspaceAuthority(
        leaves, authority.template, authority.alias_scopes)
end

function _workspace_requirement_facts(lowering, lease_capacity::Int)
    authority = _prepared_workspace_authority(
        lowering.workspace, lease_capacity)
    return map(_workspace_requirement_fact,
        authority.leaves, authority.alias_scopes)
end

"""
    workspace_requirements(plan::Plan; lease_capacity=1)

Return the complete immutable algorithmic-workspace leaf schema used by
validation, allocation, byte accounting, and inspection. Validation-status
leaves include one column per submission lease; host submission leases are
reported separately because they are lifetime bookkeeping, not device scratch.
"""
function workspace_requirements(
        plan::Plan; lease_capacity::Integer = 1
    )
    _validate_fresh_topology(plan)
    capacity = _bounded_count(
        lease_capacity, :lease_capacity; positive = true, stage = :prepare
    )
    facts = _workspace_requirement_facts(plan.lowering, capacity)
    return (
        algorithmic = facts,
        algorithmic_bytes = foldl(
            (total, fact) -> _checked_int_sum(
                total,
                fact.bytes,
                :algorithmic_workspace_bytes,
            ),
            facts;
            init = 0,
        ),
        leases = (
            storage = Vector{Any},
            minimum_capacity = 1,
            ownership = :host_lifetime_bookkeeping,
        ),
    )
end

abstract type _WorkspaceTreeSource end
struct _WorkspaceBuffers{B} <: _WorkspaceTreeSource
    buffers::B
end
struct _WorkspaceAllocator{B} <: _WorkspaceTreeSource
    backend::B
end

# Template construction is cold structural work.  Build one insertion-ordered
# path tree without specializing Julia inference on every leaf tuple and path
# depth, then freeze it into the exact typed container used by preparation.
Base.@nospecializeinfer Base.@noinline function _freeze_workspace_template(node)
    Base.@nospecialize node
    names_buffer = Any[]
    values_buffer = Any[]
    sizehint!(names_buffer, length(node))
    sizehint!(values_buffer, length(node))
    for pair in node
        push!(names_buffer, pair.first)
        value = pair.second
        push!(values_buffer, value isa Vector{Pair{Any,Any}} ?
            _freeze_workspace_template(value) : value)
    end
    names = Tuple(names_buffer)
    values = Tuple(values_buffer)
    if all(name -> name isa Symbol, names)
        return NamedTuple{names}(values)
    end
    all(name -> name isa Integer, names) && names == Tuple(eachindex(names)) ||
        error("invalid package-owned workspace container tree")
    return values
end

Base.@nospecializeinfer Base.@noinline function _workspace_template_from_leaves(spec)
    Base.@nospecialize spec
    root = Pair{Any,Any}[]
    for leaf in spec
        isempty(leaf.path) && error("invalid empty workspace path")
        node = root
        for name in leaf.path[1:(end - 1)]
            index = findfirst(pair -> pair.first == name, node)
            if index === nothing
                child = Pair{Any,Any}[]
                push!(node, name => child)
                node = child
            else
                child = node[index].second
                child isa Vector{Pair{Any,Any}} ||
                    error("invalid package-owned workspace path tree")
                node = child
            end
        end
        name = last(leaf.path)
        findfirst(pair -> pair.first == name, node) === nothing ||
            error("invalid package-owned workspace path tree")
        push!(node, name => _WorkspaceLeafSlot(leaf.name))
    end
    return _freeze_workspace_template(root)
end

Base.@nospecializeinfer Base.@noinline function _materialize_workspace(
        template,
        authority::_WorkspaceAuthority,
        source::_WorkspaceTreeSource,
    )
    Base.@nospecialize template authority source
    if template isa _WorkspaceLeafSlot
        name = template.name
        leaf = _workspace_leaf_by_name(authority.leaves, name)
        source isa _WorkspaceBuffers &&
            return getproperty(source.buffers, name)
        source isa _WorkspaceAllocator || error(
            "invalid package-owned workspace materialization source")
        return _centrally_allocate_workspace_leaf(source.backend, leaf)
    elseif template isa NamedTuple
        names = keys(template)
        values = Any[]
        sizehint!(values, length(template))
        for value in Base.values(template)
            push!(values, _materialize_workspace(value, authority, source))
        end
        return NamedTuple{names}(Tuple(values))
    elseif template isa Tuple
        values = Any[]
        sizehint!(values, length(template))
        for value in template
            push!(values, _materialize_workspace(value, authority, source))
        end
        return Tuple(values)
    elseif template isa AbstractVector
        values = Any[]
        sizehint!(values, length(template))
        for value in template
            push!(values, _materialize_workspace(value, authority, source))
        end
        return values
    end
    error("invalid package-owned workspace template")
end


function _workspace_from_buffers(authority::_WorkspaceAuthority, buffers)
    return _materialize_workspace(
        authority.template, authority, _WorkspaceBuffers(buffers))
end

"""
    allocate_workspace(plan; lease_capacity=1, buffers=nothing)

Construct the exact caller-owned workspace accepted by `prepare`. With
`buffers=nothing`, allocate every bounded algorithmic leaf once through
`KernelAbstractions.allocate`. Otherwise `buffers` must be a named tuple whose
names exactly match `workspace_requirements(plan).algorithmic`; supplied
arrays are validated and no algorithmic array is allocated.
"""
function allocate_workspace(
        plan::Plan;
        lease_capacity::Integer = 1,
        buffers::Union{Nothing, NamedTuple} = nothing,
    )
    _validate_fresh_topology(plan)
    capacity = _bounded_count(
        lease_capacity,
        :lease_capacity;
        stage = :prepare,
    )
    capacity > 0 || throw(LocalMathValidationError(
        "lease_capacity must be positive";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases,
        expected = :positive, actual = capacity,
    ))
    workspace = if buffers === nothing
        _automatic_workspace(
            plan.lowering,
            plan.backend,
            capacity,
        )
    else
        authority = _prepared_workspace_authority(
            plan.lowering.workspace, capacity
        )
        requirements = map(_workspace_requirement_fact,
            authority.leaves, authority.alias_scopes)
        expected = Tuple(fact.name for fact in requirements)
        actual = Tuple(keys(buffers))
        expected == actual || throw(LocalMathValidationError(
            "caller workspace buffer names do not match the Plan";
            stage = :prepare, contract = :workspace_binding_names,
            expected, actual,
            hint = "use the ordered names from workspace_requirements(plan)",
        ))
        algorithmic = _workspace_from_buffers(authority, buffers)
        merge(algorithmic, (; leases = Any[nothing for _ in 1:capacity]))
    end
    _validate_workspace(
        plan.lowering, workspace, plan.backend, capacity
    )
    return workspace
end

function _workspace_leaf_value(workspace, leaf::_WorkspaceLeaf)
    value = workspace
    for name in leaf.path
        if name isa Integer
            value isa Union{Tuple,AbstractVector} &&
                1 <= name <= length(value) || throw(
                LocalMathValidationError(
                    "workspace path $(join(string.(leaf.path), '.')) has no tuple index $name";
                    stage = :prepare,
                    contract = :workspace_leaf_presence,
                    workspace_leaf = leaf.name,
                    expected = leaf.path,
                    actual = typeof(value),
                )
            )
            value = value[name]
        else
            hasproperty(value, name) || throw(LocalMathValidationError(
                "workspace path $(join(string.(leaf.path), '.')) is missing $name";
                stage = :prepare, contract = :workspace_leaf_presence,
                workspace_leaf = leaf.name,
                expected = leaf.path, actual = propertynames(value),
            ))
            value = getproperty(value, name)
        end
    end
    return value
end

function _validate_workspace_leaf(workspace, leaf::_WorkspaceLeaf, backend)
    T, N = leaf.element_type, leaf.dimensions
    array = _workspace_leaf_value(
        workspace,
        leaf,
    )
    array isa AbstractArray || throw(LocalMathValidationError(
        "workspace $(leaf.name) must be an array";
        stage = :prepare, contract = :workspace_leaf_kind,
        workspace_leaf = leaf.name,
        expected = AbstractArray, actual = typeof(array),
    ))
    eltype(array) === T || throw(LocalMathValidationError(
        "workspace $(leaf.name) must have element type $T";
        stage = :prepare, contract = :workspace_leaf_element_type,
        workspace_leaf = leaf.name, expected = T, actual = eltype(array),
    ))
    ndims(array) == N && size(array) == leaf.size || throw(
        LocalMathValidationError(
            "workspace $(leaf.name) must have exact size $(leaf.size)";
            stage = :prepare, contract = :workspace_leaf_shape,
            workspace_leaf = leaf.name,
            expected = leaf.size, actual = size(array),
        )
    )
    leaf.strides === nothing || _array_strides(array) == leaf.strides || throw(
        LocalMathValidationError(
            "workspace $(leaf.name) must have exact strides $(leaf.strides)";
            stage = :prepare, contract = :workspace_leaf_strides,
            workspace_leaf = leaf.name,
            expected = leaf.strides, actual = _array_strides(array),
        )
    )
    _validate_array_backend(
        array,
        backend,
        leaf.name,
    )
    return array
end

_workspace_alias_scopes_conflict(first, second) =
    first === :persistent || second === :persistent || first == second

function _validate_workspace_spec(workspace, spec, backend,
        alias_scopes = ntuple(_ -> :global, length(spec)))
    Base.@nospecialize workspace spec backend alias_scopes
    length(alias_scopes) == length(spec) || error(
        "workspace authority alias-scope arity mismatch")
    arrays = Any[]
    sizehint!(arrays, length(spec))
    for leaf in spec
        push!(arrays, _validate_workspace_leaf(workspace, leaf, backend))
    end
    for first_index in eachindex(arrays), second_index in eachindex(arrays)
        first_index < second_index || continue
        _workspace_alias_scopes_conflict(
            alias_scopes[first_index], alias_scopes[second_index]) || continue
        Base.mightalias(arrays[first_index], arrays[second_index]) && throw(
            LocalMathValidationError(
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


function _validate_workspace_container(
    value, slot::_WorkspaceLeafSlot, path::Tuple
)
    value isa AbstractArray || throw(LocalMathValidationError(
        "workspace container path $(join(string.(path), '.')) must terminate in an array";
        stage = :prepare,
        contract = :workspace_container_tree,
        workspace_leaf = slot.name,
        expected = AbstractArray,
        actual = typeof(value),
    ))
    return nothing
end

function _validate_workspace_container(
        value, template::NamedTuple, path::Tuple
    )
    Base.@nospecialize value template path
    value isa NamedTuple && keys(value) == keys(template) || throw(
        LocalMathValidationError(
            "workspace named container $(join(string.(path), '.')) has the wrong exact fields";
            stage = :prepare,
            contract = :workspace_container_tree,
            expected = keys(template),
            actual = value isa NamedTuple ? keys(value) : typeof(value),
        )
    )
    for name in keys(template)
        _validate_workspace_container(
            getproperty(value, name),
            getproperty(template, name),
            (path..., name),
        )
    end
    return nothing
end

function _validate_workspace_container(
        value, template::Tuple, path::Tuple
    )
    Base.@nospecialize value template path
    value isa Tuple && length(value) == length(template) || throw(
        LocalMathValidationError(
            "workspace tuple container $(join(string.(path), '.')) has the wrong exact length";
            stage = :prepare,
            contract = :workspace_container_tree,
            expected = length(template),
            actual = value isa Tuple ? length(value) : typeof(value),
        )
    )
    for index in eachindex(template)
        _validate_workspace_container(
            value[index], template[index], (path..., index)
        )
    end
    return nothing
end

function _validate_workspace_container(
        value, template::AbstractVector, path::Tuple
    )
    Base.@nospecialize value template path
    value isa AbstractVector && length(value) == length(template) || throw(
        LocalMathValidationError(
            "workspace sequence $(join(string.(path), '.')) has the wrong exact length";
            stage = :prepare, contract = :workspace_container_tree,
            expected = length(template),
            actual = value isa AbstractVector ? length(value) : typeof(value),
        )
    )
    for index in eachindex(template)
        _validate_workspace_container(
            value[index], template[index], (path..., index)
        )
    end
    return nothing
end

function _validate_workspace_authority(
        workspace, authority::_WorkspaceAuthority, backend
    )
    Base.@nospecialize workspace authority backend
    template = authority.template
    expected = (keys(template)..., :leases)
    workspace isa NamedTuple && keys(workspace) == expected || throw(
        LocalMathValidationError(
            "workspace root has the wrong exact container fields";
            stage = :prepare,
            contract = :workspace_container_tree,
            expected,
            actual = workspace isa NamedTuple ? keys(workspace) :
                typeof(workspace),
        )
    )
    algorithmic = NamedTuple{keys(template)}(map(
        name -> getproperty(workspace, name), keys(template)
    ))
    _validate_workspace_container(algorithmic, template, ())
    return _validate_workspace_spec(
        workspace, authority.leaves, backend, authority.alias_scopes)
end

function _validate_workspace(lowering, workspace, backend,
        lease_capacity::Int)
    authority = _prepared_workspace_authority(
        lowering.workspace, lease_capacity)
    _validate_workspace_authority(workspace, authority, backend)
    leases = _workspace_leases(workspace)
    length(leases) == lease_capacity || throw(LocalMathValidationError(
        "workspace lease capacity disagrees with its algorithmic authority";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases,
        expected = lease_capacity, actual = length(leases),
    ))
    return nothing
end

function _typed_workspace_arrays(
    value, slot::_WorkspaceLeafSlot
)
    return (slot.name => value,)
end

function _typed_workspace_arrays(workspace::NamedTuple, template::NamedTuple)
    parts = map(_typed_workspace_arrays, values(workspace), values(template))
    return foldl((left, right) -> (left..., right...), parts; init = ())
end

function _typed_workspace_arrays(workspace::Tuple, template::Tuple)
    parts = map(_typed_workspace_arrays, workspace, template)
    return foldl((left, right) -> (left..., right...), parts; init = ())
end

function _typed_workspace_arrays(
        workspace::AbstractVector, template::AbstractVector)
    parts = map(_typed_workspace_arrays, workspace, template)
    return foldl((left, right) -> (left..., right...), parts; init = ())
end

function _workspace_leaf_bytes(leaf::_WorkspaceLeaf)
    count = foldl(leaf.size; init = 1) do total, extent
        _checked_int_product(
            total,
            extent,
            Symbol(leaf.name, :_element_count),
        )
    end
    return _checked_int_product(
        count,
        sizeof(leaf.element_type),
        Symbol(leaf.name, :_bytes),
    )
end

function _workspace_leaf_by_name(spec, name::Symbol)
    index = findfirst(leaf -> leaf.name === name, spec)
    index === nothing && throw(LocalMathValidationError(
        "algorithmic workspace specification has no leaf $name"
    ))
    return spec[index]
end

function _workspace_leaf_by_suffix(spec, suffix::Tuple)
    index = findfirst(spec) do leaf
        depth = length(suffix)
        length(leaf.path) >= depth &&
            leaf.path[(end - depth + 1):end] == suffix
    end
    index === nothing && throw(LocalMathValidationError(
        "algorithmic workspace specification has no path suffix $suffix"
    ))
    return spec[index]
end

function _allocate_workspace_leaf(backend, leaf::_WorkspaceLeaf)
    return KernelAbstractions.allocate(backend, leaf.element_type, leaf.size)
end

function _centrally_allocate_workspace_leaf(backend, leaf::_WorkspaceLeaf)
    return _allocate_workspace_leaf(backend, leaf)
end

function _allocate_algorithmic_workspace(
        lowering, backend, lease_capacity::Int)
    authority = _prepared_workspace_authority(
        lowering.workspace, lease_capacity
    )
    return _materialize_workspace(
        authority.template, authority, _WorkspaceAllocator(backend))
end

function _automatic_workspace(lowering, backend, lease_capacity::Int)
    algorithmic = _allocate_algorithmic_workspace(
        lowering, backend, lease_capacity
    )
    leases = Any[nothing for _ in 1:lease_capacity]
    return merge(algorithmic, (; leases))
end
