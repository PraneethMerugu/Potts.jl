# Field substep bounds, coupled PDE rates and parameter reactivity regressions (A-64, F1/F2 bounds).

@testitem "A-64 field substeps follow the current parameters" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-64 field substeps follow the current parameters" begin
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1
        c0 = zeros(16, 16); c0[8, 8] = 100.0
        p = PottsProblem(AuditField16(; name = :d, mode = :diffusion), [ownership => σ, kind => [1], :c => c0], (0, 10); field_solver = ExplicitEuler())
        q = remake(p; p = [:Dc => 5.0])
        fresh = PottsProblem(
            AuditField16(; name = :d, mode = :diffusion), [ownership => σ, kind => [1], :c => c0, :Dc => 5.0], (0, 10);
            field_solver = ExplicitEuler()
        )
        uq = solve(q, SequentialCPM()).u[end].site.c
        @test uq ≈ solve(fresh, SequentialCPM()).u[end].site.c
        @test maximum(abs, uq) < 100
    end
end

@testitem "a reaction nonlinear in the field has no substep bound: the count is the user's" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a reaction nonlinear in the field has no substep bound: the count is the user's" begin
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [1]]
        err = try
            PottsProblem(AuditField16(; name = :n, mode = :nonlinear), op, (0, 1); field_solver = ExplicitEuler())
        catch e
            e
        end
        @test err isa ArgumentError && occursin("no bound from the parameters", err.msg) && occursin("substeps = n", err.msg)
        @test occursin("^2", err.msg)                                       # the term is named
        # an explicit count is kept (at least the bound of the diffusion, 0.1·8/1.8 → 1), with one
        # warning naming the term the bound does not cover
        # (in the model's words: the term, not the key-prefixed `c: …` of round 0)
        prob = @test_logs (:warn, r"field `c`: 4 substeps.*does not cover `(?!c: )[^`]*c\^2[^`]*`") PottsProblem(
            AuditField16(; name = :n, mode = :nonlinear), op, (0, 1); field_solver = ExplicitEuler(substeps = 4)
        )
        @test audit_n(init(prob, SequentialCPM())) == 4
    end
end

