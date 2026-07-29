import ProcessBigraphs as PB

function _cnv_reduced_state(; division=false)
    labels = zeros(UInt32, 8, 8, 8)
    labels[2:4, 2:4, 2:3] .= UInt32(1)
    labels[6:7, 6:7, 4:5] .= UInt32(2)
    labels[6, 6, 3] = UInt32(3)
    if division
        labels .= UInt32(0)
        labels[1:5, 1:5, 1:3] .= UInt32(1)
    end
    capacity = 10
    types = zeros(UInt8, capacity)
    types[1] = division ? CorePotts.CNV_STALK : CorePotts.CNV_TIP
    if !division
        types[2] = CorePotts.CNV_RPE
        types[3] = CorePotts.CNV_BRM
    end
    target_volume = zeros(Float64, capacity)
    target_surface = zeros(Float64, capacity)
    target_volume[1] = 35
    target_surface[1] = 70
    target_volume[2] = 67
    target_surface[2] = 120
    target_volume[3] = 1
    normoxia = zeros(UInt32, capacity)
    normoxia[2] = UInt32(801)
    (
        labels=labels,
        cell_types=types,
        target_volume=target_volume,
        volume_strength=zeros(Float64, capacity),
        target_surface=target_surface,
        surface_strength=zeros(Float64, capacity),
        normoxia_timer=normoxia,
        hypoxia_timer=zeros(UInt32, capacity),
        link_a=UInt32[],
        link_b=UInt32[],
        link_strength=Float64[],
        link_target=Float64[],
        link_maximum=Float64[],
        link_active=UInt8[],
    )
end

function _cnv_biology_result(state; mcs, oxygen, rpe_vegf, mmp)
    inputs = (
        :labels => state.labels,
        :cell_types => state.cell_types,
        :target_volume => state.target_volume,
        :target_surface => state.target_surface,
        :normoxia_timer => state.normoxia_timer,
        :hypoxia_timer => state.hypoxia_timer,
        :oxygen => oxygen,
        :rpe_vegf => rpe_vegf,
        :mmp => mmp,
        :link_a => state.link_a,
        :link_b => state.link_b,
        :link_target => state.link_target,
        :link_maximum => state.link_maximum,
        :link_active => state.link_active,
    )
    prototypes = (
        :labels_out => state.labels,
        :cell_types_out => state.cell_types,
        :target_volume_out => state.target_volume,
        :target_surface_out => state.target_surface,
        :normoxia_timer_out => state.normoxia_timer,
        :hypoxia_timer_out => state.hypoxia_timer,
        :link_target_out => state.link_target,
        :link_maximum_out => state.link_maximum,
    )
    outputs = tuple(map(prototypes) do pair
        name, value = pair
        schema = PB.LeafSchema(
            eltype(value);
            shape=size(value),
            default=copy(value),
            update_law=:replace,
        )
        name => (PB.path(String(name)), schema)
    end...)
    scale = PB.TimeScale(216, 1, :second)
    context = PB.InvocationContext(
        "cnv-biology",
        "fixture-$mcs",
        PB.LogicalTime(mcs - 1, scale),
        PB.LogicalTime(mcs, scale),
        PB.Duration(1, scale),
        nothing,
        outputs,
        PB.ModelRNGContext(
            "cnv-fixture",
            PB.NormalizedRootSeed(902),
            "cnv-biology",
            PB.LogicalTime(mcs, scale),
            "fixture-$mcs",
        ),
    )
    PB.invoke(
        CorePotts.CNV2012BiologyStep(),
        PB.PortView(UInt64(0), "fixture", inputs),
        context,
    )
end

function _cnv_payload(result, name)
    target = PB.path(String(name))
    only(delta.payload for delta in result.deltas if delta.target == target)
end

@testset "CNV source trace and generated startup" begin
    state = CorePotts.cnv2012_initial_state()
    @test size(state.labels) == (40, 40, 35)
    @test maximum(state.labels) == UInt32(5151)
    @test count(!iszero, state.cell_types) == 4978
    @test count(==(CorePotts.CNV_VASCULAR), state.cell_types) == 36
    @test count(==(CorePotts.CNV_RPE), state.cell_types) == 100
    @test count(==(CorePotts.CNV_POS), state.cell_types) == 16
    @test count(==(CorePotts.CNV_PIS), state.cell_types) == 25
    @test count(==(CorePotts.CNV_TIP), state.cell_types) == 1
    @test count(==(CorePotts.CNV_BRM), state.cell_types) == 3200
    @test count(==(CorePotts.CNV_NONSTICK), state.cell_types) == 1600
    @test length(state.link_a) == 1138
    @test all(state.link_active .== UInt8(1))
    @test all(state.link_target .<= state.link_maximum)

    @test CorePotts.cnv2012_chemotaxis_response(
        CorePotts.CNV_TIP, :EC_VEGF, 1.0, 2.0) == 12000.0
    @test CorePotts.cnv2012_chemotaxis_response(
        CorePotts.CNV_VASCULAR, :EC_VEGF, 1.0, 2.0) == 5000.0
    @test CorePotts.cnv2012_chemotaxis_response(
        CorePotts.CNV_TIP, :EC_VEGF, 1.0, 2.0;
        endothelial_contact=true) == 0.0
    @test CorePotts.cnv2012_chemotaxis_response(
        CorePotts.CNV_RPE, :RPE_VEGF, 1.0, 2.0) == 0.0
