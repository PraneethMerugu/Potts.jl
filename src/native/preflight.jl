function _native_package_identity(module_value)
    root = Base.moduleroot(module_value)
    package = Base.identify_package(root, String(nameof(root)))
    version = try
        Base.pkgversion(root)
    catch
        nothing
    end
    return (
        name = package === nothing ? String(nameof(root)) : package.name,
        uuid = package === nothing ? nothing : string(package.uuid),
        version,
        module_name = join(string.(Base.fullname(module_value)), "."),
    )
end

function _native_profile_fingerprint(profile::NativeSolveProfile)
    algorithm_module = parentmodule(typeof(profile.algorithm))
    package = _native_package_identity(algorithm_module)
    return _sha256_hex(
        "potts-native-solve-profile-v1",
        profile.path,
        profile.profile_id,
        package.name,
        package.uuid,
        package.version,
        package.module_name,
        nameof(typeof(profile.algorithm)),
        repr(profile.algorithm),
        profile.options,
        profile.execution,
        profile.deterministic,
        profile.exact_replay,
    )
end

function _normalize_native_profiles(system::PottsSystem, supplied)
    components = scheduled_native_components(system)
    isempty(components) && begin
        supplied === nothing || isempty(Tuple(supplied)) || throw(ArgumentError(
            "native_profiles were supplied for a PottsSystem without native components"
        ))
        return ()
    end
    supplied === nothing && throw(ArgumentError(
        "native components require explicit path-qualified NativeSolveProfile values; " *
        "there is no default native solver"
    ))
    profiles = supplied isa NativeSolveProfile ? (supplied,) : try
        Tuple(supplied)
    catch
        throw(ArgumentError("native_profiles must contain NativeSolveProfile values"))
    end
    all(profile -> profile isa NativeSolveProfile, profiles) ||
        throw(ArgumentError(
            "native_profiles must contain only NativeSolveProfile values"
        ))
    paths = Tuple(profile.path for profile in profiles)
    length(unique(paths)) == length(paths) || throw(ArgumentError(
        "native solve-profile paths must be unique"
    ))
    expected = Tuple(native_component_path(component) for component in components)
    missing = setdiff(Set(expected), Set(paths))
    extra = setdiff(Set(paths), Set(expected))
    isempty(missing) || throw(ArgumentError(
        "missing NativeSolveProfile for component$(length(missing) == 1 ? "" : "s"): " *
        join((_native_path_string(path) for path in sort!(collect(missing); by = string)), ", ")
    ))
    isempty(extra) || throw(ArgumentError(
        "NativeSolveProfile does not resolve to a scheduled component: " *
        join((_native_path_string(path) for path in sort!(collect(extra); by = string)), ", ")
    ))
    by_path = Dict(profile.path => profile for profile in profiles)
    return Tuple(by_path[native_component_path(component)] for component in components)
end

function _native_runtime_preflight(
        problem::PottsProblem,
        algorithm::AbstractPottsAlgorithm,
        backend::AbstractPottsBackend,
        scalar_type::Type{<:AbstractFloat},
        profiles,
    )
    components = scheduled_native_components(problem.system)
    isempty(components) && return nothing
    metal_profiles = all(profile ->
        profile.execution isa MetalNativeExecution, profiles)
    cpu_profiles = all(profile ->
        profile.execution isa Union{
            SerialNativeExecution, BatchedNativeExecution,
        }, profiles)
    (metal_profiles || cpu_profiles) || throw(NativeCapabilityError(
        (:runtime, :native_components),
        :execution_profile,
        "native CPU and Metal execution modes cannot be mixed in one runtime",
    ))
    if metal_profiles
        algorithm isa CheckerboardSweepCPM || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :execution_profile,
            "qualified native Metal profiles require CheckerboardSweepCPM",
        ))
        backend isa MetalBackend || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :execution_profile,
            "MetalNativeExecution requires MetalBackend",
        ))
        scalar_type === Float32 || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :scalar_type,
            "the qualified native Metal profile requires scalar_type=Float32",
        ))
    else
        algorithm isa SequentialCPM || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :execution_profile,
            "qualified native CPU profiles require SequentialCPM",
        ))
        backend isa CPUBackend || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :execution_profile,
            "qualified native CPU profiles require CPUBackend",
        ))
        scalar_type === Float64 || throw(NativeCapabilityError(
            (:runtime, :native_components),
            :scalar_type,
            "the qualified native CPU profiles require scalar_type=Float64",
        ))
    end
    for (component, profile) in zip(components, profiles)
        path = native_component_path(component)
        declaration = getfield(component, :declaration)
        scope = getfield(declaration, :scope)
        profile.execution isa BatchedNativeExecution &&
            !(scope isa PerCell) && throw(NativeCapabilityError(
                path,
                :native_execution_mode,
                "BatchedNativeExecution is defined only for PerCell native components",
            ))
        profile.execution isa MetalNativeExecution &&
            scope isa Global && profile.execution.width != 1 &&
            throw(NativeCapabilityError(
                path,
                :native_execution_mode,
                "a Global Metal component requires MetalNativeExecution(1)",
            ))
        mod(problem.tspan[1], native_cadence_stride(declaration)) == 0 ||
            throw(NativeCapabilityError(
                path,
                :time_alignment,
                "problem start MCS $(problem.tspan[1]) is not a component cadence boundary",
            ))
        applicable(
            preflight_native_component,
            component,
            only(point for point in _problem_initial_state(problem).native if point.path == path),
            profile,
            native_time_at(declaration, problem.tspan[1]),
        ) || throw(NativeCapabilityError(
            path,
            :full_modelingtoolkit_runtime,
            "load ModelingToolkit before initializing native components",
        ))
        preflight_native_component(
            component,
            only(point for point in _problem_initial_state(problem).native if point.path == path),
            profile,
            native_time_at(declaration, problem.tspan[1]),
        )
        applicable(
            _initialize_preflighted_native_component,
            component,
            only(point for point in _problem_initial_state(problem).native if point.path == path),
            profile,
            (),
            native_time_at(declaration, problem.tspan[1]),
        ) || throw(NativeCapabilityError(
            path,
            :full_modelingtoolkit_runtime,
            "load ModelingToolkit before initializing native components",
        ))
    end
    return nothing
end

function _require_requested_native_replay(system::PottsSystem, profiles)
    components = scheduled_native_components(system)
    for (component, profile) in zip(components, profiles)
        profile.exact_replay || continue
        evidence = applicable(_native_profile_evidence, component, profile) ?
            _native_profile_evidence(component, profile) : nothing
        (evidence !== nothing &&
                evidence.status === CorePotts.BackendSPI.Supported &&
                evidence.exact_replay) ||
            throw(NativeCapabilityError(
                native_component_path(component),
                :exact_replay_evidence,
                "this system/solver/event profile has no closed exact-replay evidence row; native problem construction and solver initialization were not attempted",
            ))
    end
    return nothing
end

