# Hardware-agnostic KernelAbstractions provider. Kernel launches are implicitly
# ordered by the backend; one KernelAbstractions.synchronize call is the only
# execution-visibility boundary. No native stream, queue, or event is exposed.

struct _KernelAbstractionsDeviceGetter end
@inline (::_KernelAbstractionsDeviceGetter)(backend) =
    KernelAbstractions.device(backend)

mutable struct _KernelAbstractionsScope{B, D, T, E, G}
    const backend::B
    const device::D
    const owner::T
    const environment::E
    const device_getter::G
    poisoned::Bool
    poison_reason::Any
    synchronizations::Int
    transfers::Int
    submitted_ordinal::UInt64
    settled_ordinal::UInt64
end

mutable struct _KernelAbstractionsLane{S} <: _AbstractProviderLane
    const scope::S
    waits::Int
    transfers::Int
end

const _KA_SCOPE_TLS_KEY = gensym(:LocalMathKAScopes)

_backend_device_getter(::KernelAbstractions.Backend) =
    _KernelAbstractionsDeviceGetter()

function _backend_device_token(backend::KernelAbstractions.Backend)
    return _backend_device_getter(backend)(backend)
end

function _backend_environment(backend::KernelAbstractions.Backend)
    backend_module = parentmodule(typeof(backend))
    package = Base.PkgId(backend_module)
    package_version = try
        Base.pkgversion(backend_module)
    catch
        nothing
    end
    device = KernelAbstractions.device(backend)
    return (
        julia = VERSION,
        kernelabstractions = Base.pkgversion(KernelAbstractions),
        atomix = Base.pkgversion(Atomix),
        adapt = Base.pkgversion(Adapt),
        staticarrays = Base.pkgversion(StaticArrays),
        structarrays = Base.pkgversion(StructArrays),
        backend_package_uuid = string(package.uuid),
        backend_package_version = package_version,
        backend_module = string(backend_module),
        backend_type = string(nameof(typeof(backend))),
        device_type = string(typeof(device)),
        device_value = repr(device),
        kernel = Sys.KERNEL,
        architecture = Sys.ARCH,
        machine = Sys.MACHINE,
        cpu = Sys.CPU_NAME,
        word_size = Sys.WORD_SIZE,
    )
end

function _make_provider_lane(
        backend::KernelAbstractions.Backend, storage
    )
    functional = KernelAbstractions.functional(backend)
    backend isa KernelAbstractions.CPU || functional === true ||
        throw(LocalMathValidationError(
            "the KernelAbstractions backend is not functional"
        ))
    environment = _backend_environment(
        backend,
    )
    task_storage = task_local_storage()
    scopes = get!(task_storage, _KA_SCOPE_TLS_KEY) do
        Dict{Any, Any}()
    end
    device_getter = _backend_device_getter(backend)
    scope_key = (typeof(backend), device_getter(backend))
    scope = get(scopes, scope_key, nothing)
    if scope === nothing
        scope = _KernelAbstractionsScope(
            backend,
            device_getter(backend),
            current_task(),
            environment,
            device_getter,
            false,
            nothing,
            0,
            0,
            UInt64(0),
            UInt64(0),
        )
        scopes[scope_key] = scope
    else
        current_task() === scope.owner || throw(LocalMathValidationError(
            "the KernelAbstractions provider scope belongs to another task"
        ))
        scope.poisoned && throw(LocalMathValidationError(
            "the KernelAbstractions provider scope is poisoned"
        ))
    end
    return _KernelAbstractionsLane(scope, 0, 0)
end

