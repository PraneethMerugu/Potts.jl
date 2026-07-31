using LinearAlgebra

function _merks_delta_allocations(descriptor, context)
    return @allocated CorePotts._compiled_hamiltonian_delta(
        descriptor.evaluator,
        descriptor.role,
        context,
        context.runtime.program.descriptor_plan.domain_resources,
    )
end

@testset "visible Merks vasculogenesis fixture" begin
    # Reduced dimensions and duration keep this an ordinary test; every Merks
    # mechanism remains assembled directly in public V1 syntax.
    @variables t chemoattractant(t)
    @parameters begin
        A₀ = 10.0
        L₀ = 5.0
        λA = 4.0
        λL = 1.0
        μ = 8.0
        diffusion = 0.08
        secretion = 0.02
        decay = 0.01
        temperature = 15.0
    end

    endothelial = CellKind(:endothelial)
    border = CellKind(:border)
    extracellular = MediumKind(:extracellular)
    chemo_field = FieldState(
        chemoattractant;
        name = :field,
        initial = 0.0,
        diffusion,
        secretion,
        decay,
        substeps = 2,
        duration_per_mcs = 1.0,
        source_kind = endothelial,
    )
    field_equation = Differential(t)(chemoattractant) ~
                     diffusion * chemoattractant -
                     decay * chemoattractant + secretion

    model_statements = @statements begin
        Lattice(
            (18, 18);
            boundary = Closed(),
            relations = (
                proposal = Moore(1),
                contact = Moore(1),
                connectivity = Moore(1),
                field_stencil = VonNeumann(1),
            ),
        )
        endothelial
        border
        extracellular
        chemo_field
        EquationProcess(
            :field_dynamics,
            [field_equation];
            writes = [chemoattractant],
            solver = ExplicitDiffusion(),
            cadence = EveryMCS(),
            duration_per_mcs = 1.0,
            substeps = 2,
        )
        Volume(endothelial; target = A₀, strength = λA)
        Elongation(endothelial; target = L₀, strength = λL)
        ContactEnergy([
            (endothelial ↔ endothelial) => 8.0,
            (endothelial ↔ extracellular) => 4.0,
            (endothelial ↔ border) => 20.0,
            (extracellular ↔ extracellular) => 0.0,
        ])
        Chemotaxis(
            endothelial,
            chemo_field;
            strength = μ,
            mode = ExtensionsOnly(),
            sample = Nearest(),
        )
        LocalConnectivity(endothelial)
        Protocol(
            Sweep(:cpm; attempts = AttemptsPerSite(1), temperature),
            ObserveStage(:morphology; every = 1);
            name = :operator_split,
        )
        Observation(:field_mass, chemoattractant)
    end

    @named merks = PottsSystem(
        statements = model_statements,
        equations = [field_equation],
        unknowns = [chemoattractant],
        parameters = [
            A₀, L₀, λA, λL, μ, diffusion, secretion, decay, temperature,
        ],
        independent_variables = [t],
        initial_conditions = Dict(chemoattractant => 0.0),
    )
    executable = compile(
        complete(merks);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    capabilities = inspect(executable, Capabilities())
    @test capabilities.field
    @test capabilities.elongation
    @test size(
        getfield(getfield(executable, :core_program), :field).stencil_offsets,
        2,
    ) == 4

    labels = zeros(Int, 18, 18)
    labels[4:6, 4:6] .= 1
    labels[11:13, 5:7] .= 2
    labels[7:9, 12:14] .= 3
    initial_field = zeros(Float64, size(labels))
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = fill(endothelial, 3),
            medium = extracellular,
        ),
        values = [chemoattractant => initial_field],
    )
    problem = PottsProblem(executable, initial, (0, 3); seed = 2006)
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
    elongation_descriptor = only([
        descriptor
        for group in executable.core_program.descriptor_plan.groups
        for descriptor in group.launch.instances
        if descriptor.role isa CorePotts.HamiltonianRole &&
           executable.core_program.descriptor_plan.source_table[
               descriptor.source_handle
           ].local_id == StatementID(:elongation_endothelial)
    ])
    elongation_source = CartesianIndex(4, 4)
    elongation_target = CartesianIndex(3, 4)
    elongation_context = CorePotts._ProposalEvaluationContext(
        core_runtime,
        elongation_source,
        elongation_target,
        core_runtime.ownership[elongation_target],
        core_runtime.ownership[elongation_source],
        1,
        0,
    )
    local_elongation_delta = CorePotts._compiled_hamiltonian_delta(
        elongation_descriptor.evaluator,
        elongation_descriptor.role,
        elongation_context,
        executable.core_program.descriptor_plan.domain_resources,
    )
    _merks_delta_allocations(elongation_descriptor, elongation_context)
    @test _merks_delta_allocations(
        elongation_descriptor, elongation_context
    ) == 0
    function independent_cell_length(owner_map, cell)
        sites = findall(==(cell), owner_map)
        isempty(sites) && return 0.0
        coordinates = [
            (site[1] - 0.5, site[2] - 0.5) for site in sites
        ]
        center = (
            sum(first, coordinates) / length(coordinates),
            sum(last, coordinates) / length(coordinates),
        )
        covariance = zeros(Float64, 2, 2)
        for point in coordinates
            displacement = (point[1] - center[1], point[2] - center[2])
            for row in 1:2, column in 1:2
                covariance[row, column] +=
                    displacement[row] * displacement[column]
            end
        end
        covariance ./= length(coordinates)
        return 4.0 * sqrt(maximum(eigvals(Symmetric(covariance))))
    end
    independent_elongation_energy(owner_map) = sum(
        (independent_cell_length(owner_map, cell_index) - 5.0)^2
        for cell_index in 1:3
    )
    after_elongation_copy = copy(labels)
    after_elongation_copy[elongation_target] = labels[elongation_source]
    @test local_elongation_delta ≈
          independent_elongation_energy(after_elongation_copy) -
          independent_elongation_energy(labels)
    @test core_runtime.ownership == labels
    trajectory = solve(
        problem; save_everystep = true, observables = (:field_mass,)
    )
    replay = solve(problem; save_everystep = true)
    independent = solve(
        remake(problem; replica = 2); save_everystep = true
    )
    @test all(
        left.ownership == right.ownership && left.field == right.field
        for (left, right) in zip(trajectory, replay)
    )
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(trajectory, independent)
    )
    @test sum(trajectory(3).field) > 0
    @test all(isfinite, trajectory(3).field)
    @test trajectory(3)[:field_mass] == trajectory(3).field
end
