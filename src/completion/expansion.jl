# Structural expansion: replace registered declarations and lifecycle policies
# before namespacing or semantic qualification.
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
                "a total registered lowering into the built-in executable IR",
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

