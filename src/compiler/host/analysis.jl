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
    footprint::Vector{Any}
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
    affected_proof::Any
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

function _record_operation_role(record::QualifiedStatement)
    record.kind === :HamiltonianTerm && return :hamiltonian
    record.kind === :ProposalDrive && return :drive
    record.kind === :ProposalConstraint && return :constraint
    record.kind === :ProposalModifier && return :modifier
    record.kind === :Observation && return :observation
    record.kind in (
        :RelationshipProcess, :LifecycleProcess, :RelationshipState,
    ) && return :relationship
    record.kind in (
        :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
        :HistoryState,
    ) && return :state
    return :process
end

_record_operation_phase(record::QualifiedStatement) =
    record.phase === nothing ? :none : nameof(typeof(record.phase))

function _operation_context_admitted(
        required::Symbol,
        role::Symbol,
        phase::Symbol,
    )
    required === :any && return true
    required === :proposal && return phase in (:Proposal, :AcceptedCopy)
    required === :hamiltonian && return role === :hamiltonian
    required === :iteration && return phase in (
        :AfterMCS, :EquationStep, :Observe,
    )
    required === :relationship && return role === :relationship
    return false
end

function _operation_operand_admitted(rule::Symbol, types::Tuple)
    rule === :any && return true
    rule === :numeric && return all(type -> type <: Number, types)
    rule === :boolean && return all(type -> type <: Bool, types)
    rule === :integer && return all(type -> type <: Integer, types)
    rule === :same_type && return isempty(types) || all(==(first(types)), types)
    rule === :ifelse && return length(types) == 3 && types[1] <: Bool &&
        promote_type(types[2], types[3]) !== Any
    return false
end

function _operation_evaluation_context(role::Symbol, phase::Symbol)
    role === :hamiltonian &&
        return CorePotts.AbstractHamiltonianEvaluationContext
    # V1 observations lower through their closed observation manifest rather
    # than the generic static-evaluator path.
    role === :observation && return nothing
    phase in (:Proposal, :AcceptedCopy) &&
        return CorePotts.AbstractProposalEvaluationContext
    phase in (:AfterMCS, :EquationStep) &&
        return CorePotts.AbstractSiteStageEvaluationContext
    phase in (:RelationshipCommit, :Lifecycle) &&
        return CorePotts.AbstractRelationshipStageEvaluationContext
    return nothing
end

function _source_requirement_problem(
        transfer::OperationTransfer,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    for requirement in transfer.source_requirements
        if requirement isa LatticeRankRequirement
            actual = length(_host_lattice_shape(source))
            actual == requirement.rank || return(
                "requires lattice rank $(requirement.rank), got $actual"
            )
        elseif requirement isa SpatialRelationRequirement
            operand_node = graph.nodes[Int(node.operands[requirement.operand])]
            payload = operand_node.payload
            payload isa ResourceBindingPayload &&
                payload.kind === :SpatialRelation || return(
                "operand $(requirement.operand) must resolve to a SpatialRelation"
            )
            relation_index = findfirst(
                record -> record.identity == payload.identity &&
                    record.kind === :SpatialRelation,
                source.records,
            )
            relation_index === nothing && return(
                "operand $(requirement.operand) has no qualified SpatialRelation"
            )
            neighborhood = get(
                _record_options(source.records[relation_index]),
                :neighborhood,
                nothing,
            )
            actual_kind = neighborhood isa Moore ? :moore :
                          neighborhood isa VonNeumann ? :von_neumann : :unknown
            actual_radius = hasproperty(neighborhood, :radius) ?
                            neighborhood.radius : nothing
            actual_kind === requirement.neighborhood &&
                actual_radius == requirement.radius || return(
                "operand $(requirement.operand) requires " *
                "$(requirement.neighborhood) radius $(requirement.radius), got " *
                "$(actual_kind) radius $(repr(actual_radius))"
            )
        end
    end
    return nothing
end

function _validate_operation_use!(
        node::NormalizedTermNode,
        record::QualifiedStatement,
        operand_types::Tuple,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    transfer = node.transfer
    transfer === nothing && return nothing
    role = _record_operation_role(record)
    phase = _record_operation_phase(record)
    problem = if !(role in transfer.allowed_roles)
        "role $(repr(role)) is not in $(repr(transfer.allowed_roles))"
    elseif !(phase in transfer.allowed_phases)
        "phase $(repr(phase)) is not in $(repr(transfer.allowed_phases))"
    elseif !_operation_context_admitted(transfer.required_context, role, phase)
        "required context $(repr(transfer.required_context)) is unavailable " *
        "for role $(repr(role)) in phase $(repr(phase))"
    elseif !_operation_operand_admitted(transfer.operand_rule, operand_types)
        "operand types $(repr(operand_types)) violate rule " *
        "$(repr(transfer.operand_rule))"
    elseif (source_problem = _source_requirement_problem(
                transfer, node, graph, source
            )) !== nothing
        source_problem
    elseif (context = _operation_evaluation_context(role, phase)) !== nothing &&
            !CorePotts.operation_context_supported(node.callable, context)
        "frozen callable $(typeof(node.callable)) has no implementation for " *
        "$(nameof(context))"
    else
        nothing
    end
    problem === nothing && return nothing
    throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :illegal_operation_use,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "the frozen role, phase, context, and operand contract",
            problem,
            (),
            record.source,
        ),),
    ))
