struct DescriptorProbeAdaptor end

include("fixtures/G2SpecializationFixtures.jl")
using .G2SpecializationFixtures

_replace_parameter_default(
    expression::CorePotts.ParameterExpression,
    default,
) = CorePotts.ParameterExpression(default, expression.index)

_replace_parameter_default(
    expression::CorePotts.OperationExpression,
    default,
) = CorePotts.OperationExpression(
    expression.operation,
    map(
        argument -> _replace_parameter_default(argument, default),
        expression.arguments,
    ),
)

_replace_parameter_default(
    expression::CorePotts.AbstractStaticExpression,
    default,
) = expression

CorePotts.Adapt.adapt_storage(
    ::DescriptorProbeAdaptor, values::AbstractArray
) = copy(values)

struct OpaqueDescriptor{E, A, S, R}
    program::E
    resources::A
    capabilities::S
    proposal_role::R
    origin::Int32
end

CorePotts.descriptor_state_requirements(::OpaqueDescriptor) = ()
CorePotts.descriptor_workspace_requirements(::OpaqueDescriptor) = ()
CorePotts.descriptor_resource_access(descriptor::OpaqueDescriptor) =
    descriptor.resources
CorePotts.descriptor_stage(::OpaqueDescriptor) = :proposal
CorePotts.descriptor_role(descriptor::OpaqueDescriptor) =
    descriptor.proposal_role
CorePotts.descriptor_dependencies(::OpaqueDescriptor) = ()
CorePotts.descriptor_support(descriptor::OpaqueDescriptor) =
    descriptor.capabilities
CorePotts.descriptor_adapt(to, descriptor::OpaqueDescriptor) = descriptor
CorePotts.descriptor_evaluator_node_count(descriptor::OpaqueDescriptor) =
    CorePotts.evaluator_node_count(descriptor.program)
CorePotts.descriptor_source_handle(descriptor::OpaqueDescriptor) =
    descriptor.origin
CorePotts.descriptor_checkpoint_policy(::OpaqueDescriptor) =
    :reconstruct_from_executable
CorePotts.descriptor_checkpoint_encode(::OpaqueDescriptor) = nothing
CorePotts.descriptor_checkpoint_reconstruct(
    descriptor::OpaqueDescriptor, ::Nothing
) = descriptor
CorePotts.descriptor_inspection(descriptor::OpaqueDescriptor) = (
    family = :opaque_test_descriptor,
    source_handle = descriptor.origin,
)

function _hamiltonian_contribution_allocations(contributions, plan, context)
    return @allocated CorePotts.evaluate_hamiltonian_contributions!(
        contributions, plan, context
    )
end

