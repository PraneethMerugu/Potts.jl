"""
Type-erased, immutable authority produced by Potts completion.

Completion data is deliberately vector-backed.  A model's statement count and
heterogeneous statement topology are data, not Julia type parameters: making
them part of this carrier's type forces the compiler to specialize the entire
completion/scheduling pipeline once per model shape.  Public inspection
materializes immutable tuples at the API boundary.
"""
struct CompletedPottsData
    registry::StatementRegistry
    reference_units::Union{DeclaredReferenceUnits, ReferenceUnits}
    parameter_roles::NamedTuple
    records::Vector{QualifiedStatement}
    variables::Vector{Any}
    schedule::Vector{QualifiedStatement}
    capabilities::NamedTuple
    fingerprints::NamedTuple
    diagnostics::Vector{PottsDiagnostic}
    source_graph::Any
    normalized_graph::Any
    analysis::Any
    native_components::Vector{CompletedNativeComponent}
    scheduled::Any
end

const _STRUCTURAL_OPTION_NAMES = Set((
    :shape,
    :max_cells,
    :capacity,
    :maximum_degree,
    :substeps,
    :cadence,
    :phase,
    :solver,
    :attempts,
    :boundary,
    :relations,
    :neighborhood,
))

function _collect_quantities!(found, value)
    if value isa DynamicQuantities.UnionAbstractQuantity
        push!(found, value)
    elseif value isa NamedTuple
        foreach(item -> _collect_quantities!(found, item), values(value))
    elseif value isa Tuple || value isa AbstractArray
        foreach(item -> _collect_quantities!(found, item), value)
    elseif value isa Pair
        _collect_quantities!(found, first(value))
        _collect_quantities!(found, last(value))
    elseif value isa AbstractDict
        for (key, item) in value
            _collect_quantities!(found, key)
            _collect_quantities!(found, item)
        end
    elseif value isa AbstractPottsEffect
        for field in fieldnames(typeof(value))
            _collect_quantities!(found, getfield(value, field))
        end
    elseif value isa Union{
            AbstractIterationDomain, AbstractBoundaryPolicy,
            AbstractRelationshipEndpointPolicy, AbstractLifecyclePolicy,
            SweepStage,
            SymmetricPair,
        }
        for field in fieldnames(typeof(value))
            _collect_quantities!(found, getfield(value, field))
        end
    end
    return found
end

function _completion_quantities(
        inventory::_PottsSourceInventory, normalized_statements
    )
    quantities = Any[]
    for statement in normalized_statements
        _collect_quantities!(quantities, _statement_arguments(statement))
        _collect_quantities!(quantities, _statement_options(statement))
    end
    for reference in inventory.references
        reference.kind === :parameter || continue
        parameter = reference.value
        ModelingToolkitBase.hasdefault(parameter) || continue
        _collect_quantities!(
            quantities, ModelingToolkitBase.getdefault(parameter)
        )
    end
    for reference in inventory.references
        reference.kind === :initial_condition || continue
        _collect_quantities!(quantities, reference.value)
    end
    return quantities
end

function _completion_reference_anchors(normalized_statements, option)
    if option isa ReferenceUnits
        return Pair{Symbol, Any}[
            name => getproperty(option.values, name)
            for name in keys(option.values)
        ]
    end
    anchors = Pair{Symbol, Any}[]
    for statement in normalized_statements
        if statement isa LatticeDomain
            for (index, value) in
                    enumerate(_statement_option(statement, :spacing, ()))
                value isa DynamicQuantities.UnionAbstractQuantity &&
                    push!(anchors, Symbol(:length_axis_, index) => value)
            end
        elseif statement isa Protocol
            for stage in _statement_arguments(statement).stages
                stage isa SweepStage || continue
                if haskey(stage.options, :temperature)
                    value = stage.options.temperature
                    value isa DynamicQuantities.UnionAbstractQuantity &&
                        push!(anchors, :energy => value)
                end
            end
            duration = _statement_option(
                statement, :duration_per_mcs, nothing
            )
            duration isa DynamicQuantities.UnionAbstractQuantity &&
                push!(anchors, Symbol(:time_, statement_id(statement)) => duration)
        elseif statement isa Union{
                SiteState, CellState, MediumState, ModelState, FieldState,
                HistoryState,
            }
            value = _statement_arguments(statement).initial
            value isa DynamicQuantities.UnionAbstractQuantity &&
                push!(anchors, Symbol(:state_, statement_id(statement)) => value)
            duration = _statement_option(statement, :duration_per_mcs, nothing)
            duration isa DynamicQuantities.UnionAbstractQuantity &&
                push!(anchors, Symbol(:time_, statement_id(statement)) => duration)
        end
    end
    return anchors
