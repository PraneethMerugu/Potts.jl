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
    LocalWork

Immutable declaration of a bounded local operation: its item domain, logical
reads, named outputs, active selection, and operation descriptor. Construct it
with [`localwork`](@ref) or [`sequence`](@ref).
"""
struct LocalWork{I, R, O, A, F}
    items::I
    reads::R
    outputs::O
    active::A
    operation::F

    function LocalWork(
            ::_ConstructionToken,
            items::I,
            reads::R,
            outputs::O,
            active::A,
            operation::F,
        ) where {I, R, O, A, F}
        return new{I, R, O, A, F}(
            items, reads, outputs, active, operation
        )
    end
end

struct _SequenceOperation{W}
    works::W
end

struct _SequenceLowering{L}
    stages::L
end

struct _SingleOutputOperation{Name, F}
    operation::F
end

@inline function (operation::_SingleOutputOperation{Name})(args...) where {Name}
    return NamedTuple{(Name,)}((operation.operation(args...),))
end

"""
    WorkPlan

Reusable result of [`plan`](@ref), owning validated topology, backend, lowering,
and inspectable evidence but no concrete storage or workspace.
"""
struct WorkPlan{W, T, B, L, E}
    work::W
    topology::T
    backend::B
    lowering::L
    evidence::E

    function WorkPlan(
            ::_ConstructionToken,
            work::W,
            topology::T,
            backend::B,
            lowering::L,
            evidence::E,
        ) where {W, T, B, L, E}
        return new{W, T, B, L, E}(
            work, topology, backend, lowering, evidence
        )
    end
end

abstract type _AbstractProviderLane end

"""
    PreparedWork

Concrete, task-owned execution state produced by [`prepare`](@ref). It binds a
`WorkPlan` to storage, workspace, submission schema, provider lane, leases, and
failure state.
"""
mutable struct PreparedWork{P, S, W, Q, L, R, N, A, SI, WI, WA, TC, OC}
    const workplan::P
    const storage::S
    const workspace::W
    const submission_schema::Q
    const lane::L
    const runtime::R
    const binding_names::N
    const binding_access::A
    const static_identities::SI
    const workspace_identities::WI
    const workspace_arrays::WA
    const workspace_ownership::Symbol
    const trusted_callbacks::TC
    const operation_callbacks::OC
    trusted_world::UInt
    operation_world::UInt
    submission_signature::Any
    submission_method::Any
    binding_signature::Any
    binding_method::Any
    execution_signature::Any
    execution_method::Any
    const append_lock::ReentrantLock
    const owner::Task
    submitted::UInt64
    drained::UInt64
    const leases::Vector{Any}
    poisoned::Bool
    poison_reason::Any

    function PreparedWork(
            ::_ConstructionToken,
            workplan::P,
            storage::S,
            workspace::W,
            submission_schema::Q,
            lane::L,
            runtime::R,
            binding_names::N,
            binding_access::A,
            static_identities::SI,
            workspace_identities::WI,
            workspace_arrays::WA,
            workspace_ownership::Symbol,
            trusted_callbacks::TC,
            operation_callbacks::OC,
            trusted_world::UInt,
            operation_world::UInt,
            submission_signature,
            submission_method,
            binding_signature,
            binding_method,
            execution_signature,
            execution_method,
            append_lock::ReentrantLock,
            owner::Task,
            submitted::UInt64,
            drained::UInt64,
            leases::Vector{Any},
            poisoned::Bool,
            poison_reason,
        ) where {P, S, W, Q, L, R, N, A, SI, WI, WA, TC, OC}
        return new{P, S, W, Q, L, R, N, A, SI, WI, WA, TC, OC}(
            workplan,
            storage,
            workspace,
            submission_schema,
            lane,
            runtime,
            binding_names,
            binding_access,
            static_identities,
            workspace_identities,
            workspace_arrays,
            workspace_ownership,
            trusted_callbacks,
            operation_callbacks,
            trusted_world,
            operation_world,
            submission_signature,
            submission_method,
            binding_signature,
            binding_method,
            execution_signature,
            execution_method,
            append_lock,
            owner,
            submitted,
            drained,
            leases,
            poisoned,
            poison_reason,
        )
    end
end

"""
    WorkEvent

