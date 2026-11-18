# Exact transition-matrix oracle (ROADMAP M1.4b): the `Oracle` module is in oracle_core.jl
# (the Potts group reuses it against generated models).

@testsetup module CP_oracle
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("oracle_core.jl")

const ORA_JK = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, kind 1, kind 2
const ORA_VN = [(1, 0), (-1, 0), (0, 1), (0, -1)]
const ORA_MOORE = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
const ORA_R = 40_000
const ORA_P = (; J = SMatrix{3, 3}(ORA_JK), λ = 1.0, V0 = 2.0, T = 4.0)
const ORA_CLOSED_DIMS = (3, 2)
const ORA_CLOSED_SIGMA0 = Int8[1, 1, 0, 2, 2, 0]                    # column-major 3×2
const ORA_CLOSED_LAT = Lattice(ORA_CLOSED_DIMS; boundary = Closed())
const ORA_CLOSED_TINY = Oracle.Tiny(ORA_CLOSED_DIMS, ORA_VN, ORA_MOORE, [1, 2], ORA_JK, 1.0, 2.0, 4.0)
const ORA_CLOSED_PROB = PottsProblem(
    GG, initial_state(reshape(Int32.(ORA_CLOSED_SIGMA0), ORA_CLOSED_DIMS), [1, 2]),
    ORA_CLOSED_LAT, (0, 2), ORA_P
)

include("shared/export_all.jl")
end

@testitem "exact transition oracle (M1.4b): Closed 3x2 (Sequential, skip_interior, Checkerboard)" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "exact transition oracle (M1.4b): Closed 3x2" begin
    # the checkerboard's layout here: one block of one-site sub-regions, 64 phases per MCS
        l = init(ORA_CLOSED_PROB, CheckerboardCPM()).cache.layout
    @test CorePotts.nblocks(l) == 1 && CorePotts.boxsize(l) == 1 && l.k^2 == 64

    for (label, alg, step) in (
            ("SequentialCPM", SequentialCPM(), Oracle.sequential_mcs),
            ("SequentialCPM(skip_interior)", SequentialCPM(; skip_interior = true), Oracle.sequential_mcs),
            ("CheckerboardCPM", CheckerboardCPM(), (m, d) -> Oracle.block_mcs(m, d, 64)))
            ex = Oracle.exact(ORA_CLOSED_TINY, ORA_CLOSED_SIGMA0, 2, step)
        @test sum(values(ex)) ≈ 1
        counts = Dict{Vector{Int8}, Int}()
            for seed in 1:ORA_R
                σ = vec(Int8.(solve(remake(ORA_CLOSED_PROB; seed), alg; save_start = false).u[end].ownership))
            counts[σ] = get(counts, σ, 0) + 1
        end
            d, noise = Oracle.tv(ex, counts, ORA_R)
            z = Oracle.chi2_z(ex, counts, ORA_R)
        @info "oracle" label states = length(ex) tv = d expected_tv = noise z
        @test z < 4.5                   # a correct sampler fails this about once in 3·10⁵ runs
        @test d < 2noise
    end
    end
end

@testitem "exact transition oracle (M1.4b): Closed 3x2 mutant T=5 rejected" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "exact transition oracle (M1.4b): Closed 3x2 mutant T=5" begin
    # power: the test rejects a mutant (T = 4 → 5) at this sample size
        ex = Oracle.exact(ORA_CLOSED_TINY, ORA_CLOSED_SIGMA0, 2, (m, d) -> Oracle.block_mcs(m, d, 64))
        mutant = remake(ORA_CLOSED_PROB; p = merge(ORA_P, (; T = 5.0)))
    counts = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(mutant; seed), CheckerboardCPM()).u[end].ownership))
        counts[σ] = get(counts, σ, 0) + 1
    end
        z = Oracle.chi2_z(ex, counts, ORA_R)
    @info "oracle mutant (T = 5 against exact T = 4)" z
    @test z > 4.5
    end
end

