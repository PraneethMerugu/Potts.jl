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

