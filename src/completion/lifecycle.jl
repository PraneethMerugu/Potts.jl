# G5-L1 completion authority for the closed cell-lifecycle language.

_cell_lifecycle_effect(value) = value isa AbstractCellLifecycleEffect
_relationship_lifecycle_effect(value) = value isa Union{Create, Remove, Retune}

function _lifecycle_diagnostic(kind, statement, expected, actual; alternatives = ())
    identity = QualifiedStatementID((), statement_id(statement))
    return PottsDiagnostic(
        kind,
        identity,
        _statement_expression(statement),
        (),
        expected,
        actual,
        Tuple(alternatives),
        statement_source(statement),
    )
end

function _throw_lifecycle_completion(statement, kind, expected, actual;
        alternatives = ())
    throw(PottsValidationError(
        :completion,
        (_lifecycle_diagnostic(
            kind, statement, expected, actual; alternatives
        ),),
    ))
end

function _lifecycle_boolean_expression(value)
    value isa Bool && return true
    classification = SymbolicIndexingInterface.symbolic_type(value)
    # Completion admits a scalar symbolic trigger into the sole normalized
    # pipeline. Analysis then proves the exact Bool result and dimensionless
    # units from the frozen operation schemas; no SymbolicUtils internals are
    # consulted here.
    return classification isa SymbolicIndexingInterface.ScalarSymbolic
end

_same_binding(left::CellBinding, right::CellBinding) =
    left.name === right.name && isequal(_binding_token(left), _binding_token(right))

function _policy_value(item)
    item isa Pair && return last(item)
    return item
end

function _validate_state_policies!(statement, effect, admitted)
    for item in effect.state
        item isa Pair && first(item) isa CellState ||
            _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_state_target,
                "CellState => typed state policy",
                repr(item),
            )
        policy = _policy_value(item)
        policy isa admitted || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_state_policy,
            "one operation-compatible typed state policy",
            string(typeof(policy)),
        )
    end
    return nothing
end

function _validate_relationship_policies!(statement, effect, admitted)
    for item in effect.relationships
        item isa Pair && first(item) isa RelationshipState ||
            _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_relationship_target,
                "RelationshipState => typed consequence policy",
                repr(item),
            )
        policy = _policy_value(item)
        policy isa admitted || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_relationship_policy,
            "one operation-compatible relationship consequence policy",
            string(typeof(policy)),
        )
    end
    return nothing
end

_lifecycle_state_slot(::CreateCell) = (
    :creation, Union{InitializeFrom, Unsupported}
)
_lifecycle_state_slot(::Union{RemoveCell, Retire}) = (
    :retirement, Union{RetireTo, Unsupported}
)
_lifecycle_state_slot(::Transition) = (
    :transition, Union{Preserve, ResetTo, Transform, Unsupported}
)
_lifecycle_state_slot(::Divide) = (
    :division,
    Union{
        CopyToDaughters,
        PreserveParentResetDaughter,
        ResetBoth,
        SplitConservatively,
        TransformDaughters,
        RedrawDaughters,
        Unsupported,
    },
)

_lifecycle_relationship_slot(::Union{RemoveCell, Retire}) = (
    :retirement, Union{RejectWhileLinked, RemoveIncident}
)
_lifecycle_relationship_slot(::Transition) = (
    :transition,
    Union{PreserveCompatible, RemoveIncompatible, RejectIncompatible},
)
_lifecycle_relationship_slot(::Divide) = (
    :division, Union{RejectWhileLinked, RemoveIncident}
)

function _canonical_visible_declarations(statements, type)
    by_id = Dict{StatementID, AbstractPottsStatement}()
    for statement in statements
        statement isa type || continue
        by_id[statement_id(statement)] = statement
    end
    return Tuple(sort!(collect(values(by_id)); by = statement ->
        string(statement_id(statement))))
end

