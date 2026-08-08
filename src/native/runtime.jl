abstract type AbstractNativeRuntimeError <: Exception end

struct NativeProfileError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    message::String
end

struct NativeCapabilityError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    capability::Symbol
    message::String
end

struct NativeExecutionError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    phase::Symbol
    cause::Any
end

struct NativeSolveFailure <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    retcode::SciMLBase.ReturnCode.T
    reached_time::Any
    required_time::Any
end

_native_path_string(path) = join(path, '₊')

_native_components_have_ports(components) = any(
    component -> !isempty(native_coupling_endpoints(component)), components
)

Base.showerror(io::IO, error::NativeProfileError) = print(
    io, "native profile `", _native_path_string(error.path), "`: ", error.message
)
Base.showerror(io::IO, error::NativeCapabilityError) = print(
    io,
    "native component `", _native_path_string(error.path),
    "` lacks ", error.capability, ": ", error.message,
)
function Base.showerror(io::IO, error::NativeExecutionError)
    print(
        io,
        "native component `", _native_path_string(error.path),
        "` failed during ", error.phase, ": ",
    )
    showerror(io, error.cause)
end
Base.showerror(io::IO, error::NativeSolveFailure) = print(
    io,
    "native component `", _native_path_string(error.path),
    "` returned ", error.retcode, " at ", error.reached_time,
    "; required coupled boundary ", error.required_time,
)

"""Logical, solver-independent state of one native component boundary."""
struct NativeLogicalState{P <: Tuple, U <: Tuple, Q <: Tuple, D, T}
    path::P
    u::U
    p::Q
    du::D
    t::T
    retcode::SciMLBase.ReturnCode.T
end

function _native_logical_value(value, path, label)
    if value isa AbstractFloat
        isfinite(value) || throw(NativeCapabilityError(
            path, :logical_checkpoint,
            "$label contains a nonfinite floating-point value",
        ))
        return value
    elseif value isa Union{Bool, Integer, Symbol, AbstractString, Enum}
        return value
    elseif value isa Tuple
        return map(item -> _native_logical_value(item, path, label), value)
    elseif value isa NamedTuple
        mapped = map(
            item -> _native_logical_value(item, path, label), values(value)
        )
        return NamedTuple{keys(value)}(mapped)
    elseif value isa AbstractArray
        isbitstype(eltype(value)) || throw(NativeCapabilityError(
            path, :logical_checkpoint,
            "$label array has non-isbits element type $(eltype(value))",
        ))
        all(item -> !(item isa AbstractFloat) || isfinite(item), value) ||
            throw(NativeCapabilityError(
                path, :logical_checkpoint,
                "$label array contains a nonfinite floating-point value",
            ))
        return copy(value)
    end
    throw(NativeCapabilityError(
        path,
        :logical_checkpoint,
        "$label has unsupported logical value type $(typeof(value))",
    ))
end

function NativeLogicalState(path, u, p, du, t, retcode)
    normalized_path = _qualified_native_path(path, "NativeLogicalState")
    u isa Tuple || throw(NativeCapabilityError(
        normalized_path, :logical_state, "state values must use scheduled tuple order"
    ))
    p isa Tuple || throw(NativeCapabilityError(
        normalized_path, :logical_state, "parameter values must use scheduled tuple order"
    ))
    normalized_u = _native_logical_value(u, normalized_path, "u")
    normalized_p = _native_logical_value(p, normalized_path, "p")
    normalized_du = du === nothing ? nothing :
                    _native_logical_value(du, normalized_path, "du")
    normalized_t = _native_logical_value(t, normalized_path, "time")
    retcode isa SciMLBase.ReturnCode.T || throw(ArgumentError(
        "native logical state requires a SciML ReturnCode"
    ))
    return NativeLogicalState(
        normalized_path,
        normalized_u,
        normalized_p,
        normalized_du,
        normalized_t,
        retcode,
    )
end

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
        profiles,
    )
    components = scheduled_native_components(problem.system)
    isempty(components) && return nothing
    algorithm isa SequentialCPM || throw(NativeCapabilityError(
        (:runtime, :native_components),
        :execution_profile,
        "G5H-3 admits native coupling only with SequentialCPM",
    ))
    backend isa CPUBackend || throw(NativeCapabilityError(
        (:runtime, :native_components),
        :execution_profile,
        "G5H-3 admits native coupling only on CPUBackend",
    ))
    for (component, profile) in zip(components, profiles)
        path = native_component_path(component)
        declaration = getfield(component, :declaration)
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

