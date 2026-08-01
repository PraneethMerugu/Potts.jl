isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("fixtures/NeutralExternalTerms.jl")

function _g5_relationship_fixture(engine; seed = UInt64(5), initial_edges = nothing)
    @parameters g5_pair_weight = 1.25 g5_temperature = 1.5
    cell = CellKind(:g5_external_pair_cell)
    medium = MediumKind(:g5_external_pair_medium)
    proposal = ProposalContext(:g5_external_pair_copy)
    fixture = NeutralExternalTerms.bounded_pair_fixture(
        cell, g5_pair_weight, proposal
    )
    relationship = only(filter(
        statement -> statement isa RelationshipState,
        collect(fixture),
    ))
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice(
                (5, 5);
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            fixture,
            Protocol(Sweep(; temperature = g5_temperature); name = :main),
        )),
        parameters = [g5_pair_weight, g5_temperature],
    )
    completed = complete(model; registry = NeutralExternalTerms.registry())
    executable = compile(
        completed;
        engine,
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 5, 5)
    labels[2, 2] = 1
    labels[2, 3:4] .= 2
    values = initial_edges === nothing ? Pair[] : [relationship => initial_edges]
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell], medium
        ),
        values = values,
    )
    problem = PottsProblem(executable, initial, (0, 2); seed)
    return (; completed, executable, relationship, problem)
end

@testset "G5 generic relationship and lifecycle runtime" begin
    fixture = _g5_relationship_fixture(CheckerboardEngine())
    capabilities = inspect(fixture.completed, Capabilities())
    @test capabilities.checkerboard
    @test isempty(capabilities.checkerboard_rejections)
    @test fixture.executable.core_program.stage_plan.accepted_count == 1

    runtime = init(fixture.problem; save_start = false).runtime
    transaction = only(
        runtime.stage_buffers.relationship_transactions
    )
    maximum_batch = Int(
        runtime.program.checkerboard_plan.maximum_color_size
    ) * Int(runtime.program.attempts_per_site)
    @test length(transaction.requests) >= maximum_batch
    @test length(transaction.requests) == 16

    CorePotts.advance_mcs!(runtime)
    relationships = only(runtime.relationships)
    @test runtime.accepted == 3
    @test count(relationships.active) == 1
    edge = only(findall(relationships.active))
    @test (relationships.endpoint_a[edge], relationships.endpoint_b[edge]) ==
          (Int32(1), Int32(2))
    @test (relationships.generation_a[edge], relationships.generation_b[edge]) ==
          (UInt32(1), UInt32(1))
    @test map(values -> values[edge], relationships.payload) ==
          (1.25, 0.0, 1.25)
    @test relationships.degree == Int16[1, 1]
    @test relationships.incident_edges[1, :] == Int32[edge, edge]

    checkpoint_value = CorePotts.program_checkpoint(runtime)
    restored = CorePotts.restore_program_checkpoint(
        runtime.program, checkpoint_value
    )
    restored_relationships = only(restored.relationships)
    @test restored_relationships.active == relationships.active
    @test restored_relationships.endpoint_a == relationships.endpoint_a
    @test restored_relationships.endpoint_b == relationships.endpoint_b
    @test restored_relationships.payload == relationships.payload
    @test restored_relationships.degree == relationships.degree
    @test restored_relationships.incident_edges == relationships.incident_edges

    lifecycle_fixture = _g5_relationship_fixture(
        CheckerboardEngine();
        seed = UInt64(6),
        initial_edges = [(
            1,
            2,
            (score = -1.0, cutoff = 0.0, marker = 7.0),
        )],
    )
    lifecycle_runtime = init(
        lifecycle_fixture.problem; save_start = false
    ).runtime
    CorePotts._execute_after_mcs_stage!(lifecycle_runtime)
    @test count(only(lifecycle_runtime.relationships).active) == 0
end
