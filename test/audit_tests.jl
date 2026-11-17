# Regression tests for docs/design/AUDIT.md findings (IDs A-xx) and decisions D-041..D-045.
# Uses `selfcheck` and `proposal_states` from SymbolicSetup.

@testitem "D-041/D-042 update semantics and population folds" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "D-041/D-042 update semantics and population folds" begin
        σ = audit_blocks()
        op = [ownership => σ, kind => fill(1, 16)]
        # A-62: a fold in a cell update reads previous values, once per stage
        u = solve(PottsProblem(AuditPopCell(; name = :a), op, (0, 1)), SequentialCPM()).u[end]
        @test all(==(16.0), u.cell.q[1:16])
        # A-63: Pre is the value before the block in every scope; bare reads are new values
        u = solve(PottsProblem(AuditJacobi(; name = :j), op, (0, 1)), SequentialCPM()).u[end]
        @test u.model.m[1] == 1 && u.cell.ca[1] == 0 && all(==(0), u.site.s) && u.model.z[1] == 160
        @test u.cell.cb[1] == 11 && u.cell.y[1] == 2
        # cycles of new-value reads are errors
        @test_throws ArgumentError mtkcompile(AuditCycle(; name = :c))
        # A-60 / D-041: energy folds are per-MCS snapshots; ΔH is exact under that meaning
        p = PottsProblem(AuditEnergyPop(; name = :e), op, (0, 5))
        @test p.u0.model.__snap1[1] == 9
        @test selfcheck(p) < 1.0e-9
        # A-61: cell ODE locals do not leak into folds (dh/dt = Σ h over 16 cells)
        u = solve(PottsProblem(AuditOdePop(; name = :o), op, (0, 1)), SequentialCPM()).u[end]
        @test all(==(17.0), u.cell.h[1:16])
    end
end

@testitem "A-50/A-51/A-54 operating-point validation" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-50/A-51/A-54 operating-point validation" begin
        σ = audit_blocks()
        sys = AuditKinds(; name = :k)
        @test PottsProblem(sys, [ownership => σ, :kind => fill(:B, 16)], (0, 1)).u0.cell.kind[1] == 2
        @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => [1; fill(9, 15)]], (0, 1))
        @test_throws ArgumentError PottsProblem(sys, [ownership => -σ, kind => fill(1, 16)], (0, 1))
        @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => fill(1, 16), :lamda => 2.0], (0, 1))
    end
end

@testitem "D-043 position is Cartesian, site is the current site" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-043 position is Cartesian, site is the current site" begin
        σ = zeros(Int32, 8, 6); σ[2:3, 2:3] .= 1
        p = PottsProblem(AuditPosition(; name = :p), [ownership => σ, kind => [1]], (0, 1))
        u = solve(p, SequentialCPM()).u[end]
        L = p.lattice
        for I in CartesianIndices(σ)
            e = embed(L, Float64.(Tuple(I)))
            @test (u.site.px[I], u.site.py[I]) == e
        end
        @test all(==(6), u.site.g)                       # periodic hex: six neighbours everywhere
    end
end

@testitem "A-31 one equation per variable" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-31 one equation per variable" begin
        @test_throws ArgumentError mtkcompile(AuditField8(; name = :d, mode = :dup))
    end
end

@testitem "A-32 draws stay independent under extend" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-32 draws stay independent under extend" begin
        m = extend(AuditDrawExt(; name = :e), AuditDrawBase(; name = :b))
        σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
        u = solve(PottsProblem(m, [ownership => σ, kind => [1]], (0, 3)), SequentialCPM()).u[end]
        @test u.model.x[1] != u.model.y[1]
    end
end

@testitem "A-34 clear_on_ownership_change; unknown variable options" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-34 clear_on_ownership_change; unknown variable options" begin
        σ = zeros(Int32, 16, 16); σ[4:7, 4:7] .= 1; σ[10:13, 10:13] .= 2
        p = PottsProblem(AuditClear(; name = :c), [ownership => σ, kind => [1, 1], :act => 5.0, :tag => 5.0], (0, 5))
        u = solve(p, SequentialCPM()).u[end]
        changed = u.ownership .!= σ
        @test any(changed)
        @test all(iszero, u.site.act[changed]) && count(==(5), u.site.act) > 0   # changed back: also cleared
        @test all(==(5), u.site.tag)
        @test_throws ArgumentError AuditBadOption(; name = :b)
    end
end

