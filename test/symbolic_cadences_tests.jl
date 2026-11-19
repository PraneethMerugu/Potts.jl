# Split from test/symbolic_tests.jl

@testitem "replacement is by target; a changed cadence warns (D-045)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "replacement is by target; a changed cadence warns (D-045)" begin
        @potts_model CadenceBase begin
            @kinds medium A
            @variables n(model) = 0.0
            @lattice Lattice((8, 8))
            @after_mcs n += 1
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CadenceExt begin
            @extend n = base = CadenceBase()
            @kinds medium A
            @after_mcs Every(5) n ~ 0.0             # replaces the base's update despite the cadence (D-045)
        end

        σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
        sys = @test_logs (:warn, r"replaces the base's Every\(1\)") CadenceExt(; name = :c)
        @test solve(PottsProblem(sys, [ownership => σ, kind => [1]], (0, 4)), SequentialCPM()).u[end].model.n[1] == 0
    end
end


@testitem "P6.0f per-rule cadence: counts against the oracle (square, hex, 3D; sequential, checkerboard)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: counts against the oracle (square, hex, 3D; sequential, checkerboard)" begin
        for (label, sys_of, dims, prop) in (
                ("square", (na, nb) -> RuleCadences(; name = :rc, na, nb), (48, 32), Moore(1)),
                ("hex", (na, nb) -> RuleCadences(; name = :rc, na, nb, geometry = Hexagonal(), near = Hex(1)), (48, 32), Hex(1)),
                ("3D", (na, nb) -> RuleCadences(; name = :rc, na, nb, dims = (32, 14, 14)), (32, 14, 14), Moore(1)),
            )
            σ, kinds = rule_cadence_state(dims)
            for (na, nb) in ((2, 3), (2, 4), (3, 3), (1, 1))
                prob = PottsProblem(sys_of(na, nb), [ownership => σ, kind => kinds], (0, 6); capacity = 128)
                # the whole-lifecycle cadence: the gcd, so a shared cadence skips the pass entirely
                @test prob.f.lifecycle.every == gcd(na, nb)
                for alg in (SequentialCPM(; proposal = prop), CheckerboardCPM(; proposal = prop)), N in (1, 3, 5)
                    @test live_kinds(solve(remake(prob; tspan = (0, N)), alg).u[end]) == (cadence_oracle(na, N), cadence_oracle(nb, N))
                end
            end
        end
    end
end


@testitem "P6.0f per-rule cadence: generated gates" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: generated gates" begin
        # Every(1) and a shared cadence generate no modulo gate (zero cost when unused)
        @test !_has_any_modulo_gate(_trigger_ast(RuleCadences(; name = :rc)))
        @test !_has_any_modulo_gate(_trigger_ast(RuleCadences(; name = :rc, na = 3, nb = 3)))
        # mixed: gcd pass, gates only on the rules whose cadence is not the gcd
        c = _trigger_ast(RuleCadences(; name = :rc, na = 2, nb = 3))
        @test _has_modulo_gate(c, 2) && _has_modulo_gate(c, 3)
        c = _trigger_ast(RuleCadences(; name = :rc, na = 2, nb = 4))
        @test !_has_modulo_gate(c, 2) && _has_modulo_gate(c, 4)
    end
end


