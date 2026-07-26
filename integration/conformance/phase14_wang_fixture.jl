using StaticArrays: SVector

function _wang_runtime_property_schema(
        volume, boundary, vector_force)
    requester = ComponentIdentity(
        :wang_runtime_fixture,
        v"1.0.0", :test)
    keys = (
        :polarity_x,
        :polarity_y,
        :centroid_displacement,
        :alignment_fraction,
        :sensed_secretome,
        :rac,
        :rac_baseline,
        :rac_time,
        :focal_strength,
        :force_magnitude,
        :hill_coefficient,
    )
    supplemental = PropertySchema(map(
        key -> PropertyDescriptor(
            key, Float32,
            ConstantInitializer(0.0f0);
            requester,
            mutability = MutableProperty,
            division = ResetBothOnDivision(),
            transition = PreserveOnTransition(),
            kind = AuxiliaryProperty),
        keys)...)
    return merge_property_schemas(
        required_properties(volume),
        required_properties(boundary),
        required_properties(vector_force),
        supplemental)
end

function _cc3d_square_neighbor_offsets(order::Integer)
    order in 1:4 || throw(ArgumentError(
        "the Wang fixture only uses CC3D square NeighborOrder 1:4"))
    shell_squared_distances = (1, 2, 4, 5)
    included = shell_squared_distances[1:order]
    radius = order <= 2 ? 1 : 2
    return Tuple(
        (dx, dy)
        for squared_distance in included
        for dx in -radius:radius
        for dy in -radius:radius
        if dx * dx + dy * dy == squared_distance)
end

