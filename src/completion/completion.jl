struct CompletedPottsData{R, U, P, Q, V, S, C, F, D}
    registry::R
    reference_units::U
    parameter_roles::P
    records::Q
    variables::V
    schedule::S
    capabilities::C
    fingerprints::F
    diagnostics::D
end

const _STRUCTURAL_OPTION_NAMES = Set((
    :shape,
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
            AbstractRelationshipEndpointPolicy, SweepStage, ObserveStage,
            SymmetricPair,
        }
        for field in fieldnames(typeof(value))
            _collect_quantities!(found, getfield(value, field))
        end
    end
    return found
end

function _completion_quantities(system::PottsSystem)
    quantities = Any[]
    for statement in _all_system_statements(system)
        _collect_quantities!(quantities, _statement_arguments(statement))
        _collect_quantities!(quantities, _statement_options(statement))
    end
    for parameter in ModelingToolkitBase.parameters(system)
        ModelingToolkitBase.hasdefault(parameter) || continue
        _collect_quantities!(
            quantities, ModelingToolkitBase.getdefault(parameter)
        )
    end
    _collect_quantities!(quantities, getfield(system, :initial_conditions))
    return quantities
end

function _completion_reference_anchors(system, option)
    if option isa ReferenceUnits
        return Pair{Symbol, Any}[
            name => getproperty(option.values, name)
            for name in keys(option.values)
        ]
    end
    anchors = Pair{Symbol, Any}[]
    for statement in _all_system_statements(system)
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
        elseif statement isa EquationProcess
            value = _statement_option(
                statement, :duration_per_mcs, nothing
            )
            value isa DynamicQuantities.UnionAbstractQuantity &&
                push!(anchors, Symbol(:time_, statement_id(statement)) => value)
        elseif statement isa Union{
                SiteState, CellState, MediumState, ModelState, FieldState,
                HistoryState,
            }
            value = _statement_arguments(statement).initial
            value isa DynamicQuantities.UnionAbstractQuantity &&
                push!(anchors, Symbol(:state_, statement_id(statement)) => value)
        end
    end
    return anchors
end

function _validate_completion_reference_units(system, option)
    quantities = _completion_quantities(system)
    isempty(quantities) && return nothing
    anchors = _completion_reference_anchors(system, option)
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
            AbstractRelationshipEndpointPolicy, SweepStage, ObserveStage,
            SymmetricPair,
        }
        for field in fieldnames(typeof(value))
            _structural_parameter_variables!(found, getfield(value, field))
        end
    end
    return found
end

function _structural_parameters(system::PottsSystem)
    candidates = Any[]
    for statement in _all_system_statements(system)
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
    parameters = ModelingToolkitBase.parameters(system)
    return Tuple(parameter for parameter in parameters
        if any(candidate -> isequal(candidate, parameter), candidates))
end

function _resolve_structural_parameters(system::PottsSystem)
    structural = _structural_parameters(system)
    isempty(structural) && return system, ()
    substitutions = Dict{Any, Any}()
    manifest = NamedTuple[]
    for parameter in structural
        name = _symbolic_name(parameter; context = "structural parameter")
        ModelingToolkitBase.hasdefault(parameter) || throw(ArgumentError(
            "structural parameter `$name` must have a concrete default or be " *
            "substituted before completion"
        ))
        value = ModelingToolkitBase.getdefault(parameter)
        isempty(Symbolics.get_variables(value)) || throw(ArgumentError(
            "structural parameter `$name` did not resolve to a concrete value"
        ))
        substitutions[parameter] = value
        push!(manifest, (; name, value))
    end
    resolved = Symbolics.substitute(system, substitutions)
    sort!(manifest; by = entry -> String(entry.name))
    return resolved, Tuple(manifest)
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
            AbstractRelationshipEndpointPolicy, SweepStage, ObserveStage,
            SymmetricPair,
        }
        foreach(
            field -> _record_resources!(result, getfield(value, field), path),
            fieldnames(typeof(value)),
        )
    end
    return result
end

