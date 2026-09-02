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
    source_bindings::Vector{Any}
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
    lifecycle::Vector{LifecycleAnalysisFact}
    structural_key::String
end

function _record_operation_role(record::QualifiedStatement)
    record.kind === :HamiltonianTerm && return :hamiltonian
    record.kind === :ProposalDrive && return :drive
    record.kind === :ProposalConstraint && return :constraint
    record.kind === :ProposalModifier && return :modifier
    record.kind === :Observation && return :observation
    if record.kind === :LifecycleProcess
        arguments = first(record.normalized_payload)
        any(_cell_lifecycle_effect, arguments.effects) && return :lifecycle
        return :relationship
    end
    record.kind in (:RelationshipProcess, :RelationshipState) &&
        return :relationship
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
    required === :iteration && return phase === :AfterMCS
    required === :relationship && return role === :relationship
    required === :lifecycle_trigger && return role === :lifecycle_trigger
    required === :lifecycle_placement && return role === :lifecycle_placement
    required === :lifecycle_partition && return role === :lifecycle_partition
    required === :lifecycle_state_transform &&
        return role === :lifecycle_state_transform
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
    role === :lifecycle_trigger &&
        return CorePotts.CompilerSPI.AbstractLifecycleTriggerEvaluationContext
    role === :lifecycle_placement &&
        return CorePotts.CompilerSPI.AbstractLifecyclePlacementEvaluationContext
    role === :lifecycle_partition &&
        return CorePotts.CompilerSPI.AbstractLifecyclePartitionEvaluationContext
    role === :lifecycle_state_transform &&
        return CorePotts.CompilerSPI.AbstractLifecycleStateTransformEvaluationContext
    role === :lifecycle_priority && return nothing
    role === :hamiltonian &&
        return CorePotts.CompilerSPI.AbstractHamiltonianEvaluationContext
    # Observations lower through their closed observation manifest rather
    # than the generic static-evaluator path.
    role === :observation && return nothing
    phase in (:Proposal, :AcceptedCopy) &&
        return CorePotts.CompilerSPI.AbstractProposalEvaluationContext
    phase === :AfterMCS &&
        return CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext
    phase in (:RelationshipCommit, :Lifecycle) &&
        return CorePotts.CompilerSPI.AbstractRelationshipStageEvaluationContext
    return nothing
end

const _LIFECYCLE_ROOT_ROLES = (
    :lifecycle_trigger,
    :lifecycle_placement,
    :lifecycle_partition,
    :lifecycle_state_transform,
    :lifecycle_priority,
)

function _node_operation_roles(
        source::FrozenSourceGraph,
        graph::NormalizedTermGraph,
    )
    roles = [Symbol[] for _ in graph.nodes]
    function visit(index::Int32, role::Symbol)
        bucket = roles[Int(index)]
        role in bucket || push!(bucket, role)
        for operand in graph.nodes[Int(index)].operands
            visit(operand, role)
        end
        return nothing
    end
    for root in graph.roots
        record = source.records[Int(root.record)]
        role = root.role in _LIFECYCLE_ROOT_ROLES ? root.role :
               _record_operation_role(record)
        visit(root.node, role)
    end
    return Tuple(Tuple(sort!(bucket; by = String)) for bucket in roles)
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
        elseif requirement isa NamedSpatialRelationRequirement
            relation = _resource_record(
                source,
                source.records[Int(node.record)],
                :SpatialRelation,
                requirement.name,
            )
            relation === nothing && return(
                "requires a lexically visible SpatialRelation named " *
                repr(requirement.name)
            )
            neighborhood = get(
                _record_options(relation), :neighborhood, nothing
            )
            neighborhood isa Union{VonNeumann, Moore} || return(
                "relation $(repr(requirement.name)) must use a finite " *
                "VonNeumann or Moore neighborhood"
            )
        else
            return "unknown source requirement $(nameof(typeof(requirement)))"
        end
    end
    return nothing
end