@testitem "P6.0f per-rule cadence: API, errors" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: API, errors" begin
        @potts_model LinkCadence begin
            @kinds medium A
            @relationship bond(cell, cell) capacity = 1
            @lattice Lattice((8, 8))
            @link bond Every(7) when = new_contact(a, b)
            @sweep Metropolis(; temperature = 1.0)
        end

        V = Potts.B.volume
        dom = Potts.cells(1)
        @test Potts.divide(dom; when = V >= 4).every == 1
        @test Potts.divide(dom, Potts.Every(3); when = V >= 4).every == 3
        @test Potts.divide(dom; when = V >= 4, every = 3).every == 3                  # keyword form, as @link
        @test Potts.divide(dom, Potts.B.volume => 1.0, Potts.Every(3); when = V >= 4).every == 3   # anywhere
        @test_throws ArgumentError Potts.divide(dom, Potts.Every(2), Potts.Every(3); when = V >= 4)
        @test_throws ArgumentError Potts.divide(dom, Potts.Every(2); when = V >= 4, every = 2)
        @test_throws ArgumentError Potts.divide(dom, 3; when = V >= 4)
        @test_throws ArgumentError Potts.divide(dom; when = V >= 4, every = 0)
        @test_throws ArgumentError Potts.divide(dom; when = V >= 4, every = 2.0)
        @test_throws ArgumentError Potts.link_rule(:link, Potts.RelationshipRef(:bond); when = true, every = 2.0)
        @test occursin(
            "divide  cells(1) Every(3) when", sprint(
                show, MIME"text/plain"(), Potts.PottsSystem(;
                    name = :x, kinds = [:medium, :ka],
                    lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
                    divisions = [Potts.divide(dom, Potts.Every(3); when = V >= 4)]
                )
            )
        )
        # the macro passes a cadence through to @link as well (it used to be dropped silently)
        rel = Potts.RelationshipRef(:bond)
        @test Potts.link_rule(:link, rel, Potts.Every(4); when = true).every == 4
        @test Potts.link_rule(:link, rel; when = true, every = 4).every == 4
        @test_throws ArgumentError Potts.link_rule(:link, rel, 3; when = true)
        @test only(Potts._p(LinkCadence(; name = :l), :link_rules)).every == 7
        # a division's description names a non-default cadence (errors located at the rule)
        @test Potts._describe(Potts.divide(dom, Potts.Every(3); when = V >= 4)) == "@divide cells(1) Every(3) when = volume >= 4"
        @test Potts._describe(Potts.divide(dom; when = V >= 4)) == "@divide cells(1) when = volume >= 4"
    end
end


@testitem "P6.0f per-rule cadence: only the firing rule writes the daughters' state" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: only the firing rule writes the daughters' state" begin
        σ = zeros(Int32, 48, 32); σ[2:13, 2:13] .= 1
        function run(sys, tspan; alg = SequentialCPM())
            u = solve(PottsProblem(sys, [ownership => σ, kind => [:ka]], tspan; capacity = 32), alg).u[end]
            live = findall(>(0), Array(u.cell.volume))
            return length(live), unique(Array(u.cell.x)[live])
        end
        sys = SameKindCadences(; name = :s)
        @test PottsProblem(sys, [ownership => σ, kind => [:ka]], (0, 1)).f.lifecycle.rules === Val(true)
        for alg in (SequentialCPM(), CheckerboardCPM())
            # MCS 0: both are checked and met; the first (Every(2), x = 1) wins
            @test run(sys, (0, 1); alg) == (2, [1.0])
            # MCS 2: only Every(2) is checked
            @test run(sys, (0, 3); alg) == (4, [1.0])
            # MCS 3: only Every(3) is checked, so its state 2 (absolute MCS numbers: 3 % 3 == 0)
            @test run(sys, (0, 4); alg) == (8, [2.0])
            @test run(sys, (3, 4); alg) == (2, [2.0])
            @test run(sys, (3, 5); alg) == (4, [1.0])                               # then MCS 4: Every(2)
        end
        # the review's case: a never-firing rule for the same kind must not write the state
        @test run(SameKindCadences(; name = :s, na = 1, nb = 2, wb = 10^9), (0, 1)) == (2, [1.0])
        @test run(SameKindCadences(; name = :s, na = 1, nb = 1, wb = 10^9), (0, 2)) == (4, [1.0])
        # rule order: both fire for every cell; the first wins (one division, its state)
        @test run(SameKindCadences(; name = :s, na = 1, nb = 1), (0, 2)) == (4, [1.0])
        @test run(SameKindCadences(; name = :s, na = 1, nb = 1, xa = 2.0, xb = 1.0), (0, 2)) == (4, [2.0])
        @test run(SameKindCadences(; name = :s, na = 1, nb = 1, wa = 10^9), (0, 2)) == (4, [2.0])  # a unmet: b
    end
end


