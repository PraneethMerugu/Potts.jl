function _polarity_force_fixture(::Type{T} = Float32) where {
        T <: AbstractFloat}
    requester = ComponentIdentity(
        :polarity_force_test, v"1.0.0", :test)
    properties = (
        :polarity_x, :polarity_y, :focal_strength,
        :alignment_fraction, :rac,
        :force_x, :force_y, :force_magnitude,
        :hill_coefficient)
    schema = PropertySchema(map(
        property -> PropertyDescriptor(
            property, T, ConstantInitializer(zero(T));
            requester),
        properties)...)
    owners = fill(MediumOwner(1), 6, 6)
    owners[2, 2] = owners[2, 3] = CellOwner(1)
    owners[3, 2] = owners[3, 3] = CellOwner(2)
    owners[6, 6] = CellOwner(3)
    logical = LogicalPottsState(
        owners, CellCapacity(3);
        cell_types = Dict(
            CellID(id) => CellTypeID(1) for id in 1:3),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    property_values(logical, :polarity_x) .= T[1, 0, 0]
    property_values(logical, :polarity_y) .= T[0, 1, 0]
    property_values(logical, :focal_strength) .=
        T[500, 1000, 1000]
    property_values(logical, :rac) .= T[0, 40, 80]
    spacing = (one(T), one(T))
    domain = CartesianDomain((6, 6); spacing)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    boundary_tracker =
        BoundaryMeasureTracker(BoundaryEdgeCount(), boundary_relation)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker)
    contact_relation = first_shell_relation(
        SpatialQueryRole(), Val(2); spacing)
    alignment = CorePotts.NeighborPolarityAlignment(
        :neighbor_alignment, logical, contact_relation;
        x = :polarity_x,
        y = :polarity_y,
        strength = :focal_strength,
        fraction = :alignment_fraction,
        strength_scale = T(1000),
        maximum_fraction = T(0.4))
    force = CorePotts.HillVectorForce(
        :protrusion_force, logical;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = T(40),
        maximum_force = T(10),
        exponent = 4,
        direction = -one(T))
    return (;
        logical, domain, boundary_tracker, compiled,
        contact_relation, alignment, force)
end

@testset "Phase 14 polarity declarations realize backend workspaces" begin
    fixture = _polarity_force_fixture()
    state = CorePotts.CoupledState()
    alignment_law =
        CorePotts.NeighborPolarityAlignment(
            :neighbor_alignment,
            fixture.contact_relation;
            x = :polarity_x,
            y = :polarity_y,
            strength = :focal_strength,
            fraction = :alignment_fraction,
            strength_scale = 1000.0f0,
            maximum_fraction = 0.4f0)
    alignment = CorePotts.realize_coupled_process(
        alignment_law, state, fixture.compiled)
    @test alignment isa
        CorePotts.NeighborPolarityAlignmentExecution
    @test CorePotts.canonical_process_law(
        alignment) == alignment_law
    @test alignment.workspace.candidate_x isa
        Vector{Float32}

    force_law = CorePotts.HillVectorForce(
        :protrusion_force;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 10.0f0,
        exponent = 4,
        direction = -1.0f0)
    force = CorePotts.realize_coupled_process(
        force_law, state, fixture.compiled)
    @test force isa
        CorePotts.HillVectorForceExecution
    @test CorePotts.canonical_process_law(
        force) == force_law
    @test force.workspace.candidate_x isa
        Vector{Float32}
end

