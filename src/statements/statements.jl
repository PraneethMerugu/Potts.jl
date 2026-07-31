abstract type AbstractPottsStatement end
abstract type AbstractPottsEffect end
abstract type AbstractPottsPhase end
abstract type AbstractStatementSource end

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

struct UnknownSource <: AbstractStatementSource end

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

statement_id(statement::AbstractPottsStatement) = getfield(statement, :core).id
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

macro _define_statement_type(type_name)
    quote
        struct $(esc(type_name)){C <: StatementCore} <: AbstractPottsStatement
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

@_define_statement_type CellKind
@_define_statement_type MediumKind
@_define_statement_type LatticeDomain
@_define_statement_type SpatialRelation
@_define_statement_type SiteState
@_define_statement_type CellState
@_define_statement_type MediumState
@_define_statement_type ModelState
@_define_statement_type FieldState
@_define_statement_type HistoryState
@_define_statement_type RelationshipState
@_define_statement_type HamiltonianTerm
@_define_statement_type ProposalDrive
@_define_statement_type ProposalConstraint
@_define_statement_type ProposalModifier
@_define_statement_type SynchronousProcess
@_define_statement_type AcceptedCopyProcess
@_define_statement_type RelationshipProcess
@_define_statement_type LifecycleProcess
@_define_statement_type EquationProcess
@_define_statement_type Observation
@_define_statement_type Protocol
@_define_statement_type RegisteredStatement

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

function (::Type{T})(id::Union{Symbol, StatementID}; source = UnknownSource(), kwargs...) where {
        T <: _DECLARATION_TYPES,
    }
    return T(_statement_core(id, (), (; kwargs...), source))
end

function (::Type{T})(id::Union{Symbol, StatementID}; initial = nothing,
        source = UnknownSource(), kwargs...) where {T <: _STATE_TYPES}
    return T(_statement_core(id, (; initial), (; kwargs...), source))
end

function (::Type{T})(id::Union{Symbol, StatementID}, expression;
        source = UnknownSource(), kwargs...) where {T <: _PROPOSAL_TYPES}
    return T(_statement_core(id, (; expression), (; kwargs...), source))
end

function (::Type{T})(id::Union{Symbol, StatementID};
        domain = nothing, expression = nothing, effects = (),
        phase = nothing, source = UnknownSource(), kwargs...) where {T <: _PROCESS_TYPES}
    return T(_statement_core(
        id,
        (; domain, expression, effects = _defensive_tuple(effects)),
        (; phase, kwargs...),
        source,
    ))
end

function EquationProcess(id::Union{Symbol, StatementID}, equations;
        writes = (), solver = nothing, cadence = nothing, duration_per_mcs = nothing,
        substeps::Integer = 1, phase = nothing, source = UnknownSource(), kwargs...)
    substeps > 0 || throw(ArgumentError("EquationProcess substeps must be positive"))
    return EquationProcess(_statement_core(
        id,
        (; equations = _defensive_tuple(equations), writes = _defensive_tuple(writes)),
        (; solver, cadence, duration_per_mcs, substeps = Int(substeps), phase, kwargs...),
        source,
    ))
end

function Observation(id::Union{Symbol, StatementID}, expression;
        source = UnknownSource(), kwargs...)
    return Observation(_statement_core(id, (; expression), (; kwargs...), source))
end

function Protocol(id::Union{Symbol, StatementID}; stages = (), source = UnknownSource(), kwargs...)
    return Protocol(_statement_core(
        id, (; stages = _defensive_tuple(stages)), (; kwargs...), source
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

struct StatementRegistry{T <: Tuple}
    definitions::T
end

StatementRegistry() = StatementRegistry(())

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
    ) || throw(ArgumentError("registered effect class is not a V1 effect"))
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
        "V1 registered statements must admit the sequential engine"
    ))
    (!contract.capabilities.checkerboard &&
     isempty(contract.capabilities.reason)) &&
        throw(ArgumentError(
            "a checkerboard rejection requires a nonempty reason"
        ))
    contract.scientific_category in (
        :hamiltonian, :drive, :constraint, :modifier, :process, :observation,
    ) || throw(ArgumentError(
        "registered scientific_category is not a closed V1 category"
    ))
    contract.energy_domain in (
        nothing, :sites, :cells, :contacts, :relationships,
    ) || throw(ArgumentError(
        "registered energy_domain is not a closed V1 energy domain"
    ))
    contract.affected_region in (
        nothing, :target_site, :source_and_target_cells,
        :incident_contacts, :incident_relationships,
    ) || throw(ArgumentError(
        "registered affected_region is not a closed V1 affected-anchor class"
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

default_statement_registry() = StatementRegistry()
