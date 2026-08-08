function _expand_registered_inventory(
        inventory::_PottsSourceInventory,
        registry::StatementRegistry,
        diagnostics = PottsDiagnostic[],
    )
    groups = [AbstractPottsStatement[] for _ in inventory.systems]
    for occurrence in inventory.statements
        statement = occurrence.statement
        expanded = groups[Int(occurrence.system)]
        path = occurrence.path
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
        origin = _registered_origin_for(definition)
        append!(
            expanded,
            (_with_registered_origin(item, origin, statement_source(statement))
             for item in lowered),
        )
    end
    local_systems = PottsSystem[
        occurrence.system for occurrence in inventory.systems
    ]
    return _rebuild_source_inventory(inventory, local_systems, groups)
end

function _endpoint_retirement_constraint(relationship::RelationshipState)
    relationship_name = Symbol(statement_id(relationship))
    proposal = ProposalContext(Symbol(:endpoint_retirement_, relationship_name))
    owner = proposal.target_cell
    expression = (owner <= 0) |
                 (cell_volume(owner) != 1) |
                 (degree(relationship, owner) == 0)
    return ProposalConstraint(
        Symbol(:__potts_endpoint_retirement_, relationship_name),
        expression;
        source = statement_source(relationship),
        derived_from = :reject_endpoint_retirement,
        relationship,
    )
end

function _endpoint_removal_process(relationship::RelationshipState)
    relationship_name = Symbol(statement_id(relationship))
    edge = RelationshipBinding(
        Symbol(:endpoint_cleanup_edge_, relationship_name), relationship
    )
    expression = (cell_volume(edge.a) == 0) |
                 (cell_volume(edge.b) == 0)
    return LifecycleProcess(
        Symbol(:__potts_endpoint_cleanup_, relationship_name);
        domain = edges(relationship),
        expression,
        effects = (Remove(relationship, edge),),
        phase = Lifecycle(),
        derived_from = :remove_with_endpoint,
        source = statement_source(relationship),
    )
end

function _expand_structural_policies(
        inventory::_PottsSourceInventory,
    )
    source_groups = _inventory_statement_groups(inventory)
    expanded_groups = [AbstractPottsStatement[] for _ in inventory.systems]
    visible_by_system = Vector{Tuple}(undef, length(inventory.systems))
    for occurrence in inventory.systems
        index = Int(occurrence.index)
        expanded = AbstractPottsStatement[source_groups[index]...]
        for statement in source_groups[index]
            statement isa MediumKind && _validate_medium_extinction!(statement)
            derived = if statement isa CellKind
                _cell_extinction_statement(statement)
            elseif statement isa RelationshipState
                lifecycle = _statement_option(
                    statement, :lifecycle, RejectEndpointRetirement()
                )
                lifecycle isa RejectEndpointRetirement ?
                    _endpoint_retirement_constraint(statement) :
                lifecycle isa RemoveWithEndpoint ?
                    _endpoint_removal_process(statement) : nothing
            else
                nothing
            end
            derived === nothing && continue
            existing = findfirst(
                candidate -> statement_id(candidate) == statement_id(derived),
                expanded,
            )
            if existing === nothing
                push!(expanded, derived)
            elseif begin
                    existing_options = _statement_options(expanded[existing])
                    derived_options = _statement_options(derived)
                    existing_marker = get(
                        existing_options,
                        :compiler_synthesized,
                        get(existing_options, :derived_from, nothing),
                    )
                    derived_marker = get(
                        derived_options,
                        :compiler_synthesized,
                        get(derived_options, :derived_from, nothing),
                    )
                    existing_marker !== nothing &&
                        existing_marker === derived_marker
                end
                # An already expanded declaration retains its first resolved
                # compiler-owned statement.
                nothing
            elseif !isequal(expanded[existing], derived)
                throw(ArgumentError(
                    "relationship structural policy identity `" *
                    "$(Symbol(statement_id(derived)))` collides with a different " *
                    "statement"
                ))
            end
        end
        inherited = iszero(occurrence.parent) ? () :
                    visible_by_system[Int(occurrence.parent)]
        local_declarations = Tuple(filter(statement -> statement isa Union{
            CellState, SiteState, RelationshipState,
        }, expanded))
        visible = (inherited..., local_declarations...)
        visible_by_system[index] = visible
        resolved = AbstractPottsStatement[
            statement isa LifecycleProcess ?
                _resolve_lifecycle_process(statement, visible) : statement
            for statement in expanded
        ]
        foreach(statement -> statement isa LifecycleProcess &&
            _validate_lifecycle_process!(statement), resolved)
        expanded_groups[index] = resolved
    end
    local_systems = PottsSystem[
        occurrence.system for occurrence in inventory.systems
    ]
    return _rebuild_source_inventory(
        inventory, local_systems, expanded_groups
    )
