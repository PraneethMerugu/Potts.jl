@testset "external descriptor operation stays open" begin
    expression = CorePotts.OperationExpression(
        CorePotts.operation_callable(Val(:add), v"1.0.0"),
        CorePotts.OperationExpression(
            ExternalSquareOperation(),
            CorePotts.ParameterExpression(2.0f0, 1),
        ),
        CorePotts.LiteralExpression(1.0f0),
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    context = CorePotts.EvaluatorProbeContext(
        Float32[3],
        (
            source_site = Int32(1),
            target_site = Int32(1),
            source_cell = Int32(1),
            target_cell = Int32(1),
            source_kind = Int16(1),
            target_kind = Int16(1),
            is_extension = false,
            is_retraction = false,
        ),
    )
    descriptor = CorePotts.ProposalDescriptor(
        evaluator,
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
    )
    @test CorePotts.evaluate_static(descriptor.evaluator, context) == 10.0f0
    @test Core.Compiler.return_type(
        CorePotts.evaluate_static,
        Tuple{typeof(descriptor.evaluator), typeof(context)},
    ) === Float32
    @test Core.Compiler.return_type(
        CorePotts._compiled_evaluate_static,
        Tuple{typeof(descriptor.evaluator), typeof(context)},
    ) === Float32
    output = zeros(Float32, 4)
    backend = CorePotts.KernelAbstractions.CPU()
    kernel = CorePotts.descriptor_probe_kernel!(backend)
    kernel(output, descriptor, context; ndrange = length(output))
    CorePotts.KernelAbstractions.synchronize(backend)
    @test output == fill(10.0f0, 4)
    greater_equal = CorePotts.operation_callable(
        Val(:greater_equal), v"1.0.0"
    )
    @test greater_equal(Int64(4), 4.0f0)
    @test !greater_equal(Int64(3), 4.0f0)
    @test @inferred(greater_equal(Int64(4), 4.0f0)) === true
end

@testset "public storage layouts canonicalize representation banks" begin
    function state_schema(name, element_type)
        return CorePotts.StateBlockSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            :site,
            element_type,
            (2,),
            2,
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
    function workspace_schema(name, element_type)
        return CorePotts.WorkspaceSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            element_type,
            (2,),
            2,
            Array,
            :zero,
            :proposal,
            :bounded_write,
            :adapt_storage,
            :qualified,
            false,
        )
    end
    function banks_by_representation(layout)
        return Dict(
            CorePotts.handle_representation(entry.handle) =>
                CorePotts.handle_bank(entry.handle)
            for entry in layout.entries
        )
    end

    states = [
        state_schema(:float64_state, Float64),
        state_schema(:float32_state, Float32),
    ]
    workspaces = [
        workspace_schema(:float64_workspace, Float64),
        workspace_schema(:float32_workspace, Float32),
    ]
    @test banks_by_representation(CorePotts.StateLayout(states)) ==
          banks_by_representation(CorePotts.StateLayout(reverse(states)))
    @test banks_by_representation(CorePotts.WorkspaceLayout(workspaces)) ==
          banks_by_representation(CorePotts.WorkspaceLayout(reverse(workspaces)))

    state_layouts = map((1, 32, 1024)) do count
        CorePotts.StateLayout([
            state_schema(Symbol(:state_, index), Float64)
            for index in 1:count
        ])
    end
    workspace_layouts = map((1, 32, 1024)) do count
        CorePotts.WorkspaceLayout([
            workspace_schema(Symbol(:workspace_, index), Float64)
            for index in 1:count
        ])
    end
    @test allequal(typeof(layout) for layout in state_layouts)
    @test allequal(typeof(layout) for layout in workspace_layouts)

    states = map(CorePotts.allocate_auxiliary_state, state_layouts)
    workspaces = map(CorePotts.allocate_runtime_workspaces, workspace_layouts)
    @test allequal(typeof(state) for state in states)
    @test allequal(typeof(workspace) for workspace in workspaces)
    @test all(length(state.banks) == 1 for state in states)
    @test all(length(workspace.banks) == 1 for workspace in workspaces)
    @test size(CorePotts.state_block(
        last(states), last(last(state_layouts).entries).handle
    ).values) == (2,)
    @test size(CorePotts.workspace_block(
        last(workspaces), last(last(workspace_layouts).entries).handle
    ).values) == (2,)

    plans = map(state_layouts, workspace_layouts) do state_layout, workspace_layout
        CorePotts.DescriptorExecutionPlan(
            (),
            state_layout,
            workspace_layout,
            (),
            Any[],
            0,
            "count-stable-storage-plan",
            CorePotts.HamiltonianDomainResources(2, 0),
        )
    end
    programs = map(plans) do plan
        test_program(
            CorePotts.SequentialProgramEngine(); descriptor_plan = plan
        )
    end
    reports = map(CorePotts.program_capability_report, programs)
    @test allequal(typeof(report) for report in reports)
    runtimes = map(programs, states) do program, descriptor_state
        initial = CorePotts.ProgramInitialState(
            zeros(Int32, program.shape),
            Int16[];
            scalar_type = Float64,
            descriptor_state,
        )
        CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0x726), UInt32(1)
        )
    end
    @test allequal(typeof(program) for program in programs)
    @test allequal(typeof(runtime) for runtime in runtimes)
end

@testset "relationship declarations grow data rather than specialization" begin
    function repeated_relationship_program(count)
        schema = CorePotts.RelationshipStoreSchema(1, 1)
        return test_program(
            CorePotts.SequentialProgramEngine();
            relationships = ntuple(_ -> schema, count),
        )
    end
    programs = map(repeated_relationship_program, (1, 32, 1024))
    @test allequal(typeof(program.relationships) for program in programs)
    @test allequal(typeof(program) for program in programs)
    @test all(
        length(program.relationships.banks) == 1 for program in programs
    )

    runtimes = map(programs) do program
        initial = CorePotts.ProgramInitialState(
            zeros(Int32, program.shape),
            Int16[];
            scalar_type = Float64,
            relationships = fill(nothing, length(program.relationships)),
        )
        CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0x725), UInt32(1)
        )
    end
    @test allequal(typeof(runtime.relationships) for runtime in runtimes)
    @test all(
        length(runtime.relationships.banks) == 1 for runtime in runtimes
    )

    packed = map(
        runtime -> CorePotts.Adapt.adapt(Array, runtime.relationships), runtimes
    )
    @test allequal(typeof(storage) for storage in packed)
    @test allequal(typeof(only(storage.banks)) for storage in packed)
    @test length(last(packed)) == 1024
    final_view = last(packed)[1024]
    @test length(final_view.active) == 1
    @test size(final_view.incident_edges) == (1, 0)
end
