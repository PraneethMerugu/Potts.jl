using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, colors, color_site,
    ncolorsites, coordinates, linear_index, shift

# ---------------------------------------------------------------------------------------
# A hand-written Graner–Glazier model (what the symbolic layer will generate).

kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function gg_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
gg_temperature(st, p, prop, ctx) = p.T
const GG = CPMFunction(gg_delta_H; temperature = gg_temperature)
gg_params(T = Float64) = (; J = SMatrix{3, 3, T}(0, 16, 16, 16, 2, 11, 16, 11, 14),
    λ = T(1), V0 = T(40), T = T(10))

"""Blocky initial condition with cells of `side` sites per axis and alternating kinds."""
function blocks(dims::NTuple{N}, side; gap = 1) where {N}
    σ = zeros(Int32, dims)
    id = 0
    kinds = Int32[]
    for c in CartesianIndices(ntuple(d -> 1:(side + gap):(dims[d] - side + 1), N))
        id += 1
        push!(kinds, isodd(id) ? 1 : 2)
        σ[ntuple(d -> c[d]:(c[d] + side - 1), N)...] .= id
    end
    return σ, kinds
end

# Independent oracle: total H by brute force, each unordered contact pair counted once.
function total_H(st, lat, contact, p)
    H = 0.0
    k(c) = c == 0 ? 1 : Int(st.cell.kind[c]) + 1
    for i in 1:nsites(lat)
        x = coordinates(lat, i)
        for off in contact.offsets
            inside, y = shift(lat, x, off)
            inside || continue
            a, b = st.σ[i], st.σ[linear_index(lat, y)]
            a != b && (H += p.J[k(a), k(b)] / 2)
        end
    end
    vol = zeros(Int, length(st.cell.kind))
    for s in st.σ
        s > 0 && (vol[s] += 1)
    end
    return H + sum(p.λ * (v - p.V0)^2 for v in vol)
end

