"""Versioned extension-statement contracts and registration authority."""

const _REGISTERED_CONTRACT_FIELDS = (
    :argument_types,
    :result_type,
    :unit_constraints,
    :namespace_traversal,
    :access,
    :effect,
    :rng,
    :boundedness,
    :phase,
    :capabilities,
    :scientific_category,
    :energy_domain,
    :affected_region,
    :reference_semantics,
    :descriptor_payload_type,
    :serialization_identity,
    :lowering_identity,
)

struct StatementDefinition{C <: NamedTuple}
    schema::Symbol
    version::VersionNumber
    contract::C
end

"""Registry of versioned external statement schemas and their lowering functions."""
struct StatementRegistry{T <: Tuple}
    definitions::T
end

StatementRegistry() = StatementRegistry(())

"""Return the lowering function for a registered statement schema."""
function registered_statement_lowering end

function _validate_registered_index_set(value, name, arity)
    value isa Tuple ||
        throw(ArgumentError("registered access `$name` must be a tuple"))
    all(index -> index isa Integer && 1 <= index <= arity, value) ||
        throw(ArgumentError(
            "registered access `$name` must contain valid one-based argument indices"
        ))
    length(unique(value)) == length(value) ||
        throw(ArgumentError("registered access `$name` contains duplicate indices"))
    return nothing
end