@testitem "A-30 declared names cannot shadow built-ins or each other" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-30 declared names cannot shadow built-ins or each other" begin
        expand(body) = Potts._potts_model(:X, body, @__MODULE__)
        @test_throws ArgumentError expand(
            quote
                @kinds medium A; @parameters distance = 3.0
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium A; @parameters D = 3.0
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium source
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium A; @variables target(cell) = 1.0
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium a; @parameters a = 1.0
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium A A
            end
        )
        @test_throws ArgumentError expand(
            quote
                @kinds medium A; @variables x(cell) = 1.0; @observed x ~ 2
            end
        )
        @test expand(
            quote
                @kinds medium A; @parameters λ = 1.0; @variables x(cell) = 1.0
            end
        ) isa Expr
    end
end

@testitem "A-67 energies see on-copy writes (D-045)" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "A-67 energies see on-copy writes (D-045)" begin
        σ = audit_blocks()
        p = PottsProblem(AuditOnCopyEnergy(; name = :o), [ownership => σ, kind => fill(1, 16)], (0, 3))
        @test selfcheck(p) < 1.0e-9
        @test_throws ArgumentError mtkcompile(AuditOnCopyContact(; name = :c))
    end
end

@testitem "group 2: derived parameters, reinit!, cadence and length checks" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "group 2: derived parameters, reinit!, cadence and length checks" begin
        σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1
        op = [ownership => σ, kind => [1]]
        p = PottsProblem(AuditDerived(; name = :d), op, (0, 2))
        @test p.p.V2 == 18 && p.u0.cell.x[1] == 9                             # A-39
        @test PottsProblem(AuditDerived(; name = :d, V₀ = 4.0), op, (0, 2)).p.V2 == 8
        q = remake(p; p = [:pa => 10.0])
        @test (q.p.pa, q.p.pb) == (10, 30)                                     # pb follows pa (MTK)
        # pb is computed, so read-only (D-F2-1; before: a given value was kept)
        @test_throws ArgumentError remake(p; p = [:pa => 10.0, :pb => 1.0])
        integ = init(p, SequentialCPM())
        setp(integ, :pa)(integ, 7.0)
        @test integ.p.pb == 21
        @test_throws ArgumentError setp(integ, :J)(integ, [0 2; 5 1])       # A-53: contact tables stay symmetric
        @test_throws ArgumentError PottsProblem(AuditDerived(; name = :d), [op; :J => 2.0], (0, 2))   # A-57
        # A-15: reinit! validates shapes, takes symbolic maps, reruns callback initialization
        σ2 = zeros(Int32, 12, 12); σ2[6:8, 6:8] .= 1
        reinit!(integ, [ownership => σ2, kind => [1]])
        @test current_state(integ).ownership == σ2
        bad_u0 = PottsProblem(
            AuditDerived(; name = :d),
            [ownership => (s = zeros(Int32, 12, 12); s[1:2, 1:2] .= 1; s[5:6, 5:6] .= 2; s), kind => [1, 1]], (0, 2);
            capacity = 5
        ).u0
        @test_throws ArgumentError reinit!(integ, bad_u0)
        # A-36: Every on on-copy updates; Every(0)
        @test_throws ArgumentError mtkcompile(AuditOnCopyEvery(; name = :e))
        @test_throws ArgumentError Potts.Every(0)
    end
end

@testitem "A-43/A-44 vector lengths; a frozen medium" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-43/A-44 vector lengths; a frozen medium" begin
        @test_throws ArgumentError Potts.vector_parameter(:d, 1:2, [5.0, 6.0, 7.0])
        @test_throws ArgumentError Potts._potts_model(
            :X, quote
                @kinds medium[frozen] A
            end, @__MODULE__
        )
    end
end

@testitem "group 3: extend vectors and centroid, Julia indexing, tuple defaults" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "group 3: extend vectors and centroid, Julia indexing, tuple defaults" begin
        s = AuditVecExt(; name = :v)                                         # A-37, A-38
        σ = zeros(Int32, 10, 10); σ[2:3, 2:3] .= 1
        u = solve(PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)), SequentialCPM()).u[end]
        @test u.cell.p_1[1] == 3 && u.cell.p_2[1] == 4                       # A-42
        @test u.cell.c_2[1] ≈ Potts._centroid_axis(Float64, u.cell, PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)).lattice, 1, 2) + 2
        ex = Potts.rewrite(:(v[end] + sum(i * j for i in 1:2, j in 1:3)))    # A-40
        @test eval(
            :(
                let v = [1, 5]
                    $ex
                end
            )
        ) == 5 + 18
    end
