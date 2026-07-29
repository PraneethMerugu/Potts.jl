function _vector_boundary_state(
        owners, component; values)
    cell_ids = sort!(unique(
        Int(owner.value) for owner in owners
        if is_cell_owner(owner)))
    cell_types = Dict(
        CellID(id) => CellTypeID(1)
        for id in cell_ids)
    state = LogicalPottsState(
        owners, CellCapacity(maximum(cell_ids; init = 1));
        cell_types,
        medium_domains = [MediumID(1)],
        property_schema =
            required_properties(component))
    for (property, entries) in pairs(values)
        column = property_values(state, property)
        for (slot, value) in pairs(entries)
            column[slot] = value
        end
    end
    return state
end

CorePotts.KernelAbstractions.@kernel function _vector_boundary_probe!(
        output, state, component, proposal)
    output[1] = energy_change(
        component, proposal, state,
        state.domain)
end

@testset "coupled dynamics CC3D-derived vector boundary potential" begin
    T = Float32
    boundaries = (
        AxisBoundary(ClosedBoundary()),
        AxisBoundary(ClosedBoundary()))
    domain = CartesianDomain(
        (5, 5);
        spacing = (one(T), one(T)),
        boundaries)
    relation = first_shell_relation(
        SurfaceRole(), Val(2);
        spacing = domain.spacing)
    component =
        CellVectorBoundaryPotentialHamiltonian(
            relation;
            coefficients = (:force_x, :force_y),
            number_type = T)

    @test isbitstype(typeof(component))
    @test component_identity(component) ==
          ComponentIdentity(
        :cell_vector_boundary_potential,
        v"1.0.0", :energy)
    @test property_keys(
        required_properties(component)) ==
          (:force_x, :force_y)
    @test component_semantic_data(
        component).equilibrium === false
    @test capabilities(component).dimensions == (2,)
    @test validate_energy_component(
        component).category == :energy
    @test scientific_access(component) isa
          SnapshotScientificAccess
    @test tiled_scientific_access(component) isa
          UnsupportedTiledScientificAccess
    @test_throws ArgumentError begin
        CellVectorBoundaryPotentialHamiltonian(
            relation;
            coefficients = (:force_x, :force_x),
            number_type = T)
    end
    relation_3d = first_shell_relation(
        SurfaceRole(), Val(3))
    @test_throws DimensionMismatch begin
        CellVectorBoundaryPotentialHamiltonian(
            relation_3d;
            coefficients = (:force_x, :force_y),
            number_type = T)
    end

    linear = LinearIndices((5, 5))

    extension_owners =
        fill(MediumOwner(1), 5, 5)
    extension_owners[2, 3] = CellOwner(1)
    extension_state =
        _vector_boundary_state(
        extension_owners, component;
        values = (
            force_x = T[-4],
            force_y = T[0]))
    extension = CopyProposal(
        linear[3, 3], linear[2, 3],
        MediumOwner(1), CellOwner(1))
    @test energy_change(
        component, extension,
        extension_state, domain) === T(-4)
    energy_change(
        component, extension,
        extension_state, domain)
    @test @allocated(
        energy_change(
            component, extension,
            extension_state, domain)) == 0

    retraction_owners =
        fill(MediumOwner(1), 5, 5)
    retraction_owners[2, 3] = CellOwner(1)
    retraction_owners[3, 3] = CellOwner(1)
    retraction_state =
        _vector_boundary_state(
        retraction_owners, component;
        values = (
            force_x = T[-4],
            force_y = T[0]))
    retraction = CopyProposal(
        linear[2, 3], linear[1, 3],
        CellOwner(1), MediumOwner(1))
    @test energy_change(
        component, retraction,
        retraction_state, domain) === T(-4)

    replacement_owners =
        fill(MediumOwner(1), 5, 5)
    replacement_owners[3, 3] = CellOwner(1)
    replacement_owners[2, 3] = CellOwner(1)
    replacement_owners[3, 2] = CellOwner(2)
    replacement_state =
        _vector_boundary_state(
        replacement_owners, component;
        values = (
            force_x = T[1, -3],
            force_y = T[2, 4]))
    replacement = CopyProposal(
        linear[3, 3], linear[3, 2],
        CellOwner(1), CellOwner(2))
    @test energy_change(
        component, replacement,
        replacement_state, domain) === T(3)

    property_values(
        replacement_state, :force_x) .= zero(T)
    property_values(
        replacement_state, :force_y) .= zero(T)
    @test energy_change(
        component, replacement,
        replacement_state, domain) === zero(T)

    periodic_boundaries = (
        AxisBoundary(PeriodicBoundary()),
        AxisBoundary(ClosedBoundary()))
    periodic_domain = CartesianDomain(
        (3, 3);
        spacing = (one(T), one(T)),
        boundaries = periodic_boundaries)
    periodic_relation = first_shell_relation(
        SurfaceRole(), Val(2);
        spacing = periodic_domain.spacing)
    periodic_component =
        CellVectorBoundaryPotentialHamiltonian(
            periodic_relation;
            coefficients = (:force_x, :force_y),
            number_type = T)
    periodic_owners =
        fill(MediumOwner(1), 3, 3)
    periodic_owners[3, 2] = CellOwner(1)
    periodic_state =
        _vector_boundary_state(
        periodic_owners,
        periodic_component;
        values = (
            force_x = T[-2],
            force_y = T[0]))
    periodic_linear = LinearIndices((3, 3))
    periodic_extension = CopyProposal(
        periodic_linear[1, 2],
        periodic_linear[3, 2],
        MediumOwner(1), CellOwner(1))
    @test energy_change(
        periodic_component,
        periodic_extension,
        periodic_state,
        periodic_domain) === T(-2)

    tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), relation)
    compiled = compile_scientific_state(
        extension_state, domain, tracker)
    transaction = stage_copy_transaction(
        compiled, tracker, extension)
    context = ScientificProposalContext(
        compiled, transaction)
    @test proposal_energy_change(
        component, extension,
        context) === T(-4)
    components = ScientificComponentSet(
        energies = (component,))
    evaluation = evaluate_copy(
        components, extension,
        context, T)
    @test evaluation.delta_h === T(-4)
    @test any(
        message -> occursin(
            "non-equilibrium energy",
            message),
        algorithm_component_compatibility(
            SequentialEquilibrium(), components))

    output = zeros(T, 1)
    backend = CorePotts.KernelAbstractions.CPU()
    kernel =
        _vector_boundary_probe!(
        backend, 1)
    kernel(
        output, scientific_execution(compiled),
        component, extension; ndrange = 1)
    CorePotts.KernelAbstractions.synchronize(
        backend)
    @test output == T[-4]

    proposal_relation = first_shell_relation(
        ProposalRole(), Val(2);
        spacing = domain.spacing)
    integration = init_scientific(
        compiled, proposal_relation,
        components,
        SequentialCPM(temperature = T(25));
        seed = 0x14b)
    @test CorePotts.SciMLBase.step!(
        integration) === integration
    @test current_mcs_report(
        integration).activated_attempts ==
          mutable_site_count(domain)
end

@testset "coupled dynamics vector boundary potential is dimension generic" begin
    T = Float64
    boundaries = ntuple(
        _ -> AxisBoundary(ClosedBoundary()), 3)
    domain = CartesianDomain(
        (4, 4, 4);
        spacing = ntuple(_ -> one(T), 3),
        boundaries)
    relation = first_shell_relation(
        SurfaceRole(), Val(3);
        spacing = domain.spacing)
    component =
        CellVectorBoundaryPotentialHamiltonian(
            relation;
            coefficients = (
                :force_x, :force_y, :force_z),
            number_type = T)
    owners = fill(MediumOwner(1), 4, 4, 4)
    owners[2, 2, 2] = CellOwner(1)
    state = _vector_boundary_state(
        owners, component;
        values = (
            force_x = T[-1.5],
            force_y = T[0],
            force_z = T[0]))
    linear = LinearIndices((4, 4, 4))
    proposal = CopyProposal(
        linear[3, 2, 2],
        linear[2, 2, 2],
        MediumOwner(1), CellOwner(1))
    @test energy_change(
        component, proposal,
        state, domain) === T(-1.5)
    @test capabilities(component).dimensions == (3,)
end