function _record_units(statement, system)
    quantities = Any[]
    _collect_quantities!(quantities, _statement_arguments(statement))
    _collect_quantities!(quantities, _statement_options(statement))
    variables = _collect_symbolics((
        _statement_arguments(statement), _statement_options(statement)
    ))
    for parameter in ModelingToolkitBase.parameters(system)
        any(variable -> isequal(variable, parameter), variables) || continue
        ModelingToolkitBase.hasdefault(parameter) || continue
        _collect_quantities!(
            quantities, ModelingToolkitBase.getdefault(parameter)
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

function _record_reference_conversion(units, system, reference_units)
    isempty(units) && return ()
    anchors = _completion_reference_anchors(system, reference_units)
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
        LifecycleProcess, EquationProcess, Protocol,
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
        EquationStep => 6,
        Observe => 7,
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
    statement isa EquationProcess &&
        return phase isa Union{EquationStep, Before, After}
    statement isa Observation &&
        return phase isa Observe
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
    statement isa Union{
        ProposalEnergy, ProposalDrive, ProposalConstraint, ProposalModifier,
        SynchronousProcess, AcceptedCopyProcess, RelationshipProcess,
        LifecycleProcess, EquationProcess, Observation, RegisteredStatement,
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
    expected_reads = Tuple(arguments[index] for index in contract.access.reads)
    expected_writes = Tuple(arguments[index] for index in contract.access.writes)
    inferred_effect = _statement_effect(statement)
    inferred_bound = _effect_bound(statement)
    inferred_phase = _statement_phase(statement)
    inferred_admission = _engine_admission(statement)
    inferred_random = _random_operations(statement, identity)
    inferred_result = _record_result_type(statement)
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

function _expand_registered_system(
        system::PottsSystem,
        registry::StatementRegistry,
        diagnostics = PottsDiagnostic[],
        parent_path::Tuple = (),
    )
    path = (parent_path..., nameof(system))
    expanded = AbstractPottsStatement[]
    for statement in statements(system)
        statement isa RegisteredStatement || begin
            push!(expanded, statement)
            continue
        end
        identity = QualifiedStatementID(path, statement_id(statement))
        definition = _registered_definition(registry, statement)
        if definition === nothing
            arguments = _statement_arguments(statement)
            push!(diagnostics, PottsDiagnostic(
                :unregistered_statement_schema,
                identity,
                _statement_expression(statement),
                path,
                "a frozen registered schema $(arguments.schema) $(arguments.version)",
                "no matching definition",
                (),
                statement_source(statement),
            ))
            continue
        end
        arguments = _statement_arguments(statement).arguments
        expected = definition.contract.argument_types
        if length(arguments) != length(expected) ||
                !all(index -> arguments[index] isa expected[index], eachindex(arguments))
            push!(diagnostics, PottsDiagnostic(
                :registered_argument_type_mismatch,
                identity,
                _statement_expression(statement),
                path,
                repr(expected),
                repr(typeof.(arguments)),
                (),
                statement_source(statement),
            ))
            continue
        end
        lowered = try
            _registered_lowering_result(registered_statement_lowering(
                Val(definition.contract.lowering_identity),
                statement_id(statement),
                arguments,
                _statement_options(statement),
                statement_source(statement),
            ))
        catch error
            kind = error isa MethodError &&
                   error.f === registered_statement_lowering ?
                   :registered_lowering_unavailable :
                   :registered_lowering_failed
            push!(diagnostics, PottsDiagnostic(
                kind,
                identity,
                _statement_expression(statement),
                path,
                "a total registered lowering into built-in V1 IR",
                sprint(showerror, error),
                (),
                statement_source(statement),
            ))
            continue
        end
        _validate_registered_lowering!(
            diagnostics, statement, lowered, definition, identity, path
        ) || continue
        origin = (
            schema = definition.schema,
            version = definition.version,
            serialization_identity =
                String(definition.contract.serialization_identity),
            lowering_identity = definition.contract.lowering_identity,
        )
        append!(
            expanded,
            (_with_registered_origin(item, origin, statement_source(statement))
             for item in lowered),
        )
    end
    children = PottsSystem[
        _expand_registered_system(child, registry, diagnostics, path)
        for child in getfield(system, :systems)
    ]
    return _rebuild(system; statements = StatementSet(expanded), systems = children)
end

function _namespace_statement_names(
        statement::AbstractPottsStatement, names
    )
    isempty(names) && return statement
    namespace = Symbol[name for name in names]
    namespace_variable = function (variable)
        name = try
            Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(variable)))
        catch
            nothing
        end
        # These are globally scoped compiler tokens, not model variables.
        name !== nothing && startswith(String(name), "__potts_") &&
            return variable
        return foldr(
            (scope, current) ->
                ModelingToolkitBase.renamespace(scope, current),
            namespace;
            init = variable,
        )
    end
    namespace_value = function (value)
        variables = try
            Symbolics.get_variables(value)
        catch
            ()
        end
        isempty(variables) && return value
        replacements = Dict{Any, Any}()
        for variable in variables
            namespaced = namespace_variable(variable)
            isequal(namespaced, variable) ||
                (replacements[variable] = namespaced)
        end
        isempty(replacements) && return value
        return Symbolics.substitute(value, replacements)
    end
    return map_symbolics(namespace_value, statement)
