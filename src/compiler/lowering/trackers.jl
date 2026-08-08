# Compiler-owned resolution and admission of public tracker requirements.

function _operation_tracker_context(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
    )
    bindings = map(ir.facts.source_bindings[Int(node.identity)]) do binding
        handle = findfirst(
            record -> record.identity == binding.identity,
            ir.source.records,
        )
        handle === nothing && error(
            "analyzed operation source binding has no runtime handle"
        )
        record = ir.source.records[handle]
        metadata = if binding.kind === :SpatialRelation
            neighborhood = get(
                _record_options(record), :neighborhood, nothing
            )
            offsets = neighborhood isa Union{VonNeumann, Moore} ?
                _host_neighborhood_offsets(neighborhood, length(_lattice_shape(ir))) :
                throw(ArgumentError(
                    "operation tracker binding requires a finite V1 neighborhood"
                ))
            (
                neighborhood,
                maximum_neighbors = Int16(length(offsets)),
            )
        else
            NamedTuple()
        end
        ResolvedOperationSourceBinding(
            binding.requirement_index,
            binding.kind,
            binding.identity,
            Int32(handle),
            metadata,
        )
    end
    record = ir.source.records[Int(node.record)]
    return OperationTrackerContext(
        node.operation,
        node.transfer.schema_version,
        _descriptor_source(record),
        bindings,
    )
end

function registered_operation_tracker_requirements(
        ::Val{:cell_moments},
        context::OperationTrackerContext,
        ::Type{T},
        shape::Tuple,
    ) where {T <: AbstractFloat}
    return (CorePotts.CompilerSPI.CellMomentsTracker{length(shape), T}(),)
end

function registered_operation_tracker_requirements(
        ::Val{:cell_surface},
        context::OperationTrackerContext,
        ::Type{T},
        shape::Tuple,
    ) where {T <: AbstractFloat}
    relations = filter(
        binding -> binding.kind === :SpatialRelation,
        context.bindings,
    )
    length(relations) == 1 || throw(ArgumentError(
        "cell_surface requires one analyzed qualified spatial relation binding"
    ))
    relation = only(relations)
    maximum_neighbors = relation.metadata.maximum_neighbors
    maximum_neighbors > 0 || throw(ArgumentError(
        "surface relation degree exceeds the V1 tracker bound"
    ))
    return (CorePotts.CompilerSPI.CellSurfaceTracker(
        relation.handle, maximum_neighbors
    ),)
end

function registered_operation_tracker_requirements(
        ::Val{Identity},
        context::OperationTrackerContext,
        ::Type,
        ::Tuple,
    ) where {Identity}
    throw(ArgumentError(
        "no registered tracker constructor exists for operation requirement " *
        repr(Identity)
    ))
end

function _operation_tracker_descriptors(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        ::Type{T},
    ) where {T <: AbstractFloat}
    transfer = node.transfer
    transfer === nothing && return ()
    isempty(transfer.tracker_requirements) && return ()
    context = _operation_tracker_context(ir, node)
    shape = _lattice_shape(ir)
    descriptors = ()
    for requirement in transfer.tracker_requirements
        resolved = registered_operation_tracker_requirements(
            Val(requirement), context, T, shape
        )
        resolved isa Tuple || throw(ArgumentError(
            "registered operation tracker requirements must return a tuple"
        ))
        descriptors = (descriptors..., resolved...)
    end
    return descriptors
end

function _operation_tracker_keys(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        ::Type{T},
    ) where {T <: AbstractFloat}
    return map(
        CorePotts.CompilerSPI.tracker_quantity,
        _operation_tracker_descriptors(ir, node, T),
    )
end

function _append_tracker_requirement!(descriptors, descriptor)
    descriptor isa CorePotts.CompilerSPI.AbstractTrackerDescriptor || throw(ArgumentError(
        "registered tracker requirements must be AbstractTrackerDescriptor values"
    ))
    contract = CorePotts.CompilerSPI.tracker_contract(descriptor)
    contract isa CorePotts.CompilerSPI.TrackerContract || throw(ArgumentError(
        "registered trackers must provide a closed TrackerContract"
    ))
    quantity = CorePotts.CompilerSPI.tracker_quantity(descriptor)
    index = findfirst(
        existing -> isequal(
            CorePotts.CompilerSPI.tracker_quantity(existing), quantity
        ),
        descriptors,
    )
    if index === nothing
        push!(descriptors, descriptor)
    elseif typeof(descriptors[index]) !== typeof(descriptor) ||
            !isequal(descriptors[index], descriptor)
        throw(ArgumentError(
            "conflicting tracker descriptors claim quantity $quantity"
        ))
    end
    return descriptors