end

@testset "CNV lifecycle and degradation microfixtures" begin
    state = _cnv_reduced_state()
    oxygen = fill(80.0, size(state.labels))
    oxygen[6:7, 6:7, 4:5] .= 10.0
    rpe_vegf = fill(0.1, size(state.labels))
    mmp = zeros(Float64, size(state.labels))
    mmp[6, 6, 3] = 2.0
    result = _cnv_biology_result(
        state; mcs=400, oxygen, rpe_vegf, mmp)
    types = _cnv_payload(result, :cell_types_out)
    target_volume = _cnv_payload(result, :target_volume_out)
    @test types[1] == CorePotts.CNV_STALK
    @test types[2] == CorePotts.CNV_HRPE
    @test target_volume[3] == 0.85
    @test result.diagnostics.transitions == 2

    dividing = _cnv_reduced_state(division=true)
    division_result = _cnv_biology_result(
        dividing;
        mcs=1,
        oxygen=fill(80.0, size(dividing.labels)),
        rpe_vegf=fill(0.1, size(dividing.labels)),
        mmp=zeros(Float64, size(dividing.labels)),
    )
    divided_labels = _cnv_payload(division_result, :labels_out)
    divided_types = _cnv_payload(division_result, :cell_types_out)
    @test division_result.diagnostics.divisions == 1
    @test count(==(CorePotts.CNV_STALK), divided_types) == 2
    @test Set(filter(!iszero, divided_labels)) == Set(UInt32[1, 2])

    death_state = _cnv_reduced_state()
    death_state.cell_types[1] = CorePotts.CNV_STALK
    death_result = _cnv_biology_result(
        death_state;
        mcs=1001,
        oxygen=fill(80.0, size(death_state.labels)),
        rpe_vegf=zeros(Float64, size(death_state.labels)),
        mmp=zeros(Float64, size(death_state.labels)),
    )
    @test _cnv_payload(death_result, :target_volume_out)[1] == 0.0
    @test _cnv_payload(death_result, :target_surface_out)[1] == 0.0
    @test death_result.diagnostics.deaths >= 1
end

@testset "CNV managed four-field assembly" begin
    state = _cnv_reduced_state()
    scale = PB.TimeScale(216, 1, :second)
    composite = CorePotts.cnv2012_native_composite(state)
    observations = CorePotts.cnv2012_observation_plan(scale)
    executor = PB.SerialExecutor(
        root_seed=902, observation_plan=observations)
    runtime = PB.initialize_runtime(composite, executor)
    PB.run_until!(runtime, PB.LogicalTime(1, scale))
    snapshot = PB.current_snapshot(runtime)
    @test snapshot.time.tick == 1
    @test all(isfinite, snapshot[PB.path("oxygen")])
    @test sum(snapshot[PB.path("ec_vegf")]) > 0
    @test sum(snapshot[PB.path("mmp")]) > 0
    @test length(PB.observation_records(runtime)) == 1
    owners = Set(activation.owner
        for record in PB.event_trace(runtime)
        for activation in record.activations)
    @test Set(("cnv-cpm", "cnv-biology", "cnv-field-exchange")) <= owners

    checkpoint = PB.encode_checkpoint(PB.logical_checkpoint(runtime))
    resumed = PB.restore(composite, executor, checkpoint)
    PB.run_until!(runtime, PB.LogicalTime(2, scale))
    PB.run_until!(resumed, PB.LogicalTime(2, scale))
    @test PB.materialize(PB.current_snapshot(runtime)) ==
        PB.materialize(PB.current_snapshot(resumed))

    failing = PB.initialize_runtime(
        composite,
        PB.SerialExecutor(
            root_seed=902,
            failure_injection=PB.FailureInjection(
                :reactive_step_execution),
        ),
    )
    stable = PB.snapshot_fingerprint(PB.current_snapshot(failing))
    @test_throws PB.ProcessBigraphError PB.run_until!(
        failing, PB.LogicalTime(1, scale))
    @test PB.snapshot_fingerprint(PB.current_snapshot(failing)) == stable
    @test PB.current_snapshot(failing).time.tick == 0
end
