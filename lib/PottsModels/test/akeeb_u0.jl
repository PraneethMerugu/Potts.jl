# Akeeb initial state: leaders and followers keep their kinds through the problem's u0 and a
# sweep (paper audit 2026-10-13, item 10). `akeeb_observables(prob.u0) == o` on the
# published start cannot catch a leader/follower swap there: every count is 0 and both
# areas are 0 whatever the kinds. Here leaders and followers are counted separately (the
# state method reads kind code 1 as the leader), and the observables are taken on states
# where a swap changes them.
using Test, Potts, PottsModels

# leaders and followers among the live cells of a state, by kind code (1 leader, 2 follower)
function akeeb_u0_counts(u)
    k, v = Array(u.cell.kind), Array(u.cell.volume)
    live = findall(>(0), v)
    return (; leaders = count(c -> k[c] == 1, live), followers = count(c -> k[c] == 2, live))
end

@testset "Akeeb u0: leader and follower kinds survive (no swap)" begin
    @testset "hand-built 12×8" begin
        # follower slab (cell 1) on y = 1:2; a lone leader (2) at y = 6; a group of two
        # followers and a leader (3, 4, 5) at y = 6. Two leaders and three followers, so a
        # swap changes both counts; the lone cell is a single only if it is a leader.
        σ = zeros(Int, 12, 8)
        σ[:, 1:2] .= 1
        σ[3, 6] = 2
        σ[8, 6] = 3
        σ[9, 6] = 4
        σ[10, 6] = 5
        cue = [Float64(y - 1) for x in 1:12, y in 1:8]
        op(kinds) = [ownership => σ, kind => kinds, :clock => fill(-1.0, 5),
            :rate => [k === :leader ? 0.0 : 0.015 for k in kinds], :cue => cue]
        sys = AkeebInvasion(; name = :akeeb_u0, lattice = (12, 8))
        good = [:follower, :leader, :follower, :follower, :leader]
        u = PottsProblem(sys, op(good), (0, 1); capacity = 16).u0
        @test akeeb_u0_counts(u) == (; leaders = 2, followers = 3)
        @test Array(u.cell.kind)[1:5] == [2, 1, 2, 2, 1]
        o = akeeb_observables(u)
        @test (o.singles, o.detached, o.clusters) == (1, 4, 1)
        @test o.cluster_leaders == [1] && o.cluster_followers == [2]
        # negative control: the swapped state fails the same assertions
        bad = [k === :leader ? :follower : :leader for k in good]
        w = PottsProblem(sys, op(bad), (0, 1); capacity = 16).u0
        @test akeeb_u0_counts(w) == (; leaders = 3, followers = 2)
        @test akeeb_u0_counts(w) != (; leaders = 2, followers = 3)
        ow = akeeb_observables(w)
        @test ow.singles == 0 && ow.cluster_leaders == [2] && ow.cluster_followers == [1]
    end

    @testset "akeeb_state after 1 MCS (99×60)" begin
        op = akeeb_state(; lattice = (99, 60))
        kinds = op[2].second
        nl, nf = count(==(:leader), kinds), count(==(:follower), kinds)
        @test nl != nf                                    # so a swap changes both counts
        sys = AkeebInvasion(; name = :akeeb_u0_swept, lattice = (99, 60))
        prob = PottsProblem(sys, op, (0, 1); capacity = 1000)
        @test akeeb_u0_counts(prob.u0) == (; leaders = nl, followers = nf)
        u = solve(prob, SequentialCPM(; proposal = VonNeumann(1))).u[end]
        @test akeeb_u0_counts(u) == (; leaders = nl, followers = nf)   # no extinction, no division in 1 MCS
        # each id keeps the kind it was given
        @test all(c -> Array(u.cell.kind)[c] == (kinds[c] === :leader ? 1 : 2), eachindex(kinds))
        # negative control: the same state with the kinds swapped fails the count
        swapped = [k === :leader ? :follower : :leader for k in kinds]
        rates = [k === :leader ? 0.0 : 0.015 for k in swapped]
        clocks = [k === :leader ? -1.0 : c for (k, c) in zip(swapped, op[3].second)]
        opw = [op[1], kind => swapped, :clock => clocks, :rate => rates, op[5]]
        uw = PottsProblem(sys, opw, (0, 1); capacity = 1000).u0
        @test akeeb_u0_counts(uw) == (; leaders = nf, followers = nl)
        @test akeeb_u0_counts(uw) != (; leaders = nl, followers = nf)
    end
end