end

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
    return scheduled
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
    checkerboard_rejections = [
        (
            record.identity,
            admission.reason,
        )
        for record in records
        for admission in record.engine_admission
        if admission.engine === :checkerboard && !admission.admitted
    ]
    return (
        sequential = sequential,
        checkerboard = isempty(checkerboard_rejections),
        checkerboard_rejections,
        cpu = true,
    )
end

function _native_source_fingerprint_or_error(
        occurrence::_SourceNativeOccurrence
    )
    source = native_source(occurrence.component)
    applicable(native_source_fingerprint, source) || throw(ArgumentError(
        "native component $(join(occurrence.path, '₊')) requires the full " *
        "ModelingToolkit extension for structural source identity"
    ))
    fingerprint = native_source_fingerprint(source)
    fingerprint isa NativeSourceFingerprint || error(
        "native_source_fingerprint must return NativeSourceFingerprint"
    )
    return fingerprint
end

function _native_endpoint_occurrence(
        inventory::_PottsSourceInventory,
        native::_SourceNativeOccurrence,
        port::_NativePort,
    )
    endpoint = potts_endpoint(port)
    exact = filter(
        occurrence -> occurrence.statement === endpoint,
        inventory.statements,
    )
    if length(exact) == 1
        return only(exact)
    elseif length(exact) > 1
        paths = join((join(item.path, '₊') for item in exact), ", ")
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) is ambiguous across $paths"
        ))
    end

    same_identity = occurrence ->
        statement_id(occurrence.statement) == statement_id(endpoint) &&
        statement_kind(occurrence.statement) === statement_kind(endpoint)
    local_matches = filter(
        occurrence -> occurrence.path == native.system_path &&
                      same_identity(occurrence),
        inventory.statements,
    )
    length(local_matches) == 1 && return only(local_matches)
    length(local_matches) > 1 && error(
        "completion admitted duplicate local statement identities"
    )

    global_matches = filter(same_identity, inventory.statements)
    if isempty(global_matches)
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) does not resolve to a Potts statement"
        ))
    elseif length(global_matches) > 1
        paths = join((join(item.path, '₊') for item in global_matches), ", ")
        throw(ArgumentError(
            "native coupling endpoint $(Symbol(statement_id(endpoint))) at " *
            "$(join(native.path, '₊')) is ambiguous across $paths"
        ))
    end
    return only(global_matches)
end

function _resolve_native_components(
        inventory::_PottsSourceInventory, records
    )
    isempty(inventory.natives) && return CompletedNativeComponent[]
    by_identity = Dict(record.identity => record for record in records)
    completed = CompletedNativeComponent[]
    seen_paths = Set{Tuple{Vararg{Symbol}}}()
    all_endpoints = CouplingEndpointSchema[]
    for native in inventory.natives
        native.path in seen_paths && throw(ArgumentError(
            "duplicate native component path $(join(native.path, '₊'))"
        ))
        push!(seen_paths, native.path)
        endpoints = CouplingEndpointSchema[]
        for port in (
                native_inputs(native.component)...,
                native_outputs(native.component)...,
            )
            occurrence = _native_endpoint_occurrence(inventory, native, port)
            identity = QualifiedStatementID(
                occurrence.path, statement_id(occurrence.statement)
            )
            record = get(by_identity, identity, nothing)
            record isa QualifiedStatement || error(
                "native endpoint $identity is missing from completion records"
            )
            if record.kind in (
                    :SiteState, :CellState, :MediumState, :ModelState,
                    :FieldState, :HistoryState,
                )
                arguments = first(record.normalized_payload)
                haskey(arguments, :variable) || throw(ArgumentError(
                    "native coupling endpoint $identity resolves to a " *
                    "$(record.kind) without symbolic storage; author it with " *
                    "the symbolic state constructor"
                ))
            end
            push!(endpoints, CouplingEndpointSchema(
                native.path, port, identity, record.kind
            ))
        end
        endpoint_tuple = Tuple(endpoints)
        append!(all_endpoints, endpoints)
        push!(completed, CompletedNativeComponent(
            native.path,
            native.component,
            endpoint_tuple,
            _native_source_fingerprint_or_error(native),
        ))
    end
    _assert_single_native_writers(all_endpoints)
    return completed
