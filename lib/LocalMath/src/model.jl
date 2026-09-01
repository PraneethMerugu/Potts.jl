const _DETERMINISM_DIMENSIONS = (
    :same_run_replay,
    :workgroup_size_invariance,
    :bucket_order_invariance,
    :scheduling_invariance,
    :same_backend_bitwise,
    :cross_backend_bitwise,
    :numerical_bound,
    :rng_trajectory,
)

struct _ConstructionToken end
const _CONSTRUCTION_TOKEN = _ConstructionToken()

"""
    SourceOrigin(source, line=0; label=nothing)

Host-only authored provenance for inspection and diagnostics. `source` is a
file name or symbolic source label, `line` is its one-based line when known,
and `label` optionally names the authored stage or equation. There is no
zero-argument constructor: omit an enclosing constructor's `origin` keyword
when provenance is unavailable.

Source origins are excluded from semantic equivalence and never enter device
kernels.

```julia
SourceOrigin(@__FILE__, @__LINE__; label=:update_temperature)
```
"""
struct SourceOrigin
    source::String
    line::Int
    label::Union{Nothing, Symbol}
end

SourceOrigin(
    source::Union{AbstractString, Symbol},
    line::Integer = 0;
    label::Union{Nothing, Symbol} = nothing,
) = SourceOrigin(String(source), Int(line), label)

const _NO_SOURCE_ORIGIN = SourceOrigin("", 0, nothing)

"""
    LocalLaw

The sole cold program declaration: an ordered, nonempty tuple of semantic
`Stage` values and the one exact `ParameterSchema` they reference.  Neither
storage, routing arrays, topology records, nor execution policy belongs here.
"""
struct LocalLaw{Stages<:Tuple,Parameters}
    stages::Stages
    parameters::Parameters

    function LocalLaw(
            ::_ConstructionToken,
            stages::Stages,
            parameters::Parameters,
        ) where {Stages<:Tuple,Parameters}
        isempty(stages) && throw(LocalMathValidationError(
            "a LocalLaw program requires at least one Stage";
            stage = :construct, contract = :program_stages,
        ))
        all(stage -> stage isa Stage, stages) || throw(LocalMathValidationError(
            "LocalLaw stages must be closed Stage values";
            stage = :construct, contract = :program_stages,
            expected = :stage_tuple, actual = map(typeof, stages),
        ))
        parameters isa ParameterSchema || throw(LocalMathValidationError(
            "LocalLaw parameters must use the one ParameterSchema authority";
            stage = :construct, contract = :program_parameters,
            expected = ParameterSchema, actual = Parameters,
        ))
        _validate_program_parameter_schema(stages, parameters)
        return new{Stages,Parameters}(stages, parameters)
    end

    function LocalLaw(stages::Stages, parameters::Parameters) where {
            Stages<:Tuple,Parameters,
        }
        return LocalLaw(_CONSTRUCTION_TOKEN, stages, parameters)
    end
end

function _parameter_declarations(stage)
    declarations = stage.evaluator.parameters
    if stage.control.prefix isa _ParameterPrefix
        declarations = (declarations..., stage.control.prefix.parameter)
    end
    if stage.control.gate isa _ParameterGate
        declarations = (declarations..., stage.control.gate.parameter)
    end
    return declarations
end

_same_parameter_declaration(left, right) =
    typeof(left) === typeof(right) && left.name === right.name &&
    left.bounds == right.bounds

function _parameter_schema_from_stages(stages::Tuple)
    declarations = Tuple(
        declaration for stage in stages
        for declaration in _parameter_declarations(stage)
    )
    return _merge_parameter_schemas(Tuple(
        ParameterSchema(declaration) for declaration in declarations
    ))
end

function _validate_program_parameter_schema(stages::Tuple, schema)
    expected = _parameter_schema_from_stages(stages)
    previous = 0
    for declaration in expected.declarations
        position = findfirst(candidate -> candidate.name === declaration.name,
            schema.declarations)
        position === nothing && throw(LocalMathValidationError(
            "a Stage parameter reference is absent from the program ParameterSchema";
            stage = :construct, contract = :program_parameter_coverage,
            expected = declaration, actual = schema.declarations,
        ))
        _same_parameter_declaration(schema.declarations[position], declaration) ||
            throw(LocalMathValidationError(
                "a Stage parameter reference disagrees with its program ParameterSchema declaration";
                stage = :construct, contract = :program_parameter_schema,
                expected = declaration, actual = schema.declarations[position],
            ))
        position > previous || throw(LocalMathValidationError(
            "Stage parameter references must retain first scientific declaration order in the program ParameterSchema";
            stage = :construct, contract = :program_parameter_order,
            expected = expected.declarations, actual = schema.declarations,
        ))
        previous = position
    end
    return nothing
