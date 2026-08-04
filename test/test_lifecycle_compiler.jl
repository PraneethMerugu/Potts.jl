include("fixtures/LifecycleOperationFixtures.jl")
using .LifecycleOperationFixtures

function _lifecycle_diagnostic_kind(error)
    error isa PottsToolkit.PottsValidationError || return nothing
    return only(error.diagnostics).kind
end

@testset "lifecycle structure does not specialize on counts or capacity" begin
    function compiled_lifecycle_shape(count, max_cells)
        cell = CellKind(:specialization_cell; extinction = RetireAtZero())
        medium = MediumKind(:specialization_medium)
        births = ntuple(count) do index
            LifecycleProcess(
                Symbol(:specialization_birth_, index);
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = SeedAt(mod1(index, 32)),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
            )
        end
        system = PottsSystem(
            name = :LifecycleSpecialization,
            statements = StatementSet((
                Lattice((8, 4); max_cells),
                cell,
                medium,
                births...,
                Protocol(Sweep(); name = :main),
            )),
        )
        return compile(
            complete(system);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        ).core_program.lifecycle_plan
    end

    one = compiled_lifecycle_shape(1, 4)
    different_capacity = compiled_lifecycle_shape(1, 32)
    many = compiled_lifecycle_shape(4, 32)
    @test typeof(one) === typeof(different_capacity) === typeof(many)
    @test typeof(one.descriptors) === typeof(many.descriptors)
    @test typeof(one.evaluators) === typeof(many.evaluators)
    @test one.cell_capacity == 4
    @test different_capacity.cell_capacity == many.cell_capacity == 32
    @test length(one.descriptors) == 2
    @test length(many.descriptors) == 5

    control = CorePotts.allocate_lifecycle_backend_control(
        one, zeros(UInt32, 1), 32
    )
    @test control.counters[CorePotts._LIFECYCLE_CONTROL_ACTIVE_BANK] == 1
    @test all(eachindex(control.counters)) do index
        index == CorePotts._LIFECYCLE_CONTROL_ACTIVE_BANK ||
            iszero(control.counters[index])
    end
    @test all(iszero, control.statistics)
    @test all(iszero, control.request_scan)
    @test all(iszero, control.request_scan_scratch)
    @test all(
        payload -> payload.code === CorePotts.LifecycleStatusSuccess,
        control.candidate_status,
    )
    @test all(==(typemax(UInt64)), control.site_keys)
end

function _minimal_lifecycle_system(name, statements)
    return PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((5, 5)),
            statements...,
            Protocol(Sweep(); name = :main),
        )),
    )
end