end

function _validate_completion_reference_units(
        inventory, option, normalized_statements
    )
    quantities = _completion_quantities(inventory, normalized_statements)
    isempty(quantities) && return nothing
    anchors = _completion_reference_anchors(normalized_statements, option)
    by_dimension = Dict{String, Tuple{Symbol, Float64}}()
    for (name, anchor) in anchors
        anchor isa DynamicQuantities.UnionAbstractQuantity || throw(ArgumentError(
            "reference unit `$name` must be a DynamicQuantities quantity"
        ))
        dimension = string(DynamicQuantities.dimension(anchor))
        scale = abs(Float64(DynamicQuantities.ustrip(anchor)))
        scale > 0 && isfinite(scale) || throw(ArgumentError(
            "reference unit `$name` must have a finite nonzero scale"
        ))
        existing = get(by_dimension, dimension, nothing)
        if existing !== nothing && existing[2] != scale
            throw(ArgumentError(
                "ambiguous declared reference scale for dimension $dimension: " *
                "$(existing[1]) and $name; supply ReferenceUnits(...) explicitly"
            ))
        end
        by_dimension[dimension] = (name, scale)
    end
    required = sort!(unique(
        string(DynamicQuantities.dimension(value)) for value in quantities
    ))
    missing = filter(dimension -> !haskey(by_dimension, dimension), required)
    isempty(missing) || throw(ArgumentError(
        "missing reference-unit anchor for dimension" *
        (length(missing) == 1 ? " " : "s ") *
        join(missing, ", ") * "; supply ReferenceUnits(...) explicitly"
    ))
    return nothing
end

function _structural_parameter_variables!(found, value)
    if value isa NamedTuple
        for name in keys(value)
            name in _STRUCTURAL_OPTION_NAMES || continue
            _collect_symbolics!(found, getproperty(value, name))
        end
    elseif value isa Tuple || value isa AbstractArray
        foreach(item -> _structural_parameter_variables!(found, item), value)
    elseif value isa Union{
            AbstractIterationDomain, AbstractBoundaryPolicy,
            AbstractRelationshipEndpointPolicy, AbstractLifecyclePolicy,
            SweepStage,
            SymmetricPair,
        }
        for field in fieldnames(typeof(value))
            _structural_parameter_variables!(found, getfield(value, field))
        end
    end
    return found
end

function _structural_parameters(inventory::_PottsSourceInventory)
    candidates = Any[]
    for statement in _inventory_statements(inventory)
        _structural_parameter_variables!(candidates, _statement_options(statement))
        if statement isa Protocol
            for stage in _statement_arguments(statement).stages
                stage isa SweepStage || continue
                _structural_parameter_variables!(
                    candidates, (attempts = stage.attempts.count,)
                )
            end
        end
    end
    result = NamedTuple[]
    seen = Any[]
    for reference in inventory.references
        reference.kind === :parameter || continue
        qualified = _namespace_symbolic_value(
            reference.value, reference.path[2:end]
        )
        any(candidate -> isequal(candidate, qualified), candidates) || continue
        any(candidate -> isequal(candidate, qualified), seen) && continue
        push!(seen, qualified)
        system_index = findfirst(
            occurrence -> occurrence.path == reference.path,
            inventory.systems,
        )
        system_index === nothing && error(
            "parameter reference is detached from its source-system occurrence"
        )
        push!(result, (
            system = Int32(system_index),
            raw = reference.value,
            qualified,
        ))
    end
    return Tuple(result)
end