@testitem "P6.0f per-rule cadence: disjoint rules generate plain events" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: disjoint rules generate plain events" begin
        sys = RuleCadences(; name = :rc, na = 2, nb = 3)
        t = _trigger_ast(sys)
        @test !_has_ruled_event(t) && !_has_true_and(t)
        σ, kinds = rule_cadence_state((48, 32))
        lc = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 1)).f.lifecycle
        @test lc.rules === Val(false)
        # the state rules take no rule index
        @test !_has_ruled_divide(sys)
        same = SameKindCadences(; name = :s)
        @test _has_ruled_event(_trigger_ast(same)) && _has_ruled_divide(same)
    end
end


@testitem "P6.0f per-rule cadence: absolute MCS after remake" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: absolute MCS after remake" begin
        σ, kinds = rule_cadence_state((48, 32))
        prob = PottsProblem(RuleCadences(; name = :rc, na = 2, nb = 3), [ownership => σ, kind => kinds], (0, 1); capacity = 128)
        oracle(n, t0, t1) = 2^count(m -> m % n == 0, t0:(t1 - 1))
        for (t0, t1) in ((3, 7), (1, 2), (5, 9))
            @test live_kinds(solve(remake(prob; tspan = (t0, t1)), SequentialCPM()).u[end]) == (oracle(2, t0, t1), oracle(3, t0, t1))
        end
    end
end


@testitem "P6.0f per-rule cadence: cluster rules" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: cluster rules" begin
        σ, kinds, groups = compartment_state()
        prob = PottsProblem(ClusterCadences(; name = :cc), [ownership => σ, kind => kinds, cluster => groups], (0, 1); capacity = 128)
        @test prob.f.lifecycle.every == 1 && prob.f.lifecycle.rules === Val(true)
        c = _trigger_ast(ClusterCadences(; name = :cc))
        @test _has_modulo_gate(c, 2) && _has_modulo_gate(c, 3)
        function run(tspan)
            u = solve(remake(prob; tspan), SequentialCPM(; proposal = Moore(1))).u[end]
            live = findall(>(0), Array(u.cell.volume))
            return length(unique(Array(u.cell.cluster)[live])), length(live), unique(Array(u.cell.mass)[live])
        end
        @test run((0, 1)) == (18, 36, [3.0])       # MCS 0: both checked, the first (Every(3)) wins
        @test run((0, 2)) == (18, 36, [3.0])       # MCS 1: neither
        @test run((0, 3))[[1, 3]] == (36, [5.0])   # MCS 2: Every(2) alone (a small nucleus may miss the plane)
        @test run((3, 4)) == (18, 36, [3.0])       # MCS 3: Every(3) alone
    end
end


@testitem "P6.0f per-rule cadence: extend accumulates division rules and warns on a new cadence" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence: extend accumulates division rules and warns on a new cadence" begin
        @potts_model CadenceDivBase begin
            @kinds medium ka kb
            @lattice Lattice((16, 16))
            @energy cells => (volume - 64.0)^2
            @divide cells(ka) Every(2) when = volume >= 4 + rand()
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CadenceDivOther begin
            @kinds medium ka kb
            @lattice Lattice((16, 16))
            @energy cells => (volume - 64.0)^2
            @divide cells(ka) Every(3) when = volume >= 8 + rand()
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CadenceDivExt begin
            @structural_parameters case = :new_cadence
            @extend base = CadenceDivBase()
            @kinds medium ka kb
            if case === :new_cadence
                @divide cells(ka) Every(3) when = volume >= 8 + rand()
            elseif case === :same_cadence
                @divide cells(ka) Every(2) when = volume >= 8
            else
                @divide cells(kb) Every(5) when = volume >= 8
            end
        end

        sys = @test_logs (:warn, r"@divide cells\(1\) Every\(3\).*adds to the base's @divide cells\(1\) Every\(2\)") CadenceDivExt(; name = :e, case = :new_cadence)
        @test [d.every for d in Potts._p(sys, :divisions)] == [2, 3]                  # both rules stay, each with its cadence
        # two separately built models: extend renumbers the draws of `sys` and keeps its cadences
        other = @test_logs (:warn, r"adds to the base's") extend(
            CadenceDivOther(; name = :o), CadenceDivBase(; name = :b)
        )
        @test [d.every for d in Potts._p(other, :divisions)] == [2, 3]
        @test !isequal(Potts._p(other, :divisions)[2].when, Potts._p(CadenceDivOther(; name = :o), :divisions)[1].when)   # renumbered
        @test_logs CadenceDivExt(; name = :e, case = :same_cadence)                   # same cadence: silent
        @test_logs CadenceDivExt(; name = :e, case = :other_kind)                     # other kinds: silent
    end
