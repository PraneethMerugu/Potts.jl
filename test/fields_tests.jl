# Fields after the field-compiler cutover (C8): a model's field (a coupled PDESystem) is lowered
# by the field compiler (LatticePDE → LatticeFields) and stepped by explicit Euler over each MCS.
# Oracles: the discrete Fourier factor of FTCS, mass conservation, a hand FTCS stepper; each
# with a negative control (D-048).

@testitem "fields: the Fourier factor of FTCS, with spacing (periodic)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: the Fourier factor of FTCS, with spacing (periodic)" begin
        dims, h = (16, 8), (2.0, 2.0)
        c0 = [cos(2π * (i - 1) / 16) for i in 1:16, j in 1:8]
        for (Dc, nexp) in ((1.0, 2), (4.0, 5))           # ρ = Dc·Σ 4/h² = 2Dc: n = ceil(2Dc/1.8)
            prob = PottsProblem(FdPeriodic(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc], (0, 1);
                field_solver = ExplicitEuler())
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == nexp
            step!(integ)
            c = Array(current_state(integ).site.c)
            g = 1 - (1 / nexp) * Dc * (4 / h[1]^2) * sin(π / 16)^2      # the per-substep factor of mode 1
            @test maximum(abs.(c .- g^nexp .* c0)) < 1e-13
            @test maximum(abs.(c .- (1 - (1 / (nexp + 1)) * Dc * sin(π / 16)^2)^(nexp + 1) .* c0)) > 1e-6   # control: n + 1
        end
    end
end

@testitem "fields: auto substep counts, odd and even counts, the hand stepper" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: auto substep counts, odd and even counts, the hand stepper" begin
        dims = (12, 10)
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        # ρ = Dc·8 + k: 5 at Dc = 1; 2 at Dc = 0.45; 3 with a reaction of 0.2
        for (Dc, k, nexp) in ((1.0, 0.0, 5), (0.45, 0.0, 2), (0.45, 0.2, 3))
            prob = PottsProblem(FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc; :k => k], (0, 2);
                field_solver = ExplicitEuler())
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == nexp
            step!(integ); step!(integ)
            hand = fd_ftcs(fd_ftcs(c0, Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j]),
                Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j])
            @test maximum(abs.(Array(current_state(integ).site.c) .- hand)) < 1e-14
        end
        # an explicit count is a minimum: 3 (odd: the scratch is copied back) and 4 (even)
        for n in (3, 4)
            prob = PottsProblem(FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => 0.1], (0, 1);
                field_solver = ExplicitEuler(substeps = n))
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == n
            step!(integ)
            c = Array(current_state(integ).site.c)
            @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n; periodic = false))) < 1e-15
            @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n + 1; periodic = false))) > 1e-8   # control
        end
    end
end

@testitem "fields: mass conservation (periodic and closed), a sink as control" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: mass conservation (periodic and closed), a sink as control" begin
        c0 = [1.0 + sin(i) * cos(2j) for i in 1:16, j in 1:8]
        sol = solve(PottsProblem(FdPeriodic(; name = :f), [fd_empty((16, 8)); :c => c0], (0, 5);
            field_solver = ExplicitEuler()), SequentialCPM())
        @test abs(sum(sol.u[end].site.c) - sum(c0)) < 1e-11 * sum(c0)
        @test maximum(abs.(sol.u[end].site.c .- c0)) > 1e-3                              # the field moved
        c1 = [1.0 + sin(i) * cos(2j) for i in 1:12, j in 1:10]
        closed(k) = solve(PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c1; :k => k], (0, 5);
            field_solver = ExplicitEuler()), SequentialCPM()).u[end].site.c
        @test abs(sum(closed(0.0)) - sum(c1)) < 1e-11 * sum(c1)
        @test sum(closed(0.05)) < 0.9 * sum(c1)                                          # control: a sink
    end
end

@testitem "fields: CPM terms are filled inputs (a frozen source, hand oracle)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: CPM terms are filled inputs (a frozen source, hand oracle)" begin
        op = fd_source_op((12, 10))
        prob = PottsProblem(FdSource(; name = :f), op, (0, 3); field_solver = ExplicitEuler(substeps = 2))
        sol = solve(prob, SequentialCPM())
        src = op[1].second .== 1
        hand = zeros(12, 10)
        for _ in 1:3
            hand = fd_ftcs(hand, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (c, i, j) -> 0.05 * src[i, j])
        end
        @test maximum(abs.(sol.u[end].site.c .- hand)) < 1e-15
        @test maximum(abs.(sol.u[end].site.c .- 2 .* hand)) > 1e-3                      # control
        # the filled input is a site array of the state
        @test any(k -> endswith(string(k), "__in"), keys(prob.u0.site))
    end
end

@testitem "fields: two solver groups; a later group reads the earlier field's array" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: two solver groups; a later group reads the earlier field's array" begin
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        cvar = only(filter(x -> string(x) in ("c", "c(t)"), Potts.variables(sys)))
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.variables(sys)))
        prob = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [uvar => ExplicitEuler(substeps = 3)])
        @test count(x -> x isa CorePotts.FieldPhase, prob.f.phases.after_mcs) == 2
        sol = solve(prob, SequentialCPM())
        src = op[1].second .== 1
        c, u = zeros(12, 10), zeros(12, 10)
        for _ in 1:2
            c = fd_ftcs(c, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (q, i, j) -> 0.05 * src[i, j])
            cc = c
            u = fd_ftcs(u, 0.1, (1, 1), 1.0, 3; periodic = false, rate = (q, i, j) -> 0.5 * cc[i, j])
        end
        @test maximum(abs.(sol.u[end].site.c .- c)) < 1e-15
        @test maximum(abs.(sol.u[end].site.u .- u)) < 1e-14
        # one group (both fields with the same solver): Jacobi inside the substep, a different result
        one = solve(PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM())
        @test count(x -> x isa CorePotts.FieldPhase, PottsProblem(sys, op, (0, 2);
            field_solver = ExplicitEuler(substeps = 3)).f.phases.after_mcs) == 1
        @test maximum(abs.(one.u[end].site.u .- u)) > 1e-6
    end
end

@testitem "fields: the coupling between solver groups is bounded (F2-06 review, K-unsafe)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: the coupling between solver groups is bounded (F2-06 review, K-unsafe)" begin
        sys = FdRot(; name = :r)
        ovar = only(filter(x -> string(x) in ("o", "o(t)"), Potts.variables(sys)))
        two(k; n = 1) = PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 4); field_solver = ExplicitEuler(substeps = n),
            solvers = [ovar => ExplicitEuler(substeps = 2)])
        # k · window = 3 in two groups: refused, explicit counts or not (base: built and run)
        for n in (1, 40)
            e = try
                two(3.0; n); ""
            catch err
                err isa ArgumentError || rethrow()
                sprint(showerror, err)
            end
            @test occursin("window · Σ max|coefficient| = 3.0 > 1", e) && occursin("one solver", e) && occursin("`o`", e) &&
                  occursin("(1.0 MCS)", e)
        end
        # weak coupling (k = 0.5, read through the parameter): the groups step one after the other
        sol = solve(two(0.5), SequentialCPM())
        c, o = 1.0, 0.0
        for _ in 1:4
            c = c - 0.5 * o                                           # the c group: o held over the MCS
            for _ in 1:2
                o = o + 0.5 * c / 2                                   # the o group (2 substeps) reads the new c
            end
        end
        @test all(≈(c; rtol = 1e-12), sol.u[end].site.c) && all(≈(o; rtol = 1e-12), sol.u[end].site.o)
        @test abs(c - cos(2.0)) < 0.5 && abs(o - sin(2.0)) < 0.5      # the splitting's truncation at k dt = 0.5
        # `FieldGroups` as A's `field_solver` (F3-03): the same two groups as the `solvers` spelling
        fg = FieldGroups(ovar => ExplicitEuler(substeps = 2); default = ExplicitEuler(substeps = 1))
        sg = solve(PottsProblem(sys, [fd_empty((6, 6)); :k => 0.5], (0, 4); field_solver = fg), SequentialCPM())
        @test sg.u[end].site.c == sol.u[end].site.c && sg.u[end].site.o == sol.u[end].site.o
    end
end

@testitem "fields: a one-way chain of solver groups is not limited (F2-06 round 2)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a one-way chain of solver groups is not limited (F2-06 round 2)" begin
        sys = FdOneWay(; name = :w)
        # the values at 2c91f854, before the coupling check (u at k = 3 and 30)
        base = Dict(3.0 => 0.4039093699527255, 30.0 => 4.039093699527256)
        for k in (3.0, 30.0)                                          # window · k = 3 and 30
            sol = solve(PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 20); field_solver = ExplicitEuler(substeps = 2),
                solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3)]), SequentialCPM())
            @test Symbol(sol.retcode) === :Success
            c, u = 1.0, 0.0
            for _ in 1:20
                for _ in 1:2; c -= 0.5 * 0.1 * c; end                 # the c group (2 substeps)
                for _ in 1:3; u += (k * c - u) / 3; end               # the u group reads the new c (3 substeps)
            end
            @test all(≈(c; rtol = 1e-12), sol.u[end].site.c) && all(≈(u; rtol = 1e-12), sol.u[end].site.u)
            @test sol.u[end].site.u[1] ≈ base[k] rtol = 1e-12
            @test sol.u[end].site.c[1] ≈ 0.12851215656510334 rtol = 1e-12
        end
    end
end

@testitem "fields: loops of solver groups are limited, chains next to them are not (F2-06 round 2)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: loops of solver groups are limited, chains next to them are not (F2-06 round 2)" begin
        s3 = FdLoop3(; name = :l3)
        three(k) = PottsProblem(s3, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(s3, "o") => ExplicitEuler(substeps = 2), fdvar(s3, "v") => ExplicitEuler(substeps = 3)])
        e = fdargerr(() -> three(3.0))
        @test occursin("the fields `c`, `o`, `v` are in solver groups that read one another in a loop", e) &&
              occursin("window · Σ max|coefficient| = 3.0 > 1", e)
        @test Symbol(solve(three(0.5), SequentialCPM()).retcode) === :Success
        sc = FdLoopChain(; name = :lc)
        lc(; k, r) = PottsProblem(sc, [fd_empty((6, 6)); :k => k; :r => r], (0, 2); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sc, "o") => ExplicitEuler(substeps = 2), fdvar(sc, "u") => ExplicitEuler(substeps = 3)])
        # u's window · k = 30 (u is in no loop), the loop's 0.5: accepted
        @test Symbol(solve(lc(; k = 30.0, r = 0.5), SequentialCPM()).retcode) === :Success
        # the loop past the limit: refused, naming the loop's fields only
        e = fdargerr(() -> lc(; k = 30.0, r = 3.0))
        @test occursin("the fields `c`, `o` are in solver groups", e) && !occursin("`u`", e)
    end
end

@testitem "fields: an unseen term that reads another field counts as reading every group (F2-06 round 3)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an unseen term that reads another field counts as reading every group (F2-06 round 3)" begin
        sys = FdUnseenChain(; name = :uc)
        three(k) = PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3), fdvar(sys, "z") => ExplicitEuler(substeps = 1)])
        e = fdargerr(() -> three(3.0))
        @test occursin("the fields `c`, `u` are in solver groups that read one another in a loop", e) &&
              occursin("window · Σ max|coefficient| = 3.0", e) &&
              occursin("the terms of `c` that the stability bound cannot see and that read another field count as reading every other group", e)
        @test Symbol(solve(three(0.5), SequentialCPM()).retcode) === :Success
    end
end

@testitem "fields: an unseen term on its own field couples no group (F2-06 round 3)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an unseen term on its own field couples no group (F2-06 round 3)" begin
        sys = FdSelfSrc(; name = :ss)
        sol = solve(PottsProblem(sys, fd_empty((6, 6)), (0, 10); field_solver = ExplicitEuler(substeps = 2),
            solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3)]), SequentialCPM())
        @test Symbol(sol.retcode) === :Success
        @test sol.u[end].site.u[1] ≈ 1.5079357331026704 rtol = 1e-12          # the value at 2c91f854
    end
end

@testitem "fields: a loop of solver groups counts only the reads inside it (F2-06 round 3)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a loop of solver groups counts only the reads inside it (F2-06 round 3)" begin
        sys = FdChainLoop(; name = :cl)
        cl(w) = PottsProblem(sys, [fd_empty((6, 6)); :w => w], (0, 10); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sys, "s2") => ExplicitEuler(substeps = 2), fdvar(sys, "c") => ExplicitEuler(substeps = 3)])
        sol = solve(cl(0.05), SequentialCPM())                        # s1 → weak loop (0.05): accepted
        @test Symbol(sol.retcode) === :Success
        @test sol.u[end].site.s2[1] ≈ 16.438457412956836 rtol = 1e-12 # the values at 2c91f854
        @test sol.u[end].site.c[1] ≈ 5.8773343382071435 rtol = 1e-12
        e = fdargerr(() -> cl(3.0))                                   # a strong loop: refused, s1 not named
        @test occursin("the fields `s2`, `c` are in solver groups", e) && occursin("window · Σ max|coefficient| = 3.0 >", e) &&
              !occursin("s1", e)
    end
end

@testitem "fields: following the printed window limit is accepted (F2-06 round 2)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: following the printed window limit is accepted (F2-06 round 2)" begin
        sys = FdRot(; name = :r)
        for k in (150.0, 1 / 0.0033335, 300.0, 7.0e3 / 3, 1234.5)
            e = fdargerr(() -> PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 1); field_solver = ExplicitEuler(substeps = 1),
                solvers = [fdvar(sys, "o") => ExplicitEuler(substeps = 2)]))
            @test occursin("> 1", e)
            # the window limit, verbatim (rounded down)
            lim = parse(Float64, match(r"window ≤ ([0-9.eE+-]+)\)", e).captures[1])
            @test lim * k <= 1
            sm = fd_rot_md(lim)
            prob = PottsProblem(sm, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 1),
                solvers = [fdvar(sm, "o") => ExplicitEuler(substeps = 2)])
            @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
            # route 1: one solver with an explicit count (the rotation's rows are not dominant)
            @test occursin("one solver with an explicit count", e)
            @test PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 1); field_solver = ExplicitEuler(substeps = 4000)) isa
                  PottsProblem
        end
    end
end

