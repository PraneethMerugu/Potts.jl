"""Supertype of source-aware native-component runtime failures."""
abstract type AbstractNativeRuntimeError <: Exception end

"""Invalid or incomplete late native solve profile."""
struct NativeProfileError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    message::String
end

"""Native component failed a required structural or numerical capability check."""
struct NativeCapabilityError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    capability::Symbol
    message::String
end

"""Native execution failed during the reported coupled phase."""
struct NativeExecutionError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    phase::Symbol
    cause::Any
end

"""Native solver failed to reach a required coupled time boundary."""
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

include("component_pools.jl")

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

function _native_state_entry(plan::_PottsExecutionPlan, endpoint)
    endpoint.potts_kind in (:ModelState, :CellState, :FieldState) || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "only ModelState, CellState, and checked field-output endpoints are admitted; got $(endpoint.potts_kind)",
    ))
    identity = _qualified_resource_identity(potts_endpoint(endpoint))
    matches = filter(entry -> entry.identity == identity, plan.reports.states)
    length(matches) == 1 || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved ModelState endpoint does not map to one runtime storage handle",
    ))
    entry = only(matches)
    expected_storage = endpoint.potts_kind === :ModelState ? :model :
        endpoint.potts_kind === :CellState ? :cell : :site
    entry.storage === expected_storage || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved endpoint is not $expected_storage storage",
    ))
    return entry
end

function _read_native_endpoint(plan, descriptor_state, endpoint; slot = nothing)
    entry = _native_state_entry(plan, endpoint)
    block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
    if endpoint.potts_kind === :FieldState
        endpoint.port isa NativeFieldOutput || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "FieldState is output-only and requires NativeFieldOutput",
        ))
        size(block.values) == getfield(endpoint.port, :shape) ||
            throw(NativeCapabilityError(
                endpoint.component_path, :field_grid,
                "native field grid shape does not equal the Potts lattice shape",
            ))
        return reshape(copy(block.values), getfield(endpoint.port, :shape))
    end
    index = if endpoint.potts_kind === :ModelState
        length(block.values) == 1 || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "ModelState coupling requires one scalar value",
        ))
        firstindex(block.values)
    else
        slot isa Integer || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "CellState coupling requires a generation-validated cell slot",
        ))
        checkbounds(block.values, slot)
        Int(slot)
    end
    T = native_value_type(endpoint)
    value = try
        convert(T, block.values[index])
    catch error
        throw(NativeExecutionError(endpoint.component_path, :input_conversion, error))
    end
    value isa AbstractFloat && !isfinite(value) && throw(NativeCapabilityError(
        endpoint.component_path, :typed_io, "native input is nonfinite"
    ))
    return value
end

function _native_input_pairs(plan, descriptor_state, component; slot = nothing)
    return Tuple(
        native_variable(endpoint) =>
            _read_native_endpoint(plan, descriptor_state, endpoint; slot)
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa NativeInput
    )
end

function _native_output_updates(
        component, state::NativeLogicalState; slot = nothing
    )
    return Tuple(
        let value = try
                if endpoint.port isa NativeFieldOutput
                    values = map(
                        variable -> native_component_value(component, state, variable),
                        native_variables(endpoint.port),
                    )
                    reshape(collect(values), getfield(endpoint.port, :shape))
                else
                    native_component_value(component, state, native_variable(endpoint))
                end
            catch error
                error isa AbstractNativeRuntimeError && rethrow()
                throw(NativeExecutionError(
                    endpoint.component_path, :output_evaluation, error
                ))
            end
            T = native_value_type(endpoint)
            converted = try
                value isa AbstractArray ? T.(value) : convert(T, value)
            catch error
                throw(NativeExecutionError(
                    endpoint.component_path, :output_conversion, error
                ))
            end
            ((converted isa AbstractFloat && !isfinite(converted)) ||
                    (converted isa AbstractArray && !all(isfinite, converted))) &&
                throw(NativeCapabilityError(
                    endpoint.component_path, :typed_io,
                    "native output is nonfinite",
                ))
            (endpoint = endpoint, slot = slot, value = converted)
        end
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa Union{NativeOutput, NativeFieldOutput}
    )