end


@testitem "P6.0f per-rule cadence survives @components" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0f per-rule cadence survives @components" begin
        @potts_model CadenceComponents begin
            @kinds medium A
            @components cells(A) clock = clock
            @lattice Lattice((20, 20))
            @energy cells => (volume - 25.0)^2
            @divide cells(A) Every(4) when = clock.m_c >= 1, along = (1.0, 0.0), clock.m_c => 0.0
            @sweep Metropolis(; temperature = 1.0)
        end

        @test only(getfield(mtkcompile(CadenceComponents(; name = :cc)), :divisions)).every == 4
    end
end


@testitem "P6.0v3: a cell update fuses with the lifecycle trigger only when legal" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0v3: a cell update fuses with the lifecycle trigger only when legal" begin
        @potts_model P60v3Fuse begin
            @structural_parameters own_only = true
            @kinds medium A
            @variables g(cell) = 0.0
            @lattice Lattice((24, 24))
            @energy cells => (volume - 16.0)^2
            @after_mcs g ~ g + 1.0
            if own_only
                @divide cells(A) when = g >= 3.0, along = RandomPlane(), g => 0.0
            else
                @divide cells(A) when = g[3 - id] >= 3.0, along = RandomPlane(), g => 0.0
            end
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model P60v3FuseNotLast begin
            @kinds medium A
            @parameters k = 0.1
            @variables begin
                g(cell) = 0.0
                y(cell) = 1.0
            end
            @lattice Lattice((24, 24))
            @energy cells => (volume - 16.0)^2
            @after_mcs g ~ g + 1.0
            @equations D(y) ~ -k * y
            @divide cells(A) when = g >= 3.0, along = RandomPlane(), g => 0.0
            @sweep Metropolis(; temperature = 1.0)
        end

        R(ex, w...) = Potts._reads_own_only(ex, Set{Symbol}(w))
        @test R(:(st.cell.g[c] >= 3), :g)
        @test R(:(@inbounds(st.cell.g[c]) >= 3), :g)
        @test R(:(Potts._cellval(st.cell.g, c) >= 3), :g)
        @test R(:(st.cell.volume[d] > 0 && st.ownership[1] == 0 && p.a * st.model.m[1] > 0), :g)   # unwritten values: any
        @test R(:(Potts._cellkind(st, c) == 1), :g)
        @test R(:(CorePotts.centroid(st.cell, c)), :g)
        # negative controls: another cell's value, the whole column, cell or state
        @test !R(:(st.cell.g[3 - c] >= 3), :g)
        @test !R(:(Potts._cellval(st.cell.g, d) >= 3), :g)
        @test !R(:(sum(st.cell.g)), :g)
        @test !R(:(f(st.cell, c)), :g)
        @test !R(:(f(st)), :g)
        @test !R(:(Potts._cellkind(st, c) == 1), :kind)
        @test !R(:(CorePotts.centroid(st.cell, c)), :m1)
        σ = zeros(Int32, 24, 24); σ[3:6, 3:6] .= 1; σ[15:18, 15:18] .= 2
        op = [ownership => σ, kind => [:A, :A]]
        cellphases(prob) = count(ph -> ph isa CorePotts.CellPhase, prob.f.phases.after_mcs)
        own = PottsProblem(P60v3Fuse(; name = :f, own_only = true), op, (0, 8); capacity = 16)
        @test own.f.lifecycle.before !== nothing && cellphases(own) == 0
        for sys in (P60v3Fuse(; name = :f, own_only = false), P60v3FuseNotLast(; name = :f))
            prob = PottsProblem(sys, op, (0, 8); capacity = 16)
            @test prob.f.lifecycle.before === nothing
            @test cellphases(prob) >= 1
        end
        # same results: the update still runs every MCS before the trigger (g = 0, 1, 2 → 3:
        # every live cell divides at MCS 2, 6, …)
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(own, alg; saveat = 1)
            @test sol.stats.lifecycle.divisions == 2 + 4
            @test sol.u[4].cell.g[1:4] == zeros(4)
        end
    end
end
