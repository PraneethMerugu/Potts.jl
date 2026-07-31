@testset "statements and traversal" begin
    @variables t x(t)
    @parameters k

    declarations = (
        CellKind(:cell),
        MediumKind(:medium),
        LatticeDomain(:lattice; shape = (8, 8)),
        SpatialRelation(:proposal; neighborhood = Moore()),
    )
    states = (
        SiteState(:site; initial = 0.0),
        CellState(:cell_state; initial = 0.0),
        MediumState(:medium_state; initial = 0.0),
        ModelState(:model_state; initial = 0.0),
        FieldState(:field; initial = 0.0),
        HistoryState(:history; initial = 0.0),
        RelationshipState(:links; capacity = 8),
    )
    proposals = (
        ProposalEnergy(:energy, k * x),
        ProposalDrive(:drive, x),
        ProposalConstraint(:constraint, x > 0),
        ProposalModifier(:modifier, k),
    )
    processes = (
        SynchronousProcess(:sync; effects = (Assign(x, k),), phase = AfterMCS()),
        AcceptedCopyProcess(
            :copy; expression = true, effects = (Assign(x, k),),
            phase = AcceptedCopy(),
        ),
        RelationshipProcess(
            :relationships; domain = edges(states[end]),
            effects = (Remove(states[end], :edge),),
            phase = RelationshipCommit(),
        ),
        LifecycleProcess(
            :lifecycle; domain = cells(declarations[1]),
            effects = (Retire(:cell),), phase = Lifecycle(),
        ),
    )
    tail = (
        EquationProcess(:equations, [x ~ k]; writes = [x]),
        Observation(:observation, x),
        Protocol(:protocol; stages = (Sweep(),)),
        RegisteredStatement(:registered, :example, v"1.0.0", x),
    )
    all_statements = (declarations..., states..., proposals..., processes..., tail...)

    @test length(all_statements) == 23
    @test length(unique(PottsToolkit.statement_kind.(all_statements))) == 23
    @test all(statement -> statement_source(statement) isa UnknownSource, all_statements)

    set = StatementSet((Lattice((4, 4); relations = (proposal = Moore(),)),
        all_statements...))
    @test length(set) == 25
    @test all(statement -> statement isa AbstractPottsStatement, set)

    captured = @statements begin
        CellKind(:captured_cell)
        ProposalEnergy(:captured_energy, k * x)
    end
    @test length(captured) == 2
    @test all(statement -> statement_source(statement) isa SourceLocation, captured)
    @test occursin("ProposalEnergy", statement_source(captured[2]).expression)

    mapped = PottsToolkit.map_symbolics(
        value -> substitute(value, Dict(k => 4.0)),
        ProposalEnergy(:mapped, k * x; coefficient = k),
    )
    @test occursin("4.0", sprint(show, mapped))
    mapped_effect = PottsToolkit.map_symbolics(
        value -> substitute(value, Dict(k => 4.0)),
        AcceptedCopyProcess(
            :mapped_effect;
            expression = x > 0,
            effects = (Assign(x, k),),
            phase = AcceptedCopy(),
        ),
    )
    @test only(PottsToolkit._statement_arguments(mapped_effect).effects).value == 4.0
    mapped_protocol = PottsToolkit.map_symbolics(
        value -> substitute(value, Dict(k => 4.0)),
        Protocol(Sweep(; temperature = k); name = :mapped_protocol),
    )
    @test only(
        PottsToolkit._statement_arguments(mapped_protocol).stages
    ).options.temperature == 4.0

    copy = ProposalContext(:copy)
    @test occursin("source_cell", string(copy.source_cell))
    @test occursin("is_extension", string(copy.is_extension))
    links = RelationshipState(:focal_links; capacity = 16)
    edge = RelationshipBinding(:edge, links)
    @test occursin("endpoint_a", string(edge.a))
    @test occursin("edge_payload", string(edge.strength))
    @test draw(Normal(0.0, k), DrawKey(:noise)) isa Num

    contract = (
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
        reference_semantics = :dimensionless,
        descriptor_payload_type = CorePotts.EmptyDescriptorPayload,
        serialization_identity = "example-schema-v1",
        lowering_identity = :lower_example,
    )
    registry = register_statement(
        default_statement_registry(), :example, v"1.0.0", contract
    )
    @test register_statement(
        registry, :example, v"1.0.0", contract
    ) === registry
    @test_throws ArgumentError register_statement(
        registry,
        :example,
        v"1.0.0",
        merge(contract, (serialization_identity = "different-schema",)),
    )
    @test_throws ArgumentError register_statement(
        default_statement_registry(),
        :invalid,
        v"1.0.0",
        merge(contract, (capabilities = (sequential = true,),)),
    )
    @test_throws ArgumentError RegisteredStatement(
        :host_callback,
        :example,
        v"1.0.0",
        x;
        callback = identity,
    )
    @test_throws ArgumentError ProposalEnergy(
        :forged_public_origin,
        x;
        __registered_origin = (
            schema = :example,
            version = v"1.0.0",
            serialization_identity = "example-schema-v1",
            lowering_identity = :lower_example,
            descriptor_payload_type = CorePotts.EmptyDescriptorPayload,
        ),
    )
    @test_throws ArgumentError register_statement(
        default_statement_registry(),
        :host_contract,
        v"1.0.0",
        merge(contract, (unit_constraints = identity,)),
    )
    @test_throws ArgumentError register_statement(
        default_statement_registry(),
        :abstract_payload_contract,
        v"1.0.0",
        merge(contract, (descriptor_payload_type = AbstractString,)),
    )
    @test_throws ArgumentError register_statement(
        default_statement_registry(),
        :mutable_payload_contract,
        v"1.0.0",
        merge(contract, (descriptor_payload_type = Vector{Int},)),
    )
end