end

@testitem "A-35 trackers read only by observed/division/temperature" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-35 trackers read only by observed/division/temperature" begin
        σ = zeros(Int32, 16, 16); σ[2:4, 2:4] .= 1
        p = PottsProblem(AuditTrackers(; name = :t), [ownership => σ, kind => [1]], (0, 2))
        sol = solve(p, SequentialCPM())
        @test sol[:per][end][1] == sol.u[end].cell.surface[1]
    end
end

@testitem "D-014/D-016: binary sums, fingerprints over all code" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-014/D-016: binary sums, fingerprints over all code" begin
        # a wide energy: 40 terms lower to binary `+`, allocation-free
        ex = Potts.lower(
            sum(Potts.B.volume^k for k in 1:40) |> Potts._unwrap,
            Potts._cell_env(Float32, :c, Dict{Any, Symbol}())
        )
        @test ex.args[1] === (+) && length(ex.args) == 3
        # models differing only in an update block have different fingerprints
        σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1
        a = PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1))
        b = PottsProblem(AuditJacobi(; name = :j), [ownership => σ, kind => [1]], (0, 1))
        @test a.f.fingerprint != b.f.fingerprint
        @test PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1)).f.fingerprint == a.f.fingerprint
        @test haskey(Potts.generated_code(AuditPopCell(; name = :a)), :phases)
    end
end

@testitem "D-049: conditional sections and model proposals" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-049: conditional sections and model proposals" begin
        σ = zeros(Int32, 12, 12); σ[4:6, 4:6] .= 1
        prob(mode) = PottsProblem(AuditBranches(; name = :b, mode), [ownership => σ, kind => [1]], (0, 1))
        grow = CorePotts.Proposal(
            CorePotts.linear_index(Lattice((12, 12)), (7, 5)), CorePotts.linear_index(Lattice((12, 12)), (6, 5)),
            (7, 5), 1, Int32(0), Int32(1)
        )
        dH(p) = p.f.delta_H(p.u0, p.p, grow, (; lattice = p.lattice, contact = p.contact, p.relations...))
        @test dH(prob(:drive)) - dH(prob(:none)) ≈ 3.0
        @test dH(prob(:energy)) - dH(prob(:none)) ≈ 3.0
        # the else branch declared the proposal; the others keep the default, and algorithms
        # override the model's
        @test prob(:none).proposal isa Moore && prob(:drive).proposal isa VonNeumann
        @test CorePotts._proposal(SequentialCPM(), prob(:none)) isa Moore
        @test CorePotts._proposal(SequentialCPM(; proposal = VonNeumann(1)), prob(:none)) isa VonNeumann
        @test_throws ArgumentError Potts._potts_model(
            :AuditBadBranch, quote
                @structural_parameters begin
                    flag = true
                end
                if flag
                    @parameters begin
                        q = 1.0
                    end
                end
            end, @__MODULE__
        )
    end
end

@testitem "D-049: major_length in energies (square, hex, 3D)" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "D-049: major_length in energies (square, hex, 3D)" begin
        for (lattice, geometry, σ) in (
                ((16, 16), Square(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                ((16, 16), Hexagonal(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                ((8, 8, 8), Square(), (s = zeros(Int32, 8, 8, 8); s[2:5, 2:3, 2:3] .= 1; s)),
            )
            n = maximum(σ)
            p = PottsProblem(AuditLength(; name = :l, lattice, geometry), [ownership => σ, kind => fill(1, n)], (0, 20))
            # ΔH equals the difference of the brute-force energy along a trajectory
            worst = 0.0
            for (u, prop) in proposal_states(p; mcs = (0, 10, 20), n = 150)
                a = deepcopy(u); a.ownership[prop.target] = prop.new
                p.f.commit!(a, p.p, prop, (; lattice = p.lattice, contact = p.contact, p.relations...))
                worst = max(worst, abs(energy_change(p, u, prop) - (total_energy(p, a) - total_energy(p, u) + Potts._killing_credit(p, u, prop, a))))
            end
            @test worst < 1.0e-8
            # the built-in is the CorePotts shape descriptor
            sol = solve(p, SequentialCPM())
            u = sol.u[end]
            @test sol[:len][end] ≈ [CorePotts.cell_shape(u.cell, p.lattice, c).major_length for c in 1:n]
        end
    end
end
