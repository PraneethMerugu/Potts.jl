# Complete one source-inventory subtree into immutable semantic data.
function _complete_inventory_subtree(
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

    qualified_records = _semantic_phase_schedule(records)
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
        completion_data = _complete_inventory_subtree(
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
