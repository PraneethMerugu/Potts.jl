@testset "statements and traversal" begin
    @variables t x(t)
    @parameters k
    site_anchor = SiteBinding(:site_anchor)
    cell_anchor = CellBinding(:cell_anchor)

    declarations = (
        CellKind(:cell; extinction = RetireAtZero()),
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
        HamiltonianTerm(
            :energy;
            domain = sites(:lattice),
            anchor = site_anchor,
            expression = k * x,
        ),
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
            anchor = cell_anchor,
            expression = cell_volume(anchor_value(cell_anchor)) == 0,
            effects = (Retire(
                cell_anchor; on_inadmissible = ErrorOnInadmissible()
            ),),
            phase = Lifecycle(),
        ),
    )
    tail = (
        Observation(:observation, x),
        Protocol(:protocol; stages = (Sweep(),)),
        RegisteredStatement(:registered, :example, v"1.0.0", x),
    )
    all_statements = (declarations..., states..., proposals..., processes..., tail...)

    @test length(all_statements) == 22
    @test length(unique(PottsToolkit.statement_kind.(all_statements))) == 22
    @test all(statement -> statement_source(statement) isa UnknownSource, all_statements)

    set = StatementSet((Lattice((4, 4); relations = (proposal = Moore(),)),
        all_statements...))
    @test length(set) == 24
    @test all(statement -> statement isa AbstractPottsStatement, set)

    captured = @statements begin
        CellKind(:captured_cell; extinction = RetireAtZero())
        HamiltonianTerm(
            :captured_energy;
            domain = sites(:lattice),
            anchor = site_anchor,
            expression = k * x,
        )
    end
    @test length(captured) == 2
    @test all(statement -> statement_source(statement) isa SourceLocation, captured)
    @test occursin("HamiltonianTerm", statement_source(captured[2]).expression)

    mapped = PottsToolkit.map_symbolics(
        value -> substitute(value, Dict(k => 4.0)),
        HamiltonianTerm(
            :mapped;
            domain = sites(:lattice),
            anchor = site_anchor,
            expression = k * x,
            coefficient = k,
        ),
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
    @test PottsToolkit._statement_options(links).maximum_degree == 16
    edge = RelationshipBinding(:edge, links)
    @test occursin("endpoint_a", string(edge.a))
    @test occursin("edge_payload", string(edge.strength))
    @test draw(Normal(0.0, k), DrawKey(:noise)) isa Num

    query_contracts = (
        (contact_edge_count, 2, contact_edge_count(x, k)),
        (contact_measure, 3, contact_measure(x, k, 1.0)),
        (boundary_site_count, 2, boundary_site_count(x, k)),
        (neighbor_cell_count, 2, neighbor_cell_count(x, k)),
        (neighbor_property_sum, 3, neighbor_property_sum(x, k, x)),
        (
            neighbor_property_mean,
            4,
            neighbor_property_mean(x, k, x, 0.0),
        ),
        (
            global_interface_measure,
            3,
            global_interface_measure(x, k, 1.0),
        ),
    )
    for (operation, arity, expression) in query_contracts
        @test expression isa Num
        transfer = PottsToolkit.operation_transfer(operation, arity)
        @test transfer.arity == arity:arity
        @test transfer.allowed_roles == (:observation,)
        @test transfer.allowed_phases == (:none,)
        @test !transfer.cpu
        @test !transfer.gpu
    end
    @test !applicable(neighbor_property_mean, x, k, x)
    collection_error = try
        neighbor_cells(x, k)
        nothing
    catch caught
        caught
    end
    @test collection_error isa ArgumentError
    @test occursin("collection-valued settled-snapshot", sprint(
        showerror, collection_error
    ))
    @test occursin("G5H-4", sprint(showerror, collection_error))
    @test_throws ArgumentError Protocol(:invalid; stages = (EveryMCS(),))

    phase_cell = CellKind(:phase_cell; extinction = RetireAtZero())
    phase_medium = MediumKind(:phase_medium)
    phase_completed = complete(PottsSystem(
        name = :phase_contract,
        statements = StatementSet((
            Lattice((2, 2)),
            phase_cell,
            phase_medium,
            Observation(:settled_metadata, 1.0),
            Protocol(Sweep(); name = :phase_protocol),
        )),
    ))
    phase_records = inspect(phase_completed, Schedule())
    observation_record = only(filter(
        record -> record.kind === :Observation, phase_records
    ))
    @test observation_record.phase === nothing
    @test isempty(observation_record.ordering_dependencies)

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
        scientific_category = :observation,
        energy_domain = nothing,
        affected_region = nothing,
        reference_semantics = :dimensionless,
        descriptor_payload_type = CorePotts.CompilerSPI.EmptyDescriptorPayload,
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
    @test_throws ArgumentError HamiltonianTerm(
        :forged_public_origin;
        domain = sites(:lattice),
        anchor = site_anchor,
        expression = x,
        __registered_origin = (
            schema = :example,
            version = v"1.0.0",
            serialization_identity = "example-schema-v1",
            lowering_identity = :lower_example,
            descriptor_payload_type = CorePotts.CompilerSPI.EmptyDescriptorPayload,
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