end

function LocalLaw(stage; parameters = nothing)
    stage isa Stage || throw(LocalMathValidationError(
        "LocalLaw accepts one semantic Stage";
        stage = :construct, contract = :local_law_stage,
        expected = Stage, actual = typeof(stage),
    ))
    inferred = _parameter_schema_from_stages((stage,))
    schema = parameters === nothing ? inferred : parameters
    return LocalLaw((stage,), schema)
end

"""
    sequence(works::LocalLaw...)

Concatenate scientific stages and merge their one cold schemas in first
declaration order.  This is value composition only: it adds no scheduler,
topology bundle, compatibility operation, or execution route.
"""
function sequence(works::LocalLaw...)
    isempty(works) && throw(LocalMathValidationError(
        "a LocalLaw sequence requires at least one program";
        stage = :construct, contract = :program_sequence,
    ))
    stages = Tuple(stage for work in works for stage in work.stages)
    parameters = _merge_parameter_schemas(Tuple(
        work.parameters for work in works
    ))
    return LocalLaw(stages, parameters)
end

sequence(works::Tuple{Vararg{LocalLaw}}) = sequence(works...)

function _work_source_origin(work::LocalLaw, stage::Union{Nothing, Int})
    stage === nothing && return _NO_SOURCE_ORIGIN
    index = stage
    1 <= index <= length(work.stages) || return _NO_SOURCE_ORIGIN
    return work.stages[index].origin
end

function _with_work_source_origin(
        error,
        work::LocalLaw,
        lifecycle::Symbol,
        contract::Symbol;
        stage::Union{Nothing, Int} = nothing,
    )
    stage_index = stage === nothing ? _validation_stage_index(error) : stage
    return _with_source_origin(
        error,
        _work_source_origin(work, stage_index),
        lifecycle,
        contract,
    )
end

"""
    Plan

Reusable result of planning, owning the one validated bound program, backend,
and lowering. Inspection derives cold facts from those authorities; concrete
storage and workspace remain owned by `PreparedPlan`.
"""
struct Plan{Bound,Backend,Lowering}
    bound::Bound
    backend::Backend
    lowering::Lowering

    function Plan(
            ::_ConstructionToken,
            bound::Bound,
            backend::Backend,
            lowering::Lowering,
        ) where {Bound,Backend,Lowering}
        return new{Bound,Backend,Lowering}(bound, backend, lowering)
    end

    Plan(bound, backend, lowering) =
        Plan(_CONSTRUCTION_TOKEN, bound, backend, lowering)
end

abstract type _AbstractProviderLane end

# Fixed-layout host evidence. Callback values and compiler objects are cold;
# they must not parameterize the prepared executor.
struct _CallableAdmissionFact
    callback::Any
    signature::Type
    method::Method
    purpose::Symbol
    admission::Symbol
    return_type::Type
end

"""
    PreparedPlan

Concrete, task-owned execution state produced by [`prepare`](@ref). It binds a
`Plan` to storage, workspace, submission schema, provider lane, leases, and
failure state.
"""
mutable struct PreparedPlan{Q,L,R}
    # The plan is cold semantic/inspection evidence. Keeping its complete
    # heterogeneous program type in PreparedPlan made every warm method
    # specialize on that cold graph even though execution uses only `runtime`.
    const plan::Plan
    # Workspace is a cold ownership root. Its heterogeneous tree must remain
    # alive, but its shape is not an execution specialization dimension.
    const workspace::Any
    const submission_schema::Q
    const lane::L
    const runtime::R
    const workspace_ownership::Symbol
    const owner::Task
    submitted::UInt64
    drained::UInt64
    const leases::Vector{Any}
    const lease_generations::Vector{UInt64}
    next_lease::Int
    outstanding::Int
    const dependency_arity::Int
    poisoned::Bool
    poison_reason::Any

    function PreparedPlan(
            ::_ConstructionToken,
            plan::P,
            workspace::W,
            submission_schema::Q,
            lane::L,
            runtime::R,
            workspace_ownership::Symbol,
            owner::Task,
            submitted::UInt64,
            drained::UInt64,
            leases::Vector{Any},
            lease_generations::Vector{UInt64},
            next_lease::Int,
            outstanding::Int,
            dependency_arity::Int,
            poisoned::Bool,
            poison_reason,
        ) where {P<:Plan,W,Q,L,R}
        return new{Q,L,R}(
            plan,
            workspace,
            submission_schema,
            lane,
            runtime,
            workspace_ownership,
            owner,
            submitted,
            drained,
            leases,
            lease_generations,
            next_lease,
            outstanding,
            dependency_arity,
            poisoned,
            poison_reason,
        )
    end
