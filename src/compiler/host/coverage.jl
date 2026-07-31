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
    backend isa CPUBackend ||
        throw(ArgumentError("V1 currently admits only CPUBackend()"))
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

function _compiled_activity_declaration(statements)
    index = findfirst(statement ->
        statement isa ProposalDrive &&
        _statement_option(statement, :mechanism) === :activity, statements)
    return index === nothing ? nothing : statements[index]
end

function _compiled_relationship_declaration(statements)
    resources = filter(statement -> statement isa RelationshipState, statements)
    return length(resources) == 1 ? only(resources) : nothing
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
        activity = _compiled_activity_declaration(statements)
        activity === nothing &&
            return "Assign has no matching compiled activity declaration"
        isequal(effect.target, _statement_option(activity, :activity)) ||
            return "Assign target is not the compiled activity state"
        isequal(effect.value, _statement_option(activity, :maximum)) ||
            return "activity activation must assign the declared maximum"
        copy = ProposalContext(:copy)
        isequal(condition, copy.is_extension) ||
            return "activity activation condition must be copy.is_extension"
        return nothing
    elseif effect isa Create
        relationship = _compiled_relationship_declaration(statements)
        relationship === nothing &&
            return "Create has no matching compiled relationship state"
        _same_statement_resource(effect.relationship, relationship) ||
            return "Create has no matching compiled relationship state"
        payload = _statement_option(relationship, :payload, NamedTuple())
        all(name -> haskey(effect.payload, name) &&
                    isequal(getproperty(effect.payload, name), getproperty(payload, name)),
            keys(payload)) ||
            return "Create payload must match the compiled relationship payload"
        copy = ProposalContext(:copy)
        expected = new_contact(copy.source_cell, copy.target_cell) &
                   !linked(
            relationship, copy.source_cell, copy.target_cell
        )
        isequal(condition, expected) ||
            return "relationship creation condition must be new-contact and unlinked"
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
    activity = _compiled_activity_declaration(statements)
    activity === nothing &&
        return "Assign has no matching compiled activity declaration"
    isequal(effect.target, _statement_option(activity, :activity)) ||
        return "Assign target is not the compiled activity state"
    decay = _statement_option(statement, :decay, nothing)
    decay === nothing &&
        return "activity decay requires an explicit `decay` value"
    expected = max(effect.target - decay, 0)
    isequal(effect.value, expected) ||
        return "activity decay expression must be max(activity - decay, 0)"
    return nothing
end

function _relationship_process_rejection(statement, statements)
    relationship = _compiled_relationship_declaration(statements)
    relationship === nothing &&
        return "relationship process requires exactly one relationship state"
    arguments = _statement_arguments(statement)
    arguments.domain isa Edges &&
        _same_statement_resource(arguments.domain.relationship, relationship) ||
        return "relationship process domain must be edges(relationship)"
    length(arguments.effects) == 1 &&
        only(arguments.effects) isa Remove &&
        _same_statement_resource(
            only(arguments.effects).relationship, relationship
        ) ||
        return "relationship process must emit one Remove request"
    arguments.expression === nothing &&
        return "relationship removal requires an explicit bounded condition"
    expression = string(arguments.expression)
    all(token -> occursin(token, expression), (
        "distance", "unwrapped_center", "__potts_payload__maximum",
    )) || return "relationship removal must compare unwrapped distance to edge.maximum"
    return nothing
end

function _equation_process_rejection(statement, statements, system)
    arguments = _statement_arguments(statement)
    options = _statement_options(statement)
    options.solver isa ExplicitDiffusion ||
        return "V1 executable equation lowering currently requires ExplicitDiffusion"
    fields = filter(candidate -> candidate isa FieldState, statements)
    length(fields) == 1 ||
        return "equation lowering requires exactly one FieldState"
    variable = _statement_arguments(only(fields)).variable
    length(arguments.writes) == 1 && isequal(only(arguments.writes), variable) ||
        return "EquationProcess writes must identify the compiled FieldState"
    isempty(arguments.equations) &&
        return "EquationProcess requires at least one equation"
    all(equation -> any(isequal(equation), ModelingToolkitBase.equations(system)),
        arguments.equations) ||
        return "EquationProcess equations must be present in PottsSystem.equations"
    return nothing
end

function _statement_lowering_rejection(statement, statements, system)
    if statement isa Union{ProposalDrive, ProposalModifier}
        return nothing
    elseif statement isa ProposalConstraint
        return nothing
    elseif statement isa HamiltonianTerm
        mechanism = _statement_option(statement, :mechanism)
        mechanism === nothing || mechanism === :symbolic || mechanism in (
            :volume, :contact, :relationship, :elongation,
        ) || return "unsupported HamiltonianTerm mechanism $(repr(mechanism))"
        if mechanism === :relationship
            expression = string(_statement_arguments(statement).expression)
            all(token -> occursin(token, expression), (
                "distance", "unwrapped_center", "__potts_payload__strength",
                "__potts_payload__target",
            )) || return "relationship energy must be the canonical unwrapped spring"
        end
    elseif statement isa SynchronousProcess
        return _synchronous_rejection(statement, statements)
    elseif statement isa AcceptedCopyProcess
        return _accepted_copy_rejection(statement, statements)
    elseif statement isa Union{RelationshipProcess, LifecycleProcess}
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
