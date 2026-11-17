@testitem "fields: the threaded host loop equals one thread and allocates nothing" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields, :subprocess] begin
    @testset "fields: the threaded host loop equals one thread and allocates nothing" begin
        @test 120 * 100 > Potts.CorePotts.Exec.HOST_GRAIN
        run(t) = split(
            strip(
                read(
                    `$(Base.julia_cmd()) --startup-file=no -t $t --project=$(Base.active_project()) -e $FD_THREADS_RUN`,
                    String
                )
            )
        )
        one, three = run(1), run(3)
        @test parse(Int, one[1]) == 1 && parse(Int, three[1]) == 3
        @test parse(Int, three[2]) == 0 && parse(Int, one[2]) == 0
        @test three[3] == one[3]
    end
end

@testitem "@schedule repeat: n passes of 1/n sweeps" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "@schedule repeat: n passes of 1/n sweeps" begin
        sys = FdChemoInter(; name = :i)
        @test Potts._p(sys, :schedule) == Any[Potts.ScheduleRepeat(4, [:sweep, :fields])]
        @test occursin("repeat(4, sweep(fraction = 1//4), fields)", sprint(show, MIME"text/plain"(), sys))
        for alg in (SequentialCPM(), CheckerboardCPM())
            run(M) = solve(PottsProblem(M(; name = :m), fd_chemo_op(), (0, 3); field_solver = ExplicitEuler(substeps = 2)), alg)
            plain, split, inter = run(FdChemoPlain), run(FdChemoSplit), run(FdChemoInter)
            # oracle: with nothing between the passes the copies are exactly one sweep's
            @test split.u[end].σ == plain.u[end].σ && split.u[end].site.c == plain.u[end].site.c
            @test split.stats.attempts == plain.stats.attempts
            # control: the field stepped between the passes changes the copies
            @test inter.u[end].σ != plain.u[end].σ
        end
        p = PottsProblem(FdChemoSplit(; name = :m), fd_chemo_op(), (0, 1); field_solver = ExplicitEuler(substeps = 2))
        @test any(e -> e isa CorePotts.Repeat && e.n == 4, p.f.phases.mcs)
        @test p.f.fingerprint != PottsProblem(
            FdChemoPlain(; name = :m), fd_chemo_op(), (0, 1);
            field_solver = ExplicitEuler(substeps = 2)
        ).f.fingerprint
        # a sweep that cannot split is refused at `init`
        @test occursin("skip_interior", something(fd_err(() -> init(p, SequentialCPM(; skip_interior = true))), ""))
    end
end

@testitem "CheckerboardCPM Repeat split == plain parity with moment tracking (anchor) and deferring Global veto" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "CheckerboardCPM Repeat split == plain parity with moment tracking (anchor) and deferring Global veto" begin
        σ = zeros(Int32, 24, 24)
        σ[5:12, 5:12] .= 1
        σ[14:20, 6:14] .= 2
        op = [ownership => σ, kind => [:A, :A]]
        p_plain = PottsProblem(MomentVetoPlain(; name = :mv), op, (0, 12); seed = 4)
        p_split = PottsProblem(MomentVetoSplit(; name = :mv), op, (0, 12); seed = 4)
        @test hasproperty(p_plain.u0.cell, :anchor)
        @test hasproperty(p_split.u0.cell, :anchor)
        sol_plain = solve(p_plain, CheckerboardCPM())
        sol_split = solve(p_split, CheckerboardCPM())
        @test sol_plain.stats.connectivity_deferred > 0
        @test sol_split.stats.connectivity_deferred == sol_plain.stats.connectivity_deferred
        @test sol_split.stats.attempts == sol_plain.stats.attempts
        @test sol_split.u[end].σ == sol_plain.u[end].σ
        @test sol_split.u[end].cell.anchor == sol_plain.u[end].cell.anchor
        @test sol_split.u[end].cell.x0 == sol_plain.u[end].cell.x0
    end
end

# TS1c: `init` compiles the handler of each MCS entry before `step!` (the 2-argument
# `_run_entry!`); a `Repeat` calls the 3-argument one, `(integ, e, (j, n))`, once per pass,
# which must not box its entry: a warm MCS allocates nothing on either algorithm
@testitem "@schedule repeat: a warm MCS allocates nothing" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "@schedule repeat: a warm MCS allocates nothing" begin
        for M in (FdChemoSplit, FdChemoInter), alg in (CheckerboardCPM(), SequentialCPM())
            integ = init(
                PottsProblem(M(; name = :m), fd_chemo_op(), (0, 10); field_solver = ExplicitEuler(substeps = 2)),
                alg; save_start = false, save_end = false, save_everystep = false
            )
            step!(integ)
            step!(integ)
            @test (@allocated step!(integ)) == 0
        end
    end
end