function _canonical_policy_overrides!(statement, values, target_type, admitted)
    result = Dict{StatementID, Any}()
    for item in values
        item isa Pair && first(item) isa target_type ||
            _throw_lifecycle_completion(
                statement,
                target_type === CellState ?
                    :illegal_lifecycle_state_target :
                    :illegal_lifecycle_relationship_target,
                "$(nameof(target_type)) => compatible typed policy",
                repr(item),
            )
        identity = statement_id(first(item))
        haskey(result, identity) && _throw_lifecycle_completion(
            statement,
            :duplicate_lifecycle_policy_override,
            "one override per qualified schema",
            string(identity),
        )
        policy = last(item)
        policy isa admitted || _throw_lifecycle_completion(
            statement,
            target_type === CellState ?
                :illegal_lifecycle_state_policy :
                :illegal_lifecycle_relationship_policy,
            "an operation-compatible typed policy",
            string(typeof(policy)),
        )
        result[identity] = policy
    end
    return result
end

function _resolve_cell_state_policies(statement, effect, visible)
    slot, admitted = _lifecycle_state_slot(effect)
    overrides = _canonical_policy_overrides!(
        statement, effect.state, CellState, admitted
    )
    states = _canonical_visible_declarations(visible, CellState)
    resolved = Pair[]
    sources = Pair[]
    for state in states
        identity = statement_id(state)
        if haskey(overrides, identity)
            policy = overrides[identity]
            source = :event_override
        else
            options = _statement_options(state)
            haskey(options, slot) || _throw_lifecycle_completion(
                statement,
                :missing_lifecycle_state_policy,
                "an event override or CellState $(slot) policy for $(identity)",
                "no compatible policy",
            )
            policy = getproperty(options, slot)
            policy isa admitted || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_state_policy,
                "an operation-compatible CellState $(slot) policy",
                string(typeof(policy)),
            )
            source = :schema
        end
        push!(resolved, state => policy)
        push!(sources, identity => source)
        delete!(overrides, identity)
    end
    isempty(overrides) || _throw_lifecycle_completion(
        statement,
        :unresolved_lifecycle_state_target,
        "a lexically visible CellState",
        string(first(keys(overrides))),
    )
    return Tuple(resolved), Tuple(sources)
end

function _relationship_schema_policy(statement, relationship, slot)
    options = _statement_options(relationship)
    haskey(options, slot) && return getproperty(options, slot)
    slot === :retirement || return nothing
    endpoint = get(options, :lifecycle, RejectEndpointRetirement())
    endpoint isa RemoveWithEndpoint && return RemoveIncident()
    endpoint isa RejectEndpointRetirement && return RejectWhileLinked()
    _throw_lifecycle_completion(
        statement,
        :illegal_lifecycle_relationship_policy,
        "RemoveWithEndpoint() or RejectEndpointRetirement()",
        string(typeof(endpoint)),
    )
end

function _resolve_relationship_policies(statement, effect, visible)
    effect isa CreateCell && return (), ()
    slot, admitted = _lifecycle_relationship_slot(effect)
    overrides = _canonical_policy_overrides!(
        statement, effect.relationships, RelationshipState, admitted
    )
    relationships = _canonical_visible_declarations(visible, RelationshipState)
    resolved = Pair[]
    sources = Pair[]
    for relationship in relationships
        identity = statement_id(relationship)
        if haskey(overrides, identity)
            policy = overrides[identity]
            source = :event_override
        else
            policy = _relationship_schema_policy(statement, relationship, slot)
            policy === nothing && _throw_lifecycle_completion(
                statement,
                :missing_lifecycle_relationship_policy,
                "an event override or RelationshipState $(slot) policy for $(identity)",
                "no compatible policy",
            )
            policy isa admitted || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_relationship_policy,
                "an operation-compatible RelationshipState $(slot) policy",
                string(typeof(policy)),
            )
            source = :schema
        end
        push!(resolved, relationship => policy)
        push!(sources, identity => source)
        delete!(overrides, identity)
    end
    isempty(overrides) || _throw_lifecycle_completion(
        statement,
        :unresolved_lifecycle_relationship_target,
        "a lexically visible RelationshipState",
        string(first(keys(overrides))),
    )
    return Tuple(resolved), Tuple(sources)
end