_lane_provider(::_KernelAbstractionsLane) = :KernelAbstractions
_lane_device(lane::_KernelAbstractionsLane) = lane.scope.device
_lane_identity(lane::_KernelAbstractionsLane) = objectid(lane.scope)
_lane_wait_scope(::_KernelAbstractionsLane) = :backend_implicit_order_tail
_lane_transfer_law(::_KernelAbstractionsLane) = :same_owner_task_only
_lane_cumulative(::_KernelAbstractionsLane) = true
_lane_selective(::_KernelAbstractionsLane) = false
_lane_error_observation(::_KernelAbstractionsLane) = (
    synchronization = :kernelabstractions_backend_contract,
    asynchronous_failures = :backend_defined,
    failure_scope = :backend_owner_task,
)
_lane_wait_count(lane::_KernelAbstractionsLane) = lane.waits
_lane_scope_wait_count(lane::_KernelAbstractionsLane) =
    lane.scope.synchronizations
_lane_transfer_count(lane::_KernelAbstractionsLane) = lane.transfers
_lane_same_wait_scope(
    first::_KernelAbstractionsLane, second::_KernelAbstractionsLane
) = first.scope === second.scope
_lane_poisoned(lane::_KernelAbstractionsLane) = lane.scope.poisoned
_lane_poison_reason(lane::_KernelAbstractionsLane) = lane.scope.poison_reason
_lane_scope_ordinal(lane::_KernelAbstractionsLane) =
    lane.scope.submitted_ordinal
_lane_settled_ordinal(lane::_KernelAbstractionsLane) =
    lane.scope.settled_ordinal
function _next_lane_ordinal!(lane::_KernelAbstractionsLane)
    lane.scope.submitted_ordinal += UInt64(1)
    return lane.scope.submitted_ordinal
end
function _mark_lane_settled!(lane::_KernelAbstractionsLane, ordinal::UInt64)
    lane.scope.settled_ordinal = max(lane.scope.settled_ordinal, ordinal)
    return lane.scope.settled_ordinal
end

function _poison_lane!(lane::_KernelAbstractionsLane, error)
    lane.scope.poisoned = true
    lane.scope.poison_reason = error
    return nothing
end

function _validate_lane_current!(lane::_KernelAbstractionsLane)
    scope = lane.scope
    current_task() === scope.owner || throw(LocalMathValidationError(
        "KernelAbstractions submission must use the preparing owner task"
    ))
    scope.poisoned && throw(scope.poison_reason)
    functional = KernelAbstractions.functional(scope.backend)
    scope.backend isa KernelAbstractions.CPU || functional === true ||
        throw(LocalMathValidationError(
            "the prepared KernelAbstractions backend is no longer functional"
        ))
    device = scope.device_getter(scope.backend)
    (device === scope.device || device == scope.device) ||
        throw(LocalMathValidationError(
            "the reviewed KernelAbstractions device changed after preparation"
        ))
    return nothing
end

function _validate_lane_current!(
        lane::_KernelAbstractionsLane{<:_KernelAbstractionsScope{
            <:KernelAbstractions.CPU,
        }},
    )
    scope = lane.scope
    current_task() === scope.owner || throw(LocalMathValidationError(
        "KernelAbstractions submission must use the preparing owner task"
    ))
    scope.poisoned && throw(scope.poison_reason)
    device = KernelAbstractions.device(scope.backend)
    (device === scope.device || device == scope.device) || throw(
        LocalMathValidationError(
            "the reviewed KernelAbstractions CPU device changed after preparation"
        )
    )
    return nothing
end

_validate_provider_capacity(::_KernelAbstractionsLane, evidence, capacity) =
    nothing

function _synchronize_lane_tail!(lane::_KernelAbstractionsLane)
    lane.waits += 1
    scope = lane.scope
    current_task() === scope.owner || throw(LocalMathValidationError(
        "KernelAbstractions tail drain must use the preparing owner task"
    ))
    scope.synchronizations += 1
    try
        KernelAbstractions.synchronize(scope.backend)
    catch error
        _poison_lane!(
            lane,
            error,
        )
        rethrow()
    end
    return nothing
end

