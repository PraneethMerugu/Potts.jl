struct CompletedPottsData{R, U, Q, V, S, C, F, D}
    registry::R
    reference_units::U
    records::Q
    variables::V
    schedule::S
    capabilities::C
    fingerprints::F
    diagnostics::D
end

function _statement_expression(statement)
    source = statement_source(statement)
    source isa SourceLocation && return source.expression
    return sprint(show, statement)
end

function _qualify_records!(records, diagnostics, system::PottsSystem, path::Tuple)
    current_path = (path..., nameof(system))
    seen = Dict{StatementID, AbstractPottsStatement}()
    for statement in statements(system)
        id = statement_id(statement)
        if haskey(seen, id)
            first_statement = seen[id]
            push!(diagnostics, PottsDiagnostic(
                :duplicate_statement_identity,
                QualifiedStatementID(current_path, id),
                _statement_expression(statement),
                current_path,
                "a namespace-local unique StatementID",
                "duplicates $(_statement_expression(first_statement))",
                (),
                statement_source(statement),
            ))
            continue
        end
        seen[id] = statement
        identity = QualifiedStatementID(current_path, id)
        writes = _statement_writes(statement)
        reads = _statement_reads(statement, writes)
        effect = _statement_effect(statement)
        phase = _statement_phase(statement)
        random_operations = _random_operations(statement, identity)
        record = QualifiedStatement(
            identity,
            statement_kind(statement),
            v"1.0.0",
            statement_source(statement),
            (),
            (_statement_arguments(statement), _statement_options(statement)),
            nothing,
            nothing,
            reads,
            writes,
            effect,
            _effect_bound(statement),
            random_operations,
            phase,
            (),
            _engine_admission(statement),
            _lowering_identity(statement),
        )
        push!(records, record)
    end
    for child in getfield(system, :systems)
        _qualify_records!(records, diagnostics, child, current_path)
    end
    return records
end

function _completion_variables(system::PottsSystem, records)
    result = Any[]
    for collection in (
            ModelingToolkitBase.unknowns(system),
            ModelingToolkitBase.parameters(system),
            ModelingToolkitBase.independent_variables(system),
        )
        for value in collection
            any(isequal(value), result) || push!(result, value)
        end
    end
    for record in records
        for value in (record.reads..., record.writes...)
            value isa AbstractPottsStatement && continue
            any(isequal(value), result) || push!(result, value)
        end
    end
    return Tuple(result)
end

function _completion_schedule(records)
    phase_rank = Dict(
        Proposal => 1,
        AcceptedCopy => 2,
        AfterMCS => 3,
        RelationshipCommit => 4,
        Lifecycle => 5,
        EquationStep => 6,
        Observe => 7,
    )
    return Tuple(sort(
        collect(records);
        by = record -> (
            get(phase_rank, typeof(record.phase), 0),
            string(record.identity),
        ),
    ))
end

function _completion_capabilities(records)
    sequential = all(
        admission -> admission.admitted,
        (
            only(filter(item -> item.engine === :sequential, record.engine_admission))
            for record in records
        ),
    )
    checkerboard_rejections = Tuple(
        (
            record.identity,
            admission.reason,
        )
        for record in records
        for admission in record.engine_admission
        if admission.engine === :checkerboard && !admission.admitted
    )
    return (
        sequential = sequential,
        checkerboard = isempty(checkerboard_rejections),
        checkerboard_rejections,
        cpu = true,
    )
end

function _complete_potts(
        system::PottsSystem, reference_units, registry::StatementRegistry
    )
    records = QualifiedStatement[]
    diagnostics = PottsDiagnostic[]
    _qualify_records!(records, diagnostics, system, ())
    _throw_diagnostics(:completion, diagnostics)

    variables = _completion_variables(system, records)
    schedule = _completion_schedule(records)
    capabilities = _completion_capabilities(records)
    semantic = _semantic_fingerprint(system, records)
    completed = _completed_fingerprint(semantic, records, reference_units, registry)
    fingerprints = (semantic = semantic, completed = completed)
    return CompletedPottsData(
        registry,
        reference_units,
        Tuple(records),
        variables,
        schedule,
        capabilities,
        fingerprints,
        (),
    )
end

