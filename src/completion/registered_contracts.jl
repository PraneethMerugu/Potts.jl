function _registered_definition(
        registry::StatementRegistry, statement::RegisteredStatement
    )
    arguments = _statement_arguments(statement)
    index = findfirst(
        definition -> definition.schema === arguments.schema &&
                      definition.version == arguments.version,
        registry.definitions,
    )
    return index === nothing ? nothing : registry.definitions[index]
end

function _registered_effect(contract)
    contract.effect === :pure_read && return PureRead()
    contract.effect === :synchronous_assign && return SynchronousAssign()
    contract.effect === :accepted_copy && return AcceptedCopyEffect()
    contract.effect === :ordered_batch && return OrderedBatchEffect()
    error("unreachable registered effect")
end

function _phase_rank(phase)
    ranks = (
        Proposal => 1,
        AcceptedCopy => 2,
        AfterMCS => 3,
        RelationshipCommit => 4,
        Lifecycle => 5,
    )
    phase === nothing && return 0.0
    phase isa Before && return _phase_rank(phase.phase) - 0.25
    phase isa After && return _phase_rank(phase.phase) + 0.25
    for (phase_type, rank) in ranks
        phase isa phase_type && return Float64(rank)
    end
    throw(ArgumentError("unsupported semantic phase $(typeof(phase))"))
end

function _phase_contract(statement, phase)
    statement isa AcceptedCopyProcess &&
        return phase isa AcceptedCopy
    statement isa SynchronousProcess &&
        return phase isa AfterMCS
    statement isa RelationshipProcess &&
        return phase isa RelationshipCommit
    statement isa LifecycleProcess &&
        return phase isa Lifecycle
    statement isa Observation &&
        return phase === nothing
    return true
end

function _draw_parameter_error(arguments)
    family = _draw_family(arguments)
    first_parameter = _draw_literal(arguments[2])
    second_parameter = _draw_literal(arguments[3])
    if family === :bernoulli && first_parameter isa Real &&
            !(zero(first_parameter) <= first_parameter <= one(first_parameter))
        return "Bernoulli probability must lie in [0, 1]"
    elseif family === :uniform &&
            first_parameter isa Real && second_parameter isa Real &&
            !(first_parameter < second_parameter)
        return "Uniform minimum must be less than its maximum"
    elseif family === :normal && second_parameter isa Real &&
            !(second_parameter > zero(second_parameter))
        return "Normal standard deviation must be positive"
    elseif family === :unit_vector && first_parameter isa Real &&
            !(isinteger(first_parameter) && first_parameter > 0)
        return "UnitVector dimension must be a positive integer"
    end
    return nothing
end

function _validate_statement_draws!(diagnostics, statement, identity, path)
    calls = _draw_calls(statement)
    isempty(calls) && return nothing
    if statement isa HamiltonianTerm
        push!(diagnostics, PottsDiagnostic(
            :stochastic_hamiltonian,
            identity,
            _statement_expression(statement),
            path,
            "a deterministic conservative energy expression",
            "a Hamiltonian expression containing a random draw",
            (),
            statement_source(statement),
        ))
        return nothing
    end
    statement isa Union{
        ProposalDrive, ProposalConstraint, ProposalModifier,
        SynchronousProcess, AcceptedCopyProcess, RelationshipProcess,
        LifecycleProcess, Observation, RegisteredStatement,
    } || push!(diagnostics, PottsDiagnostic(
        :illegal_random_operation_context,
        identity,
        _statement_expression(statement),
        path,
        "a process, proposal, equation, or observation expression",
        String(statement_kind(statement)),
        (),
        statement_source(statement),
    ))
    for arguments in calls
        if _draw_family(arguments) === :unit_vector && statement isa Union{
                ProposalDrive, ProposalConstraint, ProposalModifier,
            }
            push!(diagnostics, PottsDiagnostic(
                :nonscalar_distribution_in_proposal_term,
                identity,
                _statement_expression(statement),
                path,
                "a scalar Bernoulli, Uniform, or Normal distribution",
                "UnitVector",
                (),
                statement_source(statement),
            ))
            continue
        end
        message = _draw_parameter_error(arguments)
        message === nothing && continue
        push!(diagnostics, PottsDiagnostic(
            :invalid_random_distribution,
            identity,
            _statement_expression(statement),
            path,
            "valid distribution parameters",
            message,
            (),
            statement_source(statement),
        ))
    end
    return nothing