Thin cumulative lane-tail receipt returned by [`run!`](@ref). `wait(event)`
performs the provider's portable cumulative wait and releases the completed
submitted prefix.
"""
struct WorkEvent{P}
    prepared::P
    serial::UInt64

    function WorkEvent(
            ::_ConstructionToken, prepared::P, serial::UInt64
        ) where {P}
        return new{P}(prepared, serial)
    end
end

struct _ValueSlot{T, B}
    bounds::B
end

struct _StorageSlot{T, N, S, R, A, B, D, C}
    size::S
    strides::R
    access::A
    backend_type::B
    device_identity::D
    array_type::Type{C}
end

struct _MaskedEmission{V, M}
    values::V
    mask::M
end

abstract type _AbstractOutputDeclaration end

struct _IndependentOutput{T, K, R, C} <: _AbstractOutputDeclaration end

struct _CombinationLaw{M, F, T}
    operation::F
    identity::T
end

struct _CombinedOutput{T, K, R, L} <: _AbstractOutputDeclaration
    combine::L
end

struct _GenericResolvedOutput{T, K, R, Q, O, I} <:
       _AbstractOutputDeclaration
    empty::T
    lower::Q
    upper::Q
end

function Base.getproperty(
        output::_IndependentOutput{T, K, R, C}, name::Symbol
    ) where {T, K, R, C}
    name === :route && return R
    name === :value_type && return T
    return getfield(output, name)
end


function Base.getproperty(
        output::_CombinedOutput{T, K, R}, name::Symbol
    ) where {T, K, R}
    name === :route && return R
    name === :value_type && return T
    return getfield(output, name)
end


function Base.getproperty(
        output::_GenericResolvedOutput{T, K, R, Q, O, I}, name::Symbol
    ) where {T, K, R, Q, O, I}
    name === :route && return R
    name === :value_type && return T
    name === :rank && return (
        type = Q,
        order = O,
        lower = getfield(output, :lower),
        upper = getfield(output, :upper),
    )
    name === :tie_break && return (type = I, order = :min)
    return getfield(output, name)
end

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
    LocalWorkValidationError

Exception raised when a `LocalWork`, topology, binding, workspace, submission,
or selected backend profile violates a centrally validated contract. Stable
diagnostic fields name the lifecycle `stage`, rejected `contract`, optional
`port`/`binding`/`workspace_leaf`, `expected` and `actual` facts, and an
optional recovery `hint`. Nonapplicable fields are `nothing`.
"""
struct LocalWorkValidationError <: Exception
    message::String
    stage::Union{Nothing, Symbol}
    contract::Union{Nothing, Symbol}
    port::Union{Nothing, Symbol}
    binding::Union{Nothing, Symbol}
    workspace_leaf::Union{Nothing, Symbol}
    expected::Any
    actual::Any
    hint::Union{Nothing, String}
end

function LocalWorkValidationError(
        message::AbstractString;
        stage::Union{Nothing, Symbol} = nothing,
        contract::Union{Nothing, Symbol} = nothing,
        port::Union{Nothing, Symbol} = nothing,
        binding::Union{Nothing, Symbol} = nothing,
        workspace_leaf::Union{Nothing, Symbol} = nothing,
        expected = nothing,
        actual = nothing,
        hint::Union{Nothing, AbstractString} = nothing,
    )
    return LocalWorkValidationError(
        String(message),
        stage,
        contract,
        port,
        binding,
        workspace_leaf,
        expected,
        actual,
        hint === nothing ? nothing : String(hint),
    )
end

Base.showerror(io::IO, error::LocalWorkValidationError) =
    begin
        print(io, error.message)
        error.hint === nothing || print(io, ". Hint: ", error.hint)
    end