end

function _publish_native_outputs!(plan, descriptor_state, updates)
    isempty(updates) && return descriptor_state
    descriptor_state === nothing && throw(NativeCapabilityError(
        (:runtime, :native_components),
        :typed_io,
        "native coupling endpoints require a Core descriptor-state layout",
    ))
    for update in updates
        endpoint = update.endpoint
        value = update.value
        entry = _native_state_entry(plan, endpoint)
        block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
        if endpoint.port isa NativeFieldOutput
            size(block.values) == size(value) || throw(NativeCapabilityError(
                endpoint.component_path, :field_grid,
                "native field output shape does not equal Potts field storage",
            ))
            converted = try
                eltype(block.values).(value)
            catch error
                throw(NativeExecutionError(
                    endpoint.component_path, :potts_output_conversion, error
                ))
            end
            all(isfinite, converted) || throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "converted Potts FieldState output is nonfinite",
            ))
            copyto!(block.values, converted)
            continue
        end
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
        index = if endpoint.potts_kind === :ModelState
            firstindex(block.values)
        else
            update.slot isa Integer || throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "CellState output publication requires a cell slot",
            ))
            checkbounds(block.values, update.slot)
            Int(update.slot)
        end
        block.values[index] = converted
    end
    return descriptor_state
end

function _validate_native_outputs(
    plan, descriptor_state, components, states
    )
    for (component, state) in zip(components, states)
        updates = if state isa NativeLogicalState
            _native_output_updates(component, state)
        elseif state isa NativeCellStatePool
            snapshot = native_cell_state_snapshot(state)
            Tuple(
                update
                for (slot, value) in enumerate(snapshot.states)
                if value !== nothing
                for update in _native_output_updates(component, value; slot)
            )
        else
            throw(NativeCapabilityError(
                native_component_path(component),
                :checkpoint_consistency,
                "checkpoint restoration produced an unknown native state representation",
            ))
        end
        for update in updates
            actual = _read_native_endpoint(
                plan, descriptor_state, update.endpoint; slot = update.slot
            )
            isequal(actual, update.value) || throw(NativeCapabilityError(
                update.endpoint.component_path,
                :checkpoint_consistency,
                "published Potts state does not match its native output",
            ))
        end
    end
    return nothing
end