end

_is_unknown_unit(unit) = unit === :unknown
_is_polymorphic_zero_unit(unit) = unit === :polymorphic_zero
_unit_compatible(left, right) =
    _is_unknown_unit(left) || _is_unknown_unit(right) ||
    _is_polymorphic_zero_unit(left) || _is_polymorphic_zero_unit(right) ||
    left == right

function _declared_record_unit(record::QualifiedStatement)
    isempty(record.units) && return :dimensionless
    length(record.units) == 1 || return :unknown
    return (:dimension, only(record.units).dimension)
end

function _normalized_leaf_unit(
        node::NormalizedTermNode,
        source::FrozenSourceGraph,
    )
    payload = node.payload
    value = payload isa Union{LiteralPayload, ParameterBindingPayload} ?
            payload.value : nothing
    if value isa DynamicQuantities.UnionAbstractQuantity
        return (:dimension, string(DynamicQuantities.dimension(value)))
    elseif payload isa ParameterBindingPayload
        default = try
            ModelingToolkitBase.hasdefault(value) ?
                ModelingToolkitBase.getdefault(value) : nothing
        catch
            nothing
        end
        default isa DynamicQuantities.UnionAbstractQuantity && return(
            (:dimension, string(DynamicQuantities.dimension(default)))
        )
        default isa Number && return :dimensionless
        return :unknown
    elseif payload isa Union{StateBindingPayload, VariableBindingPayload}
        index = findfirst(
            record -> record.identity == payload.identity,
            source.records,
        )
        return index === nothing ? :unknown :
               _declared_record_unit(source.records[index])
    elseif payload isa LiteralPayload
        return value isa Number && iszero(value) ?
               :polymorphic_zero : :dimensionless
    elseif node.payload_kind in (
            :proposal_context, :site_anchor, :cell_anchor, :contact_anchor,
            :relationship_context, :relationship_set, :spatial_relation,
            :kind, :relationship_payload, :draw,
        )
        return :dimensionless
    end
    return :unknown
end

function _common_unit(units::Tuple)
    known = filter(
        unit -> !_is_unknown_unit(unit) && !_is_polymorphic_zero_unit(unit),
        units,
    )
    isempty(known) && return any(_is_unknown_unit, units) ?
        :unknown : :dimensionless
    first_unit = first(known)
    all(unit -> unit == first_unit, known) || return nothing
    return first_unit
end