function _require_native_replay_evidence(system::PottsSystem, profiles)
    components = scheduled_native_components(system)
    for (component, profile) in zip(components, profiles)
        evidence = applicable(_native_profile_evidence, component, profile) ?
            _native_profile_evidence(component, profile) : nothing
        (evidence !== nothing &&
                evidence.status === CorePotts.BackendSPI.Supported &&
                Int(evidence.maturity) >=
                    Int(CorePotts.BackendSPI.ReplayQualified)) ||
            throw(NativeCapabilityError(
                native_component_path(component),
                :closed_replay_evidence,
                "the standard native problem constructs and initializes, but this system/solver/event profile has no closed exact-replay evidence row",
            ))
    end
    return nothing
end

function _native_state_entry(plan::_PottsExecutionPlan, endpoint)
    endpoint.potts_kind === :ModelState || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "only ModelState coupling endpoints are admitted; got $(endpoint.potts_kind)",
    ))
    identity = _qualified_resource_identity(potts_endpoint(endpoint))
    matches = filter(entry -> entry.identity == identity, plan.reports.states)
    length(matches) == 1 || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved ModelState endpoint does not map to one runtime storage handle",
    ))
    entry = only(matches)
    entry.storage === :model || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved endpoint is not scalar model storage",
    ))
    return entry
end

function _read_native_endpoint(plan, descriptor_state, endpoint)
    entry = _native_state_entry(plan, endpoint)
    block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
    length(block.values) == 1 || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "G5H-3 ModelState coupling requires one scalar value",
    ))
    T = native_value_type(endpoint)
    value = try
        convert(T, only(block.values))
    catch error
        throw(NativeExecutionError(endpoint.component_path, :input_conversion, error))
    end
    value isa AbstractFloat && !isfinite(value) && throw(NativeCapabilityError(
        endpoint.component_path, :typed_io, "native input is nonfinite"
    ))
    return value
end

function _native_input_pairs(plan, descriptor_state, component)
    return Tuple(
        native_variable(endpoint) =>
            _read_native_endpoint(plan, descriptor_state, endpoint)
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa NativeInput
    )
end

function _native_output_updates(component, state::NativeLogicalState)
    return Tuple(
        let value = try
                native_component_value(component, state, native_variable(endpoint))
            catch error
                error isa AbstractNativeRuntimeError && rethrow()
                throw(NativeExecutionError(
                    endpoint.component_path, :output_evaluation, error
                ))
            end
            T = native_value_type(endpoint)
            converted = try
                convert(T, value)
            catch error
                throw(NativeExecutionError(
                    endpoint.component_path, :output_conversion, error
                ))
            end
            converted isa AbstractFloat && !isfinite(converted) &&
                throw(NativeCapabilityError(
                    endpoint.component_path, :typed_io,
                    "native output is nonfinite",
                ))
            endpoint => converted
        end
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa NativeOutput
    )
end

function _publish_native_outputs!(plan, descriptor_state, updates)
    isempty(updates) && return descriptor_state
    descriptor_state === nothing && throw(NativeCapabilityError(
        (:runtime, :native_components),
        :typed_io,
        "native coupling endpoints require a Core descriptor-state layout",
    ))
    for (endpoint, value) in updates
        entry = _native_state_entry(plan, endpoint)
        block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
        converted = try
            convert(eltype(block.values), value)
        catch error
            throw(NativeExecutionError(
                endpoint.component_path, :potts_output_conversion, error
            ))
        end
        converted isa AbstractFloat && !isfinite(converted) &&
            throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "converted Potts ModelState output is nonfinite",
            ))
        onlyindex = firstindex(block.values)
        block.values[onlyindex] = converted
    end
    return descriptor_state
end

function _validate_native_outputs(
        plan, descriptor_state, components, states
    )
    for (component, state) in zip(components, states)
        for (endpoint, expected) in _native_output_updates(component, state)
            actual = _read_native_endpoint(plan, descriptor_state, endpoint)
            isequal(actual, expected) || throw(NativeCapabilityError(
                endpoint.component_path,
                :checkpoint_consistency,
                "published Potts ModelState does not match its native output",
            ))
        end
    end
    return nothing