end

"""
    ExecutionReceipt

Logical execution receipt returned by [`execute!`](@ref). Physical waiting remains
cumulative within a KernelAbstractions provider scope, while settlement,
failure caching, and lease release belong to the exact requested receipt.
[`waitall`](@ref) groups receipts by provider scope and synchronizes each scope
at most once.
"""
const _EXECUTION_RECEIPT_PENDING = UInt8(0)
const _EXECUTION_RECEIPT_SUCCESS = UInt8(1)
const _EXECUTION_RECEIPT_SEMANTIC_FAILURE = UInt8(2)
const _EXECUTION_RECEIPT_DEPENDENCY_FAILURE = UInt8(3)
const _EXECUTION_RECEIPT_PROVIDER_FAILURE = UInt8(4)

"""Logical asynchronous result of `execute!`; settle it with `wait`."""
mutable struct ExecutionReceipt
    const prepared::PreparedPlan
    const serial::UInt64
    const scope_ordinal::UInt64
    const lease_index::Int32
    const lease_generation::UInt64
    const dependencies::Tuple
    const dependency_join_count::Int32
    state::UInt8
    failure::Any

    function ExecutionReceipt(
            ::_ConstructionToken, prepared::PreparedPlan, serial::UInt64,
            scope_ordinal::UInt64, lease_index::Int32,
            lease_generation::UInt64, dependencies::Tuple,
            dependency_join_count::Int32,
        )
        return new(prepared, serial, scope_ordinal, lease_index,
            lease_generation, dependencies, dependency_join_count,
            _EXECUTION_RECEIPT_PENDING, nothing)
    end
end

struct _StaticScalarLease end
const _STATIC_SCALAR_LEASE = _StaticScalarLease()

struct _Emission{T}
    value::T
end

struct _ConditionalEmission{T}
    value::T
    when::Bool
end

struct _Candidate{R, T}
    rank::R
    value::T
end

struct _ConditionalCandidate{R, T}
    rank::R
    value::T
    when::Bool
end


"""
    LocalMathValidationError

Exception raised when a `LocalLaw`, topology, binding, workspace, submission,
or selected backend profile violates a centrally validated contract. Structured
diagnostic fields name the lifecycle `stage`, rejected `contract`, optional
`port`/`binding`/`workspace_leaf`, `expected` and `actual` facts, and an
optional recovery `hint` and source `origin`. Nonapplicable fields are
`nothing`.
"""
struct LocalMathValidationError <: Exception
    message::String
    stage::Union{Nothing, Symbol}
    contract::Union{Nothing, Symbol}
    port::Union{Nothing, Symbol}
    binding::Union{Nothing, Symbol}
    workspace_leaf::Union{Nothing, Symbol}
    expected::Any
    actual::Any
    hint::Union{Nothing, String}
    origin::Union{Nothing, SourceOrigin}
end

function LocalMathValidationError(
        message::AbstractString;
        stage::Union{Nothing, Symbol} = nothing,
        contract::Union{Nothing, Symbol} = nothing,
        port::Union{Nothing, Symbol} = nothing,
        binding::Union{Nothing, Symbol} = nothing,
        workspace_leaf::Union{Nothing, Symbol} = nothing,
        expected = nothing,
        actual = nothing,
        hint::Union{Nothing, AbstractString} = nothing,
        origin::Union{Nothing, SourceOrigin} = nothing,
    )
    return LocalMathValidationError(
        String(message),
        stage,
        contract,
        port,
        binding,
        workspace_leaf,
        expected,
        actual,
        hint === nothing ? nothing : String(hint),
        origin,
    )
end

function _show_validation_value(io::IO, value)
    context = IOContext(io, :compact => true, :limit => true)
    if value isa Exception
        showerror(context, value)
    elseif value isa AbstractString
        print(context, value)
    else
        show(context, value)
    end
    return nothing
end

function _show_validation_field(io::IO, name::AbstractString, value)
    value === nothing && return nothing
    print(io, "\n  ", name, ": ")
    _show_validation_value(io, value)
    return nothing
end