function _wang_runtime_fixture(
        side::Integer;
        target_mcs::Integer = 500,
        execution_mode =
            CorePotts.PortableCoupledExecution(),
        adaptor = Array,
        block_size::Integer = 128,
        metrics = CorePotts.ExecutionMetrics())
    side >= 32 || throw(ArgumentError(
        "Wang runtime fixture side must be at least 32"))
    target_mcs == 500 || throw(ArgumentError(
        "the canonical Wang runtime fixture closes at MCS 500"))
    spacing = (1.0f0, 1.0f0)
    proposal_relation = static_relation(
        ProposalRole(),
        _cc3d_square_neighbor_offsets(2);
        spacing)
    surface_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    connectivity_relation = first_shell_relation(
        ConnectivityRole(), Val(2); spacing)
    contact_energy_relation = static_relation(
        ContactRole(),
        _cc3d_square_neighbor_offsets(4);
        spacing)
    focal_relation = static_relation(
        SpatialQueryRole(),
        _cc3d_square_neighbor_offsets(3);
        spacing)

    volume = QuadraticVolumeHamiltonian(
        number_type = Float32)
    boundary = QuadraticBoundaryHamiltonian(
        BoundaryEdgeCount(), surface_relation;
        number_type = Float32)
    ordinary_contact = UnorderedContactHamiltonian(
        Float32[-1 -2; -2 -6],
        MediumTypeTable(
            MediumID(1) => CellTypeID(1)),
        contact_energy_relation)
    vector_force =
        CorePotts.CellVectorBoundaryPotentialHamiltonian(
            surface_relation;
            coefficients = (:force_x, :force_y),
            number_type = Float32)
    schema = _wang_runtime_property_schema(
        volume, boundary, vector_force)

    owners = fill(
        MediumOwner(1), side, side)
    center = side ÷ 2
    fill!(view(owners,
        (center - 2):(center + 2),
        (center - 12):(center - 3)),
        CellOwner(1))
    fill!(view(owners,
        (center - 2):(center + 2),
        (center + 3):(center + 12)),
        CellOwner(2))
    logical = LogicalPottsState(
        owners, CellCapacity(2);
        cell_types = Dict(
            CellID(1) => CellTypeID(2),
            CellID(2) => CellTypeID(2)),
        medium_domains = [MediumID(1)],
        property_schema = schema)
    property_values(
        logical, :target_volume) .= 50.24f0
    property_values(
        logical, :volume_strength) .= 4.0f0
    property_values(
        logical, :target_boundary) .= Int64(25)
    property_values(
        logical, :boundary_strength) .= 4.0f0
    property_values(
        logical, :polarity_x) .= 1.0f0
    property_values(
        logical, :focal_strength) .= 0.0f0
    property_values(
        logical, :rac_baseline) .= 1.0f0

    rac_dynamics = CorePotts.AffineCellAdvance(
        :wang_rac_dynamics, :cells;
        state = :rac,
        constant = :rac_baseline,
        input = :sensed_secretome,
        time = :rac_time,
        decay = 0.1f0,
        duration = 2880.0f0)
    initialization_workspace =
        CorePotts.AffineCellWorkspace(
            logical, rac_dynamics)
    rac_initializer =
        CorePotts.UniformCellInitialization(
            :wang_rac_initialization,
            :cells;
            property = :rac,
            lower = 0.0f0,
            upper = 30.0f0,
            namespace =
                CorePotts.RNGNamespaceIdentity(
                    UInt128(
                        0x77616e672f7261635f696e69745f7631)))
    CorePotts.apply_uniform_cell_initialization!(
        logical, rac_initializer,
        initialization_workspace,
        UInt64(0x7761_6e67))
    CorePotts.apply_affine_cell_advance!(
        logical, rac_dynamics,
        initialization_workspace)

    closed_boundaries = ntuple(
        _ -> AxisBoundary(ClosedBoundary()), 2)
    domain = CorePotts.CartesianDomain(
        (side, side);
        spacing,
        boundaries = closed_boundaries)
    boundary_tracker =
        BoundaryMeasureTracker(
            BoundaryEdgeCount(),
            surface_relation)
    moment_tracker = UnwrappedMomentTracker(
        connectivity_relation;
        number_type = Float32)
    host_compiled = compile_scientific_state(
        logical, domain, boundary_tracker;
        moment_tracker)
    compiled = CorePotts.Adapt.adapt(
        adaptor, host_compiled)
    CorePotts.scientific_storage_valid(compiled) ||
        throw(ArgumentError(
            "the canonical Wang scientific state must be one backend-resident array tree"))
    backend = CorePotts.KernelAbstractions.get_backend(
        compiled.potts.storage.active)
    execution_plan = CorePotts.ExecutionPlan(
        backend; block_size, metrics)

    relationship_declaration =
        CorePotts.RelationshipSet(
            :wang_junctions;
            edge =
                CorePotts.ElasticLinkParameters{
                    Float32},
            maximum_degree = 4,
            capacity =
                CorePotts.RelationshipCapacity(
                    16))
    host_relationships =
        CorePotts.RelationshipState(
            relationship_declaration)
    endpoint_1 = CorePotts.CellEndpoint(
        CellID(1),
        generation(logical, CellID(1)))
    endpoint_2 = CorePotts.CellEndpoint(
        CellID(2),
        generation(logical, CellID(2)))
    CorePotts.create_relationship!(
        host_relationships,
        endpoint_1, endpoint_2,
        CorePotts.ElasticLinkParameters(
            0.0f0, 0.0f0, 100_000.0f0))
    relationships = CorePotts.Adapt.adapt(
        adaptor, host_relationships)
    contact = CorePotts.ContactRelationshipHamiltonian(
        :wang_contact_relationship,
        :wang_junctions;
        relation = focal_relation,
        pair_filter =
            CorePotts.SameCellTypePair(
                CellTypeID(2)),
        activation_energy = -50.0f0,
        initial_payload =
            CorePotts.ElasticLinkParameters(
                0.0f0, 0.0f0, 100_000.0f0),
        namespace =
            CorePotts.RNGNamespaceIdentity(
                UInt128(
                    0x77616e675f72756e74696d655f763031)))
    transaction =
        CorePotts.ContactRelationshipTransaction(
            contact, relationships)
    attempt_workspace =
        CorePotts.CoupledAttemptWorkspace(
            (), (), (transaction,))
    components = CorePotts.Adapt.adapt(
        adaptor, ScientificComponentSet(
        energies = (
            volume, boundary, ordinary_contact,
            contact, vector_force)))
    potts = init_scientific(
        compiled, proposal_relation,
        components,
        SequentialCPM(
            temperature = 25.0f0);
        seed = 0x7761_6e67,
        plan = execution_plan,
        moment_tracker,
        algorithm_workspace =
            attempt_workspace)

    history_declaration = CorePotts.CellHistory(
        :wang_centroid_history;
        source =
            :compiled_unwrapped_centroid,
        length = 5,
        initial =
            CorePotts.RepeatInitialSample())
    initial_centroids = SVector{2, Float32}[
        SVector(
            Float32(center),
            Float32(center - 7.5)),
        SVector(
            Float32(center),
            Float32(center + 7.5)),
    ]
    host_history = CorePotts.initialize_cell_history(
        history_declaration,
        initial_centroids,
        CellGeneration[
            generation(logical, CellID(1)),
            generation(logical, CellID(2))])
    history = CorePotts.Adapt.adapt(
        adaptor, host_history)

    field_values = similar(
        compiled.potts.storage.active,
        Float32, side, side)
    fill!(field_values, 0.0f0)
    field = CorePotts.EvolvingFieldState(
        :wang_secretome, field_values)
    clock = CorePotts.ContinuousClock(
        :wang_clock;
        per_mcs = 1.0f0, unit = :mcs)
    field_dynamics = CorePotts.FieldDynamics(
        :wang_secretome_dynamics;
        field = :wang_secretome,
        law = CorePotts.ReactionDiffusion(
            diffusion = 1.0f0,
            decay = 0.0f0),
        method = CorePotts.FixedStep(
            CorePotts.ExplicitEuler();
            substeps = 5),
        clock,
        post_substep = (
            CorePotts.ConstantConcentration(
                :medium, 1.0f0),))
    exchange = CorePotts.FieldExchange(
        :wang_secretome_uptake;
        field = :wang_secretome,
        sinks = (
            CorePotts.Uptake(
                :cells;
                maximum = 1.0f0,
                relative_rate = 0.0025f0,
                output =
                    :sensed_secretome),),
        calibration =
            CorePotts.MaximumCalibration(
                4.0f0,
                :uptake_multiplier))
    exchange_runtime =
        CorePotts.FieldExchangeState(
            :uptake_multiplier,
            field, logical;
            accumulator_type = Float32)
    exchange_schedule =
        CorePotts.PlanModeSchedule(
            CorePotts.MCSRange(1, 121) =>
                CorePotts.InactiveExchange,
            CorePotts.MCSRange(122, 210) =>
                CorePotts.ResetExchange,
            CorePotts.MCSRange(211, 211) =>
                CorePotts.CalibrateExchange,
            CorePotts.MCSRange(212, 500) =>
                CorePotts.PublishExchange)

    rac_runtime = CorePotts.Adapt.adapt(
        adaptor,
        CorePotts.AffineCellRuntime(
            rac_dynamics, logical))
    centroid_sample =
        CorePotts.CentroidHistorySample(
            :wang_centroid_sample,
            :wang_centroid_history)
    history_direction =
        CorePotts.HistoryDisplacementDirection(
            :wang_history_direction,
            :wang_centroid_history;
            outputs = (
                :polarity_x, :polarity_y),
            magnitude =
                :centroid_displacement,
            lag = CorePotts.Lag(4))
    retune = CorePotts.ElasticLinkRetune(
        :wang_focal_retune,
        relationship_declaration,
        :cells;
        property = :focal_strength,
        strength = 0.0f0,
        target_length = 8.0f0,
        maximum_length = 12.0f0)
    migration_protocol =
        CorePotts.StagedProtocol(
            CorePotts.ProtocolStage(
                :relax;
                mcs = CorePotts.MCSRange(
                    1, 120)),
            CorePotts.ProtocolStage(
                :pre_signal;
                mcs = CorePotts.MCSRange(
                    121, 210)),
            CorePotts.ProtocolStage(
                :signal;
                mcs = CorePotts.MCSRange(
                    211, 500)))
    retune_parameters =
        CorePotts.ScheduledParameter(
            :wang_focal_parameters,
            migration_protocol;
            relax =
                CorePotts.ElasticLinkParameters(
                    0.0f0, 8.0f0, 12.0f0),
            pre_signal =
                CorePotts.ElasticLinkParameters(
                    20.0f0, 8.0f0, 12.0f0),
            signal =
                CorePotts.ElasticLinkParameters(
                    20.0f0, 8.0f0, 12.0f0))
    alignment =
        CorePotts.NeighborPolarityAlignment(
            :wang_neighbor_alignment,
            focal_relation;
            x = :polarity_x,
            y = :polarity_y,
            strength = :focal_strength,
            fraction =
                :alignment_fraction,
            strength_scale = 1000.0f0,
            maximum_fraction = 0.4f0)
    force = CorePotts.HillVectorForce(
        :wang_protrusion_force;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 150.0f0,
        exponent = 4,
        direction = -1.0f0)
    cleanup = CorePotts.RelationshipCleanup(
        :wang_relationship_cleanup,
        relationship_declaration)

    observation_bindings = (
        x_self_polarity = :polarity_x,
        y_self_polarity = :polarity_y,
        a = :rac_baseline,
        s = :sensed_secretome,
        rac = :rac,
        f = :force_magnitude,
        f_x = :force_x,
        f_y = :force_y,
        fpp = :focal_strength,
        f_coef = :hill_coefficient,
        p_frac = :alignment_fraction,
    )
    table =
        CorePotts.BoundedCellTableObservation(
            :wang_cell_records,
            compiled;
            bindings = observation_bindings,
            cell_capacity = 2)
    geometry =
        CorePotts.LosslessOwnershipSnapshot(
            :wang_geometry,
            compiled)
    observation = CorePotts.PhaseObservation(
        :wang_cell_records, table;
        schedule =
            CorePotts.PeriodicMCS(
                122, 1; stop = 500),
        schema = CorePotts.RecordSchema(
            :wang_cell_record_v1,
            v"1.0.0"))
    geometry_observation =
        CorePotts.PhaseObservation(
            :wang_geometry, geometry;
            schedule =
                CorePotts.AtMCS((91, 271)),
            schema = CorePotts.RecordSchema(
                :wang_ownership_snapshot_v1,
                v"1.0.0"))
    active_migration =
        CorePotts.PeriodicMCS(
            122, 1; stop = 500)

    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(
            :secretome_field_solve,
            CorePotts.Advance(
                field_dynamics;
                interval =
                    CorePotts.OneMCS())),
        CorePotts.CoupledPhase(
            :sample_centroids,
            CorePotts.Sample(
                centroid_sample)),
        CorePotts.CoupledPhase(
            :update_self_polarity,
            CorePotts.Update(
                history_direction;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :secretome_uptake,
            CorePotts.Exchange(
                exchange;
                mode = exchange_schedule)),
        CorePotts.CoupledPhase(
            :intracellular_dynamics,
            CorePotts.Advance(
                rac_dynamics;
                interval =
                    CorePotts.OneMCS(),
                active = active_migration)),
        CorePotts.CoupledPhase(
            :retune_focal_relationships,
            CorePotts.Update(
                retune;
                active =
                    CorePotts.PeriodicMCS(
                        1, 10;
                        stop = 491),
                value = retune_parameters)),
        CorePotts.CoupledPhase(
            :align_neighbor_polarity,
            CorePotts.Update(
                alignment;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :update_protrusion,
            CorePotts.Update(
                force;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :cleanup_relationships,
            CorePotts.Update(cleanup)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(
            observation,
            geometry_observation))
    coupled_state = CorePotts.CoupledState(
        histories = (history,),
        relationships = (relationships,),
        fields = (field,),
        globals = (
            exchange_runtime,
            rac_runtime))
    coupled = CorePotts.init_coupled(
        potts, plan, coupled_state;
        protocol = migration_protocol,
        execution_mode)
    return (;
        coupled, plan, compiled, history,
        relationships, field,
        exchange_runtime, rac_runtime,
        table, geometry, target_mcs,
        adaptor, backend, metrics)
end
