import ProcessBigraphs: StaticComposite, ProcessDeclaration, PortBinding,
    compile_composite

function c15_open_component(definition, amount)
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    process = ProcessDeclaration(
        "increment",
        C15Add(amount),
        FixedSchedule(Duration(1, scale)),
    )
    open_composite(
        definition,
        StaticComposite(
            schema, Dict(), scale;
            processes=(process,),
            bindings=(
                PortBinding("increment", :state, path("state")),
                PortBinding("increment", :out, path("state")),
            ),
        );
        endpoints=(
            BoundaryEndpoint(:state, path("state");
                role=:bidirectional),
        ),
    )
end

function c15_open_fork_join(; grouping=:nary)
    components = (
        CompositeMount(:left, c15_open_component("left", 1)),
        CompositeMount(:middle, c15_open_component("middle", 2)),
        CompositeMount(:right, c15_open_component("right", 3)),
    )
    mounts = if grouping === :nary
        mount_group(components...)
    elseif grouping === :left
        mount_group(mount_group(components[1], components[2]), components[3])
    else
        mount_group(components[1], mount_group(components[2], components[3]))
    end
    compose_open(
        "c15-authoring-root";
        mounts,
        junctions=(
            JunctionSpec(
                "shared-junction",
                path("shared"),
                (
                    EndpointRef(:left, :state),
                    EndpointRef(:middle, :state),
                    EndpointRef(:right, :state),
                ),
            ),
        ),
        exports=(
            CompositeExport(
                :shared, "shared-junction";
                role=:bidirectional),
        ),
    )
end

@testset "Phase 15.C six-path authoring equivalence" begin
    nary = c15_open_fork_join(grouping=:nary)
    grouped = c15_open_fork_join(grouping=:left)
    right_grouped = c15_open_fork_join(grouping=:right)
    payloads = nary.model.payloads

    compiled_paths = (
        ordinary_typed=compile_composite(canonical_model(nary)),
        direct_acset=compile_composite(
            canonical_structure(nary);
            initial_values=payloads.initial_values,
            laws=payloads.laws,
            continuations=payloads.continuations,
        ),
        nary_composition=compile_composite(nary),
        pairwise_grouping=compile_composite(grouped),
        structured_cospan=compile_composite(
            structured_cospan(nary);
            initial_values=payloads.initial_values,
            laws=payloads.laws,
            continuations=payloads.continuations,
        ),
        annotated_wiring=compile_composite(
            annotated_wiring_diagram(nary)),
    )
    reference = compiled_paths.ordinary_typed
    for (name, compiled) in pairs(compiled_paths)
        @test structural_fingerprint(compiled) ==
            structural_fingerprint(reference)
        @test model_fingerprint(compiled) == model_fingerprint(reference)
        @test execution_plan_fingerprint(compiled) ==
            execution_plan_fingerprint(reference)
        @test structural_provenance(compiled).entries ==
            structural_provenance(reference).entries
        @test snapshot_fingerprint(compiled.initial) ==
            snapshot_fingerprint(reference.initial)
    end
    @test structural_fingerprint(right_grouped) ==
        structural_fingerprint(nary)

    executor = SerialExecutor(root_seed=44)
    runtimes = (; (
        name => initialize_runtime(compiled, executor)
        for (name, compiled) in pairs(compiled_paths)
    )...)
    for runtime in runtimes
        run_until!(runtime, LogicalTime(3, TimeScale(1)))
    end
    reference_runtime = runtimes.ordinary_typed
    for runtime in runtimes
        @test snapshot_fingerprint(current_snapshot(runtime)) ==
            snapshot_fingerprint(current_snapshot(reference_runtime))
        @test event_trace(runtime) == event_trace(reference_runtime)
        @test encode_checkpoint(logical_checkpoint(runtime)) ==
            encode_checkpoint(logical_checkpoint(reference_runtime))
    end
    @test current_snapshot(reference_runtime)[path("shared")] == 18
end