@testitem "fields: lower clip, also at init" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: lower clip, also at init" begin
        op = fd_empty((6, 6))
        clip = solve(PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1, lower = 0.0)),
            SequentialCPM()).u[end].site.c
        free = solve(PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM()).u[end].site.c
        @test all(==(0.0), clip)
        @test all(≈(-1.0), free)                                                          # control
    end
end

@testitem "fields: masked conditions, the at-init clamp on fresh states only" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: masked conditions, the at-init clamp on fresh states only" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        op = [ownership => σ, kind => [:wall]]
        wall = σ .== 1
        prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
        integ = init(prob, SequentialCPM())
        @test all(==(3.0), Array(current_state(integ).site.c)[wall])                      # clamped at init
        @test all(==(0.0), Array(current_state(integ).site.c)[.!wall])
        foreach(_ -> step!(integ), 1:2)
        u = current_state(integ)
        @test all(==(3.0), Array(u.site.c)[wall]) && sum(u.site.c[.!wall]) > 0
        # a restored state is not fresh: the clamp does not run at init
        ck = checkpoint(integ)
        ck.state.site.c[wall] .= 5.0
        again = init(prob, SequentialCPM(); checkpoint = ck)
        @test all(==(5.0), Array(current_state(again).site.c)[wall])
        step!(again)
        @test all(==(3.0), Array(current_state(again).site.c)[wall])                      # the mask of the next MCS
        # checkpoint continuation is exact
        whole = solve(prob, SequentialCPM()).u[end]
        integ = init(prob, SequentialCPM()); foreach(_ -> step!(integ), 1:2)
        rest = solve!(init(prob, SequentialCPM(); checkpoint = checkpoint(integ))).u[end]
        @test rest.σ == whole.σ && rest.site.c == whole.site.c
        # a new value through `remake` rebinds the mask value
        @test all(==(7.0), solve(remake(prob; p = [:v => 7.0]), SequentialCPM()).u[end].site.c[wall])
    end
end

@testitem "fields: a parameter change rebinds the substep count and the rates" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a parameter change rebinds the substep count and the rates" begin
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        prob = PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 1); field_solver = ExplicitEuler())
        a = init(prob, SequentialCPM())
        b = init(remake(prob; p = [:Dc => 0.45]), SequentialCPM())
        @test fd_n(a) == 5 && fd_n(b) == 2
        step!(b)
        @test maximum(abs.(Array(current_state(b).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1e-15
        # in a running integrator: new parameter values are rebound at the next field phase
        a.p = remake(prob; p = [:Dc => 0.45]).p
        step!(a)
        @test fd_n(a) == 2
        @test maximum(abs.(Array(current_state(a).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1e-15
    end
end

@testitem "fields: setp, then reinit!, keeps the step's substeps (masked model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: setp, then reinit!, keeps the step's substeps (masked model)" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        op = [ownership => σ, kind => [:wall]]
        prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
        fresh = init(remake(prob; p = [:v => 7.0]), SequentialCPM()); foreach(_ -> step!(fresh), 1:3)
        integ = init(prob, SequentialCPM()); step!(integ)
        setp(integ, :v)(integ, 7.0)                          # a parameter change, then a new start
        reinit!(integ, prob.u0)                              # the at-init clamp runs with the new parameters
        @test fd_n(integ) == 2                               # the step's count, not the clamp's one substep
        foreach(_ -> step!(integ), 1:3)
        u, w = current_state(integ), current_state(fresh)
        @test Array(u.σ) == Array(w.σ) && Array(u.site.c) == Array(w.site.c)
        @test sum(u.site.c[σ .== 0]) > 0                     # control: the field evolves
    end
end

@testitem "fields: only the field's own parameters and tables (by value) rebind its launches" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: only the field's own parameters and tables (by value) rebind its launches" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        prob = PottsProblem(FdMask(; name = :m), [ownership => σ, kind => [:wall]], (0, 4); field_solver = ExplicitEuler(substeps = 2))
        integ = init(prob, SequentialCPM()); step!(integ)
        rt = CorePotts._runtime(integ.ctx.__fields1)
        even = rt.steps[1]
        setp(integ, :v)(integ, 3.0)                          # a new parameter object, equal values
        step!(integ)
        @test rt.steps[1] === even && rt.host.p === integ.p           # kept: nothing the field reads changed
        setp(integ, :v)(integ, 4.0)
        step!(integ)
        @test rt.steps[1] !== even                               # control: the mask value changed, rebound
        @test all(==(4.0), Array(current_state(integ).site.c)[σ .== 1])
        # a kind table: an equal table keeps the launches, a new one rebinds and is read
        tp = PottsProblem(FdTab(; name = :t), [ownership => σ, kind => [:A]], (0, 2); field_solver = ExplicitEuler(substeps = 1))
        a = init(tp, SequentialCPM()); step!(a)
        rt = CorePotts._runtime(a.ctx.__fields1); even = rt.steps[1]
        setp(a, :δ)(a, [0.5, 0.0])
        step!(a)
        @test rt.steps[1] === even
        s1 = deepcopy(current_state(a))
        setp(a, :δ)(a, [2.0, 0.0])
        step!(a)
        @test rt.steps[1] !== even
        b = init(remake(tp; u0 = s1, tspan = (2, 3), p = [:δ => [2.0, 0.0]]), SequentialCPM()); step!(b)
        @test Array(current_state(a).site.c) == Array(current_state(b).site.c)
        @test Array(current_state(a).site.c) != Array(s1.site.c)              # control
    end
end

@testitem "fields: an ifelse gate is bounded through its arms" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an ifelse gate is bounded through its arms" begin
        op = [fd_empty((12, 10)); :c => fd_rand((12, 10))]
        auto = PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler())
        @test fd_n(init(auto, SequentialCPM())) == 5                         # ceil(1.0·8 / 1.8)
        one = @test_logs PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler(substeps = 1))
        integ = init(one, SequentialCPM())
        @test fd_n(integ) == 5                                               # the request 1 is a minimum
        setp(integ, :Dc)(integ, 2.0)
        step!(integ)
        @test fd_n(integ) == 9                                               # ceil(2.0·8 / 1.8)
        @test all(isfinite, Array(current_state(integ).site.c))
    end
end

@testitem "fields: the threaded host loop equals one thread and allocates nothing" setup = [FieldsSetup] tags = [:potts, :fields, :subprocess] begin
    @testset "fields: the threaded host loop equals one thread and allocates nothing" begin
        @test 120 * 100 > Potts.CorePotts.Exec.HOST_GRAIN
        run(t) = split(strip(read(`$(Base.julia_cmd()) --startup-file=no -t $t --project=$(Base.active_project()) -e $FD_THREADS_RUN`,
            String)))
        one, three = run(1), run(3)
        @test parse(Int, one[1]) == 1 && parse(Int, three[1]) == 3
        @test parse(Int, three[2]) == 0 && parse(Int, one[2]) == 0
        @test three[3] == one[3]
    end
end

@testitem "fields: hexagonal lattices (the old path's six-point Laplacian)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: hexagonal lattices (the old path's six-point Laplacian)" begin
        for boundary in (Periodic(), Closed())
            prob = PottsProblem(FdHex(; name = :h, boundary), [fd_empty((8, 6)); :c => fd_rand((8, 6))], (0, 3);
                field_solver = ExplicitEuler(substeps = 3))
            u = fd_mcs(prob, 3)
            c = prob.u0.site.c
            for m in 1:3
                c = fd_oldpath(c, prob.lattice, 0.1, 3)
                @test maximum(abs.(u[m] .- c)) < 1e-14
            end
            @test sum(u[end]) ≈ sum(prob.u0.site.c)                                 # zero-sum stencil
            # negative control: the square 4-point stencil is a different field
            sq = fd_ftcs(prob.u0.site.c, 0.1, (1, 1), 1.0, 3; periodic = boundary isa Periodic)
            @test maximum(abs.(u[1] .- sq)) > 1e-3
        end
        # the stencil is exact for a quadratic: Δ|x|² = 4 (Euclidean positions of the axial sites)
        L = (24, 24)
        hl = CorePotts.Lattice(L; geometry = CorePotts.Hexagonal(), boundary = Closed())
        pos(x) = CorePotts.embed(hl, Float64.(Tuple(x)))
        f = [sum(abs2, pos(x)) for x in CartesianIndices(L)]
        prob = PottsProblem(FdHex(; name = :h, boundary = Closed(), dims = L), [fd_empty(L); :c => f], (0, 1);
            field_solver = ExplicitEuler(substeps = 1))
        c1 = solve(prob, SequentialCPM(); save_start = false).u[1].site.c
        @test (c1[10, 12] - f[10, 12]) / 0.1 ≈ 4.0
        # the program reads the six axial neighbors, and only those (the IR's hexagonal offsets)
        prog = first(ph for t in prob.f.phases.mcs if t isa Tuple for ph in t if ph isa CorePotts.FieldPhase).program
        offs = Set(Tuple(Int.(a.offset.a)) for k in prog.kernels for a in k.accesses if any(!iszero, a.offset.a))
        @test offs == Set(FD_HEX6)
    end
end

@testitem "fields: an irregular domain (zero flux at its edge, as the old path)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an irregular domain (zero flux at its edge, as the old path)" begin
        prob0 = PottsProblem(FdDomain(; name = :d), fd_empty((40, 40)), (0, 1); field_solver = ExplicitEuler(substeps = 2))
        lat = prob0.lattice
        inmask = [CorePotts.in_domain(lat, i) for i in 1:(40 * 40)]
        c0 = zeros(40, 40); c0[18:23, 18:23] .= 1.0; c0[1, 1] = 7.0                 # (1, 1) is outside
        prob = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => c0], (0, 200); field_solver = ExplicitEuler(substeps = 2))
        u = solve(prob, SequentialCPM(); save_start = false).u
        @test sum(u[end].site.c[inmask]) ≈ 36.0                                   # conserved inside
        @test u[end].site.c[1, 1] == 7.0                                          # outside: no exchange
        @test maximum(u[end].site.c[inmask]) - minimum(u[end].site.c[inmask]) < 0.05  # equilibrates inside
        # the old path's numerics, MCS by MCS, on a random field (outside sites too)
        r = fd_rand((40, 40))
        pr = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => r], (0, 3); field_solver = ExplicitEuler(substeps = 2))
        ur = fd_mcs(pr, 3)
        c = r
        for m in 1:3
            c = fd_oldpath(c, lat, 0.2, 2)
            @test maximum(abs.(ur[m] .- c)) < 1e-14
        end
        # negative control: the full box exchanges across the disk's edge
        full = PottsProblem(FdDomain(; name = :f, domain = x -> true), [fd_empty((40, 40)); :c => r], (0, 1);
            field_solver = ExplicitEuler(substeps = 2))
        @test maximum(abs.(fd_mcs(full, 1)[1] .- ur[1])) > 1e-3
        # faces against the domain edge: the face value applies at the box face, not at the edge
        st = PottsProblem(FdStripe(; name = :s), fd_empty((9, 9)), (0, 1); field_solver = ExplicitEuler(substeps = 1))
        us = solve(st, SequentialCPM(); save_start = false).u[1].site.c
        @test us == fd_oldpath(zeros(9, 9), st.lattice, 0.1, 1; bc = ((0.0, 100.0), (nothing, nothing)))
        @test all(iszero, us)                                                     # x = 7 is the edge: zero flux
        # control: on the full box the same face drives the edge site
        @test fd_oldpath(zeros(9, 9), Potts.CorePotts.Lattice((9, 9); boundary = Closed()), 0.1, 1;
            bc = ((0.0, 100.0), (nothing, nothing)))[9, 5] ≈ 0.1 * 200.0
    end
end

@testitem "fields: refusals name the reason" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: refusals name the reason" begin
        @test occursin("rand()", something(fd_err(() -> PottsProblem(FdRand(; name = :r), fd_empty((8, 6)), (0, 1);
            field_solver = ExplicitEuler(substeps = 1))), ""))
        @test occursin("field solver", something(fd_err(() -> PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
            field_solver = RK4())), ""))
    end
end

@testitem "fields: a warm MCS allocates nothing on the CPU" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a warm MCS allocates nothing on the CPU" begin
        op = fd_source_op((12, 10))
        integ = init(PottsProblem(FdSource(; name = :f), op, (0, 100); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM();
            save_start = false, save_end = false)
        step!(integ)
        @test (@allocated step!(integ)) == 0
    end
end

@testitem "parameters: a value that does not convert is named, with a role-neutral reason" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "parameters: a value that does not convert is named, with a role-neutral reason" begin
        err = fd_err(() -> PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :Dc => FdNotANumber()], (0, 1);
            field_solver = ExplicitEuler()))
        @test occursin("`Dc`", something(err, "")) && occursin("scalar type", something(err, ""))
        @test occursin("A Dual goes to the problem", something(err, ""))     # (the route since F3-21b)
        @test !occursin("CPM parameters are plain numbers", something(err, ""))
    end
end

@testitem "@schedule repeat: n passes of 1/n sweeps" setup = [FieldsSetup] tags = [:potts, :fields] begin
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
        @test p.f.fingerprint != PottsProblem(FdChemoPlain(; name = :m), fd_chemo_op(), (0, 1);
            field_solver = ExplicitEuler(substeps = 2)).f.fingerprint
        # a sweep that cannot split is refused at `init`
        @test occursin("skip_interior", something(fd_err(() -> init(p, SequentialCPM(; skip_interior = true))), ""))
    end
end

# TS1c: `init` compiles the handler of each MCS entry before `step!` (the 2-argument
# `_run_entry!`); a `Repeat` calls the 3-argument one, `(integ, e, (j, n))`, once per pass,
# which must not box its entry: a warm MCS allocates nothing on either algorithm
@testitem "@schedule repeat: a warm MCS allocates nothing" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "@schedule repeat: a warm MCS allocates nothing" begin
        for M in (FdChemoSplit, FdChemoInter), alg in (CheckerboardCPM(), SequentialCPM())
            integ = init(PottsProblem(M(; name = :m), fd_chemo_op(), (0, 10); field_solver = ExplicitEuler(substeps = 2)),
                alg; save_start = false, save_end = false)
            step!(integ)
            step!(integ)
            @test (@allocated step!(integ)) == 0
        end
    end
end