function _validate_registered_contract(contract)
    keys(contract) == _REGISTERED_CONTRACT_FIELDS || throw(ArgumentError(
        "a RegisteredStatement contract requires exactly: " *
        join(string.(_REGISTERED_CONTRACT_FIELDS), ", ")
    ))
    contract.argument_types isa Tuple ||
        throw(ArgumentError("registered argument_types must be a tuple of types"))
    all(item -> item isa Type, contract.argument_types) ||
        throw(ArgumentError("registered argument_types must contain only types"))
    contract.result_type isa Type ||
        throw(ArgumentError("registered result_type must be a type"))
    contract.namespace_traversal === :map_symbolics || throw(ArgumentError(
        "registered namespace_traversal must be `:map_symbolics`"
    ))
    contract.access isa NamedTuple &&
        keys(contract.access) == (:reads, :writes) ||
        throw(ArgumentError(
            "registered access must be `(reads=(...), writes=(...))`"
        ))
    arity = length(contract.argument_types)
    _validate_registered_index_set(contract.access.reads, :reads, arity)
    _validate_registered_index_set(contract.access.writes, :writes, arity)
    isempty(intersect(contract.access.reads, contract.access.writes)) ||
        throw(ArgumentError("registered reads and writes must be disjoint"))
    contract.effect in (
        :pure_read, :synchronous_assign, :accepted_copy, :ordered_batch
    ) || throw(ArgumentError("registered effect class is not a closed effect"))
    contract.rng isa Tuple ||
        throw(ArgumentError("registered rng contract must be a tuple"))
    for operation in contract.rng
        operation isa NamedTuple &&
            keys(operation) == (:identity, :family, :reserved) ||
            throw(ArgumentError(
                "each registered rng operation must be " *
                "`(identity=..., family=..., reserved=...)`"
            ))
        operation.identity isa Symbol && operation.family isa Symbol &&
            operation.reserved isa Bool ||
            throw(ArgumentError(
                "registered rng identity/family/reserved types are invalid"
            ))
    end
    length(unique(operation.identity for operation in contract.rng)) ==
        length(contract.rng) ||
        throw(ArgumentError("registered rng identities must be unique"))
    contract.boundedness isa NamedTuple &&
        keys(contract.boundedness) == (:maximum, :basis) ||
        throw(ArgumentError(
            "registered boundedness must be `(maximum=..., basis=...)`"
        ))
    contract.boundedness.maximum isa Integer &&
        contract.boundedness.maximum >= 0 ||
        throw(ArgumentError("registered effect bound must be nonnegative"))
    contract.boundedness.basis isa Symbol ||
        throw(ArgumentError("registered effect-bound basis must be a Symbol"))
    contract.phase isa Union{Nothing, AbstractPottsPhase} ||
        throw(ArgumentError(
            "registered phase must be nothing or an AbstractPottsPhase"
        ))
    contract.capabilities isa NamedTuple &&
        keys(contract.capabilities) == (:sequential, :checkerboard, :reason) ||
        throw(ArgumentError(
            "registered capabilities must be " *
            "`(sequential=..., checkerboard=..., reason=...)`"
        ))
    contract.capabilities.sequential isa Bool &&
        contract.capabilities.checkerboard isa Bool &&
        contract.capabilities.reason isa AbstractString ||
        throw(ArgumentError("registered capability values have invalid types"))
    contract.capabilities.sequential || throw(ArgumentError(
        "registered statements must admit the sequential engine"
    ))
    (!contract.capabilities.checkerboard &&
     isempty(contract.capabilities.reason)) &&
        throw(ArgumentError(
            "a checkerboard rejection requires a nonempty reason"
        ))
    contract.scientific_category in (
        :hamiltonian, :drive, :constraint, :modifier, :process, :observation,
    ) || throw(ArgumentError(
        "registered scientific_category is not a closed category"
    ))
    contract.energy_domain in (
        nothing, :sites, :cells, :contacts, :relationships,
    ) || throw(ArgumentError(
        "registered energy_domain is not a closed energy domain"
    ))
    contract.affected_region in (
        nothing, :target_site, :source_and_target_cells,
        :incident_contacts, :incident_relationships,
    ) || throw(ArgumentError(
        "registered affected_region is not a closed affected-anchor class"
    ))
    if contract.scientific_category === :hamiltonian
        contract.energy_domain === nothing && throw(ArgumentError(
            "a registered Hamiltonian requires an energy_domain declaration"
        ))
        contract.affected_region === nothing && throw(ArgumentError(
            "a registered Hamiltonian requires an affected_region declaration"
        ))
    elseif contract.energy_domain !== nothing || contract.affected_region !== nothing
        throw(ArgumentError(
            "only registered Hamiltonians may declare energy_domain or affected_region"
        ))
    end
    contract.reference_semantics isa Symbol ||
        throw(ArgumentError("registered reference_semantics must be a Symbol"))
    contract.descriptor_payload_type isa Type &&
        isconcretetype(contract.descriptor_payload_type) &&
        isbitstype(contract.descriptor_payload_type) ||
        throw(ArgumentError(
            "registered descriptor_payload_type must be one concrete isbits type"
        ))
    contract.serialization_identity isa AbstractString &&
        !isempty(contract.serialization_identity) ||
        throw(ArgumentError(
            "registered serialization_identity must be a nonempty string"
        ))
    contract.lowering_identity isa Symbol ||
        throw(ArgumentError("registered lowering_identity must be a Symbol"))
    return nothing
end

"""Register one versioned `RegisteredStatement` schema and lowering function."""
function register_statement(
        registry::StatementRegistry,
        schema::Symbol,
        version::VersionNumber,
        contract::NamedTuple,
    )
    _validate_registered_contract(contract)
    key = (schema, version)
    frozen_contract = NamedTuple{keys(contract)}(Tuple(
        _freeze_registered_value(value; context = "contract")
        for value in values(contract)
    ))
    definition = StatementDefinition(schema, version, frozen_contract)
    index = findfirst(item -> (item.schema, item.version) == key, registry.definitions)
    if index !== nothing
        registry.definitions[index] == definition && return registry
        throw(ArgumentError(
            "conflicting RegisteredStatement definition for $(schema) version $(version)"
        ))
    end
    definitions = sort!(
        collect((registry.definitions..., definition));
        by = item -> (String(item.schema), item.version),
    )
    return StatementRegistry(Tuple(definitions))
end

"""Return a new registry containing the package's built-in statement definitions."""
default_statement_registry() = StatementRegistry()