end

"""Reject declared public markers without executable semantics."""
function _validate_builtin_marker_support!(
        diagnostics, statement, identity, path
    )
    options = _statement_options(statement)
    if statement isa ProposalDrive &&
            get(options, :mechanism, nothing) === :chemotaxis
        mode = get(options, :mode, ExtensionsOnly())
        if !(mode isa ExtensionsOnly)
            push!(diagnostics, PottsDiagnostic(
                :unsupported_chemotaxis_mode,
                identity,
                _statement_expression(statement),
                path,
                "ExtensionsOnly() in the compiled executable profile",
                string(nameof(typeof(mode))),
                (),
                statement_source(statement),
            ))
        end
        sample = get(options, :sample, Nearest())
        if !(sample isa Nearest)
            push!(diagnostics, PottsDiagnostic(
                :unsupported_chemotaxis_sampling,
                identity,
                _statement_expression(statement),
                path,
                "Nearest() in the compiled executable profile",
                string(nameof(typeof(sample))),
                (),
                statement_source(statement),
            ))
        end
    elseif statement isa FieldState &&
            get(options, :placement, nothing) isa CellCentered
        push!(diagnostics, PottsDiagnostic(
            :unsupported_field_placement,
            identity,
            _statement_expression(statement),
            path,
            "field placement implemented by a reviewed field backend",
            "CellCentered",
            (),
            statement_source(statement),
        ))
    end
    return nothing
end

function _with_registered_origin(statement, origin, source)
    core = getfield(statement, :core)
    options = merge(core.options, (__registered_origin = origin,))
    statement_type = typeof(statement).name.wrapper
    effective_source = statement_source(statement) isa UnknownSource ?
                       source : statement_source(statement)
    return statement_type(StatementCore(
        core.id, core.arguments, options, effective_source
    ))
end

const _REGISTERED_ORIGIN_FIELDS = (
    :schema,
    :version,
    :serialization_identity,
    :lowering_identity,
    :descriptor_payload_type,
    :scientific_category,
    :energy_domain,
    :affected_region,
)

function _registered_origin_for(definition::StatementDefinition)
    return (
        schema = definition.schema,
        version = definition.version,
        serialization_identity =
            String(definition.contract.serialization_identity),
        lowering_identity = definition.contract.lowering_identity,
        descriptor_payload_type =
            definition.contract.descriptor_payload_type,
        scientific_category = definition.contract.scientific_category,
        energy_domain = definition.contract.energy_domain,
        affected_region = definition.contract.affected_region,
    )
end

function _statement_scientific_category(statement)
    statement isa HamiltonianTerm && return :hamiltonian
    statement isa ProposalDrive && return :drive
    statement isa ProposalConstraint && return :constraint
    statement isa ProposalModifier && return :modifier
    statement isa Observation && return :observation
    return :process
end

function _statement_energy_domain(statement)
    statement isa HamiltonianTerm || return nothing
    domain = _statement_arguments(statement).domain
    domain isa Sites && return :sites
    domain isa Cells && return :cells
    domain isa Contacts && return :contacts
    domain isa Edges && return :relationships
    return :invalid
end

function _authenticated_registered_origin(
        registry::StatementRegistry,
        origin,
    )
    origin isa NamedTuple && keys(origin) == _REGISTERED_ORIGIN_FIELDS ||
        return nothing
    index = findfirst(
        definition -> definition.schema === origin.schema &&
                      definition.version == origin.version,
        registry.definitions,
    )
    index === nothing && return nothing
    definition = registry.definitions[index]
    return isequal(origin, _registered_origin_for(definition)) ?
           definition : nothing
end

function _registered_lowering_result(value)
    value isa AbstractPottsStatement && return (value,)
    value isa StatementSet && return statements(value)
    value isa Tuple && return statements(StatementSet(value))
    throw(ArgumentError(
        "registered_statement_lowering must return a Potts statement, " *
        "StatementSet, or tuple of Potts statements"
    ))
end

function _same_symbolic_set(left, right)
    length(left) == length(right) || return false
    return all(value -> any(isequal(value), right), left)
end