function _resolved_site_ownership_policies(statement, effect, visible)
    effect isa Union{CreateCell, RemoveCell, Divide} || return ()
    result = Pair[]
    for state in _canonical_visible_declarations(visible, SiteState)
        options = _statement_options(state)
        haskey(options, :lifecycle) || _throw_lifecycle_completion(
            statement,
            :missing_site_ownership_policy,
            "ClearOnOwnershipChange() or PreserveOnOwnershipChange() for " *
                string(statement_id(state)),
            "no site ownership-change law",
        )
        policy = options.lifecycle
        policy isa Union{ClearOnOwnershipChange, PreserveOnOwnershipChange} ||
            _throw_lifecycle_completion(
                statement,
                :illegal_site_ownership_policy,
                "ClearOnOwnershipChange() or PreserveOnOwnershipChange()",
                string(typeof(policy)),
            )
        push!(result, state => policy)
    end
    return Tuple(result)
end

_replace_lifecycle_policies(effect::CreateCell, state, relationships) =
    CreateCell(
        effect.kind,
        effect.placement,
        state,
        effect.priority,
        effect.on_inadmissible,
    )
_replace_lifecycle_policies(effect::RemoveCell, state, relationships) =
    RemoveCell(
        effect.cell,
        effect.replacement,
        state,
        relationships,
        effect.priority,
        effect.on_inadmissible,
    )
_replace_lifecycle_policies(effect::Retire, state, relationships) = Retire(
    effect.cell,
    state,
    relationships,
    effect.priority,
    effect.on_inadmissible,
)
_replace_lifecycle_policies(effect::Transition, state, relationships) =
    Transition(
        effect.cell,
        effect.kind,
        state,
        relationships,
        effect.priority,
        effect.on_inadmissible,
    )
_replace_lifecycle_policies(effect::Divide, state, relationships) = Divide(
    effect.cell,
    effect.geometry,
    effect.relation,
    effect.side,
    effect.parent_kind,
    effect.daughter_kind,
    state,
    relationships,
    effect.priority,
    effect.on_inadmissible,
)

function _resolve_lifecycle_process(statement::LifecycleProcess, visible)
    options = _statement_options(statement)
    haskey(options, :resolved_state_policy_sources) &&
        haskey(options, :resolved_relationship_policy_sources) &&
        haskey(options, :resolved_site_ownership) && return statement
    arguments = _statement_arguments(statement)
    length(arguments.effects) == 1 || return statement
    effect = only(arguments.effects)
    _cell_lifecycle_effect(effect) || return statement
    state, state_sources = _resolve_cell_state_policies(
        statement, effect, visible
    )
    relationships, relationship_sources = _resolve_relationship_policies(
        statement, effect, visible
    )
    site_ownership = _resolved_site_ownership_policies(
        statement, effect, visible
    )
    resolved_effect = _replace_lifecycle_policies(
        effect, state, relationships
    )
    core = getfield(statement, :core)
    resolved_arguments = merge(arguments, (; effects = (resolved_effect,)))
    resolved_options = merge(core.options, (;
        resolved_state_policy_sources = state_sources,
        resolved_relationship_policy_sources = relationship_sources,
        resolved_site_ownership = site_ownership,
    ))
    return LifecycleProcess(StatementCore(
        core.id, resolved_arguments, resolved_options, core.source
    ))
end

