using PottsToolkit

inventory = PottsToolkit._v1_builtin_operation_inventory()
length(inventory) == 68 || error(
    "expected 68 literal V1 operations, found $(length(inventory))"
)
keys = [(row.identity, row.version) for row in inventory]
length(keys) == length(unique(keys)) || error(
    "V1 operation identity/version keys are not unique"
)
interface_only_spatial_queries = Set((
    :contact_edge_count,
    :contact_measure,
    :boundary_site_count,
    :neighbor_cell_count,
    :neighbor_property_sum,
    :neighbor_property_mean,
    :global_interface_measure,
))
for row in inventory
    isempty(String(row.owner)) && error("$(row.identity) has no owner")
    isempty(row.allowed_roles) && error("$(row.identity) has no legal roles")
    isempty(row.allowed_phases) && error("$(row.identity) has no legal phases")
    if row.identity in interface_only_spatial_queries
        !row.cpu && !row.gpu || error(
            "$(row.identity) must remain interface-only until G5H-4"
        )
        row.allowed_roles == (:observation,) || error(
            "$(row.identity) must be observation-only"
        )
        row.allowed_phases == (:none,) || error(
            "$(row.identity) must not claim an execution phase"
        )
    else
        row.cpu || error("$(row.identity) rejects the CPU reference backend")
    end
    isempty(row.callable_identity) && error(
        "$(row.identity) has no concrete callable identity"
    )
end
for (operation, arity) in PottsToolkit._v1_builtin_operation_declarations()
    transfer = PottsToolkit.operation_transfer(operation, arity)
    reason = PottsToolkit._operation_transfer_error(transfer, arity)
    reason === nothing || error("$(transfer.identity): $reason")
end

println("V1 operation inventory qualified: $(length(inventory)) operations")