function _substitute_source_inventory(inventory, structural)
    isempty(structural) && return inventory.systems[1].system, inventory
    global_substitutions = Dict{Any, Any}(
        entry.qualified => entry.value for entry in structural
    )
    local_systems = PottsSystem[]
    statement_groups = _inventory_statement_groups(inventory)
    transformed_groups = [AbstractPottsStatement[] for _ in inventory.systems]
    for occurrence in inventory.systems
        index = Int(occurrence.index)
        substitutions = copy(global_substitutions)
        for entry in structural
            entry.system == occurrence.index || continue
            substitutions[entry.raw] = entry.value
        end
        substitute_one = value -> _substitute_value(value, substitutions)
        is_symbolic = value -> !isempty(try
            Symbolics.get_variables(value)
        catch
            ()
        end)
        for statement in statement_groups[index]
            push!(transformed_groups[index], map_symbolics(
                substitute_one, statement
            ))
        end
        source = occurrence.system
        push!(local_systems, _rebuild(
            source;
            statements = StatementSet(transformed_groups[index]),
            equations = map(substitute_one, getfield(source, :eqs)),
            unknowns = filter(
                is_symbolic, map(substitute_one, getfield(source, :unknowns))
            ),
            parameters = filter(
                is_symbolic, map(substitute_one, getfield(source, :ps))
            ),
            independent_variables = filter(
                is_symbolic, map(substitute_one, getfield(source, :ivs))
            ),
            systems = PottsSystem[],
            inputs = filter(
                is_symbolic, map(substitute_one, getfield(source, :inputs))
            ),
            outputs = filter(
                is_symbolic, map(substitute_one, getfield(source, :outputs))
            ),
            initial_conditions = Dict(
                substitute_one(key) => substitute_one(value)
                for (key, value) in getfield(source, :initial_conditions)
            ),
            observed = map(substitute_one, getfield(source, :observed)),
            continuous_events = map(
                substitute_one, getfield(source, :continuous_events)
            ),
            discrete_events = map(
                substitute_one, getfield(source, :discrete_events)
            ),
        ))
    end
    return _rebuild_source_inventory(
        inventory, local_systems, transformed_groups
    )
end

function _resolve_structural_parameters(inventory::_PottsSourceInventory)
    structural = _structural_parameters(inventory)
    isempty(structural) && return inventory.systems[1].system, inventory, ()
    resolved = NamedTuple[]
    manifest = NamedTuple[]
    for entry in structural
        parameter = entry.qualified
        name = _symbolic_name(parameter; context = "structural parameter")
        raw = entry.raw
        ModelingToolkitBase.hasdefault(raw) || throw(ArgumentError(
            "structural parameter `$name` must have a concrete default or be " *
            "substituted before completion"
        ))
        value = ModelingToolkitBase.getdefault(raw)
        isempty(Symbolics.get_variables(value)) || throw(ArgumentError(
            "structural parameter `$name` did not resolve to a concrete value"
        ))
        push!(resolved, merge(entry, (; value)))
        push!(manifest, (; name, value))
    end
    sort!(manifest; by = entry -> String(entry.name))
    system, next_inventory = _substitute_source_inventory(
        inventory, Tuple(resolved)
    )
    return system, next_inventory, Tuple(manifest)
end

function _statement_expression(statement)
    source = statement_source(statement)
    source isa SourceLocation && return source.expression
    return sprint(show, statement)
end

function _record_resources!(result, value, path)
    if value isa AbstractPottsStatement
        identity = QualifiedStatementID(path, statement_id(value))
        identity in result || push!(result, identity)
    elseif value isa NamedTuple
        foreach(item -> _record_resources!(result, item, path), values(value))
    elseif value isa Tuple || value isa AbstractArray
        foreach(item -> _record_resources!(result, item, path), value)
    elseif value isa Pair
        _record_resources!(result, first(value), path)
        _record_resources!(result, last(value), path)
    elseif value isa AbstractPottsEffect
        foreach(
            field -> _record_resources!(result, getfield(value, field), path),
            fieldnames(typeof(value)),
        )
    elseif value isa Union{
            AbstractIterationDomain, AbstractBoundaryPolicy,
            AbstractRelationshipEndpointPolicy, AbstractLifecyclePolicy,
            SweepStage,
            SymmetricPair,
        }
        foreach(
            field -> _record_resources!(result, getfield(value, field), path),
            fieldnames(typeof(value)),
        )
    end
    return result
