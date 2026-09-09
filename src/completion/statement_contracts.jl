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

function _record_units(statement, inventory::_PottsSourceInventory, identity::QualifiedStatementID)
    quantities = Any[]
    _collect_quantities!(quantities, _statement_arguments(statement))
    _collect_quantities!(quantities, _statement_options(statement))
    variables = _collect_symbolics(
        (
            _statement_arguments(statement), _statement_options(statement),
        )
    )
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
        map(quantities) do value
            payload = DynamicQuantities.ustrip(value)
            SymbolicIndexingInterface.symbolic_type(payload) isa SymbolicIndexingInterface.NotSymbolic || throw(
                PottsValidationError(
                    :completion, (
                        PottsDiagnostic(
                            :unsupported_symbolic_quantity, identity, repr(value), identity.path,
                            "a concrete quantity; declare symbolic units through parameter defaults or state initial values",
                            "a quantity containing a symbolic value", (), statement_source(statement),
                        ),
                    )
                )
            )
            return (dimension = string(DynamicQuantities.dimension(value)), scale = Float64(payload))
        end
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

function _history_source_contract(statement::HistoryState, inventory::_PottsSourceInventory)
    source = _statement_option(statement, :of, nothing)
    source === nothing && throw(ArgumentError("HistoryState requires an explicit `of` source"))
    matches = Any[]
    for occurrence in inventory.statements
        candidate = _namespace_statement(occurrence.statement, occurrence.path)
        candidate isa Union{ModelState, CellState, SiteState, FieldState} || continue
        arguments = _statement_arguments(candidate)
        haskey(arguments, :variable) && isequal(arguments.variable, source) || continue
        push!(
            matches, (
                declaration = candidate,
                identity = QualifiedStatementID(occurrence.path, statement_id(occurrence.statement)),
            )
        )
    end
    length(matches) == 1 || throw(
        ArgumentError(
            "HistoryState source must identify exactly one declared model, cell, site, or field state"
        )
    )
    depth = _numeric_value(_statement_option(statement, :depth, 1))
    depth isa Integer && !(depth isa Bool) && depth > 0 || throw(
        ArgumentError(
            "HistoryState depth must be a positive integer number of retained samples"
        )
    )
    cadence = _statement_option(statement, :cadence, EveryMCS())
    cadence isa Union{EveryMCS, Every, AtMCS} || throw(
        ArgumentError(
            "HistoryState cadence must be EveryMCS(), Every(n), or AtMCS(n)"
        )
    )
    return only(matches)
end

function _history_declaration_diagnostic(statement, path, exception)
    return PottsDiagnostic(
        :invalid_history_declaration, QualifiedStatementID(path, statement_id(statement)),
        _statement_expression(statement), path,
        "a unique owned source, positive retention, and explicit completed-MCS cadence",
        sprint(showerror, exception), (), statement_source(statement),
    )
end

function _record_shape(statement, root_shape, history_source = nothing)
    statement isa LatticeDomain &&
        return _statement_option(statement, :shape, root_shape)
    statement isa Union{SiteState, FieldState} && return root_shape
    statement isa CellState && return :cells
    statement isa MediumState && return :media
    statement isa ModelState && return ()
    if statement isa HistoryState
        source_shape = _record_shape(history_source, root_shape)
        extent = source_shape === :cells ? (:cells,) :
            isempty(source_shape) ? (1,) : source_shape
        return (extent..., Int(_numeric_value(_statement_option(statement, :depth, 1))))
    end
    statement isa RelationshipState && return (
        capacity = Int(_numeric_value(_statement_option(statement, :capacity))),
        maximum_degree = Int(
            _numeric_value(
                _statement_option(statement, :maximum_degree)
            )
        ),
    )
    return ()
end

function _symbolic_result_type(value)
    classification = SymbolicIndexingInterface.symbolic_type(value)
    classification isa SymbolicIndexingInterface.NotSymbolic &&
        return typeof(value)
    classification isa Union{
        SymbolicIndexingInterface.ScalarSymbolic,
        SymbolicIndexingInterface.ArraySymbolic,
    } && return SymbolicUtils.symtype(Symbolics.unwrap(value))
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
