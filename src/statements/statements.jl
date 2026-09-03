"""Supertype of immutable declarative statements accepted by `PottsSystem`."""
abstract type AbstractPottsStatement end
"""Supertype of effects performed by scheduled Potts processes."""
abstract type AbstractPottsEffect end
"""Supertype of durable execution-phase markers used by process schedules."""
abstract type AbstractPottsPhase end
abstract type AbstractStatementSource end

"""Stable symbolic identity of a Potts statement."""
struct StatementID
    value::Symbol
    function StatementID(value::Symbol)
        isempty(String(value)) && throw(ArgumentError("a StatementID cannot be empty"))
        return new(value)
    end
end

StatementID(id::StatementID) = id
Base.Symbol(id::StatementID) = id.value
Base.string(id::StatementID) = String(id.value)
Base.show(io::IO, id::StatementID) = print(io, id.value)
Base.:(==)(left::StatementID, right::StatementID) = left.value == right.value
Base.hash(id::StatementID, seed::UInt) = hash(id.value, seed)

"""Source-provenance marker used when no authored location is available."""
struct UnknownSource <: AbstractStatementSource end

"""Authored file, line, module, and expression provenance for a statement."""
struct SourceLocation <: AbstractStatementSource
    file::String
    line::Int
    module_name::Symbol
    expression::String
    function SourceLocation(file, line::Integer, module_name, expression)
        line >= 0 || throw(ArgumentError("a source line must be nonnegative"))
        modname = module_name isa Module ? nameof(module_name) : Symbol(module_name)
        return new(String(file), Int(line), modname, String(expression))
    end
end

struct StatementCore{A, O, S <: AbstractStatementSource}
    id::StatementID
    arguments::A
    options::O
    source::S
end

function _statement_core(id, arguments, options, source)
    source isa AbstractStatementSource ||
        throw(ArgumentError("source must be UnknownSource() or SourceLocation(...)"))
    for name in keys(options)
        startswith(String(name), "__") || continue
        throw(ArgumentError(
            "statement option `$name` is reserved for internal compiler provenance"
        ))
    end
    return StatementCore(StatementID(id), arguments, options, source)
end

"""Return a statement's stable `StatementID`."""
statement_id(statement::AbstractPottsStatement) = getfield(statement, :core).id
"""Return a statement's `SourceLocation` or `UnknownSource` provenance."""
statement_source(statement::AbstractPottsStatement) = getfield(statement, :core).source
_statement_arguments(statement::AbstractPottsStatement) = getfield(statement, :core).arguments
_statement_options(statement::AbstractPottsStatement) = getfield(statement, :core).options

function Base.show(io::IO, statement::AbstractPottsStatement)
    print(io, nameof(typeof(statement)), "(", repr(Symbol(statement_id(statement))))
    args = _statement_arguments(statement)
    if !(args isa Tuple && isempty(args))
        print(io, ", ", repr(args))
    end
    print(io, ")")
end

"""Return the durable statement-kind symbol for a declarative statement."""
function statement_kind end

"""Return a copy of a statement carrying the supplied source provenance."""
function with_source end

"""Map `f` over the symbolic payload of a statement or symbolic binding."""
function map_symbolics end

macro _define_statement_type(type_name, documentation)
    quote
        Base.@doc $(esc(documentation)) struct $(esc(type_name)){C <: StatementCore} <: AbstractPottsStatement
            core::C
        end

        $(esc(:statement_kind))(::$(esc(type_name))) = $(QuoteNode(type_name))

        function $(esc(:with_source))(
                statement::$(esc(type_name)), source::AbstractStatementSource)
            core = getfield(statement, :core)
            return $(esc(type_name))(
                StatementCore(core.id, core.arguments, core.options, source)
            )
        end

        function $(esc(:map_symbolics))(f, statement::$(esc(type_name)))
            core = getfield(statement, :core)
            return $(esc(type_name))(
                StatementCore(
                    core.id,
                    _map_symbolic_payload(f, core.arguments),
                    _map_symbolic_payload(f, core.options),
                    core.source,
                )
            )
        end
    end
end

