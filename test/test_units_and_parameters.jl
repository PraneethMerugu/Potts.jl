@testset "scheduled units and runtime parameters" begin
    @parameters begin
        unit_target = 8.0u"μm^2"
        unit_strength = 2.0e-12u"J"
        unit_temperature = 4.0e-12u"J"
    end
    cell = CellKind(:unit_cell; extinction = RetireAtZero())
    medium = MediumKind(:unit_medium)
    source = PottsSystem(
        name = :dimensional_scheduled_model,
        statements = StatementSet((
            Lattice(
                (6, 6);
                spacing = (1.0u"μm", 1.0u"μm"),
                relations = (
                    proposal = VonNeumann(),
                    contact = Moore(),
                ),
            ),
            cell,
            medium,
            Volume(cell; target = unit_target, strength = unit_strength),
            ContactEnergy([
                (cell ↔ medium) => 6.0e-12u"J",
                (cell ↔ cell) => 2.0e-12u"J",
            ]),
            Protocol(Sweep(; temperature = unit_temperature); name = :main),
        )),
        parameters = [unit_target, unit_strength, unit_temperature],
    )
    completed = complete(
        source;
        reference_units = ReferenceUnits(
            length = 1.0u"μm",
            area = 1.0u"μm^2",
            energy = 1.0e-12u"J",
        ),
    )
    records = inspect(completed, Statements())
    @test any(record -> !isempty(record.units), records)
    @test all(
        record -> length(record.units) == length(record.reference_conversion),
        records,
    )

    scheduled = mtkcompile(completed)
    schema = inspect(scheduled, ParameterSchema())
    @test Tuple(entry.name for entry in schema.runtime) ==
          (:unit_target, :unit_strength, :unit_temperature)
    @test schema.runtime[1].default == 8.0u"μm^2"
    @test schema.runtime[2].default == 2.0e-12u"J"
    @test all(!entry.required for entry in schema.runtime)

    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    problem = PottsProblem(
        scheduled,
        initial,
        (0, 1);
        p = (
            unit_target => 10.0u"μm^2",
            unit_strength => 3.0e-12u"J",
            unit_temperature => 5.0e-12u"J",
        ),
        seed = 1,
    )
    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    @test SymbolicIndexingInterface.getp(integrator, unit_target)(integrator) ==
          10.0f0
    @test SymbolicIndexingInterface.getp(integrator, unit_strength)(integrator) ==
          3.0f0
    @test SymbolicIndexingInterface.getp(
        integrator, unit_temperature
    )(integrator) == 5.0f0

    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0, 1);
        p = (
            unit_target => 10.0u"μm^2",
            unit_strength => 3.0e-12u"J",
            unit_temperature => 1.0u"μm",
        ),
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0, 1);
        p = (
            :unknown => 1.0,
            unit_strength => 3.0e-12u"J",
            unit_temperature => 5.0e-12u"J",
        ),
        seed = 1,
    )
end

@testset "scheduled structural parameter roles" begin
    @parameters relationship_capacity = 4
    cell = CellKind(:structural_cell; extinction = RetireAtZero())
    medium = MediumKind(:structural_medium)
    links = RelationshipState(
        :structural_links;
        endpoints = Undirected(cell, cell),
        payload = (strength = 1.0, target = 2.0, maximum = 8.0),
        capacity = relationship_capacity,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    source = PottsSystem(
        name = :structural_parameter_model,
        statements = StatementSet((
            Lattice((6, 6)),
            cell,
            medium,
            links,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        parameters = [relationship_capacity],
    )
    scheduled = mtkcompile(source)
    schema = inspect(scheduled, ParameterSchema())
    @test isempty(schema.runtime)
    @test only(schema.structural).name === :relationship_capacity
    @test only(schema.structural).default == 4

    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0, 1);
        p = (relationship_capacity => 5,),
        seed = 1,
    )

    @parameters unresolved_capacity
    unresolved_links = RelationshipState(
        :unresolved_links;
        endpoints = Undirected(cell, cell),
        payload = (strength = 1.0, target = 2.0, maximum = 8.0),
        capacity = unresolved_capacity,
        maximum_degree = 2,
    )
    unresolved = PottsSystem(
        name = :unresolved_structural_parameter,
        statements = StatementSet((
            Lattice((6, 6)),
            cell,
            medium,
            unresolved_links,
            Protocol(Sweep(); name = :main),
        )),
        parameters = [unresolved_capacity],
    )
    @test_throws ArgumentError complete(unresolved)
end

@testset "completion owns reference-unit validation" begin
    @parameters incomplete_target = 8.0u"μm^2" incomplete_strength = 2.0
    cell = CellKind(:reference_cell; extinction = RetireAtZero())
    medium = MediumKind(:reference_medium)
    missing_anchor = PottsSystem(
        name = :missing_reference_anchor,
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            Volume(
                cell;
                target = incomplete_target,
                strength = incomplete_strength,
            ),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        parameters = [incomplete_target, incomplete_strength],
    )
    @test_throws ArgumentError complete(missing_anchor)

    ambiguous_anchor = PottsSystem(
        name = :ambiguous_reference_anchor,
        statements = StatementSet((
            Lattice((4, 4); spacing = (1.0u"μm", 2.0u"μm")),
            cell,
            medium,
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
    )
    @test_throws ArgumentError complete(ambiguous_anchor)
    @test iscomplete(complete(
        ambiguous_anchor;
        reference_units = ReferenceUnits(length = 1.0u"μm"),
    ))
end

@testset "unit transfer proves fixed powers and roots" begin
    @parameters begin
        transfer_length = 2.0u"m"
        transfer_area = 4.0u"m^2"
        transfer_exponent = 2.0
    end
    cell = CellKind(:unit_transfer_cell; extinction = RetireAtZero())
    medium = MediumKind(:unit_transfer_medium)
    reference_units = ReferenceUnits(
        length = 1.0u"m",
        area = 1.0u"m^2",
    )

    function unit_transfer_model(name, expression; exponent = false)
        return PottsSystem(
            name = name,
            statements = StatementSet((
                Lattice((2, 2); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                ProposalDrive(:unit_transfer_drive, expression),
                Protocol(Sweep(); name = :main),
            )),
            parameters = exponent ?
                [transfer_length, transfer_area, transfer_exponent] :
                [transfer_length, transfer_area],
        )
    end

    @test iscomplete(complete(unit_transfer_model(
        :fixed_power_units,
        transfer_length^2 - transfer_area,
    ); reference_units))
    @test iscomplete(complete(unit_transfer_model(
        :square_root_units,
        sqrt(transfer_area) - transfer_length,
    ); reference_units))

    incompatible = try
        complete(unit_transfer_model(
            :incompatible_root_units,
            sqrt(transfer_area) + transfer_area,
        ); reference_units)
        nothing
    catch caught
        caught
    end
    @test incompatible isa PottsToolkit.PottsValidationError
    @test only(incompatible.diagnostics).kind === :illegal_operation_units

    parameterized = try
        complete(unit_transfer_model(
            :parameterized_power_units,
            transfer_length^transfer_exponent;
            exponent = true,
        ); reference_units)
        nothing
    catch caught
        caught
    end
    @test parameterized isa PottsToolkit.PottsValidationError
    @test only(parameterized.diagnostics).kind === :illegal_operation_units
end
