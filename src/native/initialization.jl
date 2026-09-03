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