@_define_statement_type CellKind "Declare a finite cell-kind identity and its metadata."
@_define_statement_type MediumKind "Declare the distinguished medium kind and its metadata."
@_define_statement_type LatticeDomain "Declare a lattice domain; use `Lattice` for the regular-grid form."
@_define_statement_type SpatialRelation "Declare a named bounded spatial relation within a lattice domain."
@_define_statement_type SiteState "Declare state stored per lattice site."
@_define_statement_type CellState "Declare state stored per finite cell identity."
@_define_statement_type MediumState "Declare state associated with the medium."
@_define_statement_type ModelState "Declare singleton model state."
@_define_statement_type FieldState "Declare spatial field state, optionally from a symbolic array variable."
@_define_statement_type HistoryState "Declare bounded historical state for lagged reads."
@_define_statement_type RelationshipState "Declare bounded relationship state with `capacity` and `maximum_degree`."
@_define_statement_type HamiltonianTerm "Declare a Hamiltonian contribution over a bounded iteration domain."
@_define_statement_type ProposalDrive "Declare an additive proposal-drive expression."
@_define_statement_type ProposalConstraint "Declare a Boolean proposal-admission constraint."
@_define_statement_type ProposalModifier "Declare a proposal-energy or acceptance modifier."
@_define_statement_type SynchronousProcess "Declare a synchronous process whose reads observe stage-entry state."
@_define_statement_type AcceptedCopyProcess "Declare a process evaluated only for accepted copy proposals."
@_define_statement_type RelationshipProcess "Declare a bounded relationship-update process."
@_define_statement_type LifecycleProcess "Declare a process executed at a lifecycle boundary."
@_define_statement_type Observation "Declare a named observable expression."
@_define_statement_type Protocol "Declare ordered `SweepStage` values and a lifecycle conflict policy."
@_define_statement_type RegisteredStatement "Declare a versioned extension statement registered through `StatementRegistry`."


const _DECLARATION_TYPES = Union{
    CellKind,
    MediumKind,
    LatticeDomain,
    SpatialRelation,
}

const _STATE_TYPES = Union{
    SiteState,
    CellState,
    MediumState,
    ModelState,
    FieldState,
    HistoryState,
    RelationshipState,
}

const _SYMBOLIC_STATE_TYPES = Union{
    SiteState,
    CellState,
    MediumState,
    ModelState,
    FieldState,
    HistoryState,
}

const _PROPOSAL_TYPES = Union{
    ProposalDrive,
    ProposalConstraint,
    ProposalModifier,
}

const _PROCESS_TYPES = Union{
    SynchronousProcess,
    AcceptedCopyProcess,
    RelationshipProcess,
    LifecycleProcess,
}

function _declaration_statement(
        ::Type{T}, id::Union{Symbol, StatementID};
        source = UnknownSource(), kwargs...,
    ) where {T <: _DECLARATION_TYPES}
    return T(_statement_core(id, (), (; kwargs...), source))
end

function _state_statement(
        ::Type{T}, id::Union{Symbol, StatementID};
        initial = nothing, source = UnknownSource(), kwargs...,
    ) where {T <: _STATE_TYPES}
    return T(_statement_core(id, (; initial), (; kwargs...), source))
end

for type_name in (:CellKind, :MediumKind, :LatticeDomain, :SpatialRelation)
    @eval function $type_name(
            id::Union{Symbol, StatementID};
            source = UnknownSource(), kwargs...,
        )
        return _declaration_statement(
            $type_name, id; source, kwargs...
        )
    end
end

for type_name in (
        :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
        :HistoryState,
    )
    @eval function $type_name(
            id::Union{Symbol, StatementID};
            initial = nothing, source = UnknownSource(), kwargs...,
        )
        return _state_statement(
            $type_name, id; initial, source, kwargs...
        )
    end
end

function RelationshipState(
        id::Union{Symbol, StatementID};
        initial = nothing,
        source = UnknownSource(),
        capacity,
        maximum_degree = capacity,
        kwargs...,
    )
    return RelationshipState(_statement_core(
        id,
        (; initial),
        (; capacity, maximum_degree, kwargs...),
        source,
    ))
end

function (::Type{T})(id::Union{Symbol, StatementID}, expression;
        source = UnknownSource(), kwargs...) where {T <: _PROPOSAL_TYPES}
    return T(_statement_core(id, (; expression), (; kwargs...), source))
end

function _process_statement(
        ::Type{T}, id::Union{Symbol, StatementID};
        domain = nothing, expression = nothing, effects = (), phase = nothing,
        source = UnknownSource(), kwargs...,
    ) where {T <: _PROCESS_TYPES}
    return T(_statement_core(
        id,
        (; domain, expression, effects = _defensive_tuple(effects)),
        (; phase, kwargs...),
        source,
    ))
end


for type_name in (
        :SynchronousProcess, :AcceptedCopyProcess, :RelationshipProcess,
    )
    @eval function $type_name(
            id::Union{Symbol, StatementID};
            domain = nothing, expression = nothing, effects = (),
            phase = nothing, source = UnknownSource(), kwargs...,
        )
        return _process_statement(
            $type_name,
            id;
            domain,
            expression,
            effects,
            phase,
            source,
            kwargs...,
        )
    end