@testitem "@schedule repeat: fields inside step 1/n of the MCS per pass (hand oracle)" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "@schedule repeat: fields inside step 1/n of the MCS per pass (hand oracle)" begin
        op = fd_source_op((12, 10))
        prob = PottsProblem(FdSourceInter(; name = :f), op, (0, 2); field_solver = ExplicitEuler(substeps = 2))
        integ = init(prob, SequentialCPM())
        @test fd_n(integ) == 2
        sol = solve(prob, SequentialCPM())
        src = op[1].second .== 1
        hand = zeros(12, 10)
        for _ in 1:(2 * 4)
            hand = fd_ftcs(hand, 0.2, (1, 1), 0.25, 2; periodic = false, rate = (c, i, j) -> 0.05 * src[i, j])
        end
        @test maximum(abs.(sol.u[end].site.c .- hand)) < 1.0e-15
        whole = solve(PottsProblem(FdSource(; name = :f), op, (0, 2); field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        @test maximum(abs.(whole.u[end].site.c .- hand)) > 1.0e-6                          # control: one step of the MCS
    end
end

@testitem "@schedule repeat: errors name the offender" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "@schedule repeat: errors name the offender" begin
        bad(ex) = fd_err(() -> Potts.schedule_repeat(ex))
        @test occursin("sweep(fraction = 1//4)", something(bad(:(repeat(4, sweep(fraction = 1 // 2), fields))), ""))
        @test occursin("sweep(fraction = 1//4)", something(bad(:(repeat(4, sweep, fields))), ""))
        @test occursin("cannot be repeated", something(bad(:(repeat(4, sweep(fraction = 1 // 4), components))), ""))
        @test occursin("holds the sweep", something(bad(:(repeat(4, fields))), ""))
        @test occursin("count n ≥ 2", something(bad(:(repeat(1, sweep(fraction = 1 // 1)))), ""))
        @test bad(:(repeat(4, sweep(; fraction = 1 // 4), fields, after_mcs))) === nothing
    end
end

@testitem "fields: the field state is never lost (checkpoints, reinit!, remake, copies, ensembles)" setup = [FieldsSetup, FieldsScheduleSetup] tags = [:potts, :fields] begin
    @testset "fields: the field state is never lost (checkpoints, reinit!, remake, copies, ensembles)" begin
        for (M, alg) in ((FdChemo, SequentialCPM()), (FdChemo, CheckerboardCPM()), (FdChemoInter, SequentialCPM()))
            prob = PottsProblem(M(; name = :c), fd_chemo_op(), (0, 6); field_solver = ExplicitEuler())
            whole = solve(prob, alg).u[end]
            same(u) = Array(u.σ) == Array(whole.σ) && Array(u.site.c) == Array(whole.site.c)
            # a checkpoint taken mid-run, written, read back and continued: the uninterrupted run
            a = init(prob, alg); foreach(_ -> step!(a), 1:3)
            path = tempname()
            save_checkpoint(path, checkpoint(a))
            @test same(solve!(init(prob, alg; checkpoint = load_checkpoint(path))).u[end])
            # the original integrator continues unchanged by the checkpoint
            @test same(solve!(a).u[end])
            # a state written into another integrator (`reinit!` at MCS 3), then continued
            b = init(prob, alg); foreach(_ -> step!(b), 1:3)
            s3 = deepcopy(current_state(b))
            c = init(prob, alg); step!(c)
            reinit!(c, s3; t0 = 3)
            @test same(solve!(c).u[end])
            # `remake` from the MCS-3 state (fields included)
            @test same(solve(remake(prob; u0 = s3, tspan = (3, 6)), alg).u[end])
            # a copy of a running integrator steps on its own copy of the fields
            d = init(prob, alg); foreach(_ -> step!(d), 1:3)
            e = deepcopy(d)
            step!(e)
            @test Array(current_state(d).site.c) == Array(s3.site.c)                   # d untouched
            @test same(solve!(e).u[end]) && same(solve!(d).u[end])
            # negative control: a run missing its field state differs
            z = deepcopy(s3); z.site.c .= 0
            @test !same(solve(remake(prob; u0 = z, tspan = (3, 6)), alg).u[end])
        end
        # ensembles: each trajectory carries its own field, equal to its single run
        prob = PottsProblem(FdChemo(; name = :c), fd_chemo_op(), (0, 4); field_solver = ExplicitEuler())
        sim = solve(EnsembleProblem(prob), SequentialCPM(); trajectories = 3)
        for i in 1:3
            one = solve(remake(prob; replica = prob.replica + UInt32(i)), SequentialCPM()).u[end]
            @test sim.u[i].u[end].σ == one.σ && sim.u[i].u[end].site.c == one.site.c
        end
        @test sim.u[1].u[end].site.c != sim.u[2].u[end].site.c                         # independent trajectories
    end
end