function _settle_lane_tail!(lane::_KernelAbstractionsLane, statuses::Tuple)
    _validate_lane_current!(lane)
    lane.waits += 1
    scope = lane.scope
    scope.synchronizations += 1
    try
        if isempty(statuses)
            KernelAbstractions.synchronize(scope.backend)
        else
            # A host-visible device-to-host copy is the provider completion
            # operation. GPU providers must complete their queued prefix before
            # returning host data; issuing a second explicit synchronize would
            # duplicate that boundary (Metal and CUDA copies are blocking).
            _transfer_validation_statuses!(statuses)
            scope.transfers += 1
            lane.transfers += 1
        end
    catch error
        _poison_lane!(lane, error)
        rethrow()
    end
    return nothing
end

function _transfer_settled_validation_statuses!(
        lane::_KernelAbstractionsLane, statuses::Tuple)
    isempty(statuses) && return nothing
    try
        _transfer_validation_statuses!(statuses)
    catch error
        _poison_lane!(lane, error)
        rethrow()
    end
    lane.scope.transfers += 1
    lane.transfers += 1
    return nothing
end

_drain_lane_tail!(lane::_KernelAbstractionsLane) =
    _synchronize_lane_tail!(lane)

function _wait_lane!(lane::_KernelAbstractionsLane)
    _validate_lane_current!(lane)
    return _synchronize_lane_tail!(lane)
end

function _atomic_capability(
        backend::KernelAbstractions.Backend,
        type::Type,
        operation::Symbol,
        address_space::Symbol,
    )
    return address_space === :global && (
            type in (Int32, UInt32) && operation in (:min, :max, :add) ||
            type === Float32 && operation === :add
        )
end

function _value_capability(
        backend::KernelAbstractions.Backend,
        type::Type,
        operation::Symbol,
        address_space::Symbol,
    )
    return address_space === :global && (
        operation === :load &&
            (type in (Bool, Int16, Int32, UInt32, UInt8, UInt16, UInt64, Float32) ||
                backend isa KernelAbstractions.CPU && type === Float64) ||
        operation === :store &&
            (type in (Bool, Int16, Int32, UInt32, UInt8, UInt16, UInt64, Float32) ||
                backend isa KernelAbstractions.CPU && type === Float64)
    )
end

const _POINTWISE_FORBIDDEN_CALLS = (
    :setindex!, :unsafe_store!, :unsafe_load, :pointer, :pointer_from_objref,
    :atomic_add!, :atomic_sub!, :atomic_xchg!, :atomic_cas!, :ccall,
    :setfield!, :swapfield!, :modifyfield!, :replacefield!,
    :setglobal!, :swapglobal!, :modifyglobal!, :replaceglobal!,
    :memoryrefset!, :memoryrefswap!, :memoryrefmodify!, :memoryrefreplace!,
    :memoryrefsetonce!,
)
const _POINTWISE_FAILURE_ONLY_INVOKES = (
    Base.error, Base.throw_boundserror, Core.throw_inexacterror,
)
const _POINTWISE_PURE_UNARY_FLOAT_INVOKES = (
    Base.log, Base.sqrt, Base.cos,
)
const _POINTWISE_CALL_DEPTH_LIMIT = 32
const _POINTWISE_AND_INT = getglobal(getglobal(Core, :Intrinsics), :and_int)
const _POINTWISE_ALLOWED_LIBRARY_GLOBALS = (:emit, :candidate)
const _POINTWISE_LIBRARY_MODULE = @__MODULE__

