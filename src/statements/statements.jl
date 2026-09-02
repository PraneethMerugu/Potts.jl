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

"""Immutable, ordered collection of uniquely identified Potts statements."""
struct StatementSet{T <: Tuple}
    values::T
    StatementSet(values::T, ::Val{:raw}) where {T <: Tuple} = new{T}(values)
end

StatementSet() = StatementSet((), Val(:raw))
StatementSet(statement::AbstractPottsStatement) = StatementSet((statement,))

function StatementSet(values)
    flattened = AbstractPottsStatement[]
    for value in values
        if value isa StatementSet
            append!(flattened, value.values)
        elseif value isa AbstractPottsStatement
            push!(flattened, value)
        else
            throw(ArgumentError(
                "StatementSet accepts Potts statements, got $(typeof(value))"
            ))
        end
    end
    return StatementSet(Tuple(flattened), Val(:raw))
end

statements(set::StatementSet) = set.values
statements(statement::AbstractPottsStatement) = (statement,)
Base.length(set::StatementSet) = length(set.values)
Base.isempty(set::StatementSet) = isempty(set.values)
Base.iterate(set::StatementSet, state...) = iterate(set.values, state...)
Base.getindex(set::StatementSet, index::Integer) = set.values[index]
Base.eltype(::Type{<:StatementSet}) = AbstractPottsStatement

function Base.show(io::IO, set::StatementSet)
    print(io, "StatementSet(", length(set), " statement")
    length(set) == 1 || print(io, "s")
    print(io, ")")
end

function _capture_statement(statement, source::SourceLocation)
    if statement isa StatementSet
        return StatementSet(with_source(item, source) for item in statement)
    elseif statement isa AbstractPottsStatement
        return with_source(statement, source)
    end
    throw(ArgumentError("@statements entries must construct Potts statements"))
end

"""Construct a `StatementSet` from statement expressions while retaining source provenance."""
macro statements(block)
    expressions = block isa Expr && block.head === :block ? block.args : Any[block]
    captured = Any[]
    line = __source__.line
    source_location = GlobalRef(@__MODULE__, :SourceLocation)
    capture_statement = GlobalRef(@__MODULE__, :_capture_statement)
    statement_set = GlobalRef(@__MODULE__, :StatementSet)
    for expression in expressions
        if expression isa LineNumberNode
            line = expression.line
            continue
        end
        source = :(
            $source_location(
                $(String(__source__.file)),
                $line,
                $(QuoteNode(nameof(__module__))),
                $(string(expression)),
            )
        )
        push!(captured, :($capture_statement($(esc(expression)), $source)))
    end
    return :($statement_set(($(captured...),)))
end

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
