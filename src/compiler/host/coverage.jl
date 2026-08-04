# Compilation-choice and source-coverage validation.

# Top-level compiler orchestration.

function _validate_compilation_choices(
        completed::PottsSystem,
        engine,
        backend,
        scalar_type,
    )
    iscomplete(completed) ||
        throw(ArgumentError("compile requires a completed PottsSystem"))
    engine isa AbstractPottsEngine ||
        throw(ArgumentError("engine must be SequentialEngine() or CheckerboardEngine()"))
    backend isa AbstractPottsBackend || throw(ArgumentError(
        "backend must be a PottsToolkit backend selector"
    ))
    engine isa SequentialEngine && !(backend isa CPUBackend) &&
        throw(ArgumentError(
            "SequentialEngine is the CPU semantic reference; accelerator " *
            "backends require CheckerboardEngine()"
        ))
    _validate_backend_available(backend)
    scalar_type isa Type && scalar_type <: AbstractFloat ||
        throw(ArgumentError("scalar_type must be a concrete AbstractFloat type"))
    isconcretetype(scalar_type) ||
        throw(ArgumentError("scalar_type must be concrete"))
    capabilities = inspect(completed, Capabilities())
    engine isa SequentialEngine && !capabilities.sequential &&
        throw(ArgumentError("completed system is not admitted by SequentialEngine"))
    if engine isa CheckerboardEngine && !capabilities.checkerboard
        reasons = join(
            ("$(identity): $reason"
             for (identity, reason) in capabilities.checkerboard_rejections),
            "; ",
        )
        throw(ArgumentError(
            "completed system is not admitted by CheckerboardEngine: $reasons"
        ))
    end
    return nothing
end

function _statement_by_id(statements, id)
    index = findfirst(
        statement -> statement_id(statement) == statement_id(id), statements
    )
    return index === nothing ? nothing : statements[index]
end

function _compiled_relationship_declaration(statements, requested)
    resources = filter(statement -> statement isa RelationshipState, statements)
    matches = filter(
        statement -> _same_statement_resource(statement, requested),
        resources,
    )
    return length(matches) == 1 ? only(matches) : nothing
end

function _declared_assignment_state(target, statements)
    matches = filter(statements) do statement
        statement isa Union{
            SiteState, CellState, MediumState, ModelState, FieldState,
            HistoryState,
        } || return false
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) && isequal(arguments.variable, target)
    end
    return length(matches) == 1 ? only(matches) : nothing
end

_same_statement_resource(left, right) =
    left isa AbstractPottsStatement &&
    right isa AbstractPottsStatement &&
    statement_id(left) == statement_id(right)

function _accepted_copy_rejection(statement, statements)
    effects = _statement_arguments(statement).effects
    length(effects) == 1 ||
        return "accepted-copy lowering requires exactly one bounded V1 effect"
    effect = only(effects)
    condition = _statement_arguments(statement).expression
    if effect isa Assign
        state = _declared_assignment_state(effect.target, statements)
        state === nothing &&
            return "Assign must target one declared state"
        state isa SiteState ||
            return "accepted-copy Assign currently requires a SiteState target"
        condition === nothing &&
            return "accepted-copy Assign requires an explicit bounded condition"
        return nothing
    elseif effect isa Create
        relationship = _compiled_relationship_declaration(
            statements, effect.relationship
        )
        relationship === nothing &&
            return "Create has no matching compiled relationship state"
        _same_statement_resource(effect.relationship, relationship) ||
            return "Create has no matching compiled relationship state"
        payload = _statement_option(relationship, :payload, NamedTuple())
        effect.payload isa NamedTuple && keys(effect.payload) == keys(payload) ||
            return "Create payload must exactly match the declared payload schema"
        condition === nothing &&
            return "relationship creation requires an explicit bounded condition"
        return nothing
    end
    return "accepted-copy lowering does not support $(nameof(typeof(effect)))"
end

function _synchronous_rejection(statement, statements)
    effects = _statement_arguments(statement).effects
    length(effects) == 1 ||
        return "synchronous lowering requires exactly one bounded assignment"
    effect = only(effects)
    effect isa Assign ||
        return "synchronous lowering currently requires Assign"
    state = _declared_assignment_state(effect.target, statements)
    state === nothing && return "Assign must target one declared state"
    state isa SiteState ||
        return "synchronous Assign currently requires a SiteState target"
    return nothing
end

