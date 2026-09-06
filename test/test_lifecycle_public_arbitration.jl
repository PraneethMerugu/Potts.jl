@testset "lifecycle permutation and conflict diagnostics are canonical" begin
    successful = map((false, true)) do reversed
        fixture = permutation_lifecycle_fixture(reversed)
        scheduled = mtkcompile(fixture.source)
        integrator = init(
            PottsProblem(
                scheduled, fixture.initial, (0, 1);
                seed = 0x51f6,
            ),
            SequentialCPM();
            scalar_type = Float32,
            save_everystep = true,
        )
        lifecycle_fingerprint = getfield(
            getfield(integrator, :plan), :reports
        ).lifecycle.fingerprint
        solution = solve!(integrator)
        (; lifecycle_fingerprint, solution)
    end
    @test successful[1].lifecycle_fingerprint ==
          successful[2].lifecycle_fingerprint
    @test last(successful[1].solution).ownership ==
          last(successful[2].solution).ownership
    @test last(successful[1].solution).cell_generations ==
          last(successful[2].solution).cell_generations

    conflicts = map((false, true)) do reversed
        fixture = permutation_lifecycle_fixture(reversed; conflicting = true)
        scheduled = mtkcompile(fixture.source)
        integrator = init(
            PottsProblem(
                scheduled, fixture.initial, (0, 1);
                seed = 0x51f7,
            ),
            SequentialCPM();
            scalar_type = Float32,
            save_start = false,
        )
        before = deepcopy(integrator.u)
        lifecycle_fingerprint = getfield(
            getfield(integrator, :plan), :reports
        ).lifecycle.fingerprint
        step!(integrator)
        (; lifecycle_fingerprint, integrator, before)
    end
    @test conflicts[1].lifecycle_fingerprint ==
          conflicts[2].lifecycle_fingerprint
    @test all(
        candidate -> candidate.integrator.retcode ==
                     SciMLBase.ReturnCode.Failure,
        conflicts,
    )
    first_report = conflicts[1].integrator.failure_report
    second_report = conflicts[2].integrator.failure_report
    @test first_report isa CorePotts.ProgramFailureReport
    @test second_report isa CorePotts.ProgramFailureReport
    @test (first_report.source, first_report.secondary_source,
           first_report.anchor, first_report.detail) ==
          (second_report.source, second_report.secondary_source,
           second_report.anchor, second_report.detail)
    for candidate in conflicts
        @test candidate.integrator.u.ownership == candidate.before.ownership
        @test candidate.integrator.u.cell_kinds == candidate.before.cell_kinds
        @test candidate.integrator.u.cell_generations ==
              candidate.before.cell_generations
    end
end
@testset "stable lifecycle priority selects the declared winner" begin
    @variables priority_state
    state = CellState(
        priority_state;
        initial = 0.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    births = cell -> (
        LifecycleProcess(
            :priority_low;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                state = (state => InitializeFrom(1.0),),
                priority = 1,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        ),
        LifecycleProcess(
            :priority_high;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                state = (state => InitializeFrom(10.0),),
                priority = 10,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        ),
    )
    fixture = lifecycle_birth_system(
        :public_priority_selection,
        births;
        max_cells = 2,
        conflicts = StableLifecyclePriority(),
        state,
        unknowns = [priority_state],
    )
    solution = solve(
        PottsProblem(
            mtkcompile(fixture.source), fixture.initial, (0, 1);
            seed = 0x51f8,
        ),
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test count(!iszero, last(solution).cell_kinds) == 1
    @test last(solution)[:priority_state][1] == 10
end
