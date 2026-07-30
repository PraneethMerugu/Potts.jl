@testset "completion and diagnostics" begin
    @variables t activity(t)
    @parameters target strength maximum activity_strength
    endothelial = CellKind(:endothelial)
    extracellular = MediumKind(:extracellular)
    copy = ProposalContext(:copy)

    model_statements = StatementSet((
        Lattice(
            (8, 8);
            spacing = (1.0, 1.0),
            relations = (proposal = Moore(), contact = Moore()),
        ),
        endothelial,
        extracellular,
        Volume(endothelial; target, strength),
        ContactEnergy([
            (extracellular ↔ endothelial) => 6.0,
            (endothelial ↔ endothelial) => 2.0,
        ]),
        SiteState(
            activity;
            owner = endothelial,
            initial = 0.0,
            lifecycle = ClearOnOwnershipChange(),
        ),
        ActEnergy(
            endothelial,
            activity;
            maximum,
            strength = activity_strength,
            reduction = Moore(),
        ),
        AcceptedCopy(
            :activate,
            Assign(activity, maximum);
            when = copy.is_extension,
        ),
        Synchronous(
            :decay,
            Assign(activity, max(activity - 1, 0));
            phase = AfterMCS(),
        ),
        Protocol(Sweep(); name = :main),
    ))

    @named wortel = PottsSystem(
        statements = model_statements,
        unknowns = [activity],
        parameters = [target, strength, maximum, activity_strength],
        independent_variables = [t],
    )
    completed = complete(wortel)
    records = inspect(completed, Statements())
    @test length(records) == 12
    @test inspect(completed, Capabilities()).sequential
    @test inspect(completed, Capabilities()).checkerboard
    @test any(item -> item[2] isa AcceptedCopyEffect, inspect(completed, Effects()))
    @test any(item -> item[2] isa SynchronousAssign, inspect(completed, Effects()))
    @test length(string(semantic_fingerprint(completed))) == 64
    @test length(string(completed_system_fingerprint(completed))) == 64

    @named same_science = PottsSystem(
        statements = model_statements,
        unknowns = [activity],
        parameters = [target, strength, maximum, activity_strength],
        independent_variables = [t],
    )
    # Model name/hierarchy packaging does not enter the semantic fingerprint.
    @test semantic_fingerprint(complete(same_science)) ==
          semantic_fingerprint(completed)

    links = RelationshipState(:links; capacity = 4, maximum_degree = 2)
    edge_effect = Create(links, copy.source_cell, copy.target_cell)
    @named focal = PottsSystem(statements = StatementSet((
        links,
        AcceptedCopy(:create_link, edge_effect; when = copy.is_extension),
    )))
    focal_completed = complete(focal)
    @test !inspect(focal_completed, Capabilities()).checkerboard
    @test only(inspect(focal_completed, Capabilities()).checkerboard_rejections)[1] ==
          PottsToolkit.QualifiedStatementID((:focal,), StatementID(:create_link))

    @named invalid = PottsSystem(statements = StatementSet((
        CellKind(:duplicate),
        MediumKind(:duplicate),
    )))
    error = try
        complete(invalid)
        nothing
    catch caught
        caught
    end
    @test error isa PottsToolkit.PottsValidationError
    @test error.stage == :completion
    @test only(error.diagnostics).kind == :duplicate_statement_identity
end
