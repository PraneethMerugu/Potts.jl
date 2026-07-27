@testset "Phase 15.C reactive activation and explicit iteration" begin
    scale = TimeScale(1)
    schema = BranchSchema(
        trigger=LeafSchema(Int; default=0, update_law=:add),
        copied=LeafSchema(Int; default=0, update_law=:replace),
        converged=LeafSchema(Int; default=0, update_law=:replace),
        bounded=LeafSchema(Int; default=0, update_law=:add),
    )
    trigger = ProcessDeclaration(
        "trigger",
        C15Producer(),
        FixedSchedule(Duration(1, scale)),
    )
    copy_step = StepDeclaration("copy", C15ReactiveCopy())
    converge_step = StepDeclaration(
        "converge", C15Converge(); dependencies=("converge",))
    bounded_step = StepDeclaration("bounded", C15Bounded())
    bindings = (
        PortBinding("trigger", :out, path("trigger")),
        PortBinding("copy", :input, path("trigger")),
        PortBinding("copy", :out, path("copied")),
        PortBinding("converge", :state, path("converged")),
        PortBinding("converge", :out, path("converged")),
        PortBinding("bounded", :out, path("bounded")),
    )
    regions = (
        IterationRegion(
            "convergence",
            ("converge",);
            mode=:convergent,
            max_iterations=4,
            watch_paths=(path("converged"),),
        ),
        IterationRegion(
            "bounded-region",
            ("bounded",);
            mode=:bounded,
            max_iterations=3,
        ),
    )
    compiled = compile_composite(StaticComposite(
        schema, Dict(), scale;
        processes=(trigger,),
        steps=(copy_step, converge_step, bounded_step),
        bindings,
        iteration_regions=regions,
    ))
    @test length(iteration_regions(compiled)) == 2
    @test !isempty(execution_plan_fingerprint(compiled))
    runtime = initialize_runtime(compiled, SerialExecutor())
    run_until!(runtime, LogicalTime(1, scale))
    @test current_snapshot(runtime)[path("copied")] == 1
    @test current_snapshot(runtime)[path("converged")] == 2
    @test current_snapshot(runtime)[path("bounded")] == 3
    @test length(only(event_trace(runtime)).iterations) == 2
    @test commit_id(current_snapshot(runtime)) == 1

    undeclared_cycle = StaticComposite(
        schema, Dict(), scale;
        processes=(trigger,),
        steps=(
            StepDeclaration("a", C15Bounded(); dependencies=("b",)),
            StepDeclaration("b", C15Bounded(); dependencies=("a",)),
        ),
        bindings=(
            PortBinding("trigger", :out, path("trigger")),
            PortBinding("a", :out, path("bounded")),
            PortBinding("b", :out, path("bounded")),
        ),
    )
    @test_throws ProcessBigraphError compile_composite(undeclared_cycle)
end
