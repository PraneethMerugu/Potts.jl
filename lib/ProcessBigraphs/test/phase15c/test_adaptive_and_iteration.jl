@testset "Phase 15.C reactive activation and explicit iteration" begin
    scale = TimeScale(1)
    schema = BranchSchema(
        trigger=LeafSchema(Int; default=0, update_law=:add),
        copied=LeafSchema(Int; default=0, update_law=:replace),
        converged=LeafSchema(Int; default=0, update_law=:replace),
        bounded=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:C15IterationFixture, schema; scale) do builder, stores
        trigger = mount!(builder, :trigger, C15Producer())
        schedule!(builder, trigger, Every(Duration(1, scale)))
        attach!(builder, trigger, (out=stores.trigger,))
        copy_step = mount!(builder, :copy, C15ReactiveCopy())
        attach!(builder, copy_step, (
            input=stores.trigger,
            out=stores.copied,
        ))
        converge_step = mount!(builder, :converge, C15Converge())
        schedule!(builder, converge_step, After(converge_step))
        attach!(builder, converge_step, (
            state=stores.converged,
            out=stores.converged,
        ))
        bounded_step = mount!(builder, :bounded, C15Bounded())
        attach!(builder, bounded_step, (out=stores.bounded,))
        iteration!(
            builder,
            :convergence,
            (converge_step,);
            mode=:convergent,
            max_iterations=4,
            watch=(stores.converged,),
        )
        iteration!(
            builder,
            Symbol("bounded-region"),
            (bounded_step,);
            mode=:bounded,
            max_iterations=3,
        )
    end
    compiled = compile(model)
    @test length(iteration_regions(compiled)) == 2
    @test !isempty(execution_plan_fingerprint(compiled))
    runtime = initialize_runtime(compiled, SerialExecutor())
    run_until!(runtime, LogicalTime(1, scale))
    @test current_snapshot(runtime)[path("copied")] == 1
    @test current_snapshot(runtime)[path("converged")] == 2
    @test current_snapshot(runtime)[path("bounded")] == 3
    @test length(only(event_trace(runtime)).iterations) == 2
    @test commit_id(current_snapshot(runtime)) == 1

    @test_throws ModelValidationError compose(
        :C15CycleFixture, schema; scale) do builder, stores
        trigger = mount!(builder, :trigger, C15Producer())
        schedule!(builder, trigger, Every(Duration(1, scale)))
        attach!(builder, trigger, (out=stores.trigger,))
        a = mount!(builder, :a, C15Bounded())
        b = mount!(builder, :b, C15Bounded())
        schedule!(builder, a, After(b))
        schedule!(builder, b, After(a))
        attach!(builder, a, (out=stores.bounded,))
        attach!(builder, b, (out=stores.bounded,))
    end
end