@testitem "exact transition oracle (M1.4b): Periodic 3x3" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "Periodic 3x3" begin
        p_dims = (3, 3)
        p_σ0 = Int8[1, 1, 0, 2, 2, 0, 0, 0, 0]
        p_tiny = Oracle.Tiny(p_dims, ORA_VN, ORA_VN, [1, 2], ORA_JK, 1.0, 2.0, 4.0, true, 0.0)
        p_lat = Lattice(p_dims; boundary = Periodic())
        p_prob = PottsProblem(
            GG, initial_state(reshape(Int32.(p_σ0), p_dims), [1, 2]), p_lat, (0, 1), ORA_P;
            proposal = VonNeumann(1), contact = VonNeumann(1)
        )
        p_cb = CheckerboardCPM()
        p_k = init(p_prob, p_cb).cache.layout.k
        for (alg, step) in (
                (SequentialCPM(), Oracle.sequential_mcs),
                (SequentialCPM(; skip_interior = true), Oracle.sequential_mcs),
                (p_cb, (m, d) -> Oracle.layout_mcs(m, d, p_k)),
            )
            ex_p = Oracle.exact(p_tiny, p_σ0, 1, step)
            cnt_p = Dict{Vector{Int8}, Int}()
            for seed in 1:ORA_R
                σ = vec(Int8.(solve(remake(p_prob; seed), alg; save_start = false).u[end].ownership))
                cnt_p[σ] = get(cnt_p, σ, 0) + 1
            end
            d_p, noise_p = Oracle.tv(ex_p, cnt_p, ORA_R)
            z_p = Oracle.chi2_z(ex_p, cnt_p, ORA_R)
            @test z_p < 4.5
            @test d_p < 2noise_p
        end
    end
end

@testitem "exact transition oracle (M1.4b): Multi-block CheckerboardCPM 4x2 and mutant" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "Multi-block CheckerboardCPM (nblocks > 1) on 4x2 Closed" begin
        mb_dims = (4, 2)
        mb_σ0 = Int8[1, 1, 0, 0, 2, 2, 0, 0]
        mb_tiny = Oracle.Tiny(mb_dims, ORA_VN, ORA_VN, [1, 2], ORA_JK, 1.0, 2.0, 4.0, false, 0.0)
        mb_lat = Lattice(mb_dims; boundary = Closed())
        mb_prob = PottsProblem(
            GG, initial_state(reshape(Int32.(mb_σ0), mb_dims), [1, 2]), mb_lat, (0, 1), ORA_P;
            proposal = VonNeumann(1), contact = VonNeumann(1)
        )
        mb_alg = CheckerboardCPM(; parts = 2, region = 1)
        mb_l = init(mb_prob, mb_alg).cache.layout
        @test CorePotts.nblocks(mb_l) == 2 && CorePotts.boxsize(mb_l) == 1
        ex_mb = Oracle.exact(mb_tiny, mb_σ0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
        cnt_mb = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(mb_prob; seed), mb_alg; save_start = false).u[end].ownership))
            cnt_mb[σ] = get(cnt_mb, σ, 0) + 1
        end
        d_mb, noise_mb = Oracle.tv(ex_mb, cnt_mb, ORA_R)
        @test Oracle.chi2_z(ex_mb, cnt_mb, ORA_R) < 4.5
        @test d_mb < 2noise_mb
        # Mutant: T = 5 rejected
        mb_mut = remake(mb_prob; p = merge(ORA_P, (; T = 5.0)))
        cnt_mb_m = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(mb_mut; seed), mb_alg; save_start = false).u[end].ownership))
            cnt_mb_m[σ] = get(cnt_mb_m, σ, 0) + 1
        end
        @test Oracle.chi2_z(ex_mb, cnt_mb_m, ORA_R) > 4.5
    end
end