@testitem "@schedule repeat: fields inside step 1/n of the MCS per pass (hand oracle)" setup = [FieldsSetup] tags = [:potts, :fields] begin
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
        @test maximum(abs.(sol.u[end].site.c .- hand)) < 1e-15
        whole = solve(PottsProblem(FdSource(; name = :f), op, (0, 2); field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        @test maximum(abs.(whole.u[end].site.c .- hand)) > 1e-6                          # control: one step of the MCS
    end
end

@testitem "@schedule repeat: errors name the offender" setup = [FieldsSetup] tags = [:potts, :fields] begin
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

@testitem "fields: the field state is never lost (checkpoints, reinit!, remake, copies, ensembles)" setup = [FieldsSetup] tags = [:potts, :fields] begin
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

@testitem "fields: number types per role (lattice_storage, the backend's default T)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: number types per role (lattice_storage, the backend's default T)" begin
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        for T in (Float64, Float32)
            prob = PottsProblem(FdHalf(; name = :h), [fd_empty((12, 10)); :c => c0], (0, 3); T,
                field_solver = ExplicitEuler(substeps = 8))
            @test eltype(prob.u0.site.c) == Float16 && eltype(prob.u0.site.c__next) == Float16
            u = fd_mcs(prob, 3)
            @test eltype(u[end]) == Float16
            ref = fd_ftcs(Float64.(Float16.(c0)), 1.0, (1, 1), 3.0, 8 * 3; periodic = false)
            @test maximum(abs.(u[end] .- ref)) < 5e-3                     # Float16 rounding per substep
            # control: the same model stored in T differs by the rounding
            full = PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 3); T,
                field_solver = ExplicitEuler(substeps = 8))
            @test eltype(full.u0.site.c) == T && fd_mcs(full, 3)[end] != u[end]
        end
        @test_throws ArgumentError Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_storage = Float16)
        # the default state type follows the backend (host: Float64)
        @test eltype(PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
            backend = CorePotts.KernelAbstractions.CPU(), field_solver = ExplicitEuler()).u0.site.c) == Float64
    end
end

@testitem "F1 SD-14, F4-12a: a boundary value is an expression of parameters" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 SD-14, F4-12a: a boundary value is an expression of parameters" begin
        # F1: refused at the model with the computed-parameter route ("… is an expression of
        # parameters; … `@parameters g = g1 + g2`"); F4-12a (FE-10): it runs, and equals the
        # computed parameter's run bitwise, also after a write
        @test fd_err(() -> FdExprFace(; name = :f)) === nothing
        run(M, p = []) = solve(PottsProblem(M(; name = :f), [fd_empty((8, 8)); p], (0, 2); field_solver = ExplicitEuler())).u[end].site.c
        a = run(FdExprFace)
        @test a == run(FdComputedFace) && maximum(a) > 0
        b = run(FdExprFace, [:g1 => 3.0])
        @test b == run(FdComputedFace, [:g1 => 3.0]) && maximum(b) > maximum(a)
    end
end

@testitem "F1 V13: Potts.fields returns the model's PDESystem" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 V13: Potts.fields returns the model's PDESystem" begin
        # base: `Potts.fields(model) === nothing` on a model with fields
        @test Potts.fields(FdClosed(; name = :f)) isa Potts.ModelingToolkitBase.PDESystem
        @test Potts.fields(mtkcompile(FdClosed(; name = :f))) isa Potts.ModelingToolkitBase.PDESystem
        @test isequal(Potts.ModelingToolkitBase.equations(Potts.fields(FdClosed(; name = :f))),
                      Potts.ModelingToolkitBase.equations(Potts.fields(mtkcompile(FdClosed(; name = :f)))))
        # … with the model's defaults, so `discretize` takes it as it is (base, round 0: the field
        # and the parameters had no value, "no initial condition" / NaN): c(1) = 2 (1 − 0.05)^10
        LP = Potts.LatticePDE
        for m in (FdDefaults(; name = :f), mtkcompile(FdDefaults(; name = :f)))
            prob = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))
            s = LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1))
            @test s.retcode == Potts.SciMLBase.ReturnCode.Success && all(≈(2 * 0.95^10), s[:c, end])
            o = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))
            @test o isa Potts.SciMLBase.ODEProblem && o.p.values == [1.0, 0.5] && all(==(2.0), o.u0)
        end
        # a computed parameter folds and reads (round 1: reading threw): c(1) = (1 − 0.1)^10
        prob = LP.discretize(Potts.fields(FdComputedRate(; name = :f)), LP.LatticeDiscretization(LP.Grid((6, 4));
            T = Float64))
        @test LP.getp(prob, :k2)(prob) == 1.0
        @test all(≈(0.9^10), LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1))[:c, end])
        @test LP.getp(LP.remake(prob; p = [:k => 1.0]), :k2)(LP.remake(prob; p = [:k => 1.0])) == 2.0
        # a kind table on the ODE path is the table (round 2: the right side read the state for
        # it); c = 1 on medium sites: dc/dt = −δ[medium] = −0.5
        o = LP.discretize(Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64);
            inputs = [:kind => zeros(Int32, 10, 8)])
        du = similar(o.u0)
        o.f(du, o.u0, o.p, 0.0)
        @test all(≈(-0.5), du)
        # a field named like a generated input is refused in the model's words (round 4 via A:
        # "the input field `domain__in` has the name `domain`")
        err = something(fd_err(() -> Potts.fields(FdDomainWord(; name = :f))), "(no error)")
        @test occursin("`domain` (the lattice's domain mask)", err) && occursin("also a field", err) && !occursin("__in", err)
        # … and reads back on the owned path (round 3: "`:δ` names nothing of this problem")
        po = LP.discretize(Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64); inputs = [:kind => zeros(Int32, 10, 8)])
        ig = LP.init(po, LP.ExplicitEuler(; dt = 0.1, substeps = 1))
        @test ig.ps[:δ] == [0.5, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        LP.setp(ig, :δ)(ig, [1.0, 0.0])                     # an integrator's table is set (F2-13)
        @test ig.ps[:δ] == [1.0, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        # a problem's table is set as SciML sets a parameter, in place (F4-00; base: refused, "`δ` is a table")
        pw = LP.remake(po; p = [:δ => [0.5, 0.0]])
        LP.setp(pw, :δ)(pw, [1.0, 0.0])
        @test LP.getp(pw, :δ)(pw) == [1.0, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        # a CPM coupling is an input given by its key: one step of `s · (kind == A)` from c = 0
        K = zeros(Int32, 12, 10); K[3:5, 4:6] .= 1
        prob = LP.discretize(Potts.fields(FdSource(; name = :f)), LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64); inputs = [:kind => K])
        s = LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1); saveat = 0.1)
        @test s[:c, 2] ≈ 0.1 * 0.05 .* (K .== 1)
        # … by the model's word (round 1: only the generated key "kind__in"); "kind" too, and the
        # messages print routes that run, never `__in`
        fe(f) = something(fd_err(f), "(no error)")
        fsrc = Potts.fields(FdSource(; name = :f))
        disc = LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)
        @test LP.discretize(fsrc, disc; inputs = ["kind" => K]).p.inputs == prob.p.inputs
        err = fe(() -> LP.solve(LP.discretize(fsrc, disc), LP.ExplicitEuler(; dt = 0.1)))
        @test occursin("`kind`", err) && occursin(":kind => values", err) && !occursin("__in", err)
        # (F4-01: an unset input is named when the problem is solved, by a field algorithm or an
        # OrdinaryDiffEq solver; base: at `discretize` of the ODE problem)
        err = fe(() -> (q = LP.discretize(fsrc, LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)); q.f(similar(q.u0), q.u0, q.p, 0.0)))
        @test occursin(":kind => values", err) && !occursin("__in", err)
        err = fe(() -> LP.discretize(fsrc, disc; inputs = [:kd => K]))
        @test occursin("`kind`", err) && !occursin("__in", err)
        # (the input of a bound CPM read is named by the PDESystem's input bound to it, `volume`;
        # F4-B6 review: before, by the expression text "LatticePDE.at(volume, owner)")
        fvol = Potts.fields(FdVolumeRead(; name = :f))
        V = fill(2.0, 6, 4)
        s = LP.solve(LP.discretize(fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64);
            inputs = ["volume" => V]), LP.ExplicitEuler(; dt = 0.1, substeps = 1); saveat = 0.1)
        @test all(≈(0.1 * 0.01 * 2.0), s[:c, 2])
        err = fe(() -> LP.solve(LP.discretize(fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64)), LP.ExplicitEuler(; dt = 0.1)))
        @test occursin("volume", err) && occursin("=> values", err) && !occursin("__in", err) || (println("V13: ", err); false)
    end
end

@testitem "F1 messages: field terms in the model's words (PO02, PO06)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 messages: field terms in the model's words (PO02, PO06)" begin
        # PO06: the substep refusal names `kind`, not the generated input `kind__in(t, x, y)`
        err = something(fd_err(() -> PottsProblem(FdKindNonlinear(; name = :f), fd_empty((8, 8)), (0, 1);
            field_solver = ExplicitEuler())), "")
        @test occursin("kind", err) && !occursin("kind__in", err) && occursin("substeps = n", err)
        # PO02: LatticePDE's operators lower in `@equations` (F2-10; F1 named them "does not lower",
        # base f9a77dd3: "reads a field or site variable inside a CPM read")
        @test fd_err(() -> mtkcompile(FdDivK(; name = :f))) === nothing
    end
end

@testitem "F1 V11: a Float64 problem on a device backend gives a notice" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 V11: a Float64 problem on a device backend gives a notice" begin
        prob = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler())
        @test_logs (:warn, r"built in Float64") CorePotts._device_float_notice(prob, FdFakeDevice())
        # controls: the host backend, and a Float32 problem (base: no notice anywhere)
        @test_logs CorePotts._device_float_notice(prob, Potts.KernelAbstractions.CPU()) == false
        p32 = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler(), T = Float32)
        @test_logs CorePotts._device_float_notice(p32, FdFakeDevice()) == false
    end
end

# R-F2b (2026-10-20): the filled inputs take one canonical order, whatever order the converter
# meets the CPM reads in (the hash order of a term's arguments): `kind__in` first, the CPM
# reads by expression text (`field1__in`, `field2__in`, … in that order), `domain__in` last
@testitem "R-F2b: the filled inputs take a canonical order" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "R-F2b: the filled inputs take a canonical order" begin
        raw = Tuple{Symbol, Any, Type}[(:kind__in, :kind, Int32), (:field1__in, :zz, Float64),
            (:field2__in, :aa, Float64), (:domain__in, :dom, Bool)]
        a, b = Potts._canonical_filled(raw), Potts._canonical_filled(reverse(raw))
        @test a == b                                                   # the met order does not matter
        @test first.(a) == [:kind__in, :field1__in, :field2__in, :domain__in] && a[2][2] === :aa && a[3][2] === :zz
    end
end

# F2-07: front end B's `FieldGroups` steps FdTwo's field system as the model's two solver groups do
# (c with 2 substeps, then u with 3, reading the new c): σ is frozen (`A[frozen]`), so the
# kind input is the same at every MCS
@testitem "F2-07: B FieldGroups equals a model's two groups (FdTwo, σ frozen)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-07: B FieldGroups equals a model's two groups (FdTwo, σ frozen)" begin
        LP, Sy, SU, MTKB = Potts.LatticePDE, Potts.Symbolics, Potts.SymbolicUtils, Potts.ModelingToolkitBase
        sys = FdTwo(; name = :t)
        op = fd_source_op((12, 10))
        σ0 = copy(last(op[1]))
        prob = PottsProblem(sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)])
        integ = init(prob, SequentialCPM())
        foreach(_ -> step!(integ), 1:3)
        st = current_state(integ)
        @test Array(st.σ) == σ0 && fd_n(integ, 1) == 2 && fd_n(integ, 2) == 3
        # the model's field system in front end B: zero initial values, the time span of 3 MCS
        pdesys, _ = Potts._field_system(sys; T = Float64)
        ivs = pdesys.ivs
        isin(v) = MTKB.isinput(Sy.unwrap(v))
        states = [v for v in pdesys.dvs if !isin(v)]
        ics = [Sy.wrap(SU.operation(Sy.unwrap(v))(0.0, Sy.unwrap.(ivs[2:end])...)) ~ 0.0 for v in states]
        dom = [isequal(Sy.unwrap(d.variables), Sy.unwrap(ivs[1])) ? (ivs[1] ∈ LP.Interval(0.0, 3.0)) : d
               for d in getfield(pdesys, :domain)]
        bsys = MTKB.PDESystem(pdesys.eqs, [pdesys.bcs; ics], dom, ivs, pdesys.dvs, pdesys.ps; name = :b)
        kin = only(v for v in pdesys.dvs if isin(v))
        bp = LP.discretize(bsys, LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64);
            inputs = [kin => Int32.(σ0 .!= 0)])
        groups = LP.FieldGroups(:c => ExplicitEuler(; dt = 1.0, substeps = 2), :u => ExplicitEuler(; dt = 1.0, substeps = 3))
        bi = init(bp, groups)
        @test [r.n for r in bi.runtimes] == [2, 3]
        s = solve!(bi)
        @test isapprox(s[:c, end], Array(st.site.c); rtol = 1e-12) && isapprox(s[:u, end], Array(st.site.u); rtol = 1e-12)
        @test maximum(Array(st.site.u)) > 0                                     # u has grown from c
        # control: one group steps c and u together (u reads the old c)
        one = solve(bp, ExplicitEuler(; dt = 1.0, substeps = 3))
        @test !(one[:u, end] ≈ Array(st.site.u))
    end
end

