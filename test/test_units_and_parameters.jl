@testset "units and runtime parameters" begin
    @parameters begin
        target = 8.0u"μm^2"
        strength = 2.0e-12u"J"
        temperature = 4.0e-12u"J"
    end
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named dimensional = PottsSystem(
        statements = StatementSet((
            Lattice(
                (6, 6);
                spacing = (1.0u"μm", 1.0u"μm"),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            Volume(cell; target, strength),
            ContactEnergy([
                (cell ↔ medium) => 6.0e-12u"J",
                (cell ↔ cell) => 2.0e-12u"J",
            ]),
            Protocol(Sweep(; temperature); name = :main),
        )),
        parameters = [target, strength, temperature],
    )
    completed = complete(
        dimensional;
        reference_units = ReferenceUnits(
            length = 1.0u"μm",
            area = 1.0u"μm^2",
            energy = 1.0e-12u"J",
        ),
    )
    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    dimensional_records = inspect(completed, Statements())
    @test any(record -> !isempty(record.units), dimensional_records)
    @test all(
        record -> length(record.units) == length(record.reference_conversion),
        dimensional_records,
    )
    @test all(
        entry -> entry.unit === nothing ||
                 entry.unit isa PottsToolkit.ReferenceUnitDescriptor,
        executable.parameter_manifest,
    )
    @test all(
        descriptor -> descriptor isa PottsToolkit.ReferenceUnitDescriptor,
        executable.parameter_manifest.reference_units,
    )
    @test !any(
        descriptor -> descriptor isa DynamicQuantities.UnionAbstractQuantity,
        executable.parameter_manifest.reference_units,
    )
    @test executable.core_program.parameter_defaults == Float32[8, 2, 4]

    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    problem = PottsProblem(
        executable,
        initial,
        (0, 1);
        p = [
            target => 10.0u"μm^2",
            strength => 3.0e-12u"J",
            temperature => 5.0e-12u"J",
        ],
        seed = 1,
    )
    @test problem.parameters.values == (10.0f0, 3.0f0, 5.0f0)
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0, 1);
        p = [
            target => 10.0u"μm^2",
            strength => 3.0e-12u"J",
            temperature => 1.0u"μm",
        ],
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0, 1);
        p = [
            :unknown => 1.0,
            strength => 3.0e-12u"J",
            temperature => 5.0e-12u"J",
        ],
        seed = 1,
    )
end

@testset "compiler-proven structural parameter roles" begin
    @parameters capacity = 4
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    links = RelationshipState(
        :links;
        endpoints = Undirected(cell, cell),
        payload = (strength = 1.0, target = 2.0, maximum = 8.0),
        capacity,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    @named structural_model = PottsSystem(
        statements = StatementSet((
            Lattice((6, 6)),
            cell,
            medium,
            links,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        parameters = [capacity],
    )
    completed = complete(structural_model)
    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    schema = inspect(executable, PottsToolkit.ParameterSchema())
    @test isempty(schema.entries)
    @test only(schema.structural).name === :capacity
    @test only(schema.structural).value == 4

    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    @test_throws ArgumentError PottsProblem(
        executable, initial, (0, 1); p = [capacity => 5], seed = 1
    )

    @parameters unresolved_capacity
    unresolved_links = RelationshipState(
        :unresolved_links;
        endpoints = Undirected(cell, cell),
        payload = (strength = 1.0, target = 2.0, maximum = 8.0),
        capacity = unresolved_capacity,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    @named unresolved_model = PottsSystem(
        statements = StatementSet((
            Lattice((6, 6)),
            cell,
            medium,
            unresolved_links,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        parameters = [unresolved_capacity],
    )
    @test_throws ArgumentError complete(unresolved_model)
end

@testset "completion owns reference-unit validation" begin
    @parameters target = 8.0u"μm^2" strength = 2.0
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named missing_anchor = PottsSystem(
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            Volume(cell; target, strength),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        parameters = [target, strength],
    )
    @test_throws ArgumentError complete(missing_anchor)

    @named ambiguous_anchor = PottsSystem(
        statements = StatementSet((
            Lattice((4, 4); spacing = (1.0u"μm", 2.0u"μm")),
            cell,
            medium,
            Volume(cell; target = 8.0, strength = 2.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
    )
    @test_throws ArgumentError complete(ambiguous_anchor)
    @test iscomplete(complete(
        ambiguous_anchor;
        reference_units = ReferenceUnits(length = 1.0u"μm"),
    ))
end
