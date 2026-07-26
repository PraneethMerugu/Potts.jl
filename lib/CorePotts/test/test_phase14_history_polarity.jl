using KernelAbstractions
using SciMLBase: step!
using StaticArrays: SVector

function _history_polarity_fixture(::Type{T} = Float32) where {
        T <: AbstractFloat}
    requester = ComponentIdentity(
        :history_polarity_test, v"1.0.0", :test)
    properties = (:direction_x, :direction_y, :speed)
    schema = PropertySchema(map(
        property -> PropertyDescriptor(
            property, T, ConstantInitializer(zero(T));
            requester),
        properties)...)
    owners = fill(MediumOwner(1), 5, 5)
    owners[2, 2] = owners[2, 3] = CellOwner(1)
    logical = LogicalPottsState(
        owners, CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    spacing = (one(T), one(T))
    domain = CartesianDomain((5, 5); spacing)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    boundary_tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), boundary_relation)
    connectivity = first_shell_relation(
        ConnectivityRole(), Val(2); spacing)
    moment_tracker = UnwrappedMomentTracker(
        connectivity; number_type = T)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker; moment_tracker)
    declaration = CorePotts.CellHistory(
        :centroid_history;
        source = :compiled_unwrapped_centroid,
        length = 5,
        initial = CorePotts.MissingUntilFull())
    initial = [SVector{2, T}(zero(T), zero(T))]
    generations = [CellGeneration(0)]
    history = CorePotts.initialize_cell_history(
        declaration, initial, generations)
    return (;
        logical, compiled, declaration, initial,
        generations, history)
end

function _fill_linear_history!(
        history, generations;
        active = Bool[true])
    T = eltype(eltype(history.values))
    for mcs in 0:4
        sample = SVector{2, T}(T(mcs), T(2mcs))
        CorePotts.sample_history!(
            history, [sample], active, generations, mcs)
    end
    return history
end

@testset "Phase 14 history declarations realize backend workspaces" begin
    fixture = _history_polarity_fixture()
    state = CorePotts.CoupledState(
        histories = (fixture.history,))
    sample_law = CorePotts.CentroidHistorySample(
        :sample_centroid, :centroid_history)
    sample = CorePotts.realize_coupled_process(
        sample_law, state, fixture.compiled)
    @test sample isa
        CorePotts.CentroidHistorySampleExecution
    @test CorePotts.canonical_process_law(
        sample) == sample_law
    @test sample.workspace.samples isa
        Vector{SVector{2, Float32}}

    direction_law =
        CorePotts.HistoryDisplacementDirection(
            :polarity_from_history,
            :centroid_history;
            outputs = (
                :direction_x, :direction_y),
            magnitude = :speed,
            lag = CorePotts.Lag(4))
    direction = CorePotts.realize_coupled_process(
        direction_law, state, fixture.compiled)
    @test direction isa
        CorePotts.HistoryDisplacementDirectionExecution
    @test CorePotts.canonical_process_law(
        direction) == direction_law
    @test direction.workspace.candidate_magnitude isa
        Vector{Float32}
end

