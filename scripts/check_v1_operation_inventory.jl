using PottsToolkit

inventory = PottsToolkit._v1_builtin_operation_inventory()
length(inventory) == 65 || error(
    "expected 65 literal V1 operations, found $(length(inventory))"
)
keys = [(row.identity, row.version) for row in inventory]
length(keys) == length(unique(keys)) || error(
    "V1 operation identity/version keys are not unique"
)
for row in inventory
    isempty(String(row.owner)) && error("$(row.identity) has no owner")
    isempty(row.allowed_roles) && error("$(row.identity) has no legal roles")
    isempty(row.allowed_phases) && error("$(row.identity) has no legal phases")
    row.cpu || error("$(row.identity) rejects the CPU reference backend")
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