function _pointwise_source_safe(value)
    if value isa GlobalRef
        value.mod in (Base, Core) && return true
        isdefined(value.mod, value.name) || return false
        binding = getglobal(value.mod, value.name)
        binding === _POINTWISE_LIBRARY_MODULE && return true
        # User helpers are admitted here only as source-level references. The
        # optimized typed IR below must inline them to the same closed set of
        # load-only primitives; an opaque user invoke remains rejected.
        binding isa Function && return true
        binding isa Type && parentmodule(binding) in (Base, Core) && return true
        binding isa DataType && isconcretetype(binding) && isbitstype(binding) &&
            _storage_free_type(binding) && return true
        return isconst(value.mod, value.name) && _storage_free_value(binding)
    end
    value isa Expr || return true
    value.head in (:foreigncall, :llvmcall, :cfunction) && return false
    if value.head in (:call, :invoke) && !isempty(value.args)
        callee_index = value.head === :invoke ? 2 : 1
        length(value.args) >= callee_index || return false
        callee = value.args[callee_index]
        callee isa GlobalRef &&
            callee.name in _POINTWISE_FORBIDDEN_CALLS && return false
    end
    return all(_pointwise_source_safe, value.args)
end

mutable struct _PointwiseIRAnalysis{P,Q}
    active::Base.IdSet{Any}
    memo::Base.IdDict{Any, Bool}
    source_policy::P
    typed_policy::Q
    typed_context::Any
end

_pointwise_typed_safe(value, info) = true
_PointwiseIRAnalysis(
    source_policy = _pointwise_source_safe,
    typed_policy = _pointwise_typed_safe,
) = _PointwiseIRAnalysis(
    Base.IdSet{Any}(), Base.IdDict{Any, Bool}(),
    source_policy, typed_policy, nothing,
)

function _pointwise_residual_invoke_safe(
        code_instance,
        binding,
        analysis::_PointwiseIRAnalysis,
        depth::Int,
    )
    depth < _POINTWISE_CALL_DEPTH_LIMIT || return false
    code_instance isa Core.CodeInstance || return false
    method_instance = code_instance.def
    method_instance isa Core.MethodInstance || return false
    haskey(analysis.memo, method_instance) &&
        return analysis.memo[method_instance]
    method_instance in analysis.active && return false
    spec = Base.unwrap_unionall(method_instance.specTypes)
    spec isa DataType && spec <: Tuple || return false
    parameters = spec.parameters
    length(parameters) >= 1 || return false
    signature = try
        Core.apply_type(Tuple, parameters[2:end]...)
    catch
        return false
    end
    selected = try
        which(binding, signature)
    catch
        return false
    end
    selected === method_instance.def || return false
    if any(candidate -> candidate === binding,
            _POINTWISE_PURE_UNARY_FLOAT_INVOKES)
        length(signature.parameters) == 1 || return false
        argument_type = only(signature.parameters)
        argument_type isa DataType &&
            argument_type <: AbstractFloat &&
            isconcretetype(argument_type) || return false
        return code_instance.rettype === argument_type
    end
    lowered = try
        code_lowered(binding, signature)
    catch
        return false
    end
    length(lowered) == 1 &&
        all(analysis.source_policy, first(lowered).code) || return false
    typed = try
        code_typed(binding, signature; optimize = true)
    catch
        return false
    end
    length(typed) == 1 || return false
    code = first(typed)
    info = code isa Pair ? first(code) : code[1]
    push!(analysis.active, method_instance)
    previous_context = analysis.typed_context
    analysis.typed_context = info
    qualified = all(
        statement -> _pointwise_ir_safe(statement, analysis, depth + 1),
        info.code,
    )
    analysis.typed_context = previous_context
    delete!(analysis.active, method_instance)
    analysis.memo[method_instance] = qualified
    return qualified
end

