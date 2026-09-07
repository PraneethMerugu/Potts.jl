@testset "scheduled finite three-site reference witness" begin
    @parameters finite_weight = log(2.0) finite_temperature = 1.0
    finite_cell = CellKind(:finite_cell; extinction = RetireAtZero())
    finite_medium = MediumKind(:finite_medium)
    finite_site = SiteBinding(:finite_site)
    finite_copy = ProposalContext(:finite_copy)
    source = PottsSystem(
        name = :finite_three_site,
        statements = StatementSet((
            # Keep the three-site state space while exercising the currently
            # supported two-dimensional CPU profile.
            Lattice(
                (3, 1);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            finite_cell,
            finite_medium,
            HamiltonianTerm(
                :finite_energy;
                domain = sites(:lattice),
                anchor = finite_site,
                expression = finite_weight * occupancy(finite_cell, finite_site),
            ),
            ProposalConstraint(
                :finite_nonempty_domains,
                ifelse(
                    finite_copy.is_extension,
                    cell_volume(finite_copy.source_cell) < 2,
                    ifelse(
                        finite_copy.is_retraction,
                        cell_volume(finite_copy.target_cell) > 1,
                        true,
                    ),
                ),
            ),
            Protocol(
                Sweep(; temperature = finite_temperature);
                name = :finite_protocol,
            ),
        )),
        parameters = [finite_weight, finite_temperature],
    )
    scheduled = mtkcompile(source)
    initial = PottsInitialState(
        ownership = LabelledCells(
            reshape(Int32[1, 0, 0], 3, 1);
            cells = [finite_cell],
            medium = finite_medium,
        ),
    )
    problem = PottsProblem(
        scheduled,
        initial,
        (0, 3);
        p = (
            finite_weight => log(2.0),
            finite_temperature => 1.0,
        ),
        seed = 0x3301,
    )
    first = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    replay = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    @test first.retcode == SciMLBase.ReturnCode.Success
    @test first.t == collect(0:3)
    @test getfield.(first.u, :ownership) == getfield.(replay.u, :ownership)
    @test all(state -> count(==(Int32(1)), state.ownership) in 1:2, first.u)
    @test first.stats.candidate_attempts == 9
    @test first.stats.candidate_attempts ==
          first.stats.accepted + first.stats.null_attempts +
          first.stats.constraint_rejections + first.stats.energy_rejections
end

@testset "scheduled chemotaxis follows the independent gradient sign" begin
    @variables chemotaxis_field chemotaxis_gate
    cell = CellKind(:chemotaxis_cell; extinction = RetireAtZero())
    medium = MediumKind(:chemotaxis_medium)
    field = FieldState(
        chemotaxis_field;
        name = :chemotaxis_field,
        initial = 0.0,
    )
    gate = FieldState(
        chemotaxis_gate;
        name = :chemotaxis_gate,
        initial = 0.0,
    )
    copy = ProposalContext(:chemotaxis_copy)
    source = PottsSystem(
        name = :chemotaxis_gradient_witness,
        statements = StatementSet((
            Lattice(
                (2, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            field,
            gate,
            Chemotaxis(
                cell,
                chemotaxis_field;
                strength = 2.0,
                mode = ExtensionsOnly(),
                sample = Nearest(),
            ),
            ProposalConstraint(
                :isolate_directed_chemotaxis_extension,
                copy.is_extension &
                (field_value(chemotaxis_gate, copy.source_site) == 1) &
                (field_value(chemotaxis_gate, copy.target_site) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [chemotaxis_field, chemotaxis_gate],
    )
    scheduled = mtkcompile(source)
    labels = reshape(Int32[1, 0], 2, 1)
    gate_values = reshape(Float64[1, 2], 2, 1)
    initial(target_concentration) = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            chemotaxis_field => reshape(
                Float64[1, target_concentration], 2, 1
            ),
            chemotaxis_gate => gate_values,
        ),
    )
    function run(target_concentration, seed)
        return solve(
            PottsProblem(
                scheduled, initial(target_concentration), (0, 1); seed
            ),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
    end

    witness = nothing
    for seed in UInt64(1):UInt64(512)
        # Independent law: -strength * (target - source) is -6 for the
        # increasing field and +2 for the decreasing field.
        favorable = run(4.0, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(0.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no directed chemotaxis witness found")
    @test all(==(Int32(1)), last(witness.favorable).ownership)
    @test witness.unfavorable.stats.accepted == 0
    @test last(witness.unfavorable).ownership == labels
end

@testset "scheduled elongation follows an independent shape-energy sign" begin
    @variables elongation_gate
    @parameters elongation_target = 3.0
    cell = CellKind(:elongation_cell; extinction = RetireAtZero())
    medium = MediumKind(:elongation_medium)
    gate = FieldState(
        elongation_gate; name = :elongation_gate, initial = 0.0
    )
    copy_context = ProposalContext(:elongation_copy)
    source = PottsSystem(
        name = :elongation_sign_witness,
        statements = StatementSet((
            Lattice(
                (4, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            gate,
            Elongation(cell; target = elongation_target, strength = 4.0),
            ProposalConstraint(
                :isolate_elongation_extension,
                copy_context.is_extension &
                (field_value(
                    elongation_gate, copy_context.source_site
                ) == 1) &
                (field_value(
                    elongation_gate, copy_context.target_site
                ) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [elongation_gate],
        parameters = [elongation_target],
    )
    scheduled = mtkcompile(source)
    labels = reshape(Int32[1, 1, 0, 0], 4, 1)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            elongation_gate => reshape(Float64[0, 1, 2, 0], 4, 1),
        ),
    )
    run(target, seed) = solve(
        PottsProblem(
            scheduled,
            initial,
            (0, 1);
            p = (elongation_target => target,),
            seed,
        ),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    witness = nothing
    for seed in UInt64(1):UInt64(256)
        favorable = run(3.0, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(1.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no directed elongation witness found")
    @test last(witness.favorable).ownership ==
          reshape(Int32[1, 1, 1, 0], 4, 1)
    @test last(witness.unfavorable).ownership == labels
end