@testset "closed lifecycle compiler boundary" begin
    @variables t activity(t)
    cell = CellKind(:cell; extinction = RetireAtZero(priority = -3))
    daughter = CellKind(:daughter; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    relation = SpatialRelation(:division; neighborhood = VonNeumann())
    activity_state = CellState(
        activity;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:event_cell)

    create = LifecycleProcess(
        :create;
        domain = model(),
        expression = external_lifecycle_trigger(Symbolics.Num(1)),
        effects = (CreateCell(
            cell;
            placement = external_lifecycle_placement(Symbolics.Num(1)),
            state = (
                activity_state => InitializeFrom(
                    external_lifecycle_transform(activity)
                ),
            ),
            priority = 7,
            on_inadmissible = FilterInadmissible(),
        ),),
    )
    transition = LifecycleProcess(
        :transition;
        domain = cells(cell),
        anchor,
        expression = external_lifecycle_trigger(cell_volume(anchor_value(anchor))),
        effects = (Transition(
            anchor,
            daughter;
            state = (
                activity_state => Transform(
                    external_lifecycle_transform(activity)
                ),
            ),
            priority = 2,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    divide = LifecycleProcess(
        :divide;
        domain = cells(cell),
        anchor,
        expression = cell_volume(anchor_value(anchor)) > 4,
        effects = (Divide(
            anchor;
            geometry = external_lifecycle_partition(anchor_value(anchor)),
            relation,
            side = StableRandomSide(:division_side),
            parent_kind = PreserveKind(),
            daughter_kind = SetKind(daughter),
            priority = -1,
            on_inadmissible = FilterInadmissible(),
        ),),
    )
    completed = complete(_minimal_lifecycle_system(
        :LifecycleCompiler,
        (cell, daughter, medium, relation, activity_state, create, transition, divide),
    ))

    transfer_lookups = LifecycleOperationFixtures.TRANSFER_LOOKUPS[]
    callable_lookups = LifecycleOperationFixtures.CALLABLE_LOOKUPS[]
    plans = inspect(completed, LifecyclePlans())
    @test LifecycleOperationFixtures.TRANSFER_LOOKUPS[] == transfer_lookups
    @test LifecycleOperationFixtures.CALLABLE_LOOKUPS[] == callable_lookups

    by_effect = Dict(plan.effect => plan for plan in plans)
    @test all(!plan.runtime_ready for plan in plans)
    @test all(
        plan.domain === :model ||
            plan.domain_identity isa PottsToolkit.QualifiedStatementID
        for plan in plans
    )
    @test by_effect[:CreateCell].domain === :model
    @test by_effect[:CreateCell].policies.priority isa Int32
    @test by_effect[:CreateCell].policies.priority == 7
    @test by_effect[:CreateCell].policies.state isa Tuple
    @test by_effect[:Transition].anchor.identity ==
        by_effect[:Transition].domain_identity
    @test by_effect[:Transition].policies.destination.identity.local_id ==
        StatementID(:daughter)
    @test by_effect[:Divide].policies.daughter_kind.fields.kind.identity.local_id ==
        StatementID(:daughter)
    @test by_effect[:Divide].policies.side.kind === :StableRandomSide
    @test any(
        item -> item.policy === :schema,
        by_effect[:Divide].policies.resolution.state,
    )
    @test any(
        item -> item.policy === :event_override,
        by_effect[:Transition].policies.resolution.state,
    )

    all_abis = Tuple(Iterators.flatten(plan.operation_abis for plan in plans))
    external_abis = filter(item -> startswith(
        String(item.operation), "external_lifecycle_"
    ), all_abis)
    @test Set(item.abi.role for item in external_abis) == Set((
        :trigger, :placement, :binary_partition, :state_transform,
    ))
    @test all(item.owner === :LifecycleOperationFixtures for item in external_abis)
    @test all(item.callable_identity !== nothing for item in external_abis)

    graph = PottsToolkit._completion_data(completed).normalized_graph
    frozen_operations = Set(
        schema.transfer.identity for schema in graph.operation_snapshot
    )
    @test all(identity -> identity in frozen_operations, (
        :external_lifecycle_trigger,
        :external_lifecycle_placement,
        :external_lifecycle_partition,
        :external_lifecycle_transform,
    ))
    @test :explicit_field_euler ∉ frozen_operations
    @test :relationship_endpoint_kinds ∉ frozen_operations
    @test :draw ∉ frozen_operations
    @test length(graph.operation_snapshot) < length(
        PottsToolkit._v1_builtin_operation_inventory()
    )

    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    @test executable isa PottsExecutable
    @test executable.reports.lifecycle.descriptors == length(plans)
    @test executable.reports.lifecycle.cell_capacity == 25
    @test executable.reports.lifecycle.division_variants == 1
    @test count_ones(
        executable.core_program.lifecycle_plan.division_variant_mask
    ) == 1
    @test !iszero(
        executable.core_program.lifecycle_plan.division_variant_mask &
        CorePotts._lifecycle_division_variant_bit(
            CorePotts.ExternalLifecyclePartition,
            CorePotts.StableRandomLifecycleSide,
        )
    )
    @test executable.reports.workspace.lifecycle.allocation_model ===
        :fixed_preallocated
    @test executable.reports.workspace.lifecycle.cell_capacity == 25
    @test executable.reports.workspace.lifecycle.request_capacity ==
        executable.reports.lifecycle.maximum_requests
    @test executable.reports.workspace.lifecycle.partition_label_slots ==
        prod(executable.core_program.shape)
    @test executable.reports.workspace.lifecycle.policy_workspace_slots ==
        executable.reports.workspace.lifecycle.request_capacity * 8

    synthesized_only = complete(_minimal_lifecycle_system(
        :SynthesizedExtinction,
        (
            CellKind(:finite; extinction = RetireAtZero()),
            MediumKind(:background),
        ),
    ))
    synthesized_executable = compile(
        synthesized_only;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    @test synthesized_executable isa PottsExecutable
    @test synthesized_executable.reports.lifecycle.division_variants == 0
    @test only(inspect(synthesized_only, LifecyclePlans())).effect === :Retire

    missing_extinction = try
        complete(_minimal_lifecycle_system(
            :MissingExtinction,
            (CellKind(:finite), MediumKind(:background)),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(missing_extinction) ===
        :missing_extinction_policy

    medium_extinction = try
        complete(_minimal_lifecycle_system(
            :MediumExtinction,
            (
                CellKind(:finite; extinction = RetireAtZero()),
                MediumKind(:background; extinction = RetireAtZero()),
            ),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(medium_extinction) ===
        :medium_extinction_policy

    missing_state_policy = try
        complete(_minimal_lifecycle_system(
            :MissingStatePolicy,
            (
                CellKind(:finite; extinction = RetireAtZero()),
                MediumKind(:background),
                CellState(:unresolved_state; initial = 0.0),
            ),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(missing_state_policy) ===
        :missing_lifecycle_state_policy

    unsupported_state = CellState(
        :unsupported_state;
        initial = 0.0,
        creation = Unsupported(),
        retirement = RetireTo(0.0),
    )
    unsupported_create = LifecycleProcess(
        :unsupported_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedAt(1),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    unsupported_error = try
        complete(_minimal_lifecycle_system(
            :UnsupportedState,
            (cell, medium, unsupported_state, unsupported_create),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(unsupported_error) ===
        :unsupported_reachable_lifecycle_state

    overridden_create = LifecycleProcess(
        :overridden_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedAt(1),
            state = (unsupported_state => InitializeFrom(2.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    @test complete(_minimal_lifecycle_system(
        :OverriddenUnsupportedState,
        (cell, medium, unsupported_state, overridden_create),
    )) isa PottsSystem

    @test_throws UndefKeywordError CreateCell(cell; placement = SeedAt(1))
    @test_throws UndefKeywordError Retire(anchor)

    numeric_trigger = LifecycleProcess(
        :numeric_trigger;
        domain = cells(cell),
        anchor,
        expression = 1,
        effects = (Retire(
            anchor; on_inadmissible = ErrorOnInadmissible()
        ),),
    )
    numeric_error = try
        complete(_minimal_lifecycle_system(
            :NumericTrigger, (cell, medium, numeric_trigger)
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(numeric_error) ===
        :invalid_lifecycle_trigger_type

    site_domain = LifecycleProcess(
        :site_domain;
        domain = sites(:lattice),
        anchor,
        expression = true,
        effects = (Retire(
            anchor; on_inadmissible = ErrorOnInadmissible()
        ),),
    )
    domain_error = try
        complete(_minimal_lifecycle_system(
            :SiteDomain, (cell, medium, site_domain)
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(domain_error) ===
        :illegal_lifecycle_domain

    zero_cadence = LifecycleProcess(
        :zero_cadence;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Retire(
            anchor; on_inadmissible = ErrorOnInadmissible()
        ),),
        cadence = AtMCS(0),
    )
    cadence_error = try
        complete(_minimal_lifecycle_system(
            :ZeroCadence, (cell, medium, zero_cadence)
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(cadence_error) ===
        :illegal_lifecycle_cadence

    missing_abi_divide = LifecycleProcess(
        :missing_partition_abi;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = external_unqualified_partition(anchor_value(anchor)),
            relation,
            side = CanonicalSide(),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    missing_abi_error = try
        inspect(complete(_minimal_lifecycle_system(
            :MissingPartitionABI,
            (cell, medium, relation, activity_state, missing_abi_divide),
        )), LifecyclePlans())
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(missing_abi_error) ===
        :missing_lifecycle_policy_abi

    missing_trigger_abi = LifecycleProcess(
        :missing_trigger_abi;
        domain = cells(cell),
        anchor,
        expression = external_unqualified_trigger(anchor_value(anchor)),
        effects = (Retire(
            anchor; on_inadmissible = ErrorOnInadmissible()
        ),),
    )
    trigger_abi_error = try
        inspect(complete(_minimal_lifecycle_system(
            :MissingTriggerABI,
            (cell, medium, activity_state, missing_trigger_abi),
        )), LifecyclePlans())
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(trigger_abi_error) ===
        :missing_lifecycle_policy_abi

    missing_transform_abi = LifecycleProcess(
        :missing_transform_abi;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (
                activity_state => Transform(
                    external_unqualified_transform(activity)
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    transform_abi_error = try
        inspect(complete(_minimal_lifecycle_system(
            :MissingTransformABI,
            (cell, daughter, medium, activity_state, missing_transform_abi),
        )), LifecyclePlans())
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(transform_abi_error) ===
        :missing_lifecycle_policy_abi

    links = RelationshipState(
        :links;
        endpoints = Undirected(cell, cell),
        capacity = 4,
        maximum_degree = 2,
        lifecycle = RejectEndpointRetirement(),
    )
    missing_relationship_policy = LifecycleProcess(
        :missing_relationship_policy;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (activity_state => Preserve(),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
    )
    relationship_policy_error = try
        complete(_minimal_lifecycle_system(
            :MissingRelationshipPolicy,
            (
                cell,
                daughter,
                medium,
                activity_state,
                links,
                missing_relationship_policy,
            ),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(relationship_policy_error) ===
        :missing_lifecycle_relationship_policy

    edge = RelationshipBinding(:mixed_edge, links)
    mixed_effects = LifecycleProcess(
        :mixed_effects;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (
            Retire(anchor; on_inadmissible = ErrorOnInadmissible()),
            Remove(links, edge),
        ),
    )
    mixed_error = try
        complete(_minimal_lifecycle_system(
            :MixedLifecycleEffects,
            (cell, medium, activity_state, links, mixed_effects),
        ))
        nothing
    catch error
        error
    end
    @test _lifecycle_diagnostic_kind(mixed_error) ===
        :illegal_lifecycle_effect_composition

    proposal = ProposalContext(:illegal_lifecycle_proposal)
    proposal_trigger = LifecycleProcess(
        :proposal_trigger;
        domain = cells(cell),
        anchor,
        expression = proposal.is_extension,
        effects = (Retire(
            anchor; on_inadmissible = ErrorOnInadmissible()
        ),),
    )
    proposal_error = try
        inspect(complete(_minimal_lifecycle_system(
            :ProposalTrigger, (cell, medium, proposal_trigger)
        )), LifecyclePlans())
        nothing
    catch error
        error
    end
    @test proposal_error isa PottsToolkit.PottsValidationError
    @test only(proposal_error.diagnostics).kind in (
        :illegal_operation_use, :illegal_operation_context,
    )
end