end

function _record_units(statement, inventory::_PottsSourceInventory)
    quantities = Any[]
    _collect_quantities!(quantities, _statement_arguments(statement))
    _collect_quantities!(quantities, _statement_options(statement))
    variables = _collect_symbolics((
        _statement_arguments(statement), _statement_options(statement)
    ))
    for reference in inventory.references
        reference.kind === :parameter || continue
        parameter = _namespace_symbolic_value(
            reference.value, reference.path[2:end]
        )
        any(variable -> isequal(variable, parameter), variables) || continue
        ModelingToolkitBase.hasdefault(reference.value) || continue
        _collect_quantities!(
            quantities, ModelingToolkitBase.getdefault(reference.value)
        )
    end
    descriptors = unique(
        (
            dimension = string(DynamicQuantities.dimension(value)),
            scale = Float64(DynamicQuantities.ustrip(value)),
        )
        for value in quantities
    )
    return Tuple(sort!(collect(descriptors); by = item -> item.dimension))
end

function _record_reference_conversion(units, anchors)
    isempty(units) && return ()
    by_dimension = Dict(
        string(DynamicQuantities.dimension(value)) => (
            name,
            scale = abs(Float64(DynamicQuantities.ustrip(value))),
        )
        for (name, value) in anchors
    )
    return Tuple(
        (
            dimension = unit.dimension,
            reference = by_dimension[unit.dimension].name,
            scale = by_dimension[unit.dimension].scale,
        )
        for unit in units
    )
end

function _record_shape(statement, root_shape)
    statement isa LatticeDomain &&
        return _statement_option(statement, :shape, root_shape)
    statement isa Union{SiteState, FieldState} && return root_shape
    statement isa CellState && return :cells
    statement isa MediumState && return :media
    statement isa ModelState && return ()
    statement isa HistoryState && return (
        root_shape...,
        Int(_numeric_value(_statement_option(statement, :depth, 1))),
    )
    statement isa RelationshipState && return (
        capacity = Int(_numeric_value(_statement_option(statement, :capacity))),
        maximum_degree = Int(_numeric_value(
            _statement_option(statement, :maximum_degree)
        )),
    )
    return ()
end

function _symbolic_result_type(value)
    classification = SymbolicIndexingInterface.symbolic_type(value)
    classification isa SymbolicIndexingInterface.NotSymbolic &&
        return typeof(value)
    classification isa SymbolicIndexingInterface.ScalarSymbolic && return Real
    classification isa SymbolicIndexingInterface.ArraySymbolic &&
        return AbstractArray
    return Any
end

function _record_result_type(statement)
    arguments = _statement_arguments(statement)
    if arguments isa NamedTuple && haskey(arguments, :expression)
        return _symbolic_result_type(arguments.expression)
    end
    statement isa Union{
        SynchronousProcess, AcceptedCopyProcess, RelationshipProcess,
        LifecycleProcess, Protocol,
    } && return Nothing
    statement isa Union{
        SiteState, CellState, MediumState, ModelState, FieldState, HistoryState,
    } && return haskey(arguments, :variable) ?
          _symbolic_result_type(arguments.variable) :
          arguments.initial === nothing ? Any :
          _symbolic_result_type(arguments.initial)
    return Nothing
end

function _record_ownership(statement)
    options = _statement_options(statement)
    haskey(options, :owner) && return _manifest_symbol(options.owner)
    statement isa CellState && return :cell
    statement isa MediumState && return :medium
    statement isa ModelState && return :model
    statement isa Union{SiteState, FieldState, HistoryState} && return :site
    statement isa RelationshipState && return :relationship
    return :none
end

function _record_lifecycle(statement)
    options = _statement_options(statement)
    declared = haskey(options, :lifecycle) ?
               nameof(typeof(options.lifecycle)) : nothing
    effects = _statement_arguments(statement)
    effect_names = effects isa NamedTuple && haskey(effects, :effects) ?
                   Tuple(nameof(typeof(effect)) for effect in effects.effects) : ()
    return (declared, effects = effect_names)
end

