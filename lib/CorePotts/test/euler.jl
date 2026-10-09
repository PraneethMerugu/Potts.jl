# The Euler-characteristic tracker (P6.3j, D-192, `src/euler.jl`): ordinary tests (D-048).
# The per-copy Δχ against two from-scratch recounts (an independent one here, and
# `recompute_euler`), on every square and hex shell and sampled cubic shells; the device
# lifecycle's rebuild, fused and staged, on the CPU backend. The model-level acceptance
# (exactness under every integrator, ΔH, observables) is PottsModels' frozen
# `p6_3j_euler_tracker.jl`.

# Independent recount: χ = Σ_S (−1)^|S| · #cells, a cell being the 2^|S| sites `i + {0,1}^S`
# all in X (`:face`) or a grid face of the closed voxels of X (`:full`, its vertices counted
# by their incident voxels); hex: sites − adjacent pairs + triangles. Closed lattices only.
function euler_brute(X::AbstractArray{Bool}, adj, hex::Bool = false)
    N = ndims(X)
    L = size(X)
    g(j) = all(d -> 1 <= j[d] <= L[d], 1:N) && X[j...]
    if hex
        χ = 0
        for I in CartesianIndices(X)
            i = Tuple(I)
            χ += g(i) - sum(g(i) & g(i .+ e) for e in ((1, 0), (0, 1), (-1, 1)))
        end
        for i in Iterators.product(0:L[1], 0:L[2])          # both triangles, anchored left/below too
            χ += (g(i) & g(i .+ (1, 0)) & g(i .+ (0, 1))) + (g(i .+ (1, 0)) & g(i .+ (0, 1)) & g(i .+ (1, 1)))
        end
        return χ
    end
    χ = 0
    spans = Iterators.product(ntuple(_ -> (0, 1), N)...)
    if adj === :face
        for I in CartesianIndices(X), S in spans
            i = Tuple(I)
            all(g(i .+ e) for e in Iterators.product(ntuple(d -> S[d] == 1 ? (0, 1) : (0,), N)...)) &&
                (χ += (-1)^sum(S))
        end
    else
        for v in Iterators.product(ntuple(d -> 1:(L[d] + 1), N)...), S in spans
            any(g(v .- e) for e in Iterators.product(ntuple(d -> S[d] == 1 ? (0,) : (0, 1), N)...)) &&
                (χ += (-1)^sum(S))
        end
    end
    return χ
end

# the device lifecycle's rebuild (zeroed, then summed from σ), on the CPU backend: cells
# divide (cutting holed and fragmented cells) and the columns equal the recount
function eu_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx.lattice, prop)
    commit_euler!(st.cell.euler, prop, euler_change(st.σ, ctx, prop, Val(:face)))
    commit_euler!(st.cell.euler_full, prop, euler_change(st.σ, ctx, prop, Val(:full)))
    return nothing
end
eu_trigger(st, p, ctx, key, mcs, c) = (iseven(mcs) && st.cell.volume[c] >= 24) ? EVENT_DIVIDE : EVENT_NONE
function eu_problem()
    lat = Lattice((24, 20); boundary = (Periodic(), Closed()))
    σ = zeros(Int32, 24, 20)
    σ[2:8, 2:8] .= 1; σ[4:6, 4:6] .= 0; σ[12:17, 3:9] .= 2; σ[5:9, 12:17] .= 3; σ[24, 12:16] .= 4; σ[1:3, 12:16] .= 4
    cell = (; init_moments(σ, lat, 4)..., euler = recompute_euler(σ, lat, Val(:face), 4), euler_full = recompute_euler(σ, lat, Val(:full), 4))
    st = with_capacity(initial_state(σ, Int32[1, 2, 1, 2]; cell), 32)
    f = CPMFunction(gg_delta_H; commit! = eu_commit!, temperature = gg_temperature,
        lifecycle = Lifecycle(eu_trigger; normal = random_plane))
    return PottsProblem(f, st, lat, (0, 16), merge(gg_params(), (; V0 = 30.0, T = 8.0)); contact = Moore(1),
        proposal = Moore(1), seed = 3)