function _operation_unit_result(
        transfer::OperationTransfer,
        operand_units::Tuple,
        record::QualifiedStatement,
    )
    rule = transfer.unit_rule
    if rule === :dimensionless
        all(unit -> _unit_compatible(unit, :dimensionless), operand_units) ||
            return (
                nothing,
                "requires dimensionless operands, got $(repr(operand_units))",
            )
        return (:dimensionless, nothing)
    elseif rule === :comparison
        common = _common_unit(operand_units)
        common === nothing && return(
            nothing,
            "comparison operands have incompatible units $(repr(operand_units))",
        )
        return (:dimensionless, nothing)
    elseif rule === :branch
        length(operand_units) == 3 || return(
            nothing, "branch unit rule requires three operands"
        )
        _unit_compatible(operand_units[1], :dimensionless) || return(
            nothing, "branch condition must be dimensionless"
        )
        common = _common_unit((operand_units[2], operand_units[3]))
        common === nothing && return(
            nothing,
            "branch values have incompatible units $(repr(operand_units[2:3]))",
        )
        return (common, nothing)
    elseif rule === :unary
        return (isempty(operand_units) ? :unknown : first(operand_units), nothing)
    elseif rule === :arithmetic
        identity = transfer.identity
        if identity in (:add, :subtract, :maximum, :minimum)
            common = _common_unit(operand_units)
            common === nothing && return(
                nothing,
                "arithmetic operands have incompatible units $(repr(operand_units))",
            )
            return (common, nothing)
        elseif any(_is_unknown_unit, operand_units)
            return (:unknown, nothing)
        elseif identity === :multiply
            retained = filter(!=(:dimensionless), operand_units)
            unit = isempty(retained) ? :dimensionless :
                   length(retained) == 1 ? only(retained) :
                   (:product, retained...)
            return (unit, nothing)
        elseif identity === :divide
            length(operand_units) == 2 || return (:unknown, nothing)
            unit = operand_units[2] === :dimensionless ? operand_units[1] :
                   (:quotient, operand_units...)
            return (unit, nothing)
        elseif identity === :power
            length(operand_units) == 2 || return (:unknown, nothing)
            _unit_compatible(operand_units[2], :dimensionless) || return(
                nothing, "power exponent must be dimensionless"
            )
            return (operand_units[1], nothing)
        end
        return (:unknown, nothing)
    elseif rule === :declared
        return (_declared_record_unit(record), nothing)
    elseif rule === :distribution
        parameters = length(operand_units) >= 3 ? operand_units[2:3] : operand_units
        common = _common_unit(parameters)
        return (common === nothing ? :unknown : common, nothing)
    end
    return (:unknown, "unsupported unit rule $(repr(rule))")
end

function _validated_operation_unit(
        node::NormalizedTermNode,
        operand_units::Tuple,
        record::QualifiedStatement,
    )
    transfer = node.transfer
    transfer === nothing && return :unknown
    unit, problem = _operation_unit_result(transfer, operand_units, record)
    problem === nothing && return unit
    throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :illegal_operation_units,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "the frozen operation unit-transfer contract",
            problem,
            (),
            record.source,
        ),),
    ))
end

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

function _footprint_analysis_error(record, node, error)
    return PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :invalid_footprint_transfer,
            record.identity,
            string(node.operation),
            record.identity.path,
            "a closed, compositional, fully resolved footprint fact",
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

    dimensions = length(_host_lattice_shape(source))
    for node in graph.nodes
        index = Int(node.identity)
        record = source.records[node.record]
        operand_indices = Int.(node.operands)
        operand_footprints = Any[footprint[item] for item in operand_indices]
        transfer = node.transfer
        transfer === nothing || _validate_operation_use!(
            node,
            record,
            Tuple(result_type[item] for item in operand_indices),
            graph,
            source,
        )
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
    )
    candidates = DescriptorCandidate[]
    roots_by_record = Dict{Int32, Vector{Int32}}()
    for root in graph.roots
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
    )
    return AnalyzedTermIR(source, graph, facts, candidates, key)
end

function _analyze_completed_system(completed::PottsSystem)
    data = _completion_data(completed)
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
            operation_inventory = _v1_operation_inventory(ir.graph),
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
