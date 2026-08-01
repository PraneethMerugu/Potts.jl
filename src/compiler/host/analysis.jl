# Semantic fact inference and descriptor-candidate analysis.

struct AnalyzedFactTable
    result_type::Vector{Any}
    shape::Vector{Any}
    units::Vector{Any}
    parameter_role::Vector{Symbol}
    purity::Vector{Symbol}
    totality::Vector{Symbol}
    reads::Vector{Any}
    writes::Vector{Any}
    locality::Vector{Symbol}
    affected_region::Vector{Any}
    effect::Vector{Any}
    emission_bound::Vector{EffectBound}
    scientific_category::Vector{Symbol}
    stage::Vector{Any}
    dependencies::Vector{Any}
    rng_sites::Vector{Any}
    state_participation::Vector{Bool}
    workspace_participation::Vector{Bool}
    adaptation_participation::Vector{Bool}
    checkpoint_participation::Vector{Bool}
    engine_admission::Vector{Any}
    backend_admission::Vector{Any}
    source_chain::Vector{Any}
end

struct DescriptorCandidate
    source::QualifiedStatementID
    record::Int32
    category::Symbol
    roots::Vector{Int32}
    energy_domain::Any
    affected_anchors::Any
    structural_key::String
    provenance::Any
end

struct AnalyzedTermIR
    source::FrozenSourceGraph
    graph::NormalizedTermGraph
    facts::AnalyzedFactTable
    candidates::Vector{DescriptorCandidate}
    structural_key::String
end

_join_locality(values) =
    :bounded_relationship in values ? :bounded_relationship :
    :finite_spatial in values ? :finite_spatial :
    :owner_local in values ? :owner_local :
    :contact_local in values ? :contact_local :
    :site_local in values ? :site_local :
    :proposal_context in values ? :proposal_context : :scalar

function _hamiltonian_analysis_error(record, error)
    return PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :invalid_hamiltonian_domain,
            record.identity,
            repr(first(record.normalized_payload).expression),
            record.identity.path,
            "a conservative energy expression with a compiler-proven finite affected-anchor plan",
            sprint(showerror, error),
            (),
            record.source,
        ),),
    )
end

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

    for node in graph.nodes
        index = Int(node.identity)
        record = source.records[node.record]
        operand_indices = Int.(node.operands)
        operand_locality = Symbol[locality[item] for item in operand_indices]
        transfer = node.transfer
        result_type[index] = if node.payload_kind === :literal
            typeof(node.payload)
        elseif node.payload_kind in (:parameter, :variable, :state, :symbolic_leaf)
            record.result_type === Nothing ? Real : record.result_type
        elseif node.payload_kind in (
                :proposal_context, :site_anchor, :cell_anchor, :contact_anchor,
                :relationship_context, :relationship_set, :spatial_relation, :kind,
                :relationship_payload,
            )
            Real
        elseif transfer.result_rule === :boolean
            Bool
        elseif transfer.result_rule === :integer
            Int
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
        units[index] = isempty(record.units) ? :dimensionless : record.units
        parameter_role[index] = node.payload_kind === :parameter ? :runtime :
                                node.payload_kind === :literal ? :literal : :none
        purity[index] = transfer === nothing ? :pure : transfer.purity
        totality[index] = transfer === nothing ? :total : transfer.totality
        reads[index] = record.reads
        writes[index] = record.writes
        locality[index] = transfer === nothing ?
                          _join_locality(operand_locality) :
                          _join_locality((
                              operand_locality..., transfer.locality
                          ))
        affected_region[index] = (
            locality = locality[index],
            resources = record.resources,
            bound = record.bound,
        )
        effect[index] = record.effect
        emission_bound[index] = record.bound
        scientific_category[index] = if record.kind === :HamiltonianTerm
            :hamiltonian
        elseif record.kind === :ProposalDrive
            :drive
        elseif record.kind === :ProposalConstraint
            :constraint
        elseif record.kind === :ProposalModifier
            :modifier
        elseif record.kind in (
                :RelationshipProcess, :LifecycleProcess, :RelationshipState,
            )
            :relationship
        elseif record.kind in (
                :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
                :HistoryState,
            )
            :state
        elseif record.kind === :Observation
            :observation
        else
            :process
        end
        stage[index] = record.phase
        dependencies[index] = record.ordering_dependencies
        rng_sites[index] = record.random_operations
        state_participation[index] = record.persistence === :logical ||
                                     !isempty(record.reads) ||
                                     !isempty(record.writes)
        workspace_participation[index] = !(record.effect isa PureRead) ||
                                         locality[index] !== :scalar
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
    )
    candidates = DescriptorCandidate[]
    roots_by_record = Dict{Int32, Vector{Int32}}()
    for root in graph.roots
        push!(get!(roots_by_record, root.record, Int32[]), root.node)
    end
    for (record_index, roots) in sort!(
            collect(roots_by_record); by = first
        )
        record = source.records[record_index]
        category = scientific_category[Int(first(roots))]
        energy_domain, affected_anchors = if category === :hamiltonian
            try
                domain = _energy_domain_fact(source, record)
                affected = _affected_anchor_fact(
                    source,
                    record,
                    domain,
                    locality[Int(first(roots))],
                )
                if record.provenance isa NamedTuple &&
                        haskey(record.provenance, :registered_affected_region)
                    declared = record.provenance.registered_affected_region
                    declared === affected.kind || throw(ArgumentError(
                        "registered affected_region $(repr(declared)) does not match " *
                        "the compiler-proven class $(repr(affected.kind))"
                    ))
                end
                (domain, affected)
            catch error
                error isa PottsValidationError && rethrow(error)
                throw(_hamiltonian_analysis_error(record, error))
            end
        else
            (nothing, nothing)
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
                _sha256_hex(
                    "potts-descriptor-candidate-v1",
                    record.lowering_identity,
                    Tuple(graph.nodes[root].structural_key for root in roots),
                    category,
                    energy_domain === nothing ? nothing :
                    (energy_domain.kind, energy_domain.anchor_kind),
                    affected_anchors,
                ),
                record.provenance,
            ),
        )
    end
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
            locality[index],
            emission_bound[index].maximum,
            emission_bound[index].basis,
            scientific_category[index],
            backend_admission[index],
        ) for index in eachindex(graph.nodes)),
        Tuple(candidate.structural_key for candidate in candidates),
    )
    return AnalyzedTermIR(source, graph, facts, candidates, key)
end

function _analyze_completed_system(completed::PottsSystem)
    data = _completion_data(completed)
    graph = _normalize_source_graph(data.source_graph, completed)
    return _analyze_term_graph(data.source_graph, graph)
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
            structural_key = ir.graph.structural_key,
        ),
        analyzed = (
            candidates = length(ir.candidates),
            structural_key = ir.structural_key,
            candidate_keys = String[
                candidate.structural_key for candidate in ir.candidates
            ],
        ),
    )
end
