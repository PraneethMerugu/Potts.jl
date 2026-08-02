# Compiler-owned inference and admission of generic derived-state trackers.

function _normalized_graph_tracker_requirements(ir::AnalyzedTermIR)
    requirements = Symbol[]
    for node in ir.graph.nodes
        transfer = node.transfer
        transfer === nothing && continue
        append!(requirements, transfer.tracker_requirements)
    end
    sort!(unique!(requirements))
    return requirements
end

function _builtin_tracker_requirement(
        ::Val{:cell_moments}, ir, shape, ::Type{T}
    ) where {T <: AbstractFloat}
    return CorePotts.CellMomentsTracker{length(shape), T}()
end

function _builtin_tracker_requirement(
        ::Val{:cell_surface}, ir, shape, ::Type{T}
    ) where {T <: AbstractFloat}
    relations = QualifiedStatement[]
    for node in ir.graph.nodes
        node.operation === :cell_surface || continue
        owner = ir.source.records[Int(node.record)]
        relation = _resource_record(
            ir.source, owner, :SpatialRelation, :surface
        )
        relation === nothing && error(
            "analyzed cell_surface operation lost its required relation"
        )
        any(existing -> existing.identity == relation.identity, relations) ||
            push!(relations, relation)
    end
    length(relations) == 1 || throw(ArgumentError(
        "V1 cell_surface operations must resolve to one qualified surface relation"
    ))
    relation = only(relations)
    handle = findfirst(
        candidate -> candidate.identity == relation.identity,
        ir.source.records,
    )
    handle === nothing && error("resolved surface relation has no source handle")
    neighborhood = get(_record_options(relation), :neighborhood, nothing)
    offsets = neighborhood isa VonNeumann ?
              _host_neighborhood_offsets(neighborhood, length(shape)) :
              neighborhood isa Moore ?
              _host_neighborhood_offsets(neighborhood, length(shape)) :
              throw(ArgumentError(
                  "surface tracker requires a finite V1 neighborhood"
              ))
    0 < length(offsets) <= typemax(Int16) || throw(ArgumentError(
        "surface relation degree exceeds the V1 tracker bound"
    ))
    return CorePotts.CellSurfaceTracker(Int32(handle), Int16(length(offsets)))
end

function _builtin_tracker_requirement(
        ::Val{Identity}, ir, shape, ::Type{T}
    ) where {Identity, T <: AbstractFloat}
    throw(ArgumentError(
        "no V1 tracker descriptor exists for operation requirement `$Identity`"
    ))
end

function _append_tracker_requirement!(descriptors, descriptor)
    descriptor isa CorePotts.AbstractTrackerDescriptor || throw(ArgumentError(
        "registered tracker requirements must be AbstractTrackerDescriptor values"
    ))
    contract = CorePotts.tracker_contract(descriptor)
    contract isa CorePotts.TrackerContract || throw(ArgumentError(
        "registered trackers must provide a closed TrackerContract"
    ))
    quantity = contract.quantity
    index = findfirst(
        existing -> typeof(CorePotts.tracker_contract(existing).quantity) ===
                    typeof(quantity),
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
    contract = CorePotts.tracker_contract(descriptor)
    support = contract.support
    admitted = engine isa SequentialEngine ?
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

function _lower_tracker_plan(
        ir::AnalyzedTermIR,
        engine::AbstractPottsEngine,
        ::Type{T},
    ) where {T <: AbstractFloat}
    shape = _lattice_shape(ir)
    descriptors = CorePotts.AbstractTrackerDescriptor[]
    _append_tracker_requirement!(
        descriptors, CorePotts.OwnershipCountTracker()
    )

    if any(ir.graph.nodes) do node
            transfer = node.transfer
            transfer !== nothing && transfer.identity === :cell_elongation
        end
        length(shape) == 2 || throw(ArgumentError(
            "V1 cell elongation is qualified only for two-dimensional lattices"
        ))
    end
    for requirement in _normalized_graph_tracker_requirements(ir)
        _append_tracker_requirement!(
            descriptors,
            _builtin_tracker_requirement(Val(requirement), ir, shape, T),
        )
    end

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
        map(descriptor -> CorePotts.tracker_contract(descriptor).quantity, ordered),
        map(CorePotts.tracker_inspection, ordered),
        map(CorePotts.tracker_contract, ordered),
    )
    return CorePotts.TrackerExecutionPlan(ordered, fingerprint)
end
