# The generated Graner–Glazier model against the exact transition-matrix oracle (D-048): the
# oracle (lib/CorePotts/test/oracle_core.jl) re-derives each algorithm's Markov chain from its
# specification; the empirical end-state distribution of the generated code over many seeds
# must match it (χ² z-score and TV distance against sampling noise), and a mutant must not.

@testsetup module OracleSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using PottsModels: GranerGlazier
include(joinpath(@__DIR__, "..", "lib", "CorePotts", "test", "oracle_core.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "generated Graner–Glazier against the exact oracle" setup = [OracleSetup] tags = [:potts, :oracle] begin
    @testset "generated Graner–Glazier against the exact oracle" begin
        Jk = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, dark, light
        moore = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
        R = 40_000
        function sample(prob, alg)
            counts = Dict{Vector{Int8}, Int}()
            for seed in 1:R
                σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
                counts[σ] = get(counts, σ, 0) + 1
            end
            return counts
        end
        # periodic axes need length ≥ 3 (shorter ones alias ±1 offsets and are rejected); on 3 × 3
        # the checkerboard is one block of one-site sub-regions (64 phases per MCS)
        for (dims, σ0, nmcs, alg, step) in (
                ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, SequentialCPM(; proposal = Moore(1)), Oracle.sequential_mcs),
                ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, SequentialCPM(; proposal = Moore(1), skip_interior = true), Oracle.sequential_mcs),
                ((3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], 1, CheckerboardCPM(; proposal = Moore(1)), (m, d) -> Oracle.block_mcs(m, d, 64)))
            tiny = Oracle.Tiny(dims, moore, moore, [1, 2], Jk, 1.0, 2.0, 4.0, true)
            prob = PottsProblem(GranerGlazier(; name = :gg, lattice = dims),
                [ownership => reshape(Int32.(σ0), dims), kind => [:dark, :light], :J => Jk, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
                (0, nmcs))
            ex = Oracle.exact(tiny, σ0, nmcs, step)
            counts = sample(prob, alg)
            d, noise = Oracle.tv(ex, counts, R)
            z = Oracle.chi2_z(ex, counts, R)
            @info "generated oracle" alg = nameof(typeof(alg)) dims states = length(ex) tv = d expected_tv = noise z
            @test z < 4.5
            @test d < 2noise
            # power: the same comparison rejects a model with T = 5
            zm = Oracle.chi2_z(ex, sample(remake(prob; p = [:T => 5.0]), alg), R)
            @info "generated oracle mutant (T = 5 against exact T = 4)" zm
            @test zm > 4.5
        end

        @testset "Closed BC, multi-block / multi-site CheckerboardCPM, and copy direction" begin
            vn = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            @potts_model OracleDirClosed begin
                @kinds medium dark light
                @parameters begin
                    J[3, 3] = zeros(3, 3)
                    λ = 1.0
                    V₀ = 2.0
                    T = 4.0
                    α = 0.0
                end
                @lattice Lattice((3, 2); boundary = Closed(), neighborhood = VonNeumann(1))
                @relations proposal = VonNeumann(1)
                @energy begin
                    contacts => J[kind, kind′]
                    cells => λ * (volume - V₀)^2
                end
                @drive copy => α * direction[1]
                @sweep Metropolis(; temperature = T)
            end

            # Closed 4x2 multi-block CheckerboardCPM (nblocks > 1)
            @potts_model OracleDirMB begin
                @kinds medium dark light
                @parameters J[3, 3] = zeros(3, 3) λ = 1.0 V₀ = 2.0 T = 4.0
                @lattice Lattice((4, 2); boundary = Closed(), neighborhood = VonNeumann(1))
                @relations proposal = VonNeumann(1)
                @energy begin
                    contacts => J[kind, kind′]
                    cells => λ * (volume - V₀)^2
                end
                @sweep Metropolis(; temperature = T)
            end
            mb_dims = (4, 2)
            mb_σ0 = Int8[1, 1, 0, 0, 2, 2, 0, 0]
            mb_tiny = Oracle.Tiny(mb_dims, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, false, 0.0)
            mb_sys = OracleDirMB(; name = :mb)
            mb_prob = PottsProblem(mb_sys,
                [ownership => reshape(Int32.(mb_σ0), mb_dims), kind => [:dark, :light], :J => Jk], (0, 1))
            mb_alg = CheckerboardCPM(; proposal = VonNeumann(1), parts = 2, region = 1)
            mb_l = init(mb_prob, mb_alg).cache.layout
            @test CorePotts.nblocks(mb_l) == 2 && CorePotts.boxsize(mb_l) == 1
            ex_mb = Oracle.exact(mb_tiny, mb_σ0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
            cnt_mb = sample(mb_prob, mb_alg)
            d_mb, noise_mb = Oracle.tv(ex_mb, cnt_mb, R)
            @test Oracle.chi2_z(ex_mb, cnt_mb, R) < 4.5
            @test d_mb < 2noise_mb
            @test Oracle.chi2_z(ex_mb, sample(remake(mb_prob; p = [:T => 5.0]), mb_alg), R) > 4.5

            @potts_model OracleDirPeriodic begin
                @kinds medium dark light
                @parameters begin
                    J[3, 3] = zeros(3, 3)
                    λ = 1.0
                    V₀ = 2.0
                    T = 4.0
                    α = 0.0
                end
                @lattice Lattice((3, 3); boundary = Periodic(), neighborhood = VonNeumann(1))
                @relations proposal = VonNeumann(1)
                @energy begin
                    contacts => J[kind, kind′]
                    cells => λ * (volume - V₀)^2
                end
                @drive copy => α * direction[1]
                @sweep Metropolis(; temperature = T)
            end

            # Closed 3x2 multi-site box (boxsize > 1) and Periodic 3x3 copy-direction drive
            for (periodic, d_arg, σ_init, sys_ctor) in (
                    (false, (3, 2), Int8[1, 1, 0, 2, 2, 0], OracleDirClosed),
                    (true, (3, 3), Int8[1, 1, 0, 2, 2, 0, 0, 0, 0], OracleDirPeriodic))
                d_sys = sys_ctor(; name = :dir)
                d_prob = PottsProblem(d_sys,
                    [ownership => reshape(Int32.(σ_init), d_arg), kind => [:dark, :light], :J => Jk, :α => 2.0],
                    (0, 1))
                d_tiny = Oracle.Tiny(d_arg, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, periodic, 2.0)
                for (alg, step) in (
                        (SequentialCPM(; proposal = VonNeumann(1)), Oracle.sequential_mcs),
                        (CheckerboardCPM(; proposal = VonNeumann(1), parts = 2, region = 1),
                         (m, d) -> Oracle.layout_mcs(m, d, 2, 1)))
                    ex_d = Oracle.exact(d_tiny, σ_init, 1, step)
                    cnt_d = sample(d_prob, alg)
                    dd, nd = Oracle.tv(ex_d, cnt_d, R)
                    @test Oracle.chi2_z(ex_d, cnt_d, R) < 4.5
                    @test dd < 2nd
                    @test Oracle.chi2_z(ex_d, sample(remake(d_prob; p = [:α => -2.0, :T => 1.0]), alg), R) > 4.5
                end
            end
        end
    end
end