function _initial_native_states!(
        problem,
        plan,
        core_initial,
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
    all_updates = Any[]
    for (component, profile) in zip(components, profiles)
        path = native_component_path(component)
        point = only(
            point for point in _problem_initial_state(problem).native
            if point.path == path
        )
        declaration = getfield(component, :declaration)
        t0 = native_time_at(declaration, problem.tspan[1])
        if getfield(declaration, :scope) isa Global
            inputs = _native_input_pairs(plan, input_snapshot, component)
            candidate = _initialize_native_logical_state(
                component, point, profile, inputs, t0
            )
            push!(candidates, candidate)
            append!(all_updates, _native_output_updates(component, candidate))
        else
            lifecycle_plan = plan.core_program.lifecycle_plan
            lifecycle_plan isa CorePotts.CompilerSPI.LifecycleExecutionPlan ||
                throw(NativeCapabilityError(
                    path, :cell_capacity,
                    "PerCell native components require a compiled fixed-capacity lifecycle plan",
                ))
            capacity = Int(lifecycle_plan.cell_capacity)
            kinds = zeros(Int16, capacity)
            generations = zeros(UInt32, capacity)
            initial_kinds = core_initial.cell_kinds
            initial_generations = core_initial.cell_generations
            copyto!(kinds, 1, initial_kinds, 1, length(initial_kinds))
            copyto!(
                generations, 1, initial_generations, 1,
                length(initial_generations),
            )
            active = kinds .> 0
            template_slot = findfirst(active)
            template_slot === nothing && (template_slot = 1)
            template_inputs = _native_input_pairs(
                plan, input_snapshot, component; slot = template_slot
            )
            template = _initialize_native_logical_state(
                component, point, profile, template_inputs, t0
            )
            policy = _native_cell_state_policy(component, template, capacity)
            bank = NativeCellStateBank(template, capacity)
            for slot in eachindex(active)
                active[slot] || continue
                candidate = slot == template_slot ? template :
                    _initialize_native_logical_state(
                        component,
                        point,
                        profile,
                        _native_input_pairs(
                            plan, input_snapshot, component; slot
                        ),
                        t0,
                    )
                _write_native_cell_state!(bank, slot, candidate)
                append!(all_updates,
                    _native_output_updates(component, candidate; slot))
            end
            push!(candidates, NativeCellStatePool(
                path, active, generations, kinds, bank, policy;
                completed_mcs = problem.tspan[1],
            ))
        end
    end
    _publish_native_outputs!(plan, descriptor_state, all_updates)
    return candidates
end

function _initialize_native_logical_state(
        component, point, profile, inputs, initial_time
    )
    path = native_component_path(component)
    candidate = try
        _initialize_preflighted_native_component(
            component, point, profile, inputs, initial_time
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
    return candidate
end

function _advance_native_candidates(
        integrator,
        descriptor_state,
        completed_mcs::Int,
        receipt,
        snapshot,
    )
    components = scheduled_native_components(integrator.prob.system)
    candidates = copy(integrator.native_states)
    all_updates = Any[]
    component_transactions = Any[]
    # `descriptor_state` is one staged Core snapshot. This loop only reads it;
    # all island outputs are accumulated and published after every solve. This
    # makes due islands simultaneous/Jacobi and independent of tuple order.
    for index in eachindex(components)
        component = components[index]
        declaration = getfield(component, :declaration)
        runtime_state = integrator.native_states[index]
        if runtime_state isa NativeCellStatePool
            _prepare_native_creation_states!(
                runtime_state,
                component,
                integrator.native_profiles[index],
                integrator.plan,
                descriptor_state,
                receipt,
                completed_mcs,
                integrator.prob,
            )
            component_transaction =
                CorePotts.BackendSPI.stage_lifecycle_receipt!(
                    runtime_state.storage, receipt
                )
            push!(component_transactions, component_transaction)
            candidate_bank = CorePotts.BackendSPI.component_transaction_state(
                component_transaction
            )
            if native_due(declaration, completed_mcs)
                target = native_time_at(declaration, completed_mcs)
                profile = integrator.native_profiles[index]
                live_slots = findall(kind -> kind > 0, snapshot.cell_kinds)
                if profile.execution isa SerialNativeExecution
                    for slot in live_slots
                        state = native_cell_state(
                            runtime_state.policy, candidate_bank, slot
                        )
                        candidate = _advance_native_logical_state(
                            component,
                            state,
                            profile,
                            _native_input_pairs(
                                integrator.plan, descriptor_state, component; slot
                            ),
                            target,
                        )
                        _write_native_cell_state!(candidate_bank, slot, candidate)
                    end
                elseif profile.execution isa BatchedNativeExecution
                    mode = profile.execution
                    for first_lane in 1:mode.width:length(live_slots)
                        last_lane = min(
                            first_lane + mode.width - 1, length(live_slots)
                        )
                        slots = live_slots[first_lane:last_lane]
                        lanes = [(
                            slot = Int(slot),
                            state = native_cell_state(
                                runtime_state.policy, candidate_bank, slot
                            ),
                            inputs = _native_input_pairs(
                                integrator.plan,
                                descriptor_state,
                                component;
                                slot,
                            ),
                        ) for slot in slots]
                        results = _advance_native_cell_batch(
                            component, lanes, profile, target
                        )
                        length(results) == length(lanes) || throw(
                            NativeCapabilityError(
                                path,
                                :native_execution_mode,
                                "batched native execution returned the wrong lane count",
                            )
                        )
                        for (lane, candidate) in zip(lanes, results)
                            candidate isa NativeLogicalState || throw(
                                NativeCapabilityError(
                                    path,
                                    :logical_state,
                                    "batched native execution returned an invalid lane state",
                                )
                            )
                            _write_native_cell_state!(
                                candidate_bank, lane.slot, candidate
                            )
                        end
                    end
                else
                    mode = profile.execution
                    mode isa MetalNativeExecution || error(
                        "validated native execution mode reached no runtime branch"
                    )
                    for first_lane in 1:mode.width:length(live_slots)
                        last_lane = min(
                            first_lane + mode.width - 1, length(live_slots)
                        )
                        slots = live_slots[first_lane:last_lane]
                        lanes = [(
                            slot = Int(slot),
                            state = native_cell_state(
                                runtime_state.policy, candidate_bank, slot
                            ),
                            inputs = _native_input_pairs(
                                integrator.plan,
                                descriptor_state,
                                component;
                                slot,
                            ),
                        ) for slot in slots]
                        results = _advance_native_cell_batch(
                            component, lanes, profile, target
                        )
                        length(results) == length(lanes) || throw(
                            NativeCapabilityError(
                                path,
                                :native_execution_mode,
                                "Metal native execution returned the wrong lane count",
                            )
                        )
                        for (lane, candidate) in zip(lanes, results)
                            _write_native_cell_state!(
                                candidate_bank, lane.slot, candidate
                            )
                        end
                    end
                end
            end
            for slot in eachindex(snapshot.cell_kinds)
                snapshot.cell_kinds[slot] > 0 || continue
                state = native_cell_state(
                    runtime_state.policy, candidate_bank, slot
                )
                append!(all_updates,
                    _native_output_updates(component, state; slot))
            end
        elseif native_due(declaration, completed_mcs)
            inputs = _native_input_pairs(
                integrator.plan, descriptor_state, component
            )
            target = native_time_at(declaration, completed_mcs)
            candidate = _advance_native_logical_state(
                component, runtime_state, integrator.native_profiles[index],
                inputs, target,
            )
            candidates[index] = candidate
        end
        runtime_state isa NativeCellStatePool || append!(
            all_updates, _native_output_updates(component, candidates[index])
        )
    end
    return candidates, all_updates, component_transactions
end

function _advance_native_logical_state(
        component, state, profile, inputs, target
    )
    candidate = try
        advance_native_component(component, state, profile, inputs, target)
    catch error
        error isa AbstractNativeRuntimeError && rethrow()
        throw(NativeExecutionError(
            native_component_path(component), :solve, error
        ))
    end
    candidate isa NativeLogicalState || throw(NativeCapabilityError(
        native_component_path(component), :logical_state,
        "native advance did not return NativeLogicalState",
    ))
    return candidate
end

function _prepare_native_creation_states!(
        pool::NativeCellStatePool,
        component,
        profile,
        plan,
        descriptor_state,
        receipt,
        completed_mcs,
        problem,
    )
    action = pool.policy.creation
    action isa _NativePreparedCreationAction || return pool
    fill!(action.states, nothing)
    point = only(
        point for point in _problem_initial_state(problem).native
        if point.path == pool.path
    )
    declaration = getfield(component, :declaration)
    initial_time = native_time_at(declaration, completed_mcs - 1)
    for event in CorePotts.lifecycle_events(receipt)
        event isa CorePotts.CreateLifecycleEvent || continue
        slot = Int(event.after.slot)
        action.states[slot] = _initialize_native_logical_state(
            component,
            point,
            profile,
            _native_input_pairs(plan, descriptor_state, component; slot),
            initial_time,
        )
    end
    return pool
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

_copy_native_logical_state(state::NativeCellStatePool) =
    native_cell_state_snapshot(state)

function _copy_native_logical_state(state::NativeCellStateSnapshot)
    return NativeCellStateSnapshot(
        state.path,
        copy(state.active),
        copy(state.generations),
        copy(state.kinds),
        deepcopy(state.identities),
        Union{Nothing, NativeLogicalState}[
            value === nothing ? nothing : _copy_native_logical_state(value)
            for value in state.states
        ],
        state.capacity,
        state.completed_mcs,
        state.last_transaction_identity,
    )
end

function _native_state_by_path(states, path)
    normalized = _qualified_native_path(path, "native_state")
    matches = filter(state -> _native_runtime_path(state) == normalized, states)
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