end

function _validate_tracker_engine_support(descriptor, engine)
    contract = CorePotts.CompilerSPI.tracker_contract(descriptor)
    support = contract.support
    admitted = engine isa SequentialCPM ?
               support.sequential : support.checkerboard
    admitted || throw(ArgumentError(
        "tracker $(contract.quantity) does not support " *
        "$(nameof(typeof(engine))) (reason code $(support.reason_code))"
    ))
    support.cpu || throw(ArgumentError(
        "V1 host execution requires CPU tracker support"
    ))
    return descriptor
end

function _group_tracker_instances(ordered::Tuple)
    grouped = Any[]
    scalar_groups = Dict{DataType, Int}()
    for descriptor in ordered
        key = CorePotts.CompilerSPI.tracker_quantity(descriptor)
        storage = CorePotts.CompilerSPI.tracker_contract(descriptor).storage
        if key isa CorePotts.CompilerSPI.QualifiedTrackerKey &&
                storage isa CorePotts.CompilerSPI.DenseOwnerScalarStorage
            descriptor_type = typeof(descriptor)
            index = get(scalar_groups, descriptor_type, 0)
            if index == 0
                push!(grouped, CorePotts.CompilerSPI.DenseScalarTrackerGroup(
                    descriptor_type[descriptor]
                ))
                scalar_groups[descriptor_type] = length(grouped)
            else
                push!(grouped[index].descriptors, descriptor)
                push!(grouped[index].source_handles, key.source_handle)
            end
        else
            push!(grouped, descriptor)
        end
    end
    return Tuple(grouped)
end

function _lower_tracker_plan(
        ir::AnalyzedTermIR,
        engine::AbstractPottsAlgorithm,
        ::Type{T},
    ) where {T <: AbstractFloat}
    shape = _lattice_shape(ir)
    descriptors = CorePotts.CompilerSPI.AbstractTrackerDescriptor[]
    _append_tracker_requirement!(
        descriptors, CorePotts.CompilerSPI.OwnershipCountTracker()
    )

    if any(ir.graph.nodes) do node
            transfer = node.transfer
            transfer !== nothing && transfer.identity === :cell_elongation
        end
        length(shape) == 2 || throw(ArgumentError(
            "V1 cell elongation is qualified only for two-dimensional lattices"
        ))
    end
    for node in ir.graph.nodes
        for descriptor in _operation_tracker_descriptors(ir, node, T)
            _append_tracker_requirement!(descriptors, descriptor)
        end
    end

    lifecycle_moments = any(ir.source.records) do record
        record.kind === :LifecycleProcess || return false
        arguments = first(record.normalized_payload)
        length(arguments.effects) == 1 || return false
        effect = only(arguments.effects)
        effect isa Divide || return false
        geometry = effect.geometry
        geometry isa PrincipalAxisPlane ||
            hasproperty(geometry, :point) && geometry.point isa CellCentroid
    end
    lifecycle_moments && _append_tracker_requirement!(
        descriptors, CorePotts.CompilerSPI.CellMomentsTracker{length(shape), T}()
    )

    for candidate in ir.candidates
        candidate.category in (
            :hamiltonian, :drive, :constraint, :modifier,
        ) || continue
        record = ir.source.records[candidate.record]
        _descriptor_candidate_enabled(record) || continue
        requirements = registered_tracker_requirements(
            Val(_effective_descriptor_identity(record)),
            _descriptor_source(record),
            T,
            shape,
        )
        requirements isa Tuple || throw(ArgumentError(
            "registered_tracker_requirements must return a tuple"
        ))
        for descriptor in requirements
            _append_tracker_requirement!(descriptors, descriptor)
        end
    end

    ordered = Tuple(descriptors)
    foreach(
        descriptor -> _validate_tracker_engine_support(descriptor, engine),
        ordered,
    )
    fingerprint = _sha256_hex(
        "potts-tracker-plan-v2",
        map(CorePotts.CompilerSPI.tracker_quantity, ordered),
        map(CorePotts.CompilerSPI.tracker_inspection, ordered),
        map(CorePotts.CompilerSPI.tracker_contract, ordered),
    )
    return CorePotts.CompilerSPI.TrackerExecutionPlan(
        _group_tracker_instances(ordered), fingerprint
    )
end