@testset "Phase 14 neighbor polarity alignment is synchronous and exact" begin
    fixture = _polarity_force_fixture()
    candidate = deepcopy(fixture.logical)
    @test CorePotts.apply_neighbor_polarity_alignment!(
        candidate, fixture.logical, fixture.domain,
        fixture.alignment) === candidate
    x = property_values(candidate, :polarity_x)
    y = property_values(candidate, :polarity_y)
    fraction =
        property_values(candidate, :alignment_fraction)

    expected_first = Float32[0.8, 0.2]
    expected_first ./= sqrt(sum(abs2, expected_first))
    expected_second = Float32[0.4, 0.6]
    expected_second ./= sqrt(sum(abs2, expected_second))
    @test x[1] ≈ expected_first[1]
    @test y[1] ≈ expected_first[2]
    @test x[2] ≈ expected_second[1]
    @test y[2] ≈ expected_second[2]
    @test x[3] == 0.0f0
    @test y[3] == 0.0f0
    @test fraction == Float32[0.2, 0.4, 0.4]
    @test fixture.alignment.workspace.neighbor_count ==
        UInt32[1, 1, 0]
    @test size(fixture.alignment.workspace.adjacency) ==
        (1, 3)
    @test fixture.alignment.workspace.adjacency ==
        UInt32[2 1 0]

    packed = zeros(UInt32, 2, 34)
    CorePotts._alignment_set_adjacency!(packed, 1, 34)
    CorePotts._alignment_set_adjacency!(packed, 34, 1)
    @test CorePotts._alignment_adjacency_contains(
        packed, 1, 34)
    @test CorePotts._alignment_adjacency_contains(
        packed, 34, 1)
    @test !CorePotts._alignment_adjacency_contains(
        packed, 1, 33)

    clamped = deepcopy(fixture.logical)
    property_values(clamped, :focal_strength)[1] = 2000.0f0
    clamped_process = CorePotts.NeighborPolarityAlignment(
        :clamped_alignment, clamped,
        fixture.contact_relation;
        x = :polarity_x,
        y = :polarity_y,
        strength = :focal_strength,
        fraction = :alignment_fraction,
        strength_scale = 1000.0f0,
        maximum_fraction = 0.4f0)
    clamped_candidate = deepcopy(clamped)
    CorePotts.apply_neighbor_polarity_alignment!(
        clamped_candidate, clamped, fixture.domain,
        clamped_process)
    @test property_values(
        clamped_candidate, :alignment_fraction)[1] == 0.4f0
end