@testitem "F2-08a: a refused parameter write changes nothing (S1)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: a refused parameter write changes nothing (S1)" begin
        sys = FdRotCells(; name = :r)
        σ = zeros(Int32, 6, 6); σ[2:3, 2:3] .= 1
        pw = PottsProblem(sys, [ownership => σ, kind => [:A]], (0, 40); seed = 3, field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sys, "o") => ExplicitEuler(substeps = 2)])
        ig = init(pw, SequentialCPM())
        step!(ig)
        snap(i) = (i.t, copy(Array(current_state(i).σ)), copy(Array(current_state(i).site.c)), copy(Array(current_state(i).site.o)))
        s1, p1 = snap(ig), ig.p
        for (what, write) in (("setp", () -> setp(ig, :k)(ig, 3.0)), ("integ.ps", () -> (ig.ps[:k] = 3.0)),
                ("setp of two", () -> setp(ig, [:k, :Dc])(ig, [3.0, 0.1])))
            e = fdargerr(write)
            @test occursin("window · Σ max|coefficient| = 3.0 > 1", e)
            @test ig.p === p1 && getp(ig, :k)(ig) == 0.5 && snap(ig) == s1        # nothing changed
        end
        @test occursin("negative", fdargerr(() -> setp(ig, :Dc)(ig, -1.0)))       # the other refusal, the same way
        @test getp(ig, :Dc)(ig) == 0.1 && snap(ig) == s1
        # a kind table past the limit (kind A's entry 5: the coupling 5.5), by setp and by `ps`
        for write in (() -> setp(ig, :κ)(ig, [0.0, 5.0]), () -> (ig.ps[:κ] = [0.0, 5.0]))
            @test occursin("window · Σ max|coefficient| = 5.5 > 1", fdargerr(write))
            @test ig.p === p1 && getp(ig, :κ)(ig) == [0.0, 0.0] && snap(ig) == s1
        end
        @test occursin("window · Σ max|coefficient| = 3.0 > 1", fdargerr(() -> remake(pw; p = [:k => 3.0])))
        # the run goes on, and a write the check accepts takes effect (control)
        step!(ig)
        @test ig.t == s1[1] + 1 && Array(current_state(ig).site.c) != s1[3]
        setp(ig, :k)(ig, 0.4)
        step!(ig)
        @test getp(ig, :k)(ig) == 0.4 && ig.t == s1[1] + 2
    end
end

# F2-13 (F2 design §2.13): `integ.ps[x] = v` writes a scalar or a kind table of a Potts
# integrator, with the checks of `setp`; `integ[p]` and `integ[p] = v` of a parameter are
# errors with the `integ.ps` route (base: SciMLBase's "Indexing with parameters is deprecated"
# ErrorException); states index as before
@testitem "F2-13: integ.ps in a model; integ[p] gives the route" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-13: integ.ps in a model; integ[p] gives the route" begin
        sys = FdRotCells(; name = :r)
        σ = zeros(Int32, 6, 6); σ[2:3, 2:3] .= 1
        ig = init(PottsProblem(sys, [ownership => σ, kind => [:A]], (0, 4); seed = 3, field_solver = ExplicitEuler(substeps = 2)),
            SequentialCPM())
        ig.ps[:κ] = [0.0, 0.25]
        ig.ps[:k] = 0.4
        @test ig.ps[:κ] == [0.0, 0.25] && getp(ig, :κ)(ig) == [0.0, 0.25] && ig.ps[:k] == 0.4
        # the run reads the new values: equal to a problem built with them
        ref = init(PottsProblem(sys, [ownership => σ, kind => [:A], :κ => [0.0, 0.25], :k => 0.4], (0, 4); seed = 3,
            field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        step!(ig); step!(ref)
        @test Array(current_state(ig).site.o) == Array(current_state(ref).site.o)
        for (f, want) in ((() -> ig[:κ], "`κ` is a parameter: read `integ.ps[:κ]`"),
                (() -> (ig[:κ] = [0.0, 1.0]), "`κ` is a parameter: write `integ.ps[:κ] = v`"),
                (() -> ig[:k], "read `integ.ps[:k]`"), (() -> (ig[:k] = 1.0), "write `integ.ps[:k] = v`"),
                (() -> ig[[:c, :k]], "`k` is a parameter"))
            err = fdargerr(f)
            @test occursin(want, err) && !occursin("deprecated", err)
        end
        @test ig.ps[:κ] == [0.0, 0.25] && ig.ps[:k] == 0.4              # nothing was set
        # a field reads and writes as before
        ig[:c] = fill(2.0, 6, 6)
        @test all(==(2.0), Array(ig[:c]))
    end
end

# F2-08a: the substep count of each field group of a Potts problem or integrator, in group
# order (as front end B's `substep_counts`; base: only the internal `CorePotts._runtime(…).n`)
@testitem "F2-08a: substep_counts per field group in a model" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: substep_counts per field group in a model" begin
        sys = FdTwo(; name = :t)
        prob = PottsProblem(sys, fd_source_op((12, 10)), (0, 3); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)])
        integ = init(prob, SequentialCPM())
        @test substep_counts(integ) == [fd_n(integ, 1), fd_n(integ, 2)] == [2, 3]
        @test substep_counts(prob) == [2, 3]
        @test Potts.substep_counts === Potts.LatticePDE.substep_counts                # one function for both front ends
        # it follows a parameter write: diffusion 4× raises the automatic part of the count
        p1 = PottsProblem(FdClosed(; name = :c), fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler())
        i1 = init(p1, SequentialCPM())
        n1 = only(substep_counts(i1))
        setp(i1, :Dc)(i1, 4.0)
        # right after the write, before any step: the count of a fresh integrator at the new value
        # (review M2 of batch 3; base: the last step's count until the next step)
        fresh = substep_counts(init(remake(p1; p = [:Dc => 4.0]), SequentialCPM()))
        @test substep_counts(i1) == fresh && only(fresh) > n1
        step!(i1)
        @test only(substep_counts(i1)) == fd_n(i1) > n1
    end
end

# F2-08a: the field groups of a model are lowered by `LatticePDE.lower_group`, and
# `mtkcompile`'s lowering of the group of all fields is reused by a one-group `PottsProblem`
# (one `lower_group` call for the model); another state type or a split lowers again
@testitem "F2-08a: mtkcompile's GroupSpec is reused (one lower_group call)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: mtkcompile's GroupSpec is reused (one lower_group call)" begin
        calls() = Potts._LOWER_GROUP_CALLS[]
        n0 = calls()
        c = mtkcompile(FdClosed(; name = :c))
        @test calls() == n0 + 1
        prob = PottsProblem(c, fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler())
        @test calls() == n0 + 1                                       # reused
        @test only(substep_counts(init(prob, SequentialCPM()))) >= 1
        PottsProblem(c, fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler(substeps = 4))
        @test calls() == n0 + 1                                       # another algorithm: the same group
        PottsProblem(c, fd_empty((12, 10)), (0, 2); T = Float32, field_solver = ExplicitEuler())
        @test calls() == n0 + 2                                       # control: Float32 lowers once more
        sys2 = FdTwo(; name = :t)
        c2 = mtkcompile(sys2)
        m0 = calls()
        PottsProblem(c2, fd_source_op((12, 10)), (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)])
        @test calls() == m0 + 2                                       # a split: one per group (the whole group is cached)
    end
end

@testitem "F2-08b: a moving mask is clamped at the step start (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08b: a moving mask is clamped at the step start (in a model)" begin
        σ = zeros(Int32, 12, 12); σ[5:7, 5:7] .= 1
        prob = PottsProblem(FdMovingMask(; name = :m), [ownership => σ, kind => [:A]], (0, 40); seed = 5,
            field_solver = ExplicitEuler(substeps = 1))
        integ = init(prob, SequentialCPM())
        c0, m, moved = nothing, nothing, false
        for _ in 1:30                                   # until the cell reaches a site that does not hold `v`
            c0 = copy(Array(current_state(integ).site.c))
            step!(integ)
            m = Array(current_state(integ).σ) .!= 0
            moved = any(m .& (c0 .!= 1.0))
            moved && break
        end
        @test moved
        c1 = Array(current_state(integ).site.c)
        clamped = copy(c0); clamped[m] .= 1.0
        hand = fd_ftcs(clamped, 0.2, (1, 1), 1.0, 1; periodic = false); hand[m] .= 1.0
        @test maximum(abs.(c1 .- hand)) < 1e-14
        late = fd_ftcs(c0, 0.2, (1, 1), 1.0, 1; periodic = false); late[m] .= 1.0     # control: not clamped first
        @test maximum(abs.(c1 .- late)) > 1e-3
    end
end

@testitem "F2-08c: REAL forms of mcs over several MCS (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: REAL forms of mcs over several MCS (in a model)" begin
        # `η mcs` is hoisted into a derived parameter: derived again at each launch with the MCS number
        integ = init(PottsProblem(FdMcsSource(; name = :s), fd_empty((6, 6)), (0, 4); field_solver = ExplicitEuler(substeps = 4)),
            SequentialCPM())
        hand = 1.0
        for k in 0:3
            step!(integ)
            for _ in 1:4
                hand += 0.25 * (-hand + 0.5 * k)
            end
            @test all(v -> isapprox(v, hand; rtol = 1e-13), Array(current_state(integ).site.c))
        end
        # `(1 + ε mcs)` multiplies the diffusion (a term the bound cannot see: an explicit count);
        # a slow Fourier mode, so each MCS's factor shows
        c0 = [1.0 + cos(π * (i - 1) / 3) for i in 1:6, j in 1:6]
        prob = PottsProblem(FdMcsDiff(; name = :d), [fd_empty((6, 6)); :c => c0], (0, 3); field_solver = ExplicitEuler(substeps = 16))
        integ = init(prob, SequentialCPM())
        want = copy(c0)
        for k in 0:2
            step!(integ)
            want = fd_ftcs(want, 1 + 0.5 * k, (1, 1), 1.0, 16; periodic = true)
            @test isapprox(Array(current_state(integ).site.c), want; rtol = 1e-12)
        end
    end
end