end

function _complete_potts(
        system::PottsSystem,
        inventory::_PottsSourceInventory,
        normalized_statements,
        reference_units,
        registry::StatementRegistry,
        parameter_roles,
    )
    records = QualifiedStatement[]
    diagnostics = PottsDiagnostic[]
    domains = filter(
        statement -> statement isa LatticeDomain,
        normalized_statements,
    )
    root_shape = isempty(domains) ? () :
                 _statement_option(first(domains), :shape, ())
    reference_anchors = _completion_reference_anchors(
        normalized_statements, reference_units
    )
    _qualify_records!(
        records,
        diagnostics,
        inventory,
        reference_anchors,
        root_shape,
        registry,
    )
    _validate_random_key_uniqueness!(diagnostics, records)
    _throw_diagnostics(:completion, diagnostics)

    qualified_records = _completion_schedule(records)
    schedule = qualified_records
    native_components = _resolve_native_components(
        inventory, qualified_records
    )
    variables = _completion_variables(inventory, qualified_records)
    capabilities = _completion_capabilities(qualified_records)
    semantic = _semantic_fingerprint(
        system, qualified_records, native_components
    )
    completed = _completed_fingerprint(
        semantic,
        qualified_records,
        reference_units,
        registry,
        native_components,
    )
    fingerprints = (semantic = semantic, completed = completed)
    source_graph = _freeze_source_graph(
        inventory, qualified_records, registry
    )
    # Completion freezes the complete versioned operation schema, including
    # transfer semantics, serialization identity, and the concrete device tag.
    # Compilation may re-run normalization deterministically, but it may not
    # discover a missing downstream operation implementation for the first time.
    normalized_graph = _normalize_source_graph(source_graph)
    # A completed subsystem may be structurally valid without being directly
    # executable (for example, a reusable child that inherits its lattice only
    # after composition).  Freeze its normalized graph now, but run the
    # lattice-dependent fact pass only once the source graph has exactly one
    # concrete lattice domain.
    domains = filter(record -> record.kind === :LatticeDomain, qualified_records)
    analysis = length(domains) == 1 ?
        _analyze_term_graph(source_graph, normalized_graph) : nothing
    return CompletedPottsData(
        registry,
        reference_units,
        parameter_roles,
        qualified_records,
        variables,
        schedule,
        capabilities,
        fingerprints,
        PottsDiagnostic[],
        source_graph,
        normalized_graph,
        analysis,
        native_components,
        nothing,
    )
end

function _complete_inventory_hierarchy(
        system::PottsSystem,
        inventory::_PottsSourceInventory,
        reference_units,
        registry::StatementRegistry,
        structural_parameters,
    )
    isempty(inventory.systems) && error("source inventory has no root system")
    inventory.systems[1].system === system || error(
        "source inventory root is not the completion candidate"
    )
    children = _inventory_child_indices(inventory)
    completed = Vector{PottsSystem}(undef, length(inventory.systems))
    for index in length(inventory.systems):-1:1
        subtree = _source_subinventory(inventory, index)
        source = subtree.systems[1].system
        normalized_statements = _inventory_statements(subtree)
        _validate_lifecycle_conflicts!(normalized_statements)
        _validate_completion_reference_units(
            subtree, reference_units, normalized_statements
        )
        parameter_roles = index == 1 ?
            (structural = structural_parameters,) : (structural = (),)
        completion_data = _complete_potts(
            source,
            subtree,
            normalized_statements,
            reference_units,
            registry,
            parameter_roles,
        )
        completed_children = PottsSystem[
            completed[Int(child)] for child in children[index]
        ]
        completed[index] = _rebuild(
            source;
            systems = completed_children,
            complete = true,
            isscheduled = false,
            namespacing = false,
            completion = completion_data,
        )
    end
    return completed[1]
end