function _show_validation_origin(io::IO, origin::SourceOrigin)
    print(io, isempty(origin.source) ? "unknown source" : origin.source)
    origin.line > 0 && print(io, ":", origin.line)
    if origin.label !== nothing
        print(io, " (label: ")
        show(io, origin.label)
        print(io, ")")
    end
    return nothing
end

function Base.showerror(io::IO, error::LocalMathValidationError)
    print(io, "LocalMath validation failed: ", error.message)
    _show_validation_field(io, "lifecycle", error.stage)
    _show_validation_field(io, "contract", error.contract)
    if error.origin !== nothing
        print(io, "\n  source: ")
        _show_validation_origin(io, error.origin)
    end
    _show_validation_field(io, "port", error.port)
    _show_validation_field(io, "binding", error.binding)
    _show_validation_field(io, "workspace", error.workspace_leaf)
    _show_validation_field(io, "expected", error.expected)
    _show_validation_field(io, "actual", error.actual)
    _show_validation_field(io, "hint", error.hint)
    return nothing
end

_has_source_origin(origin::SourceOrigin) =
    !isempty(origin.source) || origin.line > 0 || origin.label !== nothing

function _with_source_origin(
        error::LocalMathValidationError,
        origin::SourceOrigin,
        _stage::Symbol,
        _contract::Symbol,
    )
    !_has_source_origin(origin) && return error
    error.origin === nothing || return error
    return LocalMathValidationError(
        error.message;
        stage = error.stage,
        contract = error.contract,
        port = error.port,
        binding = error.binding,
        workspace_leaf = error.workspace_leaf,
        expected = error.expected,
        actual = error.actual,
        hint = error.hint,
        origin,
    )
end

function _with_source_origin(
        error,
        origin::SourceOrigin,
        stage::Symbol,
        contract::Symbol,
    )
    !_has_source_origin(origin) && return error
    location = if isempty(origin.source)
        "authored local calculation"
    elseif origin.line > 0
        "local calculation at $(origin.source):$(origin.line)"
    else
        "local calculation at $(origin.source)"
    end
    return LocalMathValidationError(
        "$location failed during $stage";
        stage,
        contract,
        actual = error,
        origin,
    )
end

function _validation_stage_index(error)
    error isa LocalMathValidationError || return nothing
    actual = error.actual
    actual isa NamedTuple && hasproperty(actual, :stage) || return nothing
    stage = getproperty(actual, :stage)
    return stage isa Integer ? Int(stage) : nothing
end

function _checked_int_product(left::Integer, right::Integer, purpose)
    try
        return Base.Checked.checked_mul(Int(left), Int(right))
    catch error
        error isa OverflowError || rethrow()
        throw(LocalMathValidationError(
            "$purpose exceeds host Int capacity";
            contract = :integer_capacity,
            expected = (typemin(Int), typemax(Int)),
            actual = (left, right, operation = :multiply),
        ))
    end
end

function _checked_int_sum(left::Integer, right::Integer, purpose)
    try
        return Base.Checked.checked_add(Int(left), Int(right))
    catch error
        error isa OverflowError || rethrow()
        throw(LocalMathValidationError(
            "$purpose exceeds host Int capacity";
            contract = :integer_capacity,
            expected = (typemin(Int), typemax(Int)),
            actual = (left, right, operation = :add),
        ))
    end
end

function _checked_int32_count(
        value::Integer,
        purpose;
        terminal::Bool = false,
        stage::Symbol = :plan,
    )
    upper = terminal ? Int(typemax(Int32)) - 1 : Int(typemax(Int32))
    0 <= value <= upper || throw(LocalMathValidationError(
        "$purpose exceeds the bounded Int32 kernel ABI";
        stage, contract = :kernel_abi_capacity,
        expected = 0:upper, actual = value,
    ))
    return Int(value)
end

_qualified_rank_shape(::Type{T}) where {T} = T in (Int32, UInt32)
@generated function _qualified_rank_shape(::Type{T}) where {T <: Tuple}
    fields = T.parameters
    qualified = 2 <= length(fields) <= 12 &&
        all(field -> field in (Int32, UInt32), fields) &&
        isbitstype(T) && sizeof(T) <= 48 && Base.datatype_alignment(T) <= 4
    return qualified ? :(true) : :(false)
end

@inline _rank_compare(left::T, right::T) where {T <: Union{Int32, UInt32}} =
    left < right ? Int32(-1) : left > right ? Int32(1) : Int32(0)

@inline @generated function _rank_compare(left::T, right::T) where {T <: Tuple}
    expressions = Expr[]
    for index in 1:fieldcount(T)
        push!(expressions, quote
            local comparison = _rank_compare(
                getfield(left, $index), getfield(right, $index)
            )
            comparison == 0 || return comparison
        end)
    end
    return Expr(:block, expressions..., :(Int32(0)))
