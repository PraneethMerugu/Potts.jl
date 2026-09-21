# Compiler-owned resolution and admission of public tracker requirements.

function _site_sum_tolerances(ir, fact, manifest, ::Type{T}) where {T}
    absolute = ir.graph.nodes[Int(first(fact.policy_indices))].payload.value
    relative = ir.graph.nodes[Int(last(fact.policy_indices))].payload.value
    return (;
        absolute_tolerance = T(_numeric_value(absolute, _reference_for(manifest.reference_units, absolute))),
        relative_tolerance = T(_numeric_value(relative, _reference_for(manifest.reference_units, relative))),
    )
end

function _site_sum_identity(ir, fact, manifest, ::Type{T}) where {T}
    return _canonical_value(
        (
            :site_sum, ir.graph.nodes[Int(fact.contribution)].structural_key,
            fact.site, ir.facts.shape[Int(fact.contribution)],
            ir.facts.units[Int(fact.contribution)], T,
            _site_sum_tolerances(ir, fact, manifest, T),
        )
    )
end

function _site_sum_descriptor(
        ir, node, fact, key, manifest, ::Type{T}, state_handles, draw_handles;
        state_layout, history_descriptors, canonicalization_cache,
    ) where {T <: AbstractFloat}
    result_type = ir.facts.result_type[Int(fact.contribution)]
    element_type = result_type <: AbstractArray ? eltype(result_type) : result_type
    (element_type === Real || element_type <: AbstractFloat) ||
        throw(
        PottsValidationError(
            :descriptor_lowering, (
                PottsDiagnostic(
                    :aggregate_value_type, node.source, String(node.operation), node.source.path,
                    "a floating contribution, or literal integer one for exact unit-site count",
                    repr(result_type), (), ir.source.records[node.record].source
                ),
            )
        )
    )
    expression = _lower_static_node(
        ir.graph, ir, fact.contribution, manifest, T, state_handles, draw_handles,
        Dict{Int32, CorePotts.CompilerSPI.AbstractStaticExpression}(),
        CorePotts.CompilerSPI.IterationStageSite(); state_layout, history_descriptors,
        canonicalization_cache,
    )
    shape = ir.facts.shape[Int(fact.contribution)]
    shape isa Tuple && all(size -> size isa Integer && !(size isa Bool) && size > 0, shape) ||
        throw(
        PottsValidationError(
            :descriptor_lowering, (
                PottsDiagnostic(
                    :aggregate_value_shape, node.source, String(node.operation), node.source.path,
                    "a scalar or a nonempty fixed logical array shape", repr(shape), (),
                    ir.source.records[node.record].source
                ),
            )
        )
    )
    value_type = isempty(shape) ? T : StaticArrays.SArray{Tuple{shape...}, T, length(shape), prod(shape)}
    return CorePotts.CompilerSPI.SiteSumTracker(
        value_type, key, expression;
        _site_sum_tolerances(ir, fact, manifest, T)...,
    )
end

function _site_minimum_identity(ir, fact, manifest, ::Type{T}) where {T}
    empty = ir.graph.nodes[Int(first(fact.policy_indices))].payload.value
    maximum_sites = ir.graph.nodes[Int(last(fact.policy_indices))].payload.value
    return _canonical_value(
        (
            :site_minimum, ir.graph.nodes[Int(fact.contribution)].structural_key,
            fact.site, ir.facts.shape[Int(fact.contribution)],
            ir.facts.units[Int(fact.contribution)], T,
            T(_numeric_value(empty, _reference_for(manifest.reference_units, empty))),
            maximum_sites,
        )
    )
end

_site_aggregate_identity(ir, fact, manifest, ::Type{T}) where {T} =
    fact.law === :sum ? _site_sum_identity(ir, fact, manifest, T) :
    _site_minimum_identity(ir, fact, manifest, T)

function _site_aggregate_layout_identity(
        ir,
        fact,
        ::Type{T},
        canonicalization_cache::_OperationalCanonicalizationCache,
    ) where {T}
    contribution = Int(fact.contribution)
    return _sha256_hex(
        "potts-site-aggregate-layout-v1",
        fact.law,
        ir.facts.shape[contribution],
        ir.facts.result_type[contribution],
        T,
        _operational_expression_shape_key(
            ir.graph, ir, fact.contribution, canonicalization_cache,
        ),
    )
