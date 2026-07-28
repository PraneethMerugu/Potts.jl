using OrdinaryDiffEqTsit5: Tsit5

import ProcessBigraphs as PB

include(joinpath(
    @__DIR__,
    "..",
    "..",
    "ProcessBigraphs",
    "test",
    "fixtures",
    "independent_custom_field_adapter.jl",
))
using .IndependentCustomFieldAdapterFixture:
    independent_custom_field_declaration

function _merks_constraint_state(neighbor_labels)
    owners = fill(MediumOwner(1), 5, 5)
    center = CartesianIndex(3, 3)
    owners[center] = CellOwner(1)
    for (offset, label) in zip(
        CorePotts._MERKS_CLOCKWISE_OFFSETS, neighbor_labels)
        owners[center + CartesianIndex(offset)] =
            iszero(label) ? MediumOwner(1) : CellOwner(label)
    end
    state = LogicalPottsState(
        owners,
        CellCapacity(max(maximum(neighbor_labels; init=0), 1));
        cell_types=Dict(
            CellID(id) => CellTypeID(1)
            for id in unique(neighbor_labels)
            if !iszero(id)
        ),
        medium_domains=(MediumID(1),),
    )
    domain = CartesianDomain((5, 5))
    linear = LinearIndices((5, 5))
    proposal = CopyProposal(
        linear[center],
        linear[center + CartesianIndex(1, 0)],
        CellOwner(1),
        MediumOwner(1),
    )
    state, domain, proposal
end

@testset "Phase 16.G Merks source-mechanism microfixtures" begin
    constraint = CorePotts.MerksLocalConnectivityConstraint()

    contiguous = _merks_constraint_state(
        UInt32[0, 1, 1, 1, 0, 0, 0, 0])
    one_cell_split = _merks_constraint_state(
        UInt32[1, 0, 1, 0, 0, 0, 0, 0])
    two_cell_exception = _merks_constraint_state(
        UInt32[1, 0, 1, 0, 2, 0, 0, 0])
    three_cells = _merks_constraint_state(
        UInt32[1, 0, 1, 0, 2, 0, 3, 0])

    @test is_allowed(constraint, contiguous[3], contiguous[1], contiguous[2])
    @test !is_allowed(
        constraint, one_cell_split[3], one_cell_split[1], one_cell_split[2])
    @test is_allowed(
        constraint,
        two_cell_exception[3],
        two_cell_exception[1],
        two_cell_exception[2],
    )
    @test !is_allowed(
        constraint, three_cells[3], three_cells[1], three_cells[2])

    parameters = PB.semantic_parameters(CorePotts.Merks2006CPMStep())
    @test parameters.source_target_length_sites == 50.0
    @test parameters.corepotts_target_major_axis_rms == 12.5
    @test parameters.source_chemotaxis_gamma == 1000.0
    @test parameters.corepotts_chemotaxis_log_bias == 20.0
    @test parameters.ambiguity_profile.corepotts_elongation_strength ==
        16 * parameters.ambiguity_profile.source_length_strength

    source_labels = reshape(
        UInt32[0, 1, 0, 2, 0, 0], 2, 3)
    context = PB.InvocationContext(
        "secretion",
        "fixture",
        PB.LogicalTime(0, PB.TimeScale(2)),
        PB.LogicalTime(0, PB.TimeScale(2)),
        PB.Duration(0, PB.TimeScale(2)),
        nothing,
        (
            :forcing => (
                PB.path("forcing"),
                PB.LeafSchema(Float64;
                    shape=(2, 3), default=zeros(2, 3),
                    update_law=:replace),
            ),
            :decay_weights => (
                PB.path("decay_weights"),
                PB.LeafSchema(Float64;
                    shape=(2, 3), default=ones(2, 3),
                    update_law=:replace),
            ),
        ),
        PB.ModelRNGContext(
            "model", PB.NormalizedRootSeed(0),
            "secretion", PB.LogicalTime(0, PB.TimeScale(2)), "fixture"),
    )
    view = PB.PortView(
        UInt64(0), "fixture", (:labels => source_labels,))
    result = PB.invoke(
        CorePotts.Merks2006SecretionStep(), view, context)
    forcing = only(delta.payload for delta in result.deltas
        if delta.target == PB.path("forcing"))
    weights = only(delta.payload for delta in result.deltas
        if delta.target == PB.path("decay_weights"))
    @test all(forcing .== map(
        label -> iszero(label) ? 0.0 : 1.8e-4, source_labels))
    @test all(weights .== map(
        label -> iszero(label) ? 1.0 : 0.0, source_labels))
end

function _reduced_merks_labels()
    CorePotts.merks2006_initial_labels(
        shape=(20, 20),
        cells=2,
        central_extent=16,
        target_area_sites=5.0,
        seed=11,
    )
end