function _pointwise_method_instance_safe(
        method_instance::Core.MethodInstance,
        analysis::_PointwiseIRAnalysis,
        depth::Int,
    )
    # A non-inlined callable value has no global function binding to query.
    # Inspect its exact MethodInstance instead; the package's Julia 1.12
    # contract makes these two compiler entry points an explicit cold-boundary
    # dependency. Runtime execution never consumes this inspection result.
    depth < _POINTWISE_CALL_DEPTH_LIMIT || return false
    haskey(analysis.memo, method_instance) &&
        return analysis.memo[method_instance]
    method_instance in analysis.active && return false
    spec = Base.unwrap_unionall(method_instance.specTypes)
    spec isa DataType && spec <: Tuple || return false
    parameters = spec.parameters
    isempty(parameters) && return false
    callable_type = first(parameters)
    callable_type isa DataType && isconcretetype(callable_type) &&
        isbitstype(callable_type) && _storage_free_type(callable_type) ||
        return false
    lowered = try
        Base.uncompressed_ast(method_instance.def)
    catch
        return false
    end
    lowered isa Core.CodeInfo &&
        all(analysis.source_policy, lowered.code) || return false
    typed = try
        Base.code_typed_by_type(method_instance.specTypes; optimize = true)
    catch
        return false
    end
    length(typed) == 1 || return false
    code = first(typed)
    info = code isa Pair ? first(code) : code[1]
    push!(analysis.active, method_instance)
    previous_context = analysis.typed_context
    analysis.typed_context = info
    qualified = all(
        statement -> _pointwise_ir_safe(statement, analysis, depth + 1),
        info.code,
    )
    analysis.typed_context = previous_context
    delete!(analysis.active, method_instance)
    analysis.memo[method_instance] = qualified
    return qualified
end

_pointwise_ir_type(type) = type
_pointwise_ir_type(value::Core.Const) = typeof(value.val)

function _pointwise_operand_type(value, info)
    value isa QuoteNode && return typeof(value.value)
    value isa Core.Const && return typeof(value.val)
    info isa Core.CodeInfo || return Any
    if value isa Core.Argument || value isa Core.SlotNumber
        index = Int(getfield(value, :n))
        return 1 <= index <= length(info.slottypes) ?
            _pointwise_ir_type(info.slottypes[index]) : Any
    elseif value isa Core.SSAValue
        index = Int(getfield(value, :id))
        return 1 <= index <= length(info.ssavaluetypes) ?
            _pointwise_ir_type(info.ssavaluetypes[index]) : Any
    end
    return typeof(value)
end

function _pointwise_concrete_callable_invoke_safe(
        code_instance,
        callee,
        analysis::_PointwiseIRAnalysis,
        depth::Int,
    )
    code_instance isa Core.CodeInstance || return false
    method_instance = code_instance.def
    method_instance isa Core.MethodInstance || return false
    spec = Base.unwrap_unionall(method_instance.specTypes)
    spec isa DataType && spec <: Tuple && !isempty(spec.parameters) ||
        return false
    callable_type = first(spec.parameters)
    observed_type = _pointwise_operand_type(callee, analysis.typed_context)
    observed_type isa Type && observed_type <: callable_type || return false
    return _pointwise_method_instance_safe(method_instance, analysis, depth)
end

Base.@noinline function _pointwise_ir_safe(
        value, analysis::_PointwiseIRAnalysis, depth::Int
    )
    analysis.source_policy(value) || return false
    analysis.typed_policy(value, analysis.typed_context) || return false
    if value isa GlobalRef
        value.name in _POINTWISE_FORBIDDEN_CALLS && return false
        value.mod in (Base, Core) && return true
        isdefined(value.mod, value.name) || return false
        binding = getglobal(value.mod, value.name)
        binding isa DataType && isconcretetype(binding) && isbitstype(binding) &&
            _storage_free_type(binding) && return true
        return isconst(value.mod, value.name) && _storage_free_value(binding)
    end
    value isa Expr || return true
    value.head in (:foreigncall, :llvmcall, :cfunction) && return false
    if value.head === :invoke
        length(value.args) >= 2 || return false
        callee = value.args[2]
        operands_safe = all(
            operand -> _pointwise_ir_safe(operand, analysis, depth),
            value.args[3:end],
        )
        operands_safe || return false
        if !(callee isa GlobalRef)
            _pointwise_ir_safe(callee, analysis, depth) || return false
            return _pointwise_concrete_callable_invoke_safe(
                first(value.args), callee, analysis, depth
            )
        end
        isdefined(callee.mod, callee.name) || return false
        binding = getglobal(callee.mod, callee.name)
        any(
            candidate -> candidate === binding,
            _POINTWISE_FAILURE_ONLY_INVOKES,
        ) && return true
        return _pointwise_residual_invoke_safe(
            first(value.args), binding, analysis, depth
        )
    elseif value.head === :call
        isempty(value.args) && return false
        callee = first(value.args)
        # Optimized typed IR carries this pure builtin directly rather than as
        # a GlobalRef. Admit only recursively safe eager operands; this does
        # not admit mutation, opaque invokes, or foreign calls.
        callee in (Core.ifelse, Core.isa, _POINTWISE_AND_INT) && return all(
            operand -> _pointwise_ir_safe(operand, analysis, depth),
            value.args[2:end],
        )
        callee isa GlobalRef || return false
        _pointwise_ir_safe(callee, analysis, depth) || return false
    end
    return all(
        argument -> _pointwise_ir_safe(argument, analysis, depth),
        value.args,
    )