end

function _site_minimum_descriptor(
        ir, node, fact, key, manifest, ::Type{T}, state_handles, draw_handles;
        state_layout, history_descriptors, canonicalization_cache,
    ) where {T <: AbstractFloat}
    T === Float32 || throw(PottsValidationError(
        :descriptor_lowering, (
            PottsDiagnostic(
                :aggregate_value_type, node.source, String(node.operation), node.source.path,
                "a scalar Float32 contribution", repr(T), (),
                ir.source.records[node.record].source
            ),
        )
    ))
    isempty(ir.facts.shape[Int(fact.contribution)]) || throw(PottsValidationError(
        :descriptor_lowering, (
            PottsDiagnostic(
                :aggregate_value_shape, node.source, String(node.operation), node.source.path,
                "a scalar contribution", repr(ir.facts.shape[Int(fact.contribution)]), (),
                ir.source.records[node.record].source
            ),
        )
    ))
    expression = _lower_static_node(
        ir.graph, ir, fact.contribution, manifest, T, state_handles, draw_handles,
        Dict{Int32, CorePotts.CompilerSPI.AbstractStaticExpression}(),
        CorePotts.CompilerSPI.IterationStageSite(); state_layout, history_descriptors,
        canonicalization_cache,
    )
    empty = ir.graph.nodes[Int(first(fact.policy_indices))].payload.value
    maximum_sites = ir.graph.nodes[Int(last(fact.policy_indices))].payload.value
    required_sites = prod(_lattice_shape(ir))
    maximum_sites >= required_sites || throw(PottsValidationError(
        :descriptor_lowering, (
            PottsDiagnostic(
                :aggregate_reconstruction_bound, node.source,
                String(node.operation), node.source.path,
                "maximum_sites of at least $required_sites for the declared lattice",
                repr(maximum_sites), (), ir.source.records[node.record].source,
            ),
        )
    ))
    empty_value = T(_numeric_value(empty, _reference_for(manifest.reference_units, empty)))
    return CorePotts.CompilerSPI.SiteMinimumTracker(
        Float32, key, expression;
        maximum_sites, empty = empty_value,
    )
end

_site_aggregate_descriptor(
    ir, node, fact, key, manifest, ::Type{T}, state_handles, draw_handles;
    state_layout, history_descriptors, canonicalization_cache,
) where {T <: AbstractFloat} = fact.law === :sum ?
    _site_sum_descriptor(
        ir, node, fact, key, manifest, T, state_handles, draw_handles;
        state_layout, history_descriptors, canonicalization_cache,
    ) :
    _site_minimum_descriptor(
        ir, node, fact, key, manifest, T, state_handles, draw_handles;
        state_layout, history_descriptors, canonicalization_cache,
    )

