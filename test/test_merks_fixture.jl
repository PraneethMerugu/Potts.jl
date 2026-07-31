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