@testitem "a kind table in a rate: the bound reads it; an explicit count is a minimum" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind table in a rate: the bound reads it; an explicit count is a minimum" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:16, j in 1:16]
        op = [ownership => zeros(Int32, 16, 16), kind => Symbol[], :c => cb]
        m = AuditTableField(; name = :b, mode = :bounded, d0 = 5.0, d1 = 0.0)
        prob = PottsProblem(m, op, (0, 30); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 8                  # (round 5: refused, "no bound")
        prob1 = @test_logs PottsProblem(m, op, (0, 30); field_solver = ExplicitEuler(substeps = 1))
        @test audit_n(init(prob1, SequentialCPM())) == 8                 # raised (round 5: 5, the diffusion only)
        c = Array(solve(prob1, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(abs, c) < 1.0e-3               # stable at 8 (13 · 1/8 ≤ 2)
        # control: a request above the bound is kept
        @test audit_n(
            init(
                PottsProblem(m, op, (0, 1); field_solver = ExplicitEuler(substeps = 9)),
                SequentialCPM()
            )
        ) == 9
    end
end

@testitem "a kind-table diffusion multiplier is bounded; a CPM value read directly is refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind-table diffusion multiplier is bounded; a CPM value read directly is refused" begin
        σ = zeros(Int32, 16, 16); σ[4:6, 4:6] .= 1
        op = [ownership => σ, kind => [:A]]
        cb = [iseven(i + j) ? 1.0 : 0.0 for i in 1:16, j in 1:16]
        prob = PottsProblem(
            AuditTableField(; name = :k, mode = :kind_diff, d0 = 0.1, d1 = 2.0),
            [op; :c => cb], (0, 5); field_solver = ExplicitEuler()
        )
        @test audit_n(init(prob, SequentialCPM())) == 9
        c = Array(solve(prob, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(c) <= 1 + 1.0e-12 && minimum(c) >= -1.0e-12     # a monotone step at n = 9
        err = audit_err(() -> PottsProblem(AuditVolumeDiffusion(; name = :k), op, (0, 1); field_solver = ExplicitEuler()))
        @test err isa ArgumentError && occursin("varies by site", err.msg) && occursin("volume[owner]", err.msg) &&
            !occursin("LatticePDE.", err.msg) && !occursin("at(volume", err.msg)
        err = audit_err(
            () -> PottsProblem(
                AuditTableField(; name = :k, mode = :mcs_diff, d0 = 0.1, d1 = 0.2),
                op, (0, 1); field_solver = ExplicitEuler()
            )
        )
        @test err isa ArgumentError && occursin("δ[kind]", err.msg) && occursin("mcs", err.msg) &&
            !occursin("at(δ", err.msg) && !occursin("(1 + t)", err.msg)
    end
end

@testitem "a kind table under `1 / …`: every kind's entry, never index 0; a zero entry is named" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind table under `1 / …`: every kind's entry, never index 0; a zero entry is named" begin
        op = [ownership => zeros(Int32, 16, 16), kind => Symbol[]]
        prob = PottsProblem(AuditInvTable(; name = :v), op, (0, 1); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 2
        for fs in (ExplicitEuler(), ExplicitEuler(substeps = 3)), τ in ([0.0, 0.5], [2.0, 0.0])
            err = audit_err(() -> PottsProblem(AuditInvTable(; name = :v), [op; :τ => τ], (0, 1); field_solver = fs))
            @test err isa ArgumentError && occursin("make it nonzero", err.msg) && occursin("`τ`", err.msg)
            @test occursin(τ[1] == 0 ? "the medium's entry of `τ` (kind 0)" : "the entry of kind 1 of `τ`", err.msg)
            @test !occursin("index 0", err.msg) && !occursin("LatticePDE.", err.msg) && !occursin("__in", err.msg)
        end
        # over the evaluation cap (a 5000-entry table): an explicit count runs as given, and no
        # count is refused with the route
        p3 = PottsProblem(AuditInvTable(; name = :v), op, (0, 1); field_solver = ExplicitEuler(substeps = 3))
        big(prob) = (
            ph = audit_phase(prob);
            (
                ph.substeps, CorePotts.Problems.with_tables(
                    Float64[getproperty(prob.p, n) for n in ph.params],
                    Pair{String, Vector{Float64}}[ph.program.tables[i].key => fill(1.0, 5000) for (i, _) in ph.tables]
                ),
            )
        )
        s3, b3 = big(p3)
        # warned once per group, term and cause; the warning has no error route (F2 record (c):
        # bda31989 printed "with no count, give `PottsProblem` `field_solver = …`" inside it)
        logs, n3 = Test.collect_test_logs(() -> s3(b3))
        @test n3 == 3 && length(logs) == 1 && occursin(r"3 substeps.*does not cover.*4096", string(logs[1].message))
        @test !occursin("with no count", string(logs[1].message))
        # … raised by the bound over the terms it sees (round 9: Dc = 4.5 with 3 stayed at 3 past
        # the cap, against 22 with the 2-entry table; now 4.5·8/1.8 = 20; the group has warned)
        p45 = PottsProblem(AuditInvTable(; name = :v), [op; :Dc => 4.5], (0, 1); field_solver = ExplicitEuler(substeps = 3))
        @test audit_n(init(p45, SequentialCPM())) == 22                                    # control: 2 entries
        s45, b45 = big(p45)
        @test (@test_logs s45(b45)) == 20
        s0, b0 = big(prob)
        err = audit_err(() -> s0(b0))
        @test err isa ArgumentError && occursin("4096", err.msg) && occursin("substeps = n", err.msg)
    end
end

@testitem "÷ of parameters in a field rate has no bound: refused without a count" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "÷ of parameters in a field rate has no bound: refused without a count" begin
        op = [ownership => zeros(Int32, 16), kind => Symbol[], :c => [isodd(i) ? 1.0 : -1.0 for i in 1:16]]
        err = audit_err(() -> PottsProblem(AuditIntDivField(; name = :b), op, (0, 30); field_solver = ExplicitEuler()))
        # the term is printed in the model's words (F1, PO06: on f9a77dd3 the message printed the
        # key prefix and the internal `Potts._intdiv(k₀, 2)`)
        @test err isa ArgumentError && occursin("no bound from the parameters", err.msg) && occursin("k₀ ÷ 2", err.msg) &&
            !occursin("_intdiv", err.msg) && !occursin("`c: ", err.msg)
        # with a count: kept as a minimum over the diffusion bound (0.25·4 / 1.8 → 1)
        prob = @test_logs (:warn, r"does not cover") PottsProblem(
            AuditIntDivField(; name = :b), op, (0, 30);
            field_solver = ExplicitEuler(substeps = 3)
        )
        @test audit_n(init(prob, SequentialCPM())) == 3
    end
end

@testitem "an ifelse gate is bounded arm by arm: a gated rotation is refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "an ifelse gate is bounded arm by arm: a gated rotation is refused" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:8, j in 1:8]
        op = [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb, :u => copy(cb)]
        err = audit_err(
            () -> PottsProblem(
                AuditField8(; name = :r, mode = :gate_rotation), op, (0, 30);
                field_solver = ExplicitEuler()
            )
        )
        @test err isa ArgumentError && occursin("coupled rate", err.msg)
        # control: both arms diagonally dominant: accepted with the worst arm's bound, ceil(11 / 1.8)
        prob = PottsProblem(AuditField8(; name = :d, mode = :gate_dominant), op, (0, 30); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 7
        @test maximum(abs, Array(solve(prob, SequentialCPM()).u[end].site.c)) < 1.0e-3
    end
end

@testitem "coupled fields: no automatic count (never silently one substep); negative diffusion refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "coupled fields: no automatic count (never silently one substep); negative diffusion refused" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:8, j in 1:8]
        op = [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb, :u => copy(cb)]
        # control: the field alone gets its bound, ceil(0.5·8 / 1.8) = 3, and decays
        one = PottsProblem(
            AuditField8(; name = :o, mode = :field1), [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb],
            (0, 30); field_solver = ExplicitEuler()
        )
        @test audit_n(init(one, SequentialCPM())) == 3
        @test maximum(abs, Array(solve(one, SequentialCPM()).u[end].site.c)) < 1.0e-3
        # one way (`u` does not read `c`): block triangular, so the Gershgorin bound with no dominance
        # test (F3-22 review r1, D-C7a item 2 amended; base 9afaac05: refused), ceil((0.5·8 + 0.5·8) / 1.8)
        # and ceil((0.5·8 + 0.5) / 1.8)
        for (mode, n) in ((:cross_field, 5), (:cross_linear, 3))
            prob = @test_logs min_level = Base.CoreLogging.Warn PottsProblem(
                AuditField8(; name = :x, mode), op, (0, 30);
                field_solver = ExplicitEuler()
            )
            @test audit_n(init(prob, SequentialCPM())) == n
            @test maximum(abs, Array(solve(prob, SequentialCPM()).u[end].site.c)) < 1.0e-3
        end
        # a loop: refused without a count
        err = audit_err(
            () -> PottsProblem(
                AuditField8(; name = :x, mode = :cross_loop), op, (0, 30);
                field_solver = ExplicitEuler()
            )
        )
        @test err isa ArgumentError && occursin("coupled rates of `c`, `u`", err.msg) && occursin("substeps = n", err.msg) &&
            occursin("`field_solver = BackwardEuler()`", err.msg)
        # an explicit count: at least the Gershgorin bound of the coupled row, ceil((0.5·8 + 0.5·8) / 1.8) = 5
        prob = @test_logs (:warn, r"coupled rates of `c`") PottsProblem(
            AuditField8(; name = :x, mode = :cross_loop), op, (0, 30);
            field_solver = ExplicitEuler(substeps = 1)
        )
        @test audit_n(init(prob, SequentialCPM())) == 5
        c = Array(solve(prob, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(abs, c) < 1.0e-3
        # negative diffusion: refused with and without a count, also after a parameter change
        for fs in (ExplicitEuler(), ExplicitEuler(substeps = 20))
            err = audit_err(
                () -> PottsProblem(
                    AuditField8(; name = :o, mode = :field1),
                    [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb, :Dc => -0.1], (0, 1); field_solver = fs
                )
            )
            @test err isa ArgumentError && occursin("negative", err.msg) && occursin("`c`", err.msg)
            @test occursin("coefficient ≥ 0", err.msg)                  # the route (round 0: none)
        end
        # after a parameter change: refused by the write itself, which changes nothing (F2-08a)
        @test audit_err(() -> remake(one; p = [:Dc => -0.1])) isa ArgumentError
        integ = init(one, SequentialCPM())
        p0 = integ.p
        @test audit_err(() -> setp(integ, :Dc)(integ, -0.1)) isa ArgumentError
        @test integ.p === p0
        step!(integ)
        @test integ.t == 1
    end
end