function _operation_tracker_context(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        transfer = node.transfer,
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
                    "operation tracker binding requires a finite neighborhood"
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
        transfer.identity,
        transfer.schema_version,
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
        "surface relation degree exceeds the configured tracker bound"
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
    tracker_source = _tracker_projection_operand(node, ir.graph)
    tracker_node = tracker_source === nothing ? node : tracker_source
    # Site expressions need the canonical layout and parameter manifest. They
    # are constructed once by the same tracker-plan owner below.
    _is_site_aggregate(tracker_node) && return ()
    transfer = tracker_node.transfer
    transfer === nothing && return ()
    isempty(transfer.tracker_requirements) && return ()
    context = _operation_tracker_context(ir, tracker_node, transfer)
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
    keys = map(
        CorePotts.CompilerSPI.tracker_quantity,
        _operation_tracker_descriptors(ir, node, T),
    )
    tracker_source = _tracker_projection_operand(node, ir.graph)
    tracker_source === nothing && return keys
    transfer = tracker_source.transfer
    isempty(keys) && transfer.identity === :cell_volume &&
        return (Val(:cell_volume),)
    return keys
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
        "host execution requires CPU tracker support"
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

function _lower_site_aggregate_trackers(
        ir::AnalyzedTermIR,
        manifest,
        ::Type{T},
        state_handles,
        draw_handles;
        state_layout,
        history_descriptors,
    ) where {T <: AbstractFloat}
    # Canonical identities deduplicate equivalent quantities during lowering;
    # consumers use the analyzed node-aligned handle table and never repeat
    # aggregate source interpretation.
    contributions = Dict{String, Tuple{NormalizedTermNode, AnalyzedSiteAggregate}}()
    canonicalization_cache = _OperationalCanonicalizationCache(
        length(ir.graph.nodes),
    )
    identity_by_node = Union{Nothing, String}[nothing for _ in ir.graph.nodes]
    for node in ir.graph.nodes
        fact = ir.facts.site_aggregate[Int(node.identity)]
        fact isa AnalyzedSiteAggregate || continue
        _is_unit_count(ir.graph, node) && continue
        identity = _site_aggregate_identity(ir, fact, manifest, T)
        identity_by_node[Int(node.identity)] = identity
        get!(contributions, identity, (node, fact))
    end

    ordered = Tuple{
        String,
        String,
        NormalizedTermNode,
        AnalyzedSiteAggregate,
    }[]
    for (identity, (node, fact)) in contributions
        layout_identity = _site_aggregate_layout_identity(
            ir, fact, T, canonicalization_cache,
        )
        push!(ordered, (layout_identity, identity, node, fact))
    end
    # Qualified scientific identity remains a host value for deduplication,
    # diagnostics, and checkpoint fingerprints. Physical tuple order is grouped
    # first by the explicit operational law, value shape/type, scalar type, and
    # expression topology. Author-sensitive identity only orders descriptors
    # that share that execution layout.
    sort!(ordered; by = item -> (item[1], item[2]))

    descriptors = CorePotts.CompilerSPI.AbstractTrackerDescriptor[]
    tracker_handles_by_identity = Dict{
        String, CorePotts.CompilerSPI.QualifiedTrackerKey,
    }()
    for (index, (_, identity, node, fact)) in enumerate(ordered)
        law = fact.law === :sum ? :site_sum : :site_minimum
        key = CorePotts.CompilerSPI.QualifiedTrackerKey(Val(law), index)
        tracker_handles_by_identity[identity] = key
        descriptor = _site_aggregate_descriptor(
            ir, node, fact, key, manifest, T, state_handles, draw_handles;
            state_layout, history_descriptors, canonicalization_cache,
        )
        _append_tracker_requirement!(descriptors, descriptor)
    end
    tracker_handles = Union{
        Nothing,
        CorePotts.CompilerSPI.QualifiedTrackerKey{Val{:site_sum}},
        CorePotts.CompilerSPI.QualifiedTrackerKey{Val{:site_minimum}},
    }[
        identity === nothing ? nothing : tracker_handles_by_identity[identity]
        for identity in identity_by_node
    ]
    return (; descriptors, handles = tracker_handles)
end

function _lower_tracker_plan(
        ir::AnalyzedTermIR,
        engine::AbstractPottsAlgorithm,
        ::Type{T},
        manifest, state_handles, draw_handles;
        state_layout, history_descriptors,
    ) where {T <: AbstractFloat}
    shape = _lattice_shape(ir)
    descriptors = CorePotts.CompilerSPI.AbstractTrackerDescriptor[]
    _append_tracker_requirement!(
        descriptors, CorePotts.CompilerSPI.OwnershipCountTracker()
    )

    aggregates = _lower_site_aggregate_trackers(
        ir, manifest, T, state_handles, draw_handles;
        state_layout, history_descriptors,
    )
    foreach(
        descriptor -> _append_tracker_requirement!(descriptors, descriptor),
        aggregates.descriptors,
    )

    if any(ir.graph.nodes) do node
            transfer = node.transfer
            transfer !== nothing && transfer.identity === :cell_elongation
        end
        length(shape) == 2 || throw(ArgumentError(
            "cell elongation is qualified only for two-dimensional lattices"
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
    plan = CorePotts.CompilerSPI.TrackerExecutionPlan(_group_tracker_instances(ordered), fingerprint)
    return (; plan, handles = aggregates.handles)
end