@testitem "exact transition oracle (M1.4b): Multi-site box CheckerboardCPM 3x2" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "Multi-site sub-region CheckerboardCPM (boxsize > 1) on 3x2 Closed" begin
        bx_tiny = Oracle.Tiny(ORA_CLOSED_DIMS, ORA_VN, ORA_VN, [1, 2], ORA_JK, 1.0, 2.0, 4.0, false, 0.0)
        bx_prob = PottsProblem(
            GG, initial_state(reshape(Int32.(ORA_CLOSED_SIGMA0), ORA_CLOSED_DIMS), [1, 2]),
            ORA_CLOSED_LAT, (0, 1), ORA_P; proposal = VonNeumann(1), contact = VonNeumann(1)
        )
        bx_alg = CheckerboardCPM(; parts = 2, region = 1)
        bx_l = init(bx_prob, bx_alg).cache.layout
        @test CorePotts.nblocks(bx_l) == 1 && CorePotts.boxsize(bx_l) == 2
        ex_bx = Oracle.exact(bx_tiny, ORA_CLOSED_SIGMA0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
        cnt_bx = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(bx_prob; seed), bx_alg; save_start = false).u[end].ownership))
            cnt_bx[σ] = get(cnt_bx, σ, 0) + 1
        end
        d_bx, noise_bx = Oracle.tv(ex_bx, cnt_bx, ORA_R)
        @test Oracle.chi2_z(ex_bx, cnt_bx, ORA_R) < 4.5
        @test d_bx < 2noise_bx
    end
end

@testitem "exact transition oracle (M1.4b): Copy direction bias and flipped mutant" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
    @testset "Copy direction bias (x_target - x_source) on Closed 3x2" begin
        function dH_dir(st, par, prop, ctx)
            dx = coordinates(ctx.lattice, prop.target)[1] - coordinates(ctx.lattice, prop.source)[1]
            return gg_delta_H(st, par, prop, ctx) + par.α * dx
        end
        f_dir = CPMFunction(dH_dir; temperature = gg_temperature)
        p_dir = merge(ORA_P, (; α = 2.0))
        dir_tiny = Oracle.Tiny(ORA_CLOSED_DIMS, ORA_VN, ORA_VN, [1, 2], ORA_JK, 1.0, 2.0, 4.0, false, 2.0)
        dir_prob = PottsProblem(
            f_dir, initial_state(reshape(Int32.(ORA_CLOSED_SIGMA0), ORA_CLOSED_DIMS), [1, 2]),
            ORA_CLOSED_LAT, (0, 1), p_dir; proposal = VonNeumann(1), contact = VonNeumann(1)
        )
        ex_dir = Oracle.exact(dir_tiny, ORA_CLOSED_SIGMA0, 1, Oracle.sequential_mcs)
        cnt_dir = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(dir_prob; seed), SequentialCPM(); save_start = false).u[end].ownership))
            cnt_dir[σ] = get(cnt_dir, σ, 0) + 1
        end
        d_dir, noise_dir = Oracle.tv(ex_dir, cnt_dir, ORA_R)
        @test Oracle.chi2_z(ex_dir, cnt_dir, ORA_R) < 4.5
        @test d_dir < 2noise_dir
        # Mutant: flipped copy direction (-α) rejected
        dir_mut = remake(dir_prob; p = merge(ORA_P, (; α = -2.0)))
        cnt_dir_m = Dict{Vector{Int8}, Int}()
        for seed in 1:ORA_R
            σ = vec(Int8.(solve(remake(dir_mut; seed), SequentialCPM(); save_start = false).u[end].ownership))
            cnt_dir_m[σ] = get(cnt_dir_m, σ, 0) + 1
    end
        @test Oracle.chi2_z(ex_dir, cnt_dir_m, ORA_R) > 4.5
end
end

@testitem "the checkerboard spacing covers an undeclared read radius" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
@testset "the checkerboard spacing covers an undeclared read radius" begin
    lat = Lattice((20, 20))
    σ, k = blocks((20, 20), 3)
    wide = PottsProblem(GG, initial_state(σ, k), lat, (0, 1), gg_params();
        contact = NeighborOrder(3))
    integ = init(wide, CheckerboardCPM())
    l = integ.cache.layout
    r, w = CorePotts.reach(wide.f.footprint, integ.ctx.proposal)
    @test (l.k - 1) * minimum(l.base) >= CorePotts.radius(integ.ctx.contact) + w   # widened, not refused
    @test init(wide, SequentialCPM()) isa PottsIntegrator
    ok = CPMFunction(gg_delta_H; temperature = gg_temperature, footprint = Footprint(read = 2))
    @test solve(remake(wide; f = ok), CheckerboardCPM()).retcode == ReturnCode.Success
end
end
