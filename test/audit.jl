# Regression tests for docs/design/AUDIT.md findings (IDs A-xx) and decisions D-041..D-045.
# Uses `selfcheck` from symbolic.jl.

audit_blocks() = (σ = zeros(Int32, 20, 20);
    for (k, (i, j)) in enumerate(Iterators.product(1:5:16, 1:5:16)); σ[i:(i + 2), j:(j + 2)] .= k; end; σ)

@potts_model AuditPopCell begin
    @kinds medium A
    @variables a(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs a ~ sum(a for c in cells)
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditJacobi begin
    @kinds medium A
    @variables begin
        m(model) = 0.0
        a(cell) = 0.0
        s(site) = 0.0
        b(cell) = 10.0
        z(model) = 0.0
        y(cell) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ Pre(m) + 1
        a ~ Pre(m)
        s ~ Pre(m)
        z ~ sum(Pre(b) for c in cells)
        b ~ Pre(b) + 1
        y ~ m + 1                          # bare: m's new value
    end
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditCycle begin
    @kinds medium A
    @variables begin
        m(model) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ n + 1
        n ~ m + 1
    end
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditEnergyPop begin
    @kinds medium A
    @lattice Lattice((20, 20))
    @energy cells => (volume - mean(volume for c in cells))^2 + (volume - 9)^2
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditOdePop begin
    @kinds medium A
    @variables h(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @equations D(h) ~ sum(h for c in cells)
    @sweep Metropolis(; temperature = 5.0)
end

@testset "D-041/D-042 update semantics and population folds" begin
    σ = audit_blocks()
    op = [ownership => σ, kind => fill(1, 16)]
    # A-62: a fold in a cell update reads previous values, once per stage
    u = solve(PottsProblem(AuditPopCell(; name = :a), op, (0, 1)), SequentialCPM()).u[end]
    @test all(==(16.0), u.cell.a[1:16])
    # A-63: Pre is the value before the block in every scope; bare reads are new values
    u = solve(PottsProblem(AuditJacobi(; name = :j), op, (0, 1)), SequentialCPM()).u[end]
    @test u.model.m[1] == 1 && u.cell.a[1] == 0 && all(==(0), u.site.s) && u.model.z[1] == 160
    @test u.cell.b[1] == 11 && u.cell.y[1] == 2
    # cycles of new-value reads are errors
    @test_throws ArgumentError mtkcompile(AuditCycle(; name = :c))
    # A-60 / D-041: energy folds are per-MCS snapshots; ΔH is exact under that meaning
    p = PottsProblem(AuditEnergyPop(; name = :e), op, (0, 5))
    @test p.u0.model.__snap1[1] == 9
    @test selfcheck(p) < 1e-9
    # A-61: cell ODE locals do not leak into folds (dh/dt = Σ h over 16 cells)
    u = solve(PottsProblem(AuditOdePop(; name = :o), op, (0, 1)), SequentialCPM()).u[end]
    @test all(==(17.0), u.cell.h[1:16])
end

@potts_model AuditKinds begin
    @kinds medium A B
    @parameters λ = 1.0
    @lattice Lattice((20, 20))
    @energy cells => λ * (volume - 9)^2
    @sweep Metropolis(; temperature = 5.0)
end

@testset "A-50/A-51/A-54 operating-point validation" begin
    σ = audit_blocks()
    sys = AuditKinds(; name = :k)
    @test PottsProblem(sys, [ownership => σ, :kind => fill(:B, 16)], (0, 1)).u0.cell.kind[1] == 2
    @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => [1; fill(9, 15)]], (0, 1))
    @test_throws ArgumentError PottsProblem(sys, [ownership => -σ, kind => fill(1, 16)], (0, 1))
    @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => fill(1, 16), :lamda => 2.0], (0, 1))
end
