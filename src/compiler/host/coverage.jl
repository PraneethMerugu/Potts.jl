# Compilation-choice and source-coverage validation.

# Top-level compiler orchestration.

function _validate_compilation_choices(
        completed::PottsSystem,
        engine,
        backend,
        scalar_type,
    )
    is_scheduled(completed) || throw(
        ArgumentError(
            "late lowering requires a scheduled PottsSystem"
        )
    )
    engine isa AbstractPottsAlgorithm || throw(
        ArgumentError(
            "algorithm must be SequentialCPM() or CheckerboardSweepCPM()"
        )
    )
    backend isa AbstractPottsBackend || throw(
        ArgumentError(
            "backend must be a Potts backend selector"
        )
    )
    engine isa SequentialCPM && !(backend isa CPUBackend) &&
        throw(
        ArgumentError(
            "SequentialCPM is the CPU semantic reference; accelerator " *
                "backends require CheckerboardSweepCPM()"
        )
    )
    _validate_backend_available(backend)
    scalar_type isa Type && scalar_type <: AbstractFloat ||
        throw(ArgumentError("scalar_type must be a concrete AbstractFloat type"))
    isconcretetype(scalar_type) ||
        throw(ArgumentError("scalar_type must be concrete"))
    engine_name = engine isa SequentialCPM ? :sequential : :checkerboard
    rejections = Tuple(
        (record.identity, admission.reason)
            for record in _completion_data(completed).records
            for admission in record.engine_admission
            if admission.engine === engine_name && !admission.admitted
    )
    if !isempty(rejections)
        reasons = join(
            ("$(identity): $reason" for (identity, reason) in rejections),
            "; ",
        )
        throw(
            ArgumentError(
                "scheduled system is not admitted by $(nameof(typeof(engine))): $reasons"
            )
        )
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
    isempty(effects) && return "accepted-copy process requires at least one bounded effect"
    condition = _statement_arguments(statement).expression
    for effect in effects
        reason = _accepted_copy_effect_rejection(effect, condition, statements)
        reason === nothing || return reason
    end
    targets = Tuple(effect.target for effect in effects if effect isa Assign)
    length(unique(targets)) == length(targets) ||
        return "accepted-copy assignments must have distinct targets"
    return nothing
end

function _accepted_copy_effect_rejection(effect, condition, statements)
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
    arguments = _statement_arguments(statement)
    effects = arguments.effects
    isempty(effects) && return "synchronous process requires at least one assignment"
    domains = Symbol[]
    for effect in effects
        reason = _synchronous_assignment_rejection(effect, statements)
        reason === nothing || return reason
        state = _declared_assignment_state(effect.target, statements)
        push!(domains, state isa ModelState ? :model : state isa CellState ? :cell : :site)
    end
    all(==(first(domains)), domains) ||
        return "synchronous effects must share one iteration domain; use separate processes for model, cell, and site assignments"
    if first(domains) === :cell
        arguments.domain isa Cells ||
            return "synchronous CellState assignments require an explicit cells(kind) domain"
        any(
            candidate -> candidate isa CellKind &&
                _same_statement_resource(arguments.domain.kind, candidate), statements
        ) ||
            return "synchronous cells(kind) domain must resolve to a declared CellKind"
    elseif arguments.domain isa Cells
        return "synchronous cells(kind) domain requires CellState targets"
    end
    return nothing
end

function _synchronous_assignment_rejection(effect, statements)
    effect isa Assign ||
        return "synchronous lowering currently requires Assign"
    state = _declared_assignment_state(effect.target, statements)
    state === nothing && return "Assign must target one declared state"
    state isa Union{SiteState, CellState} && return nothing
    state isa ModelState ||
        return "synchronous Assign requires a SiteState, CellState, or ModelState target"
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

function _field_evolution_rejection(statement, statements, system)
    options = _statement_options(statement)
    evolution = get(options, :evolution, nothing)
    evolution === nothing && return haskey(options, :rhs) ?
        "an explicit field rhs requires a declared evolution policy" : nothing
    return numerical_field_rejection(evolution, statement, statements, system)
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
    elseif statement isa FieldState
        return _field_evolution_rejection(statement, statements, system)
    elseif statement isa Protocol
        all(
            stage -> stage isa SweepStage,
            _statement_arguments(statement).stages
        ) ||
            return "Protocol admits only SweepStage values"
    elseif statement isa RegisteredStatement
        return "RegisteredStatement was not lowered during completion"
    end
    return nothing
end

function _validate_compilation_coverage!(
        diagnostics, system::PottsSystem, parent_path::Tuple = ()
    )
    isempty(parent_path) || throw(
        ArgumentError(
            "compilation coverage starts from the completed root authority"
        )
    )
    completion = getfield(system, :completion)::CompletedPottsData
    records = completion.records
    all_statements = AbstractPottsStatement[
        record.normalized_statement for record in records
    ]
    for record in records
        statement = record.normalized_statement
        reason = _statement_lowering_rejection(
            statement, all_statements, system
        )
        reason === nothing && continue
        push!(
            diagnostics, PottsDiagnostic(
                :unsupported_statement_lowering,
                record.identity,
                _statement_expression(statement),
                record.identity.path,
                "a concrete, semantics-preserving statement lowering",
                reason,
                (),
                record.source,
            )
        )
    end
    return diagnostics
end
function _validate_equation_and_event_coverage!(diagnostics, system::PottsSystem)
    # Keep the tuple snapshot at the public inspection boundary.  Compiler
    # passes operate on the completion-owned vector so model size does not
    # become a tuple type parameter and trigger one specialization per size.
    records = _completion_data(system).records
    for equation in ModelingToolkitBase.equations(system)
        push!(
            diagnostics, PottsDiagnostic(
                :unowned_equation,
                _try_symbolic_name(equation.lhs),
                string(equation),
                (nameof(system),),
                "a native MTK component or bounded FieldState evolution policy",
                "a copied root equation with no native owner",
                (),
                UnknownSource(),
            )
        )
    end
    for (kind, events) in (
            :continuous_event => ModelingToolkitBase.continuous_events(system),
            :discrete_event => ModelingToolkitBase.discrete_events(system),
        )
        isempty(events) && continue
        push!(
            diagnostics, PottsDiagnostic(
                :unsupported_event_lowering,
                nameof(system),
                join(string.(events), "; "),
                (nameof(system),),
                "symbolic event effects lowerable into the closed effect language",
                "$(length(events)) $kind declaration(s) have no concrete lowering",
                (),
                UnknownSource(),
            )
        )
    end
    return diagnostics
end