@testset "Phase 14 centroid history sampling is exact and portable" begin
    fixture = _history_polarity_fixture()
    process = CorePotts.CentroidHistorySample(
        :sample_centroid, fixture.history, fixture.compiled)
    @test component_identity(process).category ==
        :centroid_history_sample
    @test CorePotts.process_reads(process) == (
        (:ownership, :lattice),
        (:tracker, :unwrapped_coordinate_moments))
    @test CorePotts.process_writes(process) ==
        ((:history, :centroid_history),)
    @test CorePotts.centroid_history_workspace_bytes(
        process.workspace) > 0
    adapted = CorePotts.Adapt.adapt(Array, process)
    @test adapted.workspace.samples isa
        Vector{SVector{2, Float32}}

    execution = scientific_execution(fixture.compiled)
    moments = execution.trackers.moments
    volume = execution.trackers.finite_volumes[1]
    expected = SVector(
        moments.coordinate_sums[1][1] / volume,
        moments.coordinate_sums[2][1] / volume)
    @test CorePotts.apply_centroid_history_sample!(
        fixture.history, fixture.compiled,
        process, 1) === fixture.history
    @test CorePotts.history_value(
        fixture.history, CellID(1), CellGeneration(0),
        CorePotts.Lag(0)) == expected
    @test fixture.history.latest_sample_mcs == 1

    portable_history = CorePotts.initialize_cell_history(
        fixture.declaration, fixture.initial,
        fixture.generations)
    portable_process = CorePotts.CentroidHistorySample(
        :sample_centroid, portable_history,
        fixture.compiled)
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    @test CorePotts.apply_centroid_history_sample!(
        plan, fixture.compiled, portable_history,
        portable_process, 1) === portable_history
    @test CorePotts.history_value(
        portable_history, CellID(1), CellGeneration(0),
        CorePotts.Lag(0)) == expected
    @test portable_history.values == fixture.history.values
    @test portable_history.heads == fixture.history.heads
    @test portable_history.fills == fixture.history.fills
    @test plan.metrics.launches == 3
    @test plan.metrics.host_to_device_transfers == 0
    @test plan.metrics.device_to_host_transfers == 0
    @test_throws ArgumentError CorePotts.apply_centroid_history_sample!(
        plan, fixture.compiled, portable_history,
        portable_process, -1)
end

