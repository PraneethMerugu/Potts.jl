function _focal_delta_allocations(descriptor, context)
    return @allocated CorePotts._compiled_hamiltonian_delta(
        descriptor.evaluator,
        descriptor.role,
        context,
        context.runtime.program.descriptor_plan.domain_resources,
    )
end

@testset "visible focal-point-plasticity fixture" begin
    @parameters begin
        A₀ = 6.0
        λA = 2.0
        λf = 1.5
        Lf = 4.0
        Lbreak = 12.0
        temperature = 8.0
    end
    endothelial = CellKind(:endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:extracellular)
    focal_links = RelationshipState(
        :focal_links;
        endpoints = Undirected(endothelial, endothelial),
        payload = (strength = λf, target = Lf, maximum = Lbreak),
        capacity = 6,
        maximum_degree = 3,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:edge, focal_links)
    copy_context = ProposalContext(:copy)
    model_statements = @statements begin
        Lattice(
            (16, 10);
            boundary = Closed(),
            relations = (proposal = VonNeumann(), contact = Moore()),
        )
        endothelial
        extracellular
        focal_links
        Volume(endothelial; target = A₀, strength = λA)
        RelationshipEnergy(
            :focal_spring,
            edge,
            edge.strength * (
                distance(
                    unwrapped_center(edge.a),
                    unwrapped_center(edge.b),
                ) - edge.target
            )^2,
        )
        AcceptedCopy(
            :create_contact_link,
            Create(
                focal_links,
                copy_context.source_cell,
                copy_context.target_cell;
                payload = (
                    strength = λf,
                    target = Lf,
                    maximum = Lbreak,
                ),
            );
            when = new_contact(
                copy_context.source_cell, copy_context.target_cell
            ) & !linked(
                focal_links,
                copy_context.source_cell,
                copy_context.target_cell,
            ),
        )
        LifecycleProcess(
            :cleanup_retired_or_stretched_links;
            domain = edges(focal_links),
            expression = distance(
                unwrapped_center(edge.a), unwrapped_center(edge.b)
            ) > edge.maximum,
            effects = (Remove(focal_links, edge),),
            phase = Lifecycle(),
        )
        Protocol(Sweep(; temperature); name = :main)
        Observation(:link_count, degree(focal_links, 1))
    end
    @named focal = PottsSystem(
        statements = model_statements,
        parameters = [A₀, λA, λf, Lf, Lbreak, temperature],
    )
    completed = complete(focal)
    @test inspect(completed, Capabilities()).checkerboard
    checkerboard_executable = compile(
        completed;
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test checkerboard_executable.core_program.engine isa
          CorePotts.CheckerboardProgramEngine
    @test CorePotts.tracker_plan_report(
        checkerboard_executable.core_program.tracker_plan
    ).quantities == (:cell_volume, :cell_moments)
    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 16, 10)
    labels[3:4, 4:5] .= 1
    labels[10:11, 4:5] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = [focal_links => [(1, 2)]],
    )
    problem = PottsProblem(executable, initial, (0, 4); seed = 0xf0ca1)
    core_initial = PottsToolkit._core_initial_state(
        executable, initial, problem.seed, problem.replica
    )
    core_runtime = CorePotts.initialize_program(
        executable.core_program,
        core_initial,
        executable.core_program.parameter_defaults,
        problem.seed,
        problem.replica,
    )
    relationship_descriptor = only([
        descriptor
        for group in executable.core_program.descriptor_plan.groups
        for descriptor in group.launch.instances
        if descriptor.role isa CorePotts.HamiltonianRole &&
           descriptor.role.domain isa CorePotts.RelationshipEnergyDomainPlan
    ])
    source_site = CartesianIndex(3, 4)
    target_site = CartesianIndex(2, 4)
    relationship_context = CorePotts._ProposalEvaluationContext(
        core_runtime,
        source_site,
        target_site,
        core_runtime.ownership[target_site],
        core_runtime.ownership[source_site],
        1,
        0,
    )
    local_relationship_delta = CorePotts._compiled_hamiltonian_delta(
        relationship_descriptor.evaluator,
        relationship_descriptor.role,
        relationship_context,
        executable.core_program.descriptor_plan.domain_resources,
    )
    _focal_delta_allocations(
        relationship_descriptor, relationship_context
    )
    @test _focal_delta_allocations(
        relationship_descriptor, relationship_context
    ) == 0
    function independent_center(owner_map, cell)
        sites = findall(==(cell), owner_map)
        isempty(sites) && return nothing
        return ntuple(2) do dimension
            sum(site[dimension] - 0.5 for site in sites) / length(sites)
        end
    end
    function independent_relationship_energy(owner_map)
        first_center = independent_center(owner_map, 1)
        second_center = independent_center(owner_map, 2)
        separation = sqrt(sum(
            (first_center[index] - second_center[index])^2 for index in 1:2
        ))
        return 1.5 * (separation - 4.0)^2
    end
    after_relationship_copy = copy(labels)
    after_relationship_copy[target_site] = labels[source_site]
    @test local_relationship_delta ≈
          independent_relationship_energy(after_relationship_copy) -
          independent_relationship_energy(labels)
    @test core_runtime.ownership == labels
    stale_initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = [
            focal_links => [(
                1,
                2,
                (
                    generation_a = 2,
                    generation_b = 1,
                    strength = 1.5,
                    target = 4.0,
                    maximum = 12.0,
                ),
            )],
        ],
    )
    @test_throws ArgumentError PottsProblem(
        executable, stale_initial, (0, 1); seed = 1
    )
    trajectory = solve(
        problem; save_everystep = true, observables = (:link_count,)
    )
    @test count(trajectory(0).focal_links.active) == 1
    @test trajectory(0)[:link_count] == 1

    integrator = init(problem; save_start = false)
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(problem; checkpoint = captured, save_start = false))
    uninterrupted = solve(problem)
    @test resumed(4).focal_links.active ==
          uninterrupted(4).focal_links.active
    @test resumed(4).focal_links.endpoint_a ==
          uninterrupted(4).focal_links.endpoint_a
end
