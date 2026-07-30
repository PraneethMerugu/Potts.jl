@testset "compilation and inspection" begin
    @parameters target=9.0 strength=2.0 temperature=4.0
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named source = PottsSystem(
        statements = StatementSet((
            Lattice(
                (10, 8);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(), contact = Moore()),
            ),
            cell,
            medium,
            Volume(cell; target, strength),
            ContactEnergy([
                (cell ↔ medium) => 6.0,
                (cell ↔ cell) => 2.0,
            ]),
            LocalConnectivity(cell),
            Protocol(
                Sweep(; attempts = AttemptsPerSite(2), temperature);
                name = :main,
            ),
        )),
        parameters = [target, strength, temperature],
    )
    completed = complete(source)
    @test_throws ArgumentError compile(
        source;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    @test_throws UndefKeywordError compile(
        completed; engine = SequentialEngine(), backend = CPUBackend()
    )

    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    checkerboard = compile(
        completed;
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    @test executable isa PottsExecutable
    @test checkerboard isa PottsExecutable
    @test inspect(executable, StoragePlan()).shape == (10, 8)
    @test inspect(executable, StoragePlan()).site_count == 80
    @test inspect(executable, Kernels()).live_state_allocated == false
    @test inspect(executable, Capabilities()).sequential
    @test length(string(PottsToolkit.executable_fingerprint(executable))) == 64
    @test PottsToolkit.executable_fingerprint(executable) !=
          PottsToolkit.executable_fingerprint(checkerboard)
    @test all(
        entry -> entry.default !== nothing,
        executable.parameter_manifest,
    )

    function forbidden(value, seen = IdSet())
        value === nothing && return false
        value isa Function && return true
        value isa DynamicQuantities.UnionAbstractQuantity && return true
        !(Symbolics.symbolic_type(value) isa
          SymbolicIndexingInterface.NotSymbolic) && return true
        value in seen && return false
        push!(seen, value)
        if value isa AbstractArray || value isa Tuple || value isa NamedTuple
            return any(item -> forbidden(item, seen), value)
        elseif isstructtype(typeof(value))
            return any(
                field -> forbidden(getfield(value, field), seen),
                fieldnames(typeof(value)),
            )
        end
        return false
    end
    @test !forbidden(getfield(executable, :core_program))

    links = RelationshipState(:links; capacity = 8)
    copy_context = ProposalContext(:copy)
    @named rejected = PottsSystem(statements = StatementSet((
        Lattice((4, 4)),
        cell,
        medium,
        links,
        AcceptedCopy(
            :link,
            Create(links, copy_context.source_cell, copy_context.target_cell),
        ),
        Protocol(Sweep(); name = :main),
    )))
    @test_throws ArgumentError compile(
        complete(rejected);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
end
