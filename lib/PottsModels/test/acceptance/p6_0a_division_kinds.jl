# P6.0a (ROADMAP Phase 6, step 0): cell division and cluster division in one model, per
# rule domain. Frozen (AUTONOMY §7.3).
using Potts: CorePotts

@potts_model MixedDivision begin
    @kinds medium cytoplasm nucleus free
    @parameters begin
        J[kind, kind] = [0 16 16 16; 16 14 30 16; 16 30 14 16; 16 16 16 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0, 25.0]
        λ = 1.0
        λc = 1.0
        Vc = 64.0
        T = 10.0
    end
    @variables mass(cell) = 2.0
    @lattice Lattice((40, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @divide cells(free) when = (mcs == 2) && (volume >= 20), along = (0.0, 1.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end

# nine 8×8 cytoplasm/nucleus clusters in 30×30, three free 5×5 cells in rows 32:36
function mixed_division_state()
    σ = zeros(Int32, 40, 30)
    n = 0
    for i in 1:10:21, j in 1:10:21
        n += 1
        σ[i:(i + 7), j:(j + 7)] .= n
    end
    for c in 1:n
        lo = minimum(findall(==(c), σ))
        σ[(lo[1] + 2):(lo[1] + 5), (lo[2] + 2):(lo[2] + 5)] .= n + c
    end
    for (k, j) in enumerate((2, 12, 22))
        σ[32:36, j:(j + 4)] .= 2n + k
    end
    kinds = vcat(fill(:cytoplasm, n), fill(:nucleus, n), fill(:free, 3))
    return σ, kinds, vcat(1:n, 1:n, (2n + 1):(2n + 3))
end

@testset "P6.0a: cell and cluster division in one model" begin
    σ, kinds, groups = mixed_division_state()
    prob = PottsProblem(MixedDivision(; name = :mixed), [ownership => σ, kind => kinds, cluster => groups], (0, 4))
    @test selfcheck(remake(prob; tspan = (0, 1))) < 1e-9
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        v = solve(prob, alg).u[end]
        live = findall(>(0), Array(v.cell.volume))
        kd = Array(v.cell.kind)
        cl = Array(v.cell.cluster)
        free = filter(c -> kd[c] == 3, live)
        members = filter(c -> kd[c] != 3, live)
        roots = unique(cl[members])
        @test length(roots) == 18                                  # every cluster divided as a unit
        @test all(r -> sort(kd[filter(c -> cl[c] == r, members)]) == [1, 2], roots)
        @test length(free) == 6                                    # every free cell divided alone
        @test all(c -> cl[c] == c, free)                           # free daughters are singletons
        @test sort(Array(v.cell.mass)[live]) == fill(1.0, 42)      # every divided cell split its mass
        # trackers stay exact through both kinds of division
        @test Array(v.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(v.σ), cl)
    end
end

@testset "P6.0a: one kind cannot be divided by both a cell rule and a cluster rule" begin
    base = MixedDivision(; name = :m)
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :a],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        divisions = [Potts.divide(Potts.cells(1); when = Potts.B.volume > 1),
            Potts.divide(Potts.clusters(1); when = Potts.B.volume > 1)]))
    @test mtkcompile(base) isa Potts.CompiledPottsSystem
end