@testitem "F2-08c: repeat(4, fields): one step index per MCS, windows mcs_duration/4 apart (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: repeat(4, fields): one step index per MCS, windows mcs_duration/4 apart (in a model)" begin
        sol = solve(PottsProblem(FdClockRepeat(; name = :r), fd_empty((4, 4)), (0, 3); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM())
        u = sol.u[end]
        @test all(≈(0 + 1 + 2), u.site.c)                                  # four passes of 1/4 at k = 0, 1, 2
        @test all(≈(0.25 * sum(0.25 * i for i in 0:11)), u.site.u)          # windows at t0 = 0, 0.25, …, 2.75
    end
end

@testitem "F2-08c: time in a field reads t0 + j h per substep (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: time in a field reads t0 + j h per substep (in a model)" begin
        integ = init(PottsProblem(FdTimeRead(; name = :t), fd_empty((4, 4)), (0, 3); field_solver = ExplicitEuler(substeps = 4)),
            SequentialCPM())
        hand = 0.3
        for m in 0:2
            step!(integ)
            for j in 0:3
                hand += 0.25 * (-hand + sin(m + 0.25 * j))
            end
            @test all(v -> isapprox(v, hand; atol = 1e-13), Array(current_state(integ).site.c))
        end
    end
end

@testitem "F2-08c: repeat(4, fields) with mcs_duration = 0.5 from MCS 2 (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: repeat(4, fields) with mcs_duration = 0.5 from MCS 2 (in a model)" begin
        u = solve(PottsProblem(FdClockHalf(; name = :h), fd_empty((4, 4)), (2, 5); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM()).u[end]
        c, uu, w = 0.0, 0.0, 1.0
        for m in 2:4, r in 0:3
            c += 0.125 * m
            uu += 0.125 * (m + r / 4) * 0.5
            w += 0.125 * (-w + 0.5 * m)
        end
        @test all(≈(c; rtol = 1e-13), u.site.c) && all(≈(uu; rtol = 1e-13), u.site.u) && all(≈(w; rtol = 1e-13), u.site.w)
    end
end

@testitem "F2-10: operators and aux fields equal LatticePDE's own run, bitwise" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-10: operators and aux fields equal LatticePDE's own run, bitwise" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        dims, k, n = (8, 6), 3, 4
        c0 = rand(StableRNG(3), dims...)
        Potts.ModelingToolkitBase.@parameters x y K0 = 0.4 s = 0.01 ux = 0.3
        Potts.ModelingToolkitBase.@variables c(..) K(..)
        ce, Ke = c(tt, x, y), K(tt, x, y)
        dom = [tt ∈ LP.Interval(0.0, Float64(k)), x ∈ LP.Interval(0.0, 8.0), y ∈ LP.Interval(0.0, 6.0)]
        Dx, Dy = MTKB.Differential(x), MTKB.Differential(y)
        b(eqs, dvs, ps) = MTKB.PDESystem(eqs, [c(0, x, y) ~ 0.0], dom, [tt, x, y], dvs, ps; name = :b)
        bsys = Dict(:FpDivK => b([DD(ce) ~ LP.DivKGrad(:harmonic)(K0, ce) + s * x], [ce], [K0, s]),
            :FpRaw => b([DD(ce) ~ Dx(K0 * Dx(ce)) + Dy(K0 * Dy(ce)) + s * x], [ce], [K0, s]),
            :FpAdvect => b([DD(ce) ~ -LP.Advect(LP.Upwind1())([ux, 0.0], ce) + s * y], [ce], [ux, s]),
            :FpAux => b([Ke ~ K0 * (1 + 0.05 * x), DD(ce) ~ LP.DivKGrad(:arithmetic)(Ke, ce) + s * x], [ce, Ke], [K0, s]))
        for (name, M) in ((:FpDivK, FpDivK), (:FpRaw, FpRaw), (:FpAdvect, FpAdvect), (:FpAux, FpAux))
            prob = PottsProblem(M(; name = :f), [fd_empty(dims); :c => c0], (0, k); field_solver = ExplicitEuler(; substeps = n))
            integ = init(prob, SequentialCPM())
            foreach(_ -> step!(integ), 1:k)
            a = Array(current_state(integ).site.c)
            bp = LP.discretize(bsys[name], LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
            bb = LP.solve(LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; dt = 1.0, substeps = n))[:c, end]
            @test a == bb
            @test maximum(abs, a .- c0) > 1e-3                 # the operator moved the field
        end
        # the raw flux form is the `DivKGrad` form (B's rule)
        rawdiv = [Array(solve(PottsProblem(M(; name = :f), [fd_empty(dims); :c => c0], (0, k);
                      field_solver = ExplicitEuler(; substeps = n)), SequentialCPM()).u[end].site.c) for M in (FpRaw, FpDivK)]
        @test rawdiv[1] == rawdiv[2]
    end
end

@testitem "F2-10 review: map under repeat, constant velocity, global coordinates, z in 2D" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-10 review: map under repeat, constant velocity, global coordinates, z in 2D" begin
        # M1: one map per MCS under `repeat(4, fields)` (base, before the fix: 1.875, 1.9921875, …:
        # one map per pass)
        integ = init(PottsProblem(FpMapRepeat(; name = :f), fd_empty((6, 4)), (0, 3)), SequentialCPM())
        vals = [(step!(integ); Array(current_state(integ).site.m)[1]) for _ in 1:3]
        @test vals == [1.0, 1.5, 1.75]
        # M2: the old refusal's route followed verbatim, `[0.3, 0.0]`, equals the parameter form
        # bitwise (base: "`Advect` takes … or a vector of 2 terms (`[ux, uy]`)")
        c0 = rand(StableRNG(3), 8, 6)
        run(M) = solve(PottsProblem(M(; name = :f), [fd_empty((8, 6)); :c => c0], (0, 2);
            field_solver = ExplicitEuler(; substeps = 4)), SequentialCPM()).u[end].site.c
        @test run(FpAdvectConst) == run(FpAdvect)
        # M3: a module global `y` read in a body (here a binding of `@fields`) warns (base: the
        # coordinate replaced it silently); a declared `x` does not
        m = Module(:FpGlobals)
        Core.eval(m, :(using Potts; const y = 3.0; const x = 1.0))
        P = FdPDE
        @test_logs (:warn, r"`y` in the model body is the lattice coordinate") match_mode = :any Core.eval(m, quote
            @potts_model GlobY begin
                @kinds medium A
                @lattice Lattice((6, 4); boundary = Closed())
                @energy cells(A) => (volume - 9.0)^2
                @fields $P.volume_read() ($P.volume => y)
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        @test_logs min_level = Base.CoreLogging.Warn Core.eval(m, quote
            @potts_model DeclX begin
                @kinds medium A
                @parameters x = 0.5
                @lattice Lattice((6, 4); boundary = Closed())
                @energy cells(A) => (volume - 9.0)^2
                @fields $P.volume_read() ($P.volume => x)
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        # R1 (batch 4 round 2): a helper argument `x` binds `x` in the helper only, so the binding's
        # `x` (the coordinate) still warns (base: the helper silenced the warning for the body)
        @test_logs (:warn, r"`x` in the model body is the lattice coordinate") match_mode = :any Core.eval(m, quote
            @potts_model GlobXHelper begin
                @kinds medium A
                @lattice Lattice((6, 4); boundary = Closed())
                g(x) = 2x
                @energy cells(A) => (volume - 9.0)^2
                @fields $P.volume_read() ($P.volume => g(1.0) * x)
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        # controls: reads of `x` only inside binders (a helper, its keyword, a generator) and a
        # keyword name (R2) do not warn
        @test_logs min_level = Base.CoreLogging.Warn Core.eval(m, quote
            @potts_model LocalXOnly begin
                @kinds medium A
                @lattice Lattice((6, 4); boundary = Closed())
                g(x) = 2x
                h(; x = 1.0) = 3x
                w = sum(x for x in 1:3)
                @energy cells(A) => (volume - 9.0)^2
                @fields $P.volume_read() ($P.volume => g(1.0) + h(x = 0.5) + w)
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        # R3: a wrong-length velocity prints the vector and the operators as written (base:
        # `SymbolicUtils.array_literal((1,), 0.3)`, `LatticePDE.Advect{…}`, `LatticePDE.Δ`)
        err = something(fd_err(() -> mtkcompile(FpAdvectShort(; name = :f))), "")
        @test occursin("cannot lower `[0.3]`", err) && occursin("got 1", err) || (println("R3: ", err); false)
        @test !occursin("array_literal", err) && !occursin("LatticePDE.", err)
        # S4: `Differential(z)` on a 2D lattice is not an axis of the PDESystem (base: "the model
        # declares its own `z`")
        err = something(fd_err(() -> mtkcompile(FpZ2D(; name = :f))), "")
        @test occursin("differentiates along `z`", err) && occursin("not one of its independent variables", err) &&
              !occursin("declares its own", err) || (println("S4: ", repr(err)); false)
    end
end

@testitem "F2-10: maps, one kind per model, coordinates" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-10: maps, one kind per model, coordinates" begin
        LP = Potts.LatticePDE
        # a map steps once per MCS (`ExplicitMap()` by default): m₁ = x, m₂ = 0.5 m₁ + x, …
        integ = init(PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3)), SequentialCPM())
        vals = [(step!(integ); copy(Array(current_state(integ).site.m))) for _ in 1:3]
        xs = [i - 0.5 for i in 1:6, j in 1:4]                  # the cell centers along x
        @test vals[1] == xs && vals[2] == 0.5 .* xs .+ xs && vals[3] == 0.5 .* vals[2] .+ xs
        # `solvers` takes `ExplicitMap()` for it; a rate algorithm is refused naming `ExplicitMap()`
        sm = solve(PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3); solvers = [:m => ExplicitMap()]), SequentialCPM())
        @test Array(sm.u[end].site.m) == vals[3]
        err = something(fd_err(() -> PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3); field_solver = ExplicitEuler())), "")
        @test occursin("`ExplicitMap()`", err) && occursin("map field", err)
        # B steps the model's map the same way
        bm = LP.solve(LP.discretize(Potts.fields(FpMap(; name = :f)), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64)), ExplicitMap())
        @test bm[:m, 2] == vals[1] && bm[:m, end] == vals[1]  # B's span is the PDESystem's (0, 1): one map step
        # a rate and a map in one model: refused on both front ends with F1's message
        err = something(fd_err(() -> mtkcompile(FpMixed(; name = :f))), "")
        @test occursin("mixes rate equations (of `c`) and maps (of `m`)", err) && occursin("@after_mcs", err)
        err = something(fd_err(() -> LP.discretize(Potts.fields(FpMixed(; name = :f)),
            LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))), "")
        @test occursin("mixes rate equations (of `c`) and maps (of `m`)", err) && occursin("two systems", err)
        # `z` is the third coordinate: one substep of 0.1 z (cell centers 0.5, 1.5, 2.5)
        uz = solve(PottsProblem(FpZ(; name = :f), fd_empty((4, 4, 3)), (0, 1)), SequentialCPM()).u[end].site.c
        @test all(kk -> all(≈(0.1 * (kk - 0.5); rtol = 1e-14), uz[:, :, kk]), 1:3)
    end
end

@testitem "F2-11: conditions lowered: a Dirichlet face, Flux and Robin" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-11: conditions lowered: a Dirichlet face, Flux and Robin" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        dims, n = (8, 6), 4
        c0 = rand(StableRNG(5), dims...)
        run(M; k = 2) = (integ = init(PottsProblem(M(; name = :f), [fd_empty(dims); :c => c0], (0, k);
                             field_solver = ExplicitEuler(; substeps = n)), SequentialCPM());
                         foreach(_ -> step!(integ), 1:k); Array(current_state(integ).site.c))
        # `c(t, 0, y) ~ 1` is the face value: the hand FTCS with the ghost `2 − c` (the face value is
        # the mean of the edge site and its ghost); without it the run differs
        a1 = run(FbBcsFace; k = 1)
        @test isapprox(a1, fb_ftcs(c0, 0.5, 1.0, 1.0, n, (d, s, ce) -> d == 1 && s < 0 ? 2.0 - ce : ce); rtol = 1e-13)
        @test run(FbBcsFace) != run(FbNone)
        # a flux and a Robin face: a hand FTCS with the ghost-node rule: low x, ∂c/∂n = q gives c + q h; high x,
        a = run(FbFluxRobin; k = 1)
        # α (c + g′)/2 + β (g′ − c)/h = g gives g′ = (g − c (α/2 − β/h)) / (α/2 + β/h); y zero flux
        ghost(d, s, ce) = d == 2 ? ce : s < 0 ? ce + 0.2 : (0.5 - ce * (1.0 - 1.0)) / (1.0 + 1.0)
        hand = fb_ftcs(c0, 0.5, 1.0, 1.0, n, ghost)
        @test isapprox(a, hand; rtol = 1e-13)
        # (control: the low side's sign flipped misses the oracle)
        @test !isapprox(a, fb_ftcs(c0, 0.5, 1.0, 1.0, n, (d, s, ce) -> d == 1 && s < 0 ? ce - 0.2 : ghost(d, s, ce)); rtol = 1e-6)
        # a Neumann and a Robin face match LatticePDE's own run of the same PDESystem
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        Potts.ModelingToolkitBase.@parameters x y Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr = 0.5
        Potts.ModelingToolkitBase.@variables c(..)
        ce = c(tt, x, y)
        bsys = MTKB.PDESystem([DD(ce) ~ Dc * LP.Δ(ce)],
            [c(0, x, y) ~ 0.0, MTKB.Differential(x)(c(tt, 8, y)) ~ q, αr * c(tt, x, 0) - βr * MTKB.Differential(y)(c(tt, x, 0)) ~ gr],
            [tt ∈ LP.Interval(0.0, 2.0), x ∈ LP.Interval(0.0, 8.0), y ∈ LP.Interval(0.0, 6.0)], [tt, x, y], [ce],
            [Dc, q, αr, βr, gr]; name = :b)
        bp = LP.discretize(bsys, LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
        @test run(FbBcsNR) == LP.solve(LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; dt = 1.0, substeps = n))[:c, end]
        # `Potts.fields` carries the conditions
        hasder(f) = any(b -> occursin("Differential(x", string(b)), getfield(f, :bcs))
        @test hasder(Potts.fields(FbFluxRobin(; name = :f))) && hasder(Potts.fields(FbFluxRobinBcs(; name = :f)))
        @test any(b -> occursin("c(t, 0.0, y) ~ 1.0", string(b)) || occursin("c(t, 0, y) ~ 1.0", string(b)),
                  getfield(Potts.fields(FbBcsFace(; name = :f)), :bcs))
    end
end

@testitem "F2-11 review: off-face lines, a self-reading mask, h = 2" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-11 review: off-face lines, a self-reading mask, h = 2" begin
        # S1: a condition off a face is `parse_bcs`'s, with the faces named (base: "the high side
        # of `x`, which `@boundary c` sets too"); the location names the PDESystem
        err = something(fd_err(() -> mtkcompile(FbInterior(; name = :f))), "")
        @test occursin("`x = 3` is not on a face", err) && occursin("the high face is `x = 8.0`", err) && !occursin("high side", err) ||
              (println("S1: ", err); false)
        @test occursin("PDESystem `fields`", err) && !occursin("in @equations", err) || (println("S1: ", err); false)
        # (a): a mask that reads the field it clamps: clamped first, evaluated at each MCS start on
        # the clamped values, held over the MCS (hand oracle)
        c0 = rand(StableRNG(9), 8, 6)
        run(M; k = 3, n = 1) = solve(PottsProblem(M(; name = :f), [fd_empty((8, 6)); :c => c0], (0, k);
            field_solver = ExplicitEuler(; substeps = n)), SequentialCPM()).u[end].site.c
        hand = map(v -> v >= 0.8 ? 0.8 : v, c0)
        for _ in 1:3
            m = hand .>= 0.8
            hand = ifelse.(m, 0.8, hand .+ 0.1)
        end
        a = run(FbSelfMaskBcs)
        @test isapprox(a, hand; rtol = 1e-14)
        # R5: with 4 substeps and diffusion, the mask is held over the MCS: evaluated at the window
        # start (then clamped), the values clamped after each substep; the control evaluates the
        # mask at every substep and misses
        function selfmask(rule; n = 4, k = 3)
            c = map(v -> v >= 0.8 ? 0.8 : v, c0)                     # the clamp at init
            for _ in 1:k
                m = c .>= 0.8
                c[m] .= 0.8
                for _ in 1:n
                    rule === :substep && (m = c .>= 0.8)
                    c = fb_ftcs(c, 0.5, 1.0, 1 / n, 1, (d, s, ce) -> ce) .+ 0.1 / n
                    c[m] .= 0.8
                end
            end
            return c
        end
        a = run(FbSelfMaskDiffBcs; n = 4)
        @test isapprox(a, selfmask(:start); rtol = 1e-14)
        @test !isapprox(a, selfmask(:substep); rtol = 1e-6)
        # N1: `Flux` and `Robin` on both axes at h = 2 against the ghost-node FTCS (α/2 − β/h ≠ 0);
        # the control `q / h` for `q h` misses
        b = solve(PottsProblem(FbFluxRobin2(; name = :f), [fd_empty((8, 6)); :c => c0], (0, 1);
            field_solver = ExplicitEuler(; substeps = 4)), SequentialCPM()).u[end].site.c
        g2(d, s, ce) = s < 0 ? ce + 0.2 * 2.0 : (0.5 - ce * (1.5 - 0.5)) / (1.5 + 0.5)
        @test isapprox(b, fb_ftcs(c0, 0.5, 2.0, 1.0, 4, g2); rtol = 1e-13)
        @test !isapprox(b, fb_ftcs(c0, 0.5, 2.0, 1.0, 4, (d, s, ce) -> s < 0 ? ce + 0.2 / 2.0 : g2(d, s, ce)); rtol = 1e-6)
    end
end

