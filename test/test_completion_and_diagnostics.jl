function PottsToolkit.registered_statement_lowering(
        ::Val{:lower_example_read},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) || error("example lowering accepts no options")
    return Observation(id, only(arguments); source)
end

struct FingerprintPayload{Name}
    schema::UInt16
end

@testset "completion and diagnostics" begin
    @variables t activity(t)
    @parameters target strength maximum activity_strength
    endothelial = CellKind(:endothelial)
    extracellular = MediumKind(:extracellular)
    copy = ProposalContext(:copy)

    model_statements = StatementSet((
        Lattice(
            (8, 8);
            spacing = (1.0, 1.0),
            relations = (
                proposal = Moore(),
                contact = Moore(),
                activity_neighborhood = Moore(),
            ),
        ),
        endothelial,
        extracellular,
        Volume(endothelial; target, strength),
        ContactEnergy([
            (extracellular ↔ endothelial) => 6.0,
            (endothelial ↔ endothelial) => 2.0,
        ]),
        SiteState(
            activity;
            owner = endothelial,
            initial = 0.0,
            lifecycle = ClearOnOwnershipChange(),
        ),
        ActEnergy(
            endothelial,
            activity;
            maximum,
            strength = activity_strength,
            reduction = :activity_neighborhood,
        ),
        AcceptedCopy(
            :activate,
            Assign(activity, maximum);
            when = copy.is_extension,
        ),
        Synchronous(
            :decay,
            Assign(activity, max(activity - 1, 0));
            phase = AfterMCS(),
        ),
        Protocol(Sweep(); name = :main),
    ))

    @named wortel = PottsSystem(
        statements = model_statements,
        unknowns = [activity],
        parameters = [target, strength, maximum, activity_strength],
        independent_variables = [t],
    )
    completed = complete(wortel)
    records = inspect(completed, Statements())
    @test length(records) == 13
    activity_record = only(filter(
        record -> record.lowering_identity === :lower_activity, records
    ))
    @test activity_record.shape == ()
    @test activity_record.ownership === :none
    @test activity_record.persistence === :none
    @test PottsToolkit.QualifiedStatementID(
        (:wortel,), StatementID(:endothelial)
    ) in activity_record.resources
    @test activity_record.provenance.schema === :built_in_v1
    @test activity_record.transaction_identity === nothing
    @test inspect(completed, Capabilities()).sequential
    @test inspect(completed, Capabilities()).checkerboard
    @test any(item -> item[2] isa AcceptedCopyEffect, inspect(completed, Effects()))
    @test any(item -> item[2] isa SynchronousAssign, inspect(completed, Effects()))
    accepted_record = only(filter(
        record -> record.identity.local_id == StatementID(:activate), records
    ))
    @test !isempty(accepted_record.ordering_dependencies)
    @test all(
        dependency -> dependency in getfield.(records, :identity),
        accepted_record.ordering_dependencies,
    )
    @test length(string(semantic_fingerprint(completed))) == 64
    @test length(string(completed_system_fingerprint(completed))) == 64

    @variables chemo_signal(t)
    chemo_field = FieldState(
        chemo_signal; name = :chemo_signal, initial = 0.0
    )
    @named unsupported_retraction = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            endothelial,
            extracellular,
            chemo_field,
            Chemotaxis(
                endothelial,
                chemo_field;
                strength = 1.0,
                mode = RetractionsOnly(),
            ),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [chemo_signal],
        independent_variables = [t],
    )
    retraction_error = try
        compile(
            complete(unsupported_retraction);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch caught
        caught
    end
    @test retraction_error isa PottsToolkit.PottsValidationError
    @test only(retraction_error.diagnostics).kind === :unsupported_v1_lowering
    @test occursin(
        "ExtensionsOnly", only(retraction_error.diagnostics).actual
    )

    @named unsupported_interpolation = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            endothelial,
            extracellular,
            chemo_field,
            Chemotaxis(
                endothelial,
                chemo_field;
                strength = 1.0,
                sample = Multilinear(),
            ),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [chemo_signal],
        independent_variables = [t],
    )
    interpolation_error = try
        compile(
            complete(unsupported_interpolation);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch caught
        caught
    end
    @test interpolation_error isa PottsToolkit.PottsValidationError
    @test only(interpolation_error.diagnostics).kind ===
          :unsupported_v1_lowering
    @test occursin(
        "Nearest", only(interpolation_error.diagnostics).actual
    )

    cell = CellBinding(:cell)
    @named unsupported_surface = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            endothelial,
            extracellular,
            HamiltonianTerm(
                :surface;
                domain = cells(endothelial),
                anchor = cell,
                expression = cell_surface(cell),
            ),
            Protocol(Sweep(); name = :main),
        )),
    )
    surface_error = try
        compile(
            complete(unsupported_surface);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch caught
        caught
    end
    @test surface_error isa PottsToolkit.PottsValidationError
    @test only(surface_error.diagnostics).kind ===
          :unsupported_operation_context

    @named same_science = PottsSystem(
        statements = model_statements,
        unknowns = [activity],
        parameters = [target, strength, maximum, activity_strength],
        independent_variables = [t],
    )
    # Model name/hierarchy packaging does not enter the semantic fingerprint.
    @test semantic_fingerprint(complete(same_science)) ==
          semantic_fingerprint(completed)

    links = RelationshipState(:links; capacity = 4, maximum_degree = 2)
    edge_effect = Create(links, copy.source_cell, copy.target_cell)
    @named focal = PottsSystem(statements = StatementSet((
        links,
        AcceptedCopy(:create_link, edge_effect; when = copy.is_extension),
    )))
    focal_completed = complete(focal)
    @test !inspect(focal_completed, Capabilities()).checkerboard
    @test only(inspect(focal_completed, Capabilities()).checkerboard_rejections)[1] ==
          PottsToolkit.QualifiedStatementID((:focal,), StatementID(:create_link))

    @named invalid = PottsSystem(statements = StatementSet((
        CellKind(:duplicate),
        MediumKind(:duplicate),
    )))
    error = try
        complete(invalid)
        nothing
    catch caught
        caught
    end
    @test error isa PottsToolkit.PottsValidationError
    @test error.stage == :completion
    @test only(error.diagnostics).kind == :duplicate_statement_identity

    registered_contract = (
        argument_types = (Num,),
        result_type = Real,
        unit_constraints = :dimensionless,
        namespace_traversal = :map_symbolics,
        access = (reads = (1,), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = Observe(),
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        scientific_category = :observation,
        energy_domain = nothing,
        affected_region = nothing,
        reference_semantics = :dimensionless,
        descriptor_payload_type = CorePotts.EmptyDescriptorPayload,
        serialization_identity = "example-read-v1",
        lowering_identity = :lower_example_read,
    )
    registry = register_statement(
        default_statement_registry(), :example_read, v"1.0.0",
        registered_contract,
    )
    @named registered_model = PottsSystem(statements = StatementSet((
        RegisteredStatement(:extension_read, :example_read, v"1.0.0", activity),
    )), unknowns = [activity], independent_variables = [t])
    registered_completed = complete(registered_model; registry)
    registered_record = only(inspect(registered_completed, Statements()))
    @test registered_record.result_type === Real
    @test registered_record.effect isa PureRead
    @test registered_record.lowering_identity === :lower_observation
    @test registered_record.provenance.schema === :example_read
    @test registered_record.schema_version == v"1.0.0"
    @test registered_record.provenance.registered_lowering_identity ===
          :lower_example_read
    @test registered_record.provenance.registered_descriptor_payload_type ===
          CorePotts.EmptyDescriptorPayload

    fingerprint_contract_a = merge(
        registered_contract,
        (descriptor_payload_type = FingerprintPayload{:a},),
    )
    fingerprint_contract_b = merge(
        registered_contract,
        (descriptor_payload_type = FingerprintPayload{:b},),
    )
    fingerprint_registry_a = register_statement(
        default_statement_registry(),
        :example_read,
        v"1.0.0",
        fingerprint_contract_a,
    )
    fingerprint_registry_b = register_statement(
        default_statement_registry(),
        :example_read,
        v"1.0.0",
        fingerprint_contract_b,
    )
    @test PottsToolkit._canonical_value(FingerprintPayload{:a}) !=
          PottsToolkit._canonical_value(FingerprintPayload{:b})
    @test completed_system_fingerprint(complete(
        registered_model;
        registry = fingerprint_registry_a,
    )) != completed_system_fingerprint(complete(
        registered_model;
        registry = fingerprint_registry_b,
    ))

    forged_origin = (
        schema = :missing_schema,
        version = v"1.0.0",
        serialization_identity = "forged-schema-v1",
        lowering_identity = :lower_external_weighted_site_term,
        descriptor_payload_type = FingerprintPayload{:forged},
    )
    forged_core = PottsToolkit.StatementCore(
        StatementID(:forged_internal_origin),
        (; expression = activity_strength),
        (; __registered_origin = forged_origin),
        UnknownSource(),
    )
    forged_statement = HamiltonianTerm(forged_core)
    @named forged_origin_model = PottsSystem(
        statements = StatementSet((forged_statement,)),
        parameters = [activity_strength],
    )
    forged_origin_error = try
        complete(forged_origin_model)
        nothing
    catch caught
        caught
    end
    @test forged_origin_error isa PottsToolkit.PottsValidationError
    @test only(forged_origin_error.diagnostics).kind ===
          :unauthenticated_registered_origin

    mismatched_origin = (
        schema = :example_read,
        version = v"1.0.0",
        serialization_identity = "example-read-v1",
        lowering_identity = :lower_example_read,
        descriptor_payload_type = FingerprintPayload{:forged},
    )
    mismatched_core = PottsToolkit.StatementCore(
        StatementID(:mismatched_internal_origin),
        (; expression = activity_strength),
        (; __registered_origin = mismatched_origin),
        UnknownSource(),
    )
    @named mismatched_origin_model = PottsSystem(
        statements = StatementSet((HamiltonianTerm(mismatched_core),)),
        parameters = [activity_strength],
    )
    mismatched_origin_error = try
        complete(mismatched_origin_model; registry)
        nothing
    catch caught
        caught
    end
    @test mismatched_origin_error isa PottsToolkit.PottsValidationError
    @test only(mismatched_origin_error.diagnostics).kind ===
          :unauthenticated_registered_origin

    missing_registry_error = try
        complete(registered_model)
        nothing
    catch caught
        caught
    end
    @test missing_registry_error isa PottsToolkit.PottsValidationError
    @test only(missing_registry_error.diagnostics).kind ===
          :unregistered_statement_schema

    @named mistyped_registered = PottsSystem(statements = StatementSet((
        RegisteredStatement(:extension_read, :example_read, v"1.0.0", 1),
    )))
    mistyped_error = try
        complete(mistyped_registered; registry)
        nothing
    catch caught
        caught
    end
    @test mistyped_error isa PottsToolkit.PottsValidationError
    @test only(mistyped_error.diagnostics).kind ===
          :registered_argument_type_mismatch

    @named aggregated_invalid = PottsSystem(statements = StatementSet((
        RegisteredStatement(:missing_a, :absent_a, v"1.0.0", activity),
        RegisteredStatement(:missing_b, :absent_b, v"2.0.0", activity),
    )), unknowns = [activity], independent_variables = [t])
    aggregate_error = try
        complete(aggregated_invalid)
        nothing
    catch caught
        caught
    end
    @test aggregate_error isa PottsToolkit.PottsValidationError
    @test length(aggregate_error.diagnostics) == 2
    @test getfield.(aggregate_error.diagnostics, :kind) ==
          (:unregistered_statement_schema, :unregistered_statement_schema)

    noise = draw(Normal(0.0, 1.0), DrawKey(:polarity_noise))
    @named stochastic = PottsSystem(statements = StatementSet((
        ProposalDrive(:noisy_drive, noise),
        Protocol(Sweep(); name = :stochastic_protocol),
    )))
    stochastic_completed = complete(stochastic)
    stochastic_operations = inspect(stochastic_completed, RandomOperations())
    @test any(
        operation -> operation.identity === :polarity_noise &&
                     operation.family === :normal && !operation.reserved,
        Iterators.flatten(last.(stochastic_operations)),
    )
    @test count(
        operation -> operation.reserved,
        Iterators.flatten(last.(stochastic_operations)),
    ) == 3

    @named duplicate_draws = PottsSystem(statements = StatementSet((
        ProposalDrive(
            :first_noise, draw(Uniform(), DrawKey(:same_key))
        ),
        ProposalModifier(
            :second_noise, draw(Bernoulli(0.5), DrawKey(:same_key))
        ),
    )))
    duplicate_draw_error = try
        complete(duplicate_draws)
        nothing
    catch caught
        caught
    end
    @test duplicate_draw_error isa PottsToolkit.PottsValidationError
    @test only(duplicate_draw_error.diagnostics).kind === :duplicate_draw_key

    @named invalid_distribution = PottsSystem(statements = StatementSet((
        ProposalDrive(
            :bad_noise, draw(Normal(0.0, -1.0), DrawKey(:bad_noise))
        ),
    )))
    distribution_error = try
        complete(invalid_distribution)
        nothing
    catch caught
        caught
    end
    @test distribution_error isa PottsToolkit.PottsValidationError
    @test only(distribution_error.diagnostics).kind ===
          :invalid_random_distribution

    @named invalid_phase = PottsSystem(statements = StatementSet((
        AcceptedCopyProcess(
            :misphased;
            effects = (Assign(activity, 1.0),),
            phase = AfterMCS(),
        ),
    )), unknowns = [activity], independent_variables = [t])
    phase_error = try
        complete(invalid_phase)
        nothing
    catch caught
        caught
    end
    @test phase_error isa PottsToolkit.PottsValidationError
    @test only(phase_error.diagnostics).kind === :illegal_effect_phase
end