function _checked_int_product(left::Integer, right::Integer, purpose)
    try
        return Base.Checked.checked_mul(Int(left), Int(right))
    catch error
        error isa OverflowError || rethrow()
        throw(LocalWorkValidationError(
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
        throw(LocalWorkValidationError(
            "$purpose exceeds host Int capacity";
            contract = :integer_capacity,
            expected = (typemin(Int), typemax(Int)),
            actual = (left, right, operation = :add),
        ))
    end
end

function _checked_int32_count(value::Integer, purpose; terminal::Bool = false)
    upper = terminal ? Int(typemax(Int32)) - 1 : Int(typemax(Int32))
    0 <= value <= upper || throw(LocalWorkValidationError(
        "$purpose exceeds the bounded Int32 kernel ABI";
        contract = :kernel_abi_capacity,
        expected = 0:upper, actual = value,
    ))
    return Int(value)
end

"""
    resolved(...)

Declare an output whose competing contributions are selected by an explicit,
total rank and canonical semantic tie-break. Only centrally admitted bounded
profiles can be planned and executed.
"""
function resolved end

"""
    independent(route; value_type, maximum=1, coverage=:all)

Declare fixed-route output with no competing writer. Full coverage requires
exactly one unconditional writer for every destination; partial coverage
preserves destinations whose fixed lane emits nothing.
"""
function independent(
        route::Symbol;
        value_type::Type{T},
        maximum::Integer = 1,
        coverage::Symbol = :all,
    ) where {T}
    isempty(String(route)) && throw(ArgumentError(
        "an independent route name must be nonempty"
    ))
    isconcretetype(T) && isbitstype(T) || throw(ArgumentError(
        "an independent output requires a concrete isbits value type"
    ))
    1 <= maximum <= typemax(Int32) || throw(ArgumentError(
        "independent maximum emissions must be a positive Int32 bound"
    ))
    coverage in (:all, :partial) || throw(ArgumentError(
        "independent coverage must be :all or :partial"
    ))
    return _IndependentOutput{T, Int(maximum), route, coverage}()
end

function _combination_law(mode::Symbol, operation, identity::T) where {T}
    isconcretetype(T) && isbitstype(T) || throw(ArgumentError(
        "a combination identity must have a concrete isbits type"
    ))
    operation isa Function || isbitstype(typeof(operation)) || throw(
        ArgumentError("a combination operation must be concrete")
    )
    return _CombinationLaw{mode, typeof(operation), T}(
        operation, identity
    )
end

"""
    deterministic(operation, identity)

Qualify a combination declaration for canonical semantic-order folding.
Executable operation/type profiles are still selected centrally.
"""
deterministic(operation, identity) =
    _combination_law(:deterministic, operation, identity)

"""
    fast(operation, identity)

Declare deliberately relaxed combination semantics. The declaration does not
self-authorize atomics or a backend; central planning must qualify the exact
backend, type, operation, and address space.
"""
fast(operation, identity) = _combination_law(:fast, operation, identity)

"""
    combined(route; value_type, maximum=1, combine)

Declare fixed-route contributions combined under an explicit deterministic or
fast law. Passing a bare operation such as `+` is intentionally rejected.
"""
function combined(
        route::Symbol;
        value_type::Type{T},
        maximum::Integer = 1,
        combine,
    ) where {T}
    isempty(String(route)) && throw(ArgumentError(
        "a combined route name must be nonempty"
    ))
    isconcretetype(T) && isbitstype(T) || throw(ArgumentError(
        "a combined output requires a concrete isbits value type"
    ))
    1 <= maximum <= typemax(Int32) || throw(ArgumentError(
        "combined maximum emissions must be a positive Int32 bound"
    ))
    combine isa _CombinationLaw || throw(ArgumentError(
        "combined output requires deterministic(...) or fast(...); a bare operation is ambiguous"
    ))
    typeof(combine.identity) === T || throw(ArgumentError(
        "combined identity type must equal the declared value type"
    ))
    return _CombinedOutput{T, Int(maximum), route, typeof(combine)}(combine)
end

"""
    emit(value[, when])

Return one fixed independent/combined output lane. Omitting `when` is an
unconditional emission; false conditional lanes emit nothing.
"""
emit(value) = _Emission(value)
emit(value, when::Bool) = _ConditionalEmission(value, when)

"""
    candidate(rank, value[, when])

Return one fixed resolved-candidate lane. Destination and canonical semantic
identity are owned by validated topology, not this dynamic value.
"""
candidate(rank, value) = _Candidate(rank, value)
candidate(rank, value, when::Bool) =
    _ConditionalCandidate(rank, value, when)

"""
    masked(values, mask)

Pair fixed-lane emission values with an eager mask. A false lane emits
nothing; it is not an empty or default contribution.
"""
masked(values, mask) = _MaskedEmission(values, mask)

function _canonical_declaration_tuple(value::NamedTuple)
    names = Tuple(sort!(collect(keys(value)); by = String))
    return NamedTuple{names}(
        ntuple(index -> getproperty(value, names[index]), length(names))
    )
end

"""
    localwork(operation, items; read=(;), outputs=(;), active=nothing)

Declare bounded local work over `items`. Logical reads and named outputs are
canonicalized by name; planning, storage binding, and execution occur later.
"""
function localwork(
        operation,
        items;
        read = (;),
        outputs = (;),
        active = nothing,
    )
    read isa NamedTuple || throw(ArgumentError(
        "LocalWork reads must be a named tuple"
    ))
    outputs isa NamedTuple || throw(ArgumentError(
        "LocalWork outputs must be a named tuple"
    ))
    items isa AbstractUnitRange{<:Integer} &&
        first(items) == one(eltype(items)) &&
        step(items) == one(eltype(items)) || throw(ArgumentError(
            "LocalWork items must be a one-based unit integer range"
        ))
    all(name -> !isempty(String(name)), keys(read)) || throw(ArgumentError(
        "LocalWork read role names must be nonempty"
    ))
    all(value -> value isa Symbol, values(read)) || throw(ArgumentError(
        "LocalWork reads must map roles to logical binding names"
    ))
    isempty(outputs) && throw(ArgumentError(
        "LocalWork requires at least one named output"
    ))
    all(name -> !isempty(String(name)), keys(outputs)) ||
        throw(ArgumentError("LocalWork output names must be nonempty"))
    all(value -> value isa _AbstractOutputDeclaration, values(outputs)) ||
        throw(ArgumentError(
            "LocalWork outputs must be LocalWorksets output declarations"
        ))
    is_plain_data = operation isa Union{
        Number, Symbol, Char, AbstractString, Type, Nothing, Missing,
        Tuple, AbstractArray,
    }
    callable_object = isbitstype(typeof(operation)) &&
        !is_plain_data && !isempty(methods(operation))
    valid_operation = operation isa Function || (
        operation isa NamedTuple &&
        hasproperty(operation, :family) &&
        operation.family isa Symbol
    ) || callable_object
    valid_operation || throw(ArgumentError(
        "LocalWork operation must be a callable or a named family declaration"
    ))
    active === nothing || active isa Symbol || throw(ArgumentError(
        "LocalWork active selection must be nothing or a submission-slot name"
    ))
    return LocalWork(
        _CONSTRUCTION_TOKEN,
        items,
        _canonical_declaration_tuple(read),
        _canonical_declaration_tuple(outputs),
        active,
        operation,
    )
end

function _declared_item_count(work::LocalWork)
    if work.operation isa _SequenceOperation
        domains = work.items
        all(==(first(domains)), domains) || throw(ArgumentError(
            "ordered LocalWork stages require one item domain"
        ))
        return length(first(domains))
    end
    return length(work.items)
end

"""
    topology(work; epoch, routes, destination_counts, semantic_ids=(;))

Construct the canonical topology record for direct and buffered local work.
Only `item_count` is derived, from the declaration's one-based item domain;
the epoch, routes, per-output destination counts, and resolved semantic
identities remain explicit and are fully validated by [`plan`](@ref).
"""
function topology(
        work::LocalWork;
        epoch,
        routes::NamedTuple,
        destination_counts::NamedTuple,
        semantic_ids::NamedTuple = (;),
    )
    typeof(epoch) === UInt64 || throw(ArgumentError(
        "topology epoch must be exactly UInt64"
    ))
    return (;
        epoch,
        item_count = invoke(
            _declared_item_count,
            Tuple{LocalWork},
            work,
        ),
        routes,
        destination_counts,
        semantic_ids,
    )
end

localwork(operation; items, read = (;), outputs = (;), active = nothing) =
    localwork(operation, items; read, outputs, active)

"""
    localwork(operation, items, name => output; read=(;), active=nothing)

Concise single-output form. The local operation returns one `emit(...)` or
`candidate(...)` value directly; LocalWorksets preserves the explicit port
name by wrapping it into the same named-output declaration used by Level 2.

```julia
work = localwork(1:4, :result => independent(
    :route; value_type = Int32
); read = (source = :source,)) do item, reads, values
    emit(@inbounds reads.source[item] + Int32(1))
end
```
"""
function localwork(
        operation,
        items,
        output::Pair{Symbol, <: _AbstractOutputDeclaration};
        read = (;),
        active = nothing,
    )
    name, declaration = output
    isempty(String(name)) && throw(ArgumentError(
        "single-output LocalWork port name must be nonempty"
    ))
    wrapped = _SingleOutputOperation{name, typeof(operation)}(operation)
    return localwork(
        wrapped,
        items;
        read,
        outputs = NamedTuple{(name,)}((declaration,)),
        active,
    )
end

Base.propertynames(work::LocalWork, private::Bool = false) =
    fieldnames(typeof(work))
Base.propertynames(plan::WorkPlan, private::Bool = false) = private ?
    fieldnames(typeof(plan)) : (:work, :topology, :backend)
Base.propertynames(prepared::PreparedWork, private::Bool = false) = private ?
    fieldnames(typeof(prepared)) :
    (:workplan, :storage, :workspace, :submission_schema)
Base.propertynames(event::WorkEvent, private::Bool = false) = private ?
    fieldnames(typeof(event)) : (:serial,)

"""
    sequence(works::LocalWork...)

Declare ordered stages that share one admitted backend/lane. Stage visibility
uses provider program order; `sequence` does not insert an intermediate host
wait or create a scheduler.
"""
function sequence(works::LocalWork...)
    isempty(works) && throw(ArgumentError(
        "a LocalWork sequence requires at least one stage"
    ))
    return LocalWork(
        _CONSTRUCTION_TOKEN,
        map(work -> work.items, works),
        map(work -> work.reads, works),
        map(work -> work.outputs, works),
        map(work -> work.active, works),
        _SequenceOperation(works),
    )
end

sequence(works::Tuple{Vararg{LocalWork}}) = sequence(works...)

"""
    value_slot(T; bounds=nothing)

Declare a submission-time scalar with exact concrete isbits type `T` and
optional inclusive bounds.
"""
function value_slot(::Type{T}; bounds = nothing) where {T}
    isconcretetype(T) || throw(ArgumentError(
        "a value slot requires a concrete type"
    ))
    isbitstype(T) || throw(ArgumentError(
        "a value slot requires an isbits type"
    ))
    bounds === nothing || (
        bounds isa AbstractUnitRange{T} && !isempty(bounds)
    ) || throw(ArgumentError(
        "value-slot bounds must be a nonempty inclusive unit range of $T"
    ))
    return _ValueSlot{T, typeof(bounds)}(bounds)
end

function _array_device_identity(array)
    backend = KernelAbstractions.get_backend(array)
    signature = Tuple{KernelAbstractions.Backend}
    method = which(_backend_device_token, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the backend device-token identity is not package-owned"
    ))
    device = backend isa KernelAbstractions.CPU ?
        KernelAbstractions.device(backend) :
        invoke(_backend_device_token, signature, backend)
    return (
        backend = typeof(backend),
        device_token_type = typeof(device),
        device_token = isbits(device) ? device : objectid(device),
        scope = :reviewed_backend_device_context,
    )
end

"""
    storage_slot(template; access)

Declare submission-time storage using `template` to freeze element type,
dimensionality, shape, strides, backend, and device/context. `access` is
`:read`, `:write`, or `:readwrite` and participates in alias validation.
"""
function storage_slot(template; access::Symbol)
    access in (:read, :write, :readwrite) || throw(ArgumentError(
        "storage-slot access must be :read, :write, or :readwrite"
    ))
    element_type = eltype(template)
    isconcretetype(element_type) || throw(ArgumentError(
        "a storage slot requires a concrete element type"
    ))
    backend = KernelAbstractions.get_backend(template)
    return _StorageSlot{
        element_type,
        ndims(template),
        typeof(size(template)),
        typeof(strides(template)),
        Symbol,
        DataType,
        typeof(invoke(_array_device_identity, Tuple{Any}, template)),
        typeof(template),
    }(
        size(template),
        strides(template),
        access,
        typeof(backend),
        invoke(_array_device_identity, Tuple{Any}, template),
        typeof(template),
    )
end