end

function _namespace_reference_payload(value, names)
    if value isa AbstractPottsStatement
        return _namespace_statement_for_lowering(value, names)
    elseif value isa NamedTuple
        mapped = map(
            item -> _namespace_reference_payload(item, names), values(value)
        )
        return NamedTuple{keys(value)}(mapped)
    elseif value isa Tuple
        return map(item -> _namespace_reference_payload(item, names), value)
    elseif value isa Pair
        return _namespace_reference_payload(first(value), names) =>
               _namespace_reference_payload(last(value), names)
    elseif value isa AbstractArray
        return map(item -> _namespace_reference_payload(item, names), value)
    elseif value isa AbstractDict
        return Dict(
            _namespace_reference_payload(key, names) =>
                _namespace_reference_payload(item, names)
            for (key, item) in value
        )
    elseif value isa Union{
            AbstractPottsEffect, AbstractIterationDomain, AbstractBoundaryPolicy,
            AbstractRelationshipEndpointPolicy, SweepStage, ObserveStage,
            SymmetricPair,
        }
        mapped = map(
            field -> _namespace_reference_payload(getfield(value, field), names),
            fieldnames(typeof(value)),
        )
        return typeof(value)(mapped...)
    end
    return value
end

function _namespace_statement_for_lowering(
        statement::AbstractPottsStatement, names
    )
    isempty(names) && return statement
    namespaced = _namespace_statement_names(statement, names)
    core = getfield(namespaced, :core)
    qualified_id = StatementID(Symbol(join(
        (String(name) for name in (names..., Symbol(core.id))), "₊"
    )))
    statement_type = typeof(namespaced).name.wrapper
    return statement_type(StatementCore(
        qualified_id,
        _namespace_reference_payload(core.arguments, names),
        _namespace_reference_payload(core.options, names),
        core.source,
    ))
end

_namespace_statement(statement::AbstractPottsStatement, current_path::Tuple) =
    _namespace_statement_names(statement, current_path[2:end])

