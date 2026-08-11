# Hardware-agnostic KernelAbstractions provider. Kernel launches are implicitly
# ordered by the backend; one KernelAbstractions.synchronize call is the only
# execution-visibility boundary. No native stream, queue, or event is exposed.

mutable struct _KernelAbstractionsScope{B, D, T, E}
    backend::B
    device::D
    owner::T
    environment::E
    poisoned::Bool
    poison_reason::Any
end

mutable struct _KernelAbstractionsLane{S} <: _AbstractProviderLane
    scope::S
    waits::Int
end

const _KA_SCOPE_TLS_KEY = gensym(:LocalWorksetsKAScopes)

function _backend_probe(backend::KernelAbstractions.Backend)
    backend_module = parentmodule(typeof(backend))
    package = Base.PkgId(backend_module)
    package_version = try
        Base.pkgversion(backend_module)
    catch
        nothing
    end
    probe = findfirst(_REVIEWED_BACKEND_PROBES) do candidate
        candidate.backend_package_uuid == string(package.uuid) &&
            candidate.backend_package_version == package_version &&
            candidate.backend_module == string(backend_module) &&
            candidate.backend_type == string(nameof(typeof(backend)))
    end
    descriptor = probe === nothing ? nothing :
                 _REVIEWED_BACKEND_PROBES[probe]
    return (; backend_module, package, package_version, descriptor)
end

function _backend_device_token(backend::KernelAbstractions.Backend)
    backend isa KernelAbstractions.CPU &&
        return KernelAbstractions.device(backend)
    probe = invoke(
        _backend_probe, Tuple{KernelAbstractions.Backend}, backend
    )
    probe.descriptor === nothing &&
        return KernelAbstractions.device(backend)
    root = Base.loaded_modules[probe.package]
    device_function = getfield(root, probe.descriptor.current_device)
    return invoke(device_function, Tuple{})
end

function _backend_environment(backend::KernelAbstractions.Backend)
    probe = invoke(
        _backend_probe, Tuple{KernelAbstractions.Backend}, backend
    )
    backend_module = probe.backend_module
    package = probe.package
    package_version = probe.package_version
    device = KernelAbstractions.device(backend)
    canonical = function (value)
        value isa Union{Nothing, Bool, Integer, VersionNumber, Symbol} &&
            return value
        applicable(String, value) && return String(value)
        return repr(value)
    end
    if probe.descriptor === nothing
        device_identity = (
            source = :kernelabstractions,
            type = string(typeof(device)),
            value = repr(device),
        )
        runtime_identity = (;)
        provider_preferences = (;)
    else
        descriptor = probe.descriptor
        root = Base.loaded_modules[package]
        actual_device = invoke(
            _backend_device_token,
            Tuple{KernelAbstractions.Backend},
            backend,
        )
        device_values = map(descriptor.device_properties) do name
            canonical(getproperty(actual_device, name))
        end
        device_identity = merge(
            (source = :reviewed_backend_probe,),
            NamedTuple{descriptor.device_properties}(device_values),
        )
        runtime_values = map(descriptor.runtime_functions) do name
            function_value = getfield(root, name)
            canonical(invoke(function_value, Tuple{}))
        end
        runtime_identity = NamedTuple{descriptor.runtime_functions}(
            runtime_values
        )
        preference_loader = getfield(root, :load_preference)
        preference_names = Tuple(Symbol.(descriptor.preferences))
        preference_values = map(descriptor.preferences) do name
            canonical(preference_loader(root, name))
        end
        provider_preferences = NamedTuple{preference_names}(
            preference_values
        )
    end
    return (
        julia = VERSION,
        kernelabstractions = Base.pkgversion(KernelAbstractions),
        atomix = Base.pkgversion(Atomix),
        adapt = Base.pkgversion(Adapt),
        backend_package_uuid = string(package.uuid),
        backend_package_version = package_version,
        backend_module = string(backend_module),
        backend_type = string(nameof(typeof(backend))),
        device_type = string(typeof(device)),
        device_value = repr(device),
        device_identity,
        runtime_identity,
        provider_preferences,
        kernel = Sys.KERNEL,
        architecture = Sys.ARCH,
        machine = Sys.MACHINE,
        cpu = Sys.CPU_NAME,
        word_size = Sys.WORD_SIZE,
    )
end

_reviewed_backend_environment(backend::KernelAbstractions.Backend) =
    begin
        signature = Tuple{KernelAbstractions.Backend}
        method = which(_backend_environment, signature)
        method.module === (@__MODULE__) || return false
        invoke(_backend_environment, signature, backend) in
            _REVIEWED_BACKEND_ENVIRONMENTS
    end