@testset "Phase 16.G canonical startup and native assembly" begin
    canonical = CorePotts.merks2006_initial_labels()
    @test size(canonical) == (500, 500)
    @test maximum(canonical) == UInt32(282)
    @test length(unique(filter(!iszero, canonical))) == 282

    labels = _reduced_merks_labels()
    scale = PB.TimeScale(2, 1, :second)
    composite = CorePotts.merks2006_native_composite(
        labels; root_seed=11)
    observation_plan = CorePotts.merks2006_observation_plan(scale)
    executor = PB.SerialExecutor(
        root_seed=11,
        observation_plan=observation_plan,
    )
    runtime = PB.initialize_runtime(composite, executor)
    PB.run_until!(runtime, PB.LogicalTime(14, scale))
    before_mcs = PB.current_snapshot(runtime)
    @test before_mcs[PB.path("labels")] == labels
    @test sum(before_mcs[PB.path("field")]) > 0
    @test all(record ->
        all(activation -> activation.owner != "merks-cpm",
            record.activations), PB.event_trace(runtime))

    cut = PB.encode_checkpoint(PB.logical_checkpoint(runtime))
    resumed = PB.restore(composite, executor, cut)
    PB.run_until!(runtime, PB.LogicalTime(30, scale))
    PB.run_until!(resumed, PB.LogicalTime(30, scale))
    @test PB.materialize(PB.current_snapshot(resumed)) ==
        PB.materialize(PB.current_snapshot(runtime))

    activations = [
        activation.owner
        for record in PB.event_trace(runtime)
        for activation in record.activations
    ]
    @test count(==("merks-cpm"), activations) == 2
    @test count(==("merks-secretion-mask"), activations) == 2
    records = PB.observation_records(runtime)
    @test map(record -> record.payload.mcs, records) == (1, 2)
    @test all(record -> record.payload.cell_count == 2, records)
    @test all(record -> record.payload.disconnected_cells == 0, records)
    @test all(record -> record.payload.occupied_sites > 0, records)
    @test all(record -> record.payload.field_mass > 0, records)
    @test PB.observation_records(resumed) == records
    snapshot = PB.current_snapshot(runtime)
    @test minimum(snapshot[PB.path("field")]) >= 0
    @test all(isfinite, snapshot[PB.path("field")])
    @test Set(snapshot[PB.path("labels")]) <=
        Set((UInt32(0), UInt32(1), UInt32(2)))

    failing = PB.initialize_runtime(
        composite,
        PB.SerialExecutor(
            root_seed=11,
            failure_injection=PB.FailureInjection(
                :reactive_step_execution),
        ),
    )
    PB.run_until!(failing, PB.LogicalTime(14, scale))
    stable = PB.snapshot_fingerprint(PB.current_snapshot(failing))
    @test_throws PB.ProcessBigraphError PB.run_until!(
        failing, PB.LogicalTime(15, scale))
    @test PB.snapshot_fingerprint(PB.current_snapshot(failing)) == stable
    @test PB.current_snapshot(failing).time.tick == 14
end

@testset "Phase 16.G arbitrary SciML field assembly" begin
    labels = _reduced_merks_labels()
    scale = PB.TimeScale(2, 1, :second)
    values = zeros(Float64, size(labels))
    problem = PB.BoundedCartesianFieldProblem(
        "merks-sciml-field",
        values;
        spacing=(2.0, 2.0),
        diffusion=0.1,
        decay=1.8e-4,
        tick_duration=2.0,
        time_scale=scale,
    )
    declaration = PB.sciml_field_declaration(
        problem,
        Tsit5();
        algorithm_id="ordinarydiffeq-tsit5",
        solver_options=(abstol=1.0e-9, reltol=1.0e-9),
    )
    composite = CorePotts.merks2006_composite(
        labels,
        declaration;
        time_scale=scale,
        root_seed=11,
        initial_field=values,
    )
    runtime = PB.initialize_runtime(
        composite, PB.SerialExecutor(root_seed=11))
    PB.run_until!(runtime, PB.LogicalTime(15, scale))
    snapshot = PB.current_snapshot(runtime)
    @test snapshot.time.tick == 15
    @test sum(snapshot[PB.path("field")]) > 0
    @test all(isfinite, snapshot[PB.path("field")])
    @test any(
        activation -> activation.owner == "merks-cpm",
        last(PB.event_trace(runtime)).activations,
    )
end

@testset "Phase 16.G independent external field assembly" begin
    labels = _reduced_merks_labels()
    scale = PB.TimeScale(2, 1, :second)
    values = zeros(Float64, size(labels))
    problem = PB.BoundedCartesianFieldProblem(
        "merks-independent-field",
        values;
        spacing=(2.0, 2.0),
        diffusion=0.1,
        decay=1.8e-4,
        tick_duration=2.0,
        time_scale=scale,
    )
    declaration = independent_custom_field_declaration(
        problem; substeps_per_tick=4)
    composite = CorePotts.merks2006_composite(
        labels,
        declaration;
        time_scale=scale,
        root_seed=11,
        initial_field=values,
    )
    runtime = PB.initialize_runtime(
        composite, PB.SerialExecutor(root_seed=11))
    PB.run_until!(runtime, PB.LogicalTime(15, scale))
    snapshot = PB.current_snapshot(runtime)
    @test snapshot.time.tick == 15
    @test sum(snapshot[PB.path("field")]) > 0
    @test all(isfinite, snapshot[PB.path("field")])
    @test any(
        activation -> activation.owner == "merks-cpm",
        last(PB.event_trace(runtime)).activations,
    )
end