end

Base.@noinline function _pointwise_code_safe(
        info;
        source_policy = _pointwise_source_safe,
        typed_policy = _pointwise_typed_safe,
    )
    analysis = _PointwiseIRAnalysis(source_policy, typed_policy)
    analysis.typed_context = info
    for statement in info.code
        _pointwise_ir_safe(statement, analysis, 0) || return false
    end
    return true
end

_pointwise_ir_safe(value) = _pointwise_ir_safe(
    value, _PointwiseIRAnalysis(), 0
)

_failed_closed_callable_analysis(reason::Symbol;
        method = nothing, return_type = Any, operation = nothing,
        hint = "use a concrete, allocation-free callable with statically resolved calls") = (
    qualified = false,
    return_type,
    method,
    reason,
    operation,
    hint,
)

function _closed_source_rejection(value)
    value isa Expr || return nothing
    value.head === :foreigncall && return :foreign_call
    value.head in (:llvmcall, :cfunction) && return :foreign_call
    if value.head in (:call, :invoke) && !isempty(value.args)
        callee_index = value.head === :invoke ? 2 : 1
        if length(value.args) >= callee_index
            callee = value.args[callee_index]
            name = callee isa GlobalRef ? callee.name : nothing
            name in (:setindex!, :setfield!, :push!, :resize!, :copyto!) &&
                return :mutation
            name in (:Array, :Vector, :Matrix, :collect, :similar, :zeros, :ones) &&
                return :allocation
            name in _POINTWISE_FORBIDDEN_CALLS && return :unsafe_global_access
        end
    end
    for argument in value.args
        reason = _closed_source_rejection(argument)
        reason === nothing || return reason
    end
    return nothing
end

function _closed_source_rejection(code::Vector)
    for statement in code
        reason = _closed_source_rejection(statement)
        reason === nothing || return reason
    end
    return :unsupported_method_shape
end

