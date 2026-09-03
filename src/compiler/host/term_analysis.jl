# Fact propagation and construction of the analyzed compiler authority.
function _analyze_term_graph(
        source::FrozenSourceGraph,
        graph::NormalizedTermGraph,
    )
    count = length(graph.nodes)
    result_type = Any[Any for _ in 1:count]
    shape = Any[() for _ in 1:count]
    units = Any[:unknown for _ in 1:count]
    parameter_role = fill(:none, count)
    purity = fill(:pure, count)
    totality = fill(:total, count)
    reads = Any[() for _ in 1:count]
    writes = Any[() for _ in 1:count]
    footprint = Any[EmptyAnalyzedFootprint() for _ in 1:count]
    locality = fill(:scalar, count)
    affected_region = Any[() for _ in 1:count]
    effect = Any[PureRead() for _ in 1:count]
    emission_bound = EffectBound[EffectBound(0, :read_only) for _ in 1:count]
    scientific_category = fill(:expression, count)
    stage = Any[nothing for _ in 1:count]
    dependencies = Any[() for _ in 1:count]
    rng_sites = Any[() for _ in 1:count]
    state_participation = falses(count)
    workspace_participation = falses(count)
    adaptation_participation = falses(count)
    checkpoint_participation = falses(count)
    engine_admission = Any[() for _ in 1:count]
    backend_admission = Any[() for _ in 1:count]
    source_chain = Any[() for _ in 1:count]
    source_bindings = Any[() for _ in 1:count]
    operation_roles = _node_operation_roles(source, graph)

    dimensions = _host_lattice_dimensions(source)
    for node in graph.nodes
        index = Int(node.identity)
        record = source.records[node.record]
        operand_indices = Int.(node.operands)
        operand_footprints = Any[footprint[item] for item in operand_indices]
        transfer = node.transfer
        if transfer !== nothing
            for role in operation_roles[index]
                _validate_operation_use!(
                    node,
                    record,
                    Tuple(result_type[item] for item in operand_indices),
                    graph,
                    source,
                    role,
                )
            end
        end
        result_type[index] = if node.payload_kind === :literal
            typeof(node.payload.value)
        elseif node.payload_kind in (:parameter, :variable, :state)
            record.result_type === Nothing ? Real : record.result_type
        elseif node.payload_kind in (
                :proposal_context, :site_anchor, :cell_anchor, :contact_anchor,
                :relationship_context, :relationship_set, :spatial_relation, :kind,
                :relationship_payload,
            )
            Real
        elseif node.payload_kind === :draw
            Int
        elseif transfer.result_rule === :boolean
            Bool
        elseif transfer.result_rule === :integer
            Int
        elseif transfer.result_rule === :site_selection
            CorePotts.CompilerSPI.AbstractLifecycleSiteSelection
        elseif transfer.result_rule === :branch_promote && length(operand_indices) == 3
            promote_type(
                result_type[operand_indices[2]],
                result_type[operand_indices[3]],
            )
        elseif transfer.result_rule in (:preserve_numeric, :promote_numeric) &&
                !isempty(operand_indices)
            promote_type((result_type[item] for item in operand_indices)...)
        else
            Real
        end
        units[index] = transfer === nothing ?
            _normalized_leaf_unit(node, source) :
            _validated_operation_unit(
                node,
                Tuple(units[item] for item in operand_indices),
                record,
                graph,
                source,
            )
        parameter_role[index] = node.payload_kind === :parameter ? :runtime :
                                node.payload_kind === :literal ? :literal : :none
        purity[index] = transfer === nothing ? :pure : transfer.purity
        totality[index] = transfer === nothing ? :total : transfer.totality
        reads[index] = record.reads
        writes[index] = record.writes
        footprint[index] = try
            _analyzed_footprint(
                source, node, record, operand_footprints, dimensions
            )
        catch error
            throw(_footprint_analysis_error(record, node, error))
        end
        locality[index] = _footprint_locality(footprint[index])
        affected_region[index] = (
            locality = locality[index],
            footprint = footprint[index],
            resources = record.resources,
            bound = record.bound,
        )
        effect[index] = record.effect
        emission_bound[index] = record.bound
        scientific_category[index] = _record_operation_role(record)
        stage[index] = record.phase
        dependencies[index] = record.ordering_dependencies
        rng_sites[index] = record.random_operations
        state_participation[index] = record.persistence === :logical ||
                                     !isempty(record.reads) ||
                                     !isempty(record.writes)
        workspace_participation[index] = !(record.effect isa PureRead) ||
                                         !(footprint[index] isa
                                           EmptyAnalyzedFootprint)
        adaptation_participation[index] =
            state_participation[index] || workspace_participation[index]
        checkpoint_participation[index] = record.persistence === :logical
        engine_admission[index] = record.engine_admission
        operand_backend_admission = (
            backend_admission[item] for item in operand_indices
        )
        own_cpu = transfer === nothing ? true : transfer.cpu
        own_gpu = transfer === nothing ? true : transfer.gpu
        operand_cpu = all(admission.cpu for admission in operand_backend_admission)
        operand_gpu = all(admission.gpu for admission in operand_backend_admission)
        rejection_reasons = String[]
        if transfer !== nothing && !own_cpu
            push!(
                rejection_reasons,
                "operation $(transfer.identity) rejects CPU execution",
            )
        end
        if transfer !== nothing && !own_gpu
            push!(
                rejection_reasons,
                "operation $(transfer.identity) rejects GPU execution",
            )
        end
        for operand in operand_indices
            reason = backend_admission[operand].reason
            isempty(reason) || reason in rejection_reasons ||
                push!(rejection_reasons, reason)
        end
        backend_admission[index] = (
            cpu = own_cpu && operand_cpu,
            gpu = own_gpu && operand_gpu,
            reason = join(rejection_reasons, "; "),
        )
        source_chain[index] = (
            identity = record.identity,
            source = record.source,
            provenance = record.provenance,
        )
        source_bindings[index] = transfer === nothing ? () :
            _resolved_operation_source_bindings(
                transfer, node, graph, source
            )
    end

    facts = AnalyzedFactTable(
        result_type,
        shape,
        units,
        parameter_role,
        purity,
        totality,
        reads,
        writes,
        footprint,
        locality,
        affected_region,
        effect,
        emission_bound,
        scientific_category,
        stage,
        dependencies,
        rng_sites,
        state_participation,
        workspace_participation,
        adaptation_participation,
        checkpoint_participation,
        engine_admission,
        backend_admission,
        source_chain,
        source_bindings,
    )
    candidates = DescriptorCandidate[]
    roots_by_record = Dict{Int32, Vector{Int32}}()
    for root in graph.roots
        if _is_unknown_unit(units[Int(root.node)])
            node = graph.nodes[Int(root.node)]
            record = source.records[Int(root.record)]
            throw(PottsValidationError(
                :analysis,
                (PottsDiagnostic(
                    :illegal_operation_units,
                    record.identity,
                    String(node.operation),
                    record.identity.path,
                    "a compiler-proven root expression unit",
                    "the root expression retains an unproven unit",
                    (),
                    record.source,
                ),),
            ))
        end
        root_footprint = footprint[Int(root.node)]
        if _footprint_has_unresolved_reference(root_footprint)
            node = graph.nodes[Int(root.node)]
            record = source.records[Int(root.record)]
            throw(_footprint_analysis_error(
                record,
                node,
                ArgumentError(
                    "root footprint retains an unconsumed relation/resource reference"
                ),
            ))
        end
        record = source.records[Int(root.record)]
        if record.kind !== :HamiltonianTerm &&
                _footprint_has_unbounded_relationship(root_footprint)
            node = graph.nodes[Int(root.node)]
            throw(_footprint_analysis_error(
                record,
                node,
                ArgumentError(
                    "relationship footprint requires a bounded maximum_degree"
                ),
            ))
        end
        push!(get!(roots_by_record, root.record, Int32[]), root.node)
    end
    for (record_index, roots) in sort!(
            collect(roots_by_record); by = first
        )
        record = source.records[record_index]
        category = scientific_category[Int(first(roots))]
        energy_domain, affected_anchors, affected_proof = if category === :hamiltonian
            try
                domain = _energy_domain_fact(source, record)
                reads = _normalized_energy_anchor_reads(graph, roots)
                forbidden = _normalized_hamiltonian_forbidden_dependency(
                    graph, roots
                )
                forbidden === nothing || throw(ArgumentError(
                    "Hamiltonian energy expressions cannot depend on " *
                    "$(first(forbidden)) $(last(forbidden))"
                ))
                transition = CopyProposalTransition()
                root_footprint = _footprint_union(Tuple(
                    footprint[Int(root)] for root in roots
                ))
                affected = _affected_anchor_fact(
                    source,
                    record,
                    domain,
                    reads,
                    transition,
                    root_footprint,
                )
                if record.provenance isa NamedTuple &&
                        haskey(record.provenance, :registered_affected_region)
                    declared = record.provenance.registered_affected_region
                    declared === affected.kind || throw(ArgumentError(
                        "registered affected_region $(repr(declared)) does not match " *
                        "the compiler-proven class $(repr(affected.kind))"
                    ))
                end
                bound = ExpressionAnchorReadFact(
                    domain.anchor_kind,
                    domain.anchor_name,
                    domain.resource_identity,
                )
                proof = AffectedAnchorProof(
                    domain, bound, reads, transition, root_footprint
                )
                (domain, affected, proof)
            catch error
                error isa PottsValidationError && rethrow(error)
                throw(_hamiltonian_analysis_error(record, error))
            end
        else
            (nothing, nothing, nothing)
        end
        push!(
            candidates,
            DescriptorCandidate(
                record.identity,
                record_index,
                category,
                roots,
                energy_domain,
                affected_anchors,
                affected_proof,
                _sha256_hex(
                    "potts-descriptor-candidate-v1",
                    record.lowering_identity,
                    Tuple(graph.nodes[root].structural_key for root in roots),
                    category,
                    energy_domain === nothing ? nothing :
                    (
                        energy_domain.kind,
                        energy_domain.resource_identity,
                        energy_domain.anchor_kind,
                    ),
                    affected_anchors,
                    affected_proof,
                ),
                record.provenance,
            ),
        )
    end
    lifecycle = _analyze_lifecycle_records(source, graph, facts)
    key = _sha256_hex(
        "potts-analyzed-term-ir-v1",
        graph.structural_key,
        Tuple((
            result_type[index],
            shape[index],
            units[index],
            parameter_role[index],
            purity[index],
            totality[index],
            footprint[index],
            locality[index],
            emission_bound[index].maximum,
            emission_bound[index].basis,
            scientific_category[index],
            backend_admission[index],
        ) for index in eachindex(graph.nodes)),
        Tuple(candidate.structural_key for candidate in candidates),
        Tuple(fact.structural_key for fact in lifecycle),
    )
    return AnalyzedTermIR(source, graph, facts, candidates, lifecycle, key)
end

function _analyze_completed_system(completed::PottsSystem)
    data = _completion_data(completed)
    data.analysis === nothing || return data.analysis
    return _analyze_term_graph(data.source_graph, data.normalized_graph)
end

function _compiler_analysis_report(ir::AnalyzedTermIR)
    return (
        source_graph = (
            systems = length(ir.source.systems),
            statements = length(ir.source.statements),
            references = length(ir.source.references),
            structural_key = ir.source.structural_key,
        ),
        normalized = (
            nodes = length(ir.graph.nodes),
            roots = length(ir.graph.roots),
            operations = length(ir.graph.operation_snapshot),
            operation_inventory = _operation_inventory(ir.graph),
            structural_key = ir.graph.structural_key,
        ),
        analyzed = (
            candidates = length(ir.candidates),
            lifecycle = length(ir.lifecycle),
            structural_key = ir.structural_key,
            candidate_keys = String[
                candidate.structural_key for candidate in ir.candidates
            ],
        ),
        lifecycle = _lifecycle_analysis_report(ir),
    )
end
