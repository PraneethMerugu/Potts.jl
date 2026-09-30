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

@potts_model AuditDerived begin
    @kinds medium A
    @parameters begin
        V₀ = 9.0
        V2 = 2V₀
        a = 2.0
        b = 3a
        J[kind, kind] = [0 2; 2 1]
    end
    @variables x(cell) = V₀
    @lattice Lattice((12, 12))
    @energy begin
        cells => (volume - V2 / 2)^2 + b * 0
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditOnCopyEvery begin
    @kinds medium A
    @variables act(site) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @on_copy Every(3) act[target] ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "group 2: derived parameters, reinit!, cadence and length checks" begin
    σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1
    op = [ownership => σ, kind => [1]]
    p = PottsProblem(AuditDerived(; name = :d), op, (0, 2))
    @test p.p.V2 == 18 && p.u0.cell.x[1] == 9                             # A-39
    @test PottsProblem(AuditDerived(; name = :d, V₀ = 4.0), op, (0, 2)).p.V2 == 8
    q = remake(p; p = [:a => 10.0])
    @test (q.p.a, q.p.b) == (10, 30)                                     # b follows a (MTK)
    @test remake(p; p = [:a => 10.0, :b => 1.0]).p.b == 1                 # unless given
    integ = init(p, SequentialCPM())
    setp(integ, :a)(integ, 7.0)
    @test integ.p.b == 21
    @test_throws ArgumentError setp(integ, :J)(integ, [0 2; 5 1])       # A-53: contact tables stay symmetric
    @test_throws ArgumentError PottsProblem(AuditDerived(; name = :d), [op; :J => 2.0], (0, 2))   # A-57
    # A-15: reinit! validates shapes, takes symbolic maps, reruns callback initialization
    σ2 = zeros(Int32, 12, 12); σ2[6:8, 6:8] .= 1
    reinit!(integ, [ownership => σ2, kind => [1]])
    @test integ.u.σ == σ2
    @test_throws Exception reinit!(integ, PottsProblem(AuditDerived(; name = :d),
        [ownership => (s = zeros(Int32, 12, 12); s[1:2, 1:2] .= 1; s[5:6, 5:6] .= 2; s), kind => [1, 1]], (0, 2); capacity = 5).u0)
    # A-36: Every on on-copy updates; Every(0)
    @test_throws ArgumentError mtkcompile(AuditOnCopyEvery(; name = :e))
    @test_throws ArgumentError Potts.Every(0)
end

@testset "A-43/A-44 vector lengths; a frozen medium" begin
    @test_throws ArgumentError Potts.vector_parameter(:d, 1:2, [5.0, 6.0, 7.0])
    @test_throws ArgumentError Potts._potts_model(:X, quote @kinds medium[frozen] A end, @__MODULE__)
end

@potts_model AuditVecBase begin
    @kinds medium A
    @parameters d[1:2] = [1.0, 2.0]
    @variables p(cell)[1:2] = (3.0, 4.0)
    @lattice Lattice((10, 10))
    @energy cells => (volume - 4)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model AuditVecExt begin
    @extend d, p = base = AuditVecBase()
    @kinds medium A
    @variables c(cell)[1:2] = 0.0
    @after_mcs c ~ centroid() .+ d
end
helper_last(v) = v[end]

@testset "group 3: extend vectors and centroid, Julia indexing, tuple defaults" begin
    s = AuditVecExt(; name = :v)                                         # A-37, A-38
    σ = zeros(Int32, 10, 10); σ[2:3, 2:3] .= 1
    u = solve(PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)), SequentialCPM()).u[end]
    @test u.cell.p_1[1] == 3 && u.cell.p_2[1] == 4                       # A-42
    @test u.cell.c_2[1] ≈ Potts._centroid_axis(Float64, u.cell, PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)).lattice, 1, 2) + 2
    ex = Potts.rewrite(:(v[end] + sum(i * j for i in 1:2, j in 1:3)))    # A-40
    @test eval(:(let v = [1, 5]; $ex; end)) == 5 + 18
end

@potts_model AuditTrackers begin
    @kinds medium A
    @variables s(cell) = 0.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 9)^2
    @observed per(cell) ~ surface
    @divide cells(A) when = volume > 1000, s => surface
    @sweep Metropolis(; temperature = 1.0 + 0 * centroid(1))
end

@testset "A-35 trackers read only by observed/division/temperature" begin
    σ = zeros(Int32, 16, 16); σ[2:4, 2:4] .= 1
    p = PottsProblem(AuditTrackers(; name = :t), [ownership => σ, kind => [1]], (0, 2))
    sol = solve(p, SequentialCPM())
    @test sol[:per][end][1] == sol.u[end].cell.surface[1]
