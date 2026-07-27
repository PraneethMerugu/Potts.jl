using ACSets

function phase15a_fixture(order=("fast", "slow"))
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
        nested=BranchSchema(
            marker=LeafSchema(String; default="ready", update_law=:replace),
        ),
    )
    declarations = Dict(
        "fast" => ProcessDeclaration("fast", PB0Increment(1),
            FixedSchedule(Duration(1, scale))),
        "slow" => ProcessDeclaration("slow", PB0Increment(10),
            FixedSchedule(Duration(2, scale))),
    )
    processes = tuple((declarations[id] for id in order)...)
    bindings = tuple((
        binding
        for id in order
        for binding in (
            PortBinding(id, :state, path("state")),
            PortBinding(id, :increment, path("state")),
        )
    )...)
    StaticComposite(schema, Dict(), scale; processes, bindings)
end

function phase15a_payloads(composite)
    owners = tuple(composite.processes..., composite.steps...)
    laws = tuple((declaration.id => declaration.law for declaration in owners)...)
    continuations =
        tuple((declaration.id => declaration.continuation for declaration in owners)...)
    laws, continuations
end

@testset "Phase 15.A canonical ProcessBigraph ACSet" begin
    composite = phase15a_fixture()
    model = canonical_model(composite)
    structure = canonical_structure(model)

    @test structure isa ProcessBigraphACSet
    @test ACSets.nparts(structure, :Composite) == 1
    @test ACSets.nparts(structure, :StoreNode) == 4
    @test ACSets.nparts(structure, :StoreContainment) == 3
    @test ACSets.nparts(structure, :Actor) == 2
    @test ACSets.nparts(structure, :Process) == 2
    @test ACSets.nparts(structure, :Step) == 0
    @test ACSets.nparts(structure, :Port) == 4
    @test ACSets.nparts(structure, :Binding) == 4
    @test length(structural_fingerprint(model)) == 64

    compiled = compile_composite(composite)
    @test structural_fingerprint(compiled) == structural_fingerprint(model)
    @test structural_epoch(compiled).version ==
        ProcessBigraphs.PROCESS_BIGRAPH_ACSET_VERSION
    @test compiled.plan isa ExecutionPlan
    @test StaticComposite ∉ fieldtypes(CompiledComposite)
    @test all(type -> !(type <: ACSets.ACSet), fieldtypes(ExecutionPlan))

    locations = structural_provenance(compiled).entries
    @test length(first.(locations)) == length(unique(first.(locations)))
    @test "composite:root" in first.(locations)
    @test "actor:fast" in first.(locations)
    @test "actor:slow" in first.(locations)
    @test count(pair -> first(last(pair)) === :store, locations) == 4
    @test count(pair -> first(last(pair)) === :port, locations) == 4
    @test count(pair -> first(last(pair)) === :binding, locations) == 4
end

@testset "Phase 15.A row, declaration, and authoring-path invariance" begin
    forward = phase15a_fixture(("fast", "slow"))
    reversed = phase15a_fixture(("slow", "fast"))
    canonical = canonical_model(forward)
    renumbered =
        ProcessBigraphs._canonical_model(reversed; reverse_insertion=true)
    canonical_rows = canonical_structure(canonical)
    renumbered_rows = canonical_structure(renumbered)

    canonical_fast = only(ACSets.incident(canonical_rows, "fast", :actor_id))
    renumbered_fast = only(ACSets.incident(renumbered_rows, "fast", :actor_id))
    @test canonical_fast != renumbered_fast
    @test structural_fingerprint(canonical) == structural_fingerprint(renumbered)

    typed = compile_composite(forward)
    row_permuted = compile_composite(renumbered)
    @test model_fingerprint(typed) == model_fingerprint(row_permuted)
    @test structural_provenance(typed).entries ==
        structural_provenance(row_permuted).entries

    laws, continuations = phase15a_payloads(forward)
    direct = compile_composite(canonical_rows;
        initial_values=forward.initial_values, laws, continuations)
    @test model_fingerprint(direct) == model_fingerprint(typed)
    @test structural_fingerprint(direct) == structural_fingerprint(typed)

    typed_runtime = initialize_runtime(typed)
    direct_runtime = initialize_runtime(direct)
    run_until!(typed_runtime, LogicalTime(4, TimeScale(1)))
    run_until!(direct_runtime, LogicalTime(4, TimeScale(1)))
    @test materialize(current_snapshot(typed_runtime)) ==
        materialize(current_snapshot(direct_runtime))
    @test event_count(typed_runtime) == event_count(direct_runtime) == 4
end

@testset "Phase 15.A frozen epoch and fail-closed corruption" begin
    composite = phase15a_fixture()
    model = canonical_model(composite)
    structure = canonical_structure(model)
    laws, continuations = phase15a_payloads(composite)
    compiled = compile_composite(structure;
        initial_values=composite.initial_values, laws, continuations)

    actor = only(ACSets.incident(structure, "fast", :actor_id))
    ACSets.set_subpart!(structure, actor, :law_version, "corrupt")
    @test_throws ProcessBigraphError compile_composite(structure;
        initial_values=composite.initial_values, laws, continuations)
    @test structural_fingerprint(model) == structural_fingerprint(compiled)

    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(2, TimeScale(1)))
    @test current_snapshot(runtime)[path("state")] == 12
    @test current_snapshot(runtime)[path("nested", "marker")] == "ready"

    detached = canonical_structure(compiled)
    root_store = only(ACSets.incident(detached, Path(), :store_path))
    ACSets.set_subpart!(detached, root_store, :schema_kind, :corrupt)
    @test structural_fingerprint(compiled) != structural_fingerprint(detached)
    @test structural_fingerprint(canonical_structure(compiled)) ==
        structural_fingerprint(compiled)
end
