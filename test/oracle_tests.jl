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

const ORACLE_JK = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, dark, light
const ORACLE_MOORE = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
const ORACLE_VN = [(1, 0), (-1, 0), (0, 1), (0, -1)]
const ORACLE_R = 40_000
const ORACLE_σ33 = Int8[1, 1, 0, 2, 2, 0, 0, 0, 0]

function oracle_sample(prob, alg)
    counts = Dict{Vector{Int8}, Int}()
    for seed in 1:ORACLE_R
        σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
        counts[σ] = get(counts, σ, 0) + 1
    end
    return counts
end

function check_oracle_match(ex, prob, alg; mutant_p = [:T => 5.0])
    counts = oracle_sample(prob, alg)
    d, noise = Oracle.tv(ex, counts, ORACLE_R)
    z = Oracle.chi2_z(ex, counts, ORACLE_R)
    @test z < 4.5
    @test d < 2noise
    zm = Oracle.chi2_z(ex, oracle_sample(remake(prob; p = mutant_p), alg), ORACLE_R)
    @test zm > 4.5
end

@potts_model OracleDir begin
    @structural_parameters begin
        dims = (3, 2)
        boundary = Closed()
        with_drive = true
    end
    @kinds medium dark light
    @parameters begin
        J[3, 3] = zeros(3, 3)
        λ = 1.0
        V₀ = 2.0
        T = 4.0
        α = 0.0
    end
    @lattice Lattice(dims; boundary, neighborhood = VonNeumann(1))
    @relations proposal = VonNeumann(1)
    @energy begin
        contacts => J[kind, kind′]
        cells => λ * (volume - V₀)^2
    end
    if with_drive
        @drive copy => α * direction[1]
    end
    @sweep Metropolis(; temperature = T)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "generated Graner–Glazier against the exact oracle: SequentialCPM" setup = [OracleSetup] tags = [:potts, :oracle] begin
    dims = (3, 3)
    tiny = Oracle.Tiny(dims, ORACLE_MOORE, ORACLE_MOORE, [1, 2], ORACLE_JK, 1.0, 2.0, 4.0, true)
    prob = PottsProblem(
        GranerGlazier(; name = :gg, lattice = dims),
        [ownership => reshape(Int32.(ORACLE_σ33), dims), kind => [:dark, :light], :J => ORACLE_JK, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
        (0, 1)
    )
    ex = Oracle.exact(tiny, ORACLE_σ33, 1, Oracle.sequential_mcs)
    check_oracle_match(ex, prob, SequentialCPM(; proposal = Moore(1)))
end

@testitem "generated Graner–Glazier against the exact oracle: SequentialCPM skip_interior" setup = [OracleSetup] tags = [:potts, :oracle] begin
    dims = (3, 3)
    tiny = Oracle.Tiny(dims, ORACLE_MOORE, ORACLE_MOORE, [1, 2], ORACLE_JK, 1.0, 2.0, 4.0, true)
    prob = PottsProblem(
        GranerGlazier(; name = :gg, lattice = dims),
        [ownership => reshape(Int32.(ORACLE_σ33), dims), kind => [:dark, :light], :J => ORACLE_JK, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
        (0, 1)
    )
    ex = Oracle.exact(tiny, ORACLE_σ33, 1, Oracle.sequential_mcs)
    check_oracle_match(ex, prob, SequentialCPM(; proposal = Moore(1), skip_interior = true))
end

@testitem "generated Graner–Glazier against the exact oracle: CheckerboardCPM" setup = [OracleSetup] tags = [:potts, :oracle] begin
    dims = (3, 3)
    # periodic axes need length ≥ 3 (shorter ones alias ±1 offsets and are rejected); on 3 × 3
    # the checkerboard is one block of one-site sub-regions (64 phases per MCS)
    tiny = Oracle.Tiny(dims, ORACLE_MOORE, ORACLE_MOORE, [1, 2], ORACLE_JK, 1.0, 2.0, 4.0, true)
    prob = PottsProblem(
        GranerGlazier(; name = :gg, lattice = dims),
        [ownership => reshape(Int32.(ORACLE_σ33), dims), kind => [:dark, :light], :J => ORACLE_JK, :λ => 1.0, :V₀ => 2.0, :T => 4.0],
        (0, 1)
    )
    ex = Oracle.exact(tiny, ORACLE_σ33, 1, (m, d) -> Oracle.block_mcs(m, d, 64))
    check_oracle_match(ex, prob, CheckerboardCPM(; proposal = Moore(1)))
end

@testitem "generated Graner–Glazier against the exact oracle: Multi-block CheckerboardCPM" setup = [OracleSetup] tags = [:potts, :oracle] begin
    mb_dims = (4, 2)
    mb_σ0 = Int8[1, 1, 0, 0, 2, 2, 0, 0]
    mb_tiny = Oracle.Tiny(mb_dims, ORACLE_VN, ORACLE_VN, [1, 2], ORACLE_JK, 1.0, 2.0, 4.0, false, 0.0)
    mb_sys = OracleDir(; name = :mb, dims = mb_dims, boundary = Closed(), with_drive = false)
    mb_prob = PottsProblem(
        mb_sys,
        [ownership => reshape(Int32.(mb_σ0), mb_dims), kind => [:dark, :light], :J => ORACLE_JK], (0, 1)
    )
    mb_alg = CheckerboardCPM(; proposal = VonNeumann(1), parts = 2, region = 1)
    mb_l = init(mb_prob, mb_alg).cache.layout
    @test CorePotts.nblocks(mb_l) == 2 && CorePotts.boxsize(mb_l) == 1
    ex_mb = Oracle.exact(mb_tiny, mb_σ0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
    check_oracle_match(ex_mb, mb_prob, mb_alg)
end

@testitem "generated Graner–Glazier against the exact oracle: Closed BC & copy direction" setup = [OracleSetup] tags = [:potts, :oracle] begin
    # Closed 3x2 multi-site box (boxsize > 1) and Periodic 3x3 copy-direction drive
    for (periodic, d_arg, σ_init, boundary) in (
            (false, (3, 2), Int8[1, 1, 0, 2, 2, 0], Closed()),
            (true, (3, 3), ORACLE_σ33, Periodic()),
        )
        d_sys = OracleDir(; name = :dir, dims = d_arg, boundary, with_drive = true)
        d_prob = PottsProblem(
            d_sys,
            [ownership => reshape(Int32.(σ_init), d_arg), kind => [:dark, :light], :J => ORACLE_JK, :α => 2.0],
            (0, 1)
        )
        d_tiny = Oracle.Tiny(d_arg, ORACLE_VN, ORACLE_VN, [1, 2], ORACLE_JK, 1.0, 2.0, 4.0, periodic, 2.0)
        for (alg, step) in (
                (SequentialCPM(; proposal = VonNeumann(1)), Oracle.sequential_mcs),
                (
                    CheckerboardCPM(; proposal = VonNeumann(1), parts = 2, region = 1),
                    (m, d) -> Oracle.layout_mcs(m, d, 2, 1),
                ),
            )
            ex_d = Oracle.exact(d_tiny, σ_init, 1, step)
            check_oracle_match(ex_d, d_prob, alg; mutant_p = [:α => -2.0, :T => 1.0])
        end
    end
end
