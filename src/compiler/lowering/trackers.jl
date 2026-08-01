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
        ::Val{:cell_moments}, shape, ::Type{T}
    ) where {T <: AbstractFloat}
    return CorePotts.CellMomentsTracker{length(shape), T}()
end

function _builtin_tracker_requirement(
        ::Val{Identity}, shape, ::Type{T}
    ) where {Identity, T <: AbstractFloat}
    throw(ArgumentError(
        "no V1 tracker descriptor exists for operation requirement `$Identity`"
    ))
end

function _append_tracker_requirement!(descriptors, descriptor)
    descriptor isa CorePotts.AbstractTrackerDescriptor || throw(ArgumentError(
        "registered tracker requirements must be AbstractTrackerDescriptor values"
    ))
    quantity = CorePotts.tracker_quantity(descriptor)
    quantity isa Val || throw(ArgumentError(
        "registered tracker quantities must be Val identities"
    ))
    index = findfirst(
        existing -> typeof(CorePotts.tracker_quantity(existing)) ===
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
    support = CorePotts.tracker_support(descriptor)
    support isa CorePotts.TrackerSupport || throw(ArgumentError(
        "tracker_support must return CorePotts.TrackerSupport"
    ))
    admitted = engine isa SequentialEngine ?
               support.sequential : support.checkerboard
    admitted || throw(ArgumentError(
        "tracker $(CorePotts.tracker_quantity(descriptor)) does not support " *
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
            _builtin_tracker_requirement(Val(requirement), shape, T),
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
        map(CorePotts.tracker_quantity, ordered),
        map(CorePotts.tracker_inspection, ordered),
        map(CorePotts.tracker_support, ordered),
        map(CorePotts.tracker_concurrency, ordered),
        map(CorePotts.tracker_checkpoint_policy, ordered),
    )
    return CorePotts.TrackerExecutionPlan(ordered, fingerprint)
end
