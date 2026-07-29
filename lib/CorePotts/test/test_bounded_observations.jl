function _bounded_observation_fixture(;
        table_cell_capacity::Integer = 4,
        table_schedule = EveryMCS(),
        geometry_schedule = AtMCS((1, 2)))
    requester = ComponentIdentity(
        :bounded_observation_test, v"1.0.0", :test)
    property_names = (
        :polarity_x, :polarity_y, :a, :s, :rac,
        :force_magnitude, :force_x, :force_y,
        :focal_strength, :hill_coefficient,
        :alignment_fraction)
    schema = PropertySchema(map(
        property -> PropertyDescriptor(
            property, Float32,
            ConstantInitializer(0.0f0); requester),
        property_names)...)
    owners = fill(MediumOwner(1), 5, 5)
    owners[2, 2] = owners[2, 3] = CellOwner(1)
    owners[4, 4] = owners[4, 5] = CellOwner(3)
    logical = LogicalPottsState(
        owners, CellCapacity(4);
        cell_types = Dict(
            CellID(1) => CellTypeID(2),
            CellID(3) => CellTypeID(4)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    for (offset, property) in enumerate(property_names)
        values = property_values(logical, property)
        values[1] = Float32(offset)
        values[3] = Float32(100 + offset)
    end
    spacing = (1.0, 1.0)
    domain = CartesianDomain((5, 5); spacing)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    boundary_tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), boundary_relation)
    connectivity = first_shell_relation(
        ConnectivityRole(), Val(2); spacing)
    moment_tracker = UnwrappedMomentTracker(
        connectivity; number_type = Float64)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker; moment_tracker)
    bindings = (
        x_self_polarity = :polarity_x,
        y_self_polarity = :polarity_y,
        a = :a,
        s = :s,
        rac = :rac,
        f = :force_magnitude,
        f_x = :force_x,
        f_y = :force_y,
        fpp = :focal_strength,
        f_coef = :hill_coefficient,
        p_frac = :alignment_fraction,
    )
    table = CorePotts.BoundedCellTableObservation(
        :cell_records, compiled;
        bindings, cell_capacity = table_cell_capacity)
    geometry = CorePotts.LosslessOwnershipSnapshot(
        :geometry, compiled)
    table_observation = CorePotts.PhaseObservation(
        :cell_records, table;
        schedule = table_schedule,
        schema = CorePotts.RecordSchema(
            :cell_record_v1, v"1.0.0"))
    geometry_observation = CorePotts.PhaseObservation(
        :geometry, geometry;
        schedule = geometry_schedule,
        schema = CorePotts.RecordSchema(
            :ownership_snapshot_v1, v"1.0.0"))
    proposal = first_shell_relation(
        ProposalRole(), Val(2); spacing)
    potts = init_scientific(
        compiled, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0);
        seed = 0x14b0,
        moment_tracker)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(
            table_observation, geometry_observation))
    coupled = CorePotts.init_coupled(
        potts, plan, CorePotts.CoupledState())
    return (;
        logical, compiled, domain, moment_tracker,
        bindings, table, geometry,
        table_observation, geometry_observation,
        coupled)
end