# Review round 2 of F2 batch 4, open question (accepted): a mask reads the state at its group's
# window start. A mask on `c` that reads `e`, stepped after `c`, reads `e` before its step,
# with one solver group or two (`c`'s first), and equals LatticePDE's own run; a mask on `e` that reads `c`,
# stepped earlier in another solver group, reads `c` as stepped in this MCS (as a rate reads
# another group). The controls (the other oracle in each case) miss.
@testitem "F2-11 review: a mask reads its group's window start" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-11 review: a mask reads its group's window start" begin
        LP = Potts.LatticePDE
        dims, K, N = (8, 6), 3, 4
        c0 = rand(StableRNG(21), dims...)
        e0 = 0.6 .* rand(StableRNG(22), dims...)
        zf(d, s, ce) = ce
        function runA(M; kw...)
            integ = init(PottsProblem(M(; name = :f), [fd_empty(dims); :c => c0; :e => e0], (0, K); kw...), SequentialCPM())
            return [(step!(integ); st = current_state(integ).site; (Array(st.c), Array(st.e))) for _ in 1:K]
        end
        one = (; field_solver = ExplicitEuler(; substeps = N))
        two = (; solvers = [:c => ExplicitEuler(; substeps = N), :e => ExplicitEuler(; substeps = 2)])
        # the mask on `c` from `e` at the window start (`:start`) or after `e`'s step (`:after`)
        function later(src)
            c, e = copy(c0), copy(e0)
            c[e .>= 0.5] .= 0.8                                       # the clamp at init
            out = Matrix{Float64}[]
            for _ in 1:K
                en = e .+ 0.1
                m = (src === :start ? e : en) .>= 0.5
                c[m] .= 0.8
                for _ in 1:N
                    c = fb_ftcs(c, 0.5, 1.0, 1 / N, 1, zf)
                    c[m] .= 0.8
                end
                e = en
                push!(out, copy(c))
            end
            return out
        end
        hs, ha = later(:start), later(:after)
        @test fd_err(() -> mtkcompile(FbMaskLaterBcs(; name = :f))) === nothing
        for kw in (one, two)
            a = runA(FbMaskLaterBcs; kw...)
            @test all(i -> isapprox(a[i][1], hs[i]; rtol = 1e-14), 1:K)
            @test !isapprox(a[K][1], ha[K]; rtol = 1e-6)               # control: `e` after its step
        end
        # LatticePDE's own run (`Potts.fields` → `discretize`) equals the coupled one with one solver group, bitwise
        pf = Potts.fields(FbMaskLaterBcs(; name = :f))
        bp = LP.discretize(pf, LP.LatticeDiscretization(LP.Grid(dims); T = Float64);
            u0 = [:c => c0, :e => e0], tspan = (0, K))
        sbp = LP.solve(bp, LP.ExplicitEuler(; dt = 1.0, substeps = N); saveat = 1.0)
        b = [sbp[:c, i] for i in 2:length(sbp.t)]
        @test b == [x[1] for x in runA(FbMaskLaterBcs; one...)]
        # the mask on `e` from `c` at the window start or after `c`'s step
        function earlier(src)
            c, e = copy(c0), copy(e0)
            e[c .>= 0.5] .= 0.0
            out = Matrix{Float64}[]
            for _ in 1:K
                cn = copy(c)
                for _ in 1:N
                    cn = fb_ftcs(cn, 0.5, 1.0, 1 / N, 1, zf) .- (0.2 / N) .* cn
                end
                m = (src === :start ? c : cn) .>= 0.5
                e = ifelse.(m, 0.0, e .+ 0.1)
                c = cn
                push!(out, copy(e))
            end
            return out
        end
        gs, ga = earlier(:start), earlier(:after)
        a1, a2 = runA(FbMaskEarlier; one...), runA(FbMaskEarlier; two...)
        @test all(i -> isapprox(a1[i][2], gs[i]; rtol = 1e-14), 1:K) && !isapprox(a1[K][2], ga[K]; rtol = 1e-6)
        @test all(i -> isapprox(a2[i][2], ga[i]; rtol = 1e-14), 1:K) && !isapprox(a2[K][2], gs[K]; rtol = 1e-6)
    end
end

@testitem "F2-11: the refusals, each with its route" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-11: the refusals, each with its route" begin
        # a periodic pair on an axis the lattice closes: per-field periodicity is FE-20 (`Robin`
        # with β = 0 or α = 0, a face set twice and an initial condition in `@bcs` were front end A's
        # refusals, gone with it in F4-B6)
        err = something(fd_err(() -> mtkcompile(FbPeriodicBcs(; name = :f))), "")
        @test occursin("FE-20", err) && occursin("periodic", err) || (println("periodic: ", err); false)
    end
end

# F2-12 (F2 design §2.8): `Potts.fields(model)` → `discretize(…; p = [:k => 2.0])` runs with no
# `remake` (base: a `MethodError`, the keyword did not exist)
@testitem "F2-12: Potts.fields then discretize with keywords" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-12: Potts.fields then discretize with keywords" begin
        LP = Potts.LatticePDE
        disc = LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)
        prob = LP.discretize(Potts.fields(FdClosed(; name = :f)), disc; p = [:k => 0.5], u0 = [:c => 1.0], tspan = (0, 1))
        @test LP.getp(prob, :k)(prob) == 0.5 && all(==(1.0), prob.u0)
        # a uniform field decays by (1 − 0.1 k) per step: 0.95^10 (control: the default k = 0 keeps 1)
        @test all(≈(0.95^10; rtol = 1e-13), LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1))[:c, end])
    end
end

@testitem "F2-15: computed parameters read-only and derived, in a model and in B" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-15: computed parameters read-only and derived, in a model and in B" begin
        LP, SII = Potts.LatticePDE, Potts.SymbolicIndexingInterface
        err(f) = something(fd_err(f), "")
        c0 = rand(StableRNG(15), 8, 6)
        # A computed face value through `Potts.fields`: B's owned run equals A's field (σ frozen,
        # no cell), bitwise, and both follow `g1`
        prob = PottsProblem(FdComputedFace(; name = :f), [fd_empty((8, 8)); :c => rand(StableRNG(4), 8, 8)], (0, 2);
            field_solver = ExplicitEuler(; substeps = 2))
        a = solve(prob, SequentialCPM()).u[end].site.c
        bp = LP.discretize(Potts.fields(FdComputedFace(; name = :f)), LP.LatticeDiscretization(LP.Grid((8, 8)); T = Float64); u0 = [:c => prob.u0.site.c], tspan = (0, 2))
        @test LP.solve(bp, LP.ExplicitEuler(; dt = 1.0, substeps = 2))[:c, end] == a
        a3 = solve(Potts.remake(prob; p = [:g1 => 3.0]), SequentialCPM()).u[end].site.c
        @test LP.solve(LP.remake(bp; p = [:g1 => 3.0]), LP.ExplicitEuler(; dt = 1.0, substeps = 2))[:c, end] == a3 != a
        # one table of writes against the model, B owned and B ODE: equal values, equal refusals
        pa = PottsProblem(FdChainK(; name = :k), [fd_empty((8, 6)); :c => c0], (0, 1))
        sysb = Potts.fields(FdChainK(; name = :k))
        # (F4-01: `po` is the owned problem of the one problem `discretize` returns, `pd` that problem)
        disc() = LP.LatticeDiscretization(LP.Grid((8, 6)); T = Float64)
        po, pd = LP.Problems.field_problem(LP.discretize(sysb, disc())), LP.discretize(sysb, disc())
        reads(q) = (getp(q, :β)(q), getp(q, :γ)(q))
        for (write, want) in (([:α => 0.2], (0.4, 0.45)), ([:α => 0.0], (0.0, 0.05)), ([:Dc => 0.3], (0.2, 0.25)))
            @test reads(Potts.remake(pa; p = write)) == reads(LP.remake(po; p = write)) == reads(LP.remake(pd; p = write)) == want
        end
        for write in ([:β => 1.0], [:γ => 1.0], [:α => 0.2, :γ => 1.0])
            ea, eo, ed = err(() -> Potts.remake(pa; p = write)), err(() -> LP.remake(po; p = write)), err(() -> LP.remake(pd; p = write))
            n = String(first(last(write)))
            for e in (ea, eo, ed)
                @test occursin("`$n` is computed from `α`", e) && occursin("set `α`", e)
            end
        end
        # the derivation is transitive: α → β → γ moves γ, and the run reads it (A equals B's ODE
        # right side at the new values)
        ia = init(Potts.remake(pa; p = [:α => 0.3]), SequentialCPM())
        @test ia.ps[:γ] == 0.65 && !SII.is_parameter(ia, :γ) && SII.is_observed(ia, :γ)
        ib = LP.init(po, LP.ExplicitEuler(; dt = 1.0))
        ib.ps[:α] = 0.3
        @test ib.ps[:γ] == 0.65
        step!(ib)
        @test ib[:c] == LP.solve(LP.remake(po; p = [:α => 0.3]), LP.ExplicitEuler(; dt = 1.0))[:c, end]   # the step reads γ
        @test occursin("`γ` is computed from `α`", err(() -> (ib.ps[:γ] = 1.0))) && ib.ps[:γ] == 0.65
        # SciMLStructures: A's `replace` derives again; B's parameter vector, replaced whole with a
        # stale computed slot, is derived again by `remake`
        SS = Potts.SciMLStructures
        q = SS.replace(SS.Tunable(), pa.p, [0.3, 0.2])
        @test (q.α, q.β, q.γ) == (0.3, 0.6, 0.65)
        v = copy(po.p)
        v[SII.parameter_index(po, :α)] = 0.3
        v[findfirst(==(0.25), v)] = 99.0                    # γ's slot, stale
        r = LP.remake(po; p = v)
        @test getp(r, :γ)(r) == 0.65 && !(99.0 in r.p)
        @test LP.solve(r, LP.ExplicitEuler(; dt = 1.0))[:c, end] == LP.solve(LP.remake(po; p = [:α => 0.3]), LP.ExplicitEuler(; dt = 1.0))[:c, end]
    end
end

@testitem "F3-00: aux fields with states start at rhs (in a model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-00: aux fields with states start at rhs (in a model)" begin
        σ0 = zeros(Int32, 8, 8)
        σ0[3:5, 3:5] .= 1
        c0 = [0.1 * i + 0.01 * j for i in 1:8, j in 1:8]
        integ = init(PottsProblem(FaState(; name = :s), [ownership => σ0, kind => [:A], :c => c0], (0, 2);
            field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        st0 = CorePotts.current_state(integ)
        @test Array(st0.site.c) == c0                                   # the zero-length step moves no state
        @test Array(st0.site.K) ≈ 2 .* c0 .+ 1 rtol = 1e-14
        @test Array(integ.saved_u[1].site.K) ≈ 2 .* c0 .+ 1 rtol = 1e-14  # the saved start
        # N1: `c` keeps its initial value bitwise under `lower = 0.0`; `K = rhs(u0)`
        ig = init(PottsProblem(FaLower(; name = :l), [ownership => σ0, kind => [:A]], (0, 2);
            field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), SequentialCPM())
        sl = CorePotts.current_state(ig)
        @test all(==(-1.0), Array(sl.site.c)) && all(==(-1.0), Array(sl.site.K))
        @test all(==(-1.0), Array(ig.saved_u[1].site.c))
        step!(ig)                                                       # (the step clips: `lower` holds)
        @test minimum(Array(CorePotts.current_state(ig).site.c)) >= 0.0
    end
end

@testitem "F3-00: aux-only fields in a model" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-00: aux-only fields in a model" begin
        st(integ) = CorePotts.current_state(integ)
        σ0 = zeros(Int32, 12, 8)
        σ0[3:6, 3:6] .= 1
        # P60bnFieldAlg's shape: builds; `cfield = 1` at init (declared 0) and after each MCS; no substep
        integ = init(PottsProblem(FaOne(; name = :a), [ownership => σ0, kind => [:A]], (0, 3)), SequentialCPM())
        @test all(==(1.0), Array(st(integ).site.cfield)) && substep_counts(integ) == [0]
        step!(integ)
        @test all(==(1.0), Array(st(integ).site.cfield))
        # PO07: a `field_solver` names the aux field
        err = try
            PottsProblem(FaOne(; name = :a), [ownership => σ0, kind => [:A]], (0, 1); field_solver = ExplicitEuler()); ""
        catch e
            sprint(showerror, e)
        end
        @test occursin("has no field to integrate: `cfield ~ …` is an aux field, evaluated once per MCS with no solver", err)
        # the clock: once per MCS under `repeat(4, …)`, in pass 1 (`time` at the MCS start, `mcs`
        # its number), one launch per MCS; at init `K = 0` (mcs 0, time 0; declared -1)
        s1 = zeros(Int32, 6, 4)
        s1[2:3, 2:3] .= 1
        integ = init(PottsProblem(FaClock(; name = :a), [ownership => s1, kind => [:A]], (0, 3)), SequentialCPM())
        @test all(==(0.0), Array(st(integ).site.K))
        for j in 1:3
            l0 = integ.stats.launches
            step!(integ)
            @test all(==(1.5 * (j - 1)), Array(st(integ).site.K)) && integ.stats.launches - l0 == 1
        end
        # a CPM read: `K` follows the kinds after each sweep (the phase runs after the sweep)
        s2 = zeros(Int32, 12, 12)
        s2[2:5, 2:5] .= 1
        s2[7:10, 7:10] .= 2
        integ = init(PottsProblem(FaKind(; name = :a), [ownership => s2, kind => [:A, :B]], (0, 4); seed = 3), SequentialCPM())
        owner(s) = (σ = Array(s.σ); [i == 0 ? 0 : (i == 1 ? 1 : 2) for i in σ])
        @test Array(st(integ).site.K) == Float64.(owner(st(integ)) .== 2)
        moved = false
        for _ in 1:4
            σb = Array(st(integ).σ)
            step!(integ)
            moved |= Array(st(integ).σ) != σb
            @test Array(st(integ).site.K) == Float64.(owner(st(integ)) .== 2)
        end
        @test moved                                     # the sweep moved the cells
        # a drive that reads `K`: the first sweep reads the init value (`K = 1`), so nothing moves;
        # control: with `K = 0` until the phase of MCS 3 (mcs 2), the sweeps move σ until then, and
        # the sweep after that phase sees `K = 1` and moves nothing
        s3 = zeros(Int32, 12, 12)
        s3[4:7, 4:7] .= 1
        run(m0, n) = (ig = init(PottsProblem(FaBlock(; name = :a), [ownership => s3, kind => [:A], :m0 => m0], (0, n); seed = 5),
                          SequentialCPM());
                      [(step!(ig); Array(st(ig).σ)) for _ in 1:n])
        @test all(==(s3), run(0.0, 2))
        late = run(2.0, 5)
        @test late[1] != s3 && late[2] != late[1] && late[3] != late[2]   # K = 0 in the sweeps of MCS 1–3
        @test late[4] == late[3] && late[5] == late[3]                    # K = 1 from the sweep of MCS 4
    end
end

@testitem "F3-01: one substep policy, one warning set" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-01: one substep policy, one warning set" begin
        LP, LFP, MTKB = Potts.LatticePDE, Potts.LatticeFields.Problems, Potts.ModelingToolkitBase
        warns(logs) = count(l -> l.level == Base.CoreLogging.Warn && occursin("does not cover", string(l.message)), logs)
        # the policy warns once per key and process: forget the keys warned so far (by an earlier
        # item in this worker, or an earlier run of this item in a dev session)
        lock(() -> empty!(LFP._SEEN_WARNED), LFP._SEEN_WARNED_LOCK)
        n0 = length(LFP._SEEN_WARNED)
        op = fd_empty((8, 8))
        # A: a sweep over `kw` with an explicit count warns once, in A's words (the A route kept)
        logs, probs = Test.collect_test_logs() do
            [PottsProblem(FwNonlinear(; name = :w), [op; :kw => k], (0, 1); field_solver = ExplicitEuler(substeps = 4))
             for k in (0.5, 0.7, 0.9)]
        end
        @test warns(logs) == 1 && occursin(r"field `c`: 4 substeps per field step.*does not cover `[^`]*c\^2", string(logs[end].message))
        @test length(LFP._SEEN_WARNED) == n0 + 1                       # the one set
        rule = only(ph.substeps for e in probs[1].f.phases.mcs for t in (e isa CorePotts.Repeat ? e.entries : (e,))
                    if t isa Tuple for ph in t if ph isa CorePotts.FieldPhase && !ph.init)
        @test rule isa LFP.GroupSubsteps
        # B: the same term in a PDESystem, a sweep over `kw` warns once more (its own program), in B's words
        Potts.ModelingToolkitBase.@parameters x y Dc = 0.1 kw = 0.5
        Potts.ModelingToolkitBase.@variables c(..)
        ce = c(MTKB.t_nounits, x, y)
        dom = [MTKB.t_nounits ∈ LP.Interval(0.0, 1.0), x ∈ LP.Interval(0.0, 8.0), y ∈ LP.Interval(0.0, 8.0)]
        sys = MTKB.PDESystem([MTKB.D_nounits(ce) ~ Dc * LP.Δ(ce) - kw * ce^2], [c(0, x, y) ~ 0.0], dom, [MTKB.t_nounits, x, y],
            [ce], [Dc, kw]; name = :w)
        bp = LP.discretize(sys, LP.LatticeDiscretization(LP.Grid((8, 8)); T = Float64))
        logs, _ = Test.collect_test_logs() do
            [LP.init(LP.remake(bp; p = [kw => k]), LP.ExplicitEuler(; dt = 1.0, substeps = 4)) for k in (0.5, 0.7, 0.9)]
        end
        @test warns(logs) == 1 && occursin("ExplicitEuler(substeps = 4): 4 substeps", string(logs[end].message))
        @test length(LFP._SEEN_WARNED) == n0 + 2
        # review r1 S2: the automatic count's refusal of the unseen term comes at `remake`, as before
        # F3-01 (743ab0a0); at 8f658abd `remake` returned and `init` refused (u1_a §4)
        err = try
            remake(probs[1]; field_solver = ExplicitEuler()); ""
        catch e
            sprint(showerror, e)
        end
        @test occursin("c^2", err) && occursin("substeps", err)
    end
end

# F3-02 (F2 design §2.2): the group's inputs are specs. A model's CPM inputs are filled (the
# model writes them on the device every MCS), another group's field read from its array is not.
@testitem "F3-02: InputSpec.filled: a model's CPM inputs are filled, another group's field is not" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-02: InputSpec.filled: a model's CPM inputs are filled, another group's field is not" begin
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.variables(sys)))
        prob = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2), solvers = [uvar => ExplicitEuler(substeps = 3)])
        phs = [ph for ph in prob.f.phases.after_mcs if ph isa CorePotts.FieldPhase]
        cin, uin = (ph.group.spec.inputs for ph in phs)
        @test all(i -> i isa Potts.LatticeFields.Problems.InputSpec, [cin; uin])
        @test !isempty(cin) && all(i -> i.filled, cin) && any(i -> occursin("kind", i.key), cin)   # `kind == A`
        @test [(i.key, i.filled) for i in uin] == [("c", false)]                                     # c's array
    end
