# Qualification: namespace symbolic payloads and construct the ordered
# QualifiedStatement records consumed by semantic analysis.
function _namespace_symbolic_value(value, names)
    isempty(names) && return value
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

function _namespace_statement_names(
        statement::AbstractPottsStatement, names
    )
    isempty(names) && return statement
    return map_symbolics(
        value -> _namespace_symbolic_value(value, names), statement
    )
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
            AbstractRelationshipEndpointPolicy, AbstractLifecyclePolicy,
            SweepStage,
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
        inventory::_PottsSourceInventory,
        reference_anchors,
        root_shape,
        registry::StatementRegistry,
    )
    seen_by_system = Dict{
        Int32, Dict{StatementID, AbstractPottsStatement}
    }()
    for occurrence in inventory.statements
        current_path = occurrence.path
        originating_statement = occurrence.statement
        seen = get!(
            () -> Dict{StatementID, AbstractPottsStatement}(),
            seen_by_system,
            occurrence.system,
        )
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
        options = _statement_options(statement)
        origin = haskey(options, :__registered_origin) ?
                 options.__registered_origin : nothing
        if origin !== nothing &&
                _authenticated_registered_origin(registry, origin) === nothing
            push!(diagnostics, PottsDiagnostic(
                :unauthenticated_registered_origin,
                identity,
                _statement_expression(originating_statement),
                current_path,
                "internal provenance exactly matching one frozen registry definition",
                repr(origin),
                (),
                statement_source(originating_statement),
            ))
            continue
        end
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
                "an executable semantic anchor or Before/After anchor",
                sprint(showerror, error),
                (),
                statement_source(originating_statement),
            ))
            continue
        end
        _validate_statement_draws!(
            diagnostics, statement, identity, current_path
        )
        _validate_builtin_marker_support!(
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
        units = _record_units(statement, inventory)
        reference_conversion = _record_reference_conversion(
            units, reference_anchors
        )
        resources = Tuple(_record_resources!(
            QualifiedStatementID[],
            (_statement_arguments(statement), _statement_options(statement)),
            current_path,
        ))
        mutating = !(effect isa PureRead)
        record = QualifiedStatement(
            identity,
            statement_kind(statement),
            origin === nothing ? v"1.0.0" : origin.version,
            statement_source(statement),
            statement,
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
                registered_descriptor_payload_type =
                    origin.descriptor_payload_type,
                registered_scientific_category =
                    origin.scientific_category,
                registered_energy_domain = origin.energy_domain,
                registered_affected_region = origin.affected_region,
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
    return records
end

function _completion_variables(inventory::_PottsSourceInventory, records)
    result = Any[]
    for reference in inventory.references
        reference.kind in (
            :variable, :parameter, :independent_variable,
        ) || continue
        value = _namespace_symbolic_value(
            reference.value, reference.path[2:end]
        )
        any(isequal(value), result) || push!(result, value)
    end
    for record in records
        for value in (record.reads..., record.writes...)
            value isa AbstractPottsStatement && continue
            any(isequal(value), result) || push!(result, value)
        end
    end
    return result
end

function _with_ordering_dependencies(record, dependencies)
    return QualifiedStatement(
        record.identity,
        record.kind,
        record.schema_version,
        record.source,
        record.normalized_statement,
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