function _registered_definition(
        registry::StatementRegistry, statement::RegisteredStatement
    )
    arguments = _statement_arguments(statement)
    index = findfirst(
        definition -> definition.schema === arguments.schema &&
                      definition.version == arguments.version,
        registry.definitions,
    )
    return index === nothing ? nothing : registry.definitions[index]
end

function _registered_effect(contract)
    contract.effect === :pure_read && return PureRead()
    contract.effect === :synchronous_assign && return SynchronousAssign()
    contract.effect === :accepted_copy && return AcceptedCopyEffect()
    contract.effect === :ordered_batch && return OrderedBatchEffect()
    error("unreachable registered effect")
end

function _phase_rank(phase)
    ranks = (
        Proposal => 1,
        AcceptedCopy => 2,
        AfterMCS => 3,
        RelationshipCommit => 4,
        Lifecycle => 5,
    )
    phase === nothing && return 0.0
    phase isa Before && return _phase_rank(phase.phase) - 0.25
    phase isa After && return _phase_rank(phase.phase) + 0.25
    for (phase_type, rank) in ranks
        phase isa phase_type && return Float64(rank)
    end
    throw(ArgumentError("unsupported semantic phase $(typeof(phase))"))
end

function _phase_contract(statement, phase)
    statement isa AcceptedCopyProcess &&
        return phase isa AcceptedCopy
    statement isa SynchronousProcess &&
        return phase isa AfterMCS
    statement isa RelationshipProcess &&
        return phase isa RelationshipCommit
    statement isa LifecycleProcess &&
        return phase isa Lifecycle
    statement isa Observation &&
        return phase === nothing
    return true
end

function _draw_parameter_error(arguments)
    family = _draw_family(arguments)
    first_parameter = _draw_literal(arguments[2])
    second_parameter = _draw_literal(arguments[3])
    if family === :bernoulli && first_parameter isa Real &&
            !(zero(first_parameter) <= first_parameter <= one(first_parameter))
        return "Bernoulli probability must lie in [0, 1]"
    elseif family === :uniform &&
            first_parameter isa Real && second_parameter isa Real &&
            !(first_parameter < second_parameter)
        return "Uniform minimum must be less than its maximum"
    elseif family === :normal && second_parameter isa Real &&
            !(second_parameter > zero(second_parameter))
        return "Normal standard deviation must be positive"
    elseif family === :unit_vector && first_parameter isa Real &&
            !(isinteger(first_parameter) && first_parameter > 0)
        return "UnitVector dimension must be a positive integer"
    end
    return nothing
end

function _validate_statement_draws!(diagnostics, statement, identity, path)
    calls = _draw_calls(statement)
    isempty(calls) && return nothing
    if statement isa HamiltonianTerm
        push!(diagnostics, PottsDiagnostic(
            :stochastic_hamiltonian,
            identity,
            _statement_expression(statement),
            path,
            "a deterministic conservative energy expression",
            "a Hamiltonian expression containing a random draw",
            (),
            statement_source(statement),
        ))
        return nothing
    end
    statement isa Union{
        ProposalDrive, ProposalConstraint, ProposalModifier,
        SynchronousProcess, AcceptedCopyProcess, RelationshipProcess,
        LifecycleProcess, Observation, RegisteredStatement,
    } || push!(diagnostics, PottsDiagnostic(
        :illegal_random_operation_context,
        identity,
        _statement_expression(statement),
        path,
        "a process, proposal, equation, or observation expression",
        String(statement_kind(statement)),
        (),
        statement_source(statement),
    ))
    for arguments in calls
        if _draw_family(arguments) === :unit_vector && statement isa Union{
                ProposalDrive, ProposalConstraint, ProposalModifier,
            }
            push!(diagnostics, PottsDiagnostic(
                :nonscalar_distribution_in_proposal_term,
                identity,
                _statement_expression(statement),
                path,
                "a scalar Bernoulli, Uniform, or Normal distribution",
                "UnitVector",
                (),
                statement_source(statement),
            ))
            continue
        end
        message = _draw_parameter_error(arguments)
        message === nothing && continue
        push!(diagnostics, PottsDiagnostic(
            :invalid_random_distribution,
            identity,
            _statement_expression(statement),
            path,
            "valid distribution parameters",
            message,
            (),
            statement_source(statement),
        ))
    end
    return nothing