@testset "Phase 14 neighbor polarity portable path agrees and fails atomically" begin
    fixture = _polarity_force_fixture()
    host_candidate = deepcopy(fixture.logical)
    CorePotts.apply_neighbor_polarity_alignment!(
        host_candidate, fixture.logical, fixture.domain,
        fixture.alignment)
    portable_process = CorePotts.NeighborPolarityAlignment(
        :neighbor_alignment, fixture.compiled,
        fixture.contact_relation;
        x = :polarity_x,
        y = :polarity_y,
        strength = :focal_strength,
        fraction = :alignment_fraction,
        strength_scale = 1000.0f0,
        maximum_fraction = 0.4f0)
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    @test CorePotts.apply_neighbor_polarity_alignment!(
        plan, fixture.compiled,
        portable_process) === fixture.compiled
    @test CorePotts.synchronize_neighbor_polarity_status!(
        plan, portable_process) === portable_process
    portable = logical_snapshot(fixture.compiled.potts)
    for property in (
            :polarity_x, :polarity_y,
            :alignment_fraction)
        @test property_values(portable, property) ≈
            property_values(host_candidate, property)
    end
    @test plan.metrics.launches == 5
    @test plan.metrics.host_to_device_transfers == 0
    @test plan.metrics.device_to_host_transfers == 0

    failing = _polarity_force_fixture()
    failing_process = CorePotts.NeighborPolarityAlignment(
        :neighbor_alignment, failing.compiled,
        failing.contact_relation;
        x = :polarity_x,
        y = :polarity_y,
        strength = :focal_strength,
        fraction = :alignment_fraction,
        strength_scale = 1000.0f0,
        maximum_fraction = 0.4f0)
    execution = scientific_execution(failing.compiled)
    execution.core.properties.focal_strength[2] = -1.0f0
    before = Tuple(copy(getproperty(
            execution.core.properties, property))
        for property in (
            :polarity_x, :polarity_y,
            :alignment_fraction))
    failing_plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    CorePotts.apply_neighbor_polarity_alignment!(
        failing_plan, failing.compiled, failing_process)
    @test_throws ArgumentError CorePotts.synchronize_neighbor_polarity_status!(
        failing_plan, failing_process)
    after = Tuple(copy(getproperty(
            execution.core.properties, property))
        for property in (
            :polarity_x, :polarity_y,
            :alignment_fraction))
    @test after == before
    key = only(failing_process.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(key) ==
        CorePotts.NEIGHBOR_ALIGNMENT_NEGATIVE_STRENGTH
    @test CorePotts._coupled_process_failing_cell(key) ==
        UInt32(2)

    heterogeneous = _polarity_force_fixture()
    heterogeneous_process = CorePotts.NeighborPolarityAlignment(
        :neighbor_alignment, heterogeneous.compiled,
        heterogeneous.contact_relation;
        x = :polarity_x,
        y = :polarity_y,
        strength = :focal_strength,
        fraction = :alignment_fraction,
        strength_scale = 1000.0f0,
        maximum_fraction = 0.4f0)
    heterogeneous_execution =
        scientific_execution(heterogeneous.compiled)
    heterogeneous_execution.core.properties.polarity_x[1] =
        Float32(NaN)
    heterogeneous_execution.core.properties.focal_strength[2] =
        -1.0f0
    heterogeneous_plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    CorePotts.apply_neighbor_polarity_alignment!(
        heterogeneous_plan, heterogeneous.compiled,
        heterogeneous_process)
    @test_throws ArgumentError CorePotts.synchronize_neighbor_polarity_status!(
        heterogeneous_plan, heterogeneous_process)
    heterogeneous_key =
        only(heterogeneous_process.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(
        heterogeneous_key) ==
        CorePotts.NEIGHBOR_ALIGNMENT_NONFINITE_INPUT
    @test CorePotts._coupled_process_failing_cell(
        heterogeneous_key) == UInt32(1)
end

@testset "Phase 14 Hill vector force has exact limits and sign" begin
    fixture = _polarity_force_fixture()
    aligned = deepcopy(fixture.logical)
    CorePotts.apply_neighbor_polarity_alignment!(
        aligned, fixture.logical, fixture.domain,
        fixture.alignment)
    force = CorePotts.HillVectorForce(
        :protrusion_force, aligned;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 10.0f0,
        exponent = 4,
        direction = -1.0f0)
    candidate = deepcopy(aligned)
    @test CorePotts.apply_hill_vector_force!(
        candidate, aligned, force) === candidate
    coefficient = property_values(
        candidate, :hill_coefficient)
    magnitude = property_values(
        candidate, :force_magnitude)
    force_x = property_values(candidate, :force_x)
    force_y = property_values(candidate, :force_y)
    @test coefficient[1] == 0.0f0
    @test coefficient[2] == 0.5f0
    @test coefficient[3] ≈ 16.0f0 / 17.0f0
    @test magnitude ≈ 10.0f0 .* coefficient
    @test force_x[1] == 0.0f0
    @test force_y[1] == 0.0f0
    @test force_x[2] ≈
        -magnitude[2] *
        property_values(aligned, :polarity_x)[2]
    @test force_y[2] ≈
        -magnitude[2] *
        property_values(aligned, :polarity_y)[2]
    @test force_x[3] == 0.0f0
    @test force_y[3] == 0.0f0
end

@testset "Phase 14 Hill vector force portable path agrees and fails atomically" begin
    fixture = _polarity_force_fixture()
    host_candidate = deepcopy(fixture.logical)
    CorePotts.apply_hill_vector_force!(
        host_candidate, fixture.logical, fixture.force)
    portable_force = CorePotts.HillVectorForce(
        :protrusion_force, fixture.compiled;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 10.0f0,
        exponent = 4,
        direction = -1.0f0)
    plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    @test CorePotts.apply_hill_vector_force!(
        plan, fixture.compiled,
        portable_force) === fixture.compiled
    @test CorePotts.synchronize_hill_vector_force_status!(
        plan, portable_force) === portable_force
    portable = logical_snapshot(fixture.compiled.potts)
    for property in (
            :force_x, :force_y,
            :force_magnitude, :hill_coefficient)
        @test property_values(portable, property) ≈
            property_values(host_candidate, property)
    end
    @test plan.metrics.launches == 3
    @test plan.metrics.host_to_device_transfers == 0
    @test plan.metrics.device_to_host_transfers == 0

    failing = _polarity_force_fixture()
    failing_force = CorePotts.HillVectorForce(
        :protrusion_force, failing.compiled;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 10.0f0,
        exponent = 4,
        direction = -1.0f0)
    execution = scientific_execution(failing.compiled)
    execution.core.properties.rac[2] = -1.0f0
    before = Tuple(copy(getproperty(
            execution.core.properties, property))
        for property in (
            :force_x, :force_y,
            :force_magnitude, :hill_coefficient))
    failing_plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    CorePotts.apply_hill_vector_force!(
        failing_plan, failing.compiled, failing_force)
    @test_throws ArgumentError CorePotts.synchronize_hill_vector_force_status!(
        failing_plan, failing_force)
    after = Tuple(copy(getproperty(
            execution.core.properties, property))
        for property in (
            :force_x, :force_y,
            :force_magnitude, :hill_coefficient))
    @test after == before
    key = only(failing_force.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(key) ==
        CorePotts.HILL_FORCE_INVALID_SIGNAL
    @test CorePotts._coupled_process_failing_cell(key) ==
        UInt32(2)

    heterogeneous = _polarity_force_fixture()
    heterogeneous_force = CorePotts.HillVectorForce(
        :protrusion_force, heterogeneous.compiled;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 10.0f0,
        exponent = 4,
        direction = -1.0f0)
    heterogeneous_execution =
        scientific_execution(heterogeneous.compiled)
    heterogeneous_execution.core.properties.polarity_x[1] =
        Float32(NaN)
    heterogeneous_execution.core.properties.rac[2] = -1.0f0
    heterogeneous_plan = ExecutionPlan(
        KernelAbstractions.CPU(); block_size = 64)
    CorePotts.apply_hill_vector_force!(
        heterogeneous_plan, heterogeneous.compiled,
        heterogeneous_force)
    @test_throws ArgumentError CorePotts.synchronize_hill_vector_force_status!(
        heterogeneous_plan, heterogeneous_force)
    heterogeneous_key =
        only(heterogeneous_force.workspace.failure_key)
    @test CorePotts._coupled_process_failure_code(
        heterogeneous_key) ==
        CorePotts.HILL_FORCE_NONFINITE_INPUT
    @test CorePotts._coupled_process_failing_cell(
        heterogeneous_key) == UInt32(1)
end

function _polarity_force_zero_alloc_probe(
        alignment_candidate, alignment_snapshot,
        domain, alignment, force_candidate,
        force_snapshot, force)
    CorePotts.apply_neighbor_polarity_alignment!(
        alignment_candidate, alignment_snapshot,
        domain, alignment)
    CorePotts.apply_hill_vector_force!(
        force_candidate, force_snapshot, force)
    return nothing
end

@testset "Phase 14 polarity and force warm CPU reference allocates zero bytes" begin
    fixture = _polarity_force_fixture()
    alignment_candidate = deepcopy(fixture.logical)
    force_candidate = deepcopy(fixture.logical)
    _polarity_force_zero_alloc_probe(
        alignment_candidate, fixture.logical,
        fixture.domain, fixture.alignment,
        force_candidate, fixture.logical, fixture.force)
    @test @allocated(_polarity_force_zero_alloc_probe(
        alignment_candidate, fixture.logical,
        fixture.domain, fixture.alignment,
        force_candidate, fixture.logical,
        fixture.force)) == 0
end

@testset "Phase 14 polarity and force coupled restart is exact" begin
    fixture = _polarity_force_fixture()
    components = ScientificComponentSet()
    proposal_relation = first_shell_relation(
        ProposalRole(), Val(2);
        spacing = (1.0f0, 1.0f0))
    potts = init_scientific(
        fixture.compiled, proposal_relation,
        components, SequentialCPM(temperature = 20.0f0);
        seed = 0x1414)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(
            :alignment,
            CorePotts.Update(fixture.alignment)),
        CorePotts.CoupledPhase(
            :force,
            CorePotts.Update(fixture.force)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase())
    coupled = CorePotts.init_coupled(
        potts, plan, CorePotts.CoupledState())
    checkpoint = capture_checkpoint(coupled)
    restored = restore_checkpoint(checkpoint, coupled)
    step!(coupled)
    step!(restored)
    @test logical_state(coupled.potts)._owners ==
        logical_state(restored.potts)._owners
    for property in (
            :polarity_x, :polarity_y,
            :alignment_fraction, :force_x, :force_y,
            :force_magnitude, :hill_coefficient)
        @test property_values(
            logical_state(coupled.potts), property) ==
            property_values(
                logical_state(restored.potts), property)
    end
    @test capture_checkpoint(coupled).state_fingerprint ==
        capture_checkpoint(restored).state_fingerprint
end