@testset "coupled dynamics bounded cell table has exact schema and ordering" begin
    fixture = _bounded_observation_fixture()
    table = fixture.table
    @test component_identity(table).category ==
        :bounded_cell_table_observation
    @test CorePotts.bounded_cell_table_workspace_bytes(
        table.workspace) > 0
    adapted = CorePotts.Adapt.adapt(Array, table)
    @test adapted.workspace.cell_id isa Vector{UInt32}
    @test adapted.workspace.coordinates isa
        Tuple{Vector{Float64}, Vector{Float64}}
    @test all(column -> column isa Vector{Float32},
        adapted.workspace.columns)

    before = logical_snapshot(fixture.coupled.potts.state.potts)
    launches = fixture.coupled.potts.plan.metrics.launches
    synchronizations =
        fixture.coupled.potts.plan.metrics.host_synchronizations
    @test CorePotts.execute_bounded_observation!(
        fixture.coupled, fixture.table_observation,
        UInt64(1)) === fixture.coupled
    @test fixture.coupled.potts.plan.metrics.launches ==
        launches + 2
    @test fixture.coupled.potts.plan.metrics.host_synchronizations ==
        synchronizations + 1
    @test fixture.coupled.potts.plan.metrics.device_to_host_transfers == 0
    after = logical_snapshot(
        fixture.coupled.potts.state.potts)
    @test after._owners == before._owners
    @test after._active == before._active
    @test after._generations == before._generations
    for property in propertynames(before.properties.columns)
        @test property_values(after, property) ==
            property_values(before, property)
    end

    record = only(fixture.coupled.observations.records)
    @test record.observation == :cell_records
    @test record.mcs == 1
    @test record.publication_epoch == 1
    publication = record.value
    @test publication.target_mcs == 1
    @test publication.source_mcs == 0
    @test publication.publication_epoch == 1
    @test publication.semantic_seed == UInt64(0x14b0)
    @test publication.active_row_count == 2
    @test publication.capacity == 4
    @test publication.cell_id == UInt32[1, 3]
    @test publication.cell_generation == UInt64[0, 0]
    @test publication.cell_type == UInt32[2, 4]
    @test publication.coordinates.x == [1.5, 3.5]
    @test publication.coordinates.y == [2.0, 4.0]
    columns = CorePotts.cell_table_columns(publication)
    @test propertynames(columns) == (
        :cell_id, :x, :y,
        :x_self_polarity, :y_self_polarity,
        :a, :s, :rac, :f, :f_x, :f_y,
        :fpp, :f_coef, :p_frac)
    @test columns.x_self_polarity == Float32[1, 101]
    @test columns.p_frac == Float32[11, 111]
    @test fixture.coupled.observations.last_published[
        :cell_records] == 1
    @test fixture.coupled.observations.publication_epochs[
        :cell_records] == 1

    @test CorePotts.execute_bounded_observation!(
        fixture.coupled, fixture.table_observation,
        UInt64(1)) === fixture.coupled
    @test length(fixture.coupled.observations.records) == 1
    @test fixture.coupled.potts.plan.metrics.launches ==
        launches + 2
end