function _closed_callable_effect_analysis(
        callable, signature, method_shape;
        source_policy = _pointwise_source_safe,
        typed_policy = _pointwise_typed_safe,
    )
    surrogate = _pointwise_surrogate_signature(signature)
    selected_method = try
        which(callable, signature)
    catch
        return _failed_closed_callable_analysis(:no_applicable_method;
            hint = "define a method for the reported analyzed signature")
    end
    selected_method === which(callable, surrogate) ||
        return _failed_closed_callable_analysis(:signature_mismatch;
            method = selected_method,
            hint = "make the callable select the same concrete method for the device surrogate signature")
    method_type = selected_method.sig
    while method_type isa UnionAll
        method_type = method_type.body
    end
    method_signature = method_type.parameters
    method_shape(method_signature) || return _failed_closed_callable_analysis(
        :unsupported_method_shape; method = selected_method)
    lowered = try
        code_lowered(callable, surrogate)
    catch
        return _failed_closed_callable_analysis(:lowering_failure;
            method = selected_method)
    end
    length(lowered) == 1 &&
        all(source_policy, first(lowered).code) ||
        return _failed_closed_callable_analysis(
            length(lowered) == 1 ?
                _closed_source_rejection(first(lowered).code) :
                :unsupported_method_shape;
            method = selected_method)
    typed = try
        code_typed(callable, surrogate; optimize = true)
    catch
        return _failed_closed_callable_analysis(:inference_failure;
            method = selected_method)
    end
    length(typed) == 1 || return _failed_closed_callable_analysis(
        :inference_failure; method = selected_method)
    code = first(typed)
    info = code isa Pair ? first(code) : code[1]
    return_type = code isa Pair ? last(code) : code[2]
    qualified = _pointwise_code_safe(info; source_policy, typed_policy)
    return qualified ? (
        qualified = true, return_type, method = selected_method,
        reason = :admitted, operation = nothing, hint = nothing,
    ) : _failed_closed_callable_analysis(:unsupported_typed_effect;
        method = selected_method, return_type,
        hint = "remove dynamic dispatch, recursion, capability introspection, or unsupported calls from the callable")
end

function _cached_closed_callable_effect_analysis!(
        cache::Dict{Any,Any}, qualification::Symbol,
        callable, signature, method_shape;
        source_policy = _pointwise_source_safe,
        typed_policy = _pointwise_typed_safe,
    )
    selected = try
        which(callable, signature)
    catch
        return _failed_closed_callable_analysis(:no_applicable_method;
            hint = "define a method for the reported analyzed signature")
    end
    key = (typeof(callable), selected, signature, qualification)
    return get!(cache, key) do
        _closed_callable_effect_analysis(callable, signature, method_shape;
            source_policy, typed_policy)
    end
end

function _closed_callable_effect_capability(
        callable, signature, method_shape
    )
    return _closed_callable_effect_analysis(
        callable, signature, method_shape
    ).qualified
end

function _pointwise_effect_capability(
        backend::KernelAbstractions.Backend, operation, signature
    )
    callable = operation isa _SingleOutputOperation ?
        operation.operation : operation
    return _closed_callable_effect_capability(
        callable, signature,
        method_signature -> length(method_signature) == 4 &&
            method_signature[3] === Any && method_signature[4] === Any,
    )
end

function _ordered_fold_effect_analysis(
        backend::KernelAbstractions.Backend, transition, signature
    )
    return _closed_callable_effect_analysis(
        transition, signature,
        method_signature -> length(method_signature) == 5,
    )
end

function _ordering_effect_capability(
        backend::KernelAbstractions.Backend, extractor, signature
    )
    return _closed_callable_effect_capability(
        extractor, signature,
        method_signature -> length(method_signature) == 2,
    )
end

function _pointwise_surrogate_type(::Type{T}) where {T}
    if T <: AbstractArray
        return Array{eltype(T), ndims(T)}
    elseif T <: NamedTuple
        names = T.parameters[1]
        fields = T.parameters[2].parameters
        tuple_type = Core.apply_type(
            Tuple, map(_pointwise_surrogate_type, fields)...
        )
        return NamedTuple{names, tuple_type}
    elseif T <: Tuple
        return Core.apply_type(
            Tuple, map(_pointwise_surrogate_type, T.parameters)...
        )
    end
    return T
end

function _pointwise_surrogate_type(
        ::Type{_PreparedFoldRead{T,S}}) where {T,S}
    storage = _pointwise_surrogate_type(S)
    return _PreparedFoldRead{T,storage}
end

function _pointwise_surrogate_type(
        ::Type{_PreparedFoldAccumulatorView{Names,C}}) where {Names,C}
    components = _pointwise_surrogate_type(C)
    return _PreparedFoldAccumulatorView{Names,components}
end

_pointwise_surrogate_signature(signature::Type{<:Tuple}) =
    _pointwise_surrogate_type(signature)