end
eu_bad(cell, σ, lat) = (n = length(cell.kind);
    count(cell.euler .!= recompute_euler(σ, lat, Val(:face), n)) +
    count(cell.euler_full .!= recompute_euler(σ, lat, Val(:full), n)))

@testset "Euler tracker" begin
    @testset "Δχ of a copy equals the recounts (every shell, $geom, $adj)" for (geom, adj) in
                                                                               ((:square, :face), (:square, :full), (:hex, :face), (:hex, :full), (:cubic, :face), (:cubic, :full))
        hex = geom === :hex
        N = geom === :cubic ? 3 : 2
        lat = hex ? Lattice((5, 5); boundary = Closed(), geometry = Hexagonal()) : Lattice(ntuple(_ -> 5, N); boundary = Closed())
        shell = hex ? CorePotts._HEX_RING : N == 2 ? CorePotts._EULER_RING2 : CorePotts._CUBIC_SHELL
        K = length(shell)
        x = ntuple(_ -> 3, N)
        masks = K <= 8 ? (0:((1 << K) - 1)) :
                [UInt32((0x9E3779B97F4A7C15 * k) >> 38) for k in 1:800]      # 26-bit, deterministic
        bad_brute = bad_rec = 0
        for m in masks
            σ = zeros(Int32, lat.dims)
            for (k, o) in enumerate(shell)
                (m >> (k - 1)) & 1 == 1 && (σ[(x .+ o)...] = 1)
                (m >> (k - 1)) & 1 == 0 && isodd(k) && (σ[(x .+ o)...] = 2)     # another cell round the target
            end
            for (old, new) in ((0, 1), (2, 1), (1, 0))
                σ0 = copy(σ); σ0[x...] = old
                σ1 = copy(σ); σ1[x...] = new
                i = linear_index(lat, x)
                prop = Proposal(i, i, x, 1, Int32(old), Int32(new))
                δ = euler_change(σ0, (; lattice = lat), prop, Val(adj))
                @test δ == euler_change(σ1, (; lattice = lat), prop, Val(adj))     # the target is not read
                for c in (old, new)
                    c == 0 && continue
                    want = euler_brute(σ1 .== c, adj, hex) - euler_brute(σ0 .== c, adj, hex)
                    got = c == old ? δ[1] : δ[2]
                    bad_brute += got != want
                    bad_rec += got != recompute_euler(σ1, lat, Val(adj), 2)[c] - recompute_euler(σ0, lat, Val(adj), 2)[c]
                end
            end
        end
        @test bad_brute == 0
        @test bad_rec == 0
        # the medium has no entry
        @test euler_change(zeros(Int32, lat.dims), (; lattice = lat),
            Proposal(1, 1, x, 1, Int32(0), Int32(0)), Val(adj)) == (Int32(0), Int32(0))
    end

    @testset "a periodic axis of length 1 is rejected (the shell would wrap onto the target)" begin
        # review repro: on (4, 4, 1) periodic the per-copy change reads the target through
        # the wrapped axis, (0, 1) before the write and (0, -1) after, against a recount of 0
        for (lat, ax) in ((Lattice((4, 4, 1)), 3), (Lattice((1, 4)), 1),
                          (Lattice((4, 1); geometry = Hexagonal()), 2))
            σ = zeros(Int32, lat.dims)
            err = try
                recompute_euler(σ, lat, Val(:face), 1); nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("euler", sprint(showerror, err)) && occursin("axis $ax", sprint(showerror, err))
        end
        # a closed axis of length 1 and a periodic axis of length 2 are fine (the recount and
        # the per-copy change agree)
        lat = Lattice((4, 4, 1); boundary = (Periodic(), Periodic(), Closed()))
        σ = zeros(Int32, 4, 4, 1); σ[2, 2, 1] = 1
        @test recompute_euler(σ, lat, Val(:face), 1) == Int32[1]
        lat = Lattice((5, 2))
        σ = zeros(Int32, 5, 2); σ[1:3, 1] .= 1
        x = (2, 2); i = linear_index(lat, x)
        δ = euler_change(σ, (; lattice = lat), Proposal(i, i, x, 1, Int32(0), Int32(1)), Val(:face))
        σ1 = copy(σ); σ1[x...] = 1
        @test recompute_euler(σ1, lat, Val(:face), 1)[1] - recompute_euler(σ, lat, Val(:face), 1)[1] == δ[2]
    end
    @testset "recompute_euler: reference shapes, torus, domain" begin
        lat = Lattice((12, 12); boundary = Closed())
        σ = zeros(Int32, 12, 12)
        σ[6:10, 2:6] .= 1; σ[7:9, 3:5] .= 0                        # annulus
        σ[2, 9] = 2; σ[4, 9] = 2; σ[3, 8] = 2; σ[3, 10] = 2        # diamond
        @test recompute_euler(σ, lat, Val(:face), 2) == Int32[0, 4]
        @test recompute_euler(σ, lat, Val(:full), 2) == Int32[0, 0]
        torus = Lattice((12, 12); boundary = Periodic())
        σ = zeros(Int32, 12, 12); σ[3:4, :] .= 1                   # a band round the torus
        @test recompute_euler(σ, torus, Val(:face), 1) == Int32[0]
        @test recompute_euler(σ, torus, Val(:full), 1) == Int32[0]
        @test recompute_euler(ones(Int32, 6, 6), Lattice((6, 6)), Val(:face), 1) == Int32[0]   # the whole torus
        # a ring round an out-of-domain obstacle has a hole (out of domain is background)
        dom = trues(9, 9); dom[5, 5] = false
        σ = zeros(Int32, 9, 9); σ[4:6, 4:6] .= 1
        @test recompute_euler(σ, Lattice((9, 9); boundary = Closed(), domain = dom), Val(:face), 1) == Int32[0]
        @test recompute_euler(σ, Lattice((9, 9); boundary = Closed()), Val(:face), 1) == Int32[1]
        # 3D: a hollow cube 2, a solid ring 0
        σ = zeros(Int32, 6, 6, 6); σ[2:4, 2:4, 2:4] .= 1; σ[3, 3, 3] = 0; σ[1:3, 1:3, 6] .= 2; σ[2, 2, 6] = 0
        for adj in (:face, :full)
            @test recompute_euler(σ, Lattice((6, 6, 6); boundary = Closed()), Val(adj), 2) == Int32[2, 0]
        end
    end

    @testset "host lifecycle rebuild (SequentialCPM)" begin
        prob = eu_problem()
        sol = solve(prob, SequentialCPM(); saveat = 1)
        @test sol.stats.lifecycle.divisions >= 2
        @test sum(u -> eu_bad(u.cell, u.σ, prob.lattice), sol.u) == 0
    end
    @testset "device lifecycle on the CPU backend ($form)" for (form, sites) in (("fused", CorePotts.FUSE_SITES[]), ("staged", 0))
        fuse = CorePotts.FUSE_SITES[]
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        CorePotts.FUSE_SITES[] = sites
        try
            prob = eu_problem()
            integ = init(prob, CheckerboardCPM(); saveat = 1)
            @test integ.lcache.device isa CorePotts.DeviceLifecycle
            @test (integ.lcache.device.fused! === nothing) == (form == "staged")
            sol = solve!(integ)
            @test sol.stats.lifecycle.divisions >= 2
            @test sum(u -> eu_bad(u.cell, u.σ, prob.lattice), sol.u) == 0
        finally
            CorePotts.FUSE_SITES[] = fuse
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        end
    end
end