@testset "G2 descriptor compiler boundary" begin
    fixture_registry = NeutralExternalTerms.registry()

    function bank_state_schema(name, element_type, shape)
        return CorePotts.StateBlockSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            :site,
            element_type,
            shape,
            prod(shape),
            :structure_of_arrays,
            :provided_or_zero,
            :shape_and_finite,
            :logical,
            :preserve,
            :declared,
            :bounded_write,
            :adapt_storage,
            :copy,
            :logical_copy,
            :qualified,
            true,
        )
    end

    function bank_workspace_schema(name, element_type, shape)
        return CorePotts.WorkspaceSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            element_type,
            shape,
            prod(shape),
            Array,
            :zero,
            :proposal,
            :read_write,
            :adapt_storage,
            :qualified,
            false,
        )
    end

    state_handle_sets = map((1, 32, 1024)) do count
        schemas = [
            bank_state_schema(Symbol(:state_, index), Float64, (4, 4))
            for index in 1:count
        ]
        order, handles = PottsToolkit._canonical_bank_handles(
            schemas,
            CorePotts.state_storage_class,
            CorePotts.StateHandle,
        )
        representation = CorePotts.state_storage_class(first(schemas))
        @test order == collect(1:count)
        @test unique(typeof.(handles)) ==
              [CorePotts.StateHandle{representation}]
        @test all(
            index -> CorePotts.handle_slot(handles[index]) == index,
            eachindex(handles),
        )
        @test all(
            handle ->
                CorePotts.handle_representation(handle) === representation,
            handles,
        )
        return handles
    end
    state_handles = last(state_handle_sets)
    @test allequal(typeof(first(handles)) for handles in state_handle_sets)

    renamed_state_class = reverse([
        bank_state_schema(Symbol(:renamed_, index), Float64, (9, 9))
        for index in 1:1024
    ])
    _, renamed_state_handles = PottsToolkit._canonical_bank_handles(
        renamed_state_class,
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    @test typeof.(renamed_state_handles) == typeof.(state_handles)

    target_state = bank_state_schema(
        :stable_float_state, Float64, (4, 4)
    )
    earlier_state = bank_state_schema(
        :added_boolean_state, Bool, (4, 4)
    )
    _, target_only_handles = PottsToolkit._canonical_bank_handles(
        [target_state],
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    _, with_earlier_handles = PottsToolkit._canonical_bank_handles(
        [target_state, earlier_state],
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    @test typeof(only(target_only_handles)) ===
          typeof(first(with_earlier_handles))
    @test CorePotts.handle_representation(only(target_only_handles)) ===
          CorePotts.handle_representation(first(with_earlier_handles))

    function handle_kernel_signature(handle)
        evaluator = CorePotts.StaticEvaluator(
            CorePotts.StateExpression(handle)
        )
        access = CorePotts.ResourceAccess(
            (handle,),
            (),
            CorePotts.EmptyFootprint(),
        )
        descriptor = CorePotts.ProposalDescriptor(
            evaluator,
            access,
            CorePotts.DescriptorSupport(true, true, true, true),
            (handle,),
            (),
            CorePotts.HamiltonianRole(),
            1,
        )
        return typeof(CorePotts.DescriptorKernelStrategy{
            typeof(descriptor),
            typeof(evaluator.expression),
            typeof(access.footprint),
            typeof(descriptor.role),
            Val{:proposal},
        }())
    end
    state_signatures = map(
        handles -> handle_kernel_signature(first(handles)),
        state_handle_sets,
    )
    @test allequal(state_signatures)
    @test handle_kernel_signature(only(target_only_handles)) ===
          handle_kernel_signature(first(with_earlier_handles))

    mixed_states = [
        bank_state_schema(:two_dimensional, Float64, (4, 4)),
        bank_state_schema(:one_dimensional, Int32, (16,)),
    ]
    _, mixed_handles = PottsToolkit._canonical_bank_handles(
        mixed_states,
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    _, reordered_mixed_handles = PottsToolkit._canonical_bank_handles(
        reverse(mixed_states),
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    mixed_types_by_class = Dict(
        CorePotts.state_storage_class(schema) => typeof(handle)
        for (schema, handle) in zip(mixed_states, mixed_handles)
    )
    reordered_types_by_class = Dict(
        CorePotts.state_storage_class(schema) => typeof(handle)
        for (schema, handle) in
            zip(reverse(mixed_states), reordered_mixed_handles)
    )
    @test mixed_types_by_class == reordered_types_by_class
    @test length(unique(Base.values(mixed_types_by_class))) == 2

    same_workspace_class = [
        bank_workspace_schema(Symbol(:workspace_, index), Float64, (4, 4))
        for index in 1:1024
    ]
    _, workspace_handles = PottsToolkit._canonical_bank_handles(
        same_workspace_class,
        CorePotts.workspace_storage_class,
        CorePotts.WorkspaceHandle,
    )
    @test unique(typeof.(workspace_handles)) ==
          [CorePotts.WorkspaceHandle{
              CorePotts.workspace_storage_class(first(same_workspace_class))
          }]

    target_workspace = bank_workspace_schema(
        :stable_float_workspace, Float64, (4, 4)
    )
    earlier_workspace = bank_workspace_schema(
        :added_boolean_workspace, Bool, (4, 4)
    )
    _, target_only_workspace_handles =
        PottsToolkit._canonical_bank_handles(
            [target_workspace],
            CorePotts.workspace_storage_class,
            CorePotts.WorkspaceHandle,
        )
    _, with_earlier_workspace_handles =
        PottsToolkit._canonical_bank_handles(
            [target_workspace, earlier_workspace],
            CorePotts.workspace_storage_class,
            CorePotts.WorkspaceHandle,
        )
    @test typeof(only(target_only_workspace_handles)) ===
          typeof(first(with_earlier_workspace_handles))

    function public_bank_model(site_name, model_name; reversed = false)
        declarations = (
            SiteState(site_name; initial = 0.0),
            ModelState(model_name; initial = 0.0),
        )
        ordered = reversed ? reverse(declarations) : declarations
        @named bank_model = PottsSystem(
            statements = StatementSet((
                Lattice((4, 4)),
                CellKind(:bank_cell),
                MediumKind(:bank_medium),
                ordered...,
                Protocol(Sweep(); name = :main),
            )),
        )
        return bank_model
    end

    first_bank_executable = compile(
        complete(public_bank_model(:z_site, :a_model));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    renamed_bank_executable = compile(
        complete(public_bank_model(
            :renamed_site,
            :renamed_model;
            reversed = true,
        ));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    first_bank_layout =
        first_bank_executable.core_program.descriptor_plan.state_layout
    renamed_bank_layout =
        renamed_bank_executable.core_program.descriptor_plan.state_layout
    @test typeof(first_bank_layout) === typeof(renamed_bank_layout)
    first_public_bank_types = Dict(
        CorePotts.state_storage_class(entry.schema) =>
            typeof(entry.handle)
        for entry in first_bank_layout.entries
    )
    renamed_public_bank_types = Dict(
        CorePotts.state_storage_class(entry.schema) =>
            typeof(entry.handle)
        for entry in renamed_bank_layout.entries
    )
    @test first_public_bank_types == renamed_public_bank_types

    # A rejected descendant cannot be hidden beneath an admitted root
    # operation. OperationTransfer capability is compositional across the DAG.
    @parameters cpu_only_parameter = 2.0
    nested_cpu_only_expression =
        1.0 + NeutralExternalTerms.external_cpu_only_value(
        cpu_only_parameter
    )
    cpu_only_site = SiteBinding(:cpu_only_site)
    @named nested_cpu_only = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            CellKind(:cpu_only_cell),
            MediumKind(:cpu_only_medium),
            HamiltonianTerm(
                :nested_cpu_only_energy;
                domain = sites(:lattice),
                anchor = cpu_only_site,
                expression = nested_cpu_only_expression,
            ),
            Protocol(Sweep(); name = :main),
        )),
        parameters = [cpu_only_parameter],
    )
    completed_cpu_only = complete(nested_cpu_only)
    cpu_only_ir =
        PottsToolkit._analyze_completed_system(completed_cpu_only)
    cpu_only_candidate = only(filter(
        candidate ->
            candidate.source.local_id ==
            StatementID(:nested_cpu_only_energy),
        cpu_only_ir.candidates,
    ))
    cpu_only_root = Int(only(cpu_only_candidate.roots))
    cpu_only_node = only(findall(
        node ->
            node.transfer !== nothing &&
            node.transfer.identity === :neutral_external_cpu_only_value,
        cpu_only_ir.graph.nodes,
    ))
    @test !cpu_only_ir.facts.backend_admission[cpu_only_node].gpu
    @test !cpu_only_ir.facts.backend_admission[cpu_only_root].gpu
    @test occursin(
        "neutral_external_cpu_only_value",
        cpu_only_ir.facts.backend_admission[cpu_only_root].reason,
    )
    cpu_only_executable = compile(
        completed_cpu_only;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    cpu_only_descriptor = only(CorePotts.descriptor_launch(only(
        cpu_only_executable.core_program.descriptor_plan.groups
    )).instances)
    @test CorePotts.descriptor_support(cpu_only_descriptor).cpu
    @test !CorePotts.descriptor_support(cpu_only_descriptor).gpu

    function site_model(
            count;
            weight_default = 2.5,
            identity_prefix = :external_site,
        )
        @variables external_activity
        @parameters external_weight = weight_default
        endothelial = CellKind(:endothelial)
        extracellular = MediumKind(:extracellular)
        site = SiteBinding(:site)
        activity = SiteState(
            external_activity;
            name = :external_activity,
            initial = 1.0,
            owner = endothelial,
            lifecycle = PreserveOnOwnershipChange(),
        )
        terms = AbstractPottsStatement[
            NeutralExternalTerms.ExternalWeightedSiteTerm(
                Symbol(identity_prefix, :_, index),
                external_weight,
                external_activity,
                endothelial,
                site,
            )
            for index in 1:count
        ]
        @named model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (4, 4);
                    relations = (
                        proposal = VonNeumann(),
                        contact = Moore(),
                    ),
                ),
                endothelial,
                extracellular,
                activity,
                terms...,
                Protocol(Sweep(); name = :main),
            )),
            unknowns = [external_activity],
            parameters = [external_weight],
        )
        return model
    end

    compile_site(count; weight_default = 2.5) = compile(
        complete(
            site_model(count; weight_default);
            registry = fixture_registry,
        );
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )

    payload_bypass = try
        compile(
            complete(
                site_model(
                    1;
                    identity_prefix = :adversarial_payload,
                );
                registry = fixture_registry,
            );
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch error
        error
    end
    @test payload_bypass isa PottsToolkit.PottsValidationError
    @test only(payload_bypass.diagnostics).kind ===
          :executable_descriptor_payload

    specialization_payload_bypass = try
        compile(
            complete(
                site_model(
                    2;
                    identity_prefix = :adversarial_specialization,
                );
                registry = fixture_registry,
            );
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch error
        error
    end
    @test specialization_payload_bypass isa
          PottsToolkit.PottsValidationError
    specialization_diagnostic = only(
        specialization_payload_bypass.diagnostics
    )
    @test specialization_diagnostic.kind ===
          :descriptor_payload_type_mismatch
    @test occursin(
        "ExternalWeightedSitePayload",
        specialization_diagnostic.expected,
    )
    @test occursin(
        "NameParameterizedPayload",
        specialization_diagnostic.actual,
    )

    single = compile_site(1)

    single_plan = single.core_program.descriptor_plan
    group = only(single_plan.groups)
    launch = CorePotts.descriptor_launch(group)
    descriptor = only(launch.instances)
    original_expression = descriptor.evaluator.expression
    parameter_expression = _replace_parameter_default(
        original_expression,
        7.5,
    )
    parameter_descriptor = CorePotts.ProposalDescriptor(
        CorePotts.StaticEvaluator(parameter_expression),
        descriptor.access,
        descriptor.support,
        descriptor.state_handles,
        descriptor.workspace_handles,
        descriptor.role,
        descriptor.source_handle,
        descriptor.payload,
    )
    parameter_groups = PottsToolkit._descriptor_groups(
        [parameter_descriptor]
    )
    function replicated_plan(count)
        groups = PottsToolkit._descriptor_groups(
            fill(descriptor, count)
        )
        return CorePotts.DescriptorExecutionPlan(
            groups,
            single_plan.state_layout,
            single_plan.workspace_layout,
            single_plan.constraints,
            single_plan.source_table,
            Int32(count),
            single_plan.fingerprint,
            single_plan.domain_resources,
        )
    end
    repeated_plan = replicated_plan(32)
    stress_plan = replicated_plan(1024)
    repeated_report = CorePotts.descriptor_plan_report(repeated_plan)
    stress_report = CorePotts.descriptor_plan_report(stress_plan)

    @test single.reports.descriptors.occurrences == 1
    @test single.reports.descriptors.groups == 1
    @test repeated_report.occurrences == 32
    @test stress_report.occurrences == 1024
    @test repeated_report.groups ==
          stress_report.groups == 1
    @test repeated_report.instances == (32,)
    @test stress_report.instances == (1024,)
    @test repeated_report.evaluator_nodes ==
          single.reports.descriptors.evaluator_nodes ==
          stress_report.evaluator_nodes
    @test repeated_report.group_splits ==
          stress_report.group_splits ==
          CorePotts.descriptor_plan_report(
              CorePotts.DescriptorExecutionPlan(
                  parameter_groups,
                  single_plan.state_layout,
                  single_plan.workspace_layout,
                  single_plan.constraints,
                  single_plan.source_table,
                  Int32(1),
                  single_plan.fingerprint,
                  single_plan.domain_resources,
              ),
          ).group_splits
    @test repeated_report.kernel_families ==
          stress_report.kernel_families ==
          Tuple(
              nameof(typeof(item.launch.strategy))
              for item in parameter_groups
          )
    @test typeof(repeated_plan.groups[1].launch.instances) ===
          typeof(single_plan.groups[1].launch.instances) ===
          typeof(stress_plan.groups[1].launch.instances)
    @test typeof(repeated_plan.groups) ===
          typeof(single_plan.groups) ===
          typeof(stress_plan.groups) ===
          typeof(parameter_groups)
    @test typeof(parameter_descriptor) === typeof(descriptor)
    @test descriptor isa CorePotts.ProposalDescriptor
    @test descriptor.payload isa
          NeutralExternalTerms.ExternalWeightedSitePayload
    state_handle = only(launch.state_handles)
    workspace_handle = only(launch.workspace_handles)
    @test CorePotts.descriptor_state_requirements(descriptor) ==
          (state_handle,)
    @test CorePotts.descriptor_workspace_requirements(descriptor) ==
          (workspace_handle,)
    @test CorePotts.handle_bank(state_handle) == 1
    @test CorePotts.handle_slot(state_handle) == 1
    @test CorePotts.handle_bank(workspace_handle) == 1
    @test CorePotts.handle_slot(workspace_handle) == 1
    @test CorePotts.descriptor_stage(descriptor) === :proposal
    @test CorePotts.descriptor_role(descriptor) isa
          CorePotts.HamiltonianRole
    @test CorePotts.descriptor_support(descriptor).gpu
    @test CorePotts.descriptor_resource_access(descriptor).footprint isa
          CorePotts.FiniteSpatialFootprint
    descriptor_checkpoint = CorePotts.descriptor_checkpoint(descriptor)
    @test descriptor_checkpoint.policy ===
          :reconstruct_from_executable
    @test descriptor_checkpoint.payload.schema == 1
    @test CorePotts.descriptor_checkpoint_reconstruct(
        descriptor, descriptor_checkpoint.payload
    ) === descriptor

    values = (
        source_site = Int32(1),
        target_site = Int32(2),
        source_cell = Int32(1),
        target_cell = Int32(2),
        source_kind = Int16(1),
        target_kind = Int16(1),
        is_extension = true,
        is_retraction = false,
        energy_anchor_site = Int32(2),
        energy_anchor_cell = Int32(1),
        energy_anchor_contact = (Int32(1), Int32(2)),
        energy_anchor_relationship = Int32(1),
        cell_volumes = Float64[0, 7],
        ownership = Int32[0, 1],
        cell_kinds = Int16[2],
    )
    initial_external_state = zeros(Float64, 4, 4)
    initial_external_state[2] = 7
    auxiliary_state = CorePotts.allocate_auxiliary_state(
        single_plan.state_layout, (initial_external_state,)
    )
    runtime_workspaces = CorePotts.allocate_runtime_workspaces(
        single_plan.workspace_layout
    )
    context = CorePotts.EvaluatorProbeContext(
        single.core_program.parameter_defaults,
        values,
        auxiliary_state,
        runtime_workspaces,
    )
    @test CorePotts.evaluate_static(descriptor.evaluator, context) == 17.5
    CorePotts.evaluate_static(descriptor.evaluator, context)
    warmed_descriptor_allocations(descriptor, context) = @allocated(
        CorePotts.evaluate_static(descriptor.evaluator, context)
    )
    @test warmed_descriptor_allocations(descriptor, context) == 0
    inferred = Core.Compiler.return_type(
        CorePotts.evaluate_static,
        Tuple{typeof(descriptor.evaluator), typeof(context)},
    )
    @test inferred === Float64
    @test isbitstype(typeof(descriptor.evaluator))
    @test isbits(descriptor)
    @test isconcretetype(typeof(launch.instances))

    runtime_state_values = zeros(Float64, 4, 4)
    runtime_state_values[2] = 7.0
    runtime_initial = PottsInitialState(
        ownership = LabelledCells(
            ones(Int32, 4, 4);
            cells = [:endothelial],
            medium = :extracellular,
        ),
        values = [:external_activity => runtime_state_values],
    )
    core_initial = PottsToolkit._core_initial_state(
        single, runtime_initial
    )
    runtime = CorePotts.initialize_program(
        single.core_program,
        core_initial,
        single.core_program.parameter_defaults,
        UInt64(0x724),
        UInt32(1),
    )
    runtime_view = CorePotts.BeforeProposalView(
        runtime, CartesianIndex(2, 1), Int32(1), Int32(1)
    )
    runtime_context = CorePotts.HamiltonianEvaluationContext(
        runtime_view, CartesianIndex(2, 1), nothing
    )
    @test CorePotts.evaluate_static(
        descriptor.evaluator, runtime_context
    ) == 17.5
    @test CorePotts.state_block(
        runtime.descriptor_state, only(launch.state_handles)
    ).values == runtime_state_values
    restored_runtime = CorePotts.restore_program_checkpoint(
        single.core_program, CorePotts.program_checkpoint(runtime)
    )
    @test CorePotts.state_block(
        restored_runtime.descriptor_state, only(launch.state_handles)
    ).values == runtime_state_values

    adapted_launch = CorePotts.adapt_descriptor_launch(
        DescriptorProbeAdaptor(), group
    )
    @test adapted_launch !== launch
    @test adapted_launch.instances !== launch.instances
    @test typeof(adapted_launch) === typeof(launch)
    @test adapted_launch.state_handles == launch.state_handles
    @test adapted_launch.workspace_handles == launch.workspace_handles

    output = zeros(Float64, length(adapted_launch.instances))
    kernel_backend = CorePotts.KernelAbstractions.CPU()
    kernel = CorePotts.descriptor_group_probe_kernel!(kernel_backend)
    kernel(
        output,
        adapted_launch,
        context;
        ndrange = length(output),
    )
    CorePotts.KernelAbstractions.synchronize(kernel_backend)
    @test output == fill(17.5, length(output))

    state_schema = only(single_plan.state_layout.schemas)
    @test state_schema.identity.path == (:model,)
    @test state_schema.identity.name === :external_activity
    @test state_schema.domain === :site
    @test state_schema.checkpoint
    workspace_schema = only(single_plan.workspace_layout.schemas)
    @test workspace_schema.identity.path == (:model,)
    @test workspace_schema.identity.name ===
          :external_weighted_occupancy
    @test workspace_schema.element_type === Float64
    @test workspace_schema.capacity == 16
    @test workspace_schema.lifetime === :observation_stage
    @test workspace_schema.adaptation === :adapt_storage

    state_block = CorePotts.state_block(
        auxiliary_state, only(launch.state_handles)
    )
    workspace_block = CorePotts.workspace_block(
        runtime_workspaces, only(launch.workspace_handles)
    )
    @test state_block.values == initial_external_state
    @test size(workspace_block.values) == (4, 4)
    @test all(iszero, workspace_block.values)
    fill!(workspace_block.values, 3)
    CorePotts.reset_runtime_workspaces!(
        single_plan.workspace_layout, runtime_workspaces
    )
    @test all(iszero, workspace_block.values)

    exported = CorePotts.settled_state_export(
        single_plan.state_layout, auxiliary_state
    )
    @test only(exported) == initial_external_state
    @test only(exported) !== state_block.values
    state_checkpoint = CorePotts.encode_auxiliary_state_checkpoint(
        single_plan.state_layout, auxiliary_state
    )
    @test !hasproperty(state_checkpoint, :workspaces)
    reconstructed_state = CorePotts.reconstruct_auxiliary_state(
        single_plan.state_layout, state_checkpoint
    )
    reconstructed_block = CorePotts.state_block(
        reconstructed_state, only(launch.state_handles)
    )
    @test reconstructed_block.values == initial_external_state
    @test reconstructed_block.values !== state_block.values

    adapted_state = CorePotts.adapt_auxiliary_state(
        DescriptorProbeAdaptor(),
        single_plan.state_layout,
        auxiliary_state,
    )
    adapted_workspaces = CorePotts.adapt_runtime_workspaces(
        DescriptorProbeAdaptor(),
        single_plan.workspace_layout,
        runtime_workspaces,
    )
    @test CorePotts.state_block(
        adapted_state, only(launch.state_handles)
    ).values !== state_block.values
    @test CorePotts.workspace_block(
        adapted_workspaces, only(launch.workspace_handles)
    ).values !== workspace_block.values
    @test only(CorePotts.inspect_auxiliary_state(
        single_plan.state_layout, auxiliary_state
    )).identity == state_schema.identity
    @test only(CorePotts.inspect_runtime_workspaces(
        single_plan.workspace_layout, runtime_workspaces
    )).identity == workspace_schema.identity
    first_descriptor_inspection =
        first(single.reports.descriptors.descriptor_inspections)[1]
    @test first_descriptor_inspection.qualified_source.path == (:model,)

    opaque = OpaqueDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(2.0)),
        CorePotts.ResourceAccess((), (), CorePotts.EmptyFootprint()),
        CorePotts.DescriptorSupport(true, true, true, true),
        CorePotts.HamiltonianRole(),
        Int32(1),
    )
    opaque_strategy = CorePotts.DescriptorKernelStrategy{
        typeof(opaque),
        typeof(opaque.program.expression),
        CorePotts.EmptyFootprint,
        CorePotts.HamiltonianRole,
        Val{:proposal},
    }()
    opaque_launch = CorePotts.DescriptorLaunch(
        opaque_strategy, [opaque], (), ()
    )
    opaque_group = CorePotts.DescriptorGroup(
        opaque_launch,
        (
            descriptor = :OpaqueDescriptor,
            evaluator = nameof(typeof(opaque.program.expression)),
            footprint = :EmptyFootprint,
            role = :HamiltonianRole,
            stage = :proposal,
        ),
    )
    @test_throws ArgumentError CorePotts.DescriptorExecutionPlan(
        (opaque_group,),
        CorePotts.StateLayout(()),
        CorePotts.WorkspaceLayout(()),
        (),
        Any[:opaque_source],
        Int32(1),
        "opaque-report-probe",
        CorePotts.HamiltonianDomainResources(0, 1),
    )

    # Direct built-in terms use the same sole grouped boundary; no occurrence
    # tuple remains hidden in CompiledPottsProgram.
    direct_one = G2SpecializationFixtures.compile_direct_model(1)
    direct_plan = direct_one.core_program.descriptor_plan
    direct_descriptor = only(CorePotts.descriptor_launch(
        only(direct_plan.groups)
    ).instances)
    direct_report(count) = CorePotts.descriptor_plan_report(
        CorePotts.DescriptorExecutionPlan(
            PottsToolkit._descriptor_groups(fill(direct_descriptor, count)),
            direct_plan.state_layout,
            direct_plan.workspace_layout,
            direct_plan.constraints,
            direct_plan.source_table,
            Int32(count),
            direct_plan.fingerprint,
            direct_plan.domain_resources,
        )
    )
    direct_reports = (
        direct_one.reports.descriptors,
        direct_report(32),
        direct_report(1024),
    )
    @test getfield.(direct_reports, :groups) == (1, 1, 1)
    @test getfield.(direct_reports, :occurrences) == (1, 32, 1024)
    @test allequal(getfield.(direct_reports, :group_splits))
    @test allequal(getfield.(direct_reports, :kernel_families))
    @test !hasproperty(direct_one.core_program, :proposal_energies)
    @test !hasproperty(direct_one.core_program, :proposal_drives)
    @test !hasproperty(direct_one.core_program, :proposal_constraints)
    @test !hasproperty(direct_one.core_program, :proposal_modifiers)

    # Partial mathematical operations are admitted only with an explicit
    # parameter-only prelaunch constraint.
    @parameters positive_scale = 2.0
    constrained_site = SiteBinding(:constrained_site)
    @named constrained = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            CellKind(:cell),
            MediumKind(:medium),
            HamiltonianTerm(
                :validated_log;
                domain = sites(:lattice),
                anchor = constrained_site,
                expression = log(positive_scale),
            ),
            Protocol(Sweep(); name = :main),
        )),
        parameters = [positive_scale],
    )
    constrained_executable = compile(
        complete(constrained);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    constrained_plan = constrained_executable.core_program.descriptor_plan
    @test length(constrained_plan.constraints) == 1
    @test CorePotts.validate_parameters(
        constrained_plan, Float64[2]
    ) === nothing
    @test_throws DomainError CorePotts.validate_parameters(
        constrained_plan, Float64[-1]
    )

    @parameters probability = 0.5 lower = -1.0 upper = 1.0 deviation = 0.25
    stochastic_expression =
        draw(Bernoulli(probability), DrawKey(:coin)) +
        draw(Uniform(lower, upper), DrawKey(:interval)) +
        draw(Normal(0.0, deviation), DrawKey(:gaussian))
    @named stochastic_domains = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            CellKind(:stochastic_cell),
            MediumKind(:stochastic_medium),
            ProposalDrive(:validated_draws, stochastic_expression),
            Protocol(Sweep(); name = :main),
        )),
        parameters = [probability, lower, upper, deviation],
    )
    stochastic_executable = compile(
        complete(stochastic_domains);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    stochastic_plan =
        stochastic_executable.core_program.descriptor_plan
    @test sum(
        length(group.instances) for group in stochastic_plan.constraints
    ) == 4
    @test CorePotts.validate_parameters(
        stochastic_plan, Float64[0.5, -1, 1, 0.25]
    ) === nothing
    @test_throws DomainError CorePotts.validate_parameters(
        stochastic_plan, Float64[-0.1, -1, 1, 0.25]
    )
    @test_throws DomainError CorePotts.validate_parameters(
        stochastic_plan, Float64[1.1, -1, 1, 0.25]
    )
    @test_throws DomainError CorePotts.validate_parameters(
        stochastic_plan, Float64[0.5, 1, -1, 0.25]
    )
    @test_throws DomainError CorePotts.validate_parameters(
        stochastic_plan, Float64[0.5, -1, 1, 0]
    )

    @variables unsafe_state
    unsafe_kind = CellKind(:unsafe_kind)
    unsafe_site = SiteBinding(:unsafe_site)
    @named unsafe = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            unsafe_kind,
            MediumKind(:unsafe_medium),
            SiteState(
                unsafe_state;
                initial = 1.0,
                owner = unsafe_kind,
                lifecycle = ClearOnOwnershipChange(),
            ),
            HamiltonianTerm(
                :unsafe_sqrt;
                domain = sites(:lattice),
                anchor = unsafe_site,
                expression = sqrt(unsafe_state),
            ),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [unsafe_state],
    )
    unsafe_error = try
        compile(
            complete(unsafe);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch error
        error
    end
    @test unsafe_error isa PottsToolkit.PottsValidationError
    @test any(
        diagnostic ->
            diagnostic.kind === :runtime_dependent_partial_operation,
        unsafe_error.diagnostics,
    )

    inspection = inspect(single, Kernels())
    @test inspection.descriptors == single.reports.descriptors
    @test !hasproperty(single.core_program.descriptor_plan, :activity)
    @test !hasproperty(single.core_program.descriptor_plan, :field)
    @test !hasproperty(single.core_program.descriptor_plan, :relationships)
end

@testset "G2 local Hamiltonian equivalence" begin
    cell = CellKind(:equivalence_cell)
    medium = MediumKind(:equivalence_medium)
    site = SiteBinding(:energy_site)
    @named equivalence = PottsSystem(statements = StatementSet((
        Lattice(
            (4, 4);
            relations = (proposal = VonNeumann(), contact = Moore()),
        ),
        cell,
        medium,
        Volume(cell; target = 4.0, strength = 2.0),
        ContactEnergy([(cell ↔ medium) => 3.0]),
        HamiltonianTerm(
            :site_energy_with_offset;
            domain = sites(:lattice),
            anchor = site,
            expression = 5.0 * occupancy(cell, site) + 99.0,
        ),
        Protocol(Sweep(); name = :main),
    )))
    executable = compile(
        complete(equivalence);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    program = executable.core_program
    plan = program.descriptor_plan
    @test plan.occurrence_count == 3
    roles = [
        descriptor.role
        for group in plan.groups
        for descriptor in group.launch.instances
        if descriptor.role isa CorePotts.HamiltonianRole
    ]
    @test any(role -> role.domain isa CorePotts.CellEnergyDomainPlan, roles)
    @test any(role -> role.domain isa CorePotts.ContactEnergyDomainPlan, roles)
    @test any(role -> role.domain isa CorePotts.SiteEnergyDomainPlan, roles)
    @test only(filter(
        role -> role.affected isa CorePotts.IncidentContactsAffectedPlan,
        roles,
    )).affected.maximum == 8

    ownership = zeros(Int32, 4, 4)
    ownership[2:3, 2:3] .= 1
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
    )
    runtime = CorePotts.initialize_program(
        program,
        initial,
        program.parameter_defaults,
        UInt64(0x42),
        UInt32(1),
    )

    # Deliberately independent full-energy oracle. It does not call a compiled
    # evaluator, affected-anchor plan, or any production delta implementation.
    moore_offsets = Tuple(
        (row, column)
        for row in -1:1 for column in -1:1
        if !(row == 0 && column == 0)
    )
    function global_energy(labels)
        volume = count(==(Int32(1)), labels)
        energy = 2.0 * (volume - 4.0)^2
        energy += 5.0 * volume + 99.0 * length(labels)
        contacts_seen = Set{Tuple{Int, Int}}()
        linear = LinearIndices(labels)
        for site_index in CartesianIndices(labels)
            for offset in moore_offsets
                neighbor = CartesianIndex(
                    mod1(site_index[1] + offset[1], size(labels, 1)),
                    mod1(site_index[2] + offset[2], size(labels, 2)),
                )
                edge = minmax(linear[site_index], linear[neighbor])
                edge in contacts_seen && continue
                push!(contacts_seen, edge)
                labels[site_index] == labels[neighbor] || (energy += 3.0)
            end
        end
        return energy
    end

    function proposal_context(source, target, attempt)
        return CorePotts._ProposalEvaluationContext(
            runtime,
            source,
            target,
            @inbounds(runtime.ownership[target]),
            @inbounds(runtime.ownership[source]),
            attempt,
            0,
        )
    end
    contributions = zeros(Float64, length(plan.source_table))
    before_ownership = copy(runtime.ownership)
    before_volumes = copy(runtime.volumes)
    checked = 0
    for target in CartesianIndices(ownership)
        for offset in ((-1, 0), (1, 0), (0, -1), (0, 1))
            source = CartesianIndex(
                mod1(target[1] + offset[1], size(ownership, 1)),
                mod1(target[2] + offset[2], size(ownership, 2)),
            )
            runtime.ownership[target] == runtime.ownership[source] && continue
            checked += 1
            context = proposal_context(source, target, checked)
            CorePotts.evaluate_hamiltonian_contributions!(
                contributions, plan, context
            )
            local_delta = CorePotts.fold_hamiltonian_contributions(
                plan, contributions
            )
            after = copy(ownership)
            after[target] = ownership[source]
            @test local_delta ≈ global_energy(after) - global_energy(ownership)
            @test runtime.ownership == before_ownership
            @test runtime.volumes == before_volumes
        end
    end
    @test checked > 0

    context = proposal_context(CartesianIndex(2, 2), CartesianIndex(1, 2), 99)
    CorePotts.evaluate_hamiltonian_contributions!(contributions, plan, context)
    canonical = CorePotts.fold_hamiltonian_contributions(plan, contributions)
    reordered = CorePotts.DescriptorExecutionPlan(
        reverse(plan.groups),
        plan.state_layout,
        plan.workspace_layout,
        plan.constraints,
        plan.source_table,
        plan.occurrence_count,
        plan.fingerprint,
        plan.domain_resources,
    )
    reordered_contributions = similar(contributions)
    CorePotts.evaluate_hamiltonian_contributions!(
        reordered_contributions, reordered, context
    )
    @test reordered_contributions == contributions
    @test CorePotts.fold_hamiltonian_contributions(
        reordered, reordered_contributions
    ) == canonical

    _hamiltonian_contribution_allocations(contributions, plan, context)
    @test _hamiltonian_contribution_allocations(
        contributions, plan, context
    ) == 0
    @test Core.Compiler.return_type(
        CorePotts.fold_hamiltonian_contributions,
        Tuple{typeof(plan), typeof(contributions)},
    ) === Float64

    function structural_types(statement_name, anchor_name)
        local_anchor = SiteBinding(anchor_name)
        @named structural = PottsSystem(statements = StatementSet((
            Lattice((3, 3)),
            CellKind(:structural_cell),
            MediumKind(:structural_medium),
            HamiltonianTerm(
                statement_name;
                domain = sites(:lattice),
                anchor = local_anchor,
                expression = 2.0 * occupancy(
                    CellKind(:structural_cell), local_anchor
                ) + 7.0,
            ),
            Protocol(Sweep(); name = :structural_protocol),
        )))
        compiled = compile(
            complete(structural);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        descriptor = only(CorePotts.descriptor_launch(
            only(compiled.core_program.descriptor_plan.groups)
        ).instances)
        return (
            typeof(descriptor),
            typeof(descriptor.role),
            typeof(descriptor.evaluator.expression),
        )
    end
    @test structural_types(:first_energy, :first_anchor) ==
          structural_types(:renamed_energy, :renamed_anchor)
end