end

@inline _rank_equal(left, right) = _rank_compare(left, right) == 0
@inline _rank_better(left, right, ::Val{:min}) =
    _rank_compare(left, right) < 0
@inline _rank_better(left, right, ::Val{:max}) =
    _rank_compare(left, right) > 0
@inline _rank_in_bounds(rank, lower, upper) =
    _rank_compare(lower, rank) <= 0 && _rank_compare(rank, upper) <= 0

Base.propertynames(plan::Plan, private::Bool = false) = private ?
    fieldnames(typeof(plan)) : (:bound, :backend)
Base.propertynames(prepared::PreparedPlan, private::Bool = false) = private ?
    fieldnames(typeof(prepared)) :
    (:plan, :workspace, :submission_schema)
Base.propertynames(receipt::ExecutionReceipt, private::Bool = false) = private ?
    fieldnames(typeof(receipt)) : (:serial,)

_array_backend(array) = KernelAbstractions.get_backend(array)

function _array_backend(array::StructArrays.StructArray)
    arrays = values(StructArrays.components(array))
    isempty(arrays) && throw(LocalMathValidationError(
        "a StructArray binding must contain at least one physical component"
    ))
    backends = map(arrays) do component
        _array_backend(component)
    end
    all(==(first(backends)), backends) || throw(LocalMathValidationError(
        "StructArray components span multiple backends"
    ))
    return first(backends)
end

function _array_device_identity(array)
    backend = _array_backend(array)
    device = backend isa KernelAbstractions.CPU ?
        KernelAbstractions.device(backend) :
        _backend_device_token(backend)
    return (
        backend = typeof(backend),
        device_token_type = typeof(device),
        device_token = isbits(device) ? device : objectid(device),
        scope = :backend_device_context,
    )
end

function _array_device_identity(array::StructArrays.StructArray)
    arrays = values(StructArrays.components(array))
    isempty(arrays) && throw(LocalMathValidationError(
        "a StructArray binding must contain at least one physical component"
    ))
    identities = map(arrays) do component
        _array_device_identity(
            component,
        )
    end
    all(==(first(identities)), identities) || throw(
        LocalMathValidationError(
            "StructArray components span multiple devices or contexts"
        )
    )
    return first(identities)
end

function _backend_root_array(array, backend)
    backend isa KernelAbstractions.CPU && return array isa Array
    return array isa AbstractArray &&
        KernelAbstractions.functional(backend) === true &&
        _array_backend(array) == backend
end

function _frozen_array_reference_graph(value)
    value isa Union{Symbol, Module, Type, String} && return true
    isbitstype(typeof(value)) && return true
    value isa Tuple && return all(
        item -> _frozen_array_reference_graph(item), value
    )
    value isa NamedTuple && return all(
        item -> _frozen_array_reference_graph(item),
        values(value),
    )
    value isa AbstractArray && return _stable_array_representation(value)
    ismutabletype(typeof(value)) && return false
    return all(
        index -> _frozen_array_reference_graph(getfield(value, index)
        ),
        1:fieldcount(typeof(value)),
    )
end

function _stable_array_representation(array)
    array isa BitArray && return false
    if array isa StructArrays.StructArray
        return all(
            component -> _stable_array_representation(component),
            values(StructArrays.components(array)),
        )
    end
    backend = _array_backend(array)
    _backend_root_array(
        array,
        backend,
    ) && return true
    ismutabletype(typeof(array)) && return false
    return all(
        index -> _frozen_array_reference_graph(
            getfield(array, index),
        ),
        1:fieldcount(typeof(array)),
    )
end

function _array_address_space(array)
    _stable_array_representation(array) || return :unknown
    return :global
end

function _require_stable_array_representation(array, stage, role)
    _stable_array_representation(array) || throw(
        LocalMathValidationError(
            "$role uses an unqualified retargetable array representation";
            stage,
            contract = :stable_array_representation,
            expected = :backend_owned_stable_array,
            actual = typeof(array),
        )
    )
    _array_address_space(array) === :global || throw(
        LocalMathValidationError(
            "$role is not qualified for global-memory kernel access";
            stage,
            contract = :array_address_space,
            expected = :global,
            actual = _array_address_space(array),
        )
    )
    return nothing
end

_array_strides(array) = strides(array)
_array_strides(array::StructArrays.StructArray) =
    map(_array_strides, StructArrays.components(array))
