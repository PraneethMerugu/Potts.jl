isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("fixtures/NeutralExternalTerms.jl")

struct IncidentLocalGuardedVector{T, V <: AbstractVector{T}} <:
        AbstractVector{T}
    values::V
    permitted::Int
    accesses::Base.RefValue{Int}
end

Base.IndexStyle(::Type{<:IncidentLocalGuardedVector}) = IndexLinear()
Base.size(values::IncidentLocalGuardedVector) = size(values.values)
function Base.getindex(values::IncidentLocalGuardedVector, index::Int)
    index == values.permitted || error(
        "relationship lookup escaped its endpoint incident list"
    )
    values.accesses[] += 1
    return @inbounds values.values[index]
end

function _g5_relationship_fixture(engine; seed = UInt64(5), initial_edges = nothing)
    @parameters g5_pair_weight = 1.25 g5_temperature = 1.5
    cell = CellKind(:g5_external_pair_cell; extinction = RetireAtZero())
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
    fixture = _g5_relationship_fixture(
        CheckerboardEngine(); seed = UInt64(1)
    )
    capabilities = inspect(fixture.completed, Capabilities())
    @test capabilities.checkerboard
    @test isempty(capabilities.checkerboard_rejections)
    @test fixture.executable.core_program.stage_plan.accepted_count == 1

    runtime = init(fixture.problem; save_start = false).runtime
    @test_throws ArgumentError CorePotts.adapt_checkerboard_workspace(
        Array, runtime.engine_workspace
    )
    transaction = only(
        runtime.stage_buffers.relationship_transactions
    )
    maximum_batch = Int(
        runtime.program.checkerboard_plan.maximum_color_size
    ) * Int(runtime.program.attempts_per_site)
    @test length(transaction.requests) == maximum_batch

    runtime = nothing
    for seed in UInt64(1):UInt64(256)
        candidate = init(remake(fixture.problem; seed); save_start = false).runtime
        CorePotts.advance_mcs!(candidate)
        candidate_relationships = only(candidate.relationships)
        edges = findall(candidate_relationships.active)
        length(edges) == 1 || continue
        candidate_edge = only(edges)
        endpoints = (
            candidate_relationships.endpoint_a[candidate_edge],
            candidate_relationships.endpoint_b[candidate_edge],
        )
        endpoints == (Int32(1), Int32(2)) || continue
        runtime = candidate
        break
    end
    @test runtime !== nothing
    runtime === nothing && error(
        "no qualified stochastic witness created the bounded pair"
    )
    relationships = only(runtime.relationships)
    @test runtime.accepted > 0
    @test count(relationships.active) == 1
    edge = only(findall(relationships.active))
    @test (relationships.endpoint_a[edge], relationships.endpoint_b[edge]) ==
          (Int32(1), Int32(2))
    @test (relationships.generation_a[edge], relationships.generation_b[edge]) ==
          (UInt32(1), UInt32(1))
    @test map(values -> values[edge], relationships.payload) ==
          (1.25, 0.0, 1.25)
    @test relationships.degree[1:2] == Int16[1, 1]
    @test all(iszero, relationships.degree[3:end])
    @test relationships.incident_edges[1, 1:2] == Int32[edge, edge]
    @test all(iszero, relationships.incident_edges[:, 3:end])

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

@testset "proposal relationship lookup is incident-local" begin
    capacity = 1024
    active = falses(capacity)
    endpoint_a = zeros(Int32, capacity)
    endpoint_b = zeros(Int32, capacity)
    active[777] = true
    endpoint_a[777] = Int32(1)
    endpoint_b[777] = Int32(2)
    active_accesses = Ref(0)
    endpoint_a_accesses = Ref(0)
    endpoint_b_accesses = Ref(0)
    state = (
        active = IncidentLocalGuardedVector(
            active, 777, active_accesses
        ),
        endpoint_a = IncidentLocalGuardedVector(
            endpoint_a, 777, endpoint_a_accesses
        ),
        endpoint_b = IncidentLocalGuardedVector(
            endpoint_b, 777, endpoint_b_accesses
        ),
        degree = Int16[1, 1],
        incident_edges = reshape(Int32[777, 777], 1, 2),
    )
    @test CorePotts._relationship_edge(state, Int32(1), Int32(2)) == 777
    @test active_accesses[] == 1
    @test endpoint_a_accesses[] == 1
    @test endpoint_b_accesses[] == 1

    endpoint_b[777] = Int32(3)
    @test CorePotts._relationship_edge(state, Int32(1), Int32(2)) === nothing
    @test active_accesses[] == 2
    @test endpoint_a_accesses[] == 2
    @test endpoint_b_accesses[] == 2
end

@testset "accepted ownership survives filtered relationship admission" begin
    @parameters filtered_pair_weight = 0.0 filtered_temperature = 1.0e6
    cell = CellKind(:filtered_pair_cell; extinction = RetireAtZero())
    medium = MediumKind(:filtered_pair_medium)
    proposal = ProposalContext(:filtered_pair_copy)
    relationships = RelationshipState(
        :filtered_pairs;
        endpoints = Undirected(cell, cell),
        payload = (score = filtered_pair_weight,),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:filtered_edge, relationships)
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice((5, 5); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            relationships,
            HamiltonianTerm(
                :filtered_pair_energy;
                domain = edges(relationships),
                anchor = edge,
                expression = filtered_pair_weight * edge.score,
            ),
            AcceptedCopy(
                :request_filtered_pair,
                Create(
                    relationships,
                    proposal.source_cell,
                    proposal.target_cell;
                    payload = (score = filtered_pair_weight,),
                );
                when = new_contact(
                    proposal.source_cell, proposal.target_cell
                ) & !linked(
                    relationships,
                    proposal.source_cell,
                    proposal.target_cell,
                ),
            ),
            Protocol(
                Sweep(; temperature = filtered_temperature); name = :main
            ),
        )),
        parameters = [filtered_pair_weight, filtered_temperature],
    )
    executable = compile(
        complete(model);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 5, 5)
    labels[2, 2] = 1
    labels[2, 3] = 2
    labels[2, 4] = 3
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell, cell], medium
        ),
        values = [
            relationships => [(1, 2, (score = 0.0,))],
        ],
    )
    filtered_run = nothing
    for seed in UInt64(1):UInt64(64)
        candidate = init(PottsProblem(
            executable, initial, (0, 1); seed
        ); save_start = false).runtime
        ownership_before = copy(candidate.ownership)
        CorePotts.advance_mcs!(candidate)
        transaction = only(
            candidate.stage_buffers.relationship_transactions
        )
        if transaction.filtered_total > 0
            filtered_run = (; runtime = candidate, ownership_before)
            break
        end
    end
    @test filtered_run !== nothing
    filtered_run = something(filtered_run)
    runtime = filtered_run.runtime
    ownership_before = filtered_run.ownership_before
    transaction = only(runtime.stage_buffers.relationship_transactions)
    @test runtime.settled
    @test runtime.accepted > 0
    @test runtime.ownership != ownership_before
    @test transaction.filtered_total > 0
    @test count(only(runtime.relationships).active) <= 1
end
