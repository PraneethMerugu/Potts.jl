# The Euler-characteristic tracker (D-192, `src/euler.jl`): ordinary tests (D-048).
# The per-copy Δχ against two from-scratch recounts (an independent one here, and
# `recompute_euler`), on every square and hex shell and sampled cubic shells; the device
# lifecycle's rebuild, fused and staged, on the CPU backend. The model-level acceptance
# (exactness under every integrator, ΔH, observables) is PottsModels'
# `lib/PottsModels/test/acceptance/euler_tracker_tests.jl`.

# Independent recount: χ = Σ_S (−1)^|S| · #cells, a cell being the 2^|S| sites `i + {0,1}^S`
# all in X (`:face`) or a grid face of the closed voxels of X (`:full`, its vertices counted
# by their incident voxels); hex: sites − adjacent pairs + triangles. Closed lattices only.

@testsetup module CP_euler
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates,
    linear_index, shift
include("shared/gg_model.jl")
include("shared/euler.jl")
include("shared/export_all.jl")
end

@testitem "Euler tracker" setup = [CP_euler] tags = [:corepotts, :euler] begin
    @testset "Euler tracker" begin
        @testset "Δχ of a copy equals the recounts (every shell, $geom, $adj)" for (
                geom,
                adj,
            ) in (
                (:square, :face), (:square, :full), (:hex, :face),
                (:hex, :full), (:cubic, :face), (:cubic, :full),
            )
            hex = geom === :hex
            N = geom === :cubic ? 3 : 2
            lat = if hex
                Lattice((5, 5); boundary = Closed(), geometry = Hexagonal())
            else
                Lattice(ntuple(_ -> 5, N); boundary = Closed())
            end
            shell = if hex
                CorePotts._HEX_RING
            elseif N == 2
                CorePotts._EULER_RING2
            else
                CorePotts._CUBIC_SHELL
            end
            K = length(shell)
            x = ntuple(_ -> 3, N)
            masks = if K <= 8
                0:((1 << K) - 1)
            else
                [UInt32((0x9E3779B97F4A7C15 * k) >> 38) for k in 1:800]
            end      # 26-bit, deterministic
            bad_brute = bad_rec = 0
            for m in masks
                σ = zeros(Int32, lat.dims)
                for (k, o) in enumerate(shell)
                    (m >> (k - 1)) & 1 == 1 && (σ[(x .+ o)...] = 1)
                    # another cell round the target
                    (m >> (k - 1)) & 1 == 0 && isodd(k) && (σ[(x .+ o)...] = 2)
                end
                for (old, new) in ((0, 1), (2, 1), (1, 0))
                    σ0 = copy(σ)
                    σ0[x...] = old
                    σ1 = copy(σ)
                    σ1[x...] = new
                    i = linear_index(lat, x)
                    prop = Proposal(i, i, x, 1, Int32(old), Int32(new))
                    δ = euler_change(σ0, (; lattice = lat), prop, Val(adj))
                    # the target is not read
                    @test δ == euler_change(σ1, (; lattice = lat), prop, Val(adj))
                    for c in (old, new)
                        c == 0 && continue
                        want = euler_brute(σ1 .== c, adj, hex) -
                            euler_brute(σ0 .== c, adj, hex)
                        got = c == old ? δ[1] : δ[2]
                        bad_brute += got != want
                        bad_rec += got !=
                            recompute_euler(σ1, lat, Val(adj), 2)[c] -
                            recompute_euler(σ0, lat, Val(adj), 2)[c]
                    end
                end
            end
            @test bad_brute == 0
            @test bad_rec == 0
            # the medium has no entry
            @test euler_change(
                zeros(Int32, lat.dims), (; lattice = lat),
                Proposal(1, 1, x, 1, Int32(0), Int32(0)), Val(adj)
            ) == (Int32(0), Int32(0))
        end

        @testset "a periodic axis of length 1 is rejected (the shell would wrap onto the \
            target)" begin
            # review repro: on (4, 4, 1) periodic the per-copy change reads the target
            # through the wrapped axis, (0, 1) before the write and (0, -1) after, against a
            # recount of 0
            for (lat, ax) in (
                    (Lattice((4, 4, 1)), 3), (Lattice((1, 4)), 1),
                    (Lattice((4, 1); geometry = Hexagonal()), 2),
                )
                σ = zeros(Int32, lat.dims)
                @test_throws ArgumentError recompute_euler(σ, lat, Val(:face), 1)
            end
            # a closed axis of length 1 and a periodic axis of length 2 are fine (the
            # recount and the per-copy change agree)
            lat = Lattice((4, 4, 1); boundary = (Periodic(), Periodic(), Closed()))
            σ = zeros(Int32, 4, 4, 1)
            σ[2, 2, 1] = 1
            @test recompute_euler(σ, lat, Val(:face), 1) == Int32[1]
            lat = Lattice((5, 2))
            σ = zeros(Int32, 5, 2)
            σ[1:3, 1] .= 1
            x = (2, 2)
            i = linear_index(lat, x)
            δ = euler_change(
                σ, (; lattice = lat), Proposal(i, i, x, 1, Int32(0), Int32(1)),
                Val(:face)
            )
            σ1 = copy(σ)
            σ1[x...] = 1
            @test recompute_euler(σ1, lat, Val(:face), 1)[1] -
                recompute_euler(σ, lat, Val(:face), 1)[1] == δ[2]
        end
        @testset "recompute_euler: reference shapes, torus, domain" begin
            lat = Lattice((12, 12); boundary = Closed())
            σ = zeros(Int32, 12, 12)
            σ[6:10, 2:6] .= 1
            σ[7:9, 3:5] .= 0                        # annulus
            σ[2, 9] = 2
            σ[4, 9] = 2
            σ[3, 8] = 2
            σ[3, 10] = 2        # diamond
            @test recompute_euler(σ, lat, Val(:face), 2) == Int32[0, 4]
            @test recompute_euler(σ, lat, Val(:full), 2) == Int32[0, 0]
            torus = Lattice((12, 12); boundary = Periodic())
            σ = zeros(Int32, 12, 12)
            σ[3:4, :] .= 1                   # a band round the torus
            @test recompute_euler(σ, torus, Val(:face), 1) == Int32[0]
            @test recompute_euler(σ, torus, Val(:full), 1) == Int32[0]
            @test recompute_euler(ones(Int32, 6, 6), Lattice((6, 6)), Val(:face), 1) ==
                Int32[0]   # the whole torus
            # a ring round an out-of-domain obstacle has a hole (out of domain is
            # background)
            dom = trues(9, 9)
            dom[5, 5] = false
            σ = zeros(Int32, 9, 9)
            σ[4:6, 4:6] .= 1
            @test recompute_euler(
                σ, Lattice((9, 9); boundary = Closed(), domain = dom),
                Val(:face), 1
            ) ==
                Int32[0]
            @test recompute_euler(σ, Lattice((9, 9); boundary = Closed()), Val(:face), 1) ==
                Int32[1]
            # 3D: a hollow cube 2, a solid ring 0
            σ = zeros(Int32, 6, 6, 6)
            σ[2:4, 2:4, 2:4] .= 1
            σ[3, 3, 3] = 0
            σ[1:3, 1:3, 6] .= 2
            σ[2, 2, 6] = 0
            for adj in (:face, :full)
                @test recompute_euler(
                    σ, Lattice((6, 6, 6); boundary = Closed()), Val(adj),
                    2
                ) ==
                    Int32[2, 0]
            end
        end

        @testset "lifecycle under SequentialCPM" begin
            prob = eu_problem()
            sol = solve(prob, SequentialCPM(); saveat = 1)
            @test sol.stats.lifecycle.divisions >= 2
            @test sum(u -> eu_bad(u.cell, u.ownership, prob.lattice), sol.u) == 0
        end
        @testset "the lifecycle planner forms ($form)" for (form, sites) in (
                (
                    "fused", CheckerboardCPM().fused_lifecycle_max_sites,
                ), ("staged", 0),
            )
            CorePotts._FORCE_FUSED_LIFECYCLE[] = true
            try
                prob = eu_problem()
                integ = init(
                    prob, CheckerboardCPM(; fused_lifecycle_max_sites = sites);
                    saveat = 1
                )
                @test integ.lcache.device isa CorePotts.DeviceLifecycle
                @test (integ.lcache.device.fused! === nothing) == (form == "staged")
                sol = solve!(integ)
                @test sol.stats.lifecycle.divisions >= 2
                @test sum(u -> eu_bad(u.cell, u.ownership, prob.lattice), sol.u) == 0
            finally
                CorePotts._FORCE_FUSED_LIFECYCLE[] = false
            end
        end
    end
end
