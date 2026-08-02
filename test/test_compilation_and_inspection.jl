@testset "compilation and inspection" begin
    @parameters target=9.0 strength=2.0 temperature=4.0
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named source = PottsSystem(
        statements = StatementSet((
            Lattice(
                (10, 8);
                boundary = Periodic(),
                relations = (
                    proposal = VonNeumann(),
                    contact = Moore(),
                    connectivity = Moore(),
                    connectivity_background = VonNeumann(),
                ),
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

    @named invalid_connectivity = PottsSystem(
        statements = StatementSet((
            Lattice(
                (10, 8);
                relations = (
                    proposal = VonNeumann(),
                    connectivity = VonNeumann(),
                    connectivity_background = Moore(),
                ),
            ),
            cell,
            medium,
            LocalConnectivity(cell),
            Protocol(Sweep(); name = :main),
        )),
    )
    invalid_connectivity_error = try
        compile(
            complete(invalid_connectivity);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
        nothing
    catch error
        error
    end
    @test invalid_connectivity_error isa PottsToolkit.PottsValidationError
    @test occursin(
        "radius-one Moore foreground",
        sprint(showerror, invalid_connectivity_error),
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
    compiled_records = inspect(executable, Statements())
    @test all(record -> haskey(record, :provenance), compiled_records)
    @test all(record -> haskey(record, :resources), compiled_records)
    @test all(record -> haskey(record, :reference_conversion), compiled_records)
    @test inspect(executable, Capabilities()).sequential
    @test length(string(PottsToolkit.executable_fingerprint(executable))) == 64
    @test PottsToolkit.executable_fingerprint(executable) !=
          PottsToolkit.executable_fingerprint(checkerboard)
    checkerboard_conflicts = CorePotts.checkerboard_plan_report(
        checkerboard.core_program.checkerboard_plan
    ).conflict_displacements
    @test isempty(checkerboard_conflicts)
    @test checkerboard.core_program.checkerboard_plan.color_count == 1

    target_write = CorePotts.FiniteSpatialFootprint(
        CorePotts.ProposalTargetFootprintAnchor(), ((0, 0),)
    )
    source_write = CorePotts.FiniteSpatialFootprint(
        CorePotts.ProposalSourceFootprintAnchor(), ((0, 0),)
    )
    exclusive_access = CorePotts.ResourceAccess(
        (),
        (:external_neighborhood_state,),
        CorePotts.EmptyFootprint(),
        CorePotts.FootprintUnion((target_write, source_write)),
        CorePotts.ExclusiveWriteAccess(),
    )
    read_only_access = CorePotts.ResourceAccess(
        (:external_read_only_state,),
        (),
        CorePotts.FiniteSpatialFootprint(
            CorePotts.ProposalSourceFootprintAnchor(),
            ((-4, 0), (4, 0)),
        ),
        CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess(),
    )
    commutative_access = CorePotts.ResourceAccess(
        (),
        (:external_commutative_tracker,),
        CorePotts.EmptyFootprint(),
        source_write,
        CorePotts.CommutativeIntegerWriteAccess(),
    )
    exclusive_conflicts = PottsToolkit._checkerboard_conflict_displacements(
        CorePotts.ResourceAccess[exclusive_access],
        executable.core_program.proposal_offsets,
        Val(2),
    )
    policy_conflicts = PottsToolkit._checkerboard_conflict_displacements(
        CorePotts.ResourceAccess[
            read_only_access, commutative_access, exclusive_access,
        ],
        executable.core_program.proposal_offsets,
        Val(2),
    )
    @test !isempty(exclusive_conflicts)
    @test policy_conflicts == exclusive_conflicts
    exclusive_plan = CorePotts.CheckerboardPlan(
        executable.core_program.shape,
        executable.core_program.periodic,
        exclusive_conflicts,
    )
    @test exclusive_plan.color_count > 1

    write_offsets = Tuple(unique((
        (0, 0),
        Tuple(
            Tuple(executable.core_program.proposal_offsets[:, column])
            for column in axes(executable.core_program.proposal_offsets, 2)
        )...,
    )))
    function apply_color!(storage, plan, color, reverse_order)
        first_index = Int(plan.color_offsets[color])
        stop_index = Int(plan.color_offsets[color + 1]) - 1
        scheduled = plan.sites[first_index:stop_index]
        reverse_order && (scheduled = reverse(scheduled))
        indices = CartesianIndices(size(storage))
        collision_free = true
        for site in scheduled
            coordinates = Tuple(indices[Int(site)])
            for offset in write_offsets
                destination_index = CartesianIndex(ntuple(2) do dimension
                    mod1(
                        coordinates[dimension] + Int(offset[dimension]),
                        size(storage, dimension),
                    )
                end)
                collision_free &= storage[destination_index] == 0
                storage[destination_index] = site
            end
        end
        return storage, collision_free
    end
    for color in 1:Int(exclusive_plan.color_count)
        forward, forward_collision_free = apply_color!(
            zeros(Int32, executable.core_program.shape),
            exclusive_plan,
            color,
            false,
        )
        backward, backward_collision_free = apply_color!(
            zeros(Int32, executable.core_program.shape),
            exclusive_plan,
            color,
            true,
        )
        @test forward_collision_free
        @test backward_collision_free
        @test forward == backward
    end
    @test all(
        entry -> entry.default !== nothing,
        executable.parameter_manifest,
    )

    function forbidden(value, seen = IdSet())
        value === nothing && return false
        value isa Union{
            Number, Symbol, String, Bool, Type, VersionNumber,
        } && return false
        value isa Function && return !(
            Base.issingletontype(typeof(value)) &&
            !startswith(String(nameof(value)), "#")
        )
        value isa AbstractPottsStatement && return true
        value isa ModelingToolkitBase.AbstractSystem && return true
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
    @test !forbidden(executable)

    connectivity_descriptor = only([
        descriptor
        for group in executable.core_program.descriptor_plan.groups
        for descriptor in group.launch.instances
        if executable.core_program.descriptor_plan.source_table[
            descriptor.source_handle
        ].local_id == StatementID(:connectivity_cell)
    ])
    connectivity_footprint = CorePotts.descriptor_resource_access(
        connectivity_descriptor
    ).footprint
    @test connectivity_footprint isa CorePotts.FiniteSpatialFootprint
    @test length(connectivity_footprint.offsets) == 8
    @test (-1, -1) in connectivity_footprint.offsets
    connectivity_labels = zeros(Int, 10, 8)
    connectivity_target = CartesianIndex(5, 4)
    connectivity_source = CartesianIndex(5, 3)
    connectivity_labels[connectivity_target] = 1
    connectivity_labels[CartesianIndex(4, 3)] = 1
    connectivity_labels[CartesianIndex(6, 5)] = 1
    connectivity_initial = PottsInitialState(
        ownership = LabelledCells(
            connectivity_labels; cells = [cell], medium
        ),
    )
    connectivity_runtime = init(PottsProblem(
        executable, connectivity_initial, (0, 1); seed = 0xc011ec7
    )).runtime
    connectivity_context = CorePotts._ProposalEvaluationContext(
        connectivity_runtime,
        connectivity_source,
        connectivity_target,
        Int32(1),
        Int32(0),
        1,
        0,
    )
    CorePotts._compiled_evaluate_static(
        connectivity_descriptor.evaluator, connectivity_context
    )
    @test !CorePotts._compiled_evaluate_static(
        connectivity_descriptor.evaluator, connectivity_context
    )
    @test @allocated(CorePotts._compiled_evaluate_static(
        connectivity_descriptor.evaluator, connectivity_context
    )) == 0
    @test size(executable.core_program.proposal_offsets, 2) == 4
    @test !hasfield(typeof(executable.core_program), :connectivity_kinds)

    links = RelationshipState(
        :links;
        endpoints = Undirected(cell, cell),
        capacity = 8,
    )
    copy_context = ProposalContext(:copy)
    @named accepted_relationship = PottsSystem(statements = StatementSet((
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
    relationship_checkerboard = compile(
        complete(accepted_relationship);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test relationship_checkerboard isa PottsExecutable

    proposal = ProposalContext(:copy)
    explicit_noise = draw(Normal(0.0, 0.05), DrawKey(:explicit_bias))
    @named symbolic_proposals = PottsSystem(statements = StatementSet((
        Lattice((4, 4)),
        cell,
        medium,
        Volume(cell; target = 4.0, strength = 1.0),
        ProposalDrive(
            :directional_drive,
            ifelse(proposal.is_extension, 0.0, 0.1),
        ),
        ProposalDrive(:custom_drive, explicit_noise),
        ProposalConstraint(
            :different_owners,
            proposal.source_cell != proposal.target_cell,
        ),
        ProposalModifier(:custom_modifier, -0.1),
        Protocol(Sweep(; temperature = 2.0); name = :main),
    )))
    symbolic_executable = compile(
        complete(symbolic_proposals);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    symbolic_program = getfield(symbolic_executable, :core_program)
    symbolic_groups = symbolic_program.descriptor_plan.groups
    @test length(symbolic_groups) == 5
    symbolic_roles = Tuple(
        CorePotts.descriptor_role(
            first(group.launch.instances)
        ) |> typeof
        for group in symbolic_groups
    )
    @test count(role -> role <: CorePotts.HamiltonianRole, symbolic_roles) == 1
    @test count(==(CorePotts.ProposalDriveRole), symbolic_roles) == 2
    @test count(==(CorePotts.ProposalConstraintRole), symbolic_roles) == 1
    @test count(==(CorePotts.ProposalModifierRole), symbolic_roles) == 1
    @test !forbidden(symbolic_program)

    proposal_labels = zeros(Int, 4, 4)
    proposal_labels[2:3, 2:3] .= 1
    proposal_initial = PottsInitialState(ownership = LabelledCells(
        proposal_labels; cells = [cell], medium
    ))
    proposal_problem = PottsProblem(
        symbolic_executable, proposal_initial, (0, 3); seed = 0x51
    )
    first_proposal_run = solve(proposal_problem; save_everystep = true)
    replayed_proposal_run = solve(proposal_problem; save_everystep = true)
    other_proposal_run = solve(
        remake(proposal_problem; replica = 2); save_everystep = true
    )
    @test getfield.(first_proposal_run.u, :ownership) ==
          getfield.(replayed_proposal_run.u, :ownership)
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(first_proposal_run, other_proposal_run)
    )

    @named external_interface = PottsSystem(
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            Volume(cell; target, strength),
            Protocol(Sweep(; temperature); name = :main),
            Observation(:cell_occupancy, occupancy(cell, :lattice)),
        )),
        parameters = [target, strength, temperature],
        inputs = [temperature],
        outputs = [:ownership, :cell_occupancy],
    )
    external_executable = compile(
        complete(external_interface);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    external_manifest = inspect(
        external_executable, PottsToolkit.ExternalIO()
    )
    @test Set(entry.identity for entry in external_manifest) ==
          Set((:temperature, :ownership, :cell_occupancy))
    @test only(filter(
        entry -> entry.identity === :ownership, external_manifest
    )).element_type === Int32
    @test only(filter(
        entry -> entry.identity === :cell_occupancy, external_manifest
    )).observation_index == 1

    @named overlapping_interface = PottsSystem(
        statements = statements(external_interface),
        parameters = [target, strength, temperature],
        inputs = [temperature],
        outputs = [temperature],
    )
    @test_throws ArgumentError compile(
        complete(overlapping_interface);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )

    @variables t marker(t)
    common_statements(initial_value) = StatementSet((
        Lattice((4, 4)),
        cell,
        medium,
        SiteState(
            marker; name = :marker, initial = initial_value
        ),
        Volume(cell; target, strength),
        Protocol(Sweep(; temperature); name = :main),
    ))
    first_initial_default = PottsSystem(
        statements = common_statements(1.0),
        unknowns = [marker],
        parameters = [target, strength, temperature],
        independent_variables = [t],
        name = :initial_default_schema,
    )
    second_initial_default = PottsSystem(
        statements = common_statements(9.0),
        unknowns = [marker],
        parameters = [target, strength, temperature],
        independent_variables = [t],
        name = :initial_default_schema,
    )
    first_completed = complete(first_initial_default)
    second_completed = complete(second_initial_default)
    @test semantic_fingerprint(first_completed) ==
          semantic_fingerprint(second_completed)
    first_executable = compile(
        first_completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    second_executable = compile(
        second_completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test PottsToolkit.executable_fingerprint(first_executable) ==
          PottsToolkit.executable_fingerprint(second_executable)
    @test only(inspect(first_executable, PottsToolkit.StateSchema())).initial ==
          1.0
    @test only(inspect(second_executable, PottsToolkit.StateSchema())).initial ==
          9.0
end