function _make_provider_lane(
        backend::KernelAbstractions.Backend, storage
    )
    functional = KernelAbstractions.functional(backend)
    backend isa KernelAbstractions.CPU || functional === true ||
        throw(LocalWorkValidationError(
            "the KernelAbstractions backend is not functional"
        ))
    invoke(
        _reviewed_backend_environment,
        Tuple{KernelAbstractions.Backend},
        backend,
    ) ||
        throw(LocalWorkValidationError(
            "the KernelAbstractions backend environment has no reviewed execution evidence"
        ))
    environment = invoke(
        _backend_environment,
        Tuple{KernelAbstractions.Backend},
        backend,
    )
    task_storage = task_local_storage()
    scopes = get!(task_storage, _KA_SCOPE_TLS_KEY) do
        Dict{Any, Any}()
    end
    scope = get(scopes, environment, nothing)
    if scope === nothing
        scope = _KernelAbstractionsScope(
            backend,
            invoke(
                _backend_device_token,
                Tuple{KernelAbstractions.Backend},
                backend,
            ),
            current_task(),
            environment,
            false,
            nothing,
        )
        scopes[environment] = scope
    else
        current_task() === scope.owner || throw(LocalWorkValidationError(
            "the KernelAbstractions provider scope belongs to another task"
        ))
        scope.poisoned && throw(LocalWorkValidationError(
            "the KernelAbstractions provider scope is poisoned"
        ))
    end
    return _KernelAbstractionsLane(scope, 0)
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
_lane_poisoned(lane::_KernelAbstractionsLane) = lane.scope.poisoned
_lane_poison_reason(lane::_KernelAbstractionsLane) = lane.scope.poison_reason

function _poison_lane!(lane::_KernelAbstractionsLane, error)
    lane.scope.poisoned = true
    lane.scope.poison_reason = error
    return nothing
end

function _validate_lane_current!(lane::_KernelAbstractionsLane)
    scope = lane.scope
    current_task() === scope.owner || throw(LocalWorkValidationError(
        "KernelAbstractions submission must use the preparing owner task"
    ))
    scope.poisoned && throw(scope.poison_reason)
    functional = KernelAbstractions.functional(scope.backend)
    scope.backend isa KernelAbstractions.CPU || functional === true ||
        throw(LocalWorkValidationError(
            "the prepared KernelAbstractions backend is no longer functional"
        ))
    device = scope.backend isa KernelAbstractions.CPU ?
        KernelAbstractions.device(scope.backend) :
        invoke(
            _backend_device_token,
            Tuple{KernelAbstractions.Backend},
            scope.backend,
        )
    (device === scope.device || device == scope.device) ||
        throw(LocalWorkValidationError(
            "the reviewed KernelAbstractions device changed after preparation"
        ))
    return nothing
end

_validate_provider_capacity(::_KernelAbstractionsLane, evidence, capacity) =
    nothing

function _wait_lane!(lane::_KernelAbstractionsLane)
    lane.waits += 1
    scope = lane.scope
    invoke(
        _validate_lane_current!, Tuple{_KernelAbstractionsLane}, lane
    )
    try
        KernelAbstractions.synchronize(scope.backend)
    catch error
        invoke(
            _poison_lane!,
            Tuple{_KernelAbstractionsLane, Any},
            lane,
            error,
        )
        rethrow()
    end
    return nothing
end

function _atomic_capability(
        backend::KernelAbstractions.Backend,
        type::Type,
        operation::Symbol,
        address_space::Symbol,
    )
    reviewed = invoke(
        _reviewed_backend_environment,
        Tuple{KernelAbstractions.Backend},
        backend,
    )
    return reviewed &&
        address_space === :global && (
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
    reviewed = invoke(
        _reviewed_backend_environment,
        Tuple{KernelAbstractions.Backend},
        backend,
    )
    return reviewed && address_space === :global && (
        operation === :load && type in (Bool, Int32, UInt32, UInt8, Float32) ||
        operation === :store && type in (Int32, UInt32, UInt8, Float32)
    )
end

function _provider_compiler_identity(
        backend::KernelAbstractions.Backend
    )
    return merge(
        invoke(
            _backend_environment,
            Tuple{KernelAbstractions.Backend},
            backend,
        ),
        (qualification = :centrally_reviewed_environment,),
    )
end