function _relationship_process_rejection(statement, statements)
    arguments = _statement_arguments(statement)
    length(arguments.effects) == 1 ||
        return "relationship process must emit one bounded request"
    effect = only(arguments.effects)
    effect isa Union{Remove, Retune} ||
        return "relationship process must emit one Remove or Retune request"
    relationship = _compiled_relationship_declaration(
        statements, effect.relationship
    )
    relationship === nothing &&
        return "relationship process request has no matching relationship state"
    arguments.domain isa Edges &&
        _same_statement_resource(arguments.domain.relationship, relationship) ||
        return "relationship process domain must be edges(relationship)"
    _same_statement_resource(effect.relationship, relationship) ||
        return "relationship process request must target its iterated store"
    arguments.expression === nothing &&
        return "relationship removal requires an explicit bounded condition"
    return nothing
end

function _lifecycle_process_rejection(statement, statements)
    arguments = _statement_arguments(statement)
    any(_cell_lifecycle_effect, arguments.effects) && return nothing
    return _relationship_process_rejection(statement, statements)
end

function _equation_process_rejection(statement, statements, system)
    options = _statement_options(statement)
    return numerical_process_rejection(
        get(options, :solver, nothing), statement, statements, system
    )
end

function _statement_lowering_rejection(statement, statements, system)
    if statement isa SynchronousProcess
        return _synchronous_rejection(statement, statements)
    elseif statement isa AcceptedCopyProcess
        return _accepted_copy_rejection(statement, statements)
    elseif statement isa LifecycleProcess
        return _lifecycle_process_rejection(statement, statements)
    elseif statement isa RelationshipProcess
        return _relationship_process_rejection(statement, statements)
    elseif statement isa EquationProcess
        return _equation_process_rejection(statement, statements, system)
    elseif statement isa Protocol
        all(stage -> stage isa Union{SweepStage, ObserveStage},
            _statement_arguments(statement).stages) ||
            return "Protocol contains an unsupported stage"
    elseif statement isa RegisteredStatement
        return "RegisteredStatement was not lowered during completion"
    end
    return nothing
end

function _validate_compilation_coverage!(
        diagnostics, system::PottsSystem, parent_path::Tuple = ()
    )
    path = (parent_path..., nameof(system))
    local_statements = statements(system)
    all_statements = _all_system_statements(system)
    for statement in local_statements
        reason = _statement_lowering_rejection(
            statement, all_statements, system
        )
        reason === nothing && continue
        push!(diagnostics, PottsDiagnostic(
            :unsupported_v1_lowering,
            QualifiedStatementID(path, statement_id(statement)),
            _statement_expression(statement),
            path,
            "a concrete, semantics-preserving V1 lowering",
            reason,
            (),
            statement_source(statement),
        ))
    end
    for child in getfield(system, :systems)
        _validate_compilation_coverage!(diagnostics, child, path)
    end
    return diagnostics
end
function _validate_equation_and_event_coverage!(diagnostics, system::PottsSystem)
    records = inspect(system, Statements())
    equation_records = filter(
        record -> record.kind === :EquationProcess, records
    )
    for equation in ModelingToolkitBase.equations(system)
        owners = filter(equation_records) do record
            arguments = first(record.normalized_payload)
            any(candidate -> isequal(candidate, equation), arguments.equations)
        end
        if isempty(owners)
            push!(diagnostics, PottsDiagnostic(
                :unowned_equation,
                _try_symbolic_name(equation.lhs),
                string(equation),
                (nameof(system),),
                "exactly one explicit EquationProcess owner",
                "no owner",
                (),
                UnknownSource(),
            ))
        elseif length(owners) > 1
            for owner in owners
                push!(diagnostics, PottsDiagnostic(
                    :duplicate_equation_owner,
                    owner.identity,
                    string(equation),
                    owner.identity.path,
                    "exactly one explicit EquationProcess owner",
                    join(string.(getfield.(owners, :identity)), ", "),
                    (),
                    owner.source,
                ))
            end
        end
    end
    written = Tuple(
        (record, value)
        for record in equation_records
        for value in first(record.normalized_payload).writes
    )
    for (record, value) in written
        owners = filter(item -> isequal(last(item), value), written)
        length(owners) <= 1 && continue
        push!(diagnostics, PottsDiagnostic(
            :duplicate_equation_write_owner,
            record.identity,
            record.source isa SourceLocation ?
            record.source.expression : string(record.identity),
            record.identity.path,
            "one EquationProcess writer per phase",
            join((string(item[1].identity) for item in owners), ", "),
            (),
            record.source,
        ))
    end
    for (kind, events) in (
            :continuous_event => ModelingToolkitBase.continuous_events(system),
            :discrete_event => ModelingToolkitBase.discrete_events(system),
        )
        isempty(events) && continue
        push!(diagnostics, PottsDiagnostic(
            :unsupported_v1_event_lowering,
            nameof(system),
            join(string.(events), "; "),
            (nameof(system),),
            "symbolic event effects lowerable into the closed V1 effect language",
            "$(length(events)) $kind declaration(s) have no concrete lowering",
            (),
            UnknownSource(),
        ))
    end
    return diagnostics
end