function _registered_access_values(arguments, indices)
    values = Any[]
    for index in indices
        argument = arguments[index]
        symbolic_values = _collect_symbolics(argument)
        if isempty(symbolic_values)
            any(isequal(argument), values) || push!(values, argument)
        else
            for value in symbolic_values
                any(isequal(value), values) || push!(values, value)
            end
        end
    end
    return Tuple(values)
end

function _validate_registered_lowering!(
        diagnostics,
        registered::RegisteredStatement,
        lowered,
        definition,
        identity,
        path,
    )
    contract = definition.contract
    arguments = _statement_arguments(registered).arguments
    if length(lowered) != 1
        push!(diagnostics, PottsDiagnostic(
            :registered_lowering_cardinality,
            identity,
            _statement_expression(registered),
            path,
            "exactly one qualified built-in executable statement",
            "$(length(lowered)) statements",
            (),
            statement_source(registered),
        ))
        return false
    end
    statement = only(lowered)
    if statement isa RegisteredStatement
        push!(diagnostics, PottsDiagnostic(
            :recursive_registered_lowering,
            identity,
            _statement_expression(registered),
            path,
            "a built-in executable statement",
            "RegisteredStatement",
            (),
            statement_source(registered),
        ))
        return false
    end
    writes = _statement_writes(statement)
    reads = _statement_reads(statement, writes)
    expected_reads = _registered_access_values(
        arguments, contract.access.reads
    )
    expected_writes = _registered_access_values(
        arguments, contract.access.writes
    )
    inferred_effect = _statement_effect(statement)
    inferred_bound = _effect_bound(statement)
    inferred_phase = _statement_phase(statement)
    inferred_admission = _engine_admission(statement)
    inferred_random = _random_operations(statement, identity)
    inferred_result = _record_result_type(statement)
    inferred_category = _statement_scientific_category(statement)
    inferred_energy_domain = _statement_energy_domain(statement)
    checks = (
        (
            :registered_result_type_mismatch,
            inferred_result === contract.result_type,
            repr(contract.result_type),
            repr(inferred_result),
        ),
        (
            :registered_read_contract_mismatch,
            _same_symbolic_set(reads, expected_reads),
            repr(expected_reads),
            repr(reads),
        ),
        (
            :registered_write_contract_mismatch,
            _same_symbolic_set(writes, expected_writes),
            repr(expected_writes),
            repr(writes),
        ),
        (
            :registered_effect_contract_mismatch,
            inferred_effect == _registered_effect(contract),
            String(contract.effect),
            String(nameof(typeof(inferred_effect))),
        ),
        (
            :registered_bound_contract_mismatch,
            inferred_bound.maximum == contract.boundedness.maximum &&
                inferred_bound.basis === contract.boundedness.basis,
            repr(contract.boundedness),
            repr((
                maximum = inferred_bound.maximum,
                basis = inferred_bound.basis,
            )),
        ),
        (
            :registered_phase_contract_mismatch,
            isequal(inferred_phase, contract.phase),
            repr(contract.phase),
            repr(inferred_phase),
        ),
        (
            :registered_rng_contract_mismatch,
            Tuple((item.identity, item.family, item.reserved)
                for item in inferred_random) ==
                Tuple((item.identity, item.family, item.reserved)
                    for item in contract.rng),
            repr(contract.rng),
            repr(inferred_random),
        ),
        (
            :registered_engine_contract_mismatch,
            all(
                admission -> getproperty(
                    contract.capabilities, admission.engine
                ) == admission.admitted,
                inferred_admission,
            ),
            repr(contract.capabilities),
            repr(inferred_admission),
        ),
        (
            :registered_scientific_category_mismatch,
            inferred_category === contract.scientific_category,
            String(contract.scientific_category),
            String(inferred_category),
        ),
        (
            :registered_energy_domain_mismatch,
            inferred_energy_domain === contract.energy_domain,
            repr(contract.energy_domain),
            repr(inferred_energy_domain),
        ),
    )
    valid = true
    for (kind, passed, expected, actual) in checks
        passed && continue
        valid = false
        push!(diagnostics, PottsDiagnostic(
            kind,
            identity,
            _statement_expression(registered),
            path,
            expected,
            actual,
            (),
            statement_source(registered),
        ))
    end
    return valid
end