function _validate_lifecycle_effect!(statement, domain, anchor, effect)
    if effect isa CreateCell
        domain isa ModelDomain || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_domain,
            "model() for CreateCell",
            string(typeof(domain)),
        )
        anchor === nothing || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_anchor,
            "no bound cell anchor for model-domain creation",
            repr(anchor),
        )
        effect.kind isa CellKind || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_kind,
            "a CellKind destination",
            string(typeof(effect.kind)),
        )
        placement = effect.placement
        builtin = placement isa AbstractLifecyclePlacementPolicy
        symbolic = !(SymbolicIndexingInterface.symbolic_type(placement) isa
            SymbolicIndexingInterface.NotSymbolic)
        (builtin || symbolic) || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_placement,
            "SeedAt, SeedStencil, or a registered symbolic placement policy",
            string(typeof(placement)),
        )
        placement isa SeedStencil && !(placement.relation isa SpatialRelation) &&
            _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_relation,
                "a SpatialRelation bound by SeedStencil",
                string(typeof(placement.relation)),
            )
        _validate_state_policies!(
            statement, effect, Union{InitializeFrom, Unsupported}
        )
    else
        domain isa Cells || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_domain,
            "cells(kind) for $(nameof(typeof(effect)))",
            string(typeof(domain)),
        )
        anchor isa CellBinding || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_anchor,
            "one explicit CellBinding",
            string(typeof(anchor)),
        )
        effect.cell isa CellBinding && _same_binding(anchor, effect.cell) ||
            _throw_lifecycle_completion(
                statement,
                :lifecycle_binding_mismatch,
                "the effect source must be the process CellBinding",
                repr(effect.cell),
            )
        domain.kind isa CellKind || _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_kind,
            "cells(CellKind)",
            string(typeof(domain.kind)),
        )
        if effect isa RemoveCell
            effect.replacement isa MediumKind || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_replacement,
                "a declared MediumKind replacement",
                string(typeof(effect.replacement)),
            )
            _validate_state_policies!(
                statement, effect, Union{RetireTo, Unsupported}
            )
            _validate_relationship_policies!(
                statement, effect, Union{RejectWhileLinked, RemoveIncident}
            )
        elseif effect isa Retire
            _validate_state_policies!(
                statement, effect, Union{RetireTo, Unsupported}
            )
            _validate_relationship_policies!(
                statement, effect, Union{RejectWhileLinked, RemoveIncident}
            )
        elseif effect isa Transition
            effect.kind isa CellKind || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_kind,
                "a CellKind transition destination",
                string(typeof(effect.kind)),
            )
            _validate_state_policies!(
                statement, effect, Union{Preserve, ResetTo, Transform, Unsupported}
            )
            _validate_relationship_policies!(
                statement,
                effect,
                Union{PreserveCompatible, RemoveIncompatible, RejectIncompatible},
            )
        elseif effect isa Divide
            builtin = effect.geometry isa AbstractLifecyclePartitionPolicy
            symbolic = !(SymbolicIndexingInterface.symbolic_type(effect.geometry) isa
                SymbolicIndexingInterface.NotSymbolic)
            (builtin || symbolic) || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_partition,
                "a built-in or registered symbolic binary partition",
                string(typeof(effect.geometry)),
            )
            effect.relation isa SpatialRelation || _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_relation,
                "an explicit SpatialRelation",
                string(typeof(effect.relation)),
            )
            effect.side isa AbstractLifecycleSidePolicy ||
                _throw_lifecycle_completion(
                    statement,
                    :illegal_lifecycle_side_policy,
                    "CanonicalSide() or StableRandomSide(draw_identity)",
                    string(typeof(effect.side)),
                )
            for policy in (effect.parent_kind, effect.daughter_kind)
                policy isa PreserveKind && continue
                policy isa SetKind && policy.kind isa CellKind && continue
                _throw_lifecycle_completion(
                    statement,
                    :illegal_lifecycle_kind_policy,
                    "PreserveKind() or SetKind(CellKind)",
                    repr(policy),
                )
            end
            _validate_state_policies!(
                statement,
                effect,
                Union{
                    CopyToDaughters,
                    PreserveParentResetDaughter,
                    ResetBoth,
                    SplitConservatively,
                    TransformDaughters,
                    RedrawDaughters,
                    Unsupported,
                },
            )
            _validate_relationship_policies!(
                statement, effect, Union{RejectWhileLinked, RemoveIncident}
            )
        end
    end
    return nothing
end

