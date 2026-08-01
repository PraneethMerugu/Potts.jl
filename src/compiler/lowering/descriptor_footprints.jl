# Closed descriptor footprints and backend/engine support.

function _reachable_term_nodes(graph::NormalizedTermGraph, root::Int32)
    pending = Int32[root]
    seen = Set{Int32}()
    while !isempty(pending)
        node = pop!(pending)
        node in seen && continue
        push!(seen, node)
        append!(pending, graph.nodes[Int(node)].operands)
    end
    return sort!(collect(seen))
end

function _spatial_footprint_offsets(ir::AnalyzedTermIR, root::Int32)
    offsets = Tuple[]
    for index in _reachable_term_nodes(ir.graph, root)
        node = ir.graph.nodes[Int(index)]
        node.payload_kind === :spatial_relation || continue
        name = _try_symbolic_name(node.payload)
        name === nothing && continue
        text = String(name)
        prefix = "__potts_spatial_relation__"
        startswith(text, prefix) || continue
        requested = Symbol(text[(lastindex(prefix) + 1):end])
        owner = ir.source.records[Int(node.record)]
        record = _resource_record(ir.source, owner, :SpatialRelation, requested)
        record === nothing && continue
        neighborhood = get(_record_options(record), :neighborhood, nothing)
        neighborhood isa Union{VonNeumann, Moore} || continue
        matrix = _neighborhood_offsets(
            neighborhood, length(_lattice_shape(ir))
        )
        for column in axes(matrix, 2)
            push!(offsets, Tuple(matrix[:, column]))
        end
    end
    sort!(unique!(offsets))
    return Tuple(offsets)
end

function _relationship_footprint_degree(ir::AnalyzedTermIR, root::Int32)
    maximum_degree = 0
    for index in _reachable_term_nodes(ir.graph, root)
        node = ir.graph.nodes[Int(index)]
        node.payload_kind === :relationship_set || continue
        name = _try_symbolic_name(node.payload)
        name === nothing && continue
        text = String(name)
        prefix = "__potts_relationship_set__"
        startswith(text, prefix) || continue
        requested = Symbol(text[(lastindex(prefix) + 1):end])
        owner = ir.source.records[Int(node.record)]
        record = _resource_record(ir.source, owner, :RelationshipState, requested)
        record === nothing && continue
        maximum_degree = max(
            maximum_degree,
            Int(_numeric_value(get(
                _record_options(record), :maximum_degree, 0
            ))),
        )
    end
    return Int32(maximum_degree)
end

function _descriptor_footprint(
        ir::AnalyzedTermIR, root::Int32, locality::Symbol
    )
    locality === :scalar && return CorePotts.EmptyFootprint()
    locality === :site_local && return CorePotts.FiniteSpatialFootprint(())
    locality === :contact_local && return CorePotts.FiniteSpatialFootprint(())
    locality === :proposal_context &&
        return CorePotts.ProposalContextFootprint()
    locality === :owner_local && return CorePotts.OwnerFootprint()
    locality === :finite_spatial &&
        return CorePotts.FiniteSpatialFootprint(
            _spatial_footprint_offsets(ir, root)
        )
    locality === :bounded_relationship &&
        return CorePotts.IncidentRelationshipFootprint(
            _relationship_footprint_degree(ir, root)
        )
    throw(ArgumentError("unsupported descriptor locality `$locality`"))
end

function _descriptor_support(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
    )
    roots = Int.(candidate.roots)
    sequential = all(roots) do root
        any(admission ->
            admission.engine === :sequential && admission.admitted,
            ir.facts.engine_admission[root])
    end
    checkerboard = all(roots) do root
        any(admission ->
            admission.engine === :checkerboard && admission.admitted,
            ir.facts.engine_admission[root])
    end
    cpu = all(root -> ir.facts.backend_admission[root].cpu, roots)
    gpu = all(root -> ir.facts.backend_admission[root].gpu, roots)
    reason_code = UInt16(
        (!sequential ? 0x01 : 0x00) |
        (!checkerboard ? 0x02 : 0x00) |
        (!cpu ? 0x04 : 0x00) |
        (!gpu ? 0x08 : 0x00)
    )
    return CorePotts.DescriptorSupport(
        sequential,
        checkerboard,
        cpu,
        gpu,
        reason_code,
    )
end

_qualified_resource_identity(identity::QualifiedStatementID) =
    CorePotts.QualifiedResourceIdentity(
        identity.path, Symbol(identity.local_id)
    )
