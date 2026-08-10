# Reachability-specialized orchestration of the ordered backend lifecycle transaction.

function enqueue_lifecycle_backend_index!(
        state;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    control = state.lifecycle_control
    control isa NoLifecycleBackendControl && return state
    workspace = state.lifecycle_workspace
    backend = KernelAbstractions.get_backend(state.ownership)
    workgroup_size === nothing || workgroup_size > 0 || throw(ArgumentError(
        "lifecycle workgroup size must be positive"
    ))
    launch(kernel) = workgroup_size === nothing ? kernel(backend) :
                     kernel(backend, Int(workgroup_size))
    reset = launch(_reset_lifecycle_backend_kernel!)
    site_keys = launch(_lifecycle_site_key_kernel!)
    reduce_status = _reduce_lifecycle_status_kernel!(backend, 1)
    index_sites = launch(_index_lifecycle_sites_kernel!)
    emit = launch(_emit_lifecycle_backend_kernel!)
    mark_requests = launch(_mark_lifecycle_requests_kernel!)
    compact_requests = launch(_compact_lifecycle_requests_kernel!)
    sort_requests = _sort_lifecycle_backend_kernel!(backend, 1)
    plan_effect = _plan_lifecycle_effect_backend_kernel!(backend, 1)
    plan_division = _plan_lifecycle_division_backend_kernel!(backend, 1)
    validate_division_relationships =
        _validate_lifecycle_division_relationships_backend_kernel!(backend, 1)
    replan_selected_division =
        _replan_selected_lifecycle_division_backend_kernel!(backend, 1)
    clear_selected_division_workspace =
        launch(_clear_selected_division_workspace_backend_kernel!)
    reduce_planning_status =
        _reduce_lifecycle_planning_status_kernel!(backend, 1)
    select_requests = _select_lifecycle_backend_kernel!(backend, 1)
    stage_structure = _stage_lifecycle_structure_backend_kernel!(backend, 1)
    stage_relationships =
        _stage_lifecycle_relationships_backend_kernel!(backend, 1)
    stage_state = _stage_lifecycle_state_backend_kernel!(backend, 1)
    finalize_effect = _finalize_lifecycle_effect_backend_kernel!(backend, 1)
    validate_requests = _validate_lifecycle_backend_kernel!(backend, 1)
    finalize_requests = _finalize_lifecycle_backend_kernel!(backend, 1)
    @debug "enqueue lifecycle backend stage" stage = :clear_policy_workspace
    clear_policy_workspace = launch(_clear_lifecycle_policy_workspace_kernel!)
    isempty(workspace.policy_workspace) || clear_policy_workspace(
        workspace, control; ndrange = length(workspace.policy_workspace)
    )
    @debug "enqueue lifecycle backend stage" stage = :reset
    reset(
        state.program.lifecycle_plan,
        workspace,
        control,
        Int32(state.mcs + 1);
        ndrange = length(control.candidate_status),
    )
    @debug "enqueue lifecycle backend stage" stage = :site_keys
    site_keys(
        control.site_keys,
        state.ownership,
        workspace,
        control,
        Int32(length(state.cell_kinds));
        ndrange = length(control.site_keys),
    )
    @debug "enqueue lifecycle backend stage" stage = :sort_site_keys
    _enqueue_lifecycle_sort!(
        control.site_keys, workspace, control, launch
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_site_status
    reduce_status(
        workspace, control, Int32(length(state.ownership)); ndrange = 1
    )
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageIndex)
    @debug "enqueue lifecycle backend stage" stage = :index_sites
    index_sites(
        workspace,
        control,
        Int32(length(state.cell_kinds));
        ndrange = length(state.cell_kinds),
    )
    @debug "enqueue lifecycle backend stage" stage = :emit_requests
    isempty(workspace.active) || emit(
        state,
        workspace,
        control,
        Int32(state.mcs + 1);
        ndrange = length(workspace.active),
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_emission_status
    reduce_status(
        workspace, control, Int32(length(workspace.active)); ndrange = 1
    )
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageEmission)
    @debug "enqueue lifecycle backend stage" stage = :mark_requests
    isempty(control.request_scan) || mark_requests(
        workspace, control; ndrange = length(control.request_scan)
    )
    @debug "enqueue lifecycle backend stage" stage = :scan_requests
    _enqueue_lifecycle_scan!(workspace, control, backend, launch)
    @debug "enqueue lifecycle backend stage" stage = :compact_requests
    isempty(control.request_scan) || compact_requests(
        workspace, control; ndrange = length(control.request_scan)
    )
    @debug "enqueue lifecycle backend stage" stage = :sort_requests
    sort_requests(state, workspace, control; ndrange = 1)
    effect_mask = state.program.lifecycle_plan.effect_mask
    for plan_class in (
            _CreateLifecyclePlan(),
            _RetireLifecyclePlan(),
            _RemoveLifecyclePlan(),
            _TransitionLifecyclePlan(),
        )
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle effect planner" plan_class
        plan_effect(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    division_variant_mask = state.program.lifecycle_plan.division_variant_mask
    division_variants = (
            _DivideLifecycleVariantPlan(
                _RandomPlanePartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _RandomPlanePartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMajorPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMajorPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMinorPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMinorPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _SpecifiedNormalPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _SpecifiedNormalPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _ExternalPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _ExternalPartitionPlan(), _StableRandomSidePlan()
            ),
        )
    for plan_class in division_variants
        iszero(
            division_variant_mask & _lifecycle_division_variant_bit(
                _lifecycle_partition_code(plan_class.partition),
                _lifecycle_side_code(plan_class.side),
            )
        ) && continue
        @debug "enqueue lifecycle division planner" plan_class
        plan_division(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :validate_division_relationships
    validate_division_relationships(
        state, workspace, control; ndrange = 1
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_planning_status
    reduce_planning_status(workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, ProgramStagePlanning)
    @debug "enqueue lifecycle backend stage" stage = :select_requests
    select_requests(state, workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageSelection)
    policy_workspace_length = length(workspace.policy_workspace)
    if policy_workspace_length > 0
        @debug "enqueue lifecycle backend stage" stage = :clear_selected_division_workspace
        clear_selected_division_workspace(
            state.program.lifecycle_plan,
            workspace,
            control;
            ndrange = policy_workspace_length,
        )
    end
    for plan_class in division_variants
        iszero(
            division_variant_mask & _lifecycle_division_variant_bit(
                _lifecycle_partition_code(plan_class.partition),
                _lifecycle_side_code(plan_class.side),
            )
        ) && continue
        @debug "enqueue selected lifecycle division planner" plan_class
        replan_selected_division(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :reduce_selected_planning_status
    reduce_planning_status(workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, ProgramStagePlanning)
    staged_state = (
        ownership = workspace.staged_ownership,
        cell_kinds = workspace.staged_cell_kinds,
        cell_generations = workspace.staged_cell_generations,
        trackers = workspace.staged_trackers,
        relationships = workspace.staged_relationships,
        descriptor_state = workspace.staged_descriptor_state,
    )
    @debug "enqueue lifecycle backend stage" stage = :stage_state
    _enqueue_lifecycle_gated_state_copy!(
        staged_state, state, backend, workspace, control
    )
    effect_classes = (
            _CreateLifecyclePlan(),
            _RetireLifecyclePlan(),
            _RemoveLifecyclePlan(),
            _TransitionLifecyclePlan(),
            _DivideLifecyclePlan(),
        )
    for plan_class in effect_classes
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle structural staging" plan_class
        stage_structure(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageStructure)
    relationship_action_mask =
        state.program.lifecycle_plan.relationship_action_mask
    for action_value in (
            Val(:remove_incident), Val(:remove_incompatible),
        )
        action = _lifecycle_relationship_action_value(action_value)
        iszero(
            relationship_action_mask &
            _lifecycle_relationship_action_bit(action)
        ) && continue
        @debug "enqueue lifecycle relationship staging" action
        stage_relationships(
            state, workspace, control, action_value; ndrange = 1
        )
    end
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageRelationships)
    state_actions = (
        Val(:initialize),
        Val(:retire_to),
        Val(:preserve),
        Val(:reset),
        Val(:transform),
        Val(:copy_daughters),
        Val(:preserve_parent_reset_daughter),
        Val(:reset_both),
        Val(:split_conservatively),
        Val(:transform_daughters),
        Val(:redraw_daughters),
    )
    state_runtime, state_descriptors, state_plan =
        _lifecycle_state_launch_payload(state, workspace)
    for action_value in state_actions
        action = _lifecycle_state_action_value(action_value)
        for plan_class in effect_classes
            iszero(
                effect_mask & _lifecycle_effect_bit(
                    _lifecycle_plan_effect(plan_class)
                )
            ) && continue
            effect_action_mask = state.program.lifecycle_plan.state_action_masks[
                Int(_lifecycle_plan_effect(plan_class))
            ]
            iszero(
                effect_action_mask & _lifecycle_state_action_bit(action)
            ) && continue
            @debug "enqueue lifecycle state staging" plan_class action
            stage_state(
                state_runtime,
                state_descriptors,
                state_plan,
                workspace,
                control,
                plan_class,
                action_value;
                ndrange = length(workspace.selected),
            )
        end
    end
    reduce_planning_status(workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageState)
    for plan_class in effect_classes
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle effect finalization" plan_class
        finalize_effect(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :validate_staged_state
    validate_requests(state, workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, ProgramStageValidation)
    @debug "enqueue lifecycle backend stage" stage = :publish_state
    _enqueue_lifecycle_gated_state_copy!(
        state, staged_state, backend, workspace, control
    )
    @debug "enqueue lifecycle backend stage" stage = :finalize
    finalize_requests(workspace, control; ndrange = 1)
    return state
end