end

function Observation(id::Union{Symbol, StatementID}, expression;
        source = UnknownSource(), kwargs...)
    return Observation(_statement_core(id, (; expression), (; kwargs...), source))
end

function Protocol(id::Union{Symbol, StatementID}; stages = (),
        lifecycle_conflicts = RejectLifecycleAmbiguity(),
        source = UnknownSource(), kwargs...)
    frozen_stages = _defensive_tuple(stages)
    all(stage -> stage isa SweepStage, frozen_stages) || throw(ArgumentError(
        "Protocol admits only SweepStage values; observations are settled save metadata"
    ))
    return Protocol(_statement_core(
        id,
        (; stages = frozen_stages),
        (; lifecycle_conflicts, kwargs...),
        source,
    ))
end

function RegisteredStatement(id::Union{Symbol, StatementID}, schema::Symbol,
        version::VersionNumber, arguments...; source = UnknownSource(), kwargs...)
    frozen_arguments = Tuple(
        _freeze_registered_value(value; context = "argument")
        for value in arguments
    )
    frozen_options = NamedTuple{keys(kwargs)}(Tuple(
        _freeze_registered_value(value; context = "option")
        for value in values(kwargs)
    ))
    return RegisteredStatement(_statement_core(
        id,
        (; schema, version, arguments = frozen_arguments),
        frozen_options,
        source,
    ))
end

function _freeze_registered_value(value; context)
    value isa Union{Function, Module, Task, IO} && throw(ArgumentError(
        "a RegisteredStatement $context cannot contain executable host state"
    ))
    # These are stable scalar schema values even when Julia implements the
    # corresponding runtime object (notably `DataType` and `Symbol`) with
    # internal mutability.
    value isa Union{
        Nothing, Missing, Bool, Number, Symbol, String, Char, VersionNumber, Type
    } && return value
    value isa AbstractPottsStatement && throw(ArgumentError(
        "a RegisteredStatement $context cannot contain a nested Potts statement"
    ))
    if parentmodule(typeof(value)) === CorePotts
        throw(ArgumentError(
            "a RegisteredStatement $context cannot contain a CorePotts object"
        ))
    elseif value isa NamedTuple
        mapped = Tuple(
            _freeze_registered_value(item; context) for item in values(value)
        )
        return NamedTuple{keys(value)}(mapped)
    elseif value isa Tuple
        return map(item -> _freeze_registered_value(item; context), value)
    elseif value isa Pair
        return _freeze_registered_value(first(value); context) =>
               _freeze_registered_value(last(value); context)
    elseif value isa AbstractArray
        return Tuple(
            _freeze_registered_value(item; context) for item in value
        )
    elseif value isa AbstractDict
        frozen = Tuple(
            _freeze_registered_value(key; context) =>
            _freeze_registered_value(item; context)
            for (key, item) in value
        )
        return Tuple(sort(collect(frozen); by = pair -> repr(first(pair))))
    elseif ismutabletype(typeof(value))
        throw(ArgumentError(
            "a RegisteredStatement $context must be immutable serializable data"
        ))
    end
    return value
end

function _defensive_tuple(values)
    values === nothing && return ()
    values isa Tuple && return map(_defensive_copy, values)
    values isa AbstractArray && return Tuple(_defensive_copy(value) for value in values)
    return (_defensive_copy(values),)
end

_defensive_copy(value::AbstractArray) = copy(value)
_defensive_copy(value::AbstractDict) = copy(value)
_defensive_copy(value) = value

function _map_symbolic_payload(f, value::NamedTuple)
    mapped = map(item -> _map_symbolic_payload(f, item), values(value))
    return NamedTuple{keys(value)}(mapped)
end

_map_symbolic_payload(f, value::Tuple) =
    map(item -> _map_symbolic_payload(f, item), value)
_map_symbolic_payload(f, value::Pair) =
    _map_symbolic_payload(f, first(value)) => _map_symbolic_payload(f, last(value))
_map_symbolic_payload(f, value::AbstractArray) =
    map(item -> _map_symbolic_payload(f, item), value)
_map_symbolic_payload(f, value::AbstractDict) =
    Dict(_map_symbolic_payload(f, key) => _map_symbolic_payload(f, item)
        for (key, item) in value)

function _map_symbolic_payload(f, value)
    symbolic = !(SymbolicIndexingInterface.symbolic_type(value) isa
        SymbolicIndexingInterface.NotSymbolic)
    return symbolic ? f(value) : value
end