# Graner–Glazier plus a surface (perimeter) constraint over a possibly weighted relation.
function gs_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    S(s, c) = p.λs * (s - p.S0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
           surface_delta(st.cell.surface, prop,
               surface_change(st.σ, ctx, prop; T = eltype(st.cell.surface)), S)
end
function gs_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_surface!(st.cell.surface, prop,
        surface_change(st.σ, ctx, prop; T = eltype(st.cell.surface)))
end
const GS = CPMFunction(gs_delta_H; commit! = gs_commit!, temperature = gg_temperature)
gs_params() = merge(gg_params(), (; λs = 0.5, S0 = 20.0))

function brute_surface(σ, lat, r, ncell)
    S = zeros(Float64, ncell)
    for i in 1:nsites(lat), (k, off) in enumerate(r.offsets)
        c = σ[i]
        inside, y = shift(lat, coordinates(lat, i), off)
        (c != 0 && inside && σ[linear_index(lat, y)] != c) || continue
        S[c] += r.weights === nothing ? 1.0 : Float64(r.weights[k])
    end
    return S
end
function total_H_surface(st, lat, ctx, p)
    H = 0.0
    k(c) = c == 0 ? 1 : Int(st.cell.kind[c]) + 1
    r = ctx.contact
    for i in 1:nsites(lat), (j, off) in enumerate(r.offsets)
        inside, y = shift(lat, coordinates(lat, i), off)
        inside || continue
        a, b = st.σ[i], st.σ[linear_index(lat, y)]
        w = r.weights === nothing ? 1.0 : Float64(r.weights[j])
        a != b && (H += w * p.J[k(a), k(b)] / 2)
    end
    n = length(st.cell.kind)
    vol = [count(==(c), st.σ) for c in 1:n]
    S = brute_surface(st.σ, lat, ctx.surface, n)
    return H + sum(p.λ * (v - p.V0)^2 for v in vol) + sum(p.λs * (s - p.S0)^2 for s in S)
end
surface_state(σ, kinds, lat, r; T = Float64) = initial_state(σ, kinds;
    cell = (; surface = recompute_surface(σ, lat, relation(r, lat), length(kinds); T)))

@testset "CorePotts" begin
    @testset "relations" begin
        l2 = Lattice((20, 20)); l3 = Lattice((12, 12, 12))
        @test length(relation(VonNeumann(1), l2)) == 4
        @test length(relation(VonNeumann(1), l3)) == 6
        @test length(relation(Moore(1), l2)) == 8
        @test length(relation(Moore(1), l3)) == 26
        @test length(relation(Moore(1; include_self = true), l2)) == 9
        # CompuCell3D NeighborOrder counts (cumulative distance shells)
        @test [length(relation(NeighborOrder(k), l2)) for k in 1:6] == [4, 8, 12, 20, 24, 28]
        @test [length(relation(NeighborOrder(k), l3)) for k in 1:6] == [6, 18, 26, 32, 56, 80]
        # canonical order: nondecreasing squared length
        r = relation(NeighborOrder(4), l2)
        @test issorted([sum(abs2, o) for o in r.offsets])
        # aliasing on small periodic axes is rejected; closed axes are fine
        @test_throws ArgumentError relation(Moore(1), Lattice((2, 10)))
        @test length(relation(Moore(1), Lattice((2, 10); boundary = Closed()))) == 8
        @test length(relation(Ball(1.5), l2)) == 8
        @test length(relation(Stencil([(1, 0), (0, 1)]), l2)) == 2
    end

    @testset "rng" begin
        # (seed, replica) tuples never collide (the XOR-key bug)
        @test RNGKey(1, 2) != RNGKey(2, 1)
        @test RNGKey(1, 0) != RNGKey(0, 1)
        @test RNGKey(7) == RNGKey(7, 0, 0)
        for T in (Float32, Float64)
            @test 0 < uniform(T, 0x00000000) < uniform(T, typemax(UInt32)) < 1
        end
        @test extrema(bounded(rand(UInt32), 6) for _ in 1:10_000) == (0, 5)
        @test stream_id("a.b") == stream_id(:var"a.b") != stream_id("a.c")
        k = RNGKey(3)
        s = UInt32(1)
        @test draw(k, 1, 2, s) == draw(k, 1, 2, s) != draw(k, 1, 3, s)
        @test draw(k, 1, 2, s) != draw(k, 1, 2, s + 0x1) != draw(k, 1, 2, s, 1)
        xs = [uniform(Float64, draw(k, 0, i, UInt32(7))[1]) for i in 1:100_000]
        @test abs(mean(xs) - 0.5) < 0.005 && abs(var(xs) - 1 / 12) < 0.002
    end

    @testset "coloring is conflict free" begin
        for (dims, bnd, s) in (((12, 12), Periodic(), 2), ((13, 11), Periodic(), 2),
                ((13, 7), Periodic(), 3), ((10, 9), Closed(), 3), ((7, 5, 6), Periodic(), 2),
                ((4, 17), Periodic(), 5))
            lat = Lattice(dims; boundary = bnd)
            seen = zeros(Int, dims)
            for c in colors(lat, s)
                sites = [color_site(c, j) for j in 1:ncolorsites(c)]
                for x in sites
                    seen[x...] += 1
                end
                for i in eachindex(sites), j in (i + 1):length(sites)
                    x, y = sites[i], sites[j]
                    dist = maximum(ntuple(length(dims)) do d
                        δ = abs(x[d] - y[d])
                        lat.periodic[d] ? min(δ, dims[d] - δ) : δ
                    end)
                    @test dist >= s
                end
            end
            @test all(==(1), seen)          # every site in exactly one color
        end
    end

    @testset "ΔH equals brute-force energy difference ($N-D, $spec)" for (N, dims, spec) in (
            (2, (24, 24), Moore(1)), (2, (24, 21), NeighborOrder(3)),
            (3, (12, 12, 12), Moore(1)), (3, (10, 10, 10), NeighborOrder(2)))
        σ, kinds = blocks(dims, 3)
        lat = Lattice(dims)
        st = initial_state(σ, kinds)
        p = merge(gg_params(), (; V0 = 20.0))
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat),
            contact = relation(spec, lat))
        checked = 0
        for t in 1:nsites(lat), dir in 1:length(ctx.proposal)
            x = coordinates(lat, t)
            inside, y = shift(lat, x, ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            a, b = st.σ[t], st.σ[s]
            (inside && a != b) || continue
            prop = Proposal(t, s, x, dir, a, b)
            before = total_H(st, lat, ctx.contact, p)
            dH = gg_delta_H(st, p, prop, ctx)
            after_state = deepcopy(st)
            after_state.σ[t] = b
            CorePotts.commit_volume!(after_state, p, prop, ctx)
            @test dH ≈ total_H(after_state, lat, ctx.contact, p) - before atol = 1e-9
            checked += 1
            checked >= 300 && break
        end
        @test checked >= 100
    end

    invdist(o) = 1 / sqrt(sum(abs2, o))
    @testset "ΔH with surface, weighted contact ($(length(dims))-D, $cspec, $sspec)" for (
            dims, cspec, sspec) in (
            ((20, 20), Moore(1), VonNeumann(1)),
            ((20, 18), Weighted(NeighborOrder(2), invdist), Moore(1)),
            ((10, 10, 10), Weighted(Moore(1), invdist), Weighted(NeighborOrder(2), invdist)),
            ((12, 12, 11), VonNeumann(1), Moore(1)))
        σ, kinds = blocks(dims, 3)
        lat = Lattice(dims; boundary = length(dims) == 2 ? Periodic() : (Periodic(), Closed(), Periodic()))
        st = surface_state(σ, kinds, lat, sspec)
        p = gs_params()
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat),
            contact = relation(cspec, lat), surface = relation(sspec, lat))
        @test st.cell.surface ≈ brute_surface(st.σ, lat, ctx.surface, length(kinds))
        st32 = surface_state(σ, kinds, lat, sspec; T = Float32)
        checked = 0
        for t in 1:7:nsites(lat), dir in 1:length(ctx.proposal)
            inside, y = shift(lat, coordinates(lat, t), ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            (inside && st.σ[t] != st.σ[s]) || continue
            prop = Proposal(t, s, coordinates(lat, t), dir, st.σ[t], st.σ[s])
            before = total_H_surface(st, lat, ctx, p)
            dH = gs_delta_H(st, p, prop, ctx)
            after = deepcopy(st)
            after.σ[t] = prop.new
            gs_commit!(after, p, prop, ctx)          # after the write, as the algorithms do
            @test dH ≈ total_H_surface(after, lat, ctx, p) - before atol = 1e-6
            @test after.cell.surface ≈ brute_surface(after.σ, lat, ctx.surface, length(kinds))
            @test gs_delta_H(st32, p, prop, ctx) ≈ dH rtol = 1e-5 atol = 1e-2   # Float32 tracker
            checked += 1
            checked >= 150 && break
        end
        @test checked >= 50
    end

    @testset "surface trackers survive a run ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        sspec = Weighted(Moore(1), invdist)
        sprob = CPMProblem(GS, surface_state(σ, kinds, lat, sspec), lat, (0, 30), gs_params();
            relations = (; surface = sspec))
        sol = solve(sprob, alg)
        @test sol.retcode == ReturnCode.Success
        u = sol.u[end]
        @test u.σ != σ
        @test u.cell.surface ≈ brute_surface(u.σ, lat, relation(sspec, lat), length(kinds)) rtol = 1e-12
        bad = CPMProblem(GS, sprob.u0, lat, (0, 1), gs_params();
            relations = (; surface = Moore(1; include_self = true)))
        @test_throws ArgumentError init(bad, alg)
    end

    σ0, kinds0 = blocks((36, 36), 5)
    lat = Lattice((36, 36))
    prob = CPMProblem(GG, initial_state(σ0, kinds0), lat, (0, 20), gg_params(); seed = 7)

    for alg in (SequentialCPM(), CheckerboardCPM(), CheckerboardCPM(; proposal = Moore(1)))
        @testset "$(nameof(typeof(alg))) with $(typeof(alg.proposal))" begin
            sol = solve(prob, alg; saveat = [5, 10])
            @test sol.retcode == ReturnCode.Success
            @test sol.t == [0, 5, 10, 20]
            last_state = sol.u[end]
            @test last_state.σ != σ0
            vol = zeros(Int32, length(kinds0))
            for s in last_state.σ
                s > 0 && (vol[s] += 1)
            end
            @test vol == last_state.cell.volume            # tracker == recomputation
            @test solve(prob, alg).u[end].σ == last_state.σ             # same seed, same run
            @test solve(remake(prob; seed = 8), alg).u[end].σ != last_state.σ
            @test sol(10).σ == sol.u[3].σ
            @test sol.u[1].σ == σ0 && sol.u[2].σ != sol.u[end].σ     # snapshots, not aliases
            @test sol.u[1].σ !== sol.u[end].σ
            @test_throws ArgumentError sol(11)
            @test sol.stats.attempts == 20 * nsites(lat)
        end
    end

    @testset "warm step allocation and recompilation" begin
        integ = init(prob, SequentialCPM(); save_start = false)
        step!(integ)
        @test @allocated(step!(integ)) == 0
        integ = init(prob, CheckerboardCPM(); save_start = false)
        step!(integ); step!(integ)
        @test @allocated(step!(integ)) < 20_000
        solve(remake(prob; p = gg_params(), seed = 1), CheckerboardCPM())
        cold = merge(gg_params(), (; T = 4.0, λ = 2.0))
        stats = @timed solve(remake(prob; p = cold, seed = 2), CheckerboardCPM())
        @test stats.compile_time == 0
        stats = @timed solve(remake(prob; p = cold, seed = 3), SequentialCPM())
        @test stats.compile_time == 0
    end

    @testset "claim buffer is clean at every color (odd color count)" begin
        lat13 = Lattice((13, 13))                     # 3 classes per axis at stride 2 → 9 colors
        σ, k = blocks((13, 13), 3)
        oprob = CPMProblem(GG, initial_state(σ, k), lat13, (0, 10), gg_params())
        integ = init(oprob, CheckerboardCPM(); save_start = false)
        @test isodd(length(integ.cache.colors))
        for _ in 1:4
            step!(integ)
            @test all(iszero, integ.cache.claims[integ.cache.buffer[]])
        end
    end

    @testset "non-finite ΔH fails the solve" begin
        bad = CPMFunction((st, p, prop, ctx) -> NaN; temperature = gg_temperature)
        bprob = CPMProblem(bad, initial_state(σ0, kinds0), lat, (0, 3), gg_params())
        @test solve(bprob, SequentialCPM()).retcode == ReturnCode.Failure
        @test solve(bprob, CheckerboardCPM()).retcode == ReturnCode.Failure
    end

    @testset "checkerboard and sequential sort alike" begin
        # differential adhesion: heterotypic fraction falls under both dynamics
        function hetero(st)
            u = c = 0
            for i in 1:nsites(lat), off in relation(Moore(1), lat).offsets
                inside, y = shift(lat, coordinates(lat, i), off)
                a, b = st.σ[i], st.σ[linear_index(lat, y)]
                (a == b || a == 0 || b == 0) && continue
                c += 1; u += st.cell.kind[a] != st.cell.kind[b]
            end
            return u / c
        end
        σr = zeros(Int32, 36, 36)
        for i in 0:5, j in 0:5
            σr[(6i + 1):(6i + 6), (6j + 1):(6j + 6)] .= 6i + j + 1
        end
        kr = Int32[isodd(i + (i ÷ 6)) ? 1 : 2 for i in 1:36]
        sprob = CPMProblem(GG, initial_state(σr, kr), lat, (0, 60),
            merge(gg_params(), (; V0 = 36.0)))
        h0 = hetero(initial_state(σr, kr))
        hs = [hetero(solve(remake(sprob; seed), SequentialCPM()).u[end]) for seed in 1:4]
        hc = [hetero(solve(remake(sprob; seed), CheckerboardCPM()).u[end]) for seed in 1:4]
        @test mean(hs) < h0 - 0.05
        @test mean(hc) < h0 - 0.05
    end
end

include("geometry.jl")
include("phases.jl")
include("fields.jl")
include("drives.jl")
include("spatial.jl")
include("lifecycle.jl")
include("relationships.jl")
include("compartments.jl")
include("checkpoint.jl")
include("oracle.jl")
include("sciml.jl")
get(ENV, "COREPOTTS_GPU", "") == "metal" && include("gpu.jl")
get(ENV, "COREPOTTS_QA", "true") == "true" && include("qa.jl")