function _qualify_records!(
        records,
        diagnostics,
        system::PottsSystem,
        path::Tuple,
        root::PottsSystem,
        reference_units,
        root_shape,
        registry::StatementRegistry,
    )
    current_path = (path..., nameof(system))
    seen = Dict{StatementID, AbstractPottsStatement}()
    for originating_statement in statements(system)
        id = statement_id(originating_statement)
        if haskey(seen, id)
            first_statement = seen[id]
            push!(diagnostics, PottsDiagnostic(
                :duplicate_statement_identity,
                QualifiedStatementID(current_path, id),
                _statement_expression(originating_statement),
                current_path,
                "a namespace-local unique StatementID",
                "duplicates $(_statement_expression(first_statement))",
                (),
                statement_source(originating_statement),
            ))
            continue
        end
        seen[id] = originating_statement
        statement = _namespace_statement(originating_statement, current_path)
        identity = QualifiedStatementID(current_path, id)
        registered = statement isa RegisteredStatement ?
                     _registered_definition(registry, statement) : nothing
        if statement isa RegisteredStatement && registered === nothing
            arguments = _statement_arguments(statement)
            push!(diagnostics, PottsDiagnostic(
                :unregistered_statement_schema,
                identity,
                _statement_expression(originating_statement),
                current_path,
                "a frozen registered schema $(arguments.schema) $(arguments.version)",
                "no matching definition",
                (),
                statement_source(originating_statement),
            ))
            continue
        end
        if registered !== nothing
            arguments = _statement_arguments(statement).arguments
            expected = registered.contract.argument_types
            if length(arguments) != length(expected) ||
                    !all(
                        index -> arguments[index] isa expected[index],
                        eachindex(arguments),
                    )
                push!(diagnostics, PottsDiagnostic(
                    :registered_argument_type_mismatch,
                    identity,
                    _statement_expression(originating_statement),
                    current_path,
                    repr(expected),
                    repr(typeof.(arguments)),
                    (),
                    statement_source(originating_statement),
                ))
                continue
            end
        end
        writes = _statement_writes(statement)
        reads = _statement_reads(statement, writes)
        effect = registered === nothing ?
                 _statement_effect(statement) :
                 _registered_effect(registered.contract)
        phase = registered === nothing ?
                _statement_phase(statement) : registered.contract.phase
        if !_phase_contract(statement, phase)
            push!(diagnostics, PottsDiagnostic(
                :illegal_effect_phase,
                identity,
                _statement_expression(originating_statement),
                current_path,
                "the semantic phase admitted by $(statement_kind(statement))",
                repr(phase),
                (),
                statement_source(originating_statement),
            ))
            continue
        end
        try
            _phase_rank(phase)
        catch error
            push!(diagnostics, PottsDiagnostic(
                :unsupported_semantic_phase,
                identity,
                _statement_expression(originating_statement),
                current_path,
                "a V1 semantic anchor or Before/After anchor",
                sprint(showerror, error),
                (),
                statement_source(originating_statement),
            ))
            continue
        end
        _validate_statement_draws!(
            diagnostics, statement, identity, current_path
        )
        random_operations = if registered === nothing
            _random_operations(statement, identity)
        else
            Tuple(
                RandomOperation(
                    operation.identity,
                    operation.family,
                    operation.reserved,
                )
                for operation in registered.contract.rng
            )
        end
        units = _record_units(statement, root)
        reference_conversion = _record_reference_conversion(
            units, root, reference_units
        )
        resources = Tuple(_record_resources!(
            QualifiedStatementID[],
            (_statement_arguments(statement), _statement_options(statement)),
            current_path,
        ))
        mutating = !(effect isa PureRead)
        origin = let options = _statement_options(statement)
            haskey(options, :__registered_origin) ?
            options.__registered_origin : nothing
        end
        record = QualifiedStatement(
            identity,
            statement_kind(statement),
            origin === nothing ? v"1.0.0" : origin.version,
            statement_source(statement),
            origin === nothing ? (
                source_capture = statement_source(statement) isa SourceLocation ?
                                 :captured : :direct,
                schema = :built_in_v1,
            ) : (
                source_capture = statement_source(statement) isa SourceLocation ?
                                 :captured : :direct,
                schema = origin.schema,
                registered_version = origin.version,
                serialization_identity = origin.serialization_identity,
                registered_lowering_identity = origin.lowering_identity,
            ),
            (_statement_arguments(statement), _statement_options(statement)),
            registered === nothing ?
            _record_result_type(statement) : registered.contract.result_type,
            _record_shape(statement, root_shape),
            units,
            reference_conversion,
            reads,
            writes,
            _record_ownership(statement),
            statement isa Union{
                SiteState, CellState, MediumState, ModelState, FieldState,
                HistoryState, RelationshipState,
            } ? :logical : :none,
            resources,
            effect,
            registered === nothing ?
            _effect_bound(statement) :
            EffectBound(
                registered.contract.boundedness.maximum,
                registered.contract.boundedness.basis,
            ),
            mutating ? identity : nothing,
            _record_lifecycle(statement),
            random_operations,
            phase,
            (),
            registered === nothing ?
            _engine_admission(statement) :
            (
                EngineAdmission(
                    :sequential,
                    registered.contract.capabilities.sequential,
                    registered.contract.capabilities.sequential ?
                    "" : registered.contract.capabilities.reason,
                ),
                EngineAdmission(
                    :checkerboard,
                    registered.contract.capabilities.checkerboard,
                    registered.contract.capabilities.checkerboard ?
                    "" : registered.contract.capabilities.reason,
                ),
            ),
            registered === nothing ?
            _lowering_identity(statement) :
            registered.contract.lowering_identity,
        )
        push!(records, record)
    end
    for child in getfield(system, :systems)
        _qualify_records!(
            records,
            diagnostics,
            child,
            current_path,
            root,
            reference_units,
            root_shape,
            registry,
        )
    end
    return records
end