end

# F3-03 (F3 design §3.7): `FieldGroups` is a model's `field_solver` too (its pairs as `solvers`
# entries of fields, its `default` the other fields' solver), so it resolves and fingerprints
# as the `solvers` spelling; both front ends print an algorithm by LatticeFields' one canonical
# text (`Problems.canonical`). Base (eb2efb60): `field_solver = FieldGroups(…)` was an
# ArgumentError ("`FieldGroups` in a `PottsProblem` is planned").
@testitem "F3-03: FieldGroups in a model; one canonical text" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-03: FieldGroups in a model; one canonical text" begin
        LFP, LP = Potts.LatticeFields.Problems, Potts.LatticePDE
        msg(f) = try
            f(); ""
        catch e
            e isa ArgumentError || rethrow()
            sprint(showerror, e)
        end
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        cvar = only(filter(x -> string(x) in ("c", "c(t)"), Potts.variables(sys)))
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.variables(sys)))
        fg = PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(uvar => ExplicitEuler(substeps = 3); default = ExplicitEuler(substeps = 2)))
        sp = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2), solvers = [uvar => ExplicitEuler(substeps = 3)])
        @test fg.f.fingerprint == sp.f.fingerprint
        s1, s2 = solve(fg, SequentialCPM()), solve(sp, SequentialCPM())
        @test s1.u[end].site.c == s2.u[end].site.c && s1.u[end].site.u == s2.u[end].site.u
        # no `default`: the others take the default solver; a name key works as in `solvers`
        nd = PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3)))
        @test nd.f.fingerprint == PottsProblem(sys, op, (0, 2); solvers = [uvar => ExplicitEuler(substeps = 3)]).f.fingerprint
        # control: another count is another fingerprint
        @test PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(uvar => ExplicitEuler(substeps = 4);
            default = ExplicitEuler(substeps = 2))).f.fingerprint != sp.f.fingerprint
        # refusals in the user's words: a field given twice, a key that is not a field
        e = msg(() -> PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(uvar => ExplicitEuler(substeps = 3)),
            solvers = [uvar => ExplicitEuler(substeps = 2)]))
        @test occursin("`u` is given twice (once in `field_solver = FieldGroups(…)`)", e)
        # at `remake` the problem's `solvers` are kept, and the clash says so with the route (review r1
        # nit); the route works
        e = msg(() -> remake(sp; field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3))))
        @test occursin("`u` is given twice (once in `field_solver = FieldGroups(…)`; `solvers` is kept from the problem: pass `solvers = []`)", e)
        @test remake(sp; field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3); default = ExplicitEuler(substeps = 2)),
            solvers = []).f.fingerprint == sp.f.fingerprint
        @test occursin("`FieldGroups`: `zz` is not a field", msg(() -> PottsProblem(sys, op, (0, 2);
            field_solver = FieldGroups(:zz => ExplicitEuler()))))
        @test occursin("give it as `field_solver = FieldGroups(", msg(() -> PottsProblem(sys, op, (0, 2);
            solvers = [cvar => FieldGroups(uvar => ExplicitEuler())])))
        # one canonical text: today's `ExplicitEuler` text byte for byte, through A's `_canonical`
        @test LFP.canonical(ExplicitEuler(substeps = 15, lower = 0.0)) == "ExplicitEuler(substeps=15,lower=0.0)" ==
              Potts._canonical(ExplicitEuler(substeps = 15, lower = 0.0))
        @test LFP.canonical(ExplicitEuler()) == "ExplicitEuler(substeps=nothing,lower=nothing)" &&
              LFP.canonical(ExplicitEuler(; dt = 0.5, substeps = 2)) == LFP.canonical(ExplicitEuler(substeps = 2))   # no dt
        @test LFP.canonical(ExplicitMap()) == "ExplicitMap()"
        S = Potts.LatticeFields.Solvers
        @test LFP.canonical(S.DevicePCG()) ==
              "DevicePCG(budget=8,precond=Multigrid(budget=nothing,cycle=V(2,2),cycles=nothing,rtol=1.0e-6,warn_tol=1.0e-6),rtol=1.0e-6)"
        @test LFP.canonical(S.Multigrid()) == "Multigrid(budget=nothing,cycle=V(2,2),cycles=nothing,rtol=1.0e-6,warn_tol=1.0e-6)"
        @test LFP.canonical(:auto) == ":auto"
        # the same objects: every algorithm LatticePDE exports is Potts' own
        algs = [n for n in names(LP) if (v = getfield(LP, n); v isa Type && v <: LFP.FieldAlgorithm)]
        @test Set(algs) ⊇ Set([:ExplicitEuler, :ExplicitMap, :FieldGroups])
        @test all(n -> isdefined(Potts, n) && Base.isexported(Potts, n) && getfield(Potts, n) === getfield(LP, n), algs)
    end
end

# F3-05 (F3 design §3.2): the solvers' inner algorithms are the same objects in both front ends
# (`LatticeFields.Solvers`, made public): `DevicePCG` and `Multigrid` exported, `V` public.
# Base (1079c4ff): neither Potts nor LatticePDE binds them (`UndefVarError: DevicePCG`).
@testitem "F3-05: the inner solvers in a model and in B" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-05: the inner solvers in a model and in B" begin
        S, LP = Potts.LatticeFields.Solvers, Potts.LatticePDE
        for n in (:DevicePCG, :Multigrid)
            @test getfield(Potts, n) === getfield(LP, n) === getfield(S, n)
            @test Base.isexported(Potts, n) && Base.isexported(LP, n) && Base.ispublic(S, n)
        end
        @test Potts.V === LP.V === S.V && Base.ispublic(Potts, :V) && Base.ispublic(LP, :V) && !Base.isexported(Potts, :V)
        for n in (:CellOperator, :FieldSolver, :steady!, :solve!, :rebuild!, :lift!, :tangent!, :set_coefficients!)
            @test Base.ispublic(S, n)
        end
        @test Potts.LatticeFields.Problems.canonical(DevicePCG(; precond = Multigrid(; cycle = Potts.V(3, 3)), budget = 12)) ==
              "DevicePCG(budget=12,precond=Multigrid(budget=nothing,cycle=V(3,3),cycles=nothing,rtol=1.0e-6,warn_tol=1.0e-6),rtol=1.0e-6)"
    end
end

