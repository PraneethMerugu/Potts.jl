# PottsModels: every model builds, compiles and runs, and its derived ΔH matches the brute-
# force energy difference; mechanism tests (mechanisms.jl) check what each model is for.
using Test, Potts, PottsModels, Aqua
using Potts: CorePotts
using Statistics: mean

function selfcheck(prob; n = 200)
    sol = solve(remake(prob; tspan = (0, 3)), SequentialCPM(; proposal = Moore(1)))
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CorePotts.relation(Moore(1), lat)
    worst = 0.0
    for u in sol.u, i in 1:n
        t = mod1(i * 7919, length(u.σ)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[mod1(i, length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.σ[t], u.σ[s])
        a = deepcopy(u); a.σ[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx)
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end

@testset "PottsModels" begin
    σ, kinds = graner_glazier_state()
    @test size(σ) == (72, 72) && length(kinds) == 64 && size(first(graner_glazier_state(2))) == (144, 144)
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    cases = [
        ("Graner–Glazier", GranerGlazier(; name = :gg), [ownership => σ, kind => kinds]),
        ("Wortel Act", WortelAct(; name = :act, lattice = (8, 8)), [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]]),
        ("Wortel Act (connected)", WortelAct(; name = :act, lattice = (8, 8), connected = true),
            [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]]),
        ("Merks", MerksVasculogenesis(; name = :merks, lattice = (8, 8)), [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]],
            (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
        ("single-division fixture", SingleDivisionFixture(; name = :fixture), [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]]),
        ("OpenVT growing monolayer", OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24))),
    ]
    @testset "$label" for (label, sys, op, kw...) in cases
        prob = PottsProblem(sys, op, (0, 10); get(kw, 1, (;))...)
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
        @test Symbol(sol.retcode) === :Success
        u = sol.u[end]
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
    end
    @testset "Akeeb invasion (99×60)" begin
        op = akeeb_state(; lattice = (99, 60))
        n0 = length(op[2].second)
        @test count(==(:follower), op[2].second) == 231 && 70 <= count(==(:leader), op[2].second) <= 77
        # 300 MCS: about 1 in 4 state seeds has no division by MCS 200 (MersenneTwister and
        # StableRNG states alike, 120 seeds each); by 300 every seed has divided
        # a layout carries no lattice (D-091): on a wider lattice the 99-wide slab is painted
        # and the rest stays medium
        wide = layout(akeeb_layout(; lattice = (99, 60)), (500, 300))[1].second
        @test all(>(0), wide[1:99, 1:21]) && all(==(0), wide[100:end, :]) && all(==(0), wide[:, 22:end])
        @test_throws ArgumentError layout(akeeb_layout(; lattice = (99, 60)), (99, 60, 4)) # 3D
        @test_throws ArgumentError akeeb_layout(; lattice = (99, 20))                      # below the slab
        prob = PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), op, (0, 300); capacity = 1000)
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = VonNeumann(1)))
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions > 0
        @test all(>(0), u.cell.volume[1:n0])                                             # no extinction
        @test all(c -> u.cell.clock[c] >= 0 || u.cell.clock[c] == -1, 1:n0)
        p0 = remake(prob; u0 = akeeb_state(; lattice = (99, 60), pp = 0.0))
        @test solve(p0, SequentialCPM(; proposal = VonNeumann(1))).stats.lifecycle.divisions == 0
        @test akeeb_contacts(-2.0)[2, 3] == akeeb_contacts(-2.0)[3, 2] == -2.0
    end
    @testset "graner_glazier_aggregate margin" begin
        for margin in (0, 10, 30)
            σm, km = graner_glazier_aggregate(200; seed = 1, margin)
            occupied = σm .!= 0
            rows = findall(vec(any(occupied; dims = 2))); cols = findall(vec(any(occupied; dims = 1)))
            @test length(km) == 200 && size(σm, 1) == size(σm, 2)
            # at least `margin` medium rows and columns on every side: a gap of ≥ 2margin to the periodic image
            @test first(rows) > margin && first(cols) > margin
            @test last(rows) <= size(σm, 1) - margin && last(cols) <= size(σm, 2) - margin
        end
        # the lattice grows by exactly twice the change of margin; the default is 10
        @test size(graner_glazier_aggregate(200; seed = 1, margin = 30)[1], 1) ==
              size(graner_glazier_aggregate(200; seed = 1)[1], 1) + 40
        @test_throws ArgumentError graner_glazier_aggregate(200; seed = 1, margin = -1)
    end
    @testset "Akeeb seeding emulates the authors' CC3D loop (D-068, spec 10 §5.3.6)" begin
        # the counted inventory of the leader layer at the published 500×300, slab 21
        n = 400
        painted, counted = zeros(Int, n), zeros(Int, n)
        quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
        for s in 1:n
            point, report = quiet(() -> layout(akeeb_layout(; seed = s), (500, 300); report = true))
            σ, kinds = point[1].second, point[2].second
            t = only(r for r in report if r.type === :InsertUntil)
            counted[s], painted[s] = t.counted, t.painted
            @test count(==(:leader), kinds) == painted[s]
            @test sort(σ[σ .> 1169]) == 1170:(1169 + painted[s])             # one site per leader
        end
        # the spec owner's 20k-rep seeding simulation: 382.1 ± 2.7 painted, 7.9 ± 2.8 empty,
        # inventory 390 in 96.1 % (our 20k: 382.14 ± 2.73, 7.90 ± 2.74, 96.1 %); 3·SE ≈ 0.4
        @test abs(mean(painted) - 382.1) < 0.5
        @test abs(mean(counted .- painted) - 7.9) < 0.5
        @test all(>=(390), counted) && 0.93 < mean(counted .== 390) <= 0.995
        # `akeeb_state` paints this layout; negative control: `:retry` paints exactly the quota
        o = akeeb_state(; seed = 3)
        @test count(==(:follower), o[2].second) == 1169 && count(==(:leader), o[2].second) == painted[3]
        @test all(s -> count(==(:leader), akeeb_state(; seed = s, seeding = :retry)[2].second) == 390, 1:5)
        @test_throws ArgumentError akeeb_state(; seeding = :other)
    end
    @test GranerGlazier(; name = :big, lattice = (144, 144), T = 5.0).lattice.dims == (144, 144)
    @test occursin("Graner & Glazier", string(@doc GranerGlazier))
end

include("mechanisms.jl")
include("papers.jl")
include("siblings.jl")
include("analysis.jl")
include("guardrails.jl")
include("frozen.jl")
foreach(f -> include(joinpath(@__DIR__, "acceptance", f)), sort(filter(endswith(".jl"), readdir(joinpath(@__DIR__, "acceptance")))))

@testset "Aqua" begin
    Aqua.test_all(PottsModels; deps_compat = (; check_extras = false))
end
