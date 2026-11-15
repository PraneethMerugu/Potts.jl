# Exact transition-matrix oracle (ROADMAP M1.4b): the `Oracle` module is in oracle_core.jl
# (the Potts group reuses it against generated models).

@testsetup module CP_oracle
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("oracle_core.jl")
include("shared/export_all.jl")
end

@testitem "exact transition oracle (M1.4b)" setup = [CP_oracle] tags = [:corepotts, :oracle] begin
@testset "exact transition oracle (M1.4b)" begin
    Jk = [0.0 6 8; 6 2 10; 8 10 3]                 # medium, kind 1, kind 2
    dims = (3, 2)
    vn = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    moore = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
    tiny = Oracle.Tiny(dims, vn, moore, [1, 2], Jk, 1.0, 2.0, 4.0)
    σ0 = Int8[1, 1, 0, 2, 2, 0]                    # column-major 3×2

    lat = Lattice(dims; boundary = Closed())
    p = (; J = SMatrix{3, 3}(Jk), λ = 1.0, V0 = 2.0, T = 4.0)
    prob = PottsProblem(GG, initial_state(reshape(Int32.(σ0), dims), [1, 2]), lat, (0, 2), p)

    # the checkerboard's layout here: one block of one-site sub-regions, 64 phases per MCS
    l = init(prob, CheckerboardCPM()).cache.layout
    @test CorePotts.nblocks(l) == 1 && CorePotts.boxsize(l) == 1 && l.k^2 == 64

    R = 40_000
    for (label, alg, step) in (
            ("SequentialCPM", SequentialCPM(), Oracle.sequential_mcs),
            ("SequentialCPM(skip_interior)", SequentialCPM(; skip_interior = true), Oracle.sequential_mcs),
            ("CheckerboardCPM", CheckerboardCPM(), (m, d) -> Oracle.block_mcs(m, d, 64)))
        ex = Oracle.exact(tiny, σ0, 2, step)
        @test sum(values(ex)) ≈ 1
        counts = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
            counts[σ] = get(counts, σ, 0) + 1
        end
        d, noise = Oracle.tv(ex, counts, R)
        z = Oracle.chi2_z(ex, counts, R)
        @info "oracle" label states = length(ex) tv = d expected_tv = noise z
        @test z < 4.5                   # a correct sampler fails this about once in 3·10⁵ runs
        @test d < 2noise
    end

    # power: the test rejects a mutant (T = 4 → 5) at this sample size
    ex = Oracle.exact(tiny, σ0, 2, (m, d) -> Oracle.block_mcs(m, d, 64))
    mutant = remake(prob; p = merge(p, (; T = 5.0)))
    counts = Dict{Vector{Int8}, Int}()
    for seed in 1:R
        σ = vec(Int8.(solve(remake(mutant; seed), CheckerboardCPM()).u[end].σ))
        counts[σ] = get(counts, σ, 0) + 1
    end
    z = Oracle.chi2_z(ex, counts, R)
    @info "oracle mutant (T = 5 against exact T = 4)" z
    @test z > 4.5

    # Periodic BC, multi-block (nblocks > 1) and multi-site box (boxsize > 1) CheckerboardCPM,
    # plus copy-direction drive
    @testset "Periodic BC, multi-block / multi-site CheckerboardCPM, and copy direction" begin
        # 1. Periodic 3x3 with SequentialCPM, skip_interior, and CheckerboardCPM
        p_dims = (3, 3)
        p_σ0 = Int8[1, 1, 0, 2, 2, 0, 0, 0, 0]
        p_tiny = Oracle.Tiny(p_dims, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, true, 0.0)
        p_lat = Lattice(p_dims; boundary = Periodic())
        p_prob = PottsProblem(GG, initial_state(reshape(Int32.(p_σ0), p_dims), [1, 2]), p_lat, (0, 1), p;
            proposal = VonNeumann(1), contact = VonNeumann(1))
        p_cb = CheckerboardCPM()
        p_k = init(p_prob, p_cb).cache.layout.k
        for (alg, step) in ((SequentialCPM(), Oracle.sequential_mcs),
                (SequentialCPM(; skip_interior = true), Oracle.sequential_mcs),
                (p_cb, (m, d) -> Oracle.layout_mcs(m, d, p_k)))
            ex_p = Oracle.exact(p_tiny, p_σ0, 1, step)
            cnt_p = Dict{Vector{Int8}, Int}()
            for seed in 1:R
                σ = vec(Int8.(solve(remake(p_prob; seed), alg; save_start = false).u[end].σ))
                cnt_p[σ] = get(cnt_p, σ, 0) + 1
            end
            d_p, noise_p = Oracle.tv(ex_p, cnt_p, R)
            z_p = Oracle.chi2_z(ex_p, cnt_p, R)
            @test z_p < 4.5
            @test d_p < 2noise_p
        end

        # 2. Multi-block CheckerboardCPM (nblocks > 1) on 4x2 Closed
        mb_dims = (4, 2)
        mb_σ0 = Int8[1, 1, 0, 0, 2, 2, 0, 0]
        mb_tiny = Oracle.Tiny(mb_dims, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, false, 0.0)
        mb_lat = Lattice(mb_dims; boundary = Closed())
        mb_prob = PottsProblem(GG, initial_state(reshape(Int32.(mb_σ0), mb_dims), [1, 2]), mb_lat, (0, 1), p;
            proposal = VonNeumann(1), contact = VonNeumann(1))
        mb_alg = CheckerboardCPM(; parts = 2, region = 1)
        mb_l = init(mb_prob, mb_alg).cache.layout
        @test CorePotts.nblocks(mb_l) == 2 && CorePotts.boxsize(mb_l) == 1
        ex_mb = Oracle.exact(mb_tiny, mb_σ0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
        cnt_mb = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(mb_prob; seed), mb_alg; save_start = false).u[end].σ))
            cnt_mb[σ] = get(cnt_mb, σ, 0) + 1
        end
        d_mb, noise_mb = Oracle.tv(ex_mb, cnt_mb, R)
        @test Oracle.chi2_z(ex_mb, cnt_mb, R) < 4.5
        @test d_mb < 2noise_mb
        # Mutant: T = 5 rejected
        mb_mut = remake(mb_prob; p = merge(p, (; T = 5.0)))
        cnt_mb_m = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(mb_mut; seed), mb_alg; save_start = false).u[end].σ))
            cnt_mb_m[σ] = get(cnt_mb_m, σ, 0) + 1
        end
        @test Oracle.chi2_z(ex_mb, cnt_mb_m, R) > 4.5

        # 3. Multi-site sub-region CheckerboardCPM (boxsize > 1) on 3x2 Closed
        bx_tiny = Oracle.Tiny(dims, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, false, 0.0)
        bx_prob = PottsProblem(GG, initial_state(reshape(Int32.(σ0), dims), [1, 2]), lat, (0, 1), p;
            proposal = VonNeumann(1), contact = VonNeumann(1))
        bx_alg = CheckerboardCPM(; parts = 2, region = 1)
        bx_l = init(bx_prob, bx_alg).cache.layout
        @test CorePotts.nblocks(bx_l) == 1 && CorePotts.boxsize(bx_l) == 2
        ex_bx = Oracle.exact(bx_tiny, σ0, 1, (m, d) -> Oracle.layout_mcs(m, d, 2, 1))
        cnt_bx = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(bx_prob; seed), bx_alg; save_start = false).u[end].σ))
            cnt_bx[σ] = get(cnt_bx, σ, 0) + 1
        end
        d_bx, noise_bx = Oracle.tv(ex_bx, cnt_bx, R)
        @test Oracle.chi2_z(ex_bx, cnt_bx, R) < 4.5
        @test d_bx < 2noise_bx

        # 4. Copy direction bias (x_target - x_source) on Closed 3x2
        function dH_dir(st, par, prop, ctx)
            dx = coordinates(ctx.lattice, prop.target)[1] - coordinates(ctx.lattice, prop.source)[1]
            return gg_delta_H(st, par, prop, ctx) + par.α * dx
        end
        f_dir = CPMFunction(dH_dir; temperature = gg_temperature)
        p_dir = merge(p, (; α = 2.0))
        dir_tiny = Oracle.Tiny(dims, vn, vn, [1, 2], Jk, 1.0, 2.0, 4.0, false, 2.0)
        dir_prob = PottsProblem(f_dir, initial_state(reshape(Int32.(σ0), dims), [1, 2]), lat, (0, 1), p_dir;
            proposal = VonNeumann(1), contact = VonNeumann(1))
        ex_dir = Oracle.exact(dir_tiny, σ0, 1, Oracle.sequential_mcs)
        cnt_dir = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(dir_prob; seed), SequentialCPM(); save_start = false).u[end].σ))
            cnt_dir[σ] = get(cnt_dir, σ, 0) + 1
        end
        d_dir, noise_dir = Oracle.tv(ex_dir, cnt_dir, R)
        @test Oracle.chi2_z(ex_dir, cnt_dir, R) < 4.5
        @test d_dir < 2noise_dir
        # Mutant: flipped copy direction (-α) rejected
        dir_mut = remake(dir_prob; p = merge(p, (; α = -2.0)))
        cnt_dir_m = Dict{Vector{Int8}, Int}()
        for seed in 1:R
            σ = vec(Int8.(solve(remake(dir_mut; seed), SequentialCPM(); save_start = false).u[end].σ))
            cnt_dir_m[σ] = get(cnt_dir_m, σ, 0) + 1
        end
        @test Oracle.chi2_z(ex_dir, cnt_dir_m, R) > 4.5
    end
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