function _resolved_operation_source_bindings(
        transfer::OperationTransfer,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    bindings = OperationSourceBinding[]
    for (requirement_index, requirement) in
            enumerate(transfer.source_requirements)
        identity = if requirement isa SpatialRelationRequirement
            payload = graph.nodes[
                Int(node.operands[requirement.operand])
            ].payload
            payload isa ResourceBindingPayload ? payload.identity : nothing
        elseif requirement isa NamedSpatialRelationRequirement
            relation = _resource_record(
                source,
                source.records[Int(node.record)],
                :SpatialRelation,
                requirement.name,
            )
            relation === nothing ? nothing : relation.identity
        else
            nothing
        end
        identity === nothing && continue
        push!(bindings, OperationSourceBinding(
            Int16(requirement_index), :SpatialRelation, identity
        ))
    end
    return Tuple(bindings)
end

function _validate_operation_use!(
        node::NormalizedTermNode,
        record::QualifiedStatement,
        operand_types::Tuple,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
        role::Symbol,
    )
    transfer = node.transfer
    transfer === nothing && return nothing
    phase = _record_operation_phase(record)
    abi_role = transfer.lifecycle_abi === nothing ? nothing :
        transfer.lifecycle_abi.role === :binary_partition ?
        :lifecycle_partition :
        Symbol(:lifecycle_, transfer.lifecycle_abi.role)
    problem = if abi_role !== nothing && role !== abi_role
        "lifecycle ABI role $(repr(abi_role)) cannot execute as $(repr(role))"
    elseif !(role in transfer.allowed_roles)
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
            !CorePotts.CompilerSPI.operation_context_supported(node.callable, context)
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
    _is_polymorphic_zero_unit(left) || _is_polymorphic_zero_unit(right) ||
    left == right

_is_native_dimension(unit) = unit isa DynamicQuantities.AbstractDimensions
_canonical_dimension(unit::DynamicQuantities.AbstractDimensions) =
    unit == one(unit) ? :dimensionless : unit

function _declared_record_unit(record::QualifiedStatement)
    isempty(record.units) && return :dimensionless
    length(record.units) == 1 || return :unknown
    declared = only(record.units).dimension
    quantities = Any[]
    _collect_quantities!(quantities, _record_arguments(record))
    _collect_quantities!(quantities, _record_options(record))
    for quantity in quantities
        dimension = DynamicQuantities.dimension(quantity)
        string(dimension) == declared || continue
        return _canonical_dimension(dimension)
    end
    # A string-backed atom is conservative: algebra may transform it, but it
    # cannot compare equal to an unrelated dimension merely because its label
    # looks similar.
    return (:declared_dimension, declared)
end

function _normalized_leaf_unit(
        node::NormalizedTermNode,
        source::FrozenSourceGraph,
    )
    payload = node.payload
    value = payload isa Union{LiteralPayload, ParameterBindingPayload} ?
            payload.value : nothing
    if value isa DynamicQuantities.UnionAbstractQuantity
        return _canonical_dimension(DynamicQuantities.dimension(value))
    elseif payload isa ParameterBindingPayload
        default = try
            ModelingToolkitBase.hasdefault(value) ?
                ModelingToolkitBase.getdefault(value) : nothing
        catch
            nothing
        end
        default isa DynamicQuantities.UnionAbstractQuantity && return(
            _canonical_dimension(DynamicQuantities.dimension(default))
        )
        default isa Number && return :dimensionless
        # Required parameters have no default from which to infer a dimension.
        # Runtime parameter normalization deliberately admits only ordinary
        # numbers for those entries, so their compiler-visible unit is
        # dimensionless as well.
        return ModelingToolkitBase.hasdefault(value) ? :unknown : :dimensionless
    elseif payload isa Union{StateBindingPayload, VariableBindingPayload}
        index = findfirst(
            record -> record.identity == payload.identity,
            source.records,
        )
        # A captured binding can be referenced by a semantic statement before
        # it is materialized as an owned state record (for example, during
        # host-only category analysis). Preserve its qualified identity as a
        # unit variable: equal bindings can be proven equal, while the value
        # cannot unify with a concrete or unrelated dimension.
        return index === nothing ? (:binding_dimension, payload.identity) :
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

function _unit_product(left, right)
    left === :dimensionless && return right
    right === :dimensionless && return left
    _is_polymorphic_zero_unit(left) && return right
    _is_polymorphic_zero_unit(right) && return left
    (_is_unknown_unit(left) || _is_unknown_unit(right)) && return :unknown
    if _is_native_dimension(left) && _is_native_dimension(right)
        return _canonical_dimension(left * right)
    end
    factors = Any[]
    append!(factors, left isa Tuple && first(left) === :product ? left[2:end] : (left,))
    append!(factors, right isa Tuple && first(right) === :product ? right[2:end] : (right,))
    sort!(factors; by = repr)
    return (:product, factors...)
end

function _unit_quotient(numerator, denominator)
    _is_polymorphic_zero_unit(numerator) && return :polymorphic_zero
    denominator === :dimensionless && return numerator
    (_is_unknown_unit(numerator) || _is_unknown_unit(denominator)) && return :unknown
    numerator == denominator && return :dimensionless
    if _is_native_dimension(numerator) && _is_native_dimension(denominator)
        return _canonical_dimension(numerator / denominator)
    end
    return (:quotient, numerator, denominator)
end

function _unit_power(unit, exponent::Rational)
    unit === :dimensionless && return (:dimensionless, nothing)
    _is_polymorphic_zero_unit(unit) && return (:polymorphic_zero, nothing)
    _is_unknown_unit(unit) && return (:unknown, nothing)
    exponent == 0 && return (:dimensionless, nothing)
    exponent == 1 && return (unit, nothing)
    if _is_native_dimension(unit)
        result = try
            unit ^ exponent
        catch error
            return (nothing, "cannot represent dimension exponent $exponent: $(sprint(showerror, error))")
        end
        return (_canonical_dimension(result), nothing)
    end
    return ((:power, unit, exponent), nothing)
end

function _literal_integer_exponent(
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
    )
    length(node.operands) == 2 || return nothing
    payload = graph.nodes[Int(node.operands[2])].payload
    payload isa LiteralPayload || return nothing
    value = payload.value
    value isa Integer && return value
    value isa Rational && denominator(value) == 1 && return Int(numerator(value))
    value isa AbstractFloat && isinteger(value) &&
        abs(value) <= typemax(Int) && return Int(value)
    return nothing
end

function _common_unit(units::Tuple)
    any(_is_unknown_unit, units) && return nothing
    known = filter(
        unit -> !_is_polymorphic_zero_unit(unit),
        units,
    )
    isempty(known) && return :dimensionless
    first_unit = first(known)
    all(unit -> unit == first_unit, known) || return nothing
    return first_unit
end


function _lattice_volume_unit(source::FrozenSourceGraph)
    domains = filter(
        record -> record.kind === :LatticeDomain, source.records
    )
    length(domains) == 1 || return(
        nothing, "lattice-volume units require exactly one lattice domain"
    )
    spacing = get(_record_options(only(domains)), :spacing, nothing)
    spacing isa Tuple && !isempty(spacing) || return(
        nothing, "lattice-volume units require a nonempty spacing tuple"
    )
    unit = :dimensionless
    for value in spacing
        factor = value isa DynamicQuantities.UnionAbstractQuantity ?
                 _canonical_dimension(DynamicQuantities.dimension(value)) :
                 value isa Number ? :dimensionless : :unknown
        _is_unknown_unit(factor) && return(
            nothing, "lattice spacing has an unproven unit"
        )
        unit = _unit_product(unit, factor)
    end
    return (unit, nothing)
end

function _operation_unit_result(
        transfer::OperationTransfer,
        operand_units::Tuple,
        record::QualifiedStatement,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    rule = transfer.unit_rule
    any(_is_unknown_unit, operand_units) && return (
        nothing,
        "cannot prove units for operands $(repr(operand_units))",
    )
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
    elseif rule === :square_root
        length(operand_units) == 1 || return(
            nothing, "square-root unit rule requires one operand"
        )
        return _unit_power(first(operand_units), 1 // 2)
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
            return (foldl(_unit_product, operand_units; init = :dimensionless), nothing)
        elseif identity === :divide
            length(operand_units) == 2 || return (:unknown, nothing)
            return (_unit_quotient(operand_units...), nothing)
        elseif identity === :power
            length(operand_units) == 2 || return (:unknown, nothing)
            _unit_compatible(operand_units[2], :dimensionless) || return(
                nothing, "power exponent must be dimensionless"
            )
            exponent = _literal_integer_exponent(node, graph)
            exponent === nothing && return(
                nothing,
                "power requires a literal integer exponent; use sqrt for square roots",
            )
            operand_units[1] === :dimensionless && return(:dimensionless, nothing)
            return _unit_power(operand_units[1], exponent // 1)
        end
        return (:unknown, nothing)
    elseif rule === :declared
        return (_declared_record_unit(record), nothing)
    elseif rule === :distribution
        parameters = length(operand_units) >= 3 ? operand_units[2:3] : operand_units
        common = _common_unit(parameters)
        common === nothing && return(
            nothing,
            "distribution parameters have incompatible or unproven units " *
            repr(parameters),
        )
        return (common, nothing)
    elseif rule === :lattice_volume
        return _lattice_volume_unit(source)
    end
    return (:unknown, "unsupported unit rule $(repr(rule))")
end

function _validated_operation_unit(
        node::NormalizedTermNode,
        operand_units::Tuple,
        record::QualifiedStatement,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    transfer = node.transfer
    transfer === nothing && return :unknown
    unit, problem = _operation_unit_result(
        transfer, operand_units, record, node, graph, source
    )
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
