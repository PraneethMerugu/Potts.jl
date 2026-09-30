# P6.0b (ROADMAP Phase 6, step 0): several named relationships per model, each with its
# own link store, laws and claim set. Frozen (AUTONOMY §7.3).
using Potts: CorePotts
using Statistics: mean

@potts_model TwoSprings begin
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        k₁ = 2.0
        ℓ₁ = 12.0
        k₂ = 2.0
        ℓ₂ = 18.0
        J[kind, kind] = [0 16; 16 2]
    end
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((64, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
        edges(bond) => k₁ * (distance - ℓ₁)^2
        edges(tether) => k₂ * (distance - ℓ₂)^2
    end
    @sweep Metropolis(; temperature = T)
end

# three 6×6 blobs in a row, 25 apart: 1–2 bonded (rest 12), 2–3 tethered (rest 18)
function two_springs_problem(tspan = (0, 1000))
    σ = zeros(Int32, 64, 30)
    σ[5:10, 12:17] .= 1
    σ[30:35, 12:17] .= 2
    σ[55:60, 12:17] .= 3
    return PottsProblem(TwoSprings(; name = :two), [ownership => σ, kind => [:blob, :blob, :blob],
        :bond => [(1, 2)], :tether => [(2, 3)]], (tspan[1], tspan[2]))
end

dist(prob, u, a, b) = CorePotts.centroid_distance(Float64, u.cell, prob.lattice, a, b)

@testset "P6.0b: two relationships, each with its own store and law" begin
    prob = two_springs_problem()
    @test selfcheck(prob) < 1e-9
    for alg in (SequentialCPM(), CheckerboardCPM())
        d = map(1:4) do seed
            u = solve(remake(prob; seed), alg).u[end]
            (dist(prob, u, 1, 2), dist(prob, u, 2, 3))
        end
        @test abs(mean(first.(d)) - 12.0) < 2.5          # bond relaxes to its own rest length
        @test abs(mean(last.(d)) - 18.0) < 2.5           # tether to its own (a shared store
                                                         # or law would pull both to one length)
    end
end

@testset "P6.0b: relationship names are checked" begin
    @test_throws Exception @eval @potts_model DuplicateRelationship begin
        @kinds medium blob
        @relationship bond(cell, cell) capacity = 1
        @relationship bond(cell, cell) capacity = 2
        @lattice Lattice((8, 8); neighborhood = Moore(1))
        @energy edges(bond) => distance
        @sweep Metropolis(; temperature = 1.0)
    end
    @test mtkcompile(TwoSprings(; name = :two)) isa Potts.CompiledPottsSystem
end
