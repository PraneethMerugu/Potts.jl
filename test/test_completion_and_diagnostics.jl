function Potts.registered_statement_lowering(
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

struct FingerprintDelimiterPayload
    value::String
end

Base.show(io::IO, value::FingerprintDelimiterPayload) =
    print(io, value.value)

struct FingerprintAxisVector{T} <: AbstractVector{T}
    values::Vector{T}
    offset::Int
end

Base.size(value::FingerprintAxisVector) = (length(value.values),)
Base.axes(value::FingerprintAxisVector) =
    (value.offset:(value.offset + length(value.values) - 1),)
Base.IndexStyle(::Type{<:FingerprintAxisVector}) = IndexCartesian()
Base.getindex(value::FingerprintAxisVector, index::Int) =
    value.values[index - value.offset + 1]

@testset "completion and diagnostics" begin
    @variables t activity(t)
    @parameters target strength maximum activity_strength
    endothelial = CellKind(:endothelial; extinction = RetireAtZero())
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
    @test length(records) == 14
    activity_record = only(filter(
        record -> record.lowering_identity === :lower_activity, records
    ))
    @test activity_record.shape == ()
    @test activity_record.ownership === :none
    @test activity_record.persistence === :none
    @test Potts.QualifiedStatementID(
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

    flat = Int16[1, 2, 3, 4]
    square = reshape(Base.copy(flat), 2, 2)
    @test collect(flat) == vec(square)
    @test Potts._canonical_value(flat) !=
          Potts._canonical_value(square)
    @test Potts._sha256_hex(:array_shape, flat) !=
          Potts._sha256_hex(:array_shape, square)

    one_based = FingerprintAxisVector(Base.copy(flat), 1)
    shifted = FingerprintAxisVector(Base.copy(flat), -2)
    @test collect(one_based) == collect(shifted)
    @test axes(one_based) != axes(shifted)
    @test Potts._canonical_value(one_based) !=
          Potts._canonical_value(shifted)

    delimiter_left = (
        FingerprintDelimiterPayload("x,y"),
        FingerprintDelimiterPayload("z"),
    )
    delimiter_right = (
        FingerprintDelimiterPayload("x"),
        FingerprintDelimiterPayload("y,z"),
    )
    legacy_join(value) = "(" *
        join((sprint(show, item) for item in value), ",") * ")"
    @test legacy_join(delimiter_left) == legacy_join(delimiter_right)
    @test Potts._canonical_value(delimiter_left) !=
          Potts._canonical_value(delimiter_right)
    @test Potts._sha256_hex(delimiter_left) !=
          Potts._sha256_hex(delimiter_right)

    cell = CellBinding(:cell)
    @named missing_surface_relation = PottsSystem(
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
    surface_relation_error = try
        mtkcompile(missing_surface_relation)
        nothing
    catch caught
        caught
    end
    @test surface_relation_error isa Potts.PottsValidationError
    @test surface_relation_error.stage === :analysis
    @test only(surface_relation_error.diagnostics).kind ===
          :illegal_operation_use
    @test occursin(
        "SpatialRelation named :surface",
        only(surface_relation_error.diagnostics).actual,
    )

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
    @test inspect(focal_completed, Capabilities()).checkerboard
    @test isempty(
        inspect(focal_completed, Capabilities()).checkerboard_rejections
    )

    @named invalid = PottsSystem(statements = StatementSet((
        CellKind(:duplicate; extinction = RetireAtZero()),
        MediumKind(:duplicate),
    )))
    error = try
        complete(invalid)
        nothing
    catch caught
        caught
    end
    @test error isa Potts.PottsValidationError
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
        phase = nothing,
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        scientific_category = :observation,
        energy_domain = nothing,
        affected_region = nothing,
        reference_semantics = :dimensionless,
        descriptor_payload_type = CorePotts.CompilerSPI.EmptyDescriptorPayload,
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
          CorePotts.CompilerSPI.EmptyDescriptorPayload

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
    @test Potts._canonical_value(FingerprintPayload{:a}) !=
          Potts._canonical_value(FingerprintPayload{:b})
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
    forged_core = Potts.StatementCore(
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
    @test forged_origin_error isa Potts.PottsValidationError
    @test only(forged_origin_error.diagnostics).kind ===
          :unauthenticated_registered_origin

    mismatched_origin = (
        schema = :example_read,
        version = v"1.0.0",
        serialization_identity = "example-read-v1",
        lowering_identity = :lower_example_read,
        descriptor_payload_type = FingerprintPayload{:forged},
    )
    mismatched_core = Potts.StatementCore(
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
    @test mismatched_origin_error isa Potts.PottsValidationError
    @test only(mismatched_origin_error.diagnostics).kind ===
          :unauthenticated_registered_origin

    missing_registry_error = try
        complete(registered_model)
        nothing
    catch caught
        caught
    end
    @test missing_registry_error isa Potts.PottsValidationError
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
    @test mistyped_error isa Potts.PottsValidationError
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
    @test aggregate_error isa Potts.PottsValidationError
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
    @test duplicate_draw_error isa Potts.PottsValidationError
    @test only(duplicate_draw_error.diagnostics).kind === :duplicate_draw_key

    @named invalid_distribution = PottsSystem(statements = @statements begin
        ProposalDrive(
            :bad_noise, draw(Normal(0.0, -1.0), DrawKey(:bad_noise))
        )
    end)
    distribution_error = try
        complete(invalid_distribution)
        nothing
    catch caught
        caught
    end
    @test distribution_error isa Potts.PottsValidationError
    @test only(distribution_error.diagnostics).kind ===
          :invalid_random_distribution
    @test only(distribution_error.diagnostics).source isa SourceLocation

    @named invalid_unit_vector = PottsSystem(statements = @statements begin
        ProposalDrive(
            :vector_noise,
            draw(UnitVector(2), DrawKey(:vector_noise)),
        )
    end)
    unit_vector_error = try
        mtkcompile(invalid_unit_vector)
        nothing
    catch caught
        caught
    end
    @test unit_vector_error isa Potts.PottsValidationError
    @test only(unit_vector_error.diagnostics).kind ===
          :nonscalar_distribution_in_proposal_term
    @test only(unit_vector_error.diagnostics).source isa SourceLocation

    marker_cell = CellKind(:marker_cell; extinction = RetireAtZero())
    marker_medium = MediumKind(:marker_medium)
    marker_field = FieldState(:marker_field; initial = 0.0)
    marker_base = @statements begin
        Lattice((2, 2))
        marker_cell
        marker_medium
        marker_field
        Protocol(Sweep(); name = :marker_protocol)
    end
    unsupported_chemotaxis = (
        (
            only(@statements begin
                Chemotaxis(
                    marker_cell,
                    marker_field;
                    strength = 1.0,
                    mode = RetractionsOnly(),
                )
            end),
            :unsupported_chemotaxis_mode,
        ),
        (
            only(@statements begin
                Chemotaxis(
                    marker_cell,
                    marker_field;
                    strength = 1.0,
                    mode = ExtensionsAndRetractions(),
                )
            end),
            :unsupported_chemotaxis_mode,
        ),
        (
            only(@statements begin
                Chemotaxis(
                    marker_cell,
                    marker_field;
                    strength = 1.0,
                    sample = Multilinear(),
                )
            end),
            :unsupported_chemotaxis_sampling,
        ),
    )
    for (statement, kind) in unsupported_chemotaxis
        marker_error = try
            complete(PottsSystem(
                name = Symbol(:invalid_, Symbol(statement_id(statement))),
                statements = StatementSet((marker_base, statement)),
            ))
            nothing
        catch caught
            caught
        end
        @test marker_error isa Potts.PottsValidationError
        @test only(marker_error.diagnostics).kind === kind
        @test only(marker_error.diagnostics).source isa SourceLocation
    end

    centered_field = only(@statements begin
        FieldState(
            :centered_field;
            initial = 0.0,
            placement = CellCentered(),
        )
    end)
    centered_error = try
        complete(PottsSystem(
            name = :unsupported_centered_field,
            statements = StatementSet((Lattice((2, 2)), centered_field)),
        ))
        nothing
    catch caught
        caught
    end
    @test centered_error isa Potts.PottsValidationError
    @test only(centered_error.diagnostics).kind ===
          :unsupported_field_placement
    @test only(centered_error.diagnostics).source isa SourceLocation

    invalid_phase_statements = @statements begin
        AcceptedCopyProcess(
            :misphased;
            effects = (Assign(activity, 1.0),),
            phase = AfterMCS(),
        )
    end
    @named invalid_phase = PottsSystem(
        statements = invalid_phase_statements,
        unknowns = [activity],
        independent_variables = [t],
    )
    phase_error = try
        complete(invalid_phase)
        nothing
    catch caught
        caught
    end
    @test phase_error isa Potts.PottsValidationError
    @test only(phase_error.diagnostics).kind === :illegal_effect_phase
    @test only(phase_error.diagnostics).source isa SourceLocation
end