end

function _initial_native_states!(
        problem,
        plan,
        descriptor_state,
        profiles,
    )
    components = scheduled_native_components(problem.system)
    isempty(components) && return Any[]
    # Every island reads this same pre-native logical boundary. Output writes
    # occur only after every initialization and output evaluation succeeds.
    has_ports = _native_components_have_ports(components)
    has_ports && descriptor_state === nothing && throw(NativeCapabilityError(
        (:runtime, :native_components),
        :typed_io,
        "native coupling endpoints require a Core descriptor-state layout",
    ))
    input_snapshot = has_ports ?
        CorePotts.CompilerSPI.copy_auxiliary_state(descriptor_state) : nothing
    candidates = Any[]
    all_updates = Pair{Any, Any}[]
    for (component, profile) in zip(components, profiles)
        path = native_component_path(component)
        point = only(
            point for point in _problem_initial_state(problem).native
            if point.path == path
        )
        declaration = getfield(component, :declaration)
        inputs = _native_input_pairs(plan, input_snapshot, component)
        t0 = native_time_at(declaration, problem.tspan[1])
        candidate = try
            _initialize_preflighted_native_component(
                component, point, profile, inputs, t0
            )
        catch error
            error isa AbstractNativeRuntimeError && rethrow()
            throw(NativeExecutionError(path, :initialization, error))
        end
        candidate isa NativeLogicalState || throw(NativeCapabilityError(
            path, :logical_state,
            "native initialization did not return NativeLogicalState",
        ))
        candidate.path == path || throw(NativeCapabilityError(
            path, :logical_state, "native initialization changed component identity"
        ))
        push!(candidates, candidate)
        append!(all_updates, _native_output_updates(component, candidate))
    end
    _publish_native_outputs!(plan, descriptor_state, all_updates)
    return candidates
end

function _advance_native_candidates(
        integrator,
        descriptor_state,
        completed_mcs::Int,
    )
    components = scheduled_native_components(integrator.prob.system)
    candidates = copy(integrator.native_states)
    all_updates = Pair{Any, Any}[]
    # `descriptor_state` is one staged Core snapshot. This loop only reads it;
    # all island outputs are accumulated and published after every solve. This
    # makes due islands simultaneous/Jacobi and independent of tuple order.
    for index in eachindex(components)
        component = components[index]
        declaration = getfield(component, :declaration)
        if native_due(declaration, completed_mcs)
            inputs = _native_input_pairs(
                integrator.plan, descriptor_state, component
            )
            target = native_time_at(declaration, completed_mcs)
            candidate = try
                advance_native_component(
                    component,
                    integrator.native_states[index],
                    integrator.native_profiles[index],
                    inputs,
                    target,
                )
            catch error
                error isa AbstractNativeRuntimeError && rethrow()
                throw(NativeExecutionError(
                    native_component_path(component), :solve, error
                ))
            end
            candidate isa NativeLogicalState || throw(NativeCapabilityError(
                native_component_path(component),
                :logical_state,
                "native advance did not return NativeLogicalState",
            ))
            candidates[index] = candidate
        end
        append!(
            all_updates,
            _native_output_updates(component, candidates[index]),
        )
    end
    return candidates, all_updates
end

function _copy_native_logical_state(state::NativeLogicalState)
    return NativeLogicalState(
        state.path,
        state.u,
        state.p,
        state.du,
        state.t,
        state.retcode,
    )
end

function _native_state_by_path(states, path)
    normalized = _qualified_native_path(path, "native_state")
    matches = filter(state -> state.path == normalized, states)
    length(matches) == 1 || throw(ArgumentError(
        "native component path `$(_native_path_string(normalized))` is not present"
    ))
    return only(matches)
end

function _native_component_by_path(system::PottsSystem, path)
    normalized = _qualified_native_path(path, "native_state")
    matches = filter(
        component -> native_component_path(component) == normalized,
        scheduled_native_components(system),
    )
    length(matches) == 1 || throw(ArgumentError(
        "native component path `$(_native_path_string(normalized))` is not present"
    ))
    return only(matches)
end
