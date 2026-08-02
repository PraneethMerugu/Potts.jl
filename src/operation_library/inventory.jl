# Literal V1 operation vocabulary. Each surface operation appears once with a
# canonical arity used to materialize its complete frozen admission contract.

function _v1_builtin_operation_declarations()
    return (
        ((+), 2), ((-), 2), ((*), 2), ((/), 2), ((^), 2),
        (max, 2), (min, 2),
        ((<), 2), ((<=), 2), ((>), 2), ((>=), 2), ((==), 2), ((!=), 2),
        ((&), 2), ((|), 2), ((! ), 1), (ifelse, 3),
        (abs, 1), (exp, 1), (log, 1), (sqrt, 1),
        (source_site, 1), (target_site, 1),
        (source_cell, 1), (target_cell, 1),
        (source_kind, 1), (target_kind, 1),
        (is_extension, 1), (is_retraction, 1),
        (new_contact, 2), (lost_contact, 2), (linked, 3),
        (_potts_proposal_bound_state_value, 1),
        (_potts_iteration_bound_state_value, 1),
        (cell_volume, 1), (cell_surface, 1), (cell_elongation, 1),
        (cell_center, 1), (unwrapped_center, 1),
        (endpoint_a, 1), (endpoint_b, 1), (degree, 2),
        (contact_owner_a, 1), (contact_owner_b, 1),
        (contact_kind_a, 1), (contact_kind_b, 1),
        (occupancy, 2), (distance, 2), (contact_measure, 2),
        (boundary_measure, 2), (neighbor_count, 2), (neighbor_sum, 2),
        (neighbor_mean, 2), (neighbor_geomean, 2),
        (field_value, 2), (field_gradient, 2), (laplacian, 2),
        (history_value, 2), (edge_payload, 2), (lag, 2),
        (_potts_draw, 4),
        (_potts_merks_local_connectivity, 3),
        (_potts_act_energy, 5),
        (_potts_explicit_field_euler, 7),
        (_potts_relationship_endpoint_kinds, 4),
    )
end

function _v1_operation_inventory(graph::NormalizedTermGraph)
    return NamedTuple[ (
        identity = schema.transfer.identity,
        version = schema.transfer.schema_version,
        owner = schema.transfer.owner,
        arity = (
            minimum = first(schema.transfer.arity),
            maximum = last(schema.transfer.arity),
        ),
        operand_rule = schema.transfer.operand_rule,
        result_rule = schema.transfer.result_rule,
        unit_rule = schema.transfer.unit_rule,
        purity = schema.transfer.purity,
        totality = schema.transfer.totality,
        footprint_rule = nameof(typeof(schema.transfer.footprint_rule)),
        tracker_requirements = schema.transfer.tracker_requirements,
        allowed_roles = schema.transfer.allowed_roles,
        allowed_phases = schema.transfer.allowed_phases,
        required_context = schema.transfer.required_context,
        cpu = schema.transfer.cpu,
        gpu = schema.transfer.gpu,
        serialization_identity = schema.transfer.serialization_identity,
        callable_identity = schema.transfer.callable_identity,
        concrete_callable = string(typeof(schema.callable)),
    ) for schema in graph.operation_snapshot ]
end

function _v1_builtin_operation_inventory()
    rows = NamedTuple[]
    for (operation, arity) in _v1_builtin_operation_declarations()
        transfer = operation_transfer(operation, arity)
        push!(rows, (
            identity = transfer.identity,
            version = transfer.schema_version,
            owner = transfer.owner,
            arity = (
                minimum = first(transfer.arity),
                maximum = last(transfer.arity),
            ),
            operand_rule = transfer.operand_rule,
            result_rule = transfer.result_rule,
            unit_rule = transfer.unit_rule,
            purity = transfer.purity,
            totality = transfer.totality,
            footprint_rule = nameof(typeof(transfer.footprint_rule)),
            tracker_requirements = transfer.tracker_requirements,
            allowed_roles = transfer.allowed_roles,
            allowed_phases = transfer.allowed_phases,
            required_context = transfer.required_context,
            cpu = transfer.cpu,
            gpu = transfer.gpu,
            serialization_identity = transfer.serialization_identity,
            callable_identity = transfer.callable_identity,
        ))
    end
    sort!(rows; by = row -> (String(row.identity), row.version))
    return Tuple(rows)
end
