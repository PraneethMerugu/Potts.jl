using Test
import Metal
using Potts

function _relationship_stage_problem(effect_kind::Symbol)
    cell = CellKind(Symbol(effect_kind, :_cell); extinction = RetireAtZero())
    medium = MediumKind(Symbol(effect_kind, :_medium))
    relationship_name = Symbol(effect_kind, :_links)
    links = RelationshipState(
        relationship_name;
        endpoints = Undirected(cell, cell),
        payload = (score = 1.0f0, marker = 1.0f0),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(Symbol(effect_kind, :_edge), links)
    effect = effect_kind === :remove ? Remove(links, edge) : Retune(
        links, edge;
        payload = (score = edge.score + 2.0f0, marker = 0.0f0),
    )
    lifecycle = LifecycleProcess(
        Symbol(effect_kind, :_once);
        domain = edges(links),
        expression = edge.marker > 0.0f0,
        effects = (effect,),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = Symbol(effect_kind, :_relationship_stage),
        statements = StatementSet((
            Lattice((3, 1); boundary = Closed()),
            cell,
            medium,
            links,
            ProposalConstraint(Symbol(:freeze_, effect_kind), false),
            lifecycle,
            Protocol(Sweep(; temperature = 0.0f0); name = :main),
        )),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            reshape(Int32[1, 0, 2], 3, 1);
            cells = [cell, cell],
            medium,
        ),
        values = (links => [(1, 2)],),
    )
    return PottsProblem(
        mtkcompile(system), initial, (0, 1); seed = 0x6c06
    ), relationship_name
end

@testset "CorePotts relationship lifecycle composes with LocalMath Metal mechanics" begin
    Metal.allowscalar(false)
    for effect_kind in (:retune, :remove)
        problem, relationship_name = _relationship_stage_problem(effect_kind)
        cpu = solve(
            problem,
            CheckerboardSweepCPM();
            backend = Potts.CPUBackend(),
            scalar_type = Float32,
            save_everystep = true,
        )
        device = solve(
            problem,
            CheckerboardSweepCPM();
            backend = Potts.MetalBackend(),
            scalar_type = Float32,
            save_everystep = true,
        )
        cpu_relationship = last(cpu)[relationship_name]
        device_relationship = last(device)[relationship_name]
        @test Array(device_relationship.active) == cpu_relationship.active
        @test map(Array, device_relationship.payload) == cpu_relationship.payload
        if effect_kind === :retune
            edge = only(findall(cpu_relationship.active))
            @test cpu_relationship.payload[1][edge] == 3.0f0
            @test cpu_relationship.payload[2][edge] == 0.0f0
        else
            @test !any(cpu_relationship.active)
        end
    end
end
