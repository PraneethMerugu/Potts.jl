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

@potts_model AuditPosition begin
    @kinds medium A
    @variables begin
        px(site) = 0.0
        py(site) = 0.0
        c(site) = 1.0
        g(site) = 0.0
    end
    @lattice Lattice((8, 6); geometry = Hexagonal())
    @energy cells => (volume - 4)^2
    @after_mcs begin
        px ~ position[1]
        py ~ position[2]
        g ~ sum(c[n] for n in Hex(1)(site))
    end
    @sweep Metropolis(; temperature = 5.0)
end

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

@potts_model AuditDupODE begin
    @kinds medium A
    @variables c(field) = 1.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @equations begin
        D(c) ~ -c / 10
        D(c) ~ -c / 10
    end
    @sweep Metropolis(; temperature = 5.0)
end

@testset "A-31 one equation per variable" begin
    @test_throws ArgumentError mtkcompile(AuditDupODE(; name = :d))
end

@potts_model AuditDrawBase begin
    @kinds medium A
    @variables x(model) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @after_mcs x ~ rand()
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model AuditDrawExt begin
    @kinds medium A
    @variables y(model) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @after_mcs y ~ rand()
    @sweep Metropolis(; temperature = 5.0)
end

@testset "A-32 draws stay independent under extend" begin
    m = extend(AuditDrawExt(; name = :e), AuditDrawBase(; name = :b))
    σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
    u = solve(PottsProblem(m, [ownership => σ, kind => [1]], (0, 3)), SequentialCPM()).u[end]
    @test u.model.x[1] != u.model.y[1]
end

@potts_model AuditDiffusion begin
    @kinds medium A
    @parameters Dc = 0.1
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 5.0)
end

@testset "A-64 field substeps follow the current parameters" begin
    σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1
    c0 = zeros(16, 16); c0[8, 8] = 100.0
    p = PottsProblem(AuditDiffusion(; name = :d), [ownership => σ, kind => [1], :c => c0], (0, 10))
    q = remake(p; p = [:Dc => 5.0])
    fresh = PottsProblem(AuditDiffusion(; name = :d), [ownership => σ, kind => [1], :c => c0, :Dc => 5.0], (0, 10))
    uq = solve(q, SequentialCPM()).u[end].site.c
    @test uq ≈ solve(fresh, SequentialCPM()).u[end].site.c
    @test maximum(abs, uq) < 100
end

@potts_model AuditClear begin
    @kinds medium A
    @variables begin
        act(site) = 0.0, [clear_on_ownership_change = true]
        tag(site) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @sweep Metropolis(; temperature = 20.0)
end

@potts_model AuditBadOption begin
    @kinds medium A
    @variables act(site) = 0.0, [clear_on_ownership_chnage = true]
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "A-34 clear_on_ownership_change; unknown variable options" begin
    σ = zeros(Int32, 16, 16); σ[4:7, 4:7] .= 1; σ[10:13, 10:13] .= 2
    p = PottsProblem(AuditClear(; name = :c), [ownership => σ, kind => [1, 1], :act => 5.0, :tag => 5.0], (0, 5))
    u = solve(p, SequentialCPM()).u[end]
    changed = u.σ .!= σ
    @test any(changed)
    @test all(iszero, u.site.act[changed]) && count(==(5), u.site.act) > 0   # changed back: also cleared
    @test all(==(5), u.site.tag)
    @test_throws ArgumentError AuditBadOption(; name = :b)
end

@testset "A-30 declared names cannot shadow built-ins or each other" begin
    expand(body) = Potts._potts_model(:X, body, @__MODULE__)
    base = quote
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = 1.0)
    end
    @test_throws ArgumentError expand(quote @kinds medium A; @parameters distance = 3.0 end)
    @test_throws ArgumentError expand(quote @kinds medium A; @parameters D = 3.0 end)
    @test_throws ArgumentError expand(quote @kinds medium source end)
    @test_throws ArgumentError expand(quote @kinds medium A; @variables target(cell) = 1.0 end)
    @test_throws ArgumentError expand(quote @kinds medium a; @parameters a = 1.0 end)
    @test_throws ArgumentError expand(quote @kinds medium A A end)
    @test_throws ArgumentError expand(quote @kinds medium A; @variables x(cell) = 1.0; @observed x ~ 2 end)
    @test expand(quote @kinds medium A; @parameters λ = 1.0; @variables x(cell) = 1.0 end) isa Expr
end

@potts_model AuditOnCopyEnergy begin
    @kinds medium A
    @variables begin
        x(cell) = 1.0
        act(site) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy begin
        cells => x * volume + (volume - 9)^2
        sites => 0.5 * act
    end
    @on_copy begin
        x[new] ~ x[new] + 1
        act[target] ~ 3.0
    end
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditOnCopyContact begin
    @kinds medium A
    @variables x(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy begin
        cells => (volume - 9)^2
        contacts => x[owner] + x[owner′]
    end
    @on_copy x[new] ~ x[new] + 1
    @sweep Metropolis(; temperature = 5.0)
end

@testset "A-67 energies see on-copy writes (D-045)" begin
    σ = audit_blocks()
    p = PottsProblem(AuditOnCopyEnergy(; name = :o), [ownership => σ, kind => fill(1, 16)], (0, 3))
    @test selfcheck(p) < 1e-9
    @test_throws ArgumentError mtkcompile(AuditOnCopyContact(; name = :c))
end