end

@testset "D-014/D-016: binary sums, fingerprints over all code" begin
    # a wide energy: 40 terms lower to binary `+`, allocation-free
    ex = Potts.lower(sum(Potts.B.volume^k for k in 1:40) |> Potts._unwrap,
        Potts._cell_env(Float32, :c, Dict{Any, Symbol}()))
    @test ex.args[1] === (+) && length(ex.args) == 3
    # models differing only in an update block have different fingerprints
    σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1
    a = PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1))
    b = PottsProblem(AuditJacobi(; name = :j), [ownership => σ, kind => [1]], (0, 1))
    @test a.f.fingerprint != b.f.fingerprint
    @test PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1)).f.fingerprint == a.f.fingerprint
    @test haskey(Potts.generated_code(AuditPopCell(; name = :a)), :phases)
end

# D-049: conditional sections, model-declared proposals, `major_length` in energies
@potts_model AuditBranches begin
    @structural_parameters begin
        mode = :none
    end
    @kinds medium A
    @parameters begin
        μ = 3.0
    end
    @lattice Lattice((12, 12); boundary = Closed())
    @energy cells(A) => (volume - 9)^2
    if mode == :drive
        @drive copy => μ
    elseif mode == :energy
        @energy cells(A) => μ * volume
    else
        @relations proposal = Moore(1)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model AuditLength begin
    @structural_parameters begin
        lattice = (16, 16)
        geometry = Square()
    end
    @kinds medium A
    @parameters begin
        λ_L = 2.0
        L = 7.0
    end
    @lattice Lattice(lattice; geometry)
    @energy begin
        cells(A) => (volume - 12)^2 + λ_L * (major_length - L)^2
        contacts => 1.0 * (kind != kind′)
    end
    @observed len(cell) ~ major_length
    @sweep Metropolis(; temperature = 4.0)
end

@testset "D-049: conditional sections and model proposals" begin
    σ = zeros(Int32, 12, 12); σ[4:6, 4:6] .= 1
    prob(mode) = PottsProblem(AuditBranches(; name = :b, mode), [ownership => σ, kind => [1]], (0, 1))
    grow = CorePotts.Proposal(CorePotts.linear_index(Lattice((12, 12)), (7, 5)), CorePotts.linear_index(Lattice((12, 12)), (6, 5)),
        (7, 5), 1, Int32(0), Int32(1))
    dH(p) = p.f.delta_H(p.u0, p.p, grow, (; lattice = p.lattice, contact = p.contact, p.relations...))
    @test dH(prob(:drive)) - dH(prob(:none)) ≈ 3.0
    @test dH(prob(:energy)) - dH(prob(:none)) ≈ 3.0
    # the else branch declared the proposal; the others keep the default, and algorithms
    # override the model's
    @test prob(:none).proposal isa Moore && prob(:drive).proposal isa VonNeumann
    @test CorePotts._proposal(SequentialCPM(), prob(:none)) isa Moore
    @test CorePotts._proposal(SequentialCPM(; proposal = VonNeumann(1)), prob(:none)) isa VonNeumann
    @test_throws Exception @eval @potts_model AuditBadBranch begin
        @structural_parameters begin
            flag = true
        end
        if flag
            @parameters begin
                q = 1.0
            end
        end
    end
end

@testset "D-049: major_length in energies (square, hex, 3D)" begin
    for (lattice, geometry, σ) in (((16, 16), Square(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                                   ((16, 16), Hexagonal(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                                   ((8, 8, 8), Square(), (s = zeros(Int32, 8, 8, 8); s[2:5, 2:3, 2:3] .= 1; s)))
        n = maximum(σ)
        p = PottsProblem(AuditLength(; name = :l, lattice, geometry), [ownership => σ, kind => fill(1, n)], (0, 20))
        # ΔH equals the difference of the brute-force energy along a trajectory
        worst = 0.0
        for (u, prop) in proposal_states(p; mcs = (0, 10, 20), n = 150)
            a = deepcopy(u); a.σ[prop.target] = prop.new
            p.f.commit!(a, p.p, prop, (; lattice = p.lattice, contact = p.contact, p.relations...))
            worst = max(worst, abs(energy_change(p, u, prop) - (total_energy(p, a) - total_energy(p, u))))
        end
        @test worst < 1e-8
        # the built-in is the CorePotts shape descriptor
        sol = solve(p, SequentialCPM())
        u = sol.u[end]
        @test sol[:len][end] ≈ [CorePotts.shape(u.cell, p.lattice, c).major_length for c in 1:n]
    end
end