@testset "Phase 14 lagged history direction matches Wang ordering" begin
    fixture = _history_polarity_fixture()
    _fill_linear_history!(
        fixture.history, fixture.generations)
    process = CorePotts.HistoryDisplacementDirection(
        :polarity_from_history,
        fixture.history, fixture.logical;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    @test component_identity(process).category ==
        :history_displacement_direction
    @test CorePotts.process_reads(process) ==
        ((:history, :centroid_history),)
    @test Set(CorePotts.process_writes(process)) == Set((
        (:cell_property, :direction_x),
        (:cell_property, :direction_y),
        (:cell_property, :speed)))

    candidate = deepcopy(fixture.logical)
    @test CorePotts.apply_history_displacement_direction!(
        candidate, fixture.logical, fixture.history,
        process) === candidate
    magnitude = Float32(4sqrt(5))
    @test property_values(candidate, :direction_x)[1] ≈
        inv(sqrt(5.0f0))
    @test property_values(candidate, :direction_y)[1] ≈
        2 / sqrt(5.0f0)
    @test property_values(candidate, :speed)[1] ≈ magnitude

    portable_history = CorePotts.initialize_cell_history(
        fixture.declaration, fixture.initial,
        fixture.generations)
    _fill_linear_history!(
        portable_history, fixture.generations)
    portable_process = CorePotts.HistoryDisplacementDirection(
        :polarity_from_history,
        portable_history, fixture.compiled;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    @test CorePotts.apply_history_displacement_direction!(
        plan, fixture.compiled, portable_history,
        portable_process) === fixture.compiled
    portable = logical_snapshot(fixture.compiled.potts)
    for property in (:direction_x, :direction_y, :speed)
        @test property_values(portable, property) ≈
            property_values(candidate, property)
    end
    @test plan.metrics.launches == 3
    @test plan.metrics.host_to_device_transfers == 0
    @test plan.metrics.device_to_host_transfers == 0
end

@testset "Phase 14 history direction failure is atomic" begin
    fixture = _history_polarity_fixture()
    CorePotts.sample_history!(
        fixture.history,
        [SVector(1.0f0, 2.0f0)],
        Bool[true], fixture.generations, 0)
    process = CorePotts.HistoryDisplacementDirection(
        :polarity_from_history,
        fixture.history, fixture.logical;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    candidate = deepcopy(fixture.logical)
    property_values(candidate, :direction_x)[1] = 11.0f0
    property_values(candidate, :direction_y)[1] = 12.0f0
    property_values(candidate, :speed)[1] = 13.0f0
    before = Tuple(copy(property_values(candidate, property))
        for property in (
            :direction_x, :direction_y, :speed))
    @test_throws ArgumentError CorePotts.apply_history_displacement_direction!(
        candidate, fixture.logical, fixture.history,
        process)
    after = Tuple(copy(property_values(candidate, property))
        for property in (
            :direction_x, :direction_y, :speed))
    @test after == before
    key = only(process.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(key) ==
        CorePotts.HISTORY_POLARITY_UNAVAILABLE
    @test CorePotts._coupled_process_failing_cell(key) ==
        UInt32(1)

    portable_fixture = _history_polarity_fixture()
    CorePotts.sample_history!(
        portable_fixture.history,
        [SVector(1.0f0, 2.0f0)],
        Bool[true], portable_fixture.generations, 0)
    portable_process = CorePotts.HistoryDisplacementDirection(
        :polarity_from_history,
        portable_fixture.history,
        portable_fixture.compiled;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    portable_execution =
        scientific_execution(portable_fixture.compiled)
    portable_execution.core.properties.direction_x[1] = 21.0f0
    portable_execution.core.properties.direction_y[1] = 22.0f0
    portable_execution.core.properties.speed[1] = 23.0f0
    portable_before = Tuple(copy(getproperty(
            portable_execution.core.properties, property))
        for property in (
            :direction_x, :direction_y, :speed))
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    @test_throws ArgumentError CorePotts.apply_history_displacement_direction!(
        plan, portable_fixture.compiled,
        portable_fixture.history, portable_process)
    portable_after = Tuple(copy(getproperty(
            portable_execution.core.properties, property))
        for property in (
            :direction_x, :direction_y, :speed))
    @test portable_after == portable_before

    zero_fixture = _history_polarity_fixture()
    for mcs in 0:4
        CorePotts.sample_history!(
            zero_fixture.history,
            [SVector(2.0f0, 3.0f0)],
            Bool[true], zero_fixture.generations, mcs)
    end
    zero_process = CorePotts.HistoryDisplacementDirection(
        :zero_displacement,
        zero_fixture.history, zero_fixture.logical;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    zero_candidate = deepcopy(zero_fixture.logical)
    CorePotts.apply_history_displacement_direction!(
        zero_candidate, zero_fixture.logical,
        zero_fixture.history, zero_process)
    @test property_values(
        zero_candidate, :direction_x) == Float32[0]
    @test property_values(
        zero_candidate, :direction_y) == Float32[0]
    @test property_values(
        zero_candidate, :speed) == Float32[0]
end

@testset "Phase 14 history direction is dimension-generic" begin
    requester = ComponentIdentity(
        :history_direction_3d_test, v"1.0.0", :test)
    properties = (:direction_x, :direction_y, :direction_z, :speed)
    schema = PropertySchema(map(
        property -> PropertyDescriptor(
            property, Float64,
            ConstantInitializer(0.0); requester),
        properties)...)
    owners = fill(MediumOwner(1), 3, 3, 3)
    owners[2, 2, 2] = CellOwner(1)
    logical = LogicalPottsState(
        owners, CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    declaration = CorePotts.CellHistory(
        :trajectory_3d;
        source = :position,
        length = 5,
        initial = CorePotts.MissingUntilFull())
    generations = [CellGeneration(0)]
    history = CorePotts.initialize_cell_history(
        declaration, [SVector(0.0, 0.0, 0.0)],
        generations)
    for mcs in 0:4
        sample = SVector(
            Float64(mcs), Float64(2mcs), Float64(2mcs))
        CorePotts.sample_history!(
            history, [sample], Bool[true],
            generations, mcs)
    end
    process = CorePotts.HistoryDisplacementDirection(
        :direction_from_trajectory,
        history, logical;
        outputs = (
            :direction_x, :direction_y, :direction_z),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    candidate = deepcopy(logical)
    CorePotts.apply_history_displacement_direction!(
        candidate, logical, history, process)
    @test property_values(candidate, :direction_x)[1] ≈ 1 / 3
    @test property_values(candidate, :direction_y)[1] ≈ 2 / 3
    @test property_values(candidate, :direction_z)[1] ≈ 2 / 3
    @test property_values(candidate, :speed)[1] ≈ 12
end

@testset "Phase 14 history processes compose, checkpoint, and replay" begin
    requester = ComponentIdentity(
        :history_plan_test, v"1.0.0", :test)
    properties = (:direction_x, :direction_y, :speed)
    schema = PropertySchema(map(
        property -> PropertyDescriptor(
            property, Float32,
            ConstantInitializer(0.0f0); requester),
        properties)...)
    owners = fill(CellOwner(1), 5, 5)
    logical = LogicalPottsState(
        owners, CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    spacing = (1.0f0, 1.0f0)
    closed = ntuple(
        _ -> AxisBoundary(ClosedBoundary()), 2)
    domain = CartesianDomain(
        (5, 5); spacing, boundaries = closed)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    boundary_tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), boundary_relation)
    connectivity = first_shell_relation(
        ConnectivityRole(), Val(2); spacing)
    moment_tracker = UnwrappedMomentTracker(
        connectivity; number_type = Float32)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker; moment_tracker)

    declaration = CorePotts.CellHistory(
        :trajectory;
        source = :compiled_unwrapped_centroid,
        length = 5,
        initial = CorePotts.MissingUntilFull())
    generations = [CellGeneration(0)]
    history = CorePotts.initialize_cell_history(
        declaration, [SVector(0.0f0, 0.0f0)],
        generations)
    for mcs in 0:4
        CorePotts.sample_history!(
            history, [SVector(0.0f0, 0.0f0)],
            Bool[true], generations, mcs)
    end
    sampler = CorePotts.CentroidHistorySample(
        :sample_position, history, compiled)
    direction = CorePotts.HistoryDisplacementDirection(
        :direction_from_trajectory, history, compiled;
        outputs = (:direction_x, :direction_y),
        magnitude = :speed,
        lag = CorePotts.Lag(4))
    proposal = first_shell_relation(
        ProposalRole(), Val(2); spacing)
    potts = init_scientific(
        compiled, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0);
        seed = 0x14b1, moment_tracker)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(
            :sample_position,
            CorePotts.Sample(sampler)),
        CorePotts.CoupledPhase(
            :derive_direction,
            CorePotts.Update(direction)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase())
    coupled = CorePotts.init_coupled(
        potts, plan,
        CorePotts.CoupledState(
            histories = (history,)))
    portable = CorePotts.init_coupled(
        deepcopy(potts), plan,
        deepcopy(coupled.state);
        execution_mode =
            CorePotts.PortableCoupledExecution())

    @test step!(coupled) === coupled
    @test step!(portable) === portable
    @test coupled.mcs == 1
    @test portable.mcs == 1
    @test history.latest_sample_mcs == 1
    @test CorePotts.history_value(
        history, CellID(1), CellGeneration(0),
        CorePotts.Lag(0)) == SVector(2.5f0, 2.5f0)
    completed = logical_state(coupled.potts)
    @test property_values(
        completed, :direction_x)[1] ≈ inv(sqrt(2.0f0))
    @test property_values(
        completed, :direction_y)[1] ≈ inv(sqrt(2.0f0))
    @test property_values(
        completed, :speed)[1] ≈ 2.5f0sqrt(2.0f0)
    report = CorePotts.coupled_backend_report(
        plan, coupled.state,
        coupled.potts.plan.capabilities)
    @test Set(row.capability for row in report.rows) ==
        Set((
            :cell_history,
            :centroid_history_sample,
            :history_displacement_direction))
    @test report.executable
    @test portable.potts.plan.metrics.launches >= 6
    @test CorePotts.capture_checkpoint(
        portable).state_fingerprint ==
        CorePotts.capture_checkpoint(
            coupled).state_fingerprint

    checkpoint = CorePotts.capture_checkpoint(coupled)
    restored = CorePotts.restore_checkpoint(
        checkpoint, coupled)
    @test step!(coupled) === coupled
    @test step!(restored) === restored
    @test CorePotts.capture_checkpoint(
        coupled).state_fingerprint ==
        CorePotts.capture_checkpoint(
            restored).state_fingerprint
    @test logical_state(restored.potts)._owners ==
        logical_state(coupled.potts)._owners
    for property in properties
        @test property_values(
            logical_state(restored.potts), property) ==
            property_values(
                logical_state(coupled.potts), property)
    end
end