# F3-05 review r1 M1: a linear solver given as A's `field_solver`, in `solvers` or in
# `FieldGroups` is refused in A's words (a linear solver, the `inner` of an implicit field
# solver) with a route that works when followed. Base (9db10886, ~/lpwork/f3b2r1-nc-a.log, 4 of 7 fail;
# the 3 that pass are the followed routes):
# "`field_solver` takes a field solver (…); got DevicePCG(Multigrid(LatticeFields.Solvers.V(2,
# 2), nothing, 1.0e-6, nothing, 1.0e-6), 8, 1.0e-6)", the same positional text for `solvers`,
# "is not a field algorithm" for `FieldGroups`, and a MethodError for `ExplicitEuler(; inner)`.
@testitem "F3-05: a linear solver where a model takes a field solver" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-05: a linear solver where a model takes a field solver" begin
        op = [fd_empty((16, 8)); :c => zeros(16, 8)]
        mk(; kw...) = PottsProblem(FdPeriodic(; name = :f), op, (0, 1); kw...)
        e(f) = try
            f(); ""
        catch err
            err isa ArgumentError ? err.msg : sprint(showerror, err)
        end
        lin = "is a linear solver: it is the `inner` of an implicit field solver, not a field solver"
        m = e(() -> mk(; field_solver = DevicePCG()))
        @test startswith(m, "`field_solver`: `DevicePCG()` " * lin) && occursin("give `field_solver = ExplicitEuler()`", m)
        @test solve(mk(; field_solver = ExplicitEuler()), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        m = e(() -> mk(; solvers = [:c => Multigrid()]))
        @test startswith(m, "`solvers`: the field `c`: `Multigrid()` " * lin) && occursin("give `solvers = [c => ExplicitEuler()]`", m)
        @test solve(mk(; solvers = [:c => ExplicitEuler()]), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        m = e(() -> mk(; field_solver = FieldGroups(:c => DevicePCG())))
        @test startswith(m, "FieldGroups: the field `c`: `DevicePCG()` " * lin) && occursin("give `c => ExplicitEuler(…)`", m)
        @test solve(mk(; field_solver = FieldGroups(:c => ExplicitEuler())), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        m = e(() -> ExplicitEuler(; inner = DevicePCG()))
        @test startswith(m, "ExplicitEuler: `inner = DevicePCG()`: `inner` is a keyword of the implicit field solvers") &&
              occursin("leave `inner` out", m)
    end
end

@testitem "F3-02: an aux-carried loop runs in a model (Jacobi in a group, the split across groups)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-02: an aux-carried loop runs in a model (Jacobi in a group, the split across groups)" begin
        σ = zeros(Int32, 6, 4)
        σ[2:3, 2:3] .= 1
        op = [ownership => σ, kind => [:A]]
        sys = FxLoop(; name = :x)
        cv = only(filter(x -> string(x) in ("c", "c(t)"), Potts.variables(sys)))
        s = solve(PottsProblem(sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        w, c = 1.0, 0.0
        for _ in 1:6
            w, c = w - 0.5 * c, c + 0.5 * w
        end
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success
        @test all(≈(w; rtol = 1e-14), s.u[end].site.w) && all(≈(c; rtol = 1e-14), s.u[end].site.c)
        s2 = solve(PottsProblem(sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 1), solvers = [cv => ExplicitEuler(substeps = 2)]),
            SequentialCPM())
        w, c = 1.0, 0.0
        for _ in 1:3
            w = w - c                                       # w's group: K = c, held over the MCS
            for _ in 1:2
                c = c + 0.5 * w                             # c's group reads the new w
            end
        end
        @test all(≈(w; rtol = 1e-14), s2.u[end].site.w) && all(≈(c; rtol = 1e-14), s2.u[end].site.c)
    end
end

@testitem "F3-04: a model reads the status word (host: after every window)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-04: a model reads the status word (host: after every window)" begin
        RC = Potts.SciMLBase.ReturnCode
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        prob(alg) = PottsProblem(sys, op, (0, 6); field_solver = alg)
        integ = init(prob(AStub(; code = 2, at = 3)), SequentialCPM())
        s = @test_logs (:warn, r"fields `c`, `u`: the solve failed in the field step of MCS 3 \(t = 2\.0\) \(the Newton iteration diverged\).*ConvergenceFailure") solve!(integ)
        @test s.retcode == RC.ConvergenceFailure && integ.t == 3 && integ.stats.fields.solves == 3
        @test s.t[end] == 3                                   # the state it stopped at is saved
        # `reinit!` starts a clean run (review r1 M2): the word, the totals, the code and the counters
        # are cleared; the stub fails at its 3rd step only, so the new run succeeds. Control: without
        # the clearing the word's failure is read again at the first window and the run stops at MCS 1
        reinit!(integ)
        @test integ.stats.fields.code == RC.Success && integ.stats.fields.solves == 0
        s = @test_logs solve!(integ)
        @test s.retcode == RC.Success && integ.t == 6 && integ.stats.fields.solves == 6
        @test startswith(repr(integ.stats.fields), "FieldStats(solves = 6, budget = 0, floor = 0, newton_budget = 0, code = ")
        # a rounding floor survives to the end
        s = solve(prob(AStub(; code = 1, at = 3)), SequentialCPM())
        @test s.retcode == RC.StalledSuccess && s.t[end] == 6
        # a budget count warns once with the route and stays `Success`; the route removes it
        integ = init(prob(AStub(; need = 10, budget = 8)), SequentialCPM())
        s = @test_logs (:warn, r"fields `c`, `u`: the linear solve reached its budget 1 time so far.*budget = n") solve!(integ)
        @test s.retcode == RC.Success && integ.stats.fields.budget == 6
        integ = init(prob(AStub(; need = 10, budget = 16)), SequentialCPM())
        s = @test_logs solve!(integ)
        @test s.retcode == RC.Success && integ.stats.fields.budget == 0 && integ.stats.fields.solves == 6
        # explicit groups read nothing: no counters; a warm MCS allocates nothing (above)
        integ = init(prob(ExplicitEuler(substeps = 2)), SequentialCPM(); save_start = false, save_end = false)
        step!(integ)
        @test (@allocated step!(integ)) == 0 && integ.stats.fields.solves == 0
    end
end

@testitem "F3-13 M1: Burgers in a model stays unseen (no frozen-velocity count)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-13 M1: Burgers in a model stays unseen (no frozen-velocity count)" begin
        c0 = [0.5 + 0.4 * sin(2π * (i - 0.5) / 32) for i in 1:32, j in 1:32]
        op = [ownership => zeros(Int32, 32, 32), kind => Symbol[], :c => c0]
        e = something(fd_err(() -> PottsProblem(FbBurgers(; name = :b), op, (0, 20); seed = 1, field_solver = ExplicitEuler())), "")
        @test occursin("Advect", e) && occursin("substeps", e)
        # (review r2 N1) the routes are a count or BackwardEuler; `bounds` cannot help this term
        @test occursin("velocity reads the field it moves", e) && occursin("BackwardEuler", e) && !occursin("`bounds", e)
        # the user's count (h = Δx/8, past the linearized limit Δx/4 at c ≡ 1): bounded, below 1
        pb = @test_logs (:warn, r"Advect") match_mode = :any PottsProblem(FbBurgers(; name = :b), op, (0, 20); seed = 1,
            field_solver = ExplicitEuler(; substeps = 8))
        s = solve(pb, SequentialCPM())
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success
        @test 0.1 - 1e-6 <= minimum(s.u[end].site.c) && maximum(s.u[end].site.c) <= 0.91
    end
end

@testitem "F3-13 M2: declared intervals after the build in a model" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-13 M2: declared intervals after the build in a model" begin
        RC = Potts.SciMLBase.ReturnCode
        dims = (16, 16)
        e = something(fd_err(() -> PottsProblem(FbDir3(; name = :f), fd_empty(dims), (0, 2))), "")
        @test occursin("field `c`: its condition on the face `x = 16.0` holds 3.0, outside the field's declared bounds (0.0, 1.0)", e)
        # the source drives c past 3 near MCS 3 (s = 1): `Unstable`, the run stops there, one warning
        pr = PottsProblem(FbDrift(; name = :f), fd_empty(dims), (0, 20))
        sol = @test_logs (:warn, r"field `c` left its declared bounds \(0\.0, 3\.0\): it holds .* by the end of the field step of MCS \d+") solve(pr,
            SequentialCPM())
        @test sol.retcode == RC.Unstable && sol.t[end] < 20 && maximum(sol.u[end].site.c) > 3
        # with a decay that keeps it inside (s = 0.1: steady 2): no warning, to the end
        sol = @test_logs solve(remake(pr; p = [:s => 0.1]), SequentialCPM())
        @test sol.retcode == RC.Success && sol.t[end] == 20
        # the check reads the field after each MCS on the host and allocates nothing there
        integ = init(remake(pr; p = [:s => 0.1]), SequentialCPM(); save_start = false, save_end = false)
        step!(integ); step!(integ)
        @test (@allocated step!(integ)) == 0
    end
end

@testitem "F3-13: the interval bound in a model (declared bounds, aux fields, coordinates, advection)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-13: the interval bound in a model (declared bounds, aux fields, coordinates, advection)" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        dims = (16, 16)
        Potts.ModelingToolkitBase.@parameters x y k = 2.0
        Potts.ModelingToolkitBase.@variables c(..) [bounds = (0.0, 1.0)] u(..) K(..)
        ce, ue, Ke = c(tt, x, y), u(tt, x, y), K(tt, x, y)
        dom = [tt ∈ LP.Interval(0.0, 2.0), x ∈ LP.Interval(0.0, 16.0), y ∈ LP.Interval(0.0, 16.0)]
        bcount(eqs, dvs, ps, ic) = (p = LP.discretize(MTKB.PDESystem(eqs, ic, dom, [tt, x, y], dvs, ps; name = :b),
            LP.LatticeDiscretization(LP.Grid(dims); T = Float64)); LP.Problems.substeps(LP.Problems.field_problem(p), LP.ExplicitEuler(; dt = 1.0)))
        acount(M; kw...) = substep_counts(init(PottsProblem(M(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler(), kw...),
            SequentialCPM()))
        # `DivKGrad(c, c)` with c ∈ (0, 1): ρ = 8 max K = 8, n = ⌈8/1.8⌉ = 5, as B
        @test acount(FbIvDivK) == [5] == [bcount([DD(ce) ~ LP.DivKGrad(:harmonic)(ce, ce)], [ce], Any[], [c(0, x, y) ~ 0.5])]
        # … and the run equals B's, bitwise (σ frozen: no cells)
        c0 = rand(StableRNG(13), dims...)
        a = Array(solve(PottsProblem(FbIvDivK(; name = :f), [fd_empty(dims); :c => c0], (0, 2); field_solver = ExplicitEuler()),
            SequentialCPM()).u[end].site.c)
        bp = LP.discretize(MTKB.PDESystem([DD(ce) ~ LP.DivKGrad(:harmonic)(ce, ce)], [c(0, x, y) ~ 0.5], dom, [tt, x, y], [ce], Any[];
            name = :b), LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
        @test a == LP.solve(LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; dt = 1.0))[:c, end]
        # no declared interval: the term stays one the bound cannot see (the count is refused)
        e = something(fd_err(() -> PottsProblem(FbIvNoBounds(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler())), "")
        @test occursin("DivKGrad", e) && occursin("cannot see", e)
        # a field that starts outside its bounds; `bounds` on a variable that is not a field
        e = something(fd_err(() -> PottsProblem(FbIvOut(; name = :f), fd_empty(dims), (0, 2); field_solver = ExplicitEuler())), "")
        @test occursin("field `c` starts at 1.5, outside its declared bounds (0, 1)", e)
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables s(Potts.t)), :site; bounds = (0, 1))), "")
        @test occursin("variable `s`: `bounds` applies to fields", e)
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables s(Potts.t)), :field; bounds = (1, 0))), "")
        @test occursin("`bounds` is a pair `(lo, hi)` of numbers with lo ≤ hi", e)
        # an aux field through its definition: ρ = 0.1 · 8 + k, n = ⌈2.8/1.8⌉ = 2 (base: refused)
        @test acount(FbIvAux) == [2] ==
              [bcount([Ke ~ k * ue, DD(ue) ~ 0.1 * LP.Δ(ue) - Ke], [ue, Ke], Any[k], [u(0, x, y) ~ 0.5])]
        # a velocity that varies by site: ρ = 0.8 + 2 max|0.05 (1 + x)| over x ∈ [−0.5, 16.5], n = 2
        @test acount(FbIvAdvect) == [2] ==
              [bcount([DD(ue) ~ 0.1 * LP.Δ(ue) - LP.Advect(LP.Upwind1())([0.05 * (1 + x), 0.0], ue)], [ue], Any[], [u(0, x, y) ~ 0.5])]
    end
end

@testitem "F3-14: lattice_storage, compute_T and solver_T in a model (FE-17)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-14: lattice_storage, compute_T and solver_T in a model (FE-17)" begin
        σ = zeros(Int32, 12, 10)
        σ[3:5, 3:5] .= 1
        σ[8:10, 6:8] .= 2
        c0 = rand(StableRNG(14), 12, 10)
        prob(T, alg) = PottsProblem(FwRoles(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0, :h => c0, :s => c0], (0, 3);
            T, seed = 3, field_solver = alg)
        run(T, alg; M = FwRoles) = (integ = init(M === FwRoles ? prob(T, alg) :
                                                 PottsProblem(FwWide(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0], (0, 3);
                                                     T, seed = 3, field_solver = alg), SequentialCPM());
                                    foreach(_ -> step!(integ), 1:3); integ)
        # the stores have the declared types, the undeclared field the state type
        for T in (Float32, Float64)
            st = current_state(run(T, ExplicitEuler(substeps = 8)))
            @test (eltype(st.site.c), eltype(st.site.h), eltype(st.site.s), eltype(st.site.u)) == (Float64, Float16, Float32, T)
            @test eltype(st.site.c__next) == Float64
        end
        # a Float32 CPM with a Float64 field computed in Float64 equals the Float64 reference to
        # 1e-12 (measured: 0, bitwise); computed in Float32 (the control) it does not (5.7e-8)
        for (a32, ref) in ((ExplicitEuler(substeps = 8, compute_T = Float64), ExplicitEuler(substeps = 8)),
                           (BackwardEuler(compute_T = Float64), BackwardEuler()))
            a, b = run(Float32, a32; M = FwWide), run(Float64, ref; M = FwWide)
            @test maximum(abs, current_state(a).site.c .- current_state(b).site.c) < 1e-12
        end
        ctl = maximum(abs, current_state(run(Float32, ExplicitEuler(substeps = 8); M = FwWide)).site.c .-
                           current_state(run(Float64, ExplicitEuler(substeps = 8); M = FwWide)).site.c)
        @test ctl > 1e-9
        # solver_T from A: the implicit solver's own type
        integ = init(PottsProblem(FwWide(; name = :w), [ownership => σ, kind => [:A, :A], :c => c0], (0, 3); T = Float32,
            field_solver = BackwardEuler(solver_T = Float64)), SequentialCPM())
        rows = CorePotts._runtime(getfield(integ.ctx, :__fields1)).cache.rows
        @test all(r -> r.solver === nothing || r.solver.T == Float64, rows) && any(r -> r.solver !== nothing, rows)
        # refusals in the user's words
        e = something(fd_err(() -> Potts.variable(only(Potts.Symbolics.@variables q(Potts.t)), :field; lattice_storage = BigFloat)), "")
        @test occursin("`lattice_storage` applies to fields and is `Float16`, `Float32` or `Float64`", e) && occursin("got BigFloat", e)
        e = something(fd_err(() -> ExplicitEuler(compute_T = Float16)), "")
        @test occursin("`compute_T` takes `:auto`", e)
    end
end

@testitem "batch-end review S4: compute_T = Float64 reaches a Float32 model's field kernels" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "batch-end review S4: compute_T = Float64 reaches a Float32 model's field kernels" begin
        run1(T, alg) = (integ = init(PottsProblem(FwNarrow(; name = :w), fd_empty((12, 10)), (0, 1); T, seed = 3, field_solver = alg),
                            SequentialCPM()); step!(integ); Array(integ.u.site.c))
        wide, narrow = run1(Float32, ExplicitEuler(; substeps = 1, compute_T = Float64)), run1(Float32, ExplicitEuler(; substeps = 1))
        ref = run1(Float64, ExplicitEuler(; substeps = 1))
        @test eltype(wide) === eltype(narrow) === Float32
        @test maximum(abs, wide .- ref) < 1e-12 && maximum(abs, narrow .- ref) > 1e-8 ||
              (println("S4: ", maximum(abs, wide .- ref), " ", maximum(abs, narrow .- ref)); false)
    end
end

@testitem "F3-14 S1, S4 in a model: Float16 under the implicit algorithms; Dual parameters in words" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F3-14 S1, S4 in a model: Float16 under the implicit algorithms; Dual parameters in words" begin
        dims = (16, 16)
        for fs in (BackwardEuler(), BackwardEuler(; compute_T = Float64), CrankNicolson(), BDF2(), QuasiSteady())
            a = solve(PottsProblem(FbHalf(; name = :h), fd_empty(dims), (0, 10); field_solver = fs, T = Float32), SequentialCPM())
            b = solve(PottsProblem(FbFull(; name = :f), fd_empty(dims), (0, 10); field_solver = fs), SequentialCPM())
            ca, cb = a.u[end].site.c, b.u[end].site.c
            @test a.retcode == Potts.SciMLBase.ReturnCode.Success && eltype(ca) == Float16
            @test maximum(abs, Float64.(ca) .- cb) <= 4e-3 * maximum(abs, cb)
        end
        # (F3-21b: the Dual runs; its field carries derivative parts, its values are the primal run's)
        pf = PottsProblem(FbFull(; name = :f), fd_empty(dims), (0, 2))
        d = solve(remake(pf; p = [:k => ForwardDiff.Dual(0.05, 1.0)]), SequentialCPM()).u[end].site.c
        @test ForwardDiff.value.(d) == solve(pf, SequentialCPM()).u[end].site.c && all(<(0), ForwardDiff.partials.(d, 1))
        # an integrator write still takes plain numbers, refused in words (the value type, not the type)
        e = something(fd_err(() -> (integ = init(pf, SequentialCPM()); integ.ps[:k] = ForwardDiff.Dual(0.05, 1.0))), "")
        @test occursin("parameter `k` = a ForwardDiff `Dual` of Float64 (value 0.05) does not convert", e) &&
              occursin("A Dual goes to the problem", e) && !occursin("Tag", e) && length(e) < 1200
    end
end