end

"""Reject declared public markers whose executable semantics are not yet V1."""
function _validate_builtin_marker_support!(
        diagnostics, statement, identity, path
    )
    options = _statement_options(statement)
    if statement isa ProposalDrive &&
            get(options, :mechanism, nothing) === :chemotaxis
        mode = get(options, :mode, ExtensionsOnly())
        if !(mode isa ExtensionsOnly)
            push!(diagnostics, PottsDiagnostic(
                :unsupported_chemotaxis_mode,
                identity,
                _statement_expression(statement),
                path,
                "ExtensionsOnly() in the V1 executable profile",
                string(nameof(typeof(mode))),
                (),
                statement_source(statement),
            ))
        end
        sample = get(options, :sample, Nearest())
        if !(sample isa Nearest)
            push!(diagnostics, PottsDiagnostic(
                :unsupported_chemotaxis_sampling,
                identity,
                _statement_expression(statement),
                path,
                "Nearest() in the V1 executable profile",
                string(nameof(typeof(sample))),
                (),
                statement_source(statement),
            ))
        end
    elseif statement isa FieldState &&
            get(options, :placement, nothing) isa CellCentered
        push!(diagnostics, PottsDiagnostic(
            :unsupported_field_placement,
            identity,
            _statement_expression(statement),
            path,
            "field placement implemented by a reviewed field backend",
            "CellCentered",
            (),
            statement_source(statement),
        ))
    end
    return nothing
end

function _with_registered_origin(statement, origin, source)
    core = getfield(statement, :core)
    options = merge(core.options, (__registered_origin = origin,))
    statement_type = typeof(statement).name.wrapper
    effective_source = statement_source(statement) isa UnknownSource ?
                       source : statement_source(statement)
    return statement_type(StatementCore(
        core.id, core.arguments, options, effective_source
    ))
end

const _REGISTERED_ORIGIN_FIELDS = (
    :schema,
    :version,
    :serialization_identity,
    :lowering_identity,
    :descriptor_payload_type,
    :scientific_category,
    :energy_domain,
    :affected_region,
)

function _registered_origin_for(definition::StatementDefinition)
    return (
        schema = definition.schema,
        version = definition.version,
        serialization_identity =
            String(definition.contract.serialization_identity),
        lowering_identity = definition.contract.lowering_identity,
        descriptor_payload_type =
            definition.contract.descriptor_payload_type,
        scientific_category = definition.contract.scientific_category,
        energy_domain = definition.contract.energy_domain,
        affected_region = definition.contract.affected_region,
    )
end

function _statement_scientific_category(statement)
    statement isa HamiltonianTerm && return :hamiltonian
    statement isa ProposalDrive && return :drive
    statement isa ProposalConstraint && return :constraint
    statement isa ProposalModifier && return :modifier
    statement isa Observation && return :observation
    return :process
end

function _statement_energy_domain(statement)
    statement isa HamiltonianTerm || return nothing
    domain = _statement_arguments(statement).domain
    domain isa Sites && return :sites
    domain isa Cells && return :cells
    domain isa Contacts && return :contacts
    domain isa Edges && return :relationships
    return :invalid
end

function _authenticated_registered_origin(
        registry::StatementRegistry,
        origin,
    )
    origin isa NamedTuple && keys(origin) == _REGISTERED_ORIGIN_FIELDS ||
        return nothing
    index = findfirst(
        definition -> definition.schema === origin.schema &&
                      definition.version == origin.version,
        registry.definitions,
    )
    index === nothing && return nothing
    definition = registry.definitions[index]
    return isequal(origin, _registered_origin_for(definition)) ?
           definition : nothing
end

function _registered_lowering_result(value)
    value isa AbstractPottsStatement && return (value,)
    value isa StatementSet && return statements(value)
    value isa Tuple && return statements(StatementSet(value))
    throw(ArgumentError(
        "registered_statement_lowering must return a Potts statement, " *
        "StatementSet, or tuple of Potts statements"
    ))
end

function _same_symbolic_set(left, right)
    length(left) == length(right) || return false
    return all(value -> any(isequal(value), right), left)
end