function _validate_lifecycle_process!(statement::LifecycleProcess)
    arguments = _statement_arguments(statement)
    options = _statement_options(statement)
    effects = arguments.effects
    isempty(effects) && _throw_lifecycle_completion(
        statement,
        :missing_lifecycle_effect,
        "one structural cell effect or bounded relationship effect",
        "no effects",
    )
    cell_effects = count(_cell_lifecycle_effect, effects)
    relationship_effects = count(_relationship_lifecycle_effect, effects)
    if cell_effects > 0
        length(effects) == 1 && cell_effects == 1 ||
            _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_effect_composition,
                "exactly one closed cell-structure effect",
                repr(nameof.(typeof.(effects))),
            )
        _validate_lifecycle_effect!(
            statement, arguments.domain, arguments.anchor, only(effects)
        )
    elseif relationship_effects != length(effects)
        _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_effect,
            "one closed cell effect or only bounded relationship effects",
            repr(nameof.(typeof.(effects))),
        )
    end
    _lifecycle_boolean_expression(arguments.expression) ||
        _throw_lifecycle_completion(
            statement,
            :invalid_lifecycle_trigger_type,
            "a dimensionless Boolean expression",
            string(typeof(arguments.expression)),
        )
    get(options, :phase, Lifecycle()) isa Lifecycle ||
        _throw_lifecycle_completion(
            statement,
            :illegal_lifecycle_phase,
            "Lifecycle()",
            string(typeof(get(options, :phase, nothing))),
        )
    cadence = get(options, :cadence, EveryMCS())
    cadence isa AbstractCadence || _throw_lifecycle_completion(
        statement,
        :illegal_lifecycle_cadence,
        "an integer-MCS cadence",
        string(typeof(cadence)),
    )
    cadence isa AtMCS && cadence.mcs <= 0 && _throw_lifecycle_completion(
        statement,
        :illegal_lifecycle_cadence,
        "a positive lifecycle MCS (MCS zero is initialization)",
        string(cadence.mcs),
    )
    return nothing
end

function _retire_at_zero_process(kind::CellKind, policy::RetireAtZero)
    local_name = Symbol(statement_id(kind))
    cell = CellBinding(Symbol(:retire_at_zero_, local_name))
    return LifecycleProcess(
        Symbol(:__potts_retire_at_zero_, local_name);
        domain = cells(kind),
        anchor = cell,
        expression = cell_volume(anchor_value(cell)) == 0,
        effects = (Retire(
            cell;
            priority = policy.priority,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        phase = Lifecycle(),
        cadence = EveryMCS(),
        compiler_synthesized = :retire_at_zero,
        source = statement_source(kind),
    )
end

function _forbid_extinction_constraint(kind::CellKind)
    local_name = Symbol(statement_id(kind))
    proposal = ProposalContext(Symbol(:forbid_extinction_, local_name))
    owner = proposal.target_cell
    expression = (owner <= 0) |
                 (proposal.target_kind != _kind_token(kind)) |
                 (cell_volume(owner) != 1)
    return ProposalConstraint(
        Symbol(:__potts_forbid_extinction_, local_name),
        expression;
        compiler_synthesized = :forbid_extinction,
        source = statement_source(kind),
    )
end

function _cell_extinction_statement(kind::CellKind)
    options = _statement_options(kind)
    haskey(options, :extinction) || _throw_lifecycle_completion(
        kind,
        :missing_extinction_policy,
        "RetireAtZero() or ForbidExtinction()",
        "no extinction policy",
    )
    policy = options.extinction
    policy isa RetireAtZero && return _retire_at_zero_process(kind, policy)
    policy isa ForbidExtinction && return _forbid_extinction_constraint(kind)
    _throw_lifecycle_completion(
        kind,
        :illegal_extinction_policy,
        "RetireAtZero() or ForbidExtinction()",
        string(typeof(policy)),
    )
end

function _validate_medium_extinction!(medium::MediumKind)
    haskey(_statement_options(medium), :extinction) || return nothing
    _throw_lifecycle_completion(
        medium,
        :medium_extinction_policy,
        "no finite-cell extinction law on a MediumKind",
        repr(_statement_options(medium).extinction),
    )
end

function _validate_lifecycle_conflicts!(statements)
    policies = Any[]
    for statement in statements
        statement isa Protocol || continue
        policy = get(
            _statement_options(statement),
            :lifecycle_conflicts,
            RejectLifecycleAmbiguity(),
        )
        policy isa AbstractLifecycleConflictPolicy ||
            _throw_lifecycle_completion(
                statement,
                :illegal_lifecycle_conflict_policy,
                "RejectLifecycleAmbiguity() or StableLifecyclePriority()",
                string(typeof(policy)),
            )
        any(candidate -> isequal(candidate, policy), policies) || push!(policies, policy)
    end
    length(policies) <= 1 || _throw_lifecycle_completion(
        first(filter(statement -> statement isa Protocol, statements)),
        :conflicting_lifecycle_phase_policy,
        "one lifecycle conflict policy across the composed system",
        repr(nameof.(typeof.(policies))),
    )
    return isempty(policies) ? RejectLifecycleAmbiguity() : only(policies)
end
