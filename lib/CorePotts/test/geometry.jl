# Moment trackers, shape descriptors and site trackers (ROADMAP M2.2).
using LinearAlgebra: eigvals, Symmetric

"""Brute-force geometry of cell c: unwrapped around its first site (cells < half box)."""
function brute_geometry(σ, lat::Lattice{N}, c) where {N}
    sites = [coordinates(lat, i) for i in 1:nsites(lat) if σ[i] == c]
    ref = first(sites)
    X = [collect(ref .+ min_image(lat, x, ref)) for x in sites]
    μ = sum(X) / length(X)
    C = sum((x - μ) * (x - μ)' for x in X) / length(X)
    wrapped = ntuple(d -> lat.periodic[d] ? mod(μ[d] - 1, lat.dims[d]) + 1 : μ[d], N)
    return wrapped, C
end
upper(C, N) = Tuple(C[d, e] for d in 1:N for e in d:N)

function gm_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx.lattice, prop)
end
const GM = CPMFunction(gg_delta_H; commit! = gm_commit!, temperature = gg_temperature)
moment_state(σ, kinds, lat) = initial_state(σ, kinds; cell = init_moments(σ, lat, length(kinds)))

@testset "geometry" begin
    @testset "minimum image" begin
        l = Lattice((10, 9); boundary = (Periodic(), Periodic()))
        @test min_image(l, (6, 1), (1, 1)) == (5, 0)          # tie at +n/2 stays +
        @test min_image(l, (1, 1), (6, 1)) == (5, 0)          # −n/2 resolves to +
        @test min_image(l, (7, 1), (1, 1)) == (-4, 0)
        @test min_image(l, (1, 6), (1, 1)) == (0, -4)         # odd axis: range −4:4
        @test min_image(l, (1, 5), (1, 1)) == (0, 4)
        c = Lattice((10, 10); boundary = Closed())
        @test min_image(c, (10, 1), (1, 1)) == (9, 0)         # closed axes never wrap
    end

    @testset "trackers match brute force after runs ($(length(dims))-D, $(nameof(typeof(alg))))" for (
            dims, alg) in (((40, 40), SequentialCPM()), ((40, 40), CheckerboardCPM()),
            ((14, 14, 14), SequentialCPM()), ((14, 14, 14), CheckerboardCPM()))
        σ, kinds = blocks(dims, length(dims) == 2 ? 6 : 4)
        σ = circshift(σ, ntuple(_ -> 3, length(dims)))      # cells straddle the seams
        lat = Lattice(dims)
        p = merge(gg_params(), (; V0 = length(dims) == 2 ? 36.0 : 64.0))
        mprob = CPMProblem(GM, moment_state(σ, kinds, lat), lat, (0, 40), p)
        u = solve(mprob, alg).u[end]
        @test u.σ != σ
        for c in eachindex(kinds)
            u.cell.volume[c] > 0 || continue
            μ, C = brute_geometry(u.σ, lat, c)
            @test all(isapprox.(centroid(u.cell, lat, c), μ; atol = 1e-9))
            @test all(isapprox.(covariance(Float64, u.cell, c, Val(length(dims))),
                upper(C, length(dims)); atol = 1e-9))
            λ = sort(eigvals(Symmetric(C)); rev = true)
            @test all(isapprox.(principal_moments(upper(C, length(dims))), λ; atol = 1e-9))
        end
        # sums stay small: re-centring keeps every mean offset within RECENTER
        @test all(abs.(u.cell.m1) .<= 2 .* max.(u.cell.volume', 1))
    end

    @testset "shape descriptors" begin
        lat = Lattice((60, 60))
        σ = zeros(Int32, 60, 60)
        σ[11:30, 21:25] .= 1                                   # 20 × 5 rectangle
        cell = merge(init_moments(σ, lat, 1), (; volume = Int32[100]))
        s = shape(cell, lat, 1)
        @test covariance(Float64, cell, 1, Val(2)) == ((20^2 - 1) / 12, 0.0, (5^2 - 1) / 12)
        @test s.elongation ≈ sqrt((20^2 - 1) / (5^2 - 1))
        @test s.major_length ≈ 4sqrt((20^2 - 1) / 12)
        @test abs(s.orientation) < 1e-12                       # along x
        @test shape(merge(cell, (; anchor = cell.anchor)), lat, 1).eccentricity ≈
              sqrt(1 - (5^2 - 1) / (20^2 - 1))
        σ2 = permutedims(σ)                                    # along y
        cell2 = merge(init_moments(σ2, lat, 1), (; volume = Int32[100]))
        @test shape(cell2, lat, 1).orientation ≈ π / 2
        # 3D box a × b × c: semiaxes √(5(n²−1)/12)
        l3 = Lattice((30, 30, 30))
        σ3 = zeros(Int32, 30, 30, 30)
        σ3[1:12, 1:6, 1:3] .= 1                                # straddles nothing, closed-free
        σ3 = circshift(σ3, (-4, -2, -1))                       # now straddles every seam
        cell3 = merge(init_moments(σ3, l3, 1), (; volume = Int32[216]))
        s3 = shape(cell3, l3, 1)
        @test all(isapprox.(s3.semiaxes, sqrt.(5 .* ((12, 6, 3) .^ 2 .- 1) ./ 12)))
        @test s3.elongation ≈ sqrt((12^2 - 1) / (3^2 - 1))
        @test all(isapprox.(centroid(cell3, l3, 1), mod.((6.5, 3.5, 2.0) .- (4, 2, 1) .- 1, 30) .+ 1))
    end

    @testset "centroid_shift equals the committed centroid change" begin
        σ, kinds = blocks((30, 30), 5; gap = 0)
        σ = circshift(σ, (2, 2))
        lat = Lattice((30, 30))
        st = moment_state(σ, kinds, lat)
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat), contact = relation(Moore(1), lat))
        n = 0
        for t in 1:nsites(lat), dir in 1:4
            inside, y = shift(lat, coordinates(lat, t), ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            a, b = st.σ[t], st.σ[s]
            (a != b && a != 0 && b != 0) || continue
            prop = Proposal(t, s, coordinates(lat, t), dir, a, b)
            δa = centroid_shift(Float64, st.cell, lat, a, prop.x, -1)
            δb = centroid_shift(Float64, st.cell, lat, b, prop.x, +1)
            ca, cb = centroid(st.cell, lat, a), centroid(st.cell, lat, b)
            after = deepcopy(st); after.σ[t] = b
            gm_commit!(after, nothing, prop, ctx)
            wrapdiff(u, v) = map((x, y, m) -> mod(x - y + m / 2, m) - m / 2, u, v, lat.dims)
            @test all(isapprox.(wrapdiff(centroid(after.cell, lat, a), ca), δa; atol = 1e-12))
            @test all(isapprox.(wrapdiff(centroid(after.cell, lat, b), cb), δb; atol = 1e-12))
            (n += 1) >= 60 && break
        end
        @test n >= 30
    end

    @testset "site sum and minimum trackers" begin
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        v = Float64[i + 0.5j for i in 1:30, j in 1:30]
        vmin = fill(Inf, length(kinds))
        recompute_site_min!(vmin, falses(length(kinds)), σ, v; all = true)
        st = initial_state(σ, kinds; cell = (; vsum = recompute_site_sum(σ, v, length(kinds)),
            vmin, stale = falses(length(kinds))))
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            commit_site_sum!(st.cell.vsum, prop, v[prop.target]);
            commit_site_min!(st.cell.vmin, st.cell.stale, prop, v[prop.target]))
        f = CPMFunction(gg_delta_H; commit!, temperature = gg_temperature)
        u = solve(CPMProblem(f, st, lat, (0, 10), gg_params()), SequentialCPM()).u[end]
        @test u.cell.vsum ≈ recompute_site_sum(u.σ, v, length(kinds))
        truth = recompute_site_min!(fill(Inf, length(kinds)), falses(length(kinds)), u.σ, v; all = true)
        @test all(u.cell.vmin[.!u.cell.stale] .== truth[.!u.cell.stale])   # exact unless stale
        @test all(u.cell.vmin .<= truth)                                    # stale ⇒ lower bound
        recompute_site_min!(u.cell.vmin, u.cell.stale, u.σ, v)
        @test u.cell.vmin == truth

        # structured (vector-valued) owner sums use the same tracker with any additive type
        w = [SVector(Float64(i), Float64(j), 1.0) for i in 1:30, j in 1:30]
        st2 = initial_state(σ, kinds; cell = (; wsum = recompute_site_sum(σ, w, length(kinds))))
        c2!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            commit_site_sum!(st.cell.wsum, prop, w[prop.target]))
        f2 = CPMFunction(gg_delta_H; commit! = c2!, temperature = gg_temperature)
        u2 = solve(CPMProblem(f2, st2, lat, (0, 10), gg_params()), CheckerboardCPM()).u[end]
        @test u2.cell.wsum ≈ recompute_site_sum(u2.σ, w, length(kinds))
        @test getindex.(u2.cell.wsum, 3) == u2.cell.volume
    end
end