@testset "coupled dynamics bounded cell table fails before publication" begin
    insufficient = _bounded_observation_fixture(
        table_cell_capacity = 2)
    before = logical_snapshot(
        insufficient.coupled.potts.state.potts)
    @test_throws ArgumentError CorePotts.execute_bounded_observation!(
        insufficient.coupled,
        insufficient.table_observation, UInt64(1))
    @test isempty(insufficient.coupled.observations.records)
    @test isempty(
        insufficient.coupled.observations.last_published)
    @test isempty(
        insufficient.coupled.observations.publication_epochs)
    after = logical_snapshot(
        insufficient.coupled.potts.state.potts)
    @test after._owners == before._owners
    @test after._active == before._active
    for property in propertynames(before.properties.columns)
        @test property_values(after, property) ==
            property_values(before, property)
    end
    key = only(insufficient.table.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(key) ==
        CorePotts.CELL_TABLE_OBSERVATION_CAPACITY
    @test CorePotts._coupled_process_failing_cell(key) ==
        UInt32(3)

    nonfinite = _bounded_observation_fixture()
    execution = scientific_execution(nonfinite.compiled)
    execution.core.properties.rac[1] = Float32(NaN)
    @test_throws ArgumentError CorePotts.execute_bounded_observation!(
        nonfinite.coupled,
        nonfinite.table_observation, UInt64(1))
    @test isempty(nonfinite.coupled.observations.records)
    key = only(nonfinite.table.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(key) ==
        CorePotts.CELL_TABLE_OBSERVATION_NONFINITE_PROPERTY
    @test CorePotts._coupled_process_failing_cell(key) ==
        UInt32(1)
end

@testset "coupled dynamics lossless ownership snapshot is exact and independent" begin
    fixture = _bounded_observation_fixture()
    @test component_identity(fixture.geometry).category ==
        :lossless_ownership_snapshot
    @test CorePotts.execute_bounded_observation!(
        fixture.coupled, fixture.geometry_observation,
        UInt64(1)) === fixture.coupled
    record = only(fixture.coupled.observations.records)
    publication = record.value
    core = fixture.compiled.potts.storage
    @test publication.target_mcs == 1
    @test publication.source_mcs == 0
    @test publication.publication_epoch == 1
    @test publication.domain.dims == (5, 5)
    @test publication.domain.spacing == (1.0, 1.0)
    @test publication.owner_tags == core.ownership.tags
    @test publication.owner_ids == core.ownership.ids
    @test publication.active == core.active
    @test publication.cell_generations == core.generations
    @test publication.cell_types == core.cell_types
    publication.owner_ids[1] = typemax(UInt32)
    @test core.ownership.ids[1] != typemax(UInt32)

    insufficient = CorePotts.LosslessOwnershipSnapshot(
        :small_geometry, fixture.compiled;
        maximum_sites = 24, maximum_cells = 4)
    observation = CorePotts.PhaseObservation(
        :small_geometry, insufficient;
        schedule = OnceAtMCS(1))
    @test_throws ArgumentError CorePotts.execute_bounded_observation!(
        fixture.coupled, observation, UInt64(1))
    @test !haskey(
        fixture.coupled.observations.last_published,
        :small_geometry)
end

@testset "coupled dynamics bounded observations preserve three-dimensional semantics" begin
    requester = ComponentIdentity(
        :bounded_observation_3d_test, v"1.0.0", :test)
    schema = PropertySchema(PropertyDescriptor(
        :signal, Float32, ConstantInitializer(0.0f0);
        requester))
    owners = fill(MediumOwner(1), 3, 3, 3)
    owners[2, 2, 2] = CellOwner(1)
    owners[2, 2, 3] = CellOwner(1)
    logical = LogicalPottsState(
        owners, CellCapacity(2);
        cell_types = Dict(CellID(1) => CellTypeID(2)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    property_values(logical, :signal)[1] = 3.5f0
    spacing = (1.0, 1.0, 1.0)
    domain = CartesianDomain((3, 3, 3); spacing)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(3); spacing)
    boundary_tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), boundary_relation)
    connectivity = first_shell_relation(
        ConnectivityRole(), Val(3); spacing)
    moment_tracker = UnwrappedMomentTracker(
        connectivity; number_type = Float64)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker; moment_tracker)
    table = CorePotts.BoundedCellTableObservation(
        :cell_records_3d, compiled;
        bindings = (signal = :signal,))
    geometry = CorePotts.LosslessOwnershipSnapshot(
        :geometry_3d, compiled)
    table_observation = CorePotts.PhaseObservation(
        :cell_records_3d, table;
        schedule = OnceAtMCS(1))
    geometry_observation = CorePotts.PhaseObservation(
        :geometry_3d, geometry;
        schedule = OnceAtMCS(1))
    proposal = first_shell_relation(
        ProposalRole(), Val(3); spacing)
    potts = init_scientific(
        compiled, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0);
        seed = 0x14b3, moment_tracker)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(
            table_observation, geometry_observation))
    coupled = CorePotts.init_coupled(
        potts, plan, CorePotts.CoupledState())

    @test table.coordinate_names == (:x, :y, :z)
    @test length(table.workspace.coordinates) == 3
    @test CorePotts.execute_bounded_observation!(
        coupled, table_observation, UInt64(1)) === coupled
    table_publication = only(coupled.observations.records).value
    columns = CorePotts.cell_table_columns(table_publication)
    @test propertynames(columns) ==
        (:cell_id, :x, :y, :z, :signal)
    @test columns.cell_id == UInt32[1]
    @test columns.signal == Float32[3.5]
    @test all(coordinate -> length(coordinate) == 1,
        values(table_publication.coordinates))

    empty!(coupled.observations.records)
    @test CorePotts.execute_bounded_observation!(
        coupled, geometry_observation, UInt64(1)) === coupled
    geometry_publication =
        only(coupled.observations.records).value
    @test size(geometry_publication.owner_tags) == (3, 3, 3)
    @test size(geometry_publication.owner_ids) == (3, 3, 3)
    @test geometry_publication.domain.dims == (3, 3, 3)
end

@testset "coupled dynamics bounded observation restart does not duplicate or skip" begin
    fixture = _bounded_observation_fixture(
        table_schedule = AtMCS((1, 2)),
        geometry_schedule = AtMCS((1, 2)))
    step!(fixture.coupled)
    @test fixture.coupled.observations.completed_mcs == 1
    @test length(fixture.coupled.observations.records) == 2
    checkpoint = capture_checkpoint(fixture.coupled)
    restored = restore_checkpoint(
        checkpoint, fixture.coupled)
    @test isempty(restored.observations.records)
    @test restored.observations.last_published ==
        Dict(:cell_records => UInt64(1),
             :geometry => UInt64(1))
    @test restored.observations.publication_epochs ==
        Dict(:cell_records => UInt64(1),
             :geometry => UInt64(1))

    step!(fixture.coupled)
    step!(restored)
    @test fixture.coupled.observations.completed_mcs == 2
    @test restored.observations.completed_mcs == 2
    @test restored.observations.last_published ==
        fixture.coupled.observations.last_published
    @test restored.observations.publication_epochs ==
        fixture.coupled.observations.publication_epochs
    @test all(record -> record.mcs == 2,
        restored.observations.records)
    @test all(record -> record.publication_epoch == 2,
        restored.observations.records)
    @test length(restored.observations.records) == 2
    @test capture_checkpoint(restored).state_fingerprint ==
        capture_checkpoint(fixture.coupled).state_fingerprint
end
