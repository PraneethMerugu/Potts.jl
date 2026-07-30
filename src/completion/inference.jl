function _collect_symbolics!(found, value)
    if value isa NamedTuple
        foreach(item -> _collect_symbolics!(found, item), values(value))
    elseif value isa Tuple || value isa AbstractArray
        foreach(item -> _collect_symbolics!(found, item), value)
    elseif value isa Pair
        _collect_symbolics!(found, first(value))
        _collect_symbolics!(found, last(value))
    elseif value isa AbstractDict
        for (key, item) in value
            _collect_symbolics!(found, key)
            _collect_symbolics!(found, item)
        end
    elseif value isa AbstractPottsEffect
        for field in fieldnames(typeof(value))
            _collect_symbolics!(found, getfield(value, field))
        end
    elseif value isa AbstractPottsStatement
        # Statement references are semantic identities, not nested declarations.
        return found
    elseif !(Symbolics.symbolic_type(value) isa
             SymbolicIndexingInterface.NotSymbolic)
        variables = try
            Symbolics.get_variables(value)
        catch
            Any[value]
        end
        for variable in variables
            any(isequal(variable), found) || push!(found, variable)
        end
    end
    return found
end

_collect_symbolics(value) = Tuple(_collect_symbolics!(Any[], value))

function _effect_writes(effect::Assign)
    return _collect_symbolics(effect.target)
end
_effect_writes(effect::Create) = (effect.relationship,)
_effect_writes(effect::Remove) = (effect.relationship,)
_effect_writes(effect::Retune) = (effect.relationship,)
_effect_writes(effect::Transition) = (effect.cell,)
_effect_writes(effect::Divide) = (effect.cell,)
_effect_writes(effect::Retire) = (effect.cell,)

function _statement_writes(statement::AbstractPottsStatement)
    if statement isa Union{
            SiteState, CellState, MediumState, ModelState, FieldState, HistoryState,
            RelationshipState,
        }
        arguments = _statement_arguments(statement)
        return arguments isa NamedTuple && haskey(arguments, :variable) ?
               (arguments.variable,) : ()
    end
    arguments = _statement_arguments(statement)
    effects = arguments isa NamedTuple && haskey(arguments, :effects) ?
              arguments.effects : ()
    writes = Any[]
    for effect in effects
        for value in _effect_writes(effect)
            any(isequal(value), writes) || push!(writes, value)
        end
    end
    if statement isa EquationProcess && arguments isa NamedTuple &&
            haskey(arguments, :writes)
        for value in arguments.writes
            any(isequal(value), writes) || push!(writes, value)
        end
    end
    return Tuple(writes)
end

function _statement_reads(statement::AbstractPottsStatement, writes)
    found = Any[]
    _collect_symbolics!(found, _statement_arguments(statement))
    _collect_symbolics!(found, _statement_options(statement))
    filter!(value -> !any(isequal(value), writes), found)
    return Tuple(found)
end

_statement_effect(::Union{
    CellKind, MediumKind, LatticeDomain, SpatialRelation,
    SiteState, CellState, MediumState, ModelState, FieldState, HistoryState,
    RelationshipState, ProposalEnergy, ProposalDrive, ProposalConstraint,
    ProposalModifier, EquationProcess, Observation, Protocol,
}) = PureRead()
_statement_effect(::SynchronousProcess) = SynchronousAssign()
_statement_effect(::AcceptedCopyProcess) = AcceptedCopyEffect()
_statement_effect(::Union{RelationshipProcess, LifecycleProcess}) = OrderedBatchEffect()
_statement_effect(::RegisteredStatement) = PureRead()

function _statement_phase(statement)
    options = _statement_options(statement)
    options isa NamedTuple && haskey(options, :phase) &&
        options.phase !== nothing && return options.phase
    statement isa Union{
        ProposalEnergy, ProposalDrive, ProposalConstraint, ProposalModifier
    } && return Proposal()
    statement isa AcceptedCopyProcess && return AcceptedCopy()
    statement isa SynchronousProcess && return AfterMCS()
    statement isa RelationshipProcess && return RelationshipCommit()
    statement isa LifecycleProcess && return Lifecycle()
    statement isa EquationProcess && return EquationStep()
    statement isa Observation && return Observe()
    return nothing
end

function _effect_bound(statement)
    arguments = _statement_arguments(statement)
    effects = arguments isa NamedTuple && haskey(arguments, :effects) ?
              arguments.effects : ()
    isempty(effects) && return EffectBound(0, :read_only)
    domain = arguments isa NamedTuple && haskey(arguments, :domain) ?
             arguments.domain : nothing
    domain isa Sites && return EffectBound(length(effects), :per_site)
    domain isa Cells && return EffectBound(length(effects), :per_cell)
    domain isa Contacts && return EffectBound(length(effects), :per_contact)
    domain isa Edges && return EffectBound(length(effects), :per_edge)
    domain isa IncidentEdges && return EffectBound(length(effects), :per_incident_edge)
    return EffectBound(length(effects), :per_invocation)
end

function _contains_relationship_effect(value)
    value isa Union{Create, Remove, Retune} && return true
    value isa NamedTuple && return any(_contains_relationship_effect, values(value))
    value isa Tuple && return any(_contains_relationship_effect, value)
    value isa AbstractArray && return any(_contains_relationship_effect, value)
    return false
end

function _engine_admission(statement)
    sequential = EngineAdmission(:sequential, true, "")
    if statement isa AcceptedCopyProcess &&
            _contains_relationship_effect(_statement_arguments(statement))
        checkerboard = EngineAdmission(
            :checkerboard,
            false,
            "accepted-copy relationship mutation has no proven complete conflict set",
        )
    else
        checkerboard = EngineAdmission(:checkerboard, true, "")
    end
    return (sequential, checkerboard)
end

function _random_operations(statement, identity::QualifiedStatementID)
    result = RandomOperation[]
    payload = (_statement_arguments(statement), _statement_options(statement))
    variables = _collect_symbolics(payload)
    for variable in variables
        occursin("__potts_draw__", string(variable)) || continue
        key = Symbol(replace(string(variable), "__potts_draw__" => ""))
        push!(result, RandomOperation(key, :explicit, false))
    end
    statement isa Protocol && push!(
        result,
        RandomOperation(Symbol(string(identity), "_proposal"), :proposal, true),
        RandomOperation(Symbol(string(identity), "_acceptance"), :acceptance, true),
    )
    return Tuple(result)
end

function _lowering_identity(statement)
    options = _statement_options(statement)
    if options isa NamedTuple && haskey(options, :mechanism)
        return Symbol(:lower_, options.mechanism)
    end
    return Symbol(:lower_, lowercase(String(statement_kind(statement))))
end
