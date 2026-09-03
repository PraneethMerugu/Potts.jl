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