function _completion_variables(system::PottsSystem, records)
    result = Any[]
    for collection in (
            ModelingToolkitBase.unknowns(system),
            ModelingToolkitBase.parameters(system),
            ModelingToolkitBase.independent_variables(system),
        )
        for value in collection
            any(isequal(value), result) || push!(result, value)
        end
    end
    for record in records
        for value in (record.reads..., record.writes...)
            value isa AbstractPottsStatement && continue
            any(isequal(value), result) || push!(result, value)
        end
    end
    return Tuple(result)
end

function _with_ordering_dependencies(record, dependencies)
    return QualifiedStatement(
        record.identity,
        record.kind,
        record.schema_version,
        record.source,
        record.provenance,
        record.normalized_payload,
        record.result_type,
        record.shape,
        record.units,
        record.reference_conversion,
        record.reads,
        record.writes,
        record.ownership,
        record.persistence,
        record.resources,
        record.effect,
        record.bound,
        record.transaction_identity,
        record.lifecycle,
        record.random_operations,
        record.phase,
        dependencies,
        record.engine_admission,
        record.lowering_identity,
    )
end

function _completion_schedule(records)
    sorted = sort(
        collect(records);
        by = record -> (_phase_rank(record.phase), string(record.identity)),
    )
    scheduled = QualifiedStatement[]
    for record in sorted
        rank = _phase_rank(record.phase)
        lower = filter(
            previous -> previous.phase !== nothing &&
                        _phase_rank(previous.phase) < rank,
            scheduled,
        )
        dependency_rank = isempty(lower) ? nothing :
                          maximum(_phase_rank(previous.phase) for previous in lower)
        dependencies = dependency_rank === nothing ? () : Tuple(
            previous.identity
            for previous in lower
            if _phase_rank(previous.phase) == dependency_rank
        )
        push!(scheduled, _with_ordering_dependencies(record, dependencies))
    end
    return Tuple(scheduled)
end

function _validate_random_key_uniqueness!(diagnostics, records)
    seen = Dict{Tuple{Tuple, Symbol}, QualifiedStatementID}()
    for record in records
        for operation in record.random_operations
            operation.reserved && continue
            key = (record.identity.path, operation.identity)
            if haskey(seen, key)
                push!(diagnostics, PottsDiagnostic(
                    :duplicate_draw_key,
                    record.identity,
                    record.source isa SourceLocation ?
                    record.source.expression : string(record.identity),
                    record.identity.path,
                    "a namespace-local unique DrawKey",
                    "duplicates $(seen[key])",
                    (),
                    record.source,
                ))
            else
                seen[key] = record.identity
            end
        end
    end
    return nothing
end

function _completion_capabilities(records)
    sequential = all(
        admission -> admission.admitted,
        (
            only(filter(item -> item.engine === :sequential, record.engine_admission))
            for record in records
        ),
    )
    checkerboard_rejections = Tuple(
        (
            record.identity,
            admission.reason,
        )
        for record in records
        for admission in record.engine_admission
        if admission.engine === :checkerboard && !admission.admitted
    )
    return (
        sequential = sequential,
        checkerboard = isempty(checkerboard_rejections),
        checkerboard_rejections,
        cpu = true,
    )
end

function _complete_potts(
        system::PottsSystem,
        reference_units,
        registry::StatementRegistry,
        parameter_roles,
    )
    records = QualifiedStatement[]
    diagnostics = PottsDiagnostic[]
    domains = filter(
        statement -> statement isa LatticeDomain,
        _all_system_statements(system),
    )
    root_shape = isempty(domains) ? () :
                 _statement_option(first(domains), :shape, ())
    _qualify_records!(
        records,
        diagnostics,
        system,
        (),
        system,
        reference_units,
        root_shape,
        registry,
    )
    _validate_random_key_uniqueness!(diagnostics, records)
    _throw_diagnostics(:completion, diagnostics)

    schedule = _completion_schedule(records)
    qualified_records = Tuple(schedule)
    variables = _completion_variables(system, qualified_records)
    capabilities = _completion_capabilities(qualified_records)
    semantic = _semantic_fingerprint(system, qualified_records)
    completed = _completed_fingerprint(
        semantic, qualified_records, reference_units, registry
    )
    fingerprints = (semantic = semantic, completed = completed)
    return CompletedPottsData(
        registry,
        reference_units,
        parameter_roles,
        qualified_records,
        variables,
        schedule,
        capabilities,
        fingerprints,
        (),
    )
end