function _registered_access_values(arguments, indices)
    values = Any[]
    for index in indices
        argument = arguments[index]
        symbolic_values = _collect_symbolics(argument)
        if isempty(symbolic_values)
            any(isequal(argument), values) || push!(values, argument)
        else
            for value in symbolic_values
                any(isequal(value), values) || push!(values, value)
            end
        end
    end
    return Tuple(values)
end

function _validate_registered_lowering!(
        diagnostics,
        registered::RegisteredStatement,
        lowered,
        definition,
        identity,
        path,
    )
    contract = definition.contract
    arguments = _statement_arguments(registered).arguments
    if length(lowered) != 1
        push!(diagnostics, PottsDiagnostic(
            :registered_lowering_cardinality,
            identity,
            _statement_expression(registered),
            path,
            "exactly one qualified built-in V1 statement",
            "$(length(lowered)) statements",
            (),
            statement_source(registered),
        ))
        return false
    end
    statement = only(lowered)
    if statement isa RegisteredStatement
        push!(diagnostics, PottsDiagnostic(
            :recursive_registered_lowering,
            identity,
            _statement_expression(registered),
            path,
            "a built-in V1 statement",
            "RegisteredStatement",
            (),
            statement_source(registered),
        ))
        return false
    end
    writes = _statement_writes(statement)
    reads = _statement_reads(statement, writes)
    expected_reads = _registered_access_values(
        arguments, contract.access.reads
    )
    expected_writes = _registered_access_values(
        arguments, contract.access.writes
    )
    inferred_effect = _statement_effect(statement)
    inferred_bound = _effect_bound(statement)
    inferred_phase = _statement_phase(statement)
    inferred_admission = _engine_admission(statement)
    inferred_random = _random_operations(statement, identity)
    inferred_result = _record_result_type(statement)
    inferred_category = _statement_scientific_category(statement)
    inferred_energy_domain = _statement_energy_domain(statement)
    checks = (
        (
            :registered_result_type_mismatch,
            inferred_result === contract.result_type,
            repr(contract.result_type),
            repr(inferred_result),
        ),
        (
            :registered_read_contract_mismatch,
            _same_symbolic_set(reads, expected_reads),
            repr(expected_reads),
            repr(reads),
        ),
        (
            :registered_write_contract_mismatch,
            _same_symbolic_set(writes, expected_writes),
            repr(expected_writes),
            repr(writes),
        ),
        (
            :registered_effect_contract_mismatch,
            inferred_effect == _registered_effect(contract),
            String(contract.effect),
            String(nameof(typeof(inferred_effect))),
        ),
        (
            :registered_bound_contract_mismatch,
            inferred_bound.maximum == contract.boundedness.maximum &&
                inferred_bound.basis === contract.boundedness.basis,
            repr(contract.boundedness),
            repr((
                maximum = inferred_bound.maximum,
                basis = inferred_bound.basis,
            )),
        ),
        (
            :registered_phase_contract_mismatch,
            isequal(inferred_phase, contract.phase),
            repr(contract.phase),
            repr(inferred_phase),
        ),
        (
            :registered_rng_contract_mismatch,
            Tuple((item.identity, item.family, item.reserved)
                for item in inferred_random) ==
                Tuple((item.identity, item.family, item.reserved)
                    for item in contract.rng),
            repr(contract.rng),
            repr(inferred_random),
        ),
        (
            :registered_engine_contract_mismatch,
            all(
                admission -> getproperty(
                    contract.capabilities, admission.engine
                ) == admission.admitted,
                inferred_admission,
            ),
            repr(contract.capabilities),
            repr(inferred_admission),
        ),
        (
            :registered_scientific_category_mismatch,
            inferred_category === contract.scientific_category,
            String(contract.scientific_category),
            String(inferred_category),
        ),
        (
            :registered_energy_domain_mismatch,
            inferred_energy_domain === contract.energy_domain,
            repr(contract.energy_domain),
            repr(inferred_energy_domain),
        ),
    )
    valid = true
    for (kind, passed, expected, actual) in checks
        passed && continue
        valid = false
        push!(diagnostics, PottsDiagnostic(
            kind,
            identity,
            _statement_expression(registered),
            path,
            expected,
            actual,
            (),
            statement_source(registered),
        ))
    end
    return valid
end
